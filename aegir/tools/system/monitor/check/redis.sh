#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/redis.incident.log"

check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
check_root

export _B_NICE=${_B_NICE//[^0-9]/}
: "${_B_NICE:=10}"

export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
: "${_INCIDENT_EMAIL_REPORT:=YES}"

if [ $(pgrep -f redis.sh | grep -v "^$$" | wc -l) -gt 4 ]; then
  echo "Too many redis.sh running $(date 2>&1)" >> /var/xdrago/log/too.many.log
  exit 0
fi

incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${pthOml}
  fi
}

fpm_reload() {
  touch /run/fmp_wait.pid
  sleep 3
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
  sleep 3
  rm -f /run/fmp_wait.pid
  exit 0
}

redis_restart() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date 2>&1) $1 incident detected" >> ${pthOml}
  echo "$(date 2>&1) $1 incident response started" >> ${pthOml}
  service redis-server stop &> /dev/null
  wait
  killall -9 redis-server &> /dev/null
  rm -f /var/lib/redis/*
  service redis-server start &> /dev/null
  wait
  if [[ "${1}" =~ "OOM" ]] || [[ "${1}" =~ "SLOW" ]]; then
    fpm_reload
  fi
  echo "$(date 2>&1) $1 incident redis-server restarted" >> ${pthOml}
  echo "$(date 2>&1) $1 incident response completed" >> ${pthOml}
  echo >> ${pthOml}
  incident_email_report "$1"
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

redis_bind_check_fix() {
  if [ `tail --lines=8 /var/log/redis/redis-server.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    thisErrLog="$(date 2>&1) RedisException BIND detected"
    echo ${thisErrLog} >> ${pthOml}
    redis_restart "Redis BIND"
  fi
}

redis_oom_check_fix() {
  if [ `tail --lines=500 /var/log/php/error_log_* \
    | grep --count "RedisException"` -gt "0" ]; then
    thisErrLog="$(date 2>&1) RedisException OOM detected"
    echo ${thisErrLog} >> ${pthOml}
    redis_restart "Redis OOM"
  fi
}

redis_slow_check_fix() {
  if [ `tail --lines=500 /var/log/php/fpm-*-slow.log \
    | grep --count "PhpRedis.php"` -gt "5" ]; then
    thisErrLog="$(date 2>&1) Slow PhpRedis detected"
    echo ${thisErrLog} >> ${pthOml}
    redis_restart "Redis SLOW"
  fi
}

if_redis_restart() {
  PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  ReTest=$(ls /data/disk/*/static/control/run-redis-restart.pid | wc -l 2>&1)
  if [[ "${PrTestPower}" =~ "POWER" ]] \
    || [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.redis.restart.cnf" ]; then
    if [ "${ReTest}" -ge "1" ]; then
      rm -f /data/disk/*/static/control/run-redis-restart.pid
      thisErrLog="$(date 2>&1) Redis Server Restart Requested"
      echo ${thisErrLog} >> ${pthOml}
      redis_restart "Redis Server Restart Requested"
    fi
  fi
}

[ -d "/data/u" ] && if_redis_restart
redis_slow_check_fix
redis_oom_check_fix
redis_bind_check_fix

echo DONE!
exit 0
###EOF2024###
