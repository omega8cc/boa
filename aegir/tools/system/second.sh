#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_monPath="/var/xdrago/monitor/check"

# Exit if proxy config exists
[ -e "/root/.proxy.cnf" ] && exit 0

# shellcheck disable=SC1091
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf

# Sanitize numeric variables (allow digits and decimal point)
_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

# Paths
_pthOml="/var/log/boa/high.load.incident.log"

# Load _RATIO defaults + sanitize
_CPU_CRIT_RATIO="$(_sanitize_number "${_CPU_CRIT_RATIO}")"
_CPU_MAX_RATIO="$(_sanitize_number "${_CPU_MAX_RATIO}")"
_CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
_CPU_SPIDER_RATIO="$(_sanitize_number "${_CPU_SPIDER_RATIO}")"

# ===== Config (ratios per CPU) =====
: "${_CPU_CRIT_RATIO:=6.1}"    # CRIT: pause web + kill long procs + block spiders
: "${_CPU_MAX_RATIO:=4.1}"     # MAX:  pause web + block spiders
: "${_CPU_TASK_RATIO:=3.1}"    # TASK: skip backend tasks (but web OK)
: "${_CPU_SPIDER_RATIO:=2.1}"  # SPIDER: allow web; block spiders only

# Sanitize to allow only digits and minus sign
export _B_NICE=${_B_NICE//[^0-9-]/}

# Validate and set default if necessary
if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
  _B_NICE=0
fi

# Clamp the value within -20 to 19
if (( _B_NICE < -20 )); then
  _B_NICE=-20
elif (( _B_NICE > 19 )); then
  _B_NICE=19
fi

renice ${_B_NICE} -p $$ &> /dev/null

# Get CPU count
_CPU_COUNT=$(nproc)
[ -z "${_CPU_COUNT}" ] && _CPU_COUNT=1

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

###
### Load + normalize _INCIDENT_REPORT
###
### Legacy values:
###   NO  becomes OFF (see below)
###   YES becomes MINI (see below)
###
### Current values:
###   OFF  == Total silence, no email alerts
###   ALL  == Very noisy, good for debugging
###   MINI == Only the most important alerts (default)
###   CRIT == Only critical if _lvl=ALERT
###
_normalize_incident_report() {
  : "${_INCIDENT_REPORT:=CRIT}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  ###
  ### Map legacy + validate
  ###
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="CRIT" ;;
    MINI) _INCIDENT_REPORT="CRIT" ;;
    OFF|ALL|CRIT) : ;;
    *)    _INCIDENT_REPORT="CRIT" ;;
  esac
}
_normalize_incident_report

###
### Function to send incident email report
###
_incident_email_report() {
  _check_uptime_grace_period >/dev/null || return 1
  local _subject="${1:-(no subject)}"
  local _lvl="${2:-INFO}"
  _lvl="${_lvl^^}"
  [ -n "${_MY_EMAIL}" ] || return 1
  # Decide if we should send
  case "${_INCIDENT_REPORT}" in
    OFF)  return 1 ;;                            # always veto
    CRIT) [ "${_lvl}" = "ALERT" ] || return 1 ;; # veto unless ALERT
    ALL) : ;;                                    # allow
  esac
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
  s-nail -s "Incident Report on ${_hName}: ${_subject}" "${_MY_EMAIL}" < ${_pthOml}
}

# Function to pause web services
_hold_services() {
  local _current_load="$1"
  local _threshold="$2"
  local _load_period="$3"
  touch /run/boa_second_auto_healing.pid
  sleep 3
  service nginx stop
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm force-quit
    fi
  done
  killall php-fpm
  killall nginx
  local _log_message
  _log_message="$(date) System Load ${_current_load}% (${_load_period}) - Web Server Paused"
  echo "${_log_message}" >> ${_pthOml}
  local _subject="Web Services Paused - ${_load_period} Load ${_current_load}% exceeded Max Load Threshold ${_threshold}%"
  _incident_email_report "${_subject}" "ALERT"
  echo >> ${_pthOml}
  echo "Action Taken: Web services paused due to high load."
  sleep 5
  [ -e "/run/boa_second_auto_healing.pid" ] && rm -f /run/boa_second_auto_healing.pid
}

