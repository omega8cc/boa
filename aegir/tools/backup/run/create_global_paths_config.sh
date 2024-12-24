#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export _sPid="f86"

# Function to create or update global paths configuration
_create_global_paths_config() {
  _global_config_dir="/root/.remote_backups/paths"
  _exclude_list="${_global_config_dir}/.backboa.exclude.list"
  _include_list="${_global_config_dir}/.backboa.include.list"
  _exclude_file="${_global_config_dir}/.backboa.exclude.file"
  _include_file="${_global_config_dir}/.backboa.include.file"
  _exclude_regexp_file="${_global_config_dir}/.backboa.exclude_regexp.file"
  _include_regexp_file="${_global_config_dir}/.backboa.include_regexp.file"
  _merged_exclude_file="${_global_config_dir}/.backboa.exclude.merged.file"
  _merged_include_file="${_global_config_dir}/.backboa.include.merged.file"
  _global_ctrl_file="${_global_config_dir}/.backboa.${_sPid}.paths.ctrl.file"
  _global_paths_file="${_global_config_dir}/paths.txt"

  # Ensure global configuration directory exists and is owned by root
  mkdir -p "${_global_config_dir}"
  chown root:root "${_global_config_dir}"
  chmod 700 "${_global_config_dir}"

  # Function to append unique entries from source to target file
  _append_unique_entries() {
    _source_file=$1
    _target_file=$2
    if [ -f "${_source_file}" ]; then
      grep -v -F -x -f "${_target_file}" "${_source_file}" >> "${_target_file}"
    fi
  }

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

  # Migrate legacy exclude/include files if present and merge unique entries
  if [ -f "/root/.backboa.exclude" ]; then
    if [ ! -f "${_exclude_list}" ]; then
      cp "/root/.backboa.exclude" "${_exclude_list}"
    else
      _append_unique_entries "/root/.backboa.exclude" "${_exclude_list}"
    fi
  fi

  if [ -f "/root/.backboa.include" ]; then
    if [ ! -f "${_include_list}" ]; then
      cp "/root/.backboa.include" "${_include_list}"
    else
      _append_unique_entries "/root/.backboa.include" "${_include_list}"
    fi
  fi

  if [ ! -f "${_global_ctrl_file}" ]; then
    cat << EOF > "${_exclude_file}"
--exclude /root/.cache
EOF
  fi

  # Create default exclude/include files if they don't exist
  if [ ! -f "${_global_ctrl_file}" ]; then
    cat << EOF > "${_include_file}"
--include /root
--include /var/backups/csf
--include /var/backups/dragon
--include /var/backups/reports
EOF
  fi

  if [ ! -f "${_global_ctrl_file}" ]; then
    cat << EOF > "${_exclude_regexp_file}"
--exclude-regexp '^/data/disk/.*/backup-exports/'
--exclude-regexp '^/data/disk/.*/backups/'
--exclude-regexp '^/data/disk/.*/static/restores/'
--exclude-regexp '^/data/disk/.*/static/trash/'
--exclude-regexp '^/data/disk/.*/static/tmp/'
--exclude-regexp '^/data/disk/.*/static/.tmp/'
EOF
  fi

  if [ ! -f "${_global_ctrl_file}" ]; then
    cat << EOF > "${_include_regexp_file}"
--include-regexp '^/var/backups/barracuda.*'
EOF
  fi

  # Function to validate configuration files
  _validate_config() {
    _file=$1
    _type=$2

    # Check for invalid entries
    if [ "${_type}" = "regexp" ]; then
      _invalid_lines=$(grep -Ev "^--(include-regexp|exclude-regexp)" "${_file}" || true)
      if [ -n "${_invalid_lines}" ]; then
        echo "Error: Invalid entries in ${_file}:"
        echo "${_invalid_lines}"
        exit 1
      fi
    else
      _invalid_lines=$(grep -Ev "^--(include|exclude)" "${_file}" || true)
      if [ -n "${_invalid_lines}" ]; then
        echo "Error: Invalid entries in ${_file}:"
        echo "${_invalid_lines}"
        exit 1
      fi
    fi
  }

  # Validate and merge exclude/include files
  [ -e "${_exclude_file}" ] && _validate_config "${_exclude_file}"
  [ -e "${_include_file}" ] && _validate_config "${_include_file}"
  [ -e "${_exclude_regexp_file}" ] && _validate_config "${_exclude_regexp_file}" "regexp"
  [ -e "${_include_regexp_file}" ] && _validate_config "${_include_regexp_file}" "regexp"

  cat "${_exclude_file}" > "${_merged_exclude_file}"
  cat "${_include_file}" > "${_merged_include_file}"

  # Merge regexp files into final configurations
  if [ -s "${_exclude_regexp_file}" ]; then
    cat "${_exclude_regexp_file}" >> "${_merged_exclude_file}"
  fi
  if [ -s "${_include_regexp_file}" ]; then
    cat "${_include_regexp_file}" >> "${_merged_include_file}"
  fi

  # Finalize by adding a backslash at the end of each line except the last
  _add_backslashes "${_merged_exclude_file}"
  _add_backslashes "${_merged_include_file}"

  # Convert the exclude file contents to a single-line variable without backslashes and excessive whitespace
  _MERGED_ALL_EXCLUDE=$(sed 's/\\//g' "${_merged_exclude_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

  # Convert the include file contents to a single-line variable without backslashes and excessive whitespace
  _MERGED_ALL_INCLUDE=$(sed 's/\\//g' "${_merged_include_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

  # Create the final paths configuration file
  cat << EOF > "${_global_paths_file}"
_SOURCE="/data /etc /home /opt/solr4 /var/aegir /var/solr7 /var/www /var/xdrago"
_EXCLUDE_PATHS="${_MERGED_ALL_EXCLUDE}"
_INCLUDE_PATHS="${_MERGED_ALL_INCLUDE}"
_EXCLUDE_LIST="${_exclude_list}"
_INCLUDE_LIST="${_include_list}"
EOF

  echo "Global paths configuration created or updated at ${_global_paths_file}"
}

#### Generate Passphrase for Root
_generate_global_secret_file() {
  local _secret_file="/root/.remote_backups/.secret.txt"

  if [ ! -f "${_secret_file}" ]; then
    openssl rand -base64 32 > "${_secret_file}"
    chmod 600 "${_secret_file}"
    chattr +i "${_secret_file}"
    echo "Global secret file created at ${_secret_file} and made immutable."
  else
    echo "Global secret file already exists at ${_secret_file}."
  fi
}

# Main execution
_create_global_paths_config
_generate_global_secret_file

exit 0
