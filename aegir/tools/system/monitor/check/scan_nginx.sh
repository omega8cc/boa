#!/bin/bash

# ==============================
# Script to Monitor and Block Suspicious NGINX Activity
# ==============================

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
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

# ==============================
# Configuration and Environment
# ==============================

# Enable verbose mode if debug configuration exists
if [[ -e "/root/.debug.monitor.cnf" ]]; then
  set -x
fi

# Enable strict error handling (optional)
# set -euo pipefail

# Set environment variables
export HOME='/root'
export PATH='/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin'

# Set Internal Field Separator for safe parsing
IFS=$'\n\t'

# Constants
_TIMES=$(date +%y%m%d-%H%M%S)
_MYIP=$(< /root/.found_correct_ipv4.cnf)

# Function to perform rounded division
_inc_round_division() {
  local numerator=$1
  local denominator=$2
  echo $(( (numerator + (denominator / 2)) / denominator ))
}

# ==============================
# Default Configuration Values
# ==============================

# Default number of lines to process from access.log (positive integer)
_NGINX_DOS_LINES=1999

# Default max allowed number for blocking (positive integer)
_NGINX_DOS_LIMIT=399

# Default mode (1 or 2)
_NGINX_DOS_MODE=2

# Default divisor for increments (positive integer)
_NGINX_DOS_DIV_INC_NR=40
_NGINX_DOS_DIV_INC_S_NR=$(( _NGINX_DOS_DIV_INC_NR * 2 ))

# Default min allowed number for increments (positive integer)
_NGINX_DOS_INC_MIN=3

# Default logging mode, can be SILENT (none), NORMAL or VERBOSE
_NGINX_DOS_LOG=VERBOSE

# Default exclude keywords (empty by default; 'doccomment' will be used if not overridden)
_NGINX_DOS_IGNORE="doccomment"

# Default DoS keywords (empty by default; 'foobar' will be used if not overridden)
_NGINX_DOS_STOP="foobar"

# ==============================
# Load Configuration File
# ==============================

_CONFIG_FILE="/root/.barracuda.cnf"

