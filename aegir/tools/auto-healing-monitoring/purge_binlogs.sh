#!/bin/bash

action()
{
NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
CTL_LOAD=888
if [ $NOW_LOAD -lt $CTL_LOAD ] ; then
echo load is $NOW_LOAD while maxload is $CTL_LOAD
echo ... now doing CTL...
/usr/bin/mysql --default-character-set=utf8 --password=NdKBu34erty325r6mUHxWy -h localhost --port=3306 -u root mysql<<EOFMYSQL
PURGE MASTER LOGS BEFORE DATE_SUB( NOW( ), INTERVAL 1 HOUR);
EOFMYSQL
echo COMPLETED ALL
touch /var/xdrago/log/purge_binlogs.done
echo CTL done
else
echo load is $NOW_LOAD while maxload is $CTL_LOAD
echo ...we have to wait...
fi
}

if test -f /var/run/boa_wait.pid ; then
  touch /var/xdrago/log/wait-purge
  exit
else
  action
  touch /var/xdrago/log/last-run-purge
fi
###EOF2012###
