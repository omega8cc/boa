#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

check_root() {
  if [ `whoami` = "root" ]; then
    chmod a+w /dev/null
    if [ ! -e "/dev/fd" ]; then
      if [ -e "/proc/self/fd" ]; then
        rm -rf /dev/fd
        ln -s /proc/self/fd /dev/fd
      fi
    fi
  else
    echo "ERROR: This script should be ran as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

n=$((RANDOM%3600+8))
echo "Waiting $n seconds 1/2 on `date` before running backup..."
sleep $n
n=$((RANDOM%1800+8))
echo "Waiting $n seconds 2/2 on `date` before running backup..."
sleep $n
echo "Starting backup on `date`"

if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
  _B_NICE=${_B_NICE//[^0-9]/}
fi
if [ -z "${_B_NICE}" ]; then
  _B_NICE=10
fi

_BACKUPDIR=/data/disk/arch/sql
_CHECK_HOST=$(uname -n 2>&1)
_DATE=$(date +%y%m%d-%H%M 2>&1)
_DOW=$(date +%u 2>&1)
_DOW=${_DOW//[^1-7]/}
_DOM=$(date +%e 2>&1)
_DOM=${_DOM//[^0-9]/}
_SAVELOCATION=${_BACKUPDIR}/${_CHECK_HOST}-${_DATE}
if [ -e "/root/.my.optimize.cnf" ]; then
  _OPTIM=YES
else
  _OPTIM=NO
fi
_VM_TEST=$(uname -a 2>&1)
if [[ "${_VM_TEST}" =~ "3.8.6-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.8.5.2-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.8.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.7.5-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.7.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.6.15-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.2.16-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
touch /var/run/boa_sql_backup.pid

create_locks() {
  echo "Creating locks.."
  #touch /var/run/boa_wait.pid
  touch /var/run/mysql_backup_running.pid
}

remove_locks() {
  echo "Removing locks.."
  #rm -f /var/run/boa_wait.pid
  rm -f /var/run/mysql_backup_running.pid
}

check_running() {
  until [ ! -z "${_IS_MYSQLD_RUNNING}" ] \
    && [ -e "/var/run/mysqld/mysqld.sock" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    echo "Waiting for MySQLD availability.."
    sleep 3
  done
}

truncate_cache_tables() {
  check_running
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
  for C in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${C};
EOFMYSQL
    sleep 1
  done
}

truncate_watchdog_tables() {
  check_running
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^watchdog$ 2>&1)
  for A in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
    sleep 1
  done
}

truncate_accesslog_tables() {
  check_running
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^accesslog$ 2>&1)
  for A in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
    sleep 1
  done
}

truncate_queue_tables() {
  check_running
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^queue$ 2>&1)
  for Q in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${Q};
EOFMYSQL
    sleep 1
  done
}

repair_this_database() {
  check_running
  mysqlcheck --repair --silent ${_DB}
}

optimize_this_database() {
  check_running
  _TABLES=$(mysql ${_DB} -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
OPTIMIZE TABLE ${T};
EOFMYSQL
  done
}

convert_to_innodb() {
  check_running
  _TABLES=$(mysql ${_DB} -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
mysql ${_DB}<<EOFMYSQL
ALTER TABLE ${T} ENGINE=INNODB;
EOFMYSQL
  done
}

backup_this_database() {
  n=$((RANDOM%15+5))
  echo waiting ${n} sec
  sleep ${n}
  check_running
  mysqldump \
    --single-transaction \
    --quick \
    --no-autocommit \
    --skip-add-locks \
    --hex-blob ${_DB} \
    | bzip2 -c > ${_SAVELOCATION}/${_DB}.sql.bz2
}

[ ! -a ${_SAVELOCATION} ] && mkdir -p ${_SAVELOCATION};

if [ "${_DB_SERIES}" = "10.3" ] \
  || [ "${_DB_SERIES}" = "10.2" ] \
  || [ "${_DB_SERIES}" = "10.1" ] \
  || [ "${_DB_SERIES}" = "5.7" ]; then
  check_running
  mysql -u root -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
  mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
  mysql -u root -e "SET GLOBAL innodb_io_capacity = 8000;" &> /dev/null
  mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
fi

for _DB in `mysql -e "show databases" -s | uniq | sort`; do
  if [ "${_DB}" != "Database" ] \
    && [ "${_DB}" != "information_schema" ] \
    && [ "${_DB}" != "performance_schema" ]; then
    check_running
    create_locks
    if [ "${_DB}" != "mysql" ]; then
      if [ -e "/var/lib/mysql/${_DB}/watchdog.ibd" ]; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/watchdog.ibd | grep "G" 2>&1)
        if [[ "${_IS_GB}" =~ "watchdog" ]]; then
          truncate_watchdog_tables &> /dev/null
          echo "Truncated giant watchdog in ${_DB}"
        fi
      fi
      # truncate_accesslog_tables &> /dev/null
      # echo "Truncated not used accesslog in ${_DB}"
      # truncate_queue_tables &> /dev/null
      # echo "Truncated queue table in ${_DB}"
      _CACHE_CLEANUP=NONE
      if [ "${_DOW}" = "6" ] && [ -e "/root/.my.batch_innodb.cnf" ]; then
        repair_this_database &> /dev/null
        echo "Repair task for ${_DB} completed"
        truncate_cache_tables &> /dev/null
        echo "All cache tables in ${_DB} truncated"
        convert_to_innodb &> /dev/null
        echo "InnoDB conversion task for ${_DB} completed"
        _CACHE_CLEANUP=DONE
      fi
      if [ "${_OPTIM}" = "YES" ] \
        && [ "${_DOW}" = "7" ] \
        && [ "${_DOM}" -ge "24" ] \
        && [ "${_DOM}" -lt "31" ]; then
        repair_this_database &> /dev/null
        echo "Repair task for ${_DB} completed"
        truncate_cache_tables &> /dev/null
        echo "All cache tables in ${_DB} truncated"
        optimize_this_database &> /dev/null
        echo "Optimize task for ${_DB} completed"
        _CACHE_CLEANUP=DONE
      fi
      if [ "${_CACHE_CLEANUP}" != "DONE" ]; then
        truncate_cache_tables &> /dev/null
        echo "All cache tables in ${_DB} truncated"
      fi
    fi
    backup_this_database &> /dev/null
    remove_locks
    echo "Backup completed for ${_DB}"
    echo " "
  fi
done

if [ "${_OPTIM}" = "YES" ] \
  && [ "${_DOW}" = "7" ] \
  && [ "${_DOM}" -ge "24" ] \
  && [ "${_DOM}" -lt "31" ] \
  && [ -e "/root/.my.restart_after_optimize.cnf" ] \
  && [ ! -e "/var/run/boa_run.pid" ]; then
  ionice -c2 -n2 -p $$
  if [ "${_DB_SERIES}" = "10.3" ] \
    || [ "${_DB_SERIES}" = "10.2" ] \
    || [ "${_DB_SERIES}" = "10.1" ] \
    || [ "${_DB_SERIES}" = "5.7" ]; then
    check_running
    mysql -u root -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
    mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
    mysql -u root -e "SET GLOBAL innodb_io_capacity = 8000;" &> /dev/null
    mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
  fi
  bash /var/xdrago/move_sql.sh
fi

ionice -c2 -n7 -p $$
find ${_BACKUPDIR} -mtime +6 -type d -exec rm -rf {} \;
echo "Backups older than 7 days deleted"

chmod 600 ${_BACKUPDIR}/*/*
chmod 700 ${_BACKUPDIR}/*
chmod 700 ${_BACKUPDIR}
chmod 700 /data/disk/arch
echo "Permissions fixed"

rm -f /var/run/boa_sql_backup.pid
touch /var/xdrago/log/last-run-backup
echo "ALL TASKS COMPLETED"
exit 0
###EOF2019###
