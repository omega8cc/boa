#
# Fix php.ini files to remove ionCube
fix_php_ini_ioncube() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_ioncube $1"
  fi
  if [ -e "${_THIS_FILE}" ] && [ "${_PHP_IONCUBE}" = "NO" ]; then
    _IONCUBE_INI_TEST=$(grep "ioncube_loader" ${_THIS_FILE} 2>&1)
    if [[ "${_IONCUBE_INI_TEST}" =~ "ioncube_loader" ]]; then
      sed -i "s/.*ioncube_loader.*//g" ${_THIS_FILE} &> /dev/null
      wait
    fi
  fi
}

#
# Fix php.ini files to remove jsmin.so
remove_php_ini_jsmin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: remove_php_ini_jsmin $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _JSMIN_INI_TEST=$(grep "^extension=jsmin.so" ${_THIS_FILE} 2>&1)
    if [[ "${_JSMIN_INI_TEST}" =~ "extension=jsmin.so" ]]; then
      sed -i "s/.*jsmin.*//g" ${_THIS_FILE} &> /dev/null
      wait
    fi
  fi
}

#
# Fix php.ini files to remove suhosin.so
remove_php_ini_suhosin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: remove_php_ini_suhosin $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _SUHOSIN_INI_TEST=$(grep "^extension=suhosin.so" ${_THIS_FILE} 2>&1)
    if [[ "${_SUHOSIN_INI_TEST}" =~ "extension=suhosin.so" ]]; then
      sed -i "s/.*suhosin.*//g" ${_THIS_FILE} &> /dev/null
      wait
    fi
  fi
}

#
# Fix php.ini files to add mailparse.so
fix_php_ini_mailparse() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_mailparse $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _MAILPARSE_INI_TEST=$(grep "^extension=mailparse.so" ${_THIS_FILE} 2>&1)
    if [[ "${_MAILPARSE_INI_TEST}" =~ "extension=mailparse.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=mailparse.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add yaml.so
fix_php_ini_yaml() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_yaml $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _YAML_INI_TEST=$(grep "^extension=yaml.so" ${_THIS_FILE} 2>&1)
    if [[ "${_YAML_INI_TEST}" =~ "extension=yaml.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=yaml.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add jsmin.so
add_php_ini_jsmin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: add_php_ini_jsmin $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _JSMIN_INI_TEST=$(grep "^extension=jsmin.so" ${_THIS_FILE} 2>&1)
    if [[ "${_JSMIN_INI_TEST}" =~ "extension=jsmin.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=jsmin.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add twig.so
fix_php_ini_twig() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_twig $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _TWIG_INI_TEST=$(grep "^extension=twig.so" ${_THIS_FILE} 2>&1)
    if [[ "${_TWIG_INI_TEST}" =~ "extension=twig.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=twig.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add redis.so
fix_php_ini_redis() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_redis $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _REDIS_INI_TEST=$(grep "^extension=redis.so" ${_THIS_FILE} 2>&1)
    if [[ "${_REDIS_INI_TEST}" =~ "extension=redis.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=redis.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add mcrypt.so
fix_php_ini_mcrypt() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_mcrypt $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _MCRYPT_INI_TEST=$(grep "^extension=mcrypt.so" ${_THIS_FILE} 2>&1)
    if [[ "${_MCRYPT_INI_TEST}" =~ "extension=mcrypt.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=mcrypt.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add apcu.so
fix_php_ini_apcu() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_apcu $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _APCU_INI_TEST=$(grep "^apc.shm_size" ${_THIS_FILE} 2>&1)
    if [[ "${_APCU_INI_TEST}" =~ "apc.shm_size" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=apcu.so" >> ${_THIS_FILE}
      echo "apc.shm_size=395M" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add igbinary.so
fix_php_ini_igbinary() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_igbinary $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _IGBINARY_INI_TEST=$(grep "^extension=igbinary.so" ${_THIS_FILE} 2>&1)
    if [[ "${_IGBINARY_INI_TEST}" =~ "extension=igbinary.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=igbinary.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini file to add newrelic.ini
fix_php_ini_newrelic() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_newrelic $1"
  fi
  _NR_TPL="${locCnf}/newrelic.ini"
  if [ -e "${_THIS_FILE}" ]; then
    _NEWRELIC_INI_TEST_A=$(grep "^extension=newrelic.so" ${_THIS_FILE} 2>&1)
    if [[ "${_NEWRELIC_INI_TEST_A}" =~ "extension=newrelic.so" ]]; then
      _DO_NOTHING=YES
    else
      cat ${_NR_TPL} >> ${_THIS_FILE}
    fi
    _NEWRELIC_INI_TEST_B=$(grep "newrelic.framework.drupal.modules" ${_THIS_FILE} 2>&1)
    if [[ "${_NEWRELIC_INI_TEST_B}" =~ "newrelic.framework.drupal.modules" ]]; then
      _DO_NOTHING=YES
    else
      echo "newrelic.framework.drupal.modules = 1" >> ${_THIS_FILE}
    fi
    sed -i "/REPLACE_WITH_REAL_KEY//g" ${_THIS_FILE} &> /dev/null
    wait
    sed -i "s/license_key=//g" ${_THIS_FILE} &> /dev/null
    wait
  fi
}

#
# Fix all php.ini files to add newrelic.ini
fix_php_ini_newrelic_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_newrelic_all $1"
  fi
  if [ -e "/etc/newrelic/newrelic.cfg" ]; then
    if [ -z "${_NEWRELIC_KEY}" ]; then
      _NEWRELIC_KEY=$(grep license_key /etc/newrelic/newrelic.cfg 2>&1)
      _NEWRELIC_KEY=$(echo -n ${_NEWRELIC_KEY} | tr -d "\n" 2>&1)
    fi
    _PHP_V="83 82 81 80 74 73 72 71 70"
    if [ "${_DB_SERIES}" = "5.7" ]; then
      _PHP_V="83 82 81 80 74 73 72 71 70"
    fi
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_newrelic ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_newrelic ${e}
    done
  fi
}

#
# Fix FMP php.ini file to add opcache.so
fix_php_ini_opcache() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_opcache $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _OPCACHE_INI_TEST=$(grep "opcache.so" ${_THIS_FILE} 2>&1)
    if [[ "${_OPCACHE_INI_TEST}" =~ "opcache.so" ]]; then
      _DO_NOTHING=YES
    else
      echo ";"                                    >> ${_THIS_FILE}
      echo "; Zend OPcache"                       >> ${_THIS_FILE}
      echo "zend_extension=\"${_OPCACHE_SO}\""    >> ${_THIS_FILE}
      echo "opcache.enable=1"                     >> ${_THIS_FILE}
      echo "opcache.memory_consumption=181"       >> ${_THIS_FILE}
      echo "opcache.revalidate_freq=10"           >> ${_THIS_FILE}
      echo ";"                                    >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix all FMP php.ini files to add Zend OPcache
fix_php_ini_opcache_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_opcache_all"
  fi
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  if [ "${_DB_SERIES}" = "5.7" ]; then
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
  fi
  for e in ${_PHP_V}; do
    _P_API=
    case "${e}" in
      83) _P_API="${_PHP83_API}" ;;
      82) _P_API="${_PHP82_API}" ;;
      81) _P_API="${_PHP81_API}" ;;
      80) _P_API="${_PHP80_API}" ;;
      74) _P_API="${_PHP74_API}" ;;
      73) _P_API="${_PHP73_API}" ;;
      72) _P_API="${_PHP72_API}" ;;
      71) _P_API="${_PHP71_API}" ;;
      70) _P_API="${_PHP70_API}" ;;
      56) _P_API="${_PHP56_API}" ;;
      *)  msg "WARN: Unknown PHP API version for PHP ${e}"
      ;;
    esac
    _THIS_FILE=/opt/php${e}/etc/php${e}.ini
    _OPCACHE_LP="/opt/php${e}/lib/php/extensions/no-debug-non-zts"
    _OPCACHE_SO="${_OPCACHE_LP}-${_P_API}/opcache.so"
    fix_php_ini_opcache ${e}
  done
}

#
# Fix php.ini file to add php_tet.so
fix_php_ini_tet() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_tet $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _TET_INI_TEST=$(grep "^extension=php_tet.so" ${_THIS_FILE} 2>&1)
    if [[ "${_TET_INI_TEST}" =~ "extension=php_tet.so" ]]; then
      _DO_NOTHING=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "PROC: php_tet.so already present in ${_THIS_FILE}"
      fi
    else
      echo "extension=php_tet.so" >> ${_THIS_FILE}
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "PROC: Just added php_tet.so to ${_THIS_FILE}"
      fi
    fi
  fi
}

#
# Fix all php.ini files to add php_tet.so
fix_php_ini_tet_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_tet_all"
  fi
  if [ "${_PHP_TET}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "TET" ]]; then
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      _P_API=
      case "${e}" in
        83) _P_API="${_PHP83_API}" ;;
        82) _P_API="${_PHP82_API}" ;;
        81) _P_API="${_PHP81_API}" ;;
        80) _P_API="${_PHP80_API}" ;;
        74) _P_API="${_PHP74_API}" ;;
        73) _P_API="${_PHP73_API}" ;;
        72) _P_API="${_PHP72_API}" ;;
        71) _P_API="${_PHP71_API}" ;;
        70) _P_API="${_PHP70_API}" ;;
        56) _P_API="${_PHP56_API}" ;;
        *)  msg "WARN: Unknown PHP API version for PHP ${e}"
        ;;
      esac
      _TET_BASE="/opt/php${e}/lib/php/extensions/no-debug-non-zts"
      _TET_SO="${_TET_BASE}-${_P_API}/php_tet.so"
      if [ ! -e "${_TET_SO}" ]; then
        if [[ "${e}" =~ "83" ]] \
          || [[ "${e}" =~ "82" ]] \
          || [[ "${e}" =~ "81" ]] \
          || [[ "${e}" =~ "80" ]] \
          || [[ "${e}" =~ "74" ]] \
          || [[ "${e}" =~ "73" ]]; then
          _TET_VRN="5.3-Linux-x64-Perl-PHP-Python-Ruby"
        else
          _TET_VRN="5.2-Linux-x86_64-Perl-PHP-Python-Ruby"
        fi
        if [ ! -e "/var/opt/TET-${_TET_VRN}/bind/php" ]; then
          mkdir -p  /var/opt
          cd /var/opt
          get_dev_src "TET-${_TET_VRN}.tar.gz"
        fi
        if [ -e "/var/opt/TET-${_TET_VRN}/bind/php/php-${e}0-nts" ]; then
          cd /var/opt/TET-${_TET_VRN}/bind/php/php-${e}0-nts/
          cp -a php_tet.so ${_TET_SO}
        fi
      fi
      if [ -e "${_TET_SO}" ]; then
        _THIS_FILE=/opt/php${e}/etc/php${e}.ini
        fix_php_ini_tet ${e}
        _THIS_FILE=/opt/php${e}/lib/php.ini
        fix_php_ini_tet ${e}
      fi
    done
  fi
}

