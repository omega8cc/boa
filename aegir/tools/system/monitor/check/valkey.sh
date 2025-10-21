#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/valkey.incident.log"
_cd="/run/valkey-monitor.cooldown"

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

[ -d /run/valkey ] || mkdir -p /run/valkey
[ -d /run/valkey ] && chown -R valkey:valkey /run/valkey

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

: "${_VALKEY_COOLDOWN_SECS:=30}"

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

###
### Load + normalize _INCIDENT_REPORT
###
### Legacy values:
###   NO  becomes OFF (see below)
###   YES becomes MINI (see below)
###
### Current values:
###   OFF  == Total silence, no email alerts
###   ALL  == Very noisy, good for debugging
###   MINI == Only the most important alerts (default)
###   CRIT == Only critical if _lvl=ALERT
###
_normalize_incident_report() {
  : "${_INCIDENT_REPORT:=MINI}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  ###
  ### Map legacy + validate
  ###
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_incident_email_report() {
  if ! _check_uptime_grace_period >/dev/null; then return 1; fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_valkey_ping_ok() {
  # Check if Valkey responds to PING (authenticated or NOAUTH)
  _sock="/run/valkey/valkey.sock"
  _cli="/usr/bin/valkey-cli"
  _pass_file="/root/.valkey.pass.txt"
  _out=
  _pass=
  if [ ! -x "${_cli}" ]; then
    return 1
  fi
  if [ -r "${_pass_file}" ]; then
    _pass="$(head -n1 "${_pass_file}" 2>/dev/null | tr -d '\r\n')"
  fi
  if [ -n "${_pass}" ]; then
    _out="$(${_cli} -s "${_sock}" -a "${_pass}" ping 2>&1)"
  else
    _out="$(${_cli} -s "${_sock}" ping 2>&1)"
  fi
  if echo "${_out}" | grep -qi '^PONG$'; then
    return 0
  fi
  if echo "${_out}" | grep -qi 'NOAUTH'; then
    return 0
  fi
  return 1
}

_fpm_reload() {
  : > /run/fmp_wait.pid
  : > /run/restarting_fmp_wait.pid
  sleep 3
  _NOW=$(date +%y%m%d-%H%M%S)
  _NOW=${_NOW//[^0-9-]/}
  mkdir -p /var/backups/php-logs/${_NOW}/
  mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm reload
    fi
  done
  echo "$(date) $1 incident PHP-FPM reloaded" >> ${_pthOml}
  sleep 1
  rm -f /run/fmp_wait.pid /run/restarting_fmp_wait.pid
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
  date +%s > "${_cd}"
  _incident_email_report "$1"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_valkey_bind_check_fix() {
  # Bind/socket/address-in-use issues → verify twice; restart only if socket missing
  _hits=$(tail -n 8 /var/log/valkey/valkey-server.log 2>/dev/null | egrep -ci "Address already in use")
  if [ "${_hits}" -gt 0 ]; then
    sleep 2
    _hits2=$(tail -n 8 /var/log/valkey/valkey-server.log 2>/dev/null | egrep -ci "Address already in use")
    if [ "${_hits2}" -gt 0 ] && [ ! -S "/run/valkey/valkey.sock" ]; then
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(tr -d '\n' < "${_cd}")
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_VALKEY_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: Valkey bind/socket conflict but in cooldown; skipping restart" >> ${_pthOml}
          return 0
        fi
      fi
      echo "$(date) Valkey bind/socket conflict; restarting" >> ${_pthOml}
      _valkey_restart "ValkeyException BIND PORT"
    fi
  fi
}

_valkey_connection_check_fix() {
  # Sustained connection/backlog issues → verify twice; cooldown then restart
  _hits=$(tail -n 500 /var/log/php/error_log_* 2>/dev/null | egrep -ci "RedisException: Connection refused")
  if [ "${_hits}" -gt 19 ]; then
    sleep 2
    _hits2=$(tail -n 500 /var/log/php/error_log_* 2>/dev/null | egrep -ci "RedisException: Connection refused")
    if [ "${_hits2}" -gt 19 ]; then
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(tr -d '\n' < "${_cd}")
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_VALKEY_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: Valkey connection issues but in cooldown; skipping restart" >> ${_pthOml}
          return 0
        fi
      fi
      echo "$(date) Valkey sustained connection issues (${_hits2} hits) — restart" >> ${_pthOml}
      _valkey_restart "ValkeyException REFUSED"
    fi
  fi
}

_valkey_slow_check_fix() {
  # Sustained latency/slowlog/accept issues → verify twice; cooldown then restart
  _hits=$(tail -n 500 /var/log/php/fpm-*-slow.log 2>/dev/null | egrep -ci "PhpRedis.php")
  if [ "${_hits}" -gt 19 ]; then
    sleep 2
    _hits2=$(tail -n 500 /var/log/php/fpm-*-slow.log 2>/dev/null | egrep -ci "PhpRedis.php")
    if [ "${_hits2}" -gt 19 ]; then
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(tr -d '\n' < "${_cd}")
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_VALKEY_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: Valkey latency symptoms but in cooldown; skipping restart" >> ${_pthOml}
          return 0
        fi
      fi
      echo "$(date) Valkey sustained latency symptoms (${_hits2} hits) — restart" >> ${_pthOml}
      _valkey_restart "ValkeyException SLOW"
    fi
  fi
}

_if_valkey_restart() {
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  _VkTest=$(ls /data/disk/*/static/control/run-valkey-restart.pid | wc -l 2>&1)
  _ReTest=$(ls /data/disk/*/static/control/run-redis-restart.pid | wc -l 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.valkey.restart.cnf" ] \
    || [ -e "/root/.allow.redis.restart.cnf" ]; then
    if [ "${_VkTest}" -ge 1 ] || [ "${_ReTest}" -ge 1 ]; then
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(tr -d '\n' < "${_cd}")
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_VALKEY_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: Valkey restart requested but in cooldown; skipped" >> ${_pthOml}
          return 0
        fi
      fi
      rm -f /data/disk/*/static/control/run-valkey-restart.pid
      rm -f /data/disk/*/static/control/run-redis-restart.pid
      _thisErrLog="$(date) Valkey Server Restart Requested"
      echo ${_thisErrLog} >> ${_pthOml}
      _valkey_restart "Valkey Server Restart Requested"
    fi
  fi
}

_valkey_health_check_fix() {

  # Double-check health: process + socket PING
  _ok_proc=false
  _ok_ping=false

  pgrep -f "/usr/bin/valkey-server" >/dev/null 2>&1 && _ok_proc=true
  if [ -x "/usr/bin/valkey-cli" ]; then
    if _valkey_ping_ok; then
      _ok_ping=true
    fi
  fi

  if ! ${_ok_proc} || ! ${_ok_ping}; then
    sleep 2
    _ok_proc=false; _ok_ping=false
    pgrep -f "/usr/bin/valkey-server" >/dev/null 2>&1 && _ok_proc=true
    if [ -x "/usr/bin/valkey-cli" ]; then
      if _valkey_ping_ok; then
        _ok_ping=true
      fi
    fi
  fi

  if ! ${_ok_proc} || ! ${_ok_ping}; then
    _now=$(date +%s)
    if [ -s "${_cd}" ]; then
      _ts=$(tr -d '\n' < "${_cd}")
      if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_VALKEY_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: Valkey unhealthy but in cooldown; skipping restart" >> ${_pthOml}
        return 0
      fi
    fi

    echo "$(date) Valkey health failed (proc=${_ok_proc} ping=${_ok_ping}) — restart" >> ${_pthOml}
    service valkey-server restart
    wait
    sleep 3

    # Post-restart verification
    _ok_proc=false; _ok_ping=false
    pgrep -f "/usr/bin/valkey-server" >/dev/null 2>&1 && _ok_proc=true
    if [ -x "/usr/bin/valkey-cli" ]; then
      if _valkey_ping_ok; then
        _ok_ping=true
      fi
    fi

    date +%s > "${_cd}"

    if ${_ok_proc} && ${_ok_ping}; then
      echo "$(date) Valkey was down, restarted" >> ${_pthOml}
      _incident_email_report "Valkey was down, restarted"
      echo >> ${_pthOml}
      exit 0
    else
      echo "$(date) Valkey still unhealthy after restart; forced stop/start" >> ${_pthOml}
      _valkey_restart "Valkey required stop/start after failed restart"
    fi
  fi
}

if [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ]; then
  if [ -x "/etc/init.d/valkey-server" ] \
    && [ -x "/usr/bin/valkey-server" ]; then
    _valkey_health_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && _valkey_slow_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && _valkey_connection_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && _valkey_bind_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && [ -d "/data/u" ] && _if_valkey_restart
  fi
fi

echo DONE!
exit 0
