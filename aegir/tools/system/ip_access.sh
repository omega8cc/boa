#!/bin/bash

# ip_access.sh — per-site nginx IP allow/deny, GLOBAL across the Aegir master and
# every Octopus instance.  Abstraction of the per-Octopus
# nginx_ip_access_<oct>.sh scripts into one generator.
#
# For each context it reads a control file of `<site>  <ip…>` records and writes
# a per-site nginx include `<site>.conf` (a block of `allow <ip>;` lines + a
# final `deny all;`) into that context's config/includes/ip_access/, which the
# per-vhost template pulls via `include $server->include_path/ip_access/<uri>*`.
# 127.0.0.1, the server's own IP and every currently logged-in SSH IP are always
# allowed (anti-lockout), so an admin / the server can never be shut out.
#
# Control files:
#   master  : /var/aegir/control/ip/access.txt          (the sqladmin proxy)
#   octopus : /data/disk/<oct>/static/control/ip/access.txt
# A site removed from the control file has its fragment pruned (restriction
# lifted).  Record format: `example.com 192.168.1.1 203.0.113.2`.

_aegir_health_check="/var/aegir/.drush/hm.alias.drushrc.php"
_drush_health_check="/var/aegir/drush/drush"
_server_ip_file="/root/.found_correct_ipv4.cnf"
_ipv4_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
_site_name_regex="^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}$"

if [[ ! -f "${_aegir_health_check}" ]] || [[ ! -x "${_drush_health_check}" ]]; then
  echo "Server is not ready yet. Exiting."
  exit 1
fi

# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy) never overlap their
# configtest+reload; wait up to 30s, then skip this run and retry next tick.
exec 9>"/run/boa_nginx_config.lock" 2>/dev/null
if ! flock -w 30 9; then
  echo "Could not acquire the shared nginx-config lock; skipping this run."
  exit 0
fi

# Server's own IP (optional) + currently logged-in SSH IPs (host-wide) feed every
# context's anti-lockout allow list.
_server_ip=""
[[ -f "${_server_ip_file}" ]] && _server_ip=$(cat "${_server_ip_file}" 2>/dev/null)

_get_ssh_ips() {
  who --ips 2>/dev/null \
    | awk '{print $NF}' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -u
}
_ssh_ips=$(_get_ssh_ips)
_ssh_ips_hash=$(echo "${_ssh_ips}" | md5sum | awk '{print $1}')

_process_context() {
  local _input_file="$1" _nginx_path="$2" _backup_dir="$3"
  [[ -f "${_input_file}" ]] || return 0

  local _current_backup="${_backup_dir}/.nginx_access_conf.current.bak.tar.gz"
  local _last_good_backup="${_backup_dir}/.nginx_access_conf.last_good.bak.tar.gz"
  local _timestamp_file="${_nginx_path}/.access_last_mod_time"
  local _ssh_hash_file="${_nginx_path}/.ssh_ips_hash"

  mkdir -p "${_nginx_path}" "${_backup_dir}"

  # Change-gate: regenerate when the control file changed OR the host SSH-IP set
  # changed (so a newly logged-in admin is added to every allow list).
  local _current_mod_time _last_mod_time=0 _previous_ssh_hash=""
  _current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null) || return 0
  [[ -f "${_timestamp_file}" ]] && _last_mod_time=$(cat "${_timestamp_file}" 2>/dev/null || echo 0)
  [[ -f "${_ssh_hash_file}" ]] && _previous_ssh_hash=$(cat "${_ssh_hash_file}" 2>/dev/null || echo "")
  if [[ "${_current_mod_time}" -le "${_last_mod_time}" && "${_ssh_ips_hash}" == "${_previous_ssh_hash}" ]]; then
    return 0
  fi

  [[ -d "${_nginx_path}" ]] && tar -czf "${_current_backup}" -C "${_nginx_path}" . 2>/dev/null

  # Generate per-site allow/deny fragments; track configured sites for pruning.
  local -a _configured=()
  local _line _site _ip _ip_sorted _frag _tmp
  local -a _ip_list
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -ra _fields <<< "${_line}"
    _site=$(echo "${_fields[0]}" | tr '[:upper:]' '[:lower:]')
    if [[ ! ${_site} =~ ${_site_name_regex} ]]; then
      echo "Invalid site name: ${_site} (${_input_file}). Skipping."
      continue
    fi
    _ip_list=("127.0.0.1")
    [[ -n "${_server_ip}" ]] && _ip_list+=("${_server_ip}")
    for _ip in ${_ssh_ips}; do _ip_list+=("${_ip}"); done
    for _ip in "${_fields[@]:1}"; do
      if [[ ${_ip} =~ ${_ipv4_regex} ]]; then
        _ip_list+=("${_ip}")
      else
        echo "Invalid IP: ${_ip} for ${_site} (${_input_file}). Skipping."
      fi
    done
    _ip_sorted=$(printf "%s\n" "${_ip_list[@]}" | sort -u)
    _frag="${_nginx_path}/${_site}.conf"
    _tmp="${_nginx_path}/.${_site}.tmp.$$"
    {
      for _ip in ${_ip_sorted}; do echo "allow ${_ip};"; done
      echo "deny all;"
    } > "${_tmp}"
    mv -f "${_tmp}" "${_frag}"
    _configured+=("${_site}")
  done < "${_input_file}"

  # Prune fragments for sites no longer in the control file (restriction lifted).
  local _f _base _keep _s
  for _f in "${_nginx_path}"/*.conf; do
    [[ -e "${_f}" ]] || continue
    _base=$(basename "${_f}" .conf)
    _keep=""
    for _s in "${_configured[@]}"; do
      [[ "${_s}" == "${_base}" ]] && _keep="yes" && break
    done
    if [[ -z "${_keep}" ]]; then
      rm -f "${_f}"
      echo "Pruned stale ip_access fragment: ${_base}.conf (${_input_file})"
    fi
  done

  # Validate the whole host nginx config; revert THIS context on failure.
  local _ct
  _ct=$(service nginx configtest 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Nginx configtest failed after ip_access update (${_input_file}): ${_ct}"
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_input_file} ip_access to last known good."
      rm -f "${_nginx_path}"/*.conf
      tar -xzf "${_last_good_backup}" -C "${_nginx_path}" 2>/dev/null
      service nginx reload
    fi
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after ip_access update (${_input_file}); reverting."
    if [[ -f "${_last_good_backup}" ]]; then
      rm -f "${_nginx_path}"/*.conf
      tar -xzf "${_last_good_backup}" -C "${_nginx_path}" 2>/dev/null
      service nginx reload
    fi
    return 1
  fi

  tar -czf "${_last_good_backup}" -C "${_nginx_path}" . 2>/dev/null
  echo "${_current_mod_time}" > "${_timestamp_file}"
  echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
  echo "ip_access updated (${_input_file}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
}

# Master (sqladmin) context — seed the control file if absent.
mkdir -p /var/aegir/control/ip
[[ ! -f /var/aegir/control/ip/access.txt ]] && echo "sqladmin.com 192.168.1.1" > /var/aegir/control/ip/access.txt
_process_context /var/aegir/control/ip/access.txt /var/aegir/config/includes/ip_access /var/aegir/undo

# Octopus instances (skip the 'arch' mounted-backup pseudo-user).
for _root in /data/disk/*; do
  [[ -d "${_root}" ]] || continue
  [[ "$(basename "${_root}")" == "arch" ]] && continue
  _process_context "${_root}/static/control/ip/access.txt" "${_root}/config/includes/ip_access" "${_root}/undo"
done

exit 0
