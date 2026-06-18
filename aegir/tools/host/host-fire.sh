#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

_guest_proc_monitor() {
  for i in `dir -d /vservers/*`; do
    _THIS_VM=`echo $i | cut -d'/' -f3 | awk '{ print $1}'`
    _VS_NAME=`echo ${_THIS_VM} | cut -d'/' -f3 | awk '{ print $1}'`
    if [ -e "${i}/var/xdrago/monitor/check/bind9.sh" ] \
      && [ ! -e "${i}/run/fmp_wait.pid" ] \
      && [ ! -e "${i}/run/boa_wait.pid" ] \
      && [ ! -e "${i}/run/boa_run.pid" ] \
      && [ ! -e "${i}/run/mysql_restart_running.pid" ] \
      && [ -e "/usr/run${i}" ]; then
      for _w in sendmail_guard convert_guard hostname_sync syslog_legacy \
                bind9 proxysql droplet newrelic_daemon newrelic_sysmond \
                collectd xinetd lsyncd; do
        vserver ${_VS_NAME} exec bash /var/xdrago/monitor/check/${_w}.sh &
      done
    fi
  done
}
###_guest_proc_monitor

_guest_guard() {
if [ ! -e "/run/fire.pid" ] && [ ! -e "/run/water.pid" ]; then
  touch /run/fire.pid
  echo start $(date)
  for i in `dir -d /vservers/*`; do
    if [ -e "${i}/var/xdrago/monitor/log/ssh.log" ] && [ -e "/usr/run${i}" ]; then
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
        [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
      done
    fi
    if [ -e "${i}/var/xdrago/monitor/log/web.log" ] && [ -e "/usr/run${i}" ]; then
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
        [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
      done
    fi
    if [ -e "${i}/var/xdrago/monitor/log/ftp.log" ] && [ -e "/usr/run${i}" ]; then
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
        [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
      done
    fi
    echo Completed for $i $(date)
  done
  echo fin $(date)
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

