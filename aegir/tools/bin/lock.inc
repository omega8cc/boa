#!/bin/bash

#
# lockinc — reusable single-instance lock helpers
# Provides: _single_instance_lock [lockfile] [fd]
#           _single_instance_unlock <fd> <lockfile>
#

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

###
### Idempotent include guard
###
[ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && return 0
_SINGLE_INSTANCE_LIB_VER="1.2"

###
### Atomic unlock to prevent TOCTOU race
###
_single_instance_unlock() {
  # Args optional: fall back to the descriptor/path recorded by _single_instance_lock,
  # so a no-arg call (e.g. from a caller's own EXIT trap that overrode our trap) still
  # releases the right lock instead of leaving _FD empty — an empty _FD tripped
  # "_FD: ambiguous redirect" on the exec {_FD}>&- close below.
  _FD="${1:-${_LOCK_FD:-}}"
  _PATH="${2:-${_LOCK_PATH:-}}"
  if command -v flock >/dev/null 2>&1; then
    case "${_FD}" in
      ''|*[!0-9]*)
        # No usable numeric descriptor recorded — nothing to unlock/close.
        :
        ;;
      *)
        flock -u "${_FD}" 2>/dev/null || true
        # Close the lock fd via the brace-expansion close form (bash >= 4.1),
        # equivalent to `eval "exec ${_FD}>&-"` without the eval. Guarded above so a
        # bare number is guaranteed here; an empty/non-numeric value would otherwise
        # print "ambiguous redirect".
        exec {_FD}>&-
        ;;
    esac
    # The lockfile itself stays: flock lives on the inode, so removing the
    # name would hand the NEXT opener a fresh inode while a process still
    # waiting on the old one proceeds too -- two holders of one lock. A
    # 0-byte file on tmpfs costs nothing and clears on reboot.
  else
    [ -n "${_PATH}" ] && rm -rf "${_PATH}" 2>/dev/null || true
  fi
}

