#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Configurable in /root/.barracuda.cnf interval in minutes between backup cycles
_BACKUP_INTERVAL=360
_WRAPPER_DIR="/root/.remote_backups/run"
_WRAPPER_SCRIPT="${_WRAPPER_DIR}/sequential_backups.sh"
_SCHEDULE_DIR="/root/.remote_backups/schedule"
_SCHEDULE_FILE="${_SCHEDULE_DIR}/backup_schedule.txt"
_CRON_FILE="/etc/cron.d/duplicity_backup"
_LOGFILE="/var/log/backup_runtime.log"

# Function to verify root access
_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 0 -p $$
    chmod a+w /dev/null
    [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST="$(command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 { gsub(/%/,"",$u); print $u }')"
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
_check_root

# shellcheck disable=SC1091
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
export _BACKUP_INTERVAL=${_BACKUP_INTERVAL//[^0-9]/}
: "${_BACKUP_INTERVAL:=360}"

# Ensure global run directory exists and is owned by root
mkdir -p "${_WRAPPER_DIR}"
chown root:root "${_WRAPPER_DIR}"
chmod 700 "${_WRAPPER_DIR}"

# Ensure global schedule directory exists and is owned by root
mkdir -p "${_SCHEDULE_DIR}"
chown root:root "${_SCHEDULE_DIR}"
chmod 700 "${_SCHEDULE_DIR}"

# Function to generate the wrapper script
_generate_wrapper_script() {
  cat << 'EOF' > "${_WRAPPER_SCRIPT}"
#!/bin/bash

# Enable strict error handling for debugging only
# set -euo pipefail

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# File paths
_SCHEDULE_FILE="/root/.remote_backups/schedule/backup_schedule.txt"
_PID_DIR="/run"
_LOGFILE="/var/log/backup_runtime.log"

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
  _multiback_pidfile="/run/duplicity_${_service}_${_user}.pid"
  if [ -f "${_multiback_pidfile}" ]; then
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

# Process each line in the backup configuration file
while IFS= read -r _line || [ -n "${_line}" ]; do
  # Skip empty lines and comments
  if [[ "${_line}" =~ ^\s*# ]] || [[ -z "${_line}" ]]; then
    continue
  fi

  # Parse the service and user
  _service=$(echo "${_line}" | cut -d' ' -f1)
  _user=$(echo "${_line}" | cut -d' ' -f2)

  # Ensure both service and user are defined
  if [ -z "${_service}" ] || [ -z "${_user}" ]; then
    echo "Error: Invalid line in configuration file: ${_line}"
    continue
  fi

  echo "Starting backup for ${_service} (${_user})..."
  export _service="${_service}"
  export _user="${_user}"

  # Define the PID file path
  _CURRENT_PIDFILE="${_PID_DIR}/duplicity_${_service}_${_user}_sequential.pid"

  # Create the PID file
  _create_pid_file "${_CURRENT_PIDFILE}"
  trap "rm -f ${_PIDFILE}; exit" EXIT

  # Remove stale multiback PID file if necessary
  _remove_stale_multiback_pid

  # Determine the paths configuration file
  if [ "${_user}" = "global" ] || [ "${_user}" = "data" ] || [ "${_user}" = "custom" ]; then
    _paths_file="/root/.remote_backups/paths/${_user}_paths.txt"
    _credentials_file="/root/.remote_backups/credentials/${_service}.txt"
    _secret_file="/root/.remote_backups/.secret.txt"

    if [ ! -f "${_secret_file}" ]; then
      echo "Secret file ${_secret_file} not found."
      _remove_pid_file "${_CURRENT_PIDFILE}"
      continue
    fi

    # Check if _paths_file exists
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

    # Change to the directory where _paths_file and credentials are located
    cd /root/.remote_backups
    _print_env "sequential_backups_a"

  elif [ "${_user}" != "arch" ] \
    && [ "${_user}" != "data" ] \
    && [ "${_user}" != "global" ] \
    && [ "${_user}" != "static" ] \
    && [ "${_user}" != "custom" ]; then
    _paths_file="/data/disk/${_user}/remote_backups/paths/paths.txt"
    _credentials_file="/data/disk/${_user}/static/control/remote_backups/credentials/${_service}.txt"
    _secret_file="/data/disk/${_user}/remote_backups/.secret.txt"

    if [ ! -f "${_secret_file}" ]; then
      echo "Secret file ${_secret_file} not found."
      _remove_pid_file "${_CURRENT_PIDFILE}"
      continue
    fi

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

    # Change to the directory where _paths_file and credentials are located
    cd "/data/disk/${_user}/remote_backups"
    _print_env "sequential_backups_b"
  fi

  # Perform the backup
  if multiback backup "${_service}" "${_user}"; then
    echo "Backup for ${_service} (${_user}) completed successfully."
  else
    echo "Backup for ${_service} (${_user}) failed."
  fi

  # Wipe out exported variables to clean up env after running the backup
  export _service=
  export _user=

  # Return to the original directory
  cd -
  _print_env "sequential_backups_d"

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
  _custom_paths_file="/root/.remote_backups/paths/custom_paths.txt"
  _GLOBAL_CRED_DIR="/root/.remote_backups/credentials"
  for _service in aws aws_one_zone aws_standard_ia azure b2 cloudflare do_spaces gcs ibm linode wasabi; do
    if [ -f "${_GLOBAL_CRED_DIR}/${_service}.txt" ] && ! grep -q "your_" "${_GLOBAL_CRED_DIR}/${_service}.txt"; then
      echo "${_service} global" >> "${_SCHEDULE_FILE}"
      echo "${_service} data" >> "${_SCHEDULE_FILE}"
      [ -s "${_custom_paths_file}" ] && echo "${_service} custom" >> "${_SCHEDULE_FILE}"
    fi
  done

  # Add user-specific backups
  for _user_dir in /data/disk/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      _USER_CRED_DIR="/data/disk/${_user}/static/control/remote_backups/credentials"
      for _service in aws aws_one_zone aws_standard_ia azure b2 cloudflare do_spaces gcs ibm linode wasabi; do
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
