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
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

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

_cd="/run/unbound-monitor.cooldown"
: "${_UNBOUND_COOLDOWN_SECS:=30}"

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc "(^|(^| )[^ ]*bash )[^ ]*/${_SCRIPT//./\\.}( |$)")
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
  # An older lock.inc without the grace helper must not silence the page:
  # an undefined function reads as "inside the grace period" otherwise.
  if command -v _check_uptime_grace_period >/dev/null 2>&1 \
    && ! _check_uptime_grace_period >/dev/null; then
    return 1
  fi
  local _subject="${1:-(no subject)}"
  local _lvl="${2:-INFO}"
  _lvl="${_lvl^^}"
  [ -n "${_MY_EMAIL}" ] || return 1
  # The severity ladder, applied to what this watchdog can say:
  #   ALERT == the resolver does not come back from a restart: auto-healing
  #            cannot fix it and an operator is the only way forward.
  #   MINI  == nothing yet; the arm is kept so the level means here what it
  #            means in the other watchdogs.
  #   INFO  == a restart that worked, ALL only, as before.
  case "${_INCIDENT_REPORT}" in
    OFF)  return 1 ;;
    CRIT) [ "${_lvl}" = "ALERT" ] || return 1 ;;
    MINI) [ "${_lvl}" = "ALERT" ] || [ "${_lvl}" = "MINI" ] || return 1 ;;
    ALL)  : ;;
  esac
  # One alert per cooldown, not one per pass. A service that keeps failing
  # used to send a mail every time a watchdog acted, which buries the signal
  # exactly when it matters most. Nothing is lost: every incident is still
  # written to the log below, and the mail body is the tail of that log, so
  # the next alert that does go out carries the ones that did not. An ALERT
  # gets its own class and a six-hour cooldown by construction, not by
  # remembering to pass them at the call site: a resolver that stays dead is
  # one incident, not one per half hour. An older lock.inc without the helper
  # simply sends as before.
  local _sfx=""
  local _key="${3:-}"
  local _cool=""
  if [ -z "${_key}" ]; then
    if [ "${_lvl}" = "ALERT" ]; then
      _key="unbound-dead"
    else
      _key="unbound"
    fi
  fi
  [ "${_lvl}" = "ALERT" ] && _cool="21600"
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    if ! _incident_email_ratelimit "${_key}" "${_cool}"; then
      # The dead-resolver line is written every minute and names the cause
      # itself; a second line per minute saying the mail was held back would
      # halve what the 200-line mail body can carry.
      if [ "${_lvl}" != "ALERT" ]; then
        echo "$(date) INFO: alert for '${_subject}' held back, one was already sent this cooldown" >> ${_pthOml}
      fi
      return 1
    fi
    if [ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]; then
      _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
    fi
  fi
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
  s-nail -s "Incident Report: ${_subject}${_sfx} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_pthOml}")
}

# Our build reads /usr/etc/unbound/unbound.conf; a distro build reads
# /etc/unbound/unbound.conf and cannot start on our config. Mirrors the
# installer's test (dns.sh.inc): true only on positive evidence, so a binary
# that cannot even print its usage is never called a distro build.
_unbound_is_distro_build() {
  [ -x "/usr/sbin/unbound" ] || return 1
  /usr/sbin/unbound -h 2>&1 | grep -q "instead of /etc/unbound/unbound.conf"
}

# A restart that leaves no daemon behind is not a restart. This used to log
# "killed and restarted" once a minute for as long as the daemon refused to
# start, with no mail at any reporting level, while the box resolved through
# the fallback servers in resolv.conf and nothing looked wrong. Returns 0 only
# when the daemon is there afterwards; otherwise says why, as far as
# unbound-checkconf can tell, and pages once per six hours.
_unbound_restart_with_cooldown() {
  local _why=""
  pkill -u unbound -x unbound &> /dev/null
  service unbound restart &> /dev/null
  wait
  date +%s > "${_cd}"
  sleep 3
  if pgrep -u unbound -x unbound > /dev/null 2>&1; then
    echo "$(date) INFO: Unbound killed and restarted" >> ${_pthOml}
    return 0
  fi
  _why="$(unbound-checkconf 2>&1 | grep -m 1 "error:" | sed "s/^.*error: //")"
  if _unbound_is_distro_build; then
    _why="${_why:+${_why}; }/usr/sbin/unbound is a distro build, not ours -- a package upgrade replaced it, the next barracuda pass reinstalls ours"
  fi
  echo "$(date) ALRT: Unbound did not start after the restart: ${_why:-no reason given by unbound-checkconf}" >> ${_pthOml}
  _incident_email_report "Unbound does not start" "ALERT"
  return 1
}

_unbound_check_cooldown_status() {
  # Check cooldown status
  _in_unbound_cooldown=false
  if [ -s "${_cd}" ]; then
    _cd_now=$(date +%s)
    _cd_ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
    if [ -n "${_cd_ts}" ] && [ $((_cd_now - _cd_ts)) -lt "${_UNBOUND_COOLDOWN_SECS}" ]; then
      _in_unbound_cooldown=true
    fi
  fi
}

