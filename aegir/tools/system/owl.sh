#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=pro
export _xSrl=588855proT01

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST="$(LC_ALL=C command df -P -l / 2>/dev/null | awk '
    NR==1 { for (i=1; i<=NF; i++) if ($i=="Use%" || $i=="Capacity") u=i }
    NR==2 && u { gsub(/%/,"",$u); print $u }')"
  [[ "${_DF_TEST}" =~ ^[0-9]+$ ]] || _DF_TEST=""
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt 90 ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
}
_check_root

# A finalized proxy keeps this gate: the night worker is per-site and
# per-account work that is meaningless without local sites and DB, and
# proxied-account certificates renew on the target (migration_proxy_certs).
[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

# A replication standby runs no night work: the hostmaster drush calls,
# per-site LE renewals and the ghost cleanups all write into state that
# arrives from the source by replication and rsync.
[ -e "/root/.standby.cnf" ] && exit 0

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
  # Rename ONLY the access logs. The .global.pid sentinel must never enter the
  # rename set: it has no gate here (unlike the weblogx binary, which guards the
  # block with [ ! -e .global.pid ]), so renaming it appended a .txt every run
  # that the sentinel survived, growing .global.pid.txt.txt... until the name
  # exceeded 255 bytes ("File name too long"). Sweep any such accumulated
  # variants too, then re-set the clean sentinel.
  ### Exclude already-renamed .txt files (crash residue from an interrupted
  ### run): renaming them again cascades a fresh access.log.N.txt into
  ### .txt.txt, which the sweep below deletes -- one dirty prepare then feeds
  ### the whole night empty logs. Excluding .txt makes re-preparation
  ### idempotent: fresh renames simply overwrite the previous corpus.
  for _log in `find ${_ARCHLOGS}/unzip \
    -maxdepth 1 -mindepth 1 -type f -name 'access*' ! -name '*.txt' | sort`; do
    mv -f ${_log} ${_log}.txt;
  done
  rm -f ${_ARCHLOGS}/unzip/*.txt.txt*
  rm -f ${_ARCHLOGS}/unzip/.global.pid.txt*
  touch ${_ARCHLOGS}/unzip/.global.pid
}

### A fail-safe that only writes a log line is silence. Say it where the
### operator looks: one dated line in /var/log/boa/nightly.incident.log and,
### unless _INCIDENT_REPORT is OFF, one mail per subject per day to the
### operator address the release notice below uses.
_night_notice() {
  local _key="$1" _subject="$2" _body="$3" _to _stamp
  mkdir -p /var/log/boa
  echo "$(date) NOTE: ${_body}" >> /var/log/boa/nightly.incident.log
  case "${_INCIDENT_REPORT^^}" in
    OFF|NO) return 0 ;;
  esac
  _stamp="/var/log/boa/nightly.notice.${_key}.$(date +%Y%m%d)"
  [ -e "${_stamp}" ] && return 0
  touch "${_stamp}"
  find /var/log/boa -maxdepth 1 -name 'nightly.notice.*' -mtime +7 -delete 2>/dev/null
  _to="${_MY_OCTO_EMAIL:-${_MY_EMAIL:-root}}"
  _to="${_to//\\\@/@}"
  if command -v s-nail > /dev/null 2>&1; then
    printf ' %s\n\n ---\n This email has been sent by your BOA nightly maintenance (owl.sh)\n' "${_body}" \
      | s-nail -s "${_subject}" "${_to}" > /dev/null 2>&1
  fi
}

### An account pass that never ends would hold its fan-out slot (or the
### serial loop) into the next night. Bound it, say so, move on: the whole
### process group gets the signal, the account's night marker is released
### (the ltd worker tests the marker's pid anyway), and the ltd worker
### re-asserts the account's locks on its next tick. _NIGHT_ACCOUNT_MAX is
### seconds in /root/.barracuda.cnf; 0 disables the bound; anything that is
### not a whole number, or a non-zero value under five minutes, is ignored
### for the default with a notice, never turned into a tiny bound. While the
### pass runs, the nightly's own marker is kept fresh so clear.sh's age
### sweep never removes it from under a live nightly.
_night_account_run() {
  local _usr="$1" _rc _max _job
  _max="${_NIGHT_ACCOUNT_MAX:-21600}"
  if [[ ! "${_max}" =~ ^[0-9]+$ ]] || { [ "${_max}" -gt 0 ] && [ "${_max}" -lt 300 ]; }; then
    _night_notice "badknob" "BOA nightly on $(hostname -f): _NIGHT_ACCOUNT_MAX ignored" \
      "_NIGHT_ACCOUNT_MAX='${_NIGHT_ACCOUNT_MAX}' is not a whole number of seconds (0 or at least 300); the default 21600 is used"
    _max=21600
  fi
  timeout -k 120 "${_max}" bash /var/xdrago/night/10-account.sh "${_usr}" &
  _job=$!
  while kill -0 "${_job}" 2>/dev/null; do
    touch /run/daily-fix.pid
    sleep 30
  done
  wait "${_job}"
  _rc=$?
  if [ "${_rc}" = "124" ] || [ "${_rc}" = "137" ]; then
    # timeout is its own process group leader: a helper the pass left hung
    # (the reason it overran) survives the pass's own death, so end the
    # group it started once timeout has returned.
    kill -KILL -- "-${_job}" 2>/dev/null
    _night_notice "bound-$(basename "${_usr}")" "BOA nightly on $(hostname -f): the pass for $(basename "${_usr}") was stopped" \
      "the nightly pass for ${_usr} ran past ${_max} s and was stopped"
    echo "NOTE: the nightly pass for ${_usr} ran past ${_max} s and was stopped"
    rm -f "/run/night-account-$(basename "${_usr}").pid"
  fi
  return "${_rc}"
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
  ### AUTO (or a legacy empty value) means the CPU core count; count first,
  ### or the fallback below would silently resolve to a single slot.
  _count_cpu
  if [ -z "${_NIGHT_MAX_PARALLEL}" ] || [ "${_NIGHT_MAX_PARALLEL}" = "AUTO" ]; then
    _NIGHT_MAX_PARALLEL="${_CPU_NR}"
  fi
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
        echo "Fan-out account ${_usEr} -- log: $(_acct_night_log "${_usEr}")"
        _night_account_run "${_usEr}" \
          >> "$(_acct_night_log "${_usEr}")" 2>&1 &
      else
        if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
          echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
          echo "User ${_usEr} -- log: $(_acct_night_log "${_usEr}")"
          _night_account_run "${_usEr}" \
            >> "$(_acct_night_log "${_usEr}")" 2>&1
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
    # Skew-guarded like the sweep below: the function ships in
    # 90-global-post.sh on its own serial, so a mixed vintage must skip.
    if [ "${_GOACCESS_VHOSTS}" = "YES" ] \
      && command -v _goaccess_vhosts > /dev/null 2>&1; then
      _goaccess_vhosts
    fi
    _cleanup_weblogx
  fi
  # Skew-guarded: the function ships in 90-global-post.sh and the two files
  # deliver on independent serials, so a mixed vintage must skip, not fatal.
  if command -v _migrate_source_sweep_all > /dev/null 2>&1; then
    _migrate_source_sweep_all
  fi
}

###--------------------###
[ ! -d "/data/u" ] && exit 1
echo "INFO: Daily maintenance start"
# Nightly maintenance deletes ghost codebases and purges backups; the old
# boa_run.pid-only wait exited the moment _finale dropped the pid mid-pass,
# while the octopus leg was still building against those trees -- wait on
# the marker and the live process forms too
_boa_pass_active() {
  [ -e "/run/boa_run.pid" ] && return 0
  [ -e "/run/boa_wait.pid" ] && return 0
  [ -e "/run/octopus_install_run.pid" ] && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/(barracuda|octopus)( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-" > /dev/null 2>&1 && return 0
  # The Ægir setup children run as "su - oN -c bash .../AegirSetupC.sh.txt"
  # and match none of the forms above, yet that is exactly the phase that
  # creates a new distro revision the cleanup movers would reap. The [ABC]
  # class also keeps this pattern from matching its own pgrep
  pgrep -f "^(/[^ ]*/)?(bash|sh|su) .*/aegir/scripts/AegirSetup[ABC]\.sh\.txt" > /dev/null 2>&1 && return 0
  return 1
}
# Bounded: a wedged process matching the sweep (or an operator's editor on
# a wrapper file) must not spin this forever with no reaper -- after 2h,
# skip tonight and let tomorrow's cron retry; deleting codebases under a
# possibly-live pass is the one thing this loop must never do
_wCnt=0
while _boa_pass_active; do
  _wCnt=$(( _wCnt + 1 ))
  if (( _wCnt > 1440 )); then
    echo "INFO: BOA pass still in flight after 2h -- nightly maintenance skipped"
    exit 0
  fi
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
_MODULES_FORCE="backup_migrate \
  coder \
  cookie_cache_bypass \
  hacked \
  mydropwizard \
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
  # mydropwizard exists only to pull update-status data from the
  # myDropWizard Drupal 6 LTS service, which closed in February 2022.
  # Its hook_cron() still fires a synchronous request to
  # updates.mydropwizard.com on every availability check, and that host
  # now refuses the TLS handshake, so the call can never succeed. A 6.x
  # and a 7.x branch both shipped, hence both lists below.
  _MODULES_OFF_SEVEN="coder \
    devel \
    filefield_nginx_progress \
    hacked \
    l10n_update \
    linkchecker \
    mydropwizard \
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
    mydropwizard \
    performance \
    poormanscron \
    security_review \
    supercron \
    watchdog_live \
    xhprof"
  # D8+ twin of the lists above -- DETECTION list only: D8+ sites are
  # never touched with Drush8 (a full Drush8 bootstrap can corrupt a
  # D8+ site's internals; only the controlled Aegir backend path may),
  # so the Tuesday pass probes each site's database directly and mails
  # the operator, who removes the module via the site's own admin UI.
  # linkchecker synchronously probes external URLs inside web cron,
  # holding an FPM worker to the FastCGI kill; the killed queue re-runs
  # forever, a permanent self-DoS on shared pools, so it is banned on
  # every core like it always was on D6/D7.
  _MODULES_OFF_EIGHT_PLUS="linkchecker"
