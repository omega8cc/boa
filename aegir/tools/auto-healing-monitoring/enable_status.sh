#!/bin/bash

action()
{
  /etc/init.d/nginx stop
  killall -9 php-fpm nginx php
  bash /var/xdrago/move_sql.sh
  /etc/init.d/php-fpm start
  /etc/init.d/nginx start
  touch /var/xdrago/log/enableStatus.done
}

if test -f /var/xdrago/log/optimize_mysql_ao.pid ; then
  touch /var/xdrago/log/optimizemysqlrunning-enabler
  exit
else
  touch /var/xdrago/log/optimize_mysql_ao.pid
  sleep 8
  action
  rm -f /var/xdrago/log/optimize_mysql_ao.pid
fi
