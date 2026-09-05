#
# Update Nginx Config.
_nginx_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_conf_update"
  fi
  if [ ! -e "${_pthLog}/nginx-config-params-fixed-${_xSrl}-${_X_VERSION}.log" ] \
    && [ -d "/var/aegir" ]; then
    if [ -e "${_locCnf}/nginx/nginx.conf" ] \
      && [ -e "/etc/nginx/nginx.conf" ]; then
      mv -f /etc/nginx/nginx.conf-* ${_vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/mime.types-pre-* ${_vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/fastcgi_params-pre-* ${_vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/nginx.conf ${_vBs}/dragon/t/nginx.conf-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
      mv -f /etc/nginx/fastcgi_params ${_vBs}/dragon/t/fastcgi_params-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${_locCnf}/nginx/nginx.conf /etc/nginx/nginx.conf
      cp -af ${_locCnf}/nginx/fastcgi_params.txt /etc/nginx/fastcgi_params
      touch ${_pthLog}/nginx-config-params-fixed-${_xSrl}-${_X_VERSION}.log
    fi
  fi
  if [ -e "${_mtrNgx}/pre.d/nginx_speed_purge.conf" ]; then
    rm -f ${_mtrNgx}/pre.d/nginx_speed_purge.conf
  fi
}

#
# Sub Force advanced Nginx configuration.
_sub_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _sub_force_advanced_nginx_config"
  fi
  if [ -e "/opt/php${_PHP_SV}/etc/php${_PHP_SV}-fpm.conf" ]; then
    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrInc}/nginx_compact_include.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${_mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${_mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${_mtrInc}/nginx_vhost_common.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${_mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${_mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${_mtrTpl}/subdir.tpl.php &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${_mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
  fi
}

#
# Force advanced Nginx configuration.
_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _force_advanced_nginx_config"
  fi
  if [ ! -e "/etc/ssl/private/nginx-wild-ssl.dhp" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Generating DH parameters, 2048 bit..."
    fi
    _mrun "openssl dhparam -out /etc/ssl/private/nginx-wild-ssl.dhp 2048"
    wait
  fi
  cp -af ${_locCnf}/nginx/nginx_compact_include.conf ${_mtrInc}/nginx_compact_include.conf
  _validate_local_ip &> /dev/null
  _sub_force_advanced_nginx_config
  sed -i "s/ 90;/ 180;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
  wait
  if [ "${_NGINX_SPDY}" = "YES" ]; then
    sed -i "s/:443;/:443 ssl;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443;/:443 ssl;/g" ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/:443 ssl spdy;/:443 ssl;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443 ssl spdy;/:443 ssl;/g" ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/:443 ssl http2;/:443 ssl;/g" ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443 ssl http2;/:443 ssl;/g" ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
  fi
  if [ -e "/root/.install.modern.openssl.cnf" ] \
    && [ -x "/usr/local/ssl3/bin/openssl" ]; then
    _SSL_BINARY=/usr/local/ssl3/bin/openssl
  else
    _SSL_BINARY=/usr/local/ssl/bin/openssl
  fi
  _SSL_ITD=$(${_SSL_BINARY} version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_SSL_ITD}" = "${_OPENSSL_MODERN_VRN}" ] \
    || [ "${_SSL_ITD}" = "${_OPENSSL_EOL_VRN}" ] \
    || [ "${_SSL_ITD}" = "${_OPENSSL_LEGACY_VRN}" ] \
    || [[ "${_SSL_ITD}" =~ "1.1.0" ]] \
    || [[ "${_SSL_ITD}" =~ "1.0.2" ]] \
    || [[ "${_SSL_ITD}" =~ "1.0.1" ]]; then
    _PFS_READY=YES
  else
    _PFS_READY=NO
  fi
  if [ "${_PFS_READY}" = "YES" ] \
    && [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    _ALLOW_NGINX_FORWARD_SECRECY=YES
    _SSL_PROTOCOLS="TLSv1.2 TLSv1.3;"
    _SSL_CIPHERS="TLS_AES_128_GCM_SHA256:  \
      TLS_AES_256_GCM_SHA384:  \
      TLS_CHACHA20_POLY1305_SHA256:  \
      ECDHE-RSA-AES256-GCM-SHA384:  \
      ECDHE-ECDSA-AES256-GCM-SHA384:  \
      ECDHE-RSA-AES256-SHA384:  \
      ECDHE-ECDSA-AES256-SHA384:  \
      AES256-GCM-SHA384:  \
      ECDHE-ECDSA-CHACHA20-POLY1305:  \
      ECDHE-RSA-CHACHA20-POLY1305:  \
      DHE-RSA-AES256-CCM:  \
      DHE-RSA-AES256-CCM8:  \
      DHE-RSA-AES128-CCM:  \
      DHE-RSA-AES128-CCM8:  \
      ECDHE-RSA-AES128-GCM-SHA256:  \
      ECDHE-ECDSA-AES128-GCM-SHA256:  \
      DHE-RSA-AES128-GCM-SHA256:  \
      DHE-DSS-AES128-GCM-SHA256:  \
      kEDH+AESGCM:  \
      ECDHE-RSA-AES128-SHA256:  \
      ECDHE-ECDSA-AES128-SHA256:  \
      ECDHE-RSA-AES128-SHA:  \
      ECDHE-ECDSA-AES128-SHA:  \
      ECDHE-RSA-AES256-SHA:  \
      ECDHE-ECDSA-AES256-SHA:  \
      DHE-RSA-AES128-SHA256:  \
      DHE-RSA-AES128-SHA:  \
      DHE-DSS-AES128-SHA256:  \
      DHE-RSA-AES256-SHA256:  \
      DHE-DSS-AES256-SHA:  \
      DHE-RSA-AES256-SHA:  \
      AES128-GCM-SHA256:  \
      AES128-SHA256:  \
      AES256-SHA256:  \
      AES128-SHA:  \
      AES256-SHA:  \
      AES:  \
      \!aNULL:  \
      \!eNULL:  \
      \!EXPORT:  \
      \!DES:  \
      \!RC4:  \
      \!MD5:  \
      \!PSK:  \
      \!aECDH:  \
      \!EDH-DSS-DES-CBC3-SHA:  \
      \!EDH-RSA-DES-CBC3-SHA:  \
      \!KRB5-DES-CBC3-SHA:  \
      \!ECDHE-ECDSA-AES128-SHA256:  \
      \!ECDHE-ECDSA-AES256-SHA384;"
    _SSL_CIPHERS=$(echo "${_SSL_CIPHERS}" | sed "s/ //g" 2>&1)
  else
    _ALLOW_NGINX_FORWARD_SECRECY=NO
  fi
  if [ "${_ALLOW_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
      ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
      ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
      ${_mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
      ${_mtrNgx}/vhost.d/* &> /dev/null
    wait
  fi
  if [ -e "${_mtrInc}/nginx_vhost_common.conf" ]; then
    rm -f ${_mtrInc}/nginx_advanced_include.conf
    rm -f ${_mtrInc}/nginx_legacy_include.conf
    rm -f ${_mtrInc}/nginx_modern_include.conf
    rm -f ${_mtrInc}/nginx_octopus_include.conf
    rm -f ${_mtrInc}/nginx_simple_include.conf
  fi
  chown aegir:aegir ${_mtrInc}/*
  chown aegir:aegir /var/aegir/.drush/sys/provision/http/Provision/Config/Nginx/*
  if [ ! -e "/data/conf/nginx_high_load_off.conf" ]; then
    mkdir -p /data/conf
    cp -af ${_locCnf}/nginx/nginx_high_load_off.conf /data/conf/nginx_high_load_off.conf
    chmod 644 /data/conf/nginx_high_load_off.conf &> /dev/null
  fi
}

#
# Check for Linux/Cdorked.A malware and delete if discovered.
_detect_cdorked_malware() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _detect_cdorked_malware"
  fi
  if [ -x "/usr/sbin/nginx" ]; then
    _C_DORKED=NO
    _C_FILE=${_bldPth}/aegir/helpers/dump_cdorked_config.c
    if [ -e "${_C_FILE}" ]; then
      ### _msg "INFO: Checking for Linux/Cdorked.A malware..."
      chattr -ai /usr/sbin/nginx
      cd ${_vBs}
      rm -rf /var/opt/foo_bar*
      gcc -o /var/opt/foo_bar ${_bldPth}/aegir/helpers/dump_cdorked_config.c &> /dev/null
      _C_DORKED_TEST=$(/var/opt/foo_bar 2>&1)
      if [[ "${_C_DORKED_TEST}" =~ "No shared memory matching Cdorked signature" ]]; then
        _DO_NOTHING=YES
        ### _msg "INFO: No Linux/Cdorked.A malware traces found - system clean"
      else
        _msg "ALRT! Your system is probably infected by Linux/Cdorked.A malware!"
        _msg "ALRT! Please send the ${_vBs}/httpd_cdorked_config.bin file"
        _msg "ALRT! to leveille@eset.com for investigation"
        rm -f $(which nginx)
        _NGX_FORCE_REINSTALL=YES
        _C_DORKED=YES
      fi
    fi
  fi
}

#
# Purge legacy Nginx config.
_nginx_clean_legacy_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_clean_legacy_config"
  fi
  if [ -e "/var/aegir/config/server_master/nginx/pre.d/nginx_speed_purge.conf" ]; then
    rm -f /var/aegir/config/server_master/nginx/pre.d/nginx_speed_purge.conf
  fi
  _R_TEST=$(grep "upload_progress" /var/aegir/config/nginx.conf 2>&1)
  if [[ "${_R_TEST}" =~ "upload_progress" ]]; then
    sed -i "s/.*upload_progress.*//g" /var/aegir/config/nginx.conf
  fi
  if [ -d "/data/u" ]; then
    _R_TEST=$(grep "upload_progress_json_output" /data/disk/*/config/includes/nginx_vhost_common.conf 2>&1)
    if [[ "${_R_TEST}" =~ "upload_progress_json_output" ]]; then
      sed -i "s/.*upload_progress_json_output.*//g" /data/disk/*/config/includes/nginx_vhost_common.conf
      sed -i "s/.*upload_progress_json_output.*//g" /data/disk/*/config/server_master/nginx/subdir.d/*/*.conf
      sed -i "s/.*upload_progress_json_output.*//g" /var/aegir/config/includes/nginx_vhost_common.conf
      wait
      sed -i "s/.*report_uploads.*//g" /data/disk/*/config/includes/nginx_vhost_common.conf
      sed -i "s/.*report_uploads.*//g" /data/disk/*/config/server_master/nginx/subdir.d/*/*.conf
      sed -i "s/.*report_uploads.*//g" /var/aegir/config/includes/nginx_vhost_common.conf
      wait
      sed -i "s/.*track_uploads.*//g" /data/disk/*/config/includes/nginx_vhost_common.conf
      sed -i "s/.*track_uploads.*//g" /data/disk/*/config/server_master/nginx/subdir.d/*/*.conf
      sed -i "s/.*track_uploads.*//g" /var/aegir/config/includes/nginx_vhost_common.conf
      wait
    fi
  fi
  _mrun "service nginx reload"
}

#
# Install or upgrade Nginx.
#
# Try the prebuilt boa-nginx .deb for the pinned version; fall back to
# sources on any failure. Published for the default build shape only: any
# box with a non-default module set (extra conf, headers-more, LDAP, NAXSI,
# purge) is refused up front and keeps the source path -- the phase-1
# _PHP_EXTRA_CONF refusal pattern -- because installing a default-shape
# binary over a working custom one and then failing the health check would
# leave a module-less nginx in place mid-run. The deb overlays the binary
# the distro nginx package owns on fresh boxes (Replaces: in the package
# control), while the distro package itself stays installed, pinned and
# held -- it keeps providing the config/init/user structure. nginx links
# its OpenSSL statically, so no loader sync is needed before the probe;
# the expected OpenSSL token is resolved here the same way the source
# build resolves it, so a marker-less box expects the version it would
# have built rather than the one the builder baked.
_install_nginx_deb() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _install_nginx_deb"
  fi
  _NGINX_DEB_INSTALLED=NO
  if [ -z "${_NGINX_VRN}" ]; then
    return 1
  fi
  if [ ! -z "${_NGINX_EXTRA_CONF}" ] \
    || [ "${_NGINX_HEADERS}" = "YES" ] \
    || [ "${_NGINX_LDAP}" = "YES" ] \
    || [ "${_NGINX_NAXSI}" = "YES" ] \
    || [ "${_PURGE_MODE}" = "ON" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Custom Nginx build shape; skipping prebuilt boa-nginx"
    fi
    return 1
  fi
  # Read-only mirror of the source build's OpenSSL selection; the stretch
  # marker cleanup stays in the source path only.
  if [ "${_OS_CODE}" = "excalibur" ] \
    || [ "${_OS_CODE}" = "daedalus" ] \
    || [ "${_OS_CODE}" = "chimaera" ] \
    || [ "${_OS_CODE}" = "beowulf" ] \
    || [ "${_OS_CODE}" = "bookworm" ] \
    || [ "${_OS_CODE}" = "bullseye" ] \
    || [ "${_OS_CODE}" = "buster" ]; then
    _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
    if [ -e "/root/.install.modern.openssl.cnf" ]; then
      _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
    fi
  elif [ "${_OS_CODE}" = "stretch" ]; then
    _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
  else
    _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
  fi
  # Builders are modern-marker boxes by construction, so every published
  # deb bakes the modern OpenSSL statically. A box that expects any other
  # version could only install the deb, fail the token check and purge --
  # leaving no binary until the source rebuild lands. Refuse up front
  # instead; such boxes keep the source path untouched.
  if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_MODERN_VRN}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Non-modern OpenSSL expected; skipping prebuilt boa-nginx"
    fi
    return 1
  fi
  # Snapshot the working binary: with Replaces: in play the deb takes
  # ownership of /usr/sbin/nginx, so a purge on any failure below removes
  # the file itself -- and the source rebuild that follows can fail
  # silently (_mrun). The snapshot keeps the failure envelope identical
  # to the source path's: a failed attempt leaves the previous working
  # binary in place. The source branch's rm -rf nginx* sweeps any stray
  # snapshot on its next run.
  if [ -x "/usr/sbin/nginx" ]; then
    cp -af /usr/sbin/nginx /var/opt/nginx-pre-deb
  fi
  # An attacker-set immutable flag would make dpkg's unpack fail silently.
  chattr -i /usr/sbin/nginx &> /dev/null
  if ! _install_boa_deb "boa-nginx" "${_NGINX_VRN}"; then
    if [ ! -x "/usr/sbin/nginx" ] && [ -x "/var/opt/nginx-pre-deb" ]; then
      cp -af /var/opt/nginx-pre-deb /usr/sbin/nginx
    fi
    rm -f /var/opt/nginx-pre-deb
    return 1
  fi
  # dpkg unpacks the payload with the builder's hardened 0750 mode but
  # archive ownership root:root, and AegirSetupM's provision probes
  # `nginx -V` as the aegir user for feature detection inside the window
  # before _strict_bin_permissions converts group root to users. An
  # unexecutable binary silently degrades the generated server config to
  # the ancient pre-1.1.8 shape (limit_zone), which the modern binary
  # then refuses to load on the next start. Normalize to the canonical
  # root:users shape immediately, matching the boa-php deb precedent.
  chown root:users /usr/sbin/nginx &> /dev/null
  chmod 750 /usr/sbin/nginx &> /dev/null
  _NGINX_DEB_F_ITD=$(/usr/sbin/nginx -v 2>&1 | tr -d "\n" \
    | cut -d"/" -f2 | awk '{ print $1}' 2>&1)
  _NGINX_DEB_V_ITD=$(/usr/sbin/nginx -V 2>&1)
  _NGINX_DEB_V_ITD="$(printf '%s' "${_NGINX_DEB_V_ITD}" | tr '\n\t' '  ')"
  _NGINX_DEB_OK=YES
  if [ ! -x "/usr/sbin/nginx" ] \
    || [ "${_NGINX_DEB_F_ITD}" != "${_NGINX_VRN}" ]; then
    _NGINX_DEB_OK=NO
  fi
  # The same compiled-in tokens the next run's rebuild decision checks; a
  # payload that would immediately re-trigger a rebuild must not pass.
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- 'geoip'; then
    _NGINX_DEB_OK=NO
  fi
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_flv_module'; then
    _NGINX_DEB_OK=NO
  fi
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_mp4_module'; then
    _NGINX_DEB_OK=NO
  fi
  if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- "OpenSSL ${_OPENSSL_NEW_VRN}"; then
    _NGINX_DEB_OK=NO
  fi
  if [ "${_NGINX_SPDY}" = "YES" ]; then
    if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_v2_module'; then
      _NGINX_DEB_OK=NO
    fi
    if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ]; then
      if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- ' --with-http_v3_module'; then
        _NGINX_DEB_OK=NO
      fi
      if ! printf '%s' "${_NGINX_DEB_V_ITD}" | grep -Fq -- 'enable-ktls'; then
        _NGINX_DEB_OK=NO
      fi
    fi
  fi
  if [ "${_NGINX_DEB_OK}" = "YES" ]; then
    rm -f /var/opt/nginx-pre-deb
    _NGINX_DEB_INSTALLED=YES
    _msg "INFO: Nginx ${_NGINX_VRN} installed from prebuilt package"
    return 0
  fi
  # The purge removes the binary boa-nginx now owns; restore the snapshot
  # so the box keeps a working nginx even if the source rebuild that runs
  # next fails silently.
  dpkg --purge "boa-nginx" &> /dev/null
  if [ -x "/var/opt/nginx-pre-deb" ]; then
    cp -af /var/opt/nginx-pre-deb /usr/sbin/nginx
    rm -f /var/opt/nginx-pre-deb
  fi
  _msg "NOTE: Prebuilt boa-nginx failed health check; building from sources"
  return 1
}

_nginx_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_install_upgrade"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "INFO: Testing Nginx version..."
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ -x "/usr/sbin/nginx" ]; then
    _NGINX_F_ITD=$(/usr/sbin/nginx -v 2>&1 | tr -d "\n" \
      | cut -d"/" -f2 | awk '{ print $1}' 2>&1)
    _NGINX_V_ITD=$(/usr/sbin/nginx -V 2>&1)
    _NGINX_V_ITD="$(printf '%s' "${_NGINX_V_ITD}" | tr '\n\t' '  ')"
    if [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ] \
      && [ "${_STATUS}" = "UPGRADE" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Nginx ${_NGINX_F_ITD}, OK"
      fi
    elif [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ] \
      && [ "${_STATUS}" = "INIT" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Nginx ${_NGINX_F_ITD}, OK"
      fi
    elif [ "${_NGINX_F_ITD}" != "${_NGINX_VRN}" ]; then
      _NGINX_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: Installed Nginx ${_NGINX_F_ITD}, upgrade required"
      fi
    fi
    if [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ]; then
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'geoip'; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include geoip module"
        fi
      fi
      if printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'nginx-development-kit'; then
        _NGINX_INSTALL_REQUIRED=YES
        _msg "INFO: Nginx rebuild required to avoid apt-get overwrite"
      fi
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_flv_module'; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include pseudo-streaming support"
        fi
      fi
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_mp4_module'; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include pseudo-streaming support"
        fi
      fi
      if [ "${_OS_CODE}" = "excalibur" ] \
        || [ "${_OS_CODE}" = "daedalus" ] \
        || [ "${_OS_CODE}" = "chimaera" ] \
        || [ "${_OS_CODE}" = "beowulf" ] \
        || [ "${_OS_CODE}" = "bookworm" ] \
        || [ "${_OS_CODE}" = "bullseye" ] \
        || [ "${_OS_CODE}" = "buster" ]; then
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
        fi
      elif [ "${_OS_CODE}" = "stretch" ]; then
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          chattr -i /root/.install.modern.openssl.cnf
          rm -f /root/.install.modern.openssl.cnf
        fi
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
      else
        _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
      fi
      if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- "OpenSSL ${_OPENSSL_NEW_VRN}"; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          _msg "INFO: Nginx forced rebuild to include latest OpenSSL version"
        fi
      fi
      if [ "${_NGINX_HEADERS}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'nginx-headers-more'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include Headers More support"
          fi
        fi
      fi
      if [ "${_NGINX_LDAP}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'nginx-auth-ldap'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include LDAP support"
          fi
        fi
      fi
      if [ "${_PURGE_MODE}" = "ON" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'purge'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include purge module"
          fi
        fi
      fi
      if [ "${_NGINX_NAXSI}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'naxsi'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include NAXSI module"
          fi
        fi
      fi
      if [ "${_NGINX_SPDY}" = "YES" ]; then
        if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_v2_module'; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            _msg "INFO: Nginx forced rebuild to include HTTP/2 support"
          fi
        fi
        if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ]; then
          if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- ' --with-http_v3_module'; then
            _NGINX_INSTALL_REQUIRED=YES
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
              _msg "INFO: Nginx forced rebuild to include HTTP/3 support"
            fi
          fi
          if ! printf '%s' "${_NGINX_V_ITD}" | grep -Fq -- 'enable-ktls'; then
            _NGINX_INSTALL_REQUIRED=YES
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              _msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
              _msg "INFO: Nginx forced rebuild to include kTLS support"
            fi
          fi
        fi
      fi
    fi
  else
    _NGINX_INSTALL_REQUIRED=YES
  fi
  _detect_cdorked_malware
  if [ "${_C_DORKED}" = "YES" ]; then
    _NGINX_INSTALL_REQUIRED=YES
    _msg "INFO: Nginx rebuild required to remove possible Linux/Cdorked.A malware"
  fi
  if [ "${_NGINX_INSTALL_REQUIRED}" = "YES" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_NGX_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_STATUS}" = "UPGRADE" ]; then
      _msg "INFO: Upgrading Nginx to ${_NGINX_VRN}..."
    else
      _msg "INFO: Installing Nginx ${_NGINX_VRN}..."
    fi
    # Prebuilt package path (_USE_PREBUILT_PKGS): replaces only the source
    # fetch + compile below; the shared tail (ldconfig, legacy-config
    # cleanup, service restart) and the follow-up _nginx_initd_check +
    # _nginx_mime_check_fix service wiring run unchanged for both paths.
    _NGINX_DEB_INSTALLED=NO
    if [ "${_USE_PREBUILT_PKGS}" = "YES" ]; then
      _install_nginx_deb
    fi
    if [ "${_NGINX_DEB_INSTALLED}" != "YES" ]; then
      cd /var/opt; rm -rf nginx*
      _get_dev_src "nginx-${_NGINX_VRN}.tar.gz"
      if [ ! -z "${_NGINX_EXTRA_CONF}" ]; then
        _NGINX_EXTRA="${_NGINX_EXTRA_CONF}"
      else
        _NGINX_EXTRA=""
      fi
      if [ "${_NGINX_HEADERS}" = "YES" ]; then
        cd /var/opt
        rm -rf /var/opt/nginx-headers-more*
        _get_dev_src "nginx-headers-more.tar.gz"
        if [ -e "/var/opt/nginx-headers-more" ]; then
          _NGINX_EXTRA="--add-module=/var/opt/nginx-headers-more/ ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_NGINX_LDAP}" = "YES" ]; then
        cd /var/opt
        rm -rf /var/opt/nginx-auth-ldap*
        _get_dev_src "nginx-auth-ldap.tar.gz"
        if [ -e "/var/opt/nginx-auth-ldap" ]; then
          _NGINX_EXTRA="--add-module=/var/opt/nginx-auth-ldap/ ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_NGINX_NAXSI}" = "YES" ]; then
        cd /var/opt
        rm -rf /var/opt/nginx-naxsi*
        _get_dev_src "nginx-naxsi.tar.gz"
        if [ -e "/var/opt/nginx-naxsi" ]; then
          _NGINX_EXTRA="--add-module=/var/opt/nginx-naxsi/naxsi_src/ ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_NGINX_SPDY}" = "YES" ]; then
        if [ "${_OS_CODE}" = "none" ]; then
          _NGINX_EXTRA="--with-http_spdy_module ${_NGINX_EXTRA}"
        else
          _NGINX_EXTRA="--with-http_v2_module ${_NGINX_EXTRA}"
        fi
      fi
      if [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ]; then
        _NGINX_EXTRA="--with-http_v3_module ${_NGINX_EXTRA}"
      fi
      if [ "${_OS_CODE}" = "excalibur" ] \
        || [ "${_OS_CODE}" = "daedalus" ] \
        || [ "${_OS_CODE}" = "chimaera" ] \
        || [ "${_OS_CODE}" = "beowulf" ] \
        || [ "${_OS_CODE}" = "bookworm" ] \
        || [ "${_OS_CODE}" = "bullseye" ] \
        || [ "${_OS_CODE}" = "buster" ]; then
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
        fi
      elif [ "${_OS_CODE}" = "stretch" ]; then
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          chattr -i /root/.install.modern.openssl.cnf
          rm -f /root/.install.modern.openssl.cnf
        fi
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
      else
        _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
      fi
      if [ ! -e "/var/opt/openssl-${_OPENSSL_NEW_VRN}" ]; then
        cd /var/opt
        rm -rf "/var/opt/openssl-${_OPENSSL_NEW_VRN}" "/var/opt/openssl-${_OPENSSL_NEW_VRN}.tar.gz"
        _get_dev_src "openssl-${_OPENSSL_NEW_VRN}.tar.gz"
      fi
      cd /var/opt/nginx-${_NGINX_VRN}
      _mrun "bash ./configure \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --group=www-data \
        --http-client-body-temp-path=/var/lib/nginx/body \
        --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
        --http-log-path=/var/log/nginx/access.log \
        --http-proxy-temp-path=/var/lib/nginx/proxy \
        --http-scgi-temp-path=/var/lib/nginx/scgi \
        --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
        --lock-path=/var/lock/nginx.lock \
        --pid-path=/run/nginx.pid \
        --prefix=/usr \
        --sbin-path=/usr/sbin/nginx \
        --user=www-data \
        --with-compat \
        --with-file-aio \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_geoip_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-threads \
        --without-http_scgi_module \
        --without-http_uwsgi_module \
        --without-mail_imap_module \
        --without-mail_pop3_module \
        --without-mail_smtp_module \
        --with-openssl=/var/opt/openssl-${_OPENSSL_NEW_VRN} \
        --with-openssl-opt='no-tests no-ssl3 enable-ktls zlib-dynamic enable-ec_nistp_64_gcc_128' \
        --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
        --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
        --with-debug ${_NGINX_EXTRA}"
      _mrun "make -j $(nproc)"
      _mrun "make install"
    fi
    ldconfig 2> /dev/null
    _nginx_clean_legacy_config
    _mrun "service nginx restart"
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ ! -L "/usr/bin/nginx" ]; then
    ln -sfn /usr/sbin/nginx /usr/bin/nginx
  fi
}

#
# Fix multi-IP cron access.
_master_fix_multi_ip_cron_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _master_fix_multi_ip_cron_access"
  fi
  [ -e "/root/.local.IP.list.allow" ] && rm -f /root/.local.IP.list.allow
  for _IP in `cat /root/.local.IP.list \
    | cut -d '#' -f1 \
    | sort \
    | uniq \
    | tr -d "\s"`;do echo "  allow        ${_IP};" >> \
      /root/.local.IP.list.allow;done
  echo "  allow 127.0.0.1;" >> /root/.local.IP.list.allow
  echo "  deny all;" >> /root/.local.IP.list.allow

  sed -i "s/allow 127.0.0.1;//g; s/ *$//g; /^$/d" \
    ${_mtrTpl}/Inc/vhost_include.tpl.php
  wait
  sed -i '/deny all;/ {r /root/.local.IP.list.allow
d;};' ${_mtrTpl}/Inc/vhost_include.tpl.php
  wait

  sed -i "s/allow 127.0.0.1;//g; s/ *$//g; /^$/d" \
    ${_mtrTpl}/subdir.tpl.php
  wait
  sed -i '/deny all;/ {r /root/.local.IP.list.allow
d;};' ${_mtrTpl}/subdir.tpl.php
  wait

  sed -i "s/allow 127.0.0.1;//g; s/ *$//g; /^$/d" \
    ${_mtrInc}/nginx_vhost_common.conf
  wait
  sed -i '/deny all;/ {r /root/.local.IP.list.allow
d;};' ${_mtrInc}/nginx_vhost_common.conf
  wait
}

_nginx_initd_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_initd_check"
  fi
  _X_INIT_TEST=
  if [ -e "/etc/init.d/nginx" ]; then
    _X_INIT_TEST_A=$(cat /etc/init.d/nginx | grep ULIMIT 2>&1)
    _X_INIT_TEST_B=$(cat /etc/init.d/nginx | grep Giedymin 2>&1)
    ### The rotate action is required by the stock logrotate.d/nginx
    ### postrotate (invoke-rc.d nginx rotate); scripts without it made
    ### the daily logrotate cron fail and left nginx writing to the
    ### renamed log files until the next reload.
    _X_INIT_TEST_C=$(cat /etc/init.d/nginx | grep rotate 2>&1)
    ### The passive-standby hold gates start() in this script (the escape
    ### hatch /root/.standby.serve.cnf names it). A deployed copy that
    ### predates the hold passes the three tests above and was never
    ### refreshed, so an upgraded mirror still booted its web tier and
    ### served its own panel until the watchdog caught up. Refresh on the
    ### gate's absence too.
    _X_INIT_TEST_D=$(cat /etc/init.d/nginx | grep standby.serve.cnf 2>&1)
  fi
  if [[ "${_X_INIT_TEST_A}" =~ ULIMIT ]] \
    && [[ "${_X_INIT_TEST_B}" =~ Giedymin ]] \
    && [[ "${_X_INIT_TEST_C}" =~ rotate ]] \
    && [[ "${_X_INIT_TEST_D}" =~ standby.serve.cnf ]]; then
    chmod 755 /etc/init.d/nginx &> /dev/null
    _mrun "update-rc.d nginx defaults"
  else
    mv -f /etc/init.d/nginx \
      ${_vBs}/nginx-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${_locCnf}/nginx/nginx /etc/init.d/nginx
    chmod 755 /etc/init.d/nginx &> /dev/null
    _mrun "update-rc.d nginx defaults"
    _mrun "service nginx start"
  fi
}

_nginx_mime_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_mime_check_fix"
  fi
  if [ -e "${_locCnf}/nginx/mime.types" ]; then
    mv -f /etc/nginx/mime.types \
      /etc/nginx/mime.types-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${_locCnf}/nginx/mime.types /etc/nginx/mime.types
    if [ ! -L "/var/www/nginx-default/index.html" ] \
      && [ ! -L "/var/www/nginx-default/under_construction.jpg" ]; then
      mkdir -p /var/www/nginx-default
      mv -f /var/www/nginx-default/index.html \
        /var/www/nginx-default/index.html-pre-${_xSrl}-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${_locCnf}/tpl/uc.html /var/www/nginx-default/index.html
      cp -af ${_locCnf}/tpl/under_construction.jpg \
        /var/www/nginx-default/under_construction.jpg
    fi
    if [ -e "${_locCnf}/tpl/maintenance.html" ]; then
      cp -af ${_locCnf}/tpl/maintenance.html \
        /var/www/nginx-default/maintenance.html
    fi
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/modules-enabled/*
    # Reload on proxies too: the mutations above have already landed on
    # disk, and skipping the reload only leaves the running nginx
    # diverged from its own config until something else reloads it.
    _mrun "service nginx reload"
  fi
}

_nginx_limit_req_zones_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_limit_req_zones_update"
  fi
  local _zones_src="${_locCnf}/nginx/nginx_limit_req_zones.conf"
  local _zones_dst="/etc/nginx/conf.d/limit-req-zones-boa.conf"
  [ -e "${_zones_src}" ] || return 0
  [ -d "/etc/nginx/conf.d" ] || return 0
  if [ -e "${_zones_dst}" ] && cmp -s "${_zones_src}" "${_zones_dst}"; then
    return 0
  fi
  ### Provision vhost includes render their limit_req consumers only when
  ### this file is present with the expected zone, so on-disk presence is
  ### the contract; no reload is needed here — the next configtest-gated
  ### reload activates the zones together with any consumer that needs them.
  local _zones_bak=""
  if [ -e "${_zones_dst}" ]; then
    _zones_bak="${_zones_dst}.pre-${_NOW}"
    cp -af "${_zones_dst}" "${_zones_bak}"
  fi
  cp -af "${_zones_src}" "${_zones_dst}.tmp"
  chmod 644 "${_zones_dst}.tmp"
  chown root:root "${_zones_dst}.tmp"
  mv -f "${_zones_dst}.tmp" "${_zones_dst}"
  ### Fail closed on a box whose nginx rejects the zones: rendered includes
  ### must never be able to trust a file the running nginx cannot load.
  ### Skip the test where nginx is not installed yet (fresh INIT ordering);
  ### the shipped content is static and known-good on every nginx BOA builds.
  if command -v nginx > /dev/null 2>&1; then
    if ! nginx -t > /dev/null 2>&1; then
      if [ -n "${_zones_bak}" ] && [ -e "${_zones_bak}" ]; then
        mv -f "${_zones_bak}" "${_zones_dst}"
      else
        rm -f "${_zones_dst}"
      fi
      _msg "ALERT: nginx -t rejected ${_zones_dst}; previous state restored"
      return 0
    fi
  fi
  if [ -n "${_zones_bak}" ]; then
    rm -f "${_zones_bak}"
  fi
  return 0
}

_nginx_wildcard_ssl_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_wildcard_ssl_install"
  fi
  _WILD_SSL_VHOST="${_mtrNgx}/pre.d/nginx_wild_ssl.conf"
  if [ ! -e "${_WILD_SSL_VHOST}" ]; then
    _msg "INFO: Installing default SSL Wildcard Nginx Proxy..."
    _validate_public_ip &> /dev/null
    _validate_xtras_ip &> /dev/null
    openssl req -x509 -nodes -sha256 -days 7300 \
      -subj "/C=US/ST=New York/O=Aegir/OU=Cloud/L=New York/CN=*.${_THISHOST}" \
      -newkey rsa:2048 \
      -keyout /etc/ssl/private/nginx-wild-ssl.key \
      -out /etc/ssl/private/nginx-wild-ssl.crt -batch 2> /dev/null
    ### The upstream must stay pinned to 127.0.0.1 — `localhost` resolves to
    ### [::1] too on dual-stack /etc/hosts while nginx listens v4-only, adding
    ### a permanently-refusing peer; one backend hiccup then marks 127.0.0.1
    ### down as well and every proxied vhost 502s ("no live upstreams").
    cp -af ${_locCnf}/nginx/nginx_wild_ssl.conf ${_WILD_SSL_VHOST}
    sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g" ${_WILD_SSL_VHOST} &> /dev/null
    [ -e "/etc/nginx/no_ktls.conf" ] \
      && sed -i "/ssl_conf_command Options.*KTLS/d" ${_WILD_SSL_VHOST} &> /dev/null
    if [ -e "${_locCnf}/global/global.inc" ]; then
      ### Deploy the full global include set (per-core chain + dispatcher);
      ### the dispatcher alone would be inert without the chain.
      _global_inc_conf_update
    fi
    if [ -e "${_mtrInc}" ] \
      && [ ! -L "${_mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${_mtrInc}/global.inc
    fi
    if [ -e "/etc/init.d/valkey-server" ]; then
      _valkey_password_update
    elif [ -e "/etc/init.d/redis-server" ]; then
      _redis_password_update
    fi
    _mrun "service nginx restart"
  else
    _WILD_SSL_PROXY_UP=NO
    _RSPRT_TEST=$(grep "quic reuseport" ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_RSPRT_TEST}" =~ "quic reuseport" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs quic reuseport update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _HTTP3_TEST=$(grep http3 ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_HTTP3_TEST}" =~ "http3" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs http3 update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _WILDCARD_SSL_TEST=$(grep "127.0.0.1:80" ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_WILDCARD_SSL_TEST}" =~ "127.0.0.1:80" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs port update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _HTTPVER_TEST=$(grep proxy_http_version ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_HTTPVER_TEST}" =~ "proxy_http_version" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs http/1.1 upstream update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _BANGUARD_TEST=$(grep is_banned ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_BANGUARD_TEST}" =~ "is_banned" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "INFO: nginx_wild_ssl.conf proxy needs IDS enforcement update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    ### Re-deploy when the deployed KTLS state disagrees with the opt-out
    ### control file, so toggling _NGINX_KTLS self-heals the front either way.
    _KTLS_STATE_TEST=$(grep "Options.*KTLS" ${_WILD_SSL_VHOST} 2>&1)
    if [ -e "/etc/nginx/no_ktls.conf" ]; then
      [[ "${_KTLS_STATE_TEST}" =~ "KTLS" ]] && _WILD_SSL_PROXY_UP=YES
    else
      [[ ! "${_KTLS_STATE_TEST}" =~ "KTLS" ]] && _WILD_SSL_PROXY_UP=YES
    fi
    if [ "${_WILD_SSL_PROXY_UP}" = "YES" ]; then
      _validate_public_ip &> /dev/null
      _validate_xtras_ip &> /dev/null
      cp -af ${_locCnf}/nginx/nginx_wild_ssl.conf ${_WILD_SSL_VHOST}
      sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g" ${_WILD_SSL_VHOST}
      [ -e "/etc/nginx/no_ktls.conf" ] \
        && sed -i "/ssl_conf_command Options.*KTLS/d" ${_WILD_SSL_VHOST}
    fi
  fi
}

_nginx_ktls_control_update() {
  ### KTLS opt-out signal. `ssl_conf_command Options KTLS` on OpenSSL 3.2+ can
  ### throw recv() (5: Input/output error) alerts that abort TLS connections
  ### mid-request (kernel kTLS RX returns EIO on a control record - alert,
  ### handshake or TLS 1.3 KeyUpdate - see nginx issue 651). This control file
  ### lets an operator shed KTLS server-wide via _NGINX_KTLS=NO: the provision
  ### render reads it (like basic_nginx.conf) to leave nginx_has_ktls FALSE, and
  ### the static wild-ssl / ssl_proxy fronts strip their KTLS line on deploy.
  ### Default _NGINX_KTLS=YES removes the file, so KTLS stays on unchanged.
  if [ "${_NGINX_KTLS}" = "NO" ]; then
    mkdir -p /etc/nginx
    if [ ! -e "/etc/nginx/no_ktls.conf" ]; then
      echo "# KTLS disabled server-wide via _NGINX_KTLS=NO in barracuda.cnf" \
        > /etc/nginx/no_ktls.conf
    fi
  else
    rm -f /etc/nginx/no_ktls.conf
  fi
}

_nginx_config_update_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _nginx_config_update_fix"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _mrun "service cron start"
    _force_advanced_nginx_config
    sleep 8
    _mrun "service nginx restart"
  else
    if [ -e "/var/aegir/config" ]; then
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/adminer.* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/cgp.* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/chive.* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/vhost.d/sqlbuddy.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:80;/  listen  \*:80;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/adminer.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/cgp.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/chive.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/sqlbuddy.* &> /dev/null
      wait
      sed -i "s/SSLv3 TLSv1;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/SSLv3 TLSv1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/TLSv1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      if [ -d "/data/u" ]; then
        sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /data/disk/*/config/server_*/nginx/vhost.d/*
      fi
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/vhost.d/*
      wait
      sed -i "s/.*ssl .*on;//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*gzip_vary .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*gzip_vary .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_buffer_size .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_buffer_size .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_buffers .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_buffers .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_busy_buffers_size .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_busy_buffers_size .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_temp_file_write_size .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_temp_file_write_size .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*proxy_buffering .*//g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/.*proxy_buffering .*//g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/proxy_redirect .*/proxy_redirect             off;\n    gzip_vary                  off;\n    proxy_buffering            off;/g" \
        /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/proxy_redirect .*/proxy_redirect             off;\n    gzip_vary                  off;\n    proxy_buffering            off;/g" \
        /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
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
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/add_header Vary .*//g" /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    if [ "${_NGINX_SPDY}" = "YES" ]; then
      sed -i "s/:443;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/:443 ssl http2;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl http2;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
    fi
    if [ -e "/root/.install.modern.openssl.cnf" ] \
      && [ -x "/usr/local/ssl3/bin/openssl" ]; then
      _SSL_BINARY=/usr/local/ssl3/bin/openssl
    else
      _SSL_BINARY=/usr/local/ssl/bin/openssl
    fi
    _SSL_ITD=$(${_SSL_BINARY} version 2>&1 | tr -d "\n" | cut -d" " -f2 | awk '{ print $1}' 2>&1)
    if [ "${_SSL_ITD}" = "${_OPENSSL_MODERN_VRN}" ] \
      || [ "${_SSL_ITD}" = "${_OPENSSL_EOL_VRN}" ] \
      || [ "${_SSL_ITD}" = "${_OPENSSL_LEGACY_VRN}" ] \
      || [[ "${_SSL_ITD}" =~ "1.1.0" ]] \
      || [[ "${_SSL_ITD}" =~ "1.0.2" ]] \
      || [[ "${_SSL_ITD}" =~ "1.0.1" ]]; then
      _PFS_READY=YES
    else
      _PFS_READY=NO
    fi
    if [ "${_PFS_READY}" = "YES" ] \
      && [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
      _ALLOW_NGINX_FORWARD_SECRECY=YES
      _SSL_PROTOCOLS="TLSv1.2 TLSv1.3;"
      _SSL_CIPHERS="TLS_AES_128_GCM_SHA256:  \
        TLS_AES_256_GCM_SHA384:  \
        TLS_CHACHA20_POLY1305_SHA256:  \
        ECDHE-RSA-AES256-GCM-SHA384:  \
        ECDHE-ECDSA-AES256-GCM-SHA384:  \
        ECDHE-RSA-AES256-SHA384:  \
        ECDHE-ECDSA-AES256-SHA384:  \
        AES256-GCM-SHA384:  \
        ECDHE-ECDSA-CHACHA20-POLY1305:  \
        ECDHE-RSA-CHACHA20-POLY1305:  \
        DHE-RSA-AES256-CCM:  \
        DHE-RSA-AES256-CCM8:  \
        DHE-RSA-AES128-CCM:  \
        DHE-RSA-AES128-CCM8:  \
        ECDHE-RSA-AES128-GCM-SHA256:  \
        ECDHE-ECDSA-AES128-GCM-SHA256:  \
        DHE-RSA-AES128-GCM-SHA256:  \
        DHE-DSS-AES128-GCM-SHA256:  \
        kEDH+AESGCM:  \
        ECDHE-RSA-AES128-SHA256:  \
        ECDHE-ECDSA-AES128-SHA256:  \
        ECDHE-RSA-AES128-SHA:  \
        ECDHE-ECDSA-AES128-SHA:  \
        ECDHE-RSA-AES256-SHA:  \
        ECDHE-ECDSA-AES256-SHA:  \
        DHE-RSA-AES128-SHA256:  \
        DHE-RSA-AES128-SHA:  \
        DHE-DSS-AES128-SHA256:  \
        DHE-RSA-AES256-SHA256:  \
        DHE-DSS-AES256-SHA:  \
        DHE-RSA-AES256-SHA:  \
        AES128-GCM-SHA256:  \
        AES128-SHA256:  \
        AES256-SHA256:  \
        AES128-SHA:  \
        AES256-SHA:  \
        AES:  \
        \!aNULL:  \
        \!eNULL:  \
        \!EXPORT:  \
        \!DES:  \
        \!RC4:  \
        \!MD5:  \
        \!PSK:  \
        \!aECDH:  \
        \!EDH-DSS-DES-CBC3-SHA:  \
        \!EDH-RSA-DES-CBC3-SHA:  \
        \!KRB5-DES-CBC3-SHA:  \
        \!ECDHE-ECDSA-AES128-SHA256:  \
        \!ECDHE-ECDSA-AES256-SHA384;"
      _SSL_CIPHERS=$(echo "${_SSL_CIPHERS}" | sed "s/ //g" 2>&1)
    else
      _ALLOW_NGINX_FORWARD_SECRECY=NO
    fi
    if [ "${_ALLOW_NGINX_FORWARD_SECRECY}" = "YES" ]; then
      sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
        /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
        /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
        /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
        /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
    fi

    ###
    ### Nginx: Convert all vhosts to wildcard mode on Barracuda upgrade
    ### to avoid extended downtime until all Octopus instances will receive
    ### full upgrade, if IP based listen directive was used before.
    ###
    if [ -e "/var/aegir" ]; then
      sed -i "s/.*listen.*127.0.0.1:80;.*//g" \
        /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
      sed -i "s/listen .*\*:80;/listen  \*:80;/g" \
        /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    if [ -d "/data/u" ]; then
      sed -i "s/.*listen.*127.0.0.1:80;.*//g" \
        /data/disk/*/config/server_*/nginx.conf &> /dev/null
      wait
      sed -i "s/listen .*\*:80;/listen  \*:80;/g" \
        /data/disk/*/config/server_*/nginx.conf &> /dev/null
      wait
      sed -i "s/.*listen .*\*:80;/  listen  \*:80;/g" \
        /data/disk/*/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen  \*:443/g" \
        /data/disk/*/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*ssl .*on;//g" \
        /data/disk/*/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /data/disk/*/config/server_*/nginx/vhost.d/*
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/vhost.d/*
      wait
    fi

    if [ -d "/data/u" ]; then
      for _OCT in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
        _pthPrN="provision/http/Provision/Config/Nginx"
        if [ -e "${_OCT}/.drush/sys/drush_make" ]; then
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/sys/${_pthPrN}/server.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/sys/${_pthPrN}/vhost.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/sys/${_pthPrN}/vhost_disabled.tpl.php &> /dev/null
          wait
        elif [ -e "${_OCT}/.drush/drush_make" ]; then
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/${_pthPrN}/server.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/${_pthPrN}/vhost.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/${_pthPrN}/vhost_disabled.tpl.php &> /dev/null
          wait
        fi
      done
    fi

    ###
    ### Delete any ghost, outdated or broken config includes and vhosts
    ### in all Octopus instances which could break Nginx restart
    ###
    if [ -d "/data/u" ]; then
      for _File in $(find /data/disk/*/config/includes/ -type f -exec grep -l will_expire_in {} +); do
        rm -f "${_File}"
      done
      for Vght in `ls /data/disk/*/log/CANCELLED 2> /dev/null \
        | cut -d"/" -f4 \
        | awk '{ print $1}'`; do
        rm -f /data/disk/$Vght/config/server_*/nginx/vhost.d/*
      done
      _wildPth="/data/disk/*/.drush/sys/provision/http/Provision/Service/http/*.conf"
      sed -i "s/OctopusMicroNoCacheID/NoCacheID/g" ${_wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNCookie/AegirCookie/g"      ${_wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNoCacheID/NoCacheID/g"      ${_wildPth} &> /dev/null
      wait
    fi
    if [ -e "/var/aegir" ]; then
      _wildPth="/var/aegir/.drush/sys/provision/http/Provision/Service/http/*.conf"
      sed -i "s/OctopusMicroNoCacheID/NoCacheID/g" ${_wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNCookie/AegirCookie/g"      ${_wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNoCacheID/NoCacheID/g"      ${_wildPth} &> /dev/null
      wait
      sed -i "s/60/180/g" /var/aegir/config/server_*/nginx.conf  &> /dev/null
      wait
      sed -i "s/300/180/g" /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    _validate_public_ip &> /dev/null
    _CRON_IP=${_THISHTIP//[^0-9.]/}
    if [ ! -e "/root/.local.IP.list" ]; then
      rm -f /root/.tmp.IP.list*
      rm -f /root/.local.IP.list*
      for _IP in `hostname -I`;do echo ${_IP} >> /root/.tmp.IP.list;done
      for _IP in `cat /root/.tmp.IP.list \
        | sort \
        | uniq`; do
        echo "${_IP} # local IP address" >> /root/.local.IP.list
      done
      rm -f /root/.tmp.IP.list*
    fi
    _IP_IF_PRESENT=$(grep "${_CRON_IP}" /root/.local.IP.list 2>&1)
    if [[ "${_IP_IF_PRESENT}" =~ "${_CRON_IP}" ]]; then
      _IP_PRESENT=YES
    else
      _IP_PRESENT=NO
    fi
    if [ ! -z "${_CRON_IP}" ] \
      && [ "${_IP_PRESENT}" = "YES" ] \
      && [ -e "/root/.local.IP.list" ]; then
      _master_fix_multi_ip_cron_access
    fi
    _mrun "service nginx reload"
  fi
}