# Function to terminate long-running processes
_terminate_processes() {
  local _current_load="$1"
  local _threshold="$2"
  local _load_period="$3"
  killall -9 php drush.php wget curl &> /dev/null
  local _log_message
  _log_message="$(date) System Load ${_current_load}% (${_load_period}) - PHP/Wget/cURL terminated"
  echo "${_log_message}" >> ${_pthOml}
  local _subject="Processes Terminated - ${_load_period} Load ${_current_load}% exceeded Critical Load Threshold ${_threshold}%"
  _incident_email_report "${_subject}" "ALERT"
  echo >> ${_pthOml}
  echo "Action Taken: Long-running processes terminated due to critical load."
}

# Function to enable nginx high load configuration
_nginx_high_load_on() {
  local _current_load="$1"
  local _threshold="$2"
  local _load_period="$3"
  mv -f /data/conf/nginx_high_load_off.conf /data/conf/nginx_high_load.conf
  service nginx reload &> /dev/null
  local _log_message
  _log_message="$(date) Enabled Spider Protection ${_load_period} Load: ${_current_load}%"
  echo "${_log_message}" >> ${_pthOml}
# local _subject="Enabled Spider Protection - ${_load_period} Load ${_current_load}% exceeded Spider Protection Threshold ${_threshold}%"
# _incident_email_report "${_subject}" "INFO"
# echo >> ${_pthOml}
  echo "Action Taken: Enabled protection from spiders (nginx high load configuration applied)."
}

# Function to disable nginx high load configuration
_nginx_high_load_off() {
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  service nginx reload &> /dev/null
  local _log_message
  _log_message="$(date) Disabled Spider Protection Load: ${_O_LOAD}%"
  echo "${_log_message}" >> ${_pthOml}
# local _subject="Disabled Spider Protection - Load decreased below Spider Protection Threshold ${_CPU_SPIDER_THRESHOLD}%"
# _incident_email_report "${_subject}" "INFO"
# echo >> ${_pthOml}
  echo "Action Taken: Disabled protection from spiders (nginx high load configuration removed)."
}

# Fire-and-forget launcher, cron-safe and interactive-safe
_spawn_detached() {
  _cmd="$1"
  if command -v nohup >/dev/null 2>&1; then
    nohup bash -c "${_cmd}" >/dev/null 2>&1 &
  elif command -v setsid >/dev/null 2>&1; then
    setsid bash -c "${_cmd}" >/dev/null 2>&1 &
  else
    ( bash -c "${_cmd}" >/dev/null 2>&1 ) &
  fi
  # If interactive shell, drop it from the job table to mimic cron behavior
  if [[ "$-" == *i* ]]; then disown; fi
}

