#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file ownership of a Drupal site. You need to
provide the following arguments:

  --site-path: Path to the Drupal site directory.
  --script-user: Username of the user to whom you want to give file ownership
                 (defaults to 'aegir').
  --web-group: accepted and ignored; the web group is derived from the
               site's account (www-data until the account has its own).

Usage: (sudo) ${0##*/} --site-path=PATH --script-user=USER
Example: (sudo) ${0##*/} --site-path=/var/aegir/platforms/drupal-7.50/sites/example.com --script-user=aegir
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# The notes on what a walk left as it was (_links_left_note) go to fd 3, a
# copy of stderr taken here: several legs below discard their own output.
exec 3>&2

# Reject any caller-supplied path that resolves outside the BOA-managed roots.
# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users,
# and the account owns the names under ${site_path}, so any of them can be a
# link. Defence:
#  1. _validate_path_prefix on the caller-supplied root.
#  2. Every hand-over below goes through _reown_here (replaces the prior
#     chown -L -R which explicitly dereferenced symlinks during traversal):
#     each directory and single-link regular file is changed through a handle
#     opened without following a link, so no link target is ever reached,
#     and a hard link planted in the tree is left alone instead of handing
#     over the file it shares. Links, root-managed ones included, keep their
#     owner.
#  3. Every hand-over runs inside a directory entered for real (_in_pinned_dir),
#     on ./names there, so a name on the way swapped for a link after the
#     path was resolved is never followed.
_validate_path_prefix() {
  # Scope the resolved path to the SUDO caller's OWN home tree (aegir ->
  # /var/aegir, Octopus oN -> /data/disk/oN), not merely "some BOA tree": a
  # tenant must not drive this root-run chown against another tenant's
  # /data/disk/oM/ files. Validating the realpath (not the raw arg) also defeats
  # a symlink planted inside the caller's own tree that points out to another
  # tenant. A direct root run (no SUDO_USER) is trusted and keeps the historical
  # BOA-tree allowlist.
  local _resolved _caller _home
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || {
    printf "Error: path does not resolve: %s\n" "$1" >&2
    exit 1
  }
  _caller="${SUDO_USER:-}"
  if [ -z "${_caller}" ]; then
    case "${_resolved}/" in
      /var/aegir/*|/data/disk/*|/home/*) return 0 ;;
      *)
        printf "Error: path outside allowed roots (/var/aegir, /data/disk, /home): %s\n" "${_resolved}" >&2
        exit 1
        ;;
    esac
  fi
  _home=$(getent passwd "${_caller}" 2>/dev/null | cut -d: -f6)
  _home="${_home%/}"
  case "${_home}" in
    /var/aegir|/data/disk/*) ;;
    *)
      printf "Error: unexpected sudo caller '%s' (home '%s'); refusing.\n" "${_caller}" "${_home}" >&2
      exit 1
      ;;
  esac
  case "${_resolved}/" in
    "${_home}"/*) ;;
    *)
      printf "Error: path '%s' is outside the caller's own tree (%s).\n" "${_resolved}" "${_home}" >&2
      exit 1
      ;;
  esac
}

_store_dir() {
  # Echo the directory to walk for a per-site files/ or private/ store, or
  # nothing (the caller then skips it). These are LEGITIMATELY symlinks --
  # autosymlink points them at <account>/static/files/<site>/<type>, and
  # static/files may itself be a symlink to a dedicated disk -- so they cannot
  # be refused outright. But the tenant owns ~/static and can own the site dir
  # itself (sites/ is 02771 on tenant codebases), so both the link and its
  # target are plantable, static/files included: its resolved path is never
  # the anchor. Accept a real directory, or a link that resolves strictly
  # below THIS account's own real static/files, or below migratefs' layout
  # for this account on attached storage (/mnt/<mount>/files/<acct>/static/files,
  # where no directory of the mount part is itself named files or static).
  local _p _acct="" _res _own _m
  _p="$1"
  [ -d "${_p}" ] || return 1
  if [ ! -L "${_p}" ]; then
    printf '%s' "${_p}"
    return 0
  fi
  case "${site_path}/" in
    /var/aegir/*)
      _own="/var/aegir/static/files/"
      ;;
    /data/disk/*/*)
      _acct="${site_path#/data/disk/}"
      _acct="${_acct%%/*}"
      case "${_acct}" in
        ""|*[!a-z0-9-]*) return 1 ;;
      esac
      _own="/data/disk/${_acct}/static/files/"
      ;;
    *)
      return 1
      ;;
  esac
  _res=$(realpath -e -- "${_p}" 2>/dev/null) || return 1
  case "${_res}" in
    *[!A-Za-z0-9._/-]*) return 1 ;;
    "${_own}"?*) ;;
    /mnt/?*/files/"${_acct}"/static/files/?*)
      [ -n "${_acct}" ] || return 1
      _m="${_res%%/files/"${_acct}"/static/files/*}"
      case "${_m}" in
        */files/*|*/static/*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  printf '%s' "${_res}"
}


# Group that owns the code tree at a validated path. Derived here, never
# taken from argv: this script is reachable through NOPASSWD sudo from every
# account, so a caller-supplied group would let one tenant chgrp its tree to
# another tenant's group. 'users' until the account has been converted to a
# private primary group named after itself, so a tool landing on an
# unconverted or half-converted box leaves it exactly as it is today.
_acct_group() {
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

# The site path and each store are resolved once below, but the account owns
# every name on the way (the platform tree, sites/, static/files), so any of
# them can be swapped for a link at any time. Every act runs inside a
# directory entered for real: cd -P, then "$@" only while pwd -P there is
# still the resolved path, so a link put on the way since is never followed,
# and ./name then stays in that directory whatever is swapped. $1 = a path
# resolved once above.
_in_pinned_dir() {
  local _d="${1}"
  shift
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_d}" ] && "$@" )
}

# Each named directory or single-link regular file handed to uid $1 and gid
# $2 through a handle opened without following a link or blocking on a FIFO.
# A file with more than one link, a link, a FIFO or a socket is left alone:
# a hard link planted in a tree the account can write shares its file with a
# name elsewhere, which a chown by name would hand over too, and nothing
# checks who owns a link. The names are ./names in the current directory.
_ACCT_REOWN_PL='use Fcntl; my ($u, $g, @f) = @ARGV; for my $f (@f) { sysopen(my $h, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or next; my @s = stat($h); chown($u, $g, $h) if @s && (-d _ || (-f _ && $s[3] == 1)); close($h); } exit 0'

# A walk leaves a regular file with more than one link as it was (a hard
# link planted in a tree the account can write would carry the change to the
# file it shares), so that file keeps its old owner and mode. Say so once
# per walk: how many the walk's selection holds and the first, found by the
# same start points and tests ("$@", run from the directory the walk ran
# in). Printed on fd 3, which the legs that discard their output leave open;
# no count is taken when the whole run's output goes to /dev/null (the
# nightly's foreign-CMS leg), which would only add a traversal nobody reads.
_links_left_note() {
  local _f _n=0 _first="" _here
  [ /dev/fd/3 -ef /dev/null ] && return 0
  while IFS= read -r -d '' _f; do
    [ -n "${_first}" ] || _first="${_f}"
    _n=$(( _n + 1 ))
  done < <(find "$@" -type f -links +1 -print0 2> /dev/null)
  [ "${_n}" -gt 0 ] || return 0
  _here="$(pwd -P)"
  _first="${_here}/${_first#./}"
  printf "Notice: %s file(s) with more than one link left unchanged under %s, first: %s\n" \
    "${_n}" "${_here}" "${_first//[[:cntrl:]]/?}" >&3
  return 0
}

# chown -h [-R] <owner[:group]> <names> as _ACCT_REOWN_PL hands them over,
# in the current (pinned) directory: the owner and group resolved to numbers
# first (a name that does not resolve is refused; no group named is -1, each
# entry keeps its own, as chown <owner> keeps it), then each ./name, or with
# -R every entry at or below each name, walked by find (any find tests after
# the names apply first) and handed over from -execdir, one ./name in the
# directory find holds; a walk ends with _links_left_note.
_reown_here() {
  local _r="" _uid _gid=-1 _rc
  if [ "${1}" = "-R" ]; then
    _r="-R"
    shift
  fi
  _uid=$(id -u -- "${1%%:*}" 2> /dev/null)
  [[ "${1}" != *:* ]] \
    || _gid=$(getent group "${1#*:}" 2> /dev/null | cut -d: -f3)
  if [[ ! "${_uid}" =~ ^[0-9]+$ || ! "${_gid}" =~ ^(-1|[0-9]+)$ ]]; then
    printf "Error: invalid owner %s\n" "${1}" >&2
    return 1
  fi
  shift
  if [ -n "${_r}" ]; then
    env PATH=/usr/local/bin:/usr/bin:/bin find "$@" \
      -execdir perl -e "${_ACCT_REOWN_PL}" "${_uid}" "${_gid}" {} +
    _rc=$?
    _links_left_note "$@"
    return "${_rc}"
  else
    perl -e "${_ACCT_REOWN_PL}" "${_uid}" "${_gid}" "$@"
  fi
}

# Each name in the current (pinned) directory that matches a pattern after
# $2 (expanded here, nowhere else) handed to $2 by _reown_here (with -R when
# $1 is -R), as ./name so no name is read as an option; a pattern that
# matches nothing is skipped.
_chown_here() {
  local _r="${1}" _o="${2}" _pat _p
  local -a _list=()
  shift 2
  for _pat in "$@"; do
    for _p in ${_pat}; do
      _p="./${_p#./}"
      [ -e "${_p}" ] || [ -L "${_p}" ] || continue
      _list+=("${_p}")
    done
  done
  [ "${#_list[@]}" -gt 0 ] || return 0
  _reown_here ${_r:+"${_r}"} "${_o}" "${_list[@]}"
}

# ./$1 in the current (pinned) directory as a fresh empty file, created
# exclusively and renamed over the name (root's, as touch made it): a link or
# a FIFO put at the name is replaced, never followed or opened.
_mark_here() {
  local _t="./.${1}.mark.$$.${RANDOM}"
  rm -f -- "${_t}"
  dd if=/dev/null of="${_t}" conv=excl status=none 2> /dev/null \
    && mv -f -T -- "${_t}" "./${1}" && return 0
  rm -f -- "${_t}"
  return 1
}

# ./$2 of the directory $1 (resolved once above) copied into the current
# (pinned) directory under the same name while that name is still free, as
# cp -a copied it: the same bytes, owner, group, read/write bits and mtime.
# The source is read bounded, never through a link or from a FIFO; the copy
# lands as a fresh file created exclusively, then renamed over the name, so
# nothing put at the name is written through. The temp is written, owned,
# moded (the read/write bits, as dd under a umask gave them) and dated
# through the one handle that created it (_COPY_PUT_PL), never by name: the
# directory is the account's, and a hard link renamed over the temp before a
# chown by name would hand the file it shares over. The write is flushed
# before the date is set, or the write at close would move it again.
_COPY_PUT_PL='use Fcntl; use IO::Handle; my ($n, $u, $g, $m, $t) = @ARGV; local $/; my $d = <STDIN>; sysopen(my $h, $n, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1; (print {$h} $d) or exit 1; $h->flush or exit 1; chown($u, $g, $h) or exit 1; chmod(oct($m) & 0666, $h) or exit 1; utime($t, $t, $h); close($h) or exit 1; exit 0'
_copy_new_here() {
  local _n="${2}" _t="./.${2}.put.$$.${RANDOM}" _st _typ _uid _gid _mod _sz _mt _c
  if [ -e "./${_n}" ] || [ -L "./${_n}" ]; then
    return 0
  fi
  _st=$(_in_pinned_dir "${1}" stat -c '%F|%u|%g|%a|%s|%Y' -- "./${_n}") \
    || return 1
  IFS='|' read -r _typ _uid _gid _mod _sz _mt <<< "${_st}"
  case "${_typ}" in
    "regular file"|"regular empty file") ;;
    *) return 1 ;;
  esac
  [[ "${_uid}" =~ ^[0-9]+$ && "${_gid}" =~ ^[0-9]+$ ]] || return 1
  [[ "${_mod}" =~ ^[0-7]+$ && "${_sz}" =~ ^[0-9]+$ && "${_mt}" =~ ^[0-9]+$ ]] \
    || return 1
  [ "${_sz}" -le 1048576 ] || return 1
  # the x keeps the trailing newlines a command substitution would drop
  _c=$(_in_pinned_dir "${1}" timeout 10 dd if="./${_n}" \
    iflag=nofollow,nonblock,fullblock bs=1048576 count=1 status=none \
    2> /dev/null && echo x) || return 1
  rm -f -- "${_t}"
  if printf '%s' "${_c%x}" \
    | perl -e "${_COPY_PUT_PL}" "${_t}" "${_uid}" "${_gid}" "${_mod}" "${_mt}" \
    && mv -f -T -- "${_t}" "./${_n}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}

# The Grav capsule model, run inside the real site directory: code
# <user>:<account group>, the writable set and the .env <user>:<web group>.
_grav_site_own_here() {
  local _wd
  _reown_here -R "${script_user}:${_code_group}" .
  for _wd in user cache logs tmp backup images assets; do
    [ -d "./${_wd}" ] || continue
    _reown_here -R "${script_user}${_wg:+:${_wg}}" "./${_wd}"
  done
  # The secret root .env drops its world bit, so FPM's read comes via
  # the web group -- the code pass above homed it to the account group.
  if [ -f ./.env ]; then
    _reown_here "${script_user}${_wg:+:${_wg}}" ./.env
  fi
}

# The Textpattern model, run inside the real site directory; the two-level
# writable dirs are handed over from inside their real parent.
_txp_site_own_here() {
  local _wd _here
  _here="$(pwd -P)"
  _reown_here -R "${script_user}:${_code_group}" .
  for _wd in tmp admin/plugins public/files public/images public/themes private; do
    [ -d "./${_wd}" ] || continue
    case "${_wd}" in
      */*)
        _in_pinned_dir "${_here}/${_wd%/*}" \
          _reown_here -R "${script_user}${_wg:+:${_wg}}" "./${_wd##*/}"
        ;;
      *)
        _reown_here -R "${script_user}${_wg:+:${_wg}}" "./${_wd}"
        ;;
    esac
  done
}

