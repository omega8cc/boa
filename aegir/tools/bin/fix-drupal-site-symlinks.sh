#!/bin/bash

# Help menu
print_help() {
cat <<-HELP
This script converts a single Drupal site's files/private directories into
symlinks pointing at the per-account static store, by invoking the BOA
autosymlink tool in its narrow single-site mode. It is the NOPASSWD-sudo entry
point used by Provision (clone task) so the unprivileged Ægir/Octopus user can
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

# Caller-scope: an Octopus tenant may only convert a site that lives in ITS OWN
# account tree. autosymlink narrow mode trusts a caller-supplied --account
# (_ACCOUNT_DIR=/data/disk/<account>) and, when it is omitted, resolves the owner
# by scanning every /data/disk/* -- so without this gate tenant o1 could pass a
# victim --site (and/or --account=o2) to drive this root-run conversion/unshare
# against another tenant. Derive the sudo identity: a per-tenant caller (home
# /data/disk/oN) may only act on a site whose Drush alias -- the authoritative
# "owned here" marker -- exists under its OWN account, and any explicit --account
# must name it. aegir (master) and a direct root run are trusted. Rejection here
# is non-fatal to Provision (it logs a warning and leaves the site as plain dirs).
_caller="${SUDO_USER:-}"
if [ -n "${_caller}" ]; then
  _caller_home=$(getent passwd "${_caller}" 2>/dev/null | cut -d: -f6)
  _caller_home="${_caller_home%/}"
  case "${_caller_home}" in
    /data/disk/*)
      _caller_acct="${_caller_home##*/}"
      if [ -n "${_account}" ] && [ "${_account}" != "${_caller_acct}" ]; then
        printf "Error: --account '%s' is not the caller's own account '%s'.\n" "${_account}" "${_caller_acct}" >&2
        exit 1
      fi
      # -f follows symlinks and ~oN/.drush is owned by the account (owner oN,
      # 0710), so a link planted here would let the caller nominate another
      # account's alias -- and with it another account's site_path; refuse a
      # link that leaves this .drush dir. The account's OWN control panel has
      # no per-site alias of its own: its alias is hostmaster.alias.drushrc.php
      # (the <panel-fqdn> symlink to it was a crutch that manage_ltd_users.sh
      # now purges, and it never existed during the install's first verify),
      # so the panel is recognised by the uri that alias carries.
      _alias_f="/data/disk/${_caller_acct}/.drush/${_site}.alias.drushrc.php"
      _alias_r=$(realpath -e -- "${_alias_f}" 2>/dev/null)
      case "${_alias_r}" in
        "/data/disk/${_caller_acct}/.drush/"*) ;;
        *) _alias_r="" ;;
      esac
      if [ -z "${_alias_r}" ] || [ ! -f "${_alias_r}" ]; then
        _hm_f="/data/disk/${_caller_acct}/.drush/hostmaster.alias.drushrc.php"
        _hm_r=$(realpath -e -- "${_hm_f}" 2>/dev/null)
        case "${_hm_r}" in
          "/data/disk/${_caller_acct}/.drush/"*) ;;
          *) _hm_r="" ;;
        esac
        if [ -n "${_hm_r}" ] && [ -f "${_hm_r}" ]; then
          _hm_uri=$(sed -n "s/.*'uri' *=> *'\([^']*\)'.*/\1/p" "${_hm_r}" 2>/dev/null | head -1)
          if [ -n "${_hm_uri}" ] && [ "${_hm_uri}" = "${_site}" ]; then
            _alias_r="${_hm_r}"
          fi
        fi
      fi
      if [ -z "${_alias_r}" ] || [ ! -f "${_alias_r}" ]; then
        printf "Error: site '%s' is not owned by the caller account '%s'.\n" "${_site}" "${_caller_acct}" >&2
        exit 1
      fi
      ;;
    /var/aegir)
      : # master aegir: trusted (narrow autosymlink only handles /data/disk sites)
      ;;
    *)
      printf "Error: unexpected sudo caller '%s' (home '%s'); refusing.\n" "${_caller}" "${_caller_home}" >&2
      exit 1
      ;;
  esac
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
