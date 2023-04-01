#
# Only supported upgrade path allowed.
sql_strict_upgrade_path() {
  _DBS_TEST=$(which mysql 2>&1)
  if [ ! -z "${_DBS_TEST}" ]; then
    _NOW_DB_V=$(mysql -V 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f6 \
      | awk '{ print $1}' \
      | cut -d"-" -f1 \
      | awk '{ print $1}' \
      | sed "s/[\,']//g" 2>&1)
  fi
  if [ ! -z "${_NOW_DB_V}" ]; then
    if [[ ! "${_NOW_DB_V}" =~ (^)"${_DB_SERIES}" ]]; then
      _SQL_FORCE_REINSTALL=YES
    fi
  else
    _SQL_FORCE_REINSTALL=YES
  fi
  if [[ "${_DB_SERVER_TEST}" =~ "Distrib ${_DB_SERIES}." ]]; then
    _SQL_UPGRADE=NO
  else
    _SQL_UPGRADE=YES
  fi
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _ALL_FORCE_REINSTALL=YES
  else
    _ALL_FORCE_REINSTALL=NO
  fi
  if [[ "${_DB_SERVER_TEST}" =~ "MariaDB" ]] \
    || [[ "${_DB_SERVER_TEST}" =~ "Distrib ${_DB_SERIES}." ]]; then
    if [ "${_DB_SERIES}" = "5.7" ]; then
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib 5.7." ]]; then
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
      elif [[ "${_DB_SERVER_TEST}" =~ "Distrib 10.2." ]]; then
        _SQL_UPGRADE=YES
        _USE_MYSQLTUNER=YES
      else
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
        msg "WARN: SQL upgrade to ${_DB_SERIES} from ${_NOW_DB_V} not supported"
        msg "HINT: You can upgrade to ${_DB_SERIES} only from 10.2"
      fi
    elif [ "${_DB_SERIES}" = "10.4" ]; then
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib 10.4." ]]; then
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
      elif [[ "${_DB_SERVER_TEST}" =~ "Distrib 10.3." ]]; then
        _SQL_UPGRADE=YES
      else
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
        msg "WARN: SQL upgrade to ${_DB_SERIES} from ${_NOW_DB_V} not supported"
        msg "HINT: You can upgrade to ${_DB_SERIES} only from 10.3"
      fi
    elif [ "${_DB_SERIES}" = "10.3" ]; then
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib 10.3." ]]; then
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
      elif [[ "${_DB_SERVER_TEST}" =~ "Distrib 10.2." ]]; then
        _SQL_UPGRADE=YES
      else
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
        msg "WARN: SQL upgrade to ${_DB_SERIES} from ${_NOW_DB_V} not supported"
        msg "HINT: You can upgrade to ${_DB_SERIES} only from 10.2"
      fi
    elif [ "${_DB_SERIES}" = "10.2" ]; then
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib 10.2." ]]; then
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
      elif [[ "${_DB_SERVER_TEST}" =~ "Distrib 10.1." ]]; then
        _SQL_UPGRADE=YES
      else
        _SQL_UPGRADE=NO
        _SQL_FORCE_REINSTALL=NO
        _ALL_FORCE_REINSTALL=NO
        msg "WARN: SQL upgrade to ${_DB_SERIES} from ${_NOW_DB_V} not supported"
        msg "HINT: You can upgrade to ${_DB_SERIES} only from 10.1"
      fi
    else
      _SQL_UPGRADE=NO
      _SQL_FORCE_REINSTALL=NO
      _ALL_FORCE_REINSTALL=NO
      msg "WARN: SQL upgrade to ${_DB_SERIES} from ${_NOW_DB_V} not supported"
      msg "HINT: You can upgrade to ${_DB_SERIES} only from 10.1"
    fi
  fi
  if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
    _SQL_UPGRADE=YES
  fi
}

#
# Update innodb_log_file_size.
update_innodb_log_file_size() {
  msg "INFO: InnoDB log file will be set to ${_INNODB_LOG_FILE_SIZE_MB}..."
  if [[ ! "${_DB_SERVER}" =~ "Percona" ]]; then
    sed -i "s/^show_compatibility_56/#show_compatibility_56/g" /etc/mysql/my.cnf &> /dev/null
      wait
  fi
  mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 0;" &> /dev/null
  mrun "bash /var/xdrago/move_sql.sh stop" &> /dev/null
  _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
  if [ -z "${_IS_MYSQLD_RUNNING}" ]; then
    mkdir -p ${vBs}/old-sql-ib-log-${_NOW}
    mrun "sleep 1"
    mv -f /var/lib/mysql/ib_logfile0 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    mv -f /var/lib/mysql/ib_logfile1 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    sed -i "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" /etc/mysql/my.cnf &> /dev/null
      wait
    mrun "bash /var/xdrago/move_sql.sh start" &> /dev/null
  else
    msg "INFO: Waiting 180s for ${_DB_SERVER} clean shutdown..."
    mrun "bash /var/xdrago/move_sql.sh stop" &> /dev/null
    mrun "sleep 180"
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    if [ -z "${_IS_MYSQLD_RUNNING}" ]; then
      mkdir -p ${vBs}/old-sql-ib-log-${_NOW}
      mrun "sleep 1"
      mv -f /var/lib/mysql/ib_logfile0 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      mv -f /var/lib/mysql/ib_logfile1 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      sed -i "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" /etc/mysql/my.cnf &> /dev/null
        wait
      mrun "bash /var/xdrago/move_sql.sh start" &> /dev/null
    else
      msg "WARN: ${_DB_SERVER} refused to stop, InnoDB log file size not updated"
      mrun "sleep 5"
    fi
  fi
}

