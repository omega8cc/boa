#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Function to create the global paths configuration file
create_global_paths_config() {
  # Define the global backup source and include/exclude variables
  GLOBAL_SOURCE="/etc /var/aegir /var/www /home /data"
  GLOBAL_INCLUDE="--include-filelist /var/xdrago/backup/include.txt"
  GLOBAL_EXCLUDE="--exclude-filelist /var/xdrago/backup/exclude.txt"

  # Create the global paths configuration file
  GLOBAL_PATH_CONFIG="/var/xdrago/backup/paths.txt"
  mkdir -p /var/xdrago/backup

  echo "SOURCE=\"$GLOBAL_SOURCE\"" > $GLOBAL_PATH_CONFIG
  echo "INCLUDE=\"$GLOBAL_INCLUDE\"" >> $GLOBAL_PATH_CONFIG
  echo "EXCLUDE=\"$GLOBAL_EXCLUDE\"" >> $GLOBAL_PATH_CONFIG

  echo "Global paths configuration created at $GLOBAL_PATH_CONFIG"
}

# Create global paths configuration file
create_global_paths_config
