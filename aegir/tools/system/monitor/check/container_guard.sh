#!/bin/bash
#
# BOA service container watchdog — container_guard v1.2.
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
# This watchdog reads every site's newest container time and stamp about
# every ten minutes and reports a site in one of two ways:
#
#   - thrown away: at three checks, each within an hour of the one before,
#     both had been written again since the previous check and the stamp was
#     the newer of the two (its code invalidates the container while it
#     serves requests, and the next request compiles it again);
#   - rebuilt: at six checks in a row both had been written again, the
#     container the newer at each (its code throws the container away and
#     compiles it again inside its requests: drupal_flush_all_caches(), or
#     invalidateContainer() then rebuildContainer()). Someone clearing all
#     caches from the admin pages again and again for an hour looks the same,
#     and the report says so.
#
# A cache rebuild (drush cr, the panel's Flush all caches), a Verify and a
# module install from the command line write the container and no stamp; a
# Migrate and the admin page's Clear all caches write the stamp and then the
# container; a Valkey restart empties both. So none of them, done once, is
# ever reported, and a stamp newer than a container that nothing has
# rewritten since (a site nobody visited after such an action) counts
# nothing. Code that rebuilds the container without throwing it away first
# (rebuildContainer() alone, a module install in every request) writes no
# stamp and is not seen. Read-only: it changes nothing on any site, cache or
# panel.
#
# A site is named, with its account, by its own sites/<name>/services.yml or
# the sites/<name> deployment identifier its container's cache key carries,
# else by the vhost name whose md5 starts the prefix. Each site gets one line
# a day in the incident log, at most fifty a run, the rest counted and
# named by a later check. The host's alert mail goes out at most once a day,
# from the first check that finds a site, listing every site found that day
# so far, among them each site still counted as thrown away (a site first
# found after it is in the next day's mail if it is found again by then).
# Valkey is read over its socket, or 127.0.0.1:6379 where there is none; a
# box that cannot be read gets one incident line a day saying so.
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
_FOUND="${_pthDat}/found"
_MAILED="${_pthDat}/.mailed"
_UNREAD="${_pthDat}/.unread"
_pthOml="/var/log/boa/container_guard.incident.log"
_VK_CLI="/usr/bin/valkey-cli"
_VK_SOCK="/run/valkey/valkey.sock"
_VK_PASS="/root/.valkey.pass.txt"
# checks that make a report of each kind, and the longest gap in seconds
# between two checks that grow the same thrown-away row
_ROW=3
_ROW_REBUILT=6
_ROW_GAP=3600
# sites a run writes to the log and the mail lists, the rest counted
_MAX_SITES=50

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

# About every ten minutes (minute.sh relaunches us every minute), unless
# --force: the reads must be minutes apart, and each one scans the whole cache.
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
# send, since a "send" answer takes the ratelimit slot. The mail goes once a
# day, so a held try and the mail that follows it are the same alert: the
# subject carries no count of held tries.
_mail_way() {
  _MAIL_WAY=send
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
  fi
}

# Valkey over its socket, or the default port when the box has no socket
# (a box whose Valkey listens on another address is not read); the password
# through the environment, never on the command line.
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
  rm -f "${_KEYS}" "${_CMDS}" "${_REPL}" "${_NAMES}" "${_STATE}.new" "${_SEEN}.new" "${_FOUND}.new"
}
trap _cleanup EXIT

# A scan or read Valkey did not answer leaves the state as it was: a missing
# answer is no evidence. It is said once a day in the incident log, so a box
# the check cannot read never looks like a box with nothing to report.
_unread() {
  local _today
  _say "NOREAD $1"
  _today="$(date +%F)"
  if [[ "$(cat "${_UNREAD}" 2> /dev/null)" != "${_today}" ]]; then
    echo "${_today}" > "${_UNREAD}"
    echo "$(date) INFO: container_guard could not read Valkey ($1); no site was judged" >> "${_pthOml}"
  fi
  exit 0
}

# Every container bin key in db 8, by SCAN (never KEYS): the containers and
# the bins' stamps. A count of 1000 keeps each call short, so no request
# waits behind it on a cache of millions of keys.
if ! timeout 300 "${_VK[@]}" --scan --pattern '*:container:*' --count 1000 > "${_KEYS}" 2> /dev/null; then
  _unread "the scan failed"
fi

