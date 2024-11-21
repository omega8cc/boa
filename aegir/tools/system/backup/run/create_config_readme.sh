#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Base directory for user configurations
_BASE_DIR="/data/disk"

# Function to ensure the config directory exists
_ensure_config_dir() {
  local _user=$1
  local _config_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/config"
  if [ ! -d "${_config_dir}" ]; then
    mkdir -p "${_config_dir}"
    chown -R ${_user}.ftp:users "${_config_dir}"
    chmod 700 "${_config_dir}"
    echo "Created config directory for user: ${_user}"
  fi
}

# Function to create a README file in the config directory
_create_config_readme_file() {
  local _user=$1
  local _config_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/config"
  local _readme_file="${_config_dir}/README.txt"

  _ensure_config_dir "${_user}"

  if [ ! -f "${_readme_file}" ]; then
    cat << EOF > "${_readme_file}"
Backup Configuration README

This directory contains configuration files for customizing backup behavior.
Users can define include and exclude directives for their backups.

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
   --include /path/to/important_directory
   --include /path/to/another_file

2. exclude.txt
   List full paths to the directories or files you want to exclude from the backup.
   Example:
   --exclude /path/to/cache
   --exclude /path/to/temp

3. include_regexp.txt
   Use regular expressions to specify patterns for directories or files to include in the backup.
   Example:
   --include-regexp '^/data/disk/.*/important_files/'
   --include-regexp '^/home/.*/documents/.*\.pdf$'

4. exclude_regexp.txt
   Use regular expressions to specify patterns for directories or files to exclude from the backup.
   Example:
   --exclude-regexp '^/data/disk/.*/cache/'
   --exclude-regexp '^.*\.tmp$'

Security:
- Ensure these files are restricted to the user only:
  - Files should have permissions set to 600 (chmod 600 <file>).
  - The directory should have permissions set to 700 (chmod 700 <directory>).

Notes:
- Directives in these files will be merged with default system directives during backup operations.
- Patterns defined in exclude_regexp.txt will take precedence over those in include_regexp.txt.
- Invalid entries may cause the backup process to fail.

Example:
If you want to exclude temporary files and include specific PDF documents:
- Add the following to exclude_regexp.txt:
  --exclude-regexp '^.*\.tmp$'
- Add the following to include_regexp.txt:
  --include-regexp '^/home/.*/documents/.*\.pdf$'
EOF
    chmod 600 "${_readme_file}"
    chown ${_user}.ftp:users "${_readme_file}"
    echo "Created README file for config directory of user: ${_user}"
  else
    echo "README file already exists for config directory of user: ${_user}"
  fi
}

# Main function to create README files for all users
_main() {
  for _user_dir in "${_BASE_DIR}"/*; do
    if [ -d "${_user_dir}" ]; then
      local _user
      _user=$(basename "${_user_dir}")
      _create_config_readme_file "${_user}"
    fi
  done
}

# Execute the script
_main
