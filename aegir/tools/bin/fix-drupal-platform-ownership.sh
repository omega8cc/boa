#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file ownership of a Drupal platform. You need to
provide the following arguments:

  --root: Path to the root of your Drupal installation.
  --script-user: Username of the user to whom you want to give file ownership
                 (defaults to 'aegir').
  --web-group: accepted and ignored; the web group is derived from the
               platform's account (www-data until the account has its own).

Usage: (sudo) ${0##*/} --root=PATH --script-user=USER
Example: (sudo) ${0##*/} --root=/var/aegir/platforms/drupal-7.50 --script-user=aegir
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# find -execdir refuses a PATH with a relative entry: the walks below run
# with the one sudo gives them.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Reject any caller-supplied path that resolves outside the BOA-managed roots.
# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users,
# and the account owns the names under ${drupal_root}, so any of them can be
# a link. Defence:
#  1. _validate_path_prefix on the caller-supplied root.
#  2. chown -h on every recursive/non-recursive call below, so a symlink under
#     the validated tree has its own metadata adjusted but its target is
#     never dereferenced. This is compatible with legacy BOA platforms that
#     legitimately use a root-managed symlink for shared core/ — those are
#     skipped, not broken. A find walk hands chown each name from -execdir,
#     one ./name in the directory find holds open.
#  3. Every chown runs inside a directory entered for real (_in_pinned_dir),
#     on ./names there, so a name on the way swapped for a link after the
#     root was resolved is never followed.
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

# The root is resolved once below, but its account owns every name on the
# way (~/static and the platform tree), so any of them can be swapped for a
# link at any time. Every act runs inside a directory entered for real: cd -P,
# then "$@" only while pwd -P there is still the resolved path, so a link put
# on the way since is never followed, and ./name then stays in that
# directory whatever is swapped. $1 = a path resolved once above.
_in_pinned_dir() {
  local _d="${1}"
  shift
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_d}" ] && "$@" )
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

# The day marker in the current (pinned) sites/all/libraries: every earlier
# one removed, today's put as _mark_here puts it.
_own_marker_here() {
  rm -f -- ./ownership-fixed*.pid
  _mark_here "ownership-fixed-${_TODAY}.pid"
}

# ./$2 of the directory $1 (resolved once above) copied into the current
# (pinned) directory under the same name while that name is still free, as
# cp -a copied it: the same bytes, owner, group, read/write bits and mtime.
# The source is read bounded, never through a link or from a FIFO; the copy
# lands as a fresh file created exclusively, then renamed over the name, so
# nothing put at the name is written through.
_copy_new_here() {
  local _n="${2}" _t="./.${2}.put.$$.${RANDOM}" _st _typ _own _mod _sz _mt _c
  if [ -e "./${_n}" ] || [ -L "./${_n}" ]; then
    return 0
  fi
  _st=$(_in_pinned_dir "${1}" stat -c '%F|%u:%g|%a|%s|%Y' -- "./${_n}") \
    || return 1
  IFS='|' read -r _typ _own _mod _sz _mt <<< "${_st}"
  case "${_typ}" in
    "regular file"|"regular empty file") ;;
    *) return 1 ;;
  esac
  [[ "${_mod}" =~ ^[0-7]+$ && "${_sz}" =~ ^[0-9]+$ && "${_mt}" =~ ^[0-9]+$ ]] \
    || return 1
  [ "${_sz}" -le 1048576 ] || return 1
  # the x keeps the trailing newlines a command substitution would drop
  _c=$(_in_pinned_dir "${1}" timeout 10 dd if="./${_n}" \
    iflag=nofollow,nonblock,fullblock bs=1048576 count=1 status=none \
    2> /dev/null && echo x) || return 1
  rm -f -- "${_t}"
  if ( umask "$(printf '%03o' "$(( 0777 & ~8#${_mod} ))")"
    printf '%s' "${_c%x}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
    && chown -h "${_own}" "${_t}" 2> /dev/null; then
    touch -h -d "@${_mt}" "${_t}" 2> /dev/null
    mv -f -T -- "${_t}" "./${_n}" && return 0
  fi
  rm -f -- "${_t}"
  return 1
}

# Each Grav capsule in the current (pinned) sites/, entered for real: its
# writable set and its .env handed to the web group.
_grav_capsules_own_here() {
  local _c _here
  _here="$(pwd -P)"
  for _c in ./*/; do
    _c="${_c#./}"
    _in_pinned_dir "${_here}/${_c%/}" _grav_capsule_own_here
  done
}
_grav_capsule_own_here() {
  local _wd
  [ -f ./system/defines.php ] || return 0
  for _wd in user cache logs tmp backup images assets; do
    [ -d "./${_wd}" ] || continue
    chown -h -R "${script_user}${_wg:+:${_wg}}" "./${_wd}"
  done
  # The secret root .env drops its world bit, so FPM's read comes via
  # the web group -- the code pass above homed it to the account group.
  if [ -f ./.env ]; then
    chown -h "${script_user}${_wg:+:${_wg}}" ./.env
  fi
}

drupal_root=${1%/}
script_user=${2:-aegir}

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root=*)
        drupal_root="${1#*=}"
        ;;
    --script-user=*)
        script_user="${1#*=}"
        ;;
    --web-group=*)
        # Accepted for the callers that pass it, never used: the web group
        # is derived from the platform's account below.
        ;;
    --help) print_help;;
    *)
      printf "Error: Invalid argument, run --help for valid arguments.\n"
      exit 1
  esac
  shift
done

### Resolve the caller-supplied root ONCE, before any check or operation reads
### it: every branch below re-walks the raw argument, and ~/static is 02775 on
### tenant codebases, so the tenant owns the name it was handed and could
### re-point it between _validate_path_prefix and the chown legs. An
### empty result falls through to the "valid Drupal root" refusal below.
if [ -n "${drupal_root}" ] && [ -e "${drupal_root}" ]; then
  drupal_root=$(realpath -e -- "${drupal_root}" 2>/dev/null) || drupal_root=""
fi

# --- Grav 2 platform (site capsules) -----------------------------------------
# A Grav root carries no Drupal system.module; detect it positively and run
# the capsule model instead of refusing (union seam: further foreign-CMS
# branches join here the same way).
if [ -n "${drupal_root}" ] \
  && [ -f "${drupal_root}/bin/grav" ] \
  && [ -f "${drupal_root}/system/defines.php" ] \
  && [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
      printf "Error: Please provide a valid user.\n"
      exit 1
  fi
  _validate_path_prefix "${drupal_root}"
  _code_group=$(_acct_group "${drupal_root}")
  _wg=$(_web_group "${drupal_root}")
  # Capsule ownership model (spike-proven): code <user>:<account group>; the
  # writable set <user>:<web group> so FPM writes via GROUP (version-flip-immune)
  # -- and web-created files are re-homed to the instance user, healing the
  # web-owned residue the lifecycle verbs otherwise have to park.
  # Each pass runs inside the real root or capsule (_in_pinned_dir), and the
  # owner and group stay one quoted argument.
  printf "Setting Grav ownership of %s to: user => %s group => %s\n" "${drupal_root}" "${script_user}" "${_code_group}"
  _in_pinned_dir "${drupal_root}" chown -h -R "${script_user}:${_code_group}" .
  _in_pinned_dir "${drupal_root}/sites" _grav_capsules_own_here
  echo "Done setting proper ownership of files and directories (Grav)."
  exit 0
fi

# --- Textpattern platform (shared core) --------------------------------------
# A TXP root carries no Drupal system.module; detect it positively (the same
# probe as codebasecheck: textpattern/lib/constants.php + css.php + no core/)
# and run the shared-core model instead of refusing.
if [ -n "${drupal_root}" ] \
  && [ -f "${drupal_root}/textpattern/lib/constants.php" ] \
  && [ -f "${drupal_root}/css.php" ] \
  && [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
      printf "Error: Please provide a valid user.\n"
      exit 1
  fi
  _validate_path_prefix "${drupal_root}"
  _code_group=$(_acct_group "${drupal_root}")
  # Shared-core ownership model: the pristine core is <user>:<account group>
  # throughout.
  # Everything under sites/* is the SITE scripts' territory -- those trees
  # carry 0440 group-read secrets (config.php, drushrc.php) and web-group
  # writable dirs the site pass owns; a platform-wide chown would re-home
  # their groups and break FPM's group-read path, so sites/* is pruned
  # outright (only the sites/ directory itself takes core ownership). Each
  # name is handed to chown -h from -execdir, one ./name in the directory
  # find holds open, so no directory on the way is resolved again.
  printf "Setting Textpattern ownership of %s to: user => %s group => %s\n" "${drupal_root}" "${script_user}" "${_code_group}"
  _in_pinned_dir "${drupal_root}" find . -path "./sites/*" -prune \
    -o -execdir chown -h "${script_user}:${_code_group}" {} + 2> /dev/null
  echo "Done setting proper ownership of files and directories (Textpattern platform)."
  exit 0
fi

# Every generation has sites/ and one of the two system.module paths. The
# test used to read (no root OR no sites/ OR no core module) AND no D7 module,
# which let a Drupal 7 tree without sites/ through: the missing directory
# was then skipped silently below and a clean report no longer proved a
# complete tree. Grouped as meant, a tree without sites/ is refused for every
# generation, loudly.
if [ -z "${drupal_root}" ] \
  || [ ! -d "${drupal_root}/sites" ] \
  || { [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
    && [ ! -f "${drupal_root}/modules/system/system.module" ]; }; then
    printf "Error: Please provide a valid Drupal root directory.\n"
    exit 1
fi

if [ -z "${script_user}" ] \
  || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
    printf "Error: Please provide a valid user.\n"
    exit 1
fi

_validate_path_prefix "${drupal_root}"
_code_group=$(_acct_group "${drupal_root}")
_wg=$(_web_group "${drupal_root}")

### sites and sites/all are names a tenant can plant as symlinks (the docroot
### is group-writable) and every op below walks THROUGH them; -h protects
### only the final component. A symlinked skeleton is never legitimate.
if [ -L "${drupal_root}/sites" ] || [ -L "${drupal_root}/sites/all" ]; then
  printf "Error: sites or sites/all is a symlink in %s; refusing.\n" "${drupal_root}" >&2
  exit 1
fi
### The four names under sites/all are plantable the same way, and the day
### marker's rm glob and touch, the mkdir, the drushrc.php chown and the
### tcpdf leg below resolve through them; -h protects only the final
### component. Never legitimately symlinks (the o_contrib* links live under
### the platform root's own modules/, never under sites/all): refuse, as the
### site-level helper does; the nightly withholds the same legs instead.
### tcpdf and its cache child are prechecked at their own leg below.
for _d in modules themes libraries drush; do
  if [ -L "${drupal_root}/sites/all/${_d}" ]; then
    printf "Error: sites/all/%s is a symlink in %s; refusing.\n" "${_d}" "${drupal_root}" >&2
    exit 1
  fi
done

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### Fix ownership only once daily, unless it's Drupal 8 or newer
if [ -e "${drupal_root}/sites/all/libraries/ownership-fixed-${_TODAY}.pid" ]; then
  if [ -e "${drupal_root}/core/themes/olivero" ] \
    || [ ! -e "${drupal_root}/core/themes/classy" ]; then
    _drupal_eight_nine_ten=TRUE
  else
    exit 0
  fi
fi

### Every act below runs inside a directory entered for real
### (_in_pinned_dir) and names only ./entries there; refuse now when the
### root itself cannot be entered as resolved.
if ! _in_pinned_dir "${drupal_root}" true; then
  printf "Error: %s is not a real directory; refusing.\n" "${drupal_root}" >&2
  exit 1
fi

printf 'Setting ownership of %s to: user => %s group => %s\n' "${drupal_root}" "${script_user}" "${_code_group}"
_in_pinned_dir "${drupal_root}" chown -h "${script_user}:${_code_group}" .

### Make sure that expected sites/all sub-directories exist
_in_pinned_dir "${drupal_root}/sites" mkdir -p ./all
_in_pinned_dir "${drupal_root}/sites/all" \
  mkdir -p ./modules ./themes ./libraries ./drush

### Create ctrl pid
_in_pinned_dir "${drupal_root}/sites/all/libraries" _own_marker_here

### sites/development.services.yml is a core scaffold file. Deleting it
### here (2019) made every later composer run re-scaffold it into the
### oN-owned sites/ directory and fail (omega8cc/boa#1936). Put core's own
### copy back where an earlier run removed it, so the scaffold plugin finds
### it unchanged and never has to write there. Read and written only inside
### the real directories (_copy_new_here).
_scaffold_yml="${drupal_root}/core/assets/scaffold/files/development.services.yml"
if [[ "${drupal_root}" =~ "/static/" ]] \
  && [ -f "${_scaffold_yml}" ] && [ ! -L "${_scaffold_yml}" ] \
  && [ ! -e "${drupal_root}/sites/development.services.yml" ] \
  && [ ! -L "${drupal_root}/sites/development.services.yml" ]; then
  _in_pinned_dir "${drupal_root}/sites" \
    _copy_new_here "${_scaffold_yml%/*}" development.services.yml
fi

### -h on every chown: symlinks under the account tree are never
### dereferenced (legacy BOA-managed shared-core symlinks under
### /var/aegir/distro/ stay untouched).
if [ -e "${drupal_root}/vendor" ]; then
  _in_pinned_dir "${drupal_root}" \
    chown -h -R "${script_user}:${_code_group}" ./vendor
elif [ -e "${drupal_root}/../vendor" ]; then
  _in_pinned_dir "${drupal_root%/*}" \
    chown -h -R "${script_user}:${_code_group}" ./vendor
fi

### The lists below span every core generation: a D7 tree has includes/ and
### misc/ but no core/ or libraries/, a D8+ tree the reverse, and sites.php
### or sites/all/drush/drushrc.php may not exist yet. chown reports each
### absent path as an error, which put a dozen "cannot access" lines into
### every install and upgrade report and trained readers to skip them. Chown
### what is there; a dangling symlink is still a target, since -h owns the
### link itself. Runs inside a directory entered for real: each argument is a
### ./name or a pattern, expanded there and nowhere else.
_own_existing() {
  local _mode="$1" _pat _pth
  shift
  case "${_mode}" in
    recursive|single) : ;;
    *)
      printf "Error: _own_existing: unknown mode %s\n" "${_mode}" >&2
      exit 1
      ;;
  esac
  for _pat in "$@"; do
    for _pth in ${_pat}; do
      [ -e "${_pth}" ] || [ -L "${_pth}" ] || continue
      if [ "${_mode}" = "recursive" ]; then
        chown -h -R "${script_user}:${_code_group}" "${_pth}"
      else
        chown -h "${script_user}:${_code_group}" "${_pth}"
      fi
    done
  done
}

_in_pinned_dir "${drupal_root}/sites/all" _own_existing recursive \
  ./modules ./themes ./libraries ./drush
_in_pinned_dir "${drupal_root}" _own_existing recursive \
  ./modules ./themes ./libraries ./includes ./misc ./profiles ./core

_in_pinned_dir "${drupal_root}/sites/all/drush" _own_existing single \
  ./drushrc.php
_in_pinned_dir "${drupal_root}" _own_existing single ./sites
_in_pinned_dir "${drupal_root}/sites" _own_existing single \
  './*' ./sites.php ./all

### known exceptions
### libraries/ is tenant-writable, so tcpdf and its cache child are names the
### tenant can plant. Precheck both, as the nightly does, and hand cache over
### from inside it, entered for real, so no name on the way is resolved
### again; a real directory is treated exactly as before.
if [ ! -L "${drupal_root}/sites/all/libraries/tcpdf" ] \
  && [ ! -L "${drupal_root}/sites/all/libraries/tcpdf/cache" ]; then
  _in_pinned_dir "${drupal_root}/sites/all/libraries/tcpdf/cache" \
    chown -h -R "${script_user}${_wg:+:${_wg}}" . &> /dev/null
fi

echo "Done setting proper ownership of platform files and directories."
