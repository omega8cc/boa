#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

[ -e "/root/.proxy.cnf" ] && exit 0

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

_NOW=$(date +%y%m%d-%H%M%S)
_NOW=${_NOW//[^0-9-]/}

_create_locks() {
  # NB: do NOT drop the page/dentry/inode cache here. A restart must not evict the
  # box-wide cache -- on a busy box that forces cold re-reads and a stampede, which
  # is one of the amplifiers behind the am095 restart storm. Genuine memory pressure
  # is handled by the OOM path, not by every MySQL restart.
  echo "Creating locks..."
  : > /run/boa_wait.pid
  : > /run/fmp_wait.pid
  : > /run/restarting_fmp_wait.pid
  : > /run/mysql_restart_running.pid
}

_remove_locks() {
  echo "Removing locks..."
  [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
  rm -f /run/fmp_wait.pid
  rm -f /run/restarting_fmp_wait.pid
  rm -f /run/mysql_restart_running.pid
}

_check_running() {
  if [ -e "/run/mysql_restart_running.pid" ]; then
    echo "MySQLD restart procedure in progress?"
    echo "Nothing to do, let's quit now. Bye!"
    exit 1
  fi
}

_start_sql() {
  _check_running
  _create_locks

  _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
  if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
    echo "MySQLD already running?"
    echo "Nothing to do. Bye!"
    _remove_locks
    # A running mysqld is the desired end state -- return/exit success. NEVER fall
    # through to rm the LIVE socket/pid below and 'service mysql start' a second
    # mysqld_safe: when mysqld_safe has already respawned mysqld between the stop
    # and start phases of a restart, that duplicate-supervisor race is what drove
    # the every-minute "mysqld_safe: 0 processes / mysqld restarted" flap on am095.
    [ "$1" = "chain" ] && return 0
    exit 0
  fi

  echo "Starting MySQLD again..."

  if [ -e "/run/mysqld/mysqld.pid" ] \
    || [ -e "/run/mysqld/mysqld.sock" ] \
    || [ -e "/run/mysqld/mysqlx.sock" ]; then
    rm -f /run/mysqld/mysql*
  fi
  renice ${_B_NICE} -p $$ &> /dev/null
  service mysql start &> /dev/null
  _mysqld_wait=0
  while [ -z "${_IS_MYSQLD_RUNNING}" ] \
    || [ ! -e "/run/mysqld/mysqld.sock" ]; do
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
    echo "Waiting for MySQLD graceful start..."
    sleep 3
    _mysqld_wait=$(( _mysqld_wait + 1 ))
    if [ "${_mysqld_wait}" -ge 20 ]; then
      # Bounded: a start that cannot succeed (corrupt data, disk full, bad config)
      # must not spin forever holding the restart locks, which would block every
      # future auto-heal. Give up this attempt, clear the locks and let the caller
      # report it; the next monitor tick can retry.
      echo "MySQLD did not come up within ~60s -- giving up this attempt"
      _remove_locks
      [ "$1" != "chain" ] && exit 1
      return 1
    fi
  done
  echo "MySQLD started"

  _remove_locks
  echo "MySQLD start procedure completed"
  [ "$1" != "chain" ] && exit 0
}

_stop_sql() {
  _check_running
  _create_locks

  echo "Stopping Nginx now..."
  service nginx stop &> /dev/null
  until [ -z "${_IS_NGINX_RUNNING}" ]; do
    _IS_NGINX_RUNNING=$(pgrep -f 'nginx: ')
    echo "Waiting for Nginx graceful shutdown..."
    sleep 1
  done
  killall nginx &> /dev/null
  echo "Nginx stopped"

  echo "Stopping all PHP-FPM instances now..."
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56 55 54 53"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
      mv -f /var/log/php/php${e}-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
      service "php${e}-fpm" force-quit &> /dev/null
    fi
  done
  until [ -z "${_IS_FPM_RUNNING}" ]; do
    _IS_FPM_RUNNING=$(pgrep -f 'php-fpm: ')
    echo "Waiting for PHP-FPM graceful shutdown..."
    sleep 1
  done
  pkill -9 -f php-fpm
  echo "PHP-FPM stopped"

  _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
  if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
    _DB_V=$(mysql -V 2>&1 \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -1 \
      | cut -d"." -f1,2)
    if [ ! -z "${_DB_V}" ]; then
      echo "Preparing MySQLD for quick shutdown..."
      # (Removed dead `_SQL_PSWD=$(cat /root/.my.pass.txt)` read — never
      #  referenced; the mysql -u root calls below use /root/.my.cnf
      #  implicitly.)
      mysql -u root -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_change_buffering = 'none';" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_io_capacity=3000;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_io_capacity_max=6000;" &> /dev/null
      if [ "${_DB_V}" = "5.7" ]; then
        mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
        mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_now = ON;" &> /dev/null
      fi
    fi
    mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 1;" &> /dev/null
    echo "Stopping MySQLD now..."
    service mysql stop &> /dev/null
    wait
    rm -f /run/mysqld/mysql*
  else
    echo "MySQLD already stopped?"
    echo "Nothing to do. Bye!"
    _remove_locks
    [ "$1" != "chain" ] && exit 1
  fi

  until [ -z "${_IS_MYSQLD_RUNNING}" ]; do
    _IS_MYSQLD_RUNNING=$(pgrep -f /usr/sbin/mysqld)
    echo "Waiting for MySQLD graceful shutdown..."
    sleep 3
  done
  echo "MySQLD stopped"

  _remove_locks
  echo "MySQLD stop procedure completed"
  [ "$1" != "chain" ] && exit 0
}

_re_start_sql() {
  _stop_sql "chain"
  _start_sql "chain"
  _remove_locks
  exit 0
}

_mysqld_answering() {
  # Local liveness probe (mirrors mysql.sh _mysql_is_answering): any reply --
  # including an auth error or "Too many connections" -- proves the server is up.
  case "$(timeout 5 mysqladmin -u root --connect-timeout=2 ping 2>&1)" in
    *"is alive"*|*"denied"*|*"Too many connections"*) return 0 ;;
    *) return 1 ;;
  esac
}

