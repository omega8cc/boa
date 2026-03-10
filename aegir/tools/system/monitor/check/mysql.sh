#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/mysql.incident.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

# Run only on fully installed system
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

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

export _SQL_MAX_TTL=${_SQL_MAX_TTL//[^0-9]/}
: "${_SQL_MAX_TTL:=3600}"

export _SQL_LOW_MAX_TTL=${_SQL_LOW_MAX_TTL//[^0-9]/}
: "${_SQL_LOW_MAX_TTL:=60}"

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
  : "${_INCIDENT_REPORT:=MINI}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  ###
  ### Map legacy + validate
  ###
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_incident_email_report() {
  if ! _check_uptime_grace_period >/dev/null; then return 1; fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ]; then
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
  touch /run/boa_mysql_auto_healing.pid
  if [ ! -d "/run/mysqld" ]; then
    mkdir -p /run/mysqld
    chown -R mysql:root /run/mysqld
  fi
  sleep 3
  echo "$(date) $1 incident detected" >> ${_pthOml}
  killall sleep &> /dev/null
  killall php
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date) $1 incident Percona server restarted" >> ${_pthOml}
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
  [ -e "/run/boa_mysql_auto_healing.pid" ] && rm -f /run/boa_mysql_auto_healing.pid
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
      _IS_PROVISION_RUNNING=$(pgrep -f provision)
      if [ -z "${_IS_PROVISION_RUNNING}" ]; then
        _sql_restart "BUSY MySQL"
      fi
    fi
  fi
  if [ -e "/root/.instant.busy.mysql.action.cnf" ]; then
    _SQL_PSWD=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
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
  # Control file to enable _SQLMONITOR
  if [ -e "/root/.mysqladmin.monitor.cnf" ]; then
    _SQLMONITOR=YES
  fi

  # Log the MySQL process list if _SQLMONITOR is enabled
  if [[ "${_SQLMONITOR}" == "YES" ]]; then
    [ -e "/var/xdrago/log/mysqladmin.monitor.log" ] && mv -f /var/xdrago/log/mysqladmin.monitor.log /var/log/boa/
    [ -e "/root/.nodebug_slow_query.pid" ] && rm -f /root/.nodebug_slow_query.pid
    if [ ! -e "/root/.debug_slow_query.pid" ]; then
      touch /root/.debug_slow_query.pid
      mysql -u root -e "SET GLOBAL slow_query_log = 'ON';" &> /dev/null
      mysql -u root -e "SET GLOBAL long_query_time = 5;" &> /dev/null
      mysql -u root -e "SET GLOBAL slow_query_log_file = '/var/log/mysql/sql-slow-query.log';" &> /dev/null
    fi
    echo "$(date 2>&1)" >> /var/log/boa/mysqladmin.monitor.log
    echo "$(mysqladmin -u root proc -v 2>&1)" >> /var/log/boa/mysqladmin.monitor.log
  else
    [ -e "/root/.debug_slow_query.pid" ] && rm -f /root/.debug_slow_query.pid
    if [ ! -e "/root/.nodebug_slow_query.pid" ]; then
      mysql -u root -e "SET GLOBAL slow_query_log = 'OFF';" &> /dev/null
      touch /root/.nodebug_slow_query.pid
      [ -e "/var/log/boa/mysqladmin.monitor.log" ] && rm -f /var/log/boa/mysqladmin.monitor.log
      [ -e "/var/log/mysql/sql-slow-query.log" ] && rm -f /var/log/mysql/sql-slow-query.log
    fi
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

_if_mydumper_is_locked() {
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
  _AR_C="$(pgrep -fc aegir.sh)"
  _DR_C="$(pgrep -fc drush.php)"
  _MD_C="$(pgrep -fc mydumper)"
  if [ "${_MD_C}" -gt 0 ]; then
    if [ "${_AR_C}" -gt "${_MULTI_MX}" ]; then
      pkill -f mydumper
      pkill -f aegir.sh
      echo "$(date) TOO MANY (${_AR_C}) aegir.sh required killing mydumper" >> ${_pthOml}
      echo >> ${_pthOml}
      _incident_email_report "TOO MANY (${_AR_C}) aegir.sh required killing mydumper"
    fi
    if [ "${_DR_C}" -gt "${_MULTI_MX}" ]; then
      pkill -f mydumper
      pkill -f drush.php
      echo "$(date) TOO MANY (${_DR_C}) drush.php required killing mydumper" >> ${_pthOml}
      echo >> ${_pthOml}
      _incident_email_report "TOO MANY (${_DR_C}) drush.php required killing mydumper"
    fi
  fi
}

_mysql_flush_hosts() {
  if pgrep -f /usr/sbin/mysqld \
    && [ -e "/run/mysqld/mysqld.sock" ] \
    && [ -e "/run/mysqld/mysqld.pid" ]; then
    mysqladmin -u root flush-hosts &> /dev/null
  fi
}

_mysql_health_check_fix() {
  if ! pgrep -f /usr/sbin/mysqld \
    || [ ! -e "/run/mysqld/mysqld.sock" ] \
    || [ ! -e "/run/mysqld/mysqld.pid" ]; then
    _sql_restart "DOWN MySQL"
  fi
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

### Main start here

if [ -x "/etc/init.d/mysql" ] \
  && [ -x "/usr/sbin/mysqld" ] \
  && [ ! -e "/run/boa_mysql_auto_healing.pid" ] \
  && [ ! -e "/run/max_load.pid" ] \
  && [ ! -e "/run/critical_load.pid" ] \
  && [ ! -e "/run/mysql_restart_running.pid" ]; then
  _mysql_health_check_fix
fi

if [ -x "/etc/init.d/mysql" ] \
  && pgrep -f /usr/sbin/mysqld \
  && [ ! -e "/run/mysql_restart_running.pid" ]; then
  _mysql_high_load
  _sql_busy_detection
  _mysql_flush_hosts
  if (( $(pgrep -fc mydumper) > 0 )) && (( $(pgrep -fc mysql_backup.sh) > 0 )); then
    sleep 5
    _if_mydumper_is_locked
  fi
  _spawn_detached 'perl /var/xdrago/monitor/check/sqlcheck.pl'
fi

if [ -e "/run/boa_sql_backup.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_mysql_auto_healing.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ]; then
  _SQL_CTRL=NO
else
  _SQL_CTRL=YES
fi

if [ "${_SQL_CTRL}" = "YES" ] \
  && [ ! -e "/run/max_load.pid" ] \
  && [ ! -e "/run/critical_load.pid" ]; then
  for _iteration in {1..3}; do
    _mysql_proc_control "${_SQL_MAX_TTL}"
    sleep 15
  done
fi

echo DONE!
exit 0

