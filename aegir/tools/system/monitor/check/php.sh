#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/php.incident.log"

# Default before the cnf source below so the cnf value wins; the
# variable is the supported switch, the /etc/boa flag stays honoured
# for one release while fleets converge.
_ALLOW_PHP_FPM_RELOAD=NO

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
# Whether this box finished installing lives in /etc/boa/control. A stamp an
# earlier release wrote in /var/log/boa is copied there first, and still counts
# when the copy cannot be made: a box never reads as not installed.
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

# A pool's worker output reaches these master logs as
#   WARNING: [pool NAME] child PID said into stderr: "..."
# (catch_workers_output). That text is the site's own, so no check below may
# act on it: each one drops worker lines before matching the master's messages.
_FPM_WORKER_LINE=' child [0-9]+ said into std(err|out): '

# The last 500 lines each master wrote itself. Read from a wider tail, so a
# burst of worker output cannot push a master message out of the window.
_fpm_master_tail() {
  local _f
  for _f in /var/log/php/php*-fpm-error.log; do
    [ -f "${_f}" ] || continue
    tail --lines=20000 "${_f}" 2>/dev/null \
      | grep -v -E "${_FPM_WORKER_LINE}" | tail --lines=500
  done
}

: "${_FPM_COOLDOWN_SECS:=30}"

_NOW=$(date +%y%m%d-%H%M%S)
_NOW=${_NOW//[^0-9-]/}

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
  if ! _check_uptime_grace_period >/dev/null; then return 1; fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "ALL" ]; then
    # One alert per cooldown, not one per pass. A service that keeps failing
    # used to send a mail every time a watchdog acted, which buries the signal
    # exactly when it matters most. Nothing is lost: every incident is still
    # written to the log below, and the mail body is the tail of that log, so
    # the next alert that does go out carries the ones that did not. An older
    # lock.inc without the helper simply sends as before.
    local _sfx=""
    if command -v _incident_email_ratelimit >/dev/null 2>&1; then
      if ! _incident_email_ratelimit "${2:-php}"; then
        echo "$(date) INFO: alert for '${1}' held back, one was already sent this cooldown" >> ${_pthOml}
        return 1
      fi
      if [ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]; then
        _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
      fi
    fi
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1}${_sfx} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_pthOml}")
  fi
}

_fpm_reload() {
  : > /run/fmp_wait.pid
  : > /run/restarting_fmp_wait.pid
  sleep 3
  renice ${_B_NICE} -p $$ &> /dev/null
  _PHP_V="86 85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -e "/opt/php${e}/bin/php" ]; then
      service "php${e}-fpm" reload
    fi
  done
  echo "$(date) $1 incident PHP-FPM reloaded" >> ${_pthOml}
  sleep 1
  rm -f /run/fmp_wait.pid /run/restarting_fmp_wait.pid
}

_fpm_master_pids() {
  # ${1} = the master title pattern. A master's just-forked child carries the
  # master's title until it names its pool, a window a stalled box stretches
  # to seconds: only a match whose parent is not itself a match is a master.
  local _all _pid _ppid
  _all=" $(pgrep -f "${1}" 2> /dev/null | tr '\n' ' ') "
  for _pid in ${_all}; do
    _ppid=$(ps -o ppid= -p "${_pid}" 2> /dev/null | tr -d ' ')
    [ -n "${_ppid}" ] || continue
    [[ "${_all}" == *" ${_ppid} "* ]] && continue
    echo "${_pid}"
  done
}

