#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=pro
export _xSrl=588855proT01

[ -e "/root/.proxy.cnf" ] && exit 0

# A replication standby holds Solr down until promotion; creating, deleting
# or restarting cores here would act on an index still being synced. The
# xmass hold marker gates too: java.sh enforces the disarm every minute while
# it exists, until cutover step 14 or post-mig re-arms symmetrically. It is
# independent of the standby marker, so it can still be set after second.sh
# has self-removed a stale one -- and core work must not fight that
# enforcement.
[ -e "/root/.standby.cnf" ] && exit 0
[ -e "/var/log/boa/.xmass_solr_hold.pid" ] && exit 0

_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_vSet="variable-set --always-set"

###-------------SYSTEM-----------------###

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

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

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

_is_foreign_cms_root() {
  # A Grav 2 or Textpattern platform root (mirrors night.inc.sh): provision's
  # provision_platform_is_grav/_txp shape plus the platform scripts' Drupal
  # negatives, so no Drupal or Backdrop tree can ever read as foreign. False
  # for a link and for an absent path. $1 = platform root.
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

# An account owns its static/control, and oN owns the rest of its
# /data/disk/oN (log/, .drush/, config/, tools/, .tmp/, undo/) and the site
# trees its aliases name, so any name there can be a link or a FIFO, and any
# directory on the way can itself be a link. Root reads and writes those
# names only through the helpers below (the helper.sh.inc and night family
# bodies; this standalone cron tool sources neither).
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
# ./$1 in the current (pinned) directory as a fresh empty file: created
# exclusively, then renamed over the name, so a link or a FIFO put at the
# name is replaced, never followed or opened.
_acct_mark_here() {
  local _t="./.${1}.mark.$$.${RANDOM}"
  rm -f -- "${_t}"
  dd if=/dev/null of="${_t}" conv=excl status=none 2> /dev/null \
    && mv -f -T -- "${_t}" "./${1}" && return 0
  rm -f -- "${_t}"
  return 1
}

# Run "$@" inside the directory $1 as it resolves now, entered for real: $1
# is never a link itself and resolves strictly below this account root, and
# the resolved path is checked again once entered, so a name on the way
# swapped for a link afterwards is no longer on the path. For the
# alias-derived platform and site trees, which the per-site gates already
# accept through a link on the way; the account's own log/, .drush/ and
# config/ go through _acct_in_real_dir. Reads _usEr.
_acct_in_resolved_dir() {
  _in_resolved_dir acct "$@"
}
# The same for a site dir, which may also sit on the shared /data/all or
# /data/disk/all store a legacy instance still hosts sites on.
_site_in_resolved_dir() {
  _in_resolved_dir site "$@"
}
_in_resolved_dir() {
  local _k="${1}" _d="${2%/}" _rd _rus
  shift 2
  [ -n "${_d}" ] && [ ! -L "${_d}" ] && [ -d "${_d}" ] || return 1
  _rd=$(realpath -e -- "${_d}" 2> /dev/null) || return 1
  _rus=$(realpath -e -- "${_usEr}" 2> /dev/null) || return 1
  case "${_rd}/" in
    "${_rus}"/?*) ;;
    /data/all/?*|/data/disk/all/?*) [ "${_k}" = "site" ] || return 1 ;;
    *) return 1 ;;
  esac
  ( cd -P -- "${_rd}" 2> /dev/null && [ "$(pwd -P)" = "${_rd}" ] && "$@" )
}

# ./$1 in the current (pinned) directory replaced by the exact bytes $2, only
# while ./$1 is a regular file below 1 MiB (so a bounded read saw all of it):
# a fresh file with the owner, group and read/write bits of the file it
# replaces, then renamed over the name. The temp is created, written, owned
# and moded through one handle opened O_EXCL|O_NOFOLLOW, so nothing root owns
# is ever chowned by name in a directory the account can write (a hard link
# renamed over the temp name before a chown by name would have handed
# another file to the owner of the file it replaces); a swap before the
# rename only lands a file the account could have put there itself. The mode
# keeps only the read/write bits of the file it replaces, as before.
_ACCT_PUT_PL='use Fcntl; my ($n, $u, $g, $m) = @ARGV; local $/; my $d = <STDIN>; sysopen(my $h, $n, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1; (print {$h} $d) or exit 1; chown($u, $g, $h) or exit 1; chmod(oct($m) & 0666, $h) or exit 1; close($h) or exit 1; exit 0'
_acct_put_same_here() {
  local _t="./.${1}.put.$$.${RANDOM}" _st _typ _uid _gid _mod _sz
  _st=$(stat -c '%F|%u|%g|%a|%s' -- "./${1}" 2> /dev/null) || return 1
  IFS='|' read -r _typ _uid _gid _mod _sz <<< "${_st}"
  case "${_typ}" in
    "regular file"|"regular empty file") ;;
    *) return 1 ;;
  esac
  [[ "${_mod}" =~ ^[0-7]+$ && "${_sz}" =~ ^[0-9]+$ ]] || return 1
  [ "${_sz}" -lt 1048576 ] || return 1
  rm -f -- "${_t}"
  if printf '%s' "${2}" \
    | perl -e "${_ACCT_PUT_PL}" "${_t}" "${_uid}" "${_gid}" "${_mod}" \
    && mv -f -T -- "${_t}" "./${1}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# The lines $2 appended to ./$1 as ">>" appended them (one newline after the
# last), and put back as _acct_put_same_here puts it.
_acct_add_same_here() {
  local _c
  _c=$(_acct_read_plain_here "${1}" && echo x) || return 1
  _acct_put_same_here "${1}" "${_c%x}${2}"$'\n'
}

# The site INI sits in a tenant-writable setgid modules dir, so it can be
# swapped for a link or a FIFO between any test and its use, and the dir
# itself for a link. It is read and added to only inside its modules dir,
# entered for real (_acct_in_resolved_dir): a read is bounded, never through
# a link and never blocked on a FIFO (status 1, and nothing, unless it is a
# regular file); an addition is made in memory and lands, written by root,
# as a fresh file with the INI's own owner and mode, never through a link or
# into a FIFO. $1 = the INI path.
_ctrl_ini_read() {
  _acct_in_resolved_dir "${1%/*}" _acct_read_plain_here "${1##*/}"
}
# $2 = the line(s) to add.
_ctrl_ini_add() {
  _acct_in_resolved_dir "${1%/*}" _acct_add_same_here "${1##*/}" "${2}"
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
  # root file nor stall the pass. Reads _usEr, _HM_U and _HM_G from the
  # caller. $1 = source template, $2 = dest INI path.
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
  _rpn=$(realpath -e -- "${_pnt}" 2>/dev/null) || return 1
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
  chown "${_HM_U}:${_HM_G:-users}" "${_new}" &> /dev/null
  chmod 0664 "${_new}" &> /dev/null
  mv -f -T -- "${_new}" "/proc/self/fd/9/${3}" &> /dev/null && return 0
  rm -f -- "${_new}"
  return 1
}

# The site's solr.php, put as _reseed_ctrl_ini puts an INI. The site dir is
# the account's own, and the sites/ above it is group-writable on a ~/static
# codebase, so solr.php or the site dir can be swapped for a link at any
# time: a write by path would follow it, and the chown and chmod after it
# would hand the target to the account. The file is made in the root-only
# staging dir with its owner and mode set there, then renamed into the site
# dir, entered for real and held open on fd 9, so nothing is written,
# chowned or chmodded through a link. Reads _usEr, _HM_U and _HM_G.
# $1 = the solr.php path, $2 = its text.
_put_solr_info() {
  [ -n "${_HM_U}" ] || return 1
  case "${1}" in
    /*/*) : ;;
    *) return 1 ;;
  esac
  _acct_in_resolved_dir "${1%/*}" _put_solr_info_held "${1##*/}" "${2}"
}
# In the site dir (the current one, entered for real): held open on fd 9
# while the staging dir is entered.
_put_solr_info_held() {
  exec 9< . || return 1
  _ctrl_in_stage_dir _put_solr_info_here "${1}" "${2}"
}
# In the staging dir (the current one): the text $2 put as a fresh file of
# the account's (0440), then renamed as $1 into the directory held open on
# fd 9.
_put_solr_info_here() {
  local _new
  _new=$(mktemp ./solr.XXXXXX 2>/dev/null) || return 1
  if ! printf '%s\n' "${2}" > "${_new}"; then
    rm -f -- "${_new}"
    return 1
  fi
  chown "${_HM_U}:${_HM_G:-users}" "${_new}" &> /dev/null
  chmod 0440 "${_new}" &> /dev/null
  mv -f -T -- "${_new}" "/proc/self/fd/9/${1}" &> /dev/null && return 0
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

_check_config_diff() {
  # $1 is template path
  # $2 is a path to core config
  # Sets _slrCnfUpdate for this call alone: YES when the core's file differs
  # from the template, or is missing while the template is there (a broken
  # core), empty otherwise. Reset first, so a value left by an earlier call
  # (another site, core or file) never decides this one.
  _preCnf="$1"
  _slrCnf="$2"
  _slrCnfUpdate=""
  if [ -f "${_preCnf}" ] && [ ! -f "${_slrCnf}" ]; then
    _slrCnfUpdate=YES
    echo "INFO: ${_slrCnf} missing -- update from ${_preCnf}"
  elif [ -f "${_preCnf}" ] && [ -f "${_slrCnf}" ]; then
    _slrCnfUpdate=NO
    _diffMyTest=$(diff -w -B ${_slrCnf} ${_preCnf} 2>&1)
    if [ -z "${_diffMyTest}" ]; then
      _slrCnfUpdate=""
      echo "INFO: ${_slrCnf} diff0 empty -- nothing to update"
    else
      _slrCnfUpdate=YES
      # _diffMyTest=$(echo -n ${_diffMyTest} | fmt -su -w 2500)
      echo "INFO: ${_slrCnf} diff1 ${_diffMyTest}"
    fi
  fi
}

# Run "$@" inside ./$1 of the current (pinned) directory, entered one name at
# a time: every name on the relative path $1 must be a real directory, never
# a link, when it is entered, so no name on the way can point the walk at
# another directory, whatever is swapped before or after. Changes the
# directory: run it only as the "$@" of _acct_in_resolved_dir (a subshell).
_acct_down_real_here() {
  local _p="${1}" _n _h
  shift
  while [ -n "${_p}" ]; do
    _n="${_p%%/*}"
    if [ "${_n}" = "${_p}" ]; then
      _p=""
    else
      _p="${_p#*/}"
    fi
    case "${_n}" in
      ""|.|..) return 1 ;;
    esac
    _h="$(pwd -P)/${_n}"
    cd -P -- "./${_n}" 2> /dev/null && [ "$(pwd -P)" = "${_h}" ] || return 1
  done
  "$@"
}

