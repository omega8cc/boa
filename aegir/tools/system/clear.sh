#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

aptYesUnth="-y --allow-unauthenticated"

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
find /var/run/boa*.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/manage*users.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/daily-fix.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/clear_m.pid -mtime +0 -exec rm -rf {} \; &> /dev/null

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

#
# Find the fastest mirror.
find_fast_mirror() {
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
    ffList="/var/backups/boa-mirrors-2023-01.txt"
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
  urlHmr="http://${_USE_MIR}/versions/dev/boa/aegir"
}

if [ ! -e "/var/run/boa_run.pid" ]; then
  if [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
    isCurl=$(curl --version 2>&1)
    if [[ ! "${isCurl}" =~ "OpenSSL" ]] || [ -z "${isCurl}" ]; then
      rm -f /etc/apt/sources.list.d/openssl.list
      if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
        && [ -e "/etc/apt/apt.conf.d" ]; then
        echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
      fi
      echo "curl install" | dpkg --set-selections &> /dev/null
      apt_clean_update
      apt-get install curl ${aptYesUnth} -fu --reinstall &> /dev/null
      mkdir -p /var/backups/libcurl
      mv -f /usr/local/lib/libcurl* /var/backups/libcurl/ &> /dev/null
      mv -f /usr/local/lib/pkgconfig/libcurl* /var/backups/libcurl/ &> /dev/null
      touch /root/.use.curl.from.packages.cnf
    fi
  fi
  rm -f /tmp/*error*
  rm -f /var/backups/BOA.sh.txt.hourly*
  find_fast_mirror
  curl -L -k -s \
    --max-redirs 5 \
    --retry 5 \
    --retry-delay 5 \
    -A iCab "http://${_USE_MIR}/versions/dev/boa/BOA.sh.txt" \
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

checkVn=$(/opt/local/bin/boa version | tr -d "\n" 2>&1)
if [[ "${checkVn}" =~ "===" ]] || [ -z "${checkVn}" ]; then
  if [ -e "/var/log/barracuda_log.txt" ]; then
    checkVn=$(tail --lines=3 /var/log/barracuda_log.txt | tr -d "\n" 2>&1)
  else
    checkVn="whereis barracuda_log.txt"
  fi
fi
crlHead="-I -k -s --retry 5 --retry-delay 5"
urlBpth="http://${_USE_MIR}/versions/dev/boa/aegir/tools/bin"
curl ${crlHead} -A "${checkVn}" "${urlBpth}/thinkdifferent" &> /dev/null
wait

renice ${_B_NICE} -p $$ &> /dev/null
service ssh restart &> /dev/null
touch /var/xdrago/log/clear.done.pid
exit 0
###EOF2023###
