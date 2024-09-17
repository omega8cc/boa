#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/php.incident.log"

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

if [ $(pgrep -f php.sh | grep -v "^$$" | wc -l) -gt 1 ]; then
  echo "Too many php.sh running"
  exit 0
fi

incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${pthOml}
  fi
}

fpm_forced_restart() {
  touch /run/fmp_wait.pid
  touch /run/restarting_fmp_wait.pid
  sleep 3
  _NOW=$(date +%y%m%d-%H%M%S 2>&1)
  _NOW=${_NOW//[^0-9-]/}
  mkdir -p /var/backups/php-logs/${_NOW}/
  mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm start
    fi
  done
  echo >> ${pthOml}
  incident_email_report "PHP $1"
  sleep 3
  rm -f /run/fmp_wait.pid
  rm -f /run/restarting_fmp_wait.pid
  exit 0
}

fpm_duplicate_instances_detection() {
  if [ `ps aux | grep -v "grep" | grep --count "php-fpm: master process"` -gt "10" ]; then
    thisErrLog="$(date 2>&1) Too many PHP-FPM master processes killed"
    echo ${thisErrLog} >> ${pthOml}
    fpm_forced_restart "Too many PHP-FPM master"
  fi
}

fpm_giant_log_detection() {
  _PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>&1)
  if [[ "${_PHPLOG_SIZE_TEST}" =~ "G" ]]; then
    thisErrLog="$(date 2>&1) Too big PHP error logs deleted: ${_PHPLOG_SIZE_TEST}"
    echo ${thisErrLog} >> ${pthOml}
    fpm_forced_restart "Too big PHP error logs"
  fi
}

fpm_listen_conflict_detection() {
  if [ -e "/var/log/php" ]; then
    if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
      | grep --count "already listen on"` -gt "0" ]; then
      thisErrLog="$(date 2>&1) FPM instances conflict detected"
      echo ${thisErrLog} >> ${pthOml}
      fpm_forced_restart "FPM instances conflict"
    fi
  fi
}

fpm_proc_max_detection() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "process.max"` -gt "0" ]; then
    thisErrLog="$(date 2>&1) Too many running FPM childs detected"
    echo ${thisErrLog} >> ${pthOml}
    fpm_forced_restart "Too many running FPM childs"
  fi
}

fpm_sockets_healing() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    thisErrLog="$(date 2>&1) FPM Sockets conflict detected"
    echo ${thisErrLog} >> ${pthOml}
    fpm_forced_restart "FPM Sockets conflict"
  fi
}

fpm_duplicate_instances_detection
fpm_giant_log_detection
fpm_listen_conflict_detection
fpm_proc_max_detection
fpm_sockets_healing

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/segfault_alert.pl
  wait
fi

echo DONE!
exit 0
###EOF2024###
