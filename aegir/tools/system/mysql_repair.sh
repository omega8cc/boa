#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ $(pgrep -f mysql_repair.sh | grep -v "^$$" | wc -l) -gt 1 ]; then
  echo "Too many mysql_repair.sh running $(date 2>&1)" >> /var/xdrago/log/too.many.log
  exit 0
fi

touch /run/boa_wait.pid
sleep 8
dir=/var/xdrago/log/mysql_optimize
mkdir -p $dir
_SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
_SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
/usr/bin/mysqlcheck -u root -Aa >> $dir/all.a.`date +%y%m%d-%H%M%S`
/usr/bin/mysqlcheck -u root -A --auto-repair >> $dir/all.r.`date +%y%m%d-%H%M%S`
/usr/bin/mysqlcheck -u root -Ao >> $dir/all.o.`date +%y%m%d-%H%M%S`
[ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
exit 0
###EOF2024###
