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

if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
  printf "Error: Please provide a valid Drupal site directory.\n"
  exit 1
fi

_validate_path_prefix "${site_path}"

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

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
_chmod_safe 0640 "${site_path}/civicrm.settings.php"
### modules,themes,libraries - site level
find ${site_path}/{modules,themes,libraries} -type d -exec \
  chmod 02775 {} \; &> /dev/null
find ${site_path}/{modules,themes,libraries} -type f -exec \
  chmod 0664 {} \; &> /dev/null

if [ ! -e "${site_path}/files/permissions-fixed-${_TODAY}.pid" ]; then
  ### ctrl pid
  rm -f ${site_path}/files/permissions-fixed*.pid
  touch ${site_path}/files/permissions-fixed-${_TODAY}.pid
  ### files - site level
  find ${site_path}/files/ -type d -exec chmod 02775 {} \; &> /dev/null
  find ${site_path}/files/ -type f -exec chmod 0664 {} \; &> /dev/null
  _chmod_safe 02775 "${site_path}/files"
  ### private - site level
  find ${site_path}/private/ -type d -exec chmod 02775 {} \; &> /dev/null
  find ${site_path}/private/ -type f -exec chmod 0664 {} \; &> /dev/null
  ### known exceptions
  _chmod_safe 0644 "${site_path}/files/.htaccess"
fi

echo "Done setting proper permissions on site files and directories."
