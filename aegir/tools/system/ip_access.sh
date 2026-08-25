#!/bin/bash

# ip_access.sh — per-site nginx IP allow/deny, GLOBAL across the Ægir master and
# every Octopus instance.  Abstraction of the per-Octopus
# nginx_ip_access_<oct>.sh scripts into one generator.
#
# For each context it reads a control file of `<site>  <ip…>` records and writes
# a per-site nginx include `<site>.conf` (a block of `allow <ip>;` lines + a
# final `deny all;`) into that context's config/includes/ip_access/, which the
# per-vhost template pulls via `include $server->include_path/ip_access/<uri>.conf*`.
# Each allowed entry may be an IPv4 or IPv6 address, with an optional CIDR prefix
# (this is a pure nginx allow/deny layer, no csf involvement, so both families and
# subnets are supported).  127.0.0.1, ::1, the server's own IPv4 and every
# currently logged-in inbound SSH peer (v4 or v6) are always allowed (anti-lockout),
# so an admin / the server can never be shut out.
#
# Control files:
#   master  : /var/aegir/control/ip/access.txt          (the sqladmin proxy)
#   octopus : /data/disk/<oct>/static/control/ip/access.txt
# A site removed from the control file has its fragment pruned (restriction
# lifted).  Record format: `example.com 203.0.113.2 10.0.0.0/8 2001:db8::/32`.

_aegir_health_check="/var/aegir/.drush/hm.alias.drushrc.php"
_drush_health_check="/var/aegir/drush/drush"
_server_ip_file="/root/.found_correct_ipv4.cnf"

# Accept an IPv4 or IPv6 address, each with an optional CIDR prefix length — the
# nginx access module (`allow`/`deny`) takes all four forms. The validators are a
# strict SUBSET of what nginx accepts (cross-checked against `nginx -t`), so a
# typo'd address (e.g. 192.168.1.300, 2001:db8::/129) is SKIPPED rather than
# emitted into an `allow` line: a loose check would pass an out-of-range value
# that nginx rejects at configtest, and because configtest validates the WHOLE
# config, one bad fragment would block reloads box-wide until the control file is
# corrected. An out-of-range octet / prefix / bad hextet fails here and is skipped.
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_ipv4="(${_ipv4_octet}\.){3}${_ipv4_octet}"
_ipv4_regex="^${_ipv4}(/(3[0-2]|[12][0-9]|[0-9]))?$"
_hex="[0-9A-Fa-f]{1,4}"
_ipv6_core="(\
(${_hex}:){7}${_hex}|\
(${_hex}:){1,7}:|\
(${_hex}:){1,6}:${_hex}|\
(${_hex}:){1,5}(:${_hex}){1,2}|\
(${_hex}:){1,4}(:${_hex}){1,3}|\
(${_hex}:){1,3}(:${_hex}){1,4}|\
(${_hex}:){1,2}(:${_hex}){1,5}|\
${_hex}:((:${_hex}){1,6})|\
:((:${_hex}){1,7}|:)|\
::(ffff(:0{1,4})?:)?(${_ipv4})|\
(${_hex}:){1,4}:(${_ipv4}))"
_ipv6_regex="^${_ipv6_core}(/(12[0-8]|1[01][0-9]|[0-9]?[0-9]))?$"
_site_name_regex="^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}$"


# A held web tier (replication standby) makes `service nginx reload` return
# rc 7 forever, and the revert branch below would then rewrite this instance's
# backup tarball into the SYNCED undo/ tree on every 2-minute pass -- a
# permanent mirror-side divergence, because the sync legs are rsync -u and the
# mirror's copy is always the newer one. On a held standby: keep the generated
# fragments (correct on disk, they activate when promotion starts nginx),
# advance the change-gate markers as a success would, and skip both the reload
# and the revert.
_nginx_held_down() {
  [ -e "/root/.standby.cnf" ] && [ ! -e "/root/.standby.serve.cnf" ] \
    && [ -z "$(find /run/boa_xmass_init.pid -mmin -2880 2>/dev/null)" ]
}

_valid_ip() {
  local _ip="$1"
  [[ "${_ip}" =~ ${_ipv4_regex} ]] && return 0
  [[ "${_ip}" =~ ${_ipv6_regex} ]] && return 0
  return 1
}

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
# The cached address can now be healed (rewritten) at runtime, so validate
# it like every other token -- a malformed value must never reach an
# `allow` line and break the box-wide configtest.
_valid_ip "${_server_ip}" || _server_ip=""