_unbound_config_fix() {
  _unbound_check_cooldown_status
  # Confirm that DNS requests are working
  if [ -e "/etc/resolv.conf" ]; then
    _RESOLV_LOC=$(grep "nameserver 127.0.0.1" /etc/resolv.conf 2>&1)
    if [[ "${_RESOLV_LOC}" =~ "nameserver 127.0.0.1" ]]; then
      _THIS_DNS_TEST=$(host files.boa.io 127.0.0.1 -w 8 2>&1)
      if [[ "${_THIS_DNS_TEST}" =~ "no servers could be reached" ]]; then
        if [ "${_in_unbound_cooldown}" = "true" ]; then
          echo "$(date) INFO: Unbound restart skipped (cooldown active)" >> ${_pthOml}
        else
          if _unbound_restart_with_cooldown; then
            echo "$(date) INFO: Unbound restarted after DNS check failed" >> ${_pthOml}
            echo >> ${_pthOml}
          fi
          exit 0
        fi
      fi
    else
      if ! grep -q "BOA-DNS-Config" /etc/resolv.conf; then
        chattr -i /etc/resolv.conf
        rm -f /etc/resolv.conf
        echo "### BOA-DNS-Config ###" > /etc/resolv.conf
        echo "nameserver 127.0.0.1" >> /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        echo "nameserver 9.9.9.9" >> /etc/resolv.conf
        chmod 0644 /etc/resolv.conf
        if [ "${_in_unbound_cooldown}" = "true" ]; then
          echo "$(date) INFO: Unbound restart skipped (cooldown active)" >> ${_pthOml}
        else
          if _unbound_restart_with_cooldown; then
            echo "$(date) INFO: Unbound restarted after /etc/resolv.conf update" >> ${_pthOml}
            echo >> ${_pthOml}
          fi
          exit 0
        fi
      fi
    fi
  fi
}

_unbound_fix_nomail() {
  _MAIN_CONF="$(unbound-checkconf 2>&1 | awk 'NR==1{print $NF}')"
  # Only a clean check ends its first line with the config path; on a config
  # error the last word is a fragment of the message, and a drop-in dir plus
  # an include line would be written relative to wherever this runs.
  if [[ ! "${_MAIN_CONF}" =~ ^/ ]] || [ ! -f "${_MAIN_CONF}" ]; then
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

_unbound_health_check_fix() {
  _unbound_check_cooldown_status
  # The daemon itself: exact process name under its own user. An unanchored
  # pgrep -f on the path matched any command line naming it (unbound-anchor,
  # unbound-control, a checksum sweep over /usr/sbin) and masked a dead resolver.
  if ! pgrep -u unbound -x unbound > /dev/null 2>&1 \
    || [ ! -e "/run/unbound/unbound.pid" ]; then
    _now=$(date +%s)
    if [ -s "${_cd}" ]; then
      _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
      if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_UNBOUND_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: Unbound unhealthy but in cooldown; skipping restart" >> ${_pthOml}
        return 0
      fi
    fi
    [ -d /run/unbound ] || mkdir -p /run/unbound
    [ -d /run/unbound ] && chown -R unbound:unbound /run/unbound
    if _unbound_restart_with_cooldown; then
      _thisErrLog="$(date) Unbound Server was down, restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _incident_email_report "Unbound Server was down, restarted"
      echo >> ${_pthOml}
    fi
    exit 0
  fi
}

_unbound_duplicate_fix() {
  _unbound_check_cooldown_status
  # Duplicate masters: only the daemon counts (exact name, its own user); a
  # helper or a tool that merely names /usr/sbin/unbound is not a second
  # master. Rechecked after a grace so one sample never restarts the
  # resolver, and the processes counted are logged before the restart.
  _CNT=$(pgrep -c -u unbound -x unbound 2> /dev/null)
  if (( _CNT > 1 )); then
    sleep 3
    _CNT=$(pgrep -c -u unbound -x unbound 2> /dev/null)
  fi
  if (( _CNT > 1 )); then
    # === cooldown-wrapped restart ===
    if [ "${_in_unbound_cooldown}" = "true" ]; then
      echo "$(date) INFO: Unbound duplicate-masters restart skipped (cooldown active)" >> ${_pthOml}
    else
      echo "$(date) INFO: Unbound masters counted: $(pgrep -a -u unbound -x unbound 2> /dev/null | tr '\n' ';')" >> ${_pthOml}
      if _unbound_restart_with_cooldown; then
        echo "$(date) INFO: Too many Unbound processes killed and service restarted (count=${_CNT})" >> ${_pthOml}
        echo >> ${_pthOml}
      fi
      exit 0
    fi
  fi
}

if [ -x "/etc/init.d/unbound" ] && [ -x "/usr/sbin/unbound" ]; then
  [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d
  _unbound_config_fix
  _unbound_check_nomail
  _unbound_health_check_fix
  _unbound_duplicate_fix
fi

echo DONE!
exit 0

