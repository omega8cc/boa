#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

pthOml="/var/xdrago/log/unbound.incident.log"

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

export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
: "${_INCIDENT_EMAIL_REPORT:=YES}"

if [ `ps aux | grep -v "grep" | grep --count "unbound.sh"` -gt "2" ]; then
  echo "Too many unbound.sh running"
  exit 0
fi

incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${pthOml}
  fi
}

unbound_check_fix() {
  if [ -x "/usr/sbin/unbound" ] \
    && [ ! -e "/etc/resolvconf/run/interface/lo.unbound" ]; then
    mkdir -p /etc/resolvconf/run/interface
    echo "nameserver 127.0.0.1" > /etc/resolvconf/run/interface/lo.unbound
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
    resolvconf -u &> /dev/null
    killall -9 unbound &> /dev/null
    service unbound restart &> /dev/null
    wait
    unbound-control reload &> /dev/null
  fi
  if [ -e "/etc/resolv.conf" ]; then
    _RESOLV_LOC=$(grep "nameserver 127.0.0.1" /etc/resolv.conf 2>&1)
    _RESOLV_ELN=$(grep "nameserver 1.1.1.1" /etc/resolv.conf 2>&1)
    _RESOLV_EGT=$(grep "nameserver 8.8.8.8" /etc/resolv.conf 2>&1)
    if [[ "${_RESOLV_LOC}" =~ "nameserver 127.0.0.1" ]] \
      && [[ "${_RESOLV_ELN}" =~ "nameserver 1.1.1.1" ]] \
      && [[ "${_RESOLV_EGT}" =~ "nameserver 8.8.8.8" ]]; then
      _THIS_DNS_TEST=$(host files.aegir.cc 127.0.0.1 -w 3 2>&1)
      if [[ "${_THIS_DNS_TEST}" =~ "no servers could be reached" ]]; then
        service unbound stop &> /dev/null
        sleep 1
        killall -9 unbound &> /dev/null
        renice ${_B_NICE} -p $$ &> /dev/null
        perl /var/xdrago/proc_num_ctrl.pl
        wait
      fi
    else
      rm -f /etc/resolv.conf
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      if [ -e "${vBs}/resolv.conf.vanilla" ]; then
        cat ${vBs}/resolv.conf.vanilla >> /etc/resolv.conf
      fi
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      echo "nameserver 1.0.0.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 8.8.4.4" >> /etc/resolv.conf
      [ -e "/etc/resolvconf/update.d/unbound" ] && chmod -x /etc/resolvconf/update.d/unbound
      killall -9 unbound &> /dev/null
      service unbound restart &> /dev/null
      wait
      unbound-control reload &> /dev/null
    fi
  fi
  if [ `ps aux | grep -v "grep" | grep --count "/usr/sbin/unbound"` -gt "1" ]; then
    kill -9 $(ps aux | grep '[u]sr/sbin/unbound' | awk '{print $2}') &> /dev/null
    service unbound start &> /dev/null
    wait
    echo "$(date 2>&1) Too many Unbound processes killed" >> ${pthOml}
    echo >> ${pthOml}
    incident_email_report "Too many Unbound processes"
  fi
}

unbound_check_fix

echo DONE!
exit 0
###EOF2024###
