#!/bin/bash

###
### sqlcheck.sh — Fast MySQL crash pre-filter
###
### Runs every minute via mysql.sh. Keeps root's own sessions out of
### performance_schema's statement summary (_keep_root_out_of_digests).
### Scans new syslog entries for MySQL table crash
### markers using byte-offset tracking. Invokes checksql.sh only when a problem
### is detected, avoiding the heavy mysqlcheck -Aa cost on clean systems.
### Then measures the optimizer statistics of large tables that still read as
### empty long after they were loaded (_heal_stale_stats).
###

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_CHECKSQL="/var/xdrago/checksql.sh"
_CLEAN_TOUCH="/var/log/boa/last-sqlcheck-clean"
_PROBLEM_LOG="/var/log/boa/last-sqlcheck-y-problem"
_SQL_LOG_BASELINE=999

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

###
### Keep root's own sessions out of performance_schema's statement summary.
###
### The summary holds one row per statement shape and schema in a table of
### fixed size (10,000 rows by default, allocated at server start). A dump
### reads each table with a few statements of its own, about four rows a
### table, so on a server with thousands of tables the nightly dump fills
### the summary within days and the sites' own statements are no longer
### counted. Every BOA dump and migration export connects as root, so root's
### sessions are left uninstrumented and every other user is counted as
### before. The rule lives in memory only: it is set again on the first pass
### after a server start, before the stand-down markers below, because a
### backup started right after a restart is the session it is for. An
### operator's own row for root is left as it is. performance_schema is off
### on 5.7 (BOA's my.cnf), and nothing runs there.
###
_keep_root_out_of_digests() {
  [ -e "/root/.proxy.cnf" ] && return 0
  command -v mysql >/dev/null 2>&1 || return 0
  local _st
  _st=$(timeout 10 mysql -N -B -e "SELECT @@GLOBAL.performance_schema, (SELECT COUNT(*) FROM performance_schema.setup_actors WHERE HOST = '%' AND USER = 'root' AND ROLE = '%')" 2>/dev/null) || return 0
  [ "${_st}" = $'1\t0' ] || return 0
  timeout 10 mysql -N -B -e "INSERT INTO performance_schema.setup_actors (HOST, USER, ROLE, ENABLED, HISTORY) VALUES ('%', 'root', '%', 'NO', 'NO')" &> /dev/null
  return 0
}
_keep_root_out_of_digests

# Stand down while the database is already being worked on. A full-server
# mysqlcheck taken while a backup holds its locks, or while the watchdog is
# restarting the server, competes for the same tables and can turn a slow
# window into a stuck one. A crashed table is not urgent: the next pass picks
# it up as soon as the window closes, and these markers are age-reaped, so a
# operation that died cannot hold this off indefinitely.
for _m in /run/boa_sql_backup.pid /run/boa_sql_cluster_backup.pid \
          /run/boa_sql_maintenance.pid /run/boa_mysql_auto_healing.pid \
          /run/mysql_restart_running.pid; do
  [ -e "${_m}" ] && exit 0
done

###
### Detect which log file MySQL actually writes to on this system.
### daemon.log is preferred when present and confirmed to contain MySQL entries;
### syslog is the fallback. The offset file is keyed to the selected log so
### that systems using different files maintain independent position tracking.
###
_detect_sql_log() {
  _SQL_LOG="/var/log/syslog"
  if [ -e "/var/log/daemon.log" ] && \
     tail -n 1000 /var/log/daemon.log 2>/dev/null | grep -qi mysql; then
    _SQL_LOG="/var/log/daemon.log"
  fi
  _SQL_LOG_OFFSET_FILE="/var/log/scan_sqlcheck_$(basename "${_SQL_LOG}")_lastpos"
}
_detect_sql_log

export _B_NICE=${_B_NICE//[^0-9-]/}
if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
  _B_NICE=0
fi
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
    _single_instance_lock
  else
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc "(^|(^| )[^ ]*bash )[^ ]*/${_SCRIPT//./\\.}( |$)")
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

_STATUS="CLEAN"

