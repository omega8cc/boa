#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/nginx.incident.log"

# Defaults before the cnf source below so the cnf value wins; the
# variable is the supported switch, the marker stays honoured for
# one release while fleets converge.
_ALLOW_NGINX_RESTART=NO

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
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# Sanitize to allow only digits and minus sign
export _B_NICE=${_B_NICE//[^0-9-]/}

# Validate and set default if necessary
if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
  _B_NICE=0
fi

# Clamp the value within -20 to 19
if (( _B_NICE < -20 )); then
  _B_NICE=-20
elif (( _B_NICE > 19 )); then
  _B_NICE=19
fi

renice ${_B_NICE} -p $$ &> /dev/null

_cd="/run/nginx-monitor.cooldown"
: "${_NGINX_COOLDOWN_SECS:=30}"

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
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
    # One alert per cooldown, not one per pass. A service that keeps failing
    # used to send a mail every time a watchdog acted, which buries the signal
    # exactly when it matters most. Nothing is lost: every incident is still
    # written to the log below, and the mail body is the tail of that log, so
    # the next alert that does go out carries the ones that did not. An older
    # lock.inc without the helper simply sends as before.
    local _sfx=""
    if command -v _incident_email_ratelimit >/dev/null 2>&1; then
      if ! _incident_email_ratelimit "${2:-nginx}"; then
        echo "$(date) INFO: alert for '${1}' held back, one was already sent this cooldown" >> ${_pthOml}
        return 1
      fi
      if [ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]; then
        _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
      fi
    fi
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1}${_sfx} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_pthOml}")
  fi
}

_stop_nginx_processes() {
  # Ask the recorded master to quit first: QUIT lets in-flight requests
  # finish, where the old unconditional -9 severed every connection on the
  # box. The -9 still follows, but only for what survives the grace, and
  # the pattern is bracket-tricked so it can never match this script's own
  # command line.
  local _mpid _w=0
  _mpid=$(tr -dc '0-9' < /run/nginx.pid 2>/dev/null)
  # The number must still BE nginx: a pidfile left by a -9'd master outlives
  # its owner on tmpfs, and a recycled pid would receive root's SIGQUIT.
  if [ -n "${_mpid}" ] \
    && [ "$(cat /proc/${_mpid}/comm 2>/dev/null)" = "nginx" ] \
    && kill -0 "${_mpid}" 2>/dev/null; then
    kill -QUIT "${_mpid}" 2>/dev/null
    while kill -0 "${_mpid}" 2>/dev/null && [ "${_w}" -lt 10 ]; do
      sleep 1
      _w=$(( _w + 1 ))
    done
  fi
  pkill -9 -f '[n]ginx: ' || true
}

_restart_nginx() {
  touch /run/boa_nginx_auto_healing.pid
  sleep 3
  echo "$(date) NGX $1 detected" >> ${_pthOml}
  # The hard-restart entry used by the OOM/bind/state detectors carried no
  # cooldown at all, so a symptom that survives a restart re-ran the whole
  # teardown on every pass; the down-detection path has always had one.
  _now=$(date +%s)
  if [ -s "${_cd}" ]; then
    _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
    if [ -n "${_ts}" ] && [ $((_now - _ts)) -ge 0 ] && [ $((_now - _ts)) -lt "${_NGINX_COOLDOWN_SECS}" ]; then
      echo "$(date) INFO: NGX $1 but in cooldown; skipping restart" >> ${_pthOml}
      [ -e "/run/boa_nginx_auto_healing.pid" ] && rm -f /run/boa_nginx_auto_healing.pid
      return 0
    fi
  fi
  echo "Killing all Nginx processes and restarting Nginx..."
  _stop_nginx_processes
  mv -f /var/log/nginx/error.log /var/log/nginx/$(date +%y%m%d-%H%M)-error.log
  service nginx restart
  date +%s > "${_cd}"
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
  [ -e "/run/boa_nginx_auto_healing.pid" ] && rm -f /run/boa_nginx_auto_healing.pid
  exit 0
}

