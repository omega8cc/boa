#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>&1)
if [[ "$_PHPLOG_SIZE_TEST" =~ "G" ]] ; then
  echo $_PHPLOG_SIZE_TEST too big
  touch /var/run/fmp_wait.pid
  rm -f /var/log/php/*
  if [ -e "/etc/init.d/php55-fpm" ] ; then
    /etc/init.d/php55-fpm reload
  fi
  if [ -e "/etc/init.d/php54-fpm" ] ; then
    /etc/init.d/php54-fpm reload
  fi
  if [ -e "/etc/init.d/php53-fpm" ] ; then
    /etc/init.d/php53-fpm reload
  fi
  if [ -e "/etc/init.d/php52-fpm" ] ; then
    /etc/init.d/php52-fpm reload
  fi
  sleep 8
  rm -f /var/run/fmp_wait.pid
  echo php logs rotated
fi

if [ -e "/var/log/nginx/error.log" ] ; then
  if [ `tail --lines=500 /var/log/nginx/error.log | grep --count "Cannot allocate memory"` -gt "0" ]; then
    touch /var/run/boa_run.pid
    echo "`date` OOM nginx detected" >> /var/xdrago/log/oom.nginx.log
    sleep 5
    echo "`date` OOM incident response started" >> /var/xdrago/log/oom.nginx.log
    mv -f /var/log/nginx/error.log /var/log/nginx/`date +%y%m%d-%H%M`-error.log
    kill -9 $(ps aux | grep '[n]ginx' | awk '{print $2}') &> /dev/null
    echo "`date` OOM nginx stopped" >> /var/xdrago/log/oom.nginx.log
    kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
    echo "`date` OOM php-fpm stopped" >> /var/xdrago/log/oom.nginx.log
    kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}') &> /dev/null
    echo "`date` OOM jetty stopped" >> /var/xdrago/log/oom.nginx.log
    kill -9 $(ps aux | grep '[n]ewrelic-daemon' | awk '{print $2}') &> /dev/null
    echo "`date` OOM newrelic-daemon stopped" >> /var/xdrago/log/oom.nginx.log
    kill -9 $(ps aux | grep '[r]edis-server' | awk '{print $2}') &> /dev/null
    echo "`date` OOM redis-server stopped" >> /var/xdrago/log/oom.nginx.log
    bash /var/xdrago/move_sql.sh
    echo "`date` OOM mysql restarted" >> /var/xdrago/log/oom.nginx.log
    echo "`date` OOM incident response completed" >> /var/xdrago/log/oom.nginx.log
    sleep 5
    rm -f /var/run/boa_run.pid
    exit 0
  fi
fi

if [ ! -e "/etc/resolvconf/run/interface/lo.pdnsd" ] ; then
  resolvconf -u &> /dev/null
  service pdnsd restart &> /dev/null
fi

if [ `ps aux | grep -v "grep" | grep --count "php-fpm: master process"` -gt 3 ]; then
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "`date` Too many PHP-FPM master processes killed" >> /var/xdrago/log/php-fpm-master-count.kill.log
fi

if [ -e "/root/.high_traffic.cnf" ] ; then
  _DO_NOTHING=YES
else
  perl /var/xdrago/monitor/check/segfault_alert
fi

mysql_proc_kill()
{
  if [ "$xtime" != "Time" ] && [ "$xuser" != "root" ] && [ "$xtime" != "|" ] && [[ "$xtime" -gt "$limit" ]] ; then
    xkill=`mysqladmin kill $each`
    times=`date`
    echo $times $each $xuser $xtime $xkill
    echo "$times $each $xuser $xtime $xkill" >> /var/xdrago/log/sql_watch.log
  fi
}

mysql_proc_control()
{
limit=3600
xkill=null
for each in `mysqladmin proc | awk '{print $2, $4, $8, $12}' | awk '{print $1}'`;
do
  xtime=`mysqladmin proc | awk '{print $2, $4, $8, $12}' | grep $each | awk '{print $4}'`
  if [ "$xtime" = "|" ] ; then
    xtime=`mysqladmin proc | awk '{print $2, $4, $8, $11}' | grep $each | awk '{print $4}'`
  fi
  xuser=`mysqladmin proc | awk '{print $2, $4, $8, $12}' | grep $each | awk '{print $2}'`
  if [ "$xtime" != "Time" ] ; then
    if [ "$xuser" = "xabuse" ] ; then
      limit=60
      mysql_proc_kill
    else
      limit=3600
      mysql_proc_kill
    fi
  fi;
done
}

lsyncd_proc_control()
{
if [ -e "/var/log/lsyncd.log" ] ; then
  if [ `tail --lines=100 /var/log/lsyncd.log | grep --count "Error: Terminating"` -gt "0" ]; then
    echo "`date` TRM lsyncd" >> /var/xdrago/log/lsyncd.monitor.log
  fi
  if [ `tail --lines=100 /var/log/lsyncd.log | grep --count "ERROR: Auto-resolving failed"` -gt "5" ]; then
    echo "`date` ERR lsyncd" >> /var/xdrago/log/lsyncd.monitor.log
  fi
  if [ `tail --lines=5000 /var/log/lsyncd.log | grep --count "Normal: Finished events list = 0"` -lt "1" ]; then
    echo "`date` NRM lsyncd" >> /var/xdrago/log/lsyncd.monitor.log
  fi
fi
if [ -e "/var/xdrago/log/lsyncd.monitor.log" ] ; then
  if [ -e "/root/.barracuda.cnf" ] ; then
    source /root/.barracuda.cnf
  fi
  if [ `tail --lines=10 /var/xdrago/log/lsyncd.monitor.log | grep --count "TRM lsyncd"` -gt "3" ] && [ -n "$_MY_EMAIL" ] ; then
    mail -s "ALERT! lsyncd TRM failure on `uname -n`" $_MY_EMAIL < /var/xdrago/log/lsyncd.monitor.log
    _ARCHIVE_LOG=YES
  fi
  if [ `tail --lines=10 /var/xdrago/log/lsyncd.monitor.log | grep --count "ERR lsyncd"` -gt "3" ] && [ -n "$_MY_EMAIL" ] ; then
    mail -s "ALERT! lsyncd ERR failure on `uname -n`" $_MY_EMAIL < /var/xdrago/log/lsyncd.monitor.log
    _ARCHIVE_LOG=YES
  fi
  if [ `tail --lines=10 /var/xdrago/log/lsyncd.monitor.log | grep --count "NRM lsyncd"` -gt "3" ] && [ -n "$_MY_EMAIL" ] ; then
    mail -s "NOTICE: lsyncd NRM problem on `uname -n`" $_MY_EMAIL < /var/xdrago/log/lsyncd.monitor.log
    _ARCHIVE_LOG=YES
  fi
  if [ "$_ARCHIVE_LOG" = "YES" ] ; then
    cat /var/xdrago/log/lsyncd.monitor.log >> /var/xdrago/log/lsyncd.warn.archive.log
    rm -f /var/xdrago/log/lsyncd.monitor.log
  fi
fi
}

lsyncd_proc_control
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
sleep 5
perl /var/xdrago/monitor/check/escapecheck
perl /var/xdrago/monitor/check/hackcheck
perl /var/xdrago/monitor/check/hackftp
perl /var/xdrago/monitor/check/scan_nginx
if [ ! -e "/root/.high_traffic.cnf" ] ; then
  perl /var/xdrago/monitor/check/locked
fi
perl /var/xdrago/monitor/check/sqlcheck
echo DONE!
exit 0
###EOF2015###
