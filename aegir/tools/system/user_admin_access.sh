#!/bin/bash

# user_admin_access.sh — per-site nginx IP allow/deny scoped to the Drupal /user
# and /admin URIs only, GLOBAL across every Octopus instance.  Parallel to
# ip_access.sh (which guards the WHOLE site and is IPv4-only to stay aligned with
# csf): this one restricts just the login/admin surface and — because it is a
# pure nginx allow/deny layer with no csf involvement — accepts IPv4 AND IPv6,
# single addresses AND CIDR subnets.
#
# For each instance it reads a control file of `<site>  <ip|cidr…>` records and
# writes two per-site nginx includes into that instance's config/includes/:
#
#   user_admin_access_map/<site>.conf  (http scope) — a `geo` classifying the
#       client IP as allowed (1) or not (0), a `map` flagging a /user|/admin
#       request on the clean $uri (BOA enforces Drupal clean URLs, so those paths
#       always arrive in $uri), and a final `map` $ua_deny_<hash> that is 1 only
#       when an admin-area request arrives from a non-allowed IP;
#   user_admin_access/<site>.conf      (server scope) — a single
#       `if ($ua_deny_<hash>) { return 403; }`.
#
# The per-site vhost pulls the first once at the file head (http scope) via
#   include $server->include_path/user_admin_access_map/<uri>.conf*;
# and the second inside every serving server block (co-located with ip_access) via
#   include $server->include_path/user_admin_access/<uri>.conf*;
# both globs no-op for a site with no fragment, so an un-listed site is entirely
# unaffected and the whole feature is strict opt-in.  The `.conf*` (not bare `*`)
# is deliberate: a bare `<uri>*` would also match a longer site whose name extends
# this one (example.com vs example.com.au), pulling that site's fragment into this
# vhost too and wrongly applying its restriction here; `.conf*` anchors on the
# fragment suffix so only this site's own <uri>.conf matches, while still no-oping
# when absent.  The geo/map is defined once per file and referenced from every
# server block in it (the :443 block precedes it in an SSL vhost — nginx resolves
# map/geo vars across the whole http{} regardless of textual order, so the forward
# reference is fine).
#
# 127.0.0.1, ::1, the server's own IPv4 and every live inbound SSH peer (v4 or v6)
# are always allowed (anti-lockout), so an admin working over SSH can never be shut
# out of /admin.  A site removed from the control file has both fragments pruned
# (restriction lifted).
#
# Control file (Octopus only — regular-site vhosts; hostmaster has its own,
# out-of-scope vhost):
#   /data/disk/<oct>/static/control/ip/user_admin.txt
#   Record: `example.com  203.0.113.10  10.0.0.0/8  2001:db8::/32  2001:db8::1`

_aegir_health_check="/var/aegir/.drush/hm.alias.drushrc.php"
_drush_health_check="/var/aegir/drush/drush"
_server_ip_file="/root/.found_correct_ipv4.cnf"

# Bump when the emitted directive shape changes, to force regeneration
# independent of the control-file mtime.
_emit_version="1"

# Validators.  Each accepts an IPv4 or IPv6 address, with an optional CIDR prefix
# length, and is a strict SUBSET of what nginx `geo` accepts — cross-checked
# against `nginx -t` — so a validated entry can never break the whole-host
# configtest (which validates every vhost; one bad geo network would block
# reloads box-wide).  A rejected token is skipped with a logged warning, like
# ip_access does for a bad octet.
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

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx not installed; nothing to do."
  exit 0
fi

# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy / user_admin_access) never overlap
# their configtest+reload; wait up to 30s, then skip this run and retry next tick.
exec 9>"/run/boa_nginx_config.lock" 2>/dev/null
if ! flock -w 30 9; then
  echo "Could not acquire the shared nginx-config lock; skipping this run."
  exit 0
fi

# Server's own IPv4 (optional) + currently logged-in inbound SSH peers (v4 or v6)
# feed every context's anti-lockout allow list.
_server_ip=""
[[ -f "${_server_ip_file}" ]] && _server_ip=$(cat "${_server_ip_file}" 2>/dev/null)

