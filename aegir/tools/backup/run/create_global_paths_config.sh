#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export _sPid="f80"

# Function to create or update global paths configuration
_create_global_paths_config() {
  _global_config_dir="/root/.remote_backups/paths"
  _include_list="${_global_config_dir}/.backboa.include.list"
  _exclude_list="${_global_config_dir}/.backboa.exclude.list"
  _custom_include_list="${_global_config_dir}/.backboa.custom_include.list"
  _custom_exclude_list="${_global_config_dir}/.backboa.custom_exclude.list"
  _include_global_file="${_global_config_dir}/.backboa.include_global.file"
  _include_data_file="${_global_config_dir}/.backboa.include_data.file"
  _exclude_global_file="${_global_config_dir}/.backboa.exclude.file"
  _include_global_regexp_file="${_global_config_dir}/.backboa.include_global_regexp.file"
  _exclude_data_regexp_file="${_global_config_dir}/.backboa.exclude_data_regexp.file"
  _merged_global_include_file="${_global_config_dir}/.backboa.global_include.merged.file"
  _merged_data_include_file="${_data_config_dir}/.backboa.data_include.merged.file"
  _merged_global_exclude_file="${_global_config_dir}/.backboa.global_exclude.merged.file"
  _merged_data_exclude_file="${_global_config_dir}/.backboa.data_exclude.merged.file"
  _global_ctrl_file="${_global_config_dir}/.backboa.${_sPid}.paths.ctrl.file"
  _global_paths_file="${_global_config_dir}/global_paths.txt"
  _data_paths_file="${_global_config_dir}/data_paths.txt"
  _custom_paths_file="${_global_config_dir}/custom_paths.txt"
  _disk_dir="/data/disk"

  # Ensure global configuration directory exists and is owned by root
  mkdir -p "${_global_config_dir}"
  chown root:root "${_global_config_dir}"
  chmod 700 "${_global_config_dir}"

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

  if [ ! -f "${_global_ctrl_file}" ]; then

    ### Migrate legacy include/exclude files if present and merge unique entries

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

    # _custom_include_list
    if [ -f "/root/.backboa.custom.include" ]; then
      if [ ! -f "${_custom_include_list}" ]; then
        cp "/root/.backboa.custom.include" "${_custom_include_list}"
      else
        _append_unique_entries "/root/.backboa.custom.include" "${_custom_include_list}"
      fi
    fi

    # _custom_exclude_list
    if [ -f "/root/.backboa.custom.exclude" ]; then
      if [ ! -f "${_custom_exclude_list}" ]; then
        cp "/root/.backboa.custom.exclude" "${_custom_exclude_list}"
      else
        _append_unique_entries "/root/.backboa.custom.exclude" "${_custom_exclude_list}"
      fi
    fi

    ### Create default include/exclude files if they don't exist

    # _include_global_file
    cat << EOF > "${_include_global_file}"
--include /data/disk/arch
--include /root
--include /var/backups/csf
--include /var/backups/dragon
--include /var/backups/reports
EOF

    # _exclude_global_file
    cat << EOF > "${_exclude_global_file}"
--exclude /data/disk
--exclude /root/.cache
--exclude /var/aegir/backups
EOF

    # _include_data_file
    # Start writing to the include data file
    cat << EOF > "${_include_data_file}"
EOF

    # Iterate over each item in the disk directory
    for subdir in "${_disk_dir}"/*/; do
      # Check if it's a directory
      if [ -d "${subdir}" ]; then
        # Remove the trailing slash for consistency
        sanitized_subdir="${subdir%/}"
        # Append the --include line to the include data file
        if [ "${sanitized_subdir}" != "arch" ]; then
          echo "--include ${sanitized_subdir}" >> "${_include_data_file}"
        fi
      fi
    done

    # Append the additional include statements
    cat << EOF >> "${_include_data_file}"
--include /data/all
--include /data/conf
--include /home
EOF

    # _include_global_regexp_file
    cat << EOF > "${_include_global_regexp_file}"
--include-regexp '^/var/backups/barracuda.*'
EOF

    # _exclude_data_regexp_file
    cat << EOF > "${_exclude_data_regexp_file}"
--exclude-regexp '^/data/disk/.*/backup-exports/'
--exclude-regexp '^/data/disk/.*/backups/'
--exclude-regexp '^/data/disk/.*/static/.tmp/'
--exclude-regexp '^/data/disk/.*/static/restores/'
--exclude-regexp '^/data/disk/.*/static/tmp/'
--exclude-regexp '^/data/disk/.*/static/trash/'
--exclude-regexp '^/data/disk/arch/.*'
--exclude-regexp '^/var/www/.*'
EOF

    # Validate and merge include/exclude files
    [ -e "${_include_data_file}" ] && _validate_config "${_include_data_file}"
    [ -e "${_include_global_file}" ] && _validate_config "${_include_global_file}"
    [ -e "${_exclude_global_file}" ] && _validate_config "${_exclude_global_file}"

    [ -e "${_include_data_file}" ] && cat "${_include_data_file}" > "${_merged_data_include_file}"
    [ -e "${_include_global_file}" ] && cat "${_include_global_file}" > "${_merged_global_include_file}"
    [ -e "${_exclude_global_file}" ] && cat "${_exclude_global_file}" > "${_merged_global_exclude_file}"

    # Merge regexp files into final configurations
    if [ -s "${_include_global_regexp_file}" ]; then
      _validate_config "${_include_global_regexp_file}" "regexp"
      cat "${_include_global_regexp_file}" >> "${_merged_global_include_file}"
    fi
    if [ -s "${_exclude_data_regexp_file}" ]; then
      _validate_config "${_exclude_data_regexp_file}" "regexp"
      cat "${_exclude_data_regexp_file}" > "${_merged_data_exclude_file}"
    fi

    # Finalize by adding a backslash at the end of each line except the last
    [ -e "${_merged_data_include_file}" ] && _add_backslashes "${_merged_data_include_file}"
    [ -e "${_merged_data_exclude_file}" ] && _add_backslashes "${_merged_data_exclude_file}"
    [ -e "${_merged_global_include_file}" ] && _add_backslashes "${_merged_global_include_file}"
    [ -e "${_merged_global_exclude_file}" ] && _add_backslashes "${_merged_global_exclude_file}"

    # Convert the exclude file contents to a single-line variable without backslashes and excessive whitespace
    [ -e "${_merged_data_include_file}" ] && _MERGED_DATA_INCLUDE=$(sed 's/\\//g' "${_merged_data_include_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    [ -e "${_merged_data_exclude_file}" ] && _MERGED_DATA_EXCLUDE=$(sed 's/\\//g' "${_merged_data_exclude_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    [ -e "${_merged_global_include_file}" ] && _MERGED_GLOBAL_INCLUDE=$(sed 's/\\//g' "${_merged_global_include_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    [ -e "${_merged_global_exclude_file}" ] && _MERGED_GLOBAL_EXCLUDE=$(sed 's/\\//g' "${_merged_global_exclude_file}" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')

    # Create the final paths configuration file
    cat << EOF > "${_global_paths_file}"
_SOURCE="/etc /opt/solr4 /var/aegir /var/solr7 /var/www /var/xdrago"
_INCLUDE_PATHS="${_MERGED_GLOBAL_INCLUDE}"
_EXCLUDE_PATHS="${_MERGED_GLOBAL_EXCLUDE}"
_INCLUDE_LIST="${_include_list}"
_EXCLUDE_LIST="${_exclude_list}"
EOF

    echo "Global paths configuration created or updated at ${_global_paths_file}"

    # Create the final paths configuration file
    cat << EOF > "${_data_paths_file}"
_SOURCE=""
_INCLUDE_PATHS="${_MERGED_DATA_INCLUDE}"
_EXCLUDE_PATHS="${_MERGED_DATA_EXCLUDE}"
_INCLUDE_LIST="${_include_list}"
_EXCLUDE_LIST="${_exclude_list}"
EOF

    echo "Global paths configuration created or updated at ${_data_paths_file}"

    [ -s "${_custom_include_list}" ] && cat << EOF > "${_custom_paths_file}"
_SOURCE=""
_INCLUDE_PATHS=""
_EXCLUDE_PATHS=""
_INCLUDE_LIST="${_custom_include_list}"
EOF

    [ -s "${_custom_exclude_list}" ] && cat << EOF >> "${_custom_paths_file}"
_EXCLUDE_LIST="${_custom_exclude_list}"
EOF

    [ -s "${_custom_paths_file}" ] && echo "Global paths configuration created or updated at ${_custom_paths_file}"

    rm -f ${_global_config_dir}/.backboa*paths.ctrl.file
    touch ${_global_ctrl_file}
  fi
}

#### Generate Passphrase for Root
_generate_global_secret_file() {
  local _secret_file="/root/.remote_backups/.secret.txt"

  if [ ! -s "${_secret_file}" ]; then
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
