#!/bin/bash

###
### night.inc.sh -- shared helper library for the nightly maintenance family.
###
### Sourced by owl.sh (the parent orchestrator) and by the per-account/per-site
### worker scripts split out
### under /var/xdrago/night/. Defines pure helpers, load helpers, the chattr
### lock helpers and the drush8 wrappers so a single copy is shared instead of
### duplicated in every split script. Functions only -- no top-level side
### effects; callers own their own prologue (PATH/HOME) and _check_root.
###
### Bodies are moved verbatim from owl.sh to keep behaviour identical; the
### drush wrappers and chattr helpers read _HM_U/_Dom from the caller's scope
### at call time, exactly as before -- the caller must set them before calling.
###

###-------------CONSTANTS-----------------###

# BOA Tier-0 constants shared by the orchestrator and the night workers. The
# worker subprocesses get these by sourcing this library; the drush config/
# variable verbs (_vSet etc.) are used throughout the per-account/per-site work.
# Default only: every worker sources /root/.barracuda.cnf after this
# file (night_load_run_env), so the cnf value wins; the literal keeps
# the read well-defined and fail-closed if a worker is ever driven
# outside that chain.
_DEBUG_DAILY=NO

_WEBG=www-data
_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_cGet="config-get user.settings"
_cSet="config-set user.settings"
_vGet="variable-get"
_vSet="variable-set --always-set"

###-------------HELPERS-----------------###

_acct_group() {
  # Group that owns an account's tree. Derived, never a literal: an account
  # converted to a private primary group named after itself gets that group,
  # everything else (an unconverted box, root, www-data, an adopted odd
  # group) falls back to 'users' -- so a tool landing on an unconverted or
  # half-converted box leaves it exactly as it is today. Box-wide paths
  # (/data/conf, /data/u, the shared cores) keep 'users' and never use this.
  # $1 = account name (oN, oN.ftp, oN.<sub>) or a path under /data/disk/<oN>
  # or /var/aegir (the master keeps 'users' in this phase).
  local _a="${1}" _g
  case "${_a}" in
    /var/aegir|/var/aegir/*|aegir|root|www-data) echo "users"; return 0 ;;
    /data/disk/*) _a="${_a#/data/disk/}"; _a="${_a%%/*}" ;;
    */*) echo "users"; return 0 ;;
  esac
  _a="${_a%%.*}"
  [ -n "${_a}" ] || { echo "users"; return 0; }
  _g=$(id -gn "${_a}" 2> /dev/null)
  [ "${_g}" = "${_a}" ] || _g="users"
  echo "${_g}"
}

_web_group_state() {
  # The account's own web group, wg-<account>, derived on the box and never
  # taken from argv or a cnf: the group its pools, backend user and shell
  # users share for its web paths once the account is converted to it.
  # Prints "<state> <gid> <group>", "none - -" when there is no such group
  # (the record is root's: run as another user, converted reads as held):
  #   none       no group of that name
  #   foreign    the group exists, but an identity outside the account holds
  #              it too: never joined nor written to; claim passes still leave
  #              its paths alone (taking them would cut the pools off)
  #   held       the group exists and only this account's identities hold it:
  #              claim passes leave its paths alone, new identities join it
  #   converted  and root's record names that gid: writers use the group
  #   phaseb     and the record says the identities have left www-data
  # The record is /root/.<account>.web-group.txt, "wg-<account> gid=<n>
  # phase=<A|B> ...", root's own file outside the account tree, so neither
  # the account nor a copy or restore of its tree can make or move it.
  # $1 = account name, one of its identities (oN.ftp, oN.<sub>, oN.web,
  # oN.NN.web), or a path under /data/disk/<oN>, /home/<oN>.*, the account's
  # gems or npm tree, or its store on attached storage
  # (/mnt/<m>/files/<oN>/static/files).
  local _a="${1}" _e _gid _u _r _rg="" _rgid="" _rph="" IFS=$' \t\n'
  # a path is read as written (an alias the account wrote can carry "..",
  # "." or "//"): normalised by text alone, never through a link, first
  case "${_a}" in
    */*) _a=$(realpath -m -s -- "${_a}" 2> /dev/null) || { echo "none - -"; return 0; } ;;
  esac
  case "${_a}" in
    /data/disk/*) _a="${_a#/data/disk/}"; _a="${_a%%/*}" ;;
    /home/*) _a="${_a#/home/}"; _a="${_a%%/*}" ;;
    /opt/user/gems/*|/opt/user/npm/*) _a="${_a#/opt/user/*/}"; _a="${_a%%/*}" ;;
    /mnt/*/files/*/static/files|/mnt/*/files/*/static/files/*)
      _a="${_a#/mnt/}"; _a="${_a#*/files/}"; _a="${_a%%/*}" ;;
    */*) echo "none - -"; return 0 ;;
  esac
  _a="${_a%%.*}"
  case "${_a}" in
    ""|all|aegir|root|www-data|wg-*|*[!a-z0-9-]*) echo "none - -"; return 0 ;;
  esac
  _e=$(getent group "wg-${_a}" 2> /dev/null) || { echo "none - -"; return 0; }
  _gid=$(printf '%s' "${_e}" | cut -d: -f3)
  case "${_gid}" in
    ""|*[!0-9]*) echo "none - -"; return 0 ;;
  esac
  # every holder of the gid: members of each group entry carrying it (a
  # second entry can share the number) and every user with it as primary
  for _u in $(getent group | awk -F: -v g="${_gid}" '$3 == g { print $4 }' | tr ',' ' ') \
    $(getent passwd | awk -F: -v g="${_gid}" '$4 == g { print $1 }'); do
    [[ "${_u}" =~ ^${_a}(\.[a-z0-9]+(-dev)?|\.[0-9]+\.web)?$ ]] \
      || { echo "foreign ${_gid} wg-${_a}"; return 0; }
  done
  _r="/root/.${_a}.web-group.txt"
  if [ -f "${_r}" ] && [ ! -L "${_r}" ] \
    && [ "$(stat -c %u -- "${_r}" 2> /dev/null)" = "0" ]; then
    read -r _rg _rgid _rph _ < "${_r}" || :
  fi
  if [ "${_rg}" != "wg-${_a}" ] || [ "${_rgid}" != "gid=${_gid}" ]; then
    echo "held ${_gid} wg-${_a}"
  elif [ "${_rph}" = "phase=B" ]; then
    echo "phaseb ${_gid} wg-${_a}"
  elif [ "${_rph}" = "phase=A" ]; then
    echo "converted ${_gid} wg-${_a}"
  else
    echo "held ${_gid} wg-${_a}"
  fi
}

