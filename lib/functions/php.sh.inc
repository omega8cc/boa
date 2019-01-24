#
# Fix php.ini files to remove ionCube
fix_php_ini_ioncube() {
  if [ -e "${_THIS_FILE}" ] && [ "${_PHP_IONCUBE}" = "NO" ]; then
    _IONCUBE_INI_TEST=$(grep "ioncube_loader" ${_THIS_FILE} 2>&1)
    if [[ "$_IONCUBE_INI_TEST" =~ "ioncube_loader" ]]; then
      sed -i "s/.*ioncube_loader.*//g" ${_THIS_FILE} &> /dev/null
      wait
    fi
  fi
}

#
# Fix php.ini files to remove suhosin.so
fix_php_ini_suhosin() {
  if [ -e "${_THIS_FILE}" ]; then
    _SUHOSIN_INI_TEST=$(grep "^extension=suhosin.so" ${_THIS_FILE} 2>&1)
    if [[ "$_SUHOSIN_INI_TEST" =~ "extension=suhosin.so" ]]; then
      sed -i "s/.*suhosin.*//g" ${_THIS_FILE} &> /dev/null
      wait
    fi
  fi
}

#
# Fix php.ini files to add mailparse.so
fix_php_ini_mailparse() {
  if [ -e "${_THIS_FILE}" ]; then
    _MAILPARSE_INI_TEST=$(grep "^extension=mailparse.so" ${_THIS_FILE} 2>&1)
    if [[ "$_MAILPARSE_INI_TEST" =~ "extension=mailparse.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=mailparse.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add yaml.so
fix_php_ini_yaml() {
  if [ -e "${_THIS_FILE}" ]; then
    _YAML_INI_TEST=$(grep "^extension=yaml.so" ${_THIS_FILE} 2>&1)
    if [[ "$_YAML_INI_TEST" =~ "extension=yaml.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=yaml.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add jsmin.so
fix_php_ini_jsmin() {
  if [ -e "${_THIS_FILE}" ]; then
    _JSMIN_INI_TEST=$(grep "^extension=jsmin.so" ${_THIS_FILE} 2>&1)
    if [[ "$_JSMIN_INI_TEST" =~ "extension=jsmin.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=jsmin.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add twig.so
fix_php_ini_twig() {
  if [ -e "${_THIS_FILE}" ]; then
    _TWIG_INI_TEST=$(grep "^extension=twig.so" ${_THIS_FILE} 2>&1)
    if [[ "$_TWIG_INI_TEST" =~ "extension=twig.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=twig.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini files to add redis.so
fix_php_ini_redis() {
  if [ -e "${_THIS_FILE}" ]; then
    _REDIS_INI_TEST=$(grep "^extension=redis.so" ${_THIS_FILE} 2>&1)
    if [[ "$_REDIS_INI_TEST" =~ "extension=redis.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=redis.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini file to add newrelic.ini
fix_php_ini_newrelic() {
  _NR_TPL="${locCnf}/newrelic.ini"
  if [ -e "${_THIS_FILE}" ]; then
    _NEWRELIC_INI_TEST_A=$(grep "^extension=newrelic.so" ${_THIS_FILE} 2>&1)
    if [[ "$_NEWRELIC_INI_TEST_A" =~ "extension=newrelic.so" ]]; then
      _DO_NOTHING=YES
    else
      cat $_NR_TPL >> ${_THIS_FILE}
    fi
    _NEWRELIC_INI_TEST_B=$(grep "newrelic.framework.drupal.modules" ${_THIS_FILE} 2>&1)
    if [[ "$_NEWRELIC_INI_TEST_B" =~ "newrelic.framework.drupal.modules" ]]; then
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
  if [ -e "/etc/newrelic/newrelic.cfg" ]; then
    if [ -z "${_NEWRELIC_KEY}" ]; then
      _NEWRELIC_KEY=$(grep license_key /etc/newrelic/newrelic.cfg 2>&1)
      _NEWRELIC_KEY=$(echo -n ${_NEWRELIC_KEY} | tr -d "\n" 2>&1)
    fi
    _PHP_V="73 72 71 70 56"
    if [ "${_DB_SERIES}" = "10.3" ] \
      || [ "${_DB_SERIES}" = "10.2" ]; then
      _PHP_V="70 56"
    fi
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_newrelic
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_newrelic
    done
  fi
}

#
# Fix FMP php.ini file to add opcache.so
fix_php_ini_opcache() {
  if [ -e "${_THIS_FILE}" ]; then
    _OPCACHE_INI_TEST=$(grep "opcache.so" ${_THIS_FILE} 2>&1)
    if [[ "$_OPCACHE_INI_TEST" =~ "opcache.so" ]]; then
      _DO_NOTHING=YES
    else
      echo ";"                                    >> ${_THIS_FILE}
      echo "; Zend OPcache"                       >> ${_THIS_FILE}
      echo "zend_extension=\"$_OPCACHE_SO\""      >> ${_THIS_FILE}
      echo "opcache.enable=1"                     >> ${_THIS_FILE}
      echo "opcache.memory_consumption=181"       >> ${_THIS_FILE}
      echo "opcache.revalidate_freq=0"            >> ${_THIS_FILE}
      echo ";"                                    >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix all FMP php.ini files to add Zend OPcache
fix_php_ini_opcache_all() {
  _PHP_V="73 72 71 70 56"
  if [ "${_DB_SERIES}" = "10.3" ] \
    || [ "${_DB_SERIES}" = "10.2" ]; then
    _PHP_V="70 56"
  fi
  for e in ${_PHP_V}; do
    case "${e}" in
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
    fix_php_ini_opcache "${e}"
  done
}

#
# Fix php.ini file to add php_tet.so
fix_php_ini_tet() {
  if [ -e "${_THIS_FILE}" ]; then
    _TET_INI_TEST=$(grep "^extension=php_tet.so" ${_THIS_FILE} 2>&1)
    if [[ "$_TET_INI_TEST" =~ "extension=php_tet.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=php_tet.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix all php.ini files to add php_tet.so
fix_php_ini_tet_all() {
  if [ "${_PHP_TET}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "TET" ]]; then
    _PHP_V="56 55"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_tet
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_tet
    done
  fi
}

#
# Fix php.ini file to add geos.so
fix_php_ini_geos() {
  if [ -e "${_THIS_FILE}" ]; then
    _GEOS_INI_TEST=$(grep "^extension=geos.so" ${_THIS_FILE} 2>&1)
    if [[ "$_GEOS_INI_TEST" =~ "extension=geos.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=geos.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix all php.ini files to add geos.so
fix_php_ini_geos_all() {
  if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
    _PHP_V="56"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_geos
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_geos
    done
  fi
}

#
# Fix php.ini file to add mongo.so
fix_php_ini_mongo() {
  if [ -e "${_THIS_FILE}" ]; then
    _MONGO_INI_TEST=$(grep "^extension=mongo.so" ${_THIS_FILE} 2>&1)
    if [[ "$_MONGO_INI_TEST" =~ "extension=mongo.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=mongo.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix php.ini file to add mongodb.so
fix_php_ini_mongodb() {
  if [ -e "${_THIS_FILE}" ]; then
    _MONGODB_INI_TEST=$(grep "^extension=mongodb.so" ${_THIS_FILE} 2>&1)
    if [[ "$_MONGODB_INI_TEST" =~ "extension=mongodb.so" ]]; then
      _DO_NOTHING=YES
    else
      echo "extension=mongodb.so" >> ${_THIS_FILE}
    fi
  fi
}

#
# Fix all php.ini files to add mongo.so or mongodb.so
fix_php_ini_mongo_all() {
  if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
    _PHP_V="56"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_mongo
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_mongo
    done
    _PHP_V="70"
    for e in ${_PHP_V}; do
      _THIS_FILE=/opt/php${e}/etc/php${e}.ini
      fix_php_ini_mongodb
      _THIS_FILE=/opt/php${e}/lib/php.ini
      fix_php_ini_mongodb
    done
  fi
}

#
# Check PHP Config.
check_update_php_config() {
  update_php_conf
  update_ini_tpl
}

#
# Update PHP Config.
update_php_conf() {
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
  _PHP_V="73 72 71 70 56"
  if [ "${_DB_SERIES}" = "10.3" ] \
    || [ "${_DB_SERIES}" = "10.2" ]; then
    _PHP_V="70 56"
  fi
  for e in ${_PHP_V}; do
    if [ ! -e "/var/www/www${e}" ]; then
      adduser --system --group --home /var/www/www${e} www${e} &> /dev/null
      usermod -aG www-data www${e} &> /dev/null
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
    if [ "${e}" = "56" ]; then
      fix_php_ini_mailparse
      fix_php_ini_twig
    fi
    fix_php_ini_jsmin
    fix_php_ini_redis
    fix_php_ini_ioncube
    fix_php_ini_suhosin
    fix_php_ini_yaml
    _THIS_FILE=/opt/php${e}/lib/php.ini
    if [ "${e}" = "56" ]; then
      fix_php_ini_mailparse
      fix_php_ini_twig
    fi
    fix_php_ini_jsmin
    fix_php_ini_redis
    fix_php_ini_ioncube
    fix_php_ini_suhosin
    fix_php_ini_yaml
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
# Tune Web Sever configuration.
tune_web_server_config() {
  _LIM_FPM="${_L_PHP_FPM_WORKERS}"
  if [ "${_LIM_FPM}" -lt "48" ]; then
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      _LIM_FPM=48
    fi
  fi
  _PROCESS_MAX_FPM=$(( _LIM_FPM * 5 ))
  _CHILD_MAX_FPM=$(( _LIM_FPM * 2 ))
  if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
    _DO_NOTHING=YES
  else
    _PHP_FPM_WORKERS=${_PHP_FPM_WORKERS//[^0-9]/}
    if [ ! -z "${_PHP_FPM_WORKERS}" ] && [ "${_PHP_FPM_WORKERS}" -gt "0" ]; then
      _CHILD_MAX_FPM="${_PHP_FPM_WORKERS}"
    fi
  fi
  _PHP_V="73 72 71 70 56"
  if [ "${_DB_SERIES}" = "10.3" ] \
    || [ "${_DB_SERIES}" = "10.2" ]; then
    _PHP_V="70 56"
  fi
  for e in ${_PHP_V}; do
    sed -i "s/process.max =.*/process.max = ${_PROCESS_MAX_FPM}/g" \
      /opt/php${e}/etc/php${e}-fpm.conf &> /dev/null
    wait
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
  if [ ! -z "${_L_NGX_WRKS}" ]; then
    sed -i "s/worker_processes.*/worker_processes  ${_L_NGX_WRKS};/g" /etc/nginx/nginx.conf    &> /dev/null
    wait
  else
    sed -i "s/worker_processes.*/worker_processes  4;/g" /etc/nginx/nginx.conf                 &> /dev/null
    wait
  fi
}

#
# Install IonCube.
install_ioncube() {
  ###--------------------###
  if [ ! -e "${pthLog}/ioncube-${_IONCUBE_VRN}.log" ] \
    || [ ! -e "/usr/local/ioncube" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    mkdir -p /usr/local/ioncube
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      SYSTEMARCH="x86_64"
      msg "INFO: Installing IonCube ${_IONCUBE_VRN} for PHP..."
      cd /var/opt
      rm -rf ioncube_loaders*
      get_dev_arch "ioncube_loaders_lin_x86-64_${_IONCUBE_VRN}.tar.gz"
    else
      SYSTEMARCH="x86"
      msg "INFO: Installing IonCube ${_IONCUBE_VRN} for PHP..."
      cd /var/opt
      rm -rf ioncube_loaders*
      get_dev_arch "ioncube_loaders_lin_x86_${_IONCUBE_VRN}.tar.gz"
    fi
    rm -f /usr/local/ioncube/*
    cp -af /var/opt/ioncube/* /usr/local/ioncube/ &> /dev/null
    touch ${pthLog}/ioncube-${_IONCUBE_VRN}.log
  fi
}

#
# Install PHP extensions.
install_php_extensions() {
  ###--------------------###
  _USE_PHPREDIS="${_PHPREDIS_VRN}"
  msg "INFO: Installing PhpRedis for PHP ${_T_PHP_VRN}..."
  cd /var/opt
  rm -rf phpredis*
  get_dev_src "phpredis-${_USE_PHPREDIS}.tar.gz"
  cd /var/opt/phpredis
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  touch ${pthLog}/phpredis-${_USE_PHPREDIS}-${_T_PHP_VRN}.log
  ###--------------------###
  if [ "$1" = "56" ]; then
    msg "INFO: Installing UploadProgress for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    get_dev_src "uploadprogress-${_UPROGRESS_LEGACY_VRN}.tgz"
    cd /var/opt/uploadprogress-${_UPROGRESS_LEGACY_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log
  else
    msg "INFO: Installing UploadProgress for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf uploadprogress*
    get_dev_src "uploadprogress-${_UPROGRESS_SEVEN_VRN}.tar.gz"
    cd /var/opt/uploadprogress-${_UPROGRESS_SEVEN_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  msg "INFO: Installing JSMin for PHP ${_T_PHP_VRN}..."
  cd /var/opt
  rm -rf pecl-jsmin*
  if [ "$1" = "56" ]; then
    get_dev_src "pecl-jsmin-${_JSMIN_VRN}.tar.gz"
    cd /var/opt/pecl-jsmin-${_JSMIN_VRN}
  else
    get_dev_src "pecl-jsmin-${_JSMIN_PHP7_VRN}.tar.gz"
    cd /var/opt/pecl-jsmin-${_JSMIN_PHP7_VRN}
  fi
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  if [ "$1" = "56" ]; then
    touch ${pthLog}/php-pecl-jsmin-${_JSMIN_VRN}-${_T_PHP_VRN}.log
  else
    touch ${pthLog}/php-pecl-jsmin-${_JSMIN_PHP7_VRN}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    msg "INFO: Installing Twig C for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf twig*
    get_dev_src "twig-${_TWIGC_VRN}.tar.gz"
    cd /var/opt/twig-${_TWIGC_VRN}/ext/twig
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
    if [ "$1" = "56" ]; then
      msg "INFO: Building GEOS extension for PHP ${_T_PHP_VRN} from sources..."
      if [ ! -e "${pthLog}/geos-${_X_VERSION}.log" ]; then
        rm -f /etc/apt/sources.list.d/openssl.list
        st_runner "apt-get update -qq" &> /dev/null
        st_runner "${_INSTAPP} libgeos-dev libgeos-c1" 2> /dev/null
        touch ${pthLog}/geos-${_X_VERSION}.log
      fi
      cd /var/opt
      rm -rf geos*
      get_dev_src "geos-${_GEOS_VRN}.tar.bz2"
      cd geos-${_GEOS_VRN}
      _PHP_V="73 72 71 70 56"
      if [ "${_DB_SERIES}" = "10.3" ] \
        || [ "${_DB_SERIES}" = "10.2" ]; then
        _PHP_V="70 56"
      fi
      for e in ${_PHP_V}; do
        if [ "$1" = "${e}" ]; then
          find . -type f -print0 \
            | xargs -0 sed -i 's/\/usr\/local/\/opt\/php${e}/g' &> /dev/null
          wait
        fi
      done
      mrun "sh ./configure --enable-php" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
    if [ "$1" = "56" ]; then
      msg "INFO: Installing MongoDB driver for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongo*
      get_dev_src "mongo-${_MONGO_VRN}.tgz"
      cd /var/opt/mongo-${_MONGO_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log
    else
      msg "INFO: Installing MongoDB driver for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongodb*
      get_dev_src "mongodb-${_MONGODB_VRN}.tgz"
      cd /var/opt/mongodb-${_MONGODB_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  msg "INFO: Installing Imagick for PHP ${_T_PHP_VRN}..."
  if [ ! -e "${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log" ]; then
    mrun "apt-get install libmagickwand-dev ${forCer}" 2> /dev/null
    touch ${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log
  fi
  cd /var/opt
  rm -rf imagick*
  get_dev_src "imagick-${_IMAGICK_VRN}.tgz"
  cd /var/opt/imagick-${_IMAGICK_VRN}
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  touch ${pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log
  ###--------------------###
  if [ "$1" = "56" ]; then
    msg "INFO: Installing MailParse for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf mailparse*
    get_dev_src "mailparse-${_MAILPARSE_VRN}.tgz"
    cd /var/opt/mailparse-${_MAILPARSE_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ ! -e "${pthLog}/libyaml-${_LIB_YAML_VRN}.log" ] \
    || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.2" ] \
    || [ -e "/usr/lib/i386-linux-gnu/libyaml-0.so.2.0.2" ]; then
    msg "INFO: Installing LibYAML for PHP..."
    cd /var/opt
    rm -rf yaml*
    get_dev_src "yaml-${_LIB_YAML_VRN}.tar.gz"
    cd /var/opt/yaml-${_LIB_YAML_VRN}
    mrun "sh ./bootstrap" 2> /dev/null
    mrun "sh ./configure --prefix=/usr" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/libyaml-${_LIB_YAML_VRN}.log
    rm -f ${pthLog}/yaml*.log
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      if [ ! -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ] \
        || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.2" ]; then
        mkdir -p /var/backups/libyaml
        mkdir -p /usr/lib/x86_64-linux-gnu
        cp -af /usr/lib/x86_64-linux-gnu/libyaml* /var/backups/libyaml/ &> /dev/null
        rm -f /usr/lib/x86_64-linux-gnu/libyaml*
        cp -af /usr/lib/libyaml* /usr/lib/x86_64-linux-gnu/ &> /dev/null
      fi
    else
      if [ ! -e "/usr/lib/i386-linux-gnu/libyaml-0.so.2.0.4" ] \
        || [ -e "/usr/lib/i386-linux-gnu/libyaml-0.so.2.0.2" ]; then
        mkdir -p /var/backups/libyaml
        mkdir -p /usr/lib/i386-linux-gnu
        cp -af /usr/lib/i386-linux-gnu/libyaml* /var/backups/libyaml/ &> /dev/null
        rm -f /usr/lib/i386-linux-gnu/libyaml*
        cp -af /usr/lib/libyaml* /usr/lib/i386-linux-gnu/ &> /dev/null
      fi
    fi
  fi
  msg "INFO: Installing YAML for PHP ${_T_PHP_VRN}..."
  cd /var/opt
  rm -rf yaml*
  if [ "$1" = "56" ]; then
    get_dev_src "yaml-${_YAML_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_VRN}
  else
    get_dev_src "yaml-${_YAML_PHP7_VRN}.tgz"
    cd /var/opt/yaml-${_YAML_PHP7_VRN}
  fi
  mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
  mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
  mrun "make --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
  touch ${pthLog}/yaml-${_YAML_VRN}-${_T_PHP_VRN}.log
}

#
# Update extensions for PHP built from sources.
update_php_extensions() {
  ###--------------------###
  _USE_PHPREDIS="${_PHPREDIS_VRN}"
  if [ ! -e "${pthLog}/phpredis-${_USE_PHPREDIS}-${_T_PHP_VRN}.log" ]; then
    msg "INFO: Installing PhpRedis upgrade for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf phpredis*
    get_dev_src "phpredis-${_USE_PHPREDIS}.tar.gz"
    cd /var/opt/phpredis
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/phpredis-${_USE_PHPREDIS}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${pthLog}/uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing UploadProgress upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      get_dev_src "uploadprogress-${_UPROGRESS_LEGACY_VRN}.tgz"
      cd /var/opt/uploadprogress-${_UPROGRESS_LEGACY_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/uploadprogress-${_UPROGRESS_LEGACY_VRN}-${_T_PHP_VRN}.log
    fi
  else
    if [ ! -e "${pthLog}/uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing UploadProgress upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf uploadprogress*
      get_dev_src "uploadprogress-${_UPROGRESS_SEVEN_VRN}.tar.gz"
      cd /var/opt/uploadprogress-${_UPROGRESS_SEVEN_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/uploadprogress-${_UPROGRESS_SEVEN_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${pthLog}/php-pecl-jsmin-${_JSMIN_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing JSMin for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf pecl-jsmin*
      get_dev_src "pecl-jsmin-${_JSMIN_VRN}.tar.gz"
      cd /var/opt/pecl-jsmin-${_JSMIN_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-pecl-jsmin-${_JSMIN_VRN}-${_T_PHP_VRN}.log
    fi
  else
    if [ ! -e "${pthLog}/php-pecl-jsmin-${_JSMIN_PHP7_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing JSMin for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf pecl-jsmin*
      get_dev_src "pecl-jsmin-${_JSMIN_PHP7_VRN}.tar.gz"
      cd /var/opt/pecl-jsmin-${_JSMIN_PHP7_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-pecl-jsmin-${_JSMIN_PHP7_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing Twig C upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf twig*
      get_dev_src "twig-${_TWIGC_VRN}.tar.gz"
      cd /var/opt/twig-${_TWIGC_VRN}/ext/twig
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-twig-${_TWIGC_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ] \
    && [ ! -e "${pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_GEOS}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "GEO" ]]; then
      msg "INFO: Building GEOS upgrade for PHP ${_T_PHP_VRN} from sources..."
      if [ ! -e "${pthLog}/geos-${_X_VERSION}.log" ]; then
        rm -f /etc/apt/sources.list.d/openssl.list
        st_runner "apt-get update -qq" &> /dev/null
        st_runner "${_INSTAPP} libgeos-dev libgeos-c1" 2> /dev/null
        touch ${pthLog}/geos-${_X_VERSION}.log
      fi
      cd /var/opt
      rm -rf geos*
      get_dev_src "geos-${_GEOS_VRN}.tar.bz2"
      cd geos-${_GEOS_VRN}
      _PHP_V="73 72 71 70 56"
      if [ "${_DB_SERIES}" = "10.3" ] \
        || [ "${_DB_SERIES}" = "10.2" ]; then
        _PHP_V="70 56"
      fi
      for e in ${_PHP_V}; do
        if [ "$1" = "${e}" ]; then
          find . -type f -print0 \
            | xargs -0 sed -i 's/\/usr\/local/\/opt\/php${e}/g' &> /dev/null
          wait
        fi
      done
      mrun "sh ./configure --enable-php" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-geos-${_GEOS_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ "$1" = "56" ] \
    && [ ! -e "${pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
      msg "INFO: Installing MongoDB PHP driver upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongo*
      get_dev_src "mongo-${_MONGO_VRN}.tgz"
      cd /var/opt/mongo-${_MONGO_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-mongo-${_MONGO_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  if [ "$1" != "56" ] \
    && [ ! -e "${pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log" ]; then
    if [ "${_PHP_MONGODB}" = "YES" ] || [[ "${_XTRAS_LIST}" =~ "MNG" ]]; then
      msg "INFO: Installing MongoDB PHP driver upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mongodb*
      get_dev_src "mongodb-${_MONGODB_VRN}.tgz"
      cd /var/opt/mongodb-${_MONGODB_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/php-mongodb-${_MONGODB_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ ! -e "${pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log" ]; then
    msg "INFO: Installing Imagick upgrade for PHP ${_T_PHP_VRN}..."
    if [ ! -e "${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log" ]; then
      mrun "apt-get install libmagickwand-dev ${forCer}" 2> /dev/null
      touch ${pthLog}/libmagickwand-dev-${_IMAGICK_VRN}-rebuild.log
    fi
    cd /var/opt
    rm -rf imagick*
    get_dev_src "imagick-${_IMAGICK_VRN}.tgz"
    cd /var/opt/imagick-${_IMAGICK_VRN}
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/imagick-${_IMAGICK_VRN}-${_T_PHP_VRN}.log
  fi
  ###--------------------###
  if [ "$1" = "56" ]; then
    if [ ! -e "${pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log" ]; then
      msg "INFO: Installing MailParse upgrade for PHP ${_T_PHP_VRN}..."
      cd /var/opt
      rm -rf mailparse*
      get_dev_src "mailparse-${_MAILPARSE_VRN}.tgz"
      cd /var/opt/mailparse-${_MAILPARSE_VRN}
      mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
      mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      touch ${pthLog}/mailparse-${_MAILPARSE_VRN}-${_T_PHP_VRN}.log
    fi
  fi
  ###--------------------###
  if [ ! -e "${pthLog}/libyaml-${_LIB_YAML_VRN}.log" ] \
    || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.2" ] \
    || [ -e "/usr/lib/i386-linux-gnu/libyaml-0.so.2.0.2" ]; then
    msg "INFO: Installing LibYAML upgrade for PHP..."
    cd /var/opt
    rm -rf yaml*
    get_dev_src "yaml-${_LIB_YAML_VRN}.tar.gz"
    cd /var/opt/yaml-${_LIB_YAML_VRN}
    mrun "sh ./bootstrap" 2> /dev/null
    mrun "sh ./configure --prefix=/usr" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/libyaml-${_LIB_YAML_VRN}.log
    rm -f ${pthLog}/yaml*.log
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      if [ ! -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.4" ] \
        || [ -e "/usr/lib/x86_64-linux-gnu/libyaml-0.so.2.0.2" ]; then
        mkdir -p /var/backups/libyaml
        cp -af /usr/lib/x86_64-linux-gnu/libyaml* /var/backups/libyaml/ &> /dev/null
        rm -f /usr/lib/x86_64-linux-gnu/libyaml*
        cp -af /usr/lib/libyaml* /usr/lib/x86_64-linux-gnu/
      fi
    else
      if [ ! -e "/usr/lib/i386-linux-gnu/libyaml-0.so.2.0.4" ] \
        || [ -e "/usr/lib/i386-linux-gnu/libyaml-0.so.2.0.2" ]; then
        mkdir -p /var/backups/libyaml
        cp -af /usr/lib/i386-linux-gnu/libyaml* /var/backups/libyaml/
        rm -f /usr/lib/i386-linux-gnu/libyaml*
        cp -af /usr/lib/libyaml* /usr/lib/i386-linux-gnu/
      fi
    fi
  fi
  if [ ! -e "${pthLog}/yaml-${_YAML_VRN}-${_T_PHP_VRN}.log" ]; then
    msg "INFO: Installing YAML upgrade for PHP ${_T_PHP_VRN}..."
    cd /var/opt
    rm -rf yaml*
    if [ "$1" = "56" ]; then
      get_dev_src "yaml-${_YAML_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_VRN}
    else
      get_dev_src "yaml-${_YAML_PHP7_VRN}.tgz"
      cd /var/opt/yaml-${_YAML_PHP7_VRN}
    fi
    mrun "${_T_PHP_PTH}/phpize" 2> /dev/null
    mrun "sh ./configure --with-php-config=${_T_PHP_CFG}" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    touch ${pthLog}/yaml-${_YAML_VRN}-${_T_PHP_VRN}.log
  fi
}

#
# Install modern PHP version
install_php_multi() {
  if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
    && [ "${_LOC_OSV}" = "jessie" ]; then
    _DO_FIX=YES
  fi
  _PHP_EXTRA=$(echo "${_PHP_EXTRA}" | sed "s/--with-curlwrappers//g" 2>&1)
  ###--------------------###
  msg "INFO: Building PHP ${_PHP_VERSION} from sources, please wait..."
  if [[ "${_PHP_EXTRA_CONF}" =~ "--with-tidy" ]] \
    && [ ! -e "${pthLog}/libtidy-${_LIB_TIDY_VRN}.log" ]; then
    if [ -e "/usr/lib/libtidy.so" ]; then
      mrun "apt-get remove libtidy-dev -y -qq" &> /dev/null
      mrun "apt-get remove libtidy-0.99-0 -y -qq" &> /dev/null
      mrun "apt-get remove tidy -y -qq" &> /dev/null
    fi
    cd /var/opt
    rm -rf tidy*
    mrun "${_INSTALL} cmake" 2> /dev/null
    get_dev_src "tidy-html5-${_LIB_TIDY_VRN}.tar.gz"
    cd tidy-html5-${_LIB_TIDY_VRN}/build/cmake
    mrun "cmake ../.. -DCMAKE_INSTALL_PREFIX=/usr/" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      cd /usr/lib
      ln -sf libtidy.so.${_LIB_TIDY_VRN} libtidy-0.99.so.0
      touch ${pthLog}/libtidy-${_LIB_TIDY_VRN}.log
    fi
  fi
  cd /var/opt
  rm -rf php*
  get_dev_src "php-${_PHP_VERSION}.tar.bz2"
  msg "INFO: Building PHP ${_PHP_VERSION} part 1/3"
  cd /var/opt/php-${_PHP_VERSION}
  mrun "sh ./buildconf --force" 2> /dev/null
  if [ "${_OSV}" = "jessie" ] \
    || [ "${_OSV}" = "stretch" ] \
    || [ "${_DO_FIX}" = "YES" ] \
    || [ "${_OSV}" = "trusty" ] \
    || [ "${_OSV}" = "precise" ]; then
    patchFile="disable_SSLv2_for_openssl_1_0_0.patch"
    patch -p1 < ${bldPth}/aegir/patches/${patchFile} &> /dev/null
  fi
  ### cd sapi/fpm/fpm
  ### patch -p1 < ${bldPth}/aegir/patches/fpm_main.c.patch &> /dev/null
  ### cd /var/opt/php-${_PHP_VERSION}
  msg "INFO: Building PHP ${_PHP_VERSION} part 2/3"
  if [ "$1" = "73" ]; then
    _PHP_EXTRA="${_PHP_EXTRA}"
  elif [ "$1" = "72" ]; then
    _PHP_EXTRA="${_PHP_EXTRA}"
  elif [ "$1" = "71" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} --enable-gd-native-ttf --with-mcrypt"
  elif [ "$1" = "70" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} --enable-gd-native-ttf --with-mcrypt"
  elif [ "$1" = "56" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} --enable-gd-native-ttf --with-mcrypt --with-mysql=/usr"
    if [ "${_OSV}" = "stretch" ]; then
      patchFile="PHP-5.6.31-OpenSSL-1.1.0-compatibility-20170801.patch"
      patch -p1 < ${bldPth}/aegir/patches/${patchFile} &> /dev/null
    fi
  fi
  _PHP_EXTRA="${_PHP_EXTRA} --enable-opcache"
  mrun "sh ./configure \
                --quiet \
                --prefix=/opt/php$1 \
                --enable-fpm \
                --enable-bcmath \
                --enable-calendar \
                --enable-exif \
                --enable-ftp \
                --enable-mbstring \
                --enable-opcache \
                --enable-pcntl \
                --enable-soap \
                --enable-zip \
                --with-curl \
                --with-fpm-group=www-data \
                --with-fpm-user=www-data \
                --with-freetype-dir=/usr \
                --with-gd \
                --with-imap \
                --with-imap-ssl \
                --with-jpeg-dir=/usr \
                --with-kerberos \
                --with-mysql-sock=/var/run/mysqld/mysqld.sock \
                --with-mysqli=/usr/bin/mysql_config \
                --with-openssl \
                --with-pdo-mysql=/usr \
                --with-pear \
                --with-png-dir=/usr \
                --with-xmlrpc \
                --with-xsl \
                --with-zlib \
                ${_PHP_EXTRA}" 2> /dev/null
  msg "INFO: Building PHP ${_PHP_VERSION} part 3/3"
  if [ -f "/var/opt/php-${_PHP_VERSION}/Makefile" ]; then
    sed -i "s/^EXTRA_LIBS = -lcrypt/EXTRA_LIBS = -llber -lcrypt/g" /var/opt/php-${_PHP_VERSION}/Makefile
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
  else
    msg "INFO: Building PHP ${_PHP_VERSION} part 2/3 (again)"
    mrun "make --quiet clean" 2> /dev/null
    mrun "sh ./configure \
                --quiet \
                --prefix=/opt/php$1 \
                --enable-fpm \
                --enable-bcmath \
                --enable-calendar \
                --enable-exif \
                --enable-ftp \
                --enable-mbstring \
                --enable-opcache \
                --enable-pcntl \
                --enable-soap \
                --enable-zip \
                --with-curl \
                --with-fpm-group=www-data \
                --with-fpm-user=www-data \
                --with-freetype-dir=/usr \
                --with-gd \
                --with-imap \
                --with-imap-ssl \
                --with-jpeg-dir=/usr \
                --with-kerberos \
                --with-mysql-sock=/var/run/mysqld/mysqld.sock \
                --with-mysqli=/usr/bin/mysql_config \
                --with-openssl \
                --with-pdo-mysql=/usr \
                --with-pear \
                --with-png-dir=/usr \
                --with-xmlrpc \
                --with-xsl \
                --with-zlib \
                ${_PHP_EXTRA}" 2> /dev/null
    sed -i "s/^EXTRA_LIBS = -lcrypt/EXTRA_LIBS = -llber -lcrypt/g" /var/opt/php-${_PHP_VERSION}/Makefile
    msg "INFO: Building PHP ${_PHP_VERSION} part 3/3 (again)"
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
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
    install_php_extensions "$1"
    if [ -e "/root/.mstr.clstr.cnf" ] \
      || [ -e "/root/.wbhd.clstr.cnf" ] \
      || [ -e "/root/.dbhd.clstr.cnf" ]; then
      _T_DBS_VRN="${_GALERA_10_VRN}"
    else
      if [ "${_DB_SERIES}" = "10.0" ]; then
        sed -i "s/^_DB_SERIES=.*/_DB_SERIES=10.1/g" ${barCnf}
        _DB_SERIES=10.1
      fi
      sed -i "s/^_DB_SERIES=5.5/_DB_SERIES=10.1/g"  ${barCnf}
      if [ "${_DB_SERIES}" = "10.3" ] \
        || [ "${_DB_SERIES}" = "10.2" ] \
        || [ "${_DB_SERIES}" = "10.1" ] \
        || [ "${_DB_SERIES}" = "10.0" ] \
        || [ "${_DB_SERIES}" = "5.7" ] \
        || [ "${_DB_SERIES}" = "5.5" ]; then
        if [ "${_DB_SERIES}" = "10.3" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_3_VRN}"
        elif [ "${_DB_SERIES}" = "10.2" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_2_VRN}"
        elif [ "${_DB_SERIES}" = "10.1" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_1_VRN}"
        elif [ "${_DB_SERIES}" = "5.7" ]; then
          _DB_SERVER=Percona
          _DBS_VRN="${_PERCONA_5_7_VRN}"
        else
          _DB_SERVER=MariaDB
          _DB_SERIES=10.1
          _DBS_VRN="${_MARIADB_10_1_VRN}"
        fi
        _T_DBS_VRN="${_DBS_VRN}"
      else
        _T_DBS_VRN="${_DBS_VRN}"
      fi
    fi
    touch ${pthLog}/installed-${_PHP_VERSION}-${_T_DBS_VRN}-${_DB_SERVER}.log
    rm -f /etc/init.d/php$1-fpm*
    cp -af ${locCnf}/php$1-fpm /etc/init.d/php$1-fpm
    chmod 755 /etc/init.d/php$1-fpm
    mrun "update-rc.d php$1-fpm defaults" &> /dev/null
  else
    msg "WARN: Building PHP ${_PHP_VERSION} failed!"
  fi
}

#
# Update PHP extensions
update_php_multi() {
  _T_PHP_VRN="${_PHP_VERSION}"
  _T_PHP_PTH="/opt/php$1/bin"
  _T_PHP_CFG="/opt/php$1/bin/php-config"
  update_php_extensions "$1"
}

#
# Update New Relic.
update_newrelic() {
  ###--------------------###
  if [ ! -z "${_NEWRELIC_KEY}" ]; then
    if [ -x "/usr/bin/gpg2" ]; then
      _GPG=gpg2
    else
      _GPG=gpg
    fi
    if [ -e "/etc/newrelic/newrelic.cfg" ] \
      || [ -e "${aptLiSys}.d/newrelic.list" ]; then
      msg "INFO: Uninstalling previous version of New Relic Apps Monitor..."
      cd /var/opt
      _KEYS_SERVER_TEST=FALSE
      until [[ "${_KEYS_SERVER_TEST}" =~ "GnuPG" ]]; do
        rm -f 548C16BF.gpg*
        wget -q -U iCab http://download.newrelic.com/548C16BF.gpg
        _KEYS_SERVER_TEST=$(grep GnuPG 548C16BF.gpg 2>&1)
        sleep 2
      done
      cat 548C16BF.gpg | ${_GPG} --import &> /dev/null
      rm -f 548C16BF.gpg*
      st_runner "aptitude remove newrelic-php5 \
                                 newrelic-php5-common \
                                 newrelic-daemon \
                                 newrelic-sysmond -y" &> /dev/null
      mkdir -p ${vBs}/nr
      mv -f /etc/newrelic \
        ${vBs}/nr/etc-newrelic-pre-${_X_VERSION}-${_NOW} &> /dev/null
      pthNrx="lib/php/extensions/no-debug-non-zts"
      _PHP_EXT_DIR_73="/opt/php73/${pthNrx}-${_PHP73_API}"
      _PHP_EXT_DIR_72="/opt/php72/${pthNrx}-${_PHP72_API}"
      _PHP_EXT_DIR_71="/opt/php71/${pthNrx}-${_PHP71_API}"
      _PHP_EXT_DIR_70="/opt/php70/${pthNrx}-${_PHP70_API}"
      _PHP_EXT_DIR_56="/opt/php56/${pthNrx}-${_PHP56_API}"
      msg "INFO: Installing latest version of New Relic Apps Monitor..."
      echo "## New Relic APT Repository" > ${aptLiSys}.d/newrelic.list
      echo "deb http://apt.newrelic.com/debian/ newrelic non-free" \
        >> ${aptLiSys}.d/newrelic.list
      rm -f /etc/apt/sources.list.d/openssl.list
      st_runner "apt-get update -qq" &> /dev/null
      st_runner "apt-get install newrelic-php5 ${nrmUpArg}" 2> /dev/null
      st_runner "apt-get install newrelic-sysmond ${nrmUpArg}" 2> /dev/null
      NR_PHPLIST="/opt/php56/bin:/opt/php70/bin:/opt/php71/bin:/opt/php72/bin:/opt/php73/bin"
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
      if [ -e "$_PHP_EXT_DIR_73" ] && [ ! -e "$_PHP_EXT_DIR_73/newrelic.so" ] \
        && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP73_API}.so" ]; then
        ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP73_API}.so \
          $_PHP_EXT_DIR_73/newrelic.so
      fi
      if [ -e "$_PHP_EXT_DIR_72" ] && [ ! -e "$_PHP_EXT_DIR_72/newrelic.so" ] \
        && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP72_API}.so" ]; then
        ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP72_API}.so \
          $_PHP_EXT_DIR_72/newrelic.so
      fi
      if [ -e "$_PHP_EXT_DIR_71" ] && [ ! -e "$_PHP_EXT_DIR_71/newrelic.so" ] \
        && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP71_API}.so" ]; then
        ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP71_API}.so \
          $_PHP_EXT_DIR_71/newrelic.so
      fi
      if [ -e "$_PHP_EXT_DIR_70" ] && [ ! -e "$_PHP_EXT_DIR_70/newrelic.so" ] \
        && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP70_API}.so" ]; then
        ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP70_API}.so \
          $_PHP_EXT_DIR_70/newrelic.so
      fi
      if [ -e "$_PHP_EXT_DIR_56" ] && [ ! -e "$_PHP_EXT_DIR_56/newrelic.so" ] \
        && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP56_API}.so" ]; then
        ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP56_API}.so \
          $_PHP_EXT_DIR_56/newrelic.so
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
install_newrelic() {
  ###--------------------###
  if [ ! -z "${_NEWRELIC_KEY}" ]; then
    if [ -x "/usr/bin/gpg2" ]; then
      _GPG=gpg2
    else
      _GPG=gpg
    fi
    _MULTI_NR=NO
    _PHP_EXT_DIR_73="/opt/php73/lib/php/extensions/no-debug-non-zts-${_PHP73_API}"
    _PHP_EXT_DIR_72="/opt/php72/lib/php/extensions/no-debug-non-zts-${_PHP72_API}"
    _PHP_EXT_DIR_71="/opt/php71/lib/php/extensions/no-debug-non-zts-${_PHP71_API}"
    _PHP_EXT_DIR_70="/opt/php70/lib/php/extensions/no-debug-non-zts-${_PHP70_API}"
    _PHP_EXT_DIR_56="/opt/php56/lib/php/extensions/no-debug-non-zts-${_PHP56_API}"
    if [ -e "$_PHP_EXT_DIR_73" ] \
      && [ ! -e "$_PHP_EXT_DIR_73/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "$_PHP_EXT_DIR_72" ] \
      && [ ! -e "$_PHP_EXT_DIR_72/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "$_PHP_EXT_DIR_71" ] \
      && [ ! -e "$_PHP_EXT_DIR_71/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "$_PHP_EXT_DIR_70" ] \
      && [ ! -e "$_PHP_EXT_DIR_70/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ -e "$_PHP_EXT_DIR_56" ] \
      && [ ! -e "$_PHP_EXT_DIR_56/newrelic.so" ]; then
      _MULTI_NR=YES
    fi
    if [ "$_MULTI_NR" = "YES" ] \
      || [ ! -e "${pthLog}/newrelic-${_X_VERSION}.log" ] \
      || [ ! -e "/etc/newrelic/newrelic.cfg" ] \
      || [ ! -e "/etc/newrelic/nrsysmond.cfg" ] \
      || [ ! -e "${aptLiSys}.d/newrelic.list" ]; then
      msg "INFO: Installing New Relic Apps Monitor..."
      cd /var/opt
      _KEYS_SERVER_TEST=FALSE
      until [[ "${_KEYS_SERVER_TEST}" =~ "GnuPG" ]]; do
        rm -f 548C16BF.gpg*
        wget -q -U iCab http://download.newrelic.com/548C16BF.gpg
        _KEYS_SERVER_TEST=$(grep GnuPG 548C16BF.gpg 2>&1)
        sleep 2
      done
      cat 548C16BF.gpg | ${_GPG} --import &> /dev/null
      rm -f 548C16BF.gpg*
      echo "## New Relic APT Repository" > \
        ${aptLiSys}.d/newrelic.list
      echo "deb http://apt.newrelic.com/debian/ newrelic non-free" \
        >> ${aptLiSys}.d/newrelic.list
      rm -f /etc/apt/sources.list.d/openssl.list
      st_runner "apt-get update -qq" &> /dev/null
      st_runner "apt-get install newrelic-php5 ${nrmUpArg}" 2> /dev/null
      st_runner "apt-get install newrelic-sysmond ${nrmUpArg}" 2> /dev/null
      if [ "$_MULTI_NR" = "YES" ]; then
        msg "INFO: Installing latest version of New Relic Apps Monitor..."
        NR_PHPLIST="/opt/php56/bin:/opt/php70/bin:/opt/php71/bin:/opt/php72/bin:/opt/php73/bin"
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
        if [ -e "$_PHP_EXT_DIR_73" ] && [ ! -e "$_PHP_EXT_DIR_73/newrelic.so" ] \
          && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP73_API}.so" ]; then
          ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP73_API}.so \
            $_PHP_EXT_DIR_73/newrelic.so
        fi
        if [ -e "$_PHP_EXT_DIR_72" ] && [ ! -e "$_PHP_EXT_DIR_72/newrelic.so" ] \
          && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP72_API}.so" ]; then
          ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP72_API}.so \
            $_PHP_EXT_DIR_72/newrelic.so
        fi
        if [ -e "$_PHP_EXT_DIR_71" ] && [ ! -e "$_PHP_EXT_DIR_71/newrelic.so" ] \
          && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP71_API}.so" ]; then
          ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP71_API}.so \
            $_PHP_EXT_DIR_71/newrelic.so
        fi
        if [ -e "$_PHP_EXT_DIR_70" ] && [ ! -e "$_PHP_EXT_DIR_70/newrelic.so" ] \
          && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP70_API}.so" ]; then
          ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP70_API}.so \
            $_PHP_EXT_DIR_70/newrelic.so
        fi
        if [ -e "$_PHP_EXT_DIR_56" ] && [ ! -e "$_PHP_EXT_DIR_56/newrelic.so" ] \
          && [ -e "${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP56_API}.so" ]; then
          ln -sf ${pthNra}/$_SYSTEM_ARCH/newrelic-${_PHP56_API}.so \
            $_PHP_EXT_DIR_56/newrelic.so
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
    touch ${pthLog}/newrelic-${_X_VERSION}.log
  fi
}

#
# Check if the PHP rebuild is required.
check_php_rebuild() {
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_PHP_FORCE_REINSTALL}" = "YES" ]; then
    _PHP_ITD=5.x
    if [ "$1" = "73" ]; then
      rm -f ${pthLog}/installed-7.3*
    elif [ "$1" = "72" ]; then
      rm -f ${pthLog}/installed-7.2*
    elif [ "$1" = "71" ]; then
      rm -f ${pthLog}/installed-7.1*
    elif [ "$1" = "70" ]; then
      rm -f ${pthLog}/installed-7.0*
    elif [ "$1" = "56" ]; then
      rm -f ${pthLog}/installed-5.6*
    fi
    msg "INFO: PHP to ${_PHP_VERSION} rebuild forced"
  else
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
  fi
  if [ -x "/opt/php$1/bin/php" ]; then
    _PHP_DRIVERS=$(/opt/php$1/bin/php -i | grep "with-mysql-sock" 2>&1)
    if [ -z "${_PHP_DRIVERS}" ]; then
      _PHP_DRIVERS_BUILD=NO
    else
      _PHP_DRIVERS_BUILD=YES
    fi
  fi
  if [ "${_PHP_DRIVERS_BUILD}" = "NO" ] \
    || [[ "${_PHP_ITD}" =~ "~" ]] \
    || [[ "${_PHP_ITD}" =~ "dotdeb" ]] \
    || [[ "${_PHP_ITD}" =~ "ubuntu" ]]; then
    msg "INFO: Installed PHP version ${_PHP_ITD}, upgrade required"
    install_php_multi "$1"
  else
    if [[ "${_PHP_ITD}" =~ "${_PHP_VERSION}" ]]; then
      if [ "$_UP_PHP" = "YES" ]; then
        if [ ! -z "${_PHP_ALREADY_REBUILT}" ] \
          && [ "${_PHP_ALREADY_REBUILT}" = "$1" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed PHP version ${_PHP_ITD}, OK"
          fi
        else
          msg "INFO: PHP ${_PHP_VERSION} rebuild required to include upgraded libs"
          install_php_multi "$1"
        fi
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installed PHP version ${_PHP_ITD}, OK"
        fi
      fi
    else
      if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
        || [ "${_PHP_FORCE_REINSTALL}" = "YES" ]; then
        _DO_NOTHING=YES
      else
        msg "INFO: Installed PHP version ${_PHP_ITD}, upgrade required"
      fi
      install_php_multi "$1"
    fi
  fi
  if [ "${_DB_SERIES}" = "10.3" ] \
    || [ "${_DB_SERIES}" = "10.2" ] \
    || [ "${_DB_SERIES}" = "10.1" ] \
    || [ "${_DB_SERIES}" = "10.0" ] \
    || [ "${_DB_SERIES}" = "5.7" ] \
    || [ "${_DB_SERIES}" = "5.5" ]; then
    if [ "${_DB_SERIES}" = "10.3" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_3_VRN}"
    elif [ "${_DB_SERIES}" = "10.2" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_2_VRN}"
    elif [ "${_DB_SERIES}" = "10.1" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_1_VRN}"
    elif [ "${_DB_SERIES}" = "5.7" ]; then
      _DB_SERVER=Percona
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    else
      _DB_SERVER=MariaDB
      _DB_SERIES=10.1
      _DBS_VRN="${_MARIADB_10_1_VRN}"
    fi
    _T_DBS_VRN="${_DBS_VRN}"
  else
    _T_DBS_VRN="${_DBS_VRN}"
  fi
  # if [ ! -e "${pthLog}/installed-${_PHP_VERSION}-${_T_DBS_VRN}-${_DB_SERVER}.log" ]; then
  #   msg "INFO: PHP ${_PHP_VERSION} rebuild required for ${_DB_SERVER} ${_T_DBS_VRN}"
  #   install_php_multi "$1"
  # fi
}

#
# Check if the PHP build is broken.
check_php_broken() {
  _BROKEN_LIBCURL_TEST=$(/opt/php$1/bin/php -v 2>&1)
  if [[ "$_BROKEN_LIBCURL_TEST" =~ "libcurl.so.4" ]]; then
    _PHP_BIN_BROKEN=YES
    msg "INFO: PHP ${_PHP_VERSION} rebuild required to fix broken libcurl"
    install_curl_src
    install_php_multi "$1"
    _PHP_ALREADY_REBUILT=$1
  else
    _PHP_ALREADY_REBUILT=
  fi
}

#
# Fix init.d to disable deprecated PHP-FPM versions
php_deprecated_cleanup() {
  if [ -e "/opt/php55/bin/php" ]; then
    mv -f /opt/php55/bin/php ${vBs}/bin-php55-cli
  fi
  if [ -e "/opt/php54/bin/php" ]; then
    mv -f /opt/php54/bin/php ${vBs}/bin-php54-cli
  fi
  if [ -e "/opt/php53/bin/php" ]; then
    mv -f /opt/php53/bin/php ${vBs}/bin-php53-cli
  fi
  if [ -e "/etc/init.d/php55-fpm" ]; then
    service php55-fpm stop &> /dev/null
    update-rc.d -f php55-fpm remove &> /dev/null
    mv -f /etc/init.d/php55-fpm ${vBs}/initd-php55-fpm
  fi
  if [ -e "/etc/init.d/php54-fpm" ]; then
    service php54-fpm stop &> /dev/null
    update-rc.d -f php54-fpm remove &> /dev/null
    mv -f /etc/init.d/php54-fpm ${vBs}/initd-php54-fpm
  fi
  if [ -e "/etc/init.d/php53-fpm" ]; then
    service php53-fpm stop &> /dev/null
    update-rc.d -f php53-fpm remove &> /dev/null
    mv -f /etc/init.d/php53-fpm ${vBs}/initd-php53-fpm
  fi
}

#
# Fix init.d to disable not used PHP-FPM versions
php_single_initd_cleanup() {
  if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
    if [ "${_PHP_SINGLE_INSTALL}" = "7.3" ]; then
      if [ -e "/opt/php72/bin/php" ]; then
        mv -f /opt/php72/bin/php ${vBs}/bin-php72-cli
      fi
      if [ -e "/opt/php71/bin/php" ]; then
        mv -f /opt/php71/bin/php ${vBs}/bin-php71-cli
      fi
      if [ -e "/opt/php70/bin/php" ]; then
        mv -f /opt/php70/bin/php ${vBs}/bin-php70-cli
      fi
      if [ -e "/opt/php56/bin/php" ]; then
        mv -f /opt/php56/bin/php ${vBs}/bin-php56-cli
      fi
      if [ -e "/etc/init.d/php72-fpm" ]; then
        update-rc.d -f php72-fpm remove &> /dev/null
        mv -f /etc/init.d/php72-fpm ${vBs}/initd-php72-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php71-fpm" ]; then
        update-rc.d -f php71-fpm remove &> /dev/null
        mv -f /etc/init.d/php71-fpm ${vBs}/initd-php71-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php70-fpm" ]; then
        update-rc.d -f php70-fpm remove &> /dev/null
        mv -f /etc/init.d/php70-fpm ${vBs}/initd-php70-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php56-fpm" ]; then
        update-rc.d -f php56-fpm remove &> /dev/null
        mv -f /etc/init.d/php56-fpm ${vBs}/initd-php56-fpm
        _FPM_INITD_CLEANUP=YES
      fi
    elif [ "${_PHP_SINGLE_INSTALL}" = "7.2" ]; then
      if [ -e "/opt/php73/bin/php" ]; then
        mv -f /opt/php73/bin/php ${vBs}/bin-php73-cli
      fi
      if [ -e "/opt/php71/bin/php" ]; then
        mv -f /opt/php71/bin/php ${vBs}/bin-php71-cli
      fi
      if [ -e "/opt/php70/bin/php" ]; then
        mv -f /opt/php70/bin/php ${vBs}/bin-php70-cli
      fi
      if [ -e "/opt/php56/bin/php" ]; then
        mv -f /opt/php56/bin/php ${vBs}/bin-php56-cli
      fi
      if [ -e "/etc/init.d/php73-fpm" ]; then
        update-rc.d -f php73-fpm remove &> /dev/null
        mv -f /etc/init.d/php73-fpm ${vBs}/initd-php73-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php71-fpm" ]; then
        update-rc.d -f php71-fpm remove &> /dev/null
        mv -f /etc/init.d/php71-fpm ${vBs}/initd-php71-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php70-fpm" ]; then
        update-rc.d -f php70-fpm remove &> /dev/null
        mv -f /etc/init.d/php70-fpm ${vBs}/initd-php70-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php56-fpm" ]; then
        update-rc.d -f php56-fpm remove &> /dev/null
        mv -f /etc/init.d/php56-fpm ${vBs}/initd-php56-fpm
        _FPM_INITD_CLEANUP=YES
      fi
    elif [ "${_PHP_SINGLE_INSTALL}" = "7.1" ]; then
      if [ -e "/opt/php73/bin/php" ]; then
        mv -f /opt/php73/bin/php ${vBs}/bin-php73-cli
      fi
      if [ -e "/opt/php72/bin/php" ]; then
        mv -f /opt/php72/bin/php ${vBs}/bin-php72-cli
      fi
      if [ -e "/opt/php70/bin/php" ]; then
        mv -f /opt/php70/bin/php ${vBs}/bin-php70-cli
      fi
      if [ -e "/opt/php56/bin/php" ]; then
        mv -f /opt/php56/bin/php ${vBs}/bin-php56-cli
      fi
      if [ -e "/etc/init.d/php73-fpm" ]; then
        update-rc.d -f php73-fpm remove &> /dev/null
        mv -f /etc/init.d/php73-fpm ${vBs}/initd-php73-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php72-fpm" ]; then
        update-rc.d -f php72-fpm remove &> /dev/null
        mv -f /etc/init.d/php72-fpm ${vBs}/initd-php72-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php70-fpm" ]; then
        update-rc.d -f php70-fpm remove &> /dev/null
        mv -f /etc/init.d/php70-fpm ${vBs}/initd-php70-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php56-fpm" ]; then
        update-rc.d -f php56-fpm remove &> /dev/null
        mv -f /etc/init.d/php56-fpm ${vBs}/initd-php56-fpm
        _FPM_INITD_CLEANUP=YES
      fi
    elif [ "${_PHP_SINGLE_INSTALL}" = "7.0" ]; then
      if [ -e "/opt/php73/bin/php" ]; then
        mv -f /opt/php73/bin/php ${vBs}/bin-php73-cli
      fi
      if [ -e "/opt/php72/bin/php" ]; then
        mv -f /opt/php72/bin/php ${vBs}/bin-php72-cli
      fi
      if [ -e "/opt/php71/bin/php" ]; then
        mv -f /opt/php71/bin/php ${vBs}/bin-php71-cli
      fi
      if [ -e "/opt/php56/bin/php" ]; then
        mv -f /opt/php56/bin/php ${vBs}/bin-php56-cli
      fi
      if [ -e "/etc/init.d/php73-fpm" ]; then
        update-rc.d -f php73-fpm remove &> /dev/null
        mv -f /etc/init.d/php73-fpm ${vBs}/initd-php73-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php72-fpm" ]; then
        update-rc.d -f php72-fpm remove &> /dev/null
        mv -f /etc/init.d/php72-fpm ${vBs}/initd-php72-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php71-fpm" ]; then
        update-rc.d -f php71-fpm remove &> /dev/null
        mv -f /etc/init.d/php71-fpm ${vBs}/initd-php71-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php56-fpm" ]; then
        update-rc.d -f php56-fpm remove &> /dev/null
        mv -f /etc/init.d/php56-fpm ${vBs}/initd-php56-fpm
        _FPM_INITD_CLEANUP=YES
      fi
    elif [ "${_PHP_SINGLE_INSTALL}" = "5.6" ]; then
      if [ -e "/opt/php73/bin/php" ]; then
        mv -f /opt/php73/bin/php ${vBs}/bin-php73-cli
      fi
      if [ -e "/opt/php72/bin/php" ]; then
        mv -f /opt/php72/bin/php ${vBs}/bin-php72-cli
      fi
      if [ -e "/opt/php71/bin/php" ]; then
        mv -f /opt/php71/bin/php ${vBs}/bin-php71-cli
      fi
      if [ -e "/opt/php70/bin/php" ]; then
        mv -f /opt/php70/bin/php ${vBs}/bin-php70-cli
      fi
      if [ -e "/etc/init.d/php73-fpm" ]; then
        update-rc.d -f php73-fpm remove &> /dev/null
        mv -f /etc/init.d/php73-fpm ${vBs}/initd-php73-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php72-fpm" ]; then
        update-rc.d -f php72-fpm remove &> /dev/null
        mv -f /etc/init.d/php72-fpm ${vBs}/initd-php72-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php71-fpm" ]; then
        update-rc.d -f php71-fpm remove &> /dev/null
        mv -f /etc/init.d/php71-fpm ${vBs}/initd-php71-fpm
        _FPM_INITD_CLEANUP=YES
      fi
      if [ -e "/etc/init.d/php70-fpm" ]; then
        update-rc.d -f php70-fpm remove &> /dev/null
        mv -f /etc/init.d/php70-fpm ${vBs}/initd-php70-fpm
        _FPM_INITD_CLEANUP=YES
      fi
    fi
    if [ "$_FPM_INITD_CLEANUP" = "YES" ]; then
      killall php-fpm &> /dev/null
    fi
    rm -f /opt/local/bin/php
  fi
}

#
# Re-set default PHP-CLI.
re_set_default_php_cli() {
  if [ "${_PHP_CLI_VERSION}" = "7.3" ]; then
    switch_php_cli "73"
  elif [ "${_PHP_CLI_VERSION}" = "7.2" ]; then
    switch_php_cli "72"
  elif [ "${_PHP_CLI_VERSION}" = "7.1" ]; then
    switch_php_cli "71"
  elif [ "${_PHP_CLI_VERSION}" = "7.0" ]; then
    switch_php_cli "70"
  elif [ "${_PHP_CLI_VERSION}" = "5.6" ]; then
    switch_php_cli "56"
  fi
}

#
# Fix path to PHP-CLI if needed.
check_php_cli() {
  if [ "${_PHP_CLI_VERSION}" = "7.3" ]; then
    _PHP_CLI_PATH="/opt/php73/bin/php"
  elif [ "${_PHP_CLI_VERSION}" = "7.2" ]; then
    _PHP_CLI_PATH="/opt/php72/bin/php"
  elif [ "${_PHP_CLI_VERSION}" = "7.1" ]; then
    _PHP_CLI_PATH="/opt/php71/bin/php"
  elif [ "${_PHP_CLI_VERSION}" = "7.0" ]; then
    _PHP_CLI_PATH="/opt/php70/bin/php"
  elif [ "${_PHP_CLI_VERSION}" = "5.6" ]; then
    _PHP_CLI_PATH="/opt/php56/bin/php"
  else
    _PHP_CLI_PATH=""
  fi
  if [ -x "$_PHP_CLI_PATH" ]; then
    _USE_PHP_CLI_PATH=$_PHP_CLI_PATH
  else
    if  [ -x "/opt/php72/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php72/bin/php"
    elif  [ -x "/opt/php73/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php73/bin/php"
    elif  [ -x "/opt/php71/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php71/bin/php"
    elif  [ -x "/opt/php70/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php70/bin/php"
    elif [ -x "/opt/php56/bin/php" ]; then
      _USE_PHP_CLI_PATH="/opt/php56/bin/php"
    fi
  fi
  if [ -x "${_USE_PHP_CLI_PATH}" ]; then
    rm -f /usr/bin/php
    rm -f /usr/bin/php-cli
    ln -sf ${_USE_PHP_CLI_PATH} /usr/bin/php
    ln -sf ${_USE_PHP_CLI_PATH} /usr/bin/php-cli
  else
    msg "WAIT: I can not find PHP-CLI anywhere!"
  fi
}

switch_php_cli() {
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
  if [ -x "/opt/php56/bin/php" ] \
    && [ -z "$_FRESH_PHP56_BUILD" ]; then
    _PHP_VERSION="${_PHP56_VRN}"
    _PHP_BIN_BROKEN=NO
    _BROKEN_LIBCURL_TEST=""
    switch_php_cli "56"
    check_php_broken "56"
    check_php_rebuild "56"
    update_php_multi "56"
    mrun "service php56-fpm restart" &> /dev/null
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
  fi
  if [ -x "/opt/php70/bin/php" ] \
    && [ -z "$_FRESH_PHP70_BUILD" ]; then
    _PHP_VERSION="${_PHP70_VRN}"
    _PHP_BIN_BROKEN=NO
    _BROKEN_LIBCURL_TEST=""
    switch_php_cli "70"
    check_php_broken "70"
    check_php_rebuild "70"
    update_php_multi "70"
    mrun "service php70-fpm restart" &> /dev/null
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
  fi
  if [ -x "/opt/php71/bin/php" ] \
    && [ -z "$_FRESH_PHP71_BUILD" ]; then
    _PHP_VERSION="${_PHP71_VRN}"
    _PHP_BIN_BROKEN=NO
    _BROKEN_LIBCURL_TEST=""
    switch_php_cli "71"
    check_php_broken "71"
    check_php_rebuild "71"
    update_php_multi "71"
    mrun "service php71-fpm restart" &> /dev/null
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
  fi
  if [ -x "/opt/php72/bin/php" ] \
    && [ -z "$_FRESH_PHP72_BUILD" ]; then
    _PHP_VERSION="${_PHP72_VRN}"
    _PHP_BIN_BROKEN=NO
    _BROKEN_LIBCURL_TEST=""
    switch_php_cli "72"
    check_php_broken "72"
    check_php_rebuild "72"
    update_php_multi "72"
    mrun "service php72-fpm restart" &> /dev/null
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
  fi
  if [ -x "/opt/php73/bin/php" ] \
    && [ -z "$_FRESH_PHP73_BUILD" ]; then
    _PHP_VERSION="${_PHP73_VRN}"
    _PHP_BIN_BROKEN=NO
    _BROKEN_LIBCURL_TEST=""
    switch_php_cli "73"
    check_php_broken "73"
    check_php_rebuild "73"
    update_php_multi "73"
    mrun "service php73-fpm restart" &> /dev/null
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
  fi
}

get_php_conf_extra() {
  _PHP_EXTRA=""
  if [ "${_OSV}" = "jessie" ] \
    || [ "${_OSV}" = "stretch" ] \
    || [ "${_DO_FIX}" = "YES" ] \
    || [ "${_OSV}" = "trusty" ] \
    || [ "${_OSV}" = "precise" ]; then
    _PHP_EXTRA="--with-ldap --with-gmp --with-xpm-dir=/usr"
  else
    _PHP_EXTRA="--with-ldap --with-gmp"
  fi
  if [ ! -z "${_PHP_EXTRA_CONF}" ]; then
    _PHP_EXTRA="${_PHP_EXTRA} ${_PHP_EXTRA_CONF}"
  fi
  if [ ! -z "${_PHP_EXTRA}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: THIS PHP EXTRA is ${_PHP_EXTRA}"
    fi
  fi
}

install_update_php() {
  if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
    && [ "${_LOC_OSV}" = "jessie" ]; then
    _DO_FIX=YES
  fi
  # if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
  #   && [ "${_LOC_OSV}" = "jessie" ]; then
  #   mrun "service nginx stop" &> /dev/null
  #   killall -9 nginx &> /dev/null
  # fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Checking if PHP upgrade is available"
    fi
    st_runner "aptitude remove php5-sasl php5-suhosin -y" &> /dev/null
    st_runner "apt-get purge php5-sasl php5-suhosin -y" &> /dev/null
  fi
  if [ "${_OSV}" = "stretch" ] \
    || [ "${_OSV}" = "jessie" ] \
    || [ "${_OSV}" = "trusty" ]; then
    ln -sf /usr/include/freetype2 /usr/include/freetype2/freetype
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "5.6" ]] \
    && [ ! -x "/opt/php56/bin/php" ]; then
    _PHP_VERSION="${_PHP56_VRN}"
    msg "INFO: PHP ${_PHP_VERSION} will be installed now"
    get_php_conf_extra
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
    get_php_conf_extra
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
    get_php_conf_extra
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
    get_php_conf_extra
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
    get_php_conf_extra
    install_php_multi "73"
    switch_php_cli "73"
    _PHP_VERSION=""
    _T_PHP_VRN=""
    _T_PHP_PTH=""
    _FRESH_PHP73_BUILD=73
  fi
}

check_fix_php() {
  check_php_cli
  if [ -x "/opt/php56/bin/php" ]; then
    _CURLWRAPPERS_TEST=$(/opt/php56/bin/php -i | grep "with-curlwrappers" 2>&1)
    if [[ "$_CURLWRAPPERS_TEST" =~ "with-curlwrappers" ]]; then
      _CURLWRAPPERS_REBUILD=YES
    fi
  fi
  if [ "$_CURLWRAPPERS_REBUILD" = "YES" ] \
    && [[ ! "${_PHP_EXTRA_CONF}" =~ "with-curlwrappers" ]]; then
    msg "INFO: PHP rebuild required to remove --with-curlwrappers option..."
    _PHP_FORCE_REINSTALL=YES
    php_upgrade_all
  fi
  if [[ "${_PHP_EXTRA_CONF}" =~ "--with-tidy" ]] \
    && [ ! -e "${pthLog}/libtidy-${_LIB_TIDY_VRN}.log" ]; then
    if [ -e "/usr/lib/libtidy.so" ]; then
      mrun "apt-get remove libtidy-dev -y -qq" &> /dev/null
      mrun "apt-get remove libtidy-0.99-0 -y -qq" &> /dev/null
      mrun "apt-get remove tidy -y -qq" &> /dev/null
    fi
    cd /var/opt
    rm -rf tidy*
    mrun "${_INSTALL} cmake" 2> /dev/null
    get_dev_src "tidy-html5-${_LIB_TIDY_VRN}.tar.gz"
    cd tidy-html5-${_LIB_TIDY_VRN}/build/cmake
    mrun "cmake ../.. -DCMAKE_INSTALL_PREFIX=/usr/" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    if [ -e "/usr/lib/libtidy.so" ]; then
      cd /usr/lib
      ln -sf libtidy.so.${_LIB_TIDY_VRN} libtidy-0.99.so.0
      touch ${pthLog}/libtidy-${_LIB_TIDY_VRN}.log
    fi
    _PHP_FORCE_REINSTALL=YES
    php_upgrade_all
  fi
  _BROKEN_LIBCURL_TEST=$(php -v 2>&1)
  if [[ "$_BROKEN_LIBCURL_TEST" =~ "libcurl.so.4" ]]; then
    msg "INFO: PHP rebuild required to fix broken libcurl..."
    install_curl_src
    php_upgrade_all
  fi
  install_newrelic
  if [ "${_PHP_IONCUBE}" = "YES" ]; then
    if [ ! -e "${pthLog}/ioncube-${_IONCUBE_VRN}.log" ] \
      || [ "${_PHP_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      install_ioncube
    fi
  fi
}

install_update_composer() {
  if [ -x "/usr/local/bin/composer" ]; then
    /usr/local/bin/composer self-update &> /dev/null
  fi
  if [ ! -x "/usr/local/bin/composer" ] || [ ! -L "/usr/bin/composer" ]; then
    rm -f /usr/local/bin/composer
    rm -f /usr/bin/composer
    rm -rf /root/.composer
    mkdir -p /var/opt
    cd /var/opt
    curl -sS https://getcomposer.org/installer | php &> /dev/null
    mv composer.phar /usr/local/bin/composer
    ln -sf /usr/local/bin/composer /usr/bin/composer
  fi
}