else
  _MODULES_ON_SEVEN="robotstxt"
  _MODULES_ON_SIX="path_alias_cache robotstxt"
  _MODULES_OFF_SEVEN="dblog syslog backup_migrate"
  _MODULES_OFF_SIX="dblog syslog backup_migrate"
  _MODULES_OFF_EIGHT_PLUS=
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
  _O_CONTRIB_BACKDROP="/data/all/${_LAST_ALL}/o_contrib_backdrop"
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
  _O_CONTRIB_BACKDROP="/data/disk/all/${_LAST_ALL}/o_contrib_backdrop"
else
  _O_CONTRIB=NO
  _O_CONTRIB_SEVEN=NO
  _O_CONTRIB_EIGHT=NO
  _O_CONTRIB_NINE=NO
  _O_CONTRIB_TEN=NO
  _O_CONTRIB_ELEVEN=NO
  _O_CONTRIB_BACKDROP=NO
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
    ### /root/.barracuda.cnf never defines _MY_OCTO_EMAIL, so this notice
    ### went to an empty recipient and was silently lost on every box; the
    ### operator address is the intended reader, local root the last resort.
    [ -z "${_MY_OCTO_EMAIL}" ] && _MY_OCTO_EMAIL="${_MY_EMAIL:-root}"
    if [[ "${_VERSIONS_TEST}" =~ "${_X_VERSION}" ]]; then
      _VERSIONS_TEST_RESULT=OK
      echo "INFO: Version test result: OK"
    else
      sT="release available, upgrade now!"
      cat <<EOF | s-nail -s "New ${_X_VERSION} ${sT}" ${_MY_OCTO_EMAIL}

 There is new ${_X_VERSION} release available!

 Please review the release notes and upgrade as soon as possible to receive all security updates and new features.

 Release notes: https://docs.boa.io/releases

 Upgrade guide: https://docs.boa.io/self-hosting/keeping-current

 ---
 This email has been sent by your BOA system release monitor