# The Drupal site directory's own names, run inside it (entered for real).
_site_own_here() {
  local _d _here
  _here="$(pwd -P)"
  ### directory and settings files - site level
  chown -h "${script_user}:${_code_group}" .
  _reown_here "${script_user}${_wg:+:${_wg}}" \
    ./local.settings.php ./settings.php ./civicrm.settings.php
  # solr.php holds the site's Solr core details for its owner; no web reader
  # opens it, so it stays in the code group its writer gives it.
  _reown_here "${script_user}:${_code_group}" ./solr.php
  ### modules,themes,libraries - site level
  for _d in modules themes libraries; do
    _in_pinned_dir "${_here}/${_d}" \
      _chown_here -R "${script_user}:${_code_group}" '*'
  done
  _reown_here "${script_user}:${_code_group}" ./drushrc.php
  _in_pinned_dir "${_here}/modules" \
    _chown_here "" "${script_user}:${_code_group}" '*.yml'
  _reown_here "${script_user}:${_code_group}" ./modules ./themes ./libraries
}

# The files store, run inside it (entered for real): the day marker, then the
# whole store and its known children handed to <user>:<web group>.
_files_own_here() {
  local _o="${script_user}${_wg:+:${_wg}}" _here
  _here="$(pwd -P)"
  ### ctrl pid
  rm -f -- ./ownership-fixed*.pid
  _mark_here "ownership-fixed-${_TODAY}.pid"
  ### files - site level
  ### The walk (_reown_here) never dereferences a symlink in the store and
  ### leaves a hard link alone.
  _reown_here -R "${_o}" .
  chown -h "${_o}" .
  _reown_here "${_o}" ./tmp ./images ./pictures ./css ./js
  _reown_here "${_o}" ./advagg_css ./advagg_js ./ctools
  _reown_here "${_o}" ./imagecache ./locations
  _reown_here "${_o}" ./xmlsitemap ./deployment ./styles ./private
  _reown_here "${_o}" ./civicrm
  _in_pinned_dir "${_here}/ctools" _reown_here "${_o}" ./css
  _in_pinned_dir "${_here}/civicrm" _reown_here "${_o}" \
    ./templates_c ./upload ./persist ./custom ./dynamic
}

