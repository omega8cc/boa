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

# Initialize variables
_PIDFILE="/var/run/backup_runner.pid"
_LOGFILE="/var/log/backup_runtime.log"
_SCHEDULE_FILE="/var/xdrago/backup/backup_schedule.txt"
_START_TIME=$(date +%s)

# Function to run a single backup
_run_backup() {
  local _service=$1
  local _user=$2
  local _config_dir=$3

  # Check for existing PID file
  if [ -f "${_PIDFILE}" ]; then
    echo "Backup process already running. Exiting..."
    exit 1
  fi

  # Create PID file
  echo $$ > "${_PIDFILE}"

  # Run the backup
  echo "Starting backup for ${_service} (${_user})..."
  multiback backup "${_service}" "${_user}" "${_config_dir}/paths.txt"

  # Remove PID file
  rm -f "${_PIDFILE}"
  echo "Backup for ${_service} (${_user}) completed."
}

# Sequentially run backups
while read -r _entry; do
  _service=$(echo "${_entry}" | cut -d' ' -f1)
  _user=$(echo "${_entry}" | cut -d' ' -f2)
  _config_dir=$(echo "${_entry}" | cut -d' ' -f3)
  _run_backup "${_service}" "${_user}" "${_config_dir}"
done < "${_SCHEDULE_FILE}"

# Log total runtime
_END_TIME=$(date +%s)
_RUNTIME=$((_END_TIME - _START_TIME))
echo "Total runtime: ${_RUNTIME} seconds" >> "${_LOGFILE}"
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
  echo "# Backup schedule (service user config_dir)" > "${_SCHEDULE_FILE}"

  # Add global backups
  _GLOBAL_CRED_DIR="/var/xdrago/backup/credentials"
  _GLOBAL_CONFIG_DIR="/var/xdrago/backup"
  for _service in aws aws_one_zone aws_standard_ia gcs b2 azure upcloud ibm wasabi do_spaces linode; do
    if [ -f "${_GLOBAL_CRED_DIR}/${_service}.txt" ] && ! grep -q "your_" "${_GLOBAL_CRED_DIR}/${_service}.txt"; then
      echo "${_service} global_user ${_GLOBAL_CONFIG_DIR}" >> "${_SCHEDULE_FILE}"
    fi
  done

  # Add user-specific backups
  for _user_dir in /data/disk/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      _USER_CRED_DIR="/data/disk/${_user}/static/control/remote_backups/credentials"
      _USER_CONFIG_DIR="/data/disk/${_user}/remote_backups"
      for _service in aws aws_one_zone aws_standard_ia gcs b2 azure upcloud ibm wasabi do_spaces linode; do
        if [ -f "${_USER_CRED_DIR}/${_service}.txt" ] && ! grep -q "your_" "${_USER_CRED_DIR}/${_service}.txt"; then
          echo "${_service} ${_user} ${_USER_CONFIG_DIR}" >> "${_SCHEDULE_FILE}"
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
