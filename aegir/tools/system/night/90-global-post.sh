#!/bin/bash

###
### 90-global-post.sh -- global, once-per-run maintenance that must happen after
### the per-account work (in the fan-out model, after all accounts join). Carved
### out of owl.sh (Phase 3 of the owl.sh/night split): shared-codebase + ghost
### cleanup, empty-hostmaster-platform removal, weblog teardown, incident
### detection, the Nginx forward-secrecy / DH-param refresh (+ single reload), and
### the /data tree permission sweep + backup pruning. Sourced by owl.sh today
### and called in place; becomes the post-join step run once by owl.sh later.
###
### Touches shared/global resources (the master /var/aegir tree, /data/all,
### /etc/ssl/private, a single `service nginx reload`), so it must NEVER run inside
### the per-account fan-out. The /run/daily-fix.pid lock stays owned by the
### orchestrator (owl.sh), not released here.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh

# night.inc.sh is delivered by its own fNN fetch, so this worker can land ahead
# of a library that predates the in-flight gate. Every "_provision_running &&
# return" below is fail-OPEN in that state -- an undefined function returns 127,
# which reads as "no Provision task running" and lets the cleanups below delete
# through a live task. Deliberately the BROAD substring form, not a copy of the
# anchored library body: it runs only while the library is behind, and
# over-matching there merely skips a cleanup (see night.inc.sh).
if ! declare -F _provision_running > /dev/null 2>&1; then
  _provision_running() {
    pgrep -f provision > /dev/null 2>&1
  }
fi