_web_group() {
  # The group a root writer gives an account's web paths (files/, private/,
  # settings.php and the like): wg-<account> once the account is converted,
  # www-data otherwise, as always. Until the record says converted every
  # identity of the account still holds www-data (a conversion grants the web
  # group first and a revert gives www-data back before it moves any path),
  # so www-data is the old state, never an outage. Callers write
  # "${_owner}${_wg:+:${_wg}}": a missing helper, an empty answer, changes no
  # group and never hands a path to a login group. Run as any user but root,
  # which cannot read root's record, a held group answers empty: the group
  # each path has is kept. $1 as _web_group_state.
  local _s
  _s=$(_web_group_state "${1}")
  case "${_s%% *}" in
    converted|phaseb) echo "${_s##* }" ;;
    held) [ "$(id -u)" = "0" ] && echo "www-data" || echo "" ;;
    *) echo "www-data" ;;
  esac
}

# An account owns its static/control, and oN owns the rest of its
# /data/disk/oN (log/, .drush/, config/, tools/, .tmp/, undo/), and a login
# owns its /home/<login>, so any name there can be a link or a FIFO, and any
# directory on the way can itself be a link. Root reads and writes those
# names only through the helpers below (the helper.sh.inc bodies; the night
# family never sources that file).
#
# Run "$@" inside the real directory $1, never one reached through a link an
# account planted on the way. Below /home and /data/disk (root's) every name
# on the path must be a real directory; elsewhere the last name is checked
# against its resolved parent. Once entered, ./name stays in that directory
# whatever is swapped.
_acct_in_real_dir() {
  local _d="${1}" _a="" _want
  shift
  case "${_d}" in
    /home/?*) _a=/home ;;
    /data/disk/?*) _a=/data/disk ;;
  esac
  if [ -n "${_a}" ]; then
    _want="$(cd -P -- "${_a}" 2> /dev/null && pwd -P)${_d#"${_a}"}"
  else
    _want="$(cd -P -- "${_d%/*}" 2> /dev/null && pwd -P)/${_d##*/}"
  fi
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_want}" ] && "$@" )
}
# ./$1 in the current (pinned) directory: never through a link, never blocked
# on a FIFO, at most 1 MiB. Empty for anything else.
_acct_read_here() {
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
    bs=1048576 count=1 status=none 2> /dev/null
}
# $2 in the real directory $1, read as _acct_read_here reads it.
_acct_read_in() {
  _acct_in_real_dir "${1}" _acct_read_here "${2}"
}
# ./$1 of the current (pinned) directory as text: status 1, and nothing,
# unless it is a regular file; read as _acct_read_here reads it.
_acct_read_plain_here() {
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
  _acct_read_here "${1}"
}
# ./$1 in the current (pinned) directory with the content $2 (0644): a fresh
# file created exclusively, then renamed over the name, so a link or a FIFO
# put at the name is replaced, never followed or opened, and a reader never
# finds the name missing.
_acct_put_here() {
  local _t="./.${1}.put.$$.${RANDOM}"
  rm -f -- "${_t}"
  ( umask 022
    printf '%s\n' "${2}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
    && mv -f -T -- "${_t}" "./${1}" && return 0
  rm -f -- "${_t}"
  return 1
}

# Validate that a caller-controlled path (parsed from a Drush alias file)
# resolves under one of BOA's writable roots. Used by the per-site loop to
# gate chown/chmod operations on _Dir (site_path) and _Plr (platform root):
# the alias file is written by aegir-context Hostmaster tasks and a compromised
# HM_U user could otherwise rewrite the alias to point at /etc and have the
# daily runner chown system paths. Returns 0 on safe path, 1 otherwise.
_validate_safe_dir() {
  local _resolved
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || return 1
  case "${_resolved}/" in
    /data/disk/*|/var/aegir/*|/home/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_validate_ctrl_dir() {
  # Gate the DIRECTORY that will hold a root-maintained control INI. The
  # alias-derived _Dir/_Plr are validated by _validate_safe_dir, but the
  # trailing modules component is not, and it lives in the tenant-writable
  # setgid tree: rename(2) and every ">>" append below resolve each parent
  # component normally, so a modules symlink planted by a tenant redirects
  # the whole per-site leg onto a root-parsed path. An ABSENT dir passes --
  # a later leg creates it with mkdir -p, and refusing here would stop that
  # on a fresh platform, which breaks more than it guards. Reads _usEr.
  # $1 = directory.
  local _resolved _anchor
  [ -L "$1" ] && return 1
  [ -e "$1" ] || return 0
  [ -d "$1" ] || return 1
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || return 1
  _anchor=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 1
  case "${_resolved}/" in
    "${_anchor}"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_ctrl_in_stage_dir() {
  # Root-only staging dir for the files root puts into an account's
  # tenant-writable trees, on the same filesystem as those trees (they all
  # live under the account root): ${_usEr}/.boa-ctrl, forced root:root 0700
  # on every call, a link planted at the name removed rather than followed.
  # oN owns the account root and can rename or replace any name in it, so
  # the dir is made, fixed and checked only once entered for real, and "$@"
  # runs inside it: ./name there is root's alone, whatever the account puts
  # at .boa-ctrl meanwhile. Reads _usEr from the caller.
  [ -n "${_usEr}" ] || return 1
  _acct_in_real_dir "${_usEr}" _ctrl_stage_here "$@"
}
_ctrl_stage_here() {
  local _h _st
  _h="$(pwd -P)/.boa-ctrl"
  [ -L ./.boa-ctrl ] && rm -f -- ./.boa-ctrl
  [ -d ./.boa-ctrl ] || mkdir ./.boa-ctrl 2> /dev/null
  cd -P -- ./.boa-ctrl 2> /dev/null && [ "$(pwd -P)" = "${_h}" ] || return 1
  chown root:root . 2> /dev/null && chmod 0700 . 2> /dev/null || return 1
  # root's, and nobody else's to enter or write
  _st=$(stat -c '%u %a' . 2> /dev/null)
  [ "${_st%% *}" = "0" ] && [[ "${_st##* }" =~ ^[0-7]+$ ]] \
    && (( (8#${_st##* } & 8#077) == 0 )) || return 1
  "$@"
}
_ctrl_stage_dir() {
  # The staging dir fixed as above, its path printed for a caller that still
  # takes one.
  _ctrl_in_stage_dir true || return 1
  echo "${_usEr}/.boa-ctrl"
}

_reseed_ctrl_ini() {
  # Seed/refresh a control INI from a regular template, symlink-proof and atomic.
  # The per-site/per-platform control INIs live in a tenant-writable setgid
  # modules dir (02775, no sticky, group-writable by the account's shell
  # identities -- and by every tenant while the instance still carries the
  # box-wide 'users' group), so a limited-shell/SFTP tenant can delete the
  # seeded INI and plant
  # a symlink at its path; a plain cp -af then writes THROUGH a live link and the
  # following chown/chmod retarget it.
  #
  # The new file is made in the root-only staging dir (_ctrl_in_stage_dir),
  # where only root can touch a name, and renamed from there onto the
  # destination with mv -f -T. Everything the account owns lives under the
  # account root, so the rename is same-filesystem and atomic; rename()
  # replaces a planted symlink (incl. a symlink-to-dir) instead of following
  # it, and a real-dir decoy makes mv fail into the clean skip.
  #
  # rename() refuses to follow only the FINAL component: every directory
  # above it is resolved normally, so a tenant who swaps the modules dir
  # itself for a symlink redirects the whole write. Refuse a symlinked
  # parent, require the resolved parent to sit under the account root, enter
  # it for real and hold it open, and rename into that open directory
  # (/proc/self/fd): a link swapped in after the check is never on the path.
  # The template is read inside its own resolved directory, only as a
  # regular file, bounded and never through a link or blocked on a FIFO, so
  # a template swapped in the tenant's modules dir can neither disclose a
  # root file nor stall the pass. Reads _usEr and _HM_U from the caller.
  # $1 = source template, $2 = dest INI path.
  local _src="$1"
  local _dst="$2"
  local _pnt _rpn _rus _rsd
  [ -L "${_src}" ] && return 1
  [ -f "${_src}" ] || return 1
  [ -n "${_HM_U}" ] || return 1
  case "${_dst}" in
    /*/*) : ;;
    *) return 1 ;;
  esac
  case "${_src}" in
    /*/*) : ;;
    *) return 1 ;;
  esac
  _pnt="${_dst%/*}"
  [ -L "${_pnt}" ] && return 1
  [ -d "${_pnt}" ] || return 1
  # Only the directories above the parent are resolved; the parent is taken
  # as a name in there, so a link swapped in at it after the test above
  # fails the check once entered instead of being followed.
  case "${_pnt}" in
    /?*/?*) : ;;
    *) return 1 ;;
  esac
  _rpn=$(realpath -e -- "${_pnt%/*}" 2>/dev/null) || return 1
  _rpn="${_rpn%/}/${_pnt##*/}"
  _rus=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 1
  case "${_rpn}/" in
    "${_rus}"/*) : ;;
    *) return 1 ;;
  esac
  _rsd=$(realpath -e -- "${_src%/*}" 2>/dev/null) || return 1
  (
    cd -P -- "${_rpn}" 2>/dev/null && [ "$(pwd -P)" = "${_rpn}" ] || exit 1
    exec 9< . || exit 1
    _ctrl_in_stage_dir _reseed_ctrl_ini_here "${_rsd}" "${_src##*/}" "${_dst##*/}"
  )
}
# In the staging dir (the current one): the template ./$2 of the resolved
# directory $1 put as a fresh file of the account's (0664), then renamed as
# $3 into the destination directory held open on fd 9.
_reseed_ctrl_ini_here() {
  local _new
  _new=$(mktemp ./ctrl.XXXXXX 2>/dev/null) || return 1
  if ! ( cd -P -- "${1}" 2>/dev/null && [ "$(pwd -P)" = "${1}" ] \
    && _acct_read_plain_here "${2}" ) > "${_new}"; then
    rm -f -- "${_new}"
    return 1
  fi
  chown "${_HM_U}:$(_acct_group "${_HM_U}")" "${_new}" &> /dev/null
  chmod 0664 "${_new}" &> /dev/null
  mv -f -T -- "${_new}" "/proc/self/fd/9/${3}" &> /dev/null && return 0
  rm -f -- "${_new}"
  return 1
}

