
tRee=dev
export tRee="${tRee}"

#
# Fix DNS settings.
fix_dns_settings() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_dns_settings"
  fi
  mkdir -p ${vBs}
  rm -f ${vBs}/resolv.conf.tmp
  if [ -e "/etc/resolv.conf" ]; then
    if [ -L "/etc/resolv.conf" ]; then
      rslvT=`readlink -n /etc/resolv.conf`
      if [ ! -e "${rslvT}" ]; then
        rm -f /etc/resolv.conf
      fi
    fi
    if [ -e "/etc/resolv.conf" ]; then
      cp -a /etc/resolv.conf ${vBs}/resolv.conf.tmp
    fi
  fi
  if [ ! -e "${vBs}/resolv.conf.tmp" ]; then
    echo "nameserver 127.0.0.1" > ${vBs}/resolv.conf.tmp
    echo "nameserver 1.1.1.1" >> ${vBs}/resolv.conf.tmp
    echo "nameserver 1.0.0.1" >> ${vBs}/resolv.conf.tmp
    echo "nameserver 8.8.8.8" >> ${vBs}/resolv.conf.tmp
    echo "nameserver 8.8.4.4" >> ${vBs}/resolv.conf.tmp
  fi
  if [ ! -e "${vBs}/resolv.conf.vanilla" ]; then
    for Pre in `ls -la ${vBs}/resolv.conf.pre-*`; do
      if [ -e "${Pre}" ] && [ -f "${Pre}" ] && [ ! -L "${Pre}" ]; then
        cp -a ${Pre} ${vBs}/resolv.conf.vanilla
      fi
    done
  fi
  if [ ! -e "${vBs}/resolv.conf.vanilla" ] \
    && [ -e "${vBs}/resolv.conf.tmp" ]; then
    if [ "${_USE_DEFAULT_DNS}" != "YES" ]; then
      rm -f /etc/resolv.conf
      cp -a ${vBs}/resolv.conf.tmp /etc/resolv.conf
      cp -a ${vBs}/resolv.conf.tmp ${vBs}/resolv.conf.vanilla
    fi
  fi
  sed -i "/^$/d" ${vBs}/resolv.conf.vanilla &> /dev/null
  if [ -e "${vBs}/resolv.conf.vanilla" ]; then
    if [ "${_USE_DEFAULT_DNS}" != "YES" ]; then
      rm -f /etc/resolv.conf
      cp -a ${vBs}/resolv.conf.vanilla /etc/resolv.conf
    fi
  else
    if [ -e "${vBs}/resolv.conf.tmp" ] \
      && [ "${_USE_DEFAULT_DNS}" != "YES" ]; then
      rm -f /etc/resolv.conf
      cp -a ${vBs}/resolv.conf.tmp /etc/resolv.conf
    fi
  fi
}

#
# Check DNS settings.
check_dns_settings() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_dns_settings"
  fi
  if [ -e "/root/.use.default.nameservers.cnf" ]; then
    _USE_DEFAULT_DNS=YES
  fi
  if [ -e "/root/.use.local.nameservers.cnf" ]; then
    _USE_PROVIDER_DNS=YES
  else
    _REMOTE_DNS_TEST=$(host -s files.aegir.cc 1.1.1.1 -w 10 2>&1)
  fi
  if [[ "${_REMOTE_DNS_TEST}" =~ "no servers could be reached" ]] \
    || [[ "${_REMOTE_DNS_TEST}" =~ "Host files.aegir.cc not found" ]] \
    || [ "${_USE_DEFAULT_DNS}" = "YES" ] \
    || [ "${_USE_PROVIDER_DNS}" = "YES" ]; then
    if [ "${_USE_DEFAULT_DNS}" = "YES" ] \
      || [ "${_USE_PROVIDER_DNS}" = "YES" ] \
      || [ ! -e "${vBs}/resolv.conf.vanilla" ]; then
      fix_dns_settings
      if [ -e "/etc/init.d/postfix" ]; then
        mrun "service postfix restart" 2> /dev/null
      fi
    fi
  fi
}

