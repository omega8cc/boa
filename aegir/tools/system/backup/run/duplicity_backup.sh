#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 9 -p $$
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
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
  : "${_INCIDENT_EMAIL_REPORT:=YES}"
  _AWS_VLV=${_AWS_VLV//[^a-z]/}
  if [ -z "${_AWS_VLV}" ]; then
    _AWS_VLV="warning"
  fi
  _DCY_MN_CMD="/usr/local/bin/duplicity -v ${_AWS_VLV} --concurrency 4"
}
_check_root

if [ -e "/root/.pause_heavy_tasks_maint.cnf" ]; then
  exit 0
fi

# New OpenSSL 3.x version is required
if [ ! -x "/usr/local/ssl3/bin/openssl" ]; then
  echo "New OpenSSL 3.x version is required"
  exit 1
fi

if [ `ps aux | grep -v "grep" | grep --count "duplicity"` -gt "0" ]; then
  echo "The duplicity backup is already running!"
  echo "Active duplicity process detected..."
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
  echo "  aws, aws_one_zone, aws_standard_ia, gcs, b2, azure, upcloud, ibm, wasabi, do_spaces, linode"
  exit 1
}

# Function to create a PID file
_create_pid_file() {
  pidfile="$1"
  if [ -f "$pidfile" ]; then
    echo "Process already running (PID file exists at $pidfile)"
    exit 1
  fi
  echo "$$" > "$pidfile" || { echo "Failed to create PID file: $pidfile"; exit 1; }
}

# Function to remove a PID file
_remove_pid_file() {
  _pidfile=$1
  if [ -f "${_pidfile}" ]; then
    rm -f "${_pidfile}" || {
      echo "Warning: Failed to remove PID file: ${_pidfile}"
    }
  fi
}

# Function to remove stale multiback PID file
_remove_stale_multiback_pid() {
  _multiback_pidfile="/var/run/duplicity_${_service}_${_user}.pid"
  if [ -f "${_multiback_pidfile}" ]; then
    _old_pid=$(cat "${_multiback_pidfile}")
    if [ -n "${_old_pid}" ] && ! kill -0 "${_old_pid}" 2>/dev/null; then
      echo "Stale multiback PID file detected: ${_multiback_pidfile}. Removing it."
      rm -f "${_multiback_pidfile}"
    fi
  fi
}

# Function to load credentials from a file
_load_credentials() {
  _service=$1
  _user=$2
  _creds_path="/data/disk/${_user}/static/control/remote_backups/credentials/${_service}.txt"
  if [ -f "${_creds_path}" ]; then
    source "${_creds_path}"
  else
    echo "Credentials file ${_creds_path} not found."
    exit 1
  fi
}

# Function to load paths and other settings from a file
_load_paths() {
  _user=$1
  _paths_path="/data/disk/${_user}/remote_backups/paths.txt"
  if [ -f "${_paths_path}" ]; then
    source "${_paths_path}"
  else
    echo "Paths configuration file ${_paths_path} not found."
    exit 1
  fi
}

