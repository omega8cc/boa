#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=dev
export _xSrl=5103devT01

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST="$(command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 { gsub(/%/,"",$u); print $u }')"
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
}
_check_root

[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

###-------------SYSTEM-----------------###

###
### Load the shared helper library: BOA Tier-0 constants (_vSet etc.), pure
### helpers, load + chattr helpers, drush8 wrappers and the run-freeze, split out
### under /var/xdrago/night/ so the same copy is reused by the night worker
### scripts. The fetcher in BOA.sh.txt installs it alongside this script; abort
### cleanly if it is missing rather than run half-defined.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh
if ! command -v _run_drush8_hmr_cmd > /dev/null 2>&1; then
  echo "FATAL ERROR: /var/xdrago/night/night.inc.sh not loaded; aborting"
  exit 1
fi

###
### Load the global-post procedures (shared cleanup, forward-secrecy + nginx
### reload, perms sweep, pruning) carved into 90-global-post.sh. Sourced here and
### called in place by the main body after _daily_action. The per-site (20-sites.sh)
### and per-account (10-account.sh) workers are NOT sourced here -- the orchestrator
### invokes 10-account.sh as a subprocess per account (it sources its own deps).
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/90-global-post.sh" ] && . /var/xdrago/night/90-global-post.sh
if ! command -v _global_cleanup > /dev/null 2>&1; then
  echo "FATAL ERROR: /var/xdrago/night/90-global-post.sh not loaded; aborting"
  exit 1
fi

###
### Load + normalize _INCIDENT_REPORT
###
### Legacy values:
###   NO  becomes OFF (see below)
###   YES becomes MINI (see below)
###
### Current values:
###   OFF  == Total silence, no email alerts
###   ALL  == Very noisy, good for debugging
###   MINI == Only the most important alerts (default)
###   CRIT == Only critical if _lvl=ALERT
###
_normalize_incident_report() {
  : "${_INCIDENT_REPORT:=MINI}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  ###
  ### Map legacy + validate
  ###
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="MINI" ;;
    OFF|ALL|MINI|CRIT) : ;;
    *)    _INCIDENT_REPORT="MINI" ;;
  esac
}
_normalize_incident_report

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
_os_detection_minimal

_if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_hName}" =~ ".aegir.cc"($) ]]; then
    _hostedSys=YES
  else
    _hostedSys=NO
  fi
}

