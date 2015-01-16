#
# Update Nginx Config.
update_nginx_conf() {
  if [ ! -e "${pthLog}/nginx-config-fixed-${_X_VERSION}" ] \
    && [ -d "/var/aegir" ]; then
    if [ -e "${locCnf}/nginx.conf" ] \
      && [ -e "/etc/nginx/nginx.conf" ]; then
      mv -f /etc/nginx/nginx.conf-* ${vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/mime.types-pre-* ${vBs}/dragon/t/ &> /dev/null
      mv -f /etc/nginx/nginx.conf ${vBs}/dragon/t/nginx.conf-pre-${_X_VERSION}-${_NOW} &> /dev/null
      cp -af ${locCnf}/nginx.conf /etc/nginx/nginx.conf
      touch ${pthLog}/nginx-config-fixed-${_X_VERSION}
    fi
  fi
  if [ -e "${mtrNgx}/pre.d" ] \
    && [ "${_PURGE_MODE}" = "ON" ]; then
    cp -af ${locCnf}/nginx_speed_purge.conf ${mtrNgx}/pre.d/nginx_speed_purge.conf
  fi
}

#
# Sub Force advanced Nginx configuration.
sub_force_advanced_nginx_config() {
  if [ -e "/opt/php${_PHP_SV}/etc/php${_PHP_SV}-fpm.conf" ]; then
    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrInc}/nginx_compact_include.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrInc}/nginx_vhost_common.conf &> /dev/null
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${mtrInc}/nginx_vhost_common.conf &> /dev/null
    sed -i "s/unix:cron:fastcgi.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g" ${mtrInc}/nginx_vhost_common.conf &> /dev/null
    sed -i "s/unix:.*www53.fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"  ${mtrInc}/nginx_vhost_common.conf &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrTpl}/subdir.tpl.php &> /dev/null
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${mtrTpl}/subdir.tpl.php &> /dev/null
    sed -i "s/unix:cron:fastcgi.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g" ${mtrTpl}/subdir.tpl.php &> /dev/null
    sed -i "s/unix:.*www53.fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"  ${mtrTpl}/subdir.tpl.php &> /dev/null

    sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"             ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    sed -i "s/data.*post.d/var\/aegir\/config\/includes/g"                         ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    sed -i "s/unix:cron:fastcgi.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g" ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
    sed -i "s/unix:.*www53.fpm.socket;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g"  ${mtrTpl}/Inc/vhost_include.tpl.php &> /dev/null
  fi
}

#
# Force advanced Nginx configuration.
force_advanced_nginx_config() {
  cp -af ${locCnf}/nginx_compact_include.conf ${mtrInc}/nginx_compact_include.conf
  validate_local_ip &> /dev/null
  sub_force_advanced_nginx_config
  sed -i "s/ 90;/ 180;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
  if [ "${_NGINX_SPDY}" = "YES" ]; then
    sed -i "s/:443;/:443 ssl spdy;/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
    sed -i "s/:443;/:443 ssl spdy;/g" ${mtrNgx}/vhost.d/*    &> /dev/null
  fi
  _SSL_ITD=$(openssl version 2>&1 \
    | tr -d "\n" \
    | cut -d" " -f2 \
    | awk '{ print $1}' 2>&1)
  if [ "${_SSL_ITD}" = "${_OPENSSL_VRN}" ] \
    && [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    _ALLOW_NGINX_FORWARD_SECRECY=YES
    _SSL_PROTOCOLS="TLSv1 TLSv1.1 TLSv1.2;"
    _SSL_CIPHERS="EECDH+ECDSA+AESGCM: \
      EECDH+aRSA+AESGCM:  \
      EECDH+ECDSA+SHA384: \
      EECDH+ECDSA+SHA256: \
      EECDH+aRSA+SHA384:  \
      EECDH+aRSA+SHA256:  \
      EECDH:    \
      EDH+aRSA: \
      \!aNULL:  \
      \!eNULL:  \
      \!LOW:    \
      \!3DES:   \
      \!MD5:    \
      \!EXP:    \
      \!PSK:    \
      \!SRP:    \
      \!DSS:    \
      \!RC4;"
    _SSL_CIPHERS=$(echo "${_SSL_CIPHERS}" | sed "s/ //g" 2>&1)
  else
    _ALLOW_NGINX_FORWARD_SECRECY=NO
  fi
  if [ "$_ALLOW_NGINX_FORWARD_SECRECY" = "YES" ]; then
    sed -i "s/ssl_protocols .*/ssl_protocols $_SSL_PROTOCOLS/g" ${mtrNgx}/pre.d/*.conf &> /dev/null
    sed -i "s/ssl_protocols .*/ssl_protocols $_SSL_PROTOCOLS/g" ${mtrNgx}/vhost.d/*    &> /dev/null
    sed -i "s/ssl_ciphers .*/ssl_ciphers $_SSL_CIPHERS/g" ${mtrNgx}/pre.d/*.conf       &> /dev/null
    sed -i "s/ssl_ciphers .*/ssl_ciphers $_SSL_CIPHERS/g" ${mtrNgx}/vhost.d/*          &> /dev/null
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
  if [ -e "/root/.high_traffic.cnf" ]; then
    sed -i "s/access_log .*/access_log             /var/log/nginx/access.log main buffer=32k;/g" ${mtrNgx}.conf &> /dev/null
  fi
}

