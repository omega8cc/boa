#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

find /var/run/boa*.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/manage*users.pid -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/run/daily-fix.pid -mtime +0 -exec rm -rf {} \; &> /dev/null

#
# Find the fastest mirror.
find_fast_mirror() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    rm -f /etc/apt/sources.list.d/openssl.list
    apt-get update -qq &> /dev/null
    apt-get install netcat -fuy --force-yes --reinstall &> /dev/null
    sleep 3
  fi
  ffMirr=$(which ffmirror 2>&1)
  if [ -x "${ffMirr}" ]; then
    ffList="/var/backups/boa-mirrors.txt"
    mkdir -p /var/backups
    if [ ! -e "${ffList}" ]; then
      echo "jp.files.aegir.cc"  > ${ffList}
      echo "nl.files.aegir.cc" >> ${ffList}
      echo "uk.files.aegir.cc" >> ${ffList}
      echo "us.files.aegir.cc" >> ${ffList}
    fi
    if [ -e "${ffList}" ]; then
      _CHECK_MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
      _USE_MIR="${_CHECK_MIRROR}"
      [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.aegir.cc"
    else
      _USE_MIR="files.aegir.cc"
    fi
  else
    _USE_MIR="files.aegir.cc"
  fi
  if ! netcat -w 10 -z "${_USE_MIR}" 80; then
    echo "INFO: The mirror ${_USE_MIR} doesn't respond, let's try default"
    _USE_MIR="files.aegir.cc"
  fi
  urlDev="http://${_USE_MIR}/dev"
  urlHmr="http://${_USE_MIR}/versions/master/aegir"
  urlStb="http://${_USE_MIR}/versions/stable"
}

service ssh restart &> /dev/null
rm -f /var/backups/.auth.IP.list*
find /var/xdrago/log/*.pid -mtime +0 -type f -exec rm -rf {} \; &> /dev/null

if [ -e "/etc/cron.daily/logrotate" ]; then
  _SYSLOG_SIZE_TEST=$(du -s -h /var/log/syslog)
  if [[ "${_SYSLOG_SIZE_TEST}" =~ "G" ]]; then
    echo ${_SYSLOG_SIZE_TEST} too big
    bash /etc/cron.daily/logrotate &> /dev/null
    echo system logs rotated
  fi
fi

if [ -e "/var/run/boa_run.pid" ]; then
  sleep 1
else
  if [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
  fi
  if [ -z "${_SKYNET_MODE}" ] || [ "${_SKYNET_MODE}" = "ON" ]; then
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
  fi
  bash /opt/local/bin/autoupboa
fi

if [ -d "/dev/disk" ]; then
  _IF_CDP=$(ps aux | grep '[c]dp_io' | awk '{print $2}')
  if [ -z "${_IF_CDP}" ] && [ ! -e "/root/.no.swap.clear.cnf" ]; then
    swapoff -a
    swapon -a
  fi
fi

touch /var/xdrago/log/clear.done
exit 0
###EOF2015###