_makeactions() {
  local _last_offset=0
  if [[ -f "${_SQL_LOG_OFFSET_FILE}" ]]; then
    _last_offset=$(< "${_SQL_LOG_OFFSET_FILE}")
  fi

  local _current_size=0
  if [[ -f "${_SQL_LOG}" ]]; then
    _current_size=$(stat -c %s "${_SQL_LOG}")
  fi

  # Reset on log rotation or truncation
  if (( _current_size < _last_offset )); then
    _last_offset=0
  fi

  if (( _last_offset == 0 )); then
    exec 3< <(tail -n "${_SQL_LOG_BASELINE}" "${_SQL_LOG}" 2>/dev/null | grep -i mysql)
  else
    exec 3< <(tail -c +$(( _last_offset + 1 )) "${_SQL_LOG}" 2>/dev/null | grep -i mysql)
  fi

  local _line
  while IFS= read -r _line <&3; do
    _line="${_line//[^a-zA-Z0-9: 	\/@_()*/.,\[\]-]/}"
    if [[ "${_line}" =~ [Cc]hecking\ table || "${_line}" =~ is\ marked\ as\ crashed ]]; then
      _STATUS="ERROR"
      printf '[%s]:[%s]\n' "$(date +%y%m%d-%H%M%S)" "${_line}" >> "${_PROBLEM_LOG}"
    fi
  done
  exec 3<&-

  if [[ -f "${_SQL_LOG}" ]]; then
    stat -c %s "${_SQL_LOG}" > "${_SQL_LOG_OFFSET_FILE}"
  fi
}

_makeactions

if [ "${_STATUS}" != "CLEAN" ]; then
  [ -x "${_CHECKSQL}" ] && bash "${_CHECKSQL}"
else
  touch "${_CLEAN_TOUCH}"
fi

###
### Measure the optimizer statistics of large tables that still read as empty.
###
### InnoDB gives a new table the statistics of an empty one, and a bulk load
### can leave them claiming a single page while the file holds millions of
### rows. Only a background queue measures the pages, and once nothing new
### wakes it, it takes one table about every ten seconds: after a run of
### migrations a large site went live while its tables still read as one page
### each, its pages were planned as full table scans, and the database server
### ran out of CPU. Provision measures the databases it imports; this catches
### every other load (a migration tool, a dump loaded by hand). A table
### qualifies when its statistics claim at most one page, its file holds more
### than 8 MB and it was created over 5 minutes ago (a load still running is
### left alone). A table measured here is left alone for a day: one that
### really is that small (rows deleted, the file never shrunk) keeps
### qualifying. Never on a replica (a local write there is an errant
### transaction) or a proxy-only box. Needs the 8.0+ tablespace view; on 5.7
### the read fails and nothing runs.
###
_pthOml="/var/log/boa/sqlstats.incident.log"
_pthStats="/var/log/boa/sqlstats.measured"

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

# A table still unmeasured after its heal is heard at the default level
# (MINI); a heal that worked only at ALL.
_stats_mail() {
  local _lvl="${1}" _subject="${2}"
  [ -n "${_MY_EMAIL}" ] || return 0
  _normalize_incident_report
  case "${_INCIDENT_REPORT}" in
    OFF|CRIT) return 0 ;;
    MINI) [ "${_lvl}" = "ALERT" ] || return 0 ;;
  esac
  _sfx=""
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    _incident_email_ratelimit "sql-stats" || return 0
    if [ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]; then
      _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
    fi
  fi
  _hName="$(tr -d '\n' < /etc/hostname 2>/dev/null)"
  [ -n "${_hName}" ] || _hName="$(hostname -f 2>/dev/null)"
  echo "Sending Incident Report Email on $(date)" >> "${_pthOml}"
  s-nail -s "Incident Report: ${_subject}${_sfx} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_pthOml}")
}

