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
  fi
  thisCountFire=`ps aux | grep -v "grep" | grep -v "null" | grep --count "fire.sh"`
  if [ ${thisCountFire} -gt "8" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed and rules purged" >> \
      /var/log/fire-purge.kill.log
    csf -tf
    csf -df
    kill -9 $(ps aux | grep '[f]ire.sh' | awk '{print $2}') &> /dev/null
  elif [ ${thisCountFire} -gt "6" ]; then
    echo "$(date 2>&1) Too many ${thisCountFire} fire.sh processes killed" >> \
      /var/log/fire-count.kill.log
    csf -tf
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
  if [ -e "/var/xdrago/monitor/web.log" ]; then
    for _IP in `cat /var/xdrago/monitor/web.log | cut -d '#' -f1 | sort`; do
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
  if [ -e "/var/xdrago/monitor/ftp.log" ]; then
    for _IP in `cat /var/xdrago/monitor/ftp.log | cut -d '#' -f1 | sort`; do
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
  rm -f /var/run/fire.pid
fi
}

if [ -e "/etc/csf/csf.deny" ] \
  && [ ! -e "/var/run/water.pid" ] \
  && [ -e "/usr/sbin/csf" ]; then
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  sleep 5
  [ ! -e "/var/run/water.pid" ] && guest_guard
  rm -f /var/run/fire.pid
fi
exit 0
###EOF2021###
