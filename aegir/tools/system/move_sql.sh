#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

if [ -e "/var/run/boa_wait.pid" ] ; then
  touch /var/xdrago/log/wait-for-mysql-restart
  exit
else
  touch /var/run/boa_wait.pid
  touch /var/xdrago/log/mysql_restart_running.pid
  /etc/init.d/mysql stop
  sleep 10
  /etc/init.d/mysql stop
  sleep 10
  /etc/init.d/mysql start
  sleep 30
  rm -f /var/run/boa_wait.pid
  rm -f /var/xdrago/log/mysql_restart_running.pid
  touch /var/xdrago/log/last-mysql-restart-done
fi
###EOF2014###
