#
# Fix php.ini files to remove ionCube
_fix_php_ini_ioncube() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_ioncube $1"
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
_remove_php_ini_jsmin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _remove_php_ini_jsmin $1"
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
_remove_php_ini_suhosin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _remove_php_ini_suhosin $1"
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
_fix_php_ini_mailparse() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_mailparse $1"
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
_fix_php_ini_yaml() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_yaml $1"
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
_add_php_ini_jsmin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _add_php_ini_jsmin $1"
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
_fix_php_ini_twig() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_twig $1"
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
_fix_php_ini_redis() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_redis $1"
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
_fix_php_ini_mcrypt() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_mcrypt $1"
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
_fix_php_ini_apcu() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_apcu $1"
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
_fix_php_ini_igbinary() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_igbinary $1"
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
_fix_php_ini_newrelic() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_newrelic $1"
  fi
  _NR_TPL="${_locCnf}/php/newrelic.ini"
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
_fix_php_ini_newrelic_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_newrelic_all $1"
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
      _fix_php_ini_newrelic ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      _fix_php_ini_newrelic ${e}
    done
  fi
}

#
# Fix FMP php.ini file to add opcache.so
_fix_php_ini_opcache() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_opcache $1"
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
_fix_php_ini_opcache_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_opcache_all"
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
      *)  _msg "WARN: Unknown PHP API version for PHP ${e}"
      ;;
    esac
    _THIS_FILE=/opt/php${e}/etc/php${e}.ini
    _OPCACHE_LP="/opt/php${e}/lib/php/extensions/no-debug-non-zts"
    _OPCACHE_SO="${_OPCACHE_LP}-${_P_API}/opcache.so"
    _fix_php_ini_opcache ${e}
  done
}

#
# Fix php.ini file to add php_tet.so
_fix_php_ini_tet() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_tet $1"
  fi
  if [ -e "${_THIS_FILE}" ]; then
    _TET_INI_TEST=$(grep "^extension=php_tet.so" ${_THIS_FILE} 2>&1)
    if [[ "${_TET_INI_TEST}" =~ "extension=php_tet.so" ]]; then
      _DO_NOTHING=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "PROC: php_tet.so already present in ${_THIS_FILE}"
      fi
    else
      echo "extension=php_tet.so" >> ${_THIS_FILE}
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "PROC: Just added php_tet.so to ${_THIS_FILE}"
      fi
    fi
  fi
}

#
# Fix all php.ini files to add php_tet.so
_fix_php_ini_tet_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_tet_all"
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
        *)  _msg "WARN: Unknown PHP API version for PHP ${e}"
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
          _get_dev_src "TET-${_TET_VRN}.tar.gz"
        fi
        if [ -e "/var/opt/TET-${_TET_VRN}/bind/php/php-${e}0-nts" ]; then
          cd /var/opt/TET-${_TET_VRN}/bind/php/php-${e}0-nts/
          cp -a php_tet.so ${_TET_SO}
        fi
      fi
      if [ -e "${_TET_SO}" ]; then
        _THIS_FILE=/opt/php${e}/etc/php${e}.ini
        _fix_php_ini_tet ${e}
        _THIS_FILE=/opt/php${e}/lib/php.ini
        _fix_php_ini_tet ${e}
      fi
    done
  fi
}

#
# Fix php.ini file to add geos.so
_fix_php_ini_geos() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_geos $1"
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
_fix_php_ini_geos_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_geos_all"
  fi
  if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
    _PHP_V="56"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      _fix_php_ini_geos ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      _fix_php_ini_geos ${e}
    done
  fi
}

#
# Fix php.ini file to add mongo.so
_fix_php_ini_mongo() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_mongo $1"
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
_fix_php_ini_mongodb() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_mongodb $1"
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
_fix_php_ini_mongo_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_php_ini_mongo_all"
  fi
  if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
    _PHP_V="56"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      _fix_php_ini_mongo ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      _fix_php_ini_mongo ${e}
    done
    _PHP_V="72 71 70"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      _fix_php_ini_mongodb ${e}
      _THIS_FILE=/opt/php${e}/lib/php.ini
      _fix_php_ini_mongodb ${e}
    done
  fi
}

#
# Update PHP Config.
_php_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_conf_update"
  fi
  if [ -z "${_THISHTIP}" ]; then
    _LOC_DOM="${_THISHOST}"
    _find_correct_ip
    _THISHTIP="${_LOC_IP}"
  fi
  if [ ! -e "/opt/etc/fpm" ] \
    || [ ! -e "/opt/etc/fpm/fpm-pool-common.conf" ]; then
    mkdir -p /opt/etc/fpm
  fi
  cp -af ${_locCnf}/php/fpm-pool-common.conf /opt/etc/fpm/fpm-pool-common.conf
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
      cp -af ${_locCnf}/php/php${e}.ini /opt/php${e}/etc/php${e}.ini
    fi
    cp -af ${_locCnf}/php/fpm${e}-pool-www.conf /opt/php${e}/etc/pool.d/www${e}.conf
    if [ ! -e "/opt/php${e}/lib/php.ini" ]; then
      mkdir -p /opt/php${e}/lib
      cp -af ${_locCnf}/php/php${e}-cli.ini /opt/php${e}/lib/php.ini
    fi
    cp -af ${_locCnf}/php/php${e}.ini /opt/php${e}/etc/php${e}.ini
    cp -af ${_locCnf}/php/php${e}-cli.ini /opt/php${e}/lib/php.ini
    cp -af ${_locCnf}/php/php${e}-fpm.conf /opt/php${e}/etc/php${e}-fpm.conf

    _THIS_FILE=/opt/php${e}/etc/php${e}.ini
    if [ "${e}" != "56" ]; then
      _fix_php_ini_apcu ${e}
    fi
    if [ "${e}" != "56" ] && [ "${e}" != "70" ] && [ "${e}" != "71" ]; then
      _fix_php_ini_mcrypt ${e}
    fi
    if [ "${e}" = "56" ]; then
      _fix_php_ini_mailparse ${e}
      _fix_php_ini_twig ${e}
    fi
    if [ "${e}" != "80" ] && [ "${e}" != "81" ] && [ "${e}" != "82" ] && [ "${e}" != "83" ]; then
      _add_php_ini_jsmin ${e}
    fi
    if [ "${e}" = "80" ] || [ "${e}" = "81" ] || [ "${e}" = "82" ] || [ "${e}" = "83" ]; then
      _remove_php_ini_jsmin ${e}
    fi
    _fix_php_ini_igbinary ${e}
    _fix_php_ini_redis ${e}
    _fix_php_ini_ioncube ${e}
    _remove_php_ini_suhosin ${e}
    _fix_php_ini_yaml ${e}

    _THIS_FILE=/opt/php${e}/lib/php.ini
    if [ "${e}" != "56" ]; then
      _fix_php_ini_apcu ${e}
    fi
    if [ "${e}" != "56" ] && [ "${e}" != "70" ] && [ "${e}" != "71" ]; then
      _fix_php_ini_mcrypt ${e}
    fi
    if [ "${e}" = "56" ]; then
      _fix_php_ini_mailparse ${e}
      _fix_php_ini_twig ${e}
    fi
    if [ "${e}" != "80" ] && [ "${e}" != "81" ] && [ "${e}" != "82" ] && [ "${e}" != "83" ]; then
      _add_php_ini_jsmin ${e}
    fi
    if [ "${e}" = "80" ] || [ "${e}" = "81" ] || [ "${e}" = "82" ] || [ "${e}" = "83" ]; then
      _remove_php_ini_jsmin ${e}
    fi
    _fix_php_ini_igbinary ${e}
    _fix_php_ini_redis ${e}
    _fix_php_ini_ioncube ${e}
    _remove_php_ini_suhosin ${e}
    _fix_php_ini_yaml ${e}

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
  _fix_php_ini_newrelic_all
  _fix_php_ini_geos_all
  _fix_php_ini_mongo_all
  _fix_php_ini_tet_all
  _fix_php_ini_opcache_all
}

#
# Check PHP Config.
_php_config_check_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_config_check_update"
  fi
  _php_conf_update
  _boa_ini_tpl_update
}

