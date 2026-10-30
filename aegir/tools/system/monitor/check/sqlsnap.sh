#!/bin/bash
#
# Save what MySQL and the box are doing when a load or database incident
# starts, once per cooldown, so the cause can still be named afterwards.
#
# A database stall leaves nothing behind on its own: the slow log and
# performance_schema are usually off, and the queries that waited are gone
# by the time anyone looks. One observed stall held InnoDB's dictionary for
# eight minutes while the load stayed low (the waiting queries sleep), then
# released a backlog that drove the load past the critical tier; nothing on
# the box could say which thread had held it. second.sh calls this when a
# load tier fires, ahead of any kill or pause; mysql.sh calls it when many
# queries have been running long at once, the shape of such a stall while
# it is still there.
#
# Read-only on the database. Every client call is time-bounded, so a server
# that does not answer costs seconds, never a hung capture. The files hold
# queries and command lines: root only, mode 600, under /var/log/boa/incident.
#
# Usage: sqlsnap.sh <reason> [/var/log/boa/<name>.incident.log]
# Off with _INCIDENT_SNAPSHOT=NO in /root/.barracuda.cnf.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_SNAP_ROOT="/var/log/boa/incident"
_SNAP_LAST="/run/boa_sqlsnap.last"

# shellcheck disable=SC1091
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf

_INCIDENT_SNAPSHOT="${_INCIDENT_SNAPSHOT^^}"
[ "${_INCIDENT_SNAPSHOT}" = "NO" ] && exit 0

