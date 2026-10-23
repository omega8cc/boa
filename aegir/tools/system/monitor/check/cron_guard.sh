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
# them with BOA's own iCabProXy agent, from the box itself) in today's and
# yesterday's access log, and reports a site whose scheduled cron failed in
# at least two different hours, at least 50 minutes apart, with no success
# in the same window. Read-only: it changes nothing on any site or panel.
# When the box's awk cannot run the judgement, it says so once a day the
# same way, instead of reporting nothing.
#
# A failure is an answer of 403 (a wrong cron key, a refusing gate), 5xx, a
# 404 with a page (a Drupal 8+ site whose panel record has no cron key is
# asked for /cron/, which no route serves), or a 3xx (Drupal and Backdrop
# never redirect a working cron; a module sending 403s to the login page
# does). The 404 of BOA's own cron gate for dev and tmp sites carries no
# page and is never one. A redirect is cleared when the request it led to
# answered 2xx. A subdirectory site whose redirect is not logged is judged as
# <parent>/<subdir>. One success in the window clears the site, except
# a success within 15 minutes of a run killed at the PHP time limit: that is
# the panel's retry meeting the cron lock the killed run left, and no cron
# ran. Only requests from the box's own addresses count: anyone can send
# the agent string.
#
# A site whose cron interval is longer than a day has one run in the window
# at most and is never judged.
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
_MFAIL="${_pthDat}/.mail_failed"
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

# How an alert goes out now: "off" (no address, the level keeps a cron
# alert out, or a box lock.inc never mails from), "held" (a fresh boot, a BOA
# pass or the ratelimit holds it back) or "send". Asked only when there is
# something to send, since a "send" answer takes the ratelimit slot.
_mail_way() {
  _MAIL_WAY=send
  _sfx=""
  if [ -z "${_MY_EMAIL}" ]; then
    _MAIL_WAY=off
    return
  fi
  # A site losing its scheduled cron is heard at the default level (MINI);
  # this guard has no ALERT tier of its own.
  case "${_INCIDENT_REPORT}" in
    OFF|CRIT) _MAIL_WAY=off; return ;;
  esac
  # The grace check also fails for good on a box without csf (optional, or
  # removed where the kernel cannot run it) or without the Master's alias:
  # no alert ever goes out there, so the sites are logged and marked.
  if command -v _check_uptime_grace_period >/dev/null 2>&1 \
    && ! _check_uptime_grace_period >/dev/null; then
    if [ ! -x "/usr/sbin/csf" ] \
      || [ ! -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      _MAIL_WAY=off
    else
      _MAIL_WAY=held
    fi
    return
  fi
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    if ! _incident_email_ratelimit "cron-guard"; then
      _MAIL_WAY=held
      return
    fi
    if [ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]; then
      _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
    fi
  fi
}

_incident_email_send() {
  local _subject="${1:-(no subject)}"
  _hName="$(tr -d '\n' < /etc/hostname 2>/dev/null)"
  [ -n "${_hName}" ] || _hName="$(hostname -f 2>/dev/null)"
  echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
  s-nail -s "Incident Report: ${_subject}${_sfx} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_pthOml}")
}

