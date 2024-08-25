#
# Update for keyrings/percona.gpg
if_sql_keyring_apt_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_sql_keyring_apt_update"
  fi

  if [ "${_DB_SERVER}" = "Percona" ]; then
    _SQL_KEYRING_UPDATE=NO
    if [ -e "/etc/apt/trusted.gpg.d/percona.gpg" ] \
      || [ ! -e "/etc/apt/keyrings/percona.gpg" ] \
      || [ -e "/etc/apt/trusted.gpg.d/percona-keyring.gpg~" ]; then
      _SQL_KEYRING_UPDATE=YES
    fi
  fi

  if [ "${_DB_SERVER}" = "Percona" ] && [ "${_SQL_KEYRING_UPDATE}" = "YES" ]; then
    if [ ! -e "/etc/apt/keyrings/percona.gpg" ]; then
      if [ ! -e "/etc/apt/keyrings" ]; then
        mkdir -m 0755 -p /etc/apt/keyrings
      fi
      if [ -e "/etc/apt/trusted.gpg.d/percona.gpg" ] \
        || [ -e "/etc/apt/trusted.gpg.d/percona-keyring.gpg~" ]; then
        rm -f /etc/apt/trusted.gpg.d/percona*
      fi
      _PERCONA_KEYS_SIG="8507EFA5"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Retrieving ${_PERCONA_KEYS_SIG} key..."
      fi
      apt-key del ${_PERCONA_KEYS_SIG} &> /dev/null
      if [ ! -e "/etc/apt/keyrings/percona.gpg" ]; then
        curl -fsSL ${urlDev}/percona-key.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/percona.gpg
      fi
      chmod 644 /etc/apt/keyrings/percona.gpg
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
    fi
    apt_clean_update
  fi

  [ ! -z "${_SQL_NEW_OS_CODE}" ] && _SQL_OS_CODE=${_SQL_NEW_OS_CODE}

  if [ "${_DB_SERVER}" = "Percona" ]; then
    _DB_SRC="repo.percona.com"
    _SQL_DEB_SRC_TEST_A=$(grep ${_DB_SRC} \
      /etc/apt/sources.list.d/percona-release.list 2>&1)
    _SQL_DEB_SRC_TEST_B=$(grep ${_SQL_OS_CODE} \
      /etc/apt/sources.list.d/percona-release.list 2>&1)
  fi
  if [[ "${_SQL_DEB_SRC_TEST_A}" =~ "${_DB_SRC}" ]] \
    && [[ "${_SQL_DEB_SRC_TEST_B}" =~ "${_SQL_OS_CODE}" ]] \
    && [ -e "/etc/apt/keyrings/percona.gpg" ] \
    && [ -e "/etc/apt/preferences.d/00percona.pref" ]; then
    _SQL_DEB_SRC_UPDATE=NO
  else
    _SQL_DEB_SRC_UPDATE=YES
  fi

  if [ "${_DB_SERVER}" = "Percona" ] && [ "${_SQL_DEB_SRC_UPDATE}" = "YES" ]; then
    rm -f /etc/apt/sources.list.d/mariadb*
    rm -f /etc/apt/sources.list.d/ourdelta*
    rm -f /etc/apt/sources.list.d/percona*
    rm -f /etc/apt/sources.list.d/xtrabackup*
    percList="/etc/apt/sources.list.d/percona-release.list"
    percRepo="${_DB_SRC}/percona/apt"
    echo "## Percona APT Repository" > ${percList}
    if [ -e "/etc/apt/keyrings/percona.gpg" ]; then
      echo "deb [signed-by=/etc/apt/keyrings/percona.gpg] http://${percRepo} ${_SQL_OS_CODE} main" >> ${percList}
      echo "deb-src [signed-by=/etc/apt/keyrings/percona.gpg] http://${percRepo} ${_SQL_OS_CODE} main" >> ${percList}
    else
      echo "deb http://${percRepo} ${_SQL_OS_CODE} main" >> ${percList}
      echo "deb-src http://${percRepo} ${_SQL_OS_CODE} main" >> ${percList}
    fi
    chmod 644 ${percList}
    echo -e 'Package: *\nPin: release o=Percona Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00percona.pref
    apt_clean_update
  fi
}