# Minutes between two snapshots: an incident that flaps between tiers, or
# trips both callers, writes one set.
_SQLSNAP_COOLDOWN_MINS="${_SQLSNAP_COOLDOWN_MINS//[^0-9]/}"
_SQLSNAP_COOLDOWN_MINS="${_SQLSNAP_COOLDOWN_MINS:0:4}"
: "${_SQLSNAP_COOLDOWN_MINS:=15}"
_SQLSNAP_COOLDOWN_MINS=$(( 10#${_SQLSNAP_COOLDOWN_MINS} ))
(( _SQLSNAP_COOLDOWN_MINS < 1 )) && _SQLSNAP_COOLDOWN_MINS=1
# Days a snapshot is kept, and the most kept at once whatever their age.
_SQLSNAP_KEEP_DAYS="${_SQLSNAP_KEEP_DAYS//[^0-9]/}"
_SQLSNAP_KEEP_DAYS="${_SQLSNAP_KEEP_DAYS:0:4}"
: "${_SQLSNAP_KEEP_DAYS:=14}"
_SQLSNAP_KEEP_DAYS=$(( 10#${_SQLSNAP_KEEP_DAYS} ))
(( _SQLSNAP_KEEP_DAYS < 1 )) && _SQLSNAP_KEEP_DAYS=1
_SQLSNAP_KEEP_MAX=200

_REASON="${1//[^a-zA-Z0-9.-]/}"
_REASON="${_REASON:0:40}"
[ -n "${_REASON}" ] || _REASON="manual"

# The incident log the caller mails from; the line naming the snapshot goes
# there, so the mail that follows carries it.
_pthOml="/var/log/boa/high.load.incident.log"
[[ "${2:-}" =~ ^/var/log/boa/[a-z0-9_.-]+\.incident\.log$ ]] && _pthOml="${2}"

for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
  [ -r "${_L}" ] && . "${_L}" && break
done
_SELF_NAME="sqlsnap.sh"
if command -v _single_instance_lock >/dev/null 2>&1; then
  _single_instance_lock
elif ! mkdir /run/sqlsnap.lock 2>/dev/null; then
  exit 0
else
  trap 'rm -rf /run/sqlsnap.lock' EXIT
fi

# Checked under the lock, so two callers in the same second write one set.
if [ -e "${_SNAP_LAST}" ] \
  && [ -z "$(find "${_SNAP_LAST}" -mmin "+${_SQLSNAP_COOLDOWN_MINS}" 2>/dev/null)" ]; then
  exit 0
fi

# Only a real directory takes the files.
if [ -L "${_SNAP_ROOT}" ] || { [ -e "${_SNAP_ROOT}" ] && [ ! -d "${_SNAP_ROOT}" ]; }; then
  echo "$(date) INFO: incident snapshot (${_REASON}) not saved: ${_SNAP_ROOT} is not a directory" >> "${_pthOml}"
  exit 1
fi
umask 077
mkdir -p "${_SNAP_ROOT}" || exit 1
chown root:root "${_SNAP_ROOT}" 2>/dev/null
chmod 700 "${_SNAP_ROOT}" 2>/dev/null

_DIR="${_SNAP_ROOT}/$(date +%Y%m%d-%H%M%S)-${_REASON}"
mkdir "${_DIR}" 2>/dev/null || exit 1
touch "${_SNAP_LAST}"
echo "$(date) INFO: incident snapshot (${_REASON}) saved to ${_DIR}" >> "${_pthOml}"

# One bounded client call; its output and exit status go to the file named.
_sql_to() {
  local _file="$1" _secs="$2" _rc
  shift 2
  timeout "${_secs}" mysql --connect-timeout=3 "$@" > "${_DIR}/${_file}" 2>&1
  _rc=$?
  [ "${_rc}" -eq 0 ] || echo "(client exit ${_rc}; 124 means no answer within ${_secs} s)" >> "${_DIR}/${_file}"
  return "${_rc}"
}

# The database first: the queries waiting now are the evidence, and the
# caller may stop web processes moments later.
_sql_to processlist.txt 10 -e "SHOW FULL PROCESSLIST"
_sql_to innodb_status.txt 15 -e "SHOW ENGINE INNODB STATUS\G"
if [ "$(timeout 5 mysql --connect-timeout=3 -N -e "SELECT @@performance_schema" 2>/dev/null | tr -dc '0-9')" = "1" ]; then
  # Metadata lock holders and waiters by connection id; empty when the
  # instrument is off.
  _sql_to metadata_locks.txt 10 -e "SELECT t.PROCESSLIST_ID, m.LOCK_STATUS, m.LOCK_TYPE, m.LOCK_DURATION, m.OBJECT_TYPE, m.OBJECT_SCHEMA, m.OBJECT_NAME FROM performance_schema.metadata_locks m LEFT JOIN performance_schema.threads t ON t.THREAD_ID = m.OWNER_THREAD_ID WHERE m.OBJECT_TYPE NOT IN ('TABLESPACE', 'BACKUP LOCK') ORDER BY m.LOCK_STATUS, t.PROCESSLIST_ID LIMIT 2000"
fi

{
  echo "reason: ${_REASON}"
  echo "date: $(date)"
  echo "host: $(cat /etc/hostname 2>/dev/null)"
  echo "uptime: $(uptime)"
  echo "loadavg: $(cat /proc/loadavg 2>/dev/null)"
  echo "cpus: $(nproc 2>/dev/null)"
  grep -E "^procs_(running|blocked) " /proc/stat 2>/dev/null
  for _p in cpu io memory; do
    [ -r "/proc/pressure/${_p}" ] && sed "s/^/pressure ${_p} /" "/proc/pressure/${_p}"
  done
  echo
  free -m 2>/dev/null
} > "${_DIR}/box.txt" 2>&1

{
  # Every thread running or in uninterruptible wait, then mysqld's threads
  # by state and kernel wait, then PHP-FPM children per pool.
  echo "### threads in R or D state: state pid tid elapsed_s wchan comm args"
  timeout 10 ps -eLo state=,pid=,tid=,etimes=,wchan:32=,comm=,args= 2>/dev/null \
    | awk '$1 ~ /^[RD]/' | head -n 2000
  _MY_PID="$(pidof -s mysqld 2>/dev/null)"
  if [ -n "${_MY_PID}" ]; then
    echo
    echo "### mysqld ${_MY_PID} threads: count state wchan comm"
    timeout 10 ps -L -o state=,wchan:32=,comm= -p "${_MY_PID}" 2>/dev/null \
      | sort | uniq -c | sort -rn | head -n 200
  fi
  echo
  echo "### php-fpm children per pool"
  timeout 10 ps -eo args= 2>/dev/null | awk '/^php-fpm: pool /{print $3}' \
    | sort | uniq -c | sort -rn
} > "${_DIR}/processes.txt" 2>&1

chmod 600 "${_DIR}"/* 2>/dev/null

# Prune by age, then by count, oldest first; only names this script writes.
find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9][0-1][0-9][0-3][0-9]-*' \
  -mtime "+${_SQLSNAP_KEEP_DAYS}" -exec rm -rf -- {} + 2>/dev/null
find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9][0-1][0-9][0-3][0-9]-*' \
  -printf '%f\n' 2>/dev/null | sort | head -n "-${_SQLSNAP_KEEP_MAX}" \
  | while read -r _old; do
      [ -n "${_old}" ] && rm -rf -- "${_SNAP_ROOT:?}/${_old}"
    done

exit 0