# Run "$@" inside the site's upload dir, sites/<site>/files/solr, entered
# for real: the platform root as it resolves now (_acct_in_resolved_dir),
# then sites and the site one real directory at a time
# (_acct_down_real_here), then files (_solr_in_files_here), then solr, a
# real directory. Reads _Plr, _Dom and _usEr.
_solr_in_upload_dir() {
  [ -n "${_Plr}" ] && [ -n "${_Dom}" ] || return 1
  _acct_in_resolved_dir "${_Plr}" _acct_down_real_here \
    "sites/${_Dom}" _solr_in_files_here "$@"
}
# In the site dir (the current one, entered for real): run "$@" inside
# ./files/solr. files is a real directory, or the link autosymlink puts
# there into the account's files store, followed only where it resolves
# into the account's own static/files or that store moved onto attached
# storage (/mnt/<mount>/files/<oN>/static/files, the mount itself possibly
# nested, with no directory named files or static between /mnt and the
# mount, as the nightly decides it), and checked again once entered. Any
# other link on the way refuses. Changes the directory: run it only inside
# a subshell. Reads _usEr.
_solr_in_files_here() {
  local _r _rus _a _m
  if [ ! -L ./files ]; then
    _acct_down_real_here files/solr "$@"
    return
  fi
  _r=$(realpath -e -- ./files 2> /dev/null) || return 1
  _rus=$(realpath -e -- "${_usEr}" 2> /dev/null) || return 1
  _a="${_usEr##*/}"
  case "${_r}" in
    ""|*[!A-Za-z0-9._/-]*) return 1 ;;
    "${_rus}/static/files/"?*) ;;
    /mnt/?*/files/"${_a}"/static/files/?*)
      _m="${_r%%/files/"${_a}"/static/files/*}"
      case "${_m}" in
        */files/*|*/static/*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  cd -P -- "${_r}" 2> /dev/null && [ "$(pwd -P)" = "${_r}" ] || return 1
  _acct_down_real_here solr "$@"
}

# The site's Solr config upload (sites/<site>/files/solr) is tenant-writable,
# so any name in it can be a link, a hard link or a FIFO, and files/solr or
# any directory above it can be swapped for a link. It is used only inside
# that directory, entered for real (_solr_in_upload_dir). Every regular file
# directly in it, the set find -maxdepth 1 -type f copied, is read bounded,
# never through a link and never blocked on a FIFO, into the root-only
# directory $1, and only those copies are diffed and published: no tenant
# path is ever diffed or copied by name. A hard link (another file's bytes),
# a file of 8 MiB or more, one that changed while read, more than 512 names
# or more than 32 MiB in all refuse the whole set, so a core never gets part
# of one. Status 1 on a refusal. Reads _Plr, _Dom and _usEr. $1 = the
# root-only staging dir.
_solr_upload_stage() {
  [ -d "${1}" ] || return 1
  _solr_in_upload_dir _solr_upload_stage_here "${1}"
}
# ./$1 in the current (pinned) directory, read as _acct_read_here reads it,
# up to 8 MiB: an uploaded synonyms or stopwords list can be large.
_solr_upload_read_here() {
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
    bs=8388608 count=1 status=none 2> /dev/null
}
# In the upload dir (the current one, entered for real): each regular file
# copied into the root-only directory $1 as root's own file.
_solr_upload_stage_here() {
  local _to="${1}" _n _q _st _typ _nl _sz _cnt=0 _tot=0
  shopt -s nullglob dotglob
  for _n in *; do
    _q="${_n//[^[:alnum:]._-]/?}"
    _cnt=$(( _cnt + 1 ))
    if [ "${_cnt}" -gt 512 ]; then
      echo "SOLR-UPLOAD-REFUSED: ${_Dom} more than 512 names in files/solr"
      return 1
    fi
    _st=$(stat -c '%F|%h|%s' -- "./${_n}" 2> /dev/null) || continue
    IFS='|' read -r _typ _nl _sz <<< "${_st}"
    # A link, a FIFO or a directory is not published, as find -type f
    # never listed one.
    case "${_typ}" in
      "regular file"|"regular empty file") ;;
      *) continue ;;
    esac
    if [ "${_nl}" != "1" ]; then
      echo "SOLR-UPLOAD-REFUSED: ${_Dom} ${_q} is a hard link"
      return 1
    fi
    if [ "${_sz}" -ge 8388608 ]; then
      echo "SOLR-UPLOAD-REFUSED: ${_Dom} ${_q} is 8 MiB or more"
      return 1
    fi
    _tot=$(( _tot + _sz ))
    if [ "${_tot}" -gt 33554432 ]; then
      echo "SOLR-UPLOAD-REFUSED: ${_Dom} more than 32 MiB in files/solr"
      return 1
    fi
    if ! _solr_upload_read_here "${_n}" > "${_to}/${_n}"; then
      echo "SOLR-UPLOAD-REFUSED: ${_Dom} ${_q} could not be read"
      return 1
    fi
    # The size stat saw, or the name was swapped or changed while read.
    if [ "$(stat -c %s -- "${_to}/${_n}" 2> /dev/null)" != "${_sz}" ]; then
      echo "SOLR-UPLOAD-REFUSED: ${_Dom} ${_q} changed while read"
      return 1
    fi
  done
  return 0
}
# The upload, emptied once published as before (rm -f files/solr/*), but
# only inside the real files/solr, entered as _solr_upload_stage enters it:
# rm unlinks a link found there and never follows one.
_solr_upload_clear() {
  _solr_in_upload_dir _solr_upload_clear_here
}
_solr_upload_clear_here() {
  local _n
  shopt -s nullglob
  for _n in *; do
    rm -f -- "./${_n}" 2> /dev/null
  done
  return 0
}
# The first file of the staged upload $1 that is missing from the core conf
# dir $2 or differs from its copy there by a byte, printed with anything
# unusual in its name masked; status 1 when every staged file is there as
# uploaded. Every file counts, not solrconfig.xml alone, so a change to any
# file of the set is applied, and a set a failed copy left short is copied
# again. Both dirs are root's or Solr's, never the account's.
_solr_upload_differs() (
  local _n
  shopt -s nullglob dotglob
  for _n in "${1}"/*; do
    _n="${_n##*/}"
    [ -f "${1}/${_n}" ] || continue
    if ! cmp -s -- "${1}/${_n}" "${2}/${_n}" 2> /dev/null; then
      echo "${_n//[^[:alnum:]._-]/?}"
      return 0
    fi
  done
  return 1
)
# The staged upload $1 put in the core conf dir $2 as one set, in place of
# the files there (what rm -f conf/* removes, which are copied aside into
# the root-only dir $3 first). When any staged file fails to copy, the files
# copied so far are removed and the previous ones put back, so the core
# never keeps part of a set and the next pass still sees the upload as new.
# Status 1 when the set is not in place, 2 when the previous files could not
# all be put back either: $3 is then the only full copy of them.
_solr_upload_apply() {
  local _from="${1}" _conf="${2}" _old="${3}"
  [ -d "${_from}" ] && [ -d "${_conf}" ] && [ -d "${_old}" ] || return 1
  find "${_conf}" -mindepth 1 -maxdepth 1 ! -type d ! -name '.*' \
    -exec cp -a -t "${_old}/" -- {} + &> /dev/null || return 1
  rm -f "${_conf}"/* 2> /dev/null
  if find "${_from}" -mindepth 1 -maxdepth 1 -type f \
    -exec cp -f -t "${_conf}/" -- {} + &> /dev/null; then
    return 0
  fi
  _solr_upload_restore "${_conf}" "${_old}" || return 2
  return 1
}
# The previous files, copied aside into the root-only dir $2 by
# _solr_upload_apply, put back into the core conf dir $1 in place of the
# files there now, modes and owners as they were. Status 1 when they could
# not all be put back.
_solr_upload_restore() {
  [ -d "${1}" ] && [ -d "${2}" ] || return 1
  rm -f "${1}"/* 2> /dev/null
  find "${2}" -mindepth 1 -maxdepth 1 \
    -exec cp -a -t "${1}/" -- {} + &> /dev/null
}

_write_solr_config() {
  # ${1} is module
  # ${2} is a path to solr.php
  # ${3} is Jetty/Solr version
  # The text is put in place by _put_solr_info, never written by path.
  local _txt
  if [ ! -z "${1}" ] \
    && [ ! -z "${2}" ] \
    && [ ! -z "${3}" ] \
    && [ ! -z "${_SolrCoreID}" ] \
    && [ -e "${_Dir}" ]; then
    if [ "${3}" = "solr9" ]; then
      _PRT="9099"
      _VRS="9.10.1"
    elif [ "${3}" = "solr7" ]; then
      _PRT="9077"
      _VRS="7.7.3"
    else
      _PRT="8099"
      _VRS="4.9.1"
    fi
    if [ "${1}" = "search_api_solr" ] || [ "${1}" = "search_api_solr7" ] || [ "${1}" = "search_api_solr9" ]; then
      _module=search_api_solr
    fi
    _txt=$(
      echo "Your SOLR core access details for ${_Dom} site are as follows:"
      echo
      echo "  Drupal 8 and newer"
      echo "  Solr version .....: ${_VRS}"
      echo "  Solr host ........: 127.0.0.1"
      echo "  Solr port ........: ${_PRT}"
      echo "  Solr path ........: leave empty"
      echo "  Solr core ........: ${_SolrCoreID}"
      echo
      echo "  Don't forget to manually upload the configuration files"
      echo "  (schema.xml, solrconfig.xml) under ${_Dom}/files/solr"
      echo
      if [ "${3}" != "solr9" ]; then
        echo "  Drupal 7:"
        echo "  Solr version .....: ${_VRS}"
        echo "  Solr host ........: 127.0.0.1"
        echo "  Solr port ........: ${_PRT}"
        echo "  Solr path ........: /solr/${_SolrCoreID}"
        echo
      fi
      echo "It has been auto-configured to work with latest version"
      echo "of your integration module, but you need to add the module "
      echo "to your site codebase before you will be able to use Solr."
      echo
      echo "To learn more please make sure to check the module docs at:"
      echo
      echo "https://drupal.org/project/${_module}"
    )
    _put_solr_info "${2}" "${_txt}"
  fi
}

_reload_core_cnf() {
  # ${1} is solr server port
  # ${2} is solr core name
  # Example: _reload_core_cnf 9077 ${_SolrCoreID}
  # Example: _reload_core_cnf 9099 ${_SolrCoreID}
  # Example: _reload_core_cnf 8099 ${_SolrCoreID}
  # Solr answers a RELOAD it refuses (a config it cannot load) with an error
  # status and keeps serving the old core from memory, so only a 200 is
  # logged as reloaded. The status is left in _slrReloadCode, 000 when
  # Solr gave no answer at all.
  local _code
  _code=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:${1}/solr/admin/cores?action=RELOAD&core=${2}" 2> /dev/null)
  wait
  _slrReloadCode="${_code:-000}"
  if [ "${_code}" = "200" ]; then
    echo "Reloaded Solr core ${2} cnf on port ${1}"
    return 0
  fi
  echo "SOLR-RELOAD-ERROR: core ${2} on port ${1} -- HTTP ${_code:-000}"
  return 1
}

_update_solr() {
  # ${1} is module
  # ${2} is solr core path (auto) == _SOLR_DIR
  # ${3} is solr server version: solr9 or solr7 or jetty9
  # ${4} is "tpl" when BOA's template may replace the core's config: a new
  # core, or a site with solr_update_config = YES. Otherwise an apachesolr
  # or Drupal 7 core keeps the config it has, as the site INI documents.
  local _upStg="" _upOld="" _upDiff="" _upRc _upPort _upCode _upKeepOld=NO
  _SERV="${3}"
  if [ ! -z "${1}" ] && [ -e "/data/conf/solr" ]; then
    if [ "${1}" = "apachesolr" ]; then
      _SERV="jetty9"
      if [ -e "${_Plr}/modules/o_contrib_seven" ]; then
        if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ] \
          && [ "${4}" = "tpl" ]; then
          _slrCnfUpdate=""
          _check_config_diff "/data/conf/solr/apachesolr/solr4_drupal7/schema.xml" "${2}/conf/schema.xml"
          if [ ! -z "${_slrCnfUpdate}" ]; then
            rm -f ${2}/conf/*
            cp -af /data/conf/solr/apachesolr/solr4_drupal7/* ${2}/conf/
            chmod 644 ${2}/conf/*
            chown ${_SERV}:${_SERV} ${2}/conf/*
            touch ${2}/conf/.just-updated.pid
          else
            rm -f ${2}/conf/.just-updated.pid
            rm -f ${2}/conf/.yes-update.txt
          fi
        fi
      elif [ -e "${_Plr}/modules/o_contrib" ]; then
        if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ] \
          && [ "${4}" = "tpl" ]; then
          _slrCnfUpdate=""
          _check_config_diff "/data/conf/solr/apachesolr/solr4_drupal6/schema.xml" "${2}/conf/schema.xml"
          if [ ! -z "${_slrCnfUpdate}" ]; then
            rm -f ${2}/conf/*
            cp -af /data/conf/solr/apachesolr/solr4_drupal6/* ${2}/conf/
            chmod 644 ${2}/conf/*
            chown ${_SERV}:${_SERV} ${2}/conf/*
            touch ${2}/conf/.just-updated.pid
          else
            rm -f ${2}/conf/.just-updated.pid
            rm -f ${2}/conf/.yes-update.txt
          fi
        fi
      fi
    elif [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ] && [ -e "${_Plr}/modules/o_contrib_seven" ]; then
      if { [ "${1}" = "search_api_solr" ] || [ "${1}" = "search_api_solr7" ]; } \
        && [ "${4}" = "tpl" ]; then
        _check_config_diff "/data/conf/solr/search_api_solr/solr7_drupal7/schema.xml" "${2}/conf/schema.xml"
        if [ ! -z "${_slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/solr7_drupal7/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown ${_SERV}:${_SERV} ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
        _check_config_diff "/data/conf/solr/search_api_solr/solr7_drupal7/solrcore.properties" "${2}/conf/solrcore.properties"
        if [ ! -z "${_slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/solr7_drupal7/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown ${_SERV}:${_SERV} ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          # The marker stays as the leg above left it: that leg may have
          # just copied the whole template in (which is why this file
          # shows no diff) and set it, and the reload below must run.
          rm -f ${2}/conf/.yes-update.txt
        fi
      fi
    elif [ ! -e "${_Plr}/modules/o_contrib_seven" ] \
      && [ ! -e "${_Plr}/modules/o_contrib" ] \
      && [ ! -e "${2}/conf/.protected.conf" ] \
      && [ -e "${2}/conf" ] \
      && [ ! -L "${_Plr}/sites/${_Dom}/files/solr" ] \
      && [ -e "${_Plr}/sites/${_Dom}/files/solr/schema.xml" ] \
      && [ -e "${_Plr}/sites/${_Dom}/files/solr/solrconfig.xml" ] \
      && [ -e "${_Plr}/sites/${_Dom}/files/solr/solrcore.properties" ]; then
      if [ "${1}" = "search_api_solr" ] || [ "${1}" = "search_api_solr7" ] || [ "${1}" = "search_api_solr9" ]; then
        ### The tests above only pick this branch. The upload is read once,
        ### inside the real files/solr, into a root-only dir
        ### (_solr_upload_stage), and only those copies are diffed and
        ### published: a link or FIFO put in the upload, or a directory on
        ### the way swapped for a link, can neither stall the pass nor make
        ### root read or publish another directory's files. A client's own
        ### links are simply not published -- the config they upload still
        ### is. The set is applied whole or not at all.
        _upStg=$(mktemp -d /tmp/solr_upload_XXXXXX 2> /dev/null)
        if [ -n "${_upStg}" ] \
          && _solr_upload_stage "${_upStg}" \
          && [ -f "${_upStg}/schema.xml" ] \
          && [ -f "${_upStg}/solrconfig.xml" ] \
          && [ -f "${_upStg}/solrcore.properties" ]; then
          # The core's solrcore.properties is kept in BOA's own form, which
          # _fix_solr9_cnf and _fix_solr7_cnf put it in, and restart Solr
          # for, at the start of a pass. The staged copy is put in that form
          # first, so the core gets it as BOA keeps it: nothing is rewritten
          # or restarted for it later, and the same set uploaded again
          # compares identical below.
          if _solr_props_boa_form "${_upStg}/solrcore.properties" "${_SERV}"; then
            echo "INFO: ${_Dom} uploaded solrcore.properties set to this server's Solr"
          fi
          # Any staged file missing from the core or different there makes
          # the set new, so a core without solrconfig.xml is repaired too.
          if _upDiff=$(_solr_upload_differs "${_upStg}" "${2}/conf"); then
            echo "INFO: ${_Dom} upload differs from ${2}/conf at ${_upDiff}"
            # root's own copies of root's own staged files. The previous
            # files stay aside until Solr has reloaded the core on the set,
            # and a set it refuses is rolled back to them, so the core is
            # never left with files it cannot load at its next start. The
            # core is marked custom, and the upload emptied, only once the
            # set is loaded; a failed copy leaves the previous files and the
            # upload in place, for the next pass to retry.
            _upOld=$(mktemp -d /tmp/solr_conf_XXXXXX 2> /dev/null)
            _upRc=1
            if [ -n "${_upOld}" ]; then
              _solr_upload_apply "${_upStg}" "${2}/conf" "${_upOld}"
              _upRc=$?
            fi
            if [ "${_upRc}" = "0" ]; then
              find "${2}/conf" -maxdepth 1 -type f \
                -exec chmod 644 {} \; &> /dev/null
              find "${2}/conf" -maxdepth 1 -type f \
                -exec chown "${_SERV}:${_SERV}" {} \; &> /dev/null
              # This core's reload is run here, not in the shared step
              # below, so its answer decides the set while the previous
              # files are still aside. The marker outlives it only when a
              # pass stops before the answer: the next pass finds the set
              # in place and leaves the reload to the shared step.
              touch "${2}/conf/.just-updated.pid"
              _upPort=""
              if [[ "${2}" =~ "/var/solr7/data" ]] && [ "${_SERV}" = "solr7" ]; then
                _upPort=9077
              elif [[ "${2}" =~ "/var/solr9/data" ]] && [ "${_SERV}" = "solr9" ]; then
                _upPort=9099
              fi
              [ -n "${_upPort}" ] && touch "${2}/conf/${_xSrl}.conf"
              if [ -z "${_upPort}" ] \
                || _reload_core_cnf "${_upPort}" "${_SolrCoreID}"; then
                touch "${2}/conf/.yes-custom.txt"
                _solr_upload_clear
              else
                _upCode="${_slrReloadCode:-000}"
                if _solr_upload_restore "${2}/conf" "${_upOld}"; then
                  echo "SOLR-UPLOAD-ROLLED-BACK: ${_Dom} Solr answered HTTP ${_upCode} to the uploaded set, previous files put back into ${2}/conf"
                  _reload_core_cnf "${_upPort}" "${_SolrCoreID}"
                else
                  _upKeepOld=YES
                  echo "SOLR-UPLOAD-ERROR: ${_Dom} previous files could not be put back into ${2}/conf, a copy is kept in ${_upOld}"
                fi
                # No answer at all (Solr not running) says nothing about the
                # set, so it is tried again on the next pass. A set Solr
                # answered with an error is removed, as an applied one is,
                # and not retried on every pass: the log says why.
                if [ "${_upCode}" = "000" ]; then
                  echo "SOLR-UPLOAD-KEPT: ${_Dom} Solr did not answer, the upload is tried again on the next pass"
                else
                  _solr_upload_clear
                fi
              fi
              rm -f "${2}/conf/.just-updated.pid"
            elif [ "${_upRc}" = "2" ]; then
              _upKeepOld=YES
              echo "SOLR-UPLOAD-ERROR: ${_Dom} copy into ${2}/conf failed and the previous files could not be put back, a copy is kept in ${_upOld}, the upload kept for the next pass"
            else
              echo "SOLR-UPLOAD-ERROR: ${_Dom} copy into ${2}/conf failed, previous files and the upload kept for the next pass"
            fi
            [ "${_upKeepOld}" = "NO" ] && [ -n "${_upOld}" ] \
              && [ -d "${_upOld}" ] && rm -rf -- "${_upOld}"
          else
            # Every staged file is in the core as uploaded: a pass that
            # applied it stopped before emptying the upload, or the same set
            # was uploaded again. It is the account's config, marked as an
            # applied upload is, and emptied, so it is not re-read on every
            # pass for good. A marker left by a pass that stopped before
            # its reload stays for the shared step below, which reloads the
            # core on the set.
            touch "${2}/conf/.yes-custom.txt"
            _solr_upload_clear
            rm -f "${2}/conf/.yes-update.txt"
          fi
        else
          echo "SKIP: Solr config upload for ${_Dom} not applied this pass"
        fi
        [ -n "${_upStg}" ] && [ -d "${_upStg}" ] && rm -rf -- "${_upStg}"
      fi
    # Drupal 8 and later cores are created on Solr's own managed schema
    # (without -d); their config comes only from the account's files/solr
    # upload above. BOA ships no template for them.
    fi
    _fiLe="${_Dir}/solr.php"
    echo "Info file for ${_Dom} is ${_fiLe}"
    echo "Info _SERV is ${_SERV}"
    _SOLR_CONFIG_INFO_UPDATE=NO
    if [ -e "${_fiLe}" ]; then
      # Read inside the site dir: never through a link or blocked on a FIFO.
      _SOLR_CONFIG_INFO_TEST=$(_acct_in_resolved_dir "${_fiLe%/*}" \
        _acct_read_plain_here "${_fiLe##*/}" | grep "${_SolrCoreID}" 2>&1)
      if [[ ! "${_SOLR_CONFIG_INFO_TEST}" =~ "${_SolrCoreID}" ]]; then
        _SOLR_CONFIG_INFO_UPDATE=YES
      fi
    fi
    if [ ! -e "${_fiLe}" ] \
      || [ "${_SOLR_CONFIG_INFO_UPDATE}" = "YES" ] \
      || [ -e "${2}/conf/.just-updated.pid" ]; then
      if [[ "${2}" =~ "/opt/solr4" ]] && [ "${_SERV}" = "jetty9" ]; then
        _write_solr_config ${1} ${_fiLe} ${_SERV}
        echo "Updated ${_fiLe} with ${2} details"
        touch ${2}/conf/${_xSrl}.conf
        _reload_core_cnf 8099 ${_SolrCoreID}
      elif [[ "${2}" =~ "/var/solr7/data" ]] && [ "${_SERV}" = "solr7" ]; then
        _write_solr_config ${1} ${_fiLe} ${_SERV}
        echo "Updated ${_fiLe} with ${2} details"
        touch ${2}/conf/${_xSrl}.conf
        _reload_core_cnf 9077 ${_SolrCoreID}
      elif [[ "${2}" =~ "/var/solr9/data" ]] && [ "${_SERV}" = "solr9" ]; then
        _write_solr_config ${1} ${_fiLe} ${_SERV}
        echo "Updated ${_fiLe} with ${2} details"
        touch ${2}/conf/${_xSrl}.conf
        _reload_core_cnf 9099 ${_SolrCoreID}
      fi
      # The marker is a one-shot request for the write and the reload
      # above. The template branches also clear it on their next no-diff
      # pass; the upload branch reloads its core itself and clears its own,
      # which reaches this step only from a pass that stopped before that
      # reload. Cleared here, so no later pass rewrites solr.php and
      # reloads the core forever.
      rm -f ${2}/conf/.just-updated.pid
    fi
  fi
}

