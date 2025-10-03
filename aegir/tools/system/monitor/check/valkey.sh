#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/valkey.incident.log"

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

# Sanitize to allow only digits and minus sign
export _B_NICE=${_B_NICE//[^0-9-]/}

# Validate and set default if necessary
if ! [[ "$_B_NICE" =~ ^-?[0-9]+$ ]]; then
  _B_NICE=0
fi

# Clamp the value within -20 to 19
if (( _B_NICE < -20 )); then
  _B_NICE=-20
elif (( _B_NICE > 19 )); then
  _B_NICE=19
fi

renice ${_B_NICE} -p $$ &> /dev/null

export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
: "${_INCIDENT_REPORT:=YES}"

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

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_fpm_reload() {
  _NOW=$(date +%y%m%d-%H%M%S)
  _NOW=${_NOW//[^0-9-]/}
  mkdir -p /var/backups/php-logs/${_NOW}/
  mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm reload
      wait
    fi
  done
  echo "$(date) $1 incident PHP-FPM reloaded" >> ${_pthOml}
}

_valkey_restart() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date) $1 incident detected" >> ${_pthOml}
  service valkey-server stop &> /dev/null
  wait
  killall -9 valkey-server &> /dev/null
  rm -f /var/lib/valkey/*
  service valkey-server start &> /dev/null
  wait
  echo "$(date) $1 incident valkey-server restarted" >> ${_pthOml}
  if [[ "${1}" =~ "REFUSED" ]] || [[ "${1}" =~ "SLOW" ]]; then
    _fpm_reload "$1"
  fi
  echo "$(date) $1 incident response completed" >> ${_pthOml}
  _incident_email_report "$1"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_valkey_bind_check_fix() {
  if [ `tail --lines=8 /var/log/valkey/valkey-server.log \
    | grep --count "Address already in use"` -gt 0 ]; then
    _thisErrLog="$(date) ValkeyException BIND detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _valkey_restart "ValkeyException BIND"
  fi
}

_valkey_connection_check_fix() {
  if [ `tail --lines=500 /var/log/php/error_log_* \
    | grep --count "ValkeyException: Connection refused"` -gt 19 ]; then
    _thisErrLog="$(date) ValkeyException Connection refused detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _valkey_restart "ValkeyException REFUSED"
  fi
}

_valkey_slow_check_fix() {
  if [ `tail --lines=500 /var/log/php/fpm-*-slow.log \
    | grep --count "PhpValkey.php"` -gt 19 ]; then
    _thisErrLog="$(date) Slow PhpValkey detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _valkey_restart "ValkeyException SLOW"
  fi
}

_if_valkey_restart() {
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  VkTest=$(ls /data/disk/*/static/control/run-valkey-restart.pid | wc -l 2>&1)
  ReTest=$(ls /data/disk/*/static/control/run-redis-restart.pid | wc -l 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.valkey.restart.cnf" ] \
    || [ -e "/root/.allow.redis.restart.cnf" ]; then
    if [ "${VkTest}" -ge 1 ] || [ "${ReTest}" -ge 1 ]; then
      rm -f /data/disk/*/static/control/run-valkey-restart.pid
      rm -f /data/disk/*/static/control/run-redis-restart.pid
      _thisErrLog="$(date) Valkey Server Restart Requested"
      echo ${_thisErrLog} >> ${_pthOml}
      _valkey_restart "Valkey Server Restart Requested"
    fi
  fi
}

_valkey_health_check_fix() {
  if ! pgrep -f -q /usr/bin/valkey-server \
    || [ ! -e "/run/valkey/valkey.sock" ] \
    || [ ! -e "/run/valkey/valkey.pid" ]; then
    mkdir -p /run/valkey
    chown -R valkey:valkey /run/valkey
    _thisErrLog="$(date) Valkey Server was down, restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _valkey_restart "Valkey Server was down, restarted"
  fi
}

if [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ]; then
  if [ -x "/etc/init.d/valkey-server" ]; then
    [ "${_ALLOW_CTRL}" = "YES" ] && _valkey_slow_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && _valkey_connection_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && _valkey_bind_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && [ -d "/data/u" ] && _if_valkey_restart
    _valkey_health_check_fix
  fi
fi

echo DONE!
exit 0