#
# Fix php.ini file to add geos.so
fix_php_ini_geos() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_geos $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _GEOS_INI_TEST=$(grep "^extension=geos.so" ${_THIS_FILE} 2>&1)
    if [[ "${_GEOS_INI_TEST}" =~ "extension=geos.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=geos.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix all php.ini files to add geos.so
fix_php_ini_geos_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_geos_all"
  fi
  if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
    _PHP_V="56"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_geos ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_geos ${e}
    done
  fi
}

#
# Fix php.ini file to add mongo.so
fix_php_ini_mongo() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_mongo $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _MONGO_INI_TEST=$(grep "^extension=mongo.so" ${_THIS_FILE} 2>&1)
    if [[ "${_MONGO_INI_TEST}" =~ "extension=mongo.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=mongo.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini file to add mongodb.so
fix_php_ini_mongodb() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_mongodb $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _MONGODB_INI_TEST=$(grep "^extension=mongodb.so" ${_THIS_FILE} 2>&1)
    if [[ "${_MONGODB_INI_TEST}" =~ "extension=mongodb.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=mongodb.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix all php.ini files to add mongo.so or mongodb.so
fix_php_ini_mongo_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_php_ini_mongo_all"
  fi
  if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
    _PHP_V="56"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_mongo ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_mongo ${e}
    done
    _PHP_V="72 71 70"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_mongodb ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_mongodb ${e}
    done
  fi
}

#
# Update PHP Config.
php_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_conf_update"
  fi
  if [ -z "${_THISHTIP}" ]; then
    _LOC_DOM="${_THISHOST}"
    find_correct_ip
    _THISHTIP="${_LOC_IP}"
  fi
  if [ ! -e "/opt/etc/fpm" ] \
    || [ ! -e "/opt/etc/fpm/fpm-pool-common.conf" ]; then
    mkdir -p /opt/etc/fpm
  fi
  cp -af ${locCnf}/fpm-pool-common.conf /opt/etc/fpm/fpm-pool-common.conf
  sed -i "s/127.0.0.1/127.0.0.1,${_THISHTIP}/g" /opt/etc/fpm/fpm-pool-common.conf
  wait
  sed -i "s/mode =.*/mode = 0660/g" /opt/etc/fpm/fpm-pool-common.conf
  wait
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  if [ "${_DB_SERIES}" = "5.7" ]; then
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
  fi
  for e in ${_PHP_V}; do
    if [ ! -e "/var/www/www${e}" ]; then
      adduser --system --group --home /var/www/www${e} www${e} &> /dev/null
      usermod -aG www-data www${e}
    fi
    if [ ! -e "/opt/php${e}/etc/php${e}.ini" ] \
      || [ ! -e "/opt/php${e}/etc/pool.d/www${e}.conf" ]; then
      mkdir -p /opt/php${e}/etc/pool.d
      cp -af ${locCnf}/php${e}.ini /opt/php${e}/etc/php${e}.ini
    fi
    cp -af ${locCnf}/fpm${e}-pool-www.conf /opt/php${e}/etc/pool.d/www${e}.conf
    if [ ! -e "/opt/php${e}/lib/php.ini" ]; then
      mkdir -p /opt/php${e}/lib
      cp -af ${locCnf}/php${e}-cli.ini /opt/php${e}/lib/php.ini
    fi
    cp -af ${locCnf}/php${e}.ini /opt/php${e}/etc/php${e}.ini
    cp -af ${locCnf}/php${e}-cli.ini /opt/php${e}/lib/php.ini
    cp -af ${locCnf}/php${e}-fpm.conf /opt/php${e}/etc/php${e}-fpm.conf

    _THIS_FILE=/opt/php${e}/etc/php${e}.ini
    if [ "${e}" != "56" ]; then
      fix_php_ini_apcu ${e}
    fi
    if [ "${e}" != "56" ] && [ "${e}" != "70" ] && [ "${e}" != "71" ]; then
      fix_php_ini_mcrypt ${e}
    fi
    if [ "${e}" = "56" ]; then
      fix_php_ini_mailparse ${e}
      fix_php_ini_twig ${e}
    fi
    if [ "${e}" != "80" ] && [ "${e}" != "81" ] && [ "${e}" != "82" ] && [ "${e}" != "83" ]; then
      add_php_ini_jsmin ${e}
    fi
    if [ "${e}" = "80" ] || [ "${e}" = "81" ] || [ "${e}" = "82" ] || [ "${e}" = "83" ]; then
      remove_php_ini_jsmin ${e}
    fi
    fix_php_ini_igbinary ${e}
    fix_php_ini_redis ${e}
    fix_php_ini_ioncube ${e}
    remove_php_ini_suhosin ${e}
    fix_php_ini_yaml ${e}

    _THIS_FILE=/opt/php${e}/lib/php.ini
    if [ "${e}" != "56" ]; then
      fix_php_ini_apcu ${e}
    fi
    if [ "${e}" != "56" ] && [ "${e}" != "70" ] && [ "${e}" != "71" ]; then
      fix_php_ini_mcrypt ${e}
    fi
    if [ "${e}" = "56" ]; then
      fix_php_ini_mailparse ${e}
      fix_php_ini_twig ${e}
    fi
    if [ "${e}" != "80" ] && [ "${e}" != "81" ] && [ "${e}" != "82" ] && [ "${e}" != "83" ]; then
      add_php_ini_jsmin ${e}
    fi
    if [ "${e}" = "80" ] || [ "${e}" = "81" ] || [ "${e}" = "82" ] || [ "${e}" = "83" ]; then
      remove_php_ini_jsmin ${e}
    fi
    fix_php_ini_igbinary ${e}
    fix_php_ini_redis ${e}
    fix_php_ini_ioncube ${e}
    remove_php_ini_suhosin ${e}
    fix_php_ini_yaml ${e}

    if [ -e "/opt/php${e}/etc/php${e}.ini" ]; then
      sed -i "s/^zlib.output_compression.*/zlib.output_compression = Off/g"       /opt/php${e}/etc/php${e}.ini
      wait
      sed -i "s/.*zlib.output_compression_level/;zlib.output_compression_level/g" /opt/php${e}/etc/php${e}.ini
      wait
    fi
    if [ -e "/opt/php${e}/lib/php.ini" ]; then
      sed -i "s/^zlib.output_compression.*/zlib.output_compression = Off/g"       /opt/php${e}/lib/php.ini
      wait
      sed -i "s/.*zlib.output_compression_level/;zlib.output_compression_level/g" /opt/php${e}/lib/php.ini
      wait
    fi
  done
  rm -f /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
  rm -f /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
  fix_php_ini_newrelic_all
  fix_php_ini_geos_all
  fix_php_ini_mongo_all
  fix_php_ini_tet_all
  fix_php_ini_opcache_all
}

#
# Check PHP Config.
php_config_check_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_config_check_update"
  fi
  php_conf_update
  boa_ini_tpl_update
}

#
# Tune Web Sever configuration.
tune_web_server_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: tune_web_server_config"
  fi
  _LIM_FPM="${_L_PHP_FPM_WORKERS}"
  if [ "${_LIM_FPM}" -lt "48" ]; then
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]]; then
      _LIM_FPM=48
    fi
  fi
  _CHILD_MAX_FPM=$(( _LIM_FPM * 2 ))
  if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
    _DO_NOTHING=YES
  else
    _PHP_FPM_WORKERS=${_PHP_FPM_WORKERS//[^0-9]/}
    if [ ! -z "${_PHP_FPM_WORKERS}" ] && [ "${_PHP_FPM_WORKERS}" -gt "0" ]; then
      _CHILD_MAX_FPM="${_PHP_FPM_WORKERS}"
    fi
  fi
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  if [ "${_DB_SERIES}" = "5.7" ]; then
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
  fi
  for e in ${_PHP_V}; do
    sed -i "s/pm.max_children =.*/pm.max_children = ${_CHILD_MAX_FPM}/g" \
      /opt/php${e}/etc/pool.d/www${e}.conf &> /dev/null
    wait
    if [ ! -z "${_PHP_FPM_DENY}" ]; then
      sed -i "s/passthru,/${_PHP_FPM_DENY},/g" \
        /opt/php${e}/etc/pool.d/www${e}.conf &> /dev/null
      wait
    fi
  done
  # PHP-FPM INI
  sed -i "s/^default_socket_timeout =.*/default_socket_timeout = 180/g" /opt/php*/etc/php*.ini &> /dev/null
  wait
  sed -i "s/^max_execution_time =.*/max_execution_time = 180/g" /opt/php*/etc/php*.ini         &> /dev/null
  wait
  sed -i "s/^max_input_time =.*/max_input_time = 180/g" /opt/php*/etc/php*.ini                 &> /dev/null
  wait
  # PHP-CLI INI
  sed -i "s/^default_socket_timeout =.*/default_socket_timeout = 3600/g" /opt/php*/lib/php.ini &> /dev/null
  wait
  sed -i "s/^max_execution_time =.*/max_execution_time = 3600/g" /opt/php*/lib/php.ini         &> /dev/null
  wait
  sed -i "s/^max_input_time =.*/max_input_time = 3600/g" /opt/php*/lib/php.ini                 &> /dev/null
  wait
  # Redis config should sync with PHP-CLI
  sed -i "s/^timeout .*/timeout 3600/g" /etc/redis/redis.conf                                  &> /dev/null
  wait
}

