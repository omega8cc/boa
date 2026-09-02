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
      /var/aegir/*) _SCOPE_ROOT="/var/aegir" ;;
      /data/disk/*) _SCOPE_ROOT="/data/disk" ;;
      /home/*)      _SCOPE_ROOT="/home" ;;
      *)
        printf "Error: path outside allowed roots (/var/aegir, /data/disk, /home): %s\n" "${_resolved}" >&2
        exit 1
        ;;
    esac
    _ROOT_RESOLVED="${_resolved}"
    return 0
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
  # Publish what was validated so every later op is pinned to it.
  _ROOT_RESOLVED="${_resolved}"
  _SCOPE_ROOT="${_home}"
}

_chmod_safe() {
  local _mode=$1
  shift
  local _p _r
  for _p in "$@"; do
    [ -L "${_p}" ] && continue
    [ -e "${_p}" ] || continue
    # -L guards the FINAL component only: a tenant-planted INTERMEDIATE (vendor,
    # vendor/symfony) still points this root chmod out of the validated tree, so
    # re-check the resolved target against the scope _validate_path_prefix set.
    [ -n "${_SCOPE_ROOT}" ] || continue
    _r=$(realpath -e -- "${_p}" 2>/dev/null) || continue
    case "${_r}/" in
      "${_SCOPE_ROOT}"/*) ;;
      *)
        printf "Error: refusing out-of-scope path %s -> %s\n" "${_p}" "${_r}" >&2
        continue
        ;;
    esac
    chmod "${_mode}" "${_p}"
  done
}

# Positional invocation is rejected by the parser below; both values come from
# the named flags, and 'lock' is the documented default.
drupal_root=""
mode="lock"

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

# Grouped on purpose: && and || bind equally left-to-right, so without the
# braces the whole verdict hangs on the D7 marker alone.
if [ -z "${drupal_root}" ] \
  || [ ! -d "${drupal_root}/sites" ] \
  || { [ ! -f "${drupal_root}/core/modules/system/system.module" ] \
    && [ ! -f "${drupal_root}/modules/system/system.module" ]; }; then
    printf "Error: Please provide a valid Drupal root directory.\n"
    exit 1
fi

# Set by _validate_path_prefix; empty means "not validated" and _chmod_safe
# refuses rather than falling open.
_ROOT_RESOLVED=""
_SCOPE_ROOT=""
_validate_path_prefix "${drupal_root}"
# Operate on the path that was actually validated: a relative --root would be
# re-resolved against the NEW cwd after the cd below, and a --root swapped for a
# symlink after the realpath check would be followed by every raw-path op.
drupal_root="${_ROOT_RESOLVED}"

cd "${drupal_root}" || exit 1

if [ -e "${drupal_root}/core" ]; then
  if [ -e "${drupal_root}/vendor" ]; then
    if [ "$mode" = "unlock" ]; then
      printf "Unlocking Drush and Symfony Console Input in "${drupal_root}/vendor"...\n"
      _chmod_safe 0775 "${drupal_root}/vendor/drush"
      _chmod_safe 0775 "${drupal_root}/vendor/symfony/console/Input"
      _chmod_safe 0775 "${drupal_root}/vendor/symfony/console/Style"
    else
      printf "Locking Drush and Symfony Console Input in %s...\n" "${drupal_root}/vendor"
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


