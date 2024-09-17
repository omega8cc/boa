#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/mysql.incident.log"

check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
check_root

export _B_NICE=${_B_NICE//[^0-9]/}
: "${_B_NICE:=10}"

export _SQL_MAX_TTL=${_SQL_MAX_TTL//[^0-9]/}
: "${_SQL_MAX_TTL:=3600}"

export _SQL_LOW_MAX_TTL=${_SQL_LOW_MAX_TTL//[^0-9]/}
: "${_SQL_LOW_MAX_TTL:=60}"

export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
: "${_INCIDENT_EMAIL_REPORT:=YES}"

if [ $(pgrep -f mysql.sh | wc -l) -gt 1 ]; then
  echo "Too many mysql.sh running"
  exit 0
fi

incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${pthOml}
  fi
}

sql_restart() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date 2>&1) $1 incident detected" >> ${pthOml}
  echo "$(date 2>&1) $1 incident response started" >> ${pthOml}
  killall sleep &> /dev/null
  killall php
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date 2>&1) $1 incident mysql restarted" >> ${pthOml}
  echo "$(date 2>&1) $1 incident response completed" >> ${pthOml}
  echo >> ${pthOml}
  incident_email_report "$1"
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

sql_busy_detection() {
  if [ -e "/var/log/daemon.log" ]; then
    _SQL_LOG="/var/log/daemon.log"
  else
    _SQL_LOG="/var/log/syslog"
  fi
  if [ -e "${_SQL_LOG}" ]; then
    if [ `tail --lines=10 ${_SQL_LOG} \
      | grep --count "Too many connections"` -gt "0" ]; then
      sql_restart "BUSY MySQL"
    fi
  fi
  _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
  _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
  if [ ! -z "${_IS_MYSQLD_RUNNING}" ] && [ ! -z "${_SQL_PSWD}" ]; then
    _MYSQL_CONN_TEST=$(mysql -u root -e "status" 2>&1)
    echo _MYSQL_CONN_TEST ${_MYSQL_CONN_TEST}
    if [[ "${_MYSQL_CONN_TEST}" =~ "Too many connections" ]]; then
      sql_restart "BUSY MySQL"
    fi
  fi
}

mysql_proc_kill() {
  xtime=${xtime//[^0-9]/}
  echo "Monitoring process $each by $xuser running for $xtime seconds"

  if [[ -n "$xtime" && $xtime -gt $limit ]]; then
    echo "Killing process $each by $xuser after $xtime seconds"
    xkill=$(mysqladmin -u root kill $each 2>&1)
    times=$(date)
    load=$(cat /proc/loadavg)

    # Log the load and the process killing details
    echo "$load" >> /var/xdrago/log/sql_watch.log
    echo "$times $each $xuser $xtime $xkill" >> /var/xdrago/log/sql_watch.log
  fi
}

mysql_proc_control() {
  # Log the MySQL process list if _SQLMONITOR is enabled
  if [[ "${_SQLMONITOR}" == "YES" ]]; then
    mysqladmin -u root proc -v >> /var/xdrago/log/mysqladmin.monitor.log
  fi

  # Default TTL limit in seconds (can be adjusted)
  limit=${1:-3600}

  # Get all MySQL processes and extract PID, user, and running time
  mysql_proc_list=$(mysqladmin -u root proc | awk 'NR>3 {print $2, $4, $12}')

  # Iterate over each process
  echo "$mysql_proc_list" | while read -r each xuser xtime; do
    each=${each//[^0-9]/}
    xuser=${xuser//[^0-9a-z_]/}
    xtime=${xtime//[^0-9]/}

    # Skip root user processes
    if [[ "$xuser" == "root" ]]; then
      echo "Skipping root process: $each"
      continue
    fi

    if [[ -n "$each" && "$each" -gt 5 && -n "$xtime" ]]; then
      echo "Process ID: $each, User: $xuser, Time: $xtime seconds"

      # Check if the user is listed on the problematic users list
      if [[ -e "/root/.sql.problematic.users.cnf" ]]; then
        for _XQ in $(cat /root/.sql.problematic.users.cnf | cut -d '#' -f1 | sort | uniq); do
          if [[ "$xuser" == "$_XQ" ]]; then
            echo "Problematic user detected: $xuser, applying lower limit"
            limit=${_SQL_LOW_MAX_TTL}
          fi
        done
      else
        limit=${_SQL_MAX_TTL}  # Default limit for non-problematic users
      fi

      mysql_proc_kill
    fi
  done
}

sql_busy_detection

if [ -e "/run/boa_sql_backup.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ]; then
  _SQL_CTRL=NO
else
  _SQL_CTRL=YES
fi

[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control "${_SQL_MAX_TTL}"
sleep 15
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control "${_SQL_MAX_TTL}"
sleep 15
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control "${_SQL_MAX_TTL}"
sleep 15
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control "${_SQL_MAX_TTL}"

perl /var/xdrago/monitor/check/sqlcheck.pl &> /dev/null
wait

echo DONE!
exit 0
###EOF2024###
