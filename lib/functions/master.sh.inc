#
# Generate provision backend db_passwd.
provision_backend_dbpass_generate() {
  _ESC_APASS=""
  _LEN_APASS=0
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
    if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt "128" ]; then
      _PWD_CHARS=128
    fi
  fi

  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt "8" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
        _ESC_APASS="$(openssl rand -base64 32 2>&1)"
      else
        _ESC_APASS=$(randpass "${_PWD_CHARS}" esc 2>&1)
      fi
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_APASS=$(cat /root/.my.pass.txt 2>&1)
      else
        _ESC_APASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _ESC_APASS=$(echo -n "${_ESC_APASS}" | tr -d "\n" 2>&1)
    _ENC_APASS=$(python -c "import urllib; print urllib.quote('''${_ESC_APASS}''')")
    _LEN_APASS=$(echo ${#_ESC_APASS} 2>&1)
  fi

  if [ -z "${_ESC_APASS}" ] || [ "${_LEN_APASS}" -lt "9" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_APASS=$(pwgen -v -s -1 2>&1)
      _ESC_APASS=$(echo -n "${_ESC_APASS}" | tr -d "\n" 2>&1)
      _ESC_APASS=$(sanitize_string "${_ESC_APASS}" 2>&1)
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_APASS=$(cat /root/.my.pass.txt 2>&1)
      else
        _ESC_APASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _ENC_APASS="${_ESC_APASS}"
  fi

  echo "${_ESC_APASS}" > ${_L_SYS}
  chown aegir:aegir ${_L_SYS} &> /dev/null
  chmod 0600 ${_L_SYS}

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _THIS_DB_HOST=$(uname -n 2>&1)
      _SQL_CONNECT=localhost
    elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    else
      _THIS_DB_HOST=localhost
      _SQL_CONNECT=localhost
    fi
    _AEGIR_HOST=$(uname -n 2>&1)
  else
    _AEGIR_HOST=$(uname -n 2>&1)
    ### _SQL_CONNECT="${_THIS_DB_HOST}"
    ### Master Instance will use local DB server
    _SQL_CONNECT=localhost
  fi

  if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
    _AEGIR_HOST=$(uname -n 2>&1)
    _SQL_CONNECT=localhost
  fi

  _RESOLVEIP=$(echo $(getent ahostsv4 ${_AEGIR_HOST}) \
    | cut -d: -f2 \
    | awk '{ print $1}' 2>&1)

  if [ -z "${_RESOLVEIP}" ]; then
    msg "FATAL ERROR:: DNS looks broken for server ${_AEGIR_HOST}"
    msg "FATAL ERROR:: Aborting Barracuda installer NOW!"
    touch /opt/tmp/status-Barracuda-FAIL
    clean_pid_exit
  fi

  _ESC="*.*"
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  mysqladmin -P${_THIS_DB_PORT} --protocol=tcp flush-privileges

  if [ "${_STATUS}" = "INIT" ]; then
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL7 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
      _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
      mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_APASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot mysql<<EOFMYSQL
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
  else
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL8 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
        _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
        mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_APASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
      fi
      _C_SQL="mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot --database=mysql -e"
      ${_C_SQL} "DROP USER '${_ADBU}'@'${_AEGIR_HOST}';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'${_RESOLVEIP}';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'localhost';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'127.0.0.1';" &> /dev/null
      ${_C_SQL} "DROP USER '${_ADBU}'@'%';" &> /dev/null
      mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot mysql<<EOFMYSQL
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
    fi
  fi

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _EXTRA_GRANTS=NO
  else
    _LOCAL_HOST=$(uname -n 2>&1)
    _LOCAL_IP=$(echo $(getent ahostsv4 ${_LOCAL_HOST}) | cut -d: -f2 | awk '{ print $1}' 2>&1)
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL9 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
      _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
      mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
DELETE FROM mysql_query_rules WHERE username='${_ADBU}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_ADBU}','${_ESC_APASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_ADBU}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot mysql<<EOFMYSQL
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_ADBU}'@'%' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
  fi
  mysqladmin -P${_THIS_DB_PORT} --protocol=tcp flush-privileges
}

#
# Sync provision backend db_passwd.
provision_backend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Syncing provision backend db_passwd..."
  fi
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _ADBU=aegir_root
  _L_SYS="/var/aegir/backups/system/.${_ADBU}.pass.txt"
  mv -f ${_L_SYS} ${_L_SYS}-pre-${_X_VERSION}-${_NOW} &> /dev/null
  provision_backend_dbpass_generate
  if [ ! -z "${_ESC_APASS}" ] && [ ! -z "${_ENC_APASS}" ]; then
    su -s /bin/bash - aegir -c "drush @hostmaster \
      sqlq \"UPDATE hosting_db_server SET db_passwd='${_ESC_APASS}' \
      WHERE db_user='${_ADBU}'\"" &> /dev/null
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    _ESC="*.*"
    _USE_DB_USER="${_ADBU}"
    _USE_AEGIR_HOST="$(uname -n 2>&1)"
    _USE_RESOLVEIP="$(echo $(getent ahostsv4 ${_USE_AEGIR_HOST}) \
      | cut -d: -f2 | awk '{ print $1}' 2>&1)"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL10 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
      _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
      mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_ESC_APASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    _C_SQL="mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot mysql<<EOFMYSQL
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
    sed -i "s/mysql:\/\/${_ADBU}:.*/mysql:\/\/${_ADBU}:${_ENC_APASS}@${_SQL_CONNECT}',/g" \
      /var/aegir/.drush/server_*.alias.drushrc.php &> /dev/null
    wait
  fi
  mysqladmin -P${_THIS_DB_PORT} --protocol=tcp flush-privileges
  su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
  rm -rf /var/aegir/.tmp/cache
  if [ -e "/var/aegir/.drush/server_localhost.alias.drushrc.php" ]; then
    su -s /bin/bash aegir -c "drush @hostmaster hosting-task @server_localhost \
      verify --force" &> /dev/null
  else
    su -s /bin/bash aegir -c "drush @hostmaster hosting-task @server_master \
      verify --force" &> /dev/null
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Running hosting-dispatch (1/3)..."
  fi
  su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch" &> /dev/null
  mrun "sleep 5"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Running hosting-dispatch (2/3)..."
  fi
  su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch" &> /dev/null
  mrun "sleep 5"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Running hosting-dispatch (3/3)..."
  fi
  su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch" &> /dev/null
}