_desymlink_planted() {
  # Strip a tenant-planted symlink at a root-maintained control-INI path before
  # this iteration seeds/edits/appends it. rm -f on a symlink removes only the
  # link (its target survives), and it is a no-op on a regular file, so a legit
  # account-owned file and the tenant's own edits are left untouched. The next
  # seed leg re-creates a missing INI as a regular file. Args = paths.
  local _p
  for _p in "$@"; do
    [ -L "${_p}" ] && rm -f "${_p}" &> /dev/null
  done
}

_is_foreign_cms_root() {
  # A Grav 2 or Textpattern platform root: the shape provision's
  # provision_platform_is_grav/_txp test, plus the platform scripts' Drupal
  # negatives, so no Drupal or Backdrop tree (core/, modules/system,
  # includes/bootstrap.inc) can ever read as foreign. Keyed on the root
  # because a site's alias root is its platform. False for a link and for an
  # absent path. $1 = platform root.
  local _r="${1%/}"
  [ -n "${_r}" ] && [ -d "${_r}" ] && [ ! -L "${_r}" ] || return 1
  [ -f "${_r}/index.php" ] || return 1
  [ -e "${_r}/core" ] && return 1
  [ -e "${_r}/modules/system/system.module" ] && return 1
  [ -e "${_r}/includes/bootstrap.inc" ] && return 1
  if [ -f "${_r}/bin/grav" ] && [ -f "${_r}/system/defines.php" ]; then
    return 0
  fi
  if [ -f "${_r}/css.php" ] \
    && [ -f "${_r}/textpattern/index.php" ] \
    && [ -f "${_r}/textpattern/lib/constants.php" ] \
    && [ ! -e "${_r}/autoload.php" ]; then
    return 0
  fi
  return 1
}

