#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/opt/php55/bin:/opt/php54/bin:/opt/php53/bin:/opt/php52/bin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

action()
{
NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
CTL_LOAD=1500
if [ $NOW_LOAD -lt $CTL_LOAD ] ; then
echo load is $NOW_LOAD while maxload is $CTL_LOAD
echo ... now doing CTL...
/usr/bin/mysql --default-character-set=utf8 mysql<<EOFMYSQL
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

if [ -e "/var/run/boa_wait.pid" ] ; then
  touch /var/xdrago/log/wait-purge
  exit
else
  action
  touch /var/xdrago/log/last-run-purge
fi
###EOF2014###
