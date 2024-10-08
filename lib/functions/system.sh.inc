
export _tRee=dev

_if_fix_iptables_symlinks() {
  ###
  ### Fix for iptables paths backward compatibility
  ###
  if [ -x "/sbin/iptables" ] && [ ! -e "/usr/sbin/iptables" ]; then
    ln -s /sbin/iptables /usr/sbin/iptables
  fi
  if [ -x "/usr/sbin/iptables" ] && [ ! -e "/sbin/iptables" ]; then
    ln -s /usr/sbin/iptables /sbin/iptables
  fi
  if [ -x "/sbin/iptables-save" ] && [ ! -e "/usr/sbin/iptables-save" ]; then
    ln -s /sbin/iptables-save /usr/sbin/iptables-save
  fi
  if [ -x "/usr/sbin/iptables-save" ] && [ ! -e "/sbin/iptables-save" ]; then
    ln -s /usr/sbin/iptables-save /sbin/iptables-save
  fi
  if [ -x "/sbin/iptables-restore" ] && [ ! -e "/usr/sbin/iptables-restore" ]; then
    ln -s /sbin/iptables-restore /usr/sbin/iptables-restore
  fi
  if [ -x "/usr/sbin/iptables-restore" ] && [ ! -e "/sbin/iptables-restore" ]; then
    ln -s /usr/sbin/iptables-restore /sbin/iptables-restore
  fi
  if [ -x "/sbin/ip6tables" ] && [ ! -e "/usr/sbin/ip6tables" ]; then
    ln -s /sbin/ip6tables /usr/sbin/ip6tables
  fi
  if [ -x "/usr/sbin/ip6tables" ] && [ ! -e "/sbin/ip6tables" ]; then
    ln -s /usr/sbin/ip6tables /sbin/ip6tables
  fi
  if [ -x "/sbin/ip6tables-save" ] && [ ! -e "/usr/sbin/ip6tables-save" ]; then
    ln -s /sbin/ip6tables-save /usr/sbin/ip6tables-save
  fi
  if [ -x "/usr/sbin/ip6tables-save" ] && [ ! -e "/sbin/ip6tables-save" ]; then
    ln -s /usr/sbin/ip6tables-save /sbin/ip6tables-save
  fi
  if [ -x "/sbin/ip6tables-restore" ] && [ ! -e "/usr/sbin/ip6tables-restore" ]; then
    ln -s /sbin/ip6tables-restore /usr/sbin/ip6tables-restore
  fi
  if [ -x "/usr/sbin/ip6tables-restore" ] && [ ! -e "/sbin/ip6tables-restore" ]; then
    ln -s /usr/sbin/ip6tables-restore /sbin/ip6tables-restore
  fi
  ###
  ### Fix for iptables paths backward compatibility
  ###
}

#
# Re-install curl if broken.
_if_reinstall_curl_src() {
  _CURL_VRN=8.9.1
  if ! command -v lsb_release &> /dev/null; then
    apt-get update -qq &> /dev/null
    apt-get install lsb-release -y -qq &> /dev/null
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  [ "${_OS_CODE}" = "wheezy" ] && _CURL_VRN=7.50.1
  [ "${_OS_CODE}" = "jessie" ] && _CURL_VRN=7.71.1
  [ "${_OS_CODE}" = "stretch" ] && _CURL_VRN=8.2.1
  _isCurl=$(curl --version 2>&1)
  if [[ ! "${_isCurl}" =~ "OpenSSL" ]] || [ -z "${_isCurl}" ]; then
    _msg "OOPS: cURL is broken! Re-installing.."
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    echo "curl install" | dpkg --set-selections 2> /dev/null
    _apt_clean_update
    apt-get remove libssl1.0-dev -y --purge --auto-remove -qq 2> /dev/null
    apt-get autoremove -y 2> /dev/null
    apt-get install libssl-dev -y -qq 2> /dev/null
    apt-get install libc-client2007e libc-client2007e-dev -y -qq 2> /dev/null
    apt-get build-dep curl -y 2> /dev/null
    if [ ! -e "/var/aegir/drush" ]; then
      apt-get install curl --reinstall -y -qq 2> /dev/null
    fi
    if [ -e "/var/aegir/drush" ]; then
      _msg "INFO: Installing curl from sources..."
      mkdir -p /var/opt
      rm -rf /var/opt/curl*
      cd /var/opt
      wget -q -U iCab http://files.aegir.cc/dev/src/curl-${_CURL_VRN}.tar.gz &> /dev/null
      tar -xzf curl-${_CURL_VRN}.tar.gz &> /dev/null
      if [ -e "/root/.install.modern.openssl.cnf" ] \
        && [ -x "/usr/local/ssl3/bin/openssl" ]; then
        _SSL_BINARY=/usr/local/ssl3/bin/openssl
      else
        _SSL_BINARY=/usr/local/ssl/bin/openssl
      fi
      if [ -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
        _SSL_PATH="/usr/local/ssl3"
        _SSL_LIB_PATH="${_SSL_PATH}/lib64"
      else
        _SSL_PATH="/usr/local/ssl"
        _SSL_LIB_PATH="${_SSL_PATH}/lib"
      fi
      _PKG_CONFIG_PATH="${_SSL_LIB_PATH}/pkgconfig"

      if [ -e "${_PKG_CONFIG_PATH}" ] \
        && [ -e "/var/opt/curl-${_CURL_VRN}" ]; then
        cd /var/opt/curl-${_CURL_VRN}
        LIBS="-ldl -lpthread" PKG_CONFIG_PATH="${_PKG_CONFIG_PATH}" ./configure \
          --with-openssl \
          --with-zlib=/usr \
          --prefix=/usr/local &> /dev/null
        make -j $(nproc) --quiet &> /dev/null
        make --quiet install &> /dev/null
        ldconfig 2> /dev/null
      fi
    fi
    if [ -f "/usr/local/bin/curl" ]; then
      _isCurl=$(/usr/local/bin/curl --version 2>&1)
      if [[ ! "${_isCurl}" =~ "OpenSSL" ]] || [ -z "${_isCurl}" ]; then
        _msg "ERRR: /usr/local/bin/curl is broken"
      else
        _msg "GOOD: /usr/local/bin/curl works"
      fi
    fi
  fi
}

#
# Install sysvinit with apt.
_sysvinit_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sysvinit_install"
  fi
  _apt_clean_update
  echo "sysvinit-core install" | dpkg --set-selections &> /dev/null
  echo "sysvinit-utils install" | dpkg --set-selections &> /dev/null
  _mrun "${_INITINS} sysvinit-core" 2> /dev/null
  _mrun "${_INITINS} sysvinit-utils" 2> /dev/null
  echo "sysvinit-core hold" | dpkg --set-selections &> /dev/null
  echo "sysvinit-utils hold" | dpkg --set-selections &> /dev/null
}

#
# Remove systemd with apt.
_systemd_remove_apt_cmd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _systemd_remove_apt_cmd"
  fi
  _apt_clean_update
  _mrun "apt-get remove systemd -y --purge --auto-remove --allow-remove-essential -qq" 2> /dev/null
  _mrun "apt-get remove libnss-systemd -y --purge --auto-remove --allow-remove-essential -qq" 2> /dev/null
  _mrun "apt-get remove systemd-sysv -y --purge --auto-remove --allow-remove-essential -qq" 2> /dev/null
  _mrun "apt-get autoremove --purge -y --purge --auto-remove -qq" 2> /dev/null
  _mrun "apt-get autoclean -y --purge --auto-remove -qq" 2> /dev/null
  _mrun "apt-get autoremove -y --purge --auto-remove -qq" 2> /dev/null
  _apt_clean_update
}

#
# Detect and prepare for major OS upgrade.
_define_loc_osr() {
  _apt_clean_update_no_releaseinfo_change
  _mrun "apt-get upgrade ${_nrmUpArg}" 2> /dev/null
  _mrun "apt-get install lsb-release ${_nrmUpArg}" 2> /dev/null
  _OS_DIST=$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _define_loc_osr"
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
    [ ! -e "/root/.top-daedalus.cnf" ] && touch /root/.top-daedalus.cnf
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
    [ ! -e "/root/.top-daedalus.cnf" ] && touch /root/.top-daedalus.cnf
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
_if_to_do_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_to_do_fix"
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
_count_cpu() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _count_cpu"
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
_if_running_as_root_barracuda() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_running_as_root_barracuda"
  fi
  if [ `whoami` = "root" ]; then
    chmod a+w /dev/null
    rm -rf /tmp/drush_make_tmp*
    rm -rf /tmp/make_tmp*
    rm -f /tmp/pm-updatecode*
    rm -f /tmp/cache.inc*
    touch /run/boa_run.pid
    mkdir -p ${_pthLog}
    find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
    # Check if dmidecode is available
    if ! command -v dmidecode &> /dev/null; then
      _apt_clean_update
      ${_INITINS} dmidecode &> /dev/null
    fi
    # Check for Amazon EC2 in the system manufacturer field
    if dmidecode -s system-manufacturer | grep -i 'Amazon EC2' &> /dev/null; then
      _VMFAMILY="AWS"
    fi
    _VM_TEST=$(uname -a 2>&1)
    if [[ "${_VM_TEST}" =~ "-beng" ]]; then
      _VMFAMILY="VS"
      touch /run/cloud_vhost.pid
      if [ ! -e "/etc/apt/preferences.d/fuse" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: fuse\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/fuse
        _apt_clean_update
      fi
      if [ ! -e "/etc/apt/preferences.d/udev" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: udev\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/udev
        _apt_clean_update
      fi
      if [ ! -e "/etc/apt/preferences.d/makedev" ]; then
        mkdir -p /etc/apt/preferences.d/
        echo -e 'Package: makedev\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/makedev
        _apt_clean_update
      fi
      _mrun "apt-get remove fuse -y --purge --auto-remove -qq" 2> /dev/null
      _mrun "apt-get remove udev -y --purge --auto-remove -qq" 2> /dev/null
      _mrun "apt-get remove makedev -y --purge --auto-remove -qq" 2> /dev/null
      if [ -e "/sbin/hdparm" ]; then
        _mrun "apt-get remove hdparm -y --purge --auto-remove -qq" 2> /dev/null
      fi
      if [ -d "/etc/webmin" ]; then
        _mrun "dpkg --configure --force-all -a" 2> /dev/null
        _apt_clean_update
        _mrun "apt-get remove webmin -y --purge --auto-remove -qq" 2> /dev/null
        rm -rf /usr/share/webmin
      fi
      rm -f /etc/apt/sources.list.d/ksplice.list
      rm -f /etc/apt/sources.list.d/longview.list
      rm -f /etc/apt/sources.list.d/webmin.list
    fi
    sleep 1
  else
    _msg "ERROR: This script should be run as a root user"
    _clean_pid_exit _if_running_as_root_barracuda_a
  fi
}

#
# Set xterm.
_set_xterm() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _set_xterm"
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
_kill_nash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _kill_nash"
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
_fix_postfix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_postfix"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _mrun "apt-get remove exim4 -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove exim4-base -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove exim4-config -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove sendmail -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove sendmail-base -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove sendmail-bin -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove sendmail-cf -y --purge --auto-remove -qq" 2> /dev/null
    rm -f /etc/aliases
    rm -rf /etc/mail
    killall -9 sendmail &> /dev/null
  else
    _POSTFIX_TEST=$(grep "fatal: open lock file" /var/log/mail.log 2>&1)
    if [[ "${_POSTFIX_TEST}" =~ "fatal: open lock file" ]]; then
      _mrun "dpkg --configure --force-all -a" 2> /dev/null
      _apt_clean_update
      _mrun "apt-get remove postfix -y -qq" 2> /dev/null
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
_fix_ftps_pam() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_ftps_pam"
  fi
  if [ ! -e "/etc/ftpusers" ]; then
    cp -af ${_locCnf}/ftpd/ftpusers /etc/ftpusers
  fi
  sed -i "s/pam_stack.so/pam_unix.so/g" /etc/pam.d/pure-ftpd &> /dev/null
  wait
  sed -i "s/ service=system-auth//g"    /etc/pam.d/pure-ftpd &> /dev/null
  wait
}

#
# Fix FTPS and SFTP access on modern systems.
_sftp_ftps_modern_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sftp_ftps_modern_fix"
  fi
  _LSHELL_PATH_TEST=$(grep "/usr/bin/lshell" /etc/shells 2>&1)
  if [[ ! "${_LSHELL_PATH_TEST}" =~ "/usr/bin/lshell" ]]; then
    echo "/usr/bin/lshell" >> /etc/shells
  fi
  if [ ! -e "${_pthLog}/mss-build-${_MSS_VRN}-${_xSrl}-${_X_VERSION}.log" ] \
    || [ ! -e "/etc/ssh/sftp_config" ] \
    || [ ! -e "/usr/bin/mysecureshell" ] \
    || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    if [ "${_MSS_BUILD}" != "YES" ]; then
      _msg "INFO: Installing MySecureShell ${_MSS_VRN}..."
      cd /var/opt
      rm -rf mysecureshell*
      _get_dev_src "mysecureshell-${_MSS_VRN}.tar.gz"
      cd /var/opt/mysecureshell
      _mrun "bash ./configure" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _st_runner "sh ./install.sh yesall" 2> /dev/null
      touch ${_pthLog}/mss-build-${_MSS_VRN}-${_xSrl}-${_X_VERSION}.log
      cp -af ${_locCnf}/var/sftp_config /etc/ssh/sftp_config
      _mrun "service ssh restart" 2> /dev/null
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
  if [ ! -e "${_pthLog}/fixed-sftp-idle.log" ]; then
    sed -i "s/IdleTimeOut.*/IdleTimeOut            15m/g" /etc/ssh/sftp_config &> /dev/null
    _mrun "service ssh reload" 2> /dev/null
    touch ${_pthLog}/fixed-sftp-idle.log
  fi
}

#
# Disable Old Purge Cruft Machine.
_disable_old_purge_cruft_machine() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _disable_old_purge_cruft_machine"
  fi
  _if_hosted_sys
  if [ "${_hostedSys}" = "YES" ]; then
    sed -i "s/.*purge_cruft.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "/^$/d" /etc/crontab &> /dev/null
    wait
  fi
}

#
# Update BOA INI templates.
_boa_ini_tpl_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _boa_ini_tpl_update"
  fi
  mkdir -p /data/conf
  if [ -e "${_locCnf}/ini/default.boa_platform_control.ini" ]; then
    cp -af ${_locCnf}/ini/default.boa_platform_control.ini /data/conf/default.boa_platform_control.ini
    rm -f /var/xdrago/conf/default.boa_platform_control.ini
  fi
  if [ -e "${_locCnf}/ini/default.boa_site_control.ini" ]; then
    cp -af ${_locCnf}/ini/default.boa_site_control.ini /data/conf/default.boa_site_control.ini
    rm -f /var/xdrago/conf/default.boa_site_control.ini
  fi
}

#
# Update global.inc Config.
_global_inc_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _global_inc_conf_update"
  fi
  _GL_D=/data/conf/global
  [ ! -d "${_GL_D}" ] && mkdir -p ${_GL_D}
  _DR_V="11 10 9 8 7 6"
  for e in ${_DR_V}; do
    if [ -e "${_GL_D}/global-${e}.inc" ]; then
      cp -af ${_GL_D}/global-${e}.inc ${_GL_D}/global-${e}.inc-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    fi
    cp -af ${_locCnf}/global/global-${e}.inc ${_GL_D}/global-${e}.inc
  done
  cp -af /data/conf/global.inc /data/conf/global.inc-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
  cp -af ${_locCnf}/global/global.inc /data/conf/global.inc
  if [ ! -z "${_SPEED_VALID_MAX}" ]; then
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" /data/conf/global.inc &> /dev/null
    wait
  fi
  cp -af ${_locCnf}/global/global-main.inc ${_GL_D}/global-main.inc
  cp -af ${_locCnf}/global/global-ini.inc ${_GL_D}/global-ini.inc
  cp -af ${_locCnf}/global/global-mode.inc ${_GL_D}/global-mode.inc
  cp -af ${_locCnf}/global/global-settings.inc ${_GL_D}/global-settings.inc
  cp -af ${_locCnf}/global/global-front-end.inc ${_GL_D}/global-front-end.inc
  if [ ! -z "${_SPEED_VALID_MAX}" ]; then
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" ${_GL_D}/global-front-end.inc &> /dev/null
  fi
  cp -af ${_locCnf}/global/global-if-redis.inc ${_GL_D}/global-if-redis.inc
  cp -af ${_locCnf}/global/global-redis.inc ${_GL_D}/global-redis.inc
  cp -af ${_locCnf}/global/global-newrelic.inc ${_GL_D}/global-newrelic.inc
  cp -af ${_locCnf}/global/global-extra.inc ${_GL_D}/global-extra.inc
}

#
# Fix this on upgrade.
_fix_on_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_on_upgrade"
  fi
  sed -i "s/loglevel.*/loglevel warning/g" /etc/redis/redis.conf &> /dev/null
  sed -i "s/^TLS.*/TLS 2/g" /usr/local/etc/pure-ftpd.conf &> /dev/null
  cp -af ${_locCnf}/var/clean-boa-env /etc/init.d/clean-boa-env
  chmod 755 /etc/init.d/clean-boa-env &> /dev/null
  _mrun "update-rc.d clean-boa-env defaults" 2> /dev/null
  _kill_nash
  _sftp_ftps_modern_fix
  _fix_ftps_pam
  _disable_old_purge_cruft_machine
  _php_config_check_update
  _nginx_conf_update
  _global_inc_conf_update
  _redis_password_update
}

#
# Tune memory limits for PHP, Nginx and Percona.
_tune_memory_limits() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _tune_memory_limits"
  fi
  _count_cpu

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
  else
    _PHP_FPM_TIMEOUT=180
  fi
  _MXC_SQL=$(( _L_PHP_FPM_WORKERS * 4 ))
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _L_PHP_FPM_WORKERS is ${_L_PHP_FPM_WORKERS}"
    _msg "TUNE: _PHP_FPM_TIMEOUT is ${_PHP_FPM_TIMEOUT}"
    _msg "TUNE: _MXC_SQL is ${_MXC_SQL}"
  fi

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
  # Check if dmidecode is available
  if ! command -v dmidecode &> /dev/null; then
    _apt_clean_update
    ${_INITINS} dmidecode &> /dev/null
  fi
  # Check for Amazon EC2 in the system manufacturer field
  if dmidecode -s system-manufacturer | grep -i 'Amazon EC2' &> /dev/null; then
    _VMFAMILY="AWS"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _VMFAMILY is ${_VMFAMILY}"
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
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]]; then
    if [ "${_CPU_VS}" -lt "8" ]; then
      _CPU_VS=8
    fi
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _PrTestPower is ${_PrTestPower}"
    _msg "TUNE: _PrTestPhantom is ${_PrTestPhantom}"
    _msg "TUNE: _PrTestCluster is ${_PrTestCluster}"
  fi
  _RAM=$(free -mt | grep Mem: | awk '{ print $2 }' 2>&1)
  if [ "${_RESERVED_RAM}" -gt "0" ]; then
    _RAM=$(( _RAM - _RESERVED_RAM ))
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _CPU_NR is ${_CPU_NR}"
    _msg "TUNE: _CPU_MX is ${_CPU_MX}"
    _msg "TUNE: _CPU_TG is ${_CPU_TG}"
    _msg "TUNE: _CPU_VS is ${_CPU_VS}"
    _msg "TUNE: _RAM is ${_RAM}"
    _msg "TUNE: _RESERVED_RAM is ${_RESERVED_RAM}"
  fi
  _USE=$(( _RAM / 4 ))
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _USE is ${_USE}"
  fi
  _if_hosted_sys
  if [ "${_VMFAMILY}" = "VS" ] \
    || [ "${_hostedSys}" = "YES" ]; then
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _USE_SQL is ${_USE_SQL}"
    _msg "TUNE: _TMP_SQL is ${_TMP_SQL}"
    _msg "TUNE: _SRT_SQL is ${_SRT_SQL}"
  fi
  if [ "${_USE}" -ge "512" ] && [ "${_USE}" -lt "2048" ]; then
    _USE_PHP=1024
    _USE_OPC=1024
    _USE_CLI=2048
    _QCE_SQL=64M
    _RND_SQL=8M
    _JBF_SQL=4M
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _CPU_NR is ${_CPU_NR}"
    _msg "TUNE: _L_NGX_WRKS is ${_L_NGX_WRKS}"
    _msg "TUNE: _PHP_FPM_WORKERS is ${_PHP_FPM_WORKERS}"
    _msg "TUNE: _L_PHP_FPM_WORKERS is ${_L_PHP_FPM_WORKERS}"
    _msg "TUNE: _USE_PHP is ${_USE_PHP}"
    _msg "TUNE: _USE_OPC is ${_USE_OPC}"
    _msg "TUNE: _USE_CLI is ${_USE_CLI}"
    _msg "TUNE: _QCE_SQL is ${_QCE_SQL}"
    _msg "TUNE: _RND_SQL is ${_RND_SQL}"
    _msg "TUNE: _JBF_SQL is ${_JBF_SQL}"
    _msg "TUNE: _MXC_SQL is ${_MXC_SQL}"
  fi
  if [ ! -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
    mkdir -p /var/xdrago/conf
  fi
  if [ ! -e "/data/conf" ]; then
    mkdir -p /data/conf
  fi
  cp -af ${_locCnf}/php/fpm-pool-foo-multi.conf /var/xdrago/conf/
  cp -af ${_locCnf}/php/fpm-pool-foo.conf /var/xdrago/conf/
  cp -af ${_locCnf}/hhvm /var/xdrago/conf/
  cp -af ${_locCnf}/hhvm/hhvm_intercept.php /data/conf/hhvm_intercept.php
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
    _tune_sql_memory_limits
    _sql_conf_update
    if [[ "${_PrTestPower}" =~ "POWER" ]] \
      || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
      || [ -e "/root/.my.cluster_root_pwd.txt" ] \
      || [[ "${_PrTestCluster}" =~ "CLUSTER" ]]; then
      _UXC_SQL="${_MXC_SQL}"
    else
      _UXC_SQL=$(echo "scale=0; ${_MXC_SQL}/2" | bc 2>&1)
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "TUNE: _UXC_SQL is ${_UXC_SQL}"
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _MAX_MEM_REDIS is ${_MAX_MEM_REDIS}"
    _msg "TUNE: _MAX_REDIS is ${_MAX_REDIS}"
  fi

  _USE_JETTY_MEM=$(( _RAM / 8 ))
  _USE_JETTY="-Xmx${_USE_JETTY_MEM}m"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _USE_JETTY_MEM is ${_USE_JETTY_MEM}"
    _msg "TUNE: _USE_JETTY is ${_USE_JETTY}"
  fi
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "TUNE: _USE_SOLR_MEM is ${_USE_SOLR_MEM}"
    _msg "TUNE: _USE_SOLR is ${_USE_SOLR}"
  fi
  if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
    sed -i "s/^SOLR_HEAP/#SOLR_HEAP/g" /etc/default/solr7.in.sh &> /dev/null
    wait
    sed -i "s/^#SOLR_JAVA_MEM/SOLR_JAVA_MEM/g" /etc/default/solr7.in.sh &> /dev/null
    wait
    sed -i "s/^SOLR_JAVA_MEM=.*/SOLR_JAVA_MEM=\"-Xms64m ${_USE_SOLR}\"/g" /etc/default/solr7.in.sh
    wait
  fi
  _tune_web_server_config
}

#
# Find server city.
_find_server_city() {
  if [ ! -e "/root/.dont.use.fancy.bash.login.cnf" ]; then
    if [ -e "/root/.found_correct_city.cnf" ]; then
      _LOC_CITY=$(cat /root/.found_correct_city.cnf 2>&1)
      _LOC_CITY=$(echo -n ${_LOC_CITY} | tr -d "\n" 2>&1)
    else
      if [ -e "/root/.found_correct_ipv4.cnf" ]; then
        _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>&1)
        _LOC_CITY=$(curl ${_crlGet} ipinfo.io/${_LOC_IP}/city 2>&1)
        _LOC_CITY=$(echo -n ${_LOC_CITY} | tr -d "\n" 2>&1)
      fi
      if [ ! -z "${_LOC_CITY}" ]; then
        _LOC_CITY=$(echo "${_LOC_CITY}" | tr ' ' '+' 2>&1)
        echo ${_LOC_CITY} > /root/.found_correct_city.cnf
      fi
    fi
  fi
}

