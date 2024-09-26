#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Paths
_PTH_VHOSTD="/var/aegir/config/server_master/nginx/vhost.d"
_PTH_OML="/var/xdrago/log/high.load.incident.log"

# Exit if proxy config exists
[ -e "/root/.proxy.cnf" ] && exit 0

# Function to check if the script is run as root
_check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script should be run as root"
    exit 1
  else
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  fi
}
_check_root

# Set default values
: "${_B_NICE:=10}"
: "${_CPU_SPIDER_RATIO:=1}"
: "${_CPU_MAX_RATIO:=2}"
: "${_CPU_CRIT_RATIO:=3}"
: "${_INCIDENT_EMAIL_REPORT:=YES}"

# Sanitize numeric variables
_B_NICE="${_B_NICE//[^0-9]/}"
_CPU_SPIDER_RATIO="${_CPU_SPIDER_RATIO//[^0-9]/}"
_CPU_MAX_RATIO="${_CPU_MAX_RATIO//[^0-9]/}"
_CPU_CRIT_RATIO="${_CPU_CRIT_RATIO//[^0-9]/}"

# Sanitize email report variable
_INCIDENT_EMAIL_REPORT="${_INCIDENT_EMAIL_REPORT^^}"
[ "${_INCIDENT_EMAIL_REPORT}" != "YES" ] && _INCIDENT_EMAIL_REPORT="NO"

# Ensure not too many instances are running
if [ "$(pgrep -f second.sh | grep -v "^$$" | wc -l)" -gt 4 ]; then
  echo "Too many second.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

# Get CPU count
_CPU_COUNT="$(nproc)"
[ -z "${_CPU_COUNT}" ] && _CPU_COUNT=1

# Function to send incident email report
_incident_email_report() {
  local _message="$1"
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    local _hostname
    _hostname="$(cat /etc/hostname)"
    echo "Sending Incident Report Email on $(date)" >> "${_PTH_OML}"
    s-nail -s "Incident Report: ${_message} on ${_hostname} at $(date)" "${_MY_EMAIL}" < "${_PTH_OML}"
  fi
}

# Function to pause web services
_hold_services() {
  killall -9 nginx
  killall -9 php-fpm
  local _log_message
  _log_message="$(date) System Load $1 Web Server Paused"
  echo "${_log_message}" >> "${_PTH_OML}"
  _incident_email_report "${_log_message}"
  echo >> "${_PTH_OML}"
  echo "Action Taken: Web services paused due to high load."
}

# Function to terminate long-running processes
_terminate_processes() {
  if [ ! -e "/run/boa_run.pid" ]; then
    killall -9 php drush.php wget curl &> /dev/null
    local _log_message
    _log_message="$(date) System Load $1 PHP/Wget/cURL terminated"
    echo "${_log_message}" >> "${_PTH_OML}"
    _incident_email_report "${_log_message}"
    echo >> "${_PTH_OML}"
    echo "Action Taken: Long-running processes terminated due to critical load."
  fi
}

# Function to enable nginx high load configuration
_nginx_high_load_on() {
  mv -f /data/conf/nginx_high_load_off.conf /data/conf/nginx_high_load.conf
  service nginx reload &> /dev/null
  local _log_message
  _log_message="$(date) nginx_high_load_on $1"
  echo "${_log_message}" >> "${_PTH_OML}"
  _incident_email_report "${_log_message}"
  echo >> "${_PTH_OML}"
  echo "Action Taken: Enabled protection from spiders (nginx high load configuration applied)."
}

# Function to disable nginx high load configuration
_nginx_high_load_off() {
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  service nginx reload &> /dev/null
  local _log_message
  _log_message="$(date) nginx_high_load_off $1"
  echo "${_log_message}" >> "${_PTH_OML}"
  _incident_email_report "${_log_message}"
  echo >> "${_PTH_OML}"
  echo "Action Taken: Disabled protection from spiders (nginx high load configuration removed)."
}

