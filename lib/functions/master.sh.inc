
export _tRee=lts
export _rLsn="BOA-5.88.855"
export _rlsE="${_rLsn}-${_tRee}"
export _bRnh="5.x-${_tRee}"
_hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"


#
# Update local INI for PHP CLI on the Ægir Master Instance.
_php_cli_local_ini_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_cli_local_ini_update"
  fi
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="/var/aegir/drush/${1}"
  else
    _DRUSH_FILE="/var/aegir/drush/drush.php"
  fi
  _U_HD="/var/aegir/.drush"
  _U_TP="/var/aegir/.tmp"
  _U_II="${_U_HD}/php.ini"
  _PHP_CLI_UPDATE=NO
  if [ ! -e "${_DRUSH_FILE}" ]; then
    return 1  # Exit the function but continue the script
  fi
  _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_DRUSH_FILE} 2>&1)
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
      && [ ! -e "${_U_HD}/.ctrl.php${e}.${_xSrl}.pid" ]; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
    || [ ! -e "${_U_II}" ] \
    || [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
    mkdir -p ${_U_TP}
    touch ${_U_TP}
    find ${_U_TP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
    chmod 02755 ${_U_TP}
    mkdir -p ${_U_HD}
    rm -f ${_U_HD}/.ctrl.php*
    rm -f ${_U_II}
    _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]]; then
        cp -af /opt/php${e}/lib/php.ini ${_U_II}
        _U_INI=${e}
      fi
    done
    if [ -e "${_U_II}" ]; then
      _INI="open_basedir = \".: \
        /data/all:           \
        /data/conf:          \
        /data/disk/all:      \
        /opt/php56:          \
        /opt/php70:          \
        /opt/php71:          \
        /opt/php72:          \
        /opt/php73:          \
        /opt/php74:          \
        /opt/php80:          \
        /opt/php81:          \
        /opt/php82:          \
        /opt/php83:          \
        /opt/php84:          \
        /opt/php85:          \
        /opt/tika:           \
        /opt/tika7:          \
        /opt/tika8:          \
        /opt/tika9:          \
        /dev/urandom:        \
        /opt/tmp/make_local: \
        /opt/tools/drush:    \
        /tmp:                \
        /usr/bin:            \
        /usr/local/bin:      \
        /var/aegir\""
      _INI=$(echo "${_INI}" | sed "s/ //g" 2>&1)
      _INI=$(echo "${_INI}" | sed "s/open_basedir=/open_basedir = /g" 2>&1)
      _INI=${_INI//\//\\\/}
      _QTP=${_U_TP//\//\\\/}
      sed -i "s/.*open_basedir =.*/${_INI}/g"                              ${_U_II}
      wait
      sed -i "s/.*error_reporting =.*/error_reporting = 1/g"               ${_U_II}
      wait
      sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_U_II}
      wait
      sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_U_II}
      wait
      sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_U_II}
      wait
      sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_U_II}
      wait
      echo > ${_U_HD}/.ctrl.php${_U_INI}.${_xSrl}.pid
      echo > ${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid
    fi
  fi
  chown -R aegir:aegir ${_U_HD}
  chown -R aegir:aegir ${_U_TP}
}


