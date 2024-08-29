#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
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

_IS_SQLBACKUP_RUNNING=$(ps aux | grep '[m]ysql_backup.sh' | awk '{print $2}' 2>&1)
if [ ! -z "${_IS_SQLBACKUP_RUNNING}" ]; then
  exit 0
fi

if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
  _SQL_PSWD=$(cat /root/.my.cluster_root_pwd.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
fi

if [ -e "/root/.my.cluster_backup_proxysql.txt" ]; then
  _SQL_PORT="6033"
  _SQL_HOST="127.0.0.1"
else
  _SQL_PORT="3306"
  if [ -e "/root/.my.cluster_write_node.txt" ]; then
    _SQL_HOST=$(cat /root/.my.cluster_write_node.txt 2>&1)
    _SQL_HOST=$(echo -n ${_SQL_HOST} | tr -d "\n" 2>&1)
  fi
  [ -z ${_SQL_HOST} ] && _SQL_HOST="127.0.0.1" && _SQL_PORT="3306"
fi

_C_SQL="mysql --user=root --password=${_SQL_PSWD} --host=${_SQL_HOST} --port=${_SQL_PORT} --protocol=tcp"

echo "SQL --host=${_SQL_HOST} --port=${_SQL_PORT}"
n=$((RANDOM%600+8))
echo "INFO: Waiting $n seconds on `date` before running backup..."
sleep $n
echo "INFO: Starting backup on `date`"

if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
  _B_NICE=${_B_NICE//[^0-9]/}
fi
if [ -z "${_B_NICE}" ]; then
  _B_NICE=10
fi

_SQL_CACHE_EXC_DEF="cache_bootstrap cache_discovery cache_config"

if [ -e "/root/.my.cache.exceptions.cnf" ]; then
  _SQL_CACHE_EXC_ADD=$(cat /root/.my.cache.exceptions.cnf 2>&1)
  _SQL_CACHE_EXC="${_SQL_CACHE_EXC_DEF} ${_SQL_CACHE_EXC_ADD}"
else
  _SQL_CACHE_EXC="${_SQL_CACHE_EXC_DEF}"
fi

_BACKUPDIR=/data/disk/arch/cluster
_CHECK_HOST=$(uname -n 2>&1)
_DATE=$(date +%y%m%d-%H%M%S 2>&1)
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
if [[ "${_VM_TEST}" =~ "-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
touch /run/boa_sql_cluster_backup.pid

create_locks() {
  echo "Creating locks for $1"
  touch /run/mysql_cluster_backup_running.pid
}

remove_locks() {
  echo "Removing locks for $1"
  rm -f /run/mysql_cluster_backup_running.pid
}

check_running() {
  _IS_PROXYSQL_RUNNING=$(ps aux | grep '[p]roxysql' | awk '{print $2}' 2>&1)
  while [ -z "${_IS_PROXYSQL_RUNNING}" ] \
    || [ ! -e "/var/lib/proxysql/proxysql.pid" ]; do
    _IS_PROXYSQL_RUNNING=$(ps aux | grep '[p]roxysql' | awk '{print $2}' 2>&1)
    echo "Waiting for ProxySQL availability..."
    sleep 3
  done
}

truncate_cache_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
  for C in ${_TABLES}; do
    _IF_SKIP_C=
    for X in ${_SQL_CACHE_EXC}; do
      if [ "${C}" = "${X}" ]; then
        _IF_SKIP_C=SKIP
      fi
    done
    if [ -z "${_IF_SKIP_C}" ]; then
      ${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${C};
EOFMYSQL
    fi
  done
}

truncate_watchdog_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^watchdog$ 2>&1)
  for W in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${W};
EOFMYSQL
  done
}

truncate_accesslog_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^accesslog$ 2>&1)
  for A in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
  done
}

truncate_batch_tables() {
  check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^batch$ 2>&1)
  for B in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${B};
EOFMYSQL
  done
}

truncate_queue_tables() {
  check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^queue$ 2>&1)
  for Q in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE ${Q};
EOFMYSQL
  done
}

truncate_views_data_export() {
  check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^views_data_export_index_ 2>&1)
  for V in ${_TABLES}; do
${_C_SQL} ${_DB}<<EOFMYSQL
DROP TABLE ${V};
EOFMYSQL
  done
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE views_data_export_object_cache;
EOFMYSQL
}

