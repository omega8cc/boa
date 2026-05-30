#!/bin/bash

###
### sqlcheck.sh — Fast MySQL crash pre-filter
###
### Runs every minute via mysql.sh. Scans new syslog entries for MySQL table crash
### markers using byte-offset tracking. Invokes checksql.sh only when a problem
### is detected, avoiding the heavy mysqlcheck -Aa cost on clean systems.
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

[ -f "/run/boa_mysql_auto_healing.pid" ] && exit 0

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
    _CNT=$(pgrep -fc ${_SCRIPT})
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

exit 0
