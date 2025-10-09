#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_tasks_maint.cnf" ] && exit 0

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

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_count_cpu() {
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt 0 ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] \
    || [ "${_CPU_NR}" -lt 1 ]; then
    _CPU_NR=1
  fi
}

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

_load_control() {
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  : "${_CPU_TASK_RATIO:=3.1}"
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

# How many hours of binlogs to keep
: "${_BINLOG_KEEP_HOURS:=1}"

_detect_mysql_major() {
  # Returns "5" or "8" for Percona/MySQL variants
  _VER_RAW="$(mysql -Nse "SELECT VERSION();" 2>/dev/null | head -n1)"
  # Examples: 5.7.44-48, 8.0.36-28, 8.4.6-6
  _MYSQL_MAJOR="$(printf '%s' "${_VER_RAW}" | awk -F. '{print $1}')"
  printf '%s' "${_MYSQL_MAJOR:-8}"
}

_purge_binlogs() {
  # Optional safety: skip if binary logging is off
  _LOG_BIN="$(mysql -Nse "SHOW VARIABLES LIKE 'log_bin';" 2>/dev/null | awk '{print $2}')"
  if [ "${_LOG_BIN}" != "ON" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo "log_bin=OFF — nothing to purge"
    fi
    return 0
  fi

  # Compute cutoff as a literal timestamp (local time)
  # For UTC, use: date -u -d "${_BINLOG_KEEP_HOURS} hour ago" '+%F %T'
  _CUTOFF="$(date -d "${_BINLOG_KEEP_HOURS} hour ago" '+%F %T')"

  _MAJOR="$(_detect_mysql_major)"

  if [ "${_MAJOR}" -ge 8 ]; then
    # Percona/MySQL 8.x — needs a literal and 'BINARY'
    _SQL="PURGE BINARY LOGS BEFORE '${_CUTOFF}';"
  else
    # MySQL/Percona 5.7 — still okay to use BINARY + literal (portable),
    # but if we prefer the legacy style, we could keep MASTER/DATE_SUB.
    _SQL="PURGE BINARY LOGS BEFORE '${_CUTOFF}';"
    # Legacy equivalent we had (not used now):
    # _SQL=\"PURGE MASTER LOGS BEFORE DATE_SUB(NOW(), INTERVAL ${_BINLOG_KEEP_HOURS} HOUR);\"
  fi

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    echo "Purging binlogs older than ${_CUTOFF} (keeping ~${_BINLOG_KEEP_HOURS}h)"
    echo "SQL> ${_SQL}"
  fi

  mysql -e "${_SQL}"
}

_purge_action() {
  _count_cpu
  _load_control
  if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
    echo load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}
    _purge_binlogs
    touch /var/log/boa/purge_binlogs.done
  fi
}

if [ -e "/run/boa_wait.pid" ]; then
  touch /var/log/boa/wait-purge.pid
  exit 0
else
  _purge_action
  touch /var/log/boa/last-run-purge
  exit 0
fi