#
# Install IonCube.
if_install_php_ioncube() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_php_ioncube"
  fi
  ###--------------------###
  _X86_64_TEST=$(uname -m 2>&1)
  if [ "${_X86_64_TEST}" = "x86_64" ]; then
    _SYSTEM_ARCH="x64"
  else
    _SYSTEM_ARCH="x32"
  fi
  if [ "${_PHP_IONCUBE}" = "YES" ] && [ "${_SYSTEM_ARCH}" = "x64" ]; then
    if [ ! -e "${pthLog}/ioncube-update-${_IONCUBE_VRN}.log" ] \
      || [ ! -e "/usr/local/ioncube" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      mkdir -p /usr/local/ioncube
      msg "INFO: Installing IonCube ${_IONCUBE_VRN} for PHP..."
      cd /var/opt
      rm -rf ioncube_loaders*
      get_dev_arch "ioncube_loaders_lin_x86-64_${_IONCUBE_VRN}.tar.gz"
      rm -f /usr/local/ioncube/*
      cp -af /var/opt/ioncube/* /usr/local/ioncube/ &> /dev/null
      touch ${pthLog}/ioncube-update-${_IONCUBE_VRN}.log
    fi
  fi
}

#
# Install PHP extensions.
install_php_extensions() {
  if [ ! -e "${pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    pthLog="/var/xdrago_wait/log"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_php_extensions $1"
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _USE_PHPREDIS="${_PHPREDIS_FOUR_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  elif [ "$1" = "70" ] || [ "$1" = "71" ]; then
    _USE_PHPREDIS="${_PHPREDIS_FIVE_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  else
    _USE_PHPREDIS="${_PHPREDIS_SIX_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  fi
  msg "INFO: Installing PhpRedis ${_USE_PHPREDIS} for PHP ${_T_PHP_VRN}..."
  ldconfig 2> /dev/null
  cd /var/opt
  rm -rf phpredis*
  get_dev_src "phpredis-${_USE_PHPREDIS}.tar.gz"
  cd /var/opt/phpredis
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "bash ./configure ${_PHPREDIS_BUILD} --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make -j $(nproc) --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/redis.so" ]; then
    msg "WARN: Installing PhpRedis for PHP ${_T_PHP_VRN} failed!"
  else
    touch ${pthLog}/phpredis-update-${_USE_PHPREDIS}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" != "56" ]; then
    msg "INFO: Installing APCu ${_PHP_APCU} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf apcu*
    get_dev_src "apcu-${_PHP_APCU}.tgz"
    cd /var/opt/apcu-${_PHP_APCU}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/apcu.so" ]; then
      msg "WARN: Installing APCu for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/apcu-${_PHP_APCU}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _USE_IGBINARY="${_PHP_IGBINARY_TWO}"
  else
    _USE_IGBINARY="${_PHP_IGBINARY_THREE}"
  fi
  msg "INFO: Installing igbinary ${_USE_IGBINARY} for PHP ${_T_PHP_VRN}..."
  cd /var/opt
  rm -rf igbinary*
  get_dev_src "igbinary-${_USE_IGBINARY}.tgz"
  cd /var/opt/igbinary-${_USE_IGBINARY}
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make -j $(nproc) --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/igbinary.so" ]; then
    msg "WARN: Installing igbinary for PHP ${_T_PHP_VRN} failed!"
  else
    touch ${pthLog}/igbinary-${_USE_IGBINARY}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" != "56" ] && [ "$1" != "70" ] && [ "$1" != "71" ]; then
    msg "INFO: Installing MCRYPT ${_PHP_MCRYPT} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf mcrypt*
    get_dev_src "mcrypt-${_PHP_MCRYPT}.tgz"
    cd /var/opt/mcrypt-${_PHP_MCRYPT}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mcrypt.so" ]; then
      msg "WARN: Installing MCRYPT for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/mcrypt-${_PHP_MCRYPT}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    msg "INFO: Installing UploadProgress ${_UPROGRESS_LEGACY_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    get_dev_src "uploadprogress-${_UPROGRESS_LEGACY_VRN}.tgz"
    cd /var/opt/uploadprogress-${_UPROGRESS_LEGACY_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
      msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/f_uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log
    fi
  elif [ "$1" = "72" ] \
    || [ "$1" = "73" ] \
    || [ "$1" = "74" ] \
    || [ "$1" = "80" ] \
    || [ "$1" = "81" ] \
    || [ "$1" = "82" ] \
    || [ "$1" = "83" ]; then
    msg "INFO: Installing UploadProgress ${_UPROGRESS_EIGHT_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    get_dev_src "uploadprogress-${_UPROGRESS_EIGHT_VRN}.tgz"
    cd /var/opt/uploadprogress-${_UPROGRESS_EIGHT_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
      msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/f_uploadprogress-${_UPROGRESS_EIGHT_VRN}-${_T_PHP_VRN}.log
    fi
  else
    msg "INFO: Installing UploadProgress ${_UPROGRESS_SEVEN_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    get_dev_src "uploadprogress-${_UPROGRESS_SEVEN_VRN}.tar.gz"
    cd /var/opt/uploadprogress-${_UPROGRESS_SEVEN_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
      msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/f_uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  cd /var/opt
  rm -rf pecl-jsmin*
  if [ "$1" = "56" ]; then
    msg "INFO: Installing JSMin ${_JSMIN_PHP_LEGACY_VRN} for PHP ${_T_PHP_VRN}..."
    get_dev_src "pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}.tar.gz"
    cd /var/opt/pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}
  else
    msg "INFO: Installing JSMin ${_JSMIN_PHP_MODERN_VRN} for PHP ${_T_PHP_VRN}..."
    get_dev_src "pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}.tar.gz"
    cd /var/opt/pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}
  fi
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make -j $(nproc) --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ]; then
    msg "WARN: Installing JSMin for PHP ${_T_PHP_VRN} failed!"
  else
    if [ "$1" = "56" ]; then
      touch ${pthLog}/php-pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
    else
      touch ${pthLog}/php-pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
    fi
  fi

  ###--------------------###
  if [ "$1" = "56" ]; then
    msg "INFO: Installing Twig C ${_TWIGC_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf twig*
    get_dev_src "twig-${_TWIGC_VRN}.tar.gz"
    cd /var/opt/twig-${_TWIGC_VRN}/ext/twig
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/twig.so" ]; then
      msg "WARN: Installing Twig C for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
    if [ "$1" = "56" ]; then
      msg "INFO: Building GEOS extension ${_GEOS_VRN} for PHP ${_T_PHP_VRN} from sources..."
      if [ ! -e "${pthLog}/geos-${_X_SE}-${_X_VERSION}.log" ]; then
        apt_clean_update
        st_runner "${_INSTAPP} libgeos-dev libgeos-c1" 2> /dev/null
        touch ${pthLog}/geos-${_X_SE}-${_X_VERSION}.log
      fi
      cd /var/opt
      rm -rf geos*
      get_dev_src "geos-${_GEOS_VRN}.tar.bz2"
      cd geos-${_GEOS_VRN}
      _PHP_V="56"
      for e in ${_PHP_V}; do
        if [ "$1" = "${e}" ]; then
          find . -type f -print0 \
            | xargs -0 sed -i 's/\/usr\/local/\/opt\/php${e}/g' &> /dev/null
          wait
        fi
      done
      mrun "bash ./configure --enable-php" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      touch ${pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
    if [ "$1" = "56" ]; then
      msg "INFO: Installing MongoDB driver ${_MONGO_VRN} for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongo*
      get_dev_src "mongo-${_MONGO_VRN}.tgz"
      cd /var/opt/mongo-${_MONGO_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log
      fi
    else
      msg "INFO: Installing MongoDB driver ${_MONGODB_VRN} for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongodb*
      get_dev_src "mongodb-${_MONGODB_VRN}.tgz"
      cd /var/opt/mongodb-${_MONGODB_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  msg "INFO: Installing Imagick ${_IMAGICK_VRN} for PHP ${_T_PHP_VRN}..."
  if [ "${_OS_CODE}" = "daedalus" ] || [ "${_OS_CODE}" = "chimaera" ]; then
    if [ -e "/usr/bin/MagickWand-config" ]; then
      mv -f /usr/bin/MagickWand-config /var/backups/usr-bin-MagickWand-config
    fi
    if [ -e "/usr/local/bin/MagickWand-config" ]; then
      mv -f /usr/local/bin/MagickWand-config /var/backups/usr-local-bin-MagickWand-config
    fi
  fi
  if [ ! -e "${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log" ]; then
    apt_clean_update
    mrun "${_INSTAPP} libmagickwand-dev" 2> /dev/null
    touch ${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log
  fi
  cd /var/opt
  rm -rf imagick*
  get_dev_src "imagick-${_IMAGICK_VRN}.tgz"
  cd /var/opt/imagick-${_IMAGICK_VRN}
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make -j $(nproc) --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/imagick.so" ]; then
    msg "WARN: Installing Imagick for PHP ${_T_PHP_VRN} failed!"
  else
    touch ${pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    msg "INFO: Installing MailParse ${_MAILPARSE_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf mailparse*
    get_dev_src "mailparse-${_MAILPARSE_VRN}.tgz"
    cd /var/opt/mailparse-${_MAILPARSE_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mailparse.so" ]; then
      msg "WARN: Installing MailParse for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ ! -e "${pthLog}/f_libyaml-${_LIB_YAML_VRN}.log" ] \
    || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ]; then
    msg "INFO: Installing LibYAML ${_LIB_YAML_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf yaml*
    get_dev_src "yaml-${_LIB_YAML_VRN}.tar.gz"
    cd /var/opt/yaml-${_LIB_YAML_VRN}
    mrun "sh ./bootstrap" 2> /dev/null
    mrun "bash ./configure --prefix=/usr" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    touch ${pthLog}/f_libyaml-${_LIB_YAML_VRN}.log
    rm -f ${pthLog}/yaml*.log
    rm -f ${pthLog}/f_yaml*.log
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      if [ ! -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.9" ] \
        || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ]; then
        mkdir -p /var/backups/libyaml
        mkdir -p /usr/lib/x86_64-linux-gnu
        cp -af /usr/lib/x86_64-linux-gnu/libyaml* /var/backups/libyaml/ &> /dev/null
        if [ -e "/usr/lib/libyaml-0.so.2.0.9" ]; then
          rm -f /usr/lib/x86_64-linux-gnu/libyaml*
          rm -f /usr/lib/libyaml-0.so.2.0.4
        fi
        cp -af /usr/lib/libyaml* /usr/lib/x86_64-linux-gnu/ &> /dev/null
      fi
    fi
  fi
  cd /var/opt
  rm -rf yaml*
  if [ "$1" = "56" ]; then
    msg "INFO: Installing YAML ${_YAML_PHP_LEGACY_VRN} for PHP ${_T_PHP_VRN}..."
    get_dev_src "yaml-${_YAML_PHP_LEGACY_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_PHP_LEGACY_VRN}
  elif [ "$1" = "70" ]; then
    msg "INFO: Installing YAML ${_YAML_PHP_SEVENO_VRN} for PHP ${_T_PHP_VRN}..."
    get_dev_src "yaml-${_YAML_PHP_SEVENO_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_PHP_SEVENO_VRN}
  else
    msg "INFO: Installing YAML ${_YAML_PHP_MODERN_VRN} for PHP ${_T_PHP_VRN}..."
    get_dev_src "yaml-${_YAML_PHP_MODERN_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_PHP_MODERN_VRN}
  fi
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make -j $(nproc) --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
    msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
  else
    if [ "$1" = "56" ]; then
      touch ${pthLog}/f_yaml-${_YAML_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
    elif [ "$1" = "70" ]; then
      touch ${pthLog}/f_yaml-${_YAML_PHP_SEVENO_VRN}-${_T_PHP_VRN}.log
    else
      touch ${pthLog}/f_yaml-${_YAML_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
    fi
  fi
}

#
# Update extensions for PHP built from sources.
php_extensions_update() {
  if [ ! -e "${pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    pthLog="/var/xdrago_wait/log"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_extensions_update $1"
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _USE_PHPREDIS="${_PHPREDIS_FOUR_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  elif [ "$1" = "70" ] || [ "$1" = "71" ]; then
    _USE_PHPREDIS="${_PHPREDIS_FIVE_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  else
    _USE_PHPREDIS="${_PHPREDIS_SIX_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  fi
  if [ ! -e "${pthLog}/phpredis-update-${_USE_PHPREDIS}-${_T_PHP_VRN}.log" ]; then
    msg "INFO: Installing PhpRedis ${_USE_PHPREDIS} upgrade for PHP ${_T_PHP_VRN}..."
    ldconfig 2> /dev/null
    cd /var/opt
    rm -rf phpredis*
    get_dev_src "phpredis-${_USE_PHPREDIS}.tar.gz"
    cd /var/opt/phpredis
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure ${_PHPREDIS_BUILD} --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/redis.so" ]; then
      msg "WARN: Installing PhpRedis for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/phpredis-update-${_USE_PHPREDIS}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" != "56" ]; then
    if [ ! -e "${pthLog}/apcu-${_PHP_APCU}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing APCu ${_PHP_APCU} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf apcu*
      get_dev_src "apcu-${_PHP_APCU}.tgz"
      cd /var/opt/apcu-${_PHP_APCU}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/apcu.so" ]; then
        msg "WARN: Installing APCu for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/apcu-${_PHP_APCU}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _USE_IGBINARY="${_PHP_IGBINARY_TWO}"
  else
    _USE_IGBINARY="${_PHP_IGBINARY_THREE}"
  fi
  if [ ! -e "${_THIS_PHP_EXT_DIR}/igbinary.so" ] \
    || [ ! -e "${pthLog}/igbinary-${_USE_IGBINARY}-${_T_PHP_VRN}.log" ]; then
    msg "INFO: Installing igbinary ${_USE_IGBINARY} upgrade for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf igbinary*
    get_dev_src "igbinary-${_USE_IGBINARY}.tgz"
    cd /var/opt/igbinary-${_USE_IGBINARY}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/igbinary.so" ]; then
      msg "WARN: Installing igbinary for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/igbinary-${_USE_IGBINARY}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" != "56" ] && [ "$1" != "70" ] && [ "$1" != "71" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mcrypt.so" ] \
      || [ ! -e "${pthLog}/mcrypt-${_PHP_MCRYPT}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing MCRYPT ${_PHP_MCRYPT} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mcrypt*
      get_dev_src "mcrypt-${_PHP_MCRYPT}.tgz"
      cd /var/opt/mcrypt-${_PHP_MCRYPT}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mcrypt.so" ]; then
        msg "WARN: Installing MCRYPT for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/mcrypt-${_PHP_MCRYPT}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ] \
      || [ ! -e "${pthLog}/f_uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing UploadProgress ${_UPROGRESS_LEGACY_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      get_dev_src "uploadprogress-${_UPROGRESS_LEGACY_VRN}.tgz"
      cd /var/opt/uploadprogress-${_UPROGRESS_LEGACY_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
        msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/f_uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  elif [ "$1" = "72" ] \
    || [ "$1" = "73" ] \
    || [ "$1" = "74" ] \
    || [ "$1" = "80" ] \
    || [ "$1" = "81" ] \
    || [ "$1" = "82" ] \
    || [ "$1" = "83" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ] \
      || [ ! -e "${pthLog}/f_uploadprogress-${_UPROGRESS_EIGHT_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing UploadProgress ${_UPROGRESS_EIGHT_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      get_dev_src "uploadprogress-${_UPROGRESS_EIGHT_VRN}.tgz"
      cd /var/opt/uploadprogress-${_UPROGRESS_EIGHT_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
        msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/f_uploadprogress-${_UPROGRESS_EIGHT_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  else
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ] \
      || [ ! -e "${pthLog}/f_uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing UploadProgress ${_UPROGRESS_SEVEN_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      get_dev_src "uploadprogress-${_UPROGRESS_SEVEN_VRN}.tar.gz"
      cd /var/opt/uploadprogress-${_UPROGRESS_SEVEN_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
        msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/f_uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ] \
      || [ ! -e "${pthLog}/php-pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing JSMin ${_JSMIN_PHP_LEGACY_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf pecl-jsmin*
      get_dev_src "pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}.tar.gz"
      cd /var/opt/pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ]; then
        msg "WARN: Installing JSMin for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/php-pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  else
    if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ] \
      || [ ! -e "${pthLog}/php-pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing JSMin ${_JSMIN_PHP_MODERN_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf pecl-jsmin*
      get_dev_src "pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}.tar.gz"
      cd /var/opt/pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ]; then
        msg "WARN: Installing JSMin for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/php-pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/twig.so" ] \
      || [ ! -e "${pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing Twig C ${_TWIGC_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf twig*
      get_dev_src "twig-${_TWIGC_VRN}.tar.gz"
      cd /var/opt/twig-${_TWIGC_VRN}/ext/twig
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/twig.so" ]; then
        msg "WARN: Installing Twig C for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ] \
    && [ ! -e "${pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
      msg "INFO: Building GEOS ${_GEOS_VRN} upgrade for PHP ${_T_PHP_VRN} from sources..."
      if [ ! -e "${pthLog}/geos-${_X_SE}-${_X_VERSION}.log" ]; then
        apt_clean_update
        st_runner "${_INSTAPP} libgeos-dev libgeos-c1" 2> /dev/null
        touch ${pthLog}/geos-${_X_SE}-${_X_VERSION}.log
      fi
      cd /var/opt
      rm -rf geos*
      get_dev_src "geos-${_GEOS_VRN}.tar.bz2"
      cd geos-${_GEOS_VRN}
      _PHP_V="56"
      for e in ${_PHP_V}; do
        if [ "$1" = "${e}" ]; then
          find . -type f -print0 \
            | xargs -0 sed -i 's/\/usr\/local/\/opt\/php${e}/g' &> /dev/null
          wait
        fi
      done
      mrun "bash ./configure --enable-php" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      touch ${pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ] \
    && [ ! -e "${pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
      msg "INFO: Installing MongoDB ${_MONGO_VRN} PHP driver upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongo*
      get_dev_src "mongo-${_MONGO_VRN}.tgz"
      cd /var/opt/mongo-${_MONGO_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  if [ "$1" != "56" ] \
    && [ ! -e "${pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
      msg "INFO: Installing MongoDB ${_MONGO_VRN} PHP driver upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongodb*
      get_dev_src "mongodb-${_MONGODB_VRN}.tgz"
      cd /var/opt/mongodb-${_MONGODB_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ ! -e "${_THIS_PHP_EXT_DIR}/imagick.so" ] \
    || [ ! -e "${pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log" ]; then
    msg "INFO: Installing Imagick ${_IMAGICK_VRN} upgrade for PHP ${_T_PHP_VRN}..."
    if [ "${_OS_CODE}" = "daedalus" ] || [ "${_OS_CODE}" = "chimaera" ]; then
      if [ -e "/usr/bin/MagickWand-config" ]; then
        mv -f /usr/bin/MagickWand-config /var/backups/usr-bin-MagickWand-config
      fi
      if [ -e "/usr/local/bin/MagickWand-config" ]; then
        mv -f /usr/local/bin/MagickWand-config /var/backups/usr-local-bin-MagickWand-config
      fi
    fi
    if [ ! -e "${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log" ]; then
      apt_clean_update
      mrun "${_INSTAPP} libmagickwand-dev" 2> /dev/null
      touch ${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log
    fi
    cd /var/opt
    rm -rf imagick*
    get_dev_src "imagick-${_IMAGICK_VRN}.tgz"
    cd /var/opt/imagick-${_IMAGICK_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/imagick.so" ]; then
      msg "WARN: Installing Imagick for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mailparse.so" ] \
      || [ ! -e "${pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing MailParse ${_MAILPARSE_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mailparse*
      get_dev_src "mailparse-${_MAILPARSE_VRN}.tgz"
      cd /var/opt/mailparse-${_MAILPARSE_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mailparse.so" ]; then
        msg "WARN: Installing MailParse for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ ! -e "${pthLog}/f_libyaml-${_LIB_YAML_VRN}.log" ] \
    || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ]; then
    msg "INFO: Installing LibYAML upgrade for PHP..."
    cd /var/opt
    rm -rf yaml*
    get_dev_src "yaml-${_LIB_YAML_VRN}.tar.gz"
    cd /var/opt/yaml-${_LIB_YAML_VRN}
    mrun "sh ./bootstrap" 2> /dev/null
    mrun "bash ./configure --prefix=/usr" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    touch ${pthLog}/f_libyaml-${_LIB_YAML_VRN}.log
    rm -f ${pthLog}/yaml*.log
    rm -f ${pthLog}/f_yaml*.log
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      if [ ! -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.9" ] \
        || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ]; then
        mkdir -p /var/backups/libyaml
        cp -af /usr/lib/x86_64-linux-gnu/libyaml* /var/backups/libyaml/ &> /dev/null
        if [ -e "/usr/lib/libyaml-0.so.2.0.9" ]; then
          rm -f /usr/lib/x86_64-linux-gnu/libyaml*
          rm -f /usr/lib/libyaml-0.so.2.0.4
        fi
        cp -af /usr/lib/libyaml* /usr/lib/x86_64-linux-gnu/
      fi
    fi
  fi
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ] \
      || [ ! -e "${pthLog}/f_yaml-${_YAML_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing YAML ${_YAML_PHP_LEGACY_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf yaml*
      get_dev_src "yaml-${_YAML_PHP_LEGACY_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_PHP_LEGACY_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
        msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/f_yaml-${_YAML_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  elif [ "$1" = "70" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ] \
      || [ ! -e "${pthLog}/f_yaml-${_YAML_PHP_SEVENO_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing YAML ${_YAML_PHP_SEVENO_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf yaml*
      get_dev_src "yaml-${_YAML_PHP_SEVENO_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_PHP_SEVENO_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
        msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/f_yaml-${_YAML_PHP_SEVENO_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  else
    if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ] \
      || [ ! -e "${pthLog}/f_yaml-${_YAML_PHP_MODERN_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing YAML ${_YAML_PHP_MODERN_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf yaml*
      get_dev_src "yaml-${_YAML_PHP_MODERN_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_PHP_MODERN_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
        msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${pthLog}/f_yaml-${_YAML_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
}

#
# Install modern PHP version
install_php_multi() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_php_multi $1"
  fi
  if_to_do_fix
  get_php_conf_extra
  _PHP_EXTRA=$(echo "${_PHP_EXTRA}" | sed "s/--with-curlwrappers//g" 2>&1)
  ###--------------------###
  msg "INFO: Building PHP ${_PHP_VERSION} from sources..."
  apt_clean_update
  mrun "${_INSTAPP} libonig-dev" 2> /dev/null
  if [[ "${_PHP_EXTRA_CONF}" =~ "--with-tidy" ]] \
    && [ ! -e "${pthLog}/libtidy-${_LIB_TIDY_VRN}.log" ]; then
    if [ -e "/usr/lib/libtidy.so" ]; then
      mrun "apt-get remove libtidy-dev -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove libtidy-0.99-0 -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove tidy -y --purge --auto-remove -qq" 2> /dev/null
    fi
    cd /var/opt
    rm -rf tidy*
    apt_clean_update
    mrun "${_INSTAPP} cmake" 2> /dev/null
    get_dev_src "tidy-html5-${_LIB_TIDY_VRN}.tar.gz"
    cd tidy-html5-${_LIB_TIDY_VRN}/build/cmake
    mrun "cmake ../.. -DCMAKE_INSTALL_PREFIX=/usr/" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      cd /usr/lib
      ln -sfn libtidy.so.${_LIB_TIDY_VRN} libtidy-0.99.so.0
      touch ${pthLog}/libtidy-${_LIB_TIDY_VRN}.log
    fi
  fi
  cd /var/opt
  rm -rf php*
  get_dev_src "php-${_PHP_VERSION}.tar.bz2"
  msg "INFO: Building PHP ${_PHP_VERSION} part 1/3"
  cd /var/opt/php-${_PHP_VERSION}
  if [ "${_OS_CODE}" = "stretch" ] \
    || [ "${_OS_CODE}" = "jessie" ]; then
    mrun "sh ./buildconf --force" 2> /dev/null
    #patchFile="disable_SSLv2_for_openssl_1_0_0.patch"
    #patch -p1 < ${bldPth}/aegir/patches/${patchFile}
  fi
  ### cd sapi/fpm/fpm
  ### patch -p1 < ${bldPth}/aegir/patches/fpm_main.c.patch &> /dev/null
  ### cd /var/opt/php-${_PHP_VERSION}
  msg "INFO: Building PHP ${_PHP_VERSION} part 2/3"
  if [ "$1" = "56" ] \
    || [ "$1" = "70" ] \
    || [ "$1" = "71" ] \
    || [ "$1" = "72" ] \
    || [ "$1" = "73" ]; then
    _PHP_EXTRA="${_PHP_EXTRA}"
  else
    _PHP_EXTRA="${_PHP_EXTRA} --enable-intl"
  fi
  if [ -e "/root/.install.modern.openssl.cnf" ] \
    && [ -x "/usr/local/ssl3/bin/openssl" ]; then
    _SSL_BINARY=/usr/local/ssl3/bin/openssl
  else
    _SSL_BINARY=/usr/local/ssl/bin/openssl
  fi
  _SSL_ITD=$(${_SSL_BINARY} version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}')
  if [[ "${_SSL_ITD}" =~ "${_OPENSSL_MODERN_VRN}" ]] \
    || [ -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
    _SSL_PATH="/usr/local/ssl3"
    _SSL_LIB_PATH="${_SSL_PATH}/lib64"
  else
    _SSL_PATH="/usr/local/ssl"
    _SSL_LIB_PATH="${_SSL_PATH}/lib"
  fi
  if [ "$1" = "56" ] \
    || [ "$1" = "70" ] \
    || [ "$1" = "71" ] \
    || [ "$1" = "72" ] \
    || [ "$1" = "73" ]; then
    if [ -e "/usr/local/ssl/lib/libssl.so.1.1" ] \
      || [ -e "/usr/local/ssl/lib/libssl.so.1.0.0" ] \
      || [ -e "/usr/local/ssl/lib/libssl.so.1.0.1" ] \
      || [ -e "/usr/local/ssl/lib/libssl.so.1.0.2" ]; then
      _SSL_PATH="/usr/local/ssl"
      _SSL_LIB_PATH="${_SSL_PATH}/lib"
    fi
  fi
  _PKG_CONFIG_PATH="${_SSL_LIB_PATH}/pkgconfig"
  if [ -e "${_SSL_LIB_PATH}" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} --with-openssl=${_SSL_PATH}"
  else
    _PHP_EXTRA="${_PHP_EXTRA} --with-openssl"
  fi
  if [ -d "/usr/local/include/curl" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} --with-curl=/usr/local"
  else
    _PHP_EXTRA="${_PHP_EXTRA} --with-curl"
  fi
  _PRE_SNFR="--enable-zip \
             --with-gd \
             --with-jpeg-dir=/usr \
             --with-png-dir=/usr \
             --with-xpm-dir=/usr \
             --with-webp-dir=/usr \
             --with-ldap \
             --with-gmp \
             --with-xmlrpc"
  _NEW_SNFR="--with-zip \
             --enable-gd \
             --with-jpeg \
             --with-xpm \
             --with-webp \
             --with-freetype \
             --with-ldap \
             --with-gmp"
  if [ "${_OS_CODE}" != "jessie" ]; then
    _NEW_SNFR="${_NEW_SNFR} --with-sodium"
  fi
  if [ "$1" = "74" ] || [ "$1" = "80" ] || [ "$1" = "81" ] || [ "$1" = "82" ] || [ "$1" = "83" ]; then
    _PHP_EXTRA=$(echo "${_PHP_EXTRA}" | sed "s/--with-freetype-dir=\/usr//g" 2>&1)
    _PHP_EXTRA="${_PHP_EXTRA} ${_NEW_SNFR}"
  elif [ "$1" = "73" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PRE_SNFR}"
  elif [ "$1" = "72" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PRE_SNFR}"
  elif [ "$1" = "71" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PRE_SNFR} --enable-gd-native-ttf --with-mcrypt"
  elif [ "$1" = "70" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PRE_SNFR} --enable-gd-native-ttf --with-mcrypt"
  elif [ "$1" = "56" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PRE_SNFR} --enable-gd-native-ttf --with-mcrypt --with-mysql=mysqlnd"
    if [ "${_OS_CODE}" != "jessie" ]; then
      patchFile="PHP-5.6.31-OpenSSL-1.1.0-compatibility-20170801.patch"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        patch -p1 < ${bldPth}/aegir/patches/${patchFile}
      else
        patch -p1 < ${bldPth}/aegir/patches/${patchFile} &> /dev/null
      fi
    fi
  fi
  if [ "${_OS_CODE}" = "daedalus" ] \
    || [ "${_OS_CODE}" = "chimaera" ] \
    || [ "${_OS_CODE}" = "beowulf" ] \
    || [ "${_OS_CODE}" = "bookworm" ] \
    || [ "${_OS_CODE}" = "bullseye" ] \
    || [ "${_OS_CODE}" = "buster" ]; then
    if [ "$1" = "56" ] || [ "$1" = "70" ] || [ "$1" = "71" ] || [ "$1" = "72" ] || [ "$1" = "73" ]; then
      patchFile="freetype.patch"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        patch -p1 < ${bldPth}/aegir/patches/${patchFile}
      else
        patch -p1 < ${bldPth}/aegir/patches/${patchFile} &> /dev/null
      fi
    fi
    if [ "$1" != "81" ] && [ "$1" != "82" ] && [ "$1" != "83" ]; then
      patchFile="php-8.1-openssl3.patch"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        patch -p1 < ${bldPth}/aegir/patches/${patchFile}
      else
        patch -p1 < ${bldPth}/aegir/patches/${patchFile} &> /dev/null
      fi
    fi
  fi
  if [ "${_OS_CODE}" != "jessie" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} \
                --with-imap \
                --with-imap-ssl \
                --with-kerberos"
  fi
  _PHP_EXTRA="${_PHP_EXTRA} --enable-opcache"
  if [ ! -z "${_PHP_EXTRA}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo "${_PHP_EXTRA}" | fmt -su -w 2500 > /var/backups/php_extra_${_PHP_VERSION}.txt
      _DISPLAY_PHP_EXTRA=$(cat /var/backups/php_extra_${_PHP_VERSION}.txt 2>&1)
      _DISPLAY_PHP_EXTRA=$(echo -n ${_DISPLAY_PHP_EXTRA} | tr -d "\n" 2>&1)
      msg "INFO: This PHP ${_PHP_VERSION} is built with:"
      msg "INFO: ${_DISPLAY_PHP_EXTRA}"
    fi
  fi
  LIBS="-ldl -lpthread" PKG_CONFIG_PATH="${_PKG_CONFIG_PATH}" ./configure \
                --prefix=/opt/php$1 \
                --enable-fpm \
                --enable-bcmath \
                --enable-calendar \
                --enable-exif \
                --enable-ftp \
                --enable-mbstring \
                --enable-pcntl \
                --enable-soap \
                --with-fpm-group=www-data \
                --with-fpm-user=www-data \
                --with-mysql-sock=/var/run/mysqld/mysqld.sock \
                --with-mysqli=mysqlnd \
                --with-pdo-mysql=mysqlnd \
                --with-pear \
                --with-xsl \
                --with-zlib \
                --with-bz2 \
                ${_PHP_EXTRA} &> /dev/null
  if [ -e "/var/opt/php-${_PHP_VERSION}/Makefile" ]; then
    msg "INFO: Building PHP ${_PHP_VERSION} part 3/3"
    msg "WAIT: This may take a while, please wait..."
    sed -i "s/^EXTRA_LIBS = \-lcrypt/EXTRA_LIBS = \-llber \-lcrypt/g" /var/opt/php-${_PHP_VERSION}/Makefile
    mrun "make -j $(nproc)" 2> /dev/null
    mrun "make install" 2> /dev/null
    ldconfig 2> /dev/null
  else
    msg "WARN: No Makefile, configure for PHP ${_PHP_VERSION} failed"
    msg "INFO: Waiting 60 seconds before trying again..."
    sleep 60
    msg "INFO: Building PHP ${_PHP_VERSION} part 2/3 (again)"
    mrun "make clean" 2> /dev/null
    LIBS="-ldl -lpthread" PKG_CONFIG_PATH="${_PKG_CONFIG_PATH}" ./configure \
                --prefix=/opt/php$1 \
                --enable-fpm \
                --enable-bcmath \
                --enable-calendar \
                --enable-exif \
                --enable-ftp \
                --enable-mbstring \
                --enable-pcntl \
                --enable-soap \
                --with-fpm-group=www-data \
                --with-fpm-user=www-data \
                --with-mysql-sock=/var/run/mysqld/mysqld.sock \
                --with-mysqli=mysqlnd \
                --with-pdo-mysql=mysqlnd \
                --with-pear \
                --with-xsl \
                --with-zlib \
                ${_PHP_EXTRA} 2> /dev/null
    if [ -f "/var/opt/php-${_PHP_VERSION}/Makefile" ]; then
      sed -i "s/^EXTRA_LIBS = \-lcrypt/EXTRA_LIBS = \-llber \-lcrypt/g" /var/opt/php-${_PHP_VERSION}/Makefile
      msg "INFO: Building PHP ${_PHP_VERSION} part 3/3 (again)"
      msg "WAIT: This may take a while, please wait..."
      mrun "make -j $(nproc)" 2> /dev/null
      mrun "make install" 2> /dev/null
      ldconfig 2> /dev/null
    else
      msg "ALRT: No Makefile, building PHP ${_PHP_VERSION} failed again!"
      msg "INFO: Waiting 3 minutes for your input or ctrl-c..."
      sleep 180
      msg "INFO: Moving on..."
    fi
  fi
  if [ -x "/opt/php$1/bin/php" ]; then
    rm -f /usr/bin/php
    rm -f /usr/bin/php-cli
    ln -s /opt/php$1/bin/php /usr/bin/php
    ln -s /opt/php$1/bin/php /usr/bin/php-cli
    if [ -x "/opt/php$1/bin/phpize" ]; then
      rm -f /usr/bin/phpize
      ln -s /opt/php$1/bin/phpize /usr/bin/phpize
    fi
    if [ -x "/opt/php$1/bin/php-config" ]; then
      rm -f /usr/bin/php-config
      ln -s /opt/php$1/bin/php-config /usr/bin/php-config
    fi
    _T_PHP_VRN="${_PHP_VERSION}"
    _T_PHP_PTH="/opt/php$1/bin"
    _T_PHP_CFG="/opt/php$1/bin/php-config"
    _THIS_PHP_EXT_DIR=
    if [ "$1" = "56" ]; then
      _THIS_PHP_EXT_DIR="/opt/php56/lib/php/extensions/no-debug-non-zts-${_PHP56_API}"
    elif [ "$1" = "70" ]; then
      _THIS_PHP_EXT_DIR="/opt/php70/lib/php/extensions/no-debug-non-zts-${_PHP70_API}"
    elif [ "$1" = "71" ]; then
      _THIS_PHP_EXT_DIR="/opt/php71/lib/php/extensions/no-debug-non-zts-${_PHP71_API}"
    elif [ "$1" = "72" ]; then
      _THIS_PHP_EXT_DIR="/opt/php72/lib/php/extensions/no-debug-non-zts-${_PHP72_API}"
    elif [ "$1" = "73" ]; then
      _THIS_PHP_EXT_DIR="/opt/php73/lib/php/extensions/no-debug-non-zts-${_PHP73_API}"
    elif [ "$1" = "74" ]; then
      _THIS_PHP_EXT_DIR="/opt/php74/lib/php/extensions/no-debug-non-zts-${_PHP74_API}"
    elif [ "$1" = "80" ]; then
      _THIS_PHP_EXT_DIR="/opt/php80/lib/php/extensions/no-debug-non-zts-${_PHP80_API}"
    elif [ "$1" = "81" ]; then
      _THIS_PHP_EXT_DIR="/opt/php81/lib/php/extensions/no-debug-non-zts-${_PHP81_API}"
    elif [ "$1" = "82" ]; then
      _THIS_PHP_EXT_DIR="/opt/php82/lib/php/extensions/no-debug-non-zts-${_PHP82_API}"
    elif [ "$1" = "83" ]; then
      _THIS_PHP_EXT_DIR="/opt/php83/lib/php/extensions/no-debug-non-zts-${_PHP83_API}"
    fi
    if [ ! -z "${_THIS_PHP_EXT_DIR}" ]; then
      install_php_extensions "$1"
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "WARN: _THIS_PHP_EXT_DIR for PHP $1 empty in install_php_multi"
      fi
    fi
    if [ -e "/root/.mstr.clstr.cnf" ] \
      || [ -e "/root/.wbhd.clstr.cnf" ] \
      || [ -e "/root/.dbhd.clstr.cnf" ]; then
      _T_DBS_VRN="${_GALERA_10_VRN}"
    else
      if [ "${_DB_SERIES}" = "5.7" ]; then
        if [ "${_DB_SERIES}" = "5.7" ]; then
          _DB_SERVER=Percona
          _DBS_VRN="${_PERCONA_5_7_VRN}"
        else
          _DB_SERVER=Percona
          _DB_SERIES=5.7
          _DBS_VRN="${_PERCONA_5_7_VRN}"
        fi
        _T_DBS_VRN="${_DBS_VRN}"
      else
        _DB_SERVER=Percona
        _DB_SERIES=5.7
        _DBS_VRN="${_PERCONA_5_7_VRN}"
        if [ -e "${barCnf}" ]; then
          sed -i "s/^_DB_SERIES=.*/_DB_SERIES=5.7/g" ${barCnf}
          sed -i "s/^_DB_SERVER=.*/_DB_SERVER=Percona/g" ${barCnf}
        fi
      fi
    fi
    touch ${pthLog}/installed-${_PHP_VERSION}-${_T_DBS_VRN}-${_DB_SERVER}.log
    rm -f /etc/init.d/php$1-fpm*
    cp -af ${locCnf}/php$1-fpm /etc/init.d/php$1-fpm
    chmod 755 /etc/init.d/php$1-fpm
    if [ -e "/root/.run_post_major_os_upgrade.info" ]; then
      touch ${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info
    fi
    mrun "update-rc.d php$1-fpm defaults" 2> /dev/null
  else
    msg "WARN: Building PHP ${_PHP_VERSION} failed!"
  fi
}

#
# Update PHP extensions
php_multi_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_multi_update $1"
  fi
  _T_PHP_VRN="${_PHP_VERSION}"
  _T_PHP_PTH="/opt/php$1/bin"
  _T_PHP_CFG="/opt/php$1/bin/php-config"
  _THIS_PHP_EXT_DIR=
  if [ "$1" = "56" ]; then
    _THIS_PHP_EXT_DIR="/opt/php56/lib/php/extensions/no-debug-non-zts-${_PHP56_API}"
  elif [ "$1" = "70" ]; then
    _THIS_PHP_EXT_DIR="/opt/php70/lib/php/extensions/no-debug-non-zts-${_PHP70_API}"
  elif [ "$1" = "71" ]; then
    _THIS_PHP_EXT_DIR="/opt/php71/lib/php/extensions/no-debug-non-zts-${_PHP71_API}"
  elif [ "$1" = "72" ]; then
    _THIS_PHP_EXT_DIR="/opt/php72/lib/php/extensions/no-debug-non-zts-${_PHP72_API}"
  elif [ "$1" = "73" ]; then
    _THIS_PHP_EXT_DIR="/opt/php73/lib/php/extensions/no-debug-non-zts-${_PHP73_API}"
  elif [ "$1" = "74" ]; then
    _THIS_PHP_EXT_DIR="/opt/php74/lib/php/extensions/no-debug-non-zts-${_PHP74_API}"
  elif [ "$1" = "80" ]; then
    _THIS_PHP_EXT_DIR="/opt/php80/lib/php/extensions/no-debug-non-zts-${_PHP80_API}"
  elif [ "$1" = "81" ]; then
    _THIS_PHP_EXT_DIR="/opt/php81/lib/php/extensions/no-debug-non-zts-${_PHP81_API}"
  elif [ "$1" = "82" ]; then
    _THIS_PHP_EXT_DIR="/opt/php82/lib/php/extensions/no-debug-non-zts-${_PHP82_API}"
  elif [ "$1" = "83" ]; then
    _THIS_PHP_EXT_DIR="/opt/php83/lib/php/extensions/no-debug-non-zts-${_PHP83_API}"
  fi
  if [ ! -z "${_THIS_PHP_EXT_DIR}" ]; then
    php_extensions_update "$1"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "WARN: _THIS_PHP_EXT_DIR for PHP $1 empty in php_multi_update"
    fi
  fi
}

