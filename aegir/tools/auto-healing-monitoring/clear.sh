#!/bin/bash

/usr/sbin/ntpdate pool.ntp.org
/etc/init.d/php-fpm reload
/etc/init.d/php53-fpm reload
sleep 5
echo rotate > /var/log/php/php-fpm-error.log
echo rotate > /var/log/php/php-fpm-slow.log
echo rotate > /opt/local/var/log/php53-fpm-error.log
echo rotate > /opt/local/var/log/php53-fpm-slow.log
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
killall memcached &> /dev/null
bash /var/xdrago/memcache.sh
invoke-rc.d redis-server stop 2>&1
sleep 2
rm -f /var/lib/redis/*
rm -f /var/log/redis/*
killall redis-server &> /dev/null
rm -f /var/lib/redis/*
sleep 2
invoke-rc.d redis-server restart 2>&1
sleep 2
rm -f /var/lib/redis/*
invoke-rc.d redis-server restart 2>&1
touch /var/xdrago/log/clear.done
