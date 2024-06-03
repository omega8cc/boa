
tRee=dev
export tRee="${tRee}"

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
# Not supported virtualization system.
not_supported_virt() {
  echo
  echo "=== OOPS! ==="
  echo
  echo "You are running not supported virtualization system:"
  echo "  $1"
  echo
  echo "If you wish to try BOA on this system anyway,"
  echo "please create an empty control file:"
  echo "  /root/.allow.any.virt.cnf"
  echo
  echo "Please be aware that it may not work at all,"
  echo "or you can experience errors breaking BOA."
  echo
  echo "BOA is known to work well on:"
  echo " * Linux KVM guest"
  echo " * Linux VServer guest"
  echo " * Parallels guest"
  echo " * VirtualBox guest"
  echo " * VMware ESXi guest (but excluding vCloud Air)"
  echo " * Xen guest"
  echo
  echo "BOA is not designed to run directly on a bare metal."
  echo "We recommend to install Linux VServer if you plan to"
  echo "use BOA on a dedicated machine -- server or laptop."
  echo
  echo "Note: There are plans to support Linux VServer installation"
  echo "via BOA tools: https://github.com/omega8cc/boa/issues/980"
  echo
  echo "Bye"
  echo
  clean_pid_exit
}

#
# Not supported OS.
not_supported_os() {
  echo
  echo "=== OOPS! ==="
  echo
  echo "It is not any supported Devuan or Debian version."
  echo
  echo "You need Devuan Beowulf (recommended) or Debian Buster first."
  echo
  echo "Bye"
  echo
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
    echo "If you see any error with advice to run 'dpkg --configure --force-all -a'"
    echo "run this command with default answer, then run this installer again"
    echo " "
    tail -15 ${_LOG}
    return 1
  fi
}

#
# Remove dangerous stuff from the string.
sanitize_string() {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\&\|\*]//g; s/\(['"'"'\]\)//g'
}

#
# Extract archive.
extract_archive() {
  if [ ! -z "$1" ]; then
    case $1 in
      *.tar.bz2)   tar xjf $1    ;;
      *.tar.gz)    tar xzf $1    ;;
      *.tar.xz)    tar xvf $1    ;;
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
    if [ -e "$1" ]; then
      extract_archive "$1"
    else
      msg "OOPS: $1 failed download from ${urlDev}/$1"
    fi
  fi
}

#
# Download and extract from dev/version mirror.
get_dev_ext() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/$1" -o "$1"
    if [ -e "$1" ]; then
      extract_archive "$1"
    else
      msg "OOPS: $1 failed download from ${urlDev}/${_AEGIR_XTS_VRN}/$1"
    fi
  fi
}

#
# Download and extract from dev/static.
get_dev_stc() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/static/$1" -o "$1"
    if [ -e "$1" ]; then
      extract_archive "$1"
    else
      msg "OOPS: $1 failed download from ${urlDev}/${_AEGIR_XTS_VRN}/static/$1"
    fi
  fi
}

#
# Download and extract from dev/contrib mirror.
get_dev_contrib() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/${_AEGIR_XTS_VRN}/contrib/$1" -o "$1"
    if [ -e "$1" ]; then
      extract_archive "$1"
    else
      msg "OOPS: $1 failed download from ${urlDev}/${_AEGIR_XTS_VRN}/contrib/$1"
    fi
  fi
}

#
# Download and extract archive from dev/src mirror.
get_dev_src() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/src/$1" -o "$1"
    if [ -e "$1" ]; then
      extract_archive "$1"
    else
      msg "OOPS: $1 failed download from ${urlDev}/src/$1"
    fi
  fi
}

