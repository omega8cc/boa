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
_SINGLE_INSTANCE_LIB_VER="1.1"

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
    [ -n "${_PATH}" ] && rm -f "${_PATH}" 2>/dev/null || true
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
    _DIR="/run"; [ -w "$_DIR" ] || _DIR="/run"; [ -w "$_DIR" ] || _DIR="/tmp"
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
    trap "_single_instance_unlock ${_LOCK_FD} '${_LOCK_PATH}'" EXIT INT TERM HUP
  else
    # mkdir is atomic; directory presence == lock held
    if ! mkdir "${_LOCK_PATH}" 2>/dev/null; then
      echo "${_SELF_NAME}: another instance is running; exiting."
      exit 0
    fi
    echo "$$" > "${_LOCK_PATH}/pid" 2>/dev/null || true
    trap "rm -rf '${_LOCK_PATH}'" EXIT INT TERM HUP
  fi
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
  if [ "${_UPTIME_MIN}" -lt 15 ] \
    || [ ! -e "/var/aegir/.drush/hm.alias.drushrc.php" ] \
    || [ ! -x "/usr/sbin/csf" ] \
    || [ ! -e "/run/lfd.pid" ] \
    || [ -e "/run/octopus_install_run.pid" ] \
    || [ -e "/run/boa_run.pid" ] \
    || [ -e "/run/boa_wait.pid" ]; then
    export _INCIDENT_REPORT=OFF
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      echo "Skipping alerts: system uptime ${_UPTIME_MIN} min < 15 min threshold."
    fi
    return 1
  fi
  return 0
}