_heal_stale_stats() {
  [ -e "/root/.proxy.cnf" ] && return 0
  [ -e "/root/.standby.cnf" ] && return 0
  command -v mysql >/dev/null 2>&1 || return 0
  local _q _rows _now _key _ts _db _tb _mb _list _count _out _old _changed
  local _ok _bad _n_ok _n_bad
  local -A _seen=() _done=()
  _now=$(date +%s)
  # The tables measured here in the last day, as "db.table<TAB>epoch" lines.
  _old=0
  if [ -s "${_pthStats}" ]; then
    while IFS=$'\t' read -r _key _ts; do
      if [[ "${_ts}" =~ ^[0-9]+$ ]] && (( _now - _ts < 86400 )); then
        _seen["${_key}"]="${_ts}"
      else
        _old=$(( _old + 1 ))
      fi
    done < "${_pthStats}"
  fi
  _q="SELECT s.database_name, s.table_name, ROUND(ts.FILE_SIZE / 1048576)
    FROM mysql.innodb_table_stats s
    JOIN information_schema.INNODB_TABLESPACES ts
      ON ts.NAME = CONCAT(s.database_name, '/', s.table_name)
    JOIN information_schema.TABLES t
      ON t.TABLE_SCHEMA = s.database_name AND t.TABLE_NAME = s.table_name
    WHERE s.clustered_index_size <= 1
      AND ts.FILE_SIZE > 8388608
      AND t.CREATE_TIME < NOW() - INTERVAL 5 MINUTE
    ORDER BY ts.FILE_SIZE DESC
    LIMIT 1000"
  _rows=$(timeout 60 mysql -N -B -e "${_q}" 2>/dev/null) || return 0
  _list=""
  _count=0
  while IFS=$'\t' read -r _db _tb _mb; do
    [ -n "${_db}" ] || continue
    # Plain names only: anything else is never spliced into a statement.
    if [[ ! "${_db}" =~ ^[A-Za-z0-9_]+$ ]] || [[ ! "${_tb}" =~ ^[A-Za-z0-9_]+$ ]]; then
      continue
    fi
    [ -n "${_seen["${_db}.${_tb}"]}" ] && continue
    (( _count < 200 )) || break
    _done["${_db}.${_tb}"]="${_mb}"
    _list="${_list}${_list:+, }\`${_db}\`.\`${_tb}\`"
    _count=$(( _count + 1 ))
  done <<< "${_rows}"
  _changed="${_old}"
  _ok=""
  _bad=""
  _n_ok=0
  _n_bad=0
  if (( _count > 0 )); then
    _out=$(timeout 300 mysql -N -B -e "SET SESSION lock_wait_timeout = 30; ANALYZE TABLE ${_list}" 2>&1)
    # The outcome, not the exit code: each table answers with its own OK.
    for _key in "${!_done[@]}"; do
      if grep -qxF "${_key}"$'\tanalyze\tstatus\tOK' <<< "${_out}"; then
        _seen["${_key}"]="${_now}"
        _n_ok=$(( _n_ok + 1 ))
        (( _n_ok <= 10 )) && _ok="${_ok}${_ok:+, }${_key} (${_done["${_key}"]} MB)"
      else
        _n_bad=$(( _n_bad + 1 ))
        (( _n_bad <= 10 )) && _bad="${_bad}${_bad:+, }${_key} (${_done["${_key}"]} MB)"
      fi
    done
    _changed=$(( _changed + _n_ok ))
  fi
  if (( _changed > 0 )); then
    for _key in "${!_seen[@]}"; do
      printf '%s\t%s\n' "${_key}" "${_seen["${_key}"]}"
    done > "${_pthStats}.tmp" && mv -f "${_pthStats}.tmp" "${_pthStats}"
  fi
  (( _n_ok > 10 )) && _ok="${_ok} and $(( _n_ok - 10 )) more"
  (( _n_bad > 10 )) && _bad="${_bad} and $(( _n_bad - 10 )) more"
  if (( _n_ok > 0 )); then
    echo "$(date) INFO: measured the optimizer statistics of ${_n_ok} large table(s) that still read as one page: ${_ok}" >> "${_pthOml}"
  fi
  if (( _n_bad > 0 )); then
    echo "$(date) ALERT: could not measure the optimizer statistics of ${_n_bad} large table(s) that still read as one page: ${_bad}" >> "${_pthOml}"
    echo "$(date) ALERT: $(grep -i -m 3 -E 'error|timeout' <<< "${_out}" | tr '\n\t' '  ')" >> "${_pthOml}"
    _stats_mail ALERT "Table statistics could not be measured"
  elif (( _n_ok > 0 )); then
    _stats_mail INFO "Measured the statistics of ${_n_ok} large table(s) that read as one page"
  fi
}

_heal_stale_stats

exit 0
