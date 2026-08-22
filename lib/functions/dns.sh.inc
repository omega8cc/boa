
export _tRee=dev

_vBs="/var/backups"

#
# Fix DNS settings.
_fix_dns_settings() {
  [ ! -d "${_vBs}" ] && mkdir -p ${_vBs}
  rm -f ${_vBs}/resolv.conf.tmp
  if [ -x "/usr/sbin/unbound" ] && [ -e "/run/unbound/unbound.pid" ]; then
    if ! grep -q "nameserver 127.0.0.1" /etc/resolv.conf; then
      _FORCE_RESOLV_UPDATE=YES
    else
      _FORCE_RESOLV_UPDATE=NO
    fi
  fi
  if ! grep -q "BOA-DNS-Config" /etc/resolv.conf || [ "${_FORCE_RESOLV_UPDATE}" = "YES" ]; then
    echo "### BOA-DNS-Config ###" > ${_vBs}/resolv.conf.tmp
    if [ -x "/usr/sbin/unbound" ] && [ -e "/run/unbound/unbound.pid" ]; then
      echo "nameserver 127.0.0.1" >> ${_vBs}/resolv.conf.tmp
    fi
    echo "nameserver 1.1.1.1" >> ${_vBs}/resolv.conf.tmp
    echo "nameserver 8.8.8.8" >> ${_vBs}/resolv.conf.tmp
    echo "nameserver 9.9.9.9" >> ${_vBs}/resolv.conf.tmp
  fi
  if [ -e "${_vBs}/resolv.conf.tmp" ]; then
    chattr -i /etc/resolv.conf
    rm -f /etc/resolv.conf
    cp -a ${_vBs}/resolv.conf.tmp /etc/resolv.conf
    chmod 0644 /etc/resolv.conf
    cp -a ${_vBs}/resolv.conf.tmp ${_vBs}/resolv.conf.vanilla
  fi
  if [ -x "/usr/sbin/unbound-control" ]; then
    unbound-control reload &> /dev/null
  fi
}

#
# Check DNS settings.
_check_dns_settings() {
  if [ -L "/etc/resolv.conf" ]; then
    _fix_dns_settings
    return 1  # Exit the function but continue the script
  fi
  if [ -x "/usr/sbin/unbound" ] && [ -e "/run/unbound/unbound.pid" ]; then
    if ! grep -q "nameserver 127.0.0.1" /etc/resolv.conf; then
      _fix_dns_settings
      return 1  # Exit the function but continue the script
    fi
  fi
  if [ -e "/root/.use.default.nameservers.cnf" ]; then
    if [ -e "/root/.use.local.nameservers.cnf" ]; then
      rm -f /root/.use.local.nameservers.cnf
    fi
    _USE_DEFAULT_DNS=YES
    if ! grep -q "BOA-DNS-Config" /etc/resolv.conf; then
      _fix_dns_settings
      return 1  # Exit the function but continue the script
    fi
  fi
  if [ -e "/root/.use.local.nameservers.cnf" ]; then
    _USE_PROVIDER_DNS=YES
  else
    _REMOTE_DNS_TEST=$(host files.boa.io 1.1.1.1 -w 10 2>&1)
    if ! grep -q "BOA-DNS-Config" /etc/resolv.conf; then
      _fix_dns_settings
      return 1  # Exit the function but continue the script
    fi
  fi
  if [[ "${_REMOTE_DNS_TEST}" =~ "no servers could be reached" ]] \
    || [[ "${_REMOTE_DNS_TEST}" =~ "Host files.boa.io not found" ]] \
    || [ "${_USE_PROVIDER_DNS}" = "YES" ]; then
    _fix_dns_settings
  fi
}

