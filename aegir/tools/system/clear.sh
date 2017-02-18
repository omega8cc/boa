#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

forCer="-fuy --force-yes --reinstall"

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
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
check_root

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
    apt-get install netcat ${forCer} &> /dev/null
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
}

if [ ! -e "/var/run/boa_run.pid" ]; then
  if [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
    isCurl=$(curl --version 2>&1)
    if [[ ! "${isCurl}" =~ "OpenSSL" ]] || [ -z "${isCurl}" ]; then
      rm -f /etc/apt/sources.list.d/openssl.list
      echo "curl install" | dpkg --set-selections
      apt-get clean -qq &> /dev/null
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
  bash /opt/local/bin/autoupboa
fi

#
# Clean up postfix queue to get rid of bounced emails.
# See also: https://omega8.cc/never-send-mailings-from-aegir-server-322
sudo postsuper -d ALL &> /dev/null

if [ -e "/etc/init.d/rsyslog" ]; then
  killall -9 rsyslogd &> /dev/null
  service rsyslog start &> /dev/null
elif [ -e "/etc/init.d/sysklogd" ]; then
  killall -9 sysklogd &> /dev/null
  service sysklogd start &> /dev/null
elif [ -e "/etc/init.d/inetutils-syslogd" ]; then
  killall -9 syslogd &> /dev/null
  service inetutils-syslogd start &> /dev/null
fi
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

if [ -d "/dev/disk" ]; then
  _IF_CDP=$(ps aux | grep '[c]dp_io' | awk '{print $2}')
  if [ -z "${_IF_CDP}" ] && [ ! -e "/root/.no.swap.clear.cnf" ]; then
    swapoff -a
    swapon -a
  fi
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

if [ -e "/var/xdrago/mysql_hourly.sh" ]; then
  bash /var/xdrago/mysql_hourly.sh
fi

renice ${_B_NICE} -p $$ &> /dev/null
service ssh restart &> /dev/null
touch /var/xdrago/log/clear.done
exit 0
###EOF2017###
