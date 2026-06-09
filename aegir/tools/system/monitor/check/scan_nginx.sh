#!/bin/bash

# ==============================================================================
# Script to Monitor and Block Suspicious NGINX Activity (DoS and DDoS)
# ==============================================================================

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

# ==============================
# Configuration and Environment
# ==============================

# Enable verbose mode if debug configuration exists
if [[ -e "/root/.debug.monitor.cnf" ]]; then
  set -x
fi

# Enable strict error handling for debugging only
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

# ---- DDoS / Shared-UA flood detection ----
# Minimum number of distinct IPs sharing the same User-Agent string within the
# current scan window that must be observed before the UA is considered an
# attack fingerprint. Tune upward on high-traffic servers.
_NGINX_DDOS_UA_IP_THRESHOLD=20

# Minimum per-UA request count (across all IPs) in the scan window required to
# declare a DDoS. This catches fast floods even when IPs are few but requests
# are extreme.
_NGINX_DDOS_UA_REQ_THRESHOLD=200

# When a DDoS UA is confirmed, only block IPs that contributed at least this
# many requests with that UA. Keeps incidental single-request hits (e.g. from
# a shared Cloudflare egress) out of the block list.
_NGINX_DDOS_IP_MIN_REQS=3

# Minimum raw requests before _handle_blocking can individually block an IP.
# Scoring multipliers can push a 1-request IP well over DOS_LIMIT; this guard
# ensures only genuinely high-volume IPs enter web.log individually.
# The distributed one-request-per-IP botnet is still caught in aggregate by
# _handle_path_flood_blocking.  Set to 1 to disable.
_NGINX_MIN_BLOCK_REQS=3

# ---- Path-flood / search-amplification detection ----
# Distributed botnets send one request per IP so per-IP rate limits never
# fire. This module tracks total 200-response traffic to expensive path
# prefixes across *all* IPs and blocks every participant once the path is
# declared under flood. Designed specifically for Solr/Elasticsearch search
# amplification attacks that bypass Nginx 444 rules by adding a Referer.

# Minimum distinct IPs hitting the same path prefix (200 responses only)
# within the scan window before a path flood is declared.
# Set to 5 rather than a higher value: the Chrome/131 subgroup of this botnet
# sends exactly 3-5 requests per scan window, staying under a threshold of 10
# but triggering reliably at 5. Lower values increase sensitivity but also the
# risk of false positives on genuinely popular search pages — tune upward if
# `_handle_path_flood_blocking` fires on legitimate traffic peaks.
_NGINX_PATH_FLOOD_IP_THRESHOLD=5

# Minimum total 200-response requests to the same path prefix in the window.
_NGINX_PATH_FLOOD_REQ_THRESHOLD=15

# Upstream response time (whole seconds) above which a request is considered
# "slow" -- i.e., it consumed real backend (Solr/PHP-FPM) cycles. Slow 200s
# get an extra per-IP counter increment on top of normal scoring.
_NGINX_PATH_FLOOD_SLOW_SECS=3

# Per-(path-prefix, IP) minimum request count before that IP is added to the
# block list during a path-flood event.  Applies to all response types (200
# and 444).  Set high enough to avoid blocking single-request botnet IPs that
# Nginx already 444s for free; only persistent IPs (making many requests within
# one scan window) warrant a csf -td entry.  Set to 1 to block every participant.
_NGINX_PATH_FLOOD_IP_MIN_REQS=10

# Extra counter weight added for each confirmed 444 on a watched attack path
# (in addition to the standard _INC_NR increment applied for all 4xx/5xx).
# Combined with _INC_NR, an IP accumulates roughly:
#   (_INC_NR + _NGINX_DOS_444_WEIGHT) × N per scan window.
# Setting this to _NGINX_DOS_LIMIT/3 means an IP is blocked after ~3
# confirmed hits rather than waiting for the full limit to accumulate naturally.
#
# Tradeoff: lower = faster blocking, higher false-positive risk.
# Set to 0 to disable (rely on standard accumulation and path-flood detection).
#
# NOTE: the distributed one-request-per-IP botnet still won't be caught
# individually by this — they're caught in aggregate by _handle_path_flood_blocking.
# This setting helps "smarter" bots that make a few repeated requests.
#
# Do not calculate the default here: /root/.barracuda.cnf may override
# _NGINX_DOS_LIMIT later.  The default is calculated after config loading and
# limit validation, unless _NGINX_DOS_444_WEIGHT is explicitly set in config.