#
# Check repo status.
check_git_repos() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_git_repos"
  fi
  if [ "${_AEGIR_VERSION}" != "static" ]; then
    _GITHUB_WORKS=NO
    _GITLAB_WORKS=NO
    if [ "${_FORCE_GIT_MIRROR}" = "drupal" ]; then
      _FORCE_GIT_MIRROR=github
    fi
    if [ "${_FORCE_GIT_MIRROR}" = "gitorious" ]; then
      _FORCE_GIT_MIRROR=gitlab
    fi
    if [ "${_FORCE_GIT_MIRROR}" = "github" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: We will use forced GitHub repository without testing connection"
      fi
      _GITHUB_WORKS=YES
      _GITLAB_WORKS=NO
      sleep 1
    elif [ "${_FORCE_GIT_MIRROR}" = "gitlab" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: We will use forced GitLab mirror without testing connection"
      fi
      _GITHUB_WORKS=NO
      _GITLAB_WORKS=YES
      sleep 1
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Testing repository mirror servers availability..."
      fi
      sleep 1
      _GITHUB_WORKS=YES
      _GITLAB_WORKS=YES
      if ! netcat -w 10 -z github.com 443 ; then
        _GITHUB_WORKS=NO
        msg "WARN: The GitHub master repository server doesn't respond..."
      elif ! netcat -w 10 -z gitlab.com 443 ; then
        _GITLAB_WORKS=NO
        msg "WARN: The GitLab mirror repository server doesn't respond..."
      fi
    fi
    if [ "${_GITHUB_WORKS}" = "YES" ]; then
      _BOA_REPO_NAME="boa"
      _BOA_REPO_GIT_URL="${gitHub}"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: GitHub master repository will be used"
      fi
    elif [ "${_GITLAB_WORKS}" = "YES" ]; then
      _BOA_REPO_NAME="boa"
      _BOA_REPO_GIT_URL="${gitLab}"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: GitLab mirror repository will be used"
      fi
    else
      cat <<EOF

      None of repository servers responded in 8 seconds,
      so we can't continue this installation.

      Please try again later or check if your firewall has port 443 open.

      Bye.

EOF
      clean_pid_exit check_git_repos_a
    fi
  fi
}

#
# Find correct IP.
find_correct_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: find_correct_ip"
  fi
  if [ -e "/root/.found_correct_ipv4.cnf" ]; then
    _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>&1)
    _LOC_IP=$(echo -n ${_LOC_IP} | tr -d "\n" 2>&1)
  else
    _LOC_IP=$(curl ${crlGet} https://api.ipify.org \
      | sed 's/[^0-9\.]//g' 2>&1)
    if [ -z "${_LOC_IP}" ]; then
      _LOC_IP=$(curl ${crlGet} http://ipv4.icanhazip.com \
        | sed 's/[^0-9\.]//g' 2>&1)
    fi
    if [ ! -z "${_LOC_IP}" ]; then
      echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
    fi
  fi
}

#
# Validate server public IP.
validate_public_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: validate_public_ip"
  fi
  if [ "${_VMFAMILY}" = "AWS" ]; then
    _LOC_DOM="${_MY_HOSTN}"
    if [ -z "${_MY_OWNIP}" ]; then
      find_correct_ip
      _MY_OWNIP="${_LOC_IP}"
    else
      _LOC_IP="${_MY_OWNIP}"
    fi
  fi
  if [ ! -z "${_LOCAL_NETWORK_IP}" ]; then
    if [ -z "${_LOCAL_NETWORK_HN}" ]; then
      msg "FATAL ERROR: you must specify also _LOCAL_NETWORK_HN"
      clean_pid_exit validate_public_ip_a
    else
      _MY_OWNIP="${_LOCAL_NETWORK_IP}"
      _MY_HOSTN="${_LOCAL_NETWORK_HN}"
      _MY_FRONT="${_LOCAL_NETWORK_HN}"
      _THISHTIP="${_LOCAL_NETWORK_IP}"
    fi
  else
    if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
      if [ -z "${_MY_OWNIP}" ]; then
        find_correct_ip
        _THISHTIP="${_LOC_IP}"
      else
        _THISHTIP="${_MY_OWNIP}"
      fi
    else
      if [ -z "${_MY_OWNIP}" ] && [ ! -z "${_MY_HOSTN}" ]; then
        _LOC_DOM="${_MY_HOSTN}"
        find_correct_ip
        _THISHTIP="${_LOC_IP}"
      else
        _THISHTIP="${_MY_OWNIP}"
      fi
    fi
  fi
}

#
# Validate server IP for xtras.
validate_xtras_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: validate_xtras_ip"
  fi
  if [ "${_VMFAMILY}" = "AWS" ]; then
    _LOC_DOM="${_MY_HOSTN}"
    if [ -z "${_MY_OWNIP}" ]; then
      find_correct_ip
      _MY_OWNIP="${_LOC_IP}"
    else
      _LOC_IP="${_MY_OWNIP}"
    fi
  fi
  _XTRAS_THISHTIP="*"
}

