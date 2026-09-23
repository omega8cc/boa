#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file permissions of a Drupal platform. You need
to provide the following argument:

  --root: Path to the root of your Drupal installation.

Usage: (sudo) ${0##*/} --root=PATH
Example: (sudo) ${0##*/} --drupal_path=/var/aegir/platforms/drupal-7.50
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users.
# A symlink planted at a known child path (e.g. ${drupal_root}/web -> /etc) would
# cause direct chmod calls to alter system file permissions. Defence:
#  1. _validate_path_prefix on the caller-supplied root.
#  2. _chmod_safe wraps each direct chmod with a symlink precheck; symlinks
#     are skipped (so root-managed legacy symlinks remain untouched, and
#     attacker-planted symlinks cannot be used to chmod arbitrary files).
#     find -type d / -type f predicates already exclude symlinks, so the
#     find-exec chmod blocks below need no change.
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

drupal_root=${1%/}

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root=*)
        drupal_root="${1#*=}"
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
### re-point it between _validate_path_prefix and the chmod legs. An
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
  _validate_path_prefix "${drupal_root}"
  # Capsule permission model (spike-proven): code 0755/0644; the writable
  # set 02775 dirs + g+rw files (FPM writes via GROUP; setgid keeps the
  # group on web-created entries).
  printf "Setting Grav permissions of %s\n" "${drupal_root}"
  find ${drupal_root} -path "${drupal_root}/sites/*/user" -prune \
    -o -path "${drupal_root}/sites/*/cache" -prune \
    -o -path "${drupal_root}/sites/*/logs" -prune \
    -o -path "${drupal_root}/sites/*/tmp" -prune \
    -o -path "${drupal_root}/sites/*/backup" -prune \
    -o -path "${drupal_root}/sites/*/images" -prune \
    -o -path "${drupal_root}/sites/*/assets" -prune \
    -o -type d -exec chmod 0755 {} + 2> /dev/null
  find ${drupal_root} -path "${drupal_root}/sites/*/user" -prune \
    -o -path "${drupal_root}/sites/*/cache" -prune \
    -o -path "${drupal_root}/sites/*/logs" -prune \
    -o -path "${drupal_root}/sites/*/tmp" -prune \
    -o -path "${drupal_root}/sites/*/backup" -prune \
    -o -path "${drupal_root}/sites/*/images" -prune \
    -o -path "${drupal_root}/sites/*/assets" -prune \
    -o -type f -exec chmod 0644 {} + 2> /dev/null
  for _capsule in ${drupal_root}/sites/*/; do
    [ -f "${_capsule}system/defines.php" ] || continue
    # The capsule's own bin/ must stay executable (the enforced-PHP wrapper
    # and the upgrade engine exec bin/grav and bin/gpm).
    _chmod_safe 0755 ${_capsule}bin/*
    for _wd in user cache logs tmp backup images assets; do
      [ -d "${_capsule}${_wd}" ] || continue
      find "${_capsule}${_wd}" -type d -exec chmod 02775 {} + 2> /dev/null
      find "${_capsule}${_wd}" -type f -exec chmod 0664 {} + 2> /dev/null
    done
    # Secret surfaces AFTER the generic pass, which would re-widen them
    # otherwise: group-rw for FPM, owner-rw for the CLI, NO world
    # bits; the root .env keeps FPM's read via group.
    for _sd in user/accounts user/config user/env; do
      [ -d "${_capsule}${_sd}" ] || continue
      find "${_capsule}${_sd}" -type d -exec chmod 02770 {} + 2> /dev/null
      find "${_capsule}${_sd}" -type f -exec chmod 0660 {} + 2> /dev/null
    done
    _chmod_safe 0640 "${_capsule}.env"
    _chmod_safe 0440 "${_capsule}drushrc.php"
  done
  _chmod_safe 0755 ${drupal_root}/bin/*
  echo "Done setting proper permissions of files and directories (Grav)."
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
  _validate_path_prefix "${drupal_root}"
  # Shared-core permission model: pristine core 0755/0644. Everything under
  # sites/* is the SITE scripts' territory -- those trees carry 0440 secrets
  # (config.php, drushrc.php) and 02775 setgid writable dirs; a platform-wide
  # chmod would widen the secrets and strip the setgid bits (the drushrc
  # lesson: never fight the writer), so sites/* is pruned outright.
  printf "Setting Textpattern permissions of %s\n" "${drupal_root}"
  find ${drupal_root} -path "${drupal_root}/sites/*" -prune \
    -o -type d -exec chmod 0755 {} + 2> /dev/null
  find ${drupal_root} -path "${drupal_root}/sites/*" -prune \
    -o -type f -exec chmod 0644 {} + 2> /dev/null
  echo "Done setting proper permissions of files and directories (Textpattern platform)."
  exit 0
fi

# Every generation has sites/ and one of the two system.module paths; the
# ungrouped form let a Drupal 7 tree without sites/ through (see the
# ownership twin).
if [ -z "${drupal_root}" ] \
  || [ ! -d "${drupal_root}/sites" ] \
  || { [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
    && [ ! -f "${drupal_root}/modules/system/system.module" ]; }; then
    printf "Error: Please provide a valid Drupal root directory.\n"
    exit 1
fi

_validate_path_prefix "${drupal_root}"

### sites and sites/all are names a tenant can plant as symlinks (the docroot
### is group-writable) and the find/chmod passes below walk THROUGH them;
### _chmod_safe protects only the final component. A symlinked skeleton is
### never legitimate.
if [ -L "${drupal_root}/sites" ] || [ -L "${drupal_root}/sites/all" ]; then
  printf "Error: sites or sites/all is a symlink in %s; refusing.\n" "${drupal_root}" >&2
  exit 1
fi
### The four names under sites/all are plantable the same way, and the day
### marker's rm glob and touch, the mkdir and the tcpdf leg below resolve
### through them; _chmod_safe protects only the final component. Never
### legitimately symlinks (the o_contrib* links live under the platform
### root's own modules/, never under sites/all): refuse, as the site-level
### helper does; the nightly withholds the same legs instead. Inside a
### skeleton that passed, a symlinked entry is skipped per entry rather
### than refused (the sites/<uri> sweep below). tcpdf and its cache child
### are prechecked at their own leg below.
for _d in modules themes libraries drush; do
  if [ -L "${drupal_root}/sites/all/${_d}" ]; then
    printf "Error: sites/all/%s is a symlink in %s; refusing.\n" "${_d}" "${drupal_root}" >&2
    exit 1
  fi
done

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### Group write is the shell pair's free-ride territory under ~/static only.
### A hostmaster tree (aegir/distro on an Octopus account, /var/aegir/distro on
### the master) serves nothing an lshell user may touch: no group write at all.
### A built-in platform (~/distro and every other root) keeps its documented
### tenant-writable sites/all/{modules,themes,libraries}, while core, profiles,
### includes, vendor and the platform root itself take no group write: the
### backend user owns them and the web user only reads.
if [[ "${drupal_root}" =~ /aegir/distro/ ]]; then
  _MODE_DIR=0755
  _MODE_FILE=0644
  _SA_DIR=0755
  _SA_FILE=0644
elif [[ "${drupal_root}" =~ /static/ ]]; then
  _MODE_DIR=02775
  _MODE_FILE=0664
  _SA_DIR=02775
  _SA_FILE=0664
else
  _MODE_DIR=0755
  _MODE_FILE=0644
  _SA_DIR=02775
  _SA_FILE=0664
fi

### Fix permissions only once daily, unless it's Drupal 8 or newer
if [ -e "${drupal_root}/sites/all/libraries/permissions-fixed-${_TODAY}.pid" ]; then
  if [ -e "${drupal_root}/core/themes/olivero" ] \
    || [ ! -e "${drupal_root}/core/themes/classy" ]; then
    _drupal_eight_nine_ten=TRUE
  else
    exit 0
  fi
fi

cd ${drupal_root}

printf "Setting main permissions inside "${drupal_root}"...\n"
mkdir -p ${drupal_root}/sites/all/{modules,themes,libraries,drush}

### Create ctrl pid
rm -f ${drupal_root}/sites/all/libraries/permissions-fixed*.pid
touch ${drupal_root}/sites/all/libraries/permissions-fixed-${_TODAY}.pid

printf "Setting permissions of all codebase directories inside "${drupal_root}"...\n"
find ${drupal_root}/{modules,themes,libraries,includes,misc,profiles,core} -type d -exec chmod ${_MODE_DIR} {} \;

printf "Setting permissions of all codebase files inside "${drupal_root}"...\n"
find ${drupal_root}/{modules,themes,libraries,includes,misc,profiles,core} -type f -exec chmod ${_MODE_FILE} {} \;

if [ -e "${drupal_root}/vendor" ]; then
  printf "Setting permissions of all codebase directories inside "${drupal_root}/vendor"...\n"
  find ${drupal_root}/vendor -type d -exec chmod ${_MODE_DIR} {} \;
  printf "Setting permissions of all codebase files inside "${drupal_root}/vendor"...\n"
  find ${drupal_root}/vendor -type f -exec chmod ${_MODE_FILE} {} \;
elif [ -e "${drupal_root}/../vendor" ]; then
  printf "Setting permissions of all codebase directories inside "${drupal_root}/../vendor"...\n"
  find ${drupal_root}/../vendor -type d -exec chmod ${_MODE_DIR} {} \;
  printf "Setting permissions of all codebase files inside "${drupal_root}/../vendor"...\n"
  find ${drupal_root}/../vendor -type f -exec chmod ${_MODE_FILE} {} \;
fi

if [ -e "${drupal_root}/vendor/bin/drush" ]; then
  mv -f ${drupal_root}/vendor/bin/drush ${drupal_root}/vendor/bin/.off-drush
elif [ -e "${drupal_root}/../vendor/bin/drush" ]; then
  mv -f ${drupal_root}/../vendor/bin/drush ${drupal_root}/../vendor/bin/.off-drush
fi

if [ -e "${drupal_root}/vendor/drush/drush/drush" ]; then
  mv -f ${drupal_root}/vendor/drush/drush/drush ${drupal_root}/vendor/drush/drush/.off-drush
elif [ -e "${drupal_root}/../vendor/drush/drush/drush" ]; then
  mv -f ${drupal_root}/../vendor/drush/drush/drush ${drupal_root}/../vendor/drush/drush/.off-drush
fi

if [ -e "${drupal_root}/vendor/drush/drush/drush.php" ]; then
  _chmod_safe 0775 "${drupal_root}/vendor/drush/drush/drush.php"
elif [ -e "${drupal_root}/../vendor/drush/drush/drush.php" ]; then
  _chmod_safe 0775 "${drupal_root}/../vendor/drush/drush/drush.php"
fi

[ -d "${drupal_root}" ] && _chmod_safe ${_MODE_DIR} "${drupal_root}"

if [ -d "${drupal_root}/web" ]; then
  _chmod_safe ${_MODE_DIR} "${drupal_root}/web"
elif [ -d "${drupal_root}/docroot" ]; then
  _chmod_safe ${_MODE_DIR} "${drupal_root}/docroot"
elif [ -d "${drupal_root}/html" ]; then
  _chmod_safe ${_MODE_DIR} "${drupal_root}/html"
fi

printf "Setting permissions of all codebase directories inside "${drupal_root}/sites/all"...\n"
find ${drupal_root}/sites/all/{modules,themes,libraries} -type d -exec chmod ${_SA_DIR} {} \;

printf "Setting permissions of all codebase files inside "${drupal_root}/sites/all"...\n"
find ${drupal_root}/sites/all/{modules,themes,libraries} -type f -exec chmod ${_SA_FILE} {} \;

_chmod_safe 0644 ${drupal_root}/*.php
_chmod_safe ${_MODE_FILE} "${drupal_root}/autoload.php"
_chmod_safe 0751 "${drupal_root}/sites"
_chmod_safe 0755 ${drupal_root}/sites/*
_chmod_safe 0644 ${drupal_root}/sites/*.php
_chmod_safe 0644 ${drupal_root}/sites/*.txt
_chmod_safe 0644 ${drupal_root}/sites/*.yml
_chmod_safe 0755 "${drupal_root}/sites/all/drush"

### Tenant composer codebases (~/static, D8+): core's composer scaffold, run
### by the oN.ftp shell user (a group member, never the owner), rewrites its
### files under sites/ whenever one is missing or changed and insists on a
### writable parent first, so its two parents take group write here. Owner
### and the x-only bit for others stay as they are; BOA-built platforms keep
### the tight skeleton (omega8cc/boa#1936). Mirrored in night/20-sites.sh
### and provision's verify exit hook.
if [[ "${drupal_root}" =~ "/static/" ]] \
  && [ -e "${drupal_root}/core/lib/Drupal.php" ]; then
  _chmod_safe 02771 "${drupal_root}/sites"
  _chmod_safe 02775 "${drupal_root}/sites/default"
fi

### Lock Local Drush and Symfony Console Input/Style
if [ -e "${drupal_root}/core" ]; then
  if [ -e "${drupal_root}/vendor" ]; then
    printf "Locking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
    _chmod_safe 0400 "${drupal_root}/vendor/drush"
    _chmod_safe 0400 "${drupal_root}/vendor/symfony/console/Input"
    _chmod_safe 0400 "${drupal_root}/vendor/symfony/console/Style"
  elif [ -e "${drupal_root}/../vendor" ]; then
    printf "Locking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
    _chmod_safe 0400 "${drupal_root}/../vendor/drush"
    _chmod_safe 0400 "${drupal_root}/../vendor/symfony/console/Input"
    _chmod_safe 0400 "${drupal_root}/../vendor/symfony/console/Style"
  fi
fi

### Known exceptions
### GNU chmod dereferences symlinks on cmdline args but ignores them during
### -R traversal, and an intermediate symlink in the operand path is resolved
### by the kernel regardless. tcpdf and its cache child are both names the
### tenant can plant under the 02775 libraries/. Precheck both, as the
### nightly does; a real directory is treated exactly as before.
if [ ! -L "${drupal_root}/sites/all/libraries/tcpdf" ] \
  && [ ! -L "${drupal_root}/sites/all/libraries/tcpdf/cache" ]; then
  chmod -R 775 ${drupal_root}/sites/all/libraries/tcpdf/cache &> /dev/null
fi
_chmod_safe 0644 "${drupal_root}/.htaccess"

echo "Done setting proper permissions on platform files and directories."
