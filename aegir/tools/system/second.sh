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
    chmod a+w /dev/null
  fi
}
_check_root

# Set default values
: "${_B_NICE:=10}"
: "${_CPU_SPIDER_RATIO:=0.8}"
: "${_CPU_MAX_RATIO:=2.1}"
: "${_CPU_CRIT_RATIO:=3.1}"
: "${_INCIDENT_EMAIL_REPORT:=YES}"

# Source configuration file to override defaults
if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
fi

# Sanitize numeric variables (allow digits and decimal point)
_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_B_NICE="$(_sanitize_number "${_B_NICE}")"
_CPU_SPIDER_RATIO="$(_sanitize_number "${_CPU_SPIDER_RATIO}")"
_CPU_MAX_RATIO="$(_sanitize_number "${_CPU_MAX_RATIO}")"
_CPU_CRIT_RATIO="$(_sanitize_number "${_CPU_CRIT_RATIO}")"

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
  local _subject="$2"
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    local _hostname
    _hostname="$(cat /etc/hostname)"
    echo "Sending Incident Report Email on $(date)" >> "${_PTH_OML}"
    s-nail -s "Incident Report on ${_hostname}: ${_subject}" "${_MY_EMAIL}" < "${_PTH_OML}"
  fi
}

# Function to pause web services
_hold_services() {
  local _current_load="$1"
  local _threshold="$2"
  local _load_period="$3"
  killall -9 nginx
  killall -9 php-fpm
  local _log_message
  _log_message="$(date) System Load ${_current_load}% (${_load_period}) - Web Server Paused"
  echo "${_log_message}" >> "${_PTH_OML}"
  local _subject="Web Services Paused - ${_load_period} Load ${_current_load}% exceeded Max Load Threshold ${_threshold}%"
  _incident_email_report "${_log_message}" "${_subject}"
  echo >> "${_PTH_OML}"
  echo "Action Taken: Web services paused due to high load."
}

# Function to terminate long-running processes
_terminate_processes() {
  local _current_load="$1"
  local _threshold="$2"
  local _load_period="$3"
  if [ ! -e "/run/boa_run.pid" ]; then
    killall -9 php drush.php wget curl &> /dev/null
    local _log_message
    _log_message="$(date) System Load ${_current_load}% (${_load_period}) - PHP/Wget/cURL terminated"
    echo "${_log_message}" >> "${_PTH_OML}"
    local _subject="Processes Terminated - ${_load_period} Load ${_current_load}% exceeded Critical Load Threshold ${_threshold}%"
    _incident_email_report "${_log_message}" "${_subject}"
    echo >> "${_PTH_OML}"
    echo "Action Taken: Long-running processes terminated due to critical load."
  fi
}

# Function to enable nginx high load configuration
_nginx_high_load_on() {
  local _current_load="$1"
  local _threshold="$2"
  local _load_period="$3"
  mv -f /data/conf/nginx_high_load_off.conf /data/conf/nginx_high_load.conf
  service nginx reload &> /dev/null
  local _log_message
  _log_message="$(date) nginx_high_load_on ${_load_period} Load: ${_current_load}%"
  echo "${_log_message}" >> "${_PTH_OML}"
  local _subject="Enabled Spider Protection - ${_load_period} Load ${_current_load}% exceeded Spider Protection Threshold ${_threshold}%"
  _incident_email_report "${_log_message}" "${_subject}"
  echo >> "${_PTH_OML}"
  echo "Action Taken: Enabled protection from spiders (nginx high load configuration applied)."
}