# Function to construct _BUCKET_NAME
_construct_bucket_name() {
  _service_abbr=$1
  _user=$2
  _hostname=$(hostname -f)
  _BUCKET_NAME="back-to-${_user}-${_hostname}-${_service_abbr}"
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
  if [ -e "/root/.cache/duplicity" ]; then
    _CacheTest=$(find /root/.cache/duplicity/* \
      -maxdepth 1 \
      -mindepth 1 \
      -type f \
      | sort 2>&1)
    if [[ "${_CacheTest}" =~ "No such file or directory" ]] \
      || [ -z "${_CacheTest}" ]; then
      _DO_CLEANUP=NO
    else
      _DO_CLEANUP=YES
    fi
  fi
  # Generate include directives dynamically
  _INCLUDE=$(_generate_include_directives "${_SOURCE}")
}

_monthly_cleanup() {
  if [ -e "${_LOGPTH}/${_BUCKET_NAME}.randomize.cleanup.log" ]; then
    _RCL=$(cat ${_LOGPTH}/${_BUCKET_NAME}.randomize.cleanup.log 2>&1)
    _RCL=$(echo -n ${_RCL} | tr -d "\n" 2>&1)
    _RCL=${_RCL//[^1-5]/}
  else
    _RCL=$((RANDOM%5+1))
    _RCL=${_RCL//[^1-5]/}
    echo ${_RCL} > ${_LOGPTH}/${_BUCKET_NAME}.randomize.cleanup.log
  fi
  if [ -e "${_LOGPTH}/${_BUCKET_NAME}.archive.log" ] \
    && [ ! -e "/root/.skip_duplicity_monthly_cleanup.cnf" ] \
    && [ "${_DOM}" = "${_RCL}" ] \
    && [ "${_DO_CLEANUP}" = "YES" ]; then
    if [ -e "/root/.randomize_duplicity_full_backup_day.cnf" ]; then
      _n=$((RANDOM%300+8))
      echo "Waiting $n seconds on `date` before running cleanup --force" > ${_LOGFILE}
      sleep ${_n}
    fi
    echo "Running cleanup --force on `date`" >> ${_LOGFILE}
    echo "Command is ${_DCY_MN_CMD} cleanup --force ${_NAME} ${_TARGET}"
    ${_DCY_MN_CMD} cleanup --force ${_NAME} ${_TARGET}
    rm -f ${_LOGPTH}/${_BUCKET_NAME}.randomize.full.log
    rm -f ${_LOGPTH}/${_BUCKET_NAME}.randomize.cleanup.log
  fi
}

# Function to set backup mode
_set_mode() {
  if [ "${_DOW}" = "${_RDW}" ] && [ "${_AWS_FLC}" = "7D" ]; then
    if [ ! -e "/root/.randomize_duplicity_full_backup_day.cnf" ]; then
      _MODE="full"
      _AWS_FLC="1M"
    fi
  else
    if [ -e "${_LOGPTH}/${_BUCKET_NAME}.archive.log" ] \
      && [ "${_DO_CLEANUP}" = "YES" ]; then
      _MODE="incremental"
    else
      _MODE="full"
    fi
  fi
}

# Function to construct backup command
_set_cmd() {
  if [ -z "${FULL_BACKUP_FREQUENCY}" ] && [ -n "${_AWS_FLC}" ]; then
    FULL_BACKUP_FREQUENCY="${_AWS_FLC}"
  fi
  _DCY_UP_CMD="/usr/local/bin/duplicity ${_MODE} \
    -v ${_AWS_VLV} \
    --allow-source-mismatch \
    --concurrency 4 \
    --follow-links \
    --full-if-older-than ${FULL_BACKUP_FREQUENCY} \
    --volsize 300"
}

# Function to perform backup
_run_backup() {
  echo "Running ${_MODE} backup on `date`" >> ${_LOGFILE}
  ${_DCY_UP_CMD} \
  ${_EXCLUDE} \
  ${_USER_EXCLUDE} \
  ${_INCLUDE} \
  ${_USER_INCLUDE} \
  --exclude '**' \
  / \
  "${_BACKUP_TARGET}"
}

# Function to prepare backup
_backup() {
  _backup_prepare
  _monthly_cleanup
  _randomize_full
  _set_mode
  _set_cmd
  _run_backup
}

# Function to clean up old backups
_cleanup() {
  duplicity remove-older-than "${KEEP_WITHIN}" --force "${_BACKUP_TARGET}"
}

# Function to restore backup
_restore() {
  _restore_target=$1
  _restore_path=$2
  _restore_time=$3
  _restore_command="duplicity restore --allow-source-mismatch"

  # Ensure _RESTORE_TARGET exists
  if [ ! -d "${_restore_target}" ]; then
    echo "Creating restore target directory: ${_restore_target}"
    mkdir -p "${_restore_target}"
  fi

  if [ -n "${_restore_time}" ]; then
    _restore_command="${_restore_command} --time ${_restore_time}"
  fi

  _restore_command="${_restore_command} ${_BACKUP_TARGET}"

  if [ -n "${_restore_path}" ]; then
    _restore_command="${_restore_command} ${_restore_path}"
  fi

  _restore_command="${_restore_command} ${_restore_target}"

  eval "${_restore_command}"
}

# Function to set backup target based on service
_set_backup_target() {
  _service=$1
  _user=$2

  case "${_service}" in
    aws|aws_one_zone|aws_standard_ia)
      _load_credentials "${_service}" "${_user}"
      _construct_bucket_name "${_service}" "${_user}"

      # Define S3-specific options
      _s3_endpoint="https://s3.dualstack.${AWS_REGION}.amazonaws.com"
      _s3_options="--s3-endpoint-url ${_s3_endpoint} --s3-region-name ${AWS_REGION}"

      # Use intelligent-tiering options for specific services
      if [ "${_service}" = "aws_standard_ia" ] || [ "${_service}" = "aws_one_zone" ]; then
        _s3_options="${_s3_options} --s3-use-ia"
      fi

      _BACKUP_TARGET="boto3+s3://${_BUCKET_NAME} ${_s3_options}"
      ;;
    gcs)
      _load_credentials "gcs" "${_user}"
      _construct_bucket_name "gcs" "${_user}"
      _BACKUP_TARGET="gs://${_BUCKET_NAME}"
      ;;
    b2)
      _load_credentials "b2" "${_user}"
      _construct_bucket_name "b2" "${_user}"
      _BACKUP_TARGET="b2://${B2_ACCOUNT_ID}:${B2_APPLICATION_KEY}@${_BUCKET_NAME}"
      ;;
    azure)
      _load_credentials "azure" "${_user}"
      _construct_bucket_name "azure" "${_user}"
      _BACKUP_TARGET="azure://${AZURE_STORAGE_ACCOUNT}@${_BUCKET_NAME}"
      ;;
    upcloud)
      _load_credentials "upcloud" "${_user}"
      _construct_bucket_name "upcloud" "${_user}"
      _BACKUP_TARGET="s3://${UPCLOUD_USERNAME}:${UPCLOUD_PASSWORD}@${REGION}/${_BUCKET_NAME}"
      ;;
    ibm)
      _load_credentials "ibm" "${_user}"
      _construct_bucket_name "ibm" "${_user}"
      _BACKUP_TARGET="ibmcos://${IBM_API_KEY_ID}:${IBM_SERVICE_INSTANCE_ID}@${IBM_REGION}/${_BUCKET_NAME}"
      ;;
    wasabi)
      _load_credentials "wasabi" "${_user}"
      _construct_bucket_name "wasabi" "${_user}"
      _BACKUP_TARGET="s3://${WASABI_ACCESS_KEY}:${WASABI_SECRET_KEY}@${WASABI_REGION}/${_BUCKET_NAME}"
      ;;
    do_spaces)
      _load_credentials "do_spaces" "${_user}"
      _construct_bucket_name "do_spaces" "${_user}"
      _BACKUP_TARGET="s3://${DO_SPACES_KEY}:${DO_SPACES_SECRET}@${DO_SPACES_REGION}/${_BUCKET_NAME}"
      ;;
    linode)
      _load_credentials "linode" "${_user}"
      _construct_bucket_name "linode" "${_user}"
      _BACKUP_TARGET="s3://${LINODE_ACCESS_KEY}:${LINODE_SECRET_KEY}@${LINODE_REGION}/${_BUCKET_NAME}"
      ;;
    *)
      echo "Error: Unknown service ${_service}"
      exit 1
      ;;
  esac
}

# Main script
if [ "$#" -lt 3 ]; then
  _usage
fi

_LOGPTH="/var/xdrago/log"
_LOGFILE="${_LOGPTH}/${_BUCKET_NAME}.log"
_NOW=$(date +%y%m%d-%H%M%S 2>&1)
_NOW=${_NOW//[^0-9-]/}
_DOW=$(date +%u 2>&1)
_DOW=${_DOW//[^1-7]/}
_DOM=$(date +%e 2>&1)
_DOM=${_DOM//[^0-9]/}
_HST=$(uname -n 2>&1)
_HST=${_HST//[^a-zA-Z0-9-.]/}
_HST=$(echo -n ${_HST} | tr A-Z a-z 2>&1)
_HST_DASH=$(echo -n ${_HST} | tr . - 2>&1)


_ACTION=$1
_SERVICE=$2
_USER=$3
_RESTORE_TARGET="${4:-/var/backups/}"
_RESTORE_PATH="${5:-}"
_RESTORE_TIME="${6:-}"
_PIDFILE="/var/run/duplicity_${_SERVICE}_${_USER}.pid"

# Create the PID file
_create_pid_file "${_PIDFILE}"
trap "rm -f ${_PIDFILE}; exit" EXIT

# Remove stale multiback PID file if necessary
_remove_stale_multiback_pid

# Load paths configuration
_load_paths "${_USER}"

case "${_ACTION}" in
  backup)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _backup
    ;;
  cleanup)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _cleanup
    ;;
  restore)
    _set_backup_target "${_SERVICE}" "${_USER}"
    _restore "${_RESTORE_TARGET}" "${_RESTORE_PATH}" "${_RESTORE_TIME}"
    ;;
  *)
    _usage
    ;;
esac

_remove_pid_file "${_PIDFILE}"