# Pipe-separated list of patterns for flood detection.
#
# Each pattern is matched against the FULL log line (URI path + query string +
# all other fields), so both path-based and query-string-based signals work.
#
# Path patterns  — match the URI segment produced by older search modules:
#   apachesolr_search  Drupal 6/7 Apache Solr module (/search/apachesolr_search/TERM)
#   /search/node       Drupal core node search path
#   /search/user       Drupal core user search path
#
# Query-string patterns  — match the parameter names produced by modern modules.
# These cover any URI (/search, /en/search, /views/...) because the search type
# is identified solely by the query string when using Search API / Solr backend:
#   search_api_views_fulltext  Search API Views exposed filter (most common)
#   search_api_fulltext        Search API programmatic fulltext parameter
#   im_taxonomy_vid            Faceted search taxonomy-vocabulary facet param
#                              (present in both apachesolr_search and Search API
#                               facets module; appears in every facet-bearing URL)
#
# Add further site-specific expensive endpoint substrings as needed.
_NGINX_PATH_FLOOD_WATCH="apachesolr_search|search_api_views_fulltext|search_api_fulltext|im_taxonomy_vid|/search/node|/search/user"

# Default exclude keywords (empty by default; 'doccomment' will be used if not overridden)
_NGINX_DOS_IGNORE="doccomment"

# Default DoS keywords (empty by default; 'foobar' will be used if not overridden)
_NGINX_DOS_STOP="WAITFOR.DELAY|DECLARE.*@x|/\*\*/|%27.*%29.*%3B|0x[0-9a-f]{6}"

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

# Calculate default watched-444 weight after config override and limit validation.
# This preserves an explicit _NGINX_DOS_444_WEIGHT=0 or custom numeric value
# from /root/.barracuda.cnf, but prevents stale defaults based on the built-in
# _NGINX_DOS_LIMIT=399 when config later changes the limit to e.g. 99.
if ! [[ "${_NGINX_DOS_444_WEIGHT:-}" =~ ^[0-9]+$ ]]; then
  _NGINX_DOS_444_WEIGHT=$(( _NGINX_DOS_LIMIT / 3 ))
fi

echo "CONFIG: _NGINX_DOS_LIMIT is ${_NGINX_DOS_LIMIT}"
echo "CONFIG: _NGINX_DOS_LINES is ${_NGINX_DOS_LINES}"
echo "CONFIG: _INC_NR is ${_INC_NR}"
echo "CONFIG: _INC_S_NR is ${_INC_S_NR}"
echo "CONFIG: _NGINX_DOS_444_WEIGHT is ${_NGINX_DOS_444_WEIGHT}"

# ==============================
# Declare Associative Arrays
# ==============================

declare -A _BANNED_IPS
declare -A _ALLOWED_IPS
declare -A _LOGGED_IN_IPS
declare -A _COUNTERS
declare -A _LI_CNT
declare -A _PX_CNT
declare -A _LI_REQ_CNT   # raw request counts for _LI_CNT IPs (unweighted, +1/req)
declare -A _PX_REQ_CNT   # raw request counts for _PX_CNT IPs (unweighted, +1/req)

# DDoS / Shared-UA detection arrays
# _UA_IP_COUNT[ua]    = number of distinct real IPs seen with this UA
# _UA_REQ_COUNT[ua]   = total requests seen with this UA
# _UA_IP_SET[ua:ip]   = sentinel: marks that IP 'ip' was seen with UA 'ua'
# _UA_IP_LIST[ua]     = space-separated list of real IPs using this UA
# _UA_IP_REQS[ua:ip]  = request count per (UA, IP) pair
declare -A _UA_IP_COUNT
declare -A _UA_REQ_COUNT
declare -A _UA_IP_SET
declare -A _UA_IP_LIST
declare -A _UA_IP_REQS

# Path-flood / search-amplification detection arrays
# Tracks 200-response traffic to expensive path prefixes across all IPs.
# Catches distributed botnets where no single IP exceeds per-IP rate limits.
#
# _PATH_REQ_COUNT[prefix]    = total 200-response requests to this path prefix
# _PATH_IP_COUNT[prefix]     = distinct real IPs hitting this path prefix (200 only)
# _PATH_IP_SET[prefix:ip]    = sentinel: IP seen on this path prefix with 200
# _PATH_IP_LIST[prefix]      = space-separated list of contributing IPs
# _PATH_IP_REQS[prefix:ip]   = per-(prefix, IP) request count
# _PATH_SLOW_COUNT[prefix]   = requests with upstream_time >= _NGINX_PATH_FLOOD_SLOW_SECS
declare -A _PATH_REQ_COUNT
declare -A _PATH_IP_COUNT
declare -A _PATH_IP_SET
declare -A _PATH_IP_LIST
# Per-(path,IP) count of 200 responses only — used to gate individual IP blocking.
# IPs that only received 444 responses are already handled by Nginx at zero
# backend cost; writing them to web.log for csf -td is redundant and causes
# web.log to accumulate thousands of entries during distributed botnet attacks.
declare -A _PATH_IP_200_REQS
declare -A _PATH_IP_REQS
declare -A _PATH_SLOW_COUNT

