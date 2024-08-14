#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/oom.incident.log"

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
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
check_root

if_fix_locked_sshd() {
  _SSH_LOG="/var/log/auth.log"
  if [ `tail --lines=100 ${_SSH_LOG} \
    | grep --count "error: Bind to port 22"` -gt "0" ]; then
    kill -9 $(ps aux | grep '[s]tartups' | awk '{print $2}') &> /dev/null
    service ssh start
  fi
}
if_fix_locked_sshd

if_fix_dhcp() {
  if [ -e "/var/log/daemon.log" ]; then
    _DHCP_LOG="/var/log/daemon.log"
  else
    _DHCP_LOG="/var/log/syslog"
  fi
  if [ -e "${_DHCP_LOG}" ]; then
    if [ `tail --lines=100 ${_DHCP_LOG} \
      | grep --count "dhclient.*Failed"` -gt "0" ]; then
      sed -i "s/.*DHCP.*//g" /etc/csf/csf.allow
      wait
      sed -i "/^$/d" /etc/csf/csf.allow
      _DHCP_TEST=$(grep DHCPREQUEST ${_DHCP_LOG} | cut -d ' ' -f13 | sort | uniq 2>&1)
      if [[ "${_DHCP_TEST}" =~ "port" ]]; then
        for _IP in `grep DHCPREQUEST ${_DHCP_LOG} | cut -d ' ' -f12 | sort | uniq`;do echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow;done
      else
        for _IP in `grep DHCPREQUEST ${_DHCP_LOG} | cut -d ' ' -f13 | sort | uniq`;do echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow;done
      fi
      csf -q &> /dev/null
    fi
  fi
}
if_fix_dhcp

if [ -e "/root/.step.init.systemd.two.cnf" ]; then
  kill -9 $(ps aux | grep '[s]ystemd-udevd' | awk '{print $2}') &> /dev/null
fi

sql_restart() {
  touch /run/boa_run.pid
  echo "$(date 2>&1) $1 incident detected"                          >> ${pthOml}
  sleep 5
  echo "$(date 2>&1) $1 incident response started"                  >> ${pthOml}
  kill -9 $(ps aux | grep '[w]khtmltopdf' | awk '{print $2}') &> /dev/null
  killall sleep &> /dev/null
  killall php
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date 2>&1) $1 incident mysql restarted"                   >> ${pthOml}
  echo "$(date 2>&1) $1 incident response completed"                >> ${pthOml}
  echo                                                              >> ${pthOml}
  sleep 5
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

if [ -e "/var/log/daemon.log" ]; then
  _SQL_LOG="/var/log/daemon.log"
else
  _SQL_LOG="/var/log/syslog"
fi
if [ -e "${_SQL_LOG}" ]; then
  if [ `tail --lines=10 ${_SQL_LOG} \
    | grep --count "Too many connections"` -gt "0" ]; then
    sql_restart "BUSY"
  fi
fi

_SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
_SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
_IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
if [ ! -z "${_IS_MYSQLD_RUNNING}" ] && [ ! -z "${_SQL_PSWD}" ]; then
  _MYSQL_CONN_TEST=$(mysql -u root -e "status" 2>&1)
  echo _MYSQL_CONN_TEST ${_MYSQL_CONN_TEST}
  if [[ "${_MYSQL_CONN_TEST}" =~ "Too many connections" ]]; then
    sql_restart "BUSY"
  fi
fi

if [ -e "/var/lib/mysql/ibtmp1" ] && [ ! -e "/run/boa_run.pid" ]; then
  _SQL_TEMP_SIZE_TEST=$(du -s -h /var/lib/mysql/ibtmp1)
  if [[ "${_SQL_TEMP_SIZE_TEST}" =~ "G" ]]; then
    echo ${_SQL_TEMP_SIZE_TEST} too big
    echo SQL restart forced
    echo "$(date 2>&1) ${_SQL_TEMP_SIZE_TEST} too big, SQL restart forced" >> \
      /var/xdrago/log/giant.ibtmp1.incident.log
    sql_restart "BIGTMP"
  fi
fi

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

