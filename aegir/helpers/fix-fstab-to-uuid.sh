#!/bin/bash

# Enable strict error handling for debugging only
# set -euo pipefail

echo "Backing up /etc/fstab to /etc/fstab.bak"
cp -p /etc/fstab /etc/fstab.bak

echo "Processing Linode volume mounts..."

# Loop through current fstab entries related to Linode Volumes
grep '/dev/disk/by-id/scsi-0Linode_Volume_' /etc/fstab.bak | while read -r line; do
  # Extract device and mount point
  device=$(echo "$line" | awk '{print $1}')
  mountpoint=$(echo "$line" | awk '{print $2}')

  # Resolve the real device path (like /dev/sdb, /dev/sdc)
  realdev=$(readlink -f "$device")

  # Get the UUID of the real device
  uuid=$(blkid -s UUID -o value "$realdev")

  if [ -n "$uuid" ]; then
    echo "Updating $mountpoint to UUID=$uuid"
    # Escape slashes for sed replacement
    escaped_device=$(echo "$device" | sed 's|/|\\/|g')
    sed -i "s|$escaped_device|UUID=$uuid|" /etc/fstab
  else
    echo "Warning: UUID not found for $device ($realdev)"
  fi
done

echo "Checking with diff.."
diff -urp /etc/fstab.bak /etc/fstab

echo "Done. New /etc/fstab is ready."
echo "Please verify with: cat /etc/fstab"
echo "If everything looks good, you can safely reboot."