#
# Only supported upgrade path allowed.
sql_strict_upgrade_path() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sql_strict_upgrade_path"
  fi
  _DB_SERVER_TEST=$(mysql -V 2>&1)
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
    if [[ "${_NOW_DB_V}" =~ "available" ]]; then
      _SQL_FORCE_REINSTALL=NO
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
  if [[ "${_NOW_DB_V}" =~ (^)"5.7" ]] \
    && [ ! -z "${_DB_SERIES}" ] \
    && [ "${_DB_SERIES}" != "5.7" ] \
    && [ "${_DB_SERIES}" != "8.0" ]; then
    _DB_SERIES=8.0
    export _DB_SERIES=8.0
    sed -i "s/^_DB_SERIES=.*/_DB_SERIES=8.0/g" ${barCnf}
    _SQL_UPGRADE=YES
  fi
  if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_ALL_FORCE_REINSTALL}" = "YES" ]; then
    _SQL_UPGRADE=YES
  fi
}

#
# Update innodb_log_file_size.
innodb_log_file_size_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: innodb_log_file_size_update"
  fi
  msg "INFO: InnoDB log file will be set to ${_INNODB_LOG_FILE_SIZE_MB}..."
  _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
  mysql -u root -e "SET GLOBAL innodb_fast_shutdown = 0;" &> /dev/null
  mrun "bash /var/xdrago/move_sql.sh stop" &> /dev/null
  wait
  _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
  if [ -z "${_IS_MYSQLD_RUNNING}" ]; then
    mkdir -p ${vBs}/old-sql-ib-log-${_NOW}
    mrun "sleep 1"
    mv -f /var/lib/mysql/ib_logfile0 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    mv -f /var/lib/mysql/ib_logfile1 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    sed -i "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" /etc/mysql/my.cnf &> /dev/null
    mrun "bash /var/xdrago/move_sql.sh start" &> /dev/null
    wait
  else
    msg "INFO: Waiting 180s for ${_DB_SERVER} clean shutdown..."
    mrun "bash /var/xdrago/move_sql.sh stop" &> /dev/null
    wait
    mrun "sleep 180"
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    if [ -z "${_IS_MYSQLD_RUNNING}" ]; then
      mkdir -p ${vBs}/old-sql-ib-log-${_NOW}
      mrun "sleep 1"
      mv -f /var/lib/mysql/ib_logfile0 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      mv -f /var/lib/mysql/ib_logfile1 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
      sed -i "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" /etc/mysql/my.cnf &> /dev/null
      mrun "bash /var/xdrago/move_sql.sh start" &> /dev/null
      wait
    else
      msg "WARN: ${_DB_SERVER} refused to stop, InnoDB log file size not updated"
      mrun "sleep 5"
    fi
  fi
}

#
# Update SQL Config.
sql_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sql_conf_update"
  fi
  sed -i "s/.*innodb_force_recovery/#innodb_force_recovery/g" /etc/mysql/my.cnf &> /dev/null
    wait
  sed -i "s/.*innodb_corrupt_table_action/#innodb_corrupt_table_action/g" /etc/mysql/my.cnf &> /dev/null
    wait
  sed -i "s/^thread_concurrency.*//g" /etc/mysql/my.cnf &> /dev/null
    wait
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ] \
    || [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]]; then
    if [ "${_CUSTOM_CONFIG_SQL}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      _INNODB_LOG_FILE_SIZE=${_INNODB_LOG_FILE_SIZE//[^0-9]/}
      if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ]; then
        if [ "${_INNODB_LOG_FILE_SIZE}" -ge "50" ]; then
          _INNODB_LOG_FILE_SIZE_MB="${_INNODB_LOG_FILE_SIZE}M"
          _INNODB_LOG_FILE_SIZE_TEST=$(grep "^innodb_log_file_size" \
            ${vBs}/dragon/t/my.cnf-pre-${_X_SE}-${_X_VERSION}-${_NOW} 2>&1)
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
    if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ]; then
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
            innodb_log_file_size_update
          fi
        fi
      fi
    fi
  fi
}

