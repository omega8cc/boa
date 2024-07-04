#
# Update Nginx Config.
nginx_conf_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: nginx_conf_update"
  fi
  if [ ! -e "${pthLog}/nginx-config-params-fixed-${_X_SE}-${_X_VERSION}.log" ] \
    && [ -d "/var/aegir" ]; then
    if [ -e "${locCnf}/nginx.conf" ] \
      && [ -e "/etc/nginx/nginx.conf" ]; then
      mv -f /etc/nginx/nginx.conf-* ${vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/mime.types-pre-* ${vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/fastcgi_params-pre-* ${vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/nginx.conf ${vBs}/dragon/t/nginx.conf-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
      mv -f /etc/nginx/fastcgi_params ${vBs}/dragon/t/fastcgi_params-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${locCnf}/nginx.conf /etc/nginx/nginx.conf
      cp -af ${locCnf}/fastcgi_params.txt /etc/nginx/fastcgi_params
      touch ${pthLog}/nginx-config-params-fixed-${_X_SE}-${_X_VERSION}.log
    fi
  fi
  if [ -e "${mtrNgx}/pre.d/nginx_speed_purge.conf" ]; then
    rm -f ${mtrNgx}/pre.d/nginx_speed_purge.conf
  fi
}

#
# Sub Force advanced Nginx configuration.
sub_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: sub_force_advanced_nginx_config"
  fi
  if [ -e "/opt/php${_PHP_SV}/etc/php${_PHP_SV}-fpm.conf" ]; then
    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrInc}/nginx_compact_include.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${mtrInc}/nginx_vhost_common.conf &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${mtrInc}/nginx_vhost_common.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${mtrTpl}/subdir.tpl.php &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${mtrTpl}/subdir.tpl.php &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"        ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    wait
    sed -i "s/set.*user_socket.*/set \$user_socket \"${_PHP_CN}\";/g"              ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
  fi
}

#
# Force advanced Nginx configuration.
force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: force_advanced_nginx_config"
  fi
  if [ ! -e "/etc/ssl/private/nginx-wild-ssl.dhp" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      msg "INFO: Generating DH parameters, 2048 bit..."
    fi
    mrun "openssl dhparam -out /etc/ssl/private/nginx-wild-ssl.dhp 2048" 2> /dev/null
    wait
  fi
  cp -af ${locCnf}/nginx_compact_include.conf ${mtrInc}/nginx_compact_include.conf
  validate_local_ip &> /dev/null
  sub_force_advanced_nginx_config
  sed -i "s/ 90;/ 180;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
  wait
  if [ "${_NGINX_SPDY}" = "YES" ]; then
    if [ "${_OS_CODE}" = "none" ]; then
      sed -i "s/:443;/:443 ssl spdy;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443;/:443 ssl spdy;/g" ${mtrNgx}/vhost.d/* &> /dev/null
      wait
      sed -i "s/:443 ssl http2;/:443 ssl spdy;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl http2;/:443 ssl spdy;/g" ${mtrNgx}/vhost.d/* &> /dev/null
      wait
    else
      sed -i "s/:443;/:443 ssl;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443;/:443 ssl;/g" ${mtrNgx}/vhost.d/* &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443 ssl;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443 ssl;/g" ${mtrNgx}/vhost.d/* &> /dev/null
      wait
    fi
  else
    sed -i "s/:443 ssl http2;/:443;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443 ssl http2;/:443;/g" ${mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/:443 ssl spdy;/:443;/g"  ${mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/:443 ssl spdy;/:443;/g"  ${mtrNgx}/vhost.d/* &> /dev/null
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
    _SSL_CIPHERS="ECDHE-RSA-AES256-GCM-SHA384:  \
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
      ${mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/ssl_protocols .*/ssl_protocols                ${_SSL_PROTOCOLS}/g" \
      ${mtrNgx}/vhost.d/* &> /dev/null
    wait
    sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
      ${mtrNgx}/pre.d/*.conf &> /dev/null
    wait
    sed -i "s/ssl_ciphers .*/ssl_ciphers                  ${_SSL_CIPHERS}/g" \
      ${mtrNgx}/vhost.d/* &> /dev/null
    wait
  fi
  if [ -e "${mtrInc}/nginx_vhost_common.conf" ]; then
    rm -f ${mtrInc}/nginx_advanced_include.conf
    rm -f ${mtrInc}/nginx_legacy_include.conf
    rm -f ${mtrInc}/nginx_modern_include.conf
    rm -f ${mtrInc}/nginx_octopus_include.conf
    rm -f ${mtrInc}/nginx_simple_include.conf
  fi
  chown aegir:aegir ${mtrInc}/*
  chown aegir:aegir /var/aegir/.drush/sys/provision/http/Provision/Config/Nginx/*
  if [ ! -e "/data/conf/nginx_high_load_off.conf" ]; then
    mkdir -p /data/conf
    cp -af ${locCnf}/nginx_high_load_off.conf /data/conf/nginx_high_load_off.conf
    chmod 644 /data/conf/nginx_high_load_off.conf &> /dev/null
  fi
  if [ -e "/root/.giant_traffic.cnf" ]; then
    sed -i "s/access_log .*/access_log             /var/log/nginx/access.log main buffer=32k;/g" ${mtrNgx}.conf &> /dev/null
    wait
  fi
}

