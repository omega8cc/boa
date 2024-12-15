#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/xdrago/log/unbound.incident.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

    # Sanitize to allow only digits and minus sign
    export _B_NICE=${_B_NICE//[^0-9-]/}

    # Validate and set default if necessary
    if ! [[ "$_B_NICE" =~ ^-?[0-9]+$ ]]; then
      _B_NICE=-5
    fi

    # Clamp the value within -20 to 19
    if (( _B_NICE < -20 )); then
      _B_NICE=-20
    elif (( _B_NICE > 19 )); then
      _B_NICE=19
    fi

    renice ${_B_NICE} -p $$ &> /dev/null

export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
: "${_INCIDENT_REPORT:=YES}"

if (( $(pgrep -fc 'unbound.sh') > 2 )); then
  echo "Too many unbound.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_unbound_check_fix() {
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
        perl /var/xdrago/proc_num_ctrl.pl &
      fi
    else
      rm -f /etc/resolv.conf
      echo "nameserver 127.0.0.1" > /etc/resolv.conf
      if [ -e "${_vBs}/resolv.conf.vanilla" ]; then
        cat ${_vBs}/resolv.conf.vanilla >> /etc/resolv.conf
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
    echo "$(date) Too many Unbound processes killed" >> ${_pthOml}
    _incident_email_report "Too many Unbound processes"
    echo >> ${_pthOml}
  fi
}

if [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

[ "${_ALLOW_CTRL}" = "YES" ] && _unbound_check_fix

echo DONE!
exit 0
###EOF2024###
