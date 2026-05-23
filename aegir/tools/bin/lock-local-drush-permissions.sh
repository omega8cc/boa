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

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# Same defence pattern as the fix-drupal-* helpers. Without this, a symlink
# planted at ${drupal_root}/vendor/drush could let the caller chmod 0775 or
# chmod 0400 arbitrary system paths via the NOPASSWD sudo entry point.
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

_validate_path_prefix "${drupal_root}"

cd ${drupal_root}

if [ -e "${drupal_root}/core" ]; then
  if [ -e "${drupal_root}/vendor" ]; then
    if [ "$mode" = "unlock" ]; then
      printf "Unlocking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
      _chmod_safe 0775 "${drupal_root}/vendor/drush"
      _chmod_safe 0775 "${drupal_root}/vendor/symfony/console/Input"
      _chmod_safe 0775 "${drupal_root}/vendor/symfony/console/Style"
    else
      printf "Locking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
      _chmod_safe 0400 "${drupal_root}/vendor/drush"
      _chmod_safe 0400 "${drupal_root}/vendor/symfony/console/Input"
      _chmod_safe 0400 "${drupal_root}/vendor/symfony/console/Style"
    fi
  elif [ -e "${drupal_root}/../vendor" ]; then
    if [ "$mode" = "unlock" ]; then
      printf "Unlocking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
      _chmod_safe 0775 "${drupal_root}/../vendor/drush"
      _chmod_safe 0775 "${drupal_root}/../vendor/symfony/console/Input"
      _chmod_safe 0775 "${drupal_root}/../vendor/symfony/console/Style"
    else
      printf "Locking Drush and Symfony Console Input in "${drupal_root}/../vendor"...\n"
      _chmod_safe 0400 "${drupal_root}/../vendor/drush"
      _chmod_safe 0400 "${drupal_root}/../vendor/symfony/console/Input"
      _chmod_safe 0400 "${drupal_root}/../vendor/symfony/console/Style"
    fi
  fi
  if [ "$mode" = "unlock" ]; then
    echo "Done Unlocking Drush and Symfony Console Input."
  else
    echo "Done Locking Drush and Symfony Console Input."
  fi
fi


