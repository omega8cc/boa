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
  # Scope the resolved path to the SUDO caller's OWN home tree (aegir ->
  # /var/aegir, Octopus oN -> /data/disk/oN), not merely "some BOA tree": a
  # tenant must not drive this root-run chown against another tenant's
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


# --- Grav 2 platform (site capsules; boa-grav D-003) -------------------------
# A Grav root carries no Drupal system.module; detect it positively and run
# the capsule model instead of refusing (union seam: further foreign-CMS
# branches join here the same way).
if [ -n "${drupal_root}" ] \
  && [ -f "${drupal_root}/bin/grav" ] \
  && [ -f "${drupal_root}/system/defines.php" ] \
  && [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
      printf "Error: Please provide a valid user.\n"
      exit 1
  fi
  _validate_path_prefix "${drupal_root}"
  # Capsule ownership model (spike-proven): code <user>:users; the writable
  # set <user>:<web_group> so FPM writes via GROUP (version-flip-immune) --
  # and web-created files are re-homed to the instance user, healing the
  # web-owned residue the lifecycle verbs otherwise have to park.
  printf "Setting Grav ownership of %s to: user => %s group => users\n" "${drupal_root}" "${script_user}"
  chown -h -R ${script_user}:users ${drupal_root}
  for _capsule in ${drupal_root}/sites/*/; do
    [ -f "${_capsule}system/defines.php" ] || continue
    for _wd in user cache logs tmp backup images assets; do
      [ -d "${_capsule}${_wd}" ] || continue
      chown -h -R ${script_user}:${web_group:-www-data} "${_capsule}${_wd}"
    done
    # The root .env drops its world bit under D-008, so FPM's read comes via
    # the web group -- the code pass above homed it to :users.
    [ -f "${_capsule}.env" ] \
      && chown -h ${script_user}:${web_group:-www-data} "${_capsule}.env"
  done
  echo "Done setting proper ownership of files and directories (Grav)."
  exit 0
fi

# --- Textpattern platform (shared core; boa-txp D-002) -----------------------
# A TXP root carries no Drupal system.module; detect it positively (the same
# probe as codebasecheck: textpattern/lib/constants.php + css.php + no core/)
# and run the shared-core model instead of refusing.
if [ -n "${drupal_root}" ] \
  && [ -f "${drupal_root}/textpattern/lib/constants.php" ] \
  && [ -f "${drupal_root}/css.php" ] \
  && [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
  && [ ! -f "${drupal_root}/modules/system/system.module" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
      printf "Error: Please provide a valid user.\n"
      exit 1
  fi
  _validate_path_prefix "${drupal_root}"
  # Shared-core ownership model: the pristine core is <user>:users throughout.
  # Everything under sites/* is the SITE scripts' territory -- those trees
  # carry 0440 group-read secrets (config.php, drushrc.php) and web-group
  # writable dirs the site pass owns; a platform-wide chown would re-home
  # their groups and break FPM's group-read path, so sites/* is pruned
  # outright (only the sites/ directory itself takes core ownership).
  printf "Setting Textpattern ownership of %s to: user => %s group => users\n" "${drupal_root}" "${script_user}"
  find ${drupal_root} -path "${drupal_root}/sites/*" -prune \
    -o -exec chown -h ${script_user}:users {} + 2> /dev/null
  echo "Done setting proper ownership of files and directories (Textpattern platform)."
  exit 0
fi

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

### sites and sites/all are names a tenant can plant as symlinks (the docroot
### is group-writable) and every op below walks THROUGH them; -h protects
### only the final component. A symlinked skeleton is never legitimate.
if [ -L "${drupal_root}/sites" ] || [ -L "${drupal_root}/sites/all" ]; then
  printf "Error: sites or sites/all is a symlink in %s; refusing.\n" "${drupal_root}" >&2
  exit 1
fi

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

### sites/development.services.yml is a core scaffold file. Deleting it
### here (2019) made every later composer run re-scaffold it into the
### oN-owned sites/ directory and fail (omega8cc/boa#1936). Put core's own
### copy back where an earlier run removed it, so the scaffold plugin finds
### it unchanged and never has to write there.
_scaffold_yml="${drupal_root}/core/assets/scaffold/files/development.services.yml"
if [[ "${drupal_root}" =~ "/static/" ]] \
  && [ -f "${_scaffold_yml}" ] && [ ! -L "${_scaffold_yml}" ] \
  && [ ! -e "${drupal_root}/sites/development.services.yml" ] \
  && [ ! -L "${drupal_root}/sites/development.services.yml" ]; then
  cp -a "${_scaffold_yml}" "${drupal_root}/sites/development.services.yml"
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
