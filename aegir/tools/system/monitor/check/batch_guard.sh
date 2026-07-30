#!/bin/bash
#
# BOA batch storm guard — batch_guard v1.0.
#
# Detects and heals a LOCAL self-DoS: the background_process+background_batch
# module pair drives D7 batches via self-HTTP POSTs to
# /bgp-start/background_batch%3A<bid>/<token> from the box's OWN address.
# Under FPM saturation every POST times out (nginx 499), the module's cron
# integration re-launches every "stale" process each pass, and the loop feeds
# itself — an observed storm drove a 48-core box to load 87 while the database
# tier stayed healthy throughout. Edge bans are impossible by construction
# (csf refuses the box's own address, correctly), so the only lever is the
# transient batch state the loop feeds on: deleting the affected {batch} rows
# makes every re-launched POST exit immediately and the worker wall drains in
# minutes with no service restart.
#
# THE FALSE-POSITIVE RULE IS ABSOLUTE: killing a client's legitimate batch is
# worse than the storm. Every stage below must pass before any row is touched:
#
#   1. Arm gate: 1-min load at or above 1.0/core, else silent exit — the
#      guard is a no-op on every healthy box.
#   2. Volume: the box's OWN IPs (kernel v4 set + /root/.local.IP.list +
#      ${_MY_OWNIP}; loopback included — self-DoS via 127.0.0.1 counts the
#      same) answering 499 in the recent access-log window, over threshold.
#   3. Repetition: a bid POSTed to /bgp-start/ tens of times IS looping — a
#      legitimate background launch is one or two POSTs. Only looping bids
#      are ever candidates, and hits count only from the recent hours of
#      the window, so a long-lived quiet log can never accumulate a slow
#      trickle into a "loop". Browser-driven batches and update.php batches
#      never traverse /bgp-start/, so both are outside the kill-list by
#      construction (update.php shares the {batch} table AND its bid
#      sequence, and reaping one mid-flight would strand a site in
#      maintenance mode).
#   4. Attribution: the vhost named by the log line's $host maps to the site
#      db via its fastcgi_param db_name. Bids are per-db AUTO_INCREMENT
#      values and COLLIDE across sites, so per-bid attribution must come
#      from the vhost of the looping requests themselves; a candidate whose
#      host resolves to no db is skipped, never guessed. The candidate must
#      then BE a background_batch process in that db — a live
#      background_process row with handle 'background_batch:<bid>' is the
#      very flywheel the cron integration re-launches, so a genuine loop
#      always has one, while a browser/update.php batch never does. This is
#      also what defeats forged log lines: a request wall aimed at another
#      site's Host cannot make its batches loop-eligible.
#   5. Two-pass no-change confirmation: on first sight a candidate is only
#      RECORDED (batch blob length+MD5, queue count). It heals on a LATER
#      pass — at least eight minutes on, comfortably past any sane FPM
#      request wall, so a live batch has had every chance to write — only
#      if it is STILL looping in the fresh log window AND nothing about it
#      changed AND the web tier, the FPM masters and mysqld have all been
#      up continuously since the first sighting (a frozen interval proves a
#      teardown, not a death). Any change means progress, and progress
#      means hands off. {batch}.timestamp is write-once at creation (D7
#      updates only the blob), so age-based staleness can NEVER be a kill
#      criterion — a long-running live batch and an abandoned one carry
#      identical timestamps. Residual, accepted and bounded: a hostile
#      co-tenant with code execution can forge every log-side signal
#      (own-IP curl, victim Host, early close), but candidacy then still
#      needs the victim bid to be a REAL background_batch process whose
#      blob never moves across the whole confirmation span — and the prize
#      is the deletion of transient progress rows that alerts the operator
#      per site db and trips the breaker after three passes.
#
# The heal deletes the confirmed bid's {batch} row and its
# background_process row — per bid, never table-wide, and the {batch}
# DELETE is CONDITIONAL on the very fingerprint the confirmation measured
# (blob LENGTH + MD5 + queue count), so a batch that resumed in the gap
# between the probe and the heal keeps every row and the pass logs SKIPPED,
# not HEALED. The drupal_batch queue rows are deliberately LEFT: deleting
# them would only tighten the spin of a worker still holding the batch in
# memory, and core cron reaps orphaned drupal_batch rows on its own 10-day
# floor — inert leftovers, no loop. The affected user sees "No active
# batch." or a stalled progress bar and re-runs the action — acceptable for
# a loop that is provably dead. Sites with a D7 table prefix are skipped
# (no bare `batch` table), by design.
#
# LOAD SEMANTICS — a deliberate split. The guard ignores load LEVEL (the
# storm IS a high-load condition — a guard that waits for calm can never
# fire, and its heal is cheap SQL, not a restart). But it must never JUDGE
# on evidence gathered across a service teardown: BOA's own load auto-pause
# (second.sh) can stop nginx and force-quit every FPM pool, and the DB
# watchdog can restart mysqld — either freezes every batch blob on the box,
# so a live batch and a dead one look identical, which is exactly the
# inference this guard runs on. The defence is CONTINUITY WITNESSES, not
# the load-tier markers (/run/max_load.pid is a load classification that
# second.sh sets even on passes where it declines to pause — e.g. the
# backup/iowait exemption — so gating on it would disarm the guard for
# whole nights while the web tier serves normally): no candidate may
# confirm unless nginx and every FPM master have been up, and mysqld
# answering, since before its first sighting. Pidfile birth times and the
# server's own Uptime are the witnesses — nginx's survives reloads while
# FPM's moves even on a reload (php-fpm rewrites its pidfile on the
# SIGUSR2 re-exec, and a reload SIGKILLs in-flight workers after
# process_control_timeout, so that over-invalidation is load-bearing) —
# and every restart moves them, so a teardown that came and went entirely
# between two of our passes still invalidates the interval. The observed
# storm never
# touched the pause tiers (load 1.8/core against a 6.1/core threshold), so
# none of this costs anything on the incident the guard was built for.
#
# Own-IP detection is v4-only in v1 — no v6 own-IP precedent exists in this
# tree.
#
# Opt-outs (all overridable in /root/.barracuda.cnf):
#   _USE_BATCH_GUARD=NO          fully off (unset means ON)
#   _BATCH_GUARD_DETECT_ONLY=YES full detection, log + alert, zero deletes
#
# Operator validation (NB --force only skips the self-throttle — a confirmed
# storm still heals; --detect-only is the true dry run, applied AFTER the
# cnf is sourced so no config line can silently re-arm the heal under it):
#
#   bash batch_guard.sh --force --stdout --detect-only
#
# Conventions: BOA monitor sibling (cf. valkey.sh / sqlprobe.sh). No systemd.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthDat="/var/log/boa/batch_guard"
_STAMP="${_pthDat}/.last_run"
_CAND="${_pthDat}/.candidates"
_pthOml="/var/log/boa/batch_guard.incident.log"
_pthLdg="/var/log/boa/batch_guard.heal.ledger"
_pthLch="/run/boa_batch_guard_latched.pid"
_cd="/run/batch-guard.cooldown"
_ACCESS_LOG="/var/log/nginx/access.log"
_LOADAVG="/proc/loadavg"
# The window size is deliberately not a knob. At the observed storm's rate a
# stormed box writes thousands of lines a minute, so a window sized in
# thousands of lines is SECONDS wide and a hundred looping bids would split
# it to a handful of hits each — under the per-bid floor. Ten thousand lines
# keep the per-bid counts robust at that scale, and the hour-bound on
# counted hits (below) stops the same window from spanning days on a
# quieter box.
_TAIL_LINES=10000

