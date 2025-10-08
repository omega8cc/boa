#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/java.incident.log"

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
[ ! -x "/usr/sbin/csf" ] && exit 0

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
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "ALL" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_jetty_restart() {
  touch /run/boa_wait.pid
  sleep 3
  pkill -9 -f jetty
  rm -f /var/log/jetty{7,8,9}/*
  renice ${_B_NICE} -p $$ &> /dev/null
  if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
    service jetty9 start
    wait
  fi
  if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
    service jetty8 start
    wait
  fi
  if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
    service jetty7 start
    wait
  fi
  _thisErrLog="$(date) Jetty service has been restarted"
  echo ${_thisErrLog} >> ${_pthOml}
  _incident_email_report "$1"
  echo >> ${_pthOml}
  [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
  exit 0
}

_jetty_listen_conflict_detection() {
  if [ -e "/var/log/jetty9" ]; then
    if [ `tail --lines=500 /var/log/jetty9/*stderrout.log \
      | grep --count "Address already in use"` -gt 0 ]; then
      _thisErrLog="$(date) BIND PORT error jetty9, service will be restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _jetty_restart "jetty9 zombie"
    fi
  fi
  if [ -e "/var/log/jetty8" ]; then
    if [ `tail --lines=500 /var/log/jetty8/*stderrout.log \
      | grep --count "Address already in use"` -gt 0 ]; then
      _thisErrLog="$(date) BIND PORT error jetty8, service will be restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _jetty_restart "jetty8 zombie"
    fi
  fi
  if [ -e "/var/log/jetty7" ]; then
    if [ `tail --lines=500 /var/log/jetty7/*stderrout.log \
      | grep --count "Address already in use"` -gt 0 ]; then
      _thisErrLog="$(date) BIND PORT error jetty7, service will be restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _jetty_restart "jetty7 zombie"
    fi
  fi
}

_jenkins_health_check_fix() {
  if ! pgrep -f java/jenkins \
    || [ ! -e "/run/jenkins/jenkins.pid" ]; then
    killall -9 java
    sleep 3
    service jenkins restart
    wait
    _thisErrLog="$(date) Jenkins Server was down, started"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "Jenkins Server was down, started"
    echo >> ${_pthOml}
  fi
}

_solr_health_check_fix() {
  if [ -x "/etc/init.d/solr9" ]; then
    _pidfile="/var/solr9/solr-9099.pid"
    if ! pgrep -f /var/solr9 || [ ! -e "${_pidfile}" ]; then
      service solr9 restart
      wait
      _thisErrLog="$(date) Solr9 Server was down, started"
      echo "${_thisErrLog}" >> ${_pthOml}
      _incident_email_report "Solr9 Server was down, started"
      echo >> ${_pthOml}
    else
      _pid="$(cat "${_pidfile}" 2>/dev/null | sed 's/[^0-9]//g')"
      if [ -n "${_pid}" ] && ! ps -p "${_pid}" >/dev/null 2>&1; then
        service solr9 restart
        wait
        _thisErrLog="$(date) Solr9 stale PID detected, restarted"
        echo "${_thisErrLog}" >> ${_pthOml}
        _incident_email_report "Solr9 stale PID detected, restarted"
        echo >> ${_pthOml}
      fi
    fi
  fi
  if [ -x "/etc/init.d/solr7" ]; then
    _pidfile="/var/solr7/solr-9077.pid"
    if ! pgrep -f /var/solr7 || [ ! -e "${_pidfile}" ]; then
      service solr7 restart
      wait
      _thisErrLog="$(date) Solr7 Server was down, started"
      echo "${_thisErrLog}" >> ${_pthOml}
      _incident_email_report "Solr7 Server was down, started"
      echo >> ${_pthOml}
    else
      _pid="$(cat "${_pidfile}" 2>/dev/null | sed 's/[^0-9]//g')"
      if [ -n "${_pid}" ] && ! ps -p "${_pid}" >/dev/null 2>&1; then
        service solr7 restart
        wait
        _thisErrLog="$(date) Solr7 stale PID detected, restarted"
        echo "${_thisErrLog}" >> ${_pthOml}
        _incident_email_report "Solr7 stale PID detected, restarted"
        echo >> ${_pthOml}
      fi
    fi
  fi
  if [ -x "/etc/init.d/jetty9" ]; then
    _pidfile="/run/jetty9.pid"
    if ! pgrep -f /opt/jetty9 || [ ! -e "${_pidfile}" ]; then
      service jetty9 restart
      wait
      _thisErrLog="$(date) Solr4 Server was down, started"
      echo "${_thisErrLog}" >> ${_pthOml}
      _incident_email_report "Solr4 Server was down, started"
      echo >> ${_pthOml}
    else
      _pid="$(cat "${_pidfile}" 2>/dev/null | sed 's/[^0-9]//g')"
      if [ -n "${_pid}" ] && ! ps -p "${_pid}" >/dev/null 2>&1; then
        service jetty9 restart
        wait
        _thisErrLog="$(date) Solr4 stale PID detected, restarted"
        echo "${_thisErrLog}" >> ${_pthOml}
        _incident_email_report "Solr4 stale PID detected, restarted"
        echo >> ${_pthOml}
      fi
    fi
  fi
}

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ]; then
  [ ! -e "/run/boa_run.pid" ] && [ -x "/etc/init.d/jenkins" ] && _jenkins_health_check_fix
  [ ! -e "/run/boa_run.pid" ] && _solr_health_check_fix
  [ ! -e "/run/boa_run.pid" ] && _jetty_listen_conflict_detection
  if [ ! -e "/root/.high_traffic.cnf" ] \
    && [ ! -e "/root/.giant_traffic.cnf" ]; then
    perl /var/xdrago/monitor/check/locked_java.pl &
  fi
fi

echo DONE!
exit 0
