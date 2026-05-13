#!/bin/bash

# =============================================================================
# hackcheck.sh — SSH auth abuse monitor for BOA
# Replaces: hackcheck.pl
#
# Improvements over the Perl original:
#   - Handles both classic syslog and ISO 8601 timestamps (Debian 12+ rsyslog)
#   - Accepts current AND previous minute to close the cron timing race window
#   - _already_logged() check prevents duplicate log/ban entries within TTL
#   - noclobber lock prevents overlapping cron runs
#   - Rolling log recycled after _BAN_SECONDS to re-arm expired bans
#   - IP extracted via grep -oE (format-agnostic, not fixed field position)
#
# Requires: bash >= 4.2, csf
# =============================================================================

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly _LOG_DIR="/var/xdrago/monitor/log"
readonly _SSH_LOG="${_LOG_DIR}/ssh.log"
readonly _SSH_ARCHIVE="${_LOG_DIR}/hackcheck.archive.log"
readonly _LOCK_FILE="/var/run/hackcheck.lock"
readonly _MAINTENANCE_FLAG="/var/xdrago/guest-fire.sh"
readonly _CSF="/usr/sbin/csf"

# Must match the TTL passed to csf -td and the */N recycle cron if used.
# BOA default: 900 (guest-fire.sh handles re-enforcement at 900s).
readonly _BAN_SECONDS=900


# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

_acquire_lock() {
  if ! ( set -o noclobber; echo "$$" > "${_LOCK_FILE}" ) 2>/dev/null; then
    local _existing_pid
    _existing_pid=$(cat "${_LOCK_FILE}" 2>/dev/null)
    if kill -0 "${_existing_pid}" 2>/dev/null; then
      exit 0
    else
      echo "$$" > "${_LOCK_FILE}"
    fi
  fi
  trap 'rm -f "${_LOCK_FILE}"' EXIT INT TERM
}

# -----------------------------------------------------------------------------
# Timestamp helpers
# -----------------------------------------------------------------------------

# Classic rsyslog:  "May 10 12:35:28 host sshd: msg"  → comparator "May:10:12:35"
# ISO 8601 rsyslog: "2026-05-10T12:35:28.612894+02:00 host sshd: msg"
#                    → comparator first 16 chars "2026-05-10T12:35"
#
# Both current AND previous minute accepted — closes the race where cron fires
# at :01, scan takes 1s, but attacks logged at :28-:59 only appear in auth.log
# when the NEXT cron run fires (at which point NOW has advanced by one minute).

_NOW_IS=""       # "Mon:DD:HH:MM"     classic, current minute
_PREV_IS=""      # "Mon:DD:HH:MM"     classic, previous minute
_NOW_IS_ISO=""   # "YYYY-MM-DDTHH:MM" ISO 8601, current minute
_PREV_IS_ISO=""  # "YYYY-MM-DDTHH:MM" ISO 8601, previous minute

_set_timestamps() {
  _NOW_IS=$(date +%b:%d:%H:%M)
  _PREV_IS=$(date -d '1 minute ago' +%b:%d:%H:%M)
  _NOW_IS_ISO=$(date +%Y-%m-%dT%H:%M)
  _PREV_IS_ISO=$(date -d '1 minute ago' +%Y-%m-%dT%H:%M)
}