_FORCE=NO
_STDOUT=NO
_CLI_DETECT_ONLY=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)       _FORCE=YES ;;
    --stdout)      _STDOUT=YES ;;
    --detect-only) _CLI_DETECT_ONLY=YES ;;
    -h|--help) echo "Usage: batch_guard.sh [--force] [--stdout] [--detect-only]"; exit 0 ;;
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
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# Opt-out: fully off when the operator says so (unset means ON).
[ "${_USE_BATCH_GUARD}" = "NO" ] && exit 0

# Major system transition in flight: stand down.
for _rt in excalibur daedalus chimaera beowulf; do
  [ -e "/root/.run-to-${_rt}.cnf" ] && exit 0
done

# Barracuda run in flight: it may restart mysqld under us.
[ -e "/run/boa_run.pid" ] && exit 0

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
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

mkdir -p "${_pthDat}"

# Self-throttle to ~5 min (minute.sh relaunches us every minute), unless
# --force. This tick is also the two-pass confirmation clock: a candidate
# recorded on one pass cannot heal before the next, so no batch is judged
# over less than a full FPM request lifetime.
if [ "${_FORCE}" != "YES" ] && [ -e "${_STAMP}" ] \
  && [ -z "$(find "${_STAMP}" -mmin +4 2>/dev/null)" ]; then
  exit 0
fi
touch "${_STAMP}"

###
### Knobs, every one operator-overridable from /root/.barracuda.cnf. The
### normaliser mirrors lock.inc's _flap_num (digits only, leading zeros
### stripped — bash reads a zero-padded number as octal inside $(( )), where
### 08 is a hard error) and is kept in-file so knob arithmetic never depends
### on which lock.inc a box happens to hold; the shared breaker primitives
### below stay command -v guarded for the same serial-skew reason.
###
_bg_num() {
  local _v="${1//[^0-9]/}"
  while [ "${#_v}" -gt 1 ] && [ "${_v:0:1}" = "0" ]; do
    _v="${_v:1}"
  done
  [ -n "${_v}" ] || _v="$2"
  printf '%s' "${_v}"
}

# The soak switch is normalised like every YES/NO knob: any case works, and
# anything that is not YES means the heal is live. The CLI flag wins over
# the cnf, deliberately and in one direction only — an operator asking for
# a dry run must GET a dry run, whatever the config says.
_BATCH_GUARD_DETECT_ONLY="${_BATCH_GUARD_DETECT_ONLY^^}"
_BATCH_GUARD_DETECT_ONLY="${_BATCH_GUARD_DETECT_ONLY//[^A-Z]/}"
[ "${_CLI_DETECT_ONLY}" = "YES" ] && _BATCH_GUARD_DETECT_ONLY=YES

_BATCH_GUARD_499_MIN=$(_bg_num "${_BATCH_GUARD_499_MIN}" 200)        # Own-IP 499 lines in the window that arm stage 2
_BATCH_GUARD_BID_MIN=$(_bg_num "${_BATCH_GUARD_BID_MIN}" 20)         # bgp-start POSTs per bid that mean LOOPING
_BATCH_GUARD_COOLDOWN_SECS=$(_bg_num "${_BATCH_GUARD_COOLDOWN_SECS}" 600) # Minimum gap between two heal passes

