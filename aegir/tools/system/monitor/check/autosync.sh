#!/bin/bash
#
# BOA standing-mirror file cadence — autosync v1.0.
#
# The database half of a replication mirror is continuously current (GTID
# replication); this driver closes the file half. While an operator has armed
# `xmass autosync <target-ip>` on the ACTIVE box (marker
# /root/.xmass.autosync.cnf), it repeats the exact leg set of
# `xmass sync --live` against the recorded target at the armed cadence, so a
# standing mirror's files stay minutes — not days — behind its database.
#
# Division of labour is deliberate: this file owns only the CADENCE (the
# per-minute launch, the self-throttle, the pass timeout, the log, the
# incident mail, the staleness alarm). Every safety decision lives in
# `xmass autosync --run` itself, which re-checks phase, roles, the
# single-flight owner-PID lock (never flock — xmass restarts daemons that
# would inherit the fd), live barracuda/octopus evidence, and the target's
# standby marker, and stands down or defers on its own. So an operator
# invoking the verb by hand gets identical safety with or without this
# driver, and this file carries no second copy of any gate to drift.
#
# One-way, active -> mirror, controlled by the active (the 2026-08-25 rule:
# nothing moves a mirror out of sync except the active server). This driver
# therefore refuses to run on a box that is itself a standby or a finalized
# proxy — an armed marker there is an anomaly worth one daily latched warning
# WITH one daily mail, never a sync.
#
# A deferred pass is SILENT and cheap by design (another xmass verb holds the
# lock, an upgrade is in flight, the cutover window is open): the next tick
# retries. A FAILED pass is loud: rc != 0 lands in the incident log and mails
# through the standard throttle. And because every silent-defer class must
# still surface eventually, the driver alarms — daily, latched — whenever the
# last COMPLETED pass is older than six cadences: a silently parked file sync
# is exactly the de-sync this feature exists to close.
#
# Opt-outs / knobs (all overridable in /root/.barracuda.cnf):
#   _USE_XMASS_AUTOSYNC=NO       fully off (unset means ON; the marker is the
#                                real switch — no marker, no work)
#   _XMASS_AUTOSYNC_TIMEOUT=21600  hard ceiling per pass in seconds (a hung
#                                ssh/rsync must not hold the slot forever; a
#                                killed pass is safe — the legs are idempotent
#                                delta rsync, the lock's signal trap exits,
#                                and the next tick resumes the delta)
#
# The cadence itself is per pair, not per box: _XMASS_AUTOSYNC_EVERY minutes
# in the marker, written by `xmass autosync <target-ip> --every=N`.
#
# Operator validation (--force only skips the self-throttle):
#
#   bash autosync.sh --force --stdout
#
# Conventions: BOA monitor sibling (cf. task_guard.sh / batch_guard.sh).

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthDat="/var/log/boa/xmass_autosync"
_STAMP="${_pthDat}/.last_run"
_pthOml="/var/log/boa/autosync.incident.log"
_pthSyncLog="/var/log/boa/xmass.autosync.log"
_AS_CNF="/root/.xmass.autosync.cnf"
_AS_STATUS="/var/log/boa/xmass.autosync.status"
# Pass duration lives HERE, in the driver, not in the status file: the status
# file is written only by a COMPLETED pass, so a pass killed at the timeout
# ceiling would leave the guard reasoning from a stale short duration -- the
# exact case where resting matters most.
_AS_DURFILE="${_pthDat}/.last_duration"

_FORCE=NO
_STDOUT=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)  _FORCE=YES ;;
    --stdout) _STDOUT=YES ;;
    -h|--help) echo "Usage: autosync.sh [--force] [--stdout]"; exit 0 ;;
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

# No marker, no work — the cheap gate that keeps this a single test on the
# entire fleet (minute.sh also pre-gates the launch on the same file).
[ ! -e "${_AS_CNF}" ] && exit 0

# Run only on a fully installed system (same guard the sibling monitors use).
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# Opt-out: fully off when the operator says so (unset means ON).
[ "${_USE_XMASS_AUTOSYNC}" = "NO" ] && exit 0

# Major system transition in flight: stand down.
for _rt in excalibur daedalus chimaera beowulf; do
  [ -e "/root/.run-to-${_rt}.cnf" ] && exit 0
done

mkdir -p "${_pthDat}"

###
### Knobs. Normaliser mirrors lock.inc's _flap_num (digits only, leading
### zeros stripped), kept in-file so knob arithmetic never depends on which
### lock.inc a box happens to hold.
###
_as_num() {
  local _v="${1//[^0-9]/}"
  while [ "${#_v}" -gt 1 ] && [ "${_v:0:1}" = "0" ]; do
    _v="${_v:1}"
  done
  [ -n "${_v}" ] || _v="$2"
  printf '%s' "${_v}"
}

