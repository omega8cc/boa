#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/xdrago/log/php.incident.log"

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

if (( $(pgrep -fc 'php.sh') > 2 )); then
  echo "Too many php.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    _hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date 2>&1)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_fpm_forced_restart() {
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
  _incident_email_report "PHP $1"
  echo >> ${_pthOml}
  sleep 3
  rm -f /run/fmp_wait.pid
  rm -f /run/restarting_fmp_wait.pid
  exit 0
}

_fpm_duplicate_instances_detection() {
  if [ `ps aux | grep -v "grep" | grep --count "php-fpm: master process"` -gt "10" ]; then
    _thisErrLog="$(date 2>&1) Too many PHP-FPM master processes killed"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "Too many PHP-FPM master"
  fi
}

_fpm_giant_log_detection() {
  _PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>&1)
  if [[ "${_PHPLOG_SIZE_TEST}" =~ "G" ]]; then
    _thisErrLog="$(date 2>&1) Too big PHP error logs deleted: ${_PHPLOG_SIZE_TEST}"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "Too big PHP error logs"
  fi
}

_fpm_listen_conflict_detection() {
  if [ -e "/var/log/php" ]; then
    if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
      | grep --count "already listen on"` -gt "0" ]; then
      _thisErrLog="$(date 2>&1) FPM instances conflict detected, service will be restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _fpm_forced_restart "FPM instances conflict"
    fi
  fi
}

_fpm_proc_max_detection() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "process.max"` -gt "0" ]; then
    _thisErrLog="$(date 2>&1) Too many running FPM childs detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "Too many running FPM childs"
  fi
}

_fpm_sockets_healing() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    _thisErrLog="$(date 2>&1) FPM Sockets conflict detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "FPM Sockets conflict"
  fi
}

_fpm_fastcgi_temp() {
  _FASTCGI_SIZE_TEST=$(du -s -h /usr/fastcgi_temp/*/*/* | grep G 2> /dev/null)
  if [[ "${_FASTCGI_SIZE_TEST}" =~ "G" ]]; then
    rm -f /usr/fastcgi_temp/*/*/*
    killall -9 nginx
    killall -9 php-fpm
    _thisErrLog="$(date 2>&1) PHP fastcgi_temp too big, cleanup forced"
    echo ${_thisErrLog} >> ${_pthOml}
    echo "$(date 2>&1) ${_FASTCGI_SIZE_TEST}" >> ${_pthOml}
    _incident_email_report "PHP fastcgi_temp too big, cleanup forced"
    echo >> ${_pthOml}
  fi
}

if [ ! -e "/var/tmp/fpm" ]; then
  mkdir -p /var/tmp/fpm
  chmod 777 /var/tmp/fpm
fi

_fpm_duplicate_instances_detection
_fpm_giant_log_detection
_fpm_listen_conflict_detection
_fpm_proc_max_detection
_fpm_sockets_healing
_fpm_fastcgi_temp

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/segfault_alert.pl &
fi

echo DONE!
exit 0
###EOF2024###
