
if_running_as_root_barracuda() {
  if [ `whoami` = "root" ]; then
    chmod a+w /dev/null
    if [ ! -e "/dev/fd" ]; then
      if [ -e "/proc/self/fd" ]; then
        rm -rf /dev/fd
        ln -s /proc/self/fd /dev/fd
      fi
    fi
    chmod a+rw /dev/null
    rm -f -r /tmp/drush_make_tmp*
    rm -f -r /tmp/make_tmp*
    rm -f /tmp/pm-updatecode*
    rm -f /tmp/cache.inc*
    if [ ! -e "/root/.upstart.cnf" ]; then
      service cron stop &> /dev/null
    fi
    touch /var/run/boa_run.pid
    mkdir -p ${pthLog}
    find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
    _AWS_TEST_A=$(grep cloudimg /etc/fstab 2>&1)
    _AWS_TEST_B=$(grep cloudconfig /etc/fstab 2>&1)
    if [[ "${_AWS_TEST_A}" =~ "cloudimg" ]] \
      || [[ "${_AWS_TEST_B}" =~ "cloudconfig" ]]; then
      _VMFAMILY="AWS"
    fi
    _VM_TEST=$(uname -a 2>&1)
    if [[ "${_VM_TEST}" =~ "3.6.14-beng" ]] \
      || [ -e "/root/.debug.cnf" ] \
      || [[ "${_VM_TEST}" =~ "3.6.15-beng" ]]; then
      _VMFAMILY="VS"
      touch /var/run/cloud_vhost.pid
      if [ -d "/etc/webmin" ]; then
        mrun "dpkg --configure -a" &> /dev/null
        mrun "apt-get clean -qq"   &> /dev/null
        mrun "apt-get update -qq"  &> /dev/null
        mrun "apt-get remove webmin -y --force-yes -qq" &> /dev/null
        mrun "apt-get purge webmin -y --force-yes -qq"  &> /dev/null
        mrun "apt-get autoremove -y --force-yes -qq"    &> /dev/null
        rm -f -r /usr/share/webmin
      fi
      rm -f ${aptLiSys}.d/ksplice.list
      rm -f ${aptLiSys}.d/longview.list
      rm -f ${aptLiSys}.d/webmin.list
    fi
    sleep 1
  else
    msg "ERROR: This script should be ran as a root user"
    clean_pid_exit
  fi
}

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
  if [[ "${_L_VM_TEST}" =~ "3.6.14-beng" ]] \
    || [ -e "/root/.debug.cnf" ] \
    || [[ "${_L_VM_TEST}" =~ "3.6.15-beng" ]]; then
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
    || [ ! -e "/usr/bin/mysecureshell" ] \
    || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Installing MySecureShell ${_MSS_VRN}..."
    cd /var/opt
    rm -f -r mysecureshell*
    get_dev_src "mysecureshell-${_MSS_VRN}.tar.gz"
    cd /var/opt/mysecureshell
    st_runner "sh ./configure" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "sh ./install.sh yesall" 2> /dev/null
    touch ${pthLog}/mss-build-${_MSS_VRN}-${_X_VERSION}.log
    cp -af ${locCnf}/sftp_config /etc/ssh/sftp_config
    mrun "service ssh restart" &> /dev/null
  fi
  if [ -e "/usr/bin/mysecureshell" ] && [ -e "/etc/ssh/sftp_config" ]; then
    _MSS_TEST=$(grep "lshell" /etc/passwd 2>&1)
    if [[ "$_MSS_TEST" =~ "lshell" ]]; then
      sed -i "s/usr\/.*\/lshell/usr\/bin\/mysecureshell/g" /etc/passwd &> /dev/null
    fi
    _MSS_TEST=$(grep "MySecureShell" /etc/passwd 2>&1)
    if [[ "$_MSS_TEST" =~ "MySecureShell" ]]; then
      sed -i "s/usr\/.*\/MySecureShell/usr\/bin\/mysecureshell/g" /etc/passwd &> /dev/null
    fi
  fi
  _MSS_PATH_TEST=$(grep "/usr/bin/mysecureshell" /etc/shells 2>&1)
  if [[ "$_MSS_PATH_TEST" =~ "/usr/bin/mysecureshell" ]]; then
    _DO_NOTHING=YES
  else
    echo "/usr/bin/mysecureshell" >> /etc/shells
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
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
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
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
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
  else
    _VMFAMILY="XEN"
  fi
  if [[ "${_VM_TEST}" =~ "3.6.14-beng" ]] \
    || [ -e "/root/.debug.cnf" ] \
    || [[ "${_VM_TEST}" =~ "3.6.15-beng" ]]; then
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
  if [ "${_VMFAMILY}" = "VS" ] \
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
    || [[ "${_THISHOST}" =~ ".host8." ]]; then
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
    _QCE_SQL=128M
    _RND_SQL=8M
    _JBF_SQL=4M
    if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
      _L_PHP_FPM_WORKERS=24
    else
      _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
    fi
    _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 2 ))
    if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
      _L_NGX_WRKS=$_CPU_MX
    else
      _L_NGX_WRKS=${_NGINX_WORKERS}
    fi
  elif [ "${_USE}" -ge "1024" ]; then
    if [ "${_VMFAMILY}" = "XEN" ] || [ "${_VMFAMILY}" = "AWS" ]; then
      _USE_PHP=1024
      _USE_OPC=1024
      _QCE_SQL=128M
      _RND_SQL=8M
      _JBF_SQL=4M
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _L_PHP_FPM_WORKERS=48
      else
        _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
      fi
      _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 2 ))
      if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
        _L_NGX_WRKS=$_CPU_MX
      else
        _L_NGX_WRKS=${_NGINX_WORKERS}
      fi
    elif [ "${_VMFAMILY}" = "VS" ] || [ "${_VMFAMILY}" = "TG" ]; then
      if [ -e "/boot/grub/grub.cfg" ] \
        || [ -e "/boot/grub/menu.lst" ] \
        || [ -e "/root/.tg.cnf" ]; then
        _USE_PHP=2048
        _USE_OPC=2048
        _QCE_SQL=256M
        _RND_SQL=8M
        _JBF_SQL=4M
        if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
          _L_PHP_FPM_WORKERS=48
        else
          _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
        fi
        _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 2 ))
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
        _QCE_SQL=64M
        _RND_SQL=2M
        _JBF_SQL=2M
        if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
          _L_PHP_FPM_WORKERS=24
        else
          _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
        fi
        _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 2 ))
        if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
          _L_NGX_WRKS=${_CPU_VS}
        else
          _L_NGX_WRKS=${_NGINX_WORKERS}
        fi
      fi
    else
      _USE_PHP=256
      _USE_OPC=256
      _QCE_SQL=32M
      _RND_SQL=2M
      _JBF_SQL=2M
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _L_PHP_FPM_WORKERS=24
      else
        _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
      fi
      _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 2 ))
      if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
        _L_NGX_WRKS=$_CPU_MX
      else
        _L_NGX_WRKS=${_NGINX_WORKERS}
      fi
    fi
  else
    _USE_PHP="${_USE}"
    _USE_OPC="${_USE}"
    _QCE_SQL=32M
    _RND_SQL=1M
    _JBF_SQL=1M
    if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
      _L_PHP_FPM_WORKERS=6
    else
      _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
    fi
    _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 2 ))
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
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms8m ${_USE_JETTY} -Djava.awt.headless=true -Dsolr.solr.home=\/opt\/solr4 \$JAVA_OPTIONS\" # Options/g" /etc/default/jetty9
  fi
  if [ -e "/etc/default/jetty8" ] && [ -e "/opt/solr3" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms8m ${_USE_JETTY} -Djava.awt.headless=true -Dsolr.solr.home=\/opt\/solr3 \$JAVA_OPTIONS\" # Options/g" /etc/default/jetty8
  fi
  if [ -e "/etc/default/jetty7" ] && [ -e "/opt/solr1" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms8m ${_USE_JETTY} -Djava.awt.headless=true -Dsolr.solr.home=\/opt\/solr1 \$JAVA_OPTIONS\" # Options/g" /etc/default/jetty7
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
  if [[ "$_LOC_TEST" =~ LANG=.*UTF-8 ]]; then
    _LOCALE_TEST=OK
  fi
  if [[ "$_LOC_TEST" =~ "Cannot" ]]; then
    _LOCALE_TEST=BROKEN
  fi
  if [ "${_LOCALE_TEST}" = "BROKEN" ]; then
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
        || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        || [ "${_VMFAMILY}" = "VS" ]; then
        if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
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
      || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
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
        sed -i "s/^_PHP_GEOS=.*/_PHP_GEOS=NO/g"                                    ${barCnf}
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
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
          || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
          || [ "${_VMFAMILY}" = "VS" ]; then
          if [ "${_VMFAMILY}" = "VS" ]; then
            sed -i "s/^_CPU_CRIT_RATIO=.*/_CPU_CRIT_RATIO=3/g"                     ${barCnf}
            sed -i "s/^_CPU_MAX_RATIO=.*/_CPU_MAX_RATIO=2/g"                       ${barCnf}
            sed -i "s/^_CPU_SPIDER_RATIO=.*/_CPU_SPIDER_RATIO=1/g"                 ${barCnf}
            sed -i "s/^_PHP_GEOS=.*/_PHP_GEOS=NO/g"                                ${barCnf}
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
    if [[ "${_L_VM_TEST}" =~ "3.6.14-beng" ]] \
      || [ -e "/root/.debug.cnf" ] \
      || [[ "${_L_VM_TEST}" =~ "3.6.15-beng" ]]; then
      _L_VMFAMILY="VS"
    fi
    if [ -e "/root/.auto.up.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
      || [ "${_L_VMFAMILY}" = "VS" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _PHP_OVERRIDE=$(grep _PHP_FPM_VERSION ${barCnf} \
          | cut -d= -f2 \
          | awk '{ print $1}' \
          | sed "s/[\"]//g" 2>&1)
        _CLSTR_PHP_MULTI_INSTALL="${_PHP_OVERRIDE}"
        _CLSTR_PHP_MULTI_INSTALL="5.6 5.5 5.3"
      fi
      if [ ! -e "/root/.debug.cnf" ] || [ -e "/root/.default.cnf" ]; then
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
        || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        || [ "${_L_VMFAMILY}" = "VS" ] \
        || [ -e "/root/.host8.cnf" ]; then
        if [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ]; then
          if [ ! -z "${_CLSTR_PHP_MULTI_INSTALL}" ]; then
            _PHP_MULTI_INSTALL="${_CLSTR_PHP_MULTI_INSTALL}"
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
            if [ ! -e "/root/.debug.cnf" ] || [ -e "/root/.default.cnf" ]; then
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
      || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
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
        sed -i "s/^_PHP_GEOS=.*/_PHP_GEOS=NO/g"                                    ${barCnf}
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
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
          || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
          || [ "${_VMFAMILY}" = "VS" ]; then
          if [ "${_VMFAMILY}" = "VS" ]; then
            sed -i "s/^_CPU_CRIT_RATIO=.*/_CPU_CRIT_RATIO=3/g"                     ${barCnf}
            sed -i "s/^_CPU_MAX_RATIO=.*/_CPU_MAX_RATIO=2/g"                       ${barCnf}
            sed -i "s/^_CPU_SPIDER_RATIO=.*/_CPU_SPIDER_RATIO=1/g"                 ${barCnf}
            sed -i "s/^_PHP_GEOS=.*/_PHP_GEOS=NO/g"                                ${barCnf}
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
        || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        || [ "${_VMFAMILY}" = "VS" ]; then
        if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
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
    st_runner "${_INSTAPP} mytop" 2> /dev/null
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
  msg "INFO: Installing extra Drush versions..."
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
  aptitude autoclean -y &> /dev/null
  apt-get clean -qq &> /dev/null
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
      sed -i "s/^deb.*security.debian.org.*/## security updates no longer available for lenny/g" ${aptLiSys} &> /dev/null
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
  ###--------------------###
  apt-get update &> /dev/null
  ###--------------------###
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
      --with-pam --with-openssl=/usr/include/openssl/" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "make --quiet install" 2> /dev/null
    mrun "service ssh restart" &> /dev/null
    if [[ ! "$_SSH_GET_DPKG" =~ "hold" ]]; then
      aptitude hold openssh-server &> /dev/null
      aptitude hold openssh-client &> /dev/null
      aptitude hold ssh &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections
      echo "openssh-client hold" | dpkg --set-selections
      echo "ssh hold" | dpkg --set-selections
    fi
  else
    if [[ ! "$_SSH_GET_DPKG" =~ "hold" ]]; then
      aptitude hold openssh-server &> /dev/null
      aptitude hold openssh-client &> /dev/null
      aptitude hold ssh &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections
      echo "openssh-client hold" | dpkg --set-selections
      echo "ssh hold" | dpkg --set-selections
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
      if [ "${_OSV}" = "stretch" ] \
        || [ "${_OSV}" = "trusty" ] \
        || [ "${_OSV}" = "precise" ]; then
        _DO_NOTHING=YES
      else
        _CURL_INSTALL_REQUIRED=YES
        msg "INFO: Installed cURL ${_CURL_ITD} with OpenSSL $_CURL_SSL_ITD"
        msg "INFO: cURL rebuild will be forced"
        sed -i "s/^_SSL_FROM_SOURCES=.*/_SSL_FROM_SOURCES=YES/g" /root/.barracuda.cnf
        echo _GIT_FORCE_REINSTALL=YES >> /root/.barracuda.cnf
        echo _SSL_FORCE_REINSTALL=YES >> /root/.barracuda.cnf
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
      echo "libcurl3 install" | dpkg --set-selections
      echo "libcurl3-gnutls install" | dpkg --set-selections
      echo "libcurl4-openssl-dev install" | dpkg --set-selections
      aptitude install libcurl3 -y &> /dev/null
      aptitude install libcurl3-gnutls -y &> /dev/null
      aptitude install libcurl4-openssl-dev -y &> /dev/null
      echo "curl hold" | dpkg --set-selections
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
          echo "curl install" | dpkg --set-selections
          apt-get install curl -y --force-yes --reinstall &> /dev/null
        fi
      fi
    else
      if [[ ! "${_CURL_GET_DPKG}" =~ "hold" ]]; then
        echo "libcurl3 install" | dpkg --set-selections
        echo "libcurl3-gnutls install" | dpkg --set-selections
        echo "libcurl4-openssl-dev install" | dpkg --set-selections
        aptitude install libcurl3 -y &> /dev/null
        aptitude install libcurl3-gnutls -y &> /dev/null
        aptitude install libcurl4-openssl-dev -y &> /dev/null
        echo "curl hold" | dpkg --set-selections
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
      echo "libssl-dev install" | dpkg --set-selections
      echo "openssl hold" | dpkg --set-selections
      echo "zlibc hold" | dpkg --set-selections
      echo "zlib1g hold" | dpkg --set-selections
      echo "zlib1g-dev hold" | dpkg --set-selections
    fi
  else
    if [[ ! "$_SSL_GET_DPKG" =~ "hold" ]]; then
      aptitude install libssl-dev -y &> /dev/null
      aptitude hold openssl &> /dev/null
      aptitude hold zlibc &> /dev/null
      aptitude hold zlib1g &> /dev/null
      aptitude hold zlib1g-dev &> /dev/null
      echo "libssl-dev install" | dpkg --set-selections
      echo "openssl hold" | dpkg --set-selections
      echo "zlibc hold" | dpkg --set-selections
      echo "zlib1g hold" | dpkg --set-selections
      echo "zlib1g-dev hold" | dpkg --set-selections
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
                  optipng \
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
                    sftp-user \
                    sftp-verif \
                    sftp-who \
                    syncpass"
  for i in ${_PROTECTED_ITEMS}; do
    _BIN_ITEM=$(which $i 2>&1)
    if [ -e "$_BIN_ITEM" ]; then
      chown root:root $_BIN_ITEM &> /dev/null
      chmod 700 $_BIN_ITEM &> /dev/null
    fi
  done

  chown root:root /usr/bin/mysecureshell &> /dev/null
  chmod 4755 /usr/bin/mysecureshell &> /dev/null

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
  if [ -e "/var/log/barracuda_log.txt" ]; then
    _T_SERIES_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
    if [[ "${_T_SERIES_TEST}" =~ "BOA-2.4." ]] \
      || [[ "${_T_SERIES_TEST}" =~ "BOA-2.3.8" ]]; then
      _DO_NOTHING=YES
    else
      fix_core_dgd
    fi
  fi
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
  rm -f /var/xdrago/monitor/acrashsql.sh
  rm -f /var/xdrago/acrashsql.sh
  rm -f /var/xdrago/usage.sh
  rm -f /var/xdrago/memcache.sh*
  rm -f /var/xdrago/purge_cruft.sh
  rm -f /var/xdrago/*.old
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
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] ; then
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
    csf -x  &> /dev/null
    csf -uf &> /dev/null
    csf -e  &> /dev/null
    csf -q  &> /dev/null
  fi
  cd /
  chmod 711 bin boot data dev emul etc home lib lib64 lib32 media mnt opt \
    sbin selinux srv sys usr var share run &> /dev/null
  chmod 700 root &> /dev/null
  msg "BYE!"
}

install_with_aptitude_deps() {
  st_runner "${_INSTAPP} ${_DEBDEPS}" 2> /dev/null
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  if [[ "${_XTRAS_LIST}" =~ "FMG" ]]; then
    if [ "${_OSV}" = "squeeze" ]; then
      _EXTRA_APT="tree ffmpeg flvtool2 libavcodec52"
    elif [ "${_OSV}" = "lucid" ]; then
      _EXTRA_APT="tree ffmpeg flvtool2 libavcodec-extra-52"
    elif [ "${_OSV}" = "wheezy" ] || [ "${_OSV}" = "trusty" ] \
      || [ "${_OSV}" = "precise" ]; then
      _EXTRA_APT="tree ffmpeg flvtool2 libavcodec-extra-53"
    else
      _EXTRA_APT="tree ffmpeg flvtool2 libavcodec51"
    fi
  else
    _EXTRA_APT="tree"
  fi
  st_runner "apt-get install $_EXTRA_APT -f -y --force-yes -q \
    --config-file /opt/tmp/apt.conf.noninteractive" 2> /dev/null
  if [ -e "/etc/init.d/php5-fpm" ]; then
    mrun "service php5-fpm stop" &> /dev/null
    mrun "update-rc.d -f php5-fpm remove" &> /dev/null
  fi
}

basic_packages_install_on_init() {
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing some basic tools now, please wait..."
    _BROKEN_KEYRING_TEST=$(apt-get update 2>&1)
    if [[ "$_BROKEN_KEYRING_TEST" =~ "signatures were invalid" ]] \
      || [[ "$_BROKEN_KEYRING_TEST" =~ "GPG error" ]]; then
      msg "WARN: Installed keyring is broken, forced reinstall required"
      if [ "${_THIS_OS}" = "Debian" ]; then
        apt-get install debian-keyring ${forCer} &> /dev/null
        apt-get install debian-archive-keyring ${forCer} &> /dev/null
      else
        apt-get install ubuntu-keyring ${forCer} &> /dev/null
      fi
    fi
    apt-get update &> /dev/null
    ${_INITINS} locales &> /dev/null
    fix_locales
    ${_INITINS} lsb-release &> /dev/null
    ${_INITINS} dnsutils &> /dev/null
    ${_INITINS} netcat &> /dev/null
    ${_INITINS} curl &> /dev/null
    ${_INITINS} wget &> /dev/null
  fi
}

more_packages_install_on_init() {
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing more basic tools now, please wait..."
    if [ -e "/etc/debian_version" ]; then
      _L_DEB_TEST=$(grep "^5." /etc/debian_version 2>&1)
      if [ ! -z "$_L_DEB_TEST" ]; then
        sed -i "s/^deb.*security.debian.org.*/## security updates no longer available for lenny/g" ${aptLiSys} &> /dev/null
        sed -i "s/ftp.*debian.org/archive.debian.org/g" \
          ${aptLiSys} &> /dev/null
        sed -i "s/volatile.debian.org/archive.debian.org/g" \
          ${aptLiSys} &> /dev/null
      fi
    fi
    apt-get update &> /dev/null
    ${_INITINS} locales &> /dev/null
    fix_locales
    ${_INITINS} git-core &> /dev/null
    ${_INITINS} aptitude &> /dev/null
    ${_INITINS} axel &> /dev/null
  fi
}

if_squeeze_to_wheezy() {
  if [ "${_SQUEEZE_TO_WHEEZY}" = "YES" ] \
    && [ "${_LOC_OSV}" = "squeeze" ]; then
    msg "WARN: Squeeze to Wheezy upgrade will start in 60 seconds..."
    msg "WARN: Now pray it will work... or hit ctrl-c to stop now!"
    if [ ! -e "/root/.upstart.cnf" ]; then
      service cron stop &> /dev/null
      mrun "sleep 60"
    fi
    check_dns_settings
    if [ "${_USE_PROVIDER_DNS}" = "NO" ]; then
      mv -f /etc/resolv.conf /etc/resolv.conf.pre-dist-upgrade
      echo "nameserver 8.8.8.8" >/etc/resolv.conf
      echo "nameserver 8.8.4.4" >>/etc/resolv.conf
      cat /etc/resolv.conf.pre-dist-upgrade >>/etc/resolv.conf
    fi
    mv -f /var/xdrago /var/xdrago_wait &> /dev/null
    mv -f /var/xdrago /var/xdrago_wait &> /dev/null
    msg "WARN: Too late! Squeeze to Wheezy upgrade in progress..."
    msg "HINT: Run tail -f ${_LOG}"
    msg "HINT: in another terminal window to watch details"
    _FULL_FORCE_REINSTALL=YES
    _PURGE_MODE=OFF
    rm -f ${mtrNgx}/pre.d/nginx_speed_purge.conf
    if [ -e "/etc/init.d/bind" ]; then
      rm -f /etc/init.d/bind
    fi
    if [ -e "/etc/default/tomcat" ] && [ -e "/etc/init.d/tomcat" ]; then
      service tomcat stop &> /dev/null
      mv /etc/init.d/tomcat /etc/init.d/offtomcat
      kill -9 $(ps aux | grep '[t]omcat' | awk '{print $2}') &> /dev/null
    fi
    echo "curl install" | dpkg --set-selections
    echo "libssl-dev install" | dpkg --set-selections
    echo "openssh-client install" | dpkg --set-selections
    echo "openssh-server install" | dpkg --set-selections
    echo "openssl install" | dpkg --set-selections
    echo "ssh install" | dpkg --set-selections
    echo "zlib1g install" | dpkg --set-selections
    echo "zlib1g-dev install" | dpkg --set-selections
    echo "zlibc install" | dpkg --set-selections
    mrun "apt-get install openssl install ${forCer}"        &> /dev/null
    mrun "apt-get install libssl-dev install ${forCer}"     &> /dev/null
    mrun "apt-get install curl install ${forCer}"           &> /dev/null
    mrun "apt-get install openssh-client install ${forCer}" &> /dev/null
    mrun "apt-get install openssh-server install ${forCer}" &> /dev/null
    mrun "apt-get install ssh install ${forCer}"            &> /dev/null
    mrun "apt-get install zlib1g install ${forCer}"         &> /dev/null
    mrun "apt-get install zlib1g-dev install ${forCer}"     &> /dev/null
    mrun "apt-get install zlibc install ${forCer}"          &> /dev/null
    mrun "apt-get remove collectd -y --force-yes -qq"       &> /dev/null
    mrun "apt-get remove nginx-extras -y --force-yes -qq"   &> /dev/null
    mrun "apt-get remove nginx -y --force-yes -qq"          &> /dev/null
    mrun "apt-get remove nginx-common -y --force-yes -qq"   &> /dev/null
    mrun "apt-get remove nginx-full -y --force-yes -qq"     &> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      touch /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      touch /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    mrun "aptitude remove php5 \
                          php5-cgi \
                          php5-curl \
                          php5-fpm \
                          php5-gd \
                          php5-geoip \
                          php5-gmp \
                          php5-imagick \
                          php5-imap \
                          php5-ldap \
                          php5-mcrypt \
                          php5-memcache \
                          php5-mysql \
                          php5-sqlite \
                          php5-xmlrpc \
                          php5-xsl -y" &> /dev/null
    mrun "apt-get autoremove -y --force-yes -qq" &> /dev/null
    mrun "aptitude remove phpunit php-pear php-benchmark -y" &> /dev/null
    mrun "aptitude remove php5-cli php5-common -y" &> /dev/null
    mrun "aptitude remove php5-apc -y" &> /dev/null
    mrun "aptitude remove php-apc -y" &> /dev/null
    mrun "aptitude remove apache2.2-common -y" &> /dev/null
    mrun "aptitude remove apache2-utils apache2.2-bin -y" &> /dev/null
    mrun "aptitude install lsof -y" &> /dev/null
    mrun "apt-get autoremove -y --force-yes -qq" &> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      rm -f /etc/php5/conf.d/{opcache.ini,imagick.ini,memcached.ini}
      rm -f /etc/php5/conf.d/{apc.ini,redis.ini,suhosin.ini,newrelic.ini}
    fi
    mrun "apt-get purge svscan -y" &> /dev/null
    mrun "apt-get purge pound -y" &> /dev/null
    mrun "apt-get autoremove -y --force-yes -qq" &> /dev/null
    sed -i "s/.*proposed-updates.*//g" /etc/apt/sources.list
    sed -i "s/squeeze/wheezy/g"  /etc/apt/sources.list.d/* &> /dev/null
    mrun "apt-get update -y --force-yes" &> /dev/null
    mrun "apt-get upgrade -f -y --force-yes -q \
      --config-file /opt/tmp/apt.conf.noninteractive" 2> /dev/null
    mrun "apt-get install apt dpkg aptitude ${forCer} -q \
      --config-file /opt/tmp/apt.conf.noninteractive" 2> /dev/null
    mrun "apt-get dist-upgrade -f -y --force-yes -q \
      --config-file /opt/tmp/apt.conf.noninteractive" 2> /dev/null
    touch ${mtrNgx}/pre.d/nginx_speed_purge.conf
    install_upgrade_nginx
    if [ -e "/etc/init.d/bind9" ] && [ ! -e "/etc/init.d/bind" ]; then
      ln -sf /etc/init.d/bind9 /etc/init.d/bind
    fi
    if [ -e "/etc/init.d/networking.dpkg-dist" ]; then
      mv -f /etc/init.d/networking /etc/init.d/networking.bak
      cp -af /etc/init.d/networking.dpkg-dist /etc/init.d/networking
      chmod 755 /etc/init.d/networking
    fi
    if [ -d "/var/www/cgp" ]; then
      mrun "apt-get install collectd -y --force-yes" 2> /dev/null
    fi
    mrun "apt-get install udev lsb-release libc-client2007e-dev \
      -y --force-yes" 2> /dev/null
    _L_VM_TEST=$(uname -a 2>&1)
    if [[ "${_L_VM_TEST}" =~ "3.6.14-beng" ]] \
      || [ -e "/root/.debug.cnf" ] \
      || [[ "${_L_VM_TEST}" =~ "3.6.15-beng" ]]; then
      _PTMX=OK
      _REMOVE_LINKS="halt \
                     hwclock.sh \
                     hwclockfirst.sh \
                     ifupdown \
                     ifupdown-clean \
                     klogd \
                     mountall-bootclean.sh \
                     mountall.sh \
                     mountdevsubfs.sh \
                     mountkernfs.sh \
                     mountnfs-bootclean.sh \
                     mountnfs.sh \
                     mountoverflowtmp \
                     mountvirtfs \
                     mtab.sh \
                     networking \
                     reboot \
                     setserial \
                     umountfs \
                     umountnfs.sh \
                     umountroot \
                     urandom"
      for link in ${_REMOVE_LINKS}; do
        update-rc.d -f $link remove &> /dev/null
      done
    else
      _PTMX=CHECK
    fi
    mrun "dpkg --configure --force-all -a" 2> /dev/null
    mrun "apt-get update -y" 2> /dev/null
    mrun "dpkg --configure --force-all -a" 2> /dev/null
    mrun "apt-get install aptitude ${forCer}" 2> /dev/null
    mrun "apt-get install util-linux ${forCer}" 2> /dev/null
    mrun "aptitude full-upgrade -f -y -q -o Dpkg::Options::=--force-confdef \
          -o Dpkg::Options::=--force-confold --allow-unauthenticated" 2> /dev/null
    mrun "dpkg --configure --force-all -a" 2> /dev/null
    mrun "apt-get -f install -qq" &> /dev/null
    mrun "aptitude full-upgrade -f -y -q -o Dpkg::Options::=--force-confdef \
          -o Dpkg::Options::=--force-confold --allow-unauthenticated" 2> /dev/null
    _PTS_TEST=$(cat /proc/mounts | grep devpts 2>&1)
    if [[ ! "${_PTS_TEST}" =~ "devpts" ]] || [ ! -e "/dev/pts/ptmx" ]; then
      _PTS=FIX
    else
      _PTS=OK
    fi
    if [ "${_PTMX}" = "CHECK" ] && [ "${_PTS}" = "FIX" ]; then
      msg "WARN: Required /dev/pts/ptmx does not exist! We will fix this now..."
      mkdir -p /dev/pts
      rm -f -r /dev/pts/*
      apt-get update -qq &> /dev/null
      apt-get install udev -y --force-yes &> /dev/null
      mount -t devpts devpts /dev/pts &> /dev/null
      echo "devpts          /dev/pts        devpts  rw,noexec,nosuid,gid=5,mode=620 0  0" >> /etc/fstab
    fi
    echo rotate > /var/log/syslog
    mv -f /var/xdrago_wait /var/xdrago &> /dev/null
    msg "INFO: No errors? Then Squeeze to Wheezy upgrade was successful - congrats!"
    msg "HINT: Please remember to reboot when Barracuda will complete all upgrades"
  fi
}

if_lenny_to_squeeze() {
  if [ "${_LENNY_TO_SQUEEZE}" = "YES" ] && [ "${_LOC_OSV}" = "lenny" ]; then
    _FULL_FORCE_REINSTALL=YES
    msg "WARN: Lenny to Squeeze upgrade will start in 60 seconds..."
    msg "WARN: Now pray it will work... or hit ctrl-c to stop now!"
    if [ ! -e "/root/.upstart.cnf" ]; then
      service cron stop &> /dev/null
      mrun "sleep 60"
    fi
    check_dns_settings
    if [ "${_USE_PROVIDER_DNS}" = "NO" ]; then
      mv -f /etc/resolv.conf /etc/resolv.conf.pre-dist-upgrade
      echo "nameserver 8.8.8.8" >/etc/resolv.conf
      echo "nameserver 8.8.4.4" >>/etc/resolv.conf
      cat /etc/resolv.conf.pre-dist-upgrade >>/etc/resolv.conf
    fi
    mv -f /var/xdrago /var/xdrago_wait &> /dev/null
    msg "WARN: Too late! Lenny to Squeeze upgrade in progress..."
    msg "HINT: Run tail -f ${_LOG}"
    msg "HINT: in another terminal window to watch details"
    if [ -e "/etc/init.d/bind" ]; then
      rm -f /etc/init.d/bind
    fi
    if [ -e "/etc/default/tomcat" ] && [ -e "/etc/init.d/tomcat" ]; then
      service tomcat stop &> /dev/null
      mv /etc/init.d/tomcat /etc/init.d/offtomcat
      kill -9 $(ps aux | grep '[t]omcat' | awk '{print $2}') &> /dev/null
    fi
    mrun "apt-get remove collectd -y --force-yes -qq" &> /dev/null
    mrun "apt-get remove libc-client2007b-dev -y --force-yes -qq" &> /dev/null
    mrun "apt-get purge svscan -y" &> /dev/null
    mrun "apt-get purge pound -y" &> /dev/null
    if [[ "${_L_VM_TEST}" =~ "3.6.14-beng" ]] \
      || [ -e "/root/.debug.cnf" ] \
      || [[ "${_L_VM_TEST}" =~ "3.6.15-beng" ]]; then
      mrun "apt-get remove udev -y --force-yes -qq" &> /dev/null
    fi
    mrun "apt-get remove lsb-release -y --force-yes -qq" &> /dev/null
    mrun "apt-get update -y --force-yes" &> /dev/null
    mrun "apt-get autoremove -y --force-yes -qq" &> /dev/null
    mrun "apt-get install apt dpkg aptitude -f -y --force-yes -q \
      --config-file /opt/tmp/apt.conf.noninteractive" 2> /dev/null
    mrun "apt-get dist-upgrade -f -y --force-yes -q \
      --config-file /opt/tmp/apt.conf.noninteractive" 2> /dev/null
    mrun "apt-get install libgeoip1 libgeoip-dev geoip-database \
      -y --force-yes" 2> /dev/null
    check_install_latest_git
    install_upgrade_nginx
    if [ -e "/etc/init.d/bind9" ] && [ ! -e "/etc/init.d/bind" ]; then
      ln -sf /etc/init.d/bind9 /etc/init.d/bind
    fi
    if [ -d "/var/www/cgp" ]; then
      mrun "apt-get install collectd -y --force-yes" 2> /dev/null
    fi
    mrun "apt-get install udev lsb-release libc-client2007e-dev \
      -y --force-yes" 2> /dev/null
    _L_VM_TEST=$(uname -a 2>&1)
    if [[ "${_L_VM_TEST}" =~ "3.6.14-beng" ]] \
      || [ -e "/root/.debug.cnf" ] \
      || [[ "${_L_VM_TEST}" =~ "3.6.15-beng" ]]; then
      _REMOVE_LINKS="halt \
                     hwclock.sh \
                     hwclockfirst.sh \
                     ifupdown \
                     ifupdown-clean \
                     klogd \
                     mountall-bootclean.sh \
                     mountall.sh \
                     mountdevsubfs.sh \
                     mountkernfs.sh \
                     mountnfs-bootclean.sh \
                     mountnfs.sh \
                     mountoverflowtmp \
                     mountvirtfs \
                     mtab.sh \
                     networking \
                     reboot \
                     setserial \
                     umountfs \
                     umountnfs.sh \
                     umountroot \
                     urandom"
      for link in ${_REMOVE_LINKS}; do
        update-rc.d -f $link remove &> /dev/null
      done
    fi
    sed -i "s/lenny/squeeze/g"  /etc/apt/sources.list.d/* &> /dev/null
    mrun "aptitude update -y" &> /dev/null
    mrun "dpkg --configure --force-all -a" 2> /dev/null
    mrun "aptitude full-upgrade -f -y -q -o Dpkg::Options::=--force-confdef \
          -o Dpkg::Options::=--force-confold --allow-unauthenticated" 2> /dev/null
    echo rotate > /var/log/syslog
    mv -f /var/xdrago_wait /var/xdrago &> /dev/null
    msg "INFO: No errors? Then Lenny to Squeeze upgrade was successful - congrats!"
    msg "HINT: Please remember to reboot when Barracuda will complete all upgrades"
  fi
}

update_webmin_apt() {
  if [ -d "/etc/webmin" ]; then
    if [ ! -e "${pthLog}/webmin_update_apt_src.log" ]; then
      cd /var/opt
      echo "## Webmin APT Repository" > ${aptLiSys}.d/webmin.list
      echo "deb http://download.webmin.com/download/repository \
        sarge contrib" | fmt -su -w 2500 >> ${aptLiSys}.d/webmin.list
      echo "deb http://webmin.mirror.somersettechsolutions.co.uk/repository \
        sarge contrib" | fmt -su -w 2500 >> ${aptLiSys}.d/webmin.list
      _KEYS_SERVER_TEST=FALSE
      until [[ "${_KEYS_SERVER_TEST}" =~ "GnuPG" ]]; do
        rm -f jcameron-key.asc*
        wget -q -U iCab ${urlDev}/jcameron-key.asc
        _KEYS_SERVER_TEST=$(grep GnuPG jcameron-key.asc 2>&1)
        sleep 2
      done
      cat jcameron-key.asc | apt-key add - &> /dev/null
      rm -f jcameron-key.asc*
      touch ${pthLog}/webmin_update_apt_src.log
    fi
  fi
}

sys_packages_update() {
  msg "INFO: Running system packages update..."
  update_webmin_apt
  if [ "${_OSV}" = "lenny" ]; then
    sed -i "s/^deb.*security.debian.org.*/## security updates no longer available for lenny/g" ${aptLiSys} &> /dev/null
    sed -i "s/ftp.*debian.org/archive.debian.org/g" \
      ${aptLiSys} &> /dev/null
    sed -i "s/volatile.debian.org/archive.debian.org/g" \
      ${aptLiSys} &> /dev/null
    st_runner "aptitude autoclean -y" &> /dev/null
    st_runner "apt-get clean -qq" &> /dev/null
  else
    st_runner "dpkg --configure --force-all -a" 2> /dev/null
  fi
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
  st_runner "aptitude update -y" &> /dev/null
  _DB_SERVER_TEST=$(mysql -V 2>&1)
  if [ "${_STATUS}" = "INIT" ]; then
    st_runner "aptitude full-upgrade -f -y -q \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold" 2> /dev/null
    st_runner "aptitude update -y" &> /dev/null
    st_runner "aptitude full-upgrade -f -y -q \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold" 2> /dev/null
    st_runner "aptitude autoclean -y" &> /dev/null
  else
    echo "gnupg-curl install" | dpkg --set-selections
    if [ -e "/etc/php5/conf.d" ]; then
      touch /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      touch /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    st_runner "aptitude remove php5 \
                               php5-cgi \
                               php5-curl \
                               php5-fpm \
                               php5-gd \
                               php5-geoip \
                               php5-gmp \
                               php5-imagick \
                               php5-imap \
                               php5-ldap \
                               php5-mcrypt \
                               php5-memcache \
                               php5-mysql \
                               php5-sqlite \
                               php5-xmlrpc \
                               php5-xsl -y" &> /dev/null
    st_runner "apt-get autoremove -y --force-yes -qq" &> /dev/null
    st_runner "aptitude remove phpunit php-pear php-benchmark -y" &> /dev/null
    st_runner "aptitude remove php5-cli php5-common -y" &> /dev/null
    st_runner "aptitude remove php5-apc -y" &> /dev/null
    st_runner "aptitude remove php-apc -y" &> /dev/null
    st_runner "aptitude remove apache2.2-common -y" &> /dev/null
    st_runner "aptitude remove apache2-utils apache2.2-bin -y" &> /dev/null
    st_runner "aptitude install lsof -y" &> /dev/null
    st_runner "apt-get autoremove -y --force-yes -qq" &> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      rm -f /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      rm -f /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    if [ "${_OSV}" = "squeeze" ]; then
      if [ -e "${aptLiSys}.d/dotdeb.list" ]; then
        rm -f ${aptLiSys}.d/dotdeb.list
        st_runner "aptitude autoclean -y" &> /dev/null
        st_runner "apt-get clean -qq" &> /dev/null
        st_runner "apt-get update -y --force-yes" &> /dev/null
      fi
    fi
    rm -f /var/lib/mysql/debian-*.flag &> /dev/null
    _KEYS_SERVER_TEST=FALSE
    if [ ! -e "/root/.upstart.cnf" ]; then
      service cron stop &> /dev/null
    fi
    if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
      csf -x &> /dev/null
    fi
    until [[ "${_KEYS_SERVER_TEST}" =~ "MariaDB" ]]; do
      _KEYS_SERVER_TEST=$(apt-key adv --recv-keys \
        --keyserver hkp://keyserver.ubuntu.com:80 1BB943DB 2>&1)
      sleep 2
    done
    _UP_JDK=NO
    _UP_LNX=NO
    _UP_NRC=NO
    _UP_PHP=NO
    check_apt_updates
  fi
}

sys_packages_install() {
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing required libraries and tools, please wait..."
  else
    msg "INFO: Upgrading required libraries and tools..."
    if [ ! -e "/etc/init.d/php5-fpm" ]; then
      cp -af ${locCnf}/php5-fpm-init-vanilla /etc/init.d/php5-fpm
    fi
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [[ "${_XTRAS_LIST}" =~ "SR" ]] \
      || [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ "${_OSV}" = "wheezy" ] \
        || [ "${_OSV}" = "trusty" ] \
        || [ "${_OSV}" = "precise" ]; then
        _APT_XTRA="openjdk-7-jre-headless openjdk-6-jre-headless nginx"
      else
        _APT_XTRA="openjdk-6-jre-headless nginx"
      fi
    else
      _APT_XTRA="nginx"
    fi
    _APT_ELSE="netcat nginx"
  else
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-6-jdk | grep install 2>&1)
    if [[ "$_APT_ITEM" =~ "install" ]]; then
      mrun "apt-get remove openjdk-6-jdk -y --force-yes -qq" &> /dev/null
      mrun "apt-get purge openjdk-6-jdk -y --force-yes -qq" &> /dev/null
      mrun "apt-get autoremove -y --force-yes -qq" &> /dev/null
    fi
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-7-jdk | grep install 2>&1)
    if [[ "$_APT_ITEM" =~ "install" ]]; then
      mrun "apt-get remove openjdk-7-jdk -y --force-yes -qq" &> /dev/null
      mrun "apt-get purge openjdk-7-jdk -y --force-yes -qq" &> /dev/null
      mrun "apt-get autoremove -y --force-yes -qq" &> /dev/null
    fi
    if [[ "${_XTRAS_LIST}" =~ "SR" ]] \
      || [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ "${_OSV}" = "wheezy" ] \
        || [ "${_OSV}" = "trusty" ] \
        || [ "${_OSV}" = "precise" ]; then
        _APT_XTRA="openjdk-7-jre-headless openjdk-6-jre-headless"
      else
        _APT_XTRA="openjdk-6-jre-headless"
      fi
    else
      _APT_XTRA=""
    fi
    _APT_ELSE="netcat"
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
    mrun "apt-get -f install -qq"                         &> /dev/null
    mrun "service nginx start"                            &> /dev/null
    mrun "apt-get remove nginx-extras -y --force-yes -qq" &> /dev/null
    mrun "apt-get remove nginx -y --force-yes -qq"        &> /dev/null
    mrun "apt-get remove nginx-common -y --force-yes -qq" &> /dev/null
    mrun "apt-get remove nginx-full -y --force-yes -qq"   &> /dev/null
    mrun "apt-get remove redis-server -y --force-yes -qq" &> /dev/null
    st_runner "apt-get autoremove -y --force-yes -qq"     &> /dev/null
    st_runner "apt-get update -y --force-yes"             &> /dev/null
  fi
  _EXTRA_LIB_APT="libmcrypt-dev"
  if [ ! -z "${_EXTRA_PACKAGES}" ]; then
    _EXTRA_PACKAGES="screen ${_EXTRA_PACKAGES}"
  else
    _EXTRA_PACKAGES="screen"
  fi
  _ETH_TEST=$(ifconfig 2>&1)
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_ETH_TEST}" =~ "venet0" ]] || [ -e "/proc/bean_counters" ]; then
    _IS_VZ=YES
  else
    _IS_VZ=NO
  fi
  if [ "$_IS_VZ" = "YES" ] \
    || [ -e "/root/.use.sysklogd.cnf" ] \
    || [ "${_OSV}" = "trusty" ] \
    || [ "${_OSV}" = "precise" ]; then
    _SYSLOGD=sysklogd
     mrun "apt-get purge rsyslog -y" &> /dev/null
     mrun "killall -9 rsyslogd" &> /dev/null
  else
    _SYSLOGD=rsyslog
  fi
  if [ "${_NGINX_SPDY}" = "YES" ] \
    || [ "${_SSL_FROM_SOURCES}" = "YES" ] \
    || [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    if [ "${_OSV}" = "wheezy" ] \
      || [ "${_OSV}" = "trusty" ] \
      || [ "${_OSV}" = "precise" ]; then
      _SSB_SRC=NO
    else
      _SSB_SRC=YES
    fi
  else
    _SSB_SRC=NO
  fi
  if [ "$_SSB_SRC" = "YES" ]; then
    _EXTRA_PACKAGES="libcurl4-openssl-dev \
                     ${_EXTRA_PACKAGES}"
  else
    _EXTRA_PACKAGES="curl \
                     libcurl4-openssl-dev \
                     ${_EXTRA_PACKAGES}"
  fi
  if [ "${_OSV}" = "trusty" ]; then
    _EXTRA_PACKAGES="libgd2-noxpm-dev \
                     libgd2-xpm-dev \
                     libgd2-dev \
                     libgd3 \
                     libxpm-dev \
                     ${_EXTRA_PACKAGES}"
  else
    _EXTRA_PACKAGES="libgd2-xpm \
                     ${_EXTRA_PACKAGES}"
  fi

  if [[ "${_XTRAS_LIST}" =~ "IMG" ]]; then
    _EXTRA_PACKAGES="advancecomp \
                     jpegoptim \
                     libjpeg-progs \
                     optipng \
                     pngcrush \
                     pngquant \
                     ${_EXTRA_PACKAGES}"
  fi

  if [ "${_OSV}" = "wheezy" ] \
    || [ "${_OSV}" = "squeeze" ] \
    || [ "${_OSV}" = "trusty" ] \
    || [ "${_OSV}" = "precise" ] \
    || [ "${_OSV}" = "lucid" ]; then
    _DEBDEPS="apticron \
              $_APT_XTRA \
              $_EXTRA_LIB_APT \
              ${_EXTRA_PACKAGES} \
              $_SYSLOGD \
              aptitude \
              auditd \
              autoconf2.13 \
              automake \
              automake1.4 \
              autotools-dev \
              bc \
              bison \
              build-essential \
              catdoc \
              cron \
              cvs \
              cython \
              defoma \
              devscripts \
              dnsutils \
              dstat \
              flex \
              fontconfig-config \
              geoip-database \
              gettext \
              ghostscript \
              gnupg \
              gnupg-curl \
              gnupg2 \
              htop \
              ifstat \
              imagemagick \
              iptables \
              ldap-utils \
              lemon \
              lftp \
              libapr1 \
              libaprutil1 \
              libc-client-dev \
              libc-client2007e \
              libc-client2007e-dev \
              libfilesys-diskspace-perl \
              libfontconfig1 \
              libfreetype6 \
              libfreetype6-dev \
              libfribidi0 \
              libgeoip-dev \
              libgeoip1 \
              libgmp3-dev \
              libhtml-template-perl \
              libjpeg-dev \
              libjpeg62 \
              libmagickwand-dev \
              libnet-daemon-perl \
              libpam-umask \
              libpam-unix2 \
              libpcre3 \
              libpcre3-dev \
              libplrpc-perl \
              libpng12-0 \
              libpng12-dev \
              libpq5 \
              libsasl2-modules \
              libssl-dev \
              libt1-5 \
              libt1-dev \
              libterm-readkey-perl \
              libtool \
              libwww-perl \
              libxcrypt1 \
              libxml2-dev \
              libxpm4 \
              libxslt-dev \
              libxslt1-dbg \
              libxslt1-dev \
              libxslt1.1 \
              m4 \
              makepasswd \
              mc \
              mcrypt \
              nano \
              ncurses-dev \
              ncurses-term \
              netcat \
              ntpdate \
              p7zip-full \
              pdftk \
              postfix \
              postfix-pcre \
              pwgen \
              python-dev \
              python-software-properties \
              re2c \
              rrdtool \
              rsync \
              s3cmd \
              shtool \
              sipcalc \
              ssh \
              ssl-cert \
              subversion \
              sudo \
              symlinks \
              sysstat \
              sysvinit-utils \
              t1lib-bin \
              telnet \
              time \
              ttf-dejavu \
              ttf-dejavu-core \
              ttf-dejavu-extra \
              udev \
              unrtf \
              unzip \
              vim \
              whois \
              xml-core \
              xml2 \
              xpdf \
              zip \
              zlib1g-dev \
              zlibc"
  elif [ "${_OSV}" = "lenny" ]; then
    _DEBDEPS="apticron \
              $_APT_ELSE \
              $_EXTRA_LIB_APT \
              ${_EXTRA_PACKAGES} \
              $_SYSLOGD \
              aptitude \
              auditd \
              autoconf2.13 \
              automake \
              automake1.4 \
              autotools-dev \
              bc \
              bison \
              build-essential \
              catdoc \
              cron \
              cvs \
              cython \
              defoma \
              devscripts \
              dnsutils \
              dstat \
              flex \
              fontconfig-config \
              gettext \
              ghostscript \
              gnupg \
              gnupg-curl \
              gnupg2 \
              htop \
              ifstat \
              imagemagick \
              iptables \
              ldap-utils \
              lemon \
              lftp \
              libapr1 \
              libaprutil1 \
              libc-client-dev \
              libc-client2007b \
              libc-client2007b-dev \
              libfilesys-diskspace-perl \
              libfontconfig1 \
              libfreetype6 \
              libfreetype6-dev \
              libfribidi0 \
              libgeoip-dev \
              libgeoip1 \
              libgmp3-dev \
              libhtml-template-perl \
              libjpeg-dev \
              libjpeg62 \
              libmagick9-dev \
              libnet-daemon-perl \
              libpam-umask \
              libpcre3 \
              libpcre3-dev \
              libplrpc-perl \
              libpng12-0 \
              libpng12-dev \
              libpq5 \
              libsasl2-modules \
              libssl-dev \
              libt1-5 \
              libt1-dev \
              libterm-readkey-perl \
              libtool \
              libwww-perl \
              libxml2-dev \
              libxpm4 \
              libxslt-dev \
              libxslt1-dbg \
              libxslt1-dev \
              libxslt1.1 \
              m4 \
              makepasswd \
              mc \
              mcrypt \
              nano \
              ncurses-dev \
              ncurses-term \
              ntpdate \
              openjdk-6-jre-headless \
              p7zip-full \
              pdftk \
              postfix \
              postfix-pcre \
              pwgen \
              python-dev \
              re2c \
              rrdtool \
              rsync \
              shtool \
              sipcalc \
              ssh \
              ssl-cert \
              subversion \
              sudo \
              symlinks \
              sysstat \
              sysvconfig \
              t1lib-bin \
              telnet \
              time \
              ttf-dejavu \
              ttf-dejavu-core \
              ttf-dejavu-extra \
              udev \
              unrtf \
              unzip \
              vim \
              whois \
              xml-core \
              xml2 \
              xpdf \
              zip \
              zlib1g-dev \
              zlibc"
  fi
}

fix_postfix() {
  if [ "${_STATUS}" = "INIT" ]; then
    st_runner "aptitude remove exim4 exim4-base exim4-config sendmail \
      sendmail-base sendmail-cf sendmail-bin -y" &> /dev/null
    st_runner "apt-get purge exim4 exim4-base exim4-config sendmail \
      sendmail-base sendmail-cf sendmail-bin -y" &> /dev/null
    st_runner "apt-get autoremove -y --force-yes -qq" &> /dev/null
    rm -f /etc/aliases
    rm -f -r /etc/mail
    killall -9 sendmail &> /dev/null
  else
    _POSTFIX_TEST=$(grep "fatal: open lock file" /var/log/mail.log 2>&1)
    if [[ "$_POSTFIX_TEST" =~ "fatal: open lock file" ]]; then
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
      mrun "dpkg --configure -a"      &> /dev/null
      mrun "apt-get clean -qq"        &> /dev/null
      mrun "apt-get update -qq"       &> /dev/null
      mrun "apt-get purge postfix -y" &> /dev/null
      echo > /var/log/mail.log
    fi
  fi
  if [ ! -e "/etc/aliases" ]; then
    echo "postmaster:    root" > /etc/aliases
    newaliases &> /dev/null
  fi
}

fix_libs_php() {
  if [ "${_OSV}" = "wheezy" ] \
    || [ "${_OSV}" = "trusty" ] \
    || [ "${_OSV}" = "precise" ]; then
    if [ ! -L "/usr/lib/libXpm.so" ] || [ ! -e "/usr/lib/libgmp.so.3" ]; then
      msg "INFO: Fix #1 for libs in ${_THIS_OS} ${_OSV}"
      _X86_64_TEST=$(uname -m 2>&1)
      if [ "$_X86_64_TEST" = "x86_64" ]; then
        ln -sf /usr/lib/x86_64-linux-gnu/libgmp.so  /usr/lib/libgmp.so
        ln -sf /usr/lib/x86_64-linux-gnu/libgmp.so  /usr/lib/libgmp.so.3
        ln -sf /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib/libjpeg.so
        ln -sf /usr/lib/x86_64-linux-gnu/libkrb5.so /usr/lib/libkrb5.so
        ln -sf /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so
        ln -sf /usr/lib/x86_64-linux-gnu/libpng.so  /usr/lib/libpng.so
        ln -sf /usr/lib/x86_64-linux-gnu/libXpm.so  /usr/lib/libXpm.so
        if [ ! -e "/usr/include/gmp.h" ] \
          && [ -e "/usr/include/x86_64-linux-gnu/gmp.h" ]; then
          ln -sf /usr/include/x86_64-linux-gnu/gmp.h  /usr/include/gmp.h
        fi
      else
        ln -sf /usr/lib/i386-linux-gnu/libgmp.so  /usr/lib/libgmp.so
        ln -sf /usr/lib/i386-linux-gnu/libgmp.so  /usr/lib/libgmp.so.3
        ln -sf /usr/lib/i386-linux-gnu/libjpeg.so /usr/lib/libjpeg.so
        ln -sf /usr/lib/i386-linux-gnu/libkrb5.so /usr/lib/libkrb5.so
        ln -sf /usr/lib/i386-linux-gnu/libldap.so /usr/lib/libldap.so
        ln -sf /usr/lib/i386-linux-gnu/libpng.so  /usr/lib/libpng.so
        ln -sf /usr/lib/i386-linux-gnu/libXpm.so  /usr/lib/libXpm.so
        if [ ! -e "/usr/include/gmp.h" ] \
          && [ -e "/usr/include/i386-linux-gnu/gmp.h" ]; then
          ln -sf /usr/include/i386-linux-gnu/gmp.h  /usr/include/gmp.h
        fi
      fi
    fi
  fi
}

fix_libssl() {
  if [ "${_OSV}" = "wheezy" ] \
    || [ "${_OSV}" = "trusty" ] \
    || [ "${_OSV}" = "precise" ]; then
    _SSL_FIX_REQUIRED=YES
    if [ "${_NGINX_SPDY}" = "YES" ] \
      || [ "${_SSL_FROM_SOURCES}" = "YES" ] \
      || [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
      if [ "${_OSV}" = "wheezy" ] \
        || [ "${_OSV}" = "trusty" ] \
        || [ "${_OSV}" = "precise" ]; then
        _SSL_FIX_REQUIRED=YES
      else
        _SSL_FIX_REQUIRED=NO
      fi
    fi
    if [ ! -e "/usr/lib/libssl.so.1.0.0" ] \
      && [ "$_SSL_FIX_REQUIRED" = "YES" ]; then
      msg "INFO: Fix #2 for libs in ${_THIS_OS} ${_OSV}"
      _X86_64_TEST=$(uname -m 2>&1)
      if [ "$_X86_64_TEST" = "x86_64" ]; then
        if [ -e "/usr/lib/x86_64-linux-gnu/libssl.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libssl.so.1.0.0" ]; then
          ln -s /usr/lib/x86_64-linux-gnu/libssl.so.1.0.0  \
            /usr/lib/libssl.so.1.0.0
        elif [ -e "/lib/x86_64-linux-gnu/libssl.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libssl.so.1.0.0" ]; then
          ln -s /lib/x86_64-linux-gnu/libssl.so.1.0.0  \
            /usr/lib/libssl.so.1.0.0
        fi
        if [ -e "/usr/lib/x86_64-linux-gnu/libcrypto.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libcrypto.so.1.0.0" ]; then
          ln -s /usr/lib/x86_64-linux-gnu/libcrypto.so.1.0.0 \
            /usr/lib/libcrypto.so.1.0.0
        elif [ -e "/lib/x86_64-linux-gnu/libcrypto.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libcrypto.so.1.0.0" ]; then
          ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 \
            /usr/lib/libcrypto.so.1.0.0
        fi
      else
        if [ -e "/usr/lib/i386-linux-gnu/libssl.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libssl.so.1.0.0" ]; then
          ln -s /usr/lib/i386-linux-gnu/libssl.so.1.0.0  \
            /usr/lib/libssl.so.1.0.0
        elif [ -e "/lib/i386-linux-gnu/libssl.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libssl.so.1.0.0" ]; then
          ln -s /lib/i386-linux-gnu/libssl.so.1.0.0  \
            /usr/lib/libssl.so.1.0.0
        fi
        if [ -e "/usr/lib/i386-linux-gnu/libcrypto.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libcrypto.so.1.0.0" ]; then
          ln -s /usr/lib/i386-linux-gnu/libcrypto.so.1.0.0 \
            /usr/lib/libcrypto.so.1.0.0
        elif [ -e "/lib/i386-linux-gnu/libcrypto.so.1.0.0" ] \
          && [ ! -e "/usr/lib/libcrypto.so.1.0.0" ]; then
          ln -s /lib/i386-linux-gnu/libcrypto.so.1.0.0 \
            /usr/lib/libcrypto.so.1.0.0
        fi
      fi
    fi
  fi
}

check_smtp() {
  if [ -z "${_SMTP_RELAY_HOST}" ] && [ "${_SMTP_RELAY_TEST}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Checking SMTP connections..."
    fi
    if ! netcat -w 14 -z smtp.gmail.com 25 ; then
      WE_NEED_RELAY=YES
      cat <<EOF

      Your outgoing SMTP port 25 doesn't work
      as expected, so your server can't send out
      any e-mails directly.

      It appears you need a SMTP relayhost added
      in your Postfix /etc/postfix/main.cf config.

      Please enter your SMTP relay host name
      as a value for _SMTP_RELAY_HOST="smtp.your.relay.server"

      Then run this script again.

EOF
      clean_pid_exit
    else
      _DO_NOTHING=YES
    fi
    ###
    ### Required if outgoing smtp port is closed and smtp relay is in use
    ###
    if [ ! -z "${_SMTP_RELAY_HOST}" ]; then
      sed -i "s/${_SMTP_RELAY_HOST}//g" /etc/postfix/main.cf &> /dev/null
      sed -i "s/relayhost =/relayhost = ${_SMTP_RELAY_HOST}/g" \
        /etc/postfix/main.cf &> /dev/null
      postfix reload &> /dev/null
    fi
  fi
}

install_vnstat() {
  if [ ! -e "/var/run/cloud_vhost.pid" ]; then
    if [ ! -e "${pthLog}/vnstat-${_VNSTAT_VRN}.log" ] \
      || [ ! -e "/usr/bin/vnstat" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      msg "INFO: Installing VnStat monitor..."
      cd /var/opt
      rm -f -r vnstat*
      get_dev_src "vnstat-${_VNSTAT_VRN}.tar.gz"
      cd vnstat-${_VNSTAT_VRN}
      st_runner "make --quiet" 2> /dev/null
      st_runner "make --quiet install" 2> /dev/null
      for INF in `vnstat --iflist | sed "s/Available interfaces//g" \
        | cut -d: -f2` ;do vnstat -u -i $INF &> /dev/null;done
      cp -af /var/opt/vnstat-${_VNSTAT_VRN}/examples/init.d/debian/vnstat \
        /etc/init.d/vnstat
      chmod 755 /etc/init.d/vnstat &> /dev/null
      st_runner "update-rc.d vnstat defaults" &> /dev/null
      sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /etc/vnstat.conf
      mrun "service vnstat start" &> /dev/null
      touch ${pthLog}/vnstat-${_VNSTAT_VRN}.log
      mrun "service vnstat restart" &> /dev/null
    fi
  fi
  if [ -e "/etc/init.d/vnstat" ] \
    && [ "${_VMFAMILY}" = "VS" ] \
    && [ ! -e "/boot/grub/grub.cfg" ] \
    && [ ! -e "/boot/grub/menu.lst" ]; then
    service vnstat stop &> /dev/null
    update-rc.d -f vnstat remove &> /dev/null
    rm -f /etc/init.d/vnstat
    rm -f /usr/bin/vnstat
    rm -f -r /var/lib/vnstat
  fi
}

install_update_xdrago() {
  cd /var
  if [ -d "/var/xdrago/conf" ] \
    && [ -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Upgrading a few more tools..."
    fi
    mv -f /var/xdrago-pre* ${vBs}/dragon/x/ &> /dev/null
    rm -f -r ${pthLog}/init.d-pre*
    rm -f -r ${vBs}/dragon/z/init.d-pre-*
    rm -f ${pthLog}/cron-root-pre*
    cp -af /var/xdrago \
      ${vBs}/dragon/x/xdrago-pre-${_X_VERSION}-${_NOW} &> /dev/null
    rm -f ${pthLog}/VISITOR_ABUSE_ONE.log
    rm -f ${pthLog}/blackIP.log
    rm -f /var/xdrago/{enableStatus,graceful,move_sql,run_all,second,Minute}
    rm -f /var/xdrago/{firewall.sh,stop-mysql-innodb.sh,firewall_restarter}
    rm -f /var/xdrago/{FireStart,memcache,redis}
    cp -af /var/spool/cron/crontabs/root \
      ${vBs}/dragon/z/cron-root-pre-${_X_VERSION}-${_NOW} &> /dev/null
    if [ "${_CUSTOM_CONFIG_LSHELL}" = "YES" ] \
      && [ -e "/var/xdrago/conf/lshell.conf" ]; then
      cp -af /var/xdrago/conf/lshell.conf ${vBs}/custom_lshell.conf
    fi
    cp -af ${bldPth}/aegir/tools/system/* /var/xdrago/ &> /dev/null
    if [ "${_CUSTOM_CONFIG_LSHELL}" = "YES" ] \
      && [ -e "${vBs}/custom_lshell.conf" ]; then
      cp -af ${vBs}/custom_lshell.conf /var/xdrago/conf/lshell.conf
    fi
    if [ -z "${_THISHTIP}" ]; then
      _LOC_DOM="${_THISHOST}"
      find_correct_ip
      _THISHTIP="${_LOC_IP}"
    fi
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [[ "${_THISHOST}" =~ "v251a.ams." ]]; then
        _NGINX_DOS_LIMIT=888
      else
        if [ -z "${_NGINX_DOS_LIMIT}" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "300" ]; then
          if [ "${_VMFAMILY}" = "VS" ]; then
            _NGINX_DOS_LIMIT=149
          else
            _NGINX_DOS_LIMIT=188
          fi
        fi
      fi
    fi
    sed -i "s/= 150/= ${_NGINX_DOS_LIMIT}/g" \
      /var/xdrago/monitor/check/scan_nginx &> /dev/null
    sed -i "s/= 200/= ${_NGINX_DOS_LIMIT}/g" \
      /var/xdrago/monitor/check/scan_nginx &> /dev/null
    if [ ! -z "$_NGINX_DOS_KEYWORDS" ]; then
      _NGINX_DOS_KEYWORDS=${_NGINX_DOS_KEYWORDS//[^a-zA-Z0-9|]/}
      if [ ! -z "$_NGINX_DOS_KEYWORDS" ]; then
        msg "INFO: Configured _NGINX_DOS_KEYWORDS: $_NGINX_DOS_KEYWORDS"
        sed -i "s/foobar/$_NGINX_DOS_KEYWORDS/g" \
          /var/xdrago/monitor/check/scan_nginx &> /dev/null
      fi
    fi
    mv -f /etc/cron.daily/mlocate ${vBs}/ &> /dev/null
    cp -af /var/xdrago/cron/crontabs/root /var/spool/cron/crontabs/ &> /dev/null
    if [ -e "/var/xdrago/cron/custom.txt" ]; then
      cat /var/xdrago/cron/custom.txt >> /var/spool/cron/crontabs/root
    fi
    chown root:crontab /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
        _DO_NOTHING=YES
      else
        if [ -e "/root/.high_load.cnf" ] \
          && [ ! -e "/root/.big_db.cnf" ] \
          && [ ! -e "/root/.tg.cnf" ]; then
          sed -i "s/3600/180/g" /var/xdrago/minute.sh &> /dev/null
        elif [ -e "/root/.big_db.cnf" ] || [ -e "/root/.tg.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/3600/1800/g" /var/xdrago/minute.sh &> /dev/null
        fi
        sed -i "s/rotate 52/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
        sed -i "s/rotate 1/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
        sed -i "s/INTERVAL 1 HOUR/INTERVAL 15 MINUTE/g" \
          /var/xdrago/purge_binlogs.sh &> /dev/null
      fi
    else
      sed -i "s/log\/lshell/log\/lsh/g" /etc/logrotate.d/lshell &> /dev/null
    fi
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing a few more tools..."
    mkdir -p ./xdrago
    cp -af ${bldPth}/aegir/tools/system/* ./xdrago/ &> /dev/null
    cp -af /var/xdrago/cron/crontabs/root /var/spool/cron/crontabs/ &> /dev/null
    chown root:crontab /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
    if [ -z "${_THISHTIP}" ]; then
      _LOC_DOM="${_THISHOST}"
      find_correct_ip
      _THISHTIP="${_LOC_IP}"
    fi
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [[ "${_THISHOST}" =~ "v251a.ams." ]]; then
        _NGINX_DOS_LIMIT=888
      else
        if [ -z "${_NGINX_DOS_LIMIT}" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "300" ]; then
          if [ "${_VMFAMILY}" = "VS" ]; then
            _NGINX_DOS_LIMIT=149
          else
            _NGINX_DOS_LIMIT=188
          fi
        fi
      fi
    fi
    sed -i "s/= 150/= ${_NGINX_DOS_LIMIT}/g" \
      /var/xdrago/monitor/check/scan_nginx &> /dev/null
    sed -i "s/= 200/= ${_NGINX_DOS_LIMIT}/g" \
      /var/xdrago/monitor/check/scan_nginx &> /dev/null
    if [ ! -z "$_NGINX_DOS_KEYWORDS" ]; then
      _NGINX_DOS_KEYWORDS=${_NGINX_DOS_KEYWORDS//[^a-zA-Z0-9|]/}
      if [ ! -z "$_NGINX_DOS_KEYWORDS" ]; then
        msg "INFO: Configured _NGINX_DOS_KEYWORDS: $_NGINX_DOS_KEYWORDS"
        sed -i "s/foobar/$_NGINX_DOS_KEYWORDS/g" \
          /var/xdrago/monitor/check/scan_nginx &> /dev/null
      fi
    fi
    mv -f /etc/cron.daily/mlocate ${vBs}/ &> /dev/null
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
        _DO_NOTHING=YES
      else
        if [ -e "/root/.high_load.cnf" ] \
          && [ ! -e "/root/.big_db.cnf" ] \
          && [ ! -e "/root/.tg.cnf" ]; then
          sed -i "s/3600/180/g" /var/xdrago/minute.sh &> /dev/null
        elif [ -e "/root/.big_db.cnf" ] || [ -e "/root/.tg.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/3600/1800/g" /var/xdrago/minute.sh &> /dev/null
        fi
        sed -i "s/rotate 52/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
        sed -i "s/rotate 1/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
      fi
    fi
  fi
  if [ -d "/var/xdrago-pre-${_X_VERSION}-${_NOW}" ]; then
    cp -af /var/xdrago-pre-${_X_VERSION}-${_NOW}/run-* /var/xdrago/ &> /dev/null
  fi
  sed -i "s/firewall/monitor/g" /var/xdrago/minute.sh &> /dev/null
  chmod -R 700 /var/xdrago/monitor/check &> /dev/null
  chmod 700 /var/xdrago/* &> /dev/null
  chmod 700 /var/xdrago &> /dev/null
}

check_fix_umask() {
  if [ ! -e "${pthLog}/umask_fixed_new.log" ]; then
    mkdir -p /var/www/nginx-default
    sed -i "s/^UMASK.*//g" /etc/default/login &> /dev/null
    echo "UMASK=002" >> /etc/default/login
    sed -i "/^$/d" /etc/default/login &> /dev/null
    sed -i "s/^UMASK.*/UMASK 002/g" /etc/login.defs &> /dev/null
    sed -i "s/^umask.*022/umask 002/g" /etc/profile &> /dev/null
    sed -i "s/^session optional pam_umask.*//g" /etc/pam.d/login &> /dev/null
    echo "session optional pam_umask.so umask=0002" >> /etc/pam.d/login
    sed -i "/^$/d" /etc/pam.d/login &> /dev/null
    echo "umask 002" >> /var/www/.profile
    chown www-data:www-data /var/www/.profile &> /dev/null
    chown www-data:www-data /var/www/nginx-default &> /dev/null
    touch ${pthLog}/umask_fixed_new.log
  fi
  if [ ! -e "${pthLog}/umask_fixed_shell_sftp.log" ]; then
    if [ "${_OSV}" = "lenny" ] || [ "${_OSV}" = "lucid" ]; then
      _DO_NOTHING=YES
    else
      sed -e '/Subsystem\ssftp/s:server$:server -u 0002:' -i /etc/ssh/sshd_config
    fi
    echo "session optional pam_umask.so umask=0002" >> /etc/pam.d/sshd
    mrun "service ssh restart" &> /dev/null
    touch ${pthLog}/umask_fixed_shell_sftp.log
  fi
  if [ ! -e "${pthLog}/src_umask_fixed_shell_sftp.log" ] \
    && [ -e "/usr/etc/sshd_config" ]; then
    if [ "${_OSV}" = "lenny" ] || [ "${_OSV}" = "lucid" ]; then
      _DO_NOTHING=YES
    else
      sed -e '/Subsystem\ssftp/s:server$:server -u 0002:' -i /usr/etc/sshd_config
    fi
    mrun "service ssh restart" &> /dev/null
    touch ${pthLog}/src_umask_fixed_shell_sftp.log
  fi
}

install_update_lshell() {
  if [ "${_OSV}" = "lenny" ]; then
    _PATH_LSHELL="/usr/bin/lshell"
  else
    _PATH_LSHELL="/usr/local/bin/lshell"
  fi
  if [ ! -e "/etc/logrotate.d/lshell" ] \
    || [ ! -e "$_PATH_LSHELL" ] \
    || [ ! -e "${pthLog}/lshell-build-${_LSHELL_VRN}" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    if [ "${_STATUS}" = "UPGRADE" ]; then
      msg "INFO: Upgrading Limited Shell to version ${_LSHELL_VRN}..."
      cp -af /etc/lshell.conf /etc/lshell.conf-bak-${_NOW} &> /dev/null
    else
      msg "INFO: Installing Limited Shell ${_LSHELL_VRN}..."
    fi
    cd /var/opt
    rm -f -r lshell*
    get_dev_src "lshell-${_LSHELL_VRN}.tar.gz"
    for Files in `find /var/opt/lshell-${_LSHELL_VRN} -type f`; do
      sed -i "s/kicked/logged/g" $Files &> /dev/null
      sed -i "s/Kicked/Logged/g" $Files &> /dev/null
    done
    cd /var/opt/lshell-${_LSHELL_VRN}
    rm -f -r /usr/local/lib/python2.6/dist-packages/lshell*
    rm -f -r /usr/local/lib/python2.7/dist-packages/lshell*
    st_runner "python setup.py install --no-compile" 2> /dev/null
    if [ "${_STATUS}" = "UPGRADE" ]; then
      cp -af /etc/lshell.conf-bak-${_NOW} /etc/lshell.conf &> /dev/null
    else
      cp -af ${bldPth}/aegir/tools/system/conf/lshell.conf /etc/lshell.conf
      echo "$_PATH_LSHELL" >> /etc/shells
    fi
    sed -i "s/log\/lshell/log\/lsh/g" /etc/logrotate.d/lshell &> /dev/null
    addgroup --system lshellg &> /dev/null
    mkdir -p /var/log/lsh
    chown :lshellg /var/log/lsh
    chmod 770 /var/log/lsh &> /dev/null
    touch ${pthLog}/lshell-build-${_LSHELL_VRN}
    if [ -f "/var/xdrago/manage_ltd_users.sh" ]; then
      if [ "${_STATUS}" = "UPGRADE" ] \
        && [ "${_CUSTOM_CONFIG_LSHELL}" = "NO" ]; then
        cp -af ${bldPth}/aegir/tools/system/conf/lshell.conf \
          /var/xdrago/conf/lshell.conf
      fi
      st_runner "bash /var/xdrago/manage_ltd_users.sh" &> /dev/null
    fi
  fi
  if [ -f "/usr/local/bin/lshell" ]; then
    if [ ! -L "/usr/bin/lshell" ]; then
      ln -sf /usr/local/bin/lshell /usr/bin/lshell &> /dev/null
    fi
  fi
  if [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ]; then
    sed -i "s/rotate 12/rotate 50/g" /etc/logrotate.d/lshell &> /dev/null
  fi
}

if_install_ftpd() {
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] || [[ "${_XTRAS_LIST}" =~ "FTP" ]]; then
    if [ ! -e "/etc/ssl/private/pure-ftpd.pem" ] \
      || [ ! -e "/usr/local/sbin/pure-config.pl" ] \
      || [ ! -e "/usr/local/sbin/pure-ftpd" ] \
      || [ ! -e "${pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_X_VERSION}.log" ] \
      || [ ! -e "/etc/ssl/private/pure-ftpd-dhparams.pem" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
      msg "INFO: Building Pure-FTPd server from sources, please wait..."
      if [ ! -e "/etc/ssl/private/pure-ftpd-dhparams.pem" ]; then
        msg "INFO: Generating DH parameters, 2048 bit, please wait..."
        st_runner "openssl dhparam \
          -out /etc/ssl/private/pure-ftpd-dhparams.pem 2048" 2> /dev/null
      fi
      if [ ! -e "/usr/local/sbin/pure-config.pl" ]; then
        echo "/bin/false" >> /etc/shells
        echo "/bin/true" >> /etc/shells
      fi
      mkdir -p /etc/ssl/private/
      rm -f /etc/ssl/private/pure-ftpd.pem
      rm -f /usr/local/sbin/pure-ftpd
      st_runner "openssl req -x509 -nodes -days 7300 -newkey rsa:2048 \
        -keyout /etc/ssl/private/pure-ftpd.pem \
        -out /etc/ssl/private/pure-ftpd.pem -batch" 2> /dev/null
      chmod 600 /etc/ssl/private/pure-ftpd.pem &> /dev/null
      cd /var/opt
      rm -f -r pure-ftpd*
      mkdir -p /usr/local/etc
      get_dev_src "pure-ftpd-${_PURE_FTPD_VRN}.tar.gz"
      cd pure-ftpd-${_PURE_FTPD_VRN}
      st_runner "sh ./configure --with-everything --with-virtualchroot \
        --without-humor --with-tls --with-diraliases --with-pam \
        --with-certfile=/etc/ssl/private/pure-ftpd.pem" 2> /dev/null
      st_runner "make install-strip" 2> /dev/null
      cd /usr/local/sbin/
      cp -af ${locCnf}/pure-config.pl.txt ./
      mv -f pure-config.pl.txt pure-config.pl &> /dev/null
      chmod 755 /usr/local/sbin/pure-config.pl &> /dev/null
      cp -af /var/opt/pure-ftpd-${_PURE_FTPD_VRN}/pam/pure-ftpd /etc/pam.d/
      fix_ftps_pam
      cd /usr/local/etc
      rm -f pure-ftpd.conf
      cp -af ${locCnf}/pure-ftpd.conf ./
      killall -9 pure-ftpd &> /dev/null
      st_runner "/usr/local/sbin/pure-config.pl \
        /usr/local/etc/pure-ftpd.conf" &> /dev/null
      cd /var/opt
      touch ${pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_X_VERSION}.log
    fi
  fi
}

check_fix_newrelic() {
  _NEWRELIC_APP_CFG="/etc/newrelic/newrelic.cfg"
  if [ -e "$_NEWRELIC_APP_CFG" ]; then
    _NEWRELIC_KEY_TEST=$(grep "REPLACE_WITH_REAL_KEY" $_NEWRELIC_APP_CFG 2>&1)
    if [[ "${_NEWRELIC_KEY_TEST}" =~ "REPLACE_WITH_REAL_KEY" ]] \
      && [ ! -z "${_NEWRELIC_KEY}" ]; then
      sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
        $_NEWRELIC_APP_CFG &> /dev/null
    fi
    sed -i "s/^loglevel=.*/loglevel=error/g" $_NEWRELIC_APP_CFG &> /dev/null
    mrun "service newrelic-daemon restart" &> /dev/null
  else
    if [ -e "/etc/init.d/newrelic-daemon" ] \
      || [ -e "/etc/init.d/newrelic-sysmond" ]; then
      service newrelic-daemon stop &> /dev/null
      update-rc.d -f newrelic-daemon remove &> /dev/null
      service newrelic-sysmond stop &> /dev/null
      update-rc.d -f newrelic-sysmond remove &> /dev/null
      st_runner "aptitude remove newrelic-php5 \
        newrelic-php5-common \
        newrelic-daemon \
        newrelic-sysmond -y" &> /dev/null
      st_runner "apt-get autoremove -y --force-yes -qq" &> /dev/null
      mv -f /etc/newrelic \
        ${vBs}/nr/etc-newrelic-pre-${_X_VERSION}-${_NOW} &> /dev/null
      rm -f /etc/init.d/newrelic-sysmond
      rm -f /etc/init.d/newrelic-daemon
      killall -9 newrelic-daemon &> /dev/null
      killall -9 nrsysmond &> /dev/null
    fi
  fi
  _NEWRELIC_SYS_CFG="/etc/newrelic/nrsysmond.cfg"
  if [ -e "$_NEWRELIC_SYS_CFG" ]; then
    _NEWRELIC_KEY_TEST=$(grep "REPLACE_WITH_REAL_KEY" $_NEWRELIC_SYS_CFG 2>&1)
    if [[ "${_NEWRELIC_KEY_TEST}" =~ "REPLACE_WITH_REAL_KEY" ]] \
      && [ ! -z "${_NEWRELIC_KEY}" ]; then
      sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
        $_NEWRELIC_SYS_CFG &> /dev/null
    fi
    sed -i "s/^loglevel=.*/loglevel=error/g" \
      $_NEWRELIC_SYS_CFG &> /dev/null
    sed -i "s/.*pidfile=.*/pidfile=\/var\/run\/nrsysmond.pid/g" \
      $_NEWRELIC_SYS_CFG &> /dev/null
    if [ -e "/root/.enable.newrelic.sysmond.cnf" ]; then
      mrun "service newrelic-sysmond restart" &> /dev/null
    else
      mrun "service newrelic-sysmond stop" &> /dev/null
    fi
  fi
}

check_fix_java() {
  if [ ! -e "/usr/lib/jvm/java-6-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-6-openjdk-amd64" ]; then
    ln -sf /usr/lib/jvm/java-6-openjdk-amd64 /usr/lib/jvm/java-6-openjdk
  fi
  if [ ! -e "/usr/lib/jvm/java-6-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-6-openjdk-i386" ]; then
    ln -sf /usr/lib/jvm/java-6-openjdk-i386 /usr/lib/jvm/java-6-openjdk
  fi
  if [ ! -e "/usr/lib/jvm/java-7-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-7-openjdk-amd64" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-amd64 /usr/lib/jvm/java-7-openjdk
  fi
  if [ ! -e "/usr/lib/jvm/java-7-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-7-openjdk-i386" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-i386 /usr/lib/jvm/java-7-openjdk
  fi
  if [ ! -e "/usr/bin/java7" ] \
    && [ -e "/usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java /usr/bin/java7
  fi
  if [ ! -e "/usr/bin/java7" ] \
    && [ -e "/usr/lib/jvm/java-7-openjdk-i386/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-i386/jre/bin/java /usr/bin/java7
  fi
}

update_initd() {
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Updating init scripts"
    cp -af ${locCnf}/clean-boa-env /etc/init.d/clean-boa-env
    chmod 755 /etc/init.d/clean-boa-env &> /dev/null
    st_runner "update-rc.d clean-boa-env defaults" &> /dev/null
    _SSH_USEDNS_TEST=$(grep "UseDNS" /etc/ssh/sshd_config 2>&1)
    if [[ "$_SSH_USEDNS_TEST" =~ (^)"UseDNS no" ]]; then
      _DO_NOTHING=YES
    elif [[ "$_SSH_USEDNS_TEST" =~ "UseDNS" ]]; then
      sed -i "s/.*UseDNS.*/UseDNS no/g" /etc/ssh/sshd_config &> /dev/null
    else
      echo >> /etc/ssh/sshd_config
      echo "UseDNS no" >> /etc/ssh/sshd_config
    fi
    if [ -e "/usr/etc/sshd_config" ]; then
      _SSH_USEDNS_TEST=$(grep "UseDNS" /usr/etc/sshd_config 2>&1)
      if [[ "$_SSH_USEDNS_TEST" =~ (^)"UseDNS no" ]]; then
        _DO_NOTHING=YES
      elif [[ "$_SSH_USEDNS_TEST" =~ "UseDNS" ]]; then
        sed -i "s/.*UseDNS.*/UseDNS no/g" /usr/etc/sshd_config &> /dev/null
      else
        echo >> /usr/etc/sshd_config
        echo "UseDNS no" >> /usr/etc/sshd_config
      fi
    fi
    mrun "service ssh reload" &> /dev/null
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      msg "INFO: Restarting Jetty 9"
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      mrun "service jetty9 start" &> /dev/null
    fi
    if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
      msg "INFO: Restarting Jetty 8"
      kill -9 $(ps aux | grep '[j]etty8' | awk '{print $2}') &> /dev/null
      mrun "service jetty8 start" &> /dev/null
    fi
    if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
      msg "INFO: Restarting Jetty 7"
      kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
      mrun "service jetty7 start" &> /dev/null
    fi
    if [ ! -e "/var/run/aegir_upgrade.pid" ]; then
      msg "INFO: Starting Redis, PHP-FPM and Nginx"
      mrun "service redis-server start" &> /dev/null
      killall -9 nginx php-cgi php-fpm &> /dev/null
      st_runner "update-rc.d -f php5-fpm remove" &> /dev/null
      st_runner "update-rc.d cron defaults" &> /dev/null
      if [ -e "/etc/init.d/php56-fpm" ]; then
        st_runner "update-rc.d php56-fpm defaults" &> /dev/null
        mrun "service php56-fpm start" &> /dev/null
      fi
      if [ -e "/etc/init.d/php55-fpm" ]; then
        st_runner "update-rc.d php55-fpm defaults" &> /dev/null
        mrun "service php55-fpm start" &> /dev/null
      fi
      if [ -e "/etc/init.d/php54-fpm" ]; then
        st_runner "update-rc.d php54-fpm defaults" &> /dev/null
        mrun "service php54-fpm start" &> /dev/null
      fi
      if [ -e "/etc/init.d/php53-fpm" ]; then
        st_runner "update-rc.d php53-fpm defaults" &> /dev/null
        mrun "service php53-fpm start" &> /dev/null
      fi
      st_runner "update-rc.d nginx defaults" &> /dev/null
      mrun "service nginx start" &> /dev/null
    fi
  else
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      sed -i "s/.*UseDNS.*//g" /etc/ssh/sshd_config &> /dev/null
      sed -i "s/^ClientAliveCountMax.*//g" /etc/ssh/sshd_config &> /dev/null
      sed -i "s/^ClientAliveInterval.*//g" /etc/ssh/sshd_config &> /dev/null
      sed -i "s/^IgnoreUserKnownHosts.*//g" /etc/ssh/sshd_config &> /dev/null
      sed -i "s/^PasswordAuthentication.*//g" /etc/ssh/sshd_config &> /dev/null
      sed -i "s/^PermitRootLogin.*/PermitRootLogin without-password/g" \
        /etc/ssh/sshd_config &> /dev/null
      echo >> /etc/ssh/sshd_config
      echo "IgnoreUserKnownHosts no" >> /etc/ssh/sshd_config
      echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
      echo "UseDNS no" >> /etc/ssh/sshd_config
      echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
      echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
      sed -i "/^$/d" /etc/ssh/sshd_config &> /dev/null
      if [ -e "/usr/etc/sshd_config" ]; then
        sed -i "s/.*UseDNS.*//g" /usr/etc/sshd_config &> /dev/null
        sed -i "s/^ClientAliveCountMax.*//g" /usr/etc/sshd_config &> /dev/null
        sed -i "s/^ClientAliveInterval.*//g" /usr/etc/sshd_config &> /dev/null
        sed -i "s/^IgnoreUserKnownHosts.*//g" /usr/etc/sshd_config &> /dev/null
        sed -i "s/^PasswordAuthentication.*//g" /usr/etc/sshd_config &> /dev/null
        sed -i "s/^PermitRootLogin.*/PermitRootLogin without-password/g" \
          /usr/etc/sshd_config &> /dev/null
        echo >> /usr/etc/sshd_config
        echo "IgnoreUserKnownHosts no" >> /usr/etc/sshd_config
        echo "PasswordAuthentication yes" >> /usr/etc/sshd_config
        echo "UseDNS no" >> /usr/etc/sshd_config
        echo "ClientAliveInterval 300" >> /usr/etc/sshd_config
        echo "ClientAliveCountMax 3" >> /usr/etc/sshd_config
        sed -i "/^$/d" /usr/etc/sshd_config &> /dev/null
      fi
      mrun "service ssh reload" &> /dev/null
    else
      _SSH_USEDNS_TEST=$(grep "^UseDNS no" /etc/ssh/sshd_config 2>&1)
      if [[ "$_SSH_USEDNS_TEST" =~ "UseDNS no" ]]; then
        _DO_NOTHING=YES
      else
        sed -i "s/.*UseDNS.*/UseDNS no/g" /etc/ssh/sshd_config &> /dev/null
      fi
      if [ -e "/usr/etc/sshd_config" ]; then
        _SSH_USEDNS_TEST=$(grep "^UseDNS no" /usr/etc/sshd_config 2>&1)
        if [[ "$_SSH_USEDNS_TEST" =~ "UseDNS no" ]]; then
          _DO_NOTHING=YES
        else
          sed -i "s/.*UseDNS.*/UseDNS no/g" /usr/etc/sshd_config &> /dev/null
        fi
      fi
      mrun "service ssh reload" &> /dev/null
    fi
    fix_on_upgrade
    tune_memory_limits
    kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}') &> /dev/null
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      msg "INFO: Restarting Jetty 9"
      mrun "service jetty9 start" &> /dev/null
    fi
    if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
      msg "INFO: Restarting Jetty 8"
      mrun "service jetty8 start" &> /dev/null
    fi
    if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
      msg "INFO: Restarting Jetty 7"
      mrun "service jetty7 start" &> /dev/null
    fi
    if [ ! -e "/var/run/aegir_upgrade.pid" ]; then
      msg "INFO: Restarting Redis, PHP-FPM and Nginx..."
      mrun "service redis-server restart" &> /dev/null
      st_runner "update-rc.d -f php5-fpm remove" &> /dev/null
      mrun "service nginx stop" &> /dev/null
      if [ -e "/etc/init.d/php56-fpm" ]; then
        st_runner "update-rc.d php56-fpm defaults" &> /dev/null
        mrun "service php56-fpm stop" &> /dev/null
      fi
      if [ -e "/etc/init.d/php55-fpm" ]; then
        st_runner "update-rc.d php55-fpm defaults" &> /dev/null
        mrun "service php55-fpm stop" &> /dev/null
      fi
      if [ -e "/etc/init.d/php54-fpm" ]; then
        st_runner "update-rc.d php54-fpm defaults" &> /dev/null
        mrun "service php54-fpm stop" &> /dev/null
      fi
      if [ -e "/etc/init.d/php53-fpm" ]; then
        st_runner "update-rc.d php53-fpm defaults" &> /dev/null
        mrun "service php53-fpm stop" &> /dev/null
      fi
      killall -9 php-fpm &> /dev/null
      killall -9 php-cgi &> /dev/null
      killall -9 pure-ftpd &> /dev/null
      msg "INFO: Restarting ${_DB_SERVER} server..."
      mrun "service mysql restart" &> /dev/null
      if [ -e "/etc/init.d/php56-fpm" ]; then
        mrun "service php56-fpm start" &> /dev/null
      fi
      if [ -e "/etc/init.d/php55-fpm" ]; then
        mrun "service php55-fpm start" &> /dev/null
      fi
      if [ -e "/etc/init.d/php54-fpm" ]; then
        mrun "service php54-fpm start" &> /dev/null
      fi
      if [ -e "/etc/init.d/php53-fpm" ]; then
        mrun "service php53-fpm start" &> /dev/null
      fi
      mrun "service nginx start" &> /dev/null
    fi
  fi
}

update_sysctl() {
  if [ ! -e "/root/.no.sysctl.update.cnf" ] \
    && [ ! -e "${pthLog}/sysctl.conf-${_X_VERSION}-${_NOW}.log" ]; then
    cp -af /etc/sysctl.conf \
      ${vBs}/dragon/t/sysctl.conf-pre-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${locCnf}/sysctl.conf /etc/sysctl.conf
    if [ -e "/etc/security/limits.conf" ]; then
      _IF_NF=$(grep '524288' /etc/security/limits.conf 2>&1)
      if [ -z "$_IF_NF" ]; then
        echo "*         hard    nofile      524288"  >> /etc/security/limits.conf
        echo "*         soft    nofile      524288"  >> /etc/security/limits.conf
        echo "root      hard    nofile      1048576" >> /etc/security/limits.conf
        echo "root      soft    nofile      1048576" >> /etc/security/limits.conf
      fi
    fi
    if [ -e "/boot/grub/grub.cfg" ] || [ -e "/boot/grub/menu.lst" ]; then
      sysctl -p /etc/sysctl.conf &> /dev/null
      _IF_CDP=$(ps aux | grep '[c]dp_io' | awk '{print $2}' 2>&1)
      if [ -z "$_IF_CDP" ] && [ ! -e "/root/.no.swap.clear.cnf" ]; then
        msg "INFO: Cleaning up system swap, it may take a moment..."
        st_runner "swapoff -a" &> /dev/null
        st_runner "swapon -a" &> /dev/null
      fi
    else
      sysctl -p /etc/sysctl.conf &> /dev/null
    fi
    touch ${pthLog}/sysctl.conf-${_X_VERSION}-${_NOW}.log
  fi
}

update_apticron() {
  XPTEMAIL=${_MY_EMAIL//\@/\\\\\@}
  sed -i "s/notify\@omega8.cc/${_MY_EMAIL}/g"  \
    /etc/csf/csf.conf &> /dev/null
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/checksql.cgi
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/daily.sh
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/weekly.sh
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/monitor/check/segfault_alert
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/monitor/check/escapecheck
  if [ -e "/usr/sbin/apticron" ]; then
    if [ -e "/etc/apticron/apticron.conf" ]; then
      _APTICRON_TEST=$(grep "NOTIFY_HOLDS" /etc/apticron/apticron.conf 2>&1)
      if [[ "$_APTICRON_TEST" =~ "NOTIFY_HOLDS" ]]; then
        sed -i "s/^# NOTIFY_HOLDS=\"0\"/NOTIFY_HOLDS=\"0\"/g" \
          /etc/apticron/apticron.conf
        sed -i "s/notify\@omega8.cc/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        sed -i "s/root/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        sed -i "s/^# be something like.*/# be something like ${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
      else
        mrun "apt-get remove apticron -y --force-yes -qq" &> /dev/null
        mrun "apt-get purge apticron -y --force-yes -qq"  &> /dev/null
        mrun "apt-get install apticron -y"                &> /dev/null
        sed -i "s/^# NOTIFY_HOLDS=\"0\"/NOTIFY_HOLDS=\"0\"/g" \
          /etc/apticron/apticron.conf
        sed -i "s/notify\@omega8.cc/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        sed -i "s/root/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        sed -i "s/^# be something like.*/# be something like ${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
      fi
    fi
    if [[ "${_X_VERSION}" =~ "dev" ]] && [ "${_AEGIR_VERSION}" = "HEAD" ]; then
      sed -i "s/aptitude full-upgrade/barracuda up-head system/g" \
        /usr/sbin/apticron
      sed -i "s/apt-get dist-upgrade/barracuda up-head system/g" \
        /usr/sbin/apticron
      sed -i "s/barracuda up-head.*/barracuda up-head system/g" \
        /usr/sbin/apticron
    else
      sed -i "s/aptitude full-upgrade/barracuda up-stable system/g" \
        /usr/sbin/apticron
      sed -i "s/apt-get dist-upgrade/barracuda up-stable system/g" \
        /usr/sbin/apticron
      sed -i "s/barracuda up-stable.*/barracuda up-stable system/g" \
        /usr/sbin/apticron
    fi
  fi
}

complete() {
  fix_lfd_whitelist
  fix_lfd_uidignore
  fix_cnf_postfix
  if [ "${_STRICT_BIN_PERMISSIONS}" = "YES" ]; then
    usermod -aG users aegir &> /dev/null
    usermod -aG users man &> /dev/null
    usermod -aG users mysql &> /dev/null
    if [ -x "/bin/dash" ]; then
      switch_to_dash
    else
      switch_to_bash
    fi
    strict_bin_permissions
  fi
  check_php_cli
  finale
}