#
# Sync hostmaster frontend db_passwd.
hostmaster_frontend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Syncing hostmaster frontend db_passwd..."
  fi
  if [ -e "/var/aegir/use_proxysql.txt" ]; then
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _THIS_HM_SPTH=$(cat /var/aegir/.drush/hostmaster.alias.drushrc.php \
    | grep "site_path'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
  _THIS_HM_DBUR=$(cat $_THIS_HM_SPTH/drushrc.php \
    | grep "options\['db_user'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1)
  _THIS_HM_DBPD=$(cat $_THIS_HM_SPTH/drushrc.php \
    | grep "options\['db_passwd'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1)
  if [ -e "$_THIS_HM_SPTH" ] \
    && [ ! -z "$_THIS_HM_DBUR" ] \
    && [ ! -z "$_THIS_HM_DBPD" ]; then
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    _ESC="*.*"
    _USE_DB_USER="${_THIS_HM_DBUR}"
    _USE_AEGIR_HOST="$(uname -n 2>&1)"
    _USE_RESOLVEIP="$(echo $(getent ahostsv4 ${_USE_AEGIR_HOST}) \
      | cut -d: -f2 | awk '{ print $1}' 2>&1)"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL11 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
      _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
      mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
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
    _C_SQL="mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot mysql<<EOFMYSQL
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_THIS_HM_DBPD}' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_THIS_HM_DBPD}' WITH GRANT OPTION;
EOFMYSQL
  fi
  mysqladmin -P${_THIS_DB_PORT} --protocol=tcp flush-privileges
}

#
# Download for Drush Make Local build.
master_download_for_local_build() {
  mL="/opt/tmp/make_local"
  if [ ! -e "${mL}/hosting/hosting.info" ] \
    || [ ! -e "${mL}/hosting_custom_settings/hosting_custom_settings.info" ]; then
    rm -rf ${mL}
    mkdir -p ${mL}
    cd ${mL}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Downloading hostmaster modules..."
    fi
    ### Drupal Core
    get_dev_ext "drupal-${_SMALLCORE7}.tar.gz"
    mv -f ${mL}/drupal-${_SMALLCORE7} ${mL}/drupal
    ### Aegir Core
    if [ "${_AEGIR_VERSION}" = "HEAD" ]; then
      ${gCb} feature/3.1.x-profile ${gitHub}/hostmaster.git    &> /dev/null
      ${gCb} feature/3.1.x-hosting ${gitHub}/hosting.git       &> /dev/null
      ${gCb} feature/3.1.x-eldir ${gitHub}/eldir.git           &> /dev/null
    else
      get_dev_ext "hostmaster.tar.gz"
      get_dev_ext "hosting.tar.gz"
      get_dev_ext "eldir.tar.gz"
    fi
    ### Aegir Golden + BOA Settings
    if [ "${_AEGIR_VERSION}" = "HEAD" ]; then
      ${gCb} 7.x-3.x ${gitHub}/aegir_objects.git               &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_civicrm.git             &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_custom_settings.git     &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_deploy.git              &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_git.git                 &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_le.git                  &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_remote_import.git       &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_site_backup_manager.git &> /dev/null
      ${gCb} 7.x-3.x ${gitHub}/hosting_tasks_extra.git         &> /dev/null
      rm -rf */.git
    else
      get_dev_ext "aegir_objects.tar.gz"
      get_dev_ext "hosting_civicrm.tar.gz"
      get_dev_ext "hosting_custom_settings.tar.gz"
      get_dev_ext "hosting_deploy.tar.gz"
      get_dev_ext "hosting_git.tar.gz"
      get_dev_ext "hosting_le.tar.gz"
      get_dev_ext "hosting_remote_import.tar.gz"
      get_dev_ext "hosting_site_backup_manager.tar.gz"
      get_dev_ext "hosting_tasks_extra.tar.gz"
    fi
    ### Aegir Drupal Contrib
    get_dev_stc "admin_menu-7.x-3.0-rc6.tar.gz"
    get_dev_stc "betterlogin-7.x-1.5.tar.gz"
    get_dev_stc "ctools-7.x-1.15.tar.gz"
    get_dev_stc "entity-7.x-1.9.tar.gz"
    get_dev_stc "libraries-7.x-2.5.tar.gz"
    get_dev_stc "module_filter-7.x-2.2.tar.gz"
    get_dev_stc "openidadmin-7.x-1.0.tar.gz"
    get_dev_stc "overlay_paths-7.x-1.3.tar.gz"
    get_dev_stc "r4032login-7.x-1.8.tar.gz"
    get_dev_stc "tfa_basic-7.x-1.1.tar.gz"
    get_dev_stc "tfa-7.x-2.0.tar.gz"
    get_dev_stc "timeago-7.x-2.3.tar.gz"
    get_dev_stc "views_bulk_operations-7.x-3.5.tar.gz"
    get_dev_stc "views-7.x-3.23.tar.gz"
    ### BOA Drupal Contrib
    get_dev_stc "features_extra-7.x-1.0.tar.gz"
    get_dev_stc "features-7.x-2.11.tar.gz"
    get_dev_stc "idna_convert-7.x-1.0.tar.gz"
    get_dev_stc "revision_deletion-7.x-1.3.tar.gz"
    get_dev_stc "strongarm-7.x-2.0.tar.gz"
    get_dev_stc "userprotect-7.x-1.2.tar.gz"
  fi
  find ${mL} -type d -exec chmod 0755 {} \; &> /dev/null
  find ${mL} -type f -exec chmod 0644 {} \; &> /dev/null
  chown -R root:root ${mL}
}

#
# Upgrade Aegir Master Instance.
upgrade_aegir_master() {
  if prompt_yes_no "Do you want to upgrade Aegir Master Instance?" ; then
    true
    msg "INFO: Running Aegir Master Instance upgrade"
    msg "INFO: Running SQL tables check and upgrade, please wait..."
    if [ -x "/usr/bin/mariadb_upgrade" ]; then
      mrun "mariadb_upgrade --force" &> /dev/null
      mrun "mysqlcheck -A --auto-repair" &> /dev/null
      mrun "mariadb_upgrade --force" &> /dev/null
    elif [ -x "/usr/bin/mysql_upgrade" ]; then
      mrun "mysql_upgrade --force" &> /dev/null
      mrun "mysqlcheck -A --auto-repair" &> /dev/null
      mrun "mysql_upgrade --force" &> /dev/null
    fi
    if [ -e "/var/aegir/use_proxysql.txt" ]; then
      _THIS_DB_PORT=6033
    else
      _THIS_DB_PORT=3306
    fi
    rm -f /opt/tmp/testecho*
    usermod -aG users aegir
    _VAR_IF_PRESENT=$(grep "aegir ALL=NOPASSWD" /etc/sudoers 2>&1)
    if [[ ! "${_VAR_IF_PRESENT}" =~ "aegir ALL=NOPASSWD" ]]; then
      echo "aegir ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
    fi
    SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership)
    for SCRIPT in ${SCRIPTS[@]}; do
      _VAR_IF_PRESENT=$(grep "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" /etc/sudoers.d/${SCRIPT} 2>&1)
      if [[ ! "${_VAR_IF_PRESENT}" =~ "aegir ALL=NOPASSWD" ]]; then
        echo "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" >> /etc/sudoers.d/${SCRIPT}
        chmod 0440 /etc/sudoers.d/${SCRIPT}
      fi
    done
    if [ ! -d "/var/aegir/.drush/sys/provision/http" ]; then
      rm -rf /var/aegir/.drush/{sys,xts,usr}
      rm -rf /var/aegir/.drush/{provision,drush_make}
      mkdir -p /var/aegir/.drush/{sys,xts,usr}
      ${gCb} ${_BRANCH_PRN} ${gitHub}/provision.git \
        /var/aegir/.drush/sys/provision &> /dev/null
      sed -i "s/files.aegir.cc/${_USE_MIR}/g" \
        /var/aegir/.drush/sys/provision/aegir.make &> /dev/null
      rm -rf /var/aegir/drush
      cd /var/aegir
      get_dev_ext "drush-${_DRUSH_VERSION}.tar.gz"
      cd /var/aegir/drush/
      rm -rf /var/aegir/drush/vendor
      get_dev_ext "vendor-${_DRUSH_VERSION}.tar.gz"
      find /var/aegir/drush -type d -exec chmod 0755 {} \; &> /dev/null
      find /var/aegir/drush -type f -exec chmod 0644 {} \; &> /dev/null
      chmod 755 /var/aegir/drush/drush
      chmod 755 /var/aegir/drush/drush.complete.sh
      chmod 755 /var/aegir/drush/drush.launcher
      chmod 755 /var/aegir/drush/drush.php
      chmod 755 /var/aegir/drush/unish.sh
      chmod 755 /var/aegir/drush/examples/drush.wrapper
      chmod 755 /var/aegir/drush/examples/git-bisect.example.sh
      chmod 755 /var/aegir/drush/examples/helloworld.script
    fi
    _THIS_HM_ROOT=$(cat /var/aegir/.drush/hostmaster.alias.drushrc.php \
      | grep "root'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    _THIS_HM_SITE=$(cat /var/aegir/.drush/hostmaster.alias.drushrc.php \
      | grep "site_path'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    mkdir -p ${_THIS_HM_ROOT}/sites/all/{modules,themes,libraries}
    chown -R aegir:aegir ${_THIS_HM_ROOT}/sites/all
    _U_HD="/var/aegir/.drush"
    chattr -i ${_U_HD}/php.ini
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

    echo "_AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${vBs}/${filIncB}
    echo "_AEGIR_XTS_VRN=\"${_AEGIR_XTS_VRN}\""         >> ${vBs}/${filIncB}
    echo "_BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${vBs}/${filIncB}
    echo "_BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${vBs}/${filIncB}
    echo "_BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${vBs}/${filIncB}
    echo "_BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${vBs}/${filIncB}
    echo "_DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${vBs}/${filIncB}
    echo "_DOMAIN=\"${_THIS_FRONT}\""                   >> ${vBs}/${filIncB}
    echo "_DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${vBs}/${filIncB}
    echo "_NOW=\"${_NOW}\""                             >> ${vBs}/${filIncB}
    echo "_PHP_CLI_VERSION=\"${_PHP_CLI_VERSION}\""     >> ${vBs}/${filIncB}
    echo "_PHP_FPM_VERSION=\"${_PHP_FPM_VERSION}\""     >> ${vBs}/${filIncB}
    echo "_SMALLCORE7=\"${_SMALLCORE7}\""               >> ${vBs}/${filIncB}
    echo "_STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${vBs}/${filIncB}
    echo "_THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${vBs}/${filIncB}
    echo "_USE_MIR=\"${_USE_MIR}\""                     >> ${vBs}/${filIncB}
    echo "_X_VERSION=\"${_X_VERSION}\""                 >> ${vBs}/${filIncB}

    mysqladmin -P${_THIS_DB_PORT} --protocol=tcp flush-hosts
    _RST=$(syncpass fix aegir 2>&1)
    provision_backend_dbpass_sync
    hostmaster_frontend_dbpass_sync
    master_download_for_local_build

    ###
    AegirUpgrade="${bldPth}/aegir/scripts/AegirUpgrade.sh.txt"
    su -s /bin/bash - aegir -c "/bin/bash ${AegirUpgrade} aegir"
    ###

    if [ -e "/opt/tmp/status-AegirUpgrade-FAIL" ]; then
      msg "FATAL ERROR: AegirUpgrade installer failed"
      msg "FATAL ERROR: Aborting Barracuda installer NOW!"
      touch /opt/tmp/status-Barracuda-FAIL
      clean_pid_exit
    else
      chattr +i ${_U_HD}/php.ini
      hostmaster_frontend_dbpass_sync
    fi
    if [ ! -L "${mtrInc}/global.inc" ] && [ -e "${mtrInc}/global.inc" ]; then
      mv -f ${mtrInc}/global.inc \
        ${mtrInc}/global.inc-pre-${_X_VERSION}-${_NOW} &> /dev/null
    fi
    mkdir -p /data/conf
    cp -af ${locCnf}/global.inc /data/conf/global.inc
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" /data/conf/global.inc &> /dev/null
    if [ -e "${mtrInc}" ] && [ ! -L "${mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sf /data/conf/global.inc ${mtrInc}/global.inc
    fi
    update_redis_password
    force_advanced_nginx_config
    cd /var/aegir
    if [ -d "${mtrNgx}/conf.d" ]; then
      if [ ! -d "${mtrNgx}/pre.d" ]; then
        cd ${mtrNgx}
        cp -a conf.d pre.d
      else
        rm -rf ${mtrNgx}/conf.d
      fi
      if [ -e "${mtrNgx}/pre.d/custom_nginx.conf" ]; then
        rm -f ${mtrNgx}/pre.d/custom_nginx.conf
      fi
    fi
    find /var/aegir/host_master/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/host_master/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R aegir:aegir /var/aegir/.drush &> /dev/null
    find /var/aegir/.drush -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/aegir/.drush -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 0440 /var/aegir/.drush/*.php &> /dev/null
    chmod 0711 /var/aegir/.drush &> /dev/null
    msg "INFO: Aegir Master Instance upgrade completed"
  else
    msg "INFO: Aegir Master Instance not upgraded this time"
  fi
  rm -f /var/aegir/*install.sh.txt
}

#
# Update php-cli in the cron entry.
update_php_cli_cron() {
  rm -f /var/spool/cron/crontabs/aegir
  if [ ! -e "/root/.mstr.clstr.cnf" ] \
    && [ ! -e "/root/.wbhd.clstr.cnf" ] \
    && [ ! -e "/root/.dbhd.clstr.cnf" ]; then
    if [ ! -e "/var/spool/cron/crontabs/aegir" ]; then
      echo -e \
        "SHELL=/bin/sh\nPATH=/opt/php56/bin:/usr/bin\n*/1 * * * * \
        /usr/bin/env php /var/aegir/drush/drush.php '@hostmaster' \
        hosting-dispatch >/dev/null 2>&1" \
        | fmt -su -w 2500 \
        | tee -a /var/spool/cron/crontabs/aegir >/dev/null 2>&1
    fi
  fi
  if [ -e "/var/spool/cron/crontabs/aegir" ]; then
    sed -i "s/hosting-dispatch.*/hosting-dispatch \>\/dev\/null 2\>\&1/g" \
      /var/spool/cron/crontabs/aegir &> /dev/null
    if [ "${_PHP_CLI_VERSION}" = "7.4" ] && [ -x "/opt/php74/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php74\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        /var/spool/cron/crontabs/aegir &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "7.3" ] && [ -x "/opt/php73/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php73\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        /var/spool/cron/crontabs/aegir &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "7.2" ] && [ -x "/opt/php72/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php72\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        /var/spool/cron/crontabs/aegir &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "7.1" ] && [ -x "/opt/php71/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php71\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        /var/spool/cron/crontabs/aegir &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "7.0" ] && [ -x "/opt/php70/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php70\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        /var/spool/cron/crontabs/aegir &> /dev/null
    elif [ "${_PHP_CLI_VERSION}" = "5.6" ] && [ -x "/opt/php56/bin/php" ]; then
      sed -i "s/^PATH=.*/PATH=\/opt\/php56\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
        /var/spool/cron/crontabs/aegir &> /dev/null
    fi
    chown aegir:crontab /var/spool/cron/crontabs/aegir &> /dev/null
    chmod 600 /var/spool/cron/crontabs/aegir
  fi
}

install_upgrade_aegir_master() {
  if [ "${_STATUS}" = "INIT" ]; then

  ###--------------------###
    if [ ! -e "/var/run/mysqld/mysqld.pid" ] \
      || [ ! -e "/var/run/mysqld/mysqld.sock" ]; then
      _DB_SERVER_TEST=$(mysql -V 2>&1)
      if [[ "${_DB_SERVER_TEST}" =~ "MariaDB" ]]; then
        _DB_SERVER=MariaDB
        msg "ALRT! ${_DB_SERVER} server not running properly!"
        msg "EXIT: We can't proceed with installation and will exit now"
        msg "HINT: Please check ${_LOG} for more information,"
        msg "HINT: (re)start ${_DB_SERVER} server and then run installer again"
        msg "Bye"
      else
        msg "ALRT! ${_DB_SERVER} server not installed properly!"
        msg "EXIT: We can't proceed and will exit now"
        msg "Bye"
      fi
      rm -f /root/.my.pass.txt
      mkdir -p /var/aegir
      clean_pid_exit
    fi

  ###--------------------###
    msg "INFO: Installing Aegir Master Instance, please wait..."
    if [ -e "/root/.mstr.clstr.cnf" ] \
      || [ -e "/root/.wbhd.clstr.cnf" ] \
      || [ -e "/root/.dbhd.clstr.cnf" ]; then
      touch /data/conf/clstr.cnf &> /dev/null
    fi
    adduser --system --group --home /var/aegir aegir &> /dev/null
    usermod -aG www-data aegir
    usermod -aG users aegir
    echo "aegir ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
    ln -sf /var/aegir/config/nginx.conf /etc/nginx/conf.d/aegir.conf &> /dev/null
    update_nginx_conf

    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _THIS_DB_HOST=$(uname -n 2>&1)
        _SQL_CONNECT=localhost
      elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
        _SQL_CONNECT=127.0.0.1
      else
        _THIS_DB_HOST=localhost
        _SQL_CONNECT=localhost
      fi
      _AEGIR_HOST=$(uname -n 2>&1)
    else
      _AEGIR_HOST=$(uname -n 2>&1)
      ### _SQL_CONNECT="${_THIS_DB_HOST}"
      ### Master Instance will use local DB server
      _SQL_CONNECT=localhost
    fi
    if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
      _AEGIR_HOST=$(uname -n 2>&1)
      _SQL_CONNECT=localhost
    fi

    _RESOLVEIP=$(echo $(getent ahostsv4 ${_AEGIR_HOST}) \
      | cut -d: -f2 \
      | awk '{ print $1}' 2>&1)
    if [ -z "${_RESOLVEIP}" ]; then
      msg "FATAL ERROR: DNS looks broken for server ${_AEGIR_HOST}"
      clean_pid_exit
    else
      _AEGIR_HOST_IP="${_RESOLVEIP}"
    fi

    if [ "${_VMFAMILY}" != "AWS" ]; then
      _MYSQLTEST=$(mysql --silent -h${_AEGIR_HOST_IP} -uINVALIDLOGIN -pINVALIDPASS 2>&1 >/dev/null | cat)
      if [ -z `echo $_MYSQLTEST | grep -q "ERROR \(2003\|1130\)"` ]; then
        msg "INFO: ${_DB_SERVER} is listening on ${_AEGIR_HOST_IP}."
      else
        msg "FATAL ERROR: ${_DB_SERVER} is not configured to listen on ${_AEGIR_HOST_IP}"
        clean_pid_exit
      fi
    fi

    _AEGIR_DB_USER=aegir_root
    _ESC_APASS=""
    _LEN_APASS=0

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
      if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt "128" ]; then
        _PWD_CHARS=128
      fi
    fi

    if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt "8" ]; then
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
          _ESC_APASS="$(openssl rand -base64 32 2>&1)"
        else
          _ESC_APASS=$(randpass "${_PWD_CHARS}" esc 2>&1)
        fi
      else
        if [ -e "/root/.my.pass.txt" ]; then
          _ESC_APASS=$(cat /root/.my.pass.txt 2>&1)
        else
          _ESC_APASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
        fi
      fi
      _ESC_APASS=$(echo -n "${_ESC_APASS}" | tr -d "\n" 2>&1)
      _LEN_APASS=$(echo ${#_ESC_APASS} 2>&1)
    fi

    if [ -z "${_ESC_APASS}" ] || [ "${_LEN_APASS}" -lt "9" ]; then
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _ESC_APASS=$(pwgen -v -s -1 2>&1)
        _ESC_APASS=$(echo -n "${_ESC_APASS}" | tr -d "\n" 2>&1)
        _ESC_APASS=$(sanitize_string "${_ESC_APASS}" 2>&1)
      else
        if [ -e "/root/.my.pass.txt" ]; then
          _ESC_APASS=$(cat /root/.my.pass.txt 2>&1)
        else
          _ESC_APASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
        fi
      fi
    fi

    _ESC="*.*"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL12 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
      _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
      mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_AEGIR_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_AEGIR_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_AEGIR_DB_USER}','${_ESC_APASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot mysql<<EOFMYSQL
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'%' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL

    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _EXTRA_GRANTS=NO
    else
      _LOCAL_HOST=$(uname -n 2>&1)
      _LOCAL_IP=$(echo $(getent ahostsv4 ${_LOCAL_HOST}) | cut -d: -f2 | awk '{ print $1}' 2>&1)
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL13 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
        _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
        mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_AEGIR_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_AEGIR_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_AEGIR_DB_USER}','${_ESC_APASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_AEGIR_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
      fi
      mysql --silent -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot mysql<<EOFMYSQL
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_AEGIR_DB_USER}'@'%' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
    fi

    echo "_AEGIR_DB_USER=\"${_AEGIR_DB_USER}\""         >> ${vBs}/${filIncB}
    echo "_AEGIR_HOST=\"${_AEGIR_HOST}\""               >> ${vBs}/${filIncB}
    echo "_AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${vBs}/${filIncB}
    echo "_AEGIR_XTS_VRN=\"${_AEGIR_XTS_VRN}\""         >> ${vBs}/${filIncB}
    echo "_BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${vBs}/${filIncB}
    echo "_BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${vBs}/${filIncB}
    echo "_BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${vBs}/${filIncB}
    echo "_BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${vBs}/${filIncB}
    echo "_DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${vBs}/${filIncB}
    echo "_DOMAIN=\"${_THIS_FRONT}\""                   >> ${vBs}/${filIncB}
    echo "_DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${vBs}/${filIncB}
    echo "_ESC_APASS=\"${_ESC_APASS}\""                 >> ${vBs}/${filIncB}
    echo "_LOCAL_NETWORK_IP=\"${_LOCAL_NETWORK_IP}\""   >> ${vBs}/${filIncB}
    echo "_MY_OWNIP=\"${_MY_OWNIP}\""                   >> ${vBs}/${filIncB}
    echo "_NOW=\"${_NOW}\""                             >> ${vBs}/${filIncB}
    echo "_PHP_CLI_VERSION=\"${_PHP_CLI_VERSION}\""     >> ${vBs}/${filIncB}
    echo "_PHP_FPM_VERSION=\"${_PHP_FPM_VERSION}\""     >> ${vBs}/${filIncB}
    echo "_STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${vBs}/${filIncB}
    echo "_THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${vBs}/${filIncB}
    echo "_USE_MIR=\"${_USE_MIR}\""                     >> ${vBs}/${filIncB}

    master_download_for_local_build

    ###
    AegirSetupM="${bldPth}/aegir/scripts/AegirSetupM.sh.txt"
    ###

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      su -s /bin/bash - aegir -c "/bin/bash ${AegirSetupM} ${_THIS_FRONT} \
        --http_service_type='nginx' \
        --aegir_db_host='${_THIS_DB_HOST}' \
        --client_email='${_MY_EMAIL}' -y -d"
    else
      su -s /bin/bash - aegir -c "/bin/bash ${AegirSetupM} ${_THIS_FRONT} \
        --http_service_type='nginx' \
        --aegir_db_host='${_THIS_DB_HOST}' \
        --client_email='${_MY_EMAIL}' -y >/var/aegir/install.log 2>&1"
    fi
    if [ -e "/opt/tmp/status-AegirSetupM-FAIL" ]; then
      msg "FATAL ERROR: AegirSetupM installer failed"
      msg "FATAL ERROR: Aborting Barracuda installer NOW!"
      msg "HINT: Please check /var/aegir/install.log"
      msg "HINT: for more information on errors occured"
      touch /opt/tmp/status-Barracuda-FAIL
      clean_pid_exit
    fi
    if [ -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ]; then
      _THIS_HM_ROOT=$(cat /var/aegir/.drush/hostmaster.alias.drushrc.php \
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
    chattr +i ${_U_HD}/php.ini
    su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
    rm -rf /var/aegir/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Running hosting-dispatch (1/3)..."
    fi
    su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch" &> /dev/null
    mrun "sleep 5"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Running hosting-dispatch (2/3)..."
    fi
    su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch" &> /dev/null
    mrun "sleep 5"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Running hosting-dispatch (3/3)..."
    fi
    su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch" &> /dev/null
    if [ -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ]; then
      _THIS_HM_ROOT=$(cat /var/aegir/.drush/hostmaster.alias.drushrc.php \
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
    if [ -e "${mtrInc}/nginx_vhost_common.conf" ]; then
      _DO_NOTHING=YES
      rm -f /root/.force.reinstall.cnf
    else
      msg "FATAL ERROR: Something went wrong, Aegir Master Instance not installed!"
      msg "HINT: Please check /var/aegir/install.log for details, and then"
      msg "HINT: run the same install command again to complete installation."
      touch /root/.force.reinstall.cnf
      clean_pid_exit
    fi

  ###--------------------###
    if [ ! -L "${mtrInc}/global.inc" ] && [ -e "${mtrInc}/global.inc" ]; then
      mv -f ${mtrInc}/global.inc \
        ${mtrInc}/global.inc-pre-${_X_VERSION}-${_NOW} &> /dev/null
    fi
    mkdir -p /data/conf
    cp -af ${locCnf}/global.inc /data/conf/global.inc
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" /data/conf/global.inc &> /dev/null
    if [ -e "${mtrInc}" ] \
      && [ ! -L "${mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sf /data/conf/global.inc ${mtrInc}/global.inc
    fi
    update_redis_password
    force_advanced_nginx_config
    chmod 0711 ${mtrInc} &> /dev/null
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
    if [ -e "${locCnf}/nginx.conf" ]; then
      mv -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf-old &> /dev/null
      cp -af ${locCnf}/nginx.conf /etc/nginx/nginx.conf
    fi
    mrun "service nginx reload" &> /dev/null
    msg "INFO: Aegir Master Instance installed"
  else
    echo " "
    if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
      && [ "${_LOC_OSV}" = "jessie" ]; then
      msg "INFO: Aegir Master Instance upgrade skipped!"
      echo " "
      msg "NOTE! You must reboot the server and run barracuda upgrade"
      msg "NOTE! again to complete all system upgrades and upgrade also"
      msg "NOTE! Aegir Master Instance."
      echo " "
    elif [ "${_SYSTEM_UPGRADE_ONLY}" = "YES" ]; then
      msg "INFO: Aegir Master Instance upgrade skipped"
    else
      if [ ! -e "/var/run/mysqld/mysqld.pid" ] \
        || [ ! -e "/var/run/mysqld/mysqld.sock" ]; then
        _DB_SERVER_TEST=$(mysql -V 2>&1)
        if [[ "${_DB_SERVER_TEST}" =~ "MariaDB" ]]; then
          _DB_SERVER=MariaDB
          msg "ALRT! ${_DB_SERVER} server not running properly!"
          msg "EXIT: We can't proceed with upgrade and will exit now"
          msg "HINT: Please check ${_LOG} for more information,"
          msg "HINT: (re)start ${_DB_SERVER} server and then run installer again"
          msg "Bye"
        else
          msg "ALRT! ${_DB_SERVER} server not installed properly!"
          msg "EXIT: We can't proceed and will exit now"
          msg "Bye"
        fi
        clean_pid_exit
      fi
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        touch /data/conf/clstr.cnf &> /dev/null
      fi
      update_php_cli_cron
      upgrade_aegir_master
      update_php_cli_cron
    fi
  fi
}

if_upgrade_only_aegir_master() {
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ "${_AEGIR_UPGRADE_ONLY}" = "YES" ] \
      && [ "${_SYSTEM_UPGRADE_ONLY}" = "NO" ]; then
      update_php_cli_cron
      upgrade_aegir_master
      update_php_cli_cron
      mrun "sleep 8"
      mrun "service nginx reload" &> /dev/null
      finale
      exit 0
    fi
  fi
}

if_display_login_link() {
  if [ "${_STATUS}" = "INIT" ]; then
    if [ "${_EASY_SETUP}" != "LOCAL" ]; then
      mrun "bash /usr/sbin/apticron" &> /dev/null
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      _AEGIR_LOGIN_URL=$(tail --lines=11 /var/aegir/install.log | grep --text "^http:" 2>&1)
      if [ ! -z "${_AEGIR_LOGIN_URL}" ]; then
        echo " "
        msg "INFO: Congratulations, Aegir have been installed successfully!"
        msg "NOTE! Please wait 2 min before visiting Aegir at:"
        echo " "
        msg "LINK: ${_AEGIR_LOGIN_URL}"
      else
        msg "ALRT! Something went wrong"
        msg "ALRT! Please check the install log for details:"
        msg "ALRT! /var/aegir/install.log"
      fi
    fi
  fi
  if [ ! -e "${pthLog}/cron_aegir_off.pid" ]; then
    touch ${pthLog}/cron_aegir_off.pid
  fi
}

#
# Update local INI for PHP CLI on the Aegir Master Instance.
update_php_cli_local_ini() {
  _X_SE="401prodQ86"
  _U_HD="/var/aegir/.drush"
  _U_TP="/var/aegir/.tmp"
  _U_II="${_U_HD}/php.ini"
  _PHP_CLI_UPDATE=NO
  _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_DRUSH_FILE} 2>&1)
  _PHP_V="72 73 74 56 71 70"
  for e in ${_PHP_V}; do
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
      && [ ! -e "${_U_HD}/.ctrl.php${e}.${_X_SE}.pid" ]; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  if [ "$_PHP_CLI_UPDATE" = "YES" ] \
    || [ ! -e "${_U_II}" ] \
    || [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_X_SE}.pid" ]; then
    mkdir -p ${_U_TP}
    touch ${_U_TP}
    find ${_U_TP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
    chmod 02755 ${_U_TP}
    mkdir -p ${_U_HD}
    rm -f ${_U_HD}/.ctrl.php*
    rm -f ${_U_II}
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php74" ]]; then
      cp -af /opt/php74/lib/php.ini ${_U_II}
      _U_INI=74
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php73" ]]; then
      cp -af /opt/php73/lib/php.ini ${_U_II}
      _U_INI=73
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php72" ]]; then
      cp -af /opt/php72/lib/php.ini ${_U_II}
      _U_INI=72
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php71" ]]; then
      cp -af /opt/php71/lib/php.ini ${_U_II}
      _U_INI=71
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php70" ]]; then
      cp -af /opt/php70/lib/php.ini ${_U_II}
      _U_INI=70
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php56" ]]; then
      cp -af /opt/php56/lib/php.ini ${_U_II}
      _U_INI=56
    fi
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
      echo > ${_U_HD}/.ctrl.php${_U_INI}.${_X_SE}.pid
      echo > ${_U_HD}/.ctrl.${_X_SE}.pid
    fi
  fi
}
