#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
BACKUPDIR=/data/disk/arch/sql
HOST=`uname -n`
DATE=`date +%y%m%d-%H%M`
SAVELOCATION=$BACKUPDIR/$HOST-$DATE
if [ -e "/root/.my.optimize.cnf" ] ; then
  OPTIM=YES
else
  OPTIM=NO
fi
_VM_TEST=`uname -a 2>&1`
if [[ "$_VM_TEST" =~ beng ]] ; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
touch /var/run/boa_sql_backup.pid

truncate_cache_tables () {
  TABLES=`mysql $DB -e "show tables" -s | grep ^cache | uniq | sort`
  for C in $TABLES; do
mysql --default-character-set=utf8 $DB<<EOFMYSQL
TRUNCATE $C;
EOFMYSQL
  done
}

truncate_accesslog_tables () {
  TABLES=`mysql $DB -e "show tables" -s | grep ^accesslog$`
  for A in $TABLES; do
mysql --default-character-set=utf8 $DB<<EOFMYSQL
TRUNCATE $A;
EOFMYSQL
  done
}

truncate_queue_tables () {
  TABLES=`mysql $DB -e "show tables" -s | grep ^queue$`
  for A in $TABLES; do
mysql --default-character-set=utf8 $DB<<EOFMYSQL
TRUNCATE $A;
EOFMYSQL
  done
}

optimize_this_database () {
  TABLES=`mysql $DB -e "show tables" -s | uniq | sort`
  for T in $TABLES; do
mysql --default-character-set=utf8 $DB<<EOFMYSQL
OPTIMIZE TABLE $T;
EOFMYSQL
  done
}

backup_this_database () {
  n=$((RANDOM%15+5))
  echo waiting $n sec
  sleep $n
  mysqldump --opt --skip-lock-tables --order-by-primary --single-transaction --default-character-set=utf8 -Q --hex-blob $DB | gzip -c > $SAVELOCATION/$DB.sql.gz
}

[ ! -a $SAVELOCATION ] && mkdir -p $SAVELOCATION ;

for DB in `mysql -e "show databases" -s | uniq | sort`
do
  if [ "$DB" != "Database" ] && [ "$DB" != "information_schema" ] && [ "$DB" != "performance_schema" ] ; then
    if [ "$DB" != "mysql" ] ; then
      truncate_cache_tables &> /dev/null
      if [[ "$HOST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
        truncate_accesslog_tables &> /dev/null
        echo "Truncated not used accesslog for $DB"
        truncate_queue_tables &> /dev/null
        echo "Truncated queue for $DB"
      fi
      echo "All cache tables truncated in $DB"
      if [ "$OPTIM" = "YES" ] ; then
        optimize_this_database &> /dev/null
        echo "Optimize completed for $DB"
      fi
    fi
    backup_this_database &> /dev/null
    echo "Backup completed for $DB"
    echo " "
  fi
done

if [ "$OPTIM" = "YES" ] ; then
  touch /var/run/boa_wait.pid
  touch /var/xdrago/log/mysql_restart_running.pid
  sleep 3
  /etc/init.d/mysql restart
  sleep 3
  rm -f /var/run/boa_wait.pid
  rm -f /var/xdrago/log/mysql_restart_running.pid
fi

find $BACKUPDIR -mtime +8 -type d -exec rm -rf {} \;
echo "Backups older than 8 days deleted"

chmod 600 /data/disk/arch/sql/*/*
chmod 700 /data/disk/arch/sql/*
chmod 700 /data/disk/arch/sql
chmod 700 /data/disk/arch
echo "Permissions fixed"

rm -f /var/run/boa_run.pid
rm -f /var/run/boa_sql_backup.pid
rm -f /var/run/boa_wait.pid
rm -f /var/run/daily-fix.pid
rm -f /var/run/manage_ltd_users.pid
rm -f /var/run/manage_rvm_users.pid
rm -f /var/run/task_runner.pid
touch /var/xdrago/log/last-run-backup
echo "COMPLETED ALL"
exit 0
###EOF2014###
