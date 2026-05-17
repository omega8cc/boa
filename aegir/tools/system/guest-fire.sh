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
_FIRE_TIMEOUT=55   # seconds — just under the 1-minute cron interval

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
# Function Definitions
# ----------------------------

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
  if [[ -e "/root/.debug.monitor.log.cnf" || "${_NGINX_DOS_LOG}" =~ ^(NORMAL|VERBOSE)$ ]]; then
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

# Function to run procedure in a loop
_guest_guard() {

  if [ -e "/var/xdrago/monitor/log/ssh.log" ]; then
    # Process each unique IP from the log file
    cut -d '#' -f1 "/var/xdrago/monitor/log/ssh.log" | sort | uniq | while read -r _IP; do
      # Reset control variables
      _FW_CLEAN=
      _FW_TEST=
      _FF_TEST=
      # Retrieve CSF status for the IP
      _FW_TEST=$(csf -g ${_IP} 2>&1)
      # Check if the IP is allowed in csf.allow for TCP port 22
      _FF_TEST=$(grep -E "^tcp\|in\|d=22\|s=${_IP}\b" "/etc/csf/csf.allow" || true)
      # Determine if the IP is allowed or needs to be denied
      if [[ "${_FF_TEST}" =~ ${_IP} ]] || [[ "${_FW_TEST}" =~ ALLOW.*ACCEPT.*dpt:22 ]]; then
        echo "${_IP} is allowed on port 22"
        _verbose_log "ALLOWED" "${_IP} is allowed on port 22"
        _FW_CLEAN="YES"
        if [[ "${_FW_CLEAN}" == "YES" ]]; then
          echo "Removing ${_IP} potential blocks on port 22"
          csf -dr ${_IP}
          csf -tr ${_IP}
          _verbose_log "CLEAN" "Removing ${_IP} potential blocks on port 22"
        fi
      elif [[ "${_FW_TEST}" =~ DENY.*DROP.*dpt:22 ]]; then
        echo "${_IP} already denied on port 22"
        _verbose_log "DENIED" "${_IP} already denied on port 22"
      else
        echo "Denying ${_IP} on port 22 in the next 15 min"
        csf -td ${_IP} 900 -p 22
        _verbose_log "DENY" "Denying ${_IP} on port 22 in the next 15 min"
      fi
      [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    done
  fi

  if [ -e "/var/xdrago/monitor/log/web.log" ]; then
    # Process each unique IP from the log file
    cut -d '#' -f1 "/var/xdrago/monitor/log/web.log" | sort | uniq | while read -r _IP; do
      # Reset control variables
      _FW_CLEAN=
      _FW_TEST=
      _FF_TEST=
      # Retrieve CSF status for the IP
      _FW_TEST=$(csf -g ${_IP} 2>&1)
      # Check if the IP is allowed in csf.allow for TCP port 80
      _FF_TEST=$(grep -E "^tcp\|in\|d=80\|s=${_IP}\b" "/etc/csf/csf.allow" || true)
      # Determine if the IP is allowed or needs to be denied
      if [[ "${_FF_TEST}" =~ ${_IP} ]] || [[ "${_FW_TEST}" =~ ALLOW.*ACCEPT.*dpt:80 ]]; then
        echo "${_IP} is allowed on port 80"
        _verbose_log "ALLOWED" "${_IP} is allowed on port 80"
        _FW_CLEAN="YES"
        if [[ "${_FW_CLEAN}" == "YES" ]]; then
          echo "Removing ${_IP} potential blocks on ports 443,80"
          csf -dr ${_IP}
          csf -tr ${_IP}
          _verbose_log "CLEAN" "Removing ${_IP} potential blocks on ports 443,80"
        fi
      elif [[ "${_FW_TEST}" =~ DENY.*DROP.*dpt:80 ]]; then
        echo "${_IP} already denied on port 80"
        _verbose_log "DENIED" "${_IP} already denied on port 80"
      elif [[ "${_FW_TEST}" =~ DENY.*DROP.*dpt:443 ]]; then
        echo "${_IP} already denied on port 443"
        _verbose_log "DENIED" "${_IP} already denied on port 443"
      else
        echo "Denying ${_IP} on ports 443,80 in the next 15 min"
        csf -td ${_IP} 900 -p 80
        csf -td ${_IP} 900 -p 443
        _verbose_log "DENY" "Denying ${_IP} on ports 443,80 in the next 15 min"
      fi
      [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    done
  fi

  if [ -e "/var/xdrago/monitor/log/ftp.log" ]; then
    # Process each unique IP from the log file
    cut -d '#' -f1 "/var/xdrago/monitor/log/ftp.log" | sort | uniq | while read -r _IP; do
      # Reset control variables
      _FW_CLEAN=
      _FW_TEST=
      _FF_TEST=
      # Retrieve CSF status for the IP
      _FW_TEST=$(csf -g ${_IP} 2>&1)
      # Check if the IP is allowed in csf.allow for TCP port 21
      _FF_TEST=$(grep -E "^tcp\|in\|d=21\|s=${_IP}\b" "/etc/csf/csf.allow" || true)
      # Determine if the IP is allowed or needs to be denied
      if [[ "${_FF_TEST}" =~ ${_IP} ]] || [[ "${_FW_TEST}" =~ ALLOW.*ACCEPT.*dpt:21 ]]; then
        echo "${_IP} is allowed on port 21"
        _verbose_log "ALLOWED" "${_IP} is allowed on port 21"
        _FW_CLEAN="YES"
        if [[ "${_FW_CLEAN}" == "YES" ]]; then
          echo "Removing ${_IP} potential blocks on port 21"
          csf -dr ${_IP}
          csf -tr ${_IP}
          _verbose_log "CLEAN" "Removing ${_IP} potential blocks on port 21"
        fi
      elif [[ "${_FW_TEST}" =~ DENY.*DROP.*dpt:21 ]]; then
        echo "${_IP} already denied on port 21"
        _verbose_log "DENIED" "${_IP} already denied on port 21"
      else
        echo "Denying ${_IP} on port 21 in the next 15 min"
        csf -td ${_IP} 900 -p 21
        _verbose_log "DENY" "Denying ${_IP} on port 21 in the next 15 min"
      fi
      [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    done
  fi

}

# Main execution
if [ -x "/usr/sbin/csf" ]; then
  # Main execution
  for _iteration in {1..5}; do
    echo "----------------------------"
    echo "Iteration ${_iteration}:"
    [ ! -e "/run/water.pid" ] && _guest_guard
    sleep 10
  done
fi

exit 0