EOF
    echo "INFO: Update notice sent: OK"
    fi
  fi
fi
#
### One nightly at a time. The marker carries this run's pid: a marker whose
### pid is gone, or no longer an owl.sh (pid reuse after a kill -9), is stale
### and never blocks; a live previous nightly makes this start skip and say
### so. clear.sh sweeps the marker by age; the account loop keeps it fresh
### while the nightly is alive.
# The redirection is set up before the 2>/dev/null, so a missing marker made
# bash print its own error to the log; group the command so the silence
# covers the open as well.
_dailyPid=$( { tr -dc '0-9' < /run/daily-fix.pid; } 2>/dev/null )
if [ -n "${_dailyPid}" ] \
  && kill -0 "${_dailyPid}" 2>/dev/null \
  && grep -q "owl.sh" "/proc/${_dailyPid}/cmdline" 2>/dev/null; then
  touch /var/log/boa/wait-for-daily
  _night_notice "overrun" "BOA nightly on $(hostname -f): the previous nightly is still running" \
    "the previous nightly (pid ${_dailyPid}) is still running; this run is skipped"
  exit 1
else
  rm -f /run/daily-fix.pid
  echo $$ > /run/daily-fix.pid
  # An account marker whose pass was killed outright (no bound fired) is dead
  # weight until the next reboot: its readers test the pid it carries, so
  # sweep by that pid, never by age -- an unbounded pass may run for hours.
  for _amk in /run/night-account-*.pid; do
    [ -e "${_amk}" ] || continue
    _amkPid=$(tr -dc '0-9' < "${_amk}" 2>/dev/null)
    if [ -z "${_amkPid}" ] || ! kill -0 "${_amkPid}" 2>/dev/null; then
      rm -f "${_amk}"
    fi
  done
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
_archive_old_daily_logs
rm -f /run/daily-fix.pid
echo "INFO: Daily maintenance complete"
exit 0