check_unbound() {
  if [ -x "/usr/sbin/unbound" ] \
    && [ ! -e "/etc/resolvconf/run/interface/lo.unbound" ]; then
    mkdir -p /etc/resolvconf/run/interface
    echo "nameserver 127.0.0.1" > /etc/resolvconf/run/interface/lo.unbound
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
    resolvconf -u &> /dev/null
    killall -9 unbound &> /dev/null
    service unbound restart &> /dev/null
    unbound-control reload &> /dev/null
  fi
  if [ -e "/etc/resolv.conf" ]; then
    _RESOLV_LOC=$(grep "nameserver 127.0.0.1" /etc/resolv.conf 2>&1)
    _RESOLV_ELN=$(grep "nameserver 1.1.1.1" /etc/resolv.conf 2>&1)
    _RESOLV_EGT=$(grep "nameserver 8.8.8.8" /etc/resolv.conf 2>&1)
    if [[ "${_RESOLV_LOC}" =~ "nameserver 127.0.0.1" ]] \
      && [[ "${_RESOLV_ELN}" =~ "nameserver 1.1.1.1" ]] \
      && [[ "${_RESOLV_EGT}" =~ "nameserver 8.8.8.8" ]]; then
      _THIS_DNS_TEST=$(host files.aegir.cc 127.0.0.1 -w 3 2>&1)
      if [[ "${_THIS_DNS_TEST}" =~ "no servers could be reached" ]]; then
        service unbound stop &> /dev/null
        sleep 1
        killall -9 unbound &> /dev/null
        renice ${_B_NICE} -p $$ &> /dev/null
        perl /var/xdrago/proc_num_ctrl.cgi
      fi
    else
      rm -f /etc/resolv.conf
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      if [ -e "${vBs}/resolv.conf.vanilla" ]; then
        cat ${vBs}/resolv.conf.vanilla >> /etc/resolv.conf
      fi
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      echo "nameserver 1.0.0.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 8.8.4.4" >> /etc/resolv.conf
      [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
      killall -9 unbound &> /dev/null
      service unbound restart &> /dev/null
      unbound-control reload &> /dev/null
    fi
  fi
}
check_unbound

if [ -e "/var/log/php" ]; then
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "already listen on"` -gt "0" ]; then
    touch /run/fmp_wait.pid
    touch /run/restarting_fmp_wait.pid
    sleep 8
    kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    rm -f /run/*.fpm.socket
    renice ${_B_NICE} -p $$ &> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        service php${e}-fpm start
      fi
    done
    sleep 8
    rm -f /run/fmp_wait.pid
    rm -f /run/restarting_fmp_wait.pid
    echo "$(date 2>&1) FPM instances conflict detected" >> \
      /var/xdrago/log/fpm.conflict.incident.log
  fi
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "process.max"` -gt "0" ]; then
    touch /run/fmp_wait.pid
    touch /run/restarting_fmp_wait.pid
    sleep 8
    kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    rm -f /run/*.fpm.socket
    renice ${_B_NICE} -p $$ &> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        service php${e}-fpm start
      fi
    done
    sleep 8
    rm -f /run/fmp_wait.pid
    rm -f /run/restarting_fmp_wait.pid
    echo "$(date 2>&1) Too many running FPM childs detected" >> \
      /var/xdrago/log/fpm.childs.incident.log
  fi
fi

_PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>&1)
if [[ "${_PHPLOG_SIZE_TEST}" =~ "G" ]]; then
  echo ${_PHPLOG_SIZE_TEST} too big
  touch /run/fmp_wait.pid
  rm -f /var/log/php/*
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm reload
    fi
  done
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
  rm -f /run/fmp_wait.pid
  echo "$(date 2>&1) Too big PHP error logs deleted: ${_PHPLOG_SIZE_TEST}" >> \
    /var/xdrago/log/php.giant.logs.incident.log
fi

almost_oom_kill() {
  touch /run/boa_run.pid
  echo "$(date 2>&1) Almost OOM $1 detected"                        >> ${pthOml}
  sleep 5
  echo "$(date 2>&1) Almost OOM incident response started"          >> ${pthOml}
  kill -9 $(ps aux | grep '[w]khtmltopdf' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) Almost OOM wkhtmltopdf killed"                 >> ${pthOml}
  killall sleep &> /dev/null
  killall php
  echo "$(date 2>&1) Almost OOM php-cli killed"                     >> ${pthOml}
  echo "$(date 2>&1) Almost OOM incident response completed"        >> ${pthOml}
  echo                                                              >> ${pthOml}
  sleep 5
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

oom_restart() {
  touch /run/boa_run.pid
  echo "$(date 2>&1) OOM $1 detected"                               >> ${pthOml}
  sleep 5
  echo "$(date 2>&1) OOM incident response started"                 >> ${pthOml}
  kill -9 $(ps aux | grep '[w]khtmltopdf' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM wkhtmltopdf killed"                        >> ${pthOml}
  killall sleep &> /dev/null
  killall php
  echo "$(date 2>&1) OOM php-cli killed"                            >> ${pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/`date +%y%m%d-%H%M`-error.log
  kill -9 $(ps aux | grep '[n]ginx' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM nginx killed"                              >> ${pthOml}
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM php-fpm killed"                            >> ${pthOml}
  kill -9 $(ps aux | grep '[j]ava' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM solr/jetty killed"                         >> ${pthOml}
  kill -9 $(ps aux | grep '[n]ewrelic-daemon' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM newrelic-daemon killed"                    >> ${pthOml}
  kill -9 $(ps aux | grep '[r]edis-server' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM redis-server killed"                       >> ${pthOml}
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date 2>&1) OOM mysql restarted"                           >> ${pthOml}
  echo "$(date 2>&1) OOM incident response completed"               >> ${pthOml}
  echo                                                              >> ${pthOml}
  sleep 5
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
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

if [ ! -z "${_RAM_PCT_FREE}" ] && [ "${_RAM_PCT_FREE}" -le "15" ]; then
  oom_restart "RAM"
elif [ "${_RAM_PCT_FREE}" -le "20" ]; then
  if [ `ps aux | grep -v "grep" | grep --count "wkhtmltopdf"` -gt "2" ]; then
    almost_oom_kill "RAM"
  fi
fi

redis_bind_check() {
  if [ `tail --lines=8 /var/log/redis/redis-server.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    service redis-server stop &> /dev/null
    killall -9 redis-server &> /dev/null
    rm -f /var/lib/redis/*
    service redis-server start &> /dev/null
    echo "$(date 2>&1) RedisException BIND detected"
    echo "$(date 2>&1) RedisException BIND detected" >> /var/xdrago/log/redis.watch.log
  fi
}
redis_bind_check

redis_oom_check() {
  if [ `tail --lines=500 /var/log/php/error_log_* \
    | grep --count "RedisException"` -gt "0" ]; then
    service redis-server stop &> /dev/null
    killall -9 redis-server &> /dev/null
    rm -f /var/lib/redis/*
    service redis-server start &> /dev/null
    echo "$(date 2>&1) RedisException OOM detected"
    echo "$(date 2>&1) RedisException OOM detected" >> /var/xdrago/log/redis.watch.log
    touch /run/fmp_wait.pid
    sleep 8
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    renice ${_B_NICE} -p $$ &> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        service php${e}-fpm reload
      fi
    done
    sleep 8
    rm -f /run/fmp_wait.pid
  fi
}
redis_oom_check

redis_slow_check() {
  if [ `tail --lines=500 /var/log/php/fpm-*-slow.log \
    | grep --count "PhpRedis.php"` -gt "5" ]; then
    touch /run/fmp_wait.pid
    sleep 8
    service redis-server stop &> /dev/null
    killall -9 redis-server &> /dev/null
    rm -f /var/lib/redis/*
    service redis-server start &> /dev/null
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    renice ${_B_NICE} -p $$ &> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        service php${e}-fpm reload
      fi
    done
    sleep 8
    rm -f /run/fmp_wait.pid
    echo "$(date 2>&1) Slow PhpRedis detected" >> \
      /var/xdrago/log/redis.slow.incident.log
  fi
}
redis_slow_check

fpm_sockets_healing() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    touch /run/fmp_wait.pid
    touch /run/restarting_fmp_wait.pid
    sleep 8
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    _NOW=${_NOW//[^0-9-]/}
    mkdir -p /var/backups/php-logs/${_NOW}/
    mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
    kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
    renice ${_B_NICE} -p $$ &> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        service php${e}-fpm start
      fi
    done
    sleep 8
    rm -f /run/fmp_wait.pid
    rm -f /run/restarting_fmp_wait.pid
    echo "$(date 2>&1) FPM Sockets conflict detected" >> \
      /var/xdrago/log/fpm.sockets.incident.log
  fi
}
fpm_sockets_healing

jetty_restart() {
  touch /run/boa_wait.pid
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
  [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
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

if [ `ps aux | grep -v "grep" | grep --count "/usr/sbin/cron"` -gt "1" ]; then
  service cron stop &> /dev/null
  killall cron &> /dev/null
  service cron start &> /dev/null
  echo "$(date 2>&1) Too many Cron instances running killed" >> \
    /var/xdrago/log/cron-count.kill.log
fi

if [ `ps aux | grep -v "grep" | grep --count "php-fpm: master process"` -gt "10" ]; then
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) Too many PHP-FPM master processes killed" >> \
    /var/xdrago/log/php-fpm-master-count.kill.log
fi

if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
  kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) Too many dirmngr processes killed" >> \
    /var/xdrago/log/dirmngr-count.kill.log
fi

if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
  kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) Too many gpg-agent processes killed" >> \
    /var/xdrago/log/gpg-agent-count.kill.log
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
      xkill=$(mysqladmin -u root kill $each 2>&1)
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
    echo "$(mysqladmin -u root proc -v 2>&1)" >> /var/xdrago/log/mysqladmin.monitor.log
    if [ ! -z "${_RAM_PCT_FREE}" ] && [ "${_RAM_PCT_FREE}" -lt "20" ]; then
      sql_restart "RAM"
    fi
  fi
  limit=300
  xkill=null
  for each in `mysqladmin -u root proc \
    | awk '{print $2, $4, $8, $12}' \
    | awk '{print $1}'`; do
    each=${each//[^0-9]/}
    [ ! -z "$each" ] && echo "each is $each"
    if [ ! -z "$each" ]; then
      if [ "$each" -gt "5" ] \
        && [ ! -z "$each" ]; then
        xtime=$(mysqladmin -u root proc \
          | awk '{print $2, $4, $8, $12}' \
          | grep $each \
          | awk '{print $4}' 2>&1)
        xtime=${xtime//[^0-9]/}
        [ ! -z "$xtime" ] && echo "xtime is $xtime [ea:$each]"
        xuser=$(mysqladmin -u root proc \
          | awk '{print $2, $4, $8, $12}' \
          | grep $each \
          | awk '{print $2}' 2>&1)
        xuser=${xuser//[^0-9a-z_]/}
        [ ! -z "$xuser" ] && echo "xuser is $xuser [xt:$xtime] [ea:$each]"
        if [ ! -z "$xtime" ]; then
          if [ -e "/root/.sql.blacklist.cnf" ]; then
            # cat /root/.sql.blacklist.cnf
            # xsqlfoo # db name/user causing problems, w/o # in front
            # xsqlbar # db name/user causing problems, w/o # in front
            # xsqlnew # db name/user causing problems, w/o # in front
            for _XQ in `cat /root/.sql.blacklist.cnf \
              | cut -d '#' -f1 \
              | sort \
              | uniq`; do
              echo "ABUSE is ${_XQ}"
              echo "xuser is ${xuser}"
              if [ "$xuser" = "${_XQ}" ]; then
                echo "checking via mysql_proc_kill ${_XQ} [xt:$xtime] [ea:$each] to avoid issues"
                limit=10
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
    if [ "${_ARCHIVE_LOG}" = "YES" ]; then
      cat /var/xdrago/log/lsyncd.monitor.log >> \
        /var/xdrago/log/lsyncd.warn.archive.log
      rm -f /var/xdrago/log/lsyncd.monitor.log
    fi
  fi
}

if [ -e "/run/boa_sql_backup.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ]; then
  _SQL_CTRL=NO
else
  _SQL_CTRL=YES
fi

if_redis_restart() {
  PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  ReTest=$(ls /data/disk/*/static/control/run-redis-restart.pid | wc -l 2>&1)
  if [[ "${PrTestPower}" =~ "POWER" ]] \
    || [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.redis.restart.cnf" ]; then
    if [ "${ReTest}" -ge "1" ]; then
      service redis-server restart &> /dev/null
      wait
      rm -f /data/disk/*/static/control/run-redis-restart.pid
      echo "$(date 2>&1) Redis Server restart forced" >> \
        /var/xdrago/log/redis-server-restart.event.log
    fi
  fi
}
[ -d "/data/u" ] && if_redis_restart

if_nginx_restart() {
  PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  ReTest=$(ls /data/disk/*/static/control/run-nginx-restart.pid | wc -l 2>&1)
  if [[ "${PrTestPower}" =~ "POWER" ]] \
    || [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.nginx.restart.cnf" ]; then
    if [ "${ReTest}" -ge "1" ]; then
      kill -9 $(ps aux | grep '[n]ginx' | awk '{print $2}') &> /dev/null
      service nginx start
      wait
      rm -f /data/disk/*/static/control/run-nginx-restart.pid
      echo "$(date 2>&1) Nginx Server restart forced" >> \
        /var/xdrago/log/nginx-server-restart.event.log
    fi
  fi
}
[ -d "/data/u" ] && if_nginx_restart

if [ -e "/root/.mysqladmin.monitor.cnf" ]; then
  _SQLMONITOR=YES
fi
lsyncd_proc_control
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx &> /dev/null
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx &> /dev/null
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx &> /dev/null
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx &> /dev/null
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
perl /var/xdrago/monitor/check/scan_nginx &> /dev/null
sleep 5
[ "${_SQL_CTRL}" = "YES" ] && mysql_proc_control
sleep 5
perl /var/xdrago/monitor/check/escapecheck &> /dev/null
perl /var/xdrago/monitor/check/hackcheck &> /dev/null
perl /var/xdrago/monitor/check/hackftp &> /dev/null
perl /var/xdrago/monitor/check/scan_nginx &> /dev/null
if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/locked &> /dev/null
fi
perl /var/xdrago/monitor/check/sqlcheck &> /dev/null
echo DONE!
exit 0
###EOF2024###
