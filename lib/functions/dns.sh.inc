#
# Fix DNS settings.
fix_dns_settings() {
  mkdir -p ${vBs}
  rm -f ${vBs}/resolv.conf.tmp
  if [ -e "/etc/resolv.conf" ]; then
    cp -a /etc/resolv.conf ${vBs}/resolv.conf.tmp
  fi
  if [ ! -e "${vBs}/resolv.conf.vanilla" ]; then
    for Pre in `ls -la ${vBs}/resolv.conf.pre-*`; do
      if [ -e "${Pre}" ] && [ -f "${Pre}" ] && [ ! -L "${Pre}" ]; then
        cp -a ${Pre} ${vBs}/resolv.conf.vanilla
      fi
    done
  fi
  if [ ! -e "${vBs}/resolv.conf.vanilla" ]; then
    rm -f /etc/resolv.conf
    cp -a ${vBs}/resolv.conf.tmp /etc/resolv.conf
    cp -a ${vBs}/resolv.conf.tmp ${vBs}/resolv.conf.vanilla
  fi
  sed -i "/^$/d" ${vBs}/resolv.conf.vanilla &> /dev/null
  rm -f /etc/resolv.conf
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
  echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  _BROKEN_DNS_TEST=$(host -a omega8.cc 8.8.8.8 -w 10 2>&1)
  if [[ "${_BROKEN_DNS_TEST}" =~ "no servers could be reached" ]] \
    && [ -e "${vBs}/resolv.conf.vanilla" ]; then
    touch /root/.use.local.nameservers.cnf
    rm -f /etc/resolv.conf
    cp -a ${vBs}/resolv.conf.vanilla /etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  else
    rm -f /etc/resolv.conf
    cp -a ${vBs}/resolv.conf.tmp /etc/resolv.conf
  fi
  if [ -e "/etc/pdnsd.conf" ]; then
    if [ -e "/root/.local.dns.IP.list" ]; then
      sed -i "s/.*127.0.0.1.*//g; s/ *$//g; /^$/d" /root/.local.dns.IP.list
      sed -i "s/.*Dynamic.*//g; s/ *$//g; /^$/d"   /root/.local.dns.IP.list
      _BROKEN_DNS_TEST=$(grep "\." /root/.local.dns.IP.list 2>&1)
      if [ -z "${_BROKEN_DNS_TEST}" ]; then
        echo "        label = \"google-servers\";" > /root/.local.dns.IP.list
        echo "        ip=8.8.8.8;" >> /root/.local.dns.IP.list
        echo "        ip=8.8.4.4;" >> /root/.local.dns.IP.list
      fi
    fi
    _CUSTOM_DNS_TEST=$(grep 8.8.8.8 /etc/pdnsd.conf 2>&1)
    _BROKEN_DNS_CONF=$(grep "ip=Dynamic" /etc/pdnsd.conf 2>&1)
    if [[ "${_CUSTOM_DNS_TEST}" =~ "8.8.8.8" ]] \
      || [[ "${_BROKEN_DNS_CONF}" =~ "Dynamic" ]]; then
      if [ -e "/root/.use.local.nameservers.cnf" ]; then
        echo "        label = \"google-servers\";" > /root/.local.dns.IP.list
        for _IP in `cat /etc/resolv.conf \
          | sed 's/.*127.0.0.1.*//g; s/.*Dynamic.*//g' \
          | cut -d ' ' -f2 \
          | sort \
          | uniq`;do echo "        ip=${_IP};" >> /root/.local.dns.IP.list;done
        sed -i "s/ip=8.8.*//g; s/ *$//g; /^$/d" /etc/pdnsd.conf
        sed -i "s/ip=127.*//g; s/ *$//g; /^$/d" /etc/pdnsd.conf
        sed -i "s/ip=Dyn.*//g; s/ *$//g; /^$/d" /etc/pdnsd.conf
        sed -i "s/.*127.0.0.1.*//g; s/ *$//g; /^$/d" /root/.local.dns.IP.list
        sed -i "s/.*Dynamic.*//g; s/ *$//g; /^$/d"   /root/.local.dns.IP.list
        _BROKEN_DNS_TEST=$(grep "\." /root/.local.dns.IP.list 2>&1)
        if [ -z "${_BROKEN_DNS_TEST}" ]; then
           echo "        ip=8.8.8.8;" >> /root/.local.dns.IP.list
           echo "        ip=8.8.4.4;" >> /root/.local.dns.IP.list
        fi
        sed -i '/        label = \"google-servers\";/ {r /root/.local.dns.IP.list
d;};' /etc/pdnsd.conf
        resolvconf -u                      &> /dev/null
        service pdnsd stop                 &> /dev/null
        rm -f /var/cache/pdnsd/pdnsd.cache &> /dev/null
        service pdnsd start                &> /dev/null
        service pdnsd stop                 &> /dev/null
        rm -f /var/cache/pdnsd/pdnsd.cache &> /dev/null
        service pdnsd start                &> /dev/null
      fi
    fi
  fi
}

