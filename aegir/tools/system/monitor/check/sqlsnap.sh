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
# it is still there, and right before it restarts a server that stopped
# answering.
#
# Read-only on the database. Every call is time-bounded, so a server that
# does not answer costs seconds, never a hung capture, and the box's own
# state is read first. The files hold queries and command lines: root only,
# mode 600, under /var/log/boa/incident, any password given on a command line
# or in a statement replaced as each file is written.
#
# Usage: sqlsnap.sh <reason> [/var/log/boa/<name>.incident.log]
# Off with _INCIDENT_SNAPSHOT=NO in /root/.barracuda.cnf.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# shellcheck disable=SC1091
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf

# Set after the cnf, so nothing sourced or inherited can move them.
_SNAP_ROOT="/var/log/boa/incident"
_SNAP_MAX=200

_INCIDENT_SNAPSHOT="${_INCIDENT_SNAPSHOT^^}"
[ "${_INCIDENT_SNAPSHOT}" = "NO" ] && exit 0

# Minutes between two snapshots of one kind: an incident that flaps between
# tiers writes one set.
_SQLSNAP_COOLDOWN_MINS="${_SQLSNAP_COOLDOWN_MINS//[^0-9]/}"
_SQLSNAP_COOLDOWN_MINS="${_SQLSNAP_COOLDOWN_MINS:0:4}"
: "${_SQLSNAP_COOLDOWN_MINS:=15}"
_SQLSNAP_COOLDOWN_MINS=$(( 10#${_SQLSNAP_COOLDOWN_MINS} ))
(( _SQLSNAP_COOLDOWN_MINS < 1 )) && _SQLSNAP_COOLDOWN_MINS=1
# Days a snapshot is kept; never more than _SNAP_MAX of them, nor more than
# _SQLSNAP_KEEP_MB in all.
_SQLSNAP_KEEP_DAYS="${_SQLSNAP_KEEP_DAYS//[^0-9]/}"
_SQLSNAP_KEEP_DAYS="${_SQLSNAP_KEEP_DAYS:0:4}"
: "${_SQLSNAP_KEEP_DAYS:=14}"
_SQLSNAP_KEEP_DAYS=$(( 10#${_SQLSNAP_KEEP_DAYS} ))
(( _SQLSNAP_KEEP_DAYS < 1 )) && _SQLSNAP_KEEP_DAYS=1
_SQLSNAP_KEEP_MB="${_SQLSNAP_KEEP_MB//[^0-9]/}"
_SQLSNAP_KEEP_MB="${_SQLSNAP_KEEP_MB:0:6}"
: "${_SQLSNAP_KEEP_MB:=1024}"
_SQLSNAP_KEEP_MB=$(( 10#${_SQLSNAP_KEEP_MB} ))
(( _SQLSNAP_KEEP_MB < 128 )) && _SQLSNAP_KEEP_MB=128

_REASON="${1//[^a-zA-Z0-9.-]/}"
_REASON="${_REASON:0:40}"
[ -n "${_REASON}" ] || _REASON="manual"

# One cooldown and one lock per kind, so a crawler block, a backup window at
# high load or a stall snapshot a minute earlier never holds back another
# kind's snapshot; a restart has its own, the watchdog's breaker already
# limits how often it comes.
case "${_REASON}" in
  spider-*) _KIND=spider ;;
  max-*|critical-*) _KIND=load ;;
  sql-down*) _KIND=down ;;
  sql-*) _KIND=sql ;;
  *) _KIND=other ;;
esac
_SNAP_LAST="/run/boa_sqlsnap.${_KIND}.last"

# The incident log the caller mails from; the line naming the snapshot goes
# there, so the mail that follows carries it.
_pthOml="/var/log/boa/high.load.incident.log"
[[ "${2:-}" =~ ^/var/log/boa/[a-z0-9_.-]+\.incident\.log$ ]] && _pthOml="${2}"

# A database being upgraded, converted or moved on purpose is no database
# incident; mysql.sh stands down on the same marker and ignores it past four
# hours. A load or crawler incident meanwhile is still saved.
if [ "${_KIND}" = "sql" ] || [ "${_KIND}" = "down" ]; then
  if [ -e "/run/boa_sql_maintenance.pid" ] \
    && [ -z "$(find /run/boa_sql_maintenance.pid -mmin +240 2>/dev/null)" ]; then
    exit 0
  fi
fi

for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
  [ -r "${_L}" ] && . "${_L}" && break
done
_SELF_NAME="sqlsnap.sh"
if [ "${_KIND}" = "down" ] && command -v flock >/dev/null 2>&1; then
  # The restart follows in seconds and never asks again: wait a little for
  # a capture of the same kind rather than give up at once.
  exec 9> "/run/sqlsnap.${_KIND}.lock"
  flock -w 5 9 || exit 0
elif command -v _single_instance_lock >/dev/null 2>&1; then
  _single_instance_lock "/run/sqlsnap.${_KIND}.lock"
elif command -v flock >/dev/null 2>&1; then
  exec 9> "/run/sqlsnap.${_KIND}.lock"
  flock -n 9 || exit 0
fi

# Checked under the lock, so two callers in the same second write one set.
if [ -e "${_SNAP_LAST}" ] \
  && [ -z "$(find "${_SNAP_LAST}" -mmin "+${_SQLSNAP_COOLDOWN_MINS}" 2>/dev/null)" ]; then
  exit 0
fi

# A refusal takes the cooldown too, so it is logged once per cooldown, not
# on every pass of the caller.
_refuse() {
  touch "${_SNAP_LAST}"
  echo "$(date) INFO: incident snapshot (${_REASON}) not saved: $1" >> "${_pthOml}"
  exit 1
}

# Only a real directory takes the files, and never the last of the disk. A
# snapshot is a few MB, at most about 100 MB: it needs 256 MB free for root
# (the reserved blocks count, so a server stalled on a full disk is saved).
if [ -L "${_SNAP_ROOT}" ] || { [ -e "${_SNAP_ROOT}" ] && [ ! -d "${_SNAP_ROOT}" ]; }; then
  _refuse "${_SNAP_ROOT} is not a directory"
fi
_FREE_MB="$(stat -f -c '%f %S' /var/log/boa 2>/dev/null | awk '{printf "%d", $1 * $2 / 1048576}')"
if [[ "${_FREE_MB}" =~ ^[0-9]+$ ]] && (( _FREE_MB < 256 )); then
  _refuse "/var/log/boa has ${_FREE_MB} MB free"
fi
umask 077
mkdir -p "${_SNAP_ROOT}" || exit 1
chown root:root "${_SNAP_ROOT}" 2>/dev/null
chmod 700 "${_SNAP_ROOT}" 2>/dev/null

_DIR="${_SNAP_ROOT}/$(date +%Y%m%d-%H%M%S)-${_REASON}"
mkdir "${_DIR}" 2>/dev/null || exit 1
touch "${_SNAP_LAST}"
echo "$(date) INFO: incident snapshot (${_REASON}) saved to ${_DIR}" >> "${_pthOml}"

# Credentials never reach a file: a password a tool got on its command line
# (an option, a database or service URL, a dump or client tool's -p, a user
# with a password, a Percona Toolkit DSN's p=, the word Drush's user:password
# takes), or a password or its hash in a statement, is replaced by *** as the
# file is written. A statement literal cut short still goes.
_REDACT_SED="$(cat <<'EOF'
s/(--[a-z_-]*pass(word|wd|phrase)?[= ])[^ ]+/\1***/g
s#(://[^:/@ ]*:)[^@ /]+@#\1***@#g
s/(( -u ?|--user[= ])[^: ]+:)[^ ]+/\1***/g
\%(^|[ /])(mysql|mysqldump|mydumper|myloader|mysqladmin|mysqlcheck|mysqlpump|mysql_upgrade|mysqlimport|mysqlbinlog|mysqlshow|mysqlslap)(\.bin)?( |$)% s/( -p)[^ ]+/\1***/g
\%(^|[ /])(mydumper|myloader|sshpass)(\.bin)?( |$)% s/( -p) [^ -][^ ]*/\1 ***/
\%(^|[ /])redis-cli( |$)% s/( -a) [^ ]+/\1 ***/g
\%(^|[ /])pt-[a-z-]+( |$)% s/([ ,]p=)[^, ]+/\1***/g
\%(^|[ /])(drush[0-9]*|drush\.php|vdrush)( |$)% s/( (user:password|user-password|upwd)( +-[^ ]+)* +[^ -][^ ]*( +-[^ ]+)* +)[^ -][^ ]*/\1***/
s/(IDENTIFIED( |\\[ntr])+(WITH [^ ]+( |\\[ntr])+)?(BY|AS)( |\\[ntr])+(PASSWORD( |\\[ntr])+)?|PASSWORD *(FOR [^=]+)?=( |\\[ntr])*|PASSWORD *\( *|PASSWORD +|REPLACE )'([^'\\]|''|\\\\.|\\.)*('|$)/\1'***'/Ig
s/(IDENTIFIED( |\\[ntr])+(WITH [^ ]+( |\\[ntr])+)?(BY|AS)( |\\[ntr])+(PASSWORD( |\\[ntr])+)?|PASSWORD *(FOR [^=]+)?=( |\\[ntr])*|PASSWORD *\( *|PASSWORD +|REPLACE )"([^"\\]|""|\\\\.|\\.)*("|$)/\1"***"/Ig
EOF
)"
_redact() {
  LC_ALL=C sed -E -e "${_REDACT_SED}"
}