#
# Check for Linux/Cdorked.A malware and delete if discovered.
detect_cdorked_malware() {
  _C_DORKED=NO
  _C_FILE=${bldPth}/aegir/helpers/dump_cdorked_config.c
  if [ -e "$_C_FILE" ]; then
    ### msg "INFO: Checking for Linux/Cdorked.A malware..."
    chattr -ai $(which nginx) &> /dev/null
    cd ${vBs}
    rm -f -r /var/opt/foo_bar*
    gcc -o /var/opt/foo_bar ${bldPth}/aegir/helpers/dump_cdorked_config.c &> /dev/null
    _C_DORKED_TEST=$(/var/opt/foo_bar 2>&1)
    if [[ "$_C_DORKED_TEST" =~ "No shared memory matching Cdorked signature" ]]; then
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
}

#
# Install or upgrade Nginx.
install_upgrade_nginx() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "INFO: Testing Nginx version..."
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ -x "/usr/sbin/nginx" ]; then
    _NGINX_F_ITD=$(/usr/sbin/nginx -v 2>&1 | tr -d "\n" \
      | cut -d" " -f4 | awk '{ print $1}' 2>&1)
    _NGINX_V_ITD=$(/usr/sbin/nginx -V 2>&1)
    if [ -z "$_NGINX_F_ITD" ]; then
      _NGINX_F_ITD=$(/usr/sbin/nginx -v 2>&1 | tr -d "\n" \
        | cut -d" " -f3 | awk '{ print $1}' 2>&1)
    fi
    _NGINX_F_VERSION="${_CUSTOM_NAME}/${_NGINX_VRN}"
    if [ "$_NGINX_F_ITD" = "$_NGINX_F_VERSION" ] \
      && [ "${_STATUS}" = "UPGRADE" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Nginx version $_NGINX_F_ITD, OK"
      fi
    elif [ "$_NGINX_F_ITD" = "$_NGINX_F_VERSION" ] \
      && [ "${_STATUS}" = "INIT" ]; then
      _NGINX_INSTALL_REQUIRED=NO
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: Installed Nginx version $_NGINX_F_ITD, OK"
      fi
    elif [ "$_NGINX_F_ITD" != "$_NGINX_F_VERSION" ]; then
      _NGINX_INSTALL_REQUIRED=YES
      msg "INFO: Installed Nginx version $_NGINX_F_ITD, upgrade required"
    fi
    if [ "$_NGINX_F_ITD" = "$_NGINX_F_VERSION" ]; then
      if [[ "$_NGINX_V_ITD" =~ "geoip" ]]; then
        _DO_NOTHING=YES
      else
        _NGINX_INSTALL_REQUIRED=YES
        msg "INFO: Installed Nginx version $_NGINX_F_ITD"
        msg "INFO: Nginx forced rebuild to include geoip module"
      fi
      if [[ "$_NGINX_V_ITD" =~ "nginx-development-kit" ]]; then
        _NGINX_INSTALL_REQUIRED=YES
        msg "INFO: Nginx rebuild required to avoid apt-get overwrite"
      fi
      if [[ "$_NGINX_V_ITD" =~ "http_flv_module" ]] \
        && [[ "$_NGINX_V_ITD" =~ "http_mp4_module" ]]; then
        _DO_NOTHING=YES
      else
        _NGINX_INSTALL_REQUIRED=YES
        msg "INFO: Installed Nginx version $_NGINX_F_ITD"
        msg "INFO: Nginx forced rebuild to include pseudo-streaming support"
      fi
      if [ "${_NGINX_LDAP}" = "YES" ]; then
        if [[ "$_NGINX_V_ITD" =~ "nginx-auth-ldap" ]]; then
          _DO_NOTHING=YES
        else
          _NGINX_INSTALL_REQUIRED=YES
          msg "INFO: Installed Nginx version $_NGINX_F_ITD"
          msg "INFO: Nginx forced rebuild to include LDAP support"
        fi
      fi
      if [ "${_PURGE_MODE}" = "ON" ]; then
        if [[ "$_NGINX_V_ITD" =~ "purge" ]]; then
          _DO_NOTHING=YES
        else
          _NGINX_INSTALL_REQUIRED=YES
          msg "INFO: Installed Nginx version $_NGINX_F_ITD"
          msg "INFO: Nginx forced rebuild to include purge module"
        fi
      fi
      if [ "${_NGINX_NAXSI}" = "YES" ]; then
        if [[ "$_NGINX_V_ITD" =~ "naxsi" ]]; then
          _DO_NOTHING=YES
        else
          _NGINX_INSTALL_REQUIRED=YES
          msg "INFO: Installed Nginx version $_NGINX_F_ITD"
          msg "INFO: Nginx forced rebuild to include NAXSI module"
        fi
      fi
      if [ "${_NGINX_SPDY}" = "YES" ]; then
        if [[ "$_NGINX_V_ITD" =~ "http_spdy_module" ]]; then
          _DO_NOTHING=YES
        else
          _NGINX_INSTALL_REQUIRED=YES
          msg "INFO: Installed Nginx version $_NGINX_F_ITD"
          msg "INFO: Nginx forced rebuild to include SPDY support"
        fi
      fi
    fi
  else
    _NGINX_INSTALL_REQUIRED=YES
  fi
  detect_cdorked_malware
  if [ "$_C_DORKED" = "YES" ]; then
    _NGINX_INSTALL_REQUIRED=YES
    msg "INFO: Nginx rebuild required to remove possible Linux/Cdorked.A malware"
  fi
  if [ "$_NGINX_INSTALL_REQUIRED" = "YES" ] \
    || [ "${_FULL_FORCE_REINSTALL}" = "YES" ] \
    || [ "${_NGX_FORCE_REINSTALL}" = "YES" ]; then
    if [ "${_STATUS}" = "UPGRADE" ]; then
      msg "INFO: Upgrading Nginx..."
    else
      msg "INFO: Installing Nginx..."
    fi
    cd /var/opt; rm -f -r nginx*
    get_dev_src "nginx-upload-progress-module.tar.gz"
    if [ "${_PURGE_MODE}" = "ON" ]; then
      get_dev_src "ngx-cache-purge.tar.gz"
    fi
    get_dev_src "nginx-${_NGINX_VRN}.tar.gz"
    sed -i "s/nginx/${_CUSTOM_NAME}/g" \
      /var/opt/nginx-${_NGINX_VRN}/src/core/nginx.h &> /dev/null
    if [ "${_PURGE_MODE}" = "ON" ] && [ -z "${_NGINX_EXTRA_CONF}" ]; then
      _NGINX_EXTRA="--add-module=/var/opt/ngx-cache-purge/"
    elif [ ! -z "${_NGINX_EXTRA_CONF}" ] && [ "${_PURGE_MODE}" = "OFF" ]; then
      _NGINX_EXTRA="${_NGINX_EXTRA_CONF}"
    elif [ ! -z "${_NGINX_EXTRA_CONF}" ] && [ "${_PURGE_MODE}" = "ON" ]; then
      _NGINX_EXTRA="--add-module=/var/opt/ngx-cache-purge/ ${_NGINX_EXTRA_CONF}"
    else
      _NGINX_EXTRA=""
    fi
    if [ -e "/var/opt/nginx-upload-progress-module" ]; then
      _NGINX_EXTRA="--add-module=/var/opt/nginx-upload-progress-module/ $_NGINX_EXTRA"
    fi
    if [ "${_NGINX_LDAP}" = "YES" ]; then
      cd /var/opt
      rm -f -r /var/opt/nginx-auth-ldap*
      get_dev_src "nginx-auth-ldap.tar.gz"
      if [ -e "/var/opt/nginx-auth-ldap" ]; then
        _NGINX_EXTRA="--add-module=/var/opt/nginx-auth-ldap/ $_NGINX_EXTRA"
      fi
    fi
    if [ "${_NGINX_NAXSI}" = "YES" ]; then
      cd /var/opt
      rm -f -r /var/opt/nginx-naxsi*
      get_dev_src "nginx-naxsi.tar.gz"
      if [ -e "/var/opt/nginx-naxsi" ]; then
        _NGINX_EXTRA="--add-module=/var/opt/nginx-naxsi/naxsi_src/ $_NGINX_EXTRA"
      fi
    fi
    if [ "${_NGINX_SPDY}" = "YES" ]; then
      _NGINX_EXTRA="--with-http_spdy_module $_NGINX_EXTRA"
    fi
    cd /var/opt/nginx-${_NGINX_VRN}
    st_runner "sh ./configure \
      --prefix=/usr \
      --sbin-path=/usr/sbin/nginx \
      --conf-path=/etc/nginx/nginx.conf \
      --error-log-path=/var/log/nginx/error.log \
      --http-log-path=/var/log/nginx/access.log \
      --pid-path=/var/run/nginx.pid \
      --lock-path=/var/lock/nginx.lock \
      --user=www-data \
      --group=www-data \
      --with-http_realip_module \
      --with-http_gzip_static_module \
      --with-http_stub_status_module \
      --with-http_ssl_module \
      --with-http_dav_module \
      --with-http_flv_module \
      --with-http_mp4_module \
      --without-mail_pop3_module \
      --without-mail_imap_module \
      --without-mail_smtp_module \
      --without-http_scgi_module \
      --without-http_uwsgi_module \
      --with-ipv6 \
      --with-http_geoip_module \
      --with-debug $_NGINX_EXTRA" 2> /dev/null
    st_runner "make --quiet" 2> /dev/null
    st_runner "make --quiet install" 2> /dev/null
    if [ "${_SQUEEZE_TO_WHEEZY}" = "YES" ] \
      && [ "${_LOC_OSV}" = "squeeze" ]; then
      _DO_NOTHING=YES
    elif [ "${_LENNY_TO_SQUEEZE}" = "YES" ] \
      && [ "${_LOC_OSV}" = "lenny" ]; then
      _DO_NOTHING=YES
    else
      mrun "service nginx stop" &> /dev/null
      killall -9 nginx &> /dev/null
      mrun "service nginx start" &> /dev/null
    fi
    _NGINX_INSTALL_REQUIRED=NO
  fi
  if [ ! -L "/usr/bin/nginx" ]; then
    ln -sf /usr/sbin/nginx /usr/bin/nginx
  fi
}

#
# Fix multi-IP cron access.
fix_multi_ip_cron_access() {
  rm -f /root/.local.IP.list.allow
  for _IP in `cat /root/.local.IP.list \
    | cut -d '#' -f1 \
    | sort \
    | uniq \
    | tr -d "\s"`;do echo "  allow        ${_IP};" >> /root/.local.IP.list.allow;done
  echo "  allow        127.0.0.1;" >> /root/.local.IP.list.allow
  echo "  deny         all;" >> /root/.local.IP.list.allow

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" ${mtrTpl}/Inc/vhost_include.tpl.php
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${mtrTpl}/Inc/vhost_include.tpl.php

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" ${mtrTpl}/subdir.tpl.php
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${mtrTpl}/subdir.tpl.php

  sed -i "s/allow        .*;//g; s/ *$//g; /^$/d" ${mtrInc}/nginx_vhost_common.conf
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${mtrInc}/nginx_vhost_common.conf

  sed -i "s/allow .*;//g; s/ *$//g; /^$/d" ${mtrNgx}/pre.d/nginx_speed_purge.conf
  sed -i '/deny         all;/ {r /root/.local.IP.list.allow
d;};' ${mtrNgx}/pre.d/nginx_speed_purge.conf
}
