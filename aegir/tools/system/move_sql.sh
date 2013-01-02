#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if test -f /var/run/boa_wait.pid ; then
  touch /var/xdrago/log/wait-for-mysql-restart
  exit
else
  touch /var/run/boa_wait.pid
  touch /var/xdrago/log/mysql_restart_running.pid
  /etc/init.d/mysql restart
  sleep 180
  rm -f /var/run/boa_wait.pid
  rm -f /var/xdrago/log/mysql_restart_running.pid
  touch /var/xdrago/log/last-mysql-restart-done
fi
###EOF2013###
