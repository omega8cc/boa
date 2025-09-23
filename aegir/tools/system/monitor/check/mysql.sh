#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/mysql.incident.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

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

export _SQL_MAX_TTL=${_SQL_MAX_TTL//[^0-9]/}
: "${_SQL_MAX_TTL:=3600}"

export _SQL_LOW_MAX_TTL=${_SQL_LOW_MAX_TTL//[^0-9]/}
: "${_SQL_LOW_MAX_TTL:=60}"

export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
: "${_INCIDENT_REPORT:=YES}"

export _LOAD_THRESHOLD=${_LOAD_THRESHOLD//[^0-9.]/}
: "${_LOAD_THRESHOLD:=33.0}" # Example: 1-minute load above 33 indicates high load

export _THREAD_THRESHOLD=${_THREAD_THRESHOLD//[^0-9]/}
: "${_THREAD_THRESHOLD:=99}" # Example: More than 99 MySQL threads

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

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_valkey_cold_restart() {
  killall -9 valkey-server &> /dev/null
  rm -f /var/lib/valkey/*
  service valkey-server start &> /dev/null
  wait
}

_redis_cold_restart() {
  killall -9 redis-server &> /dev/null
  rm -f /var/lib/redis/*
  service redis-server start &> /dev/null
  wait
}

_sql_restart() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date) $1 incident detected" >> ${_pthOml}
  killall sleep &> /dev/null
  killall php
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date) $1 incident Percona MySQL server restarted" >> ${_pthOml}
  if [ -e "/var/lib/valkey" ]; then
    _valkey_cold_restart
    echo "$(date) $1 incident Valkey server restarted" >> ${_pthOml}
  elif [ -e "/var/lib/redis" ]; then
    _redis_cold_restart
    echo "$(date) $1 incident Redis server restarted" >> ${_pthOml}
  fi
  echo "$(date) $1 incident response completed" >> ${_pthOml}
  _incident_email_report "$1"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_sql_busy_detection() {
  if [ -e "/var/log/daemon.log" ]; then
    _SQL_LOG="/var/log/daemon.log"
  else
    _SQL_LOG="/var/log/syslog"
  fi
  if [ -e "${_SQL_LOG}" ]; then
    if [ `tail --lines=333 ${_SQL_LOG} \
      | grep --count "Too many connections"` -gt 111 ]; then
      _IS_PROVISION_RUNNING=$(ps aux | grep '[p]rovision' | awk '{print $2}' 2>&1)
      if [ -z "${_IS_PROVISION_RUNNING}" ]; then
        _sql_restart "BUSY MySQL"
      fi
    fi
  fi
  if [ -e "/root/.instant.busy.mysql.action.cnf" ]; then
    _SQL_PSWD=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}')
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ] && [ ! -z "${_SQL_PSWD}" ]; then
      _MYSQL_CONN_TEST=$(mysql -u root -e "status" 2>&1)
      echo _MYSQL_CONN_TEST ${_MYSQL_CONN_TEST}
      if [[ "${_MYSQL_CONN_TEST}" =~ "Too many connections" ]]; then
        _sql_restart "BUSY MySQL"
      fi
    fi
  fi
}

_mysql_proc_kill() {
  _xtime=${_xtime//[^0-9]/}
  echo "Monitoring process ${_each} by ${_xuser} running for ${_xtime} seconds"

  if [[ -n "${_xtime}" && ${_xtime} -gt ${_limit} ]]; then
    echo "Killing process ${_each} by ${_xuser} after ${_xtime} seconds"
    _xkill=$(mysqladmin -u root kill ${_each} 2>&1)
    _times=$(date)
    _load=$(cat /proc/_loadavg)

    # Log the _load and the process killing details
    echo "${_load}" >> /var/log/boa/sql_watch.log
    echo "${_times} ${_each} ${_xuser} ${_xtime} ${_xkill}" >> /var/log/boa/sql_watch.log
  fi
}

_mysql_proc_control() {
  # Log the MySQL process list if _SQLMONITOR is enabled
  if [[ "${_SQLMONITOR}" == "YES" ]]; then
    mysqladmin -u root proc -v >> /var/log/boa/mysqladmin.monitor.log
  fi

  # Default TTL _limit in seconds (can be adjusted)
  _limit=${1:-3600}

  # Get all MySQL processes and extract PID, user, and running time
  _mysql_proc_list=$(mysqladmin -u root proc | awk 'NR>3 {print $2, $4, $12}')

  # Iterate over _each process
  echo "${_mysql_proc_list}" | while read -r _each _xuser _xtime; do
    _each=${_each//[^0-9]/}
    _xuser=${_xuser//[^0-9a-z_]/}
    _xtime=${_xtime//[^0-9]/}

    # Skip root user processes
    if [[ "${_xuser}" == "root" ]]; then
      echo "Skipping root process: ${_each}"
      continue
    fi

    if [[ -n "${_each}" && "${_each}" -gt 5 && -n "${_xtime}" ]]; then
      echo "Process ID: ${_each}, User: ${_xuser}, Time: ${_xtime} seconds"

      # Check if the user is listed on the problematic users list
      if [[ -e "/root/.sql.problematic.users.cnf" ]]; then
        for _XQ in $(cat /root/.sql.problematic.users.cnf | cut -d '#' -f1 | sort | uniq); do
          if [[ "${_xuser}" == "${_XQ}" ]]; then
            echo "Problematic user detected: ${_xuser}, applying lower limit"
            _limit=${_SQL_LOW_MAX_TTL}
          fi
        done
      else
        _limit=${_SQL_MAX_TTL}  # Default _limit for non-problematic users
      fi

      _mysql_proc_kill
    fi
  done
}

_mysql_high_load() {

  # Get the current 1-minute load average
  _LOAD=$(awk '{print $1}' /proc/loadavg)

  # Get the mysqld process ID
  _MYSQL_PID=$(pidof mysqld)

  # Count threads for the mysqld process (subtracting the header)
  _MYSQL_THREADS=$(ps -T -p "${_MYSQL_PID}" | tail -n +2 | wc -l)

  echo "Current load average: ${_LOAD}"
  echo "Current MySQL thread count: ${_MYSQL_THREADS}"

  # Compare against thresholds; use bc for floating point comparison
  if (( $(echo "${_LOAD} > ${_LOAD_THRESHOLD}" | bc -l) )) && [ "${_MYSQL_THREADS}" -gt "${_THREAD_THRESHOLD}" ]; then
    echo "High load and excessive MySQL threads detected. Restarting MySQL..."
    _sql_restart "HIGH LOAD MySQL"
  else
    echo "System operating normally."
  fi
}


_mysql_is_locked() {
  _OCT_NR=$(ls /data/disk | wc -l)

  if [ -n "${_OCT_NR}" ] && [ "${_OCT_NR}" -ge 1 ]; then
    if [ "${_OCT_NR}" -ge 6 ]; then
      _MULTI_MX=$(( _OCT_NR * 3 ))
    else
      _MULTI_MX=$(( _OCT_NR * 5 ))
    fi
    if [ "${_OCT_NR}" -lt 4 ]; then
      _MULTI_MX=$(( _OCT_NR + 10 ))
    fi
  fi

  if (( $(pgrep -fc 'aegir.sh') > ${_MULTI_MX} )); then
    if (( $(pgrep -fc 'mysql_backup.sh') > 0 )); then
      kill -9 $(ps aux | grep '[m]ydumper' | awk '{print $2}') &> /dev/null
      _incident_email_report "TOO MANY ($(pgrep -fc 'aegir.sh') aegir.sh required killing mydumper"
    fi
  fi
  if (( $(pgrep -fc 'drush.php') > ${_MULTI_MX} )); then
    if (( $(pgrep -fc 'mysql_backup.sh') > 0 )); then
      kill -9 $(ps aux | grep '[m]ydumper' | awk '{print $2}') &> /dev/null
      kill -9 $(ps aux | grep '[d]rush.php' | awk '{print $2}') &> /dev/null
      _incident_email_report "TOO MANY ($(pgrep -fc 'drush.php') drush.php required killing mydumper"
    fi
  fi
}

_mysql_high_load
_sql_busy_detection
_mysql_is_locked

perl /var/xdrago/monitor/check/sqlcheck.pl &

if [ -e "/run/boa_sql_backup.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ]; then
  _SQL_CTRL=NO
else
  _SQL_CTRL=YES
fi

[ "${_SQL_CTRL}" = "YES" ] && _mysql_proc_control "${_SQL_MAX_TTL}"
sleep 15
[ "${_SQL_CTRL}" = "YES" ] && _mysql_proc_control "${_SQL_MAX_TTL}"
sleep 15
[ "${_SQL_CTRL}" = "YES" ] && _mysql_proc_control "${_SQL_MAX_TTL}"
sleep 15
[ "${_SQL_CTRL}" = "YES" ] && _mysql_proc_control "${_SQL_MAX_TTL}"

echo DONE!
exit 0

