#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

###
### Weekly disk trim. Blocks a box frees (deleted backups, rotated logs, a
### removed seed copy, expired binary logs) stay taken on thin or SSD storage
### until the filesystem tells the disk they are free. A virtual disk with
### discard enabled then gives the space back to its host. Devuan runs no
### systemd timer for this, so BOA runs `fstrim -a` once a week itself.
###
### fstrim -a trims every mounted filesystem whose device takes discards and
### skips the rest without error, so a disk without discard support costs
### nothing. One trim schedule per box: where another one already runs (a
### weekly trim laid in /etc/cron.d/vm-fstrim, a cron.weekly or cron.monthly
### job, an enabled systemd fstrim.timer), this run stands down.
### /root/.deny.fstrim.cnf switches it off.
###

_LOG="${_FSTRIM_LOG:-/var/log/boa/fstrim.log}"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c3 -p $$ &> /dev/null
    renice 19 -p $$ &> /dev/null
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

_msg() {
  mkdir -p "$(dirname "${_LOG}")"
  echo "$(date '+%F %T') ${1}" >> "${_LOG}"
}

[ -e "/root/.deny.fstrim.cnf" ] && { _msg "SKIP: /root/.deny.fstrim.cnf"; exit 0; }
[ -e "/etc/boa/.pause_tasks_maint.cnf" ] && { _msg "SKIP: maintenance pause"; exit 0; }
[ -e "/run/boa_run.pid" ] && { _msg "SKIP: a BOA run is in flight"; exit 0; }

_FSTRIM="$(command -v fstrim 2> /dev/null)"
[ -n "${_FSTRIM}" ] && [ -x "${_FSTRIM}" ] || { _msg "SKIP: no fstrim on this box"; exit 0; }

_other_schedule() {
  local _f
  for _f in /etc/cron.d/vm-fstrim /etc/cron.weekly/fstrim /etc/cron.monthly/fstrim; do
    if [ -e "${_f}" ] && grep -qE '^[^#]*fstrim' "${_f}" 2> /dev/null; then
      echo "${_f}"
      return 0
    fi
  done
  if command -v systemctl &> /dev/null \
    && systemctl is-enabled fstrim.timer &> /dev/null; then
    echo "systemd fstrim.timer"
    return 0
  fi
  return 1
}
_other="$(_other_schedule)" && { _msg "SKIP: another weekly trim runs here (${_other})"; exit 0; }

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    _single_instance_lock
  else
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -u root -U root -fc "(^|(^| )[^ ]*bash )[^ ]*/${_SCRIPT//./\\.}( |$)")
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

_out="$("${_FSTRIM}" -av 2>&1)"
_rc=$?
while IFS= read -r _line; do
  [ -n "${_line}" ] && _msg "  ${_line}"
done <<< "${_out}"
case "${_rc}" in
  0)  _msg "DONE: trim finished" ;;
  64) _msg "DONE: trim finished on some filesystems; the others failed (rc 64)" ;;
  32) _msg "NOTE: no filesystem here takes discards (rc 32)" ;;
  *)  _msg "FAIL: fstrim ended with rc ${_rc}" ;;
esac
exit 0
