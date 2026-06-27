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

_WEBG=www-data
_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_cGet="config-get user.settings"
_cSet="config-set user.settings"
_vGet="variable-get"
_vSet="variable-set --always-set"

###-------------SYSTEM-----------------###

###
### Load the shared helper library (pure helpers, load + chattr helpers, drush8
### wrappers) split out under /var/xdrago/night/ so the same copy is reused by
### the night worker scripts. The fetcher in BOA.sh.txt installs it alongside
### this script; abort cleanly if it is missing rather than run half-defined.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh
if ! command -v _run_drush8_hmr_cmd > /dev/null 2>&1; then
  echo "FATAL ERROR: /var/xdrago/night/night.inc.sh not loaded; aborting"
  exit 1
fi

###
### Load the per-site maintenance procedures (the _daily_process loop and its
### helper family) carved out under /var/xdrago/night/. Sourced here so the
### per-account loop below can still drive _daily_process inline; it becomes a
### standalone worker in a later phase. Same fail-closed guard as above.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/20-sites.sh" ] && . /var/xdrago/night/20-sites.sh
if ! command -v _daily_process > /dev/null 2>&1; then
  echo "FATAL ERROR: /var/xdrago/night/20-sites.sh not loaded; aborting"
  exit 1
fi

###
### Load the per-account maintenance worker (the _daily_action loop body carved
### into _account_process). Sourced here so the loop below calls it per account.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/10-account.sh" ] && . /var/xdrago/night/10-account.sh
if ! command -v _account_process > /dev/null 2>&1; then
  echo "FATAL ERROR: /var/xdrago/night/10-account.sh not loaded; aborting"
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

_apt_clean_update() {
  ${_APT_UPDATE} -qq 2>/dev/null
  _CALLER_SCRIPT="$(basename "${BASH_SOURCE[-1]}")"
  _CALLER_SCRIPT="${_CALLER_SCRIPT//[^a-zA-Z0-9._-]/_}"
  date +%s > "/run/_latest_apt_clean_update.${_CALLER_SCRIPT}.pid"
}

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

_if_le_hm_ssl_old() {
  # Get the current time in seconds since epoch
  _current_time=$(date +%s)

  # Path to the file you want to check
  _filePath="$1"

  # Define the thresholds
  _recent_threshold_days=60  # 60 days to consider for new updates
  _update_check_days=30      # Don't update NEW if it was already set within the last 30 days

  # Check if the path is a symlink
  if [ -L "${_filePath}" ]; then
    _target_file="$(readlink -f "${_filePath}")"
    # Get the file's modification time in seconds since epoch
    _file_mod_time=$(stat -c %Y "${_target_file}")
  else
    # Get the file's modification time in seconds since epoch
    _file_mod_time=$(stat -c %Y "${_filePath}")
  fi

  # Calculate the time difference in minutes
  _time_diff_minutes=$(( (_current_time - _file_mod_time) / 60 ))

  # Calculate the time difference in days
  _time_diff_days=$(( _time_diff_minutes / 1440 ))

  # Calculate the last update check time (from some state file, if exists)
  if [ -f "${_filePath}.lastupdate" ]; then
    _last_update_time=$(cat "${_filePath}.lastupdate")
  else
    _last_update_time=0
  fi

  _last_update_diff_days=$(( (_current_time - _last_update_time) / 86400 ))  # 86400 seconds in a day

  # Check if the file was modified within the last 30 minutes
  if [ "${_time_diff_minutes}" -lt 30 ]; then
    _crtLastMod=NEW
  # Check if the file was modified within the last 60 days and not marked NEW in the last 30 days
  elif [ "${_time_diff_days}" -le "${_recent_threshold_days}" ] && [ "${_last_update_diff_days}" -ge "${_update_check_days}" ]; then
    _crtLastMod=NEW
    echo ${_current_time} > "${_filePath}.lastupdate"
  else
    _crtLastMod=OLD
  fi
}

