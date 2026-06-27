#!/bin/bash

###
### 90-global-post.sh -- global, once-per-run maintenance that must happen after
### the per-account work (in the fan-out model, after all accounts join). Carved
### out of daily.sh (Phase 3 of the owl.sh/night split): shared-codebase + ghost
### cleanup, empty-hostmaster-platform removal, weblog teardown, incident
### detection, the Nginx forward-secrecy / DH-param refresh (+ single reload), and
### the /data tree permission sweep + backup pruning. Sourced by daily.sh today
### and called in place; becomes the post-join step run once by owl.sh later.
###
### Touches shared/global resources (the master /var/aegir tree, /data/all,
### /etc/ssl/private, a single `service nginx reload`), so it must NEVER run inside
### the per-account fan-out. The /run/daily-fix.pid lock stays owned by the
### orchestrator (daily.sh/owl.sh), not released here.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh

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

_fix_nginx_forward_secrecy() {
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
}

_global_cleanup() {
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
}

# Prune the SHARED master /var/aegir backup trees once per run. Hoisted out of the
# per-account _purge_cruft_machine (it touched these shared paths inside per-account
# work) so parallel account workers never race on them; run once by the orchestrator
# after the account loop. Mirrors _purge_cruft_machine's _PURGE_TMP/_PURGE_BACKUPS
# derivation (reads _DEL_OLD_TMP/_DEL_OLD_BACKUPS from .barracuda.cnf + _hostedSys).
_purge_shared_aegir_backups() {
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
  find /var/aegir/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null
}