#
# Update SQL Config.
update_sql_conf() {
  sed -i "s/.*innodb_force_recovery/#innodb_force_recovery/g" /etc/mysql/my.cnf &> /dev/null
    wait
  if [[ ! "${_DB_SERVER}" =~ "Percona" ]]; then
    sed -i "s/^show_compatibility_56/#show_compatibility_56/g" /etc/mysql/my.cnf &> /dev/null
      wait
  fi
  # if [ "${_DB_SERIES}" = "10.4" ]; then
  #   sed -i "s/.*innodb-defragment/innodb-defragment/g" /etc/mysql/my.cnf &> /dev/null
  #     wait
  # fi
  sed -i "s/.*innodb_corrupt_table_action/#innodb_corrupt_table_action/g" /etc/mysql/my.cnf &> /dev/null
    wait
  sed -i "s/^thread_concurrency.*//g" /etc/mysql/my.cnf &> /dev/null
    wait
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ] \
    || [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
    || [[ "${_THISHOST}" =~ ".o8.io" ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
    || [ "${_VMFAMILY}" = "VS" ]; then
    if [ "${_CUSTOM_CONFIG_SQL}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      _INNODB_LOG_FILE_SIZE=${_INNODB_LOG_FILE_SIZE//[^0-9]/}
      if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ]; then
        if [ "${_INNODB_LOG_FILE_SIZE}" -ge "50" ]; then
          _INNODB_LOG_FILE_SIZE_MB="${_INNODB_LOG_FILE_SIZE}M"
          _INNODB_LOG_FILE_SIZE_TEST=$(grep "^innodb_log_file_size" \
            ${vBs}/dragon/t/my.cnf-pre-${_X_VERSION}-${_NOW} 2>&1)
          if [[ "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "= ${_INNODB_LOG_FILE_SIZE_MB}" ]]; then
            _INNODB_LOG_FILE_SIZE_SAME=YES
          else
            _INNODB_LOG_FILE_SIZE_SAME=NO
          fi
        fi
      fi
      sed -i "s/.*slow_query_log/#slow_query_log/g"           /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/.*long_query_time/#long_query_time/g"         /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/.*slow_query_log_file/#slow_query_log_file/g" /etc/mysql/my.cnf &> /dev/null
        wait
      if [ ! -e "/etc/mysql/skip-name-resolve.txt" ]; then
        sed -i "s/.*skip-name-resolve/#skip-name-resolve/g"   /etc/mysql/my.cnf &> /dev/null
          wait
      fi
    fi
  fi
  mv -f /etc/mysql/my.cnf-pre* ${vBs}/dragon/t/ &> /dev/null
  sed -i "s/.*default-table-type/#default-table-type/g" /etc/mysql/my.cnf &> /dev/null
    wait
  sed -i "s/.*language/#language/g" /etc/mysql/my.cnf &> /dev/null
    wait
  sed -i "s/.*innodb_lazy_drop_table.*//g" /etc/mysql/my.cnf &> /dev/null
    wait
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ]; then
    if [ "${_DB_BINARY_LOG}" = "NO" ]; then
      bash /var/xdrago/purge_binlogs.sh &> /dev/null
      sed -i "s/.*purge_binlogs.*//g" /var/spool/cron/crontabs/root
        wait
      sed -i "/^$/d" /var/spool/cron/crontabs/root
        wait
      sed -i "s/^log_bin/#log_bin/g"                   /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/^expire_logs_days/#expire_logs_days/g" /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/^max_binlog_size/#max_binlog_size/g"   /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/^binlog_row_image/#binlog_row_image/g" /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/^binlog_format/#binlog_format/g"       /etc/mysql/my.cnf &> /dev/null
        wait
    elif [ "${_DB_BINARY_LOG}" = "YES" ]; then
      sed -i "s/.*log_bin/log_bin/g"                   /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/.*expire_logs_days/expire_logs_days/g" /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/.*max_binlog_size/max_binlog_size/g"   /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/.*binlog_row_image/binlog_row_image/g" /etc/mysql/my.cnf &> /dev/null
        wait
      sed -i "s/.*binlog_format/binlog_format/g"       /etc/mysql/my.cnf &> /dev/null
        wait
    fi
    _LEGACY_CLSTR=NO
    if [ -f "/root/.mstr.clstr.cnf" ] \
      || [ -f "/root/.wbhd.clstr.cnf" ] \
      || [ -f "/root/.dbhd.clstr.cnf" ]; then
      _LEGACY_CLSTR=YES
    fi
    if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ] && [ "${_LEGACY_CLSTR}" = "NO" ]; then
      if [ "${_INNODB_LOG_FILE_SIZE}" -ge "50" ]; then
        _INNODB_LOG_FILE_SIZE_MB="${_INNODB_LOG_FILE_SIZE}M"
        _INNODB_LOG_FILE_SIZE_TEST=$(grep "^innodb_log_file_size" \
          /etc/mysql/my.cnf 2>&1)
        if [[ "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "= ${_INNODB_LOG_FILE_SIZE_MB}" ]]; then
          _DO_NOTHING=YES
        else
          if [ "${_INNODB_LOG_FILE_SIZE_SAME}" = "YES" ]; then
            sed -i "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" /etc/mysql/my.cnf &> /dev/null
              wait
          else
            update_innodb_log_file_size
          fi
        fi
      fi
    fi
  fi
}

#
#
check_mysqld_running() {
  until [ ! -z "${_IS_MYSQLD_RUNNING}" ] \
    && [ -e "/var/run/mysqld/mysqld.sock" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    msg "INFO: Waiting for MySQLD availability before tune_sql_memory_limits..."
    sleep 5
    service mysql start &> /dev/null
  done
}

#
# Tune memory limits for SQL server.
tune_sql_memory_limits() {
  check_mysqld_running
  if [ "${_DB_SERVER}" = "MariaDB" ]; then
    sed -i "s/.*check_for_crashed_tables/#check_for_crashed_tables/g" \
      /etc/mysql/debian-start &> /dev/null
    wait
  fi
  if [ ! -e "${vBs}/dragon/t/my.cnf-pre-${_X_VERSION}-${_NOW}" ]; then
    mkdir -p ${vBs}/dragon/t/
    if [ -e "/etc/mysql/my.cnf" ]; then
      cp -af /etc/mysql/my.cnf ${vBs}/dragon/t/my.cnf-pre-${_X_VERSION}-${_NOW}
    fi
  fi
  if [ "${_CUSTOM_CONFIG_SQL}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    cp -af ${locCnf}/my.cnf.txt /etc/mysql/my.cnf
  fi
  if [[ ! "${_DB_SERVER}" =~ "Percona" ]]; then
    sed -i "s/^show_compatibility_56/#show_compatibility_56/g" /etc/mysql/my.cnf &> /dev/null
      wait
  fi
  # https://raw.githubusercontent.com/major/MySQLTuner-perl/master/mysqltuner.pl
  pthTun="/var/opt/mysqltuner.pl"
  outTun="/var/opt/mysqltuner-${_X_VERSION}-${_NOW}.txt"
  if [ -e "/root/.mstr.clstr.cnf" ] \
    || [ -e "/root/.wbhd.clstr.cnf" ] \
    || [ -e "/root/.dbhd.clstr.cnf" ]; then
    _GALERA_COMP=NO
  fi
  if [ ! -e "${outTun}" ] \
    && [ "${_USE_MYSQLTUNER}" != "NO" ] \
    && [ "${_STATUS}" = "UPGRADE" ] \
    && [ -z "${_GALERA_COMP}" ]; then
    msg "INFO: Running MySQLTuner check on all databases..."
    msg "NOTE! This step may take a LONG time, please wait..."
    _MYSQLTUNER_TEST_RESULT=OK
    rm -f /var/opt/mysqltuner*
    curl ${crlGet} "${urlDev}/mysqltuner.pl.${_MYSQLTUNER_VRN}" -o ${pthTun}
    if [ ! -e "${pthTun}" ]; then
      curl ${crlGet} "${urlDev}/mysqltuner.pl" -o ${pthTun}
    fi
    if [ -e "${pthTun}" ]; then
      perl ${pthTun} > ${outTun} 2>&1
    fi
  fi
  if [ -e "${pthTun}" ] \
    && [ -e "${outTun}" ] \
    && [ "${_USE_MYSQLTUNER}" != "NO" ] \
    && [ "${_STATUS}" = "UPGRADE" ]; then
    _REC_MYISAM_MEM=$(cat ${outTun} \
      | grep "Data in MyISAM tables" \
      | cut -d: -f2 \
      | awk '{ print $1}' 2>&1)
    _REC_INNODB_MEM=$(cat ${outTun} \
      | grep "data size:" \
      | cut -d/ -f3 \
      | awk '{ print $1}' 2>&1)
    _MYSQLTUNER_TEST=$(cat ${outTun} 2>&1)
    cp -a ${outTun} ${pthLog}/
    if [ -z "${_REC_INNODB_MEM}" ] \
      || [[ "${_MYSQLTUNER_TEST}" =~ "Cannot calculate MyISAM index" ]] \
      || [[ "${_MYSQLTUNER_TEST}" =~ "InnoDB is enabled but isn" ]]; then
      _MYSQLTUNER_TEST_RESULT=FAIL
      msg "ALRT! The MySQLTuner test failed!"
      msg "ALRT! Please review ${outTun}"
      msg "ALRT! We will use some sane SQL defaults instead, do not worry!"
    fi
    ###--------------------###
    if [ ! -z "${_REC_MYISAM_MEM}" ] \
      && [ "${_MYSQLTUNER_TEST_RESULT}" = "OK" ]; then
      _RAW_MYISAM_MEM=$(echo ${_REC_MYISAM_MEM} | sed "s/[A-Z]//g" 2>&1)
      if [[ "${_REC_MYISAM_MEM}" =~ "G" ]]; then
        _RAW_MYISAM_MEM=$(echo ${_RAW_MYISAM_MEM} | awk '{print int($1+0.6)}' 2>&1)
        _RAW_MYISAM_MEM=$(echo "${_RAW_MYISAM_MEM} * 1024" | bc -l 2>&1)
      elif [[ "${_REC_MYISAM_MEM}" =~ "M" ]]; then
        _RAW_MYISAM_MEM=$(echo ${_RAW_MYISAM_MEM} | awk '{print int($1+0.6)}' 2>&1)
        _RAW_MYISAM_MEM=$(echo "${_RAW_MYISAM_MEM} * 1" | bc -l 2>&1)
      fi
      _RAW_MYISAM_MEM=$(echo "(${_RAW_MYISAM_MEM}+0.5)/1" | bc 2>&1)
      if [ "${_RAW_MYISAM_MEM}" -gt "${_USE_SQL}" ]; then
        _USE_MYISAM_MEM="${_USE_SQL}"
      else
        _RAW_MYISAM_MEM=$(echo "scale=2; (${_RAW_MYISAM_MEM} * 1.1)" | bc 2>&1)
        _USE_MYISAM_MEM=$(echo "(${_RAW_MYISAM_MEM}+0.5)/1" | bc 2>&1)
      fi
      if [ "${_USE_MYISAM_MEM}" -lt "256" ] \
        || [ -z "${_USE_MYISAM_MEM}" ]; then
        _USE_MYISAM_MEM="${_USE_SQL}"
      fi
      _USE_MYISAM_MEM="${_USE_MYISAM_MEM}M"
        sed -i "s/^key_buffer_size.*/key_buffer_size         = ${_USE_MYISAM_MEM}/g"  /etc/mysql/my.cnf &> /dev/null
        wait
    else
      _USE_MYISAM_MEM="${_USE_SQL}M"
      if [ "${_MYSQLTUNER_TEST_RESULT}" = "FAIL" ]; then
        msg "ALRT! _USE_MYISAM_MEM is ${_USE_MYISAM_MEM} because _REC_MYISAM_MEM was empty!"
      fi
        sed -i "s/^key_buffer_size.*/key_buffer_size         = ${_USE_MYISAM_MEM}/g"  /etc/mysql/my.cnf &> /dev/null
        wait
    fi
    ###--------------------###
    if [ ! -z "${_REC_INNODB_MEM}" ] \
      && [ "${_MYSQLTUNER_TEST_RESULT}" = "OK" ]; then
      _RAW_INNODB_MEM=$(echo ${_REC_INNODB_MEM} | sed "s/[A-Z]//g" 2>&1)
      if [[ "${_REC_INNODB_MEM}" =~ "G" ]]; then
        _RAW_INNODB_MEM=$(echo ${_RAW_INNODB_MEM} | awk '{print int($1+0.6)}' 2>&1)
        _RAW_INNODB_MEM=$(echo "${_RAW_INNODB_MEM} * 1024" | bc -l 2>&1)
      elif [[ "${_REC_INNODB_MEM}" =~ "M" ]]; then
        _RAW_INNODB_MEM=$(echo ${_RAW_INNODB_MEM} | awk '{print int($1+0.6)}' 2>&1)
        _RAW_INNODB_MEM=$(echo "${_RAW_INNODB_MEM} * 1" | bc -l 2>&1)
      fi
      _RAW_INNODB_MEM=$(echo "(${_RAW_INNODB_MEM}+0.5)/1" | bc 2>&1)
      if [ "${_RAW_INNODB_MEM}" -gt "${_USE_SQL}" ] \
        || [ -z "${_USE_INNODB_MEM}" ] \
        || [ "${_RAW_INNODB_MEM}" -lt "512" ]; then
        _USE_INNODB_MEM="${_USE_SQL}"
      else
        _RAW_INNODB_MEM=$(echo "scale=2; (${_RAW_INNODB_MEM} * 1.1)" | bc 2>&1)
        _USE_INNODB_MEM=$(echo "(${_RAW_INNODB_MEM}+0.5)/1" | bc 2>&1)
      fi
      _INNODB_BPI=$(echo "scale=0; ${_USE_INNODB_MEM}/1024/2" | bc 2>&1)
      if [ "${_INNODB_BPI}" -lt "1" ] || [ -z "${_INNODB_BPI}" ]; then
        _INNODB_BPI="1"
      fi
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/^innodb_buffer_pool_instances.*/innodb_buffer_pool_instances = ${_INNODB_BPI}/g" /etc/mysql/my.cnf &> /dev/null
          wait
        sed -i "s/^innodb_page_cleaners.*/innodb_page_cleaners = ${_INNODB_BPI}/g" /etc/mysql/my.cnf &> /dev/null
          wait
      fi
      _INNODB_LOG_FILE_SIZE=$(echo "scale=0; ${_USE_INNODB_MEM}/4/40*40" | bc 2>&1)
      _DB_COUNT=$(ls /var/lib/mysql/ | wc -l 2>&1)
      if [ "${_DB_COUNT}" -gt "3" ]; then
        if [ "${_INNODB_LOG_FILE_SIZE}" -gt "64" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "256" ]; then
          _INNODB_LOG_FILE_SIZE=256
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "256" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "512" ]; then
          _INNODB_LOG_FILE_SIZE=512
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "512" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "1024" ]; then
          _INNODB_LOG_FILE_SIZE=1024
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "1024" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "2048" ]; then
          _INNODB_LOG_FILE_SIZE=2048
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "2048" ]; then
          _INNODB_LOG_FILE_SIZE=2048
        fi
      fi
      if [ "${_INNODB_LOG_FILE_SIZE}" -le "64" ] \
        || [ -z "${_INNODB_LOG_FILE_SIZE}" ]; then
        _INNODB_LOG_FILE_SIZE=64
      fi
      _USE_INNODB_MEM="${_USE_INNODB_MEM}M"
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${_USE_INNODB_MEM}/g"  /etc/mysql/my.cnf &> /dev/null
      fi
        wait
    else
      _USE_INNODB_MEM="${_USE_SQL}M"
      _INNODB_LOG_FILE_SIZE=$(echo "scale=0; ${_USE_SQL}/4/40*40" | bc 2>&1)
      _DB_COUNT=$(ls /var/lib/mysql/ | wc -l 2>&1)
      if [ "${_DB_COUNT}" -gt "3" ]; then
        if [ "${_INNODB_LOG_FILE_SIZE}" -gt "64" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "256" ]; then
          _INNODB_LOG_FILE_SIZE=256
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "256" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "512" ]; then
          _INNODB_LOG_FILE_SIZE=512
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "512" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "1024" ]; then
          _INNODB_LOG_FILE_SIZE=1024
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "1024" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -le "2048" ]; then
          _INNODB_LOG_FILE_SIZE=2048
        elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "2048" ]; then
          _INNODB_LOG_FILE_SIZE=2048
        fi
      fi
      if [ "${_INNODB_LOG_FILE_SIZE}" -le "64" ] \
        || [ -z "${_INNODB_LOG_FILE_SIZE}" ]; then
        _INNODB_LOG_FILE_SIZE=64
      fi
      msg "ALRT! _USE_INNODB_MEM is ${_USE_INNODB_MEM} because _REC_INNODB_MEM was empty!"
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${_USE_INNODB_MEM}/g"  /etc/mysql/my.cnf &> /dev/null
      fi
        wait
    fi
  else
    _THIS_USE_MEM="${_USE_SQL}M"
    if [ "${_MYSQLTUNER_TEST_RESULT}" = "FAIL" ] \
      && [ "${_STATUS}" = "UPGRADE" ] \
      && [ -z "${_GALERA_COMP}" ]; then
      msg "ALRT! _USE_MYISAM_MEM is ${_THIS_USE_MEM} because _REC_MYISAM_MEM was empty!"
      msg "ALRT! _USE_INNODB_MEM is ${_THIS_USE_MEM} because _REC_INNODB_MEM was empty!"
    fi
    _INNODB_LOG_FILE_SIZE=$(echo "scale=0; ${_USE_SQL}/4/40*40" | bc 2>&1)
    _DB_COUNT=$(ls /var/lib/mysql/ | wc -l 2>&1)
    if [ "${_DB_COUNT}" -gt "3" ]; then
      if [ "${_INNODB_LOG_FILE_SIZE}" -gt "64" ] \
        && [ "${_INNODB_LOG_FILE_SIZE}" -le "256" ]; then
        _INNODB_LOG_FILE_SIZE=256
      elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "256" ] \
        && [ "${_INNODB_LOG_FILE_SIZE}" -le "512" ]; then
        _INNODB_LOG_FILE_SIZE=512
      elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "512" ] \
        && [ "${_INNODB_LOG_FILE_SIZE}" -le "1024" ]; then
        _INNODB_LOG_FILE_SIZE=1024
      elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "1024" ] \
        && [ "${_INNODB_LOG_FILE_SIZE}" -le "2048" ]; then
        _INNODB_LOG_FILE_SIZE=2048
      elif [ "${_INNODB_LOG_FILE_SIZE}" -gt "2048" ]; then
        _INNODB_LOG_FILE_SIZE=2048
      fi
    fi
    if [ "${_INNODB_LOG_FILE_SIZE}" -le "64" ] \
      || [ -z "${_INNODB_LOG_FILE_SIZE}" ]; then
      _INNODB_LOG_FILE_SIZE=64
    fi
    if [ -e "/etc/mysql/my.cnf" ]; then
      sed -i "s/= 181/= ${_USE_SQL}/g"  /etc/mysql/my.cnf &> /dev/null
    fi
      wait
  fi
}

