
if_install_bzr() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_bzr"
  fi
  if [[ "${_XTRAS_LIST}" =~ "BZR" ]]; then
    _PATH_BZR="/usr/local/bin/bzr"
    if [ ! -e "${_PATH_BZR}" ] \
      || [ ! -e "${pthLog}/bzr-${_BZR_VRN}.log" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      msg "INFO: Building Bazaar (bzr) ${_BZR_VRN} from sources..."
      if [ -e "/usr/local/lib/python2.6/dist-packages/bzrlib" ]; then
        rm -rf /usr/local/lib/python2.6/dist-packages/bzrlib
      fi
      if [ -e "/usr/local/lib/python2.7/dist-packages/bzrlib" ]; then
        rm -rf /usr/local/lib/python2.7/dist-packages/bzrlib
      fi
      if [ -e "/usr/local/lib/python3.11/dist-packages/bzrlib" ]; then
        rm -rf /usr/local/lib/python3.11/dist-packages/bzrlib
      fi
      cd /var/opt
      rm -rf bzr*
      get_dev_src "bzr-${_BZR_VRN}.tar.gz"
      cd /var/opt/bzr-${_BZR_VRN}
      isPythonTwo=$(which python2 2>&1)
      isPythonThree=$(which python3 2>&1)
      if [ -x "${isPythonThree}" ]; then
        usePyth=python3
      elif [ -x "${isPythonTwo}" ]; then
        usePyth=python2
      fi
      mrun "${usePyth} setup.py --quiet install build_ext -\
        -allow-python-fallback" 2> /dev/null
      mrun "make -j $(nproc) --quiet" 2> /dev/null
      touch ${pthLog}/bzr-${_BZR_VRN}.log
      mkdir -p /root/.bazaar
      echo ignore_missing_extensions=True > /root/.bazaar/bazaar.conf
    fi
  fi
}

if_install_adminer() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_adminer"
  fi
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_XTRAS_LIST}" =~ "ADM" ]] \
    || [ -d "/var/www/chive" ]; then
    _ADMINER_VHOST="${mtrNgx}/vhost.d/adminer.${_THIS_FRONT}"
    if [ ! -e "/var/www/adminer/index.php" ] \
      || [ ! -f "${_ADMINER_VHOST}" ] \
      || [ ! -f "${pthLog}/adminer-${_ADMINER_VRN}.log" ]; then
      echo " "
      if prompt_yes_no "Do you want to install Adminer Manager?" ; then
        true
        msg "INFO: Installing Adminer Manager..."
        cd /var/www
        rm -rf /var/www/adminer &> /dev/null
        get_dev_ext "adminer-${_ADMINER_VRN}.tar.gz"
        cd /var/www/adminer
        mv -f adminer-${_ADMINER_VRN}-mysql.php index.php
        validate_public_ip &> /dev/null
        validate_xtras_ip &> /dev/null
        cp -af ${locCnf}/nginx_sql_adminer.conf ${_ADMINER_VHOST}
        sed -i "s/127.0.0.1:80/${_XTRAS_THISHTIP}:80/g"               ${_ADMINER_VHOST}
        wait
        sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g"             ${_ADMINER_VHOST}
        wait
        sed -i "s/adminer_name/adminer.${_THIS_FRONT} ${_THISHTIP}/g" ${_ADMINER_VHOST}
        wait
        touch ${pthLog}/adminer-${_ADMINER_VRN}.log
        msg "INFO: Adminer Manager installed"
      else
        msg "INFO: Adminer Manager installation skipped"
      fi
    fi
  fi
  if [ -d "/var/www/adminer" ]; then
    if [ ! -z "${_PHP_CN}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: _PHP_CN set to ${_PHP_CN} for Adminer Manager"
      fi
      chown -R ${_PHP_CN}:www-data /var/www/adminer
    else
      msg "NOTE: _PHP_CN not set for Adminer Manager"
      chown -R www-data:www-data /var/www/adminer
    fi
    find /var/www/adminer -type d -exec chmod 0755 {} \; &> /dev/null
    find /var/www/adminer -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 0440 /var/www/adminer/index.php
  fi
}

