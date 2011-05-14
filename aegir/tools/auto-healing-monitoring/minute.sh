#!/bin/bash

perl /var/xdrago/firewall/check/hackcheck
perl /var/xdrago/firewall/check/hackmail
perl /var/xdrago/firewall/check/hackftp
perl /var/xdrago/firewall/check/scan_nginx
perl /var/xdrago/firewall/check/sqlcheck

action()
{
limit=300
xkill=null
for each in `mysqladmin proc | awk '{print $2, $4, $8, $12}' | awk '{print $1}'`;
do
  xtime=`mysqladmin proc | awk '{print $2, $4, $8, $12}' | grep $each | awk '{print $4}'`
  xuser=`mysqladmin proc | awk '{print $2, $4, $8, $12}' | grep $each | awk '{print $2}'`
  if [ "$xtime" != "Time" ] && [ "$xuser" != "root" ] && [[ "$xtime" -gt "$limit" ]] ; then
    xkill=`mysqladmin kill $each`
    times=`date`
    echo $times $each $xuser $xtime $xkill
    echo "$times $each $xuser $xtime $xkill" >> /var/xdrago/log/sql_watch.log
  fi;
done
}

action
sleep 15
action
sleep 15
action
sleep 15
action

echo DONE!
