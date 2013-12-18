#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/opt/php55/bin:/opt/php54/bin:/opt/php53/bin:/opt/php52/bin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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
###EOF2013###
