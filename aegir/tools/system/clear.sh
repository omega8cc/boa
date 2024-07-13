#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

aptYesUnth="-y --allow-unauthenticated"
tRee=lts
export tRee="${tRee}"

check_root() {
  if [ `whoami` = "root" ]; then
    if [ -e "/root/.barracuda.cnf" ]; then
      source /root/.barracuda.cnf
      _B_NICE=${_B_NICE//[^0-9]/}
    fi
    if [ -z "${_B_NICE}" ]; then
      _B_NICE=10
    fi
    chmod a+w /dev/null
    if [ ! -e "/dev/fd" ]; then
      if [ -e "/proc/self/fd" ]; then
        rm -rf /dev/fd
        ln -s /proc/self/fd /dev/fd
      fi
    fi
  else
    echo "ERROR: This script should be ran as a root user"
    exit 1
  fi
}
check_root

os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _THIS_RV=$(lsb_release -sc 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_THIS_RV}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
os_detection_minimal

apt_clean_update() {
  apt-get clean -qq 2> /dev/null
  rm -rf /var/lib/apt/lists/* &> /dev/null
  ${_APT_UPDATE} -qq 2> /dev/null
}

rm -f /var/run/clear_m.pid

_FIVE_MINUTES=$(date --date '5 minutes ago' +"%Y-%m-%d %H:%M:%S")
find /var/run/solr_jetty.pid -mtime +0 -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -rf {} \;
find /var/run/fmp_wait.pid -mtime +0 -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -rf {} \;
find /var/run/restarting_fmp_wait.pid  -mtime +0 -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -rf {} \;

_ONE_HOUR=$(date --date '1 hour ago' +"%Y-%m-%d %H:%M:%S")
find /var/run/mysql_restart_running.pid -mtime +0 -type f -not -newermt "${_ONE_HOUR}" -exec rm -rf {} \;
find /var/run/boa_wait.pid -mtime +0 -type f -not -newermt "${_ONE_HOUR}" -exec rm -rf {} \;
find /var/run/manage*users.pid  -mtime +0 -type f -not -newermt "${_ONE_HOUR}" -exec rm -rf {} \;

_THR_HOURS=$(date --date '3 hours ago' +"%Y-%m-%d %H:%M:%S")
find /var/run/boa_run.pid -mtime +0 -type f -not -newermt "${_THR_HOURS}" -exec rm -rf {} \;
find /var/run/*_backup.pid -mtime +0 -type f -not -newermt "${_THR_HOURS}" -exec rm -rf {} \;
find /var/run/daily-fix.pid -mtime +0 -type f -not -newermt "${_THR_HOURS}" -exec rm -rf {} \;

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

#
# Find the fastest mirror.
find_fast_mirror_early() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    apt_clean_update
    apt-get install netcat ${aptYesUnth} &> /dev/null
    wait
  fi
  ffMirr=$(which ffmirror 2>&1)
  if [ -x "${ffMirr}" ]; then
    ffList="/var/backups/boa-mirrors-2024-01.txt"
    mkdir -p /var/backups
    if [ ! -e "${ffList}" ]; then
      echo "de.files.aegir.cc"  > ${ffList}
      echo "ny.files.aegir.cc" >> ${ffList}
      echo "sg.files.aegir.cc" >> ${ffList}
    fi
    if [ -e "${ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
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
  urlDev="http://${_USE_MIR}/dev"
  urlHmr="http://${_USE_MIR}/versions/${tRee}/boa/aegir"
}

if_reinstall_curl() {
  _CURL_VRN=8.7.1
  isCurl=$(curl --version 2>&1)
  if [[ ! "${isCurl}" =~ "OpenSSL" ]] || [ -z "${isCurl}" ]; then
    echo "OOPS: cURL is broken! Re-installing.."
    rm -f /etc/apt/sources.list.d/openssl.list
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    echo "curl install" | dpkg --set-selections &> /dev/null
    apt_clean_update
    apt-get remove curl ${aptYesUnth} &> /dev/null
    apt-get install curl ${aptYesUnth} &> /dev/null
    ldconfig &> /dev/null
    if [ -f "/usr/bin/curl" ]; then
      isCurl=$(/usr/bin/curl --version 2>&1)
      if [[ ! "${isCurl}" =~ "OpenSSL" ]] || [ -z "${isCurl}" ]; then
        echo "OOPS: /usr/bin/curl is still broken, uninstalling.."
        apt-get remove curl ${aptYesUnth} &> /dev/null
      else
        echo "GOOD: /usr/bin/curl works"
      fi
    fi
    mkdir -p /var/opt
    rm -rf /var/opt/curl*
    cd /var/opt
    wget http://files.aegir.cc/dev/src/curl-${_CURL_VRN}.tar.gz &> /dev/null
    tar -xzf curl-${_CURL_VRN}.tar.gz &> /dev/null
    cd /var/opt/curl-${_CURL_VRN}
    sh ./configure --with-ssl --prefix=/usr/local &> /dev/null
    make -j $(nproc) --quiet &> /dev/null
    make --quiet install &> /dev/null
    if [ -f "/usr/local/bin/curl" ]; then
      isCurl=$(/usr/local/bin/curl --version 2>&1)
      if [[ ! "${isCurl}" =~ "OpenSSL" ]] || [ -z "${isCurl}" ]; then
        echo "ERRR: /usr/local/bin/curl is broken, moving to /usr/local/bin/curl--broken"
        rm -f /usr/local/bin/curl--broken
        mv -f /usr/local/bin/curl /usr/local/bin/curl--broken
      else
        echo "GOOD: /usr/local/bin/curl works"
      fi
    fi
  fi
}

check_dns_curl() {
  find_fast_mirror_early
  if_reinstall_curl
  _CURL_TEST=$(curl -L -k -s \
    --max-redirs 10 \
    --retry 3 \
    --retry-delay 10 \
    -I "http://${_USE_MIR}" 2> /dev/null)
  if [[ ! "${_CURL_TEST}" =~ "200 OK" ]]; then
    if [[ "${_CURL_TEST}" =~ "unknown option was passed in to libcurl" ]]; then
      echo "ERROR: cURL libs are out of sync! Re-installing again.."
      if_reinstall_curl
    else
      echo "ERROR: ${_USE_MIR} is not available, please try later"
      clean_pid_exit
    fi
  fi
}

if [ ! -e "/var/run/boa_run.pid" ]; then
  check_dns_curl
  if [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
  fi
  rm -f /tmp/*error*
  rm -f /var/backups/BOA.sh.txt.hourly*
  curl -L -k -s \
    --max-redirs 5 \
    --retry 5 \
    --retry-delay 5 \
    -A iCab "http://${_USE_MIR}/versions/${tRee}/boa/BOA.sh.txt" \
    -o /var/backups/BOA.sh.txt.hourly
  wait
  if [ -e "/var/backups/BOA.sh.txt.hourly" ]; then
    bash /var/backups/BOA.sh.txt.hourly
    wait
    rm -f /var/backups/BOA.sh.txt.hourly*
  else
    echo "Not available /var/backups/BOA.sh.txt.hourly"
  fi
  bash /opt/local/bin/autoupboa
fi

_OCT_NR=$(ls /data/disk | wc -l)
_OCT_NR=$(( _OCT_NR - 1 ))
for _OCT in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
  _SITES_NR=0
  if [ -e "${_OCT}/config/server_master/nginx/vhost.d" ]; then
    _SITES_NR=$(ls ${_OCT}/config/server_master/nginx/vhost.d | wc -l)
    if [ "${_SITES_NR}" -gt "0" ]; then
      if [ -z "${chckSts}" ]; then
        chckSts="SNR ${_OCT} ${_SITES_NR} "
      else
        chckSts="SNR ${_OCT} ${_SITES_NR} ${chckSts} "
      fi
    else
      _OCT_NR=$(( _OCT_NR - 1 ))
    fi
  fi
done
chckSts="OCT ${_OCT_NR} ${chckSts} "
_ALL_SITES_NR=$(ls /data/disk/*/config/server_master/nginx/vhost.d | wc -l)
_ALL_SITES_NR=$(( _ALL_SITES_NR - _OCT_NR ))
chckSts="SST ${_ALL_SITES_NR} ${chckSts}"
chckHst=$(hostname 2>&1)
chckIps=$(hostname -I 2>&1)
checkVn=$(/opt/local/bin/boa version | tr -d "\n" 2>&1)
if [[ "${checkVn}" =~ "===" ]] || [ -z "${checkVn}" ]; then
  if [ -e "/var/log/barracuda_log.txt" ]; then
    checkVn=$(tail --lines=1 /var/log/barracuda_log.txt | tr -d "\n" 2>&1)
  else
    checkVn="whereis barracuda_log.txt"
  fi
fi
crlHead="-I -k -s --retry 3 --retry-delay 3"
urlBpth="http://${_USE_MIR}/versions/${tRee}/boa/aegir/tools/bin"
curl ${crlHead} -A "${chckHst} ${chckIps} ${checkVn} ${chckSts}" "${urlBpth}/thinkdifferent" &> /dev/null
wait

renice ${_B_NICE} -p $$ &> /dev/null
service ssh restart &> /dev/null
touch /var/xdrago/log/clear.done.pid
exit 0
###EOF2024###