###
### Load + normalize _INCIDENT_REPORT
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
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

_incident_email_report() {
  # A failed pass means the mirror's files are ageing while its database
  # stays current — the default reporting level hears about that (MINI).
  # Uptime grace + ratelimit are command -v guarded: a box holding a new
  # autosync.sh against an older lock.inc still mails, and the daily-latched
  # callers below throttle themselves.
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
    if ! _incident_email_ratelimit "xmass-autosync"; then
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

# Once-a-day WARN classes, so a persistent anomaly cannot flood the incident
# log every tick. Returns 0 on the daily FIRST occurrence (the caller mails
# then), non-zero while latched.
_warn_daily() {
  local _slug="$1" _msg="$2"
  if [ -z "$(find "${_pthDat}/.warned_${_slug}" -mmin -1440 2>/dev/null)" ]; then
    echo "$(date) ${_msg}" >> ${_pthOml}
    touch "${_pthDat}/.warned_${_slug}"
    return 0
  fi
  return 1
}

# One-way means the ACTIVE drives. A standby or a finalized PX0 proxy holding
# an armed marker is a leftover from a role change, never a box that should
# push files anywhere — one daily warning WITH one daily mail (this is the
# only caller that can surface it: the loud role checks inside `--run` are
# never reached, because this stand-down is what keeps them unreached).
if [ -e "/root/.standby.cnf" ]; then
  if _warn_daily "standby" "WARN: ${_AS_CNF} armed on a passive standby — a mirror never drives autosync; remove the marker (xmass autosync --off)"; then
    _incident_email_report "Autosync marker armed on a passive standby (cadence parked)" "MINI"
  fi
  _say "STAND-DOWN reason=standby-role"
  exit 0
fi
if [ -e "/root/.proxy.cnf" ]; then
  if _warn_daily "proxy" "WARN: ${_AS_CNF} armed on a finalized PX0 proxy — nothing here to mirror; remove the marker (xmass autosync --off)"; then
    _incident_email_report "Autosync marker armed on a finalized proxy (cadence parked)" "MINI"
  fi
  _say "STAND-DOWN reason=proxy-role"
  exit 0
fi

# Cadence comes from the marker (written and validated at arm time; the
# clamp here only defends a hand-edited file). The self-throttle runs
# against EVERY-1 because "older than N" is an open bound. Checked EARLY,
# before any per-tick process work — minute.sh relaunches this up to nine
# times a minute and ~all ticks end right here.
_AS_EVERY=$(_as_num "$(grep '^_XMASS_AUTOSYNC_EVERY=' "${_AS_CNF}" 2>/dev/null | head -n1 | cut -d= -f2)" 15)
[ "${_AS_EVERY}" -lt 5 ] && _AS_EVERY=5

# --- duty-cycle guard -------------------------------------------------
# The armed cadence is what the operator wants; this is what the box can
# afford. A pass walks the estate's metadata several times over, so on a
# large estate it can outlast the interval -- and because an overlapping
# tick defers silently on the verb lock, the pair would then run back to
# back forever, walking continuously with nothing to show for it.
#
# So a pass may occupy at most 1/(_XMASS_AUTOSYNC_DUTY + 1) of wall clock:
# the box rests at least DUTY x the last measured pass before the next one.
# It needs no new gate or exit path, because ${_STAMP} is touched BEFORE the
# pass (below) and therefore carries the pass START -- "rest DUTY x D after
# the end" is exactly "(DUTY + 1) x D since the start", which is one
# widening of the number the throttle already compares against.
#
# The armed cadence still wins whenever it is the LONGER of the two: this
# only ever slows a pair down, never speeds one up.
_XMASS_AUTOSYNC_DUTY=$(_as_num "${_XMASS_AUTOSYNC_DUTY}" 3)
_AS_WINDOW="${_AS_EVERY}"
_AS_LASTDUR=$(_as_num "$(cat "${_AS_DURFILE}" 2>/dev/null)" 0)
if [ "${_AS_LASTDUR}" -gt 0 ]; then
  # ceiling division: a 40s pass at duty 3 must not round down to 2 minutes
  _AS_FLOOR=$(( ( _AS_LASTDUR * (_XMASS_AUTOSYNC_DUTY + 1) + 59 ) / 60 ))
  [ "${_AS_FLOOR}" -gt "${_AS_WINDOW}" ] && _AS_WINDOW="${_AS_FLOOR}"
fi
if [ "${_FORCE}" != "YES" ] && [ -e "${_STAMP}" ] \
  && [ -z "$(find "${_STAMP}" -mmin "+$(( _AS_WINDOW - 1 ))" 2>/dev/null)" ]; then
  exit 0
fi

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

# Touched BEFORE the pass: overlap is already refused by the xmass owner-PID
# lock, and a pass longer than the cadence must not re-fire the instant it
# ends.
touch "${_STAMP}"

# Hard per-pass ceiling: a hung ssh over a stalled TCP session can outlive
# any rsync of real data. Killing a pass is safe (idempotent delta legs; the
# lock's signal trap EXITS, releasing the slot) and the next tick resumes
# the delta; -k escalates to KILL if the TERM is ignored.
_XMASS_AUTOSYNC_TIMEOUT=$(_as_num "${_XMASS_AUTOSYNC_TIMEOUT}" 21600)
[ "${_XMASS_AUTOSYNC_TIMEOUT}" -lt 600 ] && _XMASS_AUTOSYNC_TIMEOUT=600

# The pass log carries every pass's full output (the eligible/skip list is
# state worth keeping); bound it so it can never grow without limit — but
# never while a previous longer-than-cadence pass still holds its fd on the
# file, or the rest of that pass's output vanishes into the old inode.
if [ -e "${_pthSyncLog}" ] \
  && [ "$(stat -c %s "${_pthSyncLog}" 2>/dev/null || echo 0)" -gt 4194304 ] \
  && ! pgrep -f "xmass autosync --run" > /dev/null 2>&1; then
  tail -c 2097152 "${_pthSyncLog}" > "${_pthSyncLog}.trim" 2>/dev/null \
    && mv -f "${_pthSyncLog}.trim" "${_pthSyncLog}"
fi

# The pass itself. Every safety decision — phase, roles, the owner-PID lock,
# the target's standby marker (re-proved at every leg boundary) — is xmass's
# own; a defer exits 0 silently and only a real failure comes back non-zero.
# ionice/nice keep the local tree walk polite on a serving production box;
# the remote receiver is unaffected.
echo "---------------------------- $(date '+%Y-%m-%d %H:%M:%S') autosync tick" >> "${_pthSyncLog}"
_rc=0
_AS_T0=$(date +%s)
ionice -c2 -n7 nice -n10 timeout -k 60 "${_XMASS_AUTOSYNC_TIMEOUT}" \
  bash /opt/local/bin/xmass autosync --run >> "${_pthSyncLog}" 2>&1 || _rc=$?
# Recorded for EVERY outcome, including a deferred tick and a killed pass:
# a defer is genuinely cheap and should not inflate the rest window, while a
# pass killed at the ceiling is the most expensive outcome there is and must
# not be forgotten. The verb's own quick defers cost a second or two, so they
# naturally leave the window at the armed cadence.
_AS_DUR=$(( $(date +%s) - _AS_T0 ))
echo "${_AS_DUR}" > "${_AS_DURFILE}" 2>/dev/null
_say "PASS rc=${_rc} dur=${_AS_DUR}s window=${_AS_WINDOW}m"

if [ "${_rc}" != "0" ]; then
  if [ "${_rc}" = "124" ]; then
    echo "$(date) ALRT: autosync pass killed at the ${_XMASS_AUTOSYNC_TIMEOUT}s ceiling — a hung transfer or a first pass far larger than expected; the next tick resumes the delta" >> ${_pthOml}
  fi
  {
    echo "$(date) ALRT: xmass autosync pass failed (rc=${_rc}); last pass output:"
    tail -n 40 "${_pthSyncLog}" 2>/dev/null
    echo
  } >> ${_pthOml}
  _incident_email_report "Standing-mirror file sync pass failed (rc=${_rc})" "MINI"
fi

# Staleness alarm — the backstop for every SILENT defer class at once (a
# wedged phase after an aborted cutover, a lock held by something stuck, an
# unnoticed hand-edit): if no pass has COMPLETED for six cadences, say so,
# daily, with one mail. Baseline falls back to the marker's own mtime so a
# freshly armed pair gets its full grace before the first alarm.
_AS_REF="${_AS_STATUS}"
[ -s "${_AS_REF}" ] || _AS_REF="${_AS_CNF}"
# Measured against the EFFECTIVE window, not the armed cadence: a pair the
# duty guard has correctly slowed down is not stale, and an alarm that cries
# wolf every day is worse than no alarm at all -- it trains the operator to
# ignore the one signal that backstops every silent-defer class.
_AS_STALE_MIN=$(( _AS_WINDOW * 6 ))
[ "${_AS_STALE_MIN}" -lt 180 ] && _AS_STALE_MIN=180
if [ -n "$(find "${_AS_REF}" -mmin "+${_AS_STALE_MIN}" 2>/dev/null)" ]; then
  if _warn_daily "stale" "WARN: autosync is armed but no pass has completed for over ${_AS_STALE_MIN} minutes — the mirror's files are ageing while its database stays current; read the defer/refusal reasons in ${_pthSyncLog}"; then
    _incident_email_report "Standing-mirror file sync stale: no completed pass for ${_AS_STALE_MIN}+ minutes" "MINI"
  fi
  _say "STALE ref=${_AS_REF}"
fi

exit 0
