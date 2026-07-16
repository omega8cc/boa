#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# ----------------------------
# Stuck-process watchdog
# ----------------------------
# guest-fire.sh runs 5 iterations × 10 s = ~50 s under normal load.
# During a web.log flood (thousands of IPs) it can take several minutes,
# blocking all subsequent cron invocations via _manage_single_lock.
# This watchdog kills any instance running beyond _FIRE_TIMEOUT seconds
# so the next cron slot always gets a clean start.
_FIRE_PID_FILE="/run/fire.pid"
_FIRE_TIMEOUT=180  # seconds — 3x the normal 5-iteration runtime (5x10s=50s);
                   # leaves room for slow CSF iptables rebuilds on short IP lists
                   # while still catching true flood-induced hangs (many minutes)

_kill_stuck_fire() {
  if [[ -e "${_FIRE_PID_FILE}" ]]; then
    local _OLD_PID _START_TIME _ELAPSED
    _OLD_PID=$(cat "${_FIRE_PID_FILE}" 2>/dev/null)
    if [[ -n "${_OLD_PID}" ]] && kill -0 "${_OLD_PID}" 2>/dev/null; then
      # Process is alive — check elapsed time via pid file mtime
      _START_TIME=$(stat -c %Y "${_FIRE_PID_FILE}" 2>/dev/null || echo 0)
      _ELAPSED=$(( $(date +%s) - _START_TIME ))
      if (( _ELAPSED > _FIRE_TIMEOUT )); then
        echo "$(date) [fire-watchdog] PID ${_OLD_PID} stuck ${_ELAPSED}s > ${_FIRE_TIMEOUT}s — killing" \
          >> /var/log/boa/fire_stuck.log
        kill -9 "${_OLD_PID}" 2>/dev/null || true
        rm -f "${_FIRE_PID_FILE}"
      else
        # Running but within timeout — a normal overlap; let _manage_single_lock handle it
        : # fall through; _manage_single_lock will exit if count > 2
      fi
    else
      # Stale PID file (process already gone)
      rm -f "${_FIRE_PID_FILE}"
    fi
  fi
  # Record our own PID; mtime becomes the start-time reference for the next invocation
  echo "$$" > "${_FIRE_PID_FILE}"
}

_kill_stuck_fire
# Remove PID file on exit (normal or signal)
trap 'rm -f "${_FIRE_PID_FILE}"' EXIT

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

# ----------------------------
# Configuration Section
# ----------------------------

# Default logging mode, can be SILENT (none), NORMAL or VERBOSE
_NGINX_DOS_LOG=SILENT

# ==============================
# Load Configuration File
# ==============================

_CONFIG_FILE="/root/.barracuda.cnf"

if [[ -e "${_CONFIG_FILE}" ]]; then
  source "${_CONFIG_FILE}" ### to read _NGINX_DOS_LOG value used in other scripts too
fi

# ----------------------------
# CSF state files
# ----------------------------
# Membership is tested in-shell against these files; csf itself is invoked
# only to CHANGE state. The previous per-IP `csf -g` (a perl run per IP, per
# log, per iteration) was a fork storm that could push a flood run past the
# stuck-process watchdog.
_CSF_DENY="/etc/csf/csf.deny"
_CSF_ALLOW="/etc/csf/csf.allow"
_CSF_TEMPBAN="/var/lib/csf/csf.tempban"
_CSF_TEMPALLOW="/var/lib/csf/csf.tempallow"

# Value-valid IPv4 octet: 0-255, no leading zeros
_IPV4_OCTET_RX="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"

# ----------------------------
# Function Definitions
# ----------------------------

# Escape dots so an IP can be used safely in a regex (dots are wildcards
# there — 1.2.3.4 would otherwise match 112.3.4).
_rx() {
  local _s="${1}"
  echo "${_s//./\\.}"
}

# Strict IPv4 for ban candidates: the scanner logs are attacker-adjacent
# input, so only a value-valid address (each octet 0-255, no leading zeros)
# outside the reserved ranges (0/8, 127/8 loopback, 224+ multicast) may
# ever steer a csf command.
_is_ipv4_strict() {
  local _ip="${1}"
  [[ "${_ip}" =~ ^(${_IPV4_OCTET_RX}\.){3}${_IPV4_OCTET_RX}$ ]] || return 1
  local _o1="${_ip%%.*}"
  (( _o1 == 0 || _o1 == 127 || _o1 >= 224 )) && return 1
  return 0
}

# Local addresses are never auto-banned.
_LOCAL_IPS=()

_load_local_ips() {
  local _ip
  while IFS= read -r _ip; do
    [[ -n "${_ip}" ]] && _LOCAL_IPS+=("${_ip}")
  done < <(ip -4 addr show | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}')
}

