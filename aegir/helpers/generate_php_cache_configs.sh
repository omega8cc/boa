#!/bin/bash

# ====================================================================
# Script: generate_php_cache_configs.sh
# Description: Generates optimized OPcache and APCu/APC configuration
#        files for multiple PHP versions installed under /opt/php*
# ====================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# --------------------------------------------------------------------
# Define Custom Variables
# --------------------------------------------------------------------
_PHP_BASE_DIR="/opt"
_OPCACHE_FILE_CACHE_BASE="/var/www/phpcache"
_LOCKFILE_BASE="/var/tmp/fpm"
_COMMON_POOL_CONFIG="/opt/etc/fpm/fpm-pool-common.conf"
_PHP_VERSIONS=("php56" "php70" "php71" "php72" "php73" "php74" "php80" "php81" "php82" "php83" "php84")

# --------------------------------------------------------------------
# Function: _is_legacy_version
# Description: Determines if a PHP version is legacy (PHP 5.6, 7.0-7.4)
# --------------------------------------------------------------------
_is_legacy_version() {
  _version="$1"
  case "$_version" in
    php5*) return 0 ;;          # PHP 5.x are legacy
    php7.[0-4]*) return 0 ;;      # PHP 7.0-7.4 are legacy
    php8.[0-4]*) return 1 ;;      # PHP 8.0-8.4 are current
    *)
      echo "Unknown PHP version: $_version" >&2
      return 1
      ;;
  esac
}

# --------------------------------------------------------------------
# Function: _generate_opcache_config
# Description: Creates the OPcache configuration file for a given PHP version
# --------------------------------------------------------------------
_generate_opcache_config() {
  _php_version_dir="$1"
  _is_legacy="$2"
  _php_version=$(basename "$_php_version_dir")
  _opcache_ini="${_php_version_dir}/etc/php-fpm.d/10-opcache.conf"

  echo "Generating OPcache configuration for ${_php_version_dir}"

  # Ensure the php-fpm.d directory exists
  mkdir -p "$(dirname "${_opcache_ini}")"

  # Start writing the OPcache configuration with php_admin directives
  cat > "${_opcache_ini}" <<EOL
; OPcache Configuration for ${_php_version_dir}
php_admin_flag[opcache.enable] = on
php_admin_flag[opcache.dups_fix] = on
php_admin_flag[opcache.enable_file_override] = on
php_admin_flag[opcache.load_comments] = on
php_admin_flag[opcache.revalidate_path] = on
php_admin_flag[opcache.save_comments] = on
php_admin_flag[opcache.use_cwd] = on
php_admin_flag[opcache.validate_timestamps] = on

php_admin_value[default_socket_timeout] = 180
php_admin_value[max_execution_time] = 180
php_admin_value[max_input_time] = 180
php_admin_value[memory_limit] = 1024M
php_admin_value[opcache.memory_consumption] = 256
php_admin_value[opcache.interned_strings_buffer] = 128
php_admin_value[opcache.max_accelerated_files] = 200000
php_admin_value[opcache.validate_timestamps] = 1
php_admin_value[opcache.file_update_protection] = 8
php_admin_value[opcache.consistency_checks] = 0
php_admin_value[opcache.file_cache] = ${_OPCACHE_FILE_CACHE_BASE}/${_php_version}
php_admin_value[opcache.lockfile_path] = ${_LOCKFILE_BASE}
php_admin_value[opcache.log_verbosity_level] = 0
php_admin_value[opcache.restrict_api] = /var/www
php_admin_value[opcache.validate_permission] = 1
php_admin_value[opcache.validate_root] = 1
EOL

  # Create the OPcache file cache directory with appropriate permissions
  mkdir -p "${_OPCACHE_FILE_CACHE_BASE}/${_php_version}"
  chown www-data:www-data "${_OPCACHE_FILE_CACHE_BASE}/${_php_version}"
  chmod 700 "${_OPCACHE_FILE_CACHE_BASE}/${_php_version}"

  if [ "${_is_legacy}" -eq 0 ]; then
    # Add legacy OPcache settings for PHP 5.6 and 7.0-7.4
    cat >> "${_opcache_ini}" <<EOL

; Legacy OPcache settings for compatibility
php_admin_flag[opcache.dups_fix] = on
php_admin_flag[opcache.enable_file_override] = on
EOL
  fi
}

