#!/bin/bash

# Function to create credentials files templates
create_credentials_templates() {
  local creds_dir=$1

  # Create directory if it doesn't exist
  mkdir -p "$creds_dir"

  # AWS S3
  cat << EOF > "$creds_dir/aws.txt"
export PASSPHRASE="your_backup_passphrase"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # AWS S3 Express One Zone
  cat << EOF > "$creds_dir/aws_one_zone.txt"
export PASSPHRASE="your_backup_passphrase"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # AWS S3 Standard-IA
  cat << EOF > "$creds_dir/aws_standard_ia.txt"
export PASSPHRASE="your_backup_passphrase"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # Google Cloud Storage
  cat << EOF > "$creds_dir/gcs.txt"
export PASSPHRASE="your_backup_passphrase"
export GOOGLE_APPLICATION_CREDENTIALS="your_google_application_credentials"
export PROJECT_ID="your_project_id"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # Backblaze B2
  cat << EOF > "$creds_dir/b2.txt"
export PASSPHRASE="your_backup_passphrase"
export B2_ACCOUNT_ID="your_b2_account_id"
export B2_APPLICATION_KEY="your_b2_application_key"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # Azure Blob Storage
  cat << EOF > "$creds_dir/azure.txt"
export PASSPHRASE="your_backup_passphrase"
export AZURE_STORAGE_ACCOUNT="your_azure_storage_account"
export AZURE_STORAGE_KEY="your_azure_storage_key"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # UpCloud Object Storage
  cat << EOF > "$creds_dir/upcloud.txt"
export PASSPHRASE="your_backup_passphrase"
export UPCLOUD_USERNAME="your_upcloud_username"
export UPCLOUD_PASSWORD="your_upcloud_password"
export REGION="your_upcloud_region"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # IBM Cloud Object Storage
  cat << EOF > "$creds_dir/ibm.txt"
export PASSPHRASE="your_backup_passphrase"
export IBM_API_KEY_ID="your_ibm_api_key_id"
export IBM_SERVICE_INSTANCE_ID="your_ibm_service_instance_id"
export IBM_REGION="your_ibm_region"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # Wasabi Hot Cloud Storage
  cat << EOF > "$creds_dir/wasabi.txt"
export PASSPHRASE="your_backup_passphrase"
export WASABI_ACCESS_KEY="your_wasabi_access_key"
export WASABI_SECRET_KEY="your_wasabi_secret_key"
export WASABI_REGION="your_wasabi_region"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # DigitalOcean Spaces
  cat << EOF > "$creds_dir/do_spaces.txt"
export PASSPHRASE="your_backup_passphrase"
export DO_SPACES_KEY="your_do_spaces_key"
export DO_SPACES_SECRET="your_do_spaces_secret"
export DO_SPACES_REGION="your_do_spaces_region"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF

  # Linode Object Storage by Akamai
  cat << EOF > "$creds_dir/linode.txt"
export PASSPHRASE="your_backup_passphrase"
export LINODE_ACCESS_KEY="your_linode_access_key"
export LINODE_SECRET_KEY="your_linode_secret_key"
export LINODE_REGION="your_linode_region"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF
}

# Create credentials templates for the global backup configuration
GLOBAL_CREDS_DIR="/var/xdrago/backup/credentials"
create_credentials_templates "$GLOBAL_CREDS_DIR"

# Create credentials templates for each user in /data/disk
for user_dir in /data/disk/*; do
  if [ -d "$user_dir" ]; then
    user_creds_dir="/data/disk/$(basename "$user_dir")/static/control/backups_credentials"
    create_credentials_templates "$user_creds_dir"
  fi
done