if_install_chive() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_chive"
  fi
  if [[ "${_XTRAS_LIST}" =~ "CHV" ]] || [ -d "/var/www/chive" ]; then
    _CHIVE_VHOST="${mtrNgx}/vhost.d/chive.${_THIS_FRONT}"
    if [ ! -d "/var/www/chive" ] \
      || [ ! -f "${_CHIVE_VHOST}" ] \
      || [ ! -f "${pthLog}/chive-${_CHIVE_VRN}.switch-to-adminer.log" ]; then
      echo " "
      if prompt_yes_no "Do you want to install Chive Manager?" ; then
        true
        msg "INFO: Installing Chive Manager..."
        cd /var/www
        rm -rf /var/www/chive &> /dev/null
        get_dev_arch "chive_${_CHIVE_VRN}.tar.gz"
        validate_public_ip &> /dev/null
        validate_xtras_ip &> /dev/null
        cp -af ${locCnf}/nginx_sql_chive.conf ${_CHIVE_VHOST}
        sed -i "s/127.0.0.1:80/${_XTRAS_THISHTIP}:80/g"    ${_CHIVE_VHOST}
        wait
        sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g"  ${_CHIVE_VHOST}
        wait
        sed -i "s/chive_name/chive.${_THIS_FRONT}/g"       ${_CHIVE_VHOST}
        wait
        touch ${pthLog}/chive-${_CHIVE_VRN}.switch-to-adminer.log
        msg "INFO: Chive Manager installed"
      else
        msg "INFO: Chive Manager installation skipped"
      fi
    fi
  fi
  if [ -d "/var/www/chive" ]; then
    if [ ! -z "${_PHP_CN}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: _PHP_CN set to ${_PHP_CN} for Chive Manager"
      fi
      chown -R ${_PHP_CN}:www-data /var/www/chive
    else
      msg "NOTE: _PHP_CN not set for Chive Manager"
      chown -R www-data:www-data /var/www/chive
    fi
    find /var/www/chive -type d -exec chmod 0775 {} \; &> /dev/null
    find /var/www/chive -type f -exec chmod 0664 {} \; &> /dev/null
  fi
}

if_install_sqlbuddy() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_sqlbuddy"
  fi
  if [[ "${_XTRAS_LIST}" =~ "BDD" ]]; then
    _SQLBUDDY_VHOST="${mtrNgx}/vhost.d/sqlbuddy.${_THIS_FRONT}"
    if [ ! -d "/var/www/sqlbuddy" ] \
      || [ ! -f "${_SQLBUDDY_VHOST}" ] \
      || [ ! -f "${pthLog}/sqlbuddy.fix-dns-vhost-wildcard.log" ]; then
      echo " "
      if prompt_yes_no "Do you want to install SQL Buddy Manager?" ; then
        true
        msg "INFO: Installing SQL Buddy Manager..."
        rm -rf /var/www/sqlbuddy
        cd /var/www
        get_dev_arch "sqlbuddy_1_3_3.tar.gz"
        validate_public_ip &> /dev/null
        validate_xtras_ip &> /dev/null
        cp -af ${locCnf}/nginx_sql_buddy.conf ${_SQLBUDDY_VHOST}
        sed -i "s/127.0.0.1:80/${_XTRAS_THISHTIP}:80/g"   ${_SQLBUDDY_VHOST}
        wait
        sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g" ${_SQLBUDDY_VHOST}
        wait
        sed -i "s/buddy_name/sqlbuddy.${_THIS_FRONT}/g"   ${_SQLBUDDY_VHOST}
        wait
        touch ${pthLog}/sqlbuddy.fix-dns-vhost-wildcard.log
        msg "INFO: SQL Buddy Manager installed"
      else
        msg "INFO: SQL Buddy Manager installation skipped"
      fi
    fi
  fi
  if [ -d "/var/www/sqlbuddy" ]; then
    if [ ! -z "${_PHP_CN}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: _PHP_CN set to ${_PHP_CN} for SQL Buddy Manager"
      fi
      chown -R ${_PHP_CN}:www-data /var/www/sqlbuddy
    else
      msg "NOTE: _PHP_CN not set for SQL Buddy Manager"
      chown -R www-data:www-data /var/www/sqlbuddy
    fi
    find /var/www/sqlbuddy -type d -exec chmod 0775 {} \; &> /dev/null
    find /var/www/sqlbuddy -type f -exec chmod 0664 {} \; &> /dev/null
  fi
}

