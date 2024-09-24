#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

pthVhstd="/var/aegir/config/server_master/nginx/vhost.d"

pthOml="/var/xdrago/log/high.load.incident.log"

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
check_root

export _B_NICE=${_B_NICE//[^0-9]/}
: "${_B_NICE:=10}"

export _CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO//[^0-9]/}
: "${_CPU_SPIDER_RATIO:=3}"

export _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
: "${_CPU_MAX_RATIO:=6}"

export _CPU_CRIT_RATIO=${_CPU_CRIT_RATIO//[^0-9]/}
: "${_CPU_CRIT_RATIO:=9}"

export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
: "${_INCIDENT_EMAIL_REPORT:=YES}"

if [ $(pgrep -f second.sh | grep -v "^$$" | wc -l) -gt 4 ]; then
  echo "Too many second.sh running $(date 2>&1)" >> /var/xdrago/log/too.many.log
  exit 0
fi

incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${pthOml}
  fi
}

hold() {
  killall -9 nginx
  killall -9 php-fpm
  thisErrLog="$(date 2>&1) System Load $1 Web Server Paused"
  echo ${thisErrLog} >> ${pthOml}
  incident_email_report "System Load $1 Web Server Paused"
  echo >> ${pthOml}
}

terminate() {
  if [ ! -e "/run/boa_run.pid" ]; then
    killall -9 php drush.php wget curl &> /dev/null
    thisErrLog="$(date 2>&1) System Load $1 PHP/Wget/cURL terminated"
    echo ${thisErrLog} >> ${pthOml}
    incident_email_report "System Load $1 PHP/Wget/cURL terminated"
    echo >> ${pthOml}
  fi
}

nginx_high_load_on() {
  mv -f /data/conf/nginx_high_load_off.conf /data/conf/nginx_high_load.conf
  service nginx reload &> /dev/null
  thisErrLog="$(date 2>&1) nginx_high_load_on $1"
  echo ${thisErrLog} >> ${pthOml}
  incident_email_report "nginx_high_load_on $1"
  echo >> ${pthOml}
}

nginx_high_load_off() {
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  service nginx reload &> /dev/null
  thisErrLog="$(date 2>&1) nginx_high_load_off $1"
  echo ${thisErrLog} >> ${pthOml}
  incident_email_report "nginx_high_load_off $1"
  echo >> ${pthOml}
}

proc_control() {
  if [ "${_O_LOAD}" -ge "${_O_LOAD_MAX}" ]; then
    hold "${_O_LOAD}/${_O_LOAD_MAX}"
  elif [ "${_F_LOAD}" -ge "${_F_LOAD_MAX}" ]; then
    hold "${_F_LOAD}/${_F_LOAD_MAX}"
  else
    echo "load is ${_O_LOAD}:${_F_LOAD} while \
      maxload is ${_O_LOAD_MAX}:${_F_LOAD_MAX}"
    echo ...OK now running proc_num_ctrl...
    renice ${_B_NICE} -p $$ &> /dev/null
    perl /var/xdrago/proc_num_ctrl.pl &
    touch /var/xdrago/log/proc_num_ctrl.done.pid
    echo CTL done
  fi
}

load_control() {
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  echo _O_LOAD is ${_O_LOAD}
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  echo _O_LOAD per CPU is ${_O_LOAD}

  _F_LOAD=$(awk '{print $2*100}' /proc/loadavg 2>&1)
  echo _F_LOAD is ${_F_LOAD}
  _F_LOAD=$(( _F_LOAD / _CPU_NR ))
  echo _F_LOAD per CPU is ${_F_LOAD}

  _O_LOAD_SPR=$(( 100 * _CPU_SPIDER_RATIO ))
  echo _O_LOAD_SPR is ${_O_LOAD_SPR}

  _F_LOAD_SPR=$(( _O_LOAD_SPR / 9 ))
  _F_LOAD_SPR=$(( _F_LOAD_SPR * 7 ))
  echo _F_LOAD_SPR is ${_F_LOAD_SPR}

  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
  echo _O_LOAD_MAX is ${_O_LOAD_MAX}

  _F_LOAD_MAX=$(( _O_LOAD_MAX / 9 ))
  _F_LOAD_MAX=$(( _F_LOAD_MAX * 7 ))
  echo _F_LOAD_MAX is ${_F_LOAD_MAX}

  _O_LOAD_CRT=$(( _CPU_CRIT_RATIO * 100 ))
  echo _O_LOAD_CRT is ${_O_LOAD_CRT}

  _F_LOAD_CRT=$(( _O_LOAD_CRT / 9 ))
  _F_LOAD_CRT=$(( _F_LOAD_CRT * 7 ))
  echo _F_LOAD_CRT is ${_F_LOAD_CRT}

  if [ "${_O_LOAD}" -ge "${_O_LOAD_SPR}" ] \
    && [ "${_O_LOAD}" -lt "${_O_LOAD_MAX}" ] \
    && [ -e "/data/conf/nginx_high_load_off.conf" ]; then
    nginx_high_load_on "${_O_LOAD}/${_O_LOAD_MAX}"
  elif [ "${_F_LOAD}" -ge "${_F_LOAD_SPR}" ] \
    && [ "${_F_LOAD}" -lt "${_F_LOAD_MAX}" ] \
    && [ -e "/data/conf/nginx_high_load_off.conf" ]; then
    nginx_high_load_on "${_F_LOAD}/${_F_LOAD_MAX}"
  elif [ "${_O_LOAD}" -lt "${_O_LOAD_SPR}" ] \
    && [ "${_F_LOAD}" -lt "${_F_LOAD_SPR}" ] \
    && [ -e "/data/conf/nginx_high_load.conf" ]; then
    nginx_high_load_off "${_O_LOAD}/${_F_LOAD_SPR}"
  fi

  if [ "${_O_LOAD}" -ge "${_O_LOAD_CRT}" ]; then
    terminate "${_O_LOAD}/${_O_LOAD_CRT}"
  elif [ "${_F_LOAD}" -ge "${_F_LOAD_CRT}" ]; then
    terminate "${_F_LOAD}/${_F_LOAD_CRT}"
  fi

  proc_control
}

count_cpu() {
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt "0" ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
}

count_cpu
load_control
sleep 10
load_control
sleep 10
load_control
sleep 10
load_control
sleep 10
load_control
sleep 10
load_control

echo Done !
exit 0
###EOF2024###
