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
    if [ ! -z "${_STRONG_PASSWORDS}" ] && [ "${_STRONG_PASSWORDS}" -gt "8" ]; then
      _PWD_CHARS="${_STRONG_PASSWORDS}"
    else
      _PWD_CHARS=8
    fi
    if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt "128" ]; then
      _PWD_CHARS=128
    fi
  fi

  if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt "8" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_APASS=$(randpass "${_PWD_CHARS}" esc 2>&1)
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_APASS=$(cat /root/.my.pass.txt 2>&1)
      else
        _ESC_APASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _ESC_APASS=$(echo -n ${_ESC_APASS} | tr -d "\n" 2>&1)
    _ENC_APASS=$(python -c "import urllib; print urllib.quote('''${_ESC_APASS}''')")
    _LEN_APASS=$(echo ${#_ESC_APASS} 2>&1)
  fi

  if [ -z "${_ESC_APASS}" ] || [ "${_LEN_APASS}" -lt "9" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_APASS=$(pwgen -v -s -1 2>&1)
      _ESC_APASS=$(echo -n ${_ESC_APASS} | tr -d "\n" 2>&1)
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

  if [ "${_THIS_DB_HOST}" = "localhost" ] || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _THIS_DB_HOST=$(uname -n 2>&1)
    else
      _THIS_DB_HOST=localhost
    fi
    _AEGIR_HOST=$(uname -n 2>&1)
    _SQL_CONNECT=localhost
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

  if [ -z "$_RESOLVEIP" ]; then
    msg "FATAL ERROR:: DNS looks broken for server ${_AEGIR_HOST}"
    msg "FATAL ERROR:: Aborting Barracuda installer NOW!"
    touch /opt/tmp/status-Barracuda-FAIL
    clean_pid_exit
  fi

  _ESC="\`%\`.*"
  mysqladmin flush-privileges &> /dev/null

  if [ "${_STATUS}" = "INIT" ]; then
    mysql -h${_SQL_CONNECT} -uroot mysql<<EOFMYSQL
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'${_AEGIR_HOST}' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'$_RESOLVEIP' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
  else
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      mysql -h${_SQL_CONNECT} -uroot mysql<<EOFMYSQL
DROP USER '$_ADBU'@'${_AEGIR_HOST}';
DROP USER '$_ADBU'@'$_RESOLVEIP';
DROP USER '$_ADBU'@'localhost';
EOFMYSQL
      mysql -h${_SQL_CONNECT} -uroot mysql<<EOFMYSQL
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'${_AEGIR_HOST}' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'$_RESOLVEIP' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'localhost' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
    fi
  fi

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _EXTRA_GRANTS=NO
  else
    _LOCAL_HOST=$(uname -n 2>&1)
    _LOCAL_IP=$(echo $(getent ahostsv4 $_LOCAL_HOST) | cut -d: -f2 | awk '{ print $1}' 2>&1)
    mysql -h${_SQL_CONNECT} -uroot mysql<<EOFMYSQL
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'${_THIS_DB_HOST}' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'$_LOCAL_HOST' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON $_ESC TO '$_ADBU'@'$_LOCAL_IP' IDENTIFIED BY '${_ESC_APASS}' WITH GRANT OPTION;
EOFMYSQL
  fi
  mysqladmin flush-privileges &> /dev/null
}

#
# Sync provision backend db_passwd.
provision_backend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Syncing provision backend db_passwd..."
  fi
  _ADBU=aegir_root
  _L_SYS="/var/aegir/backups/system/.$_ADBU.pass.txt"
  mv -f ${_L_SYS} ${_L_SYS}-pre-${_X_VERSION}-${_NOW} &> /dev/null
  provision_backend_dbpass_generate
  if [ ! -z "${_ESC_APASS}" ] && [ ! -z "${_ENC_APASS}" ]; then
    su -s /bin/bash - aegir -c "drush @hostmaster \
      sqlq \"UPDATE hosting_db_server SET db_passwd='${_ESC_APASS}' \
      WHERE db_user='$_ADBU'\" &> /dev/null"
    mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('${_ESC_APASS}') \
      WHERE User='$_ADBU';" &> /dev/null
    sed -i "s/mysql:\/\/$_ADBU:.*/mysql:\/\/$_ADBU:${_ENC_APASS}@${_SQL_CONNECT}',/g" \
      /var/aegir/.drush/server_*.alias.drushrc.php &> /dev/null
  fi
  mysqladmin flush-privileges &> /dev/null
  su -s /bin/bash - aegir -c "drush cache-clear drush &> /dev/null"
  rm -f -r /var/aegir/.tmp/cache
  if [ -e "/var/aegir/.drush/server_localhost.alias.drushrc.php" ]; then
    su -s /bin/bash aegir -c "drush @hostmaster hosting-task @server_localhost \
      verify --force &> /dev/null"
  else
    su -s /bin/bash aegir -c "drush @hostmaster hosting-task @server_master \
      verify --force &> /dev/null"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Running hosting-dispatch (1/3)..."
  fi
  su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch &> /dev/null"
  mrun "sleep 5"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Running hosting-dispatch (2/3)..."
  fi
  su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch &> /dev/null"
  mrun "sleep 5"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Running hosting-dispatch (3/3)..."
  fi
  su -s /bin/bash - aegir -c "drush @hostmaster hosting-dispatch &> /dev/null"
}

#
# Sync hostmaster frontend db_passwd.
hostmaster_frontend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Syncing hostmaster frontend db_passwd..."
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
    mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('$_THIS_HM_DBPD') \
      WHERE User='$_THIS_HM_DBUR';" &> /dev/null
  fi
  mysqladmin flush-privileges &> /dev/null
}

