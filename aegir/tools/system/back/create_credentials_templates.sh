#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Function to create credentials files templates
create_credentials_templates() {
  local creds_dir=$1

  # Create directory if it doesn't exist
  mkdir -p "$creds_dir"

  # AWS S3
  if [ ! -f "$creds_dir/aws.txt" ]; then
    cat << EOF > "$creds_dir/aws.txt"
export PASSPHRASE="your_backup_passphrase"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF
  fi

  # AWS S3 Express One Zone
  if [ ! -f "$creds_dir/aws_one_zone.txt" ]; then
    cat << EOF > "$creds_dir/aws_one_zone.txt"
export PASSPHRASE="your_backup_passphrase"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF
  fi

  # AWS S3 Standard-IA
  if [ ! -f "$creds_dir/aws_standard_ia.txt" ]; then
    cat << EOF > "$creds_dir/aws_standard_ia.txt"
export PASSPHRASE="your_backup_passphrase"
export AWS_ACCESS_KEY_ID="your_aws_access_key"
export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"
export AWS_REGION="your_aws_region"  # E.g., "us-east-1"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF
  fi

  # Google Cloud Storage
  if [ ! -f "$creds_dir/gcs.txt" ]; then
    cat << EOF > "$creds_dir/gcs.txt"
export PASSPHRASE="your_backup_passphrase"
export GOOGLE_APPLICATION_CREDENTIALS="your_google_application_credentials"
export PROJECT_ID="your_project_id"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF
  fi

  # Backblaze B2
  if [ ! -f "$creds_dir/b2.txt" ]; then
    cat << EOF > "$creds_dir/b2.txt"
export PASSPHRASE="your_backup_passphrase"
export B2_ACCOUNT_ID="your_b2_account_id"
export B2_APPLICATION_KEY="your_b2_application_key"
export KEEP_WITHIN="1M"  # Keep backups for 1 month
export FULL_BACKUP_FREQUENCY="1M"  # Full backup every 1 month
export KEEP_FULL_BACKUPS="2"  # Keep 2 full backups
EOF
  fi

  # Other services...
  # Repeat similar checks for other services (Azure, UpCloud, IBM, Wasabi, DigitalOcean Spaces, Linode) using the same pattern.

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
