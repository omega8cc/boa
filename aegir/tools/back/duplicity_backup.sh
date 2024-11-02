#!/bin/bash

# Ensure using the correct Python version
PYTHON_BIN="python3.12"

# Function to create PID file
create_pid_file() {
  local pidfile=$1
  if [ -e "$pidfile" ]; then
    echo "Process already running with PID file $pidfile"
    exit 1
  else
    echo $$ > "$pidfile"
  fi
}

# Function to remove PID file
remove_pid_file() {
  local pidfile=$1
  rm -f "$pidfile"
}

# Function to load credentials from a file
load_credentials() {
  local service=$1
  local user=$2
  local creds_path="/data/disk/$user/static/control/backups_credentials/$service.txt"
  if [ -f "$creds_path" ]; then
    source "$creds_path"
  else
    echo "Credentials file $creds_path not found."
    exit 1
  fi
}

# Function to load paths and other settings from a file
load_paths() {
  local user=$1
  local paths_path="/data/disk/$user/remote_backups/paths.txt"
  if [ -f "$paths_path" ]; then
    source "$paths_path"
  else
    echo "Paths configuration file $paths_path not found."
    exit 1
  fi
}

# Function to construct BUCKET_NAME
construct_bucket_name() {
  local service_abbr=$1
  local user=$2
  local hostname=$(hostname -s)
  BUCKET_NAME="${hostname}-${service_abbr}-${user}"
}

# Function to perform backup
backup() {
  $PYTHON_BIN -m duplicity \
    --full-if-older-than $FULL_BACKUP_FREQUENCY \
    --volsize 50 \
    --allow-source-mismatch \
    --asynchronous-upload \
    ${EXCLUDE} \
    ${USER_EXCLUDE} \
    ${INCLUDE} \
    ${USER_INCLUDE} \
    --exclude '**' \
    ${SOURCE} \
    $BACKUP_TARGET
}

# Function to clean up old backups
cleanup() {
  $PYTHON_BIN -m duplicity remove-older-than $KEEP_WITHIN --force $BACKUP_TARGET
  $PYTHON_BIN -m duplicity remove-all-but-n-full $KEEP_FULL_BACKUPS --force $BACKUP_TARGET
}

# Function to restore backup
restore() {
  local restore_target=$1
  local restore_path=$2
  local restore_time=$3
  restore_command="$PYTHON_BIN -m duplicity restore --allow-source-mismatch"

  if [ -n "$restore_time" ]; then
    restore_command="$restore_command --time $restore_time"
  fi

  restore_command="$restore_command $BACKUP_TARGET"

  if [ -n "$restore_path" ]; then
    restore_command="$restore_command $restore_path"
  fi

  restore_command="$restore_command $restore_target"

  eval $restore_command
}

# Function to set AWS S3 as backup target
set_aws_s3_target() {
  local user=$1
  load_credentials "aws" $user
  construct_bucket_name "aws" $user
  BACKUP_TARGET="s3://${AWS_REGION}.amazonaws.com/$BUCKET_NAME"
}

# Function to set AWS S3 Express One Zone as backup target
set_aws_s3_one_zone_target() {
  local user=$1
  load_credentials "aws_one_zone" $user
  construct_bucket_name "aws_one_zone" $user
  BACKUP_TARGET="s3://${AWS_REGION}.amazonaws.com/$BUCKET_NAME"
}

# Function to set AWS S3 Standard-IA as backup target
set_aws_s3_standard_ia_target() {
  local user=$1
  load_credentials "aws_standard_ia" $user
  construct_bucket_name "aws_standard_ia" $user
  BACKUP_TARGET="s3://${AWS_REGION}.amazonaws.com/$BUCKET_NAME"
}

# Function to set Google Cloud Storage as backup target
set_gcs_target() {
  local user=$1
  load_credentials "gcs" $user
  construct_bucket_name "gcs" $user
  BACKUP_TARGET="gs://$BUCKET_NAME"
}

# Function to set Backblaze B2 as backup target
set_b2_target() {
  local user=$1
  load_credentials "b2" $user
  construct_bucket_name "b2" $user
  BACKUP_TARGET="b2://$B2_ACCOUNT_ID:$B2_APPLICATION_KEY@$BUCKET_NAME"
}

# Function to set Azure Blob Storage as backup target
set_azure_target() {
  local user=$1
  load_credentials "azure" $user
  construct_bucket_name "azure" $user
  BACKUP_TARGET="azure://$AZURE_STORAGE_ACCOUNT@$BUCKET_NAME"
}

# Function to set UpCloud Object Storage as backup target
set_upcloud_target() {
  local user=$1
  load_credentials "upcloud" $user
  construct_bucket_name "upcloud" $user
  BACKUP_TARGET="s3://$UPCLOUD_USERNAME:$UPCLOUD_PASSWORD@$REGION/$BUCKET_NAME"
}

# Function to set IBM Cloud Object Storage as backup target
set_ibm_target() {
  local user=$1
  load_credentials "ibm" $user
  construct_bucket_name "ibm" $user
  BACKUP_TARGET="ibmcos://$IBM_API_KEY_ID:$IBM_SERVICE_INSTANCE_ID@$IBM_REGION/$BUCKET_NAME"
}

