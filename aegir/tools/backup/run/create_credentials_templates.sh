#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Global credentials directory
_GLOBAL_CREDENTIALS_DIR="/root/.remote_backups/credentials"

# Base directory for user-specific credentials
_USER_BASE_DIR="/data/disk"

# Function to ensure a directory exists
_ensure_directory() {
  _dir=$1
  if [ ! -d "${_dir}" ]; then
    mkdir -p "${_dir}"
    chmod 700 "${_dir}"
    echo "Created directory: ${_dir}"
  fi
}

# Function to create credentials template files
_create_credentials_templates() {
  _target_dir=$1

  # List of supported services
  _services=(
    "aws_one_zone"
    "aws_standard_ia"
    "aws"
    "azure"
    "b2"
    "cloudflare"
    "do_spaces"
    "gcs"
    "ibm"
    "linode"
    "wasabi"
  )

  for _service in "${_services[@]}"; do
    _template_file="${_target_dir}/${_service}.txt"

    if [ -e "${_user_pid_dir}" ] && [ ! -e "${_user_pid_dir}/.backboa.${_user}.credentials.${_service}.tpl.ctrl" ]; then
      sed -i "s/FULL_BACKUP_FREQUENCY=.*/FULL_BACKUP_FREQUENCY=\"28D\"/g" ${_template_file}
      touch ${_user_pid_dir}/.backboa.${_user}.credentials.${_service}.tpl.ctrl
    fi

    if [ ! -f "${_template_file}" ]; then
      case "${_service}" in
        aws|aws_one_zone|aws_standard_ia)
          cat << EOF > "${_template_file}"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        azure)
          cat << EOF > "${_template_file}"
export AZURE_STORAGE_ACCOUNT="your_azure_storage_account"
export AZURE_STORAGE_KEY="your_azure_storage_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        b2)
          cat << EOF > "${_template_file}"
export B2_ACCOUNT_ID="your_b2_account_id"
export B2_APPLICATION_KEY="your_b2_application_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        cloudflare)
          cat << EOF > "${_template_file}"
export R2_ACCOUNT_ID="your_account_id"
export R2_ACCESS_KEY_ID="your_access_key_id"
export R2_SECRET_ACCESS_KEY="your_secret_access_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        do_spaces)
          cat << EOF > "${_template_file}"
export DO_SPACES_KEY="your_do_spaces_key"
export DO_SPACES_SECRET="your_do_spaces_secret"
export DO_SPACES_REGION="your_do_spaces_region"  # E.g., "nyc3"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        gcs)
          cat << EOF > "${_template_file}"
export GCS_PROJECT_ID="your_gcs_project_id"
export GCS_SERVICE_ACCOUNT_KEY="your_gcs_service_account_key"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        ibm)
          cat << EOF > "${_template_file}"
export IBM_API_KEY_ID="your_ibm_api_key_id"
export IBM_SERVICE_INSTANCE_ID="your_ibm_service_instance_id"
export IBM_REGION="your_ibm_region"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        linode)
          cat << EOF > "${_template_file}"
export LINODE_ACCESS_KEY="your_linode_access_key"
export LINODE_SECRET_KEY="your_linode_secret_key"
export LINODE_REGION="your_linode_region"  # E.g., "us-east-1"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
        wasabi)
          cat << EOF > "${_template_file}"
export WASABI_ACCESS_KEY="your_wasabi_access_key"
export WASABI_SECRET_KEY="your_wasabi_secret_key"
export WASABI_REGION="your_wasabi_region"  # E.g., "us-east-1"
export KEEP_WITHIN="3M"
export FULL_BACKUP_FREQUENCY="28D"
EOF
          ;;
      esac
      chmod 600 "${_template_file}"
      echo "Created template for service: ${_service} at ${_template_file}"
    else
      echo "Template for service: ${_service} already exists at ${_template_file}"
    fi
  done
}

# Main function to create templates globally and for all users
_main() {
  # Create templates in the global credentials directory
  _ensure_directory "${_GLOBAL_CREDENTIALS_DIR}"
  _create_credentials_templates "${_GLOBAL_CREDENTIALS_DIR}"

  # Iterate over user directories and create templates for each user
  for _user_dir in "${_USER_BASE_DIR}"/*; do
    if [ -d "${_user_dir}" ]; then
      _user=$(basename "${_user_dir}")
      if [ "${_user}" != "arch" ] \
        && [ "${_user}" != "data" ] \
        && [ "${_user}" != "global" ] \
        && [ "${_user}" != "static" ] \
        && [ "${_user}" != "custom" ]; then
        _user_pid_dir="${_USER_BASE_DIR}/${_user}/log"
        _user_credentials_dir="${_USER_BASE_DIR}/${_user}/static/control/remote_backups/credentials"
        _ensure_directory "${_user_credentials_dir}"
        _create_credentials_templates "${_user_credentials_dir}"
      fi
    fi
  done
}

# Execute the script
_main
