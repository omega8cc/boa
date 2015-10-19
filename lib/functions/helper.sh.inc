
###
### Noticeable messages
###
msg() {
  echo "BOA [$(date +%T 2>&1)] ==> $*"
}

###
### Simple prompt
###
prompt_yes_no() {
if [ "${_AUTOPILOT}" = "YES" ]; then
  return 0
else
  while true; do
    printf "$* [Y/n] "
    read answer
    if [ -z "${answer}" ]; then
      return 0
    fi
    case ${answer} in
      [Yy]|[Yy][Ee][Ss])
        return 0
        ;;
      [Nn]|[Nn][Oo])
        return 1
        ;;
      *)
        echo "Please answer yes or no"
        ;;
    esac
  done
fi
}

#
# Prompt to confirm choice.
prompt_confirm_choice() {
  read -p "$1 [$2]:" _CONFIRMED_ANSWER
  if [ -z "${_CONFIRMED_ANSWER}" ]; then
    _CONFIRMED_ANSWER=$2
  fi
}

#
# Not supported OS.
not_supported_os() {
  msg "== FATAL ERROR =="
  msg "Invalid install script or OS used"
  msg "It is not any supported Debian or Ubuntu version"
  msg "You need Debian - Squeeze (recommended) or Wheezy"
  msg "or Ubuntu - Precise or Lucid"
  clean_pid_exit
}

###
### Small spinner
###
mrun() {
  CMD="$1"
  touch busy
  if [ "${_SPINNER}" = "YES" ]; then
    bash ${_SRCDIR}/spinner busy &
  fi
  if ${CMD} >> ${_LOG}; then
    rm busy
    sleep 1
    return 0
  fi
}

#
# Silent runner.
st_runner() {
  CMD="$1"
  touch busy
  if [ "${_SPINNER}" = "YES" ]; then
    bash ${_SRCDIR}/spinner busy &
  fi
  if ${CMD} >> ${_LOG}; then
    rm busy
    sleep 1
    return 0
  else
    rm busy
    sleep 1
    echo "${CMD} failed.  Error (if any): $?"
    echo " "
    echo "Displaying the last 15 lines of logfile"
    echo "  ${_LOG}"
    echo "to help troubleshoot this problem"
    echo " "
    echo "If you see any error with advice to run 'dpkg --configure -a', run this"
    echo "command first and choose default answer, then run this installer again"
    echo " "
    tail -15 ${_LOG}
    return 1
  fi
}

#
# Remove dangerous stuff from the string.
sanitize_string() {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\$\@\&\|\*]//g; s/\(['"'"'\]\)//g'
}

#
# Extract archive.
extract_archive() {
  if [ ! -z "$1" ]; then
    case $1 in
      *.tar.bz2)   tar xjf $1    ;;
      *.tar.gz)    tar xzf $1    ;;
      *.bz2)       bunzip2 $1    ;;
      *.rar)       unrar x $1    ;;
      *.gz)        gunzip -q $1  ;;
      *.tar)       tar xf $1     ;;
      *.tbz2)      tar xjf $1    ;;
      *.tgz)       tar xzf $1    ;;
      *.zip)       unzip -qq $1  ;;
      *.Z)         uncompress $1 ;;
      *.7z)        7z x $1       ;;
      *)           echo "'$1' cannot be extracted via >extract<" ;;
    esac
    rm -f $1
  fi
}

#
# Download and extract archive from dev mirror.
get_dev_arch() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/$1" -o "$1"
    extract_archive "$1"
  fi
}

#
# Download and extract from dev/version mirror.
get_dev_ext() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/$1" -o "$1"
    extract_archive "$1"
  fi
}

#
# Download and extract from dev/static.
get_dev_stc() {
  if [ ! -z "$1" ]; then
    if [ "$1" = "hosting.tar.gz" ]; then
      curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/$1" -o "$1"
    else
      curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/static/$1" -o "$1"
    fi
    extract_archive "$1"
  fi
}

#
# Download and extract from dev/contrib mirror.
get_dev_contrib() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/contrib/$1" -o "$1"
    extract_archive "$1"
  fi
}

#
# Download and extract archive from dev/src mirror.
get_dev_src() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/src/$1" -o "$1"
    extract_archive "$1"
  fi
}

