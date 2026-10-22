#!/bin/bash
#
# BOA scheduled-cron watchdog — cron_guard v1.0.
#
# The control panel runs a site's scheduled cron as a web request to the
# site's cron route (/cron.php?cron_key=, /cron/<key> on Drupal 8+,
# /core/cron.php on Backdrop) and stamps the site's last cron time whether
# the request worked or not, so a site whose every scheduled cron answers an
# error looks fine in the panel. An observed Drupal 8 site answered 500 to
# every run for thirteen days, and only its owner noticed, through scheduled
# mails that never went out.
#
# This watchdog reads what nginx logged for those requests (the panel sends
# them with BOA's own iCabProXy agent) in today's and yesterday's access log,
# and reports a site whose scheduled cron failed in at least two different
# hours with no success in the same window. Read-only: it changes nothing on
# any site or panel.
#
# A failure is an answer of 403 (a wrong cron key, a refusing gate) or 5xx.
# A 404 is never one: BOA's own cron gate answers it for dev and tmp sites
# by design. One success in the window clears the site.
#
# Opt-outs (in /root/.barracuda.cnf):
#   _USE_CRON_GUARD=NO           fully off (unset means ON)
#
# Operator validation (--force skips the hourly self-throttle):
#
#   bash cron_guard.sh --force --stdout
#
# Conventions: BOA monitor sibling (cf. task_guard.sh). No systemd.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthDat="/var/log/boa/cron_guard"
_STAMP="${_pthDat}/.last_run"
_SEEN="${_pthDat}/reported"
_pthOml="/var/log/boa/cron_guard.incident.log"
_LOGS="/var/log/nginx/access.log.1 /var/log/nginx/access.log"

_FORCE=NO
_STDOUT=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)  _FORCE=YES ;;
    --stdout) _STDOUT=YES ;;
    -h|--help) echo "Usage: cron_guard.sh [--force] [--stdout]"; exit 0 ;;
    *) echo "Unknown argument: ${_arg}" >&2; exit 2 ;;
  esac
done

_say() { [ "${_STDOUT}" = "YES" ] && echo "$@"; }

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

# Run only on a fully installed system (same guard the sibling monitors use).
_rnp_installed() {
  local _n="/etc/boa/control/reset_no_new_password.pid"
  local _o="/var/log/boa/reset_no_new_password.pid"
  [ -e "${_n}" ] && return 0
  [ -e "${_o}" ] || return 1
  mkdir -p /etc/boa/control 2> /dev/null
  chmod 0755 /etc/boa /etc/boa/control 2> /dev/null
  { cp "${_o}" "${_n}.$$" && chmod 0644 "${_n}.$$" \
    && mv -f "${_n}.$$" "${_n}"; } 2> /dev/null || rm -f "${_n}.$$" 2> /dev/null
  return 0
}
_rnp_installed || exit 0

# Opt-out: fully off when the operator says so (unset means ON).
[ "${_USE_CRON_GUARD}" = "NO" ] && exit 0

# Scheduled cron runs only where the panel's queue runs: never on a
# replication standby or a finalized PX0 proxy.
[ -e "/root/.standby.cnf" ] && exit 0
[ -e "/root/.proxy.cnf" ] && exit 0

# Major system transition in flight: stand down.
for _rt in excalibur daedalus chimaera beowulf; do
  [ -e "/root/.run-to-${_rt}.cnf" ] && exit 0
done

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    # shellcheck disable=SC1090 # one of the two fixed lock.inc paths
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    _single_instance_lock
  else
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc "(^|(^| )[^ ]*bash )[^ ]*/${_SCRIPT//./\\.}( |$)")
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

mkdir -p "${_pthDat}"
chmod 0700 "${_pthDat}"

# Hourly (minute.sh relaunches us every minute), unless --force: the panel's
# shortest cron interval worth judging is an hour, and the access logs grow.
if [ "${_FORCE}" != "YES" ] && [ -e "${_STAMP}" ] \
  && [ -z "$(find "${_STAMP}" -mmin +59 2>/dev/null)" ]; then
  exit 0
fi
touch "${_STAMP}"

renice 19 -p $$ &> /dev/null
command -v ionice > /dev/null 2>&1 && ionice -c3 -p $$ &> /dev/null

