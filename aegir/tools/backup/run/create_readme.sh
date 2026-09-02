#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _sPid="f61"

_acct_group() {
  # Group that owns an account's tree. Derived, never a literal: an account
  # converted to a private primary group named after itself gets that group,
  # everything else (an unconverted box, root, www-data, an adopted odd
  # group) falls back to 'users' -- so a tool landing on an unconverted or
  # half-converted box leaves it exactly as it is today. Box-wide paths
  # (/data/conf, /data/u, the shared cores) keep 'users' and never use this.
  # $1 = account name (oN, oN.ftp, oN.<sub>) or a path under /data/disk/<oN>
  # or /var/aegir (the master keeps 'users' in this phase).
  local _a="${1}" _g
  case "${_a}" in
    /var/aegir|/var/aegir/*|aegir|root|www-data) echo "users"; return 0 ;;
    /data/disk/*) _a="${_a#/data/disk/}"; _a="${_a%%/*}" ;;
    */*) echo "users"; return 0 ;;
  esac
  _a="${_a%%.*}"
  [ -n "${_a}" ] || { echo "users"; return 0; }
  _g=$(id -gn "${_a}" 2> /dev/null)
  [ "${_g}" = "${_a}" ] || _g="users"
  echo "${_g}"
}

# Directory for storing README files
_BASE_DIR="/data/disk"

# Function to ensure the README directory exists
_ensure_readme_dir() {
  _user=$1
  _grp=$(_acct_group "${_user}")
  _credentials_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/credentials"
  _dir_ctrl_file="${_BASE_DIR}/${_user}/log/.backboa.${_user}.${_sPid}.credentials.dir.ctrl"
  if [ ! -d "${_credentials_dir}" ] || [ ! -e "${_dir_ctrl_file}" ]; then
    mkdir -p "${_credentials_dir}"
    chown -R ${_user}.ftp:${_grp} "${_credentials_dir}"
    chmod 700 "${_credentials_dir}"
    touch "${_dir_ctrl_file}"
    echo "Created credentials directory for user: ${_user}"
  fi
}

# Function to create a README file for a specific user
_create_readme_file() {
  _user=$1
  _grp=$(_acct_group "${_user}")
  _credentials_dir="${_BASE_DIR}/${_user}/static/control/remote_backups/credentials"
  _readme_file="${_credentials_dir}/README.txt"
  _readme_ctrl_file="${_BASE_DIR}/${_user}/log/.backboa.${_user}.${_sPid}.credentials.readme.ctrl"

  _ensure_readme_dir "${_user}"

  if [ ! -f "${_readme_ctrl_file}" ]; then
    cat << EOF > "${_readme_file}"
# Backup Credentials README

This directory contains credentials files for the backup services supported by the system.
Each file corresponds to a specific backup service and must follow the correct format.

## Supported Services and Corresponding Files:
Amazon S3 (Standard, One Zone, Standard-IA)
  File: aws.txt
  export AWS_ACCESS_KEY_ID="your_aws_access_key"
  export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
  export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
  export KEEP_WITHIN="3M"              # Retain backups from the last 3 months
  export FULL_BACKUP_FREQUENCY="28D"   # Create a full backup every 28 days

Google Cloud Storage
  File: gcs.txt
  export GCS_ACCESS_KEY_ID="your_gcs_hmac_access_key"
  export GCS_SECRET_ACCESS_KEY="your_gcs_hmac_secret"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"
  Note: create an HMAC key pair for a service account with Storage Admin
  access (Cloud Storage -> Settings -> Interoperability); backups use the
  S3-compatible XML API endpoint storage.googleapis.com

Backblaze B2
  File: b2.txt
  export B2_ACCOUNT_ID="your_b2_account_id"
  export B2_APPLICATION_KEY="your_b2_application_key"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

Cloudflare R2 Object Storage
  File: cloudflare.txt
  export R2_ACCOUNT_ID="your_account_id"
  export R2_ACCESS_KEY_ID="your_access_key_id"
  export R2_SECRET_ACCESS_KEY="your_secret_access_key"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

Azure Blob Storage
  File: azure.txt
  export AZURE_STORAGE_ACCOUNT="your_azure_storage_account"
  export AZURE_STORAGE_KEY="your_azure_storage_key"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

IBM Cloud Object Storage
  File: ibm.txt
  export IBM_ACCESS_KEY_ID="your_ibm_hmac_access_key_id"
  export IBM_SECRET_ACCESS_KEY="your_ibm_hmac_secret_access_key"
  export IBM_REGION="your_ibm_region"  # E.g., "eu-de"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"
  Note: create the service credential with HMAC enabled (Include HMAC
  Credential); backups use the S3-compatible endpoint
  s3.<region>.cloud-object-storage.appdomain.cloud

Wasabi Hot Cloud Storage
  File: wasabi.txt
  export WASABI_ACCESS_KEY="your_wasabi_access_key"
  export WASABI_SECRET_KEY="your_wasabi_secret_key"
  export WASABI_REGION="your_wasabi_region"  # E.g., "us-east-1"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

DigitalOcean Spaces
  File: do_spaces.txt
  export DO_SPACES_KEY="your_do_spaces_key"
  export DO_SPACES_SECRET="your_do_spaces_secret"
  export DO_SPACES_REGION="your_do_spaces_region"  # E.g., "nyc3"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

Linode Object Storage by Akamai
  File: linode.txt
  export LINODE_ACCESS_KEY="your_linode_access_key"
  export LINODE_SECRET_KEY="your_linode_secret_key"
  export LINODE_REGION="your_linode_region"  # E.g., "us-east-1"
  export KEEP_WITHIN="3M"
  export FULL_BACKUP_FREQUENCY="28D"

## Security
- Ensure credentials files are securely managed:
  - Files should have permissions set to 600 (\`chmod 600 <file>\`).
  - The credentials directory should have permissions set to 700 (\`chmod 700 <directory>\`).

## Notes
- The backup process will fail if the credentials file for a required service is missing or contains invalid placeholders.
- Users are responsible for managing these credentials files securely.

EOF
    chmod 600 "${_readme_file}"
    chown ${_user}.ftp:${_grp} "${_readme_file}"
    echo "Created README file for user: ${_user}"
    touch "${_readme_ctrl_file}"
  else
    echo "README file already updated for user: ${_user}"
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
        _create_readme_file "${_user}"
      fi
    fi
  done
}

# Execute the script
_main