# The private store, run inside it (entered for real).
_priv_own_here() {
  local _o="${script_user}${_wg:+:${_wg}}" _here
  _here="$(pwd -P)"
  _reown_here -R "${_o}" .
  chown -h "${_o}" .
  _reown_here "${_o}" ./files ./temp
  _in_pinned_dir "${_here}/files" _reown_here "${_o}" ./backup_migrate
  _in_pinned_dir "${_here}/files/backup_migrate" _reown_here "${_o}" \
    ./manual ./scheduled
  _reown_here -R "${_o}" ./config
}

site_path=${1%/}
script_user=${2:-aegir}

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --site-path=*)
        site_path="${1#*=}"
        ;;
    --script-user=*)
        script_user="${1#*=}"
        ;;
    --web-group=*)
        # Accepted for the callers that pass it, never used: the web group
        # is derived from the site's account below.
        ;;
    --help) print_help;;
    *)
      printf "Error: Invalid argument, run --help for valid arguments.\n"
      exit 1
  esac
  shift
done

### Resolve the caller-supplied path ONCE, before any check or operation reads
### it: every branch below re-walks the raw argument, and sites/ is 02771 on
### tenant codebases, so the tenant owns the name it was handed and could
### re-point it between _validate_path_prefix and the chowns.
if [ -n "${site_path}" ] && [ -e "${site_path}" ]; then
  site_path=$(realpath -e -- "${site_path}" 2>/dev/null) || site_path=""
