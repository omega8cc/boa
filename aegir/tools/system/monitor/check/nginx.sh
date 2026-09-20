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
    _CNT=$(pgrep -fc "(^|(^| )[^ ]*bash )[^ ]*/${_SCRIPT//./\\.}( |$)")
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
  # box. The -9 still follows, but only for what survives the grace, matched
  # by the title nginx sets at argv position 0 (master, workers, cache manager
  # and loader): a title SUBSTRING also hit any grep, tail or pgrep whose argv
  # carried "nginx: " -- during the very outage being cleared -- and a bare
  # process name would take a plain `nginx -t` or `-s reload` in flight with it.
  local _mpid _w=0
  _mpid=$( { tr -dc '0-9' < /run/nginx.pid; } 2>/dev/null )
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
  pkill -9 -f '^nginx: ' || true
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
    _MASTER_COUNT=$(pgrep -fc '^nginx: master process')
    if [ "${_MASTER_COUNT}" -gt 1 ]; then
      # Double-check after a short grace to avoid flapping
      sleep 5
      _MASTER_COUNT=$(pgrep -fc '^nginx: master process')
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
    if ! pgrep -f '^nginx: master process' \
      || [ ! -e "/run/nginx.pid" ]; then
      # Double-check after a short grace to avoid flapping
      sleep 3
      if ! pgrep -f '^nginx: master process' \
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
        if pgrep -f '^nginx: master process' >/dev/null 2>&1 \
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
  # The web hold's own breadcrumb counts too: inside a marker gap the hold
  # is kept on the breadcrumb alone, and a stand-down on the bare marker ate
  # the ACTIVE box's synced request there and restarted the mirror with it.
  # In the shipped flow no pass reaches here with the breadcrumb on disk (a
  # held pass and a no-answer pass both exit before the tail; a released one
  # removed the breadcrumb first), so this second line is belt against a
  # later removal of that exit, not the guard itself.
  [ -e "/root/.standby.cnf" ] && return 0
  [ -e "/var/log/boa/.standby_web_held.pid" ] && return 0

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

# Pass-scoped state for the standby block below: the cached restart answer,
# the cached marker-gap role, and the two "this pass could not tell, so it
# changed nothing" flags the release paths read.
_NGX_SQL_MUT_RC=""
_NGX_GAP_ROLE=""
_NGX_GAP_UNKNOWN=NO
_NGX_FTPS_GAP_UNKNOWN=NO

_sql_mutation_in_flight() {
  # move_sql.sh stops Nginx and every PHP-FPM pool to restart the database, and
  # it never brings them back: these watchdogs are the intended recovery. That
  # only works if they wait for the restart to finish. Restarting the web tier
  # mid-teardown stands it in front of a database that is still down, so workers
  # pile onto failed connections and the whole herd arrives at a cold cache the
  # moment the database returns; that cascade is what turns a brief database
  # fault into a site-wide one. runner.sh and system.sh already stand down on
  # the same two markers: mysql_restart_running.pid, written by move_sql.sh,
  # and boa_mysql_auto_healing.pid, held by the database watchdog for the
  # length of its heal.
  #
  # Honoured only while the marker is recent, deliberately. clear.sh reaps a
  # leaked mysql_restart_running.pid an hour after the writer died, and an hour
  # with no web auto-healing is a worse outcome than the cascade this avoids; a
  # marker older than the bound is treated as abandoned rather than authoritative.
  #
  # Answered once per pass and cached: the standby role read below asks as
  # well as the health checks at the tail, and one pass must not write the
  # stand-down line twice.
  [ -n "${_NGX_SQL_MUT_RC}" ] && return "${_NGX_SQL_MUT_RC}"
  local _m
  for _m in /run/mysql_restart_running.pid /run/boa_mysql_auto_healing.pid; do
    [ -e "${_m}" ] || continue
    if [ -z "$(find "${_m}" -mmin "+${_SQL_MUTATION_MAX_MINS}" 2>/dev/null)" ]; then
      echo "$(date) INFO: MySQL restart in progress (${_m##*/}); standing down this pass" >> ${_pthOml}
      _NGX_SQL_MUT_RC=0
      return 0
    fi
  done
  _NGX_SQL_MUT_RC=1
  return 1
}