_nginx_oom_detection() {
  if [ -e "/var/log/nginx/error.log" ]; then
    if [ `tail --lines=500 /var/log/nginx/error.log \
      | grep --count "Cannot allocate memory"` -gt 0 ]; then
      _thisErrLog="$(date) Nginx OOM error"
      echo "${_thisErrLog}" >> ${_pthOml}
      _restart_nginx "Nginx OOM"
    fi
  fi
}

_nginx_bind_check_fix() {
  if [ `tail --lines=8 /var/log/nginx/error.log \
    | grep --count "Address already in use"` -gt 0 ]; then
    _thisErrLog="$(date) Nginx BIND PORT error, service will be restarted"
    echo "${_thisErrLog}" >> ${_pthOml}
    _restart_nginx "Nginx BIND PORT error"
  fi
}

_nginx_health_check_fix() {
  # Initialize a flag to indicate whether Nginx service has been restarted
  _NGINX_RESTARTED=false
  # Check if Nginx is running and capture the process details
  _NGINX_PROCESSES=$(ps aux | grep 'nginx: ' | grep -v 'grep')
  # Check for multiple master processes (shouldn't happen)
  if [ "${_NGINX_RESTARTED}" = false ]; then
    _MASTER_COUNT=$(pgrep -fc 'nginx: [m]aster process')
    if [ "${_MASTER_COUNT}" -gt 1 ]; then
      # Double-check after a short grace to avoid flapping
      sleep 5
      _MASTER_COUNT=$(pgrep -fc 'nginx: [m]aster process')
      if [ "${_MASTER_COUNT}" -gt 1 ]; then
        echo "Multiple (${_MASTER_COUNT}) Nginx master processes detected. Possible stuck processes."
        echo "$(date) NGX multiple (${_MASTER_COUNT}) master processes detected" >> ${_pthOml}
        _restart_nginx "_MASTER_COUNT ${_MASTER_COUNT}"
      fi
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

_nginx_if_up_check_fix() {
  # Standard check first
  if [ -x "/etc/init.d/nginx" ]; then
    if ! pgrep -f 'nginx: [m]aster process' \
      || [ ! -e "/run/nginx.pid" ]; then
      # Double-check after a short grace to avoid flapping
      sleep 3
      if ! pgrep -f 'nginx: [m]aster process' \
        || [ ! -e "/run/nginx.pid" ]; then
        _now=$(date +%s)
        if [ -s "${_cd}" ]; then
          _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
          if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_NGINX_COOLDOWN_SECS}" ]; then
            echo "$(date) INFO: Nginx unhealthy but in cooldown; skipping restart" >> ${_pthOml}
            return 0
          fi
        fi
        # Positive evidence beats absence -- but only for the pidfile
        # artefact: a LIVE master whose /run/nginx.pid went missing is not
        # an outage, and restarting a serving nginx for it would be one.
        # When the MASTER is gone the opposite holds: workers inherit the
        # listen sockets and keep serving headless, so a listening port is
        # exactly what the one state this restart exists to clear looks
        # like, and standing down on it would leave the box unhealable.
        if pgrep -f 'nginx: [m]aster process' >/dev/null 2>&1 \
          && command -v ss >/dev/null 2>&1 \
          && ss -Hltn 2>/dev/null | grep -qE ':(80|443) '; then
          echo "$(date) INFO: Nginx master alive and serving; missing pidfile treated as an artefact, standing down" >> ${_pthOml}
          return 0
        fi
        _stop_nginx_processes
        mv -f /var/log/nginx/error.log /var/log/nginx/$(date +%y%m%d-%H%M)-error.log
        service nginx restart
        # Stamp cooldown after attempting recovery
        date +%s > "${_cd}"
        _thisErrLog="$(date) Nginx Server was down, restarted"
        echo "${_thisErrLog}" >> ${_pthOml}
        _incident_email_report "Nginx Server was down, restarted"
        echo >> ${_pthOml}
        exit 0
      fi
    fi
  fi
}

