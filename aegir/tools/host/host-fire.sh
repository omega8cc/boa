#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

csf_flood_guard() {
  thisCountCsf=`ps aux | grep -v "grep" | grep -v "null" | grep --count "csf"`
  if [ ${thisCountCsf} -gt "3" ]; then
    echo "$(date 2>&1) Too many ${thisCountCsf} csf processes killed" >> \
      /var/log/csf-count.kill.log
    kill -9 $(ps aux | grep '[c]sf' | awk '{print $2}') &> /dev/null
    csf -tf
    csf -df
  fi
  thisCountFire=`ps aux | grep -v "grep" | grep -v "null" | grep --count "fire.sh"`
  if [ ${thisCountFire} -gt "9" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed and rules purged" >> \
      /var/log/fire-purge.kill.log
    csf -tf
    csf -df
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  elif [ ${thisCountFire} -gt "7" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed" >> \
      /var/log/fire-count.kill.log
    csf -tf
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  fi
}
[ ! -e "/var/run/water.pid" ] && csf_flood_guard

guest_proc_monitor() {
  for i in `dir -d /vservers/*`; do
    _THIS_VM=`echo $i | cut -d'/' -f3 | awk '{ print $1}'`
    _VS_NAME=`echo ${_THIS_VM} | cut -d'/' -f3 | awk '{ print $1}'`
    if [ -e "${i}/var/xdrago/proc_num_ctrl.cgi" ] \
      && [ ! -e "${i}/var/run/fmp_wait.pid" ] \
      && [ ! -e "${i}/var/run/boa_wait.pid" ] \
      && [ ! -e "${i}/var/run/boa_run.pid" ] \
      && [ ! -e "${i}/var/run/mysql_restart_running.pid" ] \
      && [ -e "/usr/var/run${i}" ]; then
      vserver ${_VS_NAME} exec perl /var/xdrago/proc_num_ctrl.cgi
    fi
  done
}
###guest_proc_monitor

guest_guard() {
if [ ! -e "/var/run/fire.pid" ] && [ ! -e "/var/run/water.pid" ]; then
  touch /var/run/fire.pid
  echo start `date`
  for i in `dir -d /vservers/*`; do
    if [ -e "${i}/var/xdrago/monitor/ssh.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/var/xdrago/monitor/ssh.log | cut -d '#' -f1 | sort`; do
        _FW_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        if [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 22"
        else
          echo "Deny ${_IP} on ports 21,22,443,80 in the next 1h"
          csf -td ${_IP} 3600 -p 21
          csf -td ${_IP} 3600 -p 22
          csf -td ${_IP} 3600 -p 443
          csf -td ${_IP} 3600 -p 80
        fi
      done
    fi
    if [ -e "${i}/var/xdrago/monitor/web.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/var/xdrago/monitor/web.log | cut -d '#' -f1 | sort`; do
        _FW_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        if [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 80"
        else
          echo "Deny ${_IP} on ports 21,22,443,80 in the next 1h"
          csf -td ${_IP} 3600 -p 21
          csf -td ${_IP} 3600 -p 22
          csf -td ${_IP} 3600 -p 443
          csf -td ${_IP} 3600 -p 80
        fi
      done
    fi
    if [ -e "${i}/var/xdrago/monitor/ftp.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/var/xdrago/monitor/ftp.log | cut -d '#' -f1 | sort`; do
        _FW_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        if [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 21"
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
  rm -f /var/run/fire.pid
fi
}

if [ -e "/vservers" ] \
  && [ -e "/etc/csf/csf.deny" ] \
  && [ ! -e "/var/run/water.pid" ] \
  && [ -e "/usr/sbin/csf" ]; then
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 10
  [ ! -e "/var/run/water.pid" ] && guest_guard
  rm -f /var/run/fire.pid
fi
exit 0
###EOF2021###
