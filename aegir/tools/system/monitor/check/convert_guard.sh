#!/bin/bash

# =============================================================================
# convert_guard.sh — runaway ImageMagick `convert` watcher/killer
# Split from: proc_num_ctrl.pl (legacy Perl service monitor)
#
# Mirrors the legacy convert_action: only acts when more than one `convert`
# process is running; inspects each one and, when it is hot (>10% CPU), has
# accumulated CPU time, and is in R/Z state, either kills it (when more than 5
# are running AND it exceeds 50% CPU) logging to convert.kill.log, or records
# it to convert.watch.log otherwise.
#
# The original walked `ps auxf` and relied on forest-indentation field offsets
# to pick out convert children; this inspects each convert PID directly, which
# is behaviourally equivalent (same processes, same thresholds) and robust.
# The lenient cumulative-time test is preserved verbatim (legacy split of the
# [HH:]MM:SS TIME column on ':' and a >1 test of the second field).
#
# Launched every ~5s (load-gated) from second.sh _proc_control. Single-shot.
# =============================================================================

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

###
### Atomic lock to prevent overlapping runs
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    # shellcheck source=/dev/null
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    _single_instance_lock
  else
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc "${_SCRIPT}")
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

_LOG_KILL="/var/log/boa/convert.kill.log"
_LOG_WATCH="/var/log/boa/convert.watch.log"

# Gate: only act when more than one ImageMagick convert process is running
# (legacy: convert_action invoked only when $convertsumar > 1).
mapfile -t _PIDS < <(pgrep -x convert 2>/dev/null)
_count="${#_PIDS[@]}"
[ "${_count}" -gt 1 ] || exit 0

_ts="$(date +%y%m%d-%H%M%S)"

for _pid in "${_PIDS[@]}"; do
  read -r _cpu _stat _time _user \
    < <(ps -o pcpu=,stat=,time=,user= -p "${_pid}" 2>/dev/null)
  [ -n "${_cpu}" ] || continue

  # Keep %CPU as a float and compare with awk, matching the legacy numeric
  # tests ($CPU > 10 / $CPU > 50) exactly (no integer-truncation boundary skew).
  _cpu="${_cpu//[^0-9.]/}"; _cpu="${_cpu:-0}"

  # Legacy TIME parse: split [HH:]MM:SS on ':' and test the SECOND field > 1.
  _min="${_time#*:}"; _min="${_min%%:*}"
  _min="${_min#0}"; _min="${_min//[^0-9]/}"; _min="${_min:-0}"

  if awk "BEGIN{exit !(${_cpu} > 10)}" && [ "${_min}" -gt 1 ] \
    && { [[ "${_stat}" == *R* ]] || [[ "${_stat}" == *Z* ]]; }; then
    if [ "${_count}" -gt 5 ] && awk "BEGIN{exit !(${_cpu} > 50)}"; then
      kill -9 "${_pid}" 2>/dev/null
      echo "${_user} ${_cpu} ${_stat} ${_time} ${_ts} KILL ${_count}" >> "${_LOG_KILL}"
    else
      echo "${_user} ${_cpu} ${_stat} ${_time} ${_ts} WATCH ${_count}" >> "${_LOG_WATCH}"
    fi
  fi
done

exit 0