_if_nginx_restart() {
  # A passive mirror (replication standby): the sentinel is the ACTIVE box's
  # self-service request, delivered here only because static/control rides the
  # sync leg. Never consume it on the standby -- acting restarts a box that
  # serves nothing, and deleting the file eats a request that was never ours.
  [ -e "/root/.standby.cnf" ] && return 0

  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  _PrTestUltra=$(grep "ULTRA" /root/.*.octopus.cnf 2>&1)
  _PrTestMonster=$(grep "MONSTER" /root/.*.octopus.cnf 2>&1)
  # Counted without ls: an unmatched glob stays literal and fails the -e
  # test, so no error text ever feeds the count.
  ReTest=0
  for _cp in /data/disk/*/static/control/run-nginx-restart.pid; do
    [ -e "${_cp}" ] && ReTest=$(( ReTest + 1 ))
  done
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [[ "${_PrTestUltra}" =~ "ULTRA" ]] \
    || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
    || [ -e "/etc/boa/.allow.nginx.restart.cnf" ] \
    || [ "${_ALLOW_NGINX_RESTART}" = "YES" ]; then
    if [ "${ReTest}" -ge 1 ]; then
      # The sentinel is consumed only when the restart can actually run:
      # _restart_nginx now refuses inside the cooldown, and a request eaten
      # by a refusal would simply vanish. Leave it for the next pass instead.
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -ge 0 ] && [ $((_now - _ts)) -lt "${_NGINX_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: Nginx restart requested but in cooldown; request kept for the next pass" >> ${_pthOml}
          return 0
        fi
      fi
      rm -f /data/disk/*/static/control/run-nginx-restart.pid
      _thisErrLog="$(date) Nginx Server Restart Requested"
      echo "${_thisErrLog}" >> ${_pthOml}
      _restart_nginx "Nginx Server Restart Requested"
    fi
  fi
}

###
### Stand down while the database is being deliberately restarted
###
export _SQL_MUTATION_MAX_MINS=${_SQL_MUTATION_MAX_MINS//[^0-9]/}
: "${_SQL_MUTATION_MAX_MINS:=15}"

_sql_mutation_in_flight() {
  # move_sql.sh stops Nginx and every PHP-FPM pool to restart the database, and
  # it never brings them back: these watchdogs are the intended recovery. That
  # only works if they wait for the restart to finish. Restarting the web tier
  # mid-teardown stands it in front of a database that is still down, so workers
  # pile onto failed connections and the whole herd arrives at a cold cache the
  # moment the database returns; that cascade is what turns a brief database
  # fault into a site-wide one. runner.sh and system.sh already stand down on
  # the same two markers: mysql_restart_running.pid, written by move_sql.sh and
  # by mycnfup, and boa_mysql_auto_healing.pid, held by the database watchdog
  # for the length of its heal.
  #
  # Honoured only while the marker is recent, deliberately. clear.sh reaps a
  # leaked mysql_restart_running.pid an hour after the writer died, and an hour
  # with no web auto-healing is a worse outcome than the cascade this avoids; a
  # marker older than the bound is treated as abandoned rather than authoritative.
  local _m
  for _m in /run/mysql_restart_running.pid /run/boa_mysql_auto_healing.pid; do
    [ -e "${_m}" ] || continue
    if [ -z "$(find "${_m}" -mmin "+${_SQL_MUTATION_MAX_MINS}" 2>/dev/null)" ]; then
      echo "$(date) INFO: MySQL restart in progress (${_m##*/}); standing down this pass" >> ${_pthOml}
      return 0
    fi
  done
  return 1
}

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ] \
  && ! _sql_mutation_in_flight; then
  _nginx_if_up_check_fix
  _nginx_bind_check_fix
  _nginx_oom_detection
  _nginx_health_check_fix
  [ -d "/data/u" ] && _if_nginx_restart
fi

echo "Done!"
exit 0
