#!/bin/bash

# Function to create a user's paths configuration file
create_user_paths_config() {
  local user=$1
  local user_config_dir="/data/disk/$user/remote_backups"
  local user_config_file="$user_config_dir/paths.txt"

  mkdir -p $user_config_dir

  echo "SOURCE=\"/data/disk/$user\"" > $user_config_file
  echo "INCLUDE=\"--include-filelist $user_config_dir/.backboa.$user.include\"" >> $user_config_file
  echo "EXCLUDE=\"--exclude-filelist $user_config_dir/.backboa.$user.exclude\"" >> $user_config_file

  echo "Paths configuration for $user created at $user_config_file"
}

# Create paths configuration files for each user in /data/disk
for user_dir in /data/disk/*; do
  if [ -d "$user_dir" ]; then
    user=$(basename $user_dir)
    create_user_paths_config $user
  fi
done
