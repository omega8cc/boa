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

_IS_SQLBACKUP_RUNNING=$(pgrep -f mysql_backup.sh)
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

touch /run/boa_sql_cluster_backup.pid

_create_locks() {
  echo "Creating locks for $1"
  touch /run/mysql_cluster_backup_running.pid
}

_remove_locks() {
  echo "Removing locks for $1"
  rm -f /run/mysql_cluster_backup_running.pid
}

_check_running() {
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
  ### _MYDUMPER_TRX_OPT and _MYDUMPER_ROWS_OPT unquoted by design: empty must expand to no argument.
  mydumper \
    --defaults-file=/root/.my.cluster_root.cnf \
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
}

_backup_this_database_with_mysqldump() {
  _check_running
  mysqldump \
    --defaults-extra-file=/root/.my.cluster_root.cnf \
    --single-transaction \
    --quick \
    --no-autocommit \
    --skip-add-locks \
    --no-tablespaces \
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

_DUMP_FAILED_N=0
_DUMP_FAILED_DBS=""
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
    if [ "${_MYQUICK_USE}" = "YES" ]; then
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

echo "INFO: Completing all dbs backups on $(date)"
rm -f /run/boa_sql_cluster_backup.pid
touch /var/log/boa/last-run-cluster-backup

echo "INFO: Starting dbs backup compress on $(date)"
_compress_backup &> /dev/null
echo "INFO: Completing dbs backup compress on $(date)"
_notify_dump_failures

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