fix_collectd_rrd_syslog_flood() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_collectd_rrd_syslog_flood"
  fi
  _COLLECTD_CNF="/etc/collectd/collectd.conf"
  if [ -e "${_COLLECTD_CNF}" ]; then
    _COLLECTD_CNF_TEST=$(grep "rootfs" ${_COLLECTD_CNF} 2>&1)
    if [[ "${_COLLECTD_CNF_TEST}" =~ "rootfs" ]]; then
      _DO_NOTHING=YES
    else
      echo "<Plugin df>"                 >> ${_COLLECTD_CNF}
      echo "        FSType \"rootfs\""   >> ${_COLLECTD_CNF}
      echo "        IgnoreSelected true" >> ${_COLLECTD_CNF}
      echo "</Plugin>"                   >> ${_COLLECTD_CNF}
      mrun "service collectd restart" &> /dev/null
    fi
  fi
}
### Credit: http://emacstragic.net/collectd-causing-rrd-illegal-attempt-to-update-using-time-errors/

fix_collectd_nginx() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: fix_collectd_nginx"
  fi
  _COLLECTD_CNF="/etc/collectd/collectd.conf"
  if [ -e "${_COLLECTD_CNF}" ]; then
    _COLLECTD_CNF_TEST=$(grep "^LoadPlugin nginx" ${_COLLECTD_CNF} 2>&1)
    if [[ "${_COLLECTD_CNF_TEST}" =~ "LoadPlugin nginx" ]]; then
      _DO_NOTHING=YES
    else
      echo "<Plugin nginx>"                                >> ${_COLLECTD_CNF}
      echo "        URL \"http://127.0.0.1/nginx_status\"" >> ${_COLLECTD_CNF}
      echo "        VerifyPeer false"                      >> ${_COLLECTD_CNF}
      echo "        VerifyHost false"                      >> ${_COLLECTD_CNF}
      echo "</Plugin>"                                     >> ${_COLLECTD_CNF}
      sed -i "s/^#LoadPlugin nginx/LoadPlugin nginx/g"        ${_COLLECTD_CNF}
      wait
      mrun "service collectd restart" &> /dev/null
    fi
  fi
}

if_install_collectd() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_collectd"
  fi
  if [[ "${_XTRAS_LIST}" =~ "CGP" ]]; then
    _CGP_VHOST="${mtrNgx}/vhost.d/cgp.${_THIS_FRONT}"
    if [ ! -e "/var/run/cloud_vhost.pid" ]; then
      if [ ! -d "/var/www/cgp" ] \
        || [ ! -f "${_CGP_VHOST}" ] \
        || [ ! -f "${pthLog}/cgp-${_CGP_VRN}.fix-dns-vhost-wildcard.log" ]; then
        echo " "
        if prompt_yes_no "Do you want to install Collectd Graph Panel?" ; then
          true
          msg "INFO: Installing Collectd Graph Panel..."
          st_runner "${_INSTAPP} collectd" 2> /dev/null
          rm -rf /var/www/cgp
          cd /var/www
          get_dev_arch "cgp-${_CGP_VRN}.tar.gz"
          if [ -e "/var/www/cgp-${_CGP_VRN}" ]; then
            mv -f cgp-${_CGP_VRN} cgp &> /dev/null
          fi
          sed -i "s/>uncategorized</>Barracuda Server</g" /var/www/cgp/index.php
          wait
          sed -i "s/'uncategorized'/'Barracuda Server'/g" /var/www/cgp/index.php
          wait
          validate_public_ip &> /dev/null
          validate_xtras_ip &> /dev/null
          cp -af ${locCnf}/nginx_sql_cgp.conf ${_CGP_VHOST}
          sed -i "s/127.0.0.1:80/${_XTRAS_THISHTIP}:80/g"    ${_CGP_VHOST}
          wait
          sed -i "s/127.0.0.1:443/${_XTRAS_THISHTIP}:443/g"  ${_CGP_VHOST}
          wait
          sed -i "s/cgp_name/cgp.${_THIS_FRONT}/g"           ${_CGP_VHOST}
          wait
          mrun "update-rc.d collectd defaults" &> /dev/null
          touch ${pthLog}/cgp-${_CGP_VRN}.fix-dns-vhost-wildcard.log
          msg "INFO: Collectd Graph Panel installed"
        else
          msg "INFO: Collectd Graph Panel installation skipped"
        fi
      fi
    fi
  fi
  if [ -d "/var/www/cgp" ] \
    && [ "${_VMFAMILY}" = "VS" ] \
    && [ ! -e "/boot/grub/grub.cfg" ] \
    && [ ! -e "/boot/grub/menu.lst" ]; then
    rm -f ${mtrNgx}/vhost.d/cgp*
    mrun "apt-get remove collectd -y -qq" &> /dev/null
    mrun "apt-get purge collectd -y -qq" &> /dev/null
    rm -rf /var/www/cgp
  fi
  if [ -d "/var/www/cgp" ]; then
    if [ ! -z "${_PHP_CN}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        msg "INFO: _PHP_CN set to ${_PHP_CN} for Collectd Graph Panel"
      fi
      chown -R ${_PHP_CN}:www-data /var/www/cgp
    else
      msg "NOTE: _PHP_CN not set for Collectd Graph Panel"
      chown -R www-data:www-data /var/www/cgp
    fi
    find /var/www/cgp -type d -exec chmod 0775 {} \; &> /dev/null
    find /var/www/cgp -type f -exec chmod 0664 {} \; &> /dev/null
    fix_collectd_rrd_syslog_flood
    fix_collectd_nginx
  fi
}