if [[ -e "${_CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${_CONFIG_FILE}"
fi

# ==============================
# Validate and adjust variables
# ==============================

# Config Constants
_MAX_LIMIT=${_NGINX_DOS_LINES}
_MIN_LIMIT=$(_inc_round_division "${_MAX_LIMIT}" "40")
_DEFAULT_LIMIT=$(_inc_round_division "${_MAX_LIMIT}" "5")

# Validate _NGINX_DOS_INC_MIN: must be a positive integer
if ! [[ "${_NGINX_DOS_INC_MIN}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Warning: Invalid _NGINX_DOS_INC_MIN ('${_NGINX_DOS_INC_MIN}'). Setting to default (3)."
  _NGINX_DOS_INC_MIN=3
fi

# Validate _NGINX_DOS_LIMIT: must be a number within the range
if ! [[ "${_NGINX_DOS_LIMIT}" =~ ^[0-9]+$ ]] || (( _NGINX_DOS_LIMIT < _MIN_LIMIT || _NGINX_DOS_LIMIT > _MAX_LIMIT )); then
  echo "Warning: Invalid _NGINX_DOS_LIMIT ('${_NGINX_DOS_LIMIT}'). Setting to default (${_DEFAULT_LIMIT})."
  _NGINX_DOS_LIMIT=${_DEFAULT_LIMIT}
fi

# Calculate increments with rounded division
_INC_NR=$(_inc_round_division "${_NGINX_DOS_LIMIT}" "${_NGINX_DOS_DIV_INC_NR}")
_INC_S_NR=$(_inc_round_division "${_NGINX_DOS_LIMIT}" "${_NGINX_DOS_DIV_INC_S_NR}")

# Ensure increments are at least _NGINX_DOS_INC_MIN
_INC_NR=$(( _INC_NR < _NGINX_DOS_INC_MIN ? _NGINX_DOS_INC_MIN : _INC_NR ))
_INC_S_NR=$(( _INC_S_NR < _NGINX_DOS_INC_MIN ? _NGINX_DOS_INC_MIN : _INC_S_NR ))

echo "CONFIG: _NGINX_DOS_LIMIT is ${_NGINX_DOS_LIMIT}"
echo "CONFIG: _NGINX_DOS_LINES is ${_NGINX_DOS_LINES}"
echo "CONFIG: _INC_NR is ${_INC_NR}"
echo "CONFIG: _INC_S_NR is ${_INC_S_NR}"

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
  local _log_file="/dev/null"

  # Define log file paths
  local _general_log="/var/log/scan_nginx_debug.log"
  local _flood_log="/var/log/scan_nginx_flood_debug.log"
  local _admin_log="/var/log/scan_nginx_admin_debug.log"
  local _other_log="/var/log/scan_nginx_other_debug.log"

  # Check if logging is enabled
  if [[ -e "/root/.debug.monitor.log.cnf" || "${_NGINX_DOS_LOG}" =~ ^(NORMAL|VERBOSE)$ ]]; then
    if [[ "${_reason}" =~ Counter && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_flood_log}"
    elif [[ "${_reason}" =~ "Admin URI To Ignore" && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_admin_log}"
    elif [[ "${_reason}" =~ "Other URI To Ignore" && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_other_log}"
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

# NOTE: Removed _resolve_real_ip_traversal function (its logic is inlined in the main loop for performance)

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
  # Append to web.log if not already present (use in-memory cache to avoid grep each time)
  if [[ -z "${_BANNED_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP} # [x${_sumar}] ${_TIMES}" "_block_ip"
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/web.log
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/scan_nginx.archive.log
    echo "===[${_sumar}] ${_IP} ADDED TO BLOCK LIST monitor/log/web.log ==="
  else
    echo "===[${_sumar}] ${_IP} ALREADY LISTED IN monitor/log/web.log ==="
  fi
  # Mark IP as banned in this run to prevent duplicate processing
  _BANNED_IPS["${_IP}"]=1

  # Block the IP using csf instantly (temporary block for 15 minutes)
  if [[ -x "/usr/sbin/csf" ]] && [[ -e "/root/.instant.csf.block.cnf" ]]; then
    /usr/sbin/csf -td "${_IP}" 900 -p 80
    /usr/sbin/csf -td "${_IP}" 900 -p 443
    [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
  fi
}

# Function to increment counters based on specific suspicious log patterns
_if_increment_counters() {
  if [[ "${_IP}" = "unknown" ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NR ))
    _verbose_log "Counter++ ${_INC_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "unknown"
  fi
  # Combine checks for HTTP status 400, 404, 403, 500 to increment counters in one go
  if [[ "${_line}" =~ \"\ (400|404|403|500) ]]; then
    local _code="${BASH_REMATCH[1]}"
    (( _COUNTERS["${_IP}"] += _INC_NR ))
    _verbose_log "Counter++ ${_INC_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "${_code} flood protection"
  fi
  if [[ "${_line}" =~ wp-(content|admin|includes|json) ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NR ))
    _verbose_log "Counter++ ${_INC_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "wp-x flood protection"
  fi
  if [[ "${_line}" =~ (POST|GET)\ /user/login ]]; then
    (( _COUNTERS["${_IP}"] += _INC_S_NR ))
    _verbose_log "Counter++ ${_INC_S_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/user/login flood protection"
  fi
}

# Function to process each IP
_process_ip() {
  local _IP="$1"
  local _COUNT_REF="$2"
  local _line="$3"
  local _IGNORE_ADMIN=0
  local _IGNORE_OTHER=0

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

  # Skip private network and localhost IPs immediately
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    _verbose_log "Private IP ${_IP} -- Skipping" "_process_ip"
    echo "Private IP ${_IP} -- Skipping."
    return
  fi

  # Only examine lines that are GET/HEAD/POST (ignore lines with " 301" redirect)
  if [[ "${_line}" =~ (GET|HEAD|POST) && ! "${_line}" =~ \"\ 301 ]]; then

    # Define admin URIs to ignore (combine multiple patterns into one regex for efficiency)
    if [[ "${_line}" =~ (GET|POST)\ /([a-z]{2}/)?(admin/content|quickedit|node/add|node/[0-9]+/edit|entity_reference_autocomplete|(hosting|system|admin|app|ckeditor)/|entity-browser|contextual/render|views-bulk-operations|civicrm|batch|media/browser).*\"\ (200|302) ]]; then
      _IGNORE_ADMIN=1
    fi
    # If an admin request resulted in a 403 or contains typical WP paths, do not ignore (these might be attacks)
    if [[ "${_line}" =~ (GET|HEAD|POST)\ /.*\"\ 403 ]] || [[ "${_line}" =~ wp-(content|admin|includes|json) ]]; then
      _IGNORE_ADMIN=0
    fi
    if [[ "${_IGNORE_ADMIN}" -eq 1 ]]; then
      _verbose_log "Admin URI To Ignore" "${_line}"
      return
    fi

    # Define other patterns to skip (combined multiple checks into one conditional with OR)
    if [[ "${_line}" =~ (GET|POST)\ /([a-z]{2}/)?advagg.*\"\ (200|302) || "${_line}" =~ /files/css/css_ || "${_line}" =~ /files/js/js_ || "${_line}" =~ /files/advagg_ || "${_line}" =~ /files/(imagecache|styles) || "${_line}" =~ (ajax|autocomplete|shs).*\"\ (200|302) || "${_line}" =~ (plupload|json|api/rest).*\"\ (200|302) || "${_line}" =~ GET\ /(filefield/progress|files/progress|file/progress|elfinder/connector).*\"\ (200|302) || "${_line}" =~ POST\ /js/.*\"\ (200|302) || "${_line}" =~ /files/media.*\"\ (200|302) || "${_line}" =~ GET\ /.*\.(mp4|m4a|flv|avi|mpeg|mov|wmv|mp3|ogg|ogv|wav|midi|zip|tar|tgz|rar|dmg|exe|apk|pxl|ipa|jpe?g|gif|png|ico).*\"\ (200|302) || "${_line}" =~ GET\ /timemachine/[0-9]{4}/.*\"\ (200|302) || "${_line}" =~ POST\ /.*/(cart/checkout|embed/preview).*\"\ (200|302) || "${_line}" =~ files\.aegir\.cc ]]; then
      _IGNORE_OTHER=1
    fi
    # Exclude lines containing configured ignore keywords or default 'doccomment'
    if [[ -n "${_NGINX_DOS_IGNORE}" ]]; then
      if [[ "${_line}" =~ (${_NGINX_DOS_IGNORE}).*\"\ (200|302) ]]; then
        _IGNORE_OTHER=1
      fi
    else
      if [[ "${_line}" =~ doccomment.*\"\ (200|302) ]]; then
        _IGNORE_OTHER=1
      fi
    fi
    # If the request resulted in a 403 or contains WP paths, do not ignore (likely malicious traffic)
    if [[ "${_line}" =~ (GET|HEAD|POST)\ /.*\"\ 403 ]] || [[ "${_line}" =~ wp-(content|admin|includes|json) ]]; then
      _IGNORE_OTHER=0
    fi
    if [[ "${_IGNORE_OTHER}" -eq 1 ]]; then
      _verbose_log "Other URI To Ignore" "${_line}"
      return
    fi

    # Skip processing if IP is whitelisted in CSF allow list (cached in memory)
    if [[ -n "${_CSF_ALLOW_IPS["${_IP}"]}" ]]; then
      return
    fi

    # Initialize or increment the counter safely for this IP
    if [[ -v _COUNTERS["${_IP}"] ]]; then
      (( _COUNTERS["${_IP}"]++ ))
    else
      _COUNTERS["${_IP}"]=1
    fi
  fi

  # Additional counting based on mode (only if not ignored by above filters)
  if [[ "${_IGNORE_OTHER}" -eq 0 && "${_IGNORE_ADMIN}" -eq 0 ]]; then
    _if_increment_counters
    if [[ "${_NGINX_DOS_MODE}" -eq 1 ]]; then
      if [[ "${_line}" =~ POST\ /([a-z]{2}/)?(user|user/(register|pass|login)|node/add) ]]; then
        (( _COUNTERS["${_IP}"] += 5 ))
        _verbose_log "Counter++ 5 for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/user/ and /node/add POST flood protection"
      fi
      if [[ "${_line}" =~ GET\ /([a-z]{2}/)?node/add ]]; then
        (( _COUNTERS["${_IP}"] += 3 ))
        _verbose_log "Counter++ 3 for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/node/add GET flood protection"
      fi
      if [[ -n "${_NGINX_DOS_STOP}" ]]; then
        if [[ "${_line}" =~ (${_NGINX_DOS_STOP}) ]]; then
          (( _COUNTERS["${_IP}"] += _NGINX_DOS_LIMIT ))
          _verbose_log "Counter++ ${_NGINX_DOS_LIMIT} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "_NGINX_DOS_STOP protection"
        fi
      fi
    else
      if [[ -n "${_NGINX_DOS_STOP}" ]]; then
        if [[ "${_line}" =~ (${_NGINX_DOS_STOP}) ]]; then
          (( _COUNTERS["${_IP}"] += _NGINX_DOS_LIMIT ))
          _verbose_log "Counter++ ${_NGINX_DOS_LIMIT} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "_NGINX_DOS_STOP protection"
        fi
      fi
    fi
  fi
}

# Function to handle blocking actions
_handle_blocking() {
  local -n _COUNTERS=$1
  local _TYPE=$2

  # Debug: confirm that _COUNTERS is referencing the intended array
  if [[ -n "${1}" && -e "/root/.debug.monitor.cnf" ]]; then
    declare -p _COUNTERS
    echo "DEBUG: _COUNTERS in _handle_blocking is referencing '${1}'"
  fi

  for _IP in "${!_COUNTERS[@]}"; do
    local _COUNT="${_COUNTERS["${_IP}"]}"
    local _CRITNUMBER="${_NGINX_DOS_LIMIT}"
    local _MININUMBER=$(( (_CRITNUMBER + 1) / 2 ))  # handle integer division rounding

    if (( _COUNT > _MININUMBER )); then
      if _is_logged_in "${_IP}"; then
        _CRITNUMBER=9999
      fi
      if [[ "${_IP}" == "${_MYIP}" ]]; then
        _CRITNUMBER=9998
      fi

      echo "===[${_CRITNUMBER}] MAX ${_TYPE} critnumber for ${_IP} ==="
      echo "===[${_COUNT}] COUNTER ${_TYPE} counter for ${_IP} ==="

      # Skip blocking if IP is in local allow list
      if _is_allowed_local "${_IP}"; then
        continue
      fi
      # Skip if IP was already banned/processed
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

# Load banned IPs from web.log into associative array (cache already blocked IPs)
_WEB_LOG="/var/xdrago/monitor/log/web.log"
if [[ -e "${_WEB_LOG}" ]]; then
  while IFS= read -r _line; do
    _ip="${_line%% *}"               # extract IP (before first space or comment)
    _ip="${_ip//[^0-9.]/}"           # clean any non-numeric characters from IP
    if [[ -n "${_ip}" ]]; then
      _BANNED_IPS["${_ip}"]=1
    fi
  done < "${_WEB_LOG}"
fi

# Load allowed local IPs into associative array (IPs that should not be blocked)
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

# Load allowed IPs from CSF allow list (for port 80) into memory to avoid repeated grep operations
declare -A _CSF_ALLOW_IPS
_CSF_ALLOW_FILE="/etc/csf/csf.allow"
if [[ -f "${_CSF_ALLOW_FILE}" ]]; then
  while IFS= read -r _line; do
    if [[ "${_line}" =~ ^tcp\|in\|d=80\|s=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\b ]]; then
      _ip="${BASH_REMATCH[1]}"
      _CSF_ALLOW_IPS["${_ip}"]=1
    fi
  done < "${_CSF_ALLOW_FILE}"
fi

# ==============================
# Load Logged-In IPs
# ==============================

if command -v who &> /dev/null; then
  while IFS= read -r _logged_ip; do
    if _validate_ip "${_logged_ip}"; then
      _LOGGED_IN_IPS["${_logged_ip}"]=1
    fi
  done < <(who --ips | awk '{print $5}' | tr -dc '0-9.\n')
fi

# ==============================
# Processing the Access Log
# ==============================

# Use byte offset tracking to read only new lines since last run (reduces redundant I/O)
_OFFSET_FILE="/var/log/scan_nginx_lastpos"
_last_offset=0
if [[ -f "${_OFFSET_FILE}" ]]; then
  _last_offset=$(< "${_OFFSET_FILE}")
fi
_log_file="/var/log/nginx/access.log"
_current_size=0
if [[ -f "${_log_file}" ]]; then
  _current_size=$(stat -c %s "${_log_file}")
fi
if (( _current_size < _last_offset )); then
  # Log file was rotated or truncated; reset offset to start from beginning
  _last_offset=0
fi

if (( _last_offset == 0 )); then
  # First run or reset: process the last $_NGINX_DOS_LINES lines as a baseline
  exec 3< <(tail -n "${_NGINX_DOS_LINES}" "${_log_file}")
else
  # Process only new log entries since the last recorded byte offset
  exec 3< <(tail -c +$(( _last_offset + 1 )) "${_log_file}")
fi

while IFS= read -r _line <&3; do
  # Extract the first quoted string from the log line (which contains the comma-separated IPs)
  if [[ "${_line}" =~ \"([^\"]*)\" ]]; then
    _ip_str="${BASH_REMATCH[1]}"
  else
    _ip_str=""
  fi

  # Split the IP string by commas and trim spaces
  IFS=',' read -ra _ip_array <<< "${_ip_str}"
  for i in "${!_ip_array[@]}"; do
    _ip_array[i]="${_ip_array[i]## }"
    _ip_array[i]="${_ip_array[i]% }"
  done

  # Collect only valid IPv4 addresses from the IP list
  _IP_LIST=()
  for _ip_candidate in "${_ip_array[@]}"; do
    if [[ "${_ip_candidate}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      _IP_LIST+=("${_ip_candidate}")
    fi
  done

  # Debug: Print extracted IPs if debug mode is enabled
  if [[ -e "/root/.debug.monitor.cnf" ]]; then
    echo "DEBUG: Extracted IPs: ${_IP_LIST[*]}"
  fi

  # Assign visitor IP and up to three proxy IPs (from X-Forwarded-For or similar header)
  _VISITOR="${_IP_LIST[0]:-}"
  _PROXY1="${_IP_LIST[1]:-}"
  _PROXY2="${_IP_LIST[2]:-}"
  _PROXY3="${_IP_LIST[3]:-}"

  # Resolve the real IP by traversing proxies (inlined to avoid per-line subshell overhead)
  _REAL_IP="${_VISITOR}"
  _PROXIES_TO_CHECK=()
  for _proxy in "${_PROXY1}" "${_PROXY2}" "${_PROXY3}"; do
    if [[ "${_REAL_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
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
  # If the final resolved IP is still private, treat it as a proxy as well and clear real IP
  if [[ "${_REAL_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    _PROXIES_TO_CHECK+=("${_REAL_IP}")
    _REAL_IP=""
  fi
  _PROXIES_ARRAY=( "${_PROXIES_TO_CHECK[@]}" )

  # Debug: Echo the determined real visitor IP and proxy IPs if debug mode is enabled
  if [[ -n "${_REAL_IP}" && -e "/root/.debug.monitor.cnf" ]]; then
    echo "=== checking ${_REAL_IP} / _LI_CNT ==="
  fi
  if [[ -e "/root/.debug.monitor.cnf" ]]; then
    for _proxy_ip in "${_PROXIES_ARRAY[@]}"; do
      [[ -n "${_proxy_ip}" ]] && echo "=== checking ${_proxy_ip} / _PX_CNT ==="
    done
  fi

  # Process the real visitor IP (if determined)
  if [[ -n "${_REAL_IP}" ]]; then
    _process_ip "${_REAL_IP}" "_LI_CNT" "${_line}"
  fi
  # Process each proxy IP (if any were identified as needing blocking)
  for _proxy_ip in "${_PROXIES_ARRAY[@]}"; do
    if [[ -n "${_proxy_ip}" ]]; then
      _process_ip "${_proxy_ip}" "_PX_CNT" "${_line}"
    fi
  done
done

# Close the file descriptor for the log input
exec 3<&-

# Record the new end-of-file offset for next run
if [[ -f "${_log_file}" ]]; then
  stat -c %s "${_log_file}" > "${_OFFSET_FILE}"
fi

# ==============================
# Execute Blocking Logic
# ==============================

_handle_blocking _LI_CNT "li_cnt"
_handle_blocking _PX_CNT "px_cnt"

echo "CONTROL complete for ${_MYIP}"
exit 0
