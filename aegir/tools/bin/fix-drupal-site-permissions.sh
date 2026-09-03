#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file permissions of a Drupal site. You need
to provide the following argument:

  --site-path: Path to the Drupal site's directory.

Usage: (sudo) ${0##*/} --site-path=PATH
Example: (sudo) ${0##*/} --site-path=/var/aegir/platforms/drupal-7.50/sites/example.com
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users.
# A symlink planted at a known child path inside ${site_path} (e.g. via an
# uploaded tar archive) would otherwise cause direct chmod calls to alter
# system file permissions. Defence is the same shape used by the sibling
# fix-drupal-* helpers: realpath prefix check + symlink precheck before chmod.
_validate_path_prefix() {
  # Scope the resolved path to the SUDO caller's OWN home tree (aegir ->
  # /var/aegir, Octopus oN -> /data/disk/oN), not merely "some BOA tree": a
  # tenant must not drive this root-run chmod against another tenant's
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

_chmod_safe() {
  local _mode=$1
  shift
  local _p
  for _p in "$@"; do
    [ -L "${_p}" ] && continue
    [ -e "${_p}" ] || continue
    chmod "${_mode}" "${_p}"
  done
}

site_path=${1%/}

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --site-path=*)
        site_path="${1#*=}"
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
### re-point it between _validate_path_prefix and the chmods.
if [ -n "${site_path}" ] && [ -e "${site_path}" ]; then
  site_path=$(realpath -e -- "${site_path}" 2>/dev/null) || site_path=""
fi

# --- Grav 2 site capsule (boa-grav D-003) ------------------------------------
# A capsule is a full Grav install at sites/<uri>/ with no settings.php;
# detect it positively and run the capsule permission model instead of
# refusing (union seam: further foreign-CMS branches join here the same way).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/bin/grav" ] \
  && [ -f "${site_path}/system/defines.php" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  _validate_path_prefix "${site_path}"
  # Capsule permission model (spike-proven): code 0755/0644; the writable
  # set 02775 dirs + g+rw files (FPM writes via GROUP; setgid keeps the
  # group on web-created entries); the capsule's own bin/ stays executable
  # (the enforced-PHP wrapper and the upgrade engine exec bin/grav, bin/gpm).
  printf "Setting Grav permissions of %s\n" "${site_path}"
  find ${site_path} -path "${site_path}/user" -prune \
    -o -path "${site_path}/cache" -prune \
    -o -path "${site_path}/logs" -prune \
    -o -path "${site_path}/tmp" -prune \
    -o -path "${site_path}/backup" -prune \
    -o -path "${site_path}/images" -prune \
    -o -path "${site_path}/assets" -prune \
    -o -type d -exec chmod 0755 {} + 2> /dev/null
  find ${site_path} -path "${site_path}/user" -prune \
    -o -path "${site_path}/cache" -prune \
    -o -path "${site_path}/logs" -prune \
    -o -path "${site_path}/tmp" -prune \
    -o -path "${site_path}/backup" -prune \
    -o -path "${site_path}/images" -prune \
    -o -path "${site_path}/assets" -prune \
    -o -type f -exec chmod 0644 {} + 2> /dev/null
  _chmod_safe 0755 ${site_path}/bin/*
  for _wd in user cache logs tmp backup images assets; do
    [ -d "${site_path}/${_wd}" ] || continue
    find "${site_path}/${_wd}" -type d -exec chmod 02775 {} + 2> /dev/null
    find "${site_path}/${_wd}" -type f -exec chmod 0664 {} + 2> /dev/null
  done
  # Secret surfaces AFTER the generic pass, which would re-widen them
  # (boa-grav D-008; same class as the TXP private/ store): accounts hold
  # password hashes and live reset tokens, config holds the session salt and
  # SMTP/API credentials. Group-rw for FPM, owner-rw for the CLI, NO world
  # bits. The root .env (phase 2: DB credentials) keeps FPM's read via group.
  for _sd in user/accounts user/config user/env; do
    [ -d "${site_path}/${_sd}" ] || continue
    find "${site_path}/${_sd}" -type d -exec chmod 02770 {} + 2> /dev/null
    find "${site_path}/${_sd}" -type f -exec chmod 0660 {} + 2> /dev/null
  done
  _chmod_safe 0640 "${site_path}/.env"
  _chmod_safe 0440 "${site_path}/drushrc.php"
  echo "Done setting proper permissions of files and directories (Grav site)."
  exit 0
fi

# --- Textpattern multisite site (boa-txp D-002) -------------------------------
# A TXP site is sites/<uri>/{admin,private,public} with no settings.php; detect
# it positively and run the TXP permission model instead of refusing (union seam
# shared with the Grav branch above).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/public/index.php" ] \
  && [ -f "${site_path}/public/css.php" ] \
  && [ -d "${site_path}/admin" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  _validate_path_prefix "${site_path}"
  # Code 0755/0644; the writable set 02775 dirs + g+rw files (FPM writes via
  # GROUP; setgid keeps the group on web-created entries).
  #
  # private/ is PRUNED from the generic pass on purpose: it is the credential
  # store, and the generic 0644 file pass would widen private/config.php from
  # 0440 to world-readable. It is set explicitly below instead.
  #
  # find is never given -L, so the four admin symlinks are type l, are not
  # matched by -type d/f and are not descended into -- the shared core tree is
  # never touched from here.
  printf "Setting Textpattern permissions of %s\n" "${site_path}"
  find ${site_path} -path "${site_path}/private" -prune \
    -o -path "${site_path}/tmp" -prune \
    -o -path "${site_path}/modules" -prune \
    -o -path "${site_path}/admin/plugins" -prune \
    -o -path "${site_path}/public/files" -prune \
    -o -path "${site_path}/public/images" -prune \
    -o -path "${site_path}/public/themes" -prune \
    -o -type d -exec chmod 0755 {} + 2> /dev/null
  find ${site_path} -path "${site_path}/private" -prune \
    -o -path "${site_path}/tmp" -prune \
    -o -path "${site_path}/modules" -prune \
    -o -path "${site_path}/admin/plugins" -prune \
    -o -path "${site_path}/public/files" -prune \
    -o -path "${site_path}/public/images" -prune \
    -o -path "${site_path}/public/themes" -prune \
    -o -type f -exec chmod 0644 {} + 2> /dev/null
  for _wd in tmp modules admin/plugins public/files public/images public/themes; do
    [ -d "${site_path}/${_wd}" ] || continue
    find "${site_path}/${_wd}" -type d -exec chmod 02775 {} + 2> /dev/null
    find "${site_path}/${_wd}" -type f -exec chmod 0664 {} + 2> /dev/null
  done
  # Credential store: group-traversable (FPM reads config.php through its
  # www-data group), unreadable to everyone else.
  _chmod_safe 0750 "${site_path}/private"
  find "${site_path}/private" -type f -exec chmod 0440 {} + 2> /dev/null
  # Aegir's own site drushrc sits at the site ROOT (not inside private/) and
  # carries the db credentials, so the generic 0644 pass above widens it to
  # world-readable on every verify. Restore the 0440 the Drushrc writer sets --
  # never fight the writer. (Same class as the private/ prune; caught live on
  # a test rig by isolating this script from the verify that re-renders the file.)
  _chmod_safe 0440 "${site_path}/drushrc.php"
  echo "Done setting proper permissions of files and directories (Textpattern site)."
  exit 0
fi

if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
  printf "Error: Please provide a valid Drupal site directory.\n"
  exit 1
fi

_validate_path_prefix "${site_path}"

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### modules, themes and libraries are names the tenant can plant: it can create
### the site dir itself under the group-writable sites/ (02771), and the
### site-level code dirs are 02775 and group-writable. The rm below and the find start
### points walk THROUGH them, while _chmod_safe protects only the final
### component. None is ever legitimately a symlink at site level.
for _d in modules themes libraries; do
  if [ -L "${site_path}/${_d}" ]; then
    printf "Error: %s is a symlink in %s; refusing.\n" "${_d}" "${site_path}" >&2
    exit 1
  fi
done

if [ -e "${site_path}/libraries/permissions-fixed.pid" ]; then
  rm -f ${site_path}/libraries/permissions-fixed.pid
fi
cd ${site_path}
printf "Setting correct permissions on key files and directories inside "${site_path}"...\n"
### directory and settings files - site level
if [ -e "${site_path}/aegir.services.yml" ]; then
  rm -f ${site_path}/aegir.services.yml
fi
### find -type d / -type f predicates exclude symlinks, so these are safe.
find ${site_path}/*.php -type f -exec chmod 0440 {} \; &> /dev/null
### The hostmaster site's drushrc.php carries the instance DB user (ALL
### PRIVILEGES) and only the backend user, its owner, ever reads it: no group
### read at all, box-wide 'users' or the account's own group alike.
if [[ "${site_path}" =~ /aegir/(distro|host_master)/ ]]; then
  _chmod_safe 0400 "${site_path}/drushrc.php"
fi
_chmod_safe 0640 "${site_path}/civicrm.settings.php"
### modules,themes,libraries - site level
find ${site_path}/{modules,themes,libraries} -type d -exec \
  chmod 02775 {} \; &> /dev/null
find ${site_path}/{modules,themes,libraries} -type f -exec \
  chmod 0664 {} \; &> /dev/null

### The trailing slash makes find DESCEND through files/ and private/, which
### are legitimately symlinks into the per-account static store -- so a link
### planted at either name walks this root chmod into an arbitrary tree
### (files -> /etc turns every file there 0664, i.e. world-readable). Resolve
### each store once, bounded to this account's own store root.
_files_dir=$(_store_dir "${site_path}/files") || _files_dir=""
_priv_dir=$(_store_dir "${site_path}/private") || _priv_dir=""
if [ -z "${_files_dir}" ] && [ -e "${site_path}/files" ]; then
  printf "Notice: %s is not this account's own files store; skipping.\n" \
    "${site_path}/files" >&2
fi

if [ -n "${_files_dir}" ] \
  && [ ! -e "${_files_dir}/permissions-fixed-${_TODAY}.pid" ]; then
  ### ctrl pid
  rm -f ${_files_dir}/permissions-fixed*.pid
  touch ${_files_dir}/permissions-fixed-${_TODAY}.pid
  ### files - site level
  find ${_files_dir}/ -type d -exec chmod 02775 {} \; &> /dev/null
  find ${_files_dir}/ -type f -exec chmod 0664 {} \; &> /dev/null
  _chmod_safe 02775 "${_files_dir}"
  ### private - site level
  if [ -n "${_priv_dir}" ]; then
    find ${_priv_dir}/ -type d -exec chmod 02775 {} \; &> /dev/null
    find ${_priv_dir}/ -type f -exec chmod 0664 {} \; &> /dev/null
  fi
  ### known exceptions
  _chmod_safe 0644 "${_files_dir}/.htaccess"
fi

echo "Done setting proper permissions on site files and directories."
