#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

if [ -e "/root/.disable_mysql_cleanup.cnf" ]; then
  exit 0
fi

if [ -e "/root/.proxy.cnf" ]; then
  echo "Ooops, that is a proxy server, we do not run this task on sql proxy"
  exit 0
fi

if [ $(pgrep -f mysql_cleanup.sh | grep -v "^$$" | wc -l) -gt 2 ]; then
  echo "Too many mysql_cleanup.sh running $(date 2>&1)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_IS_SQLBACKUP_RUNNING=$(ps aux | grep '[m]ysql_backup.sh' | awk '{print $2}' 2>&1)
if [ ! -z "${_IS_SQLBACKUP_RUNNING}" ]; then
  echo "Ooops, another mysql procedure/backup is running at the moment"
  exit 0
fi

_ALL_DBS_NR=$(ls /var/lib/mysql | wc -l)
if [ ! -z "${_ALL_DBS_NR}" ] && [ "${_ALL_DBS_NR}" -gt 100 ]; then
  echo "Sorry, too many databases (${_ALL_DBS_NR}) on this server for this frequent task"
  exit 0
fi

echo "INFO: Starting dbs cleanup on `date`"

[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
export _B_NICE=${_B_NICE//[^0-9]/}
: "${_B_NICE:=10}"

_SQL_CACHE_EXC_DEF="cache_bootstrap cache_discovery cache_config"

if [ -e "/root/.my.cache.exceptions.cnf" ]; then
  _SQL_CACHE_EXC_ADD=$(cat /root/.my.cache.exceptions.cnf 2>&1)
  _SQL_CACHE_EXC="${_SQL_CACHE_EXC_DEF} ${_SQL_CACHE_EXC_ADD}"
else
  _SQL_CACHE_EXC="${_SQL_CACHE_EXC_DEF}"
fi

_SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
_SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)

_create_locks() {
  echo "INFO: Creating locks for $1"
  touch /run/mysql_backup_running.pid
}

_remove_locks() {
  echo "INFO: Removing locks for $1"
  rm -f /run/mysql_backup_running.pid
}

_check_running() {
  while [ -z "${_IS_MYSQLD_RUNNING}" ] \
    || [ ! -e "/run/mysqld/mysqld.sock" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo "INFO: Waiting for MySQLD availability..."
    fi
    sleep 3
  done
}

_truncate_cache_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
  for C in ${_TABLES}; do
    _IF_SKIP_C=
    for X in ${_SQL_CACHE_EXC}; do
      if [ "${C}" = "${X}" ]; then
        _IF_SKIP_C=SKIP
      fi
    done
    if [ -z "${_IF_SKIP_C}" ]; then
      mysql ${_DB}<<EOFMYSQL
TRUNCATE ${C};
EOFMYSQL
    fi
  done
}

_truncate_watchdog_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^watchdog$ 2>&1)
  for W in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${W};
EOFMYSQL
  done
}

_truncate_accesslog_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^accesslog$ 2>&1)
  for A in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
  done
}

_truncate_batch_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^batch$ 2>&1)
  for B in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${B};
EOFMYSQL
  done
}

_truncate_queue_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^queue$ 2>&1)
  for Q in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${Q};
EOFMYSQL
  done
}

_truncate_views_data_export() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^views_data_export_index_ 2>&1)
  for V in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
DROP TABLE ${V};
EOFMYSQL
  done
mysql ${_DB}<<EOFMYSQL
TRUNCATE views_data_export_object_cache;
EOFMYSQL
}

for _DB in `mysql -e "show databases" -s | uniq | sort`; do
  if [ "${_DB}" != "Database" ] \
    && [ "${_DB}" != "information_schema" ] \
    && [ "${_DB}" != "performance_schema" ]; then
    _check_running
    _create_locks ${_DB}
    if [ "${_DB}" != "mysql" ]; then
      if [ -e "/var/lib/mysql/${_DB}/queue.ibd" ]; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/queue.ibd | grep "G" 2>&1)
        if [[ "${_IS_GB}" =~ "queue" ]]; then
          _truncate_queue_tables &> /dev/null
          echo "INFO: Truncated giant queue in ${_DB}"
        fi
      fi
      if [ -e "/var/lib/mysql/${_DB}/batch.ibd" ]; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/batch.ibd | grep "G" 2>&1)
        if [[ "${_IS_GB}" =~ "batch" ]]; then
          _truncate_batch_tables &> /dev/null
          echo "INFO: Truncated giant batch in ${_DB}"
        fi
      fi
      if [ -e "/var/lib/mysql/${_DB}/watchdog.ibd" ]; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/watchdog.ibd | grep "G" 2>&1)
        if [[ "${_IS_GB}" =~ "watchdog" ]]; then
          _truncate_watchdog_tables &> /dev/null
          echo "INFO: Truncated giant watchdog in ${_DB}"
        fi
      fi
      if [ -e "/var/lib/mysql/${_DB}/accesslog.ibd" ]; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/accesslog.ibd | grep "G" 2>&1)
        if [[ "${_IS_GB}" =~ "accesslog" ]]; then
          _truncate_accesslog_tables &> /dev/null
          echo "INFO: Truncated giant accesslog in ${_DB}"
        fi
      fi
      _truncate_views_data_export &> /dev/null
      echo "INFO: Truncated not used views_data_export in ${_DB}"
      _truncate_cache_tables &> /dev/null
      echo "INFO: All cache tables in ${_DB} truncated"
    fi
    _remove_locks ${_DB}
    echo "INFO: Cleanup completed for ${_DB}"
    echo
  fi
done

echo "INFO: Completing all dbs cleanup on `date`"
touch /var/xdrago/log/last-run-db-cleanup
rm -f /run/mysql_backup_running.pid

echo "INFO: ALL TASKS COMPLETED, BYE!"
exit 0
###EOF2024###
