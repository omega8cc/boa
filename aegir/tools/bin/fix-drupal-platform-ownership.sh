#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script is used to fix the file ownership of a Drupal platform. You need to
provide the following arguments:

  --root: Path to the root of your Drupal installation.
  --script-user: Username of the user to whom you want to give file ownership
                 (defaults to 'aegir').
  --web-group: Web server group name (defaults to 'www-data').

Usage: (sudo) ${0##*/} --root=PATH --script-user=USER --web_group=GROUP
Example: (sudo) ${0##*/} --drupal_path=/var/aegir/platforms/drupal-7.50 --script-user=aegir --web-group=www-data
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# Reject any caller-supplied path that resolves outside the BOA-managed roots.
# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users;
# a crafted symlink under ${drupal_root}/... would otherwise let chown -R
# rewrite ownership on arbitrary system paths. Defence is two-layered:
#  1. _validate_path_prefix on the caller-supplied root.
#  2. chown -h on every recursive/non-recursive call below, so symlinks
#     planted under the validated tree (e.g. via uploaded tar archives) have
#     their own metadata adjusted but their targets are never dereferenced.
#     This is compatible with legacy BOA platforms that legitimately use a
#     root-managed symlink for shared core/ — those are skipped, not broken.
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

drupal_root=${1%/}
script_user=${2:-aegir}
web_group="${3:-www-data}"

# Parse Command Line Arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root=*)
        drupal_root="${1#*=}"
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

if [ -z "${drupal_root}" ] \
  || [ ! -d "${drupal_root}/sites" ] \
  || [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
    printf "Error: Please provide a valid Drupal root directory.\n"
    exit 1
fi

if [ -z "${script_user}" ] \
  || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
    printf "Error: Please provide a valid user.\n"
    exit 1
fi

_validate_path_prefix "${drupal_root}"

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

### Fix ownership only once daily, unless it's Drupal 8 or newer
if [ -e "${drupal_root}/sites/all/libraries/ownership-fixed-${_TODAY}.pid" ]; then
  if [ -e "${drupal_root}/core/themes/olivero" ] \
    || [ ! -e "${drupal_root}/core/themes/classy" ]; then
    _drupal_eight_nine_ten=TRUE
  else
    exit 0
  fi
fi

cd ${drupal_root}

printf "Setting ownership of "${drupal_root}" to: user => "${script_user}" group => "users"\n"
chown -h ${script_user}:users ${drupal_root}

### Make sure that expected sites/all sub-directories exist
mkdir -p ${drupal_root}/sites/all/{modules,themes,libraries,drush}

### Create ctrl pid
rm -f ${drupal_root}/sites/all/libraries/ownership-fixed*.pid
touch ${drupal_root}/sites/all/libraries/ownership-fixed-${_TODAY}.pid

### BOA specific path and logic for limited user own codebases
if [[ "${drupal_root}" =~ "/static/" ]] && [ -e "${drupal_root}/core" ]; then
  rm -f ${drupal_root}/sites/development.services.yml
fi

### -h on every chown: never dereference symlinks (legacy BOA-managed
### shared-core symlinks under /var/aegir/distro/ stay untouched; attacker
### symlinks planted under /data/disk/<o>/ or /home/<u>/ via uploaded tar
### archives cannot redirect chown onto system paths).
if [ -e "${drupal_root}/vendor" ]; then
  chown -h -R ${script_user}:users ${drupal_root}/vendor
elif [ -e "${drupal_root}/../vendor" ]; then
  chown -h -R ${script_user}:users ${drupal_root}/../vendor
fi

chown -h -R ${script_user}:users \
  ${drupal_root}/sites/all/{modules,themes,libraries,drush}

chown -h -R ${script_user}:users \
  ${drupal_root}/{modules,themes,libraries,includes,misc,profiles,core}

chown -h ${script_user}:users \
  ${drupal_root}/sites/all/drush/drushrc.php \
  ${drupal_root}/sites \
  ${drupal_root}/sites/* \
  ${drupal_root}/sites/sites.php \
  ${drupal_root}/sites/all

### known exceptions
chown -h -R ${script_user}:www-data \
  ${drupal_root}/sites/all/libraries/tcpdf/cache &> /dev/null

echo "Done setting proper ownership of platform files and directories."
