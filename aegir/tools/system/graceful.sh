#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Function to check if the script is run as root
_check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script should be run as root"
    exit 1
  else
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
  fi
  # Get the hostname
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
}
_check_root

# Exit if the operator paused heavy maintenance
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

# PHP-idle surgery quiesce: barracuda holds this while swapping PHP
# versions; a marker whose owner PID is gone is stale (crashed run) and
# is cleared, never obeyed -- and /run clears itself on reboot.
if [ -e "/run/boa_php_idle_quiesce.pid" ]; then
  _qsPid=$( { tr -dc '0-9' < /run/boa_php_idle_quiesce.pid; } 2>/dev/null )
  if [ -n "${_qsPid}" ] && kill -0 "${_qsPid}" 2>/dev/null; then
    exit 0
  fi
  rm -f /run/boa_php_idle_quiesce.pid
fi

# Function to calculate RAM usage percentage as an integer
_calculate_ram_usage_percent() {
  _total_ram_kb=$1
  _available_ram_kb=$2
  used_ram_kb=$((_total_ram_kb - _available_ram_kb))

  # Using integer division to get a whole number percentage
  echo $(( (used_ram_kb * 100) / _total_ram_kb ))
}

# Function to check and display system info
_check_system_ram() {
  # Get the total and available RAM in KB
  _total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  _available_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

  # Calculate RAM usage percentage
  _ram_usage_percent=$(_calculate_ram_usage_percent ${_total_ram_kb} ${_available_ram_kb})
}

# Function to check and optimize RAM and disk caches
_optimize_ram() {
  _check_system_ram
  if [ "${_ram_usage_percent}" -gt 90 ]; then
    sync && echo 3 | tee /proc/sys/vm/drop_caches
  fi
}

_find_fast_mirror_early() {
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
  export _urlDev="https://${_USE_MIR}/dev"
}