# The keys read, in one order for the reads and the judgement: a container
# (C) or a bin's stamp (S), each under a prefix of letters, digits and
# underscores only, as the Redis module writes them (the pattern also meets
# other bins' entries whose id holds ":container:"). A key holding a single
# quote or a backslash is left out: it is sent single-quoted, which escapes
# nothing (container keys carry PHP-serialized paths, so double quotes are
# common and need no escape). Octal escapes only: the box's awk is mawk.
_KEYS_AWK='
function kind(k,   i) {
  i = index(k, ":container:")
  if (i < 2 || substr(k, 1, i - 1) !~ /^[A-Za-z0-9_]+$/) return ""
  if (index(k, "\047") || index(k, "\\")) return ""
  if (substr(k, i) == ":container:_redis_last_delete_all") return "S"
  if (substr(k, i, 29) == ":container:service_container:") return "C"
  return ""
}'

# One read per key, sent down one connection: HGET created for a container,
# GET for a stamp. In CSV each reply is one line whatever it holds (a value
# with a newline is escaped, a missing key is NULL, an error reads ERROR,...),
# cut to 80 characters, since no timestamp is longer, so the reply file and
# the judgement stay small whatever a key holds. Reads that fail come back as
# fewer lines (a lost connection writes to stderr and still exits 0) or as
# errors from the server itself (no password, loading, no free client):
# either way nothing is judged. A WRONGTYPE error belongs to one key and only
# that key is left out.
LC_ALL=C awk "${_KEYS_AWK}"'
  { t = kind($0) }
  t == "C" { print "HGET \047" $0 "\047 created" }
  t == "S" { print "GET \047" $0 "\047" }' "${_KEYS}" > "${_CMDS}"
if [[ -s "${_CMDS}" ]]; then
  timeout 300 "${_VK[@]}" --csv 2> /dev/null < "${_CMDS}" | cut -c1-80 > "${_REPL}"
  _rd=("${PIPESTATUS[@]}")
  if [[ "${_rd[0]}" -ne 0 ]] || [[ "${_rd[1]}" -ne 0 ]]; then
    _unread "the reads ended with status ${_rd[0]}"
  fi
  _nRepl=$(( $(wc -l < "${_REPL}") ))
  _nCmds=$(( $(wc -l < "${_CMDS}") ))
  if [[ "${_nRepl}" -ne "${_nCmds}" ]]; then
    _unread "${_nRepl} replies to ${_nCmds} reads"
  fi
  if grep '^ERROR,' "${_REPL}" | grep -qv '^ERROR,"WRONGTYPE '; then
    _unread "the server answered $(grep '^ERROR,' "${_REPL}" | grep -v '^ERROR,"WRONGTYPE ' | head -n 1 | tr -cd '[:print:]' | cut -c1-60)"
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
touch "${_STATE}" "${_SEEN}" "${_FOUND}"
chmod 0600 "${_STATE}" "${_SEEN}" "${_FOUND}" 2> /dev/null

# The judgement, per prefix with a stamp: the newest container time (C), the
# stamp (S), and from the last check its C and S, the thrown-away row (n),
# the rebuilt row (m), when the watch began (f, 0 for none) and when n last
# grew (lg). A check where both moved grows n when S is the newer and m when
# C is, and keeps the other row: a check can land inside one request, between
# its wipe and its rebuild or between a rebuild and the next wipe, and a
# site fixed since shows C the newer once. S the newer with nothing moved
# keeps n (nobody visited) and ends m; C the newer with nothing moved ends
# both. n ends when it has not grown for _ROW_GAP seconds. A prefix is
# thrown away while n is at _ROW and S the newer, and rebuilt at a check
# that grows m to _ROW_REBUILT or past it. State lines: S prefix C S n first
# last site account m. Report lines: R (thrown away), B (rebuilt) or W
# (watched) prefix rows first site account.
_out="$(LC_ALL=C awk -v now="${_NOW}" -v row="${_ROW}" -v rowb="${_ROW_REBUILT}" \
  -v gap="${_ROW_GAP}" -v nf="${_NAMES}" -v sf="${_STATE}" -v rf="${_REPL}" "${_KEYS_AWK}"'
