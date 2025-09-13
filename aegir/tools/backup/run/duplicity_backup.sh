#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export _tRee=dev

# Function to print env for debugging
_print_env() {
  if [ "$(id -u)" -eq 0 ] && [ -e "/root/.dev.server.cnf" ]; then
    _ENV=$(env 2>&1)
    echo
    echo "_ENV in $1 start"
    echo "${_ENV}"
    echo "_ENV in $1 end"
    echo
    _ENV=
  fi
}

# Function to verify BOA keys
_verify_boa_keys() {
  if [ -e "/root/.dev.server.cnf" ]; then
    echo "PROC: _verify_boa_keys in multiback"
  fi
  if [ "${_tRee}" = "pro" ] || [ "${_tRee}" = "dev" ]; then
    _allw=NO
    _crlGet="-L --max-redirs 3 -k -s --retry 9 --retry-delay 9 -A iCab"
    _urlEnc="http://files.aegir.cc/enc/2024"
    _encName=$(echo ${_hName} \
      | openssl md5 \
      | awk '{ print $2}' \
      | tr -d "\n" 2>&1)
    if [[ "${_hName}" =~ ".aegir.cc"($) ]] \
      || [[ "${_hName}" =~ ".o8.io"($) ]] \
      || [[ "${_hName}" =~ ".boa.io"($) ]]; then
      _allw=YES
    fi
    mkdir -p /var/opt
    rm -f /var/opt/_encN*
    curl ${_crlGet} "${_urlEnc}/${_encName}" -o /var/opt/_encN.${_encName}.tmp
    wait
    echo "${_hName}.${_encName}" > /var/opt/_encN_local.${_encName}.tmp
    wait
    if [ -e "/var/opt/_encN.${_encName}.tmp" ] && [ -e "/var/opt/_encN_local.${_encName}.tmp" ]; then
      _diffTestIf=$(diff -w -B /var/opt/_encN.${_encName}.tmp /var/opt/_encN_local.${_encName}.tmp 2>&1)
      if [ ! -z "${_diffTestIf}" ] && [ "${_allw}" = "NO" ]; then
        echo
        echo "Your system requires valid license to use this function"
        echo "Please visit https://omega8.cc/licenses to purchase your own"
        echo
        if [ -e "/var/aegir/drush/vendor" ] && [ ! -e "/var/aegir/key/barracuda_key.txt" ]; then
          mkdir -p /var/aegir/key
          cat /var/opt/_encN_local.${_encName}.tmp > /var/aegir/key/barracuda_key.txt
        fi
        rm -f /var/opt/_encN*
        exit 0
      else
        if [ -e "/var/aegir/drush/vendor" ] && [ ! -e "/var/aegir/key/barracuda_key.txt" ]; then
          mkdir -p /var/aegir/key
          cat /var/opt/_encN_local.${_encName}.tmp > /var/aegir/key/barracuda_key.txt
        fi
      fi
    else
      echo
      echo "Your system requires valid license to use this BOA feature"
      echo "Unfortunately it was not possible to verify your system status"
      echo "Please contact our support but visit https://omega8.cc/licenses first"
      echo
      exit 0
    fi
  fi
}

_if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_hName}" =~ ".aegir.cc"($) ]]; then
    _hostedSys=YES
  else
    _hostedSys=NO
  fi
}

# Function to calculate RAM usage percentage as an integer
_calculate_ram_usage_percent() {
  _total_ram_kb=$1
  _available_ram_kb=$2
  used_ram_kb=$((_total_ram_kb - _available_ram_kb))

  # Using integer division to get a whole number percentage
  echo $(( (used_ram_kb * 100) / _total_ram_kb ))
}

# Function to check and display system info
_check_system_ram() {
  # Get the total and available RAM in KB
  _total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  _available_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

  # Calculate RAM usage percentage
  _ram_usage_percent=$(_calculate_ram_usage_percent ${_total_ram_kb} ${_available_ram_kb})
}

# Function to check and optimize RAM and disk caches
_optimize_ram() {
  swapoff -a
  _check_system_ram
  if [ "${_ram_usage_percent}" -gt 50 ]; then
    sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
  fi
  swapon -a
}