if_install_hhvm() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_hhvm"
  fi
  if_to_do_fix
  if [[ "${_XTRAS_LIST}" =~ "HVM" ]]; then
    if [ -x "/usr/bin/gpg2" ]; then
      _GPG=gpg2
    else
      _GPG=gpg
    fi
    if [ "${_OSR}" = "buster" ] \
      || [ "${_OSR}" = "stretch" ] \
      || [ "${_OSR}" = "jessie" ] \
      || [ "${_DO_FIX}" = "YES" ]; then
      if [ ! -x "/usr/bin/hhvm" ]; then
        echo " "
        if prompt_yes_no "Do you want to install HHVM Engine?" ; then
          true
          msg "INFO: Installing HHVM Engine..."
          cd /var/opt
          echo "## HHVM APT Repository" > /etc/apt/sources.list.d/hhvm.list
          if [ "${_OSR}" = "jessie" ]; then
            echo "deb http://dl.hhvm.com/debian jessie main" >> \
              /etc/apt/sources.list.d/hhvm.list
          elif [ "${_OSR}" = "stretch" ] || [ "${_DO_FIX}" = "YES" ]; then
            echo "deb http://dl.hhvm.com/debian stretch main" >> \
              /etc/apt/sources.list.d/hhvm.list
          elif [ "${_OSR}" = "buster" ] || [ "${_DO_FIX}" = "YES" ]; then
            echo "deb http://dl.hhvm.com/debian buster main" >> \
              /etc/apt/sources.list.d/hhvm.list
          fi
          _KEYS_SERVER_TEST=FALSE
          until [[ "${_KEYS_SERVER_TEST}" =~ "GnuPG" ]]; do
            rm -f /var/opt/hhvm.gpg.key*
            cd /var/opt
            wget -q -U iCab http://dl.hhvm.com/conf/hhvm.gpg.key
            _KEYS_SERVER_TEST=$(grep GnuPG /var/opt/hhvm.gpg.key 2>&1)
            sleep 2
          done
          cat /var/opt/hhvm.gpg.key | ${_GPG} --import &> /dev/null
          apt_clean_update
          st_runner "apt-get install hhvm ${aptYesUnth}" 2> /dev/null
          msg "INFO: HHVM Engine installed"
        else
          msg "INFO: HHVM Engine installation skipped"
        fi
      fi
    fi
  fi
}