#
# Tune Web Sever configuration.
_tune_web_server_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _tune_web_server_config"
  fi
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
  [ ! -z "${_L_PHP_FPM_WORKERS}" ] && _L_PHP_FPM_WORKERS=${_L_PHP_FPM_WORKERS//[^0-9]/}
  [ ! -z "${_L_PHP_FPM_WORKERS}" ] && _LIM_FPM="${_L_PHP_FPM_WORKERS}"
  if [ "${_LIM_FPM}" -lt "48" ]; then
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
      _LIM_FPM=48
    fi
  fi
  if [ "${_PHP_FPM_WORKERS}" != "AUTO" ]; then
    _PHP_FPM_WORKERS=${_PHP_FPM_WORKERS//[^0-9]/}
    if [ ! -z "${_PHP_FPM_WORKERS}" ] && [ "${_PHP_FPM_WORKERS}" -ge "1" ]; then
      _LIM_FPM="${_PHP_FPM_WORKERS}"
    fi
  fi
  if [ "${_LIM_FPM}" -gt "100" ]; then
    _LIM_FPM=100
  fi
  _CHILD_MAX_FPM=$(( _LIM_FPM * 2 ))
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _PHP_FPM_WORKERS is ${_PHP_FPM_WORKERS}"
    _msg "TUNE: _L_PHP_FPM_WORKERS is ${_L_PHP_FPM_WORKERS}"
    _msg "TUNE: _LIM_FPM is ${_LIM_FPM}"
    _msg "TUNE: _CHILD_MAX_FPM is ${_CHILD_MAX_FPM}"
  fi
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  if [ "${_DB_SERIES}" = "5.7" ]; then
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
  fi
  for e in ${_PHP_V}; do
    if [ ! -z "${_CHILD_MAX_FPM}" ] && [ "${_CHILD_MAX_FPM}" -ge "8" ]; then
      sed -i "s/pm.max_children =.*/pm.max_children = ${_CHILD_MAX_FPM}/g" \
         /opt/php${e}/etc/pool.d/www${e}.conf &> /dev/null
      wait
    else
      sed -i "s/pm.max_children =.*/pm.max_children = 8/g" \
         /opt/php${e}/etc/pool.d/www${e}.conf &> /dev/null
      wait
    fi
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
_if_install_php_ioncube() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_php_ioncube"
  fi
  ###--------------------###
  _X86_64_TEST=$(uname -m 2>&1)
  if [ "${_X86_64_TEST}" = "x86_64" ]; then
    _SYSTEM_ARCH="x64"
  else
    _SYSTEM_ARCH="x32"
  fi
  if [ "${_PHP_IONCUBE}" = "YES" ] && [ "${_SYSTEM_ARCH}" = "x64" ]; then
    if [ ! -e "${_pthLog}/ioncube-update-${_IONCUBE_VRN}.log" ] \
      || [ ! -e "/usr/local/ioncube" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      mkdir -p /usr/local/ioncube
      _msg "INFO: Installing IonCube ${_IONCUBE_VRN} for PHP..."
      cd /var/opt
      rm -rf ioncube_loaders*
      _get_dev_arch "ioncube_loaders_lin_x86-64_${_IONCUBE_VRN}.tar.gz"
      rm -f /usr/local/ioncube/*
      cp -af /var/opt/ioncube/* /usr/local/ioncube/ &> /dev/null
      touch ${_pthLog}/ioncube-update-${_IONCUBE_VRN}.log
    fi
  fi
}

#
# Install PHP extensions.
_install_php_extensions() {
  if [ ! -e "${_pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    _pthLog="/var/xdrago_wait/log"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_php_extensions $1"
  fi
  ###--------------------###
  if [ "$1" != "56" ]; then
    _msg "INFO: Installing APCu ${_PHP_APCU} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf apcu*
    _get_dev_src "apcu-${_PHP_APCU}.tgz"
    cd /var/opt/apcu-${_PHP_APCU}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/apcu.so" ]; then
      _msg "WARN: Installing APCu for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/apcu-${_PHP_APCU}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  _USE_PHPREDIS=
  _PHPREDIS_BUILD=
  if [ "$1" = "56" ]; then
    _USE_PHPREDIS="${_PHPREDIS_THREE_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  elif [ "$1" = "70" ] || [ "$1" = "71" ]; then
    _USE_PHPREDIS="${_PHPREDIS_FIVE_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  else
    _USE_PHPREDIS="${_PHPREDIS_SIX_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  fi
  _msg "INFO: Installing PhpRedis ${_USE_PHPREDIS} for PHP ${_T_PHP_VRN}..."
  ldconfig 2> /dev/null
  cd /var/opt
  rm -rf phpredis*
  _get_dev_src "phpredis-${_USE_PHPREDIS}.tar.gz"
  cd /var/opt/phpredis
  _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  _mrun "bash ./configure ${_PHPREDIS_BUILD} --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  _mrun "make -j $(nproc) --quiet" 2> /dev/null
  _mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/redis.so" ]; then
    _msg "WARN: Installing PhpRedis for PHP ${_T_PHP_VRN} failed!"
  else
    touch ${_pthLog}/phpredis-update-${_USE_PHPREDIS}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _USE_IGBINARY="${_PHP_IGBINARY_TWO}"
  else
    _USE_IGBINARY="${_PHP_IGBINARY_THREE}"
  fi
  _msg "INFO: Installing igbinary ${_USE_IGBINARY} for PHP ${_T_PHP_VRN}..."
  cd /var/opt
  rm -rf igbinary*
  _get_dev_src "igbinary-${_USE_IGBINARY}.tgz"
  cd /var/opt/igbinary-${_USE_IGBINARY}
  _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  _mrun "make -j $(nproc) --quiet" 2> /dev/null
  _mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/igbinary.so" ]; then
    _msg "WARN: Installing igbinary for PHP ${_T_PHP_VRN} failed!"
  else
    touch ${_pthLog}/igbinary-${_USE_IGBINARY}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" != "56" ] && [ "$1" != "70" ] && [ "$1" != "71" ]; then
    _msg "INFO: Installing MCRYPT ${_PHP_MCRYPT} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf mcrypt*
    _get_dev_src "mcrypt-${_PHP_MCRYPT}.tgz"
    cd /var/opt/mcrypt-${_PHP_MCRYPT}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mcrypt.so" ]; then
      _msg "WARN: Installing MCRYPT for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/mcrypt-${_PHP_MCRYPT}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _msg "INFO: Installing UploadProgress ${_UPROGRESS_LEGACY_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    _get_dev_src "uploadprogress-${_UPROGRESS_LEGACY_VRN}.tgz"
    cd /var/opt/uploadprogress-${_UPROGRESS_LEGACY_VRN}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
      _msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/f_uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log
    fi
  elif [ "$1" = "72" ] \
    || [ "$1" = "73" ] \
    || [ "$1" = "74" ] \
    || [ "$1" = "80" ] \
    || [ "$1" = "81" ] \
    || [ "$1" = "82" ] \
    || [ "$1" = "83" ]; then
    _msg "INFO: Installing UploadProgress ${_UPROGRESS_EIGHT_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    _get_dev_src "uploadprogress-${_UPROGRESS_EIGHT_VRN}.tgz"
    cd /var/opt/uploadprogress-${_UPROGRESS_EIGHT_VRN}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
      _msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/f_uploadprogress-${_UPROGRESS_EIGHT_VRN}-${_T_PHP_VRN}.log
    fi
  else
    _msg "INFO: Installing UploadProgress ${_UPROGRESS_SEVEN_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    _get_dev_src "uploadprogress-${_UPROGRESS_SEVEN_VRN}.tar.gz"
    cd /var/opt/uploadprogress-${_UPROGRESS_SEVEN_VRN}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
      _msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/f_uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  cd /var/opt
  rm -rf pecl-jsmin*
  if [ "$1" = "56" ]; then
    _msg "INFO: Installing JSMin ${_JSMIN_PHP_LEGACY_VRN} for PHP ${_T_PHP_VRN}..."
    _get_dev_src "pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}.tar.gz"
    cd /var/opt/pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}
  else
    _msg "INFO: Installing JSMin ${_JSMIN_PHP_MODERN_VRN} for PHP ${_T_PHP_VRN}..."
    _get_dev_src "pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}.tar.gz"
    cd /var/opt/pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}
  fi
  _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  _mrun "make -j $(nproc) --quiet" 2> /dev/null
  _mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ]; then
    _msg "WARN: Installing JSMin for PHP ${_T_PHP_VRN} failed!"
  else
    if [ "$1" = "56" ]; then
      touch ${_pthLog}/php-pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
    else
      touch ${_pthLog}/php-pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
    fi
  fi

  ###--------------------###
  if [ "$1" = "56" ]; then
    _msg "INFO: Installing Twig C ${_TWIGC_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf twig*
    _get_dev_src "twig-${_TWIGC_VRN}.tar.gz"
    cd /var/opt/twig-${_TWIGC_VRN}/ext/twig
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/twig.so" ]; then
      _msg "WARN: Installing Twig C for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
    if [ "$1" = "56" ]; then
      _msg "INFO: Building GEOS extension ${_GEOS_VRN} for PHP ${_T_PHP_VRN} from sources..."
      if [ ! -e "${_pthLog}/geos-${_xSrl}-${_X_VERSION}.log" ]; then
        _apt_clean_update
        _st_runner "${_INSTAPP} libgeos-dev libgeos-c1" 2> /dev/null
        touch ${_pthLog}/geos-${_xSrl}-${_X_VERSION}.log
      fi
      cd /var/opt
      rm -rf geos*
      _get_dev_src "geos-${_GEOS_VRN}.tar.bz2"
      cd geos-${_GEOS_VRN}
      _PHP_V="56"
      for e in ${_PHP_V}; do
        if [ "$1" = "${e}" ]; then
          find . -type f -print0 \
            | xargs -0 sed -i 's/\/usr\/local/\/opt\/php${e}/g' &> /dev/null
          wait
        fi
      done
      _mrun "bash ./configure --enable-php" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      touch ${_pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
    if [ "$1" = "56" ]; then
      _msg "INFO: Installing MongoDB driver ${_MONGO_VRN} for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongo*
      _get_dev_src "mongo-${_MONGO_VRN}.tgz"
      cd /var/opt/mongo-${_MONGO_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        _msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log
      fi
    else
      _msg "INFO: Installing MongoDB driver ${_MONGODB_VRN} for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongodb*
      _get_dev_src "mongodb-${_MONGODB_VRN}.tgz"
      cd /var/opt/mongodb-${_MONGODB_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        _msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  _msg "INFO: Installing Imagick ${_IMAGICK_VRN} for PHP ${_T_PHP_VRN}..."
  if [ "${_OS_CODE}" = "daedalus" ] || [ "${_OS_CODE}" = "chimaera" ]; then
    if [ -e "/usr/bin/MagickWand-config" ]; then
      mv -f /usr/bin/MagickWand-config /var/backups/usr-bin-MagickWand-config
    fi
    if [ -e "/usr/local/bin/MagickWand-config" ]; then
      mv -f /usr/local/bin/MagickWand-config /var/backups/usr-local-bin-MagickWand-config
    fi
  fi
  if [ ! -e "${_pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log" ]; then
    _apt_clean_update
    _mrun "${_INSTAPP} libmagickwand-dev" 2> /dev/null
    touch ${_pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log
  fi
  cd /var/opt
  rm -rf imagick*
  _get_dev_src "imagick-${_IMAGICK_VRN}.tgz"
  cd /var/opt/imagick-${_IMAGICK_VRN}
  _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  _mrun "make -j $(nproc) --quiet" 2> /dev/null
  _mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/imagick.so" ]; then
    _msg "WARN: Installing Imagick for PHP ${_T_PHP_VRN} failed!"
  else
    touch ${_pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _msg "INFO: Installing MailParse ${_MAILPARSE_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf mailparse*
    _get_dev_src "mailparse-${_MAILPARSE_VRN}.tgz"
    cd /var/opt/mailparse-${_MAILPARSE_VRN}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mailparse.so" ]; then
      _msg "WARN: Installing MailParse for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ ! -e "${_pthLog}/f_libyaml-${_LIB_YAML_VRN}.log" ] \
    || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ]; then
    _msg "INFO: Installing LibYAML ${_LIB_YAML_VRN} for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf yaml*
    _get_dev_src "yaml-${_LIB_YAML_VRN}.tar.gz"
    cd /var/opt/yaml-${_LIB_YAML_VRN}
    _mrun "sh ./bootstrap" 2> /dev/null
    _mrun "bash ./configure --prefix=/usr" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    touch ${_pthLog}/f_libyaml-${_LIB_YAML_VRN}.log
    rm -f ${_pthLog}/yaml*.log
    rm -f ${_pthLog}/f_yaml*.log
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
    _msg "INFO: Installing YAML ${_YAML_PHP_LEGACY_VRN} for PHP ${_T_PHP_VRN}..."
    _get_dev_src "yaml-${_YAML_PHP_LEGACY_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_PHP_LEGACY_VRN}
  elif [ "$1" = "70" ]; then
    _msg "INFO: Installing YAML ${_YAML_PHP_SEVENO_VRN} for PHP ${_T_PHP_VRN}..."
    _get_dev_src "yaml-${_YAML_PHP_SEVENO_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_PHP_SEVENO_VRN}
  else
    _msg "INFO: Installing YAML ${_YAML_PHP_MODERN_VRN} for PHP ${_T_PHP_VRN}..."
    _get_dev_src "yaml-${_YAML_PHP_MODERN_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_PHP_MODERN_VRN}
  fi
  _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  _mrun "make -j $(nproc) --quiet" 2> /dev/null
  _mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null
  if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
    _msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
  else
    if [ "$1" = "56" ]; then
      touch ${_pthLog}/f_yaml-${_YAML_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
    elif [ "$1" = "70" ]; then
      touch ${_pthLog}/f_yaml-${_YAML_PHP_SEVENO_VRN}-${_T_PHP_VRN}.log
    else
      touch ${_pthLog}/f_yaml-${_YAML_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
    fi
  fi
}

#
# Update extensions for PHP built from sources.
_php_extensions_update() {
  if [ ! -e "${_pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    _pthLog="/var/xdrago_wait/log"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_extensions_update $1"
  fi
  ###--------------------###
  if [ "$1" != "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/apcu.so" ] \
      || [ ! -e "${_pthLog}/apcu-${_PHP_APCU}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing APCu ${_PHP_APCU} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf apcu*
      _get_dev_src "apcu-${_PHP_APCU}.tgz"
      cd /var/opt/apcu-${_PHP_APCU}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/apcu.so" ]; then
        _msg "WARN: Installing APCu for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/apcu-${_PHP_APCU}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  _USE_PHPREDIS=
  _PHPREDIS_BUILD=
  if [ "$1" = "56" ]; then
    _USE_PHPREDIS="${_PHPREDIS_THREE_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  elif [ "$1" = "70" ] || [ "$1" = "71" ]; then
    _USE_PHPREDIS="${_PHPREDIS_FIVE_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  else
    _USE_PHPREDIS="${_PHPREDIS_SIX_VRN}"
    _PHPREDIS_BUILD="--enable-redis-igbinary --enable-redis-lzf"
  fi
  if [ ! -e "${_THIS_PHP_EXT_DIR}/redis.so" ] \
    || [ ! -e "${_pthLog}/phpredis-update-${_USE_PHPREDIS}-${_T_PHP_VRN}.log" ]; then
    _msg "INFO: Installing PhpRedis ${_USE_PHPREDIS} upgrade for PHP ${_T_PHP_VRN}..."
    ldconfig 2> /dev/null
    cd /var/opt
    rm -rf phpredis*
    _get_dev_src "phpredis-${_USE_PHPREDIS}.tar.gz"
    cd /var/opt/phpredis
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure ${_PHPREDIS_BUILD} --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/redis.so" ]; then
      _msg "WARN: Installing PhpRedis for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/phpredis-update-${_USE_PHPREDIS}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    _USE_IGBINARY="${_PHP_IGBINARY_TWO}"
  else
    _USE_IGBINARY="${_PHP_IGBINARY_THREE}"
  fi
  if [ ! -e "${_THIS_PHP_EXT_DIR}/igbinary.so" ] \
    || [ ! -e "${_pthLog}/igbinary-${_USE_IGBINARY}-${_T_PHP_VRN}.log" ]; then
    _msg "INFO: Installing Igbinary ${_USE_IGBINARY} upgrade for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf igbinary*
    _get_dev_src "igbinary-${_USE_IGBINARY}.tgz"
    cd /var/opt/igbinary-${_USE_IGBINARY}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/igbinary.so" ]; then
      _msg "WARN: Installing Igbinary for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/igbinary-${_USE_IGBINARY}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" != "56" ] && [ "$1" != "70" ] && [ "$1" != "71" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mcrypt.so" ] \
      || [ ! -e "${_pthLog}/mcrypt-${_PHP_MCRYPT}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing MCRYPT ${_PHP_MCRYPT} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mcrypt*
      _get_dev_src "mcrypt-${_PHP_MCRYPT}.tgz"
      cd /var/opt/mcrypt-${_PHP_MCRYPT}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mcrypt.so" ]; then
        _msg "WARN: Installing MCRYPT for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/mcrypt-${_PHP_MCRYPT}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ] \
      || [ ! -e "${_pthLog}/f_uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing UploadProgress ${_UPROGRESS_LEGACY_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      _get_dev_src "uploadprogress-${_UPROGRESS_LEGACY_VRN}.tgz"
      cd /var/opt/uploadprogress-${_UPROGRESS_LEGACY_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
        _msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/f_uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log
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
      || [ ! -e "${_pthLog}/f_uploadprogress-${_UPROGRESS_EIGHT_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing UploadProgress ${_UPROGRESS_EIGHT_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      _get_dev_src "uploadprogress-${_UPROGRESS_EIGHT_VRN}.tgz"
      cd /var/opt/uploadprogress-${_UPROGRESS_EIGHT_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
        _msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/f_uploadprogress-${_UPROGRESS_EIGHT_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  else
    if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ] \
      || [ ! -e "${_pthLog}/f_uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing UploadProgress ${_UPROGRESS_SEVEN_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      _get_dev_src "uploadprogress-${_UPROGRESS_SEVEN_VRN}.tar.gz"
      cd /var/opt/uploadprogress-${_UPROGRESS_SEVEN_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/uploadprogress.so" ]; then
        _msg "WARN: Installing UploadProgress for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/f_uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ] \
      || [ ! -e "${_pthLog}/php-pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing JSMin ${_JSMIN_PHP_LEGACY_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf pecl-jsmin*
      _get_dev_src "pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}.tar.gz"
      cd /var/opt/pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ]; then
        _msg "WARN: Installing JSMin for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/php-pecl-jsmin-${_JSMIN_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  else
    if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ] \
      || [ ! -e "${_pthLog}/php-pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing JSMin ${_JSMIN_PHP_MODERN_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf pecl-jsmin*
      _get_dev_src "pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}.tar.gz"
      cd /var/opt/pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/jsmin.so" ]; then
        _msg "WARN: Installing JSMin for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/php-pecl-jsmin-${_JSMIN_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/twig.so" ] \
      || [ ! -e "${_pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing Twig C ${_TWIGC_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf twig*
      _get_dev_src "twig-${_TWIGC_VRN}.tar.gz"
      cd /var/opt/twig-${_TWIGC_VRN}/ext/twig
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/twig.so" ]; then
        _msg "WARN: Installing Twig C for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ] \
    && [ ! -e "${_pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
      _msg "INFO: Building GEOS ${_GEOS_VRN} upgrade for PHP ${_T_PHP_VRN} from sources..."
      if [ ! -e "${_pthLog}/geos-${_xSrl}-${_X_VERSION}.log" ]; then
        _apt_clean_update
        _st_runner "${_INSTAPP} libgeos-dev libgeos-c1" 2> /dev/null
        touch ${_pthLog}/geos-${_xSrl}-${_X_VERSION}.log
      fi
      cd /var/opt
      rm -rf geos*
      _get_dev_src "geos-${_GEOS_VRN}.tar.bz2"
      cd geos-${_GEOS_VRN}
      _PHP_V="56"
      for e in ${_PHP_V}; do
        if [ "$1" = "${e}" ]; then
          find . -type f -print0 \
            | xargs -0 sed -i 's/\/usr\/local/\/opt\/php${e}/g' &> /dev/null
          wait
        fi
      done
      _mrun "bash ./configure --enable-php" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      touch ${_pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ] \
    && [ ! -e "${_pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
      _msg "INFO: Installing MongoDB ${_MONGO_VRN} PHP driver upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongo*
      _get_dev_src "mongo-${_MONGO_VRN}.tgz"
      cd /var/opt/mongo-${_MONGO_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        _msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  if [ "$1" != "56" ] \
    && [ ! -e "${_pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
      _msg "INFO: Installing MongoDB ${_MONGO_VRN} PHP driver upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongodb*
      _get_dev_src "mongodb-${_MONGODB_VRN}.tgz"
      cd /var/opt/mongodb-${_MONGODB_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mongo.so" ]; then
        _msg "WARN: Installing MongoDB driver for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ ! -e "${_THIS_PHP_EXT_DIR}/imagick.so" ] \
    || [ ! -e "${_pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log" ]; then
    _msg "INFO: Installing Imagick ${_IMAGICK_VRN} upgrade for PHP ${_T_PHP_VRN}..."
    if [ "${_OS_CODE}" = "daedalus" ] || [ "${_OS_CODE}" = "chimaera" ]; then
      if [ -e "/usr/bin/MagickWand-config" ]; then
        mv -f /usr/bin/MagickWand-config /var/backups/usr-bin-MagickWand-config
      fi
      if [ -e "/usr/local/bin/MagickWand-config" ]; then
        mv -f /usr/local/bin/MagickWand-config /var/backups/usr-local-bin-MagickWand-config
      fi
    fi
    if [ ! -e "${_pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log" ]; then
      _apt_clean_update
      _mrun "${_INSTAPP} libmagickwand-dev" 2> /dev/null
      touch ${_pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log
    fi
    cd /var/opt
    rm -rf imagick*
    _get_dev_src "imagick-${_IMAGICK_VRN}.tgz"
    cd /var/opt/imagick-${_IMAGICK_VRN}
    _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ ! -e "${_THIS_PHP_EXT_DIR}/imagick.so" ]; then
      _msg "WARN: Installing Imagick for PHP ${_T_PHP_VRN} failed!"
    else
      touch ${_pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/mailparse.so" ] \
      || [ ! -e "${_pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing MailParse ${_MAILPARSE_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mailparse*
      _get_dev_src "mailparse-${_MAILPARSE_VRN}.tgz"
      cd /var/opt/mailparse-${_MAILPARSE_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/mailparse.so" ]; then
        _msg "WARN: Installing MailParse for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
  ###--------------------###
  if [ ! -e "${_pthLog}/f_libyaml-${_LIB_YAML_VRN}.log" ] \
    || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ]; then
    _msg "INFO: Installing LibYAML upgrade for PHP..."
    cd /var/opt
    rm -rf yaml*
    _get_dev_src "yaml-${_LIB_YAML_VRN}.tar.gz"
    cd /var/opt/yaml-${_LIB_YAML_VRN}
    _mrun "sh ./bootstrap" 2> /dev/null
    _mrun "bash ./configure --prefix=/usr" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    touch ${_pthLog}/f_libyaml-${_LIB_YAML_VRN}.log
    rm -f ${_pthLog}/yaml*.log
    rm -f ${_pthLog}/f_yaml*.log
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
      || [ ! -e "${_pthLog}/f_yaml-${_YAML_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing YAML ${_YAML_PHP_LEGACY_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf yaml*
      _get_dev_src "yaml-${_YAML_PHP_LEGACY_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_PHP_LEGACY_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
        _msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/f_yaml-${_YAML_PHP_LEGACY_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  elif [ "$1" = "70" ]; then
    if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ] \
      || [ ! -e "${_pthLog}/f_yaml-${_YAML_PHP_SEVENO_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing YAML ${_YAML_PHP_SEVENO_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf yaml*
      _get_dev_src "yaml-${_YAML_PHP_SEVENO_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_PHP_SEVENO_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
        _msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/f_yaml-${_YAML_PHP_SEVENO_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  else
    if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ] \
      || [ ! -e "${_pthLog}/f_yaml-${_YAML_PHP_MODERN_VRN}-${_T_PHP_VRN}.log" ]; then
      _msg "INFO: Installing YAML ${_YAML_PHP_MODERN_VRN} upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf yaml*
      _get_dev_src "yaml-${_YAML_PHP_MODERN_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_PHP_MODERN_VRN}
      _mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      _mrun "bash ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      if [ ! -e "${_THIS_PHP_EXT_DIR}/yaml.so" ]; then
        _msg "WARN: Installing YAML for PHP ${_T_PHP_VRN} failed!"
      else
        touch ${_pthLog}/f_yaml-${_YAML_PHP_MODERN_VRN}-${_T_PHP_VRN}.log
      fi
    fi
  fi
}

#
# Install modern PHP version
_install_php_multi() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_php_multi $1"
  fi
  _if_to_do_fix
  _get_php_conf_extra
  _PHP_EXTRA=$(echo "${_PHP_EXTRA}" | sed "s/--with-curlwrappers//g" 2>&1)
  ###--------------------###
  _msg "INFO: Building PHP ${_PHP_VERSION} from sources..."
  _apt_clean_update
  _mrun "${_INSTAPP} libonig-dev" 2> /dev/null
  if [[ "${_PHP_EXTRA_CONF}" =~ "--with-tidy" ]] \
    && [ ! -e "${_pthLog}/libtidy-${_LIB_TIDY_VRN}.log" ]; then
    if [ -e "/usr/lib/libtidy.so" ]; then
      _mrun "apt-get remove libtidy-dev -y --purge --auto-remove -qq" 2> /dev/null
      _mrun "apt-get remove libtidy-0.99-0 -y --purge --auto-remove -qq" 2> /dev/null
      _mrun "apt-get remove tidy -y --purge --auto-remove -qq" 2> /dev/null
    fi
    cd /var/opt
    rm -rf tidy*
    _apt_clean_update
    _mrun "${_INSTAPP} cmake" 2> /dev/null
    _get_dev_src "tidy-html5-${_LIB_TIDY_VRN}.tar.gz"
    cd tidy-html5-${_LIB_TIDY_VRN}/build/cmake
    _mrun "cmake ../.. -DCMAKE_INSTALL_PREFIX=/usr/" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      cd /usr/lib
      ln -sfn libtidy.so.${_LIB_TIDY_VRN} libtidy-0.99.so.0
      touch ${_pthLog}/libtidy-${_LIB_TIDY_VRN}.log
    fi
  fi
  cd /var/opt
  rm -rf php*
  _get_dev_src "php-${_PHP_VERSION}.tar.bz2"
  _msg "INFO: Building PHP ${_PHP_VERSION} part 1/3"
  cd /var/opt/php-${_PHP_VERSION}
  if [ "${_OS_CODE}" = "stretch" ] \
    || [ "${_OS_CODE}" = "jessie" ]; then
    _mrun "sh ./buildconf --force" 2> /dev/null
    #_patchFile="disable_SSLv2_for_openssl_1_0_0.patch"
    #patch -p1 < ${_bldPth}/aegir/patches/${_patchFile}
  fi
  ### cd sapi/fpm/fpm
  ### patch -p1 < ${_bldPth}/aegir/patches/fpm_main.c.patch &> /dev/null
  ### cd /var/opt/php-${_PHP_VERSION}
  _msg "INFO: Building PHP ${_PHP_VERSION} part 2/3"
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
      _patchFile="PHP-5.6.31-OpenSSL-1.1.0-compatibility-20170801.patch"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        patch -p1 < ${_bldPth}/aegir/patches/${_patchFile}
      else
        patch -p1 < ${_bldPth}/aegir/patches/${_patchFile} &> /dev/null
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
      _patchFile="freetype.patch"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        patch -p1 < ${_bldPth}/aegir/patches/${_patchFile}
      else
        patch -p1 < ${_bldPth}/aegir/patches/${_patchFile} &> /dev/null
      fi
    fi
    if [ "$1" != "81" ] && [ "$1" != "82" ] && [ "$1" != "83" ]; then
      _patchFile="php-8.1-openssl3.patch"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        patch -p1 < ${_bldPth}/aegir/patches/${_patchFile}
      else
        patch -p1 < ${_bldPth}/aegir/patches/${_patchFile} &> /dev/null
      fi
    fi
  fi
  if [ "${_OS_CODE}" != "jessie" ] \
    && [ ! -e "/root/.rebuild_src_on_auto_before_reboot.info" ] \
    && [ ! -e "/root/.skip-aegir-master-upgrade.cnf" ]; then
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
      _msg "INFO: This PHP ${_PHP_VERSION} is built with:"
      _msg "INFO: ${_DISPLAY_PHP_EXTRA}"
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
                --with-mysql-sock=/run/mysqld/mysqld.sock \
                --with-mysqli=mysqlnd \
                --with-pdo-mysql=mysqlnd \
                --with-pear \
                --with-xsl \
                --with-zlib \
                --with-bz2 \
                ${_PHP_EXTRA} &> /dev/null
  if [ -e "/var/opt/php-${_PHP_VERSION}/Makefile" ]; then
    _msg "INFO: Building PHP ${_PHP_VERSION} part 3/3"
    _msg "WAIT: This may take a while, please wait..."
    sed -i "s/^EXTRA_LIBS = \-lcrypt/EXTRA_LIBS = \-llber \-lcrypt/g" /var/opt/php-${_PHP_VERSION}/Makefile
    _mrun "make -j $(nproc)" 2> /dev/null
    _mrun "make install" 2> /dev/null
    ldconfig 2> /dev/null
  else
    _msg "WARN: No Makefile, configure for PHP ${_PHP_VERSION} failed"
    _msg "INFO: Waiting 60 seconds before trying again..."
    sleep 60
    _msg "INFO: Building PHP ${_PHP_VERSION} part 2/3 (again)"
    _mrun "make clean" 2> /dev/null
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
                --with-mysql-sock=/run/mysqld/mysqld.sock \
                --with-mysqli=mysqlnd \
                --with-pdo-mysql=mysqlnd \
                --with-pear \
                --with-xsl \
                --with-zlib \
                ${_PHP_EXTRA} 2> /dev/null
    if [ -f "/var/opt/php-${_PHP_VERSION}/Makefile" ]; then
      sed -i "s/^EXTRA_LIBS = \-lcrypt/EXTRA_LIBS = \-llber \-lcrypt/g" /var/opt/php-${_PHP_VERSION}/Makefile
      _msg "INFO: Building PHP ${_PHP_VERSION} part 3/3 (again)"
      _msg "WAIT: This may take a while, please wait..."
      _mrun "make -j $(nproc)" 2> /dev/null
      _mrun "make install" 2> /dev/null
      ldconfig 2> /dev/null
    else
      _msg "ALRT: No Makefile, building PHP ${_PHP_VERSION} failed again!"
      _msg "INFO: Waiting 3 minutes for your input or ctrl-c..."
      sleep 180
      _msg "INFO: Moving on..."
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
      _install_php_extensions "$1"
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "WARN: _THIS_PHP_EXT_DIR for PHP $1 empty in _install_php_multi"
      fi
    fi
    rm -f /etc/init.d/php$1-fpm*
    cp -af ${_locCnf}/php/php$1-fpm /etc/init.d/php$1-fpm
    chmod 755 /etc/init.d/php$1-fpm
    if [ -e "/root/.run_post_major_os_upgrade.info" ]; then
      touch ${_pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info
    fi
    _mrun "update-rc.d php$1-fpm defaults" 2> /dev/null
  else
    _msg "WARN: Building PHP ${_PHP_VERSION} failed!"
  fi
}

#
# Update PHP extensions
_php_multi_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_multi_update $1"
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
    _php_extensions_update "$1"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "WARN: _THIS_PHP_EXT_DIR for PHP $1 empty in _php_multi_update"
    fi
  fi
}

#
# Update New Relic.
_newrelic_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _newrelic_update"
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
    _nrList="/etc/apt/sources.list.d/newrelic.list"
    if [ -e "/etc/newrelic/newrelic.cfg" ] \
      || [ -e "/etc/apt/sources.list.d/newrelic.list" ]; then
      _msg "INFO: Uninstalling previous version of New Relic Apps Monitor..."
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
          _msg "INFO: Retrieving ${_NEWRELIC_KEYS_SIG} key..."
        fi
        apt-key del ${_NEWRELIC_KEYS_SIG} &> /dev/null
        if [ ! -e "/etc/apt/keyrings/newrelic.gpg" ]; then
          curl -fsSL ${_urlDev}/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/newrelic.gpg
        fi
        chmod 644 /etc/apt/keyrings/newrelic.gpg
      fi
      _apt_clean_update
      _mrun "${_RMAPP} newrelic-php5 \
        newrelic-php5-common \
        newrelic-daemon \
        newrelic-sysmond" 2> /dev/null
      mkdir -p ${_vBs}/nr
      mv -f /etc/newrelic \
        ${_vBs}/nr/etc-newrelic-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
      _pthNrx="lib/php/extensions/no-debug-non-zts"
      _PHP_EXT_DIR_83="/opt/php83/${_pthNrx}-${_PHP83_API}"
      _PHP_EXT_DIR_82="/opt/php82/${_pthNrx}-${_PHP82_API}"
      _PHP_EXT_DIR_81="/opt/php81/${_pthNrx}-${_PHP81_API}"
      _PHP_EXT_DIR_80="/opt/php80/${_pthNrx}-${_PHP80_API}"
      _PHP_EXT_DIR_74="/opt/php74/${_pthNrx}-${_PHP74_API}"
      _PHP_EXT_DIR_73="/opt/php73/${_pthNrx}-${_PHP73_API}"
      _PHP_EXT_DIR_72="/opt/php72/${_pthNrx}-${_PHP72_API}"
      _msg "INFO: Installing latest version of New Relic Apps Monitor..."
      echo "## New Relic APT Repository" > ${_nrList}
      if [ -e "/etc/apt/keyrings/newrelic.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/newrelic.gpg] http://apt.newrelic.com/debian/ newrelic non-free" >> ${_nrList}
      else
        echo "deb http://apt.newrelic.com/debian/ newrelic non-free" >> ${_nrList}
      fi
      _apt_clean_update
      _st_runner "apt-get install newrelic-php5-common ${_nrmUpArg}" 2> /dev/null
      _st_runner "apt-get install newrelic-daemon ${_nrmUpArg}" 2> /dev/null
      _st_runner "apt-get install newrelic-php5 ${_nrmUpArg}" 2> /dev/null
      # cd /var/opt
      # rm -rf /opt/newrelic*
      # wget -q -U iCab ${_urlDev}/newrelic-php5-common_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${_urlDev}/newrelic-daemon_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${_urlDev}/newrelic-php5_${_NEW_RELIC_VRN}_all.deb
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
      _pthNra="/usr/lib/newrelic-php5/agent"
      if [ -e "${_PHP_EXT_DIR_83}" ] && [ ! -e "${_PHP_EXT_DIR_83}/newrelic.so" ] \
        && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so" ]; then
        ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so \
          ${_PHP_EXT_DIR_83}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_82}" ] && [ ! -e "${_PHP_EXT_DIR_82}/newrelic.so" ] \
        && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so" ]; then
        ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so \
          ${_PHP_EXT_DIR_82}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_81}" ] && [ ! -e "${_PHP_EXT_DIR_81}/newrelic.so" ] \
        && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so" ]; then
        ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so \
          ${_PHP_EXT_DIR_81}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_80}" ] && [ ! -e "${_PHP_EXT_DIR_80}/newrelic.so" ] \
        && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so" ]; then
        ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so \
          ${_PHP_EXT_DIR_80}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_74}" ] && [ ! -e "${_PHP_EXT_DIR_74}/newrelic.so" ] \
        && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so" ]; then
        ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so \
          ${_PHP_EXT_DIR_74}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_73}" ] && [ ! -e "${_PHP_EXT_DIR_73}/newrelic.so" ] \
        && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so" ]; then
        ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so \
          ${_PHP_EXT_DIR_73}/newrelic.so
      fi
      if [ -e "${_PHP_EXT_DIR_72}" ] && [ ! -e "${_PHP_EXT_DIR_72}/newrelic.so" ] \
        && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so" ]; then
        ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so \
          ${_PHP_EXT_DIR_72}/newrelic.so
      fi
      if [ ! -e "/etc/newrelic/newrelic.cfg" ]; then
        echo "## New Relic Configuration" > \
          /etc/newrelic/newrelic.cfg
        echo "license_key=${_NEWRELIC_KEY}" >> \
          /etc/newrelic/newrelic.cfg
        echo "pidfile=/run/newrelic-daemon.pid" >> \
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
_if_install_php_newrelic() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_php_newrelic"
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
    _nrList="/etc/apt/sources.list.d/newrelic.list"
    _PHP_EXT_DIR_83="/opt/php83/lib/php/extensions/no-debug-non-zts-${_PHP83_API}"
    _PHP_EXT_DIR_82="/opt/php82/lib/php/extensions/no-debug-non-zts-${_PHP82_API}"
    _PHP_EXT_DIR_81="/opt/php81/lib/php/extensions/no-debug-non-zts-${_PHP81_API}"
    _PHP_EXT_DIR_80="/opt/php80/lib/php/extensions/no-debug-non-zts-${_PHP80_API}"
    _PHP_EXT_DIR_74="/opt/php74/lib/php/extensions/no-debug-non-zts-${_PHP74_API}"
    _PHP_EXT_DIR_73="/opt/php73/lib/php/extensions/no-debug-non-zts-${_PHP73_API}"
    _PHP_EXT_DIR_72="/opt/php72/lib/php/extensions/no-debug-non-zts-${_PHP72_API}"
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
    if [ "${_MULTI_NR}" = "YES" ] \
      || [ ! -e "${_pthLog}/newrelic-${_xSrl}-${_X_VERSION}.log" ] \
      || [ ! -e "/etc/newrelic/newrelic.cfg" ] \
      || [ ! -e "/etc/newrelic/nrsysmond.cfg" ] \
      || [ ! -e "/etc/apt/trusted.gpg.d/newrelic.gpg" ] \
      || [ ! -e "/etc/apt/keyrings/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg" ] \
      || [ ! -e "/etc/apt/sources.list.d/newrelic.list" ]; then
      _msg "INFO: Installing New Relic Apps Monitor..."
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
          _msg "INFO: Retrieving ${_NEWRELIC_KEYS_SIG} key..."
        fi
        apt-key del ${_NEWRELIC_KEYS_SIG} &> /dev/null
        if [ ! -e "/etc/apt/keyrings/newrelic.gpg" ]; then
          curl -fsSL ${_urlDev}/newrelic-key-${_NEWRELIC_KEYS_SIG}.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/newrelic.gpg
        fi
        chmod 644 /etc/apt/keyrings/newrelic.gpg
      fi
      echo "## New Relic APT Repository" > ${_nrList}
      if [ -e "/etc/apt/keyrings/newrelic.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/newrelic.gpg] http://apt.newrelic.com/debian/ newrelic non-free" >> ${_nrList}
      else
        echo "deb http://apt.newrelic.com/debian/ newrelic non-free" >> ${_nrList}
      fi
      _apt_clean_update
      _st_runner "apt-get install newrelic-php5-common ${_nrmUpArg}" 2> /dev/null
      _st_runner "apt-get install newrelic-daemon ${_nrmUpArg}" 2> /dev/null
      _st_runner "apt-get install newrelic-php5 ${_nrmUpArg}" 2> /dev/null
      # cd /var/opt
      # rm -rf /opt/newrelic*
      # wget -q -U iCab ${_urlDev}/newrelic-php5-common_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${_urlDev}/newrelic-daemon_${_NEW_RELIC_VRN}_all.deb
      # wget -q -U iCab ${_urlDev}/newrelic-php5_${_NEW_RELIC_VRN}_all.deb
      # dpkg -i /var/opt/newrelic-php5-common_${_NEW_RELIC_VRN}_all.deb &> /dev/null
      # dpkg -i /var/opt/newrelic-daemon_${_NEW_RELIC_VRN}_amd64.deb &> /dev/null
      # dpkg -i /var/opt/newrelic-php5_${_NEW_RELIC_VRN}_amd64.deb &> /dev/null
      if [ "${_MULTI_NR}" = "YES" ]; then
        _msg "INFO: Installing latest version of New Relic Apps Monitor..."
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
        _pthNra="/usr/lib/newrelic-php5/agent"
        if [ -e "${_PHP_EXT_DIR_83}" ] && [ ! -e "${_PHP_EXT_DIR_83}/newrelic.so" ] \
          && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so" ]; then
          ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP83_API}.so \
            ${_PHP_EXT_DIR_83}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_82}" ] && [ ! -e "${_PHP_EXT_DIR_82}/newrelic.so" ] \
          && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so" ]; then
          ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP82_API}.so \
            ${_PHP_EXT_DIR_82}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_81}" ] && [ ! -e "${_PHP_EXT_DIR_81}/newrelic.so" ] \
          && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so" ]; then
          ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP81_API}.so \
            ${_PHP_EXT_DIR_81}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_80}" ] && [ ! -e "${_PHP_EXT_DIR_80}/newrelic.so" ] \
          && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so" ]; then
          ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP80_API}.so \
            ${_PHP_EXT_DIR_80}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_74}" ] && [ ! -e "${_PHP_EXT_DIR_74}/newrelic.so" ] \
          && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so" ]; then
          ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP74_API}.so \
            ${_PHP_EXT_DIR_74}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_73}" ] && [ ! -e "${_PHP_EXT_DIR_73}/newrelic.so" ] \
          && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so" ]; then
          ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP73_API}.so \
            ${_PHP_EXT_DIR_73}/newrelic.so
        fi
        if [ -e "${_PHP_EXT_DIR_72}" ] && [ ! -e "${_PHP_EXT_DIR_72}/newrelic.so" ] \
          && [ -e "${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so" ]; then
          ln -sfn ${_pthNra}/${_SYSTEM_ARCH}/newrelic-${_PHP72_API}.so \
            ${_PHP_EXT_DIR_72}/newrelic.so
        fi
        if [ ! -e "/etc/newrelic/newrelic.cfg" ]; then
          echo "## New Relic Configuration" > \
            /etc/newrelic/newrelic.cfg
          echo "license_key=${_NEWRELIC_KEY}" >> \
            /etc/newrelic/newrelic.cfg
          echo "pidfile=/run/newrelic-daemon.pid" >> \
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
    touch ${_pthLog}/newrelic-${_xSrl}-${_X_VERSION}.log
  fi
}

#
# Check if the PHP has correct SSL headers version.
_check_php_ssl_version() {
  # Debug mode: log the start of the function
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_php_ssl_version $1"
  fi

  # Set OpenSSL version based on the OS version
  case "${_OS_CODE}" in
    daedalus|chimaera|beowulf|bookworm|bullseye|buster)
      _OPENSSL_USE_VRN="${_OPENSSL_EOL_VRN}"  # 1.1.1w
      if [ -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
        _OPENSSL_USE_VRN="${_OPENSSL_MODERN_VRN}"  # 3.0.15
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Using modern OpenSSL ${_OPENSSL_USE_VRN} for PHP in ${_OS_CODE} by default"
        fi
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Using EOL OpenSSL ${_OPENSSL_USE_VRN} for PHP in ${_OS_CODE} by default"
        fi
      fi
      ;;
    stretch)
      _OPENSSL_USE_VRN="${_OPENSSL_EOL_VRN}"  # 1.1.1w
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Using EOL OpenSSL ${_OPENSSL_USE_VRN} for PHP in ${_OS_CODE} by default"
      fi
      ;;
    *)
      _OPENSSL_USE_VRN="${_OPENSSL_LEGACY_VRN}"  # 1.0.2u
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Using Legacy OpenSSL ${_OPENSSL_USE_VRN} for PHP in ${_OS_CODE} by default"
      fi
      ;;
  esac

  # Set OpenSSL version based on PHP version and detected OpenSSL version
  case "${1}" in
    56|70|71|72|73)
      if [ -e "/usr/local/ssl/lib/libssl.so.1.1" ]; then
        _OPENSSL_USE_VRN="${_OPENSSL_EOL_VRN}"  # 1.1.1w
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Using EOL OpenSSL ${_OPENSSL_USE_VRN} for PHP ${1}"
        fi
      elif [ -e "/usr/local/ssl/lib/libssl.so.1.0.0" ] \
        || [ -e "/usr/local/ssl/lib/libssl.so.1.0.1" ] \
        || [ -e "/usr/local/ssl/lib/libssl.so.1.0.2" ]; then
        _OPENSSL_USE_VRN="${_OPENSSL_LEGACY_VRN}"  # 1.0.2u
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Using Legacy OpenSSL ${_OPENSSL_LEGACY_VRN} for PHP ${1}"
        fi
      fi
      ;;
  esac

  # Check the installed PHP OpenSSL version
  _PHP_SSL_TEST=$(/opt/php$1/bin/php -i | grep "OpenSSL Header Version" 2>&1)
  _PHP_SSL_LOOK_FOR="${_OPENSSL_USE_VRN}"

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Expected PHP OpenSSL Header Version: ${_PHP_SSL_LOOK_FOR}"
    _msg "INFO: Detected PHP OpenSSL Header Version: ${_PHP_SSL_TEST}"
  fi

  # Return true if mismatch is found, otherwise false
  if [[ ! "${_PHP_SSL_TEST}" =~ "${_PHP_SSL_LOOK_FOR}" ]]; then

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: PHP OpenSSL version mismatch detected, rebuild required"
    fi
    return 1  # SSL version mismatch, rebuild needed
  fi

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: PHP OpenSSL version is correct, no rebuild needed"
  fi
  return 0  # SSL version matches, no rebuild needed
}

#
# Check if the PHP rebuild is required.
_check_php_rebuild() {
  # Debug mode: log the function call
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_php_rebuild $1"
  fi

  _if_to_do_fix

  # Get PHP version (prioritize PHP 7, PHP 5, and PHP 8)
  _PHP_ITD=$(/opt/php$1/bin/php -v | grep -E 'PHP [758]' | awk '{print $2}' 2>&1)
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Detected PHP version: ${_PHP_ITD}"
  fi

  # Compare installed PHP version with expected version
  if [[ "${_PHP_ITD}" != "${_PHP_VERSION}" ]]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Upgrade needed from PHP ${_PHP_ITD} to ${_PHP_VERSION}"
    fi
    _PHP_FORCE_REINSTALL=YES
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: PHP version ${_PHP_VERSION} already installed"
    fi
  fi

  # Run the SSL version check
  if ! _check_php_ssl_version "$1"; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: PHP ${_PHP_ITD} uses incorrect OpenSSL, forcing rebuild"
    fi
    _PHP_FORCE_REINSTALL=YES
  fi

  # Check for presence of PHP drivers
  if [ -x "/opt/php$1/bin/php" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Checking for mysql drivers in PHP $1"
    fi

    if [ "$1" = "56" ]; then
      # Check for 'with-mysql=mysqlnd' in PHP 5.6
      _PHP_DRIVERS=$(/opt/php$1/bin/php -i | grep "with-mysql=mysqlnd" 2>&1)
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Checking for 'with-mysql=mysqlnd' in PHP 5.6"
      fi
    else
      # Check for 'with-mysqli=mysqlnd' in PHP 7 or 8
      _PHP_DRIVERS=$(/opt/php$1/bin/php -i | grep "with-mysqli=mysqlnd" 2>&1)
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Checking for 'with-mysqli=mysqlnd' in PHP $1"
      fi
    fi

    # If drivers are not found, mark build as NO
    if [ -z "${_PHP_DRIVERS}" ]; then
      _PHP_DRIVERS_BUILD=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: PHP $1 has missing mysql drivers, forcing rebuild"
      fi
      _PHP_FORCE_REINSTALL=YES
    else
      _PHP_DRIVERS_BUILD=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: PHP $1 with correct mysql drivers detected"
      fi
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: PHP $1 binary not found, skipping mysql driver check"
    fi
  fi

  # Additional conditions for force rebuild or upgrade
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] || [ "${_PHP_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_DO_FIX}" = "YES" ] || [ "${_STATUS}" != "UPGRADE" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: PHP ${_PHP_ITD} rebuild on next barracuda update"
      fi
      _PHP_FORCE_REINSTALL=NO
    else
      if [ ! -e "${_pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: PHP ${_PHP_ITD} rebuild happening now..."
        fi
        _install_php_multi "$1"
        _PHP_ALREADY_REBUILT=$1
        _PHP_FORCE_REINSTALL=NO
      fi
    fi
  fi
}

#
# Check if the PHP build has broken freetype support.
_check_php_broken_freetype() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_php_broken_freetype $1"
  fi
  _isFreeType=
  _isFreeType=$(/opt/php$1/bin/php -i | grep with-freetype 2>&1)
  if [[ ! "${_isFreeType}" =~ "with-freetype" ]] \
    || [ -z "${_isFreeType}" ]; then
    if [ -x "/usr/bin/freetype-config" ]; then
      if [ ! -e "${_pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
        _msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix freetype support..."
        _install_php_multi "$1"
        _PHP_ALREADY_REBUILT=$1
        _PHP_FORCE_REINSTALL=NO
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "NOTE: PHP ${_PHP_VERSION} was built without freetype support"
      fi
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
}

#
# Check if the PHP build has broken GD support.
_check_php_broken_gd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_php_broken_gd $1"
  fi
  _isGd=
  _isGd=$(/opt/php$1/bin/php -i | grep GD 2>&1)
  if [[ ! "${_isGd}" =~ "GD Support" ]] \
    || [ -z "${_isGd}" ]; then
    if [ ! -e "${_pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
      _msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix GD support..."
      _install_php_multi "$1"
      _PHP_ALREADY_REBUILT=$1
      _PHP_FORCE_REINSTALL=NO
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
}

#
# Check if the PHP build is totally broken.
_check_php_broken_segfault() {
  _isOnig=
  _isOnig=$(/opt/php$1/bin/php -v 2>&1)
  _isSegft=
  _isSegft=$(/opt/php$1/bin/php -v | grep cli 2>&1)
  _isSSLibs=
  _isSSLibs=$(/opt/php$1/bin/php -v 2>&1)
  _isOlog=
  if [ -e "/var/log/php/php$1-fpm-error.log" ]; then
    _isOlog=$(grep OnigEncoding /var/log/php/php$1-fpm-error.log 2>&1)
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_php_broken_segfault $1"
    _msg "CTRL: _isOnig for $1 is ${_isOnig}"
    _msg "CTRL: _isSegft for $1 is ${_isSegft}"
    _msg "CTRL: _isOlog for $1 is ${_isOlog}"
    _msg "CTRL: _isSSLibs for $1 is ${_isSSLibs}"
  fi
  if [[ ! "${_isSegft}" =~ "cli" ]] \
    || [ -z "${_isSegft}" ] \
    || [[ "${_isOnig}" =~ "OnigEncoding" ]] \
    || [[ "${_isSegft}" =~ "OnigEncoding" ]] \
    || [[ "${_isSSLibs}" =~ "no version information" ]] \
    || [[ "${_isOlog}" =~ "OnigEncoding" ]]; then
    if [ ! -e "${_pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ] \
      || [[ "${_isOlog}" =~ "OnigEncoding" ]] \
      || [[ "${_isSSLibs}" =~ "no version information" ]] \
      || [[ "${_isOnig}" =~ "OnigEncoding" ]]; then
      _msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix broken build..."
      _install_php_multi "$1"
      _PHP_ALREADY_REBUILT=$1
      _PHP_FORCE_REINSTALL=NO
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
}

#
# Check if the PHP build is broken.
_check_php_broken() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_php_broken $1"
  fi
  _check_php_broken_segfault "$1"
  _BROKEN_LIBCURL_TEST=$(/opt/php$1/bin/php -v 2>&1)
  if [[ "${_BROKEN_LIBCURL_TEST} " =~ "libcurl.so.4" ]]; then
    if [ ! -e "${_pthLog}/re-installed-php${1}-on-post_major_os_upgrade.info" ]; then
      _PHP_BIN_BROKEN=YES
      _msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix broken libcurl..."
      _curl_install_src
      _install_php_multi "$1"
      _PHP_ALREADY_REBUILT=$1
      _PHP_FORCE_REINSTALL=NO
    fi
  else
    _PHP_ALREADY_REBUILT=
  fi
  _check_php_broken_gd "$1"
  _check_php_broken_freetype "$1"
}

#
# Enable previously disabled PHP-FPM versions
_php_not_used_enable_again() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_not_used_enable_again"
  fi
  _PHP_V="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3"
  for e in ${_PHP_V}; do
    _re=
    if [ ! -e "/opt/php${_re}/bin/php" ]; then
      _re="${e}"
      _re=${_re//[^0-9]/}
      if [ -e "${_vBs}/off-php${_re}-arch/bin/php" ] \
        && [ ! -e "/opt/php${_re}/bin/php" ]; then
        rm -f -r /opt/php${_re}
        mv -f ${_vBs}/off-php${_re}-arch /opt/php${_re}
        _msg "INFO: ${_vBs}/off-php${_re}-arch moved to /opt/php${_re}"
      fi
      if [ -e "${_vBs}/initd-php${_re}-fpm" ]; then
        mv -f ${_vBs}/initd-php${_re}-fpm /etc/init.d/php${_re}-fpm
        chmod 755 /etc/init.d/php${_re}-fpm
        _mrun "update-rc.d php${_re}-fpm defaults" 2> /dev/null
        _mrun "service php${_re}-fpm start" 2> /dev/null
        _msg "INFO: ${_vBs}/initd-php${_re}-fpm moved to /etc/init.d/php${_re}-fpm"
      fi
    fi
  done
  [ -e "/root/.allow-php-multi-install-cleanup.cnf" ] && rm -f /root/.allow-php-multi-install-cleanup.cnf
}

#
# Disable not used PHP-FPM versions
_php_not_used_disable() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_not_used_disable"
  fi
  _PHP_V="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3"
  _PHP_A="${_PHP_MULTI_OPTIM}"
  for e in ${_PHP_V}; do
    _re=
    if [[ ${_PHP_A} == *"${e}"* ]]; then
      _IS_IDLE=NO
    else
      _IS_IDLE=YES
    fi
    if [ "${_IS_IDLE}" = "YES" ]; then
      _re="${e}"
      _re=${_re//[^0-9]/}
      if [ -e "/etc/init.d/php${_re}-fpm" ]; then
        _mrun "service php${_re}-fpm force-quit" 2> /dev/null
        _mrun "update-rc.d -f php${_re}-fpm _remove" 2> /dev/null
        rm -f ${_vBs}/initd-php${_re}-fpm
        mv -f /etc/init.d/php${_re}-fpm ${_vBs}/initd-php${_re}-fpm
        _msg "INFO: /etc/init.d/php${_re}-fpm moved to ${_vBs}/initd-php${_re}-fpm"
      fi
      if [ -e "/opt/php${_re}/bin/php" ]; then
        rm -f -r ${_vBs}/off-php${_re}-arch
        mv -f /opt/php${_re} ${_vBs}/off-php${_re}-arch
        _msg "INFO: /opt/php${_re} moved to ${_vBs}/off-php${_re}-arch"
      else
        rm -f -r /opt/php${_re}
      fi
    fi
  done
}

#
# Fix init.d to disable deprecated PHP-FPM versions
_php_deprecated_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_deprecated_cleanup"
  fi
  _PHP_V="55 54 53"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      _mrun "service php${e}-fpm force-quit" 2> /dev/null
      _mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
      mv -f /etc/init.d/php${e}-fpm ${_vBs}/initd-php${e}-fpm
      _msg "INFO: /etc/init.d/php${e}-fpm moved to ${_vBs}/initd-php${e}-fpm"
    fi
    if [ -e "/opt/php${e}/bin/php" ]; then
      mv -f /opt/php${e} ${_vBs}/off-php${e}-arch
      _msg "INFO: /opt/php${e} moved to ${_vBs}/off-php${e}-arch"
    fi
  done
}

#
# Fix init.d to disable not used PHP-FPM versions
_php_single_initd_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_single_initd_cleanup"
  fi
  if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
    _FPM_INITD_CLEANUP=
    if [ "${_PHP_SINGLE_INSTALL}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
      _PHP_V="82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          _mrun "service php${e}-fpm force-quit" 2> /dev/null
          _mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${_vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${_vBs}/bin-php${e}-cli
        fi
      done
    elif [ "${_PHP_SINGLE_INSTALL}" = "8.2" ] && [ -x "/opt/php82/bin/php" ]; then
      _PHP_V="83 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          _mrun "service php${e}-fpm force-quit" 2> /dev/null
          _mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${_vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${_vBs}/bin-php${e}-cli
        fi
      done
    elif [ "${_PHP_SINGLE_INSTALL}" = "8.1" ] && [ -x "/opt/php81/bin/php" ]; then
      _PHP_V="83 82 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          _mrun "service php${e}-fpm force-quit" 2> /dev/null
          _mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${_vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${_vBs}/bin-php${e}-cli
        fi
      done
    elif [ "${_PHP_SINGLE_INSTALL}" = "7.4" ] && [ -x "/opt/php74/bin/php" ]; then
      _PHP_V="83 82 81 80 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
          _mrun "service php${e}-fpm force-quit" 2> /dev/null
          _mrun "update-rc.d -f php${e}-fpm remove" 2> /dev/null
          mv -f /etc/init.d/php${e}-fpm ${_vBs}/initd-php${e}-fpm
          _FPM_INITD_CLEANUP=YES
        fi
        if [ -e "/opt/php${e}/bin/php" ]; then
          mv -f /opt/php${e}/bin/php ${_vBs}/bin-php${e}-cli
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
_re_set_default_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _re_set_default_php_cli ${_PHP_CLI_VERSION}"
  fi
  if [ "${_PHP_CLI_VERSION}" = "8.3" ]; then
    _switch_php_cli "83"
  elif [ "${_PHP_CLI_VERSION}" = "8.2" ]; then
    _switch_php_cli "82"
  elif [ "${_PHP_CLI_VERSION}" = "8.1" ]; then
    _switch_php_cli "81"
  elif [ "${_PHP_CLI_VERSION}" = "7.4" ]; then
    _switch_php_cli "74"
  fi
}

#
# Fix path to PHP-CLI if needed.
_check_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_php_cli ${_PHP_CLI_VERSION}"
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
    _msg "WAIT: I can not find PHP-CLI anywhere!"
    _msg "NOTE: BOA requires PHP 8.1 or newer"
  fi
}

_switch_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _switch_php_cli $1"
  fi
  _isTest="$1"
  _isTest=${_isTest//[^0-9]/}
  if [ ! -z "${_isTest}" ]; then
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

_php_upgrade_all() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_upgrade_all $1"
  fi
  if [ ! -z "${1}" ] && [ "${1}" != "force" ]; then
    _PHP_V="${1}"
  else
    if [ "${_OS_CODE}" = "stretch" ] || [ "${_OS_CODE}" = "jessie" ]; then
      _PHP_V="56 70 71 72 73 74 80 81"
    else
      _PHP_V="56 70 71 72 73 74 80 81 82 83"
    fi
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
      _switch_php_cli "${e}"
      if [ "${1}" = "force" ]; then
        _install_php_multi "${e}"
      else
        _check_php_broken "${e}"
        _check_php_rebuild "${e}"
      fi
      _php_multi_update "${e}"
      _mrun "service php${e}-fpm reload" 2> /dev/null
      _PHP_VERSION=""
      _T_PHP_VRN=""
      _T_PHP_PTH=""
    fi
  done
}

_get_php_conf_extra() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _get_php_conf_extra"
  fi
  _PHP_EXTRA=""
  if [ -x "/usr/bin/freetype-config" ]; then
    _PHP_EXTRA="--with-freetype-dir=/usr"
  fi
  if [ ! -z "${_PHP_EXTRA_CONF}" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PHP_EXTRA_CONF}"
  fi
}

_php_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_install_upgrade"
  fi
  _if_to_do_fix
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Checking if PHP upgrade is available"
    fi
    _mrun "apt-get remove php5-sasl php5-suhosin -y --purge --auto-remove -qq" 2> /dev/null
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "5.6" ]] \
    && [ ! -x "/opt/php56/bin/php" ]; then
    _PHP_VERSION="${_PHP56_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "56"
    _switch_php_cli "56"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP56_BUILD=56
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.0" ]] \
    && [ ! -x "/opt/php70/bin/php" ]; then
    _PHP_VERSION="${_PHP70_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "70"
    _switch_php_cli "70"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP70_BUILD=70
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.1" ]] \
    && [ ! -x "/opt/php71/bin/php" ]; then
    _PHP_VERSION="${_PHP71_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "71"
    _switch_php_cli "71"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP71_BUILD=71
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.2" ]] \
    && [ ! -x "/opt/php72/bin/php" ]; then
    _PHP_VERSION="${_PHP72_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "72"
    _switch_php_cli "72"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP72_BUILD=72
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.3" ]] \
    && [ ! -x "/opt/php73/bin/php" ]; then
    _PHP_VERSION="${_PHP73_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "73"
    _switch_php_cli "73"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP73_BUILD=73
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "7.4" ]] \
    && [ ! -x "/opt/php74/bin/php" ]; then
    _PHP_VERSION="${_PHP74_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "74"
    _switch_php_cli "74"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP74_BUILD=74
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "8.0" ]] \
    && [ ! -x "/opt/php80/bin/php" ]; then
    _PHP_VERSION="${_PHP80_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "80"
    _switch_php_cli "80"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP80_BUILD=80
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "8.1" ]] \
    && [ ! -x "/opt/php81/bin/php" ]; then
    _PHP_VERSION="${_PHP81_VRN}"
    _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    _install_php_multi "81"
    _switch_php_cli "81"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP81_BUILD=81
  fi
  if [ "${_OS_CODE}" != "stretch" ] && [ "${_OS_CODE}" != "jessie" ]; then
    if [[ "${_PHP_MULTI_INSTALL}" =~ "8.2" ]] \
      && [ ! -x "/opt/php82/bin/php" ]; then
      _PHP_VERSION="${_PHP82_VRN}"
      _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
      _install_php_multi "82"
      _switch_php_cli "82"
      _PHP_VERSION=""
      _T_PHP_VRN=""
      _T_PHP_PTH=""
      _FRESH_PHP82_BUILD=82
    fi
    if [[ "${_PHP_MULTI_INSTALL}" =~ "8.3" ]] \
      && [ ! -x "/opt/php83/bin/php" ]; then
      _PHP_VERSION="${_PHP83_VRN}"
      _msg "INFO: PHP ${_PHP_VERSION} will be installed now"
      _install_php_multi "83"
      _switch_php_cli "83"
      _PHP_VERSION=""
      _T_PHP_VRN=""
      _T_PHP_PTH=""
      _FRESH_PHP83_BUILD=83
    fi
  fi
}

_php_check_if_rebuild() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_check_if_rebuild"
  fi
  _check_php_cli
  _isLber=
  _isLber=$(php -i | grep liblber 2>&1)
  if [[ "${_isLber}" =~ "liblber" ]]; then
    _msg "INFO: PHP rebuild required to fix liblber..."
    _PHP_FORCE_REINSTALL=YES
    _php_if_versions_cleanup_cnf
    _php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  _isSeg=
  _isSeg=$(php -v | grep cli 2>&1)
  if [[ ! "${_isSeg}" =~ "cli" ]] || [ -z "${_isSeg}" ]; then
    _msg "INFO: PHP rebuild required to fix broken libs..."
    _PHP_FORCE_REINSTALL=YES
    _php_if_versions_cleanup_cnf
    _php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  _isOnig=
  _isOnig=$(php -i | grep libonig 2>&1)
  if [[ "${_isOnig}" =~ "libonig.so" ]]; then
    _msg "INFO: PHP rebuild required to fix libonig..."
    _PHP_FORCE_REINSTALL=YES
    _php_if_versions_cleanup_cnf
    _php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  _isIcu=
  _isIcu=$(php -i | grep libicuio 2>&1)
  if [[ "${_isIcu}" =~ "libicuio" ]] \
    || [ ! -e "/usr/local/lib/icu/current" ]; then
    _msg "INFO: PHP rebuild required to fix ICU support..."
    _PHP_FORCE_REINSTALL=YES
    _php_install_deps
    _php_libs_fix
    _php_if_versions_cleanup_cnf
    _php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  if [ -x "/opt/php74/bin/php" ] && [ "${_OS_CODE}" != "jessie" ]; then
    _isSodium=
    _isSodium=$(/opt/php74/bin/php -i | grep with-sodium 2>&1)
    if [[ ! "${_isSodium}" =~ "with-sodium" ]] \
      || [ -z "${_isSodium}" ]; then
      _msg "INFO: PHP rebuild required to add Sodium support..."
      _PHP_FORCE_REINSTALL=YES
      _php_if_versions_cleanup_cnf
      if [ "${_OS_CODE}" = "stretch" ]; then
        _php_upgrade_all "74 80 81"
      else
        _php_upgrade_all "74 80 81 82 83"
      fi
      _PHP_FORCE_REINSTALL=NO
    fi
  fi
  if [ -x "/opt/php56/bin/php" ]; then
    _isIgbinary=
    _isIgbinary=$(/opt/php56/bin/php -i | grep igbinary 2>&1)
    if [[ ! "${_isIgbinary}" =~ "igbinary" ]] \
      || [ -z "${_isIgbinary}" ]; then
      _msg "INFO: PHP 5.6 rebuild required to add igbinary support..."
      _PHP_FORCE_REINSTALL=YES
      _php_if_versions_cleanup_cnf
      _php_upgrade_all "56"
      _PHP_FORCE_REINSTALL=NO
    fi
  fi
  _isWebP=
  _isWebP=$(php -i | grep with-webp 2>&1)
  if [[ ! "${_isWebP}" =~ "with-webp" ]] \
    || [ -z "${_isWebP}" ]; then
    _msg "INFO: PHP rebuild required to add WebP support..."
    _PHP_FORCE_REINSTALL=YES
    _php_if_versions_cleanup_cnf
    _php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
  if [[ "${_PHP_EXTRA_CONF}" =~ "--with-tidy" ]] \
    && [ ! -e "${_pthLog}/libtidy-${_LIB_TIDY_VRN}.log" ]; then
    _apt_clean_update
    _mrun "${_INSTAPP} libonig-dev" 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      _mrun "apt-get remove libtidy-dev -y --purge --auto-remove -qq" 2> /dev/null
      _mrun "apt-get remove libtidy-0.99-0 -y --purge --auto-remove -qq" 2> /dev/null
      _mrun "apt-get remove tidy -y --purge --auto-remove -qq" 2> /dev/null
    fi
    cd /var/opt
    rm -rf tidy*
    _apt_clean_update
    _mrun "${_INSTAPP} cmake" 2> /dev/null
    _get_dev_src "tidy-html5-${_LIB_TIDY_VRN}.tar.gz"
    cd tidy-html5-${_LIB_TIDY_VRN}/build/cmake
    _mrun "cmake ../.. -DCMAKE_INSTALL_PREFIX=/usr/" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      cd /usr/lib
      ln -sfn libtidy.so.${_LIB_TIDY_VRN} libtidy-0.99.so.0
      touch ${_pthLog}/libtidy-${_LIB_TIDY_VRN}.log
    fi
    _msg "INFO: PHP rebuild required to add --with-tidy option..."
    _PHP_FORCE_REINSTALL=YES
    _php_if_versions_cleanup_cnf
    _php_upgrade_all force
    _PHP_FORCE_REINSTALL=NO
  fi
}

_php_ioncube_check_if_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_ioncube_check_if_update"
  fi
  if [ "${_PHP_IONCUBE}" = "YES" ]; then
    if [ ! -e "${_pthLog}/ioncube-update-${_IONCUBE_VRN}.log" ] \
      || [ "${_PHP_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      _if_install_php_ioncube
    fi
  fi
}

_composer_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _composer_install_upgrade"
  fi
  _COMPOSER_FROM_STATIC=NO
  if [ "${_COMPOSER_FROM_STATIC}" = "YES" ]; then
    _COMPOSER_IS=$(composer --no-interaction --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f35 \
      | awk '{ print $1}' 2>&1)
    if [ "${_COMPOSER_IS}" != "${_COMPOSER_VRN}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Composer ${_COMPOSER_IS}, update required"
      fi
      cd /var/opt
      rm -rf composer*
      _get_dev_src "composer-${_COMPOSER_VRN}.phar.gz"
      if [ -e "/var/opt/composer-${_COMPOSER_VRN}.phar" ]; then
        mv -f composer-${_COMPOSER_VRN}.phar /usr/local/bin/composer
        chmod 755 /usr/local/bin/composer
        ln -sfn /usr/local/bin/composer /usr/bin/composer
        _msg "INFO: Composer updated to version ${_COMPOSER_VRN}"
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Composer ${_COMPOSER_VRN}, no action needed"
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
      _msg "INFO: Installed Composer ${_COMPOSER_IS}"
    fi
  fi
}