# Debugging: Confirm associative arrays are declared
if [[ -e "/root/.debug.monitor.cnf" ]]; then
  declare -p _BANNED_IPS _ALLOWED_IPS _LOGGED_IN_IPS _COUNTERS _LI_CNT _PX_CNT
  declare -p _UA_IP_COUNT _UA_REQ_COUNT _UA_IP_SET _UA_IP_LIST _UA_IP_REQS
  declare -p _PATH_REQ_COUNT _PATH_IP_COUNT _PATH_IP_SET _PATH_IP_LIST _PATH_IP_REQS _PATH_SLOW_COUNT
  echo "DEBUG: Associative arrays declared (DoS + DDoS + path-flood sets)."
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

# Return 0 if IPv4 $1 is whitelisted in csf.allow (exact host or CIDR).
#
# guest-water.sh maintains /etc/csf/csf.allow daily with every provider
# range the firewall trusts: Cloudflare, Googlebot, Bingbot, Pingdom,
# Imperva, Sucuri, Auth0, Site24x7, and local addresses. The monitor must
# honour that single source of truth rather than maintain its own list.
#
# The loader (below) parses csf.allow once at startup into:
#   _CSF_ALLOW_IPS          -- exact host  -> 1  (O(1) lookup)
#   _CSF_ALLOW_CIDR_OCTET1  -- first octet -> 1  (cheap prescreen)
#   _CIDR_NET / _CIDR_MASK / _CIDR_O1            (parallel indexed arrays)
#
# At call time: pure integer arithmetic, no subshells, no external processes.
# Non-whitelisted-octet IPs cost one associative-array lookup and return 1
# immediately; only IPs whose first octet matches a loaded CIDR run the loop.
#
# Honours the allow regardless of the iptables port scope of the csf.allow
# entry: an s= record expresses "trusted source" and must gate the monitor's
# block decision on every port, including 443.
_is_whitelisted_ip() {
  local _ip="$1" _a _b _c _d _ipi _k
  [[ -n "${_CSF_ALLOW_IPS["${_ip}"]:-}" ]] && return 0
  IFS=. read -r _a _b _c _d <<< "${_ip}"
  [[ -z "${_CSF_ALLOW_CIDR_OCTET1["${_a}"]:-}" ]] && return 1
  _ipi=$(( (_a<<24)+(_b<<16)+(_c<<8)+_d ))
  for _k in "${!_CIDR_NET[@]}"; do
    [[ "${_CIDR_O1[_k]}" == "${_a}" ]] || continue
    (( (_ipi & _CIDR_MASK[_k]) == _CIDR_NET[_k] )) && return 0
  done
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
# Optional second argument: "silent" suppresses terminal echo (used for bulk path-flood blocking)
_block_ip() {
  local _IP="$1"
  local _SILENT="${2:-}"
  # Keystone safety net: never block any IP the firewall already whitelists
  # (exact host or CIDR). guest-water.sh maintains the allow list daily;
  # blocking one of its entries would drop an entire CDN PoP, monitoring
  # network, or search-engine crawler and surface as origin 502/520 errors.
  # This guard covers every call path to _block_ip, including bulk passes
  # from _handle_ddos_blocking and _handle_path_flood_blocking.
  if _is_whitelisted_ip "${_IP}"; then
    _verbose_log "Whitelisted IP ${_IP} -- refusing to block" "_block_ip"
    return
  fi
  # Append to web.log if not already present (use in-memory cache to avoid grep each time)
  if [[ -z "${_BANNED_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP} # [x${_sumar}] ${_TIMES}" "_block_ip"
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/web.log
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/scan_nginx.archive.log
    [[ "${_SILENT}" != "silent" ]] && echo "===[${_sumar}] ${_IP} ADDED TO BLOCK LIST monitor/log/web.log ==="
  else
    [[ "${_SILENT}" != "silent" ]] && echo "===[${_sumar}] ${_IP} ALREADY LISTED IN monitor/log/web.log ==="
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
  # Combine checks for HTTP status 400, 404, 403, 410, 444, 500 to increment counters in one go
  if [[ "${_line}" =~ \"\ (400|404|403|410|444|500) ]]; then
    local _code="${BASH_REMATCH[1]}"
    (( _COUNTERS["${_IP}"] += _INC_NR ))
    _verbose_log "Counter++ ${_INC_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "${_code} flood protection"
  fi
  # Extra weight for a confirmed 444 on a watched attack path.
  # Unlike the removed immediate-push approach, this accumulates over multiple
  # hits rather than triggering on the very first request — faster than natural
  # accumulation, but no single hit saturates the counter.  An IP receiving
  # _NGINX_DOS_LIMIT/3 extra per hit is blocked after roughly 3 such requests.
  # The distributed one-request-per-IP botnet is still handled by the aggregate
  # path-flood detection in _handle_path_flood_blocking.
  if [[ ${_NGINX_DOS_444_WEIGHT:-0} -gt 0 && "${_line}" =~ \"\ 444 \
      && ${#_WATCH_PATTERNS[@]} -gt 0 ]]; then
    local _444_PAT
    for _444_PAT in "${_WATCH_PATTERNS[@]}"; do
      if [[ -n "${_444_PAT}" && "${_line}" =~ ${_444_PAT} ]]; then
        (( _COUNTERS["${_IP}"] += _NGINX_DOS_444_WEIGHT ))
        _verbose_log "Counter+=${_NGINX_DOS_444_WEIGHT} for IP ${_IP}: ${_COUNTERS["${_IP}"]} (444 on watched path '${_444_PAT}')" "444 extra weight"
        break
      fi
    done
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

    # Skip processing if IP is whitelisted in CSF allow list (exact host or CIDR)
    if _is_whitelisted_ip "${_IP}"; then
      return
    fi

    # Initialize or increment the counter safely for this IP.
    # Avoid [[ -v assoc[key] ]] for compatibility with older Bash 4.x.
    (( _COUNTERS["${_IP}"] += 1 ))

    # Track raw request count (+1 per qualifying request, unweighted).
    # Uses plain (( arr[key]++ )) — bash treats an unset element as 0 before
    # the increment, so no [[ -v ]] check is needed.  The [[ -v arr[key] ]]
    # form is unreliable for associative arrays in bash 4.x, causing the
    # counter to reset to 1 on every call instead of accumulating.
    if [[ "${_COUNT_REF}" == "_LI_CNT" ]]; then
      (( _LI_REQ_CNT["${_IP}"]++ ))
    elif [[ "${_COUNT_REF}" == "_PX_CNT" ]]; then
      (( _PX_REQ_CNT["${_IP}"]++ ))
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
        (( _COUNTERS["${_IP}"] += 5 ))
        _verbose_log "Counter++ 5 for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/node/add GET flood protection"
      fi
      if [[ "${_line}" =~ GET\ /([a-z]{2}/)?search ]]; then
        (( _COUNTERS["${_IP}"] += 5 ))
        _verbose_log "Counter++ 5 for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/search GET flood protection"
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
  local _IP _COUNT _CRITNUMBER _MININUMBER _raw_reqs

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
      # Raw-reqs gate: silently skip before any output.
      # DOS_STOP and scoring multipliers can push low-volume IPs over _MININUMBER
      # without them making enough requests to warrant individual blocking.
      # Path-flood aggregate handles them; no output needed here.
      local _raw_reqs=0
      if [[ "$1" == "_LI_CNT" ]]; then
        _raw_reqs="${_LI_REQ_CNT["${_IP}"]:-0}"
      elif [[ "$1" == "_PX_CNT" ]]; then
        _raw_reqs="${_PX_REQ_CNT["${_IP}"]:-0}"
      fi
      (( _raw_reqs < _NGINX_MIN_BLOCK_REQS )) && continue

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
        echo "=== block_ip ${_IP} ${_COUNT}/${_CRITNUMBER} [${_raw_reqs} raw reqs] ==="
        _block_ip "${_IP}"
      fi
    fi
  done
}

# ==============================
# DDoS / Shared-UA Detection
# ==============================

# _track_ua_ip IP UA
# Called for every non-ignored request line during the main scan loop.
# Builds per-UA statistics: distinct IP count, total request count, and
# per-(UA,IP) request count. All work is done in-memory using associative
# arrays; no subshells or external processes are spawned.
_track_ua_ip() {
  local _IP="$1"
  local _UA="$2"

  # Skip private/localhost IPs (they cannot be blocked anyway)
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    return
  fi
  # Skip already-banned IPs to avoid inflating counts needlessly
  if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
    return
  fi
  # Skip whitelisted IPs
  if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
    return
  fi

  local _UA_IP_KEY="${_UA}:${_IP}"

  # Increment total-request counter for this UA.
  # Avoid [[ -v assoc[key] ]] for compatibility with older Bash 4.x.
  (( _UA_REQ_COUNT["${_UA}"] += 1 ))

  # Increment per-(UA,IP) request counter.
  (( _UA_IP_REQS["${_UA_IP_KEY}"] += 1 ))

  # Track distinct IPs per UA (use sentinel key to avoid duplicates)
  if [[ -z "${_UA_IP_SET["${_UA_IP_KEY}"]}" ]]; then
    _UA_IP_SET["${_UA_IP_KEY}"]=1
    (( _UA_IP_COUNT["${_UA}"] += 1 ))
    # Append IP to the list for this UA (space-separated; used during blocking phase)
    _UA_IP_LIST["${_UA}"]="${_UA_IP_LIST["${_UA}"]:-}${_UA_IP_LIST["${_UA}"]:+ }${_IP}"
  fi
}

# _handle_ddos_blocking
# Iterates over all tracked User-Agents. When a UA meets either the distinct-IP
# threshold or the total-request threshold it is declared a DDoS fingerprint
# and every contributing IP (that sent at least _NGINX_DDOS_IP_MIN_REQS
# requests with that UA) is individually blocked via _block_ip.
_handle_ddos_blocking() {
  local _UA _IP _ip_count _req_count _ip_reqs _UA_IP_KEY

  for _UA in "${!_UA_REQ_COUNT[@]}"; do
    _ip_count="${_UA_IP_COUNT["${_UA}"]:-0}"
    _req_count="${_UA_REQ_COUNT["${_UA}"]:-0}"

    # Skip only if neither threshold is met.  Using OR for detection is
    # deliberate: many-IP low-rate floods and fewer-IP high-rate floods should
    # both be detected.
    if (( _ip_count < _NGINX_DDOS_UA_IP_THRESHOLD && _req_count < _NGINX_DDOS_UA_REQ_THRESHOLD )); then
      continue
    fi

    # Strip non-printable characters from the UA before any echo / verbose-log
    # call. The UA comes from an attacker-controlled HTTP header and may carry
    # terminal escape sequences; rendering them in cron output or in a tail -f
    # view of the verbose log would confuse an operator. No RCE path (printf
    # in _verbose_log already protects against format-string injection), this
    # is cosmetic hardening.
    local _UA_SAFE="${_UA//[^[:print:][:space:]]/?}"
    _verbose_log "DDoS UA detected [${_ip_count} IPs / ${_req_count} reqs]: ${_UA_SAFE}" "_handle_ddos_blocking"
    echo "=== DDoS UA DETECTED [${_ip_count} distinct IPs | ${_req_count} total reqs] ==="
    echo "=== UA fingerprint: ${_UA_SAFE:0:120} ==="

    # Walk the IP list for this UA and block qualifying IPs.
    # Global IFS is newline+tab, so force space splitting for this list.
    local _SAVE_IFS="${IFS}"
    IFS=' '
    for _IP in ${_UA_IP_LIST["${_UA}"]}; do
      IFS="${_SAVE_IFS}"
      _UA_IP_KEY="${_UA}:${_IP}"
      _ip_reqs="${_UA_IP_REQS["${_UA_IP_KEY}"]:-0}"

      if (( _ip_reqs < _NGINX_DDOS_IP_MIN_REQS )); then
        continue
      fi

      # Skip already-banned, whitelisted, and logged-in IPs
      if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} already banned -- skipping ==="
        continue
      fi
      if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} is whitelisted -- skipping ==="
        continue
      fi
      if _is_logged_in "${_IP}"; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} is logged-in session -- skipping ==="
        continue
      fi
      if [[ "${_IP}" == "${_MYIP}" ]]; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} is local server IP -- skipping ==="
        continue
      fi

      _sumar="${_ip_reqs}"
      _block_ip "${_IP}" "silent"
    done
    IFS="${_SAVE_IFS}"
  done
}

# ==============================
# Path-Flood / Search-Amplification Detection
# ==============================

# _track_path_flood IP PATH_KEY STATUS UPSTREAM_TIME
#
# Called for every non-ignored request line whose URI matches one of the
# watched path prefixes defined in _NGINX_PATH_FLOOD_WATCH.
#
# Tracks two response classes:
#   200 — request reached the backend (Solr/PHP-FPM) and consumed real resources.
#         Slow responses (upstream_time >= _NGINX_PATH_FLOOD_SLOW_SECS) are
#         counted separately so the flood report shows backend load generated.
#   444 — Nginx blocked the request before it touched the backend.
#         Passing them here populates aggregate path/IP counts so
#         _handle_path_flood_blocking can emit a flood report and block any
#         distributed IPs the per-IP counter threshold alone would miss.
#
# All work is done in-memory using associative arrays; no subshells spawned.
_track_path_flood() {
  local _IP="$1"
  local _PATH_KEY="$2"
  local _STATUS="$3"
  local _UP_TIME="$4"

  # Accept confirmed-attack (444) and resource-consuming (200) responses only
  [[ "${_STATUS}" != "200" && "${_STATUS}" != "444" ]] && return

  # Skip private/localhost IPs (they cannot be blocked anyway)
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    return
  fi
  # Skip already-banned IPs to avoid inflating counts needlessly
  if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
    return
  fi
  # Skip whitelisted IPs
  if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
    return
  fi

  local _PATH_IP_KEY="${_PATH_KEY}:${_IP}"

  # Increment total request counter for this path prefix.
  # Avoid [[ -v assoc[key] ]] for compatibility with older Bash 4.x.
  (( _PATH_REQ_COUNT["${_PATH_KEY}"] += 1 ))

  # Track slow responses (upstream_time as whole-second integer comparison;
  # avoids bc/awk dependency by stripping the fractional part via parameter
  # expansion before the arithmetic test).
  local _UP_INT="${_UP_TIME%%.*}"
  if [[ "${_UP_INT}" =~ ^[0-9]+$ ]] && (( _UP_INT >= _NGINX_PATH_FLOOD_SLOW_SECS )); then
    (( _PATH_SLOW_COUNT["${_PATH_KEY}"] += 1 ))
  fi

  # Increment per-(path,IP) request counter.
  (( _PATH_IP_REQS["${_PATH_IP_KEY}"] += 1 ))

  # Count 200 responses per IP separately — only 200s warrant csf -td since
  # 444 responses are already free-blocked by Nginx's own map rules.
  if [[ "${_STATUS}" == "200" ]]; then
    (( _PATH_IP_200_REQS["${_PATH_IP_KEY}"] += 1 ))
  fi

  # Track distinct IPs per path prefix (sentinel pattern identical to _track_ua_ip)
  if [[ -z "${_PATH_IP_SET["${_PATH_IP_KEY}"]}" ]]; then
    _PATH_IP_SET["${_PATH_IP_KEY}"]=1
    (( _PATH_IP_COUNT["${_PATH_KEY}"] += 1 ))
    # Append IP to the space-separated list for this path prefix
    _PATH_IP_LIST["${_PATH_KEY}"]="${_PATH_IP_LIST["${_PATH_KEY}"]:-}${_PATH_IP_LIST["${_PATH_KEY}"]:+ }${_IP}"
  fi
}

# _handle_path_flood_blocking
#
# Iterates over all tracked path prefixes. When a prefix meets either the
# distinct-IP threshold OR the total-request threshold, it is declared a
# search-amplification flood and every contributing IP (that sent at least
# _NGINX_PATH_FLOOD_IP_MIN_REQS requests with that path) is blocked.
#
# Using OR (not AND) here is deliberate: a single path receiving 15+ real
# backend hits from 10+ IPs within one scan window is already anomalous
# regardless of which threshold is crossed first. Tune thresholds higher on
# genuinely high-traffic search pages.
#
# Runs after _handle_ddos_blocking so _BANNED_IPS is already fully populated
# and double-blocking IPs already caught by earlier passes is avoided.
_handle_path_flood_blocking() {
  local _PREFIX _IP _ip_count _req_count _slow_count _ip_reqs _PATH_IP_KEY

  for _PREFIX in "${!_PATH_REQ_COUNT[@]}"; do
    _ip_count="${_PATH_IP_COUNT["${_PREFIX}"]:-0}"
    _req_count="${_PATH_REQ_COUNT["${_PREFIX}"]:-0}"
    _slow_count="${_PATH_SLOW_COUNT["${_PREFIX}"]:-0}"

    # Skip if neither threshold is met
    if (( _ip_count < _NGINX_PATH_FLOOD_IP_THRESHOLD && _req_count < _NGINX_PATH_FLOOD_REQ_THRESHOLD )); then
      continue
    fi

    _verbose_log "Path flood [${_ip_count} IPs / ${_req_count} reqs / ${_slow_count} slow]: ${_PREFIX}" "_handle_path_flood_blocking"
    echo "=== PATH FLOOD DETECTED [${_ip_count} distinct IPs | ${_req_count} total reqs | ${_slow_count} slow 200s] ==="
    echo "=== Path prefix: ${_PREFIX} ==="

    # Walk the IP list for this path prefix and block qualifying IPs.
    # Global IFS is newline+tab, so force space splitting for this list.
    local _SAVE_IFS="${IFS}"
    IFS=' '
    for _IP in ${_PATH_IP_LIST["${_PREFIX}"]}; do
      IFS="${_SAVE_IFS}"
      _PATH_IP_KEY="${_PREFIX}:${_IP}"
      _ip_reqs="${_PATH_IP_REQS["${_PATH_IP_KEY}"]:-0}"

      if (( _ip_reqs < _NGINX_PATH_FLOOD_IP_MIN_REQS )); then
        continue
      fi

      # Skip already-banned, whitelisted, and logged-in IPs
      if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} already banned -- skipping ==="
        continue
      fi
      if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} is whitelisted -- skipping ==="
        continue
      fi
      if _is_logged_in "${_IP}"; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} is logged-in session -- skipping ==="
        continue
      fi
      if [[ "${_IP}" == "${_MYIP}" ]]; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} is local server IP -- skipping ==="
        continue
      fi

      _sumar="${_ip_reqs}"
      _block_ip "${_IP}" "silent"
    done
    IFS="${_SAVE_IFS}"
  done
}

