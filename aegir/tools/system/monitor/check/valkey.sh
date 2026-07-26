#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/valkey.incident.log"
_pthLdg="/var/log/boa/valkey.restart.ledger"
_pthLch="/run/boa_valkey_restart_latched.pid"
_cd="/run/valkey-monitor.cooldown"

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

[ -d /run/valkey ] || mkdir -p /run/valkey
[ -d /run/valkey ] && chown -R valkey:valkey /run/valkey

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

###
### Flap control for the auto-heal. A restart that has to be repeated is
### evidence the restart is not the remedy, so the second one is spaced out
### (cooldown) and the run of them is capped (circuit-breaker). Every value
### can be overridden from /root/.barracuda.cnf. The machinery is kept
### INLINE, like the database watchdog keeps its own copy and for the same
### reason: this file is fetched under its own serial, and a box that has
### taken a new valkey.sh but not yet a new lock.inc must not lose its
### breaker to that skew -- worst on exactly the box that needs it, one
### whose cache server is failing every pass. lock.inc's generic primitives
### stay the shared home; migrate to them only once consuming them cannot
### outrun their delivery.
###
_valkey_flap_num() {
  # Normalise one operator-supplied number: digits only, and with any leading
  # zeros stripped. Bash reads a zero-padded number as octal inside $(( )),
  # where 08 is a hard error and 0900 is not 900 -- either would quietly
  # corrupt the window arithmetic below and leave the breaker silently never
  # opening, which is the one failure this whole mechanism must not have.
  # Falls back to the given default when nothing usable is left.
  local _v="${1//[^0-9]/}"
  while [ "${#_v}" -gt 1 ] && [ "${_v:0:1}" = "0" ]; do
    _v="${_v:1}"
  done
  [ -n "${_v}" ] || _v="$2"
  printf '%s' "${_v}"
}

_VALKEY_COOLDOWN_SECS=$(_valkey_flap_num "${_VALKEY_COOLDOWN_SECS}" 30)    # Minimum gap between two auto-heals

_VALKEY_FLAP_MAX=$(_valkey_flap_num "${_VALKEY_FLAP_MAX}" 3)               # Auto-heals tolerated inside the window
# Zero would latch the breaker before the first legitimate recovery could run.
[ "${_VALKEY_FLAP_MAX}" -lt 1 ] && _VALKEY_FLAP_MAX=1

_VALKEY_FLAP_WINDOW_SECS=$(_valkey_flap_num "${_VALKEY_FLAP_WINDOW_SECS}" 3600) # Window those auto-heals are counted in
# The window has to be wide enough to still hold _VALKEY_FLAP_MAX heals at
# the pace they actually land, or the oldest entry ages out before the
# breaker can count it and the circuit never opens -- silently. That pace is
# NOT the cooldown: it is set by the dispatch tick, and a pass that has to
# confirm a wedged server (five bounded probes) and then walk the whole
# stop/start sequence overruns the tick, so consecutive heals quantise to a
# multiple of it. The slack per heal is therefore minutes, not seconds --
# the same four minutes the database watchdog allows, and for the same
# reason -- and it must clear the achievable pace strictly, because the
# ledger's window test drops an entry that lands exactly on the boundary.
_VALKEY_FLAP_FLOOR=$(( _VALKEY_FLAP_MAX * (_VALKEY_COOLDOWN_SECS + 240) ))
if [ "${_VALKEY_FLAP_WINDOW_SECS}" -lt "${_VALKEY_FLAP_FLOOR}" ]; then
  _VALKEY_FLAP_WINDOW_SECS="${_VALKEY_FLAP_FLOOR}"
fi