prep_for_install_db_sql() {
  if [ "${_OSR}" = "chimaera" ]; then
    _SQL_OSR=bullseye
  elif [ "${_OSR}" = "beowulf" ]; then
    _SQL_OSR=buster
  else
    _SQL_OSR="${_OSR}"
  fi
  _DBS_TEST=$(which mysql 2>&1)
  if [ ! -z "${_DBS_TEST}" ]; then
    _NOW_DB_V=$(mysql -V 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f6 \
      | awk '{ print $1}' \
      | cut -d"-" -f1 \
      | awk '{ print $1}' \
      | sed "s/[\,']//g" 2>&1)
  fi
  if [ -e "/usr/bin/php" ]; then
    _PHP_MYSQLND_TEST=$(/usr/bin/php -i | grep "with-mysqli=mysqlnd" 2>&1)
    if [ -z "${_PHP_MYSQLND_TEST}" ]; then
      _SQL_MAJOR_UP_ALLOW=NO
    else
      _SQL_MAJOR_UP_ALLOW=YES
    fi
  else
    _SQL_MAJOR_UP_ALLOW=YES
  fi
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  cd /var/opt
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ] \
    || [ "${_OSR}" = "trusty" ]; then
    st_runner "${_INSTAPP} software-properties-common dirmngr" 2> /dev/null
  fi
  if [ "${_DB_SERVER}" = "Percona" ] || [ "${_DB_SERIES}" = "5.7" ]; then
    _KEYS_SIG="8507EFA5"
    _KEYS_SERVER_TEST=FALSE
    until [[ "${_KEYS_SERVER_TEST}" =~ "Percona" ]]; do
      msg "INFO: Retrieving ${_KEYS_SIG} key.."
      cd /var/opt
      _KEYS_FILE_TEST=FALSE
      until [[ "${_KEYS_FILE_TEST}" =~ "GnuPG" ]]; do
        rm -f percona-key.gpg*
        wget -q -U iCab ${urlDev}/percona-key.gpg
        _KEYS_FILE_TEST=$(grep GnuPG percona-key.gpg 2>&1)
        sleep 5
      done
      cat percona-key.gpg | ${_GPG} --import &> /dev/null
      rm -f percona-key.gpg*
      ${_GPG} --keyserver pgpkeys.mit.edu --recv-key ${_KEYS_SIG} &> /dev/null
      ${_GPG} -a --export ${_KEYS_SIG} | apt-key add - &> /dev/null
      _KEYS_SERVER_TEST=$(${_GPG} --list-keys ${_KEYS_SIG} 2>&1)
      sleep 2
      if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
        kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
        echo "$(date 2>&1) Too many dirmngr processes killed" >> \
          /var/xdrago/log/dirmngr-count.kill.log
      fi
      if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
        kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
        echo "$(date 2>&1) Too many gpg-agent processes killed" >> \
          /var/xdrago/log/gpg-agent-count.kill.log
      fi
    done
    ${_APT_UPDATE} -qq &> /dev/null
  else
    _KEYS_SIG="C74CD1D8"
    _KEYS_SERVER_TEST=FALSE
    until [[ "${_KEYS_SERVER_TEST}" =~ "MariaDB" ]]; do
      msg "INFO: Retrieving ${_KEYS_SIG} key.."
      ${_GPG} --keyserver pgpkeys.mit.edu --recv-key ${_KEYS_SIG} &> /dev/null
      ${_GPG} -a --export ${_KEYS_SIG} | apt-key add - &> /dev/null
      _KEYS_SERVER_TEST=$(${_GPG} --list-keys ${_KEYS_SIG} 2>&1)
      sleep 2
      if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
        kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
        echo "$(date 2>&1) Too many dirmngr processes killed" >> \
          /var/xdrago/log/dirmngr-count.kill.log
      fi
      if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
        kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
        echo "$(date 2>&1) Too many gpg-agent processes killed" >> \
          /var/xdrago/log/gpg-agent-count.kill.log
      fi
    done
    ${_APT_UPDATE} -qq &> /dev/null
  fi
  _KEYS_SIG=""
  _KEYS_SERVER_TEST=FALSE
  if [ "${_THIS_OS}" = "Debian" ] || [ "${_THIS_OS}" = "Devuan" ]; then
    _OSN=debian
  elif [ "${_THIS_OS}" = "Ubuntu" ]; then
    _OSN=ubuntu
  fi
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ] \
    || [ "${_OSR}" = "trusty" ]; then
    if [ -e "/root/.mstr.clstr.cnf" ] \
      || [ -e "/root/.wbhd.clstr.cnf" ] \
      || [ -e "/root/.dbhd.clstr.cnf" ]; then
      _DBS_VRN="${_GALERA_10_VRN}"
    else
      if [ "${_DB_SERIES}" = "10.2" ]; then
        _DB_SERVER=MariaDB
        _DBS_VRN="${_MARIADB_10_2_VRN}"
      elif [ "${_DB_SERIES}" = "10.3" ]; then
        _DB_SERVER=MariaDB
        _DBS_VRN="${_MARIADB_10_3_VRN}"
      elif [ "${_DB_SERIES}" = "10.4" ]; then
        _DB_SERVER=MariaDB
        _DBS_VRN="${_MARIADB_10_4_VRN}"
      elif [ "${_DB_SERIES}" = "5.7" ] \
        && [ "${_SQL_MAJOR_UP_ALLOW}" = "YES" ]; then
        _DB_SERVER=Percona
        _DBS_VRN="${_PERCONA_5_7_VRN}"
        cd /var/opt
        rm -rf /var/opt/percona*
        rm -f /etc/apt/sources.list.d/mariadb.*
        rm -f /etc/apt/sources.list.d/percona-.*
        rm -f /etc/apt/sources.list.d/xtrabackup.*
        echo -e 'Package: *\nPin: release o=Percona Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00percona.pref
        aptLiSys="/etc/apt/sources.list"
        percList="${aptLiSys}.d/percona-release.list"
        percRepo="repo.percona.com/percona/apt"
        rm -f /etc/apt/sources.list.d/percona-original-release.list
        rm -f /etc/apt/sources.list.d/percona-prel-release.list
        rm -f /etc/apt/sources.list.d/percona-release.list.bak
        echo "## Percona APT Repository" > ${percList}
        echo "deb http://${percRepo} ${_SQL_OSR} main" >> ${percList}
        ${_APT_UPDATE} -qq &> /dev/null
      else
        _DB_SERVER=Percona
        _DB_SERIES=5.7
        _DBS_VRN="${_PERCONA_5_7_VRN}"
        rm -f /etc/apt/sources.list.d/mariadb.*
        rm -f /etc/apt/sources.list.d/percona-.*
        rm -f /etc/apt/sources.list.d/xtrabackup.*
        echo -e 'Package: *\nPin: release o=Percona Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00percona.pref
        cd /var/opt
        rm -rf /var/opt/percona*
        aptLiSys="/etc/apt/sources.list"
        percList="${aptLiSys}.d/percona-release.list"
        percRepo="repo.percona.com/percona/apt"
        rm -f /etc/apt/sources.list.d/percona-original-release.list
        rm -f /etc/apt/sources.list.d/percona-prel-release.list
        rm -f /etc/apt/sources.list.d/percona-release.list.bak
        echo "## Percona APT Repository" > ${percList}
        echo "deb http://${percRepo} ${_SQL_OSR} main" >> ${percList}
        ${_APT_UPDATE} -qq &> /dev/null
      fi
    fi
    msg "INFO: Installing ${_DB_SERVER} ${_DBS_VRN} in ${_THIS_OS}/${_OSR}"
  else
    if [ "${_DB_SERIES}" = "10.4" ] \
      || [ "${_DB_SERIES}" = "10.3" ] \
      || [ "${_DB_SERIES}" = "10.2" ] \
      || [ "${_DB_SERIES}" = "5.7" ]; then
      _DO_NOTHING=YES
    else
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
      msg "INFO: Forced ${_DB_SERVER} ${_DBS_VRN} in ${_THIS_OS}/${_OSR}"
    fi
    if [ -z "${_DB_SERIES}" ]; then
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
      msg "INFO: Forced ${_DB_SERVER} ${_DBS_VRN} in ${_THIS_OS}/${_OSR}"
    fi
  fi

  ### Only supported upgrade path allowed
  sql_strict_upgrade_path

  if [ "${_DB_SERVER}" = "MariaDB" ]; then
    aptRepo="${_DB_SRC}/pub/mariadb/repo/${_DB_SERIES}"
    aptLiDb="${aptLiSys}.d/mariadb.list"
    echo "## MariaDB APT Repository" > ${aptLiDb}
    echo "deb [arch=amd64,i386] http://${aptRepo}/${_OSN} ${_OSR} main" >> ${aptLiDb}
  fi
  rm -f /etc/apt/sources.list.d/percona-original-release.list
  rm -f /etc/apt/sources.list.d/percona-prel-release.list
  rm -f /etc/apt/sources.list.d/percona-release.list.bak
  percRepo="repo.percona.com/percona/apt"
  percList="${aptLiSys}.d/percona-release.list"
  echo "## Percona APT Repository" > ${percList}
  echo "deb http://${percRepo} ${_SQL_OSR} main" >> ${percList}
  if [ -e "/usr/bin/mytop" ]; then
    st_runner "${_RMAPP} mytop" &> /dev/null
    st_runner "apt-get purge mytop -y" &> /dev/null
    rm -f /usr/bin/mytop
  fi
  st_runner "${_APT_UPDATE} -qq" &> /dev/null
  if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    sed -i "s/.*innodb_force_recovery.*/innodb_force_recovery = 3/g" /etc/mysql/my.cnf &> /dev/null
      wait
  fi
  if [ "${_EASY_SETUP}" = "MSTR" ] \
    || [ "${_EASY_SETUP}" = "DBHD" ] \
    || [ "${_EASY_SETUP}" = "WBHD" ] \
    || [ -e "/etc/mysql/conf.d/galera.cnf" ] \
    || [ -e "/root/.mstr.clstr.cnf" ] \
    || [ -e "/root/.dbhd.clstr.cnf" ] \
    || [ -e "/root/.wbhd.clstr.cnf" ]; then
    SQLDEB="mariadb-galera-server"
  elif [ "${_DB_SERIES}" = "10.4" ]; then
    if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
      st_runner "${_RMAPP} mariadb-server-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.2" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.2" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.3" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.3" &> /dev/null
      st_runner "${_RMAPP} mariadb-server" &> /dev/null
    fi
    SQLDEB="mariadb-server"
  elif [ "${_DB_SERIES}" = "10.3" ]; then
    if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
      st_runner "${_RMAPP} mariadb-server-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.2" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.2" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.4" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.4" &> /dev/null
      st_runner "${_RMAPP} mariadb-server" &> /dev/null
    fi
    SQLDEB="mariadb-server"
  elif [ "${_DB_SERIES}" = "10.2" ]; then
    if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
      st_runner "${_RMAPP} mariadb-server-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.3" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.3" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.4" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.4" &> /dev/null
      st_runner "${_RMAPP} mariadb-server" &> /dev/null
    fi
    SQLDEB="mariadb-server"
  elif [ "${_DB_SERIES}" = "5.7" ]; then
    if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
      st_runner "${_RMAPP} mariadb-server-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-5.5" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.1" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.2" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.2" &> /dev/null
      st_runner "${_RMAPP} mariadb-server-10.3" &> /dev/null
      st_runner "${_RMAPP} mariadb-client-10.3" &> /dev/null
      st_runner "${_RMAPP} mariadb-server" &> /dev/null
    fi
    SQLDEB="percona-server-server-${_DB_SERIES}"
  else
    SQLDEB="mariadb-server"
  fi
  if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
    mkdir -p ${vBs}/old-sql-ib-log-${_NOW}
    mrun "sleep 1"
    mv -f /var/lib/mysql/ib_logfile0 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    mv -f /var/lib/mysql/ib_logfile1 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    mv -f /var/lib/mysql/aria_log.00000001 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    mv -f /var/lib/mysql/aria_log_control ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    sed -i "s/.*innodb-defragment.*/innodb_force_recovery = 3/g" /etc/mysql/my.cnf &> /dev/null
    sed -i "s/^thread_concurrency.*//g" /etc/mysql/my.cnf &> /dev/null
  fi
}

