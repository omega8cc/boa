
tRee=dev
export tRee="${tRee}"

#
# Re-install curl if broken.
if_reinstall_curl_src() {
  _CURL_VRN=8.8.0
  isCurl=$(curl --version 2>&1)
  if [[ ! "${isCurl}" =~ "OpenSSL" ]] || [ -z "${isCurl}" ]; then
    msg "OOPS: cURL is broken! Re-installing.."
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    echo "curl install" | dpkg --set-selections &> /dev/null
    apt_clean_update
    mrun "apt-get remove curl ${aptYesUnth}" 2> /dev/null
    mkdir -p /var/opt
    rm -rf /var/opt/curl*
    cd /var/opt
    wget -q -U iCab http://files.aegir.cc/dev/src/curl-${_CURL_VRN}.tar.gz &> /dev/null
    tar -xzf curl-${_CURL_VRN}.tar.gz &> /dev/null
    cd /var/opt/curl-${_CURL_VRN}
    sh ./configure --with-ssl --prefix=/usr/local &> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    if [ -f "/usr/local/bin/curl" ]; then
      isCurl=$(/usr/local/bin/curl --version 2>&1)
      if [[ ! "${isCurl}" =~ "OpenSSL" ]] || [ -z "${isCurl}" ]; then
        msg "ERRR: /usr/local/bin/curl is broken, moving to /usr/local/bin/curl--broken"
        rm -f /usr/local/bin/curl--broken
        mv -f /usr/local/bin/curl /usr/local/bin/curl--broken
      else
        msg "GOOD: /usr/local/bin/curl works"
      fi
    fi
  fi
}

#
# Install sysvinit with apt.
sysvinit_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sysvinit_install"
  fi
  apt_clean_update
  echo "sysvinit-core install" | dpkg --set-selections &> /dev/null
  echo "sysvinit-utils install" | dpkg --set-selections &> /dev/null
  mrun "${_INITINS} sysvinit-core" 2> /dev/null
  mrun "${_INITINS} sysvinit-utils" 2> /dev/null
  echo "sysvinit-core hold" | dpkg --set-selections &> /dev/null
  echo "sysvinit-utils hold" | dpkg --set-selections &> /dev/null
}

#
# Remove systemd with apt.
systemd_remove_apt_cmd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: systemd_remove_apt_cmd"
  fi
  apt_clean_update
  mrun "apt-get remove systemd -y --purge --auto-remove --allow-remove-essential -qq" 2> /dev/null
  mrun "apt-get remove libnss-systemd -y --purge --auto-remove --allow-remove-essential -qq" 2> /dev/null
  mrun "apt-get remove systemd-sysv -y --purge --auto-remove --allow-remove-essential -qq" 2> /dev/null
  mrun "apt-get autoremove --purge -y --purge --auto-remove -qq" 2> /dev/null
  mrun "apt-get autoclean -y --purge --auto-remove -qq" 2> /dev/null
  mrun "apt-get autoremove -y --purge --auto-remove -qq" 2> /dev/null
  apt_clean_update
}

#
# Detect and prepare for major OS upgrade.
define_loc_osr() {
  apt_clean_update_no_releaseinfo_change
  mrun "apt-get upgrade ${nrmUpArg}" 2> /dev/null
  mrun "apt-get install lsb-release ${nrmUpArg}" 2> /dev/null
  _OS_DIST=$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: define_loc_osr"
  fi
  _LOC_OS_CODE=
  _NEW_OS_CODE=
  _TGT_OSN=
  _MSG_LOC=
  if [ "${_JESSIE_TO_BEOWULF}" = "YES" ] \
    && [ "${_OS_CODE}" = "jessie" ]; then
    _LOC_OS_CODE=jessie
    _NEW_OS_CODE=beowulf
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Jessie to Devuan Beowulf"
  fi
  if [ "${_STRETCH_TO_BEOWULF}" = "YES" ] \
    && [ "${_OS_CODE}" = "stretch" ]; then
    _LOC_OS_CODE=stretch
    _NEW_OS_CODE=beowulf
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Stretch to Devuan Beowulf"
  fi
  if [ "${_BUSTER_TO_BEOWULF}" = "YES" ] \
    && [ "${_OS_CODE}" = "buster" ]; then
    _LOC_OS_CODE=buster
    _NEW_OS_CODE=beowulf
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Buster to Devuan Beowulf"
  fi
  if [ "${_BEOWULF_TO_CHIMAERA}" = "YES" ] \
    && [ "${_OS_CODE}" = "beowulf" ]; then
    _LOC_OS_CODE=beowulf
    _NEW_OS_CODE=chimaera
    _TGT_OSN=Devuan
    _MSG_LOC="Devuan Beowulf to Devuan Chimaera"
  fi
  if [ "${_CHIMAERA_TO_DAEDALUS}" = "YES" ] \
    && [ "${_OS_CODE}" = "chimaera" ]; then
    _LOC_OS_CODE=chimaera
    _NEW_OS_CODE=daedalus
    _TGT_OSN=Devuan
    _MSG_LOC="Devuan Chimaera to Devuan Daedalus"
  fi
  if [ "${_BULLSEYE_TO_CHIMAERA}" = "YES" ] \
    && [ "${_OS_CODE}" = "bullseye" ]; then
    _LOC_OS_CODE=bullseye
    _NEW_OS_CODE=chimaera
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Bullseye to Devuan Chimaera"
  fi
  if [ "${_BOOKWORM_TO_DAEDALUS}" = "YES" ] \
    && [ "${_OS_CODE}" = "bookworm" ]; then
    _LOC_OS_CODE=bookworm
    _NEW_OS_CODE=daedalus
    _TGT_OSN=Devuan
    _MSG_LOC="Debian Bookworm to Devuan Daedalus"
  fi
  if [ "${_BULLSEYE_TO_BOOKWORM}" = "YES" ] \
    && [ "${_OS_CODE}" = "bullseye" ]; then
    _LOC_OS_CODE=bullseye
    _NEW_OS_CODE=bookworm
    _TGT_OSN=Debian
    _MSG_LOC="Debian Bullseye to Debian Bookworm"
  fi
  if [ "${_BUSTER_TO_BULLSEYE}" = "YES" ] \
    && [ "${_OS_CODE}" = "buster" ]; then
    _LOC_OS_CODE=buster
    _NEW_OS_CODE=bullseye
    _TGT_OSN=Debian
    _MSG_LOC="Debian Buster to Debian Bullseye"
  fi
  if [ "${_STRETCH_TO_BUSTER}" = "YES" ] \
    && [ "${_OS_CODE}" = "stretch" ]; then
    _LOC_OS_CODE=stretch
    _NEW_OS_CODE=buster
    _TGT_OSN=Debian
    _MSG_LOC="Debian Stretch to Debian Buster"
  fi
  if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
    && [ "${_OS_CODE}" = "jessie" ]; then
    _LOC_OS_CODE=jessie
    _NEW_OS_CODE=stretch
    _TGT_OSN=Debian
    _MSG_LOC="Debian Jessie to Debian Stretch"
  fi
}

#
# Detect and prepare for major OS upgrade.
if_to_do_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_to_do_fix"
  fi
  _DO_FIX=
  if [ "${_JESSIE_TO_BEOWULF}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "jessie" ]; then
    _DO_FIX=YES
  fi
  if [ "${_STRETCH_TO_BEOWULF}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "stretch" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BUSTER_TO_BEOWULF}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "buster" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BEOWULF_TO_CHIMAERA}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "beowulf" ]; then
    _DO_FIX=YES
  fi
  if [ "${_CHIMAERA_TO_DAEDALUS}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "chimaera" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BULLSEYE_TO_CHIMAERA}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "bullseye" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BOOKWORM_TO_DAEDALUS}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "bookworm" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BULLSEYE_TO_BOOKWORM}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "bullseye" ]; then
    _DO_FIX=YES
  fi
  if [ "${_BUSTER_TO_BULLSEYE}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "buster" ]; then
    _DO_FIX=YES
  fi
  if [ "${_STRETCH_TO_BUSTER}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "stretch" ]; then
    _DO_FIX=YES
  fi
  if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
    && [ "${_LOC_OS_CODE}" = "jessie" ]; then
    _DO_FIX=YES
  fi
}

#
# Check system CPU power.
count_cpu() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: count_cpu"
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
# Make sure that we are root.
if_running_as_root_barracuda() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_running_as_root_barracuda"
  fi
  if [ `whoami` = "root" ]; then
    chmod a+w /dev/null
    rm -rf /tmp/drush_make_tmp*
    rm -rf /tmp/make_tmp*
    rm -f /tmp/pm-updatecode*
    rm -f /tmp/cache.inc*
    touch /run/boa_run.pid
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
      touch /run/cloud_vhost.pid
      if [ ! -e "/etc/apt/preferences.d/fuse" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: fuse\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/fuse
        apt_clean_update
      fi
      if [ ! -e "/etc/apt/preferences.d/udev" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: udev\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/udev
        apt_clean_update
      fi
      if [ ! -e "/etc/apt/preferences.d/makedev" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: makedev\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/makedev
        apt_clean_update
      fi
      mrun "apt-get remove fuse -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove udev -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove makedev -y --purge --auto-remove -qq" 2> /dev/null
      if [ -e "/sbin/hdparm" ]; then
        mrun "apt-get remove hdparm -y --purge --auto-remove -qq" 2> /dev/null
      fi
      if [ -d "/etc/webmin" ]; then
        mrun "dpkg --configure --force-all -a" 2> /dev/null
        apt_clean_update
        mrun "apt-get remove webmin -y --purge --auto-remove -qq" 2> /dev/null
        rm -rf /usr/share/webmin
      fi
      rm -f /etc/apt/sources.list.d/ksplice.list
      rm -f /etc/apt/sources.list.d/longview.list
      rm -f /etc/apt/sources.list.d/webmin.list
    fi
    sleep 1
  else
    msg "ERROR: This script should be ran as a root user"
    clean_pid_exit if_running_as_root_barracuda_a
  fi
}

#
# Set xterm.
set_xterm() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: set_xterm"
  fi
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: kill_nash"
  fi
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_postfix"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    mrun "apt-get remove exim4 -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove exim4-base -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove exim4-config -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove sendmail -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove sendmail-base -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove sendmail-bin -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove sendmail-cf -y --purge --auto-remove -qq" 2> /dev/null
    rm -f /etc/aliases
    rm -rf /etc/mail
    killall -9 sendmail &> /dev/null
  else
    _POSTFIX_TEST=$(grep "fatal: open lock file" /var/log/mail.log 2>&1)
    if [[ "${_POSTFIX_TEST}" =~ "fatal: open lock file" ]]; then
      mrun "dpkg --configure --force-all -a" 2> /dev/null
      apt_clean_update
      mrun "apt-get remove postfix -y -qq" 2> /dev/null
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_ftps_pam"
  fi
  if [ ! -e "/etc/ftpusers" ]; then
    cp -af ${locCnf}/ftpd/ftpusers /etc/ftpusers
  fi
  sed -i "s/pam_stack.so/pam_unix.so/g" /etc/pam.d/pure-ftpd &> /dev/null
  wait
  sed -i "s/ service=system-auth//g"    /etc/pam.d/pure-ftpd &> /dev/null
  wait
}

#
# Fix FTPS and SFTP access on modern systems.
sftp_ftps_modern_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sftp_ftps_modern_fix"
  fi
  _LSHELL_PATH_TEST=$(grep "/usr/bin/lshell" /etc/shells 2>&1)
  if [[ ! "${_LSHELL_PATH_TEST}" =~ "/usr/bin/lshell" ]]; then
    echo "/usr/bin/lshell" >> /etc/shells
  fi
  if [ ! -e "${pthLog}/mss-build-${_MSS_VRN}-${_X_SE}-${_X_VERSION}.log" ] \
    || [ ! -e "/etc/ssh/sftp_config" ] \
    || [ ! -e "/usr/bin/mysecureshell" ] \
    || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    if [ "${_MSS_BUILD}" != "YES" ]; then
      msg "INFO: Installing MySecureShell ${_MSS_VRN}..."
      cd /var/opt
      rm -rf mysecureshell*
      get_dev_src "mysecureshell-${_MSS_VRN}.tar.gz"
      cd /var/opt/mysecureshell
      mrun "bash ./configure" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      st_runner "sh ./install.sh yesall" 2> /dev/null
      touch ${pthLog}/mss-build-${_MSS_VRN}-${_X_SE}-${_X_VERSION}.log
      cp -af ${locCnf}/var/sftp_config /etc/ssh/sftp_config
      mrun "service ssh restart" 2> /dev/null
      _MSS_BUILD=YES
    fi
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
    mrun "service ssh reload" 2> /dev/null
    touch ${pthLog}/fixed-sftp-idle.log
  fi
}

#
# Disable Old Purge Cruft Machine.
disable_old_purge_cruft_machine() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: disable_old_purge_cruft_machine"
  fi
  if [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
    || [ -e "/root/.host8.cnf" ]; then
    sed -i "s/.*purge_cruft.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "/^$/d" /etc/crontab &> /dev/null
    wait
  fi
}

#
# Update BOA INI templates.
boa_ini_tpl_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: boa_ini_tpl_update"
  fi
  mkdir -p /data/conf
  if [ -e "${locCnf}/ini/default.boa_platform_control.ini" ]; then
    cp -af ${locCnf}/ini/default.boa_platform_control.ini /data/conf/default.boa_platform_control.ini
    rm -f /var/xdrago/conf/default.boa_platform_control.ini
  fi
  if [ -e "${locCnf}/ini/default.boa_site_control.ini" ]; then
    cp -af ${locCnf}/ini/default.boa_site_control.ini /data/conf/default.boa_site_control.ini
    rm -f /var/xdrago/conf/default.boa_site_control.ini
  fi
}

#
# Update global.inc Config.
global_inc_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: global_inc_conf_update"
  fi
  _GL_D=/data/conf/global
  [ ! -d "${_GL_D}" ] && mkdir -p ${_GL_D}
  _DR_V="11 10 9 8 7 6"
  for e in ${_DR_V}; do
    if [ -e "${_GL_D}/global-${e}.inc" ]; then
      cp -af ${_GL_D}/global-${e}.inc ${_GL_D}/global-${e}.inc-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${locCnf}/global/global-${e}.inc ${_GL_D}/global-${e}.inc
    fi
  done
  cp -af /data/conf/global.inc /data/conf/global.inc-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
  cp -af ${locCnf}/global/global.inc /data/conf/global.inc
  if [ ! -z "${_SPEED_VALID_MAX}" ]; then
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" /data/conf/global.inc &> /dev/null
    wait
  fi
  cp -af ${locCnf}/global/global-main.inc ${_GL_D}/global-main.inc
  cp -af ${locCnf}/global/global-ini.inc ${_GL_D}/global-ini.inc
  cp -af ${locCnf}/global/global-mode.inc ${_GL_D}/global-mode.inc
  cp -af ${locCnf}/global/global-settings.inc ${_GL_D}/global-settings.inc
  cp -af ${locCnf}/global/global-front-end.inc ${_GL_D}/global-front-end.inc
  if [ ! -z "${_SPEED_VALID_MAX}" ]; then
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" ${_GL_D}/global-front-end.inc &> /dev/null
  fi
  cp -af ${locCnf}/global/global-if-redis.inc ${_GL_D}/global-if-redis.inc
  cp -af ${locCnf}/global/global-redis.inc ${_GL_D}/global-redis.inc
  cp -af ${locCnf}/global/global-newrelic.inc ${_GL_D}/global-newrelic.inc
  cp -af ${locCnf}/global/global-extra.inc ${_GL_D}/global-extra.inc
}

#
# Fix this on upgrade.
fix_on_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_on_upgrade"
  fi
  sed -i "s/loglevel.*/loglevel warning/g" /etc/redis/redis.conf &> /dev/null
  sed -i "s/^TLS.*/TLS 2/g" /usr/local/etc/pure-ftpd.conf &> /dev/null
  cp -af ${locCnf}/var/clean-boa-env /etc/init.d/clean-boa-env
  chmod 755 /etc/init.d/clean-boa-env &> /dev/null
  mrun "update-rc.d clean-boa-env defaults" 2> /dev/null
  kill_nash
  sftp_ftps_modern_fix
  fix_ftps_pam
  disable_old_purge_cruft_machine
  php_config_check_update
  nginx_conf_update
  global_inc_conf_update
  redis_password_update
}

#
# Tune memory limits for PHP, Nginx and Percona.
tune_memory_limits() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: tune_memory_limits"
  fi
  count_cpu
  _VM_TEST=$(uname -a 2>&1)
  if [ -e "/proc/bean_counters" ]; then
    _VMFAMILY="VZ"
  elif [ -e "/root/.tg.cnf" ]; then
    _VMFAMILY="TG"
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
  PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  if [[ "${PrTestPower}" =~ "POWER" ]] \
    || [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
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
    || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
    || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
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
    _USE_CLI=2048
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
      _USE_PHP=2048
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
        _USE_PHP=2048
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
        sed -i "s/64000/128000/g"  /opt/php83/etc/php83.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php82/etc/php82.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php81/etc/php81.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php80/etc/php80.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php74/etc/php74.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php73/etc/php73.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php72/etc/php72.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php71/etc/php71.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php70/etc/php70.ini &> /dev/null
        sed -i "s/64000/128000/g"  /opt/php56/etc/php56.ini &> /dev/null
      else
        _USE_PHP=2048
        _USE_OPC=2048
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
  if [ "${_USE_PHP}" -lt "1024" ]; then
    _USE_PHP=1024
  fi
  _USE_FPM=$(( _USE_PHP / 2 ))
  if [ "${_USE_FPM}" -lt "1024" ]; then
    _USE_FPM=1024
  fi
  if [ ! -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
    mkdir -p /var/xdrago/conf
  fi
  if [ ! -e "/data/conf" ]; then
    mkdir -p /data/conf
  fi
  cp -af ${locCnf}/php/fpm-pool-foo-multi.conf /var/xdrago/conf/
  cp -af ${locCnf}/php/fpm-pool-foo.conf /var/xdrago/conf/
  cp -af ${locCnf}/hhvm /var/xdrago/conf/
  cp -af ${locCnf}/hhvm/hhvm_intercept.php /data/conf/hhvm_intercept.php
  chmod 644 /data/conf/hhvm_intercept.php
  if [ -e "/opt/etc/fpm/fpm-pool-common.conf" ]; then
    sed -i "s/395/${_USE_FPM}/g" /opt/etc/fpm/fpm-pool-common.conf &> /dev/null
  fi
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
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
    sql_conf_update
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
# Find server city.
find_server_city() {
  if [ -e "/root/.found_correct_city.cnf" ]; then
    _LOC_CITY=$(cat /root/.found_correct_city.cnf 2>&1)
    _LOC_CITY=$(echo -n ${_LOC_CITY} | tr -d "\n" 2>&1)
  else
    if [ -e "/root/.found_correct_ipv4.cnf" ]; then
      _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>&1)
      _LOC_CITY=$(curl ${crlGet} ipinfo.io/${_LOC_IP}/city 2>&1)
      _LOC_CITY=$(echo -n ${_LOC_CITY} | tr -d "\n" 2>&1)
    fi
    if [ ! -z "${_LOC_CITY}" ]; then
      _LOC_CITY=$(echo "${_LOC_CITY}" | tr ' ' '+' 2>&1)
      echo ${_LOC_CITY} > /root/.found_correct_city.cnf
    fi
  fi
}

#
# Fix locales.
locales_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: locales_check_fix"
  fi
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
    msg "NOTE!"
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
    if [ "${_OS_DIST}" = "Debian" ] || [ "${_OS_DIST}" = "Devuan" ]; then
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
    if [ -e "${locCnf}/var/boa.bashrc.txt" ]; then
      cp -af /root/.bashrc /root/.bashrc.bak.${_NOW}
      cp -af ${locCnf}/var/boa.bashrc.txt /root/.bashrc
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
    _PIPX_TEST=$(grep "PIPX" /root/.bashrc 2>&1)
    if [[ ! "${_PIPX_TEST}" =~ "PIPX" ]]; then
      echo "export PIPX_BIN_DIR=/usr/local/bin" >> /root/.bashrc
      echo "export PIPX_HOME=/opt/pipx/venvs" >> /root/.bashrc
      printf "\n" >> /root/.bashrc
    fi
  else
    if [ -e "${locCnf}/var/boa.bashrc.txt" ]; then
      cp -af /root/.bashrc /root/.bashrc.bak.${_NOW}
      cp -af ${locCnf}/var/boa.bashrc.txt /root/.bashrc
      set_xterm
    fi
    if [ "${_OS_DIST}" = "Debian" ] || [ "${_OS_DIST}" = "Devuan" ]; then
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
  _PIPX_TEST=$(grep "PIPX" /root/.bashrc 2>&1)
  if [[ ! "${_PIPX_TEST}" =~ "PIPX" ]]; then
    echo "export PIPX_BIN_DIR=/usr/local/bin" >> /root/.bashrc
    echo "export PIPX_HOME=/opt/pipx/venvs" >> /root/.bashrc
    printf "\n" >> /root/.bashrc
  fi
  if [ -e "/root/.dont.use.fancy.bash.login.cnf" ]; then
    _FANCY_TEST=$(grep "fancynow" /root/.bashrc 2>&1)
    if [[ "${_FANCY_TEST}" =~ "fancynow" ]]; then
      sed -i "s/.*fancynow.*/  \/bin\/true/g" /root/.bashrc &> /dev/null
      wait
      sed -i "s/.*screenfetch.*/  \/bin\/true/g" /root/.bashrc &> /dev/null
      wait
    fi
  else
    if [ -e "/usr/bin/screenfetch" ]; then
      _FANCY_TEST=$(grep "fancynow" /root/.bashrc 2>&1)
      if [[ ! "${_FANCY_TEST}" =~ "fancynow" ]]; then
        echo "if [ ! -z "\$PS1" ]; then" >> /root/.bashrc
        echo "  /opt/local/bin/fancynow" >> /root/.bashrc
        echo "  /usr/bin/screenfetch" >> /root/.bashrc
        echo "fi" >> /root/.bashrc
        printf "\n" >> /root/.bashrc
      fi
    fi
  fi
}

#
# Cleanup for Barracuda cnf file.
barracuda_cnf_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: barracuda_cnf_cleanup"
  fi
  ###
  ### legacy config cleanup start
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
  ### legacy config cleanup end
  ###

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
  _BOOKWORM_TO_DAEDALUS_TEST=$(grep _BOOKWORM_TO_DAEDALUS ${barCnf} 2>&1)
  if [[ "${_BOOKWORM_TO_DAEDALUS_TEST}" =~ "_BOOKWORM_TO_DAEDALUS" ]]; then
    sed -i "s/^_BOOKWORM_TO_DAEDALUS.*//g" ${barCnf}
    wait
  fi
  _CHIMAERA_TO_DAEDALUS_TEST=$(grep _CHIMAERA_TO_DAEDALUS ${barCnf} 2>&1)
  if [[ "${_CHIMAERA_TO_DAEDALUS_TEST}" =~ "_CHIMAERA_TO_DAEDALUS" ]]; then
    sed -i "s/^_CHIMAERA_TO_DAEDALUS.*//g" ${barCnf}
    wait
  fi
  _BULLSEYE_TO_CHIMAERA_TEST=$(grep _BULLSEYE_TO_CHIMAERA ${barCnf} 2>&1)
  if [[ "${_BULLSEYE_TO_CHIMAERA_TEST}" =~ "_BULLSEYE_TO_CHIMAERA" ]]; then
    sed -i "s/^_BULLSEYE_TO_CHIMAERA.*//g" ${barCnf}
    wait
  fi
  _BULLSEYE_TO_BOOKWORM_TEST=$(grep _BULLSEYE_TO_BOOKWORM ${barCnf} 2>&1)
  if [[ "${_BULLSEYE_TO_BOOKWORM_TEST}" =~ "_BULLSEYE_TO_BOOKWORM" ]]; then
    sed -i "s/^_BULLSEYE_TO_BOOKWORM.*//g" ${barCnf}
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
}

#
# Sort and de-duplicate versions in _PHP_MULTI_INSTALL.
php_multi_uniq() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_multi_uniq"
  fi
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
# Cleanup for legacy PHP versions.
php_legacy_versions_cleanup_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_legacy_versions_cleanup_cnf"
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
    mrun "service php-fpm stop" 2> /dev/null
    mrun "update-rc.d -f php-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php-fpm
  fi
  if [ -e "/etc/init.d/php52-fpm" ]; then
    mrun "service php52-fpm stop" 2> /dev/null
    mrun "update-rc.d -f php52-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php52-fpm
  fi
  if [ -e "/etc/init.d/php53-fpm" ]; then
    mrun "service php53-fpm stop" 2> /dev/null
    mrun "update-rc.d -f php53-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php53-fpm
  fi
  if [ -e "/etc/init.d/php54-fpm" ]; then
    mrun "service php54-fpm stop" 2> /dev/null
    mrun "update-rc.d -f php54-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php54-fpm
  fi
  if [ -e "/etc/init.d/php55-fpm" ]; then
    mrun "service php55-fpm stop" 2> /dev/null
    mrun "update-rc.d -f php55-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php55-fpm
  fi

  _CHECK_HOST=$(uname -n 2>&1)
  _VMFAMILY=XEN
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _VMFAMILY="VS"
  fi
}

