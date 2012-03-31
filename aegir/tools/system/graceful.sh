#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games

action()
{
  rm -f -r /opt/tmp
  mkdir -p /opt/tmp
  chmod 777 /opt/tmp
  rm -f /opt/tmp/sess*
  rm -f /tmp/*error*
  rm -f /tmp/sess*
  rm -f -r /tmp/*
  rm -f /opt/tmp/*error*
  rm -f /opt/tomcat6/logs/*
  rm -f -r /var/lib/nginx/speed/*
  /etc/init.d/nginx stop
  /etc/init.d/php-fpm stop
  /etc/init.d/php53-fpm stop
  /etc/init.d/redis-server stop
  sleep 1
  rm -f /var/lib/redis/*
  killall redis-server
  rm -f /var/run/redis.pid
  rm -f /var/lib/redis/*
  /etc/init.d/redis-server start
  rm -f /var/lib/redis/*
  /etc/init.d/redis-server restart
  killall -9 php-fpm php-cgi nginx php wget
  sleep 1
  killall -9 php-fpm php-cgi nginx php wget
  echo rotate > /var/log/nginx/speed_purge.log
  /etc/init.d/php-fpm start
  /etc/init.d/php53-fpm start
  /etc/init.d/nginx start
  rm -f /var/xdrago/log/wait-for-octopus-barracuda-running
  touch /var/xdrago/log/graceful.done
}

if test -f /var/run/boa_run.pid ; then
  touch /var/xdrago/log/wait-for-octopus-barracuda-running
  exit
else
  touch /var/run/boa_wait.pid
  sleep 300
  action
  rm -f /var/run/boa_wait.pid
fi
###EOF2012###
