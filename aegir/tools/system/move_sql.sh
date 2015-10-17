#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

if [ -e "/var/run/boa_wait.pid" ]; then
  touch /var/xdrago/log/wait-for-mysql-restart
  exit 0
else
  touch /var/run/boa_wait.pid
  touch /var/xdrago/log/mysql_restart_running.pid
  service mysql stop
  sleep 10
  service mysql stop
  sleep 10
  service mysql start
  sleep 30
  rm -f /var/run/boa_wait.pid
  rm -f /var/xdrago/log/mysql_restart_running.pid
  touch /var/xdrago/log/last-mysql-restart-done
  exit 0
fi
###EOF2015###
