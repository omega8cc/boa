#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/xdrago/log/oom.incident.log"
_oldOml="/var/xdrago/log/oom.incident.old.log"

_check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

if [ $(pgrep -f minute.sh | grep -v "^$$" | wc -l) -gt 4 ]; then
  echo "Too many minute.sh running $(date 2>&1)" >> /var/xdrago/log/too.many.log
  exit 0
fi

[ ! -d "/var/xdrago/monitor/log" ] && mkdir -p /var/xdrago/monitor/log

if [ -e "${_pthOml}" ] && [ ! -e "${_oldOml}" ]; then
  mv -f ${_pthOml} ${_oldOml}
fi

bash /var/xdrago/monitor/check/nginx.sh &
bash /var/xdrago/monitor/check/php.sh &
bash /var/xdrago/monitor/check/redis.sh &
bash /var/xdrago/monitor/check/mysql.sh &
bash /var/xdrago/monitor/check/unbound.sh &
bash /var/xdrago/monitor/check/system.sh &
bash /var/xdrago/monitor/check/java.sh &
perl /var/xdrago/monitor/check/hackcheck.pl &
perl /var/xdrago/monitor/check/hackftp.pl &
perl /var/xdrago/monitor/check/escapecheck.pl &

_second_flood_guard() {
  thisCountSec=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/second.sh"`
  if [ ${thisCountSec} -gt "4" ]; then
    echo "$(date 2>&1) Too many ${thisCountSec} second.sh processes killed" >> \
      /var/log/sec-count.kill.log
    kill -9 $(ps aux | grep '[s]econd.sh' | awk '{print $2}') &> /dev/null
  fi
}
[ ! -e "/run/boa_run.pid" ] && _second_flood_guard

echo DONE!
exit 0
###EOF2024###