#
# Check for Linux/Cdorked.A malware and delete if discovered.
detect_cdorked_malware() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: detect_cdorked_malware"
  fi
  if [ -x "/usr/sbin/nginx" ]; then
    _C_DORKED=NO
    _C_FILE=${bldPth}/aegir/helpers/dump_cdorked_config.c
    if [ -e "${_C_FILE}" ]; then
      ### msg "INFO: Checking for Linux/Cdorked.A malware..."
      chattr -ai /usr/sbin/nginx
      cd ${vBs}
      rm -rf /var/opt/foo_bar*
      gcc -o /var/opt/foo_bar ${bldPth}/aegir/helpers/dump_cdorked_config.c &> /dev/null
      _C_DORKED_TEST=$(/var/opt/foo_bar 2>&1)
      if [[ "${_C_DORKED_TEST}" =~ "No shared memory matching Cdorked signature" ]]; then
        _DO_NOTHING=YES
        ### msg "INFO: No Linux/Cdorked.A malware traces found - system clean"
      else
        msg "ALRT! Your system is probably infected by Linux/Cdorked.A malware!"
        msg "ALRT! Please send the ${vBs}/httpd_cdorked_config.bin file"
        msg "ALRT! to leveille@eset.com for investigation"
        rm -f $(which nginx)
        _NGX_FORCE_REINSTALL=YES
        _C_DORKED=YES
      fi
    fi
  fi
}

#
# Purge legacy Nginx config.
nginx_clean_legacy_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: nginx_clean_legacy_config"
  fi
  if [ -e "/var/aegir/config/server_master/nginx/pre.d/nginx_speed_purge.conf" ]; then
    rm -f /var/aegir/config/server_master/nginx/pre.d/nginx_speed_purge.conf
  fi
  _R_TEST=$(grep "upload_progress" /var/aegir/config/nginx.conf 2>&1)
  if [[ "${_R_TEST}" =~ "upload_progress" ]]; then
    sed -i "s/.*upload_progress.*//g" /var/aegir/config/nginx.conf
  fi
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
  mrun "service nginx reload" 2> /dev/null
}

