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

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# File paths
_BACKUP_CONFIG="/var/xdrago/backup/backup_schedule.txt"
_PID_DIR="/var/run"

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

# Function to handle cleanup on exit
_cleanup_on_exit() {
  _remove_pid_file "${_CURRENT_PIDFILE}"
}
trap _cleanup_on_exit EXIT

# Read backup services and users from the configuration file
if [ ! -f "${_BACKUP_CONFIG}" ]; then
  echo "Error: Backup schedule file ${_BACKUP_CONFIG} not found."
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

  # Set up PID file
  _CURRENT_PIDFILE="${_PID_DIR}/duplicity_${_service}_${_user}.pid"
  _create_pid_file "${_CURRENT_PIDFILE}"

  # Determine paths configuration
  if [ "${_user}" = "global_user" ]; then
    _paths_file="/var/xdrago/backup/paths.txt"
  else
    _paths_file="/data/disk/${_user}/remote_backups/paths.txt"
  fi

  if [ ! -f "${_paths_file}" ]; then
    echo "Paths configuration file ${_paths_file} not found."
    _remove_pid_file "${_CURRENT_PIDFILE}"
    continue
  fi

  # Load paths configuration
  source "${_paths_file}"

  # Perform backup
  multiback backup "${_service}" "${_user}"

  echo "Backup for ${_service} (${_user}) completed."

  # Remove PID file
  _remove_pid_file "${_CURRENT_PIDFILE}"

done < "${_BACKUP_CONFIG}"
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