_add_solr() {
  # ${1} is module
  # ${2} is solr core path
  # ${3} is solr core version: solr9, solr7, jetty9
  if [ "${1}" = "apachesolr" ]; then
    _SOLR_BASE="/opt/solr4"
    _SOLR_VER=jetty9
  elif [ "${1}" = "search_api_solr" ]; then
    _SOLR_BASE="/var/solr7/data"
    _SOLR_VER=solr7
  elif [ "${1}" = "search_api_solr7" ]; then
    _SOLR_BASE="/var/solr7/data"
    _SOLR_VER=solr7
  elif [ "${1}" = "search_api_solr9" ]; then
    _SOLR_BASE="/var/solr9/data"
    _SOLR_VER=solr9
  fi

  echo in _add_solr _SolrCoreID is ${_SolrCoreID}
  echo in _add_solr _SOLR_BASE is ${_SOLR_BASE}
  echo in _add_solr _SOLR_VER is ${_SOLR_VER}

  if [ ! -z "${1}" ] && [ ! -z "${2}" ] && [ -e "/data/conf/solr" ]; then
    if [ ! -e "${2}" ]; then
      if [ "${_SOLR_BASE}" = "/var/solr9/data" ] \
        && [ -x "/opt/solr9/bin/solr" ] \
        && [ -e "/var/solr9/data" ]; then
        if [ -e "${_Plr}/modules/o_contrib_ten" ] \
          || [ -e "${_Plr}/modules/o_contrib_eleven" ]; then
          echo in _add_solr create_core -p 9099 -c ${_SolrCoreID}
          su -s /bin/bash - solr9 -c "/opt/solr9/bin/solr create_core -p 9099 -c ${_SolrCoreID}"
          wait
        else
          echo "The Solr 9 is supported only for Drupal 10.2 and newer!"
        fi
      elif [ "${_SOLR_BASE}" = "/var/solr7/data" ] \
        && [ -x "/opt/solr7/bin/solr" ] \
        && [ -e "/var/solr7/data" ]; then
        if [ -e "${_Plr}/modules/o_contrib_seven" ]; then
          echo in _add_solr o_contrib_seven create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID} -d /data/conf/solr/search_api_solr/solr7_drupal7"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_eight" ]; then
          echo in _add_solr o_contrib_eight create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_nine" ]; then
          echo in _add_solr o_contrib_nine create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_ten" ]; then
          echo in _add_solr o_contrib_ten create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_eleven" ]; then
          echo in _add_solr o_contrib_eleven create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        else
          echo "The Solr 7 is supported only for Drupal 7 and newer!"
        fi
      elif [ "${_SOLR_BASE}" = "/opt/solr4" ]; then
        echo in _add_solr solr4 create ${_SolrCoreID}
        rm -rf ${_SOLR_BASE}/core0/data/*
        cp -a ${_SOLR_BASE}/core0 ${2}
        sed -i "s/.*name=\"${_Legacy_SolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "s/.*name=\"${_Old_SolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "s/.*<core name=\"core0\" instan_ceDir=\"core0\" \/>.*/<core name=\"core0\" instan_ceDir=\"core0\" \/>\n<core name=\"${_SolrCoreID}\" instan_ceDir=\"${_SolrCoreID}\" \/>\n/g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "/^$/d" ${_SOLR_BASE}/solr.xml &> /dev/null
        wait
        pkill -9 -f '^[^ ]*java[0-9]* .*jetty9'
        service jetty9 start &> /dev/null
      fi
      echo "New Solr ${3} with ${1} for ${2} added"
    fi
    # A Drupal 8+ core created while the site INI sets solr_custom_config =
    # YES (leg 1 of this call read it) is protected before the refresh
    # below, so it stays on Solr's managed schema and takes no upload. An
    # apachesolr or Drupal 7 core still goes through BOA's template check
    # here, as a new core does, and leg 2 protects it after.
    if [ "${_SLR_CM_CFG_L1}" = "YES" ] && [ -d "${2}/conf" ] \
      && [ ! -L "${2}/conf" ] && [ "${1}" != "apachesolr" ] \
      && [ ! -e "${_Plr}/modules/o_contrib_seven" ] \
      && [ ! -e "${_Plr}/modules/o_contrib" ]; then
      touch "${2}/conf/.protected.conf"
      echo "Solr config for ${2} is protected"
    fi
    _update_solr "${1}" "${2}" "${3}" tpl
  fi
}