# Function to download GeoLite2 databases
_fetch_geoip() {

  # Prepare GeoIP directories
  echo "Setting up GeoIP directories..."
  mkdir -p /usr/share/GeoIP
  chmod 755 /usr/share/GeoIP

  # Download and install GeoIP databases
  echo "Downloading GeoIP databases..."
  mkdir -p /opt/tmp
  cd /opt/tmp
  rm -f /opt/tmp/Geo*

  # For GeoIP2 ASN database:
  wget -q -U iCab ${_urlDev}/src/GeoLite2-ASN.mmdb.gz
  gunzip GeoLite2-ASN.mmdb.gz &> /dev/null
  cp -af GeoLite2-ASN.mmdb /usr/share/GeoIP/

  # For GeoIP2 City database:
  wget -q -U iCab ${_urlDev}/src/GeoLite2-City.mmdb.gz
  gunzip GeoLite2-City.mmdb.gz &> /dev/null
  cp -af GeoLite2-City.mmdb /usr/share/GeoIP/

  # For GeoIP2 Country database:
  wget -q -U iCab ${_urlDev}/src/GeoLite2-Country.mmdb.gz
  gunzip GeoLite2-Country.mmdb.gz &> /dev/null
  cp -af GeoLite2-Country.mmdb /usr/share/GeoIP/

  chmod 644 /usr/share/GeoIP/*
  rm -f /opt/tmp/Geo*
  cd
}

# Delete only the bounce notices (null sender, listed as MAILER-DAEMON).
# Mail a site sent that is merely deferred keeps postfix's own retry
# lifetime: wiping the whole queue destroyed transactional mail held back
# by a temporary delivery problem.
_purge_postfix_bounces() {
  local _qIds
  _qIds="$(postqueue -p 2> /dev/null | tail -n +2 \
    | awk 'BEGIN { RS = "" } $7 == "MAILER-DAEMON" { print $1 }' \
    | tr -d '*!')"
  if [ -n "${_qIds}" ]; then
    echo "${_qIds}" | postsuper -d - &> /dev/null
  fi
}

# Once a week, remove the copies older than 7 days that BOA leaves on every run
# and every day and nothing else removes: the PHP-FPM logs moved aside on each
# FPM restart and each barracuda or octopus run (php-logs/<stamp>/), and the
# csf.allow copies guest-water takes before each provider refresh (csf/water/);
# then the dragon vault and the other families below. Age is when a copy was
# made (ctime): cp -a keeps the mtime of the file it copies. A stamp sets the
# pace, not a weekday, so a night this pass skips only moves the prune to the
# next night it runs.
_purge_weekly_backups() {
  local _wkStamp="/var/backups/.graceful.weekly.prune.stamp"
  if [ -e "${_wkStamp}" ] \
    && [ -z "$(find "${_wkStamp}" -mmin +9000 2> /dev/null)" ]; then
    return 0
  fi
  echo "Removing old backup copies, markers and leftovers..."
  if [ -d "/var/backups/php-logs" ] && [ ! -L "/var/backups/php-logs" ]; then
    find /var/backups/php-logs -mindepth 1 -maxdepth 1 -ctime +6 \
      -exec rm -rf {} + &> /dev/null
  fi
  if [ -d "/var/backups/csf/water" ] && [ ! -L "/var/backups/csf/water" ]; then
    find /var/backups/csf/water -mindepth 1 -maxdepth 1 -type f -ctime +6 \
      -delete &> /dev/null
  fi
  _prune_dragon_vault
  _purge_run_copies
  _purge_markers
  _purge_dated_files
  _purge_leftovers
  touch "${_wkStamp}"
}

# Files dated by the day or the event that nothing reads once that day is past:
# multiback's per-day run markers (it tests only today's), the nginx error logs
# the monitor sets aside at a restart (with the rotated copy the distro's nginx
# rules make of each), codebasecheck's reports (boa info greps them all, so old
# ones kept showing), the flood detector's snapshots, and the copies synproxy
# takes of csf's config at each run (its rollback does not read them).
_purge_dated_files() {
  local _dfD="[0-9][0-9][0-9][0-9][0-9][0-9]"
  _prune_older_than /var/log/boa "back-to-*.${_dfD}.*.log" 30
  _prune_older_than /var/log/nginx "${_dfD}-[0-9][0-9][0-9][0-9]-error.log*" 30
  _prune_older_than /var/log/boa/core 'incompatible-*.log' 30
  _prune_older_than /var/log/boa/core 'box-readiness-*.log' 30
  _prune_older_than /var/xdrago/monitor/log/i18n_flood '[0-9]*-*.txt' 90
  _prune_keep_newest /etc/csf 'csfpost.sh.bak.[0-9]*' 3
  _prune_keep_newest /etc/csf 'csf.conf.bak.[0-9]*' 3
}

# Markers BOA writes in /var/log/boa on every run, at each release or for each
# build. A run reads only its own or the current one, so the newest three are
# kept (by ctime) and none goes by age: a release or a PHP build stays current
# for months. The PHP extension markers are kept per extension and PHP branch,
# since every installed branch has its own current one, and the shared module
# markers per module; a name that does not parse is left alone.
_purge_markers() {
  local _mkL="/var/log/boa" _mkP _mkE _mkB _mkM
  for _mkP in 'sysctl.conf-*.log' 'sec-valkey-pass-*.log' '.curl_libs_fix_*.pid' \
    '._php_libs_fix_*.pid' 'pure-ftpd-build-*.log' 'valkey-*.log' \
    'mss-build-ok-*.log' 'nginx-config-params-fixed-*.log' \
    'fix-drupal-site-permissions-*.log' '.force.f*.ctrl' \
    '.csf_legacy_cleanup.*.pid' '.csf_dhcp_udp_cleanup.*.pid' \
    '.disabled_modules_fix.*.pid' '.curl_ctrl.*.pid' \
    '.etc_crontab_lock_state.*.txt' 'apt-deb-src-updates-*.txt' \
    'lshell-fix-build-*.log' 'csf_BOA-*.log' 'libmagickwand-dev-*-rebuild.log'; do
    _prune_keep_newest "${_mkL}" "${_mkP}" 3
  done
  for _mkE in apcu imagick igbinary f_yaml phpredis-update f_uploadprogress \
    mcrypt php-pecl-jsmin php-geos; do
    for _mkB in $(find "${_mkL}" -mindepth 1 -maxdepth 1 -type f -name "${_mkE}-*.log" \
      -printf '%f\n' 2> /dev/null \
      | sed -n "s/^${_mkE}-.*-\([0-9]\{1,2\}\.[0-9]\{1,2\}\)\.[0-9]\{1,3\}[A-Za-z0-9]*\.log\$/\1/p" \
      | sort -u); do
      _prune_keep_newest "${_mkL}" "${_mkE}-*-${_mkB}.[0-9]*.log" 3
    done
  done
  for _mkM in $(find "${_mkL}" -mindepth 1 -maxdepth 1 -type f -name '*.ctrl.*.log' \
    -printf '%f\n' 2> /dev/null | sed -n 's/^\([a-z_]*\)\.ctrl\.[0-9a-zA-Z]*\.log$/\1/p' \
    | sort -u); do
    _prune_keep_newest "${_mkL}" "${_mkM}.ctrl.*.log" 3
  done
}

# The dragon vault's copies other than config/ go once they are a week old, by
# when each was made (ctime), the rule owl.sh's nightly pass also applies. That
# pass does not run on a standby or a proxy, where barracuda still runs and
# adds a full copy of /var/xdrago to dragon/x on every pass.
_prune_dragon_vault() {
  local _dvS
  [ -d "/var/backups/dragon" ] && [ ! -L "/var/backups/dragon" ] || return 0
  find /var/backups/dragon -mindepth 1 -maxdepth 1 ! -name config ! -type d \
    -ctime +7 -delete &> /dev/null
  for _dvS in /var/backups/dragon/*; do
    [ -d "${_dvS}" ] && [ ! -L "${_dvS}" ] || continue
    [ "${_dvS##*/}" = "config" ] && continue
    find "${_dvS}" -mindepth 1 -maxdepth 1 -ctime +7 \
      -exec rm -rf {} + &> /dev/null
  done
}

