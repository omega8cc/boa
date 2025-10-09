#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/unbound.incident.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

# Run only on fully installed system
[ ! -x "/usr/sbin/csf" ] && exit 0

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

: "${_UNBOUND_COOLDOWN_SECS:=10}"
_cd="/run/unbound-monitor.cooldown"

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "$_L" ] && . "$_L" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

###
### Load + normalize _INCIDENT_REPORT
###
### Legacy values:
###   NO  becomes OFF (see below)
###   YES becomes MINI (see below)
###
### Current values:
###   OFF  == Total silence, no email alerts
###   ALL  == Very noisy, good for debugging
###   MINI == Only the most important alerts (default)
###   CRIT == Only critical if _lvl=ALERT
###
_normalize_incident_report() {
  : "${_INCIDENT_REPORT:=MINI}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  ###
  ### Map legacy + validate
  ###
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_incident_email_report() {
  if ! _check_uptime_grace_period >/dev/null; then return 1; fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "ALL" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_unbound_restart_with_cooldown() {
  pkill -u unbound -x unbound &> /dev/null
  service unbound restart &> /dev/null
  wait
  echo "$(date) INFO: Unbound killed and restarted" >> ${_pthOml}
  date +%s > "${_UNBOUND_CD}"
  sleep 3
}

_unbound_config_fix() {


  if [ -x "/usr/sbin/unbound" ] \
    && [ ! -e "/etc/resolvconf/run/interface/lo.unbound" ]; then
    touch /run/wait-unbound.pid
    sleep 3
    mkdir -p /etc/resolvconf/run/interface
    echo "nameserver 127.0.0.1" > /etc/resolvconf/run/interface/lo.unbound
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod 644 /etc/resolvconf/update.d/unbound
    resolvconf -u &> /dev/null
    pkill -u unbound -x unbound &> /dev/null
    service unbound restart &> /dev/null
    wait
    unbound-control reload &> /dev/null
    sleep 3
    rm -f /run/wait-unbound.pid
  fi
  if [ -e "/etc/resolv.conf" ]; then
    _RESOLV_LOC=$(grep "nameserver 127.0.0.1" /etc/resolv.conf 2>&1)
    _RESOLV_ELN=$(grep "nameserver 1.1.1.1" /etc/resolv.conf 2>&1)
    _RESOLV_EGT=$(grep "nameserver 8.8.8.8" /etc/resolv.conf 2>&1)
    _RESOLV_NIN=$(grep "nameserver 9.9.9.9" /etc/resolv.conf 2>&1)
    if [[ "${_RESOLV_LOC}" =~ "nameserver 127.0.0.1" ]] \
      && [[ "${_RESOLV_ELN}" =~ "nameserver 1.1.1.1" ]] \
      && [[ "${_RESOLV_EGT}" =~ "nameserver 8.8.8.8" ]] \
      && [[ "${_RESOLV_NIN}" =~ "nameserver 9.9.9.9" ]]; then
      _THIS_DNS_TEST=$(host files.aegir.cc 127.0.0.1 -w 3 2>&1)
      if [[ "${_THIS_DNS_TEST}" =~ "no servers could be reached" ]]; then
        touch /run/wait-unbound.pid
        sleep 3
        service unbound stop &> /dev/null
        sleep 1
        pkill -u unbound -x unbound &> /dev/null
        renice ${_B_NICE} -p $$ &> /dev/null
        if [ -e "/var/xdrago/proc_num_ctrl.pl" ]; then
          perl /var/xdrago/proc_num_ctrl.pl &
        elif [ -e "/var/xdrago_wait/proc_num_ctrl.pl" ]; then
          perl /var/xdrago_wait/proc_num_ctrl.pl &
        fi
        sleep 3
        rm -f /run/wait-unbound.pid
      fi
    else
      touch /run/wait-unbound.pid
      sleep 3
      rm -f /etc/resolv.conf
      echo "### BOA-DNS-Config ###" > /etc/resolv.conf
      echo "nameserver 127.0.0.1" >> /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 9.9.9.9" >> /etc/resolv.conf
      [ -e "/etc/resolvconf/update.d/unbound" ] && chmod 644 /etc/resolvconf/update.d/unbound
      pkill -u unbound -x unbound &> /dev/null
      service unbound restart &> /dev/null
      wait
      unbound-control reload &> /dev/null
      sleep 3
      rm -f /run/wait-unbound.pid
    fi
  fi
  _CNT=$(pgrep -fc /usr/sbin/unbound)
  if (( _CNT > 1 )); then
    touch /run/wait-unbound.pid
    sleep 3
    pkill -u unbound -x unbound &> /dev/null
    service unbound restart &> /dev/null
    wait
    echo "$(date) Too many Unbound processes killed (count=${_CNT})" >> ${_pthOml}
    _incident_email_report "Too many Unbound processes (count=${_CNT})"
    echo >> ${_pthOml}
    sleep 3
    rm -f /run/wait-unbound.pid
  elif (( _CNT < 1 )); then
    [ -x "/etc/init.d/unbound" ] && service unbound restart &> /dev/null
  fi
}

_unbound_fix_nomail() {
  _MAIN_CONF="$(unbound-checkconf 2>&1 | awk 'NR==1{print $NF}')"
  if [ -z "${_MAIN_CONF}" ]; then
    _MAIN_CONF="/usr/etc/unbound/unbound.conf"
  fi
  _CONF_DIR="$(dirname "${_MAIN_CONF}")/unbound.conf.d"
  _DROP_IN="${_CONF_DIR}/ci-nomail.conf"
  install -d -m 0755 -o root -g root "${_CONF_DIR}"

cat >"${_DROP_IN}" <<'CONF'
server:
  # SendGrid
  local-zone: "sendgrid.com." always_nxdomain
  local-zone: "sendgrid.net." always_nxdomain

  # Mailgun
  local-zone: "mailgun.net." always_nxdomain

  # SparkPost
  local-zone: "sparkpost.com." always_nxdomain

  # Postmark
  local-zone: "postmarkapp.com." always_nxdomain

  # Brevo (Sendinblue)
  local-zone: "brevo.com." always_nxdomain

  # AWS SES
  local-zone: "amazonaws.com." always_nxdomain
CONF

  _INCLUDE_LINE=$(printf 'include-toplevel: "%s/*.conf"' "${_CONF_DIR}")
  if ! grep -Fq "${_INCLUDE_LINE}" "${_MAIN_CONF}"; then
    printf '\n%s\n' "${_INCLUDE_LINE}" >> "${_MAIN_CONF}"
  fi

  unbound-checkconf "${_MAIN_CONF}"
  service unbound reload

  if dig @127.0.0.1 api.sendgrid.com | grep -q 'status: NXDOMAIN'; then
    echo "OK: NXDOMAIN for api.sendgrid.com"
  else
    echo "WARN: api.sendgrid.com did not return NXDOMAIN"
  fi
}

_unbound_check_nomail() {
  [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d
  [ -e "/etc/default/unbound" ] && _isNxdEtc=$(grep "always_nxdomain" /etc/default/unbound 2>&1)
  [ -e "/etc/init.d/unbound" ] && _isIntUnb=$(grep "apply_ci_nomail" /etc/init.d/unbound 2>&1)
  if [[ "${_isNxdEtc}" =~ "always_nxdomain" ]] \
    && [[ "${_isIntUnb}" =~ "apply_ci_nomail" ]]; then
    _isIncTop=$(grep "include-toplevel" /usr/etc/unbound/unbound.conf 2>&1)
    if [ ! -e "/usr/etc/unbound/unbound.conf.d/ci-nomail.conf" ] \
      || [[ ! "${_isIncTop}" =~ "include-toplevel" ]]; then
      _unbound_fix_nomail
    fi
    _isActiveCtrl=$(unbound-control list_local_zones | grep -E 'sendgrid' 2>&1)
    if [[ ! "${_isActiveCtrl}" =~ "sendgrid" ]]; then
      service unbound reload &> /dev/null
    fi
  fi
}

_unbound_health_check_fix() {
  if ! pgrep -f /usr/sbin/unbound \
    || [ ! -e "/run/unbound/unbound.pid" ]; then
    : "${_UNBOUND_COOLDOWN_SECS:=10}"
    _cd="/run/unbound-monitor.cooldown"
    _now=$(date +%s)
    if [ -s "${_cd}" ]; then
      _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
      if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_UNBOUND_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: Unbound unhealthy but in cooldown; skipping restart" >> ${_pthOml}
        return 0
      fi
    fi
    touch /run/wait-unbound.pid
    sleep 3
    [ ! -e "/run/unbound" ] && mkdir -p /run/unbound
    chown -R unbound:unbound /run/unbound
    mkdir -p /etc/resolvconf/run/interface
    echo "nameserver 127.0.0.1" > /etc/resolvconf/run/interface/lo.unbound
    [ -e "/etc/resolvconf/update.d/unbound" ] && chmod 644 /etc/resolvconf/update.d/unbound
    resolvconf -u &> /dev/null
    _unbound_restart_with_cooldown
    _thisErrLog="$(date) Unbound Server was down, restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "Unbound Server was down, restarted"
    echo >> ${_pthOml}
  fi
}

if [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

if [ -x "/usr/sbin/unbound" ] && [ ! -e "/run/wait-unbound.pid" ]; then
  [ "${_ALLOW_CTRL}" = "YES" ] && _unbound_config_fix
  [ "${_ALLOW_CTRL}" = "YES" ] && _unbound_check_nomail
  _unbound_health_check_fix
fi

echo DONE!
exit 0

