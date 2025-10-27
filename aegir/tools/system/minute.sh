#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/oom.incident.log"
_oldOml="/var/log/boa/oom.incident.old.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "$_L" ] && . "$_L" && break
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

[ ! -d "/var/xdrago/monitor/log" ] && mkdir -p /var/xdrago/monitor/log

if [ -e "${_pthOml}" ] && [ ! -e "${_oldOml}" ]; then
  mv -f ${_pthOml} ${_oldOml}
fi

_second_flood_guard() {
  _thisCountSec=$(pgrep -fc /var/xdrago/second.sh)
  if [ "${_thisCountSec}" -gt 4 ]; then
    echo "$(date) Too many ${_thisCountSec} second.sh processes killed" >> \
      /var/log/boa/sec-count.kill.log
    pkill -9 -f second.sh
  fi
}

# Protect from high load due to csf loop/flood
_csf_flood_guard() {
  _thisCountCsf=$(pgrep -fc /csf)
  if [ ! -e "/run/boa_run.pid" ] && [ ${_thisCountCsf} -gt 4 ]; then
    echo "$(date) Too many ${_thisCountCsf} csf processes killed" >> \
      /var/log/boa/csf-count.kill.log
    pkill -9 -f csf
    csf -tf
    wait
    csf -df
    wait
  fi
  _thisCountFire=$(pgrep -fc /var/xdrago/guest-fire.sh)
  if [ ! -e "/run/boa_run.pid" ] && [ ${_thisCountFire} -gt 9 ]; then
    echo "$(date) Too many ${_thisCountFire} fire.sh processes killed and rules purged" >> \
      /var/log/boa/fire-purge.kill.log
    csf -tf
    wait
    csf -df
    wait
    pkill -9 -f fire.sh
  elif [ ! -e "/run/boa_run.pid" ] && [ ${_thisCountFire} -gt 7 ]; then
    echo "$(date) Too many ${_thisCountFire} fire.sh processes killed" >> \
      /var/log/boa/fire-count.kill.log
    csf -tf
    wait
    pkill -9 -f fire.sh
  fi
  [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
}

_launch_auto_healing() {
  nohup /var/xdrago/monitor/check/system.sh > /dev/null 2>&1 &
  nohup /var/xdrago/monitor/check/unbound.sh > /dev/null 2>&1 &
  if [ -e "/etc/init.d/valkey-server" ]; then
    nohup /var/xdrago/monitor/check/valkey.sh > /dev/null 2>&1 &
  elif [ -e "/etc/init.d/redis-server" ]; then
    nohup /var/xdrago/monitor/check/redis.sh > /dev/null 2>&1 &
  fi
  nohup /var/xdrago/monitor/check/mysql.sh > /dev/null 2>&1 &
  nohup /var/xdrago/monitor/check/php.sh > /dev/null 2>&1 &
  nohup /var/xdrago/monitor/check/nginx.sh > /dev/null 2>&1 &
  nohup /var/xdrago/monitor/check/nginx_guard.sh > /dev/null 2>&1 &
  nohup /var/xdrago/monitor/check/java.sh > /dev/null 2>&1 &
}

[ ! -d "/var/log/boa" ] && mkdir -p /var/log/boa
[ -e "/var/log/sec-count.kill.log" ] && mv -f /var/log/sec-count.kill.log /var/log/boa/
[ -e "/var/log/csf-count.kill.log" ] && mv -f /var/log/csf-count.kill.log /var/log/boa/
[ -e "/var/log/fire-purge.kill.log" ] && mv -f /var/log/fire-purge.kill.log /var/log/boa/
[ -e "/var/log/fire-count.kill.log" ] && mv -f /var/log/fire-count.kill.log /var/log/boa/

[ ! -e "/run/boa_run.pid" ] && _second_flood_guard
[ -x "/usr/sbin/csf" ] && [ ! -e "/run/water.pid" ] && _csf_flood_guard

# Main execution
for _iteration in {1..9}; do
  echo "----------------------------"
  echo "Iteration ${_iteration}:"
  _launch_auto_healing
  sleep 5
done

echo DONE!
exit 0