install_with_aptitude_sql() {
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ] \
    || [ "${_OSR}" = "trusty" ] \
    || [ "${_OSR}" = "precise" ]; then
    if [ "${_EASY_SETUP}" = "MSTR" ] \
      || [ "${_EASY_SETUP}" = "DBHD" ] \
      || [ "${_EASY_SETUP}" = "WBHD" ] \
      || [ -e "/etc/mysql/conf.d/galera.cnf" ] \
      || [ -e "/root/.mstr.clstr.cnf" ] \
      || [ -e "/root/.dbhd.clstr.cnf" ] \
      || [ -e "/root/.wbhd.clstr.cnf" ]; then
      msg "INFO: Installing ${_DB_SERVER} Galera Cluster..."
    else
      msg "INFO: Installing ${_DB_SERVER}..."
    fi
  else
    if [ "${_EASY_SETUP}" = "MSTR" ] \
      || [ "${_EASY_SETUP}" = "DBHD" ] \
      || [ "${_EASY_SETUP}" = "WBHD" ] \
      || [ -e "/etc/mysql/conf.d/galera.cnf" ] \
      || [ -e "/root/.mstr.clstr.cnf" ] \
      || [ -e "/root/.dbhd.clstr.cnf" ] \
      || [ -e "/root/.wbhd.clstr.cnf" ]; then
      msg "INFO: Installing ${_DB_SERVER} Galera Cluster..."
    else
      msg "INFO: Installing ${_DB_SERVER}..."
    fi
  fi
  prep_for_install_db_sql
  st_runner "${_INSTAPP} ${SQLDEB}" 2> /dev/null
  st_runner "${_INSTAPP} ${SQLDEB}" 2> /dev/null
  if [ ! -e "/usr/local/bin/mytop" ] && [ -e "/usr/bin/mysql" ]; then
    msg "INFO: Building MyTop from sources, please wait..."
    cd /var/opt
    rm -rf git*
    get_dev_src "mytop-1.6.tar.gz"
    cd /var/opt/mytop-1.6
    mrun "perl Makefile.PL" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
  fi
  if [ "${_EASY_SETUP}" = "DBHD" ] \
    || [ -e "/etc/mysql/conf.d/galera.cnf" ] \
    || [ -e "/root/.dbhd.clstr.cnf" ]; then
    if [[ "${_DB_SERVER_TEST}" =~ "${_DB_SERIES}" ]]; then
      msg "INFO: Running ${_DB_SERVER} system tables check..."
      if [ -x "/usr/bin/mariadb_upgrade" ]; then
        mrun "mariadb_upgrade --force" &> /dev/null
          wait
      elif [ -x "/usr/bin/mysql_upgrade" ]; then
        mrun "mysql_upgrade --force" &> /dev/null
          wait
      fi
    fi
  fi
  if [ "${_DB_SERVER}" = "Percona" ] \
    && [ "${_DB_SERIES}" = "5.7" ] \
    && [ "${_SQL_FORCE_REINSTALL}" = "YES" ]; then
    msg "INFO: Running ${_DB_SERVER} tables fix, check and upgrade..."
    rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
    mrun "mysqlcheck -A --auto-repair" &> /dev/null
      wait
    mrun "mysql_upgrade --force" &> /dev/null
      wait
    mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;" &> /dev/null
      wait
    mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;" &> /dev/null
      wait
    mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;" &> /dev/null
      wait
    mrun "mysql_upgrade --force" &> /dev/null
      wait
  fi
  usermod -aG users mysql
    wait
}