# Function to verify root access
_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
    [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
  : "${_INCIDENT_REPORT:=YES}"
  _AWS_VLV=${_AWS_VLV//[^a-z]/}
  if [ -z "${_AWS_VLV}" ]; then
    _AWS_VLV="warning"
  fi
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  _cpuNr="$(cat /data/all/cpuinfo 2>/dev/null | tr -d '\n' || nproc 2>/dev/null)"
  if [ -n "${_cpuNr}" ]; then
    [ "${_cpuNr}" -gt 8 ] && _useCpu=4
    [ "${_cpuNr}" -le 8 ] && _useCpu=2
    [ "${_cpuNr}" -le 4 ] && _useCpu=1
  else
    _useCpu=1
  fi
}
_check_root
_optimize_ram
_if_hosted_sys
_verify_boa_keys
_print_env "multiback_init"

[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

# New OpenSSL 3.x version is required
if [ ! -x "/usr/local/ssl3/bin/openssl" ]; then
  echo "New OpenSSL 3.x version is required"
  exit 1
fi

# Function to notify about still running backup
_waiting_notify() {
  local _templog="/var/backups/multiback_waiting_queue.log"
  cat /root/.remote_backups/schedule/backup_schedule.txt > ${_templog}
  ps axf | grep multiback >> ${_templog}
  ps axf | grep duplicity >> ${_templog}
  ls -la /tmp/duplicity-*-tempdir >> ${_templog}
  tree /root/.cache/duplicity >> ${_templog}
  ls -laR /root/.cache/duplicity >> ${_templog}
  grep "Out of memory: Killed process.*duplicity" /var/log/iptables.log >> ${_templog}
  boa info  >> ${_templog}
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    s-nail -s "Multiback Waiting Report for [${_hName}] on $(date)" ${_MY_EMAIL} < ${_templog}
  fi
}

if [ `ps aux | grep -v "grep" | grep --count "duplicity"` -gt 0 ]; then
  echo "[$(date)] Active duplicity process detected, will try again later..." >> /var/log/mybackup_waiting_queue.log
  _waiting_notify
  exit 1
fi

# Function to display usage information
_usage() {
  echo "Usage: $0 {backup|cleanup|restore} <SERVICE> <USER> [RESTORE_TARGET] [RESTORE_PATH] [RESTORE_TIME]"
  echo
  echo "Example commands:"
  echo "  Backup:"
  echo "  $0 backup aws john"
  echo "  $0 backup b2 jane"
  echo
  echo "  Cleanup:"
  echo "  $0 cleanup aws john"
  echo "  $0 cleanup gcs jane"
  echo
  echo "  Restore:"
  echo "  $0 restore aws john /restore/target /specific/path 1D"
  echo "  $0 restore b2 jane /restore/target /another/path 2W"
  echo
  echo "Supported services:"
  echo "  aws, aws_one_zone, aws_standard_ia, azure, b2, cloudflare, do_spaces, gcs, ibm, linode, wasabi"
  echo
  echo "NOTE: [RESTORE_PATH] must be an absolute path (no leading slash) of the file or directory to restore"
  echo
  exit 1
}

# Function to create PID file
_create_pid_file() {
  local _pidfile=$1
  if [ -e "${_pidfile}" ]; then
    echo "Process already running with PID file ${_pidfile}"
    exit 1
  else
    echo $$ > "${_pidfile}"
  fi
}

# Function to remove PID file
_remove_pid_file() {
  local _pidfile=$1
  if [ -f "${_pidfile}" ]; then
    rm -f "${_pidfile}" || {
      echo "Warning: Failed to remove PID file: ${_pidfile}"
    }
  fi
}

# Function to remove stale multiback PID file
_remove_stale_multiback_pid() {
  local _service=$1
  local _user=$2
  _multiback_pidfile="/var/run/duplicity_${_service}_${_user}.pid"
  if [ -f "${_multiback_pidfile}" ]; then
    _old_pid=$(cat "${_multiback_pidfile}")
    if [ -n "${_old_pid}" ] && ! kill -0 "${_old_pid}" 2>/dev/null; then
      echo "Stale multiback PID file detected: ${_multiback_pidfile}. Removing it."
      rm -f "${_multiback_pidfile}"
    fi
  fi
}

# Function to log validation issues
_log_issue() {
  local _type=$1
  local _file=$2
  local _message=$3
  echo "[$(date)] Validation issue type: [${_type}] in file: [${_file}] with error: ${_message}" >> "${_VALIDATION_LOG_FILE}"
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    # Alert the admin
    boa info  >> ${_LOGFILE}
    echo "Sending Backup Validation Alert to ${_MY_EMAIL} on $(date)" >> ${_LOGFILE}
    s-nail -s "Backup Validation Alert for [$(hostname)] on $(date)" ${_MY_EMAIL} < ${_LOGFILE}
  fi
}

# Helper function to URL-encode using jq
_url_encode() {
  echo -n "$1" | jq -s -R -r @uri
}

# Function to escape values
_escape_value() {
  printf '%q' "$1"
}

# Function to sanitize and validate credentials file
_validate_credentials() {
  local _cred_file="$1"
  local _service="$2"
  local _line_number=0

  while IFS= read -r _line || [ -n "${_line}" ]; do
    _line_number=$(( _line_number + 1 ))

    # Trim leading and trailing whitespace
    _line="${_line#"${_line%%[![:space:]]*}"}"
    _line="${_line%"${_line##*[![:space:]]}"}"

    # Skip empty lines immediately
    if [[ -z "${_line}" ]]; then
      continue
    fi

    # Remove full-line comments: lines that *start* with '#'
    if [[ "${_line}" == \#* ]]; then
      continue
    fi

    # Remove anything after (and including) the first '#' for inline comments
    # (This is a naive approach that does not consider # within quotes)
    if [[ "${_line}" == *"#"* ]]; then
      _line="${_line%%#*}"
      # Re-trim after removing the comment
      _line="${_line#"${_line%%[![:space:]]*}"}"
      _line="${_line%"${_line##*[![:space:]]}"}"
    fi

    # Skip if there's nothing left after stripping inline comment
    if [[ -z "${_line}" ]]; then
      continue
    fi

    # Remove 'export ' prefix if present
    _line="${_line#export }"

    # Validate the variable assignment (key=value)
    if [[ "${_line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(\".*\"|'.*'|[^[:space:]]+)$ ]]; then
      export _varname="${BASH_REMATCH[1]}"
      export _value="${BASH_REMATCH[2]}"

      # Remove surrounding quotes if present
      if [[ "${_value}" =~ ^\".*\"$ || "${_value}" =~ ^\'.*\'$ ]]; then
        export _value="${_value:1:-1}"
      fi

      # Check for forbidden characters in value
      if echo "${_value}" | grep -q -E '[$`(){};&|<>]'; then
        _log_issue "credentials" "${_cred_file}" \
          "Forbidden characters in value at line ${_line_number}: ${_line}"
        continue
      fi

      # Safely export the variable (URL-encode if needed)
      if [ "${_service}" = "b2" ]; then
        export ${_varname}=$(_url_encode "${_value}")
      else
        export ${_varname}="${_value}"
      fi
    else
      _log_issue "credentials" "${_cred_file}" \
        "Invalid syntax at line ${_line_number}: ${_line}"
    fi
  done < "${_cred_file}"

  _print_env "multiback_validate_credentials"
}

# Function to load credentials
_load_credentials() {
  local _service="$1"
  local _user="$2"
  if [ "${_user}" != "arch" ] \
    && [ "${_user}" != "data" ] \
    && [ "${_user}" != "global" ] \
    && [ "${_user}" != "static" ] \
    && [ "${_user}" != "custom" ]; then
    local _cred_file="/data/disk/${_user}/static/control/remote_backups/credentials/${_service}.txt"
    local _secret_file="/data/disk/${_user}/remote_backups/.secret.txt"
  fi
  if [ "${_user}" = "global" ] || [ "${_user}" = "data" ] || [ "${_user}" = "custom" ]; then
    local _cred_file="/root/.remote_backups/credentials/${_service}.txt"
    local _secret_file="/root/.remote_backups/.secret.txt"
  fi

  if [ -s "${_secret_file}" ]; then
    export PASSPHRASE=$(cat "${_secret_file}")
  else
    echo "Secret file ${_secret_file} not found. Unable to proceed."
    exit 1
  fi

  if [ ! -s "${_cred_file}" ]; then
    echo "Error: Credentials file '${_cred_file}' not found."
    exit 1
  fi

  _validate_credentials "${_cred_file}" "${_service}"
  _print_env "multiback_load_credentials"
}

# Function to load paths configuration
_load_paths() {
  local _user="$1"
  if [ "${_user}" != "arch" ] \
    && [ "${_user}" != "data" ] \
    && [ "${_user}" != "global" ] \
    && [ "${_user}" != "static" ] \
    && [ "${_user}" != "custom" ]; then
    local _paths_file="/data/disk/${_user}/remote_backups/paths/paths.txt"
  elif [ "${_user}" = "global" ] || [ "${_user}" = "data" ] || [ "${_user}" = "custom" ]; then
    local _paths_file="/root/.remote_backups/paths/${_user}_paths.txt"
  fi

  if [ ! -f "${_paths_file}" ]; then
    echo "Error: Paths configuration file '${_paths_file}' not found."
    exit 1
  fi

  if [ "${_user}" != "arch" ]; then
    source "${_paths_file}"
  fi
  _print_env "multiback_load_paths"
}

# Function to validate duration format and fallback to default
_validate_or_default_duration() {
  local _value=$1
  local _var_name=$2
  local _default=$3

  # Supported formats: number followed by D (days), W (weeks), M (months), Y (years)
  if [[ ! "${_value}" =~ ^[0-9]+[DWMY]$ ]] || [[ "${_value}" =~ ^[0][DWMY]$ ]]; then
    echo "Warning: Invalid value '${_value}' for ${_var_name}. Using default '${_default}'."
    eval "${_var_name}='${_default}'"
    _print_env "multiback_validate_or_default_duration"
  fi

  # Enforced min value for KEEP_WITHIN (1M)
  if [ "${_var_name}" = "KEEP_WITHIN" ] && [[ ! "${_value}" =~ ^[0-9]+[MY]$ ]]; then
    echo "Warning: Invalid value '${_value}' for ${_var_name}. It must be at least 1M. Using default '${_default}'."
    eval "${_var_name}='${_default}'"
    _print_env "multiback_validate_or_default_duration_keep"
  fi

  # Enforced min and max value for FULL_BACKUP_FREQUENCY (7D to 60D)
  if [ "${_var_name}" = "FULL_BACKUP_FREQUENCY" ] && [[ ! "${_value}" =~ ^([7-9]|[1-5][0-9]|60)D$ ]]; then
    echo "Warning: Invalid value '${_value}' for ${_var_name}. It must be between 7D and 60D. Using default '${_default}'."
    eval "${_var_name}='${_default}'"
    _print_env "multiback_validate_or_default_duration_freq"
  fi
}

# Function to construct _BUCKET_NAME
_construct_bucket_name() {
  local _service_abbr=$1
  local _user=$2
  _service_dash=$(echo -n ${_service_abbr} | tr _ -)
  _hst_dash=$(echo -n ${_hName} | tr . -)
  export _BUCKET_NAME="back-to-${_user}-${_hst_dash}-${_service_dash}"
  export _NAME="${_user}-${_service_dash}"
  export _LOGFILE="${_LOGPTH}/${_BUCKET_NAME}.log"
  _print_env "multiback_construct_bucket_name"
}

# Function to generate duplicity-compatible include directives
_generate_include_directives() {
  local _source=$1
  local _include=""
  for _cdir in ${_source}; do
    _include="${_include} --include ${_cdir}"
  done
  echo "${_include}"
}

# Function to prepare backup directives
_backup_prepare() {
  if [ -e "/root/.cache/duplicity/${_NAME}" ]; then
    _CacheTest=$(find /root/.cache/duplicity/${_NAME} \
      -maxdepth 1 \
      -mindepth 1 \
      -type f \
      | sort 2>&1)
    if [[ "${_CacheTest}" =~ "No such file or directory" ]] \
      || [ -z "${_CacheTest}" ]; then
      export _cached=NO
    else
      export _cached=YES
    fi
  fi
  # Generate include directives dynamically
  [ -n "${_SOURCE}" ] && _SRC_INCLUDE=$(_generate_include_directives "${_SOURCE}")
  #
  [ -n "${_INCLUDE_PATHS}" ] && _MERGED_ALL_INCLUDE="${_INCLUDE_PATHS}"
  [ -n "${_EXCLUDE_PATHS}" ] && _MERGED_ALL_EXCLUDE="${_EXCLUDE_PATHS}"
  #
  [ -n "${_USER_INCLUDE_PATHS}" ] && _USER_MERGED_ALL_INCLUDE="${_USER_INCLUDE_PATHS}"
  [ -n "${_USER_EXCLUDE_PATHS}" ] && _USER_MERGED_ALL_EXCLUDE="${_USER_EXCLUDE_PATHS}"
  #
  [ -s "${_INCLUDE_LIST}" ] && _LST_INCLUDE="--include-filelist ${_INCLUDE_LIST}"
  [ -s "${_EXCLUDE_LIST}" ] && _LST_EXCLUDE="--exclude-filelist ${_EXCLUDE_LIST}"
  ###
  [ -n "${_MERGED_ALL_INCLUDE}" ] && _BATCH_INCLUDE="${_MERGED_ALL_INCLUDE}"
  [ -n "${_USER_MERGED_ALL_INCLUDE}" ] && _BATCH_INCLUDE="${_USER_MERGED_ALL_INCLUDE}"
  [ -n "${_LST_INCLUDE}" ] && _BATCH_INCLUDE="${_BATCH_INCLUDE} ${_LST_INCLUDE}"
  [ -n "${_SRC_INCLUDE}" ] && _BATCH_INCLUDE="${_BATCH_INCLUDE} ${_SRC_INCLUDE}"
  #
  [ -n "${_MERGED_ALL_EXCLUDE}" ] && _BATCH_EXCLUDE="${_MERGED_ALL_EXCLUDE}"
  [ -n "${_USER_MERGED_ALL_EXCLUDE}" ] && _BATCH_EXCLUDE="${_USER_MERGED_ALL_EXCLUDE}"
  [ -n "${_LST_EXCLUDE}" ] && _BATCH_EXCLUDE="${_BATCH_EXCLUDE} ${_LST_EXCLUDE}"
  #
  export _BATCH_INCLUDE
  export _BATCH_EXCLUDE

  _print_env "multiback_backup_prepare"
}


# Function to set backup mode
_set_mode() {
  local _user="${_USER}"
  [ -z "${_MODE}" ] && _MODE="backup"
  if [ -e "${_LOGPTH}/${_BUCKET_NAME}.archive.log" ] && [ "${_cached}" = "YES" ]; then
    export _MODE="incremental"
  else
    [ ! -e "${_LOGPTH}/${_BUCKET_NAME}.${_TODAY}.full.log" ] && export _MODE="full"
  fi
  [ -e "/root/.dev.server.cnf" ] && echo "The _MODE has been set to (${_MODE}) in _set_mode for ${_BUCKET_NAME} on $(date)" >> ${_LOGFILE}
  if [ "${_hostedSys}" = "YES" ]; then
    if [ "${_user}" = "global" ] || [ "${_user}" = "data" ] || [ "${_user}" = "custom" ]; then
      if [ "${_DOM}" = 1 ] && [ ! -e "${_LOGPTH}/${_BUCKET_NAME}.${_TODAY}.full.log" ]; then
        _MODE="full"
        echo "The _MODE has been re-set to (${_MODE}) in _set_mode for ${_BUCKET_NAME} on $(date)" >> ${_LOGFILE}
      fi
    fi
  else
    [ -e "/root/.dev.server.cnf" ] && echo "The FULL_BACKUP_FREQUENCY is (${FULL_BACKUP_FREQUENCY}) for ${_BUCKET_NAME}" >> ${_LOGFILE}
  fi
  export _MODE
  _print_env "multiback_set_mode"
}

# Function to construct backup command
_set_cmd() {
  local _user="${_USER}"
  if [ -z "${KEEP_WITHIN}" ] && [ -n "${_AWS_TTL}" ]; then
    export KEEP_WITHIN="${_AWS_TTL}"
  fi
  if [ -z "${FULL_BACKUP_FREQUENCY}" ] && [ -n "${_AWS_FLC}" ]; then
    export FULL_BACKUP_FREQUENCY="${_AWS_FLC}"
  fi

  # Validate or set default for KEEP_WITHIN
  _validate_or_default_duration "${KEEP_WITHIN}" "KEEP_WITHIN" "${_DEFAULT_KEEP_WITHIN}"

  # Validate or set default for FULL_BACKUP_FREQUENCY
  _validate_or_default_duration "${FULL_BACKUP_FREQUENCY}" "FULL_BACKUP_FREQUENCY" "${_DEFAULT_FULL_BACKUP_FREQUENCY}"

  ### Default backup command with encryption
  export _DCY_BUP_CMD="/usr/local/bin/duplicity ${_MODE} \
    -v ${_AWS_VLV} \
    --name=${_NAME} \
    --allow-source-mismatch \
    --concurrency ${_useCpu} \
    --copy-links \
    --full-if-older-than ${FULL_BACKUP_FREQUENCY} \
    --volsize 300"

  ### Default utility command with encryption
  export _DCY_UTL_CMD="/usr/local/bin/duplicity \
    -v ${_AWS_VLV} \
    --name=${_NAME} \
    --allow-source-mismatch \
    --concurrency ${_useCpu}"

  ### Custom backup command with encryption and enforced own FULL_BACKUP_FREQUENCY
  export _FBF_BUP_CMD="/usr/local/bin/duplicity ${_MODE} \
    -v ${_AWS_VLV} \
    --name=${_NAME} \
    --allow-source-mismatch \
    --concurrency ${_useCpu} \
    --copy-links \
    --volsize 300"

  ### Custom backup command without encryption and enforced own FULL_BACKUP_FREQUENCY
  export _NOE_BUP_CMD="/usr/local/bin/duplicity ${_MODE} \
    -v ${_AWS_VLV} \
    --name=${_NAME} \
    --allow-source-mismatch \
    --concurrency ${_useCpu} \
    --no-encryption \
    --volsize 300"

  ### Custom utility command without encryption
  export _NOE_UTL_CMD="/usr/local/bin/duplicity \
    -v ${_AWS_VLV} \
    --name=${_NAME} \
    --allow-source-mismatch \
    --no-encryption \
    --concurrency ${_useCpu}"

  if [ "${_hostedSys}" = "YES" ]; then
    if [ "${_user}" = "global" ] || [ "${_user}" = "data" ]; then
      export _DCY_BUP_CMD="${_FBF_BUP_CMD}"
    elif [ "${_user}" = "custom" ]; then
      export _DCY_BUP_CMD="${_NOE_BUP_CMD}"
      export _DCY_UTL_CMD="${_NOE_UTL_CMD}"
    fi
  fi

  _print_env "multiback_set_cmd"
}

_test() {
  local _mode="$1"
  if [ "${_mode}" != "only" ]; then
    _set_mode
    _set_cmd
  fi
  echo "Running ${_BUCKET_NAME} connection test, please wait..."
  echo "Command is ${_DCY_UTL_CMD} cleanup --dry-run --timeout 8 ${_BACKUP_TARGET}"
  _ConnTest=$(${_DCY_UTL_CMD} cleanup --dry-run --timeout 8 ${_BACKUP_TARGET} 2>&1)
  if [[ "${_ConnTest}" =~ "No connection to backend" ]] \
    || [[ "${_ConnTest}" =~ "does not exist" ]] \
    || [[ "${_ConnTest}" =~ "IllegalLocationConstraintException" ]]; then
    echo "Sorry, I can't connect to ${_BUCKET_NAME}"
    echo >> ${_LOGFILE}
    echo "Sorry, I can't connect to ${_BUCKET_NAME}" >> ${_LOGFILE}
    echo "Please check if the bucket has expected name:" >> ${_LOGFILE}
    echo " ${_BUCKET_NAME}" >> ${_LOGFILE}
    echo "This bucket must exist in the specified ${_SERVICE} region" >> ${_LOGFILE}
    echo >> ${_LOGFILE}
  else
    echo "OK, I can connect to ${_BUCKET_NAME}"
  fi
}

# Function to check collection-status only
_status() {
  echo "Command is ${_DCY_UTL_CMD} collection-status ${_BACKUP_TARGET}"
  ${_DCY_UTL_CMD} collection-status ${_BACKUP_TARGET}
  wait
}

# Function to list-current-files only
_list() {
  echo "Command is ${_DCY_UTL_CMD} list-current-files ${_BACKUP_TARGET}"
  ${_DCY_UTL_CMD} list-current-files ${_BACKUP_TARGET}
  wait
}

_remove_older_than() {
  echo "Running remove-older-than ${KEEP_WITHIN} for ${_BUCKET_NAME} on $(date)" >> ${_LOGFILE}
  echo "Command is ${_DCY_UTL_CMD} remove-older-than ${KEEP_WITHIN} --force ${_BACKUP_TARGET}"
  ${_DCY_UTL_CMD} remove-older-than ${KEEP_WITHIN} --force ${_BACKUP_TARGET} >> ${_LOGFILE}
  wait
}

_collection_status() {
  echo "Running collection-status for ${_BUCKET_NAME} on $(date)" >> ${_LOGFILE}
  echo "Command is ${_DCY_UTL_CMD} collection-status ${_BACKUP_TARGET}"
  ${_DCY_UTL_CMD} collection-status ${_BACKUP_TARGET} >> ${_LOGFILE}
  wait
}

# Function to only repair incomplete backup sets
_repair_only() {
  echo "Running repair via cleanup --force for ${_BUCKET_NAME} on $(date)" >> ${_LOGFILE}
  echo "Command is ${_DCY_UTL_CMD} cleanup --force ${_BACKUP_TARGET}"
  ${_DCY_UTL_CMD} cleanup --force ${_BACKUP_TARGET} >> ${_LOGFILE}
  wait
}

# Function to repair incomplete backup sets
_repair() {
  _repair_only
  _collection_status
}

# Function to check if repair incomplete backup sets is needed
_check_if_repair() {
  if grep -q "found incomplete backup sets" "${_LOGFILE}"; then
    _repair_only
  fi
}

# Function to check if backup worked cleanly or log the errors
_check_if_worked_cleanly_or_log_err() {
  if [ "${_user}" = "global" ] || [ "${_user}" = "data" ] || [ "${_user}" = "custom" ]; then
    local _logs_dir="/root/.remote_backups/logs"
  else
    local _logs_dir="/data/disk/${_user}/static/control/remote_backups/logs"
  fi
  if grep -q "Backup Statistics" "${_LOGFILE}"; then
    [ ! -e "${_logs_dir}" ] && mkdir -p ${_logs_dir}
    cp -af "${_LOGFILE}" "${_logs_dir}/OK-${_BUCKET_NAME}.log"
  else
    [ ! -e "${_logs_dir}" ] && mkdir -p ${_logs_dir}
    cp -af "${_LOGFILE}" "${_logs_dir}/ERR-${_BUCKET_NAME}.log"
  fi
}

# Function to wipe the bucket completely
_wipe() {
  echo "Running wipe via remove-all-but-n-full 0 --force for ${_BUCKET_NAME} on $(date)" >> ${_LOGFILE}
  echo "Command is ${_DCY_UTL_CMD} remove-all-but-n-full 0 --force ${_BACKUP_TARGET}"
  ${_DCY_UTL_CMD} remove-all-but-n-full 0 --force ${_BACKUP_TARGET} >> ${_LOGFILE}
  wait
}

# Function to purge all backup sets
_purge() {
  _repair_only
  _wipe
  _collection_status
}

# Function to run weekly cleanup
_weekly_cleanup() {
  if [ -e "${_LOGPTH}/${_BUCKET_NAME}.archive.log" ] \
    && [ ! -e "${_LOGPTH}/${_BUCKET_NAME}.${_TODAY}.cleanup.log" ] \
    && [ "${_DOW}" = 7 ] \
    && [ "${_cached}" = "YES" ]; then
    _test "only"
    _remove_older_than
    echo "$(date)" >> ${_LOGPTH}/${_BUCKET_NAME}.${_TODAY}.cleanup.log
  else
    _test "only"
  fi
}

# Function to clean up old backups
_cleanup() {
  _remove_older_than
  _collection_status
}

# Function to perform backup
_run_backup() {
  export _FULL_BACK_CMD="${_DCY_BUP_CMD} ${_BATCH_EXCLUDE} ${_BATCH_INCLUDE} --exclude '**' / ${_BACKUP_TARGET}"
  echo "Running in ${_MODE} mode for ${_BUCKET_NAME} on $(date)" >> ${_LOGFILE}
  echo "$(date)" >> ${_LOGPTH}/${_BUCKET_NAME}.${_TODAY}.${_MODE}.log
  ${_DCY_BUP_CMD} ${_BATCH_EXCLUDE} ${_BATCH_INCLUDE} --exclude '**' / ${_BACKUP_TARGET} >> ${_LOGFILE}
  wait
  _print_env "multiback_run_backup"
}

# Function to prepare backup
_backup() {
  _backup_prepare
  _set_mode
  _set_cmd
  _run_backup
  _check_if_repair
  _weekly_cleanup
  _check_if_worked_cleanly_or_log_err
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    boa info  >> ${_LOGFILE}
    echo "Sending email report on $(date)" >> ${_LOGFILE}
    echo >> ${_LOGFILE}
    s-nail -s "Backup report (${_MODE}) for ${_BUCKET_NAME} on $(date)" ${_MY_EMAIL} < ${_LOGFILE}
  fi
  cat ${_LOGFILE} >> ${_LOGPTH}/${_BUCKET_NAME}.archive.log
  rm -f ${_LOGFILE}
  _print_env "multiback_backup"
}

### Legacy procedure for reference
#
#   Note: Be careful while restoring not to prepend a slash to the path!
#
# $ backboa restore file [time] destination
#
#   Restoring a single file to tmp/
#   $ backboa restore data/disk/o1/backups/foo.tar.gz tmp/foo.tar.gz
#
#   Restoring an older version of a directory to tmp/ - interval or full date
#   $ backboa restore data/disk/o1/backups 7D8h8s tmp/backups
#   $ backboa restore data/disk/o1/backups 2014/11/11 tmp/backups
#
# _restore() {
#   if [ $# = 2 ]; then
#     echo "Command is ${_DCY_UTL_CMD} restore --path-to-restore $1 ${_BACKUP_TARGET} $2"
#     ${_DCY_UTL_CMD} restore --path-to-restore $1 ${_BACKUP_TARGET} $2
#   else
#     echo "Command is ${_DCY_UTL_CMD} restore --path-to-restore $1 --time $2 ${_BACKUP_TARGET} $3"
#     ${_DCY_UTL_CMD} restore --path-to-restore $1 --time $2 ${_BACKUP_TARGET} $3
#   fi
# }
#
### Legacy procedure for reference

### Duplicity man page https://duplicity.gitlab.io/devel/duplicity.1.html#name
#
#   duplicity [backup|full|incremental] [options] source_directory target_url
#   duplicity verify [options] [--compare-data] [--path-to-restore <relpath>] [--time time] source_url target_directory
#   duplicity collection-status [options] [--file-changed <relpath>] [--show-changes-in-set <index>] [--jsonstat]] target_url
#   duplicity list-current-files [options] [--time time] target_url
#   duplicity [restore] [options] [--path-to-restore <relpath>] [--time time] source_url target_directory
#   duplicity remove-older-than <time> [options] [--force] target_url
#   duplicity remove-all-but-n-full <count> [options] [--force] target_url
#   duplicity remove-all-inc-of-but-n-full <count> [options] [--force] target_url
#   duplicity cleanup [options] [--force] target_url
#
#   Duplicity enters restore mode because the URL comes before the local directory.
#   If we wanted to restore just the file "Mail/article" in /home/me as it was three days ago into /home/me/restored_file:
#
#   duplicity -t 3D --path-to-restore Mail/article sftp://uid@other.host/some_dir /home/me/restored_file
#
#   duplicity [restore] [options] [--path-to-restore <relpath>] [--time time] source_url target_directory
#
### Duplicity man page

### Restore Command in mybackup for reference
#
#   mybackup restore <SERVICE> [RESTORE_PATH] [RESTORE_TIME]
#   mybackup restore aws data/disk/your_username/static/projects 7D
#
# - <SERVICE>: The cloud storage service used for your backups (e.g., aws, b2, wasabi).
# - [RESTORE_PATH] (optional): The absolute path (no leading slash) of the file or directory to restore.
# - [RESTORE_TIME] (optional): The point in time for the restore, specified in human-readable formats like:
#   - 1D (1 day ago)
#   - 7D (7 days ago)
#   - 1M (1 month ago)
#
### Restore Command in mybackup for reference

# Function to restore backup
_restore() {
  local _restore_target=$1
  local _restore_path=$2
  local _restore_time=$3
  local _restore_command="${_DCY_UTL_CMD} restore"

  # Remove any trailing slash from _restore_path for proper basename extraction
  _clean_restore_path="${_restore_path%/}"

  # Extract the last part (basename) of the restore path.
  _last_part=$(basename "${_clean_restore_path}")

  # Combine _restore_target with the extracted basename.
  # Also, remove any trailing slash from _restore_target to avoid double slashes.
  _final_restore_target="${_restore_target%/}/${_last_part}"

  # Ensure _RESTORE_TARGET exists
  if [ -n "${_restore_target}" ]; then
    if [ ! -d "${_restore_target}" ]; then
      echo "Creating restore target directory: ${_restore_target}"
      mkdir -p "${_restore_target}"
    fi
  else
    _restore_target="/data/disk/${_user}/static/restores"
    if [ ! -d "${_restore_target}" ]; then
      echo "Creating restore target directory: ${_restore_target}"
      mkdir -p "${_restore_target}"
    fi
  fi
  if [ -n "${_restore_time}" ]; then
    _restore_command="${_restore_command} --time ${_restore_time}"
  fi
  _restore_command="${_restore_command} ${_BACKUP_TARGET}"
  if [ -n "${_restore_path}" ]; then
    _restore_command="${_restore_command} --path-to-restore ${_restore_path}"
  fi
  _restore_command="${_restore_command} ${_final_restore_target}"

  echo "Command is ${_restore_command}"
  # ${_DCY_UTL_CMD} restore --time ${_restore_time} ${_BACKUP_TARGET} --path-to-restore ${_restore_path} ${_restore_target}

  # su -s /bin/bash ${_user} -c "eval \"${_restore_command}\"" &> /dev/null
  eval "${_restore_command}"

  _print_env "multiback_restore"
}

# Function to set backup target based on service
_set_backup_target() {
  local _service=$1
  local _user=$2

  case "${_service}" in
    aws|aws_one_zone|aws_standard_ia)
      _load_credentials "${_service}" "${_user}"
      _construct_bucket_name "${_service}" "${_user}"

      # Define S3-specific options
      local _s3_endpoint="https://s3.dualstack.${AWS_REGION}.amazonaws.com"
      local _s3_options="--s3-endpoint-url ${_s3_endpoint} --s3-region-name ${AWS_REGION}"

      # Use intelligent-tiering options for specific services
      if [ "${_service}" = "aws_standard_ia" ] || [ "${_service}" = "aws_one_zone" ]; then
        local _s3_options="${_s3_options} --s3-use-ia"
      fi

      export _BACKUP_TARGET="boto3+s3://${_BUCKET_NAME} ${_s3_options}"
      ;;
    azure)
      _load_credentials "azure" "${_user}"
      _construct_bucket_name "azure" "${_user}"
      export _BACKUP_TARGET="azure://${AZURE_STORAGE_ACCOUNT}@${_BUCKET_NAME}"
      ;;
    b2)
      _load_credentials "b2" "${_user}"
      _construct_bucket_name "b2" "${_user}"
      export _BACKUP_TARGET="b2://${B2_ACCOUNT_ID}:${B2_APPLICATION_KEY}@${_BUCKET_NAME}"
      ;;
    cloudflare)
      _load_credentials "cloudflare" "${_user}"
      _construct_bucket_name "cloudflare" "${_user}"

      # Custom endpoint for Cloudflare R2
      local _r2_endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

      # Configure the S3 backup target
      export _BACKUP_TARGET="boto3+s3://${R2_ACCESS_KEY_ID}:${R2_SECRET_ACCESS_KEY}@${_r2_endpoint}/${_BUCKET_NAME}"
      ;;
    do_spaces)
      _load_credentials "do_spaces" "${_user}"
      _construct_bucket_name "do_spaces" "${_user}"
      export _BACKUP_TARGET="s3://${DO_SPACES_KEY}:${DO_SPACES_SECRET}@${DO_SPACES_REGION}/${_BUCKET_NAME}"
      ;;
    gcs)
      _load_credentials "gcs" "${_user}"
      _construct_bucket_name "gcs" "${_user}"
      export _BACKUP_TARGET="gs://${_BUCKET_NAME}"
      ;;
    ibm)
      _load_credentials "ibm" "${_user}"
      _construct_bucket_name "ibm" "${_user}"
      export _BACKUP_TARGET="ibmcos://${IBM_API_KEY_ID}:${IBM_SERVICE_INSTANCE_ID}@${IBM_REGION}/${_BUCKET_NAME}"
      ;;
    linode)
      _load_credentials "linode" "${_user}"
      _construct_bucket_name "linode" "${_user}"
      export _BACKUP_TARGET="s3://${LINODE_ACCESS_KEY}:${LINODE_SECRET_KEY}@${LINODE_REGION}/${_BUCKET_NAME}"
      ;;
    wasabi)
      _load_credentials "wasabi" "${_user}"
      _construct_bucket_name "wasabi" "${_user}"
      export _BACKUP_TARGET="s3://${WASABI_ACCESS_KEY}:${WASABI_SECRET_KEY}@${WASABI_REGION}/${_BUCKET_NAME}"
      ;;
    *)
      echo "Error: Unknown service ${_service}"
      exit 1
      ;;
  esac

  _print_env "multiback_set_backup_target"
}

