#!/bin/bash

# Set the interval in minutes between backups (default to 60 minutes)
BACKUP_INTERVAL=${1:-60}

# Function to check if a credentials file contains real values (no placeholders)
has_real_values() {
  local file=$1
  if grep -q -E 'your_|place_holder_value' "$file"; then
    return 1  # Contains placeholders
  else
    return 0  # Contains real values
  fi
}

# Function to create cron entries for a specific service
add_cron_entry() {
  local user=$1
  local service=$2
  local cron_file=$3
  local config_dir=$4

  case $service in
    aws)
      cred_file="$config_dir/aws.txt"
      ;;
    aws_one_zone)
      cred_file="$config_dir/aws_one_zone.txt"
      ;;
    aws_standard_ia)
      cred_file="$config_dir/aws_standard_ia.txt"
      ;;
    gcs)
      cred_file="$config_dir/gcs.txt"
      ;;
    b2)
      cred_file="$config_dir/b2.txt"
      ;;
    azure)
      cred_file="$config_dir/azure.txt"
      ;;
    upcloud)
      cred_file="$config_dir/upcloud.txt"
      ;;
    ibm)
      cred_file="$config_dir/ibm.txt"
      ;;
    wasabi)
      cred_file="$config_dir/wasabi.txt"
      ;;
    do_spaces)
      cred_file="$config_dir/do_spaces.txt"
      ;;
    linode)
      cred_file="$config_dir/linode.txt"
      ;;
    *)
      echo "Unknown service: $service"
      return
      ;;
  esac

  if has_real_values "$cred_file"; then
    echo "0 */$BACKUP_INTERVAL * * * root /path/to/duplicity_backup.sh backup $service $user $config_dir/paths.txt" >> $cron_file
  fi
}

# Create the cron entries
create_cron_entries() {
  CRON_FILE="/etc/cron.d/duplicity_backup"
  echo "# Cron jobs for duplicity backups" > $CRON_FILE

  # Check and add global backup cron entries
  GLOBAL_CRED_DIR="/var/xdrago/backup/credentials"
  GLOBAL_CONFIG_DIR="/var/xdrago/backup"

  for service in aws aws_one_zone aws_standard_ia gcs b2 azure upcloud ibm wasabi do_spaces linode; do
    add_cron_entry "global_user" "$service" "$CRON_FILE" "$GLOBAL_CONFIG_DIR"
  done

  # Add individual user backup cron entries
  for user_dir in /data/disk/*; do
    if [ -d "$user_dir" ]; then
      user=$(basename "$user_dir")
      USER_CRED_DIR="/data/disk/$user/static/control/backups_credentials"
      USER_CONFIG_DIR="/data/disk/$user/remote_backups"
      for service in aws aws_one_zone aws_standard_ia gcs b2 azure upcloud ibm wasabi do_spaces linode; do
        add_cron_entry "$user" "$service" "$CRON_FILE" "$USER_CONFIG_DIR"
      done
    fi
  done

  # Set permissions for the cron file
  chmod 644 "$CRON_FILE"

  echo "Cron entries created successfully in $CRON_FILE"
}

# Create the cron entries
create_cron_entries
