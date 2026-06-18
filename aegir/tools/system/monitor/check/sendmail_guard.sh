#!/bin/bash

# =============================================================================
# sendmail_guard.sh — kill rogue root-owned sendmail MTA processes
# Split from: proc_num_ctrl.pl (legacy Perl service monitor)
#
# BOA delivers mail via postfix/msmtp; a root-owned sendmail MTA should never
# be running. The legacy global_action loop did, every pass:
#   system("kill -9 $PID") if $COMMAND =~ /sendmail/ && $USER =~ /root/;
# matching the process executable (first ps token). Reproduced here against the
# process comm, with an explicit self-exclusion so this guard never targets
# itself or its shell.
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

# Kill root-owned processes whose executable name contains "sendmail",
# excluding this guard itself and its interpreter.
while read -r _pid _comm; do
  [ -n "${_pid}" ] || continue
  case "${_comm}" in
    sendmail_guard*|bash|sh|dash) continue ;;
    *sendmail*) kill -9 "${_pid}" 2>/dev/null ;;
  esac
done < <(ps -u root -o pid=,comm= 2>/dev/null)

exit 0
