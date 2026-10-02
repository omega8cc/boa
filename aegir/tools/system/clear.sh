#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=lts

_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf

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
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

_os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
  _OS_LIST="excalibur daedalus chimaera beowulf buster bullseye bookworm trixie"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}

_apt_clean_update() {
  _os_detection_minimal
  ${_APT_UPDATE} -qq 2> /dev/null
  _CALLER_SCRIPT="$(basename "${BASH_SOURCE[-1]}")"
  _CALLER_SCRIPT="${_CALLER_SCRIPT//[^a-zA-Z0-9._-]/_}"
  date +%s > "/run/_latest_apt_clean_update.${_CALLER_SCRIPT}.pid"
}

_FIVE_MINUTES=$(date --date '5 minutes ago' +"%Y-%m-%d %H:%M:%S")
find /run/fmp_wait.pid              -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null
find /run/restarting_fmp_wait.pid   -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null
find /run/boa_cron_wait.pid         -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null
find /run/boa*_auto_healing.pid     -type f -not -newermt "${_FIVE_MINUTES}" -exec rm -f {} \; 2>/dev/null

# Never age-reap an installer lock while its owner may still be alive: a full
# install routinely outlives these windows, and reaping mid-pass is what let
# concurrent passes purge the build tree a chained install was still consuming.
# Once the owner is gone the next tick reaps as before, so nothing leaks.
_installer_alive() {
  # Anchored, not a bare substring: any command line merely MENTIONING the
  # wrapper -- an editor, a checksum, an operator's ssh probe -- would
  # otherwise hold installer-lock reaping off indefinitely.
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/barracuda( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/octopus( |$)" > /dev/null 2>&1 && return 0
  # Anchored: a LOCAL install only -- "ssh root@box /opt/local/bin/boa in-"
  # (xoct/xcopy driving a remote install) must not hold this box's reaping
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-" > /dev/null 2>&1 && return 0
  # Dual-path for the staging move -- see the same guard in BOA.sh.txt.
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 && return 0
  return 1
}

_ONE_HOUR=$(date --date '1 hour ago' +"%Y-%m-%d %H:%M:%S")
find /run/mysql_restart_running.pid  -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null
if ! _installer_alive; then
  find /run/boa_wait.pid             -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null
  # Second, independent reaper for the install marker: runner.sh's reaper
  # sits below its own early exits (pause/proxy/queue-stop/df guards), so
  # it must never be the only recovery path for a leaked marker
  find /run/octopus_install_run.pid  -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null
fi
find /run/manage*users.pid           -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null
find /run/speed_cleanup.pid          -type f -not -newermt "${_ONE_HOUR}" -exec rm -f {} \; 2>/dev/null

_THR_HOURS=$(date --date '3 hours ago' +"%Y-%m-%d %H:%M:%S")
# The queue-stop file holds the Ægir task queue during a maintenance move; purge
# it only when its owner PID is gone (a crashed/leaked hold) so a legitimately long
# move is never unpaused mid-flight. Only root writes it, so a pid that another
# user's process now has is gone too (the real uid in /proc/<pid>/status), and it
# is removed only while it still names the pid read, so a pause another operation
# created meanwhile stays. /run is also cleared on reboot.
if [ -e "/run/boa_queue_stop.pid" ]; then
  _qs_pid=$( { tr -dc '0-9' < /run/boa_queue_stop.pid; } 2>/dev/null )
  if { [ -z "${_qs_pid}" ] || ! kill -0 "${_qs_pid}" 2>/dev/null \
    || [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_qs_pid}/status" 2>/dev/null)" != "0" ]; } \
    && [ "$( { tr -dc '0-9' < /run/boa_queue_stop.pid; } 2>/dev/null )" = "${_qs_pid}" ]; then
    rm -f /run/boa_queue_stop.pid
  fi