#
#
check_mysqld_running() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_mysqld_running"
  fi
  while [ -z "${_IS_MYSQLD_RUNNING}" ] \
    || [ ! -e "/run/mysqld/mysqld.sock" ]; do
    _IS_MYSQLD_RUNNING=$(ps aux | grep '[m]ysqld' | awk '{print $2}' 2>&1)
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Waiting for MySQLD availability before tune_sql_memory_limits..."
    fi
    sleep 5
  done
}

#
# Tune memory limits for SQL server.
tune_sql_memory_limits() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: tune_sql_memory_limits"
  fi
  if [ -e "/root/.run-to-daedalus.cnf" ] \
    || [ -e "/root/.run-to-chimaera.cnf" ] \
    || [ -e "/root/.run-to-beowulf.cnf" ]; then
    _DO_NOTHING=YES
  else
    _DO_NOTHING=YES
    #check_mysqld_running
  fi
  if [ ! -e "${vBs}/dragon/t/my.cnf-pre-${_X_SE}-${_X_VERSION}-${_NOW}" ]; then
    mkdir -p ${vBs}/dragon/t/
    if [ -e "/etc/mysql/my.cnf" ]; then
      cp -af /etc/mysql/my.cnf ${vBs}/dragon/t/my.cnf-pre-${_X_SE}-${_X_VERSION}-${_NOW}
    fi
  fi
  if [ "${_CUSTOM_CONFIG_SQL}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    cp -af ${locCnf}/var/my.cnf.txt /etc/mysql/my.cnf
  fi
  # https://raw.githubusercontent.com/major/MySQLTuner-perl/master/mysqltuner.pl
  pthTun="/var/opt/mysqltuner.pl"
  outTun="/var/opt/mysqltuner-${_X_SE}-${_X_VERSION}-${_NOW}.txt"
  if [ -e "/root/.run-to-daedalus.cnf" ] \
    || [ -e "/root/.run-to-chimaera.cnf" ] \
    || [ -e "/root/.run-to-beowulf.cnf" ]; then
    _USE_MYSQLTUNER=NO
  fi
  if [ ! -e "${outTun}" ] \
    && [ "${_USE_MYSQLTUNER}" != "NO" ] \
    && [ "${_STATUS}" = "UPGRADE" ]; then
    msg "INFO: Running MySQLTuner check on all databases"
    msg "WAIT: This may take a while, please wait..."
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
      msg "NOTE: The MySQLTuner test failed!"
      msg "NOTE: Please review ${outTun}"
      msg "NOTE: We will use some sane SQL defaults instead, do not worry!"
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
        msg "NOTE: _USE_MYISAM_MEM is ${_USE_MYISAM_MEM} because _REC_MYISAM_MEM was empty!"
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
      msg "NOTE: _USE_INNODB_MEM is ${_USE_INNODB_MEM} because _REC_INNODB_MEM was empty!"
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${_USE_INNODB_MEM}/g"  /etc/mysql/my.cnf &> /dev/null
      fi
        wait
    fi
  else
    _THIS_USE_MEM="${_USE_SQL}M"
    if [ "${_MYSQLTUNER_TEST_RESULT}" = "FAIL" ] \
      && [ "${_STATUS}" = "UPGRADE" ]; then
      msg "NOTE: _USE_MYISAM_MEM is ${_THIS_USE_MEM} because _REC_MYISAM_MEM was empty!"
      msg "NOTE: _USE_INNODB_MEM is ${_THIS_USE_MEM} because _REC_INNODB_MEM was empty!"
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
      wait
    fi
  fi
}

