#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games

action()
{
  rm -f -r /opt/tmp
  mkdir -p /opt/tmp
  chmod 777 /opt/tmp
  cat /var/xdrago/monitor/segfault_alert >> /var/xdrago/monitor/segfault_alert_archive
  rm -f /var/xdrago/monitor/segfault_alert
  rm -f /opt/tmp/sess*
  rm -f /tmp/*error*
  rm -f /tmp/sess*
  rm -f -r /tmp/*
  rm -f /opt/tmp/*error*
  rm -f /opt/tomcat6/logs/*
  rm -f -r /var/lib/nginx/speed/*
  echo rotate > /var/log/nginx/speed_purge.log
  /etc/init.d/nginx reload
  touch /var/xdrago/log/graceful.done
}

if test -f /var/run/boa_run.pid ; then
  exit
else
  touch /var/run/boa_wait.pid
  sleep 60
  action
  rm -f /var/run/boa_wait.pid
fi
###EOF2012###