# Function to disable nginx high load configuration
_nginx_high_load_off() {
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  service nginx reload &> /dev/null
  local _log_message
  _log_message="$(date) nginx_high_load_off Load: ${_O_LOAD}%"
  echo "${_log_message}" >> "${_PTH_OML}"
  local _subject="Disabled Spider Protection - Load decreased below Spider Protection Threshold ${_CPU_SPIDER_THRESHOLD}%"
  _incident_email_report "${_log_message}" "${_subject}"
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
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_COUNT}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
  _F_LOAD=$(awk -v _load_value="${_five}" -v _cpus="${_CPU_COUNT}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

# Function to control system load actions
_load_control() {
  _get_load

  # Initialize the limits exceeded flag
  _limits_exceeded=false

  # Thresholds in percentages (calculate using bc)
  _CPU_SPIDER_THRESHOLD=$(echo "${_CPU_SPIDER_RATIO} * 100" | bc -l)
  _CPU_MAX_THRESHOLD=$(echo "${_CPU_MAX_RATIO} * 100" | bc -l)
  _CPU_CRIT_THRESHOLD=$(echo "${_CPU_CRIT_RATIO} * 100" | bc -l)

  echo "Current Load Averages:"
  echo " - 1-minute Load (per CPU): ${_O_LOAD}%"
  echo " - 5-minute Load (per CPU): ${_F_LOAD}%"
  echo "Thresholds:"
  echo " - Critical Load Threshold: ${_CPU_CRIT_THRESHOLD}%"
  echo " - Max Load Threshold: ${_CPU_MAX_THRESHOLD}%"
  echo " - Spider Protection Threshold: ${_CPU_SPIDER_THRESHOLD}%"

  # Check for critical load to terminate processes and hold services
  if awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_CRIT_THRESHOLD} || ${_F_LOAD} > ${_CPU_CRIT_THRESHOLD})}"; then
    echo "Load exceeds critical threshold. Terminating processes and pausing web services."
    _limits_exceeded=true
    if awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_CRIT_THRESHOLD})}"; then
      _current_load="${_O_LOAD}"
      _load_period="1-minute"
    else
      _current_load="${_F_LOAD}"
      _load_period="5-minute"
    fi
    _terminate_processes "${_current_load}" "${_CPU_CRIT_THRESHOLD}" "${_load_period}"
    _hold_services "${_current_load}" "${_CPU_MAX_THRESHOLD}" "${_load_period}"
  # Check for max load to hold services
  elif awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_MAX_THRESHOLD} || ${_F_LOAD} > ${_CPU_MAX_THRESHOLD})}"; then
    echo "Load exceeds max threshold. Pausing web services."
    _limits_exceeded=true
    if awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_MAX_THRESHOLD})}"; then
      _current_load="${_O_LOAD}"
      _load_period="1-minute"
    else
      _current_load="${_F_LOAD}"
      _load_period="5-minute"
    fi
    _hold_services "${_current_load}" "${_CPU_MAX_THRESHOLD}" "${_load_period}"
  # Check for spider protection threshold
  elif awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_SPIDER_THRESHOLD} && ${_O_LOAD} <= ${_CPU_MAX_THRESHOLD})}"; then
    echo "Load exceeds spider protection threshold but below max threshold."
    _limits_exceeded=true
    _current_load="${_O_LOAD}"
    _load_period="1-minute"
    if [ -e "/data/conf/nginx_high_load_off.conf" ]; then
      _nginx_high_load_on "${_current_load}" "${_CPU_SPIDER_THRESHOLD}" "${_load_period}"
    fi
  elif awk "BEGIN {exit !(${_F_LOAD} > ${_CPU_SPIDER_THRESHOLD} && ${_F_LOAD} <= ${_CPU_MAX_THRESHOLD})}"; then
    echo "Load exceeds spider protection threshold but below max threshold."
    _limits_exceeded=true
    _current_load="${_F_LOAD}"
    _load_period="5-minute"
    if [ -e "/data/conf/nginx_high_load_off.conf" ]; then
      _nginx_high_load_on "${_current_load}" "${_CPU_SPIDER_THRESHOLD}" "${_load_period}"
    fi
  else
    # If load is below spider protection threshold, disable spider protection if it's enabled
    if [ -e "/data/conf/nginx_high_load.conf" ] && \
       awk "BEGIN {exit !(${_O_LOAD} <= ${_CPU_SPIDER_THRESHOLD} && ${_F_LOAD} <= ${_CPU_SPIDER_THRESHOLD})}"; then
      echo "Load below spider protection threshold."
      _nginx_high_load_off
    else
      echo "Load within normal parameters."
    fi
  fi

  # Only run _proc_control if no limits have been exceeded
  if [ "${_limits_exceeded}" = false ]; then
    _proc_control
  else
    echo "Limits exceeded; skipping process control."
  fi
}

# Main execution
for _iteration in {1..12}; do
  echo "----------------------------"
  echo "Iteration ${_iteration}:"
  _load_control
  sleep 5
done

echo "Done!"
exit 0