if_install_webmin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_webmin"
  fi
  if [[ "${_XTRAS_LIST}" =~ "WMN" ]]; then
    if [ ! -d "/etc/webmin" ] && [ ! -e "/var/run/cloud_vhost.pid" ]; then
      if [ -x "/usr/bin/gpg2" ]; then
        _GPG=gpg2
      else
        _GPG=gpg
      fi
      echo " "
      if prompt_yes_no "Do you want to install Webmin Control Panel?" ; then
        true
        msg "INFO: Installing Webmin Control Panel..."
        cd /var/opt
        echo "## Webmin APT Repository" > /etc/apt/sources.list.d/webmin.list
        echo "deb http://download.webmin.com/download/repository \
          sarge contrib" | fmt -su -w 2500 >> /etc/apt/sources.list.d/webmin.list
        echo "deb http://webmin.mirror.somersettechsolutions.co.uk/repository \
          sarge contrib" | fmt -su -w 2500 >> /etc/apt/sources.list.d/webmin.list
        _KEYS_SERVER_TEST=FALSE
        until [[ "${_KEYS_SERVER_TEST}" =~ "GnuPG" ]]; do
          rm -f jcameron-key.gpg*
          wget -q -U iCab ${urlDev}/jcameron-key.gpg
          _KEYS_SERVER_TEST=$(grep GnuPG jcameron-key.gpg 2>&1)
          sleep 2
        done
        cat jcameron-key.gpg | ${_GPG} --import &> /dev/null
        rm -f jcameron-key.gpg*
        touch ${pthLog}/webmin_update_apt_src.log
        apt_clean_update
        st_runner "${_INSTAPP} webmin \
                             libxml-simple-perl \
                             libcrypt-ssleay-perl" 2> /dev/null
        update-rc.d webmin defaults &> /dev/null
        msg "INFO: Webmin Control Panel installed"
      else
        msg "INFO: Webmin Control Panel installation skipped"
      fi
    fi
  fi
}

if_install_bind() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_bind"
  fi
  if [[ "${_XTRAS_LIST}" =~ "BND" ]]; then
    if [ ! -e "/usr/sbin/named" ] || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      echo " "
      if prompt_yes_no "Do you want to install Bind9 DNS Server?" ; then
        true
        msg "INFO: Installing Bind9 DNS Server..."
        if [ -z "${_THISHTIP}" ]; then
          _LOC_DOM="${_THISHOST}"
          find_correct_ip
          _THISHTIP="${_LOC_IP}"
        fi
        st_runner "${_INSTAPP} bind9" 2> /dev/null
        cp -af /etc/bind/named.conf.options \
          ${vBs}/named.conf.options.pre-${_X_SE}-${_X_VERSION}-${_NOW}
        cp -af ${locCnf}/named.conf.options /etc/bind/named.conf.options
        sed -i "s/127.0.1.1/${_THISHTIP}/g" /etc/bind/named.conf.options &> /dev/null
        mrun "service bind9 restart" &> /dev/null
        if [ ! -e "/etc/init.d/bind" ]; then
          ln -sfn /etc/init.d/bind9 /etc/init.d/bind
        fi
        sed -i "s/.*bind.*//g" /etc/sudoers &> /dev/null
        wait
        sed -i "/^$/d" /etc/sudoers &> /dev/null
        wait
        msg "INFO: Bind9 DNS Server installed"
      else
        msg "INFO: Bind9 DNS Server installation skipped"
      fi
    fi
  fi
}