prep_for_install_db_sql() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: prep_for_install_db_sql"
  fi
  _SQL_SCR=APT
  if [ "${_OS_CODE}" = "daedalus" ]; then
    _SQL_OS_CODE=bookworm
  elif [ "${_OS_CODE}" = "chimaera" ]; then
    _SQL_OS_CODE=bullseye
  elif [ "${_OS_CODE}" = "beowulf" ]; then
    _SQL_OS_CODE=buster
  else
    _SQL_OS_CODE="${_OS_CODE}"
  fi
  if [ "${_SQL_OS_CODE}" = "foobar" ]; then
    _SQL_SCR=GIT
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

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Installing software-properties-common dirmngr..."
  fi
  st_runner "${_INSTAPP} software-properties-common dirmngr" 2> /dev/null

  msg "INFO: Installing ${_DB_SERVER} ${_DBS_VRN} in ${_OS_DIST}/${_OS_CODE}"

  ### Update keyring and apt if needed
  if_sql_keyring_apt_update

  ### Only supported upgrade path allowed
  sql_strict_upgrade_path

  if [ -e "/usr/bin/mytop" ]; then
    mrun "apt-get remove mytop -y --purge --auto-remove -qq" 2> /dev/null
    rm -f /usr/bin/mytop
  fi
  if [ "${_SQL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    sed -i "s/.*innodb_force_recovery.*/innodb_force_recovery = 3/g" /etc/mysql/my.cnf &> /dev/null
    wait
  fi

  SQLDEB="percona-server-server-${_DB_SERIES}"
  SQLXTR="libdbi-perl percona-toolkit"

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
  if [ "${_DB_SERIES}" = "5.7" ]; then
    SQLADD="libperconaserverclient20-dev"
  else
    SQLADD="libperconaserverclient21-dev"
  fi
}

install_with_aptitude_sql() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_with_aptitude_sql"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Installing ${_DB_SERVER}..."
  fi
  prep_for_install_db_sql
  if [ "${_SQL_SCR}" = "APT" ]; then
    st_runner "${_INSTAPP} ${SQLDEB}" 2> /dev/null
    st_runner "${_INSTAPP} ${SQLADD}" 2> /dev/null
    st_runner "${_INSTAPP} ${SQLXTR}" 2> /dev/null
    st_runner "${_INSTAPP} ${SQLDEB}" 2> /dev/null
  elif [ "${_SQL_SCR}" = "GIT" ]; then
    ### TBD -- only for testing
    st_runner "${_INSTAPP} ${SQLXTR}" 2> /dev/null
  fi
  if [ ! -e "/usr/local/bin/mytop" ] && [ -e "/usr/bin/mysql" ]; then
    msg "INFO: Building MyTop from sources..."
    apt_clean_update
    mrun "${_INSTAPP} cpanminus" 2> /dev/null
    mrun "cpanm DBD::mysql@4.050" 2> /dev/null
    cd /var/opt
    rm -rf git*
    get_dev_src "mytop-1.6.tar.gz"
    cd /var/opt/mytop-1.6
    mrun "perl Makefile.PL" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
  fi
  if [ "${_DB_SERVER}" = "Percona" ] \
    && [ "${_SQL_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Running ${_DB_SERVER} tables fix, check and upgrade..."
    fi
    rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
    _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
    _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
    mrun "mysqlcheck -u root -A --auto-repair --silent" &> /dev/null
    mrun "mysql_upgrade -u root --force" &> /dev/null
    if [ "${_DB_SERIES}" = "5.7" ]; then
      mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;" &> /dev/null
      mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;" &> /dev/null
      mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;" &> /dev/null
    fi
    mrun "mysql_upgrade -u root --force" &> /dev/null
  fi
  usermod -aG users mysql
}

