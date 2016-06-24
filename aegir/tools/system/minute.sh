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

check_pdnsd() {
  if [ -e "/etc/resolv.conf" ]; then
    _RESOLV_TEST=$(grep "nameserver 127.0.0.1" /etc/resolv.conf 2>&1)
    if [[ "$_RESOLV_TEST" =~ "nameserver 127.0.0.1" ]]; then
      _THIS_DNS_TEST=$(host -a files.aegir.cc 127.0.0.1 -w 3 2>&1)
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
    rm -f /var/log/php/*
    rm -f /var/run/*.fpm.socket
    renice ${_B_NICE} -p $$ &> /dev/null
    if [ -e "/etc/init.d/php70-fpm" ]; then
      service php70-fpm start
    fi
    if [ -e "/etc/init.d/php56-fpm" ]; then
      service php56-fpm start
    fi
    if [ -e "/etc/init.d/php55-fpm" ]; then
      service php55-fpm start
    fi
    if [ -e "/etc/init.d/php54-fpm" ]; then
      service php54-fpm start
    fi
    if [ -e "/etc/init.d/php53-fpm" ]; then
      service php53-fpm start
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
    rm -f /var/log/php/*
    renice ${_B_NICE} -p $$ &> /dev/null
    if [ -e "/etc/init.d/php70-fpm" ]; then
      service php70-fpm start
    fi
    if [ -e "/etc/init.d/php56-fpm" ]; then
      service php56-fpm start
    fi
    if [ -e "/etc/init.d/php55-fpm" ]; then
      service php55-fpm start
    fi
    if [ -e "/etc/init.d/php54-fpm" ]; then
      service php54-fpm start
    fi
    if [ -e "/etc/init.d/php53-fpm" ]; then
      service php53-fpm start
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
  if [ -e "/etc/init.d/php70-fpm" ]; then
    service php70-fpm reload
  fi
  if [ -e "/etc/init.d/php56-fpm" ]; then
    service php56-fpm reload
  fi
  if [ -e "/etc/init.d/php55-fpm" ]; then
    service php55-fpm reload
  fi
  if [ -e "/etc/init.d/php54-fpm" ]; then
    service php54-fpm reload
  fi
  if [ -e "/etc/init.d/php53-fpm" ]; then
    service php53-fpm reload
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

if [ -e "/var/log/nginx/error.log" ]; then
  if [ `tail --lines=500 /var/log/nginx/error.log \
    | grep --count "Cannot allocate memory"` -gt "0" ]; then
    oom_restart "nginx"
  fi
fi

_RAM_TOTAL=$(free -m | grep Mem: | cut -d: -f2 | awk '{ print $1}' 2>&1)
_RAM_FREE=$(free -m | grep /+ | cut -d: -f2 | awk '{ print $2}' 2>&1)
_RAM_PCT_FREE=$(echo "scale=0; $(bc -l <<< "${_RAM_FREE} / ${_RAM_TOTAL} * 100")/1" | bc 2>&1)
_RAM_PCT_FREE=${_RAM_PCT_FREE//[^0-9]/}

if [ ! -z "${_RAM_PCT_FREE}" ] && [ "${_RAM_PCT_FREE}" -lt "10" ]; then
  oom_restart "ram"
fi

jetty_restart() {
  touch /var/run/boa_run.pid
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
  rm -f /var/run/boa_run.pid
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

if [ `ps aux | grep -v "grep" | grep --count "php-fpm: master process"` -gt "5" ]; then
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) Too many PHP-FPM master processes killed" >> \
    /var/xdrago/log/php-fpm-master-count.kill.log
fi

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/segfault_alert
fi

mysql_proc_kill() {
  if [ "$xtime" != "Time" ] \
    && [ "$xuser" != "root" ] \
    && [ "$xuser" != "system" ] \
    && [ "$xtime" != "|" ] \
    && [[ "$xtime" -gt "$limit" ]]; then
    xkill=$(mysqladmin kill $each 2>&1)
    times=$(date 2>&1)
    echo $times $each $xuser $xtime $xkill
    echo "$times $each $xuser $xtime $xkill" >> /var/xdrago/log/sql_watch.log
  fi
}

mysql_proc_control() {
  if [ ! -z "${_SQLMONITOR}" ] && [ "${_SQLMONITOR}" = "YES" ]; then
    echo "$(date 2>&1)" >> /var/xdrago/log/mysqladmin.monitor.log
    echo "$(mysqladmin proc 2>&1)" >> /var/xdrago/log/mysqladmin.monitor.log
  fi
  limit=3600
  xkill=null
  for each in `mysqladmin proc \
    | awk '{print $2, $4, $8, $12}' \
    | awk '{print $1}'`; do
    if [ "$each" != "1" ] \
      && [ "$each" != "2" ] \
      && [ "$each" != "Id" ] \
      && [ ! -z "$each" ]; then
      xtime=$(mysqladmin proc \
        | awk '{print $2, $4, $8, $12}' \
        | grep $each \
        | awk '{print $4}' 2>&1)
      if [ "$xtime" = "|" ]; then
        xtime=$(mysqladmin proc \
          | awk '{print $2, $4, $8, $11}' \
          | grep $each \
          | awk '{print $4}' 2>&1)
      fi
      xuser=$(mysqladmin proc \
        | awk '{print $2, $4, $8, $12}' \
        | grep $each \
        | awk '{print $2}' 2>&1)
      if [ "$xtime" != "Time" ]; then
        if [ "$xuser" = "xabuse" ]; then
          limit=60
          mysql_proc_kill
        else
          limit=3600
          mysql_proc_kill
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
###EOF2016###