###
### One definitive read of the database's own answer
###
_standby_role_read() {
  # Publishes _NGX_ROLE_ANSWER and, with it, _NGX_STANDBY_ROLE_WHY -- the
  # reason phrase a caller's single line quotes:
  #   REPLICA  a replica config is present
  #   LOCKED   no replica config but the DB is still read-only: a lost
  #            replica or an unlock that did not land, never a promotion
  #   PROMOTED clean read, no replica config, super_read_only 0
  #   UNKNOWN  the probe did not run clean, or the variable was unreadable
  # LOCKED is kept DISTINCT from REPLICA because the two holds below need
  # different answers from it: it drops the promoted latch (it is a
  # definitive "not promoted"), but it must never make the marker-gap arm
  # hold, which only a positive replica read may do.
  #
  # The return code decides, never emptiness alone: on Percona 5.7 the
  # first dialect always fails, and a dropped connection on the second
  # would otherwise read as "no replica config" on a running replica.
  local _rpl _rc _sro
  _rpl=$(mysql --connect-timeout=5 -e "SHOW REPLICA STATUS\G" 2>/dev/null)
  _rc=$?
  if [ "${_rc}" -ne "0" ]; then
    _rpl=$(mysql --connect-timeout=5 -e "SHOW SLAVE STATUS\G" 2>/dev/null)
    _rc=$?
  fi
  if [ "${_rc}" -ne "0" ]; then
    _NGX_ROLE_ANSWER=UNKNOWN
    _NGX_STANDBY_ROLE_WHY="the role probe did not run clean (credentials? mysqld down?)"
    return 0
  fi
  if [ -n "${_rpl}" ]; then
    _NGX_ROLE_ANSWER=REPLICA
    _NGX_STANDBY_ROLE_WHY="a replica config is still present"
    return 0
  fi
  _sro=$(mysql --connect-timeout=5 -N -e "SELECT @@super_read_only" 2>/dev/null | tr -dc '0-9')
  if [ "${_sro}" = "0" ]; then
    _NGX_ROLE_ANSWER=PROMOTED
    _NGX_STANDBY_ROLE_WHY=""
    return 0
  fi
  if [ "${_sro}" = "1" ]; then
    _NGX_ROLE_ANSWER=LOCKED
    _NGX_STANDBY_ROLE_WHY="the database is still read-only -- this box is not promoted, clear super_read_only"
    return 0
  fi
  _NGX_ROLE_ANSWER=UNKNOWN
  _NGX_STANDBY_ROLE_WHY="super_read_only was unreadable (credentials?)"
  return 0
}

###
### Is this marker-carrying box PROMOTED?
###
_standby_promoted() {
  # The web hold follows the DATABASE, never the xmass in-flight signal. That
  # signal opens at INIT as well as at the cutover, and a (re-)init is the
  # window in which a committed mirror, or a box holding a copied-in
  # production datadir, is most exposed: keyed on the signal, every init
  # released the web tier for its whole length, and a replica lost before the
  # role watchdog confirmed it left the tier open for as long as the signal's
  # age ceiling. The FTPS hold below already took this reasoning.
  #
  # PROMOTED = the role probe ran clean AND returned no replica config AND
  # super_read_only reads 0. Cutover step 11.5 proves exactly that before step
  # 12 starts nginx, and publishes the latch itself so no pass is waited on.
  #
  # Latched on disk, deliberately. A definitive read moves the latch; an
  # ambiguous one (mysqld restarting, an auth error, an empty variable)
  # changes NOTHING, so a database restart can neither open the tier on a
  # mirror nor shut it on a promoted box that still carries the marker (a
  # cutover parked at rename-failed, a step 15 whose removal was not
  # confirmed). Absent means HELD. It lives beside the other standby
  # breadcrumbs, so a reboot inherits the last proven answer.
  #
  # One probe a minute, every pass while an xmass window is open: a cutover
  # driven by bytes that do not publish the latch must not wait up to a
  # minute at step 12. A box without the marker never gets here.
  local _lat="/var/log/boa/.standby_promoted.pid"
  local _stm="/run/boa_standby_role_probed.pid"
  # A false answer always carries a reason, including on the passes that do
  # not probe: the latch is then the answer of the last definitive read, and
  # that is what the kept-hold line must report.
  _NGX_STANDBY_ROLE_WHY="the last role probe did not read this box as promoted"
  if [ -z "$(find "${_stm}" -mmin -1 2>/dev/null)" ] \
    || [ -n "$(find /run/boa_xmass_init.pid -mmin -2880 2>/dev/null)" ]; then
    touch "${_stm}" 2>/dev/null
    _standby_role_read
    case "${_NGX_ROLE_ANSWER}" in
      PROMOTED)
        if [ ! -e "${_lat}" ]; then
          echo "$(date) NGX standby: NO replica config and the DB is unlocked -- this box reads as PROMOTED, web tier released" >> ${_pthOml}
          mkdir -p /var/log/boa 2>/dev/null
          touch "${_lat}" 2>/dev/null
        fi
        ;;
      REPLICA|LOCKED)
        # Never remove a latch written AFTER this probe began: the cutover
        # publishes it the moment its own readback proves the unlock, and a
        # read taken a second earlier is already stale. No stamp means no
        # publish to protect: -nt reads true against a missing file, and
        # without that test a stale latch would be pinned for good.
        if [ -e "${_lat}" ] \
          && { [ ! -e "${_stm}" ] || [ ! "${_lat}" -nt "${_stm}" ]; }; then
          echo "$(date) NGX standby: replica config present or the DB locked -- this box reads as a STANDBY again, web tier held" >> ${_pthOml}
          rm -f "${_lat}"
        fi
        ;;
    esac
  fi
  if [ -e "${_lat}" ]; then
    _NGX_STANDBY_ROLE_WHY=""
    return 0
  fi
  return 1
}