_line_is_recent() {
  local _line="${1}"
  local _first_field
  read -r _first_field _ <<< "${_line}"

  if [[ "${_first_field}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
    # ISO 8601 — compare first 16 chars
    local _line_min="${_first_field:0:16}"
    [[ "${_line_min}" == "${_NOW_IS_ISO}" || "${_line_min}" == "${_PREV_IS_ISO}" ]]
  else
    # Classic syslog — reconstruct "Mon:DD:HH:MM"
    local _mont _dayx _timex _hour _min
    read -r _mont _dayx _timex _ <<< "${_line}"
    _dayx="${_dayx//[^0-9]/}"
    (( ${#_dayx} == 1 )) && _dayx="0${_dayx}"
    _timex="${_timex//[^0-9:]/}"
    [[ "${_timex}" =~ ^[0-9] ]] || return 1
    _hour="${_timex%%:*}"
    _min="${_timex#*:}"; _min="${_min%%:*}"
    local _log_is="${_mont}:${_dayx}:${_hour}:${_min}"
    [[ "${_log_is}" == "${_NOW_IS}" || "${_log_is}" == "${_PREV_IS}" ]]
  fi
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

_LOCAL_IPS=()

_load_local_ips() {
  local _ip
  while IFS= read -r _ip; do
    [[ -n "${_ip}" ]] && _LOCAL_IPS+=("${_ip}")
  done < <(ip -4 addr show | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}')
}

_is_ipv4() {
  [[ "${1}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local _local
  for _local in "${_LOCAL_IPS[@]}"; do
    [[ "${1}" == "${_local}" ]] && return 1
  done
  return 0
}

_already_logged() {
  [[ -f "${_SSH_LOG}" ]] && grep -qE "^${1} #" "${_SSH_LOG}"
}

_csf_ban() {
  local _ip="${1}"
  # Maintenance mode: guest-fire.sh presence disables direct CSF bans
  # (guest-fire.sh itself will handle enforcement)
  [[ -e "${_MAINTENANCE_FLAG}" ]] && return 0
  [[ -x "${_CSF}" && -e "/etc/csf/csf.deny" ]] || return 0
  "${_CSF}" -td "${_ip}" "${_BAN_SECONDS}" -p 22 &>/dev/null
}

# Recycle rolling log once IPs have served their ban TTL.
# Prevents the log from permanently suppressing re-bans after expiry.
# Note: BOA also does this via */N cron rm; this internal check is a safety net
# that fires first and avoids the duplicate-ban-attempt window in that approach.
_recycle_log() {
  [[ -f "${_SSH_LOG}" ]] || return 0
  local _first_line _mark _mark_epoch _age_sec
  IFS= read -r _first_line < "${_SSH_LOG}"
  _mark="${_first_line##* }"
  if [[ "${_mark}" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
    _mark_epoch=$(date -d "20${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null)
    if [[ -n "${_mark_epoch}" ]]; then
      _age_sec=$(( $(date +%s) - _mark_epoch ))
      if (( _age_sec >= _BAN_SECONDS )); then
        rm -f "${_SSH_LOG}"
      fi
    fi
  fi
}

# -----------------------------------------------------------------------------
# Main detection logic  (replaces makeactions + verify_timestamp + check_ip)
# -----------------------------------------------------------------------------

_makeactions() {
  mkdir -p "${_LOG_DIR}"
  _load_local_ips
  _recycle_log
  _set_timestamps

  local _mark
  _mark=$(date +%y%m%d-%H%M%S)

  declare -A _hits=()
  # IPs with a successful login in this log window — never banned regardless
  # of other matching patterns. A legitimate user whose client drops a
  # connection mid-handshake would otherwise be caught by the
  # "Connection closed by [preauth]" branch.
  declare -A _accepted=()

  while IFS= read -r _line; do
    # Sanitise — strip chars outside the safe set (mirrors Perl regex)
    _line="${_line//[^a-zA-Z0-9: $'\t'\/@_()*/\[\].,\-]/}"

    # Collect accepted logins in the same pass — single read of auth.log
    if [[ "${_line}" =~ "Accepted " ]]; then
      local _acc_ip
      _acc_ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)
      _is_ipv4 "${_acc_ip}" && _accepted["${_acc_ip}"]=1
      continue
    fi

    local _ip=""

    if   [[ "${_line}" =~ "Failed password for root" ]] || \
         [[ "${_line}" =~ "Failed password for invalid user" ]] || \
         [[ "${_line}" =~ "Failed password for" && ! "${_line}" =~ "invalid user" ]]; then
      _line_is_recent "${_line}" || continue
      _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)

    elif [[ "${_line}" =~ "Invalid user" ]]; then
      # Catches empty-username probes: "Invalid user  from 1.2.3.4 port N"
      # These never produce a "Failed password" line so fall through without this branch.
      _line_is_recent "${_line}" || continue
      _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)

    elif [[ "${_line}" =~ "Received disconnect" && ! "${_line}" =~ "disconnected by user" ]]; then
      _line_is_recent "${_line}" || continue
      _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)

    elif [[ "${_line}" =~ "Timeout before authentication" ]]; then
      # Client connected but never completed auth within LoginGraceTime —
      # slow scanners or deliberate connection exhaustion.
      # Line format: "...from ATTACKER_IP to LOCAL_IP..." — take first IP match.
      _line_is_recent "${_line}" || continue
      _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | head -1)

    elif [[ "${_line}" =~ "Connection reset by" && "${_line}" =~ \[preauth\] ]]; then
      # TCP RST during key exchange — masscan-style scanners probing for sshd
      _line_is_recent "${_line}" || continue
      _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)

    elif [[ "${_line}" =~ "banner exchange" && "${_line}" =~ "invalid format" ]]; then
      # SSH protocol scanners that fail to complete the banner handshake
      _line_is_recent "${_line}" || continue
      _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)

    elif [[ "${_line}" =~ "Connection closed by" && "${_line}" =~ \[preauth\] && ! "${_line}" =~ "authenticating user" && ! "${_line}" =~ "invalid user" && ! "${_line}" =~ "disconnected by user" ]]; then
      # Port scanners that connect and immediately close with no auth attempt
      _line_is_recent "${_line}" || continue
      _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)
    fi

    _is_ipv4 "${_ip}" || continue
    # Skip IPs with a successful login in this log window
    [[ -n "${_accepted[${_ip}]+x}" ]] && continue
    (( _hits["${_ip}"]++ )) || true

  done < <(tail --lines=9999 /var/log/auth.log 2>/dev/null)

  local _sumar=0
  for _ip in "${!_hits[@]}"; do
    local _count="${_hits[${_ip}]}"
    (( _sumar += _count ))

    # Skip if already logged within current TTL window (prevents duplicate bans)
    _already_logged "${_ip}" && continue

    echo "${_ip} # [x${_count}] ${_mark}" >> "${_SSH_LOG}"
    echo "${_ip} # [x${_count}] ${_mark}" >> "${_SSH_ARCHIVE}"
    _csf_ban "${_ip}"
  done

  printf "\n===[%s]\tGLOBAL===\n\n" "${_sumar}"
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------

_acquire_lock
_makeactions
echo "CONTROL complete"
