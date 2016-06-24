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

_BACKUPDIR=/data/disk/arch/sql
_CHECK_HOST=$(uname -n 2>&1)
_DATE=$(date +%y%m%d-%H%M 2>&1)
_SAVELOCATION=${_BACKUPDIR}/${_CHECK_HOST}-$_DATE
if [ -e "/root/.my.optimize.cnf" ]; then
  _OPTIM=YES
else
  _OPTIM=NO
fi
_VM_TEST=$(uname -a 2>&1)
if [[ "${_VM_TEST}" =~ "3.8.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.7.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.6.15-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.2.16-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
touch /var/run/boa_sql_backup.pid

truncate_cache_tables() {
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
  for C in ${_TABLES}; do
mysql --default-character-set=utf8 ${_DB}<<EOFMYSQL
TRUNCATE ${C};
EOFMYSQL
  done
}

truncate_watchdog_tables() {
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^watchdog$ 2>&1)
  for A in ${_TABLES}; do
mysql --default-character-set=utf8 ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
  done
}

truncate_accesslog_tables() {
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^accesslog$ 2>&1)
  for A in ${_TABLES}; do
mysql --default-character-set=utf8 ${_DB}<<EOFMYSQL
TRUNCATE ${A};
EOFMYSQL
  done
}

truncate_queue_tables() {
  _TABLES=$(mysql ${_DB} -e "show tables" -s | grep ^queue$ 2>&1)
  for Q in ${_TABLES}; do
mysql --default-character-set=utf8 ${_DB}<<EOFMYSQL
TRUNCATE ${Q};
EOFMYSQL
  done
}

optimize_this_database() {
  _TABLES=$(mysql ${_DB} -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
mysql --default-character-set=utf8 ${_DB}<<EOFMYSQL
OPTIMIZE TABLE ${T};
EOFMYSQL
  done
}

backup_this_database() {
  n=$((RANDOM%15+5))
  echo waiting ${n} sec
  sleep ${n}
  mysqldump \
    --single-transaction \
    --quick \
    --no-autocommit \
    --default-character-set=utf8 \
    --hex-blob ${_DB} \
    | gzip -c > ${_SAVELOCATION}/${_DB}.sql.gz
}

[ ! -a ${_SAVELOCATION} ] && mkdir -p ${_SAVELOCATION};

for _DB in `mysql -e "show databases" -s | uniq | sort`; do
  if [ "${_DB}" != "Database" ] \
    && [ "${_DB}" != "information_schema" ] \
    && [ "${_DB}" != "performance_schema" ]; then
    if [ "${_DB}" != "mysql" ]; then
      truncate_cache_tables &> /dev/null
      _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/watchdog* | grep "G" 2>&1)
      if [[ "${_IS_GB}" =~ "watchdog" ]]; then
        truncate_watchdog_tables &> /dev/null
        echo "Truncated giant watchdog for ${_DB}"
      fi
      if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        || [ "${_VMFAMILY}" = "VS" ]; then
        truncate_accesslog_tables &> /dev/null
        echo "Truncated not used accesslog for ${_DB}"
        truncate_queue_tables &> /dev/null
        echo "Truncated queue for ${_DB}"
      fi
      echo "All cache tables truncated in ${_DB}"
      if [ "${_OPTIM}" = "YES" ]; then
        optimize_this_database &> /dev/null
        echo "Optimize completed for ${_DB}"
      fi
    fi
    backup_this_database &> /dev/null
    echo "Backup completed for ${_DB}"
    echo " "
  fi
done

if [ "${_OPTIM}" = "YES" ] && [ ! -e "/var/run/boa_run.pid" ]; then
  ionice -c2 -n2 -p $$
  touch /var/run/boa_wait.pid
  touch /var/xdrago/log/mysql_restart_running.pid
  sleep 10
  service mysql restart
  sleep 3
  rm -f /var/run/boa_wait.pid
  rm -f /var/xdrago/log/mysql_restart_running.pid
fi

ionice -c2 -n7 -p $$
find ${_BACKUPDIR} -mtime +8 -type d -exec rm -rf {} \;
echo "Backups older than 8 days deleted"

chmod 600 /data/disk/arch/sql/*/*
chmod 700 /data/disk/arch/sql/*
chmod 700 /data/disk/arch/sql
chmod 700 /data/disk/arch
echo "Permissions fixed"

rm -f /var/run/boa_sql_backup.pid
touch /var/xdrago/log/last-run-backup
echo "COMPLETED ALL"
exit 0
###EOF2016###
