#!/bin/bash

# =============================================================================
# hackftp.sh — FTP auth abuse monitor for BOA
# Replaces: hackftp.pl
#
# Improvements over the Perl original:
#   - Handles both classic syslog and ISO 8601 timestamps (Debian 12+ rsyslog)
#   - Accepts current AND previous minute to close the cron timing race window
#   - _already_logged() check prevents duplicate log/ban entries within TTL
#   - noclobber lock prevents overlapping cron runs
#   - Rolling log recycled after _BAN_SECONDS to re-arm expired bans
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
readonly _FTP_LOG="${_LOG_DIR}/ftp.log"
readonly _FTP_ARCHIVE="${_LOG_DIR}/hackftp.archive.log"
readonly _LOCK_FILE="/var/run/hackftp.lock"
readonly _MAINTENANCE_FLAG="/var/xdrago/guest-fire.sh"
readonly _CSF="/usr/sbin/csf"

readonly _BAN_SECONDS=3600

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
# Timestamp helpers  (identical logic to hackcheck.sh — see comments there)
# -----------------------------------------------------------------------------

_NOW_IS=""
_PREV_IS=""
_NOW_IS_ISO=""
_PREV_IS_ISO=""

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
    local _line_min="${_first_field:0:16}"
    [[ "${_line_min}" == "${_NOW_IS_ISO}" || "${_line_min}" == "${_PREV_IS_ISO}" ]]
  else
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

_is_ipv4() {
  [[ "${1}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

_already_logged() {
  [[ -f "${_FTP_LOG}" ]] && grep -qE "^${1} #" "${_FTP_LOG}"
}

_csf_ban() {
  local _ip="${1}"
  [[ -e "${_MAINTENANCE_FLAG}" ]] && return 0
  [[ -x "${_CSF}" && -e "/etc/csf/csf.deny" ]] || return 0
  "${_CSF}" -td "${_ip}" "${_BAN_SECONDS}" -p 21 &>/dev/null
}

_recycle_log() {
  [[ -f "${_FTP_LOG}" ]] || return 0
  local _first_line _mark _mark_epoch _age_sec
  IFS= read -r _first_line < "${_FTP_LOG}"
  _mark="${_first_line##* }"
  if [[ "${_mark}" =~ ^([0-9]{2})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
    _mark_epoch=$(date -d "20${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" +%s 2>/dev/null)
    if [[ -n "${_mark_epoch}" ]]; then
      _age_sec=$(( $(date +%s) - _mark_epoch ))
      if (( _age_sec >= _BAN_SECONDS )); then
        rm -f "${_FTP_LOG}"
      fi
    fi
  fi
}

# -----------------------------------------------------------------------------
# Main detection logic  (replaces makeactions + verify_timestamp + check_ip)
#
# FTP log format in /var/log/messages:
#   "... host proftpd[N]: Authentication failed for user user@1.2.3.4"
#   "... host proftpd[N]: Sorry, cleartext sessions are not accepted from user@1.2.3.4"
#
# The Perl original extracts the 6th whitespace field (user@IP) then splits on @.
# We do the same via positional read, keeping it format-faithful while also
# supporting ISO 8601 timestamps (where field positions shift by one).
# -----------------------------------------------------------------------------

_makeactions() {
  mkdir -p "${_LOG_DIR}"
  _recycle_log
  _set_timestamps

  local _mark
  _mark=$(date +%y%m%d-%H%M%S)

  declare -A _hits=()

  while IFS= read -r _line; do
    _line="${_line//[^a-zA-Z0-9: $'\t'\/@_()*/\[\].,\-]/}"

    if [[ "${_line}" =~ "Authentication failed for user" ]] || \
       [[ "${_line}" =~ "Sorry, cleartext sessions are not accepted" ]]; then

      _line_is_recent "${_line}" || continue

      # Extract user@IP field — position differs between classic and ISO syslog:
      #   Classic:  "Mon DD HH:MM:SS host proc[N]: ... user@1.2.3.4"  → field 6
      #   ISO 8601: "YYYY-MM-DDTHH:MM:SS+TZ host proc[N]: ... user@1.2.3.4" → field 6
      # Field position is the same in both cases because the ISO timestamp is
      # one field (no spaces), so field count is identical.
      local _f1 _f2 _f3 _f4 _f5 _visitorx _rest
      read -r _f1 _f2 _f3 _f4 _f5 _visitorx _rest <<< "${_line}"

      # Strip trailing punctuation, then split on @ to get the IP part
      _visitorx="${_visitorx//[^a-zA-Z0-9.@]/}"
      local _ip="${_visitorx##*@}"
      _ip="${_ip//[^0-9.]/}"

      # Fallback: if field-based extraction didn't yield an IP, grep for it
      if ! _is_ipv4 "${_ip}"; then
        _ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' <<< "${_line}" | tail -1)
      fi

      _is_ipv4 "${_ip}" || continue
      (( _hits["${_ip}"]++ )) || true
    fi

  done < <(tail --lines=999 /var/log/messages 2>/dev/null)

  local _sumar=0
  for _ip in "${!_hits[@]}"; do
    local _count="${_hits[${_ip}]}"
    (( _sumar += _count ))

    _already_logged "${_ip}" && continue

    echo "${_ip} # [x${_count}] ${_mark}" >> "${_FTP_LOG}"
    echo "${_ip} # [x${_count}] ${_mark}" >> "${_FTP_ARCHIVE}"
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