if_install_rvm() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_rvm"
  fi
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_XTRAS_LIST}" =~ "CSS" ]] \
    || [ ! -z "${_SCOUT_KEY}" ] \
    || [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".o8.io"($) ]] \
    || [[ "${_THISHOST}" =~ ".aegir.cc"($) ]] \
    || [ -e "/root/.host8.cnf" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      _L_ST="install"
    else
      _L_ST="install"
    fi
    if [ ! -x "/usr/local/rvm/rubies/ruby-${_RUBY_VRN}/bin/gem" ]; then
      echo " "
      if prompt_yes_no "Do you want to ${_L_ST} Ruby with RVM?" ; then
        true
        msg "INFO: Running Ruby with RVM ${_L_ST}..."
        if [ ! -e "${pthLog}/ruby-sys-clean-reload.log" ]; then
          _RUBY_RELOAD=YES
          rm -rf /usr/local/rvm
          touch ${pthLog}/ruby-sys-clean-reload.log
        fi
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          \curl -k -sSL ${urlDev}/mpapis.asc | ${_GPG} --import -
          \curl -k -sSL ${urlDev}/pkuczynski.asc | ${_GPG} --import -
          \curl -k -sSL ${urlHmr}/helpers/rvm-installer-root.sh | bash -s stable
        else
          \curl -k -sSL ${urlDev}/mpapis.asc | ${_GPG} --import - &> /dev/null
          \curl -k -sSL ${urlDev}/pkuczynski.asc | ${_GPG} --import - &> /dev/null
          \curl -k -sSL ${urlHmr}/helpers/rvm-installer-root.sh | bash -s stable &> /dev/null
        fi
        echo rvm_autoupdate_flag=0 > ~/.rvmrc
        wait
        echo rvm_silence_path_mismatch_check_flag=1 >> ~/.rvmrc
        mrun "sleep 5"
        if [ -e "/etc/profile.d/rvm.sh" ]; then
          source /etc/profile.d/rvm.sh
        fi
        isRvm=$(which rvm 2>&1)
        if [ -x "${isRvm}" ]; then
          rvmPth="${isRvm}"
        elif [ -x "/usr/local/rvm/bin/rvm" ]; then
          rvmPth="/usr/local/rvm/bin/rvm"
        else
          rvmPth=""
          msg "WARN: RVM ${_L_ST} failed, so we can't install Ruby!"
        fi
        if [ -x "${rvmPth}" ]; then
          usermod -aG rvm root
          if [ ! -x "/usr/local/rvm/rubies/ruby-${_RUBY_VRN}/bin/gem" ]; then
            _RUBY_UPGRADE=YES
          fi
          if [ -e "/etc/profile.d/rvm.sh" ]; then
            source /etc/profile.d/rvm.sh
          fi
          if [ -x "/bin/websh" ] && [ -L "/bin/sh" ]; then
            _WEB_SH=$(readlink -n /bin/sh 2>&1)
            _WEB_SH=$(echo -n ${_WEB_SH} | tr -d "\n" 2>&1)
            if [ -x "/bin/dash" ] || [ -x "/usr/bin/dash" ]; then
              if [ "${_WEB_SH}" != "/bin/dash" ]; then
                if [ -x "/usr/bin/dash" ]; then
                  if [ -L "/usr/bin/sh" ]; then
                    rm -f /usr/bin/sh
                    ln -s /usr/bin/dash /usr/bin/sh
                  fi
                  if [ -L "/bin/sh" ]; then
                    rm -f /bin/sh
                    ln -s /usr/bin/dash /bin/sh
                  fi
                fi
                if [ -x "/bin/dash" ] && [ ! -L "/bin/dash" ]; then
                  if [ -L "/usr/bin/sh" ]; then
                    rm -f /usr/bin/sh
                    ln -s /bin/dash /usr/bin/sh
                  fi
                  if [ -L "/bin/sh" ]; then
                    rm -f /bin/sh
                    ln -s /bin/dash /bin/sh
                  fi
                fi
              fi
            elif [ -x "/bin/bash" ] || [ -x "/usr/bin/bash" ]; then
              if [ "${_WEB_SH}" != "/bin/bash" ]; then
                if [ -x "/usr/bin/bash" ]; then
                  if [ -L "/usr/bin/sh" ]; then
                    rm -f /usr/bin/sh
                    ln -s /usr/bin/bash /usr/bin/sh
                  fi
                  if [ -L "/bin/sh" ]; then
                    rm -f /bin/sh
                    ln -s /usr/bin/bash /bin/sh
                  fi
                fi
                if [ -x "/bin/bash" ] && [ ! -L "/bin/bash" ]; then
                  if [ -L "/usr/bin/sh" ]; then
                    rm -f /usr/bin/sh
                    ln -s /bin/bash /usr/bin/sh
                  fi
                  if [ -L "/bin/sh" ]; then
                    rm -f /bin/sh
                    ln -s /bin/bash /bin/sh
                  fi
                fi
              fi
            fi
          fi
          touch /var/run/manage_rvm_users.pid
          if [ "${_STATUS}" = "INIT" ] \
            || [ "${_RUBY_UPGRADE}" = "YES" ] \
            || [ "${_RUBY_RELOAD}" = "YES" ]; then
            apt_clean_update
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              ${rvmPth} get stable --auto-dotfiles
              ${rvmPth} install ${_RUBY_VRN}
              ${rvmPth} use ${_RUBY_VRN} --default
              if [ "${_OSR}" = "stretch" ] || [ "${_OSR}" = "jessie" ]; then
                curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -
              else
                curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash -
              fi
              mrun "${_INSTAPP} nodejs"
            else
              ${rvmPth} get stable --auto-dotfiles &> /dev/null
              ${rvmPth} install ${_RUBY_VRN} &> /dev/null
              ${rvmPth} use ${_RUBY_VRN} --default &> /dev/null
              if [ "${_OSR}" = "stretch" ] || [ "${_OSR}" = "jessie" ]; then
                curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash - &> /dev/null
              else
                curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash - &> /dev/null
              fi
              mrun "${_INSTAPP} nodejs" &> /dev/null
            fi
          else
            apt_clean_update
            if [ "${_DEBUG_MODE}" = "YES" ]; then
              ${rvmPth} get stable --auto-dotfiles
              ${rvmPth} install ${_RUBY_VRN}
              ${rvmPth} use ${_RUBY_VRN} --default
              if [ "${_OSR}" = "stretch" ] || [ "${_OSR}" = "jessie" ]; then
                curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -
              else
                curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash -
              fi
              mrun "${_INSTAPP} nodejs"
            else
              ${rvmPth} get stable --auto-dotfiles &> /dev/null
              ${rvmPth} install ${_RUBY_VRN} &> /dev/null
              ${rvmPth} use ${_RUBY_VRN} --default &> /dev/null
              if [ "${_OSR}" = "stretch" ] || [ "${_OSR}" = "jessie" ]; then
                curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash - &> /dev/null
              else
                curl -sL https://deb.nodesource.com/setup_18.x | sudo -E bash - &> /dev/null
              fi
              mrun "${_INSTAPP} nodejs" &> /dev/null
            fi
          fi
          if [ ! -x "/usr/local/rvm/rubies/ruby-${_RUBY_VRN}/bin/gem" ]; then
            msg "WARN: Ruby ${_RUBY_VRN} install failed!"
          fi
          _RBY_FILE="/usr/local/rvm/rubies/ruby-${_RUBY_VRN}/bin/ruby"
          _RBY_PATH=${_RBY_FILE//\//\\\/}
          _GEM_FILE="/usr/local/rvm/gems/ruby-${_RUBY_VRN}@global/bin/scout"
          _GEM_PATH=${_GEM_FILE//\//\\\/}
          _GEM_CRON="/etc/crontab"
          _VAR_IF_PRESENT=$(grep "scout" ${_GEM_CRON} 2>&1)
          if [[ "${_VAR_IF_PRESENT}" =~ "scout" ]]; then
            if [ ! -e "${_GEM_FILE}" ] && [ ! -z "${_SCOUT_KEY}" ]; then
              mrun "${rvmPth} @global do gem install --conservative scout" 2> /dev/null
              adduser --system --group --home /var/scout scout &> /dev/null
              usermod -aG users scout
              sed -i "s/\* \* \* \* \* scout .*/* * * * * scout ${_GEM_PATH} ${_SCOUT_KEY}/g" ${_GEM_CRON} &> /dev/null
            fi
            _VAR_IF_PRESENT=$(grep "scout ALL=NOPASSWD" /etc/sudoers 2>&1)
            if [[ ! "${_VAR_IF_PRESENT}" =~ "scout ALL=NOPASSWD" ]]; then
              echo "scout ALL=NOPASSWD: /usr/bin/mysql" >> /etc/sudoers
            fi
          else
            if [ ! -z "${_SCOUT_KEY}" ]; then
              mrun "${rvmPth} @global do gem install --conservative scout" 2> /dev/null
              adduser --system --group --home /var/scout scout &> /dev/null
              usermod -aG users scout
              echo -e "* * * * * scout ${_GEM_FILE} ${_SCOUT_KEY}" \
                | fmt -su -w 2500 | tee -a ${_GEM_CRON} >/dev/null 2>&1
              _VAR_IF_PRESENT=$(grep "scout ALL=NOPASSWD" /etc/sudoers 2>&1)
              if [[ ! "${_VAR_IF_PRESENT}" =~ "scout ALL=NOPASSWD" ]]; then
                echo "scout ALL=NOPASSWD: /usr/bin/mysql" >> /etc/sudoers
              fi
            fi
          fi
          if [ -e "${_GEM_FILE}" ]; then
            sed -i "s/^#\!\/.*/#\!${_RBY_PATH}/g" ${_GEM_FILE} &> /dev/null
          fi
          PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin;export PATH
          touch ${pthLog}/compass-${_X_SE}-${_X_VERSION}-ruby-${_RUBY_VRN}-nodejs.log
          if [ -x "/usr/local/rvm/rubies/ruby-${_RUBY_VRN}/bin/gem" ]; then
            msg "INFO: Ruby with RVM ${_L_ST} completed"
            [ -e "/var/run/manage_rvm_users.pid" ] && rm -f /var/run/manage_rvm_users.pid
          fi
        fi
      else
        msg "INFO: Ruby with RVM ${_L_ST} skipped"
      fi
      _ID_SHELLS=$(id -nG root 2>&1)
      if [[ ! "${_ID_SHELLS}" =~ "rvm" ]]; then
        isRvm=$(which rvm 2>&1)
        if [ -x "${isRvm}" ]; then
          rvmPth="${isRvm}"
        elif [ -x "/usr/local/rvm/bin/rvm" ]; then
          rvmPth="/usr/local/rvm/bin/rvm"
        fi
        if [ -x "${rvmPth}" ]; then
          usermod -aG rvm root
        fi
      fi
      _ID_SHELLS=""
    fi
  fi
  if [ -e "/var/scout" ]; then
    _SCOUT_CRON_OFF=$(grep "OFFscoutOFF" /etc/crontab 2>&1)
    _SCOUT_CRON=$(grep "scout" /etc/crontab 2>&1)
    if [[ ! "${_SCOUT_CRON_OFF}" =~ "OFFscoutOFF" ]] \
      && [[ "${_SCOUT_CRON}" =~ "scout" ]]; then
      sed -i "s/scout/OFFscoutOFF/g" /etc/crontab &> /dev/null
    fi
  fi
}

magick_install_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: magick_install_upgrade"
  fi
  if [ "${_MAGICK_FROM_SOURCES}" = "YES" ]; then
    install_magick_src
  fi
}

