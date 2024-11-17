#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Function to create README.txt with instructions
create_readme() {
  local user=$1
  local creds_dir="/data/disk/$user/static/control/backups_credentials"
  mkdir -p $creds_dir

  cat << EOF > "$creds_dir/README.txt"
### Backup Credentials Setup ###

To configure backups for your account, you need to fill in the necessary credentials for each supported service.

1. **AWS S3**:
  - File: aws.txt
  - Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION

2. **AWS S3 Express One Zone**:
  - File: aws_one_zone.txt
  - Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION

3. **AWS S3 Standard-IA**:
  - File: aws_standard_ia.txt
  - Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION

4. **Google Cloud Storage**:
  - File: gcs.txt
  - Required: GOOGLE_APPLICATION_CREDENTIALS, PROJECT_ID

5. **Backblaze B2**:
  - File: b2.txt
  - Required: B2_ACCOUNT_ID, B2_APPLICATION_KEY

6. **Azure Blob Storage**:
  - File: azure.txt
  - Required: AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_KEY

7. **UpCloud Object Storage**:
  - File: upcloud.txt
  - Required: UPCLOUD_USERNAME, UPCLOUD_PASSWORD, REGION

8. **IBM Cloud Object Storage**:
  - File: ibm.txt
  - Required: IBM_API_KEY_ID, IBM_SERVICE_INSTANCE_ID, IBM_REGION

9. **Wasabi Hot Cloud Storage**:
  - File: wasabi.txt
  - Required: WASABI_ACCESS_KEY, WASABI_SECRET_KEY, WASABI_REGION

10. **DigitalOcean Spaces**:
  - File: do_spaces.txt
  - Required: DO_SPACES_KEY, DO_SPACES_SECRET, DO_SPACES_REGION

11. **Linode Object Storage by Akamai**:
  - File: linode.txt
  - Required: LINODE_ACCESS_KEY, LINODE_SECRET_KEY, LINODE_REGION

Please make sure to securely store these files and protect them with appropriate permissions.

EOF

  echo "README.txt created at $creds_dir"
}

# Create README.txt for each user in /data/disk
for user_dir in /data/disk/*; do
  if [ -d "$user_dir" ]; then
    user=$(basename $user_dir)
    create_readme $user
  fi
done
