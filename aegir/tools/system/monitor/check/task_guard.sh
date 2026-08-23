#!/bin/bash
#
# BOA crashed-task reaper — task_guard v1.0.
#
# Heals hosting_task rows orphaned at PROCESSING (-1). The final task status
# is written ONLY by the task runner's own PHP shutdown handler, so a runner
# killed without reaching it (host reboot, a killed octopus/barracuda upgrade
# swapping the live code trees under its own dispatched tasks, a signal) leaves
# its current revision at -1 forever. hosting_task_count_running() counts such
# rows as running for a full 8h window and the dispatcher subtracts them from
# its concurrency budget, so at the default single-task limit ONE corpse wedges
# the instance's whole queue ("Maximum number of tasks (N) already running"
# every minute) and hosting-pause spins on it without a timeout — an observed
# wedge held a couple of hundred queued tasks behind a batch of verifies killed
# by an interrupted upgrade. The code comment above that window says crashed-
# task recovery must be DECOUPLED from the live cap; this watchdog is that
# decoupled reaper.
#
# Current hosting releases also reap these rows themselves on every dispatch
# pass (the runner stamps its PID on the row and the dispatcher checks /proc).
# This watchdog deliberately does NOT depend on that: hosting code reaches a
# box only with a newly built hostmaster platform, while this file is delivered
# fleet-wide anytime, works on every deployed hostmaster vintage, needs no pid
# column, and keeps working even when the instance's own drush tree is broken
# mid-swap — the very failure that mints the corpses. Where both run, the
# per-vid conditional update makes them coexist: whoever reaps first wins and
# the other side no-ops.
#
# THE FALSE-POSITIVE RULE IS ABSOLUTE: marking a live task failed is worse
# than the wedge. The evidence is the process table, not timestamps alone:
#
#   1. Only CURRENT-revision -1 rows count (join on node.vid — superseded
#      revisions stay -1 forever by design and are invisible to the
#      dispatcher, so they are none of our business).
#   2. The row must be older than the grace window (a task flips to -1 the
#      second its runner starts, so a fresh row always has a live runner).
#   3. BOA executes an instance's tasks only as the instance's own user
#      (su-spawned; the master queue runs as aegir), so the row is judged
#      dead only when that user has NO live task runner AND NO live
#      provision backend. One live runner holds the ENTIRE instance for
#      this pass — with coarse per-user evidence we never guess which row
#      a process belongs to. A held corpse heals a few minutes later, and
#      the failure direction is a delayed heal, never a killed live task.
#   4. The reset is per-vid and CONDITIONAL on the row still being -1, so a
#      concurrent status writer (a patched dispatcher's own reaper, the
#      manual button) always wins and this side no-ops.
#
# Reaped rows become HOSTING_TASK_ERROR (2) — the truthful outcome for a
# killed run — with an explicit hosting_task_log row naming this watchdog,
# never "Successful"; nothing is re-run (a crashed migrate/clone must never
# be re-fired blind). The queue then dispatches on its own next minute.
#
# The mysqld gates mirror the sibling monitors: stand down while a live
# barracuda run could restart mysqld under us and while a SQL maintenance
# marker is fresh. A live OCTOPUS run is deliberately NOT a stand-down: its
# tree swap is what kills tasks in the first place, and on stock hostmaster
# bytes the upgrade itself then spins on the corpses in hosting-pause — a
# reap during the run is exactly what un-wedges it. Barracuda stand-down is
# process-anchored, never marker-only: a killed run leaves a stale
# /run/boa_run.pid behind, and a marker gate would park this watchdog
# forever on precisely the incident it exists to heal.
#
# Opt-outs (all overridable in /root/.barracuda.cnf):
#   _USE_TASK_GUARD=NO           fully off (unset means ON)
#   _TASK_GUARD_DETECT_ONLY=YES  full detection, log + alert, zero writes
#   _TASK_GUARD_GRACE_MINS=10    minimum -1 row age before it can be judged
#
# Operator validation (--force only skips the self-throttle; --detect-only
# is the true dry run and beats any cnf line):
#
#   bash task_guard.sh --force --stdout --detect-only
#
# Conventions: BOA monitor sibling (cf. batch_guard.sh / mysql.sh). No systemd.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthDat="/var/log/boa/task_guard"
_STAMP="${_pthDat}/.last_run"
_pthOml="/var/log/boa/task_guard.incident.log"

_FORCE=NO
_STDOUT=NO
_CLI_DETECT_ONLY=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)       _FORCE=YES ;;
    --stdout)      _STDOUT=YES ;;
    --detect-only) _CLI_DETECT_ONLY=YES ;;
    -h|--help) echo "Usage: task_guard.sh [--force] [--stdout] [--detect-only]"; exit 0 ;;
    *) echo "Unknown argument: ${_arg}" >&2; exit 2 ;;
  esac