# Function to control processes
_proc_control() {
  echo "Running process control..."
  renice "${_B_NICE}" -p $$ &> /dev/null
  perl /var/xdrago/proc_num_ctrl.pl &
  touch /var/xdrago/log/proc_num_ctrl.done.pid
  echo "Process control done."
}

# Function to get system load averages
_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_COUNT}" 'BEGIN { printf "%.0f", (_load_value / _cpus) * 100 }')
  _F_LOAD=$(awk -v _load_value="${_five}" -v _cpus="${_CPU_COUNT}" 'BEGIN { printf "%.0f", (_load_value / _cpus) * 100 }')
}

# Function to control system load actions
_load_control() {
  _get_load

  # Thresholds in percentages
  _CPU_SPIDER_THRESHOLD=$((_CPU_SPIDER_RATIO * 100))
  _CPU_MAX_THRESHOLD=$((_CPU_MAX_RATIO * 100))
  _CPU_CRIT_THRESHOLD=$((_CPU_CRIT_RATIO * 100))

  echo "Current Load Averages:"
  echo " - 1-minute Load (per CPU): ${_O_LOAD}%"
  echo " - 5-minute Load (per CPU): ${_F_LOAD}%"
  echo "Thresholds:"
  echo " - Spider Protection Threshold: ${_CPU_SPIDER_THRESHOLD}%"
  echo " - Max Load Threshold: ${_CPU_MAX_THRESHOLD}%"
  echo " - Critical Load Threshold: ${_CPU_CRIT_THRESHOLD}%"

  # Determine if spider protection should be enabled
  _enable_spider_protection=false
  if [ "${_O_LOAD}" -ge "${_CPU_SPIDER_THRESHOLD}" ] && [ "${_O_LOAD}" -lt "${_CPU_MAX_THRESHOLD}" ]; then
    _enable_spider_protection=true
  elif [ "${_F_LOAD}" -ge "${_CPU_SPIDER_THRESHOLD}" ] && [ "${_F_LOAD}" -lt "${_CPU_MAX_THRESHOLD}" ]; then
    _enable_spider_protection=true
  fi

  # Enable or disable spider protection as needed
  if [ "${_enable_spider_protection}" = true ] && [ -e "/data/conf/nginx_high_load_off.conf" ]; then
    echo "Load exceeds spider protection threshold but below max threshold."
    _nginx_high_load_on "${_O_LOAD}/${_CPU_MAX_THRESHOLD}"
  elif [ "${_O_LOAD}" -lt "${_CPU_SPIDER_THRESHOLD}" ] && \
     [ "${_F_LOAD}" -lt "${_CPU_SPIDER_THRESHOLD}" ] && \
     [ -e "/data/conf/nginx_high_load.conf" ]; then
    echo "Load below spider protection threshold."
    _nginx_high_load_off "${_O_LOAD}/${_CPU_SPIDER_THRESHOLD}"
  else
    echo "Load within normal parameters."
  fi

  # Check for max load to hold services
  if [ "${_O_LOAD}" -ge "${_CPU_MAX_THRESHOLD}" ] || [ "${_F_LOAD}" -ge "${_CPU_MAX_THRESHOLD}" ]; then
    echo "Load exceeds max threshold. Pausing web services."
    _hold_services "${_O_LOAD}/${_CPU_MAX_THRESHOLD}"
  fi

  # Check for critical load to terminate processes
  if [ "${_O_LOAD}" -ge "${_CPU_CRIT_THRESHOLD}" ] || [ "${_F_LOAD}" -ge "${_CPU_CRIT_THRESHOLD}" ]; then
    echo "Load exceeds critical threshold. Terminating long-running processes."
    _terminate_processes "${_O_LOAD}/${_CPU_CRIT_THRESHOLD}"
  fi

  _proc_control
}

# Main execution
for _iteration in {1..6}; do
  echo "----------------------------"
  echo "Iteration ${_iteration}:"
  _load_control
  sleep 10
done

echo "Done!"
exit 0
