#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=dev

# Function to verify BOA keys
_verify_boa_keys() {
  if [ -e "/root/.dev.server.cnf" ]; then
    echo "PROC: _verify_boa_keys in duplicity_bundle_installer"
  fi
  if [ "${_tRee}" = "pro" ] || [ "${_tRee}" = "dev" ]; then
    _allw=NO
    _crlGet="-L --max-redirs 3 -k -s --retry 9 --retry-delay 9 -A iCab"
    _urlEnc="http://files.aegir.cc/enc/2024"
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    _encName=$(echo ${_hName} \
      | openssl md5 \
      | awk '{ print $2}' \
      | tr -d "\n" 2>&1)
    if [[ "${_hName}" =~ ".aegir.cc"($) ]] \
      || [[ "${_hName}" =~ ".o8.io"($) ]] \
      || [[ "${_hName}" =~ ".boa.io"($) ]]; then
      _allw=YES
    fi
    mkdir -p /var/opt
    rm -f /var/opt/_encN*
    curl ${_crlGet} "${_urlEnc}/${_encName}" -o /var/opt/_encN.${_encName}.tmp
    wait
    echo "${_hName}.${_encName}" > /var/opt/_encN_local.${_encName}.tmp
    wait
    if [ -e "/var/opt/_encN.${_encName}.tmp" ] && [ -e "/var/opt/_encN_local.${_encName}.tmp" ]; then
      _diffTestIf=$(diff -w -B /var/opt/_encN.${_encName}.tmp /var/opt/_encN_local.${_encName}.tmp 2>&1)
      if [ ! -z "${_diffTestIf}" ] && [ "${_allw}" = "NO" ]; then
        echo
        echo "Your system requires valid license to use this function"
        echo "Please visit https://omega8.cc/licenses to purchase your own"
        echo
        if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ] \
          && [ ! -e "/var/aegir/key/barracuda_key.txt" ]; then
          mkdir -p /var/aegir/key
          cat /var/opt/_encN_local.${_encName}.tmp > /var/aegir/key/barracuda_key.txt
        fi
        rm -f /var/opt/_encN*
        exit 0
      else
        if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ] \
          && [ ! -e "/var/aegir/key/barracuda_key.txt" ]; then
          mkdir -p /var/aegir/key
          cat /var/opt/_encN_local.${_encName}.tmp > /var/aegir/key/barracuda_key.txt
        fi
      fi
    else
      echo
      echo "Your system requires valid license to use this BOA feature"
      echo "Unfortunately it was not possible to verify your system status"
      echo "Please contact our support but visit https://omega8.cc/licenses first"
      echo
      exit 0
    fi
  fi
}

# Function to verify root access
_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 0 -p $$
    chmod a+w /dev/null
    [ -e "/root/.gnupg" ] && chmod 700 /root/.gnupg
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST="$(command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 { gsub(/%/,"",$u); print $u }')"
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  _AWS_VLV=${_AWS_VLV//[^a-z]/}
  if [ -z "${_AWS_VLV}" ]; then
    _AWS_VLV="warning"
  fi
}
_check_root
_verify_boa_keys

[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

# New OpenSSL 3.x version is required
if [ ! -x "/usr/local/ssl3/bin/openssl" ]; then
  echo "New OpenSSL 3.x version is required"
  exit 1
fi

# Directory where all scripts are located
_SCRIPT_DIR="/root/.remote_backups/run"

# Define paths to individual scripts
_INSTALL_DEPENDENCIES_SCRIPT="${_SCRIPT_DIR}/install_dependencies.sh"
_CREATE_CREDENTIALS_TEMPLATES_SCRIPT="${_SCRIPT_DIR}/create_credentials_templates.sh"
_CREATE_GLOBAL_PATHS_CONFIG_SCRIPT="${_SCRIPT_DIR}/create_global_paths_config.sh"
_CREATE_USER_PATHS_CONFIG_SCRIPT="${_SCRIPT_DIR}/create_user_paths_config.sh"
_CREATE_CRON_ENTRIES_SCRIPT="${_SCRIPT_DIR}/create_cron_entries.sh"
_CREATE_README_SCRIPT="${_SCRIPT_DIR}/create_readme.sh"
_CREATE_CONFIG_README_SCRIPT="${_SCRIPT_DIR}/create_config_readme.sh"

# Function to display usage information
_usage() {
  echo "Usage: $0 {install|setup|update}"
  echo "  install : Install dependencies required for backups."
  echo "  setup   : Perform initial configuration setup (creates paths, credentials, and cron entries)."
  echo "  update  : Alias for setup; updates existing configuration."
  exit 1
}

# Function to check for required scripts
_check_scripts() {
  for _script in \
    "${_INSTALL_DEPENDENCIES_SCRIPT}" \
    "${_CREATE_CREDENTIALS_TEMPLATES_SCRIPT}" \
    "${_CREATE_GLOBAL_PATHS_CONFIG_SCRIPT}" \
    "${_CREATE_USER_PATHS_CONFIG_SCRIPT}" \
    "${_CREATE_CRON_ENTRIES_SCRIPT}" \
    "${_CREATE_README_SCRIPT}" \
    "${_CREATE_CONFIG_README_SCRIPT}"
  do
    if [ ! -f "${_script}" ]; then
      echo "Error: Required script ${_script} not found."
      exit 1
    fi
  done
}

# Function to install dependencies
_install_dependencies() {
  echo "Installing dependencies..."
  service cron stop && ln -sfn /bin/dash /usr/bin/sh
  bash "${_INSTALL_DEPENDENCIES_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install dependencies."
    exit 1
  fi
  echo "Dependencies installed successfully."
  service cron start
}

# Function to perform setup (initial configuration)
_setup_configuration() {
  echo "Setting up configuration..."

  echo "Step 1: Creating global paths configuration..."
  bash "${_CREATE_GLOBAL_PATHS_CONFIG_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create global paths configuration."
    exit 1
  fi

  echo "Step 2: Creating user-specific paths configuration..."
  bash "${_CREATE_USER_PATHS_CONFIG_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create user paths configuration."
    exit 1
  fi

  echo "Step 3: Creating credentials templates..."
  bash "${_CREATE_CREDENTIALS_TEMPLATES_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create credentials templates."
    exit 1
  fi

  echo "Step 4: Creating cron entries..."
  bash "${_CREATE_CRON_ENTRIES_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create cron entries."
    exit 1
  fi

  echo "Step 5: Creating global README files..."
  bash "${_CREATE_README_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create global README files."
    exit 1
  fi

  echo "Step 6: Creating user config README files..."
  bash "${_CREATE_CONFIG_README_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create user config README files."
    exit 1
  fi

  echo "Configuration setup completed successfully."
}

# Main logic
if [ $# -ne 1 ]; then
  _usage
fi

_action=$1
_check_scripts

case "${_action}" in
  install)
    _install_dependencies
    ;;
  setup|update)
    _setup_configuration
    ;;
  *)
    _usage
    ;;
esac
