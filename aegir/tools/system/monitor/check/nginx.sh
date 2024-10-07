#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/xdrago/log/nginx.incident.log"
_monPath="/var/xdrago/monitor/check"

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

if (( $(pgrep -fc 'nginx.sh') > 2 )); then
  echo "Too many nginx.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    _hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date 2>&1)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_restart_nginx() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date 2>&1) NGX $1 detected" >> ${_pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/`date +%y%m%d-%H%M`-error.log
  echo "Killing all Nginx processes and restarting Nginx..."
  killall -9 nginx
  wait
  service nginx start
  wait
  if pidof nginx > /dev/null; then
    echo "Nginx service restarted successfully."
    _NGINX_RESTARTED=true
    echo "$(date 2>&1) NGX $1 incident Nginx service restarted" >> ${_pthOml}
  else
    echo "Failed to restart Nginx."
    echo "$(date 2>&1) NGX $1 incident Nginx restart failed" >> ${_pthOml}
  fi
  echo "$(date 2>&1) NGX $1 incident response completed" >> ${_pthOml}
  _incident_email_report "NGX $1"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_nginx_oom_detection() {
  if [ -e "/var/log/nginx/error.log" ]; then
    if [ `tail --lines=500 /var/log/nginx/error.log \
      | grep --count "Cannot allocate memory"` -gt "0" ]; then
      _thisErrLog="$(date 2>&1) Nginx OOM"
      echo ${_thisErrLog} >> ${_pthOml}
      _restart_nginx "Nginx OOM"
    fi
  fi
}

_nginx_bind_check_fix() {
  if [ `tail --lines=8 /var/log/nginx/error.log \
    | grep --count "Address already in use"` -gt "0" ]; then
    _thisErrLog="$(date 2>&1) Nginx BIND"
    echo ${_thisErrLog} >> ${_pthOml}
    _restart_nginx "Nginx BIND"
  fi
}

_nginx_heatlh_check_fix() {
  # Initialize a flag to indicate whether Nginx service has been restarted
  _NGINX_RESTARTED=false
  # Check if Nginx is running and capture the process details
  _NGINX_PROCESSES=$(ps aux | grep 'nginx: ' | grep -v 'grep')
  # Check for multiple master processes (shouldn't happen)
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _MASTER_COUNT=$(echo "${_NGINX_PROCESSES}" | grep 'nginx: master process' | wc -l)
    if [ "${_MASTER_COUNT}" -gt 1 ]; then
      echo "Multiple Nginx master processes detected. Possible stuck processes."
      echo "$(date 2>&1) NGX multiple master processes detected" >> ${_pthOml}
      echo "$(date 2>&1) NGX ${_NGINX_PROCESSES}" >> ${_pthOml}
      _restart_nginx "_MASTER_COUNT ${_MASTER_COUNT}"
    fi
  fi
  # Check the state of the master process
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _MASTER_STATE=$(echo "${_NGINX_PROCESSES}" | grep 'nginx: master process' | awk '{print $8}')
    if [ "${_MASTER_STATE}" = "Z" ] \
      || [ "${_MASTER_STATE}" = "T" ] \
      || [ "${_MASTER_STATE}" = "D" ]; then
      echo "Nginx master process is in an abnormal state: ${_MASTER_STATE}."
      echo "$(date 2>&1) NGX master process is in an abnormal state: ${_MASTER_STATE}" >> ${_pthOml}
      echo "$(date 2>&1) NGX ${_NGINX_PROCESSES}" >> ${_pthOml}
      _restart_nginx "_MASTER_STATE ${_MASTER_STATE}"
    fi
  fi
  # Check the state of the worker processes
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _WORKER_STATE=$(echo "${_NGINX_PROCESSES}" | grep 'nginx: worker process' | awk '{print $8}')
    if [[ "${_WORKER_STATE}" =~ "Z" ]] \
      || [[ "${_WORKER_STATE}" =~ "T" ]]; then
      echo "Nginx worker process is in an abnormal state: ${_WORKER_STATE}."
      echo "$(date 2>&1) NGX worker process is in an abnormal state: ${_WORKER_STATE}" >> ${_pthOml}
      echo "$(date 2>&1) NGX ${_NGINX_PROCESSES}" >> ${_pthOml}
      _restart_nginx "_WORKER_STATE ${_WORKER_STATE}"
    fi
  fi
  # Final status message
  if [ "${_NGINX_RESTARTED}" = false ]; then
    echo "Nginx is running normally. No anomalies detected."
  else
    echo "Nginx was restarted due to detected anomalies."
    echo "$(date 2>&1) NGX service was restarted due to detected anomalies" >> ${_pthOml}
  fi
}

_if_nginx_restart() {
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  ReTest=$(ls /data/disk/*/static/control/run-nginx-restart.pid | wc -l 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [ -e "/root/.allow.nginx.restart.cnf" ]; then
    if [ "${ReTest}" -ge "1" ]; then
      rm -f /data/disk/*/static/control/run-nginx-restart.pid
      _thisErrLog="$(date 2>&1) Nginx Server Restart Requested"
      echo ${_thisErrLog} >> ${_pthOml}
      _restart_nginx "Nginx Server Restart Requested"
    fi
  fi
}

_nginx_bind_check_fix
_nginx_oom_detection
_nginx_heatlh_check_fix
[ -d "/data/u" ] && _if_nginx_restart

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl ${_monPath}/locked_nginx.pl &
fi

# Main execution
if [ -f "${_monPath}/scan_nginx.sh" ]; then
  for _iteration in {1..4}; do
    bash ${_monPath}/scan_nginx.sh &
    sleep 12
  done
elif [ -f "${_monPath}/scan_nginx.pl" ]; then
  for _iteration in {1..10}; do
    perl ${_monPath}/scan_nginx.pl &
    sleep 5
  done
fi

echo "Done!"
exit 0
###EOF2024###
