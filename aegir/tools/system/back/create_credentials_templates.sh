#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Directory for storing global credentials templates
_GLOBAL_CREDENTIALS_DIR="/var/xdrago/backup/credentials"

# Function to ensure the credentials directory exists
_create_credentials_dir() {
  if [ ! -d "${_GLOBAL_CREDENTIALS_DIR}" ]; then
    mkdir -p "${_GLOBAL_CREDENTIALS_DIR}"
    chmod 700 "${_GLOBAL_CREDENTIALS_DIR}"
    echo "Created global credentials directory: ${_GLOBAL_CREDENTIALS_DIR}"
  fi
}

# Function to create a credentials template
_create_credentials_template() {
  local _service=$1
  local _template_file="${_GLOBAL_CREDENTIALS_DIR}/${_service}.txt"

  if [ ! -f "${_template_file}" ]; then
    case "${_service}" in
      aws)
        cat << EOF > "${_template_file}"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF
        ;;
      aws_one_zone)
        cat << EOF > "${_template_file}"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      aws_standard_ia)
        cat << EOF > "${_template_file}"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      gcs)
        cat << EOF > "${_template_file}"
export GCS_PROJECT_ID="your_gcs_project_id"
export GCS_SERVICE_ACCOUNT_KEY="your_gcs_service_account_key"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      b2)
        cat << EOF > "${_template_file}"
export B2_ACCOUNT_ID="your_b2_account_id"
export B2_APPLICATION_KEY="your_b2_application_key"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      azure)
        cat << EOF > "${_template_file}"
export AZURE_STORAGE_ACCOUNT="your_azure_storage_account"
export AZURE_STORAGE_KEY="your_azure_storage_key"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      upcloud)
        cat << EOF > "${_template_file}"
export UPCLOUD_USERNAME="your_upcloud_username"
export UPCLOUD_PASSWORD="your_upcloud_password"
export REGION="your_upcloud_region"  # E.g., "fi-hel1"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      ibm)
        cat << EOF > "${_template_file}"
export IBM_API_KEY_ID="your_ibm_api_key_id"
export IBM_SERVICE_INSTANCE_ID="your_ibm_service_instance_id"
export IBM_REGION="your_ibm_region"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      wasabi)
        cat << EOF > "${_template_file}"
export WASABI_ACCESS_KEY="your_wasabi_access_key"
export WASABI_SECRET_KEY="your_wasabi_secret_key"
export WASABI_REGION="your_wasabi_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      do_spaces)
        cat << EOF > "${_template_file}"
export DO_SPACES_KEY="your_do_spaces_key"
export DO_SPACES_SECRET="your_do_spaces_secret"
export DO_SPACES_REGION="your_do_spaces_region"  # E.g., "nyc3"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      linode)
        cat << EOF > "${_template_file}"
export LINODE_ACCESS_KEY="your_linode_access_key"
export LINODE_SECRET_KEY="your_linode_secret_key"
export LINODE_REGION="your_linode_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"
export FULL_BACKUP_FREQUENCY="1M"
export KEEP_FULL_BACKUPS="2"
EOF
        ;;
      *)
        echo "Warning: No template available for service ${_service}."
        ;;
    esac
    chmod 600 "${_template_file}"
    echo "Created credentials template for service: ${_service}."
  else
    echo "Credentials template for service ${_service} already exists."
  fi
}

# Main function to create templates for all supported services
_main() {
  _create_credentials_dir

  local _services=(
    aws
    aws_one_zone
    aws_standard_ia
    gcs
    b2
    azure
    upcloud
    ibm
    wasabi
    do_spaces
    linode
  )

  for _service in "${_services[@]}"; do
    _create_credentials_template "${_service}"
  done
}

# Execute the script
_main