#
# Cleanup for PHP versions list.
php_if_versions_cleanup_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_if_versions_cleanup_cnf"
  fi
  if [ -e "/root/.allow-php-multi-install-cleanup.cnf" ] \
    || [ -e "/root/.run-to-daedalus.cnf" ] \
    || [ -e "/root/.run-to-chimaera.cnf" ] \
    || [ -e "/root/.run-to-beowulf.cnf" ]; then
    _AUTO_PHP_CLEANUP=YES
  else
    _AUTO_PHP_CLEANUP=NO
  fi
  if [ ! -d "/data/u" ]; then
    _AUTO_PHP_CLEANUP=NO
  fi
  if [ -e "/var/aegir/host_master/000/placeholder_dont_remove.txt" ] \
    && [ "${_AUTO_PHP_CLEANUP}" = "YES" ]; then
    if [ -e "/root/.mstr.clstr.cnf" ] \
      || [ -e "/root/.wbhd.clstr.cnf" ] \
      || [ -e "/root/.dbhd.clstr.cnf" ]; then
      _PHP_OVERRIDE=$(grep _PHP_FPM_VERSION ${barCnf} \
        | cut -d= -f2 \
        | awk '{ print $1}' \
        | sed "s/[\"]//g" 2>&1)
      _CLSTR_PHP_MULTI_INSTALL="${_PHP_OVERRIDE}"
      if [ ! -z "${_CLSTR_PHP_MULTI_INSTALL}" ]; then
        _PHP_MULTI_INSTALL="${_CLSTR_PHP_MULTI_INSTALL}"
      else
        ### Use default mini-legacy list if empty
        _PHP_MULTI_INSTALL="8.1 7.4 5.6"
      fi
    else
      ### Make sure that _PHP_SINGLE_INSTALL takes precedence
      if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
        if [ "${_PHP_SINGLE_INSTALL}" = "8.3" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "8.2" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "8.1" ] \
          || [ "${_PHP_SINGLE_INSTALL}" = "7.4" ]; then
          _PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}
          _PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}
          _PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}
        fi
      else
        ### Make sure that _PHP_MULTI_INSTALL includes _PHP_FPM_VERSION
        if [ "${_OPENSSL_NEW_VRN}" = "${_OPENSSL_LEGACY_VRN}" ]; then
          _PHP_CLI_VERSION=7.4
          _PHP_FPM_VERSION=7.4
        fi
        _local_PHP_MULTI_INSTALL="${_PHP_FPM_VERSION}"

        ### Include only used PHP versions on major automated OS upgrades
        _STRICT_LIMIT_PHP=NO
        if [ -e "/root/.run-to-daedalus.cnf" ] \
          || [ -e "/root/.run-to-chimaera.cnf" ] \
          || [ -e "/root/.run-to-beowulf.cnf" ]; then
          _STRICT_LIMIT_PHP=YES
        fi

        ### Include latest PHP 8.2 and 8.3 if conditions are met
        if [ "${_STRICT_LIMIT_PHP}" = "NO" ]; then
          if [ -e "/root/.include-php-latest.cnf" ] \
            || [ -e "/root/.auto.up.cnf" ] \
            || [ -e "/root/.host8.cnf" ] \
            || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
            || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
            || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
            || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]]; then
            if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ] \
              && [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_EOL_VRN}" ]; then
              _local_PHP_MULTI_INSTALL="8.2 8.3 ${_local_PHP_MULTI_INSTALL}"
            fi
          fi
        fi

        ### Add PHP 5.6 if used
        _is_PHP_multi_five_six=$(grep "5\.6" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_five_six=$(grep "5\.6" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_five_six=$(grep "5\.6" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_five_six=
        if [[ "${_is_PHP_multi_five_six}" =~ "5.6" ]] \
          || [[ "${_is_PHP_FPM_five_six}" =~ "5.6" ]] \
          || [[ "${_is_PHP_CLI_five_six}" =~ "5.6" ]]; then
          _is_PHP_five_six=5.6
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_five_six}"
        fi

        ### Add PHP 7.0 if used
        _is_PHP_multi_seven_zero=$(grep "7\.0" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_seven_zero=$(grep "7\.0" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_seven_zero=$(grep "7\.0" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_seven_zero=
        if [[ "${_is_PHP_multi_seven_zero}" =~ "7.0" ]] \
          || [[ "${_is_PHP_FPM_seven_zero}" =~ "7.0" ]] \
          || [[ "${_is_PHP_CLI_seven_zero}" =~ "7.0" ]]; then
          _is_PHP_seven_zero=7.0
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_zero}"
        fi

        ### Add PHP 7.1 if used
        _is_PHP_multi_seven_one=$(grep "7\.1" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_seven_one=$(grep "7\.1" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_seven_one=$(grep "7\.1" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_seven_one=
        if [[ "${_is_PHP_multi_seven_one}" =~ "7.1" ]] \
          || [[ "${_is_PHP_FPM_seven_one}" =~ "7.1" ]] \
          || [[ "${_is_PHP_CLI_seven_one}" =~ "7.1" ]]; then
          _is_PHP_seven_one=7.1
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_one}"
        fi

        ### Add PHP 7.2 if used
        _is_PHP_multi_seven_two=$(grep "7\.2" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_seven_two=$(grep "7\.2" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_seven_two=$(grep "7\.2" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_seven_two=
        if [[ "${_is_PHP_multi_seven_two}" =~ "7.2" ]] \
          || [[ "${_is_PHP_FPM_seven_two}" =~ "7.2" ]] \
          || [[ "${_is_PHP_CLI_seven_two}" =~ "7.2" ]]; then
          _is_PHP_seven_two=7.2
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_two}"
        fi

        ### Add PHP 7.3 if used
        _is_PHP_multi_seven_three=$(grep "7\.3" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_seven_three=$(grep "7\.3" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_seven_three=$(grep "7\.3" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_seven_three=
        if [[ "${_is_PHP_multi_seven_three}" =~ "7.3" ]] \
          || [[ "${_is_PHP_FPM_seven_three}" =~ "7.3" ]] \
          || [[ "${_is_PHP_CLI_seven_three}" =~ "7.3" ]]; then
          _is_PHP_seven_three=7.3
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_three}"
        fi

        ### Add PHP 7.4 if used
        _is_PHP_multi_seven_four=$(grep "7\.4" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_seven_four=$(grep "7\.4" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_seven_four=$(grep "7\.4" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_seven_four=
        if [[ "${_is_PHP_multi_seven_four}" =~ "7.4" ]] \
          || [[ "${_is_PHP_FPM_seven_four}" =~ "7.4" ]] \
          || [[ "${_is_PHP_CLI_seven_four}" =~ "7.4" ]]; then
          _is_PHP_seven_four=7.4
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_seven_four}"
        fi

        ### Add PHP 8.0 if used
        _is_PHP_multi_eight_zero=$(grep "8\.0" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_eight_zero=$(grep "8\.0" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_eight_zero=$(grep "8\.0" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_eight_zero=
        if [[ "${_is_PHP_multi_eight_zero}" =~ "8.0" ]] \
          || [[ "${_is_PHP_FPM_eight_zero}" =~ "8.0" ]] \
          || [[ "${_is_PHP_CLI_eight_zero}" =~ "8.0" ]]; then
          _is_PHP_eight_zero=8.0
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_eight_zero}"
        fi

        ### Add PHP 8.1 if used
        _is_PHP_multi_eight_one=$(grep "8\.1" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_eight_one=$(grep "8\.1" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_eight_one=$(grep "8\.1" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_eight_one=
        if [[ "${_is_PHP_multi_eight_one}" =~ "8.1" ]] \
          || [[ "${_is_PHP_FPM_eight_one}" =~ "8.1" ]] \
          || [[ "${_is_PHP_CLI_eight_one}" =~ "8.1" ]]; then
          _is_PHP_eight_one=8.1
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_eight_one}"
        fi

        ### Add PHP 8.2 if used
        _is_PHP_multi_eight_two=$(grep "8\.2" /data/disk/*/static/control/multi-fpm.info 2>&1)
        _is_PHP_FPM_eight_two=$(grep "8\.2" /data/disk/*/static/control/fpm.info 2>&1)
        _is_PHP_CLI_eight_two=$(grep "8\.2" /data/disk/*/static/control/cli.info 2>&1)
        _is_PHP_eight_two=
        if [[ "${_is_PHP_multi_eight_two}" =~ "8.2" ]] \
          || [[ "${_is_PHP_FPM_eight_two}" =~ "8.2" ]] \
          || [[ "${_is_PHP_CLI_eight_two}" =~ "8.2" ]]; then
          _is_PHP_eight_two=8.2
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_eight_two}"
        fi

        ### Add PHP 8.3 if used
        _is_PHP_multi_eight_three=$(grep "8\.3" /data/disk/*/static/control/multi-fpm.info 3>&1)
        _is_PHP_FPM_eight_three=$(grep "8\.3" /data/disk/*/static/control/fpm.info 3>&1)
        _is_PHP_CLI_eight_three=$(grep "8\.3" /data/disk/*/static/control/cli.info 3>&1)
        _is_PHP_eight_three=
        if [[ "${_is_PHP_multi_eight_three}" =~ "8.3" ]] \
          || [[ "${_is_PHP_FPM_eight_three}" =~ "8.3" ]] \
          || [[ "${_is_PHP_CLI_eight_three}" =~ "8.3" ]]; then
          _is_PHP_eight_three=8.3
          _local_PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL} ${_is_PHP_eight_three}"
        fi

        ### Overwrite _PHP_MULTI_INSTALL with the list of used PHP versions
        _PHP_MULTI_INSTALL="${_local_PHP_MULTI_INSTALL}"

        if [ -z "${_PHP_MULTI_INSTALL}" ]; then
          ### Use default mini-legacy list if empty
          _PHP_MULTI_INSTALL="8.1 7.4 5.6"
        else
          ### Sort and remove duplicates from _PHP_MULTI_INSTALL
          php_multi_uniq
        fi
        export _PHP_MULTI_INSTALL="${_PHP_MULTI_INSTALL}"

        ### Remove previous _PHP_MULTI_INSTALL in /root/.barracuda.cnf
        _PHP_MULTI_TEST=$(grep _PHP_MULTI_INSTALL ${barCnf} 2>&1)
        if [[ "${_PHP_MULTI_TEST}" =~ "_PHP_MULTI_INSTALL" ]]; then
          sed -i "s/^_PHP_MULTI_INSTALL.*//g" ${barCnf}
          wait
          sed -i "s/^_PHP_ORIG_MULTI.*//g" ${barCnf}
          wait
          sed -i "/^$/d" ${barCnf}
          wait
        fi

        ### Add optimized _PHP_MULTI_INSTALL in /root/.barracuda.cnf
        echo "_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"" >> ${barCnf}

        ### Export optimized list as a new var
        _PHP_MULTI_OPTIM="${_PHP_MULTI_INSTALL}"
        export _PHP_MULTI_OPTIM="${_PHP_MULTI_OPTIM}"

        ### Disable not used PHP versions
        php_not_used_disable

        ### Ctrl files cleanup
        touch /root/.sorted.multi.php.cnf
        [ -e "/root/.updated.multi.php.cnf" ] && rm -f /root/.updated.multi.php.cnf
        [ -e "/root/.fixed.multi.php.cnf" ] && rm -f /root/.fixed.multi.php.cnf
      fi
    fi
  fi
}

#
# Cleanup for PHP versions list.
if_php_idle_on_off() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_php_idle_on_off"
  fi
  if [ "${_PHP_IDLE}" = "ON" ]; then
    [ -e "/root/.allow-php-multi-install-cleanup.cnf" ] && rm -f /root/.allow-php-multi-install-cleanup.cnf
    if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
      rm -f /var/xdrago_wait/log/*.log
      rm -f /var/xdrago_wait/log/.php_libs_fix_*.pid
    else
      rm -f /var/xdrago/log/*.log
      rm -f /var/xdrago/log/.php_libs_fix_*.pid
    fi
    touch /root/.proxy.cnf
    kill -9 $(ps aux | grep '[s]econd.sh' | awk '{print $2}') &> /dev/null
    sleep 5
    php_not_used_enable_again
    sed -i "s/^_PHP_IDLE.*//g" ${barCnf}
    [ -e "/root/.proxy.cnf" ] && rm -f /root/.proxy.cnf
    php_install_deps
    php_libs_fix
    if [ "${_STATUS}" = "UPGRADE" ]; then
      php_ioncube_check_if_update
      php_check_if_rebuild
    fi
    php_install_upgrade
    php_config_check_update
    php_upgrade_all
    if_install_php_newrelic
    newrelic_check_fix
    complete
    exit 0
  elif [ "${_PHP_IDLE}" = "OFF" ]; then
    touch /root/.proxy.cnf
    kill -9 $(ps aux | grep '[s]econd.sh' | awk '{print $2}') &> /dev/null
    sleep 5
    touch /root/.allow-php-multi-install-cleanup.cnf
    php_if_versions_cleanup_cnf
    sed -i "s/^_PHP_IDLE.*//g" ${barCnf}
    [ -e "/root/.proxy.cnf" ] && rm -f /root/.proxy.cnf
    if [ -e "/root/.run-to-daedalus.cnf" ] \
      || [ -e "/root/.run-to-chimaera.cnf" ] \
      || [ -e "/root/.run-to-beowulf.cnf" ]; then
      echo " "
      msg "Bye"
      clean_pid_exit if_php_idle_on_off_a
    else
      complete
      exit 0
    fi
  fi
}

#
# Read or create Barracuda cnf file.
barracuda_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: barracuda_cnf"
  fi
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
        || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
        || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
        || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
        if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
          _DO_NOTHING=YES
        else
          _DO_NOTHING=YES
        fi
      else
        msg "EXIT: Invalid email address defined in the _MY_EMAIL variable"
        msg "EXIT: Bye (1)"
        clean_pid_exit barracuda_cnf_a
      fi
    fi
    if [ "${_DB_SERIES}" = "5.7" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _DBS_VRN="${_GALERA_10_VRN}"
      else
        if [ "${_DB_SERIES}" = "5.7" ]; then
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
    ### Force ImageMagick from packages
    sed -i "s/^_MAGICK_FROM_S.*/_MAGICK_FROM_SOURCES=NO/g"       ${barCnf}
    wait
    if [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
      || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
      || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
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
          sed -i "s/^_PHP_CLI_VERSION=5.6/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=5.6/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.0/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.0/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.1/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.1/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.2/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.2/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.3/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.3/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=8.0/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=8.0/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
        fi
        # if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        #   || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
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
    if [ "${_LOCAL_DEBIAN_MIRROR}" = "deb.debian.org" ] \
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

    if [ -d "/data/u" ]; then
      php_legacy_versions_cleanup_cnf
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

    sleep 1
    _CHECK_HOST=$(uname -n 2>&1)
    ### Force HTTP/2 or SPDY plus PFS on supported systems
    sed -i "s/^_NGINX_SPDY=.*/_NGINX_SPDY=YES/g"                 ${barCnf}
    wait
    sed -i "s/^_NGINX_FORWARD.*/_NGINX_FORWARD_SECRECY=YES/g"    ${barCnf}
    wait
    ### Force ImageMagick from packages
    sed -i "s/^_MAGICK_FROM_S.*/_MAGICK_FROM_SOURCES=NO/g"       ${barCnf}
    wait
    if [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ] \
      || [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
      || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
      || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
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
          sed -i "s/^_PHP_CLI_VERSION=5.6/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=5.6/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.0/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.0/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.1/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.1/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.2/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.2/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.3/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.3/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=7.4/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=7.4/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_CLI_VERSION=8.0/_PHP_CLI_VERSION=8.1/g"                  ${barCnf}
          wait
          sed -i "s/^_PHP_FPM_VERSION=8.0/_PHP_FPM_VERSION=8.1/g"                  ${barCnf}
          wait
        fi
        # if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
        #   || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
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
    if [ "${_LOCAL_DEBIAN_MIRROR}" = "deb.debian.org" ] \
      || [ "${_LOCAL_DEBIAN_MIRROR}" = "httpredir.debian.org" ] \
      || [ "${_LOCAL_DEBIAN_MIRROR}" = "ftp.debian.org" ]; then
      _LOCAL_DEBIAN_MIRROR="deb.debian.org"
      sed -i "s/^_LOCAL_DEBIAN_.*/_LOCAL_DEBIAN_MIRROR=deb.debian.org/g"     ${barCnf}
      wait
    fi
    if [ "${_DB_SERIES}" = "5.7" ]; then
      if [ -e "/root/.mstr.clstr.cnf" ] \
        || [ -e "/root/.wbhd.clstr.cnf" ] \
        || [ -e "/root/.dbhd.clstr.cnf" ]; then
        _DBS_VRN="${_GALERA_10_VRN}"
      else
        if [ "${_DB_SERIES}" = "5.7" ]; then
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
        || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
        || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
        || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
        if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
          _DO_NOTHING=YES
        else
          _DO_NOTHING=YES
        fi
      else
        msg "EXIT: Invalid email address defined in the _MY_EMAIL variable"
        msg "EXIT: Bye (2)"
        clean_pid_exit barracuda_cnf_b
      fi
    fi

    ### Make sure that _PHP_SINGLE_INSTALL takes precedence
    if [ ! -z "${_PHP_SINGLE_INSTALL}" ]; then
      if [ "${_PHP_SINGLE_INSTALL}" = "8.3" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "8.2" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "8.1" ] \
        || [ "${_PHP_SINGLE_INSTALL}" = "7.4" ]; then
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
        if [ -d "/data/u" ] && [ -e "/data/conf/global.inc" ]; then
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

    if [ "${_STATUS}" = "INIT" ]; then
      if prompt_yes_no "Do you want to proceed with the install?" ; then
        true
      else
        echo "Installation aborted by you"
        clean_pid_exit barracuda_cnf_c
      fi
    else
      echo " "
      if prompt_yes_no "Do you want to proceed with the upgrade?" ; then
        true
      else
        echo "Upgrade aborted by you"
        clean_pid_exit barracuda_cnf_d
      fi
    fi
  fi
}

#
# Install MyTop.
mytop_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: mytop_install"
  fi
  if [ -e "/usr/bin/mytop" ]; then
    mrun "apt-get remove mytop -y -qq" 2> /dev/null
    rm -f /usr/bin/mytop
  fi
  if [ ! -e "/usr/local/bin/mytop" ] && [ -e "/usr/bin/mysql" ]; then
    msg "INFO: Building MyTop from sources..."
    cd /var/opt
    rm -rf git*
    get_dev_src "mytop-1.6.tar.gz"
    cd /var/opt/mytop-1.6
    mrun "perl Makefile.PL" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
  fi
}

#
# Running apt-get full-dist-upgrade.
run_apt_get_dist_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: run_apt_get_dist_upgrade"
  fi
  msg "INFO: Running apt-get upgrade..."
  apt_clean_update_no_releaseinfo_change
  mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Running apt-get dist-upgrade..."
  fi
  mrun "apt-get dist-upgrade ${dstUpArg}" 2> /dev/null
  [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
  mrun "apt-get dist-upgrade -y --allow-unauthenticated" 2> /dev/null
  [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
  mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
  ### Update rsyslog configuration early
  rsyslog_config_update
  ### Reload key services if needed early
  mrun "service redis-server reload" 2> /dev/null
  mrun "service nginx reload" 2> /dev/null
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      mrun "service php${e}-fpm reload" 2> /dev/null
    fi
  done
  if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
    mrun "perl /var/xdrago_wait/proc_num_ctrl.cgi" 2> /dev/null
  else
    mrun "perl /var/xdrago/proc_num_ctrl.cgi" 2> /dev/null
  fi
}

#
# Run aptitude full-upgrade.
run_aptitude_full_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: run_aptitude_full_upgrade"
  fi
  msg "INFO: Running aptitude full-upgrade..."
  ###
  ### Make sure that percona-release package is locked in apt early.
  if [ ! -e "/etc/apt/preferences.d/percona-release" ]; then
    echo -e 'Package: percona-release\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/percona-release
    apt_clean_update
  fi
  ###
  _PERC_GET_DPKG=$(dpkg --get-selections | grep percona-release | grep 'hold$' 2>&1)
  if [[ ! "${_PERC_GET_DPKG}" =~ "hold" ]]; then
    aptitude hold percona-release &> /dev/null
    echo "percona-release hold" | dpkg --set-selections &> /dev/null
    apt_clean_update
  fi
  mrun "apt-get remove percona-release -y -qq" 2> /dev/null
  apt_clean_update
  if [ -e "/var/aegir/drush" ]; then
    _DPKG_CNF="confold"
  else
    _DPKG_CNF="confnew"
  fi
  st_runner "apt-get --fix-broken install -y" 2> /dev/null
  st_runner "dpkg --configure --force-all -a" 2> /dev/null
  st_runner "aptitude full-upgrade -f -y -q \
    --allow-untrusted \
    -o Dpkg::Options::=--force-confmiss \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-${_DPKG_CNF}" &> /dev/null
}

#
# Install latest Git.
do_install_latest_git() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: do_install_latest_git"
  fi
  if [ "${_GIT_INSTALL}" = "YES" ]; then
    msg "INFO: Building Git ${_GIT_VRN} from sources..."
    msg "WAIT: This may take a while, please wait..."
    apt_clean_update
    mrun "apt-get install libcurl4 -y --allow-unauthenticated" 2> /dev/null
    mrun "apt-get install libcurl4-openssl-dev -y --allow-unauthenticated" 2> /dev/null
    mrun "apt-get install libcurl4-gnutls-dev -y --allow-unauthenticated" 2> /dev/null
    mrun "apt-get remove git-core -y --purge --auto-remove" 2> /dev/null
    mrun "apt-get remove git -y --purge --auto-remove" 2> /dev/null
    mkdir -p /var/opt
    rm -rf /var/opt/git*
    cd /var/opt
    get_dev_src "git-${_GIT_VRN}.tar.gz"
    cd /var/opt/git-${_GIT_VRN}
    mrun "make configure" 2> /dev/null
    mrun "bash ./configure --without-tcltk" 2> /dev/null
    mrun "make all -j $(nproc)" 2> /dev/null
    mrun "make install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -x "/usr/local/bin/git" ]; then
      if [ -e "/usr/bin/git" ] && [ ! -L "/usr/bin/git" ]; then
        mv -f /usr/bin/git /usr/bin/git-old
      fi
      ln -sfn /usr/local/bin/git /usr/bin/git
    fi
    cd /var/opt
    touch ${pthLog}/git-${_GIT_VRN}-${_X_SE}-${_X_VERSION}-${_NOW}.log
    echo "git hold" | dpkg --set-selections &> /dev/null
    echo "git-core hold" | dpkg --set-selections &> /dev/null
    echo "git-man hold" | dpkg --set-selections &> /dev/null
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Git ${_GIT_V} already installed from sources ${_GIT_VRN}, OK"
    fi
  fi
}

#
# Check if latest Git should be installed.
if_install_git_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_git_src"
  fi
  _GIT_INSTALL=NO
  _GIT_V=$(git --version 2>&1 \
    | cut -d" " -f3 \
    | awk '{ print $1}' 2>&1)
  if [ ! -z "${_GIT_V}" ]; then
    if [ "${_GIT_V}" != "${_GIT_VRN}" ]; then
      _GIT_INSTALL=YES
    fi
  fi
  if [ "${_GIT_INSTALL}" = "YES" ] \
    || [ "${_GIT_FORCE_REINSTALL}" = "YES" ]; then
    do_install_latest_git
  fi
}

#
# Check apt-get updates.
check_apt_updates() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_apt_updates"
  fi
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
# Install modern ICU from sources.
install_icu_modern() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_icu_modern"
  fi
  ###--------------------###
  if [ -e "/usr/lib/x86_64-linux-gnu/.old_icu" ]; then
    rm -rf /var/backups/.old_icu
    mv -f /usr/lib/x86_64-linux-gnu/.old_icu /var/backups/.old_icu
  fi
  if [ -e "/usr/lib/x86_64-linux-gnu/.legacy_icu" ]; then
    rm -rf /var/backups/.legacy_icu
    mv -f /usr/lib/x86_64-linux-gnu/.legacy_icu /var/backups/.legacy_icu
  fi
  if [ ! -e "${pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    pthLog="/var/xdrago_wait/log"
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ -e "${pthLog}" ]; then
    pthIcuLog="${pthLog}/icu-update-${_ICU_MODERN_VRN}-for-${_OS_CODE}.log"
    pthIcuLcy="${pthLog}/icu-update-${_ICU_MODERN_VRN}.log"
  else
    pthIcuLog="/root/.icu-update-${_ICU_MODERN_VRN}-for-${_OS_CODE}.log"
    pthIcuLcy="/root/.icu-update-${_ICU_MODERN_VRN}.log"
  fi
  if [ "${_OS_CODE}" = "daedalus" ] \
    && [ -e "${pthIcuLcy}" ] \
    && [ ! -e "${pthIcuLog}" ]; then
    touch ${pthIcuLog}
  fi
  if [ -e "${pthIcuLog}" ]; then
    chattr -i ${pthIcuLog}
  fi
  if [ -e "${pthIcuLcy}" ]; then
    chattr -i ${pthIcuLcy}
  fi
  if [ ! -e "/usr/local/lib/icu/current" ] \
    || [ ! -e "${pthIcuLog}" ]; then
    msg "INFO: Installing ICU libs version ${_ICU_MODERN_VRN}..."
    msg "WAIT: This may take a while, please wait..."
    if [ ! -e "/var/opt/icu-release-${_ICU_MODERN_VRN}/icu4c/source" ]; then
      cd /var/opt
      rm -rf icu*
      get_dev_src "icu-release-${_ICU_MODERN_VRN}.tar.gz"
    fi
    cd /var/opt/icu-release-${_ICU_MODERN_VRN}/icu4c/source
    mrun "bash ./configure --prefix=/usr/local" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/local/lib/icu" ]; then
      touch ${pthIcuLog}
    fi
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      if [ -e "/usr/local/lib/icu" ]; then
        if [ -d "/usr/lib/x86_64-linux-gnu/icu" ]; then
          rm -rf /var/backups/pre_icu
          mv -f /usr/lib/x86_64-linux-gnu/icu /var/backups/pre_icu
        fi
        if [ ! -L "/usr/lib/x86_64-linux-gnu/icu" ]; then
          ln -sfn /usr/local/lib/icu /usr/lib/x86_64-linux-gnu/icu
        fi
      fi
    fi
  fi
}

#
# Install ICU from sources for Jessie.
install_icu_jessie() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_icu_jessie"
  fi
  ###--------------------###
  if [ ! -e "${pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    pthLog="/var/xdrago_wait/log"
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ -e "${pthLog}" ]; then
    pthIcuLog="${pthLog}/icu-update-${_ICU_LEGACY_VRN}-for-${_OS_CODE}.log"
    pthIcuLcy="${pthLog}/icu-update-${_ICU_LEGACY_VRN}.log"
  else
    pthIcuLog="/root/.icu-update-${_ICU_LEGACY_VRN}-for-${_OS_CODE}.log"
    pthIcuLcy="/root/.icu-update-${_ICU_LEGACY_VRN}.log"
  fi
  if [ "${_OS_CODE}" = "daedalus" ] \
    && [ -e "${pthIcuLcy}" ] \
    && [ ! -e "${pthIcuLog}" ]; then
    touch ${pthIcuLog}
  fi
  if [ -e "${pthIcuLog}" ]; then
    chattr -i ${pthIcuLog}
  fi
  if [ -e "${pthIcuLcy}" ]; then
    chattr -i ${pthIcuLcy}
  fi
  if [ ! -e "/usr/local/lib/icu/current" ] \
    || [ ! -e "${pthIcuLog}" ]; then
    msg "INFO: Installing ICU libs version ${_ICU_LEGACY_VRN}..."
    msg "WAIT: This may take a while, please wait..."
    if [ ! -e "/var/opt/icu/source" ]; then
      cd /var/opt
      rm -rf icu*
      get_dev_src "icu4c-${_ICU_LEGACY_VRN}-src.tgz"
    fi
    cd /var/opt/icu/source/
    mrun "bash ./configure --prefix=/usr/local" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/local/lib/icu" ]; then
      touch ${pthIcuLog}
    fi
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      if [ -e "/usr/local/lib/icu" ]; then
        if [ -d "/usr/lib/x86_64-linux-gnu/icu" ]; then
          rm -rf /var/backups/pre_icu
          mv -f /usr/lib/x86_64-linux-gnu/icu /var/backups/pre_icu
        fi
        if [ ! -L "/usr/lib/x86_64-linux-gnu/icu" ]; then
          ln -sfn /usr/local/lib/icu /usr/lib/x86_64-linux-gnu/icu
        fi
      fi
    fi
  fi
}

#
# Install PHP deps.
php_install_deps() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_install_deps"
  fi
  ###--------------------###
  apt_clean_update
  mrun "${_INSTAPP} cmake" 2> /dev/null
  mrun "${_INSTAPP} lbzip2" 2> /dev/null
  mrun "${_INSTAPP} libcurl4-openssl-dev" 2> /dev/null
  mrun "${_INSTAPP} libgd-dev" 2> /dev/null
  mrun "${_INSTAPP} libgd3" 2> /dev/null
  mrun "${_INSTAPP} libjpeg-dev" 2> /dev/null
  mrun "${_INSTAPP} libjpeg62" 2> /dev/null
  mrun "${_INSTAPP} libkrb5-dev" 2> /dev/null
  mrun "${_INSTAPP} liblzf-dev" 2> /dev/null
  mrun "${_INSTAPP} libmagickwand-dev" 2> /dev/null
  mrun "${_INSTAPP} libonig-dev" 2> /dev/null
  mrun "${_INSTAPP} libsodium-dev" 2> /dev/null
  mrun "${_INSTAPP} libwebp-dev" 2> /dev/null
  mrun "${_INSTAPP} libxpm-dev" 2> /dev/null
  mrun "${_INSTAPP} libzip-dev" 2> /dev/null
  if [ "${_OS_CODE}" = "daedalus" ] \
    || [ "${_OS_CODE}" = "bookworm" ]; then
    if [ ! -e "/root/.rebuild_src_on_auto_before_reboot.info" ]; then
      mrun "${_INSTAPP} libldap-common" 2> /dev/null
      mrun "${_INSTAPP} libldap-dev" 2> /dev/null
      mrun "${_INSTAPP} libldap2-dev" 2> /dev/null
    fi
  else
    mrun "${_INSTAPP} libldap-common" 2> /dev/null
    mrun "${_INSTAPP} libldap2-dev" 2> /dev/null
  fi
  if [ "${_OS_CODE}" = "jessie" ]; then
    install_icu_jessie
  else
    install_icu_modern
    # mrun "${_INSTAPP} libicu-dev icu-devtools" 2> /dev/null
  fi
}

#
# Install wkhtmltopdf and wkhtmltoimage.
if_install_wkhtmltox() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_wkhtmltox"
  fi
  ###--------------------###
  apt_clean_update
  mrun "${_INSTAPP} fonts-thai-tlwg" 2> /dev/null
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  _X86_64_TEST=$(uname -m 2>&1)
  _WOX_IS=OLD
  _WOX_ITD=$(wkhtmltopdf --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}')
  if [ "${_OS_CODE}" = "jessie" ]; then
    _WOX_ITD=$(wkhtmltopdf --version 2>&1)
  fi
  if [[ "${_WOX_ITD}" =~ "0.12.6" ]]; then
    if [ "${_OS_CODE}" = "chimaera" ] \
      || [ "${_OS_CODE}" = "beowulf" ] \
      || [ "${_OS_CODE}" = "bullseye" ] \
      || [ "${_OS_CODE}" = "buster" ] \
      || [ "${_OS_CODE}" = "stretch" ]; then
      _WOX_IS=NEW
      if [ "${_OS_CODE}" = "chimaera" ] \
        || [ "${_OS_CODE}" = "bullseye" ]; then
        _WKHTMLTOX_VRN="12.6.1-2"
      else
        _WKHTMLTOX_VRN="12.6-1"
      fi
    fi
  fi
  if [[ "${_WOX_ITD}" =~ "0.12.5" ]]; then
    if [ "${_OS_CODE}" = "jessie" ]; then
      _WOX_IS=NEW
      _WKHTMLTOX_VRN="12.5-1"
    fi
  fi
  if [ "${_OS_CODE}" = "chimaera" ] \
    || [ "${_OS_CODE}" = "beowulf" ] \
    || [ "${_OS_CODE}" = "bullseye" ] \
    || [ "${_OS_CODE}" = "buster" ] \
    || [ "${_OS_CODE}" = "stretch" ] \
    || [ "${_OS_CODE}" = "jessie" ]; then
    if [ "${_WOX_IS}" = "OLD" ] \
      || [ ! -x "/usr/local/bin/wkhtmltopdf" ] \
      || [ ! -x "/usr/local/bin/wkhtmltoimage" ] \
      || [ ! -f "/usr/bin/wkhtmltopdf" ] \
      || [ ! -f "/usr/bin/wkhtmltoimage" ] \
      || [ -L "/usr/bin/wkhtmltopdf" ] \
      || [ -L "/usr/bin/wkhtmltoimage" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installing wkhtmltox tools v.0.${_WKHTMLTOX_VRN}..."
      fi
      apt_clean_update
      mrun "${_INSTAPP} xfonts-75dpi xfonts-base" 2> /dev/null
      mrun "${_INSTAPP} wkhtmltopdf" 2> /dev/null
    fi
  else
    if [ "${_WOX_IS}" = "OLD" ] \
      || [ ! -x "/usr/local/bin/wkhtmltopdf" ] \
      || [ ! -x "/usr/local/bin/wkhtmltoimage" ] \
      || [ ! -f "/usr/bin/wkhtmltopdf" ] \
      || [ ! -f "/usr/bin/wkhtmltoimage" ] \
      || [ -L "/usr/bin/wkhtmltopdf" ] \
      || [ -L "/usr/bin/wkhtmltoimage" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      if [ "${_OS_CODE}" = "beowulf" ]; then
        _WKHTML_SYS_RV="buster"
      elif [ "${_OS_CODE}" = "chimaera" ]; then
        _WKHTML_SYS_RV="bullseye"
      elif [ "${_OS_CODE}" = "daedalus" ]; then
        _WKHTML_SYS_RV="none"
      elif [ "${_OS_CODE}" = "bookworm" ]; then
        _WKHTML_SYS_RV="none"
      else
        _WKHTML_SYS_RV="${_OS_CODE}"
      fi
      if [ "${_WKHTML_SYS_RV}" != "none" ] && [ "${_X86_64_TEST}" = "x86_64" ]; then
        SYSTEM_ARCH="x86_64"
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installing wkhtmltox tools v.0.${_WKHTMLTOX_VRN}..."
        fi
        cd /var/opt
        rm -rf wkhtmltox*
        mkdir -p /var/opt/wkhtmltox
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          mrun "${_INSTAPP} xfonts-75dpi xfonts-base" 2> /dev/null
          get_dev_src "wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb.gz"
          dpkg -i "/var/opt/wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb"
          mrun "apt-get install -f -y" 2> /dev/null
        else
          mrun "${_INSTAPP} xfonts-75dpi xfonts-base" 2> /dev/null
          get_dev_src "wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb.gz" 2> /dev/null
          dpkg -i "/var/opt/wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb" 2> /dev/null
          mrun "apt-get install -f -y" 2> /dev/null
        fi
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
  if [ ! -x "/usr/local/bin/wkhtmltopdf" ] \
    && [ -x "/usr/bin/wkhtmltopdf" ]; then
    rm -f /usr/local/bin/wkhtmltopdf
    cp -af /usr/bin/wkhtmltopdf /usr/local/bin/wkhtmltopdf
    chgrp root /usr/local/bin/wkhtmltopdf &> /dev/null
    chmod 755 /usr/local/bin/wkhtmltopdf &> /dev/null
  fi
  if [ ! -x "/usr/local/bin/wkhtmltoimage" ] \
    && [ -x "/usr/bin/wkhtmltoimage" ]; then
    rm -f /usr/local/bin/wkhtmltoimage
    cp -af /usr/bin/wkhtmltoimage /usr/local/bin/wkhtmltoimage
    chgrp root /usr/local/bin/wkhtmltoimage &> /dev/null
    chmod 755 /usr/local/bin/wkhtmltoimage &> /dev/null
  fi
}

#
# Clean Drush 12.
clean_drush_twelve() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: clean_drush_twelve"
  fi
  rm -f /usr/bin/drush12*
  ln -sfn /opt/tools/drush/12/drush/vendor/bin/drush /usr/bin/drush12
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH_TWELVE_VRN} setup complete"
  fi
}

#
# Clean Drush 11.
clean_drush_eleven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: clean_drush_eleven"
  fi
  rm -f /usr/bin/drush11*
  ln -sfn /opt/tools/drush/11/drush/vendor/bin/drush /usr/bin/drush11
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} setup complete"
  fi
}

#
# Clean Drush 10.
clean_drush_ten() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: clean_drush_ten"
  fi
  rm -f /usr/bin/drush10*
  rm -f /usr/local/bin/dcg
  rm -f /usr/local/bin/drush
  rm -f /usr/local/bin/php-parse
  rm -f /usr/local/bin/psysh
  rm -f /usr/local/bin/release
  rm -f /usr/local/bin/robo
  rm -f /usr/local/bin/var-dump-server
  ln -sfn /opt/tools/drush/10/drush/vendor/bin/drush /usr/bin/drush10
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH_TEN_VRN} setup complete"
  fi
}

#
# Set Drush permissions.
set_drush_perm() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: set_drush_perm"
  fi
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
  if [ -e "/opt/tools/drush/10/drush/vendor/bin/drush" ]; then
    chmod 755 /opt/tools/drush/10/drush/vendor/bin/*
  fi
  if [ -e "/opt/tools/drush/11/drush/vendor/drush/drush/drush" ]; then
    chmod 755 /opt/tools/drush/11/drush/vendor/drush/drush/drush
    chmod 755 /opt/tools/drush/11/drush/vendor/drush/drush/drush.php
  fi
  if [ -e "/opt/tools/drush/11/drush/vendor/bin/drush" ]; then
    chmod 755 /opt/tools/drush/11/drush/vendor/bin/*
  fi
  if [ -e "/opt/tools/drush/12/drush/vendor/drush/drush/drush" ]; then
    chmod 755 /opt/tools/drush/12/drush/vendor/drush/drush/drush
    chmod 755 /opt/tools/drush/12/drush/vendor/drush/drush/drush.php
  fi
  if [ -e "/opt/tools/drush/12/drush/vendor/bin/drush" ]; then
    chmod 755 /opt/tools/drush/12/drush/vendor/bin/*
  fi
}

#
# Install or update Drush 12.
get_drush_twelve() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: get_drush_twelve"
  fi
  rm -rf /opt/tools/drush/12/*
  cd /opt/tools/drush/12/
  get_dev_ext "drush-${_DRUSH_TWELVE_VRN}.tar.gz"
  touch /opt/tools/drush/12/.ctrl.${_X_SE}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Drush ${_DRUSH_TWELVE_VRN} installation complete"
  fi
}

#
# Install or update Drush 11.
get_drush_eleven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: get_drush_eleven"
  fi
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: get_drush_ten"
  fi
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: get_drush_eight"
  fi
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
drush_system_install_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: drush_system_install_update"
  fi
  if [ ! -e "/root/.debug-barracuda-installer.cnf" ] \
    && [ ! -e "/root/.skip-aegir-master-upgrade.cnf" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installing supported Drush versions..."
    fi
    ###
    ### Force all Drush versions update if serial is not new
    rm -f /opt/tools/drush/8/.ctrl.${_X_SE}.pid
    rm -f /opt/tools/drush/10/.ctrl.${_X_SE}.pid
    rm -f /opt/tools/drush/11/.ctrl.${_X_SE}.pid
    rm -f /opt/tools/drush/12/.ctrl.${_X_SE}.pid
    ###
    ###--------------------###
    if [ -e "/opt/tools/drush/launcher" ]; then
      rm -rf /opt/tools/drush/launcher
      rm -f /usr/bin/drushlr
    fi
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
    mkdir -p /opt/tools/drush/{8,10,11,12}
    chown -R root:root /opt/tools
    if [ -e "/opt/tools/drush/8" ]; then
      _DRUSH_ITD=$(drush8 --version 2>&1 \
        | tr -d "\n" \
        | cut -d" " -f8 \
        | awk '{ print $1}' 2>&1)
      if [ "${_DRUSH_ITD}" != "${_DRUSH_EIGHT_TEST_VRN}" ] \
        || [ ! -x "/opt/tools/drush/8/drush/drush.php" ] \
        || [ ! -e "/opt/tools/drush/8/.ctrl.${_X_SE}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_EIGHT_VRN} re-installation required"
        fi
        get_drush_eight
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_EIGHT_VRN} already installed"
        fi
      fi
    fi
    if [ -e "/opt/tools/drush/10" ]; then
      _DRUSH_ITD=$(drush10 --version 2>&1 \
        | tr -d "\n" \
        | cut -d" " -f4 \
        | awk '{ print $1}' 2>&1)
      if [ "${_DRUSH_ITD}" != "${_DRUSH_TEN_VRN}" ] \
        || [ ! -x "/opt/tools/drush/10/drush/vendor/drush/drush/drush" ] \
        || [ ! -e "/opt/tools/drush/10/.ctrl.${_X_SE}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_TEN_VRN} re-installation required"
        fi
        get_drush_ten
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_TEN_VRN} already installed"
        fi
      fi
    fi
    if [ -e "/opt/tools/drush/11" ]; then
      _DRUSH_ITD=$(drush11 --version 2>&1 \
        | tr -d "\n" \
        | cut -d" " -f4 \
        | awk '{ print $1}' 2>&1)
      if [ "${_DRUSH_ITD}" != "${_DRUSH_ELEVEN_VRN}" ] \
        || [ ! -x "/opt/tools/drush/11/drush/vendor/drush/drush/drush" ] \
        || [ ! -e "/opt/tools/drush/11/.ctrl.${_X_SE}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} re-installation required"
        fi
        get_drush_eleven
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} already installed"
        fi
      fi
    fi
    if [ -e "/opt/tools/drush/12" ]; then
      _DRUSH_ITD=$(drush12 --version 2>&1 \
        | tr -d "\n" \
        | cut -d" " -f4 \
        | awk '{ print $1}' 2>&1)
      if [ "${_DRUSH_ITD}" != "${_DRUSH_TWELVE_VRN}" ] \
        || [ ! -x "/opt/tools/drush/12/drush/vendor/bin/drush" ] \
        || [ ! -e "/opt/tools/drush/12/.ctrl.${_X_SE}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_TWELVE_VRN} re-installation required"
        fi
        get_drush_twelve
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Drush ${_DRUSH_TWELVE_VRN} already installed"
        fi
      fi
    fi
    set_drush_perm
    if [ -x "/opt/tools/drush/8/drush/drush.php" ]; then
      rm -f /usr/bin/drush8
      rm -f /usr/bin/drush
      ln -s /opt/tools/drush/8/drush/drush.php /usr/bin/drush8
      ln -s /opt/tools/drush/8/drush/drush.php /usr/bin/drush
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
    if [ -x "/opt/tools/drush/12/drush/vendor/bin/drush" ]; then
      clean_drush_twelve
    else
      msg "FAIL: Drush ${_DRUSH_TWELVE_VRN} installation failed!"
    fi
    chown -R root:root /opt/tools/drush
    cd /opt/tmp
  fi
}

#
# Update packages sources list.
sources_list_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sources_list_update"
  fi
  ###--------------------###
  apt-get clean -qq 2> /dev/null
  #rm -rf /var/lib/apt/lists/*
  ###--------------------###
  if [ -e "${pthLog}/apt-deb-src-updates-${_X_SE}.txt" ] \
    || [ -e "/var/log/apt-deb-src-updates-${_X_SE}.txt" ]; then
    _APT_SOURCES_REWRITE=NO
    if [ ! -z "${_LOCAL_DEVUAN_MIRROR}" ]; then
      _APT_SOURCES_REWRITE=YES
    fi
    if [ ! -z "${_LOCAL_DEBIAN_MIRROR}" ]; then
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
      ${vBs}/sources.list-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
    if [ "${_OS_DIST}" = "Devuan" ]; then
	  if [ -z "${_LOCAL_DEVUAN_MIRROR}" ]; then
		_MIRROR=deb.devuan.org
	  else
		_MIRROR=${_LOCAL_DEVUAN_MIRROR}
	  fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: We will use ${_OS_DIST} mirror ${_MIRROR}"
      fi
      cd /var/opt
      echo "## DEVUAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_MIRROR}/merged ${_OS_CODE} main" >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/merged ${_OS_CODE} main" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
	  echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
	  echo "deb http://${_MIRROR}/merged ${_OS_CODE}-updates main" >> ${aptLiSys}
	  echo "deb-src http://${_MIRROR}/merged ${_OS_CODE}-updates main" >> ${aptLiSys}
	  echo "" >> ${aptLiSys}
      echo "## DEVUAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://${_MIRROR}/merged ${_OS_CODE}-security main" >> ${aptLiSys}
      echo "deb-src http://${_MIRROR}/merged ${_OS_CODE}-security main" >> ${aptLiSys}
    elif [ "${_OS_DIST}" = "Debian" ]; then
      _MIRROR_CHECK=NO
      if [ "${_OS_CODE}" = "deprecated" ]; then
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
          msg "INFO: Now looking for the best/fastest ${_OS_DIST} mirror"
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
        msg "INFO: We will use ${_OS_DIST} mirror ${_MIRROR}"
      fi
      cd /var/opt
      if [ "${_OS_CODE}" = "stretch" ] || [ "${_OS_CODE}" = "jessie" ]; then
        _APT_MIRROR="archive.debian.org/debian"
        _APT_REPSRC="${_OS_CODE}-backports"
        _SEC_MIRROR="archive.debian.org/debian-security"
        _SEC_REPSRC="${_OS_CODE}/updates"
      elif [ "${_OS_CODE}" = "buster" ]; then
        _APT_MIRROR="${_MIRROR}/debian"
        _APT_REPSRC="${_OS_CODE}-updates"
        _SEC_MIRROR="security.debian.org"
        _SEC_REPSRC="${_OS_CODE}/updates"
      elif [ "${_OS_CODE}" = "bullseye" ]; then
        _APT_MIRROR="${_MIRROR}/debian"
        _APT_REPSRC="${_OS_CODE}-updates"
        _SEC_MIRROR="security.debian.org/debian-security"
        _SEC_REPSRC="${_OS_CODE}-security"
      elif [ "${_OS_CODE}" = "bookworm" ]; then
        _APT_MIRROR="${_MIRROR}/debian"
        _APT_REPSRC="${_OS_CODE}-updates"
        _SEC_MIRROR="security.debian.org/debian-security"
        _SEC_REPSRC="${_OS_CODE}-security"
      fi
      echo "## DEBIAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_APT_MIRROR} ${_OS_CODE} main contrib non-free" >> ${aptLiSys}
      echo "deb-src http://${_APT_MIRROR} ${_OS_CODE} main contrib non-free" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
      echo "deb http://${_APT_MIRROR} ${_APT_REPSRC} main contrib non-free" >> ${aptLiSys}
      echo "deb-src http://${_APT_MIRROR} ${_APT_REPSRC} main contrib non-free" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## DEBIAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://${_SEC_MIRROR} ${_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_SEC_MIRROR} ${_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
    fi
    mkdir -p ${pthLog}
    touch ${pthLog}/apt-deb-src-updates-${_X_SE}.txt
    cd /var/opt
  fi
  ###--------------------###
  apt_clean_update
  ###--------------------###
}

#
# Install OpenSSH from sources.
sshd_install_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sshd_install_src"
  fi
  if [ "${_OS_CODE}" = "jessie" ]; then
    _OPENSSH_VRN=8.3p1
  fi
  if [ "${_OS_CODE}" = "stretch" ]; then
    _OPENSSH_VRN=9.3p1
  fi
  _SSH_GET_DPKG=$(dpkg --get-selections | grep openssh-sftp-server | grep 'hold$' 2>&1)
  _SSH_INSTALL_REQUIRED=NO
  _SSH_ITD=$(ssh -V 2>&1 \
    | tr -d "\n" \
    | tr -d "," \
    | cut -d"_" -f2 \
    | awk '{ print $1}' 2>&1)
  if [ -e "/root/.install.modern.openssl.cnf" ] \
    && [ -x "/usr/local/ssl3/bin/openssl" ]; then
    _SSL_BINARY=/usr/local/ssl3/bin/openssl
  else
    _SSL_BINARY=/usr/local/ssl/bin/openssl
  fi
  _SSL_ITD=$(${_SSL_BINARY} version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  _SSH_SSL_ITD=$(ssh -V 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f3 \
    | awk '{ print $1}' 2>&1)
  if [ -e "/usr/etc/sshd_config" ]; then
    _SSH_FORCE_REINSTALL=YES
    _OLD_SYSCONFDIR="/usr/etc"
    _SYSCONFDIR="/etc/ssh"
    _PREFIX_SSH="/usr/local"
    if [ -e "${_SYSCONFDIR}" ]; then
      cp -af ${_OLD_SYSCONFDIR}/* ${_SYSCONFDIR}/
    fi
  else
    _SYSCONFDIR="/etc/ssh"
    _PREFIX_SSH="/usr/local"
  fi
  if [[ "${_SSL_ITD}" =~ "${_OPENSSL_MODERN_VRN}" ]] \
    || [ -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
    _SSL_PATH="/usr/local/ssl3"
    _SSL_LIB_PATH="${_SSL_PATH}/lib64"
  else
    _SSL_PATH="/usr/local/ssl"
    _SSL_LIB_PATH="${_SSL_PATH}/lib"
  fi
  if [ "${_SSH_SSL_ITD}" != "${_SSL_ITD}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: OpenSSL in SSH is ${_SSH_SSL_ITD}, rebuild to ${_SSL_ITD} required"
    fi
    _SSH_INSTALL_REQUIRED=YES
  fi
  if [ "${_SSH_FORCE_REINSTALL}" = "YES" ]; then
    _SSH_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: OpenSSH ${_SSH_ITD}, rebuild forced"
    fi
  elif [ "${_SSH_ITD}" != "${_OPENSSH_VRN}" ]; then
    _SSH_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installed OpenSSH version ${_SSH_ITD}, upgrade required"
    fi
  fi
  if [ "${_SSH_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Building OpenSSH ${_OPENSSH_VRN} from sources..."
    msg "WAIT: This may take a while, please wait..."
    mrun "${_INITINS} libpam0g-dev libselinux1-dev" &> /dev/null
    if [ ! -e "/var/lib/sshd" ]; then
      mkdir -p /var/lib/sshd
      chmod -R 700 /var/lib/sshd/
      chown -R root:sys /var/lib/sshd/
      useradd -r -U -d /var/lib/sshd/ -c "sshd privsep" -s /bin/false sshd &> /dev/null
    fi
    _PKG_CONFIG_PATH="${_SSL_LIB_PATH}/pkgconfig"
    cd /var/opt
    rm -rf openssh*
    get_dev_src "openssh-${_OPENSSH_VRN}.tar.gz"
    cd /var/opt/openssh-${_OPENSSH_VRN}
    LIBS="-ldl -lpthread" PKG_CONFIG_PATH="${_PKG_CONFIG_PATH}" ./configure \
      --with-ssl-dir=${_SSL_PATH} \
      --with-privsep-path=/var/lib/sshd/ \
      --sysconfdir=${_SYSCONFDIR} \
      --prefix=${_PREFIX_SSH} \
      --without-openssl-header-check \
      --with-selinux \
      --with-md5-passwords \
      --with-pam &> /dev/null
    mrun "make -j $(nproc)" 2> /dev/null
    mrun "make install" 2> /dev/null
    ldconfig 2> /dev/null
    mrun "service ssh restart" 2> /dev/null
    if [[ ! "${_SSH_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold openssh-server &> /dev/null
      aptitude hold openssh-client &> /dev/null
      aptitude hold ssh &> /dev/null
      echo "openssh-client hold" | dpkg --set-selections &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections &> /dev/null
      echo "ssh hold" | dpkg --set-selections &> /dev/null
      echo "openssh-sftp-server hold" | dpkg --set-selections &> /dev/null
    fi
  else
    if [[ ! "${_SSH_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold openssh-server &> /dev/null
      aptitude hold openssh-client &> /dev/null
      aptitude hold ssh &> /dev/null
      echo "openssh-client hold" | dpkg --set-selections &> /dev/null
      echo "openssh-server hold" | dpkg --set-selections &> /dev/null
      echo "ssh hold" | dpkg --set-selections &> /dev/null
      echo "openssh-sftp-server hold" | dpkg --set-selections &> /dev/null
    fi
  fi
  if [ -x "/usr/local/sbin/sshd" ] \
    && [ -x "/usr/local/bin/ssh" ] \
    && [ ! -e "/usr/sbin/.sshd_bak" ]; then
    mv -f /usr/sbin/sshd /usr/sbin/.sshd_bak
    ln -sfn /usr/local/sbin/sshd /usr/sbin/sshd
    mv -f /usr/bin/ssh /usr/bin/.ssh_bak
    ln -sfn /usr/local/bin/ssh /usr/bin/ssh
    if [ -e "${_OLD_SYSCONFDIR}" ]; then
      cp -a ${_OLD_SYSCONFDIR} /var/backups/old_ssh_usr_etc
      rm -f ${_OLD_SYSCONFDIR}/ssh*
      rm -f ${_OLD_SYSCONFDIR}/moduli*
    fi
    mrun "service ssh restart" 2> /dev/null
  fi
  _SSH_FORCE_REINSTALL=NO
}

#
# Install ImageMagick from sources.
install_magick_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_magick_src"
  fi
  _MAGICK_SRC_BUILD_CTRL="${pthLog}/ImageMagick-src-build-${_IMAGE_MAGICK_VRN}.log"
  _MAGICK_INSTALL_REQUIRED=NO
  _MAGICK_ITD=$(convert --version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f3 \
    | awk '{ print $1}' 2>&1)
  if [ "${_MAGICK_ITD}" != "${_IMAGE_MAGICK_VRN}" ] \
    || [ ! -e "${_MAGICK_SRC_BUILD_CTRL}" ]; then
    if [ "${_OS_CODE}" = "none" ]; then
      _MAGICK_INSTALL_REQUIRED=NO
    else
      _MAGICK_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed ImageMagick version ${_MAGICK_ITD}, upgrade required"
      fi
    fi
  fi
  if [ "${_MAGICK_INSTALL_REQUIRED}" = "YES" ]; then
    msg "INFO: Installing ImageMagick ${_IMAGE_MAGICK_VRN}..."
    msg "WAIT: This may take a while, please wait..."
    cd /var/opt
    rm -rf ImageMagick*
    get_dev_src "ImageMagick-${_IMAGE_MAGICK_VRN}.tar.gz"
    cd /var/opt/ImageMagick-${_IMAGE_MAGICK_VRN}
    mrun "bash ./configure --prefix=/usr" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    if [ ! -e "/etc/.ImageMagick-6" ] \
      && [ -e "/etc/ImageMagick-6" ]; then
        cp -a /etc/ImageMagick-6 /etc/.ImageMagick-6
    fi
    if [ ! -e "/etc/.ImageMagick" ] \
      && [ -e "/etc/ImageMagick" ]; then
        cp -a /etc/ImageMagick /etc/.ImageMagick
    fi
    mrun "apt-get remove imagemagick -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove libmagickwand-dev -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove graphviz -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove libgraphviz-dev -y --purge --auto-remove -qq" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "HINT: Please modify /usr/etc/ImageMagick-7/policy.xml file, if needed"
    fi
    touch ${_MAGICK_SRC_BUILD_CTRL}
  fi
}

#
# Fix symlinks for libs.
ssl_crypto_lib_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: ssl_crypto_lib_fix"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Fix for SSL libssl/libcrypto in ${_OS_DIST}/${_OS_CODE}"
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
    _SSL_INSTALLED=MODERN
  elif [[ "${_SSL_ITD}" =~ "1.1.1" ]]; then
    _SSL_INSTALLED=EOL
  else
    _SSL_INSTALLED=LEGACY
  fi
  if [ "${_SSL_INSTALLED}" = "LEGACY" ]; then
    ###
    _LIB_NOW=$(date +%y%m%d-%H%M 2>&1)
    _LIB_NOW=${_LIB_NOW//[^0-9-]/}
    ###
    if [ -f "/usr/local/ssl/lib/libssl.so.1.0.0" ] \
      && [ -f "/usr/local/ssl/lib/libcrypto.so.1.0.0" ] \
      && [ -f "/usr/local/ssl/lib/libssl.a" ] \
      && [ -f "/usr/local/ssl/lib/libcrypto.a" ]; then
      ###
      _SSL_LIB_PATH="/usr/local/ssl/lib"
      _SSL_CNF_PATH="/usr/local/ssl/include/openssl"
      _GNU_LIB_PATH="/usr/lib/x86_64-linux-gnu"
      _GNU_CNF_PATH="/usr/include/x86_64-linux-gnu/openssl"
      ###
      rm -f /usr/lib/libcrypto.a
      rm -f /usr/lib/libcrypto.so
      rm -f /usr/lib/libcrypto.so.1.0.0
      rm -f /usr/lib/libssl.a
      rm -f /usr/lib/libssl.so
      rm -f /usr/lib/libssl.so.1.0.0
      rm -f ${_GNU_LIB_PATH}/libcrypto.a
      rm -f ${_GNU_LIB_PATH}/libcrypto.so
      rm -f ${_GNU_LIB_PATH}/libcrypto.so.1.0.0
      rm -f ${_GNU_LIB_PATH}/libssl.a
      rm -f ${_GNU_LIB_PATH}/libssl.so
      rm -f ${_GNU_LIB_PATH}/libssl.so.1.0.0
      ###
      rm -f ${_GNU_LIB_PATH}/libssl3.so
      rm -f ${_SSL_LIB_PATH}/libcrypto.so.1.1*
      rm -f ${_SSL_LIB_PATH}/libssl.so.1.1*
      ###
      ln -sfn ${_SSL_LIB_PATH}/libssl.a /usr/lib/libssl.a
      ln -sfn ${_SSL_LIB_PATH}/libssl.a ${_GNU_LIB_PATH}/libssl.a
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.0.0 /usr/lib/libssl.so
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.0.0 /usr/lib/libssl.so.1.0.0
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.0.0 ${_GNU_LIB_PATH}/libssl.so
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.0.0 ${_GNU_LIB_PATH}/libssl.so.1.0.0
      ###
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.a /usr/lib/libcrypto.a
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.a ${_GNU_LIB_PATH}/libcrypto.a
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.0.0 /usr/lib/libcrypto.so
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.0.0 /usr/lib/libcrypto.so.1.0.0
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.0.0 ${_GNU_LIB_PATH}/libcrypto.so
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.0.0 ${_GNU_LIB_PATH}/libcrypto.so.1.0.0
      ###
      if [ -e "${_SSL_CNF_PATH}/opensslconf.h" ]; then
        if [ -e "${_GNU_CNF_PATH}/opensslconf.h" ]; then
          rm -f /var/backups/old-opensslconf-h*
          mv -f ${_GNU_CNF_PATH}/opensslconf.h /var/backups/old-opensslconf-h-${_LIB_NOW}
        fi
        ln -sfn ${_SSL_CNF_PATH}/opensslconf.h ${_GNU_CNF_PATH}/opensslconf.h
      fi
      ###
      if [ -e "/usr/include/openssl" ] \
        && [ -d "/usr/local/ssl/include/openssl" ]; then
        rm -rf /var/backups/old-usr-include-openssl*
        mv -f /usr/include/openssl /var/backups/old-usr-include-openssl-${_LIB_NOW}
        ln -sfn /usr/local/ssl/include/openssl /usr/include/openssl
      fi
    fi
  elif [ "${_SSL_INSTALLED}" = "EOL" ]; then
    ###
    _LIB_NOW=$(date +%y%m%d-%H%M 2>&1)
    _LIB_NOW=${_LIB_NOW//[^0-9-]/}
    ###
    if [ -f "/usr/local/ssl/lib/libssl.so.1.1" ] \
      && [ -f "/usr/local/ssl/lib/libcrypto.so.1.1" ] \
      && [ -f "/usr/local/ssl/lib/libssl.a" ] \
      && [ -f "/usr/local/ssl/lib/libcrypto.a" ]; then
      ###
      _SSL_LIB_PATH="/usr/local/ssl/lib"
      _SSL_CNF_PATH="/usr/local/ssl/include/openssl"
      _GNU_LIB_PATH="/usr/lib/x86_64-linux-gnu"
      _GNU_CNF_PATH="/usr/include/x86_64-linux-gnu/openssl"
      ###
      rm -f /usr/lib/libcrypto.a
      rm -f /usr/lib/libcrypto.so
      rm -f /usr/lib/libcrypto.so.1.1
      rm -f /usr/lib/libssl.a
      rm -f /usr/lib/libssl.so
      rm -f /usr/lib/libssl.so.1.1
      rm -f ${_GNU_LIB_PATH}/libcrypto.a
      rm -f ${_GNU_LIB_PATH}/libcrypto.so
      rm -f ${_GNU_LIB_PATH}/libcrypto.so.1.1
      rm -f ${_GNU_LIB_PATH}/libssl.a
      rm -f ${_GNU_LIB_PATH}/libssl.so
      rm -f ${_GNU_LIB_PATH}/libssl.so.1.1
      ###
      rm -f ${_GNU_LIB_PATH}/libssl3.so
      rm -f ${_SSL_LIB_PATH}/libcrypto.so.1.0.0*
      rm -f ${_SSL_LIB_PATH}/libssl.so.1.0.0*
      ###
      ln -sfn ${_SSL_LIB_PATH}/libssl.a /usr/lib/libssl.a
      ln -sfn ${_SSL_LIB_PATH}/libssl.a ${_GNU_LIB_PATH}/libssl.a
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.1 /usr/lib/libssl.so
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.1 /usr/lib/libssl.so.1.1
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.1 ${_GNU_LIB_PATH}/libssl.so
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.1.1 ${_GNU_LIB_PATH}/libssl.so.1.1
      ###
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.a /usr/lib/libcrypto.a
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.a ${_GNU_LIB_PATH}/libcrypto.a
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.1 /usr/lib/libcrypto.so
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.1 /usr/lib/libcrypto.so.1.1
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.1 ${_GNU_LIB_PATH}/libcrypto.so
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.1.1 ${_GNU_LIB_PATH}/libcrypto.so.1.1
      ###
      if [ -e "${_SSL_CNF_PATH}/opensslconf.h" ]; then
        if [ -e "${_GNU_CNF_PATH}/opensslconf.h" ]; then
          rm -f /var/backups/old-opensslconf-h*
          mv -f ${_GNU_CNF_PATH}/opensslconf.h /var/backups/old-opensslconf-h-${_LIB_NOW}
        fi
        ln -sfn ${_SSL_CNF_PATH}/opensslconf.h ${_GNU_CNF_PATH}/opensslconf.h
      fi
      ###
      if [ -e "/usr/include/openssl" ] \
        && [ -d "/usr/local/ssl/include/openssl" ]; then
        rm -rf /var/backups/old-usr-include-openssl*
        mv -f /usr/include/openssl /var/backups/old-usr-include-openssl-${_LIB_NOW}
        ln -sfn /usr/local/ssl/include/openssl /usr/include/openssl
      fi
    fi
  elif [ "${_SSL_INSTALLED}" = "MODERN" ]; then
    ###
    _LIB_NOW=$(date +%y%m%d-%H%M 2>&1)
    _LIB_NOW=${_LIB_NOW//[^0-9-]/}
    ###
    if [ -f "/usr/local/ssl/lib/libssl.so.1.1" ] \
      && [ -f "/usr/local/ssl/lib/libcrypto.so.1.1" ] \
      && [ -f "/usr/local/ssl/lib/libssl.a" ] \
      && [ -f "/usr/local/ssl/lib/libcrypto.a" ]; then
      ###
      _SSL_LIB_PATH="/usr/local/ssl3/lib64"
      _SSL_CNF_PATH="/usr/local/ssl3/include/openssl"
      _GNU_LIB_PATH="/usr/lib/x86_64-linux-gnu"
      _GNU_CNF_PATH="/usr/include/x86_64-linux-gnu/openssl"
      ###
      rm -f /usr/lib/libcrypto.a
      rm -f /usr/lib/libcrypto.so
      rm -f /usr/lib/libcrypto.so.3
      rm -f /usr/lib/libssl.a
      rm -f /usr/lib/libssl.so
      rm -f /usr/lib/libssl.so.3
      rm -f ${_GNU_LIB_PATH}/libcrypto.a
      rm -f ${_GNU_LIB_PATH}/libcrypto.so
      rm -f ${_GNU_LIB_PATH}/libcrypto.so.3
      rm -f ${_GNU_LIB_PATH}/libssl.a
      rm -f ${_GNU_LIB_PATH}/libssl.so
      rm -f ${_GNU_LIB_PATH}/libssl.so.3
      ###
      ln -sfn ${_SSL_LIB_PATH}/libssl.a /usr/lib/libssl.a
      ln -sfn ${_SSL_LIB_PATH}/libssl.a ${_GNU_LIB_PATH}/libssl.a
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.3 /usr/lib/libssl.so
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.3 /usr/lib/libssl.so.3
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.3 ${_GNU_LIB_PATH}/libssl.so
      ln -sfn ${_SSL_LIB_PATH}/libssl.so.3 ${_GNU_LIB_PATH}/libssl.so.3
      ###
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.a /usr/lib/libcrypto.a
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.a ${_GNU_LIB_PATH}/libcrypto.a
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.3 /usr/lib/libcrypto.so
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.3 /usr/lib/libcrypto.so.3
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.3 ${_GNU_LIB_PATH}/libcrypto.so
      ln -sfn ${_SSL_LIB_PATH}/libcrypto.so.3 ${_GNU_LIB_PATH}/libcrypto.so.3
      ###
      if [ -e "${_SSL_CNF_PATH}/opensslconf.h" ]; then
        if [ -e "${_GNU_CNF_PATH}/opensslconf.h" ]; then
          rm -f /var/backups/old-opensslconf-h*
          mv -f ${_GNU_CNF_PATH}/opensslconf.h /var/backups/old-opensslconf-h-${_LIB_NOW}
        fi
        ln -sfn ${_SSL_CNF_PATH}/opensslconf.h ${_GNU_CNF_PATH}/opensslconf.h
      fi
      ###
      if [ -e "/usr/include/openssl" ] \
        && [ -d "/usr/local/ssl3/include/openssl" ]; then
        rm -rf /var/backups/old-usr-include-openssl*
        mv -f /usr/include/openssl /var/backups/old-usr-include-openssl-${_LIB_NOW}
        ln -sfn /usr/local/ssl3/include/openssl /usr/include/openssl
      fi
    fi
  fi
  ldconfig 2> /dev/null
}

#
# Install OpenSSL from sources.
ssl_install_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: ssl_install_src"
  fi
  _SSL_INSTALL_REQUIRED=NO
  if [ -e "/usr/bin/openssl" ] && [ ! -L "/usr/bin/openssl" ]; then
    if [ -x "/usr/local/ssl3/bin/openssl" ]; then
      ln -sf /usr/local/ssl3/bin/openssl /usr/bin/openssl
    elif [ -x "/usr/local/ssl/bin/openssl" ]; then
      ln -sf /usr/local/ssl/bin/openssl /usr/bin/openssl
    fi
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
    | awk '{ print $1}' 2>&1)
  if [ -e "/root/.install.modern.openssl.cnf" ]; then
    _SSL_LIB_ITD=$(openssl version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f8 \
      | awk '{ print $1}' 2>&1)
  else
    _SSL_LIB_ITD=$(openssl version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f9 \
      | awk '{ print $1}' 2>&1)
  fi
  if [ "${_OS_CODE}" = "daedalus" ] \
    || [ "${_OS_CODE}" = "chimaera" ] \
    || [ "${_OS_CODE}" = "beowulf" ] \
    || [ "${_OS_CODE}" = "bookworm" ] \
    || [ "${_OS_CODE}" = "bullseye" ] \
    || [ "${_OS_CODE}" = "buster" ]; then
    _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
    if [ -e "/root/.install.modern.openssl.cnf" ]; then
      chattr +i /root/.install.modern.openssl.cnf
      _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
    fi
  elif [ "${_OS_CODE}" = "stretch" ]; then
    if [ -e "/root/.install.modern.openssl.cnf" ]; then
      chattr -i /root/.install.modern.openssl.cnf
      rm -f /root/.install.modern.openssl.cnf
    fi
    _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
    if [ -x "/usr/local/ssl3/bin/openssl" ]; then
      mv -f /usr/local/ssl3 /usr/local/ssl3-off
    fi
  else
    if [ -e "/root/.install.modern.openssl.cnf" ]; then
      chattr -i /root/.install.modern.openssl.cnf
      rm -f /root/.install.modern.openssl.cnf
    fi
    _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
    if [ -x "/usr/local/ssl3/bin/openssl" ]; then
      mv -f /usr/local/ssl3 /usr/local/ssl3-off
    fi
  fi
  if [ -e "/root/.install.modern.openssl.cnf" ]; then
    _SSL_BINARY=/usr/local/ssl3/bin/openssl
    if [ ! -x "${_SSL_BINARY}" ]; then
      _SSL_INSTALL_REQUIRED=YES
    fi
  else
    _SSL_BINARY=/usr/local/ssl/bin/openssl
    if [ ! -x "${_SSL_BINARY}" ]; then
      _SSL_INSTALL_REQUIRED=YES
    fi
  fi
  if [ "${_SSL_ITD}" != "${_OPENSSL_NEW_VRN}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: OpenSSL is ${_SSL_ITD}, upgrade to ${_OPENSSL_NEW_VRN} required"
    fi
    _SSL_INSTALL_REQUIRED=YES
  fi
  if [ ! -z "${_SSL_LIB_ITD}" ] && [ "${_SSL_LIB_ITD}" != "${_OPENSSL_NEW_VRN}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: OpenSSL Lib is ${_SSL_LIB_ITD}, upgrade to ${_OPENSSL_NEW_VRN} required"
    fi
    _SSL_INSTALL_REQUIRED=YES
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    if [ "${_RUNNING_MAJOR_OS_UPGRADE}" = "NO" ]; then
      _PHP_COMPATIBILITY_TEST=$(php -i | grep "SSL Version" 2>&1)
      _PHP_SSL_LOOK_FOR="${_OPENSSL_NEW_VRN}"
      _PHP_SSL_ALTER_LOOK_FOR="GnuTLS"
      _PHP_SSL_ALTER_MORE_LOOK_FOR="${_OPENSSL_MODERN_VRN}"
      if [[ "${_PHP_COMPATIBILITY_TEST}" =~ "${_PHP_SSL_LOOK_FOR}" ]] \
        || [[ "${_PHP_COMPATIBILITY_TEST}" =~ "${_PHP_SSL_ALTER_LOOK_FOR}" ]] \
        || [[ "${_PHP_COMPATIBILITY_TEST}" =~ "${_PHP_SSL_ALTER_MORE_LOOK_FOR}" ]]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: PHP ${_PHP_COMPATIBILITY_TEST}, looks OK"
        fi
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: PHP ${_PHP_COMPATIBILITY_TEST}, rebuild forced later"
        fi
        _PHP_FORCE_REINSTALL=YES
      fi
    fi
    _SPDY_COMPATIBILITY_TEST=$(service nginx configtest 2>&1)
    if [[ "${_SPDY_COMPATIBILITY_TEST}" =~ "without OpenSSL ALPN or NPN" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: OpenSSL is ${_SSL_ITD}, rebuild for Nginx forced"
      fi
      _SSL_INSTALL_REQUIRED=YES
      _NGX_FORCE_REINSTALL=YES
    fi
  fi
  if [ "${_OPENSSL_NEW_VRN}" = "${_OPENSSL_LEGACY_VRN}" ]; then
    _BROKEN_SSL_LIBS_TEST=$(php -v 2>&1)
    if [[ "${_BROKEN_SSL_LIBS_TEST}" =~ "no version information available" ]] \
      || [[ "${_BROKEN_SSL_LIBS_TEST}" =~ "cannot open shared object file" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: OpenSSL legacy libs are broken, reinstall forced"
      fi
      mrun "apt-get install openssl --reinstall -y" 2> /dev/null
      _SSL_FORCE_REINSTALL=YES
    fi
  fi
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_SSL_FORCE_REINSTALL}" = "YES" ]; then
    _SSL_INSTALL_REQUIRED=YES
    _SSH_FORCE_REINSTALL=YES
    _NGX_FORCE_REINSTALL=YES
    _PHP_FORCE_REINSTALL=YES
    rm -f ${pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_X_SE}-${_X_VERSION}.log
    rm -f ${pthLog}/mss-build-${_MSS_VRN}-${_X_SE}-${_X_VERSION}.log
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installed OpenSSL version ${_SSL_ITD}, rebuild forced"
    fi
  fi
  if [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    ###--------------------###
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Building zlib ${_ZLIB_VRN} from sources first..."
    fi
    cd /var/opt
    rm -rf zlib*
    get_dev_src "zlib-${_ZLIB_VRN}.tar.gz"
    cd /var/opt/zlib-${_ZLIB_VRN}
    st_runner "bash ./configure --prefix=/usr" 2> /dev/null
    mrun "make -j $(nproc) --quiet" 2> /dev/null
    mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    ###--------------------###
    msg "INFO: Building OpenSSL ${_OPENSSL_NEW_VRN} from sources..."
    msg "WAIT: This may take a while, please wait..."
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
      if [ -e "/root/.install.modern.openssl.cnf" ]; then
        _SSL_BUILD_ARGS="--prefix=/usr/local/ssl3 \
          --openssldir=/usr/local/ssl3"
        patchMakefile=YES
      else
        _SSL_BUILD_ARGS="--prefix=/usr/local/ssl \
          --openssldir=/usr/local/ssl"
        patchMakefile=YES
      fi
      mrun "sh ./config \
        shared \
        no-comp \
        no-hw \
        no-ssl3 \
        zlib-dynamic \
        enable-ec_nistp_64_gcc_128 \
        ${_SSL_BUILD_ARGS}" 2> /dev/null
      if [ "${patchMakefile}" = "YES" ]; then
        sed -i "s/install_docs:.*/install_docs:/g" /var/opt/openssl-${_OPENSSL_NEW_VRN}/Makefile
      fi
      mrun "make depend" 2> /dev/null
      mrun "make -j $(nproc)" 2> /dev/null
      mrun "make install" 2> /dev/null
    fi
    if [ -x "${_SSL_BINARY}" ]; then
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
      if [ -e "/usr/bin/openssl" ]; then
        cp -af /usr/bin/openssl /usr/bin/old-openssl-$(date +%y%m%d-%H%M%S 2>&1)
      fi
      ln -sfn ${_SSL_BINARY} /usr/bin/openssl
      if [ -e "/bin/openssl" ] && [ ! -L "/bin" ]; then
        cp -af /bin/openssl /bin/old-openssl-$(date +%y%m%d-%H%M%S 2>&1)
        ln -sfn ${_SSL_BINARY} /bin/openssl
      fi
      sed -i "s/.*ssl.*//g" /etc/ld.so.conf.d/libc.conf
      echo "${_SSL_LIB_PATH}" >> /etc/ld.so.conf.d/libc.conf
      _LEGACY_SSL_LIB_PATH="/usr/local/ssl/lib"
      if [ -e "${_LEGACY_SSL_LIB_PATH}" ] \
        && [ "${_LEGACY_SSL_LIB_PATH}" != "${_SSL_LIB_PATH}" ]; then
        echo "${_LEGACY_SSL_LIB_PATH}" >> /etc/ld.so.conf.d/libc.conf
      fi
      sed -i "/^$/d" /etc/ld.so.conf.d/libc.conf &> /dev/null
      ldconfig 2> /dev/null
      ###--------------------###
      _SSL_GET_DPKG=$(dpkg --get-selections \
        | grep openssl \
        | grep 'hold$' 2>&1)
      _ZLB_GET_DPKG=$(dpkg --get-selections \
        | grep zlib \
        | grep 'hold$' 2>&1)
      if [[ ! "${_SSL_GET_DPKG}" =~ "hold" ]]; then
        echo "openssl hold" | dpkg --set-selections &> /dev/null
      fi
      if [[ ! "${_ZLB_GET_DPKG}" =~ "hold" ]]; then
        echo "zlib1g hold" | dpkg --set-selections &> /dev/null
        echo "zlib1g-dev hold" | dpkg --set-selections &> /dev/null
      fi
    else
      msg "OOPS: OpenSSL version ${_OPENSSL_NEW_VRN} was not installed!"
      _SSL_INSTALL_REQUIRED=
      _SSH_FORCE_REINSTALL=
      _NGX_FORCE_REINSTALL=
      _PHP_FORCE_REINSTALL=
      _GIT_FORCE_REINSTALL=
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: OpenSSL version detected ${_SSL_ITD}, OK"
    fi
  fi
  if [ ! -e "/opt/php73/bin/php" ] \
    && [ ! -e "/opt/php72/bin/php" ] \
    && [ ! -e "/opt/php71/bin/php" ] \
    && [ ! -e "/opt/php70/bin/php" ] \
    && [ ! -e "/opt/php56/bin/php" ] \
    && [ -x "/usr/local/ssl3/bin/openssl" ] \
    && [ -x "/usr/local/ssl/bin/openssl" ]; then
    ldconfig 2> /dev/null
  fi
}

#
# Install cURL from sources.
curl_install_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: curl_install_src"
  fi
  if [ "${_OS_CODE}" = "precise" ] || [ "${_OS_CODE}" = "jessie" ]; then
    #touch /root/.use.curl.from.packages.cnf
    #chattr +i /root/.use.curl.from.packages.cnf
    _CURL_VRN=8.8.0
  fi
  if [ ! -e "/root/.use.curl.from.packages.cnf" ]; then
    if [ "${_OS_CODE}" = "daedalus" ] \
      || [ "${_OS_CODE}" = "chimaera" ] \
      || [ "${_OS_CODE}" = "beowulf" ] \
      || [ "${_OS_CODE}" = "bookworm" ] \
      || [ "${_OS_CODE}" = "bullseye" ] \
      || [ "${_OS_CODE}" = "buster" ]; then
      _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
      if [ -e "/root/.install.modern.openssl.cnf" ]; then
        _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
      fi
    elif [ "${_OS_CODE}" = "stretch" ]; then
      if [ -e "/root/.install.modern.openssl.cnf" ]; then
        chattr -i /root/.install.modern.openssl.cnf
        rm -f /root/.install.modern.openssl.cnf
      fi
      _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
    else
      if [ -e "/root/.install.modern.openssl.cnf" ]; then
        chattr -i /root/.install.modern.openssl.cnf
        rm -f /root/.install.modern.openssl.cnf
      fi
      _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
    fi
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
    _CURL_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installed cURL/lib ${_CURL_ITD}/${_CURL_LIB_ITD}, upgrade required"
    fi
  fi
  if [ "${_CURL_LIB_ITD}" != "${_CURL_VRN}" ]; then
    _CURL_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installed cURL/lib ${_CURL_ITD}/${_CURL_LIB_ITD}, rebuild required"
    fi
  fi
  if [ "${_CURL_SSL_ITD}" != "${_OPENSSL_NEW_VRN}" ]; then
    _CURL_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: cURL ${_CURL_ITD} with OpenSSL ${_CURL_SSL_ITD}, rebuild forced"
    fi
  fi
  _BROKEN_CURL_TEST=$(curl --version 2>&1)
  if [[ "${_BROKEN_CURL_TEST}" =~ "libcurl.so.4" ]]; then
    _CURL_INSTALL_REQUIRED=YES
    touch /root/.use.curl.from.packages.cnf
    chattr +i /root/.use.curl.from.packages.cnf
    sed -i "s/.*ssl.*//g" /etc/ld.so.conf.d/libc.conf
    sed -i "/^$/d" /etc/ld.so.conf.d/libc.conf &> /dev/null
    grep lib /etc/ld.so.conf.d/libc.conf
    ldconfig 2> /dev/null
    [ -e "/root/.sorted.multi.php.cnf" ] && rm -f /root/.sorted.multi.php.cnf
    msg "INFO: libcurl is broken, cURL re-install from packages required"
  fi
  if [ "${_PHP_BIN_BROKEN}" = "YES" ] && [ -z "${_CURL_ALREADY_REBUILT}" ]; then
    _CURL_INSTALL_REQUIRED=YES
  fi
  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _CURL_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installed cURL version ${_CURL_ITD} but re-install forced"
    fi
  fi
  if [ -e "/usr/lib/x86_64-linux-gnu/libcurl.so.4.4.0" ] \
    || [ ! -L "/usr/lib/x86_64-linux-gnu/libcurl.so.4" ] \
    || [ ! -L "/usr/lib/libcurl.so.4" ]; then
    _CURL_INSTALL_REQUIRED=YES
  fi
  if [ -e "/usr/lib/x86_64-linux-gnu/libcurl.so.4.3.0" ] \
    || [ ! -L "/usr/lib/x86_64-linux-gnu/libcurl.so.4" ] \
    || [ ! -L "/usr/lib/libcurl.so.4" ]; then
    _CURL_INSTALL_REQUIRED=YES
  fi
  if [ "${_CURL_INSTALL_REQUIRED}" = "YES" ]; then
    ###--------------------###
    if [ -e "/root/.use.curl.from.packages.cnf" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: cURL from packages is forced with /root/.use.curl.from.packages.cnf"
      fi
      [ -e "/root/.sorted.multi.php.cnf" ] && rm -f /root/.sorted.multi.php.cnf
      if [ -e "/usr/local/bin/curl" ]; then
        mv -f /usr/local/bin/curl /usr/local/bin/curl-src-off-$(date +%y%m%d-%H%M%S 2>&1)
      fi
      if [[ "${_CURL_GET_DPKG}" =~ "hold" ]]; then
        echo "curl install" | dpkg --set-selections &> /dev/null
        if [ -z "${_CURL_ALREADY_REBUILT}" ]; then
          apt_clean_update
          mrun "${_INSTAPP} curl" 2> /dev/null
          mrun "apt-get build-dep curl -y" 2> /dev/null
          mrun "apt-get remove libssl1.0-dev -y --purge --auto-remove -qq" 2> /dev/null
          mrun "apt-get autoremove -y" 2> /dev/null
          mrun "${_INSTAPP} libssl-dev" 2> /dev/null
          mrun "${_INSTAPP} libc-client2007e libc-client2007e-dev" 2> /dev/null
        fi
      fi
    else
      apt_clean_update
      mrun "apt-get build-dep curl -y" 2> /dev/null
      mrun "apt-get remove libssl1.0-dev -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get autoremove -y" 2> /dev/null
      mrun "${_INSTAPP} libssl-dev" 2> /dev/null
      mrun "${_INSTAPP} libc-client2007e libc-client2007e-dev" 2> /dev/null
      cd /var/opt
      rm -rf curl*
      wget -q -U iCab ${urlDev}/src/curl-${_CURL_VRN}.tar.gz
      if [ ! -e "curl-${_CURL_VRN}.tar.gz" ]; then
        msg "OOPS: failed download from ${urlDev}/src/curl-${_CURL_VRN}.tar.gz"
      else
        extract_archive "curl-${_CURL_VRN}.tar.gz"
      fi
      if [ -e "/var/opt/curl-${_CURL_VRN}" ]; then
        msg "INFO: Building cURL ${_CURL_VRN} from sources..."
        msg "WAIT: This may take a while, please wait..."
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
        _PKG_CONFIG_PATH="${_SSL_LIB_PATH}/pkgconfig"
        if [ -e "${_PKG_CONFIG_PATH}" ]; then
          cd /var/opt/curl-${_CURL_VRN}
          LIBS="-ldl -lpthread" PKG_CONFIG_PATH="${_PKG_CONFIG_PATH}" ./configure \
            --with-openssl \
            --with-zlib=/usr \
            --prefix=/usr/local &> /dev/null
          mrun "make -j $(nproc)" 2> /dev/null
          mrun "make install" 2> /dev/null
          ldconfig 2> /dev/null
          if [ -x "/usr/local/bin/curl" ]; then
            mv -f /usr/bin/curl /usr/bin/old-curl-$(date +%y%m%d-%H%M%S 2>&1)
            ln -sfn /usr/local/bin/curl /usr/bin/curl
          fi
          if [ ! -e "${_SSL_PATH}/certs/ca-certificates.crt" ]; then
            cp -af /etc/ssl/certs/* ${_SSL_PATH}/certs/ &> /dev/null
          fi
          echo "curl hold" | dpkg --set-selections &> /dev/null
        else
          msg "OOPS: Building OpenSSL ${_OPENSSL_NEW_VRN} from sources failed!"
        fi
      else
        msg "OOPS: cURL ${_CURL_VRN} could not be extracted..."
      fi
      if [ -x "/usr/local/bin/curl" ] \
        && [ -e "/usr/local/lib/libcurl.so" ] \
        && [ -e "/usr/local/include/curl/header.h" ] \
        && [ ! -e "/var/xdrago/log/.curl_libs_fix_${_CURL_VRN}-${_X_VERSION}-${_NOW}.pid" ]; then
        _X86_64_TEST=$(uname -m 2>&1)
        if [ "${_X86_64_TEST}" = "x86_64" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Updating cURL ${_CURL_VRN} libs symlinks..."
          fi
          mkdir -p /var/backups/legacy-curl-pre-${_CURL_VRN}-${_X_VERSION}-${_NOW}
          mv -f /usr/lib/x86_64-linux-gnu/libcurl.so* /var/backups/legacy-curl-pre-${_CURL_VRN}-${_X_VERSION}-${_NOW}/ &> /dev/null
          mv -f /usr/lib/x86_64-linux-gnu/libcurl.la /var/backups/legacy-curl-pre-${_CURL_VRN}-${_X_VERSION}-${_NOW}/ &> /dev/null
          mv -f /usr/lib/x86_64-linux-gnu/libcurl.a /var/backups/legacy-curl-pre-${_CURL_VRN}-${_X_VERSION}-${_NOW}/ &> /dev/null
          if [ -e "/usr/include/x86_64-linux-gnu/curl" ] \
            && [ ! -L "/usr/include/x86_64-linux-gnu/curl" ]; then
            mv -f /usr/include/x86_64-linux-gnu/curl /var/backups/legacy-curl-pre-${_CURL_VRN}-${_X_VERSION}-${_NOW}/
          fi
          if [ ! -L "/usr/include/x86_64-linux-gnu/curl" ]; then
            ln -sfn /usr/local/include/curl /usr/include/x86_64-linux-gnu/curl
          fi
          if [ -e "/usr/local/lib/libcurl.so.4.8.0" ]; then
            ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0
            ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/libcurl.so.4.8.0
          fi
          if [ -e "/usr/local/lib/libcurl.so" ]; then
            ln -sfn /usr/local/lib/libcurl.so /usr/lib/x86_64-linux-gnu/libcurl.so
            ln -sfn /usr/local/lib/libcurl.so /usr/lib/libcurl.so
          fi
          if [ -e "/usr/local/lib/libcurl.so.4" ]; then
            ln -sfn /usr/local/lib/libcurl.so.4 /usr/lib/x86_64-linux-gnu/libcurl.so.4
            ln -sfn /usr/local/lib/libcurl.so.4 /usr/lib/libcurl.so.4
          fi
          if [ -e "/usr/local/lib/libcurl.la" ]; then
            ln -sfn /usr/local/lib/libcurl.la /usr/lib/x86_64-linux-gnu/libcurl.la
            ln -sfn /usr/local/lib/libcurl.la /usr/lib/libcurl.la
          fi
          if [ -e "/usr/local/lib/libcurl.a" ]; then
            ln -sfn /usr/local/lib/libcurl.a /usr/lib/x86_64-linux-gnu/libcurl.a
            ln -sfn /usr/local/lib/libcurl.a /usr/lib/libcurl.a
          fi
        fi
        mrun "apt-get remove curl ${aptYesUnth}" 2> /dev/null
        ldconfig 2> /dev/null
        touch /var/xdrago/log/.curl_libs_fix_${_CURL_VRN}-${_X_VERSION}-${_NOW}.pid &> /dev/null
        _CURL_ALREADY_REBUILT=YES
      fi
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: cURL version detected ${_CURL_ITD}, OK"
    fi
  fi
}

#
# Symlink to dash.
symlink_to_dash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: symlink_to_dash"
  fi
  if [ -x "/usr/bin/dash" ] && [ ! -L "/usr/bin/dash" ]; then
    if [ -L "/usr/bin/sh" ]; then
      ln -sfn /usr/bin/dash /usr/bin/sh
    fi
    if [ -L "/bin/sh" ]; then
      ln -sfn /usr/bin/dash /bin/sh
    fi
  fi
  if [ -x "/bin/dash" ] && [ ! -L "/bin/dash" ]; then
    if [ -L "/usr/bin/sh" ]; then
      ln -sfn /bin/dash /usr/bin/sh
    fi
    if [ -L "/bin/sh" ]; then
      ln -sfn /bin/dash /bin/sh
    fi
  fi
}

#
# Symlink to bash.
symlink_to_bash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: symlink_to_bash"
  fi
  if [ -x "/usr/bin/bash" ] && [ ! -L "/usr/bin/bash" ]; then
    if [ -L "/usr/bin/sh" ]; then
      ln -sfn /usr/bin/bash /usr/bin/sh
    fi
    if [ -L "/bin/sh" ]; then
      ln -sfn /usr/bin/bash /bin/sh
    fi
  fi
  if [ -x "/bin/bash" ] && [ ! -L "/bin/bash" ]; then
    if [ -L "/usr/bin/sh" ]; then
      ln -sfn /bin/bash /usr/bin/sh
    fi
    if [ -L "/bin/sh" ]; then
      ln -sfn /bin/bash /bin/sh
    fi
  fi
}

#
# Switch to dash.
switch_to_dash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: switch_to_dash"
  fi
  if [ -x "/usr/bin/dash" ] && [ ! -e "/bin/dash" ]; then
    cp -a /usr/bin/dash /bin/
  fi
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
                  /etc/resolvconf/update.d \
                  /etc/webmin \
                  /opt/php56/bin \
                  /opt/php70/bin \
                  /opt/php71/bin \
                  /opt/php72/bin \
                  /opt/php73/bin \
                  /opt/php74/bin \
                  /opt/php80/bin \
                  /opt/php81/bin \
                  /opt/php82/bin \
                  /opt/php83/bin \
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
            || [[ "$f" =~ "dash"($) ]] \
            || [[ "$f" =~ "bash"($) ]] \
            || [[ "$f" =~ "ssh"($) ]] \
            || [[ "$f" =~ "sshd"($) ]] \
            || [[ "$f" =~ "websh"($) ]]; then
            _SKIP_THIS=YES
          else
            _SHELL_TEST=
            _SHELL_TEST=$(grep -I -o "\#\!.*/bin/sh" $f 2>&1)
            if [[ "${_SHELL_TEST}" =~ "/bin/sh" ]] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/\/bin\/sh/\/bin\/dash/g" $f &> /dev/null
              wait
            fi
            _SHELL_TEST=
            _SHELL_TEST=$(grep -I -o "\#\!.*/usr/bin/sh" $f 2>&1)
            if [[ "${_SHELL_TEST}" =~ "/bin/sh" ]] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: switch_to_bash"
  fi
  if [ -x "/usr/bin/bash" ] && [ ! -e "/bin/bash" ]; then
    cp -a /usr/bin/bash /bin/
  fi
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
                  /etc/resolvconf/update.d \
                  /etc/webmin \
                  /opt/php56/bin \
                  /opt/php70/bin \
                  /opt/php71/bin \
                  /opt/php72/bin \
                  /opt/php73/bin \
                  /opt/php74/bin \
                  /opt/php80/bin \
                  /opt/php81/bin \
                  /opt/php82/bin \
                  /opt/php83/bin \
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
            || [[ "$f" =~ "dash"($) ]] \
            || [[ "$f" =~ "bash"($) ]] \
            || [[ "$f" =~ "ssh"($) ]] \
            || [[ "$f" =~ "sshd"($) ]] \
            || [[ "$f" =~ "websh"($) ]]; then
            _SKIP_THIS=YES
          else
            _SHELL_TEST=
            _SHELL_TEST=$(grep -I -o "\#\!.*/bin/sh" $f 2>&1)
            if [[ "${_SHELL_TEST}" =~ "/bin/sh" ]] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
              sed -i "s/\/bin\/sh/\/bin\/bash/g" $f &> /dev/null
              wait
            fi
            _SHELL_TEST=
            _SHELL_TEST=$(grep -I -o "\#\!.*/usr/bin/sh" $f 2>&1)
            if [[ "${_SHELL_TEST}" =~ "/bin/sh" ]] \
              && [ "$f" != "/etc/init.d/clean-boa-env" ] \
              && [ "$f" != "/bin/websh" ]; then
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: strict_bin_permissions"
  fi

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
              /opt/php82/bin \
              /opt/php83/bin \
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
                  gem \
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
  chown root:root /etc/passwd*
  chmod 644 /etc/passwd*
  chown root:shadow /etc/shadow*
  chmod 640 /etc/shadow*
}

#
# Turn Off AppArmor temporarily.
turn_off_apparmor_temporarily() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: turn_off_apparmor_temporarily"
  fi
  isAppArmOn=N
  if [ -e "/sys/module/apparmor/parameters/enabled" ]; then
    isAppArmOn=$(cat /sys/module/apparmor/parameters/enabled 2>&1)
    isAppArmOn=$(echo -n ${isAppArmOn} | tr -d "\n" 2>&1)
  fi
  if [ "${isAppArmOn}" = "Y" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "ARMR: Turning off AppArmor temporarily..."
    fi
    rm -rf /var/cache/apparmor/*
    mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
    mrun "aa-complain /etc/apparmor.d/*" 2> /dev/null
    mrun "service apparmor stop" 2> /dev/null
    mrun "aa-teardown" 2> /dev/null
    mrun "service auditd stop" 2> /dev/null
  fi
}

#
# Enforce AppArmor profiles.
if_enforce_apparmor_profiles() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_enforce_apparmor_profiles"
  fi
  if [ "${isAppArmOn}" = "Y" ] || [ -d "/etc/apparmor.d" ]; then
    if [ -e "/root/.enforce.apparmor.cnf" ]; then
      _AA_TEST_A=$(aa-status | grep "profiles are loaded" 2>&1)
      _AA_TEST_B=$(aa-status | grep "0 processes are in complain mode" 2>&1)
      _AA_TEST_C=$(aa-status | grep "0 profiles are in unconfined mode" 2>&1)
      _AA_TEST_D=$(aa-status | grep "0 processes are unconfined" 2>&1)
      _AA_TEST_E=$(aa-status | grep "processes are unconfined but have a profile defined" 2>&1)
      if [ -z "${_AA_TEST_A}" ] \
        || [ -z "${_AA_TEST_B}" ] \
        || [ -z "${_AA_TEST_C}" ] \
        || [ -z "${_AA_TEST_D}" ] \
        || [ ! -z "${_AA_TEST_E}" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "ARMR: Restarting services to switch them to the enforced mode"
        fi
        mrun "bash /var/xdrago/move_sql.sh" 2> /dev/null
        wait
        mrun "service redis-server reload" 2> /dev/null
        mrun "killall unbound" 2> /dev/null
        mrun "killall pure-ftpd" 2> /dev/null
        mrun "service rsyslog restart" 2> /dev/null
      fi
    fi
  fi
}

#
# Sync AppArmor profiles.
sync_apparmor_profiles() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sync_apparmor_profiles"
  fi
  if [ "${isAppArmOn}" = "Y" ] || [ -d "/etc/apparmor.d" ]; then
    msg "ARMR: All profiles will be updated now..."
    if [ -d "/etc/apparmor.d" ]; then
      _backArmr="/var/backups/apparmor/"
      [ ! -e "${_backArmr}" ] && mkdir -p ${_backArmr}
      _profArmList="avahi \
                    cacher \
                    dnsmasq \
                    dovecot \
                    dpkg \
                    haveged \
                    identd \
                    irssi \
                    klogd \
                    lsb_release \
                    mdnsd \
                    modprobe \
                    nmbd \
                    nscd \
                    php-fpm \
                    pidgin \
                    samba \
                    scanner \
                    smb \
                    syslog \
                    tcpdump \
                    totem \
                    traceroute \
                    usr.sbin.sshd"
      for _profArm in ${_profArmList}; do
        mv -f /etc/apparmor.d/*${_profArm}* ${_backArmr} &> /dev/null
      done
      cp -af ${locCnf}/apparmor/* /etc/apparmor.d/
      if [ -d "/etc/apparmor.d/disable" ]; then
        cp -af /etc/apparmor.d/*ssh* /etc/apparmor.d/disable/ &> /dev/null
      fi
    fi
    if [ ! -e "/root/.run-to-daedalus.cnf" ] \
      && [ ! -e "/root/.run-to-chimaera.cnf" ] \
      && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
      msg "WAIT: This may take a while, please wait..."
    fi
    for proFile in `find /etc/apparmor.d/ -maxdepth 1 -mindepth 1 -type f | sort`; do
      profName=$(echo ${proFile} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
      if [ ! -z "${isAppArmorComplain}" ] \
        && [ -x "${isAppArmorComplain}" ]; then
        if [ ! -e "/root/.run-to-daedalus.cnf" ] \
          && [ ! -e "/root/.run-to-chimaera.cnf" ] \
          && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
          if [ "${isAppArmOn}" = "Y" ]; then
            mrun "apparmor_parser -Q /etc/apparmor.d/${profName}" 2> /dev/null
          fi
        fi
      fi
      chmod 644 ${proFile}
    done
    if [ -e "/etc/audit/auditd.conf" ]; then
      if [ -e "/root/.disable.auditd.logs.cnf" ]; then
        sed -i "s/^write_logs =.*/write_logs = no/g" /etc/audit/auditd.conf
      else
        sed -i "s/^write_logs =.*/write_logs = yes/g" /etc/audit/auditd.conf
      fi
      _AUDITD_CNF_LOC_TEST=$(grep "local_events" /etc/audit/auditd.conf 2>&1)
      if [[ ! "${_AUDITD_CNF_LOC_TEST}" =~ "local_events" ]]; then
        echo "local_events = yes" >> /etc/audit/auditd.conf
      fi
      _AUDITD_CNF_WRT_TEST=$(grep "write_logs" /etc/audit/auditd.conf 2>&1)
      if [[ ! "${_AUDITD_CNF_WRT_TEST}" =~ "write_logs" ]]; then
        echo "write_logs = yes" >> /etc/audit/auditd.conf
      fi
    fi
    if [ "${isAppArmOn}" = "Y" ]; then
      if [ -e "/root/.activate.apparmor.cnf" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "ARMR: Activating AppArmor in the complain mode"
        fi
        mrun "rm -rf /var/cache/apparmor/*" 2> /dev/null
        if [ -x "/etc/init.d/apparmor" ]; then
          mrun "service apparmor restart" 2> /dev/null
        fi
        if [ -x "/etc/init.d/auditd" ]; then
          mrun "service auditd restart" 2> /dev/null
        fi
        mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
        mrun "aa-complain /etc/apparmor.d/*" 2> /dev/null
      elif [ -e "/root/.enforce.apparmor.cnf" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "ARMR: Activating AppArmor in the enforced mode"
        fi
        mrun "rm -rf /var/cache/apparmor/*" 2> /dev/null
        if [ -x "/etc/init.d/apparmor" ]; then
          mrun "service apparmor restart" 2> /dev/null
        fi
        if [ -x "/etc/init.d/auditd" ]; then
          mrun "service auditd restart" 2> /dev/null
        fi
        mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
        mrun "aa-enforce /etc/apparmor.d/*" 2> /dev/null
        if_enforce_apparmor_profiles
      elif [ -e "/root/.disable.apparmor.cnf" ] \
        || [ ! -e "/root/.activate.apparmor.cnf" ] \
        || [ ! -e "/root/.enforce.apparmor.cnf" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "ARMR: Deactivating AppArmor using aa-teardown"
        fi
        mrun "rm -rf /var/cache/apparmor/*" 2> /dev/null
        mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
        mrun "aa-complain /etc/apparmor.d/*" 2> /dev/null
        if [ -x "/etc/init.d/apparmor" ]; then
          mrun "service apparmor stop" 2> /dev/null
          mrun "update-rc.d -f apparmor remove" 2> /dev/null
        fi
        if [ -x "/etc/init.d/auditd" ]; then
          mrun "service auditd stop" 2> /dev/null
          mrun "update-rc.d -f auditd remove" 2> /dev/null
        fi
        if [ -x "/usr/sbin/aa-teardown" ]; then
          mrun "aa-teardown" 2> /dev/null
        fi
      fi
    fi
  fi
}

#
# Manage AppArmor.
if_install_apparmor() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_apparmor"
  fi
  ###--------------------###
  isAppArmorRevFile="/sys/kernel/security/apparmor/revision"
  isAppArmorGrubFile="/etc/default/grub.d/apparmor.cfg"
  isAppArmorComplain=$(which aa-complain 2>&1)
  isAppArmorStatus=$(which aa-status 2>&1)
  isAppArmorGrub=NO
  if [ -e "${isAppArmorGrubFile}" ]; then
    _GRUB_APPARMOR_TEST=$(grep "apparmor=1 security=apparmor" ${isAppArmorGrubFile} 2>&1)
    if [[ "${_GRUB_APPARMOR_TEST}" =~ "apparmor=1 security=apparmor" ]]; then
      isAppArmorGrub=YES
    fi
  fi
  if [ ! -e "${isAppArmorRevFile}" ] \
    || [ ! -e "${isAppArmorGrubFile}" ] \
    || [ -z "${isAppArmorComplain}" ] \
    || [ -z "${isAppArmorStatus}" ] \
    || [ "${isAppArmorGrub}" = "NO" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "ARMR: The system AppArmor and auditd will be installed now, however..."
      msg "ARMR: ...it will become active only after you reboot this server"
      msg "ARMR: Use 'boa reboot' command for optimized reboot"
      msg "WAIT: This may take a while, please wait..."
    fi
    mrun "${_INSTAPP} auditd \
      apparmor \
      apparmor-utils \
      apparmor-notify \
      apparmor-profiles" 2> /dev/null
    mkdir -p /etc/default/grub.d
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=1 security=apparmor"' \
      | tee ${isAppArmorGrubFile} &> /dev/null
    update-grub &> /dev/null
  fi
  isAppArmOn=N
  if [ -e "/sys/module/apparmor/parameters/enabled" ]; then
    isAppArmOn=$(cat /sys/module/apparmor/parameters/enabled 2>&1)
    isAppArmOn=$(echo -n ${isAppArmOn} | tr -d "\n" 2>&1)
  fi
  if [ "${isAppArmOn}" = "Y" ]; then
    sync_apparmor_profiles
    [ -e "/root/.turn_off_apparmor_in_octopus.cnf" ] && rm -f /root/.turn_off_apparmor_in_octopus.cnf
  fi
}

#
# Final cleanup.
finale() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: finale"
  fi
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
  _KERNEL_UP=NO
  if [ -e "/run/reboot-required.pkgs" ]; then
    _T_KERNEL_TEST=$(grep linux /run/reboot-required.pkgs 2>&1)
    if [[ "${_T_KERNEL_TEST}" =~ "linux" ]]; then
      _KERNEL_UP=YES
    fi
  fi
  if [ "${_UP_LNX}" = "YES" ] || [ "${_KERNEL_UP}" = "YES" ]; then
    msg "NOTE: Your OS kernel has been upgraded"
    msg "NOTE: Please reboot this server to activate the new kernel"
    msg "NOTE: Use 'boa reboot' command for optimized reboot"
    echo " "
    mrun "sleep 8"
  fi
  msg "Final post-${_L_ST} cleaning, one moment..."
  barracuda_cnf_cleanup
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
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]]; then
    _MTD_VR="BOA-5.3.0-omm"
  elif [ -e "/root/.host8.cnf" ]; then
    _MTD_VR="BOA-5.3.0-aln"
  else
    _MTD_VR="${_X_VERSION}"
  fi
  mv -f /etc/motd ${vBs}/dragon/t/motd-pre-${_X_SE}-${_MTD_VR}-${_NOW} &> /dev/null
  mv -f /etc/motd-pre-* ${vBs}/dragon/t/ &> /dev/null
  echo > /etc/motd
  echo " Skynet Agent v.${_MTD_VR} on $(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)/$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1) \
    welcomes you aboard" | fmt -su -w 2500 >> /etc/motd
  echo >> /etc/motd
  echo > /etc/motd.tail
  echo " Skynet Agent v.${_MTD_VR} on $(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)/$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1) \
    welcomes you aboard" | fmt -su -w 2500 >> /etc/motd.tail
  echo >> /etc/motd.tail
  apt-get autoclean -y &> /dev/null
  apt-get clean -qq 2> /dev/null
  #rm -rf /var/lib/apt/lists/*
  mkdir -p /data/conf/arch
  mv -f /data/conf/global.inc-pre* /data/conf/arch/     &> /dev/null
  mv -f /data/conf/global/*inc-pre* /data/conf/arch/    &> /dev/null
  mv -f /data/conf/global.inc-before* /data/conf/arch/  &> /dev/null
  mv -f /data/conf/global.inc-missing* /data/conf/arch/ &> /dev/null
  rm -f /tmp/cache.inc*
  rm -f /var/opt/._zendopcache*
  rm -rf /var/opt/*
  rm -f /var/xdrago/monitor/acrashsql.sh
  rm -f /var/xdrago/acrashsql.sh
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]]; then
    _MY_USAGE=YES
  else
    _MY_USAGE=NO
    rm -f /var/xdrago/usage.sh
  fi
  rm -f /var/xdrago/memcache.sh*
  rm -f /var/xdrago/purge_cruft.sh
  rm -f /var/xdrago/*.old
  rm -rf /tmp/drush_make_tmp*
  rm -rf /tmp/make_tmp*
  rm -f /tmp/pm-updatecode*
  rm -rf /var/aegir/.tmp/cache
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
  [ -e "/run/manage_ltd_users.pid" ] && rm -f /run/manage_ltd_users.pid
  [ -e "/run/manage_ruby_users.pid" ] && rm -f /run/manage_ruby_users.pid
  [ -e "/var/aegir/.drush/.alias.drushrc.php" ] && rm -f /var/aegir/.drush/.alias.drushrc.php
  [ -d "/data/u" ] && rm -f /data/disk/*/.drush/.alias.drushrc.php
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
    && [ -e "${vBs}/buagent-pre-${_X_SE}-${_X_VERSION}-${_NOW}" ]; then
    mv -f ${vBs}/buagent-pre-${_X_SE}-${_X_VERSION}-${_NOW} \
      /etc/init.d/buagent &> /dev/null
  fi
  if [ -e "/etc/csf/csf.deny" ] \
    && [ -x "/usr/sbin/csf" ] \
    && [ -e "/var/xdrago/guest-fire.sh" ] \
    && [ -e "/var/xdrago/guest-water.sh" ]; then
    sed -i "s/.*fire.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "s/.*water.*//g" /etc/crontab &> /dev/null
    wait
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]]; then
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
    mrun "service clean-boa-env start" 2> /dev/null
  fi
  killall -9 memcached &> /dev/null
  php_deprecated_cleanup
  php_single_initd_cleanup
  if [ -e "/root/.skip-aegir-master-upgrade.cnf" ] \
    && [ -e "/root/.completed_post_major_os_upgrade.info" ] \
    && [ ! -e "/root/.run_post_major_os_upgrade.info" ]; then
    rm -f /root/.skip-aegir-master-upgrade.cnf
  fi
  echo "FINALE" > /root/.latest-barracuda-upgrade-finale.info
  if [ ! -e "/root/.upstart.cnf" ]; then
    mrun "service cron start" 2> /dev/null
  fi
  if [ -x "/usr/sbin/csf" ] \
    && [ -e "/etc/csf/csf.deny" ] \
    && [ ! -x "/etc/csf/csfpost.sh" ]; then
    echo "" > /etc/csf/csfpost.sh
    echo "iptables -t raw -A PREROUTING -p tcp --dport 21 -j CT --helper ftp" >> /etc/csf/csfpost.sh
    echo "iptables -t raw -A OUTPUT -p tcp --dport 21 -j CT --helper ftp" >> /etc/csf/csfpost.sh
    chmod 700 /etc/csf/csfpost.sh
    mrun "service lfd stop" 2> /dev/null
    wait
    kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
    killall sleep &> /dev/null
    rm -f /etc/csf/csf.error
    csf -x  &> /dev/null
    wait
    mrun "service clean-boa-env start" 2> /dev/null
    wait
    csf -uf &> /dev/null
    wait
    _NFTABLES_TEST=$(iptables -V 2>&1)
    if [[ "${_NFTABLES_TEST}" =~ "nf_tables" ]]; then
      if [ -e "/usr/sbin/iptables-legacy" ]; then
        update-alternatives --set iptables /usr/sbin/iptables-legacy &> /dev/null
      fi
      if [ -e "/usr/sbin/ip6tables-legacy" ]; then
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy &> /dev/null
      fi
      if [ -e "/usr/sbin/arptables-legacy" ]; then
        update-alternatives --set arptables /usr/sbin/arptables-legacy &> /dev/null
      fi
      if [ -e "/usr/sbin/ebtables-legacy" ]; then
        update-alternatives --set ebtables /usr/sbin/ebtables-legacy &> /dev/null
      fi
    fi
    csf -e  &> /dev/null
    wait
    sed -i "s/.*DHCP.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    if [ -e "/var/log/daemon.log" ]; then
      _DHCP_LOG="/var/log/daemon.log"
    else
      _DHCP_LOG="/var/log/syslog"
    fi
    _DHCP_TEST=$(grep DHCPREQUEST ${_DHCP_LOG} | cut -d ' ' -f13 | sort | uniq 2>&1)
    if [[ "${_DHCP_TEST}" =~ "port" ]]; then
      for _IP in `grep DHCPREQUEST ${_DHCP_LOG} | cut -d ' ' -f12 | sort | uniq`;do echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow;done
    else
      for _IP in `grep DHCPREQUEST ${_DHCP_LOG} | cut -d ' ' -f13 | sort | uniq`;do echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow;done
    fi
    csf -q  &> /dev/null
    mrun "service lfd start" 2> /dev/null
    wait
    ### Linux kernel TCP SACK CVEs mitigation
    ### CVE-2019-11477 SACK Panic
    ### CVE-2019-11478 SACK Slowness
    ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
    if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
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

run_aptitude_deps_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: run_aptitude_deps_install"
  fi
  if_to_do_fix
  if [ "${_OS_DIST}" = "Devuan" ]; then
    ${_INITINS} devuan-keyring &> /dev/null
  elif [ "${_OS_DIST}" = "Debian" ]; then
    ${_INITINS} debian-keyring debian-archive-keyring &> /dev/null
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing a large list of libraries and tools..."
  elif [ "${_STATUS}" = "UPGRADE" ]; then
    msg "INFO: Upgrading a large list of libraries and tools..."
  fi
  msg "WAIT: This may take a while, please wait..."
  apt_clean_update
  mrun "apt-get remove percona-xtrabackup-24 -y --purge --auto-remove -qq" 2> /dev/null
  mrun "apt-get remove libcurl4-gnutls-dev -y --purge --auto-remove -qq" 2> /dev/null
  mrun "apt-get remove polkitd -y --purge --auto-remove -qq" 2> /dev/null
  mrun "apt-get remove libcurl4-openssl-dev -y --purge --auto-remove -qq" 2> /dev/null
  mrun "apt-get autoremove -y" 2> /dev/null
  mrun "${_INSTAPP} build-essential libsasl2-modules" 2> /dev/null
  mrun "${_INSTAPP} time vim cvs makepasswd" 2> /dev/null
  mrun "${_INSTAPP} man-db dnsutils sudo symlinks iptables" 2> /dev/null
  mrun "${_INSTAPP} autoconf automake autotools-dev m4 bc" 2> /dev/null
  mrun "${_INSTAPP} curl" 2> /dev/null
  mrun "apt-get build-dep curl -y" 2> /dev/null
  mrun "apt-get remove libssl1.0-dev -y --purge --auto-remove -qq" 2> /dev/null
  mrun "${_INSTAPP} libssl-dev" 2> /dev/null
  mrun "${_INSTAPP} libc-client2007e libc-client2007e-dev" 2> /dev/null
  mrun "${_INSTAPP} mcrypt libc-client-dev" 2> /dev/null
  mrun "${_INSTAPP} apticron aptitude apt-listchanges" 2> /dev/null
  mrun "${_INSTAPP} sysstat telnet cron gnupg2 gnupg" 2> /dev/null
  mrun "${_INSTAPP} unzip unrtf wdiff pwgen flex re2c" 2> /dev/null
  mrun "${_INSTAPP} rsync strace ntpdate python-dev" 2> /dev/null
  mrun "${_INSTAPP} mc whois zlib1g zlib1g-dev librsync-dev" 2> /dev/null
  mrun "${_INSTAPP} sqlite3 libsqlite3-dev s4cmd" 2> /dev/null
  mrun "${_INSTAPP} ssh ssl-cert libpam-umask shtool" 2> /dev/null
  mrun "${_INSTAPP} xml-core xml2 xpdf libtool rrdtool" 2> /dev/null
  mrun "${_INSTAPP} ncurses-dev ncurses-term sipcalc" 2> /dev/null
  _OS_LIST="daedalus chimaera bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      mrun "${_INSTAPP} ncal" 2> /dev/null
    fi
  done
  mrun "${_INSTAPP} netcat libzip-dev libwww-perl libsodium-dev" 2> /dev/null
  mrun "${_INSTAPP} libfontconfig1 libfreetype6 libfreetype6-dev" 2> /dev/null
  mrun "${_INSTAPP} libfribidi0 libgeoip-dev libgeoip1 libgmp3-dev" 2> /dev/null
  mrun "${_INSTAPP} libonig-dev libpq5 libxml2-dev libxpm4" 2> /dev/null
  mrun "${_INSTAPP} libxslt-dev libxslt1-dev libxslt1.1 subversion" 2> /dev/null
  mrun "${_INSTAPP} libaprutil1 libapr1 ldap-utils ipset" 2> /dev/null
  mrun "${_INSTAPP} pdftk patchutils p7zip-full fontconfig-config" 2> /dev/null
  mrun "${_INSTAPP} bison catdoc cython3 geoip-database gettext" 2> /dev/null
  mrun "${_INSTAPP} clamav clamav-base clamav-daemon clamdscan" 2> /dev/null
  mrun "${_INSTAPP} ghostscript htop lemon lftp nano" 2> /dev/null
  mrun "${_INSTAPP} python3-dev python3-debian python3-magic" 2> /dev/null
  if [ -e "/root/.dont.use.fancy.bash.login.cnf" ] \
    && [ -e "/usr/bin/screenfetch" ]; then
    mrun "apt-get remove toilet -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove figlet -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove screenfetch -y --purge --auto-remove -qq" 2> /dev/null
  else
    mrun "${_INSTAPP} toilet figlet screenfetch" 2> /dev/null
  fi
  fix_postfix
  st_runner "${_INSTAPP} ${_MAILSERV}" 2> /dev/null
  st_runner "${_INSTAPP} ${_APT_XTRA}" 2> /dev/null
  st_runner "${_INSTAPP} ${_EXTRA_LIB_APT}" 2> /dev/null
  st_runner "${_INSTAPP} ${_EXTRA_PACKAGES}" 2> /dev/null
  st_runner "${_INSTAPP} ${_SYSLOGD}" 2> /dev/null
  _EXTRA_APT="tree"
  st_runner "apt-get install ${_EXTRA_APT} ${nrmUpArg}" 2> /dev/null
  if [ -e "/etc/init.d/php5-fpm" ]; then
    mrun "service php5-fpm stop" 2> /dev/null
    mrun "update-rc.d -f php5-fpm remove" 2> /dev/null
  fi
}

basic_packages_install_on_init() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: basic_packages_install_on_init"
  fi
  apt_clean_update
  if [ ! -e "/var/aegir/drush" ] && [ ! -e "/var/xdrago/manage_solr_config.sh" ]; then
    mrun "apt-get remove unscd -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove dbus -y --purge --auto-remove -qq" 2> /dev/null
    if [ -e "/usr/share/dbus-1" ]; then
      rm -f /usr/share/dbus-1/*/*freedesktop*
    fi
    userdel -r debian &> /dev/null
  fi
  usermod -aG users _apt &> /dev/null
  usermod -aG users aegir &> /dev/null
  usermod -aG users bin &> /dev/null
  usermod -aG users daemon &> /dev/null
  usermod -aG users man &> /dev/null
  usermod -aG users mysql &> /dev/null
  usermod -aG users nobody &> /dev/null
  usermod -aG users root &> /dev/null
  usermod -aG users sync &> /dev/null
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
  if [ "${_STATUS}" = "INIT" ]; then
    if [ ! -e "/root/.step.init.basic.cnf" ]; then
      msg "INFO: Installing some basic tools..."
      apt_clean_update
      mrun "${_INITINS} locales" &> /dev/null
      locales_check_fix
      mrun "${_INITINS} lsb-release" &> /dev/null
      mrun "${_INITINS} dnsutils" &> /dev/null
      mrun "${_INITINS} netcat" &> /dev/null
      mrun "${_INITINS} netcat-traditional" &> /dev/null
      mrun "${_INITINS} aptitude" &> /dev/null
      mrun "${_INITINS} curl" &> /dev/null
      mrun "${_INITINS} wget" &> /dev/null
      mrun "${_INITINS} hostname" &> /dev/null
      mrun "${_INITINS} net-tools" &> /dev/null
      mrun "${_INITINS} ntpdate" &> /dev/null
      touch /root/.step.init.basic.cnf
    fi
  fi
}

more_packages_install_on_init() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: more_packages_install_on_init"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing more basic tools now..."
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
    apt_clean_update
    mrun "${_INITINS} locales" &> /dev/null
    locales_check_fix
    mrun "${_INITINS} git" &> /dev/null
    mrun "${_INITINS} git-core" &> /dev/null
    mrun "${_INITINS} git-man" &> /dev/null
    mrun "${_INITINS} axel" &> /dev/null
    mrun "${_INITINS} build-essential" &> /dev/null
  fi
}

if_proxysql_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_proxysql_update"
  fi
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
      && [ "${_OS_DIST}" = "Debian" ]; then
      if [ "${_REINSTALL_PXC}" = "YES" ]; then
        msg "INFO: Running ProxySQL upgrade to ${_PXC_VRN}..."
      else
        msg "INFO: Running ProxySQL re-install to ${_PXC_VRN}..."
        apt_clean_update
        mrun "${_INSTAPP} sysbench" 2> /dev/null
        mrun "${_INSTAPP} debconf-utils" 2> /dev/null
        mrun "apt-get remove proxysql -y --purge --auto-remove -qq" 2> /dev/null
        apt_clean_update
        mrun "${_INSTAPP} proxysql" 2> /dev/null
      fi
      isPxy=$(which proxysql 2>&1)
      if [ ! -x "${isPxy}" ]; then
        apt_clean_update
        mrun "${_INSTAPP} sysbench" 2> /dev/null
        mrun "${_INSTAPP} debconf-utils" 2> /dev/null
        mrun "${_INSTAPP} proxysql" 2> /dev/null
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
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Restarting ProxySQL server..."
          fi
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

if_rebuild_src_on_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_rebuild_src_on_major_os_upgrade"
  fi
  _CHECKS_REMOTE_REPOS=YES
  if [ -e "/root/.run-to-daedalus.cnf" ] \
    || [ -e "/root/.run-to-chimaera.cnf" ] \
    || [ -e "/root/.run-to-beowulf.cnf" ]; then
    _CHECKS_REMOTE_REPOS=NO
    if [ -e "/root/.force.rebuild.src.on.auto.now.cnf" ]; then
      _ALLOW_HEAVY_REBUILDS=YES
    else
      _ALLOW_HEAVY_REBUILDS=NO
    fi
  else
    _ALLOW_HEAVY_REBUILDS=YES
  fi
}

if_long_generate_on_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_long_generate_on_major_os_upgrade"
  fi
  if [ -e "/root/.run-to-daedalus.cnf" ] \
    || [ -e "/root/.run-to-chimaera.cnf" ] \
    || [ -e "/root/.run-to-beowulf.cnf" ]; then
    _ALLOW_LONG_GENERATE=NO
  else
    _ALLOW_LONG_GENERATE=YES
  fi
}

if_post_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_post_major_os_upgrade"
  fi
  if [ -e "/root/.run_post_major_os_upgrade.info" ] \
    && [ ! -e "/root/.completed_post_major_os_upgrade.info" ]; then

    apt_clean_update_no_releaseinfo_change
    mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null

    msg "INFO: Cleaning up any systemd remnants..."
    sysvinit_install
    systemd_remove_apt_cmd
    sysvinit_install

    msg "INFO: Removing any packages orphaned by the migration process..."
    mrun "apt-get autoremove --purge -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get autoclean -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get autoremove -y --purge --auto-remove -qq" 2> /dev/null

    msg "INFO: Running dist-upgrade to complete the system upgrade..."
    msg "WAIT: This may take a while, please wait..."
    mrun "apt-get dist-upgrade ${dstUpArg}" 2> /dev/null
    [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
    if [ -e "/root/.allow.downgrades.on.same.os.dist.upgrade.cnf" ]; then
      msg "INFO: dist-upgrade with --allow-downgrades option is used"
      mrun "apt-get dist-upgrade -y --allow-downgrades" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
    else
      mrun "apt-get dist-upgrade -y" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
    fi
    mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
    mrun "apt-get ${dstUpArg} install" 2> /dev/null
    ### Update rsyslog configuration early
    rsyslog_config_update
    ### Reload key services if needed early
    mrun "service redis-server reload" 2> /dev/null
    mrun "service nginx reload" 2> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        mrun "service php${e}-fpm reload" 2> /dev/null
      fi
    done
    if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
      mrun "perl /var/xdrago_wait/proc_num_ctrl.cgi" 2> /dev/null
    else
      mrun "perl /var/xdrago/proc_num_ctrl.cgi" 2> /dev/null
    fi

    _REBUILD_SRC_ON_AUTO_NOW=YES
    if [ -e "/root/.run-to-daedalus.cnf" ] \
      || [ -e "/root/.run-to-chimaera.cnf" ] \
      || [ -e "/root/.run-to-beowulf.cnf" ]; then
      _REBUILD_SRC_ON_AUTO_NOW=NO
      php_if_versions_cleanup_cnf
    fi

    if [ "${_ALLOW_HEAVY_REBUILDS}" = "YES" ]; then
      _REBUILD_SRC_ON_AUTO_NOW=YES
    fi

    if [ -e "/root/.big_hop_on_major_os_upgrade.info" ] \
      && [ ! -e "/root/.rebuild_src_on_auto_before_reboot.info" ] \
      && [ "${_REBUILD_SRC_ON_AUTO_NOW}" = "YES" ]; then
      msg "INFO: Time for re-installing services built from sources..."
      if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
        rm -f /var/xdrago_wait/log/*.log
        rm -f /var/xdrago_wait/log/.php_libs_fix_*.pid
      else
        rm -f /var/xdrago/log/*.log
        rm -f /var/xdrago/log/.php_libs_fix_*.pid
      fi
      _PURGE_MODE=OFF
      _NGX_FORCE_REINSTALL=YES
      _PHP_FORCE_REINSTALL=YES
      _SSH_FORCE_REINSTALL=YES
      _SSL_FORCE_REINSTALL=YES
      if_reinstall_curl_src
      ssl_install_src
      ssl_crypto_lib_fix
      curl_install_src
      sshd_install_src
      nginx_install_upgrade
      magick_install_upgrade
      php_install_deps
      php_libs_fix
      php_if_versions_cleanup_cnf
       if [ -x "/opt/php56/bin/php" ]; then
        _PHP_VERSION="${_PHP56_VRN}"
        install_php_multi "56"
      fi
      if [ -x "/opt/php70/bin/php" ]; then
        _PHP_VERSION="${_PHP70_VRN}"
        install_php_multi "70"
      fi
      if [ -x "/opt/php71/bin/php" ]; then
        _PHP_VERSION="${_PHP71_VRN}"
        install_php_multi "71"
      fi
      if [ -x "/opt/php72/bin/php" ]; then
        _PHP_VERSION="${_PHP72_VRN}"
        install_php_multi "72"
      fi
      if [ -x "/opt/php73/bin/php" ]; then
        _PHP_VERSION="${_PHP73_VRN}"
        install_php_multi "73"
      fi
      if [ -x "/opt/php74/bin/php" ]; then
        _PHP_VERSION="${_PHP74_VRN}"
        install_php_multi "74"
      fi
      if [ -x "/opt/php80/bin/php" ]; then
        _PHP_VERSION="${_PHP80_VRN}"
        install_php_multi "80"
      fi
      if [ -x "/opt/php81/bin/php" ]; then
        _PHP_VERSION="${_PHP81_VRN}"
        install_php_multi "81"
      fi
      if [ -x "/opt/php82/bin/php" ]; then
        _PHP_VERSION="${_PHP82_VRN}"
        install_php_multi "82"
      fi
      if [ -x "/opt/php83/bin/php" ]; then
        _PHP_VERSION="${_PHP83_VRN}"
        install_php_multi "83"
      fi
      _PHP_VERSION=""
      _T_PHP_VRN=""
      _T_PHP_PTH=""
      php_libs_fix
      if [ "${_STATUS}" = "UPGRADE" ]; then
        php_ioncube_check_if_update
        php_check_if_rebuild
      fi
      php_install_upgrade
      php_config_check_update
      php_upgrade_all
      if_install_php_newrelic
      newrelic_check_fix
      _NGX_FORCE_REINSTALL=
      _PHP_FORCE_REINSTALL=
      _SSH_FORCE_REINSTALL=
      _SSL_FORCE_REINSTALL=
    fi
    if [ -e "/root/.run_post_major_os_upgrade.info" ]; then
      rm -f /root/.run_post_major_os_upgrade.info
    fi
    if [ -e "/root/.force.newrelic.update.cnf" ]; then
      rm -f /root/.force.newrelic.update.cnf
    fi
    if [ -e "/root/.allow.downgrades.on.same.os.dist.upgrade.cnf" ]; then
      rm -f /root/.allow.downgrades.on.same.os.dist.upgrade.cnf
    fi
    rm -f /var/xdrago/log/.*_crontab_*
    touch /root/.completed_post_major_os_upgrade.info
    msg "INFO: The post_major_os_upgrade procedure is complete"
  fi
}

if_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_major_os_upgrade"
  fi
  _RUNNING_MAJOR_OS_UPGRADE=NO
  define_loc_osr
  if [ ! -z "${_MSG_LOC}" ]; then
    if [ ! -e "/usr/local/lib/icu/73.1" ] \
      && [ "${_LOC_OS_CODE}" != "jessie" ]; then
      echo
      msg "OOPS: Please run normal 'barracuda up-${tRee}' upgrade"
      msg "OOPS: before trying to run major OS upgrade"
      echo
      mrun "sleep 3"
      echo "Bye"
      barracuda_cnf_cleanup
      clean_pid_exit if_major_os_upgrade_a
    fi
    if [ -e "/root/.run-to-daedalus.cnf" ] \
      || [ -e "/root/.run-to-chimaera.cnf" ] \
      || [ -e "/root/.run-to-beowulf.cnf" ]; then
      _AUTOPILOT=YES
    fi
    _RUNNING_MAJOR_OS_UPGRADE=YES
    msg "MODE: ${_MSG_LOC} upgrade"
    echo
    msg "RLLY: Have you created a Fresh Backup Snapshot of this VM?"
    echo
    mrun "sleep 5"
    msg "ATTN: You have to be prepared in case the upgrade will fail"
    msg "ATTN: You have to be prepared for a crash of this system"
    msg "ATTN: This procedure is well tested but things happen!"
    echo
    mrun "sleep 5"
    tPrmt="Are you sure you want to proceed?"
    tPrmt=$(echo -n ${tPrmt} | fmt -su -w 2500 2>&1)
    if prompt_yes_no "${tPrmt}?" ; then
      true
      echo
      msg "FINE: But you can still hit ctrl-c to stop if you wish"
      msg "WAIT: We need a minute to stop all running cron tasks..."
      mrun "service cron stop" 2> /dev/null
    else
      echo
      msg "FINE: Please try again later once you are ready"
      mrun "sleep 3"
      clean_pid_exit if_major_os_upgrade_b
    fi
    echo
    mrun "sleep 5"
    msg "WAIT: This major system upgrade will start in 60s..."
    mrun "sleep 15"
    msg "WAIT: ...it will start in 45s..."
    mrun "sleep 15"
    msg "WAIT: ...it will start in 30s..."
    mrun "sleep 15"
    msg "WAIT: ...it will start in 15s..."
    mrun "sleep 5"
    msg "ATTN: Ten seconds left to hit ctrl-c to stop..."
    mrun "sleep 10"
    msg "INFO: ${_MSG_LOC} upgrade in progress..."
    echo
    msg "HINT: Command to run in another terminal window to watch details"
    msg "CMND: tail -f ${_LOG}"
    echo
    touch /root/.skip-aegir-master-upgrade.cnf
    if [ -e "/root/.run_post_major_os_upgrade.info" ]; then
      rm -f /root/.run_post_major_os_upgrade.info
    fi
    if [ -e "/root/.completed_post_major_os_upgrade.info" ]; then
      rm -f /root/.completed_post_major_os_upgrade.info
    fi
    if [ -e "/root/.big_hop_on_major_os_upgrade.info" ]; then
      rm -f /root/.big_hop_on_major_os_upgrade.info
    fi
    check_dns_settings
    if [ "${_USE_PROVIDER_DNS}" != "YES" ]; then
      if [ -e "/etc/resolv.conf" ]; then
        mv -f /etc/resolv.conf /etc/resolv.conf.pre-dist-upgrade
      fi
      rm -f /etc/resolv.conf
  	  echo "nameserver 127.0.0.1" > /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      echo "nameserver 1.0.0.1" >> /etc/resolv.conf
  	  echo "nameserver 8.8.8.8" >> /etc/resolv.conf
  	  echo "nameserver 8.8.4.4" >> /etc/resolv.conf
      if [ -e "/etc/resolv.conf.pre-dist-upgrade" ]; then
        cat /etc/resolv.conf.pre-dist-upgrade >> /etc/resolv.conf
      fi
    fi
    rm -f ${pthLog}/ruby-sys-clean-reload.log
    mv -f /var/xdrago /var/xdrago_wait &> /dev/null
    rm -f ${mtrNgx}/pre.d/nginx_speed_purge.conf
    if [ -e "/etc/init.d/bind" ]; then
      rm -f /etc/init.d/bind
    fi
    if [ -e "/etc/default/tomcat" ] && [ -e "/etc/init.d/tomcat" ]; then
      mrun "service tomcat stop" 2> /dev/null
      mv /etc/init.d/tomcat /etc/init.d/offtomcat
      kill -9 $(ps aux | grep '[t]omcat' | awk '{print $2}') &> /dev/null
    fi
    apt_clean_update_no_releaseinfo_change
    mrun "apt-get remove dbus -y --purge --auto-remove -qq" 2> /dev/null
    if [ -e "/usr/share/dbus-1" ]; then
      rm -f /usr/share/dbus-1/*/*freedesktop*
    fi
    mrun "apt-get remove collectd -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove libc-client2007b-dev -y --purge --auto-remove -qq" 2> /dev/null
    ###
    mrun "apt-get remove --purge libmariadb3 -y -qq" 2> /dev/null
    mrun "apt-get remove --purge mariadb-common -y -qq" 2> /dev/null
    mrun "apt-get remove --purge mailutils -y -qq" 2> /dev/null
    ###
    ### Make sure that mariadb related packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/mariadb-common" ]; then
      echo -e 'Package: libmariadb3\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mariadb-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mailutils\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      apt_clean_update_no_releaseinfo_change
    fi
    ###
    _NGINX_GET_DPKG=$(dpkg --get-selections | grep mariadb-common | grep 'hold$' 2>&1)
    if [[ ! "${_NGINX_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold libmariadb3 &> /dev/null
      aptitude hold mariadb-common &> /dev/null
      aptitude hold mailutils &> /dev/null
      echo "libmariadb3 hold" | dpkg --set-selections &> /dev/null
      echo "mariadb-common hold" | dpkg --set-selections &> /dev/null
      echo "mailutils hold" | dpkg --set-selections &> /dev/null
      apt_clean_update_no_releaseinfo_change
    fi
    ###
    mrun "apt-get remove nginx-extras -y -qq" 2> /dev/null
    mrun "apt-get remove nginx -y -qq" 2> /dev/null
    mrun "apt-get remove nginx-common -y -qq" 2> /dev/null
    mrun "apt-get remove nginx-full -y -qq" 2> /dev/null
    mrun "apt-get remove percona-release -y -qq" 2> /dev/null
    ###
    ### Make sure that nginx packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/nginx-common" ]; then
      rm -f /etc/apt/preferences.d/nginx
      echo -e 'Package: nginx\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/nginx-common
      echo -e '\n\nPackage: nginx-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/nginx-common
      apt_clean_update_no_releaseinfo_change
    fi
    ###
    _NGINX_GET_DPKG=$(dpkg --get-selections | grep nginx-common | grep 'hold$' 2>&1)
    if [[ ! "${_NGINX_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold nginx &> /dev/null
      aptitude hold nginx-common &> /dev/null
      echo "nginx hold" | dpkg --set-selections &> /dev/null
      echo "nginx-common hold" | dpkg --set-selections &> /dev/null
      apt_clean_update_no_releaseinfo_change
    fi
    ###
    ### Make sure that percona-release package is locked in apt.
    if [ ! -e "/etc/apt/preferences.d/percona-release" ]; then
      echo -e 'Package: percona-release\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/percona-release
      apt_clean_update
    fi
    ###
    _PERC_GET_DPKG=$(dpkg --get-selections | grep percona-release | grep 'hold$' 2>&1)
    if [[ ! "${_PERC_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold percona-release &> /dev/null
      echo "percona-release hold" | dpkg --set-selections &> /dev/null
      apt_clean_update
    fi
    ###
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
                         php5-xsl      -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove phpunit       -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove php-pear      -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove php-benchmark -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove php5-cli      -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove php5-common   -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove php5-apc      -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove php-apc       -y --purge --auto-remove -qq" 2> /dev/null
    if [ "${_LOC_OS_CODE}" = "jessie" ]; then
      mrun "apt-get remove gnome-tweak-tool -y --purge --auto-remove -qq" 2> /dev/null
    fi
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      mrun "apt-get remove libpam-systemd -y --purge --auto-remove -qq" 2> /dev/null
    fi
    echo "curl install"           | dpkg --set-selections &> /dev/null
    echo "git install"            | dpkg --set-selections &> /dev/null
    echo "git-core install"       | dpkg --set-selections &> /dev/null
    echo "git-man install"        | dpkg --set-selections &> /dev/null
    echo "libssl-dev install"     | dpkg --set-selections &> /dev/null
    echo "nginx install"          | dpkg --set-selections &> /dev/null
    echo "nginx-common install"   | dpkg --set-selections &> /dev/null
    echo "openssh-client install" | dpkg --set-selections &> /dev/null
    echo "openssh-server install" | dpkg --set-selections &> /dev/null
    echo "openssh-sftp-server install" | dpkg --set-selections &> /dev/null
    echo "openssl install"        | dpkg --set-selections &> /dev/null
    echo "ssh install"            | dpkg --set-selections &> /dev/null
    echo "sysvinit-core install"  | dpkg --set-selections &> /dev/null
    echo "sysvinit-utils install" | dpkg --set-selections &> /dev/null
    echo "zlib1g install"         | dpkg --set-selections &> /dev/null
    echo "zlib1g-dev install"     | dpkg --set-selections &> /dev/null
    echo "zlibc install"          | dpkg --set-selections &> /dev/null
    ###
    ### Run pre-migration upgrade in the current OS version.
    mrun "apt-get upgrade ${nrmUpArg}" 2> /dev/null
    ###
    ### Check if we can continue.
    _AUDIT_DPKG=$(dpkg --audit 2>&1)
    if [ ! -z "${_AUDIT_DPKG}" ]; then
      msg "ALRT! I can not continue until dpkg --audit is clean"
      msg "ALRT! ${_AUDIT_DPKG}"
      msg "ALRT! Aborting installer NOW!"
      clean_pid_exit if_major_os_upgrade_c
    fi
    _HOLD_TEST_DPKG=$(dpkg --get-selections | grep 'hold$' 2>&1)
    if [ ! -z "${_HOLD_TEST_DPKG}" ]; then
      msg "ALRT! I can not continue until these packages are un-hold"
      msg "ALRT! ${_HOLD_TEST_DPKG}"
      msg "ALRT! Aborting installer NOW!"
      clean_pid_exit if_major_os_upgrade_d
    fi
    _HOLD_TEST_ATE=$(aptitude search "~ahold" 2>&1)
    if [ ! -z "${_HOLD_TEST_ATE}" ]; then
      msg "ALRT! I can not continue until these packages are un-hold"
      msg "ALRT! ${_HOLD_TEST_ATE}"
      msg "ALRT! Aborting installer NOW!"
      clean_pid_exit if_major_os_upgrade_e
    fi
    ###
    ### Switching db gears on the fly.
    if [ "${_TGT_OSN}" = "Debian" ] || [ "${_TGT_OSN}" = "Devuan" ]; then
      _NEW_OSN=debian
    fi
    _OS_CODE="${_NEW_OS_CODE}"
    if [ "${_OS_CODE}" = "daedalus" ]; then
      _SQL_NEW_OS_CODE=bookworm
    elif [ "${_OS_CODE}" = "chimaera" ]; then
      _SQL_NEW_OS_CODE=bullseye
    elif [ "${_OS_CODE}" = "beowulf" ]; then
      _SQL_NEW_OS_CODE=buster
    else
      _SQL_NEW_OS_CODE="${_OS_CODE}"
    fi
    ###
    ### Switching other gears on the fly first.
    _APT_SRC_TEST=$(ls -la /etc/apt/sources.list.d/* 2>&1)
    if [[ ! "${_APT_SRC_TEST}" =~ "No such file" ]]; then
      sed -i "s/${_LOC_OS_CODE}/${_SQL_NEW_OS_CODE}/g" /etc/apt/sources.list.d/*
    fi
    ###
    ### Now overwriting db gears apt sources.
    if [ "${_DB_SERVER}" = "Percona" ] && [ "${_DB_SERIES}" = "5.7" ]; then
      if [ ! -e "/etc/apt/keyrings/percona.gpg" ]; then
        if [ ! -e "/etc/apt/keyrings" ]; then
          mkdir -m 0755 -p /etc/apt/keyrings
        fi
        if [ -e "/etc/apt/trusted.gpg.d/percona.gpg" ]; then
          rm -f /etc/apt/trusted.gpg.d/percona.gpg*
        fi
        _PERCONA_KEYS_SIG="8507EFA5"
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Retrieving ${_PERCONA_KEYS_SIG} key..."
        fi
        apt-key del ${_PERCONA_KEYS_SIG} &> /dev/null
        if [ -x "/usr/bin/gpg2" ]; then
          _GPG=gpg2
        else
          _GPG=gpg
        fi
        if [ ! -e "/etc/apt/keyrings/percona.gpg" ]; then
          curl -fsSL ${urlDev}/percona-key.gpg | ${_GPG} --dearmor -o /etc/apt/keyrings/percona.gpg
        fi
        chmod 644 /etc/apt/keyrings/percona.gpg
        if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
          kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
          echo "$(date 2>&1) Too many dirmngr processes killed" >> \
            /var/xdrago/log/dirmngr-count.kill.log
        fi
        if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
          kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
          echo "$(date 2>&1) Too many gpg-agent processes killed" >> \
            /var/xdrago/log/gpg-agent-count.kill.log
        fi
      fi
      percRepo="${_DB_SRC}/percona/apt"
      percList="/etc/apt/sources.list.d/percona-release.list"
      rm -f /etc/apt/sources.list.d/percona*
      rm -f /etc/apt/sources.list.d/xtrabackup*
      echo "## Percona APT Repository" > ${percList}
      if [ -e "/etc/apt/keyrings/percona.gpg" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/percona.gpg] http://${percRepo} ${_SQL_NEW_OS_CODE} main" >> ${percList}
        echo "deb-src [signed-by=/etc/apt/keyrings/percona.gpg] http://${percRepo} ${_SQL_NEW_OS_CODE} main" >> ${percList}
      else
        echo "deb http://${percRepo} ${_SQL_NEW_OS_CODE} main" >> ${percList}
        echo "deb-src http://${percRepo} ${_SQL_NEW_OS_CODE} main" >> ${percList}
      fi
      chmod 644 ${percList}
      echo -e 'Package: *\nPin: release o=Percona Development Team\nPin-Priority: 1001' > /etc/apt/preferences.d/00percona.pref
    fi
    ###
    ### Switching system gears on the fly.
    if [ "${_TGT_OSN}" = "Devuan" ]; then
      _TGT_MRR="deb.devuan.org/merged"
      echo "## DEVUAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_TGT_MRR} ${_NEW_OS_CODE} main" >> ${aptLiSys}
      echo "deb-src http://${_TGT_MRR} ${_NEW_OS_CODE} main" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
      echo "deb http://${_TGT_MRR} ${_NEW_OS_CODE}-updates main" >> ${aptLiSys}
      echo "deb-src http://${_TGT_MRR} ${_NEW_OS_CODE}-updates main" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## DEVUAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://${_TGT_MRR} ${_NEW_OS_CODE}-security main" >> ${aptLiSys}
      echo "deb-src http://${_TGT_MRR} ${_NEW_OS_CODE}-security main" >> ${aptLiSys}
      if [ -e "/etc/apt/apt.conf" ]; then
        rm -f /etc/apt/apt.conf
      fi
      ###
      ### Add devuan-keyring first.
      apt_clean_update_no_releaseinfo_change
      mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null
      mrun "${_INITINS} devuan-keyring" 2> /dev/null
    else
      if [ "${_NEW_OS_CODE}" = "stretch" ]; then
        _NEW_APT_MIRROR="archive.debian.org/debian"
        _NEW_APT_REPSRC="${_NEW_OS_CODE}-backports"
        _NEW_SEC_MIRROR="archive.debian.org/debian-security"
        _NEW_SEC_REPSRC="${_NEW_OS_CODE}/updates"
      elif [ "${_NEW_OS_CODE}" = "buster" ]; then
        _NEW_APT_MIRROR="deb.debian.org/debian"
        _NEW_APT_REPSRC="${_NEW_OS_CODE}-updates"
        _NEW_SEC_MIRROR="security.debian.org"
        _NEW_SEC_REPSRC="${_NEW_OS_CODE}/updates"
      elif [ "${_NEW_OS_CODE}" = "bullseye" ]; then
        _NEW_APT_MIRROR="deb.debian.org/debian"
        _NEW_APT_REPSRC="${_NEW_OS_CODE}-updates"
        _NEW_SEC_MIRROR="security.debian.org/debian-security"
        _NEW_SEC_REPSRC="${_NEW_OS_CODE}-security"
      elif [ "${_NEW_OS_CODE}" = "bookworm" ]; then
        _NEW_APT_MIRROR="deb.debian.org/debian"
        _NEW_APT_REPSRC="${_NEW_OS_CODE}-updates"
        _NEW_SEC_MIRROR="security.debian.org/debian-security"
        _NEW_SEC_REPSRC="${_NEW_OS_CODE}-security"
      fi
      echo "## DEBIAN MAIN REPOSITORIES" > ${aptLiSys}
      echo "deb http://${_NEW_APT_MIRROR} ${_NEW_OS_CODE} main contrib non-free" >> ${aptLiSys}
      echo "deb-src http://${_NEW_APT_MIRROR} ${_NEW_OS_CODE} main contrib non-free" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${aptLiSys}
      echo "deb http://${_NEW_APT_MIRROR} ${_NEW_APT_REPSRC} main contrib non-free" >> ${aptLiSys}
      echo "deb-src http://${_NEW_APT_MIRROR} ${_NEW_APT_REPSRC} main contrib non-free" >> ${aptLiSys}
      echo "" >> ${aptLiSys}
      echo "## DEBIAN SECURITY UPDATES" >> ${aptLiSys}
      echo "deb http://${_NEW_SEC_MIRROR} ${_NEW_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      echo "deb-src http://${_NEW_SEC_MIRROR} ${_NEW_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${aptLiSys}
      if [ -e "/etc/apt/apt.conf" ]; then
        rm -f /etc/apt/apt.conf
      fi
    fi
    ###
    ### Make sure that systemd packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/offsystemd" ]; then
      rm -f /etc/apt/preferences.d/systemd
      echo -e 'Package: systemd\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/offsystemd
      echo -e '\n\nPackage: *systemd*\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/offsystemd
    fi
    ###
    ### Update packages registry.
    apt_clean_update_no_releaseinfo_change
    mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null
    ###
    ### Two step upgrade with apt-get only.
    mrun "apt-get install apt -t ${_NEW_OS_CODE} ${dstUpArg}" 2> /dev/null
    apt_clean_update_no_releaseinfo_change
    mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null
    ###
    ### Requirement for Debian Stretch to Devuan Beowulf migration.
    ### The libtinfo package needs to be upgraded to prevent breaks.
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      mrun "apt-get install libtinfo6 ${dstUpArg}" 2> /dev/null
    fi
    ###
    ### Note that this upgrade does not complete the migration yet.
    mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
    mrun "apt-get install apt dpkg aptitude util-linux ${dstUpArg}" 2> /dev/null
    ###
    ### Back to BOA stuff re-install as needed.
    if [ -e "/etc/init.d/bind9" ] && [ ! -e "/etc/init.d/bind" ]; then
      ln -sfn /etc/init.d/bind9 /etc/init.d/bind
    fi
    if [ -e "${mtrInc}/nginx_vhost_common.conf" ]; then
      if [ -e "/root/.debug.cnf" ]; then
        mv -f /etc/init.d/networking /etc/init.d/networking.bak
        cp -af /etc/init.d/networking.dpkg-dist /etc/init.d/networking
        chmod 755 /etc/init.d/networking
        ls -la /etc/init.d/networking
      fi
    fi
    if [ -d "/var/www/cgp" ]; then
      mrun "apt-get install collectd ${dstUpArg}" 2> /dev/null
    fi
    mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
    mrun "apt-get install libc-client2007e-dev ${dstUpArg}" 2> /dev/null
    ###
    ### Make sure that org.freedesktop.systemd1 was not atempted by dbus.
    mrun "apt-get remove dbus -y --purge --auto-remove -qq" 2> /dev/null
    if [ -e "/usr/share/dbus-1" ]; then
      rm -f /usr/share/dbus-1/*/*freedesktop*
    fi
    ###
    ### Fix any broken packages.
    apt_clean_update_no_releaseinfo_change
    mrun "apt-get --fix-broken install -y" 2> /dev/null
    ###
    ### Make sure that sysvinit-core is still installed and systemd removed.
    sysvinit_install
    systemd_remove_apt_cmd
    sysvinit_install
    ###
    ### Prepare for the last step.
    if [ "${_TGT_OSN}" = "Devuan" ]; then
      ###
      ### The last step before migration to Devuan is to switch to eudev.
      ### Jessie exception needs testing, though.
      if [ "${_LOC_OS_CODE}" != "jessie" ]; then
        mrun "apt-get install eudev ${dstUpArg}" 2> /dev/null
      fi
    fi
    ###
    ### Upgrade all packages so that you have the latest versions.
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
      #mrun "apt-get full-upgrade ${dstUpArg}" 2> /dev/null
      mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
    else
      mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
      mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
    fi
    ###
    ### Force install/upgrade to give it another chance to complete.
    mrun "apt-get ${dstUpArg} install" 2> /dev/null
    ###
    ### Upgrade again all packages so that you have the latest versions.
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
      #mrun "apt-get full-upgrade ${dstUpArg}" 2> /dev/null
      mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
    else
      mrun "apt-get upgrade ${dstUpArg}" 2> /dev/null
      mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
    fi
    mrun "apt-get upgrade -y" 2> /dev/null
    ###
    ### Make sure that sysvinit-core is still installed and systemd removed.
    sysvinit_install
    systemd_remove_apt_cmd
    sysvinit_install
    ###
    ### Finally, the proper dist-upgrade time.
    ### Note that Debian to Devuan migration always requires
    ### the key dist-upgrade step to be run AFTER reboot!
    _FORCE_REBUILD_SRC_ON_AUTO_NOW=NO
    if [ "${_LOC_OS_CODE}" = "bookworm" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      msg "ATTN: NOTE! Debian Bookworm to Devuan migration"
      msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "bullseye" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      msg "ATTN: NOTE! Debian Bullseye to Devuan migration"
      msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "buster" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      msg "ATTN: NOTE! Debian Buster to Devuan migration"
      msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "stretch" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      msg "ATTN: NOTE! Debian Stretch to Devuan migration"
      msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "jessie" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      msg "ATTN: NOTE! Debian Jessie to Devuan migration"
      msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    else
      echo
      mrun "apt-get dist-upgrade ${dstUpArg} --allow-downgrades" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
      mrun "apt-get dist-upgrade -y --allow-downgrades" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
      mrun "apt-get install lsb-release ${dstUpArg}" 2> /dev/null
      ###
      if [ "${_LOC_OS_CODE}" = "chimaera" ] \
        && [ "${_NEW_OS_CODE}" = "daedalus" ]; then
        ###
        ### Fix PHP early
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DIST: Special procedure for ${_LOC_OS_CODE} to ${_NEW_OS_CODE} upgrade"
        fi
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "TRCK: Removing libldap packages for a clean start"
        fi
        mrun "apt-get remove libldap-common -y -qq" 2> /dev/null
        mrun "apt-get remove libldap2-dev -y -qq" 2> /dev/null
        mrun "apt-get remove libldap-dev -y -qq" 2> /dev/null
        apt_clean_update
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "TRCK: Installing now libldap packages from Chimaera"
        fi
        echo "deb http://deb.devuan.org/merged chimaera main" > /etc/apt/sources.list.d/chimaera.list
        echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
        apt_clean_update
        mrun "apt-get install -t chimaera libldap-common -y" 2> /dev/null
        mrun "apt-get install -t chimaera libldap2-dev -y" 2> /dev/null
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "TRCK: Locking libldap packages to prevent upgrade on Daedalus"
        fi
        ### Make sure that libldap packages are locked in apt.
        echo -e 'Package: libldap-common\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/libldap
        echo -e '\n\nPackage: libldap2-dev\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/libldap
        echo -e '\n\nPackage: libldap-dev\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/libldap
        apt_clean_update
        ###
        _LDAP_GET_DPKG=$(dpkg --get-selections | grep libldap-common | grep 'hold$' 2>&1)
        if [[ ! "${_LDAP_GET_DPKG}" =~ "hold" ]]; then
          aptitude hold libldap-common &> /dev/null
          aptitude hold libldap2-dev &> /dev/null
          aptitude hold libldap-dev &> /dev/null
          echo "libldap-common hold" | dpkg --set-selections &> /dev/null
          echo "libldap2-dev hold" | dpkg --set-selections &> /dev/null
          echo "libldap-dev hold" | dpkg --set-selections &> /dev/null
          apt_clean_update
        fi
        rm -f /etc/apt/sources.list.d/chimaera.list
        rm -f /etc/apt/apt.conf
        apt_clean_update
        ldconfig 2> /dev/null
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DIST: Signal that --allow-downgrades can be used after reboot"
        fi
        touch /root/.allow.downgrades.on.same.os.dist.upgrade.cnf
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DIST: Rebuidling key services from sources before reboot..."
        fi
        _FORCE_REBUILD_SRC_ON_AUTO_NOW=YES
        touch /root/.force.rebuild.src.on.auto.now.cnf
        if_rebuild_src_on_major_os_upgrade
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "DIST: No quick rebuild from src on ${_LOC_OS_CODE} to ${_NEW_OS_CODE} upgrade"
        fi
      fi
      ###
    fi
    ### Make sure that sysvinit-core is still installed and systemd removed.
    sysvinit_install
    systemd_remove_apt_cmd
    sysvinit_install
    ### Update rsyslog configuration early
    rsyslog_config_update
    ### Reload key services if needed early
    mrun "service redis-server reload" 2> /dev/null
    mrun "service nginx reload" 2> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        mrun "service php${e}-fpm reload" 2> /dev/null
      fi
    done
    if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
      mrun "perl /var/xdrago_wait/proc_num_ctrl.cgi" 2> /dev/null
    else
      mrun "perl /var/xdrago/proc_num_ctrl.cgi" 2> /dev/null
    fi
    ### Add info file to keep major OS upgrades track.
    touch /root/.${_LOC_OS_CODE}_to_${_NEW_OS_CODE}_major_os_upgrade.info
    ### Force NR upgrade
    touch /root/.force.newrelic.update.cnf
    ### Re-install key services early to limit downtime and SSH keys confusion.
    if [ -e "/root/.run-to-daedalus.cnf" ] \
      || [ -e "/root/.run-to-chimaera.cnf" ] \
      || [ -e "/root/.run-to-beowulf.cnf" ]; then
      _REBUILD_SRC_ON_AUTO_NOW=NO
    else
      _REBUILD_SRC_ON_AUTO_NOW=YES
    fi
    if [ "${_FORCE_REBUILD_SRC_ON_AUTO_NOW}" = "YES" ]; then
      _REBUILD_SRC_ON_AUTO_NOW=YES
    fi
    rm -f /root/.rebuild_src_on_auto_before_reboot.info
    if [ "${_REBUILD_SRC_ON_AUTO_NOW}" = "YES" ] \
      && [ "${_ALLOW_HEAVY_REBUILDS}" = "YES" ]; then
      touch /root/.rebuild_src_on_auto_before_reboot.info
      rm -f /var/xdrago_wait/log/*.log
      _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
      _PURGE_MODE=OFF
      _NGX_FORCE_REINSTALL=YES
      _PHP_FORCE_REINSTALL=YES
      _SSL_FORCE_REINSTALL=YES
      _SSH_FORCE_REINSTALL=YES
      php_libs_fix
      if_reinstall_curl_src
      ssl_install_src
      ssl_crypto_lib_fix
      curl_install_src
      sshd_install_src
      nginx_install_upgrade
      magick_install_upgrade
      php_install_deps
      php_libs_fix
      php_if_versions_cleanup_cnf
      if [ "${_STATUS}" = "UPGRADE" ]; then
        php_ioncube_check_if_update
        php_check_if_rebuild
      fi
      php_install_upgrade
      php_config_check_update
      php_upgrade_all
      if_install_php_newrelic
      newrelic_check_fix
    fi
    if [ "${_TGT_OSN}" = "Devuan" ]; then
      if [ "${_LOC_OS_CODE}" = "bookworm" ] \
        || [ "${_LOC_OS_CODE}" = "bullseye" ] \
        || [ "${_LOC_OS_CODE}" = "buster" ]; then
        touch /root/.small_hop_on_major_os_upgrade.info
      else
        touch /root/.big_hop_on_major_os_upgrade.info
      fi
    else
      touch /root/.big_hop_on_major_os_upgrade.info
    fi
    # if [ -e "/root/.big_hop_on_major_os_upgrade.info" ]; then
    #   _PHP_FORCE_REINSTALL=YES
    #   _SQL_FORCE_REINSTALL=YES
    #   db_server_install
    #   myquick_install_upgrade
    #   php_install_deps
    #   php_libs_fix
    #   php_install_upgrade
    #   php_config_check_update
    #   php_upgrade_all
    #   if_install_php_newrelic
    #   newrelic_check_fix
    #   php_ioncube_check_if_update
    #   php_check_if_rebuild
    # fi
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
          mrun "update-rc.d -f ${link} remove" 2> /dev/null
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
        apt_clean_update_no_releaseinfo_change
        mrun "apt-get install udev -y --allow-unauthenticated" 2> /dev/null
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
    SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership lock-local-drush-permissions)
    for SCRIPT in ${SCRIPTS[@]}; do
      _VAR_IF_PRESENT=$(grep "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" /etc/sudoers.d/${SCRIPT} 2>&1)
      if [[ ! "${_VAR_IF_PRESENT}" =~ "aegir ALL=NOPASSWD" ]]; then
        echo "aegir ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" >> /etc/sudoers.d/${SCRIPT}
        chmod 0440 /etc/sudoers.d/${SCRIPT}
      fi
    done
    ###
    ### Make sure that Aegir Octopus system users are added to sudo.
    if [ -d "/data/u" ]; then
      for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
        if [ -e "${User}/config/server_master/nginx/vhost.d" ] \
          && [ ! -e "${User}/log/proxied.pid" ] \
          && [ ! -e "${User}/log/CANCELLED" ]; then
          _HM_U=$(echo ${User} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
          _VAR_IF_PRESENT=$(grep "${_HM_U} ALL=NOPASSWD" /etc/sudoers 2>&1)
          if [[ ! "${_VAR_IF_PRESENT}" =~ "${_HM_U} ALL=NOPASSWD" ]]; then
            echo "${_HM_U} ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
          fi
          SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership lock-local-drush-permissions)
          for SCRIPT in ${SCRIPTS[@]}; do
            _VAR_IF_PRESENT=$(grep "${_HM_U} ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" /etc/sudoers.d/${SCRIPT} 2>&1)
            if [[ ! "${_VAR_IF_PRESENT}" =~ "${_HM_U} ALL=NOPASSWD" ]]; then
              echo "${_HM_U} ALL=NOPASSWD: /usr/local/bin/${SCRIPT}.sh" >> /etc/sudoers.d/${SCRIPT}
              chmod 0440 /etc/sudoers.d/${SCRIPT}
            fi
          done
        fi
      done
    fi
    ###
    ### Final cleanup.
    echo rotate > /var/log/syslog
    rm -f /var/xdrago_wait/log/*.log
    mv -f /var/xdrago_wait /var/xdrago &> /dev/null
    ###
    ### Add ctrl file to trigger if_post_major_os_upgrade() after reboot.
    touch /root/.run_post_major_os_upgrade.info
    echo " "
    msg "RLLY: No errors? ${_MSG_LOC} migration worked :)"
    msg "STEP: Please reboot this server now"
    msg "STEP: Once the system is up, run 'barracuda up-${tRee}' command again"
    echo " "
    msg "Bye"
    touch /root/.latest-barracuda-upgrade-finale.info
    barracuda_cnf_cleanup
    clean_pid_exit if_major_os_upgrade_f
  fi
}

webmin_apt_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: webmin_apt_update"
  fi
  if [ -d "/etc/webmin" ]; then
    if [ ! -e "${pthLog}/webmin_update_apt_src.log" ]; then
      cd /var/opt
      echo "## Webmin APT Repository" > /etc/apt/sources.list.d/webmin.list
      echo "deb http://download.webmin.com/download/repository \
        sarge contrib" | fmt -su -w 2500 >> /etc/apt/sources.list.d/webmin.list
      echo "deb http://webmin.mirror.somersettechsolutions.co.uk/repository \
        sarge contrib" | fmt -su -w 2500 >> /etc/apt/sources.list.d/webmin.list
      _KEYS_SERVER_TEST=FALSE
      until [[ "${_KEYS_SERVER_TEST}" =~ "GnuPG" ]]; do
        rm -f jcameron-key.gpg*
        wget -q -U iCab ${urlDev}/jcameron-key.gpg
        _KEYS_SERVER_TEST=$(grep GnuPG jcameron-key.gpg 2>&1)
        sleep 2
      done
      if [ -x "/usr/bin/gpg2" ]; then
        _GPG=gpg2
      else
        _GPG=gpg
      fi
      cat jcameron-key.gpg | ${_GPG} --import &> /dev/null
      rm -f jcameron-key.gpg*
      touch ${pthLog}/webmin_update_apt_src.log
    fi
  fi
}

early_sys_ctrl_mark() {
  if [ -e "/root/.run_post_major_os_upgrade.info" ]; then
    touch /root/.early-sys-ctrl-mark.cnf
  else
    [ -e "/root/.early-sys-ctrl-mark.cnf" ] && rm -f /root/.early-sys-ctrl-mark.cnf
  fi
}

normal_sys_ctrl_mark() {
  if [ -e "/root/.latest-barracuda-upgrade-finale.info" ]; then
    rm -f /root/.latest-barracuda-upgrade-finale.info
    touch /root/.normal-sys-ctrl-mark.cnf
  else
    [ -e "/root/.normal-sys-ctrl-mark.cnf" ] && rm -f /root/.normal-sys-ctrl-mark.cnf
  fi
}

sys_packages_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sys_packages_update"
  fi
  msg "INFO: Running system packages update..."
  if [ -e "/var/aegir" ]; then
    echo "curl install"           | dpkg --set-selections &> /dev/null
    echo "git install"            | dpkg --set-selections &> /dev/null
    echo "git-core install"       | dpkg --set-selections &> /dev/null
    echo "git-man install"        | dpkg --set-selections &> /dev/null
    echo "libssl-dev install"     | dpkg --set-selections &> /dev/null
    echo "nginx install"          | dpkg --set-selections &> /dev/null
    echo "nginx-common install"   | dpkg --set-selections &> /dev/null
    echo "openssh-client install" | dpkg --set-selections &> /dev/null
    echo "openssh-server install" | dpkg --set-selections &> /dev/null
    echo "openssh-sftp-server install" | dpkg --set-selections &> /dev/null
    echo "openssl install"        | dpkg --set-selections &> /dev/null
    echo "ssh install"            | dpkg --set-selections &> /dev/null
    echo "sysvinit-core install"  | dpkg --set-selections &> /dev/null
    echo "sysvinit-utils install" | dpkg --set-selections &> /dev/null
    echo "zlib1g install"         | dpkg --set-selections &> /dev/null
    echo "zlib1g-dev install"     | dpkg --set-selections &> /dev/null
    echo "zlibc install"          | dpkg --set-selections &> /dev/null
  fi
  webmin_apt_update
  apt_clean_update
  if [ -e "/var/aegir/drush" ]; then
    _DPKG_CNF="confold"
  else
    _DPKG_CNF="confnew"
  fi
  st_runner "aptitude full-upgrade -f -y -q \
    --allow-untrusted \
    -o Dpkg::Options::=--force-confmiss \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-${_DPKG_CNF}" &> /dev/null
  if [ "${_STATUS}" = "INIT" ]; then
    apt_clean_update
    st_runner "aptitude full-upgrade -f -y -q \
      --allow-untrusted \
      -o Dpkg::Options::=--force-confmiss \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-${_DPKG_CNF}" &> /dev/null
    st_runner "apt-get autoclean -y" &> /dev/null
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
      php5-xsl" 2> /dev/null
    mrun "${_RMAPP} phpunit php-pear php-benchmark" 2> /dev/null
    mrun "${_RMAPP} php5-cli php5-common" 2> /dev/null
    mrun "${_RMAPP} php5-apc" 2> /dev/null
    mrun "${_RMAPP} php-apc" 2> /dev/null
    mrun "${_RMAPP} apache2.2-common" 2> /dev/null
    mrun "${_RMAPP} apache2.2-bin" 2> /dev/null
    mrun "aptitude install lsof -y --allow-untrusted" 2> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      rm -f /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      rm -f /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    rm -f /var/lib/mysql/debian-*.flag &> /dev/null
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sys_packages_install"
  fi
  if_to_do_fix
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Installing required libraries and tools..."
  else
    msg "INFO: Upgrading required libraries and tools..."
    if [ ! -e "/etc/init.d/php5-fpm" ]; then
      cp -af ${locCnf}/php/php5-fpm-init-vanilla /etc/init.d/php5-fpm
    fi
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [[ "${_XTRAS_LIST}" =~ "SR" ]] \
      || [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ "${_OS_CODE}" = "jessie" ]; then
        _APT_XTRA="openjdk-7-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "stretch" ]; then
        _APT_XTRA="openjdk-8-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "buster" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "bullseye" ]; then
        _APT_XTRA="openjdk-11-jre-headless openjdk-17-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "bookworm" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java nginx"
        echo "deb http://deb.debian.org/debian bullseye main contrib non-free" > /etc/apt/sources.list.d/bullseye.list
        echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
        apt_clean_update
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "TRCK: Installing now openjdk-11-jre-headless from Bullseye"
        fi
        mrun "apt-get install -t bullseye openjdk-11-jre-headless -y" 2> /dev/null
        rm -f /etc/apt/sources.list.d/bullseye.list
        rm -f /etc/apt/apt.conf
        apt_clean_update
      elif [ "${_OS_CODE}" = "beowulf" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "chimaera" ]; then
        _APT_XTRA="openjdk-11-jre-headless openjdk-17-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "daedalus" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java nginx"
        if [ ! -x "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" ]; then
          echo "deb http://deb.devuan.org/merged chimaera main" > /etc/apt/sources.list.d/chimaera.list
          echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
          apt_clean_update
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "TRCK: Installing now openjdk-11-jre-headless from Chimaera"
          fi
          mrun "apt-get install -t chimaera openjdk-11-jre-headless -y" 2> /dev/null
          rm -f /etc/apt/sources.list.d/chimaera.list
          rm -f /etc/apt/apt.conf
          apt_clean_update
        fi
      fi
    else
      _APT_XTRA="nginx"
    fi
    _APT_ELSE="netcat nginx"
  else
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-6-jdk | grep install 2>&1)
    if [[ "${_APT_ITEM}" =~ "install" ]]; then
      mrun "apt-get remove openjdk-6-jdk -y --purge --auto-remove -qq" 2> /dev/null
    fi
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-7-jdk | grep install 2>&1)
    if [[ "${_APT_ITEM}" =~ "install" ]]; then
      mrun "apt-get remove openjdk-7-jdk -y --purge --auto-remove -qq" 2> /dev/null
    fi
    if [[ "${_XTRAS_LIST}" =~ "SR" ]] \
      || [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
      || [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      if [ "${_OS_CODE}" = "jessie" ]; then
        _APT_XTRA="openjdk-7-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "stretch" ]; then
        _APT_XTRA="openjdk-8-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "buster" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "bullseye" ]; then
        _APT_XTRA="openjdk-11-jre-headless openjdk-17-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "bookworm" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java"
        echo "deb http://deb.debian.org/debian bullseye main contrib non-free" > /etc/apt/sources.list.d/bullseye.list
        echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
        apt_clean_update
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "TRCK: Installing now openjdk-11-jre-headless from Bullseye"
        fi
        mrun "apt-get install -t bullseye openjdk-11-jre-headless -y" 2> /dev/null
        rm -f /etc/apt/sources.list.d/bullseye.list
        rm -f /etc/apt/apt.conf
        apt_clean_update
      elif [ "${_OS_CODE}" = "beowulf" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "chimaera" ]; then
        _APT_XTRA="openjdk-11-jre-headless openjdk-17-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "daedalus" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java"
        if [ ! -x "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" ]; then
          echo "deb http://deb.devuan.org/merged chimaera main" > /etc/apt/sources.list.d/chimaera.list
          echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
          apt_clean_update
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "TRCK: Installing now openjdk-11-jre-headless from Chimaera"
          fi
          mrun "apt-get install -t chimaera openjdk-11-jre-headless -y" 2> /dev/null
          rm -f /etc/apt/sources.list.d/chimaera.list
          rm -f /etc/apt/apt.conf
          apt_clean_update
        fi
      fi
    else
      _APT_XTRA=""
    fi
    _APT_ELSE="netcat netcat-traditional"
    apt_clean_update
    mrun "service nginx start" 2> /dev/null
    mrun "apt-get remove nginx-extras -y -qq" 2> /dev/null
    mrun "apt-get remove nginx -y -qq" 2> /dev/null
    mrun "apt-get remove nginx-common -y -qq" 2> /dev/null
    mrun "apt-get remove nginx-full -y -qq" 2> /dev/null
    mrun "apt-get remove redis-server -y -qq" 2> /dev/null
    mrun "apt-get remove percona-release -y -qq" 2> /dev/null
    ###
    ### Make sure that nginx packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/nginx-common" ]; then
      rm -f /etc/apt/preferences.d/nginx
      echo -e 'Package: nginx\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/nginx-common
      echo -e '\n\nPackage: nginx-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/nginx-common
      apt_clean_update
    fi
    ###
    _NGINX_GET_DPKG=$(dpkg --get-selections | grep nginx-common | grep 'hold$' 2>&1)
    if [[ ! "${_NGINX_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold nginx &> /dev/null
      aptitude hold nginx-common &> /dev/null
      echo "nginx hold" | dpkg --set-selections &> /dev/null
      echo "nginx-common hold" | dpkg --set-selections &> /dev/null
      apt_clean_update
    fi
    ###
    ### Make sure that percona-release package is locked in apt.
    if [ ! -e "/etc/apt/preferences.d/percona-release" ]; then
      echo -e 'Package: percona-release\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/percona-release
      apt_clean_update
    fi
    ###
    _PERC_GET_DPKG=$(dpkg --get-selections | grep percona-release | grep 'hold$' 2>&1)
    if [[ ! "${_PERC_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold percona-release &> /dev/null
      echo "percona-release hold" | dpkg --set-selections &> /dev/null
      apt_clean_update
    fi
    ###
    mrun "apt-get remove --purge libmariadb3 -y -qq" 2> /dev/null
    mrun "apt-get remove --purge mariadb-common -y -qq" 2> /dev/null
    mrun "apt-get remove --purge mailutils -y -qq" 2> /dev/null
    ###
    ### Make sure that mariadb related packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/mariadb-common" ]; then
      echo -e 'Package: libmariadb3\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mariadb-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mailutils\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      apt_clean_update_no_releaseinfo_change
    fi
    ###
    _NGINX_GET_DPKG=$(dpkg --get-selections | grep mariadb-common | grep 'hold$' 2>&1)
    if [[ ! "${_NGINX_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold libmariadb3 &> /dev/null
      aptitude hold mariadb-common &> /dev/null
      aptitude hold mailutils &> /dev/null
      echo "libmariadb3 hold" | dpkg --set-selections &> /dev/null
      echo "mariadb-common hold" | dpkg --set-selections &> /dev/null
      echo "mailutils hold" | dpkg --set-selections &> /dev/null
      apt_clean_update_no_releaseinfo_change
    fi
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
    mrun "apt-get remove sysklogd -y --purge --auto-remove -qq" 2> /dev/null
    mrun "apt-get remove rsyslog -y --purge --auto-remove -qq" 2> /dev/null
    mrun "killall -9 sysklogd" 2> /dev/null
    mrun "killall -9 rsyslogd" 2> /dev/null
  elif [ -e "/root/.use.sysklogd.cnf" ]; then
    _SYSLOGD=sysklogd
    mrun "apt-get remove rsyslog -y --purge --auto-remove -qq" 2> /dev/null
    mrun "killall -9 rsyslogd" 2> /dev/null
  else
    _SYSLOGD=rsyslog
  fi

  if [ "${_OS_CODE}" = "daedalus" ]; then
    _EXTRA_PACKAGES="autoconf2.69 \
                     automake1.11 \
                     automake-1.16 \
                     gnupg1-curl \
                     libpcre2-dev \
                     libpcre2-posix3 \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng16-16 \
                     libtinfo6 \
                     software-properties-common \
                     python3-software-properties \
                     ${_EXTRA_PACKAGES}"
  elif [ "${_OS_CODE}" = "chimaera" ]; then
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
  elif [ "${_OS_CODE}" = "beowulf" ]; then
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
  elif [ "${_OS_CODE}" = "bookworm" ]; then
    _EXTRA_PACKAGES="autoconf2.69 \
                     automake1.11 \
                     automake-1.16 \
                     gnupg1-curl \
                     libpcre2-dev \
                     libpcre2-posix3 \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng16-16 \
                     libtinfo6 \
                     software-properties-common \
                     python3-software-properties \
                     ${_EXTRA_PACKAGES}"
  elif [ "${_OS_CODE}" = "bullseye" ]; then
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
  elif [ "${_OS_CODE}" = "buster" ]; then
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
  elif [ "${_OS_CODE}" = "stretch" ]; then
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
    _EXTRA_PACKAGES="autoconf2.64 \
                     automake1.11 \
                     automake-1.14 \
                     defoma \
                     gnupg-curl \
                     libpcre3 \
                     libpcre3-dev \
                     libpng-dev \
                     libpng12-0 \
                     libpng12-dev \
                     libpng12-0-dev \
                     libt1-5 \
                     libt1-dev \
                     python-software-properties \
                     t1lib-bin \
                     ttf-dejavu \
                     ttf-dejavu-core \
                     ttf-dejavu-extra \
                     ${_EXTRA_PACKAGES}"
  fi

  _EXTRA_PACKAGES="libgd3 \
                   libxpm-dev \
                   libwebp-dev \
                   ${_EXTRA_PACKAGES}"

  if [[ "${_XTRAS_LIST}" =~ "IMG" ]] \
    || [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
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

  if [ "${_VMFAMILY}" != "VS" ] && [ "${_OS_DIST}" != "Devuan" ]; then
    _EXTRA_PACKAGES="udev \
                     ${_EXTRA_PACKAGES}"
  fi

  if [ "${_MAGICK_FROM_SOURCES}" = "NO" ] \
    || [ -z "${_MAGICK_FROM_SOURCES}" ]; then
    _EXTRA_PACKAGES="imagemagick libmagickwand-dev graphviz libgraphviz-dev \
                     ${_EXTRA_PACKAGES}"
  fi

  _MAILSERV="postfix postfix-pcre s-nail"
}

php_libs_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: php_libs_fix"
  fi
  if_to_do_fix
  _LIB_NOW=$(date +%y%m%d-%H%M 2>&1)
  _LIB_NOW=${_LIB_NOW//[^0-9-]/}
  if [ ! -L "/usr/lib/librtmp.so" ] \
    || [ ! -e "/usr/lib/libwebpmux.so" ] \
    || [ ! -e "/usr/lib/libonig.so" ] \
    || [ ! -e "/usr/lib/libcurl.so" ] \
    || [ ! -e "/usr/lib/libicuio.so" ] \
    || [ ! -e "/usr/lib/liblber.so" ] \
    || [ ! -e "/var/xdrago/log/.php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid" ] \
    || [ ! -e "/var/xdrago/log/.php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid" ] \
    || [ ! -e "/usr/include/gmp.h" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Fix for PHP libs in ${_OS_DIST}/${_OS_CODE}"
    fi
    _X86_64_TEST=$(uname -m 2>&1)
    if [ "${_X86_64_TEST}" = "x86_64" ]; then
      if [ -e "/usr/local/lib/icu" ]; then
        if [ -e "/usr/lib/x86_64-linux-gnu/icu" ] \
          && [ ! -L "/usr/lib/x86_64-linux-gnu/icu" ]; then
          rm -rf /var/backups/.prev_icu
          mv -f /usr/lib/x86_64-linux-gnu/icu /var/backups/.prev_icu
          ln -sfn /usr/local/lib/icu /usr/lib/x86_64-linux-gnu/icu
        else
          ln -sfn /usr/local/lib/icu /usr/lib/x86_64-linux-gnu/icu
        fi
        ln -sfn /usr/local/lib/libicudata.so /usr/lib/x86_64-linux-gnu/libicudata.so
        ln -sfn /usr/local/lib/libicui18n.so /usr/lib/x86_64-linux-gnu/libicui18n.so
        ln -sfn /usr/local/lib/libicuio.so   /usr/lib/x86_64-linux-gnu/libicuio.so
        ln -sfn /usr/local/lib/libicutest.so /usr/lib/x86_64-linux-gnu/libicutest.so
        ln -sfn /usr/local/lib/libicutu.so   /usr/lib/x86_64-linux-gnu/libicutu.so
        ln -sfn /usr/local/lib/libicuuc.so   /usr/lib/x86_64-linux-gnu/libicuuc.so
        ln -sfn /usr/local/lib/libicudata.so /usr/lib/libicudata.so
        ln -sfn /usr/local/lib/libicui18n.so /usr/lib/libicui18n.so
        ln -sfn /usr/local/lib/libicuio.so   /usr/lib/libicuio.so
        ln -sfn /usr/local/lib/libicutest.so /usr/lib/libicutest.so
        ln -sfn /usr/local/lib/libicutu.so   /usr/lib/libicutu.so
        ln -sfn /usr/local/lib/libicuuc.so   /usr/lib/libicuuc.so
      fi
      ln -sfn /usr/lib/x86_64-linux-gnu/libgmp.so  /usr/lib/libgmp.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libgmp.so  /usr/lib/libgmp.so.3
      ln -sfn /usr/lib/x86_64-linux-gnu/libjpeg.so /usr/lib/libjpeg.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libkrb5.so /usr/lib/libkrb5.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libpng.so  /usr/lib/libpng.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libXpm.so  /usr/lib/libXpm.so
      ln -sfn /usr/lib/x86_64-linux-gnu/librtmp.so /usr/lib/librtmp.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libcurl.so /usr/lib/libcurl.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libwebpmux.so /usr/lib/libwebpmux.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libwebpmux.so /usr/lib/libwebpmux.so.2
      ln -sfn /usr/lib/x86_64-linux-gnu/libonig.so /usr/lib/libonig.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libonig.so /usr/lib/libonig.so.4
      ln -sfn /usr/lib/x86_64-linux-gnu/libsodium.so /usr/lib/libsodium.so
      ln -sfn /usr/lib/x86_64-linux-gnu/libsodium.so /usr/lib/libsodium.so.18
      if [ -e "/usr/lib/x86_64-linux-gnu/libwebp.so.7" ] \
        && [ ! -e "/usr/lib/x86_64-linux-gnu/libwebp.so.6" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libwebp.so.7 /usr/lib/x86_64-linux-gnu/libwebp.so.6
        ln -sfn /usr/lib/x86_64-linux-gnu/libwebp.so.7 /usr/lib/x86_64-linux-gnu/libwebp.so.6.0.2
        ln -sfn /usr/lib/x86_64-linux-gnu/libwebp.so.7 /usr/lib/libwebp.so.6
        ln -sfn /usr/lib/x86_64-linux-gnu/libwebp.so.7 /usr/lib/libwebp.so.6.0.2
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/liblber.so" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib/liblber.so
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/liblber.a" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/liblber.a /usr/lib/liblber.a
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/liblber-2.5.so.0" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/liblber-2.5.so.0 /usr/lib/liblber-2.5.so.0
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/liblber-2.4.so.2" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/liblber-2.4.so.2 /usr/lib/liblber-2.4.so.2
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libHalf.so.23" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libHalf.so.23 /usr/lib/libHalf.so.12
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libHalf.so" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libHalf.so /usr/lib/libHalf.so.12
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libIlmImf-2_2.so.23" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libIlmImf-2_2.so.23 /usr/lib/libIlmImf-2_2.so.22
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libIlmImf.so" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libIlmImf.so /usr/lib/libIlmImf-2_2.so.22
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libImath-2_2.so.23" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libImath-2_2.so.23 /usr/lib/libImath-2_2.so.12
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libImath.so" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libImath.so /usr/lib/libImath-2_2.so.12
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libIex-2_2.so.23" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libIex-2_2.so.23 /usr/lib/libIex-2_2.so.12
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libIex.so" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libIex.so /usr/lib/libIex-2_2.so.12
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libIexMath.so" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libIexMath.so /usr/lib/libIexMath-2_2.so.12
      fi
      if [ -e "/usr/lib/x86_64-linux-gnu/libIlmThread.so" ]; then
        ln -sfn /usr/lib/x86_64-linux-gnu/libIlmThread.so /usr/lib/libIlmThread-2_2.so.12
      fi
      if [ ! -e "/usr/include/curl/curl.h" ] \
        && [ -e "/usr/include/x86_64-linux-gnu/curl/curl.h" ]; then
        ln -s /usr/include/x86_64-linux-gnu/curl /usr/include/curl
      fi
      if [ ! -e "/usr/include/gmp.h" ] \
        && [ -e "/usr/include/x86_64-linux-gnu/gmp.h" ]; then
        ln -sfn /usr/include/x86_64-linux-gnu/gmp.h  /usr/include/gmp.h
      fi
      if [ ! -e "/usr/lib/x86_64-linux-gnu/librtmp.so.0" ] \
        && [ -e "/usr/lib/x86_64-linux-gnu/librtmp.so.1" ]; then
        cd /usr/lib/x86_64-linux-gnu
        ln -sfn librtmp.so.1 librtmp.so.0
      fi
    fi
    if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
      touch /var/xdrago_wait/log/.php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
      touch /var/xdrago_wait/log/.php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
    else
      touch /var/xdrago/log/.php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
      touch /var/xdrago/log/.php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
    fi
  fi
  ldconfig 2> /dev/null
}

smtp_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: smtp_check"
  fi
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

if_install_vnstat() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_vnstat"
  fi
  if [ ! -e "/run/cloud_vhost.pid" ]; then
    if [ ! -e "${pthLog}/vnstat-${_VNSTAT_VRN}.log" ] \
      || [ ! -e "/usr/bin/vnstat" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installing VnStat monitor..."
      fi
      cd /var/opt
      rm -rf vnstat*
      get_dev_src "vnstat-${_VNSTAT_VRN}.tar.gz"
      cd vnstat-${_VNSTAT_VRN}
      mrun "bash ./configure --prefix=/usr --sysconfdir=/etc" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      for INF in `vnstat --iflist \
        | sed "s/Available interfaces//g; s/(1000 Mbit)//g; s/(100 Mbit)//g; s/ lo//g;" \
        | cut -d: -f2` ;do vnstat -i $INF &> /dev/null;done
      cp -af /var/opt/vnstat-${_VNSTAT_VRN}/examples/init.d/debian/vnstat \
        /etc/init.d/vnstat
      chmod 755 /etc/init.d/vnstat &> /dev/null
      mrun "update-rc.d vnstat defaults" 2> /dev/null
      if [ -e "/usr/etc/vnstat.conf" ]; then
        sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /usr/etc/vnstat.conf
      fi
      if [ -e "/etc/vnstat.conf" ]; then
        sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /etc/vnstat.conf
      fi
      mrun "service vnstat start" 2> /dev/null
      mrun "killall vnstatd" 2> /dev/null
      touch ${pthLog}/vnstat-${_VNSTAT_VRN}.log
      mrun "service vnstat restart" 2> /dev/null
    fi
  fi
  if [ -e "/etc/init.d/vnstat" ] \
    && [ "${_VMFAMILY}" = "VS" ] \
    && [ ! -e "/boot/grub/grub.cfg" ] \
    && [ ! -e "/boot/grub/menu.lst" ]; then
    mrun "service vnstat stop" 2> /dev/null
    mrun "update-rc.d -f vnstat remove" 2> /dev/null
    rm -f /etc/init.d/vnstat
    rm -f /usr/bin/vnstat
    rm -rf /var/lib/vnstat
  fi
  if [ -e "/usr/etc/vnstat.conf" ]; then
    sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /usr/etc/vnstat.conf
    mrun "service vnstat restart" 2> /dev/null
  fi
}

install_myquick_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_myquick_src"
  fi
  if [ "${_MYQUICK_INSTALL_REQUIRED}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Building MyQuick ${_MYQUICK_VRN} from sources..."
    fi
    apt_clean_update
    mrun "${_INSTAPP} cmake" 2> /dev/null
    mrun "${_INSTAPP} libssl-dev" 2> /dev/null
    mrun "${_INSTAPP} libcurl4" 2> /dev/null
    mrun "${_INSTAPP} libcurl4-gnutls-dev" 2> /dev/null
    if [ "${_DB_SERVER}" = "Percona" ] && [ "${_DB_SERIES}" = "5.7" ]; then
      mrun "${_INSTAPP} libperconaserverclient20-dev" 2> /dev/null
    fi
    ldconfig 2> /dev/null
    cd /var/opt
    rm -rf mydumper*
    get_dev_src "mydumper-${_MYQUICK_VRN}.tar.gz"
    cd /var/opt/mydumper-${_MYQUICK_VRN}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
      export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
      LD_LIBRARY_PATH=/usr/local/lib:/usr/lib/x86_64-linux-gnu \
        cmake \
        -DWITH_SSL=ON \
        -DBUILD_DOCS=ON \
        -DCMAKE_C_FLAGS=-Wno-error=unused-function .
      mrun "make" 2> /dev/null
      mrun "make install" 2> /dev/null
    else
      export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH &> /dev/null
      export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH &> /dev/null
      LD_LIBRARY_PATH=/usr/local/lib:/usr/lib/x86_64-linux-gnu \
        cmake \
        -DWITH_SSL=ON \
        -DBUILD_DOCS=ON \
        -DCMAKE_C_FLAGS=-Wno-error=unused-function . &> /dev/null
      mrun "make --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
    fi
    ldconfig 2> /dev/null
    ssl_install_src
    ssl_crypto_lib_fix
  fi
}

myquick_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: myquick_install_upgrade"
  fi
  isMyQuick=$(which mydumper 2>&1)
  if [ ! -x "${isMyQuick}" ] \
    || [ -z "${isMyQuick}" ]; then
    install_myquick_src
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    _MYQUICK_UPGRADE_REQUIRED=NO
    _MYQUICK_ITD=$(mydumper -V 2>&1 \
      | tr -d "\n" \
      | tr -d "," \
      | tr -d "v" \
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
    if [ -x "${isMyQuick}" ]; then
      if [ "${_DB_V}" != "${_MD_V}" ]; then
        _MYQUICK_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installed MyQuick ${_MYQUICK_ITD} for ${_MD_V} (${_DB_V}), rebuild required"
        fi
        install_myquick_src
      elif [ "${_MYQUICK_ITD}" != "${_MYQUICK_VRN}" ]; then
        _MYQUICK_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installed MyQuick version ${_MYQUICK_ITD}, upgrade required"
        fi
        install_myquick_src
      fi
    fi
    if [ ! -e "${isMyQuick}" ]; then
      _MYQUICK_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: MyQuick ${_MYQUICK_VRN} not installed yet..."
      fi
      install_myquick_src
    fi
  fi
}

xdrago_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: xdrago_install_upgrade"
  fi
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
      ${vBs}/dragon/x/xdrago-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
    rm -f ${pthLog}/VISITOR_ABUSE_ONE.log
    rm -f ${pthLog}/blackIP.log
    rm -f /var/xdrago/{enableStatus,graceful,move_sql,run_all,second,Minute}
    rm -f /var/xdrago/{firewall.sh,stop-mysql-innodb.sh,firewall_restarter}
    rm -f /var/xdrago/{FireStart,memcache,redis}
    cp -af /var/spool/cron/crontabs/root \
      ${vBs}/dragon/z/cron-root-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
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
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
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
    sed -i "s/default_lines =.*/default_lines = 1999;/g" /var/xdrago/monitor/check/scan_nginx
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
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]]; then
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
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
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
    sed -i "s/default_lines =.*/default_lines = 1999;/g" /var/xdrago/monitor/check/scan_nginx
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
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]]; then
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
  if [ -d "/var/xdrago-pre-${_X_SE}-${_X_VERSION}-${_NOW}" ]; then
    cp -af /var/xdrago-pre-${_X_SE}-${_X_VERSION}-${_NOW}/run-* /var/xdrago/ &> /dev/null
  fi
  sed -i "s/firewall/monitor/g" /var/xdrago/minute.sh &> /dev/null
  wait
  chmod -R 700 /var/xdrago/monitor/check &> /dev/null
  chmod 700 /var/xdrago/* &> /dev/null
  chmod 700 /var/xdrago &> /dev/null
}

pam_umask_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: pam_umask_check_fix"
  fi
  _PAM_UMASK_TEST=$(grep "pam_umask.so umask=0002" /etc/pam.d/login 2>&1)
  if [[ ! "${_PAM_UMASK_TEST}" =~ "pam_umask.so umask=0002" ]]; then
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
    sed -i "s/.*session.*optional.*pam_umask.*//g" /etc/pam.d/login &> /dev/null
    wait
    echo "session optional pam_umask.so umask=0002" >> /etc/pam.d/login
    wait
    echo "umask 002" >> /var/www/.profile
    chown www-data:www-data /var/www/.profile &> /dev/null
    chown www-data:www-data /var/www/nginx-default &> /dev/null
  fi
  _SFTP_UMASK_TEST=$(grep "sftp-server -u 0002" /etc/ssh/sshd_config 2>&1)
  if [[ ! "${_SFTP_UMASK_TEST}" =~ "sftp-server -u 0002" ]]; then
    sed -e '/Subsystem\ssftp/s:server$:server -u 0002:' -i /etc/ssh/sshd_config
    mrun "service ssh restart" 2> /dev/null
  fi
}

pam_many_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: pam_many_check_fix"
  fi
  _PAM_FIX=NO
  _PAM_MAIL_LOGIN_TEST=$(grep "pam_mail" /etc/pam.d/login 2>&1)
  _PAM_MAIL_SSHD_TEST=$(grep "pam_mail" /etc/pam.d/sshd 2>&1)
  _PAM_MOTD_LOGIN_TEST=$(grep "pam_motd" /etc/pam.d/login 2>&1)
  _PAM_MOTD_SSHD_TEST=$(grep "pam_motd" /etc/pam.d/sshd 2>&1)
  if [[ "${_PAM_MAIL_LOGIN_TEST}" =~ "pam_mail" ]] \
    || [[ "${_PAM_MAIL_LOGIN_TEST}" =~ "pam_mail" ]]; then
    _PAM_FIX=YES
  fi
  if [[ "${_PAM_MOTD_LOGIN_TEST}" =~ "pam_motd" ]] \
    || [[ "${_PAM_MOTD_SSHD_TEST}" =~ "pam_motd" ]]; then
    _PAM_FIX=YES
  fi
  if [ "${_PAM_FIX}" = "YES" ]; then
    sed -i "s/.*session.*optional.*pam_mail.*//g" /etc/pam.d/login &> /dev/null
    wait
    sed -i "s/.*session.*optional.*pam_mail.*//g" /etc/pam.d/sshd &> /dev/null
    wait
    sed -i "s/.*session.*optional.*pam_motd.*//g" /etc/pam.d/login &> /dev/null
    wait
    sed -i "s/.*session.*optional.*pam_motd.*//g" /etc/pam.d/sshd &> /dev/null
  fi
}

fix_node_in_lshell_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_node_in_lshell_access"
  fi
  if [ "${_STATUS}" = "UPGRADE" ] && [ -e "/etc/lshell.conf" ]; then
    PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
    PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
    if [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
      || [[ "${PrTestCluster}" =~ "CLUSTER" ]] \
      || [ -e "/root/.allow.node.lshell.cnf" ]; then
      _ALLOW_NODE=YES
    else
      _ALLOW_NODE=NO
      sed -i "s/, 'node',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'node',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'npm',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'npm',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'npx',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'npx',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'find',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'find',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'scp',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'scp',/,/g" /var/xdrago/conf/lshell.conf
      wait
    fi
  fi
}

lshell_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: lshell_install_upgrade"
  fi
  _PATH_LSHELL="/usr/local/bin/lshell"
  if [ ! -e "${_PATH_LSHELL}" ] \
    || [ ! -e "${pthLog}/lshell-build-${_LSHELL_VRN}.log" ] \
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
    rm -rf /usr/local/lib/python3.4/dist-packages/lshell*
    rm -rf /usr/local/lib/python3.5/dist-packages/lshell*
    rm -rf /usr/local/lib/python3.9/dist-packages/lshell*
    rm -rf /usr/local/lib/python3.11/dist-packages/lshell*
    isPythonTwo=$(which python2 2>&1)
    isPythonThree=$(which python3 2>&1)
    if [ -x "${isPythonThree}" ]; then
      usePyth=python3
    elif [ -x "${isPythonTwo}" ]; then
      usePyth=python2
    fi
    mrun "${usePyth} setup.py install --no-compile" 2> /dev/null
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
    touch ${pthLog}/lshell-build-${_LSHELL_VRN}.log
    if [ -f "/var/xdrago/manage_ltd_users.sh" ]; then
      if [ "${_STATUS}" = "UPGRADE" ] \
        && [ "${_CUSTOM_CONFIG_LSHELL}" = "NO" ]; then
        cp -af ${bldPth}/aegir/tools/system/conf/lshell.conf \
          /var/xdrago/conf/lshell.conf
      fi
      st_runner "bash /var/xdrago/manage_ltd_users.sh" &> /dev/null
    fi
    fix_node_in_lshell_access
  fi
  if [ -f "/usr/local/bin/lshell" ]; then
    if [ ! -L "/usr/bin/lshell" ]; then
      ln -sfn /usr/local/bin/lshell /usr/bin/lshell &> /dev/null
    fi
  fi
}

if_install_ftpd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_ftpd"
  fi
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_XTRAS_LIST}" =~ "FTP" ]]; then
    if [ ! -e "/var/ftp" ]; then
      mrun "useradd -r -d /var/ftp -s /sbin/nologin -m ftp" 2> /dev/null
    fi
    if [ ! -e "/etc/ssl/private/pure-ftpd.pem" ] \
      || [ ! -e "/usr/local/sbin/pure-ftpd" ] \
      || [ ! -e "${pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_X_SE}-${_X_VERSION}.log" ] \
      || [ ! -e "/etc/ssl/private/pure-ftpd-dhparams.pem" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
      msg "INFO: Building Pure-FTPd server from sources..."
      sed -i "/^$/d" /etc/ld.so.conf.d/libc.conf &> /dev/null
      if [ ! -e "/etc/ssl/private/pure-ftpd-dhparams.pem" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Generating DH parameters, 2048 bit..."
        fi
        mrun "openssl dhparam -out /etc/ssl/private/pure-ftpd-dhparams.pem 2048" 2> /dev/null
        wait
      fi
      if [ ! -e "/usr/local/sbin/pure-config.pl" ]; then
        echo "/bin/false" >> /etc/shells
        echo "/bin/true" >> /etc/shells
      fi
      mkdir -p /etc/ssl/private/
      rm -f /etc/ssl/private/pure-ftpd.pem
      rm -f /usr/local/sbin/pure-ftpd
      openssl req -x509 -nodes -sha256 -days 7300 -newkey rsa:2048 \
        -keyout /etc/ssl/private/pure-ftpd.pem \
        -out /etc/ssl/private/pure-ftpd.pem -batch &> /dev/null
      chmod 600 /etc/ssl/private/pure-ftpd.pem &> /dev/null
      cd /var/opt
      rm -rf pure-ftpd*
      mkdir -p /usr/local/etc
      get_dev_src "pure-ftpd-${_PURE_FTPD_VRN}.tar.gz"
      cd pure-ftpd-${_PURE_FTPD_VRN}
      bash autogen.sh &> /dev/null
      LIBS="-ldl -lpthread" PKG_CONFIG_PATH="/usr/local/ssl3/lib64/pkgconfig" ./configure \
        --oldincludedir=/usr/local/ssl3/include \
        --includedir=/usr/local/ssl3/include \
        --with-everything --with-virtualchroot \
        --without-humor --with-tls --with-diraliases --with-pam \
        --with-certfile=/etc/ssl/private/pure-ftpd.pem &> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      mrun "make --quiet install" 2> /dev/null
      cd /usr/local/sbin/
      cp -af ${locCnf}/ftpd/pure-config.pl.txt ./
      mv -f pure-config.pl.txt pure-config.pl 2> /dev/null
      chmod 755 /usr/local/sbin/pure-config.pl 2> /dev/null
      cp -af /var/opt/pure-ftpd-${_PURE_FTPD_VRN}/pam/pure-ftpd /etc/pam.d/
      fix_ftps_pam
      cd /usr/local/etc
      rm -f pure-ftpd.conf
      cp -af ${locCnf}/ftpd/pure-ftpd.conf ./
      ln -sfn /usr/local/etc/pure-ftpd.conf /usr/local/etc/pure-ftpd.conf~
      killall -9 pure-ftpd &> /dev/null
      ftpdInit="/usr/local/sbin/pure-config.pl"
      ftpdConf="/usr/local/etc/pure-ftpd.conf"
      ftpdBind="/usr/local/sbin/pure-ftpd"
      if [ -x "${ftpdBind}" ] && [ -f "${ftpdConf}" ]; then
        if [ -x "${ftpdInit}" ]; then
          ${ftpdInit} ${ftpdConf} &> /dev/null
        else
          ${ftpdBind} ${ftpdConf} &> /dev/null
        fi
      fi
      cd /var/opt
      touch ${pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_X_SE}-${_X_VERSION}.log
    fi
  fi
}

newrelic_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: newrelic_check_fix"
  fi
  _NR_FORCE_REINSTALL=NO
  _NRS_TEST=$(which newrelic-daemon 2>&1)
  if [ ! -z "${_NRS_TEST}" ]; then
    _NOW_NR_V=$(newrelic-daemon --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f5 \
      | awk '{ print $1}' \
      | cut -d"-" -f1 \
      | awk '{ print $1}' 2>&1)
  fi
  if [ ! -z "${_NOW_NR_V}" ]; then
    if [ "${_NOW_NR_V}" != "${_NEW_RELIC_VRN}" ]; then
      _NR_FORCE_REINSTALL=YES
    fi
  else
    _NR_FORCE_REINSTALL=YES
  fi
  if [ "${_UP_NRC}" = "YES" ] \
    || [ "${_NR_FORCE_REINSTALL}" = "YES" ] \
    || [ -e /root/.force.newrelic.update.cnf ]; then
    newrelic_update
  fi
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
    mrun "service newrelic-daemon restart" 2> /dev/null
  else
    if [ -e "/etc/init.d/newrelic-daemon" ] \
      || [ -e "/etc/init.d/newrelic-sysmond" ]; then
      mrun "service newrelic-daemon stop" 2> /dev/null
      mrun "update-rc.d -f newrelic-daemon remove" 2> /dev/null
      mrun "service newrelic-sysmond stop" 2> /dev/null
      mrun "update-rc.d -f newrelic-sysmond remove" 2> /dev/null
      st_runner "${_RMAPP} newrelic-php5 \
        newrelic-php5-common \
        newrelic-daemon \
        newrelic-sysmond" 2> /dev/null
      mv -f /etc/newrelic \
        ${vBs}/nr/etc-newrelic-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
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
      mrun "service newrelic-sysmond restart" 2> /dev/null
    else
      mrun "service newrelic-sysmond stop" 2> /dev/null
    fi
  fi
}

java_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: java_check_fix"
  fi

  if [ "${_OS_CODE}" = "jessie" ]; then
    if [ ! -e "/usr/lib/jvm/java-7-openjdk" ] \
      && [ -d "/usr/lib/jvm/java-7-openjdk-amd64" ]; then
      ln -sfn /usr/lib/jvm/java-7-openjdk-amd64 /usr/lib/jvm/java-7-openjdk
    fi
    if [ ! -e "/usr/bin/java7" ] \
      && [ -e "/usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java" ]; then
      ln -sfn /usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java /usr/bin/java7
    fi
    if [ -e "/usr/lib/jvm/java-1.7.0-openjdk-amd64" ]; then
      rm -f /usr/lib/jvm/default-java
      ln -sfn /usr/lib/jvm/java-1.7.0-openjdk-amd64 /usr/lib/jvm/default-java
    fi
    if [ -x "/usr/lib/jvm/java-7-openjdk/jre/bin/java" ]; then
      ln -sfn /usr/lib/jvm/java-7-openjdk/jre/bin/java /etc/alternatives/java
      ln -sfn /etc/alternatives/java /usr/bin/java
    fi
  fi

  if [ ! -e "/usr/lib/jvm/java-8-openjdk" ] \
    && [ -d "/usr/lib/jvm/java-8-openjdk-amd64" ]; then
    ln -sfn /usr/lib/jvm/java-8-openjdk-amd64 /usr/lib/jvm/java-8-openjdk
  fi
  if [ ! -e "/usr/bin/java8" ] \
    && [ -e "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" ]; then
    ln -sfn /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java /usr/bin/java8
  fi
  if [ -e "/usr/lib/jvm/java-1.8.0-openjdk-amd64" ]; then
    rm -f /usr/lib/jvm/default-java
    ln -sfn /usr/lib/jvm/java-1.8.0-openjdk-amd64 /usr/lib/jvm/default-java
  fi
  if [ -x "/usr/lib/jvm/java-8-openjdk/jre/bin/java" ]; then
    ln -sfn /usr/lib/jvm/java-8-openjdk/jre/bin/java /etc/alternatives/java
    ln -sfn /etc/alternatives/java /usr/bin/java
  fi

  if [ "${_OS_CODE}" = "daedalus" ] || [ "${_OS_CODE}" = "bookworm" ]; then
    if [ ! -e "/usr/lib/jvm/java-11-openjdk" ] \
      && [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
      ln -sfn /usr/lib/jvm/java-11-openjdk-amd64 /usr/lib/jvm/java-11-openjdk
    fi
    if [ ! -e "/usr/bin/java11" ] \
      && [ -e "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" ]; then
      ln -sfn /usr/lib/jvm/java-11-openjdk-amd64/bin/java /usr/bin/java11
    fi
    if [ -e "/usr/lib/jvm/java-1.11.0-openjdk-amd64" ]; then
      rm -f /usr/lib/jvm/default-java
      ln -sfn /usr/lib/jvm/java-1.11.0-openjdk-amd64 /usr/lib/jvm/default-java
    fi
    if [ -x "/usr/lib/jvm/java-11-openjdk/bin/java" ]; then
      ln -sfn /usr/lib/jvm/java-11-openjdk/bin/java /etc/alternatives/java
      ln -sfn /etc/alternatives/java /usr/bin/java
    fi
  else
    if [ ! -e "/usr/lib/jvm/java-11-openjdk" ] \
      && [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
      ln -sfn /usr/lib/jvm/java-11-openjdk-amd64 /usr/lib/jvm/java-11-openjdk
    fi
    if [ ! -e "/usr/bin/java11" ] \
      && [ -e "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" ]; then
      ln -sfn /usr/lib/jvm/java-11-openjdk-amd64/bin/java /usr/bin/java11
    fi
    if [ -e "/usr/lib/jvm/java-1.11.0-openjdk-amd64" ]; then
      rm -f /usr/lib/jvm/default-java
      ln -sfn /usr/lib/jvm/java-1.11.0-openjdk-amd64 /usr/lib/jvm/default-java
    fi
    if [ -x "/usr/lib/jvm/java-11-openjdk/bin/java" ]; then
      ln -sfn /usr/lib/jvm/java-11-openjdk/bin/java /etc/alternatives/java
      ln -sfn /etc/alternatives/java /usr/bin/java
    fi
  fi
}

sshd_armour() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sshd_armour"
  fi
  ###
  ### See: https://stribika.github.io/2015/01/04/secure-secure-shell.html
  ### Also: https://github.com/stribika/stribika.github.io/wiki/Secure-Secure-Shell
  ###
  if [ -e "/etc/ssh/sshd_config" ]; then
    if [ "${_SSH_ARMOUR}" = "NO" ] \
      || [ -z "${_SSH_ARMOUR}" ]; then
      if [ -e "/etc/ssh/.vanilla.sshd_config" ]; then
        mv -f /etc/ssh/.vanilla.sshd_config /etc/ssh/sshd_config
      fi
      if [ -e "/etc/ssh/.vanilla.ssh_config" ]; then
        mv -f /etc/ssh/.vanilla.ssh_config /etc/ssh/ssh_config
      fi
    else
      if [ ! -e "/etc/ssh/.vanilla.sshd_config" ]; then
        cp -a /etc/ssh/sshd_config /etc/ssh/.vanilla.sshd_config
      fi
      if [ ! -e "/etc/ssh/.vanilla.ssh_config" ]; then
        cp -a /etc/ssh/ssh_config /etc/ssh/.vanilla.ssh_config
      fi
      _SSH_PROTOCOL_TEST=$(grep "Protocol" /etc/ssh/sshd_config 2>&1)
      if [[ "${_SSH_PROTOCOL_TEST}" =~ (^)"Protocol 2" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_PROTOCOL_TEST}" =~ "Protocol" ]]; then
        sed -i "s/.*Protocol.*/Protocol 2/g" /etc/ssh/sshd_config &> /dev/null
        wait
      else
        echo >> /etc/ssh/sshd_config
        echo "Protocol 2" >> /etc/ssh/sshd_config
      fi
      _SSH_ALGO_TEST=$(grep "KexAlgorithms" /etc/ssh/sshd_config 2>&1)
      if [[ "${_SSH_ALGO_TEST}" =~ (^)"KexAlgorithms curve25519-sha256" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_ALGO_TEST}" =~ "KexAlgorithms" ]]; then
        sed -i "s/.*KexAlgorithms.*//g" /etc/ssh/sshd_config &> /dev/null
        wait
        echo "KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /etc/ssh/sshd_config
      else
        echo >> /etc/ssh/sshd_config
        echo "KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /etc/ssh/sshd_config
      fi
      _SSH_CIPHERS_TEST=$(grep "Ciphers" /etc/ssh/sshd_config 2>&1)
      if [[ "${_SSH_CIPHERS_TEST}" =~ (^)"Ciphers chacha20-poly1305" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_CIPHERS_TEST}" =~ "Ciphers" ]]; then
        sed -i "s/.*Ciphers.*//g" /etc/ssh/sshd_config &> /dev/null
        wait
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
      else
        echo >> /etc/ssh/sshd_config
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
      fi
      _SSH_MACS_TEST=$(grep "MACs" /etc/ssh/sshd_config 2>&1)
      if [[ "${_SSH_MACS_TEST}" =~ (^)"MACs hmac-sha2-512-etm" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_MACS_TEST}" =~ "MACs" ]]; then
        sed -i "s/.*MACs.*//g" /etc/ssh/sshd_config &> /dev/null
        wait
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /etc/ssh/sshd_config
      else
        echo >> /etc/ssh/sshd_config
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /etc/ssh/sshd_config
      fi
      _SSH_HKEY_TEST=$(grep "HostKey" /etc/ssh/sshd_config 2>&1)
      if [[ "${_SSH_HKEY_TEST}" =~ (^)"HostKey" ]] \
        && [[ "${_SSH_HKEY_TEST}" =~ "ssh_host_ed25519_key" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_HKEY_TEST}" =~ "HostKey" ]]; then
        sed -i "s/.*HostKey.*//g" /etc/ssh/sshd_config &> /dev/null
        wait
        echo "HostKey /etc/ssh/ssh_host_ed25519_key" >> /etc/ssh/sshd_config
        echo "HostKey /etc/ssh/ssh_host_rsa_key" >> /etc/ssh/sshd_config
      else
        echo >> /etc/ssh/sshd_config
        echo "HostKey /etc/ssh/ssh_host_ed25519_key" >> /etc/ssh/sshd_config
        echo "HostKey /etc/ssh/ssh_host_rsa_key" >> /etc/ssh/sshd_config
      fi
      if [ ! -e "/etc/ssh/.ssh_host_ed25519_key.pid" ]; then
        mkdir -p /var/backups/sshd
        mv -f /etc/ssh/ssh_host_*key* /var/backups/sshd/
        msg "INFO: Generating new ssh_host_ed25519_key..."
        ssh-keygen -t ed25519 -N "" -q -f /etc/ssh/ssh_host_ed25519_key < /dev/null
        touch /etc/ssh/.ssh_host_ed25519_key.pid
      fi
      if [ ! -e "/etc/ssh/.ssh_host_rsa_key4096.pid" ]; then
        msg "INFO: Generating new ssh_host_rsa_key..."
        ssh-keygen -t rsa -b 4096 -N "" -q -f /etc/ssh/ssh_host_rsa_key < /dev/null
        touch /etc/ssh/.ssh_host_rsa_key4096.pid
        msg "NOTE: You will be asked to accept the new SSH fingerprint the next time you connect"
      fi
      isKeyg=$(which ssh-keygen 2>&1)
      if [ -x "${isKeyg}" ] \
        && [ -e "${_SYSCONFDIR}/moduli" ] \
        && [ ! -e "${_SYSCONFDIR}/.moduli_bak" ]; then
        msg "WAIT: New SSH moduli generate may take a long time, please wait..."
        cd /var/opt
        rm -rf /var/opt/moduli-*
        mrun "${isKeyg} -M generate -O bits=2048 moduli-2048.candidates" 2> /dev/null
        wait
        mrun "${isKeyg} -M screen -f moduli-2048.candidates moduli-2048" 2> /dev/null
        wait
        if [ -e "/var/opt/moduli-2048" ]; then
          cp -af ${_SYSCONFDIR}/moduli ${_SYSCONFDIR}/.moduli_bak
          cp -af /var/opt/moduli-2048 ${_SYSCONFDIR}/moduli
          mrun "service ssh restart" 2> /dev/null
        fi
      fi
      _SSH_KEXALGO_TEST=$(grep "KexAlgorithms" /etc/ssh/ssh_config 2>&1)
      if [[ "${_SSH_KEXALGO_TEST}" =~ "KexAlgorithms curve25519-sha256" ]]; then
        _DO_NOTHING=YES
      elif [[ "${_SSH_KEXALGO_TEST}" =~ "KexAlgorithms" ]]; then
        sed -i "s/.*PubkeyAuthentication.*//g" /etc/ssh/ssh_config &> /dev/null
        wait
        sed -i "s/.*UseRoaming.*//g" /etc/ssh/ssh_config &> /dev/null
        wait
        sed -i "s/.*Ciphers.*//g" /etc/ssh/ssh_config &> /dev/null
        wait
        sed -i "s/.*HostKeyAlgorithms.*//g" /etc/ssh/ssh_config &> /dev/null
        wait
        sed -i "s/.*KexAlgorithms.*//g" /etc/ssh/ssh_config &> /dev/null
        wait
        sed -i "s/.*MACs.*//g" /etc/ssh/ssh_config &> /dev/null
        wait
        echo >> /etc/ssh/ssh_config
        echo "Host *" >> /etc/ssh/ssh_config
        echo "  PubkeyAuthentication yes" >> /etc/ssh/ssh_config
        echo "  UseRoaming no" >> /etc/ssh/ssh_config
        echo "  Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/ssh_config
        echo "  HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa" >> /etc/ssh/ssh_config
        echo "  KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /etc/ssh/ssh_config
        echo "  MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /etc/ssh/ssh_config
      else
        echo >> /etc/ssh/ssh_config
        echo "Host *" >> /etc/ssh/ssh_config
        echo "  PubkeyAuthentication yes" >> /etc/ssh/ssh_config
        echo "  UseRoaming no" >> /etc/ssh/ssh_config
        echo "  Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/ssh_config
        echo "  HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa" >> /etc/ssh/ssh_config
        echo "  KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /etc/ssh/ssh_config
        echo "  MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com" >> /etc/ssh/ssh_config
      fi
    fi
    mrun "service ssh reload" 2> /dev/null
  fi
}

initd_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: initd_update"
  fi
  _THIS_DB_PORT=3306
  if [ "${_STATUS}" = "INIT" ]; then
    msg "INFO: Updating init scripts"
    cp -af ${locCnf}/var/clean-boa-env /etc/init.d/clean-boa-env
    chmod 755 /etc/init.d/clean-boa-env &> /dev/null
    mrun "update-rc.d clean-boa-env defaults" 2> /dev/null
    _SSH_USEDNS_TEST=$(grep "UseDNS" /etc/ssh/sshd_config 2>&1)
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
    _SSH_USEPAM_TEST=$(grep "UsePAM" /etc/ssh/sshd_config 2>&1)
    if [[ "${_SSH_USEPAM_TEST}" =~ (^)"UsePAM no" ]]; then
      _DO_NOTHING=YES
    elif [[ "${_SSH_USEPAM_TEST}" =~ "UsePAM" ]]; then
      sed -i "s/.*UsePAM.*/UsePAM no/g" /etc/ssh/sshd_config &> /dev/null
      wait
    else
      echo >> /etc/ssh/sshd_config
      echo "UsePAM no" >> /etc/ssh/sshd_config
    fi
    mrun "service ssh reload" 2> /dev/null
    tune_memory_limits
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Solr 7"
      fi
      kill -9 $(ps aux | grep '[s]olr' | awk '{print $2}') &> /dev/null
      mrun "service solr7 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Jetty 9"
      fi
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      mrun "service jetty9 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Jetty 8"
      fi
      kill -9 $(ps aux | grep '[j]etty8' | awk '{print $2}') &> /dev/null
      mrun "service jetty8 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Jetty 7"
      fi
      kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
      mrun "service jetty7 start" 2> /dev/null
    fi
    if [ ! -e "/run/aegir_upgrade.pid" ]; then
      msg "INFO: Starting Redis, PHP-FPM and Nginx"
      mrun "service redis-server start" 2> /dev/null
      mrun "service redis-server reload" 2> /dev/null
      mrun "update-rc.d -f php5-fpm remove" 2> /dev/null
      mrun "update-rc.d cron defaults" 2> /dev/null
      _PHP_V="83 82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          mrun "update-rc.d php${e}-fpm defaults" 2> /dev/null
          mrun "service php${e}-fpm start" 2> /dev/null
        fi
      done
      mrun "update-rc.d nginx defaults" 2> /dev/null
      mrun "service nginx start" 2> /dev/null
    fi
  else
    if [[ "${_THISHOST}" =~ ".host8." ]] \
      || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
      || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
      || [ -e "/root/.ssh.root.auth.keys.only.cnf" ]; then
      sed -i "s/^#PermitRootLogin.*/PermitRootLogin prohibit-password/g" \
        /etc/ssh/sshd_config &> /dev/null
      wait
      sed -i "s/^PermitRootLogin.*/PermitRootLogin prohibit-password/g" \
        /etc/ssh/sshd_config &> /dev/null
      wait
    fi
    sed -i "s/.*UseDNS.*//g" /etc/ssh/sshd_config &> /dev/null
    wait
    sed -i "s/.*UsePAM.*//g" /etc/ssh/sshd_config &> /dev/null
    wait
    sed -i "s/.*PrintMotd.*//g" /etc/ssh/sshd_config &> /dev/null
    wait
    sed -i "s/^ClientAliveCountMax.*//g" /etc/ssh/sshd_config &> /dev/null
    wait
    sed -i "s/^ClientAliveInterval.*//g" /etc/ssh/sshd_config &> /dev/null
    wait
    sed -i "s/^IgnoreUserKnownHosts.*//g" /etc/ssh/sshd_config &> /dev/null
    wait
    sed -i "s/^PasswordAuthentication.*//g" /etc/ssh/sshd_config &> /dev/null
    wait
    sed -i "s/^TCPKeepAlive.*//g" /etc/ssh/sshd_config &> /dev/null
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
    echo "PrintMotd yes" >> /etc/ssh/sshd_config
    echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
    echo "ClientAliveCountMax 10000" >> /etc/ssh/sshd_config
    echo "TCPKeepAlive yes" >> /etc/ssh/sshd_config
    sed -i "/^$/d" /etc/ssh/sshd_config
    wait
    mrun "service ssh reload" 2> /dev/null
    fix_on_upgrade
    tune_memory_limits
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Solr 7"
      fi
      kill -9 $(ps aux | grep '[s]olr' | awk '{print $2}') &> /dev/null
      mrun "service solr7 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Jetty 9"
      fi
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      mrun "service jetty9 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Jetty 8"
      fi
      kill -9 $(ps aux | grep '[j]etty8' | awk '{print $2}') &> /dev/null
      mrun "service jetty8 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Restarting Jetty 7"
      fi
      kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
      mrun "service jetty7 start" 2> /dev/null
    fi
    if [ ! -e "/run/aegir_upgrade.pid" ] \
      && [ ! -e "/root/.proxy.cnf" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Reloading Redis, PHP-FPM and Nginx..."
      fi
      mrun "update-rc.d -f php5-fpm remove" 2> /dev/null
      mrun "service redis-server reload" 2> /dev/null
      _PHP_V="83 82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          mrun "update-rc.d php${e}-fpm defaults" 2> /dev/null
        fi
      done
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          mrun "service php${e}-fpm reload" 2> /dev/null
        fi
      done
      mrun "service nginx quietupgrade" 2> /dev/null
      _DB_SERVER_TEST=$(mysql -V 2>&1)
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib ${_DB_SERIES}." ]]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Running ${_DB_SERVER} system tables (2) upgrade..."
        fi
        rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
        if [ -x "/usr/bin/mysql_upgrade" ]; then
          _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
          _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
          mrun "mysql_upgrade -u root --force" &> /dev/null
          mrun "mysql_upgrade -u root --force" &> /dev/null
        fi
      fi
      myCnf="/etc/mysql/my.cnf"
      preCnf="${vBs}/dragon/t/my.cnf-pre-${_X_SE}-${_X_VERSION}-${_NOW}"
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
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: ${_DB_SERVER} diff0 empty"
          fi
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
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: ${_DB_SERVER} ${_DBS_VRN} already up to date"
          fi
          myCnfUpdate=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: ${_DB_SERVER} restart after upgrade forced"
          fi
        fi
      fi
      if [ ! -e "/root/.run-to-daedalus.cnf" ] \
        && [ ! -e "/root/.run-to-chimaera.cnf" ] \
        && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
        _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
        _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
        myUptime=$(mysqladmin -u root version | grep -i uptime 2>&1)
        myUptime=$(echo -n ${myUptime} | fmt -su -w 2500 2>&1)
        msg "INFO: ${_DB_SERVER} ${myUptime}"
        if [ "${myRstrd}" = "YES" ]; then
          myCnfUpdate=NO
          msg "INFO: ${_DB_SERVER} already restarted!"
        fi
        if [ "${myCnfUpdate}" = "YES" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Restarting ${_DB_SERVER} server..."
          fi
          mysql -u root -e "INSTALL SONAME 'ha_archive';" &> /dev/null
          mrun "bash /var/xdrago/move_sql.sh" &> /dev/null
          wait
          msg "INFO: ${_DB_SERVER} server restart completed"
        fi
        if [[ "${_DB_SERIES}" =~ "5.7" ]]; then
          _CHECK_EXISTS=$(mysql -u root -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'drandom_2test')" | grep "0" 2>&1)
          if [[ "${_CHECK_EXISTS}" =~ "0" ]]; then
            _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              echo _CHECK_REPAIR 1 ${_CHECK_REPAIR}
            fi
            if [[ "${_CHECK_REPAIR}" =~ "corrupted" ]]; then
              mysqlcheck -u root -A --auto-repair --silent
              mysql_upgrade -u root --force
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN default_role;"
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN is_role;"
              mysql -u root -e "ALTER TABLE mysql.user DROP COLUMN max_statement_time;"
              mysql_upgrade -u root --force
            fi
            _CHECK_REPAIR=$(mysql -u root -e "CREATE USER IF NOT EXISTS 'drandom_2test'@'localhost';" 2>&1)
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              echo _CHECK_REPAIR 2 ${_CHECK_REPAIR}
            fi
          fi
          mysql -u root -e "SET GLOBAL innodb_flush_log_at_trx_commit=2;" &> /dev/null
          mysql -u root -e "SET GLOBAL innodb_flush_log_at_timeout=5;" &> /dev/null
          mysql -u root -e "SET GLOBAL show_compatibility_56=ON;" &> /dev/null
          mysql -u root -e "SET GLOBAL innodb_stats_on_metadata=0;" &> /dev/null
          rm -f /etc/mysql/conf.d/mysqldump.cnf
        fi
      fi
    fi
  fi
}

sysctl_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sysctl_update"
  fi
  if [ ! -e "/root/.no.sysctl.update.cnf" ] \
    && [ ! -e "${pthLog}/sysctl.conf-${_X_SE}-${_X_VERSION}-${_NOW}.log" ]; then
    cp -af /etc/sysctl.conf \
      ${vBs}/dragon/t/sysctl.conf-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
    if [ -e "${locCnf}/var/sysctl.conf" ]; then
      cp -af ${locCnf}/var/sysctl.conf /etc/sysctl.conf
    fi
    if [ -e "/etc/security/limits.conf" ]; then
      _IF_NF=$(grep '2097152' /etc/security/limits.conf 2>&1)
      if [ ! -z "${_IF_NF}" ]; then
        sed -i "s/.*2097152.*//g" /etc/security/limits.conf
        wait
      fi
      _IF_NF=$(grep '524288' /etc/security/limits.conf 2>&1)
      if [ -z "${_IF_NF}" ]; then
        echo "*         hard    nofile      524288"  >> /etc/security/limits.conf
        echo "*         soft    nofile      524288"  >> /etc/security/limits.conf
        echo "root      hard    nofile      1048576" >> /etc/security/limits.conf
        echo "root      soft    nofile      1048576" >> /etc/security/limits.conf
      fi
      _IF_NF=$(grep '65556' /etc/security/limits.conf 2>&1)
      if [ -z "${_IF_NF}" ]; then
        echo "*         hard    nproc       65556"   >> /etc/security/limits.conf
        echo "*         soft    nproc       65556"   >> /etc/security/limits.conf
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
    if [ -e "/etc/default/nginx" ]; then
      _IF_ULNX=$(grep '524288' /etc/default/nginx 2>&1)
      if [ -z "${_IF_ULNX}" ]; then
        sed -i "s/^ULIMIT=.*//gi" /etc/default/nginx
        wait
        echo ULIMIT=\"-n 524288\" >> /etc/default/nginx
        ulimit -n 524288 &> /dev/null
        service nginx restart &> /dev/null
      fi
    fi
    if [ -e "/etc/security/limits.d" ] \
      && [ ! -e "/etc/security/limits.d/sshd.conf" ]; then
      echo "sshd soft nofile 524288" > /etc/security/limits.d/sshd.conf
      echo "sshd hard nofile 999999" >> /etc/security/limits.d/sshd.conf
      echo "redis soft nofile 65535" > /etc/security/limits.d/redis.conf
      echo "redis hard nofile 524288" >> /etc/security/limits.d/redis.conf
      echo "nginx soft nofile 524288" > /etc/security/limits.d/nginx.conf
      echo "nginx hard nofile 999999" >> /etc/security/limits.d/nginx.conf
      echo "jetty9 soft nofile 65535" > /etc/security/limits.d/jetty9.conf
      echo "jetty9 hard nofile 524288" >> /etc/security/limits.d/jetty9.conf
      echo "solr7 soft nofile 65535" > /etc/security/limits.d/solr7.conf
      echo "solr7 hard nofile 524288" >> /etc/security/limits.d/solr7.conf
      echo "@www-data soft nofile 65535" > /etc/security/limits.d/www.conf
      echo "@www-data hard nofile 524288" >> /etc/security/limits.d/www.conf
      mrun "service redis-server restart" 2> /dev/null
      mrun "service nginx restart" 2> /dev/null
      mrun "service sshd restart" 2> /dev/null
      _PHP_V="83 82 81 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          mrun "service php${e}-fpm reload" 2> /dev/null
        fi
      done
    fi
    touch ${pthLog}/sysctl.conf-${_X_SE}-${_X_VERSION}-${_NOW}.log
  fi
}

apticron_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: apticron_update"
  fi
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
        mrun "apt-get remove apticron -y --purge --auto-remove -qq" 2> /dev/null
        mrun "apt-get install apticron -y" 2> /dev/null
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
    barUpv="${tRee}"
    sed -i "s/aptitude full-upgrade/barracuda up-${barUpv} system/g" /usr/sbin/apticron
      wait
    sed -i "s/apt-get dist-upgrade/barracuda up-${barUpv} system/g" /usr/sbin/apticron
      wait
    sed -i "s/barracuda up-${tRee}.*/barracuda up-${barUpv} system/g" /usr/sbin/apticron
  fi
}

rsyslog_config_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: rsyslog_config_update"
  fi
  if [ -x "/etc/init.d/rsyslog" ] \
    && [ -e "/etc/rsyslog.conf" ]; then
    mv -f /etc/rsyslog.conf \
      /var/backups/.etc.rsyslog.conf-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${locCnf}/var/rsyslog.conf /etc/rsyslog.conf
    cp -af ${locCnf}/var/logrotate.d.rsyslog.conf /etc/logrotate.d/rsyslog
    mrun "service rsyslog restart" 2> /dev/null
  fi
}

complete() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: complete"
  fi
  fix_lfd_whitelist
  fix_lfd_uidignore
  fix_cnf_postfix
  re_set_default_php_cli
  if [ -d "/data/u" ]; then
    composer_install_upgrade
  fi
  if [ "${_STATUS}" != "UPGRADE" ]; then
    _STRICT_BIN_PERMISSIONS=NO
  fi
  if [ "${_STRICT_BIN_PERMISSIONS}" = "YES" ]; then
    usermod -aG users _apt &> /dev/null
    usermod -aG users aegir &> /dev/null
    usermod -aG users bin &> /dev/null
    usermod -aG users daemon &> /dev/null
    usermod -aG users man &> /dev/null
    usermod -aG users mysql &> /dev/null
    usermod -aG users nobody &> /dev/null
    usermod -aG users root &> /dev/null
    usermod -aG users sync &> /dev/null
    usermod -aG users sys &> /dev/null
    if [ -x "/bin/dash" ] || [ -x "/usr/bin/dash" ]; then
      symlink_to_dash
      switch_to_dash
    elif [ -x "/bin/bash" ] || [ -x "/usr/bin/bash" ]; then
      symlink_to_bash
      switch_to_bash
    fi
    strict_bin_permissions
    rm -f /etc/apt/apt.conf.d/00sandboxtmp
    rm -f /etc/apt/apt.conf.d/00temp
  fi
  finale
}