# Each capture is cut at this size: a stalled server's process list can hold
# statements of many megabytes each.
_FILE_MAX=$(( 16 * 1024 * 1024 ))

# One bounded client call; its output, cut and redacted, and its exit status
# go to the file named, after anything already there when appending.
_sql_to() {
  local _file="$1" _secs="$2" _rc
  shift 2
  timeout -k 2 "${_secs}" mysql --connect-timeout=3 --quick "$@" 2>&1 \
    | head -c "${_FILE_MAX}" | _redact >> "${_DIR}/${_file}"
  _rc="${PIPESTATUS[0]}"
  [ "${_rc}" -eq 0 ] || echo "(client exit ${_rc}; 124 or 137 mean no answer within ${_secs} s)" >> "${_DIR}/${_file}"
  return "${_rc}"
}

# The box first, in under a second: when the database does not answer, the
# SQL calls below can take half a minute, and the caller may stop web
# processes or restart the server meanwhile.
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
  echo
  timeout -k 1 5 df -P /var/log/boa /var/lib/mysql 2>/dev/null
} > "${_DIR}/box.txt" 2>&1

{
  # Every thread running or in uninterruptible wait, then mysqld's threads
  # by state and kernel wait, then PHP-FPM children per pool.
  echo "### threads in R or D state: state pid tid elapsed_s wchan comm args"
  timeout -k 2 10 ps -eLo state=,pid=,tid=,etimes=,wchan:32=,comm=,args= 2>/dev/null \
    | awk '$1 ~ /^[RD]/' | head -n 2000
  _MY_PID="$(timeout -k 1 3 pgrep -xo mysqld 2>/dev/null)"
  if [ -n "${_MY_PID}" ]; then
    echo
    echo "### mysqld ${_MY_PID} threads: count state wchan comm"
    timeout -k 2 10 ps -L -o state=,wchan:32=,comm= -p "${_MY_PID}" 2>/dev/null \
      | sort | uniq -c | sort -rn | head -n 200
  fi
  echo
  echo "### php-fpm children per pool"
  timeout -k 2 10 ps -eo args= 2>/dev/null | awk '/^php-fpm: pool /{print $3}' \
    | sort | uniq -c | sort -rn
} 2>&1 | head -c "${_FILE_MAX}" | _redact > "${_DIR}/processes.txt"
# The caller that waits for the box's state before a restart reads this.
touch "/run/boa_sqlsnap.${_KIND}.boxdone"

