#!/bin/bash

if test -f /var/xdrago/log/optimize_mysql_ao.pid ; then
  touch /var/xdrago/log/wait-for-mysql-restart
  exit
else
  touch /var/xdrago/log/optimize_mysql_ao.pid
  /etc/init.d/mysql restart
  rm -f /var/xdrago/log/optimize_mysql_ao.pid
  touch /var/xdrago/log/last-mysql-restart-done
fi
