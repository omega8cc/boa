#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file ownership of a Drupal site. You need to
provide the following arguments:

  --site-path: Path to the Drupal site directory.
  --script-user: Username of the user to whom you want to give file ownership
                 (defaults to 'aegir').
  --web-group: Web server group name (defaults to 'www-data').

Usage: (sudo) ${0##*/} --site-path=PATH --script-user=USER --web_group=GROUP
Example: (sudo) ${0##*/} --site-path=/var/aegir/platforms/drupal-7.50/sites/example.com --script-user=aegir --web-group=www-data
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# Reject any caller-supplied path that resolves outside the BOA-managed roots.
# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users,
# and the account owns the names under ${site_path}, so any of them can be a
# link. Defence:
#  1. _validate_path_prefix on the caller-supplied root.
#  2. chown -h on every recursive/non-recursive call below (replaces the prior
#     chown -L -R which explicitly dereferenced symlinks during traversal).
#     This is compatible with any root-managed symlinks within the tree —
#     their own metadata is adjusted but their targets are never followed.
#  3. Every chown runs inside a directory entered for real (_in_pinned_dir),
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
  # target are plantable: accept a real directory, or a link that resolves
  # inside THIS account's own resolved store root -- the same "never another
  # account's tree" rule _validate_path_prefix applies to the site path.
  local _p _acct _root _res
  _p="$1"
  [ -d "${_p}" ] || return 1
  if [ ! -L "${_p}" ]; then
    printf '%s' "${_p}"
    return 0
  fi
  case "${site_path}/" in
    /var/aegir/*)
      _acct="/var/aegir"
      ;;
    /data/disk/*/*)
      _acct="${site_path#/data/disk/}"
      _acct="/data/disk/${_acct%%/*}"
      ;;
    *)
      return 1
      ;;
  esac
  _root=$(realpath -e -- "${_acct}/static/files" 2>/dev/null) || return 1
  _res=$(realpath -e -- "${_p}" 2>/dev/null) || return 1
  case "${_res}/" in
    "${_root}"/*) ;;
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

# chown -h (with -R when $1 is -R) to $2 of each name in the current (pinned)
# directory that matches a pattern after them (expanded here, nowhere else),
# handed over as ./name so no name is read as an option; a pattern that
# matches nothing is skipped.
_chown_here() {
  local _r="${1}" _o="${2}" _pat _p
  shift 2
  for _pat in "$@"; do
    for _p in ${_pat}; do
      _p="./${_p#./}"
      [ -e "${_p}" ] || [ -L "${_p}" ] || continue
      chown -h ${_r:+"${_r}"} "${_o}" "${_p}"
    done
  done
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

# The Grav capsule model, run inside the real site directory: code
# <user>:<account group>, the writable set and the .env <user>:<web_group>.
_grav_site_own_here() {
  local _wd
  chown -h -R "${script_user}:${_code_group}" .
  for _wd in user cache logs tmp backup images assets; do
    [ -d "./${_wd}" ] || continue
    chown -h -R "${script_user}:${web_group:-www-data}" "./${_wd}"
  done
  # The secret root .env drops its world bit, so FPM's read comes via
  # the web group -- the code pass above homed it to the account group.
  if [ -f ./.env ]; then
    chown -h "${script_user}:${web_group:-www-data}" ./.env
  fi
}

# The Textpattern model, run inside the real site directory; the two-level
# writable dirs are handed over from inside their real parent.
_txp_site_own_here() {
  local _wd _here
  _here="$(pwd -P)"
  chown -h -R "${script_user}:${_code_group}" .
  for _wd in tmp admin/plugins public/files public/images public/themes private; do
    [ -d "./${_wd}" ] || continue
    case "${_wd}" in
      */*)
        _in_pinned_dir "${_here}/${_wd%/*}" \
          chown -h -R "${script_user}:${web_group:-www-data}" "./${_wd##*/}"
        ;;
      *)
        chown -h -R "${script_user}:${web_group:-www-data}" "./${_wd}"
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
  chown -h "${script_user}:www-data" \
    ./local.settings.php ./settings.php ./civicrm.settings.php ./solr.php
  ### modules,themes,libraries - site level
  for _d in modules themes libraries; do
    _in_pinned_dir "${_here}/${_d}" \
      _chown_here -R "${script_user}:${_code_group}" '*'
  done
  chown -h "${script_user}:${_code_group}" ./drushrc.php
  _in_pinned_dir "${_here}/modules" \
    _chown_here "" "${script_user}:${_code_group}" '*.yml'
  chown -h "${script_user}:${_code_group}" ./modules ./themes ./libraries
}

# The files store, run inside it (entered for real): the day marker, then the
# whole store and its known children handed to <user>:www-data.
_files_own_here() {
  local _o="${script_user}:www-data" _here
  _here="$(pwd -P)"
  ### ctrl pid
  rm -f -- ./ownership-fixed*.pid
  _mark_here "ownership-fixed-${_TODAY}.pid"
  ### files - site level
  ### -h on recursive chown: with the default -P walk, no symlink in the
  ### store is ever dereferenced.
  chown -h -R "${_o}" .
  chown -h "${_o}" .
  chown -h "${_o}" ./tmp ./images ./pictures ./css ./js
  chown -h "${_o}" ./advagg_css ./advagg_js ./ctools
  chown -h "${_o}" ./imagecache ./locations
  chown -h "${_o}" ./xmlsitemap ./deployment ./styles ./private
  chown -h "${_o}" ./civicrm
  _in_pinned_dir "${_here}/ctools" chown -h "${_o}" ./css
  _in_pinned_dir "${_here}/civicrm" chown -h "${_o}" \
    ./templates_c ./upload ./persist ./custom ./dynamic
}

# The private store, run inside it (entered for real).
_priv_own_here() {
  local _o="${script_user}:www-data" _here
  _here="$(pwd -P)"
  chown -h -R "${_o}" .
  chown -h "${_o}" .
  chown -h "${_o}" ./files ./temp
  _in_pinned_dir "${_here}/files" chown -h "${_o}" ./backup_migrate
  _in_pinned_dir "${_here}/files/backup_migrate" chown -h "${_o}" \
    ./manual ./scheduled
  chown -h -R "${_o}" ./config
}

site_path=${1%/}
script_user=${2:-aegir}
web_group="${3:-www-data}"

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
        web_group="${1#*=}"
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
  # Capsule ownership model (spike-proven): code <user>:<account group>; the
  # writable set <user>:<web_group> so FPM writes via GROUP (version-flip-immune).
  # Runs inside the real site directory (_in_pinned_dir), and the owner and
  # group stay one quoted argument whatever --web-group carries.
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
  # Code <user>:<account group>; the writable set and the credential store
  # <user>:<web_group> so FPM reaches them via GROUP (version-flip-immune: a
  # box-default PHP bump changes the pool USER, never its www-data group).
  # -h keeps the four load-bearing admin symlinks as symlinks and never
  # follows them into the shared core.
  # Runs inside the real site directory (_in_pinned_dir), and the owner and
  # group stay one quoted argument whatever --web-group carries.
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

printf "Setting ownership of key files and directories inside "${site_path}" to: user => "${script_user}" group => "${_code_group}"\n"
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