#
# Check DNS settings.
check_dns_settings() {
  _BROKEN_DNS_TEST=$(host -a omega8.cc 8.8.8.8 -w 10 2>&1)
  if [[ "${_BROKEN_DNS_TEST}" =~ "no servers could be reached" ]] \
    || [ -e "/root/.use.local.nameservers.cnf" ]; then
    _USE_PROVIDER_DNS=YES
    fix_dns_settings
  else
    _USE_PROVIDER_DNS=NO
  fi
}

#
# Find the fastest mirror.
find_mirror() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    apt-get update -qq &> /dev/null
    apt-get install netcat -y --force-yes --reinstall &> /dev/null
    sleep 3
  fi
  ffMirr=$(which ffmirror 2>&1)
  if [ -x "${ffMirr}" ]; then
    ffList="/var/backups/boa-mirrors.txt"
    mkdir -p /var/backups
    echo "jp.files.aegir.cc"  > ${ffList}
    echo "nl.files.aegir.cc" >> ${ffList}
    echo "uk.files.aegir.cc" >> ${ffList}
    echo "us.files.aegir.cc" >> ${ffList}
    if [ -e "${ffList}" ]; then
      _CHECK_MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
      _USE_MIR="${_CHECK_MIRROR}"
    else
      _USE_MIR="files.aegir.cc"
    fi
  else
    _USE_MIR="files.aegir.cc"
  fi
  if ! netcat -w 5 -z ${_USE_MIR} 80 ; then
    echo "INFO: The mirror ${_USE_MIR} doesn't respond, let's try default"
    _USE_MIR="files.aegir.cc"
  fi
  urlDev="http://${_USE_MIR}/dev"
  urlHmr="http://${_USE_MIR}/versions/master/aegir"
  urlStb="http://${_USE_MIR}/versions/stable"
}

