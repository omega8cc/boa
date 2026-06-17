#!/bin/bash

# =============================================================================
# newrelic_sysmond.sh — New Relic server monitor (nrsysmond) watchdog for BOA
# Split from: proc_num_ctrl.pl (legacy Perl service monitor)
#
# Driven by the opt-in flag /etc/boa/.enable.newrelic.sysmond.cnf:
#   - flag present + daemon down  -> restart
#   - flag absent  + daemon up    -> stop
# Equivalent to the legacy lines:
#   system("service newrelic-sysmond restart")
#     if (!$newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond"
#         && -f "/etc/boa/.enable.newrelic.sysmond.cnf");
#   system("service newrelic-sysmond stop")
#     if ($newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond"
#         && !-f "/etc/boa/.enable.newrelic.sysmond.cnf");
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

###
### Skip service recovery while a BOA upgrade/maintenance run is in progress.
### Mirrors proc_num_ctrl.pl's any_file_exists($run_to_files) guard.
###
_run_to_active() {
  local _f
  for _f in /root/.run-to-excalibur.cnf /root/.run-to-daedalus.cnf \
            /root/.run-to-chimaera.cnf /root/.run-to-beowulf.cnf \
            /run/boa_run.pid; do
    [ -e "${_f}" ] && return 0
  done
  return 1
}
_run_to_active && exit 0

if [ -f "/etc/init.d/newrelic-sysmond" ]; then
  if [ -e "/etc/boa/.enable.newrelic.sysmond.cnf" ]; then
    pgrep -f nrsysmond >/dev/null 2>&1 || service newrelic-sysmond restart
  else
    pgrep -f nrsysmond >/dev/null 2>&1 && service newrelic-sysmond stop
  fi
fi

exit 0