#
# Validate server IP for purge vhost.
validate_purge_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: validate_purge_ip"
  fi
  if [ "${_PURGE_ALL_THISHTIP}" = "YES" ]; then
    _PURGE_THISHTIP="0.0.0.0/0"
  else
    if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
      if [ -z "${_MY_OWNIP}" ]; then
        find_correct_ip
        _PURGE_THISHTIP="${_LOC_IP}"
      else
        _PURGE_THISHTIP="${_MY_OWNIP}"
      fi
    else
      if [ -z "${_MY_OWNIP}" ]; then
        if [ -e "/usr/bin/sipcalc" ]; then
          if [ -z "${_THISHTIP}" ]; then
            _LOC_DOM="${_THISHOST}"
            find_correct_ip
            _THISHTIP="${_LOC_IP}"
          fi
          _IP_TEST=$(sipcalc ${_THISHTIP} 2>&1)
          if [[ "${_IP_TEST}" =~ "ERR" ]]; then
            _IP_TEST_RESULT=FAIL
            _PURGE_THISHTIP="0.0.0.0/0"
          else
            _IP_TEST_RESULT=OK
            _PURGE_THISHTIP="${_THISHTIP}"
          fi
        else
          _PURGE_THISHTIP="${_THISHTIP}"
        fi
      else
        _PURGE_THISHTIP="${_MY_OWNIP}"
      fi
    fi
    if [ -z "${_PURGE_THISHTIP}" ]; then
      _PURGE_THISHTIP="0.0.0.0/0"
    fi
  fi
}

#
# Validate local server IP.
validate_local_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: validate_local_ip"
  fi
  _LOCAL_THISHTIP=all
}

#
# Wait for connection.
wait_for_connection() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: wait_for_connection"
  fi
  echo " "
  msg "I can not connect to github.com on port 443 at the moment"
  msg "I will try again in 60 seconds, please wait..."
  msg "Waiting for attempt $1..."
  sleep 60
}

#
# Check connection.
check_connection() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_connection"
  fi
  if ! netcat -w 10 -z github.com 443 ; then
    wait_for_connection "2/4"
    if ! netcat -w 10 -z github.com 443 ; then
      wait_for_connection "3/4"
      if ! netcat -w 10 -z github.com 443 ; then
        wait_for_connection "4/4"
        if ! netcat -w 10 -z github.com 443 ; then
          echo " "
          msg "Sorry, I gave up."
          msg "EXIT on error due to GitHub git server at 443 downtime"
          msg "Please try to run this script again in a few minutes"
          msg "You may want to check https://www.githubstatus.com"
          msg "Also, make sure that the outgoing connections via port 443 work"
          msg "Bye"
          clean_pid_exit check_connection_a
        fi
      fi
    fi
  fi
}

#
# Install Unbound from sources.
install_unbound_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: install_unbound_src"
  fi
  msg "INFO: Installing Unbound ${_UNBOUND_VRN}..."
  ldconfig 2> /dev/null
  cd /var/opt
  rm -rf unbound*
  get_dev_src "unbound-${_UNBOUND_VRN}.tar.gz"
  cd unbound-${_UNBOUND_VRN}
  if [ -e "/usr/local/ssl3/" ]; then
    mrun "bash ./configure \
      --prefix=/usr \
      --with-pidfile=/run/unbound/unbound.pid \
      --with-ssl=/usr/local/ssl3" 2> /dev/null
  elif [ -e "/usr/local/ssl/" ]; then
    mrun "bash ./configure \
      --prefix=/usr \
      --with-pidfile=/run/unbound/unbound.pid \
      --with-ssl=/usr/local/ssl" 2> /dev/null
  fi
  mrun "make -j $(nproc) --quiet" 2> /dev/null
  mrun "make --quiet install" 2> /dev/null
}