normalize_ip_name_variables() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: normalize_ip_name_variables"
  fi
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: mode_detection"
  fi
  if [ -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ] \
    && [ ! -e "/lib/systemd/systemd" ]; then
    _STATUS=UPGRADE
    msg "MODE: UPGRADE"
    barracuda_cnf
    touch /var/run/boa_wait.pid
    [ -e "/root/.use.curl.from.packages.cnf" ] && chattr -i /root/.use.curl.from.packages.cnf
    [ -e "/root/.use.curl.from.packages.cnf" ] && rm -f /root/.use.curl.from.packages.cnf
    if [ -e "/root/.auto.up.cnf" ] \
      || [ -e "/root/.host8.cnf" ]; then
      _XTRAS_LIST="ADM CSF FTP CSS DCS"
    fi
  elif [ ! -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ] \
    && [ -e "/lib/systemd/systemd" ]; then
    _STATUS=SYSTEMD
    msg "MODE: SYSTEMD"
    touch /var/run/boa_wait.pid
  elif [ ! -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ] \
    && [ -e "/root/.run.devuan.os.upgrade.on.init.cnf" ]; then
    _STATUS=DISTRO
    msg "MODE: DISTRO"
    barracuda_cnf
    touch /var/run/boa_wait.pid
  else
    _STATUS=INIT
    [ -e "/root/.use.curl.from.packages.cnf" ] && chattr -i /root/.use.curl.from.packages.cnf
    [ -e "/root/.use.curl.from.packages.cnf" ] && rm -f /root/.use.curl.from.packages.cnf
    if [ -d "/var/aegir" ]; then
      msg "MODE: FORCED INIT"
      _FULL_FORCE_REINSTALL=YES
    else
      msg "MODE: NORMAL INIT"
    fi
    _ZOMBIE_HOME="${vBs}/zombie/${_X_VERSION}-${_NOW}"
    mkdir -p ${_ZOMBIE_HOME}
    mv -f /etc/nginx/conf.d/* ${_ZOMBIE_HOME}/ &> /dev/null
    mv -f /var/aegir ${_ZOMBIE_HOME}/ &> /dev/null
    mv -f /var/xdrago ${_ZOMBIE_HOME}/ &> /dev/null
    mv -f /root/.my.cnf ${_ZOMBIE_HOME}/ &> /dev/null
    mv -f /root/.my.pass.txt ${_ZOMBIE_HOME}/ &> /dev/null
    cp -af /etc/sudoers ${_ZOMBIE_HOME}/ &> /dev/null
    sed -i "s/^aegir.*//g" /etc/sudoers &> /dev/null
    kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
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
      _XTRAS_LIST="ADM"
      _AUTOPILOT=YES
      _SSH_PORT=22
      _DNS_SETUP_TEST=NO
      _SMTP_RELAY_TEST=NO
      _LOCAL_NETWORK_IP="127.0.1.1"
      _LOCAL_NETWORK_HN="aegir.local"
    elif [ "${_EASY_SETUP}" = "PUBLIC" ]; then
      msg "INFO: Public Setup Mode Active"
      _XTRAS_LIST="ADM CSF FTP CSS DCS"
      if [ -e "/root/.auto.up.cnf" ] \
        || [ -e "/root/.host8.cnf" ]; then
        _XTRAS_LIST="ADM CSF FTP CSS DCS"
      fi
      _AUTOPILOT=YES
      _SSH_PORT=22
      _MY_HOSTN="${_EASY_HOSTNAME}"
      _MY_FRONT="master.${_EASY_HOSTNAME}"
      validate_public_ip &> /dev/null
      _MY_OWNIP="${_THISHTIP}"
    elif [ "${_EASY_SETUP}" = "MSTR" ]; then
      msg "INFO: Cluster Master Mode Active"
      _XTRAS_LIST=""
      _AUTOPILOT=YES
      _DB_SERVER=Percona
      _DB_SERIES=5.7
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
      _DB_SERVER=Percona
      _DB_SERIES=5.7
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
      _DB_SERVER=Percona
      _DB_SERIES=5.7
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
    if [ "${_STATUS}" != "SYSTEMD" ]; then
      barracuda_cnf
    fi
  fi
  if [ "${_STATUS}" != "SYSTEMD" ]; then
    [ -e "/root/.use.curl.from.packages.cnf" ] && chattr -i /root/.use.curl.from.packages.cnf
    [ -e "/root/.use.curl.from.packages.cnf" ] && rm -f /root/.use.curl.from.packages.cnf
    kill -9 $(ps aux | grep '[s]ystemd-udevd' | awk '{print $2}') &> /dev/null
  fi
  if [ "${_AEGIR_VERSION}" != "static" ]; then
    _USE_AEGIR_VER=SRC
  else
    _USE_AEGIR_VER=STATIC
  fi
  if [ "${_USE_AEGIR_VER}" = "SRC" ] && [ ! -z "${_FORCE_GIT_MIRROR}" ]; then
    if [ "${_FORCE_GIT_MIRROR}" = "gitlab" ]; then
      _INSTAPP="/usr/bin/aptitude-fast -f -y -q \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold install"
    else
      _INSTAPP="/usr/bin/aptitude -f -y -q \
        --allow-untrusted \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold install"
    fi
  else
    _INSTAPP="/usr/bin/aptitude -f -y -q \
      --allow-untrusted \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold install"
  fi

  _RMAPP="/usr/bin/aptitude -f -y -q \
    --allow-untrusted \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold remove"

  _SRCDIR="/opt/tmp/files"
  rm -rf /var/opt/*
  mkdir -p ${_SRCDIR}
  chmod -R 777 /opt/tmp &> /dev/null
  find /opt/tmp/boa -type d -exec chmod 0755 {} \; &> /dev/null
  find /opt/tmp/boa -type f -exec chmod 0644 {} \; &> /dev/null
  rm -f /var/run/aegir_upgrade.pid
  if [ "${_STATUS}" != "UPGRADE" ]; then
    _STRICT_BIN_PERMISSIONS=NO
  fi
  if [ "${_STRICT_BIN_PERMISSIONS}" = "YES" ]; then
    if [ -x "/bin/dash" ] || [ -x "/usr/bin/dash" ]; then
      symlink_to_dash
      switch_to_dash
    elif [ -x "/bin/bash" ] || [ -x "/usr/bin/bash" ]; then
      symlink_to_bash
      switch_to_bash
    fi
  fi
  _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
  if [ -z "${_PHP_SV}" ] \
    || [ "${_PHP_SV}" = "55" ] \
    || [ "${_PHP_SV}" = "54" ] \
    || [ "${_PHP_SV}" = "53" ] \
    || [ "${_PHP_SV}" = "52" ]; then
    _PHP_SV=74
  fi
  _PHP_CN="www${_PHP_SV}"
}

check_exception_mycnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_exception_mycnf"
  fi
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

virt_detection() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: virt_detection"
  fi
  _VIRT_TOOL=$(which virt-what 2> /dev/null)
  if [ -x "${_VIRT_TOOL}" ]; then
    _VIRT_TEST=$(virt-what 2> /dev/null)
    _VIRT_TEST=$(echo -n ${_VIRT_TEST} | fmt -su -w 2500 2>&1)
    if [ ! -e "/root/.allow.any.virt.cnf" ]; then
      if [ -e "/proc/self/status" ]; then
        _VS_GUEST_TEST=$(grep -E "VxID:[[:space:]]*[0-9]{2,}$" /proc/self/status 2> /dev/null)
        _VS_HOST_TEST=$(grep -E "VxID:[[:space:]]*0$" /proc/self/status 2> /dev/null)
      fi
      if [ ! -z "${_VS_HOST_TEST}" ] || [ ! -z "${_VS_GUEST_TEST}" ]; then
        if [ -z "${_VS_HOST_TEST}" ] && [ ! -z "${_VS_GUEST_TEST}" ]; then
          _VIRT_IS="Linux VServer guest"
        else
          if [ ! -z "${_VS_HOST_TEST}" ]; then
            not_supported_virt "Linux VServer host"
          else
            not_supported_virt "unknown / not a virtual machine"
          fi
        fi
      else
        if [ -z "${_VIRT_TEST}" ] || [ "${_VIRT_TEST}" = "0" ]; then
          not_supported_virt "unknown / not a virtual machine"
        elif [[ "${_VIRT_TEST}" =~ "xen-dom0" ]]; then
          not_supported_virt "Xen privileged domain"
        elif [[ "${_VIRT_TEST}" =~ "linux_vserver-host" ]]; then
          not_supported_virt "Linux VServer host"
        else
          if [[ "${_VIRT_TEST}" =~ "xen xen-hvm" ]]; then
            _VIRT_TEST="xen-hvm"
          elif [[ "${_VIRT_TEST}" =~ "xen xen-domU" ]]; then
            _VIRT_TEST="xen-domU"
          elif [[ "${_VIRT_TEST}" =~ "virtualbox kvm" ]]; then
            _VIRT_TEST="virtualbox"
          elif [[ "${_VIRT_TEST}" =~ "hyperv qemu" ]]; then
            _VIRT_TEST="hyperv"
          elif [[ "${_VIRT_TEST}" =~ "kvm aws" ]]; then
            _VIRT_TEST="kvm"
          elif [[ "${_VIRT_TEST}" =~ "openvz lxc" ]]; then
            _VIRT_TEST="openvz"
          fi
          case "${_VIRT_TEST}" in
            hyperv)      _VIRT_IS="Microsoft Hyper-V" ;;
            kvm)         _VIRT_IS="Linux KVM guest" ;;
            lxc)         _VIRT_IS="Linux Containers (LXC)" ;;
            openvz)      _VIRT_IS="OpenVZ Containers" ;;
            parallels)   _VIRT_IS="Parallels guest" ;;
            virtualbox)  _VIRT_IS="VirtualBox guest" ;;
            vmware)      _VIRT_IS="VMware ESXi guest" ;;
            xen-domU)    _VIRT_IS="Xen paravirtualized guest domain" ;;
            xen-hvm)     _VIRT_IS="Xen guest fully virtualized (HVM)" ;;
            xen)         _VIRT_IS="Xen guest" ;;
            *)  not_supported_virt "${_VIRT_TEST}"
            ;;
          esac
        fi
      fi
      if [ "${_AUTOPILOT}" = "NO" ]; then
        echo
      fi
      msg "VIRT: This system is supported: ${_VIRT_IS}"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        echo
        msg "HINT: Command to run in another terminal window to watch details"
        msg "CMND: tail -f ${_LOG}"
        echo
      fi
    else
      if [ -z "${_VIRT_TEST}" ] || [ "${_VIRT_TEST}" = "0" ]; then
        _VIRT_TEST="unknown / not a virtual machine"
      fi
      if [ "${_AUTOPILOT}" = "NO" ]; then
        echo
      fi
      msg "WARN: This system is not supported: ${_VIRT_TEST}"
    fi
  fi
}

os_detection_minimal() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: os_detection_minimal"
  fi
  _APT_UPDATE="apt-get update"
  _THIS_RV=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_THIS_RV}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}

apt_clean_update() {
  apt-get clean -qq 2> /dev/null
  rm -rf /var/lib/apt/lists/* &> /dev/null
  ${_APT_UPDATE} -qq 2> /dev/null
}

apt_clean_update_no_releaseinfo_change() {
  apt-get clean -qq 2> /dev/null
  rm -rf /var/lib/apt/lists/* &> /dev/null
  apt-get update -qq 2> /dev/null
}

os_detection() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: os_detection"
  fi
  _THIS_OS=$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)
  _THIS_RV=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  if [ "${_THIS_OS}" = "Debian" ]; then
    if [ "${_THIS_RV}" = "bookworm" ]; then
      _OSR="bookworm"
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    elif [ "${_THIS_RV}" = "bullseye" ]; then
      _OSR="bullseye"
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    elif [ "${_THIS_RV}" = "buster" ]; then
      _OSR="buster"
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    elif [ "${_THIS_RV}" = "stretch" ]; then
      _OSR="stretch"
    elif [ "${_THIS_RV}" = "jessie" ]; then
      _OSR="jessie"
    else
      not_supported_os
    fi
    _NGINX_FORWARD_SECRECY=YES
    _NGINX_SPDY=YES
    if [ "${_DB_SERIES}" = "10.4" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_4_VRN}"
    elif [ "${_DB_SERIES}" = "10.3" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_3_VRN}"
    elif [ "${_DB_SERIES}" = "10.2" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_2_VRN}"
    elif [ "${_DB_SERIES}" = "5.7" ]; then
      _DB_SERVER=Percona
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    else
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    fi
    _SPINNER=NO
    _SKIP_LEGACY_PHP=YES
  elif [ "${_THIS_OS}" = "Devuan" ]; then
    if [ "${_THIS_RV}" = "daedalus" ]; then
      _OSR="daedalus"
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    elif [ "${_THIS_RV}" = "chimaera" ]; then
      _OSR="chimaera"
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    elif [ "${_THIS_RV}" = "beowulf" ]; then
      _OSR="beowulf"
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    else
      not_supported_os
    fi
    _NGINX_FORWARD_SECRECY=YES
    _NGINX_SPDY=YES
    if [ "${_DB_SERIES}" = "10.4" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_4_VRN}"
    elif [ "${_DB_SERIES}" = "10.3" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_3_VRN}"
    elif [ "${_DB_SERIES}" = "10.2" ]; then
      _DB_SERVER=MariaDB
      _DBS_VRN="${_MARIADB_10_2_VRN}"
    elif [ "${_DB_SERIES}" = "5.7" ]; then
      _DB_SERVER=Percona
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    else
      _DB_SERVER=Percona
      _DB_SERIES=5.7
      _DBS_VRN="${_PERCONA_5_7_VRN}"
    fi
    _SPINNER=NO
    _SKIP_LEGACY_PHP=YES
  else
    not_supported_os
  fi
  echo " "
  thiSys="$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1)/$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1) $(uname -m 2>&1)"
  thiSys="$(uname -n 2>&1) ${thiSys} PHP ${_PHP_FPM_VERSION}"
  msg "Aegir on ${thiSys}"
  echo " "
}

check_boa_php_compatibility() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_boa_php_compatibility"
  fi
  if [[ "${_PHP_MULTI_INSTALL}" =~ "8.3" ]] \
    || [[ "${_PHP_MULTI_INSTALL}" =~ "8.2" ]] \
    || [[ "${_PHP_MULTI_INSTALL}" =~ "8.1" ]] \
    || [[ "${_PHP_MULTI_INSTALL}" =~ "7.4" ]]; then
    _DO_NOTHING=YES
  else
    msg "ERROR: This BOA version depends on PHP 8.1 or newer"
    msg "Please add at least 8.1 to _PHP_MULTI_INSTALL"
    msg "in /root/.barracuda.cnf before trying again"
    msg "NOTE: You can still install also legacy PHP 7.x and 5.6 versions"
    msg "NOTE: but you must also include at least 8.1 to support Drupal 10"
    msg "Bye"
    clean_pid_exit
  fi
  if [ "${_PHP_FPM_VERSION}" = "5.3" ] \
    || [ "${_PHP_FPM_VERSION}" = "5.4" ] \
    || [ "${_PHP_FPM_VERSION}" = "5.5" ] \
    || [ "${_PHP_FPM_VERSION}" = "5.6" ] \
    || [ "${_PHP_FPM_VERSION}" = "7.0" ] \
    || [ "${_PHP_FPM_VERSION}" = "7.1" ] \
    || [ "${_PHP_FPM_VERSION}" = "7.2" ] \
    || [ "${_PHP_FPM_VERSION}" = "7.3" ] \
    || [ "${_PHP_FPM_VERSION}" = "8.0" ] \
    || [ "${_PHP_CLI_VERSION}" = "5.3" ] \
    || [ "${_PHP_CLI_VERSION}" = "5.4" ] \
    || [ "${_PHP_CLI_VERSION}" = "5.5" ] \
    || [ "${_PHP_CLI_VERSION}" = "5.6" ] \
    || [ "${_PHP_CLI_VERSION}" = "7.0" ] \
    || [ "${_PHP_CLI_VERSION}" = "7.1" ] \
    || [ "${_PHP_CLI_VERSION}" = "7.2" ] \
    || [ "${_PHP_CLI_VERSION}" = "7.3" ] \
    || [ "${_PHP_CLI_VERSION}" = "8.0" ]; then
    msg "ERROR: This BOA version depends on PHP 8.1 or newer"
    msg "Please change _PHP_FPM_VERSION and _PHP_CLI_VERSION to 8.1 or newer"
    msg "in /root/.barracuda.cnf before trying again"
    msg "NOTE: You can still install also legacy PHP 7.x and 5.6 versions"
    msg "NOTE: but you must use as default version 8.1 to support Drupal 10"
    msg "Bye"
    clean_pid_exit
  fi
}

check_boa_version() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_boa_version"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Checking BARRACUDA version..."
  fi
  if [ -e "/var/log/barracuda_log.txt" ]; then
    _SERIES_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
    if [ "${tRee}" = "lite" ] \
      && [[ "${_SERIES_TEST}" =~ "Barracuda ${rlsn}-pro" ]]; then
      msg "ERROR: Your system has been already upgraded to ${rlsn}-pro"
      msg "You can not downgrade back to previous/older/lite BOA version"
      msg "Please use 'barracuda up-pro system' to upgrade this server"
      msg "Bye"
      clean_pid_exit
    fi
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _VERSIONS_TEST_RESULT=OK
    else
      msg "ERROR: This barracuda installer can be used only when the system"
      msg "has been already upgraded to BOA-4.x or BOA-5.x release"
      msg "Please run 'barracuda up-${tRee}' full upgrade first!"
      msg "Bye"
      clean_pid_exit
    fi
    if [[ "${_SERIES_TEST}" =~ "BOA-4." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-5." ]]; then
      if [[ "${_X_VERSION}" =~ "BOA-4." ]] \
        || [[ "${_X_VERSION}" =~ "BOA-5." ]]; then
        _VERSIONS_TEST_RESULT=OK
      else
        msg "ERROR: Your system has been already upgraded to modern BOA"
        msg "You can not downgrade back to legacy or previous stable version"
        msg "Please use 'barracuda up-${tRee}' to upgrade this system"
        msg "Bye"
        clean_pid_exit
      fi
    fi
  fi
}

check_prepare_dirs_permissions() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_prepare_dirs_permissions"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Cleaning up temp files in /var/opt/"
  fi
  rm -rf /var/opt/*
  mkdir -p /var/log/php
  chmod 777 /var/log/php* &> /dev/null
  mkdir -p ${vBs}/dragon/{x,z,t}
  if [ -e "/etc/init.d/buagent" ]; then
    mv -f /etc/init.d/buagent \
      ${vBs}/buagent-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
  fi
}

avatars_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: avatars_check_fix"
  fi
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

aegir_bin_extra_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: aegir_bin_extra_check_fix"
  fi
  SDIR="${bldPth}/aegir/tools/bin"
  SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership lock-local-drush-permissions)
  if [ ! -x "/usr/local/bin/fix-drupal-site-permissions.sh" ] \
    || [ ! -e "/var/xdrago/log/fix-drupal-site-permissions-${_X_SE}-${_X_VERSION}.log" ]; then
    if [ -e "${SDIR}/fix-drupal-site-permissions.sh" ]; then
      for SCRIPT in ${SCRIPTS[@]}; do
        cp -af ${SDIR}/${SCRIPT}.sh /usr/local/bin/
        chown root:root /usr/local/bin/${SCRIPT}.sh
        chmod 700 /usr/local/bin/${SCRIPT}.sh
      done
      touch /var/xdrago/log/fix-drupal-site-permissions-${_X_SE}-${_X_VERSION}.log
    fi
  fi
}

barracuda_log_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: barracuda_log_update"
  fi
  if [ -L "${mtrInc}/barracuda_log.txt" ]; then
    rm -f ${mtrInc}/barracuda_log.txt
  fi
  if [ "${_THIS_DB_HOST}" = "localhost" ]; then
    _LOG_DB_HOST=localhost
  elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
    _LOG_DB_HOST=PROXYSQL
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
    $(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2 2>&1).$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1) \
    $(uname -m 2>&1) ${_VIRT_IS} / \
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