# Function to set Wasabi Hot Cloud Storage as backup target
set_wasabi_target() {
  local user=$1
  load_credentials "wasabi" $user
  construct_bucket_name "wasabi" $user
  BACKUP_TARGET="s3://$WASABI_ACCESS_KEY:$WASABI_SECRET_KEY@$WASABI_REGION/$BUCKET_NAME"
}

# Function to set DigitalOcean Spaces as backup target
set_do_spaces_target() {
  local user=$1
  load_credentials "do_spaces" $user
  construct_bucket_name "do_spaces" $user
  BACKUP_TARGET="s3://$DO_SPACES_KEY:$DO_SPACES_SECRET@$DO_SPACES_REGION/$BUCKET_NAME"
}

# Function to set Linode Object Storage by Akamai as backup target
set_linode_target() {
  local user=$1
  load_credentials "linode" $user
  construct_bucket_name "linode" $user
  BACKUP_TARGET="s3://$LINODE_ACCESS_KEY:$LINODE_SECRET_KEY@$LINODE_REGION/$BUCKET_NAME"
}

# Main script
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 {backup|cleanup|restore} {aws|aws_one_zone|aws_standard_ia|gcs|b2|azure|upcloud|ibm|wasabi|do_spaces|linode} USER [RESTORE_TARGET] [RESTORE_PATH] [RESTORE_TIME]"
  exit 1
fi

ACTION=$1
SERVICE=$2
USER=$3
RESTORE_TARGET="${4:-/data/disk/$USER/static/backups/}"
RESTORE_PATH="${5:-}"
RESTORE_TIME="${6:-}"
PIDFILE="/var/run/duplicity_${SERVICE}_${USER}.pid"

create_pid_file "$PIDFILE"

# Load paths configuration
load_paths $USER

case $ACTION in
  backup)
    case $SERVICE in
      aws)
        set_aws_s3_target $USER
        ;;
      aws_one_zone)
        set_aws_s3_one_zone_target $USER
        ;;
      aws_standard_ia)
        set_aws_s3_standard_ia_target $USER
        ;;
      gcs)
        set_gcs_target $USER
        ;;
      b2)
        set_b2_target $USER
        ;;
      azure)
        set_azure_target $USER
        ;;
      upcloud)
        set_upcloud_target $USER
        ;;
      ibm)
        set_ibm_target $USER
        ;;
      wasabi)
        set_wasabi_target $USER
        ;;
      do_spaces)
        set_do_spaces_target $USER
        ;;
      linode)
        set_linode_target $USER
        ;;
      *)
        echo "Usage: $0 backup {aws|aws_one_zone|aws_standard_ia|gcs|b2|azure|upcloud|ibm|wasabi|do_spaces|linode} USER"
        remove_pid_file "$PIDFILE"
        exit 1
        ;;
    esac
    backup
    ;;
  cleanup)
    case $SERVICE in
      aws)
        set_aws_s3_target $USER
        ;;
      aws_one_zone)
        set_aws_s3_one_zone_target $USER
        ;;
      aws_standard_ia)
        set_aws_s3_standard_ia_target $USER
        ;;
      gcs)
        set_gcs_target $USER
        ;;
      b2)
        set_b2_target $USER
        ;;
      azure)
        set_azure_target $USER
        ;;
      upcloud)
        set_upcloud_target $USER
        ;;
      ibm)
        set_ibm_target $USER
        ;;
      wasabi)
        set_wasabi_target $USER
        ;;
      do_spaces)
        set_do_spaces_target $USER
        ;;
      linode)
        set_linode_target $USER
        ;;
      *)
        echo "Usage: $0 cleanup {aws|aws_one_zone|aws_standard_ia|gcs|b2|azure|upcloud|ibm|wasabi|do_spaces|linode} USER"
        remove_pid_file "$PIDFILE"
        exit 1
        ;;
    esac
    cleanup
    ;;
  restore)
    case $SERVICE in
      aws)
        set_aws_s3_target $USER
        ;;
      aws_one_zone)
        set_aws_s3_one_zone_target $USER
        ;;
      aws_standard_ia)
        set_aws_s3_standard_ia_target $USER
        ;;
      gcs)
        set_gcs_target $USER
        ;;
      b2)
        set_b2_target $USER
        ;;
      azure)
        set_azure_target $USER
        ;;
      upcloud)
        set_upcloud_target $USER
        ;;
      ibm)
        set_ibm_target $USER
        ;;
      wasabi)
        set_wasabi_target $USER
        ;;
      do_spaces)
        set_do_spaces_target $USER
        ;;
      linode)
        set_linode_target $USER
        ;;
      *)
        echo "Usage: $0 restore {aws|aws_one_zone|aws_standard_ia|gcs|b2|azure|upcloud|ibm|wasabi|do_spaces|linode} USER [RESTORE_TARGET] [RESTORE_PATH] [RESTORE_TIME]"
        remove_pid_file "$PIDFILE"
        exit 1
        ;;
    esac
    restore $RESTORE_TARGET $RESTORE_PATH $RESTORE_TIME
    ;;
  *)
    echo "Usage: $0 {backup|cleanup|restore} {aws|aws_one_zone|aws_standard_ia|gcs|b2|azure|upcloud|ibm|wasabi|do_spaces|linode} USER [RESTORE_TARGET] [RESTORE_PATH] [RESTORE_TIME]"
    remove_pid_file "$PIDFILE"
    exit 1
    ;;
esac

remove_pid_file "$PIDFILE"
