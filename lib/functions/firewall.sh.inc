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
# Ensure /usr/sbin/ipset and /sbin/ipset both resolve to the actual ipset binary.
_ensure_ipset_symlinks() {
  _IPSET_REAL="$(command -v ipset 2>/dev/null || true)"
  if [ -z "${_IPSET_REAL}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "ipset not installed; skipping symlink fixes"
    fi
    return 0
  fi

  # Resolve through any intermediate symlinks.
  if [ -L "${_IPSET_REAL}" ]; then
    _IPSET_REAL="$(readlink -f "${_IPSET_REAL}")"
  fi

  for _CAND in /usr/sbin/ipset /sbin/ipset; do
    _PARENT="$(dirname "${_CAND}")"
    [ -d "${_PARENT}" ] || mkdir -p "${_PARENT}"

    # If the candidate *is* the real file, nothing to do.
    if [ "${_CAND}" = "${_IPSET_REAL}" ]; then
      continue
    fi

    # If it exists, check whether it already resolves to the right target.
    if [ -e "${_CAND}" ] || [ -L "${_CAND}" ]; then
      _TARGET="$(readlink -f "${_CAND}" 2>/dev/null || true)"
      if [ "${_TARGET}" = "${_IPSET_REAL}" ]; then
        continue
      fi
    fi

    ln -sfn "${_IPSET_REAL}" "${_CAND}"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "Linked ${_CAND} -> ${_IPSET_REAL}"
    fi
  done
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
    _mrun "apt-get install ipset ${_aptYesUnth}"
  fi

  _ensure_ipset_symlinks

  ###
  ### Fix for iptables paths backward compatibility
  ###
  if [ -x "/sbin/iptables" ] && [ ! -e "/usr/sbin/iptables" ]; then
    ln -sfn /sbin/iptables /usr/sbin/iptables
  fi
  if [ -x "/usr/sbin/iptables" ] && [ ! -e "/sbin/iptables" ]; then
    ln -sfn /usr/sbin/iptables /sbin/iptables
  fi
  if [ -x "/sbin/iptables-save" ] && [ ! -e "/usr/sbin/iptables-save" ]; then
    ln -sfn /sbin/iptables-save /usr/sbin/iptables-save
  fi
  if [ -x "/usr/sbin/iptables-save" ] && [ ! -e "/sbin/iptables-save" ]; then
    ln -sfn /usr/sbin/iptables-save /sbin/iptables-save
  fi
  if [ -x "/sbin/iptables-restore" ] && [ ! -e "/usr/sbin/iptables-restore" ]; then
    ln -sfn /sbin/iptables-restore /usr/sbin/iptables-restore
  fi
  if [ -x "/usr/sbin/iptables-restore" ] && [ ! -e "/sbin/iptables-restore" ]; then
    ln -sfn /usr/sbin/iptables-restore /sbin/iptables-restore
  fi
  if [ -x "/sbin/ip6tables" ] && [ ! -e "/usr/sbin/ip6tables" ]; then
    ln -sfn /sbin/ip6tables /usr/sbin/ip6tables
  fi
  if [ -x "/usr/sbin/ip6tables" ] && [ ! -e "/sbin/ip6tables" ]; then
    ln -sfn /usr/sbin/ip6tables /sbin/ip6tables
  fi
  if [ -x "/sbin/ip6tables-save" ] && [ ! -e "/usr/sbin/ip6tables-save" ]; then
    ln -sfn /sbin/ip6tables-save /usr/sbin/ip6tables-save
  fi
  if [ -x "/usr/sbin/ip6tables-save" ] && [ ! -e "/sbin/ip6tables-save" ]; then
    ln -sfn /usr/sbin/ip6tables-save /sbin/ip6tables-save
  fi
  if [ -x "/sbin/ip6tables-restore" ] && [ ! -e "/usr/sbin/ip6tables-restore" ]; then
    ln -sfn /sbin/ip6tables-restore /usr/sbin/ip6tables-restore
  fi
  if [ -x "/usr/sbin/ip6tables-restore" ] && [ ! -e "/sbin/ip6tables-restore" ]; then
    ln -sfn /usr/sbin/ip6tables-restore /sbin/ip6tables-restore
  fi
  ###
  ### Fix for iptables paths backward compatibility
  ###
  rm -f ${_pthLog}/lastFire
  if [ "${_OS_CODE}" = "stretch" ]; then
    _CSF_VRN=13.08
  elif [ "${_OS_CODE}" = "jessie" ]; then
    _CSF_VRN=12.04
  fi
  _get_dev_src "csf-${_CSF_VRN}.tgz"
  cd csf
  _mrun "sh install.sh"
  _NFTABLES_TEST=$(iptables -V)
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
    if [ -n "${_CUSTOM_CONFIG_CSF}" ] && [ "${_CUSTOM_CONFIG_CSF}" != "YES" ]; then
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
    fi
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
    pkill -9 -f /usr/sbin/sshd || true
    _mrun "service ssh start"
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

# Function to add an IP to a CSF file if not already present
_add_ip_if_missing() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _add_ip_if_missing"
  fi
  local _IP="$1"
  local _FILE="$2"
  if grep -q "^${_IP}$" "${_FILE}"; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Gateway IP (${_IP}) is already listed in ${_FILE}."
    fi
    _alreadyListed=TRUE
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Adding Gateway IP (${_IP}) to ${_FILE}..."
    fi
    echo "${_IP}" >> "${_FILE}"
  fi
}

# Function to add an Gateway IP to allowed and ignored by CSF/LDF
_csf_lfd_gateway_allow() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _csf_lfd_gateway_allow"
  fi
  # Detect the gateway IP from the default route
  _GATEWAY_IP=$(ip route show default 2>/dev/null | awk '/default/ {print $3}')
  # Ensure we got a valid gateway IP
  if [[ -z "${_GATEWAY_IP}" ]]; then
    _msg "WARN: Could not detect a default Gateway IP."
  else
    _CSF_ALLOW_FILE="/etc/csf/csf.allow"
    _CSF_IGNORE_FILE="/etc/csf/csf.ignore"
    # Add the gateway IP to csf.allow
    _alreadyListed=FALSE
    _add_ip_if_missing "${_GATEWAY_IP}" "${_CSF_ALLOW_FILE}"
    [ "${_alreadyListed}" = "FALSE" ] && _msg "INFO: The Gateway IP (${_GATEWAY_IP}) is now allowed by CSF/LFD."
    # Add the gateway IP to csf.ignore
    _alreadyListed=FALSE
    _add_ip_if_missing "${_GATEWAY_IP}" "${_CSF_IGNORE_FILE}"
    [ "${_alreadyListed}" = "FALSE" ] && _msg "INFO: The Gateway IP (${_GATEWAY_IP}) is now ignored by CSF/LFD."
    # Reload CSF to apply changes
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Reloading CSF..."
    fi
    if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
      csf -ra &> /dev/null
      synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    else
      csf -r &> /dev/null
    fi
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
    _mrun "apt-get install ipset ${_aptYesUnth}"
  fi

  _ensure_ipset_symlinks

  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_XTRAS_LIST}" =~ "CSF" ]]; then
    _check_system_manufacturer
    if [ ! -e "/run/cloud_vhost.pid" ] \
      && [ ! -e "/run/${_SYS_MANUFACTURER_LC}_vm.pid" ]; then
      if [ ! -e "/usr/sbin/csf" ]; then
        echo " "
        if _prompt_yes_no "Do you want to install csf/lfd firewall?" ; then
          true
          _CSF_MODE=install
          _csf_install
          _csf_lfd_gateway_allow
        else
          _msg "INFO: csf/lfd firewall installation skipped"
        fi
      fi
    fi
  fi
  if [ -x "/usr/sbin/csf" ] \
    || [ -e "/usr/sbin/lfd" ] \
    || [ -e "/etc/cron.d/lfd" ]; then
    if [ "${_CSF_COMPATIBILITY}" = "NO" ]; then
      _REMOVE_CSF=YES
    elif [ "${_VMFAMILY}" = "VS" ] \
      && [ ! -e "/boot/grub/grub.cfg" ] \
      && [ ! -e "/boot/grub/menu.lst" ]; then
      _REMOVE_CSF=YES
    fi
    if [ "${_REMOVE_CSF}" = "YES" ]; then
      _mrun "service lfd stop"
      pkill -9 -f ConfigServer
      killall sleep &> /dev/null
      rm -f /etc/csf/csf.error
      csf -x &> /dev/null
      _mrun "update-rc.d -f csf remove"
      _mrun "update-rc.d -f lfd remove"
      rm -f /etc/cron.d/{csf,lfd}*
      rm -f /usr/sbin/{csf,lfd}
      rm -f /etc/init.d/{csf,lfd}
      rm -rf /etc/csf
    else
      _CSF_ITD=$(/usr/sbin/csf --version 2>&1 \
        | tr -d "\n" \
        | tr -d "v" \
        | cut -d"-" -f1 \
        | awk '{ print $2}' 2>&1)
      if [ "${_CSF_ITD}" = "${_CSF_VRN}" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed CSF/LFD version ${_CSF_ITD}, OK"
        fi
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed CSF/LFD version ${_CSF_ITD}, upgrade required"
        fi
        _CSF_MODE=upgrade
        _csf_install
        _csf_lfd_gateway_allow
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
        _mrun "service lfd stop"
        pkill -9 -f ConfigServer
        killall sleep &> /dev/null
        rm -f /etc/csf/csf.error
        if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
          csf -ra &> /dev/null
          synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
        else
          csf -r &> /dev/null
        fi
        ### Linux kernel TCP SACK CVEs mitigation
        ### CVE-2019-11477 SACK Panic
        ### CVE-2019-11478 SACK Slowness
        ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
        if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
          _SACK_TEST=$(ip6tables --list | grep tcpmss)
          if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
            sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
            iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
            ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
            [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
          fi
        fi
      fi
    fi
  fi
}
