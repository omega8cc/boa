#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Paths
_pthOml="/var/log/boa/high.load.incident.log"

# Exit if proxy config exists
[ -e "/root/.proxy.cnf" ] && exit 0

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "$_L" ] && . "$_L" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc "[${_SCRIPT:0:1}]${_SCRIPT:1}")
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

# Set default values
: "${_CPU_SPIDER_RATIO:=2.1}"
: "${_CPU_MAX_RATIO:=4.1}"
: "${_CPU_CRIT_RATIO:=6.1}"
: "${_INCIDENT_REPORT:=YES}"

# Source configuration file to override defaults
if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
fi

    # Sanitize to allow only digits and minus sign
    export _B_NICE=${_B_NICE//[^0-9-]/}

    # Validate and set default if necessary
    if ! [[ "$_B_NICE" =~ ^-?[0-9]+$ ]]; then
      _B_NICE=0
    fi

    # Clamp the value within -20 to 19
    if (( _B_NICE < -20 )); then
      _B_NICE=-20
    elif (( _B_NICE > 19 )); then
      _B_NICE=19
    fi

    renice ${_B_NICE} -p $$ &> /dev/null

# Sanitize numeric variables (allow digits and decimal point)
_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_CPU_SPIDER_RATIO="$(_sanitize_number "${_CPU_SPIDER_RATIO}")"
_CPU_MAX_RATIO="$(_sanitize_number "${_CPU_MAX_RATIO}")"
_CPU_CRIT_RATIO="$(_sanitize_number "${_CPU_CRIT_RATIO}")"

# Sanitize email report variable
_INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
case "${_INCIDENT_REPORT}" in
  "YES"|"NO"|"VERBOSE")
    ;;
  *)
    _INCIDENT_REPORT="YES"
    ;;
esac

# Get CPU count
_CPU_COUNT=$(nproc)
[ -z "${_CPU_COUNT}" ] && _CPU_COUNT=1

# Function to send incident email report
_incident_email_report() {
  local _message="$1"
  local _subject="$2"
  local _incident_level="$3"  # "ALERT" or "INFO"

  if [ -n "${_MY_EMAIL}" ]; then
    local _send_email=false

    if [ "${_INCIDENT_REPORT}" = "VERBOSE" ]; then
      _send_email=true
    elif [ "${_INCIDENT_REPORT}" = "YES" ]; then
      if [ "${_incident_level}" = "ALERT" ]; then
        _send_email=true
      fi
    fi

    if [ "${_send_email}" = true ]; then
      _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
      echo "Sending Incident Report Email on $(date)" >> "${_pthOml}"
      s-nail -s "Incident Report on ${_hName}: ${_subject}" "${_MY_EMAIL}" < "${_pthOml}"
    fi
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
  echo "${_log_message}" >> "${_pthOml}"
  local _subject="Web Services Paused - ${_load_period} Load ${_current_load}% exceeded Max Load Threshold ${_threshold}%"
  _incident_email_report "${_log_message}" "${_subject}" "ALERT"
  echo >> "${_pthOml}"
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
    echo "${_log_message}" >> "${_pthOml}"
    local _subject="Processes Terminated - ${_load_period} Load ${_current_load}% exceeded Critical Load Threshold ${_threshold}%"
    _incident_email_report "${_log_message}" "${_subject}" "ALERT"
    echo >> "${_pthOml}"
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
  echo "${_log_message}" >> "${_pthOml}"
  local _subject="Enabled Spider Protection - ${_load_period} Load ${_current_load}% exceeded Spider Protection Threshold ${_threshold}%"
  _incident_email_report "${_log_message}" "${_subject}" "INFO"
  echo >> "${_pthOml}"
  echo "Action Taken: Enabled protection from spiders (nginx high load configuration applied)."
}

# Function to disable nginx high load configuration
_nginx_high_load_off() {
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  service nginx reload &> /dev/null
  local _log_message
  _log_message="$(date) nginx_high_load_off Load: ${_O_LOAD}%"
  echo "${_log_message}" >> "${_pthOml}"
  local _subject="Disabled Spider Protection - Load decreased below Spider Protection Threshold ${_CPU_SPIDER_THRESHOLD}%"
  _incident_email_report "${_log_message}" "${_subject}" "INFO"
  echo >> "${_pthOml}"
  echo "Action Taken: Disabled protection from spiders (nginx high load configuration removed)."
}

# Function to control processes
_proc_control() {
  echo "Running process control..."
  renice "${_B_NICE}" -p $$ &> /dev/null
  if [ -e "/var/xdrago/proc_num_ctrl.pl" ]; then
    perl /var/xdrago/proc_num_ctrl.pl &
  elif [ -e "/var/xdrago_wait/proc_num_ctrl.pl" ]; then
    perl /var/xdrago_wait/proc_num_ctrl.pl &
  fi
  touch /var/log/boa/proc_num_ctrl.done.pid
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

  # Initialize the flags
  _limits_exceeded=false
  _skip_proc_control=false

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
    _skip_proc_control=true
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
    _skip_proc_control=true
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
    # Do not set _skip_proc_control to true here
    _current_load="${_O_LOAD}"
    _load_period="1-minute"
    if [ -e "/data/conf/nginx_high_load_off.conf" ]; then
      _nginx_high_load_on "${_current_load}" "${_CPU_SPIDER_THRESHOLD}" "${_load_period}"
    fi
  elif awk "BEGIN {exit !(${_F_LOAD} > ${_CPU_SPIDER_THRESHOLD} && ${_F_LOAD} <= ${_CPU_MAX_THRESHOLD})}"; then
    echo "Load exceeds spider protection threshold but below max threshold."
    _limits_exceeded=true
    # Do not set _skip_proc_control to true here
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

  # Decide whether to run _proc_control
  if [ "${_skip_proc_control}" = false ]; then
    _proc_control
  else
    echo "Limits exceeded; skipping process control."
  fi
}

# Main execution
for _iteration in {1..9}; do
  echo "----------------------------"
  echo "Iteration ${_iteration}:"
  perl /var/xdrago/monitor/check/hackcheck.pl &
  perl /var/xdrago/monitor/check/hackftp.pl &
  perl /var/xdrago/monitor/check/escapecheck.pl &
  _load_control
  sleep 5
done

echo "Done!"
exit 0