_heal_foreign_cms_ctrl_ini() {
  # Grav and Textpattern never read a BOA control INI, so BOA no longer seeds
  # one there; this clears what an earlier
  # release left. $1 = the dir, $2 = boa_site_control.ini or
  # boa_platform_control.ini, or empty to drop only an empty dir. Both the
  # default.* template and the live file go whatever they hold: nothing reads
  # either on these CMSes, and BOA's own nightly uncommented lines in them,
  # so their content says nothing about intent. The dir goes only when that
  # leaves it empty, so nothing else in it is ever lost. Never follows a
  # link: one at the dir is left alone, one at a file name goes as a link,
  # and the unlinks and the rmdir both run in directories pinned with cd -P,
  # so a parent swapped after a check cannot redirect them. Reads _usEr.
  local _md="$1" _n="$2" _rmd _rus
  [ -n "${_md}" ] || return 0
  [ -L "${_md}" ] && return 0
  [ -d "${_md}" ] || return 0
  _rmd=$(realpath -e -- "${_md}" 2>/dev/null) || return 0
  _rus=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 0
  case "${_rmd}/" in
    "${_rus}"/*) : ;;
    *) return 0 ;;
  esac
  (
    cd -P -- "${_rmd}" 2>/dev/null || exit 0
    [ "$(pwd -P)" = "${_rmd}" ] || exit 0
    if [ -n "${_n}" ]; then
      for _f in "default.${_n}" "${_n}"; do
        if [ -L "./${_f}" ] || [ -f "./${_f}" ]; then
          rm -f -- "./${_f}" \
            && echo "Foreign-CMS control INI removed: ${_rmd}/${_f}"
        fi
      done
    fi
    cd -P .. 2>/dev/null || exit 0
    [ "$(pwd -P)" = "${_rmd%/*}" ] || exit 0
    rmdir -- "${_rmd##*/}" 2>/dev/null \
      && echo "Foreign-CMS empty dir removed: ${_rmd}"
  )
  return 0
}

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_check_file_with_wildcard_path() {
  # 2>/dev/null, NOT 2>&1: a glob that matches nothing is passed through
  # literally and ls then prints "cannot access ..." on stderr. Capturing that
  # made _WILDCARD_TEST non-empty for a path that does not exist, so this
  # answered YES for EVERY input and could never answer NO -- the auto-detect
  # callers then seeded auto_detect_*_integration = TRUE into every platform
  # control INI, module present or not. $1 stays unquoted: the glob is the point.
  _WILDCARD_TEST=$(ls $1 2>/dev/null)
  if [ -z "${_WILDCARD_TEST}" ]; then
    _FILE_EXISTS=NO
  else
    _FILE_EXISTS=YES
  fi
}

# Echo a platform's real Drupal docroot on stdout, or nothing if none found.
# The docroot is the platform root for Drupal 7-era codebases, but a subdir for
# Composer D8+ codebases whose web root differs from the app root: docroot/,
# html/, web/, in that order. Keyed on index.php, the front controller present
# in every Drupal docroot (D6..D11) regardless of build recipe. -f follows the
# symlink and is false for a dangling link, so a decoy like web -> /etc cannot
# register as a docroot. Returns 0 with the path, 1 if no docroot is found.
# Embedded here (not sourced from the install-time helper.sh.inc) so the
# deployed owl/night family carries its own structure-detection logic.
_detect_real_docroot() {
  local _plat="${1%/}"
  local _sub
  [ -n "${_plat}" ] && [ -d "${_plat}" ] || return 1
  if [ -f "${_plat}/index.php" ]; then
    printf '%s\n' "${_plat}"
    return 0
  fi
  for _sub in docroot html web; do
    if [ -f "${_plat}/${_sub}/index.php" ]; then
      printf '%s\n' "${_plat}/${_sub}"
      return 0
    fi
  done
  return 1
}

# Return 0 only when control flag <name> is set to YES (case-insensitive) in the
# control file <file>, else 1. Greps rather than sources, so it is independent
# of load order and never clobbers caller scope; a missing file or unset/non-YES
# value reads as disabled. Gates the ghost/empty cleanup moves so they stay OFF
# until opted in per-system (/root/.barracuda.cnf) or per-account
# (/root/.<user>.octopus.cnf).
_cnf_flag_yes() {
  local _file="$1"
  local _name="$2"
  local _val
  [ -r "${_file}" ] || return 1
  _val=$(grep -E "^[[:space:]]*${_name}=" "${_file}" 2>/dev/null \
    | tail -n1 | cut -d= -f2- | tr -d "\"' " | tr '[:lower:]' '[:upper:]')
  [ "${_val}" = "YES" ]
}

