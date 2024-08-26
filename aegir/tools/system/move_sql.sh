#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
  _B_NICE=${_B_NICE//[^0-9]/}
fi
if [ -z "${_B_NICE}" ]; then
  _B_NICE=10
fi

create_locks() {
  echo "Creating locks..."
  touch /run/boa_wait.pid
  touch /run/fmp_wait.pid
  touch /run/restarting_fmp_wait.pid
  touch /run/mysql_restart_running.pid
}

remove_locks() {
  echo "Removing locks..."
  [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
  rm -f /run/fmp_wait.pid
  rm -f /run/restarting_fmp_wait.pid
  rm -f /run/mysql_restart_running.pid
}

check_running() {
  if [ -e "/run/mysql_restart_running.pid" ]; then
    echo "MySQLD restart procedure in progress?"
    echo "Nothing to do, let's quit now. Bye!"
    exit 1
  fi
}

start_sql() {
  check_running
  create_locks

  _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
  if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
    echo "MySQLD already running?"
    echo "Nothing to do. Bye!"
    remove_locks
    [ "$1" != "chain" ] && exit 1
  fi

  echo "Starting MySQLD again..."
  renice ${_B_NICE} -p $$ &> /dev/null
  service mysql start &> /dev/null
  while [ -z "${_IS_MYSQLD_RUNNING}" ] \
    || [ ! -e "/run/mysqld/mysqld.sock" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    echo "Waiting for MySQLD graceful start..."
    sleep 3
  done
  echo "MySQLD started"

  remove_locks
  echo "MySQLD start procedure completed"
  [ "$1" != "chain" ] && exit 0
}

stop_sql() {
  check_running
  create_locks

  echo "Stopping Nginx now..."
  service nginx stop &> /dev/null
  until [ -z "${_IS_NGINX_RUNNING}" ]; do
    _IS_NGINX_RUNNING=$(ps aux | grep '[n]ginx' | awk '{print $2}' 2>&1)
    echo "Waiting for Nginx graceful shutdown..."
    sleep 1
  done
  killall nginx &> /dev/null
  echo "Nginx stopped"

  echo "Stopping all PHP-FPM instances now..."
  _PHP_V="83 82 81 80 74 73 72 71 70 56 55 54 53"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service php${e}-fpm force-quit &> /dev/null
    fi
  done
  until [ -z "${_IS_FPM_RUNNING}" ]; do
    _IS_FPM_RUNNING=$(ps aux | grep '[p]hp-fpm' | awk '{print $2}' 2>&1)
    echo "Waiting for PHP-FPM graceful shutdown..."
    sleep 1
  done
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "PHP-FPM stopped"

  _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
  if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
    _DBS_TEST=$(which mysql 2>&1)
    if [ ! -z "${_DBS_TEST}" ]; then
      _DB_SERVER_TEST=$(mysql -V 2>&1)
    fi
    if [[ "${_DB_SERVER_TEST}" =~ "Ver 8.3." ]]; then
      _DB_V=8.3
    elif [[ "${_DB_SERVER_TEST}" =~ "Ver 8.2." ]]; then
      _DB_V=8.2
    elif [[ "${_DB_SERVER_TEST}" =~ "Ver 8.1." ]]; then
      _DB_V=8.1
    elif [[ "${_DB_SERVER_TEST}" =~ "Ver 8.0." ]]; then
      _DB_V=8.0
    elif [[ "${_DB_SERVER_TEST}" =~ "Distrib 5.7." ]]; then
      _DB_V=5.7
    fi
    if [ ! -z "${_DB_V}" ]; then
      echo "Preparing MySQLD for quick shutdown..."
      _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
      _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
      mysql -u root -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_change_buffering = 'none';" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_io_capacity = 2000;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_io_capacity_max = 4000;" &> /dev/null
      if [ "${_DB_V}" = "5.7" ]; then
        mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
        mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_now = ON;" &> /dev/null
      fi
    fi
    mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 1;" &> /dev/null
    echo "Stopping MySQLD now..."
    service mysql stop &> /dev/null
  else
    echo "MySQLD already stopped?"
    echo "Nothing to do. Bye!"
    remove_locks
    [ "$1" != "chain" ] && exit 1
  fi

  until [ -z "${_IS_MYSQLD_RUNNING}" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    echo "Waiting for MySQLD graceful shutdown..."
    sleep 3
  done
  echo "MySQLD stopped"

  remove_locks
  echo "MySQLD stop procedure completed"
  [ "$1" != "chain" ] && exit 0
}

restart_sql() {
  stop_sql "chain"
  start_sql "chain"
  remove_locks
  exit 0
}

case "$1" in
  restart) restart_sql ;;
  start)   start_sql "only" ;;
  stop)    stop_sql "only" ;;
  *)       restart_sql
  ;;
esac

###EOF2024###
