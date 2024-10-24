#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_check_root() {
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
_check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.pause_tasks_maint.cnf" ]; then
  exit 0
fi

if (( $(pgrep -fc 'purge_binlogs.sh') > 2 )); then
  echo "Too many purge_binlogs.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_count_cpu() {
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

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

_load_control() {
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  : "${_CPU_TASK_RATIO:=3.1}"
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

_purge_action() {
  _count_cpu
  _load_control
  if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
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
  _purge_action
  touch /var/xdrago/log/last-run-purge
  exit 0
fi
###EOF2024###