# Function to control processes
_proc_control() {
  echo "Running process control..."
  renice "${_B_NICE}" -p $$ &> /dev/null
  # Service watchdogs + guards split out of the legacy proc_num_ctrl.pl. Each is
  # a single-shot, self-guarded monitor in monitor/check/; absent ones (e.g. not
  # yet fetched, or deliberately removed) are simply skipped.
  for _w in sendmail_guard convert_guard hostname_sync syslog_legacy \
            bind9 proxysql droplet newrelic_daemon newrelic_sysmond \
            collectd xinetd lsyncd; do
    [ -e "${_monPath}/${_w}.sh" ] && _spawn_detached "bash ${_monPath}/${_w}.sh"
  done
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
    sleep 9
    # Sustained critical load → verify twice with brief cooldown then react
    if awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_CRIT_THRESHOLD} || ${_F_LOAD} > ${_CPU_CRIT_THRESHOLD})}"; then
      touch /run/critical_load.pid
      [ -e "/run/max_load.pid" ] && rm -f /run/max_load.pid
      [ -e "/run/normal_load.pid" ] && rm -f /run/normal_load.pid
      [ -e "/run/spider_load.pid" ] && rm -f /run/spider_load.pid
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
      if [ ! -e "/run/boa_second_auto_healing.pid" ]; then
        _terminate_processes "${_current_load}" "${_CPU_CRIT_THRESHOLD}" "${_load_period}"
        _hold_services "${_current_load}" "${_CPU_MAX_THRESHOLD}" "${_load_period}"
      fi
    fi
  # Check for max load to hold services
  elif awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_MAX_THRESHOLD} || ${_F_LOAD} > ${_CPU_MAX_THRESHOLD})}"; then
    sleep 9
    # Sustained max load → verify twice with brief cooldown then react
    if awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_MAX_THRESHOLD} || ${_F_LOAD} > ${_CPU_MAX_THRESHOLD})}"; then
      touch /run/max_load.pid
      [ -e "/run/critical_load.pid" ] && rm -f /run/critical_load.pid
      [ -e "/run/normal_load.pid" ] && rm -f /run/normal_load.pid
      [ -e "/run/spider_load.pid" ] && rm -f /run/spider_load.pid
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
      if [ ! -e "/run/boa_second_auto_healing.pid" ]; then
        _hold_services "${_current_load}" "${_CPU_MAX_THRESHOLD}" "${_load_period}"
      fi
    fi
  # Check for spider protection threshold
  elif awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_SPIDER_THRESHOLD} && ${_O_LOAD} <= ${_CPU_MAX_THRESHOLD})}"; then
    sleep 9
    # Sustained too high for spiders load → verify twice with brief cooldown then react
    if awk "BEGIN {exit !(${_O_LOAD} > ${_CPU_SPIDER_THRESHOLD} && ${_O_LOAD} <= ${_CPU_MAX_THRESHOLD})}"; then
      touch /run/spider_load.pid
      [ -e "/run/critical_load.pid" ] && rm -f /run/critical_load.pid
      [ -e "/run/max_load.pid" ] && rm -f /run/max_load.pid
      [ -e "/run/normal_load.pid" ] && rm -f /run/normal_load.pid
      echo "Load exceeds spider protection threshold but below max threshold."
      _limits_exceeded=true
      # Do not set _skip_proc_control to true here
      _current_load="${_O_LOAD}"
      _load_period="1-minute"
      if [ -e "/data/conf/nginx_high_load_off.conf" ]; then
        _nginx_high_load_on "${_current_load}" "${_CPU_SPIDER_THRESHOLD}" "${_load_period}"
      fi
    fi
  elif awk "BEGIN {exit !(${_F_LOAD} > ${_CPU_SPIDER_THRESHOLD} && ${_F_LOAD} <= ${_CPU_MAX_THRESHOLD})}"; then
    sleep 9
    # Sustained too high for spiders load → verify twice with brief cooldown then react
    if awk "BEGIN {exit !(${_F_LOAD} > ${_CPU_SPIDER_THRESHOLD} && ${_F_LOAD} <= ${_CPU_MAX_THRESHOLD})}"; then
      touch /run/spider_load.pid
      [ -e "/run/critical_load.pid" ] && rm -f /run/critical_load.pid
      [ -e "/run/max_load.pid" ] && rm -f /run/max_load.pid
      [ -e "/run/normal_load.pid" ] && rm -f /run/normal_load.pid
      echo "Load exceeds spider protection threshold but below max threshold."
      _limits_exceeded=true
      # Do not set _skip_proc_control to true here
      _current_load="${_F_LOAD}"
      _load_period="5-minute"
      if [ -e "/data/conf/nginx_high_load_off.conf" ]; then
        _nginx_high_load_on "${_current_load}" "${_CPU_SPIDER_THRESHOLD}" "${_load_period}"
      fi
    fi
  else
    touch /run/normal_load.pid
    [ -e "/run/critical_load.pid" ] && rm -f /run/critical_load.pid
    [ -e "/run/max_load.pid" ] && rm -f /run/max_load.pid
    [ -e "/run/spider_load.pid" ] && rm -f /run/spider_load.pid
    # If load is below spider protection threshold, disable spider protection if it's enabled
    if [ -e "/data/conf/nginx_high_load.conf" ] && \
       awk "BEGIN {exit !(${_O_LOAD} <= ${_CPU_SPIDER_THRESHOLD} && ${_F_LOAD} <= ${_CPU_SPIDER_THRESHOLD})}"; then
      echo "Load below spider protection threshold."
      _nginx_high_load_off
    else
      echo "Load within normal parameters."
    fi
  fi

  # _proc_control is invoked by the main loop on the heavy fan-out cadence,
  # gated by _skip_proc_control (set true above when load limits were exceeded).
}