#
# Download and extract from core archive.
_get_core_ext() {
  if [ ! -z "${1}" ]; then
    _max_attempts=10
    _attempt_num=1
    _success=0
    while [ ${_attempt_num} -le ${_max_attempts} ]; do
      [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Attempt ${_attempt_num} of ${_max_attempts}: Downloading $1..."
      if curl ${_crlGet} "https://${_USE_MIR}/core/$1" -o "$1"; then
        _success=1
        break
      else
        [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Attempt ${_attempt_num} failed."
        _attempt_num=$((_attempt_num+1))
        if [ "${_attempt_num}" -le "${_max_attempts}" ]; then
          [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Retrying in 9 seconds..."
          sleep 9
        fi
      fi
    done
    if [ "${_success}" -eq 1 ]; then
      if [ ! -z "${2}" ]; then
        _extract_archive "${1}" "${2}"
      else
        _extract_archive "${1}"
      fi
    else
      _msg "OOPS: Failed to download https://${_USE_MIR}/core/$1 after ${_max_attempts} attempts"
      return 1  # Exit the function but continue the script
    fi
  fi
}

#
# Generate provision backend db_passwd.
_provision_backend_dbpass_generate() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _provision_backend_dbpass_generate"
  fi
  _ESC_PASS=""
  _LEN_PASS=0
  if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
    _PWD_CHARS=64
  elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
    _PWD_CHARS=32
  else
    _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
    if [ ! -z "${_STRONG_PASSWORDS}" ] \
      && [ "${_STRONG_PASSWORDS}" -gt 32 ]; then
      _PWD_CHARS="${_STRONG_PASSWORDS}"
    else
      _PWD_CHARS=32
    fi
    if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt 128 ]; then
      _PWD_CHARS=128
    fi
  fi

  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt 32 ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
        _ESC_PASS="$(openssl rand -base64 64 | tr -d '\n')"
      else
        _RANDPASS_TEST=$(randpass -V 2>&1)
        if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
          _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
        else
          _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
          _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
          _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
        fi
      fi
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _isPythonTwo="$(which python2)"
    _isPythonThree="$(which python3)"
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    if [ -x "${_isPythonThree}" ]; then
      _ENC_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${_ESC_PASS}'''))")
    elif [ -x "${_isPythonTwo}" ]; then
      _ENC_PASS=$(python2 -c "import urllib; print urllib.quote('''${_ESC_PASS}''')")
    fi
    _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
  fi

  if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt 9 ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
      _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
      _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _ENC_PASS="${_ESC_PASS}"
  fi

  echo "${_ESC_PASS}" > ${_L_SYS}
  chown aegir:aegir ${_L_SYS} &> /dev/null
  chmod 0600 ${_L_SYS}

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _THIS_DB_HOST="${_hName}"
      _SQL_CONNECT=localhost
    elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    else
      _THIS_DB_HOST=localhost
      _SQL_CONNECT=localhost
    fi
    _AEGIR_HOST="${_hName}"
  else
    _AEGIR_HOST="${_hName}"
    ### _SQL_CONNECT="${_THIS_DB_HOST}"
    ### Master Instance will use local DB server
    _SQL_CONNECT=localhost
  fi

  if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
    _AEGIR_HOST="${_hName}"
    _SQL_CONNECT=localhost
  fi

  _ESC="*.*"
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null

  if [ "${_STATUS}" = "INIT" ]; then
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL7 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_ADBU}'@'localhost';
CREATE USER IF NOT EXISTS '${_ADBU}'@'%';
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' WITH GRANT OPTION;
ALTER USER '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
  else
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL8 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _write_proxysql_adm_cnf &> /dev/null
        mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
      fi
      _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
      ${_C_SQL} "DROP USER '${_ADBU}'@'${_AEGIR_HOST}';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'${_RESOLVEIP}';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'localhost';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'127.0.0.1';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'%';" &> /dev/null
      mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_ADBU}'@'localhost';
CREATE USER IF NOT EXISTS '${_ADBU}'@'%';
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' WITH GRANT OPTION;
ALTER USER '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    fi
  fi

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _EXTRA_GRANTS=NO
  else
    _LOCAL_HOST="${_hName}"
    _find_correct_ip
    _LOCAL_IP="${_LOC_IP}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL9 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_ADBU}'@'localhost';
CREATE USER IF NOT EXISTS '${_ADBU}'@'%';
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' WITH GRANT OPTION;
ALTER USER '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
}

#
# Ensure Ægir's task queue dispatcher is enabled. BOA always drives the queue
# through hosting-dispatch, so a disabled dispatcher is drift -- it is left
# behind when hosting-setup's self-test exits non-zero during a (re)install.
# Detect and re-enable it, reporting only when a correction was needed.
_ensure_hosting_dispatch_enabled() {
  local _disp_fix
  _disp_fix=$(su -s /bin/bash - aegir -c "drush8 @hostmaster ev 'if (!variable_get(\"hosting_dispatch_enabled\", FALSE)) { variable_set(\"hosting_dispatch_enabled\", TRUE); echo \"REENABLED\"; }'" 2>/dev/null)
  if [[ "${_disp_fix}" =~ REENABLED ]]; then
    _msg "INFO: hosting_dispatch_enabled was off; task queue dispatcher re-enabled"
  fi
}

#
# Sync provision backend db_passwd.
_provision_backend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _provision_backend_dbpass_sync"
  fi
  _find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  _RESOLVEIP="${_LOC_IP}"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Syncing provision backend db_passwd..."
  fi
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _ADBU=aegir_root
  _L_SYS="/var/aegir/backups/system/.${_ADBU}.pass.txt"
  ### Never trust the moved file's inherited mode -- set 0600 explicitly.
  mv -f ${_L_SYS} ${_L_SYS}-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
  chmod 0600 ${_L_SYS}-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
  _provision_backend_dbpass_generate
  if [ ! -z "${_ESC_PASS}" ] && [ ! -z "${_ENC_PASS}" ]; then
    su -s /bin/bash - aegir -c "drush8 @hostmaster \
      sqlq \"UPDATE hosting_db_server SET db_passwd='${_ESC_PASS}' \
      WHERE db_user='${_ADBU}'\"" &> /dev/null
    wait
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    _ESC="*.*"
    _USE_DB_USER="${_ADBU}"
    _USE_AEGIR_HOST="${_hName}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL10 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    sed -i "s/mysql:\/\/${_ADBU}:.*/mysql:\/\/${_ADBU}:${_ENC_PASS}@${_SQL_CONNECT}',/g" \
      /var/aegir/.drush/server_*.alias.drushrc.php &> /dev/null
    wait
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
  su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
  wait
  rm -rf /var/aegir/.tmp/cache
  if [ -e "/var/aegir/.drush/server_localhost.alias.drushrc.php" ]; then
    su -s /bin/bash aegir -c "drush8 @hostmaster hosting-task @server_localhost \
      verify --force" &> /dev/null
  else
    su -s /bin/bash aegir -c "drush8 @hostmaster hosting-task @server_master \
      verify --force" &> /dev/null
  fi
  wait
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Running hosting-dispatch/hosting-tasks..."
  fi
  _ensure_hosting_dispatch_enabled
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-dispatch" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  # The sweeps above run their tasks synchronously (--fork=0), but a runner
  # forked by the regular dispatch can still be in flight. The master
  # upgrade is about to swap the live drush/provision trees under
  # /var/aegir; a task runner still executing from them dies on its next
  # lazy include without ever writing its final status - that write only
  # happens in the runner's own shutdown handler - leaving the task parked
  # at PROCESSING and the queue wedged behind it for the whole running-items
  # window. Give in-flight runners a bounded window to finish instead of
  # racing them; the dispatcher-side reaper heals whatever this misses.
  _QUIESCE_WAIT=0
  while pgrep -u aegir -f "drush.php.*hosting-task" > /dev/null 2>&1; do
    _QUIESCE_WAIT=$(( _QUIESCE_WAIT + 1 ))
    if [[ "${_QUIESCE_WAIT}" -ge 60 ]]; then
      break
    fi
    sleep 5
  done
}

#
# Sync hostmaster frontend db_passwd.
_hostmaster_frontend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _hostmaster_frontend_dbpass_sync"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Syncing hostmaster frontend db_passwd..."
  fi
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _THIS_HM_SPTH=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
    | grep "site_path'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
  _THIS_HM_DBUR=$(cat ${_THIS_HM_SPTH}/drushrc.php \
    | grep "options\['db_user'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1)
  _THIS_HM_DBPD=$(cat ${_THIS_HM_SPTH}/drushrc.php \
    | grep "options\['db_passwd'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1)
  if [ -e "${_THIS_HM_SPTH}" ] \
    && [ ! -z "${_THIS_HM_DBUR}" ] \
    && [ ! -z "${_THIS_HM_DBPD}" ]; then
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    _ESC="*.*"
    _USE_DB_USER="${_THIS_HM_DBUR}"
    _USE_AEGIR_HOST="${_hName}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL11 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_THIS_HM_DBPD}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_THIS_HM_DBPD}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_THIS_HM_DBPD}';
EOFMYSQL
  fi
  mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
}

#
# Download for Drush Make Local build.
_master_download_for_local_build() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _master_download_for_local_build"
  fi
  _mL="/opt/tmp/make_local"
  mkdir -p ${_mL}
  if [ ! -e "${_mL}/hostmaster/hostmaster.make" ] \
    || [ ! -e "${_mL}/hosting/hosting.module" ] \
    || [ ! -e "${_mL}/drupal/modules/system/system.module" ]; then
    rm -rf ${_mL}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading hostmaster modules..."
    fi
    if [ "${_DL_MODE}" = "BATCH" ]; then
      rm -rf /opt/tmp/make_local
      cd /opt/tmp
      _get_dev_ext "make_local.tar.gz"
      if [ -e "${_mL}/hostmaster/hostmaster.make" ] \
        && [ -e "${_mL}/hosting/hosting.module" ] \
        && [ -e "${_mL}/drupal/modules/system/system.module" ]; then
        [ -e "make_local.tar.gz" ] && rm -f make_local.tar.gz
      fi
    else
      mkdir -p ${_mL}
      cd ${_mL}
      ### Drupal Core
      _get_core_ext "${_DRUPAL7}.tar.gz"
      mv -f ${_mL}/${_DRUPAL7} ${_mL}/drupal
      ### Ægir Core
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hostmaster.git    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting.git       &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/eldir.git         &> /dev/null
      ### Ægir Golden + BOA Settings
        ${_gCb} 5.x-${_tRee} ${_gitHub}/aegir_objects.git                  &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_civicrm.git                &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_custom_settings.git        &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_deploy.git                 &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_git.git                    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_le.git                     &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_remote_import.git          &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_site_backup_manager.git    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_tasks_extra.git            &> /dev/null
        rm -rf */.git
      ### Ægir Drupal Contrib
      _get_dev_stc "admin_menu-7.x-3.0-rc7.tar.gz"
      _get_dev_stc "betterlogin-7.x-1.5.tar.gz"
      _get_dev_stc "ctools-7.x-1.21.tar.gz"
      _get_dev_stc "entity-7.x-1.12.tar.gz"
      _get_dev_stc "libraries-7.x-2.5.tar.gz"
      _get_dev_stc "module_filter-7.x-2.3.tar.gz"
      _get_dev_stc "openidadmin-7.x-1.0.tar.gz"
      _get_dev_stc "overlay_paths-7.x-1.3.tar.gz"
      _get_dev_stc "r4032login-7.x-1.8.tar.gz"
      _get_dev_stc "tfa_basic-7.x-1.1.tar.gz"
      _get_dev_stc "tfa-7.x-2.1.tar.gz"
      _get_dev_stc "timeago-7.x-2.3.tar.gz"
      _get_dev_stc "views_bulk_operations-7.x-3.7.tar.gz"
      _get_dev_stc "views-7.x-3.30.tar.gz"
      ### Ægir Third Party Libraries
      _get_dev_stc "qrcodejs.tar.gz"
      _get_dev_stc "timeagojs.tar.gz"
      _get_dev_stc "vuejs.tar.gz"
      ### BOA Drupal Contrib
      _get_dev_stc "environment_indicator-7.x-2.9.tar.gz"
      _get_dev_stc "features_extra-7.x-1.2.tar.gz"
      _get_dev_stc "features-7.x-2.15.tar.gz"
      _get_dev_stc "idna_convert-7.x-1.0.tar.gz"
      _get_dev_stc "revision_deletion-7.x-1.3.tar.gz"
      _get_dev_stc "strongarm-7.x-2.0.tar.gz"
      _get_dev_stc "tag1_d7es-7.x-1.4.tar.gz"
      _get_dev_stc "userprotect-7.x-1.3.tar.gz"
    fi
    find ${_mL} -type d -exec chmod 0755 {} \; &> /dev/null
    find ${_mL} -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R root:root ${_mL}
  fi
}

#
_php_cli_drush_update() {
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="${_ROOT}/drush/${1}"
  else
    _DRUSH_FILE="${_ROOT}/drush/drush.php"
  fi
  if [ ! -e "${_DRUSH_FILE}" ]; then
    return 1  # Exit the function but continue the script
  fi
  if [ "${_PHP_CLI_VERSION}" = "8.5" ] \
    && [ -x "/opt/php85/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php85\/bin\/php/g" \
      ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.4" ] \
    && [ -x "/opt/php84/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php84\/bin\/php/g" \
      ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.3" ] \
    && [ -x "/opt/php83/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php83\/bin\/php/g" \
      ${_DRUSH_FILE} &> /dev/null
  else
    _msg "FATAL ERROR: _PHP_CLI_VERSION must be set to one of supported values"
    _msg "FATAL ERROR: Aborting AegirM installer NOW!"
    rm -f /opt/tmp/status-AegirM-FAIL
    touch /opt/tmp/status-AegirM-FAIL
    exit 1
  fi
  # The shebang pin on drush.php is bypassed whenever the drush 8 finder
  # runs: it execs drush.launcher, which re-selects PHP via `which php`.
  # The launcher also cannot run at all via its stock `env sh` shebang,
  # because /bin/sh is websh, which refuses user-area scripts. Run it
  # under bash and default its native DRUSH_PHP to the pin -- default,
  # not override: websh exports DRUSH_PHP per invocation from the
  # static/control files (cli.info + instant phpNN.info switches), and
  # that runtime choice must always win over the baked pin.
  _DRUSH_LNCH="${_ROOT}/drush/drush.launcher"
  _LNCH_PHP="/opt/php${_PHP_CLI_VERSION//./}/bin/php"
  if [ -e "${_DRUSH_LNCH}" ] && [ -x "${_LNCH_PHP}" ]; then
    sed -i "1s/^#\!.*/#\!\/bin\/bash/" ${_DRUSH_LNCH} &> /dev/null
    sed -i "/^export DRUSH_PHP=/d" ${_DRUSH_LNCH} &> /dev/null
    sed -i "1a export DRUSH_PHP=\"\${DRUSH_PHP:-${_LNCH_PHP}}\"" ${_DRUSH_LNCH} &> /dev/null
  fi
}

#
_provision_backend_up() {
  if [ "${_DL_MODE}" = "BATCH" ]; then
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/drush_make
    rm -rf ${_ROOT}/.drush/sys/drush_make
    cd ${_ROOT}/.drush
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    _get_dev_ext "backend.tar.gz"
    mv -f ${_ROOT}/.drush/backend/sys ${_ROOT}/.drush/
    mv -f ${_ROOT}/.drush/backend/xts ${_ROOT}/.drush/
    mv -f ${_ROOT}/.drush/backend/usr ${_ROOT}/.drush/
    if [ -e "${_ROOT}/.drush/sys/provision/provision.inc" ] \
      && [ -d "${_ROOT}/.drush/xts/security_review" ] \
      && [ -d "${_ROOT}/.drush/usr/registry_rebuild" ]; then
      [ -e "${_ROOT}/.drush/backend" ] && rm -rf ${_ROOT}/.drush/backend*
    fi
  elif [ "${_DL_MODE}" = "GIT" ]; then
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/drush_make
    rm -rf ${_ROOT}/.drush/sys/drush_make
    cd ${_ROOT}/.drush
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    _rD="${_ROOT}/.drush"
    ${_gCb} ${_BRANCH_PRN} ${_gitHub}/provision.git      ${_rD}/sys/provision &> /dev/null
    ${_gCb} 7.x-1.x-dev ${_gitHub}/drupalgeddon.git      ${_rD}/usr/drupalgeddon &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/drush_ecl.git             ${_rD}/usr/drush_ecl &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/security_review.git       ${_rD}/xts/security_review &> /dev/null
    ${_gCb} 7.x-2.x ${_gitHub}/provision_boost.git       ${_rD}/xts/provision_boost &> /dev/null
    ${_gCb} 7.x-2.x ${_gitHub}/registry_rebuild.git      ${_rD}/usr/registry_rebuild &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/safe_cache_form_clear.git ${_rD}/usr/safe_cache_form_clear &> /dev/null
    rm -rf ${_rD}/*/.git
    rm -rf ${_rD}/*/*/.git
    cd ${_rD}/usr
    _get_dev_ext "clean_missing_modules.tar.gz"
    _get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    cd ${_ROOT}/.drush/sys
    _get_dev_ext "provision.tar.gz"
    cd ${_ROOT}/.drush/usr
    _get_dev_ext "clean_missing_modules.tar.gz"
    _get_dev_ext "drupalgeddon.tar.gz"
    _get_dev_ext "drush_ecl.tar.gz"
    _get_dev_ext "registry_rebuild.tar.gz"
    _get_dev_ext "safe_cache_form_clear.tar.gz"
    _get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
    cd ${_ROOT}/.drush/xts
    _get_dev_ext "provision_boost.tar.gz"
    _get_dev_ext "security_review.tar.gz"
  fi
}

#
_hostmaster_dr_up() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Downloading drush ${_DRUSH_VERSION}..."
  fi
  mkdir -p ${_ROOT}/backups/system
  chmod 700 ${_ROOT}/backups/system
  cd ${_ROOT}
  if [ -f "/opt/tools/drush/8/drush/drush.php" ]; then
    mv -f drush ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} &> /dev/null
    cp -af /opt/tools/drush/8/drush ${_ROOT}/
  else
    mv -f drush ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} &> /dev/null
    _get_dev_ext "drush-${_DRUSH_VERSION}.tar.gz"
    cd ${_ROOT}/drush/
    find ${_ROOT}/drush -type d -exec chmod 0755 {} \; &> /dev/null
    find ${_ROOT}/drush -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 755 ${_ROOT}/drush/drush
    chmod 755 ${_ROOT}/drush/drush.complete.sh
    chmod 755 ${_ROOT}/drush/drush.launcher
    chmod 755 ${_ROOT}/drush/drush.php
    chmod 755 ${_ROOT}/drush/unish.sh
    chmod 755 ${_ROOT}/drush/examples/drush.wrapper
    chmod 755 ${_ROOT}/drush/examples/git-bisect.example.sh
    chmod 755 ${_ROOT}/drush/examples/helloworld.script
  fi
}

#
# Upgrade Ægir Master Instance.
_aegir_master_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _aegir_master_upgrade"
  fi
  if _prompt_yes_no "Do you want to upgrade Ægir Master Instance?" ; then
    true
    _msg "INFO: Running Ægir Master Instance upgrade"
    if [ -x "/usr/bin/mysql_upgrade" ]; then
      _check_mysql_version
      if [ "${_DB_V}" = "5.7" ]; then
        _mrun "mysql_upgrade -u root --force"
      fi
    fi
    if [ -e "/var/aegir/use_proxysql.txt" ]; then
      _SQL_CONNECT=127.0.0.1
      _THIS_DB_PORT=6033
    else
      _THIS_DB_PORT=3306
    fi
    rm -f /opt/tmp/testecho*
    usermod -aG users aegir
    _sudoers_safe_append /etc/sudoers \
      "aegir ALL=NOPASSWD: /etc/init.d/nginx" "aegir ALL=NOPASSWD"
    _SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership fix-drupal-site-symlinks lock-local-drush-permissions)
    for SCRIPT in ${_SCRIPTS[@]}; do
      _sudoers_safe_append /etc/sudoers.d/${SCRIPT} \
        "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh"
    done

    _hostmaster_dr_up

    if [ ! -d "/var/aegir/.drush/sys/provision/http" ] \
      || [ ! -d "/var/aegir/drush/includes" ]; then
      rm -rf /var/aegir/.drush/{sys,xts,usr}
      rm -rf /var/aegir/.drush/{provision,drush_make}
      mkdir -p /var/aegir/.drush/{sys,xts,usr}
      ${_gCb} ${_BRANCH_PRN} ${_gitHub}/provision.git /var/aegir/.drush/sys/provision &> /dev/null
    fi
    _THIS_HM_ROOT=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
      | grep "root'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    _THIS_HM_SITE=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
      | grep "site_path'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    mkdir -p ${_THIS_HM_ROOT}/sites/all/{modules,themes,libraries}
    chown -R aegir:aegir ${_THIS_HM_ROOT}/sites/all
    _U_HD="/var/aegir/.drush"
    if [ -e "${_U_HD}/php.ini" ]; then
      chattr -i ${_U_HD}/php.ini
    fi
    mkdir -p /var/aegir/backups/system
    chmod 700 /var/aegir/backups/system
    chown -R aegir:aegir /var/aegir/.drush
    chown -R aegir:aegir /var/aegir/backups
    chown -R aegir:aegir /var/aegir/clients
    chown -R aegir:aegir /var/aegir/config
    chown -R aegir:aegir /var/aegir/drush
    chown -R aegir ${_THIS_HM_ROOT}
    chown -R aegir:www-data ${_THIS_HM_SITE}/files
    chmod -R 02775 ${_THIS_HM_SITE}/files

    # Never serialize an empty PHP version: the drush shebang update just
    # below hard-exits on an unresolved value, and the appends further down
    # shadow the template's shipped default, so an empty value here would
    # reach the su'd child as-is and break its version branch table
    if [ -z "${_PHP_CLI_VERSION}" ]; then
      _cliPhpBin=$(readlink -f /usr/bin/php 2>/dev/null)
      _cliPhpNum="${_cliPhpBin%/bin/php}"
      _cliPhpNum="${_cliPhpNum##*php}"
      if [ -n "${_cliPhpNum}" ] && [ -x "/opt/php${_cliPhpNum}/bin/php" ]; then
        _PHP_CLI_VERSION="${_cliPhpNum:0:1}.${_cliPhpNum:1}"
      else
        for _fbV in 84 85 83; do
          if [ -x "/opt/php${_fbV}/bin/php" ]; then
            _PHP_CLI_VERSION="${_fbV:0:1}.${_fbV:1}"
            break
          fi
        done
      fi
      if [ -z "${_PHP_CLI_VERSION}" ]; then
        _PHP_CLI_VERSION=8.4
      fi
    fi
    if [ -z "${_PHP_FPM_VERSION}" ]; then
      _PHP_FPM_VERSION="${_PHP_CLI_VERSION}"
    fi

    _DRUSH_FILES="drush.php drush"
    for _df in ${_DRUSH_FILES}; do
      _php_cli_drush_update "${_df}"
    done

    export _xSrl=588855ltsT01
    export _X_VERSION="${_X_VERSION}"

    # Refuse to hand off provably broken values: an empty front domain or
    # mirror here means a guaranteed child fatal much later, with far
    # worse diagnostics than failing loudly now
    for _hndVar in _THIS_FRONT _USE_MIR; do
      if [ -z "${!_hndVar}" ]; then
        _msg "FATAL ERROR: ${_hndVar} is empty, AegirUpgrade hand-off aborted"
        _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
        rm -f /opt/tmp/status-Barracuda-FAIL
        touch /opt/tmp/status-Barracuda-FAIL
        _clean_pid_exit _aegir_master_upgrade_b
      fi
    done

    # Build the per-spawn child include on a private same-dir temp copy
    # and swap it in place 0600 aegir-owned: AegirUpgrade sources ONLY
    # this file and the values must never be half-written nor readable
    # by other local users; the shared barracuda.sh.cnf stays root's own
    # load path and no longer carries these appends
    _hndIncB="${_filIncB}.AegirUpgrade"
    _tmpIncB="${_vBs}/.${_hndIncB}.tmp"
    rm -f ${_tmpIncB}
    cp -af ${_vBs}/${_filIncB} ${_tmpIncB}
    chown aegir:aegir ${_tmpIncB} &> /dev/null
    chmod 0600 ${_tmpIncB}

    echo "_AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${_tmpIncB}
    echo "_AEGIR_XTS_VRN=\"${_tRee}\""                  >> ${_tmpIncB}
    echo "_BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${_tmpIncB}
    echo "_BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${_tmpIncB}
    echo "_BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${_tmpIncB}
    echo "_BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${_tmpIncB}
    echo "_DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${_tmpIncB}
    echo "_DL_MODE=\"${_DL_MODE}\""                     >> ${_tmpIncB}
    echo "_DOMAIN=\"${_THIS_FRONT}\""                   >> ${_tmpIncB}
    echo "_DRUPAL7=\"${_DRUPAL7}\""                     >> ${_tmpIncB}
    echo "_DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${_tmpIncB}
    echo "_NOW=\"${_NOW}\""                             >> ${_tmpIncB}
    echo "_PHP_CLI_VERSION=\"${_PHP_CLI_VERSION}\""     >> ${_tmpIncB}
    echo "_PHP_FPM_VERSION=\"${_PHP_FPM_VERSION}\""     >> ${_tmpIncB}
    echo "_SMALLCORE7_V=\"${_SMALLCORE7_V}\""           >> ${_tmpIncB}
    echo "_STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${_tmpIncB}
    echo "_THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${_tmpIncB}
    echo "_USE_MIR=\"${_USE_MIR}\""                     >> ${_tmpIncB}
    echo "_xSrl=\"${_xSrl}\""                           >> ${_tmpIncB}
    echo "_X_VERSION=\"${_X_VERSION}\""                 >> ${_tmpIncB}
    # The seal must stay the LAST line: the child asserts it after
    # sourcing, so any truncated append sequence is detected, not used
    echo "_HANDOFF_SEAL=\"AegirUpgrade\""               >> ${_tmpIncB}

    mv -f ${_tmpIncB} ${_vBs}/${_hndIncB}

    mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG HOSTS" &> /dev/null
    _RST=$(syncpass fix aegir 2>&1)
    _find_correct_ip
    _USE_RESOLVEIP="${_LOC_IP}"
    _RESOLVEIP="${_LOC_IP}"
    _provision_backend_dbpass_sync
    _hostmaster_frontend_dbpass_sync
    _master_download_for_local_build

    ### Make sure that required web services are up and running
    _mrun "webserver up"

    ###
    AegirUpgrade="${_bldPth}/aegir/scripts/AegirUpgrade.sh.txt"
    # Same state dir AegirSetupM signals in: root owns the state root, aegir
    # owns its own dir. Stale markers from an earlier run are purged first, so
    # an old FAIL cannot veto a clean run and an old OK cannot vouch for a run
    # that died before stamping (the satellite twin does this in its
    # pre-cleanup; the master had no purge at all).
    mkdir -p /opt/tmp/state/aegir &> /dev/null
    chown root:root /opt/tmp/state &> /dev/null
    chmod 0755 /opt/tmp/state &> /dev/null
    chown aegir:aegir /opt/tmp/state/aegir &> /dev/null
    chmod 0700 /opt/tmp/state/aegir &> /dev/null
    rm -f /opt/tmp/state/aegir/status-AegirUpgrade-FAIL \
      /opt/tmp/state/aegir/status-AegirUpgrade-OK \
      /opt/tmp/status-AegirUpgrade-FAIL &> /dev/null
    su -s /bin/bash - aegir -c "/bin/bash ${AegirUpgrade} aegir"
    wait
    ###

    if [ -e "/opt/tmp/state/aegir/status-AegirUpgrade-FAIL" ] \
      || [ ! -e "/opt/tmp/state/aegir/status-AegirUpgrade-OK" ]; then
      _msg "FATAL ERROR: AegirUpgrade installer failed"
      _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
      rm -f /opt/tmp/status-Barracuda-FAIL
      touch /opt/tmp/status-Barracuda-FAIL
      _clean_pid_exit _aegir_master_upgrade_a
    else
      # Consumed once; kept only on failure for post-mortem reading
      rm -f ${_vBs}/${_hndIncB}
      if [ -e "${_U_HD}/php.ini" ]; then
        chattr +i ${_U_HD}/php.ini
      fi
      _hostmaster_frontend_dbpass_sync
    fi
    if [ ! -L "${_mtrInc}/global.inc" ] && [ -e "${_mtrInc}/global.inc" ]; then
      mv -f ${_mtrInc}/global.inc \
        ${_mtrInc}/global.inc-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    fi
    ### Deploy the full global include set (per-core chain + dispatcher);
    ### the dispatcher alone would be inert without the chain.
    _global_inc_conf_update
    if [ -e "${_mtrInc}" ] && [ ! -L "${_mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${_mtrInc}/global.inc
    fi
    if [ -e "/etc/init.d/valkey-server" ]; then
      _valkey_password_update
    elif [ -e "/etc/init.d/redis-server" ]; then
      _redis_password_update
    fi
    _force_advanced_nginx_config
    cd /var/aegir
    if [ -d "${_mtrNgx}/conf.d" ]; then
      if [ ! -d "${_mtrNgx}/pre.d" ]; then
        cd ${_mtrNgx}
        cp -a conf.d pre.d
      else
        rm -rf ${_mtrNgx}/conf.d
      fi
      if [ -e "${_mtrNgx}/pre.d/custom_nginx.conf" ]; then
        rm -f ${_mtrNgx}/pre.d/custom_nginx.conf
      fi
    fi
    find /var/aegir/host_master/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/host_master/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R aegir:aegir /var/aegir/.drush &> /dev/null
    chown -R aegir:aegir /var/aegir/.tmp &> /dev/null
    find /var/aegir/.drush -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/.drush -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 0440 /var/aegir/.drush/*.php &> /dev/null
    chmod 0711 /var/aegir/.drush &> /dev/null
    _msg "INFO: Ægir Master Instance upgrade completed"
  else
    _msg "INFO: Ægir Master Instance not upgraded this time"
  fi
  rm -f /var/aegir/*install.sh.txt
}

#
# Update php-cli in the cron entry.
_php_cli_cron_update() {
  local _mCron
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_cli_cron_update"
  fi
  # Key the target name on the ROLE, not on runner.sh's artifact: on a
  # standby the dispatch must stay parked across an Aegir master upgrade
  # (a live crontab minted beside the parked copy re-armed it), while on
  # every other box -- including a CI box mid-upgrade, whose "fail toward
  # enabled" contract needs the dispatch LIVE for its verify tasks -- the
  # live name wins and a leftover parked copy is cleared; runner.sh's own
  # grace logic re-parks an idle CI box afterwards.
  if [ -e "/root/.standby.cnf" ]; then
    _mCron="/var/spool/cron/crontabs/.aegir"
    rm -f /var/spool/cron/crontabs/aegir
  else
    _mCron="/var/spool/cron/crontabs/aegir"
    rm -f /var/spool/cron/crontabs/.aegir
  fi
  rm -f "${_mCron}"
  if [ ! -e "${_mCron}" ]; then
    #_DRUSH_HOSTING_TASKS_CMD="/usr/bin/drush @hostmaster hosting-tasks --force;"
    _DRUSH_HOSTING_DISPATCH_CMD="/usr/bin/env php /var/aegir/drush/drush.php @hostmaster hosting-dispatch"
    echo -e \
    "\nSHELL=/bin/sh\nPATH=/opt/php84/bin:/usr/bin\n\n*/1 * * * * \
    ${_DRUSH_HOSTING_DISPATCH_CMD}" \
    | fmt -su -w 2500 \
    | tee -a "${_mCron}" >/dev/null 2>&1
  fi
  if [ -e "${_mCron}" ]; then
    if [ "${_PHP_CLI_VERSION}" = "8.5" ] && [ -x "/opt/php85/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php85\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        "${_mCron}" &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "8.4" ] && [ -x "/opt/php84/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php84\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        "${_mCron}" &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php83\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        "${_mCron}" &> /dev/null
    fi
    chown aegir:crontab "${_mCron}" &> /dev/null
    chmod 600 "${_mCron}"
  fi
}

#
# Add allow-snail group if not exists.
_add_allow_snail_if_not_exists() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _add_allow_snail_if_not_exists"
  fi
  _SNAIL_EXISTS=$(getent group allow-snail 2>&1)
  if [[ ! "${_SNAIL_EXISTS}" =~ "allow-snail" ]]; then
    addgroup --system allow-snail &> /dev/null
  fi
}

#
# Unlock sendmail for allow-snail group
_unlock_sendmail_for_snail() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _unlock_sendmail_for_snail"
  fi
  _add_allow_snail_if_not_exists
  chown root /usr/sbin/sendmail &> /dev/null
  chgrp allow-snail /usr/sbin/sendmail &> /dev/null
}

_aegir_master_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _aegir_master_install_upgrade"
  fi

  if [ "${_STATUS}" = "INIT" ]; then

  ###--------------------###
    if [ ! -e "/run/mysqld/mysqld.pid" ] \
      || [ ! -e "/run/mysqld/mysqld.sock" ]; then
      _msg "ALRT! ${_DB_SERVER} server not running properly!"
      _msg "EXIT: We can't proceed and will exit now"
      _msg "HINT: Please check for more information two log files:"
      _msg "INFO:   ${_LOG_INFO}"
      _msg "ERRR:   ${_LOG_ERRR}"
      _msg "HINT: (re)start ${_DB_SERVER} server, then run the installer again"
      _msg "Bye"
      [ -e "/root/.my.pass.txt" ] && rm -f /root/.my.pass.txt
      mkdir -p /var/aegir
      _clean_pid_exit _aegir_master_install_upgrade_a
    fi

  ###--------------------###
    _msg "INFO: Installing Ægir Master Instance..."
    adduser --system --group --home /var/aegir aegir &> /dev/null
    usermod -aG www-data aegir
    usermod -aG users aegir
    _sudoers_safe_append /etc/sudoers \
      "aegir ALL=NOPASSWD: /etc/init.d/nginx" "aegir ALL=NOPASSWD"

    _unlock_sendmail_for_snail
    if getent group allow-snail >/dev/null 2>&1 && \
      ! id -nG "aegir" 2>/dev/null | tr ' ' '\n' | grep -qxF "allow-snail"; then
      usermod -aG allow-snail aegir
    fi
    chmod 755 /usr/sbin/sendmail &> /dev/null

    ln -sfn /var/aegir/config/nginx.conf /etc/nginx/conf.d/aegir.conf &> /dev/null
    _nginx_conf_update

    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _THIS_DB_HOST="${_hName}"
        _SQL_CONNECT=localhost
      elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
        _SQL_CONNECT=127.0.0.1
      else
        _THIS_DB_HOST=localhost
        _SQL_CONNECT=localhost
      fi
      _AEGIR_HOST="${_hName}"
    else
      _AEGIR_HOST="${_hName}"
      ### _SQL_CONNECT="${_THIS_DB_HOST}"
      ### Master Instance will use local DB server
      _SQL_CONNECT=localhost
    fi
    if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
      _AEGIR_HOST="${_hName}"
      _SQL_CONNECT=localhost
    fi

    _find_correct_ip
    _RESOLVEIP="${_LOC_IP}"
    if [ -z "${_RESOLVEIP}" ]; then
      _msg "FATAL ERROR: DNS looks broken for server ${_AEGIR_HOST}"
      _clean_pid_exit _aegir_master_install_upgrade_b
    else
      _AEGIR_HOST_IP="${_RESOLVEIP}"
    fi

    if [ "${_VMFAMILY}" != "AWS" ]; then
      _MYSQLTEST=$(mysql --silent -u root -h${_AEGIR_HOST_IP} -uINVALIDLOGIN -pINVALIDPASS 2>&1 >/dev/null | cat)
      if [ -z `echo ${_MYSQLTEST} | grep -q "ERROR \(2003\|1130\)"` ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: ${_DB_SERVER} is listening on ${_AEGIR_HOST_IP}."
        fi
      else
        _msg "FATAL ERROR: ${_DB_SERVER} is not configured to listen on ${_AEGIR_HOST_IP}"
        _clean_pid_exit _aegir_master_install_upgrade_c
      fi
    fi

    _AEGIR_DB_USER=aegir_root
    _ESC_PASS=""
    _LEN_PASS=0

    if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
      _PWD_CHARS=64
    elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
      _PWD_CHARS=32
    else
      _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
      if [ ! -z "${_STRONG_PASSWORDS}" ] \
        && [ "${_STRONG_PASSWORDS}" -gt 32 ]; then
        _PWD_CHARS="${_STRONG_PASSWORDS}"
      else
        _PWD_CHARS=32
      fi
      if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt 128 ]; then
        _PWD_CHARS=128
      fi
    fi

    if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt 32 ]; then
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
          _ESC_PASS="$(openssl rand -base64 64 | tr -d '\n')"
        else
          _RANDPASS_TEST=$(randpass -V 2>&1)
          if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
            _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
          else
            _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
            _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
            _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
          fi
        fi
      else
        if [ -e "/root/.my.pass.txt" ]; then
          _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
        else
          _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
        fi
      fi
      _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
      _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
    fi

    if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt 9 ]; then
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
        _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
      else
        if [ -e "/root/.my.pass.txt" ]; then
          _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
        else
          _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
        fi
      fi
    fi

    _ESC="*.*"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL12 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_AEGIR_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_AEGIR_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_AEGIR_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_AEGIR_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_AEGIR_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL

    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _EXTRA_GRANTS=NO
    else
      _LOCAL_HOST="${_hName}"
      _find_correct_ip
      _LOCAL_IP="${_LOC_IP}"
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL13 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _write_proxysql_adm_cnf &> /dev/null
        mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_AEGIR_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_AEGIR_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_AEGIR_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
      fi
      mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_AEGIR_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_AEGIR_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_AEGIR_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    fi

    export _xSrl=588855ltsT01
    export _X_VERSION="${_X_VERSION}"

    # Never serialize an empty PHP version: these appends shadow the
    # template's shipped default, so an empty value here would reach the
    # su'd child as-is and break its version branch table
    if [ -z "${_PHP_CLI_VERSION}" ]; then
      _cliPhpBin=$(readlink -f /usr/bin/php 2>/dev/null)
      _cliPhpNum="${_cliPhpBin%/bin/php}"
      _cliPhpNum="${_cliPhpNum##*php}"
      if [ -n "${_cliPhpNum}" ] && [ -x "/opt/php${_cliPhpNum}/bin/php" ]; then
        _PHP_CLI_VERSION="${_cliPhpNum:0:1}.${_cliPhpNum:1}"
      else
        for _fbV in 84 85 83; do
          if [ -x "/opt/php${_fbV}/bin/php" ]; then
            _PHP_CLI_VERSION="${_fbV:0:1}.${_fbV:1}"
            break
          fi
        done
      fi
      if [ -z "${_PHP_CLI_VERSION}" ]; then
        _PHP_CLI_VERSION=8.4
      fi
    fi
    if [ -z "${_PHP_FPM_VERSION}" ]; then
      _PHP_FPM_VERSION="${_PHP_CLI_VERSION}"
    fi

    # Refuse to hand off provably broken values: each of these fatals the
    # child (aegir_host/db_user/db_pass args, the distro path, the mirror
    # fetches) and none is a legitimate empty state on the INIT path
    for _hndVar in _AEGIR_HOST _AEGIR_DB_USER _ESC_PASS \
      _AEGIR_VERSION _USE_MIR; do
      if [ -z "${!_hndVar}" ]; then
        _msg "FATAL ERROR: ${_hndVar} is empty, AegirSetupM hand-off aborted"
        _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
        rm -f /opt/tmp/status-Barracuda-FAIL
        touch /opt/tmp/status-Barracuda-FAIL
        _clean_pid_exit _aegir_master_install_upgrade_h
      fi
    done

    # Build the per-spawn child include on a private same-dir temp copy
    # and swap it in place 0600 aegir-owned: the Ægir DB password lands in
    # this file, so it must never be half-written nor readable by other
    # local users; AegirSetupM sources ONLY this file and the shared
    # barracuda.sh.cnf stays root's own load path
    _hndIncB="${_filIncB}.AegirSetupM"
    _tmpIncB="${_vBs}/.${_hndIncB}.tmp"
    rm -f ${_tmpIncB}
    cp -af ${_vBs}/${_filIncB} ${_tmpIncB}
    chown aegir:aegir ${_tmpIncB} &> /dev/null
    chmod 0600 ${_tmpIncB}

    echo "_AEGIR_DB_USER=\"${_AEGIR_DB_USER}\""         >> ${_tmpIncB}
    echo "_AEGIR_HOST=\"${_AEGIR_HOST}\""               >> ${_tmpIncB}
    echo "_AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${_tmpIncB}
    echo "_AEGIR_XTS_VRN=\"${_tRee}\""                  >> ${_tmpIncB}
    echo "_BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${_tmpIncB}
    echo "_BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${_tmpIncB}
    echo "_BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${_tmpIncB}
    echo "_BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${_tmpIncB}
    echo "_DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${_tmpIncB}
    echo "_DL_MODE=\"${_DL_MODE}\""                     >> ${_tmpIncB}
    echo "_DOMAIN=\"${_THIS_FRONT}\""                   >> ${_tmpIncB}
    echo "_DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${_tmpIncB}
    echo "_ESC_PASS=\"${_ESC_PASS}\""                   >> ${_tmpIncB}
    echo "_LOCAL_NETWORK_IP=\"${_LOCAL_NETWORK_IP}\""   >> ${_tmpIncB}
    echo "_MY_OWNIP=\"${_MY_OWNIP}\""                   >> ${_tmpIncB}
    echo "_NOW=\"${_NOW}\""                             >> ${_tmpIncB}
    echo "_PHP_CLI_VERSION=\"${_PHP_CLI_VERSION}\""     >> ${_tmpIncB}
    echo "_PHP_FPM_VERSION=\"${_PHP_FPM_VERSION}\""     >> ${_tmpIncB}
    echo "_STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${_tmpIncB}
    echo "_THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${_tmpIncB}
    echo "_USE_MIR=\"${_USE_MIR}\""                     >> ${_tmpIncB}
    echo "_xSrl=\"${_xSrl}\""                           >> ${_tmpIncB}
    echo "_X_VERSION=\"${_X_VERSION}\""                 >> ${_tmpIncB}
    # The seal must stay the LAST line: the child asserts it after
    # sourcing, so any truncated append sequence is detected, not used
    echo "_HANDOFF_SEAL=\"AegirSetupM\""                >> ${_tmpIncB}

    mv -f ${_tmpIncB} ${_vBs}/${_hndIncB}

    ###  Download Drupal core and modules
    _master_download_for_local_build

    ### Make sure that required web services are up and running
    _mrun "webserver up"

    ###
    AegirSetupM="${_bldPth}/aegir/scripts/AegirSetupM.sh.txt"
    mkdir -p /opt/tmp/state/aegir &> /dev/null
    chown root:root /opt/tmp/state &> /dev/null
    chmod 0755 /opt/tmp/state &> /dev/null
    chown aegir:aegir /opt/tmp/state/aegir &> /dev/null
    chmod 0700 /opt/tmp/state/aegir &> /dev/null
    # Per-run purge, the master-side mirror of _satellite_pre_cleanup: a FAIL
    # left by an earlier attempt would veto every later run, a stale OK would
    # vouch for a child killed before it could stamp.
    rm -f /opt/tmp/state/aegir/status-AegirSetupM-FAIL \
      /opt/tmp/state/aegir/status-AegirSetupM-OK &> /dev/null
    ###

    touch /var/log/boa/aegir_install.log
    chown aegir:aegir /var/log/boa/aegir_install.log
    # 0600 (not the default 0644): the install log captures the Ægir
    # one-time-login URL — readable by any local user during the URL's
    # TTL would let a tenant race the admin to redeem it as Hostmaster.
    chmod 0600 /var/log/boa/aegir_install.log

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      su -s /bin/bash - aegir -c "/bin/bash ${AegirSetupM} ${_THIS_FRONT} \
        --http_service_type='nginx' \
        --aegir_db_host='${_THIS_DB_HOST}' \
        --client_email='${_MY_EMAIL}' -y -d" \
      2>&1 | tee /var/log/boa/aegir_install.log
    else
      su -s /bin/bash - aegir -c "/bin/bash ${AegirSetupM} ${_THIS_FRONT} \
        --http_service_type='nginx' \
        --aegir_db_host='${_THIS_DB_HOST}' \
        --client_email='${_MY_EMAIL}' -y" \
      >/var/log/boa/aegir_install.log 2>&1
    fi
    wait

    _php_cli_local_ini_update

    if [ -e "/opt/tmp/state/aegir/status-AegirSetupM-FAIL" ] \
      || [ ! -e "/opt/tmp/state/aegir/status-AegirSetupM-OK" ]; then
      _msg "FATAL ERROR: AegirSetupM installer failed"
      _msg "FATAL ERROR: Aborting Barracuda installer NOW!"
      _msg "HINT: Please check /var/log/boa/aegir_install.log"
      _msg "HINT: for more information on errors occured"
      rm -f /opt/tmp/status-Barracuda-FAIL
      touch /opt/tmp/status-Barracuda-FAIL
      _clean_pid_exit _aegir_master_install_upgrade_d
    fi
    # Consumed once and it carries the Ægir DB password; kept only on
    # failure (the exit above) for post-mortem reading
    rm -f ${_vBs}/${_hndIncB}
    if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      _THIS_HM_ROOT=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_ROOT}/sites/all" ] \
        && [ ! -e "${_THIS_HM_ROOT}/sites/all/libraries" ]; then
        mkdir -p \
          ${_THIS_HM_ROOT}/sites/all/{modules,themes,libraries} &> /dev/null
      fi
    fi
    _U_HD="/var/aegir/.drush"
    if [ -e "${_U_HD}/php.ini" ]; then
      chattr +i ${_U_HD}/php.ini
    fi
    su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
    wait
    rm -rf /var/aegir/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Running hosting-dispatch/hosting-tasks..."
    fi
    _ensure_hosting_dispatch_enabled
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-dispatch" &> /dev/null
    wait
    sleep 5
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
    wait
    sleep 5
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
    wait
    sleep 5
    su -s /bin/bash - aegir -c "drush8 @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
    wait
    if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      _THIS_HM_ROOT=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_ROOT}/sites/all" ] \
        && [ ! -e "${_THIS_HM_ROOT}/sites/all/libraries" ]; then
        mkdir -p \
          ${_THIS_HM_ROOT}/sites/all/{modules,themes,libraries} &> /dev/null
      fi
    fi
    chown -R aegir:aegir ${_THIS_HM_ROOT}/sites/all &> /dev/null

  ###--------------------###
    if [ -e "${_mtrInc}/nginx_vhost_common.conf" ]; then
      _DO_NOTHING=YES
      [ -e "/root/.force.reinstall.cnf" ] && rm -f /root/.force.reinstall.cnf
    else
      _msg "FATAL ERROR: Something went wrong, Ægir Master Instance not installed!"
      _msg "HINT: Please check /var/log/boa/aegir_install.log for details, and then"
      _msg "HINT: run the same install command again to complete installation."
      _msg "HINT: You can also enforce installation with empty control file:"
      _msg "      touch /root/.force.reinstall.cnf -- and then try again."
      _clean_pid_exit _aegir_master_install_upgrade_e
    fi

  ###--------------------###
    if [ ! -L "${_mtrInc}/global.inc" ] && [ -e "${_mtrInc}/global.inc" ]; then
      mv -f ${_mtrInc}/global.inc \
        ${_mtrInc}/global.inc-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    fi
    ### Deploy the full global include set (per-core chain + dispatcher);
    ### the dispatcher alone would be inert without the chain.
    _global_inc_conf_update
    if [ -e "${_mtrInc}" ] \
      && [ ! -L "${_mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${_mtrInc}/global.inc
    fi
    if [ -e "/etc/init.d/valkey-server" ]; then
      _valkey_password_update
    elif [ -e "/etc/init.d/redis-server" ]; then
      _redis_password_update
    fi
    _force_advanced_nginx_config
    chmod 0711 ${_mtrInc} &> /dev/null
    chmod 0711 /var/aegir/config &> /dev/null
    find /var/aegir/host_master/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/host_master/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R aegir:aegir /var/aegir/.drush &> /dev/null
    find /var/aegir/.drush -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/.drush -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 0440 /var/aegir/.drush/*.php &> /dev/null
    chmod 0711 /var/aegir/.drush &> /dev/null
    cd /var/aegir
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/modules-enabled/*
    if [ -e "${_locCnf}/nginx/nginx.conf" ]; then
      mv -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf-old &> /dev/null
      cp -af ${_locCnf}/nginx/nginx.conf /etc/nginx/nginx.conf
    fi
    _mrun "service nginx reload"
    _msg "INFO: Ægir Master Instance installed"
  else
    if [ "${_tRee}" = "lts" ]; then
      _SERIES_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
      if [[ "${_SERIES_TEST}" =~ "Barracuda ${_rLsn}-pro" ]]; then
        _msg "ERROR: Your system has been already upgraded to ${_rLsn}-pro"
        _msg "You can not downgrade back to previous/older/lts BOA version"
        _msg "Please use 'barracuda up-pro system' to upgrade this server"
        _msg "Display all supported commands with: barracuda help"
        _msg "Bye"
        _clean_pid_exit _aegir_master_install_upgrade_f
      fi
    fi
    echo " "
    if [ -e "/root/.debug-barracuda-installer.cnf" ] \
      || [ -e "/root/.skip-aegir-master-upgrade.cnf" ]; then
      _SYSTEM_UP_ONLY=YES
    fi
    _if_to_do_fix
    if [ "${_DO_FIX}" = "YES" ]; then
      _msg "INFO: Ægir Master Instance upgrade skipped!"
      echo " "
      _msg "NOTE! You must reboot the server and run barracuda upgrade"
      _msg "NOTE! again to complete all system upgrades and upgrade also"
      _msg "NOTE! Ægir Master Instance."
      echo " "
    elif [ "${_SYSTEM_UP_ONLY}" = "YES" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Ægir Master Instance upgrade skipped"
      fi
    elif [ -e "/root/.standby.cnf" ]; then
      # The standby steer guarantees only the FLAVOR (_outP=system); the
      # _SYSTEM_UP_ONLY probe above keys on two master artefacts and fails
      # OPEN when either is missing, which on a damaged standby would run
      # the master upgrade -- drush updb plus DROP USER/GRANT churn --
      # against the replicated hostmaster DB. The role marker wins.
      _msg "NOTE: replication standby -- Ægir Master Instance upgrade refused"
    else
      if [ ! -e "/run/mysqld/mysqld.pid" ] \
        || [ ! -e "/run/mysqld/mysqld.sock" ]; then
        _msg "ALRT! ${_DB_SERVER} server not running properly!"
        _msg "EXIT: We can't proceed and will exit now"
        _msg "HINT: Please check for more information two log files:"
        _msg "INFO:   ${_LOG_INFO}"
        _msg "ERRR:   ${_LOG_ERRR}"
        _msg "HINT: (re)start ${_DB_SERVER} server, then run the installer again"
        _msg "Bye"
        _clean_pid_exit _aegir_master_install_upgrade_g
      fi
      _php_cli_cron_update
      _aegir_master_upgrade
      _php_cli_cron_update
    fi
  fi
}

_if_upgrade_only_aegir_master() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_upgrade_only_aegir_master"
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ "${_AEGIR_UPGRADE_ONLY}" = "YES" ] \
      && [ "${_SYSTEM_UP_ONLY}" = "NO" ]; then
      _php_cli_cron_update
      _aegir_master_upgrade
      _php_cli_cron_update
      sleep 8
      _mrun "service nginx reload"
      _finale
      exit 0
    fi
  fi
}

_aegir_master_display_login_link() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _aegir_master_display_login_link"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ "${_EASY_SETUP}" != "LOCAL" ]; then
      _mrun "bash /usr/sbin/apticron"
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      _AEGIR_LOGIN_URL=$(tail --lines=11 /var/log/boa/aegir_install.log | grep --text "^http:" 2>&1)
      if [ ! -z "${_AEGIR_LOGIN_URL}" ]; then
        echo " "
        _msg "INFO: Congratulations, Ægir Master have been installed successfully!"
#         _msg "NOTE! Please wait 3 min before visiting Ægir at:"
#         echo " "
#         _msg "LINK: ${_AEGIR_LOGIN_URL}"
#         echo " "
#         _msg "NOTE! The initial one-time login link will no longer work."
#         sleep 3
#         _msg "To access your Barracuda Ægir control panel after the procedure is finished..."
#         _msg "...please generate a new link by running the following command:"
#         sleep 3
#         echo " "
#         echo "  su -s /bin/bash aegir -c \"drush @hm uli\""
#         echo " "
        sleep 3
      else
        _msg "ALRT! Something went wrong"
        _msg "ALRT! Please check the install log for details:"
        _msg "ALRT! /var/log/boa/aegir_install.log"
      fi
    fi
  fi
  if [ ! -e "${_pthLog}/cron_aegir_off.pid" ]; then
    touch ${_pthLog}/cron_aegir_off.pid
  fi
}