#
# Update New Relic.
newrelic_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: newrelic_update"
  fi
  ###--------------------###
  _X86_64_TEST=$(uname -m 2>&1)
  if [ "${_X86_64_TEST}" = "x86_64" ]; then
    _SYSTEM_ARCH="x64"
  else
    _SYSTEM_ARCH="x32"
  fi
  if [ ! -z "${_NEWRELIC_KEY}" ] && [ "${_SYSTEM_ARCH}" = "x64" ]; then
    if [ -x "/usr/bin/gpg2" ]; then
      _GPG=gpg2
    else
      _GPG=gpg
    fi
    _NEWRELIC_KEYS_SIG="548C16BF"
    nrList="/etc/apt/sources.list.d/newrelic.list"
    if [ -e "/etc/newrelic/newrelic.cfg" ] \
      || [ -e "/etc/apt/sources.list.d/newrelic.list" ]; then
      msg "INFO: Uninstalling previous version of New Relic Apps Monitor..."
      cd /var/opt
      if [ ! -e "/etc/apt/keyrings/newrelic.gpg" ] \
        || [ -e "/etc/apt/trusted.gpg.d/newrelic.gpg" ] \
        || [ -e "/etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg" ] \
        || [ -e /root/.force.newrelic.update.cnf ]; then
        if [ ! -e "/etc/apt/keyrings" ]; then
          mkdir -m 0755 -p /etc/apt/keyrings
        fi
        if [ -e "/etc/apt/trusted.gpg.d/newrelic.gpg" ]; then
          rm -f /etc/apt/trusted.gpg.d/newrelic.gpg*
        fi
        if [ -e "/etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg" ]; then
          rm -f /etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg
        fi
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Retrieving ${_NEWRELIC_KEYS_SIG} key..."
        fi
        apt-key del ${_NEWRELIC_KEYS_SIG} &> /dev/null
        if [ ! -e "/etc/apt/keyrings/newrelic.gpg" ]; then
          curl -fsSL ${urlDev}/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/newrelic.gpg
        fi
        chmod 644 /etc/apt/keyrings/newrelic.gpg
      fi
      apt_clean_update
      mrun "${_RMAPP} newrelic-php5 \
        newrelic-php5-common \
        newrelic-daemon \
        newrelic-sysmond" 2> /dev/null
      mkdir -p ${vBs}/nr
      mv -f /etc/newrelic \
        ${vBs}/nr/etc-newrelic-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
      pthNrx="lib/php/extensions/no-debug-non-zts"
      _PHP_EXT_DIR_83="/opt/php83/${pthNrx}-${_PHP83_API}"
      _PHP_EXT_DIR_82="/opt/php82/${pthNrx}-${_PHP82_API}"
      _PHP_EXT_DIR_81="/opt/php81/${pthNrx}-${_PHP81_API}"
      _PHP_EXT_DIR_80="/opt/php80/${pthNrx}-${_PHP80_API}"
      _PHP_EXT_DIR_74="/opt/php74/${pthNrx}-${_PHP74_API}"
      _PHP_EXT_DIR_73="/opt/php73/${pthNrx}-${_PHP73_API}"
      _PHP_EXT_DIR_72="/opt/php72/${pthNrx}-${_PHP72_API}"
      _PHP_EXT_DIR_71="/opt/php71/${pthNrx}-${_PHP71_API}"
      _PHP_EXT_DIR_70="/opt/php70/${pthNrx}-${_PHP70_API}"
      msg "INFO: Installing latest version of New Relic Apps Monitor..."
      echo "## New Relic APT Repository" > ${nrList}
      if [ -e "/etc/apt/keyrings/newrelic.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/newrelic.gpg] http://apt.newrelic.com/debian/ newrelic non-free" >> ${nrList}
      else
        echo "deb http://apt.newrelic.com/debian/ newrelic non-free" >> ${nrList}
      fi
      apt_clean_update
      st_runner "apt-get install newrelic-php5-common ${nrmUpArg}" 2> /dev/null
      st_runner "apt-get install newrelic-daemon ${nrmUpArg}" 2> /dev/null
      st_runner "apt-get install newrelic-php5 ${nrmUpArg}" 2> /dev/null
      # cd /var/opt
      # rm -rf /opt/newrelic*
      # wget -q -U iCab ${urlDev}/newrelic-php5-common_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${urlDev}/newrelic-daemon_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${urlDev}/newrelic-php5_${_NEW_RELIC_VRN}_all.deb
      # dpkg -i /var/opt/newrelic-php5-common_${_NEW_RELIC_VRN}_all.deb &> /dev/null
      # dpkg -i /var/opt/newrelic-daemon_${_NEW_RELIC_VRN}_amd64.deb &> /dev/null
      # dpkg -i /var/opt/newrelic-php5_${_NEW_RELIC_VRN}_amd64.deb &> /dev/null
      NR_PHPLIST="/opt/php70/bin:/opt/php71/bin:/opt/php72/bin:/opt/php73/bin:/opt/php74/bin:/opt/php80/bin:/opt/php81/bin:/opt/php82/bin:/opt/php83/bin"
      NR_SILENT="silent"
      export NR_INSTALL_PHPLIST="${NR_PHPLIST}"
      export NR_INSTALL_SILENT="${NR_SILENT}"
      newrelic-install install &> /dev/null
      _X86_64_TEST=$(uname -m 2>&1)
      if [ "${_X86_64_TEST}" = "x86_64" ]; then
        _SYSTEM_ARCH="x64"
      else
        _SYSTEM_ARCH="x32"
      fi
      pthNra="/usr/lib/newrelic-php5/agent"
      if [ -e "${_PHP_EXT_DIR_83}" ] && [ ! -e "${_PHP_EXT_DIR_83}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so \
          ${_PHP_EXT_DIR_83}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_82}" ] && [ ! -e "${_PHP_EXT_DIR_82}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so \
          ${_PHP_EXT_DIR_82}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_81}" ] && [ ! -e "${_PHP_EXT_DIR_81}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so \
          ${_PHP_EXT_DIR_81}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_80}" ] && [ ! -e "${_PHP_EXT_DIR_80}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so \
          ${_PHP_EXT_DIR_80}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_74}" ] && [ ! -e "${_PHP_EXT_DIR_74}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so \
          ${_PHP_EXT_DIR_74}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_73}" ] && [ ! -e "${_PHP_EXT_DIR_73}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so \
          ${_PHP_EXT_DIR_73}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_72}" ] && [ ! -e "${_PHP_EXT_DIR_72}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so \
          ${_PHP_EXT_DIR_72}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_71}" ] && [ ! -e "${_PHP_EXT_DIR_71}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP71_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP71_API}.so \
          ${_PHP_EXT_DIR_71}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_70}" ] && [ ! -e "${_PHP_EXT_DIR_70}/newrelic.so" ] \
        && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP70_API}.so" ]; then
        ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP70_API}.so \
          ${_PHP_EXT_DIR_70}/newrelic.so
      fi
      if [ ! -e "/etc/newrelic/newrelic.cfg" ]; then
        echo "## New Relic Configuration" > \
          /etc/newrelic/newrelic.cfg
        echo "license_key=${_NEWRELIC_KEY}" >> \
          /etc/newrelic/newrelic.cfg
        echo "pidfile=/var/run/newrelic-daemon.pid" >> \
          /etc/newrelic/newrelic.cfg
        echo "logfile=/var/log/newrelic/newrelic-daemon.log" >> \
          /etc/newrelic/newrelic.cfg
        echo "loglevel=error" >> \
          /etc/newrelic/newrelic.cfg
      else
        sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
          /etc/newrelic/newrelic.cfg &> /dev/null
        wait
      fi
      sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
        /etc/newrelic/nrsysmond.cfg &> /dev/null
      wait
    fi
  fi
}