#
# Forced MySQL root password update.
forced_mysql_root_password_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: forced_mysql_root_password_update"
  fi
  _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
  mv -f /root/.my.cnf-pre-* ${vBs}/ &> /dev/null
  mv -f /root/.my.pass.txt-pre-* ${vBs}/ &> /dev/null
  touch /root/.my.pass.txt
  chmod 0600 /root/.my.pass.txt &> /dev/null
  _ESC_PASS=""
  _LEN_PASS=0
  _ESC="*.*"
  if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
    _PWD_CHARS=64
  elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
    _PWD_CHARS=32
  else
    _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
    if [ ! -z "${_STRONG_PASSWORDS}" ] \
      && [ "${_STRONG_PASSWORDS}" -gt "32" ]; then
      _PWD_CHARS="${_STRONG_PASSWORDS}"
    else
      _PWD_CHARS=32
    fi
    if [ ! -z "${_PWD_CHARS}" ] \
      && [ "${_PWD_CHARS}" -gt "128" ]; then
      _PWD_CHARS=128
    fi
  fi
  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt "32" ]; then
    if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
      _ESC_PASS="$(openssl rand -base64 64 2>&1)"
    else
      _RANDPASS_TEST=$(randpass -V 2>&1)
      if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
        _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
      else
        _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _ESC_PASS=$(sanitize_string "${_ESC_PASS}" 2>&1)
      fi
    fi
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
  fi
  if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt "9" ]; then
    _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
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
      mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
    fi
    cp -af /root/.my.cnf /root/.my.cnf-pre-${_X_SE}-${_X_VERSION}-${_NOW}
    cp -af /root/.my.pass.txt /root/.my.pass.txt-pre-${_X_SE}-${_X_VERSION}-${_NOW}
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'localhost';"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'localhost' WITH GRANT OPTION;"
    if [ "${_DB_SERIES}" = "5.7" ]; then
      mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
    else
      mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
    fi
    echo "[client]" > /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[mysql]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[mysqldump]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[mydumper]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[myloader]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[boa]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[barracuda]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[octopus]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[autobeowulf]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[autochimaera]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[autodaedalus]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[autoupboa]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[mycnfup]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[syncpass]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    echo "[xboa]" >> /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=${_ESC_PASS}" >> /root/.my.cnf
      echo " " >> /root/.my.cnf
    chmod 0600 /root/.my.cnf
    echo "db=mysql" > /root/.mytop
    chmod 0600 /root/.mytop
    echo "${_ESC_PASS}" > /root/.my.pass.txt
    _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
    _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';"
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'::1';"
    mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_MY_OWNIP}';"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'::1' WITH GRANT OPTION;"
    mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_MY_OWNIP}' WITH GRANT OPTION;"
    if [ "${_DB_SERIES}" = "5.7" ]; then
      mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH mysql_native_password BY '${_ESC_PASS}';"
    else
      mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
      mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH caching_sha2_password BY '${_ESC_PASS}';"
    fi
    mysqladmin -u root flush-privileges &> /dev/null
    mysqladmin -u root flush-hosts &> /dev/null
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "DAFT: ${_DB_SERVER} _ESC_PASS ${_ESC_PASS}"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
      mysql -u root -e "SHOW GRANTS FOR 'root'@'::1';"
      mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
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

db_server_apt_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: db_server_apt_cleanup"
  fi
  [ -e "/etc/apt/sources.list.d/percona-original-release.list.bak" ] && rm -f /etc/apt/sources.list.d/percona-original-release.list.bak
  [ -e "/etc/apt/sources.list.d/percona-original-release.list" ] && rm -f /etc/apt/sources.list.d/percona-original-release.list
  [ -e "/etc/apt/sources.list.d/percona-prel-release.list.bak" ] && rm -f /etc/apt/sources.list.d/percona-prel-release.list.bak
  [ -e "/etc/apt/sources.list.d/percona-prel-release.list" ] && rm -f /etc/apt/sources.list.d/percona-prel-release.list
  [ -e "/etc/apt/sources.list.d/percona-release.list.bak" ] && rm -f /etc/apt/sources.list.d/percona-release.list.bak
  apt_clean_update
}