function num(v) {
  if (v !~ /^"[0-9]+(\.[0-9]+)?"$/) return ""
  return substr(v, 2, length(v) - 2)
}
BEGIN {
  while ((getline l < nf) > 0) {
    split(l, w, " ")
    if (w[1] != "" && !(w[1] in nm)) { nm[w[1]] = w[2]; na[w[1]] = w[3] }
  }
  close(nf)
  while ((getline l < sf) > 0) {
    split(l, w, " ")
    if (w[1] == "") continue
    pc[w[1]] = w[2]; ps[w[1]] = w[3]; pn[w[1]] = w[4]; pf[w[1]] = w[5]; pl[w[1]] = w[6]; pm[w[1]] = w[9]
  }
  close(sf)
}
{
  t = kind($0)
  if (t == "") next
  if ((getline v < rf) <= 0) v = ""
  v = num(v)
  k = $0
  p = substr(k, 1, index(k, ":container:") - 1)
  if (t == "S") { if (v != "") st[p] = v; next }
  if (v == "") next
  if (!(p in cc) || v + 0 > cc[p] + 0) {
    cc[p] = v
    s = ""; a = ""
    if (match(k, /\/sites\/[A-Za-z0-9][A-Za-z0-9._-]*\/services\.yml/)) s = substr(k, RSTART + 7, RLENGTH - 20)
    else if (match(k, /[:.]sites\/[A-Za-z0-9][A-Za-z0-9._-]*:/)) s = substr(k, RSTART + 7, RLENGTH - 8)
    if (s == "default" || s == "all") s = ""
    if (match(k, /\/data\/disk\/[A-Za-z0-9._-]+\//)) a = substr(k, RSTART + 11, RLENGTH - 12)
    site[p] = s; acct[p] = a
  }
}
END {
  for (p in cc) {
    if (!(p in st)) continue
    s = site[p]; a = acct[p]
    h = substr(p, 1, 32)
    if (s == "" && (h in nm)) s = nm[h]
    if (a == "" && (h in na)) a = na[h]
    if (s == "") s = "-"
    if (a == "") a = "-"
    c = cc[p]; d = st[p]
    x = (d + 0 > c + 0)
    had = (p in pc)
    moved = (had && pc[p] != c && ps[p] != d)
    if (had) { n = pn[p] + 0; m = pm[p] + 0; f = pf[p] + 0; lg = pl[p] + 0 }
    else { n = 0; m = 0; f = 0; lg = 0 }
    if (n > 0 && now - lg > gap) { n = 0; if (m == 0) f = 0 }
    if (moved) {
      if (x) { n++; lg = now }
      else m++
    }
    else if (x) m = 0
    else { n = 0; m = 0 }
    if (n == 0 && m == 0 && !x) f = 0
    else if (f == 0) f = now
    printf "S %s %s %s %d %.0f %.0f %s %s %d\n", p, c, d, n, f, lg, s, a, m
    if (x && n >= row) printf "R %s %d %.0f %s %s\n", p, n, f, s, a
    else if (moved && !x && m >= rowb) printf "B %s %d %.0f %s %s\n", p, m, f, s, a
    else if (f > 0) printf "W %s %d/%d %.0f %s %s\n", p, n, m, f, s, a
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
_nNow=0
_newLines=()
_more=0
while read -r _t _p _n _f _s _a; do
  [[ -n "${_p}" ]] || continue
  _since="$(date -d "@${_f}" '+%F %H:%M' 2> /dev/null)"
  case "${_t}" in
    W)
      _say "WATCH prefix=${_p} site=${_s} account=${_a} rows=${_n}"
      continue
      ;;
    R)
      _say "FAULTY prefix=${_p} site=${_s} account=${_a} kind=thrown-away row=${_n} since=${_since}"
      _what="wrote Drupal's service container and threw it away again at ${_n} checks since ${_since:-unknown}: its own code invalidates the container while it serves requests, so each request pays for a full container build"
      _item="  ${_s} (account ${_a}): since ${_since:-unknown}, thrown away after it was written at ${_n} checks"
      ;;
    B)
      _say "FAULTY prefix=${_p} site=${_s} account=${_a} kind=rebuilt row=${_n} since=${_since}"
      _what="threw Drupal's service container away and compiled it again at ${_n} checks in a row since ${_since:-unknown}: something rebuilds the container while the site serves requests (its own code on every request, or all caches cleared again and again from its admin pages), so requests pay for full container builds"
      _item="  ${_s} (account ${_a}): since ${_since:-unknown}, rebuilt at ${_n} checks in a row"
      ;;
    *) continue ;;
  esac
  _nNow=$(( _nNow + 1 ))
  # the day's list for the mail: each site once, as first found that day
  if ! grep -q "^${_today}"$'\t'"${_p}"$'\t' "${_FOUND}"; then
    printf '%s\t%s\t%s\n' "${_today}" "${_p}" "${_item}" >> "${_FOUND}"
  fi
  # one log line a day per site; a site past the cap is named by a later check
  grep -qxF "${_today} ${_p}" "${_SEEN}" && continue
  if [[ "${#_newLines[@]}" -lt "${_MAX_SITES}" ]]; then
    echo "${_today} ${_p}" >> "${_SEEN}"
    _newLines+=("$(date) CONTAINER: ${_s} (account ${_a}, cache prefix ${_p}) ${_what}")
  else
    _more=$(( _more + 1 ))
  fi
