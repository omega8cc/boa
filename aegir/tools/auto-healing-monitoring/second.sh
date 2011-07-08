#!/bin/bash

hold()
{
  /etc/init.d/nginx stop
  killall -9 nginx
  sleep 1
  killall -9 nginx
  /etc/init.d/php-fpm stop
  /etc/init.d/redis-server stop
  killall -9 memcached
  killall -9 php-fpm php-cgi php wget
  echo load is $ONEX_LOAD:$FIVX_LOAD while maxload is $CTL_ONEX_LOAD:$CTL_FIVX_LOAD
}

control()
{
ONEX_LOAD=`awk '{print $1*100}' /proc/loadavg`
FIVX_LOAD=`awk '{print $2*100}' /proc/loadavg`
CTL_ONEX_LOAD=888
CTL_FIVX_LOAD=555
if [ $ONEX_LOAD -gt $CTL_ONEX_LOAD ]; then
  hold
elif [ $FIVX_LOAD -gt $CTL_FIVX_LOAD ]; then
  hold
else
  echo load is $ONEX_LOAD:$FIVX_LOAD while maxload is $CTL_ONEX_LOAD:$CTL_FIVX_LOAD
  echo ...OK now doing CTL...
  perl /var/xdrago/proc_num_ctrl.cgi
  touch /var/xdrago/log/proc_num_ctrl.done
  echo CTL done
fi
}

control
sleep 10
control
sleep 10
control
sleep 10
control
sleep 10
control
sleep 10
control
echo Done !
