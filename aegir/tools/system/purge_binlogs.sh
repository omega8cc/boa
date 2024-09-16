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

if [ -e "/root/.pause_tasks_maint.cnf" ]; then
  exit 0
fi

if [ `ps aux | grep -v "grep" | grep --count "purge_binlogs.sh"` -gt "2" ]; then
  echo "Too many purge_binlogs.sh running"
  exit 0
fi

count_cpu() {
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt "0" ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] \
    || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
}

load_control() {
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  export _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  : "${_CPU_MAX_RATIO:=6}"
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
}

action() {
  count_cpu
  load_control
  if [ "${_O_LOAD}" -lt "${_O_LOAD_MAX}" ]; then
    echo load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}
/usr/bin/mysql mysql<<EOFMYSQL
PURGE MASTER LOGS BEFORE DATE_SUB( NOW( ), INTERVAL 1 HOUR);
EOFMYSQL
    touch /var/xdrago/log/purge_binlogs.done
  fi
}

if [ -e "/run/boa_wait.pid" ]; then
  touch /var/xdrago/log/wait-purge.pid
  exit 0
else
  action
  touch /var/xdrago/log/last-run-purge
  exit 0
fi
###EOF2024###