# --------------------------------------------------------------------
# Function: _generate_apcu_config
# Description: Creates the APCu or APC configuration file for a given PHP version
# --------------------------------------------------------------------
_generate_apcu_config() {
  _php_version_dir="$1"
  _is_legacy="$2"
  _php_version=$(basename "$_php_version_dir")
  _apc_ini="${_php_version_dir}/etc/php-fpm.d/20-apcu.conf"

  echo "Generating APCu/APC configuration for ${_php_version_dir}"

  # Ensure the php-fpm.d directory exists
  mkdir -p "$(dirname "${_apc_ini}")"

  if [ "${_is_legacy}" -eq 0 ]; then
    # For legacy PHP versions (PHP 5.6, 7.0-7.4), use APC for both opcode and user cache
    cat > "${_apc_ini}" <<EOL
; APC Configuration for ${_php_version_dir}
php_admin_flag[apc.enabled] = on
php_admin_value[apc.shm_size] = 1024M
php_admin_value[apc.shm_segments] = 1
php_admin_value[apc.user_entries_hint] = 4096
php_admin_value[apc.user_ttl] = 7200
php_admin_value[apc.gc_ttl] = 3600

; Additional APC Settings
php_admin_flag[apc.cache_by_default] = on
php_admin_flag[apc.stat] = on
EOL
  else
    # For current PHP versions (PHP 8.0-8.4), use APCu for user cache only
    cat > "${_apc_ini}" <<EOL
; APCu Configuration for ${_php_version_dir}
php_admin_flag[apc.enabled] = on
php_admin_value[apc.shm_size] = 256M
php_admin_value[apc.shm_segments] = 1
php_admin_value[apc.user_entries_hint] = 4096
php_admin_value[apc.user_ttl] = 7200
php_admin_value[apc.gc_ttl] = 3600
EOL
  fi
}

# --------------------------------------------------------------------
# Function: _backup_common_pool_config
# Description: Backs up the common pool configuration file
# --------------------------------------------------------------------
_backup_common_pool_config() {
  if [ -f "${_COMMON_POOL_CONFIG}" ]; then
    echo "Backing up common pool configuration..."
    cp "${_COMMON_POOL_CONFIG}" "${_COMMON_POOL_CONFIG}.bak"
  else
    echo "Common pool configuration file not found at ${_COMMON_POOL_CONFIG}. Skipping backup."
  fi
}

# --------------------------------------------------------------------
# Function: _remove_cache_settings_from_common_pool
# Description: Removes cache-related directives from the common pool config
# --------------------------------------------------------------------
_remove_cache_settings_from_common_pool() {
  echo "Removing cache-related settings from common pool configuration..."
  sed -i '/php_admin_flag\[opcache\./d' "${_COMMON_POOL_CONFIG}"
  sed -i '/php_admin_value\[opcache\./d' "${_COMMON_POOL_CONFIG}"
  sed -i '/php_admin_flag\[apc\./d' "${_COMMON_POOL_CONFIG}"
  sed -i '/php_admin_value\[apc\./d' "${_COMMON_POOL_CONFIG}"
}

