
define_loc_osr() {
  _LOC_OSR=
  _MSG_LOC=
  if [ "${_JESSIE_TO_BEOWULF}" = "YES" ] \
    && [ "${_OSR}" = "jessie" ]; then
    _LOC_OSR=jessie
    _NEW_OSR=beowulf
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Jessie to Devuan Beowulf"
  fi
  if [ "${_STRETCH_TO_BEOWULF}" = "YES" ] \
    && [ "${_OSR}" = "stretch" ]; then
    _LOC_OSR=stretch
    _NEW_OSR=beowulf
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Stretch to Devuan Beowulf"
  fi
  if [ "${_BUSTER_TO_BEOWULF}" = "YES" ] \
    && [ "${_OSR}" = "buster" ]; then
    _LOC_OSR=buster
    _NEW_OSR=beowulf
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Buster to Devuan Beowulf"
  fi
  if [ "${_BEOWULF_TO_CHIMAERA}" = "YES" ] \
    && [ "${_OSR}" = "beowulf" ]; then
    _LOC_OSR=beowulf
    _NEW_OSR=chimaera
    _TGT_OSN=Devuan
    _MSG_LOC="Devuan Beowulf to Devuan Chimaera"
  fi
  if [ "${_BULLSEYE_TO_CHIMAERA}" = "YES" ] \
    && [ "${_OSR}" = "bullseye" ]; then
    _LOC_OSR=bullseye
    _NEW_OSR=chimaera
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Bullseye to Devuan Chimaera"
  fi
  if [ "${_BUSTER_TO_BULLSEYE}" = "YES" ] \
    && [ "${_OSR}" = "buster" ]; then
    _LOC_OSR=buster
    _NEW_OSR=bullseye
    _TGT_OSN=Debian
    _MSG_LOC="Debian Buster to Debian Bullseye"
  fi
  if [ "${_STRETCH_TO_BUSTER}" = "YES" ] \
    && [ "${_OSR}" = "stretch" ]; then
    _LOC_OSR=stretch
    _NEW_OSR=buster
    _TGT_OSN=Debian
    _MSG_LOC="Debian Stretch to Debian Buster"
  fi
  if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
    && [ "${_OSR}" = "jessie" ]; then
    _LOC_OSR=jessie
    _NEW_OSR=stretch
    _TGT_OSN=Debian
    _MSG_LOC="Debian Jessie to Debian Stretch"
  fi
}

if_to_do_fix() {
  _DO_FIX=
  if [ "${_JESSIE_TO_BEOWULF}" = "YES" ] \
    && [ "${_LOC_OSR}" = "jessie" ]; then
    _DO_FIX=YES
  fi
  if [ "${_STRETCH_TO_BEOWULF}" = "YES" ] \
    && [ "${_LOC_OSR}" = "stretch" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BUSTER_TO_BEOWULF}" = "YES" ] \
    && [ "${_LOC_OSR}" = "buster" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BEOWULF_TO_CHIMAERA}" = "YES" ] \
    && [ "${_LOC_OSR}" = "beowulf" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BULLSEYE_TO_CHIMAERA}" = "YES" ] \
    && [ "${_LOC_OSR}" = "bullseye" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BUSTER_TO_BULLSEYE}" = "YES" ] \
    && [ "${_LOC_OSR}" = "buster" ]; then
    _DO_FIX=YES
  fi
  if [ "${_STRETCH_TO_BUSTER}" = "YES" ] \
    && [ "${_LOC_OSR}" = "stretch" ]; then
    _DO_FIX=YES
  fi
  if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
    && [ "${_LOC_OSR}" = "jessie" ]; then
    _DO_FIX=YES
  fi
}

