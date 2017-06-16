#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

guest_guard() {
if [ ! -e "/var/run/fire.pid" ] && [ ! -e "/var/run/water.pid" ]; then
  touch /var/run/fire.pid
  echo start `date`
  for i in `dir -d /vservers/*`; do
    if [ -e "$i/var/xdrago/monitor/ssh.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat $i/var/xdrago/monitor/ssh.log | cut -d '#' -f1 | sort`; do
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
    if [ -e "$i/var/xdrago/monitor/web.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat $i/var/xdrago/monitor/web.log | cut -d '#' -f1 | sort`; do
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
    if [ -e "$i/var/xdrago/monitor/ftp.log" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat $i/var/xdrago/monitor/ftp.log | cut -d '#' -f1 | sort`; do
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
###EOF2017###