# Master cleanup interlock. While any Ægir/Provision task is running
# (provision-verify/install/clone/migrate/backup/restore), the site and platform
# trees are in flux -- files/private momentarily absent or symlinks mid-repoint,
# aliases mid-rewrite, vhosts staged under a leading dot -- and that transient
# state would be mis-read as a ghost and reaped. Return 0 when a provision
# process is detected, so every cleanup mover can skip while one is in flight.
# Same signal BOA already uses in monitor/check/mysql.sh.
_provision_running() {
  # Genuine task EXECUTIONS only. BOA spawns them as
  #   su -s /bin/bash - <user> -c "<php> /usr/bin/drush @<site> provision-<task>"
  # (_run_drush8_cmd above), so a real task always carries the drush command
  # token somewhere in the tree, and the php/su process running it always has
  # provision on its command line. The bare substring match this replaces
  # reported "running" for any command line that merely MENTIONED a provision
  # path -- a checksum, an editor, an operator's ssh probe, a monitoring loop --
  # and then silently skipped that night's cleanups; observed live when a
  # watcher holding .drush/sys/provision/... in its argv read as a live task.
  # Same lesson, and the same fix, as the _fetch_versioned running-tool guard.
  # The second pattern is the old one plus an execution-shape constraint, so the
  # only processes this stops matching are the non-executions; the first keeps
  # the inner `bash -c "... provision-<task>"` link of the su chain covered.
  pgrep -f '(^| )provision-[a-z0-9-]+( |$)' > /dev/null 2>&1 && return 0
  # The front-end dispatch phase of a task carries no provision-* token: the
  # backend child is spawned only after bootstrap, and the post-hooks run after
  # it exits, so those windows were invisible. ( |$) is LOAD-BEARING -- without
  # it this also matches hosting-tasks and hosting-dispatch, the per-minute
  # pollers, which would pin the gate ON and disable every nightly cleanup.
  pgrep -f "hosting-task( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^([^ ]*/)?(php[0-9.]*|su|env|drush[0-9]*)( |$).*provision" > /dev/null 2>&1 && return 0
  return 1
}