#
# Install or upgrade Nginx.
nginx_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: nginx_install_upgrade"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Testing Nginx version..."
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ -x "/usr/sbin/nginx" ]; then
    _NGINX_F_ITD=$(/usr/sbin/nginx -v 2>&1 | tr -d "\n" \
      | cut -d"/" -f2 | awk '{ print $1}' 2>&1)
    _NGINX_V_ITD=$(/usr/sbin/nginx -V 2>&1)
    if [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ] \
      && [ "${_STATUS}" = "UPGRADE" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Nginx ${_NGINX_F_ITD}, OK"
      fi
    elif [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ] \
      && [ "${_STATUS}" = "INIT" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Nginx ${_NGINX_F_ITD}, OK"
      fi
    elif [ "${_NGINX_F_ITD}" != "${_NGINX_VRN}" ]; then
      _NGINX_INSTALL_REQUIRED=YES
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Nginx ${_NGINX_F_ITD}, upgrade required"
      fi
    fi
    if [ "${_NGINX_F_ITD}" = "${_NGINX_VRN}" ]; then
      if [[ ! "${_NGINX_V_ITD}" =~ "geoip" ]]; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          msg "INFO: Nginx forced rebuild to include geoip module"
        fi
      fi
      if [[ "${_NGINX_V_ITD}" =~ "nginx-development-kit" ]]; then
        _NGINX_INSTALL_REQUIRED=YES
        msg "INFO: Nginx rebuild required to avoid apt-get overwrite"
      fi
      if [[ ! "${_NGINX_V_ITD}" =~ "http_flv_module" ]] \
        || [[ ! "${_NGINX_V_ITD}" =~ "http_mp4_module" ]]; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          msg "INFO: Nginx forced rebuild to include pseudo-streaming support"
        fi
      fi
      if [ "${_OS_CODE}" = "daedalus" ] \
        || [ "${_OS_CODE}" = "chimaera" ] \
        || [ "${_OS_CODE}" = "beowulf" ] \
        || [ "${_OS_CODE}" = "bookworm" ] \
        || [ "${_OS_CODE}" = "bullseye" ] \
        || [ "${_OS_CODE}" = "buster" ] \
        || [ "${_OS_CODE}" = "stretch" ]; then
        _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
        if [ -e "/root/.install.modern.openssl.cnf" ]; then
          _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
        fi
      else
        _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
      fi
      if [[ ! "${_NGINX_V_ITD}" =~ "openssl-${_OPENSSL_NEW_VRN}" ]]; then
        _NGINX_INSTALL_REQUIRED=YES
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
          msg "INFO: Nginx forced rebuild to include latest OpenSSL version"
        fi
      fi
      if [ "${_NGINX_HEADERS}" = "YES" ]; then
        if [[ ! "${_NGINX_V_ITD}" =~ "nginx-headers-more" ]]; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            msg "INFO: Nginx forced rebuild to include Headers More support"
          fi
        fi
      fi
      if [ "${_NGINX_LDAP}" = "YES" ]; then
        if [[ ! "${_NGINX_V_ITD}" =~ "nginx-auth-ldap" ]]; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            msg "INFO: Nginx forced rebuild to include LDAP support"
          fi
        fi
      fi
      if [ "${_PURGE_MODE}" = "ON" ]; then
        if [[ ! "${_NGINX_V_ITD}" =~ "purge" ]]; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            msg "INFO: Nginx forced rebuild to include purge module"
          fi
        fi
      fi
      if [ "${_NGINX_NAXSI}" = "YES" ]; then
        if [[ ! "${_NGINX_V_ITD}" =~ "naxsi" ]]; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            msg "INFO: Nginx forced rebuild to include NAXSI module"
          fi
        fi
      fi
      if [ "${_NGINX_SPDY}" = "YES" ]; then
        if [[ ! "${_NGINX_V_ITD}" =~ "http_v2_module" ]]; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            msg "INFO: Nginx forced rebuild to include HTTP/2 support"
          fi
        fi
        if [[ ! "${_NGINX_V_ITD}" =~ "http_v3_module" ]] \
          && [ "${_OPENSSL_NEW_VRN}" != "${_OPENSSL_LEGACY_VRN}" ]; then
          _NGINX_INSTALL_REQUIRED=YES
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            msg "INFO: Installed Nginx ${_NGINX_F_ITD}"
            msg "INFO: Nginx forced rebuild to include HTTP/3 support"
          fi
        fi
      fi
    fi
  else
    _NGINX_INSTALL_REQUIRED=YES
  fi
  detect_cdorked_malware
  if [ "${_C_DORKED}" = "YES" ]; then
    _NGINX_INSTALL_REQUIRED=YES
    msg "INFO: Nginx rebuild required to remove possible Linux/Cdorked.A malware"
  fi
  if [ "${_NGINX_INSTALL_REQUIRED}" = "YES" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_NGX_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_STATUS}" = "UPGRADE" ]; then
      msg "INFO: Upgrading Nginx to ${_NGINX_VRN}..."
    else
      msg "INFO: Installing Nginx ${_NGINX_VRN}..."
    fi
    cd /var/opt; rm -rf nginx*
    get_dev_src "nginx-${_NGINX_VRN}.tar.gz"
    sed -i "s/nginx/${_CUSTOM_NAME}/g" \
      /var/opt/nginx-${_NGINX_VRN}/src/core/nginx.h &> /dev/null
    wait
    if [ ! -z "${_NGINX_EXTRA_CONF}" ]; then
      _NGINX_EXTRA="${_NGINX_EXTRA_CONF}"
    else
      _NGINX_EXTRA=""
    fi
    if [ "${_NGINX_HEADERS}" = "YES" ]; then
      cd /var/opt
      rm -rf /var/opt/nginx-headers-more*
      get_dev_src "nginx-headers-more.tar.gz"
      if [ -e "/var/opt/nginx-headers-more" ]; then
        _NGINX_EXTRA="--add-module=/var/opt/nginx-headers-more/ ${_NGINX_EXTRA}"
      fi
    fi
    if [ "${_NGINX_LDAP}" = "YES" ]; then
      cd /var/opt
      rm -rf /var/opt/nginx-auth-ldap*
      get_dev_src "nginx-auth-ldap.tar.gz"
      if [ -e "/var/opt/nginx-auth-ldap" ]; then
        _NGINX_EXTRA="--add-module=/var/opt/nginx-auth-ldap/ ${_NGINX_EXTRA}"
      fi
    fi
    if [ "${_NGINX_NAXSI}" = "YES" ]; then
      cd /var/opt
      rm -rf /var/opt/nginx-naxsi*
      get_dev_src "nginx-naxsi.tar.gz"
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
    if [ "${_OS_CODE}" = "daedalus" ] \
      || [ "${_OS_CODE}" = "chimaera" ] \
      || [ "${_OS_CODE}" = "beowulf" ] \
      || [ "${_OS_CODE}" = "bookworm" ] \
      || [ "${_OS_CODE}" = "bullseye" ] \
      || [ "${_OS_CODE}" = "buster" ] \
      || [ "${_OS_CODE}" = "stretch" ]; then
      _OPENSSL_NEW_VRN="${_OPENSSL_EOL_VRN}"
      if [ -e "/root/.install.modern.openssl.cnf" ]; then
        _OPENSSL_NEW_VRN="${_OPENSSL_MODERN_VRN}"
      fi
    else
      _OPENSSL_NEW_VRN="${_OPENSSL_LEGACY_VRN}"
    fi
    if [ ! -e "/var/opt/openssl-${_OPENSSL_NEW_VRN}" ]; then
      cd /var/opt
      rm -rf openssl*
      get_dev_src "openssl-${_OPENSSL_NEW_VRN}.tar.gz"
    fi
    cd /var/opt/nginx-${_NGINX_VRN}
    mrun "bash ./configure \
      --prefix=/usr \
      --sbin-path=/usr/sbin/nginx \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/var/log/nginx/error.log \
      --http-log-path=/var/log/nginx/access.log \
      --pid-path=/var/run/nginx.pid \
      --lock-path=/var/lock/nginx.lock \
      --user=www-data \
      --group=www-data \
      --with-http_dav_module \
      --with-http_flv_module \
      --with-http_geoip_module \
      --with-http_gzip_static_module \
      --with-http_mp4_module \
      --with-http_realip_module \
      --with-http_ssl_module \
      --with-http_stub_status_module \
      --with-stream_ssl_module \
      --without-http_scgi_module \
      --without-http_uwsgi_module \
      --without-mail_imap_module \
      --without-mail_pop3_module \
      --without-mail_smtp_module \
      --with-openssl=/var/opt/openssl-${_OPENSSL_NEW_VRN} \
      --with-debug ${_NGINX_EXTRA}" 2> /dev/null
    mrun "make -j $(nproc)" 2> /dev/null
    mrun "make install" 2> /dev/null
    ldconfig 2> /dev/null
    nginx_clean_legacy_config
    mrun "service nginx quietupgrade" 2> /dev/null
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ ! -L "/usr/bin/nginx" ]; then
    ln -sfn /usr/sbin/nginx /usr/bin/nginx
  fi
}

