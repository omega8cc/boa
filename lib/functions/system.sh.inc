#
# Set xterm.
set_xterm() {
  if [ -e "/root/.bashrc" ]; then
    _XTERM_TEST=$(grep ${_X_VERSION} /root/.bashrc 2>&1)
    if [[ "$_XTERM_TEST" =~ "${_X_VERSION}" ]]; then
      sed -i "s/^export TERM=.*/export TERM=xterm-color/g" /root/.bashrc
    fi
  fi
}

#
# Kill nash-hotplug.
kill_nash() {
  _L_VM_TEST=$(uname -a 2>&1)
  if [[ "${_L_VM_TEST}" =~ beng ]]; then
    _DO_NOTHING=YES
  else
    _NASH_TEST=$(grep nash-hotplug /etc/rc.local 2>&1)
    if [[ "$_NASH_TEST" =~ "nash-hotplug" ]]; then
      _DO_NOTHING=YES
    else
      cp -af /etc/rc.local /etc/rc.local.bak.${_NOW}
      sed -i "s/exit 0//g" /etc/rc.local &> /dev/null
      echo "killall -9 nash-hotplug" >> /etc/rc.local
      echo "exit 0" >> /etc/rc.local
      killall -9 nash-hotplug &> /dev/null
    fi
  fi
}

#
# Fix FTPS PAM where required.
fix_ftps_pam() {
  if [ ! -e "/etc/ftpusers" ]; then
    cp -af ${locCnf}/ftpusers /etc/ftpusers
  fi
  if [ "${_OSV}" = "lenny" ]; then
    _DO_NOTHING=YES
  else
    sed -i "s/pam_stack.so/pam_unix.so/g" /etc/pam.d/pure-ftpd &> /dev/null
    sed -i "s/ service=system-auth//g"    /etc/pam.d/pure-ftpd &> /dev/null
  fi
}

#
# Fix FTPS and SFTP access on modern systems.
fix_sftp_ftps_modern() {
  if [ "${_OSV}" != "lenny" ]; then
    _LSHELL_PATH_TEST=$(grep "/usr/bin/lshell" /etc/shells 2>&1)
    if [[ "$_LSHELL_PATH_TEST" =~ "/usr/bin/lshell" ]]; then
      _DO_NOTHING=YES
    else
      echo "/usr/bin/lshell" >> /etc/shells
    fi
  fi
  if [ ! -e "${pthLog}/mss-build-${_MSS_VRN}-${_X_VERSION}.log" ] \
    || [ ! -e "/etc/ssh/sftp_config" ] \
    || [ ! -e "/usr/bin/MySecureShell" ] \
    || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Installing MySecureShell ${_MSS_VRN}..."
    cd /var/opt
    rm -f -r mysecureshell*
    get_dev_src "mysecureshell-${_MSS_VRN}.tar.gz"
    cd /var/opt/mysecureshell-${_MSS_VRN}
    st_runner "sh ./configure" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "sh ./install.sh yesall" 2> /dev/null
    touch ${pthLog}/mss-build-${_MSS_VRN}-${_X_VERSION}.log
    cp -af ${locCnf}/sftp_config /etc/ssh/sftp_config
    mrun "service ssh restart" &> /dev/null
  fi
  if [ -e "/usr/bin/MySecureShell" ] && [ -e "/etc/ssh/sftp_config" ]; then
    _MSS_TEST=$(grep "lshell" /etc/passwd 2>&1)
    if [[ "$_MSS_TEST" =~ "lshell" ]]; then
      sed -i "s/usr\/.*\/lshell/usr\/bin\/MySecureShell/g" /etc/passwd &> /dev/null
    fi
  fi
  _MSS_PATH_TEST=$(grep "/usr/bin/MySecureShell" /etc/shells 2>&1)
  if [[ "$_MSS_PATH_TEST" =~ "/usr/bin/MySecureShell" ]]; then
    _DO_NOTHING=YES
  else
    echo "/usr/bin/MySecureShell" >> /etc/shells
  fi
  if [ ! -e "${pthLog}/fixed-sftp-idle.log" ]; then
    sed -i "s/IdleTimeOut.*/IdleTimeOut            15m/g" /etc/ssh/sftp_config &> /dev/null
    mrun "service ssh reload" &> /dev/null
    touch ${pthLog}/fixed-sftp-idle.log
  fi
}

