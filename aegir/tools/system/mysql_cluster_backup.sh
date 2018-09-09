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

[ -e "/root/.proxy.cnf" ] && exit 0
[ ! -e "/root/.my.cluster_write_node.txt" ] && exit 0
[ ! -e "/root/.my.cluster_root_pwd.txt" ] && exit 0

if [ -e "/root/.my.cluster_write_node.txt" ]; then
  _SQL_HOST=$(cat /root/.my.cluster_write_node.txt 2>&1)
  _SQL_HOST=$(echo -n ${_SQL_HOST} | tr -d "\n" 2>&1)
fi
if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
  _SQL_PSWD=$(cat /root/.my.cluster_root_pwd.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
fi
_SQL_PORT="3306"
_C_SQL="mysql --user=root --password=${_SQL_PSWD} --host=${_SQL_HOST} --port=${_SQL_PORT} --protocol=tcp"

echo "SQL --host=${_SQL_HOST} --port=${_SQL_PORT}"
n=$((RANDOM%3600+8))
echo "Waiting $n seconds on `date` before running backup..."
sleep $n
echo "Starting backup on `date`"

if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
  _B_NICE=${_B_NICE//[^0-9]/}
fi
if [ -z "${_B_NICE}" ]; then
  _B_NICE=10
fi

_BACKUPDIR=/data/disk/arch/cluster
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
touch /var/run/boa_sql_cluster_backup.pid

create_locks() {
  echo "Creating locks.."
  #touch /var/run/boa_wait.pid
  touch /var/run/mysql_cluster_backup_running.pid
}

remove_locks() {
  echo "Removing locks.."
  #rm -f /var/run/boa_wait.pid
  rm -f /var/run/mysql_cluster_backup_running.pid
}

check_running() {
  until [ ! -z "${_IS_PROXYSQL_RUNNING}" ] \
    && [ -e "/var/lib/proxysql/proxysql.pid" ]; do
    _IS_PROXYSQL_RUNNING=$(ps aux | grep '[p]roxysql' | awk '{print $2}' 2>&1)
    echo "Waiting for ProxySQL availability.."
    sleep 3
  done
}

truncate_cache_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
  for C in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${C};
EOFMYSQL
    sleep 1
  done
}

truncate_watchdog_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^watchdog$ 2>&1)
  for A in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
    sleep 1
  done
}

truncate_accesslog_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^accesslog$ 2>&1)
  for A in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
    sleep 1
  done
}

truncate_queue_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^queue$ 2>&1)
  for Q in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${Q};
EOFMYSQL
    sleep 1
  done
}

repair_this_database() {
  check_running
  mysqlcheck --host=${_SQL_HOST} --port=${_SQL_PORT} --protocol=tcp --user=root --repair --silent ${_DB}
}

optimize_this_database() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
OPTIMIZE TABLE ${T};
EOFMYSQL
  done
}

convert_to_innodb() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
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
    --user=root \
    --password=${_SQL_PSWD} \
    --host=${_SQL_HOST} \
    --port=${_SQL_PORT} \
    --protocol=tcp \
    --single-transaction \
    --quick \
    --no-autocommit \
    --skip-add-locks \
    --hex-blob ${_DB} \
    | bzip2 -c > ${_SAVELOCATION}/${_DB}.sql.bz2
}

[ ! -a ${_SAVELOCATION} ] && mkdir -p ${_SAVELOCATION};

if [ "${_DB_SERIES}" = "10.2" ] \
  || [ "${_DB_SERIES}" = "10.1" ]; then
  check_running
  ${_C_SQL} -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
  ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
  ${_C_SQL} -e "SET GLOBAL innodb_io_capacity = 8000;" &> /dev/null
  ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
fi

for _DB in `${_C_SQL} -e "show databases" -s | uniq | sort`; do
  if [ "${_DB}" != "Database" ] \
    && [ "${_DB}" != "information_schema" ] \
    && [ "${_DB}" != "performance_schema" ]; then
    check_running
    create_locks
    if [ "${_DB}" != "mysql" ]; then
      _IS_GB=$(${_C_SQL} --skip-column-names --silent -e "SELECT table_name 'Table Name', round(((data_length + index_length)/1024/1024),0)
'Table Size (MB)' FROM information_schema.TABLES WHERE table_schema = '${_DB}' AND table_name ='watchdog';" | cut -d'/' -f1 | awk '{ print $2}' | sed "s/[\/\s+]//g" | bc 2>&1)
      _IS_GB=${_IS_GB//[^0-9]/}
      _SQL_MAX_LIMIT="1024"
      if [ ! -z "${_IS_GB}" ]; then
        if [ "${_IS_GB}" -gt "${_SQL_MAX_LIMIT}" ]; then
          truncate_watchdog_tables &> /dev/null
          echo "Truncated giant ${_IS_GB} watchdog in ${_DB}"
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

ionice -c2 -n7 -p $$
find ${_BACKUPDIR} -mtime +30 -type d -exec rm -rf {} \;
echo "Backups older than 31 days deleted"

chmod 600 ${_BACKUPDIR}/*/*
chmod 700 ${_BACKUPDIR}/*
chmod 700 ${_BACKUPDIR}
chmod 700 /data/disk/arch
echo "Permissions fixed"

rm -f /var/run/boa_sql_cluster_backup.pid
touch /var/xdrago/log/last-run-cluster-backup
echo "ALL TASKS COMPLETED"
exit 0
###EOF2018###