###
### A marker GAP is not a promotion
###
# Every hold used to key on the bare presence of /root/.standby.cnf and
# released within one pass of its absence, while 'xmass sync --live' treats
# the same absence as an ACCIDENT and rewrites the marker on every run: a
# gap of seconds is an ordinary event on a healthy mirror. Measured on a
# 24 s gap: the DB hold released, this loop read the database as unlocked
# and opened the web tier, and the standby's own panel wrote 207 local
# transactions before the marker came back -- the replica's SQL thread died
# on a duplicate key and stayed dead.
#
# So a hold survives a gap on a box that still READS as a replica, and
# releases on a PROMOTED one: marker gone AND (a clean role probe with no
# replica config and an unlocked database, or the cutover's latch). A
# promotion by hand is "remove the marker AND reset the replica" -- the
# operator must reset it anyway, or the box keeps applying the source's
# binlog.
#
# Only a POSITIVE replica read may HOLD here, and that asymmetry is the
# point: an unreadable database is not evidence of anything, and a gap arm
# that held on "could not tell" would stop nginx and DROP 80/443 on a box
# being returned to service -- 'xmass restore-target' stops mysqld with
# this hold's breadcrumb still on disk. So LOCKED and UNKNOWN change
# NOTHING in either direction this pass: nothing is held, and the release
# paths below are skipped too (_NGX_GAP_UNKNOWN), so neither the chain nor
# the breadcrumb is removed on an answer that was never given.
#
# Cutover invariants this must not change: step 11.5 unlocks the database
# and publishes the latch while the marker is still present, so this hold
# is already released (chain gone, breadcrumb gone) before step 12 starts
# nginx; step 12 and step 15 remove the breadcrumbs themselves, so the arm
# below never engages on a promoted box.
_standby_hold_kept_log() {
  # One line per episode, shared by both holds below: this loop runs
  # several times a minute and the kept state lasts as long as the operator
  # leaves a half-promoted box alone. Cleared when the marker returns or
  # the box promotes. The reason is the one the read actually gave
  # (_NGX_STANDBY_ROLE_WHY): a line that guessed between the legs sent the
  # operator of a web-dark box after the wrong one.
  [ -e "/run/boa_standby_webkept_logged.pid" ] && return 0
  touch /run/boa_standby_webkept_logged.pid 2>/dev/null
  echo "$(date) NGX standby hold KEPT: marker gone but ${_NGX_STANDBY_ROLE_WHY} -- not a promotion (reset the replica to promote by hand; xmass sync restores the marker)" >> ${_pthOml}
  return 0
}

