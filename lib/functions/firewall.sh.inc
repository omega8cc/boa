#
# Fix csf.uidignore file to whitelist important system uids when UID_INTERVAL != 0
_fix_lfd_uidignore() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_lfd_uidignore"
  fi
  _THIS_FILE=/etc/csf/csf.uidignore
  if [ -e "${_THIS_FILE}" ]; then
    _CSF_UIDIGNORE_TEST=$(grep "unbound" ${_THIS_FILE} 2>&1)
    if [[ "${_CSF_UIDIGNORE_TEST}" =~ "unbound" ]]; then
      _DO_NOTHING=YES
    else
      echo "#root"          >> /etc/csf/csf.uidignore
      echo `id -u root`     >> /etc/csf/csf.uidignore
      if [ -r "/etc/unbound/unbound.conf.d/unbound.conf" ]; then
        echo "#unbound"       >> /etc/csf/csf.uidignore
        echo `id -u unbound`  >> /etc/csf/csf.uidignore
      fi
      echo "#postfix"       >> /etc/csf/csf.uidignore
      echo `id -u postfix`  >> /etc/csf/csf.uidignore
      echo "#www-data"      >> /etc/csf/csf.uidignore
      echo `id -u www-data` >> /etc/csf/csf.uidignore
    fi
    if [ -e "/usr/sbin/named" ]; then
      _CSF_UIDIGNORE_TEST=$(grep "bind" ${_THIS_FILE} 2>&1)
      if [[ "${_CSF_UIDIGNORE_TEST}" =~ "bind" ]]; then
        _DO_NOTHING=YES
      else
        echo "#bind"        >> /etc/csf/csf.uidignore
        echo `id -u bind`   >> /etc/csf/csf.uidignore
      fi
    fi
    sed -i "/^$/d" ${_THIS_FILE} &> /dev/null
  fi
}

