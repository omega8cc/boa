#!/bin/bash

# =============================================================================
# hostname_sync.sh — enforce the configured hostname on DHCP-managed hosts
# Split from: proc_num_ctrl.pl (legacy Perl service monitor)
#
# When a DHCP client (dhcpcd or dhclient) is active, a lease renewal can reset
# the running hostname; this restores it from /etc/hostname. Equivalent to:
#   if ($dhcpcdlives || $dhclientlives) {
#     $wanted = `cat /etc/hostname`; $current = `hostname`;
#     system("hostname","-b",$wanted) if ($current ne $wanted);
#   }
# A non-empty /etc/hostname is required before applying (avoids ever setting an
# empty hostname — the only deliberate hardening over the original).
#
# This is the DHCP branch of the legacy elsif chain; the no-DHCP branch (legacy
# syslog recovery) lives in syslog_legacy.sh, preserving their mutual exclusion.
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

if pgrep -x dhcpcd >/dev/null 2>&1 || pgrep -x dhclient >/dev/null 2>&1; then
  _wanted="$(cat /etc/hostname 2>/dev/null)"
  _current="$(hostname 2>/dev/null)"
  if [ -n "${_wanted}" ] && [ "${_current}" != "${_wanted}" ]; then
    hostname -b "${_wanted}"
  fi
fi

exit 0