_BATCH_GUARD_FLAP_MAX=$(_bg_num "${_BATCH_GUARD_FLAP_MAX}" 3)        # Heal passes tolerated inside the window
# Zero would latch the breaker before the first legitimate heal could run.
[ "${_BATCH_GUARD_FLAP_MAX}" -lt 1 ] && _BATCH_GUARD_FLAP_MAX=1

_BATCH_GUARD_FLAP_WINDOW_SECS=$(_bg_num "${_BATCH_GUARD_FLAP_WINDOW_SECS}" 7200) # Window those heals are counted in
# The window has to be wide enough to still hold _BATCH_GUARD_FLAP_MAX heals
# at the pace they actually land, or the oldest entry ages out before the
# breaker can count it and the circuit never opens — silently. Heals here
# quantise to the 5-minute self-throttle tick on top of the cooldown, so the
# slack per heal is minutes, not seconds — the same four minutes the database
# and cache watchdogs allow, and it must clear the achievable pace strictly,
# because the ledger's window test drops an entry that lands exactly on the
# boundary.
_BATCH_GUARD_FLAP_FLOOR=$(( _BATCH_GUARD_FLAP_MAX * (_BATCH_GUARD_COOLDOWN_SECS + 240) ))
if [ "${_BATCH_GUARD_FLAP_WINDOW_SECS}" -lt "${_BATCH_GUARD_FLAP_FLOOR}" ]; then
  _BATCH_GUARD_FLAP_WINDOW_SECS="${_BATCH_GUARD_FLAP_FLOOR}"
fi

_BATCH_GUARD_FLAP_LATCH_MINS=$(_bg_num "${_BATCH_GUARD_FLAP_LATCH_MINS}" 60) # Cool-off before an open circuit re-arms

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
  local _subject="${1:-(no subject)}"
  local _lvl="${2:-INFO}"
  _lvl="${_lvl^^}"
  [ -n "${_MY_EMAIL}" ] || return 1
  # The severity ladder, applied to what this guard can say:
  #   ALERT == the circuit breaker latched: the guard has stopped acting and
  #            an operator is the only way forward.
  #   MINI  == a storm was healed (or, in detect-only mode, confirmed). The
  #            default reporting level hears about this now: rows were
  #            deleted from a client site's database, and that must never
  #            be something an operator learns from the load graphs.
  #   INFO  == routine notices, ALL only.
  case "${_INCIDENT_REPORT}" in
    OFF)  return 1 ;;
    CRIT) [ "${_lvl}" = "ALERT" ] || return 1 ;;
    MINI) [ "${_lvl}" = "ALERT" ] || [ "${_lvl}" = "MINI" ] || return 1 ;;
    ALL)  : ;;
  esac
  # One alert per cooldown per KEY. Confirmed storms alert per site db, so
  # two sites can each say so once; the circuit-breaker page keeps its own
  # key by construction so a heal notice can never hold it back. An older
  # lock.inc without the helper sends as before.
  local _sfx=""
  local _key="${3:-}"
  if [ -z "${_key}" ]; then
    if [ "${_lvl}" = "ALERT" ]; then
      _key="batch-alert"
    else
      _key="batch"
    fi
  fi
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    if ! _incident_email_ratelimit "${_key}"; then
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

###
### Stage 1 — arm gate. A sub-load loop is not an incident: below 1.0/core
### the guard exits without reading a single log line, so on every healthy
### box on the fleet it costs one /proc read per tick.
###
_CORES=$(nproc 2>/dev/null)
_CORES=$(_bg_num "${_CORES}" 1)
_LOAD1=$(awk '{print $1}' "${_LOADAVG}" 2>/dev/null)
if ! awk -v l="${_LOAD1:-0}" -v c="${_CORES}" 'BEGIN { exit !(l >= c) }'; then
  _say "DISARMED load=${_LOAD1:-0} cores=${_CORES}"
  exit 0
fi
_say "ARMED load=${_LOAD1} cores=${_CORES}"

# mysqld must be answering: the confirmation and the heal are both SQL, and
# database downtime is mysql.sh's business, not ours.
if [ ! -S "/run/mysqld/mysqld.sock" ] && [ ! -S "/var/run/mysqld/mysqld.sock" ]; then
  exit 0
fi

# DB-mutation stand-down (the shared family gate): while move_sql.sh or the
# database watchdog holds a restart in flight, this guard's probes would
# race the restart and its heal could land mid-recovery. Both markers are
# needed — move_sql.sh holds the restart one per PHASE, the heal marker
# covers the gap between phases. A marker older than the bound is a leak
# (clear.sh reaps those), not a live mutation, and is ignored.
_SQL_MUTATION_MAX_MINS="${_SQL_MUTATION_MAX_MINS//[^0-9]/}"
[ -n "${_SQL_MUTATION_MAX_MINS}" ] || _SQL_MUTATION_MAX_MINS=15
for _mk in /run/mysql_restart_running.pid /run/boa_mysql_auto_healing.pid; do
  if [ -e "${_mk}" ] \
    && [ -z "$(find "${_mk}" -mmin "+${_SQL_MUTATION_MAX_MINS}" 2>/dev/null)" ]; then
    _say "STAND-DOWN marker=${_mk}"
    exit 0
  fi
done

