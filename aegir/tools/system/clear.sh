#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

forCer="-fuy --allow-unauthenticated --reinstall"

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

find /var/run/boa*.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/manage*users.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/daily-fix.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/clear_m.pid -mtime +0 -exec rm -rf {} \; &> /dev/null

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/var/run/clear_m.pid" ]; then
  exit 0
fi

touch /var/run/clear_m.pid

#
# Find the fastest mirror.
find_fast_mirror() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    apt-get update -qq &> /dev/null
    apt-get install netcat ${forCer} &> /dev/null
    sleep 3
  fi
  _USE_MIR="files.aegir.cc"
  if ! netcat -w 10 -z "${_USE_MIR}" 80; then
    echo "INFO: The mirror ${_USE_MIR} doesn't respond, let's try default"
    _USE_MIR="104.245.208.226"
  fi
  urlDev="http://${_USE_MIR}/dev"
  urlHmr="http://${_USE_MIR}/versions/master/aegir"
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
      apt-get clean -qq &> /dev/null
      rm -f -r /var/lib/apt/lists/*
      apt-get update -qq &> /dev/null
      apt-get install curl ${forCer} &> /dev/null
      touch /root/.use.curl.from.packages.cnf
    fi
  fi
  rm -f /tmp/*error*
  rm -f /var/backups/BOA.sh.txt.hourly*
  find_fast_mirror
  curl -L -k -s \
    --max-redirs 10 \
    --retry 10 \
    --retry-delay 5 \
    -A iCab "http://${_USE_MIR}/BOA.sh.txt" \
    -o /var/backups/BOA.sh.txt.hourly
  bash /var/backups/BOA.sh.txt.hourly &> /dev/null
  rm -f /var/backups/BOA.sh.txt.hourly*
  sleep 3
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
crlHead="-I -k -s --retry 8 --retry-delay 8"
urlBpth="http://files.aegir.cc/versions/master/aegir/tools/bin"
curl ${crlHead} -A "${checkVn}" "${urlBpth}/thinkdifferent" &> /dev/null

renice ${_B_NICE} -p $$ &> /dev/null
service ssh restart &> /dev/null
touch /var/xdrago/log/clear.done
rm -f /var/run/clear_m.pid
exit 0
###EOF2020###