_archive_solr_core() {
  # ${1} = core dir. A teardown is unrecoverable once the index is gone, and
  # the trigger is a cleared directive -- recoverable intent deserves a
  # recoverable result. For Solr 7 and 9 the archive IS the delete, in the
  # orphan path's own shape (_archive_orphan_core, recovery recipe there):
  # UNLOAD without deleting any file, then move the core tree to
  # /var/backups/solr7|solr9/<ts>-<core>. No copy, no extra disk, and it
  # cannot repeat, because the source is gone -- the callers delete only a
  # core that is still in place afterwards. Solr 4 has no core-admin API
  # here, so its tree is tarred under a free-space precheck before the
  # rm -rf that follows; a core that cannot be archived is left in place
  # rather than deleted. An empty or absent core has nothing worth keeping
  # and passes straight through.
  local _core="$1" _name _ts _port _bkp _need _free _arch
  [ -d "${_core}" ] || return 0
  [ -n "$(find "${_core}" -type f -print -quit 2>/dev/null)" ] || return 0
  _name=$(basename "${_core}")
  _ts=$(date +%Y%m%d-%H%M%S)
  case "${_core}" in
    /var/solr9/data/*) _port=9099; _bkp=/var/backups/solr9 ;;
    /var/solr7/data/*) _port=9077; _bkp=/var/backups/solr7 ;;
    *) _port=; _bkp=/var/backups/solr-archive ;;
  esac
  if [ -n "${_port}" ]; then
    curl -s --max-time 15 \
      "http://127.0.0.1:${_port}/solr/admin/cores?action=UNLOAD&core=${_name}&deleteIndex=false&deleteDataDir=false&deleteInstanceDir=false" \
      &> /dev/null || true
    wait
    mkdir -p "${_bkp}" &> /dev/null
    if mv "${_core}" "${_bkp}/${_ts}-${_name}" 2>/dev/null; then
      echo "Archived Solr core ${_core} to ${_bkp}/${_ts}-${_name}"
      return 0
    fi
    echo "Could not archive Solr core ${_core} -- leaving it in place"
    return 1
  fi
  _need=$(du -sk "${_core}" 2>/dev/null | cut -f1)
  _need="${_need//[^0-9]/}"
  _free=$(df -Pk /var/backups 2>/dev/null | awk 'NR==2 {print $4}')
  _free="${_free//[^0-9]/}"
  if [ -z "${_need}" ] || [ -z "${_free}" ] \
    || [ "${_free}" -lt $(( _need + 262144 )) ]; then
    echo "Not enough free space under /var/backups to archive Solr core ${_core} -- leaving it in place"
    return 1
  fi
  mkdir -p "${_bkp}" &> /dev/null
  chmod 0700 "${_bkp}" &> /dev/null
  _arch="${_bkp}/${_name}-${_ts}.tar.gz"
  if tar -czf "${_arch}.tmp" -C "$(dirname "${_core}")" "${_name}" 2>/dev/null \
    && [ -s "${_arch}.tmp" ] \
    && mv -f "${_arch}.tmp" "${_arch}" 2>/dev/null; then
    echo "Archived Solr core ${_core} to ${_arch}"
    return 0
  fi
  rm -f "${_arch}.tmp" &> /dev/null
  echo "Could not archive Solr core ${_core} -- leaving it in place"
  return 1
}

_delete_solr() {
  # ${1} is solr core path
  # The site's solr.php is removed only inside the site dir, entered for real
  # (_acct_in_resolved_dir), so a site dir swapped for a link is never used.
  if [[ "${1}" =~ "solr4" ]]; then
    _SOLR_BASE="/opt/solr4"
  elif [[ "${1}" =~ "solr7" ]]; then
    _SOLR_BASE="/var/solr7/data"
  elif [[ "${1}" =~ "solr9" ]]; then
    _SOLR_BASE="/var/solr9/data"
  fi
  if [ ! -z "${1}" ] && [ -e "/data/conf/solr" ] && [ -e "${1}/conf" ]; then
    # The Solr 9 home holds no solr.xml -- since Solr 9 it is loaded from
    # the install dir -- so gate on the data dir itself, as _add_solr does.
    if [ "${_SOLR_BASE}" = "/var/solr9/data" ] \
      && [ -x "/opt/solr9/bin/solr" ] \
      && [ -e "/var/solr9/data" ]; then
      # The Solr 9 CLI ignores -p for delete and falls back to port 8983,
      # so remove the core via the Core Admin API on the instance port
      if [ -e "${_SOLR_BASE}/${_SolrCoreID}" ] \
        && _archive_solr_core "${_SOLR_BASE}/${_SolrCoreID}" \
        && [ -e "${_SOLR_BASE}/${_SolrCoreID}" ]; then
        curl -s --max-time 15 \
          "http://127.0.0.1:9099/solr/admin/cores?action=UNLOAD&core=${_SolrCoreID}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" \
          &> /dev/null
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Old_SolrCoreID}" ] \
        && _archive_solr_core "${_SOLR_BASE}/${_Old_SolrCoreID}" \
        && [ -e "${_SOLR_BASE}/${_Old_SolrCoreID}" ]; then
        curl -s --max-time 15 \
          "http://127.0.0.1:9099/solr/admin/cores?action=UNLOAD&core=${_Old_SolrCoreID}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" \
          &> /dev/null
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Legacy_SolrCoreID}" ] \
        && _archive_solr_core "${_SOLR_BASE}/${_Legacy_SolrCoreID}" \
        && [ -e "${_SOLR_BASE}/${_Legacy_SolrCoreID}" ]; then
        curl -s --max-time 15 \
          "http://127.0.0.1:9099/solr/admin/cores?action=UNLOAD&core=${_Legacy_SolrCoreID}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" \
          &> /dev/null
        wait
      fi
      _acct_in_resolved_dir "${_Dir}" rm -f -- ./solr.php &> /dev/null
    elif [ "${_SOLR_BASE}" = "/var/solr7/data" ] \
      && [ -x "/opt/solr7/bin/solr" ] \
      && [ -e "/var/solr7/data/solr.xml" ]; then
      if [ -e "${_SOLR_BASE}/${_SolrCoreID}" ] \
        && _archive_solr_core "${_SOLR_BASE}/${_SolrCoreID}" \
        && [ -e "${_SOLR_BASE}/${_SolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${_SolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Old_SolrCoreID}" ] \
        && _archive_solr_core "${_SOLR_BASE}/${_Old_SolrCoreID}" \
        && [ -e "${_SOLR_BASE}/${_Old_SolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${_Old_SolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Legacy_SolrCoreID}" ] \
        && _archive_solr_core "${_SOLR_BASE}/${_Legacy_SolrCoreID}" \
        && [ -e "${_SOLR_BASE}/${_Legacy_SolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${_Legacy_SolrCoreID}"
        wait
      fi
      _acct_in_resolved_dir "${_Dir}" rm -f -- ./solr.php &> /dev/null
    elif [ "${_SOLR_BASE}" = "/opt/solr4" ] && _archive_solr_core "${1}"; then
      sed -i "s/.*instan_ceDir=\"${_SolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
      wait
      sed -i "s/.*name=\"${_Legacy_SolrCoreID}\".*//g"  ${_SOLR_BASE}/solr.xml
      wait
      sed -i "s/.*name=\"${_Old_SolrCoreID}\".*//g"     ${_SOLR_BASE}/solr.xml
      wait
      sed -i "/^$/d" ${_SOLR_BASE}/solr.xml &> /dev/null
      wait
      rm -rf ${1}
      _acct_in_resolved_dir "${_Dir}" rm -f -- ./solr.php &> /dev/null
      pkill -9 -f '^[^ ]*java[0-9]* .*jetty9'
      service jetty9 start &> /dev/null
    fi
    echo "Deleted Solr core in ${1}"
  fi
}

_core_registry_state() {
  # ${1} = port  ${2} = core name
  # Prints registered, failed, absent, nopython or unknown (Solr unreachable,
  # or its answer not usable). A STATUS for a single name answers with an
  # empty status block for a name Solr does not know, and lists a core that
  # failed to load under initFailures instead -- two shapes the caller must
  # tell apart, so the answer is parsed, not grepped. An error answer (a
  # damaged index makes STATUS itself throw) carries no status block at
  # all and must not read as absent.
  local _port="${1}" _core="${2}" _json _tmp _state
  if ! command -v python3 &> /dev/null; then
    echo "nopython"
    return 0
  fi
  _json=$(curl -s --max-time 15 \
    "http://127.0.0.1:${_port}/solr/admin/cores?action=STATUS&core=${_core}&wt=json" 2>/dev/null)
  if [ -z "${_json}" ]; then
    echo "unknown"
    return 0
  fi
  _tmp=$(mktemp /tmp/solr_status_XXXXXX.json)
  if [ -z "${_tmp}" ]; then
    echo "unknown"
    return 0
  fi
  echo "${_json}" > "${_tmp}"
  _state=$(python3 - "${_tmp}" "${_core}" <<'PYSTATE'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    print("unknown")
    sys.exit(0)
core = sys.argv[2]
if not isinstance(data, dict) or "error" in data or "status" not in data \
        or (data.get("responseHeader") or {}).get("status", 0) != 0:
    print("unknown")
elif core in (data.get("initFailures") or {}):
    print("failed")
elif (data.get("status") or {}).get(core):
    print("registered")
else:
    print("absent")
PYSTATE
)
  rm -f "${_tmp}"
  echo "${_state:-unknown}"
}

_core_retry_due() {
  # ${1} = core path  ${2} = failed-attempt stamp
  # A failed attempt is retried once the conf has changed since (the
  # daemon's own refresh touches the release stamp in conf as it reloads;
  # a hand edit gives a newer file) or after an hour, whichever comes
  # first -- never on every pass, and never left for a Solr restart alone.
  local _p="${1}" _s="${2}" _f
  [ -e "${_s}" ] || return 0
  [ -n "$(find "${_s}" -maxdepth 0 -mmin +60 2>/dev/null)" ] && return 0
  for _f in "${_p}/conf/${_xSrl}.conf" "${_p}/conf/solrconfig.xml" "${_p}/conf/schema.xml"; do
    [ "${_f}" -nt "${_s}" ] && return 0
  done
  return 1
}