_VALKEY_FLAP_LATCH_MINS=$(_valkey_flap_num "${_VALKEY_FLAP_LATCH_MINS}" 60)     # Cool-off before an open circuit re-arms

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
  # The severity ladder, applied to what this watchdog can say:
  #   ALERT == the circuit breaker latched: auto-healing has stopped acting
  #            and an operator is the only way forward.
  #   MINI  == a genuine restart of the cache server happened. The default
  #            reporting level hears about this now: a cache restart empties
  #            the cache, and while it was ALL-only an operator learnt about
  #            a flapping cache server from the load graphs, not from a mail.
  #   INFO  == routine notices, ALL only.
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
  # the next alert that does go out carries the ones that did not. Classes
  # that are not the same incident keep their own key -- the circuit-breaker
  # page must never be held back behind the heal mails it explains -- and an
  # ALERT gets its own cooldown by construction, not by remembering to pass a
  # key at the call site. An older lock.inc without the helper sends as before.
  local _sfx=""
  local _key="${3:-}"
  if [ -z "${_key}" ]; then
    if [ "${_lvl}" = "ALERT" ]; then
      _key="valkey-alert"
    else
      _key="valkey"
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

_valkey_is_answering() {
  # Authoritative liveness probe. Only a demonstrable failure to CONNECT --
  # refused, missing socket, reset, or a hang past the timeout -- counts as
  # down. A reply of ANY other kind proves a live server: WRONGPASS/NOAUTH is
  # an auth drift to fix, not an outage (restarting on it turns a stale
  # password file into a restart loop, because the restart never changes the
  # password), LOADING is a dataset being read back in that a restart would
  # only start over, and any other error is still a reply the server composed
  # and sent. The classification reads the reply, never the exit code,
  # because valkey-cli's exit status does not separate "server answered with
  # an error" from "no server". `timeout` bounds a wedged server.
  local _out _pass
  if [ ! -x "/usr/bin/valkey-cli" ]; then
    # No cli to ask: process presence is the only evidence left. Thin, but it
    # can only under-heal (a wedged-but-present server is left alone), never
    # restart a healthy one.
    pgrep -f "/usr/bin/valkey-server" >/dev/null 2>&1 && return 0
    return 1
  fi
  _pass=
  if [ -r "/root/.valkey.pass.txt" ]; then
    _pass="$(head -n1 /root/.valkey.pass.txt 2>/dev/null | tr -d '\r\n')"
  fi
  if [ -n "${_pass}" ]; then
    _out="$(timeout 5 /usr/bin/valkey-cli -s /run/valkey/valkey.sock --no-auth-warning -a "${_pass}" ping 2>&1)"
  else
    _out="$(timeout 5 /usr/bin/valkey-cli -s /run/valkey/valkey.sock ping 2>&1)"
  fi
  # The cli's -a advice line goes to stderr BEFORE it even connects, so it is
  # the one thing a probe killed mid-hang has always managed to say -- left
  # in, it would satisfy the emptiness test below and disguise every wedged
  # server as an answering one. --no-auth-warning silences it at the source
  # and the filter drops whatever advice another cli build still prints,
  # because only the SERVER's words may count as a reply.
  _out="$(printf '%s\n' "${_out}" | grep -v '^Warning:')"
  # Empty output means the cli said nothing at all: killed by the timeout
  # while a wedged server sat on the reply, or crashed before it could even
  # report a connection error.
  [ -n "${_out}" ] || return 1
  if echo "${_out}" | grep -qiE "Could not connect|Connection refused|Connection reset|Connection timed out|Failed to connect|Server closed the connection|Broken pipe|I/O error"; then
    return 1
  fi
  return 0
}

