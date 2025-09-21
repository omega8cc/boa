#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/log/boa/oom.incident.log"
_oldOml="/var/log/boa/oom.incident.old.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "$_L" ] && . "$_L" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy one-slot guard ---------
    # allow up to ONE concurrent worker; exit the 2nd+
    # Robustly match only the real worker:
    #  - direct exec:  "/full/path/script"
    #  - via bash:     "bash /full/path/script"
    _ABS="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
    # escape regex specials for pgrep
    _PAT="$(printf '%s' "$_ABS" | sed 's/[.[\*^$(){}+?\\|]/\\&/g')"
    # Count only lines that contain our absolute path, *and* either begin with bash+path or path at a word boundary.
    # This avoids counting the wrapper like '/bin/dash -c bash /path/script …' twice.
    _CNT=$(
      ps ax -o pid= -o args= \
        | awk -v P="$_PAT" '
            $0 ~ ("(^|[[:space:]]|/)bash[[:space:]]+" P "([[:space:]]|$)") ||
            $0 ~ ("(^|[[:space:]])" P "([[:space:]]|$)")
          ' \
        | wc -l
    )
    if [ "${_CNT:-0}" -gt 1 ]; then
      mkdir -p /var/log/boa 2>/dev/null || true
      echo "Too many ${_SELF_NAME} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

[ ! -d "/var/xdrago/monitor/log" ] && mkdir -p /var/xdrago/monitor/log

if [ -e "${_pthOml}" ] && [ ! -e "${_oldOml}" ]; then
  mv -f ${_pthOml} ${_oldOml}
fi

bash /var/xdrago/monitor/check/nginx.sh &
bash /var/xdrago/monitor/check/php.sh &
if [ -e "/etc/init.d/valkey-server" ]; then
  bash /var/xdrago/monitor/check/valkey.sh &
elif [ -e "/etc/init.d/redis-server" ]; then
  bash /var/xdrago/monitor/check/redis.sh &
fi
bash /var/xdrago/monitor/check/mysql.sh &
bash /var/xdrago/monitor/check/unbound.sh &
bash /var/xdrago/monitor/check/system.sh &
bash /var/xdrago/monitor/check/java.sh &

_second_flood_guard() {
  _thisCountSec=`ps aux | grep -v "grep" | grep -v "null" | grep --count "/second.sh"`
  if [ "${_thisCountSec}" -gt 4 ]; then
    echo "$(date) Too many ${_thisCountSec} second.sh processes killed" >> \
      /var/log/sec-count.kill.log
    kill -9 $(ps aux | grep '[s]econd.sh' | awk '{print $2}') &> /dev/null
  fi
}
[ ! -e "/run/boa_run.pid" ] && _second_flood_guard

echo DONE!
exit 0