#
# Fix multi-IP cron access.
master_fix_multi_ip_cron_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: master_fix_multi_ip_cron_access"
  fi
  [ -e "/root/.local.IP.list.allow" ] && rm -f /root/.local.IP.list.allow
  for _IP in `cat /root/.local.IP.list \
    | cut -d '#' -f1 \
    | sort \
    | uniq \
    | tr -d "\s"`;do echo "  allow        ${_IP};" >> \
      /root/.local.IP.list.allow;done
  echo "  allow        127.0.0.1;" >> /root/.local.IP.list.allow
  echo "  deny         all;" >> /root/.local.IP.list.allow

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" \
    ${mtrTpl}/Inc/vhost_include.tpl.php
  wait
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${mtrTpl}/Inc/vhost_include.tpl.php
  wait

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" \
    ${mtrTpl}/subdir.tpl.php
  wait
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${mtrTpl}/subdir.tpl.php
  wait

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" \
    ${mtrInc}/nginx_vhost_common.conf
  wait
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${mtrInc}/nginx_vhost_common.conf
  wait
}

nginx_initd_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: nginx_initd_check"
  fi
  _X_INIT_TEST=
  if [ -e "/etc/init.d/nginx" ]; then
    _X_INIT_TEST=$(cat /etc/init.d/nginx | grep ULIMIT 2>&1)
  fi
  if [[ "${_X_INIT_TEST}" =~ "ULIMIT" ]]; then
    chmod 755 /etc/init.d/nginx &> /dev/null
    mrun "update-rc.d nginx defaults" 2> /dev/null
  else
    mv -f /etc/init.d/nginx \
      ${vBs}/nginx-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${locCnf}/nginx /etc/init.d/nginx
    chmod 755 /etc/init.d/nginx &> /dev/null
    mrun "update-rc.d nginx defaults" 2> /dev/null
    mrun "service nginx start" 2> /dev/null
  fi
}

