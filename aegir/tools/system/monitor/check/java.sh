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
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# An xmass hold keeps Solr DOWN while its index arrives by rsync, and the
# hold must be ENFORCED here, not just skipped: a barracuda pass re-arms
# the init scripts (+x) and starts Solr outright, and boot rc links
# survive plain stops. This per-minute watchdog is the loop that puts the
# hold back (the same role second.sh played for the old cron-wide
# quiesce). Disarm shape mirrors xmass/xtrim: no exec bit, no rc links,
# no process -- armed (-x) scripts only, so an already-disarmed set stays
# quiet. Kills go by service USER, never by bare substring: 'pkill -f
# solr9' matches the rsync receiver carrying /var/solr9 and would kill
# the very index transfer the hold protects. The marker is re-tested
# before each service so a concurrent step-14 removal stops us mid-loop.
if [ -e "/var/log/boa/.xmass_solr_hold.pid" ]; then
  for _svc in solr9 solr7 jetty9; do
    [ -e "/var/log/boa/.xmass_solr_hold.pid" ] || break
    if [ -e "/etc/init.d/${_svc}" ]; then
      if [ -x "/etc/init.d/${_svc}" ]; then
        # Record the disarm (a LIST, so the reversal below re-arms only
        # what this watchdog or xmass actually took down).
        grep -qx "${_svc}" /var/log/boa/.xmass_solr_disarmed.list 2>/dev/null \
          || echo "${_svc}" >> /var/log/boa/.xmass_solr_disarmed.list
        if id "${_svc}" &> /dev/null; then
          pkill -9 -u "${_svc}" &> /dev/null
        else
          pkill -9 -f "jav[a][0-9]* .*${_svc}" &> /dev/null
        fi
        update-rc.d "${_svc}" disable &> /dev/null
        chmod -x "/etc/init.d/${_svc}" 2>/dev/null
      elif id "${_svc}" &> /dev/null && pgrep -u "${_svc}" &> /dev/null; then
        # Already disarmed but a stray JVM survived (a raced start):
        # the hold means DOWN, so reap it.
        pkill -9 -u "${_svc}" &> /dev/null
      fi
    fi
  done
  if [ -x "/etc/init.d/solr4" ]; then
    grep -qx "solr4" /var/log/boa/.xmass_solr_disarmed.list 2>/dev/null \
      || echo "solr4" >> /var/log/boa/.xmass_solr_disarmed.list
    update-rc.d solr4 disable &> /dev/null
    chmod -x /etc/init.d/solr4 2>/dev/null
  fi
  exit 0
fi
# Belt for a standby without the hold marker (hand-built replica): never
# (re)start Solr on a box whose index may be arriving by rsync -- and
# never re-arm anything here either, whatever records linger.
[ -e "/root/.standby.cnf" ] && exit 0
# Self-reversing against vintage mix: if the hold's disarm was recorded
# and the marker is gone, an OLD-bytes xmass step 14 (which never
# re-arms, its start loop is -x gated) would leave Solr silently dead
# after cutover -- so restore exec bits and rc links for EXACTLY the
# recorded set; _solr_health_check_fix below then starts what should
# run. xtrim-finalized proxies and operator hand-disarms never enter the
# list and stay down. Below the standby belt on purpose: a standby box
# must not re-register Solr boot links.
if [ -e "/var/log/boa/.xmass_solr_disarmed.list" ]; then
  while read -r _svc; do
    case "${_svc}" in solr9|solr7|solr4|jetty9) : ;; *) continue ;; esac
    if [ -e "/etc/init.d/${_svc}" ]; then
      [ ! -x "/etc/init.d/${_svc}" ] && chmod 744 "/etc/init.d/${_svc}" 2>/dev/null
      update-rc.d "${_svc}" defaults &> /dev/null
      update-rc.d "${_svc}" enable &> /dev/null
    fi
  done < /var/log/boa/.xmass_solr_disarmed.list
  rm -f /var/log/boa/.xmass_solr_disarmed.list
fi
# Legacy record from the first shape of this mechanism: treat it as an
# unscoped hint once, then retire it.
if [ -e "/var/log/boa/.xmass_solr_disarmed.pid" ]; then
  rm -f /var/log/boa/.xmass_solr_disarmed.pid
fi

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
      if ! _incident_email_ratelimit "${2:-java}"; then
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