#
# Forced MySQL root password update.
forced_mysql_root_password_update() {
  mv -f /root/.my.cnf-pre-* ${vBs}/ &> /dev/null
  mv -f /root/.my.pass.txt-pre-* ${vBs}/ &> /dev/null
  touch /root/.my.pass.txt
  chmod 0600 /root/.my.pass.txt &> /dev/null
  _ESC_PASS=""
  _LEN_PASS=0
  _ESC="*.*"
  if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
    _PWD_CHARS=32
  elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
    _PWD_CHARS=8
  else
    _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
    if [ ! -z "${_STRONG_PASSWORDS}" ] \
      && [ "${_STRONG_PASSWORDS}" -gt "8" ]; then
      _PWD_CHARS="${_STRONG_PASSWORDS}"
    else
      _PWD_CHARS=8
    fi
    if [ ! -z "${_PWD_CHARS}" ] \
      && [ "${_PWD_CHARS}" -gt "128" ]; then
      _PWD_CHARS=128
    fi
  fi
  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt "8" ]; then
    if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
      _ESC_PASS="$(openssl rand -base64 32 2>&1)"
    else
      _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
    fi
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
  fi
  if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt "9" ]; then
    _ESC_PASS=$(shuf -zer -n19 {A..Z} {a..z} {0..9} | tr -d '\0' 2>&1)
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    _ESC_PASS=$(sanitize_string "${_ESC_PASS}" 2>&1)
  fi
  if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
    _ROOT_SQL_PASWD=$(cat /root/.my.cluster_root_pwd.txt 2>&1)
    _ROOT_SQL_PASWD=$(echo -n ${_ROOT_SQL_PASWD} | tr -d "\n" 2>&1)
    _ESC_PASS="${_ROOT_SQL_PASWD}"
  fi
  if [ ! -z "${_ESC_PASS}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "DBEF: ${_DB_SERVER} _ESC_PASS ${_ESC_PASS}"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
      if [ "${_DB_SERIES}" = "10.3" ] \
        || [ "${_DB_SERIES}" = "10.2" ]; then
        mysql -u root -e "SELECT user,host,password FROM mysql.user;"
      elif [ "${_DB_SERIES}" = "5.7" ]; then
        mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
      fi
    fi
    cp -af /root/.my.cnf /root/.my.cnf-pre-${_X_VERSION}-${_NOW}
    cp -af /root/.my.pass.txt /root/.my.pass.txt-pre-${_X_VERSION}-${_NOW}
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'localhost';"
      wait
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'localhost' WITH GRANT OPTION;"
      wait
    if [ "${_DB_SERIES}" = "5.7" ]; then
      mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
    else
      mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${_ESC_PASS}';"
    fi
      wait
    echo "[client]" > /root/.my.cnf
      wait
    echo "user=root" >> /root/.my.cnf
      wait
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      wait
    chmod 0600 /root/.my.cnf
      wait
    echo "db=mysql" > /root/.mytop
      wait
    chmod 0600 /root/.mytop
      wait
    echo "${_ESC_PASS}" > /root/.my.pass.txt
      wait
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';"
      wait
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'::1';"
      wait
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_MY_OWNIP}';"
      wait
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'127.0.0.1' WITH GRANT OPTION;"
      wait
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'::1' WITH GRANT OPTION;"
      wait
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_MY_OWNIP}' WITH GRANT OPTION;"
      wait
    if [ "${_DB_SERIES}" = "5.7" ]; then
      mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
        wait
      mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
        wait
      mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
        wait
    else
      mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${_ESC_PASS}';"
        wait
      mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED BY '${_ESC_PASS}';"
        wait
      mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED BY '${_ESC_PASS}';"
        wait
    fi
    mysqladmin flush-privileges
      wait
    mysqladmin flush-hosts
      wait
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "DAFT: ${_DB_SERVER} _ESC_PASS ${_ESC_PASS}"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'::1';"
      if [ "${_DB_SERIES}" = "10.3" ] \
        || [ "${_DB_SERIES}" = "10.2" ]; then
        mysql -u root -e "SELECT user,host,password FROM mysql.user;"
      elif [ "${_DB_SERIES}" = "5.7" ]; then
        mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
      fi
    fi
    echo " "
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
        msg "INFO: New secure random password for ${_DB_SERVER} generated"
      else
        msg "INFO: New random password for ${_DB_SERVER} generated"
      fi
    fi
  else
    msg "CRIT: _ESC_PASS empty or not generated, ignored, no changes"
  fi
}

