#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games

###-------------SYSTEM-----------------###

action()
{
for Runner in `find /var/xdrago -maxdepth 1 -mindepth 1 -type f | grep run- | uniq | sort`
do
  NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
  CTL_LOAD=388
  if [ $NOW_LOAD -lt $CTL_LOAD ] ; then
    echo load is $NOW_LOAD while maxload is $CTL_LOAD
    echo running $Runner
    bash $Runner
    echo waiting 3 sec
    sleep 3
    echo CTL done
  else
    echo load is $NOW_LOAD while maxload is $CTL_LOAD
    echo ...we have to wait...
  fi
done
}

###-------------SYSTEM-----------------###

if test -f /var/run/boa_wait.pid ; then
  touch /var/xdrago/log/wait-runner
  exit
else
  action
fi
###EOF2012###