# Then the database: the connections and their statements (cut at 4 KB
# each, the longest-running active ones first, idle ones last; the plain
# list when that query gets no answer), InnoDB's own view, and when
# performance_schema is on, who waits for and who holds each metadata lock
# (holders of a contended object first) and which server thread each
# connection runs on.
if ! _sql_to processlist.txt 10 -e "SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 4096) AS INFO FROM information_schema.PROCESSLIST ORDER BY (COMMAND = 'Sleep'), TIME DESC"; then
  echo "### SHOW PROCESSLIST" >> "${_DIR}/processlist.txt"
  _sql_to processlist.txt 10 -e "SHOW PROCESSLIST"
fi
_sql_to innodb_status.txt 15 -e "SHOW ENGINE INNODB STATUS\G"
if [ "$(timeout -k 2 5 mysql --connect-timeout=3 -N -e "SELECT @@performance_schema" 2>/dev/null | tr -dc '0-9')" = "1" ]; then
  _sql_to metadata_locks.txt 10 -e "SELECT t.PROCESSLIST_ID, m.LOCK_STATUS, m.LOCK_TYPE, m.LOCK_DURATION, m.OBJECT_TYPE, m.OBJECT_SCHEMA, m.OBJECT_NAME FROM performance_schema.metadata_locks m LEFT JOIN performance_schema.threads t ON t.THREAD_ID = m.OWNER_THREAD_ID WHERE m.OBJECT_TYPE NOT IN ('TABLESPACE', 'BACKUP LOCK') ORDER BY (m.LOCK_STATUS = 'PENDING') DESC, (m.OBJECT_SCHEMA, m.OBJECT_NAME) IN (SELECT p.OBJECT_SCHEMA, p.OBJECT_NAME FROM performance_schema.metadata_locks p WHERE p.LOCK_STATUS = 'PENDING') DESC, t.PROCESSLIST_ID LIMIT 2000"
  _sql_to threads.txt 10 -e "SELECT THREAD_ID, PROCESSLIST_ID, THREAD_OS_ID, NAME, PROCESSLIST_COMMAND, PROCESSLIST_STATE, PROCESSLIST_TIME FROM performance_schema.threads ORDER BY PROCESSLIST_TIME DESC LIMIT 2000"
