#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/mysql.incident.log"
_pthLdg="/var/log/boa/mysql.restart.ledger"
_pthCdn="/run/mysql-monitor.cooldown"
_pthLch="/run/boa_mysql_restart_latched.pid"

# Defaults before the cnf source below so the cnf value wins; the
# variable is the supported switch, the marker stays honoured for
# one release while fleets converge.
_INSTANT_BUSY_MYSQL_ACTION=NO
_MYSQLADMIN_MONITOR=NO

_provision_running() {
  # Genuine task EXECUTIONS only. BOA spawns them as
  #   su -s /bin/bash - <user> -c "<php> /usr/bin/drush @<site> provision-<task>"
  # so a real task always carries the drush command token somewhere in its
  # process tree, and the php/su process running it always has provision on its
  # command line. The bare substring match this replaces reported "running" for
  # any command line that merely MENTIONED a provision path -- a checksum, an
  # editor, an operator's ssh probe, a monitoring loop. Mirrored from
  # night/night.inc.sh on purpose: this tool has no library to source.
  pgrep -f "provision-[a-z]" > /dev/null 2>&1 && return 0
  # The front-end dispatch phase of a task carries no provision-* token: the
  # backend child is spawned only after bootstrap, and the post-hooks run after
  # it exits, so those windows were invisible. ( |$) is LOAD-BEARING -- without
  # it this also matches hosting-tasks and hosting-dispatch, the per-minute
  # pollers, which would pin the gate ON and disable every nightly cleanup.
  pgrep -f "hosting-task( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^([^ ]*/)?(php[0-9.]*|su|env|drush[0-9]*)( |$).*provision" > /dev/null 2>&1 && return 0
  return 1
}

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

# Stand down ENTIRELY during a controlled SQL maintenance window. A Percona
# upgrade or an xmass/xoct migration deliberately stops, locks, dumps, restores
# or restarts MySQL, and ANY action from this watchdog -- auto-heal restart,
# high-load restart, busy restart, long-query kill -- races that into a corrupt
# xtrabackup snapshot, a broken replica, a broken cutover FLUSH-lock (DATA LOSS),
# or a half-applied 5.7->8.0 DD upgrade (the ibdata1 lock loop). The operation
# holds /run/boa_sql_maintenance.pid for its critical section and clears it at
# the end. A STALE marker (>4h, e.g. an operation that died without cleanup) is
# ignored so auto-heal can never be disabled forever; /run is tmpfs so it also
# clears on reboot.
if [ -e "/run/boa_sql_maintenance.pid" ]; then
  if [ -n "$(find /run/boa_sql_maintenance.pid -mmin +240 2>/dev/null)" ]; then
    rm -f /run/boa_sql_maintenance.pid
  else
    exit 0
  fi
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

