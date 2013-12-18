#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/opt/php55/bin:/opt/php54/bin:/opt/php53/bin:/opt/php52/bin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

action()
{
  /etc/init.d/nginx stop
  killall -9 php-fpm php-cgi drush.php nginx php wget
  bash /var/xdrago/move_sql.sh
  /etc/init.d/php-fpm start
  /etc/init.d/php53-fpm start
  /etc/init.d/nginx start
  touch /var/xdrago/log/enableStatus.done
}

if [ -e "/var/run/boa_wait.pid" ] ; then
  touch /var/xdrago/log/optimizemysqlrunning-enabler
  exit
else
  touch /var/run/boa_wait.pid
  sleep 8
  action
  rm -f /var/run/boa_wait.pid
fi
###EOF2013###