#
# Fix locales.
_locales_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _locales_check_fix"
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
    _msg "NOTE!"
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
    if [ -e "${_locCnf}/var/boa.bashrc.txt" ]; then
      cp -af /root/.bashrc /root/.bashrc.bak.${_NOW}
      cp -af ${_locCnf}/var/boa.bashrc.txt /root/.bashrc
      _set_xterm
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
    if [ -e "${_locCnf}/var/boa.bashrc.txt" ]; then
      cp -af /root/.bashrc /root/.bashrc.bak.${_NOW}
      cp -af ${_locCnf}/var/boa.bashrc.txt /root/.bashrc
      _set_xterm
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
_barracuda_cnf_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _barracuda_cnf_cleanup"
  fi
  ###
  ### legacy config cleanup start
  ###
  _DB_ENGINE_TEST=$(grep _DB_ENGINE ${_barCnf} 2>&1)
  if [[ "${_DB_ENGINE_TEST}" =~ "_DB_ENGINE" ]]; then
    sed -i "s/^_DB_ENGINE.*//g" ${_barCnf}
    wait
  fi
  _INNODB_LOG_FILE_SIZE_TEST=$(grep _INNODB_LOG_FILE_SIZE ${_barCnf} 2>&1)
  if [[ "${_INNODB_LOG_FILE_SIZE_TEST}" =~ "_INNODB_LOG_FILE_SIZE" ]]; then
    sed -i "s/^_INNODB_LOG_FILE_SIZE.*//g" ${_barCnf}
    wait
  fi
  _USE_STOCK_TEST=$(grep _USE_STOCK ${_barCnf} 2>&1)
  if [[ "${_USE_STOCK_TEST}" =~ "_USE_STOCK" ]]; then
    sed -i "s/^_USE_STOCK.*//g" ${_barCnf}
    wait
  fi
  _HTTP_WILDCARD_TEST=$(grep _HTTP_WILDCARD ${_barCnf} 2>&1)
  if [[ "${_HTTP_WILDCARD_TEST}" =~ "_HTTP_WILDCARD" ]]; then
    sed -i "s/^_HTTP_WILDCARD.*//g" ${_barCnf}
    wait
  fi
  _PHP_MODERN_ONLY_TEST=$(grep _PHP_MODERN_ONLY ${_barCnf} 2>&1)
  if [[ "${_PHP_MODERN_ONLY_TEST}" =~ "_PHP_MODERN_ONLY" ]]; then
    sed -i "s/^_PHP_MODERN_ONLY.*//g" ${_barCnf}
    wait
  fi
  _USE_SPEED_BOOSTER_TEST=$(grep _USE_SPEED_BOOSTER ${_barCnf} 2>&1)
  if [[ "${_USE_SPEED_BOOSTER_TEST}" =~ "_USE_SPEED_BOOSTER" ]]; then
    sed -i "s/^_USE_SPEED_BOOSTER.*//g" ${_barCnf}
    wait
  fi
  _PHP_INSTALL_NEW_TEST=$(grep _PHP_INSTALL_NEW ${_barCnf} 2>&1)
  if [[ "${_PHP_INSTALL_NEW_TEST}" =~ "_PHP_INSTALL_NEW" ]]; then
    sed -i "s/^_PHP_INSTALL_NEW.*//g" ${_barCnf}
    wait
  fi
  _CUSTOM_CONFIG_PHP_TEST=$(grep _CUSTOM_CONFIG_PHP ${_barCnf} 2>&1)
  if [[ "${_CUSTOM_CONFIG_PHP_TEST}" =~ "_CUSTOM_CONFIG_PHP" ]]; then
    sed -i "s/^_CUSTOM_CONFIG_PHP.*//g" ${_barCnf}
    wait
  fi
  _LOAD_LIMIT_ONE_TEST=$(grep _LOAD_LIMIT_ONE ${_barCnf} 2>&1)
  if [[ "${_LOAD_LIMIT_ONE_TEST}" =~ "_LOAD_LIMIT_ONE" ]]; then
    sed -i "s/^_LOAD_LIMIT_ONE.*//g" ${_barCnf}
    wait
  fi
  _LOAD_LIMIT_TWO_TEST=$(grep _LOAD_LIMIT_TWO ${_barCnf} 2>&1)
  if [[ "${_LOAD_LIMIT_TWO_TEST}" =~ "_LOAD_LIMIT_TWO" ]]; then
    sed -i "s/^_LOAD_LIMIT_TWO.*//g" ${_barCnf}
    wait
  fi
  _USE_MEMCACHED_TEST=$(grep _USE_MEMCACHED ${_barCnf} 2>&1)
  if [[ "${_USE_MEMCACHED_TEST}" =~ "_USE_MEMCACHED" ]]; then
    sed -i "s/^_USE_MEMCACHED.*//g" ${_barCnf}
    wait
  fi
  _PHP_ZEND_OPCACHE_TEST=$(grep _PHP_ZEND_OPCACHE ${_barCnf} 2>&1)
  if [[ "${_PHP_ZEND_OPCACHE_TEST}" =~ "_PHP_ZEND_OPCACHE" ]]; then
    sed -i "s/^_PHP_ZEND_OPCACHE.*//g" ${_barCnf}
    wait
  fi
  _BUILD_FROM_SRC_TEST=$(grep _BUILD_FROM_SRC ${_barCnf} 2>&1)
  if [[ "${_BUILD_FROM_SRC_TEST}" =~ "_BUILD_FROM_SRC" ]]; then
    sed -i "s/^_BUILD_FROM_SRC.*//g" ${_barCnf}
    wait
  fi
  _SSL_FROM_SOURCES_TEST=$(grep _SSL_FROM_SOURCES ${_barCnf} 2>&1)
  if [[ "${_SSL_FROM_SOURCES_TEST}" =~ "_SSL_FROM_SOURCES" ]]; then
    sed -i "s/^_SSL_FROM_SOURCES.*//g" ${_barCnf}
    wait
  fi
  ###
  ### legacy config cleanup end
  ###

  ###
  ### config cleanup start
  ###
  _NGX_FORCE_REINSTALL_TEST=$(grep _NGX_FORCE_REINSTALL ${_barCnf} 2>&1)
  if [[ "${_NGX_FORCE_REINSTALL_TEST}" =~ "_NGX_FORCE_REINSTALL" ]]; then
    sed -i "s/^_NGX_FORCE_REINSTALL.*//g" ${_barCnf}
    wait
  fi
  _PHP_FORCE_REINSTALL_TEST=$(grep _PHP_FORCE_REINSTALL ${_barCnf} 2>&1)
  if [[ "${_PHP_FORCE_REINSTALL_TEST}" =~ "_PHP_FORCE_REINSTALL" ]]; then
    sed -i "s/^_PHP_FORCE_REINSTALL.*//g" ${_barCnf}
    wait
  fi
  _SQL_FORCE_REINSTALL_TEST=$(grep _SQL_FORCE_REINSTALL ${_barCnf} 2>&1)
  if [[ "${_SQL_FORCE_REINSTALL_TEST}" =~ "_SQL_FORCE_REINSTALL" ]]; then
    sed -i "s/^_SQL_FORCE_REINSTALL.*//g" ${_barCnf}
    wait
  fi
  _SSL_FORCE_REINSTALL_TEST=$(grep _SSL_FORCE_REINSTALL ${_barCnf} 2>&1)
  if [[ "${_SSL_FORCE_REINSTALL_TEST}" =~ "_SSL_FORCE_REINSTALL" ]]; then
    sed -i "s/^_SSL_FORCE_REINSTALL.*//g" ${_barCnf}
    wait
  fi
  _SSH_FORCE_REINSTALL_TEST=$(grep _SSH_FORCE_REINSTALL ${_barCnf} 2>&1)
  if [[ "${_SSH_FORCE_REINSTALL_TEST}" =~ "_SSH_FORCE_REINSTALL" ]]; then
    sed -i "s/^_SSH_FORCE_REINSTALL.*//g" ${_barCnf}
    wait
  fi
  _GIT_FORCE_REINSTALL_TEST=$(grep _GIT_FORCE_REINSTALL ${_barCnf} 2>&1)
  if [[ "${_GIT_FORCE_REINSTALL_TEST}" =~ "_GIT_FORCE_REINSTALL" ]]; then
    sed -i "s/^_GIT_FORCE_REINSTALL.*//g" ${_barCnf}
    wait
  fi
  _FULL_FORCE_REINSTALL_TEST=$(grep _FULL_FORCE_REINSTALL ${_barCnf} 2>&1)
  if [[ "${_FULL_FORCE_REINSTALL_TEST}" =~ "_FULL_FORCE_REINSTALL" ]]; then
    sed -i "s/^_FULL_FORCE_REINSTALL.*//g" ${_barCnf}
    wait
  fi
  _TOMCAT_TO_JETTY_TEST=$(grep _TOMCAT_TO_JETTY ${_barCnf} 2>&1)
  if [[ "${_TOMCAT_TO_JETTY_TEST}" =~ "_TOMCAT_TO_JETTY" ]]; then
    if [ ! -e "/etc/init.d/tomcat" ]; then
      sed -i "s/^_TOMCAT_TO_JETTY.*//g" ${_barCnf}
      wait
    fi
  fi
  _BOOKWORM_TO_DAEDALUS_TEST=$(grep _BOOKWORM_TO_DAEDALUS ${_barCnf} 2>&1)
  if [[ "${_BOOKWORM_TO_DAEDALUS_TEST}" =~ "_BOOKWORM_TO_DAEDALUS" ]]; then
    sed -i "s/^_BOOKWORM_TO_DAEDALUS.*//g" ${_barCnf}
    wait
  fi
  _CHIMAERA_TO_DAEDALUS_TEST=$(grep _CHIMAERA_TO_DAEDALUS ${_barCnf} 2>&1)
  if [[ "${_CHIMAERA_TO_DAEDALUS_TEST}" =~ "_CHIMAERA_TO_DAEDALUS" ]]; then
    sed -i "s/^_CHIMAERA_TO_DAEDALUS.*//g" ${_barCnf}
    wait
  fi
  _BULLSEYE_TO_CHIMAERA_TEST=$(grep _BULLSEYE_TO_CHIMAERA ${_barCnf} 2>&1)
  if [[ "${_BULLSEYE_TO_CHIMAERA_TEST}" =~ "_BULLSEYE_TO_CHIMAERA" ]]; then
    sed -i "s/^_BULLSEYE_TO_CHIMAERA.*//g" ${_barCnf}
    wait
  fi
  _BULLSEYE_TO_BOOKWORM_TEST=$(grep _BULLSEYE_TO_BOOKWORM ${_barCnf} 2>&1)
  if [[ "${_BULLSEYE_TO_BOOKWORM_TEST}" =~ "_BULLSEYE_TO_BOOKWORM" ]]; then
    sed -i "s/^_BULLSEYE_TO_BOOKWORM.*//g" ${_barCnf}
    wait
  fi
  _BEOWULF_TO_CHIMAERA_TEST=$(grep _BEOWULF_TO_CHIMAERA ${_barCnf} 2>&1)
  if [[ "${_BEOWULF_TO_CHIMAERA_TEST}" =~ "_BEOWULF_TO_CHIMAERA" ]]; then
    sed -i "s/^_BEOWULF_TO_CHIMAERA.*//g" ${_barCnf}
    wait
  fi
  _BUSTER_TO_BEOWULF_TEST=$(grep _BUSTER_TO_BEOWULF ${_barCnf} 2>&1)
  if [[ "${_BUSTER_TO_BEOWULF_TEST}" =~ "_BUSTER_TO_BEOWULF" ]]; then
    sed -i "s/^_BUSTER_TO_BEOWULF.*//g" ${_barCnf}
    wait
  fi
  _STRETCH_TO_BEOWULF_TEST=$(grep _STRETCH_TO_BEOWULF ${_barCnf} 2>&1)
  if [[ "${_STRETCH_TO_BEOWULF_TEST}" =~ "_STRETCH_TO_BEOWULF" ]]; then
    sed -i "s/^_STRETCH_TO_BEOWULF.*//g" ${_barCnf}
    wait
  fi
  _JESSIE_TO_BEOWULF_TEST=$(grep _JESSIE_TO_BEOWULF ${_barCnf} 2>&1)
  if [[ "${_JESSIE_TO_BEOWULF_TEST}" =~ "_JESSIE_TO_BEOWULF" ]]; then
    sed -i "s/^_JESSIE_TO_BEOWULF.*//g" ${_barCnf}
    wait
  fi
  _BUSTER_TO_BULLSEYE_TEST=$(grep _BUSTER_TO_BULLSEYE ${_barCnf} 2>&1)
  if [[ "${_BUSTER_TO_BULLSEYE_TEST}" =~ "_BUSTER_TO_BULLSEYE" ]]; then
    sed -i "s/^_BUSTER_TO_BULLSEYE.*//g" ${_barCnf}
    wait
  fi
  _STRETCH_TO_BUSTER_TEST=$(grep _STRETCH_TO_BUSTER ${_barCnf} 2>&1)
  if [[ "${_STRETCH_TO_BUSTER_TEST}" =~ "_STRETCH_TO_BUSTER" ]]; then
    sed -i "s/^_STRETCH_TO_BUSTER.*//g" ${_barCnf}
    wait
  fi
  _JESSIE_TO_STRETCH_TEST=$(grep _JESSIE_TO_STRETCH ${_barCnf} 2>&1)
  if [[ "${_JESSIE_TO_STRETCH_TEST}" =~ "_JESSIE_TO_STRETCH" ]]; then
    sed -i "s/^_JESSIE_TO_STRETCH.*//g" ${_barCnf}
    wait
  fi
  _WHEEZY_TO_JESSIE_TEST=$(grep _WHEEZY_TO_JESSIE ${_barCnf} 2>&1)
  if [[ "${_WHEEZY_TO_JESSIE_TEST}" =~ "_WHEEZY_TO_JESSIE" ]]; then
    sed -i "s/^_WHEEZY_TO_JESSIE.*//g" ${_barCnf}
    wait
  fi
  _SQUEEZE_TO_WHEEZY_TEST=$(grep _SQUEEZE_TO_WHEEZY ${_barCnf} 2>&1)
  if [[ "${_SQUEEZE_TO_WHEEZY_TEST}" =~ "_SQUEEZE_TO_WHEEZY" ]]; then
    sed -i "s/^_SQUEEZE_TO_WHEEZY.*//g" ${_barCnf}
    wait
  fi
  _LENNY_TO_SQUEEZE_TEST=$(grep _LENNY_TO_SQUEEZE ${_barCnf} 2>&1)
  if [[ "${_LENNY_TO_SQUEEZE_TEST}" =~ "_LENNY_TO_SQUEEZE" ]]; then
    sed -i "s/^_LENNY_TO_SQUEEZE.*//g" ${_barCnf}
    wait
  fi
  sed -i "/^$/d" ${_barCnf}
  wait
  ###
  ### config cleanup end
  ###
}

#
# Sort and de-duplicate versions in _PHP_MULTI_INSTALL.
_php_multi_uniq() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_multi_uniq"
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
_php_legacy_versions_cleanup_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_legacy_versions_cleanup_cnf"
  fi
  _PHP_CLI_LEGACY_IF_USED_A=$(grep "5\.2" /data/disk/*/log/cli.txt 2>&1)
  _PHP_CLI_LEGACY_IF_USED_B=$(grep "5\.2" /data/disk/*/static/control/cli.info 2>&1)
  _PHP_CLI_LEGACY_IF_USED_C=$(grep "CLI.*5\.2" /root/.*.octopus.cnf 2>&1)
  if [[ "${_PHP_CLI_LEGACY_IF_USED_A}" =~ "5.2" ]] \
    || [[ "${_PHP_CLI_LEGACY_IF_USED_B}" =~ "5.2" ]] \
    || [[ "${_PHP_CLI_LEGACY_IF_USED_C}" =~ "5.2" ]]; then
    if [ -e "/opt/php52/bin/php" ] || [ -e "/etc/init.d/php52-fpm" ]; then
      echo " "
      _msg "Legacy PHP-CLI 5.2 is used on this system but will be removed"
    fi
  fi

  _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.2" /data/disk/*/log/fpm.txt 2>&1)
  _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.2" /data/disk/*/static/control/fpm.info 2>&1)
  _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.2" /root/.*.octopus.cnf 2>&1)
  if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.2" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.2" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.2" ]]; then
    if [ -e "/opt/php52/bin/php" ] || [ -e "/etc/init.d/php52-fpm" ]; then
      _msg "Legacy PHP-FPM 5.2 is used on this system but will be removed"
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
      _msg "Legacy PHP-CLI 5.3 is used on this system but will be removed"
    fi
  fi

  _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.3" /data/disk/*/log/fpm.txt 2>&1)
  _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.3" /data/disk/*/static/control/fpm.info 2>&1)
  _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.3" /root/.*.octopus.cnf 2>&1)
  if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.3" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.3" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.3" ]]; then
    if [ -e "/opt/php53/bin/php" ] || [ -e "/etc/init.d/php53-fpm" ]; then
      _msg "Legacy PHP-FPM 5.3 is used on this system but will be removed"
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
      _msg "Legacy PHP-CLI 5.4 is used on this system but will be removed"
    fi
  fi

  _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.4" /data/disk/*/log/fpm.txt 2>&1)
  _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.4" /data/disk/*/static/control/fpm.info 2>&1)
  _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.4" /root/.*.octopus.cnf 2>&1)
  if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.4" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.4" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.4" ]]; then
    if [ -e "/opt/php54/bin/php" ] || [ -e "/etc/init.d/php54-fpm" ]; then
      _msg "Legacy PHP-FPM 5.4 is used on this system but will be removed"
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
      _msg "Legacy PHP-CLI 5.5 is used on this system but will be removed"
    fi
  fi

  _PHP_FPM_LEGACY_IF_USED_A=$(grep "5\.5" /data/disk/*/log/fpm.txt 2>&1)
  _PHP_FPM_LEGACY_IF_USED_B=$(grep "5\.5" /data/disk/*/static/control/fpm.info 2>&1)
  _PHP_FPM_LEGACY_IF_USED_C=$(grep "FPM.*5\.5" /root/.*.octopus.cnf 2>&1)
  if [[ "${_PHP_FPM_LEGACY_IF_USED_A}" =~ "5.5" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_B}" =~ "5.5" ]] \
    || [[ "${_PHP_FPM_LEGACY_IF_USED_C}" =~ "5.5" ]]; then
    if [ -e "/opt/php55/bin/php" ] || [ -e "/etc/init.d/php55-fpm" ]; then
      _msg "Legacy PHP-FPM 5.5 is used on this system but will be removed"
      echo " "
    fi
  fi

  _PHP_MULTI_INSTALL_TEST=$(grep _PHP_MULTI_INSTALL ${_barCnf} 2>&1)

  if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.2" ]]; then
    _R_M=5.2
    _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
    sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${_barCnf}
    wait
    sed -i "/^$/d" ${_barCnf}
    wait
  fi

  if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.3" ]]; then
    _R_M=5.3
    _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
    sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${_barCnf}
    wait
    sed -i "/^$/d" ${_barCnf}
    wait
  fi

  if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.4" ]]; then
    _R_M=5.4
    _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
    sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${_barCnf}
    wait
    sed -i "/^$/d" ${_barCnf}
    wait
  fi

  if [[ "${_PHP_MULTI_INSTALL_TEST}" =~ "5.5" ]]; then
    _R_M=5.5
    _PHP_MULTI_INSTALL=${_PHP_MULTI_INSTALL%%${_R_M}}
    sed -i "s/^_PHP_MULTI_INSTALL.*/_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"/g" ${_barCnf}
    wait
    sed -i "/^$/d" ${_barCnf}
    wait
  fi

  if [ -e "/etc/init.d/php-fpm" ]; then
    _mrun "service php-fpm stop" 2> /dev/null
    _mrun "update-rc.d -f php-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php-fpm
  fi
  if [ -e "/etc/init.d/php52-fpm" ]; then
    _mrun "service php52-fpm stop" 2> /dev/null
    _mrun "update-rc.d -f php52-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php52-fpm
  fi
  if [ -e "/etc/init.d/php53-fpm" ]; then
    _mrun "service php53-fpm stop" 2> /dev/null
    _mrun "update-rc.d -f php53-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php53-fpm
  fi
  if [ -e "/etc/init.d/php54-fpm" ]; then
    _mrun "service php54-fpm stop" 2> /dev/null
    _mrun "update-rc.d -f php54-fpm remove" 2> /dev/null
    rm -f /etc/init.d/php54-fpm
  fi
  if [ -e "/etc/init.d/php55-fpm" ]; then
    _mrun "service php55-fpm stop" 2> /dev/null
    _mrun "update-rc.d -f php55-fpm remove" 2> /dev/null
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
_php_if_versions_cleanup_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_if_versions_cleanup_cnf"
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
      _if_hosted_sys
      if [ "${_STRICT_LIMIT_PHP}" = "NO" ]; then
        if [ -e "/root/.include-php-latest.cnf" ] \
          || [ "${_hostedSys}" = "YES" ]; then
          if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ] \
            && [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_EOL_VRN}" ]; then
            _local_PHP_MULTI_INSTALL="8.2 8.3 ${_local_PHP_MULTI_INSTALL}"
          fi
        fi
      fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: _OPENSSL_NEW_VRN is ${_OPENSSL_NEW_VRN}"
        _msg "INFO: _local_PHP_MULTI_INSTALL is ${_local_PHP_MULTI_INSTALL}"
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
        _PHP_MULTI_INSTALL="8.3 7.4 5.6"
      else
        ### Sort and remove duplicates from _PHP_MULTI_INSTALL
        _php_multi_uniq
      fi
      export _PHP_MULTI_INSTALL="${_PHP_MULTI_INSTALL}"

      ### Remove previous _PHP_MULTI_INSTALL in /root/.barracuda.cnf
      _PHP_MULTI_TEST=$(grep _PHP_MULTI_INSTALL ${_barCnf} 2>&1)
      if [[ "${_PHP_MULTI_TEST}" =~ "_PHP_MULTI_INSTALL" ]]; then
        sed -i "s/^_PHP_MULTI_INSTALL.*//g" ${_barCnf}
        wait
        sed -i "s/^_PHP_ORIG_MULTI.*//g" ${_barCnf}
        wait
        sed -i "/^$/d" ${_barCnf}
        wait
      fi

      ### Add optimized _PHP_MULTI_INSTALL in /root/.barracuda.cnf
      echo "_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\"" >> ${_barCnf}

      ### Export optimized list as a new var
      _PHP_MULTI_OPTIM="${_PHP_MULTI_INSTALL}"
      export _PHP_MULTI_OPTIM="${_PHP_MULTI_OPTIM}"

      ### Disable not used PHP versions
      _php_not_used_disable

      ### Ctrl files cleanup
      touch /root/.sorted.multi.php.cnf
      [ -e "/root/.updated.multi.php.cnf" ] && rm -f /root/.updated.multi.php.cnf
      [ -e "/root/.fixed.multi.php.cnf" ] && rm -f /root/.fixed.multi.php.cnf
    fi
  fi
}

#
# Cleanup for PHP versions list.
_if_php_idle_on_off() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_php_idle_on_off"
  fi
  if [ "${_PHP_IDLE}" = "ON" ]; then
    [ -e "/root/.allow-php-multi-install-cleanup.cnf" ] && rm -f /root/.allow-php-multi-install-cleanup.cnf
    if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
      rm -f /var/xdrago_wait/log/*.log
      rm -f /var/xdrago_wait/log/._php_libs_fix_*.pid
    else
      rm -f /var/xdrago/log/*.log
      rm -f /var/xdrago/log/._php_libs_fix_*.pid
    fi
    touch /root/.proxy.cnf
    kill -9 $(ps aux | grep '[s]econd.sh' | awk '{print $2}') &> /dev/null
    sleep 5
    _php_not_used_enable_again
    sed -i "s/^_PHP_IDLE.*//g" ${_barCnf}
    [ -e "/root/.proxy.cnf" ] && rm -f /root/.proxy.cnf
    _php_install_deps
    _php_libs_fix
    if [ "${_STATUS}" = "UPGRADE" ]; then
      _php_ioncube_check_if_update
      _php_check_if_rebuild
    fi
    _php_install_upgrade
    _php_config_check_update
    _php_upgrade_all
    _if_install_php_newrelic
    _newrelic_check_fix
    _complete
    exit 0
  elif [ "${_PHP_IDLE}" = "OFF" ]; then
    touch /root/.proxy.cnf
    kill -9 $(ps aux | grep '[s]econd.sh' | awk '{print $2}') &> /dev/null
    sleep 5
    touch /root/.allow-php-multi-install-cleanup.cnf
    _php_if_versions_cleanup_cnf
    sed -i "s/^_PHP_IDLE.*//g" ${_barCnf}
    [ -e "/root/.proxy.cnf" ] && rm -f /root/.proxy.cnf
    if [ -e "/root/.run-to-daedalus.cnf" ] \
      || [ -e "/root/.run-to-chimaera.cnf" ] \
      || [ -e "/root/.run-to-beowulf.cnf" ]; then
      echo " "
      _msg "Bye"
      _clean_pid_exit _if_php_idle_on_off_a
    else
      _complete
      exit 0
    fi
  fi
}

