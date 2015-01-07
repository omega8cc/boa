#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

count_cpu() {
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

load_control() {
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

action() {
  count_cpu
  load_control
  if [ $_O_LOAD -lt $_O_LOAD_MAX ] ; then
    echo load is $_O_LOAD while maxload is $_O_LOAD_MAX
    echo ...now doing CTL...
/usr/bin/mysql --default-character-set=utf8 mysql<<EOFMYSQL
PURGE MASTER LOGS BEFORE DATE_SUB( NOW( ), INTERVAL 1 HOUR);
EOFMYSQL
    touch /var/xdrago/log/purge_binlogs.done
    echo CTL done
  else
    echo load is $_O_LOAD while maxload is $_O_LOAD_MAX
    echo ...we have to wait...
  fi
}

if [ -e "/var/run/boa_wait.pid" ] ; then
  touch /var/xdrago/log/wait-purge
  exit 0
else
  action
  touch /var/xdrago/log/last-run-purge
  exit 0
fi
###EOF2015###
