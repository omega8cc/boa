#!/bin/bash

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
  killall -9 nginx
  /etc/init.d/nginx start
  rm -f /var/xdrago/log/wait-for-octopus-barracuda-running
  touch /var/xdrago/log/graceful.done
}

if test -f /var/run/octopus_barracuda.pid ; then
  touch /var/xdrago/log/wait-for-octopus-barracuda-running
  exit
else
  touch /var/xdrago/log/optimize_mysql_ao.pid
  sleep 60
  action
  rm -f /var/xdrago/log/optimize_mysql_ao.pid
fi