_reregister_solr_core() {
  # ${1} = core path  ${2} = solr server version
  # A core directory with no core.properties is invisible to Solr, whose
  # core discovery keys on that file, and it was invisible here too: the
  # update path only ever RELOADs, and Solr answers "No such core" for a
  # directory it never loaded -- silently, every pass, for as long as the
  # site stays bound. Seen after a core's conf was replaced from an archive
  # that did not carry the file. A CoreAdmin CREATE on the existing
  # instanceDir registers the directory as it is, index included, and
  # writes only core.properties. The gate on that file's absence is not a
  # shortcut: Solr refuses a CREATE into an instanceDir that already holds
  # one and deletes the file on its way out, which would unregister a core
  # that merely failed to load. Solr 4 keeps its registry in solr.xml and
  # has no such file, so it is not handled here. Runs after the check's
  # _update_solr, which applies a Drupal 8+ site's upload when one waits,
  # so that attempt loads the conf just published. A Drupal 7 or
  # apachesolr core takes BOA's template only later, in the
  # solr_update_config = YES leg, so this attempt loads the conf the core
  # already has.
  local _path="${1}" _serv="${2}" _port _core _state _resp _rc _stamp _own
  case "${_path}" in
    /var/solr9/data/*) _port=9099; [ "${_serv}" = "solr9" ] || return 0 ;;
    /var/solr7/data/*) _port=9077; [ "${_serv}" = "solr7" ] || return 0 ;;
    *) return 0 ;;
  esac
  [ -d "${_path}" ] && [ ! -L "${_path}" ] || return 0
  [ -e "${_path}/core.properties" ] && return 0
  [ -x "/etc/init.d/${_serv}" ] || return 0
  _core=$(basename "${_path}")
  # -e is false on a dangling symlink, and both writers below would follow it
  if [ -L "${_path}/core.properties" ]; then
    echo "CORE-REREGISTER-SKIP: ${_core} carries a symlink named core.properties under ${_path} -- not touched"
    return 0
  fi
  if [ ! -e "${_path}/conf/solrconfig.xml" ]; then
    echo "CORE-REREGISTER-SKIP: ${_core} has no conf/solrconfig.xml under ${_path} -- not re-registered"
    return 0
  fi
  _state=$(_core_registry_state "${_port}" "${_core}")
  _stamp="${_path}/conf/.reregister-failed.pid"
  case "${_state}" in
    absent) ;;
    registered)
      # The latent phase of the same outage: Solr still serves the core
      # from memory and will not find it at its next start. The name is
      # the file's only load-bearing line and is all Solr itself writes
      # for a core created here, so put it back and say so.
      if printf 'name=%s\n' "${_core}" > "${_path}/core.properties" \
        && chown "${_serv}:${_serv}" "${_path}/core.properties" \
        && chmod 644 "${_path}/core.properties"; then
        echo "CORE-REREGISTER-PERSISTED: ${_core} on port ${_port} was served from memory only -- core.properties written back for the next Solr start"
      else
        echo "CORE-REREGISTER-ERROR: ${_core} on port ${_port} -- could not write ${_path}/core.properties"
      fi
      return 0
      ;;
    failed)
      if ! _core_retry_due "${_path}" "${_stamp}"; then
        echo "CORE-REREGISTER-SKIP: ${_core} on port ${_port} failed to load -- retried when its conf changes or after an hour"
        return 0
      fi
      # Clear Solr's record of the failure so the CREATE is not refused.
      # Every delete flag off: a failed core has no descriptor, so this
      # touches no file.
      curl -s --max-time 15 \
        "http://127.0.0.1:${_port}/solr/admin/cores?action=UNLOAD&core=${_core}&deleteIndex=false&deleteDataDir=false&deleteInstanceDir=false" \
        &> /dev/null
      ;;
    nopython)
      echo "CORE-REREGISTER-SKIP: python3 not available, ${_core} on port ${_port} not checked"
      return 0
      ;;
    *) return 0 ;;
  esac
  if [ -e "${_stamp}" ] && ! _core_retry_due "${_path}" "${_stamp}"; then
    echo "CORE-REREGISTER-SKIP: ${_core} on port ${_port} refused last time -- retried when its conf changes or after an hour"
    return 0
  fi
  # A fleet-wide loss would otherwise spend one pass on every core at once;
  # each CREATE opens an index, so keep a pass to a few and take the rest
  # on the next tick.
  if [ "${_REREGISTER_DONE:-0}" -ge "${_REREGISTER_MAX:-3}" ]; then
    echo "CORE-REREGISTER-DEFERRED: ${_core} on port ${_port} -- pass limit reached, next pass"
    return 0
  fi
  # A tree restored as root cannot take Solr's core.properties, and that
  # refusal leaves no failure record to bound the retries.
  _own=$(stat -c %U "${_path}" 2>/dev/null)
  if [ -n "${_own}" ] && [ "${_own}" != "${_serv}" ]; then
    chown -R "${_serv}:${_serv}" "${_path}" &> /dev/null
    echo "CORE-REREGISTER-CHOWN: ${_core} tree was owned by ${_own}, now ${_serv}"
  fi
  _resp=$(curl -s --max-time 120 \
    "http://127.0.0.1:${_port}/solr/admin/cores?action=CREATE&name=${_core}&instanceDir=${_path}&wt=json" 2>/dev/null)
  _rc=$?
  _REREGISTER_DONE=$(( ${_REREGISTER_DONE:-0} + 1 ))
  if [ -e "${_path}/core.properties" ] \
    && [ "$(_core_registry_state "${_port}" "${_core}")" = "registered" ]; then
    rm -f "${_stamp}"
    echo "CORE-REREGISTERED: ${_core} on port ${_port} from ${_path}"
  elif [ "${_rc}" = "28" ] && [ -e "${_path}/core.properties" ]; then
    # Solr writes the file before it opens the index, so a slow load past
    # the timeout is still succeeding.
    echo "CORE-REREGISTER-PENDING: ${_core} on port ${_port} -- Solr is still loading it"
  else
    [ -n "${_resp}" ] && _resp=$(printf '%s' "${_resp}" | tr -s '[:space:]' ' ' | cut -c1-300)
    touch "${_stamp}"
    echo "CORE-REREGISTER-ERROR: ${_core} on port ${_port} -- ${_resp:-no response}"
  fi
}

_check_solr() {
  # ${1} is module
  # ${2} is solr core path
  # ${3} is solr server version
  if [ ! -z "${1}" ] && [ ! -z "${2}" ] && [ ! -z "${3}" ] && [ -e "/data/conf/solr" ]; then
    echo "Checking Solr ${3} with ${1} for ${2}"
    if [ ! -e "${2}" ]; then
      _add_solr "${1}" "${2}" "${3}"
    else
      _update_solr "${1}" "${2}" "${3}"
      _reregister_solr_core "${2}" "${3}"
    fi
  fi
}

_ctrl_ini_leg_ok() {
  # Re-check the site INI right before a read/add leg. The loop-start strip
  # in _check_sites_list can be minutes old by now (a CoreAdmin CREATE, a
  # jetty9 restart), and a link planted since stays until stripped.
  # Re-validate the dir, strip a planted link, and act only on a regular
  # file; the leg itself reads and adds through _ctrl_ini_read and
  # _ctrl_ini_add, which never follow a name swapped after this test.
  # Reads _Dir and _DIR_CTRL_F.
  _validate_ctrl_dir "${_Dir}/modules" || return 1
  _desymlink_planted "${_DIR_CTRL_F}"
  [ -f "${_DIR_CTRL_F}" ] && [ ! -L "${_DIR_CTRL_F}" ]
}

_solr_teardown_intended() {
  # ${1} = site INI text (_ctrl_ini_read). A commented-out directive is an
  # operator's teardown request (docs/SOLR.md) -- unless the INI is the
  # placeholder BOA itself reseeded after the file went missing. That pass
  # sets a root-only sentinel in the staging dir, and later passes keep
  # honouring it for as long as
  # the INI still carries the pristine placeholder line: the first moment the
  # placeholder can carry operator intent is when that line has been edited,
  # and BOA's own nightly INI writers never touch it. The sentinel is dropped
  # again the moment a valid module directive is seen. Durable on purpose: a
  # shell flag protects one pass, and the cron runs every four minutes.
  # oN owns the account root, so the sentinel is looked up only inside the
  # real .boa-ctrl, never through a link put at that name.
  [ "${_SOLR_INI_RESEEDED}" = "YES" ] && return 1
  [ -n "${_SolrCoreID}" ] || return 0
  _acct_in_real_dir "${_usEr}/.boa-ctrl" \
    test -e "./solr-reseeded.${_SolrCoreID}" || return 0
  if grep -q "^;solr_integration_module = your_module_name_here" <<< "$1" 2>/dev/null; then
    return 1
  fi
  return 0
}

_setup_solr() {
  # A site INI that is MISSING is reseeded from the default template, whose
  # solr_integration_module line is the commented-out placeholder -- the very
  # shape the teardown branch below reads as "directive cleared". A missing
  # file is not an operator decision (a deploy rsync --delete, a hand rm, a
  # stripped symlink all produce it), so a pass that had to reseed never tears
  # down, and -- through the sentinel _solr_teardown_intended reads -- neither
  # does any later pass until the operator has edited the directive itself.
  #
  # The core state below is global and every site of every account runs
  # through here in one process, so it is cleared first: legs 2 and 3 act
  # only on the core leg 1 chose for this site in this call (_leg1), never
  # on one left by the site before, possibly another account's, when this
  # site's leg 1 did not run.
  local _iniTxt _leg1=NO
  _SOLR_MODULE="" _SOLR_BASE="" _SOLR_VER="" _SOLR_DIR="" _SOLR_TEARDOWN=NO
  _SLR_CM_CFG_RT=NO _SOLR_PROTECT_CTRL="" _SLR_CM_CFG_L1=NO
  _SOLR_INI_RESEEDED=NO
  if [ -e "/data/conf/default.boa_site_control.ini" ] \
    && [ ! -e "${_DIR_CTRL_F}" ]; then
    _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
    _SOLR_INI_RESEEDED=YES
    if [ -e "${_DIR_CTRL_F}" ] && [ -n "${_SolrCoreID}" ]; then
      _ctrl_in_stage_dir _acct_mark_here "solr-reseeded.${_SolrCoreID}" \
        &> /dev/null
    fi
  fi
  ###
  ### Each leg reads the INI once, as it stands when the leg starts
  ### (_ctrl_ini_read), and tests that text: a leg can come minutes after the
  ### one before it (a CoreAdmin CREATE, a jetty9 restart).
  ###
  ### Support for solr_integration_module directive
  ###
  if _ctrl_ini_leg_ok && _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
    _leg1=YES
    _SOLR_MODULE="your_module_name_here"
    _SOLR_IM_PT=$(grep "solr_integration_module" <<< "${_iniTxt}" 2>&1)
    if [[ "${_SOLR_IM_PT}" =~ "solr_integration_module" ]]; then
      _DO_NOTHING=YES
    else
      # The teardown test below reads this placeholder, so the text gets it
      # too, as the file does.
      _ctrl_ini_add "${_DIR_CTRL_F}" \
        ";solr_integration_module = your_module_name_here" \
        && _iniTxt="${_iniTxt}"$'\n'";solr_integration_module = your_module_name_here"
    fi
    _ASOLR_T=$(grep "^solr_integration_module = apachesolr" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_ASOLR_T}" =~ "apachesolr" ]]; then
      _SOLR_MODULE="apachesolr"
    fi
    _SAPI_SOLR_T=$(grep "^solr_integration_module = search_api_solr" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SAPI_SOLR_T}" =~ "search_api_solr" ]]; then
      _SOLR_MODULE="search_api_solr"
    fi
    _SAPI_SOLR_U=$(grep "^solr_integration_module = search_api_solr7" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SAPI_SOLR_U}" =~ "search_api_solr7" ]]; then
      _SOLR_MODULE="search_api_solr7"
    fi
    _SAPI_SOLR_V=$(grep "^solr_integration_module = search_api_solr9" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SAPI_SOLR_V}" =~ "search_api_solr9" ]]; then
      _SOLR_MODULE="search_api_solr9"
    fi
    _SOLR_TEARDOWN=NO
    if [ "${_SOLR_MODULE}" = "apachesolr" ] && [ -e "/opt/solr4" ]; then
      _SOLR_BASE="/opt/solr4"
      _SOLR_VER=jetty9
    elif [ "${_SOLR_MODULE}" = "search_api_solr" ] && [ -e "/var/solr7/data" ]; then
      _SOLR_BASE="/var/solr7/data"
      _SOLR_VER=solr7
    elif [ "${_SOLR_MODULE}" = "search_api_solr7" ] && [ -e "/var/solr7/data" ]; then
      _SOLR_BASE="/var/solr7/data"
      _SOLR_VER=solr7
    elif [ "${_SOLR_MODULE}" = "search_api_solr9" ] && [ -e "/var/solr9/data" ]; then
      _SOLR_BASE="/var/solr9/data"
      _SOLR_VER=solr9
    else
      # Only an unset, commented out or invalid directive requests core
      # teardown; a valid module whose Solr base is not installed must
      # not delete existing cores. The eligibility has to be carried in
      # its own flag because _SOLR_VER is blanked right here.
      if [ "${_SOLR_MODULE}" = "your_module_name_here" ] \
        && _solr_teardown_intended "${_iniTxt}"; then
        _SOLR_TEARDOWN=YES
      fi
      _SOLR_MODULE=
      _SOLR_BASE=
      _SOLR_VER=
    fi
    _SOLR_DIR="${_SOLR_BASE}/${_SolrCoreID}"
    if [ "${_SOLR_MODULE}" = "search_api_solr" ] \
      || [ "${_SOLR_MODULE}" = "search_api_solr7" ] \
      || [ "${_SOLR_MODULE}" = "search_api_solr9" ] \
      || [ "${_SOLR_MODULE}" = "apachesolr" ]; then
      # A valid directive ends the reseed grace: the operator has spoken.
      [ -n "${_SolrCoreID}" ] \
        && _acct_in_real_dir "${_usEr}/.boa-ctrl" \
          rm -f -- "./solr-reseeded.${_SolrCoreID}" &> /dev/null
      # A core this same text protects is protected before the check, which
      # otherwise refreshes it once from a template or an upload before leg 2
      # writes the marker; a core the check creates is protected by
      # _add_solr, right after it is made.
      if grep -q "^solr_custom_config = YES" <<< "${_iniTxt}"; then
        _SLR_CM_CFG_L1=YES
        if [ -n "${_SOLR_VER}" ] && [ -d "${_SOLR_DIR}/conf" ]; then
          touch "${_SOLR_DIR}/conf/.protected.conf"
        fi
      fi
      [ -n "${_SOLR_VER}" ] && _check_solr "${_SOLR_MODULE}" "${_SOLR_DIR}" "${_SOLR_VER}"
    else
      if [ "${_SOLR_TEARDOWN}" = "YES" ]; then
        _SOLR_DIR_DEL="/opt/solr4/${_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr7/data/${_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr9/data/${_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/opt/solr4/${_Legacy_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr7/data/${_Legacy_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/opt/solr4/${_Old_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr7/data/${_Old_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr9/data/${_Old_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
      fi
    fi
  fi
  ###
  ### Support for solr_custom_config directive
  ###
  ### Legs 2 and 3 still add their placeholder line to this site's own INI
  ### whatever leg 1 found (only they add it, and the INI of a site with no
  ### Solr needs it as well), but touch the core only after leg 1 chose a
  ### valid one in this call.
  ###
  if _ctrl_ini_leg_ok && _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
    _SLR_CM_CFG_P=$(grep "solr_custom_config" <<< "${_iniTxt}" 2>&1)
    if [[ "${_SLR_CM_CFG_P}" =~ "solr_custom_config" ]]; then
      _DO_NOTHING=YES
    else
      _ctrl_ini_add "${_DIR_CTRL_F}" ";solr_custom_config = NO"
    fi
    if [ "${_leg1}" = "YES" ] && [ -n "${_SOLR_VER}" ]; then
      _SOLR_PROTECT_CTRL="${_SOLR_DIR}/conf/.protected.conf"
      _SLR_CM_CFG_T=$(grep "^solr_custom_config = YES" <<< "${_iniTxt}" 2>&1)
      if [[ "${_SLR_CM_CFG_T}" =~ "solr_custom_config = YES" ]]; then
        _SLR_CM_CFG_RT=YES
        if [ ! -e "${_SOLR_PROTECT_CTRL}" ]; then
          touch "${_SOLR_PROTECT_CTRL}"
        fi
        echo "Solr config for ${_SOLR_DIR} is protected"
      else
        if [ -e "${_SOLR_PROTECT_CTRL}" ]; then
          rm -f "${_SOLR_PROTECT_CTRL}"
        fi
      fi
    fi
  fi
  ###
  ### Support for solr_update_config directive
  ###
  ### _SOLR_PROTECT_CTRL is set only by leg 2 of this call, after a valid
  ### leg 1, so an update never runs on a protection state this call did
  ### not read.
  ###
  if _ctrl_ini_leg_ok && _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
    _SOLR_UP_CFG_PT=$(grep "solr_update_config" <<< "${_iniTxt}" 2>&1)
    if [[ "${_SOLR_UP_CFG_PT}" =~ "solr_update_config" ]]; then
      _DO_NOTHING=YES
    else
      _ctrl_ini_add "${_DIR_CTRL_F}" ";solr_update_config = NO"
    fi
    _SOLR_UP_CFG_TT=$(grep "^solr_update_config = YES" <<< "${_iniTxt}" 2>&1)
    if [[ "${_SOLR_UP_CFG_TT}" =~ "solr_update_config = YES" ]]; then
      if [ "${_leg1}" = "YES" ] \
        && [ -n "${_SOLR_VER}" ] \
        && [ -n "${_SOLR_PROTECT_CTRL}" ] \
        && [ "${_SLR_CM_CFG_RT}" = "NO" ] \
        && [ ! -e "${_SOLR_PROTECT_CTRL}" ]; then
        _update_solr "${_SOLR_MODULE}" "${_SOLR_DIR}" "${_SOLR_VER}" tpl
      fi
    fi
  fi
}

_proceed_solr() {
  if [ ! -z "${_Dan}" ] \
    && [ "${_Dan}" != "hostmaster" ]; then
    CoreID="${_Dan}.${_HM_U}"
    CoreHS=$(echo ${CoreID} \
      | openssl md5 \
      | awk '{ print $2}' \
      | tr -d "\n" 2>&1)
    #_SolrCoreID="${_HM_U}-${_Dan}-${CoreHS}"
    _Legacy_SolrCoreID="${_HM_U}.${_Dan}"
    _Old_SolrCoreID="solr.${_HM_U}.${_Dan}"
    _SolrCoreID="oct.${_HM_U}.${_Dan}"
    _setup_solr
  fi
}

_check_sites_list() {
  # config/ and .drush/ are oN's: the vhost list is taken and every vhost
  # and alias read only inside the real directory, bounded and never through
  # a link or a FIFO (_acct_in_real_dir, _acct_read_in).
  local _vhD="${_usEr}/config/server_master/nginx/vhost.d" _vhTxt _alTxt
  for _Site in `_acct_in_real_dir "${_vhD}" find . \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _Site="${_vhD}/${_Site#./}"
    _MOMENT=$(date +%y%m%d-%H%M%S)
    echo ${_MOMENT} Start Checking Site ${_Site}
    _Dom=$(echo ${_Site} | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    _vhTxt=$(_acct_read_in "${_vhD}" "${_Dom}")
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d/${_Dom}" ]; then
      _Plx=$(printf '%s\n' "${_vhTxt}" \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "${_Plx}" =~ "aegir/distro" ]]; then
        _Dan="hostmaster"
      else
        _Dan="${_Dom}"
      fi
    fi
    _STATUS_DISABLED=NO
    _STATUS_TEST=$(grep "Do not reveal Aegir front-end URL here" \
      <<< "${_vhTxt}" 2>&1)
    if [[ "${_STATUS_TEST}" =~ "Do not reveal Aegir front-end URL here" ]]; then
      _STATUS_DISABLED=YES
      echo "${_Dom} site is DISABLED"
    fi
    if [ -e "${_usEr}/.drush/${_Dan}.alias.drushrc.php" ] \
      && [ "${_STATUS_DISABLED}" = "NO" ]; then
      _alTxt=$(_acct_read_in "${_usEr}/.drush" "${_Dan}.alias.drushrc.php")
      _Dir=$(printf '%s\n' "${_alTxt}" \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _DIR_CTRL_F="${_Dir}/modules/boa_site_control.ini"
      _Plr=$(printf '%s\n' "${_alTxt}" \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _PLR_CTRL_F="${_Plr}/sites/all/modules/boa_platform_control.ini"
      if [ -n "${_Dir}" ] && ! _validate_safe_dir "${_Dir}"; then
        echo "SKIP: _Dir resolves outside allowed roots: ${_Dir}"
        continue
      fi
      if [ -n "${_Plr}" ] && ! _validate_safe_dir "${_Plr}"; then
        echo "SKIP: _Plr resolves outside allowed roots: ${_Plr}"
        continue
      fi
      # Grav and Textpattern sites carry no BOA control INI and no Solr
      # binding: never seed, read or act on
      # one for them. A core an earlier pass made for such a site is left to
      # the orphan sweep, which no longer counts its INI either.
      if [ -n "${_Plr}" ] \
        && _is_foreign_cms_root "$(realpath -e -- "${_Plr}" 2>/dev/null)"; then
        _acct_in_real_dir "${_usEr}/.boa-ctrl" \
          rm -f -- "./solr-reseeded.oct.${_HM_U}.${_Dan}" &> /dev/null
        echo "SKIP: ${_Dom} is a Grav or Textpattern site (no control INI)"
        continue
      fi
      # The checks above validate the alias-derived roots, not the modules
      # dir the control INIs actually live in. That component sits in the
      # tenant-writable setgid tree, and a symlink planted there redirects
      # every INI leg further down, so gate it here too. Absent is allowed;
      # a symlink, or a dir resolving outside the account root, skips the
      # iteration.
      if [ -n "${_Dir}" ] && ! _validate_ctrl_dir "${_Dir}/modules"; then
        echo "SKIP: not a plain dir under ${_usEr}: ${_Dir}/modules"
        continue
      fi
      if [ -n "${_Plr}" ] \
        && ! _validate_ctrl_dir "${_Plr}/sites/all/modules"; then
        echo "SKIP: not a plain dir under ${_usEr}: ${_Plr}/sites/all/modules"
        continue
      fi
      _desymlink_planted \
        "${_DIR_CTRL_F}" \
        "${_Dir}/modules/default.boa_site_control.ini" \
        "${_PLR_CTRL_F}" \
        "${_Plr}/sites/all/modules/default.boa_platform_control.ini"
      _proceed_solr
    fi
  done
}

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
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  : "${_CPU_TASK_RATIO:=3.1}"
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

# A core's solrcore.properties ($1) put in BOA's own form for Solr $2
# (solr7 or solr9): unless the file already names that Solr (and on Solr 9
# its port), the install and contrib dir lines, and on Solr 9 the
# replication URL, give way to this server's own values. The one rewrite
# for every core's file, the Drupal 7 template and a staged upload, so a
# file put in this form is never rewritten again. Status 0 when the file
# was changed, 1 when it was already in that form or is not there.
_solr_props_boa_form() {
  local _file="${1}"
  [ -f "${_file}" ] || return 1
  case "${2}" in
    solr9)
      if grep -q "solr9" "${_file}" 2> /dev/null \
        && grep -q "9099" "${_file}" 2> /dev/null; then
        return 1
      fi
      sed -i "s/^solr\.replication\.masterUrl.*//g" "${_file}"
      sed -i "s/^solr\.install\.dir.*//g" "${_file}"
      sed -i "s/^solr\.contrib\.dir.*//g" "${_file}"
      echo "solr.replication.masterUrl=http://localhost:9099" >> "${_file}"
      echo "solr.install.dir=/opt/solr9" >> "${_file}"
      ;;
    solr7)
      grep -q "solr7" "${_file}" 2> /dev/null && return 1
      sed -i "s/^solr\.install\.dir.*//g" "${_file}"
      sed -i "s/^solr\.contrib\.dir.*//g" "${_file}"
      echo "solr.install.dir=/opt/solr7" >> "${_file}"
      ;;
    *)
      return 1
      ;;
  esac
  sed -i "/^$/d" "${_file}"
  return 0
}

