#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=dev

_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_wgetGet="--max-redirect=3 --no-check-certificate -q --tries=9 --wait=9 --user-agent='iCab'"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf

    # Sanitize to allow only digits and minus sign
    export _B_NICE=${_B_NICE//[^0-9-]/}

    # Validate and set default if necessary
    if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
      _B_NICE=0
    fi

    # Clamp the value within -20 to 19
    if (( _B_NICE < -20 )); then
      _B_NICE=-20
    elif (( _B_NICE > 19 )); then
      _B_NICE=19
    fi

    renice ${_B_NICE} -p $$ &> /dev/null
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

_os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
  _OS_LIST="excalibur daedalus chimaera beowulf buster bullseye bookworm trixie"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}

_apt_clean_update() {
  _os_detection_minimal
  ${_APT_UPDATE} -qq 2> /dev/null
  _CALLER_SCRIPT="$(basename "${BASH_SOURCE[-1]}")"
  _CALLER_SCRIPT="${_CALLER_SCRIPT//[^a-zA-Z0-9._-]/_}"
  date +%s > "/run/_latest_apt_clean_update.${_CALLER_SCRIPT}.pid"
}

_FIVE_MINUTES=$(date --date '5 minutes ago' +"%Y-%m-%d %H:%M:%S")
find /run/fmp_wait.pid              -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null
find /run/restarting_fmp_wait.pid   -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null
find /run/boa_cron_wait.pid         -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null
find /run/boa*_auto_healing.pid     -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null

_ONE_HOUR=$(date --date '1 hour ago' +"%Y-%m-%d %H:%M:%S")
find /run/mysql_restart_running.pid  -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null
find /run/boa_wait.pid               -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null
find /run/manage*users.pid           -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null
find /run/speed_cleanup.pid          -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null

_THR_HOURS=$(date --date '3 hours ago' +"%Y-%m-%d %H:%M:%S")
find /run/boa_run.pid                -type f -not -newermt "${_THR_HOURS}" -exec rm -f {} \; 2>/dev/null
find /run/*_backup.pid               -type f -not -newermt "${_THR_HOURS}" -exec rm -f {} \; 2>/dev/null
find /run/daily-fix.pid              -type f -not -newermt "${_THR_HOURS}" -exec rm -f {} \; 2>/dev/null

[ -e "/root/.proxy.cnf" ] && exit 0

#
# Find the fastest mirror.
_find_fast_mirror_early() {
  _isNetc="$(which netcat)"
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    [ ! -e "/run/clear_m.pid" ] && _apt_clean_update
    apt-get install netcat-traditional ${_aptYesUnth} 2> /dev/null
    wait
  fi
  _ffMirr=/opt/local/bin/ffmirror
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2026-05.txt"
    [ -d "/var/backups" ] || mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "files.boa.io"  > ${_ffList}
      echo "files.o8.io" >> ${_ffList}
      echo "files.host8.biz" >> ${_ffList}
      if [ -e "/etc/csf/csf.allow" ]; then
        sed -i "s/.*aegir.*//g" /etc/csf/csf.allow
        csf -a 172.235.166.69  files.boa.io &> /dev/null
        csf -a 172.233.219.37  files.o8.io &> /dev/null
        csf -a 172.105.168.103 files.host8.biz &> /dev/null
        if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
          csf -ra &> /dev/null
          synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
        else
          csf -r &> /dev/null
        fi
      fi
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.boa.io"
      else
        _USE_MIR="files.boa.io"
      fi
    else
      _USE_MIR="files.boa.io"
    fi
  else
    _USE_MIR="files.boa.io"
  fi
  _urlDev="http://${_USE_MIR}/dev"
  _urlHmr="http://${_USE_MIR}/versions/${_tRee}/boa/aegir"
}

_if_reinstall_curl_src() {
  _CURL_VRN=8.20.0
  if ! command -v lsb_release &> /dev/null; then
    apt-get update -qq &> /dev/null
    apt-get install lsb-release ${_aptYesUnth} -qq &> /dev/null
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
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
    [ ! -e "/run/clear_m.pid" ] && _apt_clean_update
    # Check for libssl1.0-dev and remove conditionally
    if dpkg-query -W -f='${Status}' libssl1.0-dev 2>/dev/null | grep -q "install ok installed"; then
      apt-get remove libssl1.0-dev -y --purge --auto-remove -qq 2>/dev/null
    fi
    apt-get autoremove -y 2> /dev/null
    apt-get install libssl-dev ${_aptYesUnth} -qq 2> /dev/null
    apt-get build-dep curl -y 2> /dev/null
    if [ ! -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      apt-get install curl --reinstall ${_aptYesUnth} -qq 2> /dev/null
    fi
    if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      echo "INFO: Installing curl from sources..."
      mkdir -p /var/opt
      rm -rf /var/opt/curl*
      cd /var/opt
      wget ${_wgetGet} http://files.boa.io/dev/src/curl-${_CURL_VRN}.tar.gz &> /dev/null
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
    fi
  fi
}

if [ ! -e "/run/boa_run.pid" ]; then
  _check_dns_curl
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
    if [ "${_SITES_NR}" -gt 0 ]; then
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

_if_fix_locked_sshd() {
  _SSH_LOG="/var/log/auth.log"
  if [ `tail --lines=30 ${_SSH_LOG} \
    | grep --count "error: Bind to port 22"` -gt 0 ]; then
    pkill -9 -f /usr/sbin/sshd || true
    service ssh start
  fi
}
_if_fix_locked_sshd

#setprio &> /dev/null

if [ -e "/root/.remote_backups/schedule/backup_schedule.txt" ]; then
  if [ -e "/root/.remote_backups/paths/paths.txt" ]; then
    rm -f /root/.remote_backups/paths/*
    rm -f /root/.remote_backups/paths/.*
    [ -x "/usr/local/bin/dcysetup" ] && bash /usr/local/bin/dcysetup update &> /dev/null
  fi
  _CNT=$(pgrep -fc duplicity)
  if (( _CNT > 0 )); then
    echo "[$(date)] Active duplicity process detected, will try again later..." >> /var/log/mybackup_waiting_queue.log
  else
    [ -x "/usr/local/bin/dcysetup" ] && bash /usr/local/bin/dcysetup update &> /dev/null
    wait
    [ -x "/usr/local/bin/mybackup" ] && nohup /usr/local/bin/mybackup > /dev/null 2>&1 &
  fi
fi

touch /var/log/boa/clear.done.pid
exit 0