fi
# The web group's holds: the master's task-queue hold (runner.sh stops on it)
# and each account's hold (the nightly skips the account on it) carry the pid
# of the root instgrp run that took them, and a run killed outright leaves
# them behind until that account's next web-group run. Removed here as the
# queue-stop file above: when the pid is gone or is not root's, and only
# while the file still names the pid read; an empty one only once it is a
# minute old (a run writes its pid just after it creates the file).
for _wgHold in /run/boa_master_queue_stop.pid /run/instgrp-web-*.pid; do
  [ -f "${_wgHold}" ] || continue
  _wgPid=$( { tr -dc '0-9' < "${_wgHold}"; } 2>/dev/null )
  if [ -z "${_wgPid}" ]; then
    [ -n "$(find "${_wgHold}" -maxdepth 0 -type f -mmin +1 2>/dev/null)" ] || continue
  elif kill -0 "${_wgPid}" 2>/dev/null \
    && [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_wgPid}/status" 2>/dev/null)" = "0" ]; then
    continue
  fi
  [ "$( { tr -dc '0-9' < "${_wgHold}"; } 2>/dev/null )" = "${_wgPid}" ] && rm -f -- "${_wgHold}"
done
# The run lock carries a pid only when instgrp wrote it; the barracuda,
# octopus and boa wrappers create it empty and refuse to start while it
# exists. A pid there whose process is gone (or is not root's) is a killed
# instgrp's leftover, and every reader of the lock (the queue runner, the
# nightly, the limited-shell worker and the web-group witnesses it runs)
# would wait for it until the sweep below, hours later. Removed only while
# it still names the pid read.
if [ -s "/run/boa_run.pid" ]; then
  _rl_pid=$( { tr -dc '0-9' < /run/boa_run.pid; } 2>/dev/null )
  if [ -n "${_rl_pid}" ] \
    && { ! kill -0 "${_rl_pid}" 2>/dev/null \
      || [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_rl_pid}/status" 2>/dev/null)" != "0" ]; } \
    && [ "$( { tr -dc '0-9' < /run/boa_run.pid; } 2>/dev/null )" = "${_rl_pid}" ]; then
    rm -f /run/boa_run.pid
    [ -d "/var/log/boa" ] && echo "$(date) reaped /run/boa_run.pid left by a killed run (pid ${_rl_pid})" >> /var/log/boa/clear.hold.incident.log
  fi
fi
if ! _installer_alive; then
  find /run/boa_run.pid              -type f -not -newermt "${_THR_HOURS}" -exec rm -f {} \; 2>/dev/null
fi
# Hard ceiling: liveness suppression must never be unbounded -- a hung (not
# dead) installer still matching the sweep would otherwise hold the locks
# forever and silently stop the fleet self-update on this box
_TWELVE_HOURS=$(date --date '12 hours ago' +"%Y-%m-%d %H:%M:%S")
find /run/boa_wait.pid               -type f -not -newermt "${_TWELVE_HOURS}" -exec rm -f {} \; 2>/dev/null
find /run/boa_run.pid                -type f -not -newermt "${_TWELVE_HOURS}" -exec rm -f {} \; 2>/dev/null
find /run/octopus_install_run.pid    -type f -not -newermt "${_TWELVE_HOURS}" -exec rm -f {} \; 2>/dev/null
# A migration's runner park (xoct/xcopy pre-mig until post-mig, an xmass
# cutover until its unpark) holds the five runners out of the tools refresh. Bounded: a migration abandoned
# without post-mig gets its dispatcher, nightly, usage, graceful and worker
# back within a day. Re-running pre-mig re-arms the marker.
_ONE_DAY=$(date --date '24 hours ago' +"%Y-%m-%d %H:%M:%S")
if [ -n "$(find /run/boa_migration_park.pid -type f -not -newermt "${_ONE_DAY}" 2>/dev/null)" ]; then
  rm -f /run/boa_migration_park.pid
  [ -d "/var/log/boa" ] \
    && echo "$(date) migration runner park expired after 24 hours; the runners are fetched back" \
    >> /var/log/boa/clear.hold.incident.log
