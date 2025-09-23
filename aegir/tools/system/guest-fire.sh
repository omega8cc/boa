#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Protect from high load due to csf loop/flood
_csf_flood_guard() {
  _thisCountCsf=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/csf"`
  if [ ! -e "/run/boa_run.pid" ] && [ ${_thisCountCsf} -gt 4 ]; then
    echo "$(date) Too many ${_thisCountCsf} csf processes killed" >> \
      /var/log/csf-count.kill.log
    kill -9 $(ps aux | grep '[c]sf' | awk '{print $2}') &> /dev/null
    csf -tf
    wait
    csf -df
    wait
  fi
  _thisCountFire=`ps aux | grep -v "grep" | grep -v "null" | grep --count "fire.sh"`
  if [ ! -e "/run/boa_run.pid" ] && [ ${_thisCountFire} -gt 9 ]; then
    echo "$(date) Too many ${_thisCountFire} fire.sh processes killed and rules purged" >> \
      /var/log/fire-purge.kill.log
    csf -tf
    wait
    csf -df
    wait
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  elif [ ! -e "/run/boa_run.pid" ] && [ ${_thisCountFire} -gt 7 ]; then
    echo "$(date) Too many ${_thisCountFire} fire.sh processes killed" >> \
      /var/log/fire-count.kill.log
    csf -tf
    wait
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  fi
  [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
}
[ ! -e "/run/water.pid" ] && _csf_flood_guard

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "$_L" ] && . "$_L" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc "[${_SCRIPT:0:1}]${_SCRIPT:1}")
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
  _timestamp
  _log_file

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
  for _iteration in {1..3}; do
    echo "----------------------------"
    echo "Iteration ${_iteration}:"
    [ ! -e "/run/water.pid" ] && _guest_guard
    sleep 15
  done
fi

exit 0

