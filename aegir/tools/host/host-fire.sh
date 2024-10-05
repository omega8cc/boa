#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Exit if more than 2 instances of the script are running
if (( $(pgrep -fc 'host-fire.sh') > 2 )); then
  # Optional: Log too many instances
  echo "$(date) Too many host-fire.sh running" >> /var/xdrago/log/too.many.log
  exit 0
fi

_guest_proc_monitor() {
  for i in `dir -d /vservers/*`; do
    _THIS_VM=`echo $i | cut -d'/' -f3 | awk '{ print $1}'`
    _VS_NAME=`echo ${_THIS_VM} | cut -d'/' -f3 | awk '{ print $1}'`
    if [ -e "${i}/var/xdrago/proc_num_ctrl.pl" ] \
      && [ ! -e "${i}/run/fmp_wait.pid" ] \
      && [ ! -e "${i}/run/boa_wait.pid" ] \
      && [ ! -e "${i}/run/boa_run.pid" ] \
      && [ ! -e "${i}/run/mysql_restart_running.pid" ] \
      && [ -e "/usr/var/run${i}" ]; then
      vserver ${_VS_NAME} exec perl /var/xdrago/proc_num_ctrl.pl &
    fi
  done
}
###_guest_proc_monitor

_guest_guard() {
if [ ! -e "/run/fire.pid" ] && [ ! -e "/run/water.pid" ]; then
  touch /run/fire.pid
  echo start `date`
  for i in `dir -d /vservers/*`; do
    if [ -e "${i}/var/xdrago/monitor/log/ssh.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/var/xdrago/monitor/log/ssh.log | cut -d '#' -f1 | sort`; do
        _FW_TEST=
        _FF_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        _FF_TEST=$(grep "=${_IP} " /etc/csf/csf.allow 2>&1)
        if [[ "${_FF_TEST}" =~ "${_IP}" ]] || [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 22"
          if [[ "${_FF_TEST}" =~ "${_IP}" ]]; then
            csf -dr ${_IP}
            csf -tr ${_IP}
          fi
        else
          echo "Deny ${_IP} on ports 21,22,443,80 in the next 1h"
          csf -td ${_IP} 3600 -p 21
          csf -td ${_IP} 3600 -p 22
          csf -td ${_IP} 3600 -p 443
          csf -td ${_IP} 3600 -p 80
        fi
      done
    fi
    if [ -e "${i}/var/xdrago/monitor/log/web.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/var/xdrago/monitor/log/web.log | cut -d '#' -f1 | sort`; do
        _FW_TEST=
        _FF_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        _FF_TEST=$(grep "=${_IP} " /etc/csf/csf.allow 2>&1)
        if [[ "${_FF_TEST}" =~ "${_IP}" ]] || [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 80"
          if [[ "${_FF_TEST}" =~ "${_IP}" ]]; then
            csf -dr ${_IP}
            csf -tr ${_IP}
          fi
        else
          echo "Deny ${_IP} on ports 21,22,443,80 in the next 1h"
          csf -td ${_IP} 3600 -p 21
          csf -td ${_IP} 3600 -p 22
          csf -td ${_IP} 3600 -p 443
          csf -td ${_IP} 3600 -p 80
        fi
      done
    fi
    if [ -e "${i}/var/xdrago/monitor/log/ftp.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/var/xdrago/monitor/log/ftp.log | cut -d '#' -f1 | sort`; do
        _FW_TEST=
        _FF_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        _FF_TEST=$(grep "=${_IP} " /etc/csf/csf.allow 2>&1)
        if [[ "${_FF_TEST}" =~ "${_IP}" ]] || [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 21"
          if [[ "${_FF_TEST}" =~ "${_IP}" ]]; then
            csf -dr ${_IP}
            csf -tr ${_IP}
          fi
        else
          echo "Deny ${_IP} on ports 21,22,443,80 in the next 1h"
          csf -td ${_IP} 3600 -p 21
          csf -td ${_IP} 3600 -p 22
          csf -td ${_IP} 3600 -p 443
          csf -td ${_IP} 3600 -p 80
        fi
      done
    fi
    echo Completed for $i `date`
  done
  echo fin `date`
  rm -f /run/fire.pid
fi
}

if [ -e "/vservers" ] \
  && [ -e "/etc/csf/csf.deny" ] \
  && [ ! -e "/run/water.pid" ] \
  && [ -x "/usr/sbin/csf" ]; then
  [ ! -e "/run/water.pid" ] && _guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && _guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && _guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && _guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && _guest_guard
  rm -f /run/fire.pid
fi
exit 0
###EOF2024###