_if_le_hm_ssl_crt_key_copy() {
  if [ -e "${_leCrtPath}/fullchain.pem" ]; then
    _crtPath="${_leCrtPath}/fullchain.pem"
  elif [ -e "${_leCrtPath}/cert.pem" ]; then
    _crtPath="${_leCrtPath}/cert.pem"
  fi
  if [ -e "${_crtPath}" ]; then
    if [ -L "${_crtPath}" ]; then
      _crtPathR="$(readlink -n "${_crtPath}")"
      if [ -f "${_leCrtPath}/${_crtPathR}" ]; then
        rm -f /etc/ssl/private/${_hmFront}.crt
        cp -a ${_leCrtPath}/${_crtPathR} /etc/ssl/private/${_hmFront}.crt
      fi
    else
      rm -f /etc/ssl/private/${_hmFront}.crt
      cp -a ${_crtPath} /etc/ssl/private/${_hmFront}.crt
    fi
  fi
  _keyPath="${_leCrtPath}/privkey.pem"
  if [ -e "${_keyPath}" ]; then
    if [ -L "${_keyPath}" ]; then
      _keyPathR="$(readlink -n "${_keyPath}")"
      if [ -f "${_leCrtPath}/${_keyPathR}" ]; then
        rm -f /etc/ssl/private/${_hmFront}.key
        cp -a ${_leCrtPath}/${_keyPathR} /etc/ssl/private/${_hmFront}.key
      fi
    else
      rm -f /etc/ssl/private/${_hmFront}.key
      cp -a ${_keyPath} /etc/ssl/private/${_hmFront}.key
    fi
  fi
}