db_server_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: db_server_install"
  fi
  db_server_apt_cleanup
  _SQL_SCR=APT
  if [ "${_OS_CODE}" = "daedalus" ]; then
    _SQL_OS_CODE=bookworm
  elif [ "${_OS_CODE}" = "chimaera" ]; then
    _SQL_OS_CODE=bullseye
  elif [ "${_OS_CODE}" = "beowulf" ]; then
    _SQL_OS_CODE=buster
  else
    _SQL_OS_CODE="${_OS_CODE}"
  fi
  if [ "${_SQL_OS_CODE}" = "foobar" ]; then
    _SQL_SCR=GIT
  fi
  _THIS_DB_PORT=3306
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    db_server_apt_cleanup
    install_with_aptitude_sql
    db_server_apt_cleanup
  else
    ###
    ### Update keyring and apt if needed
    if_sql_keyring_apt_update
    ###
    ### Only supported upgrade path allowed
    sql_strict_upgrade_path
    ###
    if [ "${_SQL_UPGRADE}" = "YES" ]; then
      msg "INFO: Running ${_DB_SERVER} upgrade..."
      msg "WAIT: This may take a while, please wait..."
      if [ ! -e "/root/.proxy.cnf" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Running ${_DB_SERVER} system tables check..."
        fi
        rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
        if [ -x "/usr/bin/mysql_upgrade" ]; then
          _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
          _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
          mrun "mysql_upgrade -u root --force" &> /dev/null
        fi
      fi
      st_runner "apt-get autoclean -y" &> /dev/null
      apt_clean_update
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*default-table-type/#default-table-type/g" /etc/mysql/my.cnf &> /dev/null
          wait
        sed -i "s/.*language/#language/g" /etc/mysql/my.cnf &> /dev/null
          wait
      fi
      rm -f /var/lib/mysql/debian-*.flag &> /dev/null
      rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
      db_server_apt_cleanup
      install_with_aptitude_sql
      db_server_apt_cleanup
      if [ -e "/etc/mysql/my.cnf" ]; then
        sed -i "s/.*innodb_lazy_drop_table.*//g" /etc/mysql/my.cnf &> /dev/null
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
      _DB_SERVER_TEST=$(mysql -V 2>&1)
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib ${_DB_SERIES}." ]]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Running ${_DB_SERVER} system tables (1) upgrade..."
        fi
        rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
        if [ -x "/usr/bin/mysql_upgrade" ]; then
          _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
          _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
          mrun "mysql_upgrade -u root --force" &> /dev/null
          mrun "mysql_upgrade -u root --force" &> /dev/null
        fi
      fi
      tune_memory_limits
      myCnf="/etc/mysql/my.cnf"
      preCnf="${vBs}/dragon/t/my.cnf-pre-${_X_SE}-${_X_VERSION}-${_NOW}"
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
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: ${_DB_SERVER} diff0 empty"
          fi
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
      if [ ! -e "/root/.run-to-daedalus.cnf" ] \
        && [ ! -e "/root/.run-to-chimaera.cnf" ] \
        && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
        _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
        _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
        myUptime=$(mysqladmin -u root version | grep -i uptime 2>&1)
        myUptime=$(echo -n ${myUptime} | fmt -su -w 2500 2>&1)
        msg "INFO: ${_DB_SERVER} ${myUptime}"
        if [ "${myCnfUpdate}" = "YES" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Restarting ${_DB_SERVER} server..."
          fi
          mysql -u root -e "INSTALL SONAME 'ha_archive';" &> /dev/null
          mrun "bash /var/xdrago/move_sql.sh" &> /dev/null
          wait
          msg "INFO: ${_DB_SERVER} server restart completed"
          myRstrd=YES
        fi
        if [ "${_DB_SERIES}" = "5.7" ]; then
          _CHECK_EXISTS=$(mysql -u root -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'drandom_2test')" | grep "0" 2>&1)
          if [[ "${_CHECK_EXISTS}" =~ "0" ]]; then
            _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              echo _CHECK_REPAIR 1 ${_CHECK_REPAIR}
            fi
            if [[ "${_CHECK_REPAIR}" =~ "corrupted" ]]; then
              mysqlcheck -u root -A --auto-repair --silent
              mysql_upgrade -u root --force
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;"
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;"
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;"
              mysql_upgrade -u root --force
            fi
            _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              echo _CHECK_REPAIR 2 ${_CHECK_REPAIR}
            fi
          fi
          mysql -u root -e "SET GLOBAL innodb_flush_log_at_trx_commit=2;" &> /dev/null
          mysql -u root -e "SET GLOBAL innodb_flush_log_at_timeout=5;" &> /dev/null
          mysql -u root -e "SET GLOBAL innodb_stats_on_metadata=0;" &> /dev/null
          rm -f /etc/mysql/conf.d/mysqldump.cnf
        fi
      fi
      if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
        mrun "csf -e" &> /dev/null
        wait
        mrun "service lfd start" 2> /dev/null
        wait
        ### Linux kernel TCP SACK CVEs mitigation
        ### CVE-2019-11477 SACK Panic
        ### CVE-2019-11478 SACK Slowness
        ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
        if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
          _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
          if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
            sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
            iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
            ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
          fi
        fi
      fi
    fi
  fi
}

init_sql_root_credentials() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: init_sql_root_credentials"
  fi
  if [ ! -e "/root/.my.pass.txt" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Generating random password for ${_DB_SERVER}"
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Using default dummy password for ${_DB_SERVER}"
      fi
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
        _PWD_CHARS=64
      elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
        _PWD_CHARS=32
      else
        _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
        if [ ! -z "${_STRONG_PASSWORDS}" ] \
          && [ "${_STRONG_PASSWORDS}" -gt "32" ]; then
          _PWD_CHARS="${_STRONG_PASSWORDS}"
        else
          _PWD_CHARS=32
        fi
        if [ ! -z "${_PWD_CHARS}" ] \
          && [ "${_PWD_CHARS}" -gt "128" ]; then
          _PWD_CHARS=128
        fi
      fi
      if [ "${_STRONG_PASSWORDS}" = "YES" ] \
        || [ "${_PWD_CHARS}" -gt "32" ]; then
        if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
          _ESC_PASS="$(openssl rand -base64 64 2>&1)"
        else
          _RANDPASS_TEST=$(randpass -V 2>&1)
          if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
            _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
          else
            _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
            _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
            _ESC_PASS=$(sanitize_string "${_ESC_PASS}" 2>&1)
          fi
        fi
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
      fi
      if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt "9" ]; then
        _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
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
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: New ${_DB_SERVER} root password in /root/.my.pass.txt"
      fi
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
    clean_pid_exit init_sql_root_credentials_a
  fi
}

