#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Function to create or update a user's paths configuration file
_create_user_paths_config() {
  _user=$1
  _user_config_dir="/data/disk/${_user}/remote_backups"
  _user_control_dir="/data/disk/${_user}/static/control/remote_backups/config"
  _include_file="${_user_config_dir}/.backboa.${_user}.include"
  _exclude_file="${_user_config_dir}/.backboa.${_user}.exclude"
  _include_regexp_file="${_user_config_dir}/.backboa.${_user}.include_regexp"
  _exclude_regexp_file="${_user_config_dir}/.backboa.${_user}.exclude_regexp"
  _merged_include_file="${_user_config_dir}/.backboa.${_user}.include.merged"
  _merged_exclude_file="${_user_config_dir}/.backboa.${_user}.exclude.merged"
  _include_ctrl_file="${_user_config_dir}/.backboa.${_user}.f93.include.ctrl"
  _exclude_ctrl_file="${_user_config_dir}/.backboa.${_user}.f93.exclude.ctrl"

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
    echo "# No default include-regexp rules for ${_user}"
  fi

  if [ ! -f "${_exclude_regexp_file}" ]; then
    echo "# No default exclude-regexp rules for ${_user}"
  fi

  # Validate user-space config files (inside config/)
  _validate_user_config() {
    _file=$1
    _type=$2

    # Check for invalid entries in config files
    if [ "${_type}" = "regexp" ]; then
      _invalid_lines
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

      # Check for paths outside allowed directories
      _invalid_lines=$(grep -E "^--(include|exclude) " "${_file}" | grep -vE "^--(include|exclude) (/(data/disk/${_user}/static|/home/${_user}.ftp))" || true)
      if [ -n "${_invalid_lines}" ]; then
        echo "Error: Unauthorized paths in ${_file}:"
        echo "${_invalid_lines}"
        exit 1
      fi
    fi
  }

  # Merge system-level files if they exist
  [ -f "${_include_file}" ] && cat "${_include_file}" > "${_merged_include_file}"
  # Merge user-space files if they exist and are valid
  if [ -f "${_user_control_dir}/include.txt" ]; then
    _validate_user_config "${_user_control_dir}/include.txt"
    cat "${_user_control_dir}/include.txt" >> "${_merged_include_file}"
  fi

  # Merge system-level files if they exist
  [ -f "${_exclude_file}" ] && cat "${_exclude_file}" > "${_merged_exclude_file}"
  # Merge user-space files if they exist and are valid
  if [ -f "${_user_control_dir}/exclude.txt" ]; then
    _validate_user_config "${_user_control_dir}/exclude.txt"
    cat "${_user_control_dir}/exclude.txt" >> "${_merged_exclude_file}"
  fi

  # Merge system-level files if they exist
  [ -f "${_include_regexp_file}" ] && cat "${_include_regexp_file}" > "${_user_config_dir}/.backboa.${_user}.include_regexp.merged"
  if [ -f "${_user_control_dir}/include_regexp.txt" ]; then
    _validate_user_config "${_user_control_dir}/include_regexp.txt" "regexp"
    cat "${_user_control_dir}/include_regexp.txt" >> "${_user_config_dir}/.backboa.${_user}.include_regexp.merged"
  fi

  # Merge system-level files if they exist
  [ -f "${_exclude_regexp_file}" ] && cat "${_exclude_regexp_file}" > "${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged"
  if [ -f "${_user_control_dir}/exclude_regexp.txt" ]; then
    _validate_user_config "${_user_control_dir}/exclude_regexp.txt" "regexp"
    cat "${_user_control_dir}/exclude_regexp.txt" >> "${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged"
  fi

  # Create the final paths configuration file
  _user_config_file="${_user_config_dir}/paths.txt"
  cat << EOF > "${_user_config_file}"
_SOURCE="/data/disk/${_user}/static"
_INCLUDE="--include-filelist ${_merged_include_file} --include-regexp-filelist ${_user_config_dir}/.backboa.${_user}.include_regexp.merged"
_EXCLUDE="--exclude-filelist ${_merged_exclude_file} --exclude-regexp-filelist ${_user_config_dir}/.backboa.${_user}.exclude_regexp.merged"
EOF

  echo "Paths configuration for ${_user} created or updated at ${_user_config_file}"
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