# --------------------------------------------------------------------
# Function: _update_pool_configs_to_include_version_specific
# Description: Updates each PHP-FPM pool to include version-specific cache configs
# --------------------------------------------------------------------
_update_pool_configs_to_include_version_specific() {
  echo "Updating pool configurations to include version-specific cache configs..."

  for _php_version in "${_PHP_VERSIONS[@]}"; do
    _php_version_dir="${_PHP_BASE_DIR}/${_php_version}"
    _pool_dir="${_php_version_dir}/etc/php-fpm.d"

    if [ ! -d "${_pool_dir}" ]; then
      echo "Pool directory ${_pool_dir} does not exist. Skipping..."
      continue
    fi

    for _pool_conf in "${_pool_dir}"/*.conf; do
      # Ensure it's a regular file
      if [ ! -f "${_pool_conf}" ]; then
        echo "No .conf files found in ${_pool_dir}. Skipping..."
        continue
      fi

      # Define the specific cache config files to include
      _opcache_include="${_php_version_dir}/etc/php-fpm.d/10-opcache.conf"
      _apcu_include="${_php_version_dir}/etc/php-fpm.d/20-apcu.conf"

      # Check and add OPcache include directive
      if ! grep -q "include = ${_opcache_include}" "${_pool_conf}"; then
        echo "Adding include for OPcache config to ${_pool_conf}"
        echo "include = ${_opcache_include}" >> "${_pool_conf}"
      else
        echo "OPcache include directive already exists in ${_pool_conf}. Skipping."
      fi

      # Check and add APCu/APC include directive
      if ! grep -q "include = ${_apcu_include}" "${_pool_conf}"; then
        echo "Adding include for APCu/APC config to ${_pool_conf}"
        echo "include = ${_apcu_include}" >> "${_pool_conf}"
      else
        echo "APCu/APC include directive already exists in ${_pool_conf}. Skipping."
      fi
    done
  done
}

# --------------------------------------------------------------------
# Function: _restart_php_fpm_services
# Description: Restarts PHP-FPM services to apply new configurations
# --------------------------------------------------------------------
_restart_php_fpm_services() {
  echo "Restarting PHP-FPM services..."

  for _php_version in "${_PHP_VERSIONS[@]}"; do
    _service_suffix="${_php_version:3}"  # Extracts '56' from 'php56'
    _service_name="php${_service_suffix}-fpm"

    # Check if the service exists using 'service --status-all'
    if service --status-all 2>&1 | grep -q "[ + ] ${_service_name}"; then
      echo "Restarting ${_service_name}..."
      sudo service "${_service_name}" restart
    else
      echo "Service ${_service_name} does not exist. Skipping..."
    fi
  done

  echo "All applicable PHP-FPM services have been restarted."
}

# --------------------------------------------------------------------
# Function: _generate_configurations
# Description: Generates OPcache and APCu/APC configurations for all PHP versions
# --------------------------------------------------------------------
_generate_configurations() {
  for _php_version in "${_PHP_VERSIONS[@]}"; do
    _php_version_dir="${_PHP_BASE_DIR}/${_php_version}"

    # Check if the PHP version directory exists
    if [ ! -d "${_php_version_dir}" ]; then
      echo "Directory ${_php_version_dir} does not exist. Skipping..."
      continue
    fi

    # Determine if the PHP version is legacy
    _is_legacy=1
    _is_legacy_version "${_php_version}" && _is_legacy=0

    # Generate OPcache configuration
    _generate_opcache_config "${_php_version_dir}" "${_is_legacy}"

    # Generate APCu/APC configuration
    _generate_apcu_config "${_php_version_dir}" "${_is_legacy}"

    echo "Configuration for ${_php_version} completed."
    echo "----------------------------------------"
  done
}

# --------------------------------------------------------------------
# Function: _backup_and_clean_common_pool_config
# Description: Backs up and cleans the common pool configuration
# --------------------------------------------------------------------
_backup_and_clean_common_pool_config() {
  _backup_common_pool_config
  _remove_cache_settings_from_common_pool
}

# --------------------------------------------------------------------
# Function: _main
# Description: Main execution flow
# --------------------------------------------------------------------
_main() {
  # Step 1: Backup and clean the common pool configuration
  _backup_and_clean_common_pool_config

  # Step 2: Generate OPcache and APCu/APC configurations
  _generate_configurations

  # Step 3: Update pool configurations to include version-specific cache configs
  _update_pool_configs_to_include_version_specific

  # Step 4: Restart PHP-FPM services to apply changes
  _restart_php_fpm_services

  echo "All configurations have been applied successfully."
}

# --------------------------------------------------------------------
# Execute Main Function
# --------------------------------------------------------------------
_main
