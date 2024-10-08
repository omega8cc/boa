#!/bin/bash

# ==============================
# Script to Monitor and Block Suspicious NGINX Activity
# ==============================

# Exit if more than 2 instances of the script are running
if (( $(pgrep -fc 'scan_nginx.sh') > 2 )); then
  # Optional: Log too many instances
  echo "Too many scan_nginx.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

# ==============================
# Configuration and Environment
# ==============================

# Enable verbose mode if debug configuration exists
if [[ -e "/root/.debug.monitor.cnf" ]]; then
  set -x
fi

# Enable strict error handling
#set -euo pipefail

# Set environment variables
export HOME='/root'
export PATH='/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin'

# Set Internal Field Separator for safe parsing
IFS=$'\n\t'

# Constants
_TIMES=$(date +%y%m%d-%H%M%S)
_MYIP=$(< /root/.found_correct_ipv4.cnf)

# ==============================
# Default Configuration Values
# ==============================

# Default number of lines to process from access.log (positive integer)
_NGINX_DOS_LINES=1999

# Default max allowed number for blocking (positive integer)
_NGINX_DOS_LIMIT=399

# Default mode (1 or 2)
_NGINX_DOS_MODE=2

# Default logging mode, can be SILENT (none), NORMAL or VERBOSE
_NGINX_DOS_LOG=SILENT

# Default exclude keywords (empty by default; 'doccomment' will be used if not overridden)
_NGINX_DOS_IGNORE="doccomment"

# Default DoS keywords (empty by default; 'foobar' will be used if not overridden)
_NGINX_DOS_STOP="foobar"

# Precompute increments based on _NGINX_DOS_LIMIT
_INC_NUMBER=$(( (_NGINX_DOS_LIMIT + 2) / 4 ))  # Approx division by 4
_INC_S_NUMBER=$(( (_NGINX_DOS_LIMIT + 4) / 8 ))  # Approx division by 8

echo "CONFIG: _NGINX_DOS_LIMIT is ${_NGINX_DOS_LIMIT}"
echo "CONFIG: _NGINX_DOS_LINES is ${_NGINX_DOS_LINES}"
echo "CONFIG: _INC_NUMBER is ${_INC_NUMBER}"
echo "CONFIG: _INC_S_NUMBER is ${_INC_S_NUMBER}"

# ==============================
# Load Configuration File
# ==============================

_CONFIG_FILE="/root/.barracuda.cnf"