#
# DNS cache Unbound.
dns_unbound_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: dns_unbound_install_upgrade"
  fi
  isUnbnd=$(which unbound 2>&1)
  isUnbndErr=$(${isUnbnd} -V 2>&1)
  if [[ "${isUnbndErr}" =~ "cannot open shared object file" ]] \
    || [[ "${isUnbndErr}" =~ "No such file or directory" ]] \
    || [ -z "${isUnbndErr}" ]; then
    isUnbndFix=YES
  else
    isUnbndFix=NO
    isUnbndBr=$(service unbound restart 2>&1)
    [[ "${isUnbndBr}" =~ "fatal error" ]] && isUnbndFix=YES
    [[ "${isUnbndBr}" =~ "not found" ]] && isUnbndFix=YES
    [[ "${isUnbndBr}" =~ "address already in use" ]] && killPdnsd=YES
  fi
  if [ ! -x "${isUnbnd}" ] \
    || [ -z "${isUnbnd}" ] \
    || [ "${isUnbndFix}" = "YES" ] \
    || [ -e "/usr/etc/unbound/unbound.pid" ] \
    || [ ! -e "/run/unbound" ] \
    || [ ! -x "/usr/libexec/unbound-helper" ] \
    || [ ! -x "/etc/init.d/unbound" ] \
    || [ ! -e "/etc/resolvconf/run/interface/lo.unbound" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Installing DNS cache Unbound server from packages..."
    fi
    if [ -e "/etc/resolv.conf" ]; then
      cp -af /etc/resolv.conf ${vBs}/resolv.conf.pre-${_X_SE}-${_X_VERSION}-${_NOW}
    fi
    check_dns_settings
    fix_dns_settings
    if [ "${_USE_PROVIDER_DNS}" != "YES" ]; then
      rm -f /etc/resolv.conf
      echo "nameserver 1.1.1.1" > /etc/resolv.conf
      echo "nameserver 1.0.0.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    fi
    apt_clean_update
    if [ "${isUnbndFix}" = "YES" ]; then
      mrun "apt-get remove unbound -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove unbound-anchor -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove unbound-host -y --purge --auto-remove -qq" 2> /dev/null
      mrun "apt-get remove dns-root-data -y --purge --auto-remove -qq" 2> /dev/null
    fi
    mrun "apt-get remove resolvconf -y --purge --auto-remove -qq" 2> /dev/null
    rm -rf /lib/init/rw/resolvconf
    rm -rf /run/resolvconf
    rm -rf /etc/resolvconf
    mrun "apt-get remove resolvconf -y --purge --auto-remove -qq" 2> /dev/null
    if [ "${_USE_PROVIDER_DNS}" != "YES" ]; then
      rm -f /etc/resolv.conf
      echo "nameserver 1.1.1.1" > /etc/resolv.conf
      echo "nameserver 1.0.0.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    fi
    mrun "${_INSTAPP} resolvconf" 2> /dev/null
    mrun "${_INSTAPP} unbound" 2> /dev/null
    mrun "${_INSTAPP} unbound-anchor" 2> /dev/null
    mrun "${_INSTAPP} unbound-host" 2> /dev/null
    mrun "${_INSTAPP} dns-root-data" 2> /dev/null
    ###
    [ ! -e "/run/unbound" ] && mkdir -p /run/unbound
    chown -R unbound:unbound /run/unbound
    [ ! -e "/var/log/unbound/" ] && mkdir -p /var/log/unbound/
    touch /var/log/unbound/unbound.log
    chown -R unbound:unbound /var/log/unbound
    [ ! -e "/var/lib/unbound/" ] && mkdir -p /var/lib/unbound/
    [ -e "/usr/share/dns/" ] && cp -a /usr/share/dns/* /var/lib/unbound/
    [ -e "/var/lib/unbound/" ] && chown -R unbound:unbound /var/lib/unbound
    [ ! -e "/etc/unbound/unbound_control.key" ] && mrun "unbound-control-setup" 2> /dev/null
    cp -af ${locCnf}/dns/unbound /etc/init.d/unbound
    chmod 755 /etc/init.d/unbound
    mrun "update-rc.d unbound defaults" 2> /dev/null
    ###
    if [ -e "/etc/apparmor.d" ] && [ ! -e "/etc/apparmor.d/usr.sbin.unbound" ]; then
      cat ${locCnf}/apparmor/usr.sbin.unbound > /etc/apparmor.d/usr.sbin.unbound
      chmod 644 /etc/apparmor.d/usr.sbin.unbound
    fi
    ###
    cp -a ${locCnf}/dns/unbound-helper > /usr/libexec/unbound-helper
    cat ${locCnf}/dns/unbound.conf > /etc/unbound/unbound.conf.d/unbound.conf
    if [ "${_USE_PROVIDER_DNS}" = "YES" ] \
      && [ -e "${vBs}/resolv.conf.vanilla" ]; then
      cat ${vBs}/resolv.conf.vanilla > /etc/resolvconf/resolv.conf.d/base
    fi
    sed -i "s/pdnsd/unbound/g" /etc/resolvconf/interface-order
    mkdir -p /etc/resolvconf/run/interface
    echo "nameserver 127.0.0.1" > /etc/resolvconf/run/interface/lo.unbound
    resolvconf -u &> /dev/null
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
    killall -9 unbound &> /dev/null
    mrun "service unbound restart" 2> /dev/null
  fi
  check_dns_settings
  if [ "${_USE_PROVIDER_DNS}" = "YES" ] \
    && [ -e "${vBs}/resolv.conf.vanilla" ]; then
    cat ${vBs}/resolv.conf.vanilla > /etc/resolvconf/resolv.conf.d/base
    sed -i "s/pdnsd/unbound/g" /etc/resolvconf/interface-order
    mkdir -p /etc/resolvconf/run/interface
    echo "nameserver 127.0.0.1" > /etc/resolvconf/run/interface/lo.unbound
    resolvconf -u &> /dev/null
  fi
  if [ -e "/etc/resolvconf/run/resolv.conf" ] \
    || [ -e "/run/resolvconf/resolv.conf" ]; then
    _RESOLV_LOC=$(grep "nameserver 127.0.0.1" /etc/resolv.conf 2>&1)
    _RESOLV_ELN=$(grep "nameserver 1.1.1.1" /etc/resolv.conf 2>&1)
    _RESOLV_EGT=$(grep "nameserver 8.8.8.8" /etc/resolv.conf 2>&1)
    if [[ "${_RESOLV_LOC}" =~ "nameserver 127.0.0.1" ]] \
      && [[ "${_RESOLV_ELN}" =~ "nameserver 1.1.1.1" ]] \
      && [[ "${_RESOLV_EGT}" =~ "nameserver 8.8.8.8" ]]; then
      _DO_NOTHING=YES
    else
      rm -f /etc/resolv.conf
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      if [ -e "${vBs}/resolv.conf.vanilla" ]; then
        cat ${vBs}/resolv.conf.vanilla >> /etc/resolv.conf
      fi
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      echo "nameserver 1.0.0.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 8.8.4.4" >> /etc/resolv.conf
      [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
      killall -9 unbound &> /dev/null
      mrun "service unbound restart" 2> /dev/null
      unbound-control reload &> /dev/null
    fi
  fi
  if [ ! -f "/etc/resolv.conf" ]; then
    rm -f /etc/resolv.conf
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
    if [ -e "${vBs}/resolv.conf.vanilla" ]; then
      cat ${vBs}/resolv.conf.vanilla >> /etc/resolv.conf
    fi
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    echo "nameserver 1.0.0.1" >> /etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
    killall -9 unbound &> /dev/null
    mrun "service unbound restart" 2> /dev/null
    unbound-control reload &> /dev/null
  fi
  if [ -e "/etc/NetworkManager/NetworkManager.conf" ]; then
    sed -i "s/^dns=.*/dns=unbound/g" \
      /etc/NetworkManager/NetworkManager.conf &> /dev/null
    mrun "service network-manager restart" 2> /dev/null
  fi
  if [ -x "${isUnbnd}" ] && [ "${isUnbndFix}" = "NO" ]; then
    _UNBOUND_V_ITD=$(${isUnbnd} -V 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f2 \
      | awk '{ print $1}' \
      | sed "s/Configure//gi" 2>&1)
    if [ "${_UNBOUND_V_ITD}" = "${_UNBOUND_VRN}" ]; then
      _UNBOUND_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Unbound version ${_UNBOUND_V_ITD}, OK"
      fi
    else
      _UNBOUND_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Unbound version ${_UNBOUND_V_ITD}, upgrade required"
      fi
    fi
  else
    _UNBOUND_INSTALL_REQUIRED=YES
  fi
  [ -e "/usr/etc/unbound/unbound.pid" ] && _UNBOUND_INSTALL_REQUIRED=YES
  [ -e "/usr/etc/unbound/unbound.pid" ] && rm -f /usr/etc/unbound/unbound.pid
  if [ "${_UNBOUND_INSTALL_REQUIRED}" = "YES" ]; then
    install_unbound_src
  fi
  isUnbnd=$(which unbound 2>&1)
  isUnbndErr=$(${isUnbnd} -V 2>&1)
  if [[ "${isUnbndErr}" =~ "cannot open shared object file" ]] \
    || [[ "${isUnbndErr}" =~ "No such file or directory" ]] \
    || [ -z "${isUnbndErr}" ]; then
    isUnbndFix=YES
  else
    isUnbndFix=NO
  fi
  if [ "${isUnbndFix}" = "NO" ] || [ "${killPdnsd}" = "YES" ]; then
    isPdnsd=$(which pdnsd 2>&1)
    if [ -x "${isPdnsd}" ]; then
      mrun "service pdnsd stop" 2> /dev/null
      mrun "update-rc.d -f pdnsd remove" 2> /dev/null
      killall -9 pdnsd &> /dev/null
      mv -f ${isPdnsd} /var/backups
    fi
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
    killall -9 unbound &> /dev/null
    mrun "service unbound restart" 2> /dev/null
  fi
  if [ -x "${isUnbnd}" ] \
    && [ "${isUnbndFix}" = "NO" ] \
    && [ -e "/etc/resolvconf/interface-order" ]; then
    sed -i "s/pdnsd/unbound/g" /etc/resolvconf/interface-order
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
    killall -9 unbound &> /dev/null
    mrun "service unbound restart" 2> /dev/null
  fi
}

