#!/bin/bash
#
# BOA service container watchdog — container_guard v1.0.
#
# Drupal 8+ compiles its service container once and keeps it in a cache; on
# BOA that cache is Valkey (db 8), one hash per site and container under
# <prefix>:container:service_container:..., whose "created" field is the time
# it was written. When a site's code calls the kernel's invalidateContainer()
# while it serves requests, the Redis module's deleteAll() writes the bin's
# stamp, <prefix>:container:_redis_last_delete_all, which marks every entry
# written before it as stale, and the next request compiles the container
# again. A site whose code does that on every request pays a full container
# build on each one: an observed store lost about 0.9 s a request this way
# for days, and nothing on the box said so.
#
# This watchdog reads every site's newest container time and stamp every ten
# minutes and reports a site when, at three checks in a row, both had been
# written again since the check before and the stamp was the newer of the
# two: the site kept compiling its container and throwing it away while it
# served requests. A cache rebuild (drush cr, the panel's Flush all caches),
# a Verify, a Migrate, a module install, the admin page's Clear all caches
# and a Valkey restart all leave the container newer than any stamp, so none
# of them is ever reported; a stamp newer than a container that nothing has
# rewritten since (a site nobody visited after such an action) counts nothing.
# Read-only: it changes nothing on any site, cache or panel.
#
# A site is named, with its account, by the path its container's cache key
# carries, else by the vhost name whose md5 starts the prefix. Each site gets
# one line a day in the incident log; the host's alert mail goes out at most
# once a day, listing every site found that day so far.
#
# Opt-outs (in /root/.barracuda.cnf):
#   _USE_CONTAINER_GUARD=NO      fully off (unset means ON)
#
# Operator validation (--force skips the ten-minute self-throttle):
#
#   bash container_guard.sh --force --stdout
#
# Conventions: BOA monitor sibling (cf. cron_guard.sh). No systemd.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthDat="/var/log/boa/container_guard"
_STAMP="${_pthDat}/.last_run"
_STATE="${_pthDat}/state"
_SEEN="${_pthDat}/reported"
_MAILED="${_pthDat}/.mailed"
_pthOml="/var/log/boa/container_guard.incident.log"
_VK_CLI="/usr/bin/valkey-cli"
_VK_SOCK="/run/valkey/valkey.sock"
_VK_PASS="/root/.valkey.pass.txt"
# checks in a row that make a report, and the longest gap in seconds between
# two rewrites that still counts as a row
_ROW=3
_ROW_GAP=3600

_FORCE=NO
_STDOUT=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)  _FORCE=YES ;;
    --stdout) _STDOUT=YES ;;
    -h|--help) echo "Usage: container_guard.sh [--force] [--stdout]"; exit 0 ;;
    *) echo "Unknown argument: ${_arg}" >&2; exit 2 ;;
  esac
done

_say() { [[ "${_STDOUT}" = "YES" ]] && echo "$@"; }

_check_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    # shellcheck disable=SC1091
    [[ -e "/root/.barracuda.cnf" ]] && source /root/.barracuda.cnf
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
  [[ -e "${_n}" ]] && return 0
  [[ -e "${_o}" ]] || return 1
  mkdir -p /etc/boa/control 2> /dev/null
  chmod 0755 /etc/boa /etc/boa/control 2> /dev/null
  { cp "${_o}" "${_n}.$$" && chmod 0644 "${_n}.$$" \
    && mv -f "${_n}.$$" "${_n}"; } 2> /dev/null || rm -f "${_n}.$$" 2> /dev/null
  return 0
}
_rnp_installed || exit 0

# Opt-out: fully off when the operator says so (unset means ON).
[[ "${_USE_CONTAINER_GUARD}" = "NO" ]] && exit 0

# A replication standby and a finalized PX0 proxy serve no site.
[[ -e "/root/.standby.cnf" ]] && exit 0
[[ -e "/root/.proxy.cnf" ]] && exit 0

# Major system transition in flight: stand down.
for _rt in excalibur daedalus chimaera beowulf; do
  [[ -e "/root/.run-to-${_rt}.cnf" ]] && exit 0
done

[[ -x "${_VK_CLI}" ]] || exit 0

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    # shellcheck disable=SC1090 # one of the two fixed lock.inc paths
    [[ -r "${_L}" ]] && . "${_L}" && break
  done
  if [[ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ]] && command -v _single_instance_lock >/dev/null 2>&1; then
    _single_instance_lock
  else
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -u root -U root -fc "(^|(^| )[^ ]*bash )[^ ]*/${_SCRIPT//./\\.}( |$)")
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

mkdir -p "${_pthDat}"
chmod 0700 "${_pthDat}"