_find_fast_mirror_early() {
  _isNetc="$(which netcat)"
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    _apt_clean_update
    apt-get install netcat-traditional ${_aptYesUnth} 2> /dev/null
    wait
  fi
  _ffMirr=/opt/local/bin/ffmirror
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2026-05.txt"
    [ -d "/var/backups" ] || mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "files.boa.io"  > ${_ffList}
      echo "files.o8.io" >> ${_ffList}
      echo "files.host8.biz" >> ${_ffList}
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

_prepare_weblogx() {
  _ARCHLOGS=/var/www/adminer/access/archive
  mkdir -p ${_ARCHLOGS}/unzip
  echo "[+] SYNCING LOGS TO: ${_ARCHLOGS}"
  rsync -rlvz --size-only --progress /var/log/nginx/access* ${_ARCHLOGS}/
  echo "[+] COPYING LOGS TO: ${_ARCHLOGS}/unzip/"
  cp -af ${_ARCHLOGS}/access* ${_ARCHLOGS}/unzip/
  echo "[+] DECOMPRESSING GZ FILES"
  find ${_ARCHLOGS}/unzip -name "*.gz" -exec gunzip -f {} \;
  echo "[+] RENAMING RAW FILES"
  for _log in `find ${_ARCHLOGS}/unzip \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    mv -f ${_log} ${_log}.txt;
  done
  rm -f ${_ARCHLOGS}/unzip/*.txt.txt*
  touch ${_ARCHLOGS}/unzip/.global.pid
}

_daily_action() {
  if [ -n "${_ENABLE_GOACCESS}" ] && [ "${_ENABLE_GOACCESS}" = "YES" ]; then
    _prepare_weblogx
  fi
  ###
  ### Freeze the per-run state for the per-account workers, then process each
  ### Octopus account by invoking the 10-account.sh worker as a subprocess. The
  ### load gate + eligibility checks stay here in the orchestrator. _NIGHT_PARALLEL
  ### (default NO) fans accounts out concurrently up to _NIGHT_MAX_PARALLEL slots;
  ### the default serial path is behaviour-equivalent to the former inline call.
  ###
  night_emit_run_env
  : "${_NIGHT_PARALLEL:=NO}"
  : "${_NIGHT_MAX_PARALLEL:=${_CPU_NR}}"
  _NIGHT_MAX_PARALLEL="$(_sanitize_number "${_NIGHT_MAX_PARALLEL}")"
  [ -z "${_NIGHT_MAX_PARALLEL}" ] && _NIGHT_MAX_PARALLEL=1
  for _usEr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    _count_cpu
    _load_control
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/CANCELLED" ]; then
      if [ "${_NIGHT_PARALLEL}" = "YES" ]; then
        ###
        ### Parallel: wait for a free slot AND load headroom, then fan out. This
        ### waits (rather than skips an overloaded account) so parallelism does
        ### not raise the silent-skip rate; each worker logs to its own file.
        ###
        while :; do
          _count_cpu
          _load_control
          if [ "$(jobs -rp | wc -l)" -lt "${_NIGHT_MAX_PARALLEL}" ] \
            && (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
            break
          fi
          sleep 5
        done
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "Fan-out account ${_usEr}"
        bash /var/xdrago/night/10-account.sh "${_usEr}" \
          >> "/var/log/boa/daily/acct-$(basename ${_usEr})-${_NOW}.log" 2>&1 &
      else
        if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
          echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
          echo "User ${_usEr}"
          bash /var/xdrago/night/10-account.sh "${_usEr}"
        else
          echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
          echo "...we have to wait..."
        fi
      fi
      echo
      echo
    fi
  done
  [ "${_NIGHT_PARALLEL}" = "YES" ] && wait
  _shared_codebases_cleanup
  _ghost_codebases_cleanup
  _check_old_empty_hostmaster_platforms
  _purge_shared_aegir_backups
  if [ -n "${_ENABLE_GOACCESS}" ] && [ "${_ENABLE_GOACCESS}" = "YES" ]; then
    _cleanup_weblogx
  fi
}

###--------------------###
[ ! -d "/data/u" ] && exit 1
echo "INFO: Daily maintenance start"
while [ -e "/run/boa_run.pid" ]; do
  echo "Waiting for BOA queue availability..."
  sleep 5
done
#
_NOW=$(date +%y%m%d-%H%M%S)
_NOW=${_NOW//[^0-9-]/}
_DOW=$(date +%u)
_DOW=${_DOW//[^1-7]/}
#
if [ -e "/root/.force.sites.verify.cnf" ]; then
  _FORCE_SITES_VERIFY=YES
else
  _FORCE_SITES_VERIFY=NO
fi
#
_MODULES_FORCE="automated_cron \
  backup_migrate \
  coder \
  cookie_cache_bypass \
  hacked \
  poormanscron \
  security_review \
  site_audit \
  syslog \
  watchdog_live \
  xhprof"
#
if [ "${_DOW}" = "2" ]; then
  _MODULES_ON_SEVEN=
  _MODULES_ON_SIX=
  _MODULES_OFF_SEVEN="coder \
    devel \
    filefield_nginx_progress \
    hacked \
    l10n_update \
    linkchecker \
    performance \
    security_review \
    site_audit \
    watchdog_live \
    xhprof"
  _MODULES_OFF_SIX="coder \
    cookie_cache_bypass \
    devel \
    hacked \
    l10n_update \
    linkchecker \
    performance \
    poormanscron \
    security_review \
    supercron \
    watchdog_live \
    xhprof"
else
  _MODULES_ON_SEVEN="robotstxt"
  _MODULES_ON_SIX="path_alias_cache robotstxt"
  _MODULES_OFF_SEVEN="dblog syslog backup_migrate"
  _MODULES_OFF_SIX="dblog syslog backup_migrate"
fi
#
_CTRL_TPL_FORCE_UPDATE=YES
#
# Check for last all nr
if [ -e "/data/all" ]; then
  cd /data/all
  _listl=([0-9]*)
  _LAST_ALL=${_listl[@]: -1}
  _O_CONTRIB="/data/all/${_LAST_ALL}/o_contrib"
  _O_CONTRIB_SEVEN="/data/all/${_LAST_ALL}/o_contrib_seven"
  _O_CONTRIB_EIGHT="/data/all/${_LAST_ALL}/o_contrib_eight"
  _O_CONTRIB_NINE="/data/all/${_LAST_ALL}/o_contrib_nine"
  _O_CONTRIB_TEN="/data/all/${_LAST_ALL}/o_contrib_ten"
  _O_CONTRIB_ELEVEN="/data/all/${_LAST_ALL}/o_contrib_eleven"
elif [ -e "/data/disk/all" ]; then
  cd /data/disk/all
  _listl=([0-9]*)
  _LAST_ALL=${_listl[@]: -1}
  _O_CONTRIB="/data/disk/all/${_LAST_ALL}/o_contrib"
  _O_CONTRIB_SEVEN="/data/disk/all/${_LAST_ALL}/o_contrib_seven"
  _O_CONTRIB_EIGHT="/data/disk/all/${_LAST_ALL}/o_contrib_eight"
  _O_CONTRIB_NINE="/data/disk/all/${_LAST_ALL}/o_contrib_nine"
  _O_CONTRIB_TEN="/data/disk/all/${_LAST_ALL}/o_contrib_ten"
  _O_CONTRIB_ELEVEN="/data/disk/all/${_LAST_ALL}/o_contrib_eleven"
else
  _O_CONTRIB=NO
  _O_CONTRIB_SEVEN=NO
  _O_CONTRIB_EIGHT=NO
  _O_CONTRIB_NINE=NO
  _O_CONTRIB_TEN=NO
  _O_CONTRIB_ELEVEN=NO
fi
#
mkdir -p /var/log/boa/daily
mkdir -p /var/log/boa/le
#
# shellcheck disable=SC1091
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
#
_find_fast_mirror_early
#
###--------------------###
if [ -z "${_SKYNET_MODE}" ] || [ "${_SKYNET_MODE}" = "ON" ]; then
  echo "INFO: Checking BARRACUDA version"
  rm -f /opt/tmp/barracuda-release.txt*
  curl -L -s \
    --max-redirs 10 \
    --retry 3 \
    --retry-delay 15 -A iCab \
    "${_urlHmr}/conf/version/barracuda-release.txt" \
    -o /opt/tmp/barracuda-release.txt
else
  rm -f /opt/tmp/barracuda-release.txt*
fi
if [ -e "/opt/tmp/barracuda-release.txt" ]; then
  _X_VERSION=$(cat /opt/tmp/barracuda-release.txt 2>&1)
  _VERSIONS_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
  if [ ! -z "${_X_VERSION}" ]; then
    _MY_OCTO_EMAIL=${_MY_OCTO_EMAIL//\\\@/\@}
    if [[ "${_VERSIONS_TEST}" =~ "${_X_VERSION}" ]]; then
      _VERSIONS_TEST_RESULT=OK
      echo "INFO: Version test result: OK"
    else
      sT="release available, upgrade now!"
      cat <<EOF | s-nail -s "New ${_X_VERSION} ${sT}" ${_MY_OCTO_EMAIL}

 There is new ${_X_VERSION} release available!

 Please review the changelog and upgrade as soon as possible to receive all security updates and new features.

 BOA Changelog: https://bit.ly/boa-changelog

 BOA Upgrade: https://bit.ly/boa-upgrade-docs

 ---
 This email has been sent by your BOA system release monitor

EOF
    echo "INFO: Update notice sent: OK"
    fi
  fi
fi
#
if [ -e "/run/daily-fix.pid" ]; then
  touch /var/log/boa/wait-for-daily
  exit 1
else
  touch /run/daily-fix.pid
  _MAILX_TEST=$(s-nail -V 2>&1)
  _if_hosted_sys
  if [ -z "${_PERMISSIONS_FIX}" ]; then
    _PERMISSIONS_FIX=YES
  fi
  if [ -z "${_MODULES_FIX}" ]; then
    _MODULES_FIX=YES
  fi
  if [ -z "${_CLEAR_BOOST}" ]; then
    _CLEAR_BOOST=YES
  fi
  if [ -e "/data/all" ]; then
    if [ ! -e "/data/all/permissions-fix-post-up-${_xSrl}.info" ]; then
      rm -f /data/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/all/permissions-fix-post-up-${_xSrl}.info
    fi
  elif [ -e "/data/disk/all" ]; then
    if [ ! -e "/data/disk/all/permissions-fix-post-up-${_xSrl}.info" ]; then
      rm -f /data/disk/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/disk/all/permissions-fix-post-up-${_xSrl}.info
    fi
  fi

  su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
  wait
  rm -rf /var/aegir/.tmp/cache
  su -s /bin/bash - aegir -c "drush8 @hostmaster dis update syslog dblog -y" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster cron" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster cache-clear all" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster cache-clear all" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster utf8mb4-convert-databases -y" &> /dev/null
  wait

  _thisLog="/var/log/boa/daily/daily-${_NOW}.log"

  _daily_action > ${_thisLog} 2>&1

  _incident_detection

  _fix_nginx_forward_secrecy
fi

_global_cleanup
rm -f /run/daily-fix.pid
echo "INFO: Daily maintenance complete"
exit 0