count_cpu() {
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
    rm -rf /tmp/drush_make_tmp*
    rm -rf /tmp/make_tmp*
    rm -f /tmp/pm-updatecode*
    rm -f /tmp/cache.inc*
    touch /var/run/boa_run.pid
    mkdir -p ${pthLog}
    find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
    _AWS_TEST_A=$(dmidecode -s bios-version 2>&1)
    _AWS_TEST_B=$(head -c 3 /sys/hypervisor/uuid 2>&1)
    if [[ "${_AWS_TEST_A}" =~ "amazon" ]] \
      || [[ "${_AWS_TEST_B}" =~ "ec2" ]]; then
      _VMFAMILY="AWS"
    fi
    _VM_TEST=$(uname -a 2>&1)
    if [[ "${_VM_TEST}" =~ "-beng" ]]; then
      _VMFAMILY="VS"
      touch /var/run/cloud_vhost.pid
      if [ ! -e "/etc/apt/preferences.d/fuse" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: fuse\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/fuse
        apt-get update -qq &> /dev/null
      fi
      if [ ! -e "/etc/apt/preferences.d/udev" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: udev\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/udev
        apt-get update -qq &> /dev/null
      fi
      if [ ! -e "/etc/apt/preferences.d/makedev" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: makedev\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/makedev
        apt-get update -qq &> /dev/null
      fi
      apt-get remove fuse -y -qq &> /dev/null
      apt-get purge fuse -y -qq &> /dev/null
      apt-get remove udev -y -qq &> /dev/null
      apt-get purge udev -y -qq &> /dev/null
      apt-get remove makedev -y -qq &> /dev/null
      apt-get purge makedev -y -qq &> /dev/null
      if [ -e "/sbin/hdparm" ]; then
        mrun "apt-get remove hdparm -y -qq" &> /dev/null
        mrun "apt-get purge hdparm -y -qq" &> /dev/null
      fi
      if [ -e "/sbin/auditd" ]; then
        mrun "apt-get remove auditd -y -qq" &> /dev/null
        mrun "apt-get purge auditd -y -qq" &> /dev/null
      fi
      if [ -d "/etc/webmin" ]; then
        mrun "apt --fix-broken install -y" 2> /dev/null
        mrun "dpkg --configure --force-all -a" 2> /dev/null
        mrun "apt-get clean -qq" &> /dev/null
        rm -rf /var/lib/apt/lists/*
        mrun "apt-get update -qq" &> /dev/null
        mrun "apt-get remove webmin -y -qq" &> /dev/null
        mrun "apt-get purge webmin -y -qq" &> /dev/null
        rm -rf /usr/share/webmin
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
    _XTERM_TEST=$(grep "export TERM" /root/.bashrc 2>&1)
    if [[ "${_XTERM_TEST}" =~ "export TERM" ]]; then
      sed -i "s/.*export TERM=.*//g" /root/.bashrc
      wait
    fi
  fi
}

#
# Kill nash-hotplug.
kill_nash() {
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _DO_NOTHING=YES
  else
    _NASH_TEST=$(grep nash-hotplug /etc/rc.local 2>&1)
    if [[ ! "${_NASH_TEST}" =~ "nash-hotplug" ]]; then
      cp -af /etc/rc.local /etc/rc.local.bak.${_NOW}
      sed -i "s/exit 0//g" /etc/rc.local &> /dev/null
      wait
      echo "killall -9 nash-hotplug" >> /etc/rc.local
      echo "exit 0" >> /etc/rc.local
      killall -9 nash-hotplug &> /dev/null
    fi
  fi
}

#
# Cleanup for Postfix.
fix_postfix() {
  if [ "${_STATUS}" = "INIT" ]; then
    st_runner "${_RMAPP} exim4 exim4-base exim4-config" &> /dev/null
    st_runner "${_RMAPP} sendmail \
               sendmail-base sendmail-cf sendmail-bin" &> /dev/null
    st_runner "apt-get purge exim4 exim4-base exim4-config -y" &> /dev/null
    st_runner "apt-get purge sendmail \
               sendmail-base sendmail-cf sendmail-bin -y" &> /dev/null
    rm -f /etc/aliases
    rm -rf /etc/mail
    killall -9 sendmail &> /dev/null
  else
    _POSTFIX_TEST=$(grep "fatal: open lock file" /var/log/mail.log 2>&1)
    if [[ "${_POSTFIX_TEST}" =~ "fatal: open lock file" ]]; then
      mrun "apt --fix-broken install -y" 2> /dev/null
      mrun "dpkg --configure --force-all -a" 2> /dev/null
      mrun "apt-get clean -qq" &> /dev/null
      rm -rf /var/lib/apt/lists/*
      mrun "apt-get update -qq" &> /dev/null
      mrun "apt-get purge postfix -y" &> /dev/null
      echo > /var/log/mail.log
    fi
  fi
  if [ ! -e "/etc/aliases" ]; then
    echo "postmaster:    root" > /etc/aliases
    newaliases &> /dev/null
  fi
}

#
# Fix FTPS PAM where required.
fix_ftps_pam() {
  if [ ! -e "/etc/ftpusers" ]; then
    cp -af ${locCnf}/ftpusers /etc/ftpusers
  fi
  sed -i "s/pam_stack.so/pam_unix.so/g" /etc/pam.d/pure-ftpd &> /dev/null
  wait
  sed -i "s/ service=system-auth//g"    /etc/pam.d/pure-ftpd &> /dev/null
  wait
}

#
# Fix FTPS and SFTP access on modern systems.
fix_sftp_ftps_modern() {
  _LSHELL_PATH_TEST=$(grep "/usr/bin/lshell" /etc/shells 2>&1)
  if [[ ! "${_LSHELL_PATH_TEST}" =~ "/usr/bin/lshell" ]]; then
    echo "/usr/bin/lshell" >> /etc/shells
  fi
  if [ ! -e "${pthLog}/mss-build-${_MSS_VRN}-${_X_VERSION}.log" ] \
    || [ ! -e "/etc/ssh/sftp_config" ] \
    || [ ! -e "/usr/bin/mysecureshell" ] \
    || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Installing MySecureShell ${_MSS_VRN}..."
    cd /var/opt
    rm -rf mysecureshell*
    get_dev_src "mysecureshell-${_MSS_VRN}.tar.gz"
    cd /var/opt/mysecureshell
    mrun "bash ./configure" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    st_runner "sh ./install.sh yesall" 2> /dev/null
    touch ${pthLog}/mss-build-${_MSS_VRN}-${_X_VERSION}.log
    cp -af ${locCnf}/sftp_config /etc/ssh/sftp_config
    mrun "service ssh restart" &> /dev/null
  fi
  if [ -e "/usr/bin/mysecureshell" ] && [ -e "/etc/ssh/sftp_config" ]; then
    _MSS_TEST=$(grep "lshell" /etc/passwd 2>&1)
    if [[ "${_MSS_TEST}" =~ "lshell" ]]; then
      sed -i "s/usr\/.*\/lshell/usr\/bin\/mysecureshell/g" /etc/passwd &> /dev/null
      wait
    fi
    _MSS_TEST=$(grep "MySecureShell" /etc/passwd 2>&1)
    if [[ "${_MSS_TEST}" =~ "MySecureShell" ]]; then
      sed -i "s/usr\/.*\/MySecureShell/usr\/bin\/mysecureshell/g" /etc/passwd &> /dev/null
      wait
    fi
  fi
  _MSS_PATH_TEST=$(grep "/usr/bin/mysecureshell" /etc/shells 2>&1)
  if [[ "${_MSS_PATH_TEST}" =~ "/usr/bin/mysecureshell" ]]; then
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
    || [[ "${_THISHOST}" =~ ".o8.io" ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
    || [ -e "/root/.host8.cnf" ]; then
    sed -i "s/.*purge_cruft.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "/^$/d" /etc/crontab &> /dev/null
    wait
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
    wait
  fi
}

#
# Fix this on upgrade.
fix_on_upgrade() {
  sed -i "s/loglevel.*/loglevel warning/g" /etc/redis/redis.conf &> /dev/null
  sed -i "s/^TLS.*/TLS 2/g" /usr/local/etc/pure-ftpd.conf &> /dev/null
  cp -af ${locCnf}/clean-boa-env /etc/init.d/clean-boa-env
  chmod 755 /etc/init.d/clean-boa-env &> /dev/null
  mrun "update-rc.d clean-boa-env defaults" &> /dev/null
  kill_nash
  fix_sftp_ftps_modern
  fix_ftps_pam
  disable_old_purge_cruft_machine
  update_php_conf
  update_ini_tpl
  update_nginx_conf
  update_global_inc_conf
  update_redis_password
}

#
# Tune memory limits for PHP, Nginx and MariaDB or Percona.
tune_memory_limits() {
  count_cpu
  _VM_TEST=$(uname -a 2>&1)
  if [ -e "/proc/bean_counters" ]; then
    _VMFAMILY="VZ"
  else
    _VMFAMILY="XEN"
  fi
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _VMFAMILY="VS"
  fi
  if [[ "${_AWS_TEST_A}" =~ "amazon" ]] \
    || [[ "${_AWS_TEST_B}" =~ "ec2" ]]; then
    _VMFAMILY="AWS"
  fi
  _CPU_MX=$(( _CPU_NR * 2 ))
  if [ "${_CPU_MX}" -lt "4" ]; then
    _CPU_MX=4
  fi
  _CPU_TG=$(( _CPU_NR / 2 ))
  if [ "${_CPU_TG}" -lt "4" ]; then
    _CPU_TG=4
  fi
  _CPU_VS=$(( _CPU_NR / 12 ))
  if [ "${_CPU_VS}" -lt "2" ]; then
    _CPU_VS=2
  fi
  PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  if [[ "${PrTestPower}" =~ "POWER" ]] \
    || [[ "${PrTestCluster}" =~ "CLUSTER" ]]; then
    if [ "${_CPU_VS}" -lt "8" ]; then
      _CPU_VS=8
    fi
  fi
  _RAM=$(free -mt | grep Mem: | awk '{ print $2 }' 2>&1)
  if [ "${_RESERVED_RAM}" -gt "0" ]; then
    _RAM=$(( _RAM - _RESERVED_RAM ))
  fi
  _USE=$(( _RAM / 4 ))
  if [ "${_VMFAMILY}" = "VS" ] \
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
    || [[ "${_THISHOST}" =~ ".o8.io" ]] \
    || [[ "${_THISHOST}" =~ ".host8." ]]; then
    if [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.tg.cnf" ]; then
        _USE_SQL=$(( _RAM / 12 ))
      else
        _USE_SQL=$(( _RAM / 24 ))
      fi
    else
      _USE_SQL=$(( _RAM / 8 ))
    fi
  else
    _USE_SQL=$(( _RAM / 8 ))
  fi
  if [ "${_USE_SQL}" -lt "64" ]; then
    _USE_SQL=64
  fi
  _TMP_SQL="${_USE_SQL}M"
  _SRT_SQL=$(( _USE_SQL * 2 ))
  _SRT_SQL="${_SRT_SQL}K"
  if [ "${_USE}" -ge "512" ] && [ "${_USE}" -lt "2048" ]; then
    _USE_PHP=1024
    _USE_OPC=1024
    _USE_CLI=1024
    _QCE_SQL=64M
    _RND_SQL=8M
    _JBF_SQL=4M
    if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
      _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
    else
      _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
    fi
    _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 4 ))
    if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
      _L_NGX_WRKS=${_CPU_MX}
    else
      _L_NGX_WRKS=${_NGINX_WORKERS}
    fi
  elif [ "${_USE}" -ge "2048" ]; then
    if [ "${_VMFAMILY}" = "XEN" ] || [ "${_VMFAMILY}" = "AWS" ]; then
      _USE_PHP=1024
      _USE_OPC=2048
      _USE_CLI=4096
      _QCE_SQL=64M
      _RND_SQL=8M
      _JBF_SQL=4M
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
      else
        _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
      fi
      _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 4 ))
      if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
        _L_NGX_WRKS=${_CPU_MX}
      else
        _L_NGX_WRKS=${_NGINX_WORKERS}
      fi
    elif [ "${_VMFAMILY}" = "VS" ] || [ "${_VMFAMILY}" = "TG" ]; then
      if [ -e "/boot/grub/grub.cfg" ] \
        || [ -e "/boot/grub/menu.lst" ] \
        || [ -e "/root/.tg.cnf" ]; then
        _USE_PHP=1024
        _USE_OPC=2048
        _USE_CLI=4096
        _QCE_SQL=64M
        _RND_SQL=8M
        _JBF_SQL=4M
        if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
          _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
        else
          _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
        fi
        _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 4 ))
        if [ "${_MXC_SQL}" -lt "10" ]; then
          _MXC_SQL=10
        fi
        if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
          _L_NGX_WRKS=${_CPU_TG}
        else
          _L_NGX_WRKS=${_NGINX_WORKERS}
        fi
        sed -i "s/64000/128000/g"  /opt/php81/etc/php81.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php80/etc/php80.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php74/etc/php74.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php73/etc/php73.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php72/etc/php72.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php71/etc/php71.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php70/etc/php70.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php56/etc/php56.ini &> /dev/null
      else
        _USE_PHP=1024
        _USE_OPC=1024
        _USE_CLI=2048
        _QCE_SQL=64M
        _RND_SQL=2M
        _JBF_SQL=2M
        if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
          _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
        else
          _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
        fi
        _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 4 ))
        if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
          _L_NGX_WRKS=${_CPU_VS}
        else
          _L_NGX_WRKS=${_NGINX_WORKERS}
        fi
      fi
    else
      _USE_PHP=512
      _USE_OPC=512
      _USE_CLI=512
      _QCE_SQL=32M
      _RND_SQL=2M
      _JBF_SQL=2M
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
      else
        _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
      fi
      _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 4 ))
      if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
        _L_NGX_WRKS=${_CPU_MX}
      else
        _L_NGX_WRKS=${_NGINX_WORKERS}
      fi
    fi
  else
    _USE_PHP="${_USE}"
    _USE_OPC="${_USE}"
    _USE_CLI="${_USE}"
    _QCE_SQL=32M
    _RND_SQL=1M
    _JBF_SQL=1M
    if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
      _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
    else
      _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
    fi
    _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 4 ))
    if [ "${_NGINX_WORKERS}" = "AUTO" ]; then
      _L_NGX_WRKS=${_CPU_MX}
    else
      _L_NGX_WRKS=${_NGINX_WORKERS}
    fi
  fi
  if [ "${_VMFAMILY}" = "VZ" ]; then
    _USE_OPC=64
  fi
  if [ "${_USE_PHP}" -lt "512" ]; then
    _USE_PHP=512
  fi
  _USE_FPM=$(( _USE_PHP / 2 ))
  if [ "${_USE_FPM}" -lt "395" ]; then
    _USE_FPM=395
  fi
  if [ ! -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
    mkdir -p /var/xdrago/conf
  fi
  if [ ! -e "/data/conf" ]; then
    mkdir -p /data/conf
  fi
  cp -af ${locCnf}/fpm-pool-foo-multi.conf /var/xdrago/conf/
  cp -af ${locCnf}/fpm-pool-foo.conf /var/xdrago/conf/
  cp -af ${locCnf}/hhvm /var/xdrago/conf/
  cp -af ${locCnf}/hhvm/hhvm_intercept.php /data/conf/hhvm_intercept.php
  chmod 644 /data/conf/hhvm_intercept.php
  if [ -e "/opt/etc/fpm/fpm-pool-common.conf" ]; then
    sed -i "s/395/${_USE_FPM}/g" /opt/etc/fpm/fpm-pool-common.conf &> /dev/null
  fi
  _PHP_V="81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/opt/php${e}/etc/php${e}.ini" ]; then
      sed -i "s/395/${_USE_FPM}/g" /opt/php${e}/etc/php${e}.ini &> /dev/null
      wait
      sed -i "s/181/${_USE_OPC}/g" /opt/php${e}/etc/php${e}.ini &> /dev/null
      sed -i "s/395/${_USE_CLI}/g" /opt/php${e}/lib/php.ini     &> /dev/null
    fi
  done
  if [ "${_CUSTOM_CONFIG_SQL}" = "NO" ]; then
    tune_sql_memory_limits
    update_sql_conf
    if [[ "${PrTestPower}" =~ "POWER" ]] \
      || [ -e "/root/.my.cluster_root_pwd.txt" ] \
      || [[ "${PrTestCluster}" =~ "CLUSTER" ]]; then
      _UXC_SQL="${_MXC_SQL}"
    else
      _UXC_SQL=$(echo "scale=0; ${_MXC_SQL}/2" | bc 2>&1)
    fi
    sed -i "s/= 191/= ${_UXC_SQL}/g"                                              /etc/mysql/my.cnf &> /dev/null
    wait
    sed -i "s/= 292/= ${_MXC_SQL}/g"                                              /etc/mysql/my.cnf &> /dev/null
    wait
    sed -i "s/^tmp_table_size.*/tmp_table_size          = ${_TMP_SQL}/g"          /etc/mysql/my.cnf &> /dev/null
    wait
    sed -i "s/^max_heap_table_size.*/max_heap_table_size     = ${_TMP_SQL}/g"     /etc/mysql/my.cnf &> /dev/null
    wait
    sed -i "s/^myisam_sort_buffer_size.*/myisam_sort_buffer_size = ${_SRT_SQL}/g" /etc/mysql/my.cnf &> /dev/null
    wait
    sed -i "s/^read_rnd_buffer_size.*/read_rnd_buffer_size    = ${_RND_SQL}/g"    /etc/mysql/my.cnf &> /dev/null
    wait
    sed -i "s/^join_buffer_size.*/join_buffer_size        = ${_JBF_SQL}/g"        /etc/mysql/my.cnf &> /dev/null
    wait
    if [ ! -z "${_CUSTOM_COLLATION_SQL}" ]; then
      _SYS_COLLATION_SQL=${_CUSTOM_COLLATION_SQL}
    fi
    if [ ! -z "${_SYS_COLLATION_SQL}" ]; then
      sed -i "s/utf8mb4_unicode_ci/${_SYS_COLLATION_SQL}/g"                       /etc/mysql/my.cnf &> /dev/null
      wait
      sed -i "s/utf8mb4_general_ci/${_SYS_COLLATION_SQL}/g"                       /etc/mysql/my.cnf &> /dev/null
    fi
  fi

  _MAX_MEM_REDIS=$(( _RAM / 8 ))
  _MAX_REDIS="${_MAX_MEM_REDIS}MB"
  sed -i "s/^maxmemory .*/maxmemory ${_MAX_REDIS}/g" /etc/redis/redis.conf &> /dev/null

  _USE_JETTY_MEM=$(( _RAM / 8 ))
  _USE_JETTY="-Xmx${_USE_JETTY_MEM}m"
  if [ -e "/etc/default/jetty9" ] && [ -e "/opt/solr4" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms64m ${_USE_JETTY} -Djava.awt.headless=true -Dsolr.solr.home=\/opt\/solr4 \$JAVA_OPTIONS\" # Options/g" /etc/default/jetty9
  fi
  if [ -e "/etc/default/jetty8" ] && [ -e "/opt/solr3" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms64m ${_USE_JETTY} -Djava.awt.headless=true -Dsolr.solr.home=\/opt\/solr3 \$JAVA_OPTIONS\" # Options/g" /etc/default/jetty8
  fi
  if [ -e "/etc/default/jetty7" ] && [ -e "/opt/solr1" ]; then
    sed -i "s/^JAVA_OPTIONS.*/JAVA_OPTIONS=\"-Xms64m ${_USE_JETTY} -Djava.awt.headless=true -Dsolr.solr.home=\/opt\/solr1 \$JAVA_OPTIONS\" # Options/g" /etc/default/jetty7
  fi

  _USE_SOLR_MEM=$(( _RAM / 8 ))
  _USE_SOLR="-Xmx${_USE_SOLR_MEM}m"
  if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
    sed -i "s/^SOLR_HEAP/#SOLR_HEAP/g" /etc/default/solr7.in.sh &> /dev/null
    wait
    sed -i "s/^#SOLR_JAVA_MEM/SOLR_JAVA_MEM/g" /etc/default/solr7.in.sh &> /dev/null
    wait
    sed -i "s/^SOLR_JAVA_MEM=.*/SOLR_JAVA_MEM=\"-Xms64m ${_USE_SOLR}\"/g" /etc/default/solr7.in.sh
    wait
  fi
  tune_web_server_config
}

#
# Fix locales.
fix_locales() {
  ${_INITINS} locales &> /dev/null
  if [ -e "/etc/ssh/sshd_config" ]; then
    _SSH_LC_TEST=$(grep "^AcceptEnv LANG LC_" /etc/ssh/sshd_config 2>&1)
    if [[ "${_SSH_LC_TEST}" =~ "AcceptEnv LANG LC_" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/.*AcceptEnv.*//g" /etc/ssh/sshd_config
      wait
      echo "AcceptEnv LANG LC_*" >> /etc/ssh/sshd_config
    fi
  fi
  if [ -e "/usr/etc/sshd_config" ]; then
    _SSH_LC_TEST=$(grep "^AcceptEnv LANG LC_" /usr/etc/sshd_config 2>&1)
    if [[ "${_SSH_LC_TEST}" =~ "AcceptEnv LANG LC_" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/.*AcceptEnv.*//g" /usr/etc/sshd_config
      wait
      echo "AcceptEnv LANG LC_*" >> /usr/etc/sshd_config
    fi
  fi
  _LOCALE_TEST=BROKEN
  _LOC_TEST=$(locale 2>&1)
  if [[ "${_LOC_TEST}" =~ LANG=.*UTF-8 ]]; then
    _LOCALE_TEST=OK
  fi
  if [ -n "${STY+x}" ]; then
    _LOCALE_TEST=OK
  fi
  if [[ "${_LOC_TEST}" =~ "Cannot" ]]; then
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
    if [ "${_THIS_OS}" = "Debian" ] || [ "${_THIS_OS}" = "Devuan" ]; then
      _LOCALE_GEN_TEST=$(grep -v "^#" /etc/locale.gen 2>&1)
      if [[ ! "${_LOCALE_GEN_TEST}" =~ "en_US.UTF-8 UTF-8" ]]; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
      fi
      sed -i "/^$/d" /etc/locale.gen
      locale-gen &> /dev/null
    fi
    locale-gen en_US.UTF-8 &> /dev/null
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
    export LANG=en_US.UTF-8 &> /dev/null
    export LC_CTYPE=en_US.UTF-8 &> /dev/null
    export LC_COLLATE=POSIX &> /dev/null
    export LC_NUMERIC=POSIX &> /dev/null
    export LC_TIME=en_US.UTF-8 &> /dev/null
    export LC_MONETARY=en_US.UTF-8 &> /dev/null
    export LC_MESSAGES=en_US.UTF-8 &> /dev/null
    export LC_PAPER=en_US.UTF-8 &> /dev/null
    export LC_NAME=en_US.UTF-8 &> /dev/null
    export LC_ADDRESS=en_US.UTF-8 &> /dev/null
    export LC_TELEPHONE=en_US.UTF-8 &> /dev/null
    export LC_MEASUREMENT=en_US.UTF-8 &> /dev/null
    export LC_IDENTIFICATION=en_US.UTF-8 &> /dev/null
    export LC_ALL= &> /dev/null
  else
    if [ -e "${locCnf}/boa.bashrc.txt" ]; then
      cp -af /root/.bashrc /root/.bashrc.bak.${_NOW}
      cp -af ${locCnf}/boa.bashrc.txt /root/.bashrc
      set_xterm
    fi
    if [ "${_THIS_OS}" = "Debian" ] || [ "${_THIS_OS}" = "Devuan" ]; then
      _LOCALE_GEN_TEST=$(grep -v "^#" /etc/locale.gen 2>&1)
      if [[ ! "${_LOCALE_GEN_TEST}" =~ "en_US.UTF-8 UTF-8" ]]; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
      fi
      sed -i "/^$/d" /etc/locale.gen
      locale-gen &> /dev/null
    fi
    locale-gen en_US.UTF-8 &> /dev/null
    # Explicitly enforce locale settings required for consistency
    update-locale \
      LANG=en_US.UTF-8 \
      LC_CTYPE=en_US.UTF-8 \
      LC_COLLATE=POSIX \
      LC_NUMERIC=POSIX \
      LC_ALL= &> /dev/null
    # Define locale settings required for consistency also on the fly
    if [ "${_STATUS}" != "INIT" ]; then
      # On initial install it usually causes a warning:
      # setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8):
      # No such file or directory
      export LC_CTYPE=en_US.UTF-8 &> /dev/null
    fi
    export LC_COLLATE=POSIX &> /dev/null
    export LC_NUMERIC=POSIX &> /dev/null
    export LC_ALL= &> /dev/null
  fi
  _LOCALES_BASHRC_TEST=$(grep LC_COLLATE /root/.bashrc 2>&1)
  if [[ ! "${_LOCALES_BASHRC_TEST}" =~ "LC_COLLATE" ]]; then
    printf "\n" >> /root/.bashrc
    echo "export LANG=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_CTYPE=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_COLLATE=POSIX" >> /root/.bashrc
    echo "export LC_NUMERIC=POSIX" >> /root/.bashrc
    echo "export LC_TIME=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_MONETARY=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_MESSAGES=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_PAPER=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_NAME=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_ADDRESS=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_TELEPHONE=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_MEASUREMENT=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_IDENTIFICATION=en_US.UTF-8" >> /root/.bashrc
    echo "export LC_ALL=" >> /root/.bashrc
    printf "\n" >> /root/.bashrc
  fi
}

#
# Sort and de-duplicate versions in _PHP_MULTI_INSTALL.
php_multi_uniq() {
  _uniqPHPv=
  rm -f /var/backups/_vPHP.txt
  for _vPHP in `echo ${_PHP_MULTI_INSTALL} \
    | sort \
    | uniq`; do
    echo "${_vPHP}" >> /var/backups/_vPHP.txt
  done
  for _vPHP in `cat /var/backups/_vPHP.txt \
    | sort \
    | uniq`; do
    if [ -z "${_uniqPHPv}" ]; then
      _uniqPHPv="${_vPHP}"
    else
      _uniqPHPv="${_uniqPHPv} ${_vPHP}"
    fi
  done
  _PHP_MULTI_INSTALL="${_uniqPHPv}"
}

#
# Read or create Barracuda cnf file.
barracuda_cnf() {
  _CHECK_HOST=$(uname -n 2>&1)
  _VMFAMILY=XEN
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _VMFAMILY="VS"
  fi
  if [ ! -e "${barCnf}" ]; then
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      if [ -e "/root/.auto.up.cnf" ] \
        || [ -e "/root/.host8.cnf" ] \
        || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        || [[ "${_CHECK_HOST}" =~ ".o8.io" ]] \
        || [[ "${_CHECK_HOST}" =~ ".aegir.cc" ]] \
        || [ "${_VMFAMILY}" = "VS" ]; then
        if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
          _DO_NOTHING=YES
        else
          _DO_NOTHING=YES
        fi
      else
        msg "EXIT: Invalid email address defined in the _MY_EMAIL variable"
        msg "EXIT: Bye (1)"
        clean_pid_exit
      fi
    fi
    if [ "${_DB_SERIES}" = "10.4" ] \
      || [ "${_DB_SERIES}" = "10.3" ] \
      || [ "${_DB_SERIES}" = "10.2" ] \
      || [ "${_DB_SERIES}" = "5.7" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _DBS_VRN="${_GALERA_10_VRN}"
      else
        if [ "${_DB_SERIES}" = "10.3" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_3_VRN}"
        elif [ "${_DB_SERIES}" = "10.2" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_2_VRN}"
        elif [ "${_DB_SERIES}" = "10.4" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_4_VRN}"
        elif [ "${_DB_SERIES}" = "5.7" ]; then
          _DB_SERVER=Percona
          _DBS_VRN="${_PERCONA_5_7_VRN}"
        else
          _DB_SERVER=Percona
          _DB_SERIES=5.7
          _DBS_VRN="${_PERCONA_5_7_VRN}"
        fi
      fi
    else
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
      if [ -e "${barCnf}" ]; then
        sed -i "s/^_DB_SERIES=.*/_DB_SERIES=5.7/g" ${barCnf}
        sed -i "s/^_DB_SERVER=.*/_DB_SERVER=Percona/g" ${barCnf}
      fi
    fi

    php_multi_uniq

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
    echo "_DB_SERIES=${_DB_SERIES}"                           >> ${barCnf}
    echo "_DB_SERVER=${_DB_SERVER}"                           >> ${barCnf}
    echo "_USE_MYSQLTUNER=${_USE_MYSQLTUNER}"                 >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_DNS_SETUP_TEST=${_DNS_SETUP_TEST}"                 >> ${barCnf}
    echo "_EXTRA_PACKAGES=${_EXTRA_PACKAGES}"                 >> ${barCnf}
    echo "_FORCE_GIT_MIRROR=\"${_FORCE_GIT_MIRROR}\""         >> ${barCnf}
    echo "_LOCAL_DEVUAN_MIRROR=${_LOCAL_DEVUAN_MIRROR}"       >> ${barCnf}
    echo "_LOCAL_DEBIAN_MIRROR=${_LOCAL_DEBIAN_MIRROR}"       >> ${barCnf}
    echo "_LOCAL_UBUNTU_MIRROR=${_LOCAL_UBUNTU_MIRROR}"       >> ${barCnf}
    echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}"                     >> ${barCnf}
    echo "_SCOUT_KEY=${_SCOUT_KEY}"                           >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_MAGICK_FROM_SOURCES=${_MAGICK_FROM_SOURCES}"       >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}"               >> ${barCnf}
    echo "_NGINX_EXTRA_CONF=\"${_NGINX_EXTRA_CONF}\""         >> ${barCnf}
    echo "_NGINX_FORWARD_SECRECY=${_NGINX_FORWARD_SECRECY}"   >> ${barCnf}
    echo "_NGINX_HEADERS=${_NGINX_HEADERS}"                   >> ${barCnf}
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
    echo "_PHP_IONCUBE=${_PHP_IONCUBE}"                       >> ${barCnf}
    echo "_PHP_GEOS=${_PHP_GEOS}"                             >> ${barCnf}
    echo "_PHP_MONGODB=${_PHP_MONGODB}"                       >> ${barCnf}
    echo "_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\""       >> ${barCnf}
    echo "_PHP_SINGLE_INSTALL=${_PHP_SINGLE_INSTALL}"         >> ${barCnf}

    echo "###"                                                >> ${barCnf}
    echo "_REDIS_LISTEN_MODE=${_REDIS_LISTEN_MODE}"           >> ${barCnf}
    echo "_REDIS_MAJOR_RELEASE=${_REDIS_MAJOR_RELEASE}"       >> ${barCnf}
    echo "_RESERVED_RAM=${_RESERVED_RAM}"                     >> ${barCnf}
    echo "_SPEED_VALID_MAX=${_SPEED_VALID_MAX}"               >> ${barCnf}
    echo "_SSH_ARMOUR=${_SSH_ARMOUR}"                         >> ${barCnf}
    echo "_SSH_FROM_SOURCES=${_SSH_FROM_SOURCES}"             >> ${barCnf}
    echo "_SSH_PORT=${_SSH_PORT}"                             >> ${barCnf}
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
    ### Force HTTP/2 or SPDY plus PFS on supported systems
    sed -i "s/^_NGINX_SPDY=.*/_NGINX_SPDY=YES/g"                 ${barCnf}
    wait
    sed -i "s/^_NGINX_FORWARD.*/_NGINX_FORWARD_SECRECY=YES/g"    ${barCnf}
    wait
    if [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
      || [[ "${_CHECK_HOST}" =~ ".o8.io" ]] \
      || [[ "${_CHECK_HOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      ### Force latest OpenSSH from sources on supported systems
      sed -i "s/^_SSH_FROM_SOURCES=.*/_SSH_FROM_SOURCES=YES/g"   ${barCnf}
      wait
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
        _DO_NOTHING=YES
      else
        devM="deb.devuan.org"
        debM="deb.debian.org"
        sed -i "s/^_AUTOPILOT=.*/_AUTOPILOT=YES/g"                                 ${barCnf}
        wait
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  ${barCnf}
        wait
        sed -i "s/^_LOCAL_DEVUAN_MIRROR=.*/_LOCAL_DEVUAN_MIRROR=${devM}/g"         ${barCnf}
        wait
        sed -i "s/^_LOCAL_DEBIAN_MIRROR=.*/_LOCAL_DEBIAN_MIRROR=${debM}/g"         ${barCnf}
        wait
        sed -i "s/^_MY_EMAIL=.*/_MY_EMAIL=\"notify\@omega8.cc\"/g"                 ${barCnf}
        wait
        sed -i "s/^_STRICT_BIN_PERMISSIONS=.*/_STRICT_BIN_PERMISSIONS=YES/g"       ${barCnf}
        wait
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   ${barCnf}
        wait
        sed -i "s/^_PERMISSIONS_FIX=.*/_PERMISSIONS_FIX=YES/g"                     ${barCnf}
        wait
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  /root/.*.octopus.cnf &> /dev/null
        wait
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   /root/.*.octopus.cnf &> /dev/null
        wait
        if [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ] \
          || [ -e "/root/.test.clstr.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/^_REDIS_LISTEN_MODE=.*/_REDIS_LISTEN_MODE=SOCKET/g"            ${barCnf}
          wait
        fi
        if [ -z "${_PHP_SINGLE_INSTALL}" ]; then
          sed -i "s/^_PHP_CLI_VERSION=5.6/_PHP_CLI_VERSION=7.4/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=5.6/_PHP_FPM_VERSION=7.4/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.0/_PHP_CLI_VERSION=7.4/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.0/_PHP_FPM_VERSION=7.4/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.1/_PHP_CLI_VERSION=7.4/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.1/_PHP_FPM_VERSION=7.4/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.2/_PHP_CLI_VERSION=7.4/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.2/_PHP_FPM_VERSION=7.4/g"                  ${barCnf}
          wait
        fi
        # if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        #   || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        #   || [ "${_VMFAMILY}" = "VS" ]; then
        #   if [ "${_VMFAMILY}" = "VS" ]; then
        #     sed -i "s/^_CPU_CRIT_RATIO=.*/_CPU_CRIT_RATIO=3/g"                     ${barCnf}
        #     wait
        #     sed -i "s/^_CPU_MAX_RATIO=.*/_CPU_MAX_RATIO=2/g"                       ${barCnf}
        #     wait
        #     sed -i "s/^_CPU_SPIDER_RATIO=.*/_CPU_SPIDER_RATIO=1/g"                 ${barCnf}
        #     wait
        #   fi
        # fi
      fi
    fi
    if [ "${_LOCAL_DEBIAN_MIRROR}" = "http.debian.net" ] \
      || [ "${_LOCAL_DEBIAN_MIRROR}" = "httpredir.debian.org" ] \
      || [ "${_LOCAL_DEBIAN_MIRROR}" = "ftp.debian.org" ]; then
      _LOCAL_DEBIAN_MIRROR="deb.debian.org"
      sed -i "s/^_LOCAL_DEBIAN_.*/_LOCAL_DEBIAN_MIRROR=deb.debian.org/g"     ${barCnf}
      wait
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Reading your ${barCnf} config file"
      sleep 1
      msg "NOTE! Please review all config options displayed below"
      msg "NOTE! It will *override* all settings in the Barracuda script"
    fi
    sed -i "s/_SPEED_VALID_MAX=300/_SPEED_VALID_MAX=3600/g" ${barCnf}
    wait

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
    if [[ "${_PHP_CLI_LEGACY_IF_USED_A}" =~ "5.2" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_B}" =~ "5.2" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_C}" =~ "5.2" ]]; then
      if [ -e "/opt/php52/bin/php" ] || [ -e "/etc/init.d/php52-fpm" ]; then
        echo " "
        msg "Legacy PHP-CLI 5.2 is used on this system but will be removed"
      fi
    fi

    _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.2" /data/disk/*/log/fpm.txt 2>&1)
    _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.2" /data/disk/*/static/control/fpm.info 2>&1)
    _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.2" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.2" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.2" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.2" ]]; then
      if [ -e "/opt/php52/bin/php" ] || [ -e "/etc/init.d/php52-fpm" ]; then
        msg "Legacy PHP-FPM 5.2 is used on this system but will be removed"
        echo " "
      fi
    fi

    _PHP_CLI_LEGACY_IF_USED_A=$(grep "5\.3" /data/disk/*/log/cli.txt 2>&1)
    _PHP_CLI_LEGACY_IF_USED_B=$(grep "5\.3" /data/disk/*/static/control/cli.info 2>&1)
    _PHP_CLI_LEGACY_IF_USED_C=$(grep "CLI.*5\.3" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PHP_CLI_LEGACY_IF_USED_A}" =~ "5.3" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_B}" =~ "5.3" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_C}" =~ "5.3" ]]; then
      if [ -e "/opt/php53/bin/php" ] || [ -e "/etc/init.d/php53-fpm" ]; then
        echo " "
        msg "Legacy PHP-CLI 5.3 is used on this system but will be removed"
      fi
    fi

    _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.3" /data/disk/*/log/fpm.txt 2>&1)
    _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.3" /data/disk/*/static/control/fpm.info 2>&1)
    _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.3" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.3" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.3" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.3" ]]; then
      if [ -e "/opt/php53/bin/php" ] || [ -e "/etc/init.d/php53-fpm" ]; then
        msg "Legacy PHP-FPM 5.3 is used on this system but will be removed"
        echo " "
      fi
    fi

    _PHP_CLI_LEGACY_IF_USED_A=$(grep "5\.4" /data/disk/*/log/cli.txt 2>&1)
    _PHP_CLI_LEGACY_IF_USED_B=$(grep "5\.4" /data/disk/*/static/control/cli.info 2>&1)
    _PHP_CLI_LEGACY_IF_USED_C=$(grep "CLI.*5\.4" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PHP_CLI_LEGACY_IF_USED_A}" =~ "5.4" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_B}" =~ "5.4" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_C}" =~ "5.4" ]]; then
      if [ -e "/opt/php54/bin/php" ] || [ -e "/etc/init.d/php54-fpm" ]; then
        echo " "
        msg "Legacy PHP-CLI 5.4 is used on this system but will be removed"
      fi
    fi

    _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.4" /data/disk/*/log/fpm.txt 2>&1)
    _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.4" /data/disk/*/static/control/fpm.info 2>&1)
    _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.4" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.4" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.4" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.4" ]]; then
      if [ -e "/opt/php54/bin/php" ] || [ -e "/etc/init.d/php54-fpm" ]; then
        msg "Legacy PHP-FPM 5.4 is used on this system but will be removed"
        echo " "
      fi
    fi

    _PHP_CLI_LEGACY_IF_USED_A=$(grep "5\.5" /data/disk/*/log/cli.txt 2>&1)
    _PHP_CLI_LEGACY_IF_USED_B=$(grep "5\.5" /data/disk/*/static/control/cli.info 2>&1)
    _PHP_CLI_LEGACY_IF_USED_C=$(grep "CLI.*5\.5" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PHP_CLI_LEGACY_IF_USED_A}" =~ "5.5" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_B}" =~ "5.5" ]] \
      || [[ "${_PHP_CLI_LEGACY_IF_USED_C}" =~ "5.5" ]]; then
      if [ -e "/opt/php55/bin/php" ] || [ -e "/etc/init.d/php55-fpm" ]; then
        echo " "
        msg "Legacy PHP-CLI 5.5 is used on this system but will be removed"
      fi
    fi

    _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.5" /data/disk/*/log/fpm.txt 2>&1)
    _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.5" /data/disk/*/static/control/fpm.info 2>&1)
    _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.5" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.5" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.5" ]] \
      || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.5" ]]; then
      if [ -e "/opt/php55/bin/php" ] || [ -e "/etc/init.d/php55-fpm" ]; then
        msg "Legacy PHP-FPM 5.5 is used on this system but will be removed"
        echo " "
      fi
    fi

    _PHP_MULTI_INSTALL_TEST=$(grep _PHP_MULTI_INSTALL ${barCnf} 2>&1)

    if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.2" ]]; then
      _R_M=5.2
      _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
      sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${barCnf}
      wait
      sed -i "/^$/d" ${barCnf}
      wait
    fi

    if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.3" ]]; then
      _R_M=5.3
      _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
      sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${barCnf}
      wait
      sed -i "/^$/d" ${barCnf}
      wait
    fi

    if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.4" ]]; then
      _R_M=5.4
      _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
      sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${barCnf}
      wait
      sed -i "/^$/d" ${barCnf}
      wait
    fi

    if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.5" ]]; then
      _R_M=5.5
      _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
      sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${barCnf}
      wait
      sed -i "/^$/d" ${barCnf}
      wait
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
    if [ -e "/etc/init.d/php53-fpm" ]; then
      mrun "service php53-fpm stop" &> /dev/null
      update-rc.d -f php53-fpm remove &> /dev/null
      rm -f /etc/init.d/php53-fpm
    fi
    if [ -e "/etc/init.d/php54-fpm" ]; then
      mrun "service php54-fpm stop" &> /dev/null
      update-rc.d -f php54-fpm remove &> /dev/null
      rm -f /etc/init.d/php54-fpm
    fi
    if [ -e "/etc/init.d/php55-fpm" ]; then
      mrun "service php55-fpm stop" &> /dev/null
      update-rc.d -f php55-fpm remove &> /dev/null
      rm -f /etc/init.d/php55-fpm
    fi

    _CHECK_HOST=$(uname -n 2>&1)
    _VMFAMILY=XEN
    _VM_TEST=$(uname -a 2>&1)
    if [[ "${_VM_TEST}" =~ "-beng" ]]; then
      _VMFAMILY="VS"
    fi
    if [ -e "/root/.auto.up.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
      || [[ "${_CHECK_HOST}" =~ ".o8.io" ]] \
      || [[ "${_CHECK_HOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _PHP_OVERRIDE=$(grep _PHP_FPM_VERSION ${barCnf} \
          | cut -d= -f2 \
          | awk '{ print $1}' \
          | sed "s/[\"]//g" 2>&1)
        _CLSTR_PHP_MULTI_INSTALL="${_PHP_OVERRIDE}"
        _CLSTR_PHP_MULTI_INSTALL="7.3 5.6"
      fi
      if [ ! -e "/root/.debug.cnf" ] || [ -e "/root/.default.cnf" ]; then
        sed -i "s/^_PHP_MULTI_INSTALL.*//g" ${barCnf}
        wait
        sed -i "/^$/d" ${barCnf}
        wait
        _PHP_MULTI_INSTALL=""
      fi
    fi

    _PHP_MULTI_INSTALL_TEST=$(grep _PHP_MULTI_INSTALL ${barCnf} 2>&1)
    if [ -z "${_PHP_MULTI_INSTALL_TEST}" ]; then
      rm -f /root/.sorted.multi.php.cnf
    fi

    if [ -e "/root/.sorted.multi.php.cnf" ]; then
      _DO_NOTHING=YES
    else
      if [ -e "/var/aegir/host_master/000/placeholder_dont_remove.txt" ]; then
        if [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ]; then
          if [ ! -z "${_CLSTR_PHP_MULTI_INSTALL}" ]; then
            _PHP_MULTI_INSTALL="${_CLSTR_PHP_MULTI_INSTALL}"
          else
            _PHP_MULTI_INSTALL="7.2"
          fi
        else
          ### Make sure that _PHP_SINGLE_INSTALL takes precedence
          if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
            if [ "${_PHP_SINGLE_INSTALL}" = "8.1" ] \
              || [ "${_PHP_SINGLE_INSTALL}" = "8.0" ] \
              || [ "${_PHP_SINGLE_INSTALL}" = "7.4" ] \
              || [ "${_PHP_SINGLE_INSTALL}" = "7.3" ]; then
              _PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}
              _PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}
              _PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}
            fi
          else
            if [ -e "/data/disk/arch/sql" ]; then
              _local_PHP_MULTI_INSTALL=

              _is_PHP_multi_five_six=$(grep "5\.6" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_five_six=$(grep "5\.6" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_five_six=$(grep "5\.6" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_five_six=
              if [[ "${_is_PHP_multi_five_six}" =~ "5.6" ]] \
                || [[ "${_is_PHP_FPM_five_six}" =~ "5.6" ]] \
                || [[ "${_is_PHP_CLI_five_six}" =~ "5.6" ]]; then
                _is_PHP_five_six=5.6
                if [ "${_is_PHP_five_six}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_PHP_FPM_VERSION} ${_is_PHP_five_six}"
                fi
              fi

              _is_PHP_multi_seven_zero=$(grep "7\.0" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_seven_zero=$(grep "7\.0" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_seven_zero=$(grep "7\.0" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_seven_zero=
              if [[ "${_is_PHP_multi_seven_zero}" =~ "7.0" ]] \
                || [[ "${_is_PHP_FPM_seven_zero}" =~ "7.0" ]] \
                || [[ "${_is_PHP_CLI_seven_zero}" =~ "7.0" ]]; then
                _is_PHP_seven_zero=7.0
                if [ "${_is_PHP_seven_zero}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_zero}"
                fi
              fi

              _is_PHP_multi_seven_one=$(grep "7\.1" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_seven_one=$(grep "7\.1" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_seven_one=$(grep "7\.1" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_seven_one=
              if [[ "${_is_PHP_multi_seven_one}" =~ "7.1" ]] \
                || [[ "${_is_PHP_FPM_seven_one}" =~ "7.1" ]] \
                || [[ "${_is_PHP_CLI_seven_one}" =~ "7.1" ]]; then
                _is_PHP_seven_one=7.1
                if [ "${_is_PHP_seven_one}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_one}"
                fi
              fi

              _is_PHP_multi_seven_two=$(grep "7\.2" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_seven_two=$(grep "7\.2" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_seven_two=$(grep "7\.2" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_seven_two=
              if [[ "${_is_PHP_multi_seven_two}" =~ "7.2" ]] \
                || [[ "${_is_PHP_FPM_seven_two}" =~ "7.2" ]] \
                || [[ "${_is_PHP_CLI_seven_two}" =~ "7.2" ]]; then
                _is_PHP_seven_two=7.2
                if [ "${_is_PHP_seven_two}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_two}"
                fi
              fi

              _is_PHP_multi_seven_three=$(grep "7\.3" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_seven_three=$(grep "7\.3" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_seven_three=$(grep "7\.3" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_seven_three=
              if [[ "${_is_PHP_multi_seven_three}" =~ "7.3" ]] \
                || [[ "${_is_PHP_FPM_seven_three}" =~ "7.3" ]] \
                || [[ "${_is_PHP_CLI_seven_three}" =~ "7.3" ]]; then
                _is_PHP_seven_three=7.3
                if [ "${_is_PHP_seven_three}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_three}"
                fi
              fi

              _is_PHP_multi_seven_four=$(grep "7\.4" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_seven_four=$(grep "7\.4" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_seven_four=$(grep "7\.4" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_seven_four=
              if [[ "${_is_PHP_multi_seven_four}" =~ "7.4" ]] \
                || [[ "${_is_PHP_FPM_seven_four}" =~ "7.4" ]] \
                || [[ "${_is_PHP_CLI_seven_four}" =~ "7.4" ]]; then
                _is_PHP_seven_four=7.4
                if [ "${_is_PHP_seven_four}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_four}"
                fi
              fi

              _is_PHP_multi_eight_zero=$(grep "8\.0" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_eight_zero=$(grep "8\.0" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_eight_zero=$(grep "8\.0" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_eight_zero=
              if [[ "${_is_PHP_multi_eight_zero}" =~ "8.0" ]] \
                || [[ "${_is_PHP_FPM_eight_zero}" =~ "8.0" ]] \
                || [[ "${_is_PHP_CLI_eight_zero}" =~ "8.0" ]]; then
                _is_PHP_eight_zero=8.0
                if [ "${_is_PHP_eight_zero}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_eight_zero}"
                fi
              fi

              _is_PHP_multi_eight_one=$(grep "8\.1" /data/disk/*/static/control/multi-fpm.info 2>&1)
              _is_PHP_FPM_eight_one=$(grep "8\.1" /data/disk/*/static/control/fpm.info 2>&1)
              _is_PHP_CLI_eight_one=$(grep "8\.1" /data/disk/*/static/control/cli.info 2>&1)
              _is_PHP_eight_one=
              if [[ "${_is_PHP_multi_eight_one}" =~ "8.1" ]] \
                || [[ "${_is_PHP_FPM_eight_one}" =~ "8.1" ]] \
                || [[ "${_is_PHP_CLI_eight_one}" =~ "8.1" ]]; then
                _is_PHP_eight_one=8.1
                if [ "${_is_PHP_eight_one}" != "${_PHP_FPM_VERSION}" ]; then
                  _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_eight_one}"
                fi
              fi

              _PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL}"
              if [ -z "${_PHP_MULTI_INSTALL}" ]; then
                _PHP_MULTI_INSTALL="7.4 7.3"
              fi
            fi
          fi
        fi
      fi
      ### Make sure that _PHP_SINGLE_INSTALL takes precedence
      if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
        if [ "${_PHP_SINGLE_INSTALL}" = "8.1" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "8.0" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "7.4" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "7.3" ]; then
          _PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}
          _PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}
          _PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}
        fi
      else
        _PHP_MULTI_INSTALL_TEST=$(grep _PHP_MULTI_INSTALL ${barCnf} 2>&1)
        if [[ ! "${_PHP_MULTI_INSTALL_TEST}" =~ "7.3" ]]; then
          if [ -z "${_PHP_MULTI_INSTALL}" ]; then
            _PHP_MULTI_INSTALL="7.3"
          else
            _PHP_MULTI_INSTALL="7.3 ${_PHP_MULTI_INSTALL}"
          fi
        fi
        if [[ ! "${_PHP_MULTI_INSTALL_TEST}" =~ "7.4" ]]; then
          if [ -z "${_PHP_MULTI_INSTALL}" ]; then
            _PHP_MULTI_INSTALL="7.4"
          else
            _PHP_MULTI_INSTALL="7.4 ${_PHP_MULTI_INSTALL}"
          fi
        fi
        if [ -e "/root/.host8.cnf" ]; then
          if [[ ! "${_PHP_MULTI_INSTALL_TEST}" =~ "8.0" ]] \
            || [[ ! "${_PHP_MULTI_INSTALL_TEST}" =~ "8.1" ]]; then
            _PHP_MULTI_INSTALL="8.0 8.1 ${_PHP_MULTI_INSTALL}"
          fi
        fi
      fi

      php_multi_uniq

      if [ ! -z "${_PHP_MULTI_INSTALL}" ]; then
        _PHP_MULTI_TEST=$(grep _PHP_MULTI_INSTALL ${barCnf} 2>&1)
        if [[ "${_PHP_MULTI_TEST}" =~ "_PHP_MULTI_INSTALL" ]]; then
          sed -i "s/^_PHP_MULTI_INSTALL.*//g" ${barCnf}
          sed -i "/^$/d" ${barCnf}
        fi
        echo "_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"" >> ${barCnf}
      fi
      touch /root/.sorted.multi.php.cnf
      rm -f /root/.updated.multi.php.cnf
      rm -f /root/.fixed.multi.php.cnf
    fi

    _PHP_FPM_VERSION_TEST=$(grep _PHP_FPM_VERSION ${barCnf} 2>&1)
    if [[ ! "${_PHP_FPM_VERSION_TEST}" =~ "_PHP_FPM_VERSION" ]]; then
      echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}" >> ${barCnf}
    fi

    _PHP_CLI_VERSION_TEST=$(grep _PHP_CLI_VERSION ${barCnf} 2>&1)
    if [[ ! "${_PHP_CLI_VERSION_TEST}" =~ "_PHP_CLI_VERSION" ]]; then
      echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}" >> ${barCnf}
    fi

    _PHP_SINGLE_INSTALL_TEST=$(grep _PHP_SINGLE_INSTALL ${barCnf} 2>&1)
    if [[ ! "${_PHP_SINGLE_INSTALL_TEST}" =~ "_PHP_SINGLE_INSTALL" ]]; then
      echo "_PHP_SINGLE_INSTALL=${_PHP_SINGLE_INSTALL}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_LSHELL_TEST=$(grep _CUSTOM_CONFIG_LSHELL ${barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_LSHELL_TEST}" =~ "_CUSTOM_CONFIG_LSHELL" ]]; then
      echo "_CUSTOM_CONFIG_LSHELL=${_CUSTOM_CONFIG_LSHELL}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_CSF_TEST=$(grep _CUSTOM_CONFIG_CSF ${barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_CSF_TEST}" =~ "_CUSTOM_CONFIG_CSF" ]]; then
      echo "_CUSTOM_CONFIG_CSF=${_CUSTOM_CONFIG_CSF}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_SQL_TEST=$(grep _CUSTOM_CONFIG_SQL ${barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_SQL_TEST}" =~ "_CUSTOM_CONFIG_SQL" ]]; then
      echo "_CUSTOM_CONFIG_SQL=${_CUSTOM_CONFIG_SQL}" >> ${barCnf}
    fi

    _SPEED_VALID_MAX_TEST=$(grep _SPEED_VALID_MAX ${barCnf} 2>&1)
    if [[ ! "${_SPEED_VALID_MAX_TEST}" =~ "_SPEED_VALID_MAX" ]]; then
      echo "_SPEED_VALID_MAX=${_SPEED_VALID_MAX}" >> ${barCnf}
    fi

    _NGINX_DOS_LIMIT_TEST=$(grep _NGINX_DOS_LIMIT ${barCnf} 2>&1)
    if [[ ! "${_NGINX_DOS_LIMIT_TEST}" =~ "_NGINX_DOS_LIMIT" ]]; then
      echo "_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}" >> ${barCnf}
    fi

    _CPU_SPIDER_RATIO_TEST=$(grep _CPU_SPIDER_RATIO ${barCnf} 2>&1)
    if [[ ! "${_CPU_SPIDER_RATIO_TEST}" =~ "_CPU_SPIDER_RATIO" ]]; then
      echo "_CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO}" >> ${barCnf}
    fi

    _CPU_MAX_RATIO_TEST=$(grep _CPU_MAX_RATIO ${barCnf} 2>&1)
    if [[ ! "${_CPU_MAX_RATIO_TEST}" =~ "_CPU_MAX_RATIO" ]]; then
      echo "_CPU_MAX_RATIO=${_CPU_MAX_RATIO}" >> ${barCnf}
    fi

    _CPU_CRIT_RATIO_TEST=$(grep _CPU_CRIT_RATIO ${barCnf} 2>&1)
    if [[ ! "${_CPU_CRIT_RATIO_TEST}" =~ "_CPU_CRIT_RATIO" ]]; then
      echo "_CPU_CRIT_RATIO=${_CPU_CRIT_RATIO}" >> ${barCnf}
    fi

    _SYSTEM_UPGRADE_ONLY_TEST=$(grep _SYSTEM_UPGRADE_ONLY ${barCnf} 2>&1)
    if [[ ! "${_SYSTEM_UPGRADE_ONLY_TEST}" =~ "_SYSTEM_UPGRADE_ONLY" ]]; then
      echo "_SYSTEM_UPGRADE_ONLY=${_SYSTEM_UPGRADE_ONLY}" >> ${barCnf}
    fi

    _AEGIR_UPGRADE_ONLY_TEST=$(grep _AEGIR_UPGRADE_ONLY ${barCnf} 2>&1)
    if [[ ! "${_AEGIR_UPGRADE_ONLY_TEST}" =~ "_AEGIR_UPGRADE_ONLY" ]]; then
      echo "_AEGIR_UPGRADE_ONLY=${_AEGIR_UPGRADE_ONLY}" >> ${barCnf}
    fi

    _CUSTOM_CONFIG_REDIS_TEST=$(grep _CUSTOM_CONFIG_REDIS ${barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_REDIS_TEST}" =~ "_CUSTOM_CONFIG_REDIS" ]]; then
      echo "_CUSTOM_CONFIG_REDIS=${_CUSTOM_CONFIG_REDIS}" >> ${barCnf}
    fi

    _NEWRELIC_KEY_TEST=$(grep _NEWRELIC_KEY ${barCnf} 2>&1)
    if [[ ! "${_NEWRELIC_KEY_TEST}" =~ "_NEWRELIC_KEY" ]]; then
      if [ ! -z "${_NEWRELIC_KEY}" ]; then
        echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}" >> ${barCnf}
      else
        if [ -e "/etc/newrelic/newrelic.cfg" ]; then
          _NEWRELIC_KEY=$(grep license_key /etc/newrelic/newrelic.cfg 2>&1)
          _NEWRELIC_KEY=$(echo -n ${_NEWRELIC_KEY} | tr -d "\n" 2>&1)
          echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}" >> ${barCnf}
          sed -i "s/license_key=//g" ${barCnf}
          wait
        fi
      fi
    fi

    _SCOUT_KEY_TEST=$(grep _SCOUT_KEY ${barCnf} 2>&1)
    if [[ ! "${_SCOUT_KEY_TEST}" =~ "_SCOUT_KEY" ]]; then
      echo "_SCOUT_KEY=${_SCOUT_KEY}" >> ${barCnf}
    fi

    _EXTRA_PACKAGES_TEST=$(grep _EXTRA_PACKAGES ${barCnf} 2>&1)
    if [[ ! "${_EXTRA_PACKAGES_TEST}" =~ "_EXTRA_PACKAGES" ]]; then
      echo "_EXTRA_PACKAGES=${_EXTRA_PACKAGES}" >> ${barCnf}
    fi

    _PHP_EXTRA_CONF_TEST=$(grep _PHP_EXTRA_CONF ${barCnf} 2>&1)
    if [[ ! "${_PHP_EXTRA_CONF_TEST}" =~ "_PHP_EXTRA_CONF" ]]; then
      echo "_PHP_EXTRA_CONF=\"${_PHP_EXTRA_CONF}\"" >> ${barCnf}
    fi

    _PHP_FPM_DENY_TEST=$(grep _PHP_FPM_DENY ${barCnf} 2>&1)
    if [[ ! "${_PHP_FPM_DENY_TEST}" =~ "_PHP_FPM_DENY" ]]; then
      echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\"" >> ${barCnf}
    fi

    _STRONG_PASSWORDS_TEST=$(grep _STRONG_PASSWORDS ${barCnf} 2>&1)
    if [[ ! "${_STRONG_PASSWORDS_TEST}" =~ "_STRONG_PASSWORDS" ]]; then
      echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}" >> ${barCnf}
    fi

    _DB_BINARY_LOG_TEST=$(grep _DB_BINARY_LOG ${barCnf} 2>&1)
    if [[ ! "${_DB_BINARY_LOG_TEST}" =~ "_DB_BINARY_LOG" ]]; then
      echo "_DB_BINARY_LOG=${_DB_BINARY_LOG}" >> ${barCnf}
    fi

    _USE_MYSQLTUNER_TEST=$(grep _USE_MYSQLTUNER ${barCnf} 2>&1)
    if [[ ! "${_USE_MYSQLTUNER_TEST}" =~ "_USE_MYSQLTUNER" ]]; then
      echo "_USE_MYSQLTUNER=${_USE_MYSQLTUNER}" >> ${barCnf}
    fi

    _REDIS_LISTEN_MODE_TEST=$(grep _REDIS_LISTEN_MODE ${barCnf} 2>&1)
    if [[ ! "${_REDIS_LISTEN_MODE_TEST}" =~ "_REDIS_LISTEN_MODE" ]]; then
      echo "_REDIS_LISTEN_MODE=${_REDIS_LISTEN_MODE}" >> ${barCnf}
    fi

    _REDIS_MAJOR_RELEASE_TEST=$(grep _REDIS_MAJOR_RELEASE ${barCnf} 2>&1)
    if [[ ! "${_REDIS_MAJOR_RELEASE_TEST}" =~ "_REDIS_MAJOR_RELEASE" ]]; then
      echo "_REDIS_MAJOR_RELEASE=${_REDIS_MAJOR_RELEASE}" >> ${barCnf}
    fi

    _NGINX_HEADERS_TEST=$(grep _NGINX_HEADERS ${barCnf} 2>&1)
    if [[ ! "${_NGINX_HEADERS_TEST}" =~ "_NGINX_HEADERS" ]]; then
      echo "_NGINX_HEADERS=${_NGINX_HEADERS}" >> ${barCnf}
    fi

    _NGINX_LDAP_TEST=$(grep _NGINX_LDAP ${barCnf} 2>&1)
    if [[ ! "${_NGINX_LDAP_TEST}" =~ "_NGINX_LDAP" ]]; then
      echo "_NGINX_LDAP=${_NGINX_LDAP}" >> ${barCnf}
    fi

    _NGINX_NAXSI_TEST=$(grep _NGINX_NAXSI ${barCnf} 2>&1)
    if [[ ! "${_NGINX_NAXSI_TEST}" =~ "_NGINX_NAXSI" ]]; then
      echo "_NGINX_NAXSI=${_NGINX_NAXSI}" >> ${barCnf}
    fi

    _NGINX_SPDY_TEST=$(grep _NGINX_SPDY ${barCnf} 2>&1)
    if [[ ! "${_NGINX_SPDY_TEST}" =~ "_NGINX_SPDY" ]]; then
      echo "_NGINX_SPDY=${_NGINX_SPDY}" >> ${barCnf}
    fi

    _NGINX_FORWARD_SECRECY_TEST=$(grep _NGINX_FORWARD_SECRECY ${barCnf} 2>&1)
    if [[ ! "${_NGINX_FORWARD_SECRECY_TEST}" =~ "_NGINX_FORWARD_SECRECY" ]]; then
      echo "_NGINX_FORWARD_SECRECY=${_NGINX_FORWARD_SECRECY}" >> ${barCnf}
    fi

    _PHP_IONCUBE_TEST=$(grep _PHP_IONCUBE ${barCnf} 2>&1)
    if [[ ! "${_PHP_IONCUBE_TEST}" =~ "_PHP_IONCUBE" ]]; then
      echo "_PHP_IONCUBE=${_PHP_IONCUBE}" >> ${barCnf}
    fi

    _PHP_GEOS_TEST=$(grep _PHP_GEOS ${barCnf} 2>&1)
    if [[ ! "${_PHP_GEOS_TEST}" =~ "_PHP_GEOS" ]]; then
      echo "_PHP_GEOS=${_PHP_GEOS}" >> ${barCnf}
    fi

    _PHP_MONGODB_TEST=$(grep _PHP_MONGODB ${barCnf} 2>&1)
    if [[ ! "${_PHP_MONGODB_TEST}" =~ "_PHP_MONGODB" ]]; then
      echo "_PHP_MONGODB=${_PHP_MONGODB}" >> ${barCnf}
    fi

    _PERMISSIONS_FIX_TEST=$(grep _PERMISSIONS_FIX ${barCnf} 2>&1)
    if [[ ! "${_PERMISSIONS_FIX_TEST}" =~ "_PERMISSIONS_FIX" ]]; then
      echo "_PERMISSIONS_FIX=${_PERMISSIONS_FIX}" >> ${barCnf}
    fi

    _MODULES_FIX_TEST=$(grep _MODULES_FIX ${barCnf} 2>&1)
    if [[ ! "${_MODULES_FIX_TEST}" =~ "_MODULES_FIX" ]]; then
      echo "_MODULES_FIX=${_MODULES_FIX}" >> ${barCnf}
    fi

    _MODULES_SKIP_TEST=$(grep _MODULES_SKIP ${barCnf} 2>&1)
    if [[ ! "${_MODULES_SKIP_TEST}" =~ "_MODULES_SKIP" ]]; then
      echo "_MODULES_SKIP=\"${_MODULES_SKIP}\"" >> ${barCnf}
    fi

    _SSH_FROM_SOURCES_TEST=$(grep _SSH_FROM_SOURCES ${barCnf} 2>&1)
    if [[ ! "${_SSH_FROM_SOURCES_TEST}" =~ "_SSH_FROM_SOURCES" ]]; then
      echo "_SSH_FROM_SOURCES=${_SSH_FROM_SOURCES}" >> ${barCnf}
    fi

    _SSH_ARMOUR_TEST=$(grep _SSH_ARMOUR ${barCnf} 2>&1)
    if [[ ! "${_SSH_ARMOUR_TEST}" =~ "_SSH_ARMOUR" ]]; then
      echo "_SSH_ARMOUR=${_SSH_ARMOUR}" >> ${barCnf}
    fi

    _MAGICK_FROM_SOURCES_TEST=$(grep _MAGICK_FROM_SOURCES ${barCnf} 2>&1)
    if [[ ! "${_MAGICK_FROM_SOURCES_TEST}" =~ "_MAGICK_FROM_SOURCES" ]]; then
      echo "_MAGICK_FROM_SOURCES=${_MAGICK_FROM_SOURCES}" >> ${barCnf}
    fi

    _RESERVED_RAM_TEST=$(grep _RESERVED_RAM ${barCnf} 2>&1)
    if [[ ! "${_RESERVED_RAM_TEST}" =~ "_RESERVED_RAM" ]]; then
      echo "_RESERVED_RAM=${_RESERVED_RAM}" >> ${barCnf}
    fi

    _STRICT_BIN_PERMISSIONS_TEST=$(grep _STRICT_BIN_PERMISSIONS ${barCnf} 2>&1)
    if [[ ! "${_STRICT_BIN_PERMISSIONS_TEST}" =~ "_STRICT_BIN_PERMISSIONS" ]]; then
      echo "_STRICT_BIN_PERMISSIONS=${_STRICT_BIN_PERMISSIONS}" >> ${barCnf}
    fi

    _DB_SERIES_TEST=$(grep _DB_SERIES ${barCnf} 2>&1)
    if [[ ! "${_DB_SERIES_TEST}" =~ "_DB_SERIES" ]]; then
      echo "_DB_SERIES=${_DB_SERIES}" >> ${barCnf}
    fi

    if [ -e "/etc/init.d/tomcat" ]; then
      echo "_TOMCAT_TO_JETTY=YES" >> ${barCnf}
    fi

    ###
    ### config cleanup start
    ###
    _DB_ENGINE_TEST=$(grep _DB_ENGINE ${barCnf} 2>&1)
    if [[ "${_DB_ENGINE_TEST}" =~ "_DB_ENGINE" ]]; then
      sed -i "s/^_DB_ENGINE.*//g" ${barCnf}
      wait
    fi
    _INNODB_LOG_FILE_SIZE_TEST=$(grep _INNODB_LOG_FILE_SIZE ${barCnf} 2>&1)
    if [[ "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "_INNODB_LOG_FILE_SIZE" ]]; then
      sed -i "s/^_INNODB_LOG_FILE_SIZE.*//g" ${barCnf}
      wait
    fi
    _USE_STOCK_TEST=$(grep _USE_STOCK ${barCnf} 2>&1)
    if [[ "${_USE_STOCK_TEST}" =~ "_USE_STOCK" ]]; then
      sed -i "s/^_USE_STOCK.*//g" ${barCnf}
      wait
    fi
    _HTTP_WILDCARD_TEST=$(grep _HTTP_WILDCARD ${barCnf} 2>&1)
    if [[ "${_HTTP_WILDCARD_TEST}" =~ "_HTTP_WILDCARD" ]]; then
      sed -i "s/^_HTTP_WILDCARD.*//g" ${barCnf}
      wait
    fi
    _PHP_MODERN_ONLY_TEST=$(grep _PHP_MODERN_ONLY ${barCnf} 2>&1)
    if [[ "${_PHP_MODERN_ONLY_TEST}" =~ "_PHP_MODERN_ONLY" ]]; then
      sed -i "s/^_PHP_MODERN_ONLY.*//g" ${barCnf}
      wait
    fi
    _USE_SPEED_BOOSTER_TEST=$(grep _USE_SPEED_BOOSTER ${barCnf} 2>&1)
    if [[ "${_USE_SPEED_BOOSTER_TEST}" =~ "_USE_SPEED_BOOSTER" ]]; then
      sed -i "s/^_USE_SPEED_BOOSTER.*//g" ${barCnf}
      wait
    fi
    _PHP_INSTALL_NEW_TEST=$(grep _PHP_INSTALL_NEW ${barCnf} 2>&1)
    if [[ "${_PHP_INSTALL_NEW_TEST}" =~ "_PHP_INSTALL_NEW" ]]; then
      sed -i "s/^_PHP_INSTALL_NEW.*//g" ${barCnf}
      wait
    fi
    _CUSTOM_CONFIG_PHP_TEST=$(grep _CUSTOM_CONFIG_PHP ${barCnf} 2>&1)
    if [[ "${_CUSTOM_CONFIG_PHP_TEST}" =~ "_CUSTOM_CONFIG_PHP" ]]; then
      sed -i "s/^_CUSTOM_CONFIG_PHP.*//g" ${barCnf}
      wait
    fi
    _LOAD_LIMIT_ONE_TEST=$(grep _LOAD_LIMIT_ONE ${barCnf} 2>&1)
    if [[ "${_LOAD_LIMIT_ONE_TEST}" =~ "_LOAD_LIMIT_ONE" ]]; then
      sed -i "s/^_LOAD_LIMIT_ONE.*//g" ${barCnf}
      wait
    fi
    _LOAD_LIMIT_TWO_TEST=$(grep _LOAD_LIMIT_TWO ${barCnf} 2>&1)
    if [[ "${_LOAD_LIMIT_TWO_TEST}" =~ "_LOAD_LIMIT_TWO" ]]; then
      sed -i "s/^_LOAD_LIMIT_TWO.*//g" ${barCnf}
      wait
    fi
    _USE_MEMCACHED_TEST=$(grep _USE_MEMCACHED ${barCnf} 2>&1)
    if [[ "${_USE_MEMCACHED_TEST}" =~ "_USE_MEMCACHED" ]]; then
      sed -i "s/^_USE_MEMCACHED.*//g" ${barCnf}
      wait
    fi
    _PHP_ZEND_OPCACHE_TEST=$(grep _PHP_ZEND_OPCACHE ${barCnf} 2>&1)
    if [[ "${_PHP_ZEND_OPCACHE_TEST}" =~ "_PHP_ZEND_OPCACHE" ]]; then
      sed -i "s/^_PHP_ZEND_OPCACHE.*//g" ${barCnf}
      wait
    fi
    _BUILD_FROM_SRC_TEST=$(grep _BUILD_FROM_SRC ${barCnf} 2>&1)
    if [[ "${_BUILD_FROM_SRC_TEST}" =~ "_BUILD_FROM_SRC" ]]; then
      sed -i "s/^_BUILD_FROM_SRC.*//g" ${barCnf}
      wait
    fi
    _SSL_FROM_SOURCES_TEST=$(grep _SSL_FROM_SOURCES ${barCnf} 2>&1)
    if [[ "${_SSL_FROM_SOURCES_TEST}" =~ "_SSL_FROM_SOURCES" ]]; then
      sed -i "s/^_SSL_FROM_SOURCES.*//g" ${barCnf}
      wait
    fi
    ###
    ### config cleanup end
    ###

    sleep 1
    _CHECK_HOST=$(uname -n 2>&1)
    ### Force HTTP/2 or SPDY plus PFS on supported systems
    sed -i "s/^_NGINX_SPDY=.*/_NGINX_SPDY=YES/g"                 ${barCnf}
    wait
    sed -i "s/^_NGINX_FORWARD.*/_NGINX_FORWARD_SECRECY=YES/g"    ${barCnf}
    wait
    if [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
      || [[ "${_CHECK_HOST}" =~ ".o8.io" ]] \
      || [[ "${_CHECK_HOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      ### Force latest OpenSSH from sources on supported systems
      sed -i "s/^_SSH_FROM_SOURCES=.*/_SSH_FROM_SOURCES=YES/g"   ${barCnf}
      wait
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
        _DO_NOTHING=YES
      else
        devM="deb.devuan.org"
        debM="deb.debian.org"
        sed -i "s/^_AUTOPILOT=.*/_AUTOPILOT=YES/g"                                 ${barCnf}
        wait
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  ${barCnf}
        wait
        sed -i "s/^_LOCAL_DEVUAN_MIRROR=.*/_LOCAL_DEVUAN_MIRROR=${devM}/g"         ${barCnf}
        wait
        sed -i "s/^_LOCAL_DEBIAN_MIRROR=.*/_LOCAL_DEBIAN_MIRROR=${debM}/g"         ${barCnf}
        wait
        sed -i "s/^_MY_EMAIL=.*/_MY_EMAIL=\"notify\@omega8.cc\"/g"                 ${barCnf}
        wait
        sed -i "s/^_STRICT_BIN_PERMISSIONS=.*/_STRICT_BIN_PERMISSIONS=YES/g"       ${barCnf}
        wait
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   ${barCnf}
        wait
        sed -i "s/^_PERMISSIONS_FIX=.*/_PERMISSIONS_FIX=YES/g"                     ${barCnf}
        wait
        sed -i "s/^_FORCE_GIT_MIRROR=.*/_FORCE_GIT_MIRROR=\"\"/g"                  /root/.*.octopus.cnf &> /dev/null
        wait
        sed -i "s/^_STRONG_PASSWORDS=.*/_STRONG_PASSWORDS=YES/g"                   /root/.*.octopus.cnf &> /dev/null
        wait
        if [ -e "/root/.mstr.clstr.cnf" ] \
          || [ -e "/root/.wbhd.clstr.cnf" ] \
          || [ -e "/root/.dbhd.clstr.cnf" ] \
          || [ -e "/root/.test.clstr.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/^_REDIS_LISTEN_MODE=.*/_REDIS_LISTEN_MODE=SOCKET/g"            ${barCnf}
          wait
        fi
        if [ -z "${_PHP_SINGLE_INSTALL}" ]; then
          sed -i "s/^_PHP_CLI_VERSION=5.6/_PHP_CLI_VERSION=7.3/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=5.6/_PHP_FPM_VERSION=7.3/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.2/_PHP_CLI_VERSION=7.3/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.2/_PHP_FPM_VERSION=7.3/g"                  ${barCnf}
          wait
        fi
        # if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        #   || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        #   || [ "${_VMFAMILY}" = "VS" ]; then
        #   if [ "${_VMFAMILY}" = "VS" ]; then
        #     sed -i "s/^_CPU_CRIT_RATIO=.*/_CPU_CRIT_RATIO=3/g"                     ${barCnf}
        #     wait
        #     sed -i "s/^_CPU_MAX_RATIO=.*/_CPU_MAX_RATIO=2/g"                       ${barCnf}
        #     wait
        #     sed -i "s/^_CPU_SPIDER_RATIO=.*/_CPU_SPIDER_RATIO=1/g"                 ${barCnf}
        #     wait
        #   fi
        # fi
      fi
    fi
    sed -i "/^$/d" ${barCnf}
    wait
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
    if [ "${_LOCAL_DEBIAN_MIRROR}" = "http.debian.net" ] \
      || [ "${_LOCAL_DEBIAN_MIRROR}" = "httpredir.debian.org" ] \
      || [ "${_LOCAL_DEBIAN_MIRROR}" = "ftp.debian.org" ]; then
      _LOCAL_DEBIAN_MIRROR="deb.debian.org"
      sed -i "s/^_LOCAL_DEBIAN_.*/_LOCAL_DEBIAN_MIRROR=deb.debian.org/g"     ${barCnf}
      wait
    fi
    if [ "${_DB_SERIES}" = "10.4" ] \
      || [ "${_DB_SERIES}" = "10.3" ] \
      || [ "${_DB_SERIES}" = "10.2" ] \
      || [ "${_DB_SERIES}" = "5.7" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _DBS_VRN="${_GALERA_10_VRN}"
      else
        if [ "${_DB_SERIES}" = "10.3" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_3_VRN}"
        elif [ "${_DB_SERIES}" = "10.2" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_2_VRN}"
        elif [ "${_DB_SERIES}" = "10.4" ]; then
          _DB_SERVER=MariaDB
          _DBS_VRN="${_MARIADB_10_4_VRN}"
        elif [ "${_DB_SERIES}" = "5.7" ]; then
          _DB_SERVER=Percona
          _DBS_VRN="${_PERCONA_5_7_VRN}"
        else
          _DB_SERVER=Percona
          _DB_SERIES=5.7
          _DBS_VRN="${_PERCONA_5_7_VRN}"
        fi
      fi
    else
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
      if [ -e "${barCnf}" ]; then
        sed -i "s/^_DB_SERIES=.*/_DB_SERIES=5.7/g" ${barCnf}
        sed -i "s/^_DB_SERVER=.*/_DB_SERVER=Percona/g" ${barCnf}
      fi
    fi
    _CHECK_HOST=$(uname -n 2>&1)
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      if [ -e "/root/.auto.up.cnf" ] \
        || [ -e "/root/.host8.cnf" ] \
        || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
        || [[ "${_CHECK_HOST}" =~ ".o8.io" ]] \
        || [[ "${_CHECK_HOST}" =~ ".aegir.cc" ]] \
        || [ "${_VMFAMILY}" = "VS" ]; then
        if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
          _DO_NOTHING=YES
        else
          _DO_NOTHING=YES
        fi
      else
        msg "EXIT: Invalid email address defined in the _MY_EMAIL variable"
        msg "EXIT: Bye (2)"
        clean_pid_exit
      fi
    fi

    ### Make sure that _PHP_SINGLE_INSTALL takes precedence
    if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
      if [ "${_PHP_SINGLE_INSTALL}" = "8.1" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "8.0" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "7.4" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "7.3" ]; then
        _PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}
        _PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}
        _PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}
        sed -i "s/^_PHP_MULTI_INSTALL=.*/_PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}/g" ${barCnf}
        wait
        sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}/g"     ${barCnf}
        wait
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}/g"     ${barCnf}
        wait
        sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}/g" /root/.*.octopus.cnf &> /dev/null
        wait
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}/g" /root/.*.octopus.cnf &> /dev/null
        wait
        if [ -e "/data/disk" ] && [ -e "/data/conf/global.inc" ]; then
          for Ctrl in `find /data/disk/*/log -maxdepth 0 -mindepth 0 | sort`; do
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/fpm.txt
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/cli.txt
            ### msg "INFO: Forced PHP ${_PHP_SINGLE_INSTALL} in $Ctrl"
          done
          for Ctrl in `find /data/disk/*/static/control \
            -maxdepth 0 -mindepth 0 | sort`; do
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/fpm.info
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/cli.info
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
      wait
    fi
    _PHP_FORCE_REINSTALL_TEST=$(grep _PHP_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_PHP_FORCE_REINSTALL_TEST}" =~ "_PHP_FORCE_REINSTALL" ]]; then
      sed -i "s/^_PHP_FORCE_REINSTALL.*//g" ${barCnf}
      wait
    fi
    _SQL_FORCE_REINSTALL_TEST=$(grep _SQL_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_SQL_FORCE_REINSTALL_TEST}" =~ "_SQL_FORCE_REINSTALL" ]]; then
      sed -i "s/^_SQL_FORCE_REINSTALL.*//g" ${barCnf}
      wait
    fi
    _SSL_FORCE_REINSTALL_TEST=$(grep _SSL_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_SSL_FORCE_REINSTALL_TEST}" =~ "_SSL_FORCE_REINSTALL" ]]; then
      sed -i "s/^_SSL_FORCE_REINSTALL.*//g" ${barCnf}
      wait
    fi
    _SSH_FORCE_REINSTALL_TEST=$(grep _SSH_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_SSH_FORCE_REINSTALL_TEST}" =~ "_SSH_FORCE_REINSTALL" ]]; then
      sed -i "s/^_SSH_FORCE_REINSTALL.*//g" ${barCnf}
      wait
    fi
    _GIT_FORCE_REINSTALL_TEST=$(grep _GIT_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_GIT_FORCE_REINSTALL_TEST}" =~ "_GIT_FORCE_REINSTALL" ]]; then
      sed -i "s/^_GIT_FORCE_REINSTALL.*//g" ${barCnf}
      wait
    fi
    _FULL_FORCE_REINSTALL_TEST=$(grep _FULL_FORCE_REINSTALL ${barCnf} 2>&1)
    if [[ "${_FULL_FORCE_REINSTALL_TEST}" =~ "_FULL_FORCE_REINSTALL" ]]; then
      sed -i "s/^_FULL_FORCE_REINSTALL.*//g" ${barCnf}
      wait
    fi
    _TOMCAT_TO_JETTY_TEST=$(grep _TOMCAT_TO_JETTY ${barCnf} 2>&1)
    if [[ "${_TOMCAT_TO_JETTY_TEST}" =~ "_TOMCAT_TO_JETTY" ]]; then
      if [ ! -e "/etc/init.d/tomcat" ]; then
        sed -i "s/^_TOMCAT_TO_JETTY.*//g" ${barCnf}
        wait
      fi
    fi
    _BULLSEYE_TO_CHIMAERA_TEST=$(grep _BULLSEYE_TO_CHIMAERA ${barCnf} 2>&1)
    if [[ "${_BULLSEYE_TO_CHIMAERA_TEST}" =~ "_BULLSEYE_TO_CHIMAERA" ]]; then
      sed -i "s/^_BULLSEYE_TO_CHIMAERA.*//g" ${barCnf}
      wait
    fi
    _BEOWULF_TO_CHIMAERA_TEST=$(grep _BEOWULF_TO_CHIMAERA ${barCnf} 2>&1)
    if [[ "${_BEOWULF_TO_CHIMAERA_TEST}" =~ "_BEOWULF_TO_CHIMAERA" ]]; then
      sed -i "s/^_BEOWULF_TO_CHIMAERA.*//g" ${barCnf}
      wait
    fi
    _BUSTER_TO_BEOWULF_TEST=$(grep _BUSTER_TO_BEOWULF ${barCnf} 2>&1)
    if [[ "${_BUSTER_TO_BEOWULF_TEST}" =~ "_BUSTER_TO_BEOWULF" ]]; then
      sed -i "s/^_BUSTER_TO_BEOWULF.*//g" ${barCnf}
      wait
    fi
    _STRETCH_TO_BEOWULF_TEST=$(grep _STRETCH_TO_BEOWULF ${barCnf} 2>&1)
    if [[ "${_STRETCH_TO_BEOWULF_TEST}" =~ "_STRETCH_TO_BEOWULF" ]]; then
      sed -i "s/^_STRETCH_TO_BEOWULF.*//g" ${barCnf}
      wait
    fi
    _JESSIE_TO_BEOWULF_TEST=$(grep _JESSIE_TO_BEOWULF ${barCnf} 2>&1)
    if [[ "${_JESSIE_TO_BEOWULF_TEST}" =~ "_JESSIE_TO_BEOWULF" ]]; then
      sed -i "s/^_JESSIE_TO_BEOWULF.*//g" ${barCnf}
      wait
    fi
    _BUSTER_TO_BULLSEYE_TEST=$(grep _BUSTER_TO_BULLSEYE ${barCnf} 2>&1)
    if [[ "${_BUSTER_TO_BULLSEYE_TEST}" =~ "_BUSTER_TO_BULLSEYE" ]]; then
      sed -i "s/^_BUSTER_TO_BULLSEYE.*//g" ${barCnf}
      wait
    fi
    _STRETCH_TO_BUSTER_TEST=$(grep _STRETCH_TO_BUSTER ${barCnf} 2>&1)
    if [[ "${_STRETCH_TO_BUSTER_TEST}" =~ "_STRETCH_TO_BUSTER" ]]; then
      sed -i "s/^_STRETCH_TO_BUSTER.*//g" ${barCnf}
      wait
    fi
    _JESSIE_TO_STRETCH_TEST=$(grep _JESSIE_TO_STRETCH ${barCnf} 2>&1)
    if [[ "${_JESSIE_TO_STRETCH_TEST}" =~ "_JESSIE_TO_STRETCH" ]]; then
      sed -i "s/^_JESSIE_TO_STRETCH.*//g" ${barCnf}
      wait
    fi
    _WHEEZY_TO_JESSIE_TEST=$(grep _WHEEZY_TO_JESSIE ${barCnf} 2>&1)
    if [[ "${_WHEEZY_TO_JESSIE_TEST}" =~ "_WHEEZY_TO_JESSIE" ]]; then
      sed -i "s/^_WHEEZY_TO_JESSIE.*//g" ${barCnf}
      wait
    fi
    _SQUEEZE_TO_WHEEZY_TEST=$(grep _SQUEEZE_TO_WHEEZY ${barCnf} 2>&1)
    if [[ "${_SQUEEZE_TO_WHEEZY_TEST}" =~ "_SQUEEZE_TO_WHEEZY" ]]; then
      sed -i "s/^_SQUEEZE_TO_WHEEZY.*//g" ${barCnf}
      wait
    fi
    _LENNY_TO_SQUEEZE_TEST=$(grep _LENNY_TO_SQUEEZE ${barCnf} 2>&1)
    if [[ "${_LENNY_TO_SQUEEZE_TEST}" =~ "_LENNY_TO_SQUEEZE" ]]; then
      sed -i "s/^_LENNY_TO_SQUEEZE.*//g" ${barCnf}
      wait
    fi
    sed -i "/^$/d" ${barCnf}
    wait
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
  st_runner "apt --fix-broken install -y" 2> /dev/null
  st_runner "dpkg --configure --force-all -a" 2> /dev/null
  st_runner "apt-get update -qq" &> /dev/null
  if [ -e "/usr/bin/mytop" ]; then
    st_runner "${_RMAPP} mytop" &> /dev/null
    st_runner "apt-get purge mytop -y -qq" &> /dev/null
    rm -f /usr/bin/mytop
  fi
  st_runner "aptitude full-upgrade -f -y -q \
    --allow-untrusted \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold" &> /dev/null
  if [ ! -e "/usr/local/bin/mytop" ] && [ -e "/usr/bin/mysql" ]; then
    msg "INFO: Building MyTop from sources, please wait..."
    cd /var/opt
    rm -rf git*
    get_dev_src "mytop-1.6.tar.gz"
    cd /var/opt/mytop-1.6
    mrun "perl Makefile.PL" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
  fi
}

#
# Install latest Git.
do_install_latest_git() {
  if [ ! -e "${pthLog}/git-${_GIT_VRN}-${_X_VERSION}-${_NOW}.log" ]; then
    msg "INFO: Building Git ${_GIT_VRN} from sources, please wait..."
    cd /var/opt
    rm -rf git*
    get_dev_src "git-${_GIT_VRN}.tar.gz"
    cd /var/opt/git-${_GIT_VRN}
    mrun "make configure" 2> /dev/null
    mrun "bash ./configure --without-tcltk --quiet" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
    mv -f /usr/bin/git /usr/bin/git-old
    ln -sf /usr/local/bin/git /usr/bin/git
    cd /var/opt
    touch ${pthLog}/git-${_GIT_VRN}-${_X_VERSION}-${_NOW}.log
    echo "git hold" | dpkg --set-selections &> /dev/null
    echo "git-core hold" | dpkg --set-selections &> /dev/null
    echo "git-man hold" | dpkg --set-selections &> /dev/null
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
  if [[ "${_GIT_ITD}" =~ "git version 1.9.1" ]]; then
    _GIT_FORCE_REINSTALL=YES
  fi
  if [[ "${_XTRAS_LIST}" =~ "GIT" ]] \
    || [ "${_GIT_FORCE_REINSTALL}" = "YES" ]; then
    _GIT_TEST=$(git --version 2>&1)
    if [[ "${_GIT_TEST}" =~ "git version ${_GIT_VRN}" ]]; then
      if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
        || [ "${_GIT_FORCE_REINSTALL}" = "YES" ]; then
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
  for Update in `/usr/bin/apt-get -q -y --allow-unauthenticated \
    -s dist-upgrade | grep ^Inst | cut -d\  -f2 | sort`; do
    case "${Update}" in
      *libcurl*)    _UP_PHP=YES ;;
      *libmysql*)   _UP_SQL=YES ;;
      *libssl*)     _UP_PHP=YES ;;
      *linux-*)     _UP_LNX=YES ;;
      *newrelic*)   _UP_NRC=YES ;;
      *openjdk*)    _UP_JDK=YES ;;
      *openssl*)    _UP_PHP=YES ;;
      *proxysql*)   _UP_PXC=YES ;;
      *)  ;;
    esac
  done
}

#
# Install ICU from sources for Jessie.
install_icu() {
  ###--------------------###
  if [ ! -e "/usr/local/lib/icu/current" ]; then
    msg "INFO: Installing ICU libs version ${_ICU_VRN}..."
    if [ ! -e "/var/opt/icu/source" ]; then
      cd /var/opt
      rm -rf icu*
      get_dev_src "icu4c-${_ICU_VRN}-src.tgz"
    fi
    cd /var/opt/icu/source/
    mrun "bash ./configure \
      --prefix=/usr/local" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
  fi
}

#
# Install PHP deps.
install_php_deps() {
  ###--------------------###
  st_runner "${_INSTALL} libgd-dev" 2> /dev/null
  st_runner "${_INSTALL} libgd3" 2> /dev/null
  st_runner "${_INSTALL} libkrb5-dev" 2> /dev/null
  st_runner "${_INSTALL} libldap-dev" 2> /dev/null
  st_runner "${_INSTALL} libmagickwand-dev" 2> /dev/null
  st_runner "${_INSTALL} libxpm-dev" 2> /dev/null
  st_runner "${_INSTALL} libwebp-dev" 2> /dev/null
  st_runner "${_INSTALL} libsodium-dev" 2> /dev/null
  if [ "${_OSR}" = "jessie" ]; then
    install_icu
  else
    st_runner "${_INSTALL} libicu-dev" 2> /dev/null
  fi
}

#
# Install wkhtmltopdf and wkhtmltoimage.
install_wkhtmltox() {
  ###--------------------###
  mrun "${_INSTALL} fonts-thai-tlwg" 2> /dev/null
  _THIS_RV=$(lsb_release -sc 2>&1)
  _X86_64_TEST=$(uname -m 2>&1)
  _WOX_IS=OLD
  _WOX_ITD=$(wkhtmltopdf --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}')
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_THIS_RV}" = "stretch" ]; then
    if [[ "${_WOX_ITD}" =~ "0.12.6" ]]; then
      _WOX_IS=NEW
    fi
  else
    if [[ "${_WOX_ITD}" =~ "0.12.5" ]]; then
      _WOX_IS=NEW
    fi
  fi
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_THIS_RV}" = "stretch" ] \
    || [ "${_THIS_RV}" = "jessie" ] \
    || [ "${_THIS_RV}" = "trusty" ]; then
    if [ "${_WOX_IS}" = "OLD" ] \
      || [ ! -x "/usr/local/bin/wkhtmltopdf" ] \
      || [ ! -x "/usr/local/bin/wkhtmltoimage" ] \
      || [ ! -f "/usr/bin/wkhtmltopdf" ] \
      || [ ! -f "/usr/bin/wkhtmltoimage" ] \
      || [ -L "/usr/bin/wkhtmltopdf" ] \
      || [ -L "/usr/bin/wkhtmltoimage" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      if [ "${_X86_64_TEST}" = "x86_64" ]; then
        SYSTEM_ARCH="x86_64"
        msg "INFO: Installing wkhtmltox tools v.0.${_WKHTMLTOX_VRN}..."
        cd /var/opt
        rm -rf wkhtmltox*
        mkdir -p /var/opt/wkhtmltox
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          mrun "${_INSTALL} xfonts-75dpi xfonts-base"
          get_dev_src "wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_THIS_RV}_amd64.deb.gz"
          dpkg -i "/var/opt/wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_THIS_RV}_amd64.deb"
          apt-get install -f -y
        else
          mrun "${_INSTALL} xfonts-75dpi xfonts-base" &> /dev/null
          get_dev_src "wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_THIS_RV}_amd64.deb.gz" &> /dev/null
          dpkg -i "/var/opt/wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_THIS_RV}_amd64.deb" &> /dev/null
          apt-get install -f -y &> /dev/null
        fi
      else
        SYSTEM_ARCH="x86"
        msg "INFO: Installing wkhtmltox tools v.0.${_WKHTMLTOX_VRN}..."
        mrun "${_INSTALL} xfonts-75dpi xfonts-base" &> /dev/null
        cd /var/opt
        rm -rf wkhtmltox*
        mkdir -p /var/opt/wkhtmltox
        get_dev_src "wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_THIS_RV}_i386.deb.gz" &> /dev/null
        dpkg -i "/var/opt/wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_THIS_RV}_i386.deb" &> /dev/null
        apt-get install -f -y &> /dev/null
      fi
      if [ -x "/usr/local/bin/wkhtmltopdf" ]; then
        if [ ! -e "/usr/bin/wkhtmltopdf-0.12.4" ]; then
          mv -f /usr/bin/wkhtmltopdf /usr/bin/wkhtmltopdf-0.12.4 &> /dev/null
        fi
        rm -f /usr/bin/wkhtmltopdf
        cp -af /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf
      fi
      if [ -x "/usr/local/bin/wkhtmltoimage" ]; then
        if [ ! -e "/usr/bin/wkhtmltoimage-0.12.4" ]; then
          mv -f /usr/bin/wkhtmltoimage /usr/bin/wkhtmltoimage-0.12.4 &> /dev/null
        fi
        rm -f /usr/bin/wkhtmltoimage
        cp -af /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage
      fi
      if [ -x "/usr/local/bin/wkhtmltoimage" ] \
        && [ -x "/usr/local/bin/wkhtmltopdf" ]; then
        touch ${pthLog}/wkhtmltox-${_WKHTMLTOX_VRN}-fix.log
        msg "INFO: The wkhtmltox tools v.0.${_WKHTMLTOX_VRN} installation complete"
      fi
      cd /var/opt
    fi
  fi
}

#
# Clean Drush 11.
clean_drush_eleven() {
  rm -f /usr/bin/drush11*
  ln -sf /opt/tools/drush/11/drush/vendor/drush/drush/drush /usr/bin/drush11-bin
  msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} setup complete"
}

#
# Clean Drush 10.
clean_drush_ten() {
  rm -f /usr/bin/drush10*
  rm -f /usr/local/bin/dcg
  rm -f /usr/local/bin/drush
  rm -f /usr/local/bin/php-parse
  rm -f /usr/local/bin/psysh
  rm -f /usr/local/bin/release
  rm -f /usr/local/bin/robo
  rm -f /usr/local/bin/var-dump-server
  ln -sf /opt/tools/drush/10/drush/vendor/drush/drush/drush /usr/bin/drush10-bin
  msg "INFO: Drush ${_DRUSH_TEN_VRN} setup complete"
}

#
# Set Drush permissions.
set_drush_perm() {
  find /opt/tools -type d -exec chmod 0755 {} \; &> /dev/null
  find /opt/tools -type f -exec chmod 0644 {} \; &> /dev/null
  chmod 755 /opt/tools/drush/*/drush/drush
  chmod 755 /opt/tools/drush/*/drush/drush.complete.sh
  chmod 755 /opt/tools/drush/*/drush/drush.launcher
  chmod 755 /opt/tools/drush/*/drush/drush.php
  chmod 755 /opt/tools/drush/*/drush/unish.sh
  chmod 755 /opt/tools/drush/*/drush/examples/drush.wrapper
  chmod 755 /opt/tools/drush/*/drush/examples/git-bisect.example.sh
  chmod 755 /opt/tools/drush/*/drush/examples/helloworld.script
  if [ -e "/opt/tools/drush/10/drush/vendor/drush/drush/drush" ]; then
    chmod 755 /opt/tools/drush/10/drush/vendor/drush/drush/drush
    chmod 755 /opt/tools/drush/10/drush/vendor/drush/drush/drush.php
  fi
  if [ -e "/opt/tools/drush/11/drush/vendor/drush/drush/drush" ]; then
    chmod 755 /opt/tools/drush/11/drush/vendor/drush/drush/drush
    chmod 755 /opt/tools/drush/11/drush/vendor/drush/drush/drush.php
  fi
  if [ -e "/opt/tools/drush/launcher/drush.phar" ]; then
    chmod 755 /opt/tools/drush/launcher/drush.phar
  fi
}

#
# Install or update Drush Launcher.
get_drush_launcher() {
  rm -rf /opt/tools/drush/launcher/*
  cd /opt/tools/drush/launcher/
  wget -q -U iCab https://github.com/drush-ops/drush-launcher/releases/latest/download/drush.phar
  touch /opt/tools/drush/launcher/.ctrl.${_X_SE}.pid
  rm -f /usr/bin/drush-launcher
  rm -f /usr/bin/drushlr
  ln -sf /opt/tools/drush/launcher/drush.phar /usr/bin/drush-launcher
  ln -sf /opt/tools/drush/launcher/drush.phar /usr/bin/drushlr
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush Launcher ${_DRUSH_LAUNCHER_VRN} installation complete"
  fi
}

#
# Install or update Drush 11.
get_drush_eleven() {
  rm -rf /opt/tools/drush/11/*
  cd /opt/tools/drush/11/
  get_dev_ext "drush-${_DRUSH_ELEVEN_VRN}.tar.gz"
  touch /opt/tools/drush/11/.ctrl.${_X_SE}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} installation complete"
  fi
}

#
# Install or update Drush 10.
get_drush_ten() {
  rm -rf /opt/tools/drush/10/*
  cd /opt/tools/drush/10/
  get_dev_ext "drush-${_DRUSH_TEN_VRN}.tar.gz"
  touch /opt/tools/drush/10/.ctrl.${_X_SE}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH_TEN_VRN} installation complete"
  fi
}

#
# Install or update Drush 8.
get_drush_eight() {
  rm -rf /opt/tools/drush/8/*
  cd /opt/tools/drush/8/
  get_dev_ext "drush-${_DRUSH_EIGHT_VRN}.tar.gz"
  touch /opt/tools/drush/8/.ctrl.${_X_SE}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH_EIGHT_VRN} installation complete"
  fi
}

#
# Install or update Drush versions.
get_drush_versions() {
  msg "INFO: Installing supported Drush versions..."
  _X_SE="414prodT58"
  ###--------------------###
  if [ -e "/opt/tools/drush/9" ]; then
    rm -rf /opt/tools/drush/9
    rm -f /usr/bin/drush9
  fi
  if [ -e "/opt/tools/drush/7" ]; then
    rm -rf /opt/tools/drush/7
    rm -f /usr/bin/drush7
  fi
  if [ -e "/opt/tools/drush/6" ]; then
    rm -rf /opt/tools/drush/6
    rm -f /usr/bin/drush6
  fi
  if [ -e "/opt/tools/drush/5" ]; then
    rm -rf /opt/tools/drush/5
    rm -f /usr/bin/drush5
  fi
  if [ -e "/opt/tools/drush/4" ]; then
    rm -rf /opt/tools/drush/4
    rm -f /usr/bin/drush4
  fi
  mkdir -p /opt/tools/drush/{8,10,11,launcher}
  chown -R root:root /opt/tools
  if [ -e "/opt/tools/drush/8" ]; then
    _DRUSH_ITD=$(drush8 --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f8 \
      | awk '{ print $1}' 2>&1)
    if [ "${_DRUSH_ITD}" != "${_DRUSH_EIGHT_TEST_VRN}" ] \
      || [ ! -x "/opt/tools/drush/8/drush/drush" ] \
      || [ ! -e "/opt/tools/drush/8/.ctrl.${_X_SE}.pid" ]; then
      msg "INFO: Drush ${_DRUSH_EIGHT_VRN} re-installation required"
      get_drush_eight
    else
      msg "INFO: Drush ${_DRUSH_EIGHT_VRN} already installed"
    fi
  fi
  if [ -e "/opt/tools/drush/10" ]; then
    _DRUSH_ITD=$(drush10-bin --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f4 \
      | awk '{ print $1}' 2>&1)
    if [ "${_DRUSH_ITD}" != "${_DRUSH_TEN_VRN}" ] \
      || [ ! -x "/opt/tools/drush/10/drush/vendor/drush/drush/drush" ] \
      || [ ! -e "/opt/tools/drush/10/.ctrl.${_X_SE}.pid" ]; then
      msg "INFO: Drush ${_DRUSH_TEN_VRN} re-installation required"
      get_drush_ten
    else
      msg "INFO: Drush ${_DRUSH_TEN_VRN} already installed"
    fi
  fi
  if [ -e "/opt/tools/drush/11" ]; then
    _DRUSH_ITD=$(drush11-bin --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f4 \
      | awk '{ print $1}' 2>&1)
    if [ "${_DRUSH_ITD}" != "${_DRUSH_ELEVEN_VRN}" ] \
      || [ ! -x "/opt/tools/drush/11/drush/vendor/drush/drush/drush" ] \
      || [ ! -e "/opt/tools/drush/11/.ctrl.${_X_SE}.pid" ]; then
      msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} re-installation required"
      get_drush_eleven
    else
      msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} already installed"
    fi
  fi
  if [ -e "/opt/tools/drush/launcher" ]; then
    _DRUSH_ITD=$(drush-launcher --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f4 \
      | sed 's/The//g' \
      | awk '{ print $1}' 2>&1)
    if [ "${_DRUSH_ITD}" != "${_DRUSH_LAUNCHER_VRN}" ] \
      || [ ! -x "/opt/tools/drush/launcher/drush.phar" ] \
      || [ ! -e "/opt/tools/drush/launcher/.ctrl.${_X_SE}.pid" ]; then
      msg "INFO: Drush Launcher ${_DRUSH_LAUNCHER_VRN} re-installation required"
      get_drush_launcher
    else
      msg "INFO: Drush Launcher ${_DRUSH_LAUNCHER_VRN} already installed"
    fi
  fi
  set_drush_perm
  if [ -x "/opt/tools/drush/8/drush/drush" ]; then
    rm -f /usr/bin/drush8
    rm -f /usr/bin/drush
    ln -s /opt/tools/drush/8/drush/drush /usr/bin/drush8
    ln -s /opt/tools/drush/8/drush/drush /usr/bin/drush
  else
    msg "FAIL: Drush ${_DRUSH_EIGHT_VRN} installation failed!"
  fi
  if [ -x "/opt/tools/drush/10/drush/vendor/drush/drush/drush" ]; then
    clean_drush_ten
  else
    msg "FAIL: Drush ${_DRUSH_TEN_VRN} installation failed!"
  fi
  if [ -x "/opt/tools/drush/11/drush/vendor/drush/drush/drush" ]; then
    clean_drush_eleven
  else
    msg "FAIL: Drush ${_DRUSH_ELEVEN_VRN} installation failed!"
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
  rm -rf /var/lib/apt/lists/*
  ###--------------------###
  if [ -e "${pthLog}/apt-updates-beowulf.txt" ] \
    || [ -e "/var/log/apt-updates-beowulf.txt" ]; then
    _APT_SOURCES_REWRITE=NO
    if [ ! -z "${_LOCAL_DEVUAN_MIRROR}" ]; then
      _APT_SOURCES_REWRITE=YES
    fi
    if [ ! -z "${_LOCAL_DEBIAN_MIRROR}" ]; then
      _APT_SOURCES_REWRITE=YES
    fi
    if [ ! -z "${_LOCAL_UBUNTU_MIRROR}" ]; then
      _APT_SOURCES_REWRITE=YES
    fi
  else
    _APT_SOURCES_REWRITE=YES
  fi
  if [ "${_APT_SOURCES_REWRITE}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Updating packages sources list..."
    fi
    mv -f ${aptLiSys} \
      ${vBs}/sources.list-pre-${_X_VERSION}-${_NOW} &> /dev/null
    if [ "${_THIS_OS}" = "Devuan" ]; then
	  if [ -z "${_LOCAL_DEVUAN_MIRROR}" ]; then
		_MIRROR=deb.devuan.org
	  else
		_MIRROR=${_LOCAL_DEVUAN_MIRROR}
	  fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: We will use ${_THIS_OS} mirror ${_MIRROR}"
      fi
      cd /var/opt
      echo "## DEVUAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_MIRROR}/merged/ ${_OSR} main" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
	  echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
	  echo "deb http://${_MIRROR}/merged/ ${_OSR}-updates main" | fmt -su -w 2500 >> ${aptLiSys}
	  echo "" >> ${aptLiSys}
      echo "## DEVUAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/merged/ ${_OSR}-security main" | fmt -su -w 2500 >> ${aptLiSys}
    elif [ "${_THIS_OS}" = "Debian" ]; then
      _MIRROR_CHECK=NO
      if [ "${_OSR}" = "deprecated" ]; then
        _MIRROR=archive.debian.org
      else
        if [ "${_AUTOPILOT}" = "YES" ]; then
          if [ -z "${_LOCAL_DEBIAN_MIRROR}" ]; then
            _MIRROR=deb.debian.org
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
          _MIRROR=deb.debian.org
        fi
      fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: We will use ${_THIS_OS} mirror ${_MIRROR}"
      fi
      cd /var/opt
      echo "## DEBIAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_MIRROR}/debian/ ${_OSR} main contrib non-free" >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/debian/ ${_OSR} main contrib non-free" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/debian/ ${_OSR}-updates main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/debian/ ${_OSR}-updates main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## DEBIAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://security.debian.org/debian-security ${_OSR}-security main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://security.debian.org/debian-security ${_OSR}-security main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
    elif [ "${_THIS_OS}" = "Ubuntu" ]; then
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
      echo "deb http://${_MIRROR}/ubuntu/ ${_OSR} main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/ubuntu/ ${_OSR} main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/ubuntu/ ${_OSR}-updates main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/ubuntu/ ${_OSR}-updates main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## BACKPORTS" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/ubuntu/ ${_OSR}-backports main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/ubuntu/ ${_OSR}-backports main \
        restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## UBUNTU SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://security.ubuntu.com/ubuntu ${_OSR}-security \
        main restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://security.ubuntu.com/ubuntu ${_OSR}-security \
        main restricted universe multiverse" | fmt -su -w 2500 >> ${aptLiSys}
    fi
    mkdir -p ${pthLog}
    touch ${pthLog}/apt-updates-beowulf.txt
    cd /var/opt
  fi
  ###--------------------###
  apt-get update -qq &> /dev/null
  ###--------------------###
}

#
# Install OpenSSH from sources.
install_ssh_src() {
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ]; then
    _SSH_GET_DPKG=$(dpkg --get-selections | grep openssh-sftp-server | grep 'hold$' 2>&1)
  else
    _SSH_GET_DPKG=$(dpkg --get-selections | grep ssh | grep 'hold$' 2>&1)
  fi
  _SSH_INSTALL_REQUIRED=NO
  _SSH_ITD=$(ssh -V 2>&1 \
    | tr -d "\n" \
    | tr -d "," \
    | cut -d"_" -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_SSH_FORCE_REINSTALL}" = "YES" ]; then
    _SSH_INSTALL_REQUIRED=YES
    msg "INFO: OpenSSH ${_SSH_ITD}, rebuild forced"
  elif [ "${_SSH_ITD}" = "${_OPENSSH_VRN}" ]; then
    _DO_NOTHING=YES
  else
    _SSH_INSTALL_REQUIRED=YES
    msg "INFO: Installed OpenSSH version ${_SSH_ITD}, upgrade required"
  fi
  if [ "${_SSH_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Building OpenSSH ${_OPENSSH_VRN} from sources, please wait..."
    cd /var/opt
    rm -rf openssh*
    get_dev_src "openssh-${_OPENSSH_VRN}.tar.gz"
    cd /var/opt/openssh-${_OPENSSH_VRN}
    mrun "bash ./configure \
      --with-openssl \
      --without-openssl-header-check \
      --prefix=/usr \
      --with-pam" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
    mrun "service ssh restart" &> /dev/null
    if [[ ! "${_SSH_GET_DPKG}" =~ "hold" ]]; then
      ### aptitude hold openssh-server &> /dev/null
      ### aptitude hold openssh-client &> /dev/null
      ### aptitude hold ssh &> /dev/null
      echo "openssh-client hold" | dpkg --set-selections &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections &> /dev/null
      echo "ssh hold" | dpkg --set-selections &> /dev/null
      if [ "${_OSR}" = "chimaera" ] \
        || [ "${_OSR}" = "beowulf" ] \
        || [ "${_OSR}" = "bullseye" ] \
        || [ "${_OSR}" = "buster" ] \
        || [ "${_OSR}" = "stretch" ] \
        || [ "${_OSR}" = "jessie" ]; then
        echo "openssh-sftp-server hold" | dpkg --set-selections &> /dev/null
      fi
    fi
  else
    if [[ ! "${_SSH_GET_DPKG}" =~ "hold" ]]; then
      ### aptitude hold openssh-server &> /dev/null
      ### aptitude hold openssh-client &> /dev/null
      ### aptitude hold ssh &> /dev/null
      echo "openssh-client hold" | dpkg --set-selections &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections &> /dev/null
      echo "ssh hold" | dpkg --set-selections &> /dev/null
      if [ "${_OSR}" = "chimaera" ] \
        || [ "${_OSR}" = "beowulf" ] \
        || [ "${_OSR}" = "bullseye" ] \
        || [ "${_OSR}" = "buster" ] \
        || [ "${_OSR}" = "stretch" ] \
        || [ "${_OSR}" = "jessie" ]; then
        echo "openssh-sftp-server hold" | dpkg --set-selections &> /dev/null
      fi
    fi
  fi
  _SSH_FORCE_REINSTALL=NO
}

#
# Install ImageMagick from sources.
install_magick_src() {
  _MAGICK_INSTALL_REQUIRED=NO
  _MAGICK_ITD=$(convert --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f3 \
    | awk '{ print $1}' 2>&1)
  if [ "${_MAGICK_ITD}" != "${_IMAGE_MAGICK_VRN}" ]; then
    if [ "${_OSR}" = "none" ]; then
      _MAGICK_INSTALL_REQUIRED=NO
    else
      _MAGICK_INSTALL_REQUIRED=YES
      msg "INFO: Installed ImageMagick version ${_MAGICK_ITD}, upgrade required"
    fi
  fi
  if [ "${_MAGICK_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Building ImageMagick ${_IMAGE_MAGICK_VRN} from sources, please wait..."
    cd /var/opt
    rm -rf ImageMagick*
    get_dev_src "ImageMagick-${_IMAGE_MAGICK_VRN}.tar.gz"
    cd /var/opt/ImageMagick-${_IMAGE_MAGICK_VRN}
    mrun "bash ./configure --prefix=/usr" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    if [ ! -e "/etc/.ImageMagick-6" ] \
      && [ -e "/etc/ImageMagick-6" ]; then
        cp -a /etc/ImageMagick-6 /etc/.ImageMagick-6
    fi
    if [ ! -e "/etc/.ImageMagick" ] \
      && [ -e "/etc/ImageMagick" ]; then
        cp -a /etc/ImageMagick /etc/.ImageMagick
    fi
    mrun "apt-get remove imagemagick -y -qq" 2> /dev/null
    mrun "apt-get purge imagemagick -y -qq" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
    msg "HINT: Please modify /usr/etc/ImageMagick-7/policy.xml file, if needed"
  fi
}

#
# Install OpenSSL from sources.
install_ssl_src() {
  _SSL_INSTALL_REQUIRED=NO
  _SSL_ITD=$(openssl version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_SSL_ITD}" = "${_OPENSSL_LEGACY_VRN}" ] \
    || [ "${_SSL_ITD}" = "${_OPENSSL_CURRENT_VRN}" ]; then
    _SPDY_COMPATIBILITY_TEST=$(service nginx configtest 2>&1)
    if [[ "${_SPDY_COMPATIBILITY_TEST}" =~ "without OpenSSL ALPN or NPN" ]]; then
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
    if [ "${_OSR}" = "chimaera" ] \
      || [ "${_OSR}" = "beowulf" ] \
      || [ "${_OSR}" = "bullseye" ] \
      || [ "${_OSR}" = "buster" ] \
      || [ "${_OSR}" = "stretch" ]; then
      _OPENSSL_NEW_VRN=${_OPENSSL_CURRENT_VRN}
    else
      _OPENSSL_NEW_VRN=${_OPENSSL_LEGACY_VRN}
    fi
    ###--------------------###
    msg "INFO: Building zlib ${_ZLIB_VRN} from sources first, please wait..."
    cd /var/opt
    rm -rf zlib*
    get_dev_src "zlib-${_ZLIB_VRN}.tar.gz"
    cd /var/opt/zlib-${_ZLIB_VRN}
    st_runner "bash ./configure --prefix=/usr" 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
    ###--------------------###
    msg "INFO: Building OpenSSL ${_OPENSSL_NEW_VRN} from sources, please wait..."
    if [ ! -e "/var/opt/openssl-${_OPENSSL_NEW_VRN}" ]; then
      cd /var/opt
      rm -rf openssl*
      wget -q -U iCab ${urlDev}/src/openssl-${_OPENSSL_NEW_VRN}.tar.gz
      if [ -e "openssl-${_OPENSSL_NEW_VRN}.tar.gz" ]; then
        extract_archive "openssl-${_OPENSSL_NEW_VRN}.tar.gz"
      else
        msg "OOPS: failed download from ${urlDev}/src/openssl-${_OPENSSL_NEW_VRN}.tar.gz"
      fi
    fi
    if [ -e "/var/opt/openssl-${_OPENSSL_NEW_VRN}" ]; then
      cd /var/opt/openssl-${_OPENSSL_NEW_VRN}
      _X86_64_IF=$(uname -m 2>&1)
      if [ "${_X86_64_IF}" = "x86_64" ]; then
        mrun "sh ./config zlib-dynamic \
          --prefix=/usr/local/ssl \
          --openssldir=/usr/local/ssl \
          shared enable-ec_nistp_64_gcc_128" 2> /dev/null
      else
        mrun "sh ./config zlib-dynamic \
          --prefix=/usr/local/ssl \
          --openssldir=/usr/local/ssl \
          shared" 2> /dev/null
      fi
      mrun "make depend" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
    fi
    if [ -x "/usr/local/ssl/bin/openssl" ]; then
      cp -af /usr/bin/openssl /usr/bin/old-openssl-$(date +%y%m%d-%H%M%S 2>&1)
      ln -sf /usr/local/ssl/bin/openssl `which openssl`
      echo "/usr/local/ssl/lib" >> /etc/ld.so.conf.d/libc.conf
      mrun "ldconfig" 2> /dev/null
      ###--------------------###
      _SSL_GET_DPKG=$(dpkg --get-selections \
        | grep openssl \
        | grep 'hold$' 2>&1)
      _ZLB_GET_DPKG=$(dpkg --get-selections \
        | grep zlibc \
        | grep 'hold$' 2>&1)
      if [[ ! "${_SSL_GET_DPKG}" =~ "hold" ]]; then
        echo "openssl hold" | dpkg --set-selections &> /dev/null
      fi
      if [[ ! "${_ZLB_GET_DPKG}" =~ "hold" ]]; then
        echo "zlibc hold" | dpkg --set-selections &> /dev/null
        echo "zlib1g hold" | dpkg --set-selections &> /dev/null
        echo "zlib1g-dev hold" | dpkg --set-selections &> /dev/null
      fi
      fix_libssl
    else
      msg "OOPS: OpenSSL version ${_OPENSSL_NEW_VRN} was not installed!"
      _SSL_INSTALL_REQUIRED=
      _SSH_FORCE_REINSTALL=
      _NGX_FORCE_REINSTALL=
      _PHP_FORCE_REINSTALL=
      _GIT_FORCE_REINSTALL=
    fi
  fi
}

#
# Install cURL from sources.
install_curl_src() {
  if [ "${_OSR}" = "precise" ] || [ "${_OSR}" = "jessie" ]; then
    touch /root/.use.curl.from.packages.cnf
    chattr +i /root/.use.curl.from.packages.cnf
    _CURL_VRN=8.0.1
  fi
  _CURL_INSTALL_REQUIRED=NO
  _CURL_GET_DPKG=$(dpkg --get-selections | grep curl | grep 'hold$' 2>&1)
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
  if [ "${_CURL_ITD}" != "${_CURL_VRN}" ]; then
    if [ "${_OSR}" = "none" ]; then
      _CURL_INSTALL_REQUIRED=NO
    else
      _CURL_INSTALL_REQUIRED=YES
      msg "INFO: Installed cURL version ${_CURL_ITD}, upgrade required"
    fi
  fi
  _BROKEN_CURL_TEST=$(curl --version 2>&1)
  if [[ "${_BROKEN_CURL_TEST}" =~ "libcurl.so.4" ]]; then
    _CURL_INSTALL_REQUIRED=YES
    touch /root/.use.curl.from.packages.cnf
    chattr +i /root/.use.curl.from.packages.cnf
    sed -i "s/.*ssl.*//g" /etc/ld.so.conf.d/libc.conf
    grep lib /etc/ld.so.conf.d/libc.conf
    mrun "ldconfig" &> /dev/null
    rm -f /root/.sorted.multi.php.cnf
    msg "INFO: libcurl is broken, cURL re-install from packages required"
  fi
  if [ "${_PHP_BIN_BROKEN}" = "YES" ] && [ -z "${_CURL_ALREADY_REBUILT}" ]; then
    _CURL_INSTALL_REQUIRED=YES
  fi
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _CURL_INSTALL_REQUIRED=YES
    msg "INFO: Installed cURL version ${_CURL_ITD}, rebuild forced"
  fi
  if [ "${_CURL_INSTALL_REQUIRED}" = "YES" ]; then
    ###--------------------###
    if [ -e "/root/.use.curl.from.packages.cnf" ]; then
      msg "INFO: cURL from packages is forced with /root/.use.curl.from.packages.cnf"
      rm -f /root/.sorted.multi.php.cnf
      mkdir -p /var/backups/libcurl
      mv -f /usr/local/lib/libcurl* /var/backups/libcurl/ &> /dev/null
      mv -f /usr/local/lib/pkgconfig/libcurl* /var/backups/libcurl/ &> /dev/null
      if [ -e "/usr/local/bin/curl" ]; then
        mv -f /usr/local/bin/curl /usr/local/bin/curl-src-off-$(date +%y%m%d-%H%M%S 2>&1)
      fi
      if [[ "${_CURL_GET_DPKG}" =~ "hold" ]]; then
        echo "curl install" | dpkg --set-selections &> /dev/null
        if [ -z "${_CURL_ALREADY_REBUILT}" ]; then
          echo "libcurl4 install" | dpkg --set-selections &> /dev/null
          echo "libcurl4-gnutls-dev install" | dpkg --set-selections &> /dev/null
          mrun "apt-get clean -qq" 2> /dev/null
          rm -rf /var/lib/apt/lists/*
          mrun "apt-get update -qq" 2> /dev/null
          mrun "apt-get install libcurl4 ${forCer}" 2> /dev/null
          mrun "apt-get install libcurl4-gnutls-dev ${forCer}" 2> /dev/null
          mrun "apt-get install curl ${forCer}" 2> /dev/null
        fi
      fi
    else
      if [[ ! "${_CURL_GET_DPKG}" =~ "hold" ]]; then
        echo "curl hold" | dpkg --set-selections &> /dev/null
      fi
      mrun "apt-get build-dep curl -y" 2> /dev/null
      mrun "${_INSTALL} libssl-dev" 2> /dev/null
      mrun "${_INSTALL} libc-client2007e-dev" 2> /dev/null
      cd /var/opt
      rm -rf curl*
      wget -q -U iCab ${urlDev}/src/curl-${_CURL_VRN}.tar.gz
      if [ ! -e "curl-${_CURL_VRN}.tar.gz" ]; then
        msg "OOPS: failed download from ${urlDev}/src/curl-${_CURL_VRN}.tar.gz"
      else
        extract_archive "curl-${_CURL_VRN}.tar.gz"
      fi
      if [ -e "/var/opt/curl-${_CURL_VRN}" ]; then
        if [ "${_OSR}" = "chimaera" ] \
          || [ "${_OSR}" = "beowulf" ] \
          || [ "${_OSR}" = "bullseye" ] \
          || [ "${_OSR}" = "buster" ] \
          || [ "${_OSR}" = "stretch" ]; then
          _OPENSSL_NEW_VRN=${_OPENSSL_CURRENT_VRN}
        else
          _OPENSSL_NEW_VRN=${_OPENSSL_LEGACY_VRN}
        fi
        ###--------------------###
        _SSL_FORCE_REINSTALL=YES
        install_ssl_src
        ###--------------------###
        msg "INFO: Building cURL ${_CURL_VRN} from sources, please wait..."
        if [ -e "/usr/local/ssl/lib/libssl.so.1.1" ] \
          || [ -e "/usr/local/ssl/lib/libssl.so.1.0.0" ]; then
          cd /var/opt/curl-${_CURL_VRN}
          LIBS="-ldl -lpthread" PKG_CONFIG_PATH="/usr/local/ssl/lib/pkgconfig" ./configure \
            --with-ssl \
            --with-zlib=/usr \
            --with-libssl-prefix=/usr/local/ssl \
            --prefix=/usr/local &> /dev/null
          mrun "make --quiet" 2> /dev/null
          mrun "make --quiet install" 2> /dev/null
          mrun "ldconfig" &> /dev/null
          if [ -x "/usr/local/bin/curl" ]; then
            mv -f /usr/bin/curl /usr/bin/old-curl-$(date +%y%m%d-%H%M%S 2>&1)
            ln -sf /usr/local/bin/curl /usr/bin/curl
          fi
          if [ ! -e "/usr/local/ssl/certs/ca-certificates.crt" ]; then
            cp -af /etc/ssl/certs/* /usr/local/ssl/certs/ &> /dev/null
          fi
        else
          msg "OOPS: Building OpenSSL ${_OPENSSL_NEW_VRN} from sources failed!"
        fi
      else
        msg "OOPS: cURL ${_CURL_VRN} could not be extracted..."
      fi
      if [ -e "/usr/local/lib/libcurl.so" ] \
        && [ -e "/usr/local/include/curl/curl.h" ]; then
        _X86_64_TEST=$(uname -m 2>&1)
        if [ "${_X86_64_TEST}" = "x86_64" ]; then
          mkdir -p /var/backups/legacy-curl-pre-${_CURL_VRN}
          if [ -e "/usr/include/x86_64-linux-gnu/curl" ] \
            && [ ! -L "/usr/include/x86_64-linux-gnu/curl" ]; then
            mv -f /usr/include/x86_64-linux-gnu/curl /var/backups/legacy-curl-pre-${_CURL_VRN}/ &> /dev/null
            mv -f /usr/lib/x86_64-linux-gnu/libcurl.so /var/backups/legacy-curl-pre-${_CURL_VRN}/ &> /dev/null
          fi
          if [ ! -L "/usr/lib/x86_64-linux-gnu/libcurl.so" ]; then
            ln -sf /usr/local/lib/libcurl.so /usr/lib/x86_64-linux-gnu/libcurl.so &> /dev/null
          fi
          if [ ! -L "/usr/include/x86_64-linux-gnu/curl" ]; then
            ln -sf /usr/local/include/curl /usr/include/x86_64-linux-gnu/curl &> /dev/null
          fi
        else
          mkdir -p /var/backups/legacy-curl-pre-${_CURL_VRN}
          if [ -e "/usr/include/i386-linux-gnu/curl" ] \
            && [ ! -L "/usr/include/i386-linux-gnu/curl" ]; then
            mv -f /usr/include/i386-linux-gnu/curl /var/backups/legacy-curl-pre-${_CURL_VRN}/ &> /dev/null
            mv -f /usr/lib/i386-linux-gnu/libcurl.so /var/backups/legacy-curl-pre-${_CURL_VRN}/ &> /dev/null
          fi
          if [ ! -L "/usr/lib/i386-linux-gnu/libcurl.so" ]; then
            ln -sf /usr/local/lib/libcurl.so /usr/lib/i386-linux-gnu/libcurl.so &> /dev/null
          fi
          if [ ! -L "/usr/include/i386-linux-gnu/curl" ]; then
            ln -sf /usr/local/include/curl /usr/include/i386-linux-gnu/curl &> /dev/null
          fi
        fi
      fi
    fi
    _CURL_ALREADY_REBUILT=YES
  fi
}

#
# Symlink to dash.
symlink_to_dash() {
  if [ -x "/bin/dash" ]; then
    rm -f /bin/sh
    ln -s /bin/dash /bin/sh
    if [ -e "/usr/bin/sh" ]; then
      rm -f /usr/bin/sh
      ln -s /bin/dash /usr/bin/sh
    fi
  fi
}

#
# Symlink to bash.
symlink_to_bash() {
  if [ -x "/bin/bash" ]; then
    rm -f /bin/sh
    ln -s /bin/bash /bin/sh
    if [ -e "/usr/bin/sh" ]; then
      rm -f /usr/bin/sh
      ln -s /bin/bash /usr/bin/sh
    fi
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
                  /opt/php56/bin \
                  /opt/php70/bin \
                  /opt/php71/bin \
                  /opt/php72/bin \
                  /opt/php73/bin \
                  /opt/php74/bin \
                  /opt/php80/bin \
                  /opt/php81/bin \
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
    for p in ${_X_BIN_PATHS}; do
      if [ -e "$p" ]; then
        for f in `find $p ! -perm -4000 ! -perm -2000 -type f`; do
          if [[ "$f" =~ "drush"($) ]] \
            || [[ "$f" =~ "clean-boa-env"($) ]] \
            || [[ "$f" =~ "websh"($) ]]; then
            _SKIP_THIS=YES
          else
            _SHELL_TEST=$(grep -I -o "/bin/sh" $f 2>&1)
            if [ ! -z "${_SHELL_TEST}" ] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/^#\! \/.*/#\!\/bin\/dash/g" $f &> /dev/null
              wait
              sed -i "s/\/bin\/sh/\/bin\/dash/g" $f &> /dev/null
              wait
            fi
            _SHELL_TEST=$(grep -I -o "/usr/bin/sh" $f 2>&1)
            if [ ! -z "${_SHELL_TEST}" ] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/^#\! \/.*/#\!\/bin\/dash/g" $f &> /dev/null
              wait
              sed -i "s/\/usr\/bin\/sh/\/bin\/dash/g" $f &> /dev/null
              wait
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
                  /opt/php56/bin \
                  /opt/php70/bin \
                  /opt/php71/bin \
                  /opt/php72/bin \
                  /opt/php73/bin \
                  /opt/php74/bin \
                  /opt/php80/bin \
                  /opt/php81/bin \
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
    for p in ${_X_BIN_PATHS}; do
      if [ -e "$p" ]; then
        for f in `find $p ! -perm -4000 ! -perm -2000 -type f`; do
          if [[ "$f" =~ "drush"($) ]] \
            || [[ "$f" =~ "clean-boa-env"($) ]] \
            || [[ "$f" =~ "websh"($) ]]; then
            _SKIP_THIS=YES
          else
            _SHELL_TEST=$(grep -I -o "/bin/sh" $f 2>&1)
            if [ ! -z "${_SHELL_TEST}" ] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/^#\! \/.*/#\!\/bin\/bash/g" $f &> /dev/null
              wait
              sed -i "s/\/bin\/sh/\/bin\/bash/g" $f &> /dev/null
              wait
            fi
            _SHELL_TEST=$(grep -I -o "/usr/bin/sh" $f 2>&1)
            if [ ! -z "${_SHELL_TEST}" ] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/^#\! \/.*/#\!\/bin\/bash/g" $f &> /dev/null
              wait
              sed -i "s/\/usr\/bin\/sh/\/bin\/bash/g" $f &> /dev/null
              wait
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
              /opt/php56/bin \
              /opt/php70/bin \
              /opt/php71/bin \
              /opt/php72/bin \
              /opt/php73/bin \
              /opt/php74/bin \
              /opt/php80/bin \
              /opt/php81/bin \
              /sbin \
              /usr/bin \
              /usr/local/bin \
              /usr/local/sbin \
              /usr/sbin"

  for p in ${_BIN_PATHS}; do
    if [ -e "$p" ]; then
      chown root:root $p &> /dev/null
      chmod 711 $p &> /dev/null
    fi
  done
  for p in ${_BIN_PATHS}; do
    if [ -e "$p" ]; then
      for f in `find $p -group users ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp root $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in ${_BIN_PATHS}; do
    if [ -e "$p" ]; then
      for f in `find $p -group lshellg ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp root $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in ${_BIN_PATHS}; do
    if [ -e "$p" ]; then
      for f in `find $p -group www-data ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp root $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in ${_BIN_PATHS}; do
    if [ -e "$p" ]; then
      for f in `find $p -group root ! -perm -4000 ! -perm -2000 -type f`; do
        chgrp users $f &> /dev/null
        chmod 750 $f &> /dev/null
      done
    fi
  done
  for p in ${_BIN_PATHS}; do
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
                  apt \
                  apt-cache \
                  apt-config \
                  apt-get \
                  apt-key \
                  apt-listchanges \
                  apt-mark \
                  aptitude \
                  avconv \
                  bash \
                  clambc \
                  clamconf \
                  clamd \
                  clamdscan \
                  clamdtop \
                  clamscan \
                  clamsubmit \
                  compass \
                  composer \
                  convert \
                  curl \
                  dash \
                  env \
                  ffmpeg \
                  ffprobe \
                  flvtool2 \
                  freshclam \
                  git \
                  gpg \
                  gpgv \
                  gpgv1 \
                  gpgv2 \
                  gs \
                  hhvm \
                  id \
                  java \
                  java6 \
                  java7 \
                  java8 \
                  jpegoptim \
                  jpegtran \
                  logger \
                  magick \
                  man-db \
                  mongo \
                  mongod \
                  mongodump \
                  mongoexport \
                  mongofiles \
                  mongoimport \
                  mongooplog \
                  mongoperf \
                  mongorestore \
                  mongos \
                  mongosniff \
                  mongostat \
                  mongotop \
                  newrelic-daemon \
                  node \
                  npm \
                  npx \
                  nrsysmond \
                  optipng \
                  pngcrush \
                  pngquant \
                  redis-server \
                  rrdtool \
                  ruby \
                  rvm \
                  sass \
                  sass-convert \
                  scss \
                  sendmail \
                  wget \
                  which \
                  wkhtmltoimage-0.12.4 \
                  wkhtmltopdf-0.12.4 \
                  wkhtmltoimage \
                  wkhtmltopdf"
  if [ ! -z "${_BACKEND_ITEMS_LIST}" ]; then
    _BACKEND_ITEMS="${_BACKEND_ITEMS} ${_BACKEND_ITEMS_LIST}"
  fi
  for i in ${_BACKEND_ITEMS}; do
    _BIN_ITEM=$(which $i 2>&1)
    if [ -e "${_BIN_ITEM}" ]; then
      chgrp root ${_BIN_ITEM} &> /dev/null
      chmod 755 ${_BIN_ITEM} &> /dev/null
    fi
  done

  _PROTECTED_ITEMS="backboa \
                    barracuda \
                    boa \
                    clamconf \
                    fix-drupal-platform-ownership.sh \
                    fix-drupal-platform-permissions.sh \
                    fix-drupal-site-ownership.sh \
                    fix-drupal-site-permissions.sh \
                    named \
                    octopus \
                    redis-benchmark \
                    redis-check-aof \
                    redis-check-dump \
                    redis-cli \
                    rkhunter \
                    sftp-admin \
                    sftp-kill \
                    sftp-state \
                    sftp-user \
                    sftp-verif \
                    sftp-who \
                    syncpass"
  for i in ${_PROTECTED_ITEMS}; do
    _BIN_ITEM=$(which $i 2>&1)
    if [ -e "${_BIN_ITEM}" ]; then
      chown root:root ${_BIN_ITEM} &> /dev/null
      chmod 700 ${_BIN_ITEM} &> /dev/null
    fi
  done

  chown root:root /usr/bin/mysecureshell
  chmod 4755 /usr/bin/mysecureshell

  chown root:root /usr/bin/redis-server
  chmod 755 /usr/bin/redis-server

  if [ -e "/bin/ping" ]; then
    _PING_TEST=$(ls -la /bin/ping | grep rwsr-xr-x 2>&1)
    if [ -z "${_PING_TEST}" ]; then
      chown root:root /bin/ping
      chmod 4755 /bin/ping
    fi
  fi

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
  mrun "sleep 2"
  msg "CARD: It will take a moment to process your payment..."
  mrun "sleep 5"
  msg "JOKE: Just kidding !!! Enjoy your Aegir Hosting System :)"
  mrun "sleep 3"
  echo " "
  if [ "${_UP_LNX}" = "YES" ]; then
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
    if [[ "${_T_SERIES_TEST}" =~ "BOA-4." ]] \
      || [[ "${_T_SERIES_TEST}" =~ "BOA-3." ]] \
      || [[ "${_T_SERIES_TEST}" =~ "BOA-2.4." ]] \
      || [[ "${_T_SERIES_TEST}" =~ "BOA-2.3.8" ]]; then
      _DO_NOTHING=YES
    else
      _DO_NOTHING=YES
      # fix_core_dgd
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
  rm -rf /var/lib/apt/lists/*
  mkdir -p /data/conf/arch
  mv -f /data/conf/global.inc-pre* /data/conf/arch/     &> /dev/null
  mv -f /data/conf/global.inc-before* /data/conf/arch/  &> /dev/null
  mv -f /data/conf/global.inc-missing* /data/conf/arch/ &> /dev/null
  rm -f /tmp/cache.inc*
  rm -f /var/opt/._zendopcache*
  rm -rf /var/opt/*
  rm -f /var/xdrago/monitor/acrashsql.sh
  rm -f /var/xdrago/acrashsql.sh
  rm -f /var/xdrago/usage.sh
  rm -f /var/xdrago/memcache.sh*
  rm -f /var/xdrago/purge_cruft.sh
  rm -f /var/xdrago/*.old
  rm -rf /tmp/drush_make_tmp*
  rm -rf /tmp/make_tmp*
  rm -f /tmp/pm-updatecode*
  rm -rf /var/aegir/.tmp/cache
  rm -f /var/run/boa_run.pid
  rm -f /var/run/boa_wait.pid
  rm -f /var/run/manage_ltd_users.pid
  rm -f /var/run/manage_rvm_users.pid
  rm -f /var/aegir/.drush/.alias.drushrc.php
  rm -f /data/disk/*/.drush/.alias.drushrc.php
  rm -f ${pthLog}/protected-vhosts-clean.log
  rm -f ${vBs}/.auth.IP.list*
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${mtrNgx}/vhost.d/adminer.* &> /dev/null
  wait
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${mtrNgx}/vhost.d/cgp.* &> /dev/null
  wait
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${mtrNgx}/vhost.d/chive.* &> /dev/null
  wait
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${mtrNgx}/vhost.d/sqlbuddy.* &> /dev/null
  wait
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
    wait
    sed -i "s/.*water.*//g" /etc/crontab &> /dev/null
    wait
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]]; then
      if [ "${_VMFAMILY}" = "VS" ]; then
        _DO_NOTHING=YES
      else
        echo "*  *    * * *   root    bash /var/xdrago/guest-fire.sh >/dev/null 2>&1"  >> /etc/crontab
        echo "01 5    * * *   root    bash /var/xdrago/guest-water.sh >/dev/null 2>&1" >> /etc/crontab
      fi
    else
      echo "*  *    * * *   root    bash /var/xdrago/guest-fire.sh >/dev/null 2>&1"  >> /etc/crontab
      echo "01 5    * * *   root    bash /var/xdrago/guest-water.sh >/dev/null 2>&1" >> /etc/crontab
    fi
    sed -i "/^$/d" /etc/crontab &> /dev/null
    wait
  else
    sed -i "s/.*fire.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "s/.*water.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "/^$/d" /etc/crontab &> /dev/null
    wait
  fi
  if [ -e "/root/.dbhd.clstr.cnf" ]; then
    service clean-boa-env stop &> /dev/null
  fi
  killall -9 memcached     &> /dev/null
  if [ -e "/sbin/auditd" ]; then
    chmod 0750 /sbin/audispd &> /dev/null
    service auditd restart   &> /dev/null
  fi
  php_deprecated_cleanup
  php_single_initd_cleanup
  if [ ! -e "/root/.upstart.cnf" ]; then
    service cron start     &> /dev/null
  fi
  if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    if [ ! -x "/etc/csf/csfpost.sh" ]; then
      echo "" > /etc/csf/csfpost.sh
      echo "iptables -t raw -A PREROUTING -p tcp --dport 21 -j CT --helper ftp" >> /etc/csf/csfpost.sh
      echo "iptables -t raw -A OUTPUT -p tcp --dport 21 -j CT --helper ftp" >> /etc/csf/csfpost.sh
      chmod 700 /etc/csf/csfpost.sh
    fi
    service lfd stop &> /dev/null
    sleep 3
    kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
    killall sleep &> /dev/null
    rm -f /etc/csf/csf.error
    csf -x  &> /dev/null
    csf -uf &> /dev/null
    csf -e  &> /dev/null
    csf -q  &> /dev/null
    sleep 8
    service lfd start &> /dev/null
    ### Linux kernel TCP SACK CVEs mitigation
    ### CVE-2019-11477 SACK Panic
    ### CVE-2019-11478 SACK Slowness
    ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
    if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
      _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
      if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
        sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
        iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
        ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      fi
    fi
  fi
  cd /
  chmod 711 bin boot data dev emul etc home lib lib64 lib32 media mnt opt \
    sbin selinux srv sys usr var share run &> /dev/null
  chmod 700 root &> /dev/null
  msg "BYE!"
}

install_with_aptitude_deps() {
  if_to_do_fix
  if [ "${_THIS_OS}" = "Devuan" ]; then
    ${_INITINS} devuan-keyring --allow-unauthenticated &> /dev/null
  elif [ "${_THIS_OS}" = "Debian" ]; then
    ${_INITINS} debian-keyring debian-archive-keyring &> /dev/null
  elif [ "${_THIS_OS}" = "Ubuntu" ]; then
    ${_INITINS} ubuntu-keyring &> /dev/null
  fi
  mrun "${_INSTAPP} build-essential libsasl2-modules" 2> /dev/null
  mrun "${_INSTAPP} man-db dnsutils sudo symlinks iptables" 2> /dev/null
  mrun "${_INSTAPP} autoconf automake autotools-dev m4 bc" 2> /dev/null
  mrun "${_INSTAPP} apticron aptitude auditd apt-listchanges" 2> /dev/null
  mrun "${_INSTAPP} sysstat telnet cron gnupg2 gnupg" 2> /dev/null
  mrun "${_INSTAPP} zlibc time vim cvs makepasswd" 2> /dev/null
  mrun "${_INSTAPP} unzip unrtf wdiff pwgen" 2> /dev/null
  mrun "${_INSTAPP} rsync strace ntpdate python-dev" 2> /dev/null
  mrun "${_INSTAPP} mc whois zlib1g zlib1g-dev librsync-dev" 2> /dev/null
  mrun "${_INSTAPP} mcrypt curl libcurl4 libssl-dev" 2> /dev/null
  mrun "${_INSTAPP} libcurl4-gnutls-dev" 2> /dev/null
  mrun "${_INSTAPP} sqlite3 libsqlite3-dev s4cmd" 2> /dev/null
  mrun "${_INSTAPP} ssh ssl-cert libpam-umask shtool" 2> /dev/null
  mrun "${_INSTAPP} xml-core xml2 xpdf libtool rrdtool" 2> /dev/null
  mrun "${_INSTAPP} ncurses-dev ncurses-term sipcalc" 2> /dev/null
  mrun "${_INSTAPP} netcat libzip-dev libwww-perl libsodium-dev" 2> /dev/null
  mrun "${_INSTAPP} libfontconfig1 libfreetype6 libfreetype6-dev" 2> /dev/null
  mrun "${_INSTAPP} libfribidi0 libgeoip-dev libgeoip1 libgmp3-dev" 2> /dev/null
  mrun "${_INSTAPP} libicu-dev libjpeg-dev libjpeg62" 2> /dev/null
  mrun "${_INSTAPP} libonig-dev libpq5 libxml2-dev libxpm4" 2> /dev/null
  mrun "${_INSTAPP} libxslt-dev libxslt1-dev libxslt1.1 subversion" 2> /dev/null
  mrun "${_INSTAPP} libaprutil1 libapr1 ldap-utils ipset" 2> /dev/null
  mrun "${_INSTAPP} libc-client-dev libc-client2007e libc-client2007e-dev" 2> /dev/null
  mrun "${_INSTAPP} pdftk patchutils p7zip-full fontconfig-config" 2> /dev/null
  mrun "${_INSTAPP} bison catdoc cython3 geoip-database gettext" 2> /dev/null
  mrun "${_INSTAPP} clamav clamav-base clamav-daemon clamdscan" 2> /dev/null
  mrun "${_INSTAPP} ghostscript htop icu-devtools lemon lftp nano" 2> /dev/null
  mrun "${_INSTAPP} python3-dev python3-debian python3-magic" 2> /dev/null
  mrun "apt --fix-broken install -y" 2> /dev/null
  fix_postfix
  st_runner "${_INSTAPP} ${_MAILSERV}" 2> /dev/null
  st_runner "${_INSTAPP} ${_APT_XTRA}" 2> /dev/null
  st_runner "${_INSTAPP} ${_EXTRA_LIB_APT}" 2> /dev/null
  st_runner "${_INSTAPP} ${_EXTRA_PACKAGES}" 2> /dev/null
  st_runner "${_INSTAPP} ${_SYSLOGD}" 2> /dev/null
  mrun "apt --fix-broken install -y" 2> /dev/null
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  _EXTRA_APT="tree"
  st_runner "apt-get install ${_EXTRA_APT} ${nrmUpArg}" 2> /dev/null
  if [ -e "/etc/init.d/php5-fpm" ]; then
    mrun "service php5-fpm stop" &> /dev/null
    mrun "update-rc.d -f php5-fpm remove" &> /dev/null
  fi
}

basic_packages_install_on_init() {
  apt-get remove --purge unscd -y &> /dev/null
  userdel -r debian &> /dev/null
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ]; then
    _APT_SHELLS=$(id -nG _apt 2>&1)
    if [[ "${_APT_SHELLS}" =~ "nogroup" ]]; then
      usermod -aG users _apt
    fi
  fi
  _MAN_SHELLS=$(id -nG man 2>&1)
  if [[ "${_MAN_SHELLS}" =~ "man" ]]; then
    usermod -aG users man
  fi
  if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
    && [ -e "/etc/apt/apt.conf.d" ]; then
    echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
  fi
  if [ ! -e "/etc/apt/apt.conf.d/99ignorestrict" ] \
    && [ -e "/etc/apt/apt.conf.d" ]; then
    echo "APT::Get::AllowInsecureRepositories \"true\";" > /etc/apt/apt.conf.d/99ignorestrict
    echo "APT::Get::AllowUnauthenticated \"true\";"     >> /etc/apt/apt.conf.d/99ignorestrict
    echo "Aptitude::CmdLine::Fix-Broken \"true\";"      >> /etc/apt/apt.conf.d/99ignorestrict
  fi
  if [ "${_STATUS}" = "INIT" ] || [ "${_STATUS}" = "SYSTEMD" ]; then
    if [ ! -e "/root/.step.init.basic.cnf" ]; then
      msg "INFO: Installing some basic tools, please wait..."
      apt-get clean -qq &> /dev/null
      rm -rf /var/lib/apt/lists/*
      apt-get update -qq &> /dev/null
      ${_INITINS} locales &> /dev/null
      fix_locales
      ${_INITINS} lsb-release &> /dev/null
      ${_INITINS} dnsutils &> /dev/null
      ${_INITINS} netcat &> /dev/null
      ${_INITINS} curl &> /dev/null
      ${_INITINS} wget &> /dev/null
      touch /root/.step.init.basic.cnf
    fi
  fi
  if [ "${_STATUS}" = "SYSTEMD" ]; then
    if [ ! -e "/root/.step.init.systemd.one.cnf" ]; then
      msg "INFO: This server is running systemd, which should be"
      msg "INFO: removed before installing BOA which involves"
      msg "INFO: procedure in five steps, as outlined below:"
      echo
      msg "STEP: 1. The 'boa init' command will install sysvinit"
      msg "STEP: 2. You will reboot the server"
      msg "STEP: 3. Run 'boa init' again so it can remove systemd"
      msg "STEP: 4. You will reboot the server again"
      msg "STEP: 5. Run boa standard install command"
      echo
      msg "STEP: Let's begin with STEP 1..."
      msg "INFO: Installing sysvinit on ${_THIS_OS} ${_OSR}..."
      mrun "apt-get update -qq" &> /dev/null
      mrun "${_INITINS} sysvinit-core" 2> /dev/null
      mrun "${_INITINS} sysvinit-utils" 2> /dev/null
      mrun "apt --fix-broken install -y" 2> /dev/null
      if [ -e "/usr/share/sysvinit/inittab" ]; then
        cp -af /usr/share/sysvinit/inittab /etc/inittab
        echo -e 'Package: systemd\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/systemd
        echo -e '\n\nPackage: *systemd*\nPin: origin ""\nPin-Priority: -1' >> /etc/apt/preferences.d/systemd
        mrun "apt-get update -qq" &> /dev/null
        mrun "${_INITINS} sysvinit-core" 2> /dev/null
        mrun "${_INITINS} sysvinit-utils" 2> /dev/null
        mrun "apt --fix-broken install -y" 2> /dev/null
        rm -f /etc/apt/sources.list.d/nosystemd.list
        rm -f /etc/apt/preferences.d/nosystemd
        msg "INFO: The sysvinit-core installed on ${_THIS_OS} ${_OSR}..."
        echo
        msg "STEP: Let's continue to STEP 2... Please reboot this server"
        msg "STEP: Once the system is up, run 'boa init' command again"
        touch /root/.step.init.systemd.one.cnf
      else
        echo
        msg "ALRT: The sysvinit has NOT been installed on ${_THIS_OS} ${_OSR}"
        msg "ALRT: Please check details in the logs located in /var/backups/"
      fi
      echo
      mrun "sleep 8"
      echo "Bye"
      clean_pid_exit
    fi
    if [ ! -e "/root/.step.init.systemd.two.cnf" ] \
      && [ -e "/root/.step.init.systemd.one.cnf" ]; then
      msg "STEP: Let's continue to STEP 3..."
      msg "INFO: Removing systemd on ${_THIS_OS} ${_OSR}..."
      mrun "${_INITINS} sysvinit-core" 2> /dev/null
      mrun "${_INITINS} sysvinit-utils" 2> /dev/null
      mrun "apt --fix-broken install -y" 2> /dev/null
      if [ -e "/usr/share/sysvinit/inittab" ]; then
        cp -af /usr/share/sysvinit/inittab /etc/inittab
        echo -e 'Package: systemd\nPin: origin ""\nPin-Priority: -1' > /etc/apt/preferences.d/systemd
        echo -e '\n\nPackage: *systemd*\nPin: origin ""\nPin-Priority: -1' >> /etc/apt/preferences.d/systemd
        mrun "${_INITINS} sysvinit-core" 2> /dev/null
        mrun "${_INITINS} sysvinit-utils" 2> /dev/null
        mrun "apt --fix-broken install -y" 2> /dev/null
        rm -f /etc/apt/sources.list.d/nosystemd.list
        rm -f /etc/apt/preferences.d/nosystemd
        mrun "apt-get remove systemd-sysv -y -qq --purge --auto-remove" 2> /dev/null
        mrun "apt-get remove systemd -y -qq --purge --auto-remove" 2> /dev/null
        mrun "apt-get remove libnss-systemd -y -qq --purge --auto-remove" 2> /dev/null
        mrun "apt --fix-broken install -y" 2> /dev/null
      else
        echo
        msg "ALRT: The sysvinit has NOT been installed on ${_THIS_OS} ${_OSR}"
        msg "ALRT: Please check details in the logs located in /var/backups/"
        echo
        mrun "sleep 8"
        echo "Bye"
        clean_pid_exit
      fi
      if [ ! -e "/lib/systemd/systemd" ]; then
        msg "INFO: The systemd has been removed on ${_THIS_OS} ${_OSR}"
        echo
        msg "STEP: Let's continue to STEP 4... Please reboot this server again"
        msg "STEP: Once the system is up, run standard boa install command"
        touch /root/.step.init.systemd.two.cnf
      else
        echo
        msg "ALRT: The systemd has NOT been removed on ${_THIS_OS} ${_OSR}"
        msg "ALRT: Please check details in the logs located in /var/backups/"
      fi
      echo
      msg "INFO: One more check to make sure that it works..."
      _CHECK_CRON=$(service cron status 2>&1)
      if [[ "${_CHECK_CRON}" =~ "running" ]]; then
        msg "INFO: OK, it works! ${_CHECK_CRON}"
        kill -9 $(ps aux | grep '[s]ystemd-udevd' | awk '{print $2}') &> /dev/null
      else
        msg "ALRT: Ouch! cron does not work ${_CHECK_CRON}"
        msg "ALRT: Please do not reboot until you manage to fix this!"
      fi
      echo
      mrun "sleep 8"
      echo "Bye"
      clean_pid_exit
    fi
  fi
}

more_packages_install_on_init() {
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing more basic tools now, please wait..."
    if [ -e "/etc/debian_version" ]; then
      _L_DEB_TEST=$(grep "^5." /etc/debian_version 2>&1)
      if [ ! -z "${_L_DEB_TEST}" ]; then
        sed -i "s/^deb.*security.debian.org.*/## security updates no longer available/g" ${aptLiSys} &> /dev/null
        wait
        sed -i "s/ftp.*debian.org/archive.debian.org/g" \
          ${aptLiSys} &> /dev/null
        wait
        sed -i "s/volatile.debian.org/archive.debian.org/g" \
          ${aptLiSys} &> /dev/null
        wait
      fi
    fi
    apt-get update -qq &> /dev/null
    ${_INITINS} locales &> /dev/null
    fix_locales
    ${_INITINS} git &> /dev/null
    ${_INITINS} git-core &> /dev/null
    ${_INITINS} git-man &> /dev/null
    ${_INITINS} aptitude &> /dev/null
    ${_INITINS} axel &> /dev/null
    ${_INITINS} hostname &> /dev/null
    ${_INITINS} net-tools &> /dev/null
    ${_INITINS} build-essential &> /dev/null
  fi
}

if_proxysql_update() {
  if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
    isPxy=$(which proxysql 2>&1)
    _REINSTALL_PXC=NO
    if [ -x "${isPxy}" ]; then
      _PXY=$(${isPxy} --version 2>&1 \
        | tr -d "\n" \
        | cut -d"-" -f1 \
        | awk '{ print $3}' 2>&1)
      msg "INFO: ProxySQL version detected ${_PXY}"
      pGc="/usr/bin/proxysql_galera_checker"
      if [ ! -e "${pGc}" ]; then
        _UP_PXC=YES
        _REINSTALL_PXC=YES
      else
        _PAV_TEST=$(grep Maestro ${pGc} 2>&1)
        if [[ ! "${_PAV_TEST}" =~ "Maestro" ]]; then
          _UP_PXC=YES
        fi
      fi
      pNm="/usr/bin/proxysql_node_monitor"
      if [ ! -e "${pNm}" ]; then
        _UP_PXC=YES
        _REINSTALL_PXC=YES
      else
        _PAV_TEST=$(grep Vivaldi ${pNm} 2>&1)
        if [[ ! "${_PAV_TEST}" =~ "Vivaldi" ]]; then
          _UP_PXC=YES
        fi
      fi
    fi
    isPxyVer=$(proxysql --version 2>&1)
    if [[ ! "${isPxyVer}" =~ "${_PXC_VRN}" ]]; then
      _UP_PXC=YES
    fi
    if [ "${_UP_PXC}" = "YES" ] \
      && [ "${_THIS_OS}" = "Debian" ]; then
      if [ "${_REINSTALL_PXC}" = "YES" ]; then
        msg "INFO: Running ProxySQL upgrade to ${_PXC_VRN}..."
      else
        msg "INFO: Running ProxySQL re-install to ${_PXC_VRN}..."
        mrun "apt-get clean" 2> /dev/null
        mrun "apt-get update -qq" 2> /dev/null
        mrun "${_INSTALL} sysbench" 2> /dev/null
        mrun "${_INSTALL} debconf-utils" 2> /dev/null
        mrun "apt-get remove proxysql -y" 2> /dev/null
        mrun "apt-get clean" 2> /dev/null
        mrun "apt-get update -qq" 2> /dev/null
        mrun "${_INSTALL} proxysql" 2> /dev/null
      fi
      isPxy=$(which proxysql 2>&1)
      if [ ! -x "${isPxy}" ]; then
        mrun "apt-get clean" 2> /dev/null
        mrun "apt-get update -qq" 2> /dev/null
        mrun "${_INSTALL} sysbench" 2> /dev/null
        mrun "${_INSTALL} debconf-utils" 2> /dev/null
        mrun "${_INSTALL} proxysql" 2> /dev/null
      else
        mrun "apt-get install --only-upgrade ${nrmUpArg} proxysql" 2> /dev/null
      fi
      if [ ! -e "/etc/proxysql.cnf" ]; then
        msg "OOPS: Unable to open config file /etc/proxysql.cnf"
      else
        chmod 640 /etc/proxysql.cnf
      fi
      if [ ! -e "/etc/proxysql-admin.cnf" ]; then
        msg "OOPS: Unable to open config file /etc/proxysql-admin.cnf"
      else
        chmod 640 /etc/proxysql-admin.cnf
      fi
      if [ -x "${isPxy}" ] \
        && [ -e "/etc/proxysql.cnf" ] \
        && [ -e "/etc/proxysql-admin.cnf" ]; then
        _PXY=$(${isPxy} --version 2>&1 \
          | tr -d "\n" \
          | cut -d"-" -f1 \
          | awk '{ print $3}' 2>&1)
        msg "INFO: ProxySQL version detected ${_PXY}"
        msg "INFO: Updating ProxySQL Node Monitor..."
        if [ -e "${pNm}" ]; then
          rm -f ${pNm}
        fi
        tBn="tools/bin"
        tURL="${urlHmr}/${tBn}/proxysql_node_monitor"
        msg "PNM download URL is ${tURL}"
        curl -I ${tURL}
        curl ${crlGet} "${tURL}" -o ${pNm}
        if [ ! -e "${pNm}" ]; then
          curl ${crlGet} "${tURL}" -o ${pNm}
        else
          _PAV_TEST=$(grep Vivaldi ${pNm} 2>&1)
          if [[ ! "${_PAV_TEST}" =~ "Vivaldi" ]]; then
            rm -f ${pNm}
            curl ${crlGet} "${tURL}" -o ${pNm}
          fi
        fi
        curl ${crlGet} "${tURL}" -o ${pNm}
        ls -la ${pNm}
        if [ -e "${pNm}" ]; then
          chmod 755 ${pNm}
          msg "INFO: `${pNm} --version`"
        fi

        msg "INFO: Updating ProxySQL Galera Checker..."
        if [ -e "${pGc}" ]; then
          rm -f ${pGc}
        fi
        tBn="tools/bin"
        tURL="${urlHmr}/${tBn}/proxysql_galera_checker"
        msg "PGC download URL is ${tURL}"
        curl -I ${tURL}
        curl ${crlGet} "${tURL}" -o ${pGc}
        if [ ! -e "${pGc}" ]; then
          curl ${crlGet} "${tURL}" -o ${pGc}
        else
          _PAV_TEST=$(grep Maestro ${pGc} 2>&1)
          if [[ ! "${_PAV_TEST}" =~ "Maestro" ]]; then
            rm -f ${pGc}
            curl ${crlGet} "${tURL}" -o ${pGc}
          fi
        fi
        curl ${crlGet} "${tURL}" -o ${pGc}
        ls -la ${pGc}

        if [ -e "${pGc}" ]; then
          chmod 755 ${pGc}
          msg "INFO: `${pGc} --version`"
          echo loadbal > /var/lib/proxysql/mode
          echo loadbal > /var/lib/proxysql/c1r_galera_mode
          echo loadbal > /var/lib/proxysql/--mode=singlewrite_mode
          echo loadbal > /var/lib/proxysql/--mode=loadbal_mode
          chown proxysql:proxysql /var/lib/proxysql/*mode*
          echo 0 > /var/lib/proxysql/reload
          echo 0 > /var/lib/proxysql/c1r_galera_reload
          chown proxysql:proxysql /var/lib/proxysql/*reload
          rm -f /var/lib/proxysql/pxc_test_proxysql_galera_check.log
          proxysql_galera_checker --log=/var/lib/proxysql/pxc_test_proxysql_galera_check.log --debug
          cat /var/lib/proxysql/pxc_test_proxysql_galera_check.log
          msg "INFO: Restarting ProxySQL server..."
          mrun "service proxysql restart" 2> /dev/null
          mysql -uadmin -p`cat /root/.my.proxysql_adm_pwd.txt` -h127.0.0.1 -P6032 -e "SELECT * FROM scheduler\G"
          mysql -uadmin -p`cat /root/.my.proxysql_adm_pwd.txt` -h127.0.0.1 -P6032 -e "SELECT * FROM mysql_servers;"
        else
          msg "OOPS: ProxySQL Galera Checker will not work!"
        fi
      else
        msg "OOPS: ProxySQL will not work!"
      fi
    fi
  fi
}

if_post_major_os_upgrade() {
  if [ -e "/root/run_post_major_os_upgrade.info" ]; then
    msg "INFO: Running dist-upgrade to complete the major system upgrade.."
    mrun "apt-get update --allow-insecure-repositories -qq" 2> /dev/null
    mrun "apt-get dist-upgrade ${dstUpArg}" 2> /dev/null
    mrun "apt-get ${dstUpArg} install" 2> /dev/null
    msg "INFO: Cleaning up any systemd remnants.."
    mrun "apt-get remove systemd-sysv -y -qq --purge --auto-remove" 2> /dev/null
    mrun "apt-get remove systemd -y -qq --purge --auto-remove" 2> /dev/null
    mrun "apt-get remove libnss-systemd -y -qq --purge --auto-remove" 2> /dev/null
    mrun "apt --fix-broken install -y" 2> /dev/null
    msg "INFO: Removing any packages orphaned by the migration process.."
    mrun "apt-get autoremove --purge -y -qq" 2> /dev/null
    mrun "apt-get autoclean -y -qq" 2> /dev/null
    rm -f /root/run_post_major_os_upgrade.info
    msg "INFO: The post_major_os_upgrade procedure is complete."
  fi
}

if_major_os_upgrade() {
  if [ -e "/root/run_post_major_os_upgrade.info" ]; then
    rm -f /root/run_post_major_os_upgrade.info
  fi
  define_loc_osr
  if [ ! -z "${_MSG_LOC}" ]; then
    msg "WARN: ${_MSG_LOC} upgrade will start in 60 seconds..."
    msg "WARN: Now pray it will work... or hit ctrl-c to stop now!"
    if [ ! -e "/root/.upstart.cnf" ]; then
      service cron stop &> /dev/null
      mrun "sleep 60"
    fi
    check_dns_settings
    if [ "${_USE_PROVIDER_DNS}" != "YES" ]; then
      if [ -e "/etc/resolv.conf" ]; then
        mv -f /etc/resolv.conf /etc/resolv.conf.pre-dist-upgrade
      fi
      rm -f /etc/resolv.conf
      echo "nameserver 1.1.1.1" >/etc/resolv.conf
      echo "nameserver 1.0.0.1" >>/etc/resolv.conf
      if [ -e "/etc/resolv.conf.pre-dist-upgrade" ]; then
        cat /etc/resolv.conf.pre-dist-upgrade >>/etc/resolv.conf
      fi
    fi
    rm -f ${pthLog}/ruby-sys-clean-reload.log
    mv -f /var/xdrago /var/xdrago_wait &> /dev/null
    msg "WARN: Too late! ${_MSG_LOC} upgrade in progress..."
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
    mrun "apt-get update -qq" 2> /dev/null
    mrun "apt-get remove collectd      -y -qq" 2> /dev/null
    mrun "apt-get remove libc-client2007b-dev -y -qq" 2> /dev/null
    mrun "apt-get remove nginx-extras  -y -qq" 2> /dev/null
    mrun "apt-get remove nginx         -y -qq" 2> /dev/null
    mrun "apt-get remove nginx-common  -y -qq" 2> /dev/null
    mrun "apt-get remove nginx-full    -y -qq" 2> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      touch /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      touch /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    mrun "apt-get remove php5 \
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
                         php5-xsl      -y -qq" 2> /dev/null
    mrun "apt-get remove phpunit       -y -qq" 2> /dev/null
    mrun "apt-get remove php-pear      -y -qq" 2> /dev/null
    mrun "apt-get remove php-benchmark -y -qq" 2> /dev/null
    mrun "apt-get remove php5-cli      -y -qq" 2> /dev/null
    mrun "apt-get remove php5-common   -y -qq" 2> /dev/null
    mrun "apt-get remove php5-apc      -y -qq" 2> /dev/null
    mrun "apt-get remove php-apc       -y -qq" 2> /dev/null
    if [ "${_LOC_OSR}" = "jessie" ]; then
      mrun "apt-get purge gnome-tweak-tool -y -qq" 2> /dev/null
    fi
    if [ "${_LOC_OSR}" = "stretch" ]; then
      mrun "apt-get purge libpam-systemd -y -qq" 2> /dev/null
    fi
    echo "curl install"           | dpkg --set-selections &> /dev/null
    echo "git install"            | dpkg --set-selections &> /dev/null
    echo "git-core install"       | dpkg --set-selections &> /dev/null
    echo "git-man install"        | dpkg --set-selections &> /dev/null
    echo "libssl-dev install"     | dpkg --set-selections &> /dev/null
    echo "openssh-client install" | dpkg --set-selections &> /dev/null
    echo "openssh-server install" | dpkg --set-selections &> /dev/null
    echo "openssh-sftp-server install" | dpkg --set-selections &> /dev/null
    echo "openssl install"        | dpkg --set-selections &> /dev/null
    echo "ssh install"            | dpkg --set-selections &> /dev/null
    echo "zlib1g install"         | dpkg --set-selections &> /dev/null
    echo "zlib1g-dev install"     | dpkg --set-selections &> /dev/null
    echo "zlibc install"          | dpkg --set-selections &> /dev/null
    mrun "${_INSTALL} zlib1g"     2> /dev/null
    mrun "${_INSTALL} zlib1g-dev" 2> /dev/null
    mrun "${_INSTALL} zlibc"      2> /dev/null
    mrun "${_INSTALL} openssl"    2> /dev/null
    mrun "${_INSTALL} libssl-dev" 2> /dev/null
    mrun "apt-get install curl ${forCer}"           2> /dev/null
    mrun "apt-get install git ${forCer}"            2> /dev/null
    mrun "apt-get install git-core ${forCer}"       2> /dev/null
    mrun "apt-get install git-man ${forCer}"        2> /dev/null
    sed -i "s/^PermitRootLogin.*/#PermitRootLogin yes/g" \
      /etc/ssh/sshd_config &> /dev/null
    mrun "apt-get install openssh-client ${forCer}" 2> /dev/null
    mrun "apt-get install openssh-server ${forCer}" 2> /dev/null
    mrun "apt-get install ssh ${forCer}"            2> /dev/null
    if [ -e "/usr/bin/java" ] \
      || [ -e "/usr/bin/java7" ] \
      || [ -e "/usr/bin/java8" ] \
      || [ -e "/usr/bin/java11" ]; then
      mrun "apt-get install default-jre ${forCer}" 2> /dev/null
    fi
    ###
    ### Make sure that udev is installed first, if needed.
    if [ "${_VMFAMILY}" != "VS" ]; then
      mrun "apt-get install udev ${dstUpArg}" 2> /dev/null
    fi
    ###
    ### Run pre-migration upgrade in the current OS version.
    mrun "apt-get upgrade ${nrmUpArg}" 2> /dev/null
    mrun "apt-get dist-upgrade ${nrmUpArg}" 2> /dev/null
    ###
    ### Check if we can continue.
    _AUDIT_DPKG=$(dpkg --audit 2>&1)
    if [ ! -z "${_AUDIT_DPKG}" ]; then
      msg "ALRT! I can not continue until dpkg --audit is clean"
      msg "ALRT! ${_AUDIT_DPKG}"
      msg "ALRT! Aborting installer NOW!"
      clean_pid_exit
    fi
    _HOLD_TEST_DPKG=$(dpkg --get-selections | grep 'hold$' 2>&1)
    if [ ! -z "${_HOLD_TEST_DPKG}" ]; then
      msg "ALRT! I can not continue until these packages are un-hold"
      msg "ALRT! ${_HOLD_TEST_DPKG}"
      msg "ALRT! Aborting installer NOW!"
      clean_pid_exit
    fi
    _HOLD_TEST_ATE=$(aptitude search "~ahold" 2>&1)
    if [ ! -z "${_HOLD_TEST_ATE}" ]; then
      msg "ALRT! I can not continue until these packages are un-hold"
      msg "ALRT! ${_HOLD_TEST_ATE}"
      msg "ALRT! Aborting installer NOW!"
      clean_pid_exit
    fi
    ###
    ### Switching gears on the fly.
    if [ "${_TGT_OSN}" = "Devuan" ]; then
      echo "## DEVUAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_MIRROR}/merged/ ${_NEW_OSR} main" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/merged/ ${_NEW_OSR}-updates main" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## DEVUAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/merged/ ${_NEW_OSR}-security main" | fmt -su -w 2500 >> ${aptLiSys}
      if [ -e "/etc/apt/apt.conf" ]; then
        sed -i "s/APT::Default-Release.*/APT::Default-Release \"${_NEW_OSR}\";/g" \
          /etc/apt/apt.conf &> /dev/null
        wait
      fi
      ###
      ### Add devuan-keyring first.
      mrun "apt-get update --allow-insecure-repositories -qq" 2> /dev/null
      mrun "${_INITINS} devuan-keyring --allow-unauthenticated" 2> /dev/null
    else
      echo "## DEBIAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_MIRROR}/debian/ ${_OSR} main contrib non-free" >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/debian/ ${_OSR} main contrib non-free" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/debian/ ${_OSR}-updates main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/debian/ ${_OSR}-updates main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## DEBIAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://security.debian.org/debian-security ${_OSR}-security main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://security.debian.org/debian-security ${_OSR}-security main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      if [ -e "/etc/apt/apt.conf" ]; then
        sed -i "s/APT::Default-Release.*/APT::Default-Release \"${_NEW_OSR}\";/g" \
          /etc/apt/apt.conf &> /dev/null
        wait
      fi
    fi
    ###
    ### Update packages registry.
    mrun "apt-get update --allow-insecure-repositories -qq" 2> /dev/null
    ###
    ### Two step upgrade with apt-get only.
    mrun "apt-get install apt -t ${_NEW_OSR} ${dstUpArg}" 2> /dev/null
    mrun "apt-get update --allow-insecure-repositories -qq" 2> /dev/null
    ###
    ### Requirement for Debian Stretch to Devuan Beowulf migration.
    ### The libtinfo package needs to be upgraded to prevent breaks.
    if [ "${_LOC_OSR}" = "stretch" ]; then
      mrun "apt-get install libtinfo6 ${dstUpArg}" 2> /dev/null
    fi
    ###
    ### Note that this upgrade does not complete the migration yet.
    mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
    mrun "apt-get install apt dpkg aptitude util-linux ${dstUpArg}" 2> /dev/null
    ###
    ### Back to BOA stuff re-install as needed.
    install_upgrade_nginx
    if [ -e "/etc/init.d/bind9" ] && [ ! -e "/etc/init.d/bind" ]; then
      ln -sf /etc/init.d/bind9 /etc/init.d/bind
    fi
    if [ -e "${mtrInc}/nginx_vhost_common.conf" ]; then
      if [ -e "/root/.debug.cnf" ]; then
        mv -f /etc/init.d/networking /etc/init.d/networking.bak
        cp -af /etc/init.d/networking.dpkg-dist /etc/init.d/networking
        chmod 755 /etc/init.d/networking
      fi
      ll /etc/init.d/networking
    fi
    if [ -d "/var/www/cgp" ]; then
      mrun "apt-get install collectd ${dstUpArg}" 2> /dev/null
    fi
    mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
    mrun "apt-get install libc-client2007e-dev ${dstUpArg}" 2> /dev/null
    ###
    ### Make sure that sysvinit-core is installed.
    mrun "${_INITINS} sysvinit-core" 2> /dev/null
    mrun "${_INITINS} sysvinit-utils" 2> /dev/null
    mrun "apt --fix-broken install -y" 2> /dev/null
    if [ "${_TGT_OSN}" = "Devuan" ]; then
      ###
      ### The last step before migration to Devuan is to switch to eudev.
      ### Jessie exception needs testing, though.
      if [ "${_LOC_OSR}" != "jessie" ]; then
        mrun "apt-get install eudev ${dstUpArg}" 2> /dev/null
      fi
    fi
    ###
    ### Upgrade all packages so that you have the latest versions.
    if [ "${_LOC_OSR}" = "stretch" ]; then
      mrun "apt-get full-upgrade ${dstUpArg}" 2> /dev/null
    else
      mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
    fi
    ###
    ### Force install/upgrade to give it another chance to complete.
    mrun "apt-get ${dstUpArg} install" 2> /dev/null
    ###
    ### Upgrade again all packages so that you have the latest versions.
    if [ "${_LOC_OSR}" = "stretch" ]; then
      mrun "apt-get full-upgrade ${dstUpArg}" 2> /dev/null
    else
      mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
    fi
    ###
    ### Finally, the proper dist-upgrade time.
    ### Note that Debian Bullseye to Devuan Chimaera migration
    ### requires the dist-upgrade step to be run AFTER reboot!
    if [ "${_LOC_OSR}" = "bullseye" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      msg "ATTN: NOTE! Debian Bullseye to Devuan Chimaera migration"
      msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot."
    else
      mrun "apt-get dist-upgrade ${dstUpArg}" 2> /dev/null
    fi
    ###
    ### Time for init scripts cleanup for VM running beng kernel.
    _VM_TEST=$(uname -a 2>&1)
    if [[ "${_VM_TEST}" =~ "-beng" ]]; then
      _PTMX=OK
      _REMOVE_LINKS="buagent \
                     checkroot.sh \
                     fancontrol \
                     halt \
                     hwclock.sh \
                     hwclockfirst.sh \
                     ifupdown \
                     ifupdown-clean \
                     kerneloops \
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
                     procps \
                     reboot \
                     sendsigs \
                     setserial \
                     svscan \
                     sysstat \
                     umountfs \
                     umountnfs.sh \
                     umountroot \
                     urandom \
                     vnstat"
      for link in ${_REMOVE_LINKS}; do
        if [ -e "/etc/init.d/${link}" ]; then
          update-rc.d -f ${link} remove &> /dev/null
          mv -f /etc/init.d/${link} /var/backups/init.d.${link}
        fi
      done
      for s in cron dbus ssh; do
        if [ -e "/etc/init.d/${s}" ]; then
          sed -rn -e 's/^(# Default-Stop:).*$/\1 0 1 6/' -e '/^### BEGIN INIT INFO/,/^### END INIT INFO/p' /etc/init.d/${s} > /etc/insserv/overrides/${s}
        fi
      done
      /sbin/insserv -v -d &> /dev/null
    else
      _PTMX=CHECK
    fi
    ###
    ### For extra debugging only.
    if [ -e "/root/.debug.cnf" ]; then
      _PTS_TEST=$(cat /proc/mounts | grep devpts 2>&1)
      if [[ ! "${_PTS_TEST}" =~ "devpts" ]] && [ ! -e "/dev/pts/ptmx" ]; then
        _PTS=FIX
      else
        _PTS=OK
      fi
      if [ "${_PTMX}" = "CHECK" ] && [ "${_PTS}" = "FIX" ]; then
        msg "WARN: Required /dev/pts/ptmx does not exist! We will fix this now..."
        mkdir -p /dev/pts
        rm -rf /dev/pts/*
        apt-get update -qq &> /dev/null
        apt-get install udev -y --allow-unauthenticated &> /dev/null
        echo "devpts          /dev/pts        devpts  rw,noexec,nosuid,gid=5,mode=620 0  0" >> /etc/fstab
        mount -t devpts devpts /dev/pts &> /dev/null
      fi
    fi
    ###
    ### Make sure that Aegir Master system user is added to sudo.
    _VAR_IF_PRESENT=$(grep "aegir ALL=NOPASSWD" /etc/sudoers 2>&1)
    if [[ ! "${_VAR_IF_PRESENT}" =~ "aegir ALL=NOPASSWD" ]]; then
      echo "aegir ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
    fi
    ###
    ### Make sure that Aegir special system-wide scripts are added to sudo.
    SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership)
    for SCRIPT in ${SCRIPTS[@]}; do
      _VAR_IF_PRESENT=$(grep "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" /etc/sudoers.d/${SCRIPT} 2>&1)
      if [[ ! "${_VAR_IF_PRESENT}" =~ "aegir ALL=NOPASSWD" ]]; then
        echo "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" >> /etc/sudoers.d/${SCRIPT}
        chmod 0440 /etc/sudoers.d/${SCRIPT}
      fi
    done
    ###
    ### Make sure that Aegir Octopus system users are added to sudo.
    for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
      if [ -e "${User}/config/server_master/nginx/vhost.d" ] \
        && [ ! -e "${User}/log/proxied.pid" ] \
        && [ ! -e "${User}/log/CANCELLED" ]; then
        _HM_U=$(echo ${User} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _VAR_IF_PRESENT=$(grep "${_HM_U} ALL=NOPASSWD" /etc/sudoers 2>&1)
        if [[ ! "${_VAR_IF_PRESENT}" =~ "${_HM_U} ALL=NOPASSWD" ]]; then
          echo "${_HM_U} ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
        fi
        SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership)
        for SCRIPT in ${SCRIPTS[@]}; do
          _VAR_IF_PRESENT=$(grep "${_HM_U} ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" /etc/sudoers.d/${SCRIPT} 2>&1)
          if [[ ! "${_VAR_IF_PRESENT}" =~ "${_HM_U} ALL=NOPASSWD" ]]; then
            echo "${_HM_U} ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" >> /etc/sudoers.d/${SCRIPT}
            chmod 0440 /etc/sudoers.d/${SCRIPT}
          fi
        done
      fi
    done
    ###
    ### Final cleanup.
    echo rotate > /var/log/syslog
    rm -f /var/xdrago/log/*.log
    mv -f /var/xdrago_wait /var/xdrago &> /dev/null
    ###
    ### Add ctrl file to trigger if_post_major_os_upgrade() after reboot.
    touch /root/run_post_major_os_upgrade.info
    echo " "
    msg "INFO: No errors? Then ${_MSG_LOC} upgrade was successful :)"
    msg "INFO: REBOOT your system once Barracuda completes THIS run AND.."
    msg "INFO: THEN remember to RUN ANOTHER Barracuda full upgrade"
    echo " "
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
        rm -f jcameron-key.gpg*
        wget -q -U iCab ${urlDev}/jcameron-key.gpg
        _KEYS_SERVER_TEST=$(grep GnuPG jcameron-key.gpg 2>&1)
        sleep 2
      done
      cat jcameron-key.gpg | ${_GPG} --import &> /dev/null
      rm -f jcameron-key.gpg*
      touch ${pthLog}/webmin_update_apt_src.log
    fi
  fi
}

sys_packages_update() {
  msg "INFO: Running system packages update..."
  if [ -e "/var/aegir" ]; then
    echo "curl install"           | dpkg --set-selections &> /dev/null
    echo "git install"            | dpkg --set-selections &> /dev/null
    echo "git-core install"       | dpkg --set-selections &> /dev/null
    echo "git-man install"        | dpkg --set-selections &> /dev/null
    echo "libssl-dev install"     | dpkg --set-selections &> /dev/null
    echo "openssh-client install" | dpkg --set-selections &> /dev/null
    echo "openssh-server install" | dpkg --set-selections &> /dev/null
    echo "openssh-sftp-server install" | dpkg --set-selections &> /dev/null
    echo "openssl install"        | dpkg --set-selections &> /dev/null
    echo "ssh install"            | dpkg --set-selections &> /dev/null
    echo "zlib1g install"         | dpkg --set-selections &> /dev/null
    echo "zlib1g-dev install"     | dpkg --set-selections &> /dev/null
    echo "zlibc install"          | dpkg --set-selections &> /dev/null
  fi
  update_webmin_apt
  st_runner "apt --fix-broken install -y" 2> /dev/null
  st_runner "dpkg --configure --force-all -a" 2> /dev/null
  st_runner "apt-get update -qq" &> /dev/null
  st_runner "apt-get upgrade ${nrmUpArg}" 2> /dev/null
  if [ "${_LOC_OSR}" = "bullseye" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
    _SAFE_TO_DIST=NO
  else
    st_runner "apt-get dist-upgrade ${nrmUpArg}" 2> /dev/null
  fi
  st_runner "apt --fix-broken install -y" 2> /dev/null
  st_runner "dpkg --configure --force-all -a" 2> /dev/null
  _DB_SERVER_TEST=$(mysql -V 2>&1)
  if [ "${_STATUS}" = "INIT" ]; then
    st_runner "aptitude full-upgrade -f -y -q \
      --allow-untrusted \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold" &> /dev/null
    st_runner "apt-get update -qq" &> /dev/null
    st_runner "aptitude full-upgrade -f -y -q \
      --allow-untrusted \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold" &> /dev/null
    st_runner "aptitude autoclean -y" &> /dev/null
  else
    echo "gnupg-curl install" | dpkg --set-selections &> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      touch /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      touch /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    mrun "${_RMAPP} php5 \
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
      php5-xsl" &> /dev/null
    mrun "${_RMAPP} phpunit php-pear php-benchmark" &> /dev/null
    mrun "${_RMAPP} php5-cli php5-common" &> /dev/null
    mrun "${_RMAPP} php5-apc" &> /dev/null
    mrun "${_RMAPP} php-apc" &> /dev/null
    mrun "${_RMAPP} apache2.2-common" &> /dev/null
    mrun "${_RMAPP} apache2.2-bin" &> /dev/null
    mrun "aptitude install lsof -y --allow-untrusted" &> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      rm -f /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      rm -f /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    rm -f /var/lib/mysql/debian-*.flag &> /dev/null
    if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
      service lfd stop &> /dev/null
      sleep 3
      kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
      killall sleep &> /dev/null
      rm -f /etc/csf/csf.error
      csf -x &> /dev/null
    fi
    _UP_JDK=NO
    _UP_LNX=NO
    _UP_NRC=NO
    _UP_PHP=NO
    _UP_PXC=NO
    _UP_SQL=NO
    check_apt_updates
  fi
}

sys_packages_install() {
  if_to_do_fix
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
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ "${_OSR}" = "trusty" ] \
        || [ "${_OSR}" = "precise" ]; then
        _APT_XTRA="openjdk-7-jre-headless ca-certificates-java nginx"
      elif [ "${_OSR}" = "jessie" ]; then
        _APT_XTRA="openjdk-7-jre-headless ca-certificates-java nginx"
      elif [ "${_OSR}" = "stretch" ]; then
        _APT_XTRA="openjdk-8-jre-headless ca-certificates-java nginx"
      elif [ "${_OSR}" = "buster" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java nginx"
      elif [ "${_OSR}" = "bullseye" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java nginx"
      elif [ "${_OSR}" = "beowulf" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java nginx"
      elif [ "${_OSR}" = "chimaera" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java nginx"
      fi
    else
      _APT_XTRA="nginx"
    fi
    _APT_ELSE="netcat nginx"
  else
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-6-jdk | grep install 2>&1)
    if [[ "${_APT_ITEM}" =~ "install" ]]; then
      mrun "apt-get remove openjdk-6-jdk -y -qq" &> /dev/null
      mrun "apt-get purge openjdk-6-jdk -y -qq" &> /dev/null
    fi
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-7-jdk | grep install 2>&1)
    if [[ "${_APT_ITEM}" =~ "install" ]]; then
      mrun "apt-get remove openjdk-7-jdk -y -qq" &> /dev/null
      mrun "apt-get purge openjdk-7-jdk -y -qq" &> /dev/null
    fi
    if [[ "${_XTRAS_LIST}" =~ "SR" ]] \
      || [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ "${_OSR}" = "trusty" ] \
        || [ "${_OSR}" = "precise" ]; then
        _APT_XTRA="openjdk-7-jre-headless ca-certificates-java"
      elif [ "${_OSR}" = "jessie" ]; then
        _APT_XTRA="openjdk-7-jre-headless ca-certificates-java"
      elif [ "${_OSR}" = "stretch" ]; then
        _APT_XTRA="openjdk-8-jre-headless ca-certificates-java"
      elif [ "${_OSR}" = "buster" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java"
      elif [ "${_OSR}" = "bullseye" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java"
      elif [ "${_OSR}" = "beowulf" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java"
      elif [ "${_OSR}" = "chimaera" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java"
      fi
    else
      _APT_XTRA=""
    fi
    _APT_ELSE="netcat"
    mrun "apt-get -f install -qq"             &> /dev/null
    mrun "service nginx start"                &> /dev/null
    mrun "apt-get remove nginx-extras -y -qq" &> /dev/null
    mrun "apt-get remove nginx -y -qq"        &> /dev/null
    mrun "apt-get remove nginx-common -y -qq" &> /dev/null
    mrun "apt-get remove nginx-full -y -qq"   &> /dev/null
    mrun "apt-get remove redis-server -y -qq" &> /dev/null
    st_runner "apt-get update -qq"            &> /dev/null
  fi
  _EXTRA_LIB_APT="libmcrypt-dev"
  if [ ! -z "${_EXTRA_PACKAGES}" ]; then
    _EXTRA_PACKAGES="screen ${_EXTRA_PACKAGES}"
  else
    _EXTRA_PACKAGES="screen"
  fi
  if [ -e "/proc/bean_counters" ]; then
    _IS_VZ=YES
  else
    _IS_VZ=NO
  fi
  if [ "${_IS_VZ}" = "YES" ]; then
    _SYSLOGD=inetutils-syslogd
    mrun "apt-get purge sysklogd -y" &> /dev/null
    mrun "apt-get purge rsyslog -y" &> /dev/null
    mrun "killall -9 sysklogd" &> /dev/null
    mrun "killall -9 rsyslogd" &> /dev/null
  elif [ -e "/root/.use.sysklogd.cnf" ] \
    || [ "${_OSR}" = "trusty" ] \
    || [ "${_OSR}" = "precise" ]; then
    _SYSLOGD=sysklogd
    mrun "apt-get purge rsyslog -y" &> /dev/null
    mrun "killall -9 rsyslogd" &> /dev/null
  else
    _SYSLOGD=rsyslog
  fi

  if [ "${_OSR}" = "chimaera" ]; then
    _EXTRA_PACKAGES="autoconf2.69 \
                     automake1.11 \
                     automake-1.16 \
                     gnupg1-curl \
                     libpcre2-dev \
                     libpcre2-posix2 \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng16-16 \
                     libtinfo6 \
                     software-properties-common \
                     ${_EXTRA_PACKAGES}"
  elif [ "${_OSR}" = "beowulf" ]; then
    _EXTRA_PACKAGES="autoconf2.64 \
                     automake1.11 \
                     automake-1.15 \
                     automake-1.16 \
                     gnupg1-curl \
                     libpcre2-dev \
                     libpcre2-posix0 \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng16-16 \
                     libtinfo6 \
                     software-properties-common \
                     ttf-dejavu \
                     ttf-dejavu-core \
                     ttf-dejavu-extra \
                     ${_EXTRA_PACKAGES}"
  elif [ "${_OSR}" = "bullseye" ]; then
    _EXTRA_PACKAGES="autoconf2.69 \
                     automake1.11 \
                     automake-1.16 \
                     gnupg1-curl \
                     libpcre2-dev \
                     libpcre2-posix2 \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng16-16 \
                     libtinfo6 \
                     software-properties-common \
                     ${_EXTRA_PACKAGES}"
  elif [ "${_OSR}" = "buster" ]; then
    _EXTRA_PACKAGES="autoconf2.64 \
                     automake1.11 \
                     automake-1.15 \
                     automake-1.16 \
                     gnupg1-curl \
                     libpcre2-dev \
                     libpcre2-posix0 \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng16-16 \
                     libtinfo6 \
                     software-properties-common \
                     ttf-dejavu \
                     ttf-dejavu-core \
                     ttf-dejavu-extra \
                     ${_EXTRA_PACKAGES}"
  elif [ "${_OSR}" = "stretch" ]; then
    _EXTRA_PACKAGES="autoconf2.64 \
                     automake1.11 \
                     automake-1.15 \
                     gnupg1-curl \
                     libpcre2-dev \
                     libpcre2-posix0 \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng16-16 \
                     software-properties-common \
                     ttf-dejavu \
                     ttf-dejavu-core \
                     ttf-dejavu-extra \
                     ${_EXTRA_PACKAGES}"
  else
    _EXTRA_PACKAGES="autoconf2.13 \
                     automake1.4 \
                     defoma \
                     gnupg-curl \
                     libpcre3 \
                     libpcre3-dev \
                     libpng12-0 \
                     libpng12-dev \
                     libt1-5 \
                     libt1-dev \
                     python-software-properties \
                     t1lib-bin \
                     ttf-dejavu \
                     ttf-dejavu-core \
                     ttf-dejavu-extra \
                     ${_EXTRA_PACKAGES}"
  fi

  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ] \
    || [ "${_OSR}" = "trusty" ]; then
    _EXTRA_PACKAGES="libgd3 \
                     libkrb5-dev \
                     libldap-dev \
                     libxpm-dev \
                     libwebp-dev \
                     ${_EXTRA_PACKAGES}"
  else
    _EXTRA_PACKAGES="libgd2-xpm \
                     ${_EXTRA_PACKAGES}"
  fi

  if [[ "${_XTRAS_LIST}" =~ "IMG" ]] \
    || [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
    || [[ "${_THISHOST}" =~ ".o8.io" ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
    || [ -e "/root/.auto.up.cnf" ] \
    || [ -e "/root/.host8.cnf" ]; then
    _EXTRA_PACKAGES="advancecomp \
                     jpegoptim \
                     libjpeg-progs \
                     optipng \
                     pngcrush \
                     pngquant \
                     ${_EXTRA_PACKAGES}"
  fi

  if [ "${_VMFAMILY}" != "VS" ] && [ "${_THIS_OS}" != "Devuan" ]; then
    _EXTRA_PACKAGES="udev \
                     ${_EXTRA_PACKAGES}"
  fi

  _MAGICK_FROM_SOURCES=YES
  if [ "${_MAGICK_FROM_SOURCES}" = "NO" ] \
    || [ -z "${_MAGICK_FROM_SOURCES}" ]; then
    _EXTRA_PACKAGES="imagemagick \
                     ${_EXTRA_PACKAGES}"
  fi

  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ] \
    || [ "${_OSR}" = "trusty" ] \
    || [ "${_OSR}" = "precise" ]; then
    _MAILSERV="postfix postfix-pcre"
  fi
}

fix_libs_php() {
  if_to_do_fix
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ] \
    || [ "${_DO_FIX}" = "YES" ] \
    || [ "${_OSR}" = "trusty" ] \
    || [ "${_OSR}" = "precise" ]; then
    if [ ! -L "/usr/lib/librtmp.so" ] \
      || [ ! -e "/usr/lib/libgmp.so.3" ] \
      || [ ! -e "/usr/lib/libcurl.so" ] \
      || [ ! -e "/usr/include/gmp.h" ]; then
      msg "INFO: Fix #1 for libs in ${_THIS_OS} ${_OSR}"
      _X86_64_TEST=$(uname -m 2>&1)
      if [ "${_X86_64_TEST}" = "x86_64" ]; then
        ln -sf /usr/lib/x86_64-linux-gnu/libgmp.so  /usr/lib/libgmp.so
        ln -sf /usr/lib/x86_64-linux-gnu/libgmp.so  /usr/lib/libgmp.so.3
        ln -sf /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib/libjpeg.so
        ln -sf /usr/lib/x86_64-linux-gnu/libkrb5.so /usr/lib/libkrb5.so
        ln -sf /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so
        ln -sf /usr/lib/x86_64-linux-gnu/libpng.so  /usr/lib/libpng.so
        ln -sf /usr/lib/x86_64-linux-gnu/libXpm.so  /usr/lib/libXpm.so
        ln -sf /usr/lib/x86_64-linux-gnu/librtmp.so /usr/lib/librtmp.so
        ln -sf /usr/lib/x86_64-linux-gnu/libcurl.so /usr/lib/libcurl.so
        if [ ! -e "/usr/include/curl/curl.h" ] \
          && [ -e "/usr/include/x86_64-linux-gnu/curl/curl.h" ]; then
          ln -s /usr/include/x86_64-linux-gnu/curl /usr/include/curl
        fi
        if [ ! -e "/usr/include/gmp.h" ] \
          && [ -e "/usr/include/x86_64-linux-gnu/gmp.h" ]; then
          ln -sf /usr/include/x86_64-linux-gnu/gmp.h  /usr/include/gmp.h
        fi
        if [ ! -e "/usr/lib/x86_64-linux-gnu/librtmp.so.0" ] \
          && [ -e "/usr/lib/x86_64-linux-gnu/librtmp.so.1" ]; then
          cd /usr/lib/x86_64-linux-gnu
          ln -sf librtmp.so.1 librtmp.so.0
        fi
      else
        ln -sf /usr/lib/i386-linux-gnu/libgmp.so  /usr/lib/libgmp.so
        ln -sf /usr/lib/i386-linux-gnu/libgmp.so  /usr/lib/libgmp.so.3
        ln -sf /usr/lib/i386-linux-gnu/libjpeg.so /usr/lib/libjpeg.so
        ln -sf /usr/lib/i386-linux-gnu/libkrb5.so /usr/lib/libkrb5.so
        ln -sf /usr/lib/i386-linux-gnu/libldap.so /usr/lib/libldap.so
        ln -sf /usr/lib/i386-linux-gnu/libpng.so  /usr/lib/libpng.so
        ln -sf /usr/lib/i386-linux-gnu/libXpm.so  /usr/lib/libXpm.so
        ln -sf /usr/lib/i386-linux-gnu/librtmp.so /usr/lib/librtmp.so
        ln -sf /usr/lib/i386-linux-gnu/libcurl.so /usr/lib/libcurl.so
        if [ ! -e "/usr/include/curl/curl.h" ] \
          && [ -e "/usr/include/i386-linux-gnu/curl/curl.h" ]; then
          ln -s /usr/include/i386-linux-gnu/curl /usr/include/curl
        fi
        if [ ! -e "/usr/include/gmp.h" ] \
          && [ -e "/usr/include/i386-linux-gnu/gmp.h" ]; then
          ln -sf /usr/include/i386-linux-gnu/gmp.h  /usr/include/gmp.h
        fi
        if [ ! -e "/usr/lib/i386-linux-gnu/librtmp.so.0" ] \
          && [ -e "/usr/lib/i386-linux-gnu/librtmp.so.1" ]; then
          cd /usr/lib/i386-linux-gnu
          ln -sf librtmp.so.1 librtmp.so.0
        fi
      fi
    fi
  fi
}

fix_libssl() {
  if_to_do_fix
  if [ "${_OSR}" = "chimaera" ] \
    || [ "${_OSR}" = "beowulf" ] \
    || [ "${_OSR}" = "bullseye" ] \
    || [ "${_OSR}" = "buster" ] \
    || [ "${_OSR}" = "stretch" ] \
    || [ "${_OSR}" = "jessie" ] \
    || [ "${_DO_FIX}" = "YES" ] \
    || [ "${_OSR}" = "trusty" ] \
    || [ "${_OSR}" = "precise" ]; then
    _SSL_FIX_REQUIRED=YES
    if [ "${_NGINX_SPDY}" = "YES" ] \
      || [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
      if [ "${_OSR}" = "chimaera" ] \
        || [ "${_OSR}" = "beowulf" ] \
        || [ "${_OSR}" = "bullseye" ] \
        || [ "${_OSR}" = "buster" ] \
        || [ "${_OSR}" = "stretch" ] \
        || [ "${_OSR}" = "jessie" ] \
        || [ "${_DO_FIX}" = "YES" ] \
        || [ "${_OSR}" = "trusty" ] \
        || [ "${_OSR}" = "precise" ]; then
        _SSL_FIX_REQUIRED=YES
      else
        _SSL_FIX_REQUIRED=NO
      fi
    fi
    if [ ! -e "/usr/lib/libssl.so" ] \
      && [ "${_SSL_FIX_REQUIRED}" = "YES" ]; then
      msg "INFO: Fix #2 for libs in ${_THIS_OS} ${_OSR}"
      _X86_64_TEST=$(uname -m 2>&1)
      if [ "${_X86_64_TEST}" = "x86_64" ]; then
        if [ -e "/usr/lib/x86_64-linux-gnu/libssl.so" ] \
          && [ ! -e "/usr/lib/libssl.so" ]; then
          ln -s /usr/lib/x86_64-linux-gnu/libssl.so  \
            /usr/lib/libssl.so
        elif [ -e "/lib/x86_64-linux-gnu/libssl.so" ] \
          && [ ! -e "/usr/lib/libssl.so" ]; then
          ln -s /lib/x86_64-linux-gnu/libssl.so  \
            /usr/lib/libssl.so
        fi
        if [ -e "/usr/lib/x86_64-linux-gnu/libcrypto.so" ] \
          && [ ! -e "/usr/lib/libcrypto.so" ]; then
          ln -s /usr/lib/x86_64-linux-gnu/libcrypto.so \
            /usr/lib/libcrypto.so
        elif [ -e "/lib/x86_64-linux-gnu/libcrypto.so" ] \
          && [ ! -e "/usr/lib/libcrypto.so" ]; then
          ln -s /lib/x86_64-linux-gnu/libcrypto.so \
            /usr/lib/libcrypto.so
        fi
      else
        if [ -e "/usr/lib/i386-linux-gnu/libssl.so" ] \
          && [ ! -e "/usr/lib/libssl.so" ]; then
          ln -s /usr/lib/i386-linux-gnu/libssl.so  \
            /usr/lib/libssl.so
        elif [ -e "/lib/i386-linux-gnu/libssl.so" ] \
          && [ ! -e "/usr/lib/libssl.so" ]; then
          ln -s /lib/i386-linux-gnu/libssl.so  \
            /usr/lib/libssl.so
        fi
        if [ -e "/usr/lib/i386-linux-gnu/libcrypto.so" ] \
          && [ ! -e "/usr/lib/libcrypto.so" ]; then
          ln -s /usr/lib/i386-linux-gnu/libcrypto.so \
            /usr/lib/libcrypto.so
        elif [ -e "/lib/i386-linux-gnu/libcrypto.so" ] \
          && [ ! -e "/usr/lib/libcrypto.so" ]; then
          ln -s /lib/i386-linux-gnu/libcrypto.so \
            /usr/lib/libcrypto.so
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
    if ! netcat -w 10 -z smtp.gmail.com 25 ; then
      cat <<EOF

      Your outgoing SMTP port 25 doesn't work
      as expected, so your server can't send out
      any emails directly.

      Your SMTP relay host, if available, should be added as
        _SMTP_RELAY_HOST="smtp.your.relay.server"
      in the /root/.barracuda.cnf file.

      For now we will continue the installation anyway,
      but you will have to find the welcome email with all
      initial access credentials in the file located in:

        /data/disk/o1/log/setupmail.txt

EOF
    fi
    ###
    ### Required if outgoing smtp port is closed and smtp relay is in use
    ###
    if [ ! -z "${_SMTP_RELAY_HOST}" ]; then
      sed -i "s/${_SMTP_RELAY_HOST}//g" /etc/postfix/main.cf &> /dev/null
      wait
      sed -i "s/relayhost =/relayhost = ${_SMTP_RELAY_HOST}/g" \
        /etc/postfix/main.cf &> /dev/null
      wait
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
      rm -rf vnstat*
      get_dev_src "vnstat-${_VNSTAT_VRN}.tar.gz"
      cd vnstat-${_VNSTAT_VRN}
      mrun "bash ./configure --prefix=/usr --sysconfdir=/etc" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      mrun "ldconfig" 2> /dev/null
      for INF in `vnstat --iflist \
        | sed "s/Available interfaces//g; s/(1000 Mbit)//g; s/(100 Mbit)//g; s/ lo//g;" \
        | cut -d: -f2` ;do vnstat -i $INF &> /dev/null;done
      cp -af /var/opt/vnstat-${_VNSTAT_VRN}/examples/init.d/debian/vnstat \
        /etc/init.d/vnstat
      chmod 755 /etc/init.d/vnstat &> /dev/null
      mrun "update-rc.d vnstat defaults" &> /dev/null
      if [ -e "/usr/etc/vnstat.conf" ]; then
        sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /usr/etc/vnstat.conf
      fi
      if [ -e "/etc/vnstat.conf" ]; then
        sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /etc/vnstat.conf
      fi
      mrun "service vnstat start" &> /dev/null
      mrun "killall vnstatd" &> /dev/null
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
    rm -rf /var/lib/vnstat
  fi
  if [ -e "/usr/etc/vnstat.conf" ]; then
    sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /usr/etc/vnstat.conf
    mrun "service vnstat restart" &> /dev/null
  fi
}

install_myquick_src() {
  if [ "${_MYQUICK_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Building MyQuick ${_MYQUICK_VRN} from sources, please wait..."
    mrun "apt-get update -qq" &> /dev/null
    mrun "${_INSTALL} cmake" 2> /dev/null
    if [ "${_DB_SERVER}" = "Percona" ] || [ "${_DB_SERIES}" = "5.7" ]; then
      mrun "${_INSTALL} libperconaserverclient20-dev" 2> /dev/null
    else
      mrun "${_INSTALL} libmariadb-dev" 2> /dev/null
    fi
    cd /var/opt
    rm -rf mydumper*
    get_dev_src "mydumper-${_MYQUICK_VRN}.tar.gz"
    cd /var/opt/mydumper-${_MYQUICK_VRN}
    mrun "cmake -DWITH_SSL=OFF ." 2> /dev/null
    mrun "make --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    mrun "ldconfig" 2> /dev/null
  fi
}

check_install_myquick() {
  if [ ! -e "/etc/mysql/mariadb.conf.d" ]; then
    mkdir -p /etc/mysql/mariadb.conf.d/
  fi
  isMyQuick=$(which mydumper 2>&1)
  if [ ! -x "${isMyQuick}" ] \
    || [ -z "${isMyQuick}" ]; then
    install_myquick_src
  fi
  isMyQuick=$(which myloader 2>&1)
  if [ ! -x "${isMyQuick}" ] \
    || [ -z "${isMyQuick}" ]; then
    install_myquick_src
  fi
  _MYQUICK_UPGRADE_REQUIRED=NO
  _MYQUICK_ITD=$(mydumper -V 2>&1 \
    | tr -d "\n" \
    | tr -d "," \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  _DB_V=$(mysql -V 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f6 \
    | awk '{ print $1}' \
    | cut -d"-" -f1 \
    | awk '{ print $1}' \
    | sed "s/[\,']//g" 2>&1)
  _MD_V=$(mydumper --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f6 \
    | awk '{ print $1}' \
    | cut -d"-" -f1 \
    | awk '{ print $1}' \
    | sed "s/[\,']//g" 2>&1)
  if [ "${_DB_V}" != "${_MD_V}" ]; then
    _MYQUICK_INSTALL_REQUIRED=YES
    msg "INFO: Installed MyQuick ${_MYQUICK_ITD} for ${_MD_V} (${_DB_V}), rebuild required"
    install_myquick_src
  fi
  if [ ! -e "/usr/include/mysql" ] || [ ! -e "/usr/include/mysql" ]; then
    _MYQUICK_INSTALL_REQUIRED=YES
    msg "INFO: Installed MyQuick ${_MYQUICK_ITD} for ${_MD_V} (${_DB_V}), rebuild required"
    install_myquick_src
  fi
  if [ "${_MYQUICK_ITD}" != "${_MYQUICK_VRN}" ]; then
    _MYQUICK_INSTALL_REQUIRED=YES
    msg "INFO: Installed MyQuick version ${_MYQUICK_ITD}, upgrade required"
    install_myquick_src
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
    rm -rf ${pthLog}/init.d-pre*
    rm -rf ${vBs}/dragon/z/init.d-pre-*
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
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ ! -e "/etc/init.d/redis-server" ]; then
        _NGINX_DOS_LIMIT=888
      else
        if [ -z "${_NGINX_DOS_LIMIT}" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "199" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "299" ]; then
          _NGINX_DOS_LIMIT=399
        fi
      fi
    fi
    sed -i "s/^_NGINX_DOS_LIMIT=.*/_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}/g"  ${barCnf}
    sed -i "s/default_critnumber =.*/default_critnumber = ${_NGINX_DOS_LIMIT};/g" /var/xdrago/monitor/check/scan_nginx
    wait
    sed -i "s/default_lines =.*/default_lines = 599;/g" /var/xdrago/monitor/check/scan_nginx
    wait
    if [ ! -z "${_NGINX_DOS_KEYWORDS}" ]; then
      _NGINX_DOS_KEYWORDS=${_NGINX_DOS_KEYWORDS//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DOS_KEYWORDS}" ]; then
        msg "INFO: Configured _NGINX_DOS_KEYWORDS: ${_NGINX_DOS_KEYWORDS}"
        sed -i "s/foobar/${_NGINX_DOS_KEYWORDS}/g" \
          /var/xdrago/monitor/check/scan_nginx &> /dev/null
        wait
      fi
    fi
    if [ ! -z "${_NGINX_DONTCOUNT_KEYWORDS}" ]; then
      _NGINX_DONTCOUNT_KEYWORDS=${_NGINX_DONTCOUNT_KEYWORDS//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DONTCOUNT_KEYWORDS}" ]; then
        msg "INFO: Configured _NGINX_DONTCOUNT_KEYWORDS: ${_NGINX_DONTCOUNT_KEYWORDS}"
        sed -i "s/dontcount/${_NGINX_DONTCOUNT_KEYWORDS}/g" \
          /var/xdrago/monitor/check/scan_nginx &> /dev/null
        wait
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
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      sed -i "s/rotate 52/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
      wait
      sed -i "s/rotate 1/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
      wait
      sed -i "s/INTERVAL 1 HOUR/INTERVAL 15 MINUTE/g" \
        /var/xdrago/purge_binlogs.sh &> /dev/null
      wait
    fi
    if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
      _DO_NOTHING=YES
    else
      if [ -e "/root/.high_load.cnf" ] \
        && [ ! -e "/root/.big_db.cnf" ] \
        && [ ! -e "/root/.tg.cnf" ]; then
        sed -i "s/3600/300/g" /var/xdrago/minute.sh &> /dev/null
        wait
      elif [ -e "/root/.big_db.cnf" ] || [ -e "/root/.tg.cnf" ]; then
        _DO_NOTHING=YES
      else
        sed -i "s/3600/1800/g" /var/xdrago/minute.sh &> /dev/null
        wait
      fi
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
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ ! -e "/etc/init.d/redis-server" ]; then
        _NGINX_DOS_LIMIT=888
      else
        if [ -z "${_NGINX_DOS_LIMIT}" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "199" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "299" ]; then
          _NGINX_DOS_LIMIT=399
        fi
      fi
    fi
    sed -i "s/^_NGINX_DOS_LIMIT=.*/_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}/g"  ${barCnf}
    sed -i "s/default_critnumber =.*/default_critnumber = ${_NGINX_DOS_LIMIT};/g" /var/xdrago/monitor/check/scan_nginx
    wait
    sed -i "s/default_lines =.*/default_lines = 599;/g" /var/xdrago/monitor/check/scan_nginx
    wait
    if [ ! -z "${_NGINX_DOS_KEYWORDS}" ]; then
      _NGINX_DOS_KEYWORDS=${_NGINX_DOS_KEYWORDS//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DOS_KEYWORDS}" ]; then
        msg "INFO: Configured _NGINX_DOS_KEYWORDS: ${_NGINX_DOS_KEYWORDS}"
        sed -i "s/foobar/${_NGINX_DOS_KEYWORDS}/g" \
          /var/xdrago/monitor/check/scan_nginx &> /dev/null
        wait
      fi
    fi
    if [ ! -z "${_NGINX_DONTCOUNT_KEYWORDS}" ]; then
      _NGINX_DONTCOUNT_KEYWORDS=${_NGINX_DONTCOUNT_KEYWORDS//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DONTCOUNT_KEYWORDS}" ]; then
        msg "INFO: Configured _NGINX_DONTCOUNT_KEYWORDS: ${_NGINX_DONTCOUNT_KEYWORDS}"
        sed -i "s/dontcount/${_NGINX_DONTCOUNT_KEYWORDS}/g" \
          /var/xdrago/monitor/check/scan_nginx &> /dev/null
        wait
      fi
    fi
    mv -f /etc/cron.daily/mlocate ${vBs}/ &> /dev/null
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
        _DO_NOTHING=YES
      else
        if [ -e "/root/.high_load.cnf" ] \
          && [ ! -e "/root/.big_db.cnf" ] \
          && [ ! -e "/root/.tg.cnf" ]; then
          sed -i "s/3600/180/g" /var/xdrago/minute.sh &> /dev/null
          wait
        elif [ -e "/root/.big_db.cnf" ] || [ -e "/root/.tg.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/3600/1800/g" /var/xdrago/minute.sh &> /dev/null
          wait
        fi
        sed -i "s/rotate 52/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
        wait
        sed -i "s/rotate 1/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
        wait
      fi
    fi
  fi
  if [ -d "/var/xdrago-pre-${_X_VERSION}-${_NOW}" ]; then
    cp -af /var/xdrago-pre-${_X_VERSION}-${_NOW}/run-* /var/xdrago/ &> /dev/null
  fi
  sed -i "s/firewall/monitor/g" /var/xdrago/minute.sh &> /dev/null
  wait
  chmod -R 700 /var/xdrago/monitor/check &> /dev/null
  chmod 700 /var/xdrago/* &> /dev/null
  chmod 700 /var/xdrago &> /dev/null
}

check_fix_umask() {
  if [ ! -e "${pthLog}/umask_fixed_new.log" ]; then
    mkdir -p /var/www/nginx-default
    sed -i "s/^UMASK.*//g" /etc/default/login &> /dev/null
    wait
    echo "UMASK=002" >> /etc/default/login
    sed -i "/^$/d" /etc/default/login &> /dev/null
    wait
    sed -i "s/^UMASK.*/UMASK 002/g" /etc/login.defs &> /dev/null
    wait
    sed -i "s/^umask.*022/umask 002/g" /etc/profile &> /dev/null
    wait
    sed -i "s/^session optional pam_umask.*//g" /etc/pam.d/login &> /dev/null
    wait
    echo "session optional pam_umask.so umask=0002" >> /etc/pam.d/login
    sed -i "/^$/d" /etc/pam.d/login &> /dev/null
    wait
    echo "umask 002" >> /var/www/.profile
    chown www-data:www-data /var/www/.profile &> /dev/null
    chown www-data:www-data /var/www/nginx-default &> /dev/null
    touch ${pthLog}/umask_fixed_new.log
  fi
  if [ ! -e "${pthLog}/umask_fixed_shell_sftp.log" ]; then
    sed -e '/Subsystem\ssftp/s:server$:server -u 0002:' -i /etc/ssh/sshd_config
    echo "session optional pam_umask.so umask=0002" >> /etc/pam.d/sshd
    mrun "service ssh restart" &> /dev/null
    touch ${pthLog}/umask_fixed_shell_sftp.log
  fi
  if [ ! -e "${pthLog}/src_umask_fixed_shell_sftp.log" ] \
    && [ -e "/usr/etc/sshd_config" ]; then
    sed -e '/Subsystem\ssftp/s:server$:server -u 0002:' -i /usr/etc/sshd_config
    mrun "service ssh restart" &> /dev/null
    touch ${pthLog}/src_umask_fixed_shell_sftp.log
  fi
}

install_update_lshell() {
  _PATH_LSHELL="/usr/local/bin/lshell"
  if [ ! -e "${_PATH_LSHELL}" ] \
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
    rm -rf lshell*
    get_dev_src "lshell-${_LSHELL_VRN}.tar.gz"
    for Files in `find /var/opt/lshell-${_LSHELL_VRN} -type f`; do
      sed -i "s/kicked/logged/g" $Files &> /dev/null
      wait
      sed -i "s/Kicked/Logged/g" $Files &> /dev/null
      wait
    done
    cd /var/opt/lshell-${_LSHELL_VRN}
    rm -rf /usr/local/lib/python2.6/dist-packages/lshell*
    rm -rf /usr/local/lib/python2.7/dist-packages/lshell*
    mrun "python setup.py install --no-compile" 2> /dev/null
    if [ "${_STATUS}" = "UPGRADE" ]; then
      cp -af /etc/lshell.conf-bak-${_NOW} /etc/lshell.conf &> /dev/null
    else
      cp -af ${bldPth}/aegir/tools/system/conf/lshell.conf /etc/lshell.conf
      echo "${_PATH_LSHELL}" >> /etc/shells
    fi
    rm -f /etc/logrotate.d/lshell
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
      st_runner "openssl req -x509 -nodes -sha256 -days 7300 -newkey rsa:2048 \
        -keyout /etc/ssl/private/pure-ftpd.pem \
        -out /etc/ssl/private/pure-ftpd.pem -batch" 2> /dev/null
      chmod 600 /etc/ssl/private/pure-ftpd.pem &> /dev/null
      cd /var/opt
      rm -rf pure-ftpd*
      mkdir -p /usr/local/etc
      get_dev_src "pure-ftpd-${_PURE_FTPD_VRN}.tar.gz"
      cd pure-ftpd-${_PURE_FTPD_VRN}
      mrun "bash ./configure --with-everything --with-virtualchroot \
        --without-humor --with-tls --with-diraliases --with-pam \
        --with-certfile=/etc/ssl/private/pure-ftpd.pem" 2> /dev/null
      mrun "make install-strip" 2> /dev/null
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
  if [ -e "${_NEWRELIC_APP_CFG}" ]; then
    _NEWRELIC_KEY_TEST=$(grep "REPLACE_WITH_REAL_KEY" ${_NEWRELIC_APP_CFG} 2>&1)
    if [[ "${_NEWRELIC_KEY_TEST}" =~ "REPLACE_WITH_REAL_KEY" ]] \
      && [ ! -z "${_NEWRELIC_KEY}" ]; then
      sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
        ${_NEWRELIC_APP_CFG} &> /dev/null
      wait
    fi
    sed -i "s/^loglevel=.*/loglevel=error/g" ${_NEWRELIC_APP_CFG} &> /dev/null
    wait
    mrun "service newrelic-daemon restart" &> /dev/null
  else
    if [ -e "/etc/init.d/newrelic-daemon" ] \
      || [ -e "/etc/init.d/newrelic-sysmond" ]; then
      service newrelic-daemon stop &> /dev/null
      update-rc.d -f newrelic-daemon remove &> /dev/null
      service newrelic-sysmond stop &> /dev/null
      update-rc.d -f newrelic-sysmond remove &> /dev/null
      st_runner "${_RMAPP} newrelic-php5 \
        newrelic-php5-common \
        newrelic-daemon \
        newrelic-sysmond" &> /dev/null
      mv -f /etc/newrelic \
        ${vBs}/nr/etc-newrelic-pre-${_X_VERSION}-${_NOW} &> /dev/null
      rm -f /etc/init.d/newrelic-sysmond
      rm -f /etc/init.d/newrelic-daemon
      killall -9 newrelic-daemon &> /dev/null
      killall -9 nrsysmond &> /dev/null
    fi
  fi
  _NEWRELIC_SYS_CFG="/etc/newrelic/nrsysmond.cfg"
  if [ -e "${_NEWRELIC_SYS_CFG}" ]; then
    _NEWRELIC_KEY_TEST=$(grep "REPLACE_WITH_REAL_KEY" ${_NEWRELIC_SYS_CFG} 2>&1)
    if [[ "${_NEWRELIC_KEY_TEST}" =~ "REPLACE_WITH_REAL_KEY" ]] \
      && [ ! -z "${_NEWRELIC_KEY}" ]; then
      sed -i "s/REPLACE_WITH_REAL_KEY/${_NEWRELIC_KEY}/g" \
        ${_NEWRELIC_SYS_CFG} &> /dev/null
      wait
    fi
    sed -i "s/^loglevel=.*/loglevel=error/g" \
      ${_NEWRELIC_SYS_CFG} &> /dev/null
    wait
    sed -i "s/.*pidfile=.*/pidfile=\/var\/run\/nrsysmond.pid/g" \
      ${_NEWRELIC_SYS_CFG} &> /dev/null
    wait
    if [ -e "/root/.enable.newrelic.sysmond.cnf" ]; then
      mrun "service newrelic-sysmond restart" &> /dev/null
    else
      mrun "service newrelic-sysmond stop" &> /dev/null
    fi
  fi
}

check_fix_java() {
  if [ ! -e "/usr/lib/jvm/java-7-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-7-openjdk-amd64" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-amd64 /usr/lib/jvm/java-7-openjdk
  fi
  if [ ! -e "/usr/lib/jvm/java-7-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-7-openjdk-i386" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-i386 /usr/lib/jvm/java-7-openjdk
  fi
  if [ -e "/usr/lib/jvm/java-1.7.0-openjdk-i386" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -s /usr/lib/jvm/java-1.7.0-openjdk-i386 /usr/lib/jvm/default-java
  fi
  if [ ! -e "/usr/bin/java7" ] \
    && [ -e "/usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java /usr/bin/java7
  fi
  if [ ! -e "/usr/bin/java7" ] \
    && [ -e "/usr/lib/jvm/java-7-openjdk-i386/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk-i386/jre/bin/java /usr/bin/java7
  fi
  if [ -e "/usr/lib/jvm/java-1.7.0-openjdk-amd64" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sf /usr/lib/jvm/java-1.7.0-openjdk-amd64 /usr/lib/jvm/default-java
  fi
  if [ -x "/usr/lib/jvm/java-7-openjdk/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-7-openjdk/jre/bin/java /etc/alternatives/java
    ln -sf /etc/alternatives/java /usr/bin/java
  fi

  if [ ! -e "/usr/lib/jvm/java-8-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-8-openjdk-amd64" ]; then
    ln -sf /usr/lib/jvm/java-8-openjdk-amd64 /usr/lib/jvm/java-8-openjdk
  fi
  if [ ! -e "/usr/lib/jvm/java-8-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-8-openjdk-i386" ]; then
    ln -sf /usr/lib/jvm/java-8-openjdk-i386 /usr/lib/jvm/java-8-openjdk
  fi
  if [ -e "/usr/lib/jvm/java-1.8.0-openjdk-i386" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sf /usr/lib/jvm/java-1.8.0-openjdk-i386 /usr/lib/jvm/default-java
  fi
  if [ ! -e "/usr/bin/java8" ] \
    && [ -e "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java /usr/bin/java8
  fi
  if [ ! -e "/usr/bin/java8" ] \
    && [ -e "/usr/lib/jvm/java-8-openjdk-i386/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-8-openjdk-i386/jre/bin/java /usr/bin/java8
  fi
  if [ -e "/usr/lib/jvm/java-1.8.0-openjdk-amd64" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sf /usr/lib/jvm/java-1.8.0-openjdk-amd64 /usr/lib/jvm/default-java
  fi
  if [ -x "/usr/lib/jvm/java-8-openjdk/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-8-openjdk/jre/bin/java /etc/alternatives/java
    ln -sf /etc/alternatives/java /usr/bin/java
  fi

  if [ ! -e "/usr/lib/jvm/java-11-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
    ln -sf /usr/lib/jvm/java-11-openjdk-amd64 /usr/lib/jvm/java-11-openjdk
  fi
  if [ ! -e "/usr/lib/jvm/java-11-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-11-openjdk-i386" ]; then
    ln -sf /usr/lib/jvm/java-11-openjdk-i386 /usr/lib/jvm/java-11-openjdk
  fi
  if [ -e "/usr/lib/jvm/java-1.11.0-openjdk-i386" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sf /usr/lib/jvm/java-1.11.0-openjdk-i386 /usr/lib/jvm/default-java
  fi
  if [ ! -e "/usr/bin/java11" ] \
    && [ -e "/usr/lib/jvm/java-11-openjdk-amd64/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-11-openjdk-amd64/jre/bin/java /usr/bin/java11
  fi
  if [ ! -e "/usr/bin/java11" ] \
    && [ -e "/usr/lib/jvm/java-11-openjdk-i386/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-11-openjdk-i386/jre/bin/java /usr/bin/java11
  fi
  if [ -e "/usr/lib/jvm/java-1.11.0-openjdk-amd64" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sf /usr/lib/jvm/java-1.11.0-openjdk-amd64 /usr/lib/jvm/default-java
  fi
  if [ -x "/usr/lib/jvm/java-11-openjdk/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-11-openjdk/jre/bin/java /etc/alternatives/java
    ln -sf /etc/alternatives/java /usr/bin/java
  fi

  if [ ! -e "/usr/lib/jvm/java-17-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    ln -sf /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/java-17-openjdk
  fi
  if [ ! -e "/usr/lib/jvm/java-17-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-17-openjdk-i386" ]; then
    ln -sf /usr/lib/jvm/java-17-openjdk-i386 /usr/lib/jvm/java-17-openjdk
  fi
  if [ -e "/usr/lib/jvm/java-1.17.0-openjdk-i386" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sf /usr/lib/jvm/java-1.17.0-openjdk-i386 /usr/lib/jvm/default-java
  fi
  if [ ! -e "/usr/bin/java17" ] \
    && [ -e "/usr/lib/jvm/java-17-openjdk-amd64/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-17-openjdk-amd64/jre/bin/java /usr/bin/java17
  fi
  if [ ! -e "/usr/bin/java17" ] \
    && [ -e "/usr/lib/jvm/java-17-openjdk-i386/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-17-openjdk-i386/jre/bin/java /usr/bin/java17
  fi
  if [ -e "/usr/lib/jvm/java-1.17.0-openjdk-amd64" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sf /usr/lib/jvm/java-1.17.0-openjdk-amd64 /usr/lib/jvm/default-java
  fi
  if [ -x "/usr/lib/jvm/java-17-openjdk/jre/bin/java" ]; then
    ln -sf /usr/lib/jvm/java-17-openjdk/jre/bin/java /etc/alternatives/java
    ln -sf /etc/alternatives/java /usr/bin/java
  fi
}

sshd_armour() {
  ###
  ### See: https://stribika.github.io/2015/01/04/secure-secure-shell.html
  ### Also: https://github.com/stribika/stribika.github.io/wiki/Secure-Secure-Shell
  ###
  if [ -e "/usr/etc/sshd_config" ]; then
    if [ "${_SSH_ARMOUR}" = "NO" ] \
      || [ -z "${_SSH_ARMOUR}" ]; then
      if [ -e "/usr/etc/.vanilla.sshd_config" ]; then
        mv -f /usr/etc/.vanilla.sshd_config /usr/etc/sshd_config
      fi
      if [ -e "/usr/etc/.vanilla.ssh_config" ]; then
        mv -f /usr/etc/.vanilla.ssh_config /usr/etc/ssh_config
      fi
    else
      if [ ! -e "/usr/etc/.vanilla.sshd_config" ]; then
        cp -a /usr/etc/sshd_config /usr/etc/.vanilla.sshd_config
      fi
      if [ ! -e "/usr/etc/.vanilla.ssh_config" ]; then
        cp -a /usr/etc/ssh_config /usr/etc/.vanilla.ssh_config
      fi
      _SSH_PROTOCOL_TEST=$(grep "Protocol" /usr/etc/sshd_config 2>&1)
      if [[ "${_SSH_PROTOCOL_TEST}" =~ (^)"Protocol 2" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_PROTOCOL_TEST}" =~ "Protocol" ]]; then
        sed -i "s/.*Protocol.*/Protocol 2/g" /usr/etc/sshd_config &> /dev/null
        wait
      else
        echo >> /usr/etc/sshd_config
        echo "Protocol 2" >> /usr/etc/sshd_config
      fi
      _SSH_ALGO_TEST=$(grep "KexAlgorithms" /usr/etc/sshd_config 2>&1)
      if [[ "${_SSH_ALGO_TEST}" =~ (^)"KexAlgorithms curve25519-sha256" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_ALGO_TEST}" =~ "KexAlgorithms" ]]; then
        sed -i "s/.*KexAlgorithms.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        echo "KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /usr/etc/sshd_config
      else
        echo >> /usr/etc/sshd_config
        echo "KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /usr/etc/sshd_config
      fi
      _SSH_CIPHERS_TEST=$(grep "Ciphers" /usr/etc/sshd_config 2>&1)
      if [[ "${_SSH_CIPHERS_TEST}" =~ (^)"Ciphers chacha20-poly1305" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_CIPHERS_TEST}" =~ "Ciphers" ]]; then
        sed -i "s/.*Ciphers.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /usr/etc/sshd_config
      else
        echo >> /usr/etc/sshd_config
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /usr/etc/sshd_config
      fi
      _SSH_MACS_TEST=$(grep "MACs" /usr/etc/sshd_config 2>&1)
      if [[ "${_SSH_MACS_TEST}" =~ (^)"MACs hmac-sha2-512-etm" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_MACS_TEST}" =~ "MACs" ]]; then
        sed -i "s/.*MACs.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /usr/etc/sshd_config
      else
        echo >> /usr/etc/sshd_config
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /usr/etc/sshd_config
      fi
      _SSH_HKEY_TEST=$(grep "HostKey" /usr/etc/sshd_config 2>&1)
      if [[ "${_SSH_HKEY_TEST}" =~ (^)"HostKey" ]] \
        && [[ "${_SSH_HKEY_TEST}" =~ "ssh_host_ed25519_key" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_HKEY_TEST}" =~ "HostKey" ]]; then
        sed -i "s/.*HostKey.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        echo "HostKey /usr/etc/ssh_host_ed25519_key" >> /usr/etc/sshd_config
        echo "HostKey /usr/etc/ssh_host_rsa_key" >> /usr/etc/sshd_config
      else
        echo >> /usr/etc/sshd_config
        echo "HostKey /usr/etc/ssh_host_ed25519_key" >> /usr/etc/sshd_config
        echo "HostKey /usr/etc/ssh_host_rsa_key" >> /usr/etc/sshd_config
      fi
      if [ ! -e "/usr/etc/.ssh_host_ed25519_key.pid" ]; then
        mkdir -p /var/backups/sshd
        mv -f /usr/etc/ssh_host_*key* /var/backups/sshd/
        msg "INFO: Generating new ssh_host_ed25519_key..."
        ssh-keygen -t ed25519 -N "" -q -f /usr/etc/ssh_host_ed25519_key < /dev/null
        touch /usr/etc/.ssh_host_ed25519_key.pid
      fi
      if [ ! -e "/usr/etc/.ssh_host_rsa_key4096.pid" ]; then
        msg "INFO: Generating new ssh_host_rsa_key..."
        ssh-keygen -t rsa -b 4096 -N "" -q -f /usr/etc/ssh_host_rsa_key < /dev/null
        touch /usr/etc/.ssh_host_rsa_key4096.pid
        msg "NOTE: You will be asked to accept the new SSH fingerprint the next time you connect"
      fi
      if [ ! -e "/usr/etc/.moduli.pid" ]; then
        if [ -e "/usr/etc/moduli" ]; then
          mv -f /usr/etc/moduli /usr/etc/.old.moduli
          awk '$5 > 2000' /usr/etc/.old.moduli > /usr/etc/.tmp.moduli
          mv -f /usr/etc/.tmp.moduli /usr/etc/moduli
          touch /usr/etc/.moduli.pid
        else
          msg "INFO: Generating new SSH moduli, this may take 1-2 hours :/ please wait..."
          mrun "ssh-keygen -G /usr/etc/moduli.all -b 4096" &> /dev/null
          mrun "ssh-keygen -T /usr/etc/moduli.safe -f /usr/etc/moduli.all" &> /dev/null
          mv -f /usr/etc/moduli.safe /usr/etc/moduli
          rm -f /usr/etc/moduli.all
          touch /usr/etc/.moduli.pid
        fi
      fi
      _SSH_KEXALGO_TEST=$(grep "KexAlgorithms" /usr/etc/ssh_config 2>&1)
      if [[ "${_SSH_KEXALGO_TEST}" =~ "KexAlgorithms curve25519-sha256" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_KEXALGO_TEST}" =~ "KexAlgorithms" ]]; then
        sed -i "s/.*PubkeyAuthentication.*//g" /usr/etc/ssh_config &> /dev/null
        wait
        sed -i "s/.*UseRoaming.*//g" /usr/etc/ssh_config &> /dev/null
        wait
        sed -i "s/.*Ciphers.*//g" /usr/etc/ssh_config &> /dev/null
        wait
        sed -i "s/.*HostKeyAlgorithms.*//g" /usr/etc/ssh_config &> /dev/null
        wait
        sed -i "s/.*KexAlgorithms.*//g" /usr/etc/ssh_config &> /dev/null
        wait
        sed -i "s/.*MACs.*//g" /usr/etc/ssh_config &> /dev/null
        wait
        echo >> /usr/etc/ssh_config
        echo "Host *" >> /usr/etc/ssh_config
        echo "  PubkeyAuthentication yes" >> /usr/etc/ssh_config
        echo "  UseRoaming no" >> /usr/etc/ssh_config
        echo "  Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /usr/etc/ssh_config
        echo "  HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa" >> /usr/etc/ssh_config
        echo "  KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /usr/etc/ssh_config
        echo "  MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /usr/etc/ssh_config
      else
        echo >> /usr/etc/ssh_config
        echo "Host *" >> /usr/etc/ssh_config
        echo "  PubkeyAuthentication yes" >> /usr/etc/ssh_config
        echo "  UseRoaming no" >> /usr/etc/ssh_config
        echo "  Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /usr/etc/ssh_config
        echo "  HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa" >> /usr/etc/ssh_config
        echo "  KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /usr/etc/ssh_config
        echo "  MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /usr/etc/ssh_config
      fi
    fi
    sed -i "/^$/d" /usr/etc/sshd_config &> /dev/nul
    sed -i "/^$/d" /usr/etc/ssh_config &> /dev/null
    mrun "service ssh reload" &> /dev/null
  fi
}

update_initd() {
  _THIS_DB_PORT=3306
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Updating init scripts"
    cp -af ${locCnf}/clean-boa-env /etc/init.d/clean-boa-env
    chmod 755 /etc/init.d/clean-boa-env &> /dev/null
    mrun "update-rc.d clean-boa-env defaults" &> /dev/null
    _SSH_USEDNS_TEST=$(grep "UseDNS" /etc/ssh/sshd_config 2>&1)
    if [[ "${_SSH_USEDNS_TEST}" =~ (^)"UseDNS no" ]]; then
      _DO_NOTHING=YES
    elif [[ "${_SSH_USEDNS_TEST}" =~ "UseDNS" ]]; then
      sed -i "s/.*UseDNS.*/UseDNS no/g" /etc/ssh/sshd_config &> /dev/null
      wait
    else
      echo >> /etc/ssh/sshd_config
      echo "UseDNS no" >> /etc/ssh/sshd_config
    fi
    if [ -e "/usr/etc/sshd_config" ]; then
      _SSH_USEDNS_TEST=$(grep "UseDNS" /usr/etc/sshd_config 2>&1)
      if [[ "${_SSH_USEDNS_TEST}" =~ (^)"UseDNS no" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_USEDNS_TEST}" =~ "UseDNS" ]]; then
        sed -i "s/.*UseDNS.*/UseDNS no/g" /usr/etc/sshd_config &> /dev/null
        wait
      else
        echo >> /usr/etc/sshd_config
        echo "UseDNS no" >> /usr/etc/sshd_config
      fi
      _SSH_USEPAM_TEST=$(grep "UsePAM" /usr/etc/sshd_config 2>&1)
      if [[ "${_SSH_USEPAM_TEST}" =~ (^)"UsePAM no" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_USEPAM_TEST}" =~ "UsePAM" ]]; then
        sed -i "s/.*UsePAM.*/UsePAM no/g" /usr/etc/sshd_config &> /dev/null
        wait
      else
        echo >> /usr/etc/sshd_config
        echo "UsePAM no" >> /usr/etc/sshd_config
      fi
    fi
    mrun "service ssh reload" &> /dev/null
    tune_memory_limits
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      msg "INFO: Restarting Solr 7"
      mrun "service solr7 stop" &> /dev/null
      #kill -9 $(ps aux | grep '[j]ava-8-openjdk' | awk '{print $2}') &> /dev/null
      mrun "service solr7 start" &> /dev/null
    fi
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
      mrun "update-rc.d -f php5-fpm remove" &> /dev/null
      mrun "update-rc.d cron defaults" &> /dev/null
      _PHP_V="81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          mrun "update-rc.d php${e}-fpm defaults" &> /dev/null
          mrun "service php${e}-fpm start" &> /dev/null
        fi
      done
      mrun "update-rc.d nginx defaults" &> /dev/null
      mrun "service nginx start" &> /dev/null
    fi
  else
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io" ]] \
      || [[ "${_THISHOST}" =~ ".o8.io" ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      sed -i "s/.*UseDNS.*//g" /etc/ssh/sshd_config &> /dev/null
      wait
      sed -i "s/.*UsePAM.*//g" /etc/ssh/sshd_config &> /dev/null
      wait
      sed -i "s/^ClientAliveCountMax.*//g" /etc/ssh/sshd_config &> /dev/null
      wait
      sed -i "s/^ClientAliveInterval.*//g" /etc/ssh/sshd_config &> /dev/null
      wait
      sed -i "s/^IgnoreUserKnownHosts.*//g" /etc/ssh/sshd_config &> /dev/null
      wait
      sed -i "s/^PasswordAuthentication.*//g" /etc/ssh/sshd_config &> /dev/null
      wait
      sed -i "s/^PermitRootLogin.*/PermitRootLogin without-password/g" \
        /etc/ssh/sshd_config &> /dev/null
      wait
      echo >> /etc/ssh/sshd_config
      echo "IgnoreUserKnownHosts no" >> /etc/ssh/sshd_config
      if [ -e "/root/.ssh.auth.keys.only.cnf" ]; then
        echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
      else
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
      fi
      echo "UseDNS no" >> /etc/ssh/sshd_config
      echo "UsePAM no" >> /etc/ssh/sshd_config
      echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
      echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
      sed -i "/^$/d" /etc/ssh/sshd_config &> /dev/null
      wait
      if [ -e "/usr/etc/sshd_config" ]; then
        sed -i "s/.*UseDNS.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        sed -i "s/.*UsePAM.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        sed -i "s/^ClientAliveCountMax.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        sed -i "s/^ClientAliveInterval.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        sed -i "s/^IgnoreUserKnownHosts.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        sed -i "s/^PasswordAuthentication.*//g" /usr/etc/sshd_config &> /dev/null
        wait
        sed -i "s/^#PermitRootLogin.*/PermitRootLogin without-password/g" \
          /usr/etc/sshd_config &> /dev/null
        wait
        sed -i "s/^PermitRootLogin.*/PermitRootLogin without-password/g" \
          /usr/etc/sshd_config &> /dev/null
        wait
        echo >> /usr/etc/sshd_config
        echo "IgnoreUserKnownHosts no" >> /usr/etc/sshd_config
        if [ -e "/root/.ssh.auth.keys.only.cnf" ]; then
          echo "PasswordAuthentication no" >> /usr/etc/sshd_config
        else
          echo "PasswordAuthentication yes" >> /usr/etc/sshd_config
        fi
        echo "UseDNS no" >> /usr/etc/sshd_config
        echo "UsePAM no" >> /usr/etc/sshd_config
        echo "ClientAliveInterval 300" >> /usr/etc/sshd_config
        echo "ClientAliveCountMax 3" >> /usr/etc/sshd_config
        sed -i "/^$/d" /usr/etc/sshd_config &> /dev/null
        wait
      fi
      mrun "service ssh reload" &> /dev/null
    else
      _SSH_USEDNS_TEST=$(grep "^UseDNS no" /etc/ssh/sshd_config 2>&1)
      if [[ ! "${_SSH_USEDNS_TEST}" =~ "UseDNS no" ]]; then
        sed -i "s/.*UseDNS.*/UseDNS no/g" /etc/ssh/sshd_config &> /dev/null
        wait
      fi
      if [ -e "/usr/etc/sshd_config" ]; then
        _SSH_USEDNS_TEST=$(grep "^UseDNS no" /usr/etc/sshd_config 2>&1)
        if [[ ! "${_SSH_USEDNS_TEST}" =~ "UseDNS no" ]]; then
          sed -i "s/.*UseDNS.*/UseDNS no/g" /usr/etc/sshd_config &> /dev/null
          wait
        fi
      fi
      mrun "service ssh reload" &> /dev/null
    fi
    fix_on_upgrade
    tune_memory_limits
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      msg "INFO: Restarting Solr 7"
      mrun "service solr7 stop" &> /dev/null
      #kill -9 $(ps aux | grep '[j]ava-8-openjdk' | awk '{print $2}') &> /dev/null
      mrun "service solr7 start" &> /dev/null
    fi
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
    if [ ! -e "/var/run/aegir_upgrade.pid" ] \
      && [ ! -e "/root/.proxy.cnf" ]; then
      msg "INFO: Restarting Redis, PHP-FPM and Nginx..."
      mrun "service redis-server stop" &> /dev/null
      mrun "killall -9 redis-server" &> /dev/null
      rm -f /var/lib/redis/*
      mrun "service redis-server start" &> /dev/null
      sleep 3
      mrun "service redis-server restart" &> /dev/null
      mrun "update-rc.d -f php5-fpm remove" &> /dev/null
      mrun "service nginx stop" &> /dev/null
      _PHP_V="81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          mrun "update-rc.d php${e}-fpm defaults" &> /dev/null
          mrun "service php${e}-fpm stop" &> /dev/null
        fi
      done
      killall -9 php-fpm &> /dev/null
      killall -9 php-cgi &> /dev/null
      killall -9 pure-ftpd &> /dev/null
      _PHP_V="81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          mrun "service php${e}-fpm start" &> /dev/null
        fi
      done
      mrun "service nginx start" &> /dev/null
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib ${_DB_SERIES}." ]]; then
        msg "INFO: Running ${_DB_SERVER} system tables (2) upgrade..."
        rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
        if [ -x "/usr/bin/mariadb_upgrade" ]; then
          mrun "mariadb_upgrade --force" &> /dev/null
          mrun "mariadb_upgrade --force" &> /dev/null
        elif [ -x "/usr/bin/mysql_upgrade" ]; then
          mrun "mysql_upgrade --force" &> /dev/null
          mrun "mysql_upgrade --force" &> /dev/null
        fi
      fi
      myCnf="/etc/mysql/my.cnf"
      preCnf="${vBs}/dragon/t/my.cnf-pre-${_X_VERSION}-${_NOW}"
      if [ -f "${myCnf}" ]; then
        myCnfUpdate=NO
        if [ ! -f "${preCnf}" ]; then
          mkdir -p ${vBs}/dragon/t/
          cp -af ${myCnf} ${preCnf}
        fi
        diffMyTest=$(diff -w -B \
          -I innodb_buffer_pool_size \
          -I innodb_buffer_pool_instances \
          -I innodb_page_cleaners \
          -I tmp_table_size \
          -I max_heap_table_size \
          -I myisam_sort_buffer_size \
          -I key_buffer_size ${myCnf} ${preCnf} 2>&1)
        if [ -z "${diffMyTest}" ]; then
          myCnfUpdate=NO
          msg "INFO: ${_DB_SERVER} diff0 empty"
        else
          myCnfUpdate=YES
          # diffMyTest=$(echo -n ${diffMyTest} | fmt -su -w 2500 2>&1)
          msg "INFO: ${_DB_SERVER} diff1 ${diffMyTest}"
        fi
        if [[ "${diffMyTest}" =~ "innodb_buffer_pool_size" ]]; then
          myCnfUpdate=NO
          msg "INFO: ${_DB_SERVER} diff2 ${diffMyTest}"
        fi
        if [[ "${diffMyTest}" =~ "No such file or directory" ]]; then
          myCnfUpdate=NO
          msg "INFO: ${_DB_SERVER} diff3 ${diffMyTest}"
        fi
      fi
      if [ "${_UP_SQL}" = "YES" ]; then
        myVnTest=$(mysql -V 2>&1)
        if [[ "${myVnTest}" =~ "${_DBS_VRN}" ]]; then
          msg "INFO: ${_DB_SERVER} ${_DBS_VRN} already up to date"
          myCnfUpdate=YES
          msg "INFO: ${_DB_SERVER} restart after upgrade forced"
        fi
      fi
      if [ ! -e "/etc/mysql/mariadb.conf.d" ]; then
        mkdir -p /etc/mysql/mariadb.conf.d/
      fi
      myUptime=$(mysqladmin version | grep -i uptime 2>&1)
      myUptime=$(echo -n ${myUptime} | fmt -su -w 2500 2>&1)
      msg "INFO: ${_DB_SERVER} ${myUptime}"
      if [ "${myRstrd}" = "YES" ]; then
        myCnfUpdate=NO
        msg "INFO: ${_DB_SERVER} already restarted!"
      fi
      if [ "${myCnfUpdate}" = "YES" ]; then
        msg "INFO: Restarting ${_DB_SERVER} server..."
        mysql -u root -e "INSTALL SONAME 'ha_archive';" &> /dev/null
        mrun "bash /var/xdrago/move_sql.sh" &> /dev/null
        msg "INFO: ${_DB_SERVER} server restart completed"
      fi
      if [[ "${_DB_SERIES}" =~ "5.7" ]]; then
        _CHECK_EXISTS=$(mysql -u root -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'drandom_2test')" | grep "0" 2>&1)
        if [[ "${_CHECK_EXISTS}" =~ "0" ]]; then
          _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
          echo _CHECK_REPAIR 1 ${_CHECK_REPAIR}
          if [[ "${_CHECK_REPAIR}" =~ "corrupted" ]]; then
            # mysqlcheck -A --auto-repair
            mysql_upgrade --force
            mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;"
            mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;"
            mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;"
            mysql_upgrade --force
          fi
          _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
          echo _CHECK_REPAIR 2 ${_CHECK_REPAIR}
        fi
        mysql -u root -e "SET GLOBAL innodb_flush_log_at_trx_commit=2;" &> /dev/null
        mysql -u root -e "SET GLOBAL innodb_flush_log_at_timeout=5;" &> /dev/null
        mysql -u root -e "SET GLOBAL show_compatibility_56=ON;" &> /dev/null
        mysql -u root -e "SET GLOBAL innodb_stats_on_metadata=0;" &> /dev/null
        rm -f /etc/mysql/conf.d/mysqldump.cnf
      fi
    fi
  fi
}

update_sysctl() {
  if [ ! -e "/root/.no.sysctl.update.cnf" ] \
    && [ ! -e "${pthLog}/sysctl.conf-${_X_VERSION}-${_NOW}.log" ]; then
    cp -af /etc/sysctl.conf \
      ${vBs}/dragon/t/sysctl.conf-pre-${_X_VERSION}-${_NOW} &> /dev/null
    if [ -e "${locCnf}/sysctl.conf" ]; then
      cp -af ${locCnf}/sysctl.conf /etc/sysctl.conf
    fi
    if [ -e "/etc/security/limits.conf" ]; then
      _IF_NF=$(grep '524288' /etc/security/limits.conf 2>&1)
      if [ -z "${_IF_NF}" ]; then
        echo "*         hard    nofile      524288"  >> /etc/security/limits.conf
        echo "*         soft    nofile      524288"  >> /etc/security/limits.conf
        echo "root      hard    nofile      1048576" >> /etc/security/limits.conf
        echo "root      soft    nofile      1048576" >> /etc/security/limits.conf
      fi
    fi
    if [ -e "/boot/grub/grub.cfg" ] || [ -e "/boot/grub/menu.lst" ]; then
      #echo never > /sys/kernel/mm/transparent_hugepage/enabled
      if [ -e "/etc/sysctl.conf" ]; then
        sysctl -p /etc/sysctl.conf &> /dev/null
      fi
    else
      if [ -e "/etc/sysctl.conf" ]; then
        sysctl -p /etc/sysctl.conf &> /dev/null
      fi
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
    /var/xdrago/usage.sh
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/monitor/check/segfault_alert
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/monitor/check/escapecheck
  if [ -e "/usr/sbin/apticron" ]; then
    if [ -e "/etc/apticron/apticron.conf" ]; then
      _APTICRON_TEST=$(grep "NOTIFY_HOLDS" /etc/apticron/apticron.conf 2>&1)
      if [[ "${_APTICRON_TEST}" =~ "NOTIFY_HOLDS" ]]; then
        sed -i "s/^# NOTIFY_HOLDS=\"0\"/NOTIFY_HOLDS=\"0\"/g" \
          /etc/apticron/apticron.conf
        wait
        sed -i "s/notify\@omega8.cc/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        wait
        sed -i "s/root/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        wait
        sed -i "s/^# be something like.*/# be something like ${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        wait
      else
        mrun "apt-get remove apticron -y -qq" &> /dev/null
        mrun "apt-get purge apticron -y -qq"  &> /dev/null
        mrun "apt-get install apticron -y"    &> /dev/null
        sed -i "s/^# NOTIFY_HOLDS=\"0\"/NOTIFY_HOLDS=\"0\"/g" \
          /etc/apticron/apticron.conf
        wait
        sed -i "s/notify\@omega8.cc/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        wait
        sed -i "s/root/${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        wait
        sed -i "s/^# be something like.*/# be something like ${_MY_EMAIL}/g" \
          /etc/apticron/apticron.conf
        wait
      fi
    fi
    if [[ "${_X_VERSION}" =~ "rel" ]] && [ "${_AEGIR_VERSION}" = "HEAD" ]; then
      sed -i "s/aptitude full-upgrade/barracuda up-head system/g" \
        /usr/sbin/apticron
      wait
      sed -i "s/apt-get dist-upgrade/barracuda up-head system/g" \
        /usr/sbin/apticron
      wait
      sed -i "s/barracuda up-head.*/barracuda up-head system/g" \
        /usr/sbin/apticron
      wait
    else
      sed -i "s/aptitude full-upgrade/barracuda up-head system/g" \
        /usr/sbin/apticron
      wait
      sed -i "s/apt-get dist-upgrade/barracuda up-head system/g" \
        /usr/sbin/apticron
      wait
      sed -i "s/barracuda up-stable.*/barracuda up-head system/g" \
        /usr/sbin/apticron
      wait
    fi
  fi
}

complete() {
  fix_lfd_whitelist
  fix_lfd_uidignore
  fix_cnf_postfix
  re_set_default_php_cli
  install_update_composer
  if [ "${_STATUS}" = "INIT" ]; then
    _STRICT_BIN_PERMISSIONS=NO
  fi
  if [ "${_STRICT_BIN_PERMISSIONS}" = "YES" ]; then
    usermod -aG users aegir
    usermod -aG users man
    usermod -aG users mysql
    if [ "${_OSR}" = "chimaera" ] \
      || [ "${_OSR}" = "beowulf" ] \
      || [ "${_OSR}" = "bullseye" ] \
      || [ "${_OSR}" = "buster" ] \
      || [ "${_OSR}" = "stretch" ]; then
      usermod -aG users _apt
    fi
    if [ -x "/bin/bash" ]; then
      switch_to_bash
    elif [ -x "/bin/dash" ]; then
      switch_to_dash
    fi
    strict_bin_permissions
    rm -f /etc/apt/apt.conf.d/00sandboxtmp
    rm -f /etc/apt/apt.conf.d/00temp
  fi
  finale
}
