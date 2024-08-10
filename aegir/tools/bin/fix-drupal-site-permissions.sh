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

if [ $(id -u) != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

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

_TODAY=$(date +%y%m%d 2>&1)
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
find ${site_path}/*.php -type f -exec chmod 0440 {} \; &> /dev/null
chmod 0640 ${site_path}/civicrm.settings.php &> /dev/null
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
  chmod 02775 ${site_path}/files &> /dev/null
  ### private - site level
  find ${site_path}/private/ -type d -exec chmod 02775 {} \; &> /dev/null
  find ${site_path}/private/ -type f -exec chmod 0664 {} \; &> /dev/null
  ### known exceptions
  chmod 0644 ${site_path}/files/.htaccess
fi

echo "Done setting proper permissions on site files and directories."