# Remove all but the newest $3 entries the find pattern $2 names directly in
# the real directory $1, newest by when each was made there (ctime).
_prune_keep_newest() {
  local _kDir="${1}" _kPat="${2}" _kKeep="${3}"
  [ -d "${_kDir}" ] && [ ! -L "${_kDir}" ] || return 0
  find "${_kDir}" -mindepth 1 -maxdepth 1 -name "${_kPat}" -printf '%C@ %p\0' \
    2> /dev/null | LC_ALL=C sort -z -rn | tail -z -n +$(( _kKeep + 1 )) \
    | cut -z -d' ' -f2- | xargs -0 -r rm -rf -- &> /dev/null
}

# Remove the entries the find pattern $2 names directly in the real directory
# $1 that were made there more than $3 days ago (ctime).
_prune_older_than() {
  local _oDir="${1}" _oPat="${2}" _oDays="${3}"
  [ -d "${_oDir}" ] && [ ! -L "${_oDir}" ] || return 0
  find "${_oDir}" -mindepth 1 -maxdepth 1 -name "${_oPat}" -ctime +"${_oDays}" \
    -exec rm -rf {} + &> /dev/null
}

# Copies BOA makes on every run or on a change and never reads again: the
# config files a barracuda pass replaces, csf's allow and ignore lists at each
# release, the libcurl a cURL change retires, the PHP build options a debug
# build writes, and the drush aliases syncpass rewrites, kept per alias and
# account (a name that does not parse is left alone).
_purge_run_copies() {
  local _rcAls _rcUsr _rcStm="[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]"
  _prune_keep_newest /var/backups 'sources.list-pre-*' 3
  _prune_keep_newest /var/backups '.etc.rsyslog.conf-pre-*' 3
  _prune_keep_newest /var/backups 'resolv.conf.pre-*' 3
  _prune_keep_newest /var/backups 'nginx-pre-*' 3
  _prune_keep_newest /var/backups/csf 'csf.allow.*.txt' 5
  _prune_keep_newest /var/backups/csf 'csf.ignore.*.txt' 5
  _prune_keep_newest /var/backups 'legacy-libcurl-pre-*' 1
  _prune_older_than /var/backups 'php_extra_*' 30
  for _rcAls in server_master server_localhost; do
    for _rcUsr in $(find /var/backups -mindepth 1 -maxdepth 1 -type f \
      -name "${_rcAls}.alias.drushrc.php.*-${_rcStm}" -printf '%f\n' 2> /dev/null \
      | sed -n "s/^${_rcAls}\.alias\.drushrc\.php\.\([a-z0-9._]*\)-[0-9]\{6\}-[0-9]\{6\}\$/\1/p" \
      | sort -u); do
      _prune_keep_newest /var/backups \
        "${_rcAls}.alias.drushrc.php.${_rcUsr}-${_rcStm}" 3
    done
  done
}