_jetty_restart() {
  touch /run/boa_java_auto_healing.pid
  sleep 3
  pkill -9 -f jetty9
  rm -f /var/log/jetty9/*
  find /tmp -mindepth 1 -user jetty9 -exec rm -rf {} + 2>/dev/null
  renice ${_B_NICE} -p $$ &> /dev/null
  if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
    service jetty9 start
    wait
  fi
  _thisErrLog="$(date) Jetty service has been restarted"
  echo ${_thisErrLog} >> ${_pthOml}
  _incident_email_report "$1"
  echo >> ${_pthOml}
  [ -e "/run/boa_java_auto_healing.pid" ] && rm -f /run/boa_java_auto_healing.pid
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
}

_jenkins_health_check_fix() {
  if ! pgrep -f java/jenkins \
    || [ ! -e "/run/jenkins/jenkins.pid" ]; then
    pkill -9 -f java
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
      find /tmp -mindepth 1 -user solr9 -exec rm -rf {} + 2>/dev/null
      service solr9 restart
      wait
      _thisErrLog="$(date) Solr9 Server was down, started"
      echo "${_thisErrLog}" >> ${_pthOml}
      _incident_email_report "Solr9 Server was down, started"
      echo >> ${_pthOml}
    else
      _pid="$(cat "${_pidfile}" 2>/dev/null | sed 's/[^0-9]//g')"
      if [ -n "${_pid}" ] && ! ps -p "${_pid}" >/dev/null 2>&1; then
        find /tmp -mindepth 1 -user solr9 -exec rm -rf {} + 2>/dev/null
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
      find /tmp -mindepth 1 -user solr7 -exec rm -rf {} + 2>/dev/null
      service solr7 restart
      wait
      _thisErrLog="$(date) Solr7 Server was down, started"
      echo "${_thisErrLog}" >> ${_pthOml}
      _incident_email_report "Solr7 Server was down, started"
      echo >> ${_pthOml}
    else
      _pid="$(cat "${_pidfile}" 2>/dev/null | sed 's/[^0-9]//g')"
      if [ -n "${_pid}" ] && ! ps -p "${_pid}" >/dev/null 2>&1; then
        find /tmp -mindepth 1 -user solr7 -exec rm -rf {} + 2>/dev/null
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
      find /tmp -mindepth 1 -user jetty9 -exec rm -rf {} + 2>/dev/null
      service jetty9 restart
      wait
      _thisErrLog="$(date) Solr4 Server was down, started"
      echo "${_thisErrLog}" >> ${_pthOml}
      _incident_email_report "Solr4 Server was down, started"
      echo >> ${_pthOml}
    else
      _pid="$(cat "${_pidfile}" 2>/dev/null | sed 's/[^0-9]//g')"
      if [ -n "${_pid}" ] && ! ps -p "${_pid}" >/dev/null 2>&1; then
        find /tmp -mindepth 1 -user jetty9 -exec rm -rf {} + 2>/dev/null
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

# Fire-and-forget launcher, cron-safe and interactive-safe
_spawn_detached() {
  _cmd="$1"
  if command -v nohup >/dev/null 2>&1; then
    nohup bash -c "${_cmd}" >/dev/null 2>&1 &
  elif command -v setsid >/dev/null 2>&1; then
    setsid bash -c "${_cmd}" >/dev/null 2>&1 &
  else
    ( bash -c "${_cmd}" >/dev/null 2>&1 ) &
  fi
  # If interactive shell, drop it from the job table to mimic cron behavior
  if [[ "$-" == *i* ]]; then disown; fi
}

_is_protected_run() {
  _protectedRun=FALSE
  _optBin="/opt/local/bin"
  _boaBins="autoinit automini barracuda boa octopus"
  for _cbn in ${_boaBins}; do
    if [ -e "${_optBin}/${_cbn}" ]; then
      # Anchored for every member, not just "boa": a bare path substring
      # matches any command line that merely MENTIONS the wrapper -- an
      # editor, a checksum, an operator's ssh probe -- and phantom-protects
      # the run. Same form clear.sh/runner.sh/owl.sh already use.
      _cPat="^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/${_cbn}( |$)"
      # Bare "boa" would match an hours-long remote install driven
      # from this box over ssh (and every boa-info probe); anchor it
      # to the LOCAL install form, as clear.sh/runner.sh already do
      [ "${_cbn}" = "boa" ] && _cPat="^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-"
      _CNT=$(pgrep -fc "${_cPat}")
      if (( _CNT > 0 )); then
        echo "The ${_cbn} is running!"
        _protectedRun=TRUE
      fi
    fi
  done
  # The chained install's legs run as "bash /var/backups/*.sh.txt", not as
  # the wrapper binaries swept above -- match them too: the installer takes
  # solr/jetty down and up inside those legs, and this watchdog fires ~9x a
  # minute, so a blind window here is near-certain to be hit
  if pgrep -f "^(/[^ ]*/)?bash (-c )?/var/backups/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1; then
    _protectedRun=TRUE
  fi
  [ -e "/run/octopus_install_run.pid" ] && _protectedRun=TRUE
  [ -e "/run/boa_run.pid" ] && _protectedRun=TRUE
  [ -e "/run/boa_wait.pid" ] && _protectedRun=TRUE
}
_is_protected_run

if [ "${_protectedRun}" = "FALSE" ]; then
  if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ]; then
    [ ! -e "/run/boa_java_auto_healing.pid" ] && [ -x "/etc/init.d/jenkins" ] && _jenkins_health_check_fix
    [ ! -e "/run/boa_java_auto_healing.pid" ] && _solr_health_check_fix
    [ ! -e "/run/boa_java_auto_healing.pid" ] && _jetty_listen_conflict_detection
  fi
fi

echo DONE!
exit 0