###
### Atomic lock to prevent TOCTOU race
###
_single_instance_lock() {
  # Ensure not too many instances are running
  # usage: _single_instance_lock [lockfile_path] [fd]
  # default lock: /run/<script>.lock (falls back to /run or /tmp)
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  _LOCK_FD="${2:-9}"
  if [ -n "${1:-}" ]; then
    _LOCK_PATH="$1"
  else
    _DIR="/run"; [ -w "$_DIR" ] || _DIR="/tmp"
    _LOCK_PATH="${_DIR}/${_SELF_NAME%.sh}.lock"
  fi

  if command -v flock >/dev/null 2>&1; then
    # Open _LOCK_PATH on a fresh fd. The brace-expansion form lets bash
    # auto-assign the next available descriptor into _LOCK_FD (overriding
    # the default of 9 set above), avoiding the eval that the original
    # code needed to use a variable as an fd number. All current callers
    # invoke _single_instance_lock with no args, so they accept whichever
    # fd bash picks.
    exec {_LOCK_FD}>"${_LOCK_PATH}"
    if ! flock -n "${_LOCK_FD}"; then
      echo "${_SELF_NAME}: another instance is running; exiting."
      exit 0
    fi
    printf '%s\n' "$$" 1>&"${_LOCK_FD}" 2>/dev/null || true   # optional: PID note
    # This trap is the lock's release path; a caller that installs its own
    # EXIT trap after locking replaces it and must call
    # _single_instance_unlock itself (flock still auto-releases when the
    # process exits, so the worst a lost trap costs is the tidy-up).
    trap "_single_instance_unlock ${_LOCK_FD} '${_LOCK_PATH}'" EXIT INT TERM HUP
  else
    # mkdir is atomic; directory presence == lock held. A holder that died
    # without its trap (SIGKILL, power loss) must not lock every future run
    # out: a recorded owner that is no longer alive, on a lock old enough
    # that no live run can still own it, is reclaimed once.
    if ! mkdir "${_LOCK_PATH}" 2>/dev/null; then
      _OWNER_PID="$(tr -dc '0-9' < "${_LOCK_PATH}/pid" 2>/dev/null)"
      if { [ -z "${_OWNER_PID}" ] || ! kill -0 "${_OWNER_PID}" 2>/dev/null; } \
        && [ -n "$(find "${_LOCK_PATH}" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
        rm -rf "${_LOCK_PATH}" 2>/dev/null
        mkdir "${_LOCK_PATH}" 2>/dev/null || { echo "${_SELF_NAME}: another instance is running; exiting."; exit 0; }
      else
        echo "${_SELF_NAME}: another instance is running; exiting."
        exit 0
      fi
    fi
    echo "$$" > "${_LOCK_PATH}/pid" 2>/dev/null || true
    trap "rm -rf '${_LOCK_PATH}'" EXIT INT TERM HUP
  fi
}

###
### Flap circuit-breaker primitives (shared)
###
### A heal that has to be repeated is evidence the heal is not the remedy. A
### caller keeps a ledger of action timestamps; once too many land inside a
### window it latches a breaker file, pages once, and stops acting until an
### operator deletes the latch or a cool-off passes. These are the generic
### forms of the machinery the database watchdog ships inline; that copy stays
### inline for now, deliberately -- it is fetched under its own serial, and a
### box holding a new mysql.sh against an old lock.inc must not lose its
### breaker. Migrate it here only once this library has been on boxes a while.
### First shared consumer: the system watchdog's OOM response.
###
_flap_num() {
  # Normalise one operator-supplied number: digits only, leading zeros
  # stripped (bash reads a zero-padded number as octal inside $(( )), where 08
  # is a hard error), falling back to the given default.
  local _v="${1//[^0-9]/}"
  while [ "${#_v}" -gt 1 ] && [ "${_v:0:1}" = "0" ]; do
    _v="${_v:1}"
  done
  [ -n "${_v}" ] || _v="$2"
  printf '%s' "${_v}"
}

_flap_prune_ledger() {
  # Usage: _flap_prune_ledger <ledger> <now-epoch> <window-secs>
  # Counts the actions recorded inside the window into the global _FLAP_COUNT
  # and rewrites the ledger with only those, so it stays small and needs no
  # rotation. Entries stamped in the future (a backwards clock step) are
  # dropped rather than counted, and nothing older than boot is counted: a
  # breaker must never latch on a clock artefact or on a previous boot's
  # history and refuse a genuine recovery.
  local _ldg="$1" _now="$2" _win="$3" _cut _boot _line _stamp _tmp
  _FLAP_COUNT=0
  [ -s "${_ldg}" ] || return 0
  _cut=$(( _now - _win ))
  _boot=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
  _boot="${_boot//[^0-9]/}"
  if [ -n "${_boot}" ] && [ "$(( _now - _boot ))" -gt "${_cut}" ]; then
    _cut=$(( _now - _boot ))
  fi
  _tmp="${_ldg}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  while read -r _line; do
    _stamp="${_line//[^0-9]/}"
    [ -n "${_stamp}" ] || continue
    if [ "${_stamp}" -gt "${_cut}" ] && [ "${_stamp}" -le "${_now}" ]; then
      echo "${_stamp}" >> "${_tmp}"
      _FLAP_COUNT=$(( _FLAP_COUNT + 1 ))
    fi
  done < "${_ldg}"
  mv -f "${_tmp}" "${_ldg}" 2>/dev/null || rm -f "${_tmp}"
}

_flap_breaker_is_open() {
  # Usage: _flap_breaker_is_open <latch> <cooloff-mins> <ledger> [logfile]
  # Returns 0 while the latch is fresh. An aged latch re-arms the breaker and
  # discards the history that opened it, so the count restarts at zero and a
  # forgotten latch can never disable healing permanently; /run is tmpfs, so a
  # reboot clears it too.
  local _lch="$1" _mins="$2" _ldg="$3" _log="$4"
  [ -e "${_lch}" ] || return 1
  if [ -n "$(find "${_lch}" -mmin "+${_mins}" 2>/dev/null)" ]; then
    rm -f "${_lch}"
    rm -f "${_ldg}"
    [ -n "${_log}" ] && echo "$(date) auto-heal re-armed after the ${_mins} min cool-off" >> "${_log}"
    return 1
  fi
  return 0
}

###
### Collapse a flap into one alert without silencing a sustained outage
###
### Usage: in any _send_email function, after the grace check:
###
###        _incident_email_ratelimit <key> [cooldown_secs] || return 1
###
### Returns 0 when the mail should go out and 1 when it should be held back,
### and sets _INCIDENT_SUPPRESSED to how many alerts have been held back since
### the last one that went out, so the caller can say so in the subject.
###
### Nothing is lost by suppressing: every incident is written to the service's
### own .incident.log regardless, and the mail body is the tail of that log, so
### the next alert that does go out carries the ones that did not.
###
_incident_email_ratelimit() {
  local _key _cool _stamp _now _gap _ts _cnt
  _key="${1:-incident}"
  _key="${_key//[^A-Za-z0-9._-]/}"
  [ -n "${_key}" ] || _key="incident"
  _cool="${2:-${_INCIDENT_EMAIL_COOLDOWN_SECS:-1800}}"
  _cool="${_cool//[^0-9]/}"
  [ -n "${_cool}" ] || _cool=1800
  _INCIDENT_SUPPRESSED=0
  # A zero cooldown is a deliberate opt-out: never hold anything back.
  [ "${_cool}" -gt 0 ] || return 0
  _stamp="/run/incident.${_key}.stamp"
  _now=$(date +%s)
  if [ -s "${_stamp}" ]; then
    read -r _ts _cnt < "${_stamp}" 2>/dev/null
    _ts="${_ts//[^0-9]/}"
    _cnt="${_cnt//[^0-9]/}"
    [ -n "${_cnt}" ] || _cnt=0
    if [ -n "${_ts}" ]; then
      _gap=$(( _now - _ts ))
      # A negative gap means the clock stepped backwards; treat the stamp as
      # unusable and alert, rather than going quiet until it catches up.
      if [ "${_gap}" -ge 0 ] && [ "${_gap}" -lt "${_cool}" ]; then
        printf '%s %s\n' "${_ts}" "$(( _cnt + 1 ))" > "${_stamp}" 2>/dev/null
        return 1
      fi
    fi
    _INCIDENT_SUPPRESSED="${_cnt}"
  fi
  # A stamp that cannot be written fails open: alerting matters more than the
  # throttle, and /run is tmpfs so this clears on reboot in any case.
  printf '%s 0\n' "${_now}" > "${_stamp}" 2>/dev/null
  return 0
}

###
### Prevent a flood of alerts on services up/down status if uptime < 15 minutes
###
### Usage: in any _send_email function add at the top this line
###        to exit/disable that function but continue the script:
###
###        if ! _check_uptime_grace_period >/dev/null; then return 1; fi
###
_check_uptime_grace_period() {
  _UPTIME_MIN=$(awk '{print int($1/60)}' /proc/uptime 2>/dev/null)
  # An unreadable /proc/uptime must read as "just booted", not as a shell
  # error in the comparison below: staying quiet is the safe direction.
  [ -n "${_UPTIME_MIN}" ] || _UPTIME_MIN=0
  # The .sh.txt pgreps cover the chained install's legs, which drop the
  # lock pids mid-chain by design: their pkill/restart churn is exactly
  # the noise this grace period exists to keep out of incident mail
  if [ "${_UPTIME_MIN}" -lt 15 ] \
    || [ ! -e "/var/aegir/.drush/hm.alias.drushrc.php" ] \
    || [ ! -x "/usr/sbin/csf" ] \
    || [ ! -e "/run/lfd.pid" ] \
    || [ -e "/run/octopus_install_run.pid" ] \
    || [ -e "/run/boa_run.pid" ] \
    || [ -e "/run/boa_wait.pid" ] \
    || pgrep -f "^(/[^ ]*/)?bash (-c )?/var/backups/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 \
    || pgrep -f "^(/[^ ]*/)?(bash|sh|su) .*/aegir/scripts/AegirSetup[ABC]\.sh\.txt" > /dev/null 2>&1; then
    export _INCIDENT_REPORT=OFF
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo "Skipping alerts: system uptime ${_UPTIME_MIN} min < 15 min threshold."
    fi
    return 1
  fi
  return 0
}