done

_say() { [ "${_STDOUT}" = "YES" ] && echo "$@"; }

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

# Run only on a fully installed system (same guard the sibling monitors use).
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# A replication standby's hosting_task rows arrive by replication — never
# write into the replica. The read-only diagnostic mode stays available.
if [ -e "/root/.standby.cnf" ] && [ "${_CLI_DETECT_ONLY}" != "YES" ]; then
  exit 0
fi

# A finalized PX0 proxy runs no task queue (runner.sh parks it on the same
# marker) — nothing here to reap.
[ -e "/root/.proxy.cnf" ] && exit 0

# Opt-out: fully off when the operator says so (unset means ON).
[ "${_USE_TASK_GUARD}" = "NO" ] && exit 0

# Major system transition in flight: stand down.
for _rt in excalibur daedalus chimaera beowulf; do
  [ -e "/root/.run-to-${_rt}.cnf" ] && exit 0
done

# Live barracuda run: it may restart mysqld under us. Process-anchored on
# purpose (see the header) — the launcher and the fetched-copy leg, the same
# arms runner.sh trusts. A stale /run/boa_run.pid alone never parks us.
if pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/barracuda( |$)" > /dev/null 2>&1 \
  || pgrep -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/BARRACUDA\.sh\.txt" > /dev/null 2>&1; then
  _say "STAND-DOWN reason=barracuda-run"
  exit 0
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

mkdir -p "${_pthDat}"

# Self-throttle to ~5 min (minute.sh relaunches us every minute), unless
# --force. With the grace below, a corpse heals within one tick plus its
# grace — minutes against the 8h the dispatch window would take.
if [ "${_FORCE}" != "YES" ] && [ -e "${_STAMP}" ] \
  && [ -z "$(find "${_STAMP}" -mmin +4 2>/dev/null)" ]; then
  exit 0
fi
touch "${_STAMP}"

###
### Knobs. The normaliser mirrors lock.inc's _flap_num (digits only, leading
### zeros stripped) and is kept in-file so knob arithmetic never depends on
### which lock.inc a box happens to hold.
###
_tg_num() {
  local _v="${1//[^0-9]/}"
  while [ "${#_v}" -gt 1 ] && [ "${_v:0:1}" = "0" ]; do
    _v="${_v:1}"
  done
  [ -n "${_v}" ] || _v="$2"
  printf '%s' "${_v}"
}

# The CLI flag wins over the cnf, deliberately and in one direction only —
# an operator asking for a dry run must GET a dry run.
_TASK_GUARD_DETECT_ONLY="${_TASK_GUARD_DETECT_ONLY^^}"
_TASK_GUARD_DETECT_ONLY="${_TASK_GUARD_DETECT_ONLY//[^A-Z]/}"
[ "${_CLI_DETECT_ONLY}" = "YES" ] && _TASK_GUARD_DETECT_ONLY=YES

# Minimum -1 row age before it can be judged. A runner stamps -1 the second
# it starts, so any genuinely fresh row still has its runner alive and the
# process check below is the real gate; the grace only keeps us clear of
# start-up races. The floor is 3 minutes — below that the grace stops
# meaning anything against process churn.
_TASK_GUARD_GRACE_MINS=$(_tg_num "${_TASK_GUARD_GRACE_MINS}" 10)
[ "${_TASK_GUARD_GRACE_MINS}" -lt 3 ] && _TASK_GUARD_GRACE_MINS=3
_GRACE_SECS=$(( _TASK_GUARD_GRACE_MINS * 60 ))

###
### Load + normalize _INCIDENT_REPORT
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
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_incident_email_report() {
  # A reap means tasks in a client-visible queue were marked failed — the
  # default reporting level hears about that (MINI); this guard has no
  # ALERT tier of its own. Uptime grace + ratelimit are command -v guarded:
  # a box holding a new task_guard.sh against an older lock.inc still mails.
  if command -v _check_uptime_grace_period >/dev/null 2>&1 \
    && ! _check_uptime_grace_period >/dev/null; then
    return 1
  fi
  local _subject="${1:-(no subject)}"
  local _lvl="${2:-MINI}"
  _lvl="${_lvl^^}"
  [ -n "${_MY_EMAIL}" ] || return 1
  case "${_INCIDENT_REPORT}" in
    OFF)  return 1 ;;
    CRIT) [ "${_lvl}" = "ALERT" ] || return 1 ;;
    MINI) [ "${_lvl}" = "ALERT" ] || [ "${_lvl}" = "MINI" ] || return 1 ;;
    ALL)  : ;;
  esac
  local _sfx=""
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    if ! _incident_email_ratelimit "task-guard"; then
      echo "$(date) INFO: alert for '${_subject}' held back, one was already sent this cooldown" >> ${_pthOml}
      return 1
    fi
    if [ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]; then
      _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
    fi
  fi
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
  s-nail -s "Incident Report: ${_subject}${_sfx} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_pthOml}")
}

