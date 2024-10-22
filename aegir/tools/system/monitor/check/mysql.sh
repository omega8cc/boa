#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/xdrago/log/mysql.incident.log"

_check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

export _B_NICE=${_B_NICE//[^0-9]/}
: "${_B_NICE:=10}"

export _SQL_MAX_TTL=${_SQL_MAX_TTL//[^0-9]/}
: "${_SQL_MAX_TTL:=3600}"

export _SQL_LOW_MAX_TTL=${_SQL_LOW_MAX_TTL//[^0-9]/}
: "${_SQL_LOW_MAX_TTL:=60}"

export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
: "${_INCIDENT_EMAIL_REPORT:=YES}"

if (( $(pgrep -fc 'mysql.sh') > 2 )); then
  echo "Too many mysql.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    _hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date 2>&1)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_sql_restart() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date 2>&1) $1 incident detected" >> ${_pthOml}
  killall sleep &> /dev/null
  killall php
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date 2>&1) $1 incident Percona MySQL server restarted" >> ${_pthOml}
  echo "$(date 2>&1) $1 incident response completed" >> ${_pthOml}
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
    if [ `tail --lines=30 ${_SQL_LOG} \
      | grep --count "Too many connections"` -gt "10" ]; then
      _sql_restart "BUSY MySQL"
    fi
  fi
  if [ -e "/root/.instant.busy.mysql.action.cnf" ]; then
    _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
    _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
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
    echo "${_load}" >> /var/xdrago/log/sql_watch.log
    echo "${_times} ${_each} ${_xuser} ${_xtime} ${_xkill}" >> /var/xdrago/log/sql_watch.log
  fi
}

_mysql_proc_control() {
  # Log the MySQL process list if _SQLMONITOR is enabled
  if [[ "${_SQLMONITOR}" == "YES" ]]; then
    mysqladmin -u root proc -v >> /var/xdrago/log/mysqladmin.monitor.log
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

_sql_busy_detection

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
###EOF2024###