export _SQL_MAX_TTL=${_SQL_MAX_TTL//[^0-9]/}
: "${_SQL_MAX_TTL:=3600}"

export _SQL_LOW_MAX_TTL=${_SQL_LOW_MAX_TTL//[^0-9]/}
: "${_SQL_LOW_MAX_TTL:=60}"

export _LOAD_THRESHOLD=${_LOAD_THRESHOLD//[^0-9.]/}
: "${_LOAD_THRESHOLD:=33.0}" # Example: 1-minute load above 33 indicates high load

export _THREAD_THRESHOLD=${_THREAD_THRESHOLD//[^0-9]/}
: "${_THREAD_THRESHOLD:=99}" # Example: More than 99 MySQL threads

###
### Flap control for the auto-heal. A restart that has to be repeated is evidence
### the restart is not the remedy, so the second one is spaced out (cooldown) and
### the run of them is capped (circuit-breaker). Every value can be overridden
### from /root/.barracuda.cnf.
###
_sql_flap_num() {
  # Normalise one operator-supplied number: digits only, and with any leading
  # zeros stripped. Bash reads a zero-padded number as octal inside $(( )),
  # where 08 is a hard error and 0900 is not 900 -- either would quietly corrupt
  # the window arithmetic below and leave the breaker silently never opening,
  # which is the one failure this whole mechanism must not have. Falls back to
  # the given default when nothing usable is left.
  local _v="${1//[^0-9]/}"
  while [ "${#_v}" -gt 1 ] && [ "${_v:0:1}" = "0" ]; do
    _v="${_v:1}"
  done
  [ -n "${_v}" ] || _v="$2"
  printf '%s' "${_v}"
}

_SQL_COOLDOWN_SECS=$(_sql_flap_num "${_SQL_COOLDOWN_SECS}" 120)   # Minimum gap between two auto-heals

_SQL_FLAP_MAX=$(_sql_flap_num "${_SQL_FLAP_MAX}" 3)               # Auto-heals tolerated inside the window
# Zero would latch the breaker before the first legitimate recovery could run.
[ "${_SQL_FLAP_MAX}" -lt 1 ] && _SQL_FLAP_MAX=1

_SQL_FLAP_WINDOW_SECS=$(_sql_flap_num "${_SQL_FLAP_WINDOW_SECS}" 3600) # Window those auto-heals are counted in
# The window has to be wide enough to still hold _SQL_FLAP_MAX heals at the pace
# this watchdog itself enforces, or the oldest entry ages out before the breaker
# can count it and the circuit never opens -- silently, and worst on exactly the
# big boxes it exists for, where confirming the outage, stopping a wedged server
# and waiting out a multi-gigabyte buffer pool can put minutes between heals on
# top of the cooldown. Floor it at that pace so a narrowed window cannot disable
# the breaker by accident.
_SQL_FLAP_FLOOR=$(( _SQL_FLAP_MAX * (_SQL_COOLDOWN_SECS + 240) ))
if [ "${_SQL_FLAP_WINDOW_SECS}" -lt "${_SQL_FLAP_FLOOR}" ]; then
  _SQL_FLAP_WINDOW_SECS="${_SQL_FLAP_FLOOR}"
fi

_SQL_FLAP_LATCH_MINS=$(_sql_flap_num "${_SQL_FLAP_LATCH_MINS}" 60)     # Cool-off before an open circuit re-arms

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
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ]; then
    # One alert per cooldown, not one per heal. The restart storm this watchdog
    # was rebuilt around sent nine near-identical mails in fourteen minutes, and
    # an operator cannot tell one flap from nine faults that way. Nothing is
    # lost: every incident is still written to the log below, and the mail body
    # is the tail of that log, so the next alert carries the ones held back.
    # The caller passes its own key as $2 to keep a class of alert on its own
    # cooldown, and classes that are not the same incident must not share one:
    # the circuit-breaker page has its own so it is never held behind the heal
    # mails it explains, and backup contention has its own so a busy backup
    # window cannot swallow the page that says the database went down. An older
    # lock.inc sends as before.
    local _sfx=""
    if command -v _incident_email_ratelimit >/dev/null 2>&1; then
      if ! _incident_email_ratelimit "${2:-mysql}"; then
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

_sql_flap_prune_ledger() {
  # Count the auto-heals recorded within the flap window and rewrite the ledger
  # with only those, so it stays small and needs no rotation. Result in the
  # global _SQL_FLAP_COUNT. Reads via redirect, not a pipe, so the counter is
  # incremented in this shell and not in a subshell that discards it.
  #
  # An entry stamped in the future can only come from a backwards clock step; it
  # is dropped rather than counted, because the breaker must never latch on a
  # clock artefact and refuse a genuine recovery.
  #
  # The ledger outlives a reboot, but the flap history does not: restarts from
  # before the box came up say nothing about this boot, and counting them could
  # latch the breaker during the post-boot window where alerts are suppressed --
  # a latch nobody is paged about. So never look further back than boot time.
  local _cut _boot _line _stamp _tmp
  _SQL_FLAP_COUNT=0
  [ -s "${_pthLdg}" ] || return 0
  _cut=$(( $1 - _SQL_FLAP_WINDOW_SECS ))
  _boot=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
  _boot="${_boot//[^0-9]/}"
  if [ -n "${_boot}" ] && [ "$(( $1 - _boot ))" -gt "${_cut}" ]; then
    _cut=$(( $1 - _boot ))
  fi
  _tmp="${_pthLdg}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  while read -r _line; do
    _stamp="${_line//[^0-9]/}"
    [ -n "${_stamp}" ] || continue
    if [ "${_stamp}" -gt "${_cut}" ] && [ "${_stamp}" -le "$1" ]; then
      echo "${_stamp}" >> "${_tmp}"
      _SQL_FLAP_COUNT=$(( _SQL_FLAP_COUNT + 1 ))
    fi
  done < "${_pthLdg}"
  mv -f "${_tmp}" "${_pthLdg}" 2>/dev/null || rm -f "${_tmp}"
}

_sql_flap_breaker_is_open() {
  # The open circuit is a latched refusal to auto-restart MySQL, cleared by an
  # operator (remove the file) or by the cool-off. Age comes from the file mtime
  # with the same `find -mmin` idiom the SQL-maintenance stand-down uses above,
  # so a forgotten latch can never disable auto-healing permanently.
  [ -e "${_pthLch}" ] || return 1
  if [ -n "$(find "${_pthLch}" -mmin "+${_SQL_FLAP_LATCH_MINS}" 2>/dev/null)" ]; then
    rm -f "${_pthLch}"
    # Opening the circuit already discarded the history, and nothing is counted
    # while it is open. Clear it again anyway so the invariant "a re-armed
    # breaker starts counting at zero" holds however the ledger got there.
    rm -f "${_pthLdg}"
    echo "$(date) MySQL auto-restart re-armed after the ${_SQL_FLAP_LATCH_MINS} min cool-off" >> ${_pthOml}
    return 1
  fi
  return 0
}

_sql_restart() {
  # Minimal-blast-radius recovery: a DB fault heals ONLY the DB. Never stop
  # nginx/php-fpm, drop caches, wipe the cache or kill php from here -- that
  # amplifies a DB blip into a site-wide outage and a cache stampede (the
  # observed restart storm).
  #
  # A server that answers at all is not something to restart: return at once so
  # the caller's real remedies (flush-hosts, long-query kill) still run and no
  # incident is logged or emailed for a non-event. This also catches a DB that
  # recovered on its own between detection and here (e.g. a mysqld_safe respawn).
  if _mysql_is_answering; then
    return 0
  fi
  # Flap control. A database that was just auto-restarted and is down AGAIN is
  # not one another restart will fix; repeating the heal is what turned a 1s blip
  # into nine whole-stack teardowns in fourteen minutes on one busy hosted box
  # with the most cache to lose and the largest herd behind it. Two guards,
  # cheapest first: a cooldown that spaces consecutive heals, and a breaker that
  # latches once _SQL_FLAP_MAX heals have run inside _SQL_FLAP_WINDOW_SECS and
  # then refuses to act at all, pages once, and waits for an operator.
  local _now _ts _gap
  _now=$(date +%s)
  if _sql_flap_breaker_is_open; then
    echo "$(date) $1 incident: CIRCUIT OPEN, auto-restart refused -- see ${_pthLch}" >> ${_pthOml}
    echo >> ${_pthOml}
    exit 0
  fi
  if [ -s "${_pthCdn}" ]; then
    _ts=$(tr -dc '0-9' < "${_pthCdn}" 2>/dev/null)
    if [ -n "${_ts}" ]; then
      _gap=$(( _now - _ts ))
      # A negative gap means the clock stepped backwards: treat the stamp as
      # unusable and act, instead of freezing the watchdog until it catches up.
      if [ "${_gap}" -ge 0 ] && [ "${_gap}" -lt "${_SQL_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: MySQL not answering but in cooldown (${_gap}s < ${_SQL_COOLDOWN_SECS}s); skipping restart" >> ${_pthOml}
        exit 0
      fi
    fi
  fi
  _sql_flap_prune_ledger "${_now}"
  if [ "${_SQL_FLAP_COUNT}" -ge "${_SQL_FLAP_MAX}" ]; then
    echo "$(date) CIRCUIT OPEN: ${_SQL_FLAP_COUNT} MySQL auto-restarts in the last ${_SQL_FLAP_WINDOW_SECS} seconds, so auto-restart is now disabled. Fix the cause, then delete this file to re-arm it; it also re-arms on its own ${_SQL_FLAP_LATCH_MINS} minutes after this stamp." > "${_pthLch}"
    # The latch now carries the whole state of the breaker, so the history that
    # opened it goes with it. Otherwise an operator who fixes the cause and does
    # what the latch file tells them -- delete it -- would be re-latched and
    # re-paged on those same stale entries, and left refusing the restart they
    # just enabled. Re-arming, by hand or by cool-off, starts counting at zero.
    rm -f "${_pthLdg}"
    echo "$(date) $1 incident: CIRCUIT OPEN after ${_SQL_FLAP_COUNT} auto-restarts within ${_SQL_FLAP_WINDOW_SECS}s -- refusing to restart MySQL again" >> ${_pthOml}
    _incident_email_report "CIRCUIT OPEN: MySQL auto-restart disabled after ${_SQL_FLAP_COUNT} restarts" "mysql-circuit"
    echo >> ${_pthOml}
    exit 0
  fi
  # Record the attempt BEFORE acting: a heal that ends this script (or the box)
  # must still leave evidence, or the breaker forgets the restart ever happened.
  echo "${_now}" >> "${_pthLdg}"
  # Genuinely not answering. Recover mysqld and nothing else.
  touch /run/boa_mysql_auto_healing.pid
  if [ ! -d "/run/mysqld" ]; then
    mkdir -p /run/mysqld
    chown -R mysql:root /run/mysqld
  fi
  if pgrep -f /usr/sbin/mysqld > /dev/null 2>&1; then
    # Present but not answering = wedged/deadlocked. A plain start would no-op on
    # the live PID, so force a db-only restart (stop the hung mysqld, start fresh).
    echo "$(date) $1 incident: mysqld present but not answering -- db-only restart" >> ${_pthOml}
    bash /var/xdrago/move_sql.sh dbrestart
  else
    echo "$(date) $1 incident: mysqld absent -- starting it" >> ${_pthOml}
    bash /var/xdrago/move_sql.sh start
  fi
  if _mysql_is_answering; then
    echo "$(date) $1 incident response completed: MySQL answering" >> ${_pthOml}
  else
    echo "$(date) $1 incident response completed: MySQL still not answering" >> ${_pthOml}
  fi
  # Hold the next auto-heal off for the cooldown window. Stamped after the action
  # so the gap is measured from when this heal finished, matching nginx.sh/php.sh.
  date +%s > "${_pthCdn}"
  _incident_email_report "$1"
  echo >> ${_pthOml}
  [ -e "/run/boa_mysql_auto_healing.pid" ] && rm -f /run/boa_mysql_auto_healing.pid
  exit 0
}

_sql_busy_detection() {
  if [ -e "/var/log/daemon.log" ]; then
    _SQL_LOG="/var/log/daemon.log"
  else
    _SQL_LOG="/var/log/syslog"
  fi
  if [ -e "${_SQL_LOG}" ]; then
    if [ `tail --lines=333 ${_SQL_LOG} \
      | grep --count "Too many connections"` -gt 111 ]; then
      if ! _provision_running; then
        _sql_restart "BUSY MySQL"
      fi
    fi
  fi
  if [ "${_INSTANT_BUSY_MYSQL_ACTION}" = "YES" ] \
    || [ -e "/etc/boa/.instant.busy.mysql.action.cnf" ]; then
    # File-existence check instead of cat'ing the cleartext root password
    # into a shell variable just to test its non-emptiness. The mysql call
    # below uses /root/.my.cnf credentials implicitly via `mysql -u root`.
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ] && [ -s /root/.my.pass.txt ]; then
      _MYSQL_CONN_TEST=$(mysql -u root -e "status" 2>&1)
      if [[ "${_MYSQL_CONN_TEST}" =~ "Too many connections" ]]; then
        # This used to call _sql_restart, which could never act: the trigger
        # above proves the server is ANSWERING, and _mysql_is_answering counts
        # "Too many connections" as alive, so _sql_restart returned at its first
        # line every time. The opt-in silently did nothing.
        #
        # Route it to the remedies that actually relieve connection saturation.
        # Both also run later in an ordinary pass, but the later long-query
        # sweep is suppressed while max_load/critical_load markers exist -- which
        # is exactly the regime that produces this saturation -- so running them
        # here is what makes the opt-in mean something.
        if ! _provision_running; then
          echo "INSTANT BUSY MySQL: relieving connection saturation"
          _mysql_flush_hosts
          _mysql_proc_control "${_SQL_MAX_TTL}"
        else
          echo "INSTANT BUSY MySQL: an Aegir/Provision task is in flight -- deferring"
        fi
      fi
    fi
  fi
}

_mysql_proc_kill() {
  _xtime=${_xtime//[^0-9]/}
  echo "Monitoring process ${_each} by ${_xuser} running for ${_xtime} seconds"

  if [[ -n "${_xtime}" && ${_xtime} -gt ${_limit} ]]; then
    echo "Killing process ${_each} by ${_xuser} after ${_xtime} seconds"
    _xkill=$(mysqladmin -u root kill ${_each} 2>&1)
    _times=$(date)
    _load=$(cat /proc/loadavg)

    # Log the _load and the process killing details
    echo "${_load}" >> /var/log/boa/sql_watch.log
    echo "${_times} ${_each} ${_xuser} ${_xtime} ${_xkill}" >> /var/log/boa/sql_watch.log
  fi
}

_mysql_proc_control() {
  # Control file to enable _SQLMONITOR
  if [ "${_MYSQLADMIN_MONITOR}" = "YES" ] \
    || [ -e "/etc/boa/.mysqladmin.monitor.cnf" ]; then
    _SQLMONITOR=YES
  fi

  # Log the MySQL process list if _SQLMONITOR is enabled
  for _f in .debug_slow_query.pid .nodebug_slow_query.pid; do
    [ -e "/root/${_f}" ] && [ ! -e "/var/log/boa/${_f}" ] && cp -a "/root/${_f}" /var/log/boa/ 2>/dev/null
  done
  if [[ "${_SQLMONITOR}" == "YES" ]]; then
    [ -e "/var/xdrago/log/mysqladmin.monitor.log" ] && mv -f /var/xdrago/log/mysqladmin.monitor.log /var/log/boa/
    [ -e "/var/log/boa/.nodebug_slow_query.pid" ] && rm -f /var/log/boa/.nodebug_slow_query.pid
    if [ ! -e "/var/log/boa/.debug_slow_query.pid" ]; then
      touch /var/log/boa/.debug_slow_query.pid
      mysql -u root -e "SET GLOBAL slow_query_log = 'ON';" &> /dev/null
      mysql -u root -e "SET GLOBAL long_query_time = 5;" &> /dev/null
      mysql -u root -e "SET GLOBAL slow_query_log_file = '/var/log/mysql/sql-slow-query.log';" &> /dev/null
    fi
    echo "$(date 2>&1)" >> /var/log/boa/mysqladmin.monitor.log
    echo "$(mysqladmin -u root proc -v 2>&1)" >> /var/log/boa/mysqladmin.monitor.log
  else
    [ -e "/var/log/boa/.debug_slow_query.pid" ] && rm -f /var/log/boa/.debug_slow_query.pid
    if [ ! -e "/var/log/boa/.nodebug_slow_query.pid" ]; then
      mysql -u root -e "SET GLOBAL slow_query_log = 'OFF';" &> /dev/null
      touch /var/log/boa/.nodebug_slow_query.pid
      [ -e "/var/log/boa/mysqladmin.monitor.log" ] && rm -f /var/log/boa/mysqladmin.monitor.log
      [ -e "/var/log/mysql/sql-slow-query.log" ] && rm -f /var/log/mysql/sql-slow-query.log
    fi
  fi

  # Default TTL _limit in seconds (can be adjusted)
  _limit=${1:-3600}

  # Get all MySQL processes and extract PID, user, and running time. Asked
  # for by name: the old positional parse of formatted output shifted
  # whenever a column was blank (NULL db, empty host), so the time tested
  # could be some other field entirely -- on the path that kills.
  _mysql_proc_list=$(mysql -Nse "SELECT id, user, time FROM information_schema.processlist WHERE id != CONNECTION_ID() AND command != 'Daemon' AND command NOT LIKE 'Binlog Dump%' AND user != 'system user';" 2>/dev/null)

  # Iterate over _each process
  echo "${_mysql_proc_list}" | while read -r _each _xuser _xtime; do
    _each=${_each//[^0-9]/}
    _xuser=${_xuser//[^0-9a-z_]/}
    _xtime=${_xtime//[^0-9]/}

    # Skip root user processes
    if [[ "${_xuser}" == "root" ]]; then
      echo "Skipping root process: ${_each}"
      continue
    fi

    if [[ -n "${_each}" && "${_each}" -gt 5 && -n "${_xtime}" ]]; then
      echo "Process ID: ${_each}, User: ${_xuser}, Time: ${_xtime} seconds"

      # The limit is computed fresh for every process: it used to be lowered
      # once a problematic user matched and never restored, so a single
      # short-TTL user dragged every later process in the pass down with it.
      _limit=${_SQL_MAX_TTL}
      if [[ -e "/etc/boa/.sql.problematic.users.cnf" ]]; then
        for _XQ in $(cat /etc/boa/.sql.problematic.users.cnf | cut -d '#' -f1 | sort | uniq); do
          if [[ "${_xuser}" == "${_XQ}" ]]; then
            echo "Problematic user detected: ${_xuser}, applying lower limit"
            _limit=${_SQL_LOW_MAX_TTL}
          fi
        done
      fi

      _mysql_proc_kill
    fi
  done
}

_mysql_high_load() {

  # Get the current 1-minute load average
  _LOAD=$(awk '{print $1}' /proc/loadavg)

  # Get the mysqld process ID
  _MYSQL_PID=$(pidof mysqld)

  # Count threads for the mysqld process (subtracting the header)
  _MYSQL_THREADS=$(ps -T -p "${_MYSQL_PID}" | tail -n +2 | wc -l)

  echo "Current load average: ${_LOAD}"
  echo "Current MySQL thread count: ${_MYSQL_THREADS}"

  # Compare against thresholds; use bc for floating point comparison
  if (( $(echo "${_LOAD} > ${_LOAD_THRESHOLD}" | bc -l) )) && [ "${_MYSQL_THREADS}" -gt "${_THREAD_THRESHOLD}" ]; then
    echo "High load and excessive MySQL threads detected. Restarting MySQL..."
    # Gated like the busy path below: a Provision task churns connections and
    # threads by design, and restarting under it loses the task's work. The DOWN
    # path (_mysql_health_check_fix) stays UNgated on purpose -- a server that
    # fails four live probes is a real outage and must be healed regardless.
    if ! _provision_running; then
      _sql_restart "HIGH LOAD MySQL"
    else
      echo "HIGH LOAD MySQL: an Aegir/Provision task is in flight -- not restarting"
    fi
  else
    echo "System operating normally."
  fi
}

_if_mydumper_is_locked() {
  _OCT_NR=$(ls /data/disk | wc -l)
  if [ -n "${_OCT_NR}" ] && [ "${_OCT_NR}" -ge 1 ]; then
    if [ "${_OCT_NR}" -ge 6 ]; then
      _MULTI_MX=$(( _OCT_NR * 3 ))
    else
      _MULTI_MX=$(( _OCT_NR * 5 ))
    fi
    if [ "${_OCT_NR}" -lt 4 ]; then
      _MULTI_MX=$(( _OCT_NR + 10 ))
    fi
  fi
  _AR_C="$(pgrep -fc aegir.sh)"
  _DR_C="$(pgrep -fc drush.php)"
  _MD_C="$(pgrep -fc mydumper)"
  if [ "${_MD_C}" -gt 0 ]; then
    if [ "${_AR_C}" -gt "${_MULTI_MX}" ]; then
      pkill -f mydumper
      pkill -f aegir.sh
      echo "$(date) TOO MANY (${_AR_C}) aegir.sh required killing mydumper" >> ${_pthOml}
      echo >> ${_pthOml}
      _incident_email_report "TOO MANY (${_AR_C}) aegir.sh required killing mydumper" "mysql-mydumper"
    fi
    if [ "${_DR_C}" -gt "${_MULTI_MX}" ]; then
      pkill -f mydumper
      pkill -f drush.php
      echo "$(date) TOO MANY (${_DR_C}) drush.php required killing mydumper" >> ${_pthOml}
      echo >> ${_pthOml}
      _incident_email_report "TOO MANY (${_DR_C}) drush.php required killing mydumper" "mysql-mydumper"
    fi
  fi
}

_mysql_flush_hosts() {
  if pgrep -f /usr/sbin/mysqld >/dev/null 2>&1 \
    && [ -e "/run/mysqld/mysqld.sock" ] \
    && [ -e "/run/mysqld/mysqld.pid" ]; then
    mysqladmin -u root flush-hosts &> /dev/null
  fi
}

_mysql_is_answering() {
  # Authoritative liveness probe. A reply of ANY kind -- including an auth error
  # -- proves the server is up and accepting connections. `timeout` bounds a hung
  # server; --connect-timeout bounds a dead socket. Uses /root/.my.cnf implicitly.
  local _out
  _out=$(timeout 5 mysqladmin -u root --connect-timeout=2 ping 2>&1)
  case "${_out}" in
    *"is alive"*|*"denied"*|*"Too many connections"*) return 0 ;;
    *) return 1 ;;
  esac
}

_mysql_health_check_fix() {
  # A momentarily missing process/socket/pid is NOT proof of a hard outage:
  # mysqld_safe (the SysV supervisor) respawns an unexpectedly dead mysqld within
  # ~1-2s, during which the socket and pid are legitimately absent. Acting on that
  # self-healing window -- restarting a recovering DB, wiping the cache and bouncing
  # the whole web stack -- is what turned a 1s blip into a 14-minute restart storm.
  # Confirm a genuine outage with the live probe across a short grace; stand down
  # the moment the server answers. Only sustained silence counts as DOWN.
  _mysql_is_answering && return 0
  local _try
  for _try in 1 2 3 4; do
    sleep 3
    _mysql_is_answering && return 0
  done
  _sql_restart "DOWN MySQL"
}

### Main start here

if [ -x "/etc/init.d/mysql" ] \
  && [ -x "/usr/sbin/mysqld" ] \
  && [ ! -e "/run/boa_mysql_auto_healing.pid" ] \
  && [ ! -e "/run/max_load.pid" ] \
  && [ ! -e "/run/critical_load.pid" ] \
  && [ ! -e "/run/mysql_restart_running.pid" ]; then
  _mysql_health_check_fix
fi

if [ -x "/etc/init.d/mysql" ] \
  && pgrep -f /usr/sbin/mysqld >/dev/null 2>&1 \
  && [ ! -e "/run/boa_mysql_auto_healing.pid" ] \
  && [ ! -e "/run/mysql_restart_running.pid" ]; then
  _mysql_high_load
  _sql_busy_detection
  _mysql_flush_hosts
  if (( $(pgrep -fc mydumper) > 0 )) && (( $(pgrep -fc mysql_backup.sh) > 0 )); then
    sleep 5
    _if_mydumper_is_locked
  fi
  nohup /var/xdrago/monitor/check/sqlcheck.sh > /dev/null 2>&1 &
fi

if [ -e "/run/boa_sql_backup.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_mysql_auto_healing.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ]; then
  _SQL_CTRL=NO
else
  _SQL_CTRL=YES
fi

if [ "${_SQL_CTRL}" = "YES" ] \
  && [ ! -e "/run/max_load.pid" ] \
  && [ ! -e "/run/critical_load.pid" ]; then
  for _iteration in {1..3}; do
    _mysql_proc_control "${_SQL_MAX_TTL}"
    sleep 15
  done
fi

echo DONE!
exit 0

