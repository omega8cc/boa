#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

touch /var/run/fmp_wait.pid
echo rotate > /var/log/php/php-fpm-error.log
echo rotate > /var/log/php/php-fpm-slow.log
echo rotate > /var/log/php/php53-fpm-error.log
echo rotate > /var/log/php/php53-fpm-slow.log
echo rotate > /var/log/php/error_log_52
echo rotate > /var/log/php/error_log_53
echo rotate > /var/log/php/error_log_cli_52
echo rotate > /var/log/php/error_log_cli_53
echo rotate > /var/log/redis/redis-server.log
echo rotate > /var/log/mysql/sql-slow-query.log
if test -f /root/.high_traffic.cnf ; then
  echo rotate > /var/log/nginx/access.log
else
  /etc/init.d/php53-fpm reload
  if test -f /etc/init.d/php-fpm ; then
    /etc/init.d/php-fpm reload
  fi
  sleep 8
fi
if test -f /var/run/boa_run.pid ; then
  sleep 1
else
  rm -f /tmp/*error*
fi
rm -f /var/run/fmp_wait.pid
ntpdate pool.ntp.org
touch /var/xdrago/log/clear.done
###EOF2013###