#
# Check repo status.
check_git_repos_status() {
  _GITHUB_WORKS=NO
  _GITORIOUS_WORKS=NO
  if [ "${_FORCE_GIT_MIRROR}" = "drupal" ]; then
    _FORCE_GIT_MIRROR=github
  fi
  if [ "${_FORCE_GIT_MIRROR}" = "github" ]; then
    msg "INFO: We will use forced GitHub repository without testing connection"
    _GITHUB_WORKS=YES
    _GITORIOUS_WORKS=NO
    sleep 1
  elif [ "${_FORCE_GIT_MIRROR}" = "gitorious" ]; then
    msg "INFO: We will use forced Gitorious mirror without testing connection"
    _GITHUB_WORKS=NO
    _GITORIOUS_WORKS=YES
    sleep 1
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Testing repository mirror servers availability..."
    fi
    sleep 1
    _GITHUB_WORKS=YES
    _GITORIOUS_WORKS=YES
    if ! netcat -w 14 -z github.com 9418 ; then
      _GITHUB_WORKS=NO
      msg "WARN: The GitHub master repository server doesn't respond..."
    elif ! netcat -w 14 -z code.aegir.cc 9418 ; then
      _GITORIOUS_WORKS=NO
      msg "WARN: The Gitorious mirror repository server doesn't respond..."
    fi
  fi
  if [ "$_GITHUB_WORKS" = "YES" ]; then
    _BOA_REPO_NAME="boa"
    _BOA_REPO_GIT_URL="${gitHub}"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: GitHub master repository will be used"
    fi
  elif [ "$_GITORIOUS_WORKS" = "YES" ]; then
    _BOA_REPO_NAME="barracuda-octopus"
    _BOA_REPO_GIT_URL="git://code.aegir.cc/aegir"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Gitorious mirror repository will be used"
    fi
  else
    cat <<EOF

    None of repository servers responded in 8 seconds,
    so we can't continue this installation.

    Please try again later or check if your firewall has port 9418 open.

    Bye.

EOF
    clean_pid_exit
  fi
  _BOA_REPO_GIT_URLX=${_BOA_REPO_GIT_URL//\//\\\/}
}

#
# Find correct IP.
find_correct_ip() {
  _LOC_IP=$(echo $(getent ahostsv4 $_LOC_DOM) \
    | cut -d: -f2 \
    | awk '{ print $1}' 2>&1)
}

#
# Validate server public IP.
validate_public_ip() {
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
      clean_pid_exit
    else
      _MY_OWNIP="${_LOCAL_NETWORK_IP}"
      _MY_HOSTN="${_LOCAL_NETWORK_HN}"
      _MY_FRONT="${_LOCAL_NETWORK_HN}"
      _THISHTIP="${_LOCAL_NETWORK_IP}"
    fi
  else
    _ETH_TEST=$(ifconfig 2>&1)
    if [[ "${_ETH_TEST}" =~ "venet0" ]]; then
      _IFCONFIG="venet0"
    elif [ -e "/proc/bean_counters" ]; then
      _IFCONFIG="venet0"
    else
      _IFCONFIG="eth0"
    fi
    if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
      if [ -z "${_MY_OWNIP}" ]; then
        _THISHTIP=$(ifconfig ${_IFCONFIG} \
          | grep 'inet addr:' \
          | cut -d: -f2 \
          | awk '{ print $1}' 2>&1)
        if [[ "${_THISHTIP}" =~ "127.0.0." ]]; then
          _THISHTIP=$(ifconfig ${_IFCONFIG}:0 \
            | grep 'inet addr:' \
            | cut -d: -f2 \
            | awk '{ print $1}' 2>&1)
        fi
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
  if [ "${_PURGE_ALL_THISHTIP}" = "YES" ]; then
    _PURGE_THISHTIP="0.0.0.0/0"
  else
    _ETH_TEST=$(ifconfig 2>&1)
    if [[ "${_ETH_TEST}" =~ "venet0" ]]; then
      _IFCONFIG="venet0"
    elif [ -e "/proc/bean_counters" ]; then
      _IFCONFIG="venet0"
    else
      _IFCONFIG="eth0"
    fi
    if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
      if [ -z "${_MY_OWNIP}" ]; then
        _PURGE_THISHTIP=$(ifconfig ${_IFCONFIG} \
          | grep 'inet addr:' \
          | cut -d: -f2 \
          | awk '{ print $1}' 2>&1)
        if [[ "$_PURGE_THISHTIP" =~ "127.0.0." ]]; then
          _PURGE_THISHTIP=$(ifconfig ${_IFCONFIG}:0 \
            | grep 'inet addr:' \
            | cut -d: -f2 \
            | awk '{ print $1}' 2>&1)
        fi
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
    if [ -z "$_PURGE_THISHTIP" ]; then
      _PURGE_THISHTIP="0.0.0.0/0"
    fi
  fi
}

#
# Validate local server IP.
validate_local_ip() {
  _LOCAL_THISHTIP=all
}
