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
  local _resolved
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || {
    printf "Error: path does not resolve: %s\n" "$1" >&2
    exit 1
  }
  case "${_resolved}/" in
    /var/aegir/*|/data/disk/*|/home/*)
      ;;
    *)
      printf "Error: path outside allowed roots (/var/aegir, /data/disk, /home): %s\n" "${_resolved}" >&2
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

if [ -z "${drupal_root}" ] \
  || [ ! -d "${drupal_root}/sites" ] \
  || [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
    printf "Error: Please provide a valid Drupal root directory.\n"
    exit 1
fi

_validate_path_prefix "${drupal_root}"

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

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
find ${drupal_root}/{modules,themes,libraries,includes,misc,profiles,core} -type d -exec chmod 02775 {} \;

printf "Setting permissions of all codebase files inside "${drupal_root}"...\n"
find ${drupal_root}/{modules,themes,libraries,includes,misc,profiles,core} -type f -exec chmod 0664 {} \;

if [ -e "${drupal_root}/core/modules/workspaces_ui" ]; then
  printf "Removing all .drush.inc files inside codebase "${drupal_root}"...\n"
  find ${drupal_root}/modules/contrib -type f -name "*.drush.inc" -exec rm -f {} \;
  find ${drupal_root}/sites/*/modules -type f -name "*.drush.inc" -exec rm -f {} \;
fi

if [ -e "${drupal_root}/vendor" ]; then
  printf "Setting permissions of all codebase directories inside "${drupal_root}/vendor"...\n"
  find ${drupal_root}/vendor -type d -exec chmod 02775 {} \;
  printf "Setting permissions of all codebase files inside "${drupal_root}/vendor"...\n"
  find ${drupal_root}/vendor -type f -exec chmod 0664 {} \;
elif [ -e "${drupal_root}/../vendor" ]; then
  printf "Setting permissions of all codebase directories inside "${drupal_root}/../vendor"...\n"
  find ${drupal_root}/../vendor -type d -exec chmod 02775 {} \;
  printf "Setting permissions of all codebase files inside "${drupal_root}/../vendor"...\n"
  find ${drupal_root}/../vendor -type f -exec chmod 0664 {} \;
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

[ -d "${drupal_root}" ] && _chmod_safe 02775 "${drupal_root}"

if [ -d "${drupal_root}/web" ]; then
  _chmod_safe 02775 "${drupal_root}/web"
elif [ -d "${drupal_root}/docroot" ]; then
  _chmod_safe 02775 "${drupal_root}/docroot"
elif [ -d "${drupal_root}/html" ]; then
  _chmod_safe 02775 "${drupal_root}/html"
fi

printf "Setting permissions of all codebase directories inside "${drupal_root}/sites/all"...\n"
find ${drupal_root}/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \;

printf "Setting permissions of all codebase files inside "${drupal_root}/sites/all"...\n"
find ${drupal_root}/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \;

_chmod_safe 0644 ${drupal_root}/*.php
_chmod_safe 0664 "${drupal_root}/autoload.php"
_chmod_safe 0751 "${drupal_root}/sites"
_chmod_safe 0755 ${drupal_root}/sites/*
_chmod_safe 0644 ${drupal_root}/sites/*.php
_chmod_safe 0644 ${drupal_root}/sites/*.txt
_chmod_safe 0644 ${drupal_root}/sites/*.yml
_chmod_safe 0755 "${drupal_root}/sites/all/drush"

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
### -R traversal. Precheck the cmdline path to avoid a symlink redirect; the
### recursive descent below is then safe.
if [ ! -L "${drupal_root}/sites/all/libraries/tcpdf/cache" ]; then
  chmod -R 775 ${drupal_root}/sites/all/libraries/tcpdf/cache &> /dev/null
fi
_chmod_safe 0644 "${drupal_root}/.htaccess"

echo "Done setting proper permissions on platform files and directories."
