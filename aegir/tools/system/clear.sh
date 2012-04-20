#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games

/usr/sbin/ntpdate pool.ntp.org
/etc/init.d/php-fpm reload
/etc/init.d/php53-fpm reload
sleep 5
echo rotate > /var/log/php/php-fpm-error.log
echo rotate > /var/log/php/php-fpm-slow.log
echo rotate > /var/log/php/php53-fpm-error.log
echo rotate > /var/log/php/php53-fpm-slow.log
echo rotate > /var/log/php/error_log_52
echo rotate > /var/log/php/error_log_53
echo rotate > /var/log/php/error_log_cli
echo rotate > /var/log/php/error_log_cli_53
echo rotate > /var/log/redis/redis-server.log
echo rotate > /var/log/mysql/sql-slow-query.log
if test -f /var/run/boa_run.pid ; then
  sleep 1
else
  rm -f -r /tmp/*
fi
touch /var/xdrago/log/clear.done
###EOF2012###