fi
find /run/*_backup.pid               -type f -not -newermt "${_THR_HOURS}" -exec rm -f {} \; 2>/dev/null
find /run/daily-fix.pid              -type f -not -newermt "${_THR_HOURS}" -exec rm -f {} \; 2>/dev/null
# The SQL backups' wait marker, held while a run waits for migratefs to
# release /data/disk/arch, has no age bound: a run killed in its wait
# leaves it behind, and a later process given its pid would hold off every
# SQL backup. Removed once its pid is not a live root process that runs an
# SQL backup script (the real uid in /proc/<pid>/status: /proc/<pid> itself
# shows root as the owner of any process that is not dumpable), and only
# while it still names that pid, so a run writing it afresh keeps it.
if [ -e "/run/boa_sql_backup_wait.pid" ]; then
  _sw_pid=$( { tr -dc '0-9' < /run/boa_sql_backup_wait.pid; } 2>/dev/null )
  if ! { [ -n "${_sw_pid}" ] && kill -0 "${_sw_pid}" 2>/dev/null \
    && [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_sw_pid}/status" 2>/dev/null)" = "0" ] \
    && { tr '\0' ' ' < "/proc/${_sw_pid}/cmdline"; } 2>/dev/null \
    | grep -qE '^([^ ]*/)?bash (-[^ ]+ )*([^ ]*/)?mysql_(cluster_)?backup\.sh( |$)'; } \
    && [ "$( { tr -dc '0-9' < /run/boa_sql_backup_wait.pid; } 2>/dev/null )" = "${_sw_pid}" ]; then
    rm -f /run/boa_sql_backup_wait.pid
  fi
fi

# PHP-idle surgery quiesce: barracuda holds this while swapping PHP
# versions; a marker whose owner PID is gone is stale (crashed run) and
# is cleared, never obeyed -- and /run clears itself on reboot.
if [ -e "/run/boa_php_idle_quiesce.pid" ]; then
  _qsPid=$( { tr -dc '0-9' < /run/boa_php_idle_quiesce.pid; } 2>/dev/null )
  if [ -n "${_qsPid}" ] && kill -0 "${_qsPid}" 2>/dev/null; then
    [ "$1" = "wait" ] && exit 3
    exit 0
  fi
  rm -f /run/boa_php_idle_quiesce.pid
fi

#
# Find the fastest mirror.
_find_fast_mirror_early() {
  _isNetc="$(which netcat)"
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    [ ! -e "/run/clear_m.pid" ] && _apt_clean_update
    apt-get install netcat-traditional ${_aptYesUnth} 2> /dev/null
    wait
  fi
  _ffMirr=/opt/local/bin/ffmirror
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2026-07.txt"
    [ -d "/var/backups" ] || mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "files.boa.io"  > ${_ffList}
      echo "files.o8.io" >> ${_ffList}
      echo "files.host8.biz" >> ${_ffList}
      echo "files.aegir.biz" >> ${_ffList}
      echo "files.aoboshi.com" >> ${_ffList}
      if [ -e "/etc/csf/csf.allow" ]; then
        sed -i "s/.*aegir.*//g" /etc/csf/csf.allow
        csf -a 172.235.166.69  files.boa.io &> /dev/null
        csf -a 172.233.219.37  files.o8.io &> /dev/null
        csf -a 172.105.168.103 files.host8.biz &> /dev/null
        csf -a 88.216.74.103  files.aegir.biz &> /dev/null
        csf -a 88.216.74.97   files.aoboshi.com &> /dev/null
        if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
          csf -ra &> /dev/null
          synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
        else
          csf -r &> /dev/null
        fi
      fi
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.boa.io"
      else
        _USE_MIR="files.boa.io"
      fi
    else
      _USE_MIR="files.boa.io"
    fi
  else
    _USE_MIR="files.boa.io"
  fi
  _urlDev="https://${_USE_MIR}/dev"
  _urlHmr="https://${_USE_MIR}/versions/${_tRee}/boa/aegir"
}

