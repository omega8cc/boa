#
# Update innodb_log_file_size.
update_innodb_log_file_size() {
  msg "INFO: InnoDB log file will be set to ${_INNODB_LOG_FILE_SIZE_MB}..."
  mrun "service mysql stop" &> /dev/null
  mrun "sleep 5"
  if [ ! -e "/var/run/mysqld/mysqld.sock" ] \
    && [ ! -e "/var/run/mysqld/mysqld.pid" ]; then
    mkdir -p ${vBs}/old-sql-ib-log-${_NOW}
    mrun "sleep 5"
    mv -f /var/lib/mysql/ib_logfile0 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    mv -f /var/lib/mysql/ib_logfile1 ${vBs}/old-sql-ib-log-${_NOW}/ &> /dev/null
    sed -i "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" /etc/mysql/my.cnf
    mrun "sleep 5"
  fi
  mrun "service mysql start" &> /dev/null
}

#
# Update SQL Config.
update_sql_conf() {
  sed -i "s/.*check_for_crashed_tables/#check_for_crashed_tables/g" /etc/mysql/debian-start
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ] \
    || [[ "${_THISHOST}" =~ ".host8." ]] \
    || [ "${_VMFAMILY}" = "VS" ]; then
    if [ "${_CUSTOM_CONFIG_SQL}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      cp -af /etc/mysql/my.cnf ${vBs}/dragon/t/my.cnf-pre-${_X_VERSION}-${_NOW}
      cp -af ${locCnf}/my.cnf.txt /etc/mysql/my.cnf
      _INNODB_LOG_FILE_SIZE=${_INNODB_LOG_FILE_SIZE//[^0-9]/}
      if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ]; then
        if [ "${_INNODB_LOG_FILE_SIZE}" -ge "10" ] \
          && [ "${_INNODB_LOG_FILE_SIZE}" -lt "501" ]; then
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
      sed -i "s/.*slow_query_log/#slow_query_log/g"           /etc/mysql/my.cnf
      sed -i "s/.*long_query_time/#long_query_time/g"         /etc/mysql/my.cnf
      sed -i "s/.*slow_query_log_file/#slow_query_log_file/g" /etc/mysql/my.cnf
      if [ ! -e "/etc/mysql/skip-name-resolve.txt" ]; then
        sed -i "s/.*skip-name-resolve/#skip-name-resolve/g"   /etc/mysql/my.cnf
      fi
    fi
  fi
  mv -f /etc/mysql/my.cnf-pre* ${vBs}/dragon/t/ &> /dev/null
  sed -i "s/.*default-table-type/#default-table-type/g" /etc/mysql/my.cnf
  sed -i "s/.*language/#language/g" /etc/mysql/my.cnf
  _THIS_DB_SERVER_TEST=$(mysql -V 2>&1)
  if [[ "${_THIS_DB_SERVER_TEST}" =~ "5.5." ]] \
    || [[ "${_THIS_DB_SERVER_TEST}" =~ "10.0" ]]; then
    _DO_NOTHING=YES
  else
    sed -i "s/.*lc_messages_dir /#lc_messages_dir /g" /etc/mysql/my.cnf
    sed -i "s/.*lc_messages /#lc_messages /g"         /etc/mysql/my.cnf
  fi
  if [[ "${_THIS_DB_SERVER_TEST}" =~ "MariaDB" ]]; then
    sed -i "s/.*innodb_lazy_drop_table /#innodb_lazy_drop_table /g" /etc/mysql/my.cnf
  fi
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ]; then
    if [ "${_DB_BINARY_LOG}" = "NO" ]; then
      bash /var/xdrago/purge_binlogs.sh &> /dev/null
      sed -i "s/.*purge_binlogs.*//g" /var/spool/cron/crontabs/root
      sed -i "/^$/d"                  /var/spool/cron/crontabs/root
      sed -i "s/^log_bin/#log_bin/g"                   /etc/mysql/my.cnf
      sed -i "s/^expire_logs_days/#expire_logs_days/g" /etc/mysql/my.cnf
      sed -i "s/^max_binlog_size/#max_binlog_size/g"   /etc/mysql/my.cnf
    elif [ "${_DB_BINARY_LOG}" = "YES" ]; then
      sed -i "s/.*log_bin/log_bin/g"                   /etc/mysql/my.cnf
      sed -i "s/.*expire_logs_days/expire_logs_days/g" /etc/mysql/my.cnf
      sed -i "s/.*max_binlog_size/max_binlog_size/g"   /etc/mysql/my.cnf
    fi
    if [ "${_DB_ENGINE}" = "MyISAM" ] || [ "${_DB_ENGINE}" = "InnoDB" ]; then
      sed -i "s/^default_storage_engine.*/default_storage_engine  = ${_DB_ENGINE}/g" /etc/mysql/my.cnf
    fi
    if [ ! -z "${_INNODB_LOG_FILE_SIZE}" ]; then
      if [ "${_INNODB_LOG_FILE_SIZE}" -ge "10" ] \
        && [ "${_INNODB_LOG_FILE_SIZE}" -lt "501" ]; then
        _INNODB_LOG_FILE_SIZE_MB="${_INNODB_LOG_FILE_SIZE}M"
        _INNODB_LOG_FILE_SIZE_TEST=$(grep "^innodb_log_file_size" \
          /etc/mysql/my.cnf 2>&1)
        if [[ "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "= ${_INNODB_LOG_FILE_SIZE_MB}" ]]; then
          _DO_NOTHING=YES
        else
          if [ "${_INNODB_LOG_FILE_SIZE_SAME}" = "YES" ]; then
            sed -i "s/.*innodb_log_file_size.*/innodb_log_file_size    = ${_INNODB_LOG_FILE_SIZE_MB}/g" /etc/mysql/my.cnf
          else
            update_innodb_log_file_size
          fi
        fi
      fi
    fi
  fi
}

#
# Tune memory limits for SQL server.
tune_sql_memory_limits() {
  urlDld="https://raw.githubusercontent.com/major/MySQLTuner-perl/master"
  pthTun="/var/opt/mysqltuner.pl"
  outTun="/var/opt/mysqltuner-${_X_VERSION}-${_NOW}.txt"
  if [ -e "/root/.mstr.clstr.cnf" ] \
    || [ -e "/root/.wbhd.clstr.cnf" ] \
    || [ -e "/root/.dbhd.clstr.cnf" ]; then
    _GALERA_COMP=NO
  fi
  if [ ! -e "${outTun}" ] \
    && [ "${_STATUS}" = "UPGRADE" ] \
    && [ -z "$_GALERA_COMP" ]; then
    msg "INFO: Running MySQLTuner check on all databases..."
    msg "NOTE! This step may take a LONG time, please wait..."
    _MYSQLTUNER_TEST_RESULT=OK
    rm -f /var/opt/mysqltuner*
    curl ${crlGet} "${urlDld}/mysqltuner.pl" -o ${pthTun}
    if [ ! -e "${pthTun}" ]; then
      curl ${crlGet} "${urlDev}/mysqltuner.pl" -o ${pthTun}
    fi
    if [ -e "${pthTun}" ]; then
      perl ${pthTun} > ${outTun} 2>&1
    fi
  fi
  if [ -e "${pthTun}" ] \
    && [ -e "${outTun}" ] \
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
    if [ -z "$_REC_INNODB_MEM" ] \
      || [[ "$_MYSQLTUNER_TEST" =~ "Cannot calculate MyISAM index" ]] \
      || [[ "$_MYSQLTUNER_TEST" =~ "InnoDB is enabled but isn" ]]; then
      _MYSQLTUNER_TEST_RESULT=FAIL
      msg "ALRT! The MySQLTuner test failed!"
      msg "ALRT! Please review ${outTun}"
      msg "ALRT! We will use some sane SQL defaults instead, do not worry!"
    fi
    ###--------------------###
    if [ ! -z "$_REC_MYISAM_MEM" ] \
      && [ "$_MYSQLTUNER_TEST_RESULT" = "OK" ]; then
      _RAW_MYISAM_MEM=$(echo $_REC_MYISAM_MEM | sed "s/[A-Z]//g" 2>&1)
      if [[ "$_REC_MYISAM_MEM" =~ "G" ]]; then
        _RAW_MYISAM_MEM=$(( _RAW_MYISAM_MEM * 1024 ))
      fi
      if [ "$_RAW_MYISAM_MEM" -gt "${_USE_SQL}" ]; then
        _USE_MYISAM_MEM="${_USE_SQL}"
      else
        _USE_MYISAM_MEM="$_RAW_MYISAM_MEM"
      fi
      if [ "${_USE_MYISAM_MEM}" -lt "256" ] || [ -z "${_USE_MYISAM_MEM}" ]; then
        _USE_MYISAM_MEM="${_USE_SQL}"
      fi
      _USE_MYISAM_MEM="${_USE_MYISAM_MEM}M"
      sed -i "s/^key_buffer_size.*/key_buffer_size         = ${_USE_MYISAM_MEM}/g"  /etc/mysql/my.cnf
    else
      _USE_MYISAM_MEM="${_USE_SQL}M"
      if [ "$_MYSQLTUNER_TEST_RESULT" = "FAIL" ]; then
        msg "ALRT! _USE_MYISAM_MEM is ${_USE_MYISAM_MEM} because _REC_MYISAM_MEM was empty!"
      fi
      sed -i "s/^key_buffer_size.*/key_buffer_size         = ${_USE_MYISAM_MEM}/g"  /etc/mysql/my.cnf
    fi
    ###--------------------###
    if [ ! -z "$_REC_INNODB_MEM" ] && [ "$_MYSQLTUNER_TEST_RESULT" = "OK" ]; then
      _RAW_INNODB_MEM=$(echo $_REC_INNODB_MEM | sed "s/[A-Z]//g" 2>&1)
      if [[ "$_REC_INNODB_MEM" =~ "G" ]]; then
        _RAW_INNODB_MEM=$(echo "$_RAW_INNODB_MEM * 1024" | bc -l 2>&1)
      fi
      _RAW_INNODB_MEM=$(echo "($_RAW_INNODB_MEM+0.5)/1" | bc 2>&1)
      if [ "$_RAW_INNODB_MEM" -gt "${_USE_SQL}" ]; then
        _USE_INNODB_MEM="${_USE_SQL}"
      else
        _RAW_INNODB_MEM=$(echo "scale=2; ($_RAW_INNODB_MEM * 1.1)" | bc 2>&1)
        _USE_INNODB_MEM=$(echo "($_RAW_INNODB_MEM+0.5)/1" | bc 2>&1)
      fi
      _INNODB_BPI="0"
      _INNODB_BPI=$(echo "scale=0; ${_USE_INNODB_MEM}/1024" | bc 2>&1)
      if [ "$_INNODB_BPI" -gt "1" ]; then
        sed -i "s/innodb_file_per_table   = 1/innodb_file_per_table   = 1\ninnodb_buffer_pool_instances = $_INNODB_BPI/g" /etc/mysql/my.cnf
      fi
      if [ "${_USE_INNODB_MEM}" -lt "256" ] || [ -z "${_USE_INNODB_MEM}" ]; then
        _USE_INNODB_MEM="${_USE_SQL}"
      fi
      _USE_INNODB_MEM="${_USE_INNODB_MEM}M"
      sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${_USE_INNODB_MEM}/g"  /etc/mysql/my.cnf
    else
      _USE_INNODB_MEM="${_USE_SQL}M"
      msg "ALRT! _USE_INNODB_MEM is ${_USE_INNODB_MEM} because _REC_INNODB_MEM was empty!"
      sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${_USE_INNODB_MEM}/g"  /etc/mysql/my.cnf
    fi
  else
    _THIS_USE_MEM="${_USE_SQL}M"
    if [ "$_MYSQLTUNER_TEST_RESULT" = "FAIL" ] \
      && [ "${_STATUS}" = "UPGRADE" ] \
      && [ -z "$_GALERA_COMP" ]; then
      msg "ALRT! _USE_MYISAM_MEM is $_THIS_USE_MEM because _REC_MYISAM_MEM was empty!"
      msg "ALRT! _USE_INNODB_MEM is $_THIS_USE_MEM because _REC_INNODB_MEM was empty!"
    fi
    sed -i "s/= 181/= ${_USE_SQL}/g"  /etc/mysql/my.cnf
  fi
}

