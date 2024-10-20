#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/xdrago/log/redis.incident.log"

_check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

export _B_NICE=${_B_NICE//[^0-9]/}
: "${_B_NICE:=10}"

export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
: "${_INCIDENT_EMAIL_REPORT:=YES}"

if (( $(pgrep -fc 'redis.sh') > 2 )); then
  echo "Too many redis.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    _hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date 2>&1)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_fpm_reload() {
  _NOW=$(date +%y%m%d-%H%M%S 2>&1)
  _NOW=${_NOW//[^0-9-]/}
  mkdir -p /var/backups/php-logs/${_NOW}/
  mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm reload
    fi
  done
  echo "$(date 2>&1) $1 incident PHP-FPM reloaded" >> ${_pthOml}
}

_redis_restart() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date 2>&1) $1 incident detected" >> ${_pthOml}
  service redis-server stop &> /dev/null
  wait
  killall -9 redis-server &> /dev/null
  rm -f /var/lib/redis/*
  service redis-server start &> /dev/null
  wait
  echo "$(date 2>&1) $1 incident redis-server restarted" >> ${_pthOml}
  if [[ "${1}" =~ "REFUSED" ]] || [[ "${1}" =~ "SLOW" ]]; then
    _fpm_reload "$1"
  fi
  echo "$(date 2>&1) $1 incident response completed" >> ${_pthOml}
  _incident_email_report "$1"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_redis_bind_check_fix() {
  if [ `tail --lines=8 /var/log/redis/redis-server.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    _thisErrLog="$(date 2>&1) RedisException BIND detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _redis_restart "Redis BIND"
  fi
}

_redis_connection_check_fix() {
  if [ `tail --lines=500 /var/log/php/error_log_* \
    | grep --count "RedisException: Connection refused"` -gt "19" ]; then
    _thisErrLog="$(date 2>&1) RedisException Connection refused detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _redis_restart "Redis REFUSED"
  fi
}

_redis_slow_check_fix() {
  if [ `tail --lines=500 /var/log/php/fpm-*-slow.log \
    | grep --count "PhpRedis.php"` -gt "19" ]; then
    _thisErrLog="$(date 2>&1) Slow PhpRedis detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _redis_restart "Redis SLOW"
  fi
}

_if_redis_restart() {
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  ReTest=$(ls /data/disk/*/static/control/run-redis-restart.pid | wc -l 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.redis.restart.cnf" ]; then
    if [ "${ReTest}" -ge "1" ]; then
      rm -f /data/disk/*/static/control/run-redis-restart.pid
      _thisErrLog="$(date 2>&1) Redis Server Restart Requested"
      echo ${_thisErrLog} >> ${_pthOml}
      _redis_restart "Redis Server Restart Requested"
    fi
  fi
}

if [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

[ "${_ALLOW_CTRL}" = "YES" ] && _redis_slow_check_fix
[ "${_ALLOW_CTRL}" = "YES" ] && _redis_connection_check_fix
[ "${_ALLOW_CTRL}" = "YES" ] && _redis_bind_check_fix
[ "${_ALLOW_CTRL}" = "YES" ] && [ -d "/data/u" ] && _if_redis_restart

echo DONE!
exit 0
###EOF2024###
