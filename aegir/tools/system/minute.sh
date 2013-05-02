#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if test -f /root/.high_traffic.cnf ; then
  true
else
  perl /var/xdrago/monitor/check/segfault_alert
fi

killit()
{
  if [ "$xtime" != "Time" ] && [ "$xuser" != "root" ] && [[ "$xtime" -gt "$limit" ]] ; then
    xkill=`mysqladmin kill $each`
    times=`date`
    echo $times $each $xuser $xtime $xkill
    echo "$times $each $xuser $xtime $xkill" >> /var/xdrago/log/sql_watch.log
  fi
}

action()
{
limit=3600
xkill=null
for each in `mysqladmin proc | awk '{print $2, $4, $8, $12}' | awk '{print $1}'`;
do
  xtime=`mysqladmin proc | awk '{print $2, $4, $8, $12}' | grep $each | awk '{print $4}'`
  xuser=`mysqladmin proc | awk '{print $2, $4, $8, $12}' | grep $each | awk '{print $2}'`
  if [ "$xtime" != "Time" ] ; then
    if [ "$xuser" = "xabuse" ] ; then
      limit=60
      killit
    else
      limit=3600
      killit
    fi
  fi;
done
}

action
echo watcher 1
sleep 10

action
echo watcher 2
sleep 10

action
echo watcher 3
sleep 10

action
echo watcher 4
sleep 10

action
echo watcher 5
sleep 10

action
echo watcher 6
sleep 5
perl /var/xdrago/monitor/check/escapecheck
perl /var/xdrago/monitor/check/hackcheck
perl /var/xdrago/monitor/check/hackftp
perl /var/xdrago/monitor/check/hackmail
perl /var/xdrago/monitor/check/scan_nginx
perl /var/xdrago/monitor/check/locked
perl /var/xdrago/monitor/check/sqlcheck
echo DONE!
###EOF2013###