###
### Stage 2 — the box's own addresses answering 499. The own-IP set is the
### kernel's v4 addresses (loopback included), the operator-maintained
### /root/.local.IP.list, and ${_MY_OWNIP} from barracuda.cnf. NEVER an
### external resolver: a monitor must not depend on the outside world to
### recognise the box it runs on.
###
_LOCAL_IPS=()
_load_local_ips() {
  local _ip
  while IFS= read -r _ip; do
    [[ -n "${_ip}" ]] && _LOCAL_IPS+=("${_ip}")
  done < <(ip -4 addr show | grep -oE 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}')
  if [[ -f "/root/.local.IP.list" ]]; then
    while IFS= read -r _ip; do
      _ip="${_ip%%#*}"
      _ip="${_ip//[[:space:]]/}"
      [[ "${_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && _LOCAL_IPS+=("${_ip}")
    done < /root/.local.IP.list
  fi
  [[ "${_MY_OWNIP:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && _LOCAL_IPS+=("${_MY_OWNIP}")
}
_load_local_ips
if [ "${#_LOCAL_IPS[@]}" -eq 0 ]; then
  _say "NO-OWN-IPS"
  exit 0
fi

###
### Stages 2+3 in one pass over the recent window. The vhost log format puts
### the client in field 1 as "$remote_addr" and the vhost in field 2 as
### $host, so splitting on double quotes is stable: $2=client, $3 carries
### "host [time]", $4=request, $5 starts with the status. nginx escapes any
### quote inside the logged request, referer and UA, so the split cannot be
### fooled by request content. Two time bounds, both in nginx time_local
### form with LC_ALL=C pinning the English month names nginx always logs:
### counted hits must fall inside the last three clock HOURS (so a quiet
### box's window, which can span days of lines, can never accumulate a slow
### trickle into a "loop"), and the fresh set is the last eight wall-clock
### MINUTES — a bid may only heal while it is STILL looping, not on the
### memory of a storm that already ended.
###
_FRESH_RE=""
for _i in 0 1 2 3 4 5 6 7; do
  _m=$(LC_ALL=C date -d "-${_i} min" '+%d/%b/%Y:%H:%M' 2>/dev/null)
  [ -n "${_m}" ] && _FRESH_RE="${_FRESH_RE}|${_m}"
done
_FRESH_RE="${_FRESH_RE#|}"
_HOURS_RE=""
for _i in 0 1 2; do
  _m=$(LC_ALL=C date -d "-${_i} hour" '+%d/%b/%Y:%H' 2>/dev/null)
  [ -n "${_m}" ] && _HOURS_RE="${_HOURS_RE}|${_m}"
done
_HOURS_RE="${_HOURS_RE#|}"
if [ -z "${_FRESH_RE}" ] || [ -z "${_HOURS_RE}" ]; then
  # Without the time bounds no confirmation is safe; refuse loudly rather
  # than silently, because a guard that cannot fire should say so once.
  echo "$(date) WARN: date -d unavailable, time bounds empty -- batch_guard cannot confirm anything on this box" >> ${_pthOml}
  _say "NO-TIME-BOUNDS"
  exit 0
fi

_SCAN=$(tail -n "${_TAIL_LINES}" "${_ACCESS_LOG}" 2>/dev/null | awk -F'"' \
  -v ips=" ${_LOCAL_IPS[*]} " -v fre="${_FRESH_RE}" -v hre="${_HOURS_RE}" '
  {
    ip = $2
    if (index(ips, " " ip " ") == 0) next
    # A request riding the wild-ssl local 443 front logs TWICE: once on the
    # front (real client) and once on the port-80 backend (client 127.0.0.1,
    # xff carrying the front chain plus the loopback hop — always a comma).
    # Skip only that proxied duplicate; a genuine direct-to-loopback
    # self-POST has a single-token xff and stays counted.
    if (ip == "127.0.0.1" && $0 ~ /xff="[^"]*,/) next
    split($5, st, " ")
    if (st[1] != "499") next
    n = split($3, h3, " ")
    host = h3[1]
    t = h3[2]; sub(/^\[/, "", t)
    if (substr(t, 1, 14) !~ "^(" hre ")") next
    total++
    if ($4 !~ /^POST \/bgp-start\/background_batch%3[Aa][0-9]+\//) next
    split($4, rq, " ")
    bid = rq[2]
    sub(/^\/bgp-start\/background_batch%3[Aa]/, "", bid)
    sub(/\/.*$/, "", bid)
    if (bid !~ /^[0-9]+$/) next
    if (host !~ /^[a-zA-Z0-9.-]+$/) next
    key = host " " bid
    hits[key]++
    if (substr(t, 1, 17) ~ "^(" fre ")") fresh[key]++
  }
  END {
    printf "TOTAL %d\n", total + 0
    for (k in hits)  printf "BID %s %d\n", k, hits[k]
    for (k in fresh) printf "FRESH %s %d\n", k, fresh[k]
  }')

_TOTAL499=$(printf '%s\n' "${_SCAN}" | awk '$1 == "TOTAL" { print $2; exit }')
_TOTAL499=$(_bg_num "${_TOTAL499}" 0)
_say "TOTAL499=${_TOTAL499} min=${_BATCH_GUARD_499_MIN}"
if [ "${_TOTAL499}" -lt "${_BATCH_GUARD_499_MIN}" ]; then
  # Not a storm. Discard any recorded candidates rather than let them age:
  # confirmation must come from two passes of the SAME storm, so a lull
  # resets the clock — the conservative direction, it can only delay a heal.
  rm -f "${_CAND}"
  exit 0
fi

###
### Stage 4 — attribution. The vhost file named by $host carries the site db
### as fastcgi_param db_name; the identifier is allowlisted before it can
### reach a query. Hostmaster-style docroots are skipped the way the backup
### tooling skips them. A live processlist probe is logged as corroboration
### only — bids collide across dbs, so it must never attribute.
###
_is_safe_ident() {
  [[ "${1}" =~ ^[A-Za-z0-9_]+$ ]]
}

_db_for_host() {
  # Probed in nginx's own parse order (platform.d/oN.conf — each Octopus
  # instance's vhost.d — is included BEFORE the master's vhost.d, and the
  # first-defined server wins a duplicate server_name), so a unique answer
  # names the vhost that actually served. A host answered by MORE than one
  # db across the roots is ambiguous — skip, never guess: healing the wrong
  # db on a colliding bid is the exact hazard attribution exists to prevent.
  local _host="$1" _vf _db _found=""
  for _vf in /data/disk/*/config/server_master/nginx/vhost.d/"${_host}" \
    "/var/aegir/config/server_master/nginx/vhost.d/${_host}"; do
    [ -f "${_vf}" ] || continue
    if grep -qE "root[[:space:]]+/data/disk/.*/aegir/distro/" "${_vf}"; then
      continue
    fi
    if grep -q "fastcgi_param db_name" "${_vf}"; then
      _db=$(grep -m1 "fastcgi_param db_name" "${_vf}" | awk '{print $NF}' | tr -d ';')
      if [ -z "${_found}" ]; then
        _found="${_db}"
      elif [ "${_db}" != "${_found}" ]; then
        echo "$(date) WARN: ${_host} maps to more than one db across vhost roots (${_found} vs ${_db}); skipped -- run vhostcheck" >> ${_pthOml}
        return 1
      fi
    fi
  done
  [ -n "${_found}" ] || return 1
  printf '%s' "${_found}"
  return 0
}

# The flywheel precondition: a genuine background_batch loop always has a
# background_process row with this handle — that row is the very thing the
# module's cron integration re-launches — while a browser or update.php
# batch never does. Requiring it makes those structurally unreachable AND
# defeats forged log lines: a hostile tenant curling its own box with
# another site's Host cannot make that site's batches loop-eligible. A
# query failure reads as "no flywheel"; fewer candidates is the safe
# direction.
_bp_is_flywheel() {
  local _db="$1" _bid="$2" _n
  _n=$(timeout 10 mysql -u root -Nse \
    "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '${_db}' AND TABLE_NAME = 'background_process'" 2>/dev/null)
  [ "$(_bg_num "${_n}" 0)" -gt 0 ] || return 1
  _n=$(timeout 10 mysql -u root -Nse \
    "SELECT COUNT(*) FROM \`${_db}\`.\`background_process\` WHERE handle = 'background_batch:${_bid}'" 2>/dev/null)
  [ "$(_bg_num "${_n}" 0)" -gt 0 ] || return 1
  return 0
}

# Current per-bid state: prints "<len> <md5> <qcount>". Return codes:
#   0  state read;
#   1  the bid has no {batch} row (candidacy over — every re-launched POST
#      already exits immediately), or the blob is NULL (nothing genuine
#      writes one, and the fingerprint heal could never match it);
#   2  the probe itself failed (timeout, connection, no bare `batch` table)
#      and says NOTHING about the batch — the caller keeps its recorded
#      state and waits instead of forgetting it.
_probe_batch_state() {
  local _db="$1" _bid="$2" _row _qn _len _md5
  _row=$(timeout 10 mysql -u root -Nse \
    "SELECT LENGTH(batch), MD5(batch) FROM \`${_db}\`.\`batch\` WHERE bid = ${_bid}" 2>/dev/null)
  [ "$?" -eq 0 ] || return 2
  [ -n "${_row}" ] || return 1
  _qn=$(timeout 10 mysql -u root -Nse \
    "SELECT COUNT(*) FROM \`${_db}\`.\`queue\` WHERE name LIKE 'drupal_batch:${_bid}:%'" 2>/dev/null)
  # A failed count is a failed probe, never a real zero: the zero is
  # load-bearing in the no-change comparison.
  [ -n "${_qn}" ] || return 2
  _qn=$(_bg_num "${_qn}" 0)
  _len=$(printf '%s' "${_row}" | cut -f1)
  _md5=$(printf '%s' "${_row}" | cut -f2)
  [ "${_md5}" = "NULL" ] && return 1
  printf '%s %s %s' "${_len}" "${_md5}" "${_qn}"
  return 0
}

_now=$(date +%s)
# Continuity witnesses (see the header's load-semantics note). Masters write
# their pidfiles once, at start, and reloads keep them — so the NEWEST birth
# time across nginx and every FPM master is when the serving tier was last
# torn down, and the server-reported Uptime is mysqld's. A candidate may
# only confirm if all three have been up since before its sighting was
# recorded; any restart between the two passes moves a stamp forward and
# invalidates the interval, even when the teardown came and went entirely
# between our ticks. nginx's pidfile must exist at all (0 = web down or
# unreadable = no confirmation — fail-safe).
_WEB_UP_SINCE=$(stat -c %Y /run/nginx.pid 2>/dev/null)
_WEB_UP_SINCE=$(_bg_num "${_WEB_UP_SINCE}" 0)
if [ "${_WEB_UP_SINCE}" -gt 0 ]; then
  for _pf in /run/php*-fpm.pid; do
    [ -e "${_pf}" ] || continue
    _pfm=$(_bg_num "$(stat -c %Y "${_pf}" 2>/dev/null)" 0)
    [ "${_pfm}" -gt "${_WEB_UP_SINCE}" ] && _WEB_UP_SINCE="${_pfm}"
  done
fi
_DB_UPT=$(timeout 10 mysql -u root -Nse "SHOW GLOBAL STATUS LIKE 'Uptime'" 2>/dev/null | cut -f2)
_DB_UPT=$(_bg_num "${_DB_UPT}" 0)
if [ "${_DB_UPT}" -gt 0 ]; then
  _DB_UP_SINCE=$(( _now - _DB_UPT ))
else
  # Unreadable uptime reads as "restarted just now": nothing confirms.
  _DB_UP_SINCE="${_now}"
fi
_CONFIRMED=""
_NEWSTATE=""
_RESTAMPED=0

while read -r _tag _host _bid _hits; do
  [ "${_tag}" = "BID" ] || continue
  _hits=$(_bg_num "${_hits}" 0)
  [ "${_hits}" -ge "${_BATCH_GUARD_BID_MIN}" ] || continue
  _fresh=$(printf '%s\n' "${_SCAN}" | awk -v h="${_host}" -v b="${_bid}" \
    '$1 == "FRESH" && $2 == h && $3 == b { print $4; exit }')
  _fresh=$(_bg_num "${_fresh}" 0)
  _say "CANDIDATE host=${_host} bid=${_bid} hits=${_hits} fresh=${_fresh}"
  if ! _db=$(_db_for_host "${_host}"); then
    _say "SKIP bid=${_bid} reason=no-vhost-db"
    echo "$(date) WARN: looping bid ${_bid} on ${_host} has no resolvable site db; skipped" >> ${_pthOml}
    continue
  fi
  if ! _is_safe_ident "${_db}"; then
    _say "SKIP bid=${_bid} reason=unsafe-ident"
    echo "$(date) WARN: unsafe db identifier for ${_host}; skipped" >> ${_pthOml}
    continue
  fi
  if ! _bp_is_flywheel "${_db}" "${_bid}"; then
    _say "SKIP bid=${_bid} reason=no-flywheel"
    continue
  fi
  _cur=$(_probe_batch_state "${_db}" "${_bid}")
  _prc=$?
  if [ "${_prc}" -eq 2 ]; then
    # The probe said nothing about the batch; keep any recorded sighting so
    # a loaded mysqld cannot make the guard forget a half-confirmed storm.
    _prev=$(grep -F -m1 " ${_host} ${_db} ${_bid} " "${_CAND}" 2>/dev/null)
    if [ -n "${_prev}" ]; then
      _pts=$(_bg_num "${_prev%% *}" 0)
      if [ $(( _now - _pts )) -le 3600 ]; then
        _NEWSTATE="${_NEWSTATE}${_prev}"$'\n'
        _say "HELD db=${_db} bid=${_bid} reason=probe-failed"
        continue
      fi
    fi
    _say "SKIP bid=${_bid} reason=probe-failed"
    continue
  fi
  if [ "${_prc}" -ne 0 ]; then
    _say "SKIP bid=${_bid} reason=no-batch-row"
    continue
  fi
  read -r _len _md5 _qn <<< "${_cur}"
  _prev=$(grep -F -m1 " ${_host} ${_db} ${_bid} " "${_CAND}" 2>/dev/null)
  if [ -n "${_prev}" ]; then
    read -r _pts _phost _pdb _pbid _plen _pmd5 _pqn <<< "${_prev}"
    _pts=$(_bg_num "${_pts}" 0)
    _age=$(( _now - _pts ))
    if [ "${_plen}" = "${_len}" ] && [ "${_pmd5}" = "${_md5}" ] \
      && [ "${_pqn}" = "${_qn}" ]; then
      if [ "${_WEB_UP_SINCE}" -eq 0 ] || [ "${_WEB_UP_SINCE}" -ge "${_pts}" ]; then
        # The web tier restarted (or is down) since this sighting: the
        # no-change interval proves a pause, not a death. Start it over.
        _say "RECORDED db=${_db} bid=${_bid} reason=web-restart"
        _RESTAMPED=$(( _RESTAMPED + 1 ))
        _NEWSTATE="${_NEWSTATE}${_now} ${_host} ${_db} ${_bid} ${_len} ${_md5} ${_qn}"$'\n'
      elif [ "${_DB_UP_SINCE}" -ge "${_pts}" ]; then
        # mysqld restarted since this sighting: the blobs were frozen for
        # part of the interval, so it proves nothing. Start it over.
        _say "RECORDED db=${_db} bid=${_bid} reason=db-restart"
        _RESTAMPED=$(( _RESTAMPED + 1 ))
        _NEWSTATE="${_NEWSTATE}${_now} ${_host} ${_db} ${_bid} ${_len} ${_md5} ${_qn}"$'\n'
      elif [ "${_age}" -ge 480 ] && [ "${_age}" -le 3600 ] && [ "${_fresh}" -ge 1 ]; then
        # Still looping, nothing moved across two full ticks of
        # uninterrupted service — longer than any sane FPM request wall, so
        # a batch alive inside a single long operation has had its request
        # boundary and its chance to write: dead. The full fingerprint
        # rides along so the heal can be conditional on all three values.
        _say "CONFIRMED db=${_db} bid=${_bid} age=${_age}"
        _CONFIRMED="${_CONFIRMED}${_host} ${_db} ${_bid} ${_hits} ${_len} ${_md5} ${_qn}"$'\n'
        _NEWSTATE="${_NEWSTATE}${_pts} ${_host} ${_db} ${_bid} ${_len} ${_md5} ${_qn}"$'\n'
      else
        # Unchanged but not yet judgeable (too young, too stale, or not in
        # the fresh window): keep the original sighting and wait.
        if [ "${_age}" -le 3600 ]; then
          _say "HELD db=${_db} bid=${_bid} age=${_age} fresh=${_fresh}"
          _NEWSTATE="${_NEWSTATE}${_pts} ${_host} ${_db} ${_bid} ${_len} ${_md5} ${_qn}"$'\n'
        else
          _say "RECORDED db=${_db} bid=${_bid} reason=stale-entry"
          _NEWSTATE="${_NEWSTATE}${_now} ${_host} ${_db} ${_bid} ${_len} ${_md5} ${_qn}"$'\n'
        fi
      fi
    else
      # It progressed — that is a live batch fighting through the storm.
      # Record the new state; hands off.
      _say "RECORDED db=${_db} bid=${_bid} reason=progressed"
      _NEWSTATE="${_NEWSTATE}${_now} ${_host} ${_db} ${_bid} ${_len} ${_md5} ${_qn}"$'\n'
    fi
  else
    _say "RECORDED db=${_db} bid=${_bid} reason=first-sight"
    _NEWSTATE="${_NEWSTATE}${_now} ${_host} ${_db} ${_bid} ${_len} ${_md5} ${_qn}"$'\n'
  fi
done <<< "$(printf '%s\n' "${_SCAN}" | grep '^BID ')"

# A service restart resetting confirmation clocks is worth one loud line
# per pass: a tier that keeps restarting faster than the confirmation floor
# would otherwise keep the guard silently unable to fire through a storm.
if [ "${_RESTAMPED}" -gt 0 ]; then
  echo "$(date) INFO: ${_RESTAMPED} candidate sighting(s) re-stamped -- a service restarted inside the confirmation interval" >> ${_pthOml}
fi

# Rewrite the state atomically: only current candidates survive, so a bid
# that stopped looping (or a finished storm) leaves nothing behind.
if [ -n "${_NEWSTATE}" ]; then
  printf '%s' "${_NEWSTATE}" > "${_CAND}.tmp" && mv -f "${_CAND}.tmp" "${_CAND}"
else
  rm -f "${_CAND}"
fi

[ -n "${_CONFIRMED}" ] || exit 0

# Corroboration for the record, never attribution: the busiest db seen
# running drupal_batch queue reads right now.
_PROC_DB=$(timeout 10 mysql -u root -Nse \
  "SELECT db FROM information_schema.processlist WHERE info LIKE '%drupal_batch%' AND db IS NOT NULL LIMIT 1" 2>/dev/null)

echo "$(date) Batch storm confirmed: own-IP 499s=${_TOTAL499} (threshold ${_BATCH_GUARD_499_MIN}), load ${_LOAD1} on ${_CORES} cores, processlist db hint: ${_PROC_DB:-none}" >> ${_pthOml}

###
### Detect-only: everything above ran, nothing below will. The operator soak
### switch — alerts carry exactly what a heal would have done.
###
if [ "${_BATCH_GUARD_DETECT_ONLY}" = "YES" ]; then
  while read -r _host _db _bid _hits _len _md5 _qn; do
    [ -n "${_bid}" ] || continue
    _say "DETECT-ONLY db=${_db} bid=${_bid}"
    echo "$(date) DETECT-ONLY: would heal looping batch bid ${_bid} (${_hits} bgp-start POSTs) in db ${_db} [${_host}]" >> ${_pthOml}
    _incident_email_report "Batch storm confirmed in ${_db} (detect-only, nothing deleted)" "MINI" "batch-${_db}"
  done <<< "${_CONFIRMED}"
  echo >> ${_pthOml}
  exit 0
fi

###
### Heal gate — cheapest refusal first: an open circuit refuses everything; a
### heal inside the cooldown waits; a heal that would overrun the flap budget
### latches the circuit, pages once on its own key, and stops the run.
### Passing the gate records the pass in the ledger BEFORE acting, so a heal
### that ends this script still leaves evidence for the breaker. The shared
### primitives are command -v guarded: a box holding a new batch_guard.sh
### against an old lock.inc degrades to cooldown-only pacing, never to a
### half-armed breaker.
###
if command -v _flap_breaker_is_open >/dev/null 2>&1; then
  if _flap_breaker_is_open "${_pthLch}" "${_BATCH_GUARD_FLAP_LATCH_MINS}" \
    "${_pthLdg}" "${_pthOml}"; then
    echo "$(date) batch storm: CIRCUIT OPEN, heal refused -- see ${_pthLch}" >> ${_pthOml}
    echo >> ${_pthOml}
    _say "REFUSED reason=circuit-open"
    exit 0
  fi
fi
if [ -s "${_cd}" ]; then
  _ts=$(tr -dc '0-9' < "${_cd}" 2>/dev/null)
  if [ -n "${_ts}" ]; then
    _gap=$(( _now - _ts ))
    # A negative gap means the clock stepped backwards: treat the stamp as
    # unusable and act, instead of freezing the guard until it catches up.
    if [ "${_gap}" -ge 0 ] && [ "${_gap}" -lt "${_BATCH_GUARD_COOLDOWN_SECS}" ]; then
      echo "$(date) INFO: storm confirmed but in cooldown (${_gap}s < ${_BATCH_GUARD_COOLDOWN_SECS}s); skipping heal" >> ${_pthOml}
      _say "REFUSED reason=cooldown gap=${_gap}"
      exit 0
    fi
  fi
fi
if command -v _flap_prune_ledger >/dev/null 2>&1; then
  _flap_prune_ledger "${_pthLdg}" "${_now}" "${_BATCH_GUARD_FLAP_WINDOW_SECS}"
  if [ "${_FLAP_COUNT}" -ge "${_BATCH_GUARD_FLAP_MAX}" ]; then
    # The latch carries the whole state of the breaker; the history that
    # opened it goes with it, so any re-arm starts counting at zero.
    echo "$(date) CIRCUIT OPEN: ${_FLAP_COUNT} batch-storm heals in the last ${_BATCH_GUARD_FLAP_WINDOW_SECS} seconds, so the automatic heal is now disabled. Fix the storm's cause (the site's background_process configuration), then delete this file to re-arm it; it also re-arms on its own ${_BATCH_GUARD_FLAP_LATCH_MINS} minutes after this stamp." > "${_pthLch}"
    rm -f "${_pthLdg}"
    echo "$(date) batch storm: CIRCUIT OPEN after ${_FLAP_COUNT} heals within ${_BATCH_GUARD_FLAP_WINDOW_SECS}s -- refusing further automatic heals" >> ${_pthOml}
    _incident_email_report "CIRCUIT OPEN: batch storm auto-heal disabled after ${_FLAP_COUNT} heals" "ALERT" "batch-circuit"
    echo >> ${_pthOml}
    _say "REFUSED reason=circuit-latched"
    exit 0
  fi
  echo "${_now}" >> "${_pthLdg}"
fi

###
### The heal — per confirmed bid, never table-wide, and CONDITIONAL: the
### {batch} DELETE carries the confirmed fingerprint in its WHERE clause, so
### a batch that moved at any point between the probe and this statement —
### the measure-then-act gap grows with the candidate count on a loaded box
### — matches nothing and keeps every row. Only a genuine {batch} delete
### unlocks the background_process delete; the outcome is logged as what it
### actually was. Deleting the {batch} row severs the loop (every
### re-launched POST finds no batch and exits). No FPM restart: the observed
### storm drained in two minutes on row deletion alone.
###
touch /run/boa_batch_guard_auto_healing.pid
_HEALED_DBS=""
while read -r _host _db _bid _hits _len _md5 _qn; do
  [ -n "${_bid}" ] || continue
  _len="${_len//[^0-9]/}"
  _md5="${_md5//[^0-9a-fA-F]/}"
  _qn="${_qn//[^0-9]/}"
  if [ -z "${_len}" ] || [ -z "${_md5}" ] || [ -z "${_qn}" ]; then
    _say "SKIPPED db=${_db} bid=${_bid} reason=bad-fingerprint"
    continue
  fi
  _del=$(timeout 30 mysql -u root -Nse \
    "DELETE FROM \`${_db}\`.\`batch\` WHERE bid = ${_bid} AND LENGTH(batch) = ${_len} AND MD5(batch) = '${_md5}' AND (SELECT COUNT(*) FROM \`${_db}\`.\`queue\` WHERE name LIKE 'drupal_batch:${_bid}:%') = ${_qn}; SELECT ROW_COUNT();" 2>/dev/null)
  _del=$(_bg_num "${_del}" 0)
  if [ "${_del}" -lt 1 ]; then
    echo "$(date) SKIPPED: batch bid ${_bid} in db ${_db} not deleted -- it changed or vanished since confirmation, or the delete could not run; left untouched" >> ${_pthOml}
    _say "SKIPPED db=${_db} bid=${_bid} reason=changed-since-confirm"
    continue
  fi
  # The flywheel row goes with the batch row; the queue rows deliberately
  # do NOT. Deleting them would only tighten the spin of a worker that is
  # somehow still holding the batch in memory, and core cron reaps orphaned
  # drupal_batch rows on its own 10-day floor — inert leftovers, no loop.
  timeout 30 mysql -u root <<EOFMYSQL 2>/dev/null
DELETE FROM \`${_db}\`.\`background_process\` WHERE handle = 'background_batch:${_bid}';
EOFMYSQL
  echo "$(date) HEALED: deleted looping batch bid ${_bid} (${_hits} bgp-start POSTs in the window) from db ${_db} [${_host}]" >> ${_pthOml}
  _say "HEALED db=${_db} bid=${_bid}"
  if ! [[ " ${_HEALED_DBS} " == *" ${_db} "* ]]; then
    _HEALED_DBS="${_HEALED_DBS}${_db} "
  fi
  # Drop the healed bid from the recorded state.
  if [ -e "${_CAND}" ]; then
    grep -vF " ${_host} ${_db} ${_bid} " "${_CAND}" > "${_CAND}.tmp" 2>/dev/null
    mv -f "${_CAND}.tmp" "${_CAND}"
  fi
done <<< "${_CONFIRMED}"
rm -f /run/boa_batch_guard_auto_healing.pid

# Hold the next heal off for the cooldown window. Stamped after the action so
# the gap is measured from when this heal finished.
date +%s > "${_cd}"

for _db in ${_HEALED_DBS}; do
  _incident_email_report "Batch storm healed: looping batches cleared in ${_db}" "MINI" "batch-${_db}"
done
echo >> ${_pthOml}

exit 0