_standby_no_answer_log() {
  # The legs that answer NEITHER way (LOCKED, UNKNOWN) leave the box
  # firewalled off the web and its tenant channel shut, and they used to
  # write nothing at all: the reason the read composed was discarded, and
  # the only line such a box produced was the healer's misleading "Nginx
  # Server was down, restarted". This is the sole diagnostic for a
  # web-dark box, so it says what the read gave and that nothing moved.
  # Same stamp and cadence as the kept-hold line above -- one line per
  # episode, cleared when the marker returns or the box releases -- so the
  # two can never both speak for one episode.
  [ -e "/run/boa_standby_webkept_logged.pid" ] && return 0
  touch /run/boa_standby_webkept_logged.pid 2>/dev/null
  local _kept=""
  [ -e "/var/log/boa/.standby_web_held.pid" ] \
    && _kept="the firewall hold and the web breadcrumb"
  if [ -e "/var/log/boa/.standby_ftps_held.pid" ]; then
    [ -n "${_kept}" ] && _kept="${_kept} and "
    _kept="${_kept}the FTPS hold"
  fi
  : "${_kept:=the standby holds}"
  if [ "${_NGX_GAP_UNKNOWN}" = "YES" ]; then
    echo "$(date) NGX standby: marker gone but ${_NGX_STANDBY_ROLE_WHY} -- no answer, nothing changed this pass (${_kept} are kept)" >> ${_pthOml}
  else
    # Only the FTPS hold had no answer: a serving mirror's web tier is not
    # held, and this pass may just have released it, so the sentence must
    # not claim the whole pass stood still.
    echo "$(date) NGX standby: marker gone but ${_NGX_STANDBY_ROLE_WHY} -- no answer for the FTPS hold, it is kept" >> ${_pthOml}
  fi
  return 0
}

_standby_gap_role() {
  # The marker-GAP answer, shared by the two holds that key on their own
  # "was held" breadcrumb. Read once per pass and cached: both holds ask,
  # and a box that answered REPLICA to one must not answer PROMOTED to the
  # other within the same pass.
  #
  # The latch is read first: one file test, and it is the answer the
  # cutover PROVED at its step 11.5. second.sh reaps it within a minute of
  # the marker going, so a latch met here is a fresh one.
  #
  # Throttled to one probe a minute like the marker-present arm, and for a
  # harder reason: this is the ONE state the slice is built to sustain for
  # days (a half-promoted box, a LOST replica), and at nine passes a minute
  # every pass spent two to four mysql clients against a replica that is
  # applying the source's binlog. The stamp the marker arm writes is the
  # key, and the answer is cached beside it.
  #
  # The cache can only ever KEEP a hold, never take one down: PROMOTED is
  # the answer that releases, and it is never written to the cache, so a
  # release is always a fresh read (or the latch above, which is a file
  # test taken before it). The worst a stale cache can do is leave a box
  # held for the same minute the marker-present arm already waits.
  #
  # It cannot pin an answer across a re-seed either: the cache is read only
  # while the STAMP is present, second.sh reaps that stamp every minute the
  # marker is gone (its marker-gap reap) and xmass drops it at init, and
  # the answer file carries its own one-minute ceiling on top.
  # Only a box that was held and has lost its marker ever gets here.
  [ -n "${_NGX_GAP_ROLE}" ] && return 0
  local _stm="/run/boa_standby_role_probed.pid"
  local _ans="/run/boa_standby_role_answer"
  if [ -e "/var/log/boa/.standby_promoted.pid" ]; then
    _NGX_GAP_ROLE=PROMOTED
    _NGX_STANDBY_ROLE_WHY=""
    return 0
  fi
  # A database being torn down and restarted cannot be asked what it is.
  if _sql_mutation_in_flight; then
    _NGX_GAP_ROLE=UNKNOWN
    _NGX_STANDBY_ROLE_WHY="the database is being restarted"
    return 0
  fi
  if [ -e "${_stm}" ] && [ -n "$(find "${_ans}" -mmin -1 2>/dev/null)" ]; then
    local _cached
    _cached=$(head -1 "${_ans}" 2>/dev/null)
    case "${_cached}" in
      REPLICA|LOCKED|UNKNOWN)
        _NGX_GAP_ROLE="${_cached}"
        # The reason travels with the answer: a kept-hold line that guessed
        # between the legs sent the operator of a web-dark box after the
        # wrong one, and a cached answer must not reintroduce that guess.
        _NGX_STANDBY_ROLE_WHY=$(sed -n '2p' "${_ans}" 2>/dev/null)
        return 0
        ;;
    esac
  fi
  _standby_role_read
  _NGX_GAP_ROLE="${_NGX_ROLE_ANSWER}"
  touch "${_stm}" 2>/dev/null
  if [ "${_NGX_ROLE_ANSWER}" = "PROMOTED" ]; then
    rm -f "${_ans}"
  else
    { printf '%s\n%s\n' "${_NGX_ROLE_ANSWER}" "${_NGX_STANDBY_ROLE_WHY}" \
      > "${_ans}"; } 2>/dev/null
  fi
  return 0
}

