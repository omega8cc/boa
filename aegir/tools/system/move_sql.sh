#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
  _B_NICE=${_B_NICE//[^0-9]/}
fi
if [ -z "${_B_NICE}" ]; then
  _B_NICE=10
fi

if [ -e "/var/xdrago/log/mysql_restart_running.pid" ]; then
  touch /var/xdrago/log/wait-for-mysql-restart
  echo "mysql server restart already in progress..."
  exit 0
else
  touch /var/run/boa_wait.pid
  touch /var/xdrago/log/mysql_restart_running.pid
  mysql -u root -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;"
  mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;"
  service mysql stop
  sleep 15
  if [ -e "/var/run/mysqld/mysqld.pid" ] \
    || [ -e "/var/run/mysqld/mysqld.sock" ]; then
    service mysql stop
    sleep 15
  fi
  renice ${_B_NICE} -p $$ &> /dev/null
  if [ ! -e "/var/run/mysqld/mysqld.sock" ]; then
    service mysql start
  fi
  sleep 15
  rm -f /var/run/boa_wait.pid
  rm -f /var/xdrago/log/mysql_restart_running.pid
  touch /var/xdrago/log/last-mysql-restart-done
  exit 0
fi
###EOF2016###