install_db_server() {
  if [ "${_OSR}" = "chimaera" ]; then
    _SQL_OSR=bullseye
  elif [ "${_OSR}" = "beowulf" ]; then
    _SQL_OSR=buster
  else
    _SQL_OSR="${_OSR}"
  fi
  _THIS_DB_PORT=3306
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ -e "/usr/sbin/csf" ] \
      && [ -e "/etc/csf/csf.deny" ]; then
      service lfd stop &> /dev/null
      sleep 3
      kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
      killall sleep &> /dev/null
      rm -f /etc/csf/csf.error
      csf -x &> /dev/null
    fi
    install_with_aptitude_sql
  else
    if [ "${_UP_NRC}" = "YES" ]; then
      update_newrelic
    fi

    ### Only supported upgrade path allowed
    sql_strict_upgrade_path

    if_to_do_fix
    if [ "${_DO_FIX}" = "YES" ]; then
      _SQL_UPGRADE=NO
    fi
    if [ "${_DB_SERVER}" = "MariaDB" ]; then
      _DB_SRC="ftp.osuosl.org"
      _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} \
        ${aptLiSys}.d/mariadb.list 2>&1)
      _SQL_DEB_SRC_TEST_B=$(grep ${_OSR} \
        ${aptLiSys}.d/mariadb.list 2>&1)
    else
      _DB_SRC="repo.percona.com"
      _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} \
        ${aptLiSys}.d/percona-release.list 2>&1)
      _SQL_DEB_SRC_TEST_B=$(grep ${_OSR} \
        ${aptLiSys}.d/percona-release.list 2>&1)
    fi
    if [[ "${_SQL_DEB_SRC_TEST_A}" =~ "${_DB_SRC}" ]] \
      && [[ "${_SQL_DEB_SRC_TEST_B}" =~ "${_OSR}" ]]; then
      _SQL_DEB_SRC_UPDATE=NO
    else
      if [ "${_THIS_OS}" = "Debian" ] || [ "${_THIS_OS}" = "Devuan" ]; then
        _OSN=debian
      elif [ "${_THIS_OS}" = "Ubuntu" ]; then
        _OSN=ubuntu
      fi
      if [ "${_DB_SERVER}" = "MariaDB" ]; then
        aptRepo="${_DB_SRC}/pub/mariadb/repo/${_DB_SERIES}"
        aptLiDb="${aptLiSys}.d/mariadb.list"
        echo "## MariaDB APT Repository" > ${aptLiDb}
        echo "deb [arch=amd64,i386] http://${aptRepo}/${_OSN} ${_OSR} main" >> ${aptLiDb}
        rm -f /etc/apt/sources.list.d/percona-release.*
        rm -f /etc/apt/sources.list.d/xtrabackup.*
        rm -f /etc/apt/preferences.d/00percona.pref
      else
        cd /var/opt
        rm -rf /var/opt/percona*
        rm -f /etc/apt/sources.list.d/mariadb.*
        rm -f /etc/apt/sources.list.d/percona-.*
        rm -f /etc/apt/sources.list.d/xtrabackup.*
        echo -e 'Package: *\nPin: release o=Percona Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00percona.pref
        aptLiSys="/etc/apt/sources.list"
        percList="${aptLiSys}.d/percona-release.list"
        percRepo="repo.percona.com/percona/apt"
        rm -f /etc/apt/sources.list.d/percona-original-release.list
        rm -f /etc/apt/sources.list.d/percona-prel-release.list
        rm -f /etc/apt/sources.list.d/percona-release.list.bak
        echo "## Percona APT Repository" > ${percList}
        echo "deb http://${percRepo} ${_SQL_OSR} main" >> ${percList}
        st_runner "${_APT_UPDATE} -qq" &> /dev/null
      fi
      st_runner "${_APT_UPDATE} -qq" &> /dev/null
    fi
    if [ "${_SQL_UPGRADE}" = "YES" ]; then
      if [ -e "/usr/sbin/csf" ] \
        && [ -e "/etc/csf/csf.deny" ]; then
        service lfd stop &> /dev/null
        sleep 3
        kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
        killall sleep &> /dev/null
        rm -f /etc/csf/csf.error
        csf -x &> /dev/null
      fi
      msg "INFO: Running ${_DB_SERVER} upgrade..."
      if [ ! -e "/root/.proxy.cnf" ]; then
        mrun "sleep 120"
        mrun "service nginx stop" &> /dev/null
        msg "INFO: Running ${_DB_SERVER} system tables check..."
        rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
        if [ -x "/usr/bin/mariadb_upgrade" ]; then
          mrun "mariadb_upgrade --force" &> /dev/null
            wait
        elif [ -x "/usr/bin/mysql_upgrade" ]; then
          mrun "mysql_upgrade --force" &> /dev/null
            wait
        fi
      fi
      rm -f ${aptLiSys}.d/ourdelta.list
      if [ "${_DB_SERVER}" = "Percona" ] || [ "${_DB_SERIES}" = "5.7" ]; then
        _KEYS_SIG="8507EFA5"
        _KEYS_SERVER_TEST=FALSE
        until [[ "${_KEYS_SERVER_TEST}" =~ "Percona" ]]; do
          msg "INFO: Retrieving ${_KEYS_SIG} key.."
          cd /var/opt
          _KEYS_FILE_TEST=FALSE
          until [[ "${_KEYS_FILE_TEST}" =~ "GnuPG" ]]; do
            rm -f percona-key.gpg*
            wget -q -U iCab ${urlDev}/percona-key.gpg
            _KEYS_FILE_TEST=$(grep GnuPG percona-key.gpg 2>&1)
            sleep 5
          done
          cat percona-key.gpg | ${_GPG} --import &> /dev/null
          rm -f percona-key.gpg*
          ${_GPG} --keyserver pgpkeys.mit.edu --recv-key ${_KEYS_SIG} &> /dev/null
          ${_GPG} -a --export ${_KEYS_SIG} | apt-key add - &> /dev/null
          _KEYS_SERVER_TEST=$(${_GPG} --list-keys ${_KEYS_SIG} 2>&1)
          sleep 2
          if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
            kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
            echo "$(date 2>&1) Too many dirmngr processes killed" >> \
              /var/xdrago/log/dirmngr-count.kill.log
          fi
          if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
            kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
            echo "$(date 2>&1) Too many gpg-agent processes killed" >> \
              /var/xdrago/log/gpg-agent-count.kill.log
          fi
        done
        ${_APT_UPDATE} -qq &> /dev/null
      else
        _KEYS_SIG="C74CD1D8"
        _KEYS_SERVER_TEST=FALSE
        until [[ "${_KEYS_SERVER_TEST}" =~ "MariaDB" ]]; do
          msg "INFO: Retrieving ${_KEYS_SIG} key.."
          ${_GPG} --keyserver pgpkeys.mit.edu --recv-key ${_KEYS_SIG} &> /dev/null
          ${_GPG} -a --export ${_KEYS_SIG} | apt-key add - &> /dev/null
          _KEYS_SERVER_TEST=$(${_GPG} --list-keys ${_KEYS_SIG} 2>&1)
          sleep 2
          if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
            kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
            echo "$(date 2>&1) Too many dirmngr processes killed" >> \
              /var/xdrago/log/dirmngr-count.kill.log
          fi
          if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
            kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
            echo "$(date 2>&1) Too many gpg-agent processes killed" >> \
              /var/xdrago/log/gpg-agent-count.kill.log
          fi
        done
        ${_APT_UPDATE} -qq &> /dev/null
      fi
      _KEYS_SIG=""
      _KEYS_SERVER_TEST=FALSE
      if [ "${_THIS_OS}" = "Debian" ] || [ "${_THIS_OS}" = "Devuan" ]; then
        _OSN=debian
      elif [ "${_THIS_OS}" = "Ubuntu" ]; then
        _OSN=ubuntu
      fi
      st_runner "aptitude autoclean -y" &> /dev/null
      st_runner "apt-get clean -qq" &> /dev/null
      rm -rf /var/lib/apt/lists/*
      st_runner "${_APT_UPDATE} -qq" &> /dev/null
      if [ "${_DB_SERVER}" = "MariaDB" ]; then
        cp -af /etc/mysql/debian-start /etc/mysql/debian-start-mariadb &> /dev/null
      fi
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*default-table-type/#default-table-type/g" /etc/mysql/my.cnf &> /dev/null
          wait
        sed -i "s/.*language/#language/g" /etc/mysql/my.cnf &> /dev/null
          wait
      fi
      rm -f /var/lib/mysql/debian-*.flag &> /dev/null
      rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
      install_with_aptitude_sql
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*innodb_lazy_drop_table.*//g" /etc/mysql/my.cnf &> /dev/null
          wait
      fi
      if [[ ! "${_DB_SERVER}" =~ "Percona" ]]; then
        sed -i "s/^show_compatibility_56/#show_compatibility_56/g" /etc/mysql/my.cnf &> /dev/null
          wait
      fi
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*default-table-type/#default-table-type/g" /etc/mysql/my.cnf &> /dev/null
          wait
        sed -i "s/.*language/#language/g" /etc/mysql/my.cnf &> /dev/null
          wait
      fi
      _CUSTOM_CONFIG_SQL=NO
      mrun "sleep 8"
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib ${_DB_SERIES}." ]]; then
        msg "INFO: Running ${_DB_SERVER} system tables (1) upgrade..."
        rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
        if [ -x "/usr/bin/mariadb_upgrade" ]; then
          mrun "mariadb_upgrade --force" &> /dev/null
            wait
          mrun "mariadb_upgrade --force" &> /dev/null
            wait
        elif [ -x "/usr/bin/mysql_upgrade" ]; then
          mrun "mysql_upgrade --force" &> /dev/null
            wait
          mrun "mysql_upgrade --force" &> /dev/null
            wait
        fi
      fi
      tune_memory_limits
      myCnf="/etc/mysql/my.cnf"
      preCnf="${vBs}/dragon/t/my.cnf-pre-${_X_VERSION}-${_NOW}"
      if [ -f "${myCnf}" ]; then
        myCnfUpdate=NO
        myRstrd=NO
        if [ ! -f "${preCnf}" ]; then
          mkdir -p ${vBs}/dragon/t/
          cp -af ${myCnf} ${preCnf}
        fi
        diffMyTest=$(diff -w -B \
          -I innodb_buffer_pool_size \
          -I innodb_buffer_pool_instances \
          -I innodb_page_cleaners \
          -I tmp_table_size \
          -I max_heap_table_size \
          -I myisam_sort_buffer_size \
          -I key_buffer_size ${myCnf} ${preCnf} 2>&1)
        if [ -z "${diffMyTest}" ]; then
          myCnfUpdate=NO
          msg "INFO: ${_DB_SERVER} diff0 empty"
        else
          myCnfUpdate=YES
          # diffMyTest=$(echo -n ${diffMyTest} | fmt -su -w 2500 2>&1)
          msg "INFO: ${_DB_SERVER} diff1 ${diffMyTest}"
        fi
        if [[ "${diffMyTest}" =~ "innodb_buffer_pool_size" ]]; then
          myCnfUpdate=NO
          msg "INFO: ${_DB_SERVER} diff2 ${diffMyTest}"
        fi
        if [[ "${diffMyTest}" =~ "No such file or directory" ]]; then
          myCnfUpdate=NO
          msg "INFO: ${_DB_SERVER} diff3 ${diffMyTest}"
        fi
      fi
      if [ ! -e "/etc/mysql/mariadb.conf.d" ]; then
        mkdir -p /etc/mysql/mariadb.conf.d/
      fi
      myUptime=$(mysqladmin version | grep -i uptime 2>&1)
      myUptime=$(echo -n ${myUptime} | fmt -su -w 2500 2>&1)
      msg "INFO: ${_DB_SERVER} ${myUptime}"
      if [ "${myCnfUpdate}" = "YES" ]; then
        msg "INFO: Restarting ${_DB_SERVER} server..."
        mysql -u root -e "INSTALL SONAME 'ha_archive';" &> /dev/null
          wait
        mrun "bash /var/xdrago/move_sql.sh" &> /dev/null
        msg "INFO: ${_DB_SERVER} server restart completed"
        myRstrd=YES
      fi
      if [[ "${_DB_SERIES}" =~ "5.7" ]]; then
        _CHECK_EXISTS=$(mysql -u root -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'drandom_2test')" | grep "0" 2>&1)
        if [[ "${_CHECK_EXISTS}" =~ "0" ]]; then
          _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
          echo _CHECK_REPAIR 1 ${_CHECK_REPAIR}
          if [[ "${_CHECK_REPAIR}" =~ "corrupted" ]]; then
            # mysqlcheck -A --auto-repair
            mysql_upgrade --force
              wait
            mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;"
              wait
            mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;"
              wait
            mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;"
              wait
            mysql_upgrade --force
              wait
          fi
          _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
          echo _CHECK_REPAIR 2 ${_CHECK_REPAIR}
        fi
        mysql -u root -e "SET GLOBAL innodb_flush_log_at_trx_commit=2;" &> /dev/null
        mysql -u root -e "SET GLOBAL innodb_flush_log_at_timeout=5;" &> /dev/null
        mysql -u root -e "SET GLOBAL show_compatibility_56=ON;" &> /dev/null
        mysql -u root -e "SET GLOBAL innodb_stats_on_metadata=0;" &> /dev/null
        rm -f /etc/mysql/conf.d/mysqldump.cnf
      fi
      if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
        mrun "csf -e" &> /dev/null
        sleep 3
        service lfd start &> /dev/null
        ### Linux kernel TCP SACK CVEs mitigation
        ### CVE-2019-11477 SACK Panic
        ### CVE-2019-11478 SACK Slowness
        ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
        if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
          _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
          if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
            sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
            iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/sull
            ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
          fi
        fi
      fi
    fi
  fi
}

