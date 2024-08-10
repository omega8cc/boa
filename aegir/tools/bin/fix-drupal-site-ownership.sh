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

if [ $(id -u) != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

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

if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
  printf "Error: Please provide a valid Drupal site directory.\n"
  exit 1
fi

if [ -z "${script_user}" ] \
  || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
  printf "Error: Please provide a valid user.\n"
  exit 1
fi

if [ -e "${site_path}/libraries/ownership-fixed.pid" ]; then
  rm -f ${site_path}/libraries/ownership-fixed.pid
fi

_TODAY=$(date +%y%m%d 2>&1)
_TODAY=${_TODAY//[^0-9]/}

if [ -e "${site_path}/../sites/default/default.services.yml" ]; then
  if [ ! -e "${site_path}/modules/default.services.yml" ]; then
    cp -a ${site_path}/../sites/default/default.services.yml ${site_path}/modules/
  fi
fi
if [ -e "${site_path}/modules/services.yml" ] && [ ! -e "${site_path}/services.yml" ]; then
  ln -s ${site_path}/modules/services.yml ${site_path}/services.yml
fi

cd ${site_path}
printf "Setting ownership of key files and directories inside "${site_path}" to: user => "${script_user}"\n"
if [ ! -e "${site_path}/libraries" ]; then
  mkdir ${site_path}/libraries
fi
### directory and settings files - site level
chown ${script_user}:users ${site_path} &> /dev/null
chown ${script_user}:www-data \
  ${site_path}/{local.settings.php,settings.php,civicrm.settings.php,solr.php} &> /dev/null
### modules,themes,libraries - site level
chown -R ${script_user}:users \
  ${site_path}/{modules,themes,libraries}/* &> /dev/null
chown ${script_user}:users \
  ${site_path}/drushrc.php \
  ${site_path}/modules/*.yml \
  ${site_path}/{modules,themes,libraries} &> /dev/null

if [ ! -e "${site_path}/files/ownership-fixed-${_TODAY}.pid" ]; then
  ### ctrl pid
  rm -f ${site_path}/files/ownership-fixed*.pid
  touch ${site_path}/files/ownership-fixed-${_TODAY}.pid
  ### files - site level
  chown -L -R ${script_user}:www-data ${site_path}/files &> /dev/null
  chown ${script_user}:www-data ${site_path}/files &> /dev/null
  chown ${script_user}:www-data ${site_path}/files/{tmp,images,pictures,css,js} &> /dev/null
  chown ${script_user}:www-data ${site_path}/files/{advagg_css,advagg_js,ctools} &> /dev/null
  chown ${script_user}:www-data ${site_path}/files/{ctools/css,imagecache,locations} &> /dev/null
  chown ${script_user}:www-data ${site_path}/files/{xmlsitemap,deployment,styles,private} &> /dev/null
  chown ${script_user}:www-data ${site_path}/files/{civicrm,civicrm/templates_c} &> /dev/null
  chown ${script_user}:www-data ${site_path}/files/{civicrm/upload,civicrm/persist} &> /dev/null
  chown ${script_user}:www-data ${site_path}/files/{civicrm/custom,civicrm/dynamic} &> /dev/null
  ### private - site level
  chown -L -R ${script_user}:www-data ${site_path}/private &> /dev/null
  chown ${script_user}:www-data ${site_path}/private &> /dev/null
  chown ${script_user}:www-data ${site_path}/private/{files,temp} &> /dev/null
  chown ${script_user}:www-data ${site_path}/private/files/backup_migrate &> /dev/null
  chown ${script_user}:www-data ${site_path}/private/files/backup_migrate/{manual,scheduled} &> /dev/null
  chown -L -R ${script_user}:www-data ${site_path}/private/config &> /dev/null
fi

echo "Done setting proper ownership of site files and directories."