done <<< "$(grep '^[RBW] ' <<< "${_out}" | sort -k5,5 -k2,2)"

for _l in "${_newLines[@]}"; do
  echo "${_l}" >> "${_pthOml}"
done
if [[ "${_more}" -gt 0 ]]; then
  echo "$(date) CONTAINER: and ${_more} more sites found by this check, not listed one by one (at most ${_MAX_SITES} a check)" >> "${_pthOml}"
fi

# keep a week of daily records
_keep="$(date -d '7 days ago' +%F 2> /dev/null)"
if [[ -n "${_keep}" ]] && [[ -s "${_SEEN}" ]]; then
  awk -v k="${_keep}" '$1 >= k' "${_SEEN}" > "${_SEEN}.new" \
    && mv -f "${_SEEN}.new" "${_SEEN}"
fi
if [[ -n "${_keep}" ]] && [[ -s "${_FOUND}" ]]; then
  awk -F'\t' -v k="${_keep}" '$1 >= k' "${_FOUND}" > "${_FOUND}.new" \
    && mv -f "${_FOUND}.new" "${_FOUND}"
fi

# The mail's list: every site found today so far, each once by its name and
# account (a migrated site can be found under its old and new prefixes).
_found=()
while IFS= read -r _l; do
  _found+=("${_l}")
done < <(awk -F'\t' -v d="${_today}" '$1 == d {
  k = $3; sub(/:.*/, "", k)
  if (!(k in s)) { s[k] = 1; print $3 }
}' "${_FOUND}" 2> /dev/null)
_nFound=${#_found[@]}
_moreMail=0
if [[ "${_nFound}" -gt "${_MAX_SITES}" ]]; then
  _moreMail=$(( _nFound - _MAX_SITES ))
  _found=("${_found[@]:0:${_MAX_SITES}}")
fi

_mail_body() {
  echo "Drupal's service container is compiled again and again on these sites of"
  echo "${_hName}, request after request. Each such request pays for a full"
  echo "container build: on one observed store about 0.9 seconds a request, for"
  echo "days, with nothing else showing it."
  echo
  printf '%s\n' "${_found[@]}"
  [[ "${_moreMail}" -gt 0 ]] && echo "  and ${_moreMail} more, not listed here"
  echo
  echo "How it was seen: BOA keeps each Drupal 8+ site's compiled container in"
  echo "Valkey, and the Redis module stamps the container cache each time a"
  echo "site throws its container away. At the checks counted, about ten minutes"
  echo "apart, the site's container and that stamp had both been written again"
  echo "since the check before. \"Thrown away\": the stamp was the newer, so the"
  echo "site's code calls the kernel's invalidateContainer() while it serves"
  echo "requests and the next request compiles the container again. \"Rebuilt\":"
  echo "the container was the newer at six checks in a row, so the container is"
  echo "thrown away and compiled again inside the site's requests: by its code on"
  echo "every request, or by someone clearing all caches from its admin pages again"
  echo "and again. A cache rebuild (drush cr, Flush all caches), a Verify, a"
  echo "Migrate or a Valkey restart, done once, never looks like this, and none of"
  echo "them fixes it."
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

# The mail: once a day at most, the sites found so far that day. A held one
# is tried again at the next check; a failed one waits for the next day.
_mailed="NO"
if [[ "${_nFound}" -gt 0 ]] && [[ "$(cat "${_MAILED}" 2> /dev/null)" != "${_today}" ]]; then
  _mail_way
  case "${_MAIL_WAY}" in
    held)
      _mailed="HELD"
      if [[ "${#_newLines[@]}" -gt 0 ]]; then
        echo "$(date) INFO: alert for ${_nFound} site(s) held back (a fresh boot, a BOA pass or the cooldown); the next check tries again" >> "${_pthOml}"
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
      if _mail_body | s-nail -s "Incident Report: Drupal container rebuilt on every request on ${_nFound} site(s) on ${_hName} at $(date)" ${_MY_EMAIL}; then
        _mailed="YES"
      else
        _mailed="FAILED"
        echo "$(date) INFO: the alert mail for ${_nFound} site(s) failed; the next day's check tries again" >> "${_pthOml}"
      fi
      ;;
  esac
fi
if [[ "${#_newLines[@]}" -gt 0 ]] || [[ "${_more}" -gt 0 ]]; then
  echo >> "${_pthOml}"
fi
_say "DONE faulty=${_nNow} new=${#_newLines[@]} more=${_more} mail=${_mailed} today=${_nFound}"

exit 0
