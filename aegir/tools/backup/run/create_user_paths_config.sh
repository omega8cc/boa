#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _sPid="f62"

# Log file for escape attempts and validation issues
_VALIDATION_LOG_FILE="/var/log/backup_validation_issues.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
    : "${_INCIDENT_REPORT:=YES}"
  fi
}
_check_root

# Function to generate passphrase for user level backups
_generate_user_secret_file() {
  local _user=$1
  local _secret_file="/data/disk/${_user}/remote_backups/.secret.txt"
  if [ ! -s "${_secret_file}" ]; then
    openssl rand -base64 32 > "${_secret_file}"
    chmod 600 "${_secret_file}"
    chattr +i "${_secret_file}"
    echo "User secret file created at ${_secret_file} and made immutable."
  else
    echo "User secret file already exists at ${_secret_file}."
  fi
}

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
  local _allowed_prefixes="'^/((data/disk/${_user}/static)|(home/${_user}\.ftp))"
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
  local _include_list="${_user_config_dir}/.backboa.${_user}.include.list"
  local _exclude_list="${_user_config_dir}/.backboa.${_user}.exclude.list"
  local _include_file="${_user_config_dir}/.backboa.${_user}.include.file"
  local _exclude_file="${_user_config_dir}/.backboa.${_user}.exclude.file"
  local _include_regexp_file="${_user_config_dir}/.backboa.${_user}.include_regexp.file"
  local _exclude_regexp_file="${_user_config_dir}/.backboa.${_user}.exclude_regexp.file"
  local _merged_include_file="${_user_config_dir}/.backboa.${_user}.include.merged.file"
  local _merged_exclude_file="${_user_config_dir}/.backboa.${_user}.exclude.merged.file"
  local _merged_regexp_include_file="${_user_config_dir}/.backboa.${_user}.include_regexp.merged.file"
  local _merged_regexp_exclude_file="${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged.file"
  local _user_ctrl_file="${_user_config_dir}/.backboa.${_sPid}.paths.ctrl.file"
  local _include_ctrl_file="${_user_config_dir}/.backboa.${_user}.${_sPid}.include.ctrl.file"
  local _exclude_ctrl_file="${_user_config_dir}/.backboa.${_user}.${_sPid}.exclude.ctrl.file"
  local _merged_all_include_file="${_user_config_dir}/.backboa.${_user}.all.include.merged.file"
  local _merged_all_exclude_file="${_user_config_dir}/.backboa.${_user}.all.exclude.merged.file"
  local _user_paths_file="${_user_config_dir}/paths.txt"

  # Ensure user configuration directory exists and is owned by root
  mkdir -p "${_user_config_dir}"
  chown root:root "${_user_config_dir}"
  chmod 755 "${_user_config_dir}"

  # Function to append unique entries from source to target file
  _append_unique_entries() {
    _source_file=$1
    _target_file=$2
    if [ -f "${_source_file}" ]; then
      grep -v -F -x -f "${_target_file}" "${_source_file}" >> "${_target_file}"
    fi
  }

  if [ ! -f "${_user_ctrl_file}" ]; then

    ### Migrate legacy exclude/include files if present and merge unique entries

    # _include_list
    if [ -f "/root/.backboa.include" ]; then
      if [ ! -f "${_include_list}" ]; then
        cp "/root/.backboa.include" "${_include_list}"
      else
        _append_unique_entries "/root/.backboa.include" "${_include_list}"
      fi
    fi

    # _exclude_list
    if [ -f "/root/.backboa.exclude" ]; then
      if [ ! -f "${_exclude_list}" ]; then
        cp "/root/.backboa.exclude" "${_exclude_list}"
      else
        _append_unique_entries "/root/.backboa.exclude" "${_exclude_list}"
      fi
    else
      cat << EOF > "${_exclude_list}"
