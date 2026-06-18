#!/bin/bash

# =============================================================================
# syslog_legacy.sh — legacy syslog daemon watchdog (sysklogd / inetutils-syslogd)
# Split from: proc_num_ctrl.pl (legacy Perl service monitor)
#
# rsyslog (the BOA default) is watched by monitor/check/system.sh. This script
# covers only the two legacy alternatives, which are mutually exclusive (a host
# installs at most one): sysklogd or inetutils-syslogd.
#
# Faithful to the legacy elsif chain, which handled syslog ONLY when no DHCP
# client was active (the DHCP branch — now hostname_sync.sh — took priority):
#   if ($dhcpcdlives || $dhclientlives) { ...hostname... }
#   elsif (-f "/etc/init.d/sysklogd")          { ...restart sysklogd... }
#   elsif (-f "/etc/init.d/inetutils-syslogd") { ...restart inetutils-syslogd... }
# The DHCP precedence is preserved below so behaviour is unchanged.
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

### Preserve legacy precedence: skip while a DHCP client is active (that path
### is handled by hostname_sync.sh, exactly as the original elsif chain did).
if pgrep -x dhcpcd >/dev/null 2>&1 || pgrep -x dhclient >/dev/null 2>&1; then
  exit 0
fi

if [ -f "/etc/init.d/sysklogd" ]; then
  if ! pgrep -f /sbin/syslogd >/dev/null 2>&1 || [ ! -e "/run/syslogd.pid" ]; then
    # Legacy quirk preserved: the original killed by the name "sysklogd"
    # (the daemon binary is actually "syslogd"); the restart below recovers
    # the service regardless.
    killall -9 sysklogd >/dev/null 2>&1
    service sysklogd restart
  fi
elif [ -f "/etc/init.d/inetutils-syslogd" ]; then
  if ! pgrep -f /sbin/syslogd >/dev/null 2>&1 || [ ! -e "/run/syslog.pid" ]; then
    killall -9 syslogd >/dev/null 2>&1
    service inetutils-syslogd restart
  fi
fi

exit 0