repair_this_database() {
  check_running
  mysqlcheck --host=${_SQL_HOST} --port=${_SQL_PORT} --protocol=tcp -u root --auto-repair --silent ${_DB}
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

backup_this_database_with_mydumper() {
  check_running
  if [ ! -d "${_SAVELOCATION}/${_DB}" ]; then
    mkdir -p ${_SAVELOCATION}/${_DB}
  fi
  mydumper \
    --database=${_DB} \
    --host=${_SQL_HOST} \
    --user=root \
    --password=${_SQL_PSWD} \
    --port=${_SQL_PORT} \
    --outputdir=${_SAVELOCATION}/${_DB}/ \
    --rows=50000 \
    --build-empty-files \
    --threads=4 \
    --less-locking \
    --long-query-guard=900 \
    --verbose=1
}

backup_this_database_with_mysqldump() {
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
    --no-tablespaces \
    --hex-blob ${_DB} \
    > ${_SAVELOCATION}/${_DB}.sql
}

compress_backup() {
  if [ "${_MYQUICK_USE}" = "YES" ]; then
    for DbPath in `find ${_SAVELOCATION}/ -maxdepth 1 -mindepth 1 | sort`; do
      if [ -e "${DbPath}/metadata" ]; then
        DbName=$(echo ${DbPath} | cut -d'/' -f7 | awk '{ print $1}' 2>&1)
        cd ${_SAVELOCATION}
        tar cvfj ${DbName}-${_DATE}.tar.bz2 ${DbName} &> /dev/null
        rm -f -r ${DbName}
      fi
    done
    chmod 600 ${_SAVELOCATION}/*
    chmod 700 ${_SAVELOCATION}
    chmod 700 /data/disk/arch
    echo "INFO: Permissions fixed"
  else
    bzip2 ${_SAVELOCATION}/*.sql
    chmod 600 ${_BACKUPDIR}/*/*
    chmod 700 ${_BACKUPDIR}/*
    chmod 700 ${_BACKUPDIR}
    chmod 700 /data/disk/arch
    echo "INFO: Permissions fixed"
  fi
}

[ ! -a ${_SAVELOCATION} ] && mkdir -p ${_SAVELOCATION};

check_mysql_version() {
  _DBS_TEST=$(which mysql 2>&1)
  if [ ! -z "${_DBS_TEST}" ]; then
    _DB_SERVER_TEST=$(mysql -V 2>&1)
  fi
  if [[ "${_DB_SERVER_TEST}" =~ "Ver 8.3." ]]; then
    _DB_V=8.3
  elif [[ "${_DB_SERVER_TEST}" =~ "Ver 8.0." ]]; then
    _DB_V=8.0
  elif [[ "${_DB_SERVER_TEST}" =~ "Distrib 5.7." ]]; then
    _DB_V=5.7
  fi
  if [ ! -z "${_DB_V}" ]; then
    ${_C_SQL} -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_change_buffering = 'none';" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_io_capacity = 2000;" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_io_capacity_max = 4000;" &> /dev/null
    if [ "${_DB_V}" = "5.7" ]; then
      ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
      ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_now = ON;" &> /dev/null
    fi
    ${_C_SQL} -e -e "SET GLOBAL innodb_fast_shutdown = 1;" &> /dev/null
  fi
}

check_running
check_mysql_version

_MYQUICK_USE=NO
if [ -x "/usr/local/bin/mydumper" ]; then
  _MYQUICK_ITD=$(mydumper -V 2>&1 \
    | tr -d "\n" \
    | tr -d "," \
    | tr -d "v" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  _DB_V=$(mysql -V 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f6 \
    | awk '{ print $1}' \
    | cut -d"-" -f1 \
    | awk '{ print $1}' \
    | sed "s/[\,']//g" 2>&1)
  if [ "${_DB_V}" = "Linux" ]; then
    _DB_V=$(mysql -V 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f4 \
      | awk '{ print $1}' \
      | cut -d"-" -f1 \
      | awk '{ print $1}' \
      | sed "s/[\,']//g" 2>&1)
  fi
  _MD_V=$(mydumper --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f6 \
    | awk '{ print $1}' \
    | cut -d"-" -f1 \
    | awk '{ print $1}' \
    | sed "s/[\,']//g" 2>&1)
  if [ ! -e "/root/.mysql.force.legacy.backup.cnf" ]; then
    _MYQUICK_USE=YES
    echo "INFO: Installed MyQuick ${_MYQUICK_ITD} for ${_MD_V} (${_DB_V})"
  fi
fi

for _DB in `${_C_SQL} -e "show databases" -s | uniq | sort`; do
  if [ "${_DB}" != "Database" ] \
    && [ "${_DB}" != "information_schema" ] \
    && [ "${_DB}" != "performance_schema" ]; then
    check_running
    create_locks ${_DB}
    if [ "${_DB}" != "mysql" ]; then
      _IS_GB=$(${_C_SQL} --skip-column-names --silent -e "SELECT table_name 'Table Name', round(((data_length + index_length)/1024/1024),0)
'Table Size (MB)' FROM information_schema.TABLES WHERE table_schema = '${_DB}' AND table_name ='watchdog';" | cut -d'/' -f1 | awk '{ print $2}' | sed "s/[\/\s+]//g" | bc 2>&1)
      _IS_GB=${_IS_GB//[^0-9]/}
      _SQL_MAX_LIMIT="1024"
      if [ ! -z "${_IS_GB}" ]; then
        if [ "${_IS_GB}" -gt "${_SQL_MAX_LIMIT}" ]; then
          truncate_watchdog_tables &> /dev/null
          echo "INFO: Truncated giant ${_IS_GB} watchdog in ${_DB}"
        fi
      fi
      # truncate_accesslog_tables &> /dev/null
      # echo "Truncated not used accesslog in ${_DB}"
      # truncate_queue_tables &> /dev/null
      # echo "Truncated queue table in ${_DB}"
      _CACHE_CLEANUP=NONE
      # if [ "${_DOW}" = "6" ] && [ -e "/root/.my.batch_innodb.cnf" ]; then
      #   repair_this_database &> /dev/null
      #   echo "Repair task for ${_DB} completed"
      #   truncate_cache_tables &> /dev/null
      #   echo "All cache tables in ${_DB} truncated"
      #   convert_to_innodb &> /dev/null
      #   echo "InnoDB conversion task for ${_DB} completed"
      #   _CACHE_CLEANUP=DONE
      # fi
      # if [ "${_OPTIM}" = "YES" ] \
      #   && [ "${_DOW}" = "7" ] \
      #   && [ "${_DOM}" -ge "24" ] \
      #   && [ "${_DOM}" -lt "31" ]; then
      #   repair_this_database &> /dev/null
      #   echo "Repair task for ${_DB} completed"
      #   truncate_cache_tables &> /dev/null
      #   echo "All cache tables in ${_DB} truncated"
      #   optimize_this_database &> /dev/null
      #   echo "Optimize task for ${_DB} completed"
      #   _CACHE_CLEANUP=DONE
      # fi
      if [ "${_CACHE_CLEANUP}" != "DONE" ]; then
        truncate_cache_tables &> /dev/null
        echo "INFO: All cache tables in ${_DB} truncated"
      fi
    fi
    if [ "${_MYQUICK_USE}" = "YES" ]; then
      backup_this_database_with_mydumper &> /dev/null
    else
      backup_this_database_with_mysqldump &> /dev/null
    fi
    remove_locks ${_DB}
    echo "INFO: Backup completed for ${_DB}"
    echo
  fi
done

echo "INFO: Completing all dbs backups on `date`"
rm -f /run/boa_sql_cluster_backup.pid
touch /var/xdrago/log/last-run-cluster-backup

echo "INFO: Starting dbs backup compress on `date`"
compress_backup &> /dev/null
echo "INFO: Completing dbs backup compress on `date`"

echo "INFO: Starting dbs backup cleanup on `date`"
_DB_BACKUPS_TTL=${_DB_BACKUPS_TTL//[^0-9]/}
if [ -z "${_DB_BACKUPS_TTL}" ]; then
  _DB_BACKUPS_TTL="30"
fi
find ${_BACKUPDIR} -mtime +${_DB_BACKUPS_TTL} -type d -exec rm -rf {} \;
echo "INFO: Backups older than ${_DB_BACKUPS_TTL} days deleted"

echo "INFO: ALL TASKS COMPLETED, BYE!"
exit 0
###EOF2024###
