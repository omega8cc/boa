#!/bin/bash

action()
{
  /etc/init.d/nginx stop
  killall -9 php-fpm php-cgi nginx php wget
  bash /var/xdrago/move_sql.sh
  /etc/init.d/php-fpm start
  /etc/init.d/php53-fpm start
  /etc/init.d/nginx start
  touch /var/xdrago/log/enableStatus.done
}

if test -f /var/run/boa_wait.pid ; then
  touch /var/xdrago/log/optimizemysqlrunning-enabler
  exit
else
  touch /var/run/boa_wait.pid
  sleep 8
  action
  rm -f /var/run/boa_wait.pid
fi
