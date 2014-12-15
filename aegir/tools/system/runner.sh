#!/bin/bash

SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin

###-------------SYSTEM-----------------###

count_cpu()
{
  _CPU_INFO=$(grep -c processor /proc/cpuinfo)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc)
  if [ -z "$_NPROC_TEST" ] ; then
    _CPU_NR="$_CPU_INFO"
  else
    _CPU_NR=`nproc`
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "$_CPU_NR" ] && [ ! -z "$_CPU_INFO" ] && [ "$_CPU_NR" -gt "$_CPU_INFO" ] && [ "$_CPU_INFO" -gt "0" ] ; then
    _CPU_NR="$_CPU_INFO"
  fi
  if [ -z "$_CPU_NR" ] || [ "$_CPU_NR" -lt "1" ] ; then
    _CPU_NR=1
  fi
}

load_control()
{
  if [ -e "/root/.barracuda.cnf" ] ; then
    source /root/.barracuda.cnf
    _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  fi
  if [ -z "$_CPU_MAX_RATIO" ] ; then
    _CPU_MAX_RATIO=6
  fi
  _O_LOAD=`awk '{print $1*100}' /proc/loadavg`
  let "_O_LOAD = (($_O_LOAD / $_CPU_NR))"
  let "_O_LOAD_MAX = ((100 * $_CPU_MAX_RATIO))"
}

action()
{
for Runner in `find /var/xdrago -maxdepth 1 -mindepth 1 -type f | grep run- | uniq | sort`
do
  count_cpu
  load_control
  if [ $_O_LOAD -lt $_O_LOAD_MAX ] ; then
    echo load is $_O_LOAD while maxload is $_O_LOAD_MAX
    n=$((RANDOM%9+2))
    echo waiting $n sec
    sleep $n
    if [ ! -e "/var/run/boa_wait.pid" ] && [ ! -e "/var/run/manage_rvm_users.pid" ] ; then
      echo running $Runner
      bash $Runner
    fi
  else
    echo load is $_O_LOAD while maxload is $_O_LOAD_MAX
  fi
done
}

###-------------SYSTEM-----------------###

if [ -e "/var/run/task_runner.pid" ] || [ -e "/var/run/boa_wait.pid" ] || [ -e "/var/run/manage_rvm_users.pid" ] ; then
  touch /var/xdrago/log/wait-runner
  exit 0
else
  if [ -e "/root/.wbhd.clstr.cnf" ] || [ -e "/root/.dbhd.clstr.cnf" ] ; then
    exit 0
  fi
  touch /var/run/task_runner.pid
  sleep 5
  action
  sleep 5
  rm -f /var/run/task_runner.pid
  exit 0
fi
###EOF2014###
