#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/java.incident.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
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
    # -------- legacy one-slot guard ---------
    # allow up to ONE concurrent worker; exit the 2nd+
    # Robustly match only the real worker:
    #  - direct exec:  "/full/path/script"
    #  - via bash:     "bash /full/path/script"
    _ABS="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
    # escape regex specials for pgrep
    _PAT="$(printf '%s' "$_ABS" | sed 's/[.[\*^$(){}+?\\|]/\\&/g')"
    # Count only lines that contain our absolute path, *and* either begin with bash+path or path at a word boundary.
    # This avoids counting the wrapper like '/bin/dash -c bash /path/script …' twice.
    _CNT=$(
      ps ax -o pid= -o args= \
        | awk -v P="$_PAT" '
            $0 ~ ("(^|[[:space:]]|/)bash[[:space:]]+" P "([[:space:]]|$)") ||
            $0 ~ ("(^|[[:space:]])" P "([[:space:]]|$)")
          ' \
        | wc -l
    )
    if [ "${_CNT:-0}" -gt 1 ]; then
      mkdir -p /var/log/boa 2>/dev/null || true
      echo "Too many ${_SELF_NAME} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
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

_jetty_restart() {
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
      _thisErrLog="$(date) Address already in use for jetty9"
      echo ${_thisErrLog} >> ${_pthOml}
      _jetty_restart "jetty9 zombie"
    fi
  fi
  if [ -e "/var/log/jetty8" ]; then
    if [ `tail --lines=500 /var/log/jetty8/*stderrout.log \
      | grep --count "Address already in use"` -gt 0 ]; then
      _thisErrLog="$(date) Address already in use for jetty8"
      echo ${_thisErrLog} >> ${_pthOml}
      _jetty_restart "jetty8 zombie"
    fi
  fi
  if [ -e "/var/log/jetty7" ]; then
    if [ `tail --lines=500 /var/log/jetty7/*stderrout.log \
      | grep --count "Address already in use"` -gt 0 ]; then
      _thisErrLog="$(date) Address already in use for jetty7"
      echo ${_thisErrLog} >> ${_pthOml}
      _jetty_restart "jetty7 zombie"
    fi
  fi
}

if [ ! -e "/root/.high_traffic.cnf" ] \
  && [ ! -e "/root/.giant_traffic.cnf" ]; then
  perl /var/xdrago/monitor/check/locked_java.pl &
fi

echo DONE!
exit 0

