#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

second_flood_guard() {
  thisCountSec=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/second.sh"`
  if [ ${thisCountSec} -gt "4" ]; then
    echo "$(date 2>&1) Too many ${thisCountSec} second.sh processes killed" >> \
      /var/log/sec-count.kill.log
    kill -9 $(ps aux | grep '[s]econd.sh' | awk '{print $2}') &> /dev/null
  fi
}
[ ! -e "/var/run/boa_run.pid" ] && second_flood_guard

csf_flood_guard() {
  thisCountCsf=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/csf"`
  if [ ! -e "/var/run/boa_run.pid" ] && [ ${thisCountCsf} -gt "4" ]; then
    echo "$(date 2>&1) Too many ${thisCountCsf} csf processes killed" >> \
      /var/log/csf-count.kill.log
    kill -9 $(ps aux | grep '[c]sf' | awk '{print $2}') &> /dev/null
    csf -tf
    wait
    csf -df
    wait
  fi
  thisCountFire=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/fire.sh"`
  if [ ! -e "/var/run/boa_run.pid" ] && [ ${thisCountFire} -gt "9" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed and rules purged" >> \
      /var/log/fire-purge.kill.log
    csf -tf
    wait
    csf -df
    wait
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  elif [ ! -e "/var/run/boa_run.pid" ] && [ ${thisCountFire} -gt "7" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed" >> \
      /var/log/fire-count.kill.log
    csf -tf
    wait
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  fi
}
[ ! -e "/var/run/water.pid" ] && csf_flood_guard

guest_guard() {
if [ ! -e "/var/run/fire.pid" ] && [ ! -e "/var/run/water.pid" ]; then
  touch /var/run/fire.pid
  if [ -e "/var/xdrago/monitor/ssh.log" ]; then
    for _IP in `cat /var/xdrago/monitor/ssh.log | cut -d '#' -f1 | sort`; do
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
  if [ -e "/var/xdrago/monitor/web.log" ]; then
    for _IP in `cat /var/xdrago/monitor/web.log | cut -d '#' -f1 | sort`; do
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
  if [ -e "/var/xdrago/monitor/ftp.log" ]; then
    for _IP in `cat /var/xdrago/monitor/ftp.log | cut -d '#' -f1 | sort`; do
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
  rm -f /var/run/fire.pid
fi
}

if [ -e "/etc/csf/csf.deny" ] \
  && [ ! -e "/var/run/water.pid" ] \
  && [ -x "/usr/sbin/csf" ]; then
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
###EOF2024###