_valkey_flap_prune_ledger() {
  # Count the auto-heals recorded within the flap window and rewrite the
  # ledger with only those, so it stays small and needs no rotation. Result
  # in the global _VALKEY_FLAP_COUNT. Reads via redirect, not a pipe, so the
  # counter is incremented in this shell and not in a subshell that discards
  # it.
  #
  # An entry stamped in the future can only come from a backwards clock step;
  # it is dropped rather than counted, because the breaker must never latch
  # on a clock artefact and refuse a genuine recovery.
  #
  # The ledger outlives a reboot, but the flap history does not: restarts
  # from before the box came up say nothing about this boot, and counting
  # them could latch the breaker during the post-boot window where alerts
  # are suppressed -- a latch nobody is paged about. So never look further
  # back than boot time.
  local _cut _boot _line _stamp _tmp
  _VALKEY_FLAP_COUNT=0
  [ -s "${_pthLdg}" ] || return 0
  _cut=$(( $1 - _VALKEY_FLAP_WINDOW_SECS ))
  _boot=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
  _boot="${_boot//[^0-9]/}"
  if [ -n "${_boot}" ] && [ "$(( $1 - _boot ))" -gt "${_cut}" ]; then
    _cut=$(( $1 - _boot ))
  fi
  _tmp="${_pthLdg}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  while read -r _line; do
    _stamp="${_line//[^0-9]/}"
    [ -n "${_stamp}" ] || continue
    if [ "${_stamp}" -gt "${_cut}" ] && [ "${_stamp}" -le "$1" ]; then
      echo "${_stamp}" >> "${_tmp}"
      _VALKEY_FLAP_COUNT=$(( _VALKEY_FLAP_COUNT + 1 ))
    fi
  done < "${_pthLdg}"
  mv -f "${_tmp}" "${_pthLdg}" 2>/dev/null || rm -f "${_tmp}"
}

_valkey_flap_breaker_is_open() {
  # The open circuit is a latched refusal to auto-restart Valkey, cleared by
  # an operator (remove the file) or by the cool-off. Age comes from the file
  # mtime with the same `find -mmin` idiom the SQL-mutation stand-down uses
  # below, so a forgotten latch can never disable auto-healing permanently;
  # /run is tmpfs, so a reboot clears it too.
  [ -e "${_pthLch}" ] || return 1
  if [ -n "$(find "${_pthLch}" -mmin "+${_VALKEY_FLAP_LATCH_MINS}" 2>/dev/null)" ]; then
    rm -f "${_pthLch}"
    # Opening the circuit already discarded the history, and nothing is
    # counted while it is open. Clear it again anyway so the invariant "a
    # re-armed breaker starts counting at zero" holds however the ledger got
    # there.
    rm -f "${_pthLdg}"
    echo "$(date) Valkey auto-restart re-armed after the ${_VALKEY_FLAP_LATCH_MINS} min cool-off" >> ${_pthOml}
    return 1
  fi
  return 0
}