###
### Classify the box so the heavy fan-out can be throttled on the small/idle/CI
### hosts where it dominates idle load, while normal production hosts keep the
### historical every-pass cadence. Precedence matches runner.sh: a small box
### (.slow.cron.cnf, auto-created + immutable on <=4GB, or a RAM<=4096 fallback)
### is SLOW UNLESS .force.queue.runner.cnf opts it back to full cadence.
### .fast.cron.cnf is deliberately NOT honored here — runner.sh ignores it while
### .slow.cron.cnf is set, so letting it force NORMAL would un-throttle exactly
### the tiny boxes this targets (e.g. a 4GB box carrying both markers).
###
_monitor_box_class() {
  local _ram_mb
  _ram_mb="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
  _ram_mb="${_ram_mb//[^0-9]/}"
  if [ -e "/etc/boa/.look.like.jenkins.cnf" ]; then
    _BOX_CLASS=CI
  elif { [ -e "/root/.slow.cron.cnf" ] \
       || { [ -n "${_ram_mb}" ] && [ "${_ram_mb}" -le 4096 ]; }; } \
    && [ ! -e "/root/.force.queue.runner.cnf" ]; then
    _BOX_CLASS=SLOW
  else
    _BOX_CLASS=NORMAL
  fi
}

# Decide the heavy fan-out cadence. The 10x/5s loop is kept so load sampling and
# auto-pause stay responsive (cheap), but the expensive part — the watchdog
# fan-out (_proc_control) and the hack/escape scanners — runs only every Nth
# pass: every pass on NORMAL (unchanged), every 4th on SLOW, once/minute on CI.
# Overridable from .barracuda.cnf via _MONITOR_HEAVY_EVERY.
_monitor_box_class
case "${_BOX_CLASS}" in
  CI)   _HEAVY_EVERY=10 ;;
  SLOW) _HEAVY_EVERY=4  ;;
  *)    _HEAVY_EVERY=1  ;;
esac
[[ "${_MONITOR_HEAVY_EVERY}" =~ ^[0-9]+$ ]] && _HEAVY_EVERY="${_MONITOR_HEAVY_EVERY}"
(( _HEAVY_EVERY < 1 )) && _HEAVY_EVERY=1

# Main execution
for _iteration in {1..10}; do
  echo "----------------------------"
  echo "Iteration ${_iteration}:"
  _load_control
  if (( (_iteration - 1) % _HEAVY_EVERY == 0 )); then
    if [ "${_skip_proc_control}" = false ]; then
      _proc_control
    else
      echo "Limits exceeded; skipping process control."
    fi
    nohup ${_monPath}/hackcheck.sh > /dev/null 2>&1 &
    nohup ${_monPath}/hackftp.sh > /dev/null 2>&1 &
    nohup ${_monPath}/escapecheck.sh > /dev/null 2>&1 &
  fi
  sleep 5
done

echo "Done!"
exit 0
