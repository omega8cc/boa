#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

#
# Find the fastest mirror.
find_mirror() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ] ; then
    apt-get update -qq &> /dev/null
    apt-get install netcat -y --force-yes --reinstall &> /dev/null
    sleep 3
  fi
  ffMirr=$(which ffmirror 2>&1)
  if [ -x "${ffMirr}" ] ; then
    ffList="/var/backups/boa-mirrors.txt"
    mkdir -p /var/backups
    echo "jp.files.aegir.cc"  > ${ffList}
    echo "nl.files.aegir.cc" >> ${ffList}
    echo "uk.files.aegir.cc" >> ${ffList}
    echo "us.files.aegir.cc" >> ${ffList}
    if [ -e "${ffList}" ] ; then
      _CHECK_MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
      _USE_MIRROR="${_CHECK_MIRROR}"
    else
      _USE_MIRROR="files.aegir.cc"
    fi
  else
    _USE_MIRROR="files.aegir.cc"
  fi
  if ! netcat -w 5 -z ${_USE_MIRROR} 80 ; then
    echo "INFO: The mirror ${_USE_MIRROR} doesn't respond, let's try default"
    _USE_MIRROR="files.aegir.cc"
  fi
}

service ssh restart &> /dev/null
rm -f /var/backups/.auth.IP.list*
find /var/xdrago/log/*.pid -mtime +0 -type f -exec rm -rf {} \; &> /dev/null

if [ -e "/etc/cron.daily/logrotate" ] ; then
  _SYSLOG_SIZE_TEST=$(du -s -h /var/log/syslog)
  if [[ "${_SYSLOG_SIZE_TEST}" =~ "G" ]] ; then
    echo ${_SYSLOG_SIZE_TEST} too big
    bash /etc/cron.daily/logrotate &> /dev/null
    echo system logs rotated
  fi
fi

if [ -e "/root/.high_traffic.cnf" ] ; then
  echo rotate > /var/log/nginx/access.log
fi

if [ -e "/var/run/boa_run.pid" ] || [ -e "/var/run/daily-fix.pid" ] ; then
  sleep 1
else
  if [ -e "/root/.barracuda.cnf" ] ; then
    source /root/.barracuda.cnf
  fi
  if [ -z "${_SKYNET_MODE}" ] || [ "${_SKYNET_MODE}" = "ON" ] ; then
    rm -f /tmp/*error*
    rm -f /var/backups/BOA.sh.txt.hourly*
    find_mirror
    curl -L -k -s \
      --max-redirs 10 \
      --retry 10 \
      --retry-delay 5 \
      -A iCab "http://${_USE_MIRROR}/BOA.sh.txt" \
      -o /var/backups/BOA.sh.txt.hourly
    bash /var/backups/BOA.sh.txt.hourly &> /dev/null
    rm -f /var/backups/BOA.sh.txt.hourly*
  fi
  bash /opt/local/bin/autoupboa
fi

if [ -e "/etc/resolvconf/run/interface/lo.pdnsd" ] ; then
  rm -f /etc/resolvconf/run/interface/eth*
  resolvconf -u &> /dev/null
fi

if [ -d "/dev/disk" ] ; then
  _IF_CDP=$(ps aux | grep '[c]dp_io' | awk '{print $2}')
  if [ -z "${_IF_CDP}" ] && [ ! -e "/root/.no.swap.clear.cnf" ] ; then
    swapoff -a
    swapon -a
  fi
fi

touch /var/xdrago/log/clear.done
exit 0
###EOF2015###