_fpm_duplicate_instances_detection() {
  _PHP_V="86 85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    # Count masters for this exact conf path
    _pat="^php-fpm: master process.*/opt/php${e}/etc/php${e}-fpm.conf"
    _cnt=$(_fpm_master_pids "${_pat}" | grep -c .)
    (( _cnt > 1 )) || continue
    # Asked again after a grace and gated like the health check: this
    # restarts the whole version, cutting every request of every pool on it,
    # and one sample under a stall is not evidence of a second master.
    sleep 3
    _cnt=$(_fpm_master_pids "${_pat}" | grep -c .)
    (( _cnt > 1 )) || continue
    _sql_mutation_began && return 0
    _cd="/run/php${e}-fpm.cooldown"
    _now=$(date +%s)
    _ts=
    [ -s "${_cd}" ] && _ts=$(tr -dc '0-9' < "${_cd}" 2> /dev/null)
    if [ -n "${_ts}" ] && [ $(( _now - _ts )) -ge 0 ] \
      && [ $(( _now - _ts )) -lt "${_FPM_COOLDOWN_SECS}" ]; then
      echo "$(date) INFO: php${e}-fpm duplicate master but in cooldown; skipping restart" >> "${_pthOml}"
      continue
    fi
    _thisErrLog="$(date) Duplicate master for php${e}-fpm (count=${_cnt})"
    echo "${_thisErrLog}" >> "${_pthOml}"
    echo "$(date) INFO: php${e}-fpm masters counted: $(ps -o pid=,ppid=,etimes=,args= -p "$(_fpm_master_pids "${_pat}" | paste -sd, -)" 2> /dev/null | tr -s ' ' | tr '\n' ';')" >> "${_pthOml}"
    [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p "/var/backups/php-logs/${_NOW}/"
    mv -f "/var/log/php/php${e}-fpm-error.log" "/var/backups/php-logs/${_NOW}/" &> /dev/null
    service "php${e}-fpm" restart
    wait
    date +%s > "${_cd}"
  done
}

_fpm_giant_log_detection() {
  _PHPLOG_SIZE_TEST=$(du -s -h /var/log/php 2>/dev/null)
  if echo "${_PHPLOG_SIZE_TEST}" | grep -q "G"; then
    _thisErrLog="$(date) Too big PHP error logs detected: ${_PHPLOG_SIZE_TEST}"
    echo ${_thisErrLog} >> ${_pthOml}
    # No restart here; health checks will react if needed.
  fi
}

_fpm_listen_conflict_detection() {
  if [ -e "/var/log/php" ]; then
    _hit=$(_fpm_master_tail | grep -c "already listen on")
    if [ "${_hit}" -gt 0 ]; then
      sleep 2
      _hit2=$(_fpm_master_tail | grep -c "already listen on")
      if [ "${_hit2}" -gt 0 ]; then
        _sql_mutation_began && return 0
        [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
        mv -f /var/log/php/php*-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
        _PHP_V="86 85 84 83 82 81 80 74 73 72 71 70 56"
        for e in ${_PHP_V}; do
          if [ ! -S "/run/www${e}.fpm.socket" ]; then
            _thisErrLog="$(date) FPM listen conflict for php${e}, restarting"
            echo ${_thisErrLog} >> ${_pthOml}
            service "php${e}-fpm" restart
            wait
          fi
        done
      fi
    fi
  fi
}

_fpm_proc_max_detection() {
  # Per-pool saturation is what FPM actually logs when a pool cannot spawn a
  # worker:
  #   WARNING: [pool NAME] server reached max_children setting (N), consider raising it
  # The GLOBAL "process.max" ceiling BOA sets to 0 (disabled) is never logged,
  # so the old grep for it never matched. Match the per-pool string instead.
  #
  # Because that warning line persists in the log until rotation, a flat
  # "tail | grep -c" would re-emit the NOTE on every run (this script runs each
  # minute) for as long as the line stays in the tail window. Track a per-file
  # byte offset so only NEW hits since the last run are reported — same approach
  # scan_nginx.sh uses for its Tier-B FPM-saturation trigger.
  local _posfile="/var/log/boa/fpm_maxchildren.pos"
  local _tmp _f _sz _off _new _hits _hitf
  declare -A _POS
  if [ -f "${_posfile}" ]; then
    while IFS='|' read -r _f _off; do
      [ -n "${_f}" ] && [[ "${_off}" =~ ^[0-9]+$ ]] && _POS["${_f}"]="${_off}"
    done < "${_posfile}"
  fi
  _tmp="${_posfile}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  _hits=0
  _hitf=""
  for _f in /var/log/php/php*-fpm-error.log; do
    [ -f "${_f}" ] || continue
    _sz=$(stat -c %s "${_f}" 2>/dev/null)
    [[ "${_sz}" =~ ^[0-9]+$ ]] || _sz=0
    _off="${_POS["${_f}"]:-0}"
    # Log rotated/truncated since last run: re-baseline from the start.
    (( _sz < _off )) && _off=0
    if (( _sz > _off )); then
      _new=$(tail -c +"$(( _off + 1 ))" "${_f}" 2>/dev/null \
        | grep -v -E "${_FPM_WORKER_LINE}" | grep -c -- "reached max_children setting")
      [[ "${_new}" =~ ^[0-9]+$ ]] || _new=0
      if (( _new > 0 )); then
        _hits=$(( _hits + _new ))
        _hitf="${_hitf} ${_f##*/}(${_new})"
      fi
    fi
    printf '%s|%s\n' "${_f}" "${_sz}" >> "${_tmp}"
  done
  mv -f "${_tmp}" "${_posfile}" 2>/dev/null
  if (( _hits > 0 )); then
    _thisErrLog="$(date) NOTE: PHP-FPM reached max_children setting (${_hits} new hit(s) in${_hitf}). Consider raising pm.max_children for the affected pool(s)"
    echo "${_thisErrLog}" >> "${_pthOml}"
    # No restart; capacity signal only.
  fi
}

# A request a pool cuts at its request_terminate_timeout is logged by the
# master, with no site name, as
#   WARNING: [pool NAME] child PID, script 'PATH' (request: "METHOD URI")
#   execution timed out (SECS sec), terminating
# Each pass reads only what the master logs gained since the last one (a
# byte offset and inode of its own per file; the first run starts at their
# ends, so no earlier cut is counted). One record per cut,
# "time|account|seconds|script|METHOD /segment", goes to root's
# /var/backups/ltd/fpmcut/<account>.<day> for the ltd worker, which tells
# the account; the nightly age prune of /var/backups/ltd/*/* removes a day's
# file a day after its last record. A cut counts for an account only in a
# pool of its own and a script in its own tree outside its control panel's.
# Of the request only the method and the path's first segment are kept,
# never the query string: a Drupal 8+ cron key is a path segment, a search
# its terms. No site is named and nothing else is read: the line has no
# host, and a guess from the access log or the vhosts could hand another
# tenant's name or request to the account; the script's path names the
# platform. Times are read as the box's local time, as the master writes
# them. The offsets are saved before anything is recorded, and a pass that
# cannot save them records nothing: the next one reads the same lines.
_FPM_CUT_AWK='
function dfc(y, m, d,   e, yoe, doy) {
  y -= (m <= 2)
  e = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - e * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  return e * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - 719468
}
function lsec(d, mo, y, hh, mm, ss,   m) {
  m = index("JanFebMarAprMayJunJulAugSepOctNovDec", mo)
  if (m == 0 || (m - 1) % 3) return -1
  return dfc(y + 0, (m + 2) / 3, d + 0) * 86400 + hh * 3600 + mm * 60 + ss
}
function zsec(z,   s) {
  if (z !~ /^[-+][0-9][0-9][0-9][0-9]$/) return 0
  s = substr(z, 2, 2) * 3600 + substr(z, 4, 2) * 60
  return substr(z, 1, 1) == "-" ? -s : s
}
function seg(p,   i) {
  gsub(/[^A-Za-z0-9._~\/%:@+,;=-]/, "_", p)
  p = substr(p, 1, 200)
  i = index(substr(p, 2), "/")
  if (i > 0 && length(p) > i + 1) p = substr(p, 1, i + 1) "\342\200\246"
  return p
}
BEGIN {
  q = "\047"
  pre = "^\\[[0-9][0-9]-[A-Z][a-z][a-z]-[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9](\\.[0-9]+)?\\] WARNING: \\[pool [a-z0-9._-]+\\] child [0-9]+, script " q "/"
  off = zsec(tz)
}
$0 ~ pre {
  t = lsec(substr($0, 2, 2), substr($0, 5, 3), substr($0, 9, 4), substr($0, 14, 2), substr($0, 17, 2), substr($0, 20, 2))
  if (t < 0) next
  t -= off
  r = substr($0, index($0, "] WARNING: [pool ") + 17)
  pool = substr(r, 1, index(r, "]") - 1)
  r = substr(r, index(r, ", script " q) + 10)
  i = index(r, q " (request: \"")
  if (i < 2) next
  sc = substr(r, 1, i - 1)
  r = substr(r, i + 13)
  if (!match(r, /"\) execution timed out \([0-9]+(\.[0-9]+)? sec\), terminating$/)) next
  secs = substr(r, RSTART + 24) + 0
  rq = substr(r, 1, RSTART - 1)
  sp = index(rq, " ")
  if (sp < 2) next
  me = substr(rq, 1, sp - 1)
  pa = substr(rq, sp + 1)
  sub(/\?.*$/, "", pa)
  ac = pool
  sub(/\..*$/, "", ac)
  if (pool ~ /^www[0-9]+$/ || pool ~ /\.hm$/ || ac !~ /^[a-z0-9][a-z0-9_-]*$/) next
  if (index(sc, "/data/disk/" ac "/") != 1 || index(sc, "/data/disk/" ac "/aegir/") == 1) next
  if (sc ~ /\/\.\.?\// || me !~ /^[A-Z]+$/) next
  gsub(/[^A-Za-z0-9._\/+@-]/, "_", sc)
  printf "%.0f|%s|%d|%s|%s %s\n", t, ac, secs, substr(sc, 1, 300), me, seg(pa) >> (dir "/" ac "." day)
}
'
_fpm_timeout_detection() {
  local _posfile="/var/log/boa/fpm_timeout.pos"
  local _dir="/var/backups/ltd/fpmcut"
  local _tmp _cut _f _x _y _off _sz _ino _new _first=YES
  declare -A _POS _INO
  if [ -f "${_posfile}" ]; then
    while IFS='|' read -r _f _x _y; do
      if [ -n "${_f}" ] && [[ "${_x}" =~ ^[0-9]+$ ]]; then
        _POS["${_f}"]="${_x}"
        _INO["${_f}"]="${_y}"
        _first=NO
      fi
    done < "${_posfile}"
  fi
  _tmp="${_posfile}.$$"
  _cut="${_posfile}.cut.$$"
  : > "${_cut}" 2> /dev/null || return 0
  _new=""
  for _f in /var/log/php/php*-fpm-error.log; do
    [ -f "${_f}" ] || continue
    _sz=""
    _ino=""
    read -r _sz _ino < <(stat -c '%s %i' -- "${_f}" 2> /dev/null)
    [[ "${_sz}" =~ ^[0-9]+$ ]] || continue
    if [ "${_first}" = "YES" ]; then
      _off="${_sz}"
    else
      # a log new since the last pass, or moved away by a restart and
      # made again, or rotated: from its start
      _off="${_POS["${_f}"]:-0}"
      if [ "${_INO["${_f}"]:-}" != "${_ino}" ] || (( _sz < _off )); then
        _off=0
      fi
    fi
    if (( _sz > _off )); then
      # as bytes and text whatever they hold: a worker's stderr can put a NUL
      # in the log, a request an invalid UTF-8 byte, and grep would read the
      # chunk as binary and print none of its lines
      tail -c +"$(( _off + 1 ))" -- "${_f}" 2> /dev/null | head -c "$(( _sz - _off ))" \
        | LC_ALL=C grep -a -F -- ') execution timed out (' \
        | LC_ALL=C grep -a -v -E -- "${_FPM_WORKER_LINE}" >> "${_cut}"
    fi
    _new+="${_f}|${_sz}|${_ino}"$'\n'
  done
  if ! printf '%s' "${_new}" > "${_tmp}" 2> /dev/null \
    || ! mv -f "${_tmp}" "${_posfile}" 2> /dev/null; then
    rm -f "${_tmp}" "${_cut}"
    return 0
  fi
  if [ -s "${_cut}" ]; then
    if [ ! -d "${_dir}" ] || [ -L "${_dir}" ]; then
      rm -f "${_dir}"
      mkdir -p "${_dir}"
    fi
    chmod 700 "${_dir}"
    LC_ALL=C awk -v tz="$(date +%z)" -v dir="${_dir}" -v day="$(date +%Y%m%d)" \
      "${_FPM_CUT_AWK}" < "${_cut}" 2> /dev/null
  fi
  rm -f "${_cut}"
}

_fpm_sockets_healing() {
  _hit=$(_fpm_master_tail | grep -c "Address already in use")
  if [ "${_hit}" -gt 0 ]; then
    sleep 2
    _hit2=$(_fpm_master_tail | grep -c "Address already in use")
    if [ "${_hit2}" -gt 0 ]; then
      _sql_mutation_began && return 0
      [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
      mv -f /var/log/php/php*-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
      _PHP_V="86 85 84 83 82 81 80 74 73 72 71 70 56"
      for e in ${_PHP_V}; do
        if [ ! -S "/run/www${e}.fpm.socket" ]; then
          _thisErrLog="$(date) FPM socket conflict sustained for php${e}; restarting"
          echo ${_thisErrLog} >> ${_pthOml}
          service "php${e}-fpm" restart
          wait
        fi
      done
    fi
  fi
}

_fpm_fastcgi_temp() {
  _FASTCGI_SIZE_TEST=$(du -s -h /usr/fastcgi_temp/*/*/* 2>/dev/null | grep G)
  if [ -n "${_FASTCGI_SIZE_TEST}" ]; then
    rm -f /usr/fastcgi_temp/*/*/* 2>/dev/null
    _thisErrLog="$(date) PHP fastcgi_temp too big, cleaned"
    echo ${_thisErrLog} >> ${_pthOml}
    echo "$(date) ${_FASTCGI_SIZE_TEST}" >> ${_pthOml}
    _incident_email_report "PHP fastcgi_temp too big, cleaned"
    echo >> ${_pthOml}
  fi
}

_fpm_health_ok() {
  # ${1} = version: its master, its www socket and its pid file are all there
  pgrep -f "^php-fpm: master process.*/opt/php${1}/etc/php${1}-fpm.conf" >/dev/null 2>&1 || return 1
  [ -S "/run/www${1}.fpm.socket" ] || return 1
  [ -s "/run/php${1}-fpm.pid" ] || return 1
  return 0
}

_fpm_health_check_fix() {
  _thisErrLog=
  _PHP_V="86 85 84 83 82 81 80 74 73 72 71 70 56"
  # The versions the sites and the panel run come first: when a database
  # restart stops every version at once, Nginx is back within seconds and
  # sends requests to them while versions nobody uses would still be healing.
  _ORD=""
  for e in "${_PHP_FPM_VERSION//[^0-9]/}" "${_HM_FPM_VERSION//[^0-9]/}"; do
    if [ -n "${e}" ] && [[ " ${_PHP_V} " == *" ${e} "* ]] \
      && [[ " ${_ORD} " != *" ${e} "* ]]; then
      _ORD="${_ORD} ${e}"
    fi
  done
  for e in ${_PHP_V}; do
    [[ " ${_ORD} " == *" ${e} "* ]] || _ORD="${_ORD} ${e}"
  done
  _PHP_V="${_ORD}"
  # One grace for reloads, shared by every version found down: a grace per
  # version makes each one wait for every version listed before it.
  _DOWN_V=""
  for e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -x "/opt/php${e}/bin/php" ]; then
      _fpm_health_ok "${e}" || _DOWN_V="${_DOWN_V} ${e}"
    fi
  done
  [ -n "${_DOWN_V}" ] || return 0
  sleep 2
  for e in ${_DOWN_V}; do
    if [ -e "/etc/init.d/php${e}-fpm" ] && [ -x "/opt/php${e}/bin/php" ]; then
      _pat="^php-fpm: master process.*/opt/php${e}/etc/php${e}-fpm.conf"

      _ok_master=false; _ok_socket=false; _ok_pid=false
      pgrep -f "${_pat}" >/dev/null 2>&1 && _ok_master=true
      [ -S "/run/www${e}.fpm.socket" ] && _ok_socket=true
      [ -s "/run/php${e}-fpm.pid" ] && _ok_pid=true

      if ! ${_ok_master} || ! ${_ok_socket} || ! ${_ok_pid}; then
        _sql_mutation_began && break
        # Per-version cooldown: /run/php<ver>-fpm.cooldown, gated by
        # _FPM_COOLDOWN_SECS
        _cd="/run/php${e}-fpm.cooldown"
        _now=$(date +%s)
        if [ -s "${_cd}" ]; then
          _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
          if [ -n "${_ts}" ]; then
            _delta=$(( _now - _ts ))
            if [ "${_delta}" -lt "${_FPM_COOLDOWN_SECS}" ]; then
              echo "$(date) INFO: php${e}-fpm unhealthy but in cooldown (${_delta}s < ${_FPM_COOLDOWN_SECS}s); skipping restart" >> ${_pthOml}
              continue
            fi
          fi
        fi

        : > /run/fmp_wait.pid
        : > /run/restarting_fmp_wait.pid

        echo "$(date) php${e}-fpm health failed (master=${_ok_master} socket=${_ok_socket} pid=${_ok_pid}) — restart" >> ${_pthOml}
        [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
        mv -f /var/log/php/php${e}-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
        service "php${e}-fpm" restart

        # Readiness poll, bounded: a master that just restarted can take a
        # few seconds to bind its socket under load, and one second of
        # patience escalated to a needless stop/start.
        _w=0
        _ok_master=false; _ok_socket=false; _ok_pid=false
        while [ "${_w}" -lt 10 ]; do
          sleep 1
          _ok_master=false; _ok_socket=false; _ok_pid=false
          pgrep -f "${_pat}" >/dev/null 2>&1 && _ok_master=true
          [ -S "/run/www${e}.fpm.socket" ] && _ok_socket=true
          [ -s "/run/php${e}-fpm.pid" ] && _ok_pid=true
          if ${_ok_master} && ${_ok_socket} && ${_ok_pid}; then
            break
          fi
          _w=$(( _w + 1 ))
        done

        if ${_ok_master} && ${_ok_socket} && ${_ok_pid}; then
          _thisErrLog="$(date) PHP-FPM ${e} was down, restarted"
          echo ${_thisErrLog} >> ${_pthOml}
          date +%s > "${_cd}"
        else
          # As last resort: stop/start for only this version
          echo "$(date) php${e}-fpm still unhealthy after restart; stop/start" >> ${_pthOml}
          service "php${e}-fpm" stop
          sleep 1
          [ -d "/var/backups/php-logs/${_NOW}" ] || mkdir -p /var/backups/php-logs/${_NOW}/
          mv -f /var/log/php/php${e}-fpm-error.log /var/backups/php-logs/${_NOW}/ &> /dev/null
          service "php${e}-fpm" start
          date +%s > "${_cd}"
        fi

        rm -f /run/fmp_wait.pid /run/restarting_fmp_wait.pid
      fi
    fi
  done
  if [ -n "${_thisErrLog}" ]; then
    _incident_email_report "PHP-FPM was down, restarted"
    echo >> ${_pthOml}
  fi
}

# Fire-and-forget launcher, cron-safe and interactive-safe
_spawn_detached() {
  _cmd="$1"
  if command -v nohup >/dev/null 2>&1; then
    nohup bash -c "${_cmd}" >/dev/null 2>&1 &
  elif command -v setsid >/dev/null 2>&1; then
    setsid bash -c "${_cmd}" >/dev/null 2>&1 &
  else
    ( bash -c "${_cmd}" >/dev/null 2>&1 ) &
  fi
  # If interactive shell, drop it from the job table to mimic cron behavior
  if [[ "$-" == *i* ]]; then disown; fi
}

_fpm_logs_empty() {
  # Decided on the logs the installed versions should actually be writing,
  # not on a bare count of directory entries: the old threshold of three
  # counted anything in the directory and reloaded EVERY pool (clearing
  # APCu box-wide) when it came up short. The remedy is scoped the same
  # way: only the version missing its log is reloaded, behind its own
  # cooldown stamp, so a log that stays absent for a reason a reload does
  # not fix cannot become an APCu-clearing storm.
  local _e _cdE _tsE _nowE
  _PHP_V="86 85 84 83 82 81 80 74 73 72 71 70 56"
  for _e in ${_PHP_V}; do
    if [ -e "/etc/init.d/php${_e}-fpm" ] && [ -x "/opt/php${_e}/bin/php" ] \
      && [ ! -e "/var/log/php/php${_e}-fpm-error.log" ]; then
      # Its OWN stamp, never the health path's: this reload cannot start a
      # dead master, and re-stamping the shared cooldown just before the
      # health check reads it would starve the one remedy that can.
      _cdE="/run/php${_e}-fpm.logfix.cooldown"
      _nowE=$(date +%s)
      if [ -s "${_cdE}" ]; then
        _tsE=$(tr -dc '0-9' < "${_cdE}" 2>/dev/null)
        if [ -n "${_tsE}" ] && [ $((_nowE - _tsE)) -ge 0 ] && [ $((_nowE - _tsE)) -lt "${_FPM_COOLDOWN_SECS}" ]; then
          continue
        fi
      fi
      echo "$(date) php${_e}-fpm error log missing; reloading that version" >> ${_pthOml}
      service "php${_e}-fpm" reload &> /dev/null
      date +%s > "${_cdE}"
    fi
  done
}

_fpm_apcu_reload_sentinel() {
  # A passive mirror (replication standby): the sentinel is the ACTIVE box's
  # self-service request, delivered here only because static/control rides the
  # sync leg. Never consume it on the standby -- acting restarts a box that
  # serves nothing, and deleting the file eats a request that was never ours.
  [ -e "/root/.standby.cnf" ] && return 0

  # Allows site owners on qualifying plans to request a graceful PHP-FPM
  # reload (which clears APCu) by creating an empty sentinel file:
  #
  #   touch ~/static/control/run-php-fpm-reload.pid
  #
  # The system detects the file within seconds, performs a graceful reload
  # of all PHP-FPM versions, and removes the file automatically.
  #
  # Plan gate: mirrors _if_valkey_restart in valkey.sh — only available on
  # POWER, PHANTOM, CLUSTER, ULTRA, MONSTER plans, or box-wide via
  # _ALLOW_PHP_FPM_RELOAD=YES in /root/.barracuda.cnf (the former
  # /etc/boa/.allow.php.fpm.reload.cnf flag stays honoured during the
  # conversion window).
  #
  # Why this is needed:
  #   APCu caches field definitions, plugin registries, and other Drupal
  #   internals at the PHP-FPM worker process level. Unlike Valkey, APCu
  #   cannot be flushed remotely — it lives inside the FPM worker processes.
  #   After a config change, platform update, or Solr core rename, stale APCu
  #   entries can cause FieldException and PluginNotFoundException errors in
  #   Drupal logs. A graceful FPM reload recycles all workers and clears APCu
  #   without dropping active connections.
  #
  # Cooldown: respects _FPM_COOLDOWN_SECS (default 30s) to prevent reload
  # storms if the sentinel is created repeatedly.

  # Plan-level gate — same logic as _if_valkey_restart in valkey.sh
  local _PrTestPower _PrTestPhantom _PrTestCluster _PrTestUltra _PrTestMonster
  _PrTestPower=$(grep "POWER" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestUltra=$(grep "ULTRA" /root/.*.octopus.cnf 2>/dev/null)
  _PrTestMonster=$(grep "MONSTER" /root/.*.octopus.cnf 2>/dev/null)

  if [[ "${_PrTestPower}"   =~ "POWER"   ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
    || [[ "${_PrTestUltra}"   =~ "ULTRA"   ]] \
    || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
    || [ -e "/etc/boa/.allow.php.fpm.reload.cnf" ] \
    || [ "${_ALLOW_PHP_FPM_RELOAD}" = "YES" ]; then
    : # plan allows self-service FPM reload — proceed
  else
    return 0  # plan does not allow self-service FPM reload
  fi

  local _FpmTest
  _FpmTest=$(ls /data/disk/*/static/control/run-php-fpm-reload.pid 2>/dev/null | wc -l)
  [ "${_FpmTest}" -lt 1 ] && return 0

  # Cooldown check — reuse php84-fpm cooldown as shared gate since a reload
  # affects all FPM versions simultaneously
  local _cd="/run/php84-fpm.cooldown"
  local _now
  _now=$(date +%s)
  if [ -s "${_cd}" ]; then
    local _ts _delta
    _ts=$(tr -d '\n' < "${_cd}" 2>/dev/null)
    if [ -n "${_ts}" ]; then
      _delta=$(( _now - _ts ))
      if [ "${_delta}" -lt "${_FPM_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: run-php-fpm-reload.pid found but in cooldown (${_delta}s < ${_FPM_COOLDOWN_SECS}s); skipping" >> ${_pthOml}
        rm -f /data/disk/*/static/control/run-php-fpm-reload.pid
        return 0
      fi
    fi
  fi

  echo "$(date) PHP-FPM reload requested via sentinel — reloading to clear APCu" >> ${_pthOml}
  rm -f /data/disk/*/static/control/run-php-fpm-reload.pid
  _fpm_reload "SENTINEL"

  # Update cooldown timestamp for all FPM versions
  local _PHP_V="86 85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    [ -e "/etc/init.d/php${e}-fpm" ] && date +%s > "/run/php${e}-fpm.cooldown"
  done
  echo "$(date) PHP-FPM reload complete (APCu cleared)" >> ${_pthOml}
}


# /var/tmp/fpm is sticky (1777) and root's: every pool keeps its opcache
# lockfile there and none may remove another's. valkey/ in it holds the
# backoff flag every pool and CLI shares and is 0777 without the sticky bit
# on purpose (any pool must replace or remove a flag another armed), so the
# kernel's link protections do not cover it: PHP uses it only while it and
# its parent are real root-owned directories, and root keeps them so. A
# wrong entry is moved into a fresh root-only directory (mktemp) and removed
# there, after its replacement exists; a new one is only ever made with a
# plain mkdir, which fails on any name that exists, a link included, and is
# then left to the next pass. valkey/ is handled from inside root's own
# /var/tmp/fpm, and modes are set only on root's own entries, which no other
# user can move in these sticky root-owned parents.
_fpm_tmp_enforce() {
  local _d=/var/tmp/fpm
  local _old
  if [ -L "${_d}" ] || { [ -e "${_d}" ] && [ ! -d "${_d}" ]; } \
    || { [ -d "${_d}" ] && [ "$(stat -c '%u' "${_d}")" != "0" ]; }; then
    _old="$(mktemp -d /var/tmp/.fpm.old.XXXXXXXX)" || return 1
    if mv -T -- "${_d}" "${_old}/fpm"; then
      mkdir "${_d}" && chmod 1777 "${_d}"
    fi
    rm -rf --one-file-system -- "${_old}"
  fi
  if [ ! -e "${_d}" ] && [ ! -L "${_d}" ]; then
    mkdir "${_d}" && chmod 1777 "${_d}"
  fi
  [ -d "${_d}" ] && [ ! -L "${_d}" ] \
    && [ "$(stat -c '%u' "${_d}")" = "0" ] || return 1
  if [ "$(stat -c '%g %a' "${_d}")" != "0 1777" ]; then
    chgrp root "${_d}" && chmod 1777 "${_d}"
  fi
  (
    cd -P -- "${_d}" && [ "$(stat -c '%u' .)" = "0" ] || exit 1
    if [ -L ./valkey ] || { [ -e ./valkey ] && [ ! -d ./valkey ]; } \
      || { [ -d ./valkey ] && [ "$(stat -c '%u' ./valkey)" != "0" ]; }; then
      _old="$(mktemp -d ./.valkey.old.XXXXXXXX)" || exit 1
      if mv -T -- ./valkey "${_old}/valkey"; then
        mkdir -m 0777 ./valkey
      fi
      rm -rf --one-file-system -- "${_old}"
    fi
    if [ ! -e ./valkey ] && [ ! -L ./valkey ]; then
      mkdir -m 0777 ./valkey || exit 1
    fi
    [ -d ./valkey ] && [ ! -L ./valkey ] \
      && [ "$(stat -c '%u' ./valkey)" = "0" ] || exit 1
    if [ "$(stat -c '%g %a' ./valkey)" != "0 777" ]; then
      chgrp root ./valkey && chmod 0777 ./valkey
    fi
    # a directory at the flag name keeps every pool from arming the backoff
    if [ -d ./valkey/disabled.flag ] && [ ! -L ./valkey/disabled.flag ]; then
      rm -rf --one-file-system -- ./valkey/disabled.flag
    fi
  )
}
_fpm_tmp_enforce

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
  # the same two markers: mysql_restart_running.pid, written by move_sql.sh,
  # and boa_mysql_auto_healing.pid, held by the database watchdog for the
  # length of its heal.
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

# Asked again after a grace and before a restart: move_sql.sh writes its
# marker and only then stops every PHP-FPM master, so a master or socket
# gone after the grace may be that stop under way, and a restart now would
# bring PHP-FPM up in the middle of the database restart. Once seen, the
# rest of the pass restarts nothing.
_FPM_SQL_MUT=NO
_sql_mutation_began() {
  [ "${_FPM_SQL_MUT}" = "YES" ] && return 0
  _sql_mutation_in_flight || return 1
  _FPM_SQL_MUT=YES
  return 0
}

if [ ! -e "/run/max_load.pid" ] && [ ! -e "/run/critical_load.pid" ] \
  && ! _sql_mutation_in_flight; then
  _fpm_apcu_reload_sentinel
  _fpm_logs_empty
  _fpm_duplicate_instances_detection
  _fpm_listen_conflict_detection
  _fpm_proc_max_detection
  _fpm_timeout_detection
  _fpm_sockets_healing
  _fpm_fastcgi_temp
  _fpm_giant_log_detection
  _fpm_health_check_fix
  if [ ! -e "/root/.high_traffic.cnf" ] \
    && [ ! -e "/root/.giant_traffic.cnf" ]; then
    _spawn_detached 'perl /var/xdrago/monitor/check/segfault_alert.pl'
  fi
fi

echo DONE!
exit 0
