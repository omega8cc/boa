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

if [ "$(id -u)" != 0 ]; then
  printf "Error: You must run this with sudo or root.\n"
  exit 1
fi

# Reject any caller-supplied path that resolves outside the BOA-managed roots.
# The script is invoked via NOPASSWD sudo by aegir and per-Octopus admin users;
# a crafted symlink under ${site_path}/... (e.g. uploaded inside a tar archive)
# would otherwise let chown -R rewrite ownership on arbitrary system paths.
# Defence is two-layered:
#  1. _validate_path_prefix on the caller-supplied root.
#  2. chown -h on every recursive/non-recursive call below (replaces the prior
#     chown -L -R which explicitly dereferenced symlinks during traversal).
#     This is compatible with any root-managed symlinks within the tree —
#     their own metadata is adjusted but their targets are never followed.
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

_store_dir() {
  # Echo the directory to walk for a per-site files/ or private/ store, or
  # nothing (the caller then skips it). These are LEGITIMATELY symlinks --
  # autosymlink points them at <account>/static/files/<site>/<type>, and
  # static/files may itself be a symlink to a dedicated disk -- so they cannot
  # be refused outright. But the tenant owns ~/static and can own the site dir
  # itself (sites/ is 02771 on tenant codebases), so both the link and its
  # target are plantable: accept a real directory, or a link that resolves
  # inside THIS account's own resolved store root -- the same "never another
  # account's tree" rule _validate_path_prefix applies to the site path.
  local _p _acct _root _res
  _p="$1"
  [ -d "${_p}" ] || return 1
  if [ ! -L "${_p}" ]; then
    printf '%s' "${_p}"
    return 0
  fi
  case "${site_path}/" in
    /var/aegir/*)
      _acct="/var/aegir"
      ;;
    /data/disk/*/*)
      _acct="${site_path#/data/disk/}"
      _acct="/data/disk/${_acct%%/*}"
      ;;
    *)
      return 1
      ;;
  esac
  _root=$(realpath -e -- "${_acct}/static/files" 2>/dev/null) || return 1
  _res=$(realpath -e -- "${_p}" 2>/dev/null) || return 1
  case "${_res}/" in
    "${_root}"/*) ;;
    *) return 1 ;;
  esac
  printf '%s' "${_res}"
}

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

### Resolve the caller-supplied path ONCE, before any check or operation reads
### it: every branch below re-walks the raw argument, and sites/ is 02771 on
### tenant codebases, so the tenant owns the name it was handed and could
### re-point it between _validate_path_prefix and the chowns.
if [ -n "${site_path}" ] && [ -e "${site_path}" ]; then
  site_path=$(realpath -e -- "${site_path}" 2>/dev/null) || site_path=""
fi

# --- Grav 2 site capsule (boa-grav D-003) ------------------------------------
# A capsule is a full Grav install at sites/<uri>/ with no settings.php;
# detect it positively and run the capsule ownership model instead of
# refusing (union seam: further foreign-CMS branches join here the same way).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/bin/grav" ] \
  && [ -f "${site_path}/system/defines.php" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
    printf "Error: Please provide a valid user.\n"
    exit 1
  fi
  _validate_path_prefix "${site_path}"
  # Capsule ownership model (spike-proven): code <user>:users; the writable
  # set <user>:<web_group> so FPM writes via GROUP (version-flip-immune).
  printf "Setting Grav ownership of %s to: user => %s group => users\n" "${site_path}" "${script_user}"
  chown -h -R ${script_user}:users ${site_path}
  for _wd in user cache logs tmp backup images assets; do
    [ -d "${site_path}/${_wd}" ] || continue
    chown -h -R ${script_user}:${web_group:-www-data} "${site_path}/${_wd}"
  done
  # The root .env drops its world bit under D-008, so FPM's read comes via
  # the web group -- the code pass above homed it to :users.
  [ -f "${site_path}/.env" ] \
    && chown -h ${script_user}:${web_group:-www-data} "${site_path}/.env"
  echo "Done setting proper ownership of files and directories (Grav site)."
  exit 0
fi

# --- Textpattern multisite site (boa-txp D-002) -------------------------------
# A TXP site is sites/<uri>/{admin,private,public} with no settings.php; detect
# it positively and run the TXP ownership model instead of refusing (union seam
# shared with the Grav branch above; further foreign CMSes join the same way).
if [ -n "${site_path}" ] \
  && [ -f "${site_path}/public/index.php" ] \
  && [ -f "${site_path}/public/css.php" ] \
  && [ -d "${site_path}/admin" ] \
  && [ ! -f "${site_path}/settings.php" ]; then
  if [ -z "${script_user}" ] \
    || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
    printf "Error: Please provide a valid user.\n"
    exit 1
  fi
  _validate_path_prefix "${site_path}"
  # Code <user>:users; the writable set and the credential store
  # <user>:<web_group> so FPM reaches them via GROUP (version-flip-immune: a
  # box-default PHP bump changes the pool USER, never its www-data group).
  # -h keeps the four load-bearing admin symlinks as symlinks and never
  # follows them into the shared core.
  printf "Setting Textpattern ownership of %s to: user => %s group => users\n" "${site_path}" "${script_user}"
  chown -h -R ${script_user}:users ${site_path}
  for _wd in tmp modules admin/plugins public/files public/images public/themes private; do
    [ -d "${site_path}/${_wd}" ] || continue
    chown -h -R ${script_user}:${web_group:-www-data} "${site_path}/${_wd}"
  done
  echo "Done setting proper ownership of files and directories (Textpattern site)."
  exit 0
fi

if [ -z "${site_path}" ] || [ ! -f "${site_path}/settings.php" ]; then
  printf "Error: Please provide a valid Drupal site directory.\n"
  exit 1
fi

if [ -z "${script_user}" ] \
  || [[ $(id -un "${script_user}" 2> /dev/null) != "${script_user}" ]]; then
  printf "Error: Please provide a valid user.\n"
  exit 1
fi

_validate_path_prefix "${site_path}"

### modules, themes and libraries are names the tenant can plant: it can create
### the site dir itself under the group-writable sites/ (02771), and the
### site-level code dirs are 02775 group users. The rm below, the cp -a
### destination and the globs walk THROUGH them, while chown -h protects only
### the final component. None is ever legitimately a symlink at site level.
for _d in modules themes libraries; do
  if [ -L "${site_path}/${_d}" ]; then
    printf "Error: %s is a symlink in %s; refusing.\n" "${_d}" "${site_path}" >&2
    exit 1
  fi
done

if [ -e "${site_path}/libraries/ownership-fixed.pid" ]; then
  rm -f ${site_path}/libraries/ownership-fixed.pid
fi

_TODAY=$(date +%y%m%d)
_TODAY=${_TODAY//[^0-9]/}

if [ -e "${site_path}/../sites/default/default.services.yml" ]; then
  if [ ! -e "${site_path}/modules/default.services.yml" ]; then
    cp -a ${site_path}/../sites/default/default.services.yml ${site_path}/modules/
  fi
fi
if [ -e "${site_path}/modules/services.yml" ] && [ ! -e "${site_path}/services.yml" ]; then
  ln -sfn ${site_path}/modules/services.yml ${site_path}/services.yml
fi

cd ${site_path}
printf "Setting ownership of key files and directories inside "${site_path}" to: user => "${script_user}"\n"
if [ ! -e "${site_path}/libraries" ]; then
  mkdir ${site_path}/libraries
fi
### directory and settings files - site level
chown -h ${script_user}:users ${site_path} &> /dev/null
chown -h ${script_user}:www-data \
  ${site_path}/{local.settings.php,settings.php,civicrm.settings.php,solr.php} &> /dev/null
### modules,themes,libraries - site level
chown -h -R ${script_user}:users \
  ${site_path}/{modules,themes,libraries}/* &> /dev/null
chown -h ${script_user}:users \
  ${site_path}/drushrc.php \
  ${site_path}/modules/*.yml \
  ${site_path}/{modules,themes,libraries} &> /dev/null

### files/ and private/ are LEGITIMATELY symlinks into the per-account static
### store, so every path below walks THROUGH them and chown -h protects only
### the final component: a link planted at either name aims these chowns at,
### say, /var/aegir/config -- whose nginx vhosts the tenant may then rewrite,
### with `sudo /etc/init.d/nginx` already granted. Resolve each store once,
### bounded to this account's own store root, and operate on the resolved dir.
_files_dir=$(_store_dir "${site_path}/files") || _files_dir=""
_priv_dir=$(_store_dir "${site_path}/private") || _priv_dir=""
if [ -z "${_files_dir}" ] && [ -e "${site_path}/files" ]; then
  printf "Notice: %s is not this account's own files store; skipping.\n" \
    "${site_path}/files" >&2
fi

if [ -n "${_files_dir}" ] \
  && [ ! -e "${_files_dir}/ownership-fixed-${_TODAY}.pid" ]; then
  ### ctrl pid
  rm -f ${_files_dir}/ownership-fixed*.pid
  touch ${_files_dir}/ownership-fixed-${_TODAY}.pid
  ### files - site level
  ### -h on recursive chown: never dereference symlinks; combined with default
  ### -P traversal this prevents a tar-uploaded symlink from rerouting chown
  ### to a system path.
  chown -h -R ${script_user}:www-data ${_files_dir} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir}/{tmp,images,pictures,css,js} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir}/{advagg_css,advagg_js,ctools} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir}/{ctools/css,imagecache,locations} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir}/{xmlsitemap,deployment,styles,private} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir}/{civicrm,civicrm/templates_c} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir}/{civicrm/upload,civicrm/persist} &> /dev/null
  chown -h ${script_user}:www-data ${_files_dir}/{civicrm/custom,civicrm/dynamic} &> /dev/null
  ### private - site level
  if [ -n "${_priv_dir}" ]; then
    chown -h -R ${script_user}:www-data ${_priv_dir} &> /dev/null
    chown -h ${script_user}:www-data ${_priv_dir} &> /dev/null
    chown -h ${script_user}:www-data ${_priv_dir}/{files,temp} &> /dev/null
    chown -h ${script_user}:www-data ${_priv_dir}/files/backup_migrate &> /dev/null
    chown -h ${script_user}:www-data ${_priv_dir}/files/backup_migrate/{manual,scheduled} &> /dev/null
    chown -h -R ${script_user}:www-data ${_priv_dir}/config &> /dev/null
  fi
fi

echo "Done setting proper ownership of site files and directories."
