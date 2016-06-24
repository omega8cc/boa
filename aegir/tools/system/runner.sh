#!/bin/bash

PATH=/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash

###-------------SYSTEM-----------------###

check_root() {
  if [ `whoami` = "root" ]; then
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
    _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  fi
  if [ -z "${_CPU_MAX_RATIO}" ]; then
    _CPU_MAX_RATIO=6
  fi
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
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
    if [ ! -e "/var/run/boa_wait.pid" ] \
      && [ ! -e "/var/run/manage_rvm_users.pid" ]; then
      echo running ${Runner}
      bash ${Runner}
    fi
    n=$((RANDOM%9+2))
    echo waiting $n sec
    sleep $n
  else
    echo load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}
  fi
done
}

###-------------SYSTEM-----------------###

if [ -e "/var/run/boa_wait.pid" ] \
  || [ -e "/var/run/manage_rvm_users.pid" ]; then
  touch /var/xdrago/log/wait-runner
  exit 0
elif [ `ps aux | grep -v "grep" \
  | grep --count "c bash.*runner"` -gt "2" ]; then
  touch /var/xdrago/log/wait-runner
  exit 0
else
  if [ -e "/root/.wbhd.clstr.cnf" ] \
    || [ -e "/root/.dbhd.clstr.cnf" ]; then
    exit 0
  fi
  if [ -e "/root/.fast.cron.cnf" ]; then
    action
    sleep 10
    action
    sleep 10
    action
    sleep 10
    action
    sleep 10
    action
    sleep 10
    action
  else
    action
  fi
  exit 0
fi
###EOF2016###