# Every ten minutes (minute.sh relaunches us every minute), unless --force:
# the reads must be minutes apart, and each one scans the whole cache.
if [[ "${_FORCE}" != "YES" ]] && [[ -e "${_STAMP}" ]] \
  && [[ -z "$(find "${_STAMP}" -mmin +9 2> /dev/null)" ]]; then
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

# How the alert goes out now: "off" (no address, the level keeps it out, or
# a box lock.inc never mails from), "held" (a fresh boot, a BOA pass or the
# ratelimit holds it back) or "send". Asked only when there is something to
# send, since a "send" answer takes the ratelimit slot.
_mail_way() {
  _MAIL_WAY=send
  _sfx=""
  if [[ -z "${_MY_EMAIL}" ]]; then
    _MAIL_WAY=off
    return
  fi
  # A site paying a container build on every request is heard at the
  # default level (MINI); this watchdog has no ALERT tier of its own.
  case "${_INCIDENT_REPORT}" in
    OFF|CRIT) _MAIL_WAY=off; return ;;
  esac
  # The grace check also fails for good on a box without csf or without the
  # Master's alias: no alert ever goes out there.
  if command -v _check_uptime_grace_period >/dev/null 2>&1 \
    && ! _check_uptime_grace_period >/dev/null; then
    if [[ ! -x "/usr/sbin/csf" ]] \
      || [[ ! -e "/var/aegir/.drush/hm.alias.drushrc.php" ]]; then
      _MAIL_WAY=off
    else
      _MAIL_WAY=held
    fi
    return
  fi
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    if ! _incident_email_ratelimit "container-guard"; then
      _MAIL_WAY=held
      return
    fi
    if [[ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]]; then
      _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
    fi
  fi
}

# Valkey over its socket, or the default port when the box has no socket;
# the password through the environment, never on the command line.
_VK=("${_VK_CLI}" -n 8)
if [[ -S "${_VK_SOCK}" ]]; then
  _VK=("${_VK_CLI}" -s "${_VK_SOCK}" -n 8)
fi
if [[ -r "${_VK_PASS}" ]]; then
  REDISCLI_AUTH="$(head -n 1 "${_VK_PASS}" 2> /dev/null | tr -d '\r\n')"
  export REDISCLI_AUTH
fi

_KEYS="${_pthDat}/.keys"
_CMDS="${_pthDat}/.cmds"
_REPL="${_pthDat}/.replies"
_NAMES="${_pthDat}/.names"
_cleanup() {
  rm -f "${_KEYS}" "${_CMDS}" "${_REPL}" "${_NAMES}" "${_STATE}.new" "${_SEEN}.new"
}
trap _cleanup EXIT

# Every container bin key in db 8, by SCAN (never KEYS): the containers and
# the bins' stamps. A count of 1000 keeps each call short, so no request
# waits behind it on a cache of millions of keys. A scan that fails or is
# cut off leaves the state as it was: a missing answer is no evidence.
if ! timeout 300 "${_VK[@]}" --scan --pattern '*:container:*' --count 1000 > "${_KEYS}" 2> /dev/null; then
  _say "NOSCAN valkey did not answer the scan"
  exit 0
fi

# The keys read, in one order for the reads and the judgement: a container
# (C) or a bin's stamp (S), each under a prefix with no colon in it (the
# pattern also meets other bins' entries whose id holds ":container:"). A key
# holding a single quote or a backslash is left out: it is sent single-quoted,
# which escapes nothing (container keys carry PHP-serialized paths, so double
# quotes are common and need no escape). Octal escapes only: the box's awk is
# mawk.
_KEYS_AWK='
function kind(k,   i) {
  i = index(k, ":container:")
  if (i < 2 || index(substr(k, 1, i - 1), ":")) return ""
  if (index(k, "\047") || index(k, "\\")) return ""
  if (substr(k, i) == ":container:_redis_last_delete_all") return "S"
  if (substr(k, i, 29) == ":container:service_container:") return "C"
  return ""
}'

# One read per key, sent down one connection: HGET created for a container,
# GET for a stamp; one reply line each, in order, an empty line for a key
# gone meanwhile.
LC_ALL=C awk "${_KEYS_AWK}"'
  { t = kind($0) }
  t == "C" { print "HGET \047" $0 "\047 created" }
  t == "S" { print "GET \047" $0 "\047" }' "${_KEYS}" > "${_CMDS}"
if [[ -s "${_CMDS}" ]]; then
  if ! timeout 300 "${_VK[@]}" 2> /dev/null < "${_CMDS}" > "${_REPL}"; then
    _say "NOREAD valkey did not answer the reads"
    exit 0
  fi
else
  : > "${_REPL}"
fi