_stop_mysqld_only() {
  # Stop ONLY mysqld -- never nginx/php-fpm, never the cache. Used by the DB
  # watchdog to recover a wedged-but-present mysqld (hung/deadlocked) with minimal
  # blast radius. A hung server will not honour a graceful mysqladmin shutdown, so
  # cap the graceful attempt (timeout) and then force the survivor down (TERM, then
  # KILL).
  #
  # CRITICAL: stop escalating the instant the server answers again. On a mysqld_safe
  # box the supervisor respawns a fresh mysqld within ~1-2s; hard-killing or
  # de-socketing that healthy respawn would recreate the am095 restart flap this
  # redesign exists to prevent. So re-probe between each step and leave a live,
  # answering server alone; only clear the socket/pid when mysqld is genuinely gone.
  _check_running
  _create_locks
  if [ -z "$(pgrep -f /usr/sbin/mysqld)" ]; then
    echo "MySQLD already stopped"
    _remove_locks
    return 0
  fi
  echo "Stopping MySQLD (db-only) ..."
  timeout 60 service mysql stop &> /dev/null
  if _mysqld_answering; then
    echo "MySQLD answering after stop (healthy respawn) -- leaving it"
    _remove_locks
    return 0
  fi
  if pgrep -f /usr/sbin/mysqld > /dev/null 2>&1; then
    pkill -TERM -f /usr/sbin/mysqld
    sleep 5
    if _mysqld_answering; then
      echo "MySQLD answering after TERM (healthy respawn) -- leaving it"
      _remove_locks
      return 0
    fi
    pkill -KILL -f /usr/sbin/mysqld
    sleep 2
  fi
  # Never de-socket a live server: only clear stale files once mysqld is truly gone.
  if [ -z "$(pgrep -f /usr/sbin/mysqld)" ]; then
    rm -f /run/mysqld/mysql*
  fi
  _remove_locks
  echo "MySQLD stopped (db-only)"
}

_re_start_mysqld_only() {
  _stop_mysqld_only
  _start_sql "chain"
  _remove_locks
  exit 0
}

case "$1" in
  restart)   _re_start_sql ;;
  start)     _start_sql "only" ;;
  stop)      _stop_sql "only" ;;
  dbrestart) _re_start_mysqld_only ;;
  *)         _re_start_sql
  ;;
esac