#
# Read or create Barracuda cnf file.
_barracuda_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _barracuda_cnf"
  fi
  _CHECK_HOST=$(uname -n 2>&1)
  _VMFAMILY=XEN
  _VM_TEST=$(uname -a 2>&1)
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _VMFAMILY="VS"
  fi
  if [ ! -e "${_barCnf}" ]; then
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      _if_hosted_sys
      if [ "${_hostedSys}" != "YES" ]; then
        _msg "EXIT: Invalid email address defined in the _MY_EMAIL variable"
        _msg "EXIT: Bye (1)"
        _clean_pid_exit _barracuda_cnf_a
      fi
    fi

    _php_multi_uniq

    _msg "INFO: Creating your ${_barCnf} config file"
    sleep 1
    echo "###"                                                 > ${_barCnf}
    echo "### Configuration created on ${_NOW}"               >> ${_barCnf}
    echo "###"                                                >> ${_barCnf}
    echo "_LOCAL_NETWORK_HN=\"${_LOCAL_NETWORK_HN}\""         >> ${_barCnf}
    echo "_LOCAL_NETWORK_IP=\"${_LOCAL_NETWORK_IP}\""         >> ${_barCnf}
    echo "_MY_FRONT=\"${_MY_FRONT}\""                         >> ${_barCnf}
    echo "_MY_HOSTN=\"${_MY_HOSTN}\""                         >> ${_barCnf}
    echo "_MY_OWNIP=\"${_MY_OWNIP}\""                         >> ${_barCnf}
    echo "_SMTP_RELAY_HOST=\"${_SMTP_RELAY_HOST}\""           >> ${_barCnf}
    echo "_SMTP_RELAY_TEST=${_SMTP_RELAY_TEST}"               >> ${_barCnf}
    echo "_THIS_DB_HOST=${_THIS_DB_HOST}"                     >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_AUTOPILOT=${_AUTOPILOT}"                           >> ${_barCnf}
    echo "_DEBUG_MODE=${_DEBUG_MODE}"                         >> ${_barCnf}
    echo "_MY_EMAIL=\"${_MY_EMAIL}\""                         >> ${_barCnf}
    echo "_XTRAS_LIST=\"${_XTRAS_LIST}\""                     >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_MODULES_FIX=${_MODULES_FIX}"                       >> ${_barCnf}
    echo "_MODULES_SKIP=\"${_MODULES_SKIP}\""                 >> ${_barCnf}
    echo "_PERMISSIONS_FIX=${_PERMISSIONS_FIX}"               >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_CPU_CRIT_RATIO=${_CPU_CRIT_RATIO}"                 >> ${_barCnf}
    echo "_CPU_MAX_RATIO=${_CPU_MAX_RATIO}"                   >> ${_barCnf}
    echo "_CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO}"             >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_DB_BINARY_LOG=${_DB_BINARY_LOG}"                   >> ${_barCnf}
    echo "_DB_SERIES=${_DB_SERIES}"                           >> ${_barCnf}
    echo "_DB_SERVER=${_DB_SERVER}"                           >> ${_barCnf}
    echo "_USE_MYSQLTUNER=${_USE_MYSQLTUNER}"                 >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_DNS_SETUP_TEST=${_DNS_SETUP_TEST}"                 >> ${_barCnf}
    echo "_EXTRA_PACKAGES=${_EXTRA_PACKAGES}"                 >> ${_barCnf}
    echo "_FORCE_GIT_MIRROR=\"${_FORCE_GIT_MIRROR}\""         >> ${_barCnf}
    echo "_LOCAL_DEVUAN_MIRROR=${_LOCAL_DEVUAN_MIRROR}"       >> ${_barCnf}
    echo "_LOCAL_DEBIAN_MIRROR=${_LOCAL_DEBIAN_MIRROR}"       >> ${_barCnf}
    echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}"                     >> ${_barCnf}
    echo "_SCOUT_KEY=${_SCOUT_KEY}"                           >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_MAGICK_FROM_SOURCES=${_MAGICK_FROM_SOURCES}"       >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_NGINX_DOS_LINES=${_NGINX_DOS_LINES}"               >> ${_barCnf}
    echo "_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}"               >> ${_barCnf}
    echo "_NGINX_DOS_MODE=${_NGINX_DOS_MODE}"                 >> ${_barCnf}
    echo "_NGINX_DOS_LOG=${_NGINX_DOS_LOG}"                   >> ${_barCnf}
    echo "_NGINX_DOS_IGNORE=\"${_NGINX_DOS_IGNORE}\""         >> ${_barCnf}
    echo "_NGINX_DOS_STOP=\"${_NGINX_DOS_STOP}\""             >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_NGINX_EXTRA_CONF=\"${_NGINX_EXTRA_CONF}\""         >> ${_barCnf}
    echo "_NGINX_FORWARD_SECRECY=${_NGINX_FORWARD_SECRECY}"   >> ${_barCnf}
    echo "_NGINX_HEADERS=${_NGINX_HEADERS}"                   >> ${_barCnf}
    echo "_NGINX_LDAP=${_NGINX_LDAP}"                         >> ${_barCnf}
    echo "_NGINX_NAXSI=${_NGINX_NAXSI}"                       >> ${_barCnf}
    echo "_NGINX_SPDY=${_NGINX_SPDY}"                         >> ${_barCnf}
    echo "_NGINX_WORKERS=${_NGINX_WORKERS}"                   >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}"               >> ${_barCnf}
    echo "_PHP_EXTRA_CONF=\"${_PHP_EXTRA_CONF}\""             >> ${_barCnf}
    echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\""                 >> ${_barCnf}
    echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}"               >> ${_barCnf}
    echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}"               >> ${_barCnf}
    echo "_PHP_IONCUBE=${_PHP_IONCUBE}"                       >> ${_barCnf}
    echo "_PHP_GEOS=${_PHP_GEOS}"                             >> ${_barCnf}
    echo "_PHP_MONGODB=${_PHP_MONGODB}"                       >> ${_barCnf}
    echo "_PHP_MULTI_INSTALL=\"${_PHP_MULTI_INSTALL}\""       >> ${_barCnf}
    echo "_PHP_SINGLE_INSTALL=${_PHP_SINGLE_INSTALL}"         >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_REDIS_LISTEN_MODE=${_REDIS_LISTEN_MODE}"           >> ${_barCnf}
    echo "_REDIS_MAJOR_RELEASE=${_REDIS_MAJOR_RELEASE}"       >> ${_barCnf}
    echo "_RESERVED_RAM=${_RESERVED_RAM}"                     >> ${_barCnf}
    echo "_SPEED_VALID_MAX=${_SPEED_VALID_MAX}"               >> ${_barCnf}
    echo "_SSH_ARMOUR=${_SSH_ARMOUR}"                         >> ${_barCnf}
    echo "_SSH_FROM_SOURCES=${_SSH_FROM_SOURCES}"             >> ${_barCnf}
    echo "_SSH_PORT=${_SSH_PORT}"                             >> ${_barCnf}
    echo "_STRICT_BIN_PERMISSIONS=${_STRICT_BIN_PERMISSIONS}" >> ${_barCnf}
    echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}"             >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_CUSTOM_CONFIG_CSF=${_CUSTOM_CONFIG_CSF}"           >> ${_barCnf}
    echo "_CUSTOM_CONFIG_LSHELL=${_CUSTOM_CONFIG_LSHELL}"     >> ${_barCnf}
    echo "_CUSTOM_CONFIG_REDIS=${_CUSTOM_CONFIG_REDIS}"       >> ${_barCnf}
    echo "_CUSTOM_CONFIG_SQL=${_CUSTOM_CONFIG_SQL}"           >> ${_barCnf}

    echo "###"                                                >> ${_barCnf}
    echo "_AEGIR_UPGRADE_ONLY=${_AEGIR_UPGRADE_ONLY}"         >> ${_barCnf}
    echo "_SYSTEM_UP_ONLY=${_SYSTEM_UP_ONLY}"                 >> ${_barCnf}
    echo "###"                                                >> ${_barCnf}
    _CHECK_HOST=$(uname -n 2>&1)
    ### Force HTTP/2 or SPDY plus PFS on supported systems
    sed -i "s/^_NGINX_SPDY=.*/_NGINX_SPDY=YES/g"                 ${_barCnf}
    wait
    sed -i "s/^_NGINX_FORWARD.*/_NGINX_FORWARD_SECRECY=YES/g"    ${_barCnf}
    wait
    ### Force ImageMagick from packages
    sed -i "s/^_MAGICK_FROM_S.*/_MAGICK_FROM_SOURCES=NO/g"       ${_barCnf}
    wait
    sed -i "s/^_AUTOPILOT=.*/_AUTOPILOT=YES/g"                   ${_barCnf}
    wait
    sed -i "s/^_FORCE_GIT_.*/_FORCE_GIT_MIRROR=\"\"/g"           ${_barCnf}
    wait

    _devM="deb.devuan.org"
    _debM="deb.debian.org"

    sed -i "s/^_LOCAL_DEVUAN_.*/_LOCAL_DEVUAN_MIRROR=${_devM}/g"  ${_barCnf}
    wait
    sed -i "s/^_LOCAL_DEBIAN_.*/_LOCAL_DEBIAN_MIRROR=${_debM}/g"  ${_barCnf}
    wait
    sed -i "s/^_SSH_FROM_SOURCES=.*/_SSH_FROM_SOURCES=YES/g"      ${_barCnf}
    wait
    sed -i "s/^_STRICT_BIN_.*/_STRICT_BIN_PERMISSIONS=YES/g"      ${_barCnf}
    wait
    sed -i "s/^_STRONG_PASS.*/_STRONG_PASSWORDS=YES/g"            ${_barCnf}
    wait
    sed -i "s/^_PERMISSIONS_FIX=.*/_PERMISSIONS_FIX=YES/g"        ${_barCnf}
    wait
    sed -i "s/^_FORCE_GIT_.*/_FORCE_GIT_MIRROR=\"\"/g" /root/.*.octopus.cnf &> /dev/null
    wait
    sed -i "s/^_STRONG_PASS.*/_STRONG_PASSWORDS=YES/g" /root/.*.octopus.cnf &> /dev/null
    wait
    sed -i "s/^_REDIS_LISTEN.*/_REDIS_LISTEN_MODE=SOCKET/g"       ${_barCnf}
    wait
    if [ "${_OS_CODE}" = "stretch" ] || [ "${_OS_CODE}" = "jessie" ]; then
      if [ -x "/opt/php74/bin/php" ]; then
        _fCli=7.4
      elif [ -x "/opt/php73/bin/php" ]; then
        _fCli=7.3
      elif [ -x "/opt/php72/bin/php" ]; then
        _fCli=7.2
      elif [ -x "/opt/php71/bin/php" ]; then
        _fCli=7.1
      elif [ -x "/opt/php70/bin/php" ]; then
        _fCli=7.0
      elif [ -x "/opt/php56/bin/php" ]; then
        _fCli=5.6
      fi
    else
      _fCli=8.3
    fi
    if [ -z "${_PHP_SINGLE_INSTALL}" ]; then
      sed -i "s/^_PHP_CLI_VERSION=5.6/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=5.6/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.0/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.0/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.1/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.1/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.2/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.2/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.3/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.3/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=8.0/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=8.0/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
    fi
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
      sed -i "s/^_MY_EMAIL=.*/_MY_EMAIL=\"notify\@omega8.cc\"/g" ${_barCnf}
      wait
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Reading your ${_barCnf} config file"
      sleep 1
      _msg "NOTE! Please review all config options displayed below"
      _msg "NOTE! It will *override* all settings in the Barracuda script"
    fi
    sed -i "s/_SPEED_VALID_MAX=300/_SPEED_VALID_MAX=3600/g" ${_barCnf}
    wait

    _NGINX_WORKERS_TEST=$(grep _NGINX_WORKERS ${_barCnf} 2>&1)
    if [[ "${_NGINX_WORKERS_TEST}" =~ "_NGINX_WORKERS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_NGINX_WORKERS=${_NGINX_WORKERS}" >> ${_barCnf}
    fi

    _PHP_FPM_WORKERS_TEST=$(grep _PHP_FPM_WORKERS ${_barCnf} 2>&1)
    if [[ "${_PHP_FPM_WORKERS_TEST}" =~ "_PHP_FPM_WORKERS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}" >> ${_barCnf}
    fi

    if [ -d "/data/u" ]; then
      _php_legacy_versions_cleanup_cnf
    fi

    _PHP_FPM_VERSION_TEST=$(grep _PHP_FPM_VERSION ${_barCnf} 2>&1)
    if [[ ! "${_PHP_FPM_VERSION_TEST}" =~ "_PHP_FPM_VERSION" ]]; then
      echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}" >> ${_barCnf}
    fi

    _PHP_CLI_VERSION_TEST=$(grep _PHP_CLI_VERSION ${_barCnf} 2>&1)
    if [[ ! "${_PHP_CLI_VERSION_TEST}" =~ "_PHP_CLI_VERSION" ]]; then
      echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}" >> ${_barCnf}
    fi

    _PHP_SINGLE_INSTALL_TEST=$(grep _PHP_SINGLE_INSTALL ${_barCnf} 2>&1)
    if [[ ! "${_PHP_SINGLE_INSTALL_TEST}" =~ "_PHP_SINGLE_INSTALL" ]]; then
      echo "_PHP_SINGLE_INSTALL=${_PHP_SINGLE_INSTALL}" >> ${_barCnf}
    fi

    _CUSTOM_CONFIG_LSHELL_TEST=$(grep _CUSTOM_CONFIG_LSHELL ${_barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_LSHELL_TEST}" =~ "_CUSTOM_CONFIG_LSHELL" ]]; then
      echo "_CUSTOM_CONFIG_LSHELL=${_CUSTOM_CONFIG_LSHELL}" >> ${_barCnf}
    fi

    _CUSTOM_CONFIG_CSF_TEST=$(grep _CUSTOM_CONFIG_CSF ${_barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_CSF_TEST}" =~ "_CUSTOM_CONFIG_CSF" ]]; then
      echo "_CUSTOM_CONFIG_CSF=${_CUSTOM_CONFIG_CSF}" >> ${_barCnf}
    fi

    _CUSTOM_CONFIG_SQL_TEST=$(grep _CUSTOM_CONFIG_SQL ${_barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_SQL_TEST}" =~ "_CUSTOM_CONFIG_SQL" ]]; then
      echo "_CUSTOM_CONFIG_SQL=${_CUSTOM_CONFIG_SQL}" >> ${_barCnf}
    fi

    _SPEED_VALID_MAX_TEST=$(grep _SPEED_VALID_MAX ${_barCnf} 2>&1)
    if [[ ! "${_SPEED_VALID_MAX_TEST}" =~ "_SPEED_VALID_MAX" ]]; then
      echo "_SPEED_VALID_MAX=${_SPEED_VALID_MAX}" >> ${_barCnf}
    fi

    _NGINX_DOS_LIMIT_TEST=$(grep _NGINX_DOS_LIMIT ${_barCnf} 2>&1)
    if [[ ! "${_NGINX_DOS_LIMIT_TEST}" =~ "_NGINX_DOS_LIMIT" ]]; then
      echo "_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}" >> ${_barCnf}
    fi

    _CPU_SPIDER_RATIO_TEST=$(grep _CPU_SPIDER_RATIO ${_barCnf} 2>&1)
    if [[ ! "${_CPU_SPIDER_RATIO_TEST}" =~ "_CPU_SPIDER_RATIO" ]]; then
      echo "_CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO}" >> ${_barCnf}
    fi

    _CPU_MAX_RATIO_TEST=$(grep _CPU_MAX_RATIO ${_barCnf} 2>&1)
    if [[ ! "${_CPU_MAX_RATIO_TEST}" =~ "_CPU_MAX_RATIO" ]]; then
      echo "_CPU_MAX_RATIO=${_CPU_MAX_RATIO}" >> ${_barCnf}
    fi

    _CPU_CRIT_RATIO_TEST=$(grep _CPU_CRIT_RATIO ${_barCnf} 2>&1)
    if [[ ! "${_CPU_CRIT_RATIO_TEST}" =~ "_CPU_CRIT_RATIO" ]]; then
      echo "_CPU_CRIT_RATIO=${_CPU_CRIT_RATIO}" >> ${_barCnf}
    fi

    _SYSTEM_UP_ONLY_TEST=$(grep _SYSTEM_UP_ONLY ${_barCnf} 2>&1)
    if [[ ! "${_SYSTEM_UP_ONLY_TEST}" =~ "_SYSTEM_UP_ONLY" ]]; then
      echo "_SYSTEM_UP_ONLY=${_SYSTEM_UP_ONLY}" >> ${_barCnf}
    fi

    _AEGIR_UPGRADE_ONLY_TEST=$(grep _AEGIR_UPGRADE_ONLY ${_barCnf} 2>&1)
    if [[ ! "${_AEGIR_UPGRADE_ONLY_TEST}" =~ "_AEGIR_UPGRADE_ONLY" ]]; then
      echo "_AEGIR_UPGRADE_ONLY=${_AEGIR_UPGRADE_ONLY}" >> ${_barCnf}
    fi

    _CUSTOM_CONFIG_REDIS_TEST=$(grep _CUSTOM_CONFIG_REDIS ${_barCnf} 2>&1)
    if [[ ! "${_CUSTOM_CONFIG_REDIS_TEST}" =~ "_CUSTOM_CONFIG_REDIS" ]]; then
      echo "_CUSTOM_CONFIG_REDIS=${_CUSTOM_CONFIG_REDIS}" >> ${_barCnf}
    fi

    _NEWRELIC_KEY_TEST=$(grep _NEWRELIC_KEY ${_barCnf} 2>&1)
    if [[ ! "${_NEWRELIC_KEY_TEST}" =~ "_NEWRELIC_KEY" ]]; then
      if [ ! -z "${_NEWRELIC_KEY}" ]; then
        echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}" >> ${_barCnf}
      else
        if [ -e "/etc/newrelic/newrelic.cfg" ]; then
          _NEWRELIC_KEY=$(grep license_key /etc/newrelic/newrelic.cfg 2>&1)
          _NEWRELIC_KEY=$(echo -n ${_NEWRELIC_KEY} | tr -d "\n" 2>&1)
          echo "_NEWRELIC_KEY=${_NEWRELIC_KEY}" >> ${_barCnf}
          sed -i "s/license_key=//g" ${_barCnf}
          wait
        fi
      fi
    fi

    _SCOUT_KEY_TEST=$(grep _SCOUT_KEY ${_barCnf} 2>&1)
    if [[ ! "${_SCOUT_KEY_TEST}" =~ "_SCOUT_KEY" ]]; then
      echo "_SCOUT_KEY=${_SCOUT_KEY}" >> ${_barCnf}
    fi

    _EXTRA_PACKAGES_TEST=$(grep _EXTRA_PACKAGES ${_barCnf} 2>&1)
    if [[ ! "${_EXTRA_PACKAGES_TEST}" =~ "_EXTRA_PACKAGES" ]]; then
      echo "_EXTRA_PACKAGES=${_EXTRA_PACKAGES}" >> ${_barCnf}
    fi

    _PHP_EXTRA_CONF_TEST=$(grep _PHP_EXTRA_CONF ${_barCnf} 2>&1)
    if [[ ! "${_PHP_EXTRA_CONF_TEST}" =~ "_PHP_EXTRA_CONF" ]]; then
      echo "_PHP_EXTRA_CONF=\"${_PHP_EXTRA_CONF}\"" >> ${_barCnf}
    fi

    _PHP_FPM_DENY_TEST=$(grep _PHP_FPM_DENY ${_barCnf} 2>&1)
    if [[ ! "${_PHP_FPM_DENY_TEST}" =~ "_PHP_FPM_DENY" ]]; then
      echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\"" >> ${_barCnf}
    fi

    _STRONG_PASSWORDS_TEST=$(grep _STRONG_PASSWORDS ${_barCnf} 2>&1)
    if [[ ! "${_STRONG_PASSWORDS_TEST}" =~ "_STRONG_PASSWORDS" ]]; then
      echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}" >> ${_barCnf}
    fi

    _DB_BINARY_LOG_TEST=$(grep _DB_BINARY_LOG ${_barCnf} 2>&1)
    if [[ ! "${_DB_BINARY_LOG_TEST}" =~ "_DB_BINARY_LOG" ]]; then
      echo "_DB_BINARY_LOG=${_DB_BINARY_LOG}" >> ${_barCnf}
    fi

    _USE_MYSQLTUNER_TEST=$(grep _USE_MYSQLTUNER ${_barCnf} 2>&1)
    if [[ ! "${_USE_MYSQLTUNER_TEST}" =~ "_USE_MYSQLTUNER" ]]; then
      echo "_USE_MYSQLTUNER=${_USE_MYSQLTUNER}" >> ${_barCnf}
    fi

    _REDIS_LISTEN_MODE_TEST=$(grep _REDIS_LISTEN_MODE ${_barCnf} 2>&1)
    if [[ ! "${_REDIS_LISTEN_MODE_TEST}" =~ "_REDIS_LISTEN_MODE" ]]; then
      echo "_REDIS_LISTEN_MODE=${_REDIS_LISTEN_MODE}" >> ${_barCnf}
    fi

    _REDIS_MAJOR_RELEASE_TEST=$(grep _REDIS_MAJOR_RELEASE ${_barCnf} 2>&1)
    if [[ ! "${_REDIS_MAJOR_RELEASE_TEST}" =~ "_REDIS_MAJOR_RELEASE" ]]; then
      echo "_REDIS_MAJOR_RELEASE=${_REDIS_MAJOR_RELEASE}" >> ${_barCnf}
    fi

    _NGINX_HEADERS_TEST=$(grep _NGINX_HEADERS ${_barCnf} 2>&1)
    if [[ ! "${_NGINX_HEADERS_TEST}" =~ "_NGINX_HEADERS" ]]; then
      echo "_NGINX_HEADERS=${_NGINX_HEADERS}" >> ${_barCnf}
    fi

    _NGINX_LDAP_TEST=$(grep _NGINX_LDAP ${_barCnf} 2>&1)
    if [[ ! "${_NGINX_LDAP_TEST}" =~ "_NGINX_LDAP" ]]; then
      echo "_NGINX_LDAP=${_NGINX_LDAP}" >> ${_barCnf}
    fi

    _NGINX_NAXSI_TEST=$(grep _NGINX_NAXSI ${_barCnf} 2>&1)
    if [[ ! "${_NGINX_NAXSI_TEST}" =~ "_NGINX_NAXSI" ]]; then
      echo "_NGINX_NAXSI=${_NGINX_NAXSI}" >> ${_barCnf}
    fi

    _NGINX_SPDY_TEST=$(grep _NGINX_SPDY ${_barCnf} 2>&1)
    if [[ ! "${_NGINX_SPDY_TEST}" =~ "_NGINX_SPDY" ]]; then
      echo "_NGINX_SPDY=${_NGINX_SPDY}" >> ${_barCnf}
    fi

    _NGINX_FORWARD_SECRECY_TEST=$(grep _NGINX_FORWARD_SECRECY ${_barCnf} 2>&1)
    if [[ ! "${_NGINX_FORWARD_SECRECY_TEST}" =~ "_NGINX_FORWARD_SECRECY" ]]; then
      echo "_NGINX_FORWARD_SECRECY=${_NGINX_FORWARD_SECRECY}" >> ${_barCnf}
    fi

    _PHP_IONCUBE_TEST=$(grep _PHP_IONCUBE ${_barCnf} 2>&1)
    if [[ ! "${_PHP_IONCUBE_TEST}" =~ "_PHP_IONCUBE" ]]; then
      echo "_PHP_IONCUBE=${_PHP_IONCUBE}" >> ${_barCnf}
    fi

    _PHP_GEOS_TEST=$(grep _PHP_GEOS ${_barCnf} 2>&1)
    if [[ ! "${_PHP_GEOS_TEST}" =~ "_PHP_GEOS" ]]; then
      echo "_PHP_GEOS=${_PHP_GEOS}" >> ${_barCnf}
    fi

    _PHP_MONGODB_TEST=$(grep _PHP_MONGODB ${_barCnf} 2>&1)
    if [[ ! "${_PHP_MONGODB_TEST}" =~ "_PHP_MONGODB" ]]; then
      echo "_PHP_MONGODB=${_PHP_MONGODB}" >> ${_barCnf}
    fi

    _PERMISSIONS_FIX_TEST=$(grep _PERMISSIONS_FIX ${_barCnf} 2>&1)
    if [[ ! "${_PERMISSIONS_FIX_TEST}" =~ "_PERMISSIONS_FIX" ]]; then
      echo "_PERMISSIONS_FIX=${_PERMISSIONS_FIX}" >> ${_barCnf}
    fi

    _MODULES_FIX_TEST=$(grep _MODULES_FIX ${_barCnf} 2>&1)
    if [[ ! "${_MODULES_FIX_TEST}" =~ "_MODULES_FIX" ]]; then
      echo "_MODULES_FIX=${_MODULES_FIX}" >> ${_barCnf}
    fi

    _MODULES_SKIP_TEST=$(grep _MODULES_SKIP ${_barCnf} 2>&1)
    if [[ ! "${_MODULES_SKIP_TEST}" =~ "_MODULES_SKIP" ]]; then
      echo "_MODULES_SKIP=\"${_MODULES_SKIP}\"" >> ${_barCnf}
    fi

    _SSH_FROM_SOURCES_TEST=$(grep _SSH_FROM_SOURCES ${_barCnf} 2>&1)
    if [[ ! "${_SSH_FROM_SOURCES_TEST}" =~ "_SSH_FROM_SOURCES" ]]; then
      echo "_SSH_FROM_SOURCES=${_SSH_FROM_SOURCES}" >> ${_barCnf}
    fi

    _SSH_ARMOUR_TEST=$(grep _SSH_ARMOUR ${_barCnf} 2>&1)
    if [[ ! "${_SSH_ARMOUR_TEST}" =~ "_SSH_ARMOUR" ]]; then
      echo "_SSH_ARMOUR=${_SSH_ARMOUR}" >> ${_barCnf}
    fi

    _MAGICK_FROM_SOURCES_TEST=$(grep _MAGICK_FROM_SOURCES ${_barCnf} 2>&1)
    if [[ ! "${_MAGICK_FROM_SOURCES_TEST}" =~ "_MAGICK_FROM_SOURCES" ]]; then
      echo "_MAGICK_FROM_SOURCES=${_MAGICK_FROM_SOURCES}" >> ${_barCnf}
    fi

    _RESERVED_RAM_TEST=$(grep _RESERVED_RAM ${_barCnf} 2>&1)
    if [[ ! "${_RESERVED_RAM_TEST}" =~ "_RESERVED_RAM" ]]; then
      echo "_RESERVED_RAM=${_RESERVED_RAM}" >> ${_barCnf}
    fi

    _STRICT_BIN_PERMISSIONS_TEST=$(grep _STRICT_BIN_PERMISSIONS ${_barCnf} 2>&1)
    if [[ ! "${_STRICT_BIN_PERMISSIONS_TEST}" =~ "_STRICT_BIN_PERMISSIONS" ]]; then
      echo "_STRICT_BIN_PERMISSIONS=${_STRICT_BIN_PERMISSIONS}" >> ${_barCnf}
    fi

    _DB_SERIES_TEST=$(grep _DB_SERIES ${_barCnf} 2>&1)
    if [[ ! "${_DB_SERIES_TEST}" =~ "_DB_SERIES" ]]; then
      echo "_DB_SERIES=${_DB_SERIES}" >> ${_barCnf}
    fi

    if [ -e "/etc/init.d/tomcat" ]; then
      echo "_TOMCAT_TO_JETTY=YES" >> ${_barCnf}
    fi

    sleep 1
    _CHECK_HOST=$(uname -n 2>&1)
    ### Force HTTP/2 or SPDY plus PFS on supported systems
    sed -i "s/^_NGINX_SPDY=.*/_NGINX_SPDY=YES/g"                 ${_barCnf}
    wait
    sed -i "s/^_NGINX_FORWARD.*/_NGINX_FORWARD_SECRECY=YES/g"    ${_barCnf}
    wait
    ### Force ImageMagick from packages
    sed -i "s/^_MAGICK_FROM_S.*/_MAGICK_FROM_SOURCES=NO/g"       ${_barCnf}
    wait
    ### Force latest OpenSSH from sources on supported systems
    sed -i "s/^_SSH_FROM_SOURCES=.*/_SSH_FROM_SOURCES=YES/g"     ${_barCnf}
    wait

    _devM="deb.devuan.org"
    _debM="deb.debian.org"

    sed -i "s/^_LOCAL_DEVUAN_.*/_LOCAL_DEVUAN_MIRROR=${_devM}/g"  ${_barCnf}
    wait
    sed -i "s/^_LOCAL_DEBIAN_.*/_LOCAL_DEBIAN_MIRROR=${_debM}/g"  ${_barCnf}
    wait

    sed -i "s/^_AUTOPILOT=.*/_AUTOPILOT=YES/g"                   ${_barCnf}
    wait
    sed -i "s/^_FORCE_GIT_.*/_FORCE_GIT_MIRROR=\"\"/g"           ${_barCnf}
    wait
    sed -i "s/^_STRICT_BIN_.*/_STRICT_BIN_PERMISSIONS=YES/g"     ${_barCnf}
    wait
    sed -i "s/^_STRONG_PASS.*/_STRONG_PASSWORDS=YES/g"           ${_barCnf}
    wait
    sed -i "s/^_PERMISSIONS_.*/_PERMISSIONS_FIX=YES/g"           ${_barCnf}
    wait
    sed -i "s/^_FORCE_GIT_.*/_FORCE_GIT_MIRROR=\"\"/g" /root/.*.octopus.cnf &> /dev/null
    wait
    sed -i "s/^_STRONG_PASS.*/_STRONG_PASSWORDS=YES/g" /root/.*.octopus.cnf &> /dev/null
    wait
    sed -i "s/^_REDIS_LISTEN_.*/_REDIS_LISTEN_MODE=SOCKET/g"     ${_barCnf}
    wait
    if [ "${_OS_CODE}" = "stretch" ] || [ "${_OS_CODE}" = "jessie" ]; then
      if [ -x "/opt/php74/bin/php" ]; then
        _fCli=7.4
      elif [ -x "/opt/php73/bin/php" ]; then
        _fCli=7.3
      elif [ -x "/opt/php72/bin/php" ]; then
        _fCli=7.2
      elif [ -x "/opt/php71/bin/php" ]; then
        _fCli=7.1
      elif [ -x "/opt/php70/bin/php" ]; then
        _fCli=7.0
      elif [ -x "/opt/php56/bin/php" ]; then
        _fCli=5.6
      fi
    else
      _fCli=8.3
    fi
    if [ -z "${_PHP_SINGLE_INSTALL}" ]; then
      sed -i "s/^_PHP_CLI_VERSION=5.6/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=5.6/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.0/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.0/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.1/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.1/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.2/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.2/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.3/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.3/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=7.4/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=7.4/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_CLI_VERSION=8.0/_PHP_CLI_VERSION=${_fCli}/g"    ${_barCnf}
      wait
      sed -i "s/^_PHP_FPM_VERSION=8.0/_PHP_FPM_VERSION=${_fCli}/g"    ${_barCnf}
      wait
    fi

    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
      sed -i "s/^_MY_EMAIL=.*/_MY_EMAIL=\"notify\@omega8.cc\"/g" ${_barCnf}
      wait
    fi

    sed -i "/^$/d" ${_barCnf}
    wait
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo " "
      while read line; do
        echo "$line"
      done < ${_barCnf}
      echo " "
    fi
    if [ -e "${_barCnf}" ]; then
      source ${_barCnf}
    fi

    if [ "${_DB_SERVER}" = "Percona" ]; then
      if [ "${_DB_SERIES}" = "5.7" ]; then
        _DBS_VRN="${_PERCONA_5_7_VRN}"
      elif [ "${_DB_SERIES}" = "8.0" ]; then
        _DBS_VRN="${_PERCONA_8_0_VRN}"
      elif [ "${_DB_SERIES}" = "8.3" ]; then
        _DBS_VRN="${_PERCONA_8_3_VRN}"
      elif [ "${_DB_SERIES}" = "8.4" ]; then
        _DBS_VRN="${_PERCONA_8_4_VRN}"
      else
        _DB_SERIES=5.7
        _DBS_VRN="${_PERCONA_5_7_VRN}"
      fi
    else
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
      if [ -e "${_barCnf}" ]; then
        sed -i "s/^_DB_SERIES=.*/_DB_SERIES=5.7/g" ${_barCnf}
        sed -i "s/^_DB_SERVER=.*/_DB_SERVER=Percona/g" ${_barCnf}
      fi
    fi

    _CHECK_HOST=$(uname -n 2>&1)
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      _if_hosted_sys
      if [ "${_hostedSys}" != "YES" ]; then
        _msg "EXIT: Invalid email address defined in the _MY_EMAIL variable"
        _msg "EXIT: Bye (2)"
        _clean_pid_exit _barracuda_cnf_b
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
        sed -i "s/^_PHP_MULTI_INSTALL=.*/_PHP_MULTI_INSTALL=${_PHP_SINGLE_INSTALL}/g" ${_barCnf}
        wait
        sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}/g"     ${_barCnf}
        wait
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}/g"     ${_barCnf}
        wait
        sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_PHP_SINGLE_INSTALL}/g" /root/.*.octopus.cnf &> /dev/null
        wait
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_PHP_SINGLE_INSTALL}/g" /root/.*.octopus.cnf &> /dev/null
        wait
        if [ -d "/data/u" ] && [ -e "/data/conf/global.inc" ]; then
          for _Ctrl in `find /data/disk/*/log -maxdepth 0 -mindepth 0 | sort`; do
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/fpm.txt
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/cli.txt
            ### _msg "INFO: Forced PHP ${_PHP_SINGLE_INSTALL} in $Ctrl"
          done
          for _Ctrl in `find /data/disk/*/static/control \
            -maxdepth 0 -mindepth 0 | sort`; do
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/fpm.info
            echo ${_PHP_SINGLE_INSTALL} > $Ctrl/cli.info
            ### _msg "INFO: Forced PHP ${_PHP_SINGLE_INSTALL} in $Ctrl"
          done
          for _Ctrl in `find /data/disk/*/.drush \
            -maxdepth 0 -mindepth 0 | sort`; do
            rm -f $Ctrl/.ctrl.php*
            ### _msg "INFO: Forced PHP ${_PHP_SINGLE_INSTALL} in $Ctrl"
          done
        fi
      fi
    fi

    if [ "${_STATUS}" = "INIT" ]; then
      if _prompt_yes_no "Do you want to proceed with the install?" ; then
        true
      else
        echo "Installation aborted by you"
        _clean_pid_exit _barracuda_cnf_c
      fi
    else
      echo " "
      if _prompt_yes_no "Do you want to proceed with the upgrade?" ; then
        true
      else
        echo "Upgrade aborted by you"
        _clean_pid_exit _barracuda_cnf_d
      fi
    fi
  fi
}

#
# Install MyTop.
_mytop_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _mytop_install"
  fi
  if [ -e "/usr/bin/mytop" ]; then
    _mrun "apt-get remove mytop -y -qq" 2> /dev/null
    rm -f /usr/bin/mytop
  fi
  _MYTOP_REINSTALL=NO
  _MYTOP_TEST=$(mytop -b 2>&1)
  if [[ "${_MYTOP_TEST}" =~ "cannot open shared object file" ]] \
    || [[ "${_MYTOP_TEST}" =~ "you may need to install" ]] \
    || [[ "${_MYTOP_TEST}" =~ "failed" ]]; then
    _MYTOP_REINSTALL=YES
  fi
  if [ -e "/usr/bin/mysql" ]; then
    if [ ! -e "/usr/local/bin/mytop" ] || [ "${_MYTOP_REINSTALL}" = "YES" ]; then
      _msg "INFO: Building MyTop from sources..."
      _check_mysql_version
      _apt_clean_update
      _mrun "${_INSTAPP} libperl-dev" 2> /dev/null
      _mrun "${_INSTAPP} cpanminus" 2> /dev/null
      if [ "${_DB_V}" != "5.7" ] || [ "${_SQL_UPGRADE}" = "YES" ]; then
        _mrun "cpanm DBD::mysql" 2> /dev/null
        _mrun "cpanm DBI" 2> /dev/null
        _mrun "cpanm Term::ReadKey" 2> /dev/null
      else
        _mrun "cpanm DBD::mysql@4.050" 2> /dev/null
        _mrun "cpanm Term::ReadKey" 2> /dev/null
      fi
      cd /var/opt
      rm -rf git*
      _get_dev_src "mytop-1.6.tar.gz"
      cd /var/opt/mytop-1.6
      _mrun "perl Makefile.PL" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
    fi
  fi
}

#
# Running apt-get full-dist-upgrade.
_run_apt_get_dist_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _run_apt_get_dist_upgrade"
  fi
  _msg "INFO: Running apt-get upgrade..."
  _apt_clean_update_no_releaseinfo_change
  _mrun "apt-get upgrade ${_dstUpArg}" 2> /dev/null
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Running apt-get dist-upgrade..."
  fi
  _mrun "apt-get dist-upgrade ${_dstUpArg}" 2> /dev/null
  [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
  _mrun "apt-get dist-upgrade -y --allow-unauthenticated" 2> /dev/null
  [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
  _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
  ### Update rsyslog configuration early
  _rsyslog_config_update
  ### Reload key services if needed early
  _mrun "service redis-server reload" 2> /dev/null
  _mrun "service nginx reload" 2> /dev/null
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      _mrun "service php${e}-fpm reload" 2> /dev/null
    fi
  done
  if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
    perl /var/xdrago_wait/proc_num_ctrl.pl &
  else
    perl /var/xdrago/proc_num_ctrl.pl &
  fi
}

#
# Run aptitude full-upgrade.
_run_aptitude_full_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _run_aptitude_full_upgrade"
  fi
  _msg "INFO: Running aptitude full-upgrade..."
  ###
  ### Make sure that percona-release package is locked in apt early.
  if [ ! -e "/etc/apt/preferences.d/percona-release" ]; then
    echo -e 'Package: percona-release\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/percona-release
    _apt_clean_update
  fi
  ###
  _PERC_GET_DPKG=$(dpkg --get-selections | grep percona-release | grep 'hold$' 2>&1)
  if [[ ! "${_PERC_GET_DPKG}" =~ "hold" ]]; then
    aptitude hold percona-release &> /dev/null
    echo "percona-release hold" | dpkg --set-selections &> /dev/null
    _apt_clean_update
  fi
  _mrun "apt-get remove percona-release -y -qq" 2> /dev/null
  _apt_clean_update
  if [ -e "/var/aegir/drush" ]; then
    _DPKG_CNF="confold"
  else
    _DPKG_CNF="confnew"
  fi
  _st_runner "apt-get --fix-broken install -y" 2> /dev/null
  _st_runner "dpkg --configure --force-all -a" 2> /dev/null
  _st_runner "aptitude full-upgrade -f -y -q \
    --allow-untrusted \
    -o Dpkg::Options::=--force-confmiss \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-${_DPKG_CNF}" &> /dev/null
}

#
# Install latest Git.
_do_install_latest_git() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _do_install_latest_git"
  fi
  if [ "${_GIT_INSTALL}" = "YES" ]; then
    _msg "INFO: Building Git ${_GIT_VRN} from sources..."
    _msg "WAIT: This may take a while, please wait..."
    if [ ! -x "/usr/local/bin/git" ]; then
      _apt_clean_update
      _mrun "apt-get install libcurl4 -y --allow-unauthenticated" 2> /dev/null
      _mrun "apt-get install libcurl4-openssl-dev -y --allow-unauthenticated" 2> /dev/null
      _mrun "apt-get install libcurl4-gnutls-dev -y --allow-unauthenticated" 2> /dev/null
      _mrun "apt-get remove git-core -y --purge --auto-remove" 2> /dev/null
      _mrun "apt-get remove git -y --purge --auto-remove" 2> /dev/null
    fi
    mkdir -p /var/opt
    rm -rf /var/opt/git*
    cd /var/opt
    _get_dev_src "git-${_GIT_VRN}.tar.gz"
    cd /var/opt/git-${_GIT_VRN}
    _mrun "make configure" 2> /dev/null
    _mrun "bash ./configure --without-tcltk" 2> /dev/null
    _mrun "make all -j $(nproc)" 2> /dev/null
    _mrun "make install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -x "/usr/local/bin/git" ]; then
      if [ -e "/usr/bin/git" ] && [ ! -L "/usr/bin/git" ]; then
        mv -f /usr/bin/git /usr/bin/git-old
      fi
      ln -sfn /usr/local/bin/git /usr/bin/git
    fi
    cd /var/opt
    touch ${_pthLog}/git-${_GIT_VRN}-${_xSrl}-${_X_VERSION}-${_NOW}.log
    echo "git hold" | dpkg --set-selections &> /dev/null
    echo "git-core hold" | dpkg --set-selections &> /dev/null
    echo "git-man hold" | dpkg --set-selections &> /dev/null
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Git ${_GIT_V} already installed from sources ${_GIT_VRN}, OK"
    fi
  fi
}

#
# Check if latest Git should be installed.
_if_install_git_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_git_src"
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
    _do_install_latest_git
  fi
}

#
# Check apt-get updates.
_check_apt_updates() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_apt_updates"
  fi
  for _Update in `/usr/bin/apt-get -q -y --allow-unauthenticated \
    -s dist-upgrade | grep ^Inst | cut -d\  -f2 | sort`; do
    case "${_Update}" in
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
_install_icu_modern() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_icu_modern"
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
  if [ ! -e "${_pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    _pthLog="/var/xdrago_wait/log"
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ -e "${_pthLog}" ]; then
    _pthIcuLog="${_pthLog}/icu-update-${_ICU_MODERN_VRN}-for-${_OS_CODE}.log"
    _pthIcuLcy="${_pthLog}/icu-update-${_ICU_MODERN_VRN}.log"
  else
    _pthIcuLog="/root/.icu-update-${_ICU_MODERN_VRN}-for-${_OS_CODE}.log"
    _pthIcuLcy="/root/.icu-update-${_ICU_MODERN_VRN}.log"
  fi
  if [ "${_OS_CODE}" = "daedalus" ] \
    && [ -e "${_pthIcuLcy}" ] \
    && [ ! -e "${_pthIcuLog}" ]; then
    touch ${_pthIcuLog}
  fi
  if [ -e "${_pthIcuLog}" ]; then
    chattr -i ${_pthIcuLog}
  fi
  if [ -e "${_pthIcuLcy}" ]; then
    chattr -i ${_pthIcuLcy}
  fi
  if [ ! -e "/usr/local/lib/icu/current" ] \
    || [ ! -e "${_pthIcuLog}" ]; then
    _msg "INFO: Installing ICU libs version ${_ICU_MODERN_VRN}..."
    _msg "WAIT: This may take a while, please wait..."
    if [ ! -e "/var/opt/icu-release-${_ICU_MODERN_VRN}/icu4c/source" ]; then
      cd /var/opt
      rm -rf icu*
      _get_dev_src "icu-release-${_ICU_MODERN_VRN}.tar.gz"
    fi
    cd /var/opt/icu-release-${_ICU_MODERN_VRN}/icu4c/source
    _mrun "bash ./configure --prefix=/usr/local" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/local/lib/icu" ]; then
      touch ${_pthIcuLog}
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
_install_icu_jessie() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_icu_jessie"
  fi
  ###--------------------###
  if [ ! -e "${_pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    _pthLog="/var/xdrago_wait/log"
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ -e "${_pthLog}" ]; then
    _pthIcuLog="${_pthLog}/icu-update-${_ICU_LEGACY_VRN}-for-${_OS_CODE}.log"
    _pthIcuLcy="${_pthLog}/icu-update-${_ICU_LEGACY_VRN}.log"
  else
    _pthIcuLog="/root/.icu-update-${_ICU_LEGACY_VRN}-for-${_OS_CODE}.log"
    _pthIcuLcy="/root/.icu-update-${_ICU_LEGACY_VRN}.log"
  fi
  if [ "${_OS_CODE}" = "daedalus" ] \
    && [ -e "${_pthIcuLcy}" ] \
    && [ ! -e "${_pthIcuLog}" ]; then
    touch ${_pthIcuLog}
  fi
  if [ -e "${_pthIcuLog}" ]; then
    chattr -i ${_pthIcuLog}
  fi
  if [ -e "${_pthIcuLcy}" ]; then
    chattr -i ${_pthIcuLcy}
  fi
  if [ ! -e "/usr/local/lib/icu/current" ] \
    || [ ! -e "${_pthIcuLog}" ]; then
    _msg "INFO: Installing ICU libs version ${_ICU_LEGACY_VRN}..."
    _msg "WAIT: This may take a while, please wait..."
    if [ ! -e "/var/opt/icu/source" ]; then
      cd /var/opt
      rm -rf icu*
      _get_dev_src "icu4c-${_ICU_LEGACY_VRN}-src.tgz"
    fi
    cd /var/opt/icu/source/
    _mrun "bash ./configure --prefix=/usr/local" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ -e "/usr/local/lib/icu" ]; then
      touch ${_pthIcuLog}
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
_php_install_deps() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_install_deps"
  fi
  ###--------------------###
  _apt_clean_update
  _mrun "${_INSTAPP} cmake" 2> /dev/null
  _mrun "${_INSTAPP} lbzip2" 2> /dev/null
  if [ ! -e "/usr/local/include/curl/curl.h" ] \
    && [ ! -e "/usr/local/include/curl/easy.h" ]; then
    _mrun "${_INSTAPP} libcurl4-openssl-dev" 2> /dev/null
  fi
  _mrun "${_INSTAPP} libgd-dev" 2> /dev/null
  _mrun "${_INSTAPP} libgd3" 2> /dev/null
  _mrun "${_INSTAPP} libjpeg-dev" 2> /dev/null
  _mrun "${_INSTAPP} libjpeg62" 2> /dev/null
  _mrun "${_INSTAPP} libkrb5-dev" 2> /dev/null
  _mrun "${_INSTAPP} liblzf-dev" 2> /dev/null
  _mrun "${_INSTAPP} libmagickwand-dev" 2> /dev/null
  _mrun "${_INSTAPP} libonig-dev" 2> /dev/null
  _mrun "${_INSTAPP} libsodium-dev" 2> /dev/null
  _mrun "${_INSTAPP} libwebp-dev" 2> /dev/null
  _mrun "${_INSTAPP} libxpm-dev" 2> /dev/null
  _mrun "${_INSTAPP} libzip-dev" 2> /dev/null
  if [ "${_OS_CODE}" = "daedalus" ] \
    || [ "${_OS_CODE}" = "bookworm" ]; then
    if [ ! -e "/root/.rebuild_src_on_auto_before_reboot.info" ]; then
      _mrun "${_INSTAPP} libldap-common" 2> /dev/null
      _mrun "${_INSTAPP} libldap-dev" 2> /dev/null
      _mrun "${_INSTAPP} libldap2-dev" 2> /dev/null
    fi
  else
    _mrun "${_INSTAPP} libldap-common" 2> /dev/null
    _mrun "${_INSTAPP} libldap2-dev" 2> /dev/null
  fi
  if [ "${_OS_CODE}" = "jessie" ]; then
    _install_icu_jessie
  else
    _install_icu_modern
    # _mrun "${_INSTAPP} libicu-dev icu-devtools" 2> /dev/null
  fi
}