fi

chmod 600 "${_DIR}"/* 2>/dev/null

# Prune, one run at a time (a run busy pruning leaves it to the next): by
# age, then by count and by total size, oldest first, crawler-block then
# load snapshots before any other and database ones last; never a snapshot
# younger than five minutes (another kind may be writing it), and only names
# this script writes.
exec 8> /run/sqlsnap.prune.lock
flock -n 8 || exit 0
_NAMES='20[0-9][0-9][0-1][0-9][0-3][0-9]-*'
find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "${_NAMES}" \
  -mtime "+${_SQLSNAP_KEEP_DAYS}" -exec rm -rf -- {} + 2>/dev/null
_snap_list() {
  {
    find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "${_NAMES}-spider-*" -mmin +5 -printf '%f\n' | sort
    find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d \( -name "${_NAMES}-max-*" -o -name "${_NAMES}-critical-*" \) -mmin +5 -printf '%f\n' | sort
    find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "${_NAMES}" ! -name "${_NAMES}-spider-*" \
      ! -name "${_NAMES}-max-*" ! -name "${_NAMES}-critical-*" ! -name "${_NAMES}-sql-*" -mmin +5 -printf '%f\n' | sort
    find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "${_NAMES}-sql-*" -mmin +5 -printf '%f\n' | sort
  } 2>/dev/null
}
_snap_kb() {
  find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "${_NAMES}" -exec du -sk {} + 2>/dev/null \
    | awk '{s += $1} END {printf "%d", s}'
}
_COUNT="$(find "${_SNAP_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "${_NAMES}" 2>/dev/null | wc -l)"
if (( _COUNT > _SNAP_MAX )); then
  _snap_list | head -n "$(( _COUNT - _SNAP_MAX ))" | while read -r _old; do
    [ -n "${_old}" ] && [ "${_SNAP_ROOT}/${_old}" != "${_DIR}" ] || continue
    rm -rf -- "${_SNAP_ROOT:?}/${_old}"
  done
fi
if (( $(_snap_kb) > _SQLSNAP_KEEP_MB * 1024 )); then
  _snap_list | while read -r _old; do
    [ -n "${_old}" ] && [ "${_SNAP_ROOT}/${_old}" != "${_DIR}" ] || continue
    (( $(_snap_kb) > _SQLSNAP_KEEP_MB * 1024 )) || break
    rm -rf -- "${_SNAP_ROOT:?}/${_old}"
  done
fi

exit 0