if_install_ffmpeg() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_ffmpeg"
  fi
  if [[ "${_XTRAS_LIST}" =~ "FMG" ]]; then
    if [ ! -x "/usr/bin/ffmpeg" ]; then
      echo " "
      if prompt_yes_no "Do you want to install FFmpeg?" ; then
        true
        msg "INFO: Installing FFmpeg..."
        cd /var/opt
        echo "## deb-multimedia APT Repository for FFmpeg" > /etc/apt/sources.list.d/ffmpeg.list
        if [ "${_OSR}" = "bookworm" ] \
          || [ "${_OSR}" = "bullseye" ] \
          || [ "${_OSR}" = "buster" ] \
          || [ "${_OSR}" = "stretch" ] \
          || [ "${_OSR}" = "jessie" ]; then
          echo "deb http://www.deb-multimedia.org ${_OSR} main non-free" >> /etc/apt/sources.list.d/ffmpeg.list
          echo "deb http://www.deb-multimedia.org ${_OSR}-backports main" >> /etc/apt/sources.list.d/ffmpeg.list
        elif [ "${_OSR}" = "daedalus" ]; then
          echo "deb http://www.deb-multimedia.org bookworm main non-free" >> /etc/apt/sources.list.d/ffmpeg.list
          echo "deb http://www.deb-multimedia.org bookworm-backports main" >> /etc/apt/sources.list.d/ffmpeg.list
        elif [ "${_OSR}" = "chimaera" ]; then
          echo "deb http://www.deb-multimedia.org bullseye main non-free" >> /etc/apt/sources.list.d/ffmpeg.list
          echo "deb http://www.deb-multimedia.org bullseye-backports main" >> /etc/apt/sources.list.d/ffmpeg.list
        elif [ "${_OSR}" = "beowulf" ]; then
          echo "deb http://www.deb-multimedia.org buster main non-free" >> /etc/apt/sources.list.d/ffmpeg.list
          echo "deb http://www.deb-multimedia.org buster-backports main" >> /etc/apt/sources.list.d/ffmpeg.list
        fi
        apt_clean_update
        st_runner "apt-get install deb-multimedia-keyring ${aptYesUnth}" 2> /dev/null
        apt_clean_update
        st_runner "${_INSTAPP} ffmpeg" 2> /dev/null
        msg "INFO: FFmpeg installed"
      else
        msg "INFO: FFmpeg installation skipped"
      fi
    fi
  fi
}
