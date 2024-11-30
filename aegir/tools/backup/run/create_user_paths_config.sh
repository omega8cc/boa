#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Log file for escape attempts and validation issues
_LOG_FILE="/var/log/backup_validation_issues.log"

# Function to log unauthorized access attempts
_log_validation_issue() {
  local _user=$1
  local _file=$2
  local _details=$3

  echo "[$(date)] Validation issue detected for user '${_user}' in file '${_file}': ${_details}" >> "${_LOG_FILE}"

  # Alert the admin
  echo "Alert: Validation issue detected for user '${_user}' in file '${_file}'. Check ${_LOG_FILE} for details." | mail -s "Backup Validation Alert for ${_user}" admin@example.com
}

# Function to validate and merge configuration files
_validate_and_merge_paths() {
  local _file=$1
  local _user=$2
  local _allowed_prefixes="^/(data/disk/${_user}/static|^/home/${_user}.ftp)"
  local _output_file=$3
  local _invalid_paths_found=false

  # Ensure output file exists and is empty
  > "${_output_file}"

  while IFS= read -r _line; do
    # Skip empty lines and comments
    if [[ "${_line}" =~ ^\s*(#|$) ]]; then
      echo "${_line}" >> "${_output_file}"
      continue
    fi

    # Validate directives
    if [[ "${_line}" =~ ^--(include|exclude|include-regexp|exclude-regexp) ]]; then
      if echo "${_line}" | grep -Eq "^--(include|exclude|include-regexp|exclude-regexp) ${_allowed_prefixes}"; then
        echo "${_line}" >> "${_output_file}"
      else
        _log_validation_issue "${_user}" "${_file}" "Invalid path: ${_line}"
        _invalid_paths_found=true
      fi
    else
      _log_validation_issue "${_user}" "${_file}" "Invalid directive: ${_line}"
      _invalid_paths_found=true
    fi
  done < "${_file}"

  # If invalid paths were found, alert and skip merging
  if [ "${_invalid_paths_found}" = true ]; then
    echo "Skipping invalid file '${_file}' for user '${_user}'."
    > "${_output_file}" # Clear output to avoid invalid entries
  fi
}

# Function to create or update a user's paths configuration file
_create_user_paths_config() {
  local _user=$1
  local _user_config_dir="/data/disk/${_user}/remote_backups/paths"
  local _user_control_dir="/data/disk/${_user}/static/control/remote_backups/config"
  local _include_file="${_user_config_dir}/.backboa.${_user}.include"
  local _exclude_file="${_user_config_dir}/.backboa.${_user}.exclude"
  local _include_regexp_file="${_user_config_dir}/.backboa.${_user}.include_regexp"
  local _exclude_regexp_file="${_user_config_dir}/.backboa.${_user}.exclude_regexp"
  local _merged_include_file="${_user_config_dir}/.backboa.${_user}.include.merged"
  local _merged_exclude_file="${_user_config_dir}/.backboa.${_user}.exclude.merged"
  local _include_ctrl_file="${_user_config_dir}/.backboa.${_user}.f93.include.ctrl"
  local _exclude_ctrl_file="${_user_config_dir}/.backboa.${_user}.f93.exclude.ctrl"

  # Ensure user configuration directory exists and is owned by root
  mkdir -p "${_user_config_dir}"
  chown root:root "${_user_config_dir}"
  chmod 700 "${_user_config_dir}"

  # Create default include/exclude files if they don't exist
  if [ ! -f "${_include_ctrl_file}" ]; then
    cat << EOF > "${_include_file}"
--include  /data/disk/${_user}/distro
--include  /data/disk/${_user}/platforms
--include  /data/disk/${_user}/static
--include  /home/${_user}.ftp
EOF
    touch "${_include_ctrl_file}"
  fi

  if [ ! -f "${_exclude_ctrl_file}" ]; then
    cat << EOF > "${_exclude_file}"
--exclude '**'
--exclude /data/disk/${_user}/aegir
--exclude /data/disk/${_user}/backup-exports
--exclude /data/disk/${_user}/backups
--exclude /data/disk/${_user}/log
--exclude /data/disk/${_user}/src
--exclude /data/disk/${_user}/tools
--exclude /data/disk/${_user}/undo
EOF
    touch "${_exclude_ctrl_file}"
  fi

  if [ ! -f "${_include_regexp_file}" ]; then
    echo "# No default include-regexp rules for ${_user}" > "${_include_regexp_file}"
  fi

  if [ ! -f "${_exclude_regexp_file}" ]; then
    echo "# No default exclude-regexp rules for ${_user}" > "${_exclude_regexp_file}"
  fi

  # Validate and merge system and user-space include files
  _validate_and_merge_paths "${_include_file}" "${_user}" "${_merged_include_file}"
  if [ -f "${_user_control_dir}/include.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/include.txt" "${_user}" "${_merged_include_file}"
  fi

  # Validate and merge system and user-space exclude files
  _validate_and_merge_paths "${_exclude_file}" "${_user}" "${_merged_exclude_file}"
  if [ -f "${_user_control_dir}/exclude.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/exclude.txt" "${_user}" "${_merged_exclude_file}"
  fi

  # Validate and merge regexp include files
  if [ -f "${_include_regexp_file}" ]; then
    _validate_and_merge_paths "${_include_regexp_file}" "${_user}" "${_user_config_dir}/.backboa.${_user}.include_regexp.merged"
  fi
  if [ -f "${_user_control_dir}/include_regexp.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/include_regexp.txt" "${_user}" "${_user_config_dir}/.backboa.${_user}.include_regexp.merged"
  fi

  # Validate and merge regexp exclude files
  if [ -f "${_exclude_regexp_file}" ]; then
    _validate_and_merge_paths "${_exclude_regexp_file}" "${_user}" "${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged"
  fi
  if [ -f "${_user_control_dir}/exclude_regexp.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/exclude_regexp.txt" "${_user}" "${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged"
  fi

  # Create the final paths configuration file
  local _user_config_file="${_user_config_dir}/paths/paths.txt"
  cat << EOF > "${_user_config_file}"
_SOURCE="/data/disk/${_user}/static"
_USER_INCLUDE="--include-filelist ${_merged_include_file} --include-regexp-filelist ${_user_config_dir}/.backboa.${_user}.include_regexp.merged"
_USER_EXCLUDE="--exclude-filelist ${_merged_exclude_file} --exclude-regexp-filelist ${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged"
EOF

  echo "Paths configuration for '${_user}' created or updated at '${_user_config_file}'."
}

# Generate paths configuration for each user
for _user_dir in /data/disk/*; do
  if [ -d "${_user_dir}" ]; then
    _user=$(basename "${_user_dir}")
    if [ "${_user}" != "arch" ] && [ "${_user}" != "global_user" ]; then
      _create_user_paths_config "${_user}"
    fi
  fi
done
