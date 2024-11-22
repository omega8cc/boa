#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Default interval in minutes between backup cycles
_BACKUP_INTERVAL=60
_WRAPPER_SCRIPT="/var/xdrago/backup/run/sequential_backups.sh"
_SCHEDULE_FILE="/var/xdrago/backup/backup_schedule.txt"
_CRON_FILE="/etc/cron.d/duplicity_backup"
_LOGFILE="/var/log/backup_runtime.log"

# Function to generate the wrapper script
_generate_wrapper_script() {
  cat << 'EOF' > "${_WRAPPER_SCRIPT}"
#!/bin/bash

# Enable strict error handling for debugging only
# set -euo pipefail

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# File paths
_SCHEDULE_FILE="/var/xdrago/backup/backup_schedule.txt"
_PID_DIR="/var/run"
_LOGFILE="/var/log/backup_runtime.log"

# Function to create a PID file
_create_pid_file() {
  local _pidfile=$1
  local _current_pid=$BASHPID  # Use BASHPID for unique PID in subshells

  if [ -f "${_pidfile}" ]; then
    local _old_pid
    _old_pid=$(cat "${_pidfile}")

    # Check if the process ID in the PID file is still active
    if [ -n "${_old_pid}" ] && kill -0 "${_old_pid}" 2>/dev/null; then
      echo "Process already running with PID ${_old_pid} (from ${_pidfile})"
      exit 1
    else
      echo "Stale PID file detected: ${_pidfile}. Removing it."
      rm -f "${_pidfile}"
    fi
  fi

  # Write the current PID to the file
  echo "${_current_pid}" > "${_pidfile}"
}

# Function to remove a PID file
_remove_pid_file() {
  local _pidfile=$1
  if [ -f "${_pidfile}" ]; then
    rm -f "${_pidfile}" || {
      echo "Warning: Failed to remove PID file: ${_pidfile}"
    }
  fi
}

# Function to handle cleanup on exit
_cleanup_on_exit() {
  _remove_pid_file "${_CURRENT_PIDFILE:-}"
}
trap _cleanup_on_exit EXIT

# Function to remove stale multiback PID file
_remove_stale_multiback_pid() {
  local _multiback_pidfile="/var/run/duplicity_${_service}_${_user}.pid"
  if [ -f "${_multiback_pidfile}" ]; then
    local _old_pid
    _old_pid=$(cat "${_multiback_pidfile}")
    if [ -n "${_old_pid}" ] && ! kill -0 "${_old_pid}" 2>/dev/null; then
      echo "Stale multiback PID file detected: ${_multiback_pidfile}. Removing it."
      rm -f "${_multiback_pidfile}"
    fi
  fi
}

# Read backup services and users from the configuration file
if [ ! -f "${_SCHEDULE_FILE}" ]; then
  echo "Error: Backup schedule file ${_SCHEDULE_FILE} not found."
  exit 1
fi

# Start processing each line from the configuration file
while IFS= read -r _line || [ -n "${_line}" ]; do
  # Skip empty lines and comments
  if [[ "${_line}" =~ ^\s*# ]] || [[ -z "${_line}" ]]; then
    continue
  fi

  # Parse service and user
  _service=$(echo "${_line}" | cut -d' ' -f1)
  _user=$(echo "${_line}" | cut -d' ' -f2)

  # Ensure both service and user are defined
  if [ -z "${_service}" ] || [ -z "${_user}" ]; then
    echo "Error: Invalid line in configuration file: ${_line}"
    continue
  fi

  echo "Starting backup for ${_service} (${_user})..."

  # Define the PID file path
  _CURRENT_PIDFILE="${_PID_DIR}/duplicity_${_service}_${_user}_script.pid"

  # Create the PID file
  _create_pid_file "${_CURRENT_PIDFILE}"

  # Remove stale multiback PID file if necessary
  _remove_stale_multiback_pid

  # Determine the paths configuration file
  if [ "${_user}" = "global_user" ]; then
    _paths_file="/var/xdrago/backup/paths.txt"
    _credentials_file="/var/xdrago/backup/credentials/${_service}.txt"

    # Check if paths.txt exists
    if [ ! -f "${_paths_file}" ]; then
      echo "Error: Paths configuration file ${_paths_file} not found."
      _remove_pid_file "${_CURRENT_PIDFILE}"
      continue
    fi

    # Check if credentials file exists
    if [ ! -f "${_credentials_file}" ]; then
      echo "Error: Credentials file ${_credentials_file} not found."
      _remove_pid_file "${_CURRENT_PIDFILE}"
      continue
    fi

    # Change to the directory where paths.txt and credentials are located
    cd /var/xdrago/backup

  else
    _paths_file="/data/disk/${_user}/remote_backups/paths.txt"
    _credentials_file="/data/disk/${_user}/static/control/remote_backups/credentials/${_service}.txt"

    if [ ! -f "${_paths_file}" ]; then
      echo "Error: Paths configuration file ${_paths_file} not found."
      _remove_pid_file "${_CURRENT_PIDFILE}"
      continue
    fi

    if [ ! -f "${_credentials_file}" ]; then
      echo "Error: Credentials file ${_credentials_file} not found."
      _remove_pid_file "${_CURRENT_PIDFILE}"
      continue
    fi

    # Change to the directory where paths.txt and credentials are located
    cd "/data/disk/${_user}/remote_backups"
  fi

  # Load the paths configuration
  [ -f "${_paths_file}" ] && source "${_paths_file}"

  # Export variables so multiback can use them
  export _SOURCE
  export _INCLUDE
  export _EXCLUDE

  # Perform the backup
  if multiback backup "${_service}" "${_user}"; then
    echo "Backup for ${_service} (${_user}) completed successfully."
  else
    echo "Backup for ${_service} (${_user}) failed."
  fi

  # Return to the original directory
  cd -

  # Remove the PID file
  _remove_pid_file "${_CURRENT_PIDFILE}"

done < "${_SCHEDULE_FILE}"
EOF

  chmod +x "${_WRAPPER_SCRIPT}"
  echo "Wrapper script created at ${_WRAPPER_SCRIPT}"
}

# Function to create cron entries
_create_cron_entries() {
  echo "# Cron job for sequential backups" > "${_CRON_FILE}"
  echo "0 */$((_BACKUP_INTERVAL / 60)) * * * root ${_WRAPPER_SCRIPT}" >> "${_CRON_FILE}"
  chmod 644 "${_CRON_FILE}"
  echo "Cron entry created at ${_CRON_FILE}"

  # Validate the cron file
  _validate_cron_file
}

# Function to validate the cron file
_validate_cron_file() {
  if ! grep -q -E "^[^#]*${_WRAPPER_SCRIPT}" "${_CRON_FILE}"; then
    echo "Error: Cron file validation failed. Please check the file at ${_CRON_FILE}."
    exit 1
  fi
  echo "Cron file validated successfully."
}

# Function to generate the backup schedule
_generate_backup_schedule() {
  echo "# Backup schedule (service user)" > "${_SCHEDULE_FILE}"

  # Add global backups
  _GLOBAL_CRED_DIR="/var/xdrago/backup/credentials"
  for _service in aws aws_one_zone aws_standard_ia gcs b2 azure upcloud ibm wasabi do_spaces linode; do
    if [ -f "${_GLOBAL_CRED_DIR}/${_service}.txt" ] && ! grep -q "your_" "${_GLOBAL_CRED_DIR}/${_service}.txt"; then
      echo "${_service} global_user" >> "${_SCHEDULE_FILE}"
    fi
  done

  # Add user-specific backups
  for _user_dir in /data/disk/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      _USER_CRED_DIR="/data/disk/${_user}/static/control/remote_backups/credentials"
      for _service in aws aws_one_zone aws_standard_ia gcs b2 azure upcloud ibm wasabi do_spaces linode; do
        if [ -f "${_USER_CRED_DIR}/${_service}.txt" ] && ! grep -q "your_" "${_USER_CRED_DIR}/${_service}.txt"; then
          echo "${_service} ${_user}" >> "${_SCHEDULE_FILE}"
        fi
      done
    fi
  done

  echo "Backup schedule created at ${_SCHEDULE_FILE}"
}

# Function to adjust the backup interval dynamically
_adjust_backup_interval() {
  if [ -f "${_LOGFILE}" ]; then
    _TOTAL_RUNTIME=$(tail -n1 "${_LOGFILE}" | awk '{print $NF}')
    _NEW_INTERVAL=$(( (_TOTAL_RUNTIME / 3600 + 1) * 60 ))  # Round up to the next hour
    if [ "${_NEW_INTERVAL}" -gt "${_BACKUP_INTERVAL}" ]; then
      _BACKUP_INTERVAL="${_NEW_INTERVAL}"
      echo "Adjusted backup interval to $((_BACKUP_INTERVAL / 60)) hours."
      _create_cron_entries
    fi
  fi
}

# Main script execution
_generate_wrapper_script
_generate_backup_schedule
_adjust_backup_interval
_create_cron_entries