if [[ -e "${_CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${_CONFIG_FILE}"
fi

# ==============================
# Declare Associative Arrays
# ==============================

declare -A _BANNED_IPS
declare -A _ALLOWED_IPS
declare -A _LOGGED_IN_IPS
declare -A _COUNTERS
declare -A _LI_CNT
declare -A _PX_CNT

# Debugging: Confirm associative arrays are declared
if [[ -e "/root/.debug.monitor.cnf" ]]; then
  declare -p _BANNED_IPS _ALLOWED_IPS _LOGGED_IN_IPS _COUNTERS _LI_CNT _PX_CNT
  echo "DEBUG: Associative arrays _BANNED_IPS, _ALLOWED_IPS, _LOGGED_IN_IPS, _COUNTERS, _LI_CNT, and _PX_CNT have been declared."
fi

# ==============================
# Helper Functions
# ==============================

# Function for logging in verbose mode
_verbose_log() {
  local _reason="${1}"
  local _message="${2}"
  local _timestamp
  local _log_file

  # Define log file paths
  local _general_log="/var/log/scan_nginx_debug.log"
  local _flood_log="/var/log/scan_nginx_flood_debug.log"
  local _admin_log="/var/log/scan_nginx_admin_debug.log"

  # Check if logging is enabled
  if [[ -e "/root/.debug.monitor.log.cnf" || "${_NGINX_DOS_LOG}" =~ ^(NORMAL|VERBOSE)$ ]]; then
    if [[ "${_reason}" =~ Counter && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_flood_log}"
    elif [[ "${_reason}" =~ "Admin URI To Ignore" && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_admin_log}"
    else
      _log_file="${_general_log}"
    fi

    # Generate timestamp
    _timestamp=$(date)

    # Write to the appropriate log file using printf
    printf "%s %s REASON: %s\n" "${_timestamp}" "${_reason}" "${_message}" >> "${_log_file}"
  fi
}

# Function to validate IP format
_validate_ip() {
  local _IP="$1"

  # Remove any trailing punctuation (comma, period)
  _IP="${_IP%,}"
  _IP="${_IP%.}"

  if [[ "${_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    # Further validate each octet is between 0 and 255
    IFS='.' read -r _a _b _c _d <<< "${_IP}"
    if (( _a <= 255 && _b <= 255 && _c <= 255 && _d <= 255 )); then
      return 0
    fi
  fi
  return 1
}

# Function to resolve the real IP address by traversing proxies
_resolve_real_ip_traversal() {
  local _VISITOR="$1"
  local _PROXY1="$2"
  local _PROXY2="$3"
  local _PROXY3="$4"

  local _REAL_IP="${_VISITOR}"
  local _PROXIES_TO_CHECK=()

  # Traverse proxies up to 3 levels
  for _proxy in "${_PROXY1}" "${_PROXY2}" "${_PROXY3}"; do
    if [[ "${_REAL_IP}" =~ ^(192\.168\.|172\.16\.|unknown|10\.|127\.0\.) ]]; then
      if [[ -n "${_proxy}" ]]; then
        _PROXIES_TO_CHECK+=("${_REAL_IP}")
        _REAL_IP="${_proxy}"
      else
        break
      fi
    else
      break
    fi
  done

  # Final check if the last IP is still private
  if [[ "${_REAL_IP}" =~ ^(192\.168\.|172\.16\.|unknown|10\.|127\.0\.) ]]; then
    _PROXIES_TO_CHECK+=("${_REAL_IP}")
    _REAL_IP=""
  fi

  # Return real IP and proxies to check, each on separate lines
  # _verbose_log "${_REAL_IP}" "_REAL_IP to check"
  echo "${_REAL_IP}"
  for _proxy in "${_PROXIES_TO_CHECK[@]}"; do
    _verbose_log "${_proxy}" "_PROXIES_TO_CHECK"
    echo "${_proxy}"
  done
}

# Function to check if an IP is banned using associative array
_is_banned_or_allowed() {
  local _IP="$1"
  if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP}" "_is_banned_or_allowed"
    echo "=== _is_banned_or_allowed ${_IP} ==="
    return 0
  fi
  return 1
}

# Function to check if an IP is allowed (local) using associative array
_is_allowed_local() {
  local _IP="$1"
  if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP}" "_is_allowed_local"
    echo "=== _is_allowed_local ${_IP} ==="
    return 0
  fi
  return 1
}

# Function to check if an IP is logged in using associative array
_is_logged_in() {
  local _IP="$1"
  if [[ -n "${_LOGGED_IN_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP}" "_is_logged_in"
    echo "=== _is_logged_in ${_IP} ==="
    return 0
  fi
  return 1
}

# Function to log and block an IP
_block_ip() {
  local _IP="$1"

  # Append to web.log if not already present
  if [[ ! -f "/var/xdrago/monitor/log/web.log" ]] || ! grep -q "^${_IP} " "/var/xdrago/monitor/log/web.log"; then
    _verbose_log "${_IP} # [x${_sumar}] ${_TIMES}" "_block_ip"
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/web.log
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/scan_nginx.archive.log
    echo "===[${_sumar}] ${_IP} ADDED TO BLOCK LIST monitor/log/web.log ==="
  else
    echo "===[${_sumar}] ${_IP} ALREADY LISTED IN monitor/log/web.log ==="
  fi

  # Add the blocked IP to _BANNED_IPS to prevent duplicates within the same run
  _BANNED_IPS["${_IP}"]=1

  # Block the IP using csf instantly but only for 15 minutes initially
  # this can be extended up to 1 hour once guest-fire.sh notices the IP
  # still present in /var/xdrago/monitor/log/web.log but no longer blocked
  if [[ -x "/usr/sbin/csf" ]]; then
    /usr/sbin/csf -td "${_IP}" 900 -p 80
    /usr/sbin/csf -td "${_IP}" 900 -p 443
  fi
}

# Function to increment counters based on specific suspicious log patterns
_if_increment_counters() {
  if [[ "${_IP}" = "unknown" ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NUMBER ))
    _verbose_log "Counter++ for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "unknown"
  fi
  if [[ "${_line}" =~ '" 404' ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NUMBER ))
    _verbose_log "Counter++ for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "404 flood protection"
  fi
  if [[ "${_line}" =~ '" 403' ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NUMBER ))
    _verbose_log "Counter++ for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "403 flood protection"
  fi
  if [[ "${_line}" =~ '" 500' ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NUMBER ))
    _verbose_log "Counter++ for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "500 flood protection"
  fi
  if [[ "${_line}" =~ wp-(content|admin|includes) ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NUMBER ))
    _verbose_log "Counter++ for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "wp-x flood protection"
  fi
  if [[ "${_line}" =~ "(POST|GET) /user/login" ]]; then
    (( _COUNTERS["${_IP}"] += _INC_S_NUMBER ))
    _verbose_log "Counter++ for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/user/login flood protection"
  fi
}

# Function to process each IP
_process_ip() {
  local _IP="$1"
  local _COUNT_REF="$2"
  local _line="$3"
  local _IGNORE_ADMIN=0
  local _SKIP_POST=0

  # Debug: Print the value of _COUNT_REF
  # _verbose_log "${_IP} with counter reference: ${_COUNT_REF}" "_process_ip"

  # Validate that _COUNT_REF is a recognized associative array
  if [[ "${_COUNT_REF}" != "_LI_CNT" && "${_COUNT_REF}" != "_PX_CNT" ]]; then
    _verbose_log "Error: _COUNT_REF '${_COUNT_REF}' is not a recognized associative array" "_process_ip"
    echo "Error: _COUNT_REF '${_COUNT_REF}' is not a recognized associative array."
    return
  fi

  # Reference the appropriate counter array
  local -n _COUNTERS=${_COUNT_REF}

  # Validate IP format
  if ! _validate_ip "${_IP}"; then
    _verbose_log "Invalid IP format: ${_IP} -- Skipping" "_validate_ip"
    echo "Invalid IP format: ${_IP} -- Skipping."
    return
  fi

  # Skip private and local IPs
  if [[ "${_IP}" =~ ^(192\.168\.|172\.16\.|10\.|127\.0\.) ]]; then
    _verbose_log "Private IP ${_IP} -- Skipping" "_validate_ip"
    echo "Private IP ${_IP} -- Skipping."
    return
  fi

  # Initialize or increment the counter safely
  if [[ -v _COUNTERS["${_IP}"] ]]; then
    (( _COUNTERS["${_IP}"]++ ))
  else
    _COUNTERS["${_IP}"]=1
  fi

  # Define lines to check
  if [[ "${_line}" =~ (GET|HEAD|POST) && ! "${_line}" =~ '" 301' ]]; then

    # Define admin URIs to ignore
    if [[ "${_line}" =~ /admin/content || \
        "${_line}" =~ POST\ /quickedit || \
        "${_line}" =~ POST\ /node/add || \
        "${_line}" =~ GET\ /entity_reference_autocomplete || \
        "${_line}" =~ POST\ /entity-browser || \
        "${_line}" =~ POST\ /contextual/render || \
        "${_line}" =~ POST\ /node/ ]]; then
      _IGNORE_ADMIN=1
      _verbose_log "Admin URI To Ignore" "${_line}"
    fi

    # Define other patterns to skip
    if [[ "${_line}" =~ (GET|POST)\ /([a-z]{2}/)?(civicrm|batch|advagg|views-bulk-operations|node/[0-9]+/edit|media/browser) || \
        "${_line}" =~ (GET|POST)\ /([a-z]{2}/)?(hosting|system|admin|app|ckeditor)/ || \
        "${_line}" =~ \b(/files/css/css_)\b || \
        "${_line}" =~ \b(/files/js/js_)\b || \
        "${_line}" =~ \b(/files/advagg_)\b || \
        "${_line}" =~ \b(ajax|autocomplete|shs)\b || \
        "${_line}" =~ \b(plupload|json|api/rest)\b || \
        "${_line}" =~ GET\ /(filefield_nginx_progress|filefield/progress|files/progress|file/progress|elfinder/connector) || \
        "${_line}" =~ POST\ /js/ ]]; then
      _SKIP_POST=1
      _IGNORE_ADMIN=1
    elif [[ "${_line}" =~ files/(imagecache|styles|media) ]]; then
      _SKIP_POST=1
    elif [[ "${_line}" =~ GET\ /.*\.(mp4|m4a|flv|avi|mpeg|mov|wmv|mp3|ogg|ogv|wav|midi|zip|tar|tgz|rar|dmg|exe|apk|pxl|ipa)\" ]]; then
      _SKIP_POST=1
    elif [[ "${_line}" =~ GET\ /timemachine/[0-9]{4}/ ]]; then
      _SKIP_POST=1
    elif [[ "${_line}" =~ POST\ /.*\/cart\/checkout ]]; then
      _SKIP_POST=1
    elif [[ "${_line}" =~ POST\ /.*\/embed\/preview ]]; then
      _SKIP_POST=1
    elif [[ "${_line}" =~ files\.aegir\.cc ]]; then
      _SKIP_POST=1
    fi

    # Exclude based on _NGINX_DOS_IGNORE or default to 'doccomment'
    if [[ -n "${_NGINX_DOS_IGNORE}" ]]; then
      if [[ "${_line}" =~ (${_NGINX_DOS_IGNORE}) ]]; then
        _SKIP_POST=1
      fi
    else
      if [[ "${_line}" =~ doccomment ]]; then
        _SKIP_POST=1
      fi
    fi

    if [[ "${_SKIP_POST}" -eq 1 || "${_IGNORE_ADMIN}" -eq 1 ]]; then
      return
    fi

    # Check if the IP is present in the csf.allow list early
    _FF_TEST=$(grep -E "^tcp\|in\|d=80\|s=${_IP}\b" "/etc/csf/csf.allow")

    # Determine if the IP is allowed or needs to be denied early
    if [[ "${_FF_TEST}" =~ ${_IP} ]]; then
      return
    fi

    # Increment counter if not excluded
    (( _COUNTERS["${_IP}"]++ ))
  fi

  # Additional counting based on mode
  if [[ "${_SKIP_POST}" -eq 0 || "${_IGNORE_ADMIN}" -eq 0 ]]; then

    _if_increment_counters

    if [[ "${_NGINX_DOS_MODE}" -eq 1 ]]; then
      if [[ "${_line}" =~ POST && "${_line}" =~ (/user|user/(register|pass|login)|node/add) ]]; then
        (( _COUNTERS["${_IP}"] += 5 ))
      fi
      if [[ "${_line}" =~ GET && "${_line}" =~ node/add ]]; then
        (( _COUNTERS["${_IP}"] += 3 ))
      fi
      if [[ -n "${_NGINX_DOS_STOP}" ]]; then
        if [[ "${_line}" =~ (${_NGINX_DOS_STOP}) ]]; then
          (( _COUNTERS["${_IP}"] += 5 ))
        fi
      fi
    else
      if [[ "${_line}" =~ POST ]]; then
        (( _COUNTERS["${_IP}"] += 1 ))
      fi
      if [[ -n "${_NGINX_DOS_STOP}" ]]; then
        if [[ "${_line}" =~ (${_NGINX_DOS_STOP}) ]]; then
          (( _COUNTERS["${_IP}"] += 5 ))
        fi
      fi
    fi
  fi
}

# Function to handle blocking actions
_handle_blocking() {
  local -n _COUNTERS=$1
  local _TYPE=$2

  # Debug: Confirm that _COUNTERS is correctly referencing the intended array
  if [[ -n "${1}" && -e "/root/.debug.monitor.cnf" ]]; then
    declare -p _COUNTERS
    echo "DEBUG: _COUNTERS in _handle_blocking is referencing '${1}'"
  fi

  for _IP in "${!_COUNTERS[@]}"; do
    local _COUNT="${_COUNTERS["${_IP}"]}"
    local _CRITNUMBER="${_NGINX_DOS_LIMIT}"
    local _MININUMBER=$(( (_CRITNUMBER + 1) / 2 ))  # To handle integer division correctly

    if (( _COUNT > _MININUMBER )); then
      if _is_logged_in "${_IP}"; then
        _CRITNUMBER=9999
      fi

      if [[ "${_IP}" == "${_MYIP}" ]]; then
        _CRITNUMBER=9998
      fi

      echo "===[${_CRITNUMBER}] MAX ${_TYPE} critnumber for ${_IP} ==="
      echo "===[${_COUNT}] COUNTER ${_TYPE} counter for ${_IP} ==="

      # Check if IP is already allowed
      if _is_allowed_local "${_IP}"; then
        continue
      fi

      # Check if IP is already banned
      if _is_banned_or_allowed "${_IP}"; then
        continue
      fi

      if (( _COUNT > _CRITNUMBER )); then
        _sumar="${_COUNT}"
        echo "=== block_ip ${_IP} ${_COUNT}/${_CRITNUMBER} ==="
        _block_ip "${_IP}"
      fi
    fi
  done
}

# ==============================
# Load Banned and Allowed IPs Lists
# ==============================

# Load banned IPs from web.log into associative array
_WEB_LOG="/var/xdrago/monitor/log/web.log"
if [[ -e "${_WEB_LOG}" ]]; then
  while IFS= read -r _line; do
    # Extract IP before any space or comment
    _ip="${_line%% *}"
    # Clean IP
    _ip="${_ip//[^0-9.]/}"
    if [[ -n "${_ip}" ]]; then
      _BANNED_IPS["${_ip}"]=1
    fi
  done < "${_WEB_LOG}"
fi

# Load allowed local IPs into associative array
_LOCAL_IP_LIST="/root/.local.IP.list"
if [[ -e "${_LOCAL_IP_LIST}" ]]; then
  while IFS= read -r _line; do
    _ip="${_line%% *}"
    _ip="${_ip//[^0-9.]/}"
    if [[ -n "${_ip}" ]]; then
      _ALLOWED_IPS["${_ip}"]=1
    fi
  done < "${_LOCAL_IP_LIST}"
fi

# ==============================
# Load Logged-In IPs
# ==============================

if command -v who &> /dev/null; then
  while IFS= read -r _logged_ip; do
    # Validate IP format using the existing function
    if _validate_ip "${_logged_ip}"; then
      _LOGGED_IN_IPS["${_logged_ip}"]=1
    fi
  done < <(who --ips | awk '{print $5}' | tr -dc '0-9.\n')
fi

# ==============================
# Processing the Access Log
# ==============================

# Read the access log once using file descriptor 3 for efficiency
exec 3< <(tail -n "${_NGINX_DOS_LINES}" /var/log/nginx/access.log)

while IFS= read -r _line <&3; do
  # Extract the first quoted string containing IPs
  if [[ "${_line}" =~ \"([^\"]*)\" ]]; then
    _ip_str="${BASH_REMATCH[1]}"
  else
    _ip_str=""
  fi

  # Split the IP string by comma and space
  IFS=',' read -ra _ip_array <<< "${_ip_str}"
  # Trim spaces around IPs
  for i in "${!_ip_array[@]}"; do
    _ip_array[i]="${_ip_array[i]## }"
    _ip_array[i]="${_ip_array[i]% }"
  done

  # Extract valid IPs using Bash's regex
  _IP_LIST=()
  for _ip_candidate in "${_ip_array[@]}"; do
    if [[ "${_ip_candidate}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      _IP_LIST+=("${_ip_candidate}")
    fi
  done

  # Debug: Print extracted IPs
  if [[ -e "/root/.debug.monitor.cnf" ]]; then
    echo "DEBUG: Extracted IPs: ${_IP_LIST[*]}"
  fi

  # Assign visitor IP and up to three proxies
  _VISITOR="${_IP_LIST[0]:-}"
  _PROXY1="${_IP_LIST[1]:-}"
  _PROXY2="${_IP_LIST[2]:-}"
  _PROXY3="${_IP_LIST[3]:-}"

  # Resolve real IP and collect proxies to block
  readarray -t _resolved_ips < <(_resolve_real_ip_traversal "${_VISITOR}" "${_PROXY1}" "${_PROXY2}" "${_PROXY3}")

  _REAL_IP="${_resolved_ips[0]:-}"
  _PROXIES_ARRAY=("${_resolved_ips[@]:1}")

  # Debug: Echo the real visitor and proxy IPs if debug config exists
  if [[ -n "${_REAL_IP}" && -e "/root/.debug.monitor.cnf" ]]; then
    echo "=== checking ${_REAL_IP} / _LI_CNT ==="
  fi
  for _proxy_ip in "${_PROXIES_ARRAY[@]}"; do
    if [[ -n "${_proxy_ip}" && -e "/root/.debug.monitor.cnf" ]]; then
      echo "=== checking ${_proxy_ip} / _PX_CNT ==="
    fi
  done

  # Process REAL_IP if exists
  if [[ -n "${_REAL_IP}" ]]; then
    _process_ip "${_REAL_IP}" "_LI_CNT" "${_line}"
  fi

  # Process PROXY_IPs to block
  for _proxy_ip in "${_PROXIES_ARRAY[@]}"; do
    if [[ -n "${_proxy_ip}" ]]; then
      _process_ip "${_proxy_ip}" "_PX_CNT" "${_line}"
    fi
  done

done

# Close the file descriptor
exec 3<&-

# ==============================
# Execute Blocking Logic
# ==============================

_handle_blocking _LI_CNT "li_cnt"
_handle_blocking _PX_CNT "px_cnt"

echo "CONTROL complete for ${_MYIP}"
exit 0