fi

# --- Grav 2 site capsule -----------------------------------------------------
# A capsule is a full Grav install at sites/<uri>/ with no settings.php;
# detect it positively and run the capsule ownership model instead of
# refusing (union seam: further foreign-CMS branches join here the same way).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/bin/grav" ] \
  && [ -f "${site_path}/system/defines.php" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
    printf "Error: Please provide a valid user.\n"
    exit 1
  fi
  _validate_path_prefix "${site_path}"
  _code_group=$(_acct_group "${site_path}")
  _wg=$(_web_group "${site_path}")
  # Capsule ownership model (spike-proven): code <user>:<account group>; the
  # writable set <user>:<web group> so FPM writes via GROUP (version-flip-immune).
  # Runs inside the real site directory (_in_pinned_dir), and the owner and
  # group stay one quoted argument.
  printf "Setting Grav ownership of %s to: user => %s group => %s\n" "${site_path}" "${script_user}" "${_code_group}"
  _in_pinned_dir "${site_path}" _grav_site_own_here
  echo "Done setting proper ownership of files and directories (Grav site)."
  exit 0
fi

# --- Textpattern multisite site -----------------------------------------------
# A TXP site is sites/<uri>/{admin,private,public} with no settings.php; detect
# it positively and run the TXP ownership model instead of refusing (union seam
# shared with the Grav branch above; further foreign CMSes join the same way).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/public/index.php" ] \
  && [ -f "${site_path}/public/css.php" ] \
  && [ -d "${site_path}/admin" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
    printf "Error: Please provide a valid user.\n"
    exit 1
  fi
  _validate_path_prefix "${site_path}"
  _code_group=$(_acct_group "${site_path}")
  _wg=$(_web_group "${site_path}")
  # Code <user>:<account group>; the writable set and the credential store
  # <user>:<web group> so FPM reaches them via GROUP (version-flip-immune: a
  # box-default PHP bump changes the pool USER, never its group).
  # The walk (_reown_here) leaves the four load-bearing admin symlinks as
  # they are and never follows them into the shared core.
  # Runs inside the real site directory (_in_pinned_dir), and the owner and
  # group stay one quoted argument.
  printf "Setting Textpattern ownership of %s to: user => %s group => %s\n" "${site_path}" "${script_user}" "${_code_group}"
  _in_pinned_dir "${site_path}" _txp_site_own_here
  echo "Done setting proper ownership of files and directories (Textpattern site)."
  exit 0
fi

if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
  printf "Error: Please provide a valid Drupal site directory.\n"
  exit 1
fi

if [ -z "${script_user}" ] \
  || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
  printf "Error: Please provide a valid user.\n"
  exit 1
fi

_validate_path_prefix "${site_path}"
_code_group=$(_acct_group "${site_path}")
_wg=$(_web_group "${site_path}")

### modules, themes and libraries are names the tenant can plant: it can create
### the site dir itself under the group-writable sites/ (02771), and the
### site-level code dirs are 02775 group users. The rm below, the cp -a
### destination and the globs walk THROUGH them, while chown -h protects only
### the final component. None is ever legitimately a symlink at site level.
for _d in modules themes libraries; do
  if [ -L "${site_path}/${_d}" ]; then
    printf "Error: %s is a symlink in %s; refusing.\n" "${_d}" "${site_path}" >&2
    exit 1
  fi
done

### Every act below runs inside a directory entered for real
### (_in_pinned_dir) and names only ./entries there; refuse now when the
### site directory itself cannot be entered as resolved.
if ! _in_pinned_dir "${site_path}" true; then
  printf "Error: %s is not a real directory; refusing.\n" "${site_path}" >&2
  exit 1
fi

if [ -e "${site_path}/libraries/ownership-fixed.pid" ]; then
  _in_pinned_dir "${site_path}/libraries" rm -f -- ./ownership-fixed.pid
fi

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### Read and written only inside the real directories (_copy_new_here).
if [ -e "${site_path}/../sites/default/default.services.yml" ]; then
  if [ ! -e "${site_path}/modules/default.services.yml" ]; then
    _in_pinned_dir "${site_path}/modules" \
      _copy_new_here "${site_path%/*}/sites/default" default.services.yml
  fi
fi
if [ -e "${site_path}/modules/services.yml" ] && [ ! -e "${site_path}/services.yml" ]; then
  _in_pinned_dir "${site_path}" \
    ln -sfn "${site_path}/modules/services.yml" ./services.yml
fi

printf 'Setting ownership of key files and directories inside %s to: user => %s group => %s\n' "${site_path}" "${script_user}" "${_code_group}"
if [ ! -e "${site_path}/libraries" ]; then
  _in_pinned_dir "${site_path}" mkdir ./libraries
fi
_in_pinned_dir "${site_path}" _site_own_here &> /dev/null

### files/ and private/ are LEGITIMATELY symlinks into the per-account static
### store, and chown -h protects only the final name, so a path through such
### a link goes wherever it points. Each store is resolved once, accepted
### only inside this account's own store root, and handed over from inside
### the resolved directory, entered for real.
_files_dir=$(_store_dir "${site_path}/files") || _files_dir=""
_priv_dir=$(_store_dir "${site_path}/private") || _priv_dir=""
if [ -z "${_files_dir}" ] && [ -e "${site_path}/files" ]; then
  printf "Notice: %s is not this account's own files store; skipping.\n" \
    "${site_path}/files" >&2
fi

if [ -n "${_files_dir}" ] \
  && [ ! -e "${_files_dir}/ownership-fixed-${_TODAY}.pid" ]; then
  _in_pinned_dir "${_files_dir}" _files_own_here &> /dev/null
  ### private - site level
  if [ -n "${_priv_dir}" ]; then
    _in_pinned_dir "${_priv_dir}" _priv_own_here &> /dev/null
  fi
fi

echo "Done setting proper ownership of site files and directories."
