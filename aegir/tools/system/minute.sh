#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/oom.incident.log"
oldOml="/var/xdrago/log/oom.incident.old.log"

check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
check_root

if [ $(pgrep -f minute.sh | grep -v "^$$" | wc -l) -gt 1 ]; then
  echo "Too many minute.sh running $(date 2>&1)" >> /var/xdrago/log/too.many.log
  exit 0
fi

[ ! -d "/var/xdrago/monitor/log" ] && mkdir -p /var/xdrago/monitor/log

if [ -e "${pthOml}" ] && [ ! -e "${oldOml}" ]; then
  mv -f ${pthOml} ${oldOml}
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

echo DONE!
exit 0
###EOF2024###