_standby_held_without_marker() {
  # A box that WAS held (the web breadcrumb) and has lost its marker stays
  # held while it still reads as a REPLICA. The breadcrumb is what keeps a
  # normal box out of here for one file test, and what makes this
  # self-limiting: the release path below removes it, so a box released
  # once never re-enters.
  [ -e "/root/.standby.cnf" ] && return 1
  [ -e "/var/log/boa/.standby_web_held.pid" ] || return 1
  _standby_gap_role
  case "${_NGX_GAP_ROLE}" in
    REPLICA)
      _standby_hold_kept_log
      return 0
      ;;
    PROMOTED)
      return 1
      ;;
  esac
  # LOCKED or UNKNOWN: no answer, so no action -- and the release path must
  # not act either.
  _NGX_GAP_UNKNOWN=YES
  return 1
}

_standby_web_hold_wanted() {
  # serve.cnf semantics unchanged: a deliberately serving mirror is never
  # held here (and never wrote the breadcrumb, so it cannot reach the
  # marker-gap arm either).
  [ -e "/root/.standby.serve.cnf" ] && return 1
  if [ -e "/root/.standby.cnf" ]; then
    # The marker is back: the kept-hold episode is over, and a leaked stamp
    # would swallow the next one's line.
    [ -e "/run/boa_standby_webkept_logged.pid" ] \
      && rm -f /run/boa_standby_webkept_logged.pid
    _standby_promoted && return 1
    return 0
  fi
  _standby_held_without_marker
}

_standby_ftps_hold_wanted() {
  # FTPS keys on its OWN breadcrumb, never the web one: serve.cnf exempts
  # the web tier only, so a deliberately serving mirror never writes the
  # web breadcrumb -- borrowing it left exactly that box's tenant write
  # channel open for the whole of a marker gap, which is the one thing the
  # serve exemption is not meant to open. The breadcrumb is written by the
  # hold itself below, marker or gap, and removed when the box reads as
  # PROMOTED (the cutover and restore-target remove it too).
  [ -e "/root/.standby.cnf" ] && return 0
  [ -e "/var/log/boa/.standby_ftps_held.pid" ] || return 1
  _standby_gap_role
  case "${_NGX_GAP_ROLE}" in
    REPLICA)
      _standby_hold_kept_log
      return 0
      ;;
    PROMOTED)
      return 1
      ;;
  esac
  # LOCKED or UNKNOWN: no answer, so the breadcrumb stays and nothing is
  # killed this pass.
  _NGX_FTPS_GAP_UNKNOWN=YES
  return 1
}

# A passive mirror must not serve HTTP. A single rendered Drupal page writes
# its own panel/tenant database -- cache_bootstrap, the drupal_css_cache_files
# and drupal_js_cache_files aggregate registries, sessions, watchdog -- and on
# a replica those local writes both diverge the data and mint errant own-UUID
# GTIDs (measured: 13 transactions from one GET on an otherwise quiesced
# standby). Nothing on a standby needs the web tier before promotion, so hold
# nginx DOWN here and never heal it back up. This loop is the authoritative
# enforcer: it runs several times a minute, so an nginx a barracuda pass
# restarts underneath us is taken back down within seconds.
#
# Stands down once the box is PROMOTED (_standby_promoted above), not while
# an xmass window is open. Cutover step 12 (_xmass_prove_target_web) starts
# nginx and requires it to answer BEFORE step 15 removes the standby marker;
# step 11.5 runs first on every entry, resumes included, proves the database
# unlocked and publishes the latch, so step 12 never meets this hold. No init
# step needs the web tier, so an init window holds like any other minute.
#
# Operator escape hatch for a mirror that must genuinely serve:
# /root/.standby.serve.cnf
#
# FTPS on a standby: the same class of writer as the web tier -- an
# authenticated tenant upload lands in the synced trees and permanently
# shadows the active's copy under the -u legs. pure-ftpd has no init
# script; on a standby it exists only if something resurrected it (the
# system.sh healer stands aside on the marker OR on this hold's own
# breadcrumb, so the two do not fight across a gap), so kill on sight, log
# on transition only. Deliberately OUTSIDE the serve.cnf-exempt block
# below: serve is a web-only preview, never a tenant write channel. No
# cutover step needs FTPS, so the hold runs the whole cutover and step 15's
# removal of the standby marker is what releases it, within one monitor
# pass -- but a marker GAP is not that removal, so the same rule as the
# web tier applies: a box that was held and has lost its marker keeps FTPS
# down while it still reads as a REPLICA. The marker arm short-circuits,
# so a held mirror still pays one file test and no probe.
if _standby_ftps_hold_wanted; then
  # Written on every held pass, marker or gap: this is the record of "this
  # box was held as a standby" that the gap arm keys on, and a serve.cnf
  # mirror writes it too.
  mkdir -p /var/log/boa 2>/dev/null
  touch /var/log/boa/.standby_ftps_held.pid 2>/dev/null
  if pgrep -f '^pure-ftpd( |$)' > /dev/null 2>&1; then
    echo "$(date) FTPD replication standby: holding FTPS DOWN" >> ${_pthOml}
    pkill -9 -f '^pure-ftpd( |$)' > /dev/null 2>&1
  fi