sql_root_credentials_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sql_root_credentials_update"
  fi
  if [ ! -e "/root/.my.cnf" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: ${_DB_SERVER} final setup"
    fi
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
      myUsrTbl="mysql.user"
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
          mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
        fi
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'localhost';"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'localhost' WITH GRANT OPTION;"
        if [ "${_DB_SERIES}" = "5.7" ]; then
          mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
        else
          mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${PASWD}';"
        fi
        echo "[client]" > /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
        echo " " >> /root/.my.cnf
        echo "[mysql]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[mysqldump]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[mydumper]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[myloader]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[boa]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[barracuda]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[octopus]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[mycnfup]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[syncpass]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        echo "[xboa]" >> /root/.my.cnf
        echo "user=root" >> /root/.my.cnf
        echo "password=${PASWD}" >> /root/.my.cnf
          echo " " >> /root/.my.cnf
        chmod 0600 /root/.my.cnf
        echo "db=mysql" > /root/.mytop
        chmod 0600 /root/.mytop
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1';"
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'::1';"
        mysql -u root -e "CREATE USER IF NOT EXISTS 'root'@'${_MY_OWNIP}';"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'127.0.0.1' WITH GRANT OPTION;"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'::1' WITH GRANT OPTION;"
        mysql -u root -e "GRANT ALL ON ${_ESC} TO 'root'@'${_MY_OWNIP}' WITH GRANT OPTION;"
        if [ "${_DB_SERIES}" = "5.7" ]; then
          mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH mysql_native_password BY '${PASWD}';"
        else
          mysql -u root -e "ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH caching_sha2_password BY '${PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'::1' IDENTIFIED WITH caching_sha2_password BY '${PASWD}';"
          mysql -u root -e "ALTER USER 'root'@'${_MY_OWNIP}' IDENTIFIED WITH caching_sha2_password BY '${PASWD}';"
        fi
        mysqladmin -u root flush-privileges
        mysqladmin -u root flush-hosts
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DAFT: ${_DB_SERVER} PASWD ${PASWD}"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'localhost';"
          mysql -u root -e "SHOW GRANTS FOR 'root'@'127.0.0.1';"
          mysql -u root -e "SELECT host,user,authentication_string FROM mysql.user;"
        fi
        if [ "${_THIS_DB_HOST}" = "localhost" ] \
          || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
          || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
          echo "skip-name-resolve" > /etc/mysql/skip-name-resolve.txt
        else
          sed -i "s/.*skip-name-resolve/#skip-name-resolve/g" /etc/mysql/my.cnf &> /dev/null
        fi
        mysqladmin -u root flush-privileges
        mysqladmin -u root flush-hosts
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Restarting ${_DB_SERVER} server..."
        fi
        mrun "bash /var/xdrago/move_sql.sh" &> /dev/null
        wait
        mysql -u root -e "INSTALL SONAME 'ha_archive';" &> /dev/null
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: ${_DB_SERVER} setup completed"
          msg "INFO: You can now log in as root by typing just 'mysql'"
        fi
      fi
    fi
  else
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
