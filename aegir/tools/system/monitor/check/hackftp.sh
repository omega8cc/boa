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

# Byte-offset tracking — avoids re-reading the entire /var/log/messages on
# every run. On first run (or after log rotation) the last _FTP_LOG_BASELINE
# lines are used as a baseline; subsequent runs read only bytes appended since
# the previous execution.
readonly _MESSAGES_LOG="/var/log/messages"
readonly _MESSAGES_LOG_OFFSET_FILE="/var/log/scan_hackftp_lastpos"
readonly _FTP_LOG_BASELINE=999

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
# BOA runs pure-ftpd (DontResolve/-H), which logs to /var/log/messages as:
#   "... host pure-ftpd: (?@1.2.3.4) [WARNING] Authentication failed for user [name]"
#   "... host pure-ftpd: (?@1.2.3.4) [WARNING] Sorry, cleartext sessions are not accepted"
#
# The peer IP is the server-written "(?@<ip>)" prefix; the login name is
# attacker-controlled and logged later inside "[...]". We anchor extraction on
# that prefix so it is timestamp-position-invariant (classic AND ISO 8601 syslog)
# and can never be spoofed by an IP-shaped username.
# -----------------------------------------------------------------------------

_makeactions() {
  mkdir -p "${_LOG_DIR}"
  _recycle_log
  _set_timestamps

  local _mark
  _mark=$(date +%y%m%d-%H%M%S)

  declare -A _hits=()

  # -------------------------------------------------------------------------
  # Byte-offset tracking — read only new lines since the last run.
  # Mirrors the approach used in scan_nginx.sh.
  # -------------------------------------------------------------------------
  local _last_offset=0
  if [[ -f "${_MESSAGES_LOG_OFFSET_FILE}" ]]; then
    _last_offset=$(< "${_MESSAGES_LOG_OFFSET_FILE}")
  fi
  local _current_size=0
  if [[ -f "${_MESSAGES_LOG}" ]]; then
    _current_size=$(stat -c %s "${_MESSAGES_LOG}")
  fi
  # Reset on log rotation or truncation
  if (( _current_size < _last_offset )); then
    _last_offset=0
  fi

  if (( _last_offset == 0 )); then
    # First run or reset: process the last _FTP_LOG_BASELINE lines as a baseline
    exec 3< <(tail -n "${_FTP_LOG_BASELINE}" "${_MESSAGES_LOG}" 2>/dev/null)
  else
    # Process only new log entries since the last recorded byte offset
    exec 3< <(tail -c +$(( _last_offset + 1 )) "${_MESSAGES_LOG}" 2>/dev/null)
  fi

  while IFS= read -r _line <&3; do
    _line="${_line//[^a-zA-Z0-9: $'\t'\/@_()*/\[\].,\-]/}"

    if [[ "${_line}" =~ "Authentication failed for user" ]] || \
       [[ "${_line}" =~ "Sorry, cleartext sessions are not accepted" ]]; then

      _line_is_recent "${_line}" || continue

      # Extract the peer IP from pure-ftpd's server-written prefix -- the FIRST
      # parenthesised "(user@host)" token AFTER the "pure-ftpd:" program tag. That
      # tag is written by pure-ftpd/syslog, never the client, so anchoring on it is
      # injection-proof: the attacker-controlled login name (logged later inside
      # "[...]", and which may itself contain a "(x@1.2.3.4)" token because the
      # sanitiser keeps parentheses) can never be reached by the match. We take THAT
      # token's host and require it to be IPv4 -- we deliberately do NOT let a free
      # "@<ipv4>" =~ search run, because on a non-IPv4 first paren (an IPv6 or
      # IPv4-mapped peer) it would skip the real prefix and match the attacker's
      # "(x@8.8.8.8)" username token, banning an attacker-framed third party.
      # Position-invariant across classic and ISO 8601 syslog (the tag precedes both
      # message variants).
      #
      # IPv4-mapped IPv6 peer (::ffff:1.2.3.4 -- the default log form for an IPv4
      # client on a dual-stack pure-ftpd): recover the embedded IPv4 so a real
      # client is still banned. A pure IPv6 peer has no IPv4 form, so _is_ipv4 skips
      # it (csf is IPv4-only) rather than mis-attributing the ban.
      local _ip=""
      local _ftp_peer_re='pure-ftpd(\[[0-9]+\])?:[[:space:]]*\(([^()]*)@([^()]*)\)'
      if [[ "${_line}" =~ ${_ftp_peer_re} ]]; then
        _ip="${BASH_REMATCH[3]}"
      fi
      [[ "${_ip}" == *:*.*.*.* ]] && _ip="${_ip##*:}"

      _is_ipv4 "${_ip}" || continue
      (( _hits["${_ip}"]++ )) || true
    fi

  done
  exec 3<&-

  # Persist the new end-of-file offset for the next run
  if [[ -f "${_MESSAGES_LOG}" ]]; then
    stat -c %s "${_MESSAGES_LOG}" > "${_MESSAGES_LOG_OFFSET_FILE}"
  fi

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
