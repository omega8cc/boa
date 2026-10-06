#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# One channel for everything this run has to say to the operator: a dated
# line in the backup incident log, and the body from stdin mailed to
# _MY_EMAIL unless _INCIDENT_REPORT is OFF. Usable before the cnf is
# sourced below (the disk check runs first), so it sources what it needs.
_backup_notice() {
  local _sub="${1}" _detail="${2}"
  mkdir -p /var/log/boa
  echo "$(date) ${_sub}${_detail:+: ${_detail}}" >> /var/log/boa/mysql.backup.incident.log
  if [ -z "${_MY_EMAIL}" ] && [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
  fi
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  [ "${_INCIDENT_REPORT}" = "NO" ] && _INCIDENT_REPORT="OFF"
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ] \
    && [[ "$(s-nail -V 2>&1)" =~ "built for Linux" ]]; then
    {
      cat
      echo "Logged to /var/log/boa/mysql.backup.incident.log"
      echo
      echo "--"
      echo "This email has been sent by your nightly database backup"
    } | s-nail -s "${_sub}" ${_MY_EMAIL}
    echo "INFO: Backup notice sent to ${_MY_EMAIL}: ${_sub}"
  else
    cat > /dev/null
  fi
}

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

# A passive replication standby takes no DB dumps of its own -- the replica
# IS the live copy. Role marker only, never a local replica probe: this
# script targets the cluster's designated write node, so a local probe would
# falsely suppress a backup whose writes replicate correctly by design.
[ -e "/root/.standby.cnf" ] && exit 0

[ ! -e "/root/.my.cluster_write_node.txt" ] && exit 0
[ ! -e "/root/.my.cluster_root_pwd.txt" ] && exit 0

_IS_SQLBACKUP_RUNNING=$(pgrep -f '(^|(^| )[^ ]*bash )/var/xdrago/mysql_backup\.sh( |$)')
if [ ! -z "${_IS_SQLBACKUP_RUNNING}" ]; then
  exit 0
fi

if [ -e "/root/.my.cluster_backup_proxysql.txt" ]; then
  _SQL_PORT="6033"
  _SQL_HOST="127.0.0.1"
else
  _SQL_PORT="3306"
  if [ -e "/root/.my.cluster_write_node.txt" ]; then
    _SQL_HOST=$(cat /root/.my.cluster_write_node.txt 2>&1)
    _SQL_HOST=$(echo -n ${_SQL_HOST} | tr -d "\n" 2>&1)
  fi
  [ -z ${_SQL_HOST} ] && _SQL_HOST="127.0.0.1" && _SQL_PORT="3306"
fi

# Generate /root/.my.cluster_root.cnf (mode 0600) from the cluster root
# password file plus the resolved host/port above. Used via
# `_C_SQL` -> mysql --defaults-extra-file=... so the password never
# appears in /proc/<mysql-pid>/cmdline. The cluster-backup cron runs
# this every day, so the cnf is regenerated each run to track changes
# in _SQL_HOST/_SQL_PORT.
if [ -s "/root/.my.cluster_root_pwd.txt" ]; then
  _CLUSTER_ROOT_PWD=$(tr -d '\n' < /root/.my.cluster_root_pwd.txt)
  install -m 0600 -o root -g root /dev/null /root/.my.cluster_root.cnf
  cat > /root/.my.cluster_root.cnf <<CLUSTER_CNF
[client]
user=root
password="${_CLUSTER_ROOT_PWD}"
host=${_SQL_HOST}
port=${_SQL_PORT}
protocol=tcp
CLUSTER_CNF
  unset _CLUSTER_ROOT_PWD
fi

_C_SQL="mysql --defaults-extra-file=/root/.my.cluster_root.cnf"

echo "SQL --host=${_SQL_HOST} --port=${_SQL_PORT}"
_n=$((RANDOM%600+8))
echo "INFO: Waiting ${_n} seconds on $(date) before running backup..."
sleep ${_n}
echo "INFO: Starting backup on $(date)"

# shellcheck disable=SC1091
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf

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

_SQL_CACHE_EXC_DEF="cache_bootstrap cache_discovery cache_config"

if [ -e "/root/.my.cache.exceptions.cnf" ]; then
  _SQL_CACHE_EXC_ADD=$(cat /root/.my.cache.exceptions.cnf 2>&1)
  _SQL_CACHE_EXC="${_SQL_CACHE_EXC_DEF} ${_SQL_CACHE_EXC_ADD}"
else
  _SQL_CACHE_EXC="${_SQL_CACHE_EXC_DEF}"
fi