init_sql_root_credentials() {
  if [ ! -e "/root/.my.pass.txt" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      msg "INFO: Generating random password for ${_DB_SERVER}"
    else
      msg "INFO: Using default dummy password for ${_DB_SERVER}"
    fi
    touch /root/.my.pass.txt
    chmod 0600 /root/.my.pass.txt &> /dev/null
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_PASS=""
      _LEN_PASS=0
      if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
        _PWD_CHARS=32
      elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
        _PWD_CHARS=8
      else
        _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
        if [ ! -z "${_STRONG_PASSWORDS}" ] \
          && [ "${_STRONG_PASSWORDS}" -gt "8" ]; then
          _PWD_CHARS="${_STRONG_PASSWORDS}"
        else
          _PWD_CHARS=8
        fi
        if [ ! -z "${_PWD_CHARS}" ] \
          && [ "${_PWD_CHARS}" -gt "128" ]; then
          _PWD_CHARS=128
        fi
      fi
      if [ "${_STRONG_PASSWORDS}" = "YES" ] \
        || [ "${_PWD_CHARS}" -gt "8" ]; then
        if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
          _ESC_PASS="$(openssl rand -base64 32 2>&1)"
        else
          _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
        fi
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
      fi
      if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt "9" ]; then
        _ESC_PASS=$(shuf -zer -n19 {A..Z} {a..z} {0..9} | tr -d '\0' 2>&1)
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _ESC_PASS=$(sanitize_string "${_ESC_PASS}" 2>&1)
      fi
    else
      _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
    fi
    echo "${_ESC_PASS}" > /root/.my.pass.txt
  fi
  if [ -e "/root/.my.pass.txt" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      msg "INFO: New ${_DB_SERVER} root password in /root/.my.pass.txt"
    fi
  else
    msg "EXIT on error due to not found file with your ${_DB_SERVER} root password"
    cat <<EOF

    It appears that you don't have required file with your root sql password.
    Create this file first and run this script again:

    echo "your_working_SQL_ROOT_password" > /root/.my.pass.txt
    chmod 0600 /root/.my.pass.txt

EOF
    msg "EXIT on error due to not found file with your ${_DB_SERVER} root password"
    clean_pid_exit
  fi
}

update_sql_root_credentials() {
  if [ ! -e "/root/.my.cnf" ]; then
    msg "INFO: ${_DB_SERVER} final setup"
    #
    # Let's just do what mysql_secure_installation does,
    # so we can do it non-interactively:
    # - remove anonymous users
    # - remove remote root
    # - remove test database
    # - remove privileges on test database
    # - set auto-generated root password
    # - reload privileges table
    #
    if [ ! -e "/root/.my.pass.txt" ]; then
      init_sql_root_credentials
    fi
    if [ -e "/root/.my.pass.txt" ]; then
      if [ "${_DB_SERIES}" = "10.4" ]; then
        myUsrTbl="mysql.global_priv"
      else
        myUsrTbl="mysql.user"
      fi
      if [ -z "${_ESC_PASS}" ]; then
        PXSWD=$(cat /root/.my.pass.txt 2>&1)
      else
        PXSWD="${_ESC_PASS}"
      fi
      PASWD=$(echo -n ${PXSWD} | tr -d "\n" 2>&1)
      _ESC="*.*"
      if [ -z "${PASWD}" ]; then
        msg "CRIT: PASWD for ${_DB_SERVER} is empty!"
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DBEF: ${_DB_SERVER} PASWD ${PASWD}"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
          if [ "${_DB_SERIES}" = "10.3" ] \
            || [ "${_DB_SERIES}" = "10.2" ]; then
            mysql -u root -e "SELECT user,host,password FROM mysql.user;"
          elif [ "${_DB_SERIES}" = "5.7" ]; then
            mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
          fi
        fi
        if [ "${_DB_SERIES}" = "10.3" ] \
          || [ "${_DB_SERIES}" = "10.2" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "DEBG: ${_DB_SERVER} init cleanup"
          fi
          mysqladmin flush-privileges
            wait
          mysqladmin flush-hosts
            wait
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            mysql -u root -e "DELETE FROM ${myUsrTbl} WHERE User='';"
              wait
            mysql -u root -e "DELETE FROM ${myUsrTbl} WHERE User='root' AND \
              Host NOT IN ('localhost', '127.0.0.1', '::1');"
              wait
            mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR \
              Db='test\\_%';"
              wait
          else
            mysql -u root -e "DELETE FROM ${myUsrTbl} WHERE User='';" &> /dev/null
              wait
            mysql -u root -e "DELETE FROM ${myUsrTbl} WHERE User='root' AND \
              Host NOT IN ('localhost', '127.0.0.1', '::1');" &> /dev/null
              wait
            mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR \
              Db='test\\_%';" &> /dev/null
              wait
          fi
        fi
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'localhost';"
          wait
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'localhost' WITH GRANT OPTION;"
          wait
        if [ "${_DB_SERIES}" = "5.7" ]; then
          mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
        else
          mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${PASWD}';"
        fi
          wait
        echo "[client]" > /root/.my.cnf
          wait
        echo "user=root" >> /root/.my.cnf
          wait
        echo "password=${PASWD}" >> /root/.my.cnf
          wait
        chmod 0600 /root/.my.cnf
          wait
        echo "db=mysql" > /root/.mytop
          wait
        chmod 0600 /root/.mytop
          wait
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';"
          wait
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'::1';"
          wait
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_MY_OWNIP}';"
          wait
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'127.0.0.1' WITH GRANT OPTION;"
          wait
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'::1' WITH GRANT OPTION;"
          wait
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_MY_OWNIP}' WITH GRANT OPTION;"
          wait
        if [ "${_DB_SERIES}" = "5.7" ]; then
          mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
            wait
          mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
            wait
          mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
            wait
        else
          mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${PASWD}';"
            wait
          mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED BY '${PASWD}';"
            wait
          mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED BY '${PASWD}';"
            wait
        fi
        mysqladmin flush-privileges
          wait
        mysqladmin flush-hosts
          wait
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DAFT: ${_DB_SERVER} PASWD ${PASWD}"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
          if [ "${_DB_SERIES}" = "10.3" ] \
            || [ "${_DB_SERIES}" = "10.2" ]; then
            mysql -u root -e "SELECT user,host,password FROM mysql.user;"
          elif [ "${_DB_SERIES}" = "5.7" ]; then
            mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
          fi
        fi
        if [ "${_THIS_DB_HOST}" = "localhost" ] \
          || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
          || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
          || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
          _DO_NOTHING=YES
        else
          if [ -e "/etc/mysql/debian.cnf" ] && [ "${_STATUS}" = "INIT" ]; then
            mySysMn="debian-sys-maint"
            mysql -u root -e "CREATE USER IF NOT EXISTS '${mySysMn}'@'localhost';"
              wait
            mysql -u root -e "CREATE USER IF NOT EXISTS '${mySysMn}'@'127.0.0.1';"
              wait
            mysql -u root -e "CREATE USER IF NOT EXISTS '${mySysMn}'@'${_MY_OWNIP}';"
              wait
            mysql -u root -e "GRANT ALL ON ${_ESC} TO '${mySysMn}'@'localhost' WITH GRANT OPTION;"
              wait
            mysql -u root -e "GRANT ALL ON ${_ESC} TO '${mySysMn}'@'127.0.0.1' WITH GRANT OPTION;"
              wait
            mysql -u root -e "GRANT ALL ON ${_ESC} TO '${mySysMn}'@'${_MY_OWNIP}' WITH GRANT OPTION;"
              wait
            mysql -u root -e "ALTER USER '${mySysMn}'@'localhost' IDENTIFIED BY '${PASWD}';"
              wait
            mysql -u root -e "ALTER USER '${mySysMn}'@'127.0.0.1' IDENTIFIED BY '${PASWD}';"
              wait
            mysql -u root -e "ALTER USER '${mySysMn}'@'${_MY_OWNIP}' IDENTIFIED BY '${PASWD}';"
              wait
            mkdir -p ${vBs}
            cp -af /etc/mysql/debian.cnf \
              ${vBs}/debian.cnf-pre-${_X_VERSION}-${_NOW}.txt
            chmod 400 ${vBs}/debian.cnf-pre-${_X_VERSION}-${_NOW}.txt
            sed -i "s/^password =.*/password = ${PASWD}/g" \
              /etc/mysql/debian.cnf &> /dev/null
              wait
          fi
          if [ -e "/root/.remote.IP.list" ]; then
            _ESC="*.*"
            for _IP in `cat /root/.remote.IP.list \
              | cut -d '#' -f1 \
              | sort \
              | uniq \
              | tr -d "\s"`; do
              mysql -u root -e "CREATE USER IF NOT EXISTS 'aegir_root'@'${_IP}';"
                wait
              mysql -u root -e "GRANT ALL ON ${_ESC} TO 'aegir_root'@'${_IP}' WITH GRANT OPTION;"
                wait
              mysql -u root -e "ALTER USER 'aegir_root'@'${_IP}' IDENTIFIED BY '${PASWD}';"
                wait
            done
          fi
          if [ -e "/root/.cluster.IP.list" ]; then
            for _IP in `cat /root/.cluster.IP.list \
              | cut -d '#' -f1 \
              | sort \
              | uniq \
              | tr -d "\s"`; do
              mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_IP}';"
                wait
              mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_IP}' WITH GRANT OPTION;"
                wait
              if [ "${_DB_SERIES}" = "5.7" ]; then
                mysql -u root -e "ALTER USER 'root'@'${_IP}' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
              else
                mysql -u root -e "ALTER USER 'root'@'${_IP}' IDENTIFIED BY '${PASWD}';"
              fi
                wait
            done
            mysql -u root -e "CREATE USER IF NOT EXISTS 'wsrep'@'%';"
              wait
            mysql -u root -e "GRANT ALL ON ${_ESC} TO 'wsrep'@'%' WITH GRANT OPTION;"
              wait
            mysql -u root -e "ALTER USER 'wsrep'@'%' IDENTIFIED BY '${PASWD}';"
              wait
          fi
          touch ${pthLog}/fixed-cluster-ip-grants.log
        fi
        if [ "${_THIS_DB_HOST}" = "localhost" ] \
          || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
          || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
          echo "skip-name-resolve" > /etc/mysql/skip-name-resolve.txt
        elif [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ]; then
          echo "skip-name-resolve" > /etc/mysql/skip-name-resolve.txt
        else
          sed -i "s/.*skip-name-resolve/#skip-name-resolve/g" /etc/mysql/my.cnf &> /dev/null
            wait
        fi
        if [ "${_DB_SERVER}" = "MariaDB" ]; then
          sed -i "s/.*check_for_crashed_tables/#check_for_crashed_tables/g" \
            /etc/mysql/debian-start &> /dev/null
          wait
        fi
        mysqladmin flush-privileges
          wait
        mysqladmin flush-hosts
          wait
        msg "INFO: Restarting ${_DB_SERVER} server..."
        mrun "bash /var/xdrago/move_sql.sh" &> /dev/null
        mysql -u root -e "INSTALL SONAME 'ha_archive';" &> /dev/null
          wait
        msg "INFO: ${_DB_SERVER} setup completed"
        msg "INFO: You can now log in as root by typing just 'mysql'"
      fi
    fi
  else
    if [ ! -e "${pthLog}/fixed-cluster-ip-grants.log" ] \
      && [ -e "/root/.dbhd.clstr.cnf" ]; then
      PXSWD=$(cat /root/.my.pass.txt 2>&1)
      PASWD=$(echo -n ${PXSWD} | tr -d "\n" 2>&1)
      if [ -e "/root/.remote.IP.list" ]; then
        _ESC="*.*"
        for _IP in `cat /root/.remote.IP.list \
          | cut -d '#' -f1 \
          | sort \
          | uniq \
          | tr -d "\s"`; do
          mysql -u root -e "CREATE USER IF NOT EXISTS 'aegir_root'@'${_IP}';"
            wait
          mysql -u root -e "GRANT ALL ON ${_ESC} TO 'aegir_root'@'${_IP}' WITH GRANT OPTION;"
            wait
          mysql -u root -e "ALTER USER 'aegir_root'@'${_IP}' IDENTIFIED BY '${PASWD}';"
            wait
        done
      fi
      if [ -e "/root/.cluster.IP.list" ]; then
        for _IP in `cat /root/.cluster.IP.list \
          | cut -d '#' -f1 \
          | sort \
          | uniq \
          | tr -d "\s"`; do
          mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_IP}';"
            wait
          mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_IP}' WITH GRANT OPTION;"
            wait
          if [ "${_DB_SERIES}" = "5.7" ]; then
            mysql -u root -e "ALTER USER 'root'@'${_IP}' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
          else
            mysql -u root -e "ALTER USER 'root'@'${_IP}' IDENTIFIED BY '${PASWD}';"
          fi
            wait
        done
        mysql -u root -e "CREATE USER IF NOT EXISTS 'wsrep'@'%';"
          wait
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'wsrep'@'%' WITH GRANT OPTION;"
          wait
        mysql -u root -e "ALTER USER 'wsrep'@'%' IDENTIFIED BY '${PASWD}';"
          wait
      fi
      touch ${pthLog}/fixed-cluster-ip-grants.log
    fi
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ ! -e "/root/.mysql.no.new.password.cnf" ]; then
        if [ -e "/root/.mysql.yes.new.password.cnf" ] \
          || [ -e "/root/.my.cluster_root_pwd.txt" ]; then
          forced_mysql_root_password_update
        fi
      fi
    fi
  fi
}
