#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/nginx.incident.log"
_monPath="/var/xdrago/monitor/check"

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
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_restart_nginx() {
  touch /run/boa_run.pid
  sleep 3
  echo "$(date) NGX $1 detected" >> ${_pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/$(date +%y%m%d-%H%M)-error.log
  echo "Killing all Nginx processes and restarting Nginx..."
  killall -9 nginx
  wait
  service nginx start
  wait
  if pidof nginx > /dev/null; then
    echo "Nginx service restarted successfully."
    _NGINX_RESTARTED=true
    echo "$(date) NGX $1 incident Nginx service restarted" >> ${_pthOml}
  else
    echo "Failed to restart Nginx."
    echo "$(date) NGX $1 incident Nginx restart failed" >> ${_pthOml}
  fi
  echo "$(date) NGX $1 incident response completed" >> ${_pthOml}
  _incident_email_report "NGX $1"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_nginx_oom_detection() {
  if [ -e "/var/log/nginx/error.log" ]; then
    if [ `tail --lines=500 /var/log/nginx/error.log \
      | grep --count "Cannot allocate memory"` -gt 0 ]; then
      _thisErrLog="$(date) Nginx OOM"
      echo ${_thisErrLog} >> ${_pthOml}
      _restart_nginx "Nginx OOM"
    fi
  fi
}

_nginx_bind_check_fix() {
  if [ `tail --lines=8 /var/log/nginx/error.log \
    | grep --count "Address already in use"` -gt 0 ]; then
    _thisErrLog="$(date) Nginx BIND"
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
    _MASTER_COUNT=$(pgrep -fc 'nginx: master process')
    if [ "${_MASTER_COUNT}" -gt 1 ]; then
      echo "Multiple (${_MASTER_COUNT}) Nginx master processes detected. Possible stuck processes."
      echo "$(date) NGX multiple (${_MASTER_COUNT}) master processes detected" >> ${_pthOml}
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
      echo "$(date) NGX master process is in an abnormal state: ${_MASTER_STATE}" >> ${_pthOml}
      echo "$(date) NGX ${_NGINX_PROCESSES}" >> ${_pthOml}
      _restart_nginx "_MASTER_STATE ${_MASTER_STATE}"
    fi
  fi
  # Check the state of the worker processes
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _WORKER_STATE=$(echo "${_NGINX_PROCESSES}" | grep 'nginx: worker process' | awk '{print $8}')
    if [[ "${_WORKER_STATE}" =~ "Z" ]] \
      || [[ "${_WORKER_STATE}" =~ "T" ]]; then
      echo "Nginx worker process is in an abnormal state: ${_WORKER_STATE}."
      echo "$(date) NGX worker process is in an abnormal state: ${_WORKER_STATE}" >> ${_pthOml}
      echo "$(date) NGX ${_NGINX_PROCESSES}" >> ${_pthOml}
      _restart_nginx "_WORKER_STATE ${_WORKER_STATE}"
    fi
  fi
  # Final status message
  if [ "${_NGINX_RESTARTED}" = false ]; then
    echo "Nginx is running normally. No anomalies detected."
  else
    echo "Nginx was restarted due to detected anomalies."
    echo "$(date) NGX service was restarted due to detected anomalies" >> ${_pthOml}
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
    if [ "${ReTest}" -ge 1 ]; then
      rm -f /data/disk/*/static/control/run-nginx-restart.pid
      _thisErrLog="$(date) Nginx Server Restart Requested"
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

# Reload nginx if access log is missing or empty
[ -s /var/log/nginx/access.log ] || service nginx reload

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