#
# Install wkhtmltopdf and wkhtmltoimage.
_if_install_wkhtmltox() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_wkhtmltox"
  fi
  ###--------------------###
  _apt_clean_update
  _mrun "${_INSTAPP} fonts-thai-tlwg" 2> /dev/null
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
        _msg "INFO: Installing wkhtmltox tools v.0.${_WKHTMLTOX_VRN}..."
      fi
      _apt_clean_update
      _mrun "${_INSTAPP} xfonts-75dpi xfonts-base" 2> /dev/null
      _mrun "${_INSTAPP} wkhtmltopdf" 2> /dev/null
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
          _msg "INFO: Installing wkhtmltox tools v.0.${_WKHTMLTOX_VRN}..."
        fi
        cd /var/opt
        rm -rf wkhtmltox*
        mkdir -p /var/opt/wkhtmltox
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _mrun "${_INSTAPP} xfonts-75dpi xfonts-base" 2> /dev/null
          _get_dev_src "wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb.gz"
          dpkg -i "/var/opt/wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb"
          _mrun "apt-get install -f -y" 2> /dev/null
        else
          _mrun "${_INSTAPP} xfonts-75dpi xfonts-base" 2> /dev/null
          _get_dev_src "wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb.gz" 2> /dev/null
          dpkg -i "/var/opt/wkhtmltox/wkhtmltox_0.${_WKHTMLTOX_VRN}.${_WKHTML_SYS_RV}_amd64.deb" 2> /dev/null
          _mrun "apt-get install -f -y" 2> /dev/null
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
        touch ${_pthLog}/wkhtmltox-${_WKHTMLTOX_VRN}-fix.log
        _msg "INFO: The wkhtmltox tools v.0.${_WKHTMLTOX_VRN} installation complete"
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
_clean_drush_twelve() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _clean_drush_twelve"
  fi
  rm -f /usr/bin/drush12*
  ln -sfn /opt/tools/drush/12/drush/vendor/bin/drush /usr/bin/drush12
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Drush ${_DRUSH_TWELVE_VRN} setup complete"
  fi
}

#
# Clean Drush 11.
_clean_drush_eleven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _clean_drush_eleven"
  fi
  rm -f /usr/bin/drush11*
  ln -sfn /opt/tools/drush/11/drush/vendor/bin/drush /usr/bin/drush11
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} setup complete"
  fi
}

#
# Clean Drush 10.
_clean_drush_ten() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _clean_drush_ten"
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
    _msg "INFO: Drush ${_DRUSH_TEN_VRN} setup complete"
  fi
}

