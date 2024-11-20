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
_PHP_VERSIONS=("php56" "php70" "php71" "php72" "php73" "php74" "php80" "php81" "php82" "php83")

# --------------------------------------------------------------------
# Function: _is_legacy_version
# Description: Determines if a PHP version is legacy (PHP 5.6, 7.0-7.4)
# --------------------------------------------------------------------
_is_legacy_version() {
  local _version="$1"
  case "$_version" in
    php5*) return 0 ;;          # PHP 5.x are legacy
    php7.[0-4]*) return 0 ;;      # PHP 7.0-7.4 are legacy
    php8.[0-3]*) return 1 ;;      # PHP 8.0-8.3 are current
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
  local _php_version_dir="$1"
  local _is_legacy="$2"
  local _php_version=$(basename "$_php_version_dir")
  local _opcache_ini="${_php_version_dir}/etc/php/fpm/conf.d/10-opcache.ini"

  echo "Generating OPcache configuration for ${_php_version_dir}"

  # Ensure the conf.d directory exists
  mkdir -p "$(dirname "${_opcache_ini}")"

  # Start writing the OPcache configuration
  cat > "${_opcache_ini}" <<EOL
; OPcache Configuration for ${_php_version_dir}
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=100000
opcache.validate_timestamps=0
opcache.revalidate_freq=60
opcache.fast_shutdown=1
opcache.enable_cli=0
opcache.save_comments=1
opcache.load_comments=1
opcache.use_cwd=1
opcache.file_cache=${_OPCACHE_FILE_CACHE_BASE}/${_php_version}
opcache.consistency_checks=0
opcache.file_update_protection=60
opcache.lockfile_path=${_LOCKFILE_BASE}
opcache.log_verbosity_level=0
opcache.restrict_api=/var/www
opcache.validate_permission=1
opcache.validate_root=1
EOL

  # Create the OPcache file cache directory
  mkdir -p "${_OPCACHE_FILE_CACHE_BASE}/${_php_version}"
  chown www-data:www-data "${_OPCACHE_FILE_CACHE_BASE}/${_php_version}"
  chmod 700 "${_OPCACHE_FILE_CACHE_BASE}/${_php_version}"

  if [ "${_is_legacy}" -eq 0 ]; then
    # Add legacy OPcache settings for PHP 5.6 and 7.0-7.4
    cat >> "${_opcache_ini}" <<EOL

; Legacy OPcache settings for compatibility
opcache.dups_fix=1
opcache.enable_file_override=1
EOL
  fi
}

# --------------------------------------------------------------------
# Function: _generate_apcu_config
# Description: Creates the APCu or APC configuration file for a given PHP version
# --------------------------------------------------------------------
_generate_apcu_config() {
  local _php_version_dir="$1"
  local _is_legacy="$2"
  local _php_version=$(basename "$_php_version_dir")
  local _apc_ini="${_php_version_dir}/etc/php/fpm/conf.d/20-apcu.ini"

  echo "Generating APCu/APC configuration for ${_php_version_dir}"

  # Ensure the conf.d directory exists
  mkdir -p "$(dirname "${_apc_ini}")"

  if [ "${_is_legacy}" -eq 0 ]; then
    # For legacy PHP versions (PHP 5.6, 7.0-7.4), use APC for both opcode and user cache
    cat > "${_apc_ini}" <<EOL
; APC Configuration for ${_php_version_dir}
extension=apc.so
apc.enabled=1
apc.shm_size=1024M
apc.shm_segments=1
apc.user_entries_hint=4096
apc.user_ttl=7200
apc.gc_ttl=3600

; APC Settings
apc.cache_by_default=1
apc.stat=1
EOL
  else
    # For current PHP versions (PHP 8.0-8.3), use APCu for user cache only
    cat > "${_apc_ini}" <<EOL
; APCu Configuration for ${_php_version_dir}
extension=apcu.so
apc.enabled=1
apc.shm_size=256M
apc.shm_segments=1
apc.user_entries_hint=4096
apc.user_ttl=7200
apc.gc_ttl=3600
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
  sed -i '/opcache\./d' "${_COMMON_POOL_CONFIG}"
  sed -i '/apc\./d' "${_COMMON_POOL_CONFIG}"
}

# --------------------------------------------------------------------
# Function: _update_pool_configs_to_include_version_specific
# Description: Updates each PHP-FPM pool to include version-specific cache configs
# --------------------------------------------------------------------
_update_pool_configs_to_include_version_specific() {
  echo "Updating pool configurations to include version-specific cache configs..."

  for _php_version in "${_PHP_VERSIONS[@]}"; do
    _php_version_dir="${_PHP_BASE_DIR}/${_php_version}"
    _pool_dir="${_php_version_dir}/etc/pool.d"

    if [ ! -d "${_pool_dir}" ]; then
      echo "Pool directory ${_pool_dir} does not exist. Skipping..."
      continue
    fi

    for _pool_conf in "${_pool_dir}"/*.conf; do
      # Define the include directive
      _cache_include="${_php_version_dir}/etc/php/fpm/conf.d/*.ini"

      # Check if the include directive already exists
      if ! grep -q "include = ${_cache_include}" "${_pool_conf}"; then
        echo "Adding include for cache configs to ${_pool_conf}"
        echo "include = ${_cache_include}" >> "${_pool_conf}"
      else
        echo "Include directive for cache configs already exists in ${_pool_conf}. Skipping."
      fi
    done
  done
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