**files/advagg_css/**
**files/advagg_js/**
**files/css/**
**files/js/**
**private/temp/**
EOF
    fi

    ### Create default exclude/include files if they don't exist

    # _include_file
    if [ ! -f "${_include_ctrl_file}" ]; then
      cat << EOF > "${_include_file}"
--include /data/disk/${_user}/distro
--include /data/disk/${_user}/platforms
--include /data/disk/${_user}/static
--include /home/${_user}.ftp
EOF
      rm -f "${_user_config_dir}/.backboa.${_user}.*.include.ctrl.file"
      touch "${_include_ctrl_file}"
    fi

    # _exclude_file
    if [ ! -f "${_exclude_ctrl_file}" ]; then
      cat << EOF > "${_exclude_file}"
--exclude /data/disk/${_user}/.tmp
--exclude /data/disk/${_user}/clients
--exclude /data/disk/${_user}/static/restores
--exclude /data/disk/${_user}/static/tmp
--exclude /data/disk/${_user}/static/trash
--exclude /data/disk/${_user}/u
--exclude /data/disk/${_user}/undo
--exclude /home/${_user}.ftp/.tmp
--exclude /home/${_user}.ftp/backups
--exclude /home/${_user}.ftp/clients
--exclude /home/${_user}.ftp/platforms
--exclude /home/${_user}.ftp/static
EOF
      rm -f ${_user_config_dir}/.backboa.${_user}.*.exclude.ctrl.file
      touch "${_exclude_ctrl_file}"
    fi

    # Cleanup for empty or not used include config files
    if [ ! -f "${_user_control_dir}/include_regexp.txt" ]; then
      [ -e "${_include_regexp_file}" ] && rm -f "${_include_regexp_file}"
      [ -e "${_merged_regexp_include_file}" ] && rm -f "${_merged_regexp_include_file}"
    fi

    # Cleanup for empty or not used exclude config files
    if [ ! -f "${_user_control_dir}/exclude_regexp.txt" ]; then
      [ -e "${_exclude_regexp_file}" ] && rm -f "${_exclude_regexp_file}"
      [ -e "${_merged_regexp_exclude_file}" ] && rm -f "${_merged_regexp_exclude_file}"
    fi

    # Validate and merge system and user-space include files
    _validate_and_merge_paths "${_include_file}" "${_user}" "${_merged_include_file}" NO
    if [ -f "${_user_control_dir}/include.txt" ]; then
      _validate_and_merge_paths "${_user_control_dir}/include.txt" "${_user}" "${_merged_include_file}" YES
    fi

    # Validate and merge system and user-space exclude files
    _validate_and_merge_paths "${_exclude_file}" "${_user}" "${_merged_exclude_file}" NO
    if [ -f "${_user_control_dir}/exclude.txt" ]; then
      _validate_and_merge_paths "${_user_control_dir}/exclude.txt" "${_user}" "${_merged_exclude_file}" YES
    fi

    # Validate and merge regexp include files
    if [ -f "${_include_regexp_file}" ]; then
      _validate_and_merge_paths "${_include_regexp_file}" "${_user}" "${_merged_regexp_include_file}" NO
    fi
    if [ -f "${_user_control_dir}/include_regexp.txt" ]; then
      _validate_and_merge_paths "${_user_control_dir}/include_regexp.txt" "${_user}" "${_merged_regexp_include_file}" YES
    fi

    # Validate and merge regexp exclude files
    if [ -f "${_exclude_regexp_file}" ]; then
      _validate_and_merge_paths "${_exclude_regexp_file}" "${_user}" "${_merged_regexp_exclude_file}" NO
    fi
    if [ -f "${_user_control_dir}/exclude_regexp.txt" ]; then
      _validate_and_merge_paths "${_user_control_dir}/exclude_regexp.txt" "${_user}" "${_merged_regexp_exclude_file}" YES
    fi

    # Merge all include path directives into single file
    cat "${_merged_include_file}" > "${_merged_all_include_file}"
    cat "${_merged_regexp_include_file}" >> "${_merged_all_include_file}"

    # Merge all exclude path directives into single file
    cat "${_merged_exclude_file}" > "${_merged_all_exclude_file}"
    cat "${_merged_regexp_exclude_file}" >> "${_merged_all_exclude_file}"

    # Convert the include file contents to a single-line variable without extra backslashes and excessive whitespace
    local _MERGED_ALL_INCLUDE=$(cat "${_merged_all_include_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

    # Convert the exclude file contents to a single-line variable without extra backslashes and excessive whitespace
    local _MERGED_ALL_EXCLUDE=$(cat "${_merged_all_exclude_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

    # Create the final paths configuration file
    cat << EOF > "${_user_paths_file}"
_SOURCE=""
_USER_INCLUDE_PATHS="${_MERGED_ALL_INCLUDE}"
_USER_EXCLUDE_PATHS="${_MERGED_ALL_EXCLUDE}"
_INCLUDE_LIST="${_include_list}"
_EXCLUDE_LIST="${_exclude_list}"
EOF

    rm -f ${_user_config_dir}/.backboa*paths.ctrl.file
    touch ${_user_ctrl_file}
    echo "Paths configuration for '${_user}' created or updated at '${_user_paths_file}'."
  fi
}

# Generate paths configuration for each user
for _user_dir in /data/disk/*; do
  if [ -d "${_user_dir}" ]; then
    _user=$(basename "${_user_dir}")
    if [ "${_user}" != "arch" ] \
      && [ "${_user}" != "data" ] \
      && [ "${_user}" != "global" ] \
      && [ "${_user}" != "static" ] \
      && [ "${_user}" != "custom" ]; then
      _create_user_paths_config "${_user}"
      _generate_user_secret_file "${_user}"
    fi
  fi
done