#
# Disable Old Purge Cruft Machine.
disable_old_purge_cruft_machine() {
  if [[ "${_THISHOST}" =~ ".host8." ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
    || [ -e "/root/.host8.cnf" ]; then
    sed -i "s/.*purge_cruft.*//g" /etc/crontab &> /dev/null
    sed -i "/^$/d" /etc/crontab &> /dev/null
  fi
}

#
# Enable Weekly Usage Monitor (Monday).
enable_weekly_usage_monitor() {
  if [[ "${_THISHOST}" =~ ".host8." ]] \
    || [ "${_VMFAMILY}" = "VS" ]; then
    sed -i "s/.*weekly.sh.*//g" /etc/crontab &> /dev/null
    sed -i "/^$/d" /etc/crontab &> /dev/null
    echo "28 6    * * 7   root    bash /var/xdrago/weekly.sh >/dev/null 2>&1" >> /etc/crontab
  fi
}

#
# Update INI templates.
update_ini_tpl() {
  mkdir -p /data/conf
  if [ -e "${locCnf}/default.boa_platform_control.ini" ]; then
    cp -af ${locCnf}/default.boa_platform_control.ini /data/conf/default.boa_platform_control.ini
    rm -f /var/xdrago/conf/default.boa_platform_control.ini
  fi
  if [ -e "${locCnf}/default.boa_site_control.ini" ]; then
    cp -af ${locCnf}/default.boa_site_control.ini /data/conf/default.boa_site_control.ini
    rm -f /var/xdrago/conf/default.boa_site_control.ini
  fi
}

#
# Update global.inc Config.
update_global_inc_conf() {
  if [ -e "/data/conf/global.inc" ]; then
    mv -f /data/conf/global.inc /data/conf/global.inc-pre-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${locCnf}/global.inc /data/conf/global.inc
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" /data/conf/global.inc &> /dev/null
  fi
}

#
# Fix this on upgrade.
fix_on_upgrade() {
  sed -i "s/loglevel.*/loglevel warning/g" /etc/redis/redis.conf &> /dev/null
  sed -i "s/^TLS.*/TLS 2/g" /usr/local/etc/pure-ftpd.conf &> /dev/null
  cp -af ${locCnf}/clean-boa-env /etc/init.d/clean-boa-env
  chmod 755 /etc/init.d/clean-boa-env &> /dev/null
  st_runner "update-rc.d clean-boa-env defaults" &> /dev/null
  kill_nash
  fix_sftp_ftps_modern
  fix_ftps_pam
  disable_old_purge_cruft_machine
  enable_weekly_usage_monitor
  update_php_conf
  update_ini_tpl
  update_sql_conf
  update_nginx_conf
  update_global_inc_conf
  update_redis_password
}

#
# Tune memory limits for PHP, Nginx and MariaDB.
tune_memory_limits() {
  _ETH_TEST=$(ifconfig 2>&1)
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_ETH_TEST}" =~ "venet0" ]]; then
    _VMFAMILY="VZ"
  elif [ -e "/proc/bean_counters" ]; then
    _VMFAMILY="VZ"
  elif [[ "${_THISHOST}" =~ ".host8." ]] && [ -e "/boot/grub/menu.lst" ]; then
    _VMFAMILY="TG"
  elif [[ "${_THISHOST}" =~ ".host8." ]] && [ -e "/boot/grub/grub.cfg" ]; then
    _VMFAMILY="TG"
  else
    _VMFAMILY="XEN"
  fi
  if [[ "${_VM_TEST}" =~ beng ]]; then
    _VMFAMILY="VS"
  fi
  if [[ "${_AWS_TEST_A}" =~ "cloudimg" ]] \
    || [[ "${_AWS_TEST_B}" =~ "cloudconfig" ]]; then
    _VMFAMILY="AWS"
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
  if [ ! -z "${_CPU_NR}" ] && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] && [ "${_CPU_INFO}" -gt "0" ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
  _CPU_MX=$(( _CPU_NR * 2 ))
  if [ "$_CPU_MX" -lt "4" ]; then
    _CPU_MX=4
  fi
  _CPU_TG=$(( _CPU_NR / 2 ))
  if [ "$_CPU_TG" -lt "4" ]; then
    _CPU_TG=4
  fi
  _CPU_VS=$(( _CPU_NR / 12 ))
  if [ "${_CPU_VS}" -lt "2" ]; then
    _CPU_VS=2
  fi
  _RAM=$(free -mto | grep Mem: | awk '{ print $2 }' 2>&1)
  if [ "${_RESERVED_RAM}" -gt "0" ]; then
    _RAM=$(( _RAM - _RESERVED_RAM ))
  fi
  _USE=$(( _RAM / 4 ))
  if [ "${_VMFAMILY}" = "VS" ] || [[ "${_THISHOST}" =~ ".host8." ]]; then
    if [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.tg.cnf" ]; then
        _USE_SQL=$(( _RAM / 8 ))
      else
        _USE_SQL=$(( _RAM / 18 ))
      fi
    else
      _USE_SQL=$(( _RAM / 8 ))
    fi
  else
    _USE_SQL=$(( _RAM / 8 ))
  fi
  if [ "${_USE_SQL}" -lt "256" ]; then
    _USE_SQL=256
  fi
  _TMP_SQL="${_USE_SQL}M"
  _SRT_SQL=$(( _USE_SQL * 2 ))
  _SRT_SQL="${_SRT_SQL}K"
  if [ "${_USE}" -ge "512" ] && [ "${_USE}" -lt "1024" ]; then
    _USE_PHP=512
    _USE_OPC=512
    _MXC_SQL=20
    _QCE_SQL=128M
    _RND_SQL=8M
    _JBF_SQL=4M
    if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
      _L_PHP_FPM_WORKERS=12
    else
      _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
    fi
    if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
      _L_NGX_WRKS=$_CPU_MX
    else
      _L_NGX_WRKS=${_NGINX_WORKERS}
    fi
  elif [ "${_USE}" -ge "1024" ]; then
    if [ "${_VMFAMILY}" = "XEN" ] || [ "${_VMFAMILY}" = "AWS" ]; then
      _USE_PHP=512
      _USE_OPC=1024
      _MXC_SQL=30
      _QCE_SQL=128M
      _RND_SQL=8M
      _JBF_SQL=4M
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _L_PHP_FPM_WORKERS=24
      else
        _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
      fi
      if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
        _L_NGX_WRKS=$_CPU_MX
      else
        _L_NGX_WRKS=${_NGINX_WORKERS}
      fi
    elif [ "${_VMFAMILY}" = "VS" ] || [ "${_VMFAMILY}" = "TG" ]; then
      if [ -e "/boot/grub/grub.cfg" ] \
        || [ -e "/boot/grub/menu.lst" ] \
        || [ -e "/root/.tg.cnf" ]; then
        _USE_PHP=1024
        _USE_OPC=1024
        _MXC_SQL=100
        _QCE_SQL=256M
        _RND_SQL=8M
        _JBF_SQL=4M
        if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
          _L_PHP_FPM_WORKERS=24
        else
          _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
        fi
        if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
          _L_NGX_WRKS=$_CPU_TG
        else
          _L_NGX_WRKS=${_NGINX_WORKERS}
        fi
        sed -i "s/64000/128000/g"  /opt/php56/etc/php56.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php55/etc/php55.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php54/etc/php54.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php53/etc/php53.ini &> /dev/null
      else
        _USE_PHP=1024
        _USE_OPC=1024
        _MXC_SQL=30
        _QCE_SQL=64M
        _RND_SQL=2M
        _JBF_SQL=2M
        if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
          _L_PHP_FPM_WORKERS=6
        else
          _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
        fi
        if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
          _L_NGX_WRKS=${_CPU_VS}
        else
          _L_NGX_WRKS=${_NGINX_WORKERS}
        fi
      fi
    else
      _USE_PHP=256
      _USE_OPC=256
      _MXC_SQL=10
      _QCE_SQL=32M
      _RND_SQL=2M
      _JBF_SQL=2M
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _L_PHP_FPM_WORKERS=12
      else
        _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
      fi
      if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
        _L_NGX_WRKS=$_CPU_MX
      else
        _L_NGX_WRKS=${_NGINX_WORKERS}
      fi
    fi
  else
    _USE_PHP="${_USE}"
    _USE_OPC="${_USE}"
    _MXC_SQL=10
    _QCE_SQL=32M
    _RND_SQL=1M
    _JBF_SQL=1M
    if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
      _L_PHP_FPM_WORKERS=6
    else
      _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
    fi
    if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
      _L_NGX_WRKS=$_CPU_MX
    else
      _L_NGX_WRKS=${_NGINX_WORKERS}
    fi
  fi
  _USE_JETTY="-Xmx${_USE_OPC}m"
  if [ "${_VMFAMILY}" = "VZ" ]; then
    _USE_OPC=64
  fi
  _USE_FPM=$(( _USE_PHP / 2 ))
  if [ "${_USE_FPM}" -lt "196" ]; then
    _USE_FPM=196
  fi
  if [ "${_USE_PHP}" -lt "196" ]; then
    _USE_PHP=196
  fi
  if [ ! -e "/var/xdrago/conf/fpm-pool-foo.conf" ]; then
    mkdir -p /var/xdrago/conf
  fi
  if [ ! -e "/data/conf" ]; then
    mkdir -p /data/conf
  fi
  cp -af ${locCnf}/fpm-pool-foo.conf /var/xdrago/conf/fpm-pool-foo.conf
  cp -af ${locCnf}/hhvm /var/xdrago/conf/
  cp -af ${locCnf}/hhvm/hhvm_intercept.php /data/conf/hhvm_intercept.php
  chmod 644 /data/conf/hhvm_intercept.php
  if [ -e "/opt/etc/fpm/fpm-pool-common.conf" ]; then
    sed -i "s/256/${_USE_FPM}/g" /opt/etc/fpm/fpm-pool-common.conf &> /dev/null
  fi
  if [ -e "/opt/php56/etc/php56.ini" ]; then
    sed -i "s/256/${_USE_FPM}/g" /opt/php56/etc/php56.ini &> /dev/null
    sed -i "s/181/${_USE_OPC}/g" /opt/php56/etc/php56.ini &> /dev/null
    sed -i "s/256/${_USE_PHP}/g" /opt/php56/lib/php.ini   &> /dev/null
  fi
  if [ -e "/opt/php55/etc/php55.ini" ]; then
    sed -i "s/256/${_USE_FPM}/g" /opt/php55/etc/php55.ini &> /dev/null
    sed -i "s/181/${_USE_OPC}/g" /opt/php55/etc/php55.ini &> /dev/null
    sed -i "s/256/${_USE_PHP}/g" /opt/php55/lib/php.ini   &> /dev/null
  fi
  if [ -e "/opt/php54/etc/php54.ini" ]; then
    sed -i "s/256/${_USE_FPM}/g" /opt/php54/etc/php54.ini &> /dev/null
    sed -i "s/181/${_USE_OPC}/g" /opt/php54/etc/php54.ini &> /dev/null
    sed -i "s/256/${_USE_PHP}/g" /opt/php54/lib/php.ini   &> /dev/null
  fi
  if [ -e "/opt/php53/etc/php53.ini" ]; then
    sed -i "s/256/${_USE_FPM}/g" /opt/php53/etc/php53.ini &> /dev/null
    sed -i "s/181/${_USE_OPC}/g" /opt/php53/etc/php53.ini &> /dev/null
    sed -i "s/256/${_USE_PHP}/g" /opt/php53/lib/php.ini   &> /dev/null
  fi
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ]; then
    tune_sql_memory_limits
    _UXC_SQL=${_MXC_SQL}
    _UXC_SQL=$(( _MXC_SQL / 2 ))
    sed -i "s/= 191/= ${_UXC_SQL}/g"                                              /etc/mysql/my.cnf
    sed -i "s/= 292/= ${_MXC_SQL}/g"                                              /etc/mysql/my.cnf
    sed -i "s/^tmp_table_size.*/tmp_table_size          = ${_TMP_SQL}/g"          /etc/mysql/my.cnf
    sed -i "s/^max_heap_table_size.*/max_heap_table_size     = ${_TMP_SQL}/g"     /etc/mysql/my.cnf
    sed -i "s/^myisam_sort_buffer_size.*/myisam_sort_buffer_size = ${_SRT_SQL}/g" /etc/mysql/my.cnf
    sed -i "s/^query_cache_size.*/query_cache_size        = ${_QCE_SQL}/g"        /etc/mysql/my.cnf
    sed -i "s/^read_rnd_buffer_size.*/read_rnd_buffer_size    = ${_RND_SQL}/g"    /etc/mysql/my.cnf
    sed -i "s/^join_buffer_size.*/join_buffer_size        = ${_JBF_SQL}/g"        /etc/mysql/my.cnf
  fi
  _MAX_MEM_REDIS="${_USE_OPC}MB"
  sed -i "s/^maxmemory .*/maxmemory ${_MAX_MEM_REDIS}/g" \
    /etc/redis/redis.conf &> /dev/null
  if [ -e "/etc/default/jetty9" ] && [ -e "/opt/solr4" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms8m ${_USE_JETTY} \
      -Djava.awt.headless=true \
      -Dsolr.solr.home=\/opt\/solr4 \$JAVA_OPTIONS\" \
      # Options/g" /etc/default/jetty9
  fi
  if [ -e "/etc/default/jetty8" ] && [ -e "/opt/solr3" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms8m ${_USE_JETTY} \
      -Djava.awt.headless=true \
      -Dsolr.solr.home=\/opt\/solr3 \$JAVA_OPTIONS\" \
      # Options/g" /etc/default/jetty8
  fi
  if [ -e "/etc/default/jetty7" ] && [ -e "/opt/solr1" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms8m ${_USE_JETTY} \
      -Djava.awt.headless=true \
      -Dsolr.solr.home=\/opt\/solr1 \$JAVA_OPTIONS\" \
      # Options/g" /etc/default/jetty7
  fi
  tune_web_server_config
}

#
# Fix locales.
fix_locales() {
  if [ -e "/etc/ssh/sshd_config" ]; then
    _SSH_LC_TEST=$(grep "^AcceptEnv LANG LC_" /etc/ssh/sshd_config 2>&1)
    if [[ "$_SSH_LC_TEST" =~ "AcceptEnv LANG LC_" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/.*AcceptEnv.*//g" /etc/ssh/sshd_config
      echo "AcceptEnv LANG LC_*" >> /etc/ssh/sshd_config
    fi
  fi
  if [ -e "/usr/etc/sshd_config" ]; then
    _SSH_LC_TEST=$(grep "^AcceptEnv LANG LC_" /usr/etc/sshd_config 2>&1)
    if [[ "$_SSH_LC_TEST" =~ "AcceptEnv LANG LC_" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/.*AcceptEnv.*//g" /usr/etc/sshd_config
      echo "AcceptEnv LANG LC_*" >> /usr/etc/sshd_config
    fi
  fi
  _LOCALE_TEST=BROKEN
  _LOC_TEST=$(locale 2>&1)
  if [[ "$_LOC_TEST" =~ LANGUAGE=.*UTF-8 ]] \
    && [[ "$_LOC_TEST" =~ LANG=.*UTF-8 ]]; then
    _LOCALE_TEST=OK
  fi
  if [[ "$_LOC_TEST" =~ "Cannot" ]]; then
    _LOCALE_TEST=BROKEN
  fi
  if [ "$_LOCALE_TEST" = "BROKEN" ]; then
    msg "WARNING!"
    cat <<EOF

  Locales on this system are broken or not installed
  and/or not configured correctly yet. This is a known
  issue on some systems/hosts which either don't configure
  locales at all or don't use UTF-8 compatible locales
  during initial OS setup.

  We will fix this problem for you now by enforcing en_US.UTF-8
  locale settings on the fly during install, and as system
  defaults in /etc/default/locale for future sessions. This
  overrides any locale settings passed by your SSH client.

  You should log out when this installer will finish all its tasks
  and display last line with "BYE!" and then log in again
  to see the result.

  We will continue in 5 seconds...

EOF
    sleep 5
    if [ "${_THIS_OS}" = "Debian" ]; then
      _LOCALE_GEN_TEST=$(grep -v "^#" /etc/locale.gen 2>&1)
      if [[ ! "$_LOCALE_GEN_TEST" =~ "en_US.UTF-8 UTF-8" ]]; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
      fi
      sed -i "/^$/d" /etc/locale.gen
      locale-gen &> /dev/null
    else
      locale-gen en_US.UTF-8 &> /dev/null # Ubuntu-specific locale-gen
    fi
    # Explicitly enforce all locale settings
    update-locale \
      LANG=en_US.UTF-8 \
      LC_CTYPE=en_US.UTF-8 \
      LC_COLLATE=POSIX \
      LC_NUMERIC=POSIX \
      LC_TIME=en_US.UTF-8 \
      LC_MONETARY=en_US.UTF-8 \
      LC_MESSAGES=en_US.UTF-8 \
      LC_PAPER=en_US.UTF-8 \
      LC_NAME=en_US.UTF-8 \
      LC_ADDRESS=en_US.UTF-8 \
      LC_TELEPHONE=en_US.UTF-8 \
      LC_MEASUREMENT=en_US.UTF-8 \
      LC_IDENTIFICATION=en_US.UTF-8 \
      LC_ALL= &> /dev/null
    if [ -e "${locCnf}/boa.bashrc.txt" ]; then
      cp -af /root/.bashrc /root/.bashrc.bak.${_NOW}
      cp -af ${locCnf}/boa.bashrc.txt /root/.bashrc
      set_xterm
    fi
    # Define all locale settings on the fly to prevent unnecessary
    # warnings during installation of packages.
    export LANG=en_US.UTF-8
    export LC_CTYPE=en_US.UTF-8
    export LC_COLLATE=POSIX
    export LC_NUMERIC=POSIX
    export LC_TIME=en_US.UTF-8
    export LC_MONETARY=en_US.UTF-8
    export LC_MESSAGES=en_US.UTF-8
    export LC_PAPER=en_US.UTF-8
    export LC_NAME=en_US.UTF-8
    export LC_ADDRESS=en_US.UTF-8
    export LC_TELEPHONE=en_US.UTF-8
    export LC_MEASUREMENT=en_US.UTF-8
    export LC_IDENTIFICATION=en_US.UTF-8
    export LC_ALL=
  else
    if [ -e "${locCnf}/boa.bashrc.txt" ]; then
      cp -af /root/.bashrc /root/.bashrc.bak.${_NOW}
      cp -af ${locCnf}/boa.bashrc.txt /root/.bashrc
      set_xterm
    fi
    if [ "${_THIS_OS}" = "Debian" ]; then
      _LOCALE_GEN_TEST=$(grep -v "^#" /etc/locale.gen 2>&1)
      if [[ ! "$_LOCALE_GEN_TEST" =~ "en_US.UTF-8 UTF-8" ]]; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
      fi
      sed -i "/^$/d" /etc/locale.gen
      locale-gen &> /dev/null
    else
      locale-gen en_US.UTF-8 &> /dev/null # Ubuntu-specific locale-gen
    fi
    # Explicitly enforce locale settings required for consistency
    update-locale \
      LANG=en_US.UTF-8 \
      LC_CTYPE=en_US.UTF-8 \
      LC_COLLATE=POSIX \
      LC_NUMERIC=POSIX \
      LC_ALL= &> /dev/null
    # Define locale settings required for consistency also on the fly
    if [ "${_STATUS}" != "INIT" ]; then
      # On initial install it causes warning on Wheezy:
      # setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8):
      # No such file or directory
      export LC_CTYPE=en_US.UTF-8
    fi
    export LC_COLLATE=POSIX
    export LC_NUMERIC=POSIX
    export LC_ALL=
  fi
}

#
# Read or create Barracuda cnf file.
barracuda_cnf() {
  if [ ! -e "${barCnf}" ]; then
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      _CHECK_HOST=$(uname -n 2>&1)
      if [ -e "/root/.auto.up.cnf" ] \
        || [ -e "/root/.host8.cnf" ] \
        || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        || [ "${_VMFAMILY}" = "VS" ]; then
        if [ -e "/root/.debug.cnf" ]; then
          _DO_NOTHING=YES
        else
          _DB_SERVER=MariaDB
        fi
      else
        msg "EXIT: Invalid e-mail address defined in the _MY_EMAIL variable"
        msg "EXIT: Bye (1)"
        clean_pid_exit
      fi
    fi
    if [ "${_DB_SERIES}" = "10.0" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _MARIADB_VRN="${_GALERA_10_VRN}"
      else
        _MARIADB_VRN="${_MARIADB_10_VRN}"
      fi
    else
      _DB_SERIES=5.5
      _MARIADB_VRN="${_MARIADB_5_VRN}"
    fi
    msg "INFO: Creating your ${barCnf} config file"
    sleep 1
    echo "###"                                                 > ${barCnf}
    echo "### Configuration created on ${_NOW}"               >> ${barCnf}
    echo "###"                                                >> ${barCnf}
    echo "_LOCAL_NETWORK_HN=\"${_LOCAL_NETWORK_HN}\""         >> ${barCnf}
    echo "_LOCAL_NETWORK_IP=\"${_LOCAL_NETWORK_IP}\""         >> ${barCnf}
    echo "_MY_FRONT=\"${_MY_FRONT}\""                         >> ${barCnf}
    echo "_MY_HOSTN=\"${_MY_HOSTN}\""                         >> ${barCnf}
    echo "_MY_OWNIP=\"${_MY_OWNIP}\""                         >> ${barCnf}
    echo "_SMTP_RELAY_HOST=\"${_SMTP_RELAY_HOST}\""           >> ${barCnf}
    echo "_SMTP_RELAY_TEST=${_SMTP_RELAY_TEST}"               >> ${barCnf}
    echo "_THIS_DB_HOST=${_THIS_DB_HOST}"                     >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_AUTOPILOT=${_AUTOPILOT}"                           >> ${barCnf}
    echo "_DEBUG_MODE=${_DEBUG_MODE}"                         >> ${barCnf}
    echo "_MY_EMAIL=\"${_MY_EMAIL}\""                         >> ${barCnf}
    echo "_XTRAS_LIST=\"${_XTRAS_LIST}\""                     >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_MODULES_FIX=${_MODULES_FIX}"                       >> ${barCnf}
    echo "_MODULES_SKIP=\"${_MODULES_SKIP}\""                 >> ${barCnf}
    echo "_PERMISSIONS_FIX=${_PERMISSIONS_FIX}"               >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_CPU_CRIT_RATIO=${_CPU_CRIT_RATIO}"                 >> ${barCnf}
    echo "_CPU_MAX_RATIO=${_CPU_MAX_RATIO}"                   >> ${barCnf}
    echo "_CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO}"             >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_DB_BINARY_LOG=${_DB_BINARY_LOG}"                   >> ${barCnf}
    echo "_DB_ENGINE=${_DB_ENGINE}"                           >> ${barCnf}
    echo "_DB_SERIES=${_DB_SERIES}"                           >> ${barCnf}
    echo "_DB_SERVER=${_DB_SERVER}"                           >> ${barCnf}
    echo "_INNODB_LOG_FILE_SIZE=${_INNODB_LOG_FILE_SIZE}"     >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_DNS_SETUP_TEST=${_DNS_SETUP_TEST}"                 >> ${barCnf}
    echo "_EXTRA_PACKAGES=${_EXTRA_PACKAGES}"                 >> ${barCnf}
    echo "_FORCE_GIT_MIRROR=\"${_FORCE_GIT_MIRROR}\""         >> ${barCnf}
    echo "_LOCAL_DEBIAN_MIRROR=${_LOCAL_DEBIAN_MIRROR}"       >> ${barCnf}
    echo "_LOCAL_UBUNTU_MIRROR=${_LOCAL_UBUNTU_MIRROR}"       >> ${barCnf}
    echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}"                     >> ${barCnf}
    echo "_SCOUT_KEY=${_SCOUT_KEY}"                           >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}"               >> ${barCnf}
    echo "_NGINX_EXTRA_CONF=\"${_NGINX_EXTRA_CONF}\""         >> ${barCnf}
    echo "_NGINX_FORWARD_SECRECY=${_NGINX_FORWARD_SECRECY}"   >> ${barCnf}
    echo "_NGINX_LDAP=${_NGINX_LDAP}"                         >> ${barCnf}
    echo "_NGINX_NAXSI=${_NGINX_NAXSI}"                       >> ${barCnf}
    echo "_NGINX_SPDY=${_NGINX_SPDY}"                         >> ${barCnf}
    echo "_NGINX_WORKERS=${_NGINX_WORKERS}"                   >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}"               >> ${barCnf}
    echo "_PHP_EXTRA_CONF=\"${_PHP_EXTRA_CONF}\""             >> ${barCnf}
    echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\""                 >> ${barCnf}
    echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}"               >> ${barCnf}
    echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}"               >> ${barCnf}
    echo "_PHP_GEOS=${_PHP_GEOS}"                             >> ${barCnf}
    echo "_PHP_MONGODB=${_PHP_MONGODB}"                       >> ${barCnf}
    echo "_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\""       >> ${barCnf}
    echo "_PHP_SINGLE_INSTALL=${_PHP_SINGLE_INSTALL}"         >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_REDIS_LISTEN_MODE=${_REDIS_LISTEN_MODE}"           >> ${barCnf}
    echo "_RESERVED_RAM=${_RESERVED_RAM}"                     >> ${barCnf}
    echo "_SPEED_VALID_MAX=${_SPEED_VALID_MAX}"               >> ${barCnf}
    echo "_SSH_FROM_SOURCES=${_SSH_FROM_SOURCES}"             >> ${barCnf}
    echo "_SSH_PORT=${_SSH_PORT}"                             >> ${barCnf}
    echo "_SSL_FROM_SOURCES=${_SSL_FROM_SOURCES}"             >> ${barCnf}
    echo "_STRICT_BIN_PERMISSIONS=${_STRICT_BIN_PERMISSIONS}" >> ${barCnf}
    echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}"             >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_CUSTOM_CONFIG_CSF=${_CUSTOM_CONFIG_CSF}"           >> ${barCnf}
    echo "_CUSTOM_CONFIG_LSHELL=${_CUSTOM_CONFIG_LSHELL}"     >> ${barCnf}
    echo "_CUSTOM_CONFIG_REDIS=${_CUSTOM_CONFIG_REDIS}"       >> ${barCnf}
    echo "_CUSTOM_CONFIG_SQL=${_CUSTOM_CONFIG_SQL}"           >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_AEGIR_UPGRADE_ONLY=${_AEGIR_UPGRADE_ONLY}"         >> ${barCnf}
    echo "_SYSTEM_UPGRADE_ONLY=${_SYSTEM_UPGRADE_ONLY}"       >> ${barCnf}
    echo "###"                                                >> ${barCnf}
    _CHECK_HOST=$(uname -n 2>&1)
    sed -i "s/^_DB_SERVER=.*/_DB_SERVER=MariaDB/g" ${barCnf}
    if [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.debug.cnf" ]; then
        _DO_NOTHING=YES
      else
        sed -i "s/^_AUTOPILOT=.*/_AUTOPILOT=YES/g"                                 ${barCnf}
        sed -i "s/^_DB_ENGINE=.*/_DB_ENGINE=InnoDB/g"                              ${barCnf}
        sed -i "s/^_DB_SERVER=.*/_DB_SERVER=MariaDB/g"                             ${barCnf}
        sed -i "s/^_DEBUG_MODE=.*/_DEBUG_MODE=NO/g"                                ${barCnf}
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  ${barCnf}
        sed -i "s/^_LOCAL_DEBIAN_MIRROR=.*/_LOCAL_DEBIAN_MIRROR=ftp.debian.org/g"  ${barCnf}
        sed -i "s/^_MY_EMAIL=.*/_MY_EMAIL=\"notify\@omega8.cc\"/g"                 ${barCnf}
        sed -i "s/^_NGINX_FORWARD_SECRECY=.*/_NGINX_FORWARD_SECRECY=YES/g"         ${barCnf}
        sed -i "s/^_NGINX_SPDY=.*/_NGINX_SPDY=YES/g"                               ${barCnf}
        sed -i "s/^_SSH_FROM_SOURCES=.*/_SSH_FROM_SOURCES=YES/g"                   ${barCnf}
        sed -i "s/^_STRICT_BIN_PERMISSIONS=.*/_STRICT_BIN_PERMISSIONS=YES/g"       ${barCnf}
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   ${barCnf}
        sed -i "s/^_DEBUG_MODE=.*/_DEBUG_MODE=NO/g"                                /root/.*.octopus.cnf &> /dev/null
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  /root/.*.octopus.cnf &> /dev/null
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   /root/.*.octopus.cnf &> /dev/null
        if [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ] \
          || [ -e "/root/.test.clstr.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/^_REDIS_LISTEN_MODE=.*/_REDIS_LISTEN_MODE=SOCKET/g"            ${barCnf}
        fi
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] || [ "${_VMFAMILY}" = "VS" ]; then
          if [ "${_VMFAMILY}" = "VS" ]; then
            sed -i "s/^_CPU_CRIT_RATIO=.*/_CPU_CRIT_RATIO=3/g"                     ${barCnf}
            sed -i "s/^_CPU_MAX_RATIO=.*/_CPU_MAX_RATIO=2/g"                       ${barCnf}
            sed -i "s/^_CPU_SPIDER_RATIO=.*/_CPU_SPIDER_RATIO=1/g"                 ${barCnf}
          fi
          sed -i "s/^_SQL_CONVERT=.*/_SQL_CONVERT=NO/g"                            /root/.*.octopus.cnf &> /dev/null
          sed -i "s/^_MODULES_FIX=.*/_MODULES_FIX=YES/g"                           ${barCnf}
          sed -i "s/^_PERMISSIONS_FIX=.*/_PERMISSIONS_FIX=YES/g"                   ${barCnf}
          if [ -x "/opt/php55/bin/php" ] && [ -z "${_PHP_SINGLE_INSTALL}" ]; then
            sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=5.5/g"                 ${barCnf}
            sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=5.5/g"                 ${barCnf}
          fi
        fi
      fi
    fi
    if [ "${_LOCAL_DEBIAN_MIRROR}" = "http.debian.net" ]; then
      _LOCAL_DEBIAN_MIRROR="ftp.debian.org"
      sed -i "s/^_LOCAL_DEBIAN_MIRROR=.*/_LOCAL_DEBIAN_MIRROR=ftp.debian.org/g"    ${barCnf}
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Reading your ${barCnf} config file"
      sleep 1
      msg "NOTE! Please review all config options displayed below"
      msg "NOTE! It will *override* all settings in the Barracuda script"
    fi
    sed -i "s/_SPEED_VALID_MAX=300/_SPEED_VALID_MAX=3600/g" ${barCnf}

    _NGINX_WORKERS_TEST=$(grep _NGINX_WORKERS ${barCnf} 2>&1)
    if [[ "${_NGINX_WORKERS_TEST}" =~ "_NGINX_WORKERS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_NGINX_WORKERS=${_NGINX_WORKERS}" >> ${barCnf}
    fi

    _PHP_FPM_WORKERS_TEST=$(grep _PHP_FPM_WORKERS ${barCnf} 2>&1)
    if [[ "${_PHP_FPM_WORKERS_TEST}" =~ "_PHP_FPM_WORKERS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}" >> ${barCnf}
    fi

    _PHP_CLI_LEGACY_IF_USED_A=$(grep "5\.2" /data/disk/*/log/cli.txt 2>&1)
    _PHP_CLI_LEGACY_IF_USED_B=$(grep "5\.2" /data/disk/*/static/control/cli.info 2>&1)
    _PHP_CLI_LEGACY_IF_USED_C=$(grep "CLI.*5\.2" /root/.*.octopus.cnf 2>&1)
    if [[ "$_PHP_CLI_LEGACY_IF_USED_A" =~ "5.2" ]] \
      || [[ "$_PHP_CLI_LEGACY_IF_USED_B" =~ "5.2" ]] \
      || [[ "$_PHP_CLI_LEGACY_IF_USED_C" =~ "5.2" ]]; then
      if [ -e "/opt/php52/bin/php" ] || [ -e "/etc/init.d/php52-fpm" ]; then
        echo " "
        msg "Legacy PHP-CLI 5.2 is used on this system but will be removed"
      fi
    fi

    _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.2" /data/disk/*/log/fpm.txt 2>&1)
    _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.2" /data/disk/*/static/control/fpm.info 2>&1)
    _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.2" /root/.*.octopus.cnf 2>&1)
    if [[ "$_PHP_FPM_LEGACY_IF_USED_A" =~ "5.2" ]] \
      || [[ "$_PHP_FPM_LEGACY_IF_USED_B" =~ "5.2" ]] \
      || [[ "$_PHP_FPM_LEGACY_IF_USED_C" =~ "5.2" ]]; then
      if [ -e "/opt/php52/bin/php" ] || [ -e "/etc/init.d/php52-fpm" ]; then
        msg "Legacy PHP-FPM 5.2 is used on this system but will be removed"
        echo " "
      fi
    fi

    _PHP_MULTI_INSTALL_TEST=$(grep _PHP_MULTI_INSTALL ${barCnf} 2>&1)

    if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.2" ]]; then
      _R_M=5.2
      _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
      sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${barCnf}
      sed -i "/^$/d" ${barCnf}
    fi

    if [ -e "/etc/init.d/php-fpm" ]; then
      mrun "service php-fpm stop" &> /dev/null
      update-rc.d -f php-fpm remove &> /dev/null
      rm -f /etc/init.d/php-fpm
    fi
    if [ -e "/etc/init.d/php52-fpm" ]; then
      mrun "service php52-fpm stop" &> /dev/null
      update-rc.d -f php52-fpm remove &> /dev/null
      rm -f /etc/init.d/php52-fpm
    fi
    killall -9 php-cgi &> /dev/null

    _CHECK_HOST=$(uname -n 2>&1)
    _L_VMFAMILY=XEN
    _L_VM_TEST=$(uname -a 2>&1)
    if [[ "${_L_VM_TEST}" =~ beng ]]; then
      _L_VMFAMILY="VS"
    fi
    if [ -e "/root/.auto.up.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [ "${_L_VMFAMILY}" = "VS" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _CLSTR_PHP_MULTI_INSTALL="${_PHP_MULTI_INSTALL}"
      fi
      if [ ! -e "/root/.debug.cnf" ]; then
        sed -i "s/^_PHP_MULTI_INSTALL.*//g" ${barCnf}
        sed -i "/^$/d" ${barCnf}
        _PHP_MULTI_INSTALL=""
      fi
    fi

    if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "_PHP_MULTI_INSTALL" ]] \
      && [ ! -z "${_PHP_MULTI_INSTALL}" ]; then
      _DO_NOTHING=YES
    else
      if [ -e "/root/.auto.up.cnf" ] \
        || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        || [ "${_L_VMFAMILY}" = "VS" ] \
        || [ -e "/root/.host8.cnf" ]; then
        if [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ]; then
          if [ ! -z "$_CLSTR_PHP_MULTI_INSTALL" ]; then
            _PHP_MULTI_INSTALL="$_CLSTR_PHP_MULTI_INSTALL"
          else
            _PHP_MULTI_INSTALL="5.5"
          fi
        else
          if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
            if [ "${_PHP_SINGLE_INSTALL}" = "5.6" ] \
              || [ "${_PHP_SINGLE_INSTALL}" = "5.5" ] \
              || [ "${_PHP_SINGLE_INSTALL}" = "5.4" ] \
              || [ "${_PHP_SINGLE_INSTALL}" = "5.3" ]; then
              _PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}
              _PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}
              _PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}
            fi
          else
            if [ ! -e "/root/.debug.cnf" ]; then
              _PHP_MULTI_INSTALL="5.6 5.5 5.4 5.3"
            fi
          fi
        fi
      fi
      if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
        if [ "${_PHP_SINGLE_INSTALL}" = "5.6" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "5.5" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "5.4" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "5.3" ]; then
          _PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}
          _PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}
          _PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}
        fi
      fi
      echo "_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"" >> ${barCnf}
    fi

    _PHP_FPM_VERSION_TEST=$(grep _PHP_FPM_VERSION ${barCnf} 2>&1)
    if [[ "${_PHP_FPM_VERSION_TEST}" =~ "_PHP_FPM_VERSION" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}" >> ${barCnf}
    fi

    _PHP_CLI_VERSION_TEST=$(grep _PHP_CLI_VERSION ${barCnf} 2>&1)
    if [[ "${_PHP_CLI_VERSION_TEST}" =~ "_PHP_CLI_VERSION" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}" >> ${barCnf}
    fi

    _PHP_SINGLE_INSTALL_TEST=$(grep _PHP_SINGLE_INSTALL ${barCnf} 2>&1)
    if [[ "${_PHP_SINGLE_INSTALL_TEST}" =~ "_PHP_SINGLE_INSTALL" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_SINGLE_INSTALL=${_PHP_SINGLE_INSTALL}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_LSHELL_TEST=$(grep _CUSTOM_CONFIG_LSHELL ${barCnf} 2>&1)
    if [[ "${_CUSTOM_CONFIG_LSHELL_TEST}" =~ "_CUSTOM_CONFIG_LSHELL" ]]; then
      _DO_NOTHING=YES
    else
      echo "_CUSTOM_CONFIG_LSHELL=${_CUSTOM_CONFIG_LSHELL}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_CSF_TEST=$(grep _CUSTOM_CONFIG_CSF ${barCnf} 2>&1)
    if [[ "${_CUSTOM_CONFIG_CSF_TEST}" =~ "_CUSTOM_CONFIG_CSF" ]]; then
      _DO_NOTHING=YES
    else
      echo "_CUSTOM_CONFIG_CSF=${_CUSTOM_CONFIG_CSF}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_SQL_TEST=$(grep _CUSTOM_CONFIG_SQL ${barCnf} 2>&1)
    if [[ "${_CUSTOM_CONFIG_SQL_TEST}" =~ "_CUSTOM_CONFIG_SQL" ]]; then
      _DO_NOTHING=YES
    else
      echo "_CUSTOM_CONFIG_SQL=${_CUSTOM_CONFIG_SQL}" >> ${barCnf}
    fi

    _SPEED_VALID_MAX_TEST=$(grep _SPEED_VALID_MAX ${barCnf} 2>&1)
    if [[ "${_SPEED_VALID_MAX_TEST}" =~ "_SPEED_VALID_MAX" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SPEED_VALID_MAX=${_SPEED_VALID_MAX}" >> ${barCnf}
    fi

    _NGINX_DOS_LIMIT_TEST=$(grep _NGINX_DOS_LIMIT ${barCnf} 2>&1)
    if [[ "${_NGINX_DOS_LIMIT_TEST}" =~ "_NGINX_DOS_LIMIT" ]]; then
      _DO_NOTHING=YES
    else
      echo "_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}" >> ${barCnf}
    fi

    _CPU_SPIDER_RATIO_TEST=$(grep _CPU_SPIDER_RATIO ${barCnf} 2>&1)
    if [[ "${_CPU_SPIDER_RATIO_TEST}" =~ "_CPU_SPIDER_RATIO" ]]; then
      _DO_NOTHING=YES
    else
      echo "_CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO}" >> ${barCnf}
    fi

    _CPU_MAX_RATIO_TEST=$(grep _CPU_MAX_RATIO ${barCnf} 2>&1)
    if [[ "${_CPU_MAX_RATIO_TEST}" =~ "_CPU_MAX_RATIO" ]]; then
      _DO_NOTHING=YES
    else
      echo "_CPU_MAX_RATIO=${_CPU_MAX_RATIO}" >> ${barCnf}
    fi

    _CPU_CRIT_RATIO_TEST=$(grep _CPU_CRIT_RATIO ${barCnf} 2>&1)
    if [[ "${_CPU_CRIT_RATIO_TEST}" =~ "_CPU_CRIT_RATIO" ]]; then
      _DO_NOTHING=YES
    else
      echo "_CPU_CRIT_RATIO=${_CPU_CRIT_RATIO}" >> ${barCnf}
    fi

    _SYSTEM_UPGRADE_ONLY_TEST=$(grep _SYSTEM_UPGRADE_ONLY ${barCnf} 2>&1)
    if [[ "${_SYSTEM_UPGRADE_ONLY_TEST}" =~ "_SYSTEM_UPGRADE_ONLY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SYSTEM_UPGRADE_ONLY=${_SYSTEM_UPGRADE_ONLY}" >> ${barCnf}
    fi

    _AEGIR_UPGRADE_ONLY_TEST=$(grep _AEGIR_UPGRADE_ONLY ${barCnf} 2>&1)
    if [[ "${_AEGIR_UPGRADE_ONLY_TEST}" =~ "_AEGIR_UPGRADE_ONLY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_AEGIR_UPGRADE_ONLY=${_AEGIR_UPGRADE_ONLY}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_REDIS_TEST=$(grep _CUSTOM_CONFIG_REDIS ${barCnf} 2>&1)
    if [[ "${_CUSTOM_CONFIG_REDIS_TEST}" =~ "_CUSTOM_CONFIG_REDIS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_CUSTOM_CONFIG_REDIS=${_CUSTOM_CONFIG_REDIS}" >> ${barCnf}
    fi

    _NEWRELIC_KEY_TEST=$(grep _NEWRELIC_KEY ${barCnf} 2>&1)
    if [[ "${_NEWRELIC_KEY_TEST}" =~ "_NEWRELIC_KEY" ]]; then
      _DO_NOTHING=YES
    else
      if [ ! -z "${_NEWRELIC_KEY}" ]; then
        echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}" >> ${barCnf}
      else
        if [ -e "/etc/newrelic/newrelic.cfg" ]; then
          _NEWRELIC_KEY=$(grep license_key /etc/newrelic/newrelic.cfg 2>&1)
          _NEWRELIC_KEY=$(echo -n ${_NEWRELIC_KEY} | tr -d "\n" 2>&1)
          echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}" >> ${barCnf}
          sed -i "s/license_key=//g" ${barCnf}
        fi
      fi
    fi

    _SCOUT_KEY_TEST=$(grep _SCOUT_KEY ${barCnf} 2>&1)
    if [[ "${_SCOUT_KEY_TEST}" =~ "_SCOUT_KEY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SCOUT_KEY=${_SCOUT_KEY}" >> ${barCnf}
    fi

    _EXTRA_PACKAGES_TEST=$(grep _EXTRA_PACKAGES ${barCnf} 2>&1)
    if [[ "${_EXTRA_PACKAGES_TEST}" =~ "_EXTRA_PACKAGES" ]]; then
      _DO_NOTHING=YES
    else
      echo "_EXTRA_PACKAGES=${_EXTRA_PACKAGES}" >> ${barCnf}
    fi

    _PHP_EXTRA_CONF_TEST=$(grep _PHP_EXTRA_CONF ${barCnf} 2>&1)
    if [[ "${_PHP_EXTRA_CONF_TEST}" =~ "_PHP_EXTRA_CONF" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_EXTRA_CONF=\"${_PHP_EXTRA_CONF}\"" >> ${barCnf}
    fi

    _PHP_FPM_DENY_TEST=$(grep _PHP_FPM_DENY ${barCnf} 2>&1)
    if [[ "${_PHP_FPM_DENY_TEST}" =~ "_PHP_FPM_DENY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\"" >> ${barCnf}
    fi

    _STRONG_PASSWORDS_TEST=$(grep _STRONG_PASSWORDS ${barCnf} 2>&1)
    if [[ "${_STRONG_PASSWORDS_TEST}" =~ "_STRONG_PASSWORDS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}" >> ${barCnf}
    fi

    _DB_BINARY_LOG_TEST=$(grep _DB_BINARY_LOG ${barCnf} 2>&1)
    if [[ "${_DB_BINARY_LOG_TEST}" =~ "_DB_BINARY_LOG" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DB_BINARY_LOG=${_DB_BINARY_LOG}" >> ${barCnf}
    fi

    _INNODB_LOG_FILE_SIZE_TEST=$(grep _INNODB_LOG_FILE_SIZE ${barCnf} 2>&1)
    if [[ "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "_INNODB_LOG_FILE_SIZE" ]]; then
      _DO_NOTHING=YES
    else
      echo "_INNODB_LOG_FILE_SIZE=${_INNODB_LOG_FILE_SIZE}" >> ${barCnf}
    fi

    _DB_ENGINE_TEST=$(grep _DB_ENGINE ${barCnf} 2>&1)
    if [[ "${_DB_ENGINE_TEST}" =~ "_DB_ENGINE" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DB_ENGINE=${_DB_ENGINE}" >> ${barCnf}
    fi

    _REDIS_LISTEN_MODE_TEST=$(grep _REDIS_LISTEN_MODE ${barCnf} 2>&1)
    if [[ "${_REDIS_LISTEN_MODE_TEST}" =~ "_REDIS_LISTEN_MODE" ]]; then
      _DO_NOTHING=YES
    else
      echo "_REDIS_LISTEN_MODE=${_REDIS_LISTEN_MODE}" >> ${barCnf}
    fi

    _NGINX_LDAP_TEST=$(grep _NGINX_LDAP ${barCnf} 2>&1)
    if [[ "${_NGINX_LDAP_TEST}" =~ "_NGINX_LDAP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_NGINX_LDAP=${_NGINX_LDAP}" >> ${barCnf}
    fi

    _NGINX_NAXSI_TEST=$(grep _NGINX_NAXSI ${barCnf} 2>&1)
    if [[ "${_NGINX_NAXSI_TEST}" =~ "_NGINX_NAXSI" ]]; then
      _DO_NOTHING=YES
    else
      echo "_NGINX_NAXSI=${_NGINX_NAXSI}" >> ${barCnf}
    fi

    _NGINX_SPDY_TEST=$(grep _NGINX_SPDY ${barCnf} 2>&1)
    if [[ "${_NGINX_SPDY_TEST}" =~ "_NGINX_SPDY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_NGINX_SPDY=${_NGINX_SPDY}" >> ${barCnf}
    fi

    _NGINX_FORWARD_SECRECY_TEST=$(grep _NGINX_FORWARD_SECRECY ${barCnf} 2>&1)
    if [[ "${_NGINX_FORWARD_SECRECY_TEST}" =~ "_NGINX_FORWARD_SECRECY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_NGINX_FORWARD_SECRECY=${_NGINX_FORWARD_SECRECY}" >> ${barCnf}
    fi

    _PHP_GEOS_TEST=$(grep _PHP_GEOS ${barCnf} 2>&1)
    if [[ "${_PHP_GEOS_TEST}" =~ "_PHP_GEOS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_GEOS=${_PHP_GEOS}" >> ${barCnf}
    fi

    _PHP_MONGODB_TEST=$(grep _PHP_MONGODB ${barCnf} 2>&1)
    if [[ "${_PHP_MONGODB_TEST}" =~ "_PHP_MONGODB" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_MONGODB=${_PHP_MONGODB}" >> ${barCnf}
    fi

    _PERMISSIONS_FIX_TEST=$(grep _PERMISSIONS_FIX ${barCnf} 2>&1)
    if [[ "${_PERMISSIONS_FIX_TEST}" =~ "_PERMISSIONS_FIX" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PERMISSIONS_FIX=${_PERMISSIONS_FIX}" >> ${barCnf}
    fi

    _MODULES_FIX_TEST=$(grep _MODULES_FIX ${barCnf} 2>&1)
    if [[ "${_MODULES_FIX_TEST}" =~ "_MODULES_FIX" ]]; then
      _DO_NOTHING=YES
    else
      echo "_MODULES_FIX=${_MODULES_FIX}" >> ${barCnf}
    fi

    _MODULES_SKIP_TEST=$(grep _MODULES_SKIP ${barCnf} 2>&1)
    if [[ "${_MODULES_SKIP_TEST}" =~ "_MODULES_SKIP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_MODULES_SKIP=\"${_MODULES_SKIP}\"" >> ${barCnf}
    fi

    _SSL_FROM_SOURCES_TEST=$(grep _SSL_FROM_SOURCES ${barCnf} 2>&1)
    if [[ "${_SSL_FROM_SOURCES_TEST}" =~ "_SSL_FROM_SOURCES" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SSL_FROM_SOURCES=${_SSL_FROM_SOURCES}" >> ${barCnf}
    fi

    _SSH_FROM_SOURCES_TEST=$(grep _SSH_FROM_SOURCES ${barCnf} 2>&1)
    if [[ "${_SSH_FROM_SOURCES_TEST}" =~ "_SSH_FROM_SOURCES" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SSH_FROM_SOURCES=${_SSH_FROM_SOURCES}" >> ${barCnf}
    fi

    _RESERVED_RAM_TEST=$(grep _RESERVED_RAM ${barCnf} 2>&1)
    if [[ "${_RESERVED_RAM_TEST}" =~ "_RESERVED_RAM" ]]; then
      _DO_NOTHING=YES
    else
      echo "_RESERVED_RAM=${_RESERVED_RAM}" >> ${barCnf}
    fi

    _STRICT_BIN_PERMISSIONS_TEST=$(grep _STRICT_BIN_PERMISSIONS ${barCnf} 2>&1)
    if [[ "${_STRICT_BIN_PERMISSIONS_TEST}" =~ "_STRICT_BIN_PERMISSIONS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_STRICT_BIN_PERMISSIONS=${_STRICT_BIN_PERMISSIONS}" >> ${barCnf}
    fi

    _DB_SERIES_TEST=$(grep _DB_SERIES ${barCnf} 2>&1)
    if [[ "${_DB_SERIES_TEST}" =~ "_DB_SERIES" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DB_SERIES=${_DB_SERIES}" >> ${barCnf}
    fi

    if [ -e "/etc/init.d/tomcat" ]; then
      echo "_TOMCAT_TO_JETTY=YES" >> ${barCnf}
    fi

    ###
    ### config cleanup start
    ###
    _USE_STOCK_TEST=$(grep _USE_STOCK ${barCnf} 2>&1)
    if [[ "${_USE_STOCK_TEST}" =~ "_USE_STOCK" ]]; then
      sed -i "s/^_USE_STOCK.*//g" ${barCnf}
    fi
    _HTTP_WILDCARD_TEST=$(grep _HTTP_WILDCARD ${barCnf} 2>&1)
    if [[ "${_HTTP_WILDCARD_TEST}" =~ "_HTTP_WILDCARD" ]]; then
      sed -i "s/^_HTTP_WILDCARD.*//g" ${barCnf}
    fi
    _PHP_MODERN_ONLY_TEST=$(grep _PHP_MODERN_ONLY ${barCnf} 2>&1)
    if [[ "${_PHP_MODERN_ONLY_TEST}" =~ "_PHP_MODERN_ONLY" ]]; then
      sed -i "s/^_PHP_MODERN_ONLY.*//g" ${barCnf}
    fi
    _USE_SPEED_BOOSTER_TEST=$(grep _USE_SPEED_BOOSTER ${barCnf} 2>&1)
    if [[ "${_USE_SPEED_BOOSTER_TEST}" =~ "_USE_SPEED_BOOSTER" ]]; then
      sed -i "s/^_USE_SPEED_BOOSTER.*//g" ${barCnf}
    fi
    _PHP_INSTALL_NEW_TEST=$(grep _PHP_INSTALL_NEW ${barCnf} 2>&1)
    if [[ "${_PHP_INSTALL_NEW_TEST}" =~ "_PHP_INSTALL_NEW" ]]; then
      sed -i "s/^_PHP_INSTALL_NEW.*//g" ${barCnf}
    fi
    _CUSTOM_CONFIG_PHP_TEST=$(grep _CUSTOM_CONFIG_PHP ${barCnf} 2>&1)
    if [[ "${_CUSTOM_CONFIG_PHP_TEST}" =~ "_CUSTOM_CONFIG_PHP" ]]; then
      sed -i "s/^_CUSTOM_CONFIG_PHP.*//g" ${barCnf}
    fi
    _LOAD_LIMIT_ONE_TEST=$(grep _LOAD_LIMIT_ONE ${barCnf} 2>&1)
    if [[ "${_LOAD_LIMIT_ONE_TEST}" =~ "_LOAD_LIMIT_ONE" ]]; then
      sed -i "s/^_LOAD_LIMIT_ONE.*//g" ${barCnf}
    fi
    _LOAD_LIMIT_TWO_TEST=$(grep _LOAD_LIMIT_TWO ${barCnf} 2>&1)
    if [[ "${_LOAD_LIMIT_TWO_TEST}" =~ "_LOAD_LIMIT_TWO" ]]; then
      sed -i "s/^_LOAD_LIMIT_TWO.*//g" ${barCnf}
    fi
    _USE_MEMCACHED_TEST=$(grep _USE_MEMCACHED ${barCnf} 2>&1)
    if [[ "${_USE_MEMCACHED_TEST}" =~ "_USE_MEMCACHED" ]]; then
      sed -i "s/^_USE_MEMCACHED.*//g" ${barCnf}
    fi
    _PHP_ZEND_OPCACHE_TEST=$(grep _PHP_ZEND_OPCACHE ${barCnf} 2>&1)
    if [[ "${_PHP_ZEND_OPCACHE_TEST}" =~ "_PHP_ZEND_OPCACHE" ]]; then
      sed -i "s/^_PHP_ZEND_OPCACHE.*//g" ${barCnf}
    fi
    _BUILD_FROM_SRC_TEST=$(grep _BUILD_FROM_SRC ${barCnf} 2>&1)
    if [[ "${_BUILD_FROM_SRC_TEST}" =~ "_BUILD_FROM_SRC" ]]; then
      sed -i "s/^_BUILD_FROM_SRC.*//g" ${barCnf}
    fi
    ###
    ### config cleanup end
    ###

    sleep 1
    _CHECK_HOST=$(uname -n 2>&1)
    sed -i "s/^_DB_SERVER=.*/_DB_SERVER=MariaDB/g" ${barCnf}
    if [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.debug.cnf" ]; then
        _DO_NOTHING=YES
      else
        sed -i "s/^_AUTOPILOT=.*/_AUTOPILOT=YES/g"                                 ${barCnf}
        sed -i "s/^_DB_ENGINE=.*/_DB_ENGINE=InnoDB/g"                              ${barCnf}
        sed -i "s/^_DB_SERVER=.*/_DB_SERVER=MariaDB/g"                             ${barCnf}
        sed -i "s/^_DEBUG_MODE=.*/_DEBUG_MODE=NO/g"                                ${barCnf}
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  ${barCnf}
        sed -i "s/^_LOCAL_DEBIAN_MIRROR=.*/_LOCAL_DEBIAN_MIRROR=ftp.debian.org/g"  ${barCnf}
        sed -i "s/^_MY_EMAIL=.*/_MY_EMAIL=\"notify\@omega8.cc\"/g"                 ${barCnf}
        sed -i "s/^_NGINX_FORWARD_SECRECY=.*/_NGINX_FORWARD_SECRECY=YES/g"         ${barCnf}
        sed -i "s/^_NGINX_SPDY=.*/_NGINX_SPDY=YES/g"                               ${barCnf}
        sed -i "s/^_SSH_FROM_SOURCES=.*/_SSH_FROM_SOURCES=YES/g"                   ${barCnf}
        sed -i "s/^_STRICT_BIN_PERMISSIONS=.*/_STRICT_BIN_PERMISSIONS=YES/g"       ${barCnf}
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   ${barCnf}
        sed -i "s/^_DEBUG_MODE=.*/_DEBUG_MODE=NO/g"                                /root/.*.octopus.cnf &> /dev/null
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  /root/.*.octopus.cnf &> /dev/null
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   /root/.*.octopus.cnf &> /dev/null
        if [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ] \
          || [ -e "/root/.test.clstr.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/^_REDIS_LISTEN_MODE=.*/_REDIS_LISTEN_MODE=SOCKET/g"            ${barCnf}
        fi
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] || [ "${_VMFAMILY}" = "VS" ]; then
          if [ "${_VMFAMILY}" = "VS" ]; then
            sed -i "s/^_CPU_CRIT_RATIO=.*/_CPU_CRIT_RATIO=3/g"                     ${barCnf}
            sed -i "s/^_CPU_MAX_RATIO=.*/_CPU_MAX_RATIO=2/g"                       ${barCnf}
            sed -i "s/^_CPU_SPIDER_RATIO=.*/_CPU_SPIDER_RATIO=1/g"                 ${barCnf}
          fi
          sed -i "s/^_MODULES_FIX=.*/_MODULES_FIX=YES/g"                           ${barCnf}
          sed -i "s/^_PERMISSIONS_FIX=.*/_PERMISSIONS_FIX=YES/g"                   ${barCnf}
          sed -i "s/^_SQL_CONVERT=.*/_SQL_CONVERT=NO/g"                            /root/.*.octopus.cnf &> /dev/null
          if [ -x "/opt/php55/bin/php" ] && [ -z "${_PHP_SINGLE_INSTALL}" ]; then
            sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=5.5/g"                 ${barCnf}
            sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=5.5/g"                 ${barCnf}
          fi
        fi
      fi
    fi
    sed -i "/^$/d" ${barCnf}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo " "
      while read line; do
        echo "$line"
      done < ${barCnf}
      echo " "
    fi
    if [ -e "${barCnf}" ]; then
      source ${barCnf}
    fi
    if [ "${_LOCAL_DEBIAN_MIRROR}" = "http.debian.net" ]; then
      _LOCAL_DEBIAN_MIRROR=ftp.debian.org
      sed -i "s/^_LOCAL_DEBIAN_MIRROR=.*/_LOCAL_DEBIAN_MIRROR=ftp.debian.org/g"    ${barCnf}
    fi
    if [ "${_DB_SERIES}" = "10.0" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _MARIADB_VRN="${_GALERA_10_VRN}"
      else
        _MARIADB_VRN="${_MARIADB_10_VRN}"
      fi
    else
      _DB_SERIES=5.5
      _MARIADB_VRN="${_MARIADB_5_VRN}"
    fi
    _CHECK_HOST=$(uname -n 2>&1)
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      if [ -e "/root/.auto.up.cnf" ] \
        || [ -e "/root/.host8.cnf" ] \
        || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        || [ "${_VMFAMILY}" = "VS" ]; then
        if [ -e "/root/.debug.cnf" ]; then
          _DO_NOTHING=YES
        else
          _DB_SERVER=MariaDB
        fi
      else
        msg "EXIT: Invalid e-mail address defined in the _MY_EMAIL variable"
        msg "EXIT: Bye (2)"
        clean_pid_exit
      fi
    fi

    ### Make sure that _PHP_SINGLE_INSTALL takes precedence
    if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
      if [ "${_PHP_SINGLE_INSTALL}" = "5.6" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "5.5" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "5.4" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "5.3" ]; then
        _PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}
        _PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}
        _PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}
        sed -i "s/^_PHP_MULTI_INSTALL=.*/_PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}/g" ${barCnf}
        sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}/g"     ${barCnf}
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}/g"     ${barCnf}
        sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=5.2/g" /root/.*.octopus.cnf &> /dev/null
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=5.2/g" /root/.*.octopus.cnf &> /dev/null
        if [ -e "/data/disk" ] && [ -e "/data/conf/global.inc" ]; then
          for Ctrl in `find /data/disk/*/log -maxdepth 0 -mindepth 0 | sort`; do
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/fpm.txt
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/cli.txt
            ### msg "INFO: Forced PHP ${_PHP_SINGLE_INSTALL} in $Ctrl"
          done
          for Ctrl in `find /data/disk/*/static/control \
            -maxdepth 0 -mindepth 0 | sort`; do
            echo 5.2 > $Ctrl/fpm.info
            echo 5.2 > $Ctrl/cli.info
            ### msg "INFO: Forced PHP ${_PHP_SINGLE_INSTALL} in $Ctrl"
          done
          for Ctrl in `find /data/disk/*/.drush \
            -maxdepth 0 -mindepth 0 | sort`; do
            rm -f $Ctrl/.ctrl.php*
            ### msg "INFO: Forced PHP ${_PHP_SINGLE_INSTALL} in $Ctrl"
          done
        fi
      fi
    fi

    ###
    ### config cleanup start
    ###
    _NGX_FORCE_REINSTALL_TEST=$(grep _NGX_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_NGX_FORCE_REINSTALL_TEST}" =~ "_NGX_FORCE_REINSTALL" ]]; then
      sed -i "s/^_NGX_FORCE_REINSTALL.*//g" ${barCnf}
    fi
    _PHP_FORCE_REINSTALL_TEST=$(grep _PHP_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_PHP_FORCE_REINSTALL_TEST}" =~ "_PHP_FORCE_REINSTALL" ]]; then
      sed -i "s/^_PHP_FORCE_REINSTALL.*//g" ${barCnf}
    fi
    _SQL_FORCE_REINSTALL_TEST=$(grep _SQL_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_SQL_FORCE_REINSTALL_TEST}" =~ "_SQL_FORCE_REINSTALL" ]]; then
      sed -i "s/^_SQL_FORCE_REINSTALL.*//g" ${barCnf}
    fi
    _SSL_FORCE_REINSTALL_TEST=$(grep _SSL_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_SSL_FORCE_REINSTALL_TEST}" =~ "_SSL_FORCE_REINSTALL" ]]; then
      sed -i "s/^_SSL_FORCE_REINSTALL.*//g" ${barCnf}
    fi
    _SSH_FORCE_REINSTALL_TEST=$(grep _SSH_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_SSH_FORCE_REINSTALL_TEST}" =~ "_SSH_FORCE_REINSTALL" ]]; then
      sed -i "s/^_SSH_FORCE_REINSTALL.*//g" ${barCnf}
    fi
    _GIT_FORCE_REINSTALL_TEST=$(grep _GIT_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_GIT_FORCE_REINSTALL_TEST}" =~ "_GIT_FORCE_REINSTALL" ]]; then
      sed -i "s/^_GIT_FORCE_REINSTALL.*//g" ${barCnf}
    fi
    _FULL_FORCE_REINSTALL_TEST=$(grep _FULL_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_FULL_FORCE_REINSTALL_TEST}" =~ "_FULL_FORCE_REINSTALL" ]]; then
      sed -i "s/^_FULL_FORCE_REINSTALL.*//g" ${barCnf}
    fi
    _TOMCAT_TO_JETTY_TEST=$(grep _TOMCAT_TO_JETTY ${barCnf} 2>&1)
    if [[ "${_TOMCAT_TO_JETTY_TEST}" =~ "_TOMCAT_TO_JETTY" ]]; then
      if [ ! -e "/etc/init.d/tomcat" ]; then
        sed -i "s/^_TOMCAT_TO_JETTY.*//g" ${barCnf}
      fi
    fi
    _SQUEEZE_TO_WHEEZY_TEST=$(grep _SQUEEZE_TO_WHEEZY ${barCnf} 2>&1)
    if [[ "${_SQUEEZE_TO_WHEEZY_TEST}" =~ "_SQUEEZE_TO_WHEEZY" ]]; then
      sed -i "s/^_SQUEEZE_TO_WHEEZY.*//g" ${barCnf}
    fi
    _LENNY_TO_SQUEEZE_TEST=$(grep _LENNY_TO_SQUEEZE ${barCnf} 2>&1)
    if [[ "${_LENNY_TO_SQUEEZE_TEST}" =~ "_LENNY_TO_SQUEEZE" ]]; then
      sed -i "s/^_LENNY_TO_SQUEEZE.*//g" ${barCnf}
    fi
    sed -i "/^$/d" ${barCnf}
    ###
    ### config cleanup end
    ###

    if [ "${_STATUS}" = "INIT" ]; then
      if prompt_yes_no "Do you want to proceed with the install?" ; then
        true
      else
        echo "Installation aborted by you"
        clean_pid_exit
      fi
    else
      echo " "
      if prompt_yes_no "Do you want to proceed with the upgrade?" ; then
        true
      else
        echo "Upgrade aborted by you"
        clean_pid_exit
      fi
    fi
  fi
}

#
# Running aptitude full-upgrade.
run_aptitude_full_upgrade() {
  msg "INFO: Running aptitude full-upgrade..."
  _BROKEN_KEYRING_TEST=$(apt-get update 2>&1)
  if [[ "$_BROKEN_KEYRING_TEST" =~ "signatures were invalid" ]] \
    || [[ "$_BROKEN_KEYRING_TEST" =~ "GPG error" ]]; then
    msg "WARN: Installed keyring is broken, forced reinstall required"
    if [ "${_THIS_OS}" = "Debian" ]; then
      st_runner "apt-get install debian-keyring ${forCer}" 2> /dev/null
      st_runner "apt-get install debian-archive-keyring ${forCer}" 2> /dev/null
    else
      st_runner "apt-get install ubuntu-keyring ${forCer}" 2> /dev/null
    fi
  fi
  st_runner "dpkg --configure --force-all -a" 2> /dev/null
  st_runner "aptitude update -y" &> /dev/null
  _THIS_DB_SERVER_TEST=$(mysql -V 2>&1)
  if [[ "${_THIS_DB_SERVER_TEST}" =~ "MariaDB" ]] \
    && [ ! -e "${pthLog}/fixed-mytop-mariadb.log" ]; then
    st_runner "aptitude remove mytop -y" &> /dev/null
    st_runner "apt-get purge mytop -y --force-yes -qq" &> /dev/null
    rm -f /usr/bin/mytop
    touch ${pthLog}/fixed-mytop-mariadb.log
  fi
  st_runner "aptitude full-upgrade -f -y -q \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold" 2> /dev/null
  if [[ "${_THIS_DB_SERVER_TEST}" =~ "MariaDB" ]] \
    && [ -e "${pthLog}/fixed-mytop-mariadb.log" ]; then
    st_runner "$_INSTAPP mytop" 2> /dev/null
  fi
}

#
# Running silent aptitude full-upgrade.
run_silent_aptitude_full_upgrade() {
  msg "INFO: Running silent aptitude full-upgrade..."
  _BROKEN_KEYRING_TEST=$(apt-get update 2>&1)
  if [[ "$_BROKEN_KEYRING_TEST" =~ "signatures were invalid" ]] \
    || [[ "$_BROKEN_KEYRING_TEST" =~ "GPG error" ]]; then
    msg "WARN: Installed keyring is broken, forced reinstall required"
    if [ "${_THIS_OS}" = "Debian" ]; then
      mrun "apt-get install debian-keyring ${forCer}" 2> /dev/null
      mrun "apt-get install debian-archive-keyring ${forCer}" 2> /dev/null
    else
      mrun "apt-get install ubuntu-keyring ${forCer}" 2> /dev/null
    fi
  fi
  mrun "dpkg --configure --force-all -a" 2> /dev/null
  mrun "apt-get update -y" 2> /dev/null
  mrun "dpkg --configure --force-all -a" 2> /dev/null
  mrun "apt-get install aptitude ${forCer}" 2> /dev/null
  mrun "apt-get install util-linux ${forCer}" 2> /dev/null
  mrun "apt-get install libmagickwand-dev ${forCer}" 2> /dev/null
  mrun "aptitude full-upgrade -f -y -q -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold --allow-unauthenticated" 2> /dev/null
}

#
# Install latest Git.
do_install_latest_git() {
  if [ ! -e "${pthLog}/git-${_GIT_VRN}-${_X_VERSION}-${_NOW}.log" ]; then
    msg "INFO: Building Git ${_GIT_VRN} from sources, please wait..."
    cd /var/opt
    rm -f -r git*
    get_dev_src "git-${_GIT_VRN}.tar.gz"
    cd /var/opt/git-${_GIT_VRN}
    st_runner "make configure" 2> /dev/null
    st_runner "sh ./configure --without-tcltk --quiet" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "make --quiet install" 2> /dev/null
    mv -f /usr/bin/git /usr/bin/git-old
    ln -sf /usr/local/bin/git /usr/bin/git
    cd /var/opt
    touch ${pthLog}/git-${_GIT_VRN}-${_X_VERSION}-${_NOW}.log
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Git ${_GIT_VRN} already installed from sources, OK"
    fi
  fi
}

#
# Check if latest Git should be installed.
check_install_latest_git() {
  _GIT_ITD=$(git --version 2>&1)
  if [[ "$_GIT_ITD" =~ "git version 1.9.1" ]]; then
    _GIT_FORCE_REINSTALL=YES
  fi
  if [[ "${_XTRAS_LIST}" =~ "GIT" ]] \
    || [ "${_OSV}" = "lenny" ] \
    || [ "${_OSV}" = "lucid" ] \
    || [ "$_SSB_SRC" = "YES" ] \
    || [ "$_GIT_FORCE_REINSTALL" = "YES" ]; then
    _GIT_TEST=$(git --version 2>&1)
    if [[ "$_GIT_TEST" =~ "git version ${_GIT_VRN}" ]]; then
      if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
        || [ "$_GIT_FORCE_REINSTALL" = "YES" ]; then
        do_install_latest_git
      fi
    else
      do_install_latest_git
    fi
  fi
}

#
# Check apt updates.
check_apt_updates() {
  for Update in `/usr/bin/apt-get -q -y --force-yes --allow-unauthenticated \
    -s dist-upgrade | grep ^Inst | cut -d\  -f2 | sort`; do
    case $Update in
      *libcurl*)    _UP_CRL=YES ;;
      *libmysql*)   _UP_PHP=YES ;;
      *libssl*)     _UP_PHP=YES ;;
      *linux-*)     _UP_LNX=YES ;;
      *mariadb*)    _UP_PHP=YES ;;
      *newrelic*)   _UP_NRC=YES ;;
      *openjdk*)    _UP_JDK=YES ;;
      *openssl*)    _YP_PHP=YES ;;
      *)  ;;
    esac
  done
  if [ "$_YP_PHP" = "YES" ]; then
    if [ "${_NGINX_SPDY}" = "YES" ] \
      || [ "${_SSL_FROM_SOURCES}" = "YES" ] \
      || [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
      if [ "${_OSV}" = "wheezy" ] \
        || [ "${_OSV}" = "trusty" ] \
        || [ "${_OSV}" = "precise" ]; then
        _UP_PHP=YES
      else
        _UP_PHP=NO
      fi
    else
      _UP_PHP=YES
    fi
  fi
  if [ "$_UP_CRL" = "YES" ]; then
    _UP_PHP=YES
  fi
}

#
# Install wkhtmltopdf.
install_wkhtmltopdf() {
  ###--------------------###
  if [ ! -e "${pthLog}/wkhtmltopdf-fix10" ] \
    || [ ! -x "/usr/bin/wkhtmltopdf" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "$_X86_64_TEST" = "x86_64" ]; then
      SYSTEMARCH="x86_64"
      msg "INFO: Installing /usr/bin/wkhtmltopdf $SYSTEMARCH version..."
      cd /var/opt
      rm -f -r wkhtmltopdf*
      get_dev_arch "wkhtmltopdf-0.10.0_rc2-static-amd64.tar.bz2"
      cp -af wkhtmltopdf-amd64 /usr/bin/wkhtmltopdf &> /dev/null
      chown root:root /usr/bin/wkhtmltopdf &> /dev/null
      chmod 755 /usr/bin/wkhtmltopdf &> /dev/null
    else
      SYSTEMARCH="x86"
      msg "INFO: Installing /usr/bin/wkhtmltopdf $SYSTEMARCH version..."
      cd /var/opt
      rm -f -r wkhtmltopdf*
      get_dev_arch "wkhtmltopdf-0.10.0_rc2-static-i386.tar.bz2"
      cp -af wkhtmltopdf-i386 /usr/bin/wkhtmltopdf &> /dev/null
      chown root:root /usr/bin/wkhtmltopdf &> /dev/null
      chmod 755 /usr/bin/wkhtmltopdf &> /dev/null
    fi
    touch ${pthLog}/wkhtmltopdf-fix10
  fi
}

#
# Install wkhtmltoimage.
install_wkhtmltoimage() {
  ###--------------------###
  if [ ! -e "${pthLog}/wkhtmltoimage-fix10" ] \
    || [ ! -x "/usr/bin/wkhtmltoimage" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "$_X86_64_TEST" = "x86_64" ]; then
      SYSTEMARCH="x86_64"
      msg "INFO: Installing /usr/bin/wkhtmltoimage $SYSTEMARCH version..."
      cd /var/opt
      rm -f -r wkhtmltoimage*
      get_dev_arch "wkhtmltoimage-0.10.0_rc2-static-amd64.tar.bz2"
      cp -af wkhtmltoimage-amd64 /usr/bin/wkhtmltoimage &> /dev/null
      chown root:root /usr/bin/wkhtmltoimage &> /dev/null
      chmod 755 /usr/bin/wkhtmltoimage &> /dev/null
    else
      SYSTEMARCH="x86"
      msg "INFO: Installing /usr/bin/wkhtmltoimage $SYSTEMARCH version..."
      cd /var/opt
      rm -f -r wkhtmltoimage*
      get_dev_arch "wkhtmltoimage-0.10.0_rc2-static-i386.tar.bz2"
      cp -af wkhtmltoimage-i386 /usr/bin/wkhtmltoimage &> /dev/null
      chown root:root /usr/bin/wkhtmltoimage &> /dev/null
      chmod 755 /usr/bin/wkhtmltoimage &> /dev/null
    fi
    touch ${pthLog}/wkhtmltoimage-fix10
  fi
}

#
# Install or update Drush versions.
get_drush_versions() {
  ###--------------------###
  mkdir -p /opt/tools/drush/{4,6,7}
  chown -R root:root /opt/tools
  rm -f -r /opt/tools/drush/4/*
  cd /opt/tools/drush/4/
  get_dev_ext "drush-${_DRUSH4_VRN}.tar.gz"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH4_VRN} installation complete"
  fi
  rm -f -r /opt/tools/drush/6/*
  cd /opt/tools/drush/6/
  get_dev_ext "drush-${_DRUSH6_VRN}.tar.gz"
  cd /opt/tools/drush/6/drush/lib
  get_dev_ext "Console_Table-1.1.3.tgz"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH6_VRN} installation complete"
  fi
  rm -f -r /opt/tools/drush/7/*
  cd /opt/tools/drush/7/
  get_dev_ext "drush-${_DRUSH7_VRN}.tar.gz"
  cd /opt/tools/drush/7/drush/
  rm -f -r /opt/tools/drush/7/drush/vendor
  get_dev_ext "vendor-${_DRUSH7_VRN}.tar.gz"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH7_VRN} installation complete"
  fi
  find /opt/tools -type d -exec chmod 0755 {} \; &> /dev/null
  find /opt/tools -type f -exec chmod 0644 {} \; &> /dev/null
  chmod 755 /opt/tools/drush/*/drush/drush
  chmod 755 /opt/tools/drush/*/drush/drush.php
  if [ -x "/opt/tools/drush/4/drush/drush" ]; then
    rm -f /usr/bin/drush4
    ln -s /opt/tools/drush/4/drush/drush /usr/bin/drush4
  fi
  if [ -x "/opt/tools/drush/6/drush/drush" ]; then
    rm -f /usr/bin/drush6
    ln -s /opt/tools/drush/6/drush/drush /usr/bin/drush6
  fi
  if [ -x "/opt/tools/drush/7/drush/drush" ]; then
    rm -f /usr/bin/drush7
    rm -f /usr/bin/drush
    ln -s /opt/tools/drush/7/drush/drush /usr/bin/drush7
    ln -s /opt/tools/drush/7/drush/drush /usr/bin/drush
  else
    rm -f /usr/bin/drush7
    if [ -x "/opt/tools/drush/6/drush/drush" ]; then
      ln -s /opt/tools/drush/6/drush/drush /usr/bin/drush7
    fi
  fi
  if [ -e "/opt/tools/drush/5" ]; then
    rm -f -r /opt/tools/drush/5
    rm -f /usr/bin/drush5
  fi
  chown -R root:root /opt/tools/drush
  cd /opt/tmp
}

#
# Update packages sources list.
update_sources_list() {
  ###--------------------###
  if [ -e "${pthLog}/apt-fast-install-log.txt" ] \
    || [ -e "/var/log/apt-fast-install-log.txt" ]; then
    _APT_SOURCES_REWRITE=NO
    if [ ! -z "${_LOCAL_DEBIAN_MIRROR}" ]; then
      _APT_SOURCES_REWRITE=YES
    fi
    if [ ! -z "${_LOCAL_UBUNTU_MIRROR}" ]; then
      _APT_SOURCES_REWRITE=YES
    fi
    if [ "${_OSV}" = "lenny" ]; then
      sed -i "s/^deb.*security.debian.org.*/## security updates no longer \
        available for lenny/g" ${aptLiSys} &> /dev/null
      sed -i "s/ftp.*debian.org/archive.debian.org/g" \
        ${aptLiSys} &> /dev/null
      sed -i "s/volatile.debian.org/archive.debian.org/g" \
        ${aptLiSys} &> /dev/null
    fi
    if [ "${_SQUEEZE_TO_WHEEZY}" = "YES" ] \
      && [ "${_OSV}" = "squeeze" ]; then
      run_silent_aptitude_full_upgrade
      _LOC_OSV=squeeze
      _OSV=wheezy
      _APT_SOURCES_REWRITE=YES
    elif [ "${_LENNY_TO_SQUEEZE}" = "YES" ] \
      && [ "${_OSV}" = "lenny" ]; then
      run_silent_aptitude_full_upgrade
      _LOC_OSV=lenny
      _OSV=squeeze
      _APT_SOURCES_REWRITE=YES
    fi
    if [ "${_OSV}" = "squeeze" ]; then
      _LTS_TEST=$(grep "DEBIAN LTS UPDATES" ${aptLiSys} 2>&1)
      if [[ "$_LTS_TEST" =~ "DEBIAN LTS UPDATES" ]]; then
        _DO_NOTHING=YES
      else
        _APT_SOURCES_REWRITE=YES
      fi
      _PROPOSED_TEST=$(grep "DEBIAN PROPOSED UPDATES" ${aptLiSys} 2>&1)
      if [[ "$_PROPOSED_TEST" =~ "DEBIAN PROPOSED UPDATES" ]]; then
        _DO_NOTHING=YES
      else
        _APT_SOURCES_REWRITE=YES
      fi
      _VOLATILE_TEST=$(grep "MAJOR BUG FIX UPDATES" ${aptLiSys} 2>&1)
      if [[ "$_VOLATILE_TEST" =~ "MAJOR BUG FIX UPDATES" ]]; then
        _DO_NOTHING=YES
      else
        _APT_SOURCES_REWRITE=YES
      fi
      if [ ! -e "${aptLiSys}.d/mariadb.list" ]; then
        _APT_SOURCES_REWRITE=YES
      fi
    fi
  else
    _APT_SOURCES_REWRITE=YES
  fi
  if [ "$_APT_SOURCES_REWRITE" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Updating packages sources list..."
    fi
    mv -f ${aptLiSys} \
      ${vBs}/sources.list-pre-${_X_VERSION}-${_NOW} &> /dev/null
    if [ "${_THIS_OS}" = "Ubuntu" ]; then
      if [ "${_AUTOPILOT}" = "YES" ]; then
        if [ -z "${_LOCAL_UBUNTU_MIRROR}" ]; then
          _MIRROR=archive.ubuntu.com
        else
          _MIRROR=${_LOCAL_UBUNTU_MIRROR}
        fi
      else
        if [ -z "${_LOCAL_UBUNTU_MIRROR}" ]; then
          msg "INFO: Now looking for the best/fastest ${_THIS_OS} mirror"
          msg "INFO: This may take a while, please wait..."
          hlpPth="/opt/tmp/boa/aegir/helpers"
          ffMirr=$(which ffmirror 2>&1)
          ffList="${hlpPth}/apt-list-ubuntu.txt"
          if [ -e "${ffMirr}" ] && [ -e "${ffList}" ]; then
            _MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
            _MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
            echo " "
            askThis="Enter your own mirror to use or press enter"
            askThis="${askThis} to use the fastest found mirror"
            prompt_confirm_choice "${askThis}" ${_MIRROR}
            echo " "
            _MIRROR=${_CONFIRMED_ANSWER}
          else
            _MIRROR=${_LOCAL_UBUNTU_MIRROR}
          fi
        else
          _MIRROR=${_LOCAL_UBUNTU_MIRROR}
        fi
        if ! netcat -w 5 -z ${_MIRROR} 80 ; then
          msg "INFO: The mirror ${_MIRROR} doesn't respond, let's try default"
          _MIRROR=archive.ubuntu.com
        fi
      fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: We will use ${_THIS_OS} mirror ${_MIRROR}"
      fi
      cd /var/opt
      echo "## MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_MIRROR}/ubuntu/ ${_OSV} main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/ubuntu/ ${_OSV} main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/ubuntu/ ${_OSV}-updates main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/ubuntu/ ${_OSV}-updates main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## BACKPORTS" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/ubuntu/ ${_OSV}-backports main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/ubuntu/ ${_OSV}-backports main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## UBUNTU SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://security.ubuntu.com/ubuntu ${_OSV}-security \
        main restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://security.ubuntu.com/ubuntu ${_OSV}-security \
        main restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      if [ -e "${locCnf}/etc-apt-preferences-ubuntu.txt" ]; then
        cp -af ${locCnf}/etc-apt-preferences-ubuntu.txt /etc/apt/preferences
      else
        curl ${crlGet} "${urlHmr}/conf/etc-apt-preferences-ubuntu.txt" \
          -o /etc/apt/preferences
      fi
    elif [ "${_THIS_OS}" = "Debian" ]; then
      _MIRROR_CHECK=NO
      if [ "${_OSV}" = "lenny" ]; then
        _MIRROR=archive.debian.org
      else
        if [ "${_AUTOPILOT}" = "YES" ]; then
          if [ -z "${_LOCAL_DEBIAN_MIRROR}" ]; then
            _MIRROR=ftp.debian.org
          else
            _MIRROR=${_LOCAL_DEBIAN_MIRROR}
          fi
        else
          _MIRROR_CHECK=YES
        fi
      fi
      if [ "${_MIRROR_CHECK}" = "YES" ]; then
        if [ -z "${_LOCAL_DEBIAN_MIRROR}" ]; then
          msg "INFO: Now looking for the best/fastest ${_THIS_OS} mirror"
          msg "INFO: This may take a while, please wait..."
          hlpPth="/opt/tmp/boa/aegir/helpers"
          ffMirr=$(which ffmirror 2>&1)
          ffList="${hlpPth}/apt-list-debian.txt"
          if [ -e "${ffMirr}" ] && [ -e "${ffList}" ]; then
            _MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
            _MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
            echo " "
            askThis="Enter your own mirror to use or press enter"
            askThis="${askThis} to use the fastest found mirror"
            prompt_confirm_choice "${askThis}" ${_MIRROR}
            echo " "
            _MIRROR=${_CONFIRMED_ANSWER}
          else
            _MIRROR=${_LOCAL_DEBIAN_MIRROR}
          fi
        else
          _MIRROR=${_LOCAL_DEBIAN_MIRROR}
        fi
        if ! netcat -w 5 -z ${_MIRROR} 80 ; then
          msg "INFO: The mirror ${_MIRROR} doesn't respond, let's try default"
          _MIRROR=ftp.debian.org
        fi
      fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: We will use ${_THIS_OS} mirror ${_MIRROR}"
      fi
      cd /var/opt
      echo "## MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_MIRROR}/debian/ ${_OSV} main contrib non-free" \
        >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/debian/ ${_OSV} main contrib non-free" \
        >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" \
        >> ${aptLiSys}
      if [ "${_OSV}" = "lenny" ]; then
        echo "deb http://archive.debian.org/debian-volatile \
          ${_OSV}/volatile main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
        echo "deb-src http://archive.debian.org/debian-volatile \
          ${_OSV}/volatile main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      else
        echo "deb http://${_MIRROR}/debian/ ${_OSV}-updates main" \
          >> ${aptLiSys}
        echo "deb-src http://${_MIRROR}/debian/ ${_OSV}-updates main" \
          >> ${aptLiSys}
        echo "" >> ${aptLiSys}
        echo "## DEBIAN SECURITY UPDATES" >> ${aptLiSys}
        echo "deb http://security.debian.org/ ${_OSV}/updates main \
          contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
        echo "deb-src http://security.debian.org/ ${_OSV}/updates main \
          contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
        echo "" >> ${aptLiSys}
        echo "## DEBIAN PROPOSED UPDATES" >> ${aptLiSys}
        echo "deb http://${_MIRROR}/debian/ ${_OSV}-proposed-updates main" \
          >> ${aptLiSys}
        if [ "${_OSV}" = "wheezy" ]; then
          if [ -e "${locCnf}/etc-apt-preferences-wheezy.txt" ]; then
            cp -af ${locCnf}/etc-apt-preferences-wheezy.txt /etc/apt/preferences
          else
            curl ${crlGet} "${urlHmr}/conf/etc-apt-preferences-wheezy.txt" \
              -o /etc/apt/preferences
          fi
        fi
        if [ "${_OSV}" = "squeeze" ]; then
          echo "" >> ${aptLiSys}
          echo "## DEBIAN LTS UPDATES" >> ${aptLiSys}
          echo "deb http://${_MIRROR}/debian/ ${_OSV}-lts main \
            contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
          echo "deb-src http://${_MIRROR}/debian/ ${_OSV}-lts main \
            contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
          if [ -e "/etc/apt/apt.conf" ]; then
            sed -i "s/APT::Default-Release \"squeeze\";/APT::Default-Release \"squeeze-lts\";/g" \
              /etc/apt/apt.conf &> /dev/null
          fi
          if [ -e "${locCnf}/etc-apt-preferences-squeeze.txt" ]; then
            cp -af ${locCnf}/etc-apt-preferences-squeeze.txt /etc/apt/preferences
          else
            curl ${crlGet} "${urlHmr}/conf/etc-apt-preferences-squeeze.txt" \
              -o /etc/apt/preferences
          fi
        fi
      fi
    fi
    mkdir -p ${pthLog}
    touch ${pthLog}/apt-fast-install-log.txt
    cd /var/opt
  fi
  if [ ! -e "/etc/apt/preferences" ]; then
    if [ "${_THIS_OS}" = "Ubuntu" ]; then
      if [ -e "${locCnf}/etc-apt-preferences-ubuntu.txt" ]; then
        cp -af ${locCnf}/etc-apt-preferences-ubuntu.txt /etc/apt/preferences
      else
        curl ${crlGet} "${urlHmr}/conf/etc-apt-preferences-ubuntu.txt" \
          -o /etc/apt/preferences
      fi
    else
      if [ "${_OSV}" = "wheezy" ]; then
        if [ -e "${locCnf}/etc-apt-preferences-wheezy.txt" ]; then
          cp -af ${locCnf}/etc-apt-preferences-wheezy.txt /etc/apt/preferences
        else
          curl ${crlGet} "${urlHmr}/conf/etc-apt-preferences-wheezy.txt" \
            -o /etc/apt/preferences
        fi
      else
        if [ -e "${locCnf}/etc-apt-preferences-squeeze.txt" ]; then
          cp -af ${locCnf}/etc-apt-preferences-squeeze.txt /etc/apt/preferences
        else
          curl ${crlGet} "${urlHmr}/conf/etc-apt-preferences-squeeze.txt" \
            -o /etc/apt/preferences
        fi
      fi
    fi
  fi
}

#
# Install OpenSSH from sources.
install_ssh_src() {
  _SSH_GET_DPKG=$(dpkg --get-selections | grep ssh | grep hold 2>&1)
  _SSH_INSTALL_REQUIRED=NO
  _SSH_ITD=$(ssh -V 2>&1 \
    | tr -d "\n" \
    | tr -d "," \
    | cut -d"_" -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "$_SSH_FORCE_REINSTALL" = "YES" ]; then
    _SSH_INSTALL_REQUIRED=YES
    msg "INFO: OpenSSH $_SSH_ITD, rebuild forced"
  elif [ "$_SSH_ITD" = "${_OPENSSH_VRN}" ]; then
    _DO_NOTHING=YES
  else
    _SSH_INSTALL_REQUIRED=YES
    msg "INFO: Installed OpenSSH version $_SSH_ITD, upgrade required"
  fi
  if [ "$_SSH_INSTALL_REQUIRED" = "YES" ]; then
    msg "INFO: Building OpenSSH ${_OPENSSH_VRN} from sources, please wait..."
    cd /var/opt
    rm -f -r openssh*
    get_dev_src "openssh-${_OPENSSH_VRN}.tar.gz"
    cd /var/opt/openssh-${_OPENSSH_VRN}
    st_runner "sh ./configure --without-openssl-header-check --prefix=/usr \
      --with-pam" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "make --quiet install" 2> /dev/null
    mrun "service ssh restart" &> /dev/null
    if [[ ! "$_SSH_GET_DPKG" =~ "hold" ]]; then
      aptitude hold openssh-server &> /dev/null
      aptitude hold openssh-client &> /dev/null
      aptitude hold ssh &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections &> /dev/null
      echo "openssh-client hold" | dpkg --set-selections &> /dev/null
      echo "ssh hold" | dpkg --set-selections &> /dev/null
    fi
  else
    if [[ ! "$_SSH_GET_DPKG" =~ "hold" ]]; then
      aptitude hold openssh-server &> /dev/null
      aptitude hold openssh-client &> /dev/null
      aptitude hold ssh &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections &> /dev/null
      echo "openssh-client hold" | dpkg --set-selections &> /dev/null
      echo "ssh hold" | dpkg --set-selections &> /dev/null
    fi
  fi
  _SSH_FORCE_REINSTALL=NO
}

#
# Install cURL from sources.
install_curl_src() {
  _CURL_INSTALL_REQUIRED=NO
  _CURL_GET_DPKG=$(dpkg --get-selections | grep curl | grep hold 2>&1)
  _CURL_ITD=$(curl --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  _CURL_SSL_ITD=$(curl --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f5 \
    | awk '{ print $1}' \
    | cut -d"/" -f2 \
    | awk '{ print $1}' 2>&1)
  _CURL_LIB_ITD=$(curl --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f4 \
    | awk '{ print $1}' \
    | cut -d"/" -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_CURL_ITD}" = "${_CURL_VRN}" ]; then
    if [ "$_CURL_SSL_ITD" = "${_OPENSSL_VRN}" ]; then
      _CURL_INSTALL_REQUIRED=NO
    else
      if [ "${_OSV}" = "wheezy" ] \
        || [ "${_OSV}" = "trusty" ] \
        || [ "${_OSV}" = "precise" ]; then
        _DO_NOTHING=YES
      else
        _CURL_INSTALL_REQUIRED=YES
        msg "INFO: Installed cURL ${_CURL_ITD} with OpenSSL $_CURL_SSL_ITD"
        msg "INFO: cURL rebuild will be forced"
      fi
    fi
  else
    if [ "${_OSV}" = "wheezy" ] \
      || [ "${_OSV}" = "trusty" ] \
      || [ "${_OSV}" = "precise" ]; then
      _DO_NOTHING=YES
    else
      _CURL_INSTALL_REQUIRED=YES
      msg "INFO: Installed cURL version ${_CURL_ITD}, upgrade required"
    fi
  fi
  _BROKEN_CURL_TEST=$(curl --version 2>&1)
  if [[ "${_BROKEN_CURL_TEST}" =~ "libcurl.so.4" ]]; then
    _CURL_INSTALL_REQUIRED=YES
    msg "INFO: Installed libcurl is broken, cURL ${_CURL_ITD} upgrade required"
  fi
  if [ "${_PHP_BIN_BROKEN}" = "YES" ] && [ -z "$_CURL_ALREADY_REBUILT" ]; then
    _CURL_INSTALL_REQUIRED=YES
  fi
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _CURL_INSTALL_REQUIRED=YES
    msg "INFO: Installed cURL version ${_CURL_ITD}, rebuild forced"
  fi
  if [ "${_OSV}" = "wheezy" ] \
    || [ "${_OSV}" = "trusty" ] \
    || [ "${_OSV}" = "precise" ]; then
    _CURL_INSTALL_REQUIRED=NO
  fi
  if [ "$_CURL_INSTALL_REQUIRED" = "YES" ]; then
    ###--------------------###
    if [[ ! "${_CURL_GET_DPKG}" =~ "hold" ]]; then
      echo "libcurl3 install" | dpkg --set-selections &> /dev/null
      echo "libcurl3-gnutls install" | dpkg --set-selections &> /dev/null
      echo "libcurl4-openssl-dev install" | dpkg --set-selections &> /dev/null
      aptitude install libcurl3 -y &> /dev/null
      aptitude install libcurl3-gnutls -y &> /dev/null
      aptitude install libcurl4-openssl-dev -y &> /dev/null
      echo "curl hold" | dpkg --set-selections &> /dev/null
      aptitude hold curl &> /dev/null
    fi
    msg "INFO: Building cURL ${_CURL_VRN} from sources, please wait..."
    cd /var/opt
    rm -f -r curl*
    get_dev_src "curl-${_CURL_VRN}.tar.gz"
    cd /var/opt/curl-${_CURL_VRN}
    st_runner "sh ./configure --prefix=/usr" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "make --quiet install" 2> /dev/null
    _CURL_ALREADY_REBUILT=YES
    _UP_PHP=YES
  else
    ###--------------------###
    if [ "${_OSV}" = "wheezy" ] \
      || [ "${_OSV}" = "trusty" ] \
      || [ "${_OSV}" = "precise" ]; then
      if [ "${_CURL_ITD}" = "${_CURL_LIB_ITD}" ]; then
        _DO_NOTHING=YES
      else
        if [ "${_OSV}" = "trusty" ] \
          || [ "${_OSV}" = "precise" ]; then
          apt-mark unhold curl &> /dev/null
        fi
        if [[ "${_CURL_GET_DPKG}" =~ "hold" ]]; then
          echo "curl install" | dpkg --set-selections &> /dev/null
          apt-get install curl -y --force-yes --reinstall &> /dev/null
        fi
      fi
    else
      if [[ ! "${_CURL_GET_DPKG}" =~ "hold" ]]; then
        echo "libcurl3 install" | dpkg --set-selections &> /dev/null
        echo "libcurl3-gnutls install" | dpkg --set-selections &> /dev/null
        echo "libcurl4-openssl-dev install" | dpkg --set-selections &> /dev/null
        aptitude install libcurl3 -y &> /dev/null
        aptitude install libcurl3-gnutls -y &> /dev/null
        aptitude install libcurl4-openssl-dev -y &> /dev/null
        echo "curl hold" | dpkg --set-selections &> /dev/null
        aptitude hold curl &> /dev/null
      fi
    fi
  fi
}

#
# Install OpenSSL from sources.
install_ssl_src() {
  _SSL_INSTALL_REQUIRED=NO
  _SSL_GET_DPKG=$(dpkg --get-selections \
    | grep openssl \
    | grep hold 2>&1)
  _SSL_ITD=$(openssl version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_SSL_ITD}" = "${_OPENSSL_VRN}" ]; then
    _SPDY_COMPATIBILITY_TEST=$(service nginx configtest 2>&1)
    if [[ "$_SPDY_COMPATIBILITY_TEST" =~ "without OpenSSL ALPN or NPN" ]]; then
      _SSL_FORCE_REINSTALL=YES
    fi
    if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_SSL_FORCE_REINSTALL}" = "YES" ]; then
      _SSL_INSTALL_REQUIRED=YES
      _SSH_FORCE_REINSTALL=YES
      _NGX_FORCE_REINSTALL=YES
      _PHP_FORCE_REINSTALL=YES
      _GIT_FORCE_REINSTALL=YES
      rm -f ${pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_X_VERSION}.log
      rm -f ${pthLog}/mss-build-${_MSS_VRN}-${_X_VERSION}.log
      msg "INFO: Installed OpenSSL version ${_SSL_ITD}, rebuild forced"
    else
      _DO_NOTHING=YES
      _SSH_FORCE_REINSTALL=NO
    fi
  else
    _SSL_INSTALL_REQUIRED=YES
    _SSH_FORCE_REINSTALL=YES
    _NGX_FORCE_REINSTALL=YES
    _PHP_FORCE_REINSTALL=YES
    _GIT_FORCE_REINSTALL=YES
    rm -f ${pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_X_VERSION}.log
    rm -f ${pthLog}/mss-build-${_MSS_VRN}-${_X_VERSION}.log
    msg "INFO: Installed OpenSSL version ${_SSL_ITD}, upgrade required"
  fi
  if [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    ###--------------------###
    msg "INFO: Building zlib ${_ZLIB_VRN} from sources, please wait..."
    cd /var/opt
    rm -f -r zlib*
    get_dev_src "zlib-${_ZLIB_VRN}.tar.gz"
    cd /var/opt/zlib-${_ZLIB_VRN}
    st_runner "./configure --prefix=/usr" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "make --quiet install" 2> /dev/null
    ###--------------------###
    msg "INFO: Building OpenSSL ${_OPENSSL_VRN} from sources, please wait..."
    cd /var/opt
    rm -f -r openssl*
    get_dev_src "openssl-${_OPENSSL_VRN}.tar.gz"
    cd /var/opt/openssl-${_OPENSSL_VRN}
    _X86_64_IF=$(uname -m 2>&1)
    if [ "$_X86_64_IF" = "x86_64" ]; then
      st_runner "sh ./config --prefix=/usr zlib-dynamic --openssldir=/etc/ssl \
        shared enable-ec_nistp_64_gcc_128" 2> /dev/null
      st_runner "make depend" 2> /dev/null
    else
      st_runner "sh ./config --prefix=/usr zlib-dynamic --openssldir=/etc/ssl \
        shared" 2> /dev/null
    fi
    st_runner "make --quiet" 2> /dev/null
    st_runner "make --quiet install" 2> /dev/null
    ###--------------------###
    if [[ ! "$_SSL_GET_DPKG" =~ "hold" ]]; then
      aptitude install libssl-dev -y &> /dev/null
      aptitude hold openssl &> /dev/null
      aptitude hold zlibc &> /dev/null
      aptitude hold zlib1g &> /dev/null
      aptitude hold zlib1g-dev &> /dev/null
      echo "libssl-dev install" | dpkg --set-selections &> /dev/null
      echo "openssl hold" | dpkg --set-selections &> /dev/null
      echo "zlibc hold" | dpkg --set-selections &> /dev/null
      echo "zlib1g hold" | dpkg --set-selections &> /dev/null
      echo "zlib1g-dev hold" | dpkg --set-selections &> /dev/null
    fi
  else
    if [[ ! "$_SSL_GET_DPKG" =~ "hold" ]]; then
      aptitude install libssl-dev -y &> /dev/null
      aptitude hold openssl &> /dev/null
      aptitude hold zlibc &> /dev/null
      aptitude hold zlib1g &> /dev/null
      aptitude hold zlib1g-dev &> /dev/null
      echo "libssl-dev install" | dpkg --set-selections &> /dev/null
      echo "openssl hold" | dpkg --set-selections &> /dev/null
      echo "zlibc hold" | dpkg --set-selections &> /dev/null
      echo "zlib1g hold" | dpkg --set-selections &> /dev/null
      echo "zlib1g-dev hold" | dpkg --set-selections &> /dev/null
    fi
  fi
}

#
# Symlink to dash.
symlink_to_dash() {
  if [ -x "/bin/dash" ]; then
    rm -f /bin/sh
    ln -s /bin/dash /bin/sh
  fi
}

#
# Symlink to bash.
symlink_to_bash() {
  if [ -x "/bin/bash" ]; then
    rm -f /bin/sh
    ln -s /bin/bash /bin/sh
  fi
}

#
# Switch to dash.
switch_to_dash() {
  if [ -x "/bin/dash" ]; then
    sed -i "s/:\/bin\/sh/:\/bin\/dash/g"  /etc/passwd &> /dev/null
    sed -i "s/\/bin\/sh/\/bin\/dash/g" /etc/crontab &> /dev/null
    _X_BIN_PATHS="/bin \
                  /etc/alternatives \
                  /etc/cron.d \
                  /etc/cron.daily \
                  /etc/cron.monthly \
                  /etc/cron.weekly \
                  /etc/init.d \
                  /etc/network/if-down.d \
                  /etc/network/if-up.d \
                  /etc/resolvconf \
                  /etc/webmin \
                  /opt/php53/bin \
                  /opt/php54/bin \
                  /opt/php55/bin \
                  /opt/php56/bin \
                  /sbin \
                  /usr/bin \
                  /usr/lib/ConsoleKit/run-session.d \
                  /usr/lib/git-core \
                  /usr/lib/postfix \
                  /usr/lib/sysstat \
                  /usr/local/bin \
                  /usr/local/libexec/git-core \
                  /usr/local/sbin \
                  /usr/sbin"
    for p in $_X_BIN_PATHS; do
      if [ -e "$p" ]; then
        for f in `find $p ! -perm -4000 ! -perm -2000 -type f`; do
          if [[ "$f" =~ "drush"($) ]] \
            || [[ "$f" =~ "clean-boa-env"($) ]] \
            || [[ "$f" =~ "websh"($) ]]; then
            _SKIP_THIS=YES
          else
            _SHELL_TEST=$(grep -I -o "/bin/sh" $f 2>&1)
            if [ ! -z "$_SHELL_TEST" ] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/^#\! \/.*/#\!\/bin\/dash/g" $f &> /dev/null
              sed -i "s/\/bin\/sh/\/bin\/dash/g" $f &> /dev/null
            fi
          fi
        done
      fi
    done
  fi
}

#
# Switch to bash.
switch_to_bash() {
  if [ -x "/bin/bash" ]; then
    sed -i "s/:\/bin\/sh/:\/bin\/bash/g"  /etc/passwd &> /dev/null
    sed -i "s/\/bin\/sh/\/bin\/bash/g" /etc/crontab &> /dev/null
    _X_BIN_PATHS="/bin \
                  /etc/alternatives \
                  /etc/cron.d \
                  /etc/cron.daily \
                  /etc/cron.monthly \
                  /etc/cron.weekly \
                  /etc/init.d \
                  /etc/network/if-down.d \
                  /etc/network/if-up.d \
                  /etc/resolvconf \
                  /etc/webmin \
                  /opt/php53/bin \
                  /opt/php54/bin \
                  /opt/php55/bin \
                  /opt/php56/bin \
                  /sbin \
                  /usr/bin \
                  /usr/lib/ConsoleKit/run-session.d \
                  /usr/lib/git-core \
                  /usr/lib/postfix \
                  /usr/lib/sysstat \
                  /usr/local/bin \
                  /usr/local/libexec/git-core \
                  /usr/local/sbin \
                  /usr/sbin"
    for p in $_X_BIN_PATHS; do
      if [ -e "$p" ]; then
        for f in `find $p ! -perm -4000 ! -perm -2000 -type f`; do
          if [[ "$f" =~ "drush"($) ]] \
            || [[ "$f" =~ "clean-boa-env"($) ]] \
            || [[ "$f" =~ "websh"($) ]]; then
            _SKIP_THIS=YES
          else
            _SHELL_TEST=$(grep -I -o "/bin/sh" $f 2>&1)
            if [ ! -z "$_SHELL_TEST" ] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/^#\! \/.*/#\!\/bin\/bash/g" $f &> /dev/null
              sed -i "s/\/bin\/sh/\/bin\/bash/g" $f &> /dev/null
            fi
          fi
        done
      fi
    done
  fi
}

#
# Strict Permissions on All Binaries.
strict_bin_permissions() {

  _BIN_PATHS="/bin \
              /etc/alternatives \
              /opt/php53/bin \
              /opt/php54/bin \
              /opt/php55/bin \
              /opt/php56/bin \
              /sbin \
              /usr/bin \
              /usr/local/bin \
              /usr/local/sbin \
              /usr/sbin"

  for p in $_BIN_PATHS; do
    if [ -e "$p" ]; then
      chown root:root $p &> /dev/null
      chmod 711 $p &> /dev/null
    fi
  done
  for p in $_BIN_PATHS; do
    if [ -e "$p" ]; then
      for f in `find $p -group users ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp root $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in $_BIN_PATHS; do
    if [ -e "$p" ]; then
      for f in `find $p -group lshellg ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp root $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in $_BIN_PATHS; do
    if [ -e "$p" ]; then
      for f in `find $p -group www-data ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp root $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in $_BIN_PATHS; do
    if [ -e "$p" ]; then
      for f in `find $p -group root ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp users $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in $_BIN_PATHS; do
    if [ -e "$p" ]; then
      for f in `find $p -group staff ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp users $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done

  _WEBSERVER_BIN_PATHS="/bin \
                        /etc/alternatives \
                        /sbin \
                        /usr/bin \
                        /usr/local/bin \
                        /usr/local/sbin \
                        /usr/sbin"
  for p in ${_WEBSERVER_BIN_PATHS}; do
    for f in `find $p ! -perm -4000 ! -perm -2000 -type f | grep pdf`; do
      if [ -e "$f" ]; then
        chgrp root $f &> /dev/null
        chmod 755 $f &> /dev/null
      fi
    done
  done

  _BACKEND_ITEMS="advdef \
                  advpng \
                  avconv \
                  bash \
                  compass \
                  convert \
                  curl \
                  dash \
                  env \
                  ffmpeg \
                  flvtool2 \
                  git \
                  gs \
                  hhvm \
                  id \
                  java \
                  java6 \
                  java7 \
                  jpegoptim \
                  jpegtran \
                  logger \
                  newrelic-daemon \
                  nrsysmond \
                  pngcrush \
                  pngquant \
                  redis-server \
                  rrdtool \
                  sass \
                  sass-convert \
                  scss \
                  sendmail \
                  wget \
                  which \
                  wkhtmltoimage \
                  wkhtmltopdf"
  if [ ! -z "${_BACKEND_ITEMS_LIST}" ]; then
    _BACKEND_ITEMS="${_BACKEND_ITEMS} ${_BACKEND_ITEMS_LIST}"
  fi
  for i in ${_BACKEND_ITEMS}; do
    _BIN_ITEM=$(which $i 2>&1)
    if [ -e "$_BIN_ITEM" ]; then
      chgrp root $_BIN_ITEM &> /dev/null
      chmod 755 $_BIN_ITEM &> /dev/null
    fi
  done

  _PROTECTED_ITEMS="backboa \
                    barracuda \
                    boa \
                    named \
                    octopus \
                    redis-benchmark \
                    redis-check-aof \
                    redis-check-dump \
                    redis-cli \
                    sftp-admin \
                    sftp-kill \
                    sftp-state \
                    syncpass"
  for i in ${_PROTECTED_ITEMS}; do
    _BIN_ITEM=$(which $i 2>&1)
    if [ -e "$_BIN_ITEM" ]; then
      chown root:root $_BIN_ITEM &> /dev/null
      chmod 700 $_BIN_ITEM &> /dev/null
    fi
  done

  cp -af ${bldPth}/aegir/helpers/websh.sh.txt /bin/websh
  chmod 755 /bin/websh
  chown root:root /bin/websh
  chown root:root /etc/passwd
  chmod 644 /etc/passwd
}

#
# Final cleanup.
finale() {
  ###--------------------###
  if [ "${_STATUS}" = "INIT" ]; then
    _L_ST="install"
    touch ${pthLog}/SA-CORE-2014-005-fixed-d7.log
  else
    _L_ST="upgrade"
  fi
  msg "CARD: Now charging your credit card for this magic show..."
  mrun "sleep 5"
  msg "CARD: Thank you for entering your correct PIN code..."
  mrun "sleep 5"
  msg "CARD: It will take a moment to process your payment..."
  mrun "sleep 8"
  msg "JOKE: Just kidding !!! Enjoy your Aegir Hosting System :)"
  mrun "sleep 5"
  echo " "
  if [ "$_UP_LNX" = "YES" ]; then
    msg "ALRT! Your OS kernel has been upgraded!"
    if [ ! -e "/usr/sbin/uptrack-upgrade" ]; then
      msg "ALRT! You *must* reboot immediately to stay secure!"
    else
      msg "NOTE: You have Ksplice rebootless kernel updates installed"
      msg "HINT: It is recommened to run the uptrack-upgrade -y command"
    fi
    echo " "
    mrun "sleep 8"
  fi
  msg "Final post-${_L_ST} cleaning, one moment..."
  fix_core_dgd
  mv -f /etc/motd ${vBs}/dragon/t/motd-pre-${_X_VERSION}-${_NOW} &> /dev/null
  mv -f /etc/motd-pre-* ${vBs}/dragon/t/ &> /dev/null
  echo > /etc/motd
  echo " Barracuda System managed by Skynet Agent v.${_X_VERSION} \
    welcomes you aboard" | fmt -su -w 2500 >> /etc/motd
  echo >> /etc/motd
  echo > /etc/motd.tail
  echo " Barracuda System managed by Skynet Agent v.${_X_VERSION} \
    welcomes you aboard" | fmt -su -w 2500 >> /etc/motd.tail
  echo >> /etc/motd.tail
  aptitude autoclean -y &> /dev/null
  apt-get clean -qq &> /dev/null
  mkdir -p /data/conf/arch
  mv -f /data/conf/global.inc-pre* /data/conf/arch/     &> /dev/null
  mv -f /data/conf/global.inc-before* /data/conf/arch/  &> /dev/null
  mv -f /data/conf/global.inc-missing* /data/conf/arch/ &> /dev/null
  rm -f /tmp/cache.inc*
  rm -f /var/opt/._zendopcache*
  rm -f -r /var/opt/*
  rm -f -r /opt/tmp/*
  rm -f /var/xdrago/monitor/acrashsql.sh
  rm -f /var/xdrago/acrashsql.sh
  rm -f /var/xdrago/usage.sh
  rm -f /var/xdrago/memcache.sh*
  rm -f /var/xdrago/purge_cruft.sh
  rm -f -r /tmp/drush_make_tmp*
  rm -f -r /tmp/make_tmp*
  rm -f /tmp/pm-updatecode*
  rm -f -r /var/aegir/.tmp/cache
  rm -f /var/run/boa_run.pid
  rm -f /var/run/boa_wait.pid
  rm -f /var/run/manage_ltd_users.pid
  rm -f /var/run/manage_rvm_users.pid
  rm -f /var/aegir/.drush/.alias.drushrc.php
  rm -f /data/disk/*/.drush/.alias.drushrc.php
  rm -f ${pthLog}/protected-vhosts-clean.log
  rm -f ${vBs}/.auth.IP.list*
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${mtrNgx}/vhost.d/chive.* &> /dev/null
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${mtrNgx}/vhost.d/cgp.* &> /dev/null
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${mtrNgx}/vhost.d/sqlbuddy.* &> /dev/null
  find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
  chmod 700 /root
  if [ ! -e "/etc/init.d/buagent" ] \
    && [ -e "${vBs}/buagent-pre-${_X_VERSION}-${_NOW}" ]; then
    mv -f ${vBs}/buagent-pre-${_X_VERSION}-${_NOW} \
      /etc/init.d/buagent &> /dev/null
  fi
  if [ -e "/etc/csf/csf.deny" ] \
    && [ -e "/usr/sbin/csf" ] \
    && [ -e "/var/xdrago/guest-fire.sh" ] \
    && [ -e "/var/xdrago/guest-water.sh" ]; then
    sed -i "s/.*fire.*//g" /etc/crontab &> /dev/null
    sed -i "s/.*water.*//g" /etc/crontab &> /dev/null
    if [[ "${_THISHOST}" =~ ".host8." ]]; then
      if [ "${_VMFAMILY}" = "VS" ]; then
        _DO_NOTHING=YES
      else
        echo "*  *    * * *   root    bash /var/xdrago/guest-fire.sh >/dev/null 2>&1"  >> /etc/crontab
        echo "01 *    * * *   root    bash /var/xdrago/guest-water.sh >/dev/null 2>&1" >> /etc/crontab
      fi
    else
      echo "*  *    * * *   root    bash /var/xdrago/guest-fire.sh >/dev/null 2>&1"  >> /etc/crontab
      echo "01 *    * * *   root    bash /var/xdrago/guest-water.sh >/dev/null 2>&1" >> /etc/crontab
    fi
    sed -i "/^$/d" /etc/crontab &> /dev/null
  else
    sed -i "s/.*fire.*//g" /etc/crontab &> /dev/null
    sed -i "s/.*water.*//g" /etc/crontab &> /dev/null
    sed -i "/^$/d" /etc/crontab &> /dev/null
  fi
  if [ -e "/root/.dbhd.clstr.cnf" ]; then
    service clean-boa-env stop &> /dev/null
  fi
  killall -9 memcached     &> /dev/null
  chmod 0750 /sbin/audispd &> /dev/null
  service auditd restart   &> /dev/null
  php_single_initd_cleanup
  if [ ! -e "/root/.upstart.cnf" ]; then
    service cron start     &> /dev/null
  fi
  if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    csf -x &> /dev/null
    csf -e &> /dev/null
    csf -q &> /dev/null
  fi
  cd /
  chmod 711 bin boot data dev emul etc home lib lib64 lib32 media mnt opt \
    sbin selinux srv sys usr var share run &> /dev/null
  chmod 700 root &> /dev/null
  msg "BYE!"
}
