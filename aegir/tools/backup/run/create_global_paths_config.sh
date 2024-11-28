#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Function to create or update global paths configuration
_create_global_paths_config() {
  _global_config_dir="/root/.remote_backups/paths"
  _include_file="${_global_config_dir}/.backboa.include"
  _exclude_file="${_global_config_dir}/.backboa.exclude"
  _include_regexp_file="${_global_config_dir}/.backboa.include_regexp"
  _exclude_regexp_file="${_global_config_dir}/.backboa.exclude_regexp"
  _merged_include_file="${_global_config_dir}/.backboa.include.merged"
  _merged_exclude_file="${_global_config_dir}/.backboa.exclude.merged"

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

  # Migrate legacy include/exclude files if present and merge unique entries
  if [ -f "/root/.backboa.include" ]; then
    if [ ! -f "${_include_file}" ]; then
      cp "/root/.backboa.include" "${_include_file}"
    else
      _append_unique_entries "/root/.backboa.include" "${_include_file}"
    fi
  fi

  if [ -f "/root/.backboa.exclude" ]; then
    if [ ! -f "${_exclude_file}" ]; then
      cp "/root/.backboa.exclude" "${_exclude_file}"
    else
      _append_unique_entries "/root/.backboa.exclude" "${_exclude_file}"
    fi
  fi

  # Create default include/exclude files if they don't exist
  if [ ! -f "${_include_file}" ]; then
    cat << EOF > "${_include_file}"
--include /root
EOF
  fi

  if [ ! -f "${_exclude_file}" ]; then
    cat << EOF > "${_exclude_file}"
--exclude /root/.cache
EOF
  fi

  if [ ! -f "${_include_regexp_file}" ]; then
    echo "# No default include-regexp rules for root"
  fi

  if [ ! -f "${_exclude_regexp_file}" ]; then
    echo "# No default exclude-regexp rules for root"
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

  # Validate and merge include/exclude files
  [ -e "${_include_file}" ] && _validate_config "${_include_file}"
  [ -e "${_exclude_file}" ] && _validate_config "${_exclude_file}"
  [ -e "${_include_regexp_file}" ] && _validate_config "${_include_regexp_file}" "regexp"
  [ -e "${_exclude_regexp_file}" ] && _validate_config "${_exclude_regexp_file}" "regexp"

  cat "${_include_file}" > "${_merged_include_file}"
  cat "${_exclude_file}" > "${_merged_exclude_file}"

  # Merge regexp files into final configurations
  if [ -s "${_include_regexp_file}" ]; then
    cat "${_include_regexp_file}" >> "${_merged_include_file}"
  fi
  if [ -s "${_exclude_regexp_file}" ]; then
    cat "${_exclude_regexp_file}" >> "${_merged_exclude_file}"
  fi

  # Create the final paths configuration file
  _global_paths_file="${_global_config_dir}/paths/paths.txt"
  cat << EOF > "${_global_paths_file}"
_SOURCE="/data /home /etc /var/aegir /var/www /var/solr7 /opt/solr4 /var/xdrago"
_INCLUDE="--include-filelist ${_merged_include_file}"
_EXCLUDE="--exclude-filelist ${_merged_exclude_file}"
EOF

  echo "Global paths configuration created or updated at ${_global_paths_file}"
}

#### Generate Passphrase and Store in .secret.txt per user
_generate_user_secret_file() {
  local _user_dir=$1
  local _secret_file="${_user_dir}/remote_backups/.secret.txt"

  if [ ! -f "${_secret_file}" ]; then
    mkdir -p "$(dirname "${_secret_file}")"
    openssl rand -base64 32 > "${_secret_file}"
    chmod 600 "${_secret_file}"
    chown "${USER}:${USER}" "${_secret_file}"
    chattr +i "${_secret_file}"
    echo "Secret file created at ${_secret_file} and made immutable."
  else
    echo "Secret file already exists at ${_secret_file}."
  fi
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