#
# Fix csf.fignore file to whitelist /tmp/drush_*
_fix_lfd_whitelist() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _fix_lfd_whitelist"
  fi
  _THIS_FILE=/etc/csf/csf.fignore
  if [ -e "${_THIS_FILE}" ]; then
    _CSF_WHITELIST_TEST=$(grep "jetty" ${_THIS_FILE} 2>&1)
    if [[ "${_CSF_WHITELIST_TEST}" =~ "jetty" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/.*\/tmp\/.*//g" ${_THIS_FILE} &> /dev/null
      wait
      sed -i "/^$/d"            ${_THIS_FILE} &> /dev/null
      wait
      echo "/tmp/drush_tmp.*"      >> ${_THIS_FILE}
      echo "/tmp/drush_make_tmp.*" >> ${_THIS_FILE}
      echo "/tmp/make_tmp.*"       >> ${_THIS_FILE}
      echo "/tmp/hsperfdata.*"     >> ${_THIS_FILE}
      echo "/tmp/jetty.*"          >> ${_THIS_FILE}
    fi
  fi
}

#
# install csf/lfd firewall
_csf_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _csf_install"
  fi
  if [ "${_CSF_MODE}" = "install" ]; then
    _msg "INFO: Installing csf/lfd firewall..."
  else
    _msg "INFO: Upgrading csf/lfd firewall..."
  fi
  cd /var/opt
  _IPSET_TEST=$(which ipset 2> /dev/null)
  if [ ! -x "${_IPSET_TEST}" ]; then
    _apt_clean_update
    if [ -L "/sbin/ipset" ]; then
      rm -f /sbin/ipset
    fi
    if [ -L "/usr/sbin/ipset" ]; then
      rm -f /usr/sbin/ipset
    fi
    _mrun "apt-get install ipset ${_aptYesUnth}" 2> /dev/null
  fi
  if [ -x "/sbin/ipset" ] && [ ! -e "/usr/sbin/ipset" ]; then
    ln -s /sbin/ipset /usr/sbin/ipset
  fi
  if [ -x "/usr/sbin/ipset" ] && [ ! -e "/sbin/ipset" ]; then
    ln -s /usr/sbin/ipset /sbin/ipset
  fi
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
  rm -f ${_pthLog}/lastFire
  ### from https://download.configserver.com/csf.tgz
  _get_dev_src "csf-${_CSF_VRN}.tgz"
  cd csf
  _mrun "sh install.sh" 2> /dev/null
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
  cd /var/opt
  _if_hosted_sys
  if [ "${_hostedSys}" = "YES" ]; then
    _SSH_PORT=22
  fi
  _CSF_COMPATIBILITY_TEST=$(perl /etc/csf/csftest.pl 2>&1)
  if [[ "${_CSF_COMPATIBILITY_TEST}" =~ "RESULT: csf should function" ]]; then
    _CSF_COMPATIBILITY=YES
  elif [[ "${_CSF_COMPATIBILITY_TEST}" =~ "some features will not work" ]]; then
    _CSF_COMPATIBILITY=PARTIAL
    sed -i "s/^PORTFLOOD .*/PORTFLOOD = \"\"/g" /etc/csf/csf.conf &> /dev/null
    wait
    sed -i "s/^CONNLIMIT .*/CONNLIMIT = \"\"/g" /etc/csf/csf.conf &> /dev/null
    wait
    sed -i "s/^USE_CONNTRACK .*/USE_CONNTRACK = \"0\"/g" /etc/csf/csf.conf &> /dev/null
    wait
  elif [[ "${_CSF_COMPATIBILITY_TEST}" =~ "FATAL" ]]; then
    _CSF_COMPATIBILITY=NO
  else
    _CSF_COMPATIBILITY=NO
  fi
  if [ "${_CSF_COMPATIBILITY}" = "YES" ] \
    || [ "${_CSF_COMPATIBILITY}" = "PARTIAL" ]; then
    if [ "${_CSF_COMPATIBILITY}" = "PARTIAL" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "TEST: csf/lfd firewall should mostly work on this system"
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "TEST: csf/lfd firewall should work fine on this system"
      fi
    fi
    mv -f /etc/csf/csf.conf \
      /etc/csf/csf.conf-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${_locCnf}/var/csf.conf /etc/csf/csf.conf
    sed -i "s/notify\@omega8.cc/${_MY_EMAIL}/g" /etc/csf/csf.conf &> /dev/null
    wait
    sed -i "s/TCP_IN = \"20,21,22,/TCP_IN = \"20,21,${_SSH_PORT},/g" \
      /etc/csf/csf.conf &> /dev/null
    wait
    sed -i "s/^CC_SRC .*/CC_SRC = \"2\"/g" /etc/csf/csf.conf &> /dev/null
    wait
    chmod 600 /etc/csf/csf.conf &> /dev/null
    if [ -e "/etc/ssh/sshd_config" ]; then
      sed -i "s/^Port.*/Port ${_SSH_PORT}/g"  /etc/ssh/sshd_config
      wait
      sed -i "s/^#Port.*/Port ${_SSH_PORT}/g" /etc/ssh/sshd_config
      wait
      sed -i "s/^UsePrivilegeSeparation.*//g" /etc/ssh/sshd_config
      wait
      sed -i "s/^ClientAliveCountMax.*/ClientAliveCountMax 10000/g" /etc/ssh/sshd_config
      wait
      sed -i "s/^#TCPKeepAlive.*/TCPKeepAlive yes/g" /etc/ssh/sshd_config
      wait
    fi
    _mrun "service ssh restart" 2> /dev/null
    if [ "${_CSF_MODE}" = "install" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: csf/lfd firewall installed"
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: csf/lfd firewall upgrade completed"
      fi
    fi
    touch ${_pthLog}/csf_${_X_VERSION}.log
  else
    _msg "TEST: csf/lfd firewall can not be installed on this system"
  fi
}

_csf_lfd_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _csf_lfd_install_upgrade"
  fi
  _IPSET_TEST=$(which ipset 2> /dev/null)
  if [ ! -x "${_IPSET_TEST}" ]; then
    _apt_clean_update
    if [ -L "/sbin/ipset" ]; then
      rm -f /sbin/ipset
    fi
    if [ -L "/usr/sbin/ipset" ]; then
      rm -f /usr/sbin/ipset
    fi
    _mrun "apt-get install ipset ${_aptYesUnth}" 2> /dev/null
  fi
  if [ -x "/sbin/ipset" ] && [ ! -e "/usr/sbin/ipset" ]; then
    ln -s /sbin/ipset /usr/sbin/ipset
  fi
  if [ -x "/usr/sbin/ipset" ] && [ ! -e "/sbin/ipset" ]; then
    ln -s /usr/sbin/ipset /sbin/ipset
  fi
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_XTRAS_LIST}" =~ "CSF" ]] \
    || [ "${_CSF_CLSTR}" = "YES" ]; then
    if [ ! -e "/run/cloud_vhost.pid" ]; then
      if [ ! -e "/usr/sbin/csf" ]; then
        echo " "
        if _prompt_yes_no "Do you want to install csf/lfd firewall?" ; then
          true
          _CSF_MODE=install
          _csf_install
        else
          _msg "INFO: csf/lfd firewall installation skipped"
        fi
      fi
    fi
  fi
  if [ -x "/usr/sbin/csf" ] \
    || [ -e "/usr/sbin/lfd" ] \
    || [ -e "/etc/cron.d/lfd" ]; then
    if [ "${_CSF_COMPATIBILITY}" = "NO" ] \
      || [ "${_CSF_CLSTR}" = "NO" ]; then
      _REMOVE_CSF=YES
    elif [ "${_VMFAMILY}" = "VS" ] \
      && [ ! -e "/boot/grub/grub.cfg" ] \
      && [ ! -e "/boot/grub/menu.lst" ]; then
      _REMOVE_CSF=YES
    fi
    if [ "${_REMOVE_CSF}" = "YES" ]; then
      _mrun "service lfd stop" 2> /dev/null
      wait
      kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
      killall sleep &> /dev/null
      rm -f /etc/csf/csf.error
      csf -x &> /dev/null
      wait
      _mrun "update-rc.d -f csf remove" 2> /dev/null
      _mrun "update-rc.d -f lfd remove" 2> /dev/null
      rm -f /etc/cron.d/{csf,lfd}*
      rm -f /usr/sbin/{csf,lfd}
      rm -f /etc/init.d/{csf,lfd}
      rm -rf /etc/csf
    else
      if [ "${_CUSTOM_CONFIG_CSF}" = "YES" ]; then
        _DO_NOTHING=YES
      else
        _CSF_MODE=upgrade
        _csf_install
      fi
      sed -i "s/^AUTO_UPDATES .*/AUTO_UPDATES = \"0\"/g" /etc/csf/csf.conf &> /dev/null
      wait
      if [ "${_VMFAMILY}" = "VZ" ]; then
        sed -i "s/^PORTFLOOD .*/PORTFLOOD = \"\"/g" /etc/csf/csf.conf &> /dev/null
        wait
        sed -i "s/^CONNLIMIT .*/CONNLIMIT = \"\"/g" /etc/csf/csf.conf &> /dev/null
        wait
        sed -i "s/^USE_CONNTRACK .*/USE_CONNTRACK = \"0\"/g" /etc/csf/csf.conf &> /dev/null
        wait
      fi
      if [ -e "${_pthLog}/lastFire" ]; then
        rm -f ${_pthLog}/lastFire
        _mrun "service lfd stop" 2> /dev/null
        wait
        kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
        killall sleep &> /dev/null
        rm -f /etc/csf/csf.error
        _mrun "csf -x" &> /dev/null
        wait
        _mrun "csf -e" &> /dev/null
        wait
        _mrun "csf -q" &> /dev/null
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
    fi
  fi
}