nginx_mime_check_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: nginx_mime_check_fix"
  fi
  if [ -e "${locCnf}/mime.types" ]; then
    mv -f /etc/nginx/mime.types \
      /etc/nginx/mime.types-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
    cp -af ${locCnf}/mime.types /etc/nginx/mime.types
    if [ ! -L "/var/www/nginx-default/index.html" ] \
      && [ ! -L "/var/www/nginx-default/under_construction.jpg" ]; then
      mkdir -p /var/www/nginx-default
      mv -f /var/www/nginx-default/index.html \
        /var/www/nginx-default/index.html-pre-${_X_SE}-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${locCnf}/uc.html /var/www/nginx-default/index.html
      cp -af ${locCnf}/under_construction.jpg \
        /var/www/nginx-default/under_construction.jpg
    fi
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/modules-enabled/*
    if [ ! -e "/var/run/aegir_upgrade.pid" ]; then
      mrun "service nginx reload" 2> /dev/null
    fi
  fi
}

nginx_wildcard_ssl_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: nginx_wildcard_ssl_install"
  fi
  _WILD_SSL_VHOST="${mtrNgx}/pre.d/nginx_wild_ssl.conf"
  if [ ! -e "${_WILD_SSL_VHOST}" ]; then
    msg "INFO: Installing default SSL Wildcard Nginx Proxy..."
    validate_public_ip &> /dev/null
    validate_xtras_ip &> /dev/null
    openssl req -x509 -nodes -sha256 -days 7300 \
      -subj "/C=US/ST=New York/O=Aegir/OU=Cloud/L=New York/CN=*.${_THISHOST}" \
      -newkey rsa:2048 \
      -keyout /etc/ssl/private/nginx-wild-ssl.key \
      -out /etc/ssl/private/nginx-wild-ssl.crt -batch 2> /dev/null
    cp -af ${locCnf}/nginx_wild_ssl.conf ${_WILD_SSL_VHOST}
    sed -i "s/127.0.0.1:80/localhost:80/g" ${_WILD_SSL_VHOST} &> /dev/null
    sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g" ${_WILD_SSL_VHOST} &> /dev/null
    mkdir -p /data/conf
    if [ -e "${locCnf}/global.inc" ]; then
      cp -af ${locCnf}/global.inc /data/conf/global.inc
    fi
    if [ -e "${mtrInc}" ] \
      && [ ! -L "${mtrInc}/global.inc" ] \
      && [ -e "/data/conf/global.inc" ]; then
      ln -sfn /data/conf/global.inc ${mtrInc}/global.inc
    fi
    sed -i "s/3600/${_SPEED_VALID_MAX}/g" /data/conf/global.inc &> /dev/null
    redis_password_update
    mrun "service nginx quietupgrade" 2> /dev/null
  else
    _WILD_SSL_PROXY_UP=NO
    _HTTP3_TEST=$(grep http3 ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_HTTP3_TEST}" =~ "http3" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: nginx_wild_ssl.conf proxy needs http3 update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    _WILDCARD_SSL_TEST=$(grep "localhost:80" ${_WILD_SSL_VHOST} 2>&1)
    if [[ ! "${_WILDCARD_SSL_TEST}" =~ "localhost:80" ]]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: nginx_wild_ssl.conf proxy needs port update..."
      fi
      _WILD_SSL_PROXY_UP=YES
    fi
    if [ "${_WILD_SSL_PROXY_UP}" = "YES" ]; then
      validate_public_ip &> /dev/null
      validate_xtras_ip &> /dev/null
      cp -af ${locCnf}/nginx_wild_ssl.conf ${_WILD_SSL_VHOST}
      sed -i "s/127.0.0.1:80/localhost:80/g" ${_WILD_SSL_VHOST}
      wait
      sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g" ${_WILD_SSL_VHOST}
    fi
  fi
}

nginx_config_update_fix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: nginx_config_update_fix"
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    mrun "service cron start" 2> /dev/null
    if [ "${_EASY_SETUP}" = "NO" ]; then
      echo " "
      msg "Now waiting 2 minutes before restarting Nginx..."
      mrun "sleep 111"
    fi
    force_advanced_nginx_config
    mrun "sleep 8"
    mrun "service nginx restart" 2> /dev/null
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
      sed -i "s/.*listen .*\*:80;/  listen                       \*:80;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen                       \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/adminer.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen                       \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/cgp.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen                       \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/chive.* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen                       \*:443/g" /var/aegir/config/server_*/nginx/vhost.d/sqlbuddy.* &> /dev/null
      wait
      sed -i "s/SSLv3 TLSv1;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/SSLv3 TLSv1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/TLSv1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      if [ -e "/data/disk" ]; then
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
      sed -i "s/ssl_prefer_server_ciphers .*/ssl_prefer_server_ciphers on;\n  ssl_stapling on;\n  ssl_stapling_verify on;\n  resolver 1.1.1.1 1.0.0.1 valid=300s;\n  resolver_timeout 5s;/g" \
        /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/add_header Vary .*//g" /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    if [ "${_NGINX_SPDY}" = "YES" ]; then
      if [ "${_OS_CODE}" = "none" ]; then
        sed -i "s/:443;/:443 ssl spdy;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
        wait
        sed -i "s/:443;/:443 ssl spdy;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
        wait
        sed -i "s/:443 ssl http2;/:443 ssl spdy;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
        wait
        sed -i "s/:443 ssl http2;/:443 ssl spdy;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
        wait
      else
        sed -i "s/:443;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
        wait
        sed -i "s/:443;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
        wait
        sed -i "s/:443 ssl spdy;/:443 ssl;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
        wait
        sed -i "s/:443 ssl spdy;/:443 ssl;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
        wait
      fi
    else
      sed -i "s/:443 ssl http2;/:443;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl http2;/:443;/g" /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443;/g"  /var/aegir/config/server_*/nginx/pre.d/*.conf &> /dev/null
      wait
      sed -i "s/:443 ssl spdy;/:443;/g"  /var/aegir/config/server_*/nginx/vhost.d/* &> /dev/null
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
      _SSL_CIPHERS="ECDHE-RSA-AES256-GCM-SHA384:  \
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
      sed -i "s/listen .*\*:80;/listen        \*:80;/g" \
        /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    if [ -e "/data/disk" ]; then
      sed -i "s/.*listen.*127.0.0.1:80;.*//g" \
        /data/disk/*/config/server_*/nginx.conf &> /dev/null
      wait
      sed -i "s/listen .*\*:80;/listen        \*:80;/g" \
        /data/disk/*/config/server_*/nginx.conf &> /dev/null
      wait
      sed -i "s/.*listen .*\*:80;/  listen        \*:80;/g" \
        /data/disk/*/config/server_*/nginx/vhost.d/* &> /dev/null
      wait
      sed -i "s/.*listen .*\*:443/  listen        \*:443/g" \
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

    if [ -e "/data/disk" ]; then
      for _OCT in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
        pthPrN="provision/http/Provision/Config/Nginx"
        if [ -e "${_OCT}/.drush/sys/drush_make" ]; then
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/sys/${pNx}/server.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/sys/${pNx}/vhost.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/sys/${pNx}/vhost_disabled.tpl.php &> /dev/null
          wait
        elif [ -e "${_OCT}/.drush/drush_make" ]; then
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/${pNx}/server.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/${pNx}/vhost.tpl.php &> /dev/null
          wait
          sed -i "s/\!empty.*';/'*';/g" \
            ${_OCT}/.drush/${pNx}/vhost_disabled.tpl.php &> /dev/null
          wait
        fi
      done
    fi

    ###
    ### Delete any ghost, outdated or broken config includes and vhosts
    ### in all Octopus instances which could break Nginx restart
    ###
    if [ -e "/data/disk" ]; then
      for File in `grep will_expire_in /data/disk/*/config/includes/* \
        | cut -d: -f1 \
        | awk '{ print $1}'`; do
        rm -f $File
      done
      for Vght in `ls /data/disk/*/log/CANCELLED 2> /dev/null \
        | cut -d"/" -f4 \
        | awk '{ print $1}'`; do
        rm -f /data/disk/$Vght/config/server_*/nginx/vhost.d/*
      done
      wildPth="/data/disk/*/.drush/sys/provision/http/Provision/Service/http/*.conf"
      sed -i "s/OctopusMicroNoCacheID/NoCacheID/g" ${wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNCookie/AegirCookie/g"      ${wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNoCacheID/NoCacheID/g"      ${wildPth} &> /dev/null
      wait
    fi
    if [ -e "/var/aegir" ]; then
      wildPth="/var/aegir/.drush/sys/provision/http/Provision/Service/http/*.conf"
      sed -i "s/OctopusMicroNoCacheID/NoCacheID/g" ${wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNCookie/AegirCookie/g"      ${wildPth} &> /dev/null
      wait
      sed -i "s/OctopusNoCacheID/NoCacheID/g"      ${wildPth} &> /dev/null
      wait
      sed -i "s/60/180/g" /var/aegir/config/server_*/nginx.conf  &> /dev/null
      wait
      sed -i "s/300/180/g" /var/aegir/config/server_*/nginx.conf &> /dev/null
      wait
    fi
    validate_public_ip &> /dev/null
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
      master_fix_multi_ip_cron_access
    fi
    mrun "service nginx reload" 2> /dev/null
  fi
}
