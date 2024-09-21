#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

csf_flood_guard() {
  thisCountCsf=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/csf"`
  if [ ${thisCountCsf} -gt "4" ]; then
    echo "$(date 2>&1) Too many ${thisCountCsf} csf processes killed" >> \
      /var/log/csf-count.kill.log
    kill -9 $(ps aux | grep '[c]sf' | awk '{print $2}') &> /dev/null
    csf -tf
    wait
    csf -df
    wait
  fi
  thisCountFire=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/fire.sh"`
  if [ ${thisCountFire} -gt "9" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed and rules purged" >> \
      /var/log/fire-purge.kill.log
    csf -tf
    wait
    csf -df
    wait
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  elif [ ${thisCountFire} -gt "7" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed" >> \
      /var/log/fire-count.kill.log
    csf -tf
    wait
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  fi
}
[ ! -e "/run/water.pid" ] && csf_flood_guard

guest_proc_monitor() {
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
###guest_proc_monitor

guest_guard() {
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
  [ ! -e "/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/run/water.pid" ] && guest_guard
  rm -f /run/fire.pid
fi
exit 0
###EOF2024###