# Main script
if [ "$#" -lt 3 ]; then
  _usage
fi

export _LOGPTH="/var/log/boa"
_NOW=$(date +%y%m%d-%H%M%S)
export _NOW=${_NOW//[^0-9-]/}
_TODAY=$(date +%y%m%d)
export _TODAY=${_TODAY//[^0-9]/}
_DOW=$(date +%u)
export _DOW=${_DOW//[^1-7]/}
_DOM=$(date +%e)
export _DOM=${_DOM//[^0-9]/}
_HST=${_hName//[^a-zA-Z0-9-.]/}
_HST=$(echo -n ${_HST} | tr A-Z a-z 2>&1)
export _HST_DASH=$(echo -n ${_HST} | tr . - 2>&1)

export _ACTION=$1
export _SERVICE=$2
export _USER=$3
export _RESTORE_TARGET="${4:-/var/backups/restored/}"
export _RESTORE_PATH="${5:-}"
export _RESTORE_TIME="${6:-}"
export _PIDFILE="/var/run/duplicity_${_SERVICE}_${_USER}.pid"
# Default values
export _DEFAULT_KEEP_WITHIN="3M"            # Default: 3 month
export _DEFAULT_FULL_BACKUP_FREQUENCY="28D" # Default: 28 days

# Log file for validation issues
export _VALIDATION_LOG_FILE="/var/log/backup_validation_issues.log"
export _SANITIZATION_TMP_DIR="/var/tmp/backup_sanitization"
mkdir -p "${_SANITIZATION_TMP_DIR}"
chmod 700 "${_SANITIZATION_TMP_DIR}"

_print_env "multiback_main"

# Create the PID file
_create_pid_file "${_PIDFILE}"
trap "rm -f ${_PIDFILE}; exit" EXIT

# Remove stale multiback PID file if necessary
_remove_stale_multiback_pid "${_SERVICE}" "${_USER}"

# Load paths configuration
_load_paths "${_USER}"

case "${_ACTION}" in
  test)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _test
    ;;
  backup)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _backup
    ;;
  cleanup)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _test
    _cleanup
    ;;
  list)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _test
    _list
    ;;
  purge)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _test
    _purge
    ;;
  status)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _test
    _status
    ;;
  repair)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _test
    _repair
    ;;
  restore)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _test
    _restore "${_RESTORE_TARGET}" "${_RESTORE_PATH}" "${_RESTORE_TIME}"
    ;;
  *)
    _usage
    ;;
esac

_remove_pid_file "${_PIDFILE}"

# Wipe out any exported variables to clean up env after running the backup
  export FULL_BACKUP_FREQUENCY=
  export PASSPHRASE=
  export _ACTION=
  export _BACKUP_TARGET=
  export _BUCKET_NAME=
  export _DCY_BUP_CMD=
  export _DCY_UTL_CMD=
  export _EXCLUDE_LIST=
  export _FBF_BUP_CMD=
  export _INCLUDE_LIST=
  export _LST_EXCLUDE=
  export _LST_INCLUDE=
  export _MODE=
  export _NAME=
  export _NOE_BUP_CMD=
  export _NOE_UTL_CMD=
  export _PIDFILE=
  export _RESTORE_PATH=
  export _RESTORE_TARGET=
  export _RESTORE_TIME=
  export _SERVICE=
  export _SOURCE=
  export _SRC_INCLUDE=
  export _USER=
  export _USER_EXCLUDE_PATHS=
  export _USER_INCLUDE_PATHS=
  export _USER_MERGED_ALL=
  export _cached=
  export _credentials_file=
  export _paths_file=
  export _secret_file=
  export _value=
  export _varname=

_print_env "multiback_exit"
exit 0
