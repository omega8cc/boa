#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to lock permissions on local Drush. You need
to provide the following argument:

  --root: Path to the root of your Drupal installation.
  --mode: Action mode lock/unlock (defaults to 'lock')

Usage: (sudo) ${0##*/} --root=PATH --mode=MODE
Example: (sudo) ${0##*/} --drupal_path=/var/aegir/platforms/drupal-10.1
HELP
exit 0
}

if [ $(id -u) != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

drupal_root=${1%/}
lock_mode=${2:-lock}

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root=*)
        drupal_root="${1#*=}"
        ;;
    --mode=*)
        mode="${1#*=}"
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

cd ${drupal_root}

if [ -e "${drupal_root}/core" ]; then
  if [ -e "${drupal_root}/vendor" ]; then
    if [ "$mode" = "unlock" ]; then
      printf "Unlocking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
      chmod 0755 ${drupal_root}/vendor/drush
      chmod 0755 ${drupal_root}/vendor/symfony/console/Input
    else
      printf "Locking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
      chmod 0400 ${drupal_root}/vendor/drush
      chmod 0400 ${drupal_root}/vendor/symfony/console/Input
    fi
  elif [ -e "${drupal_root}/../vendor" ]; then
    if [ "$mode" = "unlock" ]; then
      printf "Unlocking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
      chmod 0755 ${drupal_root}/../vendor/drush
      chmod 0755 ${drupal_root}/../vendor/symfony/console/Input
    else
      printf "Locking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
      chmod 0400 ${drupal_root}/../vendor/drush
      chmod 0400 ${drupal_root}/../vendor/symfony/console/Input
    fi
  fi
  if [ "$mode" = "unlock" ]; then
    echo "Done Unlocking Drush and Symfony Console Input."
  else
    echo "Done Locking Drush and Symfony Console Input."
  fi
fi


