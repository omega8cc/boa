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

# A replication standby: REPAIR/OPTIMIZE are local writes that land in
# the binlog as errant transactions on a replica -- the source's own
# repair replicates over instead.
[ -e "/root/.standby.cnf" ] && exit 0

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

# A full-server check, repair and optimize locks and rewrites every table, which
# is exactly what the watchdog's maintenance marker exists to announce: while it
# is held the database watchdog stands down entirely, so it cannot read this
# work as a fault and restart the server underneath it. The trap means a killed
# run cannot leave auto-healing disabled, and the watchdog ignores the marker
# once it is stale in any case.
touch /run/boa_sql_maintenance.pid
trap 'rm -f /run/boa_sql_maintenance.pid' EXIT

dir=/var/log/boa/mysql_optimize
mkdir -p $dir
# (Removed dead `_SQL_PSWD=$(cat /root/.my.pass.txt)` read — never
#  referenced; mysqlcheck below uses /root/.my.cnf implicitly.)
/usr/bin/mysqlcheck -u root -Aa >> $dir/all.a.$(date +%y%m%d-%H%M%S)
/usr/bin/mysqlcheck -u root -A --auto-repair >> $dir/all.r.$(date +%y%m%d-%H%M%S)
/usr/bin/mysqlcheck -u root -Ao >> $dir/all.o.$(date +%y%m%d-%H%M%S)
exit 0