_valkey_heal_gate() {
  # Every AUTO-heal passes here before acting; the operator-requested restart
  # deliberately does not (an explicit request must not be refused on the
  # strength of automation history -- it keeps its own cooldown only).
  # Order, cheapest refusal first: a server that answers again needs nothing;
  # an open circuit refuses everything; a heal inside the cooldown waits; and
  # a heal that would overrun the flap budget latches the circuit, pages once
  # on its own key, and stops the run. Passing the gate records the attempt
  # in the ledger BEFORE acting, so a heal that ends this script still leaves
  # evidence for the breaker.
  local _now _ts _gap
  if _valkey_is_answering; then
    echo "$(date) INFO: Valkey answering again before action ($1); standing down" >> ${_pthOml}
    return 1
  fi
  _now=$(date +%s)
  if _valkey_flap_breaker_is_open; then
    echo "$(date) $1 incident: CIRCUIT OPEN, auto-restart refused -- see ${_pthLch}" >> ${_pthOml}
    echo >> ${_pthOml}
    return 1
  fi
  if [ -s "${_cd}" ]; then
    _ts=$(tr -dc '0-9' < "${_cd}" 2>/dev/null)
    if [ -n "${_ts}" ]; then
      _gap=$(( _now - _ts ))
      # A negative gap means the clock stepped backwards: treat the stamp as
      # unusable and act, instead of freezing the watchdog until it catches up.
      if [ "${_gap}" -ge 0 ] && [ "${_gap}" -lt "${_VALKEY_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: Valkey unhealthy but in cooldown (${_gap}s < ${_VALKEY_COOLDOWN_SECS}s); skipping restart" >> ${_pthOml}
        return 1
      fi
    fi
  fi
  _valkey_flap_prune_ledger "${_now}"
  if [ "${_VALKEY_FLAP_COUNT}" -ge "${_VALKEY_FLAP_MAX}" ]; then
    # The latch carries the whole state of the breaker; the history that
    # opened it goes with it, so any re-arm starts counting at zero.
    echo "$(date) CIRCUIT OPEN: ${_VALKEY_FLAP_COUNT} Valkey auto-restarts in the last ${_VALKEY_FLAP_WINDOW_SECS} seconds, so auto-restart is now disabled. Fix the cause, then delete this file to re-arm it; it also re-arms on its own ${_VALKEY_FLAP_LATCH_MINS} minutes after this stamp." > "${_pthLch}"
    rm -f "${_pthLdg}"
    echo "$(date) $1 incident: CIRCUIT OPEN after ${_VALKEY_FLAP_COUNT} auto-restarts within ${_VALKEY_FLAP_WINDOW_SECS}s -- refusing to restart Valkey again" >> ${_pthOml}
    _incident_email_report "CIRCUIT OPEN: Valkey auto-restart disabled after ${_VALKEY_FLAP_COUNT} restarts" "ALERT" "valkey-circuit"
    echo >> ${_pthOml}
    return 1
  fi
  echo "${_now}" >> "${_pthLdg}"
  return 0
}

_valkey_restart() {
  touch /run/boa_valkey_auto_healing.pid
  sleep 3
  echo "$(date) $1 incident detected" >> ${_pthOml}
  service valkey-server stop &> /dev/null
  killall -9 valkey-server &> /dev/null
  # Last-resort path only: clearing the data files is what a plain restart
  # cannot do, and a dataset the server refuses to load back is the one fault
  # left once a plain restart has failed. The files hold a disposable page
  # cache, so losing them costs warm-up, not data.
  rm -f /var/lib/valkey/*
  service valkey-server start &> /dev/null
  echo "$(date) $1 incident valkey-server restarted" >> ${_pthOml}
  sleep 3
  if _valkey_is_answering; then
    echo "$(date) $1 incident response completed: Valkey answering" >> ${_pthOml}
  else
    echo "$(date) $1 incident response completed: Valkey still not answering" >> ${_pthOml}
  fi
  # Hold the next auto-heal off for the cooldown window. Stamped after the
  # action so the gap is measured from when this heal finished.
  date +%s > "${_cd}"
  _incident_email_report "$1" "MINI"
  echo >> ${_pthOml}
  [ -e "/run/boa_valkey_auto_healing.pid" ] && rm -f /run/boa_valkey_auto_healing.pid
  exit 0
}

_valkey_bind_check_fix() {
  # Bind/socket/address-in-use issues -> verify twice; restart only if socket
  # missing. This reads Valkey's own server log and its own socket, so it is
  # first-hand evidence, unlike the PHP-side symptom checks this file used to
  # carry.
  _hits=$(tail -n 8 /var/log/valkey/valkey-server.log 2>/dev/null | egrep -ci "Address already in use")
  if [ "${_hits}" -gt 0 ]; then
    sleep 2
    _hits2=$(tail -n 8 /var/log/valkey/valkey-server.log 2>/dev/null | egrep -ci "Address already in use")
    if [ "${_hits2}" -gt 0 ] && [ ! -S "/run/valkey/valkey.sock" ]; then
      _valkey_heal_gate "ValkeyException BIND PORT" || return 0
      echo "$(date) Valkey bind/socket conflict; restarting" >> ${_pthOml}
      _valkey_restart "ValkeyException BIND PORT"
    fi
  fi
}

_if_valkey_restart() {
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
  _PrTestUltra=$(grep "ULTRA" /root/.*.octopus.cnf 2>&1)
  _PrTestMonster=$(grep "MONSTER" /root/.*.octopus.cnf 2>&1)
  _VkTest=$(ls /data/disk/*/static/control/run-valkey-restart.pid | wc -l 2>&1)
  _ReTest=$(ls /data/disk/*/static/control/run-redis-restart.pid | wc -l 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [[ "${_PrTestUltra}" =~ "ULTRA" ]] \
    || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
    || [ -e "/etc/boa/.allow.valkey.restart.cnf" ] \
    || [ -e "/etc/boa/.allow.redis.restart.cnf" ]; then
    if [ "${_VkTest}" -ge 1 ] || [ "${_ReTest}" -ge 1 ]; then
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(tr -d '\n' < "${_cd}")
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_VALKEY_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: Valkey restart requested but in cooldown; skipped" >> ${_pthOml}
          return 0
        fi
      fi
      rm -f /data/disk/*/static/control/run-valkey-restart.pid
      rm -f /data/disk/*/static/control/run-redis-restart.pid
      _thisErrLog="$(date) Valkey Server Restart Requested"
      echo ${_thisErrLog} >> ${_pthOml}
      _valkey_restart "Valkey Server Restart Requested"
    fi
  fi
}

_valkey_health_check_fix() {
  # A momentarily silent probe is NOT proof of a hard outage; only sustained
  # silence is. Confirm across spaced probes of Valkey itself and stand down
  # the moment any probe answers. Down-detection must come from Valkey, not
  # from PHP-side symptoms: the log-driven checks this replaces counted other
  # services' error lines, restarted a healthy cache server on them, and then
  # reloaded every PHP-FPM pool behind it -- which is how a transient blip
  # elsewhere used to become a cold cache and a site-wide slowdown here.
  _valkey_is_answering && return 0
  local _try
  for _try in 1 2 3 4; do
    sleep 3
    _valkey_is_answering && return 0
  done
  _valkey_heal_gate "DOWN Valkey" || return 0
  echo "$(date) Valkey down (sustained across 5 probes) -- restart" >> ${_pthOml}
  service valkey-server restart &> /dev/null
  sleep 3
  if _valkey_is_answering; then
    # Hold the next auto-heal off for the cooldown window, measured from when
    # this heal finished.
    date +%s > "${_cd}"
    echo "$(date) Valkey was down, restarted" >> ${_pthOml}
    _incident_email_report "Valkey was down, restarted" "MINI"
    echo >> ${_pthOml}
    exit 0
  fi
  echo "$(date) Valkey still not answering after restart; forced stop/start" >> ${_pthOml}
  _valkey_restart "Valkey required stop/start after failed restart"
}

if [ -e "/run/boa_valkey_auto_healing.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

###
### Stand down while the database is being deliberately restarted
###
export _SQL_MUTATION_MAX_MINS=${_SQL_MUTATION_MAX_MINS//[^0-9]/}
: "${_SQL_MUTATION_MAX_MINS:=15}"

_sql_mutation_in_flight() {
  # move_sql.sh stops Nginx and every PHP-FPM pool to restart the database, and
  # it never brings them back: these watchdogs are the intended recovery. That
  # only works if they wait for the restart to finish. Restarting the web tier
  # mid-teardown stands it in front of a database that is still down, so workers
  # pile onto failed connections and the whole herd arrives at a cold cache the
  # moment the database returns; that cascade is what turns a brief database
  # fault into a site-wide one. runner.sh and system.sh already stand down on
  # the same two markers: mysql_restart_running.pid, written by move_sql.sh and
  # by mycnfup, and boa_mysql_auto_healing.pid, held by the database watchdog
  # for the length of its heal.
  #
  # Honoured only while the marker is recent, deliberately. clear.sh reaps a
  # leaked mysql_restart_running.pid an hour after the writer died, and an hour
  # with no web auto-healing is a worse outcome than the cascade this avoids; a
  # marker older than the bound is treated as abandoned rather than authoritative.
  local _m
  for _m in /run/mysql_restart_running.pid /run/boa_mysql_auto_healing.pid; do
    [ -e "${_m}" ] || continue
    if [ -z "$(find "${_m}" -mmin "+${_SQL_MUTATION_MAX_MINS}" 2>/dev/null)" ]; then
      echo "$(date) INFO: MySQL restart in progress (${_m##*/}); standing down this pass" >> ${_pthOml}
      return 0
    fi
  done
  return 1
}

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ] \
  && ! _sql_mutation_in_flight; then
  if [ -x "/etc/init.d/valkey-server" ] \
    && [ -x "/usr/bin/valkey-server" ]; then
    _valkey_health_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && _valkey_bind_check_fix
    [ "${_ALLOW_CTRL}" = "YES" ] && [ -d "/data/u" ] && _if_valkey_restart
  fi
fi

echo DONE!
exit 0