_BACKUPDIR=/data/disk/arch/cluster
_DATE=$(date +%y%m%d-%H%M%S)
_DOW=$(date +%u)
_hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
_DOW=${_DOW//[^1-7]/}
_DOM=$(date +%e)
_DOM=${_DOM//[^0-9]/}
_SAVELOCATION=${_BACKUPDIR}/${_hName}-${_DATE}
if [ -e "/root/.my.optimize.cnf" ]; then
  _OPTIM=YES
else
  _OPTIM=NO
fi
_VM_TEST="$(uname -a)"
if [[ "${_VM_TEST}" =~ "-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
# Run only after the by-design stand-down gates above (proxy, standby, not
# the cluster's write node, no cluster credentials): a box that takes no
# dumps by design must never be mailed about the disk it would not have used.
_check_disk_space() {
  _DF_TEST="$(LC_ALL=C command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 && u { gsub(/%/,"",$u); print $u }')"
  [[ "${_DF_TEST}" =~ ^[0-9]+$ ]] || _DF_TEST=""
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    ### No backup at all tonight is an incident, not a quiet exit.
    {
      echo "The cluster database backup run on ${_hName} did not start: the"
      echo "root filesystem is ${_DF_TEST}% full and the run refuses to add to it"
      echo "above 90%. No database was dumped. Free space, then run:"
      echo
      echo "  bash /var/xdrago/mysql_cluster_backup.sh"
      echo
    } | _backup_notice "Backup ABORTED on [${_hName}]: disk ${_DF_TEST}% full" "root filesystem ${_DF_TEST}% full"
    exit 1
  fi
}
_check_disk_space

# migratefs relocating /data/disk/arch holds it: /run/migratefs-arch.pid
# names a live root process that runs migratefs, matched as executed,
# never as a word anywhere on a command line (a pid reused after a kill -9,
# by another user's process or another command, never holds). Root is read
# as the real uid in /proc/<pid>/status: /proc/<pid> itself shows root as
# the owner of any process that is not dumpable. Prints that pid while the
# hold stands.
_arch_mfs_held() {
  local _p
  _p=$( { tr -dc '0-9' < /run/migratefs-arch.pid; } 2> /dev/null )
  [ -n "${_p}" ] && kill -0 "${_p}" 2> /dev/null \
    && [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_p}/status" 2> /dev/null)" = "0" ] \
    && { tr '\0' ' ' < "/proc/${_p}/cmdline"; } 2> /dev/null \
    | grep -qE '^([^ ]*/)?bash (-[^ ]+ )*([^ ]*/)?migratefs( |$)' \
    && echo "${_p}"
}
# The wait for that relocation, on the console and in migratefs's own log,
# next to the relocation it waits for: cron discards this output, and a
# wait that ends in a normal run is no incident for the incident log.
_arch_wait_log() {
  echo "INFO: $*"
  mkdir -p /var/log/boa
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >> /var/log/boa/migratefs.log
}
# Drops the wait marker while it still names this run.
_sql_wait_drop() {
  if [ "$( { tr -dc '0-9' < /run/boa_sql_backup_wait.pid; } 2> /dev/null )" = "$$" ]; then
    rm -f /run/boa_sql_backup_wait.pid
  fi
}
# A dump into a held archive would make /data/disk/arch again at the name
# the relocation's final pass set aside, or fail to write. Checked with the
# wait marker in place (the one the basic backup writes; each script
# refuses to start while the other runs): migratefs writes its hold before
# it looks for this run, and defers, dropping the hold, when it sees it; so
# one of the two always goes ahead, and a hold found here is a relocation
# already under way or one about to defer. Waited for up to 3 hours,
# checked every 60 s; a hold that outlives the bound skips this run, with a
# notice. The run marker, which the watchdogs and the task runner read as a
# backup in progress, is made only once no hold is left, and before the
# wait marker goes, so one of the two is always in place: a run that only
# waits stands none of them down.
echo $$ > /run/boa_sql_backup_wait.pid
_mfsPid=$(_arch_mfs_held)
if [[ -n "${_mfsPid}" ]]; then
  _mfsWait=0
  _arch_wait_log "mysql_cluster_backup.sh (pid $$) waits for migratefs (pid ${_mfsPid}) to finish relocating /data/disk/arch, up to 3 hours"
  while [[ -n "${_mfsPid}" ]] && [[ "${_mfsWait}" -lt 10800 ]]; do
    sleep 60
    _mfsWait=$(( _mfsWait + 60 ))
    _mfsPid=$(_arch_mfs_held)
  done
  if [[ -n "${_mfsPid}" ]]; then
    _arch_wait_log "mysql_cluster_backup.sh (pid $$) waited ${_mfsWait} s and /data/disk/arch is still held by migratefs (pid ${_mfsPid}); this run is skipped"
    {
      echo "The cluster database backup run on ${_hName} did not start:"
      echo "migratefs (pid ${_mfsPid}) was still relocating /data/disk/arch after"
      echo "this run had waited 3 hours for it. No database was dumped. Once the"
      echo "relocation has ended, run:"
      echo
      echo "  bash /var/xdrago/mysql_cluster_backup.sh"
      echo
    } | _backup_notice "Backup SKIPPED on [${_hName}]: /data/disk/arch is being relocated" "migratefs pid ${_mfsPid} still held it after ${_mfsWait} s"
    _sql_wait_drop
    exit 0
  fi
  _arch_wait_log "mysql_cluster_backup.sh (pid $$) waited ${_mfsWait} s; /data/disk/arch is no longer held, the database backup starts"
fi
touch /run/boa_sql_cluster_backup.pid
_sql_wait_drop

_create_locks() {
  echo "Creating locks for $1"
  touch /run/mysql_cluster_backup_running.pid
}

_remove_locks() {
  echo "Removing locks for $1"
  rm -f /run/mysql_cluster_backup_running.pid
}

_check_running() {
  # kept as a bare word on purpose: ProxySQL's command line is not observable
  # on the test fleet and a pattern that missed it would hold this loop forever
  _IS_PROXYSQL_RUNNING=$(pgrep -f proxysql)
  while [ -z "${_IS_PROXYSQL_RUNNING}" ] \
    || [ ! -e "/var/lib/proxysql/proxysql.pid" ]; do
    _IS_PROXYSQL_RUNNING=$(pgrep -f proxysql)
    echo "Waiting for ProxySQL availability..."
    sleep 3
  done
}

# Mirrors the mysql_cleanup.sh / mysql_backup.sh allowlist landed in
# category 5 of the security audit. Reject any DB or table identifier
# that contains characters outside [A-Za-z0-9_] before interpolating
# into SQL — same cross-tenant DROP DATABASE risk as the sibling scripts.
_is_safe_ident() {
  [[ "${1}" =~ ^[A-Za-z0-9_]+$ ]]
}

_truncate_cache_tables() {
  _check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
  for C in ${_TABLES}; do
    if ! _is_safe_ident "${C}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${C}"
      continue
    fi
    _IF_SKIP_C=
    for X in ${_SQL_CACHE_EXC}; do
      if [ "${C}" = "${X}" ]; then
        _IF_SKIP_C=SKIP
      fi
    done
    if [ -z "${_IF_SKIP_C}" ]; then
      ${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE \`${C}\`;
EOFMYSQL
    fi
  done
}

_truncate_watchdog_tables() {
  _check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^watchdog$ 2>&1)
  for W in ${_TABLES}; do
    if ! _is_safe_ident "${W}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${W}"
      continue
    fi
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE \`${W}\`;
EOFMYSQL
  done
}

_truncate_accesslog_tables() {
  _check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^accesslog$ 2>&1)
  for A in ${_TABLES}; do
    if ! _is_safe_ident "${A}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${A}"
      continue
    fi
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE \`${A}\`;
EOFMYSQL
  done
}

_truncate_batch_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^batch$ 2>&1)
  for B in ${_TABLES}; do
    if ! _is_safe_ident "${B}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${B}"
      continue
    fi
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE \`${B}\`;
EOFMYSQL
  done
}

_truncate_queue_tables() {
  _check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | grep ^queue$ 2>&1)
  for Q in ${_TABLES}; do
    if ! _is_safe_ident "${Q}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${Q}"
      continue
    fi
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE \`${Q}\`;
EOFMYSQL
  done
}

_truncate_views_data_export() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^views_data_export_index_ 2>&1)
  for V in ${_TABLES}; do
    if ! _is_safe_ident "${V}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${V}"
      continue
    fi
${_C_SQL} ${_DB}<<EOFMYSQL
DROP TABLE \`${V}\`;
EOFMYSQL
  done
${_C_SQL} ${_DB}<<EOFMYSQL
TRUNCATE \`views_data_export_object_cache\`;
EOFMYSQL
}

_repair_this_database() {
  _check_running
  mysqlcheck --defaults-extra-file=/root/.my.cluster_root.cnf --auto-repair --silent ${_DB}
}

_optimize_this_database() {
  _check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
    if ! _is_safe_ident "${T}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${T}"
      continue
    fi
${_C_SQL} ${_DB}<<EOFMYSQL
OPTIMIZE TABLE \`${T}\`;
EOFMYSQL
  done
}

_convert_to_innodb() {
  _check_running
  _TABLES=$(${_C_SQL} ${_DB} -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
    if ! _is_safe_ident "${T}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${T}"
      continue
    fi
${_C_SQL} ${_DB}<<EOFMYSQL
ALTER TABLE \`${T}\` ENGINE=INNODB;
EOFMYSQL
  done
}

### Percona 5.7 dumps sync their threads with FLUSH TABLES WITH READ LOCK
### (FTWRL), and mydumper also takes Percona's backup lock there (LOCK TABLES
### FOR BACKUP), keeping it until the dump ends, past the FTWRL release. A
### write to a MyISAM table waits for that lock with its table open, and the
### event scheduler writes one at every event run (mysql.event is MyISAM on
### 5.7): the flush ahead of FTWRL then waits for that table, or FTWRL for
### the writer, and neither side gives way. The server sees no deadlock, so
### the dump stalls there and every write on the box queues behind it. FTWRL
### alone still gives the dump its consistent point. Sets _MYDUMPER_BACKUP_LOCKS to
### --no-backup-locks when the local mydumper lists it, so a build without
### it gets its arguments as before.
_mydumper_backup_locks_opts() {
  local _h
  _MYDUMPER_BACKUP_LOCKS=()
  _h=$(mydumper --help 2>&1)
  if printf '%s\n' "${_h}" | grep -qE -- "^[[:space:]]+(-[[:alpha:]],[[:space:]]+)?--no-backup-locks([[:space:]]|=|$)"; then
    _MYDUMPER_BACKUP_LOCKS=(--no-backup-locks)
  fi
  return 0
}

### A database's triggers, stored routines and events are dumped with its
### tables. mydumper writes none of them unless asked, so a site that kept
### them (a logging trigger, a function its queries call, a scheduled event)
### found its nightly dumps without them. Each keeps its DEFINER, the site's
### own database user: a restore as root brings them back as that user, and
### the user restoring into its own database needs no extra privilege for
### objects it defines itself. Sets _MYDUMPER_OBJECTS to those of the three
### options the local mydumper lists, so a build without one gets its
### arguments as before.
_mydumper_objects_opts() {
  local _h _o
  _MYDUMPER_OBJECTS=()
  _h=$(mydumper --help 2>&1)
  for _o in --triggers --routines --events; do
    if printf '%s\n' "${_h}" | grep -qE -- "^[[:space:]]+(-[[:alpha:]],[[:space:]]+)?${_o}([[:space:]]|=|$)"; then
      _MYDUMPER_OBJECTS+=("${_o}")
    fi
  done
  return 0
}

### mydumper writes every trigger, routine and event of a database under one
### file-wide sql_mode, so an object made under another one (Drupal's own
### connections use ANSI_QUOTES and PIPES_AS_CONCAT) fails its load, or
### loads and then behaves otherwise. This gives each object back the mode
### the server stored for it: a plain SET before its CREATE and the file's
### mode after it (myloader stops on a versioned-comment SET in the middle
### of a file). Mode words 8.x refuses are left out, so a 5.7 dump loads
### there. It reads the file whole, never through a link, and replaces it
### through a new one in the same directory. Exits 1, the file as it was,
### when a line cannot be placed; 2 when an object had no mode to give.
_MYDUMPER_MODES_PL='use strict; use Fcntl;
my ($f) = @ARGV; my (%m, @o, $p, $miss);
my $gone = qr/^(?:NO_AUTO_CREATE_USER|NO_FIELD_OPTIONS|NO_KEY_OPTIONS|NO_TABLE_OPTIONS|DB2|MAXDB|MSSQL|MYSQL323|MYSQL40|ORACLE|POSTGRESQL)$/;
for (split /\n/, (defined $ENV{_MYDUMPER_MODES} ? $ENV{_MYDUMPER_MODES} : "")) {
  my ($t, $h, $s) = split /\t/, $_, 3;
  next unless defined $s && $t =~ /^(?:TRIGGER|FUNCTION|PROCEDURE|EVENT)$/
    && $h =~ /^[0-9A-Fa-f]+$/ && $s =~ /^[A-Z0-9_,]*$/;
  $m{$t . " " . lc($h)} = join(",", grep { $_ !~ $gone } split(/,/, $s));
}
sysopen(my $in, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or exit 1;
my @st = stat($in); exit 1 unless @st && -f _;
my @l = <$in>; close($in);
my $fm;
for my $x (@l[0 .. ($#l < 9 ? $#l : 9)]) {
  $fm = $1 if !defined $fm && $x =~ /^\/\*!40101 SET SQL_MODE=\x27([A-Z0-9_,]*)\x27\*\/;$/;
}
exit 1 unless defined $fm;
for my $i (0 .. $#l) {
  my $x = $l[$i];
  if ($p && $x =~ /^SET character_set_client = \@PREV_CHARACTER_SET_CLIENT;$/) {
    push @o, "SET SQL_MODE=\x27$fm\x27;\n"; $p = 0;
  }
  push @o, $x;
  next unless $x =~ /^DROP (TRIGGER|FUNCTION|PROCEDURE|EVENT) IF EXISTS `((?:[^`]|``)+)`;$/;
  my ($t, $n) = ($1, $2); $n =~ s/``/`/g;
  exit 0 if $i < $#l && $l[$i + 1] =~ /^SET SQL_MODE=/;
  my $s = $m{$t . " " . unpack("H*", $n)};
  if (defined $s) { push @o, "SET SQL_MODE=\x27$s\x27;\n"; $p = 1; } else { $miss = 1; }
}
exit 1 if $p;
my $w = $f . ".modes";
sysopen(my $out, $w, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1;
if (!(print {$out} @o) || !close($out) || !chmod($st[2] & 07777, $w)
  || ($> == 0 && !chown($st[4], $st[5], $w)) || !rename($w, $f)) { unlink($w); exit 1; }
exit($miss ? 2 : 0);'

### Gives every stored object of database $1, dumped by mydumper into the
### directory $2, its own sql_mode back (see _MYDUMPER_MODES_PL), read with
### the client command that follows. Returns 0 when done or when there is
### nothing to do, 1 when the modes could not be read (the files as
### mydumper wrote them), 2 when an object or a file kept the dump's mode.
### It never fails a dump: the caller says what was left.
_mydumper_object_modes() {
  local _db="${1}" _dir="${2}" _q _modes _f _rc=0
  shift 2
  [[ "${_db}" =~ ^[A-Za-z0-9_]+$ ]] || return 2
  _q="SELECT 'TRIGGER', HEX(TRIGGER_NAME), SQL_MODE FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = '${_db}'"
  _q="${_q} UNION ALL SELECT ROUTINE_TYPE, HEX(ROUTINE_NAME), SQL_MODE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '${_db}'"
  _q="${_q} UNION ALL SELECT 'EVENT', HEX(EVENT_NAME), SQL_MODE FROM information_schema.EVENTS WHERE EVENT_SCHEMA = '${_db}'"
  _modes=$("$@" -N -B -e "${_q}" 2> /dev/null) || return 1
  [[ -n "${_modes}" ]] || return 0
  for _f in "${_dir}"/*-schema-post.sql "${_dir}"/*-schema-triggers.sql; do
    if [[ -L "${_f}" ]]; then
      _rc=2
      continue
    fi
    [[ -f "${_f}" ]] || continue
    _MYDUMPER_MODES="${_modes}" perl -e "${_MYDUMPER_MODES_PL}" -- "${_f}" || _rc=2
  done
  return "${_rc}"
}

_backup_this_database_with_mydumper() {
  _check_running
  if [ ! -d "${_SAVELOCATION}/${_DB}" ]; then
    mkdir -p ${_SAVELOCATION}/${_DB}
  fi
  _MYDUMPER_LOCK_MODE="AUTO"
  _MYDUMPER_BACKUP_LOCKS=()
  if [[ "${_DB_V}" == "5.7" ]]; then
    _MYDUMPER_LOCK_MODE="FTWRL"
    _mydumper_backup_locks_opts
  fi
  ### Any non-transactional table makes mydumper abort the whole database
  ### unless --trx-tables=0 is passed; InnoDB-only keeps the fast path.
  _NON_TRX_COUNT=$(${_C_SQL} -s -N -e "SELECT COUNT(*) FROM \
information_schema.TABLES WHERE TABLE_SCHEMA='${_DB}' AND \
TABLE_TYPE='BASE TABLE' AND ENGINE IS NOT NULL AND \
ENGINE NOT IN ('InnoDB')" 2> /dev/null)
  _MYDUMPER_TRX_OPT=""
  if [[ "${_NON_TRX_COUNT}" =~ ^[0-9]+$ ]] && [[ "${_NON_TRX_COUNT}" -gt "0" ]]; then
    _MYDUMPER_TRX_OPT="--trx-tables=0"
  fi
  ### mydumper 1.x fixed the adaptive chunker: 0.21.x truncated a chunk's file
  ### to 0 bytes when another thread's split landed past the last existing key,
  ### exiting clean with metadata written. On 1.x the tables are chunked and
  ### dumped in parallel again; older builds keep chunking off (--rows=-1). A
  ### fixed --rows=N never comes back: it walks a sparse key span in N-key steps
  ### until the box runs out of inodes. Probed here, per database, and anchored
  ### on the banner line: a stray line ahead of it cannot pass as a version,
  ### and a binary replaced during the run (the agent pass installs the pin)
  ### meets the flags it takes from the next database on.
  _MYDUMPER_ROWS_OPT="--rows=-1"
  _MYDUMPER_MAJOR=$(mydumper -V 2>&1 | grep -m1 "^mydumper v" | cut -d" " -f2 | tr -d "v" | cut -d"." -f1)
  case "${_MYDUMPER_MAJOR}" in
    [1-9]*) _MYDUMPER_ROWS_OPT="" ;;
  esac
  _mydumper_objects_opts
  ### _MYDUMPER_TRX_OPT and _MYDUMPER_ROWS_OPT unquoted by design: empty must expand to no argument.
  mydumper \
    --defaults-file=/root/.my.cluster_root.cnf \
    --database=${_DB} \
    --host=localhost \
    --port=3306 \
    --outputdir=${_SAVELOCATION}/${_DB}/ \
    ${_MYDUMPER_ROWS_OPT} \
    "${_MYDUMPER_OBJECTS[@]}" \
    --build-empty-files \
    --threads=4 \
    --long-query-guard=900 \
    --sync-thread-lock-mode=${_MYDUMPER_LOCK_MODE} \
    "${_MYDUMPER_BACKUP_LOCKS[@]}" \
    ${_MYDUMPER_TRX_OPT} \
    --verbose=1 &> "${_SAVELOCATION}/${_DB}.mydumper.log"
  _MYDUMPER_RC=$?
  ### mydumper renames metadata into place at the end of its run, so a
  ### missing marker means the run never got there (a crash, a kill, a
  ### failed lock) and a non-zero exit means it logged an error on the way.
  ### Neither is a dump to archive: keep the debris and the tool's own
  ### output out of the compressor's way and in the operator's sight. The
  ### loop redirects this helper, so its output is the only trace kept.
  if [ "${_MYDUMPER_RC}" -ne "0" ] || [ ! -e "${_SAVELOCATION}/${_DB}/metadata" ]; then
    echo "ALRT: mydumper FAILED or left no metadata for ${_DB} -- keeping the debris and the tool's output in ${_DB}.FAILED/"
    mv -f ${_SAVELOCATION}/${_DB} ${_SAVELOCATION}/${_DB}.FAILED 2>/dev/null
    mkdir -p "${_SAVELOCATION}/${_DB}.FAILED"
    mv -f "${_SAVELOCATION}/${_DB}.mydumper.log" "${_SAVELOCATION}/${_DB}.FAILED/mydumper.log" 2>/dev/null
    return 1
  fi
  rm -f "${_SAVELOCATION}/${_DB}.mydumper.log"
  _mydumper_object_modes "${_DB}" "${_SAVELOCATION}/${_DB}" mysql --defaults-extra-file=/root/.my.cluster_root.cnf || _MYDUMPER_MODES_LEFT="YES"
  return 0
}

### The dumps never carry the server's GTID state. By default
### (--set-gtid-purged=AUTO) a dump taken while GTID is on opens with
### SET @@SESSION.SQL_LOG_BIN=0 and sets @@GLOBAL.GTID_PURGED. A database
### user without SUPER cannot load such a dump at all (ERROR 1227), loading
### it back on a server that shares that history fails (ERROR 3546 on 8.x,
### 1840 on 5.7), and where it passes it stays out of the binary log, so the
### other nodes and replicas never get the restored rows. OFF writes
### neither. Sets _MYSQLDUMP_GTID to the option when the local mysqldump
### takes it: one that does not (MariaDB's) would refuse it and writes
### neither anyway, so it is asked, never assumed.
_mysqldump_gtid_opts() {
  _MYSQLDUMP_GTID=()
  if mysqldump --help 2> /dev/null | grep -q -- '--set-gtid-purged'; then
    _MYSQLDUMP_GTID=(--set-gtid-purged=OFF)
  fi
  return 0
}

### A database's stored routines and events are dumped with its tables,
### views and triggers. mysqldump writes neither unless asked, so a site
### that kept them (a function its queries call, a scheduled event) found
### its nightly dumps without them. Each keeps its DEFINER, as the views and
### triggers always have: a restore as root brings them back as they were.
### mysqldump stops the whole dump on a routine whose body the dumping login
### may not read and on events it may not list, so each option is asked
### first, as that login (the client command given after the database
### name), and left out when refused or when the question fails: the
### tables are then dumped as before, and _MYSQLDUMP_LEFT_OUT names what
### the dump lacks for the run's notice. Sets _MYSQLDUMP_OBJECTS.
_mysqldump_objects_opts() {
  local _db="$1" _n
  shift
  _MYSQLDUMP_OBJECTS=()
  _MYSQLDUMP_LEFT_OUT=""
  _n=$("$@" -B -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_DEFINITION IS NULL" "${_db}" 2> /dev/null)
  if [ "${_n}" = "0" ]; then
    _MYSQLDUMP_OBJECTS+=(--routines)
  else
    _MYSQLDUMP_LEFT_OUT="routines"
  fi
  if "$@" -B -N -e "SHOW EVENTS" "${_db}" > /dev/null 2>&1; then
    _MYSQLDUMP_OBJECTS+=(--events)
  else
    _MYSQLDUMP_LEFT_OUT="${_MYSQLDUMP_LEFT_OUT:+${_MYSQLDUMP_LEFT_OUT} and }events"
  fi
  return 0
}

_backup_this_database_with_mysqldump() {
  _check_running
  ### _C_SQL unquoted by design: the client and its option file, two words.
  _mysqldump_objects_opts "${_DB}" ${_C_SQL}
  ### --defaults-extra-file must stay the first option.
  mysqldump \
    --defaults-extra-file=/root/.my.cluster_root.cnf \
    "${_MYSQLDUMP_GTID[@]}" \
    --single-transaction \
    --quick \
    --no-autocommit \
    --skip-add-locks \
    --no-tablespaces \
    "${_MYSQLDUMP_OBJECTS[@]}" \
    --hex-blob ${_DB} \
    > ${_SAVELOCATION}/${_DB}.sql 2> "${_SAVELOCATION}/${_DB}.mysqldump.log"
  _MYSQLDUMP_RC=$?
  ### A failed or truncated dump used to be compressed and kept as THE
  ### backup for the night: the rc was never read, and gzip turns any
  ### partial file into a valid archive. Demand rc=0 and mysqldump's own
  ### trailer, and get the debris out of the way so the compressor cannot
  ### promote it to a backup. The debris goes into a directory: a bare
  ### <db>.sql.FAILED file reads as <db>'s backup to the tenant copier,
  ### which strips two extensions to find the database name.
  if [ "${_MYSQLDUMP_RC}" -ne "0" ] || ! tail -5 ${_SAVELOCATION}/${_DB}.sql 2>/dev/null | grep -q "Dump completed"; then
    echo "ALRT: mysqldump FAILED or produced a truncated dump for ${_DB} -- keeping the debris and the tool's output in ${_DB}.FAILED/"
    mkdir -p "${_SAVELOCATION}/${_DB}.FAILED"
    mv -f ${_SAVELOCATION}/${_DB}.sql "${_SAVELOCATION}/${_DB}.FAILED/${_DB}.sql" 2>/dev/null
    mv -f "${_SAVELOCATION}/${_DB}.mysqldump.log" "${_SAVELOCATION}/${_DB}.FAILED/mysqldump.log" 2>/dev/null
    return 1
  fi
  rm -f "${_SAVELOCATION}/${_DB}.mysqldump.log"
}

_compress_backup() {
  if [ "${_MYQUICK_USE}" = "YES" ]; then
    for DbPath in `find ${_SAVELOCATION}/ -maxdepth 1 -mindepth 1 | sort`; do
      if [ -e "${DbPath}/metadata" ]; then
        DbName=$(echo ${DbPath} | cut -d'/' -f7 | awk '{ print $1}' 2>&1)
        cd ${_SAVELOCATION}
        ### NEVER delete the dump until the archive that replaces it is
        ### proven readable: an unchecked tar (disk full, zstd missing)
        ### left a 0-byte .tar.zst and the rm then destroyed the only
        ### copy of the night's backup.
        if tar -c -p -I zstd -f ${DbName}-${_DATE}.tar.zst ${DbName} &> /dev/null \
          && [ -s "${DbName}-${_DATE}.tar.zst" ] \
          && tar -p -I zstd -tf ${DbName}-${_DATE}.tar.zst &> /dev/null; then
          rm -f -r ${DbName}
        else
          echo "ALRT: compressing ${DbName} FAILED -- keeping the uncompressed dump directory"
          rm -f ${DbName}-${_DATE}.tar.zst
          _COMPRESS_FAILED_N=$(( ${_COMPRESS_FAILED_N:-0} + 1 ))
          _COMPRESS_FAILED_DBS="${_COMPRESS_FAILED_DBS} ${DbName}"
        fi
      fi
    done
    chmod 600 ${_SAVELOCATION}/*
    chmod 700 ${_SAVELOCATION}
    chmod 700 /data/disk/arch
    echo "INFO: Permissions fixed"
  else
    ### Per file, so one failure is counted and reported and the others
    ### still get their archive; gzip leaves a failed input untouched.
    for DbSql in ${_SAVELOCATION}/*.sql; do
      [ -e "${DbSql}" ] || continue
      if ! gzip "${DbSql}"; then
        echo "ALRT: compressing $(basename "${DbSql}") FAILED -- keeping the uncompressed dump"
        _COMPRESS_FAILED_N=$(( ${_COMPRESS_FAILED_N:-0} + 1 ))
        _COMPRESS_FAILED_DBS="${_COMPRESS_FAILED_DBS} $(basename "${DbSql}" .sql)"
      fi
    done
    chmod 600 ${_BACKUPDIR}/*/*
    chmod 700 ${_BACKUPDIR}/*
    chmod 700 ${_BACKUPDIR}
    chmod 700 /data/disk/arch
    echo "INFO: Permissions fixed"
  fi
}

[ ! -e ${_SAVELOCATION} ] && mkdir -p ${_SAVELOCATION};

_check_mysql_version() {
  _DB_V=$(mysql -V 2>&1 \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1 \
    | cut -d"." -f1,2)
  if [ ! -z "${_DB_V}" ]; then
    ${_C_SQL} -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_change_buffering = 'none';" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_io_capacity=3000;" &> /dev/null
    ${_C_SQL} -e "SET GLOBAL innodb_io_capacity_max=6000;" &> /dev/null
    if [ "${_DB_V}" = "5.7" ]; then
      ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
      ${_C_SQL} -e "SET GLOBAL innodb_buffer_pool_dump_now = ON;" &> /dev/null
    fi
    ${_C_SQL} -e -e "SET GLOBAL innodb_fast_shutdown = 1;" &> /dev/null
  fi
}

_check_running
_check_mysql_version

_MYQUICK_USE=NO
if [ -x "/usr/local/bin/mydumper" ]; then
  _MYQUICK_ITD=$(mydumper -V 2>&1 \
    | tr -d "\n" \
    | tr -d "," \
    | tr -d "v" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  _DB_V=$(mysql -V 2>&1 \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1 \
    | cut -d"." -f1,2)
  _MD_V=$(mydumper --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f6 \
    | awk '{ print $1}' \
    | cut -d"-" -f1 \
    | awk '{ print $1}' \
    | sed "s/[\,']//g" 2>&1)
  if [ ! -e "/root/.mysql.force.legacy.backup.cnf" ]; then
    _MYQUICK_USE=YES
    echo "INFO: Installed MyQuick ${_MYQUICK_ITD} for ${_MD_V} (${_DB_V})"
  fi
fi
if [ "${_MYQUICK_USE}" != "YES" ]; then
  _mysqldump_gtid_opts
  [ "${#_MYSQLDUMP_GTID[@]}" -eq 0 ] \
    && echo "INFO: this mysqldump takes no --set-gtid-purged: its dumps carry no GTID state"
fi


# A dump that failed must never disappear quietly: cron discards this
# script's output, so the ALRT lines above reach nobody. Every failure is
# counted in the loop and the compress phase, then reported ONCE per run --
# a dated line in /var/log/boa/mysql.backup.incident.log (harvested with the
# other incident logs) and an e-mail to _MY_EMAIL unless _INCIDENT_REPORT is
# OFF. The debris of a failed dump is kept beside the archives as
# <name>.FAILED with the tool's own output as <name>.mydumper.log, so the
# operator reads what the tool said instead of guessing.
_notify_dump_failures() {
  [ "${_DUMP_FAILED_N:-0}" = "0" ] && [ "${_COMPRESS_FAILED_N:-0}" = "0" ] && return 0
  local _sub _d
  if [ "${_DUMP_FAILED_N:-0}" != "0" ]; then
    _sub="Backup FAILED for ${_DUMP_FAILED_N} database(s) on [${_hName}]"
  else
    _sub="Backup archive INCOMPLETE for ${_COMPRESS_FAILED_N} database(s) on [${_hName}]"
  fi
  {
    if [ "${_DUMP_FAILED_N:-0}" != "0" ]; then
      echo "The database backup run on ${_hName} could not dump ${_DUMP_FAILED_N} database(s):"
      echo
      for _d in ${_DUMP_FAILED_DBS}; do
        echo "  ${_d}"
      done
      echo
      echo "Their dumps are missing from ${_SAVELOCATION}. What the dump tool"
      echo "left behind is kept there in <name>.FAILED/ together with the tool's"
      echo "own output (mydumper.log or mysqldump.log); every other database"
      echo "was archived as usual."
      echo
    fi
    if [ "${_COMPRESS_FAILED_N:-0}" != "0" ]; then
      echo "The archive step failed for ${_COMPRESS_FAILED_N} database(s), whose dump"
      echo "directories are kept uncompressed in ${_SAVELOCATION}:"
      echo
      for _d in ${_COMPRESS_FAILED_DBS}; do
        echo "  ${_d}"
      done
      echo
      echo "A full disk or a missing zstd is the usual cause."
      echo
    fi
    echo "To repeat the run once the cause is fixed:"
    echo
    echo "  bash /var/xdrago/mysql_cluster_backup.sh"
    echo
  } | _backup_notice "${_sub}" "in ${_SAVELOCATION}:${_DUMP_FAILED_DBS}${_COMPRESS_FAILED_DBS:+ uncompressed:${_COMPRESS_FAILED_DBS}}"
}

# A dump the probe had to take without the stored routines or events is
# archived, but must not pass for a complete one: reported once per run on
# the same channel.
_notify_objects_left_out() {
  [ -z "${_OBJECTS_LEFT_DBS}" ] && return 0
  local _d
  {
    echo "The database backup run on ${_hName} dumped these database(s) without"
    echo "their stored routines or events (database:left out):"
    echo
    for _d in ${_OBJECTS_LEFT_DBS}; do
      echo "  ${_d}"
    done
    echo
    echo "The dumping login could not read them, and mysqldump would have"
    echo "stopped the whole dump, so the tables were dumped without them."
    echo "Check the rights of the login in the option file the run uses."
    echo
  } | _backup_notice "Backup without stored routines or events on [${_hName}]" "in ${_SAVELOCATION}:${_OBJECTS_LEFT_DBS}"
}

# A dump whose stored objects could not each be given the sql_mode they
# were made under (_mydumper_object_modes) is archived as mydumper wrote
# it; cron discards the run's WARN line, so it is reported once per run on
# the same channel.
_notify_modes_left() {
  [ -z "${_MODES_LEFT_DBS}" ] && return 0
  local _d
  {
    echo "The database backup run on ${_hName} archived the triggers, routines"
    echo "or events of these database(s) under the dump's own sql_mode:"
    echo
    for _d in ${_MODES_LEFT_DBS}; do
      echo "  ${_d}"
    done
    echo
    echo "Their own modes could not each be written into the dump, so a load"
    echo "of one made under another mode (a Drupal site's own, for one) can"
    echo "fail or work otherwise. The next run writes them again."
    echo
  } | _backup_notice "Backup with stored objects under the dump's sql_mode on [${_hName}]" "in ${_SAVELOCATION}:${_MODES_LEFT_DBS}"
}

_DUMP_FAILED_N=0
_DUMP_FAILED_DBS=""
_OBJECTS_LEFT_DBS=""
_MODES_LEFT_DBS=""
for _DB in `${_C_SQL} -e "show databases" -s | uniq | sort`; do
  if [ "${_DB}" != "Database" ] \
    && [ "${_DB}" != "information_schema" ] \
    && [ "${_DB}" != "performance_schema" ]; then
    if ! _is_safe_ident "${_DB}"; then
      echo "WARN: skipping unsafe database identifier: ${_DB}"
      continue
    fi
    _check_running
    _create_locks ${_DB}
    if [ "${_DB}" != "mysql" ]; then
      _IS_GB=$(${_C_SQL} --skip-column-names --silent -e "SELECT table_name 'Table Name', round(((data_length + index_length)/1024/1024),0)
'Table Size (MB)' FROM information_schema.TABLES WHERE table_schema = '${_DB}' AND table_name ='watchdog';" | cut -d'/' -f1 | awk '{ print $2}' | sed "s/[\/\s+]//g" | bc 2>&1)
      _IS_GB=${_IS_GB//[^0-9]/}
      _SQL_MAX_LIMIT="1024"
      if [ ! -z "${_IS_GB}" ]; then
        if [ "${_IS_GB}" -gt "${_SQL_MAX_LIMIT}" ]; then
          _truncate_watchdog_tables &> /dev/null
          echo "INFO: Truncated giant ${_IS_GB} watchdog in ${_DB}"
        fi
      fi
      # _truncate_accesslog_tables &> /dev/null
      # echo "Truncated not used accesslog in ${_DB}"
      # _truncate_queue_tables &> /dev/null
      # echo "Truncated queue table in ${_DB}"
      _CACHE_CLEANUP=NONE
      # if [ "${_DOW}" = "6" ] && [ -e "/root/.my.batch_innodb.cnf" ]; then
      #   _repair_this_database &> /dev/null
      #   echo "Repair task for ${_DB} completed"
      #   _truncate_cache_tables &> /dev/null
      #   echo "All cache tables in ${_DB} truncated"
      #   _convert_to_innodb &> /dev/null
      #   echo "InnoDB conversion task for ${_DB} completed"
      #   _CACHE_CLEANUP=DONE
      # fi
      # if [ "${_OPTIM}" = "YES" ] \
      #   && [ "${_DOW}" = "7" ] \
      #   && [ "${_DOM}" -ge 24 ] \
      #   && [ "${_DOM}" -lt 31 ]; then
      #   _repair_this_database &> /dev/null
      #   echo "Repair task for ${_DB} completed"
      #   _truncate_cache_tables &> /dev/null
      #   echo "All cache tables in ${_DB} truncated"
      #   _optimize_this_database &> /dev/null
      #   echo "Optimize task for ${_DB} completed"
      #   _CACHE_CLEANUP=DONE
      # fi
      if [ "${_CACHE_CLEANUP}" != "DONE" ]; then
        _truncate_cache_tables &> /dev/null
        echo "INFO: All cache tables in ${_DB} truncated"
      fi
    fi
    _DUMP_RC=0
    _MYSQLDUMP_LEFT_OUT=""
    _MYDUMPER_MODES_LEFT=""
    if [ "${_MYQUICK_USE}" = "YES" ]; then
      _backup_this_database_with_mydumper &> /dev/null || _DUMP_RC=1
    else
      _backup_this_database_with_mysqldump &> /dev/null || _DUMP_RC=1
    fi
    _remove_locks ${_DB}
    if [ "${_DUMP_RC}" = "0" ]; then
      echo "INFO: Backup completed for ${_DB}"
      if [ -n "${_MYSQLDUMP_LEFT_OUT}" ]; then
        echo "WARN: ${_DB} was dumped without its ${_MYSQLDUMP_LEFT_OUT}: the dumping login could not read them"
        _OBJECTS_LEFT_DBS="${_OBJECTS_LEFT_DBS} ${_DB}:${_MYSQLDUMP_LEFT_OUT// and /+}"
      fi
      if [ -n "${_MYDUMPER_MODES_LEFT}" ]; then
        echo "WARN: ${_DB}'s stored objects kept the dump's own sql_mode: a load of one made under another mode can fail or work otherwise"
        _MODES_LEFT_DBS="${_MODES_LEFT_DBS} ${_DB}"
      fi
    else
      _DUMP_FAILED_N=$(( ${_DUMP_FAILED_N:-0} + 1 ))
      _DUMP_FAILED_DBS="${_DUMP_FAILED_DBS} ${_DB}"
      echo "ALRT: Backup FAILED for ${_DB} -- this run's archive will not carry it"
    fi
    echo
  fi
done

echo "INFO: Completing all dbs backups on $(date)"
rm -f /run/boa_sql_cluster_backup.pid
touch /var/log/boa/last-run-cluster-backup

echo "INFO: Starting dbs backup compress on $(date)"
_compress_backup &> /dev/null
echo "INFO: Completing dbs backup compress on $(date)"
_notify_dump_failures
_notify_objects_left_out
_notify_modes_left

echo "INFO: Starting dbs backup cleanup on $(date)"
_DB_BACKUPS_TTL=${_DB_BACKUPS_TTL//[^0-9]/}
if [ -z "${_DB_BACKUPS_TTL}" ]; then
  _DB_BACKUPS_TTL="30"
fi
find ${_BACKUPDIR} -mtime +${_DB_BACKUPS_TTL} -type d -exec rm -rf {} \;
echo "INFO: Backups older than ${_DB_BACKUPS_TTL} days deleted"

echo "INFO: ALL TASKS COMPLETED, BYE!"
### exit 0 by design even after failed dumps: they are reported above, and
### cron reads nothing from the exit status; a non-zero exit would only
### matter to an operator's wrapper, which must then read the incident log.
exit 0

