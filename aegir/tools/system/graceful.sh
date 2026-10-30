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

# Once a week, remove the copies that BOA leaves on every run and every day
# and nothing else removes: the PHP-FPM logs moved aside on each FPM restart
# and each barracuda or octopus run (php-logs/<stamp>/), kept 30 days so the
# logs of a forced security pass can still be read a month later, when the
# reports saying what to look for usually arrive; the csf.allow copies
# guest-water takes before each provider refresh (csf/water/), kept 7 days;
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
    find /var/backups/php-logs -mindepth 1 -maxdepth 1 -ctime +30 \
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
  _purge_solr_tmp
  _purge_le_accounts
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

# Solr's Jetty leaves a work directory (jetty-*) and a start properties file
# (start_*.properties) in /tmp at every start, and nothing removes the old ones:
# BOA's own cleaner matches only Solr 4's jetty9. Only what the solr7 and solr9
# users own counts, since any account can make such names in /tmp, and of that
# only an entry made over two days ago that is not the newest of its kind for
# its owner and that no process holds open, maps or works in. The maps files
# go through cat: awk given a file that is gone (a process that ended after the
# glob was expanded) stops there and reads none of the rest.
_purge_solr_tmp() {
  local _stU _stK _stC _stE _stHeld
  _stHeld="$( { find /proc/[0-9]*/fd /proc/[0-9]*/cwd -maxdepth 1 -lname '/tmp/*' \
    -printf '%l\n'; cat /proc/[0-9]*/maps | awk '$6 ~ /^\/tmp\// { print $6 }'; } \
    2> /dev/null | sort -u)"
  for _stU in solr7 solr9; do
    id -u "${_stU}" &> /dev/null || continue
    for _stK in 'jetty-*' 'start_*.properties'; do
      find /tmp -mindepth 1 -maxdepth 1 -user "${_stU}" -name "${_stK}" \
        -printf '%C@ %f\n' 2> /dev/null | LC_ALL=C sort -rn | tail -n +2 \
        | while read -r _stC _stE; do
          case "${_stE}" in
            ""|*/*|*[!A-Za-z0-9._-]*) continue ;;
          esac
          if printf '%s\n' "${_stHeld}" | grep -q -e "^/tmp/${_stE}\$" \
            -e "^/tmp/${_stE}/"; then
            continue
          fi
          find /tmp -mindepth 1 -maxdepth 1 -name "${_stE}" -user "${_stU}" \
            -ctime +1 -execdir rm -rf -- {} + 2> /dev/null
        done
    done
  done
}

# The ACME account keys the certificate heal sets aside per account when it
# registers anew (/var/backups/le-accounts/<account>/accounts-<stamp>): the newest
# three per account stay, newest by the date and time in the name, which keeps
# its order whatever later touches the copies. Other names stay.
_purge_le_accounts() {
  local _laD _laE
  [ -d "/var/backups/le-accounts" ] && [ ! -L "/var/backups/le-accounts" ] || return 0
  for _laD in /var/backups/le-accounts/*; do
    [ -d "${_laD}" ] && [ ! -L "${_laD}" ] || continue
    find "${_laD}" -mindepth 1 -maxdepth 1 -name \
      'accounts-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' \
      -printf '%f\n' 2> /dev/null | LC_ALL=C sort -r | tail -n +4 \
      | while read -r _laE; do
        rm -rf -- "${_laD:?}/${_laE}"
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

# Resident size in MB of the shared memory a PHP-FPM master maps (opcache and
# APCu: the master creates both before it forks its workers). A page any worker
# ever filled stays resident until the master restarts, long after that worker
# is gone, so the master's own RSS shows almost none of it: fincore reads the
# segment's own pages instead. Each object counts once.
_fpm_shared_resident_mb() {
  local _rng _perm _off _dev _ino _name _res _seen=" " _tot=0
  while read -r _rng _perm _off _dev _ino _name; do
    [[ "${_perm}" == *s* ]] || continue
    [[ "${_ino}" != "0" ]] || continue
    case "${_name}" in
      /dev/zero*|/memfd:*|/SYSV*) ;;
      *) continue ;;
    esac
    [[ "${_seen}" == *" ${_dev}:${_ino} "* ]] && continue
    _seen="${_seen}${_dev}:${_ino} "
    _res=$(fincore -n -b -o RES "/proc/${1}/map_files/${_rng}" 2> /dev/null)
    _res="${_res//[^0-9]/}"
    [ -n "${_res}" ] && _tot=$(( _tot + _res ))
  done < "/proc/${1}/maps"
  echo "$(( _tot / 1048576 ))"
}

# Every PHP-FPM version keeps its opcache and APCu filled to their high-water
# mark until its master restarts, and BOA sizes each version's segments for the
# whole PHP budget of the box. When sites move to another version, the one they
# left holds its filled segments with nothing using them: a hosted box had its
# database OOM-killed with 5.8 GB held that way beside the 6.2 GB of the version
# in use. Reload a version the FPM sampler saw without a single worker in every
# sample of the last day (at least 12 hours of samples of its current master)
# while it still holds 256 MB or more of them: no request is in flight to lose,
# and the reload hands the memory back.
_reload_idle_fpm_versions() {
  local _now _from _mPid _mVer _mUp _since _verdict _shm _mNew _after
  local _tuneDir="/var/log/boa/fpm-tune"
  local _relLog="/var/log/boa/fpm-idle-reload.log"
  command -v fincore > /dev/null 2>&1 || return 0
  [ -d "${_tuneDir}" ] || return 0
  _now=$(date +%s)
  _from=$(( _now - 86400 ))
  for _mPid in $(pgrep -f '^php-fpm: master process'); do
    _mVer=$(tr '\0' ' ' 2> /dev/null < "/proc/${_mPid}/cmdline" \
      | grep -o '/opt/php[0-9]\+/' | head -n1)
    _mVer="${_mVer//[^0-9]/}"
    [ -n "${_mVer}" ] && [ -e "/etc/init.d/php${_mVer}-fpm" ] || continue
    _mUp=$(ps -o etimes= -p "${_mPid}" 2> /dev/null)
    _mUp="${_mUp//[^0-9]/}"
    [ -n "${_mUp}" ] || continue
    _since=$(( _now - _mUp ))
    [ "${_since}" -lt "${_from}" ] && _since="${_from}"
    _verdict=$(cat "${_tuneDir}/$(date -d "@${_from}" +%Y%m%d).jsonl" \
      "${_tuneDir}/$(date -d "@${_now}" +%Y%m%d).jsonl" 2> /dev/null \
      | awk -v v="${_mVer}" -v p="${_mPid}" -v s="${_since}" '
        function num(k,   r) {
          if (!match($0, "\"" k "\":[0-9]+")) return -1
          r = substr($0, RSTART, RLENGTH); sub(/.*:/, "", r); return r + 0
        }
        /"scope":"version"/ {
          if (num("version") != v || num("master_pid") != p) next
          t = num("ts"); if (t < s) next
          k = num("n_children"); if (k < 0) next
          n++; if (k > 0) busy++
          if (lo == "" || t < lo) lo = t
          if (t > hi) hi = t
        }
        END { if (n >= 100 && hi - lo >= 43200 && busy == 0) print "IDLE" }')
    [ "${_verdict}" = "IDLE" ] || continue
    _shm=$(_fpm_shared_resident_mb "${_mPid}")
    [ "${_shm:-0}" -ge 256 ] || continue
    echo "Reloading PHP ${_mVer} FPM, idle all day with ${_shm} MB of caches..."
    if service "php${_mVer}-fpm" reload > /dev/null 2>&1; then
      # What the version holds after the reload, read from its master then
      # (a fresh master starts at a baseline of some tens of MB).
      sleep 3
      _mNew=$(pgrep -f "^php-fpm: master process \(/opt/php${_mVer}/" | head -n1)
      _after="?"
      [ -n "${_mNew}" ] && _after=$(_fpm_shared_resident_mb "${_mNew}")
      echo "$(date) php${_mVer}-fpm reloaded: no worker for a day, opcache and APCu held ${_shm} MB before, ${_after} MB after" >> "${_relLog}"
    else
      echo "$(date) php${_mVer}-fpm reload FAILED: no worker for a day, ${_shm} MB of opcache and APCu still held" >> "${_relLog}"
    fi
  done
}

# Size in kB and kB in use of one active swap area, "0 0" when it is not on.
_swap_area_kb() {
  awk -v f="$1" '$1 == f { s = $3; u = $4 } END { printf "%d %d\n", s, u }' /proc/swaps
}

# Highest swap use in kB the xdr9000 sampler recorded over the last 14 days,
# and the number of samples read.
_swap_sampled_peak() {
  local _now _d _day _f
  local _arch="/var/log/boa/xdr9000"
  if [ ! -d "${_arch}" ]; then
    echo "0 0"
    return 0
  fi
  _now=$(date +%s)
  for _d in $(seq 0 13); do
    _day=$(date -d "@$(( _now - _d * 86400 ))" +%Y/%m/samples-%Y%m%d)
    for _f in "${_arch}/${_day}.jsonl" "${_arch}/${_day}.jsonl.gz"; do
      [ -e "${_f}" ] && zcat -f "${_f}" 2> /dev/null
    done
  done | awk '
    /"c":"smp"/ && match($0, /"swp":[0-9]+/) {
      v = substr($0, RSTART + 6, RLENGTH - 6) + 0
      n++
      if (v > m) m = v
    }
    END { printf "%d %d\n", m, n }'
}

# Swap cannot be switched on inside a container, and a file built there only
# takes disk space.
_swap_in_container() {
  [ -e "/proc/vz" ] && [ ! -e "/proc/bc" ] && return 0
  [ -e "/proc/bean_counters" ] && return 0
  [ -e "/run/.containerenv" ] && return 0
  [ -e "/.dockerenv" ] && return 0
  { tr '\0' '\n' < /proc/1/environ; } 2> /dev/null | grep -q '^container=' && return 0
  return 1
}

# Build a swap file of $2 MB at $1 and switch it on. fallocate is tried
# first; a filesystem that leaves holes in it makes swapon refuse it, so the
# file is then written out in full. A refusal for lack of permission is not
# retried that way.
_swap_make_file() {
  local _f="$1"
  local _mb="$2"
  local _err
  rm -f "${_f}"
  if ( umask 077; fallocate -l "${_mb}M" "${_f}" ) 2> /dev/null; then
    chmod 600 "${_f}"
    if mkswap "${_f}" > /dev/null 2>&1; then
      _err=$(swapon "${_f}" 2>&1) && return 0
      if [[ "${_err}" =~ "not permitted" ]]; then
        rm -f "${_f}"
        return 1
      fi
    fi
  fi
  rm -f "${_f}"
  if ! ( umask 077; dd if=/dev/zero of="${_f}" bs=1M count="${_mb}" status=none ) 2> /dev/null; then
    rm -f "${_f}"
    return 1
  fi
  chmod 600 "${_f}"
  mkswap "${_f}" > /dev/null 2>&1 && swapon "${_f}" 2> /dev/null && return 0
  rm -f "${_f}"
  return 1
}

# autoupboa's and multiback's purges run swapoff -a; swapon -a, which brings
# back only what fstab lists.
_swap_fstab_line() {
  local _tmp
  grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab && return 0
  [ -d "/var/backups" ] || mkdir -p /var/backups
  cp -a /etc/fstab "/var/backups/fstab.pre-swapfile.$(date +%y%m%d-%H%M%S)"
  _tmp=$(mktemp /etc/.fstab.boa.XXXXXX) || return 1
  if cat /etc/fstab > "${_tmp}" \
    && { [ -z "$(tail -c1 "${_tmp}")" ] || echo >> "${_tmp}"; } \
    && echo "/swapfile none swap sw 0 0" >> "${_tmp}" \
    && chmod 644 "${_tmp}" \
    && mv -f "${_tmp}" /etc/fstab; then
    return 0
  fi
  rm -f "${_tmp}"
  return 1
}

# Can free RAM take back $1 kB of swapped pages and still keep a tenth of
# the RAM (at least 512 MB) free? The OOM guard in system.sh acts at 5%.
_swap_off_fits() {
  local _availKb _ramKb _spare
  _ramKb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  _availKb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  _spare=$(( _ramKb / 10 ))
  [ "${_spare}" -lt 524288 ] && _spare=524288
  [ $(( _availKb - $1 )) -ge "${_spare}" ]
}

# The swap total BOA aims for, the /swapfile size that gives it, and what to
# do: "grow", "shrink" or "keep". Arguments in MB: RAM, other swap areas,
# the current /swapfile, the 14-day peak use, and the size BOA recorded when
# it last built /swapfile (empty when it never did). Half the RAM, at least
# 1 GB and at most 4 GB, raised to twice the peak, so a normal fortnight
# stays near the half-full mark where autoupboa empties swap; a swap that ran
# 90% full is doubled, as its samples cannot show how much more it needed.
# Never above the RAM or 16 GB. The total grows only when it falls a fifth or
# more short, so a peak that crept a little past half full does not resize
# every fortnight. A file BOA built is shrunk when it is twice the size it
# should be; any other /swapfile is only ever grown.
_swap_plan() {
  local _ram="$1" _oth="$2" _file="$3" _peak="$4" _made="$5"
  local _tot _base _want _cap _need _act="keep"
  _tot=$(( _oth + _file ))
  _base=$(( _ram / 2 ))
  [ "${_base}" -lt 1024 ] && _base=1024
  [ "${_base}" -gt 4096 ] && _base=4096
  if [ "${_tot}" -gt 0 ] && [ $(( _peak * 10 )) -ge $(( _tot * 9 )) ]; then
    _want=$(( _tot * 2 ))
  else
    _want=$(( _peak * 2 ))
  fi
  [ "${_want}" -lt "${_base}" ] && _want="${_base}"
  _cap="${_ram}"
  [ "${_cap}" -gt 16384 ] && _cap=16384
  [ "${_cap}" -lt "${_base}" ] && _cap="${_base}"
  if [ "${_want}" -ge "${_cap}" ]; then
    _want=$(( _cap / 256 * 256 ))
  else
    _want=$(( (_want + 255) / 256 * 256 ))
  fi
  _need=$(( _want - _oth ))
  if [ "${_need}" -ge 256 ]; then
    if [ $(( _tot * 5 )) -le $(( _want * 4 )) ] \
      && [ "${_need}" -ge $(( _file + 256 )) ]; then
      _act="grow"
    elif [ "${_made}" = "${_file}" ] \
      && [ "${_file}" -gt $(( _need * 2 )) ] \
      && [ "${_file}" -ge $(( _need + 1024 )) ]; then
      _act="shrink"
    fi
  fi
  echo "${_want} ${_need} ${_act}"
}

# BOA sizes /swapfile to the RAM and to what the box really swaps (see
# _swap_plan). Other swap areas (a provider's partition) count towards the
# total and are never touched. Not in a container, not on a filesystem other
# than ext3, ext4 or xfs, and not past 80% of /. _SWAP_AUTOSIZE=NO in
# /root/.barracuda.cnf leaves swap alone.
_size_swap() {
  local _log="/var/log/boa/swap-size.log"
  local _swn="/swapfile.boa"
  local _mark="/etc/boa/control/swapfile-boa.txt"
  local _off="/var/log/boa/swap-size.backoff"
  local _fsType _curKb _curUsed _newKb _newUsed _ramMb _othMb _fileMb
  local _peakKb _smp _usedKb _peakMb _totMb _want _needMb _act
  local _sum _rootSz _rootUsed _rootAv

  [ "${_SWAP_AUTOSIZE}" = "NO" ] && return 0
  if _swap_in_container; then
    echo "$(date) swap left alone: this system runs in a container" >> "${_log}"
    return 0
  fi
  _fsType=$(awk '$2 == "/" { t = $3 } END { print t }' /proc/mounts)
  case "${_fsType}" in
    ext3|ext4|xfs) ;;
    *)
      echo "$(date) swap left alone: / is ${_fsType:-unknown}, not ext3, ext4 or xfs" >> "${_log}"
      return 0
    ;;
  esac
  if [ -L "/swapfile" ] || { [ -e "/swapfile" ] && [ ! -f "/swapfile" ]; }; then
    echo "$(date) swap left alone: /swapfile is not a plain file" >> "${_log}"
    return 0
  fi
  [ -n "$(find "${_off}" -mmin -10080 2> /dev/null)" ] && return 0
  if pgrep -x swapoff > /dev/null 2>&1; then
    echo "$(date) swap left alone: a swapoff is running" >> "${_log}"
    return 0
  fi

  # A new file an interrupted run left behind.
  read -r _newKb _newUsed < <(_swap_area_kb "${_swn}")
  if [ "${_newKb}" -gt 0 ]; then
    if ! _swap_off_fits "${_newUsed}" || ! swapoff "${_swn}" 2> /dev/null; then
      echo "$(date) swap left alone: ${_swn} from an earlier run is on and cannot be switched off now" >> "${_log}"
      return 0
    fi
  fi
  rm -f "${_swn}"

  read -r _curKb _curUsed < <(_swap_area_kb /swapfile)
  if [ -f "/swapfile" ] && [ "${_curKb}" -eq 0 ]; then
    swapon /swapfile 2> /dev/null
    read -r _curKb _curUsed < <(_swap_area_kb /swapfile)
  fi

  _ramMb=$(( $(awk '/^MemTotal:/ {print $2}' /proc/meminfo) / 1024 ))
  # /proc/swaps leaves out each area's header page: round up to whole MB.
  _othMb=$(( ($(awk 'NR > 1 && $1 != "/swapfile" && $1 != "/swapfile.boa" && $1 !~ /^\/dev\/zram/ { s += $3 } END { printf "%d", s }' /proc/swaps) + 1023) / 1024 ))
  _fileMb=$(( (_curKb + 1023) / 1024 ))
  read -r _peakKb _smp < <(_swap_sampled_peak)
  _usedKb=$(awk '/^SwapTotal:/ {t = $2} /^SwapFree:/ {f = $2} END {print t - f}' /proc/meminfo)
  [ "${_usedKb}" -gt "${_peakKb}" ] && _peakKb="${_usedKb}"
  _peakMb=$(( _peakKb / 1024 ))
  _totMb=$(( _othMb + _fileMb ))

  read -r _want _needMb _act < <(_swap_plan "${_ramMb}" "${_othMb}" \
    "${_fileMb}" "${_peakMb}" "$(cat "${_mark}" 2> /dev/null)")

  _sum="RAM ${_ramMb} MB, swap ${_totMb} MB (/swapfile ${_fileMb} MB), 14-day peak ${_peakMb} MB in ${_smp} samples, target ${_want} MB"
  if [ "${_act}" = "keep" ]; then
    [ "${_curKb}" -gt 0 ] && _swap_fstab_line
    echo "$(date) ${_sum}: kept" >> "${_log}"
    return 0
  fi

  read -r _rootSz _rootUsed _rootAv < <(df -Pk / | awk 'NR == 2 {print $2, $3, $4}')
  if [ $(( (_rootUsed + _needMb * 1024) * 100 )) -gt $(( _rootSz * 80 )) ] \
    || [ $(( _rootAv - _needMb * 1024 )) -lt 2097152 ]; then
    echo "$(date) ${_sum}: no room on / for a ${_needMb} MB file (it would pass 80% or leave under 2 GB free)" >> "${_log}"
    return 0
  fi

  mkdir -p /etc/boa/control
  if [ "${_curKb}" -eq 0 ]; then
    rm -f /swapfile
    if ! _swap_make_file /swapfile "${_needMb}"; then
      touch "${_off}"
      echo "$(date) ${_sum}: building a ${_needMb} MB /swapfile FAILED, next try in 7 days" >> "${_log}"
      return 0
    fi
    _swap_fstab_line
    echo "${_needMb}" > "${_mark}"
    echo "$(date) ${_sum}: /swapfile created, ${_needMb} MB" >> "${_log}"
    return 0
  fi

  # The kernel refuses to rename a swap file that is on, so the new file is
  # built and tried under another name, switched off again while it is still
  # empty, and takes the name once the old one is off: for those seconds only
  # the other swap areas are on, so the old one goes only while free RAM can
  # take its pages back with room to spare.
  if ! _swap_off_fits "${_curUsed}"; then
    echo "$(date) ${_sum}: ${_act} waits, ${_curUsed} kB in /swapfile and not enough free RAM to take it back" >> "${_log}"
    return 0
  fi
  if ! _swap_make_file "${_swn}" "${_needMb}"; then
    touch "${_off}"
    echo "$(date) ${_sum}: building a ${_needMb} MB file to ${_act} /swapfile FAILED, next try in 7 days" >> "${_log}"
    return 0
  fi
  if ! swapoff "${_swn}" 2> /dev/null; then
    echo "$(date) ${_sum}: switching the new ${_swn} off FAILED, left on beside /swapfile" >> "${_log}"
    return 0
  fi
  if ! swapoff /swapfile 2> /dev/null; then
    rm -f "${_swn}"
    echo "$(date) ${_sum}: swapoff /swapfile FAILED, /swapfile kept at ${_fileMb} MB" >> "${_log}"
    return 0
  fi
  if mv -f "${_swn}" /swapfile && swapon /swapfile 2> /dev/null; then
    _swap_fstab_line
    echo "${_needMb}" > "${_mark}"
    echo "$(date) ${_sum}: /swapfile ${_act}: ${_fileMb} MB to ${_needMb} MB" >> "${_log}"
  else
    touch "${_off}"
    echo "$(date) ${_sum}: switching the new /swapfile on FAILED, no /swapfile on, next try in 7 days" >> "${_log}"
  fi
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

  # RAM and disk cache management. No swap reset here any more: autoupboa's
  # _swap_purge_if_bloated empties swap from clear.sh's five-minute tick once
  # it is half full, and only while free RAM can take it back. The nightly
  # swapoff here checked no RAM at all, so with a large swap it could pull
  # back more than the box had free.
  if [ -d "/dev/disk" ]; then
    echo "Optimizing RAM usage..."
    _optimize_ram
  fi

  # The purges in autoupboa and multiback stand aside while this runs.
  echo "Sizing swap..."
  echo "$$" > /run/boa_swap_size.pid
  _size_swap
  rm -f /run/boa_swap_size.pid

  echo "Removing empty login-session cgroups..."
  _trim_session_cgroups

  echo "Checking for PHP-FPM versions idle all day..."
  _reload_idle_fpm_versions

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