_if_reinstall_curl_src() {
  _CURL_VRN=8.22.0
  if ! command -v lsb_release &> /dev/null; then
    apt-get update -qq &> /dev/null
    apt-get install lsb-release ${_aptYesUnth} -qq &> /dev/null
  fi
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
  [ "${_OS_CODE}" = "wheezy" ] && _CURL_VRN=7.50.1
  [ "${_OS_CODE}" = "jessie" ] && _CURL_VRN=7.71.1
  [ "${_OS_CODE}" = "stretch" ] && _CURL_VRN=8.2.1
  _isCurl=$(curl --version 2>&1)
  if [[ ! "${_isCurl}" =~ "OpenSSL" ]] || [ -z "${_isCurl}" ]; then
    echo "OOPS: cURL is broken! Re-installing.."
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    echo "curl install" | dpkg --set-selections 2> /dev/null
    [ ! -e "/run/clear_m.pid" ] && _apt_clean_update
    # Check for libssl1.0-dev and remove conditionally
    if dpkg-query -W -f='${Status}' libssl1.0-dev 2>/dev/null | grep -q "install ok installed"; then
      apt-get remove libssl1.0-dev -y --purge --auto-remove -qq 2>/dev/null
    fi
    apt-get autoremove -y 2> /dev/null
    apt-get install libssl-dev ${_aptYesUnth} -qq 2> /dev/null
    apt-get build-dep curl -y 2> /dev/null
    if [ ! -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      apt-get install curl --reinstall ${_aptYesUnth} -qq 2> /dev/null
    fi
    if [ -e "/var/aegir/.drush/hm.alias.drushrc.php" ]; then
      echo "INFO: Installing curl from sources..."
      mkdir -p /var/opt
      rm -rf /var/opt/curl*
      cd /var/opt
      wget ${_wgetGet} https://files.boa.io/dev/src/curl-${_CURL_VRN}.tar.gz &> /dev/null
      tar -xzf curl-${_CURL_VRN}.tar.gz &> /dev/null
      if [ -e "/root/.install.modern.openssl.cnf" ] \
        && [ -x "/usr/local/ssl3/bin/openssl" ]; then
        _SSL_BINARY=/usr/local/ssl3/bin/openssl
      else
        _SSL_BINARY=/usr/local/ssl/bin/openssl
      fi
      if [ -e "/usr/local/ssl3/lib64/libssl.so.3" ]; then
        _SSL_PATH="/usr/local/ssl3"
        _SSL_LIB_PATH="${_SSL_PATH}/lib64"
      else
        _SSL_PATH="/usr/local/ssl"
        _SSL_LIB_PATH="${_SSL_PATH}/lib"
      fi
      _PKG_CONFIG_PATH="${_SSL_LIB_PATH}/pkgconfig"

      if [ -e "${_PKG_CONFIG_PATH}" ] \
        && [ -e "/var/opt/curl-${_CURL_VRN}" ]; then
        cd /var/opt/curl-${_CURL_VRN}
        LIBS="-ldl -lpthread" PKG_CONFIG_PATH="${_PKG_CONFIG_PATH}" ./configure \
          --with-openssl \
          --with-zlib=/usr \
          --prefix=/usr/local &> /dev/null
        make -j $(nproc) --quiet &> /dev/null
        make --quiet install &> /dev/null
        ldconfig 2> /dev/null
      fi
    fi
    if [ -f "/usr/local/bin/curl" ]; then
      _isCurl=$(/usr/local/bin/curl --version 2>&1)
      if [[ ! "${_isCurl}" =~ "OpenSSL" ]] || [ -z "${_isCurl}" ]; then
        echo "ERRR: /usr/local/bin/curl is broken"
      else
        echo "GOOD: /usr/local/bin/curl works"
      fi
    fi
  fi
}

_check_dns_curl() {
  _find_fast_mirror_early
  _if_reinstall_curl_src
  _CURL_TEST=$(curl -L -s \
    --max-redirs 10 \
    --retry 3 \
    --retry-delay 10 \
    -I "https://${_USE_MIR}" 2> /dev/null)
  if [[ ! "${_CURL_TEST}" =~ "HTTP/2 200" ]]; then
    if [[ "${_CURL_TEST}" =~ "unknown option was passed in to libcurl" ]]; then
      echo "ERROR: cURL libs are out of sync! Re-installing again.."
      _if_reinstall_curl_src
    else
      echo "ERROR: ${_USE_MIR} is not available, please try later"
    fi
  fi
}

# One self-update at a time. clear.sh runs from two schedulers on purpose
# (the root crontab and /etc/crontab, on staggered minutes) and by hand, and
# everything above is safe to repeat; the BOA.sh.txt run and autoupboa below
# are not: two runs that overlapped replaced the same shared module from one
# download, one unpacked it half written, and both stamped it deployed. The
# lock is a pid file, never flock (BOA.sh.txt restarts daemons, which would
# inherit the descriptor). Every take goes through a claim directory (mkdir is
# atomic), so one run at a time looks at the lock and only that run writes it,
# whole, by a rename. It is trusted only while its pid is a live clear.sh run
# as root and for 3 hours at most, so the reapers above never need to know it.
# "clear.sh wait" (a caller that needs the tools current now, such as xmass)
# waits up to 20 minutes for a running self-update instead of skipping its own.
_SELF_LOCK=/run/boa_selfupdate.pid
_self_lock_pid() {
  { tr -dc '0-9' < "${_SELF_LOCK}"; } 2>/dev/null
}
_self_lock_live() {
  local _p="$1"
  [ -n "${_p}" ] && [ "${_p}" != "$$" ] && kill -0 "${_p}" 2>/dev/null \
    && [ "$(awk '/^Uid:/ { print $2; exit }' "/proc/${_p}/status" 2>/dev/null)" = "0" ] \
    && { tr '\0' ' ' < "/proc/${_p}/cmdline"; } 2>/dev/null \
    | grep -qE '^([^ ]*/)?bash (-[^ ]+ )*([^ ]*/)?clear\.sh( |$)'
}
# 0: taken, or /run cannot hold a lock (the run then goes ahead without it,
# flagged: the self-update is what can deliver a fix); 1: held elsewhere.
_self_lock_take() {
  local _c="${_SELF_LOCK}.claim" _t="${_SELF_LOCK}.$$"
  find /run -maxdepth 1 -name 'boa_selfupdate.pid.*' -type f -mmin +60 -delete 2>/dev/null
  if ! mkdir "${_c}" 2>/dev/null; then
    if ! { : > "${_t}"; } 2>/dev/null; then
      _SELF_LOCK_OPEN=YES
      return 0
    fi
    rm -f "${_t}"
    # another run is taking the lock right now, or a killed run left its claim
    [ -n "$(find "${_c}" -maxdepth 0 -mmin +2 2>/dev/null)" ] && rmdir "${_c}" 2>/dev/null
    return 1
  fi
  if [ -e "${_SELF_LOCK}" ] && _self_lock_live "$(_self_lock_pid)" \
    && [ -z "$(find "${_SELF_LOCK}" -not -newermt "${_THR_HOURS}" 2>/dev/null)" ]; then
    rmdir "${_c}" 2>/dev/null
    return 1
  fi
  if echo "$$" > "${_t}" 2>/dev/null && mv -f "${_t}" "${_SELF_LOCK}" 2>/dev/null; then
    rmdir "${_c}" 2>/dev/null
    return 0
  fi
  rm -f "${_t}"
  rmdir "${_c}" 2>/dev/null
  _SELF_LOCK_OPEN=YES
  return 0
}
_self_lock_release() {
  local _c="${_SELF_LOCK}.claim" _i=0 _got=NO
  while [ "${_i}" -lt 20 ]; do
    mkdir "${_c}" 2>/dev/null && { _got=YES; break; }
    sleep 0.1
    _i=$((_i + 1))
  done
  [ "$(_self_lock_pid)" = "$$" ] && rm -f "${_SELF_LOCK}"
  [ "${_got}" = "YES" ] && rmdir "${_c}" 2>/dev/null
}
# An install or upgrade in flight holds the self-update too (see below).
_install_held() {
  [ -e "/run/boa_run.pid" ] || [ -e "/run/boa_wait.pid" ] \
    || [ -e "/run/octopus_install_run.pid" ] || _installer_alive
}
# A wait-mode run checks the install holds again after every pause: an install
# can start while it waits, even from the run it waits for.
_self_lock_gate() {
  local _i=0
  _self_lock_take && return 0
  [ "${_CLEAR_MODE}" = "wait" ] || return 1
  while [ "${_i}" -lt 120 ]; do
    sleep 10
    _install_held && return 1
    _self_lock_take && return 0
    _i=$((_i + 1))
  done
  return 1
}
_CLEAR_MODE="$1"
_CLEAR_RC=0
_SELF_LOCK_OPEN=NO

# Hold both the key-tools self-update and autoupboa while ANY install or
# important task is in flight, not just while boa_run.pid exists -- the
# chained install's octopus leg holds only octopus_install_run.pid, and a
# BOA.sh.txt run in that window used to purge the consumed build tree
if ! _install_held && _self_lock_gate; then
  if [ "${_SELF_LOCK_OPEN}" = "YES" ] && [ -d "/var/log/boa" ]; then
    echo "$(date) self-update ran without its lock: ${_SELF_LOCK} could not be written" >> /var/log/boa/clear.hold.incident.log
  fi
  _check_dns_curl
  rm -f /tmp/*error*
  # Piping straight into bash cannot tell "ran the meta-installer" from "the
  # mirror served nothing": an empty body, or the mirror's HTML placeholder for
  # a tree it does not carry, both leave bash with nothing to do and exit 0, so
  # a box can stop self-updating every 5 minutes for hours and say nothing.
  # Fetch first, require the file's own first line, and run it from stdin so the
  # invocation stays exactly what it was (BASH_SOURCE, hence the per-caller apt
  # cadence stamp, is read inside).
  _boaShTmp=/var/opt/.boa.sh.txt.$$
  if wget -q -O "${_boaShTmp}" https://${_USE_MIR}/versions/${_tRee}/boa/BOA.sh.txt \
    && grep -q "^export _tRee=" "${_boaShTmp}"; then
    bash < "${_boaShTmp}"
  else
    [ -d "/var/log/boa" ] \
      && echo "$(date) OOPS: ${_USE_MIR} served no usable BOA.sh.txt for the ${_tRee} tree" \
        >> /var/log/boa/mirror.incident.log
  fi
  rm -f "${_boaShTmp}"
  wait
  if [ -e "/run/clear.hold.last" ]; then
    [ -d "/var/log/boa" ] && echo "$(date) hold released (was$(cat /run/clear.hold.last 2>/dev/null))" >> /var/log/boa/clear.hold.incident.log
    rm -f /run/clear.hold.last
  fi
  bash /opt/local/bin/autoupboa
  wait
  _self_lock_release
else
  # Name what held this tick: with the self-update and autoupboa skipped in
  # silence, a fresh install's reset marker arrived anywhere between 1 and
  # 15 minutes after its last pass and nothing recorded which gate held.
  # One line per change of holder, not per tick (a stale marker would write
  # 288 lines a day for ever), under the rotated *.incident.log name.
  _held=""
  for _m in boa_run.pid boa_wait.pid octopus_install_run.pid; do
    [ -e "/run/${_m}" ] && _held="${_held} ${_m}"
  done
  if [ -z "${_held}" ]; then
    if _installer_alive; then
      _held=" installer-alive"
    else
      # Another self-update is running: routine when the two schedules
      # overlap, so it is only said here; the log records a holder only once
      # it has run for over 30 minutes.
      echo "clear.sh: self-update skipped, another run holds ${_SELF_LOCK}"
      _held=""
      [ -n "$(find "${_SELF_LOCK}" -mmin +30 2>/dev/null)" ] \
        && _held=" boa_selfupdate.pid (over 30 minutes)"
    fi
  fi
  if [ -n "${_held}" ] && [ -d "/var/log/boa" ] \
    && [ "${_held}" != "$(cat /run/clear.hold.last 2>/dev/null)" ]; then
    echo "${_held}" > /run/clear.hold.last
    echo "$(date) self-update and autoupboa held by${_held}" >> /var/log/boa/clear.hold.incident.log
  fi
  # a caller that asked to wait (xmass) is told the self-update did not run
  if [ "${_CLEAR_MODE}" = "wait" ]; then
    _CLEAR_RC=3
    [ -d "/var/log/boa" ] \
      && echo "$(date) clear.sh wait: self-update not run (held by${_held:- boa_selfupdate.pid})" \
        >> /var/log/boa/clear.hold.incident.log
  fi
fi

# The box tells the mirror its BOA release and OS release, and nothing else,
# as the User-Agent of one HEAD request: what decides when a legacy OS can be
# dropped. It lives only in the mirrors' rotated access logs. Opt out with
# _VERSION_REPORT=NO in /root/.barracuda.cnf.
if [ -d "/data/u" ] && [ "${_VERSION_REPORT}" != "NO" ]; then
  _checkVn=$(/opt/local/bin/boa version 2>/dev/null | grep -o "BOA-[^ ]*" | head -1)
  if [ -z "${_checkVn}" ] && [ -e "/var/log/barracuda_log.txt" ]; then
    _checkVn=$(tail --lines=1 /var/log/barracuda_log.txt | grep -o "BOA-[^ ]*" | head -1)
  fi
  [ -z "${_checkVn}" ] && _checkVn="BOA-unknown"
  _checkOs=$(. /etc/os-release 2>/dev/null; echo "${ID} ${VERSION_ID} ${VERSION_CODENAME}" | xargs)
  [ -z "${_checkOs}" ] && _checkOs="os-unknown"
  _crlHead="-I -s --retry 3 --retry-delay 3"
  _urlBpth="https://${_USE_MIR}/versions/${_tRee}/boa/aegir/tools/bin"
  curl ${_crlHead} -A "${_checkVn} ${_checkOs}" "${_urlBpth}/thinkdifferent" &> /dev/null
  wait
fi

_if_fix_locked_sshd() {
  _SSH_LOG="/var/log/auth.log"
  if [ `tail --lines=30 ${_SSH_LOG} \
    | grep --count "error: Bind to port 22"` -gt 0 ]; then
    pkill -9 -f '^(sshd: )?/usr/sbin/sshd( |$)' || true
    service ssh start
  fi
}
_if_fix_locked_sshd

#setprio &> /dev/null

if [ -e "/root/.remote_backups/schedule/backup_schedule.txt" ]; then
  if [ -e "/root/.remote_backups/paths/paths.txt" ]; then
    rm -f /root/.remote_backups/paths/*
    rm -f /root/.remote_backups/paths/.*
    [ -x "/usr/local/bin/dcysetup" ] && bash /usr/local/bin/dcysetup update &> /dev/null
  fi
  # Genuine duplicity executions only, the same anchored pair as the
  # _fetch_versioned guard: duplicity runs as its venv python with the
  # console script as the script argument, and a bare substring match
  # also deferred this arm whenever any command line merely mentioned
  # the word (an editor, a tail, an operator probe).
  _CNT="$(pgrep -fc "^([^ ]*/)?((ba|da)?sh|python[0-9.]*) (-[^ ]+ )*[^ ]*duplicity( |$)" 2>/dev/null)"
  _CNT="${_CNT:-0}"
  _CNTD="$(pgrep -fc "^[^ ]*duplicity( |$)" 2>/dev/null)"
  _CNTD="${_CNTD:-0}"
  if (( _CNT + _CNTD > 0 )); then
    echo "[$(date)] Active duplicity process detected, will try again later..." >> /var/log/mybackup_waiting_queue.log
  else
    [ -x "/usr/local/bin/dcysetup" ] && bash /usr/local/bin/dcysetup update &> /dev/null
    wait
    [ -x "/usr/local/bin/mybackup" ] && nohup /usr/local/bin/mybackup > /dev/null 2>&1 &
  fi
fi

touch /var/log/boa/clear.done.pid
exit ${_CLEAR_RC}