_fix_solr9_cnf() {
  if [ -x "/etc/init.d/solr9" ] && [ -e "/var/solr9/logs" ]; then
    _IF_RESTART_SOLR=NO
    for _pRp in `find /var/solr9/data/oct.*/conf/solrcore.properties -maxdepth 1 | sort`; do
      if _solr_props_boa_form "${_pRp}" solr9; then
        echo "Fixed ${_pRp}"
        _IF_RESTART_SOLR=YES
      fi
    done
    rStart="/var/solr9/logs/.restarted_new_fix_solr9_cnf.txt"
    if [ "${_IF_RESTART_SOLR}" = "YES" ] \
      || [ ! -e "${rStart}" ]; then
      echo "Restarting Solr 9..."
      service solr9 restart
      wait
      touch ${rStart}
    fi
  fi
}

_fix_solr7_core() {
  if _solr_props_boa_form "${1}" solr7; then
    echo "Fixed ${1}"
    _IF_RESTART_SOLR=YES
  fi
}

_fix_solr7_cnf() {
  if [ -x "/etc/init.d/solr7" ] && [ -e "/var/solr7/logs" ]; then
    _IF_RESTART_SOLR=NO
    for _pRp in `find /var/solr7/data/oct.*/conf/solrcore.properties -maxdepth 1 | sort`; do
      _fix_solr7_core "${_pRp}"
    done
    _solr7_paths=(
      "/var/xdrago/conf/solr/search_api_solr/solr7_drupal7/solrcore.properties"
      "/data/conf/solr/search_api_solr/solr7_drupal7/solrcore.properties"
    )
    for path in "${_solr7_paths[@]}"; do
      _fix_solr7_core "${path}"
    done
    rStart="/var/solr7/logs/.restarted_new_fix_solr7_cnf.txt"
    if [ "${_IF_RESTART_SOLR}" = "YES" ] \
      || [ ! -e "${rStart}" ]; then
      echo "Restarting Solr 7..."
      service solr7 restart
      wait
      touch ${rStart}
    fi
  fi
}

_sync_solr_config() {
  local _rel_dir="$1"
  local _base_dir="/var/xdrago/conf/solr/${_rel_dir}"

  if [ -d "${_base_dir}" ]; then
    local _baseCpy="${_base_dir}/schema.xml"
    local _liveCpy="/data/conf/solr/${_rel_dir}/schema.xml"

    _check_config_diff "${_baseCpy}" "${_liveCpy}"

    if [ ! -e "/data/conf/solr/${_rel_dir}/solrconfig.xml" ] \
      || [ ! -e "/data/conf/solr/.ctrl.${_tRee}.${_xSrl}.pid" ] \
      || [ ! -z "${_slrCnfUpdate}" ]; then
      rm -rf /data/conf/solr
      cp -af /var/xdrago/conf/solr /data/conf/
      rm -f /data/conf/solr/.ctrl*
      touch /data/conf/solr/.ctrl.${_tRee}.${_xSrl}.pid
    fi
  fi
}

###
### Orphan core cleanup
###
### Three-tier classification for every oct.* / solr.* core found on disk:
###
###   TIER 1 — No vhost at all, OR vhost exists but no Ægir drush alias:
###            Core is unknown to the provisioning layer. Apply short
###            staleness threshold (_ORPHAN_STALE_DAYS, default 14d).
###
###   TIER 2 — Vhost exists AND Ægir alias exists (site is known but may be
###            an abandoned clone, old staging env, renamed domain, etc.):
###            Apply long staleness threshold (_ORPHAN_VHOST_STALE_DAYS,
###            default 60d) on data/index/ mtime only — giving cloned/renamed
###            sites plenty of time before their core is retired.
###
###   TIER 3 — Protected by conf/.protected.conf: never touched regardless.
###
### Staleness is measured on data/index/ (Lucene commit mtime — the cleanest
### signal of real indexing activity). data/ itself is intentionally NOT used
### as the primary signal because Solr keeps it perpetually fresh via tlog,
### write.lock and other bookkeeping writes even on idle cores.
###
### Qualifying cores are NOT deleted — they are unloaded from Solr's registry
### and moved to /var/backups/solrN/<timestamp>-<core>/ for easy recovery.
###
_ORPHAN_STALE_DAYS=14       # tier 1: no vhost / no alias
_ORPHAN_VHOST_STALE_DAYS=60 # tier 2: vhost+alias present but index inactive

_build_active_core_set() {
  # Populates three global associative arrays:
  #
  #   _CORES_WITH_VHOST       — core has a matching enabled nginx vhost
  #   _CORES_WITH_ALIAS       — core also has a matching Ægir drush alias
  #   _CORES_WITH_SOLR_MODULE — site has solr_integration_module explicitly
  #                             set in boa_site_control.ini — these are
  #                             actively managed and must never be archived
  #                             based on index age alone, even if stale
  #
  # All three historical name formats (oct.*, solr.*, <user>.<domain>) are
  # registered for each site so transitional/renamed cores are never wrongly
  # retired.
  declare -gA _CORES_WITH_VHOST=()
  declare -gA _CORES_WITH_ALIAS=()
  declare -gA _CORES_WITH_SOLR_MODULE=()

  for _usEr in $(find /data/disk/ -maxdepth 1 -mindepth 1 | sort); do
    [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] || continue
    local _HM_U_TMP _vhDTmp
    _HM_U_TMP=$(echo "${_usEr}" | cut -d'/' -f4 | awk '{ print $1}')
    # The vhosts, aliases and site INIs are listed and read as
    # _check_sites_list reads them: never through a link or a FIFO.
    _vhDTmp="${_usEr}/config/server_master/nginx/vhost.d"

    for _Site in $(_acct_in_real_dir "${_vhDTmp}" find . \
        -maxdepth 1 -mindepth 1 -type f | sort); do
      local _DomTmp _STATUS_T _PlxTmp _vhTxtTmp _alTxtTmp
      _Site="${_vhDTmp}/${_Site#./}"
      _DomTmp=$(echo "${_Site}" | cut -d'/' -f9 | awk '{ print $1}')
      [ -z "${_DomTmp}" ] && continue
      _vhTxtTmp=$(_acct_read_in "${_vhDTmp}" "${_DomTmp}")

      # Skip disabled/parked sites
      _STATUS_T=$(grep "Do not reveal Aegir front-end URL here" <<< "${_vhTxtTmp}" 2>&1)
      [[ "${_STATUS_T}" =~ "Do not reveal Aegir front-end URL here" ]] && continue

      # Skip hostmaster vhosts
      _PlxTmp=$(printf '%s\n' "${_vhTxtTmp}" | grep "root " | cut -d: -f2 | awk '{ print $2}' | sed "s/[\;]//g" 2>&1)
      [[ "${_PlxTmp}" =~ "aegir/distro" ]] && continue

      # Register vhost presence for all three name formats
      _CORES_WITH_VHOST["oct.${_HM_U_TMP}.${_DomTmp}"]=1
      _CORES_WITH_VHOST["solr.${_HM_U_TMP}.${_DomTmp}"]=1
      _CORES_WITH_VHOST["${_HM_U_TMP}.${_DomTmp}"]=1

      # Check for Ægir drush alias
      local _aliasFile="${_usEr}/.drush/${_DomTmp}.alias.drushrc.php"
      if [ -f "${_aliasFile}" ]; then
        _CORES_WITH_ALIAS["oct.${_HM_U_TMP}.${_DomTmp}"]=1
        _CORES_WITH_ALIAS["solr.${_HM_U_TMP}.${_DomTmp}"]=1
        _CORES_WITH_ALIAS["${_HM_U_TMP}.${_DomTmp}"]=1

        # Check for explicit solr_integration_module in boa_site_control.ini.
        # A site with this set is actively managed by _check_sites_list and
        # must not be archived based on index age — _add_solr will recreate
        # the core empty if we archive it, losing the index permanently.
        local _sitePath _rootPath
        _alTxtTmp=$(_acct_read_in "${_usEr}/.drush" "${_DomTmp}.alias.drushrc.php")
        _sitePath=$(printf '%s\n' "${_alTxtTmp}" | grep "site_path'" \
          | cut -d: -f2 | awk '{print $3}' | sed "s/[\,']//g" 2>/dev/null)
        _rootPath=$(printf '%s\n' "${_alTxtTmp}" | grep "'root' =>" \
          | cut -d: -f2 | awk '{print $3}' | sed "s/[\,']//g" 2>/dev/null)
        # A Grav or Textpattern site has no Solr binding for _check_sites_list
        # to manage (it skips them), so an INI a tenant edited there must not
        # keep a leftover core out of the orphan sweep.
        if [ -n "${_sitePath}" ] && ! _is_foreign_cms_root "${_rootPath}"; then
          local _ctrlFile="${_sitePath}/modules/boa_site_control.ini"
          if [ -f "${_ctrlFile}" ]; then
            local _solrMod
            _solrMod=$(_site_in_resolved_dir "${_ctrlFile%/*}" \
              _acct_read_plain_here "${_ctrlFile##*/}" \
              | grep "^solr_integration_module" 2>/dev/null)
            if [ -n "${_solrMod}" ]; then
              _CORES_WITH_SOLR_MODULE["oct.${_HM_U_TMP}.${_DomTmp}"]=1
              _CORES_WITH_SOLR_MODULE["solr.${_HM_U_TMP}.${_DomTmp}"]=1
              _CORES_WITH_SOLR_MODULE["${_HM_U_TMP}.${_DomTmp}"]=1
            fi
          fi
        fi
      fi
    done
  done
}

