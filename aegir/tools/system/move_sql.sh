#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

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
  echo "Creating locks.."
  touch /var/run/boa_wait.pid
  touch /var/run/fmp_wait.pid
  touch /var/run/mysql_restart_running.pid
}

remove_locks() {
  echo "Removing locks.."
  rm -f /var/run/boa_wait.pid
  rm -f /var/run/fmp_wait.pid
  rm -f /var/run/mysql_restart_running.pid
}

check_running() {
  if [ -e "/var/run/mysql_restart_running.pid" ]; then
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

  echo "Starting MySQLD again.."
  renice ${_B_NICE} -p $$ &> /dev/null
  service mysql start &> /dev/null
  until [ ! -z "${_IS_MYSQLD_RUNNING}" ] \
    && [ -e "/var/run/mysqld/mysqld.sock" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    echo "Waiting for MySQLD graceful start.."
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

  echo "Stopping Nginx now.."
  service nginx stop &> /dev/null
  until [ -z "${_IS_NGINX_RUNNING}" ]; do
    _IS_NGINX_RUNNING=$(ps aux | grep '[n]ginx' | awk '{print $2}' 2>&1)
    echo "Waiting for Nginx graceful shutdown.."
    sleep 3
  done
  echo "Nginx stopped"

  echo "Stopping all PHP-FPM instances now.."
  if [ -e "/etc/init.d/php74-fpm" ]; then
    service php74-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php73-fpm" ]; then
    service php73-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php72-fpm" ]; then
    service php72-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php71-fpm" ]; then
    service php71-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php70-fpm" ]; then
    service php70-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php56-fpm" ]; then
    service php56-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php55-fpm" ]; then
    service php55-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php54-fpm" ]; then
    service php54-fpm stop &> /dev/null
  fi
  if [ -e "/etc/init.d/php53-fpm" ]; then
    service php53-fpm stop &> /dev/null
  fi
  # kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}')
  until [ -z "${_IS_FPM_RUNNING}" ]; do
    _IS_FPM_RUNNING=$(ps aux | grep '[p]hp-fpm' | awk '{print $2}' 2>&1)
    echo "Waiting for PHP-FPM graceful shutdown.."
    sleep 3
  done
  echo "PHP-FPM stopped"

  _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
  if [ ! -z "${_IS_MYSQLD_RUNNING}" ]; then
    if [ "${_DB_SERIES}" = "10.3" ] \
      || [ "${_DB_SERIES}" = "10.2" ] \
      || [ "${_DB_SERIES}" = "10.4" ] \
      || [ "${_DB_SERIES}" = "5.7" ]; then
      echo "Preparing MySQLD for quick shutdown.."
      mysql -u root -e "SET GLOBAL innodb_max_dirty_pages_pct = 0;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_io_capacity = 2000;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_io_capacity_max = 4000;" &> /dev/null
      mysql -u root -e "SET GLOBAL innodb_buffer_pool_dump_pct = 100;" &> /dev/null
    fi
    echo "Stopping MySQLD now.."
    service mysql stop &> /dev/null
  else
    echo "MySQLD already stopped?"
    echo "Nothing to do. Bye!"
    remove_locks
    [ "$1" != "chain" ] && exit 1
  fi

  until [ -z "${_IS_MYSQLD_RUNNING}" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    echo "Waiting for MySQLD graceful shutdown.."
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

###EOF2020###
