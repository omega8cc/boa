#!/bin/bash

###-------------SYSTEM-----------------###

action()
{
for Runner in `find /var/xdrago -maxdepth 1 -type f | grep run- | uniq | sort`
do
  NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
  CTL_LOAD=288
  if [ $NOW_LOAD -lt $CTL_LOAD ]; then
    echo load is $NOW_LOAD while maxload is $CTL_LOAD
    echo running $Runner
    bash $Runner
    echo waiting 2 sec
    sleep 2
    echo CTL done
  else
    echo load is $NOW_LOAD while maxload is $CTL_LOAD
    echo ...we have to wait...
  fi
done
}

###-------------SYSTEM-----------------###

if test -f /var/xdrago/log/optimize_mysql_ao.pid ; then
  touch /var/xdrago/log/wait-runner
  exit
else
  action
fi