_get_ssh_ips() {
  # Same source ip_access.sh uses: `who --ips` is unavailable on Excalibur and
  # newer, so read established inbound SSH peers from netstat.  netstat prints the
  # foreign address as `<addr>:<port>`; the port is always the final `:field`, so
  # strip it with a trailing-`:port` chop rather than splitting on the first colon
  # — that yields the peer address for BOTH families (IPv4 `1.2.3.4:22` ->
  # `1.2.3.4`, IPv6 `2001:db8::2:50913` -> `2001:db8::2`).  Each harvested token is
  # validated by _valid_ip before it reaches a geo entry, so a parsed-garbage /
  # scoped (fe80::1%eth0) token can never break configtest.
  netstat -tn 2>/dev/null \
    | awk '$6 == "ESTABLISHED" && $4 ~ /:22$/ { addr=$5; sub(/:[0-9]+$/, "", addr); print addr }' \
    | sort -u
}
_ssh_ips=$(_get_ssh_ips)
_ssh_ips_hash=$(echo "${_ssh_ips}" | md5sum | awk '{print $1}')

_process_instance() {
  local _root="$1"
  local _input_file="${_root}/static/control/ip/user_admin.txt"
  local _map_path="${_root}/config/includes/user_admin_access_map"
  local _srv_path="${_root}/config/includes/user_admin_access"
  local _backup_dir="${_root}/undo"
  local _current_backup="${_backup_dir}/.nginx_user_admin.current.bak.tar.gz"
  local _last_good_backup="${_backup_dir}/.nginx_user_admin.last_good.bak.tar.gz"
  local _timestamp_file="${_srv_path}/.ua_last_mod_time"
  local _ssh_hash_file="${_srv_path}/.ua_ssh_ips_hash"
  local _version_file="${_srv_path}/.ua_emit_version"

  [[ -f "${_input_file}" ]] || return 0
  [[ -d "${_root}/config/includes" ]] || return 0

  mkdir -p "${_map_path}" "${_srv_path}" "${_backup_dir}"

  # Change-gate: regenerate only when the control file changed, the host SSH-IP
  # set changed (a newly logged-in admin must propagate), or the emit version
  # bumped.  No change -> no write, no reload.
  local _current_mod_time _last_mod_time=0 _previous_ssh_hash="" _last_version=""
  _current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null) || return 0
  [[ -f "${_timestamp_file}" ]] && _last_mod_time=$(cat "${_timestamp_file}" 2>/dev/null || echo 0)
  [[ -f "${_ssh_hash_file}" ]] && _previous_ssh_hash=$(cat "${_ssh_hash_file}" 2>/dev/null || echo "")
  [[ -f "${_version_file}" ]] && _last_version=$(cat "${_version_file}" 2>/dev/null || echo "")
  if [[ "${_current_mod_time}" -le "${_last_mod_time}" \
     && "${_ssh_ips_hash}" == "${_previous_ssh_hash}" \
     && "${_last_version}" == "${_emit_version}" ]]; then
    return 0
  fi

  # Back up both fragment dirs before regenerating.
  tar -czf "${_current_backup}" -C "${_root}/config/includes" \
    user_admin_access_map user_admin_access 2>/dev/null

  # Generate per-site fragments; track configured sites for pruning.
  local -a _configured=() _fields _ip_list
  local _line _site _hash _ip _norm _ip_sorted _frag _tmp _e _d _f _base _keep _s
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -ra _fields <<< "${_line}"
    _site=$(echo "${_fields[0]}" | tr '[:upper:]' '[:lower:]')
    if [[ ! ${_site} =~ ${_site_name_regex} ]]; then
      echo "Invalid site name: ${_site} (${_input_file}). Skipping."
      continue
    fi
    _hash=$(echo -n "${_site}" | md5sum | awk '{print $1}' | cut -c1-12)

    # Anti-lockout, then the operator's validated entries.
    _ip_list=("127.0.0.1" "::1")
    [[ -n "${_server_ip}" ]] && _ip_list+=("${_server_ip}")
    # SSH peers validated here (not at harvest) so a scoped/garbage token never
    # reaches a geo entry and breaks the box-wide configtest.
    for _ip in ${_ssh_ips}; do
      _valid_ip "${_ip}" && _ip_list+=("${_ip}")
    done
    for _ip in "${_fields[@]:1}"; do
      if _valid_ip "${_ip}"; then
        # Drop a redundant host prefix so a listed 1.2.3.4/32 (or v6 …/128) does
        # not collide as a duplicate geo network with the plain anti-lockout form.
        if [[ "${_ip}" == *:* ]]; then
          _norm="${_ip%/128}"
        else
          _norm="${_ip%/32}"
        fi
        _ip_list+=("${_norm}")
      else
        echo "Invalid IP/subnet: ${_ip} for ${_site} (${_input_file}). Skipping."
      fi
    done
    _ip_sorted=$(printf '%s\n' "${_ip_list[@]}" | sort -u)

    # http-scope fragment: geo (IP -> allowed) + area maps + deny map.
    _frag="${_map_path}/${_site}.conf"
    _tmp="${_map_path}/.${_site}.tmp.$$"
    {
      echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
      echo "# Per-site /user + /admin IP access for ${_site}."
      echo "geo \$ua_ip_ok_${_hash} {"
      echo "  default 0;"
      for _e in ${_ip_sorted}; do echo "  ${_e} 1;"; done
      echo "}"
      # BOA enforces Drupal clean URLs, so /user and /admin always arrive as the
      # real request path in \$uri (which nginx percent-decodes and normalises —
      # /./ , and // under the default merge_slashes on). We match \$uri only: the
      # legacy ?q=admin query form is not a clean path and is not served by
      # default on BOA, and \$arg_q cannot be reliably matched at nginx (it is
      # neither percent-decoded nor de-duplicated the way Drupal reads \$_GET['q']).
      # ^/+ (not ^/) also catches a multi-slash //admin even if a vhost ever
      # disabled merge_slashes.
      echo "map \$uri \$ua_u_${_hash} {"
      echo "  default 0;"
      echo "  ~*^/+(?:user|admin)(?:/|\$) 1;"
      echo "}"
      echo "map \"\$ua_u_${_hash}\$ua_ip_ok_${_hash}\" \$ua_deny_${_hash} {"
      echo "  default 0;"
      echo "  \"10\" 1;"
      echo "}"
    } > "${_tmp}"
    mv -f "${_tmp}" "${_frag}"

    # server-scope fragment: the 403 gate for the admin surface.
    _frag="${_srv_path}/${_site}.conf"
    _tmp="${_srv_path}/.${_site}.tmp.$$"
    {
      echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
      echo "if (\$ua_deny_${_hash}) { return 403; }"
    } > "${_tmp}"
    mv -f "${_tmp}" "${_frag}"

    _configured+=("${_site}")
  done < "${_input_file}"

  # Prune fragments (both dirs) for sites no longer in the control file.
  for _d in "${_map_path}" "${_srv_path}"; do
    for _f in "${_d}"/*.conf; do
      [[ -e "${_f}" ]] || continue
      _base=$(basename "${_f}" .conf)
      _keep=""
      for _s in "${_configured[@]}"; do
        [[ "${_s}" == "${_base}" ]] && _keep="yes" && break
      done
      if [[ -z "${_keep}" ]]; then
        rm -f "${_f}"
        echo "Pruned stale user_admin_access fragment: ${_base}.conf (${_d})"
      fi
    done
  done

  # Validate the whole host nginx config; revert THIS instance on failure.
  local _ct
  _ct=$(service nginx configtest 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Nginx configtest failed after user_admin_access update (${_root}): ${_ct}"
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_root} user_admin_access to last known good."
      rm -f "${_map_path}"/*.conf "${_srv_path}"/*.conf
      tar -xzf "${_last_good_backup}" -C "${_root}/config/includes" 2>/dev/null
      service nginx reload
    else
      # No last-good yet (a first run failed configtest). nginx never reloaded the
      # bad config (configtest gates the reload), so just drop the fragments this
      # run wrote — otherwise a bad one lingers and keeps EVERY tool's configtest
      # failing box-wide until someone finds and fixes it.
      echo "No last-good backup for ${_root}; removing just-written fragments."
      rm -f "${_map_path}"/*.conf "${_srv_path}"/*.conf
    fi
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after user_admin_access update (${_root}); reverting."
    if [[ -f "${_last_good_backup}" ]]; then
      rm -f "${_map_path}"/*.conf "${_srv_path}"/*.conf
      tar -xzf "${_last_good_backup}" -C "${_root}/config/includes" 2>/dev/null
      service nginx reload
    fi
    return 1
  fi

  # Success: refresh this instance's last-good backup + change-gate markers.
  tar -czf "${_last_good_backup}" -C "${_root}/config/includes" \
    user_admin_access_map user_admin_access 2>/dev/null
  echo "${_current_mod_time}" > "${_timestamp_file}"
  echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
  echo "${_emit_version}" > "${_version_file}"
  echo "user_admin_access updated (${_root}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
}

# Octopus instances only. Real instances carry tools/drush; the BOA-canonical
# instance test transparently skips every non-instance pseudo-dir (arch, all,
# legacy, global, static, custom, …), not just 'arch' by name.
for _root in /data/disk/*; do
  [[ -d "${_root}" && -e "${_root}/tools/drush" ]] || continue
  _process_instance "${_root}"
done

exit 0
