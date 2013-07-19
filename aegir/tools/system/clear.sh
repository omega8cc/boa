#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ -e "/etc/cron.daily/logrotate" ] ; then
  _SYSLOG_SIZE_TEST=$(du -s -h /var/log/syslog)
  if [[ "$_SYSLOG_SIZE_TEST" =~ "G" ]] ; then
    echo $_SYSLOG_SIZE_TEST too big
    bash /etc/cron.daily/logrotate
    echo system logs rotated
  fi
fi
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
  touch /var/run/fmp_wait.pid
  if [ -e "/etc/init.d/php-fpm" ] ; then
    /etc/init.d/php-fpm reload
  fi
  /etc/init.d/php53-fpm reload
  sleep 8
  rm -f /var/run/fmp_wait.pid
fi
if test -f /var/run/boa_run.pid ; then
  sleep 1
else
  rm -f /tmp/*error*
fi
if test -f /etc/resolvconf/run/interface/lo.pdnsd ; then
  rm -f /etc/resolvconf/run/interface/eth*
  resolvconf -u &> /dev/null
fi
if test -d /dev/disk ; then
  swapoff -a
  swapon -a
fi
touch /var/xdrago/log/clear.done
###EOF2013###
