#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

check_root() {
  if [ `whoami` = "root" ]; then
    if [ -e "/root/.barracuda.cnf" ]; then
      source /root/.barracuda.cnf
      _B_NICE=${_B_NICE//[^0-9]/}
    fi
    if [ -z "${_B_NICE}" ]; then
      _B_NICE=10
    fi
    chmod a+w /dev/null
    if [ ! -e "/dev/fd" ]; then
      if [ -e "/proc/self/fd" ]; then
        rm -rf /dev/fd
        ln -s /proc/self/fd /dev/fd
      fi
    fi
  else
    echo "ERROR: This script should be ran as a root user"
    exit 1
  fi
}
check_root

if [ -e "/etc/cron.daily/logrotate" ]; then
  _SYSLOG_SIZE_TEST=$(du -s -h /var/log/syslog)
  if [[ "${_SYSLOG_SIZE_TEST}" =~ "G" ]]; then
    echo ${_SYSLOG_SIZE_TEST} too big
    bash /etc/cron.daily/logrotate &> /dev/null
    echo system logs rotated
    echo "$(date 2>&1) ${_SYSLOG_SIZE_TEST} too big, logrotate forced" >> \
      /var/xdrago/log/giant.syslog.incident.log
  fi
fi

check_pdnsd() {
  if [ -x "/usr/sbin/pdnsd" ] \
    && [ ! -e "/etc/resolvconf/run/interface/lo.pdnsd" ]; then
    mkdir -p /etc/resolvconf/run/interface
    echo "nameserver 127.0.0.1" > /etc/resolvconf/run/interface/lo.pdnsd
    resolvconf -u         &> /dev/null
    service pdnsd restart &> /dev/null
    pdnsd-ctl empty-cache &> /dev/null
  fi
  if [ -e "/etc/resolv.conf" ]; then
    _RESOLV_TEST=$(grep "nameserver 127.0.0.1" /etc/resolv.conf 2>&1)
    if [[ "$_RESOLV_TEST" =~ "nameserver 127.0.0.1" ]]; then
      _THIS_DNS_TEST=$(host files.aegir.cc 127.0.0.1 -w 3 2>&1)
      if [[ "${_THIS_DNS_TEST}" =~ "no servers could be reached" ]]; then
        service pdnsd stop &> /dev/null
        sleep 1
        renice ${_B_NICE} -p $$ &> /dev/null
        perl /var/xdrago/proc_num_ctrl.cgi
      fi
    fi
  fi
}
check_pdnsd

if [ -e "/var/log/php" ]; then
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "already listen on"` -gt "0" ]; then
    touch /var/run/fmp_wait.pid
    sleep 8
    kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}')
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    rm -f /var/run/*.fpm.socket
    renice ${_B_NICE} -p $$ &> /dev/null
    if [ -e "/etc/init.d/php74-fpm" ]; then
      service php74-fpm start
    fi
    if [ -e "/etc/init.d/php73-fpm" ]; then
      service php73-fpm start
    fi
    if [ -e "/etc/init.d/php72-fpm" ]; then
      service php72-fpm start
    fi
    if [ -e "/etc/init.d/php71-fpm" ]; then
      service php71-fpm start
    fi
    if [ -e "/etc/init.d/php70-fpm" ]; then
      service php70-fpm start
    fi
    if [ -e "/etc/init.d/php56-fpm" ]; then
      service php56-fpm start
    fi
    sleep 8
    rm -f /var/run/fmp_wait.pid
    echo "$(date 2>&1) FPM instances conflict detected" >> \
      /var/xdrago/log/fpm.conflict.incident.log
  fi
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "process.max"` -gt "0" ]; then
    touch /var/run/fmp_wait.pid
    sleep 8
    kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}')
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    rm -f /var/run/*.fpm.socket
    renice ${_B_NICE} -p $$ &> /dev/null
    if [ -e "/etc/init.d/php74-fpm" ]; then
      service php74-fpm start
    fi
    if [ -e "/etc/init.d/php73-fpm" ]; then
      service php73-fpm start
    fi
    if [ -e "/etc/init.d/php72-fpm" ]; then
      service php72-fpm start
    fi
    if [ -e "/etc/init.d/php71-fpm" ]; then
      service php71-fpm start
    fi
    if [ -e "/etc/init.d/php70-fpm" ]; then
      service php70-fpm start
    fi
    if [ -e "/etc/init.d/php56-fpm" ]; then
      service php56-fpm start
    fi
    sleep 8
    rm -f /var/run/fmp_wait.pid
    echo "$(date 2>&1) Too many running FPM childs detected" >> \
      /var/xdrago/log/fpm.childs.incident.log
  fi
fi

_PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>&1)
if [[ "$_PHPLOG_SIZE_TEST" =~ "G" ]]; then
  echo $_PHPLOG_SIZE_TEST too big
  touch /var/run/fmp_wait.pid
  rm -f /var/log/php/*
  renice ${_B_NICE} -p $$ &> /dev/null
  if [ -e "/etc/init.d/php74-fpm" ]; then
    service php74-fpm reload
  fi
  if [ -e "/etc/init.d/php73-fpm" ]; then
    service php73-fpm reload
  fi
  if [ -e "/etc/init.d/php72-fpm" ]; then
    service php72-fpm reload
  fi
  if [ -e "/etc/init.d/php71-fpm" ]; then
    service php71-fpm reload
  fi
  if [ -e "/etc/init.d/php70-fpm" ]; then
    service php70-fpm reload
  fi
  if [ -e "/etc/init.d/php56-fpm" ]; then
    service php56-fpm reload
  fi
  if [ -e "/etc/init.d/php55-fpm" ]; then
    service php55-fpm stop
  fi
  if [ -e "/etc/init.d/php54-fpm" ]; then
    service php54-fpm stop
  fi
  if [ -e "/etc/init.d/php53-fpm" ]; then
    service php53-fpm stop
  fi
  sleep 8
  rm -f /var/run/fmp_wait.pid
  echo "$(date 2>&1) Too big PHP error logs deleted: $_PHPLOG_SIZE_TEST" >> \
    /var/xdrago/log/php.giant.logs.incident.log
fi

pthOml="/var/xdrago/log/oom.incident.log"

oom_restart() {
  touch /var/run/boa_run.pid
  echo "$(date 2>&1) OOM $1 detected"                               >> ${pthOml}
  sleep 5
  echo "$(date 2>&1) OOM incident response started"                 >> ${pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/`date +%y%m%d-%H%M`-error.log
  kill -9 $(ps aux | grep '[n]ginx' | awk '{print $2}')
  echo "$(date 2>&1) OOM nginx stopped"                             >> ${pthOml}
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}')
  echo "$(date 2>&1) OOM php-fpm stopped"                           >> ${pthOml}
  kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}')
  echo "$(date 2>&1) OOM jetty stopped"                             >> ${pthOml}
  kill -9 $(ps aux | grep '[j]ava-8-openjdk' | awk '{print $2}')
  echo "$(date 2>&1) OOM solr stopped"                              >> ${pthOml}
  kill -9 $(ps aux | grep '[n]ewrelic-daemon' | awk '{print $2}')
  echo "$(date 2>&1) OOM newrelic-daemon stopped"                   >> ${pthOml}
  kill -9 $(ps aux | grep '[r]edis-server' | awk '{print $2}')
  echo "$(date 2>&1) OOM redis-server stopped"                      >> ${pthOml}
  bash /var/xdrago/move_sql.sh
  echo "$(date 2>&1) OOM mysql restarted"                           >> ${pthOml}
  echo "$(date 2>&1) OOM incident response completed"               >> ${pthOml}
  echo                                                              >> ${pthOml}
  sleep 5
  rm -f /var/run/boa_run.pid
  exit 0
}

sql_restart() {
  touch /var/run/boa_run.pid
  echo "$(date 2>&1) LOW $1 detected"                               >> ${pthOml}
  sleep 5
  echo "$(date 2>&1) LOW incident response started"                 >> ${pthOml}
  bash /var/xdrago/move_sql.sh
  echo "$(date 2>&1) LOW mysql restarted"                           >> ${pthOml}
  echo "$(date 2>&1) LOW incident response completed"               >> ${pthOml}
  echo                                                              >> ${pthOml}
  sleep 5
  rm -f /var/run/boa_run.pid
  exit 0
}

if [ -e "/var/log/nginx/error.log" ]; then
  if [ `tail --lines=500 /var/log/nginx/error.log \
    | grep --count "Cannot allocate memory"` -gt "0" ]; then
    oom_restart "nginx"
  fi
fi

_RAM_TOTAL=$(free -mt | grep Mem: | cut -d: -f2 | awk '{ print $1}' 2>&1)
_RAM_FREE_TEST=$(free -mt 2>&1)
if [[ "${_RAM_FREE_TEST}" =~ "buffers/cache:" ]]; then
  _RAM_FREE=$(free -mt | grep /+ | cut -d: -f2 | awk '{ print $2}' 2>&1)
else
  _RAM_FREE=$(free -mt | grep Mem: | cut -d: -f2 | awk '{ print $6}' 2>&1)
fi
_RAM_PCT_FREE=$(echo "scale=0; $(bc -l <<< "${_RAM_FREE} / ${_RAM_TOTAL} * 100")/1" | bc 2>&1)
_RAM_PCT_FREE=${_RAM_PCT_FREE//[^0-9]/}

echo _RAM_TOTAL is ${_RAM_TOTAL}
echo _RAM_PCT_FREE is ${_RAM_PCT_FREE}

if [ ! -z "${_RAM_PCT_FREE}" ] && [ "${_RAM_PCT_FREE}" -lt "10" ]; then
  oom_restart "RAM"
fi

redis_oom_check() {
  if [ `tail --lines=500 /var/log/php/error_log_* \
    | grep --count "RedisException"` -gt "0" ]; then
    service redis-server stop &> /dev/null
    killall -9 redis-server &> /dev/null
    service redis-server start &> /dev/null
    echo "$(date 2>&1) RedisException OOM detected"
    echo "$(date 2>&1) RedisException OOM detected" >> /var/xdrago/log/redis.watch.log
    touch /var/run/fmp_wait.pid
    sleep 8
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    renice ${_B_NICE} -p $$ &> /dev/null
    if [ -e "/etc/init.d/php74-fpm" ]; then
      service php74-fpm reload
    fi
    if [ -e "/etc/init.d/php73-fpm" ]; then
      service php73-fpm reload
    fi
    if [ -e "/etc/init.d/php72-fpm" ]; then
      service php72-fpm reload
    fi
    if [ -e "/etc/init.d/php71-fpm" ]; then
      service php71-fpm reload
    fi
    if [ -e "/etc/init.d/php70-fpm" ]; then
      service php70-fpm reload
    fi
    if [ -e "/etc/init.d/php56-fpm" ]; then
      service php56-fpm reload
    fi
    sleep 8
    rm -f /var/run/fmp_wait.pid
  fi
}
redis_oom_check

redis_slow_check() {
  if [ `tail --lines=500 /var/log/php/fpm-*-slow.log \
    | grep --count "PhpRedis.php"` -gt "5" ]; then
    touch /var/run/fmp_wait.pid
    sleep 8
    service redis-server stop &> /dev/null
    killall -9 redis-server &> /dev/null
    service redis-server start &> /dev/null
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    renice ${_B_NICE} -p $$ &> /dev/null
    if [ -e "/etc/init.d/php74-fpm" ]; then
      service php74-fpm reload
    fi
    if [ -e "/etc/init.d/php73-fpm" ]; then
      service php73-fpm reload
    fi
    if [ -e "/etc/init.d/php72-fpm" ]; then
      service php72-fpm reload
    fi
    if [ -e "/etc/init.d/php71-fpm" ]; then
      service php71-fpm reload
    fi
    if [ -e "/etc/init.d/php70-fpm" ]; then
      service php70-fpm reload
    fi
    if [ -e "/etc/init.d/php56-fpm" ]; then
      service php56-fpm reload
    fi
    sleep 8
    rm -f /var/run/fmp_wait.pid
    echo "$(date 2>&1) Slow PhpRedis detected" >> \
      /var/xdrago/log/redis.slow.incident.log
  fi
}
redis_slow_check

fpm_sockets_healing() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    touch /var/run/fmp_wait.pid
    sleep 8
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
    renice ${_B_NICE} -p $$ &> /dev/null
    if [ -e "/etc/init.d/php74-fpm" ]; then
      service php74-fpm start
    fi
    if [ -e "/etc/init.d/php73-fpm" ]; then
      service php73-fpm start
    fi
    if [ -e "/etc/init.d/php72-fpm" ]; then
      service php72-fpm start
    fi
    if [ -e "/etc/init.d/php71-fpm" ]; then
      service php71-fpm start
    fi
    if [ -e "/etc/init.d/php70-fpm" ]; then
      service php70-fpm start
    fi
    if [ -e "/etc/init.d/php56-fpm" ]; then
      service php56-fpm start
    fi
    sleep 8
    rm -f /var/run/fmp_wait.pid
    echo "$(date 2>&1) FPM Sockets conflict detected" >> \
      /var/xdrago/log/fpm.sockets.incident.log
  fi
}
fpm_sockets_healing

jetty_restart() {
  touch /var/run/boa_wait.pid
  sleep 5
  kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}') &> /dev/null
  rm -f /var/log/jetty{7,8,9}/*
  renice ${_B_NICE} -p $$ &> /dev/null
  if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
    service jetty9 start
  fi
  if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
    service jetty8 start
  fi
  if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
    service jetty7 start
  fi
  sleep 5
  rm -f /var/run/boa_wait.pid
}

if [ -e "/var/log/jetty9" ]; then
  if [ `tail --lines=500 /var/log/jetty9/*stderrout.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    jetty_restart "zombie"
    echo "$(date 2>&1) Address already in use for jetty9" >> \
      /var/xdrago/log/jetty.zombie.incident.log
  fi
fi

if [ -e "/var/log/jetty8" ]; then
  if [ `tail --lines=500 /var/log/jetty8/*stderrout.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    jetty_restart "zombie"
    echo "$(date 2>&1) Address already in use for jetty8" >> \
      /var/xdrago/log/jetty.zombie.incident.log
  fi
fi

if [ -e "/var/log/jetty7" ]; then
  if [ `tail --lines=500 /var/log/jetty7/*stderrout.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    jetty_restart "zombie"
    echo "$(date 2>&1) Address already in use for jetty7" >> \
      /var/xdrago/log/jetty.zombie.incident.log
  fi
fi

if [ `ps aux | grep -v "grep" | grep --count "php-fpm: master process"` -gt "6" ]; then
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) Too many PHP-FPM master processes killed" >> \
    /var/xdrago/log/php-fpm-master-count.kill.log
fi

if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "3" ]; then
  kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) Too many dirmngr processes killed" >> \
    /var/xdrago/log/dirmngr-count.kill.log
fi

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/segfault_alert
fi

mysql_proc_kill() {
  xtime=${xtime//[^0-9]/}
  echo "proc nr to monitor is $each by $xuser runnning for $xtime seconds"
  if [ ! -z "$xtime" ]; then
    if [ $xtime -gt $limit ]; then
      echo "proc to kill is $each by $xuser after $xtime"
      xkill=$(mysqladmin kill $each 2>&1)
      times=$(date 2>&1)
      load=$(cat /proc/loadavg 2>&1)
      echo "$load"
      echo "$load" >> /var/xdrago/log/sql_watch.log
      echo $times $each $xuser $xtime $xkill
      echo "$times $each $xuser $xtime $xkill" >> /var/xdrago/log/sql_watch.log
    fi
  fi
}

mysql_proc_control() {
  if [ ! -z "${_SQLMONITOR}" ] && [ "${_SQLMONITOR}" = "YES" ]; then
    echo "$(date 2>&1)" >> /var/xdrago/log/mysqladmin.monitor.log
    echo "$(mysqladmin proc 2>&1)" >> /var/xdrago/log/mysqladmin.monitor.log
    if [ ! -z "${_RAM_PCT_FREE}" ] && [ "${_RAM_PCT_FREE}" -lt "20" ]; then
      sql_restart "RAM"
    fi
  fi
  limit=3600
  xkill=null
  for each in `mysqladmin proc \
    | awk '{print $2, $4, $8, $12}' \
    | awk '{print $1}'`; do
    each=${each//[^0-9]/}
    if [ ! -z "$each" ]; then
      if [ "$each" -gt "5" ] \
        && [ ! -z "$each" ]; then
        xtime=$(mysqladmin proc \
          | awk '{print $2, $4, $8, $12}' \
          | grep $each \
          | awk '{print $4}' 2>&1)
        xtime=${xtime//[^0-9]/}
        xuser=$(mysqladmin proc \
          | awk '{print $2, $4, $8, $12}' \
          | grep $each \
          | awk '{print $2}' 2>&1)
        xuser=${xuser//[^0-9a-z_]/}
        if [ ! -z "$xtime" ]; then
          if [ -e "/root/.sql.blacklist.cnf" ]; then
            ## cat /root/.sql.blacklist.cnf
            # xsqlfoo # db name/user causing problems, w/o # in front
            # xsqlbar # db name/user causing problems, w/o # in front
            # xsqlnew # db name/user causing problems, w/o # in front
            for _XQ in `cat /root/.sql.blacklist.cnf \
              | cut -d '#' -f1 \
              | sort \
              | uniq \
              | tr -d "\s"`; do
              if [ "$xuser" = "${_XQ}" ]; then
                echo killing ${_XQ} to avoid issues
                limit=1
                mysql_proc_kill
              fi
            done
          else
            limit=3600
            mysql_proc_kill
          fi
        fi
      fi
    fi;
  done
}

lsyncd_proc_control() {
  if [ -e "/var/log/lsyncd.log" ]; then
    if [ `tail --lines=100 /var/log/lsyncd.log \
      | grep --count "Error: Terminating"` -gt "0" ]; then
      echo "$(date 2>&1) TRM lsyncd" >> /var/xdrago/log/lsyncd.monitor.log
    fi
    if [ `tail --lines=100 /var/log/lsyncd.log \
      | grep --count "ERROR: Auto-resolving failed"` -gt "5" ]; then
      echo "$(date 2>&1) ERR lsyncd" >> /var/xdrago/log/lsyncd.monitor.log
    fi
    if [ `tail --lines=5000 /var/log/lsyncd.log \
      | grep --count "Normal: Finished events list = 0"` -lt "1" ]; then
      echo "$(date 2>&1) NRM lsyncd" >> /var/xdrago/log/lsyncd.monitor.log
    fi
  fi
  if [ -e "/var/xdrago/log/lsyncd.monitor.log" ]; then
    if [ -e "/root/.barracuda.cnf" ]; then
      source /root/.barracuda.cnf
    fi
    if [ `tail --lines=10 /var/xdrago/log/lsyncd.monitor.log \
      | grep --count "TRM lsyncd"` -gt "3" ] && [ -n "${_MY_EMAIL}" ]; then
      mail -s "ALERT! lsyncd TRM failure on $(uname -n 2>&1)" ${_MY_EMAIL} < \
        /var/xdrago/log/lsyncd.monitor.log
      _ARCHIVE_LOG=YES
    fi
    if [ `tail --lines=10 /var/xdrago/log/lsyncd.monitor.log \
      | grep --count "ERR lsyncd"` -gt "3" ] && [ -n "${_MY_EMAIL}" ]; then
      mail -s "ALERT! lsyncd ERR failure on $(uname -n 2>&1)" ${_MY_EMAIL} < \
        /var/xdrago/log/lsyncd.monitor.log
      _ARCHIVE_LOG=YES
    fi
    if [ `tail --lines=10 /var/xdrago/log/lsyncd.monitor.log \
      | grep --count "NRM lsyncd"` -gt "3" ] && [ -n "${_MY_EMAIL}" ]; then
      mail -s "NOTICE: lsyncd NRM problem on $(uname -n 2>&1)" ${_MY_EMAIL} < \
        /var/xdrago/log/lsyncd.monitor.log
      _ARCHIVE_LOG=YES
    fi
    if [ "$_ARCHIVE_LOG" = "YES" ]; then
      cat /var/xdrago/log/lsyncd.monitor.log >> \
        /var/xdrago/log/lsyncd.warn.archive.log
      rm -f /var/xdrago/log/lsyncd.monitor.log
    fi
  fi
}

if [ -e "/root/.mysqladmin.monitor.cnf" ]; then
  _SQLMONITOR=YES
fi
lsyncd_proc_control
mysql_proc_control
sleep 5
mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx
sleep 5
mysql_proc_control
sleep 5
mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx
sleep 5
mysql_proc_control
sleep 5
perl /var/xdrago/monitor/check/escapecheck
perl /var/xdrago/monitor/check/hackcheck
perl /var/xdrago/monitor/check/hackftp
perl /var/xdrago/monitor/check/scan_nginx
if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/locked
fi
perl /var/xdrago/monitor/check/sqlcheck
echo DONE!
exit 0
###EOF2020###