# The vhost names of every account, for a key that names no site: the
# prefix starts with md5 of the name without www.
for _v in /data/disk/*/config/server_master/nginx/vhost.d/*; do
  [[ -f "${_v}" ]] || continue
  _n="${_v##*/}"
  [[ "${_n}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || continue
  _a="${_v#/data/disk/}"
  printf '%s %s %s\n' "$(printf '%s' "${_n#www.}" | md5sum | cut -c1-32)" "${_n}" "${_a%%/*}"
done > "${_NAMES}" 2> /dev/null

_NOW="$(date +%s)"
touch "${_STATE}" "${_SEEN}"
chmod 0600 "${_STATE}" "${_SEEN}" 2> /dev/null

# The judgement, per prefix: the newest container time (C), the stamp (S),
# and from the last check its C and S, the row (n), when the row began and
# when it last grew. A check whose C and S both moved and whose S is the
# newer grows the row; one that leaves S newer and nothing moved keeps it
# (nobody visited); a container newer than the stamp ends it, unless both
# moved (a check landing between a rebuild and its wipe, or a site fixed
# since: the row is kept, unreported, and the next check decides); a row that
# has not grown for _ROW_GAP seconds starts again. State lines: S prefix C S
# n first last site account. Report lines: R (a report) or W (watched)
# prefix n first site account.
_out="$(LC_ALL=C awk -v now="${_NOW}" -v row="${_ROW}" -v gap="${_ROW_GAP}" \
  -v nf="${_NAMES}" -v sf="${_STATE}" -v rf="${_REPL}" "${_KEYS_AWK}"'
function num(v) { return (v ~ /^[0-9]+(\.[0-9]+)?$/) }
BEGIN {
  while ((getline l < nf) > 0) {
    split(l, w, " ")
    if (w[1] != "" && !(w[1] in nm)) { nm[w[1]] = w[2]; na[w[1]] = w[3] }
  }
  close(nf)
  while ((getline l < sf) > 0) {
    split(l, w, " ")
    if (w[1] == "") continue
    pc[w[1]] = w[2]; ps[w[1]] = w[3]; pn[w[1]] = w[4]; pf[w[1]] = w[5]; pl[w[1]] = w[6]
  }
  close(sf)
}
{
  t = kind($0)
  if (t == "") next
  if ((getline v < rf) <= 0) v = ""
  k = $0
  p = substr(k, 1, index(k, ":container:") - 1)
  if (t == "S") { if (num(v)) st[p] = v; next }
  if (!num(v)) next
  if (!(p in cc) || v + 0 > cc[p] + 0) {
    cc[p] = v
    s = ""; a = ""
    if (match(k, /sites\/[A-Za-z0-9][A-Za-z0-9._-]*/)) s = substr(k, RSTART + 6, RLENGTH - 6)
    if (s == "default" || s == "all") s = ""
    if (match(k, /\/data\/disk\/[A-Za-z0-9._-]+\//)) a = substr(k, RSTART + 11, RLENGTH - 12)
    site[p] = s; acct[p] = a
  }
}
END {
  for (p in cc) {
    s = site[p]; a = acct[p]
    h = substr(p, 1, 32)
    if (s == "" && (h in nm)) s = nm[h]
    if (a == "" && (h in na)) a = na[h]
    if (s == "") s = "-"
    if (a == "") a = "-"
    c = cc[p]; d = ((p in st) ? st[p] : "")
    x = (d != "" && d + 0 > c + 0)
    had = (p in pc)
    moved = (had && d != "" && pc[p] != c && ps[p] != d)
    if (!x && !moved) continue
    if (!had) { n = 0; f = now; lg = now }
    else {
      n = pn[p] + 0; f = pf[p]; lg = pl[p]
      if (now - lg > gap) { n = 0; f = now; lg = now }
      if (x && moved) { n++; lg = now }
    }
    if (!x && n == 0) continue
    printf "S %s %s %s %d %s %s %s %s\n", p, c, (d == "" ? "-" : d), n, f, lg, s, a
    # A row kept with the container the newer is never reported at that
    # check: it is as likely a site just fixed (one rebuild after its last
    # wipe) as a check between a request's rebuild and its wipe, and the
    # next check tells them apart.
    if (!x) continue
    printf "%s %s %d %s %s %s\n", ((n >= row) ? "R" : "W"), p, n, f, s, a
  }
}' "${_KEYS}")"
_awkRc=$?
if [[ "${_awkRc}" -ne 0 ]]; then
  _say "READERFAIL rc=${_awkRc}"
  exit 0
fi

grep '^S ' <<< "${_out}" | cut -d' ' -f2- > "${_STATE}.new"
mv -f "${_STATE}.new" "${_STATE}"
chmod 0600 "${_STATE}" 2> /dev/null

_today="$(date +%F)"
_found=()
_newLines=()
while read -r _t _p _n _f _s _a; do
  [[ -n "${_p}" ]] || continue
  _since="$(date -d "@${_f}" '+%F %H:%M' 2> /dev/null)"
  if [[ "${_t}" = "W" ]]; then
    _say "WATCH prefix=${_p} site=${_s} account=${_a} row=${_n}"
    continue
  fi
  _say "FAULTY prefix=${_p} site=${_s} account=${_a} row=${_n} since=${_since}"
  _found+=("  ${_s} (account ${_a}): since ${_since:-unknown}, at ${_n} checks in a row")
  # once a day per site: the log keeps the record, the mail the summary
  grep -qxF "${_today} ${_p}" "${_SEEN}" && continue
  echo "${_today} ${_p}" >> "${_SEEN}"
  _newLines+=("$(date) CONTAINER: ${_s} (account ${_a}, cache prefix ${_p}) compiled Drupal's service container and threw it away again at ${_n} checks in a row since ${_since:-unknown}: its own code invalidates the container while it serves requests, so each request pays for a full container build")
done <<< "$(grep '^[RW] ' <<< "${_out}" | sort -k5,5 -k2,2)"

for _l in "${_newLines[@]}"; do
  echo "${_l}" >> "${_pthOml}"
done

# keep a week of daily records
if [[ -s "${_SEEN}" ]]; then
  _keep="$(date -d '7 days ago' +%F 2> /dev/null)"
  [[ -n "${_keep}" ]] && awk -v k="${_keep}" '$1 >= k' "${_SEEN}" > "${_SEEN}.new" \
    && mv -f "${_SEEN}.new" "${_SEEN}"
fi

_mail_body() {
  echo "Drupal's service container is compiled again and thrown away right after,"
  echo "request after request, on these sites of ${_hName}. Each of their requests"
  echo "pays for a full container build: on one observed store about 0.9 seconds a"
  echo "request, for days, with nothing else showing it."
  echo
  printf '%s\n' "${_found[@]}"
  echo
  echo "How it was seen: BOA keeps each Drupal 8+ site's compiled container in"
  echo "Valkey. At each of these checks, ten minutes apart, the site's container"
  echo "had been written again since the check before and was already marked"
  echo "stale by the site itself. That happens when the site's code calls the"
  echo "kernel's invalidateContainer() while it serves requests. A cache rebuild"
  echo "(drush cr, Flush all caches), a Verify, a Migrate or a Valkey restart"
  echo "never leaves this state, and none of them fixes it."
  echo
  echo "What to look for in the site's code: calls of invalidateContainer(),"
  echo "rebuildContainer() or drupal_flush_all_caches() that ordinary requests"
  echo "reach, most often in an event subscriber (kernel.request, kernel.terminate)"
  echo "of a custom module or of a local patch to a contributed one; and code that"
  echo "runs while the container is compiled (getSubscribedEvents(), a service"
  echo "provider) and reads another service, which fails there and can send a"
  echo "module down such a path."
  echo
  echo "This is a report only: BOA changed nothing on these sites. Each site's"
  echo "line is also in ${_pthOml}."
}

# The mail: once a day at most, every site found so far that day. A held one
# is tried again at the next check; a failed one waits for the next day.
_mailed="NO"
if [[ "${#_found[@]}" -gt 0 ]] && [[ "$(cat "${_MAILED}" 2> /dev/null)" != "${_today}" ]]; then
  _mail_way
  case "${_MAIL_WAY}" in
    held)
      _mailed="HELD"
      if [[ "${#_newLines[@]}" -gt 0 ]]; then
        echo "$(date) INFO: alert for ${#_found[@]} site(s) held back (a fresh boot, a BOA pass or the cooldown); the next check tries again" >> "${_pthOml}"
      fi
      ;;
    off)
      echo "${_today}" > "${_MAILED}"
      ;;
    send)
      _hName="$(tr -d '\n' 2> /dev/null < /etc/hostname)"
      [[ -n "${_hName}" ]] || _hName="$(hostname -f 2> /dev/null)"
      echo "${_today}" > "${_MAILED}"
      echo "Sending Incident Report Email on $(date)" >> "${_pthOml}"
      if _mail_body | s-nail -s "Incident Report: Drupal container rebuilt on every request on ${#_found[@]} site(s)${_sfx} on ${_hName} at $(date)" ${_MY_EMAIL}; then
        _mailed="YES"
      else
        _mailed="FAILED"
        echo "$(date) INFO: the alert mail for ${#_found[@]} site(s) failed; the next day's check tries again" >> "${_pthOml}"
      fi
      ;;
  esac
fi
if [[ "${#_newLines[@]}" -gt 0 ]]; then
  echo >> "${_pthOml}"
fi
_say "DONE faulty=${#_found[@]} new=${#_newLines[@]} mail=${_mailed}"

exit 0
