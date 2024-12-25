#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export _sPid="f84"

# Log file for escape attempts and validation issues
_VALIDATION_LOG_FILE="/var/log/backup_validation_issues.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
    : "${_INCIDENT_REPORT:=YES}"
  fi
}
_check_root

# Function to log validation issues
_log_issue() {
  local _type=$1
  local _file=$2
  local _message=$3
  echo "[$(date)] Validation issue: [${_type}] in file: [${_file}] with error: ${_message}" >> "${_VALIDATION_LOG_FILE}"
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    # Alert the admin
    echo "Sending Backup Validation Alert to ${_MY_EMAIL} on $(date)" >> ${_VALIDATION_LOG_FILE}
    s-nail -s "Backup Validation Alert for [$(hostname)] on $(date)" ${_MY_EMAIL} < ${_VALIDATION_LOG_FILE}
  fi
}

# Function to validate and merge configuration files
_validate_and_merge_paths() {
  local _file=$1
  local _user=$2
  local _allowed_prefixes="^/(data/disk/${_user}/static|^/home/${_user}.ftp)"
  local _output_file=$3
  local _if_validate=$4
  local _invalid_paths_found=false

  # Ensure output file exists and is empty
  > "${_output_file}"

  while IFS= read -r _line; do
    # Skip empty lines and comments
    if [[ "${_line}" =~ ^\s*(#|$) ]]; then
      echo "${_line}" >> "${_output_file}"
      continue
    fi

    if [ "${_if_validate}" = "YES" ]; then
      # Validate directives
      if [[ "${_line}" =~ ^--(include|exclude|include-regexp|exclude-regexp) ]]; then
        if echo "${_line}" | grep -Eq "^--(include|exclude|include-regexp|exclude-regexp) ${_allowed_prefixes}"; then
          echo "${_line}" >> "${_output_file}"
        else
          _log_issue "${_user}" "${_file}" "Invalid path: ${_line}"
          _invalid_paths_found=true
        fi
      else
        _log_issue "${_user}" "${_file}" "Invalid directive: ${_line}"
        _invalid_paths_found=true
      fi
    elif [ "${_if_validate}" = "NO" ]; then
      echo "${_line}" >> "${_output_file}"
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
  local _include_file="${_user_config_dir}/.backboa.${_user}.include.file"
  local _exclude_file="${_user_config_dir}/.backboa.${_user}.exclude.file"
  local _include_regexp_file="${_user_config_dir}/.backboa.${_user}.include_regexp.file"
  local _exclude_regexp_file="${_user_config_dir}/.backboa.${_user}.exclude_regexp.file"
  local _merged_include_file="${_user_config_dir}/.backboa.${_user}.include.merged.file"
  local _merged_exclude_file="${_user_config_dir}/.backboa.${_user}.exclude.merged.file"
  local _merged_regexp_include_file="${_user_config_dir}/.backboa.${_user}.include_regexp.merged.file"
  local _merged_regexp_exclude_file="${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged.file"
  local _exclude_ctrl_file="${_user_config_dir}/.backboa.${_user}.${_sPid}.exclude.ctrl.file"
  local _include_ctrl_file="${_user_config_dir}/.backboa.${_user}.${_sPid}.include.ctrl.file"
  local _merged_all_exclude_file="${_user_config_dir}/.backboa.${_user}.all.exclude.merged.file"
  local _merged_all_include_file="${_user_config_dir}/.backboa.${_user}.all.include.merged.file"
  local _user_paths_file="${_user_config_dir}/paths.txt"

  # Ensure user configuration directory exists and is owned by root
  mkdir -p "${_user_config_dir}"
  chown root:root "${_user_config_dir}"
  chmod 700 "${_user_config_dir}"

  if [ ! -f "${_exclude_ctrl_file}" ]; then
    cat << EOF > "${_exclude_file}"
--exclude /data/disk/${_user}/aegir
--exclude /data/disk/${_user}/backup-exports
--exclude /data/disk/${_user}/backups
--exclude /data/disk/${_user}/log
--exclude /data/disk/${_user}/src
--exclude /data/disk/${_user}/tmp
--exclude /data/disk/${_user}/.tmp
--exclude /data/disk/${_user}/static/restores
--exclude /data/disk/${_user}/static/trash
--exclude /data/disk/${_user}/tools
--exclude /data/disk/${_user}/undo
EOF
    rm -f ${_user_config_dir}/.backboa.${_user}.*.exclude.ctrl.file
    touch "${_exclude_ctrl_file}"
  fi

  # Create default include/exclude files if they don't exist
  if [ ! -f "${_include_ctrl_file}" ]; then
    cat << EOF > "${_include_file}"
--include  /data/disk/${_user}/distro
--include  /data/disk/${_user}/platforms
--include  /data/disk/${_user}/static
--include  /home/${_user}.ftp
EOF
    rm -f "${_user_config_dir}/.backboa.${_user}.*.include.ctrl.file"
    touch "${_include_ctrl_file}"
  fi

  if [ ! -f "${_user_control_dir}/exclude_regexp.txt" ]; then
    [ -e "${_exclude_regexp_file}" ] && rm -f "${_exclude_regexp_file}"
    [ -e "${_merged_regexp_exclude_file}" ] && rm -f "${_merged_regexp_exclude_file}"
  fi

  if [ ! -f "${_user_control_dir}/include_regexp.txt" ]; then
    [ -e "${_include_regexp_file}" ] && rm -f "${_include_regexp_file}"
    [ -e "${_merged_regexp_include_file}" ] && rm -f "${_merged_regexp_include_file}"
  fi

  # Validate and merge system and user-space exclude files
  _validate_and_merge_paths "${_exclude_file}" "${_user}" "${_merged_exclude_file}" NO
  if [ -f "${_user_control_dir}/exclude.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/exclude.txt" "${_user}" "${_merged_exclude_file}" YES
  fi

  # Validate and merge system and user-space include files
  _validate_and_merge_paths "${_include_file}" "${_user}" "${_merged_include_file}" NO
  if [ -f "${_user_control_dir}/include.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/include.txt" "${_user}" "${_merged_include_file}" YES
  fi

  # Validate and merge regexp exclude files
  if [ -f "${_exclude_regexp_file}" ]; then
    _validate_and_merge_paths "${_exclude_regexp_file}" "${_user}" "${_merged_regexp_exclude_file}" NO
  fi
  if [ -f "${_user_control_dir}/exclude_regexp.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/exclude_regexp.txt" "${_user}" "${_merged_regexp_exclude_file}" YES
  fi

  # Validate and merge regexp include files
  if [ -f "${_include_regexp_file}" ]; then
    _validate_and_merge_paths "${_include_regexp_file}" "${_user}" "${_merged_regexp_include_file}" NO
  fi
  if [ -f "${_user_control_dir}/include_regexp.txt" ]; then
    _validate_and_merge_paths "${_user_control_dir}/include_regexp.txt" "${_user}" "${_merged_regexp_include_file}" YES
  fi

  # Function to add a single backslash at the end of each line except the last
  _add_backslashes() {
    local file="$1"
    if [ -f "${file}" ]; then
      # Remove existing trailing backslashes to avoid duplication
      sed -i 's/[[:space:]]*\\$//' "${file}"
      # Append a backslash to all lines except the last one
      sed -i '$!s/$/ \\/' "${file}"
    fi
  }

  # Merge all exclude path directives into single file
  cat "${_merged_exclude_file}" > "${_merged_all_exclude_file}"
  cat "${_merged_regexp_exclude_file}" >> "${_merged_all_exclude_file}"

  # Merge all include path directives into single file
  cat "${_merged_include_file}" > "${_merged_all_include_file}"
  cat "${_merged_regexp_include_file}" >> "${_merged_all_include_file}"

  # Finalize by adding a backslash at the end of each line except the last
  _add_backslashes "${_merged_all_exclude_file}"
  _add_backslashes "${_merged_all_include_file}"

  # Convert the exclude file contents to a single-line variable without backslashes and excessive whitespace
  local _MERGED_ALL_EXCLUDE=$(sed 's/\\//g' "${_merged_all_exclude_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

  # Convert the include file contents to a single-line variable without backslashes and excessive whitespace
  local _MERGED_ALL_INCLUDE=$(sed 's/\\//g' "${_merged_all_include_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

  # Create the final paths configuration file
  cat << EOF > "${_user_paths_file}"
_SOURCE="/data/disk/${_user}/static"
_USER_EXCLUDE_PATHS="${_MERGED_ALL_EXCLUDE}"
_USER_INCLUDE_PATHS="${_MERGED_ALL_INCLUDE}"
EOF

  echo "Paths configuration for '${_user}' created or updated at '${_user_paths_file}'."
}

# Generate paths configuration for each user
for _user_dir in /data/disk/*; do
  if [ -d "${_user_dir}" ]; then
    _user=$(basename "${_user_dir}")
    if [ "${_user}" != "arch" ] && [ "${_user}" != "data" ] && [ "${_user}" != "global" ]; then
      _create_user_paths_config "${_user}"
    fi
  fi
done