# The scheduled cron requests in the window, judged per site: a site is
# printed when it has no success and failed answers in at least two
# different hours at least 50 minutes apart, as "host hours last-status
# last-time". Fields per provision's log_format main: "$remote_addr" $host
# [$time_local] "$request" $status $body_bytes_sent $request_length
# $bytes_sent "$http_referer" "$http_user_agent" $request_time ..., so
# $1 = "address", $2 = host, $3 = [date:time, $6 = path, $8 = status,
# $9 = body bytes, $14 = request time. The Drupal 8+ key takes only the key
# alphabet, as in global-main.inc: a /cron/../node request reaches a page,
# not cron. The gate's 404 has no page: 0 bytes, or a few bytes of framing
# in the line the SSL front logs for the same request; a page is 64 bytes
# or more.
# A 5xx after 170 s or more is a run killed at the time limit, started its
# request time earlier. Its cron lock outlives it: 900 s on Drupal 8+ and
# BOA's Drupal 7, 240 s on Backdrop, and Drupal 6 keeps its semaphore an
# hour, then the request that clears it runs nothing either (Drupal 6 is the
# one asked for /cron.php with no key). A 2xx in that time ran no cron.
# Each window has 30 s more: the lock is taken after the bootstrap, and the
# panel times a site's next run from the start of its last one.
# A redirect is cleared by the 2xx it led to, also on a path with a
# language prefix (a module sending /cron/<key> to /en/cron/<key>) or on
# another name (www to the bare name, a subdirectory site's name to its
# parent's path). The panel's curl follows a redirect at once, so its next
# hop is the next line for the same key, begun within 2 s of the redirect
# (the panel waits 3 s between sites), on the same name or another. A clone
# keeps its source's key, so a key alone would let a working clone clear its
# failing source. A prefixed path is a language prefix or a subdirectory
# site's cron route under its parent's name (/<subdir>/cron.php,
# /<subdir>/core/cron.php, /<subdir>/cron/<key>, a language prefix inside
# the subdirectory). A prefixed line no logged redirect led to belongs to a
# subdirectory site whose own name redirects through a vhost that logs
# nothing (the alias redirect logs only through the wildcard SSL front): it
# is judged as <parent>/<subdir>, the path below it as its route. The SSL
# front's copy of the line that ended a chain (same host, path and status,
# the same second or the next) is the same request, never such a line. A run
# killed on a prefixed path is timed by the host and path it was logged on,
# where its retry lands too: a subdirectory site's parent host has its own
# clock; Backdrop's lock is the shorter one there as well.
# Seconds count from the first day in the window (the logs are read in
# order, each line written when its request ended; mawk has no time
# functions).
_CRON_GUARD_AWK='
function ckey(p,   k) {
  k = p
  if (sub(/^.*[?&]cron_key=/, "", k)) { sub(/&.*$/, "", k); return k }
  if (match(p, /\/cron\/[A-Za-z0-9_-]+/)) return substr(p, RSTART + 6, RLENGTH - 6)
  return ""
}
# The open redirect chain of key k takes a line on host h begun at b when it
# began at most 2 s after the last line of the chain ended; on another name
# not before it either (the SSL front logs its copy of a request after the
# line of the site, and the copy began earlier).
function linked(k, h, b) {
  return (k != "" && ch[k] != "" && b - ct[k] <= 2 && (chh[k] == h || ct[k] <= b + 1))
}
# One line for key k on host h, judged as name n, ended at e, started at b:
# a 3xx opens or extends the chain of k, any other line ends it, and a 2xx
# that counts as a run (r) clears every name in it.
function hop(k, h, n, s, e, b, r,   on, m, i, c) {
  if (k == "") return
  on = linked(k, h, b)
  if (s ~ /^3/) {
    if (!on) ch[k] = n; else if (chn[k] != n) ch[k] = ch[k] " " n
    chh[k] = h; chn[k] = n; ct[k] = e; return
  }
  if (on && r) { m = split(ch[k], c, " "); for (i = 1; i <= m; i++) cl[c[i], k] = 1 }
  ch[k] = ""
}
function route(p) {
  return (p ~ /^\/(cron\/[A-Za-z0-9_-]*|cron\.php|core\/cron\.php)([?].*)?$/)
}
BEGIN { n = split(own, a, " "); for (i = 1; i <= n; i++) mine[a[i]] = 1 }
$8 ~ /^[0-9][0-9][0-9]$/ {
  ip = $1; gsub(/"/, "", ip); sub(/^::ffff:/, "", ip)
  if (!(ip in mine) && ip !~ /^127\./ && ip != "::1") next
  p = $6
  pre = 0
  if (!route(p)) {
    if (p !~ /^\/[A-Za-z][A-Za-z0-9_-]*(\/[A-Za-z][A-Za-z0-9_-]*)?\/(cron\/[A-Za-z0-9_-]*|cron\.php|core\/cron\.php)([?].*)?$/) next
    pre = 1
  }
  rh = $2; h = rh; s = $8; t = $3; sub(/^\[/, "", t)
  split(t, f, ":")
  if (!(f[1] in day)) day[f[1]] = ++nd
  sec = day[f[1]] * 86400 + f[2] * 3600 + f[3] * 60 + f[4]
  k = ckey(p); b = sec - $14
  if (pre && !linked(k, rh, b)) {
    if ((k in cp) && cp[k] == rh SUBSEP p SUBSEP s && sec - cpe[k] <= 1) next
    x = p; sub(/^\//, "", x); sub(/\/.*$/, "", x)
    h = rh "/" x; p = substr(p, length(x) + 2)
    if (!route(p)) { hop(k, rh, h, s, sec, b, 0); next }
    pre = 0
  }
  if (pre) {
    if (k != "" && s !~ /^3/) { cp[k] = rh SUBSEP p SUBSEP s; cpe[k] = sec }
    kp = p; sub(/[?].*$/, "", kp)
    if (s ~ /^5/ && $14 + 0 >= 170) kk[rh, kp] = sec - int($14 + 0)
    hop(k, rh, rh, s, sec, b, s ~ /^2/ && !(((rh, kp) in kk) && sec - kk[rh, kp] <= ((kp ~ /\/core\/cron\.php$/) ? 270 : 930)))
    next
  }
  if (s ~ /^2/) {
    if (h in ks) {
      if (sec - ks[h] <= ((p ~ /^\/core\//) ? 270 : 930)) { hop(k, rh, h, s, sec, b, 0); next }
      if (h in d6) { if (sec - ks[h] > 3630) delete d6[h]; hop(k, rh, h, s, sec, b, 0); next }
    }
    ok[h] = 1; hop(k, rh, h, s, sec, b, 1); next
  }
  hop(k, rh, h, s, sec, b, 0)
  if (s ~ /^3/) {
    if (k == "") next
    rk[h SUBSEP k] = 1
  }
  else if (s == "404") { if ($9 + 0 < 64) next }
  else if (s != "403" && s !~ /^5/) next
  if (s ~ /^5/ && $14 + 0 >= 170) {
    ks[h] = sec - int($14 + 0)
    if (p == "/cron.php") d6[h] = 1; else delete d6[h]
  }
  k = substr(t, 1, 14)
  if (!((h, k) in seen)) { seen[h, k] = 1; hrs[h]++ }
  if (!(h in first)) first[h] = sec
  lasts[h] = sec; last[h] = s; when[h] = t
}
END {
  for (x in rk) if (x in cl) { split(x, q, SUBSEP); ok[q[1]] = 1 }
  for (h in hrs) if (!(h in ok) && hrs[h] >= 2 && lasts[h] - first[h] >= 3000) print h, hrs[h], last[h], when[h]
}'

# The box's own addresses (kernel, operator list, barracuda.cnf): the
# panel's requests come from them, loopback included.
_OWN_IPS="$( { ip -o addr show 2> /dev/null | awk '{print $4}' | sed 's#/.*##'
    [ -r /root/.local.IP.list ] && sed -e 's/#.*//' -e 's/[[:space:]]//g' /root/.local.IP.list
    echo "${_MY_OWNIP}"; } | grep -E '^[0-9A-Fa-f.:]+$' | sort -u | tr '\n' ' ')"

# -a: a log with a crash-zeroed stretch must not read as binary, which
# would hide every line after it. The judgement's errors are kept: an awk
# that cannot run it reports no site at all and would look healthy.
_AERR="${_pthDat}/.reader.err"
_failing="$(for _f in ${_LOGS}; do
    [ -f "${_f}" ] && [ ! -L "${_f}" ] && [ -r "${_f}" ] || continue
    LC_ALL=C grep -a -h -F '"iCabProXy"' "${_f}"
  done | awk -v own="${_OWN_IPS}" "${_CRON_GUARD_AWK}" 2> "${_AERR}")"
_awkRc=$?
_failing="$(sort <<< "${_failing}")"

_today="$(date +%F)"
touch "${_SEEN}"
_newHosts=()
_newLines=()
_subject=""
# once a day, like a site: the next hourly run tries again while held
if [ "${_awkRc}" -ne 0 ]; then
  _aErr="$(head -n 1 "${_AERR}" 2> /dev/null | tr -cd '[:print:]' | cut -c1-160)"
  _say "READERFAIL rc=${_awkRc} ${_aErr}"
  if ! grep -qxF "${_today} (log reader)" "${_SEEN}"; then
    _newHosts+=("(log reader)")
    _newLines+=("$(date) CRON: cron_guard could not judge the access logs (awk exit ${_awkRc}${_aErr:+: ${_aErr}}); no failing site can be reported until it can")
    _subject="cron_guard cannot judge the access logs"
  fi
fi
rm -f "${_AERR}"
while read -r _h _hrs _st _when; do
  [ -n "${_h}" ] || continue
  _say "FAILING host=${_h} hours=${_hrs} last=${_st} at=${_when}"
  # once a day per site: the log keeps the record, the mail the summary
  grep -qxF "${_today} ${_h}" "${_SEEN}" && continue
  _newHosts+=("${_h}")
  _newLines+=("$(date) CRON: scheduled cron of ${_h} failed in ${_hrs} different hours with no success since yesterday; last answer ${_st} at ${_when} (the panel still shows cron as run)")
done <<< "${_failing}"
_new="${#_newHosts[@]}"

# keep a week of daily records
if [ -s "${_SEEN}" ]; then
  _keep="$(date -d '7 days ago' +%F 2> /dev/null)"
  [ -n "${_keep}" ] && awk -v k="${_keep}" '$1 >= k' "${_SEEN}" > "${_SEEN}.new" \
    && mv -f "${_SEEN}.new" "${_SEEN}"
fi

# A site is marked as reported only when its alert went out, or when no
# alert can: a held one is tried again by the next hourly run, and so is a
# failed mail, once a day (a box whose mail never works logs it once a day).
if [ "${_new}" -gt 0 ]; then
  _mail_way
  if [ "${_MAIL_WAY}" = "held" ]; then
    echo "$(date) INFO: alert for ${_new} site(s) held back (a fresh boot, a BOA pass or the cooldown); the next hourly run tries again" >> ${_pthOml}
    _say "HELD new=${_new}"
    exit 0
  fi
  for _i in "${!_newHosts[@]}"; do
    echo "${_newLines[${_i}]}" >> ${_pthOml}
  done
  _mark=YES
  if [ "${_MAIL_WAY}" = "send" ] \
    && ! _incident_email_send "${_subject:-Scheduled cron failing for ${_new} site(s)}"; then
    if [ "$(cat "${_MFAIL}" 2> /dev/null)" != "${_today}" ]; then
      echo "${_today}" > "${_MFAIL}"
      _mark=NO
    fi
    echo "$(date) INFO: the alert mail for ${_new} site(s) failed" >> ${_pthOml}
    _say "MAILFAIL new=${_new} marked=${_mark}"
  fi
  if [ "${_mark}" = "YES" ]; then
    for _i in "${!_newHosts[@]}"; do
      echo "${_today} ${_newHosts[${_i}]}" >> "${_SEEN}"
    done
  fi
  echo >> ${_pthOml}
fi
_say "DONE new=${_new}"

exit 0
