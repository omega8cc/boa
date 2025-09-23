#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _sPid="f62"

# Base directory for user configurations
_BASE_DIR="/data/disk"

# Function to ensure the config directory exists
_ensure_config_dir() {
  _user=$1
  _config_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/config"
  _dir_ctrl_file="${_BASE_DIR}/${_user}/log/.backboa.${_user}.${_sPid}.config.dir.ctrl"
  if [ ! -d "${_config_dir}" ] || [ ! -e "${_dir_ctrl_file}" ]; then
    mkdir -p "${_config_dir}"
    chown -R ${_user}.ftp:users "${_config_dir}"
    chmod 700 "${_config_dir}"
    touch "${_dir_ctrl_file}"
    echo "Created config directory for user: ${_user}"
  fi
}

# Function to create a README file in the config directory
_create_config_readme_file() {
  _user=$1
  _config_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/config"
  _readme_file="${_config_dir}/README.txt"
  _readme_ctrl_file="${_BASE_DIR}/${_user}/log/.backboa.${_user}.${_sPid}.config.readme.ctrl"
  _user_static_dir="/data/disk/${_user}/static"
  _user_ftp_dir="/home/${_user}.ftp"
  _user_ftp_dir_regex="/home/${_user}\.ftp"

  _ensure_config_dir "${_user}"

  if [ ! -f "${_readme_ctrl_file}" ]; then
    cat << EOF > "${_readme_file}"
Backup Configuration README

This directory contains configuration files for customizing backup behavior.
Users can define include and exclude directives for their backups.

Allowed paths for backups are restricted to:
- ${_user_static_dir}
- ${_user_ftp_dir}

Available Configuration Files:

1. include.txt
   Use this file to specify additional directories or files to include in the backup.

2. exclude.txt
   Use this file to specify directories or files to exclude from the backup.

3. include_regexp.txt
   Use this file to specify patterns for including directories or files using regular expressions.

4. exclude_regexp.txt
   Use this file to specify patterns for excluding directories or files using regular expressions.

Usage Instructions:

1. include.txt
   List full paths to the directories or files you want to include in the backup.
   Example:
   --include ${_user_static_dir}/documents
   --include ${_user_ftp_dir}/documents

2. exclude.txt
   List full paths to the directories or files you want to exclude from the backup.
   Example:
   --exclude ${_user_static_dir}/cache
   --exclude ${_user_ftp_dir}/temp

3. include_regexp.txt
   Use regular expressions to specify patterns for directories or files to include in the backup.
   Example:
   --include-regexp '^${_user_ftp_dir_regex}/documents/.*\.pdf$'
   --include-regexp '^${_user_static_dir}/project_data/.*'

4. exclude_regexp.txt
   Use regular expressions to specify patterns for directories or files to exclude from the backup.
   Example:
   --exclude-regexp '^${_user_static_dir}/trash/.*'
   --exclude-regexp '^${_user_ftp_dir_regex}/temp_files/.*'

Security:
- Ensure these files are restricted to the user only:
  - Files should have permissions set to 600 (chmod 600 <file>).
  - The directory should have permissions set to 700 (chmod 700 <directory>).

Notes:
- Directives in these files will be merged with default system directives during backup operations.
- Patterns defined in exclude_regexp.txt will take precedence over those in include_regexp.txt.
- You can only define paths in the /data/disk/${_user}/static/ directory tree.
- Paths for platforms without direct access in /data/disk/${_user}/distro are included by default.
- Invalid entries may cause the backup process to fail.

Example Configuration:

If you want to exclude temporary files:
- Add the following to exclude_regexp.txt:
  --exclude-regexp '^${_user_static_dir}/temp/.*'
  --exclude-regexp '^${_user_ftp_dir_regex}/temp/.*'

If you want to include specific documents:
- Add the following to include_regexp.txt:
  --include-regexp '^${_user_ftp_dir_regex}/documents/.*\.pdf$'
  --include-regexp '^${_user_static_dir}/important_data/.*'

EOF
    chmod 600 "${_readme_file}"
    chown ${_user}.ftp:users "${_readme_file}"
    echo "Created README file for config directory of user: ${_user}"
    touch "${_readme_ctrl_file}"
  else
    echo "README file already updated for config directory of user: ${_user}"
  fi
}

# Main function to create README files for all users
_main() {
  for _user_dir in "${_BASE_DIR}"/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      if [ "${_user}" != "arch" ] \
        && [ "${_user}" != "data" ] \
        && [ "${_user}" != "global" ] \
        && [ "${_user}" != "static" ] \
        && [ "${_user}" != "custom" ]; then
        _create_config_readme_file "${_user}"
      fi
    fi
  done
}

# Execute the script
_main