_core_is_stale() {
  # Returns 0 (stale/archive-eligible) or 1 (fresh/keep).
  # ${1} = core path
  # ${2} = staleness threshold in days
  #
  # Primary signal: data/index/ mtime — updated only on Lucene segment commits.
  # Fallback:       data/ mtime — catches tlog-only replicas mid-reindex.
  # A core with no data/ at all was never indexed → immediately stale.
  local _corePath="${1}"
  local _threshold="${2}"
  local _dataDir="${_corePath}/data"
  local _indexDir="${_corePath}/data/index"

  [ -d "${_dataDir}" ] || return 0  # no data dir → stale

  if [ -d "${_indexDir}" ]; then
    local _indexFresh
    _indexFresh=$(find "${_indexDir}" -maxdepth 0 \
      -mtime "-${_threshold}" 2>/dev/null)
    [ -n "${_indexFresh}" ] && return 1  # index recently committed → keep
  fi

  local _dataFresh
  _dataFresh=$(find "${_dataDir}" -maxdepth 0 \
    -mtime "-${_threshold}" 2>/dev/null)
  [ -n "${_dataFresh}" ] && return 1  # data dir recently touched → keep

  return 0  # both older than threshold → stale
}

_core_last_activity_days() {
  # Echoes age in days of the most recent of data/index/ and data/ mtimes.
  # Used only for human-readable log output.
  local _corePath="${1}"
  local _now _iMtime _dMtime _newest
  _now=$(date +%s)
  _iMtime=0
  _dMtime=0
  [ -d "${_corePath}/data/index" ] && \
    _iMtime=$(stat -c %Y "${_corePath}/data/index" 2>/dev/null || echo 0)
  [ -d "${_corePath}/data" ] && \
    _dMtime=$(stat -c %Y "${_corePath}/data" 2>/dev/null || echo 0)
  _newest=$(( _iMtime >= _dMtime ? _iMtime : _dMtime ))
  echo $(( ( _now - _newest ) / 86400 ))
}

_archive_orphan_core() {
  # Unloads the core from Solr's registry (without deleting any files) then
  # moves the directory to the backup location for easy manual recovery.
  #
  # ${1} = port  ${2} = backup base dir  ${3} = core path  ${4} = timestamp
  #
  # RECOVERY — to restore an archived core:
  #
  #   port=9077  # or 9099 for solr9
  #   core="oct.o1.example.com"
  #   bkp="/var/backups/solr7/20260418-222802-${core}"   # adjust timestamp
  #   dest="/var/solr7/data/${core}"                     # or solr9
  #
  #   mv "${bkp}" "${dest}"
  #   chown -R solr7:solr7 "${dest}"                     # or solr9:solr9
  #   curl "http://127.0.0.1:${port}/solr/admin/cores?action=CREATE&name=${core}&instanceDir=${dest}"
  #
  # NOTE: use CREATE not RELOAD — RELOAD only works for already-registered
  # cores. CREATE re-registers the existing directory without touching files.
  local _port="${1}" _bkpBase="${2}" _corePath="${3}" _ts="${4}"
  local _coreName
  _coreName=$(basename "${_corePath}")

  # Unload via admin API — deleteIndex/DataDir/InstanceDir all false so Solr
  # releases its handle but leaves every file intact for the mv below
  curl -s --max-time 15 \
    "http://127.0.0.1:${_port}/solr/admin/cores?action=UNLOAD&core=${_coreName}&deleteIndex=false&deleteDataDir=false&deleteInstanceDir=false" \
    > /dev/null 2>&1 || true
  wait

  local _bkpDest="${_bkpBase}/${_ts}-${_coreName}"
  mkdir -p "${_bkpBase}"
  if mv "${_corePath}" "${_bkpDest}"; then
    echo "ORPHAN-ARCHIVED: ${_coreName} → ${_bkpDest}"
  else
    echo "ORPHAN-ERROR: mv failed for ${_corePath} — skipping"
  fi
}

_purge_orphan_cores() {
  # ${1} = solr binary   ${2} = solr unix user  ${3} = port
  # ${4} = data dir      ${5} = backup base dir
  local _bin="${1}" _usr="${2}" _port="${3}" _datadir="${4}" _bkpBase="${5}"

  [ -x "${_bin}" ]     || return
  [ -d "${_datadir}" ] || return

  local _archived=0 _protected=0 _fresh=0 _skipped=0 _ts
  _ts=$(date +%Y%m%d-%H%M%S)

  for _corePath in $(find "${_datadir}" -maxdepth 1 -mindepth 1 -type d | sort); do
    local _coreName _dot_count
    _coreName=$(basename "${_corePath}")

    # Only process cores matching our naming convention
    if [[ ! "${_coreName}" =~ ^(oct|solr)\. ]]; then
      _dot_count=$(echo "${_coreName}" | tr -cd '.' | wc -c)
      [ "${_dot_count}" -lt 1 ] && continue
    fi

    # Protection sentinel always wins — no logging spam for these
    if [ -e "${_corePath}/conf/.protected.conf" ]; then
      (( _protected++ ))
      continue
    fi

    local _hasVhost _hasAlias _threshold _tier _age
    _hasVhost=0
    _hasAlias=0
    [ -n "${_CORES_WITH_VHOST[${_coreName}]+x}" ] && _hasVhost=1
    [ -n "${_CORES_WITH_ALIAS[${_coreName}]+x}" ] && _hasAlias=1

    if [ "${_hasVhost}" -eq 1 ] && [ "${_hasAlias}" -eq 1 ]; then
      # Extra gate: if site has solr_integration_module explicitly configured,
      # _check_sites_list actively manages this core and will recreate it
      # empty if we archive it.  Protect it unconditionally.
      if [ -n "${_CORES_WITH_SOLR_MODULE[${_coreName}]+x}" ]; then
        echo "ORPHAN-SKIP: ${_coreName} — solr_integration_module set, actively managed"
        (( _protected++ ))
        continue
      fi
      # Tier 2: properly provisioned site — use the long threshold
      _threshold="${_ORPHAN_VHOST_STALE_DAYS}"
      _tier="tier2(vhost+alias)"
    else
      # Tier 1: no vhost, or vhost with no Ægir alias (nginx leftover / dead clone)
      _threshold="${_ORPHAN_STALE_DAYS}"
      _tier="tier1(no-vhost-or-alias)"
    fi

    if ! _core_is_stale "${_corePath}" "${_threshold}"; then
      _age=$(_core_last_activity_days "${_corePath}")
      echo "ORPHAN-FRESH: ${_coreName} [${_tier}] index ${_age}d ago (threshold ${_threshold}d) — keeping"
      (( _fresh++ ))
      continue
    fi

    _age=$(_core_last_activity_days "${_corePath}")
    echo "ORPHAN-CANDIDATE: ${_coreName} [${_tier}] index ${_age}d ago — archiving"
    _archive_orphan_core "${_port}" "${_bkpBase}" "${_corePath}" "${_ts}"
    (( _archived++ ))
  done

  echo "Orphan cleanup port=${_port}: archived=${_archived} fresh(kept)=${_fresh} protected=${_protected}"
}

_cleanup_orphan_cores() {
  # Guard: never run during a BOA install or upgrade; re-evaluate here --
  # _start_up loops every account and can outlive the top-level check, so
  # an install that started mid-run must still hold this destructive step
  _is_protected_run
  [ "${_protectedRun}" = "TRUE" ] && return

  # Throttle: run at most once every 6 hours.
  # The sentinel file is touched on each successful run; we skip if it is
  # younger than 6 hours (360 minutes — find -mmin returns a result = fresh).
  local _sentinel="/var/backups/solr/.orphan_cleanup_last_run.pid"
  mkdir -p /var/backups/solr
  if [ -e "${_sentinel}" ]; then
    local _sentinel_fresh
    _sentinel_fresh=$(find "${_sentinel}" -mmin "-360" 2>/dev/null)
    if [ -n "${_sentinel_fresh}" ]; then
      echo "Orphan cleanup skipped -- last run less than 6 hours ago (${_sentinel})"
      return
    fi
  fi

  echo "=== Orphan core cleanup start ==="

  _build_active_core_set
  echo "Active cores with vhost: ${#_CORES_WITH_VHOST[@]}  with alias: ${#_CORES_WITH_ALIAS[@]}  with solr module: ${#_CORES_WITH_SOLR_MODULE[@]}"

  if [ -x "/etc/init.d/solr7" ] && [ -d "/var/solr7/data" ]; then
    mkdir -p /var/backups/solr7
    _purge_orphan_cores \
      "/opt/solr7/bin/solr" "solr7" "9077" "/var/solr7/data" "/var/backups/solr7"
  fi

  if [ -x "/etc/init.d/solr9" ] && [ -d "/var/solr9/data" ]; then
    mkdir -p /var/backups/solr9
    _purge_orphan_cores \
      "/opt/solr9/bin/solr" "solr9" "9099" "/var/solr9/data" "/var/backups/solr9"
  fi

  touch "${_sentinel}"
  echo "=== Orphan core cleanup end ==="
}

_check_solr_core_health() {
  # Queries the Solr admin STATUS API for every registered core and logs
  # anomalies that could indicate memory pressure or a problematic core:
  #
  #   - Cores reporting initFailures (failed to load)
  #   - High segment count (>50) -- many small unmerged segments hold open
  #     file handles and contribute to Metaspace pressure via per-segment
  #     FieldCache entries
  #   - High deleted doc ratio (>20% of maxDoc) -- unmerged deletes inflate
  #     heap and prevent segment GC
  #   - Large index size (>500MB) -- informational
  #
  # Read-only diagnostic -- no changes are made.
  # ${1} = port   e.g. 9077 or 9099
  # ${2} = label  e.g. solr7 or solr9
  local _port="${1}" _label="${2}"
  local _api="http://127.0.0.1:${_port}/solr/admin/cores?action=STATUS&wt=json"

  if ! command -v python3 &>/dev/null; then
    echo "HEALTH-SKIP: python3 not available, skipping ${_label} core health check"
    return
  fi

  local _json
  _json=$(curl -s --max-time 15 "${_api}" 2>/dev/null)
  if [ -z "${_json}" ]; then
    echo "HEALTH-ERROR: no response from ${_label} on port ${_port}"
    return
  fi

  local _tmpjson
  _tmpjson=$(mktemp /tmp/solr_health_XXXXXX.json)
  echo "${_json}" > "${_tmpjson}"

  echo "=== Core health check ${_label} port=${_port} ==="

  python3 - "${_tmpjson}" "/var/${_label}/data" "${_label}" <<'PYEOF'
import json, os, sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception as e:
    print(f"HEALTH-ERROR: JSON parse failed: {e}")
    sys.exit(0)

init_failures = data.get("initFailures", {})
if init_failures:
    for core, err in init_failures.items():
        print(f"HEALTH-INIT-FAIL: {core} -- {err}")

cores = data.get("status", {})

# The mirror shape of a core Solr stopped listing: the directory carries
# core.properties (an archive taken while Solr was down, a tree copied in
# from elsewhere, a recovery that stopped before the CREATE) and Solr does
# not know it. The reconciliation pass cannot CREATE into it (Solr refuses
# and deletes the file), so say it here, once per pass, with the way out.
datadir, label = sys.argv[2], sys.argv[3]
known = set(cores) | set(init_failures)
if os.path.isdir(datadir):
    for name in sorted(os.listdir(datadir)):
        if name in known:
            continue
        if os.path.isfile(os.path.join(datadir, name, "core.properties")):
            print(f"HEALTH-WARN: {name} has core.properties under {datadir} but {label} "
                  f"does not list it -- move that file aside and a bound site's core is "
                  f"re-registered on the next pass, or restart {label}")

if not cores:
    print("HEALTH-INFO: no cores registered")
    sys.exit(0)

print(f"HEALTH-INFO: {len(cores)} cores registered")

for name, info in sorted(cores.items()):
    index    = info.get("index", {})
    num_docs = index.get("numDocs", 0)
    max_doc  = index.get("maxDoc", 0)
    deleted  = max_doc - num_docs
    segments = index.get("segmentCount", 0)
    size_mb  = index.get("sizeInBytes", 0) / 1048576

    issues = []

    if segments > 50:
        issues.append(f"high segment count={segments}")

    if max_doc > 0:
        del_pct = (deleted / max_doc) * 100
        if del_pct > 20:
            issues.append(f"deleted={deleted}/{max_doc} ({del_pct:.0f}%)")

    if size_mb > 500:
        issues.append(f"large index={size_mb:.0f}MB")

    if issues:
        print(f"HEALTH-WARN: {name}  docs={num_docs}  segs={segments}  "
              f"size={size_mb:.1f}MB  issues: {', '.join(issues)}")
PYEOF

  rm -f "${_tmpjson}"
  echo "=== Core health check end ==="
}