#
# Install New Relic.
if_install_php_newrelic() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_php_newrelic"
  fi
  ###--------------------###
  _X86_64_TEST=$(uname -m 2>&1)
  if [ "${_X86_64_TEST}" = "x86_64" ]; then
    _SYSTEM_ARCH="x64"
  else
    _SYSTEM_ARCH="x32"
  fi
  if [ ! -z "${_NEWRELIC_KEY}" ] && [ "${_SYSTEM_ARCH}" = "x64" ]; then
    if [ -x "/usr/bin/gpg2" ]; then
      _GPG=gpg2
    else
      _GPG=gpg
    fi
    _MULTI_NR=NO
    _NEWRELIC_KEYS_SIG="548C16BF"
    nrList="/etc/apt/sources.list.d/newrelic.list"
    _PHP_EXT_DIR_83="/opt/php83/lib/php/extensions/no-debug-non-zts-${_PHP83_API}"
    _PHP_EXT_DIR_82="/opt/php82/lib/php/extensions/no-debug-non-zts-${_PHP82_API}"
    _PHP_EXT_DIR_81="/opt/php81/lib/php/extensions/no-debug-non-zts-${_PHP81_API}"
    _PHP_EXT_DIR_80="/opt/php80/lib/php/extensions/no-debug-non-zts-${_PHP80_API}"
    _PHP_EXT_DIR_74="/opt/php74/lib/php/extensions/no-debug-non-zts-${_PHP74_API}"
    _PHP_EXT_DIR_73="/opt/php73/lib/php/extensions/no-debug-non-zts-${_PHP73_API}"
    _PHP_EXT_DIR_72="/opt/php72/lib/php/extensions/no-debug-non-zts-${_PHP72_API}"
    _PHP_EXT_DIR_71="/opt/php71/lib/php/extensions/no-debug-non-zts-${_PHP71_API}"
    _PHP_EXT_DIR_70="/opt/php70/lib/php/extensions/no-debug-non-zts-${_PHP70_API}"
    if [ -e "${_PHP_EXT_DIR_83}" ] \
      && [ ! -e "${_PHP_EXT_DIR_83}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_82}" ] \
      && [ ! -e "${_PHP_EXT_DIR_82}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_81}" ] \
      && [ ! -e "${_PHP_EXT_DIR_81}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_80}" ] \
      && [ ! -e "${_PHP_EXT_DIR_80}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_74}" ] \
      && [ ! -e "${_PHP_EXT_DIR_74}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_73}" ] \
      && [ ! -e "${_PHP_EXT_DIR_73}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_72}" ] \
      && [ ! -e "${_PHP_EXT_DIR_72}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_71}" ] \
      && [ ! -e "${_PHP_EXT_DIR_71}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "${_PHP_EXT_DIR_70}" ] \
      && [ ! -e "${_PHP_EXT_DIR_70}/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ "${_MULTI_NR}" = "YES" ] \
      || [ ! -e "${pthLog}/newrelic-${_X_SE}-${_X_VERSION}.log" ] \
      || [ ! -e "/etc/newrelic/newrelic.cfg" ] \
      || [ ! -e "/etc/newrelic/nrsysmond.cfg" ] \
      || [ ! -e "/etc/apt/trusted.gpg.d/newrelic.gpg" ] \
      || [ ! -e "/etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg" ] \
      || [ ! -e "/etc/apt/sources.list.d/newrelic.list" ]; then
      msg "INFO: Installing New Relic Apps Monitor..."
      cd /var/opt
      if [ ! -e "/etc/apt/keyrings/newrelic.gpg" ] \
        || [ -e "/etc/apt/trusted.gpg.d/newrelic.gpg" ] \
        || [ -e "/etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg" ] \
        || [ -e /root/.force.newrelic.update.cnf ]; then
        if [ ! -e "/etc/apt/keyrings" ]; then
          mkdir -m 0755 -p /etc/apt/keyrings
        fi
        if [ -e "/etc/apt/trusted.gpg.d/newrelic.gpg" ]; then
          rm -f /etc/apt/trusted.gpg.d/newrelic.gpg*
        fi
        if [ -e "/etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg" ]; then
          rm -f /etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg
        fi
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Retrieving ${_NEWRELIC_KEYS_SIG} key..."
        fi
        apt-key del ${_NEWRELIC_KEYS_SIG} &> /dev/null
        if [ ! -e "/etc/apt/keyrings/newrelic.gpg" ]; then
          curl -fsSL ${urlDev}/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/newrelic.gpg
        fi
        chmod 644 /etc/apt/keyrings/newrelic.gpg
      fi
      echo "## New Relic APT Repository" > ${nrList}
      if [ -e "/etc/apt/keyrings/newrelic.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/newrelic.gpg] http://apt.newrelic.com/debian/ newrelic non-free" >> ${nrList}
      else
        echo "deb http://apt.newrelic.com/debian/ newrelic non-free" >> ${nrList}
      fi
      apt_clean_update
      st_runner "apt-get install newrelic-php5-common ${nrmUpArg}" 2> /dev/null
      st_runner "apt-get install newrelic-daemon ${nrmUpArg}" 2> /dev/null
      st_runner "apt-get install newrelic-php5 ${nrmUpArg}" 2> /dev/null
      # cd /var/opt
      # rm -rf /opt/newrelic*
      # wget -q -U iCab ${urlDev}/newrelic-php5-common_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${urlDev}/newrelic-daemon_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${urlDev}/newrelic-php5_${_NEW_RELIC_VRN}_all.deb
      # dpkg -i /var/opt/newrelic-php5-common_${_NEW_RELIC_VRN}_all.deb &> /dev/null
      # dpkg -i /var/opt/newrelic-daemon_${_NEW_RELIC_VRN}_amd64.deb &> /dev/null
      # dpkg -i /var/opt/newrelic-php5_${_NEW_RELIC_VRN}_amd64.deb &> /dev/null
      if [ "${_MULTI_NR}" = "YES" ]; then
        msg "INFO: Installing latest version of New Relic Apps Monitor..."
        NR_PHPLIST="/opt/php70/bin:/opt/php71/bin:/opt/php72/bin:/opt/php73/bin:/opt/php74/bin:/opt/php80/bin:/opt/php81/bin:/opt/php82/bin:/opt/php83/bin"
        NR_SILENT="silent"
        export NR_INSTALL_PHPLIST="${NR_PHPLIST}"
        export NR_INSTALL_SILENT="${NR_SILENT}"
        newrelic-install install &> /dev/null
        _X86_64_TEST=$(uname -m 2>&1)
        if [ "${_X86_64_TEST}" = "x86_64" ]; then
          _SYSTEM_ARCH="x64"
        else
          _SYSTEM_ARCH="x32"
        fi
        pthNra="/usr/lib/newrelic-php5/agent"
        if [ -e "${_PHP_EXT_DIR_83}" ] && [ ! -e "${_PHP_EXT_DIR_83}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so \
            ${_PHP_EXT_DIR_83}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_82}" ] && [ ! -e "${_PHP_EXT_DIR_82}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so \
            ${_PHP_EXT_DIR_82}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_81}" ] && [ ! -e "${_PHP_EXT_DIR_81}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so \
            ${_PHP_EXT_DIR_81}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_80}" ] && [ ! -e "${_PHP_EXT_DIR_80}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so \
            ${_PHP_EXT_DIR_80}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_74}" ] && [ ! -e "${_PHP_EXT_DIR_74}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so \
            ${_PHP_EXT_DIR_74}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_73}" ] && [ ! -e "${_PHP_EXT_DIR_73}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so \
            ${_PHP_EXT_DIR_73}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_72}" ] && [ ! -e "${_PHP_EXT_DIR_72}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so \
            ${_PHP_EXT_DIR_72}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_71}" ] && [ ! -e "${_PHP_EXT_DIR_71}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP71_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP71_API}.so \
            ${_PHP_EXT_DIR_71}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_70}" ] && [ ! -e "${_PHP_EXT_DIR_70}/newrelic.so" ] \
          && [ -e "${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP70_API}.so" ]; then
          ln -sfn ${pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP70_API}.so \
            ${_PHP_EXT_DIR_70}/newrelic.so
        fi
        if [ ! -e "/etc/newrelic/newrelic.cfg" ]; then
          echo "## New Relic Configuration" > \
            /etc/newrelic/newrelic.cfg
          echo "license_key=${_NEWRELIC_KEY}" >> \
            /etc/newrelic/newrelic.cfg
          echo "pidfile=/var/run/newrelic-daemon.pid" >> \
            /etc/newrelic/newrelic.cfg
          echo "logfile=/var/log/newrelic/newrelic-daemon.log" >> \
            /etc/newrelic/newrelic.cfg
          echo "loglevel=error" >> \
            /etc/newrelic/newrelic.cfg
        else
          sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
            /etc/newrelic/newrelic.cfg &> /dev/null
          wait
        fi
        sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
          /etc/newrelic/nrsysmond.cfg &> /dev/null
        wait
      fi
    fi
    touch ${pthLog}/newrelic-${_X_SE}-${_X_VERSION}.log
  fi
}

