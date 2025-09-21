#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
_check_root

[ -e "/root/.proxy.cnf" ] && exit 0

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

touch /run/boa_wait.pid
sleep 8
dir=/var/log/boa/mysql_optimize
mkdir -p $dir
_SQL_PSWD=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
/usr/bin/mysqlcheck -u root -Aa >> $dir/all.a.$(date +%y%m%d-%H%M%S)
/usr/bin/mysqlcheck -u root -A --auto-repair >> $dir/all.r.$(date +%y%m%d-%H%M%S)
/usr/bin/mysqlcheck -u root -Ao >> $dir/all.o.$(date +%y%m%d-%H%M%S)
[ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
exit 0

