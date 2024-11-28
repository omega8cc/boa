#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

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
  bash "${_INSTALL_DEPENDENCIES_SCRIPT}"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install dependencies."
    exit 1
  fi
  echo "Dependencies installed successfully."
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
