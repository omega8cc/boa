#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Ensure using the correct Python version
_PYTHON_BIN="python3.12"

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
  rm -f "${_pidfile}"
}

# Function to load credentials from a file
_load_credentials() {
  local _service=$1
  local _user=$2
  local _creds_path="/data/disk/${_user}/static/control/backups_credentials/${_service}.txt"
  if [ -f "${_creds_path}" ]; then
    source "${_creds_path}"
  else
    echo "Credentials file ${_creds_path} not found."
    exit 1
  fi
}

# Function to load paths and other settings from a file
_load_paths() {
  local _user=$1
  local _paths_path="/data/disk/${_user}/remote_backups/paths.txt"
  if [ -f "${_paths_path}" ]; then
    source "${_paths_path}"
  else
    echo "Paths configuration file ${_paths_path} not found."
    exit 1
  fi
}

# Function to construct BUCKET_NAME
_construct_bucket_name() {
  local _service_abbr=$1
  local _user=$2
  local _hostname=$(hostname -s)
  BUCKET_NAME="${_hostname}-${_service_abbr}-${_user}"
}

# Function to perform backup
_backup() {
  ${_PYTHON_BIN} -m duplicity \
    --full-if-older-than "${FULL_BACKUP_FREQUENCY}" \
    --volsize 50 \
    --allow-source-mismatch \
    --follow-links \
    --asynchronous-upload \
    ${EXCLUDE} \
    ${USER_EXCLUDE} \
    ${INCLUDE} \
    ${USER_INCLUDE} \
    --exclude '**' \
    "${SOURCE}" \
    "${BACKUP_TARGET}"
}

# Function to clean up old backups
_cleanup() {
  ${_PYTHON_BIN} -m duplicity remove-older-than "${KEEP_WITHIN}" --force "${BACKUP_TARGET}"
  ${_PYTHON_BIN} -m duplicity remove-all-but-n-full "${KEEP_FULL_BACKUPS}" --force "${BACKUP_TARGET}"
}

# Function to restore backup
_restore() {
  local _restore_target=$1
  local _restore_path=$2
  local _restore_time=$3
  local _restore_command="${_PYTHON_BIN} -m duplicity restore --allow-source-mismatch"

  # Ensure _RESTORE_TARGET exists
  if [ ! -d "${_restore_target}" ]; then
    echo "Creating restore target directory: ${_restore_target}"
    mkdir -p "${_restore_target}"
  fi

  if [ -n "${_restore_time}" ]; then
    _restore_command="${_restore_command} --time ${_restore_time}"
  fi

  _restore_command="${_restore_command} ${BACKUP_TARGET}"

  if [ -n "${_restore_path}" ]; then
    _restore_command="${_restore_command} ${_restore_path}"
  fi

  _restore_command="${_restore_command} ${_restore_target}"

  eval "${_restore_command}"
}

# Function to set backup target based on service
_set_backup_target() {
  local _service=$1
  local _user=$2

  case "${_service}" in
    aws)
      _load_credentials "aws" "${_user}"
      _construct_bucket_name "aws" "${_user}"
      BACKUP_TARGET="s3://${AWS_REGION}.amazonaws.com/${BUCKET_NAME}"
      ;;
    aws_one_zone)
      _load_credentials "aws_one_zone" "${_user}"
      _construct_bucket_name "aws_one_zone" "${_user}"
      BACKUP_TARGET="s3://${AWS_REGION}.amazonaws.com/${BUCKET_NAME}"
      ;;
    aws_standard_ia)
      _load_credentials "aws_standard_ia" "${_user}"
      _construct_bucket_name "aws_standard_ia" "${_user}"
      BACKUP_TARGET="s3://${AWS_REGION}.amazonaws.com/${BUCKET_NAME}"
      ;;
    gcs)
      _load_credentials "gcs" "${_user}"
      _construct_bucket_name "gcs" "${_user}"
      BACKUP_TARGET="gs://${BUCKET_NAME}"
      ;;
    b2)
      _load_credentials "b2" "${_user}"
      _construct_bucket_name "b2" "${_user}"
      BACKUP_TARGET="b2://${B2_ACCOUNT_ID}:${B2_APPLICATION_KEY}@${BUCKET_NAME}"
      ;;
    azure)
      _load_credentials "azure" "${_user}"
      _construct_bucket_name "azure" "${_user}"
      BACKUP_TARGET="azure://${AZURE_STORAGE_ACCOUNT}@${BUCKET_NAME}"
      ;;
    upcloud)
      _load_credentials "upcloud" "${_user}"
      _construct_bucket_name "upcloud" "${_user}"
      BACKUP_TARGET="s3://${UPCLOUD_USERNAME}:${UPCLOUD_PASSWORD}@${REGION}/${BUCKET_NAME}"
      ;;
    ibm)
      _load_credentials "ibm" "${_user}"
      _construct_bucket_name "ibm" "${_user}"
      BACKUP_TARGET="ibmcos://${IBM_API_KEY_ID}:${IBM_SERVICE_INSTANCE_ID}@${IBM_REGION}/${BUCKET_NAME}"
      ;;
    wasabi)
      _load_credentials "wasabi" "${_user}"
      _construct_bucket_name "wasabi" "${_user}"
      BACKUP_TARGET="s3://${WASABI_ACCESS_KEY}:${WASABI_SECRET_KEY}@${WASABI_REGION}/${BUCKET_NAME}"
      ;;
    do_spaces)
      _load_credentials "do_spaces" "${_user}"
      _construct_bucket_name "do_spaces" "${_user}"
      BACKUP_TARGET="s3://${DO_SPACES_KEY}:${DO_SPACES_SECRET}@${DO_SPACES_REGION}/${BUCKET_NAME}"
      ;;
    linode)
      _load_credentials "linode" "${_user}"
      _construct_bucket_name "linode" "${_user}"
      BACKUP_TARGET="s3://${LINODE_ACCESS_KEY}:${LINODE_SECRET_KEY}@${LINODE_REGION}/${BUCKET_NAME}"
      ;;
    *)
      echo "Error: Unknown service ${_service}"
      exit 1
      ;;
  esac
}

# Main script
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 {backup|cleanup|restore} <SERVICE> <USER> [RESTORE_TARGET] [RESTORE_PATH] [RESTORE_TIME]"
  exit 1
fi

_ACTION=$1
_SERVICE=$2
_USER=$3
_RESTORE_TARGET="${4:-/data/disk/${_USER}/static/backups/}"
_RESTORE_PATH="${5:-}"
_RESTORE_TIME="${6:-}"
_PIDFILE="/var/run/duplicity_${_SERVICE}_${_USER}.pid"

_create_pid_file "${_PIDFILE}"

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
    echo "Error: Invalid action ${_ACTION}"
    _remove_pid_file "${_PIDFILE}"
    exit 1
    ;;
esac

_remove_pid_file "${_PIDFILE}"
