#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

hold()
{
  /etc/init.d/nginx stop
  killall -9 nginx
  sleep 1
  killall -9 nginx
  /etc/init.d/php-fpm stop
  /etc/init.d/php53-fpm stop
  killall -9 php-fpm php-cgi
  echo load is $ONEX_LOAD:$FIVX_LOAD while maxload is $CTL_ONEX_LOAD:$CTL_FIVX_LOAD
}

terminate()
{
  if test -f /var/run/boa_run.pid ; then
    sleep 1
  else
    killall -9 php drush.php wget
  fi
}

nginx_high_load_on()
{
  mv -f /data/conf/nginx_high_load_off.conf /data/conf/nginx_high_load.conf
  /etc/init.d/nginx reload
}

nginx_high_load_off()
{
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  /etc/init.d/nginx reload
}

control()
{
ONEX_LOAD=`awk '{print $1*100}' /proc/loadavg`
FIVX_LOAD=`awk '{print $2*100}' /proc/loadavg`
CTL_ONEX_SPIDER_LOAD=300
CTL_FIVX_SPIDER_LOAD=300
CTL_ONEX_LOAD=1444
CTL_FIVX_LOAD=888
CTL_ONEX_LOAD_CRIT=1888
CTL_FIVX_LOAD_CRIT=1555
if [ $ONEX_LOAD -ge $CTL_ONEX_SPIDER_LOAD ] && [ $ONEX_LOAD -lt $CTL_ONEX_LOAD ] && [ -e "/data/conf/nginx_high_load_off.conf" ] ; then
  nginx_high_load_on
elif [ $FIVX_LOAD -ge $CTL_FIVX_SPIDER_LOAD ] && [ $FIVX_LOAD -lt $CTL_FIVX_LOAD ] && [ -e "/data/conf/nginx_high_load_off.conf" ] ; then
  nginx_high_load_on
elif [ $ONEX_LOAD -lt $CTL_ONEX_SPIDER_LOAD ] && [ $FIVX_LOAD -lt $CTL_FIVX_SPIDER_LOAD ] && [ -e "/data/conf/nginx_high_load.conf" ] ; then
  nginx_high_load_off
fi
if [ $ONEX_LOAD -ge $CTL_ONEX_LOAD_CRIT ] ; then
  terminate
elif [ $FIVX_LOAD -ge $CTL_FIVX_LOAD_CRIT ] ; then
  terminate
fi
if [ $ONEX_LOAD -ge $CTL_ONEX_LOAD ] ; then
  hold
elif [ $FIVX_LOAD -ge $CTL_FIVX_LOAD ] ; then
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
###EOF2012###