_optimize_solr_cores() {
  # Runs expungeDeletes on every registered core where the deleted doc ratio
  # exceeds _OPTIMIZE_DEL_PCT_THRESHOLD, and a full optimize (maxSegments=1)
  # on cores where the ratio exceeds _OPTIMIZE_FULL_THRESHOLD.
  #
  # Design decisions:
  #
  #   expungeDeletes vs full optimize:
  #     expungeDeletes merges only segments whose deleted doc fraction exceeds
  #     the merge policy threshold. It is cheap, non-blocking for queries, and
  #     safe to run frequently. Full optimize (maxSegments=1) merges everything
  #     into a single segment — expensive on large indexes but reclaims the
  #     most space and gives the best query performance. We use a higher
  #     threshold to trigger the full optimize and only do it when genuinely
  #     needed.
  #
  #   waitFlush=false:
  #     Both calls return immediately while the merge continues in the
  #     background. This keeps the script runtime bounded regardless of index
  #     size. The next health check run will reflect the improved state.
  #
  #   Protected cores (conf/.protected.conf):
  #     These have custom solrconfig.xml and may have their own merge policy
  #     already tuned (e.g. TieredMergePolicy with deletesPctAllowed=20).
  #     We still run expungeDeletes on them if the ratio is very high, but
  #     skip the full optimize to avoid interfering with their tuning.
  #
  #   Throttle:
  #     Sentinel file at /var/backups/solr/.optimize_last_run.pid limits
  #     execution to once every _OPTIMIZE_INTERVAL_HOURS hours (default 12).
  #     This keeps the function rate-limited even though _start_up runs
  #     every 4 minutes.
  #
  # ${1} = port   e.g. 9077 or 9099
  # ${2} = label  e.g. solr7 or solr9
  # ${3} = data dir  e.g. /var/solr7/data
  local _port="${1}" _label="${2}" _datadir="${3}"

  [ -d "${_datadir}" ] || return

  if ! command -v python3 &>/dev/null; then
    echo "OPTIMIZE-SKIP: python3 not available"
    return
  fi

  local _api="http://127.0.0.1:${_port}/solr/admin/cores?action=STATUS&wt=json"
  local _json
  _json=$(curl -s --max-time 15 "${_api}" 2>/dev/null)
  if [ -z "${_json}" ]; then
    echo "OPTIMIZE-ERROR: no response from ${_label} on port ${_port}"
    return
  fi

  local _tmpjson
  _tmpjson=$(mktemp /tmp/solr_optimize_XXXXXX.json)
  echo "${_json}" > "${_tmpjson}"

  echo "=== Index optimize check ${_label} port=${_port} ==="

  # Extract core names and their deleted doc ratios from the STATUS response,
  # then decide per-core action. Output format: <action> <corename>
  # where action is: skip | expunge | optimize
  local _decisions
  _decisions=$(python3 - "${_tmpjson}" \
    "${_OPTIMIZE_DEL_PCT_THRESHOLD}" "${_OPTIMIZE_FULL_THRESHOLD}" <<'PYEOF'
import json, sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception as e:
    print(f"# parse error: {e}", file=sys.stderr)
    sys.exit(0)

expunge_threshold = float(sys.argv[2])
full_threshold    = float(sys.argv[3])

cores = data.get("status", {})
for name, info in sorted(cores.items()):
    index    = info.get("index", {})
    num_docs = index.get("numDocs", 0)
    max_doc  = index.get("maxDoc", 0)
    deleted  = max_doc - num_docs
    del_pct  = (deleted / max_doc * 100) if max_doc > 0 else 0
    size_mb  = index.get("sizeInBytes", 0) / 1048576

    if del_pct >= full_threshold:
        print(f"optimize {name} {del_pct:.1f} {size_mb:.0f}")
    elif del_pct >= expunge_threshold:
        print(f"expunge {name} {del_pct:.1f} {size_mb:.0f}")
    else:
        print(f"skip {name} {del_pct:.1f} {size_mb:.0f}")
PYEOF
)

  rm -f "${_tmpjson}"

  local _action _coreName _delPct _sizeMb _isProtected
  while read -r _action _coreName _delPct _sizeMb; do
    [ -z "${_coreName}" ] && continue

    # Check protection sentinel
    _isProtected=0
    [ -e "${_datadir}/${_coreName}/conf/.protected.conf" ] && _isProtected=1

    case "${_action}" in
      skip)
        echo "OPTIMIZE-OK: ${_coreName} deleted=${_delPct}% — no action needed"
        ;;
      expunge)
        echo "OPTIMIZE-EXPUNGE: ${_coreName} deleted=${_delPct}% size=${_sizeMb}MB — running expungeDeletes"
        curl -s --max-time 30 \
          "http://127.0.0.1:${_port}/solr/${_coreName}/update?expungeDeletes=true&waitFlush=false" \
          > /dev/null 2>&1 || true
        ;;
      optimize)
        if [ "${_isProtected}" -eq 1 ]; then
          # Protected core: TieredMergePolicy may already handle this.
          # Run expungeDeletes only — do not force a full merge that could
          # interfere with a custom merge policy tuned for this workload.
          echo "OPTIMIZE-EXPUNGE: ${_coreName} deleted=${_delPct}% size=${_sizeMb}MB (protected) — expungeDeletes only"
          curl -s --max-time 30 \
            "http://127.0.0.1:${_port}/solr/${_coreName}/update?expungeDeletes=true&waitFlush=false" \
            > /dev/null 2>&1 || true
        else
          echo "OPTIMIZE-FULL: ${_coreName} deleted=${_delPct}% size=${_sizeMb}MB — running full optimize (background)"
          curl -s --max-time 30 \
            "http://127.0.0.1:${_port}/solr/${_coreName}/update?optimize=true&maxSegments=1&waitFlush=false" \
            > /dev/null 2>&1 || true
        fi
        ;;
    esac
  done <<< "${_decisions}"

  echo "=== Index optimize check end ==="
}

_run_optimize_if_due() {
  # Throttle wrapper for _optimize_solr_cores.
  # Runs at most once every _OPTIMIZE_INTERVAL_HOURS hours using a sentinel
  # file, then calls per-instance optimize checks.
  # Re-evaluated: _start_up can outlive the top-level protection check
  _is_protected_run
  [ "${_protectedRun}" = "TRUE" ] && return

  local _sentinel="/var/backups/solr/.optimize_last_run.pid"
  mkdir -p /var/backups/solr

  if [ -e "${_sentinel}" ]; then
    local _sentinelFresh
    _sentinelFresh=$(find "${_sentinel}" \
      -mmin "-$(( _OPTIMIZE_INTERVAL_HOURS * 60 ))" 2>/dev/null)
    if [ -n "${_sentinelFresh}" ]; then
      echo "Index optimize skipped — last run less than ${_OPTIMIZE_INTERVAL_HOURS}h ago"
      return
    fi
  fi

  echo "=== Index optimize start (interval=${_OPTIMIZE_INTERVAL_HOURS}h expunge>=${_OPTIMIZE_DEL_PCT_THRESHOLD}% full>=${_OPTIMIZE_FULL_THRESHOLD}%) ==="

  if [ -x "/etc/init.d/solr7" ] && [ -d "/var/solr7/data" ]; then
    _optimize_solr_cores "9077" "solr7" "/var/solr7/data"
  fi

  if [ -x "/etc/init.d/solr9" ] && [ -d "/var/solr9/data" ]; then
    _optimize_solr_cores "9099" "solr9" "/var/solr9/data"
  fi

  touch "${_sentinel}"
  echo "=== Index optimize end ==="
}

# Thresholds and interval — tune here without touching function logic.
#
# _OPTIMIZE_DEL_PCT_THRESHOLD: deleted doc % at which expungeDeletes fires.
#   Lucene's default merge policy tolerates ~10% before merging naturally.
#   20% is a safe threshold that catches accumulation without over-merging.
#
# _OPTIMIZE_FULL_THRESHOLD: deleted doc % at which a full optimize fires.
#   Only triggered on genuinely problematic indexes. 30% chosen because at
#   this level merge policy is clearly not keeping up with write rate.
#
# _OPTIMIZE_INTERVAL_HOURS: minimum hours between optimize runs.
#   12h means at most 2 runs per day regardless of how often the script
#   is invoked. Set to 6 for more aggressive maintenance.
_OPTIMIZE_DEL_PCT_THRESHOLD=20
_OPTIMIZE_FULL_THRESHOLD=30
_OPTIMIZE_INTERVAL_HOURS=12

_start_up() {
  _REREGISTER_DONE=0
  _fix_solr9_cnf
  _fix_solr7_cnf

  _solr_cnf_dirs=(
    "search_api_solr/solr7_drupal7"
    "apachesolr/solr4_drupal6"
    "apachesolr/solr4_drupal7"
  )

  for dir in "${_solr_cnf_dirs[@]}"; do
    _sync_solr_config "$dir"
  done

  for _usEr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    _count_cpu
    _load_control
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/CANCELLED" ]; then
      if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
        _HM_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        # Group owning this account's tree, re-derived for every account in
        # the loop so nothing leaks from the previous iteration.
        _HM_G=$(_acct_group "${_HM_U}")
        _THIS_HM_SITE=$(_acct_read_in "${_usEr}/.drush" \
          hostmaster.alias.drushrc.php \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "User ${_usEr}"
        ### The account home is owned by oN, the backend uid site-local Drush
        ### and the account cron run as, so a planted log symlink would
        ### redirect this root mkdir: made only inside the real log/.
        _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null
        # shellcheck disable=SC1091
        [ -e "/root/.${_HM_U}.octopus.cnf" ] && source /root/.${_HM_U}.octopus.cnf
        _check_sites_list
      fi
    fi
  done

  # Orphan cleanup runs AFTER _check_sites_list so that any core legitimately
  # recreated by _add_solr in this same run is already on disk and registered
  # before we evaluate what qualifies as an orphan. Running before
  # _check_sites_list caused a race where a managed core with a stale index
  # was archived and then immediately recreated empty by _add_solr.
  _cleanup_orphan_cores
  [ -x "/etc/init.d/solr7" ] && _check_solr_core_health "9077" "solr7"
  [ -x "/etc/init.d/solr9" ] && _check_solr_core_health "9099" "solr9"
  _run_optimize_if_due
}

_is_protected_run() {
  _protectedRun=FALSE
  _optBin="/opt/local/bin"
  _boaBins="autoinit automini barracuda boa octopus"
  for _cbn in ${_boaBins}; do
    if [ -e "${_optBin}/${_cbn}" ]; then
      # Anchored for every member, not just "boa": a bare path substring
      # matches any command line that merely MENTIONS the wrapper -- an
      # editor, a checksum, an operator's ssh probe -- and phantom-holds
      # this guard. Same form clear.sh/runner.sh/owl.sh/java.sh use.
      _cPat="^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/${_cbn}( |$)"
      # Bare "boa" would match an hours-long remote install driven
      # from this box over ssh (and every boa-info probe); anchor it
      # to the LOCAL install form, as clear.sh/runner.sh already do
      [ "${_cbn}" = "boa" ] && _cPat="^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-"
      _CNT=$(pgrep -fc "${_cPat}")
      if (( _CNT > 0 )); then
        echo "The ${_cbn} is running!"
        _protectedRun=TRUE
      fi
    fi
  done
  # The chained install's legs run as "bash /var/backups/*.sh.txt", not as
  # the wrapper binaries swept above -- match them too
  if pgrep -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1; then
    _protectedRun=TRUE
  fi
  [ -e "/run/octopus_install_run.pid" ] && _protectedRun=TRUE
  [ -e "/run/boa_run.pid" ] && _protectedRun=TRUE
  [ -e "/run/boa_wait.pid" ] && _protectedRun=TRUE
}
_manage_single_lock() {
  # The pass now carries a write that is not idempotent (a CoreAdmin
  # CREATE: a second one for the same core is refused and takes the first
  # one's core.properties with it), and the likeliest overlap is an
  # operator running this script by hand while the cron tick fires.
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    _single_instance_lock
  else
    # -------- legacy pgrep guard (no lock.inc on the box yet) ---------
    # Anchored to the execution form the crontab uses; the $( ) fork of
    # this very process matches as well, hence a count of two is ours.
    _CNT=$(pgrep -fc "^(/[^ ]*/)?bash (-c )?/var/xdrago/manage_solr_config\.sh( |$)")
    if (( _CNT > 2 )); then
      echo "Too many manage_solr_config.sh running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}

_is_protected_run

if [ "${_protectedRun}" = "FALSE" ]; then
  _manage_single_lock
  _NOW=$(date +%y%m%d-%H%M%S)
  _NOW=${_NOW//[^0-9-]/}
  [ -d "/var/backups/solr/log" ] || mkdir -p /var/backups/solr/log
  find /var/backups/solr/*/* -mtime +0 -type f -exec rm -f {} \; &> /dev/null
  find /var/backups/solr-archive -mindepth 1 -maxdepth 1 -type f -mtime +30 -exec rm -f {} \; &> /dev/null
  _start_up >/var/backups/solr/log/solr-${_NOW}.log 2>&1
fi

exit 0