#
# Check if the PHP rebuild is required.
check_php_rebuild() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_php_rebuild $1"
  fi
  if_to_do_fix
  _PHP_ITD=$(/opt/php$1/bin/php -v \
    | grep 'PHP 7' \
    | cut -d: -f1 \
    | awk '{ print $2}' 2>&1)
  if [ -z "${_PHP_ITD}" ]; then
    _PHP_ITD=$(/opt/php$1/bin/php -v \
      | grep 'PHP 5' \
      | cut -d: -f1 \
      | awk '{ print $2}' 2>&1)
  fi
  if [ -z "${_PHP_ITD}" ]; then
    _PHP_ITD=$(/opt/php$1/bin/php -v \
      | grep 'PHP 8' \
      | cut -d: -f1 \
      | awk '{ print $2}' 2>&1)
  fi
  if [ "${_OS_CODE}" = "daedalus" ] \
    || [ "${_OS_CODE}" = "chimaera" ] \
    || [ "${_OS_CODE}" = "beowulf" ] \
    || [ "${_OS_CODE}" = "bookworm" ] \
    || [ "${_OS_CODE}" = "bullseye" ] \
    || [ "${_OS_CODE}" = "buster" ] \
    || [ "${_OS_CODE}" = "stretch" ]; then
    _OPENSSL_USE_VRN="${_OPENSSL_EOL_VRN}"
    if [ -e "/root/.install.modern.openssl.cnf" ] \
      && [ -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
      _OPENSSL_USE_VRN="${_OPENSSL_MODERN_VRN}"
    fi
  else
    _OPENSSL_USE_VRN="${_OPENSSL_LEGACY_VRN}"
  fi
  if [ "$1" = "56" ] \
    || [ "$1" = "70" ] \
    || [ "$1" = "71" ] \
    || [ "$1" = "72" ] \
    || [ "$1" = "73" ]; then
    if [ -e "/usr/local/ssl/lib/libssl.so.1.1" ]; then
      _OPENSSL_USE_VRN="${_OPENSSL_EOL_VRN}"
    elif [ -e "/usr/local/ssl/lib/libssl.so.1.0.0" ] \
      || [ -e "/usr/local/ssl/lib/libssl.so.1.0.1" ] \
      || [ -e "/usr/local/ssl/lib/libssl.so.1.0.2" ]; then
      _OPENSSL_USE_VRN="${_OPENSSL_LEGACY_VRN}"
    fi
  fi
  if [ "${_DO_FIX}" = "YES" ] || [ "${_STATUS}" != "UPGRADE" ]; then
    _PHP_FORCE_REINSTALL=NO
  fi
  _PHP_SSL_TEST=$(/opt/php$1/bin/php -i | grep "SSL Version" 2>&1)
  _PHP_SSL_LOOK_FOR="${_OPENSSL_USE_VRN}"
  _PHP_SSL_ALTER_LOOK_FOR="GnuTLS"
  _PHP_SSL_ALTER_MORE_LOOK_FOR="${_OPENSSL_MODERN_VRN}"
  if [ "$1" = "56" ] \
    || [ "$1" = "70" ] \
    || [ "$1" = "71" ] \
    || [ "$1" = "72" ] \
    || [ "$1" = "73" ]; then
    if [[ "${_PHP_SSL_TEST}" =~ "${_PHP_SSL_LOOK_FOR}" ]] \
      || [[ "${_PHP_SSL_TEST}" =~ "${_PHP_SSL_ALTER_LOOK_FOR}" ]] \
      || [[ "${_PHP_SSL_TEST}" =~ "${_PHP_SSL_ALTER_MORE_LOOK_FOR}" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed PHP ${_PHP_ITD} with ${_PHP_SSL_TEST}, OK"
      fi
    else
      if [ "${_DO_FIX}" = "YES" ] || [ "${_STATUS}" != "UPGRADE" ]; then
        msg "INFO: PHP ${_PHP_ITD} ${_PHP_SSL_TEST}, rebuild on next upgrade"
        _PHP_FORCE_REINSTALL=NO
      else
        msg "INFO: PHP ${_PHP_ITD} ${_PHP_SSL_TEST}, thus rebuild forced"
        _PHP_FORCE_REINSTALL=YES
      fi
    fi
  else
    if [[ ! "${_PHP_SSL_TEST}" =~ "${_PHP_SSL_LOOK_FOR}" ]]; then
      if [ "${_DO_FIX}" = "YES" ] || [ "${_STATUS}" != "UPGRADE" ]; then
        msg "INFO: PHP ${_PHP_ITD} ${_PHP_SSL_TEST}, rebuild on next upgrade"
        _PHP_FORCE_REINSTALL=NO
      else
        msg "INFO: PHP ${_PHP_ITD} ${_PHP_SSL_TEST}, thus rebuild forced"
        _PHP_FORCE_REINSTALL=YES
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed PHP ${_PHP_ITD} with ${_PHP_SSL_TEST}, OK"
      fi
    fi
  fi
  if [ -x "/opt/php$1/bin/php" ]; then
    if [ "$1" = "56" ]; then
      _PHP_DRIVERS=$(/opt/php$1/bin/php -i | grep "with-mysql=mysqlnd" 2>&1)
    else
      _PHP_DRIVERS=$(/opt/php$1/bin/php -i | grep "with-mysqli=mysqlnd" 2>&1)
    fi
    if [ -z "${_PHP_DRIVERS}" ]; then
      _PHP_DRIVERS_BUILD=NO
    else
      _PHP_DRIVERS_BUILD=YES
    fi
  fi
  if [ "${_PHP_DRIVERS_BUILD}" = "NO" ] \
    || [[ "${_PHP_ITD}" =~ "~" ]] \
    || [[ "${_PHP_ITD}" =~ "dotdeb" ]]; then
    if [ ! -e "${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
      msg "INFO: Installed PHP version ${_PHP_ITD}, upgrade to mysqlnd required"
      install_php_multi "$1"
      _PHP_ALREADY_REBUILT=$1
      _PHP_FORCE_REINSTALL=NO
    fi
  else
    if [[ "${_PHP_ITD}" =~ "${_PHP_VERSION}" ]]; then
      if [ "${_UP_PHP}" = "YES" ]; then
        if [ ! -z "${_PHP_ALREADY_REBUILT}" ] \
          && [ "${_PHP_ALREADY_REBUILT}" = "$1" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed PHP version ${_PHP_ITD}, OK"
          fi
        else
          if [ "${_DO_FIX}" = "YES" ] || [ "${_STATUS}" != "UPGRADE" ]; then
            msg "INFO: PHP ${_PHP_ITD} libs related rebuild on next upgrade"
            _PHP_FORCE_REINSTALL=NO
          else
            msg "INFO: PHP ${_PHP_ITD} libs related rebuild forced now"
            _PHP_FORCE_REINSTALL=YES
          fi
        fi
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installed PHP version ${_PHP_ITD}, OK"
        fi
      fi
      if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
        || [ "${_PHP_FORCE_REINSTALL}" = "YES" ]; then
        if [ "${_DO_FIX}" = "YES" ] || [ "${_STATUS}" != "UPGRADE" ]; then
          msg "INFO: PHP ${_PHP_ITD} forced rebuild on next barracuda up-${tRee}"
          _PHP_FORCE_REINSTALL=NO
        else
          if [ ! -e "${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
            msg "INFO: PHP ${_PHP_ITD} forced rebuild will happen now..."
            install_php_multi "$1"
            _PHP_ALREADY_REBUILT=$1
            _PHP_FORCE_REINSTALL=NO
          fi
        fi
      fi
    else
      if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
        || [ "${_PHP_FORCE_REINSTALL}" = "YES" ]; then
        msg "INFO: Installed PHP version ${_PHP_ITD}, rebuild forced"
      else
        msg "INFO: Installed PHP version ${_PHP_ITD}, upgrade required"
      fi
      if [ "${_DO_FIX}" = "YES" ] || [ "${_STATUS}" != "UPGRADE" ]; then
        msg "INFO: PHP ${_PHP_ITD} upgrade on next barracuda up-${tRee}"
      else
        if [ ! -e "${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
          msg "INFO: PHP ${_PHP_ITD} upgrade will happen now..."
          install_php_multi "$1"
          _PHP_ALREADY_REBUILT=$1
          _PHP_FORCE_REINSTALL=NO
        fi
      fi
    fi
  fi
  if [ "${_DB_SERIES}" = "5.7" ]; then
    if [ "${_DB_SERIES}" = "5.7" ]; then
      _DB_SERVER=Percona
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    else
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    fi
    _T_DBS_VRN="${_DBS_VRN}"
  else
    _DB_SERVER=Percona
    _DB_SERIES=5.7
    _DBS_VRN="${_PERCONA_5_7_VRN}"
    _T_DBS_VRN="${_DBS_VRN}"
    if [ -e "${barCnf}" ]; then
      sed -i "s/^_DB_SERIES=.*/_DB_SERIES=5.7/g" ${barCnf}
      sed -i "s/^_DB_SERVER=.*/_DB_SERVER=Percona/g" ${barCnf}
    fi
  fi
}

#
# Check if the PHP build has broken freetype support.
check_php_broken_freetype() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_php_broken_freetype $1"
  fi
  isFreeType=
  isFreeType=$(/opt/php$1/bin/php -i | grep with-freetype 2>&1)
  if [[ ! "${isFreeType}" =~ "with-freetype" ]] \
    || [ -z "${isFreeType}" ]; then
    if [ -x "/usr/bin/freetype-config" ]; then
      if [ ! -e "${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
        msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix freetype support..."
        install_php_multi "$1"
        _PHP_ALREADY_REBUILT=$1
        _PHP_FORCE_REINSTALL=NO
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "NOTE: PHP ${_PHP_VERSION} was built without freetype support"
      fi
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
}

#
# Check if the PHP build has broken GD support.
check_php_broken_gd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_php_broken_gd $1"
  fi
  isGd=
  isGd=$(/opt/php$1/bin/php -i | grep GD 2>&1)
  if [[ ! "${isGd}" =~ "GD Support" ]] \
    || [ -z "${isGd}" ]; then
    if [ ! -e "${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
      msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix GD support..."
      install_php_multi "$1"
      _PHP_ALREADY_REBUILT=$1
      _PHP_FORCE_REINSTALL=NO
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
}

#
# Check if the PHP build is totally broken.
check_php_broken_segfault() {
  isOnig=
  isOnig=$(/opt/php$1/bin/php -v 2>&1)
  isSegft=
  isSegft=$(/opt/php$1/bin/php -v | grep cli 2>&1)
  isSSLibs=
  isSSLibs=$(/opt/php$1/bin/php -v 2>&1)
  isOlog=
  if [ -e "/var/log/php/php$1-fpm-error.log" ]; then
    isOlog=$(grep OnigEncoding /var/log/php/php$1-fpm-error.log 2>&1)
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_php_broken_segfault $1"
    msg "CTRL: isOnig for $1 is ${isOnig}"
    msg "CTRL: isSegft for $1 is ${isSegft}"
    msg "CTRL: isOlog for $1 is ${isOlog}"
    msg "CTRL: isSSLibs for $1 is ${isSSLibs}"
  fi
  if [[ ! "${isSegft}" =~ "cli" ]] \
    || [ -z "${isSegft}" ] \
    || [[ "${isOnig}" =~ "OnigEncoding" ]] \
    || [[ "${isSegft}" =~ "OnigEncoding" ]] \
    || [[ "${isSSLibs}" =~ "no version information" ]] \
    || [[ "${isOlog}" =~ "OnigEncoding" ]]; then
    if [ ! -e "${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ] \
      || [[ "${isOlog}" =~ "OnigEncoding" ]] \
      || [[ "${isSSLibs}" =~ "no version information" ]] \
      || [[ "${isOnig}" =~ "OnigEncoding" ]]; then
      msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix broken build..."
      install_php_multi "$1"
      _PHP_ALREADY_REBUILT=$1
      _PHP_FORCE_REINSTALL=NO
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
}

#
# Check if the PHP build is broken.
check_php_broken() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_php_broken $1"
  fi
  check_php_broken_segfault "$1"
  _BROKEN_LIBCURL_TEST=$(/opt/php$1/bin/php -v 2>&1)
  if [[ "${_BROKEN_LIBCURL_TEST} " =~ "libcurl.so.4" ]]; then
    if [ ! -e "${pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
      _PHP_BIN_BROKEN=YES
      msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix broken libcurl..."
      curl_install_src
      install_php_multi "$1"
      _PHP_ALREADY_REBUILT=$1
      _PHP_FORCE_REINSTALL=NO
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
  check_php_broken_gd "$1"
  check_php_broken_freetype "$1"
}

#
# Enable previously disabled PHP-FPM versions
php_not_used_enable_again() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_not_used_enable_again"
  fi
  _PHP_V="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3"
  for e in ${_PHP_V}; do
    re=
    if [ ! -e "/opt/php${re}/bin/php" ]; then
      re="${e}"
      re=${re//[^0-9]/}
      if [ -e "${vBs}/off-php${re}-arch/bin/php" ] \
        && [ ! -e "/opt/php${re}/bin/php" ]; then
        rm -f -r /opt/php${re}
        mv -f ${vBs}/off-php${re}-arch /opt/php${re}
        msg "INFO: ${vBs}/off-php${re}-arch moved to /opt/php${re}"
      fi
      if [ -e "${vBs}/initd-php${re}-fpm" ]; then
        mv -f ${vBs}/initd-php${re}-fpm /etc/init.d/php${re}-fpm
        chmod 755 /etc/init.d/php${re}-fpm
        mrun "update-rc.d php${re}-fpm defaults" 2> /dev/null
        mrun "service php${re}-fpm start" 2> /dev/null
        msg "INFO: ${vBs}/initd-php${re}-fpm moved to /etc/init.d/php${re}-fpm"
      fi
    fi
  done
  [ -e "/root/.allow-php-multi-install-cleanup.cnf" ] && rm -f /root/.allow-php-multi-install-cleanup.cnf
}

#
# Disable not used PHP-FPM versions
php_not_used_disable() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_not_used_disable"
  fi
  _PHP_V="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3"
  _PHP_A="${_PHP_MULTI_OPTIM}"
  for e in ${_PHP_V}; do
    re=
    if [[ ${_PHP_A} == *"${e}"* ]]; then
      _IS_IDLE=NO
    else
      _IS_IDLE=YES
    fi
    if [ "${_IS_IDLE}" = "YES" ]; then
      re="${e}"
      re=${re//[^0-9]/}
      if [ -e "/etc/init.d/php${re}-fpm" ]; then
        mrun "service php${re}-fpm force-quit" 2> /dev/null
        mrun "update-rc.d -f php${re}-fpm remove" 2> /dev/null
        rm -f ${vBs}/initd-php${re}-fpm
        mv -f /etc/init.d/php${re}-fpm ${vBs}/initd-php${re}-fpm
        msg "INFO: /etc/init.d/php${re}-fpm moved to ${vBs}/initd-php${re}-fpm"
      fi
      if [ -e "/opt/php${re}/bin/php" ]; then
        rm -f -r ${vBs}/off-php${re}-arch
        mv -f /opt/php${re} ${vBs}/off-php${re}-arch
        msg "INFO: /opt/php${re} moved to ${vBs}/off-php${re}-arch"
      else
        rm -f -r /opt/php${re}
      fi
    fi
  done
}

#
# Fix init.d to disable deprecated PHP-FPM versions
php_deprecated_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_deprecated_cleanup"
  fi
  _PHP_V="55 54 53"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      mrun "service php${e}-fpm force-quit" 2> /dev/null
      mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
      mv -f /etc/init.d/php${e}-fpm ${vBs}/initd-php${e}-fpm
      msg "INFO: /etc/init.d/php${e}-fpm moved to ${vBs}/initd-php${e}-fpm"
    fi
    if [ -e "/opt/php${e}/bin/php" ]; then
      mv -f /opt/php${e} ${vBs}/off-php${e}-arch
      msg "INFO: /opt/php${e} moved to ${vBs}/off-php${e}-arch"
    fi
  done
}

#
# Fix init.d to disable not used PHP-FPM versions
php_single_initd_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_single_initd_cleanup"
  fi
  if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
    _FPM_INITD_CLEANUP=
    if [ "${_PHP_SINGLE_INSTALL}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
      _PHP_V="82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          mrun "service php${e}-fpm force-quit" 2> /dev/null
          mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${vBs}/bin-php${e}-cli
        fi
      done
    elif [ "${_PHP_SINGLE_INSTALL}" = "8.2" ] && [ -x "/opt/php82/bin/php" ]; then
      _PHP_V="83 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          mrun "service php${e}-fpm force-quit" 2> /dev/null
          mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${vBs}/bin-php${e}-cli
        fi
      done
    elif [ "${_PHP_SINGLE_INSTALL}" = "8.1" ] && [ -x "/opt/php81/bin/php" ]; then
      _PHP_V="83 82 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          mrun "service php${e}-fpm force-quit" 2> /dev/null
          mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${vBs}/bin-php${e}-cli
        fi
      done
    elif [ "${_PHP_SINGLE_INSTALL}" = "7.4" ] && [ -x "/opt/php74/bin/php" ]; then
      _PHP_V="83 82 81 80 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          mrun "service php${e}-fpm force-quit" 2> /dev/null
          mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${vBs}/bin-php${e}-cli
        fi
      done
    fi
    if [ "${_FPM_INITD_CLEANUP}" = "YES" ]; then
      killall php-fpm &> /dev/null
    fi
    rm -f /opt/local/bin/php
  fi
  rm -f /var/log/php/*log
}

#
# Re-set default PHP-CLI.
re_set_default_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: re_set_default_php_cli ${_PHP_CLI_VERSION}"
  fi
  if [ "${_PHP_CLI_VERSION}" = "8.3" ]; then
    switch_php_cli "83"
  elif [ "${_PHP_CLI_VERSION}" = "8.2" ]; then
    switch_php_cli "82"
  elif [ "${_PHP_CLI_VERSION}" = "8.1" ]; then
    switch_php_cli "81"
  elif [ "${_PHP_CLI_VERSION}" = "7.4" ]; then
    switch_php_cli "74"
  fi
}

#
# Fix path to PHP-CLI if needed.
check_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_php_cli ${_PHP_CLI_VERSION}"
  fi
  if [ "${_PHP_CLI_VERSION}" = "7.4" ]; then
    _PHP_CLI_PATH="/opt/php74/bin/php"
  elif [ "${_PHP_CLI_VERSION}" = "8.1" ]; then
    _PHP_CLI_PATH="/opt/php81/bin/php"
  elif [ "${_PHP_CLI_VERSION}" = "8.2" ]; then
    _PHP_CLI_PATH="/opt/php82/bin/php"
  elif [ "${_PHP_CLI_VERSION}" = "8.3" ]; then
    _PHP_CLI_PATH="/opt/php83/bin/php"
  else
    _PHP_CLI_PATH=""
  fi
  if [ -x "${_PHP_CLI_PATH}" ]; then
    _USE_PHP_CLI_PATH=${_PHP_CLI_PATH}
  else
    if  [ -x "/opt/php74/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php74/bin/php"
    elif  [ -x "/opt/php81/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php81/bin/php"
    elif  [ -x "/opt/php82/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php82/bin/php"
    elif  [ -x "/opt/php83/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php83/bin/php"
    fi
  fi
  if [ -x "${_USE_PHP_CLI_PATH}" ]; then
    rm -f /usr/bin/php
    rm -f /usr/bin/php-cli
    ln -sfn ${_USE_PHP_CLI_PATH} /usr/bin/php
    ln -sfn ${_USE_PHP_CLI_PATH} /usr/bin/php-cli
  else
    msg "WAIT: I can not find PHP-CLI anywhere!"
    msg "NOTE: BOA requires PHP 8.1 or newer"
  fi
}

switch_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: switch_php_cli $1"
  fi
  isTest="$1"
  isTest=${isTest//[^0-9]/}
  if [ ! -z "${isTest}" ]; then
    if [ -x "/opt/php$1/bin/php" ]; then
      rm -f /usr/bin/php
      rm -f /usr/bin/php-cli
      ln -s /opt/php$1/bin/php /usr/bin/php
      ln -s /opt/php$1/bin/php /usr/bin/php-cli
    fi
    if [ -x "/opt/php$1/bin/phpize" ]; then
      rm -f /usr/bin/phpize
      ln -s /opt/php$1/bin/phpize /usr/bin/phpize
    fi
    if [ -x "/opt/php$1/bin/php-config" ]; then
      rm -f /usr/bin/php-config
      ln -s /opt/php$1/bin/php-config /usr/bin/php-config
    fi
  fi
}

php_upgrade_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_upgrade_all $1"
  fi
  if [ ! -z "${1}" ] && [ "${1}" != "force" ]; then
    _PHP_V="${1}"
  else
    _PHP_V="56 70 71 72 73 74 80 81 82 83"
  fi
  for e in ${_PHP_V}; do
    if [ -x "/opt/php${e}/bin/php" ]; then
      if [ "${e}" = "56" ]; then
        _PHP_VERSION="${_PHP56_VRN}"
      elif [ "${e}" = "70" ]; then
        _PHP_VERSION="${_PHP70_VRN}"
      elif [ "${e}" = "71" ]; then
        _PHP_VERSION="${_PHP71_VRN}"
      elif [ "${e}" = "72" ]; then
        _PHP_VERSION="${_PHP72_VRN}"
      elif [ "${e}" = "73" ]; then
        _PHP_VERSION="${_PHP73_VRN}"
      elif [ "${e}" = "74" ]; then
        _PHP_VERSION="${_PHP74_VRN}"
      elif [ "${e}" = "80" ]; then
        _PHP_VERSION="${_PHP80_VRN}"
      elif [ "${e}" = "81" ]; then
        _PHP_VERSION="${_PHP81_VRN}"
      elif [ "${e}" = "82" ]; then
        _PHP_VERSION="${_PHP82_VRN}"
      elif [ "${e}" = "83" ]; then
        _PHP_VERSION="${_PHP83_VRN}"
      fi
      _PHP_BIN_BROKEN=NO
      _BROKEN_LIBCURL_TEST=""
      switch_php_cli "${e}"
      if [ "${1}" = "force" ]; then
        install_php_multi "${e}"
      else
        check_php_broken "${e}"
        check_php_rebuild "${e}"
      fi
      php_multi_update "${e}"
      mrun "service php${e}-fpm reload" 2> /dev/null
      _PHP_VERSION=""
      _T_PHP_VRN=""
      _T_PHP_PTH=""
    fi
  done
}

get_php_conf_extra() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: get_php_conf_extra"
  fi
  _PHP_EXTRA=""
  if [ -x "/usr/bin/freetype-config" ]; then
    _PHP_EXTRA="--with-freetype-dir=/usr"
  fi
  if [ ! -z "${_PHP_EXTRA_CONF}" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PHP_EXTRA_CONF}"
  fi
}

php_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_install_upgrade"
  fi
  if_to_do_fix
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Checking if PHP upgrade is available"
    fi
    mrun "apt-get remove php5-sasl php5-suhosin -y --purge --auto-remove -qq" 2> /dev/null
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "5.6" ]] \
    && [ ! -x "/opt/php56/bin/php" ]; then
    _PHP_VERSION="${_PHP56_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "56"
    switch_php_cli "56"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP56_BUILD=56
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.0" ]] \
    && [ ! -x "/opt/php70/bin/php" ]; then
    _PHP_VERSION="${_PHP70_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "70"
    switch_php_cli "70"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP70_BUILD=70
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.1" ]] \
    && [ ! -x "/opt/php71/bin/php" ]; then
    _PHP_VERSION="${_PHP71_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "71"
    switch_php_cli "71"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP71_BUILD=71
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.2" ]] \
    && [ ! -x "/opt/php72/bin/php" ]; then
    _PHP_VERSION="${_PHP72_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "72"
    switch_php_cli "72"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP72_BUILD=72
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.3" ]] \
    && [ ! -x "/opt/php73/bin/php" ]; then
    _PHP_VERSION="${_PHP73_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "73"
    switch_php_cli "73"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP73_BUILD=73
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.4" ]] \
    && [ ! -x "/opt/php74/bin/php" ]; then
    _PHP_VERSION="${_PHP74_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "74"
    switch_php_cli "74"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP74_BUILD=74
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "8.0" ]] \
    && [ ! -x "/opt/php80/bin/php" ]; then
    _PHP_VERSION="${_PHP80_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "80"
    switch_php_cli "80"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP80_BUILD=80
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "8.1" ]] \
    && [ ! -x "/opt/php81/bin/php" ]; then
    _PHP_VERSION="${_PHP81_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "81"
    switch_php_cli "81"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP81_BUILD=81
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "8.2" ]] \
    && [ ! -x "/opt/php82/bin/php" ]; then
    _PHP_VERSION="${_PHP82_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "82"
    switch_php_cli "82"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP82_BUILD=82
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "8.3" ]] \
    && [ ! -x "/opt/php83/bin/php" ]; then
    _PHP_VERSION="${_PHP83_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    install_php_multi "83"
    switch_php_cli "83"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP83_BUILD=83
  fi
}

php_check_if_rebuild() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_check_if_rebuild"
  fi
  check_php_cli
  isLber=
  isLber=$(php -i | grep liblber 2>&1)
  if [[ "${isLber}" =~ "liblber" ]]; then
    msg "INFO: PHP rebuild required to fix liblber..."
    _PHP_FORCE_REINSTALL=YES
    php_if_versions_cleanup_cnf
    php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  isSeg=
  isSeg=$(php -v | grep cli 2>&1)
  if [[ ! "${isSeg}" =~ "cli" ]] || [ -z "${isSeg}" ]; then
    msg "INFO: PHP rebuild required to fix broken libs..."
    _PHP_FORCE_REINSTALL=YES
    php_if_versions_cleanup_cnf
    php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  isOnig=
  isOnig=$(php -i | grep libonig 2>&1)
  if [[ "${isOnig}" =~ "libonig.so" ]]; then
    msg "INFO: PHP rebuild required to fix libonig..."
    _PHP_FORCE_REINSTALL=YES
    php_if_versions_cleanup_cnf
    php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  isIcu=
  isIcu=$(php -i | grep libicuio 2>&1)
  if [[ "${isIcu}" =~ "libicuio" ]] \
    || [ ! -e "/usr/local/lib/icu/current" ]; then
    msg "INFO: PHP rebuild required to fix ICU support..."
    _PHP_FORCE_REINSTALL=YES
    php_install_deps
    php_libs_fix
    php_if_versions_cleanup_cnf
    php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  if [ -x "/opt/php74/bin/php" ] && [ "${_OS_CODE}" != "jessie" ]; then
    isSodium=
    isSodium=$(/opt/php74/bin/php -i | grep with-sodium 2>&1)
    if [[ ! "${isSodium}" =~ "with-sodium" ]] \
      || [ -z "${isSodium}" ]; then
      msg "INFO: PHP rebuild required to add Sodium support..."
      _PHP_FORCE_REINSTALL=YES
      php_if_versions_cleanup_cnf
      php_upgrade_all "74 80 81 82 83"
      _PHP_FORCE_REINSTALL=NO
    fi
  fi
  if [ -x "/opt/php56/bin/php" ]; then
    isIgbinary=
    isIgbinary=$(/opt/php56/bin/php -i | grep igbinary 2>&1)
    if [[ ! "${isIgbinary}" =~ "igbinary" ]] \
      || [ -z "${isIgbinary}" ]; then
      msg "INFO: PHP 5.6 rebuild required to add igbinary support..."
      _PHP_FORCE_REINSTALL=YES
      php_if_versions_cleanup_cnf
      php_upgrade_all "56"
      _PHP_FORCE_REINSTALL=NO
    fi
  fi
  isWebP=
  isWebP=$(php -i | grep with-webp 2>&1)
  if [[ ! "${isWebP}" =~ "with-webp" ]] \
    || [ -z "${isWebP}" ]; then
    msg "INFO: PHP rebuild required to add WebP support..."
    _PHP_FORCE_REINSTALL=YES
    php_if_versions_cleanup_cnf
    php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  if [[ "${_PHP_EXTRA_CONF}" =~ "--with-tidy" ]] \
    && [ ! -e "${pthLog}/libtidy-${_LIB_TIDY_VRN}.log" ]; then
    apt_clean_update
    mrun "${_INSTAPP} libonig-dev" 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      mrun "apt-get remove libtidy-dev -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove libtidy-0.99-0 -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove tidy -y --purge --auto-remove -qq" 2> /dev/null
    fi
    cd /var/opt
    rm -rf tidy*
    apt_clean_update
    mrun "${_INSTAPP} cmake" 2> /dev/null
    get_dev_src "tidy-html5-${_LIB_TIDY_VRN}.tar.gz"
    cd tidy-html5-${_LIB_TIDY_VRN}/build/cmake
    mrun "cmake ../.. -DCMAKE_INSTALL_PREFIX=/usr/" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      cd /usr/lib
      ln -sfn libtidy.so.${_LIB_TIDY_VRN} libtidy-0.99.so.0
      touch ${pthLog}/libtidy-${_LIB_TIDY_VRN}.log
    fi
    msg "INFO: PHP rebuild required to add --with-tidy option..."
    _PHP_FORCE_REINSTALL=YES
    php_if_versions_cleanup_cnf
    php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
}

php_ioncube_check_if_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_ioncube_check_if_update"
  fi
  if [ "${_PHP_IONCUBE}" = "YES" ]; then
    if [ ! -e "${pthLog}/ioncube-update-${_IONCUBE_VRN}.log" ] \
      || [ "${_PHP_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      if_install_php_ioncube
    fi
  fi
}

composer_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: composer_install_upgrade"
  fi
  _COMPOSER_FROM_STATIC=NO
  if [ "${_COMPOSER_FROM_STATIC}" = "YES" ]; then
    _COMPOSER_IS=$(composer --no-interaction --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f35 \
      | awk '{ print $1}' 2>&1)
    if [ "${_COMPOSER_IS}" != "${_COMPOSER_VRN}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Composer ${_COMPOSER_IS}, update required"
      fi
      cd /var/opt
      rm -rf composer*
      get_dev_src "composer-${_COMPOSER_VRN}.phar.gz"
      if [ -e "/var/opt/composer-${_COMPOSER_VRN}.phar" ]; then
        mv -f composer-${_COMPOSER_VRN}.phar /usr/local/bin/composer
        chmod 755 /usr/local/bin/composer
        ln -sfn /usr/local/bin/composer /usr/bin/composer
        msg "INFO: Composer updated to version ${_COMPOSER_VRN}"
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Composer ${_COMPOSER_VRN}, no action needed"
      fi
    fi
  else
    if [ -x "/usr/local/bin/composer" ]; then
      /usr/local/bin/composer self-update --2 &> /dev/null
    fi
    if [ ! -x "/usr/local/bin/composer" ] || [ ! -L "/usr/bin/composer" ]; then
      rm -f /usr/local/bin/composer
      rm -f /usr/bin/composer
      rm -rf /root/.composer
      mkdir -p /var/opt
      cd /var/opt
      rm -f /var/opt/composer.phar
      curl -sS https://getcomposer.org/installer | php &> /dev/null
      mv -f composer.phar /usr/local/bin/composer
      ln -sfn /usr/local/bin/composer /usr/bin/composer
    fi
    _COMPOSER_IS=$(composer --no-interaction --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f35 \
      | awk '{ print $1}' 2>&1)
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installed Composer ${_COMPOSER_IS}"
    fi
  fi
}