#
# Check repo status.
_check_git_repos() {
  if [ "${_DL_MODE}" != "GIT" ]; then
    return 1  # Exit the function but continue the script
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_git_repos"
  fi
  if [ "${_DL_MODE}" = "GIT" ]; then
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
        _msg "INFO: We will use forced GitHub repository without testing connection"
      fi
      _GITHUB_WORKS=YES
      _GITLAB_WORKS=NO
      sleep 1
    elif [ "${_FORCE_GIT_MIRROR}" = "gitlab" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: We will use forced GitLab mirror without testing connection"
      fi
      _GITHUB_WORKS=NO
      _GITLAB_WORKS=YES
      sleep 1
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Testing repository mirror servers availability..."
      fi
      sleep 1
      _GITHUB_WORKS=YES
      _GITLAB_WORKS=YES
      if ! command nc -w 10 -z github.com 443 >/dev/null 2>&1 ; then
        _GITHUB_WORKS=NO
        _msg "WARN: The GitHub master repository server doesn't respond..."
      elif ! command nc -w 10 -z gitlab.com 443 >/dev/null 2>&1 ; then
        _GITLAB_WORKS=NO
        _msg "WARN: The GitLab mirror repository server doesn't respond..."
      fi
    fi
    if [ "${_GITHUB_WORKS}" = "YES" ]; then
      _BOA_REPO_NAME="boa"
      _BOA_REPO_GIT_URL="${_gitHub}"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: GitHub master repository will be used"
      fi
    elif [ "${_GITLAB_WORKS}" = "YES" ]; then
      _BOA_REPO_NAME="boa"
      _BOA_REPO_GIT_URL="${_gitLab}"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: GitLab mirror repository will be used"
      fi
    else
      cat <<EOF

      None of repository servers responded in 5 seconds,
      so we can't continue this installation.

      Please try again later or check if your firewall has port 443 open.

      Bye.

EOF
      _clean_pid_exit _check_git_repos_a
    fi
  fi
}

#
# Find correct IP.
_find_correct_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _find_correct_ip"
  fi
  if [ -e "/root/.found_correct_ipv4.cnf" ]; then
    _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>/dev/null | tr -d '\n')
    ### Self-heal a cache orphaned by a server migration: when the cached
    ### value is no longer any local address AND the box carries a real
    ### public IPv4 (so never on 1:1-NAT topologies, where the egress IP
    ### is legitimately not local -- incl. CGNAT 100.64/10), re-probe at
    ### most ONCE per process with hard timeouts and replace the cache
    ### only on a validated, different dotted quad. A failed probe never
    ### invalidates a working cache. The city memo is dropped on replace,
    ### else it stays pinned to the old address forever.
    if [ -z "${_ipHealDone}" ] && [ -n "${_LOC_IP}" ]; then
      _ipHealDone=YES
      _locV4s=$(ip -4 addr show scope global 2>/dev/null \
        | awk '/inet /{sub(/\/.*/,"",$2); print $2}')
      if [ -n "${_locV4s}" ] && ! echo "${_locV4s}" | grep -qx "${_LOC_IP}"; then
        _hasPubV4=NO
        for _v4 in ${_locV4s}; do
          case "${_v4}" in
            10.*|127.*|169.254.*|192.168.*) ;;
            172.1[6-9].*|172.2[0-9].*|172.3[01].*) ;;
            100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) ;;
            *) _hasPubV4=YES ;;
          esac
        done
        if [ "${_hasPubV4}" = "YES" ]; then
          _freshV4=$(curl -4 -s --connect-timeout 5 --max-time 15 \
            https://api.ipify.org 2>/dev/null | tr -d '\n')
          if [[ ! "${_freshV4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            _freshV4=$(curl -4 -s --connect-timeout 5 --max-time 15 \
              http://ipv4.icanhazip.com 2>/dev/null | tr -d '\n')
          fi
          if [[ "${_freshV4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
            && [ "${_freshV4}" != "${_LOC_IP}" ]; then
            _LOC_IP="${_freshV4}"
            echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
            rm -f /root/.found_correct_city.cnf
          fi
        fi
      fi
    fi
  else
    _LOC_IP=$(curl ${_crlGet} https://api.ipify.org | sed 's/[^0-9\.]//g')
    if [ -z "${_LOC_IP}" ]; then
      _LOC_IP=$(curl ${_crlGet} http://ipv4.icanhazip.com | sed 's/[^0-9\.]//g')
    fi
    ### Last-resort fallback removed in 2020 in favour of the remote
    ### probes, restored as a TAIL: when BOTH probes fail (mirror or
    ### network outage), resolve the box's own name locally -- callers
    ### assign it via _LOC_DOM right before calling. Single validated
    ### dotted quad only; anything else stays empty (fail-safe).
    if [ -z "${_LOC_IP}" ] && [ -n "${_LOC_DOM}" ]; then
      _LOC_IP=$(getent ahostsv4 "${_LOC_DOM}" 2>/dev/null | awk '{print $1; exit}')
      [[ "${_LOC_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || _LOC_IP=""
      ### Stock images map the FQDN to 127.0.1.1 in /etc/hosts; a loopback
      ### is never the box's public address, so leave empty instead.
      case "${_LOC_IP}" in 127.*) _LOC_IP="" ;; esac
    fi
    if [ ! -z "${_LOC_IP}" ]; then
      echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
    fi
  fi
  if [ -n "${_LOC_IP}" ] && grep -qE "${_LOC_IP}\s" /etc/hosts; then
    cp -af /etc/hosts /etc/.was.hosts
    sed -i "s/^${_LOC_IP}.*//g" /etc/hosts
    [ -x "/etc/init.d/unbound" ] && [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d
    [ -x "/etc/init.d/unbound" ] && service unbound restart &> /dev/null
  fi
}

#
# Validate server public IP.
_validate_public_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _validate_public_ip"
  fi
  if [ "${_VMFAMILY}" = "AWS" ]; then
    _LOC_DOM="${_MY_HOSTN}"
    if [ -z "${_MY_OWNIP}" ]; then
      _find_correct_ip
      _MY_OWNIP="${_LOC_IP}"
    else
      _LOC_IP="${_MY_OWNIP}"
    fi
  fi
  if [ ! -z "${_LOCAL_NETWORK_IP}" ]; then
    if [ -z "${_LOCAL_NETWORK_HN}" ]; then
      _msg "FATAL ERROR: you must specify also _LOCAL_NETWORK_HN"
      _clean_pid_exit _validate_public_ip_a
    else
      _MY_OWNIP="${_LOCAL_NETWORK_IP}"
      _MY_HOSTN="${_LOCAL_NETWORK_HN}"
      _MY_FRONT="${_LOCAL_NETWORK_HN}"
      _THISHTIP="${_LOCAL_NETWORK_IP}"
    fi
  else
    if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
      if [ -z "${_MY_OWNIP}" ]; then
        _find_correct_ip
        _THISHTIP="${_LOC_IP}"
      else
        _THISHTIP="${_MY_OWNIP}"
      fi
    else
      if [ -z "${_MY_OWNIP}" ] && [ ! -z "${_MY_HOSTN}" ]; then
        _LOC_DOM="${_MY_HOSTN}"
        _find_correct_ip
        _THISHTIP="${_LOC_IP}"
      else
        _THISHTIP="${_MY_OWNIP}"
      fi
    fi
  fi
}

#
# Validate server IP for xtras.
_validate_xtras_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _validate_xtras_ip"
  fi
  if [ "${_VMFAMILY}" = "AWS" ]; then
    _LOC_DOM="${_MY_HOSTN}"
    if [ -z "${_MY_OWNIP}" ]; then
      _find_correct_ip
      _MY_OWNIP="${_LOC_IP}"
    else
      _LOC_IP="${_MY_OWNIP}"
    fi
  fi
  _XTRAS_THISHTIP="*"
}

#
# Validate server IP for purge vhost.
_validate_purge_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _validate_purge_ip"
  fi
  if [ "${_PURGE_ALL_THISHTIP}" = "YES" ]; then
    _PURGE_THISHTIP="0.0.0.0/0"
  else
    if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
      if [ -z "${_MY_OWNIP}" ]; then
        _find_correct_ip
        _PURGE_THISHTIP="${_LOC_IP}"
      else
        _PURGE_THISHTIP="${_MY_OWNIP}"
      fi
    else
      if [ -z "${_MY_OWNIP}" ]; then
        if [ -e "/usr/bin/sipcalc" ]; then
          if [ -z "${_THISHTIP}" ]; then
            _LOC_DOM="${_THISHOST}"
            _find_correct_ip
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
_validate_local_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _validate_local_ip"
  fi
  _LOCAL_THISHTIP=all
}

#
# Wait for connection.
_wait_for_connection() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _wait_for_connection"
  fi
  echo " "
  _msg "I can not connect to github.com on port 443 at the moment"
  _msg "I will try again in 60 seconds, please wait..."
  _msg "Waiting for attempt $1..."
  sleep 60
}

#
# Check connection.
_check_connection() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_connection"
  fi
  if ! command nc -w 10 -z github.com 443 >/dev/null 2>&1 ; then
    _wait_for_connection "2/4"
    if ! command nc -w 10 -z github.com 443 >/dev/null 2>&1 ; then
      _wait_for_connection "3/4"
      if ! command nc -w 10 -z github.com 443 >/dev/null 2>&1 ; then
        _wait_for_connection "4/4"
        if ! command nc -w 10 -z github.com 443 >/dev/null 2>&1 ; then
          echo " "
          _msg "Sorry, I gave up."
          _msg "EXIT on error due to GitHub git server at 443 downtime"
          _msg "Please try to run this script again in a few minutes"
          _msg "You may want to check https://www.githubstatus.com"
          _msg "Also, make sure that the outgoing connections via port 443 work"
          _msg "Bye"
          _clean_pid_exit _check_connection_a
        fi
      fi
    fi
  fi
}

#
# Try the prebuilt boa-unbound .deb for the pinned version; fall back to
# sources on any failure. The payload carries the six /usr/sbin binaries
# only, overlaying files the distro unbound and unbound-anchor packages
# own (Replaces: in the package control) while both distro packages stay
# installed as the structure providers -- the boa-nginx overlay shape.
# Config, keys, the init script and the runtime dirs stay
# installer-managed on both paths, and the shared tail of
# _dns_unbound_install_upgrade (keys sync, pdnsd removal, service
# restart) runs unchanged after either path. Builders are modern-marker
# boxes by construction, so every published binary resolves its OpenSSL
# through a /usr/local/ssl3/lib64 RUNPATH; a box without the modern
# OpenSSL tree is refused up front and keeps the source path. With
# Replaces: in play a purge removes the daemon binary itself and the
# source rebuild that follows can fail silently (_mrun), so the previous
# binaries are snapshotted first and restored on any failure -- the
# failure envelope stays identical to the source path's.
_install_unbound_deb() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_unbound_deb"
  fi
  _UNBOUND_DEB_INSTALLED=NO
  if [ -z "${_UNBOUND_VRN}" ]; then
    return 1
  fi
  if [ ! -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Modern OpenSSL tree missing; skipping prebuilt boa-unbound"
    fi
    return 1
  fi
  mkdir -p /var/opt/unbound-pre-deb
  for _unbDebBin in unbound unbound-anchor unbound-checkconf \
    unbound-control unbound-control-setup unbound-host; do
    if [ -e "/usr/sbin/${_unbDebBin}" ]; then
      cp -af /usr/sbin/${_unbDebBin} /var/opt/unbound-pre-deb/
    fi
    # An attacker-set immutable flag would make dpkg's unpack fail silently.
    chattr -i /usr/sbin/${_unbDebBin} &> /dev/null
  done
  if ! _install_boa_deb "boa-unbound" "${_UNBOUND_VRN}"; then
    for _unbDebBin in unbound unbound-anchor unbound-checkconf \
      unbound-control unbound-control-setup unbound-host; do
      if [ ! -x "/usr/sbin/${_unbDebBin}" ] \
        && [ -x "/var/opt/unbound-pre-deb/${_unbDebBin}" ]; then
        cp -af /var/opt/unbound-pre-deb/${_unbDebBin} /usr/sbin/${_unbDebBin}
      fi
    done
    rm -rf /var/opt/unbound-pre-deb
    return 1
  fi
  # dpkg unpacks the payload with the builder's hardened 0750 mode but
  # archive ownership root:root; normalize to the canonical root:users
  # shape immediately rather than waiting for the end-of-run hardening
  # pass, matching the boa-nginx/boa-php deb precedent.
  for _unbDebBin in unbound unbound-anchor unbound-checkconf \
    unbound-control unbound-control-setup unbound-host; do
    chown root:users /usr/sbin/${_unbDebBin} &> /dev/null
    chmod 750 /usr/sbin/${_unbDebBin} &> /dev/null
  done
  _UNBOUND_DEB_ITD=$(/usr/sbin/unbound -V 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' \
    | sed "s/Configure//gi" 2>&1)
  # The same libevent linkage _dns_unbound_install_upgrade reads as its
  # fix trigger, plus full loader resolution across the ELF payload
  # (unbound-control-setup is a shell script) -- a payload that would
  # immediately re-trigger the fix path must not pass.
  _UNBOUND_DEB_LIBVT=$(ldd /usr/sbin/unbound 2>&1 | grep libevent 2>&1)
  _UNBOUND_DEB_MISSING=$(ldd /usr/sbin/unbound /usr/sbin/unbound-anchor \
    /usr/sbin/unbound-checkconf /usr/sbin/unbound-control \
    /usr/sbin/unbound-host 2>&1 | grep "not found" 2>&1)
  if [ -x "/usr/sbin/unbound" ] \
    && [ -x "/usr/sbin/unbound-anchor" ] \
    && [ -x "/usr/sbin/unbound-checkconf" ] \
    && [ -x "/usr/sbin/unbound-control" ] \
    && [ -x "/usr/sbin/unbound-control-setup" ] \
    && [ -x "/usr/sbin/unbound-host" ] \
    && [ "${_UNBOUND_DEB_ITD}" = "${_UNBOUND_VRN}" ] \
    && [[ "${_UNBOUND_DEB_LIBVT}" =~ "libevent" ]] \
    && [ -z "${_UNBOUND_DEB_MISSING}" ]; then
    rm -rf /var/opt/unbound-pre-deb
    _UNBOUND_DEB_INSTALLED=YES
    _msg "INFO: Unbound ${_UNBOUND_VRN} installed from prebuilt package"
    return 0
  fi
  # The purge removes the binaries boa-unbound now owns; restore the
  # snapshot so the box keeps a working resolver even if the source
  # rebuild that runs next fails silently.
  dpkg --purge "boa-unbound" &> /dev/null
  for _unbDebBin in unbound unbound-anchor unbound-checkconf \
    unbound-control unbound-control-setup unbound-host; do
    if [ ! -x "/usr/sbin/${_unbDebBin}" ] \
      && [ -x "/var/opt/unbound-pre-deb/${_unbDebBin}" ]; then
      cp -af /var/opt/unbound-pre-deb/${_unbDebBin} /usr/sbin/${_unbDebBin}
    fi
  done
  rm -rf /var/opt/unbound-pre-deb
  _msg "NOTE: Prebuilt boa-unbound failed health check; building from sources"
  return 1
}

#
# Install Unbound from sources.
_install_unbound_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_unbound_src"
  fi
  _msg "INFO: Installing Unbound ${_UNBOUND_VRN}..."
  ldconfig 2> /dev/null
  cd /var/opt
  rm -rf unbound*
  # Prebuilt package path (_USE_PREBUILT_PKGS): replaces only the source
  # fetch + compile; the shared tail in _dns_unbound_install_upgrade runs
  # unchanged for both paths.
  _UNBOUND_DEB_INSTALLED=NO
  if [ "${_USE_PREBUILT_PKGS}" = "YES" ]; then
    _install_unbound_deb
  fi
  if [ "${_UNBOUND_DEB_INSTALLED}" = "YES" ]; then
    return 0
  fi
  _get_dev_src "unbound-${_UNBOUND_VRN}.tar.gz"
  cd unbound-${_UNBOUND_VRN}
  if [ -e "/usr/local/ssl3/" ]; then
    _mrun "bash ./configure \
      --prefix=/usr \
      --with-libevent \
      --with-pidfile=/run/unbound/unbound.pid \
      --with-ssl=/usr/local/ssl3"
  elif [ -e "/usr/local/ssl/" ]; then
    _mrun "bash ./configure \
      --prefix=/usr \
      --with-libevent \
      --with-pidfile=/run/unbound/unbound.pid \
      --with-ssl=/usr/local/ssl"
  fi
  _mrun "make -j $(nproc) --quiet"
  _mrun "make --quiet install"
}

#
# DNS cache Unbound.
_dns_unbound_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _dns_unbound_install_upgrade"
  fi
  _isUnbnd="$(which unbound)"
  _isUnbndErr=$(${_isUnbnd} -V 2>&1)
  [ -x "${_isUnbnd}" ] && _isUnbLibvt=$(ldd ${_isUnbnd} | grep libevent 2>&1)
  if [[ "${_isUnbndErr}" =~ "cannot open shared object file" ]] \
    || [[ "${_isUnbndErr}" =~ "No such file or directory" ]] \
    || [[ ! "${_isUnbLibvt}" =~ "libevent" ]] \
    || [ -z "${_isUnbndErr}" ]; then
    _isUnbndFix=YES
  else
    _isUnbndFix=NO
    [ -x "/etc/init.d/unbound" ] && [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d
    _isUnbndBr=$(service unbound restart 2>&1)
    [[ "${_isUnbndBr}" =~ "fatal error" ]] && _isUnbndFix=YES
    [[ "${_isUnbndBr}" =~ "not found" ]] && _isUnbndFix=YES
    [[ "${_isUnbndBr}" =~ "address already in use" ]] && _killPdnsd=YES
  fi
  if [ ! -x "${_isUnbnd}" ] \
    || [ -z "${_isUnbnd}" ] \
    || [ "${_isUnbndFix}" = "YES" ] \
    || [ -e "/usr/etc/unbound/unbound.pid" ] \
    || [ -e "/etc/unbound/unbound.conf.d/remote-control.conf" ] \
    || [ -e "/etc/resolvconf/run/interface/lo.unbound" ] \
    || [ -e "/lib/resolvconf" ] \
    || [ ! -e "/run/unbound" ] \
    || [ ! -x "/usr/libexec/unbound-helper" ] \
    || [ ! -x "/etc/init.d/unbound" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Installing DNS cache Unbound server from packages..."
    fi
    if [ -e "/etc/resolv.conf" ]; then
      cp -af /etc/resolv.conf ${_vBs}/resolv.conf.pre-${_xSrl}-${_X_VERSION}-${_NOW}
    fi
    _check_dns_settings
    _fix_dns_settings
    if [ "${_USE_PROVIDER_DNS}" != "YES" ]; then
      chattr -i /etc/resolv.conf
      rm -f /etc/resolv.conf
      echo "### BOA-DNS-Config ###" > /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 9.9.9.9" >> /etc/resolv.conf
      chmod 0644 /etc/resolv.conf
    fi
    _apt_clean_update
    [ -e "/usr/etc/unbound/unbound.pid" ] && _isUnbndFix=YES
    if [ "${_isUnbndFix}" = "YES" ]; then
      ###
      for _PKG in unbound unbound-anchor unbound-host dns-root-data; do
        if _pkg_installed "${_PKG}"; then
          _mrun "apt-get remove ${_PKG} -y --purge --auto-remove -qq"
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "PCKG: ${_PKG} removed as requested."
          fi
        fi
      done
      ###
      rm -rf /etc/unbound
      rm -rf /usr/etc/unbound
    fi
    if dpkg-query -W -f='${Status}' resolvconf 2>/dev/null | grep -q "install ok installed"; then
      _mrun "apt-get remove resolvconf -y --purge --auto-remove -qq"
    fi
    rm -rf /lib/init/rw/resolvconf
    rm -rf /run/resolvconf
    rm -rf /etc/resolvconf
    rm -rf /lib/resolvconf
    if dpkg-query -W -f='${Status}' resolvconf 2>/dev/null | grep -q "install ok installed"; then
      _mrun "apt-get remove resolvconf -y --purge --auto-remove -qq"
    fi
    if [ "${_USE_PROVIDER_DNS}" != "YES" ]; then
      chattr -i /etc/resolv.conf
      rm -f /etc/resolv.conf
      echo "### BOA-DNS-Config ###" > /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 9.9.9.9" >> /etc/resolv.conf
      chmod 0644 /etc/resolv.conf
    fi
    if [ -x "/usr/sbin/aa-teardown" ]; then
      aa-teardown &> /dev/null
    fi
    # With Replaces: in play the boa-unbound overlay package owns the
    # /usr/sbin binaries, and dpkg refuses to hand those paths back to
    # the distro packages (${_INSTAPP} carries no --force-overwrite and
    # _mrun would swallow the refusal silently) -- so a repair pass that
    # needs to reinstall any of them must drop the overlay record first.
    # The overlay binaries go with it, which is safe here: the distro
    # set is reinstalled right below (restoring /etc/unbound), and
    # _install_unbound_src reinstates the pinned version (deb or source)
    # at the end of this run either way -- the same recovery envelope
    # the source-only path always had.
    if dpkg-query -W -f='${Status}' "boa-unbound" 2>/dev/null \
      | grep -q "install ok installed"; then
      for _PKG in unbound unbound-anchor unbound-host dns-root-data; do
        if ! _pkg_installed "${_PKG}"; then
          dpkg --purge "boa-unbound" &> /dev/null
          break
        fi
      done
    fi
    for _PKG in libevent-dev unbound unbound-anchor unbound-host dns-root-data; do
      if ! _pkg_installed "${_PKG}"; then
        _mrun "${_INSTAPP} ${_PKG}"
      fi
    done
    grep -q '^RESOLVCONF=' /etc/default/unbound \
      && sed -i 's/^RESOLVCONF=.*/RESOLVCONF=false/' /etc/default/unbound \
      || echo 'RESOLVCONF=false' >> /etc/default/unbound
    if [ -x "/usr/sbin/aa-teardown" ]; then
      aa-teardown &> /dev/null
    fi
    ###
    [ -d /run/unbound ] || mkdir -p /run/unbound
    [ -d /run/unbound ] && chown -R unbound:unbound /run/unbound
    [ -d /var/log/unbound ] || mkdir -p /var/log/unbound/
    touch /var/log/unbound/unbound.log
    chown -R unbound:unbound /var/log/unbound
    [ -d /var/lib/unbound ] || mkdir -p /var/lib/unbound/
    [ -d /usr/share/dns ] && cp -a /usr/share/dns/* /var/lib/unbound/
    [ -d /var/lib/unbound ] && chown -R unbound:unbound /var/lib/unbound
    [ ! -e "/etc/unbound/unbound_control.key" ] && _mrun "unbound-control-setup"
    cp -af ${_locCnf}/dns/unbound /etc/init.d/unbound
    chmod 755 /etc/init.d/unbound
    _mrun "update-rc.d unbound defaults"
    ###
    if [ -e "/etc/apparmor.d" ] && [ ! -e "/etc/apparmor.d/usr.sbin.unbound" ]; then
      cat ${_locCnf}/apparmor/usr.sbin.unbound > /etc/apparmor.d/usr.sbin.unbound
      chmod 644 /etc/apparmor.d/usr.sbin.unbound
    fi
    ###
    [ ! -d "/usr/libexec" ] && mkdir -p /usr/libexec
    [ ! -e "/usr/libexec/unbound-helper" ] && cp -a ${_locCnf}/dns/unbound-helper /usr/libexec/
    [ -e "/usr/libexec/unbound-helper" ] && chmod 755 /usr/libexec/unbound-helper
    cat ${_locCnf}/dns/unbound.conf > /etc/unbound/unbound.conf.d/unbound.conf
    [ -x "/etc/init.d/unbound" ] && [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d
    _mrun "pkill -u unbound -x unbound"
    _mrun "service unbound restart"
  fi
  _check_dns_settings
  if [ ! -f "/etc/resolv.conf" ]; then
    chattr -i /etc/resolv.conf
    rm -f /etc/resolv.conf
    echo "### BOA-DNS-Config ###" > /etc/resolv.conf
    echo "nameserver 127.0.0.1" >> /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 9.9.9.9" >> /etc/resolv.conf
    chmod 0644 /etc/resolv.conf
    [ -x "/etc/init.d/unbound" ] && [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d
    _mrun "pkill -u unbound -x unbound"
    _mrun "service unbound restart"
  fi
  if [ -e "/etc/NetworkManager/NetworkManager.conf" ]; then
    sed -i "s/^dns=.*/dns=unbound/g" \
      /etc/NetworkManager/NetworkManager.conf &> /dev/null
    _mrun "service network-manager restart"
  fi
  if [ -x "${_isUnbnd}" ] && [ "${_isUnbndFix}" = "NO" ]; then
    _UNBOUND_V_ITD=$(${_isUnbnd} -V 2>&1 \
      | tr -d "\n" \
      | cut -d" " -f2 \
      | awk '{ print $1}' \
      | sed "s/Configure//gi" 2>&1)
    if [ "${_UNBOUND_V_ITD}" = "${_UNBOUND_VRN}" ]; then
      _UNBOUND_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Unbound version ${_UNBOUND_V_ITD}, OK"
      fi
    else
      _UNBOUND_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Unbound version ${_UNBOUND_V_ITD}, upgrade required"
      fi
    fi
  else
    _UNBOUND_INSTALL_REQUIRED=YES
  fi
  [ -e "/usr/etc/unbound/unbound.pid" ] && _UNBOUND_INSTALL_REQUIRED=YES
  [ -e "/usr/etc/unbound/unbound.pid" ] && rm -f /usr/etc/unbound/unbound.pid
  if [ "${_UNBOUND_INSTALL_REQUIRED}" = "YES" ]; then
    _install_unbound_src
  fi
  [ -e "/usr/etc/unbound" ] && cp -af /etc/unbound/*.key /usr/etc/unbound/
  [ -e "/usr/etc/unbound" ] && cp -af /etc/unbound/*.pem /usr/etc/unbound/
  [ -e "/usr/etc/unbound" ] && cp -af /etc/unbound/unbound.conf.d/unbound.conf /usr/etc/unbound/
  _isUnbnd="$(which unbound)"
  _isUnbndErr=$(${_isUnbnd} -V 2>&1)
  if [[ "${_isUnbndErr}" =~ "cannot open shared object file" ]] \
    || [[ "${_isUnbndErr}" =~ "No such file or directory" ]] \
    || [ -z "${_isUnbndErr}" ]; then
    _isUnbndFix=YES
  else
    _isUnbndFix=NO
  fi
  [ -e "/etc/unbound/unbound.conf.d/remote-control.conf" ] && rm -f /etc/unbound/unbound.conf.d/remote-control.conf
  if [ "${_isUnbndFix}" = "NO" ] || [ "${_killPdnsd}" = "YES" ]; then
    _isPdnsd="$(which pdnsd)"
    if [ -x "${_isPdnsd}" ]; then
      _mrun "service pdnsd stop"
      _mrun "update-rc.d -f pdnsd remove"
      _mrun "killall -9 pdnsd"
      mv -f ${_isPdnsd} /var/backups
    fi
    _mrun "pkill -u unbound -x unbound"
    _mrun "service unbound restart"
  fi
  [ -e "/etc/default/unbound" ] && _isNxdEtc=$(grep "always_nxdomain" /etc/default/unbound 2>&1)
  [ -e "/etc/init.d/unbound" ] && _isIntUnb=$(grep "apply_ci_nomail" /etc/init.d/unbound 2>&1)
  if [[ "${_isNxdEtc}" =~ "always_nxdomain" ]] \
    && [[ ! "${_isIntUnb}" =~ "apply_ci_nomail" ]]; then
    cp -af ${_locCnf}/dns/unbound /etc/init.d/unbound
    chmod 755 /etc/init.d/unbound
    _mrun "update-rc.d unbound defaults"
    _mrun "service unbound reload"
  fi
}

_check_github_for_aegir_head_mode() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_github_for_aegir_head_mode"
  fi
  if [ "${_SYSTEM_UP_ONLY}" = "NO" ] \
    && [ "${_DL_MODE}" = "GIT" ]; then
    rm -rf /opt/tmp/test-*
    _check_connection
    _GITHUB_TEST=$(git clone ${_gitHub}/provision.git \
      /opt/tmp/test-provision 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      _msg "EXIT on error (provision) due to GitHub downtime"
      _msg "Please try to run this script again in a few minutes"
      _msg "You may want to check https://www.githubstatus.com"
      _msg "Bye"
      rm -rf /opt/tmp/test-*
      _clean_pid_exit _check_github_for_aegir_head_mode_a
    fi
  fi
}

_check_db_src() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_db_src"
  fi
  if ! command nc -w 10 -z repo.percona.com 443 >/dev/null 2>&1 ; then
    echo " "
    _msg "EXIT on error due to repo.percona.com downtime"
    _msg "Please try to run this script again in a few minutes"
    _msg "or better yet, hours"
    _msg "Bye"
    _clean_pid_exit _check_db_src_a
  fi
}

_check_ip_hostname() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _check_ip_hostname"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ ! -z "${_LOCAL_NETWORK_IP}" ]; then
      if [ -z "${_LOCAL_NETWORK_HN}" ]; then
        _msg "FATAL ERROR: you must specify also _LOCAL_NETWORK_HN"
        _clean_pid_exit _check_ip_hostname_a
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
        _find_correct_ip
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
            if [ -n "${_MY_OWNIP}" ] && grep -qE "${_MY_OWNIP}\s" /etc/hosts; then
              sed -i "s/^${_MY_OWNIP}.*//g" /etc/hosts &> /dev/null
            fi
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
      _find_correct_ip
      _THISRDIP="${_LOC_IP}"
      if [ "${_THISRDIP}" = "${_THISHTIP}" ]; then
        _FQDNTEST="TRUE"
        _LOC_DOM="${_MY_FRONT}"
        _find_correct_ip
        _THEFRDIP="${_LOC_IP}"
        if [ "${_THEFRDIP}" = "${_THISHTIP}" ]; then
          _TESTHOST="$(hostname -f 2>/dev/null || uname -n)"
          _LOC_DOM="${_TESTHOST}"
          _find_correct_ip
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
      _find_correct_ip
      _THISHTIP="${_LOC_IP}"
      _FQDNPROB="$(hostname -f 2>/dev/null || uname -n)"
      _FQDNTEST="FALSE"
      _THISHOST="$(hostname -f 2>/dev/null || uname -n)"
      if [ ! -z "${_FQDNPROB}" ]; then
        _THISHOST="$(hostname -f 2>/dev/null || uname -n)"
        _THISHOST=${_THISHOST//[^a-zA-Z0-9-.]/}
        _THISHOST=$(echo -n ${_THISHOST} | tr A-Z a-z 2>&1)
        _LOC_DOM="${_THISHOST}"
        _find_correct_ip
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
          _find_correct_ip
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
        _find_correct_ip
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
      _msg "FATAL ERROR: you can't use localhost as your FQDN hostname"
      _msg "Please try something like: aegir.local"
      _clean_pid_exit _check_ip_hostname_b
    fi
    if [ "${_FQDNTEST}" = "FALSE" ]; then
      echo " "
      _msg "EXIT on error due to invalid DNS setup"
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
      _msg "EXIT on error due to invalid DNS setup"
      _clean_pid_exit _check_ip_hostname_c
    else
      echo "${_THISHOST}" > /etc/hostname
      echo "${_THISHOST}" > /etc/mailname
      hostname -b ${_THISHOST}
      _msg "INFO: DNS test: OK"
    fi
    echo " "
    : "${_DISPLAY_CHECKPOINT:=YES}"
    if [ "${_DISPLAY_CHECKPOINT}" = "YES" ]; then
      if [ -z "${_THISHTIP}" ]; then
        _find_correct_ip
        _THISHTIP="${_LOC_IP}"
      fi
      _find_server_city
      [ -n "${_LOC_CITY}" ] && _LOC_CITY="$(echo "${_LOC_CITY}" | tr '+' ' ')"
      [ -z "${_LOC_CITY}" ] && _LOC_CITY="Cicely"
      _VENDOR="$(dmidecode -s system-manufacturer 2>&1)"
      [ -z "${_VENDOR}" ] && _VENDOR="Maurice Minnifield"
      _msg "INSTALL START -> checkpoint: "
      cat <<EOF

      * Your sysadmin Email is ${_MY_EMAIL}
      * Your server City is ${_LOC_CITY}
      * Your server Vendor is ${_VENDOR}
      * Your server System is ${_VIRT_IS}
      * Your server IP is ${_THISHTIP}
      * Your server Hostname is ${_THISHOST}
EOF
      echo " "
    fi
    if _prompt_yes_no "Do you want to proceed with the install?" ; then
      true
    else
      echo "Installation aborted by you"
      _clean_pid_exit _check_ip_hostname_d
    fi
  elif [ "${_STATUS}" = "UPGRADE" ]; then
    _THISHOST="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    _THISHOST=${_THISHOST//[^a-zA-Z0-9-.]/}
    _THISHOST=$(echo -n ${_THISHOST} | tr A-Z a-z 2>&1)
    if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      _THIS_FRONT=$(cat /var/aegir/.drush/hm.alias.drushrc.php \
        | grep -E "^[[:space:]]*'uri'[[:space:]]*=>" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    elif [ ! -z "${_MY_FRONT}" ]; then
      _THIS_FRONT="${_MY_FRONT}"
    else
      _msg "EXIT on error due to not found or not specified Ægir domain"
      _msg "Please specify your working Ægir domain as a value of _MY_FRONT"
      _clean_pid_exit _check_ip_hostname_e
    fi
    : "${_DISPLAY_CHECKPOINT:=YES}"
    if [ "${_DISPLAY_CHECKPOINT}" = "YES" ]; then
      if [ -z "${_THISHTIP}" ]; then
        _find_correct_ip
        _THISHTIP="${_LOC_IP}"
      fi
      _find_server_city
      [ -n "${_LOC_CITY}" ] && _LOC_CITY="$(echo "${_LOC_CITY}" | tr '+' ' ')"
      [ -z "${_LOC_CITY}" ] && _LOC_CITY="Cicely"
      _VENDOR="$(dmidecode -s system-manufacturer 2>&1)"
      [ -z "${_VENDOR}" ] && _VENDOR="Maurice Minnifield"
      echo " "
      _msg "UPGRADE START -> checkpoint: "
      cat <<EOF

    * Your sysadmin Email is ${_MY_EMAIL}
    * Your server City is ${_LOC_CITY}
    * Your server Vendor is ${_VENDOR}
    * Your server System is ${_VIRT_IS}
    * Your server IP is ${_THISHTIP}
    * Your server Hostname is ${_THISHOST}
EOF
      echo " "
    fi
    if _prompt_yes_no "Do you want to proceed with the upgrade?" ; then
      true
    else
      echo "Upgrade aborted by you"
      _clean_pid_exit _check_ip_hostname_f
    fi
  fi
}
