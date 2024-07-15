#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

###-------------SYSTEM-----------------###

check_root() {
  if [ `whoami` = "root" ]; then
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be ran as a root user"
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
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
}

load_control() {
  if [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
    _CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO//[^0-9]/}
  fi
  if [ -z "${_CPU_SPIDER_RATIO}" ]; then
    _CPU_SPIDER_RATIO=6
  fi
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  _O_LOAD_MAX=$(( 99 * _CPU_SPIDER_RATIO ))
}

action() {
for Runner in `find /var/xdrago -maxdepth 1 -mindepth 1 -type f \
  | grep run- \
  | uniq \
  | sort`; do
  count_cpu
  load_control
  if [ "${_O_LOAD}" -lt "${_O_LOAD_MAX}" ]; then
    echo load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}
    if [ ! -e "/run/boa_wait.pid" ]; then
      echo running ${Runner}
      bash ${Runner}
      n=$((RANDOM%9+2))
      echo waiting $n sec
      sleep $n
    else
      echo "Another BOA task is running, we have to wait..."
    fi
  else
    echo load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}
  fi
done
}

###-------------SYSTEM-----------------###

if [ -e "/run/boa_wait.pid" ] \
  || [ -e "/run/boa_cron_wait.pid" ]; then
  touch /var/xdrago/log/wait-runner.pid
  echo "Another BOA task is running, we will try again later..."
  exit 0
elif [ `ps aux | grep -v "grep" \
  | grep --count "n7 bash.*runner"` -gt "8" ]; then
  touch /var/xdrago/log/wait-runner.pid
  echo "Too many Aegir tasks running now, we will try again later..."
  exit 0
else
  if [ -e "/root/.wbhd.clstr.cnf" ] \
    || [ -e "/root/.dbhd.clstr.cnf" ]; then
    echo "Aegir tasks ignored on this cluster node"
    exit 0
  fi
  if [ -e "/root/.slow.cron.cnf" ]; then
    touch /run/boa_cron_wait.pid
    sleep 15
    action
    sleep 15
    rm -f /run/boa_cron_wait.pid
  elif [ -e "/root/.fast.cron.cnf" ]; then
    rm -f /run/boa_cron_wait.pid
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
    sleep 5
    action
  else
    action
  fi
  exit 0
fi
###EOF2024###