# Once-a-day WARN classes, so a persistently unparseable instance cannot
# flood the incident log every tick.
_warn_daily() {
  local _slug="$1" _msg="$2"
  if [ -z "$(find "${_pthDat}/.warned_${_slug}" -mmin -1440 2>/dev/null)" ]; then
    echo "$(date) ${_msg}" >> ${_pthOml}
    touch "${_pthDat}/.warned_${_slug}"
  fi
}

# mysqld must be answering: the probe and the heal are both SQL, and
# database downtime is mysql.sh's business, not ours.
if [ ! -S "/run/mysqld/mysqld.sock" ] && [ ! -S "/var/run/mysqld/mysqld.sock" ]; then
  exit 0
fi

# DB-mutation stand-down (the shared family gate): while move_sql.sh or the
# database watchdog holds a restart in flight, our conditional updates would
# race the restart. A marker older than the bound is a leak (clear.sh reaps
# those), not a live mutation, and is ignored.
_SQL_MUTATION_MAX_MINS="${_SQL_MUTATION_MAX_MINS//[^0-9]/}"
[ -n "${_SQL_MUTATION_MAX_MINS}" ] || _SQL_MUTATION_MAX_MINS=15
for _mk in /run/mysql_restart_running.pid /run/boa_mysql_auto_healing.pid; do
  if [ -e "${_mk}" ] \
    && [ -z "$(find "${_mk}" -mmin "+${_SQL_MUTATION_MAX_MINS}" 2>/dev/null)" ]; then
    _say "STAND-DOWN marker=${_mk}"
    exit 0
  fi
done

_is_safe_ident() {
  [[ "${1}" =~ ^[A-Za-z0-9_]+$ ]]
}

