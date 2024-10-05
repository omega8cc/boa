#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Exit if more than 2 instances of the script are running
if (( $(pgrep -fc 'guest-fire.sh') > 2 )); then
  # Optional: Log too many instances
  echo "Too many guest-fire.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

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
  local _reason="${1}"
  local _message="${2}"
  local _timestamp
  local _log_file

  # Define log file paths
  local _csf_dry_log="/var/log/csf_dry_debug.log"
  local _csf_fail_log="/var/log/csf_fail_debug.log"
  local _csf_deny_log="/var/log/csf_deny_debug.log"
  local _csf_denied_log="/var/log/csf_denied_debug.log"
  local _csf_allow_log="/var/log/csf_allow_debug.log"

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
        echo "Denying ${_IP} on port 22 in the next 10min"
        csf -td ${_IP} 600 -p 22
        _verbose_log "DENY" "Denying ${_IP} on port 22 in the next 10min"
      fi
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
        echo "Denying ${_IP} on ports 443,80 in the next 10min"
        csf -td ${_IP} 600 -p 80
        csf -td ${_IP} 600 -p 443
        _verbose_log "DENY" "Denying ${_IP} on ports 443,80 in the next 10min"
      fi
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
        echo "Denying ${_IP} on port 21 in the next 10min"
        csf -td ${_IP} 600 -p 21
        _verbose_log "DENY" "Denying ${_IP} on port 21 in the next 10min"
      fi
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
###EOF2024###
