#!/bin/bash

if test -f /var/xdrago/log/optimize_mysql_ao.pid ; then
  touch /var/xdrago/log/wait-for-mysql-restart
  exit
else
  touch /var/xdrago/log/optimize_mysql_ao.pid
  touch /var/xdrago/log/mysql_restart_running.pid
  /etc/init.d/mysql restart
  sleep 180
  rm -f /var/xdrago/log/optimize_mysql_ao.pid
  rm -f /var/xdrago/log/mysql_restart_running.pid
  touch /var/xdrago/log/last-mysql-restart-done
fi
