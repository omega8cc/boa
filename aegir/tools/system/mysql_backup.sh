#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
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

optimize_this_database () {
  TABLES=`mysql $DB -e "show tables" -s | uniq | sort`
  for T in $TABLES; do
mysql --default-character-set=utf8 $DB<<EOFMYSQL
OPTIMIZE TABLE $T;
EOFMYSQL
  done
}

backup_this_database () {
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

/etc/init.d/redis-server stop
killall -9 redis-server
rm -f /var/run/redis.pid
rm -f /var/lib/redis/*
/etc/init.d/redis-server start
echo "Redis server restarted"

touch /var/xdrago/log/last-run-backup
echo "COMPLETED ALL"
###EOF2013###