elif [ "${_NGX_FTPS_GAP_UNKNOWN}" != "YES" ] \
  && [ -e "/var/log/boa/.standby_ftps_held.pid" ]; then
  # Released (PROMOTED): the breadcrumb goes with the hold, so this box
  # never re-enters the gap arm. A normal box pays one file test.
  rm -f /var/log/boa/.standby_ftps_held.pid
fi

# A serving standby is deliberate but must stay VISIBLE (2026-08-25 ruling:
# web-only scope, no expiry, operator-owned): one line an hour while the
# escape hatch holds, so a forgotten marker surfaces in the incident log
# instead of lingering silently for weeks.
if [ -e "/root/.standby.cnf" ] && [ -e "/root/.standby.serve.cnf" ]; then
  if [ -z "$(find /var/log/boa/.standby_serve_logged -mmin -60 2>/dev/null)" ]; then
    echo "$(date) NGX replication standby: SERVING deliberately via /root/.standby.serve.cnf (DB/tenant/backup holds stay)" >> ${_pthOml}
    mkdir -p /var/log/boa 2>/dev/null
    touch /var/log/boa/.standby_serve_logged
  fi
fi
if _standby_web_hold_wanted; then
  # Re-read the latch right before acting: the cutover may have published it
  # while the probe above was still reading a locked database.
  if pgrep -f '^nginx: master process' > /dev/null 2>&1 \
    && [ ! -e "/var/log/boa/.standby_promoted.pid" ]; then
    # Log on TRANSITION only: an orphan pidfile alone would otherwise write
    # ~9 lines a minute into the incident log forever.
    echo "$(date) NGX replication standby: holding the web tier DOWN" >> ${_pthOml}
    service nginx stop &> /dev/null
    sleep 2
    if pgrep -f '^nginx: master process' > /dev/null 2>&1; then
      _stop_nginx_processes
    fi
  fi
  # The init script only clears the pidfile on its own success branch, and
  # _stop_nginx_processes never does; a stale one left here would make the
  # health checks re-enter every pass.
  if [ -e "/run/nginx.pid" ] \
    && ! pgrep -f '^nginx: master process' > /dev/null 2>&1; then
    rm -f /run/nginx.pid
  fi
  # Firewall half of the web hold (2026-08-25 ruling): insurance against a
  # future init-script regression -- a directly started nginx would serve
  # for up to a minute before this loop kills it. Loopback stays exempt
  # (! -i lo): local proofs and cutover's own checks are not the traffic
  # this blocks. csfpost.sh re-adds the same rules right after any csf
  # restart flushes them; this loop heals the drift within a minute both
  # ways. Cutover step 12 removes the chain itself before proving the port
  # externally, so promotion never waits on this loop. The latch is read
  # once more here for the same reason as above: a chain re-added under
  # step 12's external proof would park the cutover. With the latch present
  # this pass falls through to the release path below.
  if [ ! -e "/var/log/boa/.standby_promoted.pid" ]; then
    for _ipt in iptables ip6tables; do
      command -v "${_ipt}" > /dev/null 2>&1 || continue
      "${_ipt}" -w 5 -nL BOA_STANDBY_WEB > /dev/null 2>&1 \
        || "${_ipt}" -w 5 -N BOA_STANDBY_WEB > /dev/null 2>&1
      "${_ipt}" -w 5 -C INPUT -j BOA_STANDBY_WEB > /dev/null 2>&1 \
        || "${_ipt}" -w 5 -I INPUT -j BOA_STANDBY_WEB > /dev/null 2>&1
      "${_ipt}" -w 5 -C BOA_STANDBY_WEB ! -i lo -p tcp -m multiport --dports 80,443 -j DROP > /dev/null 2>&1 \
        || "${_ipt}" -w 5 -A BOA_STANDBY_WEB ! -i lo -p tcp -m multiport --dports 80,443 -j DROP > /dev/null 2>&1
    done
    # Breadcrumb for the release path: only a box that ever HELD pays the
    # iptables execs on release checks -- a normal box pays one file test.
    mkdir -p /var/log/boa 2>/dev/null
    touch /var/log/boa/.standby_web_held.pid 2>/dev/null
    echo "Replication standby: web tier held down."
    exit 0
  fi