# Leftovers no current code writes or reads, removed once: the copies of the
# MySQL root password and client config older releases kept at the top of
# /var/backups (they go to dragon/config now), the log folder used before
# /var/log/boa (BOA.sh.txt copied its files there once and then wrote
# .migrated.txt), markers whose writers are gone, and the attack archives older
# releases set aside at each release (<name>.archive.<serial>.log and
# <name>.archive-old-*.log); the live archives and their one-time .x3 copies,
# which guest-water and xdr9000 read, stay. The old folder is emptied only after
# that copy, and never when it leads to /var/log/boa itself.
_purge_leftovers() {
  local _lfA
  rm -f /var/backups/.my.pass.txt-pre-* /var/backups/.my.cnf-pre-*
  if [ -e "/var/log/boa/.migrated.txt" ] \
    && [ -d "/var/xdrago/log" ] && [ ! -L "/var/xdrago/log" ] \
    && [ "$(readlink -f /var/xdrago/log)" != "$(readlink -f /var/log/boa)" ]; then
    find /var/xdrago/log -mindepth 1 -maxdepth 1 ! -name EMPTY.txt \
      -exec rm -rf {} + &> /dev/null
  fi
  rm -f /var/log/boa/sec-redis-pass-* /var/log/boa/.custom_percona_forced.* \
    /var/log/boa/mss-build-master-* /var/log/boa/geos-* \
    /var/log/boa/nginx.kill-start.log /var/log/boa/cron-count.kill.log
  if [ -d "/var/xdrago/monitor/log" ] && [ ! -L "/var/xdrago/monitor/log" ]; then
    for _lfA in hackcheck scan_nginx hackftp; do
      find /var/xdrago/monitor/log -mindepth 1 -maxdepth 1 -type f \
        \( -name "${_lfA}.archive.*.log" ! -name "${_lfA}.archive.x3.log" \
        -o -name "${_lfA}.archive-old-*.log" \) -delete &> /dev/null
    done
  fi
}

