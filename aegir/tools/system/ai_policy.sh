#!/bin/bash

# ai_policy.sh — per-site AI bot policy.  Turns the global AI defaults on/off
# per site by generating nginx server-scope fragments from a user-space control
# file, exactly like ip_access.sh does for IP allow/deny.
#
# Global defaults (set in the Provision nginx templates):
#   AI training crawlers       -> blocked
#   AI search/user/utility     -> allowed + rate-limited
#
# Per-site opt-ins (control-file flags), each toggling one of those:
#   train-allow    -> allow AI training for this site   (set $ai_train_allow 1)
#   search-block   -> block AI search crawlers          (if $is_ai_search  444)
#   user-block     -> block AI user-triggered fetchers  (if $is_ai_user    444)
#   utility-block  -> block AI utility bots             (if $is_ai_utility 444)
#
# A site with no record gets no fragment (the empty-glob include is a no-op) and
# keeps the global defaults.  Fragments are included at server scope before
# nginx_vhost_common.conf, so the per-site $ai_train_allow set / if-return guards
# evaluate ahead of the global guards.  A site gets the include LINE on its next
# vhost re-verify (a Provision change); this tool then writes/refreshes the
# fragment and reloads nginx for fast control-file turnaround.

_aegir_health_check="/var/aegir/.drush/hm.alias.drushrc.php"
_drush_health_check="/var/aegir/drush/drush"
_ctrl_dir="/var/aegir/control/ai"
_input_file="${_ctrl_dir}/policy.txt"
_nginx_ai_path="/var/aegir/config/includes/ai_policy"
_backup_dir="/var/aegir/undo"
_current_backup_file="${_backup_dir}/.nginx_ai_policy.current.bak.tar.gz"
_last_good_backup_file="${_backup_dir}/.nginx_ai_policy.last_good.bak.tar.gz"
_timestamp_file="${_nginx_ai_path}/.policy_last_mod_time"
_version_file="${_nginx_ai_path}/.emit_version"
_lock_file="/run/ai_policy.lock"

# Bump when the emitted directive shape changes, to force a regeneration
# independent of the control-file mtime.
_emit_version="1"

# Validate site names the same way ip_access.sh does.
_site_name_regex="^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}$"

if [[ ! -f "${_aegir_health_check}" ]] || [[ ! -x "${_drush_health_check}" ]]; then
  echo "Server is not ready yet. Exiting."
  exit 1
fi

# Re-entrancy guard: skip this tick if a previous run is still active.
exec 9>"${_lock_file}" 2>/dev/null
if ! flock -n 9; then
  echo "Another ai_policy run is active. Skipping."
  exit 0
fi

mkdir -p "${_backup_dir}" "${_ctrl_dir}" "${_nginx_ai_path}"

# Seed a documented, empty control file if absent.
if [[ ! -f "${_input_file}" ]]; then
  {
    echo "# Per-site AI bot policy.  One record per line:"
    echo "#   <site>  [train-allow] [search-block] [user-block] [utility-block]"
    echo "#"
    echo "# Default (no record): AI training blocked; AI search/user/utility"
    echo "# allowed + rate-limited.  Flags above flip one default for that site."
  } > "${_input_file}"
fi

# Change-gate: regenerate only when the control file changed or the emit
# version moved.  Mirrors ip_access.sh; never keyed on anything but this file.
_current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null)
if [[ $? -ne 0 ]]; then
  echo "Failed to stat ${_input_file}. Exiting."
  exit 1
fi
_last_mod_time=0
[[ -f "${_timestamp_file}" ]] && _last_mod_time=$(cat "${_timestamp_file}" 2>/dev/null || echo 0)
_last_version=""
[[ -f "${_version_file}" ]] && _last_version=$(cat "${_version_file}" 2>/dev/null || echo "")
if [[ "${_current_mod_time}" -le "${_last_mod_time}" && "${_last_version}" == "${_emit_version}" ]]; then
  echo "No changes in ${_input_file} (emit version unchanged). Exiting."
  exit 0
