#!/bin/bash

hold()
{
  /etc/init.d/nginx stop
  killall -9 nginx
  sleep 1
  killall -9 nginx
  /etc/init.d/php-fpm stop
  /etc/init.d/php53-fpm stop
  /etc/init.d/redis-server stop
  killall -9 memcached php-fpm php-cgi
  echo load is $ONEX_LOAD:$FIVX_LOAD while maxload is $CTL_ONEX_LOAD:$CTL_FIVX_LOAD
}

terminate()
{
  if test -f /var/run/octopus_barracuda.pid ; then
    sleep 1
  else
    killall -9 php wget
  fi
}

control()
{
ONEX_LOAD=`awk '{print $1*100}' /proc/loadavg`
FIVX_LOAD=`awk '{print $2*100}' /proc/loadavg`
CTL_ONEX_LOAD=888
CTL_FIVX_LOAD=888
CTL_ONEX_LOAD_CRIT=1888
CTL_FIVX_LOAD_CRIT=1444
if [ $ONEX_LOAD -gt $CTL_ONEX_LOAD_CRIT ]; then
  terminate
elif [ $FIVX_LOAD -gt $CTL_FIVX_LOAD_CRIT ]; then
  terminate
fi
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