_is_local_ip() {
  local _check_ip="${1}" _local
  for _local in "${_LOCAL_IPS[@]}"; do
    [[ "${_check_ip}" == "${_local}" ]] && return 0
  done
  if [[ -f "/root/.local.IP.list" ]]; then
    grep -qE "^[[:space:]]*$(_rx "${_check_ip}")([[:space:]#]|$)" \
      /root/.local.IP.list 2>/dev/null && return 0
  fi
  return 1
}

_ip_to_int() {
  local _a _b _c _d
  IFS=. read -r _a _b _c _d <<< "${1}"
  echo $(( (_a << 24) + (_b << 16) + (_c << 8) + _d ))
}

# Return 0 if any CIDR block read from stdin covers the IP.
_cidr_covers_ip() {
  local _ip="${1}"
  local _int; _int="$(_ip_to_int "${_ip}")"
  local _entry _net _pfx _mask
  while IFS= read -r _entry; do
    _net="${_entry%/*}"; _pfx="${_entry#*/}"
    [[ "${_pfx}" =~ ^[0-9]+$ ]] || continue
    (( _pfx >= 1 && _pfx <= 31 )) || continue
    [[ "${_net}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || continue
    _mask=$(( (0xFFFFFFFF << (32 - _pfx)) & 0xFFFFFFFF ))
    if (( ( _int & _mask ) == ( $(_ip_to_int "${_net}") & _mask ) )); then
      return 0
    fi
  done
  return 1
}

# Membership test against a CSF state file, honouring every entry form CSF
# accepts: plain first-field IP, IP/32, advanced syntax (s=/d=), and covering
# CIDR blocks anywhere in an entry. This is the TRUST test: any appearance
# means the address is operator- or provider-listed and must not be banned.
_csf_file_matches_ip() {
  local _ip="${1}" _file="${2}"
  local _ip_rx; _ip_rx="$(_rx "${_ip}")"
  [[ -f "${_file}" ]] || return 1
  grep -qE "(^|\|s=|\|d=)${_ip_rx}(/32)?([[:space:]#|]|$)" "${_file}" 2>/dev/null \
    && return 0
  cut -d'#' -f1 "${_file}" 2>/dev/null \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' \
    | sort -u \
    | _cidr_covers_ip "${_ip}"
}

# First-field entries only — plain IP, IP/32, or a covering plain CIDR: the
# forms that apply to every port.
_csf_plain_covers_ip() {
  local _ip="${1}" _file="${2}"
  local _ip_rx; _ip_rx="$(_rx "${_ip}")"
  [[ -f "${_file}" ]] || return 1
  grep -qE "^${_ip_rx}(/32)?([[:space:]#]|$)" "${_file}" 2>/dev/null \
    && return 0
  grep -oE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' "${_file}" 2>/dev/null \
    | sort -u \
    | _cidr_covers_ip "${_ip}"
}

# Return 0 if the IP has an active inbound temp ban covering the port.
# csf.tempban line format: epoch|ip|port|direction|ttl|comment
_is_temp_banned_port() {
  local _ip="${1}" _port="${2}"
  [[ -f "${_CSF_TEMPBAN}" ]] || return 1
  awk -F'|' -v ip="${_ip}" -v p="${_port}" \
    '$2 == ip && ($3 == p || $3 == "*" || $3 == "") && ($4 == "in" || $4 == "inout" || $4 == "") { _found=1; exit } END { exit !_found }' \
    "${_CSF_TEMPBAN}" 2>/dev/null
}

# Return 0 if the IP has an active temp allow (any port).
_is_temp_allowed() {
  local _ip="${1}"
  [[ -f "${_CSF_TEMPALLOW}" ]] || return 1
  awk -F'|' -v ip="${_ip}" \
    '$2 == ip { _found=1; exit } END { exit !_found }' \
    "${_CSF_TEMPALLOW}" 2>/dev/null
}

# Function for logging in verbose mode
_verbose_log() {
  _reason="${1}"
  _message="${2}"
  _log_file="/dev/null"

  # Define log file paths
  _csf_dry_log="/var/log/csf_dry_debug.log"
  _csf_fail_log="/var/log/csf_fail_debug.log"
  _csf_deny_log="/var/log/csf_deny_debug.log"
  _csf_denied_log="/var/log/csf_denied_debug.log"
  _csf_allow_log="/var/log/csf_allow_debug.log"

  # Check if logging is enabled
  if [[ -e "/etc/boa/.debug.monitor.log.cnf" || "${_NGINX_DOS_LOG}" =~ ^(NORMAL|VERBOSE)$ ]]; then
    if [[ "${_reason}" =~ ^(DRY|NORMAL|DEBUG)$ && "${_NGINX_DOS_LOG}" = VERBOSE ]]; then
      _log_file="${_csf_dry_log}"
    elif [[ "${_reason}" =~ ^(FAIL|INVALID|ERROR)$ ]]; then
      _log_file="${_csf_fail_log}"
    elif [[ "${_reason}" =~ ^DENY$ && "${_NGINX_DOS_LOG}" =~ ^(NORMAL|VERBOSE)$ ]]; then
      _log_file="${_csf_deny_log}"
    elif [[ "${_reason}" =~ ^DENIED$ && "${_NGINX_DOS_LOG}" =~ ^(NORMAL|VERBOSE)$ ]]; then
      _log_file="${_csf_denied_log}"
    elif [[ "${_reason}" =~ ^(ALLOWED|CLEAN)$ && "${_NGINX_DOS_LOG}" = VERBOSE ]]; then
      _log_file="${_csf_allow_log}"
    else
      # Unrecognized _reason; skip logging to prevent unbound variable
      return
    fi

    # Generate timestamp
    _timestamp=$(date)

    # Write to the appropriate log file using printf
    printf "%s %s REASON: %s\n" "${_timestamp}" "${_reason}" "${_message}" >> "${_log_file}"
  fi
}

# One enforcement pass over a rolling scanner log. The first port is the one
# the allow rules are checked against (matches the scanner that feeds the
# log); every port in the list is banned/verified individually, so an IP
# temp-banned on 443 only still gets its missing port 80 ban.
_guard_log() {
  # NB: NOT named _log_file — the shared _verbose_log() assigns a global
  # _log_file without `local`, and bash dynamic scoping would clobber this
  # frame's copy on the first call, corrupting later ${_src_log} messages.
  local _src_log="${1}"
  shift
  local _ports=("$@")
  local _allow_port="${_ports[0]}"
  [ -e "${_src_log}" ] || return 0

  local _IP _PORT _FW_CHANGED=
  # Process each unique IP from the log file
  while read -r _IP; do
    [ -z "${_IP}" ] && continue
    if ! _is_ipv4_strict "${_IP}"; then
      _verbose_log "INVALID" "Skipping invalid IP ${_IP} from ${_src_log}"
      continue
    fi
    if _is_local_ip "${_IP}"; then
      _verbose_log "CLEAN" "Skipping local/trusted ${_IP} from ${_src_log}"
      continue
    fi
    if _csf_file_matches_ip "${_IP}" "${_CSF_ALLOW}"; then
      echo "${_IP} is allowed on port ${_allow_port}"
      _verbose_log "ALLOWED" "${_IP} is allowed on port ${_allow_port}"
      # Strip lingering blocks only for allow forms that cover the port:
      # a plain/CIDR entry (all ports) or an inbound rule scoped to it.
      if _csf_plain_covers_ip "${_IP}" "${_CSF_ALLOW}" \
        || grep -qE "^[a-z]+\|in\|d=${_allow_port}\|s=$(_rx "${_IP}")([[:space:]#|]|$)" "${_CSF_ALLOW}" 2>/dev/null; then
        echo "Removing ${_IP} potential blocks on ports ${_ports[*]}"
        csf -dr ${_IP}
        csf -tr ${_IP}
        _FW_CHANGED=YES
        _verbose_log "CLEAN" "Removing ${_IP} potential blocks on ports ${_ports[*]}"
      fi
      continue
    fi
    if _is_temp_allowed "${_IP}"; then
      # Operator temp allow — never ban, but never csf -tr either
      # (that would remove the temp allow itself).
      echo "${_IP} is temporarily allowed"
      _verbose_log "ALLOWED" "${_IP} is temporarily allowed"
      continue
    fi
    for _PORT in "${_ports[@]}"; do
      if _csf_plain_covers_ip "${_IP}" "${_CSF_DENY}" \
        || grep -qE "^[a-z]+\|in\|d=${_PORT}\|s=$(_rx "${_IP}")([[:space:]#|]|$)" "${_CSF_DENY}" 2>/dev/null \
        || _is_temp_banned_port "${_IP}" "${_PORT}"; then
        echo "${_IP} already denied on port ${_PORT}"
        _verbose_log "DENIED" "${_IP} already denied on port ${_PORT}"
      else
        echo "Denying ${_IP} on port ${_PORT} in the next 15 min"
        csf -td ${_IP} 900 -p ${_PORT}
        _FW_CHANGED=YES
        _verbose_log "DENY" "Denying ${_IP} on port ${_PORT} in the next 15 min"
      fi
    done
  done < <(cut -d '#' -f1 "${_src_log}" | tr -d ' ' | sort | uniq)

  # One reassert per pass when the rules changed — not one per IP.
  if [ "${_FW_CHANGED}" = "YES" ] && [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
    synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
  fi
}

# Function to run procedure in a loop
_guest_guard() {
  _guard_log "/var/xdrago/monitor/log/ssh.log" 22
  _guard_log "/var/xdrago/monitor/log/web.log" 80 443
  _guard_log "/var/xdrago/monitor/log/ftp.log" 21
}

# Main execution
if [ -x "/usr/sbin/csf" ]; then
  _load_local_ips
  # Main execution
  for _iteration in {1..5}; do
    echo "----------------------------"
    echo "Iteration ${_iteration}:"
    [ ! -e "/run/water.pid" ] && _guest_guard
    sleep 10
  done
fi

exit 0

