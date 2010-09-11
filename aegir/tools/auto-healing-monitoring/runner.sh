#!/bin/bash

###-------------SYSTEM-----------------###

SERVERS="run-a run-b"

###-------------SYSTEM-----------------###
action()
{
NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
CTL_LOAD=200
if [ $NOW_LOAD -lt $CTL_LOAD ]; then
echo load is $NOW_LOAD while maxload is $CTL_LOAD
echo ... now doing CTL...
for i in $SERVERS; do
sh /var/xdrago/$i
sleep 5
done
echo CTL done
else
echo load is $NOW_LOAD while maxload is $CTL_LOAD
echo ...we have to wait...
fi
}

if test -f /var/xdrago/log/optimize_mysql_ao.pid ; then
touch /var/xdrago/log/wait-runner
exit
else
action
fi