normalize_ip_name_variables() {
  if [ ! -z "${_LOCAL_NETWORK_IP}" ]; then
    _LOCAL_NETWORK_IP=${_LOCAL_NETWORK_IP//[^0-9.]/}
  fi
  if [ ! -z "${_LOCAL_NETWORK_HN}" ]; then
    _LOCAL_NETWORK_HN=${_LOCAL_NETWORK_HN//[^a-zA-Z0-9-.]/}
    _LOCAL_NETWORK_HN=$(echo -n ${_LOCAL_NETWORK_HN} | tr A-Z a-z 2>&1)
  fi
  if [ ! -z "${_MY_OWNIP}" ]; then
    _MY_OWNIP=${_MY_OWNIP//[^0-9.]/}
  fi
  if [ ! -z "${_MY_HOSTN}" ]; then
    _MY_HOSTN=${_MY_HOSTN//[^a-zA-Z0-9-.]/}
    _MY_HOSTN=$(echo -n ${_MY_HOSTN} | tr A-Z a-z 2>&1)
  fi
  if [ ! -z "${_MY_FRONT}" ]; then
    _MY_FRONT=${_MY_FRONT//[^a-zA-Z0-9-.]/}
    _MY_FRONT=$(echo -n ${_MY_FRONT} | tr A-Z a-z 2>&1)
  fi
  if [ ! -z "${_SMTP_RELAY_HOST}" ]; then
    _SMTP_RELAY_HOST=${_SMTP_RELAY_HOST//[^a-zA-Z0-9-.]/}
    _SMTP_RELAY_HOST=$(echo -n ${_SMTP_RELAY_HOST} | tr A-Z a-z 2>&1)
  fi
}

mode_detection() {
  if [ -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ]; then
    _STATUS=UPGRADE
    msg "INFO: UPGRADE"
    barracuda_cnf
    touch /var/run/boa_wait.pid
  else
    _STATUS=INIT
    if [ -d "/var/aegir" ]; then
      msg "INFO: FORCED INIT"
      _FULL_FORCE_REINSTALL=YES
    else
      msg "INFO: NORMAL INIT"
    fi
    _ZOMBIE_HOME="${vBs}/zombie/${_X_VERSION}-${_NOW}"
    mkdir -p $_ZOMBIE_HOME
    mv -f /etc/nginx/conf.d/* $_ZOMBIE_HOME/ &> /dev/null
    mv -f /var/aegir $_ZOMBIE_HOME/ &> /dev/null
    mv -f /var/xdrago $_ZOMBIE_HOME/ &> /dev/null
    mv -f /root/.my.cnf $_ZOMBIE_HOME/ &> /dev/null
    mv -f /root/.my.pass.txt $_ZOMBIE_HOME/ &> /dev/null
    cp -af /etc/sudoers $_ZOMBIE_HOME/ &> /dev/null
    sed -i "s/^aegir.*//g" /etc/sudoers &> /dev/null
    deluser aegir &> /dev/null
    rm -f /usr/bin/drush
    if [ ! -z "${_EASY_SETUP}" ] && [[ ! "${_EASY_SETUP}" =~ "NO" ]]; then
      if [ "${_EASY_SETUP}" != "LOCAL" ]; then
        if [ -z "${_EASY_HOSTNAME}" ] \
          || [ "${_EASY_HOSTNAME}" = "wildcard-enabled-hostname" ]; then
          msg "FATAL ERROR: You must define also _EASY_HOSTNAME"
          clean_pid_exit
        fi
      fi
    fi
    if [ "${_EASY_SETUP}" = "LOCAL" ]; then
      msg "INFO: Localhost Setup Mode Active"
      _XTRAS_LIST="CHV"
      _AUTOPILOT=YES
      _DEBUG_MODE=NO
      _DB_SERVER=MariaDB
      _SSH_PORT=22
      _DNS_SETUP_TEST=NO
      _SMTP_RELAY_TEST=NO
      _LOCAL_NETWORK_IP="127.0.1.1"
      _LOCAL_NETWORK_HN="aegir.local"
    elif [ "${_EASY_SETUP}" = "PUBLIC" ]; then
      msg "INFO: Public Setup Mode Active"
      _XTRAS_LIST="CSF CHV FTP"
      _AUTOPILOT=YES
      _DEBUG_MODE=NO
      _DB_SERVER=MariaDB
      _SSH_PORT=22
      _DNS_SETUP_TEST=YES
      _SMTP_RELAY_TEST=YES
      _MY_HOSTN="${_EASY_HOSTNAME}"
      _MY_FRONT="master.${_EASY_HOSTNAME}"
      validate_public_ip &> /dev/null
      _MY_OWNIP="${_THISHTIP}"
    elif [ "${_EASY_SETUP}" = "MSTR" ]; then
      msg "INFO: Cluster Master Mode Active"
      _XTRAS_LIST=""
      _AUTOPILOT=YES
      _DEBUG_MODE=NO
      _DB_SERVER=MariaDB
      _DB_SERIES=10.0
      _SSH_PORT=22
      _DNS_SETUP_TEST=NO
      _SMTP_RELAY_TEST=NO
      _MY_HOSTN="${_EASY_HOSTNAME}"
      _MY_FRONT="master.${_EASY_HOSTNAME}"
      validate_public_ip &> /dev/null
      _MY_OWNIP="${_THISHTIP}"
      if [ ! -e "/root/.mstr.clstr.cnf" ]; then
        touch /root/.mstr.clstr.cnf
      fi
    elif [ "${_EASY_SETUP}" = "WBHD" ]; then
      msg "INFO: Cluster WEB Head Mode Active"
      _XTRAS_LIST=""
      _AUTOPILOT=YES
      _DEBUG_MODE=NO
      _DB_SERVER=MariaDB
      _DB_SERIES=10.0
      _SSH_PORT=22
      _DNS_SETUP_TEST=NO
      _SMTP_RELAY_TEST=NO
      _MY_HOSTN="${_EASY_HOSTNAME}"
      _MY_FRONT="master.${_EASY_HOSTNAME}"
      validate_public_ip &> /dev/null
      _MY_OWNIP="${_THISHTIP}"
      if [ ! -e "/root/.wbhd.clstr.cnf" ]; then
        touch /root/.wbhd.clstr.cnf
      fi
    elif [ "${_EASY_SETUP}" = "DBHD" ]; then
      msg "INFO: Cluster DB Head Mode Active"
      _XTRAS_LIST=""
      _AUTOPILOT=YES
      _DEBUG_MODE=NO
      _DB_SERVER=MariaDB
      _DB_SERIES=10.0
      _SSH_PORT=22
      _DNS_SETUP_TEST=NO
      _SMTP_RELAY_TEST=NO
      _MY_HOSTN="${_EASY_HOSTNAME}"
      _MY_FRONT="master.${_EASY_HOSTNAME}"
      validate_public_ip &> /dev/null
      _MY_OWNIP="${_THISHTIP}"
      if [ ! -e "/root/.dbhd.clstr.cnf" ]; then
        touch /root/.dbhd.clstr.cnf
      fi
    fi
    barracuda_cnf
  fi
  if [ "${_AEGIR_VERSION}" = "HEAD" ] && [ ! -z "${_FORCE_GIT_MIRROR}" ]; then
    if [ "${_FORCE_GIT_MIRROR}" = "gitlab" ]; then
      _INSTAPP="/usr/bin/aptitude-fast -f -y -q \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold install"
    else
      _INSTAPP="/usr/bin/aptitude -f -y -q \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold install"
    fi
  else
    _INSTAPP="/usr/bin/aptitude -f -y -q \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold install"
  fi
  _SRCDIR="/opt/tmp/files"
  rm -f -r /var/opt/*
  mkdir -p ${_SRCDIR}
  chmod -R 777 /opt/tmp &> /dev/null
  find /opt/tmp/boa -type d -exec chmod 0755 {} \; &> /dev/null
  find /opt/tmp/boa -type f -exec chmod 0644 {} \; &> /dev/null
  rm -f /var/run/aegir_upgrade.pid
  if [ "${_STRICT_BIN_PERMISSIONS}" = "YES" ]; then
    if [ -x "/bin/dash" ]; then
      symlink_to_dash
      switch_to_dash
    else
      symlink_to_bash
      switch_to_bash
    fi
  fi
  _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
  if [ -z "${_PHP_SV}" ] || [ "${_PHP_SV}" = "52" ]; then
    _PHP_SV=55
  fi
  _PHP_CN="www${_PHP_SV}"
}

check_exception_mycnf() {
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ ! -e "/root/.my.cnf" ]; then
    msg "EXIT on error due to not found file with your ${_DB_SERVER} root password"
    cat <<EOF

    It appears you don't have required file with your root sql password.
    Create this file first and run this script again:

    echo "[client]" > /root/.my.cnf
    echo "user=root" >> /root/.my.cnf
    echo "password=your_SQL_ROOT_password" >> /root/.my.cnf
    chmod 0600 /root/.my.cnf

EOF
    msg "EXIT on error due to not found file with your ${_DB_SERVER} root password"
    clean_pid_exit
    fi
  fi
}

os_detection() {
  _THIS_OS=$(lsb_release -si 2>&1)
  _THIS_RV=$(lsb_release -sc 2>&1)
  if [ "${_THIS_OS}" = "Ubuntu" ]; then
    if [ "${_THIS_RV}" = "trusty" ]; then
      _OSV="trusty"
      _DB_SERIES=10.0
      _NGINX_FORWARD_SECRECY=YES
      _NGINX_SPDY=YES
      _SSH_FROM_SOURCES=NO
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _MARIADB_VRN="${_GALERA_10_VRN}"
      else
        _MARIADB_VRN="${_MARIADB_10_VRN}"
      fi
    elif [ "${_THIS_RV}" = "precise" ]; then
      _OSV="precise"
      _NGINX_FORWARD_SECRECY=YES
      _NGINX_SPDY=YES
      _SSH_FROM_SOURCES=NO
    elif [ "${_THIS_RV}" = "lucid" ]; then
      _OSV="lucid"
      _NGINX_FORWARD_SECRECY=NO
      _NGINX_SPDY=NO
      _SSH_FROM_SOURCES=NO
      _SSL_FROM_SOURCES=NO
    else
      not_supported_os
    fi
  elif [ "${_THIS_OS}" = "Debian" ]; then
    if [ "${_THIS_RV}" = "wheezy" ]; then
      _OSV="wheezy"
      _NGINX_FORWARD_SECRECY=YES
      _NGINX_SPDY=YES
      _SSH_FROM_SOURCES=YES
      _SSL_FROM_SOURCES=YES
    elif [ "${_THIS_RV}" = "squeeze" ]; then
      _OSV="squeeze"
      _NGINX_VRN=1.9.4
      _OPENSSL_VRN=1.0.1p
      _NGINX_FORWARD_SECRECY=YES
      _NGINX_SPDY=YES
      _SSH_FROM_SOURCES=YES
      _SSL_FROM_SOURCES=YES
    else
      not_supported_os
    fi
  else
    not_supported_os
  fi
  echo " "
  thiSys="$(lsb_release -si 2>&1)/$(lsb_release -sc 2>&1) $(uname -m 2>&1)"
  thiSys="$(uname -n 2>&1) ${thiSys} PHP ${_PHP_FPM_VERSION}"
  msg "Aegir on ${thiSys}"
  echo " "
}

check_boa_version() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Checking BARRACUDA version..."
  fi
  if [ "${_AEGIR_VERSION}" = "HEAD" ]; then
    _FILE_VERSION=barracuda-release.txt
  else
    _FILE_VERSION=barracuda-version.txt
  fi
  if [ -e "${locCnf}/${_FILE_VERSION}" ]; then
    _VERSIONS_TEST=$(cat ${locCnf}/${_FILE_VERSION} 2>&1)
    if [[ "${_VERSIONS_TEST}" =~ "-dev" ]]; then
      if [[ "${_VERSIONS_TEST}" =~ "${_X_VERSION}" ]] \
        && [ "${_AEGIR_VERSION}" = "HEAD" ]; then
        _VERSIONS_TEST_RESULT=OK
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: BARRACUDA version test: OK"
        fi
      else
        _VERSIONS_TEST_RESULT=FAIL
      fi
    else
      if [[ "${_VERSIONS_TEST}" =~ "${_X_VERSION}" ]] \
        && [[ "${_AEGIR_VERSION}" =~ "BOA" ]]; then
        _VERSIONS_TEST_RESULT=OK
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: BARRACUDA version test: OK"
        fi
      else
        _VERSIONS_TEST_RESULT=FAIL
      fi
    fi
    if [ "${_VERSIONS_TEST_RESULT}" = "FAIL" ]; then
      msg "ERROR: This BARRACUDA version is outdated and will not work correctly"
      msg "Bye"
      clean_pid_exit
    fi
  fi
  if [ -e "/var/log/barracuda_log.txt" ]; then
    _SERIES_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
    if [[ "${_SERIES_TEST}" =~ "BOA-2.4." ]]; then
      if [[ ! "${_X_VERSION}" =~ "BOA-2.4." ]]; then
        msg "ERROR: Your system has been already upgraded to modern BOA-2.4.x series"
        msg "ERROR: You can not downgrade back to legacy or previous stable BOA version"
        msg "ERROR: Please use barracuda up-stable to upgrade this system"
        msg "Bye"
        clean_pid_exit
      fi
    fi
  fi
}

check_prepare_dirs_permissions() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Cleaning up temp files in /var/opt/"
  fi
  rm -f -r /var/opt/*
  mkdir -p /var/log/php
  chmod 777 /var/log/php* &> /dev/null
  mkdir -p ${vBs}/dragon/{x,z,t}
  if [ -e "/etc/init.d/buagent" ]; then
    mv -f /etc/init.d/buagent \
      ${vBs}/buagent-pre-${_X_VERSION}-${_NOW} &> /dev/null
  fi
}

check_fix_avatars() {
  if [ ! -e "/var/www/nginx-default/profiles/commons/images/avatars" ]; then
    if [ -e "${bldPth}/aegir/var/commons/images" ]; then
      mkdir -p /var/www/nginx-default/profiles/commons
      cp -af ${bldPth}/aegir/var/commons/images \
        /var/www/nginx-default/profiles/commons/
      chown -R www-data:www-data /var/www/nginx-default/profiles &> /dev/null
      find /var/www/nginx-default/profiles -type d -exec chmod 0755 {} \; &> /dev/null
      find /var/www/nginx-default/profiles -type f -exec chmod 0644 {} \; &> /dev/null
    fi
  fi
}

update_barracuda_log() {
  if [ -L "${mtrInc}/barracuda_log.txt" ]; then
    rm -f ${mtrInc}/barracuda_log.txt
  fi
  if [ "${_THIS_DB_HOST}" = "localhost" ]; then
    _LOG_DB_HOST=localhost
  elif [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _LOG_DB_HOST=FQDN
  else
    _LOG_DB_HOST=REMOTE
  fi
  if [ ! -z "${_FORCE_GIT_MIRROR}" ]; then
    _LOG_GIT_MIRROR="-${_FORCE_GIT_MIRROR}"
  fi
  _LOG_DB_V=$(mysql -V 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f6 \
    | awk '{ print $1}' \
    | cut -d"-" -f1 \
    | awk '{ print $1}' \
    | sed "s/[\,']//g" 2>&1)
  _BARRACUDA_VERSION_INFO="$(date 2>&1) / \
    $(lsb_release -si 2>&1).$(lsb_release -sc 2>&1) \
    $(uname -m 2>&1) ${_VMFAMILY} / \
    Aegir ${_AEGIR_VERSION} / \
    Barracuda ${_X_VERSION}${_LOG_GIT_MIRROR} / \
    Nginx ${_NGINX_VRN} / \
    PHP-MI ${_PHP_MULTI_INSTALL} / \
    PHP-SE ${_PHP_SINGLE_INSTALL} / \
    FPM ${_PHP_FPM_VERSION} / \
    CLI ${_PHP_CLI_VERSION} / \
    ${_DB_SERVER}-${_LOG_DB_V} \
    ${_LOG_DB_HOST}"

  echo "${_BARRACUDA_VERSION_INFO}" | fmt -su -w 2500 >> /var/log/barracuda_log.txt
  echo "${_BARRACUDA_VERSION_INFO}" | fmt -su -w 2500 >> ${vBs}/barracuda_log.txt

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: New entry added to /var/log/barracuda_log.txt"
  fi
}