# The hostmaster db for an instance, from the same chain the operator tools
# trust: hostmaster alias -> site_path -> the site's own drushrc.php. No
# drush bootstrap — the whole point is to keep working when the instance's
# drush tree is broken mid-swap. The db name survives platform migrations,
# so even an alias caught mid-upgrade still names the right database.
_hm_db_for_alias() {
  local _alias="$1" _dir _dbn
  _dir=$(grep "site_path'" "${_alias}" 2>/dev/null \
    | awk '{ print $3}' \
    | sed "s/[\,']//g")
  [ -n "${_dir}" ] && [ -e "${_dir}/drushrc.php" ] || return 1
  _dbn=$(grep "options\['db_name'\] = " "${_dir}/drushrc.php" 2>/dev/null \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g")
  [ -n "${_dbn}" ] || return 1
  printf '%s' "${_dbn}"
  return 0
}

# Whether the instance user still has a live task runner or provision
# backend. Patterns mirror the shared _provision_running arms: ( |$) after
# hosting-task is LOAD-BEARING — without it the per-minute hosting-tasks /
# hosting-dispatch pollers would match and hold every instance forever.
# The -u filter is the attribution: BOA spawns every task execution as the
# instance's own user, and it also keeps this watchdog's own command line
# out of the match by construction.
_instance_tasks_alive() {
  local _u="$1"
  pgrep -u "${_u}" -f "hosting-task( |$)" > /dev/null 2>&1 && return 0
  pgrep -u "${_u}" -f "provision-[a-z]" > /dev/null 2>&1 && return 0
  return 1
}

_REAPED_TOTAL=0
_HELD_TOTAL=0

_reap_instance() {
  local _u="$1" _alias="$2" _dbn _n _rows _vid _nid _age _upd
  [ -e "${_alias}" ] || return 0
  if ! _dbn=$(_hm_db_for_alias "${_alias}"); then
    _warn_daily "nodb_${_u}" "WARN: cannot resolve the hostmaster db for ${_u}; instance skipped (latched for a day)"
    _say "SKIP user=${_u} reason=no-db"
    return 0
  fi
  if ! _is_safe_ident "${_dbn}"; then
    _warn_daily "unsafe_${_u}" "WARN: unsafe hostmaster db identifier for ${_u}; instance skipped (latched for a day)"
    _say "SKIP user=${_u} reason=unsafe-ident"
    return 0
  fi
  _n=$(timeout 10 mysql -u root -Nse \
    "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '${_dbn}' AND TABLE_NAME = 'hosting_task'" 2>/dev/null)
  if [ "$(_tg_num "${_n}" 0)" -eq 0 ]; then
    _say "SKIP user=${_u} db=${_dbn} reason=no-hosting-task-table"
    return 0
  fi
  # Current-revision PROCESSING rows past the grace. Superseded revisions
  # are excluded by the node.vid join — they stay -1 by design.
  _rows=$(timeout 10 mysql -u root -Nse \
    "SELECT t.vid, t.nid, (UNIX_TIMESTAMP() - t.executed) FROM \`${_dbn}\`.hosting_task t INNER JOIN \`${_dbn}\`.node n ON t.vid = n.vid WHERE n.type = 'task' AND t.task_status = -1 AND t.executed < (UNIX_TIMESTAMP() - ${_GRACE_SECS})" 2>/dev/null)
  [ -n "${_rows}" ] || return 0
  # The process check runs AFTER the row scan on purpose: a runner that
  # dies between the two reads is dead either way, and one that starts
  # between them can only make us hold — the safe direction.
  if _instance_tasks_alive "${_u}"; then
    _HELD_TOTAL=$(( _HELD_TOTAL + $(printf '%s\n' "${_rows}" | wc -l | tr -dc '0-9') ))
    _say "HELD user=${_u} db=${_dbn} reason=live-task-process"
    return 0
  fi
  while read -r _vid _nid _age; do
    [[ "${_vid}" =~ ^[0-9]+$ ]] || continue
    [[ "${_nid}" =~ ^[0-9]+$ ]] || continue
    _age=$(_tg_num "${_age}" 0)
    if [ "${_TASK_GUARD_DETECT_ONLY}" = "YES" ]; then
      echo "$(date) DETECT-ONLY: would mark orphaned task node/${_nid} revision ${_vid} failed in db ${_dbn} [${_u}] (stuck PROCESSING for ${_age}s, no live runner)" >> ${_pthOml}
      _say "DETECT-ONLY user=${_u} db=${_dbn} nid=${_nid} vid=${_vid} age=${_age}"
      _REAPED_TOTAL=$(( _REAPED_TOTAL + 1 ))
      continue
    fi
    # Conditional on the row still being -1: any concurrent status writer
    # (a patched dispatcher's reaper, the manual button) wins and we no-op.
    _upd=$(timeout 10 mysql -u root -Nse \
      "UPDATE \`${_dbn}\`.hosting_task t INNER JOIN \`${_dbn}\`.node n ON t.vid = n.vid SET t.task_status = 2 WHERE t.vid = ${_vid} AND n.type = 'task' AND t.task_status = -1; SELECT ROW_COUNT();" 2>/dev/null)
    _upd=$(_tg_num "${_upd}" 0)
    if [ "${_upd}" -lt 1 ]; then
      _say "SKIPPED user=${_u} db=${_dbn} vid=${_vid} reason=changed-since-scan"
      continue
    fi
    # The truthful record in the panel, mirroring what the in-frontend
    # reaper writes; lid is auto-increment.
    timeout 10 mysql -u root -Nse \
      "INSERT INTO \`${_dbn}\`.hosting_task_log (vid, nid, type, message, error, timestamp) VALUES (${_vid}, ${_nid}, 'error', 'Task runner process is gone without reporting a final status; marked failed by the BOA task_guard watchdog.', '', UNIX_TIMESTAMP())" &> /dev/null
    echo "$(date) REAPED: orphaned task node/${_nid} revision ${_vid} in db ${_dbn} [${_u}] marked failed (stuck PROCESSING for ${_age}s, no live runner)" >> ${_pthOml}
    _say "REAPED user=${_u} db=${_dbn} nid=${_nid} vid=${_vid} age=${_age}"
    _REAPED_TOTAL=$(( _REAPED_TOTAL + 1 ))
  done <<< "${_rows}"
}

# Every Octopus instance, then the master queue. The alias file is the
# discriminator for "this is an Aegir instance" — bare dirs are skipped.
for _d in /data/disk/*; do
  [ -d "${_d}" ] || continue
  _u=$(basename "${_d}")
  _reap_instance "${_u}" "${_d}/.drush/hostmaster.alias.drushrc.php"
done
_reap_instance "aegir" "/var/aegir/.drush/hm.alias.drushrc.php"

if [ "${_REAPED_TOTAL}" -gt 0 ]; then
  if [ "${_TASK_GUARD_DETECT_ONLY}" = "YES" ]; then
    _incident_email_report "Orphaned tasks confirmed: ${_REAPED_TOTAL} stuck PROCESSING (detect-only, nothing changed)" "MINI"
  else
    _incident_email_report "Orphaned tasks reaped: ${_REAPED_TOTAL} stuck PROCESSING marked failed" "MINI"
  fi
  echo >> ${_pthOml}
fi
_say "DONE reaped=${_REAPED_TOTAL} held=${_HELD_TOTAL}"

exit 0
