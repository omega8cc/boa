#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/java.incident.log"

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

if [ $(pgrep -f java.sh | grep -v "^$$" | wc -l) -gt 2 ]; then
  echo "Too many java.sh running $(date 2>&1)" >> /var/xdrago/log/too.many.log
  exit 0
fi

incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${pthOml}
  fi
}

jetty_restart() {
  touch /run/boa_wait.pid
  sleep 3
  kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}') &> /dev/null
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
  thisErrLog="$(date 2>&1) Jetty has been restarted"
  echo ${thisErrLog} >> ${pthOml}
  incident_email_report "$1"
  echo >> ${pthOml}
  [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
  exit 0
}

jetty_listen_conflict_detection() {
  if [ -e "/var/log/jetty9" ]; then
    if [ `tail --lines=500 /var/log/jetty9/*stderrout.log \
      | grep --count "Address already in use"` -gt "0" ]; then
      thisErrLog="$(date 2>&1) Address already in use for jetty9"
      echo ${thisErrLog} >> ${pthOml}
      jetty_restart "jetty9 zombie"
    fi
  fi
  if [ -e "/var/log/jetty8" ]; then
    if [ `tail --lines=500 /var/log/jetty8/*stderrout.log \
      | grep --count "Address already in use"` -gt "0" ]; then
      thisErrLog="$(date 2>&1) Address already in use for jetty8"
      echo ${thisErrLog} >> ${pthOml}
      jetty_restart "jetty8 zombie"
    fi
  fi
  if [ -e "/var/log/jetty7" ]; then
    if [ `tail --lines=500 /var/log/jetty7/*stderrout.log \
      | grep --count "Address already in use"` -gt "0" ]; then
      thisErrLog="$(date 2>&1) Address already in use for jetty7"
      echo ${thisErrLog} >> ${pthOml}
      jetty_restart "jetty7 zombie"
    fi
  fi
}

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/locked_java.pl &> /dev/null
  wait
fi

echo DONE!
exit 0
###EOF2024###