#
# Download for Drush Make Local build.
download_for_dmlb() {
  mL="/opt/tmp/make_local"
  if [ ! -d "${mL}" ]; then
    mkdir -p ${mL}
  fi
  cd ${mL}
  get_dev_stc "hosting.tar.gz"
  get_dev_stc "eldir.tar.gz"
  get_dev_stc "views-6.x-3.0.tar.gz"
  get_dev_stc "views_bulk_operations-6.x-1.16.tar.gz"
  get_dev_stc "admin_menu.tar.gz"
  get_dev_stc "install_profile_api.tar.gz"
  get_dev_stc "jquery_ui.tar.gz"
  get_dev_stc "jquery_update.tar.gz"
  get_dev_stc "modalframe.tar.gz"
  get_dev_stc "openidadmin.tar.gz"
  get_dev_stc "css_emimage.tar.gz"
  get_dev_stc "ctools.tar.gz"
  get_dev_stc "features_extra.tar.gz"
  get_dev_stc "features.tar.gz"
  get_dev_stc "hosting_backup_queue.tar.gz"
  get_dev_stc "hosting_platform_pathauto.tar.gz"
  get_dev_stc "hosting_task_gc.tar.gz"
  get_dev_stc "protect_critical_users.tar.gz"
  get_dev_stc "revision_deletion.tar.gz"
  get_dev_stc "strongarm.tar.gz"
  get_dev_stc "userprotect.tar.gz"
  get_dev_stc "jquery-ui-1.7.3.zip"
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
    rm -f /opt/tmp/testecho*
    if [ ! -e "/root/.upstart.cnf" ]; then
      service cron stop &> /dev/null
    fi
    usermod -aG users aegir &> /dev/null
    if [ ! -d "/var/aegir/.drush/sys/provision/http" ]; then
      rm -f -r /var/aegir/.drush/{sys,xts,usr}
      rm -f -r /var/aegir/.drush/{provision,drush_make}
      mkdir -p /var/aegir/.drush/{sys,xts,usr}
      git clone --branch ${_BRANCH_PRN} ${gitHub}/provision.git \
        /var/aegir/.drush/sys/provision &> /dev/null
      sed -i "s/files.aegir.cc/${_USE_MIR}/g" \
        /var/aegir/.drush/sys/provision/aegir.make &> /dev/null
      rm -f -r /var/aegir/drush
      cd /var/aegir
      get_dev_ext "drush-${_DRUSH_VERSION}.tar.gz"
      cd /var/aegir/drush/
      rm -f -r /var/aegir/drush/vendor
      get_dev_ext "vendor-${_DRUSH_VERSION}.tar.gz"
      find /var/aegir/drush -type d -exec chmod 0755 {} \; &> /dev/null
      find /var/aegir/drush -type f -exec chmod 0644 {} \; &> /dev/null
      chmod 755 /var/aegir/drush/drush
      chmod 755 /var/aegir/drush/drush.php
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
    chattr -i ${_U_HD}/php.ini &> /dev/null
    chown -R aegir:aegir /var/aegir/.drush
    chown -R aegir:aegir /var/aegir/backups
    chown -R aegir:aegir /var/aegir/clients
    chown -R aegir:aegir /var/aegir/config
    chown -R aegir:aegir /var/aegir/drush
    chown -R aegir ${_THIS_HM_ROOT}
    chown -R aegir:www-data $_THIS_HM_SITE/files
    chmod -R 02775 $_THIS_HM_SITE/files
    cd /var/aegir
    cp ${bldPth}/aegir/scripts/AegirUpgrade.sh.txt ./
    pthAue="/var/aegir/AegirUpgrade.sh.txt"
    sed -i "s/EDIT_AEGIR_VERSION/${_AEGIR_VERSION}/g"         ${pthAue}
    sed -i "s/EDIT_AEGIR_XTS_VRN/${_AEGIR_XTS_VRN}/g"         ${pthAue}
    sed -i "s/EDIT_BOA_REPO_GIT_URL/${_BOA_REPO_GIT_URLX}/g"  ${pthAue}
    sed -i "s/EDIT_BOA_REPO_NAME/${_BOA_REPO_NAME}/g"         ${pthAue}
    sed -i "s/EDIT_BRANCH_BOA/${_BRANCH_BOA}/g"               ${pthAue}
    sed -i "s/EDIT_BRANCH_PRN/${_BRANCH_PRN}/g"               ${pthAue}
    sed -i "s/EDIT_DEBUG_MODE/${_DEBUG_MODE}/g"               ${pthAue}
    sed -i "s/EDIT_DOMAIN/${_THIS_FRONT}/g"                   ${pthAue}
    sed -i "s/EDIT_DRUSH_VERSION/${_DRUSH_VERSION}/g"         ${pthAue}
    sed -i "s/EDIT_PHP_CLI_VERSION/${_PHP_CLI_VERSION}/g"     ${pthAue}
    sed -i "s/EDIT_PHP_FPM_VERSION/${_PHP_FPM_VERSION}/g"     ${pthAue}
    sed -i "s/EDIT_STRONG_PASSWORDS/${_STRONG_PASSWORDS}/g"   ${pthAue}
    sed -i "s/EDIT_THIS_DB_HOST/${_THIS_DB_HOST}/g"           ${pthAue}
    sed -i "s/EDIT_USE_MIR/${_USE_MIR}/g"                     ${pthAue}
    sed -i "s/EDIT_X_VERSION/${_X_VERSION}/g"                 ${pthAue}
    mysqladmin flush-hosts &> /dev/null
    provision_backend_dbpass_sync
    hostmaster_frontend_dbpass_sync
    download_for_dmlb
    cd /var/aegir
    su -s /bin/bash - aegir -c "bash AegirUpgrade.sh.txt"
    if [ -e "/opt/tmp/status-AegirUpgrade-FAIL" ]; then
      msg "FATAL ERROR: AegirUpgrade installer failed"
      msg "FATAL ERROR: Aborting Barracuda installer NOW!"
      touch /opt/tmp/status-Barracuda-FAIL
      clean_pid_exit
    else
      chattr +i ${_U_HD}/php.ini &> /dev/null
      hostmaster_frontend_dbpass_sync
      sed -i "s/hosting-dispatch.*/hosting-dispatch \>\/dev\/null 2\>\&1/g" \
        /var/spool/cron/crontabs/aegir &> /dev/null
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
    rm -f AegirUpgrade.sh.txt
    if [ -d "${mtrNgx}/conf.d" ]; then
      if [ ! -d "${mtrNgx}/pre.d" ]; then
        cd ${mtrNgx}
        cp -a conf.d pre.d
      else
        rm -f -r ${mtrNgx}/conf.d
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
  if [ "${_PHP_CLI_VERSION}" = "5.5" ] && [ -x "/opt/php55/bin/php" ]; then
    sed -i "s/^PATH=.*/PATH=\/opt\/php55\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
      /var/spool/cron/crontabs/aegir &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "5.6" ] && [ -x "/opt/php56/bin/php" ]; then
    sed -i "s/^PATH=.*/PATH=\/opt\/php56\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
      /var/spool/cron/crontabs/aegir &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "5.4" ] && [ -x "/opt/php54/bin/php" ]; then
    sed -i "s/^PATH=.*/PATH=\/opt\/php54\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
      /var/spool/cron/crontabs/aegir &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "5.3" ] && [ -x "/opt/php53/bin/php" ]; then
    sed -i "s/^PATH=.*/PATH=\/opt\/php53\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin/g" \
      /var/spool/cron/crontabs/aegir &> /dev/null
  fi
  chown aegir:crontab /var/spool/cron/crontabs/aegir &> /dev/null
}