# A session cgroup is idle when no process is in it or below it and it has no
# child cgroup.
_session_cgroup_idle() {
  local _cgKey _cgVal _cgSub
  local _cgPop=1
  [ -d "$1" ] && [ -r "$1/cgroup.events" ] || return 1
  while read -r _cgKey _cgVal; do
    if [ "${_cgKey}" = "populated" ]; then
      _cgPop="${_cgVal}"
    fi
  done < "$1/cgroup.events"
  [ "${_cgPop}" = "0" ] || return 1
  for _cgSub in "$1"/*/; do
    [ -d "${_cgSub}" ] && return 1
  done
  return 0
}

# elogind never removes the cgroup it makes for each login session, and every
# su, cron run and ssh login makes one; their kernel memory grows until the
# OOM killer steps in. Barracuda removes elogind's PAM module, but where it is
# still in place (or a long session ended since) remove the empty session
# cgroups: top-level c<N> and <N> directories on the cgroup2 hierarchy elogind
# mounts, never on a systemd host, only those idle at two reads three seconds
# apart. The kernel refuses rmdir on a populated cgroup in any case.
_trim_session_cgroups() {
  local _cgDir _cgLeft
  local -a _cgCand=()
  local -a _cgGone=()
  [ -d "/run/systemd/system" ] && return 0
  grep -qs "^[^ ]* /sys/fs/cgroup cgroup2 " /proc/mounts || return 0
  for _cgDir in /sys/fs/cgroup/c[0-9]* /sys/fs/cgroup/[0-9]*; do
    [[ "${_cgDir##*/}" =~ ^c?[0-9]+$ ]] || continue
    _session_cgroup_idle "${_cgDir}" && _cgCand+=("${_cgDir}")
  done
  (( ${#_cgCand[@]} )) || return 0
  sleep 3
  for _cgDir in "${_cgCand[@]}"; do
    _session_cgroup_idle "${_cgDir}" && _cgGone+=("${_cgDir}")
  done
  (( ${#_cgGone[@]} )) || return 0
  printf '%s\0' "${_cgGone[@]}" | xargs -0 rmdir 2> /dev/null
  _cgLeft=0
  for _cgDir in "${_cgGone[@]}"; do
    [ -d "${_cgDir}" ] && _cgLeft=$(( _cgLeft + 1 ))
  done
  echo "Removed $(( ${#_cgGone[@]} - _cgLeft )) empty login-session cgroups"
}

# Main action function
_graceful_action() {
  echo "Starting system maintenance tasks..."

  # Update Devuan mirrors daily
  _ffDevuan="$(which ffdevuan)"
  _pthLog="/var/log/boa/ffdevuan.update.log"
  if [ -x "${_ffDevuan}" ]; then
    bash ${_ffDevuan} >> ${_pthLog}
    wait
    echo "Devuan Mirrors Updated on [$(date)]" >> ${_pthLog}
    echo >> ${_pthLog}
  fi

  # Clean up postfix queue to get rid of bounced emails
  echo "Removing bounce notices from postfix queue..."
  _purge_postfix_bounces

  # Restart syslog service
  echo "Restarting syslog service..."
  if [ -e "/etc/init.d/rsyslog" ]; then
    pkill -9 rsyslogd
    service rsyslog start
  fi

  # Swap, RAM and disk cache management
  _IF_BCP="$(pgrep -f '^([^ ]*/)?((ba|da)?sh|python[0-9.]*) (-[^ ]+ )*[^ ]*duplicity( |$)'; pgrep -f '^[^ ]*duplicity( |$)')"
  if [ -d "/dev/disk" ]; then
    if [ ! -e "/root/.no.swap.clear.cnf" ]; then
      if [ -n "${_IF_BCP}" ]; then
        # Old shape ran swapoff unconditionally and skipped only the
        # swapon, leaving the box SWAPLESS for a day whenever a backup
        # overlapped 03:01. Defer the whole reset instead.
        echo "Backup in progress; swap reset deferred to the next run..."
      else
        echo "Resetting swap..."
        swapoff -a
        swapon -a
      fi
    fi
    echo "Optimizing RAM usage..."
    _optimize_ram
  fi

  echo "Removing empty login-session cgroups..."
  _trim_session_cgroups

  # Setup GeoIP directories
  if [ ! -e "/usr/share/GeoIP/GeoLite2-City.mmdb" ]; then
    _find_fast_mirror_early
    _fetch_geoip
  fi

  # Cleanup for /opt/tmp/sess*
  rm -f /opt/tmp/sess*

  _purge_weekly_backups

  # Speed cleanup
  _IF_BCP="$(pgrep -f '^([^ ]*/)?((ba|da)?sh|python[0-9.]*) (-[^ ]+ )*[^ ]*duplicity( |$)'; pgrep -f '^[^ ]*duplicity( |$)')"
  if [ -z "${_IF_BCP}" ] && [ ! -e "/run/speed_cleanup.pid" ] && [ ! -e "/root/.giant_traffic.cnf" ]; then
    echo "Performing speed cleanup..."
    touch /run/speed_cleanup.pid
    echo " " >> /var/log/nginx/speed_cleanup.log
    sed -i "s/levels=2:2:2/levels=2:2/g" /var/aegir/config/server_master/nginx.conf
    service nginx reload &> /dev/null
    echo "speed_purge start $(date)" >> /var/log/nginx/speed_cleanup.log
    nice -n 9 ionice -c2 -n7 find /var/lib/nginx/speed/ -mtime +1 -exec rm -rf {} \; &> /dev/null
    echo "speed_purge complete $(date)" >> /var/log/nginx/speed_cleanup.log
    service nginx reload &> /dev/null
    rm -f /run/speed_cleanup.pid
  fi

  touch /var/log/boa/graceful.done.pid
  echo "System maintenance tasks completed."
}

# Main script execution

# Check for ongoing operations or skip configurations
# In-flight gate. This mirrors _boa_pass_active in owl.sh deliberately (see the
# master/satellite mirror rule): boa_run.pid alone is not enough -- the chained
# install's octopus leg holds only octopus_install_run.pid, boa_wait.pid covers
# the queued window, and the Ægir setup children match none of the wrapper forms
# yet are exactly the phase that rewrites the trees this script sed's and
# reloads nginx against.
_boa_pass_active() {
  [ -e "/run/boa_run.pid" ] && return 0
  [ -e "/run/boa_wait.pid" ] && return 0
  [ -e "/run/octopus_install_run.pid" ] && return 0
  # xmass windows: the init/copy-back phase is exactly when a swapoff or
  # cache drop can OOM the restore. Fresh-bounded like their consumers
  # (second.sh 2880 min for the init signal, mysql.sh 240 min for the
  # maintenance mute) so a stale marker cannot park this script forever.
  [ -n "$(find /run/boa_xmass_init.pid /root/.standby.init.pid -mmin -2880 2> /dev/null)" ] && return 0
  [ -n "$(find /run/boa_sql_maintenance.pid -mmin -240 2> /dev/null)" ] && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/(barracuda|octopus)( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?(bash|sh|su) .*/aegir/scripts/AegirSetup[ABC]\.sh\.txt" > /dev/null 2>&1 && return 0
  return 1
}

if _boa_pass_active || [ -e "/root/.skip_cleanup.cnf" ]; then
  echo "Cleanup skipped due to ongoing operations or configuration settings."
  exit 0
else
  _graceful_action
  exit 0
fi