# Install/upgrade interlock for the night workers, distinct from the entry gate
# in owl.sh: that one is evaluated ONCE, before the per-account fan-out, so a
# pass that starts afterwards is invisible to it -- and the octopus pass drops
# boa_run.pid at the end of EVERY account (satellite _satellite_post_cleanup),
# so on a multi-account box the lock pids stop being a reliable signal partway
# through. The AegirSetup arm covers the phase that actually builds a new
# distro revision: those children run as "su - oN -c bash .../AegirSetupC.sh.txt"
# and match none of the wrapper or .sh.txt forms the other gates look for.
# Anchored on the executor so a remotely driven install cannot defer this box,
# and the [ABC] class keeps the pattern from matching its own pgrep.
_night_boa_pass_active() {
  [ -e "/run/boa_run.pid" ] && return 0
  [ -e "/run/boa_wait.pid" ] && return 0
  [ -e "/run/octopus_install_run.pid" ] && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/(barracuda|octopus)( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?(bash|sh|su) .*/aegir/scripts/AegirSetup[ABC]\.sh\.txt" > /dev/null 2>&1 && return 0
  return 1
}

# Consecutive-ghost tracking so nothing is reaped on a single night's snapshot.
# A per-item counter in the account's log/ctrl, named $1 (a name, never a
# path), records how many consecutive runs the item has looked like a ghost.
# Returns 0 only once that reaches $2 (default 2), giving a transient state --
# a verify/clone in flight, a momentarily-unmounted store, a symlink
# mid-repoint -- at least one grace run to recover. The caller MUST call
# _ghost_seen_reset_acct on any run where the item is found valid, so a
# recovered item never carries a stale count into a later reap. log/ is oN's:
# the counter is read, put and removed only inside the real log/ctrl, so a
# link or a FIFO at the name, or at log/ or log/ctrl, is never followed or
# opened, and a counter that cannot be kept there never counts. Reads _usEr.
# 20-sites.sh carries the same two bodies.
_ghost_seen_enough_acct() {
  local _n
  _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null
  _n=$(_acct_in_real_dir "${_usEr}/log/ctrl" _acct_read_plain_here "${1}" \
    | head -c 32)
  _n="${_n//[^0-9]/}"
  _n="${_n:0:9}"
  _n=$(( 10#${_n:-0} + 1 ))
  _acct_in_real_dir "${_usEr}/log/ctrl" _acct_put_here "${1}" "${_n}" \
    || return 1
  [ "${_n}" -ge "${2:-2}" ]
}
_ghost_seen_reset_acct() {
  _acct_in_real_dir "${_usEr}/log/ctrl" rm -f -- "./${1}" 2> /dev/null
  return 0
}
# The same for a caller that passes the counter's path: honoured only for a
# name directly in the account's log/ctrl; any other path never counts.
_ghost_seen_enough() {
  [ "${1%/*}" = "${_usEr}/log/ctrl" ] || return 1
  _ghost_seen_enough_acct "${1##*/}" "${2:-2}"
}
_ghost_seen_reset() {
  [ "${1%/*}" = "${_usEr}/log/ctrl" ] || return 0
  _ghost_seen_reset_acct "${1##*/}"
}

###-------------LOAD-----------------###

_count_cpu() {
  _CPU_INFO="$(grep -c processor /proc/cpuinfo)"
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST="$(which nproc)"
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt 0 ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt 1 ]; then
    _CPU_NR=1
  fi
  echo ${_CPU_NR} > /data/all/cpuinfo
  chmod 644 /data/all/cpuinfo &> /dev/null
}

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

_load_control() {
  : "${_CPU_TASK_RATIO:=3.1}"
  [ -e "/root/.force.sites.verify.cnf" ] && _CPU_TASK_RATIO=4.1
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

###-------------CHATTR-----------------###

# A login owns its home, and a *.ftp home is never itself made immutable, so
# every name below it can be swapped for a link, and chattr follows a link
# named with a trailing slash. Each directory is locked and unlocked only
# inside the real directory (_acct_in_real_dir): locking takes the
# directory first, after which no name in it can change; unlocking clears
# the names while it still holds. No entry is locked or unlocked by its
# name: a directory from inside itself, a regular file through a handle
# (_night_chattr_entries_here), so a link is never followed and a hard link
# put there beforehand never passes the flag to the file it names.
_night_lock_here() {
  chattr +i . &> /dev/null
  return 0
}
_night_unlock_here() {
  chattr -i . &> /dev/null
  return 0
}
# The immutable flag set (+) or cleared (-) on a directory, or on a regular
# file with a single link, through a handle opened without following a link
# or blocking on a FIFO: a hard link, a link, a FIFO or anything else is
# refused (status 1). Args: + or -, then the names.
_ACCT_CHATTR_PL='use Fcntl; my ($op, @f) = @ARGV; my $rc = 0; for my $f (@f) { sysopen(my $h, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or do { $rc = 1; next }; my @s = stat($h); if (@s && (-d _ || (-f _ && $s[3] == 1))) { my $b = pack("L", 0); if (ioctl($h, 0x80086601, $b)) { my $fl = unpack("L", $b); $fl = $op eq "+" ? ($fl | 0x10) : ($fl & ~0x10); ioctl($h, 0x40086602, pack("L", $fl)) or $rc = 1; } else { $rc = 1 } } else { $rc = 1 } close($h); } exit $rc'
# The real directory ./$2 of the current (pinned) one given (+) or cleared
# of (-) the immutable flag from inside itself ($1): a directory is never a
# hard link, and a name swapped for anything else is never entered.
_night_chattr_sub_here() {
  local _h
  _h="$(pwd -P)"
  ( cd -P -- "./${2}" 2> /dev/null && [ "$(pwd -P)" = "${_h}/${2}" ] \
    && chattr "${1}i" . ) &> /dev/null
  return 0
}
# Every entry of the current (pinned) directory given (+) or cleared of (-)
# the immutable flag ($1), as chattr ${1}i ./* gave it: each real directory
# from inside itself, the regular files through _ACCT_CHATTR_PL; a link or
# anything else is left alone.
_night_chattr_entries_here() {
  local _e _chf=()
  for _e in ./*; do
    if [ -d "${_e}" ] && [ ! -L "${_e}" ]; then
      _night_chattr_sub_here "${1}" "${_e#./}"
    elif [ -f "${_e}" ] && [ ! -L "${_e}" ]; then
      _chf+=( "${_e}" )
    fi
  done
  [ "${#_chf[@]}" -eq 0 ] \
    || perl -e "${_ACCT_CHATTR_PL}" "${1}" "${_chf[@]}" &> /dev/null
  return 0
}
_night_lock_all_here() {
  chattr +i . &> /dev/null
  _night_chattr_entries_here +
  return 0
}
_night_unlock_all_here() {
  _night_chattr_entries_here -
  chattr -i . &> /dev/null
  return 0
}
_night_drush_lock_here() {
  chattr +i . &> /dev/null
  _night_chattr_sub_here + usr
  return 0
}
_night_drush_unlock_here() {
  _night_chattr_sub_here - usr
  # a CLI php.ini an earlier release left, for the ltd worker to remove
  [ -f ./php.ini ] && [ ! -L ./php.ini ] \
    && perl -e "${_ACCT_CHATTR_PL}" - ./php.ini &> /dev/null
  chattr -i . &> /dev/null
  return 0
}

_enable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      _acct_in_real_dir "/home/$1" _night_lock_here
    else
      _acct_in_real_dir "/home/$1/platforms" _night_lock_all_here
    fi
    _acct_in_real_dir "/home/$1/.drush" _night_drush_lock_here
    _acct_in_real_dir "/home/$1/.bazaar" _night_lock_here
  fi
}

_disable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  # Same names as _enable_chattr, inverted harm: clearing +i through a
  # planted link strips the immutable protection from a tree of the
  # tenant's choosing (e.g. /var/aegir/.drush and its *.ini, which BOA locks
  # on purpose), so the same real-directory rule applies.
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      _acct_in_real_dir "/home/$1" _night_unlock_here
    else
      _acct_in_real_dir "/home/$1/platforms" _night_unlock_all_here
    fi
    _acct_in_real_dir "/home/$1/.drush" _night_drush_unlock_here
    _acct_in_real_dir "/home/$1/.bazaar" _night_unlock_here
  fi
}

###-------------DRUSH8-----------------###

# Verbose gate (_DEBUG_DAILY=YES in the cnf, or the legacy marker file): one
# timestamped line per drush8 run, written to STDERR on purpose. Callers
# capture the nosilent wrapper's stdout to parse a drush value (variable-get
# through cut/awk in 20-sites.sh), so a line the wrapper itself printed on
# stdout became part of that value: the timestamp survived the digits-only
# filter in _fix_user_register_protection_with_vSet and user_register read as
# a number like 20020120 instead of 0/1/2, which no branch of the check ever
# acts on (an unset variable read as non-empty the same way). Every process
# that runs a wrapper joins stderr into its log (owl.sh redirects
# _daily_action and each 10-account.sh subprocess with 2>&1), so the line
# reaches the same log, now also from the calls whose stdout a caller
# captures, where it used to vanish into the value. Callers that fold stderr
# into their capture on purpose (2>&1, for drush's own messages) still see
# the line: they pattern-match rather than parse, and the pml probes match
# "($m)" while the echoed command line carries the caller's literal "\($m\)",
# so the line cannot satisfy that test -- keep those backslashes if the
# probes are ever reworked.

_run_drush8_cmd() {
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} ${_HM_U} running drush8 @${_Dom} $1" >&2
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${_Dom} $1" &> /dev/null
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${_Dom} $1" &> /dev/null
  fi
  wait
}

_run_drush8_hmr_cmd() {
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} ${_HM_U} running drush8 @hostmaster $1" >&2
  fi
  su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

# Whether the account's own Aegir front-end still has a record for a site
# name. A site's hosting_context row is registered with the domain on node
# insert and removed by hosting_context_delete when the node is deleted, so
# it distinguishes "the customer can still see and remove this in the panel"
# (YES) from "only backend leftovers remain" (NO). Echoes YES / NO / UNKNOWN
# (front-end unreachable or unparseable output) -- callers pick the
# fail-direction. Same @hostmaster/account-user shape as _run_drush8_hmr_cmd,
# but CAPTURES output; tail -n1 keeps the count row under any profile noise.
_hmr_context_exists() {
  local _name="$1"
  local _out
  # a site name comes from a file name the account controls: a host name
  # only, never text that could change the query
  if [[ ! "${_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo UNKNOWN
    return 0
  fi
  _out=$(su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster sqlq \"SELECT COUNT(*) FROM hosting_context WHERE name='${_name}'\"" 2>/dev/null \
    | grep -o '[0-9][0-9]*' | tail -n 1)
  case "${_out}" in
    "") echo UNKNOWN ;;
    0)  echo NO ;;
    *)  echo YES ;;
  esac
}

_run_drush8_hmr_master_cmd() {
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} aegir running drush8 @hostmaster $1" >&2
  fi
  su -s /bin/bash - aegir -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

_run_drush8_nosilent_cmd() {
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} ${_HM_U} running drush8 @${_Dom} $1" >&2
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${_Dom} $1"
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${_Dom} $1"
  fi
  wait
}

### Shared helpers promoted from owl.sh / 20-sites.sh (used by both
### the orchestrator and the per-account / per-site workers).

_apt_clean_update() {
  ${_APT_UPDATE} -qq 2>/dev/null
  _CALLER_SCRIPT="$(basename "${BASH_SOURCE[-1]}")"
  _CALLER_SCRIPT="${_CALLER_SCRIPT//[^a-zA-Z0-9._-]/_}"
  date +%s > "/run/_latest_apt_clean_update.${_CALLER_SCRIPT}.pid"
}

# In the real static/: a link put at goaccess removed, the directory made
# when missing (root's).
_goaccess_dir_here() {
  [ -L ./goaccess ] && rm -f -- ./goaccess
  [ -e ./goaccess ] || mkdir ./goaccess 2> /dev/null
  return 0
}
# In the real static/goaccess, while root owns it: the report tree $1 copied
# in as ./<its name>.
_goaccess_copy_here() {
  [ -O . ] && cp -af -- "${1}" ./
}

_if_gen_goaccess() {
  local _gaD
  _PrTestPower=$(grep "POWER" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestUltra=$(grep "ULTRA" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestMonster=$(grep "MONSTER" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.${_HM_U}.octopus.cnf 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestUltra}" =~ "ULTRA" ]] \
    || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]]; then
    _isWblgx="$(which weblogx)"
    # The name comes from a vhost file name the account controls: a host
    # name (or ALL) only, never a path, a glob or an option.
    [[ "${1}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 0
    if [ -x "${_isWblgx}" ]; then
      ${_isWblgx} --site="${1}" --env="${_HM_U}"
      wait
      # static/ is tenant-writable (02775, no sticky), so goaccess can be a
      # planted symlink, and any name on the way can be swapped at any
      # moment: a report tree copied through one would drop root-owned files
      # wherever the tenant chose. goaccess is made, and a report published
      # into it or withdrawn from it, only inside the real directory, and
      # only while root owns it.
      _acct_in_real_dir "/data/disk/${_HM_U}/static" _goaccess_dir_here
      _gaD="/data/disk/${_HM_U}/static/goaccess"
      if [ -e "/var/www/adminer/access/${_HM_U}/${1}/index.html" ] \
        && _acct_in_real_dir "${_gaD}" test -O .; then
        _acct_in_real_dir "${_gaD}" _goaccess_copy_here \
          "/var/www/adminer/access/${_HM_U}/${1}"
      else
        rm -rf -- "/var/www/adminer/access/${_HM_U}/${1}"
        _acct_in_real_dir "${_gaD}" rm -rf -- "./${1}"
      fi
    fi
  fi
}

###-------------NIGHT LOG + LE INCIDENT-----------------###

# Per-account night log path. The orchestrator (owl.sh) redirects each
# `10-account.sh <account>` run here -- serial AND parallel -- so every
# account's output lands in its own file; the worker reads the same path back
# to build its Let's Encrypt renewal incident report. Both sides derive it
# identically from _NOW (the frozen run keystone) + the account basename, so
# they always agree on the file name.
_acct_night_log() {
  echo "/var/log/boa/daily/acct-$(basename "$1")-${_NOW}.log"
}

# Extract failed Let's Encrypt renewals from a single account's night log.
# dehydrated prints a stable block on failure: a "Processing <domain> [with
# alternative names: ...]" header, then for the failing challenge an ACME
# result whose tab-separated lines include ["error","type"] and
# ["error","detail"]. We emit one record per failure with five fields joined by
# the US control byte (0x1f), NOT a tab: <site-context><US><cert-domain><US>
# <alt-names><US><short-type><US><detail>. The separator must be non-whitespace
# because the alt-names field is EMPTY for single-domain certs, and `read` with
# a whitespace IFS (tab) silently collapses an empty middle field, shifting every
# later field left. 0x1f cannot occur in a domain or ACME detail string.
# Keyed on the ["error","detail"] line (exactly one per failed cert), paired
# with the most recent type + Processing/Running context seen above it.
# Successful or "Skipping renew!" blocks carry no error detail line and are
# never emitted. Operates on ONE account's log, so every record provably
# belongs to that account -- this is what guarantees a client notice can never
# be cross-attributed to the wrong account.
_le_extract_failures() {
  [ -r "$1" ] || return 0
  awk '
    /^Running LE cert check directly for / {
      currun=$0; sub(/^Running LE cert check directly for /,"",currun)
    }
    /^Processing / {
      p=$0; sub(/^Processing /,"",p)
      i=index(p," with alternative names: ")
      if (i>0) { curdom=substr(p,1,i-1); curalt=substr(p,i+length(" with alternative names: ")) }
      else     { curdom=p; curalt="" }
    }
    /^\["error","type"\]/ {
      t=$0; sub(/^\["error","type"\][ \t]+/,"",t); gsub(/"/,"",t); curtype=t
    }
    /^\["error","detail"\]/ {
      d=$0; sub(/^\["error","detail"\][ \t]+/,"",d); sub(/^"/,"",d); sub(/"$/,"",d)
      gsub(/\\"/,"\"",d)
      st=curtype; sub(/^.*:/,"",st)
      printf "%s\037%s\037%s\037%s\037%s\n", currun, curdom, curalt, st, d
      curtype=""
    }
  ' "$1"
}

# Map an ACME error type + detail to a short, non-technical cause phrase, used
# in both the operator and the client mail. The detail string is the most
# reliable signal (the type is sometimes a generic "unauthorized" for several
# distinct causes), so match on it first, then fall back to the type.
_le_reason() {
  local _t="$1"
  local _d="$2"
  case "${_d}" in
    *"key authorization file"*)
      echo "another server is currently answering for this name (an old host, a parked page or a CDN), so verification fails" ;;
    *NXDOMAIN*|*"no valid A records"*|*"DNS problem"*)
      echo "the domain or one of its aliases has no working DNS record pointing to this server" ;;
    *"Timeout during connect"*|*"Connection refused"*|*"Fetching"*)
      echo "the name points to a server that cannot be reached from the Internet (DNS elsewhere or a firewall)" ;;
    *"Invalid response"*)
      echo "the name resolves to a different server (the verification request was answered elsewhere)" ;;
    *)
      case "${_t}" in
        dns)         echo "the domain or one of its aliases has no working DNS record pointing to this server" ;;
        rateLimited) echo "Let's Encrypt temporarily rate-limited new certificates; it will retry automatically" ;;
        *)           echo "the certificate could not be validated by Let's Encrypt" ;;
      esac ;;
  esac
}

###-------------RUN-FREEZE-----------------###

# Freeze the per-run state a per-account worker needs into /run/night/run.env so a
# `10-account.sh <account>` subprocess sees the SAME run context the orchestrator
# computed. Called once by the orchestrator (owl.sh) after global-pre,
# before the account loop. _NOW is the keystone -- it names every *-${_NOW}.info
# idempotency guard, so a worker must INHERIT it here and never re-derive it.
night_emit_run_env() {
  mkdir -p /run/night
  # Create it 0600 up front: the redirect below would otherwise leave the file
  # at the root umask (0644) for the whole write, with the chmod only landing
  # afterwards. /run is root-only, so this is hardening, not a live hole.
  install -m 0600 /dev/null /run/night/run.env &> /dev/null
  {
    echo "export _NOW=\"${_NOW}\""
    echo "export _DOW=\"${_DOW}\""
    echo "export _xSrl=\"${_xSrl}\""
    echo "export _FORCE_SITES_VERIFY=\"${_FORCE_SITES_VERIFY}\""
    echo "export _CTRL_TPL_FORCE_UPDATE=\"${_CTRL_TPL_FORCE_UPDATE}\""
    echo "export _O_CONTRIB=\"${_O_CONTRIB}\""
    echo "export _O_CONTRIB_SEVEN=\"${_O_CONTRIB_SEVEN}\""
    echo "export _O_CONTRIB_EIGHT=\"${_O_CONTRIB_EIGHT}\""
    echo "export _O_CONTRIB_NINE=\"${_O_CONTRIB_NINE}\""
    echo "export _O_CONTRIB_TEN=\"${_O_CONTRIB_TEN}\""
    echo "export _O_CONTRIB_ELEVEN=\"${_O_CONTRIB_ELEVEN}\""
    echo "export _O_CONTRIB_BACKDROP=\"${_O_CONTRIB_BACKDROP}\""
    echo "export _MODULES_FORCE=\"${_MODULES_FORCE}\""
    echo "export _MODULES_ON_SEVEN=\"${_MODULES_ON_SEVEN}\""
    echo "export _MODULES_ON_SIX=\"${_MODULES_ON_SIX}\""
    echo "export _MODULES_OFF_SEVEN=\"${_MODULES_OFF_SEVEN}\""
    echo "export _MODULES_OFF_SIX=\"${_MODULES_OFF_SIX}\""
    echo "export _MODULES_OFF_EIGHT_PLUS=\"${_MODULES_OFF_EIGHT_PLUS}\""
    echo "export _hostedSys=\"${_hostedSys}\""
    echo "export _APT_UPDATE=\"${_APT_UPDATE}\""
    echo "export _PERMISSIONS_FIX=\"${_PERMISSIONS_FIX}\""
    echo "export _MODULES_FIX=\"${_MODULES_FIX}\""
    echo "export _CLEAR_BOOST=\"${_CLEAR_BOOST}\""
    echo "export _ENABLE_GOACCESS=\"${_ENABLE_GOACCESS}\""
    echo "export _ADMIN_EMAIL=\"${_MY_EMAIL}\""
    echo "export _INCIDENT_REPORT=\"${_INCIDENT_REPORT}\""
    echo "export _LE_CLIENT_NOTIFY=\"${_LE_CLIENT_NOTIFY}\""
    echo "export _GHOST_CLIENT_NOTIFY=\"${_GHOST_CLIENT_NOTIFY}\""
  } > /run/night/run.env
  chmod 0600 /run/night/run.env &> /dev/null
}

# Load the run context in a worker: source .barracuda.cnf first (cnf flags and
# any var not in the freeze), then the run-freeze (authoritative for the frozen
# per-run set). No-op-safe if either is absent.
night_load_run_env() {
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && . /root/.barracuda.cnf
  # shellcheck disable=SC1091
  [ -r "/run/night/run.env" ] && . /run/night/run.env
}