# ==============================
# Load Banned / Allowed IPs
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

# Load the CSF allow list into memory — the single source of truth for all
# provider ranges, maintained daily by guest-water.sh (Cloudflare, Googlebot,
# Bingbot, Pingdom, Imperva, Sucuri, Auth0, Site24x7, local addresses, ...).
#
# The previous loader only matched exact hosts (s=A.B.C.D), so every provider
# whitelisted as a CIDR (Cloudflare, Googlebot, Bingbot, Imperva, Sucuri, ...)
# was silently ignored: the regex captured the network address from s=A.B.C.D/N
# and filed it as a host key that no real edge IP ever matched. Only Pingdom
# (whitelisted as individual hosts) was actually protected.
#
# This loader separates exact hosts (O(1) assoc lookup) from CIDRs (precomputed
# integer network+mask, bucketed by first octet so _is_whitelisted_ip can do a
# fork-free containment test with a single array lookup as the common-case
# early exit). Destination-only rules (DNS/DHCP use d=<ip>, not s=) are
# excluded naturally since they contain no s= field.
declare -A _CSF_ALLOW_IPS            # exact host -> 1
declare -A _CSF_ALLOW_CIDR_OCTET1    # first octet -> 1  (cheap prescreen)
_CIDR_NET=()                         # masked network as 32-bit int  (indexed)
_CIDR_MASK=()                        # 32-bit subnet mask             (indexed)
_CIDR_O1=()                          # first octet, parallel to above (indexed)
_CSF_ALLOW_FILE="/etc/csf/csf.allow"
if [[ -f "${_CSF_ALLOW_FILE}" ]]; then
  while IFS= read -r _aline; do
    # Skip full-line comments
    [[ "${_aline}" =~ ^[[:space:]]*# ]] && continue
    # Match any s=A.B.C.D or s=A.B.C.D/N (port/direction-agnostic)
    [[ "${_aline}" =~ s=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(/([0-9]+))? ]] || continue
    _addr="${BASH_REMATCH[1]}"
    _bits="${BASH_REMATCH[3]}"
    IFS=. read -r _a _b _c _d <<< "${_addr}"
    # Skip malformed octets
    (( _a<=255 && _b<=255 && _c<=255 && _d<=255 )) || continue
    if [[ -z "${_bits}" || "${_bits}" == "32" ]]; then
      # Bare host or explicit /32 — exact lookup is sufficient
      _CSF_ALLOW_IPS["${_addr}"]=1
    else
      # CIDR — precompute masked network int and mask once at load time so
      # _is_whitelisted_ip never needs subshells or external tools at runtime
      (( _bits < 1 || _bits > 31 )) && continue
      _ni=$(( (_a<<24)+(_b<<16)+(_c<<8)+_d ))
      _mk=$(( (0xFFFFFFFF << (32 - _bits)) & 0xFFFFFFFF ))
      _CIDR_NET+=( $(( _ni & _mk )) )
      _CIDR_MASK+=( "${_mk}" )
      _CIDR_O1+=( "${_a}" )
      _CSF_ALLOW_CIDR_OCTET1["${_a}"]=1
    fi
  done < "${_CSF_ALLOW_FILE}"
fi

# ==============================
# Load Logged-In IPs
# ==============================

_get_ssh_ips() {
  netstat -tn | awk '$4 ~ /:22$/ && $6 == "ESTABLISHED" { split($5, a, ":"); print a[1] }' | sort | uniq
}

if command -v netstat &>/dev/null; then
  while IFS= read -r _logged_ip; do
    if _validate_ip "${_logged_ip}"; then
      _LOGGED_IN_IPS["${_logged_ip}"]=1
    fi
  done < <(_get_ssh_ips)
fi

# ==============================
# Pre-process Path-Flood Watch Patterns
# ==============================

# Split _NGINX_PATH_FLOOD_WATCH on '|' once before the main loop to avoid
# repeated string manipulation inside the hot path. The resulting array is
# used during per-line path matching below.
_WATCH_PATTERNS=()
if [[ -n "${_NGINX_PATH_FLOOD_WATCH:-}" ]]; then
  _SAVE_IFS="${IFS}"
  IFS='|' read -ra _WATCH_PATTERNS <<< "${_NGINX_PATH_FLOOD_WATCH}"
  IFS="${_SAVE_IFS}"
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

  # Collect only valid IPv4 addresses from the IP list.
  # _validate_ip applies both the regex and the per-octet 0..255 range check,
  # so off-spec values like 999.999.999.999 are filtered out here at the
  # collection step rather than relying on csf to reject them downstream.
  # This also keeps the _track_ua_ip / _track_path_flood handlers (which do
  # not call _validate_ip themselves) from accumulating junk keys.
  _IP_LIST=()
  for _ip_candidate in "${_ip_array[@]}"; do
    if _validate_ip "${_ip_candidate}"; then
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

  # Skip internal Aegir file server requests — *.files.boa.io hostnames appear
  # in the log's vhost field and must not feed counters, UA tracking, or path-flood
  # detection.  The same pattern is also guarded inside _process_ip, but that gate
  # does not cover _track_ua_ip / _track_path_flood called later in this loop.
  [[ "${_line}" =~ files\.boa\.io ]] && continue
  [[ "${_line}" =~ files\.o8\.io ]] && continue
  [[ "${_line}" =~ files\.host8\.biz ]] && continue
  [[ "${_line}" =~ files\.aegir\.cc ]] && continue

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

  # ---- DDoS / Shared-UA tracking + upstream time extraction ----
  # The log format ends: ..."UA" upstream_time "cache_status" proto=...
  # We capture both the final quoted UA token and the decimal upstream time
  # that follows it. Both values are reused by the path-flood tracker below,
  # so extracting them once here avoids a second regex match per line.
  _DDOS_UA=""
  _UP_TIME="0"
  if [[ -n "${_REAL_IP}" && "${_line}" =~ \"([^\"]+)\"\ ([0-9]+\.[0-9]+) ]]; then
    _DDOS_UA="${BASH_REMATCH[1]}"
    _UP_TIME="${BASH_REMATCH[2]}"
    # Only track if UA is non-trivial (longer than 10 chars) and the line is
    # not a redirect (301) so we stay consistent with _process_ip filtering.
    if [[ ${#_DDOS_UA} -gt 10 && ! "${_line}" =~ \"\ 301 ]]; then
      _track_ua_ip "${_REAL_IP}" "${_DDOS_UA}"
    fi
  fi

  # ---- Path-flood / search-amplification tracking ----
  # Extract the HTTP status code for this line and feed matching requests to
  # _track_path_flood for aggregate flood detection and reporting.
  #
  # 200s: consumed real backend resources -- tracked for resource-exhaustion
  #       flood detection via _PATH_SLOW_COUNT and IP/req thresholds.
  # 444s: Nginx blocked the request before it touched the backend.
  #       Passing them here populates aggregate path/IP counts so the flood
  #       report is accurate and _handle_path_flood_blocking catches distributed
  #       IPs that the per-IP counter threshold alone would miss.
  if [[ -n "${_REAL_IP}" && ${#_WATCH_PATTERNS[@]} -gt 0 ]]; then
    _LINE_STATUS=""
    _STATUS_RE='"\ ([0-9]{3}) '
    if [[ "${_line}" =~ ${_STATUS_RE} ]]; then
      _LINE_STATUS="${BASH_REMATCH[1]}"
    fi
    if [[ "${_LINE_STATUS}" == "200" || "${_LINE_STATUS}" == "444" ]]; then
      for _WPFX in "${_WATCH_PATTERNS[@]}"; do
        if [[ -n "${_WPFX}" && "${_line}" =~ ${_WPFX} ]]; then
          _track_path_flood "${_REAL_IP}" "${_WPFX}" "${_LINE_STATUS}" "${_UP_TIME}"
          # Stop after the first matching prefix to avoid double-counting a
          # single request against multiple overlapping patterns.
          break
        fi
      done
    fi
  fi

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

# DDoS / Shared-UA flood blocking (runs after per-IP counters so _BANNED_IPS
# is already populated and we avoid double-blocking IPs caught by the DoS pass)
_handle_ddos_blocking

# Path-flood / search-amplification blocking (runs last so _BANNED_IPS reflects
# everything caught by the DoS and DDoS passes above; distributed bots that
# slipped through per-IP rate checks are caught here by the aggregate path count)
_handle_path_flood_blocking

echo "CONTROL complete for ${_MYIP}"
exit 0
