#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_monPath="/var/xdrago/monitor/check"

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

# Run only on fully installed system
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# Sanitize to allow only digits and minus sign
export _B_NICE=${_B_NICE//[^0-9-]/}

# Validate and set default if necessary
if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
  _B_NICE=0
fi

# Clamp the value within -20 to 19
if (( _B_NICE < -20 )); then
  _B_NICE=-20
elif (( _B_NICE > 19 )); then
  _B_NICE=19
fi

renice ${_B_NICE} -p $$ &> /dev/null

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

###
### Fire-and-forget launcher, cron-safe and interactive-safe
###
_spawn_detached() {
  _cmd="$1"
  if command -v nohup >/dev/null 2>&1; then
    nohup bash -c "${_cmd}" >/dev/null 2>&1 &
  elif command -v setsid >/dev/null 2>&1; then
    setsid bash -c "${_cmd}" >/dev/null 2>&1 &
  else
    ( bash -c "${_cmd}" >/dev/null 2>&1 ) &
  fi
  # If interactive shell, drop it from the job table to mimic cron behavior
  if [[ "$-" == *i* ]]; then disown; fi
}

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ]; then

  # Reload nginx if access log is missing or empty
  [ -s /var/log/nginx/access.log ] || service nginx reload

  # Main execution
  if [ -f "${_monPath}/scan_nginx.sh" ]; then
    for _iteration in {1..10}; do
      nohup ${_monPath}/scan_nginx.sh > /dev/null 2>&1 &
      sleep 5
    done
  fi

else

  # Under a load-pause the watchdog stops nginx to shed load, but the flood that
  # tripped the pause is often still arriving, and suppressing the IDS here too
  # left its offenders unbanned -- so on resume the same flood re-saturated the
  # box.  Run ONE bounded scan_nginx pass so the worst aggressors are CSF-banned
  # before nginx restarts.  Single pass, no 10x fan-out and no sleep loop:
  # _block_ip bans via csf/iptables and appends to web.log without reloading
  # nginx, so it cannot lift the pause or add the normal path's load.  minute.sh
  # re-invokes this guard each minute, giving one more ban pass per paused minute.
  if [ -f "${_monPath}/scan_nginx.sh" ]; then
    nohup ${_monPath}/scan_nginx.sh > /dev/null 2>&1 &
  fi
fi

echo "Done!"
exit 0