###
### Load + normalize _INCIDENT_REPORT
###
###   OFF  == Total silence, no email alerts
###   ALL  == Very noisy, good for debugging
###   MINI == Only the most important alerts (default)
###   CRIT == Only critical if _lvl=ALERT
###
_normalize_incident_report() {
  : "${_INCIDENT_REPORT:=MINI}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_incident_email_report() {
  # A site losing its scheduled cron is heard at the default level (MINI);
  # this guard has no ALERT tier of its own.
  if command -v _check_uptime_grace_period >/dev/null 2>&1 \
    && ! _check_uptime_grace_period >/dev/null; then
    return 1
  fi
  local _subject="${1:-(no subject)}"
  local _lvl="${2:-MINI}"
  _lvl="${_lvl^^}"
  [ -n "${_MY_EMAIL}" ] || return 1
  case "${_INCIDENT_REPORT}" in
    OFF)  return 1 ;;
    CRIT) [ "${_lvl}" = "ALERT" ] || return 1 ;;
    MINI) [ "${_lvl}" = "ALERT" ] || [ "${_lvl}" = "MINI" ] || return 1 ;;
    ALL)  : ;;
  esac
  local _sfx=""
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    if ! _incident_email_ratelimit "cron-guard"; then
      echo "$(date) INFO: alert for '${_subject}' held back, one was already sent this cooldown" >> ${_pthOml}
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

# The scheduled cron requests in the window, judged per site: a site is
# printed when it has no 2xx/3xx answer and failed answers (403, 5xx) in at
# least two different hours, as "host hours last-status last-time".
# Fields per provision's log_format main: "$remote_addr" $host [$time_local]
# "$request" $status ..., so $2 = host, $3 = [date:time, $6 = path, $8 = status.
# The Drupal 8+ key takes only the key alphabet, as in global-main.inc: a
# /cron/../node request reaches a page, not cron.
_CRON_GUARD_AWK='
$6 ~ /^\/(cron\/[A-Za-z0-9_-]+|cron\.php|core\/cron\.php)([?].*)?$/ && $8 ~ /^[0-9][0-9][0-9]$/ {
  h = $2; s = $8; t = $3; sub(/^\[/, "", t)
  if (s ~ /^[23]/) { ok[h] = 1; next }
  if (s != "403" && s !~ /^5/) next
  k = substr(t, 1, 14)
  if (!((h, k) in seen)) { seen[h, k] = 1; hrs[h]++ }
  last[h] = s; when[h] = t
}
END {
  for (h in hrs) if (!(h in ok) && hrs[h] >= 2) print h, hrs[h], last[h], when[h]
}'

_failing="$(for _f in ${_LOGS}; do
    [ -f "${_f}" ] && [ ! -L "${_f}" ] && [ -r "${_f}" ] || continue
    grep -h -F '"iCabProXy"' "${_f}"
  done | awk "${_CRON_GUARD_AWK}" 2> /dev/null | sort)"

_today="$(date +%F)"
touch "${_SEEN}"
_new=0
while read -r _h _hrs _st _when; do
  [ -n "${_h}" ] || continue
  _say "FAILING host=${_h} hours=${_hrs} last=${_st} at=${_when}"
  # once a day per site: the log keeps the record, the mail the summary
  grep -qxF "${_today} ${_h}" "${_SEEN}" && continue
  echo "${_today} ${_h}" >> "${_SEEN}"
  echo "$(date) CRON: scheduled cron of ${_h} failed in ${_hrs} different hours with no success since yesterday; last answer ${_st} at ${_when} (the panel still shows cron as run)" >> ${_pthOml}
  _new=$(( _new + 1 ))
done <<< "${_failing}"

# keep a week of daily records
if [ -s "${_SEEN}" ]; then
  _keep="$(date -d '7 days ago' +%F 2> /dev/null)"
  [ -n "${_keep}" ] && awk -v k="${_keep}" '$1 >= k' "${_SEEN}" > "${_SEEN}.new" \
    && mv -f "${_SEEN}.new" "${_SEEN}"
fi

if [ "${_new}" -gt 0 ]; then
  _incident_email_report "Scheduled cron failing for ${_new} site(s)" "MINI"
  echo >> ${_pthOml}
fi
_say "DONE new=${_new}"

exit 0