_delete_this_empty_hostmaster_platform() {
  _run_drush8_hmr_master_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

_check_old_empty_hostmaster_platforms() {
  _provision_running && { echo "INFO: provision task active -- skipping empty-platform cleanup"; return; }
  if [ -n "${_DEL_OLD_EMPTY_PLATFORMS}" ] \
	&& [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
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
        if [ -z "$(_detect_real_docroot "${_T_PFM_ROOT}")" ]; then
          # Version-agnostic emptiness: no index.php at the (already docroot-
          # corrected) alias root nor under web/docroot/html. Do NOT key on
          # sites/all, which D8+ dropped.
          if _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; then
            mkdir -p /var/aegir/undo
            mv -f /var/aegir/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php /var/aegir/undo/ &> /dev/null
            echo "GHOST platform ${_T_PFM_ROOT} detected and moved to /var/aegir/undo/"
          else
            echo "GHOST platform ${_T_PFM_ROOT} detected (dry-run; set _GHOST_PLATFORMS_CLEANUP=YES in /root/.barracuda.cnf to move)"
          fi
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
  _provision_running && { echo "INFO: provision task active -- skipping shared-codebases cleanup"; return; }
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
        # Defensive: a tree with a detectable docroot is a real codebase of any
        # version -- never reap it. This loop targets the legacy D6/D7 shared
        # /data/all store (anchored on a root-level profiles/); D8+ codebases are
        # self-contained under distro/ and are not managed here.
        [ -n "$(_detect_real_docroot "${_CodebaseDir}")" ] && continue
        _CodebaseTest=$(find /data/disk/*/distro/*/*/ -maxdepth 1 -mindepth 1 \
          -type l -lname ${_Codebase} | sort 2>&1)
        if [[ "${_CodebaseTest}" =~ "No such file or directory" ]] \
          || [ -z "${_CodebaseTest}" ]; then
          if _cnf_flag_yes /root/.barracuda.cnf _SHARED_CODEBASES_CLEANUP; then
            mkdir -p ${_CLD}${i}
            echo "Moving no longer used ${_CodebaseDir} to ${_CLD}${i}"
            mv -f ${_CodebaseDir} ${_CLD}${i}
          else
            echo "Unused ${_CodebaseDir} detected (dry-run; set _SHARED_CODEBASES_CLEANUP=YES in /root/.barracuda.cnf to move)"
          fi
        fi
      done
    fi
  done
}

_ghost_codebases_cleanup() {
  _provision_running && { echo "INFO: provision task active -- skipping ghost-codebases cleanup"; return; }
  _CLD="/var/backups/ghost-codebases-cleanup"
  for i in `dir -d /data/disk/*/distro/*/*/`; do
    _CodebaseTest=$(find ${i} -maxdepth 1 -mindepth 1 \
      -type d -name vendor | sort 2>&1)
    for _vendor in ${_CodebaseTest}; do
      _ParentDir=`echo ${_vendor} | sed "s/\/vendor//g"`
      if [ -n "$(_detect_real_docroot "${_ParentDir}")" ]; then
        # A detectable docroot (index.php at root or under web/docroot/html)
        # means a real codebase of ANY Drupal version -- never a ghost. Do NOT
        # key on sites/all, which D8+ dropped (web/sites/default, no sites/all).
        _CLEAN_THIS=SKIP
      else
        _CLEAN_THIS="${_ParentDir}"
        _TSTAMP=$(date +%y%m%d-%H%M%S)
        if _cnf_flag_yes /root/.barracuda.cnf _GHOST_CODEBASES_CLEANUP; then
          mkdir -p ${_CLD}${i}${_TSTAMP}
          echo "Moving ghost ${_CLEAN_THIS} to ${_CLD}${i}${_TSTAMP}/"
          mv -f ${_CLEAN_THIS} ${_CLD}${i}${_TSTAMP}/
        else
          echo "Ghost ${_CLEAN_THIS} detected (dry-run; set _GHOST_CODEBASES_CLEANUP=YES in /root/.barracuda.cnf to move)"
        fi
      fi
    done
  done
}

_goaccess_vhosts() {
  ### Standalone vhosts under /etc/nginx/sites-enabled have no Octopus account,
  ### so the per-site arm in 20-sites.sh can never reach them. Enumerate every
  ### literal server_name and build one report per name, plus the box-wide ALL
  ### aggregate. Reports land in the xdr9000 archive tree (already pulled by the
  ### operator's fleet tooling), not the tenant-facing adminer path.
  local _vhDom _vhTgt _isWblgx
  local -a _vhDoms=()
  _isWblgx="$(which weblogx)"
  [ -x "${_isWblgx}" ] || return 0
  [ -d "/etc/nginx/sites-enabled" ] || return 0
  ### Multi-line server_name directives are valid nginx config, so collect
  ### tokens from the directive up to its terminating semicolon, drop what
  ### follows the semicolon, and lowercase (nginx normalizes server names, the
  ### $host log field is lowercase, and lowercasing also keeps any name from
  ### matching weblogx's uppercase ALL trigger). The while-read keeps tokens
  ### away from pathname expansion, unlike a for-in over a substitution.
  while IFS= read -r _vhDom; do
    ### Names become filesystem paths and weblogx arguments; accept only sane
    ### hostnames (alnum edges), which also rejects wildcards, "_" catch-alls,
    ### dot-runs and anything option-shaped.
    if [[ ! "${_vhDom}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] \
      || [[ "${_vhDom}" =~ \.\. ]] \
      || [ "${_vhDom}" = "localhost" ]; then
      continue
    fi
    _vhDoms+=("${_vhDom}")
  done < <(awk '
    /^[[:space:]]*server_name([[:space:]]|$)/ { inns=1; sub(/^[[:space:]]*server_name/, "") }
    inns {
      end = index($0, ";")
      line = (end ? substr($0, 1, end - 1) : $0)
      sub(/#.*/, "", line)
      n = split(line, tok, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (tok[i] != "") print tok[i]
      if (end) inns = 0
    }' /etc/nginx/sites-enabled/* 2>/dev/null | tr 'A-Z' 'a-z' | sort -u)
  ### No standalone vhosts -- nothing to report on, including no ALL run.
  [ "${#_vhDoms[@]}" -eq 0 ] && return 0
  _vhTgt=/var/log/boa/xdr9000/goaccess
  mkdir -p "${_vhTgt}"
  ### The engine keeps the archive root 0700; assert it in case this created it.
  chmod 700 /var/log/boa/xdr9000 "${_vhTgt}" &> /dev/null
  ### Stage the log corpus ONCE for the whole loop. weblogx's internal prepare
  ### never plants the .global.pid sentinel, so without it every call would
  ### re-prepare the corpus; in the nightly, _prepare_weblogx (owl.sh) has
  ### already staged it and planted the sentinel. Standalone, do the same:
  ### first call prepares, then the sentinel makes the rest reuse the corpus.
  if [ ! -e "/var/www/adminer/access/archive/unzip/.global.pid" ]; then
    if command -v _prepare_weblogx > /dev/null 2>&1; then
      _prepare_weblogx
    else
      ${_isWblgx} --site="${_vhDoms[0]}" --env=vhosts
      wait
      touch /var/www/adminer/access/archive/unzip/.global.pid
    fi
  fi
  ### Build in weblogx's standard working area (it stages its merged-log
  ### scratch beside the report), then publish ONLY the finished HTML into the
  ### archive tree, atomically -- the hourly fleet pull must never catch a
  ### multi-MB scratch corpus or a half-written report.
  for _vhDom in "${_vhDoms[@]}" ALL; do
    ${_isWblgx} --site="${_vhDom}" --env=vhosts
    wait
    if [ -e "/var/www/adminer/access/vhosts/${_vhDom}/index.html" ]; then
      mkdir -p "${_vhTgt}/${_vhDom}"
      cp -af "/var/www/adminer/access/vhosts/${_vhDom}/index.html" \
        "${_vhTgt}/${_vhDom}/.index.html.new"
      mv -f "${_vhTgt}/${_vhDom}/.index.html.new" \
        "${_vhTgt}/${_vhDom}/index.html"
    fi
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
    ###
    ### Send the matching error lines WITH context, not a blind tail: this is
    ### the global (orchestrator) log, and per-account work now lives in its own
    ### acct-*.log, so a tail here would only show late global-post output, never
    ### the incident itself. -F treats the token as a fixed string.
    ###
    {
      echo "Incident '${1}' detected during owl.sh on ${_hName} at $(date)"
      echo
      echo "Matching log lines (with context) from ${_thisLog}:"
      echo
      grep -F -n -a -A3 -B3 -- "${1}" "${_thisLog}" 2>/dev/null | head -n 120
      echo
      echo "Full log: ${_thisLog}"
    } | s-nail -s "Incident Report during owl.sh: ${1} on ${_hName} at $(date)" ${_MY_EMAIL}
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
    ### sed -i rewrites every file it is handed, match or no match, so running
    ### it blind over the vhost tree refreshed the mtime of every vhost on the
    ### system every night. That destroyed the only freshness signal the ghost
    ### vhost reaper has (see _cleanup_ghost_vhosts), and long after the last
    ### TLSv1.1 line was gone it still rewrote thousands of files for nothing.
    ### Rewrite only the files that actually still carry the old directive.
    if [ -d "/data/u" ]; then
      grep -Zl "TLSv1.1 TLSv1.2 TLSv1.3;" /data/disk/*/config/server_*/nginx/vhost.d/* 2>/dev/null \
        | xargs -0 -r sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
    fi
    if [ -e "/var/aegir/config" ]; then
      grep -Zl "TLSv1.1 TLSv1.2 TLSv1.3;" /var/aegir/config/server_*/nginx.conf 2>/dev/null \
        | xargs -0 -r sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
      grep -Zl "TLSv1.1 TLSv1.2 TLSv1.3;" /var/aegir/config/server_*/nginx/vhost.d/* 2>/dev/null \
        | xargs -0 -r sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
      grep -Zl "TLSv1.1 TLSv1.2 TLSv1.3;" /var/aegir/config/server_*/nginx/pre.d/*.conf 2>/dev/null \
        | xargs -0 -r sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g"
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
  find /var/backups/solr-archive -mindepth 1 -maxdepth 1 -type f -mtime +30 -exec rm -f {} \; &> /dev/null
  find /var/backups/jetty* -mtime +0 -exec rm -rf {} \; &> /dev/null
  find /var/backups/dragon/* -maxdepth 0 ! -name config -mtime +7 -exec rm -rf {} \; &> /dev/null
  # dragon/config is a low-volume, high-value config archive -- never auto-purged.
  ### Account password backups written by the rotation-on-update path: heal any
  ### copy left world-readable by older code (the account home allows traversal,
  ### so a lax mode is readable by local users by exact path), then keep only
  ### the newest 3 per credential file -- only the newest can hold a
  ### half-failed-rotation recovery value; older ones are dead history that
  ### only assists password guessing.
  chmod 0600 /data/disk/*/.*.pass.txt-pre-* /data/disk/*/.*.pass.php-pre-* &> /dev/null
  chmod 0600 /var/aegir/backups/system/.*.pass.txt-pre-* &> /dev/null
  for _P_LIVE in /data/disk/*/.*.pass.txt /data/disk/*/.*.pass.php \
    /var/aegir/backups/system/.*.pass.txt; do
    [ -e "${_P_LIVE}" ] || continue
    ls -t ${_P_LIVE}-pre-* 2>/dev/null | tail -n +4 | xargs -r rm -f
  done
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
  find /run/*_backup.pid /run/*backboa.pid -mtime +1 -exec rm -f {} \; &> /dev/null
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

# Archive past-month night logs into MM-YYYY subdirectories so /var/log/boa/daily
# does not grow unbounded -- WITHOUT deleting anything, since the logs may be
# needed later for incident analysis. Idempotent: only top-level *.log files
# whose month (by mtime) differs from the current month are moved, so the current
# run's daily-*.log and acct-*.log stay in place and already-archived files inside
# the MM-YYYY subdirs are never re-scanned (-maxdepth 1). Safe to run every night.
_archive_old_daily_logs() {
  _logDir="/var/log/boa/daily"
  [ -d "${_logDir}" ] || return 0
  _curMY=$(date +%m-%Y)
  for _f in `find "${_logDir}" -maxdepth 1 -type f -name '*.log' 2>/dev/null`; do
    _logMY=$(date -r "${_f}" +%m-%Y 2>/dev/null)
    [ -z "${_logMY}" ] && continue
    [ "${_logMY}" = "${_curMY}" ] && continue
    mkdir -p "${_logDir}/${_logMY}"
    mv -f "${_f}" "${_logDir}/${_logMY}/" 2>/dev/null
  done
}

# Hand the migration-source sweep back to the module's own daily hosting queue
# on every hosted instance that carries it. The nightly pass below switches that
# queue off per instance because the paused nightly run is the only executor on
# a BOA box -- so when the nightly executor is itself switched off, the queue has
# to be switched back on, or nothing revokes migration-source grants here again.
# Enabling is all this does: what the queue then runs is the module's own
# documented daily cadence, the one plain Aegir installs use.
_migrate_source_queue_fallback_on() {
  local _armPth _armUsr _armHas
  for _armPth in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    if [ -e "${_armPth}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${_armPth}/log/proxied.pid" ] \
      && [ ! -e "${_armPth}/log/CANCELLED" ]; then
      _armUsr=$(echo "${_armPth}" | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
      _armHas=$(su -s /bin/bash - "${_armUsr}" -c "drush8 @hostmaster php-eval \"echo (int) module_exists('hosting_migrate_source');\"" 2>/dev/null | tr -dc '0-9')
      if [ "${_armHas}" = "1" ]; then
        echo "migrate-sweep: ${_armUsr} daily fallback queue re-armed"
        su -s /bin/bash - "${_armUsr}" -c "drush8 @hostmaster vset hosting_queue_migrate_source_enabled 1" &> /dev/null
      fi
    fi
  done
}

_migrate_source_sweep_all() {
  # Nightly migration-source sweep for every hosted instance, executed inside
  # a box-wide task-queue pause (/run/boa_queue_stop.pid -- the same marker
  # the backups relocation and updatesymlinks hold, honoured by runner.sh
  # before it dispatches any instance queue) so no verify can revoke the same
  # grant concurrently with a sweep pass. The sweep's own frontend hosting
  # queue stays registered as a daily fallback for plain Aegir; on BOA boxes
  # it is switched off per instance every night below, making this paused run
  # the only scheduled executor here -- so switching this run off switches the
  # fallback back on (_migrate_source_queue_fallback_on), never leaving the box
  # with no executor at all. A leaked marker self-heals: clear.sh removes one
  # whose recorded owner PID is gone.
  local _stop="/run/boa_queue_stop.pid" _madeStop=NO _drain=0
  local _swpPth _swpUsr _swpHas _lockfd _armOwned=NO
  local _armed="/var/log/boa/migrate-sweep-fallback-on.info"
  local _armSeed="/var/log/boa/.migrate-sweep-ownership-seeded.info"
  # One-time transition to the ownership stamp above. The previous serial gave
  # the same file the opposite meaning and REMOVED it on every real pass, so a
  # box that was already sweeping nightly carries none -- and the kill-switch
  # branch below would then leave it with the daily queue off and no executor
  # at all, the one state this function must never produce. Seed the stamp
  # once per box, and only where the nightly logs prove a real pass ran here,
  # so an operator's own panel-off on a box that never swept is untouched.
  # This can only ever ADD the stamp; the seed marker makes it once, so a
  # genuine re-arm's consumption of the stamp is never undone.
  if [ ! -e "${_armSeed}" ]; then
    if [ ! -e "${_armed}" ] \
      && grep -qsE 'migrate-sweep: [^ ]+ pass$' /var/log/boa/daily/*.log \
        /var/log/boa/daily/*/*.log; then
      touch "${_armed}" 2>/dev/null
    fi
    touch "${_armSeed}" 2>/dev/null
  fi
  if [ -e "/data/conf/disable_migrate_sweep_night.cnf" ]; then
    # The night run is off. Undo ONLY a queue-off this runner wrote: the stamp
    # is set by a real pass when it switches the daily queue off, so a box
    # whose queue was never disabled by us -- an operator's own panel setting,
    # a box that never swept -- is left exactly as found, and the re-arm fires
    # once, on the genuine transition (nights ran, then the kill-switch
    # appeared). Consuming the stamp is what makes it once.
    if [ -e "${_armed}" ]; then
      echo "migrate-sweep: nightly run disabled; handing the sweep back to the daily queue"
      _migrate_source_queue_fallback_on
      rm -f "${_armed}" 2>/dev/null
    fi
    return 0
  fi
  if ! command -v _provision_running > /dev/null 2>&1; then
    # Delivery-skew stub, deliberately broad -- over-matching only lengthens
    # the wait, never shortens it.
    _provision_running() { pgrep -f provision > /dev/null 2>&1; }
  fi
  exec {_lockfd}>/run/.boa_migrate_sweep.flock 2>/dev/null || return 0
  if ! flock -n "${_lockfd}"; then
    # Another nightly pass is sweeping right now -- say so, so a night with no
    # sweep output is never silent.
    echo "migrate-sweep: another pass holds the sweep lock; skipping this night"
    exec {_lockfd}>&-
    return 0
  fi
  if [ ! -e "${_stop}" ]; then
    echo "$$" > "${_stop}" 2>/dev/null && _madeStop=YES
  fi
  if [ "${_madeStop}" != "YES" ]; then
    # Another operation already holds the pause; its window is not ours to
    # piggyback on or to extend.
    echo "migrate-sweep: queue pause held elsewhere; skipping this night"
    flock -u "${_lockfd}"
    exec {_lockfd}>&-
    return 0
  fi
  # A runner.sh pass that cleared the gate before the marker landed can still
  # fork a task within its minute; the grace outlives that window, then the
  # drain waits out anything already running.
  sleep 90
  while _provision_running && [ "${_drain}" -lt 30 ]; do
    sleep 5
    _drain=$((_drain + 1))
  done
  if _provision_running; then
    echo "migrate-sweep: provision task still active after grace and drain; skipping this night"
  else
    for _swpPth in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
      if [ -e "${_swpPth}/config/server_master/nginx/vhost.d" ] \
        && [ ! -e "${_swpPth}/log/proxied.pid" ] \
        && [ ! -e "${_swpPth}/log/CANCELLED" ]; then
        _swpUsr=$(echo ${_swpPth} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _swpHas=$(su -s /bin/bash - ${_swpUsr} -c "drush8 @hostmaster php-eval \"echo (int) module_exists('hosting_migrate_source');\"" 2>/dev/null | tr -dc '0-9')
        if [ "${_swpHas}" = "1" ]; then
          # This paused nightly run is the executor on BOA boxes; keep the
          # frontend daily queue off so an unpaused pass never runs. The stamp
          # written after this loop records that THIS runner owns the
          # queue-off -- the only state the kill-switch branch above undoes.
          su -s /bin/bash - ${_swpUsr} -c "drush8 @hostmaster vset hosting_queue_migrate_source_enabled 0" &> /dev/null
          _armOwned=YES
          echo "migrate-sweep: ${_swpUsr} pass"
          timeout 300 su -s /bin/bash - ${_swpUsr} -c "drush8 @hostmaster hosting-migrate-source-sweep" 2>&1
        fi
      fi
    done
    [ "${_armOwned}" = "YES" ] && touch "${_armed}" 2>/dev/null
    wait
  fi
  if [ "${_madeStop}" = "YES" ] \
    && [ "$(tr -dc '0-9' < "${_stop}" 2>/dev/null)" = "$$" ]; then
    rm -f "${_stop}"
  fi
  flock -u "${_lockfd}"
  exec {_lockfd}>&-
}