_get_ssh_ips() {
  # `who --ips` is unavailable on Excalibur and newer, so read currently
  # established inbound SSH peers from netstat instead — the BOA-canonical
  # source for logged-in IPs.  netstat prints the foreign address as
  # `<addr>:<port>`; the port is always the final `:field`, so strip it with a
  # trailing-`:port` chop rather than splitting on the first colon — that yields
  # the peer address for BOTH families (IPv4 `1.2.3.4:22` -> `1.2.3.4`, IPv6
  # `2001:db8::2:50913` -> `2001:db8::2`).  Each harvested token is validated by
  # _valid_ip before it reaches an `allow` line, so a parsed-garbage / scoped
  # (fe80::1%eth0) token can never break configtest.
  # sshd may serve a custom _SSH_PORT, but the declared cnf value is not
  # always the effective one: hosted boxes and a failed sshd -t validation
  # force 22, and a cnf edit reaches sshd only on a firewall pass. Harvest
  # against the union of 22, the cnf value (inline comments stripped, never
  # sourced -- sourcing a slice resets config vars) and every port the live
  # sshd config serves, so a default-port box can never lose its peers and
  # a custom-port box is still covered.
  local _p _ports="22" _cnf_port _sshd_ports
  _cnf_port=$(sed -n 's/^_SSH_PORT=//p' /root/.barracuda.cnf 2>/dev/null \
    | tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '" ')
  _sshd_ports=$(/usr/sbin/sshd -T 2>/dev/null | awk '/^port /{print $2}')
  for _p in ${_cnf_port} ${_sshd_ports}; do
    if [[ "${_p}" =~ ^[0-9]+$ ]] && [[ ! " ${_ports} " =~ " ${_p} " ]]; then
      _ports="${_ports} ${_p}"
    fi
  done
  netstat -tn 2>/dev/null \
    | awk -v p=":(${_ports// /|})$" '$6 == "ESTABLISHED" && $4 ~ p { addr=$5; sub(/:[0-9]+$/, "", addr); print addr }' \
    | sort -u
}
_ssh_ips=$(_get_ssh_ips)
# The server IP is baked into every fragment, so a healed address must
# fire the change-gate exactly like a changed SSH-peer set.
_ssh_ips_hash=$(echo "${_ssh_ips} ${_server_ip}" | md5sum | awk '{print $1}')

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
    _ip_list=("127.0.0.1" "::1")
    [[ -n "${_server_ip}" ]] && _ip_list+=("${_server_ip}")
    # SSH peers are validated here (not at harvest) so a scoped/garbage token
    # never reaches an `allow` line and breaks the box-wide configtest.
    for _ip in ${_ssh_ips}; do
      _valid_ip "${_ip}" && _ip_list+=("${_ip}")
    done
    for _ip in "${_fields[@]:1}"; do
      if _valid_ip "${_ip}"; then
        _ip_list+=("${_ip}")
      else
        echo "Invalid IP/subnet: ${_ip} for ${_site} (${_input_file}). Skipping."
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

  if _nginx_held_down; then
    echo "${_current_mod_time}" > "${_timestamp_file}"
    echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
    echo "ip_access written (${_input_file}); replication standby -- reload skipped (web tier held)."
    return 0
  fi

  # Validate the whole host nginx config; revert THIS context on failure.
  local _ct
  _ct=$(service nginx configtest 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Nginx configtest failed after ip_access update (${_input_file}): ${_ct}"
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_input_file} ip_access to last known good."
      ### Prove the archive is readable BEFORE deleting what is on disk:
      ### the old order wiped every fragment and then extracted from an
      ### unverified tarball, so a corrupt or truncated backup left the
      ### box with no access-control fragments at all.
      if tar -tzf "${_last_good_backup}" &> /dev/null; then
        rm -f "${_nginx_path}"/*.conf
        if ! tar -xzf "${_last_good_backup}" -C "${_nginx_path}" 2>/dev/null; then
          echo "ALRT: restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
        service nginx reload
      else
        echo "ALRT: last-good backup ${_last_good_backup} is unreadable -- keeping the"
        echo "ALRT: fragments now on disk rather than deleting them for an archive"
        echo "ALRT: that cannot be restored. Fix ${_input_file} and re-run."
      fi
    else
      # No last-good yet (a first run failed configtest). nginx never reloaded the
      # bad config (configtest gates the reload), so just drop the fragments this
      # run wrote — otherwise a bad one lingers and keeps EVERY tool's configtest
      # failing box-wide until someone finds and fixes it.
      echo "No last-good backup for ${_input_file}; removing just-written fragments."
      rm -f "${_nginx_path}"/*.conf
    fi
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after ip_access update (${_input_file}); reverting."
    if [[ -f "${_last_good_backup}" ]]; then
      if tar -tzf "${_last_good_backup}" &> /dev/null; then
        rm -f "${_nginx_path}"/*.conf
        if ! tar -xzf "${_last_good_backup}" -C "${_nginx_path}" 2>/dev/null; then
          echo "ALRT: restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
        service nginx reload
      else
        echo "ALRT: last-good backup ${_last_good_backup} is unreadable -- fragments left in place."
      fi
    fi
    return 1
  fi

  ### An unverified last-good archive is worse than none: the revert path
  ### above trusts it enough to delete the live fragments.
  if tar -czf "${_last_good_backup}" -C "${_nginx_path}" . 2>/dev/null \
    && tar -tzf "${_last_good_backup}" &> /dev/null; then
    :
  else
    echo "ALRT: could not write a verifiable last-good ip_access backup; removing it"
    rm -f "${_last_good_backup}"
  fi
  echo "${_current_mod_time}" > "${_timestamp_file}"
  echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
  echo "ip_access updated (${_input_file}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
}

# Master (sqladmin) context — seed the control file if absent.
mkdir -p /var/aegir/control/ip
[[ ! -f /var/aegir/control/ip/access.txt ]] && echo "sqladmin.com 192.168.1.1" > /var/aegir/control/ip/access.txt
_process_context /var/aegir/control/ip/access.txt /var/aegir/config/includes/ip_access /var/aegir/undo

# Octopus instances. Real instances carry tools/drush; the BOA-canonical instance
# test (see autosymlink) transparently skips every non-instance pseudo-dir
# (arch, all, legacy, global, static, custom, …), not just 'arch' by name.
for _root in /data/disk/*; do
  [[ -d "${_root}" && -e "${_root}/tools/drush" ]] || continue
  _process_context "${_root}/static/control/ip/access.txt" "${_root}/config/includes/ip_access" "${_root}/undo"
done

exit 0
