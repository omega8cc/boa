
tRee=dev
rlsn="BOA-5.4.0"
rlse="${rlsn}-${tRee}"
export tRee="${tRee}"
export rlsn="${rlsn}"

#
# Check key things in every proc.
debug_proc() {
  if [ -e "/root/.dev.server.cnf" ]; then
    msg "DBLS: `ls -la /usr/bin/sh`"
    msg "DBLS: `ls -la /bin/sh`"
    msg "DBLS: `ls -la /run/octopus_install_run.pid`"
    [ -e "/data/disk/${_USER}/.tmp/cache" ] && msg "DBLS: `ls -la /data/disk/${_USER}/.tmp/cache`"
  fi
}

#
# Count system CPUs.
count_cpu() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: count_cpu"
    debug_proc
  fi
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt "0" ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
}

#
# Find correct IP.
find_correct_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: find_correct_ip"
    debug_proc
  fi
  if [ -e "/root/.found_correct_ipv4.cnf" ]; then
    _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>&1)
    _LOC_IP=$(echo -n ${_LOC_IP} | tr -d "\n" 2>&1)
  else
    _LOC_IP=$(curl ${crlGet} https://api.ipify.org \
      | sed 's/[^0-9\.]//g' 2>&1)
    if [ -z "${_LOC_IP}" ]; then
      _LOC_IP=$(curl ${crlGet} http://ipv4.icanhazip.com \
        | sed 's/[^0-9\.]//g' 2>&1)
    fi
    if [ ! -z "${_LOC_IP}" ]; then
      echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
    fi
  fi
}

#
# Tune FPM workers.
satellite_tune_fpm_workers() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_tune_fpm_workers"
    debug_proc
  fi
  count_cpu
  # Set _PHP_FPM_WORKERS to AUTO if it is empty
  [ -z "${_PHP_FPM_WORKERS}" ] && _PHP_FPM_WORKERS=AUTO
  # If _PHP_FPM_WORKERS is not AUTO and not empty, then check if it is less than 1
  if [ "${_PHP_FPM_WORKERS}" != "AUTO" ] && [ -n "${_PHP_FPM_WORKERS}" ]; then
    if [ "${_PHP_FPM_WORKERS}" -lt 1 ] 2>/dev/null; then
      _PHP_FPM_WORKERS=AUTO
    fi
  fi
  # If _PHP_FPM_WORKERS is not AUTO, remove non-numeric characters
  [ "${_PHP_FPM_WORKERS}" != "AUTO" ] && _PHP_FPM_WORKERS=${_PHP_FPM_WORKERS//[^0-9]/}
  if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
    _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
  else
    _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
  fi
  # Set _PHP_FPM_TIMEOUT to AUTO if it is empty
  [ -z "${_PHP_FPM_TIMEOUT}" ] && _PHP_FPM_TIMEOUT=AUTO
  # If _PHP_FPM_TIMEOUT is not AUTO and not empty, then check if it is between 60 and 180
  if [ "${_PHP_FPM_TIMEOUT}" != "AUTO" ] && [ -n "${_PHP_FPM_TIMEOUT}" ]; then
    # If _PHP_FPM_TIMEOUT is not AUTO and not empty, remove non-numeric characters
    [ "${_PHP_FPM_TIMEOUT}" != "AUTO" ] && _PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT//[^0-9]/}
    # If _PHP_FPM_TIMEOUT is outside of the allowed range, use either min or max allowed
    if [ "${_PHP_FPM_TIMEOUT}" -lt 60 ]; then
      _PHP_FPM_TIMEOUT=60
    elif [ "${_PHP_FPM_TIMEOUT}" -gt 180 ]; then
      _PHP_FPM_TIMEOUT=180
    fi
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "DEBUG: _L_PHP_FPM_WORKERS is ${_L_PHP_FPM_WORKERS}"
    msg "DEBUG: _PHP_FPM_TIMEOUT is ${_PHP_FPM_TIMEOUT}"
  fi
}

#
# Update web user.
satellite_web_user_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_web_user_update"
    debug_proc
  fi
  isTest="${_WEB}"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ]; then
    _T_HD="/home/${_WEB}/.drush"
    _T_TP="/home/${_WEB}/.tmp"
    _T_TS="/home/${_WEB}/.aws"
    _T_II="${_T_HD}/php.ini"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "DEBUG: ${_WEB} in satellite_web_user_update A"
    fi
    if [ -d "/home/${_WEB}/" ] && [ ! -e "/home/${_WEB}/.lock" ]; then
      if [ -d "/home/${_WEB}/" ]; then
        chattr -i -R /home/${_WEB}/ &> /dev/null
      fi
      if [ -d "/home/${_WEB}/.drush/" ]; then
        chattr -i /home/${_WEB}/.drush/
      fi
      if [ -e "${_T_II}" ]; then
        chattr -i ${_T_II}
      fi
      mkdir -p /home/${_WEB}/.{tmp,drush,aws}
      touch /home/${_WEB}/.lock
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "DEBUG: ${_WEB} in satellite_web_user_update B"
        msg "DEBUG: ARG1 is $1 in satellite_web_user_update B"
      fi
      isTest="$1"
      isTest=${isTest//[^a-z0-9]/}
      if [ ! -z "${isTest}" ]; then
        if [ "$1" = "hhvm" ]; then
          if [ -e "/opt/php56/etc/php56.ini" ]; then
            _T_PV=56
          elif [ -e "/opt/php55/etc/php55.ini" ]; then
            _T_PV=55
          fi
        else
          _T_PV=$1
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "DEBUG: _T_PV is ${_T_PV} in satellite_web_user_update C"
          fi
        fi
      fi
      if [ ! -z "${_T_PV}" ] && [ -e "/opt/php${_T_PV}/etc/php${_T_PV}.ini" ]; then
        cp -af /opt/php${_T_PV}/etc/php${_T_PV}.ini ${_T_II}
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DEBUG: _T_PV is ${_T_PV} in satellite_web_user_update D"
        fi
      else
        _PHP_V="83 82 81 80 74 73 72 71 70 56"
        for e in ${_PHP_V}; do
          if [ -e "/opt/php${e}/etc/php${e}.ini" ]; then
            cp -af /opt/php${e}/etc/php${e}.ini ${_T_II}
            _T_PV=${e}
          fi
        done
      fi
      if [ -e "${_T_II}" ]; then
        _INI="open_basedir = \".: \
          /data/all:      \
          /data/conf:     \
          /data/disk/all: \
          /mnt:           \
          /opt/php56:     \
          /opt/php70:     \
          /opt/php71:     \
          /opt/php72:     \
          /opt/php73:     \
          /opt/php74:     \
          /opt/php80:     \
          /opt/php81:     \
          /opt/php82:     \
          /opt/php83:     \
          /opt/tika:      \
          /opt/tika7:     \
          /opt/tika8:     \
          /opt/tika9:     \
          /dev/urandom:   \
          /srv:           \
          /usr/bin:       \
          /usr/local/bin: \
          /var/second/${_USER}:    \
          ${_ROOT}/aegir:          \
          ${_ROOT}/backup-exports: \
          ${_ROOT}/distro:         \
          ${_ROOT}/platforms:      \
          ${_ROOT}/static:         \
          ${_T_HD}:                \
          ${_T_TP}:                \
          ${_T_TS}\""
        _INI=$(echo "${_INI}" | sed "s/ //g" 2>&1)
        _INI=$(echo "${_INI}" | sed "s/open_basedir=/open_basedir = /g" 2>&1)
        _INI=${_INI//\//\\\/}
        _QTP=${_T_TP//\//\\\/}
        sed -i "s/.*open_basedir =.*/${_INI}/g"                              ${_T_II}
        wait
        sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_T_II}
        wait
        sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_T_II}
        wait
        sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_T_II}
        wait
        sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_T_II}
        wait
        rm -f ${_T_HD}/.ctrl.php*
        echo > ${_T_HD}/.ctrl.php${_T_PV}.${_X_SE}.pid
      fi
      chmod 700 /home/${_WEB}/
      chown -R ${_WEB}:www-data /home/${_WEB}/
      chmod 550 /home/${_WEB}/.drush/
      chmod 440 /home/${_WEB}/.drush/php.ini
      rm -f /home/${_WEB}/.lock
      if [ -d "/home/${_WEB}/" ]; then
        chattr +i /home/${_WEB}/
      fi
      if [ -d "/home/${_WEB}/.drush/" ]; then
        chattr +i /home/${_WEB}/.drush/
      fi
      if [ -e "${_T_II}" ]; then
        chattr +i ${_T_II}
      fi
    fi
  fi
}

#
# Remove web user.
satellite_remove_web_user() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_remove_web_user"
    debug_proc
  fi
  if [ -d "/home/${_WEB}/" ] || [ "$1" = "clean" ]; then
    chattr -i -R /home/${_WEB}/ &> /dev/null
    if [ -d "/home/${_WEB}/.drush/" ]; then
      chattr -i /home/${_WEB}/.drush/
    fi
    mkdir -p ${vBs}/zombie/deleted
    kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
    deluser --remove-home --backup-to ${vBs}/zombie/deleted ${_WEB} &> /dev/null
    if [ -d "/home/${_WEB}/" ]; then
      rm -rf /home/${_WEB}/ &> /dev/null
    fi
  fi
}