check_github_for_aegir_head_mode() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_github_for_aegir_head_mode"
  fi
  if [ "${_AEGIR_VERSION}" != "static" ]; then
    _USE_AEGIR_VER=SRC
  else
    _USE_AEGIR_VER=STATIC
  fi
  if [ "${_SYSTEM_UPGRADE_ONLY}" = "NO" ] \
    && [ "${_USE_AEGIR_VER}" = "SRC" ]; then
    rm -rf /opt/tmp/test-*
    check_connection
    _GITHUB_TEST=$(git clone ${gitHub}/provision.git \
      /opt/tmp/test-provision 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      msg "EXIT on error (provision) due to GitHub downtime"
      msg "Please try to run this script again in a few minutes"
      msg "You may want to check https://www.githubstatus.com"
      msg "Bye"
      rm -rf /opt/tmp/test-*
      clean_pid_exit check_github_for_aegir_head_mode_a
    fi
    _GITHUB_TEST=$(git clone ${gitHub}/hostmaster.git \
      /opt/tmp/test-hostmaster 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      msg "EXIT on error (hostmaster) due to GitHub downtime"
      msg "Please try to run this script again in a few minutes"
      msg "You may want to check https://www.githubstatus.com"
      msg "Bye"
      rm -rf /opt/tmp/test-*
      clean_pid_exit check_github_for_aegir_head_mode_b
    fi
    rm -rf /opt/tmp/test-*
  fi
  if [[ "${_X_VERSION}" =~ "-dev" ]] \
    || [[ "${_X_VERSION}" =~ "-lts" ]] \
    || [[ "${_X_VERSION}" =~ "-pro" ]]; then
    rm -rf /opt/tmp/test-*
    _GITHUB_TEST=$(git clone ${gitHub}/boa.git \
      /opt/tmp/test-boa 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      msg "EXIT on error (boa) due to GitHub downtime"
      msg "Please try to run this script again in a few minutes"
      msg "You may want to check https://www.githubstatus.com"
      msg "Bye"
      rm -rf /opt/tmp/test-*
      clean_pid_exit check_github_for_aegir_head_mode_c
    fi
    rm -rf /opt/tmp/test-*
  fi
}

check_db_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_db_src"
  fi
  if ! netcat -w 14 -z ${_DB_SRC} 80 ; then
    echo " "
    msg "EXIT on error due to ${_DB_SRC} downtime"
    msg "Please try to run this script again in a few minutes"
    msg "or better yet, hours"
    msg "Bye"
    clean_pid_exit check_db_src_a
  fi
}

check_ip_hostname() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: check_ip_hostname"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ ! -z "${_LOCAL_NETWORK_IP}" ]; then
      if [ -z "${_LOCAL_NETWORK_HN}" ]; then
        msg "FATAL ERROR: you must specify also _LOCAL_NETWORK_HN"
        clean_pid_exit check_ip_hostname_a
      else
        _DNS_SETUP_TEST=NO
        _SMTP_RELAY_TEST=NO
        _MY_OWNIP="${_LOCAL_NETWORK_IP}"
        _MY_HOSTN="${_LOCAL_NETWORK_HN}"
        _MY_FRONT="${_LOCAL_NETWORK_HN}"
      fi
    fi
    if [ "${_VMFAMILY}" = "AWS" ]; then
      _THIS_DB_HOST=localhost
      _LOC_DOM="${_MY_HOSTN}"
      if [ -z "${_MY_OWNIP}" ]; then
        find_correct_ip
        _MY_OWNIP="${_LOC_IP}"
      else
        _LOC_IP="${_MY_OWNIP}"
      fi
    fi
    if [ ! -z "${_MY_OWNIP}" ]; then
      if [ ! -z "${_MY_HOSTN}" ]; then
        _S_N=${_MY_HOSTN}
        _S_T=${_S_N#*.*}
        _S_Q=${_S_N%%${_S_T}}
        _S_E=${_S_Q%*.*}
        if [ ! -z "${_LOCAL_NETWORK_HN}" ]; then
          if [ "${_EASY_SETUP}" = "LOCAL" ]; then
            _DO_NOTHING=YES
          else
            sed -i "s/^${_MY_OWNIP}.*//g" /etc/hosts &> /dev/null
            echo "${_MY_OWNIP} ${_MY_HOSTN} chive.${_MY_HOSTN} sqlbuddy.${_MY_HOSTN} cgp.${_MY_HOSTN} ${_S_E}" >> /etc/hosts
          fi
        fi
        hostname -b ${_MY_HOSTN} ### force our custom FQDN/local hostname
        echo "${_MY_HOSTN}" > /etc/hostname
        echo "${_MY_HOSTN}" > /etc/mailname
      fi
      _THISHTIP="${_MY_OWNIP}"
      _THISHOST="${_MY_HOSTN}"
      _LOC_DOM="${_THISHOST}"
      find_correct_ip
      _THISRDIP="${_LOC_IP}"
      if [ "${_THISRDIP}" = "${_THISHTIP}" ]; then
        _FQDNTEST="TRUE"
        _LOC_DOM="${_MY_FRONT}"
        find_correct_ip
        _THEFRDIP="${_LOC_IP}"
        if [ "${_THEFRDIP}" = "${_THISHTIP}" ]; then
          _TESTHOST=$(uname -n 2>&1)
          _LOC_DOM="${_TESTHOST}"
          find_correct_ip
          _TESTRDIP="${_LOC_IP}"
          if [ "${_TESTRDIP}" = "${_THISHTIP}" ]; then
            _FQDNTEST="TRUE"
            hostname -b ${_TESTHOST}
          else
           _FQDNTEST="FALSE"
          fi
        else
          _FQDNTEST="FALSE"
        fi
      else
        _FQDNTEST="FALSE"
      fi
    else
      find_correct_ip
      _THISHTIP="${_LOC_IP}"
      _FQDNPROB=$(uname -n 2>&1)
      _FQDNTEST="FALSE"
      _THISHOST=$(uname -n 2>&1)
      if [ ! -z "${_FQDNPROB}" ]; then
        _THISHOST=$(uname -n 2>&1)
        _THISHOST=${_THISHOST//[^a-zA-Z0-9-.]/}
        _THISHOST=$(echo -n ${_THISHOST} | tr A-Z a-z 2>&1)
        _LOC_DOM="${_THISHOST}"
        find_correct_ip
        _THISRDIP="${_LOC_IP}"
        if [ "${_THISRDIP}" = "${_THISHTIP}" ]; then
          _FQDNTEST="TRUE"
          hostname -b ${_THISHOST}
        else
          _FQDNTEST="FALSE"
          _REVHOSTN=$(host ${_THISHTIP} | cut -d: -f2 | awk '{ print $5}' 2>&1)
          _REVHOSTN=$(echo -n ${_REVHOSTN} |sed 's/\(.*\)./\1/' 2>&1)
          _REVHOSTN=${_REVHOSTN//[^a-zA-Z0-9-.]/}
          _REVHOSTN=$(echo -n ${_REVHOSTN} | tr A-Z a-z 2>&1)
          _LOC_DOM="${_REVHOSTN}"
          find_correct_ip
          _REVHSTIP="${_LOC_IP}"
          if [ "${_REVHSTIP}" = "${_THISHTIP}" ]; then
            hostname -b ${_REVHOSTN}
            _THISHOST="${_REVHOSTN}"
            _FQDNTEST="TRUE"
          else
            _FQDNTEST="FALSE"
          fi
        fi
      else
        _REVHOSTN=$(host ${_THISHTIP} | cut -d: -f2 | awk '{ print $5}' 2>&1)
        _REVHOSTN=$(echo -n ${_REVHOSTN} |sed 's/\(.*\)./\1/' 2>&1)
        _REVHOSTN=${_REVHOSTN//[^a-zA-Z0-9-.]/}
        _REVHOSTN=$(echo -n ${_REVHOSTN} | tr A-Z a-z 2>&1)
        _LOC_DOM="${_REVHOSTN}"
        find_correct_ip
        _REVHSTIP="${_LOC_IP}"
        if [ "${_REVHSTIP}" = "${_THISHTIP}" ]; then
          hostname -b ${_REVHOSTN}
          _THISHOST="${_REVHOSTN}"
          _FQDNTEST="TRUE"
        else
         _FQDNTEST="FALSE"
        fi
      fi
    fi
    if [ ! -z "${_MY_FRONT}" ]; then
      _THIS_FRONT="${_MY_FRONT}"
    else
      _THIS_FRONT="${_THISHOST}"
    fi
    if [ "${_DNS_SETUP_TEST}" = "NO" ]; then
      _FQDNTEST=TRUE
    fi
    if [ "${_THISHOST}" = "localhost" ]; then
      msg "FATAL ERROR: you can't use localhost as your FQDN hostname"
      msg "Please try something like: aegir.local"
      clean_pid_exit check_ip_hostname_b
    fi
    if [ "${_FQDNTEST}" = "FALSE" ]; then
      echo " "
      msg "EXIT on error due to invalid DNS setup"
      if [ ! -z "${_MY_OWNIP}" ]; then
        cat <<EOF

    * Your custom _MY_OWNIP is set to "${_MY_OWNIP}"
    * Your custom _MY_HOSTN is set to "${_MY_HOSTN}"
    * Your custom _MY_FRONT is set to "${_MY_FRONT}"

    * Your _MY_HOSTN and/or _MY_FRONT doesn't match your _MY_OWNIP,
      or your hostname is not set properly yet.

    * Please make sure that below command returns your FQDN hostname "${_MY_HOSTN}":

    $ uname -n

EOF
      fi
      cat <<EOF

    Your server needs a working FQDN hostname pointing to its IP address.
    This means that you have to configure DNS for your hostname before
    trying to install BOA. Reverse DNS is not required, though.
    Make sure that DNS A record for ${_THISHOST} points to ${_THISHTIP} and
    then allow some time for DNS propagation before trying this again.
    Alternatively, disable this check with _DNS_SETUP_TEST=NO

EOF
      msg "EXIT on error due to invalid DNS setup"
      clean_pid_exit check_ip_hostname_c
    else
      echo "${_THISHOST}" > /etc/hostname
      echo "${_THISHOST}" > /etc/mailname
      hostname -b ${_THISHOST}
      msg "INFO: DNS test: OK"
    fi
    echo " "
    msg "INSTALL START -> checkpoint: "
    cat <<EOF

    * Your email address is ${_MY_EMAIL}
    * Your IP address is ${_THISHTIP}
    * Your hostname is ${_THISHOST}
EOF
    echo " "
    if prompt_yes_no "Do you want to proceed with the install?" ; then
      true
    else
      echo "Installation aborted by you"
      clean_pid_exit check_ip_hostname_d
    fi
  elif [ "${_STATUS}" = "UPGRADE" ]; then
    _THISHOST=$(cat /etc/hostname 2>&1)
    _THISHOST=$(echo -n ${_THISHOST} | tr -d "\n" 2>&1)
    _THISHOST=${_THISHOST//[^a-zA-Z0-9-.]/}
    _THISHOST=$(echo -n ${_THISHOST} | tr A-Z a-z 2>&1)
    if [ -e "/var/aegir/.drush/hostmaster.alias.drushrc.php" ]; then
      _THIS_FRONT=$(cat /var/aegir/.drush/hostmaster.alias.drushrc.php \
        | grep "uri'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    elif [ ! -z "${_MY_FRONT}" ]; then
      _THIS_FRONT="${_MY_FRONT}"
    else
      msg "EXIT on error due to not found or not specified Aegir domain"
      msg "Please specify your working Aegir domain as a value of _MY_FRONT"
      clean_pid_exit check_ip_hostname_e
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo " "
      msg "UPGRADE START -> checkpoint: "
      cat <<EOF

    * Your email address is ${_MY_EMAIL}
    * Your server hostname is ${_THISHOST}
    * Your Aegir control panel URL is https://${_THIS_FRONT}
EOF
      echo " "
    fi
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      if prompt_yes_no "Do you want to proceed with the upgrade?" ; then
        true
      else
        echo "Upgrade aborted by you"
        clean_pid_exit check_ip_hostname_f
      fi
    fi
  fi
}