fi

# Backup current fragments before regenerating.
if [[ -d "${_nginx_ai_path}" ]]; then
  tar -czf "${_current_backup_file}" -C "${_nginx_ai_path}" . 2>/dev/null
fi

_configured_sites=()

_generate_fragments() {
  local _line _site_name _flag _body _frag _tmp
  while IFS= read -r _line; do
    # Strip trailing comments and skip blank lines.
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue

    read -ra _fields <<< "${_line}"
    _site_name=$(echo "${_fields[0]}" | tr '[:upper:]' '[:lower:]')
    if [[ ! ${_site_name} =~ ${_site_name_regex} ]]; then
      echo "Invalid site name: ${_site_name}. Skipping."
      continue
    fi

    _body=""
    for _flag in "${_fields[@]:1}"; do
      case "${_flag}" in
        train-allow)   _body+="set \$ai_train_allow 1;"$'\n' ;;
        search-block)  _body+="if (\$is_ai_search)  { return 444; }"$'\n' ;;
        user-block)    _body+="if (\$is_ai_user)    { return 444; }"$'\n' ;;
        utility-block) _body+="if (\$is_ai_utility) { return 444; }"$'\n' ;;
        *) echo "Unknown policy flag '${_flag}' for ${_site_name}. Skipping flag." ;;
      esac
    done

    if [[ -z "${_body}" ]]; then
      echo "No valid policy flags for ${_site_name}; no fragment written."
      continue
    fi

    _frag="${_nginx_ai_path}/${_site_name}.conf"
    # Leading-dot tmp so the per-site include glob (<site>*) never matches it;
    # same-dir so the install mv is atomic.
    _tmp="${_nginx_ai_path}/.${_site_name}.tmp.$$"
    {
      echo "# Generated by /var/xdrago/ai_policy.sh — DO NOT EDIT BY HAND."
      echo "# Per-site AI policy for ${_site_name}."
      printf '%s' "${_body}"
    } > "${_tmp}"
    mv -f "${_tmp}" "${_frag}"
    _configured_sites+=("${_site_name}")
  done < "${_input_file}"
}

# Remove fragments for sites no longer present in the control file (opt-out).
_prune_fragments() {
  local _f _base _s _keep
  for _f in "${_nginx_ai_path}"/*.conf; do
    [[ -e "${_f}" ]] || continue
    _base=$(basename "${_f}" .conf)
    _keep=""
    for _s in "${_configured_sites[@]}"; do
      [[ "${_s}" == "${_base}" ]] && _keep="yes" && break
    done
    if [[ -z "${_keep}" ]]; then
      rm -f "${_f}"
      echo "Pruned stale AI policy fragment: ${_base}.conf"
    fi
  done
}

_revert() {
  if [[ -f "${_last_good_backup_file}" ]]; then
    echo "Reverting to the last known good AI policy."
    rm -f "${_nginx_ai_path}"/*.conf
    tar -xzf "${_last_good_backup_file}" -C "${_nginx_ai_path}" 2>/dev/null
    service nginx reload
  else
    echo "No last-good backup to revert to. Manual intervention required."
  fi
}

_generate_fragments
_prune_fragments

# Validate the whole nginx config; revert on failure.
_configtest=$(service nginx configtest 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Nginx configtest failed after AI policy update: ${_configtest}"
  _revert
  exit 1
fi

if ! service nginx reload; then
  echo "Nginx reload failed after AI policy update."
  _revert
  exit 1
fi

# Success: refresh the last-good backup and the change-gate markers.
tar -czf "${_last_good_backup_file}" -C "${_nginx_ai_path}" . 2>/dev/null
echo "${_current_mod_time}" > "${_timestamp_file}"
echo "${_emit_version}" > "${_version_file}"
echo "AI policy updated for ${#_configured_sites[@]} site(s); Nginx reloaded."
exit 0