#
# Add web user.
satellite_create_web_user() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_create_web_user"
    debug_proc
  fi
  _T_HD="/home/${_WEB}/.drush"
  _T_II="${_T_HD}/php.ini"
  _T_ID_EXISTS=$(getent passwd ${_WEB} 2>&1)
  if [ ! -z "${_T_ID_EXISTS}" ] && [ -e "${_T_II}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "DEBUG: ARG1 is $1 in satellite_create_web_user B"
    fi
    satellite_web_user_update "$1"
  elif [ -z "${_T_ID_EXISTS}" ] || [ ! -e "${_T_II}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "DEBUG: ARG1 is $1 in satellite_create_web_user C"
    fi
    satellite_remove_web_user "clean"
    adduser --force-badname --system --ingroup www-data --home /home/${_WEB} ${_WEB} &> /dev/null
    satellite_web_user_update "$1"
  fi
}

#
# Tune FPM configuration.
satellite_tune_fpm_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_tune_fpm_config"
    debug_proc
  fi
  satellite_tune_fpm_workers

  _LIM_FPM="${_L_PHP_FPM_WORKERS}"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "DEBUG: _LIM_FPM is ${_LIM_FPM}"
  fi

  if [ ! -z "${_CLIENT_OPTION}" ]; then
    if [ "${_CLIENT_OPTION}" = "CLUSTER" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=96
      fi
    elif [ "${_CLIENT_OPTION}" = "LITE" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=32
      fi
    elif [ "${_CLIENT_OPTION}" = "PHANTOM" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=16
      fi
    elif [ "${_CLIENT_OPTION}" = "POWER" ] \
      || [ "${_CLIENT_OPTION}" = "BUS" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=8
      fi
    elif [ "${_CLIENT_OPTION}" = "EDGE" ] \
      || [ "${_CLIENT_OPTION}" = "SSD" ] \
      || [ "${_CLIENT_OPTION}" = "CLASSIC" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=2
      fi
    elif [ "${_CLIENT_OPTION}" = "MINI" ] \
      || [ "${_CLIENT_OPTION}" = "MICRO" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=1
      fi
    else
      _LIM_FPM=2
    fi
  fi

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "DEBUG: _LIM_FPM is ${_LIM_FPM}"
    msg "DEBUG: _CLIENT_OPTION is ${_CLIENT_OPTION}"
  fi

  if [ ! -z "${_CLIENT_CORES}" ] && [ "${_CLIENT_CORES}" -ge "1" ]; then
    if [ -e "${_ROOT}/log/cores.txt" ]; then
      _CLIENT_CORES=$(cat ${_ROOT}/log/cores.txt 2>&1)
      _CLIENT_CORES=$(echo -n ${_CLIENT_CORES} | tr -d "\n" 2>&1)
    fi
    _CLIENT_CORES=${_CLIENT_CORES//[^0-9]/}
    if [ ! -z "${_CLIENT_CORES}" ] && [ "${_CLIENT_CORES}" -ge "1" ]; then
      _LIM_FPM=$(( _LIM_FPM *= _CLIENT_CORES ))
    fi
  fi

  if [ "${_LIM_FPM}" -gt "100" ]; then
    _LIM_FPM=100
  fi

  _CHILD_MAX_FPM=$(( _LIM_FPM * 2 ))

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "DEBUG: _LIM_FPM is ${_LIM_FPM}"
    msg "DEBUG: _CHILD_MAX_FPM is ${_CHILD_MAX_FPM}"
  fi

  _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
  if [ -z "${_PHP_SV}" ]; then
    _PHP_SV=74
  fi
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  _PHP_OLD_SV=
  for e in ${_PHP_V}; do
    if [ -e "/opt/php${e}/etc/pool.d/${_USER}.conf" ]; then
      _PHP_OLD_SV=${e}
    fi
  done
  if [ ! -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
    mkdir -p /var/xdrago/conf
  fi
  cp -af ${bldPth}/aegir/conf/php/fpm-pool-foo-multi.conf /var/xdrago/conf/
  cp -af ${bldPth}/aegir/conf/php/fpm-pool-foo.conf /var/xdrago/conf/
  if [ ! -z "${_PHP_FPM_TIMEOUT}" ] && [ ! -z "${_PHP_SV}" ]; then
    if [ -e "/var/xdrago/conf/fpm-pool-foo.conf" ]; then
      rm -f /opt/php*/etc/pool.d/${_USER}.conf
      cp -af /var/xdrago/conf/fpm-pool-foo.conf \
        /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf
    fi
    if [ -e "/opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf" ]; then
      ### create or update special system user if needed
      if [ -e "/home/${_WEB}/.drush/php.ini" ]; then
        _OLD_PHP_IN_USE=$(grep "/lib/php" /home/${_WEB}/.drush/php.ini 2>&1)
        _PHP_V="83 82 81 80 74 73 72 71 70 56"
        for e in ${_PHP_V}; do
          if [[ "${_OLD_PHP_IN_USE}" =~ "php${e}" ]]; then
            if [ "${e}" != "${_PHP_SV}" ] \
              || [ ! -e "/home/${_WEB}/.drush/.ctrl.php${_PHP_SV}.${_X_SE}.pid" ]; then
              satellite_web_user_update "${_PHP_SV}"
            fi
          fi
        done
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DEBUG: _PHP_SV is ${_PHP_SV} in satellite_create_web_user A"
        fi
        satellite_create_web_user "${_PHP_SV}"
      fi
      ### create or update special system user if needed
      sed -i "s/.ftp/.web/g" \
        /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      sed -i "s/\/data\/disk\/foo\/.tmp/\/home\/foo.web\/.tmp/g" \
        /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      sed -i "s/foo/${_USER}/g" \
        /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      sed -i "s/THISPOOL/${_USER}/g" \
        /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      if [ ! -z "${_PHP_FPM_DENY}" ]; then
        sed -i "s/passthru,/${_PHP_FPM_DENY},/g" \
          /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
        wait
      fi
    fi
    _PHP_TO="${_PHP_FPM_TIMEOUT}s"
    sed -i "s/180s/${_PHP_TO}/g" \
      /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
    wait
    if [ ! -z "${_CHILD_MAX_FPM}" ] && [ "${_CHILD_MAX_FPM}" -ge "8" ]; then
      sed -i "s/pm.max_children =.*/pm.max_children = ${_CHILD_MAX_FPM}/g" \
        /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
    else
      sed -i "s/pm.max_children =.*/pm.max_children = 8/g" \
        /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
    fi
    if [ ! -d "${_ROOT}/tmp" ]; then
      mkdir -p ${_ROOT}/tmp
      chown ${_USER}:users ${_ROOT}/tmp &> /dev/null
    fi
    if [ ! -z "${_PHP_OLD_SV}" ] \
      && [ -e "/etc/init.d/php${_PHP_OLD_SV}-fpm" ]; then
      mrun "service php${_PHP_OLD_SV}-fpm reload" 2> /dev/null
    fi
    if [ -e "/etc/init.d/php${_PHP_SV}-fpm" ]; then
      mrun "service php${_PHP_SV}-fpm reload" 2> /dev/null
    fi
  fi
}

#
# Make sure that username is unique and not restricted.
satellite_check_id() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_check_id"
    debug_proc
  fi
  _ID_EXISTS=$(getent passwd ${_USER} 2>&1)
  if [ -z "${_ID_EXISTS}" ]; then
    _DO_NOTHING=YES
  elif [[ "${_ID_EXISTS}" =~ "${_USER}" ]]; then
    msg "ERROR: ${_USER} username is already taken"
    msg "Please choose different _USER"
    clean_pid_exit satellite_check_id_a
  else
    msg "ERROR: ${_USER} username check failed"
    msg "Please try different _USER"
    clean_pid_exit satellite_check_id_b
  fi
  if [ "${_USER}" = "admin" ] \
    || [ "${_USER}" = "hostmaster" ] \
    || [ "${_USER}" = "barracuda" ] \
    || [ "${_USER}" = "octopus" ] \
    || [ "${_USER}" = "boa" ] \
    || [ "${_USER}" = "all" ]; then
    msg "ERROR: ${_USER} is a restricted username"
    msg "ERROR: Please choose a different _USER"
    clean_pid_exit satellite_check_id_c
  elif [[ "${_USER}" =~ "drupal" ]] \
    || [[ "${_USER}" =~ "drush" ]] \
    || [[ "${_USER}" =~ "sites" ]] \
    || [[ "${_USER}" =~ "default" ]]; then
    msg "ERROR: ${_USER} includes restricted keyword"
    msg "ERROR: Please choose a different _USER"
    clean_pid_exit satellite_check_id_d
  fi
  _REGEX="^[[:digit:]]"
  if [[ "${_USER}" =~ "${_REGEX}" ]]; then
    msg "ERROR: ${_USER} is a wrong username"
    msg "ERROR: The correct username should start with a letter, not digit"
    clean_pid_exit satellite_check_id_e
  fi
}

#
# Enable chattr.
enable_chattr() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: enable_chattr"
    debug_proc
  fi
  isTest="$1"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [ -d "/home/$1/" ]; then
    if [ -d "/home/$1/platforms/" ]; then
      chattr +i /home/$1/platforms/
      chattr +i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.drush/" ]; then
      chattr +i /home/$1/.drush/
    fi
    if [ -d "/home/$1/.drush/usr/" ]; then
      chattr +i /home/$1/.drush/usr/
    fi
    if [ -f "/home/$1/.drush/php.ini" ]; then
      chattr +i /home/$1/.drush/*.ini
    fi
    if [ -d "/home/$1/.bazaar/" ]; then
      chattr +i /home/$1/.bazaar/
    fi
  fi
}

#
# Disable chattr.
disable_chattr() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: disable_chattr"
    debug_proc
  fi
  isTest="$1"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [ -d "/home/$1/" ]; then
    if [ -d "/home/$1/platforms/" ]; then
      chattr -i /home/$1/platforms/
      chattr -i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.drush/" ]; then
      chattr -i /home/$1/.drush/
    fi
    if [ -d "/home/$1/.drush/usr/" ]; then
      chattr -i /home/$1/.drush/usr/
    fi
    if [ -f "/home/$1/.drush/php.ini" ]; then
      chattr -i /home/$1/.drush/*.ini
    fi
    if [ -d "/home/$1/.bazaar/" ]; then
      chattr -i /home/$1/.bazaar/
    fi
  fi
}

#
# Read or create Octopus cnf file.
satellite_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_cnf"
    debug_proc
  fi
  if [ ! -e "${octCnf}" ]; then
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]] \
      || [[ "${_CLIENT_EMAIL}" =~ "omega8.cc" ]]; then
      _CHECK_HOST=$(uname -n 2>&1)
      if_hosted_sys
      if [ "${hostedSys}" != "YES" ]; then
        msg "EXIT: You must enter **your** valid email address"
        msg "EXIT: in the _MY_EMAIL **and** _CLIENT_EMAIL variables"
        clean_pid_exit satellite_cnf_a
      fi
    fi
    msg "INFO: Creating your ${octCnf} config file"
    sleep 1
    echo "###"                                                   > ${octCnf}
    echo "### Configuration created on ${_NOW} with"            >> ${octCnf}
    echo "### Octopus version ${_X_VERSION}"                    >> ${octCnf}
    echo "###"                                                  >> ${octCnf}
    echo "_USER=\"${_USER}\""                                   >> ${octCnf}
    echo "_MY_EMAIL=\"${_MY_EMAIL}\""                           >> ${octCnf}
    echo "_PLATFORMS_LIST=\"${_PLATFORMS_LIST}\""               >> ${octCnf}
    echo "_AUTOPILOT=${_AUTOPILOT}"                             >> ${octCnf}
    echo "_HM_ONLY=${_HM_ONLY}"                                 >> ${octCnf}
    echo "_DEBUG_MODE=${_DEBUG_MODE}"                           >> ${octCnf}
    echo "_MY_OWNIP=${_MY_OWNIP}"                               >> ${octCnf}
    echo "_FORCE_GIT_MIRROR=\"${_FORCE_GIT_MIRROR}\""           >> ${octCnf}
    echo "_THIS_DB_HOST=${_THIS_DB_HOST}"                       >> ${octCnf}
    echo "_THIS_DB_PORT=${_THIS_DB_PORT}"                       >> ${octCnf}
    echo "_DNS_SETUP_TEST=${_DNS_SETUP_TEST}"                   >> ${octCnf}
    echo "_HOT_SAUCE=${_HOT_SAUCE}"                             >> ${octCnf}
    echo "_USE_CURRENT=${_USE_CURRENT}"                         >> ${octCnf}
    echo "_DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS}" >> ${octCnf}
    echo "_DEL_OLD_BACKUPS=${_DEL_OLD_BACKUPS}"                 >> ${octCnf}
    echo "_DEL_OLD_TMP=${_DEL_OLD_TMP}"                         >> ${octCnf}
    echo "_LOCAL_NETWORK_IP=${_LOCAL_NETWORK_IP}"               >> ${octCnf}
    echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}"                 >> ${octCnf}
    echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}"                 >> ${octCnf}
    echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}"                 >> ${octCnf}
    echo "_PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT}"                 >> ${octCnf}
    echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\""                   >> ${octCnf}
    echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}"               >> ${octCnf}
    echo "_SQL_CONVERT=${_SQL_CONVERT}"                         >> ${octCnf}
    echo "_RESERVED_RAM=${_RESERVED_RAM}"                       >> ${octCnf}
    echo "###"                                                  >> ${octCnf}
    echo "_DOMAIN=\"${_DOMAIN}\""                               >> ${octCnf}
    echo "_CLIENT_EMAIL=\"${_CLIENT_EMAIL}\""                   >> ${octCnf}
    echo "_CLIENT_OPTION=\"${_CLIENT_OPTION}\""                 >> ${octCnf}
    echo "_CLIENT_SUBSCR=\"${_CLIENT_SUBSCR}\""                 >> ${octCnf}
    echo "_CLIENT_CORES=\"${_CLIENT_CORES}\""                   >> ${octCnf}
    echo "###"                                                  >> ${octCnf}
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Reading your ${octCnf} config file"
    fi
    sleep 1
    _PHP_FPM_WORKERS_TEST=$(grep _PHP_FPM_WORKERS ${octCnf} 2>&1)
    if [[ "${_PHP_FPM_WORKERS_TEST}" =~ "_PHP_FPM_WORKERS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}" >> ${octCnf}
    fi
    _PHP_FPM_TIMEOUT_TEST=$(grep _PHP_FPM_TIMEOUT ${octCnf} 2>&1)
    if [[ "${_PHP_FPM_TIMEOUT_TEST}" =~ "_PHP_FPM_TIMEOUT" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT}" >> ${octCnf}
    fi
    _PHP_FPM_DENY_TEST=$(grep _PHP_FPM_DENY ${octCnf} 2>&1)
    if [[ "${_PHP_FPM_DENY_TEST}" =~ "_PHP_FPM_DENY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\"" >> ${octCnf}
    fi
     _RESERVED_RAM_TEST=$(grep _RESERVED_RAM ${octCnf} 2>&1)
    if [[ "${_RESERVED_RAM_TEST}" =~ "_RESERVED_RAM" ]]; then
      _DO_NOTHING=YES
    else
      echo "_RESERVED_RAM=${_RESERVED_RAM}" >> ${octCnf}
    fi
    _PHP_FPM_VERSION_TEST=$(grep _PHP_FPM_VERSION ${octCnf} 2>&1)
    if [[ "${_PHP_FPM_VERSION_TEST}" =~ "_PHP_FPM_VERSION" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}" >> ${octCnf}
    fi
    _PHP_CLI_VERSION_TEST=$(grep _PHP_CLI_VERSION ${octCnf} 2>&1)
    if [[ "${_PHP_CLI_VERSION_TEST}" =~ "_PHP_CLI_VERSION" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}" >> ${octCnf}
    fi
    _CHECK_HOST=$(uname -n 2>&1)
    if_hosted_sys
    if [ "${hostedSys}" = "YES" ]; then
      _LD_DOM=YES
    else
      _LD_DOM=NO
    fi

    if [ ! -e "${_ROOT}/static/control/fpm.info" ]; then
      if [ -e "${_ROOT}/log/fpm.txt" ]; then
        _PHP_FPM_VERSION=$(cat ${_ROOT}/log/fpm.txt 2>&1)
        _PHP_FPM_VERSION=$(echo -n ${_PHP_FPM_VERSION} | tr -d "\n" 2>&1)
      else
        _PHP_FPM_VERSION=8.1
      fi
      echo ${_PHP_FPM_VERSION} > ${_ROOT}/static/control/fpm.info
      chown ${_USER}.ftp:users ${_ROOT}/static/control/fpm.info
    fi

    if [ -e "${_ROOT}/static/control/fpm.info" ]; then
      _PHP_FPM_VERSION=$(cat ${_ROOT}/static/control/fpm.info 2>&1)
      _PHP_FPM_VERSION=$(echo -n ${_PHP_FPM_VERSION} | tr -d "\n" 2>&1)
      if [ "${_PHP_FPM_VERSION}" = "8.3" ] \
        || [ "${_PHP_FPM_VERSION}" = "8.2" ] \
        || [ "${_PHP_FPM_VERSION}" = "8.1" ] \
        || [ "${_PHP_FPM_VERSION}" = "8.0" ] \
        || [ "${_PHP_FPM_VERSION}" = "7.4" ] \
        || [ "${_PHP_FPM_VERSION}" = "7.3" ] \
        || [ "${_PHP_FPM_VERSION}" = "7.2" ] \
        || [ "${_PHP_FPM_VERSION}" = "7.1" ] \
        || [ "${_PHP_FPM_VERSION}" = "7.0" ] \
        || [ "${_PHP_FPM_VERSION}" = "5.6" ]; then
        if [ "${_PHP_FPM_VERSION}" = "8.3" ] \
          && [ ! -x "/opt/php83/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_FPM_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.2" ] \
          && [ ! -x "/opt/php82/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_FPM_VERSION=8.3
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.1" ] \
          && [ ! -x "/opt/php81/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_FPM_VERSION=8.2
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_FPM_VERSION=8.3
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.0" ] \
          && [ ! -x "/opt/php80/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.4" ] \
          && [ ! -x "/opt/php74/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.3" ] \
          && [ ! -x "/opt/php73/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.2" ] \
          && [ ! -x "/opt/php72/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.1" ] \
          && [ ! -x "/opt/php71/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.0" ] \
          && [ ! -x "/opt/php70/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "5.6" ] \
          && [ ! -x "/opt/php56/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        fi
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_PHP_FPM_VERSION}/g" \
          ${octCnf} &> /dev/null
        wait
        echo ${_PHP_FPM_VERSION} > ${_ROOT}/log/fpm.txt
        echo ${_PHP_FPM_VERSION} > ${_ROOT}/static/control/fpm.info
        chown ${_USER}.ftp:users ${_ROOT}/static/control/fpm.info
      fi
    fi

    if [ ! -e "${_ROOT}/static/control/cli.info" ]; then
      if [ -e "${_ROOT}/log/cli.txt" ]; then
        _PHP_CLI_VERSION=$(cat ${_ROOT}/log/cli.txt 2>&1)
        _PHP_CLI_VERSION=$(echo -n ${_PHP_CLI_VERSION} | tr -d "\n" 2>&1)
      else
        _PHP_CLI_VERSION=8.1
      fi
      echo ${_PHP_CLI_VERSION} > ${_ROOT}/static/control/cli.info
      chown ${_USER}.ftp:users ${_ROOT}/static/control/cli.info
    fi

    if [ -e "${_ROOT}/static/control/cli.info" ]; then
      _PHP_CLI_VERSION=$(cat ${_ROOT}/static/control/cli.info 2>&1)
      _PHP_CLI_VERSION=$(echo -n ${_PHP_CLI_VERSION} | tr -d "\n" 2>&1)
      if [ "${_PHP_CLI_VERSION}" = "8.3" ] \
        || [ "${_PHP_CLI_VERSION}" = "8.2" ] \
        || [ "${_PHP_CLI_VERSION}" = "8.1" ] \
        || [ "${_PHP_CLI_VERSION}" = "8.0" ] \
        || [ "${_PHP_CLI_VERSION}" = "7.4" ] \
        || [ "${_PHP_CLI_VERSION}" = "7.3" ] \
        || [ "${_PHP_CLI_VERSION}" = "7.2" ] \
        || [ "${_PHP_CLI_VERSION}" = "7.1" ] \
        || [ "${_PHP_CLI_VERSION}" = "7.0" ] \
        || [ "${_PHP_CLI_VERSION}" = "5.6" ]; then
        if [ "${_PHP_CLI_VERSION}" = "8.3" ] \
          && [ ! -x "/opt/php83/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_CLI_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.2" ] \
          && [ ! -x "/opt/php82/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_CLI_VERSION=8.3
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.1" ] \
          && [ ! -x "/opt/php81/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_CLI_VERSION=8.2
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_CLI_VERSION=8.3
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.0" ] \
          && [ ! -x "/opt/php80/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.4" ] \
          && [ ! -x "/opt/php74/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.3" ] \
          && [ ! -x "/opt/php73/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.2" ] \
          && [ ! -x "/opt/php72/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.1" ] \
          && [ ! -x "/opt/php71/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.0" ] \
          && [ ! -x "/opt/php70/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "5.6" ] \
          && [ ! -x "/opt/php56/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        fi
        sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_PHP_CLI_VERSION}/g" \
          ${octCnf} &> /dev/null
        wait
        echo ${_PHP_CLI_VERSION} > ${_ROOT}/log/cli.txt
        echo ${_PHP_CLI_VERSION} > ${_ROOT}/static/control/cli.info
        chown ${_USER}.ftp:users ${_ROOT}/static/control/cli.info
      fi
    fi

    _O_CONTRIB_UP_TEST=$(grep _O_CONTRIB_UP ${octCnf} 2>&1)
    if [[ "${_O_CONTRIB_UP_TEST}" =~ "_O_CONTRIB_UP" ]]; then
      sed -i "s/^_O_CONTRIB_UP.*//g" ${octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${octCnf} &> /dev/null
      wait
    fi

    _ALLOW_UNSUPPORTED_TEST=$(grep _ALLOW_UNSUPPORTED ${octCnf} 2>&1)
    if [[ "${_ALLOW_UNSUPPORTED_TEST}" =~ "_ALLOW_UNSUPPORTED" ]]; then
      sed -i "s/^_ALLOW_UNSUPPORTED.*//g" ${octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${octCnf} &> /dev/null
      wait
    fi

    _USE_STOCK_TEST=$(grep _USE_STOCK ${octCnf} 2>&1)
    if [[ "${_USE_STOCK_TEST}" =~ "_USE_STOCK" ]]; then
      sed -i "s/^_USE_STOCK.*//g" ${octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${octCnf} &> /dev/null
      wait
    fi

    _HTTP_WILDCARD_TEST=$(grep _HTTP_WILDCARD ${octCnf} 2>&1)
    if [[ "${_HTTP_WILDCARD_TEST}" =~ "_HTTP_WILDCARD" ]]; then
      sed -i "s/^_HTTP_WILDCARD.*//g" ${octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${octCnf} &> /dev/null
      wait
    fi

    _DEL_OLD_EMPTY_PLATFORMS_TEST=$(grep _DEL_OLD_EMPTY_PLATFORMS ${octCnf} 2>&1)
    if [[ "${_DEL_OLD_EMPTY_PLATFORMS_TEST}" =~ "_DEL_OLD_EMPTY_PLATFORMS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS}" >> ${octCnf}
    fi

    _DEL_OLD_BACKUPS_TEST=$(grep _DEL_OLD_BACKUPS ${octCnf} 2>&1)
    if [[ "${_DEL_OLD_BACKUPS_TEST}" =~ "_DEL_OLD_BACKUPS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DEL_OLD_BACKUPS=${_DEL_OLD_BACKUPS}" >> ${octCnf}
    fi

    _DEL_OLD_TMP_TEST=$(grep _DEL_OLD_TMP ${octCnf} 2>&1)
    if [[ "${_DEL_OLD_TMP_TEST}" =~ "_DEL_OLD_TMP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DEL_OLD_TMP=${_DEL_OLD_TMP}" >> ${octCnf}
    fi

    if [ "${_LD_DOM}" = "YES" ]; then
      _STRONG_PASSWORDS=YES
    fi
    _STRONG_PASSWORDS_TEST=$(grep _STRONG_PASSWORDS ${octCnf} 2>&1)
    if [[ "${_STRONG_PASSWORDS_TEST}" =~ "_STRONG_PASSWORDS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}" >> ${octCnf}
    fi

    _SQL_CONVERT_TEST=$(grep _SQL_CONVERT ${octCnf} 2>&1)
    if [[ "${_SQL_CONVERT_TEST}" =~ "_SQL_CONVERT" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SQL_CONVERT=${_SQL_CONVERT}" >> ${octCnf}
    fi

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "NOTE! Please review all config options displayed below"
      sleep 3
      echo " "
      while read line; do
        echo "$line"
      done < ${octCnf}
      echo " "
    fi

    if [ -e "${octCnf}" ]; then
      source ${octCnf}
    fi
    _PRE_PLATFORMS_LIST="${_PLATFORMS_LIST}"
    if [ -e "${_ROOT}/static/control/platforms.info" ]; then
      _PLATFORMS_LIST=$(cat ${_ROOT}/static/control/platforms.info 2>&1)
      _PLATFORMS_LIST=$(echo -n ${_PLATFORMS_LIST} | tr -d "\n" 2>&1)
      _PLATFORMS_LIST=${_PLATFORMS_LIST//[^ 0-9A-Z]/}
      msg "NOTE! Custom Platforms List: ${_PLATFORMS_LIST}"
      if [ -z "${_PLATFORMS_LIST}" ]; then
        _PLATFORMS_LIST="${_PRE_PLATFORMS_LIST}"
        msg "NOTE! Default Platforms List: ${_PLATFORMS_LIST}"
      fi
    fi
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      if_hosted_sys
      if [ "${hostedSys}" != "YES" ]; then
        msg "EXIT: You must enter **your** valid email address in the"
        msg "EXIT: _MY_EMAIL variable in the ${octCnf} file"
        clean_pid_exit satellite_cnf_b
      fi
    fi
    if [ "${_PHP_FPM_VERSION}" = "8.3" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.3" ]; then
      if [ ! -x "/opt/php83/bin/php" ]; then
        if [ -x "/opt/php81/bin/php" ]; then
          _PHP_FPM_VERSION=8.1
          _PHP_CLI_VERSION=8.1
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.2" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.2" ]; then
      if [ ! -x "/opt/php82/bin/php" ]; then
        if [ -x "/opt/php81/bin/php" ]; then
          _PHP_FPM_VERSION=8.1
          _PHP_CLI_VERSION=8.1
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.1" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.1" ]; then
      if [ ! -x "/opt/php81/bin/php" ]; then
        if [ -x "/opt/php82/bin/php" ]; then
          _PHP_FPM_VERSION=8.2
          _PHP_CLI_VERSION=8.2
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.0" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.0" ]; then
      if [ ! -x "/opt/php80/bin/php" ]; then
        if [ -x "/opt/php81/bin/php" ]; then
          _PHP_FPM_VERSION=8.1
          _PHP_CLI_VERSION=8.1
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.4" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.4" ]; then
      if [ ! -x "/opt/php74/bin/php" ]; then
        if [ -x "/opt/php81/bin/php" ]; then
          _PHP_FPM_VERSION=8.1
          _PHP_CLI_VERSION=8.1
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.3" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.3" ]; then
      if [ ! -x "/opt/php73/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.2" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.2" ]; then
      if [ ! -x "/opt/php72/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.1" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.1" ]; then
      if [ ! -x "/opt/php71/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.0" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.0" ]; then
      if [ ! -x "/opt/php70/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "5.6" ] \
      || [ "${_PHP_CLI_VERSION}" = "5.6" ]; then
      if [ ! -x "/opt/php56/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    else
      _PHP_FPM_VERSION=8.1
      _PHP_CLI_VERSION=8.1
    fi
    if [ -z "${_PHP_FPM_VERSION}" ] || [ -z "${_PHP_CLI_VERSION}" ]; then
      msg "EXIT: You must specify already installed PHP version"
      msg "EXIT: in both _PHP_FPM_VERSION and _PHP_CLI_VERSION"
      clean_pid_exit satellite_cnf_c
    fi
  fi

  if [ ! -z "${_LOCAL_NETWORK_IP}" ] \
    && [ "${_THIS_HOST}" != "aegir.local" ]; then
    _DNS_SETUP_TEST=NO
    _MY_OWNIP="${_LOCAL_NETWORK_IP}"
  fi
}

#
# Fix advanced cron IP for cURL requests.
satellite_fix_cron_curl() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_fix_cron_curl"
    debug_proc
  fi
  if [ -e "${_ROOT}/.drush/hostmaster.alias.drushrc.php" ]; then
    _THIS_HM_ROOT=$(cat ${_ROOT}/.drush/hostmaster.alias.drushrc.php \
      | grep "root'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    pthA="profiles/hostmaster/modules/aegir/hosting/cron"
    pthB="hosting_cron.module"
    if [ -e "${_THIS_HM_ROOT}/${pthA}/${pthB}" ]; then
      sed -i "s/127.0.0.1/${_CRON_IP}/g" ${_THIS_HM_ROOT}/${pthA}/${pthB}
    fi
  fi
}

#
# Fix multi-IP cron access.
satellite_fix_multi_ip_cron_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_fix_multi_ip_cron_access"
    debug_proc
  fi
  [ -e "/root/.local.IP.list.allow" ] && rm -f /root/.local.IP.list.allow
  for _IP in `cat /root/.local.IP.list \
    | cut -d '#' -f1 \
    | sort \
    | uniq \
    | tr -d "\s"`;do echo "  allow        ${_IP};" >> \
      /root/.local.IP.list.allow;done
  echo "  allow        127.0.0.1;" >> /root/.local.IP.list.allow
  echo "  deny         all;" >> /root/.local.IP.list.allow

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" \
    ${octTpl}/Inc/vhost_include.tpl.php
  wait
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${octTpl}/Inc/vhost_include.tpl.php
  wait

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" \
    ${octTpl}/subdir.tpl.php
  wait
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${octTpl}/subdir.tpl.php
  wait

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" \
    ${octInc}/nginx_vhost_common.conf
  wait
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${octInc}/nginx_vhost_common.conf
  wait
}

#
# Sub Force advanced Nginx configuration.
satellite_sub_satellite_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_sub_satellite_force_advanced_nginx_config"
    debug_proc
  fi
  if [ -d "${octInc}" ]; then
    _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
    if [ -z "${_PHP_SV}" ]; then
      _PHP_SV=74
    fi
    if [ -e "/opt/php${_PHP_SV}/etc/php${_PHP_SV}-fpm.conf" ]; then
      sed -i "s/set.*user_socket.*/set \$user_socket \"${_USER}\";/g" ${octTpl}/Inc/vhost_include.tpl.php &> /dev/null
      sed -i "s/set.*user_socket.*/set \$user_socket \"${_USER}\";/g" ${octTpl}/subdir.tpl.php            &> /dev/null
      sed -i "s/set.*user_socket.*/set \$user_socket \"${_USER}\";/g" ${octInc}/nginx_vhost_common.conf   &> /dev/null
    fi
    if [ ! -z "${_CUSTOM_COLLATION_SQL}" ]; then
      _SITES_COLLATION_SQL=${_CUSTOM_COLLATION_SQL}
    fi
    if [ ! -z "${_SITES_COLLATION_SQL}" ]; then
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_10.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_9.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_8.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_7.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_6.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_10.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_9.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_8.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_7.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${octSetTpl}/provision_drupal_settings_6.tpl.php &> /dev/null
    fi
    _CRON_IP=${_THISHTIP//[^0-9.]/}
    if [ ! -e "/root/.local.IP.list" ]; then
      rm -f /root/.tmp.IP.list*
      rm -f /root/.local.IP.list*
      for _IP in `hostname -I`;do echo ${_IP} >> /root/.tmp.IP.list;done
      for _IP in `cat /root/.tmp.IP.list \
        | sort \
        | uniq`;do echo "${_IP} # local IP address" >> /root/.local.IP.list;done
      rm -f /root/.tmp.IP.list*
    fi
    _IP_IF_PRESENT=$(grep "${_CRON_IP}" /root/.local.IP.list 2>&1)
    if [[ "${_IP_IF_PRESENT}" =~ "${_CRON_IP}" ]]; then
      _IP_PRESENT=YES
    else
      _IP_PRESENT=NO
    fi
    if [ ! -z "${_CRON_IP}" ] \
      && [ "${_IP_PRESENT}" = "YES" ] \
      && [ -e "/root/.local.IP.list" ]; then
      satellite_fix_multi_ip_cron_access
      satellite_fix_cron_curl
    fi
  fi
}

#
# Force advanced Nginx configuration.
satellite_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_force_advanced_nginx_config"
    debug_proc
  fi
  satellite_sub_satellite_force_advanced_nginx_config
  if [ -e "${_ROOT}/config/includes/nginx_vhost_common.conf" ]; then
    rm -f ${_ROOT}/config/includes/nginx_advanced_include.conf
    rm -f ${_ROOT}/config/includes/nginx_legacy_include.conf
    rm -f ${_ROOT}/config/includes/nginx_modern_include.conf
    rm -f ${_ROOT}/config/includes/nginx_octopus_include.conf
    rm -f ${_ROOT}/config/includes/nginx_simple_include.conf
  fi
}

#
# Update local INI for PHP CLI on the Aegir Satellite Instance.
satellite_child_b_update_ini_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_update_ini_php_cli"
    debug_proc
  fi
  _U_HD="${_ROOT}/.drush"
  _U_TP="${_ROOT}/.tmp"
  _U_II="${_U_HD}/php.ini"
  _PHP_CLI_UPDATE=NO
  _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_DRUSH_FILE} 2>&1)
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
      && [ ! -e "${_U_HD}/.ctrl.php${e}.${_X_SE}.pid" ]; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
    || [ ! -e "${_U_II}" ] \
    || [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_X_SE}.pid" ]; then
    mkdir -p ${_U_TP}
    touch ${_U_TP}
    find ${_U_TP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
    chmod 02755 ${_U_TP}
    mkdir -p ${_U_HD}/{sys,xts,usr}
    rm -f ${_U_HD}/.ctrl.php*
    rm -f ${_U_II}
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]]; then
        if [ -e "/opt/php${e}/lib/php.ini" ]; then
          cp -af /opt/php${e}/lib/php.ini ${_U_II}
          _U_INI=${e}
        fi
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
        /opt/tika:           \
        /opt/tika7:          \
        /opt/tika8:          \
        /opt/tika9:          \
        /dev/urandom:        \
        /opt/tmp/make_local: \
        /opt/tools/drush:    \
        ${_ROOT}:            \
        /usr/local/bin:      \
        /usr/bin\""
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

#
# Update php-cli for Drush.
satellite_child_b_update_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_update_php_cli"
    debug_proc
  fi
  _DRUSH_FILE="${_ROOT}/tools/drush/drush.php"
  if [ "${_PHP_CLI_VERSION}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php83\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.2" ] && [ -x "/opt/php82/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php82\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.1" ] && [ -x "/opt/php81/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php81\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.0" ] && [ -x "/opt/php80/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php80\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.4" ] && [ -x "/opt/php74/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php74\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.3" ] && [ -x "/opt/php73/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php73\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.2" ] && [ -x "/opt/php72/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php72\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.1" ] && [ -x "/opt/php71/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php71\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.0" ] && [ -x "/opt/php70/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php70\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "5.6" ] && [ -x "/opt/php56/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php56\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
  else
    msg "${_STATUS} B: FATAL ERROR: _PHP_CLI_VERSION is not set correctly"
    msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
    touch /opt/tmp/status-AegirSetupB-FAIL
    exit 1
  fi
}

#
# Create shared dirs.
satellite_create_shared_dirs() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_create_shared_dirs"
    debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Creating shared directories..."
  fi
  mkdir -p ${_D}/000/{core,modules}
  rm -rf /data/src
  if [ ! -d "${_CORE}" ]; then
    mkdir -p ${_CORE}
  fi
  chown -R ${_USER}:${_USRG} /data/conf      &> /dev/null
  chown -R ${_USER}:${_USRG} /opt/tmp        &> /dev/null
  chown ${_USER}:${_USRG} ${_D}              &> /dev/null
  chown ${_USER}:${_USRG} ${_D}/000          &> /dev/null
  chown ${_USER}:${_USRG} ${_D}/000/core     &> /dev/null
  chown ${_USER}:${_USRG} ${_CORE}           &> /dev/null
  chmod 777 ${_CORE} ${_D} /data /data/disk /data/conf &> /dev/null
}

#
# Update o_contrib.
satellite_o_contrib_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_o_contrib_update_global"
    debug_proc
  fi

  _RMMODULES="drupal-nginx-fast-x-accel-redirect varnish bakery session443 \
    cookie_cache_bypass_adv module_supports imageinfo_cache redis"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib" ] \
      && [ ! -e "${i}/o_contrib/update-${_X_SE}-${_X_VERSION}.info" ]; then
      _FORCE_UP_SIX=YES
    elif [ -e "${i}/o_contrib" ] \
      && [ ! -e "${_D}/000/modules/redis_edge" ]; then
      _FORCE_UP_SIX=YES
    elif [ -e "${i}/o_contrib" ] \
      && [ ! -L "${i}/o_contrib/redis_edge" ]; then
      _FORCE_UP_SIX=YES
    else
      _FORCE_UP_SIX=NO
    fi
    if [ "${_FORCE_UP_SIX}" = "YES" ] && [ -e "${i}/o_contrib" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib/$m" ]; then
          rm -rf ${i}/o_contrib/$m
        fi
      done
      cd ${i}/o_contrib
      if [ ! -d "${i}/o_contrib/advagg" ]; then
        get_dev_contrib "advagg-6.x-1.11.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/boost" ]; then
        get_dev_contrib "boost-6.x-1.22.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/cdn" ]; then
        get_dev_contrib "cdn-6.x-2.7.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/force_password_change" ]; then
        get_dev_contrib "force_password_change-6.x-3.4.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/fpa" ]; then
        get_dev_contrib "fpa-6.x-2.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/httprl" ]; then
        get_dev_contrib "httprl-6.x-1.14.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/js" ]; then
        get_dev_contrib "js-6.x-1.3.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/panels_content_cache" ]; then
        get_dev_contrib "panels_content_cache-6.x-1.0.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/phpass" ]; then
        get_dev_contrib "phpass-6.x-2.1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/session_expire" ]; then
        get_dev_contrib "session_expire-6.x-1.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/taxonomy_edge" ]; then
        get_dev_contrib "taxonomy_edge-6.x-1.7.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/views_cache_bully" ]; then
        get_dev_contrib "views_cache_bully-6.x-3.1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/views_content_cache" ]; then
        get_dev_contrib "views_content_cache-6.x-2.x-dev.tar.gz"
      fi
      if [ -d "${i}/o_contrib/expire" ]; then
        rm -rf ${i}/o_contrib/expire
      fi
      if [ -d "${i}/o_contrib/purge" ]; then
        rm -rf ${i}/o_contrib/purge
      fi
      if [ -d "${i}/o_contrib/cache_backport" ]; then
        rm -rf ${i}/o_contrib/cache_backport
      fi
      if [ -d "${i}/o_contrib/redis" ]; then
        rm -rf ${i}/o_contrib/redis
      fi
      if [ -d "${i}/o_contrib/redis_edge" ]; then
        rm -rf ${i}/o_contrib/redis_edge
      fi
      if [ -e "${_D}/000/modules/cache_backport" ] \
        && [ ! -L "${i}/o_contrib/cache_backport" ]; then
        ln -sfn ${_D}/000/modules/cache_backport ${i}/o_contrib/cache_backport
      fi
      if [ -L "${i}/o_contrib/redis" ]; then
        rm -f ${i}/o_contrib/redis
      fi
      if [ -e "${_D}/000/modules/redis_edge" ] \
        && [ ! -L "${i}/o_contrib/redis_edge" ]; then
        ln -sfn ${_D}/000/modules/redis_edge ${i}/o_contrib/redis_edge
      fi
      touch ${i}/o_contrib/update-${_X_SE}-${_X_VERSION}.info
      find ${i}/o_contrib -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib -type f -exec chmod 0644 {} \; &> /dev/null
    fi
    if [ -d "${_D}/$i" ]; then
      for p in `find ${i}/ -maxdepth 1 -mindepth 1 -type d | sort`; do
        if [ -d "$p/modules/cookie_cache_bypass" ]; then
          rm -rf $p/modules/cookie_cache_bypass
        fi
      done
    fi
  done
  cd
}

#
# Update o_contrib_seven.
satellite_o_contrib_seven_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_o_contrib_seven_update_global"
    debug_proc
  fi

  _RMMODULES="session443 cookie_cache_bypass_adv agrcache speedy redis"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_seven" ] \
      && [ ! -e "${i}/o_contrib_seven/update-${_X_SE}-${_X_VERSION}.info" ]; then
      _FORCE_UP_SEVEN=YES
    elif [ -e "${i}/o_contrib_seven" ] \
      && [ ! -e "${i}/o_contrib_seven/views_accelerator" ]; then
      _FORCE_UP_SEVEN=YES
    elif [ -e "${i}/o_contrib_seven" ] \
      && [ ! -e "${_D}/000/modules/redis_edge" ]; then
      _FORCE_UP_SEVEN=YES
    elif [ -e "${i}/o_contrib_seven" ] \
      && [ ! -L "${i}/o_contrib_seven/redis_edge" ]; then
      _FORCE_UP_SEVEN=YES
    else
      _FORCE_UP_SEVEN=NO
    fi
    if [ "${_FORCE_UP_SEVEN}" = "YES" ] \
      && [ -e "${i}/o_contrib_seven" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_seven/$m" ]; then
          rm -rf ${i}/o_contrib_seven/$m
        fi
      done
      _ADMINER_VRN=4.8.1
      cd ${i}/o_contrib_seven
      if [ ! -e "${i}/o_contrib_seven/adminer/adminer/adminer-${_ADMINER_VRN}-mysql.php" ]; then
        rm -rf ${i}/o_contrib_seven/adminer
        get_dev_contrib "adminer_bundle-7.x-1.2.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/advagg" ]; then
        get_dev_contrib "advagg-7.x-2.36.tar.gz"
      fi
      if [ ! -e "${i}/o_contrib_seven/autoslave/patches/update-pdo-7.22.patch" ]; then
        rm -rf ${i}/o_contrib_seven/autoslave
        get_dev_contrib "autoslave-7.x-1.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/boost" ]; then
        get_dev_contrib "boost-7.x-1.2.tar.gz"
      fi
      if [ ! -e "${i}/o_contrib_seven/cache_consistent/3010585-cache-consistent-php72-2.patch" ]; then
        rm -rf ${i}/o_contrib_seven/cache_consistent
        get_dev_contrib "cache_consistent-7.x-2.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/cdn" ]; then
        get_dev_contrib "cdn-7.x-2.10.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/display_cache" ]; then
        get_dev_contrib "display_cache-7.x-1.3.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/entity_print" ]; then
        get_dev_contrib "entity_print-7.x-1.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/entitycache" ]; then
        get_dev_contrib "entitycache-7.x-1.7.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/file_resup" ]; then
        get_dev_contrib "file_resup-7.x-1.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/force_password_change" ]; then
        get_dev_contrib "force_password_change-7.x-2.2.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/fpa" ]; then
        get_dev_contrib "fpa-7.x-2.6.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/httprl" ]; then
        get_dev_contrib "httprl-7.x-1.14.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/js" ]; then
        get_dev_contrib "js-7.x-2.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/panels_content_cache" ]; then
        get_dev_contrib "panels_content_cache-7.x-1.4.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/session_expire" ]; then
        get_dev_contrib "session_expire-7.x-1.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/speedy" ]; then
        get_dev_contrib "speedy-7.x-1.34.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/taxonomy_edge" ]; then
        get_dev_contrib "taxonomy_edge-7.x-1.9.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/views_accelerator" ]; then
        get_dev_contrib "views_accelerator-7.x-1.0-beta1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/views_cache_bully" ]; then
        get_dev_contrib "views_cache_bully-7.x-3.1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/views_content_cache" ]; then
        get_dev_contrib "views_content_cache-7.x-3.0-alpha3.tar.gz"
      fi
      if [ ! -e "${i}/o_contrib_seven/entitycache/includes/entitycache.node.inc" ]; then
        rm -rf ${i}/o_contrib_seven/entitycache
        get_dev_contrib "entitycache-7.x-1.7.tar.gz"
      fi
      if [ -d "${i}/o_contrib_seven/expire" ] \
        || [ -d "${i}/o_contrib_seven/purge" ]; then
        rm -rf ${i}/o_contrib_seven/expire
        rm -rf ${i}/o_contrib_seven/purge
      fi
      if [ -d "${i}/o_contrib_seven/redis" ]; then
        rm -rf ${i}/o_contrib_seven/redis
      fi
      if [ -d "${i}/o_contrib_seven/redis_edge" ]; then
        rm -rf ${i}/o_contrib_seven/redis_edge
      fi
      if [ -L "${i}/o_contrib_seven/redis" ]; then
        rm -f ${i}/o_contrib_seven/redis
      fi
      if [ -e "${_D}/000/modules/redis_edge" ] \
        && [ ! -L "${i}/o_contrib_seven/redis_edge" ]; then
        ln -sfn ${_D}/000/modules/redis_edge ${i}/o_contrib_seven/redis_edge
      fi
      find ${i}/o_contrib_seven -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_seven -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_seven/update-${_X_SE}-${_X_VERSION}.info
    fi
  done
  cd
}

#
# Update o_contrib_eight.
satellite_o_contrib_eight_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_o_contrib_eight_update_global"
    debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_eight" ] \
      && [ ! -e "${i}/o_contrib_eight/update-${_X_SE}-${_X_VERSION}.info" ]; then
      _FORCE_UP_EIGHT=YES
    elif [ -e "${i}/o_contrib_eight" ] \
      && [ ! -e "${_D}/000/modules/redis_eight" ]; then
      _FORCE_UP_EIGHT=YES
    elif [ -e "${i}/o_contrib_eight" ] \
      && [ ! -L "${i}/o_contrib_eight/redis_eight" ]; then
      _FORCE_UP_EIGHT=YES
    elif [ -e "${i}/o_contrib_eight" ] \
      && [ ! -L "${i}/o_contrib_eight/redis_compr" ]; then
      _FORCE_UP_EIGHT=YES
    else
      _FORCE_UP_EIGHT=NO
    fi
    if [ "${_FORCE_UP_EIGHT}" = "YES" ] \
      && [ -e "${i}/o_contrib_eight" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_eight/$m" ]; then
          rm -rf ${i}/o_contrib_eight/$m
        fi
      done
      cd ${i}/o_contrib_eight
      if [ -d "${i}/o_contrib_eight/redis_eight" ]; then
        rm -rf ${i}/o_contrib_eight/redis_eight
      fi
      if [ -e "${_D}/000/modules/redis_eight" ] \
        && [ ! -L "${i}/o_contrib_eight/redis_eight" ]; then
        ln -sfn ${_D}/000/modules/redis_eight ${i}/o_contrib_eight/redis_eight
      fi
      if [ -e "${_D}/000/modules/redis_compr" ] \
        && [ ! -L "${i}/o_contrib_eight/redis_compr" ]; then
        ln -sfn ${_D}/000/modules/redis_compr ${i}/o_contrib_eight/redis_compr
      fi
      find ${i}/o_contrib_eight -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_eight -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_eight/update-${_X_SE}-${_X_VERSION}.info
    fi
  done
  cd
}


#
# Update o_contrib_nine.
satellite_o_contrib_nine_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_o_contrib_nine_update_global"
    debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_nine" ] \
      && [ ! -e "${i}/o_contrib_nine/update-${_X_SE}-${_X_VERSION}.info" ]; then
      _FORCE_UP_NINE=YES
    elif [ -e "${i}/o_contrib_nine" ] \
      && [ ! -L "${i}/o_contrib_nine/redis_nine_ten" ]; then
      _FORCE_UP_NINE=YES
    else
      _FORCE_UP_NINE=NO
    fi
    if [ "${_FORCE_UP_NINE}" = "YES" ] \
      && [ -e "${i}/o_contrib_nine" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_nine/$m" ]; then
          rm -rf ${i}/o_contrib_nine/$m
        fi
      done
      cd ${i}/o_contrib_nine
      if [ -d "${i}/o_contrib_nine/redis_eight" ]; then
        rm -rf ${i}/o_contrib_nine/redis_eight
      fi
      if [ -e "${_D}/000/modules/redis_nine_ten" ] \
        && [ ! -L "${i}/o_contrib_nine/redis_nine_ten" ]; then
        ln -sfn ${_D}/000/modules/redis_nine_ten ${i}/o_contrib_nine/redis_nine_ten
      fi
      if [ -e "${_D}/000/modules/redis_compr" ] \
        && [ ! -L "${i}/o_contrib_nine/redis_compr" ]; then
        ln -sfn ${_D}/000/modules/redis_compr ${i}/o_contrib_nine/redis_compr
      fi
      find ${i}/o_contrib_nine -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_nine -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_nine/update-${_X_SE}-${_X_VERSION}.info
    fi
  done
  cd
}


#
# Update o_contrib_ten.
satellite_o_contrib_ten_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_o_contrib_ten_update_global"
    debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_ten" ] \
      && [ ! -e "${i}/o_contrib_ten/update-${_X_SE}-${_X_VERSION}.info" ]; then
      _FORCE_UP_TEN=YES
    elif [ -e "${i}/o_contrib_ten" ] \
      && [ ! -L "${i}/o_contrib_ten/redis_nine_ten" ]; then
      _FORCE_UP_TEN=YES
    else
      _FORCE_UP_TEN=NO
    fi
    if [ "${_FORCE_UP_TEN}" = "YES" ] \
      && [ -e "${i}/o_contrib_ten" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_ten/$m" ]; then
          rm -rf ${i}/o_contrib_ten/$m
        fi
      done
      cd ${i}/o_contrib_ten
      if [ -d "${i}/o_contrib_ten/redis_compr" ]; then
        rm -rf ${i}/o_contrib_ten/redis_compr
      fi
      if [ -d "${i}/o_contrib_ten/redis_eight" ]; then
        rm -rf ${i}/o_contrib_ten/redis_eight
      fi
      if [ -e "${_D}/000/modules/redis_nine_ten" ] \
        && [ ! -L "${i}/o_contrib_ten/redis_nine_ten" ]; then
        ln -sfn ${_D}/000/modules/redis_nine_ten ${i}/o_contrib_ten/redis_nine_ten
      fi
      find ${i}/o_contrib_ten -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_ten -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_ten/update-${_X_SE}-${_X_VERSION}.info
    fi
  done
  cd
}


