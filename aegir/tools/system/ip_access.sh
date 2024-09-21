#!/bin/bash

# Define the file paths
ctrl_dir="/var/aegir/control/ip"
input_file="$ctrl_dir/access.txt"
nginx_access_path="/var/aegir/config/includes/ip_access"
backup_dir="/var/aegir/undo"
current_backup_file="$backup_dir/.nginx_access_conf.current.bak.tar.gz"
last_good_backup_file="$backup_dir/.nginx_access_conf.last_good.bak.tar.gz"
timestamp_file="$nginx_access_path/.access_last_mod_time"
ssh_ips_hash_file="$nginx_access_path/.ssh_ips_hash"
server_ip_file="/root/.found_correct_ipv4.cnf"

# Regular expression for validating IPv4 addresses and site names
ipv4_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
site_name_regex="^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}$"

# Ensure the ctrl, output and backup directories exist
mkdir -p "$backup_dir"
mkdir -p "$ctrl_dir"
mkdir -p "$nginx_access_path"

# Create a dummy input file if does not exist
[[ ! -f "$input_file" ]] && echo "sqladmin.com 192.168.1.1" > $input_file

if [[ ! -f "$server_ip_file" ]]; then
  echo "Server IP file $server_ip_file not found. Exiting."
  exit 1
fi

# Get the server's own IP address from the configuration file
server_ip=$(cat "$server_ip_file" 2>/dev/null)

# Function to get currently logged in SSH IPs
get_ssh_ips() {
  # Use `who --ips` to get logged-in user IPs, filter out local sessions, and return unique, sorted IPs
  who --ips | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort | uniq
}

# Store SSH IPs and compute hash
ssh_ips=$(get_ssh_ips)
ssh_ips_hash=$(echo "$ssh_ips" | md5sum | awk '{print $1}')

# Check if the timestamp file exists before trying to read it
if [[ -f "$timestamp_file" ]]; then
  last_mod_time=$(cat "$timestamp_file" 2>/dev/null || echo 0)
else
  last_mod_time=0
fi

# Get the current modification time of the input file
current_mod_time=$(stat -c %Y "$input_file" 2>/dev/null)
if [[ $? -ne 0 ]]; then
  echo "Failed to get modification time for $input_file. Exiting."
  exit 1
fi

# Check if the SSH IP hash file exists
if [[ -f "$ssh_ips_hash_file" ]]; then
  previous_ssh_ips_hash=$(cat "$ssh_ips_hash_file" 2>/dev/null || echo "")
else
  previous_ssh_ips_hash=""
fi

# Check if we need to update the whitelists based on file or SSH IP changes
if [[ "$current_mod_time" -le "$last_mod_time" && "$ssh_ips_hash" == "$previous_ssh_ips_hash" ]]; then
  echo "No changes detected in $input_file or SSH IPs. Exiting."
  exit 0
fi

# Backup the current configuration files before making changes, if they exist
if [[ -d "$nginx_access_path" ]]; then
  tar -czf "$current_backup_file" -C "$nginx_access_path" .
else
  echo "No existing configuration directory to backup."
fi

# Function to generate the IP whitelist include files per vhost
generate_whitelists() {
  while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Split the line into an array
    read -ra fields <<< "$line"

    # The first field is the site name
    site_name="${fields[0]}"

    # Convert the site name to lowercase
    site_name=$(echo "$site_name" | tr '[:upper:]' '[:lower:]')

    # Validate the site name
    if [[ ! $site_name =~ $site_name_regex ]]; then
      echo "Invalid site name detected: $site_name. Skipping."
      continue
    fi

    # Prepare the whitelist include file path
    whitelist_file="$nginx_access_path/$site_name.conf"

    # Collect IP addresses for this site
    ip_addresses="${fields[@]:1}"
    ip_list=()

    # Always include loopback, server's own IP, and SSH logged-in IPs
    ip_list+=("127.0.0.1")
    [[ -n "$server_ip" ]] && ip_list+=("$server_ip")

    # Add SSH IPs to the allowed list
    for ssh_ip in $ssh_ips; do
      ip_list+=("$ssh_ip")
    done

    for ip in $ip_addresses; do
      # Validate the IP address
      if [[ $ip =~ $ipv4_regex ]]; then
        ip_list+=("$ip")
      else
        echo "Invalid IP address format detected: $ip. Skipping."
      fi
    done

    # Remove duplicates and sort the IP list
    ip_list_sorted=$(printf "%s\n" "${ip_list[@]}" | sort | uniq)

    # Write the IP whitelist configuration to the file
    {
      for ip in $ip_list_sorted; do
        echo "allow $ip;"
      done
      echo "deny all;"
    } > "$whitelist_file"

  done < "$input_file"
}

# Generate the IP whitelist files
generate_whitelists

# Test the new Nginx configuration
nginx_configtest=$(sudo /etc/init.d/nginx configtest 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Nginx configuration test failed: $nginx_configtest"
  echo "Reverting to the last known good configuration."
  if [[ -f "$last_good_backup_file" ]]; then
    tar -xzf "$last_good_backup_file" -C "$nginx_access_path"
    sudo /etc/init.d/nginx reload
  else
    echo "No backup found to revert to. Manual intervention required."
  fi
  exit 1
fi

# Reload Nginx if the configuration test passed
sudo /etc/init.d/nginx reload
if [[ $? -ne 0 ]]; then
  echo "Nginx reload failed. Reverting to the last known good configuration."
  if [[ -f "$last_good_backup_file" ]]; then
    tar -xzf "$last_good_backup_file" -C "$nginx_access_path"
    sudo /etc/init.d/nginx reload
  else
    echo "No backup found to revert to. Manual intervention required."
  fi
  exit 1
fi

# If everything is successful, update the last known good backup
tar -czf "$last_good_backup_file" -C "$nginx_access_path" .

# Update the timestamp file and SSH IPs hash
echo "$current_mod_time" > "$timestamp_file"
echo "$ssh_ips_hash" > "$ssh_ips_hash_file"

# Output the result
echo "Nginx IP whitelist configuration updated and Nginx reloaded successfully."