fi

# Not held (no marker and never held, serve.cnf, or a PROMOTED box): the
# firewall half must not survive -- remove it so a promotion by hand
# (marker removed AND the replica reset, no cutover) opens the web path
# within a minute, and serve.cnf opens the web tier without touching the
# DB/tenant/backup holds. A marker gap on a box that still reads as a
# replica never reaches this path: the hold above exits the pass first.
# A gap the role read could not answer (LOCKED, UNKNOWN) does not reach it
# either -- removing the chain and the breadcrumb there would release the
# box on no evidence, and the breadcrumb is what the next pass needs to
# ask the question again.
# Logs on transition only
# (the chain exists exactly once after a release). A box that still carries
# the marker looks every pass, breadcrumb or not: a csf restart through a
# csfpost.sh block of an older vintage may re-assert the chain there, and
# that must not outlive one pass on a promoted box.
if [ "${_NGX_GAP_UNKNOWN}" != "YES" ] \
  && { [ -e "/var/log/boa/.standby_web_held.pid" ] \
    || [ -e "/root/.standby.cnf" ]; }; then
  for _ipt in iptables ip6tables; do
    command -v "${_ipt}" > /dev/null 2>&1 || continue
    if "${_ipt}" -w 5 -nL BOA_STANDBY_WEB > /dev/null 2>&1; then
      echo "$(date) NGX standby web-hold released: removing firewall hold (${_ipt})" >> ${_pthOml}
      while "${_ipt}" -w 5 -D INPUT -j BOA_STANDBY_WEB 2>/dev/null; do :; done
      "${_ipt}" -w 5 -F BOA_STANDBY_WEB > /dev/null 2>&1
      "${_ipt}" -w 5 -X BOA_STANDBY_WEB > /dev/null 2>&1
    fi
  done
  # The breadcrumb goes with the chain: it is what keeps a released box out
  # of the marker-gap arm above. The kept-hold stamp goes with it -- that
  # episode ended the moment this box released.
  rm -f /var/log/boa/.standby_web_held.pid /run/boa_standby_webkept_logged.pid
fi

# A gap the role read could not answer changes NOTHING for the whole pass,
# the health checks below included. Without this exit the pass that must
# change nothing handed the deliberately stopped nginx to the healer at the
# tail: no master process, no restart marker, so it restarted a box that is
# dark on purpose, mailed an outage report about it, and the next pass that
# read REPLICA again stopped it -- the healer-versus-enforcer flap, in the
# fail-open direction, while this same pass keeps the DROP chain and the
# breadcrumb in place. The hold arm exits on its own answer for the same
# reason; this is the no-answer half of it. The FTPS leg gets its line
# here too, but never this exit: a serving mirror's web tier is up on
# purpose and its health checks must still run.
if [ "${_NGX_GAP_UNKNOWN}" = "YES" ] \
  || [ "${_NGX_FTPS_GAP_UNKNOWN}" = "YES" ]; then
  _standby_no_answer_log
fi
if [ "${_NGX_GAP_UNKNOWN}" = "YES" ]; then
  echo "Replication standby: no role answer this pass, nothing changed."
  exit 0
fi

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
