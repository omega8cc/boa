#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script converts a single Drupal site's files/private directories into
symlinks pointing at the per-account static store, by invoking the BOA
autosymlink tool in its narrow single-site mode. It is the NOPASSWD-sudo entry
point used by Provision (clone task) so the unprivileged Aegir/Octopus user can
trigger the conversion for ONE site WITHOUT being able to reach autosymlink's
global batch/live modes (which operate on every account on the box).

  --site:    Site URL (e.g. example.com). Required.
  --account: Owning Octopus account dir name (e.g. o1). Optional; autosymlink
             resolves it from the vhost+alias pair when omitted.
  --force-unshare: Break an inherited cross-account files symlink even if a
             share control file exists. Used by the clone task so a freshly
             cloned site gets its own separate copy (it never opted into sharing).

Usage: (sudo) ${0##*/} --site=URL [--account=oNNN] [--force-unshare]
HELP
exit 0
}

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# Fixed, hardcoded target. The caller can only influence WHICH site/account is
# passed through, never the autosymlink mode, so this entry point cannot be
# coaxed into a global batch/live run.
_AUTOSYMLINK="/opt/local/bin/autosymlink"

_site=""
_account=""
_force_unshare="NO"

# Parse named arguments only; reject anything else fail-closed.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --site=*)    _site="${1#*=}" ;;
    --account=*) _account="${1#*=}" ;;
    --force-unshare) _force_unshare="YES" ;;
    --help)      print_help ;;
    *)
      printf "Error: Invalid argument, run --help for valid arguments.\n"
      exit 1
      ;;
  esac
  shift
done

# Fail-closed token validation (mirror autosymlink narrow mode): reject empty,
# traversal, path separators, and anything outside the expected charset before
# the value is passed to a root-level tool.
case "${_site}" in
  ""|*..*|*/*)
    printf "Error: missing or invalid --site.\n"
    exit 1
    ;;
esac
if ! printf '%s' "${_site}" | grep -qE '^[a-z0-9][a-z0-9._-]*$'; then
  printf "Error: invalid --site token.\n"
  exit 1
fi

if [ -n "${_account}" ]; then
  case "${_account}" in
    *..*|*/*)
      printf "Error: invalid --account.\n"
      exit 1
      ;;
  esac
  if ! printf '%s' "${_account}" | grep -qE '^[A-Za-z0-9._-]+$'; then
    printf "Error: invalid --account token.\n"
    exit 1
  fi
fi

if [ ! -x "${_AUTOSYMLINK}" ]; then
  printf "Error: autosymlink not found at %s\n" "${_AUTOSYMLINK}"
  exit 1
fi

# Narrow single-site apply only. autosymlink itself re-validates the tokens,
# resolves/verifies the owning account by the vhost+alias pair, runs a per-site
# clean dry-run before any change, and never touches the global state file.
# Build the fixed argument list (the parser already consumed our own args).
set -- --site "${_site}"
if [ -n "${_account}" ]; then
  set -- "$@" --account "${_account}"
fi
if [ "${_force_unshare}" = "YES" ]; then
  set -- "$@" --force-unshare
fi
set -- "$@" --apply

exec "${_AUTOSYMLINK}" "$@"