#
# Download o_contrib_ten.
satellite_download_o_contrib_ten() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_download_o_contrib_ten"
    debug_proc
  fi
  touch update-${_X_SE}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Downloading o_contrib_ten modules..."
  fi
  get_dev_contrib "robotstxt-8.x-1.5.tar.gz"
  get_dev_contrib "readonlymode-8.x-1.2.tar.gz"
  if [ ! -e "${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_nine_ten
    get_dev_contrib "redis_nine_ten-${_REDIS_T_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_X_SE}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}


#
# Download o_contrib_nine.
satellite_download_o_contrib_nine() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_download_o_contrib_nine"
    debug_proc
  fi
  touch update-${_X_SE}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Downloading o_contrib_nine modules..."
  fi
  get_dev_contrib "robotstxt-8.x-1.5.tar.gz"
  get_dev_contrib "readonlymode-8.x-1.2.tar.gz"
  if [ ! -e "${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_nine_ten
    get_dev_contrib "redis_nine_ten-${_REDIS_T_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_X_SE}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_compr
    get_dev_contrib "redis_compr-${_REDIS_C_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_X_SE}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}


#
# Download o_contrib_eight.
satellite_download_o_contrib_eight() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_download_o_contrib_eight"
    debug_proc
  fi
  touch update-${_X_SE}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Downloading o_contrib_eight modules..."
  fi
  get_dev_contrib "robotstxt-8.x-1.4.tar.gz"
  get_dev_contrib "readonlymode-8.x-1.2.tar.gz"
  if [ ! -e "${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_eight
    get_dev_contrib "redis_eight-${_REDIS_N_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_X_SE}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_compr
    get_dev_contrib "redis_compr-${_REDIS_C_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_X_SE}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}


#
# Download o_contrib_seven.
satellite_download_o_contrib_seven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_download_o_contrib_seven"
    debug_proc
  fi
  touch update-${_X_SE}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Downloading o_contrib_seven modules..."
  fi
  get_dev_contrib "admin-7.x-2.0-beta3.tar.gz"
  get_dev_contrib "adminer_bundle-7.x-1.2.tar.gz"
  # get_dev_contrib "adminer-7.x-1.2.tar.gz"
  # curl ${crlGet} "https://github.com/vrana/adminer/releases/download/v${_ADMINER_VRN}/adminer-${_ADMINER_VRN}-mysql.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/adminer-${_ADMINER_VRN}-mysql.php"
  # curl ${crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/designs/nette/adminer.css" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/styles/adminer.css"
  # curl ${crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/plugin.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/plugin.php"
  # curl ${crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/enum-option.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/enum-option.php"
  # curl ${crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/edit-textarea.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/edit-textarea.php"
  # curl ${crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/version-noverify.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/version-noverify.php"
  # curl ${crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/frames.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/frames.php"
  get_dev_contrib "advagg-7.x-2.36.tar.gz"
  get_dev_contrib "autoslave-7.x-1.x-dev.tar.gz"
  get_dev_contrib "blockcache_alter-7.x-1.1.tar.gz"
  get_dev_contrib "boost-7.x-1.2.tar.gz"
  get_dev_contrib "cache_consistent-7.x-2.x-dev.tar.gz"
  get_dev_contrib "cdn-7.x-2.10.tar.gz"
  get_dev_contrib "config_perms-7.x-2.2.tar.gz"
  get_dev_contrib "css_emimage-7.x-1.3.tar.gz"
  get_dev_contrib "display_cache-7.x-1.3.tar.gz"
  get_dev_contrib "entity_print-7.x-1.5.tar.gz"
  get_dev_contrib "entitycache-7.x-1.7.tar.gz"
  get_dev_contrib "esi-7.x-3.x-dev.tar.gz"
  get_dev_contrib "file_resup-7.x-1.5.tar.gz"
  get_dev_contrib "flood_control-7.x-1.1.tar.gz"
  get_dev_contrib "force_password_change-7.x-2.2.tar.gz"
  get_dev_contrib "fpa-7.x-2.6.tar.gz"
  get_dev_contrib "httprl-7.x-1.14.tar.gz"
  get_dev_contrib "js-7.x-2.5.tar.gz"
  get_dev_contrib "login_security-7.x-1.9.tar.gz"
  get_dev_contrib "nocurrent_pass-7.x-1.1.tar.gz"
  get_dev_contrib "panels_content_cache-7.x-1.4.tar.gz"
  get_dev_contrib "readonlymode-7.x-1.2.tar.gz"
  get_dev_contrib "reroute_email-7.x-1.4.tar.gz"
  get_dev_contrib "robotstxt-7.x-1.4.tar.gz"
  get_dev_contrib "securesite-7.x-2.0-beta3.tar.gz"
  get_dev_contrib "session_expire-7.x-1.x-dev.tar.gz"
  get_dev_contrib "site_verify-7.x-1.2.tar.gz"
  get_dev_contrib "speedy-7.x-1.34.tar.gz"
  get_dev_contrib "taxonomy_edge-7.x-1.9.tar.gz"
  get_dev_contrib "variable_clean-7.x-1.x-dev.tar.gz"
  get_dev_contrib "views_accelerator-7.x-1.0-beta1.tar.gz"
  get_dev_contrib "views_cache_bully-7.x-3.1.tar.gz"
  get_dev_contrib "views_content_cache-7.x-3.0-alpha3.tar.gz"
  get_dev_contrib "views404-7.x-1.0-beta1.tar.gz"
  rm -rf nginx_accel_redirect*
  rm -rf purge*
  rm -rf expire*
  find ./ -type d -exec chmod 0755 {} \; &> /dev/null
  find ./ -type f -exec chmod 0644 {} \; &> /dev/null
  touch ctrl-${_X_SE}-${_X_VERSION}
  if [ -L "./redis" ]; then
    rm -f redis
  fi
  if [ ! -L "./redis_edge" ]; then
    ln -sfn ${_D}/000/modules/redis_edge redis_edge
  fi
  if [ -e "${_D}/000/modules/redis" ]; then
    rm -rf ${_D}/000/modules/redis
  fi
  if [ ! -e "${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_edge
    get_dev_contrib "redis_edge-${_REDIS_L_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_X_SE}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}

#
# Download o_contrib_six.
satellite_download_o_contrib_six() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_download_o_contrib_six"
    debug_proc
  fi
  touch update-${_X_SE}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Downloading o_contrib modules..."
  fi
  get_dev_contrib "admin-6.x-2.0.tar.gz"
  get_dev_contrib "advagg-6.x-1.11.tar.gz"
  get_dev_contrib "blockcache_alter-6.x-1.6.tar.gz"
  get_dev_contrib "boost-6.x-1.22.tar.gz"
  get_dev_contrib "cdn-6.x-2.7.tar.gz"
  get_dev_contrib "config_perms-6.x-2.x-dev.tar.gz"
  get_dev_contrib "css_emimage-6.x-2.x-dev.tar.gz"
  get_dev_contrib "dbtuner-6.x-1.x-dev.tar.gz"
  get_dev_contrib "esi-6.x-2.x-dev.tar.gz"
  get_dev_contrib "force_password_change-6.x-3.4.tar.gz"
  get_dev_contrib "fpa-6.x-2.5.tar.gz"
  get_dev_contrib "httprl-6.x-1.14.tar.gz"
  get_dev_contrib "image-6.x-1.2.tar.gz"
  get_dev_contrib "js-6.x-1.3.tar.gz"
  get_dev_contrib "login_security-6.x-1.4.tar.gz"
  get_dev_contrib "panels_content_cache-6.x-1.0.tar.gz"
  get_dev_contrib "phpass-6.x-2.1.tar.gz"
  get_dev_contrib "private_upload-6.x-1.x-dev.tar.gz"
  get_dev_contrib "readonlymode-6.x-1.2.tar.gz"
  get_dev_contrib "reroute_email-6.x-1.3.tar.gz"
  get_dev_contrib "robotstxt-6.x-1.4.tar.gz"
  get_dev_contrib "securesite-6.x-2.4.tar.gz"
  get_dev_contrib "session_expire-6.x-1.x-dev.tar.gz"
  get_dev_contrib "site_verify-6.x-1.0.tar.gz"
  get_dev_contrib "taxonomy_edge-6.x-1.7.tar.gz"
  get_dev_contrib "variable_clean-6.x-1.x-dev.tar.gz"
  get_dev_contrib "views_cache_bully-6.x-3.1.tar.gz"
  get_dev_contrib "views_content_cache-6.x-2.x-dev.tar.gz"
  get_dev_contrib "views404-6.x-1.x-dev.tar.gz"
  rm -rf nginx_accel_redirect*
  rm -rf purge*
  rm -rf expire*
  find ./ -type d -exec chmod 0755 {} \; &> /dev/null
  find ./ -type f -exec chmod 0644 {} \; &> /dev/null
  touch ctrl-${_X_SE}-${_X_VERSION}
  if [ -L "./redis" ]; then
    rm -f redis
  fi
  if [ ! -L "./redis_edge" ]; then
    ln -sfn ${_D}/000/modules/redis_edge redis_edge
  fi
  if [ ! -L "./cache_backport" ]; then
    ln -sfn ${_D}/000/modules/cache_backport cache_backport
  fi
  if [ ! -e "${_D}/000/modules/cache_backport/update-${_X_SE}-${_X_VERSION}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/cache_backport
    get_dev_contrib "cache_backport-6.x-1.0-rc4.tar.gz"
    echo update > cache_backport/update-${_X_SE}-${_X_VERSION}.info
  fi
  if [ -e "${_D}/000/modules/redis" ]; then
    rm -rf ${_D}/000/modules/redis
  fi
  if [ ! -e "${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_edge
    get_dev_contrib "redis_edge-${_REDIS_L_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_X_SE}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}

#
# Upgrade o_contrib.
satellite_check_fix_o_contrib() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_check_fix_o_contrib"
    debug_proc
  fi
  if [ -e "${_CORE}/o_contrib_ten" ]; then
    if [ ! -d "${_CORE}/o_contrib_ten/redis_nine_ten" ] \
      || [ -e "${_CORE}/o_contrib_ten/advagg" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      msg "${_STATUS} A: Running o_contrib_ten forced upgrade..."
      cd ${_CORE}/o_contrib_ten
      rm -rf ${_CORE}/o_contrib_ten/*
      satellite_download_o_contrib_ten
      cd ${_CORE}/o_contrib_ten
    fi
  fi
  if [ -e "${_CORE}/o_contrib_nine" ]; then
    if [ ! -d "${_CORE}/o_contrib_nine/redis_nine_ten" ] \
      || [ -e "${_CORE}/o_contrib_nine/advagg" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      msg "${_STATUS} A: Running o_contrib_nine forced upgrade..."
      cd ${_CORE}/o_contrib_nine
      rm -rf ${_CORE}/o_contrib_nine/*
      satellite_download_o_contrib_nine
      cd ${_CORE}/o_contrib_nine
    fi
  fi
  if [ -e "${_CORE}/o_contrib_eight" ]; then
    if [ ! -d "${_CORE}/o_contrib_eight/redis_compr" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      msg "${_STATUS} A: Running o_contrib_eight forced upgrade..."
      cd ${_CORE}/o_contrib_eight
      rm -rf ${_CORE}/o_contrib_eight/*
      satellite_download_o_contrib_eight
      cd ${_CORE}/o_contrib_eight
    fi
  fi
  if [ -e "${_CORE}/o_contrib_seven" ]; then
    if [ ! -d "${_CORE}/o_contrib_seven/robotstxt" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      msg "${_STATUS} A: Running o_contrib_seven forced upgrade..."
      cd ${_CORE}/o_contrib_seven
      rm -rf ${_CORE}/o_contrib_seven/*
      satellite_download_o_contrib_seven
      cd ${_CORE}/o_contrib_seven
    fi
  fi
  if [ -e "${_CORE}/o_contrib" ]; then
    if [ ! -d "${_CORE}/o_contrib/robotstxt" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      msg "${_STATUS} A: Running o_contrib forced upgrade..."
      cd ${_CORE}/o_contrib
      rm -rf ${_CORE}/o_contrib/*
      satellite_download_o_contrib_six
      cd ${_CORE}/o_contrib
    fi
  fi
  if [ ! -e "${_D}/000/modules/cache_backport/update-${_X_SE}-${_X_VERSION}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/cache_backport
    get_dev_contrib "cache_backport-6.x-1.0-rc4.tar.gz"
    echo update > cache_backport/update-${_X_SE}-${_X_VERSION}.info
  fi
  if [ -e "${_D}/000/modules/redis" ]; then
    rm -rf ${_D}/000/modules/redis
  fi
  if [ ! -e "${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_edge
    get_dev_contrib "redis_edge-${_REDIS_L_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_X_SE}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_eight
    get_dev_contrib "redis_eight-${_REDIS_N_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_X_SE}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_compr
    get_dev_contrib "redis_compr-${_REDIS_C_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_X_SE}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_X_SE}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_nine_ten
    get_dev_contrib "redis_nine_ten-${_REDIS_T_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_X_SE}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}

#
# Manage o_contrib.
satellite_manage_o_contrib() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_manage_o_contrib"
    debug_proc
  fi
  if [ ! -e "${_CORE}/o_contrib_ten" ]; then
    mkdir -p ${_CORE}/o_contrib_ten
    cd ${_CORE}/o_contrib_ten
    satellite_download_o_contrib_ten
    cd ${_CORE}/o_contrib_ten
  fi
  if [ ! -e "${_CORE}/o_contrib_nine" ]; then
    mkdir -p ${_CORE}/o_contrib_nine
    cd ${_CORE}/o_contrib_nine
    satellite_download_o_contrib_nine
    cd ${_CORE}/o_contrib_nine
  fi
  if [ ! -e "${_CORE}/o_contrib_eight" ]; then
    mkdir -p ${_CORE}/o_contrib_eight
    cd ${_CORE}/o_contrib_eight
    satellite_download_o_contrib_eight
    cd ${_CORE}/o_contrib_eight
  fi
  if [ ! -e "${_CORE}/o_contrib_seven" ]; then
    mkdir -p ${_CORE}/o_contrib_seven
    cd ${_CORE}/o_contrib_seven
    satellite_download_o_contrib_seven
    cd ${_CORE}/o_contrib_seven
  fi
  if [ ! -e "${_CORE}/o_contrib" ]; then
    mkdir -p ${_CORE}/o_contrib
    cd ${_CORE}/o_contrib
    satellite_download_o_contrib_six
    cd ${_CORE}/o_contrib
  fi
  mkdir -p ${_D}/000/modules
  rm -f ${_D}/000/modules/o_contrib_ten
  ln -s ${_CORE}/o_contrib_ten ${_D}/000/modules/o_contrib_ten
  rm -f ${_D}/000/modules/o_contrib_nine
  ln -s ${_CORE}/o_contrib_nine ${_D}/000/modules/o_contrib_nine
  rm -f ${_D}/000/modules/o_contrib_eight
  ln -s ${_CORE}/o_contrib_eight ${_D}/000/modules/o_contrib_eight
  rm -f ${_D}/000/modules/o_contrib_seven
  ln -s ${_CORE}/o_contrib_seven ${_D}/000/modules/o_contrib_seven
  rm -f ${_D}/000/modules/o_contrib
  ln -s ${_CORE}/o_contrib ${_D}/000/modules/o_contrib
  if [ "${_STATUS}" != "INIT" ]; then
    satellite_check_fix_o_contrib
  fi
}

satellite_hot_sauce_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_hot_sauce_check"
    debug_proc
  fi
  mNewC="Shared platforms code v.${_ALL_DISTRO} (new) will be created"
  mLstC="Shared platforms code v.${_LAST_ALL} will be used"
  if [ "${_HOT_SAUCE}" = "NO" ]; then
    _CORE="${_D}/${_LAST_ALL}"
    _THIS_CORE="${_LAST_ALL}"
    if [ "${_USE_CURRENT}" = "YES" ] \
      && [ -e "${_D}/000/core-v-${_SMALLCORE6_V}.txt" ] \
      && [ -e "${_D}/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      msg "${_STATUS} A: ${mLstC}"
    elif [ "${_USE_CURRENT}" = "NO" ] \
      || [ ! -e "${_D}/000/core-v-${_SMALLCORE6_V}.txt" ] \
      || [ ! -e "${_D}/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      _CORE="${_D}/${_ALL_DISTRO}"
      _THIS_CORE="${_ALL_DISTRO}"
      msg "${_STATUS} A: ${mNewC}"
      sed -i "s/^_USE_CURRENT=.*/_USE_CURRENT=NO/g" ${vBs}/${filIncO}
      wait
    else
      msg "${_STATUS} A: ${mLstC}"
    fi
  else
    _CORE="${_D}/${_ALL_DISTRO}"
    _THIS_CORE="${_ALL_DISTRO}"
    msg "${_STATUS} A: ${mNewC}"
  fi
}

satellite_add_user_dirs() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_add_user_dirs"
    debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Creating directories with correct permissions"
  fi
  mkdir -p /data/u
  mkdir -p /data/disk
  mkdir -p /data/conf
  chown root:root /data &> /dev/null
  chown root:root /data/disk &> /dev/null
  if [ ! -d "${_ROOT}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding user..."
    fi
    find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
    adduser --system --home ${_ROOT} --ingroup ${_USRG} ${_USER} &> /dev/null
    adduser ${_USER} ${_WEBG} &> /dev/null
  fi
  chown -R ${_USER}:${_USRG} /opt/tmp &> /dev/null
  chown -R ${_USER}:${_USRG} /data/conf &> /dev/null
}

satellite_prepare_child_scripts() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_prepare_child_scripts"
    debug_proc
  fi
  chmod 0711 ${_ROOT}
  cd ${_ROOT}
  AegirSetupB="${bldPth}/aegir/scripts/AegirSetupB.sh.txt"
  AegirSetupC="${bldPth}/aegir/scripts/AegirSetupC.sh.txt"
  chown ${_USER}:${_USRG} ${AegirSetupB} &> /dev/null
  chown ${_USER}:${_USRG} ${AegirSetupC} &> /dev/null
}

#
# Generate provision backend db_passwd.
provision_backend_dbpass_generate() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: provision_backend_dbpass_generate"
    debug_proc
  fi
  _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
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
      && [ "${_STRONG_PASSWORDS}" -gt "32" ]; then
      _PWD_CHARS="${_STRONG_PASSWORDS}"
    else
      _PWD_CHARS=32
    fi
    if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt "128" ]; then
      _PWD_CHARS=128
    fi
  fi
  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt "32" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
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
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>&1)
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    isPythonTwo=$(which python2 2>&1)
    isPythonThree=$(which python3 2>&1)
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    if [ -x "${isPythonThree}" ]; then
      _ENC_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${_ESC_PASS}'''))")
    elif [ -x "${isPythonTwo}" ]; then
      _ENC_PASS=$(python2 -c "import urllib; print urllib.quote('''${_ESC_PASS}''')")
    fi
    _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
  fi
  if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt "9" ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
      _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
      _ESC_PASS=$(sanitize_string "${_ESC_PASS}" 2>&1)
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>&1)
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _ENC_PASS="${_ESC_PASS}"
  fi

  _L_SYS="${_ROOT}/.${_USER}.pass.txt"
  echo "${_ESC_PASS}" > ${_L_SYS}
  chown ${_USER}:${_USRG} ${_L_SYS}
  chmod 0600 ${_L_SYS}

  _L_SYS_PHP="${_ROOT}/.${_USER}.pass.php"
  echo "<?php" > ${_L_SYS_PHP}
  echo "\$oct_db_user = \"${_USER}\";" >> ${_L_SYS_PHP}
  echo "\$oct_db_pass = \"${_ESC_PASS}\";" >> ${_L_SYS_PHP}
  echo "\$oct_db_host = \"${_THIS_DB_HOST}\";" >> ${_L_SYS_PHP}
  echo "\$oct_db_port = \"${_THIS_DB_PORT}\";" >> ${_L_SYS_PHP}
  echo "\$oct_db_dirs = \"/data/disk/${_USER}/backups\";" >> ${_L_SYS_PHP}
  chown ${_USER}:${_USRG} ${_L_SYS_PHP}
  chmod 0600 ${_L_SYS_PHP}

  _ESC="*.*"

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _USE_AEGIR_HOST=$(uname -n 2>&1)
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    _USE_DB_USER="${_USER}"
  else
    _USE_AEGIR_HOST=$(uname -n 2>&1)
    _SQL_CONNECT="${_THIS_DB_HOST}"
    _USE_DB_USER=aegir_root
  fi
  if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
    _USE_AEGIR_HOST=$(uname -n 2>&1)
    _SQL_CONNECT=localhost
  fi
  find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"

  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysqladmin -u root flush-privileges &> /dev/null
  fi

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL14 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
        _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
        mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
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
      ###
      ###
      # if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
      #   _ROOT_SQL_PASWD=$(cat /root/.my.cluster_root_pwd.txt 2>&1)
      #   _ROOT_SQL_PASWD=$(echo -n ${_ROOT_SQL_PASWD} | tr -d "\n" 2>&1)
      # elif [ -e "/root/.my.pass.txt" ]; then
      #   _ROOT_SQL_PASWD=$(cat /root/.my.pass.tx 2>&1)
      #   _ROOT_SQL_PASWD=$(echo -n ${_ROOT_SQL_PASWD} | tr -d "\n" 2>&1)
      # fi
      # if [ -e "/root/.my.cluster_write_node.txt" ]; then
      #   _CL_WR_NODE=$(cat /root/.my.cluster_write_node.txt 2>&1)
      #   _CL_WR_NODE=$(echo -n ${_CL_WR_NODE} | tr -d "\n" 2>&1)
      #   _SQL_CONNECT="${_CL_WR_NODE}"
      #   _THIS_DB_PORT="3306"
      # fi
      ### -p${_ROOT_SQL_PASWD}
      ### [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL14CR -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      ###
      ###
      mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    else
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL15 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
        if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
          _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
          _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
          mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
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
      fi
    fi
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysqladmin -u root flush-privileges &> /dev/null
  fi
}

#
# Sync provision backend db_passwd.
provision_backend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: provision_backend_dbpass_sync"
    debug_proc
  fi
  _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
  find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  _RESOLVEIP="${_LOC_IP}"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Syncing provision backend db_passwd..."
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _L_SYS="${_ROOT}/.${_USER}.pass.txt"
  mv -f ${_L_SYS} ${_L_SYS}-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
  _L_SYS_PHP="${_ROOT}/.${_USER}.pass.php"
  mv -f ${_L_SYS_PHP} ${_L_SYS_PHP}-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
  provision_backend_dbpass_generate
  if [ ! -z "${_ESC_PASS}" ] || [ ! -z "${_ENC_PASS}" ]; then
    su -s /bin/bash - ${_USER} -c "${_DRUSHCMD} @hostmaster \
      sqlq \"UPDATE hosting_db_server SET db_passwd='${_ESC_PASS}' \
      WHERE db_user='${_USER}'\"" &> /dev/null
    wait
    _ESC="*.*"
    _USE_DB_USER="${_USER}"
    _USE_AEGIR_HOST="$(uname -n 2>&1)"
    find_correct_ip
    _USE_RESOLVEIP="${_LOC_IP}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL16 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _PROXYSQL_PASSWORD=$(cat /root/.my.proxysql_adm_pwd.txt 2>&1)
      _PROXYSQL_PASSWORD=$(echo -n ${_PROXYSQL_PASSWORD} | tr -d "\n" 2>&1)
      mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
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
    sed -i \
      "s/mysql:\/\/${_USER}:.*/mysql:\/\/${_USER}:${_ENC_PASS}@${_SQL_CONNECT}',/g" \
      ${_ROOT}/.drush/server_*.alias.drushrc.php &> /dev/null
    wait
  else
    msg "CRIT: _ESC_PASS empty or not generated"
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysqladmin -u root flush-privileges &> /dev/null
  fi
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} cc drush" &> /dev/null
  wait
  rm -rf ${_ROOT}/.tmp/cache
  if [ -e "${_ROOT}/.drush/server_localhost.alias.drushrc.php" ]; then
    su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster \
      hosting-task @server_localhost verify --force" &> /dev/null
  else
    su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster \
      hosting-task @server_master verify --force" &> /dev/null
  fi
  wait
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Running hosting-dispatch/hosting-tasks..."
  fi
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-dispatch" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-tasks --force" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-tasks --force" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-tasks --force" &> /dev/null
  wait
}

#
# Sync hostmaster frontend db_passwd.
hostmaster_frontend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: hostmaster_frontend_dbpass_sync"
    debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: Syncing hostmaster frontend db_passwd..."
  fi
  _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _THIS_HM_SPTH=$(cat ${_ROOT}/.drush/hostmaster.alias.drushrc.php \
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
    _ESC="*.*"
    _USE_DB_USER="${_THIS_HM_DBUR}"
    _USE_AEGIR_HOST="$(uname -n 2>&1)"
    find_correct_ip
    _USE_RESOLVEIP="${_LOC_IP}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL17 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
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
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysqladmin -u root flush-privileges &> /dev/null
  fi
}

satellite_run_pre_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_run_pre_install"
    debug_proc
  fi
  _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
  _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
  find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  _RESOLVEIP="${_LOC_IP}"
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
      _SQL_CONNECT=127.0.0.1
      _THIS_DB_PORT=6033
      mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-hosts &> /dev/null
    else
      mysqladmin -u root flush-hosts &> /dev/null
    fi
    provision_backend_dbpass_generate
    echo "${_USER} ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
    SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership lock-local-drush-permissions)
    for SCRIPT in ${SCRIPTS[@]}; do
      echo "${_USER} ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" >> /etc/sudoers.d/${SCRIPT}
      chmod 0440 /etc/sudoers.d/${SCRIPT}
    done
  else
    _VAR_IF_PRESENT=$(grep "${_USER} ALL=NOPASSWD" /etc/sudoers 2>&1)
    if [[ ! "${_VAR_IF_PRESENT}" =~ "${_USER} ALL=NOPASSWD" ]]; then
      echo "${_USER} ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
    fi
    SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership lock-local-drush-permissions)
    for SCRIPT in ${SCRIPTS[@]}; do
      _VAR_IF_PRESENT=$(grep "${_USER} ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" /etc/sudoers.d/${SCRIPT} 2>&1)
      if [[ ! "${_VAR_IF_PRESENT}" =~ "${_USER} ALL=NOPASSWD" ]]; then
        echo "${_USER} ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" >> /etc/sudoers.d/${SCRIPT}
        chmod 0440 /etc/sudoers.d/${SCRIPT}
      fi
    done
    if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
      _SQL_CONNECT=127.0.0.1
      _THIS_DB_PORT=6033
      mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-hosts &> /dev/null
    else
      mysqladmin -u root flush-hosts &> /dev/null
    fi
    _RST=$(syncpass fix ${_USER} 2>&1)
    provision_backend_dbpass_sync
  fi
  cd ${_ROOT}
}

#
# Download for Drush Make Local build.
satellite_download_for_local_build() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_download_for_local_build"
    debug_proc
  fi
  mL="/opt/tmp/make_local"
  if [ ! -e "${mL}/hosting/hosting.info" ] \
    || [ ! -e "${mL}/hosting_custom_settings/hosting_custom_settings.info" ]; then
    rm -rf ${mL}
    mkdir -p ${mL}
    cd ${mL}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Downloading hostmaster modules..."
    fi
    ### Drupal Core
    get_dev_ext "drupal-${_SMALLCORE7_V}.tar.gz"
    mv -f ${mL}/drupal-${_SMALLCORE7_V} ${mL}/drupal
    ### Aegir Core
      ${gCb} 5.x-${tRee} ${gitHub}/hostmaster.git    &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting.git       &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/eldir.git         &> /dev/null
    ### Aegir Golden + BOA Settings
      ${gCb} 5.x-${tRee} ${gitHub}/aegir_objects.git                  &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_civicrm.git                &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_custom_settings.git        &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_deploy.git                 &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_git.git                    &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_le.git                     &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_remote_import.git          &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_site_backup_manager.git    &> /dev/null
      ${gCb} 5.x-${tRee} ${gitHub}/hosting_tasks_extra.git            &> /dev/null
      rm -rf */.git
    ### Aegir Drupal Contrib
    get_dev_stc "admin_menu-7.x-3.0-rc7.tar.gz"
    get_dev_stc "betterlogin-7.x-1.5.tar.gz"
    get_dev_stc "ctools-7.x-1.21.tar.gz"
    get_dev_stc "entity-7.x-1.11.tar.gz"
    get_dev_stc "libraries-7.x-2.5.tar.gz"
    get_dev_stc "module_filter-7.x-2.3.tar.gz"
    get_dev_stc "openidadmin-7.x-1.0.tar.gz"
    get_dev_stc "overlay_paths-7.x-1.3.tar.gz"
    get_dev_stc "r4032login-7.x-1.8.tar.gz"
    get_dev_stc "tfa_basic-7.x-1.1.tar.gz"
    get_dev_stc "tfa-7.x-2.1.tar.gz"
    get_dev_stc "timeago-7.x-2.3.tar.gz"
    get_dev_stc "views_bulk_operations-7.x-3.7.tar.gz"
    get_dev_stc "views-7.x-3.29.tar.gz"
    ### BOA Drupal Contrib
    get_dev_stc "features_extra-7.x-1.0.tar.gz"
    get_dev_stc "features-7.x-2.15.tar.gz"
    get_dev_stc "idna_convert-7.x-1.0.tar.gz"
    get_dev_stc "revision_deletion-7.x-1.3.tar.gz"
    get_dev_stc "strongarm-7.x-2.0.tar.gz"
    get_dev_stc "userprotect-7.x-1.3.tar.gz"
  fi
  find ${mL} -type d -exec chmod 0755 {} \; &> /dev/null
  find ${mL} -type f -exec chmod 0644 {} \; &> /dev/null
  chown -R root:root ${mL}
}

#
# Run child B.
satellite_run_child_b() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_run_child_b"
    debug_proc
  fi
  find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Switching user and running AegirSetupB..."
    fi
    rm -f /opt/tmp/testecho*
    chown root:${_USRG} /data/u &> /dev/null
    chmod 0771 /data/u &> /dev/null
    su -s /bin/bash - ${_USER} -c "/bin/bash ${AegirSetupB} ${_USER}"
    wait
    if [ -e "/opt/tmp/status-AegirSetupB-FAIL" ]; then
      msg "${_STATUS} A: FATAL ERROR: AegirSetupB installer failed"
      msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
      touch /opt/tmp/status-AegirSetupA-FAIL
      exit 1
    fi
    _U_HD="${_ROOT}/.drush"
    chattr +i ${_U_HD}/php.ini
    chmod 0700 /data/u &> /dev/null
    chown root:root /data/u &> /dev/null
    msg "${_STATUS} A: Aegir Satellite Instance installed"
  else
    if [ "${_PLATFORMS_ONLY}" = "YES" ]; then
      msg "${_STATUS} A: Satellite Instance Hostmaster upgrade skipped"
    else
      if [ ! -d "${_ROOT}/.drush/sys/provision/http" ]; then
        mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
        rm -rf ${_ROOT}/.drush/provision
        rm -rf ${_ROOT}/.drush/sys/provision
        ${gCb} ${_BRANCH_PRN} ${gitHub}/provision.git \
          ${_ROOT}/.drush/sys/provision &> /dev/null
        sed -i "s/files.aegir.cc/${_USE_MIR}/g" \
          ${_ROOT}/.drush/sys/provision/aegir.make &> /dev/null
        wait
      fi
      rm -rf ${_ROOT}/.drush/drush_make
      rm -rf ${_ROOT}/.drush/sys/drush_make
      hostmaster_frontend_dbpass_sync
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "${_STATUS} A: Switching user and running AegirSetupB..."
      fi
      rm -f /opt/tmp/testecho*
      _THIS_HM_ROOT=$(cat ${_ROOT}/.drush/hostmaster.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _THIS_HM_SITE=$(cat ${_ROOT}/.drush/hostmaster.alias.drushrc.php \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _U_HD="${_ROOT}/.drush"
      chattr -i ${_U_HD}/php.ini
      chown -R ${_USER}:${_USRG} ${_ROOT}/.drush
      chown -R ${_USER}:${_USRG} ${_ROOT}/backups
      chown -R ${_USER}:${_USRG} ${_ROOT}/clients
      chown -R ${_USER}:${_USRG} ${_ROOT}/config
      chown -R ${_USER}:${_USRG} ${_ROOT}/tools
      chown -R ${_USER} ${_THIS_HM_ROOT}
      chown -R ${_USER}:${_WEBG} ${_THIS_HM_SITE}/files
      chmod -R 02775 ${_THIS_HM_SITE}/files
      chown root:${_USRG} /data/u &> /dev/null
      chmod 0771 /data/u &> /dev/null
      su -s /bin/bash - ${_USER} -c "/bin/bash ${AegirSetupB} ${_USER}"
      wait
      if [ -e "/opt/tmp/status-AegirSetupB-FAIL" ]; then
        msg "${_STATUS} A: FATAL ERROR: AegirSetupB installer failed"
        msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
        touch /opt/tmp/status-AegirSetupA-FAIL
        exit 1
      else
        chattr +i ${_U_HD}/php.ini
        mkdir -p ${_ROOT}/backups/system/old_hostmaster
        chmod 700 ${_ROOT}/backups/system/old_hostmaster
        chmod 700 ${_ROOT}/backups/system
        mv -f ${_ROOT}/backups/*host8* \
          ${_ROOT}/backups/system/old_hostmaster/ &> /dev/null
        mv -f ${_ROOT}/backups/*o8.io* \
          ${_ROOT}/backups/system/old_hostmaster/ &> /dev/null
        mv -f ${_ROOT}/backups/*boa.io* \
          ${_ROOT}/backups/system/old_hostmaster/ &> /dev/null
        mv -f ${_ROOT}/backups/*aegir.cc* \
          ${_ROOT}/backups/system/old_hostmaster/ &> /dev/null
        chmod 600 ${_ROOT}/backups/system/old_hostmaster/* &> /dev/null
        hostmaster_frontend_dbpass_sync
      fi
      su -s /bin/bash - ${_USER} -c "drush8 @hm rr" &> /dev/null
      wait
      chmod 0700 /data/u &> /dev/null
      chown root:root /data/u &> /dev/null
      msg "${_STATUS} A: Aegir Satellite Instance upgrade completed"
    fi
  fi
}

satellite_if_create_local_bin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_create_local_bin"
    debug_proc
  fi
  _L_BIN="${_ROOT}/bin"
  if [ ! -d "${_L_BIN}" ]; then
    mkdir -p ${_L_BIN}
    chown ${_USER}:${_USRG} ${_L_BIN}
    chmod 700 ${_L_BIN}
  fi
  if [ ! -L "${_L_BIN}/drush" ]; then
    ln -sfn ${_ROOT}/tools/drush/drush ${_L_BIN}/drush
  fi
}

#
# Run standard post-install.
satellite_run_post_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_run_post_install"
    debug_proc
  fi
  _LOCAL_STATUS="${_STATUS}"
  if [ -e "/run/aegir_upgrade.pid" ]; then
    _LOCAL_STATUS=INIT
  fi
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    if [ ! -e "${_ROOT}/config/${_USER}.nginx.conf" ]; then
      rm -f /var/aegir/config/server_master/nginx/platform.d/${_USER}.conf
      echo "include ${_ROOT}/config/server_master/nginx/vhost.d/*;" > \
        ${_ROOT}/config/${_USER}.nginx.conf
      ln -sfn ${_ROOT}/config/${_USER}.nginx.conf \
        /var/aegir/config/server_master/nginx/platform.d/${_USER}.conf
    fi
    chgrp -R ${_WEBG} ${_HM_ROOT}/sites/${_DOMAIN}/files
    chgrp ${_WEBG} ${_HM_ROOT}/sites/${_DOMAIN}/settings.php
    rm -rf ${_HM_ROOT}/profiles/default
    rm -rf ${_HM_ROOT}/themes/bluemarine
    rm -rf ${_HM_ROOT}/themes/chameleon
    rm -rf ${_HM_ROOT}/themes/pushbutton
    rm -rf ${_HM_ROOT}/scripts
    rm -f ${_HM_ROOT}/themes/README.txt
    rm -f ${_HM_ROOT}/*.txt
    mrun "service nginx reload" 2> /dev/null
    cd ${_HM_ROOT}
    cp -af /opt/tmp/boa/aegir/conf/tpl/robots.txt ./
    cd ${_ROOT}
  fi
}

#
# Set permissions for all.
satellite_set_permissions_for_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_set_permissions_for_all"
    debug_proc
  fi
  chmod 0755 ${_HM_ROOT} &> /dev/null
  find ${_ROOT}/config/server_master -type d -exec chmod 0700 {} \; &> /dev/null
  find ${_ROOT}/config/server_master -type f -exec chmod 0600 {} \; &> /dev/null
  chmod 0711 ${_ROOT}/config &> /dev/null
  chmod 0711 ${_ROOT}/config/includes &> /dev/null
  chmod 0750 ${_ROOT}/backups &> /dev/null
  chmod 0750 ${_ROOT}/clients &> /dev/null
  find ${_ROOT}/aegir/distro/*/profiles/* -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_ROOT}/aegir/distro/*/profiles/* -type f -exec chmod 0644 {} \; &> /dev/null
  find ${_ROOT}/aegir/distro/*/sites/all/* -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_ROOT}/aegir/distro/*/sites/all/* -type f -exec chmod 0644 {} \; &> /dev/null
  chown -R ${_USER}:${_USRG} ${_ROOT}/.drush &> /dev/null
  find ${_ROOT}/.drush -type d -exec chmod 0710 {} \; &> /dev/null
  find ${_ROOT}/.drush/usr -type d -exec chmod 0750 {} \; &> /dev/null
  find ${_ROOT}/.drush -type f -exec chmod 0640 {} \; &> /dev/null
  chmod 0440 ${_ROOT}/.drush/*.php &> /dev/null
  if [ ! -e "${_ROOT}/.drush/hm.alias.drushrc.php" ]; then
    cp -a ${_ROOT}/.drush/hostmaster.alias.drushrc.php ${_ROOT}/.drush/hm.alias.drushrc.php
    sed -i "s/\['hostmaster'\]/['hm']/g" ${_ROOT}/.drush/hm.alias.drushrc.php
  fi
  chmod 0400 ${_ROOT}/.drush/server_*.php &> /dev/null
  chmod 0400 ${_ROOT}/.drush/platform_*.php &> /dev/null
  chmod 0400 ${_ROOT}/.drush/hostmaster*.php &> /dev/null
  chmod 0400 ${_ROOT}/.drush/hm.alias.drushrc.php &> /dev/null
  chmod 0710 ${_ROOT}/.drush &> /dev/null
}

#
# Run child C.
satellite_run_child_c() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_run_child_c"
    debug_proc
  fi
  _LOCAL_STATUS="${_STATUS}"
  if [ -e "/run/aegir_upgrade.pid" ]; then
    _LOCAL_STATUS=INIT
  fi
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    _DIST_INSTALL=YES
    rm -f /opt/tmp/testecho*
    satellite_create_shared_dirs
    satellite_manage_o_contrib
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Switching user and running Platforms build"
    fi
    cd ${_ROOT}
    AegirSetupC="${bldPth}/aegir/scripts/AegirSetupC.sh.txt"
    su -s /bin/bash - ${_USER} -c "/bin/bash ${AegirSetupC} ${_USER}"
    wait
    if [ -e "/opt/tmp/status-AegirSetupC-FAIL" ]; then
      msg "${_STATUS} A: FATAL ERROR: AegirSetupC installer failed"
      msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
      touch /opt/tmp/status-AegirSetupA-FAIL
      exit 1
    fi
    if [ -e "/opt/tmp/status-AegirSetupC-runVerify" ]; then
      msg "${_STATUS} A: Platforms installed"
    fi
  else
    if [ "${_HM_ONLY}" = "YES" ]; then
      _DIST_INSTALL=NO
    else
      echo " "
      if prompt_yes_no "Do you want to install some ready to use platforms?"; then
        true
        _DIST_INSTALL=YES
        rm -f /opt/tmp/testecho*
        satellite_create_shared_dirs
        satellite_manage_o_contrib
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "${_STATUS} A: Switching user and running Platforms build"
        fi
        cd ${_ROOT}
        AegirSetupC="${bldPth}/aegir/scripts/AegirSetupC.sh.txt"
        su -s /bin/bash - ${_USER} -c "/bin/bash ${AegirSetupC} ${_USER}"
        wait
        if [ -e "/opt/tmp/status-AegirSetupC-FAIL" ]; then
          msg "${_STATUS} A: FATAL ERROR: AegirSetupC installer failed"
          msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
          touch /opt/tmp/status-AegirSetupA-FAIL
          exit 1
        fi
        if [ -e "/opt/tmp/status-AegirSetupC-runVerify" ]; then
          msg "${_STATUS} A: Platforms installed"
        fi
      else
        msg "${_STATUS} A: No new Platforms added this time"
      fi
    fi
  fi
  if [ ! -e "${_CORE}/dot-files-ctrl-${_X_SE}-${_X_VERSION}" ] \
    && [ -e "${_CORE}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Cleaning up various dot files, please wait..."
    fi
    cd ${_CORE}
    find . -name .svn -exec rm -rf {} \; &> /dev/null
    find . -name .bzr -exec rm -rf {} \; &> /dev/null
    find . -name .git -exec rm -rf {} \; &> /dev/null
    find . -name .DS_Store -exec rm -rf {} \; &> /dev/null
    find . -name "._*" -type f | xargs rm -rf &> /dev/null
    touch ${_CORE}/dot-files-ctrl-${_X_SE}-${_X_VERSION}
  fi
}

satellite_if_legacy_permissions_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_legacy_permissions_fix"
    debug_proc
  fi
  if [ -e "/run/aegir_upgrade.pid" ]; then
    _PLATF_IMP=$(ls -la /data/u \
      | grep ${_USER} \
      | cut -d'>' -f2 \
      | sort \
      | uniq \
      | awk '{ print $1}')
    for _PLATF in ${_PLATF_IMP}; do
      if [[ "${_PLATF}" =~ "aegir" ]]; then
        _FOUND_HM=YES
      else
        chown -R ${_USER}:www-data ${_PLATF}/sites/*/files &> /dev/null
        chmod -R 02775 ${_PLATF}/sites/*/files &> /dev/null
      fi
    done
  fi
}

satellite_child_scripts_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_scripts_cleanup"
    debug_proc
  fi
  rm -f ${_ROOT}/AegirSetupC.sh.txt*
  rm -f ${_ROOT}/AegirSetupB.sh.txt*
  rm -f ${_ROOT}/*.sh.txt
  rm -f /var/spool/cron/crontabs/${_USER}
}

satellite_if_add_ftps_lshell_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_add_ftps_lshell_access"
    debug_proc
  fi
  _USERFTP="${_USER}.ftp"
  _USERFTP_ROOT="/home/${_USERFTP}"
  if [ -e "/usr/bin/mysecureshell" ] && [ -e "/etc/ssh/sftp_config" ]; then
    _PATH_LSHELL="/usr/bin/mysecureshell"
  else
    _PATH_LSHELL="/usr/bin/lshell"
  fi
  _ID_SHELLS=$(id -nG ${_USERFTP} 2>&1)
  if [[ ! "${_ID_SHELLS}" =~ "users" ]] \
    || [ ! -d "${_USERFTP_ROOT}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding ftps/lshell user"
    fi
    # add user
    find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
    useradd -d /home/${_USERFTP} -s ${_PATH_LSHELL} -m -N -r ${_USERFTP} &> /dev/null
    adduser ${_USERFTP} ${_WEBG} &> /dev/null
    # Make sure new file which contains password is private
    cd ${_ROOT}/log
    touch ${_ROOT}/log/pass.txt
    chmod 0600 ${_ROOT}/log/pass.txt
    # generate a nice secure password and put it in a file
    _ESC_LUPASS=""
    _LEN_LUPASS=0
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
      if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt "128" ]; then
        _PWD_CHARS=128
      fi
    fi
    if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt "32" ]; then
      _RANDPASS_TEST=$(randpass -V 2>&1)
      if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
        _ESC_LUPASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
      else
        _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _ESC_LUPASS=$(sanitize_string "${_ESC_LUPASS}" 2>&1)
      fi
      _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
      _LEN_LUPASS=$(echo ${#_ESC_LUPASS} 2>&1)
    fi
    if [ -z "${_ESC_LUPASS}" ] || [ "${_LEN_LUPASS}" -lt "9" ]; then
      _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
      _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
      _ESC_LUPASS=$(sanitize_string "${_ESC_LUPASS}" 2>&1)
    fi
    echo "${_ESC_LUPASS}" > ${_ROOT}/log/pass.txt
    # get the password hash
    ph=$(mkpasswd -m sha-512 "${_ESC_LUPASS}" $(openssl rand -base64 16 \
      | tr -d '+=' | head -c 16))
    # Set the password
    usermod -p $ph ${_USERFTP} &> /dev/null
    passwd -w 7 -x 90 ${_USERFTP} &> /dev/null
  fi
  usermod -aG lshellg ${_USERFTP}
  chsh -s ${_PATH_LSHELL} ${_USERFTP} &> /dev/null
  echo >> /etc/lshell.conf
  echo "[${_USERFTP}]" >> /etc/lshell.conf
  echo "path : ['/opt/user/gems/${_USERFTP}', \
    '/opt/user/npm/${_USERFTP}', \
    '${_ROOT}/distro', \
    '${_ROOT}/static', \
    '${_ROOT}/backups', \
    '${_ROOT}/clients']" \
    | fmt -su -w 2500 >> /etc/lshell.conf
}

satellite_if_add_update_user_symlinks() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_add_update_user_symlinks"
    debug_proc
  fi
  ###---### Add symlink to the sites backups.
  #
  _USERFTP="${_USER}.ftp"
  _USER_HD="/home/${_USERFTP}"
  _USER_DS="${_USER_HD}/.drush"
  disable_chattr ${_USERFTP}
  if [ ! -L "${_USER_HD}/backups" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the sites backups"
    fi
    ln -sfn ${_ROOT}/backups ${_USER_HD}/backups
  fi

  ###---### Remove legacy symlinks.
  #
  if [ -e "${_USER_DS}/drush_make" ]; then
    rm -f ${_USER_DS}/drush_make
  fi
  if [ -e "${_USER_DS}/registry_rebuild" ]; then
    rm -f ${_USER_DS}/registry_rebuild
  fi
  if [ -e "${_USER_DS}/clean_missing_modules" ]; then
    rm -f ${_USER_DS}/clean_missing_modules
  fi
  if [ -e "${_USER_DS}/drush_ecl" ]; then
    rm -f ${_USER_DS}/drush_ecl
  fi
  if [ -e "${_USER_DS}/make_local" ]; then
    rm -f ${_USER_DS}/make_local
  fi
  if [ -e "${_USER_DS}/safe_cache_form_clear" ]; then
    rm -f ${_USER_DS}/safe_cache_form_clear
  fi
  if [ -e "${_USER_DS}/mydropwizard" ]; then
    rm -f ${_USER_DS}/mydropwizard
  fi
  if [ -e "${_USER_DS}/utf8mb4_convert" ]; then
    rm -f ${_USER_DS}/utf8mb4_convert
  fi

  ###---### Add symlink to the system registry_rebuild.
  #
  if [ ! -L "${_USER_DS}/usr/registry_rebuild" ] \
    && [ -e "${_ROOT}/.drush/usr/registry_rebuild" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the system registry_rebuild"
    fi
    mkdir -p ${_USER_DS}/usr
    chown ${_USERFTP}:${_USRG} ${_USER_DS}
    chown ${_USERFTP}:${_USRG} ${_USER_DS}/usr
    chmod 700 ${_USER_DS}
    ln -sfn ${_ROOT}/.drush/usr/registry_rebuild \
      ${_USER_DS}/usr/registry_rebuild
  fi

  ###---### Add symlink to the system clean_missing_modules.
  #
  if [ ! -L "${_USER_DS}/usr/clean_missing_modules" ] \
    && [ -e "${_ROOT}/.drush/usr/clean_missing_modules" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the system clean_missing_modules"
    fi
    mkdir -p ${_USER_DS}/usr
    chown ${_USERFTP}:${_USRG} ${_USER_DS}
    chown ${_USERFTP}:${_USRG} ${_USER_DS}/usr
    chmod 700 ${_USER_DS}
    ln -sfn ${_ROOT}/.drush/usr/clean_missing_modules \
      ${_USER_DS}/usr/clean_missing_modules
  fi

  ###---### Add symlink to the system drupalgeddon.
  #
  if [ ! -L "${_USER_DS}/usr/drupalgeddon" ] \
    && [ -e "${_ROOT}/.drush/usr/drupalgeddon" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the system drupalgeddon"
    fi
    mkdir -p ${_USER_DS}/usr
    chown ${_USERFTP}:${_USRG} ${_USER_DS}
    chown ${_USERFTP}:${_USRG} ${_USER_DS}/usr
    chmod 700 ${_USER_DS}
    ln -sfn ${_ROOT}/.drush/usr/drupalgeddon \
      ${_USER_DS}/usr/drupalgeddon
  fi

  ###---### Add symlink to the system drush_ecl.
  #
  if [ ! -L "${_USER_DS}/usr/drush_ecl" ] \
    && [ -e "${_ROOT}/.drush/usr/drush_ecl" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the system drush_ecl"
    fi
    mkdir -p ${_USER_DS}/usr
    chown ${_USERFTP}:${_USRG} ${_USER_DS}
    chown ${_USERFTP}:${_USRG} ${_USER_DS}/usr
    chmod 700 ${_USER_DS}
    ln -sfn ${_ROOT}/.drush/usr/drush_ecl \
      ${_USER_DS}/usr/drush_ecl
  fi

  ###---### Add symlink to the system safe_cache_form_clear.
  #
  if [ ! -L "${_USER_DS}/usr/safe_cache_form_clear" ] \
    && [ -e "${_ROOT}/.drush/usr/safe_cache_form_clear" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the system safe_cache_form_clear"
    fi
    mkdir -p ${_USER_DS}/usr
    chown ${_USERFTP}:${_USRG} ${_USER_DS}
    chown ${_USERFTP}:${_USRG} ${_USER_DS}/usr
    chmod 700 ${_USER_DS}
    ln -sfn ${_ROOT}/.drush/usr/safe_cache_form_clear \
      ${_USER_DS}/usr/safe_cache_form_clear
  fi

  ###---### Add symlink to the system utf8mb4_convert.
  #
  if [ ! -L "${_USER_DS}/usr/utf8mb4_convert" ] \
    && [ -e "${_ROOT}/.drush/usr/utf8mb4_convert" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the system utf8mb4_convert"
    fi
    mkdir -p ${_USER_DS}/usr
    chown ${_USERFTP}:${_USRG} ${_USER_DS}
    chown ${_USERFTP}:${_USRG} ${_USER_DS}/usr
    chmod 700 ${_USER_DS}
    ln -sfn ${_ROOT}/.drush/usr/utf8mb4_convert \
      ${_USER_DS}/usr/utf8mb4_convert
  fi

  ###---### Add symlink to the clients directory.
  #
  if [ ! -L "${_USER_HD}/clients" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Adding symlink to the clients directory"
    fi
    ln -sfn ${_ROOT}/clients ${_USER_HD}/clients
  fi
  rm -rf ${_ROOT}/clients/admin &> /dev/null
  rm -rf ${_ROOT}/clients/omega8ccgmailcom &> /dev/null
  rm -rf ${_ROOT}/clients/nocomega8cc &> /dev/null
  rm -rf ${_ROOT}/clients/*/backups &> /dev/null
  symlinks -dr ${_ROOT}/clients &> /dev/null
}

satellite_if_add_update_user_dot_dirs() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_add_update_user_dot_dirs"
    debug_proc
  fi
  ###---### Create .tmp dir if not exists.
  #
  _USER_TMP="${_USER_HD}/.tmp"
  if [ ! -d "${_USER_TMP}" ]; then
    mkdir -p ${_USER_TMP}
    touch ${_USER_TMP}
    find ${_USER_TMP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
    chown -R ${_USERFTP}:${_USRG} ${_USER_TMP}
    chmod 755 ${_USER_TMP}
  fi

  ###---### Create .ssh dir if not exists.
  #
  _USER_SSH="${_USER_HD}/.ssh"
  if [ ! -d "${_USER_SSH}" ]; then
    mkdir -p ${_USER_SSH}
    chown -R ${_USERFTP}:${_USRG} ${_USER_SSH}
    chmod 700 ${_USER_SSH}
  fi
  chmod 600 ${_USER_SSH}/id_{r,d}sa &> /dev/null

  ###---### Create .bazaar dir and conf file if not exist.
  #
  _USER_BZR="${_USER_HD}/.bazaar"
  if [ -x "/usr/local/bin/bzr" ]; then
    if [ ! -e "${_USER_BZR}/bazaar.conf" ]; then
      mkdir -p ${_USER_BZR}
      echo ignore_missing_extensions=True > ${_USER_BZR}/bazaar.conf
      chown -R ${_USERFTP}:${_USRG} ${_USER_BZR}
      chmod 700 ${_USER_BZR}
    fi
  else
    if [ -d "${_USER_BZR}" ]; then
      rm -rf ${_USER_BZR}
    fi
  fi

  ###---### Remove not used dot files.
  #
  rm -f ${_USER_HD}/{.profile,.bash_logout,.bash_profile,.bashrc}
}

###---### Reading or creating pass.txt.
#
satellite_if_read_create_pass_txt() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_read_create_pass_txt"
    debug_proc
  fi
  if [ "${_HM_ONLY}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    if [ -e "${_ROOT}/pass.txt" ]; then
      _PASWD=$(cat ${_ROOT}/pass.txt 2>&1)
      _PASWD=$(echo -n ${_PASWD} | tr -d "\n" 2>&1)
      mv -f ${_ROOT}/pass.txt ${_ROOT}/log/pass.txt &> /dev/null
    elif [ -e "${_ROOT}/log/pass.txt" ]; then
      _PASWD=$(cat ${_ROOT}/log/pass.txt 2>&1)
      _PASWD=$(echo -n ${_PASWD} | tr -d "\n" 2>&1)
      rm -f ${_ROOT}/pass.txt
    else
      cd ${_ROOT}/log
      touch ${_ROOT}/log/pass.txt
      chmod 0600 ${_ROOT}/log/pass.txt
      _ESC_LUPASS=""
      _LEN_LUPASS=0
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
        if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt "128" ]; then
          _PWD_CHARS=128
        fi
      fi
      if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt "32" ]; then
        _RANDPASS_TEST=$(randpass -V 2>&1)
        if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
          _ESC_LUPASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
        else
          _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
          _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
          _ESC_LUPASS=$(sanitize_string "${_ESC_LUPASS}" 2>&1)
        fi
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _LEN_LUPASS=$(echo ${#_ESC_LUPASS} 2>&1)
      fi
      if [ -z "${_ESC_LUPASS}" ] || [ "${_LEN_LUPASS}" -lt "9" ]; then
        _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _ESC_LUPASS=$(sanitize_string "${_ESC_LUPASS}" 2>&1)
      fi
      echo "${_ESC_LUPASS}" > ${_ROOT}/log/pass.txt
      ph=$(mkpasswd -m sha-512 "${_ESC_LUPASS}" $(openssl rand -base64 16 \
        | tr -d '+=' | head -c 16))
      usermod -p $ph ${_USERFTP} &> /dev/null
      _PASWD=$(cat ${_ROOT}/log/pass.txt 2>&1)
      _PASWD=$(echo -n ${_PASWD} | tr -d "\n" 2>&1)
    fi
  fi
}

###---### Creating platforms symlinks.
#
satellite_if_add_update_user_platforms_symlinks() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_add_update_user_platforms_symlinks"
    debug_proc
  fi
  if [ "${_DIST_INSTALL}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Creating ftp symlinks"
    fi

    _QR="${_ROOT}/distro/${_THIS_CORE}"
    _QH="/home/${_USERFTP}/platforms/${_THIS_CORE}"

    if [ ! -d "${_QH}" ]; then
      mkdir -p ${_QH}
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "DEBUG: _QH is ${_QH} in action symlinks 1"
      fi
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "DEBUG: _QH is ${_QH} in action symlinks 2"
    fi
    chown -R ${_USER}:${_USRG} /home/${_USERFTP}/platforms &> /dev/null
    chmod 700 /home/${_USERFTP} &> /dev/null
    rm -f ${_QH}/{cod,commerce,commons,openatrium,openscholar,drupal6,drupal7}

    if [ -d "${_QR}/agov-${_AGOV}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/agov-${_AGOV}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/agov-${_AGOV}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/agov-${_AGOV}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/civicrm-${_CIVICRM_M6}-${_SMALLCORE6_V}/sites" ]; then
      if [ ! -L "${_QH}/civicrm-${_CIVICRM_M6}-${_SMALLCORE6_V}" ]; then
        _A="${_QR}/civicrm-${_CIVICRM_M6}-${_SMALLCORE6_V}/sites"
        _B="${_QH}/civicrm-${_CIVICRM_M6}-${_SMALLCORE6_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/civicrm-${_CIVICRM_M7}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/civicrm-${_CIVICRM_M7}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/civicrm-${_CIVICRM_M7}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/civicrm-${_CIVICRM_M7}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/cod-${_COD}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/cod-${_COD}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/cod-${_COD}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/cod-${_COD}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/commerce-${_COMMERCE1}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/commerce-${_COMMERCE1}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/commerce-${_COMMERCE1}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/commerce-${_COMMERCE1}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/commerce-${_COMMERCE2}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/commerce-${_COMMERCE2}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/commerce-${_COMMERCE2}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/commerce-${_COMMERCE2}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/commons-${_COMMONS2}-${_SMALLCORE6_V}/sites" ]; then
      if [ ! -L "${_QH}/commons-${_COMMONS2}-${_SMALLCORE6_V}" ]; then
        _A="${_QR}/commons-${_COMMONS2}-${_SMALLCORE6_V}/sites"
        _B="${_QH}/commons-${_COMMONS2}-${_SMALLCORE6_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/commons-${_COMMONS3}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/commons-${_COMMONS3}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/commons-${_COMMONS3}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/commons-${_COMMONS3}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi

    if [ -d "${_QR}/pressflow-${_SMALLCORE6_V}-dev/sites" ]; then
      if [ ! -L "${_QH}/pressflow-${_SMALLCORE6_V}-dev" ]; then
        _A="${_QR}/pressflow-${_SMALLCORE6_V}-dev/sites"
        _B="${_QH}/pressflow-${_SMALLCORE6_V}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/pressflow-${_SMALLCORE6_V}-stage/sites" ]; then
      if [ ! -L "${_QH}/pressflow-${_SMALLCORE6_V}-stage" ]; then
        _A="${_QR}/pressflow-${_SMALLCORE6_V}-stage/sites"
        _B="${_QH}/pressflow-${_SMALLCORE6_V}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/pressflow" ]; then
      if [ -d "${_QR}/pressflow-${_SMALLCORE6_V}-prod/sites" ]; then
        if [ ! -L "${_QH}/pressflow-${_SMALLCORE6_V}-prod" ]; then
          _A="${_QR}/pressflow-${_SMALLCORE6_V}-prod/sites"
          _B="${_QH}/pressflow-${_SMALLCORE6_V}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/pressflow-${_SMALLCORE6_V}-prod" ]; then
      if [ -d "${_QR}/pressflow/sites" ]; then
        if [ ! -L "${_QH}/pressflow-${_SMALLCORE6_V}-prod" ]; then
          _A="${_QR}/pressflow/sites"
          _B="${_QH}/pressflow-${_SMALLCORE6_V}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/${_DRUPAL7D}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL7}-dev" ]; then
        _A="${_QR}/${_DRUPAL7D}/sites"
        _B="${_QH}/${_DRUPAL7}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/${_DRUPAL7S}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL7}-stage" ]; then
        _A="${_QR}/${_DRUPAL7S}/sites"
        _B="${_QH}/${_DRUPAL7}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/${_DRUPAL7}" ]; then
      if [ -d "${_QR}/${_DRUPAL7P}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL7}-prod" ]; then
          _A="${_QR}/${_DRUPAL7P}/sites"
          _B="${_QH}/${_DRUPAL7}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/${_DRUPAL7P}" ]; then
      if [ -d "${_QR}/${_DRUPAL7}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL7}-prod" ]; then
          _A="${_QR}/${_DRUPAL7}/sites"
          _B="${_QH}/${_DRUPAL7}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/${_DRUPAL9_D}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL9}-dev" ]; then
        _A="${_QR}/${_DRUPAL9_D}/sites"
        _B="${_QH}/${_DRUPAL9}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/${_DRUPAL9_S}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL9}-stage" ]; then
        _A="${_QR}/${_DRUPAL9_S}/sites"
        _B="${_QH}/${_DRUPAL9}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/${_DRUPAL9}" ]; then
      if [ -d "${_QR}/${_DRUPAL9_P}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL9}-prod" ]; then
          _A="${_QR}/${_DRUPAL9_P}/sites"
          _B="${_QH}/${_DRUPAL9}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/${_DRUPAL9_P}" ]; then
      if [ -d "${_QR}/${_DRUPAL9}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL9}-prod" ]; then
          _A="${_QR}/${_DRUPAL9}/sites"
          _B="${_QH}/${_DRUPAL9}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/${_DRUPAL10_0_D}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_0}-dev" ]; then
        _A="${_QR}/${_DRUPAL10_0_D}/sites"
        _B="${_QH}/${_DRUPAL10_0}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/${_DRUPAL10_0_S}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_0}-stage" ]; then
        _A="${_QR}/${_DRUPAL10_0_S}/sites"
        _B="${_QH}/${_DRUPAL10_0}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/${_DRUPAL10_0}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_0_P}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_0}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_0_P}/sites"
          _B="${_QH}/${_DRUPAL10_0}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/${_DRUPAL10_0_P}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_0}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_0}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_0}/sites"
          _B="${_QH}/${_DRUPAL10_0}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/${_DRUPAL10_1_D}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_1}-dev" ]; then
        _A="${_QR}/${_DRUPAL10_1_D}/sites"
        _B="${_QH}/${_DRUPAL10_1}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/${_DRUPAL10_1_S}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_1}-stage" ]; then
        _A="${_QR}/${_DRUPAL10_1_S}/sites"
        _B="${_QH}/${_DRUPAL10_1}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/${_DRUPAL10_1}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_1_P}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_1}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_1_P}/sites"
          _B="${_QH}/${_DRUPAL10_1}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/${_DRUPAL10_1_P}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_1}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_1}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_1}/sites"
          _B="${_QH}/${_DRUPAL10_1}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/${_DRUPAL10_2_D}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_2}-dev" ]; then
        _A="${_QR}/${_DRUPAL10_2_D}/sites"
        _B="${_QH}/${_DRUPAL10_2}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/${_DRUPAL10_2_S}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_2}-stage" ]; then
        _A="${_QR}/${_DRUPAL10_2_S}/sites"
        _B="${_QH}/${_DRUPAL10_2}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/${_DRUPAL10_2}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_2_P}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_2}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_2_P}/sites"
          _B="${_QH}/${_DRUPAL10_2}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/${_DRUPAL10_2_P}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_2}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_2}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_2}/sites"
          _B="${_QH}/${_DRUPAL10_2}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/${_DRUPAL10_3_D}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_3}-dev" ]; then
        _A="${_QR}/${_DRUPAL10_3_D}/sites"
        _B="${_QH}/${_DRUPAL10_3}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/${_DRUPAL10_3_S}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_3}-stage" ]; then
        _A="${_QR}/${_DRUPAL10_3_S}/sites"
        _B="${_QH}/${_DRUPAL10_3}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/${_DRUPAL10_3}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_3_P}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_3}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_3_P}/sites"
          _B="${_QH}/${_DRUPAL10_3}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/${_DRUPAL10_3_P}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_3}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_3}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_3}/sites"
          _B="${_QH}/${_DRUPAL10_3}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/${_DRUPAL10_4_D}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_4}-dev" ]; then
        _A="${_QR}/${_DRUPAL10_4_D}/sites"
        _B="${_QH}/${_DRUPAL10_4}-dev"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/${_DRUPAL10_4_S}/sites" ]; then
      if [ ! -L "${_QH}/${_DRUPAL10_4}-stage" ]; then
        _A="${_QR}/${_DRUPAL10_4_S}/sites"
        _B="${_QH}/${_DRUPAL10_4}-stage"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ ! -d "${_QR}/${_DRUPAL10_4}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_4_P}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_4}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_4_P}/sites"
          _B="${_QH}/${_DRUPAL10_4}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    elif [ ! -d "${_QR}/${_DRUPAL10_4_P}" ]; then
      if [ -d "${_QR}/${_DRUPAL10_4}/sites" ]; then
        if [ ! -L "${_QH}/${_DRUPAL10_4}-prod" ]; then
          _A="${_QR}/${_DRUPAL10_4}/sites"
          _B="${_QH}/${_DRUPAL10_4}-prod"
          ln -sfn ${_A} ${_B}
        fi
      fi
    fi

    if [ -d "${_QR}/erpal-${_ERPAL}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/erpal-${_ERPAL}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/erpal-${_ERPAL}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/erpal-${_ERPAL}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/fserver-${_SMALLCORE6_V}/sites" ]; then
      if [ ! -L "${_QH}/fserver-${_SMALLCORE6_V}" ]; then
        _A="${_QR}/fserver-${_SMALLCORE6_V}/sites"
        _B="${_QH}/fserver-${_SMALLCORE6_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/guardr-${_GUARDR}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/guardr-${_GUARDR}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/guardr-${_GUARDR}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/guardr-${_GUARDR}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openacademy-${_OPENACADEMY}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openacademy-${_OPENACADEMY}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openacademy-${_OPENACADEMY}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openacademy-${_OPENACADEMY}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openaid-${_OPENAID}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openaid-${_OPENAID}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openaid-${_OPENAID}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openaid-${_OPENAID}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openatrium-${_OPENATRIUM7}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openatrium-${_OPENATRIUM7}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openatrium-${_OPENATRIUM7}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openatrium-${_OPENATRIUM7}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openblog-${_OPENBLOG}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openblog-${_OPENBLOG}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openblog-${_OPENBLOG}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openblog-${_OPENBLOG}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openchurch-${_OPENCHURCH1}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openchurch-${_OPENCHURCH1}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openchurch-${_OPENCHURCH1}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openchurch-${_OPENCHURCH1}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openchurch-${_OPENCHURCH2}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openchurch-${_OPENCHURCH2}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openchurch-${_OPENCHURCH2}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openchurch-${_OPENCHURCH2}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/opendeals-${_OPENDEALS}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/opendeals-${_OPENDEALS}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/opendeals-${_OPENDEALS}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/opendeals-${_OPENDEALS}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openlucius-${_OPENLUCIUS}-${_SMALLCORE9_V}/web/sites" ]; then
      if [ ! -L "${_QH}/openlucius-${_OPENLUCIUS}-${_SMALLCORE9_V}" ]; then
        _A="${_QR}/openlucius-${_OPENLUCIUS}-${_SMALLCORE9_V}/web/sites"
        _B="${_QH}/openlucius-${_OPENLUCIUS}-${_SMALLCORE9_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openoutreach-${_OPENOUTREACH}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openoutreach-${_OPENOUTREACH}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openoutreach-${_OPENOUTREACH}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openoutreach-${_OPENOUTREACH}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openpublic-${_OPENPUBLIC}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openpublic-${_OPENPUBLIC}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openpublic-${_OPENPUBLIC}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openpublic-${_OPENPUBLIC}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openpublish-${_OPENPUBLISH}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openpublish-${_OPENPUBLISH}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openpublish-${_OPENPUBLISH}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openpublish-${_OPENPUBLISH}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/openscholar-${_OPENSCHOLAR}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/openscholar-${_OPENSCHOLAR}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/openscholar-${_OPENSCHOLAR}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/openscholar-${_OPENSCHOLAR}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/opigno_lms-${_OPIGNOLMS7}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/opigno_lms-${_OPIGNOLMS7}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/opigno_lms-${_OPIGNOLMS7}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/opigno_lms-${_OPIGNOLMS7}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/panopoly-${_PANOPOLY}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/panopoly-${_PANOPOLY}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/panopoly-${_PANOPOLY}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/panopoly-${_PANOPOLY}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/recruiter-${_RECRUITER}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/recruiter-${_RECRUITER}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/recruiter-${_RECRUITER}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/recruiter-${_RECRUITER}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/restaurant-${_RESTAURANT}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/restaurant-${_RESTAURANT}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/restaurant-${_RESTAURANT}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/restaurant-${_RESTAURANT}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/thunder-${_THUNDER}-${_SMALLCORE10_3_V}/docroot/sites" ]; then
      if [ ! -L "${_QH}/thunder-${_THUNDER}-${_SMALLCORE10_3_V}" ]; then
        _A="${_QR}/thunder-${_THUNDER}-${_SMALLCORE10_3_V}/docroot/sites"
        _B="${_QH}/thunder-${_THUNDER}-${_SMALLCORE10_3_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/ubercart-${_UBERCART6}-${_SMALLCORE6_V}/sites" ]; then
      if [ ! -L "${_QH}/ubercart-${_UBERCART6}-${_SMALLCORE6_V}" ]; then
        _A="${_QR}/ubercart-${_UBERCART6}-${_SMALLCORE6_V}/sites"
        _B="${_QH}/ubercart-${_UBERCART6}-${_SMALLCORE6_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/ubercart-${_UBERCART7}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/ubercart-${_UBERCART7}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/ubercart-${_UBERCART7}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/ubercart-${_UBERCART7}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/ubercart-testing-${_UBERCART7}-${_SMALLCORE7_V}/sites" ]; then
      if [ ! -L "${_QH}/ubercart-testing-${_UBERCART7}-${_SMALLCORE7_V}" ]; then
        _A="${_QR}/ubercart-testing-${_UBERCART7}-${_SMALLCORE7_V}/sites"
        _B="${_QH}/ubercart-testing-${_UBERCART7}-${_SMALLCORE7_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/varbase-${_VARBASE9}-${_SMALLCORE10_2_6_V}/docroot/sites" ]; then
      if [ ! -L "${_QH}/varbase-${_VARBASE9}-${_SMALLCORE10_2_6_V}" ]; then
        _A="${_QR}/varbase-${_VARBASE9}-${_SMALLCORE10_2_6_V}/docroot/sites"
        _B="${_QH}/varbase-${_VARBASE9}-${_SMALLCORE10_2_6_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/varbase-${_VARBASE10}-${_SMALLCORE10_3_V}/docroot/sites" ]; then
      if [ ! -L "${_QH}/varbase-${_VARBASE10}-${_SMALLCORE10_3_V}" ]; then
        _A="${_QR}/varbase-${_VARBASE10}-${_SMALLCORE10_3_V}/docroot/sites"
        _B="${_QH}/varbase-${_VARBASE10}-${_SMALLCORE10_3_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/social-${_SOCIAL}-${_SMALLCORE10_2_6_V}/html/sites" ]; then
      if [ ! -L "${_QH}/social-${_SOCIAL}-${_SMALLCORE10_2_6_V}" ]; then
        _A="${_QR}/social-${_SOCIAL}-${_SMALLCORE10_2_6_V}/html/sites"
        _B="${_QH}/social-${_SOCIAL}-${_SMALLCORE10_2_6_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
    if [ -d "${_QR}/opigno_lms-${_OPIGNOLMS9}-${_SMALLCORE9_V}/web/sites" ]; then
      if [ ! -L "${_QH}/opigno_lms-${_OPIGNOLMS9}-${_SMALLCORE9_V}" ]; then
        _A="${_QR}/opigno_lms-${_OPIGNOLMS9}-${_SMALLCORE9_V}/web/sites"
        _B="${_QH}/opigno_lms-${_OPIGNOLMS9}-${_SMALLCORE9_V}"
        ln -sfn ${_A} ${_B}
      fi
    fi
  fi
}

satellite_if_add_update_backend_user_dirs_files_clean() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_add_update_backend_user_dirs_files_clean"
    debug_proc
  fi
  ###---### Create ~/static dir if not exists.
  #
  if [ ! -d "${_ROOT}/static" ]; then
    mkdir -p ${_ROOT}/static
    ln -sfn ${_ROOT}/static /home/${_USERFTP}/static
  fi
  chown ${_USER}:${_USRG} ${_ROOT}/static &> /dev/null
  chmod 02775 ${_ROOT}/static &> /dev/null
  echo empty > ${_ROOT}/static/EMPTY.txt

  ###---### Create ~/.tmp dir if not exists.
  #
  if [ ! -d "${_ROOT}/.tmp" ]; then
    rm -rf ${_ROOT}/.tmp
    mkdir -p ${_ROOT}/.tmp
    chown ${_USER}:users ${_ROOT}/.tmp
    chmod 02775 ${_ROOT}/.tmp
  fi

  ###---### Create .ssh dir and keys if not exist, plus some known_hosts for system user.
  #
  if [ ! -e "${_ROOT}/.ssh/id_rsa.pub" ]; then
    su -s /bin/bash - ${_USER} -c "ssh-keygen -b 4096 -t rsa -N \"\" -f ~/.ssh/id_rsa" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H ${_USER}.beanstalkapp.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H ${_USER}.unfuddle.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H beanstalkapp.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H bitbucket.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H codebasehq.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H drupal.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H git.drupal.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H github.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H gitlab.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H gitlab.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H unfuddle.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    cp -af ${_ROOT}/.ssh/id_rsa.pub ${_ROOT}/static/${_USER}.id_rsa.pub
    chmod 644 ${_ROOT}/static/${_USER}.id_rsa.pub
  fi

  ###---### Create .bazaar dir and conf file if not exist for system user.
  #
  _SYSTEM_USER_BZR="${_ROOT}/.bazaar"
  if [ -x "/usr/local/bin/bzr" ]; then
    if [ ! -e "${_SYSTEM_USER_BZR}/bazaar.conf" ]; then
      mkdir -p ${_SYSTEM_USER_BZR}
      echo ignore_missing_extensions=True > ${_SYSTEM_USER_BZR}/bazaar.conf
      chown -R ${_USER}:${_USRG} ${_SYSTEM_USER_BZR}
      chmod 700 ${_SYSTEM_USER_BZR}
    fi
  else
    if [ -d "${_SYSTEM_USER_BZR}" ]; then
      rm -rf ${_SYSTEM_USER_BZR}
    fi
  fi

  ###---### Create other dirs and symlinks if not exist.
  #
  if [ "${_HM_ONLY}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    if [ ! -d "${_QR}/keys" ]; then
      mkdir -p ${_QR}/keys
      chown ${_USERFTP}:${_WEBG} ${_QR}/keys &> /dev/null
      chmod 02775 ${_QR}/keys
    fi
    if [ -d "${_QR}/keys" ]; then
      if [ ! -L "${_QH}/keys" ]; then
        ln -sfn ${_QR}/keys ${_QH}/keys
      fi
    fi
    rm -f ${_QR}/*/robots.txt &> /dev/null
    if [ ! -e "${_CORE}/javascript_aggregator.out.txt" ] \
      && [ -e "${_CORE}" ]; then
      sed -i "s/, 'javascript_aggregator'//g" \
        ${_CORE}/*/profiles/*/*.profile &> /dev/null
      wait
      touch ${_CORE}/javascript_aggregator.out.txt
    fi
  fi

  ###---### Remove not used cache module.
  #
  if [ ! -e "${_D}/000/old_cache.out2.txt" ] && [ -e "${_D}/000" ]; then
    sed -i "s/, 'cache'//g" ${_D}/*/*/profiles/*/*.profile &> /dev/null
    wait
    sed -i "s/'cache', //g" ${_D}/*/*/profiles/*/*.profile &> /dev/null
    wait
    rm -rf ${_D}/*/o_contrib/cache
    touch ${_D}/000/old_cache.out2.txt
  fi
}

###---### Preparing setupmail.txt.
#
satellite_prepare_setup_email_tpl() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_prepare_setup_email_tpl"
    debug_proc
  fi
  if [ "${_HM_ONLY}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Preparing setupmail.txt"
    fi
    _AT_CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
    _MY_EMAIL=${_MY_EMAIL//\\\@/\@}
    if [ -e "${_ROOT}/log/setupmail.txt" ] \
      || [ -e "${_ROOT}/log/legacy_setupmail.txt" ] \
      || [ -e "${_ROOT}/log/latest_setupmail.txt" ]; then
      if [ "${_DIST_INSTALL}" = "YES" ]; then
        cd ${_ROOT}/log
        if [ -e "${_ROOT}/log/upgrademail.txt" ]; then
          mv -f ${_ROOT}/log/upgrademail.txt \
            ${_ROOT}/log/upgrademail-pre-${_THIS_CORE}.txt
        fi
        cp -af /opt/tmp/boa/aegir/conf/tpl/upgrademail.txt ./
        sed -i "s/aegir.url.name/${_DOMAIN}/g" ${_ROOT}/log/upgrademail.txt
        wait
        sed -i "s/dragon/${_USER}/g" ${_ROOT}/log/upgrademail.txt
        wait
        sed -i "s/FN8rXcQn/${_PASWD}/g" ${_ROOT}/log/upgrademail.txt
        wait
        sed -i "s/166.84.6.231/${_THISHTIP}/g" ${_ROOT}/log/upgrademail.txt
        wait
        sed -i "s/boa.version/${_X_VERSION}/g" ${_ROOT}/log/upgrademail.txt
        wait
      else
        _SEND_UPGRADE_EMAIL=NO
      fi
    elif [ "${_STATUS}" = "INIT" ]; then
     cd ${_ROOT}/log
     cp -af /opt/tmp/boa/aegir/conf/tpl/setupmail.txt ./
     sed -i "s/aegir.url.name/${_DOMAIN}/g" ${_ROOT}/log/setupmail.txt
     wait
     sed -i "s/dragon/${_USER}/g" ${_ROOT}/log/setupmail.txt
     wait
     sed -i "s/FN8rXcQn/${_PASWD}/g" ${_ROOT}/log/setupmail.txt
     wait
     sed -i "s/166.84.6.231/${_THISHTIP}/g" ${_ROOT}/log/setupmail.txt
     wait
     sed -i "s/boa.version/${_X_VERSION}/g" ${_ROOT}/log/setupmail.txt
     wait
    fi
  fi
}

###---### Sending setup email.
#
satellite_send_welcome_email() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_send_welcome_email"
    debug_proc
  fi
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [ "${_STATUS}" = "INIT" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Sending setup email on init..."
    fi
    TIME=$(date 2>&1)
    _Q="Your Aegir Install on ${TIME} [${_USER}]"
    echo ${TIME} > ${_ROOT}/log/date-init.txt
    if [ -e "${_ROOT}/log/setupmail.txt" ] \
      || [ -e "${_ROOT}/log/legacy_setupmail.txt" ] \
      || [ -e "${_ROOT}/log/latest_setupmail.txt" ]; then
      if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
        cat ${_ROOT}/log/setupmail.txt \
          | sed "s/[\~]//g" \
          | s-nail -b ${_MY_EMAIL} -s "${_Q}" ${_AT_CLIENT_EMAIL}
      fi
    fi
  else
    if [ "${_DIST_INSTALL}" = "YES" ] && [ "${_PLATFORMS_ONLY}" = "NO" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "${_STATUS} A: Resending setup email on upgrade..."
      fi
      TIME=$(date 2>&1)
      _Q="[${_X_VERSION}] Aegir Upgrade [${_USER}]"
      echo ${TIME} > ${_ROOT}/log/date-upgrade-${_THIS_CORE}.txt
      if [ -e "${_ROOT}/log/upgrademail.txt" ]; then
        if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
          cat ${_ROOT}/log/upgrademail.txt \
            | sed "s/[\~]//g" \
            | s-nail -b ${_MY_EMAIL} -s "${_Q}" ${_AT_CLIENT_EMAIL}
        fi
      else
        if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
          cat ${_ROOT}/log/setupmail.txt \
            | sed "s/[\~]//g" \
            | s-nail -b ${_MY_EMAIL} -s "${_Q}" ${_AT_CLIENT_EMAIL}
        fi
      fi
    else
      _SEND_UPGRADE_EMAIL=NO
    fi
  fi
}

#
# Satellite start.
satellite_make() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_make"
    debug_proc
  fi
  export _OS_DIST=$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)
  export _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ -d "/data/all/000" ]; then
    if [ ! -e "/data/all/000/core-v-${_SMALLCORE6_V}.txt" ] \
      || [ ! -e "/data/all/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      export _USE_CURRENT=NO
      export _HOT_SAUCE=YES
      export _HM_ONLY=NO
    fi
  fi

  tocIncO="${filIncO}.${_USER}"

  if [ -e "${vBs}/${tocIncO}" ]; then
    writeTo="${vBs}/${tocIncO}"
  elif [ -e "${vBs}/${filIncO}" ]; then
    writeTo="${vBs}/${filIncO}"
  fi

  _X_SE="540devT01"
  export _X_SE="${_X_SE}"
  export _X_VERSION="${_X_VERSION}"

  echo "_AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${writeTo}
  echo "_AEGIR_XTS_VRN=\"${_AEGIR_XTS_VRN}\""         >> ${writeTo}
  echo "_AGOV=\"${_AGOV}\""                           >> ${writeTo}
  echo "_ALL_DISTRO=\"${_ALL_DISTRO}\""               >> ${writeTo}
  echo "_AUTOPILOT=\"${_AUTOPILOT}\""                 >> ${writeTo}
  echo "_BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${writeTo}
  echo "_BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${writeTo}
  echo "_BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${writeTo}
  echo "_BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${writeTo}
  echo "_CIVICRM_M6=\"${_CIVICRM_M6}\""               >> ${writeTo}
  echo "_CIVICRM_M7=\"${_CIVICRM_M7}\""               >> ${writeTo}
  echo "_CLIENT_CORES=\"${_CLIENT_CORES}\""           >> ${writeTo}
  echo "_CLIENT_EMAIL=\"${_CLIENT_EMAIL}\""           >> ${writeTo}
  echo "_CLIENT_OPTION=\"${_CLIENT_OPTION}\""         >> ${writeTo}
  echo "_COD=\"${_COD}\""                             >> ${writeTo}
  echo "_COMMERCE1=\"${_COMMERCE1}\""                 >> ${writeTo}
  echo "_COMMERCE2=\"${_COMMERCE2}\""                 >> ${writeTo}
  echo "_COMMONS2=\"${_COMMONS2}\""                   >> ${writeTo}
  echo "_COMMONS3=\"${_COMMONS3}\""                   >> ${writeTo}
  echo "_DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${writeTo}
  echo "_DISTRO=\"${_DISTRO}\""                       >> ${writeTo}
  echo "_DOMAIN=\"${_DOMAIN}\""                       >> ${writeTo}
  echo "_DRUPAL7=\"${_DRUPAL7}\""                     >> ${writeTo}
  echo "_DRUPAL7D=\"${_DRUPAL7}-dev\""                >> ${writeTo}
  echo "_DRUPAL7P=\"${_DRUPAL7}-prod\""               >> ${writeTo}
  echo "_DRUPAL7S=\"${_DRUPAL7}-stage\""              >> ${writeTo}
  echo "_DRUPAL8=\"${_DRUPAL8}\""                     >> ${writeTo}
  echo "_DRUPAL9=\"${_DRUPAL9}\""                     >> ${writeTo}
  echo "_DRUPAL9_D=\"${_DRUPAL9}-dev\""               >> ${writeTo}
  echo "_DRUPAL9_P=\"${_DRUPAL9}-prod\""              >> ${writeTo}
  echo "_DRUPAL9_S=\"${_DRUPAL9}-stage\""             >> ${writeTo}
  echo "_DRUPAL10_0=\"${_DRUPAL10_0}\""               >> ${writeTo}
  echo "_DRUPAL10_0_D=\"${_DRUPAL10_0}-dev\""         >> ${writeTo}
  echo "_DRUPAL10_0_P=\"${_DRUPAL10_0}-prod\""        >> ${writeTo}
  echo "_DRUPAL10_0_S=\"${_DRUPAL10_0}-stage\""       >> ${writeTo}
  echo "_DRUPAL10_1=\"${_DRUPAL10_1}\""               >> ${writeTo}
  echo "_DRUPAL10_1_D=\"${_DRUPAL10_1}-dev\""         >> ${writeTo}
  echo "_DRUPAL10_1_P=\"${_DRUPAL10_1}-prod\""        >> ${writeTo}
  echo "_DRUPAL10_1_S=\"${_DRUPAL10_1}-stage\""       >> ${writeTo}
  echo "_DRUPAL10_2=\"${_DRUPAL10_2}\""               >> ${writeTo}
  echo "_DRUPAL10_2_D=\"${_DRUPAL10_2}-dev\""         >> ${writeTo}
  echo "_DRUPAL10_2_P=\"${_DRUPAL10_2}-prod\""        >> ${writeTo}
  echo "_DRUPAL10_2_S=\"${_DRUPAL10_2}-stage\""       >> ${writeTo}
  echo "_DRUPAL10_3=\"${_DRUPAL10_3}\""               >> ${writeTo}
  echo "_DRUPAL10_3_D=\"${_DRUPAL10_3}-dev\""         >> ${writeTo}
  echo "_DRUPAL10_3_P=\"${_DRUPAL10_3}-prod\""        >> ${writeTo}
  echo "_DRUPAL10_3_S=\"${_DRUPAL10_3}-stage\""       >> ${writeTo}
  echo "_DRUPAL10_4=\"${_DRUPAL10_4}\""               >> ${writeTo}
  echo "_DRUPAL10_4_D=\"${_DRUPAL10_4}-dev\""         >> ${writeTo}
  echo "_DRUPAL10_4_P=\"${_DRUPAL10_4}-prod\""        >> ${writeTo}
  echo "_DRUPAL10_4_S=\"${_DRUPAL10_4}-stage\""       >> ${writeTo}
  echo "_DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${writeTo}
  echo "_ERPAL=\"${_ERPAL}\""                         >> ${writeTo}
  echo "_F_TIME=\"${_F_TIME}\""                       >> ${writeTo}
  echo "_GUARDR=\"${_GUARDR}\""                       >> ${writeTo}
  echo "_HM_DISTRO=\"${_HM_DISTRO}\""                 >> ${writeTo}
  echo "_HM_ONLY=\"${_HM_ONLY}\""                     >> ${writeTo}
  echo "_HOT_SAUCE=\"${_HOT_SAUCE}\""                 >> ${writeTo}
  echo "_LAST_ALL=\"${_LAST_ALL}\""                   >> ${writeTo}
  echo "_LAST_HMR=\"${_LAST_HMR}\""                   >> ${writeTo}
  echo "_LASTNUM=\"${_LASTNUM}\""                     >> ${writeTo}
  echo "_MY_EMAIL=\"${_MY_EMAIL}\""                   >> ${writeTo}
  echo "_MY_OWNIP=\"${_MY_OWNIP}\""                   >> ${writeTo}
  echo "_NOW=\"${_NOW}\""                             >> ${writeTo}
  echo "_OPENACADEMY=\"${_OPENACADEMY}\""             >> ${writeTo}
  echo "_OPENAID=\"${_OPENAID}\""                     >> ${writeTo}
  echo "_OPENATRIUM7=\"${_OPENATRIUM7}\""             >> ${writeTo}
  echo "_OPENBLOG=\"${_OPENBLOG}\""                   >> ${writeTo}
  echo "_OPENCHURCH1=\"${_OPENCHURCH1}\""             >> ${writeTo}
  echo "_OPENCHURCH2=\"${_OPENCHURCH2}\""             >> ${writeTo}
  echo "_OPENDEALS=\"${_OPENDEALS}\""                 >> ${writeTo}
  echo "_OPENLUCIUS=\"${_OPENLUCIUS}\""               >> ${writeTo}
  echo "_OPENOUTREACH=\"${_OPENOUTREACH}\""           >> ${writeTo}
  echo "_OPENPUBLIC=\"${_OPENPUBLIC}\""               >> ${writeTo}
  echo "_OPENPUBLISH=\"${_OPENPUBLISH}\""             >> ${writeTo}
  echo "_OPENSCHOLAR=\"${_OPENSCHOLAR}\""             >> ${writeTo}
  echo "_OPIGNOLMS7=\"${_OPIGNOLMS7}\""               >> ${writeTo}
  echo "_OPIGNOLMS9=\"${_OPIGNOLMS9}\""               >> ${writeTo}
  echo "_OS_CODE=\"${_OS_CODE}\""                     >> ${writeTo}
  echo "_PANOPOLY=\"${_PANOPOLY}\""                   >> ${writeTo}
  echo "_PHP_CLI_VERSION=\"${_PHP_CLI_VERSION}\""     >> ${writeTo}
  echo "_PHP_FPM_VERSION=\"${_PHP_FPM_VERSION}\""     >> ${writeTo}
  echo "_PLATFORMS_LIST=\"${_PLATFORMS_LIST}\""       >> ${writeTo}
  echo "_PLATFORMS_ONLY=\"${_PLATFORMS_ONLY}\""       >> ${writeTo}
  echo "_PURGE_FOR_SEVEN=\"${_PURGE_FOR_SEVEN}\""     >> ${writeTo}
  echo "_PURGE_MODE=\"${_PURGE_MODE}\""               >> ${writeTo}
  echo "_RECRUITER=\"${_RECRUITER}\""                 >> ${writeTo}
  echo "_REDIS_C_VERSION=\"${_REDIS_C_VERSION}\""     >> ${writeTo}
  echo "_REDIS_L_VERSION=\"${_REDIS_L_VERSION}\""     >> ${writeTo}
  echo "_REDIS_N_VERSION=\"${_REDIS_N_VERSION}\""     >> ${writeTo}
  echo "_REDIS_T_VERSION=\"${_REDIS_T_VERSION}\""     >> ${writeTo}
  echo "_RESTAURANT=\"${_RESTAURANT}\""               >> ${writeTo}
  echo "_SERIES_RESULT=\"${_SERIES_RESULT}\""         >> ${writeTo}
  echo "_SMALLCORE10_0_V=\"${_SMALLCORE10_0_V}\""     >> ${writeTo}
  echo "_SMALLCORE10_1_V=\"${_SMALLCORE10_1_V}\""     >> ${writeTo}
  echo "_SMALLCORE10_2_V=\"${_SMALLCORE10_2_V}\""     >> ${writeTo}
  echo "_SMALLCORE10_2_6_V=\"${_SMALLCORE10_2_6_V}\"" >> ${writeTo}
  echo "_SMALLCORE10_3_V=\"${_SMALLCORE10_3_V}\""     >> ${writeTo}
  echo "_SMALLCORE10_4_V=\"${_SMALLCORE10_4_V}\""     >> ${writeTo}
  echo "_SMALLCORE6_V=\"${_SMALLCORE6_V}\""           >> ${writeTo}
  echo "_SMALLCORE7_V=\"${_SMALLCORE7_V}\""           >> ${writeTo}
  echo "_SMALLCORE9_V=\"${_SMALLCORE9_V}\""           >> ${writeTo}
  echo "_SOCIAL=\"${_SOCIAL}\""                       >> ${writeTo}
  echo "_SPINNER=\"${_SPINNER}\""                     >> ${writeTo}
  echo "_STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${writeTo}
  echo "_T_BUILD=\"${_T_BUILD}\""                     >> ${writeTo}
  echo "_THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${writeTo}
  echo "_THIS_DB_PORT=\"${_THIS_DB_PORT}\""           >> ${writeTo}
  echo "_OS_DIST=\"${_OS_DIST}\""                     >> ${writeTo}
  echo "_THISHTIP=\"${_THISHTIP}\""                   >> ${writeTo}
  echo "_THUNDER=\"${_THUNDER}\""                     >> ${writeTo}
  echo "_TODAY=\"${_TODAY}\""                         >> ${writeTo}
  echo "_UBERCART6=\"${_UBERCART6}\""                 >> ${writeTo}
  echo "_UBERCART7=\"${_UBERCART7}\""                 >> ${writeTo}
  echo "_USE_CURRENT=\"${_USE_CURRENT}\""             >> ${writeTo}
  echo "_USE_MIR=\"${_USE_MIR}\""                     >> ${writeTo}
  echo "_USER=\"${_USER}\""                           >> ${writeTo}
  echo "_USRG=\"${_USRG}\""                           >> ${writeTo}
  echo "_VARBASE9=\"${_VARBASE9}\""                   >> ${writeTo}
  echo "_VARBASE10=\"${_VARBASE10}\""                 >> ${writeTo}
  echo "_WEBG=\"${_WEBG}\""                           >> ${writeTo}
  echo "_X_SE=\"${_X_SE}\""                           >> ${writeTo}
  echo "_X_VERSION=\"${_X_VERSION}\""                 >> ${writeTo}

  _THISHOST=$(cat /etc/hostname 2>&1)
  _THISHOST=$(echo -n ${_THISHOST} | tr -d "\n" 2>&1)
  if [ -e "/usr/bin/sipcalc" ]; then
    if [ -z "${_THISHTIP}" ]; then
      _LOC_DOM="${_THISHOST}"
      find_correct_ip
      _THISHTIP="${_LOC_IP}"
    fi
    _IP_TEST=$(sipcalc ${_THISHTIP} 2>&1)
    if [[ "${_IP_TEST}" =~ "ERR" ]]; then
      _IP_TEST_RESULT=FAIL
      _LOCAL_THISHTIP=all
    else
      _IP_TEST_RESULT=OK
      _LOCAL_THISHTIP="${_THISHTIP}"
    fi
  else
    _LOCAL_THISHTIP="${_THISHTIP}"
  fi
  if [ -z "${_LOCAL_THISHTIP}" ]; then
    _LOC_DOM="${_THISHOST}"
    find_correct_ip
    _LOCAL_THISHTIP="${_LOC_IP}"
  fi
  if [ -z "${_LOCAL_THISHTIP}" ]; then
    _LOCAL_THISHTIP=all
  fi

  cp -af ${bldPth}/aegir/scripts/run-xdrago /var/xdrago/run-${_USER}
  sed -i "s/EDIT_USER/${_USER}/g" /var/xdrago/run-${_USER}
  wait
  chmod 700 /var/xdrago/run-${_USER} &> /dev/null
  chmod 700 ${bldPth}/aegir/scripts/* &> /dev/null

  ###
  AegirSetupA="${bldPth}/aegir/scripts/AegirSetupA.sh.txt"
  bash ${AegirSetupA} ${_USER}
  wait
  ###

  if [ -e "/opt/tmp/status-AegirSetupA-FAIL" ]; then
    msg "FATAL ERROR: AegirSetupA installer failed"
    msg "FATAL ERROR: Aborting Octopus installer NOW!"
    touch /opt/tmp/status-Octopus-FAIL
    clean_pid_exit satellite_make_a
  fi

  if [ ! -e "${_ROOT}/log/email.txt" ]; then
    echo ${_CLIENT_EMAIL} > ${_ROOT}/log/email.txt
  fi
  if [ ! -e "${_ROOT}/log/option.txt" ]; then
    echo ${_CLIENT_OPTION} > ${_ROOT}/log/option.txt
  fi
  if [ ! -e "${_ROOT}/log/cores.txt" ]; then
    echo ${_CLIENT_CORES} > ${_ROOT}/log/cores.txt
  fi
  if [ ! -e "${_ROOT}/log/subscr.txt" ]; then
    echo ${_CLIENT_SUBSCR} > ${_ROOT}/log/subscr.txt
  fi
  if [ ! -e "${_ROOT}/log/fpm.txt" ]; then
    echo ${_PHP_FPM_VERSION} > ${_ROOT}/log/fpm.txt
  fi
  if [ ! -e "${_ROOT}/log/cli.txt" ]; then
    echo ${_PHP_CLI_VERSION} > ${_ROOT}/log/cli.txt
  fi
  if [ ! -e "${_ROOT}/static/control" ]; then
    mkdir -p ${_ROOT}/static/control
    chmod 755 ${_ROOT}/static/control
  fi
  if [ ! -e "${_ROOT}/static/control/fpm.info" ]; then
    echo ${_PHP_FPM_VERSION} > ${_ROOT}/static/control/fpm.info
  fi
  if [ ! -e "${_ROOT}/static/control/cli.info" ]; then
    if [ -e "${_ROOT}/static/control/fpm.info" ]; then
      cp -af ${_ROOT}/static/control/fpm.info ${_ROOT}/static/control/cli.info
    else
      echo ${_PHP_CLI_VERSION} > ${_ROOT}/static/control/cli.info
    fi
  fi

  if [ ! -e "${_ROOT}/static/control/.ctrl.${_X_SE}.pid" ] \
    && [ -e "/home/${_USER}.ftp/clients" ]; then
    if [ -e "/var/xdrago/conf/control-readme.txt" ]; then
      cp -af /var/xdrago/conf/control-readme.txt \
        ${_ROOT}/static/control/README.txt &> /dev/null
      chmod 0644 ${_ROOT}/static/control/README.txt
    fi
    rm -f ${_ROOT}/static/control/.ctrl.*
    echo OK > ${_ROOT}/static/control/.ctrl.${_X_SE}.pid
  fi
  chown -R ${_USER}.ftp:${_USRG} ${_ROOT}/static/control

  if [ -d "/data/all/000" ]; then
    if [ ! -e "/data/all/000/core-v-${_SMALLCORE6_V}.txt" ] \
      || [ ! -e "/data/all/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      echo "${_SMALLCORE6_V}" > /data/all/000/core-v-${_SMALLCORE6_V}.txt
      echo "${_SMALLCORE7_V}" > /data/all/000/core-v-${_SMALLCORE7_V}.txt
    fi
  fi

  if [ -e "${_ROOT}/log/email.txt" ]; then
    _PHP_FPM_MULTI=NO
    if [ -f "${_ROOT}/static/control/multi-fpm.info" ] \
      && [ -d "${_ROOT}/tools/le" ]; then
      _PHP_FPM_MULTI=YES
    fi
    if [ "${_PHP_FPM_MULTI}" = "NO" ]; then
      satellite_tune_fpm_config
    fi
    satellite_force_advanced_nginx_config
    mrun "service nginx reload" 2> /dev/null
  fi
}

satellite_if_head_github_connection_test() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_head_github_connection_test"
    debug_proc
  fi
  ###--------------------###
  if [ "${_AEGIR_VERSION}" != "static" ]; then
    rm -rf /opt/tmp/test-*
    check_connection
    _GITHUB_TEST=$(git clone ${gitHub}/provision.git \
      /opt/tmp/test-provision 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      msg "EXIT on error (provision) due to GitHub downtime"
      msg "Please try to run this script again in a few minutes"
      msg "You may want to check https://www.githubstatus.com"
      msg "Bye"
      rm -rf /opt/tmp/test-*
      clean_pid_exit satellite_if_head_github_connection_test_a
    fi
    _GITHUB_TEST=$(git clone ${gitHub}/hostmaster.git \
      /opt/tmp/test-hostmaster 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      msg "EXIT on error (hostmaster) due to GitHub downtime"
      msg "Please try to run this script again in a few minutes"
      msg "You may want to check https://www.githubstatus.com"
      msg "Bye"
      rm -rf /opt/tmp/test-*
      clean_pid_exit satellite_if_head_github_connection_test_b
    fi
    rm -rf /opt/tmp/test-*
  fi
  if [[ "${_X_VERSION}" =~ "-dev" ]] \
    || [[ "${_X_VERSION}" =~ "-lts" ]] \
    || [[ "${_X_VERSION}" =~ "-pro" ]]; then
    rm -rf /opt/tmp/test-*
    _GITHUB_TEST=$(git clone ${gitHub}/boa.git \
      /opt/tmp/test-boa 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      msg "EXIT on error (boa) due to GitHub downtime"
      msg "Please try to run this script again in a few minutes"
      msg "You may want to check https://www.githubstatus.com"
      msg "Bye"
      rm -rf /opt/tmp/test-*
      clean_pid_exit satellite_if_head_github_connection_test_c
    fi
    rm -rf /opt/tmp/test-*
  fi
}

satellite_if_sql_exception_test() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_sql_exception_test"
    debug_proc
  fi
  ###--------------------###
  if [ ! -e "/run/mysqld/mysqld.pid" ] \
    || [ ! -e "/run/mysqld/mysqld.sock" ]; then
    msg "ALRT! ${_DB_SERVER} server not running properly!"
    msg "EXIT: We can't proceed and will exit now"
    msg "HINT: Please check ${_LOG} for more information,"
    msg "HINT: (re)start ${_DB_SERVER} server, then run the installer again"
    msg "Bye"
    clean_pid_exit satellite_if_sql_exception_test_a
  fi
}

satellite_if_running_as_root_octopus() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_running_as_root_octopus"
    debug_proc
  fi
  if [ `whoami` = "root" ]; then
    chmod a+w /dev/null
  else
    msg "ERROR: This script should be run as a root user"
    msg "Bye"
    clean_pid_exit satellite_if_running_as_root_octopus_a
  fi
}

satellite_check_sanitize_user_name() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_check_sanitize_user_name"
    debug_proc
  fi
  _USER=${_USER//[^a-zA-Z0-9-.]/}
  _USER=$(echo -n ${_USER} | tr A-Z a-z 2>&1)
  _WEB="${_USER}.web"
  _ROOT="/data/disk/${_USER}"
  if [ -d "${_ROOT}" ]; then
    _STATUS=UPGRADE
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    satellite_check_id
  fi
}

satellite_if_localhost_mode_magic() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_localhost_mode_magic"
    debug_proc
  fi
  _THIS_HOST=$(uname -n 2>&1)
  if [ "${_THIS_HOST}" = "aegir.local" ] && [ ! -d "${_ROOT}" ]; then
    _DEBUG_MODE=NO
    _DNS_SETUP_TEST=NO
    _DOMAIN="${_USER}.sub.aegir.local"
    _LOCAL_NETWORK_IP="127.0.1.1"
    _MY_OWNIP="${_LOCAL_NETWORK_IP}"
    msg "_LOCAL_NETWORK_IP is ${_LOCAL_NETWORK_IP}"
  fi
}

satellite_check_sanitize_domain_name() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_check_sanitize_domain_name"
    debug_proc
  fi
  _DOMAIN=${_DOMAIN//[^a-zA-Z0-9-.]/}
  _DOMAIN=$(echo -n ${_DOMAIN} | tr A-Z a-z 2>&1)
  if [ ! -f "/var/aegir/config/server_master/nginx/vhost.d/${_DOMAIN}" ]; then
    _DO_NOTHING=YES
  else
    msg "ERROR: ${_DOMAIN} is already used on the Aegir Master Instance"
    msg "Please change the value for _DOMAIN to make it unique"
    msg "Bye"
    clean_pid_exit satellite_check_sanitize_domain_name_a
  fi
}

satellite_detect_vm_family() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_detect_vm_family"
    debug_proc
  fi
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _VMFAMILY="VS"
  else
    _VMFAMILY="XEN"
  fi
  # Check for Amazon EC2 in the system manufacturer field
  if dmidecode -s system-manufacturer | grep -i 'Amazon EC2' &> /dev/null; then
    _VMFAMILY="AWS"
  fi
  if [ "${_VMFAMILY}" = "AWS" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      _THIS_DB_HOST=localhost
    fi
    _LOC_DOM="${_DOMAIN}"
    if [ -z "${_MY_OWNIP}" ]; then
      find_correct_ip
      _MY_OWNIP="${_LOC_IP}"
    else
      _LOC_IP="${_MY_OWNIP}"
    fi
  fi
}

satellite_check_php_compatibility() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_check_php_compatibility"
    debug_proc
  fi
  if [ -e "${_ROOT}/static/control/fpm.info" ]; then
    _T_FPM_VRN=$(cat ${_ROOT}/static/control/fpm.info 2>&1)
    _T_FPM_VRN=${_T_FPM_VRN//[^0-9.]/}
    _T_FPM_VRN=$(echo -n ${_T_FPM_VRN} | tr -d "\n" 2>&1)
    if [ "${_T_FPM_VRN}" = "8.3" ] \
      || [ "${_T_FPM_VRN}" = "8.2" ] \
      || [ "${_T_FPM_VRN}" = "8.1" ] \
      || [ "${_T_FPM_VRN}" = "8.0" ] \
      || [ "${_T_FPM_VRN}" = "7.4" ] \
      || [ "${_T_FPM_VRN}" = "7.3" ] \
      || [ "${_T_FPM_VRN}" = "7.2" ] \
      || [ "${_T_FPM_VRN}" = "7.1" ] \
      || [ "${_T_FPM_VRN}" = "7.0" ] \
      || [ "${_T_FPM_VRN}" = "5.6" ]; then
      _PHP_FPM_LEGACY_FREE=YES
    else
      _PHP_FPM_LEGACY_FREE=NO
    fi
  else
    _PHP_FPM_LEGACY_FREE=YES
  fi
  if [ -e "${_ROOT}/static/control/cli.info" ]; then
    _T_CLI_VRN=$(cat ${_ROOT}/static/control/cli.info 2>&1)
    _T_CLI_VRN=${_T_CLI_VRN//[^0-9.]/}
    _T_CLI_VRN=$(echo -n ${_T_CLI_VRN} | tr -d "\n" 2>&1)
    if [ "${_T_CLI_VRN}" = "8.3" ] \
      || [ "${_T_CLI_VRN}" = "8.2" ] \
      || [ "${_T_CLI_VRN}" = "8.1" ] \
      || [ "${_T_CLI_VRN}" = "8.0" ] \
      || [ "${_T_CLI_VRN}" = "7.4" ] \
      || [ "${_T_CLI_VRN}" = "7.3" ] \
      || [ "${_T_CLI_VRN}" = "7.2" ] \
      || [ "${_T_CLI_VRN}" = "7.1" ] \
      || [ "${_T_CLI_VRN}" = "7.0" ] \
      || [ "${_T_CLI_VRN}" = "5.6" ]; then
      _PHP_CLI_LEGACY_FREE=YES
    else
      _PHP_CLI_LEGACY_FREE=NO
    fi
  else
    _PHP_CLI_LEGACY_FREE=YES
  fi
  if [ "${_PHP_CLI_LEGACY_FREE}" = "YES" ] \
    && [ "${_PHP_FPM_LEGACY_FREE}" = "YES" ]; then
    _PHP_LEGACY_FREE=YES
  else
    _PHP_LEGACY_FREE=NO
  fi
  if [ "${_PHP_LEGACY_FREE}" = "NO" ]; then
    msg "ERROR: This instance ${_USER} still depends on the old PHP version"
    msg "FPM.${_T_FPM_VRN} CLI.${_T_CLI_VRN}"
    msg "It is not possible to upgrade it to ${_X_VERSION}"
    msg "Please switch FPM and CLI on ${_USER} to PHP 5.6 or newer"
    msg "Then please run the octopus upgrade again"
    msg "Bye"
    clean_pid_exit satellite_check_php_compatibility_a
  fi
}

satellite_check_octopus_vs_barracuda_ver() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_check_octopus_vs_barracuda_ver"
    debug_proc
  fi
  if [ ! -f "/var/log/barracuda_log.txt" ]; then
    msg "ERROR: This octopus installer can be used only when the same version"
    msg "of boa or barracuda installer was used before. Your system must be"
    msg "upgraded with barracuda installer version ${_X_VERSION} first!"
    msg "Bye"
    clean_pid_exit satellite_check_octopus_vs_barracuda_ver_a
  else
    _VERSIONS_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
    if [[ "${_VERSIONS_TEST}" =~ "${_X_VERSION}" ]]; then
      _VERSIONS_TEST_RESULT=OK
    else
      msg "ERROR: This octopus installer can be used only when the same version"
      msg "of boa or barracuda installer was used before. Your system must be"
      msg "upgraded with barracuda installer version ${_X_VERSION} first!"
      msg "Bye"
      clean_pid_exit satellite_check_octopus_vs_barracuda_ver_b
    fi
  fi
  if [ -e "${_ROOT}/log/octopus_log.txt" ]; then
    if [ -e "/var/aegir/key/barracuda_key.txt" ] \
      && [ ! -e "${_ROOT}/tools/key/octopus_key.txt" ]; then
      mkdir ${_ROOT}/tools/key
      cat /var/aegir/key/barracuda_key.txt > ${_ROOT}/tools/key/octopus_key.txt
    fi
    _SERIES_TEST=$(cat ${_ROOT}/log/octopus_log.txt 2>&1)
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _VERSIONS_TEST_RESULT=OK
    else
      msg "ERROR: This octopus installer can be used only when the instance"
      msg "has been already upgraded to BOA-4.x or BOA-5.x release"
      msg "Please run 'octopus up-lts/pro/dev ${_USER} force' upgrade first!"
      msg "Display all supported commands with: octopus help"
      msg "Bye"
      clean_pid_exit satellite_check_octopus_vs_barracuda_ver_c
    fi
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _SERIES_RESULT=OK
    fi
  fi
  if [ -e "${_ROOT}/log/octopus_log.txt" ] \
    && [ "${tRee}" = "lts" ]; then
    _SERIES_TEST=$(cat ${_ROOT}/log/octopus_log.txt 2>&1)
    if [[ "${_SERIES_TEST}" =~ "Octopus ${rlsn}-pro" ]] \
      || [ -e "${_ROOT}/tools/key/octopus_key.txt" ]; then
      msg "ERROR: Your Octopus has been already upgraded to ${rlsn}-pro"
      msg "You can not downgrade back to previous/older/lts BOA version"
      msg "Please use 'octopus up-pro ${_USER} force' to upgrade"
      msg "Display all supported commands with: octopus help"
      msg "Bye"
      clean_pid_exit satellite_check_octopus_vs_barracuda_ver_d
    fi
  fi
  rm -f /run/aegir_upgrade.pid
  rm -f /opt/tmp/testecho*
}

satellite_if_init_or_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_init_or_upgrade"
    debug_proc
  fi
  if [ -d "${_ROOT}" ]; then
    msg "Octopus Satellite Instance Upgrade in progress..."
    if [ -d "${_ROOT}/distro" ]; then
      if [ -e "${_ROOT}/log/domain.txt" ]; then
        _DOMAIN=$(cat ${_ROOT}/log/domain.txt 2>&1)
        _DOMAIN=$(echo -n ${_DOMAIN} | tr -d "\n" 2>&1)
      fi
      if [ -z "${_DOMAIN}" ]; then
        msg "ALERT! _DOMAIN is e-m-p-t-y, exit now"
        clean_pid_exit satellite_if_init_or_upgrade_a
      fi
      if [ -z "${_USER}" ]; then
        msg "ALERT! _USER is e-m-p-t-y, exit now"
        clean_pid_exit satellite_if_init_or_upgrade_b
      fi
      _CHECK_HOST=$(uname -n 2>&1)
      if_hosted_sys
      if [ "${hostedSys}" = "YES" ]; then
        if [ -e "${_ROOT}/log/amazing_upgrade.txt" ] \
          && [ ! -e "${_ROOT}/log/amazing_upgrade_complete.txt" ]; then
          if [ -e "${_ROOT}/log/original_option.txt" ]; then
            cp -af ${_ROOT}/log/option.txt \
              ${_ROOT}/log/prev_option.txt
            cp -af ${_ROOT}/log/original_option.txt \
              ${_ROOT}/log/option.txt
          fi
          if [ -e "${_ROOT}/log/original_cores.txt" ]; then
            cp -af ${_ROOT}/log/cores.txt \
              ${_ROOT}/log/prev_cores.txt
            cp -af ${_ROOT}/log/original_cores.txt \
              ${_ROOT}/log/cores.txt
          fi
          echo completed > ${_ROOT}/log/amazing_upgrade_complete.txt
        fi
      fi
      if [ -e "${_ROOT}/log/option.txt" ]; then
        _CLIENT_OPTION=$(cat ${_ROOT}/log/option.txt 2>&1)
        _CLIENT_OPTION=$(echo -n ${_CLIENT_OPTION} | tr -d "\n" 2>&1)
      fi
      if [ -e "${_ROOT}/log/cores.txt" ]; then
        _CLIENT_CORES=$(cat ${_ROOT}/log/cores.txt 2>&1)
        _CLIENT_CORES=$(echo -n ${_CLIENT_CORES} | tr -d "\n" 2>&1)
      fi
      if [ -e "${_ROOT}/log/subscr.txt" ]; then
        _CLIENT_SUBSCR=$(cat ${_ROOT}/log/subscr.txt 2>&1)
        _CLIENT_SUBSCR=$(echo -n ${_CLIENT_SUBSCR} | tr -d "\n" 2>&1)
      fi
      if [ -e "${_ROOT}/log/email.txt" ]; then
        _CLIENT_EMAIL=$(cat ${_ROOT}/log/email.txt 2>&1)
        _CLIENT_EMAIL=$(echo -n ${_CLIENT_EMAIL} | tr -d "\n" 2>&1)
        if [[ "${_CLIENT_EMAIL}" =~ "@" ]]; then
          _DO_NOTHING=YES
        else
          msg "EXIT: You must enter your valid email address in the"
          msg "EXIT: _CLIENT_EMAIL variable written both in the"
          msg "EXIT: ${octCnf} file and in the"
          msg "EXIT: ${_ROOT}/log/email.txt file"
          msg "EXIT: Bye (1)"
          clean_pid_exit satellite_if_init_or_upgrade_c
        fi
        _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
      fi
      if [[ "${_CLIENT_EMAIL}" =~ "omega8.cc" ]]; then
        _CHECK_HOST=$(uname -n 2>&1)
        if_hosted_sys
        if [ "${hostedSys}" != "YES" ]; then
          msg "EXIT: You must enter your valid email address in the"
          msg "EXIT: _CLIENT_EMAIL variable written both in the"
          msg "EXIT: ${octCnf} file and in the"
          msg "EXIT: ${_ROOT}/log/email.txt file"
          msg "EXIT: Bye (2)"
          clean_pid_exit satellite_if_init_or_upgrade_d
        fi
      fi
      #
      # Check for last distro nr
      if [ -d "${_ROOT}/distro" ]; then
        cd ${_ROOT}/distro
        list=([0-9]*)
        last=${list[@]: -1}
        _LASTNUM=$last
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          nextnum=00$((10#0${last%%[^0-9]*} + 1))
        else
          nextnum=00$((10#${last%%[^0-9]*} + 1))
        fi
        nextnum=${nextnum: -3}
        _DISTRO=${nextnum}
      fi
      #
      # Check for last hm nr
      if [ -d "${_ROOT}/aegir/distro" ]; then
        cd ${_ROOT}/aegir/distro
        listx=([0-9]*)
        lastx=${listx[@]: -1}
        _LAST_HMR=$lastx
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          nextnumx=00$((10#0${lastx%%[^0-9]*} + 1))
        else
          nextnumx=00$((10#${lastx%%[^0-9]*} + 1))
        fi
        nextnumx=${nextnumx: -3}
        _HM_DISTRO=${nextnumx}
      fi
      #
      # Check for last all nr
      if [ -d "/data/all" ]; then
        cd /data/all
        listl=([0-9]*)
        lastl=${listl[@]: -1}
        export _LAST_ALL=$lastl
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          nextnuml=00$((10#0${lastl%%[^0-9]*} + 1))
        else
          nextnuml=00$((10#${lastl%%[^0-9]*} + 1))
        fi
        nextnuml=${nextnuml: -3}
        export _ALL_DISTRO=${nextnuml}
      fi
    #
    #
    elif [ ! -d "${_ROOT}/distro" ]; then
      if [ -e "${_ROOT}/log/domain.txt" ]; then
        _DOMAIN=$(cat ${_ROOT}/log/domain.txt 2>&1)
        _DOMAIN=$(echo -n ${_DOMAIN} | tr -d "\n" 2>&1)
      fi
    fi
  else
    msg "New Octopus Setup on $(uname -n 2>&1) in progress..."
    #
    # Check for last all nr
    if [ -d "/data/all" ]; then
      cd /data/all
      listl=([0-9]*)
      lastl=${listl[@]: -1}
      export _LAST_ALL=$lastl
      _BASH_TEST=$(bash --version 2>&1)
      if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
        nextnuml=00$((10#0${lastl%%[^0-9]*} + 1))
      else
        nextnuml=00$((10#${lastl%%[^0-9]*} + 1))
      fi
      nextnuml=${nextnuml: -3}
      export _ALL_DISTRO=${nextnuml}
    fi
  fi
}

satellite_if_major_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_major_upgrade"
    debug_proc
  fi
  if [ "${_CLIENT_OPTION}" = "POWER" ] \
    && [ -e "${_ROOT}/log/octopus_log.txt" ]; then
    _SERIES_TEST=$(cat ${_ROOT}/log/octopus_log.txt 2>&1)
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _IT_IS_OK=YES
    else
      if [ ! -e "${_ROOT}/log/satellite_major_upgrade_ok.txt" ]; then
        msg "ERROR: Major version upgrade requires control file:"
        msg "${_ROOT}/log/satellite_major_upgrade_ok.txt"
        msg "Bye"
        clean_pid_exit satellite_if_major_upgrade_a
      fi
    fi
  fi
  if [ "${_CLIENT_OPTION}" = "CLUSTER" ] \
    && [ -e "${_ROOT}/log/octopus_log.txt" ]; then
    _SERIES_TEST=$(cat ${_ROOT}/log/octopus_log.txt 2>&1)
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _IT_IS_OK=YES
    else
      if [ ! -e "${_ROOT}/log/satellite_major_upgrade_ok.txt" ]; then
        msg "ERROR: Major version upgrade requires control file:"
        msg "${_ROOT}/log/satellite_major_upgrade_ok.txt"
        msg "Bye"
        clean_pid_exit satellite_if_major_upgrade_b
      fi
    fi
  fi
}

satellite_if_check_dns() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_if_check_dns"
    debug_proc
  fi
  if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
    if [ "${_VMFAMILY}" = "AWS" ]; then
      _LOC_DOM="${_DOMAIN}"
      if [ -z "${_MY_OWNIP}" ]; then
        find_correct_ip
        _MY_OWNIP="${_LOC_IP}"
      else
        _LOC_IP="${_MY_OWNIP}"
      fi
    fi
    if [ -z "${_MY_OWNIP}" ]; then
      find_correct_ip
      _THISHTIP="${_LOC_IP}"
    else
      _THISHTIP="${_MY_OWNIP}"
    fi
    _LOC_DOM="${_DOMAIN}"
    find_correct_ip
    _THISRDIP="${_LOC_IP}"
    if [ "${_THISRDIP}" = "${_THISHTIP}" ]; then
      _DO_NOTHING=YES
    else
      msg "ERROR: ${_DOMAIN} doesn't point to your IP: ${_THISHTIP}"
      msg "Please make sure you have a valid A record in your DNS"
      msg "It is also possible that DNS change didn't propagate yet"
      msg "Bye"
      clean_pid_exit satellite_if_check_dns_a
    fi
  else
    if [ -z "${_MY_OWNIP}" ]; then
      _LOC_DOM="${_DOMAIN}"
      find_correct_ip
      _THISHTIP="${_LOC_IP}"
      _THISRDIP="${_LOC_IP}"
    else
      _THISHTIP="${_MY_OWNIP}"
      _THISRDIP="${_MY_OWNIP}"
    fi
  fi
}

satellite_checkpoint() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_checkpoint"
    debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    echo " "
    msg "START -> checkpoint: "
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    modeDetect="installation"
    optInf="${_CLIENT_OPTION} / ${_CLIENT_SUBSCR} / ${_CLIENT_CORES} C"
    cat <<EOF

    * Your email address is ${_MY_EMAIL}
    * Your client email address is ${_CLIENT_EMAIL}
    * Your Aegir control panel for this instance will be available at:
        https://${_DOMAIN}
    * Your Aegir system user for this instance will be ${_USER}
    * This Octopus will use PHP-CLI ${_PHP_CLI_VERSION} for all sites
    * This Octopus will use PHP-FPM ${_PHP_FPM_VERSION} for all sites
    * This Octopus includes platforms: ${_PLATFORMS_LIST}
    * This Octopus options are listed as ${optInf}

EOF
  else
    modeDetect="upgrade"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      optInf="${_CLIENT_OPTION} / ${_CLIENT_SUBSCR} / ${_CLIENT_CORES} C"
      cat <<EOF

    * Your Aegir control panel for this instance is available at:
        https://${_DOMAIN}
    * Your Aegir system user for this instance is ${_USER}
    * This Octopus will use PHP-CLI ${_PHP_CLI_VERSION} for all sites
    * This Octopus will use PHP-FPM ${_PHP_FPM_VERSION} for all sites
    * This Octopus includes platforms: ${_PLATFORMS_LIST}
    * This Octopus options are listed as ${optInf}

EOF
    else
      echo " "
      thiSys="$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)/$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1) $(uname -m 2>&1)"
      msg "This Octopus System is ${thiSys}"
      msg "This Octopus PHP FPM/CLI version is ${_PHP_FPM_VERSION}/${_PHP_CLI_VERSION}"
      msg "This Octopus URL address is ${_DOMAIN}"
      echo " "
    fi
  fi

  ### _MY_EMAIL=${_MY_EMAIL//\@/\\\@}
  ### _CLIENT_EMAIL=${_CLIENT_EMAIL//\@/\\\@}

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "8s before we will continue..."
    export _DEBUG_MODE="${_DEBUG_MODE}"
    if [ ! -z "${_USE_MIR}" ]; then
      export _USE_MIR="${_USE_MIR}"
    fi
  fi
  sleep 8
}

satellite_pre_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_pre_cleanup"
    debug_proc
  fi
  rm -f /tmp/cache.inc*
  rm -f /opt/tmp/status-*
  rm -rf /tmp/drush_make_tmp*
  rm -rf /tmp/make_tmp*
  rm -f /tmp/pm-updatecode*
  if [ -d "/home/${_USER}.ftp/" ]; then
    disable_chattr ${_USER}.ftp
  fi
}

satellite_post_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_post_cleanup"
    debug_proc
  fi
  if [ -d "/home/${_USER}.ftp/" ]; then
    enable_chattr ${_USER}.ftp
  fi
  rm -f /tmp/cache.inc*
  rm -rf /var/opt/*
  rm -rf /tmp/drush_make_tmp*
  rm -rf /tmp/make_tmp*
  rm -f /tmp/pm-updatecode*
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  rm -rf ${_ROOT}/.tmp/cache
  [ -e "/run/manage_ltd_users.pid" ] && rm -f /run/manage_ltd_users.pid
  [ -e "/run/manage_ruby_users.pid" ] && rm -f /run/manage_ruby_users.pid
}

satellite_letsencrypt_crt_key_copy() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_letsencrypt_crt_key_copy"
    debug_proc
  fi
  if [ -e "${leCrtPath}/fullchain.pem" ]; then
    crtPath="${leCrtPath}/fullchain.pem"
  elif [ -e "${leCrtPath}/cert.pem" ]; then
    crtPath="${leCrtPath}/cert.pem"
  fi
  if [ -e "${crtPath}" ]; then
    if [ -L "${crtPath}" ]; then
      crtPathR=$(readlink -n ${crtPath} 2>&1)
      crtPathR=$(echo -n ${crtPathR} | tr -d "\n" 2>&1)
      if [ -f "${leCrtPath}/${crtPathR}" ]; then
        rm -f /etc/ssl/private/${_DOMAIN}.crt
        cp -a ${leCrtPath}/${crtPathR} /etc/ssl/private/${_DOMAIN}.crt
      fi
    else
      rm -f /etc/ssl/private/${_DOMAIN}.crt
      cp -a ${crtPath} /etc/ssl/private/${_DOMAIN}.crt
    fi
  fi
  keyPath="${leCrtPath}/privkey.pem"
  if [ -e "${keyPath}" ]; then
    if [ -L "${keyPath}" ]; then
      keyPathR=$(readlink -n ${keyPath} 2>&1)
      keyPathR=$(echo -n ${keyPathR} | tr -d "\n" 2>&1)
      if [ -f "${leCrtPath}/${keyPathR}" ]; then
        rm -f /etc/ssl/private/${_DOMAIN}.key
        cp -a ${leCrtPath}/${keyPathR} /etc/ssl/private/${_DOMAIN}.key
      fi
    else
      rm -f /etc/ssl/private/${_DOMAIN}.key
      cp -a ${keyPath} /etc/ssl/private/${_DOMAIN}.key
    fi
  fi
}

satellite_letsencrypt_vhost_setup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_letsencrypt_vhost_setup"
    debug_proc
  fi
  ifvHst="YES"
  leRoot="${_ROOT}/tools/le"
  leKeyJ="${leRoot}/tools/le/private_key.json"
  leKeyP="${leRoot}/tools/le/private_key.pem"
  leCrtPath="${leRoot}/certs/${_DOMAIN}"
  exeLe="${leRoot}/dehydrated"
  Ssl="/var/aegir/config/server_master/nginx/pre.d/z_${_DOMAIN}_ssl_proxy.conf"
  if [ -e "${leRoot}/.ctrl/ssl-demo-mode.pid" ] \
    && [ -e "${leRoot}/config.sh" ]; then
    if [ -e "${Ssl}" ]; then
      rm -f ${Ssl}
      ifvHst="NO"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "${_STATUS} A: Reloading Nginx..."
        service nginx reload
      else
        mrun "service nginx reload" 2> /dev/null
      fi
    fi
  fi
  if [ "${ifvHst}" = "YES" ]; then
    if [ -e "${leCrtPath}/fullchain.pem" ] \
      || [ -e "${leCrtPath}/cert.pem" ]; then
      if [ -e "${Ssl}" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "${_STATUS} A: pre.d/z_${_DOMAIN}_ssl_proxy.conf exists, OK!"
        fi
        satellite_letsencrypt_crt_key_copy
        _HTTP3_TEST=$(grep http3 ${Ssl} 2>&1)
        if [[ ! "${_HTTP3_TEST}" =~ "http3" ]]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "${_STATUS} A: pre.d/z_${_DOMAIN}_ssl_proxy.conf needs update..."
          fi
          echo "${_DOMAIN} ${_THISHTIP} ${_USER} ${_CLIENT_EMAIL} ${_THISHTIP}" > /root/.ssl.proxy.cnf
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            bash /opt/local/bin/xboa ssl-gen
          else
            mrun "bash /opt/local/bin/xboa ssl-gen" &> /dev/null
          fi
        fi
      else
        msg "${_STATUS} A: Creating LE vhost for Hostmaster, please wait..."
        satellite_letsencrypt_crt_key_copy
        echo "${_DOMAIN} ${_THISHTIP} ${_USER} ${_CLIENT_EMAIL} ${_THISHTIP}" > /root/.ssl.proxy.cnf
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          bash /opt/local/bin/xboa ssl-gen
        else
          mrun "bash /opt/local/bin/xboa ssl-gen" &> /dev/null
        fi
        if [ -e "${Ssl}" ]; then
          [ -e "/root/.ssl.proxy.cnf" ] && rm -f /root/.ssl.proxy.cnf
          if [ -e "${crtPath}" ]; then
            crtPath=${crtPath//\//\\\/}
            sed -i "s/ssl_certificate .*/ssl_certificate              ${crtPath};/g" ${Ssl}
            wait
          fi
          if [ -e "${keyPath}" ]; then
            keyPath=${keyPath//\//\\\/}
            sed -i "s/ssl_certificate_key .*/ssl_certificate_key          ${keyPath};/g" ${Ssl}
            wait
          fi
          dhpWildPath="/etc/ssl/private/nginx-wild-ssl.dhp"
          if [ -e "/etc/ssl/private/4096.dhp" ]; then
            dhpPath="/etc/ssl/private/4096.dhp"
            _DIFF_T=$(diff -w -B ${dhpPath} ${dhpWildPath} 2>&1)
            if [ ! -z "${_DIFF_T}" ]; then
              cp -af ${dhpPath} ${dhpWildPath}
            fi
          elif [ -e "/etc/ssl/private/${_DOMAIN}.dhp" ]; then
            dhpPath="/etc/ssl/private/${_DOMAIN}.dhp"
          elif [ -e "${dhpWildPath}" ]; then
            dhpPath="${dhpWildPath}"
          fi
          if [ -e "${dhpPath}" ]; then
            dhpPath=${dhpPath//\//\\\/}
            sed -i "s/ssl_dhparam .*/ssl_dhparam                  ${dhpPath};/g" ${Ssl}
          else
            sed -i "s/.*ssl_dhparam .*//g" ${Ssl}
          fi
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "${_STATUS} A: Reloading Nginx..."
            service nginx reload
          else
            mrun "service nginx reload" 2> /dev/null
          fi
        else
          msg "${_STATUS} A: pre.d/z_${_DOMAIN}_ssl_proxy.conf doesn't exist!"
        fi
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "${_STATUS} A: le/certs/${_DOMAIN}/fullchain.pem doesn't exist!"
      fi
    fi
  fi
}

satellite_log_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_log_update"
    debug_proc
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    echo ${_F_TIME} > ${_ROOT}/log/date-init.txt
  else
    echo ${_F_TIME} > ${_ROOT}/log/date-upgrade-${_THIS_CORE}.txt
  fi
  _OCTOPUS_VERSION_INFO="${_F_TIME} / \
    ${_OS_DIST}.${_OS_CODE} $(uname -m 2>&1) \
    / Aegir ${_AEGIR_VERSION} / Octopus ${_X_VERSION} \
    / FPM ${_PHP_FPM_VERSION} / CLI ${_PHP_CLI_VERSION}"
  echo "${_OCTOPUS_VERSION_INFO}" | fmt -su -w 2500 >> \
    ${_ROOT}/log/octopus_log.txt
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: New entry added to ${_ROOT}/log/octopus_log.txt"
  fi
}

satellite_batch_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_batch_cleanup"
    debug_proc
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _L_ST="install"
  else
    _L_ST="upgrade"
  fi
  msg "Final post-${_L_ST} cleaning, one moment..."
  cd /
  chmod 711 bin boot data dev emul etc home lib lib64 lib32 media mnt &> /dev/null
  chmod 711 opt sbin selinux srv sys usr var share run &> /dev/null
  chmod 700 root &> /dev/null
  if [ -e "${_D}" ]; then
    if [ ! -f "${_D}/permissions-fix-${_X_SE}-${_X_VERSION}-${_TODAY}.info" ]; then
      find ${_D}/000 -type d -exec chmod 0755 {} \; &> /dev/null
      find ${_D}/000 -type f -exec chmod 0644 {} \; &> /dev/null
      mrun "chmod 755 ${_D}/*/*/profiles" &> /dev/null
      mrun "chmod 02775 ${_D}/*/*/sites/all/{modules,libraries,themes}" &> /dev/null
      mrun "chmod 02775 ${_D}/000/core/*/sites/all/{modules,libraries,themes}" &> /dev/null
      mrun "chown -R root:root ${_D}" &> /dev/null
      mrun "chown -R root:users ${_D}/*/*/sites" &> /dev/null
      echo fixed > ${_D}/permissions-fix-${_X_SE}-${_X_VERSION}-${_TODAY}.info
    fi
    chown root:root ${_D} &> /dev/null
    chown root:root ${_CORE} &> /dev/null
    mrun "chown -R root:root /data/conf" &> /dev/null
    mrun "chown -R root:root ${_CORE}/o_contrib" &> /dev/null
    mrun "chown -R root:root ${_CORE}/o_contrib_seven" &> /dev/null
    mrun "chown -R root:root ${_D}/000" &> /dev/null
    find /data/conf -type d -exec chmod 0755 {} \; &> /dev/null
    find /data/conf -type f -exec chmod 0644 {} \; &> /dev/null
    chown root:root /opt/tmp &> /dev/null
    chmod 0711 /data ${_D}/* /data/disk /data/conf &> /dev/null
    chmod 644 /data/all/cpuinfo &> /dev/null
    chmod 0755 ${_D} ${_D}/000 &> /dev/null
  elif [ -e "/data/disk/all" ]; then
    if [ ! -f "/data/disk/all/permissions-fix-${_X_SE}-${_X_VERSION}-${_TODAY}.info" ]; then
      find /data/disk/all/000 -type d -exec chmod 0755 {} \; &> /dev/null
      find /data/disk/all/000 -type f -exec chmod 0644 {} \; &> /dev/null
      mrun "chmod 755 /data/disk/all/*/*/profiles" &> /dev/null
      mrun "chmod 02775 /data/disk/all/*/*/sites/all/{modules,libraries,themes}" &> /dev/null
      mrun "chmod 02775 /data/disk/all/000/core/*/sites/all/{modules,libraries,themes}" &> /dev/null
      mrun "chown -R root:root /data/disk/all" &> /dev/null
      mrun "chown -R root:users /data/disk/all/*/*/sites" &> /dev/null
      echo fixed > /data/disk/all/permissions-fix-${_X_SE}-${_X_VERSION}-${_TODAY}.info
    fi
    chown root:root /data/disk/all &> /dev/null
    chown root:root ${_CORE} &> /dev/null
    mrun "chown -R root:root /data/conf" &> /dev/null
    mrun "chown -R root:root ${_CORE}/o_contrib" &> /dev/null
    mrun "chown -R root:root ${_CORE}/o_contrib_seven" &> /dev/null
    mrun "chown -R root:root /data/disk/all/000" &> /dev/null
    find /data/conf -type d -exec chmod 0755 {} \; &> /dev/null
    find /data/conf -type f -exec chmod 0644 {} \; &> /dev/null
    chown root:root /opt/tmp &> /dev/null
    chmod 0711 /data /data/disk/all/* /data/disk /data/conf &> /dev/null
    chmod 644 /data/disk/all/cpuinfo &> /dev/null
    chmod 0755 /data/disk/all /data/disk/all/000 &> /dev/null
  fi
  chmod 0700 /data/u &> /dev/null
  chown root:root /data/u &> /dev/null
  rm -f /data/u/*host8* &> /dev/null
  rm -f /data/u/*o8.io* &> /dev/null
  rm -f /data/u/*boa.io* &> /dev/null
  rm -f /data/u/*aegir.cc* &> /dev/null
  mv -f ${_ROOT}/backups/drupalgeddon-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/drush_make-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/drush-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/make_local-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/provision_boost-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/provision_cdn-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/provision_civicrm-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/provision_platform_git-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/provision_site_backup-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/provision_tasks_extra-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/provision-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/registry_rebuild-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/safe_cache_form_clear-pre* ${_ROOT}/backups/system/ &> /dev/null
  mv -f ${_ROOT}/backups/mydropwizard-pre* ${_ROOT}/backups/system/ &> /dev/null
  mkdir -p /data/conf/arch
  mv -f /data/conf/global.inc-pre* /data/conf/arch/ &> /dev/null
  mv -f /data/conf/global/*inc-pre* /data/conf/arch/ &> /dev/null
  mv -f /data/conf/global.inc-before* /data/conf/arch/ &> /dev/null
  mv -f /data/conf/global.inc-missing* /data/conf/arch/ &> /dev/null
  find ${_ROOT}/static/*/module* -maxdepth 0 -mindepth 0 -type d -exec chmod 775 {} \; &> /dev/null
  find ${_ROOT}/static/*/*/module* -maxdepth 0 -mindepth 0 -type d -exec chmod 775 {} \; &> /dev/null
  find ${_ROOT}/static/*/*/*/module* -maxdepth 0 -mindepth 0 -type d -exec chmod 775 {} \; &> /dev/null
  find ${_ROOT}/static/*/*/*/*/module* -maxdepth 0 -mindepth 0 -type d -exec chmod 775 {} \; &> /dev/null
  if [ -d "${_CORE}/${_DRUPAL7}" ]; then
    mkdir -p /var/backups/trash
    rm -rf /var/backups/trash/*
    mv -f ${_CORE}/${_DRUPAL7} /var/backups/trash/ &> /dev/null
  fi
}

satellite_display_url_finalize() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_display_url_finalize"
    debug_proc
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      _AEGIR_LOGIN_URL=$(tail --lines=11 ${_ROOT}/log/install.log | grep --text "^http:" 2>&1)
      if [ ! -z "${_AEGIR_LOGIN_URL}" ]; then
        echo " "
        msg "INFO: Congratulations, Aegir have been installed successfully!"
        msg "NOTE! Please wait 2 min before visiting Aegir at:"
        echo " "
        msg "LINK: ${_AEGIR_LOGIN_URL}"
        echo " "
        msg "NOTE! The initial one-time login link will no longer work."
        sleep 3
        msg "To access your Octopus Aegir control panel after the procedure is finished..."
        msg "...please generate a new link by running the following command:"
        sleep 3
        echo " "
        echo "  su -s /bin/bash ${_USER} -c \"drush @hm uli\""
        echo " "
        sleep 3
      else
        msg "ALRT! Something went wrong"
        msg "ALRT! Please check the install log for details:"
        msg "ALRT! ${_ROOT}/log/install.log"
      fi
    fi
  else
    satellite_o_contrib_update_global
    satellite_o_contrib_seven_update_global
    satellite_o_contrib_eight_update_global
    satellite_o_contrib_nine_update_global
    satellite_o_contrib_ten_update_global
  fi
  if [ ! -e "/root/.upstart.cnf" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} A: Starting the cron now"
    fi
    mrun "service cron start" 2> /dev/null
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} A: All done!"
  fi
  msg "BYE!"

  touch /opt/tmp/status-AegirSetupA-OK
}


satellite_child_b_prepare_dirs_permissions() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_prepare_dirs_permissions"
    debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} B: Creating directories with correct permissions"
  fi
  if [ -e "${_ROOT}/aegir.sh" ]; then
    rm -f ${_ROOT}/aegir.sh
  fi
  #_DRUSH_HOSTING_TASKS_CMD="/usr/bin/drush @hostmaster hosting-tasks --force"
  _DRUSH_HOSTING_DISPATCH_CMD="${_T_CLI}/php ${_ROOT}/tools/drush/drush.php @hostmaster hosting-dispatch"
  touch ${_ROOT}/aegir.sh
  chmod 0700 ${_ROOT}/aegir.sh &> /dev/null
  echo -e \
    "#!/bin/bash\n\nPATH=.:${_T_CLI}:/usr/sbin:/usr/bin:/sbin:/bin\n \
     \n${_DRUSH_HOSTING_DISPATCH_CMD} \
     \ntouch ${_ROOT}/${_USER}-task.done" \
     | fmt -su -w 2500 | tee -a ${_ROOT}/aegir.sh >/dev/null 2>&1

  mkdir -p ${_ROOT}/aegir/distro
  mkdir -p ${_ROOT}/distro/${_DISTRO}
  mkdir -p ${_ROOT}/src/${_DISTRO}
  mkdir -p ${_ROOT}/src/{modules,themes}
  mkdir -p ${_ROOT}/{tools,log,u,backups,platforms,clients}
  chmod 0700 ${_ROOT}/{log,src,u} &> /dev/null
  chmod 0700 ${_ROOT}/src/${_DISTRO} &> /dev/null
  chmod 0700 ${_ROOT}/src/{modules,themes} &> /dev/null
  chmod 0711 ${_ROOT}/{aegir,aegir/distro,distro,platforms,tools} &> /dev/null
  chmod 0711 ${_ROOT}/distro/${_DISTRO} &> /dev/null
  chmod 0750 ${_ROOT}/{backups,clients} &> /dev/null

  if [ "${_STATUS}" = "UPGRADE" ]; then
    #msg "${_STATUS} B: UPGRADE in progress..."
    if [ -d "${_ROOT}/distro" ]; then
     #msg "${_STATUS} B: UPGRADE v.2 in progress..."
     if [ -e "${_ROOT}/log/domain.txt" ]; then
      _DOMAIN=$(cat ${_ROOT}/log/domain.txt 2>&1)
      _DOMAIN=$(echo -n ${_DOMAIN} | tr -d "\n" 2>&1)
     fi
     #msg "${_STATUS} B: _DOMAIN is ${_DOMAIN}"
    elif [ ! -d "${_ROOT}/distro" ]; then
     #msg "${_STATUS} B: UPGRADE v.1 in progress..."
     #msg "${_STATUS} B: _DISTRO is ${_DISTRO}"
     if [ -e "${_ROOT}/log/domain.txt" ]; then
      _DOMAIN=$(cat ${_ROOT}/log/domain.txt 2>&1)
      _DOMAIN=$(echo -n ${_DOMAIN} | tr -d "\n" 2>&1)
     fi
     #msg "${_STATUS} B: _DOMAIN is ${_DOMAIN}"
    fi
  else
    true
    #msg "${_STATUS} B: NEW AEGIR setup in progress..."
    #msg "${_STATUS} B: _DISTRO is ${_DISTRO}"
    #msg "${_STATUS} B: _DOMAIN is ${_DOMAIN}"
  fi
  echo ${_DOMAIN} > ${_ROOT}/log/domain.txt
}

satellite_child_b_install_drush() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_install_drush"
    debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} B: Running standard installer"
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    mkdir -p ${_ROOT}/backups/system
    chmod 700 ${_ROOT}/backups/system
    if [ -d "${_ROOT}/aegir/config" ]; then
      if [ ! -d "${_ROOT}/config" ]; then
        cd ${_ROOT}/aegir
        mv -f config ${_ROOT}/config &> /dev/null
        ln -sfn ${_ROOT}/config ${_ROOT}/aegir/config
      fi
    fi
    if [ -d "${_ROOT}/tools/drush" ]; then
      cd ${_ROOT}/tools
      mv -f drush \
        ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} &> /dev/null
    fi
  fi
  cd ${_ROOT}/tools
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} B: Downloading drush ${_DRUSH_VERSION}..."
  fi
  get_dev_ext "drush-${_DRUSH_VERSION}.tar.gz"
  cd ${_ROOT}/tools/drush/
  find ${_ROOT}/tools/drush -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_ROOT}/tools/drush -type f -exec chmod 0644 {} \; &> /dev/null
  chmod 755 ${_ROOT}/tools/drush/drush
  chmod 755 ${_ROOT}/tools/drush/drush.complete.sh
  chmod 755 ${_ROOT}/tools/drush/drush.launcher
  chmod 755 ${_ROOT}/tools/drush/drush.php
  chmod 755 ${_ROOT}/tools/drush/unish.sh
  chmod 755 ${_ROOT}/tools/drush/examples/drush.wrapper
  chmod 755 ${_ROOT}/tools/drush/examples/git-bisect.example.sh
  chmod 755 ${_ROOT}/tools/drush/examples/helloworld.script
  satellite_child_b_update_php_cli
  satellite_child_b_update_ini_php_cli
}

satellite_child_b_drush_xts_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_drush_xts_cleanup"
    debug_proc
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    mkdir -p ${_ROOT}/backups/system
    chmod 700 ${_ROOT}/backups/system
    mv -f ${_ROOT}/backups/drush-pre* ${_ROOT}/backups/system/ &> /dev/null
    _B_EXT="provision clean_missing_modules drupalgeddon drush_ecl make_local \
      provision_boost provision_cdn provision_civicrm provision_platform_git \
      provision_site_backup provision_tasks_extra remote_import mydropwizard \
      registry_rebuild safe_cache_form_clear security_check security_review \
      utf8mb4_convert"
    for e in ${_B_EXT}; do
      if [ -e "${_ROOT}/.drush/$e" ]; then
        mv -f ${_ROOT}/.drush/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
      if [ -e "${_ROOT}/.drush/xts/$e" ]; then
        mv -f ${_ROOT}/.drush/xts/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
      if [ -e "${_ROOT}/.drush/usr/$e" ]; then
        mv -f ${_ROOT}/.drush/usr/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
      if [ -e "${_ROOT}/.drush/sys/$e" ]; then
        mv -f ${_ROOT}/.drush/sys/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
    done
  fi
}

satellite_child_b_drush_xts_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_drush_xts_install"
    debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} B: Installing Aegir Provision backend..."
  fi
  mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
  cd ${_ROOT}/.drush
  if [ "${_AEGIR_VERSION}" != "static" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} B: Downloading Drush and Provision extensions..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    rD="${_ROOT}/.drush"
    ${gCb} ${_BRANCH_PRN} ${gitHub}/provision.git \
      ${rD}/sys/provision &> /dev/null
    ${gCb} 7.x-1.x-dev ${gitHub}/drupalgeddon.git \
      ${rD}/usr/drupalgeddon &> /dev/null
    ${gCb} 7.x-1.x ${gitHub}/drush_ecl.git \
      ${rD}/usr/drush_ecl &> /dev/null
    ${gCb} 7.x-1.x ${gitHub}/security_review.git \
      ${rD}/xts/security_review &> /dev/null
    ${gCb} 7.x-2.x ${gitHub}/provision_boost.git \
      ${rD}/xts/provision_boost &> /dev/null
    ${gCb} 7.x-2.x ${gitHub}/registry_rebuild.git \
      ${rD}/usr/registry_rebuild &> /dev/null
    ${gCb} 7.x-1.x ${gitHub}/safe_cache_form_clear.git \
      ${rD}/usr/safe_cache_form_clear &> /dev/null
    rm -rf ${rD}/*/.git
    rm -rf ${rD}/*/*/.git
    cd ${rD}/usr
    get_dev_ext "clean_missing_modules.tar.gz"
    get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} B: Downloading Drush and Provision extensions..."
    fi
    cd ${_ROOT}/.drush/sys
    get_dev_ext "provision.tar.gz"
    cd ${_ROOT}/.drush/usr
    get_dev_ext "clean_missing_modules.tar.gz"
    get_dev_ext "drupalgeddon.tar.gz"
    get_dev_ext "drush_ecl.tar.gz"
    get_dev_ext "registry_rebuild.tar.gz"
    get_dev_ext "safe_cache_form_clear.tar.gz"
    get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
    cd ${_ROOT}/.drush/xts
    get_dev_ext "provision_boost.tar.gz"
    get_dev_ext "security_review.tar.gz"
    cd ${_ROOT}/.drush
  fi
  sed -i "s/files.aegir.cc/${_USE_MIR}/g" \
    ${_ROOT}/.drush/sys/provision/aegir.make &> /dev/null
  wait
}

satellite_child_b_drush_test() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_drush_test"
    debug_proc
  fi
  drush8 cc drush &> /dev/null
  rm -rf ${_ROOT}/.tmp/cache
  if ${_DRUSHCMD} help | grep "^ provision-install" > /dev/null ; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} B: Drush test result OK"
    fi
  else
    msg "${_STATUS} B: FATAL ERROR: Drush is broken (${_DRUSHCMD} help failed)"
    msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
    touch /opt/tmp/status-AegirSetupB-FAIL
    exit 1
  fi
}

satellite_child_b_aegir_build() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_aegir_build"
    debug_proc
  fi
  _LOCAL_STATUS="${_STATUS}"
  if [ -e "/run/aegir_upgrade.pid" ]; then
    _LOCAL_STATUS=INIT
  fi
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    cd ${_ROOT}
    _AGRPXSWD=$(cat ${_ROOT}/.${_USER}.pass.txt 2>&1)
    _AGRPASWD=$(echo -n ${_AGRPXSWD} | tr -d "\n" 2>&1)
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _THIS_DB_HOST=$(uname -n 2>&1)
      elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
        _SQL_CONNECT=127.0.0.1
        _THIS_DB_HOST=127.0.0.1
      else
        _THIS_DB_HOST=localhost
      fi
      _USE_AEGIR_HOST=$(uname -n 2>&1)
      _USE_DB_USER="${_USER}"
    else
      _USE_AEGIR_HOST=$(uname -n 2>&1)
      _USE_DB_USER=aegir_root
    fi
    if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
      _USE_AEGIR_HOST=$(uname -n 2>&1)
      _THIS_DB_HOST=$(uname -n 2>&1)
    fi
    _L_SYS_PHP="${_ROOT}/.${_USER}.pass.php"
    echo "<?php" > ${_L_SYS_PHP}
    echo "\$oct_db_user = \"${_USER}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_pass = \"${_AGRPASWD}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_port = \"${_THIS_DB_PORT}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_host = \"${_THIS_DB_HOST}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_dirs = \"/data/disk/${_USER}/backups\";" >> ${_L_SYS_PHP}
    chown ${_USER}:${_USRG} ${_L_SYS_PHP}
    chmod 0600 ${_L_SYS_PHP}

    msg "${_STATUS} B: Running hostmaster-install, please wait..."
    ${_DRUSHCMD} cc drush >${_ROOT}/log/install.log 2>&1
    rm -rf ${_ROOT}/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      ${_DRUSHCMD} hostmaster-install ${_DOMAIN} \
        --aegir_db_host=${_THIS_DB_HOST} \
        --aegir_db_port=${_THIS_DB_PORT} \
        --aegir_db_pass=${_AGRPASWD} \
        --aegir_db_user=${_USE_DB_USER} \
        --aegir_host=${_USE_AEGIR_HOST} \
        --aegir_root=${_ROOT} \
        --client_email=${_MY_EMAIL} \
        --http_service_type=nginx \
        --root=${_HM_ROOT} \
        --script_user=${_USER} \
        --web_group=${_WEBG} \
        --version=${_AEGIR_VERSION} -y -d
    else
      ${_DRUSHCMD} hostmaster-install ${_DOMAIN} \
        --aegir_db_host=${_THIS_DB_HOST} \
        --aegir_db_port=${_THIS_DB_PORT} \
        --aegir_db_pass=${_AGRPASWD} \
        --aegir_db_user=${_USE_DB_USER} \
        --aegir_host=${_USE_AEGIR_HOST} \
        --aegir_root=${_ROOT} \
        --client_email=${_MY_EMAIL} \
        --http_service_type=nginx \
        --root=${_HM_ROOT} \
        --script_user=${_USER} \
        --web_group=${_WEBG} \
        --version=${_AEGIR_VERSION} -y >${_ROOT}/log/install.log 2>&1
    fi
    rm -rf ${_HM_ROOT}/profiles/{default,standard,minimal,testing}
    cd ${_HM_ROOT}
    mkdir -p sites/all/{modules,themes,libraries}
    mkdir -p sites/${_DOMAIN}/files/{tmp,js,css}
    chmod 02775 -R sites/${_DOMAIN}/files &> /dev/null
    chgrp -R ${_WEBG} sites/${_DOMAIN}/files &> /dev/null
    rm -f ${_ROOT}/u/${_DOMAIN}
    ln -sfn ${_HM_ROOT} ${_ROOT}/u/${_DOMAIN}
    rm -f /data/u/${_DOMAIN} &> /dev/null
    ln -sfn ${_HM_ROOT} /data/u/${_DOMAIN}
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} B: Running hosting-dispatch/hosting-tasks..."
    fi
    ${_DRUSHCMD} @hostmaster hosting-dispatch &> /dev/null
    wait
    sleep 5
    ${_DRUSHCMD} @hostmaster hosting-tasks --force &> /dev/null
    wait
    sleep 5
    ${_DRUSHCMD} @hostmaster hosting-tasks --force &> /dev/null
    wait
    sleep 5
    ${_DRUSHCMD} @hostmaster hosting-tasks --force &> /dev/null
    wait
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} B: Testing previous install..."
    fi
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache

    ### Pre-Fix for migrated/merged instances
    if [ -e "${_ROOT}/log/imported.pid" ] || [ -e "${_ROOT}/log/exported.pid" ]; then
      if [ -e "${_ROOT}/aegir/distro/001/sites/${_DOMAIN}/drushrc.php" ]; then
        sed -i "s/platform_0.*'/platform_hostmaster'/g"    ${_ROOT}/.drush/hostmaster.alias.drushrc.php
        wait
        sed -i "s/distro\/0.*\/sites/distro\/001\/sites/g" ${_ROOT}/.drush/hostmaster.alias.drushrc.php
        wait
        sed -i "s/distro\/01.*',/distro\/001',/g"          ${_ROOT}/.drush/hostmaster.alias.drushrc.php
        wait
        sed -i "s/distro\/02.*',/distro\/001',/g"          ${_ROOT}/.drush/hostmaster.alias.drushrc.php
        wait
        sed -i "s/distro\/03.*',/distro\/001',/g"          ${_ROOT}/.drush/hostmaster.alias.drushrc.php
        wait
        sed -i "s/distro\/04.*',/distro\/001',/g"          ${_ROOT}/.drush/hostmaster.alias.drushrc.php
        wait
        sed -i "s/distro\/05.*',/distro\/001',/g"          ${_ROOT}/.drush/hostmaster.alias.drushrc.php
        wait
      fi
    fi

    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache
    if [ -d "${_HM_ROOT}/modules/o_contrib" ] \
      && [ ! -L "${_HM_ROOT}/modules/o_contrib" ]; then
      rm -f ${_HM_ROOT}/modules/o_contrib/{cache_backport,redis_edge,redis}
    fi
    if [ -d "${_PREV_HM_ROOT}/modules/o_contrib" ] \
      && [ ! -L "${_PREV_HM_ROOT}/modules/o_contrib" ]; then
      rm -f ${_PREV_HM_ROOT}/modules/o_contrib/{cache_backport,redis_edge,redis}
    fi
    if [ -d "${_HM_ROOT}/modules/o_contrib_seven" ] \
      && [ ! -L "${_HM_ROOT}/modules/o_contrib_seven" ]; then
      rm -f ${_HM_ROOT}/modules/o_contrib_seven/{cache_backport,redis_edge,redis}
    fi
    if [ -d "${_PREV_HM_ROOT}/modules/o_contrib_seven" ] \
      && [ ! -L "${_PREV_HM_ROOT}/modules/o_contrib_seven" ]; then
      rm -f ${_PREV_HM_ROOT}/modules/o_contrib_seven/{cache_backport,redis_edge,redis}
    fi
    if [ -e "${_PREV_HM_ROOT}/modules/path_alias_cache" ]; then
      _DEBUG_MODE=YES
    fi
    if [ ! -e "${_PREV_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
      _DEBUG_MODE=YES
      msg "${_STATUS} B: Testing previous install..."
      msg "${_STATUS} B: OPS, zombie found, moving it to backups..."
      mv -f ${_PREV_HM_ROOT} \
        ${_ROOT}/backups/system/empty-host-master-${_LAST_HMR}-${_NOW}
      cd ${_ROOT}/aegir/distro
      list=([0-9]*)
      last=${list[@]: -1}
      _L_LAST_HMR=$last
      _BASH_TEST=$(bash --version 2>&1)
      if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
        nextnum=00$((10#0${last%%[^0-9]*} + 1))
      else
        nextnum=00$((10#${last%%[^0-9]*} + 1))
      fi
      nextnum=${nextnum: -3}
      _L_HM_DISTRO=${nextnum}
      _HM_ROOT="${_ROOT}/aegir/distro/${_L_HM_DISTRO}"
      _PREV_HM_ROOT="${_ROOT}/aegir/distro/${_L_LAST_HMR}"
      msg "${_STATUS} B: Testing previous install again after removing zombie..."
      if [ ! -e "${_PREV_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
        _DEBUG_MODE=YES
        msg "${_STATUS} B: Testing previous install again..."
        msg "${_STATUS} B: OPS, another zombie found, moving it to backups..."
        mv -f ${_PREV_HM_ROOT} \
          ${_ROOT}/backups/system/empty-host-master-${_L_HM_DISTRO}-${_NOW}-sec
        cd ${_ROOT}/aegir/distro
        list=([0-9]*)
        last=${list[@]: -1}
        _L_LAST_HMR=$last
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          nextnum=00$((10#0${last%%[^0-9]*} + 1))
        else
          nextnum=00$((10#${last%%[^0-9]*} + 1))
        fi
        nextnum=${nextnum: -3}
        _L_HM_DISTRO=${nextnum}
        _HM_ROOT="${_ROOT}/aegir/distro/${_L_HM_DISTRO}"
        _PREV_HM_ROOT="${_ROOT}/aegir/distro/${_L_LAST_HMR}"
        msg "${_STATUS} B: Let's hope there are no more zombies left..."
      fi
    fi
    if [ -d "${_HM_ROOT}" ]; then
      msg "${_STATUS} B: FATAL ERROR: ${_HM_ROOT} already exists"
      msg "${_STATUS} B: FATAL ERROR: Too many zombies to delete! Try again..."
      msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
      touch /opt/tmp/status-AegirSetupB-FAIL
      exit 1
    fi
    msg "${_STATUS} B: Hostmaster STATUS: Upgrade in progress..."
    ### security_review breaks the upgrade if active
    mv -f ${_ROOT}/.drush/xts/security_review/security_review.drush.inc \
      ${_ROOT}/.drush/xts/security_review/foo.txt  &> /dev/null
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    if [ -z "${TERM+x}" ]; then
      export TERM=vt100
    fi

    #
    # Fix broken Entity module if needed.
    #
    pthA="profiles/hostmaster/modules/contrib/entity"
    pthB="module_filter.module"
    #
    if [ -e "${_PREV_HM_ROOT}/${pthA}/${pthB}" ]; then
      msg "${_STATUS} B: Fixing broken Entity module..."
      rm -rf ${_PREV_HM_ROOT}/${pthA}
      cd ${_PREV_HM_ROOT}/profiles/hostmaster/modules/contrib
      get_dev_stc "entity-7.x-1.11.tar.gz"
      ${_DRUSHCMD} @hostmaster en entity -y
      ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_service WHERE service LIKE 'http'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "INSERT INTO hosting_service (nid, vid, service, type, restart_cmd, port, available) VALUES ('2', '2', 'http', 'nginx_ssl', 'sudo /etc/init.d/nginx reload', '80', '1')" &> /dev/null
      ${_DRUSHCMD} @hostmaster hosting-task @server_master verify --force
      ${_DRUSHCMD} @hostmaster hosting-dispatch
      wait
      sleep 5
      ${_DRUSHCMD} @hostmaster hosting-tasks --force
      wait
      sleep 5
      ${_DRUSHCMD} @hostmaster hosting-tasks --force
      wait
      sleep 5
      ${_DRUSHCMD} @hostmaster hosting-tasks --force
      wait
      msg "${_STATUS} B: Waiting 15 seconds..."
      sleep 15
    fi

    if [ -e "${_PREV_HM_ROOT}/modules/path_alias_cache" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        ${_DRUSHCMD} @hostmaster dis aegir_custom_settings -y
        ${_DRUSHCMD} @hostmaster pm-uninstall aegir_custom_settings -y
        ${_DRUSHCMD} @hostmaster dis hosting_advanced_cron -y
        ${_DRUSHCMD} @hostmaster en ctools -y
        ${_DRUSHCMD} @hostmaster registry-rebuild
      else
        ${_DRUSHCMD} @hostmaster dis aegir_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster pm-uninstall aegir_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster dis hosting_advanced_cron -y &> /dev/null
        ${_DRUSHCMD} @hostmaster en ctools -y &> /dev/null
        ${_DRUSHCMD} @hostmaster registry-rebuild &> /dev/null
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        ${_DRUSHCMD} @hostmaster dis hosting_custom_settings -y
        ${_DRUSHCMD} @hostmaster pm-uninstall hosting_custom_settings -y
        ${_DRUSHCMD} @hostmaster registry-rebuild
      else
        ${_DRUSHCMD} @hostmaster dis hosting_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster pm-uninstall hosting_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster registry-rebuild &> /dev/null
      fi
    fi

    cd ${_PREV_HM_ROOT}
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache

    ${_DRUSHCMD} @hostmaster sqlc < ${bldPth}/aegir/helpers/hosting_cron.sql &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_task_log \
      WHERE timestamp < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 3 MONTH))" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "OPTIMIZE TABLE hosting_task_log" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_task \
      WHERE task_type='delete' AND task_status='-1'" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_task \
      WHERE task_type='delete' AND task_status='0' AND executed='0'" &> /dev/null

    ### Fix for migrated/merged instances
    if [ -e "${_ROOT}/log/imported.pid" ] \
      || [ -e "${_ROOT}/log/exported.pid" ]; then
      if [ ! -e "${_ROOT}/log/post-merge-fix.pid" ]; then
        msg "${_STATUS} B: Hostmaster STATUS: Fix for migrated/merged instance 1/2 start"
        _USE_AEGIR_HOST=$(uname -n 2>&1)
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO hosting_context (nid, name) \
          VALUES ('4', 'server_localhost'), ('2', 'server_master')" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO hosting_package (vid, nid, \
          package_type, short_name, old_short_name, description) VALUES ('6', \
          '6', 'platform', 'drupal', '', '')" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO node_revisions (nid, vid, \
          uid, title, body, teaser, log, timestamp, format) VALUES ('6', '6', \
          '1', 'drupal', '', '', '', '1412168340', '0')" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO node (nid, vid, type, \
          language, title, uid, status, created, changed, comment, promote, \
          moderate, sticky, tnid, translate) VALUES ('6', '6', 'package', '', \
          'drupal', '1', '1', '1412168321', '1412168340', '0', '0', '0', '0', \
          '0', '0')" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_package \
          WHERE nid='2' AND short_name='drupal'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_package \
          WHERE nid='4' AND short_name='drupal'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM node \
          WHERE nid='8' AND type='site'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM node_revisions \
          WHERE nid='8'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node \
          SET type='server' WHERE nid='2'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node \
          SET type='server' WHERE nid='4'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node \
          SET title='${_USE_AEGIR_HOST}' WHERE nid='2'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node \
          SET title='localhost' WHERE nid='4'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node_revision \
          SET title='${_USE_AEGIR_HOST}' WHERE nid='2'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node_revision \
          SET title='localhost' WHERE nid='4'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site \
          SET db_server='4' WHERE db_server='2'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
          SET web_server='2' WHERE web_server='0'" &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE users_roles \
          SET rid='7' WHERE rid='5'" &> /dev/null
        ${_DRUSHCMD} cc drush &> /dev/null
        rm -rf ${_ROOT}/.tmp/cache
        ${_DRUSHCMD} @hostmaster hosting-task @server_localhost \
          verify --force &> /dev/null
        ${_DRUSHCMD} @hostmaster hosting-dispatch &> /dev/null
        wait
        sleep 5
        ${_DRUSHCMD} @hostmaster hosting-tasks --force &> /dev/null
        wait
        sleep 5
        ${_DRUSHCMD} @hostmaster hosting-tasks --force &> /dev/null
        wait
        sleep 5
        ${_DRUSHCMD} @hostmaster hosting-tasks --force &> /dev/null
        wait
        msg "${_STATUS} B: Hostmaster STATUS: Fix for migrated/merged instance 1/2 complete"
      fi
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site \
        SET client='1' WHERE profile='7'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site \
        SET client='1' WHERE profile='9'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site \
        SET client='1' WHERE client='0'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
        SET web_server='2' WHERE web_server='0'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE node \
        SET uid='1' WHERE uid='0'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE node_revision \
        SET uid='1' WHERE uid='0'" &> /dev/null
      _HM_NID=$(${_DRUSHCMD} @hostmaster sqlq "SELECT site.nid \
        FROM hosting_site site JOIN hosting_package_instance pkgi \
        ON pkgi.rid=site.nid JOIN hosting_package pkg \
        ON pkg.nid=pkgi.package_id WHERE pkg.short_name='hostmaster'" 2>&1)
      _HM_NID=${_HM_NID//[^0-9]/}
      if [ ! -z "${_HM_NID}" ]; then
        msg "${_STATUS} B: Hostmaster STATUS: Fix 1/2 hosting_context ${_HM_NID}"
        if [ -e "${_ROOT}/aegir/distro/001/sites/${_DOMAIN}/drushrc.php" ]; then
          _HM_PLF=$(${_DRUSHCMD} @hostmaster sqlq "SELECT platform FROM hosting_site WHERE nid='${_HM_NID}'" 2>&1)
          _HM_PLF=${_HM_PLF//[^0-9]/}
          ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_context SET name='platform_hostmaster' WHERE nid='${_HM_PLF}'" &> /dev/null
        fi
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_context SET name='hostmaster' WHERE nid='${_HM_NID}'"         &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node SET title='${_DOMAIN}' WHERE nid='${_HM_NID}'"                   &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node_revision SET title='${_DOMAIN}' WHERE nid='${_HM_NID}'"          &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site_alias SET alias='www.${_DOMAIN}' WHERE nid='${_HM_NID}'" &> /dev/null
      else
        msg "${_STATUS} B: Hostmaster STATUS: Fix 1/2 hosting_context ${_HM_NID} empty!"
      fi
      if [ -e "${_ROOT}/aegir/distro/001/sites/${_DOMAIN}/drushrc.php" ] \
        && [ ! -e "${_ROOT}/log/hmpathfix.pid" ]; then
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
          SET publish_path='${_ROOT}/aegir/distro/001' \
          WHERE publish_path LIKE '%/aegir/distro/%'" &> /dev/null
        touch ${_ROOT}/log/hmpathfix.pid
      fi
    fi
    ### Fix for old migrated/merged instances

    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      ${_DRUSHCMD} hostmaster-migrate ${_DOMAIN} ${_HM_ROOT} -y -d
      ${_DRUSHCMD} @hostmaster registry-rebuild
    else
      ${_DRUSHCMD} hostmaster-migrate ${_DOMAIN} ${_HM_ROOT} -y &> /dev/null
      ${_DRUSHCMD} @hostmaster registry-rebuild &> /dev/null
    fi
    cd ${_HM_ROOT}
    mkdir -p sites/all/{modules,themes,libraries}
    export DEBIAN_FRONTEND=text
    mv -f ${_ROOT}/.drush/xts/security_review/foo.txt \
      ${_ROOT}/.drush/xts/security_review/security_review.drush.inc  &> /dev/null
    rm -f ${_ROOT}/u/${_DOMAIN}
    ln -sfn ${_HM_ROOT} ${_ROOT}/u/${_DOMAIN}
    rm -f /data/u/${_DOMAIN} &> /dev/null
    ln -sfn ${_HM_ROOT} /data/u/${_DOMAIN}
    rm -rf ${_HM_ROOT}/profiles/{default,standard,minimal,testing}

    ### Fix for migrated/merged instances
    if [ -e "${_ROOT}/log/imported.pid" ] \
      || [ -e "${_ROOT}/log/exported.pid" ]; then
      if [ ! -e "${_ROOT}/log/post-merge-fix.pid" ]; then
        msg "${_STATUS} B: Hostmaster STATUS: Fix for migrated/merged instance 2/2 start"
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE users_roles \
          SET rid='7' WHERE rid='5'" &> /dev/null
        echo FIXED > ${_ROOT}/log/post-merge-fix.pid
        msg "${_STATUS} B: Hostmaster STATUS: Fix for migrated/merged instance 2/2 complete"
      fi
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site \
        SET client='1' WHERE profile='7'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site \
        SET client='1' WHERE profile='9'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site \
        SET client='1' WHERE client='0'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
        SET web_server='2' WHERE web_server='0'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE node \
        SET uid='1' WHERE uid='0'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE node_revision \
        SET uid='1' WHERE uid='0'" &> /dev/null
      _HM_NID=$(${_DRUSHCMD} @hostmaster sqlq "SELECT site.nid \
        FROM hosting_site site JOIN hosting_package_instance pkgi \
        ON pkgi.rid=site.nid JOIN hosting_package pkg \
        ON pkg.nid=pkgi.package_id WHERE pkg.short_name='hostmaster'" 2>&1)
      _HM_NID=${_HM_NID//[^0-9]/}
      if [ ! -z "${_HM_NID}" ]; then
        msg "${_STATUS} B: Hostmaster STATUS: Fix 2/2 hosting_context ${_HM_NID}"
        if [ -e "${_ROOT}/aegir/distro/001/sites/${_DOMAIN}/drushrc.php" ]; then
          _HM_PLF=$(${_DRUSHCMD} @hostmaster sqlq "SELECT platform FROM hosting_site WHERE nid='${_HM_NID}'" 2>&1)
          _HM_PLF=${_HM_PLF//[^0-9]/}
          ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_context SET name='platform_hostmaster' WHERE nid='${_HM_PLF}'" &> /dev/null
        fi
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_context SET name='hostmaster' WHERE nid='${_HM_NID}'"         &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node SET title='${_DOMAIN}' WHERE nid='${_HM_NID}'"                   &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE node_revision SET title='${_DOMAIN}' WHERE nid='${_HM_NID}'"          &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_site_alias SET alias='www.${_DOMAIN}' WHERE nid='${_HM_NID}'" &> /dev/null
      else
        msg "${_STATUS} B: Hostmaster STATUS: Fix 2/2 hosting_context ${_HM_NID} empty!"
      fi
      if [ -e "${_ROOT}/aegir/distro/001/sites/${_DOMAIN}/drushrc.php" ] \
        && [ ! -e "${_ROOT}/log/hmpathfix.pid" ]; then
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
          SET publish_path='${_ROOT}/aegir/distro/001' \
          WHERE publish_path LIKE '%/aegir/distro/%'" &> /dev/null
        touch ${_ROOT}/log/hmpathfix.pid
      fi
    fi
    ### Fix for migrated/merged instances
    msg "${_STATUS} B: Hostmaster STATUS: Upgrade completed"
  fi
}

satellite_child_b_aegir_health_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_aegir_health_check"
    debug_proc
  fi
  ###--------------------###
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    _MSG_STATUS="install"
  else
    _MSG_STATUS="upgrade"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "${_STATUS} B: Simple check if Aegir ${_MSG_STATUS} is successful"
  fi
  if [ -e "${_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
    msg "${_STATUS} B: Aegir ${_MSG_STATUS} test result: OK"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "${_STATUS} B: Reloading Nginx..."
      sudo /etc/init.d/nginx reload
      wait
    else
      sudo /etc/init.d/nginx reload &> /dev/null
      wait
    fi
  else
    msg "${_STATUS} B: FATAL ERROR: Required file does not exist:"
    msg "${_STATUS} B: FATAL ERROR: ${_HM_ROOT}/sites/${_DOMAIN}/settings.php"
    msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
    touch /opt/tmp/status-AegirSetupB-FAIL
    exit 1
  fi
}

satellite_child_b_letsencrypt() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_letsencrypt"
    debug_proc
  fi
  leParams="--cron --ipv4"
  leRoot="${_ROOT}/tools/le"
  leKeyJ="${leRoot}/tools/le/private_key.json"
  leKeyP="${leRoot}/tools/le/private_key.pem"
  leCrtPath="${leRoot}/certs/${_DOMAIN}"
  exeLe="${leRoot}/dehydrated"
  pthLe="${_ROOT}/backups/system/dehydrated"
  mkdir -p ${_ROOT}/backups/system
  chmod 700 ${_ROOT}/backups/system
  rm -f ${_ROOT}/backups/system/letsencrypt*
  curl ${crlGet} "${urlHmr}/helpers/dehydrated" -o ${pthLe}
  if [ ! -e "${leRoot}" ]; then
    leSetup="YES"
  fi
  if [ -e "${pthLe}" ]; then
    mkdir -p ${leRoot}/.ctrl
    chmod 0711 ${leRoot}/.ctrl
    mkdir -p ${leRoot}/.acme-challenges
    chmod 0711 ${leRoot}/.acme-challenges
    mkdir -p ${leRoot}/certs
    chmod 0700 ${leRoot}/certs
    chmod 0711 ${leRoot}
    cp -af ${pthLe} ${exeLe}
    if [ -e "${exeLe}" ]; then
      chmod 0700 ${exeLe}
      if [ "${_STATUS}" = "INIT" ] \
        || [ "${leSetup}" = "YES" ] \
        || [ -e "${leRoot}/.ctrl/ssl-demo-mode.pid" ]; then
        touch ${leRoot}/.ctrl/ssl-demo-mode.pid
        echo -e 'CA="https://acme-staging-v02.api.letsencrypt.org/directory"\n' > ${leRoot}/config.sh
        cp -af ${leRoot}/config.sh ${leRoot}/config
        if [ -e "${leKeyJ}" ]; then
          mv -f ${leKeyJ} "${leKeyJ}-prev"
        fi
        if [ -e "${leKeyP}" ]; then
          mv -f ${leKeyP} "${leKeyP}-prev"
        fi
        echo ""
        msg "${_STATUS} B: Letsencrypt SSL mode: LIVE after auto-upgrade"
        echo ""
        msg "${_STATUS} B: LE -- !!! ATTENTION"
        msg "${_STATUS} B: LE -- Never enable SSL for the Hostmaster site in Aegir"
        msg "${_STATUS} B: LE -- The Hostmaster site SSL is auto-managed separately"
        msg "${_STATUS} B: LE -- !!! ATTENTION"
        echo ""
      fi
    else
      msg "${_STATUS} B: LE -- Missing ${exeLe} file?"
    fi
  fi
  if [ ! -e "${leRoot}/.ctrl/ssl-demo-mode.pid" ] \
    && [ -e "${leRoot}/config.sh" ]; then
    rm -f ${leRoot}/config.sh
    rm -f ${leRoot}/config
    if [ -e "${leKeyJ}" ]; then
      mv -f ${leKeyJ} "${leKeyJ}-prev"
    fi
    if [ -e "${leKeyP}" ]; then
      mv -f ${leKeyP} "${leKeyP}-prev"
    fi
  fi
  if [ -x "${exeLe}" ] \
    && [ ! -e "${leRoot}/.ctrl/ssl-demo-mode.pid" ] \
    && [ ! -e "${leRoot}/config.sh" ]; then
    if [ -e "${leCrtPath}/fullchain.pem" ]; then
      msg "${_STATUS} B: Updating Letsencrypt cert for Hostmaster..."
    else
      msg "${_STATUS} B: Creating Letsencrypt cert for Hostmaster..."
    fi
    onDemandRegPid="${leRoot}/.ctrl/onDemand-register.pid"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      if [ -e "${onDemandRegPid}" ]; then
        rm -rf ${leRoot}/accounts*
        bash ${exeLe} --register --accept-terms
        wait
        bash ${exeLe} --register --accept-terms
        wait
        bash ${exeLe} ${leParams} --domain ${_DOMAIN} --force
        wait
        touch ${leRoot}/.ctrl/forced-${_DOMAIN}-mode.pid
      else
        bash ${exeLe} --register --accept-terms
        wait
        bash ${exeLe} ${leParams} --domain ${_DOMAIN}
        wait
      fi
    else
      mkdir -p ${_ROOT}/log
      if [ -e "${onDemandRegPid}" ]; then
        rm -rf ${leRoot}/accounts*
        bash ${exeLe} --register --accept-terms >${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
        bash ${exeLe} --register --accept-terms >>${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
        bash ${exeLe} ${leParams} --domain ${_DOMAIN} --force >>${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
        touch ${leRoot}/.ctrl/forced-${_DOMAIN}-mode.pid
      else
        bash ${exeLe} --register --accept-terms >>${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
        bash ${exeLe} ${leParams} --domain ${_DOMAIN} >>${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
      fi
    fi
  else
    if [ -e "${leCrtPath}/fullchain.pem" ]; then
      rm -rf ${leCrtPath}
    fi
  fi
}

satellite_child_b_aegir_ui_enhance() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_aegir_ui_enhance"
    debug_proc
  fi
  msg "${_STATUS} B: Enhancing Aegir UI, please wait..."
  mkdir -p ${_HM_ROOT}/sites/all/{modules,themes,libraries}
  mkdir -p ${_HM_ROOT}/profiles/hostmaster/modules/{aegir,contrib}
  cd ${_HM_ROOT}/sites/${_DOMAIN}
  if [ -e "${_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
    _VM_TEST=$(uname -a 2>&1)
    if [[ "${_VM_TEST}" =~ "-beng" ]]; then
      _VMFAMILY="VS"
    else
      _VMFAMILY="XEN"
    fi
    cd ${_HM_ROOT}/sites/${_DOMAIN}
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache
    ${_DRUSHCMD} @hostmaster en aegir_objects -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en fix_ownership -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en fix_permissions -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_civicrm -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_civicrm_cron -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_client -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_cron -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_deploy -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_platform_composer -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_platform_composer_git -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_platform_git -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_tasks_extra -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_site_backup_manager -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_http_basic_auth -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en libraries -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en overlay -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en overlay_paths -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en revision_deletion -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en timeago -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en userprotect -y &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} client 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} clone 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} hosting_admin_client 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} hosting_client_register_user 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} hosting_client_send_welcome 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} hosting_client_send_welcome 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} hosting_feature_client 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_cron_default_interval 3600 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_queue_cron_frequency 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_civicrm_cron_queue_frequency 60 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_queue_task_gc_frequency 300 &> /dev/null
    if [ -e "${_ROOT}/log/hosting_cron_use_backend.txt" ]; then
      ${_DRUSHCMD} @hostmaster ${vSet} \
        hosting_cron_use_backend 1 &> /dev/null
    else
      ${_DRUSHCMD} @hostmaster ${vSet} \
        hosting_cron_use_backend 0 &> /dev/null
    fi
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_ignore_default_profiles 0 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_queue_tasks_frequency 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_queue_tasks_items 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_delete_force 0 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_alias_automatic_no_www 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_alias_automatic_www 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_upload_platform_path "${_ROOT}/static" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_upload_upload_path "sites/${_DOMAIN}/files/deployment" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_platform_base_path "${_ROOT}/static/" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      aegir_backup_export_path "${_ROOT}/backup-exports" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${vSet} \
      hosting_default_profile "standard" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM menu_links \
      WHERE link_path='hosting/platforms'" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM menu_links \
      WHERE link_path='hosting/sites'" &> /dev/null

    ${_DRUSHCMD} @hostmaster vdel -y --exact hosting_task_logs_types_display &> /dev/null

    ${_DRUSHCMD} @hostmaster ev 'variable_set("hosting_task_logs_types_display", array(
      "error" => "error",
      "info" => "info",
      "message" => "message",
      "notice" => "notice",
      "ok" => "ok",
      "status" => "status",
      "success" => "success",
      "warning" => "warning",
      "backup" => "backup",
      "bootstrap" => "bootstrap",
      "command" => "command",
      "debug" => "none",
      "debugnotify" => "none",
      "queue" => "queue"))' &> /dev/null

    if [ "${_LOCAL_STATUS}" = "INIT" ]; then
      pBy="Octopus System powered by Barracuda"
      ${_DRUSHCMD} @hostmaster ${vSet} site_name "${pBy}" &> /dev/null
      ${_DRUSHCMD} @hostmaster ${vSet} site_mail "${_MY_EMAIL}" &> /dev/null
      cp -af /opt/tmp/boa/aegir/helpers/make_home.php.txt ./
      mv -f make_home.php.txt make_home.php &> /dev/null
      ${_DRUSHCMD} php-script make_home &> /dev/null
      rm -f make_home.php
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE field_data_body \
        SET body_format='full_html' WHERE bundle='book' AND entity_type='node'" &> /dev/null
      cp -af /opt/tmp/boa/aegir/helpers/make_client.php.txt ./
      mv -f make_client.php.txt make_client.php &> /dev/null
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
          SET status=-1 WHERE nid=7" &> /dev/null
      else
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
          SET status=-1 WHERE nid=5" &> /dev/null
      fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        ${_DRUSHCMD} php-script make_client ${_CLIENT_EMAIL}
      else
        ${_DRUSHCMD} php-script make_client ${_CLIENT_EMAIL} &> /dev/null
      fi
      ### rm -f make_client.php
    else
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
        SET status=-2 WHERE publish_path LIKE '%/aegir/distro/%'" &> /dev/null
      _THIS_HM_PLR=$(cat ${_ROOT}/.drush/hostmaster.alias.drushrc.php \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
        SET status=1 WHERE publish_path LIKE '${_THIS_HM_PLR}'" &> /dev/null
      _CHECK_HOST=$(uname -n 2>&1)
      if_hosted_sys
      if [ "${hostedSys}" = "YES" ]; then
        pBy="Octopus System powered by Barracuda"
        ${_DRUSHCMD} @hostmaster ${vSet} site_name "${pBy}" &> /dev/null
        cp -af /opt/tmp/boa/aegir/helpers/make_home.php.txt ./
        mv -f make_home.php.txt make_home.php &> /dev/null
        ${_DRUSHCMD} php-script make_home &> /dev/null
        rm -f make_home.php
      fi
      ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM field_data_body \
        WHERE body_format IS NULL" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE field_data_body \
        SET body_format='full_html' WHERE bundle='book' AND entity_type='node'" &> /dev/null
    fi

    ${_DRUSHCMD} @hostmaster sqlq "UPDATE menu_links \
      SET hidden=1 WHERE plid='0' AND menu_name LIKE 'user-menu'" &> /dev/null

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_format"  &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_formats" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter"         &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_le -y
      ${_DRUSHCMD} @hostmaster en hosting_le_vhost -y
      ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y
      ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y
      ${_DRUSHCMD} @hostmaster cache-clear all
      ${_DRUSHCMD} @hostmaster updb -y
    else
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_format"  &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_formats" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter"         &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_le -y               &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_le_vhost -y         &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y  &> /dev/null
      ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y  &> /dev/null
      ${_DRUSHCMD} @hostmaster cache-clear all                &> /dev/null
      ${_DRUSHCMD} @hostmaster updb -y                        &> /dev/null
    fi

    if [ "${_LOCAL_STATUS}" = "INIT" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        ${_DRUSHCMD} @hostmaster \
          urol "admin" --mail=${_CLIENT_EMAIL}
        ${_DRUSHCMD} @hostmaster \
          urol "aegir account manager" --mail=${_CLIENT_EMAIL}
        ${_DRUSHCMD} @hostmaster \
          urol "aegir client" --mail=${_CLIENT_EMAIL}
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO userprotect \
          (uid, up_name, up_mail, up_pass, up_status, up_roles, up_cancel, up_edit, up_type, up_openid) VALUES \
          ('0', '0', '0', '0', '0', '0', '1', '1', 'user', '1'),\
          ('1', '0', '0', '0', '0', '0', '0', '0', 'admin', '0'),\
          ('1', '1', '1', '1', '1', '1', '1', '1', 'user', '1'),\
          ('2', '0', '0', '0', '1', '1', '1', '0', 'user', '1');"
      else
        ${_DRUSHCMD} @hostmaster \
          urol "admin" --mail=${_CLIENT_EMAIL} &> /dev/null
        ${_DRUSHCMD} @hostmaster \
          urol "aegir account manager" --mail=${_CLIENT_EMAIL} &> /dev/null
        ${_DRUSHCMD} @hostmaster \
          urol "aegir client" --mail=${_CLIENT_EMAIL} &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO userprotect \
          (uid, up_name, up_mail, up_pass, up_status, up_roles, up_cancel, up_edit, up_type, up_openid) VALUES \
          ('0', '0', '0', '0', '0', '0', '1', '1', 'user', '1'),\
          ('1', '0', '0', '0', '0', '0', '0', '0', 'admin', '0'),\
          ('1', '1', '1', '1', '1', '1', '1', '1', 'user', '1'),\
          ('2', '0', '0', '0', '1', '1', '1', '0', 'user', '1');" &> /dev/null
      fi
    fi

    if [ ! -e "${_ROOT}/log/hosting_le_enable.txt" ]; then
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_service SET type='nginx_ssl' WHERE service='http'" &> /dev/null
      wait
      ${_DRUSHCMD} @hostmaster hosting-task @server_master verify --force &> /dev/null
      wait
      mkdir -p ${_ROOT}/log
      touch ${_ROOT}/log/hosting_le_enable.txt
    fi
  fi
}

satellite_child_b_vhosts_hotfix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_vhosts_hotfix"
    debug_proc
  fi
  ###---### Make sure there are no ghost or disabled vhost which still listen on IP.
  #
  rPth="${_ROOT}/config/server"
  sed -i "s/.*listen .*127.0.0.1:80;.*//g"             ${rPth}_*/nginx.conf
  wait
  sed -i "s/listen .*\*:80;/listen        \*:80;/g"      ${rPth}_*/nginx.conf
  wait
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    sed -i "s/param db_port.*/param db_port   6033;/g" ${rPth}_*/nginx/vhost.d/*
  else
    sed -i "s/param db_port.*/param db_port   3306;/g" ${rPth}_*/nginx/vhost.d/*
  fi
  wait
  sed -i "s/listen .*\*:80;/listen        \*:80;/g"      ${rPth}_*/nginx/vhost.d/*
  wait
}

satellite_child_b_symlink_global_inc() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_symlink_global_inc"
    debug_proc
  fi
  cd ${_ROOT}
  if [ -e "/data/conf/global.inc" ]; then
    ln -sfn /data/conf/global.inc ${_ROOT}/config/includes/global.inc
  fi
}

satellite_child_b_redis_enable_finalize() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: satellite_child_b_redis_enable_finalize"
    debug_proc
  fi
  if [ -e "${_HM_ROOT}/modules/o_contrib" ]; then
    rm -rf ${_HM_ROOT}/modules/o_contrib
  fi
  if [ ! -e "${_HM_ROOT}/modules/o_contrib_seven/redis_edge" ]; then
    if [ -e "/data/all/000/modules/redis_edge" ]; then
      mkdir -p ${_HM_ROOT}/modules/o_contrib_seven
      rm -f ${_HM_ROOT}/modules/o_contrib_seven/{redis_edge,redis}
      ln -s /data/all/000/modules/redis_edge \
        ${_HM_ROOT}/modules/o_contrib_seven/redis_edge
    fi
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y
    ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y
    ${_DRUSHCMD} @hostmaster cache-clear all
  else
    ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y &> /dev/null
    ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y &> /dev/null
    ${_DRUSHCMD} @hostmaster cache-clear all &> /dev/null
  fi
  touch /opt/tmp/status-AegirSetupB-OK
}
