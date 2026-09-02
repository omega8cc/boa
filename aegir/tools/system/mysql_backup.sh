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
  _DF_TEST="$(LC_ALL=C command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 && u { gsub(/%/,"",$u); print $u }')"
  [[ "${_DF_TEST}" =~ ^[0-9]+$ ]] || _DF_TEST=""
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
_check_root

[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

# A passive replication standby takes no local DB dumps or TRUNCATEs even
# before its replication is configured -- xmass writes the role marker
# ahead of the datadir swap, and this gate is what protects the copied-in
# datadir during that window.
[ -e "/root/.standby.cnf" ] && exit 0

# Never TRUNCATE/DROP/OPTIMIZE on a configured replica: under ROW binlog a
# replicated change to a locally truncated row stops the SQL thread outright
# -- the same guard mysql_cleanup.sh carries, because this script performs
# the same class of local writes nightly. The replica config itself is the
# authoritative role state; it clears at promotion (RESET REPLICA/SLAVE ALL
# empties the probe). 8.4 removed SHOW SLAVE STATUS and 5.7 lacks SHOW
# REPLICA STATUS, so the fallback rides the probe's EXIT CODE: empty output
# with rc 0 is the only clean "not a replica", and an errored probe (broken
# or under-privileged credentials) proves nothing and REFUSES -- the old
# form read both as "not a replica". With mysqld down the role cannot be
# judged yet: the head call defers, and the gate asks again right after
# _check_running has waited the daemon up -- the old form probed once,
# read the empty answer as clean, then waited for the very daemon it
# failed to reach and proceeded to DROP/TRUNCATE on it. NB: the cluster
# variant (mysql_cluster_backup.sh) carries the standby ROLE marker gate
# instead of this probe -- it targets the cluster's designated write node,
# so a local replica probe there would falsely suppress a backup whose
# writes replicate correctly by design.
_replica_role_gate() {
  local _rplState _rplRc
  if ! mysqladmin ping &> /dev/null; then
    # Unreachable (booting or down): defer -- the caller after
    # _check_running re-asks once the daemon is up.
    return 0
  fi
  _rplState=$(mysql -e "SHOW REPLICA STATUS\G" 2>/dev/null)
  _rplRc=$?
  if [ "${_rplRc}" -ne "0" ]; then
    _rplState=$(mysql -e "SHOW SLAVE STATUS\G" 2>/dev/null)
    _rplRc=$?
  fi
  if [ "${_rplRc}" -ne "0" ]; then
    # One retry before refusing: a transient server hiccup must not cost
    # a healthy box its whole nightly backup.
    sleep 3
    _rplState=$(mysql -e "SHOW REPLICA STATUS\G" 2>/dev/null)
    _rplRc=$?
    if [ "${_rplRc}" -ne "0" ]; then
      _rplState=$(mysql -e "SHOW SLAVE STATUS\G" 2>/dev/null)
      _rplRc=$?
    fi
  fi
  if [ "${_rplRc}" -eq "0" ] && [ -n "${_rplState}" ]; then
    # The run marker may already exist (the re-ask sits after the pid
    # write); five watchdog consumers read it as a live backup, so it
    # must not outlive this exit -- but ONLY when it is OURS: at the head
    # call this process has not written it yet, and a concurrent run's
    # live marker must never be deleted from here.
    if [ "$(tr -dc '0-9' < /run/boa_sql_backup.pid 2>/dev/null)" = "$$" ]; then
      rm -f /run/boa_sql_backup.pid
    fi
    echo "Ooops, this box is a configured replication replica, local TRUNCATE/OPTIMIZE would break the SQL thread"
    exit 0
  fi
  if [ "${_rplRc}" -ne "0" ]; then
    # mysqladmin ping exits 0 even on Access denied, so credential
    # failures land here, not in the ping branch. Fail closed.
    if [ "$(tr -dc '0-9' < /run/boa_sql_backup.pid 2>/dev/null)" = "$$" ]; then
      rm -f /run/boa_sql_backup.pid
    fi
    echo "Ooops, the replica role probe FAILED (credentials?) -- refusing local TRUNCATE/DROP; verify /root/.my.cnf"
    exit 0
  fi
  return 0
}
_replica_role_gate

_IS_SQLBACKUP_RUNNING=$(pgrep -f mysql_cluster_backup.sh)
if [ ! -z "${_IS_SQLBACKUP_RUNNING}" ]; then
  exit 0
fi

# Nor on top of another run of this script. The nightly cron cannot overlap
# itself, but `backchain` runs the basic mode on demand and can land inside the
# full nightly run, putting two dump chains on the same server. The marker is
# only believed while the process that wrote it is alive, so a killed backup
# cannot lock the next one out.
if [ -s "/run/boa_sql_backup.pid" ]; then
  _RUNNING_PID="$(tr -dc '0-9' < /run/boa_sql_backup.pid 2>/dev/null)"
  if [ -n "${_RUNNING_PID}" ] && kill -0 "${_RUNNING_PID}" 2>/dev/null; then
    echo "Another SQL backup (pid ${_RUNNING_PID}) is already running"
    exit 0
  fi
fi

if [ "${1}" = "full" ] || [ -z "${1}" ]; then
  _THIS_MODE="full"
elif [ "${1}" = "basic" ]; then
  _THIS_MODE="basic"
fi

if [ "${_THIS_MODE}" = "full" ]; then
  echo "INFO: Starting silent usage report on $(date)"
  bash /var/xdrago/usage.sh silent
  wait
  echo "INFO: Completing silent usage report on $(date)"
fi

_VM_TEST="$(uname -a)"
if [[ "${_VM_TEST}" =~ "-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi

if [ "${_VMFAMILY}" = "VS" ] && [ "${_THIS_MODE}" = "full" ]; then
  _n=$((RANDOM%600+8))
  echo "INFO: Waiting ${_n} seconds 1/2 on $(date) before running backup..."
  sleep ${_n}
  _n=$((RANDOM%300+8))
  echo "INFO: Waiting ${_n} seconds 2/2 on $(date) before running backup..."
  sleep ${_n}
fi

echo "INFO: Starting dbs backup on $(date)"

# Defaults before the cnf source below so the cnf value wins; the
# variable is the supported switch, the marker stays honoured for
# one release while fleets converge.
_MY_RESTART_AFTER_OPTIMIZE=NO

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

_BACKUPDIR=/data/disk/arch/sql
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
# Record the owning pid so a later run can tell a live backup from a leaked
# marker; clear.sh still age-reaps it as a backstop.
echo $$ > /run/boa_sql_backup.pid

# (Previously: _SQL_PSWD=$(cat /root/.my.pass.txt ...). Removed in the
#  security-audit credential-exposure pass — mydumper now reads creds
#  from /root/.my.cnf via --defaults-file, keeping the password out of
#  /proc/PID/cmdline.)

_free_memory() {
  echo "Freeing memory..."
  sync && echo 3 | tee /proc/sys/vm/drop_caches
}

_create_locks() {
  echo "INFO: Creating locks for $1"
  touch /run/mysql_backup_running.pid
  _free_memory
}

_remove_locks() {
  echo "INFO: Removing locks for $1"
  rm -f /run/mysql_backup_running.pid
  _free_memory
}

_check_running() {
  # Bounded two ways, the shape the launcher and lib mirrors already use:
  # ~60s of CONSECUTIVE dead samples catches a database that is not coming
  # back, while the total ceiling still ends the run against a flapping
  # server. A live process with no socket yet is a recovery or
  # data-dictionary upgrade in progress and RESETS the dead counter --
  # counting those ticks made the bound a total-time bound and aborted the
  # nightly run against a healthy, starting server. A cron job waiting
  # forever helps nobody and holds its lock pid meanwhile; on give-up the
  # next scheduled run retries. No start attempt here on purpose: bringing
  # the server up is not a backup job's business.
  local _dead=0
  local _tot=0
  while : ; do
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ] && [ -e "/run/mysqld/mysqld.sock" ]; then
      return 0
    fi
    if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
      _dead=0
    else
      _dead=$(( _dead + 1 ))
    fi
    _tot=$(( _tot + 1 ))
    if [ "${_dead}" -gt 20 ] || [ "${_tot}" -gt 400 ]; then
      echo "ALERT: MySQLD did not become available (down $(( _dead > 0 ? (_dead - 1) * 3 : 0 ))s, total wait $(( (_tot - 1) * 3 ))s), giving up."
      _remove_locks _check_running_timeout
      exit 1
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo "INFO: Waiting for MySQLD availability..."
    fi
    sleep 3
  done
}

# Mirrors the mysql_cleanup.sh allowlist landed in category 5 of the
# security audit. Reject any DB or table identifier that contains
# characters outside [A-Za-z0-9_] before interpolating into SQL — a
# tenant-created table named like `cache_x\`; DROP DATABASE other; -- `
# would otherwise let the TRUNCATE heredoc cross-tenant-drop in root
# mysql context.
_is_safe_ident() {
  [[ "${1}" =~ ^[A-Za-z0-9_]+$ ]]
}

_truncate_cache_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
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
      mysql ${_DB}<<EOFMYSQL
TRUNCATE \`${C}\`;
EOFMYSQL
    fi
  done
}

_truncate_watchdog_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^watchdog$ 2>&1)
  for W in ${_TABLES}; do
    if ! _is_safe_ident "${W}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${W}"
      continue
    fi
mysql ${_DB}<<EOFMYSQL
TRUNCATE \`${W}\`;
EOFMYSQL
  done
}

_truncate_accesslog_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^accesslog$ 2>&1)
  for A in ${_TABLES}; do
    if ! _is_safe_ident "${A}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${A}"
      continue
    fi
mysql ${_DB}<<EOFMYSQL
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
mysql ${_DB}<<EOFMYSQL
TRUNCATE \`${B}\`;
EOFMYSQL
  done
}

_truncate_queue_tables() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^queue$ 2>&1)
  for Q in ${_TABLES}; do
    if ! _is_safe_ident "${Q}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${Q}"
      continue
    fi
mysql ${_DB}<<EOFMYSQL
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
mysql ${_DB}<<EOFMYSQL
DROP TABLE \`${V}\`;
EOFMYSQL
  done
mysql ${_DB}<<EOFMYSQL
TRUNCATE \`views_data_export_object_cache\`;
EOFMYSQL
}

_repair_this_database() {
  _check_running
  mysqlcheck -u root --auto-repair --silent ${_DB}
}

_optimize_this_database() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
    if ! _is_safe_ident "${T}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${T}"
      continue
    fi
mysql ${_DB}<<EOFMYSQL
OPTIMIZE TABLE \`${T}\`;
EOFMYSQL
  done
}

_convert_to_innodb() {
  _check_running
  _TABLES=$(mysql ${_DB} -u root -e "show tables" -s | uniq | sort 2>&1)
  for T in ${_TABLES}; do
    if ! _is_safe_ident "${T}"; then
      echo "WARN: skipping unsafe table identifier in ${_DB}: ${T}"
      continue
    fi
mysql ${_DB}<<EOFMYSQL
ALTER TABLE \`${T}\` ENGINE=INNODB;
EOFMYSQL
  done
}

_backup_this_database_with_mydumper() {
  _check_running
  if [ ! -d "${_SAVELOCATION}/${_DB}" ]; then
    mkdir -p ${_SAVELOCATION}/${_DB}
  fi
  _MYDUMPER_LOCK_MODE="AUTO"
  if [[ "${_DB_V}" == "5.7" ]]; then
    _MYDUMPER_LOCK_MODE="FTWRL"
  fi
  ### Any non-transactional table makes mydumper abort the whole database
  ### unless --trx-tables=0 is passed; InnoDB-only keeps the fast path.
  _NON_TRX_COUNT=$(mysql -u root -s -N -e "SELECT COUNT(*) FROM \
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
  ### until the box runs out of inodes.
  _MYDUMPER_ROWS_OPT="--rows=-1"
  case "${_MYQUICK_ITD}" in
    [1-9]*) _MYDUMPER_ROWS_OPT="" ;;
  esac
  ### _MYDUMPER_TRX_OPT and _MYDUMPER_ROWS_OPT unquoted by design: empty must expand to no argument.
  mydumper \
    --defaults-file=/root/.my.cnf \
    --database=${_DB} \
    --host=localhost \
    --port=3306 \
    --outputdir=${_SAVELOCATION}/${_DB}/ \
    ${_MYDUMPER_ROWS_OPT} \
    --build-empty-files \
    --threads=4 \
    --long-query-guard=900 \
    --sync-thread-lock-mode=${_MYDUMPER_LOCK_MODE} \
    ${_MYDUMPER_TRX_OPT} \
    --verbose=1
  ### mydumper renames metadata into place only when every table is
  ### dumped, so a non-zero exit or a missing marker both mean an
  ### incomplete dump: keep its debris out of the compressor's way and
  ### in the operator's sight.
  if [ "$?" -ne "0" ] || [ ! -e "${_SAVELOCATION}/${_DB}/metadata" ]; then
    echo "ALRT: mydumper FAILED or left no metadata for ${_DB} -- keeping the debris as ${_DB}.FAILED"
    mv -f ${_SAVELOCATION}/${_DB} ${_SAVELOCATION}/${_DB}.FAILED 2>/dev/null
    return 1
  fi
}

_backup_this_database_with_mysqldump() {
  _check_running
  mysqldump \
    --single-transaction \
    --quick \
    --no-autocommit \
    --skip-add-locks \
    --no-tablespaces \
    --hex-blob ${_DB} \
    > ${_SAVELOCATION}/${_DB}.sql
  ### A failed or truncated dump used to be compressed and kept as THE
  ### backup for the night: the rc was never read, and gzip turns any
  ### partial file into a valid archive. Demand rc=0 and mysqldump's own
  ### trailer, and get the debris out of the way so the compressor cannot
  ### promote it to a backup.
  if [ "$?" -ne "0" ] || ! tail -5 ${_SAVELOCATION}/${_DB}.sql 2>/dev/null | grep -q "Dump completed"; then
    echo "ALRT: mysqldump FAILED or produced a truncated dump for ${_DB} -- discarding it"
    mv -f ${_SAVELOCATION}/${_DB}.sql ${_SAVELOCATION}/${_DB}.sql.FAILED 2>/dev/null
    return 1
  fi
}

_backup_mysql_schema() {
  _check_running
  # The mysql system schema uses MyISAM on Percona 5.7 and a mix on 8.x,
  # so mydumper is never appropriate here. mysqldump handles mixed-engine
  # system schemas correctly. --routines and --events are required to
  # capture stored procedures and scheduled events which mydumper would miss.
  # --single-transaction is a no-op for MyISAM tables but harmless and
  # ensures InnoDB system tables (8.x) are captured consistently.
  mysqldump \
    --single-transaction \
    --quick \
    --no-autocommit \
    --skip-add-locks \
    --no-tablespaces \
    --hex-blob \
    --routines \
    --events \
    mysql \
    > ${_SAVELOCATION}/mysql.sql
  if [ "$?" -ne "0" ] || ! tail -5 ${_SAVELOCATION}/mysql.sql 2>/dev/null | grep -q "Dump completed"; then
    echo "ALRT: mysqldump FAILED or produced a truncated dump for the mysql system schema -- discarding it"
    mv -f ${_SAVELOCATION}/mysql.sql ${_SAVELOCATION}/mysql.sql.FAILED 2>/dev/null
    return 1
  fi
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
        fi
      fi
    done
    # mysql schema is always backed up with mysqldump regardless of _MYQUICK_USE,
    # so compress it separately alongside the mydumper zst archives
    if [ -e "${_SAVELOCATION}/mysql.sql" ]; then
      gzip ${_SAVELOCATION}/mysql.sql
    fi
    chmod 600 ${_SAVELOCATION}/*
    chmod 700 ${_SAVELOCATION}
    chmod 700 /data/disk/arch
    echo "INFO: Permissions fixed"
  else
    gzip ${_SAVELOCATION}/*.sql
    chmod 600 ${_SAVELOCATION}/*.sql.gz
    chmod 700 ${_SAVELOCATION}
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
    mysql -u root -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
    mysql -u root -e "SET GLOBAL innodb_change_buffering = 'none';" &> /dev/null
    mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
    mysql -u root -e "SET GLOBAL innodb_io_capacity=3000;" &> /dev/null
    mysql -u root -e "SET GLOBAL innodb_io_capacity_max=6000;" &> /dev/null
    if [ "${_DB_V}" = "5.7" ]; then
      mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_now = ON;" &> /dev/null
    fi
    mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 1;" &> /dev/null
  fi
}

_check_running
# Re-ask now that _check_running has waited mysqld up: the head call
# cannot judge the role while the daemon is unreachable.
_replica_role_gate
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


# A dump that failed must never disappear quietly: cron discards this
# script's stdout, so the ALRT lines above reach nobody. Every failure is
# counted in the loop, then reported ONCE per run through the same channel
# the watchdogs use -- a dated line in /var/log/boa and an e-mail to
# _MY_EMAIL unless _INCIDENT_REPORT is OFF. The debris of a failed dump is
# kept beside the archives as <name>.FAILED, so the operator can read the
# tool's own leftovers instead of guessing.
_notify_dump_failures() {
  [ "${_DUMP_FAILED_N:-0}" = "0" ] && return 0
  mkdir -p /var/log/boa
  echo "$(date) Backup FAILED for ${_DUMP_FAILED_N} database(s) in ${_SAVELOCATION}:${_DUMP_FAILED_DBS}" \
    >> /var/log/boa/mysql.backup.incident.log
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  [ "${_INCIDENT_REPORT}" = "NO" ] && _INCIDENT_REPORT="OFF"
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ] \
    && [[ "$(s-nail -V 2>&1)" =~ "built for Linux" ]]; then
    {
      echo "The database backup run on ${_hName} could not dump ${_DUMP_FAILED_N} database(s):"
      echo
      for _d in ${_DUMP_FAILED_DBS}; do
        echo "  ${_d}"
      done
      echo
      echo "Their dumps are missing from ${_SAVELOCATION}. Whatever the dump tool"
      echo "left behind is kept there as <name>.FAILED for inspection; every"
      echo "other database was archived as usual. Run the script by hand and"
      echo "read its ALRT lines to see the tool's own error:"
      echo
      echo "  bash /var/xdrago/mysql_backup.sh basic"
      echo
      echo "Logged to /var/log/boa/mysql.backup.incident.log"
      echo
      echo "--"
      echo "This email has been sent by your nightly database backup"
    } | s-nail -s "Backup FAILED for ${_DUMP_FAILED_N} database(s) on [${_hName}]" ${_MY_EMAIL}
    echo "INFO: Backup failure notice sent to ${_MY_EMAIL}"
  fi
}

_DUMP_FAILED_N=0
_DUMP_FAILED_DBS=""
for _DB in `mysql -e "show databases" -s | uniq | sort`; do
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
      if [ -e "/var/lib/mysql/${_DB}/queue.ibd" ] \
        && [ ! -e "/etc/boa/.disable_mysql_cleanup.cnf" ] \
        && ! grep -qiE "^[[:space:]]*(export[[:space:]]+)?_DISABLE_MYSQL_CLEANUP=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/queue.ibd | grep "G" 2>/dev/null)
        if [[ "${_IS_GB}" =~ "queue" ]]; then
          _truncate_queue_tables &> /dev/null
          echo "INFO: Truncated giant queue in ${_DB}"
        fi
      fi
      if [ -e "/var/lib/mysql/${_DB}/batch.ibd" ] \
        && [ ! -e "/etc/boa/.disable_mysql_cleanup.cnf" ] \
        && ! grep -qiE "^[[:space:]]*(export[[:space:]]+)?_DISABLE_MYSQL_CLEANUP=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/batch.ibd | grep "G" 2>/dev/null)
        if [[ "${_IS_GB}" =~ "batch" ]]; then
          _truncate_batch_tables &> /dev/null
          echo "INFO: Truncated giant batch in ${_DB}"
        fi
      fi
      if [ -e "/var/lib/mysql/${_DB}/watchdog.ibd" ] \
        && [ ! -e "/etc/boa/.disable_mysql_cleanup.cnf" ] \
        && ! grep -qiE "^[[:space:]]*(export[[:space:]]+)?_DISABLE_MYSQL_CLEANUP=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/watchdog.ibd | grep "G" 2>/dev/null)
        if [[ "${_IS_GB}" =~ "watchdog" ]]; then
          _truncate_watchdog_tables &> /dev/null
          echo "INFO: Truncated giant watchdog in ${_DB}"
        fi
      fi
      if [ -e "/var/lib/mysql/${_DB}/accesslog.ibd" ] \
        && [ ! -e "/etc/boa/.disable_mysql_cleanup.cnf" ] \
        && ! grep -qiE "^[[:space:]]*(export[[:space:]]+)?_DISABLE_MYSQL_CLEANUP=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
        _IS_GB=$(du -s -h /var/lib/mysql/${_DB}/accesslog.ibd | grep "G" 2>/dev/null)
        if [[ "${_IS_GB}" =~ "accesslog" ]]; then
          _truncate_accesslog_tables &> /dev/null
          echo "INFO: Truncated giant accesslog in ${_DB}"
        fi
      fi
      _truncate_views_data_export &> /dev/null
      echo "INFO: Truncated not used views_data_export in ${_DB}"
      _CACHE_CLEANUP=NONE
      if [ "${_DOW}" = "6" ] && [ -e "/root/.my.batch_innodb.cnf" ]; then
        _repair_this_database &> /dev/null
        echo "INFO: Repair task for ${_DB} completed"
        _truncate_cache_tables &> /dev/null
        echo "INFO: All cache tables in ${_DB} truncated"
        _convert_to_innodb &> /dev/null
        echo "INFO: InnoDB conversion task for ${_DB} completed"
        _CACHE_CLEANUP=DONE
      fi
      if [ "${_OPTIM}" = "YES" ] \
        && [ "${_DOW}" = "7" ] \
        && [ "${_THIS_MODE}" = "full" ] \
        && [ "${_DOM}" -ge 24 ] \
        && [ "${_DOM}" -lt 31 ]; then
        _repair_this_database &> /dev/null
        echo "INFO: Repair task for ${_DB} completed"
        _truncate_cache_tables &> /dev/null
        echo "INFO: All cache tables in ${_DB} truncated"
        _optimize_this_database &> /dev/null
        echo "INFO: Optimize task for ${_DB} completed"
        _CACHE_CLEANUP=DONE
      fi
      if [ "${_CACHE_CLEANUP}" != "DONE" ]; then
        _truncate_cache_tables &> /dev/null
        echo "INFO: All cache tables in ${_DB} truncated"
      fi
    fi
    _DUMP_RC=0
    if [ "${_DB}" = "mysql" ]; then
      _backup_mysql_schema &> /dev/null || _DUMP_RC=1
    elif [ "${_MYQUICK_USE}" = "YES" ]; then
      _backup_this_database_with_mydumper &> /dev/null || _DUMP_RC=1
    else
      _backup_this_database_with_mysqldump &> /dev/null || _DUMP_RC=1
    fi
    _remove_locks ${_DB}
    if [ "${_DUMP_RC}" = "0" ]; then
      echo "INFO: Backup completed for ${_DB}"
    else
      _DUMP_FAILED_N=$(( ${_DUMP_FAILED_N:-0} + 1 ))
      _DUMP_FAILED_DBS="${_DUMP_FAILED_DBS} ${_DB}"
      echo "ALRT: Backup FAILED for ${_DB} -- this run's archive will not carry it"
    fi
    echo
  fi
done

if [ "${_THIS_MODE}" = "full" ]; then
  echo "INFO: Running all dbs usage report on $(date)"
  mkdir -p /var/log/boa 2>/dev/null
  du -s /var/lib/mysql/* > /var/log/boa/.du.local.sql
  echo "INFO: Completing all dbs usage report on $(date)"
fi

if [ "${_OPTIM}" = "YES" ] \
  && [ "${_DOW}" = "7" ] \
  && [ "${_THIS_MODE}" = "full" ] \
  && [ "${_DOM}" -ge 24 ] \
  && [ "${_DOM}" -lt 31 ] \
  && { [ "${_MY_RESTART_AFTER_OPTIMIZE}" = "YES" ] \
    || [ -e "/root/.my.restart_after_optimize.cnf" ]; } \
  && [ ! -e "/run/boa_run.pid" ] \
  && [ ! -e "/run/boa_wait.pid" ] \
  && [ ! -e "/run/octopus_install_run.pid" ] \
  && ! pgrep -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 \
  && ! pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/(barracuda|octopus)( |$)" > /dev/null 2>&1 \
  && ! pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-" > /dev/null 2>&1; then
  _check_running
  _check_mysql_version
  echo "INFO: Running db server restart on $(date)"
  bash /var/xdrago/move_sql.sh
  wait
  echo "INFO: Completing db server restart on $(date)"
elif [ "${_OPTIM}" = "YES" ] \
  && [ "${_DOW}" = "7" ] \
  && [ "${_THIS_MODE}" = "full" ] \
  && [ "${_DOM}" -ge 24 ] \
  && [ "${_DOM}" -lt 31 ] \
  && { [ "${_MY_RESTART_AFTER_OPTIMIZE}" = "YES" ] \
    || [ -e "/root/.my.restart_after_optimize.cnf" ]; }; then
  # This window recurs once a month: say WHY the restart was skipped, or
  # a deferral is indistinguishable from the feature silently breaking
  echo "INFO: db server restart after optimize SKIPPED on $(date) -- an install/upgrade pass is in flight; next window next month"
fi

echo "INFO: Completing all dbs backups on $(date)"
rm -f /run/boa_sql_backup.pid
touch /var/log/boa/last-run-backup

if [ "${_VMFAMILY}" = "VS" ] && [ "${_THIS_MODE}" = "full" ]; then
  _n=$((RANDOM%300+8))
  echo "INFO: Waiting ${_n} seconds on $(date) before running compress..."
  sleep ${_n}
fi
echo "INFO: Starting dbs backup compress on $(date)"
_compress_backup &> /dev/null
echo "INFO: Completing dbs backup compress on $(date)"
_notify_dump_failures

echo "INFO: Starting dbs backup cleanup on $(date)"
_DB_BACKUPS_TTL=${_DB_BACKUPS_TTL//[^0-9]/}
if [ -z "${_DB_BACKUPS_TTL}" ]; then
  _DB_BACKUPS_TTL="14"
fi
if [ "${_THIS_MODE}" = "basic" ]; then
  _DB_BACKUPS_TTL="3"
fi
find ${_BACKUPDIR}/* -mtime +${_DB_BACKUPS_TTL} -type d -exec rm -rf {} \;
echo "INFO: Backups older than ${_DB_BACKUPS_TTL} days deleted"

if [ "${_THIS_MODE}" = "full" ]; then
  if [ -x "/opt/local/bin/copydbackup" ]; then
    echo "INFO: Copying backups to users space"
    bash /opt/local/bin/copydbackup &> /dev/null
    wait
  fi
fi

if [ "${_THIS_MODE}" = "full" ]; then
  echo "INFO: Starting verbose usage report on $(date)"
  bash /var/xdrago/usage.sh verbose
  wait
  echo "INFO: Completing verbose usage report on $(date)"
fi

echo "INFO: ALL TASKS COMPLETED, BYE!"
exit 0

