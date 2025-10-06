#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/php.incident.log"

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
  if ! _check_uptime_grace_period >/dev/null; then return 1; fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_fpm_forced_restart() {
  : > /run/fmp_wait.pid
  : > /run/restarting_fmp_wait.pid
  sleep 3
  _NOW=$(date +%y%m%d-%H%M%S)
  _NOW=${_NOW//[^0-9-]/}
  mkdir -p /var/backups/php-logs/${_NOW}/
  mv -f /var/log/php/* /var/backups/php-logs/${_NOW}/
  pkill -9 -f php-fpm
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm start
    fi
  done
  _incident_email_report "PHP $1"
  echo >> ${_pthOml}
  sleep 3
  rm -f /run/fmp_wait.pid /run/restarting_fmp_wait.pid
  exit 0
}

_fpm_duplicate_instances_detection() {
  _CNT=$(pgrep -fc "php-fpm: master process")
  if (( _CNT > 11 )); then
    _thisErrLog="$(date) Too many PHP-FPM master processes killed (count=${_CNT})"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "Too many PHP-FPM master (count=${_CNT})"
  fi
}

_fpm_giant_log_detection() {
  _PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>/dev/null)
  if [[ "${_PHPLOG_SIZE_TEST}" =~ "G" ]]; then
    _thisErrLog="$(date) Too big PHP error logs deleted: ${_PHPLOG_SIZE_TEST}"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "Too big PHP error logs"
  fi
}

_fpm_listen_conflict_detection() {
  if [ -e "/var/log/php" ]; then
    if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
      | grep --count "already listen on"` -gt 0 ]; then
      _thisErrLog="$(date) FPM instances conflict detected, service will be restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _fpm_forced_restart "FPM instances conflict"
    fi
  fi
}

_fpm_proc_max_detection() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "process.max"` -gt 0 ]; then
    _thisErrLog="$(date) Too many running FPM childs detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "Too many running FPM childs"
  fi
}

_fpm_sockets_healing() {
  if [ `tail --lines=500 /var/log/php/php*-fpm-error.log \
    | grep --count "Address already in use"` -gt 0 ]; then
    _thisErrLog="$(date) FPM Sockets conflict detected, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _fpm_forced_restart "FPM Sockets conflict"
  fi
}

_fpm_fastcgi_temp() {
  _FASTCGI_SIZE_TEST=$(du -s -h /usr/fastcgi_temp/*/*/* | grep G 2>/dev/null)
  if [[ "${_FASTCGI_SIZE_TEST}" =~ "G" ]]; then
    rm -f /usr/fastcgi_temp/*/*/*
    killall -9 nginx
    killall -9 php-fpm
    _thisErrLog="$(date) PHP fastcgi_temp too big, cleanup forced"
    echo ${_thisErrLog} >> ${_pthOml}
    echo "$(date) ${_FASTCGI_SIZE_TEST}" >> ${_pthOml}
    _incident_email_report "PHP fastcgi_temp too big, cleanup forced"
    echo >> ${_pthOml}
  fi
}

_fpm_health_check_fix() {
  _thisErrLog=
  _PHP_V="84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -x "/opt/php${e}/bin/php" ]; then
      _pat="php-fpm: master process.*/opt/php${e}/etc/php${e}-fpm.conf"
      _TestPhp="$(pgrep -f "${_pat}")"
      echo "Pgrep is ${_TestPhp}"
      echo "Socket is $(ls -la "/run/www${e}.fpm.socket" 2>/dev/null || echo 'missing')"
      echo "PID is $(cat "/run/php${e}-fpm.pid" 2>/dev/null || echo 'missing')"
      if ! pgrep -f "${_pat}" \
        || [ ! -S "/run/www${e}.fpm.socket" ] \
        || [ ! -s "/run/php${e}-fpm.pid" ]; then
        : > /run/fmp_wait.pid
        : > /run/restarting_fmp_wait.pid
        sleep 1
        service "php${e}-fpm" restart
        wait
        _thisErrLog="$(date) PHP-FPM ${e} was down, restarted"
        echo ${_thisErrLog} >> ${_pthOml}
        sleep 1
        rm -f /run/fmp_wait.pid /run/restarting_fmp_wait.pid
      fi
    fi
  done
  if [ -n "${_thisErrLog}" ]; then
    _incident_email_report "PHP-FPM was down, restarted"
    echo >> ${_pthOml}
  fi
}

if [ ! -e "/var/tmp/fpm" ]; then
  mkdir -p /var/tmp/fpm
  chmod 777 /var/tmp/fpm
fi

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ]; then
  _fpm_duplicate_instances_detection
  _fpm_listen_conflict_detection
  _fpm_proc_max_detection
  _fpm_sockets_healing
  _fpm_fastcgi_temp
  _fpm_giant_log_detection
  _fpm_health_check_fix
  if [ ! -e "/root/.high_traffic.cnf" ] \
    && [ ! -e "/root/.giant_traffic.cnf" ]; then
    perl /var/xdrago/monitor/check/segfault_alert.pl &
  fi
fi

echo DONE!
exit 0

