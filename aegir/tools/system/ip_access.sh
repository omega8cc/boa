#!/bin/bash

# Define the file paths
_ctrl_dir="/var/aegir/control/ip"
_input_file="${_ctrl_dir}/access.txt"
_nginx_access_path="/var/aegir/config/includes/ip_access"
_backup_dir="/var/aegir/undo"
_current_backup_file="${_backup_dir}/.nginx_access_conf.current.bak.tar.gz"
_last_good_backup_file="${_backup_dir}/.nginx_access_conf.last_good.bak.tar.gz"
_timestamp_file="${_nginx_access_path}/.access_last_mod_time"
_ssh_ips_hash_file="${_nginx_access_path}/.ssh_ips_hash"
_server_ip_file="/root/.found_correct_ipv4.cnf"

# Regular expression for validating IPv4 addresses and site names
_ipv4_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
_site_name_regex="^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}$"

# Ensure the ctrl, output and backup directories exist
mkdir -p "${_backup_dir}"
mkdir -p "${_ctrl_dir}"
mkdir -p "${_nginx_access_path}"

# Create a dummy input file if does not exist
[[ ! -f "${_input_file}" ]] && echo "sqladmin.com 192.168.1.1" > ${_input_file}

if [[ ! -f "${_server_ip_file}" ]]; then
  echo "Server IP file ${_server_ip_file} not found. Exiting."
  exit 1
fi

# Get the server's own IP address from the configuration file
_server_ip=$(cat "${_server_ip_file}" 2>/dev/null)

# Function to get currently logged in SSH IPs
_get_ssh_ips() {
  # Use `who --ips` to get logged-in user IPs, filter out local sessions, and return unique, sorted IPs
  who --ips | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort | uniq
}

# Store SSH IPs and compute hash
_ssh_ips=$(_get_ssh_ips)
_ssh_ips_hash=$(echo "${_ssh_ips}" | md5sum | awk '{print $1}')

# Check if the timestamp file exists before trying to read it
if [[ -f "${_timestamp_file}" ]]; then
  _last_mod_time=$(cat "${_timestamp_file}" 2>/dev/null || echo 0)
else
  _last_mod_time=0
fi

# Get the current modification time of the input file
_current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null)
if [[ $? -ne 0 ]]; then
  echo "Failed to get modification time for ${_input_file}. Exiting."
  exit 1
fi

# Check if the SSH IP hash file exists
if [[ -f "${_ssh_ips_hash_file}" ]]; then
  _previous_ssh_ips_hash=$(cat "${_ssh_ips_hash_file}" 2>/dev/null || echo "")
else
  _previous_ssh_ips_hash=""
fi

# Check if we need to update the whitelists based on file or SSH IP changes
if [[ "${_current_mod_time}" -le "${_last_mod_time}" && "${_ssh_ips_hash}" == "${_previous_ssh_ips_hash}" ]]; then
  echo "No changes detected in ${_input_file} or SSH IPs. Exiting."
  exit 0
fi

# Backup the current configuration files before making changes, if they exist
if [[ -d "${_nginx_access_path}" ]]; then
  tar -czf "${_current_backup_file}" -C "${_nginx_access_path}" .
else
  echo "No existing configuration directory to backup."
fi

# Function to generate the IP whitelist include files per vhost
_generate_whitelists() {
  while IFS= read -r _line; do
    # Skip empty lines
    [[ -z "${_line}" ]] && continue

    # Split the line into an array
    read -ra _fields <<< "${_line}"

    # The first field is the site name
    _site_name="${_fields[0]}"

    # Convert the site name to lowercase
    _site_name=$(echo "${_site_name}" | tr '[:upper:]' '[:lower:]')

    # Validate the site name
    if [[ ! ${_site_name} =~ ${_site_name_regex} ]]; then
      echo "Invalid site name detected: ${_site_name}. Skipping."
      continue
    fi

    # Prepare the whitelist include file path
    whitelist_file="${_nginx_access_path}/${_site_name}.conf"

    # Collect IP addresses for this site
    _ip_addresses="${_fields[@]:1}"
    _ip_list=()

    # Always include loopback, server's own IP, and SSH logged-in IPs
    _ip_list+=("127.0.0.1")
    [[ -n "${_server_ip}" ]] && _ip_list+=("${_server_ip}")

    # Add SSH IPs to the allowed list
    for _ssh_ip in ${_ssh_ips}; do
      _ip_list+=("${_ssh_ip}")
    done

    for _ip in ${_ip_addresses}; do
      # Validate the IP address
      if [[ ${_ip} =~ ${_ipv4_regex} ]]; then
        _ip_list+=("${_ip}")
      else
        echo "Invalid IP address format detected: ${_ip}. Skipping."
      fi
    done

    # Remove duplicates and sort the IP list
    _ip_list_sorted=$(printf "%s\n" "${_ip_list[@]}" | sort | uniq)

    # Write the IP whitelist configuration to the file
    {
      for _ip in ${_ip_list_sorted}; do
        echo "allow ${_ip};"
      done
      echo "deny all;"
    } > "$whitelist_file"

  done < "${_input_file}"
}

# Generate the IP whitelist files
_generate_whitelists

# Test the new Nginx configuration
nginx_configtest=$(sudo /etc/init.d/nginx configtest 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Nginx configuration test failed: $nginx_configtest"
  echo "Reverting to the last known good configuration."
  if [[ -f "${_last_good_backup_file}" ]]; then
    tar -xzf "${_last_good_backup_file}" -C "${_nginx_access_path}"
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
  if [[ -f "${_last_good_backup_file}" ]]; then
    tar -xzf "${_last_good_backup_file}" -C "${_nginx_access_path}"
    sudo /etc/init.d/nginx reload
  else
    echo "No backup found to revert to. Manual intervention required."
  fi
  exit 1
fi

# If everything is successful, update the last known good backup
tar -czf "${_last_good_backup_file}" -C "${_nginx_access_path}" .

# Update the timestamp file and SSH IPs hash
echo "${_current_mod_time}" > "${_timestamp_file}"
echo "${_ssh_ips_hash}" > "${_ssh_ips_hash_file}"

# Output the result
echo "Nginx IP whitelist configuration updated and Nginx reloaded successfully."

