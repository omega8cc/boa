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

if [ $(id -u) != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

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

_TODAY=$(date +%y%m%d 2>&1)
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
  chmod 0775 ${drupal_root}/vendor/bin/drush
elif [ -e "${drupal_root}/../vendor/bin/drush" ]; then
  chmod 0775 ${drupal_root}/../vendor/bin/drush
fi

if [ -e "${drupal_root}/vendor/drush/drush/drush.php" ]; then
  chmod 0775 ${drupal_root}/vendor/drush/drush/drush.php
  chmod 0775 ${drupal_root}/vendor/drush/drush/drush
elif [ -e "${drupal_root}/../vendor/drush/drush/drush.php" ]; then
  chmod 0775 ${drupal_root}/../vendor/drush/drush/drush.php
  chmod 0775 ${drupal_root}/../vendor/drush/drush/drush
fi

printf "Setting permissions of all codebase directories inside "${drupal_root}/sites/all"...\n"
find ${drupal_root}/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \;

printf "Setting permissions of all codebase files inside "${drupal_root}/sites/all"...\n"
find ${drupal_root}/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \;

chmod 0644 ${drupal_root}/*.php
chmod 0664 ${drupal_root}/autoload.php
chmod 0751 ${drupal_root}/sites
chmod 0755 ${drupal_root}/sites/*
chmod 0644 ${drupal_root}/sites/*.php
chmod 0644 ${drupal_root}/sites/*.txt
chmod 0644 ${drupal_root}/sites/*.yml
chmod 0755 ${drupal_root}/sites/all/drush

### Lock Local Drush and Symfony Console Input
if [ -e "${drupal_root}/core" ]; then
  if [ -e "${drupal_root}/vendor" ]; then
    printf "Locking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
    chmod 0400 ${drupal_root}/vendor/drush
    chmod 0400 ${drupal_root}/vendor/symfony/console/Input
  elif [ -e "${drupal_root}/../vendor" ]; then
    printf "Locking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
    chmod 0400 ${drupal_root}/../vendor/drush
    chmod 0400 ${drupal_root}/../vendor/symfony/console/Input
  fi
fi

### Known exceptions
chmod -R 775 ${drupal_root}/sites/all/libraries/tcpdf/cache &> /dev/null
chmod 0644 ${drupal_root}/.htaccess

echo "Done setting proper permissions on platform files and directories."