_le_hm_ssl_check_update() {
  _leCrtPath=
  _exeLe="${_usEr}/tools/le/dehydrated"
  if [ -e "${_usEr}/log/domain.txt" ]; then
    _hmFront=$(cat ${_usEr}/log/domain.txt 2>&1)
    _hmFront=$(echo -n ${_hmFront} | tr -d "\n" 2>&1)
  fi
  if [ -e "${_usEr}/log/extra_domain.txt" ]; then
    _hmFrontExtra=$(cat ${_usEr}/log/extra_domain.txt 2>&1)
    _hmFrontExtra=$(echo -n ${_hmFrontExtra} | tr -d "\n" 2>&1)
  fi
  if [ -z "${_hmFront}" ]; then
    if [ -e "${_usEr}/.drush/hostmaster.alias.drushrc.php" ]; then
      _hmFront=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
        | grep "uri'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    fi
  fi
  if [ ! -z "${_hmFront}" ]; then
    _leCrtPath="${_usEr}/tools/le/certs/${_hmFront}"
  fi
  if [ -x "${_exeLe}" ] \
    && [ ! -z "${_hmFront}" ] \
    && [ -e "${_leCrtPath}/fullchain.pem" ]; then
    _DOM=$(date +%e)
    _DOM=${_DOM//[^0-9]/}
    _RDM=$((RANDOM%25+6))
    if [ "${_DOM}" = "${_RDM}" ] || [ -e "${_usEr}/static/control/force-ssl-certs-rebuild.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/site.${_hmFront}.cert-x1-rebuilt.info" ]; then
        _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
        mkdir -p ${_usEr}/log/ctrl
        touch ${_usEr}/log/ctrl/site.${_hmFront}.cert-x1-rebuilt.info
      else
        _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
      fi
    else
      _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
    fi
    if [ ! -z "${_hmFrontExtra}" ]; then
      echo "Running LE cert check directly for hostmaster ${_HM_U} with ${_hmFrontExtra}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} --domain ${_hmFront} --domain ${_hmFrontExtra}"
      wait
    else
      echo "Running LE cert check directly for hostmaster ${_HM_U}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} --domain ${_hmFront}"
      wait
    fi
  fi
  _crtLastMod=OLD
  _if_le_hm_ssl_old "${_leCrtPath}/fullchain.pem"
  if [ "${_crtLastMod}" = "NEW" ]; then
    echo "Copying NEW LE cert for hostmaster ${_hmFront} to /etc/ssl/private/"
    _if_le_hm_ssl_crt_key_copy
  else
    echo "No new LE cert for hostmaster ${_hmFront} to copy"
  fi
}

_delete_this_empty_hostmaster_platform() {
  _run_drush8_hmr_master_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

_check_old_empty_hostmaster_platforms() {
  if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ] \
	&& [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
	_DO_NOTHING=YES
  else
    if [ "${_hostedSys}" = "YES" ]; then
	  _DEL_OLD_EMPTY_PLATFORMS="3"
	else
	  _DEL_OLD_EMPTY_PLATFORMS="7"
	fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on /var/aegir instance"
      for _Platform in `find /var/aegir/.drush/platform_* -maxdepth 1 -mtime \
        +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`; do
        _T_PFM_NAME=$(echo "${_Platform}" \
          | sed "s/.*platform_//g; s/.alias.drushrc.php//g" \
          | awk '{ print $1}' 2>&1)
        _T_PFM_ROOT=$(cat ${_Platform} \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _T_PFM_SITE=$(grep "${_T_PFM_ROOT}/sites/" \
          /var/aegir/.drush/*.drushrc.php \
          | grep site_path 2>&1)
        if [ ! -e "${_T_PFM_ROOT}/sites/all" ] \
          || [ ! -e "${_T_PFM_ROOT}/index.php" ]; then
          mkdir -p /var/aegir/undo
          ### mv -f /var/aegir/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php /var/aegir/undo/ &> /dev/null
          echo "GHOST platform ${_T_PFM_ROOT} detected and moved to /var/aegir/undo/"
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_ROOT}/sites/all" ]; then
          _delete_this_empty_hostmaster_platform
        fi
      done
    fi
  fi
}

_delete_this_platform() {
  _run_drush8_hmr_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

_check_old_empty_platforms() {
  if [ "${_hostedSys}" = "YES" ]; then
    if [[ "${_hName}" =~ "demo.aegir.cc" ]] \
      || [ -e "${_usEr}/static/control/platforms.info" ]; then
      _DO_NOTHING=YES
    else
      if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ] \
        && [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
        _DO_NOTHING=YES
      else
        _DEL_OLD_EMPTY_PLATFORMS="60"
      fi
    fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on ${_HM_U} instance"
      for _Platform in `find ${_usEr}/.drush/platform_* -maxdepth 1 -mtime \
        +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`; do
        _T_PFM_NAME=$(echo "${_Platform}" \
          | sed "s/.*platform_//g; s/.alias.drushrc.php//g" \
          | awk '{ print $1}' 2>&1)
        _T_PFM_ROOT=$(cat ${_Platform} \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _T_PFM_SITE=$(grep "${_T_PFM_ROOT}/sites/" \
          ${_usEr}/.drush/*.drushrc.php \
          | grep site_path 2>&1)
        if [ ! -e "${_T_PFM_ROOT}/sites/all" ] \
          || [ ! -e "${_T_PFM_ROOT}/index.php" ]; then
          if [ ! -e "${_T_PFM_ROOT}/vendor" ]; then
            mkdir -p ${_usEr}/undo
            ### mv -f ${_usEr}/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
            echo "GHOST platform ${_T_PFM_ROOT} detected and moved to ${_usEr}/undo/"
          fi
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_ROOT}/sites/all" ]; then
          _delete_this_platform
        fi
      done
    fi
  fi
}

_purge_cruft_machine() {

  if [ ! -z "${_DEL_OLD_TMP}" ] && [ "${_DEL_OLD_TMP}" -gt 0 ]; then
    _PURGE_TMP="${_DEL_OLD_TMP}"
  else
    _PURGE_TMP="0"
  fi

  if [ ! -z "${_DEL_OLD_BACKUPS}" ] && [ "${_DEL_OLD_BACKUPS}" -gt 0 ]; then
    _PURGE_BACKUPS="${_DEL_OLD_BACKUPS}"
  else
    _PURGE_BACKUPS="14"
    if [ "${_hostedSys}" = "YES" ]; then
      _PURGE_BACKUPS="7"
    fi
  fi

  _LOW_NR="2"
  _PURGE_CTRL="14"

  find ${_usEr}/log/ctrl/*cert-x1-rebuilt.info \
    -mtime +${_PURGE_CTRL} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/log/ctrl/plr* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/log/ctrl/*rom-fix.info \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${_usEr}/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${_usEr}/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null

  find /var/aegir/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null

  find ${_usEr}/distro/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/distro/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/static/*/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/static/*/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/distro/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/distro/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null

  find /home/${_HM_U}.ftp/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find /home/${_HM_U}.ftp/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  chown -R ${_HM_U}:users ${_usEr}/tools/le
  mkdir -p ${_usEr}/static/trash
  chown ${_HM_U}.ftp:users ${_usEr}/static/trash &> /dev/null
  find ${_usEr}/static/trash/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  for i in $(dir -d /home/${_HM_U}.ftp/platforms/* 2>/dev/null); do
    if [ -e "${i}" ]; then
      _RevisionTest=$(ls ${i} \
        | wc -l \
        | tr -d "\n" 2>&1)
      if [ "${_RevisionTest}" -lt "${_LOW_NR}" ] \
        && [ ! -z "${_RevisionTest}" ]; then
        if [ -d "/home/${_HM_U}.ftp/platforms" ]; then
          chattr -i /home/${_HM_U}.ftp/platforms
          chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
        fi
        _NOW=$(date +%y%m%d-%H%M%S)
        [ -d "/var/backups/ghost/${_HM_U}/${_NOW}" ] || mkdir -p /var/backups/ghost/${_HM_U}/${_NOW}
        echo "Moving ${i} to /var/backups/ghost/${_HM_U}/${_NOW}"
        mv -f ${i} /var/backups/ghost/${_HM_U}/${_NOW}/
      fi
    fi
  done

  for i in $(dir -d ${_usEr}/distro/* 2>/dev/null); do
    if [ -d "${i}" ]; then
      if [ ! -d "${i}/keys" ]; then
        mkdir -p ${i}/keys
      fi
      _RevisionTest=$(ls ${i} | wc -l 2>&1)
      if [ "${_RevisionTest}" -lt 2 ] && [ ! -z "${_RevisionTest}" ]; then
        echo "_RevisionTest is ${_RevisionTest}"
        _NOW=$(date +%y%m%d-%H%M%S)
        mkdir -p ${_usEr}/undo/dist/${_NOW}
        mv -f ${i} ${_usEr}/undo/dist/${_NOW}/ &> /dev/null
        echo "GHOST revision ${i} detected and moved to ${_usEr}/undo/dist/${_NOW}/"
      fi
    fi
  done

  for i in $(dir -d ${_usEr}/distro/* 2>/dev/null); do
    if [ -e "${i}" ]; then
      _distTrNr=$(echo ${i} \
        | cut -d'/' -f6 \
        | awk '{ print $1}' 2> /dev/null)
      if [ -d "/home/${_HM_U}.ftp/platforms" ]; then
        chattr -i /home/${_HM_U}.ftp/platforms
        chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
      fi
      if [ ! -e "${i}/keys" ]; then
        mkdir -p ${i}/keys
        chown ${_HM_U}.ftp:${_WEBG} ${i}/keys &> /dev/null
        chmod 02775 ${i}/keys &> /dev/null
      fi
      if [ ! -e "/home/${_HM_U}.ftp/platforms/${_distTrNr}" ]; then
        mkdir -p /home/${_HM_U}.ftp/platforms/${_distTrNr}
      fi
      if [ -e "${i}/keys" ] && [ ! -e "/home/${_HM_U}.ftp/platforms/${_distTrNr}/keys" ]; then
        ln -sfn ${i}/keys /home/${_HM_U}.ftp/platforms/${_distTrNr}/keys
      fi
      if [ -e "/home/${_HM_U}.ftp/platforms/data" ]; then
        _NOW=$(date +%y%m%d-%H%M%S)
        [ -d "/var/backups/ghost/${_HM_U}/${_NOW}" ] || mkdir -p /var/backups/ghost/${_HM_U}/${_NOW}
        mv -f /home/${_HM_U}.ftp/platforms/data /var/backups/ghost/${_HM_U}/${_NOW}/platforms_data
      fi
      for _Codebase in `find ${i}/* \
        -maxdepth 1 \
        -mindepth 1 \
        -type d \
        | grep "/sites$" 2>&1`; do
        _CodebaseName=$(echo ${_Codebase} \
          | cut -d'/' -f7 \
          | awk '{ print $1}' 2> /dev/null)
        ln -sfn ${_Codebase} /home/${_HM_U}.ftp/platforms/${_distTrNr}/${_CodebaseName}
        echo "Fixed ${_CodebaseName} in ${_distTrNr} symlink to ${_Codebase} for ${_HM_U}.ftp"
      done
    fi
  done
}

_shared_codebases_cleanup() {
  if [ -L "/data/all" ]; then
    _CLD="/data/disk/codebases-cleanup"
  else
    _CLD="/var/backups/codebases-cleanup"
  fi
  for i in `dir -d /data/all/*/`; do
    if [ -d "${i}o_contrib" ]; then
      for _Codebase in `find ${i}* -maxdepth 1 -mindepth 1 -type d \
        | grep "/profiles$" 2>&1`; do
        _CodebaseDir=$(echo ${_Codebase} \
          | sed 's/\/profiles//g' \
          | awk '{print $1}' 2> /dev/null)
        _CodebaseTest=$(find /data/disk/*/distro/*/*/ -maxdepth 1 -mindepth 1 \
          -type l -lname ${_Codebase} | sort 2>&1)
        if [[ "${_CodebaseTest}" =~ "No such file or directory" ]] \
          || [ -z "${_CodebaseTest}" ]; then
          mkdir -p ${_CLD}${i}
          echo "Moving no longer used ${_CodebaseDir} to ${_CLD}${i}"
          ### mv -f ${_CodebaseDir} ${_CLD}${i}
        fi
      done
    fi
  done
}

_ghost_codebases_cleanup() {
  _CLD="/var/backups/ghost-codebases-cleanup"
  for i in `dir -d /data/disk/*/distro/*/*/`; do
    _CodebaseTest=$(find ${i} -maxdepth 1 -mindepth 1 \
      -type d -name vendor | sort 2>&1)
    for _vendor in ${_CodebaseTest}; do
      _ParentDir=`echo ${_vendor} | sed "s/\/vendor//g"`
      if [ -d "${_ParentDir}/docroot/sites/all" ] \
        || [ -d "${_ParentDir}/html/sites/all" ] \
        || [ -d "${_ParentDir}/web/sites/all" ]; then
        _CLEAN_THIS=SKIP
      else
        _CLEAN_THIS="${_ParentDir}"
        _TSTAMP=$(date +%y%m%d-%H%M%S)
        mkdir -p ${_CLD}${i}${_TSTAMP}
        echo "Moving ghost ${_CLEAN_THIS} to ${_CLD}${i}${_TSTAMP}/"
        ### mv -f ${_CLEAN_THIS} ${_CLD}${i}${_TSTAMP}/
      fi
    done
  done
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

_cleanup_weblogx() {
  _ARCHLOGS=/var/www/adminer/access/archive
  if [ -e "${_ARCHLOGS}/unzip" ]; then
    rm -f ${_ARCHLOGS}/unzip/access*
    rm -f ${_ARCHLOGS}/unzip/.global.pid
  fi
}

_incident_email_report() {
  if [ -e "/root/.barracuda.cnf" ]; then
    _MY_EMAIL=
    # shellcheck disable=SC1091
    source /root/.barracuda.cnf
    export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
    : "${_INCIDENT_REPORT:=MINI}"
  fi
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" != "OFF" ]; then
    echo "Sending Incident Report Email on $(date)" >> ${_thisLog}
    s-nail -s "Incident Report during daily.sh: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < <(tail -n 200 "${_thisLog}")
  fi
}

_incident_detection() {
  # Array of errors to search for
  declare -a _errors=(
    "urn:ietf:params:acme:error:unauthorized"
    "urn:ietf:params:acme:error:badNonce"
    "urn:ietf:params:acme:error:rateLimited"
    "urn:ietf:params:acme:error:dns"
    "urn:acme:error:serverInternal"
    "Remote PerformValidation RPC failed"
    "ModuleNotFoundError"
    "Traceback"
    "Drush command terminated abnormally"
    "ArgumentCountError"
  )

  # Loop through errors and check if any exist in the log file
  for _error in "${_errors[@]}"; do
    if grep -q "${_error}" "${_thisLog}"; then
      _incident_email_report "${_error}"
      break  # Exit the loop after the first detected error
    fi
  done
}

_daily_action() {
  if [ -n "${_ENABLE_GOACCESS}" ] && [ "${_ENABLE_GOACCESS}" = "YES" ]; then
    _prepare_weblogx
  fi
  for _usEr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    _count_cpu
    _load_control
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/CANCELLED" ]; then
      if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
        _account_process
      else
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "...we have to wait..."
      fi
      echo
      echo
    fi
  done
  _shared_codebases_cleanup
  _ghost_codebases_cleanup
  _check_old_empty_hostmaster_platforms
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

  _dhpWildPath="/etc/ssl/private/nginx-wild-ssl.dhp"
  if [ -e "/etc/ssl/private/4096.dhp" ]; then
    _dhpPath="/etc/ssl/private/4096.dhp"
    _DIFF_T=$(diff -w -B ${_dhpPath} ${_dhpWildPath} 2>&1)
    if [ ! -z "${_DIFF_T}" ]; then
      cp -af ${_dhpPath} ${_dhpWildPath}
    fi
  fi

  if [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    if [ ! -e "/etc/ssl/private/4096.dhp" ]; then
      echo "Generating 4096.dhp -- it may take a very long time..."
      openssl dhparam -out /etc/ssl/private/4096.dhp 4096 > /dev/null 2>&1 &
    fi
    for f in `find /etc/ssl/private/*.crt -type f`; do
      _sslName=$(echo ${f} | cut -d'/' -f5 | awk '{ print $1}' | sed "s/.crt//g")
      _sslFile="/etc/ssl/private/${_sslName}.dhp"
      _sslFileZ=${_sslFile//\//\\\/}
      if [ -e "${f}" ] && [ ! -z "${_sslName}" ]; then
        if [ ! -e "${_sslFile}" ]; then
          openssl dhparam -out ${_sslFile} 2048 &> /dev/null
        else
          _PFS_TEST=$(grep "DH PARAMETERS" ${_sslFile} 2>&1)
          if [[ ! "${_PFS_TEST}" =~ "DH PARAMETERS" ]]; then
            openssl dhparam -out ${_sslFile} 2048 &> /dev/null
          fi
          _sslRootd="/var/aegir/config/server_master/nginx/pre.d"
          _sslFileX="${_sslRootd}/z_${_sslName}_ssl_proxy.conf"
          _sslFileY="${_sslRootd}/${_sslName}_ssl_proxy.conf"
          if [ -e "${_sslFileX}" ]; then
            _DHP_TEST=$(grep "_sslFile" ${_sslFileX} 2>&1)
            if [[ "${_DHP_TEST}" =~ "_sslFile" ]]; then
              sed -i "s/.*_sslFile.*//g" ${_sslFileX} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileX} &> /dev/null
              wait
            fi
          fi
          if [ -e "${_sslFileY}" ]; then
            _DHP_TEST=$(grep "_sslFile" ${_sslFileY} 2>&1)
            if [[ "${_DHP_TEST}" =~ "_sslFile" ]]; then
              sed -i "s/.*_sslFile.*//g" ${_sslFileY} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileY} &> /dev/null
              wait
            fi
          fi
          if [ -e "${_sslFileX}" ]; then
            _DHP_TEST=$(grep "ssl_dhparam" ${_sslFileX} 2>&1)
            if [[ ! "${_DHP_TEST}" =~ "ssl_dhparam" ]]; then
              sed -i "s/ssl_session_timeout .*/ssl_session_timeout          5m;\n  ssl_dhparam                  ${_sslFileZ};/g" ${_sslFileX} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileX} &> /dev/null
              wait
            fi
          fi
          if [ -e "${_sslFileY}" ]; then
            _DHP_TEST=$(grep "ssl_dhparam" ${_sslFileY} 2>&1)
            if [[ ! "${_DHP_TEST}" =~ "ssl_dhparam" ]]; then
              sed -i "s/ssl_session_timeout .*/ssl_session_timeout          5m;\n  ssl_dhparam                  ${_sslFileZ};/g" ${_sslFileY} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${_sslFileY} &> /dev/null
              wait
            fi
          fi
        fi
      fi
    done
    if [ -e "/var/aegir/config" ]; then
      sed -i "s/.*ssl_stapling .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*ssl_stapling_verify .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*resolver .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*resolver_timeout .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/.*http2.*on;//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/ssl_prefer_server_ciphers .*/ssl_prefer_server_ciphers on;\n  http2 on;/g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
    fi
    if [ -d "/data/u" ]; then
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /data/disk/*/config/server_*/nginx/vhost.d/*
    fi
    if [ -e "/var/aegir/config" ]; then
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/vhost.d/*
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf
    fi
    service nginx reload
  fi
fi

if [ "${_PERMISSIONS_FIX}" = "YES" ] \
  && [ ! -z "${_X_VERSION}" ] \
  && [ -e "/opt/tmp/barracuda-release.txt" ] \
  && [ ! -e "/data/all/permissions-fix-${_xSrl}-${_X_VERSION}-fixed-dz.info" ]; then
  echo "INFO: Fixing permissions in the /data/all tree..."
  find /data/conf -type d -exec chmod 0755 {} \; &> /dev/null
  find /data/conf -type f -exec chmod 0644 {} \; &> /dev/null
  chown -R root:root /data/conf &> /dev/null
  if [ -e "/data/all" ]; then
    find /data/all -type d -exec chmod 0755 {} \; &> /dev/null
    find /data/all -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 02775 /data/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
    chmod 02775 /data/all/000/core/*/sites/all/{modules,libraries,themes} &> /dev/null
    chown -R root:root /data/all &> /dev/null
    chown -R root:users /data/all/*/*/sites &> /dev/null
    chown -R root:users /data/all/000/core/*/sites &> /dev/null
  elif [ -e "/data/disk/all" ]; then
    find /data/disk/all -type d -exec chmod 0755 {} \; &> /dev/null
    find /data/disk/all -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 02775 /data/disk/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
    chmod 02775 /data/disk/all/000/core/*/sites/all/{modules,libraries,themes} &> /dev/null
    chown -R root:root /data/disk/all &> /dev/null
    chown -R root:users /data/disk/all/*/*/sites &> /dev/null
    chown -R root:users /data/disk/all/000/core/*/sites &> /dev/null
  fi
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  echo fixed > /data/all/permissions-fix-${_xSrl}-${_X_VERSION}-fixed-dz.info
fi
if [ ! -e "/var/backups/fix-sites-all-permsissions-${_xSrl}.txt" ]; then
  chmod 0751  /data/disk/*/distro/*/*/sites &> /dev/null
  chmod 0755  /data/disk/*/distro/*/*/sites/all &> /dev/null
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  echo FIXED > /var/backups/fix-sites-all-permsissions-${_xSrl}.txt
  echo "Permissions in sites/all tree just fixed"
fi
find /var/backups/old-sql* -mtime +1 -exec rm -rf {} \; &> /dev/null
find /var/backups/ltd/*/* -mtime +0 -type f -exec rm -f {} \; &> /dev/null
find /var/backups/solr/*/* -mtime +0 -type f -exec rm -f {} \; &> /dev/null
find /var/backups/jetty* -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/backups/dragon/* -maxdepth 0 ! -name config -mtime +7 -exec rm -rf {} \; &> /dev/null
find /var/backups/dragon/config -type f -mtime +90 -exec rm -f {} \; &> /dev/null
if [ "${_hostedSys}" = "YES" ]; then
  if [ -d "/var/backups/codebases-cleanup" ]; then
    find /var/backups/codebases-cleanup/* -mtime +7 -exec rm -rf {} \; &> /dev/null
  elif [ -d "/data/disk/codebases-cleanup" ]; then
    find /data/disk/codebases-cleanup/* -mtime +7 -exec rm -rf {} \; &> /dev/null
  fi
fi
rm -f /tmp/.cron.*.pid
rm -f /tmp/.busy.*.pid
rm -f /data/disk/*/.tmp/.cron.*.pid
rm -f /data/disk/*/.tmp/.busy.*.pid

###
### Delete duplicity ghost pid file if older than 2 days
###
find /run/*_backup.pid -mtime +1 -exec rm -f {} \; &> /dev/null
rm -f /run/daily-fix.pid
echo "INFO: Daily maintenance complete"
exit 0