#
# Set Drush permissions.
_set_drush_perm() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _set_drush_perm"
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
_get_drush_twelve() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _get_drush_twelve"
  fi
  rm -rf /opt/tools/drush/12/*
  cd /opt/tools/drush/12/
  _get_dev_ext "drush-${_DRUSH_TWELVE_VRN}.tar.gz"
  touch /opt/tools/drush/12/.ctrl.${_tRee}.${_xSrl}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Drush ${_DRUSH_TWELVE_VRN} installation complete"
  fi
}

#
# Install or update Drush 11.
_get_drush_eleven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _get_drush_eleven"
  fi
  rm -rf /opt/tools/drush/11/*
  cd /opt/tools/drush/11/
  _get_dev_ext "drush-${_DRUSH_ELEVEN_VRN}.tar.gz"
  touch /opt/tools/drush/11/.ctrl.${_tRee}.${_xSrl}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} installation complete"
  fi
}

#
# Install or update Drush 10.
_get_drush_ten() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _get_drush_ten"
  fi
  rm -rf /opt/tools/drush/10/*
  cd /opt/tools/drush/10/
  _get_dev_ext "drush-${_DRUSH_TEN_VRN}.tar.gz"
  touch /opt/tools/drush/10/.ctrl.${_tRee}.${_xSrl}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Drush ${_DRUSH_TEN_VRN} installation complete"
  fi
}

#
# Install or update Drush 8.
_get_drush_eight() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _get_drush_eight"
  fi
  rm -rf /opt/tools/drush/8/*
  cd /opt/tools/drush/8/
  _get_dev_ext "drush-${_DRUSH_EIGHT_VRN}.tar.gz"
  touch /opt/tools/drush/8/.ctrl.${_tRee}.${_xSrl}.pid
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Drush ${_DRUSH_EIGHT_VRN} installation complete"
  fi
}

#
# Install or update Drush versions.
_drush_system_install_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _drush_system_install_update"
  fi
  if [ ! -e "/root/.debug-barracuda-installer.cnf" ] \
    && [ ! -e "/root/.skip-aegir-master-upgrade.cnf" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Installing supported Drush versions..."
    fi
    ###
    ### Force all Drush versions update if serial is not new
    rm -f /opt/tools/drush/8/.ctrl.${_tRee}.${_xSrl}.pid
    rm -f /opt/tools/drush/10/.ctrl.${_tRee}.${_xSrl}.pid
    rm -f /opt/tools/drush/11/.ctrl.${_tRee}.${_xSrl}.pid
    rm -f /opt/tools/drush/12/.ctrl.${_tRee}.${_xSrl}.pid
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
        || [ ! -e "/opt/tools/drush/8/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_EIGHT_VRN} re-installation required"
        fi
        _get_drush_eight
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_EIGHT_VRN} already installed"
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
        || [ ! -e "/opt/tools/drush/10/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_TEN_VRN} re-installation required"
        fi
        _get_drush_ten
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_TEN_VRN} already installed"
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
        || [ ! -e "/opt/tools/drush/11/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} re-installation required"
        fi
        _get_drush_eleven
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_ELEVEN_VRN} already installed"
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
        || [ ! -e "/opt/tools/drush/12/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_TWELVE_VRN} re-installation required"
        fi
        _get_drush_twelve
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Drush ${_DRUSH_TWELVE_VRN} already installed"
        fi
      fi
    fi
    _set_drush_perm
    if [ -x "/opt/tools/drush/8/drush/drush.php" ]; then
      rm -f /usr/bin/drush8
      rm -f /usr/bin/drush
      ln -s /opt/tools/drush/8/drush/drush.php /usr/bin/drush8
      ln -s /opt/tools/drush/8/drush/drush.php /usr/bin/drush
    else
      _msg "FAIL: Drush ${_DRUSH_EIGHT_VRN} installation failed!"
    fi
    if [ -x "/opt/tools/drush/10/drush/vendor/drush/drush/drush" ]; then
      _clean_drush_ten
    else
      _msg "FAIL: Drush ${_DRUSH_TEN_VRN} installation failed!"
    fi
    if [ -x "/opt/tools/drush/11/drush/vendor/drush/drush/drush" ]; then
      _clean_drush_eleven
    else
      _msg "FAIL: Drush ${_DRUSH_ELEVEN_VRN} installation failed!"
    fi
    if [ -x "/opt/tools/drush/12/drush/vendor/bin/drush" ]; then
      _clean_drush_twelve
    else
      _msg "FAIL: Drush ${_DRUSH_TWELVE_VRN} installation failed!"
    fi
    chown -R root:root /opt/tools/drush
    cd /opt/tmp
  fi
}

#
# Update packages sources list.
_sources_list_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sources_list_update"
  fi
  ###--------------------###
  apt-get clean -qq 2> /dev/null
  #rm -rf /var/lib/apt/lists/*
  ###--------------------###
  if [ -e "${_pthLog}/apt-deb-src-updates-${_xSrl}.txt" ] \
    || [ -e "/var/log/apt-deb-src-updates-${_xSrl}.txt" ]; then
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
      _msg "INFO: Updating packages sources list..."
    fi
    mv -f ${_aptLiSys} \
      ${_vBs}/sources.list-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    if [ "${_OS_DIST}" = "Devuan" ]; then
	  if [ -z "${_LOCAL_DEVUAN_MIRROR}" ]; then
		_MIRROR=deb.devuan.org
	  else
		_MIRROR=${_LOCAL_DEVUAN_MIRROR}
	  fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: We will use ${_OS_DIST} mirror ${_MIRROR}"
      fi
      cd /var/opt
      echo "## DEVUAN MAIN REPOSITORIES" > ${_aptLiSys}
      echo "deb http://${_MIRROR}/merged ${_OS_CODE} main" >> ${_aptLiSys}
      echo "deb-src http://${_MIRROR}/merged ${_OS_CODE} main" >> ${_aptLiSys}
      echo "" >> ${_aptLiSys}
	  echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${_aptLiSys}
	  echo "deb http://${_MIRROR}/merged ${_OS_CODE}-updates main" >> ${_aptLiSys}
	  echo "deb-src http://${_MIRROR}/merged ${_OS_CODE}-updates main" >> ${_aptLiSys}
	  echo "" >> ${_aptLiSys}
      echo "## DEVUAN SECURITY UPDATES" >> ${_aptLiSys}
      echo "deb http://${_MIRROR}/merged ${_OS_CODE}-security main" >> ${_aptLiSys}
      echo "deb-src http://${_MIRROR}/merged ${_OS_CODE}-security main" >> ${_aptLiSys}
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
          _msg "INFO: Now looking for the best/fastest ${_OS_DIST} mirror"
          _msg "INFO: This may take a while, please wait..."
          _hlpPth="/opt/tmp/boa/aegir/helpers"
          _ffMirr=$(which ffmirror 2>&1)
          _ffList="${_hlpPth}/apt-list-debian.txt"
          if [ -e "${_ffMirr}" ] && [ -e "${_ffList}" ]; then
            _MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
            _MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
            echo " "
            _askThis="Enter your own mirror to use or press enter"
            _askThis="${_askThis} to use the fastest found mirror"
            _prompt_confirm_choice "${_askThis}" ${_MIRROR}
            echo " "
            _MIRROR=${_CONFIRMED_ANSWER}
          else
            _MIRROR=${_LOCAL_DEBIAN_MIRROR}
          fi
        else
          _MIRROR=${_LOCAL_DEBIAN_MIRROR}
        fi
        if ! netcat -w 5 -z ${_MIRROR} 80 ; then
          _msg "INFO: The mirror ${_MIRROR} doesn't respond, let's try default"
          _MIRROR=deb.debian.org
        fi
      fi
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: We will use ${_OS_DIST} mirror ${_MIRROR}"
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
      echo "## DEBIAN MAIN REPOSITORIES" > ${_aptLiSys}
      echo "deb http://${_APT_MIRROR} ${_OS_CODE} main contrib non-free" >> ${_aptLiSys}
      echo "deb-src http://${_APT_MIRROR} ${_OS_CODE} main contrib non-free" >> ${_aptLiSys}
      echo "" >> ${_aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${_aptLiSys}
      echo "deb http://${_APT_MIRROR} ${_APT_REPSRC} main contrib non-free" >> ${_aptLiSys}
      echo "deb-src http://${_APT_MIRROR} ${_APT_REPSRC} main contrib non-free" >> ${_aptLiSys}
      echo "" >> ${_aptLiSys}
      echo "## DEBIAN SECURITY UPDATES" >> ${_aptLiSys}
      echo "deb http://${_SEC_MIRROR} ${_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${_aptLiSys}
      echo "deb-src http://${_SEC_MIRROR} ${_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${_aptLiSys}
    fi
    mkdir -p ${_pthLog}
    touch ${_pthLog}/apt-deb-src-updates-${_xSrl}.txt
    cd /var/opt
  fi
  ###--------------------###
  _apt_clean_update
  ###--------------------###
}

#
# Install OpenSSH from sources.
_sshd_install_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sshd_install_src"
  fi
  if [ "${_OS_CODE}" = "jessie" ]; then
    _OPENSSH_VRN=8.3p1
  fi
  if [ "${_OS_CODE}" = "stretch" ]; then
    _OPENSSH_VRN=9.3p1
  fi
  if [ -x "/usr/local/sbin/sshd" ] \
    && [ -x "/usr/local/bin/ssh" ]; then
    if [ ! -L "/usr/sbin/sshd" ] && [ -x "/usr/sbin/sshd" ]; then
      mv -f /usr/sbin/sshd /usr/sbin/.sshd_bak
      ln -sfn /usr/local/sbin/sshd /usr/sbin/sshd
    fi
    if [ ! -L "/usr/sbin/ssh" ] && [ -x "/usr/sbin/ssh" ]; then
      mv -f /usr/sbin/ssh /usr/sbin/.ssh_bak
      ln -sfn /usr/local/sbin/ssh /usr/sbin/ssh
    fi
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
  if [ -e "/usr/local/sbin/sshd" ]; then
    _SSH_IF_SELINUX=$(ldd /usr/local/sbin/sshd | grep selinux 2>&1)
  fi
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
      _msg "INFO: OpenSSL in SSH is ${_SSH_SSL_ITD}, rebuild to ${_SSL_ITD} required"
    fi
    _SSH_INSTALL_REQUIRED=YES
  fi
  if [[ "${_SSH_IF_SELINUX}" =~ "libselinux" ]]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: SSH was built --with-selinux, rebuild required"
    fi
    _SSH_INSTALL_REQUIRED=YES
  fi
  if [ "${_SSH_FORCE_REINSTALL}" = "YES" ]; then
    _SSH_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: OpenSSH ${_SSH_ITD}, rebuild forced"
    fi
  elif [ "${_SSH_ITD}" != "${_OPENSSH_VRN}" ]; then
    _SSH_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Installed OpenSSH version ${_SSH_ITD}, upgrade required"
    fi
  fi
  if [ "${_SSH_INSTALL_REQUIRED}" = "YES" ]; then
    _msg "INFO: Building OpenSSH ${_OPENSSH_VRN} from sources..."
    _msg "WAIT: This may take a while, please wait..."
    _mrun "${_INITINS} libpam0g-dev" &> /dev/null
    if [ ! -e "/var/lib/sshd" ]; then
      mkdir -p /var/lib/sshd
      chmod -R 700 /var/lib/sshd/
      chown -R root:sys /var/lib/sshd/
      useradd -r -U -d /var/lib/sshd/ -c "sshd privsep" -s /bin/false sshd &> /dev/null
    fi
    _PKG_CONFIG_PATH="${_SSL_LIB_PATH}/pkgconfig"
    cd /var/opt
    rm -rf openssh*
    _get_dev_src "openssh-${_OPENSSH_VRN}.tar.gz"
    cd /var/opt/openssh-${_OPENSSH_VRN}
    LIBS="-ldl -lpthread" PKG_CONFIG_PATH="${_PKG_CONFIG_PATH}" ./configure \
      --with-ssl-dir=${_SSL_PATH} \
      --with-privsep-path=/var/lib/sshd/ \
      --sysconfdir=${_SYSCONFDIR} \
      --prefix=${_PREFIX_SSH} \
      --without-openssl-header-check \
      --with-md5-passwords \
      --with-pam &> /dev/null
    _mrun "make -j $(nproc)" 2> /dev/null
    _mrun "make install" 2> /dev/null
    ldconfig 2> /dev/null
    _mrun "service ssh restart" 2> /dev/null
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
    && [ -x "/usr/local/bin/ssh" ]; then
    if [ ! -L "/usr/sbin/sshd" ] && [ -x "/usr/sbin/sshd" ]; then
      mv -f /usr/sbin/sshd /usr/sbin/.sshd_bak
      ln -sfn /usr/local/sbin/sshd /usr/sbin/sshd
    fi
    if [ ! -L "/usr/sbin/ssh" ] && [ -x "/usr/sbin/ssh" ]; then
      mv -f /usr/sbin/ssh /usr/sbin/.ssh_bak
      ln -sfn /usr/local/sbin/ssh /usr/sbin/ssh
    fi
    if [ -e "${_OLD_SYSCONFDIR}" ]; then
      cp -a ${_OLD_SYSCONFDIR} /var/backups/old_ssh_usr_etc
      rm -f ${_OLD_SYSCONFDIR}/ssh*
      rm -f ${_OLD_SYSCONFDIR}/moduli*
    fi
    _mrun "service ssh restart" 2> /dev/null
  fi
  _SSH_FORCE_REINSTALL=NO
}

#
# Install ImageMagick from sources.
_install_magick_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_magick_src"
  fi
  _MAGICK_SRC_BUILD_CTRL="${_pthLog}/ImageMagick-src-build-${_IMAGE_MAGICK_VRN}.log"
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
        _msg "INFO: Installed ImageMagick version ${_MAGICK_ITD}, upgrade required"
      fi
    fi
  fi
  if [ "${_MAGICK_INSTALL_REQUIRED}" = "YES" ]; then
    _msg "INFO: Installing ImageMagick ${_IMAGE_MAGICK_VRN}..."
    _msg "WAIT: This may take a while, please wait..."
    cd /var/opt
    rm -rf ImageMagick*
    _get_dev_src "ImageMagick-${_IMAGE_MAGICK_VRN}.tar.gz"
    cd /var/opt/ImageMagick-${_IMAGE_MAGICK_VRN}
    _mrun "bash ./configure --prefix=/usr" 2> /dev/null
    _mrun "make -j $(nproc) --quiet" 2> /dev/null
    if [ ! -e "/etc/.ImageMagick-6" ] \
      && [ -e "/etc/ImageMagick-6" ]; then
        cp -a /etc/ImageMagick-6 /etc/.ImageMagick-6
    fi
    if [ ! -e "/etc/.ImageMagick" ] \
      && [ -e "/etc/ImageMagick" ]; then
        cp -a /etc/ImageMagick /etc/.ImageMagick
    fi
    _mrun "apt-get remove imagemagick -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove libmagickwand-dev -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove graphviz -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove libgraphviz-dev -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "make --quiet install" 2> /dev/null
    ldconfig 2> /dev/null
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "HINT: Please modify /usr/etc/ImageMagick-7/policy.xml file, if needed"
    fi
    touch ${_MAGICK_SRC_BUILD_CTRL}
  fi
}

#
# Fix symlinks for libs.
_ssl_crypto_lib_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _ssl_crypto_lib_fix"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Fix for SSL libssl/libcrypto in ${_OS_DIST}/${_OS_CODE}"
  fi
  if [ -e "/root/.install.modern.openssl.cnf" ] \
    && [ -x "/usr/local/ssl3/bin/openssl" ]; then
    _SSL_BINARY=/usr/local/ssl3/bin/openssl
  else
    _SSL_BINARY=/usr/local/ssl/bin/openssl
  fi
  [ -x "${_SSL_BINARY}" ] && _SSL_ITD=$(${_SSL_BINARY} version 2>&1 | awk '{print $2}')
  if [[ "${_SSL_ITD}" =~ "${_OPENSSL_MODERN_VRN}" ]] \
    || [ -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
    _SSL_INSTALLED=MODERN
  elif [[ "${_SSL_ITD}" =~ "1.1.1" ]]; then
    _SSL_INSTALLED=EOL
  elif [[ "${_SSL_ITD}" =~ "1.0.2" ]]; then
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
# Update OpenSSL apt locks.
_ssl_apt_locks_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _ssl_apt_locks_update"
  fi

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
}

#
# Update OpenSSL paths.
_ssl_paths_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _ssl_paths_update"
  fi

  if [ -x "${_SSL_MODERN_BINARY}" ]; then
    _LINK_TO="${_SSL_MODERN_BINARY}"
  elif [ -x "${_SSL_LEGACY_BINARY}" ]; then
    _LINK_TO="${_SSL_LEGACY_BINARY}"
  else
    _LINK_TO=
  fi

  if [ -n "${_LINK_TO}" ]; then
    if [ -e "/usr/bin/openssl" ]; then
      cp -af /usr/bin/openssl /usr/bin/old-openssl-$(date +%y%m%d-%H%M%S 2>&1)
    fi
    ln -sfn ${_LINK_TO} /usr/bin/openssl
    if [ -e "/bin/openssl" ] && [ ! -L "/bin" ]; then
      cp -af /bin/openssl /bin/old-openssl-$(date +%y%m%d-%H%M%S 2>&1)
      ln -sfn ${_LINK_TO} /bin/openssl
    fi
  fi

  [ -x "${1}" ] && _THIS_SSL_ITD=$(${1} version 2>&1 | awk '{print $2}')

  if [[ "${_THIS_SSL_ITD}" =~ "${_OPENSSL_NEW_VRN}" ]]; then
    _SSL_PATH="/usr/local/ssl3"
    _SSL_LIB_PATH="${_SSL_PATH}/lib64"
  else
    _SSL_PATH="/usr/local/ssl"
    _SSL_LIB_PATH="${_SSL_PATH}/lib"
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
}

#
# Install OpenSSL from sources.
_ssl_install_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _ssl_install_src"
  fi

  if [ "${1}" = "Modern" ]; then
    _OPENSSL_BUILD_VRN="${_OPENSSL_NEW_VRN}"
    _THIS_SSL_BINARY="${_SSL_MODERN_BINARY}"
  elif [ "${1}" = "Legacy" ]; then
    _OPENSSL_BUILD_VRN="${_OPENSSL_OLD_VRN}"
    _THIS_SSL_BINARY="${_SSL_LEGACY_BINARY}"
  fi

  ###--------------------###
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Building zlib ${_ZLIB_VRN} from sources first..."
  fi
  cd /var/opt
  rm -rf zlib*
  _get_dev_src "zlib-${_ZLIB_VRN}.tar.gz"
  cd /var/opt/zlib-${_ZLIB_VRN}
  _st_runner "bash ./configure --prefix=/usr" 2> /dev/null
  _mrun "make -j $(nproc) --quiet" 2> /dev/null
  _mrun "make --quiet install" 2> /dev/null
  ldconfig 2> /dev/null

  ###--------------------###
  _msg "INFO: Building ${1} OpenSSL from sources..."
  _msg "WAIT: This may take a while, please wait..."

  if [ ! -e "/var/opt/openssl-${_OPENSSL_BUILD_VRN}" ]; then
    cd /var/opt
    rm -rf openssl*
    wget -q -U iCab ${_urlDev}/src/openssl-${_OPENSSL_BUILD_VRN}.tar.gz
    if [ -e "openssl-${_OPENSSL_BUILD_VRN}.tar.gz" ]; then
      _extract_archive "openssl-${_OPENSSL_BUILD_VRN}.tar.gz"
    else
      _msg "OOPS: failed download from ${_urlDev}/src/openssl-${_OPENSSL_BUILD_VRN}.tar.gz"
    fi
  fi
  if [ -e "/var/opt/openssl-${_OPENSSL_BUILD_VRN}" ]; then
    cd /var/opt/openssl-${_OPENSSL_BUILD_VRN}
    if [ "${1}" = "Modern" ]; then
      _SSL_BUILD_ARGS="--prefix=/usr/local/ssl3 \
        --openssldir=/usr/local/ssl3"
      _patchMakefile=YES
    else
      _SSL_BUILD_ARGS="--prefix=/usr/local/ssl \
        --openssldir=/usr/local/ssl"
      _patchMakefile=YES
    fi
    _mrun "sh ./config \
      shared \
      no-comp \
      no-hw \
      no-ssl3 \
      zlib-dynamic \
      enable-ec_nistp_64_gcc_128 \
      ${_SSL_BUILD_ARGS}" 2> /dev/null
    if [ "${_patchMakefile}" = "YES" ]; then
      sed -i "s/install_docs:.*/install_docs:/g" /var/opt/openssl-${_OPENSSL_BUILD_VRN}/Makefile
    fi
    _mrun "make depend" 2> /dev/null
    _mrun "make -j $(nproc)" 2> /dev/null
    _mrun "make install" 2> /dev/null
  fi

  if [ -x "${_THIS_SSL_BINARY}" ]; then
    _ssl_paths_update "${_THIS_SSL_BINARY}"
    _ssl_apt_locks_update
  else
    _msg "OOPS: OpenSSL version ${_OPENSSL_NEW_VRN} was not installed!"
    _SSL_INSTALL_REQUIRED=
    _SSH_FORCE_REINSTALL=
    _NGX_FORCE_REINSTALL=
    _PHP_FORCE_REINSTALL=
    _GIT_FORCE_REINSTALL=
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
# If Install OpenSSL from sources.
_if_ssl_install_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_ssl_install_src"
  fi

  _SSL_LEGACY_INSTALL_REQUIRED=NO
  _SSL_MODERN_INSTALL_REQUIRED=NO
  _SSL_LEGACY_BINARY="/usr/local/ssl/bin/openssl"
  _SSL_MODERN_BINARY="/usr/local/ssl3/bin/openssl"

  [ ! -x "${_SSL_LEGACY_BINARY}" ] && _SSL_LEGACY_INSTALL_REQUIRED=YES

  # Determine which OpenSSL version to use based on _OS_CODE
  if [ "${_OS_CODE}" = "stretch" ] || [ "${_OS_CODE}" = "jessie" ]; then
    if [ -e "/root/.install.modern.openssl.cnf" ]; then
      chattr -i /root/.install.modern.openssl.cnf
      rm -f /root/.install.modern.openssl.cnf
    fi
    if [ -x "/usr/local/ssl3/bin/openssl" ]; then
      mv -f /usr/local/ssl3 /usr/local/ssl3-off
    fi
  else
    [ ! -x "${_SSL_MODERN_BINARY}" ] && _SSL_MODERN_INSTALL_REQUIRED=YES
    _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
  fi

  if [ "${_OS_CODE}" = "jessie" ]; then
    _OPENSSL_OLD_VRN="${_OPENSSL_LEGACY_VRN}"
  else
    _OPENSSL_OLD_VRN="${_OPENSSL_EOL_VRN}"
  fi

  # Get installed versions
  [ -x "${_SSL_MODERN_BINARY}" ] && _SSL_MODERN_ITD=$(${_SSL_MODERN_BINARY} version 2>&1 | awk '{print $2}')
  [ -x "${_SSL_LEGACY_BINARY}" ] && _SSL_LEGACY_ITD=$(${_SSL_LEGACY_BINARY} version 2>&1 | awk '{print $2}')

  # Determine _SSL_LIB_ITD
  [ -x "${_SSL_MODERN_BINARY}" ] && _SSL_LIB_ITD=$(${_SSL_MODERN_BINARY} version 2>&1 | awk '{print $8}')

  # Check if legacy version needs upgrading
  if [ ! -x "${_SSL_LEGACY_BINARY}" ] || [ "${_SSL_LEGACY_ITD}" != "${_OPENSSL_OLD_VRN}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Legacy OpenSSL (${_SSL_LEGACY_ITD}), upgrade to (${_OPENSSL_OLD_VRN}) required"
    fi
    _SSL_LEGACY_INSTALL_REQUIRED=YES
  fi

  # Check if modern version needs upgrading
  if [ "${_OS_CODE}" != "stretch" ] && [ "${_OS_CODE}" != "jessie" ]; then
    if [ ! -x "${_SSL_MODERN_BINARY}" ] || [ "${_SSL_MODERN_ITD}" != "${_OPENSSL_NEW_VRN}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Modern OpenSSL (${_SSL_MODERN_ITD}), upgrade to (${_OPENSSL_NEW_VRN}) required"
      fi
      _SSL_MODERN_INSTALL_REQUIRED=YES
    fi
  fi

  # Check if OpenSSL 3.x libraries/headers match the binary version
  if [ -x "${_SSL_MODERN_BINARY}" ] && [ "${_SSL_LIB_ITD}" != "${_SSL_MODERN_ITD}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: OpenSSL Lib is (${_SSL_LIB_ITD}) sync with (${_SSL_MODERN_ITD}) required"
    fi
    _SSL_MODERN_INSTALL_REQUIRED=YES
  fi

  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_SSL_FORCE_REINSTALL}" = "YES" ]; then
    _SSL_LEGACY_INSTALL_REQUIRED=YES
    _SSL_MODERN_INSTALL_REQUIRED=YES
    _SSH_FORCE_REINSTALL=YES
    _NGX_FORCE_REINSTALL=YES
    _PHP_FORCE_REINSTALL=YES
    rm -f ${_pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_xSrl}-${_X_VERSION}.log
    rm -f ${_pthLog}/mss-build-${_MSS_VRN}-${_xSrl}-${_X_VERSION}.log
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: OpenSSL rebuild forced"
    fi
  fi

  # Perform the legacy OpenSSL installation or upgrade if required
  if [ "${_SSL_LEGACY_INSTALL_REQUIRED}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Upgrading Legacy OpenSSL to ${_OPENSSL_OLD_VRN}"
    fi
    _ssl_install_src "Legacy"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Legacy OpenSSL ${_OPENSSL_OLD_VRN} is up-to-date."
    fi
  fi

  # Perform the modern OpenSSL installation or upgrade if required
  if [ "${_OS_CODE}" != "stretch" ] && [ "${_OS_CODE}" != "jessie" ]; then
    if [ "${_SSL_MODERN_INSTALL_REQUIRED}" = "YES" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Upgrading Modern OpenSSL to ${_OPENSSL_NEW_VRN}"
      fi
      _ssl_install_src "Modern"
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Modern OpenSSL ${_OPENSSL_NEW_VRN} is up-to-date."
      fi
    fi
  fi
}

#
# Detect, remove, and report broken symlinks
_check_and_remove_broken_symlinks() {
  local _dir=$1

  # Find broken symlinks in the directory
  _broken_symlinks=$(find "${_dir}" -maxdepth 1 -type l ! -exec test -e {} \; -print)

  if [ -n "${_broken_symlinks}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "CLNP: Removing the following broken symlinks from ${_dir}:"
      _msg "CLNP: ${_broken_symlinks}"
    fi

    for _symlink in ${_broken_symlinks}; do
      rm "${_symlink}"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "CLNP: Removed broken symlink: ${_symlink}"
      fi
    done

    # Set the _ifAnySymlinksCleaned variable to true since we removed broken symlinks
    _ifAnySymlinksCleaned=YES
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "CLNP: No broken symlinks found in ${_dir}"
    fi
  fi
}

#
# Check and move disallowed versions
_check_and_move() {
  local _dir=$1

  # Determine the name of the backup subdirectory based on the source directory
  local _backup_dir="${_backLegBase}$(echo "${_dir}" | tr '/' '_')"

  # Find any libcurl.so files in the directory, excluding the allowed version and those without a complete version number
  _found_versions=$(find "${_dir}" -maxdepth 1 -type f -name "libcurl.so.*" ! -name "${_allowedFile}" | grep -E "libcurl\.so\.[0-9]+\.[0-9]+\.[0-9]+$")

  if [ -n "${_found_versions}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "CLNP: Moving the following disallowed versions from ${_dir} to ${_backup_dir}:"
      _msg "CLNP: ${_found_versions}"
    fi

    # Create the backup directory if it doesn't exist
    mkdir -p "${_backup_dir}"

    # Move each found version to the backup directory
    for _file in ${_found_versions}; do
      mv -f "${_file}" "${_backup_dir}/"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "CLNP: Moved ${_file} to ${_backup_dir}/"
      fi
    done

    # Set the _ifAnyFilesCleaned variable to true since we moved files
    _ifAnyFilesCleaned=YES
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "CLNP: Only the allowed version (${_allowedFile}) is present in ${_dir}"
    fi
  fi
}

#
# Install cURL from sources.
_curl_install_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _curl_install_src"
  fi

  if ! command -v lsb_release &> /dev/null; then
    apt-get update -qq &> /dev/null
    apt-get install lsb-release -y -qq &> /dev/null
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  [ "${_OS_CODE}" = "wheezy" ] && _CURL_VRN=7.50.1
  [ "${_OS_CODE}" = "jessie" ] && _CURL_VRN=7.71.1
  [ "${_OS_CODE}" = "stretch" ] && _CURL_VRN=8.2.1

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
      _msg "INFO: Installed cURL/lib ${_CURL_ITD}/${_CURL_LIB_ITD}, upgrade required"
    fi
  fi

  if [ "${_CURL_LIB_ITD}" != "${_CURL_VRN}" ]; then
    _CURL_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Installed cURL/lib ${_CURL_ITD}/${_CURL_LIB_ITD}, rebuild required"
    fi
  fi

  if [ "${_CURL_SSL_ITD}" != "${_OPENSSL_NEW_VRN}" ]; then
    _CURL_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: cURL ${_CURL_ITD} with OpenSSL ${_CURL_SSL_ITD}, rebuild forced"
    fi
  fi

  _BROKEN_CURL_TEST=$(curl --version 2>&1)
  if [[ "${_BROKEN_CURL_TEST}" =~ "libcurl.so.4" ]]; then
    _CURL_INSTALL_REQUIRED=YES
  fi

  if [ "${_PHP_BIN_BROKEN}" = "YES" ] && [ -z "${_CURL_ALREADY_REBUILT}" ]; then
    _CURL_INSTALL_REQUIRED=YES
  fi

  if [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
    _CURL_INSTALL_REQUIRED=YES
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Installed cURL version ${_CURL_ITD} but re-install forced"
    fi
  fi

  if [ "${_OS_CODE}" != "jessie" ] && [ "${_OS_CODE}" != "stretch" ]; then

    # Target version
    _allowedFile="libcurl.so.4.8.0"

    # Directories to check
    _dirsToClean=("/usr/lib" "/usr/local/lib" "/usr/lib/x86_64-linux-gnu")

    # Backup base directory
    _backLegBase="/var/backups/legacy-libcurl-${_X_VERSION}-${_NOW}"

    # Variable to track if any files were moved
    _ifAnyFilesCleaned=NO

    # Variable to track if any broken symlinks were found and removed
    _ifAnySymlinksCleaned=NO

    # Iterate over the directories and apply the _check_and_move function
    for _dir in "${_dirsToClean[@]}"; do
      _check_and_move "${_dir}"
    done

    # Iterate over the directories and apply the _check_and_remove_broken_symlinks function
    for _dir in "${_dirsToClean[@]}"; do
      _check_and_remove_broken_symlinks "${_dir}"
    done

    # Export the _ifAnyFilesCleaned variable for later use
    export _ifAnyFilesCleaned

    # Export the _ifAnySymlinksCleaned variable for later use
    export _ifAnySymlinksCleaned

  fi

  if [ "${_ifAnySymlinksCleaned}" = "YES" ] \
    || [ "${_ifAnyFilesCleaned}" = "YES" ] \
    || [ "${_CURL_INSTALL_REQUIRED}" = "YES" ]; then
    _CURL_INSTALL_REQUIRED=YES
    _bkLibcurlPre="/var/backups/legacy-libcurl-pre-${_CURL_VRN}-${_NOW}"
    mkdir -p ${_bkLibcurlPre}
    mv -f /usr/lib/x86_64-linux-gnu/libcurl.so* ${_bkLibcurlPre}/ &> /dev/null
    mv -f /usr/lib/x86_64-linux-gnu/libcurl.la ${_bkLibcurlPre}/ &> /dev/null
    mv -f /usr/lib/x86_64-linux-gnu/libcurl.a ${_bkLibcurlPre}/ &> /dev/null
  fi

  if [ "${_CURL_INSTALL_REQUIRED}" = "YES" ]; then
    ###--------------------###
    if [ -e "/root/.use.curl.from.packages.cnf" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: cURL from packages is forced with /root/.use.curl.from.packages.cnf"
      fi
      [ -e "/root/.sorted.multi.php.cnf" ] && rm -f /root/.sorted.multi.php.cnf
      if [ -e "/usr/local/bin/curl" ]; then
        mv -f /usr/local/bin/curl /usr/local/bin/curl-src-off-$(date +%y%m%d-%H%M%S 2>&1)
      fi
      if [[ "${_CURL_GET_DPKG}" =~ "hold" ]]; then
        echo "curl install" | dpkg --set-selections &> /dev/null
        if [ -z "${_CURL_ALREADY_REBUILT}" ]; then
          _apt_clean_update
          _mrun "apt-get remove libssl1.0-dev -y --purge --auto-remove -qq" 2> /dev/null
          _mrun "apt-get autoremove -y" 2> /dev/null
          _mrun "${_INSTAPP} libssl-dev" 2> /dev/null
          _mrun "${_INSTAPP} libc-client2007e libc-client2007e-dev" 2> /dev/null
          _mrun "apt-get build-dep curl -y" 2> /dev/null
          _mrun "${_INSTAPP} curl" 2> /dev/null
        fi
      fi
    else
      _apt_clean_update
      _mrun "apt-get remove libssl1.0-dev -y --purge --auto-remove -qq" 2> /dev/null
      _mrun "apt-get autoremove -y" 2> /dev/null
      _mrun "${_INSTAPP} libssl-dev" 2> /dev/null
      _mrun "${_INSTAPP} libc-client2007e libc-client2007e-dev" 2> /dev/null
      _mrun "apt-get build-dep curl -y" 2> /dev/null
      cd /var/opt
      rm -rf curl*
      wget -q -U iCab ${_urlDev}/src/curl-${_CURL_VRN}.tar.gz
      if [ ! -e "curl-${_CURL_VRN}.tar.gz" ]; then
        _msg "OOPS: failed download from ${_urlDev}/src/curl-${_CURL_VRN}.tar.gz"
      else
        _extract_archive "curl-${_CURL_VRN}.tar.gz"
      fi
      if [ -e "/var/opt/curl-${_CURL_VRN}" ]; then
        _msg "INFO: Building cURL ${_CURL_VRN} from sources..."
        _msg "WAIT: This may take a while, please wait..."
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
          _mrun "make -j $(nproc)" 2> /dev/null
          _mrun "make install" 2> /dev/null
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
          _msg "OOPS: Building OpenSSL ${_OPENSSL_NEW_VRN} from sources failed!"
        fi
      else
        _msg "OOPS: cURL ${_CURL_VRN} could not be extracted..."
      fi
      if [ -x "/usr/local/bin/curl" ] \
        && [ ! -e "/var/xdrago/log/.curl_libs_fix_${_CURL_VRN}-${_X_VERSION}-${_NOW}.pid" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Updating cURL ${_CURL_VRN} libs symlinks..."
        fi
        if [ -e "/usr/local/lib/libcurl.so.4.8.0" ]; then
          ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/libcurl.so
          ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/libcurl.so.4
          ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/libcurl.so.4.8.0
          ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/x86_64-linux-gnu/libcurl.so
          ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/x86_64-linux-gnu/libcurl.so.4
          ln -sfn /usr/local/lib/libcurl.so.4.8.0 /usr/lib/x86_64-linux-gnu/libcurl.so.4.8.0
        fi
        if [ -e "/usr/local/lib/libcurl.a" ]; then
          ln -sfn /usr/local/lib/libcurl.a /usr/lib/x86_64-linux-gnu/libcurl.a
          ln -sfn /usr/local/lib/libcurl.a /usr/lib/libcurl.a
        fi
        if [ -e "/usr/local/lib/libcurl.la" ]; then
          ln -sfn /usr/local/lib/libcurl.la /usr/lib/x86_64-linux-gnu/libcurl.la
          ln -sfn /usr/local/lib/libcurl.la /usr/lib/libcurl.la
        fi
      fi
      ldconfig 2> /dev/null
      touch /var/xdrago/log/.curl_libs_fix_${_CURL_VRN}-${_X_VERSION}-${_NOW}.pid &> /dev/null
      _CURL_ALREADY_REBUILT=YES
      if [ -e "/usr/local/include/curl/curl.h" ] \
        && [ -e "/usr/local/include/curl/easy.h" ] \
        && [ -d "/usr/include/x86_64-linux-gnu/curl" ] \
        && [ ! -L "/usr/include/x86_64-linux-gnu/curl" ]; then
        _mrun "apt-get remove libcurl4-openssl-dev -y --purge --auto-remove -qq" 2> /dev/null
        ln -sfn /usr/local/include/curl /usr/include/x86_64-linux-gnu/curl
        ldconfig 2> /dev/null
      fi
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: cURL version detected ${_CURL_ITD}, OK"
    fi
  fi
}

#
# Symlink to dash.
_symlink_to_dash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _symlink_to_dash"
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
_symlink_to_bash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _symlink_to_bash"
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
_switch_to_dash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _switch_to_dash"
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
_switch_to_bash() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _switch_to_bash"
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
_strict_bin_permissions() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _strict_bin_permissions"
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

  cp -af ${_bldPth}/aegir/helpers/websh.sh.txt /bin/websh
  chmod 755 /bin/websh
  chown root:root /bin/websh
  chown root:root /etc/passwd*
  chmod 644 /etc/passwd*
  chown root:shadow /etc/shadow*
  chmod 640 /etc/shadow*
}

#
# Turn Off AppArmor temporarily.
_turn_off_apparmor_temporarily() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _turn_off_apparmor_temporarily"
  fi
  _isAppArmOn=N
  if [ -e "/sys/module/apparmor/parameters/enabled" ]; then
    _isAppArmOn=$(cat /sys/module/apparmor/parameters/enabled 2>&1)
    _isAppArmOn=$(echo -n ${_isAppArmOn} | tr -d "\n" 2>&1)
  fi
  if [ "${_isAppArmOn}" = "Y" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "ARMR: Turning off AppArmor temporarily..."
    fi
    rm -rf /var/cache/apparmor/*
    _mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
    _mrun "aa-complain /etc/apparmor.d/*" 2> /dev/null
    _mrun "service apparmor stop" 2> /dev/null
    _mrun "aa-teardown" 2> /dev/null
    _mrun "service auditd stop" 2> /dev/null
  fi
}

#
# Enforce AppArmor profiles.
_if_enforce_apparmor_profiles() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_enforce_apparmor_profiles"
  fi
  if [ "${_isAppArmOn}" = "Y" ] || [ -d "/etc/apparmor.d" ]; then
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
          _msg "ARMR: Restarting services to switch them to the enforced mode"
        fi
        _mrun "bash /var/xdrago/move_sql.sh" 2> /dev/null
        wait
        _mrun "service redis-server reload" 2> /dev/null
        _mrun "killall unbound" 2> /dev/null
        _mrun "killall pure-ftpd" 2> /dev/null
        _mrun "killall rsyslogd" 2> /dev/null
        _mrun "service rsyslog restart" 2> /dev/null
      fi
    fi
  fi
}

#
# Sync AppArmor profiles.
_sync_apparmor_profiles() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sync_apparmor_profiles"
  fi
  if [ "${_isAppArmOn}" = "Y" ] || [ -d "/etc/apparmor.d" ]; then
    _msg "ARMR: All profiles will be updated now..."
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
      cp -af ${_locCnf}/apparmor/* /etc/apparmor.d/
      if [ -d "/etc/apparmor.d/disable" ]; then
        cp -af /etc/apparmor.d/*ssh* /etc/apparmor.d/disable/ &> /dev/null
      fi
    fi
    if [ ! -e "/root/.run-to-daedalus.cnf" ] \
      && [ ! -e "/root/.run-to-chimaera.cnf" ] \
      && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
      _msg "WAIT: This may take a while, please wait..."
    fi
    for _proFile in `find /etc/apparmor.d/ -maxdepth 1 -mindepth 1 -type f | sort`; do
      _profName=$(echo ${_proFile} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
      if [ ! -z "${_isAppArmorComplain}" ] \
        && [ -x "${_isAppArmorComplain}" ]; then
        if [ ! -e "/root/.run-to-daedalus.cnf" ] \
          && [ ! -e "/root/.run-to-chimaera.cnf" ] \
          && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
          if [ "${_isAppArmOn}" = "Y" ]; then
            _mrun "apparmor_parser -Q /etc/apparmor.d/${_profName}" 2> /dev/null
          fi
        fi
      fi
      chmod 644 ${_proFile}
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
    if [ "${_isAppArmOn}" = "Y" ]; then
      if [ -e "/root/.activate.apparmor.cnf" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "ARMR: Activating AppArmor in the complain mode"
        fi
        _mrun "rm -rf /var/cache/apparmor/*" 2> /dev/null
        if [ -x "/etc/init.d/apparmor" ]; then
          _mrun "service apparmor restart" 2> /dev/null
        fi
        if [ -x "/etc/init.d/auditd" ]; then
          _mrun "service auditd restart" 2> /dev/null
        fi
        _mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
        _mrun "aa-complain /etc/apparmor.d/*" 2> /dev/null
      elif [ -e "/root/.enforce.apparmor.cnf" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "ARMR: Activating AppArmor in the enforced mode"
        fi
        _mrun "rm -rf /var/cache/apparmor/*" 2> /dev/null
        if [ -x "/etc/init.d/apparmor" ]; then
          _mrun "service apparmor restart" 2> /dev/null
        fi
        if [ -x "/etc/init.d/auditd" ]; then
          _mrun "service auditd restart" 2> /dev/null
        fi
        _mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
        _mrun "aa-enforce /etc/apparmor.d/*" 2> /dev/null
        if [ "${_OS_CODE}" != "stretch" ] && [ "${_OS_CODE}" != "jessie" ]; then
          _if_enforce_apparmor_profiles
        fi
      elif [ -e "/root/.disable.apparmor.cnf" ] \
        || [ ! -e "/root/.activate.apparmor.cnf" ] \
        || [ ! -e "/root/.enforce.apparmor.cnf" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "ARMR: Deactivating AppArmor using aa-teardown"
        fi
        _mrun "rm -rf /var/cache/apparmor/*" 2> /dev/null
        _mrun "apparmor_parser -r /etc/apparmor.d/*" 2> /dev/null
        _mrun "aa-complain /etc/apparmor.d/*" 2> /dev/null
        if [ -x "/etc/init.d/apparmor" ]; then
          _mrun "service apparmor stop" 2> /dev/null
          _mrun "update-rc.d -f apparmor remove" 2> /dev/null
        fi
        if [ -x "/etc/init.d/auditd" ]; then
          _mrun "service auditd stop" 2> /dev/null
          _mrun "update-rc.d -f auditd remove" 2> /dev/null
        fi
        if [ -x "/usr/sbin/aa-teardown" ]; then
          _mrun "aa-teardown" 2> /dev/null
        fi
      fi
    fi
  fi
}

#
# Manage AppArmor.
_if_install_apparmor() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_apparmor"
  fi
  ###--------------------###
  _isAppArmorRevFile="/sys/kernel/security/apparmor/revision"
  _isAppArmorGrubFile="/etc/default/grub.d/apparmor.cfg"
  _isAppArmorComplain=$(which aa-complain 2>&1)
  _isAppArmorStatus=$(which aa-status 2>&1)
  _isAppArmorGrub=NO
  if [ -e "${_isAppArmorGrubFile}" ]; then
    _GRUB_APPARMOR_TEST=$(grep "apparmor=1 security=apparmor" ${_isAppArmorGrubFile} 2>&1)
    if [[ "${_GRUB_APPARMOR_TEST}" =~ "apparmor=1 security=apparmor" ]]; then
      _isAppArmorGrub=YES
    fi
  fi
  if [ ! -e "${_isAppArmorRevFile}" ] \
    || [ ! -e "${_isAppArmorGrubFile}" ] \
    || [ -z "${_isAppArmorComplain}" ] \
    || [ -z "${_isAppArmorStatus}" ] \
    || [ "${_isAppArmorGrub}" = "NO" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "ARMR: The system AppArmor and auditd will be installed now, however..."
      _msg "ARMR: ...it will become active only after you reboot this server"
      _msg "ARMR: Use 'boa reboot' command for optimized reboot"
      _msg "WAIT: This may take a while, please wait..."
    fi
    _mrun "${_INSTAPP} auditd \
      apparmor \
      apparmor-utils \
      apparmor-notify \
      apparmor-profiles" 2> /dev/null
    mkdir -p /etc/default/grub.d
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=1 security=apparmor"' \
      | tee ${_isAppArmorGrubFile} &> /dev/null
    update-grub &> /dev/null
  fi
  _isAppArmOn=N
  if [ -e "/sys/module/apparmor/parameters/enabled" ]; then
    _isAppArmOn=$(cat /sys/module/apparmor/parameters/enabled 2>&1)
    _isAppArmOn=$(echo -n ${_isAppArmOn} | tr -d "\n" 2>&1)
  fi
  if [ "${_isAppArmOn}" = "Y" ]; then
    _sync_apparmor_profiles
    [ -e "/root/.turn_off_apparmor_in_octopus.cnf" ] && rm -f /root/.turn_off_apparmor_in_octopus.cnf
  fi
}

#
# Final cleanup.
_finale() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _finale"
  fi
  ###--------------------###
  if [ "${_STATUS}" = "INIT" ]; then
    _L_ST="install"
    touch ${_pthLog}/SA-CORE-2014-005-fixed-d7.log
  else
    _L_ST="upgrade"
  fi
  _msg "CARD: Now charging your credit card for this magic show..."
  _mrun "sleep 2"
  _msg "CARD: It will take a moment to process your payment..."
  _mrun "sleep 5"
  _msg "JOKE: Just kidding !!! Enjoy your Aegir Hosting System :)"
  _mrun "sleep 3"
  echo " "
  _KERNEL_UP=NO
  if [ -e "/run/reboot-required.pkgs" ]; then
    _T_KERNEL_TEST=$(grep linux /run/reboot-required.pkgs 2>&1)
    if [[ "${_T_KERNEL_TEST}" =~ "linux" ]]; then
      _KERNEL_UP=YES
    fi
  fi
  if [ "${_UP_LNX}" = "YES" ] || [ "${_KERNEL_UP}" = "YES" ]; then
    _msg "NOTE: Your OS kernel has been upgraded"
    _msg "NOTE: Please reboot this server to activate the new kernel"
    _msg "NOTE: Use 'boa reboot' command for optimized reboot"
    echo " "
    _mrun "sleep 8"
  fi
  _msg "Final post-${_L_ST} cleaning, one moment..."
  _barracuda_cnf_cleanup
  if [ -e "/var/log/barracuda_log.txt" ]; then
    _T_SERIES_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
    if [[ "${_T_SERIES_TEST}" =~ "BOA-4." ]] \
      || [[ "${_T_SERIES_TEST}" =~ "BOA-3." ]] \
      || [[ "${_T_SERIES_TEST}" =~ "BOA-2.4." ]] \
      || [[ "${_T_SERIES_TEST}" =~ "BOA-2.3.8" ]]; then
      _DO_NOTHING=YES
    else
      _DO_NOTHING=YES
      # _fix_core_dgd
    fi
  fi
  if [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
    _MTD_VR="BOA-5.4.0-omm"
  elif [ -e "/root/.host8.cnf" ]; then
    _MTD_VR="BOA-5.4.0-aln"
  else
    _MTD_VR="${_X_VERSION}"
  fi
  mv -f /etc/motd ${_vBs}/dragon/t/motd-pre-${_xSrl}-${_MTD_VR}-${_NOW} &> /dev/null
  mv -f /etc/motd-pre-* ${_vBs}/dragon/t/ &> /dev/null
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
  _if_hosted_sys
  if [ "${_hostedSys}" = "YES" ]; then
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
  rm -f ${_pthLog}/protected-vhosts-clean.log
  rm -f ${_vBs}/.auth.IP.list*
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${_mtrNgx}/vhost.d/adminer.* &> /dev/null
  wait
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${_mtrNgx}/vhost.d/cgp.* &> /dev/null
  wait
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${_mtrNgx}/vhost.d/chive.* &> /dev/null
  wait
  sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
    ${_mtrNgx}/vhost.d/sqlbuddy.* &> /dev/null
  wait
  find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
  chmod 700 /root
  if [ ! -e "/etc/init.d/buagent" ] \
    && [ -e "${_vBs}/buagent-pre-${_xSrl}-${_X_VERSION}-${_NOW}" ]; then
    mv -f ${_vBs}/buagent-pre-${_xSrl}-${_X_VERSION}-${_NOW} \
      /etc/init.d/buagent &> /dev/null
  fi
  _CSF_CRON_TEST=$(grep water /etc/crontab 2>&1)
  if [ -e "/etc/csf/csf.deny" ] \
    && [ -x "/usr/sbin/csf" ] \
    && [[ "${_CSF_CRON_TEST}" =~ "water" ]]; then
    sed -i "s/.*fire.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "s/.*water.*//g" /etc/crontab &> /dev/null
    wait
    sed -i "/^$/d" /etc/crontab &> /dev/null
    wait
  fi
  killall -9 memcached &> /dev/null
  _php_deprecated_cleanup
  _php_single_initd_cleanup
  if [ -e "/root/.skip-aegir-master-upgrade.cnf" ] \
    && [ -e "/root/.completed_post_major_os_upgrade.info" ] \
    && [ ! -e "/root/.run_post_major_os_upgrade.info" ]; then
    rm -f /root/.skip-aegir-master-upgrade.cnf
  fi
  echo "FINALE" > /root/.latest-barracuda-upgrade-finale.info
  if [ ! -e "/root/.upstart.cnf" ]; then
    _mrun "service cron start" 2> /dev/null
  fi
  if [ -x "/usr/sbin/csf" ] \
    && [ -e "/etc/csf/csf.deny" ] \
    && [ ! -x "/etc/csf/csfpost.sh" ]; then
    echo "" > /etc/csf/csfpost.sh
    echo "iptables -t raw -A PREROUTING -p tcp --dport 21 -j CT --helper ftp" >> /etc/csf/csfpost.sh
    echo "iptables -t raw -A OUTPUT -p tcp --dport 21 -j CT --helper ftp" >> /etc/csf/csfpost.sh
    chmod 700 /etc/csf/csfpost.sh
    _mrun "service lfd stop" 2> /dev/null
    wait
    kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
    killall sleep &> /dev/null
    rm -f /etc/csf/csf.error
    csf -x  &> /dev/null
    wait
    _mrun "service clean-boa-env start" 2> /dev/null
    wait
    _if_fix_iptables_symlinks
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
    grep DHCPREQUEST "${_DHCP_LOG}" | awk '{print $12}' | sort -u | while read -r _IP; do
      if [[ ${_IP} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r oct1 oct2 oct3 oct4 <<< "${_IP}"
        if (( oct1 <= 255 && oct2 <= 255 && oct3 <= 255 && oct4 <= 255 )); then
          echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow
        fi
      fi
    done
    csf -q  &> /dev/null
    _mrun "service lfd start" 2> /dev/null
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
  _msg "BYE!"
}

_run_aptitude_deps_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _run_aptitude_deps_install"
  fi
  _if_to_do_fix
  if [ "${_OS_DIST}" = "Devuan" ]; then
    ${_INITINS} devuan-keyring &> /dev/null
  elif [ "${_OS_DIST}" = "Debian" ]; then
    ${_INITINS} debian-keyring debian-archive-keyring &> /dev/null
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _msg "INFO: Installing a large list of libraries and tools..."
  elif [ "${_STATUS}" = "UPGRADE" ]; then
    _msg "INFO: Upgrading a large list of libraries and tools..."
  fi
  _msg "WAIT: This may take a while, please wait..."
  _apt_clean_update
  _mrun "apt-get remove percona-xtrabackup-24 -y --purge --auto-remove -qq" 2> /dev/null
  _mrun "apt-get autoremove -y" 2> /dev/null
  _mrun "${_INSTAPP} build-essential libsasl2-modules" 2> /dev/null
  _mrun "${_INSTAPP} time vim cvs makepasswd" 2> /dev/null
  _mrun "${_INSTAPP} man-db dnsutils sudo symlinks iptables" 2> /dev/null
  _mrun "${_INSTAPP} autoconf automake autotools-dev m4 bc" 2> /dev/null
  if [ ! -x "/usr/local/bin/curl" ]; then
    _mrun "apt-get build-dep curl -y" 2> /dev/null
    _mrun "${_INSTAPP} curl" 2> /dev/null
  fi
  _mrun "apt-get remove libssl1.0-dev -y --purge --auto-remove -qq" 2> /dev/null
  _mrun "${_INSTAPP} libssl-dev" 2> /dev/null
  _mrun "${_INSTAPP} libc-client2007e libc-client2007e-dev" 2> /dev/null
  _mrun "${_INSTAPP} mcrypt libc-client-dev" 2> /dev/null
  if [ "${_OS_DIST}" = "Devuan" ]; then
    _mrun "${_INSTAPP} apticron aptitude apt-listchanges" 2> /dev/null
  else
    _mrun "${_INSTAPP} apticron aptitude" 2> /dev/null
    _mrun "dpkg --remove --force-remove-reinstreq apt-listchanges" 2> /dev/null
  fi
  _mrun "${_INSTAPP} sysstat telnet cron gnupg2 gnupg" 2> /dev/null
  _mrun "${_INSTAPP} unzip unrtf wdiff pwgen flex re2c" 2> /dev/null
  _mrun "${_INSTAPP} rsync strace ntpdate python-dev" 2> /dev/null
  _mrun "${_INSTAPP} mc whois zlib1g zlib1g-dev librsync-dev" 2> /dev/null
  _mrun "${_INSTAPP} sqlite3 libsqlite3-dev s4cmd" 2> /dev/null
  _mrun "${_INSTAPP} ssh ssl-cert libpam-umask shtool" 2> /dev/null
  _mrun "${_INSTAPP} xml-core xml2 xpdf libtool rrdtool" 2> /dev/null
  _mrun "${_INSTAPP} ncurses-dev ncurses-term sipcalc" 2> /dev/null
  _OS_LIST="daedalus chimaera bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _mrun "${_INSTAPP} ncal" 2> /dev/null
    fi
  done
  _mrun "${_INSTAPP} netcat libzip-dev libwww-perl" 2> /dev/null
  _mrun "${_INSTAPP} libfontconfig1 libfreetype6 libfreetype6-dev" 2> /dev/null
  _mrun "${_INSTAPP} libfribidi0 libgeoip-dev libgeoip1 libgmp3-dev" 2> /dev/null
  _mrun "${_INSTAPP} libonig-dev libpq5 libxml2-dev libxpm4" 2> /dev/null
  _mrun "${_INSTAPP} libxslt-dev libxslt1-dev libxslt1.1 subversion" 2> /dev/null
  _mrun "${_INSTAPP} libaprutil1 libapr1 ldap-utils ipset" 2> /dev/null
  _mrun "${_INSTAPP} pdftk patchutils p7zip-full fontconfig-config" 2> /dev/null
  _mrun "${_INSTAPP} bison catdoc cython3 geoip-database gettext" 2> /dev/null
  _mrun "${_INSTAPP} clamav clamav-base clamav-daemon clamdscan" 2> /dev/null
  _mrun "${_INSTAPP} ghostscript htop lemon lftp nano" 2> /dev/null
  _mrun "${_INSTAPP} python3-dev python3-debian python3-magic" 2> /dev/null
  if [ -e "/root/.dont.use.fancy.bash.login.cnf" ] \
    && [ -e "/usr/bin/screenfetch" ]; then
    _mrun "apt-get remove toilet -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove figlet -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove screenfetch -y --purge --auto-remove -qq" 2> /dev/null
  else
    _mrun "${_INSTAPP} toilet figlet screenfetch" 2> /dev/null
  fi
  _fix_postfix
  _st_runner "${_INSTAPP} ${_MAILSERV}" 2> /dev/null
  _st_runner "${_INSTAPP} ${_APT_XTRA}" 2> /dev/null
  _st_runner "${_INSTAPP} ${_EXTRA_LIB_APT}" 2> /dev/null
  _st_runner "${_INSTAPP} ${_EXTRA_PACKAGES}" 2> /dev/null
  _st_runner "${_INSTAPP} ${_SYSLOGD}" 2> /dev/null
  _EXTRA_APT="tree"
  _st_runner "apt-get install ${_EXTRA_APT} ${_nrmUpArg}" 2> /dev/null
  if [ -e "/etc/init.d/php5-fpm" ]; then
    _mrun "service php5-fpm stop" 2> /dev/null
    _mrun "update-rc.d -f php5-fpm remove" 2> /dev/null
  fi
}

_basic_packages_install_on_init() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _basic_packages_install_on_init"
  fi
  _apt_clean_update
  if [ ! -e "/var/aegir/drush" ] && [ ! -e "/var/xdrago/manage_solr_config.sh" ]; then
#     _mrun "apt-get remove unscd -y --purge --auto-remove -qq" 2> /dev/null
#     _mrun "apt-get remove dbus -y --purge --auto-remove -qq" 2> /dev/null
#     if [ -e "/usr/share/dbus-1" ]; then
#       rm -f /usr/share/dbus-1/*/*freedesktop*
#     fi
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
      _msg "INFO: Installing some basic tools..."
      _apt_clean_update
      _mrun "${_INITINS} locales" &> /dev/null
      _locales_check_fix
      _mrun "${_INITINS} lsb-release" &> /dev/null
      _mrun "${_INITINS} dnsutils" &> /dev/null
      _mrun "${_INITINS} netcat" &> /dev/null
      _mrun "${_INITINS} netcat-traditional" &> /dev/null
      _mrun "${_INITINS} aptitude" &> /dev/null
      _mrun "${_INITINS} curl" &> /dev/null
      _mrun "${_INITINS} wget" &> /dev/null
      _mrun "${_INITINS} hostname" &> /dev/null
      _mrun "${_INITINS} net-tools" &> /dev/null
      _mrun "${_INITINS} ntpdate" &> /dev/null
      touch /root/.step.init.basic.cnf
    fi
  fi
}

_more_packages_install_on_init() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _more_packages_install_on_init"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _msg "INFO: Installing more basic tools now..."
    if [ -e "/etc/debian_version" ]; then
      _L_DEB_TEST=$(grep "^5." /etc/debian_version 2>&1)
      if [ ! -z "${_L_DEB_TEST}" ]; then
        sed -i "s/^deb.*security.debian.org.*/## security updates no longer available/g" ${_aptLiSys} &> /dev/null
        wait
        sed -i "s/ftp.*debian.org/archive.debian.org/g" \
          ${_aptLiSys} &> /dev/null
        wait
        sed -i "s/volatile.debian.org/archive.debian.org/g" \
          ${_aptLiSys} &> /dev/null
        wait
      fi
    fi
    _apt_clean_update
    _mrun "${_INITINS} locales" &> /dev/null
    _locales_check_fix
    _mrun "${_INITINS} git" &> /dev/null
    _mrun "${_INITINS} git-core" &> /dev/null
    _mrun "${_INITINS} git-man" &> /dev/null
    _mrun "${_INITINS} axel" &> /dev/null
    _mrun "${_INITINS} build-essential" &> /dev/null
  fi
}

_if_proxysql_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_proxysql_update"
  fi
  if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
    _isPxy=$(which proxysql 2>&1)
    _REINSTALL_PXC=NO
    if [ -x "${_isPxy}" ]; then
      _PXY=$(${_isPxy} --version 2>&1 \
        | tr -d "\n" \
        | cut -d"-" -f1 \
        | awk '{ print $3}' 2>&1)
      _msg "INFO: ProxySQL version detected ${_PXY}"
      _pGc="/usr/bin/proxysql_galera_checker"
      if [ ! -e "${_pGc}" ]; then
        _UP_PXC=YES
        _REINSTALL_PXC=YES
      else
        _PAV_TEST=$(grep Maestro ${_pGc} 2>&1)
        if [[ ! "${_PAV_TEST}" =~ "Maestro" ]]; then
          _UP_PXC=YES
        fi
      fi
      _pNm="/usr/bin/proxysql_node_monitor"
      if [ ! -e "${_pNm}" ]; then
        _UP_PXC=YES
        _REINSTALL_PXC=YES
      else
        _PAV_TEST=$(grep Vivaldi ${_pNm} 2>&1)
        if [[ ! "${_PAV_TEST}" =~ "Vivaldi" ]]; then
          _UP_PXC=YES
        fi
      fi
    fi
    _isPxyVer=$(proxysql --version 2>&1)
    if [[ ! "${_isPxyVer}" =~ "${_PXC_VRN}" ]]; then
      _UP_PXC=YES
    fi
    if [ "${_UP_PXC}" = "YES" ] \
      && [ "${_OS_DIST}" = "Debian" ]; then
      if [ "${_REINSTALL_PXC}" = "YES" ]; then
        _msg "INFO: Running ProxySQL upgrade to ${_PXC_VRN}..."
      else
        _msg "INFO: Running ProxySQL re-install to ${_PXC_VRN}..."
        _apt_clean_update
        _mrun "${_INSTAPP} sysbench" 2> /dev/null
        _mrun "${_INSTAPP} debconf-utils" 2> /dev/null
        _mrun "apt-get remove proxysql -y --purge --auto-remove -qq" 2> /dev/null
        _apt_clean_update
        _mrun "${_INSTAPP} proxysql" 2> /dev/null
      fi
      _isPxy=$(which proxysql 2>&1)
      if [ ! -x "${_isPxy}" ]; then
        _apt_clean_update
        _mrun "${_INSTAPP} sysbench" 2> /dev/null
        _mrun "${_INSTAPP} debconf-utils" 2> /dev/null
        _mrun "${_INSTAPP} proxysql" 2> /dev/null
      else
        _mrun "apt-get install --only-upgrade ${_nrmUpArg} proxysql" 2> /dev/null
      fi
      if [ ! -e "/etc/proxysql.cnf" ]; then
        _msg "OOPS: Unable to open config file /etc/proxysql.cnf"
      else
        chmod 640 /etc/proxysql.cnf
      fi
      if [ ! -e "/etc/proxysql-admin.cnf" ]; then
        _msg "OOPS: Unable to open config file /etc/proxysql-admin.cnf"
      else
        chmod 640 /etc/proxysql-admin.cnf
      fi
      if [ -x "${_isPxy}" ] \
        && [ -e "/etc/proxysql.cnf" ] \
        && [ -e "/etc/proxysql-admin.cnf" ]; then
        _PXY=$(${_isPxy} --version 2>&1 \
          | tr -d "\n" \
          | cut -d"-" -f1 \
          | awk '{ print $3}' 2>&1)
        _msg "INFO: ProxySQL version detected ${_PXY}"
        _msg "INFO: Updating ProxySQL Node Monitor..."
        if [ -e "${_pNm}" ]; then
          rm -f ${_pNm}
        fi
        _tBn="tools/bin"
        _tURL="${_urlHmr}/${_tBn}/proxysql_node_monitor"
        _msg "PNM download URL is ${_tURL}"
        curl -I ${_tURL}
        curl ${_crlGet} "${_tURL}" -o ${_pNm}
        if [ ! -e "${_pNm}" ]; then
          curl ${_crlGet} "${_tURL}" -o ${_pNm}
        else
          _PAV_TEST=$(grep Vivaldi ${_pNm} 2>&1)
          if [[ ! "${_PAV_TEST}" =~ "Vivaldi" ]]; then
            rm -f ${_pNm}
            curl ${_crlGet} "${_tURL}" -o ${_pNm}
          fi
        fi
        curl ${_crlGet} "${_tURL}" -o ${_pNm}
        ls -la ${_pNm}
        if [ -e "${_pNm}" ]; then
          chmod 755 ${_pNm}
          _msg "INFO: `${_pNm} --version`"
        fi

        _msg "INFO: Updating ProxySQL Galera Checker..."
        if [ -e "${_pGc}" ]; then
          rm -f ${_pGc}
        fi
        _tBn="tools/bin"
        _tURL="${_urlHmr}/${_tBn}/proxysql_galera_checker"
        _msg "PGC download URL is ${_tURL}"
        curl -I ${_tURL}
        curl ${_crlGet} "${_tURL}" -o ${_pGc}
        if [ ! -e "${_pGc}" ]; then
          curl ${_crlGet} "${_tURL}" -o ${_pGc}
        else
          _PAV_TEST=$(grep Maestro ${_pGc} 2>&1)
          if [[ ! "${_PAV_TEST}" =~ "Maestro" ]]; then
            rm -f ${_pGc}
            curl ${_crlGet} "${_tURL}" -o ${_pGc}
          fi
        fi
        curl ${_crlGet} "${_tURL}" -o ${_pGc}
        ls -la ${_pGc}

        if [ -e "${_pGc}" ]; then
          chmod 755 ${_pGc}
          _msg "INFO: `${_pGc} --version`"
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
            _msg "INFO: Restarting ProxySQL server..."
          fi
          _mrun "service proxysql restart" 2> /dev/null
          mysql -uadmin -p`cat /root/.my.proxysql_adm_pwd.txt` -h127.0.0.1 -P6032 -e "SELECT * FROM scheduler\G"
          mysql -uadmin -p`cat /root/.my.proxysql_adm_pwd.txt` -h127.0.0.1 -P6032 -e "SELECT * FROM mysql_servers;"
        else
          _msg "OOPS: ProxySQL Galera Checker will not work!"
        fi
      else
        _msg "OOPS: ProxySQL will not work!"
      fi
    fi
  fi
}

_if_rebuild_src_on_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_rebuild_src_on_major_os_upgrade"
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

_if_long_generate_on_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_long_generate_on_major_os_upgrade"
  fi
  if [ -e "/root/.run-to-daedalus.cnf" ] \
    || [ -e "/root/.run-to-chimaera.cnf" ] \
    || [ -e "/root/.run-to-beowulf.cnf" ]; then
    _ALLOW_LONG_GENERATE=NO
  else
    _ALLOW_LONG_GENERATE=YES
  fi
}

_if_post_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_post_major_os_upgrade"
  fi
  if [ -e "/root/.run_post_major_os_upgrade.info" ] \
    && [ ! -e "/root/.completed_post_major_os_upgrade.info" ]; then

    _apt_clean_update_no_releaseinfo_change
    _mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null

    _msg "INFO: Cleaning up any systemd remnants..."
    _sysvinit_install
    _systemd_remove_apt_cmd
    _sysvinit_install

    _msg "INFO: Removing any packages orphaned by the migration process..."
    _mrun "apt-get autoremove --purge -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get autoclean -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get autoremove -y --purge --auto-remove -qq" 2> /dev/null

    _msg "INFO: Running dist-upgrade to complete the system upgrade..."
    _msg "WAIT: This may take a while, please wait..."
    _mrun "apt-get dist-upgrade ${_dstUpArg}" 2> /dev/null
    [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
    if [ -e "/root/.allow.downgrades.on.same.os.dist.upgrade.cnf" ]; then
      _msg "INFO: dist-upgrade with --allow-downgrades option is used"
      _mrun "apt-get dist-upgrade -y --allow-downgrades" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
    else
      _mrun "apt-get dist-upgrade -y" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
    fi
    _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
    _mrun "apt-get ${_dstUpArg} install" 2> /dev/null
    [ -e "/root/.top-daedalus.cnf" ] && /usr/bin/apt-get install base-files=12.4devuan3 -y --allow-downgrades 2> /dev/null
    ### Update rsyslog configuration early
    _rsyslog_config_update
    ### Reload key services if needed early
    _mrun "service redis-server reload" 2> /dev/null
    _mrun "service nginx reload" 2> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        _mrun "service php${e}-fpm reload" 2> /dev/null
      fi
    done
    if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
      perl /var/xdrago_wait/proc_num_ctrl.pl &
    else
      perl /var/xdrago/proc_num_ctrl.pl &
    fi

    _REBUILD_SRC_ON_AUTO_NOW=YES
    if [ -e "/root/.run-to-daedalus.cnf" ] \
      || [ -e "/root/.run-to-chimaera.cnf" ] \
      || [ -e "/root/.run-to-beowulf.cnf" ]; then
      _REBUILD_SRC_ON_AUTO_NOW=NO
      _php_if_versions_cleanup_cnf
    fi

    if [ "${_ALLOW_HEAVY_REBUILDS}" = "YES" ]; then
      _REBUILD_SRC_ON_AUTO_NOW=YES
    fi

    if [ -e "/root/.big_hop_on_major_os_upgrade.info" ] \
      && [ ! -e "/root/.rebuild_src_on_auto_before_reboot.info" ] \
      && [ "${_REBUILD_SRC_ON_AUTO_NOW}" = "YES" ]; then
      _msg "INFO: Time for re-installing services built from sources..."
      if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
        rm -f /var/xdrago_wait/log/*.log
        rm -f /var/xdrago_wait/log/._php_libs_fix_*.pid
      else
        rm -f /var/xdrago/log/*.log
        rm -f /var/xdrago/log/._php_libs_fix_*.pid
      fi
      _PURGE_MODE=OFF
      _NGX_FORCE_REINSTALL=YES
      _PHP_FORCE_REINSTALL=YES
      _SSH_FORCE_REINSTALL=YES
      _SSL_FORCE_REINSTALL=YES
      _if_reinstall_curl_src
      _if_ssl_install_src
      _ssl_crypto_lib_fix
      _curl_install_src
      _sshd_install_src
      _nginx_install_upgrade
      _magick_install_upgrade
      _php_install_deps
      _php_libs_fix
      _php_if_versions_cleanup_cnf
       if [ -x "/opt/php56/bin/php" ]; then
        _PHP_VERSION="${_PHP56_VRN}"
        _install_php_multi "56"
      fi
      if [ -x "/opt/php70/bin/php" ]; then
        _PHP_VERSION="${_PHP70_VRN}"
        _install_php_multi "70"
      fi
      if [ -x "/opt/php71/bin/php" ]; then
        _PHP_VERSION="${_PHP71_VRN}"
        _install_php_multi "71"
      fi
      if [ -x "/opt/php72/bin/php" ]; then
        _PHP_VERSION="${_PHP72_VRN}"
        _install_php_multi "72"
      fi
      if [ -x "/opt/php73/bin/php" ]; then
        _PHP_VERSION="${_PHP73_VRN}"
        _install_php_multi "73"
      fi
      if [ -x "/opt/php74/bin/php" ]; then
        _PHP_VERSION="${_PHP74_VRN}"
        _install_php_multi "74"
      fi
      if [ -x "/opt/php80/bin/php" ]; then
        _PHP_VERSION="${_PHP80_VRN}"
        _install_php_multi "80"
      fi
      if [ -x "/opt/php81/bin/php" ]; then
        _PHP_VERSION="${_PHP81_VRN}"
        _install_php_multi "81"
      fi
      if [ -x "/opt/php82/bin/php" ]; then
        _PHP_VERSION="${_PHP82_VRN}"
        _install_php_multi "82"
      fi
      if [ -x "/opt/php83/bin/php" ]; then
        _PHP_VERSION="${_PHP83_VRN}"
        _install_php_multi "83"
      fi
      _PHP_VERSION=""
      _T_PHP_VRN=""
      _T_PHP_PTH=""
      _php_libs_fix
      if [ "${_STATUS}" = "UPGRADE" ]; then
        _php_ioncube_check_if_update
        _php_check_if_rebuild
      fi
      _php_install_upgrade
      _php_config_check_update
      _php_upgrade_all
      _if_install_php_newrelic
      _newrelic_check_fix
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
    _msg "INFO: The post_major_os_upgrade procedure is complete"
  fi
}

_if_major_os_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_major_os_upgrade"
  fi
  _RUNNING_MAJOR_OS_UPGRADE=NO
  _define_loc_osr
  if [ ! -z "${_MSG_LOC}" ]; then
    if [ ! -e "/usr/local/lib/icu/73.1" ] \
      && [ "${_LOC_OS_CODE}" != "jessie" ]; then
      echo
      _msg "OOPS: Please run normal 'barracuda up-${_tRee}' upgrade"
      _msg "OOPS: before trying to run major OS upgrade"
      echo
      _mrun "sleep 3"
      echo "Bye"
      _barracuda_cnf_cleanup
      _clean_pid_exit _if_major_os_upgrade_a
    fi
    if [ -e "/root/.run-to-daedalus.cnf" ] \
      || [ -e "/root/.run-to-chimaera.cnf" ] \
      || [ -e "/root/.run-to-beowulf.cnf" ]; then
      _AUTOPILOT=YES
    fi
    _RUNNING_MAJOR_OS_UPGRADE=YES
    _msg "MODE: ${_MSG_LOC} upgrade"
    echo
    _msg "RLLY: Have you created a Fresh Backup Snapshot of this VM?"
    echo
    _mrun "sleep 5"
    _msg "ATTN: You have to be prepared in case the upgrade will fail"
    _msg "ATTN: You have to be prepared for a crash of this system"
    _msg "ATTN: This procedure is well tested but things happen!"
    echo
    _mrun "sleep 5"
    _tPrmt="Are you sure you want to proceed?"
    _tPrmt=$(echo -n ${_tPrmt} | fmt -su -w 2500 2>&1)
    if _prompt_yes_no "${_tPrmt}?" ; then
      true
      echo
      _msg "FINE: But you can still hit ctrl-c to stop if you wish"
      _msg "WAIT: We need a minute to stop all running cron tasks..."
      _mrun "service cron stop" 2> /dev/null
    else
      echo
      _msg "FINE: Please try again later once you are ready"
      _mrun "sleep 3"
      _clean_pid_exit _if_major_os_upgrade_b
    fi
    echo
    _mrun "sleep 5"
    _msg "WAIT: This major system upgrade will start in 60s..."
    _mrun "sleep 15"
    _msg "WAIT: ...it will start in 45s..."
    _mrun "sleep 15"
    _msg "WAIT: ...it will start in 30s..."
    _mrun "sleep 15"
    _msg "WAIT: ...it will start in 15s..."
    _mrun "sleep 5"
    _msg "ATTN: Ten seconds left to hit ctrl-c to stop..."
    _mrun "sleep 10"
    _msg "INFO: ${_MSG_LOC} upgrade in progress..."
    echo
    _msg "HINT: Command to run in another terminal window to watch details"
    _msg "CMND: tail -f ${_LOG}"
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
    _check_dns_settings
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
    rm -f ${_pthLog}/ruby-sys-clean-reload.log
    mv -f /var/xdrago /var/xdrago_wait &> /dev/null
    rm -f ${_mtrNgx}/pre.d/nginx_speed_purge.conf
    if [ -e "/etc/init.d/bind" ]; then
      rm -f /etc/init.d/bind
    fi
    if [ -e "/etc/default/tomcat" ] && [ -e "/etc/init.d/tomcat" ]; then
      _mrun "service tomcat stop" 2> /dev/null
      mv /etc/init.d/tomcat /etc/init.d/offtomcat
      kill -9 $(ps aux | grep '[t]omcat' | awk '{print $2}') &> /dev/null
    fi
    _apt_clean_update_no_releaseinfo_change
#     _mrun "apt-get remove dbus -y --purge --auto-remove -qq" 2> /dev/null
#     if [ -e "/usr/share/dbus-1" ]; then
#       rm -f /usr/share/dbus-1/*/*freedesktop*
#     fi
    _mrun "apt-get remove collectd -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove libc-client2007b-dev -y --purge --auto-remove -qq" 2> /dev/null
    ###
    _mrun "apt-get remove --purge libmariadb3 -y -qq" 2> /dev/null
    _mrun "apt-get remove --purge mariadb-common -y -qq" 2> /dev/null
    _mrun "apt-get remove --purge mailutils -y -qq" 2> /dev/null
    ###
    ### Make sure that mariadb related packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/mariadb-common" ]; then
      echo -e 'Package: libmariadb3\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mariadb-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mailutils\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      _apt_clean_update_no_releaseinfo_change
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
      _apt_clean_update_no_releaseinfo_change
    fi
    ###
    _mrun "apt-get remove nginx-extras -y -qq" 2> /dev/null
    _mrun "apt-get remove nginx -y -qq" 2> /dev/null
    _mrun "apt-get remove nginx-common -y -qq" 2> /dev/null
    _mrun "apt-get remove nginx-full -y -qq" 2> /dev/null
    _mrun "apt-get remove percona-release -y -qq" 2> /dev/null
    ###
    ### Make sure that nginx packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/nginx-common" ]; then
      rm -f /etc/apt/preferences.d/nginx
      echo -e 'Package: nginx\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/nginx-common
      echo -e '\n\nPackage: nginx-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/nginx-common
      _apt_clean_update_no_releaseinfo_change
    fi
    ###
    _NGINX_GET_DPKG=$(dpkg --get-selections | grep nginx-common | grep 'hold$' 2>&1)
    if [[ ! "${_NGINX_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold nginx &> /dev/null
      aptitude hold nginx-common &> /dev/null
      echo "nginx hold" | dpkg --set-selections &> /dev/null
      echo "nginx-common hold" | dpkg --set-selections &> /dev/null
      _apt_clean_update_no_releaseinfo_change
    fi
    ###
    ### Make sure that percona-release package is locked in apt.
    if [ ! -e "/etc/apt/preferences.d/percona-release" ]; then
      echo -e 'Package: percona-release\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/percona-release
      _apt_clean_update
    fi
    ###
    _PERC_GET_DPKG=$(dpkg --get-selections | grep percona-release | grep 'hold$' 2>&1)
    if [[ ! "${_PERC_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold percona-release &> /dev/null
      echo "percona-release hold" | dpkg --set-selections &> /dev/null
      _apt_clean_update
    fi
    ###
    if [ -e "/etc/php5/conf.d" ]; then
      touch /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      touch /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    _mrun "apt-get remove php5 \
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
    _mrun "apt-get remove phpunit       -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove php-pear      -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove php-benchmark -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove php5-cli      -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove php5-common   -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove php5-apc      -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove php-apc       -y --purge --auto-remove -qq" 2> /dev/null
    if [ "${_LOC_OS_CODE}" = "jessie" ]; then
      _mrun "apt-get remove gnome-tweak-tool -y --purge --auto-remove -qq" 2> /dev/null
    fi
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      _mrun "apt-get remove libpam-systemd -y --purge --auto-remove -qq" 2> /dev/null
    fi
    echo "curl install"                | dpkg --set-selections &> /dev/null
    echo "git install"                 | dpkg --set-selections &> /dev/null
    echo "git-core install"            | dpkg --set-selections &> /dev/null
    echo "git-man install"             | dpkg --set-selections &> /dev/null
    echo "libldap-common install"      | dpkg --set-selections &> /dev/null
    echo "libldap-dev install"         | dpkg --set-selections &> /dev/null
    echo "libldap2-dev install"        | dpkg --set-selections &> /dev/null
    echo "libmariadb3 install"         | dpkg --set-selections &> /dev/null
    echo "libssl-dev install"          | dpkg --set-selections &> /dev/null
    echo "mailutils install"           | dpkg --set-selections &> /dev/null
    echo "mariadb-common install"      | dpkg --set-selections &> /dev/null
    echo "nginx install"               | dpkg --set-selections &> /dev/null
    echo "nginx-common install"        | dpkg --set-selections &> /dev/null
    echo "openssh-client install"      | dpkg --set-selections &> /dev/null
    echo "openssh-server install"      | dpkg --set-selections &> /dev/null
    echo "openssh-sftp-server install" | dpkg --set-selections &> /dev/null
    echo "openssl install"             | dpkg --set-selections &> /dev/null
    echo "percona-release install"     | dpkg --set-selections &> /dev/null
    echo "ssh install"                 | dpkg --set-selections &> /dev/null
    echo "sysvinit-core install"       | dpkg --set-selections &> /dev/null
    echo "sysvinit-utils install"      | dpkg --set-selections &> /dev/null
    echo "zlib1g install"              | dpkg --set-selections &> /dev/null
    echo "zlib1g-dev install"          | dpkg --set-selections &> /dev/null
    echo "zlibc install"               | dpkg --set-selections &> /dev/null
    ###
    ### Run pre-migration upgrade in the current OS version.
    _mrun "apt-get upgrade ${_nrmUpArg}" 2> /dev/null
    ###
    ### Check if we can continue.
    _AUDIT_DPKG=$(dpkg --audit 2>&1)
    if [ ! -z "${_AUDIT_DPKG}" ]; then
      _msg "ALRT! I can not continue until dpkg --audit is clean"
      _msg "ALRT! ${_AUDIT_DPKG}"
      _msg "ALRT! Aborting installer NOW!"
      _clean_pid_exit _if_major_os_upgrade_c
    fi
    _HOLD_TEST_DPKG=$(dpkg --get-selections | grep 'hold$' 2>&1)
    if [ ! -z "${_HOLD_TEST_DPKG}" ]; then
      _msg "ALRT! I can not continue until these packages are un-hold"
      _msg "ALRT! ${_HOLD_TEST_DPKG}"
      _msg "ALRT! Aborting installer NOW!"
      _clean_pid_exit _if_major_os_upgrade_d
    fi
    _HOLD_TEST_ATE=$(aptitude search "~ahold" 2>&1)
    if [ ! -z "${_HOLD_TEST_ATE}" ]; then
      _msg "ALRT! I can not continue until these packages are un-hold"
      _msg "ALRT! ${_HOLD_TEST_ATE}"
      _msg "ALRT! Aborting installer NOW!"
      _clean_pid_exit _if_major_os_upgrade_e
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
    _if_sql_keyring_apt_update
    ###
    ### Switching system gears on the fly.
    if [ "${_TGT_OSN}" = "Devuan" ]; then
      _TGT_MRR="deb.devuan.org/merged"
      echo "## DEVUAN MAIN REPOSITORIES" > ${_aptLiSys}
      echo "deb http://${_TGT_MRR} ${_NEW_OS_CODE} main" >> ${_aptLiSys}
      echo "deb-src http://${_TGT_MRR} ${_NEW_OS_CODE} main" >> ${_aptLiSys}
      echo "" >> ${_aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${_aptLiSys}
      echo "deb http://${_TGT_MRR} ${_NEW_OS_CODE}-updates main" >> ${_aptLiSys}
      echo "deb-src http://${_TGT_MRR} ${_NEW_OS_CODE}-updates main" >> ${_aptLiSys}
      echo "" >> ${_aptLiSys}
      echo "## DEVUAN SECURITY UPDATES" >> ${_aptLiSys}
      echo "deb http://${_TGT_MRR} ${_NEW_OS_CODE}-security main" >> ${_aptLiSys}
      echo "deb-src http://${_TGT_MRR} ${_NEW_OS_CODE}-security main" >> ${_aptLiSys}
      if [ -e "/etc/apt/apt.conf" ]; then
        rm -f /etc/apt/apt.conf
      fi
      ###
      ### Add devuan-keyring first.
      _apt_clean_update_no_releaseinfo_change
      _mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null
      _mrun "${_INITINS} devuan-keyring" 2> /dev/null
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
      echo "## DEBIAN MAIN REPOSITORIES" > ${_aptLiSys}
      echo "deb http://${_NEW_APT_MIRROR} ${_NEW_OS_CODE} main contrib non-free" >> ${_aptLiSys}
      echo "deb-src http://${_NEW_APT_MIRROR} ${_NEW_OS_CODE} main contrib non-free" >> ${_aptLiSys}
      echo "" >> ${_aptLiSys}
      echo "## MAJOR BUG FIX UPDATES produced after the final release" >> ${_aptLiSys}
      echo "deb http://${_NEW_APT_MIRROR} ${_NEW_APT_REPSRC} main contrib non-free" >> ${_aptLiSys}
      echo "deb-src http://${_NEW_APT_MIRROR} ${_NEW_APT_REPSRC} main contrib non-free" >> ${_aptLiSys}
      echo "" >> ${_aptLiSys}
      echo "## DEBIAN SECURITY UPDATES" >> ${_aptLiSys}
      echo "deb http://${_NEW_SEC_MIRROR} ${_NEW_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${_aptLiSys}
      echo "deb-src http://${_NEW_SEC_MIRROR} ${_NEW_SEC_REPSRC} main contrib non-free" | fmt -su -w 2500 >> ${_aptLiSys}
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
    _apt_clean_update_no_releaseinfo_change
    _mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null
    ###
    ### Two step upgrade with apt-get only.
    _mrun "apt-get install apt -t ${_NEW_OS_CODE} ${_dstUpArg}" 2> /dev/null
    _apt_clean_update_no_releaseinfo_change
    _mrun "${_APT_UPDATE} --allow-insecure-repositories -qq" 2> /dev/null
    ###
    ### Requirement for Debian Stretch to Devuan Beowulf migration.
    ### The libtinfo package needs to be upgraded to prevent breaks.
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      _mrun "apt-get install libtinfo6 ${_dstUpArg}" 2> /dev/null
    fi
    ###
    ### Note that this upgrade does not complete the migration yet.
    _mrun "apt-get upgrade ${_dstUpArg}" 2> /dev/null
    _mrun "apt-get install apt dpkg aptitude util-linux ${_dstUpArg}" 2> /dev/null
    ###
    ### Back to BOA stuff re-install as needed.
    if [ -e "/etc/init.d/bind9" ] && [ ! -e "/etc/init.d/bind" ]; then
      ln -sfn /etc/init.d/bind9 /etc/init.d/bind
    fi
    if [ -e "${_mtrInc}/nginx_vhost_common.conf" ]; then
      if [ -e "/root/.debug.cnf" ]; then
        mv -f /etc/init.d/networking /etc/init.d/networking.bak
        cp -af /etc/init.d/networking.dpkg-dist /etc/init.d/networking
        chmod 755 /etc/init.d/networking
        ls -la /etc/init.d/networking
      fi
    fi
    if [ -d "/var/www/cgp" ]; then
      _mrun "apt-get install collectd ${_dstUpArg}" 2> /dev/null
    fi
    _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
    _mrun "apt-get install libc-client2007e-dev ${_dstUpArg}" 2> /dev/null
    ###
    ### Make sure that org.freedesktop.systemd1 was not atempted by dbus.
#     _mrun "apt-get remove dbus -y --purge --auto-remove -qq" 2> /dev/null
#     if [ -e "/usr/share/dbus-1" ]; then
#       rm -f /usr/share/dbus-1/*/*freedesktop*
#     fi
    ###
    ### Fix any broken packages.
    _apt_clean_update_no_releaseinfo_change
    _mrun "apt-get --fix-broken install -y" 2> /dev/null
    ###
    ### Make sure that sysvinit-core is still installed and systemd removed.
    _sysvinit_install
    _systemd_remove_apt_cmd
    _sysvinit_install
    ###
    ### Prepare for the last step.
    if [ "${_TGT_OSN}" = "Devuan" ]; then
      ###
      ### The last step before migration to Devuan is to switch to eudev.
      ### Jessie exception needs testing, though.
      if [ "${_LOC_OS_CODE}" != "jessie" ]; then
        _mrun "apt-get install eudev ${_dstUpArg}" 2> /dev/null
      fi
    fi
    ###
    ### Upgrade all packages so that you have the latest versions.
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      _mrun "apt-get upgrade ${_dstUpArg}" 2> /dev/null
      #_mrun "apt-get full-upgrade ${_dstUpArg}" 2> /dev/null
      _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
    else
      _mrun "apt-get upgrade ${_dstUpArg}" 2> /dev/null
      _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
    fi
    ###
    ### Force install/upgrade to give it another chance to complete.
    _mrun "apt-get ${_dstUpArg} install" 2> /dev/null
    ###
    ### Upgrade again all packages so that you have the latest versions.
    if [ "${_LOC_OS_CODE}" = "stretch" ]; then
      _mrun "apt-get upgrade ${_dstUpArg}" 2> /dev/null
      #_mrun "apt-get full-upgrade ${_dstUpArg}" 2> /dev/null
      _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
    else
      _mrun "apt-get upgrade ${_dstUpArg}" 2> /dev/null
      _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
    fi
    _mrun "apt-get upgrade -y" 2> /dev/null
    ###
    ### Make sure that sysvinit-core is still installed and systemd removed.
    _sysvinit_install
    _systemd_remove_apt_cmd
    _sysvinit_install
    ###
    ### Finally, the proper dist-upgrade time.
    ### Note that Debian to Devuan migration always requires
    ### the key dist-upgrade step to be run AFTER reboot!
    _FORCE_REBUILD_SRC_ON_AUTO_NOW=NO
    if [ "${_LOC_OS_CODE}" = "bookworm" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      _msg "ATTN: NOTE! Debian Bookworm to Devuan migration"
      _msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      _msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "bullseye" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      _msg "ATTN: NOTE! Debian Bullseye to Devuan migration"
      _msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      _msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "buster" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      _msg "ATTN: NOTE! Debian Buster to Devuan migration"
      _msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      _msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "stretch" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      _msg "ATTN: NOTE! Debian Stretch to Devuan migration"
      _msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      _msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    elif [ "${_LOC_OS_CODE}" = "jessie" ] && [ "${_TGT_OSN}" = "Devuan" ]; then
      echo
      _msg "ATTN: NOTE! Debian Jessie to Devuan migration"
      _msg "ATTN: requires the key dist-upgrade step AFTER reboot, so"
      _msg "ATTN: you MUST RUN ANOTHER Barracuda upgrade after reboot"
    else
      echo
      _mrun "apt-get dist-upgrade ${_dstUpArg} --allow-downgrades" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
      _mrun "apt-get dist-upgrade -y --allow-downgrades" 2> /dev/null
      [ -e "/var/lib/man-db/auto-update" ] && rm -f /var/lib/man-db/auto-update
      _mrun "apt-get install lsb-release ${_dstUpArg}" 2> /dev/null
      ###
      if [ "${_LOC_OS_CODE}" = "chimaera" ] \
        && [ "${_NEW_OS_CODE}" = "daedalus" ]; then
        ###
        ### Fix PHP early
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DIST: Special procedure for ${_LOC_OS_CODE} to ${_NEW_OS_CODE} upgrade"
        fi
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "TRCK: Removing libldap packages for a clean start"
        fi
        _mrun "apt-get remove libldap-common -y -qq" 2> /dev/null
        _mrun "apt-get remove libldap2-dev -y -qq" 2> /dev/null
        _mrun "apt-get remove libldap-dev -y -qq" 2> /dev/null
        _apt_clean_update
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "TRCK: Installing now libldap packages from Chimaera"
        fi
        echo "## DEVUAN MAIN REPOSITORIES" > /etc/apt/sources.list.d/chimaera.list
        echo "deb http://deb.devuan.org/merged chimaera main" >> /etc/apt/sources.list.d/chimaera.list
        echo "deb-src http://deb.devuan.org/merged chimaera main" >> /etc/apt/sources.list.d/chimaera.list
        echo "" >> /etc/apt/sources.list.d/chimaera.list
        echo "## MAJOR BUG FIX UPDATES produced after the final release" >> /etc/apt/sources.list.d/chimaera.list
        echo "deb http://deb.devuan.org/merged chimaera-updates main" >> /etc/apt/sources.list.d/chimaera.list
        echo "deb-src http://deb.devuan.org/merged chimaera-updates main" >> /etc/apt/sources.list.d/chimaera.list
        echo "" >> /etc/apt/sources.list.d/chimaera.list
        echo "## DEVUAN SECURITY UPDATES" >> /etc/apt/sources.list.d/chimaera.list
        echo "deb http://deb.devuan.org/merged chimaera-security main" >> /etc/apt/sources.list.d/chimaera.list
        echo "deb-src http://deb.devuan.org/merged chimaera-security main" >> /etc/apt/sources.list.d/chimaera.list
        echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
        _apt_clean_update
        _mrun "apt-get install -t chimaera libldap-common -y" 2> /dev/null
        _mrun "apt-get install -t chimaera libldap2-dev -y" 2> /dev/null
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "TRCK: Locking libldap packages to prevent upgrade on Daedalus"
        fi
        ### Make sure that libldap packages are locked in apt.
        echo -e 'Package: libldap-common\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/libldap
        echo -e '\n\nPackage: libldap2-dev\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/libldap
        echo -e '\n\nPackage: libldap-dev\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/libldap
        _apt_clean_update
        ###
        _LDAP_GET_DPKG=$(dpkg --get-selections | grep libldap-common | grep 'hold$' 2>&1)
        if [[ ! "${_LDAP_GET_DPKG}" =~ "hold" ]]; then
          aptitude hold libldap-common &> /dev/null
          aptitude hold libldap2-dev &> /dev/null
          aptitude hold libldap-dev &> /dev/null
          echo "libldap-common hold" | dpkg --set-selections &> /dev/null
          echo "libldap2-dev hold" | dpkg --set-selections &> /dev/null
          echo "libldap-dev hold" | dpkg --set-selections &> /dev/null
          _apt_clean_update
        fi
        rm -f /etc/apt/sources.list.d/chimaera.list
        rm -f /etc/apt/apt.conf
        _apt_clean_update
        ldconfig 2> /dev/null
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DIST: Signal that --allow-downgrades can be used after reboot"
        fi
        touch /root/.allow.downgrades.on.same.os.dist.upgrade.cnf
        ###
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DIST: Rebuidling key services from sources before reboot..."
        fi
        _FORCE_REBUILD_SRC_ON_AUTO_NOW=YES
        touch /root/.force.rebuild.src.on.auto.now.cnf
        _if_rebuild_src_on_major_os_upgrade
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DIST: No quick rebuild from src on ${_LOC_OS_CODE} to ${_NEW_OS_CODE} upgrade"
        fi
      fi
      ###
    fi
    ### Make sure that sysvinit-core is still installed and systemd removed.
    _sysvinit_install
    _systemd_remove_apt_cmd
    _sysvinit_install
    ### Update rsyslog configuration early
    _rsyslog_config_update
    ### Reload key services if needed early
    _mrun "service redis-server reload" 2> /dev/null
    _mrun "service nginx reload" 2> /dev/null
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
        _mrun "service php${e}-fpm reload" 2> /dev/null
      fi
    done
    if [ ! -e "/var/xdrago/log" ] && [ -e "/var/xdrago_wait/log" ]; then
      perl /var/xdrago_wait/proc_num_ctrl.pl &
    else
      perl /var/xdrago/proc_num_ctrl.pl &
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
      _php_libs_fix
      _if_reinstall_curl_src
      _if_ssl_install_src
      _ssl_crypto_lib_fix
      _curl_install_src
      _sshd_install_src
      _nginx_install_upgrade
      _magick_install_upgrade
      _php_install_deps
      _php_libs_fix
      _php_if_versions_cleanup_cnf
      if [ "${_STATUS}" = "UPGRADE" ]; then
        _php_ioncube_check_if_update
        _php_check_if_rebuild
      fi
      _php_install_upgrade
      _php_config_check_update
      _php_upgrade_all
      _if_install_php_newrelic
      _newrelic_check_fix
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
    #   _db_server_install
    #   _myquick_install_upgrade
    #   _php_install_deps
    #   _php_libs_fix
    #   _php_install_upgrade
    #   _php_config_check_update
    #   _php_upgrade_all
    #   _if_install_php_newrelic
    #   _newrelic_check_fix
    #   _php_ioncube_check_if_update
    #   _php_check_if_rebuild
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
      for _link in ${_REMOVE_LINKS}; do
        if [ -e "/etc/init.d/${_link}" ]; then
          _mrun "update-rc.d -f ${_link} remove" 2> /dev/null
          mv -f /etc/init.d/${_link} /var/backups/init.d.${_link}
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
        _msg "WARN: Required /dev/pts/ptmx does not exist! We will fix this now..."
        mkdir -p /dev/pts
        rm -rf /dev/pts/*
        _apt_clean_update_no_releaseinfo_change
        _mrun "apt-get install udev -y --allow-unauthenticated" 2> /dev/null
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
    _SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership lock-local-drush-permissions)
    for _SCRIPT in ${_SCRIPTS[@]}; do
      _VAR_IF_PRESENT=$(grep "aegir ALL=NOPASSWD: /usr/local/bin/${_SCRIPT}.sh" /etc/sudoers.d/${_SCRIPT} 2>&1)
      if [[ ! "${_VAR_IF_PRESENT}" =~ "aegir ALL=NOPASSWD" ]]; then
        echo "aegir ALL=NOPASSWD: /usr/local/bin/${_SCRIPT}.sh" >> /etc/sudoers.d/${_SCRIPT}
        chmod 0440 /etc/sudoers.d/${_SCRIPT}
      fi
    done
    ###
    ### Make sure that Aegir Octopus system users are added to sudo.
    if [ -d "/data/u" ]; then
      for _usEr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
        if [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] \
          && [ ! -e "${_usEr}/log/proxied.pid" ] \
          && [ ! -e "${_usEr}/log/CANCELLED" ]; then
          _HM_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
          _VAR_IF_PRESENT=$(grep "${_HM_U} ALL=NOPASSWD" /etc/sudoers 2>&1)
          if [[ ! "${_VAR_IF_PRESENT}" =~ "${_HM_U} ALL=NOPASSWD" ]]; then
            echo "${_HM_U} ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
          fi
          _SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership lock-local-drush-permissions)
          for _SCRIPT in ${_SCRIPTS[@]}; do
            _VAR_IF_PRESENT=$(grep "${_HM_U} ALL=NOPASSWD: /usr/local/bin/${_SCRIPT}.sh" /etc/sudoers.d/${_SCRIPT} 2>&1)
            if [[ ! "${_VAR_IF_PRESENT}" =~ "${_HM_U} ALL=NOPASSWD" ]]; then
              echo "${_HM_U} ALL=NOPASSWD: /usr/local/bin/${_SCRIPT}.sh" >> /etc/sudoers.d/${_SCRIPT}
              chmod 0440 /etc/sudoers.d/${_SCRIPT}
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
    ### Add ctrl file to trigger _if_post_major_os_upgrade() after reboot.
    touch /root/.run_post_major_os_upgrade.info
    echo " "
    _msg "RLLY: No errors? ${_MSG_LOC} migration worked :)"
    _msg "STEP: Please reboot this server now"
    _msg "STEP: Once the system is up, run 'barracuda up-${_tRee}' command again"
    echo " "
    _msg "Bye"
    touch /root/.latest-barracuda-upgrade-finale.info
    _barracuda_cnf_cleanup
    _clean_pid_exit _if_major_os_upgrade_f
  fi
}

_webmin_apt_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _webmin_apt_update"
  fi
  if [ -d "/etc/webmin" ]; then
    if [ ! -e "${_pthLog}/webmin_update_apt_src.log" ]; then
      cd /var/opt
      echo "## Webmin APT Repository" > /etc/apt/sources.list.d/webmin.list
      echo "deb http://download.webmin.com/download/repository \
        sarge contrib" | fmt -su -w 2500 >> /etc/apt/sources.list.d/webmin.list
      echo "deb http://webmin.mirror.somersettechsolutions.co.uk/repository \
        sarge contrib" | fmt -su -w 2500 >> /etc/apt/sources.list.d/webmin.list
      _KEYS_SERVER_TEST=FALSE
      until [[ "${_KEYS_SERVER_TEST}" =~ "GnuPG" ]]; do
        rm -f jcameron-key.gpg*
        wget -q -U iCab ${_urlDev}/jcameron-key.gpg
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
      touch ${_pthLog}/webmin_update_apt_src.log
    fi
  fi
}

_early_sys_ctrl_mark() {
  if [ -e "/root/.run_post_major_os_upgrade.info" ]; then
    touch /root/.early-sys-ctrl-mark.cnf
  else
    [ -e "/root/.early-sys-ctrl-mark.cnf" ] && rm -f /root/.early-sys-ctrl-mark.cnf
  fi
}

_normal_sys_ctrl_mark() {
  if [ -e "/root/.latest-barracuda-upgrade-finale.info" ]; then
    rm -f /root/.latest-barracuda-upgrade-finale.info
    touch /root/.normal-sys-ctrl-mark.cnf
  else
    [ -e "/root/.normal-sys-ctrl-mark.cnf" ] && rm -f /root/.normal-sys-ctrl-mark.cnf
  fi
}

_sys_packages_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sys_packages_update"
  fi
  _msg "INFO: Running system packages update..."
  if [ -e "/var/aegir" ]; then
    echo "curl install"                | dpkg --set-selections &> /dev/null
    echo "git install"                 | dpkg --set-selections &> /dev/null
    echo "git-core install"            | dpkg --set-selections &> /dev/null
    echo "git-man install"             | dpkg --set-selections &> /dev/null
    echo "libldap-common install"      | dpkg --set-selections &> /dev/null
    echo "libldap-dev install"         | dpkg --set-selections &> /dev/null
    echo "libldap2-dev install"        | dpkg --set-selections &> /dev/null
    echo "libmariadb3 install"         | dpkg --set-selections &> /dev/null
    echo "libssl-dev install"          | dpkg --set-selections &> /dev/null
    echo "mailutils install"           | dpkg --set-selections &> /dev/null
    echo "mariadb-common install"      | dpkg --set-selections &> /dev/null
    echo "nginx install"               | dpkg --set-selections &> /dev/null
    echo "nginx-common install"        | dpkg --set-selections &> /dev/null
    echo "openssh-client install"      | dpkg --set-selections &> /dev/null
    echo "openssh-server install"      | dpkg --set-selections &> /dev/null
    echo "openssh-sftp-server install" | dpkg --set-selections &> /dev/null
    echo "openssl install"             | dpkg --set-selections &> /dev/null
    echo "percona-release install"     | dpkg --set-selections &> /dev/null
    echo "ssh install"                 | dpkg --set-selections &> /dev/null
    echo "sysvinit-core install"       | dpkg --set-selections &> /dev/null
    echo "sysvinit-utils install"      | dpkg --set-selections &> /dev/null
    echo "zlib1g install"              | dpkg --set-selections &> /dev/null
    echo "zlib1g-dev install"          | dpkg --set-selections &> /dev/null
    echo "zlibc install"               | dpkg --set-selections &> /dev/null
  fi
  _webmin_apt_update
  _apt_clean_update
  if [ -e "/var/aegir/drush" ]; then
    _DPKG_CNF="confold"
  else
    _DPKG_CNF="confnew"
  fi
  _st_runner "aptitude full-upgrade -f -y -q \
    --allow-untrusted \
    -o Dpkg::Options::=--force-confmiss \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-${_DPKG_CNF}" &> /dev/null
  if [ "${_STATUS}" = "INIT" ]; then
    _apt_clean_update
    _st_runner "aptitude full-upgrade -f -y -q \
      --allow-untrusted \
      -o Dpkg::Options::=--force-confmiss \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-${_DPKG_CNF}" &> /dev/null
    _st_runner "apt-get autoclean -y" &> /dev/null
  else
    echo "gnupg-curl install" | dpkg --set-selections &> /dev/null
    if [ -e "/etc/php5/conf.d" ]; then
      touch /etc/php5/conf.d/{opcache.ini,apc.ini,imagick.ini,memcached.ini}
      touch /etc/php5/conf.d/{redis.ini,suhosin.ini,newrelic.ini}
    fi
    _mrun "${_RMAPP} php5 \
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
    _mrun "${_RMAPP} phpunit php-pear php-benchmark" 2> /dev/null
    _mrun "${_RMAPP} php5-cli php5-common" 2> /dev/null
    _mrun "${_RMAPP} php5-apc" 2> /dev/null
    _mrun "${_RMAPP} php-apc" 2> /dev/null
    _mrun "${_RMAPP} apache2.2-common" 2> /dev/null
    _mrun "${_RMAPP} apache2.2-bin" 2> /dev/null
    _mrun "aptitude install lsof -y --allow-untrusted" 2> /dev/null
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
    _check_apt_updates
  fi
}

_sys_packages_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sys_packages_install"
  fi
  _if_to_do_fix
  if [ "${_STATUS}" = "INIT" ]; then
    _msg "INFO: Installing required libraries and tools..."
  else
    _msg "INFO: Upgrading required libraries and tools..."
    if [ ! -e "/etc/init.d/php5-fpm" ]; then
      cp -af ${_locCnf}/php/php5-fpm-init-vanilla /etc/init.d/php5-fpm
    fi
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _if_hosted_sys
    if [[ "${_XTRAS_LIST}" =~ "SR" ]] \
      || [ "${_hostedSys}" = "YES" ]; then
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
        _apt_clean_update
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "TRCK: Installing now openjdk-11-jre-headless from Bullseye"
        fi
        _mrun "apt-get install -t bullseye openjdk-11-jre-headless -y" 2> /dev/null
        rm -f /etc/apt/sources.list.d/bullseye.list
        rm -f /etc/apt/apt.conf
        _apt_clean_update
      elif [ "${_OS_CODE}" = "beowulf" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "chimaera" ]; then
        _APT_XTRA="openjdk-11-jre-headless openjdk-17-jre-headless ca-certificates-java nginx"
      elif [ "${_OS_CODE}" = "daedalus" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java nginx"
        if [ ! -x "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" ]; then
          echo "## DEVUAN MAIN REPOSITORIES" > /etc/apt/sources.list.d/chimaera.list
          echo "deb http://deb.devuan.org/merged chimaera main" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb-src http://deb.devuan.org/merged chimaera main" >> /etc/apt/sources.list.d/chimaera.list
          echo "" >> /etc/apt/sources.list.d/chimaera.list
          echo "## MAJOR BUG FIX UPDATES produced after the final release" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb http://deb.devuan.org/merged chimaera-updates main" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb-src http://deb.devuan.org/merged chimaera-updates main" >> /etc/apt/sources.list.d/chimaera.list
          echo "" >> /etc/apt/sources.list.d/chimaera.list
          echo "## DEVUAN SECURITY UPDATES" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb http://deb.devuan.org/merged chimaera-security main" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb-src http://deb.devuan.org/merged chimaera-security main" >> /etc/apt/sources.list.d/chimaera.list
          echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
          _apt_clean_update
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "TRCK: Installing now openjdk-11-jre-headless from Chimaera"
          fi
          _mrun "apt-get install -t chimaera openjdk-11-jre-headless -y" 2> /dev/null
          rm -f /etc/apt/sources.list.d/chimaera.list
          rm -f /etc/apt/apt.conf
          _apt_clean_update
        fi
      fi
    else
      _APT_XTRA="nginx"
    fi
    _APT_ELSE="netcat nginx"
  else
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-6-jdk | grep install 2>&1)
    if [[ "${_APT_ITEM}" =~ "install" ]]; then
      _mrun "apt-get remove openjdk-6-jdk -y --purge --auto-remove -qq" 2> /dev/null
    fi
    _APT_ITEM=$(dpkg --get-selections | grep openjdk-7-jdk | grep install 2>&1)
    if [[ "${_APT_ITEM}" =~ "install" ]]; then
      _mrun "apt-get remove openjdk-7-jdk -y --purge --auto-remove -qq" 2> /dev/null
    fi
    _if_hosted_sys
    if [[ "${_XTRAS_LIST}" =~ "SR" ]] \
      || [ "${_hostedSys}" = "YES" ]; then
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
        _apt_clean_update
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "TRCK: Installing now openjdk-11-jre-headless from Bullseye"
        fi
        _mrun "apt-get install -t bullseye openjdk-11-jre-headless -y" 2> /dev/null
        rm -f /etc/apt/sources.list.d/bullseye.list
        rm -f /etc/apt/apt.conf
        _apt_clean_update
      elif [ "${_OS_CODE}" = "beowulf" ]; then
        _APT_XTRA="openjdk-11-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "chimaera" ]; then
        _APT_XTRA="openjdk-11-jre-headless openjdk-17-jre-headless ca-certificates-java"
      elif [ "${_OS_CODE}" = "daedalus" ]; then
        _APT_XTRA="openjdk-17-jre-headless ca-certificates-java"
        if [ -x "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" ]; then
          _JAVA_TEST=$(/usr/lib/jvm/java-11-openjdk-amd64/bin/java --version 2>&1)
        fi
        if [ ! -x "/usr/lib/jvm/java-11-openjdk-amd64/bin/java" ] || [[ ! "${_JAVA_TEST}" =~ "openjdk 11.0.24" ]]; then
          echo "## DEVUAN MAIN REPOSITORIES" > /etc/apt/sources.list.d/chimaera.list
          echo "deb http://deb.devuan.org/merged chimaera main" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb-src http://deb.devuan.org/merged chimaera main" >> /etc/apt/sources.list.d/chimaera.list
          echo "" >> /etc/apt/sources.list.d/chimaera.list
          echo "## MAJOR BUG FIX UPDATES produced after the final release" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb http://deb.devuan.org/merged chimaera-updates main" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb-src http://deb.devuan.org/merged chimaera-updates main" >> /etc/apt/sources.list.d/chimaera.list
          echo "" >> /etc/apt/sources.list.d/chimaera.list
          echo "## DEVUAN SECURITY UPDATES" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb http://deb.devuan.org/merged chimaera-security main" >> /etc/apt/sources.list.d/chimaera.list
          echo "deb-src http://deb.devuan.org/merged chimaera-security main" >> /etc/apt/sources.list.d/chimaera.list
          echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
          _apt_clean_update
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "TRCK: Installing now openjdk-11-jre-headless from Chimaera"
          fi
          _mrun "apt-get install -t chimaera openjdk-11-jre-headless -y" 2> /dev/null
          rm -f /etc/apt/sources.list.d/chimaera.list
          rm -f /etc/apt/apt.conf
          _apt_clean_update
        fi
      fi
    else
      _APT_XTRA=""
    fi
    _APT_ELSE="netcat netcat-traditional"
    _apt_clean_update
    _mrun "service nginx start" 2> /dev/null
    _mrun "apt-get remove nginx-extras -y -qq" 2> /dev/null
    _mrun "apt-get remove nginx -y -qq" 2> /dev/null
    _mrun "apt-get remove nginx-common -y -qq" 2> /dev/null
    _mrun "apt-get remove nginx-full -y -qq" 2> /dev/null
    _mrun "apt-get remove redis-server -y -qq" 2> /dev/null
    _mrun "apt-get remove percona-release -y -qq" 2> /dev/null
    ###
    ### Make sure that nginx packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/nginx-common" ]; then
      rm -f /etc/apt/preferences.d/nginx
      echo -e 'Package: nginx\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/nginx-common
      echo -e '\n\nPackage: nginx-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/nginx-common
      _apt_clean_update
    fi
    ###
    _NGINX_GET_DPKG=$(dpkg --get-selections | grep nginx-common | grep 'hold$' 2>&1)
    if [[ ! "${_NGINX_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold nginx &> /dev/null
      aptitude hold nginx-common &> /dev/null
      echo "nginx hold" | dpkg --set-selections &> /dev/null
      echo "nginx-common hold" | dpkg --set-selections &> /dev/null
      _apt_clean_update
    fi
    ###
    ### Make sure that percona-release package is locked in apt.
    if [ ! -e "/etc/apt/preferences.d/percona-release" ]; then
      echo -e 'Package: percona-release\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/percona-release
      _apt_clean_update
    fi
    ###
    _PERC_GET_DPKG=$(dpkg --get-selections | grep percona-release | grep 'hold$' 2>&1)
    if [[ ! "${_PERC_GET_DPKG}" =~ "hold" ]]; then
      aptitude hold percona-release &> /dev/null
      echo "percona-release hold" | dpkg --set-selections &> /dev/null
      _apt_clean_update
    fi
    ###
    _mrun "apt-get remove --purge libmariadb3 -y -qq" 2> /dev/null
    _mrun "apt-get remove --purge mariadb-common -y -qq" 2> /dev/null
    _mrun "apt-get remove --purge mailutils -y -qq" 2> /dev/null
    ###
    ### Make sure that mariadb related packages are locked in apt.
    if [ ! -e "/etc/apt/preferences.d/mariadb-common" ]; then
      echo -e 'Package: libmariadb3\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mariadb-common\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      echo -e '\n\nPackage: mailutils\nPin: release *\nPin-Priority: -1' >> /etc/apt/preferences.d/mariadb-common
      _apt_clean_update_no_releaseinfo_change
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
      _apt_clean_update_no_releaseinfo_change
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
    _mrun "apt-get remove sysklogd -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "apt-get remove rsyslog -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "killall -9 sysklogd" 2> /dev/null
    _mrun "killall -9 rsyslogd" 2> /dev/null
  elif [ -e "/root/.use.sysklogd.cnf" ]; then
    _SYSLOGD=sysklogd
    _mrun "apt-get remove rsyslog -y --purge --auto-remove -qq" 2> /dev/null
    _mrun "killall -9 rsyslogd" 2> /dev/null
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

  _if_hosted_sys
  if [[ "${_XTRAS_LIST}" =~ "IMG" ]] \
    || [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [ "${_hostedSys}" = "YES" ]; then
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

_php_libs_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _php_libs_fix"
  fi
  _if_to_do_fix
  _LIB_NOW=$(date +%y%m%d-%H%M 2>&1)
  _LIB_NOW=${_LIB_NOW//[^0-9-]/}
  if [ ! -L "/usr/lib/librtmp.so" ] \
    || [ ! -e "/usr/lib/libwebpmux.so" ] \
    || [ ! -e "/usr/lib/libonig.so" ] \
    || [ ! -e "/usr/lib/libicuio.so" ] \
    || [ ! -e "/usr/lib/liblber.so" ] \
    || [ ! -e "/var/xdrago/log/._php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid" ] \
    || [ ! -e "/usr/include/gmp.h" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Fix for PHP libs in ${_OS_DIST}/${_OS_CODE}"
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
      touch /var/xdrago_wait/log/._php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
      touch /var/xdrago_wait/log/._php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
    else
      touch /var/xdrago/log/._php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
      touch /var/xdrago/log/._php_libs_fix_${_OS_CODE}_${_LIB_NOW}.pid
    fi
  fi
  ldconfig 2> /dev/null
}

_smtp_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _smtp_check"
  fi
  if [ -z "${_SMTP_RELAY_HOST}" ] && [ "${_SMTP_RELAY_TEST}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Checking SMTP connections..."
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

_if_install_vnstat() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_vnstat"
  fi
  if [ ! -e "/run/cloud_vhost.pid" ]; then
    if [ ! -e "${_pthLog}/vnstat-${_VNSTAT_VRN}.log" ] \
      || [ ! -e "/usr/bin/vnstat" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installing VnStat monitor..."
      fi
      cd /var/opt
      rm -rf vnstat*
      _get_dev_src "vnstat-${_VNSTAT_VRN}.tar.gz"
      cd vnstat-${_VNSTAT_VRN}
      _mrun "bash ./configure --prefix=/usr --sysconfdir=/etc" 2> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      ldconfig 2> /dev/null
      for INF in `vnstat --iflist \
        | sed "s/Available interfaces//g; s/(1000 Mbit)//g; s/(100 Mbit)//g; s/ lo//g;" \
        | cut -d: -f2` ;do vnstat -i $INF &> /dev/null;done
      cp -af /var/opt/vnstat-${_VNSTAT_VRN}/examples/init.d/debian/vnstat \
        /etc/init.d/vnstat
      chmod 755 /etc/init.d/vnstat &> /dev/null
      _mrun "update-rc.d vnstat defaults" 2> /dev/null
      if [ -e "/usr/etc/vnstat.conf" ]; then
        sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /usr/etc/vnstat.conf
      fi
      if [ -e "/etc/vnstat.conf" ]; then
        sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /etc/vnstat.conf
      fi
      _mrun "service vnstat start" 2> /dev/null
      _mrun "killall vnstatd" 2> /dev/null
      touch ${_pthLog}/vnstat-${_VNSTAT_VRN}.log
      _mrun "service vnstat restart" 2> /dev/null
    fi
  fi
  if [ -e "/etc/init.d/vnstat" ] \
    && [ "${_VMFAMILY}" = "VS" ] \
    && [ ! -e "/boot/grub/grub.cfg" ] \
    && [ ! -e "/boot/grub/menu.lst" ]; then
    _mrun "service vnstat stop" 2> /dev/null
    _mrun "update-rc.d -f vnstat remove" 2> /dev/null
    rm -f /etc/init.d/vnstat
    rm -f /usr/bin/vnstat
    rm -rf /var/lib/vnstat
  fi
  if [ -e "/usr/etc/vnstat.conf" ]; then
    sed -i "s/^MaxBandwidth.*/MaxBandwidth 1000/g" /usr/etc/vnstat.conf
    _mrun "service vnstat restart" 2> /dev/null
  fi
}

_install_myquick_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_myquick_src"
  fi
  if [ "${_MYQUICK_INSTALL_REQUIRED}" = "YES" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Building MyQuick ${_MYQUICK_VRN_FIVE} from sources..."
    fi
    _apt_clean_update
    _mrun "${_INSTAPP} cmake" 2> /dev/null
    _mrun "${_INSTAPP} libssl-dev" 2> /dev/null
#     _mrun "${_INSTAPP} libcurl4" 2> /dev/null
#     _mrun "${_INSTAPP} libcurl4-gnutls-dev" 2> /dev/null
    if [ "${_DB_SERVER}" = "Percona" ]; then
      if [ "${_DB_SERIES}" = "5.7" ]; then
        _mrun "${_INSTAPP} libperconaserverclient20 libperconaserverclient20-dev" 2> /dev/null
      elif [ "${_DB_SERIES}" = "8.0" ]; then
        _mrun "${_INSTAPP} libperconaserverclient21 libperconaserverclient21-dev" 2> /dev/null
      else
        _mrun "${_INSTAPP} libperconaserverclient22 libperconaserverclient22-dev" 2> /dev/null
      fi
    fi
    ldconfig 2> /dev/null
    cd /var/opt
    rm -rf mydumper*
    _get_dev_src "mydumper-${_MYQUICK_VRN_FIVE}.tar.gz"
    cd /var/opt/mydumper-${_MYQUICK_VRN_FIVE}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
      export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
      LD_LIBRARY_PATH=/usr/local/lib:/usr/lib/x86_64-linux-gnu \
        cmake \
        -DWITH_SSL=ON \
        -DBUILD_DOCS=ON \
        -DCMAKE_C_FLAGS=-Wno-error=unused-function .
      _mrun "make" 2> /dev/null
      _mrun "make install" 2> /dev/null
    else
      export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH &> /dev/null
      export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH &> /dev/null
      LD_LIBRARY_PATH=/usr/local/lib:/usr/lib/x86_64-linux-gnu \
        cmake \
        -DWITH_SSL=ON \
        -DBUILD_DOCS=ON \
        -DCMAKE_C_FLAGS=-Wno-error=unused-function . &> /dev/null
      _mrun "make --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
    fi
    ldconfig 2> /dev/null
  fi
}

_install_myquick_deb() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_myquick_deb"
  fi
  if [ "${_MYQUICK_SRC_INSTALL_REQUIRED}" = "NO" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Installing MyQuick ${_MYQUICK_VRN_EIGHT} from ${_USE_CODE} packages"
    fi
    cd /var/opt
    rm -rf mydumper_*
    _get_dev_arch "mydumper_${_MYQUICK_VRN_EIGHT}.${_USE_CODE}_amd64.deb.gz"
    if [ -e "/var/opt/mydumper_${_MYQUICK_VRN_EIGHT}.${_USE_CODE}_amd64.deb" ]; then
      _mrun "dpkg -i mydumper_${_MYQUICK_VRN_EIGHT}.${_USE_CODE}_amd64.deb" 2> /dev/null
    fi
    if [ -x "/usr/bin/mydumper" ]; then
      [ -e "/usr/local/bin/mydumper" ] && rm -f /usr/local/bin/mydumper
      [ -e "/usr/local/bin/myloader" ] && rm -f /usr/local/bin/myloader
      ln -sfn /usr/bin/mydumper /usr/local/bin/mydumper
      ln -sfn /usr/bin/myloader /usr/local/bin/myloader
    fi
  else
    _MYQUICK_INSTALL_REQUIRED=YES
    _install_myquick_src
  fi
}

_myquick_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _myquick_install_upgrade"
  fi
  _MYQUICK_SRC_INSTALL_REQUIRED=NO
  if [ "${_SQL_OS_CODE}" = "bookworm" ]; then
    _USE_CODE=bookworm
  elif [ "${_SQL_OS_CODE}" = "bullseye" ]; then
    _USE_CODE=bullseye
  elif [ "${_SQL_OS_CODE}" = "buster" ]; then
    _USE_CODE=buster
  else
    _MYQUICK_SRC_INSTALL_REQUIRED=YES
  fi
  if [ -e "/root/.install.myquick.src.info" ]; then
    _MYQUICK_SRC_INSTALL_REQUIRED=YES
  fi
  _check_mysql_version
  _isMyQuick=$(which mydumper 2>&1)
  if [ ! -x "${_isMyQuick}" ] \
    || [ -z "${_isMyQuick}" ]; then
    if [ "${_MYQUICK_SRC_INSTALL_REQUIRED}" = "NO" ]; then
      _install_myquick_deb
    else
      _install_myquick_src
    fi
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    _MYQUICK_INSTALL_REQUIRED=NO
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
    if [ "${_DB_V}" = "Linux" ]; then
      _DB_V=$(mysql -V 2>&1 \
        | tr -d "\n" \
        | cut -d" " -f4 \
        | awk '{ print $1}' \
        | cut -d"-" -f1 \
        | awk '{ print $1}' \
        | sed "s/[\,']//g" 2>&1)
    fi
    _MD_V=$(mydumper --version 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f6 \
      | awk '{ print $1}' \
      | cut -d"-" -f1 \
      | awk '{ print $1}' \
      | sed "s/[\,']//g" 2>&1)
    if [ -x "${_isMyQuick}" ]; then
      if [ "${_MYQUICK_SRC_INSTALL_REQUIRED}" = "NO" ]; then
        if [ "${_MYQUICK_ITD}" != "${_MYQUICK_VRN_EIGHT}" ]; then
          _MYQUICK_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed MyQuick version ${_MYQUICK_ITD}, upgrade required"
          fi
          _install_myquick_deb
        fi
      else
        if [ "${_MYQUICK_ITD}" != "${_MYQUICK_VRN_FIVE}" ] || [ "${_MD_V}" != "${_DB_V}" ]; then
          _MYQUICK_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed MyQuick version ${_MYQUICK_ITD}, upgrade required"
          fi
          _install_myquick_src
        fi
      fi
    fi
    _isMyQuick=$(which mydumper 2>&1)
    if [ ! -e "${_isMyQuick}" ]; then
      _MYQUICK_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: MyQuick not installed yet"
      fi
      _install_myquick_deb
    fi
  fi
}

_xdrago_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _xdrago_install_upgrade"
  fi
  cd /var
  if [ -d "/var/xdrago/conf" ] \
    && [ -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Upgrading a few more tools..."
    fi
    mv -f /var/xdrago-pre* ${_vBs}/dragon/x/ &> /dev/null
    rm -rf ${_pthLog}/init.d-pre*
    rm -rf ${_vBs}/dragon/z/init.d-pre-*
    rm -f ${_pthLog}/cron-root-pre*
    cp -af /var/xdrago \
      ${_vBs}/dragon/x/xdrago-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    rm -f ${_pthLog}/VISITOR_ABUSE_ONE.log
    rm -f ${_pthLog}/blackIP.log
    rm -f /var/xdrago/{enableStatus,graceful,move_sql,run_all,second,Minute}
    rm -f /var/xdrago/{firewall.sh,stop-mysql-innodb.sh,firewall_restarter}
    rm -f /var/xdrago/{FireStart,memcache,redis}
    cp -af /var/spool/cron/crontabs/root \
      ${_vBs}/dragon/z/cron-root-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    if [ "${_CUSTOM_CONFIG_LSHELL}" = "YES" ] \
      && [ -e "/var/xdrago/conf/lshell.conf" ]; then
      cp -af /var/xdrago/conf/lshell.conf ${_vBs}/custom_lshell.conf
    fi
    cp -af ${_bldPth}/aegir/tools/system/* /var/xdrago/ &> /dev/null
    if [ "${_CUSTOM_CONFIG_LSHELL}" = "YES" ] \
      && [ -e "${_vBs}/custom_lshell.conf" ]; then
      cp -af ${_vBs}/custom_lshell.conf /var/xdrago/conf/lshell.conf
    fi
    if [ -z "${_THISHTIP}" ]; then
      _LOC_DOM="${_THISHOST}"
      _find_correct_ip
      _THISHTIP="${_LOC_IP}"
    fi
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
      if [ ! -e "/etc/init.d/redis-server" ]; then
        _NGINX_DOS_LIMIT=8888
      else
        if [ -z "${_NGINX_DOS_LIMIT}" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "199" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "299" ]; then
          _NGINX_DOS_LIMIT=399
        fi
      fi
    fi
    sed -i "s/^_NGINX_DOS_LIMIT=.*/_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}/g"  ${_barCnf}
    sed -i "s/default_critnumber =.*/default_critnumber = ${_NGINX_DOS_LIMIT};/g" /var/xdrago/monitor/check/scan_nginx.pl
    wait
    sed -i "s/default_lines =.*/default_lines = 1999;/g" /var/xdrago/monitor/check/scan_nginx.pl
    wait
    if [ ! -z "${_NGINX_DOS_STOP}" ]; then
      _NGINX_DOS_STOP=${_NGINX_DOS_STOP//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DOS_STOP}" ]; then
        _msg "INFO: Configured _NGINX_DOS_STOP: ${_NGINX_DOS_STOP}"
        sed -i "s/foobar/${_NGINX_DOS_STOP}/g" \
          /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
        wait
      fi
    fi
    if [ ! -z "${_NGINX_DOS_IGNORE}" ]; then
      _NGINX_DOS_IGNORE=${_NGINX_DOS_IGNORE//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DOS_IGNORE}" ]; then
        _msg "INFO: Configured _NGINX_DOS_IGNORE: ${_NGINX_DOS_IGNORE}"
        sed -i "s/dontcount/${_NGINX_DOS_IGNORE}/g" \
          /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
        wait
      fi
    fi
    mv -f /etc/cron.daily/mlocate ${_vBs}/ &> /dev/null
    cp -af /var/xdrago/cron/crontabs/root /var/spool/cron/crontabs/ &> /dev/null
    if [ -e "/var/xdrago/cron/custom.txt" ]; then
      cat /var/xdrago/cron/custom.txt >> /var/spool/cron/crontabs/root
    fi
    chown root:crontab /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
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
        sed -i "s/3600/300/g" /var/xdrago/monitor/check/mysql.sh &> /dev/null
        wait
      elif [ -e "/root/.big_db.cnf" ] || [ -e "/root/.tg.cnf" ]; then
        _DO_NOTHING=YES
      else
        sed -i "s/3600/1800/g" /var/xdrago/monitor/check/mysql.sh &> /dev/null
        wait
      fi
    fi
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    mkdir -p ./xdrago
    cp -af ${_bldPth}/aegir/tools/system/* ./xdrago/ &> /dev/null
    cp -af /var/xdrago/cron/crontabs/root /var/spool/cron/crontabs/ &> /dev/null
    chown root:crontab /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
    if [ -z "${_THISHTIP}" ]; then
      _LOC_DOM="${_THISHOST}"
      _find_correct_ip
      _THISHTIP="${_LOC_IP}"
    fi
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
      if [ ! -e "/etc/init.d/redis-server" ]; then
        _NGINX_DOS_LIMIT=8888
      else
        if [ -z "${_NGINX_DOS_LIMIT}" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "199" ] \
          || [ "${_NGINX_DOS_LIMIT}" = "299" ]; then
          _NGINX_DOS_LIMIT=399
        fi
      fi
    fi
    sed -i "s/^_NGINX_DOS_LIMIT=.*/_NGINX_DOS_LIMIT=${_NGINX_DOS_LIMIT}/g"  ${_barCnf}
    sed -i "s/default_critnumber =.*/default_critnumber = ${_NGINX_DOS_LIMIT};/g" /var/xdrago/monitor/check/scan_nginx.pl
    wait
    sed -i "s/default_lines =.*/default_lines = 1999;/g" /var/xdrago/monitor/check/scan_nginx.pl
    wait
    if [ ! -z "${_NGINX_DOS_STOP}" ]; then
      _NGINX_DOS_STOP=${_NGINX_DOS_STOP//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DOS_STOP}" ]; then
        _msg "INFO: Configured _NGINX_DOS_STOP: ${_NGINX_DOS_STOP}"
        sed -i "s/foobar/${_NGINX_DOS_STOP}/g" \
          /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
        wait
      fi
    fi
    if [ ! -z "${_NGINX_DOS_IGNORE}" ]; then
      _NGINX_DOS_IGNORE=${_NGINX_DOS_IGNORE//[^a-zA-Z0-9|-]/}
      if [ ! -z "${_NGINX_DOS_IGNORE}" ]; then
        _msg "INFO: Configured _NGINX_DOS_IGNORE: ${_NGINX_DOS_IGNORE}"
        sed -i "s/dontcount/${_NGINX_DOS_IGNORE}/g" \
          /var/xdrago/monitor/check/scan_nginx.pl &> /dev/null
        wait
      fi
    fi
    mv -f /etc/cron.daily/mlocate ${_vBs}/ &> /dev/null
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
      if [ -e "/root/.debug.cnf" ] && [ ! -e "/root/.default.cnf" ]; then
        _DO_NOTHING=YES
      else
        if [ -e "/root/.high_load.cnf" ] \
          && [ ! -e "/root/.big_db.cnf" ] \
          && [ ! -e "/root/.tg.cnf" ]; then
          sed -i "s/3600/300/g" /var/xdrago/monitor/check/mysql.sh &> /dev/null
          wait
        elif [ -e "/root/.big_db.cnf" ] || [ -e "/root/.tg.cnf" ]; then
          _DO_NOTHING=YES
        else
          sed -i "s/3600/1800/g" /var/xdrago/monitor/check/mysql.sh &> /dev/null
          wait
        fi
        sed -i "s/rotate 52/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
        wait
        sed -i "s/rotate 1/rotate 7/g" /etc/logrotate.d/nginx &> /dev/null
        wait
      fi
    fi
  fi
  if [ -d "/var/xdrago-pre-${_xSrl}-${_X_VERSION}-${_NOW}" ]; then
    cp -af /var/xdrago-pre-${_xSrl}-${_X_VERSION}-${_NOW}/run-* /var/xdrago/ &> /dev/null
  fi
  chmod -R 700 /var/xdrago/monitor/check &> /dev/null
  chmod 700 /var/xdrago/* &> /dev/null
  chmod 700 /var/xdrago &> /dev/null
}

_pam_umask_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _pam_umask_check_fix"
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
    _mrun "service ssh restart" 2> /dev/null
  fi
}

_pam_many_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _pam_many_check_fix"
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

_fix_node_in_lshell_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_node_in_lshell_access"
  fi
  if [ "${_STATUS}" = "UPGRADE" ] && [ -e "/etc/lshell.conf" ]; then
    _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
    _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
      || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
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

_lshell_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _lshell_install_upgrade"
  fi
  _PATH_LSHELL="/usr/local/bin/lshell"
  _LSHELL_CHK_VRN=0.9.18
  _LSHELL_FORCE_REINSTALL=NO
  _isLshell=$(which lshell 2>&1)
  _LSHELL_ITD=$(${_isLshell} --version 2>&1 \
    | tr -d "\n" \
    | cut -d"-" -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_LSHELL_ITD}" != "${_LSHELL_CHK_VRN}" ] \
    || [[ "${_LSHELL_ITD}" =~ "Traceback" ]] \
    || [[ "${_LSHELL_ITD}" =~ "bad interpreter" ]] \
    || [[ "${_LSHELL_ITD}" =~ "ImportError" ]]; then
    _LSHELL_FORCE_REINSTALL=YES
  fi
  if [ ! -e "${_PATH_LSHELL}" ] \
    || [ "${_LSHELL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
    if [ "${_STATUS}" = "UPGRADE" ]; then
      _msg "INFO: Upgrading Limited Shell to version ${_LSHELL_VRN}..."
      cp -af /etc/lshell.conf /etc/lshell.conf-bak-${_NOW} &> /dev/null
    else
      _msg "INFO: Installing Limited Shell ${_LSHELL_VRN}..."
    fi
    _apt_clean_update
    _mrun "${_INSTAPP} python3-pip" 2> /dev/null
    if [ -x "/usr/local/bin/pip3" ]; then
      _usePip=/usr/local/bin/pip3
    elif [ -x "/usr/bin/pip3" ]; then
      _usePip=/usr/bin/pip3
    fi
    _PIP_TEST=$(${_usePip} --version 2>&1)
    if [[ "${_PIP_TEST}" =~ "python 3.11" ]] \
      || [[ "${_PIP_TEST}" =~ "python 3.12" ]]; then
      _mrun "${_usePip} install --upgrade pip --root-user-action ignore" 2> /dev/null
    else
      _mrun "${_usePip} install --upgrade pip" 2> /dev/null
    fi
    cd /var/opt
    rm -rf lshell*
    _get_dev_src "lshell-${_LSHELL_VRN}.tar.gz"
    for _Files in `find /var/opt/lshell-${_LSHELL_VRN} -type f`; do
      sed -i "s/kicked/logged/g" ${_Files} &> /dev/null
      wait
      sed -i "s/Kicked/Logged/g" ${_Files} &> /dev/null
      wait
    done
    rm -rf /usr/local/lib/python*/site-packages/lshell*
    rm -rf /usr/local/lib/python*/dist-packages/lshell*
    cd /var/opt/lshell-${_LSHELL_VRN}
    _PIP_TEST=$(${_usePip} --version 2>&1)
    if [[ "${_PIP_TEST}" =~ "python 3.11" ]] \
      || [[ "${_PIP_TEST}" =~ "python 3.12" ]]; then
      _mrun "${_usePip} install . --break-system-packages --root-user-action ignore" 2> /dev/null
    else
      _mrun "${_usePip} install . " 2> /dev/null
    fi
    if [ "${_STATUS}" = "UPGRADE" ]; then
      cp -af /etc/lshell.conf-bak-${_NOW} /etc/lshell.conf &> /dev/null
    else
      cp -af ${_bldPth}/aegir/tools/system/conf/lshell.conf /etc/lshell.conf
      echo "${_PATH_LSHELL}" >> /etc/shells
    fi
    rm -f /etc/logrotate.d/lshell
    addgroup --system lshellg &> /dev/null
    mkdir -p /var/log/lsh
    chown :lshellg /var/log/lsh
    chmod 770 /var/log/lsh &> /dev/null
    touch ${_pthLog}/lshell-build-${_LSHELL_VRN}.log
    if [ -f "/var/xdrago/manage_ltd_users.sh" ]; then
      if [ "${_STATUS}" = "UPGRADE" ] \
        && [ "${_CUSTOM_CONFIG_LSHELL}" = "NO" ]; then
        cp -af ${_bldPth}/aegir/tools/system/conf/lshell.conf \
          /var/xdrago/conf/lshell.conf
      fi
      _st_runner "bash /var/xdrago/manage_ltd_users.sh" &> /dev/null
    fi
    _fix_node_in_lshell_access
  fi
  if [ -f "/usr/local/bin/lshell" ]; then
    if [ ! -L "/usr/bin/lshell" ]; then
      ln -sfn /usr/local/bin/lshell /usr/bin/lshell &> /dev/null
    fi
  fi
}

_if_install_ftpd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_ftpd"
  fi
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_XTRAS_LIST}" =~ "FTP" ]]; then
    if [ ! -e "/var/ftp" ]; then
      _mrun "useradd -r -d /var/ftp -s /sbin/nologin -m ftp" 2> /dev/null
    fi
    if [ ! -e "/etc/ssl/private/pure-ftpd.pem" ] \
      || [ ! -e "/usr/local/sbin/pure-ftpd" ] \
      || [ ! -e "${_pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_xSrl}-${_X_VERSION}.log" ] \
      || [ ! -e "/etc/ssl/private/pure-ftpd-dhparams.pem" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
      || [ "${_SSL_INSTALL_REQUIRED}" = "YES" ]; then
      _msg "INFO: Building Pure-FTPd server from sources..."
      sed -i "/^$/d" /etc/ld.so.conf.d/libc.conf &> /dev/null
      if [ ! -e "/etc/ssl/private/pure-ftpd-dhparams.pem" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Generating DH parameters, 2048 bit..."
        fi
        _mrun "openssl dhparam -out /etc/ssl/private/pure-ftpd-dhparams.pem 2048" 2> /dev/null
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
      _get_dev_src "pure-ftpd-${_PURE_FTPD_VRN}.tar.gz"
      cd pure-ftpd-${_PURE_FTPD_VRN}
      bash autogen.sh &> /dev/null
      LIBS="-ldl -lpthread" PKG_CONFIG_PATH="/usr/local/ssl3/lib64/pkgconfig" ./configure \
        --oldincludedir=/usr/local/ssl3/include \
        --includedir=/usr/local/ssl3/include \
        --with-everything --with-virtualchroot \
        --without-humor --with-tls --with-diraliases --with-pam \
        --with-certfile=/etc/ssl/private/pure-ftpd.pem &> /dev/null
      _mrun "make -j $(nproc) --quiet" 2> /dev/null
      _mrun "make --quiet install" 2> /dev/null
      cd /usr/local/sbin/
      cp -af ${_locCnf}/ftpd/pure-config.pl.txt ./
      mv -f pure-config.pl.txt pure-config.pl 2> /dev/null
      chmod 755 /usr/local/sbin/pure-config.pl 2> /dev/null
      cp -af /var/opt/pure-ftpd-${_PURE_FTPD_VRN}/pam/pure-ftpd /etc/pam.d/
      _fix_ftps_pam
      cd /usr/local/etc
      rm -f pure-ftpd.conf
      cp -af ${_locCnf}/ftpd/pure-ftpd.conf ./
      ln -sfn /usr/local/etc/pure-ftpd.conf /usr/local/etc/pure-ftpd.conf~
      killall -9 pure-ftpd &> /dev/null
      _ftpdInit="/usr/local/sbin/pure-config.pl"
      _ftpdConf="/usr/local/etc/pure-ftpd.conf"
      _ftpdBind="/usr/local/sbin/pure-ftpd"
      if [ -x "${_ftpdBind}" ] && [ -f "${_ftpdConf}" ]; then
        if [ -x "${_ftpdInit}" ]; then
          ${_ftpdInit} ${_ftpdConf} &> /dev/null
        else
          ${_ftpdBind} ${_ftpdConf} &> /dev/null
        fi
      fi
      cd /var/opt
      touch ${_pthLog}/pure-ftpd-build-${_PURE_FTPD_VRN}-${_xSrl}-${_X_VERSION}.log
    fi
  fi
}

_newrelic_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _newrelic_check_fix"
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
    _newrelic_update
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
    _mrun "service newrelic-daemon restart" 2> /dev/null
  else
    if [ -e "/etc/init.d/newrelic-daemon" ] \
      || [ -e "/etc/init.d/newrelic-sysmond" ]; then
      _mrun "service newrelic-daemon stop" 2> /dev/null
      _mrun "update-rc.d -f newrelic-daemon remove" 2> /dev/null
      _mrun "service newrelic-sysmond stop" 2> /dev/null
      _mrun "update-rc.d -f newrelic-sysmond remove" 2> /dev/null
      _st_runner "${_RMAPP} newrelic-php5 \
        newrelic-php5-common \
        newrelic-daemon \
        newrelic-sysmond" 2> /dev/null
      mv -f /etc/newrelic \
        ${_vBs}/nr/etc-newrelic-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
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
      _mrun "service newrelic-sysmond restart" 2> /dev/null
    else
      _mrun "service newrelic-sysmond stop" 2> /dev/null
    fi
  fi
}

_java_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _java_check_fix"
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

_sshd_armour() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sshd_armour"
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
        _msg "INFO: Generating new ssh_host_ed25519_key..."
        ssh-keygen -t ed25519 -N "" -q -f /etc/ssh/ssh_host_ed25519_key < /dev/null
        touch /etc/ssh/.ssh_host_ed25519_key.pid
      fi
      if [ ! -e "/etc/ssh/.ssh_host_rsa_key4096.pid" ]; then
        _msg "INFO: Generating new ssh_host_rsa_key..."
        ssh-keygen -t rsa -b 4096 -N "" -q -f /etc/ssh/ssh_host_rsa_key < /dev/null
        touch /etc/ssh/.ssh_host_rsa_key4096.pid
        _msg "NOTE: You will be asked to accept the new SSH fingerprint the next time you connect"
      fi
      _isKeyg=$(which ssh-keygen 2>&1)
      if [ -x "${_isKeyg}" ] \
        && [ -e "${_SYSCONFDIR}/moduli" ] \
        && [ ! -e "${_SYSCONFDIR}/.moduli_bak" ]; then
        _msg "WAIT: New SSH moduli generate may take a long time, please wait..."
        cd /var/opt
        rm -rf /var/opt/moduli-*
        _mrun "${_isKeyg} -M generate -O bits=2048 moduli-2048.candidates" 2> /dev/null
        wait
        _mrun "${_isKeyg} -M screen -f moduli-2048.candidates moduli-2048" 2> /dev/null
        wait
        if [ -e "/var/opt/moduli-2048" ]; then
          cp -af ${_SYSCONFDIR}/moduli ${_SYSCONFDIR}/.moduli_bak
          cp -af /var/opt/moduli-2048 ${_SYSCONFDIR}/moduli
          _mrun "service ssh restart" 2> /dev/null
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
    _mrun "service ssh reload" 2> /dev/null
  fi
}

_initd_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _initd_update"
  fi
  _THIS_DB_PORT=3306
  if [ "${_STATUS}" = "INIT" ]; then
    _msg "INFO: Updating init scripts"
    cp -af ${_locCnf}/var/clean-boa-env /etc/init.d/clean-boa-env
    chmod 755 /etc/init.d/clean-boa-env &> /dev/null
    _mrun "update-rc.d clean-boa-env defaults" 2> /dev/null
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
    _mrun "service ssh reload" 2> /dev/null
    _tune_memory_limits
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Solr 7"
      fi
      kill -9 $(ps aux | grep '[s]olr' | awk '{print $2}') &> /dev/null
      _mrun "service solr7 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Jetty 9"
      fi
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      _mrun "service jetty9 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Jetty 8"
      fi
      kill -9 $(ps aux | grep '[j]etty8' | awk '{print $2}') &> /dev/null
      _mrun "service jetty8 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Jetty 7"
      fi
      kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
      _mrun "service jetty7 start" 2> /dev/null
    fi
    if [ ! -e "/run/aegir_upgrade.pid" ]; then
      _msg "INFO: Starting Redis, PHP-FPM and Nginx"
      _mrun "service redis-server start" 2> /dev/null
      _mrun "service redis-server reload" 2> /dev/null
      _mrun "update-rc.d -f php5-fpm remove" 2> /dev/null
      _mrun "update-rc.d cron defaults" 2> /dev/null
      _PHP_V="83 82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          _mrun "update-rc.d php${e}-fpm defaults" 2> /dev/null
          _mrun "service php${e}-fpm start" 2> /dev/null
        fi
      done
      _mrun "update-rc.d nginx defaults" 2> /dev/null
      _mrun "service nginx start" 2> /dev/null
    fi
  else
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ] \
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
    _mrun "service ssh reload" 2> /dev/null
    _fix_on_upgrade
    _tune_memory_limits
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Solr 7"
      fi
      kill -9 $(ps aux | grep '[s]olr' | awk '{print $2}') &> /dev/null
      _mrun "service solr7 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Jetty 9"
      fi
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      _mrun "service jetty9 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Jetty 8"
      fi
      kill -9 $(ps aux | grep '[j]etty8' | awk '{print $2}') &> /dev/null
      _mrun "service jetty8 start" 2> /dev/null
    fi
    if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Restarting Jetty 7"
      fi
      kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
      _mrun "service jetty7 start" 2> /dev/null
    fi
    if [ ! -e "/run/aegir_upgrade.pid" ] \
      && [ ! -e "/root/.proxy.cnf" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Reloading Redis, PHP-FPM and Nginx..."
      fi
      _mrun "update-rc.d -f php5-fpm remove" 2> /dev/null
      _mrun "service redis-server reload" 2> /dev/null
      _PHP_V="83 82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          _mrun "update-rc.d php${e}-fpm defaults" 2> /dev/null
        fi
      done
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          _mrun "service php${e}-fpm reload" 2> /dev/null
        fi
      done
      _mrun "service nginx quietupgrade" 2> /dev/null
      _DB_SERVER_TEST=$(mysql -V 2>&1)
      if [[ "${_DB_SERVER_TEST}" =~ "Distrib ${_DB_SERIES}." ]]; then
        _check_mysql_version
        if [ "${_DB_V}" = "5.7" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Running ${_DB_SERVER} system tables (2) upgrade..."
          fi
          rm -f /var/lib/mysql/mysql_upgrade_info &> /dev/null
          if [ -x "/usr/bin/mysql_upgrade" ]; then
            _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
            _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
            _mrun "mysql_upgrade -u root --force" &> /dev/null
            _mrun "mysql_upgrade -u root --force" &> /dev/null
          fi
        fi
      fi
      _myCnf="/etc/mysql/my.cnf"
      _preCnf="${_vBs}/dragon/t/my.cnf-pre-${_xSrl}-${_X_VERSION}-${_NOW}"
      if [ -f "${_myCnf}" ]; then
        _myCnfUpdate=NO
        if [ ! -f "${_preCnf}" ]; then
          mkdir -p ${_vBs}/dragon/t/
          cp -af ${_myCnf} ${_preCnf}
        fi
        _diffMyTest=$(diff -w -B \
          -I innodb_buffer_pool_size \
          -I innodb_buffer_pool_instances \
          -I innodb_page_cleaners \
          -I tmp_table_size \
          -I max_heap_table_size \
          -I myisam_sort_buffer_size \
          -I key_buffer_size ${_myCnf} ${_preCnf} 2>&1)
        if [ -z "${_diffMyTest}" ]; then
          _myCnfUpdate=NO
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: ${_DB_SERVER} diff0 empty"
          fi
        else
          _myCnfUpdate=YES
          # _diffMyTest=$(echo -n ${_diffMyTest} | fmt -su -w 2500 2>&1)
          _msg "INFO: ${_DB_SERVER} diff1 ${_diffMyTest}"
        fi
        if [[ "${_diffMyTest}" =~ "innodb_buffer_pool_size" ]]; then
          _myCnfUpdate=NO
          _msg "INFO: ${_DB_SERVER} diff2 ${_diffMyTest}"
        fi
        if [[ "${_diffMyTest}" =~ "No such file or directory" ]]; then
          _myCnfUpdate=NO
          _msg "INFO: ${_DB_SERVER} diff3 ${_diffMyTest}"
        fi
      fi
      if [ "${_UP_SQL}" = "YES" ]; then
        _myVnTest=$(mysql -V 2>&1)
        if [[ "${_myVnTest}" =~ "${_DBS_VRN}" ]]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: ${_DB_SERVER} ${_DBS_VRN} already up to date"
          fi
          _myCnfUpdate=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: ${_DB_SERVER} restart after upgrade forced"
          fi
        fi
      fi
      if [ ! -e "/root/.run-to-daedalus.cnf" ] \
        && [ ! -e "/root/.run-to-chimaera.cnf" ] \
        && [ ! -e "/root/.run-to-beowulf.cnf" ]; then
        _SQL_PSWD=$(cat /root/.my.pass.txt 2>&1)
        _SQL_PSWD=$(echo -n ${_SQL_PSWD} | tr -d "\n" 2>&1)
        _myUptime=$(mysqladmin -u root version | grep -i uptime 2>&1)
        _myUptime=$(echo -n ${_myUptime} | fmt -su -w 2500 2>&1)
        _msg "INFO: ${_DB_SERVER} ${_myUptime}"
        if [ "${_myRstrd}" = "YES" ]; then
          _myCnfUpdate=NO
          _msg "INFO: ${_DB_SERVER} already restarted!"
        fi
        if [ "${_myCnfUpdate}" = "YES" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Restarting ${_DB_SERVER} server..."
          fi
          mysql -u root -e "INSTALL SONAME 'ha_archive';" &> /dev/null
          _mrun "bash /var/xdrago/move_sql.sh" &> /dev/null
          wait
          _msg "INFO: ${_DB_SERVER} server restart completed"
        fi
        _check_mysql_version
        if [ "${_DB_V}" = "5.7" ] || [ "${_DB_SERIES}" = "5.7" ]; then
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
          mysql -u root -e "SET GLOBAL innodb_stats_on_metadata=0;" &> /dev/null
          rm -f /etc/mysql/conf.d/mysqldump.cnf
        fi
      fi
    fi
  fi
}

_sysctl_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sysctl_update"
  fi
  if [ ! -e "/root/.no.sysctl.update.cnf" ] \
    && [ ! -e "${_pthLog}/sysctl.conf-${_xSrl}-${_X_VERSION}-${_NOW}.log" ]; then
    cp -af /etc/sysctl.conf \
      ${_vBs}/dragon/t/sysctl.conf-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    if [ -e "${_locCnf}/var/sysctl.conf" ]; then
      cp -af ${_locCnf}/var/sysctl.conf /etc/sysctl.conf
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
      _mrun "service redis-server restart" 2> /dev/null
      _mrun "service nginx restart" 2> /dev/null
      _mrun "service sshd restart" 2> /dev/null
      _PHP_V="83 82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ -e "/etc/init.d/php${e}-fpm" ]; then
          _mrun "service php${e}-fpm reload" 2> /dev/null
        fi
      done
    fi
    touch ${_pthLog}/sysctl.conf-${_xSrl}-${_X_VERSION}-${_NOW}.log
  fi
}

_apticron_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _apticron_update"
  fi
  XPTEMAIL=${_MY_EMAIL//\@/\\\\\@}
  sed -i "s/notify\@omega8.cc/${_MY_EMAIL}/g"  \
    /etc/csf/csf.conf &> /dev/null
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/checksql.pl
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/daily.sh
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/usage.sh
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/monitor/check/segfault_alert.pl
  sed -i "s/notify\\\@omega8.cc/$XPTEMAIL/g" \
    /var/xdrago/monitor/check/escapecheck.pl
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
        _mrun "apt-get remove apticron -y --purge --auto-remove -qq" 2> /dev/null
        _mrun "apt-get install apticron -y" 2> /dev/null
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
    _barUpv="${_tRee}"
    sed -i "s/aptitude full-upgrade/barracuda up-${_barUpv} system/g" /usr/sbin/apticron
      wait
    sed -i "s/apt-get dist-upgrade/barracuda up-${_barUpv} system/g" /usr/sbin/apticron
      wait
    sed -i "s/barracuda up-${_tRee}.*/barracuda up-${_barUpv} system/g" /usr/sbin/apticron
  fi
}

_rsyslog_config_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _rsyslog_config_update"
  fi
  if [ -x "/etc/init.d/rsyslog" ] \
    && [ -e "/etc/rsyslog.conf" ]; then
    mv -f /etc/rsyslog.conf \
      /var/backups/.etc.rsyslog.conf-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${_locCnf}/var/rsyslog.conf /etc/rsyslog.conf
    cp -af ${_locCnf}/var/mysql-notices.conf /etc/rsyslog.d/mysql-notices.conf
    cp -af ${_locCnf}/var/logrotate.d.rsyslog.conf /etc/logrotate.d/rsyslog
    touch /var/log/mysql-notices.log
    chmod 640 /var/log/mysql-notices.log
    chown root:adm /var/log/mysql-notices.log
    _mrun "service rsyslog restart" 2> /dev/null
  fi
}

_complete() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _complete"
  fi
  _fix_lfd_whitelist
  _fix_lfd_uidignore
  _fix_cnf_postfix
  _re_set_default_php_cli
  if [ -d "/data/u" ]; then
    _composer_install_upgrade
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
      _symlink_to_dash
      _switch_to_dash
    elif [ -x "/bin/bash" ] || [ -x "/usr/bin/bash" ]; then
      _symlink_to_bash
      _switch_to_bash
    fi
    _strict_bin_permissions
    rm -f /etc/apt/apt.conf.d/00sandboxtmp
    rm -f /etc/apt/apt.conf.d/00temp
  fi
  _finale
}
