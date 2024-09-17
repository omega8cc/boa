#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/nginx.incident.log"

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

if [ $(pgrep -f nginx.sh | grep -v "^$$" | wc -l) -gt 1 ]; then
  echo "Too many nginx.sh running" >> /var/xdrago/log/too.many.log
  exit 0
fi

incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${pthOml}
  fi
}

restart_nginx() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date 2>&1) NGX $1 detected" >> ${pthOml}
  echo "$(date 2>&1) NGX $1 incident response started" >> ${pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/`date +%y%m%d-%H%M`-error.log
  echo "Killing all Nginx processes and restarting Nginx..."
  killall -9 nginx
  wait
  service nginx start
  wait
  if pidof nginx > /dev/null; then
    echo "Nginx restarted successfully."
    _NGINX_RESTARTED=true
    echo "$(date 2>&1) NGX $1 incident nginx restarted" >> ${pthOml}
  else
    echo "Failed to restart Nginx."
    echo "$(date 2>&1) NGX $1 incident nginx restart failed" >> ${pthOml}
  fi
  echo "$(date 2>&1) NGX $1 incident response completed" >> ${pthOml}
  echo >> ${pthOml}
  incident_email_report "NGX $1"
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

nginx_oom_detection() {
  if [ -e "/var/log/nginx/error.log" ]; then
    if [ `tail --lines=500 /var/log/nginx/error.log \
      | grep --count "Cannot allocate memory"` -gt "0" ]; then
      thisErrLog="$(date 2>&1) Nginx OOM"
      echo ${thisErrLog} >> ${pthOml}
      restart_nginx "Nginx OOM"
    fi
  fi
}

nginx_heatlh_check_fix() {
  # Initialize a flag to indicate whether Nginx has been restarted
  _NGINX_RESTARTED=false
  # Check if Nginx is running and capture the process details
  _NGINX_PROCESSES=$(ps aux | grep 'nginx: ' | grep -v 'grep')
  # Check for multiple master processes (shouldn't happen)
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _MASTER_COUNT=$(echo "${_NGINX_PROCESSES}" | grep 'nginx: master process' | wc -l)
    if [ "${_MASTER_COUNT}" -gt 1 ]; then
      echo "Multiple Nginx master processes detected. Possible stuck processes."
      echo "$(date 2>&1) NGX multiple master processes detected" >> ${pthOml}
      echo "$(date 2>&1) NGX ${_NGINX_PROCESSES}" >> ${pthOml}
      restart_nginx "_MASTER_COUNT ${_MASTER_COUNT}"
    fi
  fi
  # Check the state of the master process
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _MASTER_STATE=$(echo "${_NGINX_PROCESSES}" | grep 'nginx: master process' | awk '{print $8}')
    if [ "${_MASTER_STATE}" = "Z" ] \
      || [ "${_MASTER_STATE}" = "T" ] \
      || [ "${_MASTER_STATE}" = "D" ]; then
      echo "Nginx master process is in an abnormal state: ${_MASTER_STATE}."
      echo "$(date 2>&1) NGX master process is in an abnormal state: ${_MASTER_STATE}" >> ${pthOml}
      echo "$(date 2>&1) NGX ${_NGINX_PROCESSES}" >> ${pthOml}
      restart_nginx "_MASTER_STATE ${_MASTER_STATE}"
    fi
  fi
  # Check the state of the worker processes
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _WORKER_STATE=$(echo "${_NGINX_PROCESSES}" | grep 'nginx: worker process' | awk '{print $8}')
    if [[ "${_WORKER_STATE}" =~ "Z" ]] \
      || [[ "${_WORKER_STATE}" =~ "T" ]]; then
      echo "Nginx worker process is in an abnormal state: ${_WORKER_STATE}."
      echo "$(date 2>&1) NGX worker process is in an abnormal state: ${_WORKER_STATE}" >> ${pthOml}
      echo "$(date 2>&1) NGX ${_NGINX_PROCESSES}" >> ${pthOml}
      restart_nginx "_WORKER_STATE ${_WORKER_STATE}"
    fi
  fi
  # Final status message
  if [ "${_NGINX_RESTARTED}" = false ]; then
    echo "Nginx is running normally. No anomalies detected."
  else
    echo "Nginx was restarted due to detected anomalies."
    echo "$(date 2>&1) NGX was restarted due to detected anomalies" >> ${pthOml}
  fi
}

if_nginx_restart() {
  PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  ReTest=$(ls /data/disk/*/static/control/run-nginx-restart.pid | wc -l 2>&1)
  if [[ "${PrTestPower}" =~ "POWER" ]] \
    || [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.nginx.restart.cnf" ]; then
    if [ "${ReTest}" -ge "1" ]; then
      rm -f /data/disk/*/static/control/run-nginx-restart.pid
      thisErrLog="$(date 2>&1) Nginx Server Restart Requested"
      echo ${thisErrLog} >> ${pthOml}
      restart_nginx "Nginx Server Restart Requested"
    fi
  fi
}

nginx_oom_detection
nginx_heatlh_check_fix
[ -d "/data/u" ] && if_nginx_restart

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/locked_nginx.pl &> /dev/null
  wait
fi

perl /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
wait
sleep 15
perl /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
wait
sleep 15
perl /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
wait
sleep 15
perl /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
wait

echo DONE!
exit 0
###EOF2024###
