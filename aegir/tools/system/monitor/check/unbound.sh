#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/log/boa/unbound.incident.log"

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
      _B_NICE=0
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
    # -------- legacy one-slot guard ---------
    # allow up to ONE concurrent worker; exit the 2nd+
    # Robustly match only the real worker:
    #  - direct exec:  "/full/path/script"
    #  - via bash:     "bash /full/path/script"
    _ABS="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
    # escape regex specials for pgrep
    _PAT="$(printf '%s' "$_ABS" | sed 's/[.[\*^$(){}+?\\|]/\\&/g')"
    # Count only lines that contain our absolute path, *and* either begin with bash+path or path at a word boundary.
    # This avoids counting the wrapper like '/bin/dash -c bash /path/script …' twice.
    _CNT=$(
      ps ax -o pid= -o args= \
        | awk -v P="$_PAT" '
            $0 ~ ("(^|[[:space:]]|/)bash[[:space:]]+" P "([[:space:]]|$)") ||
            $0 ~ ("(^|[[:space:]])" P "([[:space:]]|$)")
          ' \
        | wc -l
    )
    if [ "${_CNT:-0}" -gt 1 ]; then
      mkdir -p /var/log/boa 2>/dev/null || true
      echo "Too many ${_SELF_NAME} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_unbound_check_fix() {

  [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d

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
        if [ -e "/var/xdrago/proc_num_ctrl.pl" ]; then
          perl /var/xdrago/proc_num_ctrl.pl &
        elif [ -e "/var/xdrago_wait/proc_num_ctrl.pl" ]; then
          perl /var/xdrago_wait/proc_num_ctrl.pl &
        fi
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
  if [ `ps aux | grep -v "grep" | grep --count "/usr/sbin/unbound"` -gt 1 ]; then
    kill -9 $(ps aux | grep '[u]sr/sbin/unbound' | awk '{print $2}') &> /dev/null
    service unbound start &> /dev/null
    wait
    echo "$(date) Too many Unbound processes killed" >> ${_pthOml}
    _incident_email_report "Too many Unbound processes"
    echo >> ${_pthOml}
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

if [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

[ "${_ALLOW_CTRL}" = "YES" ] && _unbound_check_fix

### Check and modify and reload if needed
_unbound_check_nomail

echo DONE!
exit 0

