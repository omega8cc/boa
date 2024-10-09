#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export _tRee=dev

_aptYesUnth="-y --allow-unauthenticated"

_check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    export _B_NICE=${_B_NICE//[^0-9]/}
    : "${_B_NICE:=10}"
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

_os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
_os_detection_minimal

_apt_clean_update() {
  #apt-get clean -qq 2> /dev/null
  #rm -rf /var/lib/apt/lists/* &> /dev/null
  ${_APT_UPDATE} -qq 2> /dev/null
}

rm -f /run/clear_m.pid

_FIVE_MINUTES=$(date --date '5 minutes ago' +"%Y-%m-%d %H:%M:%S")
find /run/solr_jetty.pid -mtime +0 -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -rf {} \; &> /dev/null
find /run/fmp_wait.pid -mtime +0 -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -rf {} \; &> /dev/null
find /run/restarting_fmp_wait.pid  -mtime +0 -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -rf {} \; &> /dev/null

_ONE_HOUR=$(date --date '1 hour ago' +"%Y-%m-%d %H:%M:%S")
find /run/mysql_restart_running.pid -mtime +0 -type f -not -newermt "${_ONE_HOUR}" -exec rm -rf {} \; &> /dev/null
find /run/boa_wait.pid -mtime +0 -type f -not -newermt "${_ONE_HOUR}" -exec rm -rf {} \; &> /dev/null
find /run/manage*users.pid  -mtime +0 -type f -not -newermt "${_ONE_HOUR}" -exec rm -rf {} \; &> /dev/null

_THR_HOURS=$(date --date '3 hours ago' +"%Y-%m-%d %H:%M:%S")
find /run/boa_run.pid -mtime +0 -type f -not -newermt "${_THR_HOURS}" -exec rm -rf {} \; &> /dev/null
find /run/*_backup.pid -mtime +0 -type f -not -newermt "${_THR_HOURS}" -exec rm -rf {} \; &> /dev/null
find /run/daily-fix.pid -mtime +0 -type f -not -newermt "${_THR_HOURS}" -exec rm -rf {} \; &> /dev/null

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

#
# Find the fastest mirror.
_find_fast_mirror_early() {
  _isNetc=$(which netcat 2>&1)
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    _apt_clean_update
    apt-get install netcat ${_aptYesUnth} 2> /dev/null
    apt-get install netcat-traditional ${_aptYesUnth} 2> /dev/null
    wait
  fi
  _ffMirr=$(which ffmirror 2>&1)
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2024-01.txt"
    mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "de.files.aegir.cc"  > ${_ffList}
      echo "ny.files.aegir.cc" >> ${_ffList}
      echo "sg.files.aegir.cc" >> ${_ffList}
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.aegir.cc"
      else
        _USE_MIR="files.aegir.cc"
      fi
    else
      _USE_MIR="files.aegir.cc"
    fi
  else
    _USE_MIR="files.aegir.cc"
  fi
  _urlDev="http://${_USE_MIR}/dev"
  _urlHmr="http://${_USE_MIR}/versions/${_tRee}/boa/aegir"
}

_if_reinstall_curl_src() {
  _CURL_VRN=8.10.1
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
    echo "OOPS: cURL is broken! Re-installing.."
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
      echo "INFO: Installing curl from sources..."
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
        echo "ERRR: /usr/local/bin/curl is broken"
      else
        echo "GOOD: /usr/local/bin/curl works"
      fi
    fi
  fi
}

_check_dns_curl() {
  _find_fast_mirror_early
  _if_reinstall_curl_src
  _CURL_TEST=$(curl -L -k -s \
    --max-redirs 10 \
    --retry 3 \
    --retry-delay 10 \
    -I "http://${_USE_MIR}" 2> /dev/null)
  if [[ ! "${_CURL_TEST}" =~ "200 OK" ]]; then
    if [[ "${_CURL_TEST}" =~ "unknown option was passed in to libcurl" ]]; then
      echo "ERROR: cURL libs are out of sync! Re-installing again.."
      _if_reinstall_curl_src
    else
      echo "ERROR: ${_USE_MIR} is not available, please try later"
      _clean_pid_exit _check_dns_curl_clear_a
    fi
  fi
}

if [ ! -e "/run/boa_run.pid" ]; then
  _check_dns_curl
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  rm -f /tmp/*error*
  wget -qO- http://${_USE_MIR}/versions/${_tRee}/boa/BOA.sh.txt | bash
  wait
  bash /opt/local/bin/autoupboa
  wait
fi

_OCT_NR=$(ls /data/disk | wc -l)
_OCT_NR=$(( _OCT_NR - 1 ))
for _OCT in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
  _SITES_NR=0
  if [ -e "${_OCT}/config/server_master/nginx/vhost.d" ]; then
    _SITES_NR=$(ls ${_OCT}/config/server_master/nginx/vhost.d | wc -l)
    if [ "${_SITES_NR}" -gt "0" ]; then
      if [ -z "${_chckSts}" ]; then
        _chckSts="SNR ${_OCT} ${_SITES_NR} "
      else
        _chckSts="SNR ${_OCT} ${_SITES_NR} ${_chckSts} "
      fi
    else
      _OCT_NR=$(( _OCT_NR - 1 ))
    fi
  fi
done
if [ -d "/data/u" ]; then
  _chckSts="OCT ${_OCT_NR} ${_chckSts} "
  _ALL_SITES_NR=$(ls /data/disk/*/config/server_master/nginx/vhost.d | wc -l)
  _ALL_SITES_NR=$(( _ALL_SITES_NR - _OCT_NR ))
  _chckSts="SST ${_ALL_SITES_NR} ${_chckSts}"
  _chckHst=$(hostname 2>&1)
  _chckIps=$(hostname -I 2>&1)
  _checkVn=$(/opt/local/bin/boa version | tr -d "\n" 2>&1)
  if [[ "${_checkVn}" =~ "===" ]] || [ -z "${_checkVn}" ]; then
    if [ -e "/var/log/barracuda_log.txt" ]; then
      _checkVn=$(tail --lines=1 /var/log/barracuda_log.txt | tr -d "\n" 2>&1)
    else
      _checkVn="whereis barracuda_log.txt"
    fi
  fi
  _crlHead="-I -k -s --retry 3 --retry-delay 3"
  _urlBpth="http://${_USE_MIR}/versions/${_tRee}/boa/aegir/tools/bin"
  curl ${_crlHead} -A "${_chckHst} ${_chckIps} ${_checkVn} ${_chckSts}" "${_urlBpth}/thinkdifferent" &> /dev/null
  wait
fi

renice ${_B_NICE} -p $$ &> /dev/null
service ssh restart
_if_fix_locked_sshd() {
  _SSH_LOG="/var/log/auth.log"
  if [ `tail --lines=100 ${_SSH_LOG} \
    | grep --count "error: Bind to port 22"` -gt "0" ]; then
    kill -9 $(ps aux | grep '[s]tartups' | awk '{print $2}')
    service ssh start
  fi
}
_if_fix_locked_sshd
touch /var/xdrago/log/clear.done.pid
exit 0
###EOF2024###
