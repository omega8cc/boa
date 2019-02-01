
if_install_bzr() {
  if [[ "${_XTRAS_LIST}" =~ "BZR" ]]; then
    _PATH_BZR="/usr/local/bin/bzr"
    if [ ! -e "$_PATH_BZR" ] \
      || [ ! -e "${pthLog}/bzr-${_BZR_VRN}.log" ] \
      || [ "${_FULL_FORCE_REINSTALL}" = "YES" ]; then
      msg "INFO: Building Bazaar (bzr) ${_BZR_VRN} from sources, please wait..."
      if [ -e "/usr/local/lib/python2.6/dist-packages/bzrlib" ]; then
        rm -rf /usr/local/lib/python2.6/dist-packages/bzrlib
      fi
      if [ -e "/usr/local/lib/python2.7/dist-packages/bzrlib" ]; then
        rm -rf /usr/local/lib/python2.7/dist-packages/bzrlib
      fi
      cd /var/opt
      rm -rf bzr*
      get_dev_src "bzr-${_BZR_VRN}.tar.gz"
      cd /var/opt/bzr-${_BZR_VRN}
      mrun "python setup.py --quiet install build_ext -\
        -allow-python-fallback" 2> /dev/null
      mrun "make --quiet" 2> /dev/null
      touch ${pthLog}/bzr-${_BZR_VRN}.log
      mkdir -p /root/.bazaar
      echo ignore_missing_extensions=True > /root/.bazaar/bazaar.conf
    fi
  fi
}

if_install_adminer() {
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
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] || [[ "${_XTRAS_LIST}" =~ "CGP" ]]; then
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
  if [ "${_JESSIE_TO_STRETCH}" = "YES" ] \
    && [ "${_LOC_OSV}" = "jessie" ]; then
    _DO_FIX=YES
  fi
  if [[ "${_XTRAS_LIST}" =~ "HVM" ]]; then
    if [ -x "/usr/bin/gpg2" ]; then
      _GPG=gpg2
    else
      _GPG=gpg
    fi
    if [ "${_OSV}" = "jessie" ] \
      || [ "${_OSV}" = "stretch" ] \
      || [ "${_OSV}" = "trusty" ] \
      || [ "${_DO_FIX}" = "YES" ]; then
      if [ ! -x "/usr/bin/hhvm" ]; then
        echo " "
        if prompt_yes_no "Do you want to install HHVM Engine?" ; then
          true
          msg "INFO: Installing HHVM Engine..."
          cd /var/opt
          echo "## HHVM APT Repository" > ${aptLiSys}.d/hhvm.list
          if [ "${_OSV}" = "jessie" ]; then
            echo "deb http://dl.hhvm.com/debian jessie main" >> \
              ${aptLiSys}.d/hhvm.list
          elif [ "${_OSV}" = "stretch" ] || [ "${_DO_FIX}" = "YES" ]; then
            echo "deb http://dl.hhvm.com/debian stretch main" >> \
              ${aptLiSys}.d/hhvm.list
          elif [ "${_OSV}" = "trusty" ]; then
            echo "deb http://dl.hhvm.com/ubuntu trusty main" >> \
              ${aptLiSys}.d/hhvm.list
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
          rm -f /etc/apt/sources.list.d/openssl.list
          st_runner "apt-get update -qq" &> /dev/null
          st_runner "apt-get install hhvm ${forCer}" 2> /dev/null
          msg "INFO: HHVM Engine installed"
        else
          msg "INFO: HHVM Engine installation skipped"
        fi
      fi
    fi
  fi
}

if_install_webmin() {
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] || [[ "${_XTRAS_LIST}" =~ "WMN" ]]; then
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
        echo "## Webmin APT Repository" > ${aptLiSys}.d/webmin.list
        echo "deb http://download.webmin.com/download/repository \
          sarge contrib" | fmt -su -w 2500 >> ${aptLiSys}.d/webmin.list
        echo "deb http://webmin.mirror.somersettechsolutions.co.uk/repository \
          sarge contrib" | fmt -su -w 2500 >> ${aptLiSys}.d/webmin.list
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
        rm -f /etc/apt/sources.list.d/openssl.list
        st_runner "apt-get update -qq" &> /dev/null
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
  _CHECK_OS=$(grep "Ubuntu.*LTS" /etc/issue.net 2>&1)
  if [[ "${_CHECK_OS}" =~ "Ubuntu" ]]; then
    _CHECK_OS=ULTS
  else
    _CHECK_OS=OTHER
  fi
  if [[ "${_XTRAS_LIST}" =~ "BND" ]] && [ "${_CHECK_OS}" = "OTHER" ]; then
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
          ${vBs}/named.conf.options.pre-${_X_VERSION}-${_NOW}
        cp -af ${locCnf}/named.conf.options /etc/bind/named.conf.options
        sed -i "s/127.0.1.1/${_THISHTIP}/g" /etc/bind/named.conf.options &> /dev/null
        mrun "service bind9 restart" &> /dev/null
        if [ ! -e "/etc/init.d/bind" ]; then
          ln -sf /etc/init.d/bind9 /etc/init.d/bind
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
  if [ -x "/usr/bin/gpg2" ]; then
    _GPG=gpg2
  else
    _GPG=gpg
  fi
  if [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [[ "${_XTRAS_LIST}" =~ "CSS" ]] \
    || [ ! -z "${_SCOUT_KEY}" ] \
    || [[ "${_THISHOST}" =~ ".host8." ]] \
    || [[ "${_THISHOST}" =~ ".boa.io" ]] \
    || [ -e "/root/.host8.cnf" ] \
    || [ "${_VMFAMILY}" = "VS" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      _L_ST="install"
    else
      _L_ST="upgrade"
    fi
    if [ ! -e "${pthLog}/compass-${_X_VERSION}-ruby-${_RUBY_VRN}-nodejs.log" ]; then
      echo " "
      if prompt_yes_no "Do you want to ${_L_ST} Ruby with RVM for root?" ; then
        true
        msg "INFO: Running Ruby with RVM ${_L_ST}..."
        if [ ! -e "${pthLog}/ruby-root-clean-reload.log" ]; then
          _RUBY_RELOAD=YES
          rm -rf /usr/local/rvm
          touch ${pthLog}/ruby-root-clean-reload.log
        fi
        _KEYS_SIG="409B6B1796C275462A1703113804BB82D39DC0E3"
        _KEYS_SERVER_TEST=FALSE
        until [[ "${_KEYS_SERVER_TEST}" =~ "Michal Papis" ]]; do
          echo "Retrieving ${_KEYS_SIG} key.."
          ${_GPG} --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "${_KEYS_SIG}" &> /dev/null
          ${_GPG} --export "${_KEYS_SIG}" > /etc/apt/trusted.gpg.d/${_KEYS_SIG}.gpg &> /dev/null
          _KEYS_SERVER_TEST=$(${_GPG} --list-keys "${_KEYS_SIG}" 2>&1)
          sleep 2
        done
        _KEYS_SIG="7D2BAF1CF37B13E2069D6956105BD0E739499BDB"
        _KEYS_SERVER_TEST=FALSE
        until [[ "${_KEYS_SERVER_TEST}" =~ "Piotr Kuczynski" ]]; do
          echo "Retrieving ${_KEYS_SIG} key.."
          ${_GPG} --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "${_KEYS_SIG}" &> /dev/null
          ${_GPG} --export "${_KEYS_SIG}" > /etc/apt/trusted.gpg.d/${_KEYS_SIG}.gpg &> /dev/null
          _KEYS_SERVER_TEST=$(${_GPG} --list-keys "${_KEYS_SIG}" 2>&1)
          sleep 2
        done
        _KEYS_SIG=""
        _KEYS_SERVER_TEST=FALSE
        curl -sSL https://rvm.io/mpapis.asc | ${_GPG} --import - &> /dev/null
        curl -sSL https://rvm.io/pkuczynski.asc | ${_GPG} --import - &> /dev/null
        curl -sSL https://get.rvm.io | bash -s stable &> /dev/null
        echo rvm_autoupdate_flag=0 > ~/.rvmrc
        echo rvm_silence_path_mismatch_check_flag=1 >> ~/.rvmrc
        if [ -e "/etc/profile.d/rvm.sh" ]; then
          source /etc/profile.d/rvm.sh
        fi
        if [ ! -x "/usr/local/rvm/rubies/ruby-${_RUBY_VRN}/bin/gem" ]; then
          _RUBY_UPGRADE=YES
        fi
        if [ "${_STATUS}" = "INIT" ] \
          || [ "$_RUBY_UPGRADE" = "YES" ] \
          || [ "$_RUBY_RELOAD" = "YES" ]; then
          rm -f /etc/apt/sources.list.d/openssl.list
          mrun "apt-get update -qq" &> /dev/null
          mrun "apt-get remove rubygems \
                               ruby1.9.1-dev \
                               libruby1.9.1 \
                               ruby1.9.1 \
                               -y -qq" &> /dev/null
          mrun "rvm install ${_RUBY_VRN}" &> /dev/null
          mrun "rvm use ${_RUBY_VRN} --default" &> /dev/null
          mrun "rvm get stable" 2> /dev/null
          mrun "rvm @global do gem update -q" 2> /dev/null
          curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash - &> /dev/null
          mrun "${_INSTALL} nodejs" 2> /dev/null
        else
          mrun "rvm get stable" 2> /dev/null
          mrun "rvm @global do gem update -q" 2> /dev/null
          curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash - &> /dev/null
          mrun "${_INSTALL} nodejs" 2> /dev/null
        fi
        _RBY_FILE="/usr/local/rvm/rubies/ruby-${_RUBY_VRN}/bin/ruby"
        _RBY_PATH=${_RBY_FILE//\//\\\/}
        _GEM_FILE="/usr/local/rvm/gems/ruby-${_RUBY_VRN}@global/bin/scout"
        _GEM_PATH=${_GEM_FILE//\//\\\/}
        _GEM_CRON="/etc/crontab"
        _VAR_IF_PRESENT=$(grep "scout" $_GEM_CRON 2>&1)
        if [[ "${_VAR_IF_PRESENT}" =~ "scout" ]]; then
          if [ ! -e "$_GEM_FILE" ] && [ ! -z "${_SCOUT_KEY}" ]; then
            mrun "rvm @global do gem install --conservative scout" 2> /dev/null
            adduser --system --group --home /var/scout scout &> /dev/null
            usermod -aG users scout &> /dev/null
            sed -i "s/\* \* \* \* \* scout .*/* * * * * scout $_GEM_PATH ${_SCOUT_KEY}/g" $_GEM_CRON &> /dev/null
          fi
          _VAR_IF_PRESENT=$(grep "scout ALL=NOPASSWD" /etc/sudoers 2>&1)
          if [[ ! "${_VAR_IF_PRESENT}" =~ "scout ALL=NOPASSWD" ]]; then
            echo "scout ALL=NOPASSWD: /usr/bin/mysql" >> /etc/sudoers
          fi
        else
          if [ ! -z "${_SCOUT_KEY}" ]; then
            mrun "rvm @global do gem install --conservative scout" 2> /dev/null
            adduser --system --group --home /var/scout scout &> /dev/null
            usermod -aG users scout &> /dev/null
            echo -e "* * * * * scout $_GEM_FILE ${_SCOUT_KEY}" \
              | fmt -su -w 2500 | tee -a $_GEM_CRON >/dev/null 2>&1
            _VAR_IF_PRESENT=$(grep "scout ALL=NOPASSWD" /etc/sudoers 2>&1)
            if [[ ! "${_VAR_IF_PRESENT}" =~ "scout ALL=NOPASSWD" ]]; then
              echo "scout ALL=NOPASSWD: /usr/bin/mysql" >> /etc/sudoers
            fi
          fi
        fi
        if [ -e "$_GEM_FILE" ]; then
          sed -i "s/^#\!\/.*/#\!$_RBY_PATH/g" $_GEM_FILE &> /dev/null
        fi
        PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin;export PATH
        touch ${pthLog}/compass-${_X_VERSION}-ruby-${_RUBY_VRN}-nodejs.log
        msg "INFO: Ruby with RVM ${_L_ST} for root completed"
      else
        msg "INFO: Ruby with RVM ${_L_ST} for root skipped"
      fi
    fi
  fi
  if [ -e "/var/scout" ]; then
    _SCOUT_CRON_OFF=$(grep "OFFscoutOFF" /etc/crontab 2>&1)
    _SCOUT_CRON=$(grep "scout" /etc/crontab 2>&1)
    if [[ ! "${_SCOUT_CRON_OFF}" =~ "OFFscoutOFF" ]] \
      && [[ "$_SCOUT_CRON" =~ "scout" ]]; then
      sed -i "s/scout/OFFscoutOFF/g" /etc/crontab &> /dev/null
    fi
  fi
}

if_install_magick() {
  if [ "${_MAGICK_FROM_SOURCES}" = "YES" ]; then
    install_magick_src
  fi
}

if_install_ffmpeg() {
  if [[ "${_XTRAS_LIST}" =~ "FMG" ]]; then
    if [ ! -x "/usr/bin/ffmpeg" ]; then
      echo " "
      if prompt_yes_no "Do you want to install FFmpeg?" ; then
        true
        msg "INFO: Installing FFmpeg..."
        cd /var/opt
        if [ "${_OSV}" = "jessie" ] || [ "${_OSV}" = "stretch" ]; then
          echo "## deb-multimedia APT Repository for FFmpeg" > ${aptLiSys}.d/ffmpeg.list
          if [ "${_OSV}" = "jessie" ]; then
            echo "deb http://www.deb-multimedia.org jessie main non-free" >> ${aptLiSys}.d/ffmpeg.list
            echo "deb http://www.deb-multimedia.org jessie-backports main" >> ${aptLiSys}.d/ffmpeg.list
          elif [ "${_OSV}" = "stretch" ]; then
            echo "deb http://www.deb-multimedia.org stretch main non-free" >> ${aptLiSys}.d/ffmpeg.list
            echo "deb http://www.deb-multimedia.org stretch-backports main" >> ${aptLiSys}.d/ffmpeg.list
          fi
          st_runner "apt-get update -qq" &> /dev/null
          st_runner "apt-get install deb-multimedia-keyring ${forCer}" 2> /dev/null
          st_runner "apt-get update -qq" &> /dev/null
          st_runner "${_INSTAPP} ffmpeg" 2> /dev/null
        elif [ "${_OSV}" = "trusty" ] || [ "${_OSV}" = "precise" ]; then
          _X86_64_TEST=$(uname -m 2>&1)
          rm -rf ffmpeg*
          if [ "${_X86_64_TEST}" = "x86_64" ]; then
            SYSTEMARCH="x86_64"
            msg "INFO: Installing ffmpeg ${SYSTEMARCH}..."
            curl ${crlGet} "http://johnvansickle.com/ffmpeg/releases/ffmpeg-release-64bit-static.tar.xz" -o "ffmpeg-release-64bit-static.tar.xz"
            unxz "ffmpeg-release-64bit-static.tar.xz"
            mkdir ffmpeg-release-64bit-static
            tar -xf ffmpeg-release-64bit-static.tar --strip-components 1 -C ffmpeg-release-64bit-static
            cd ffmpeg-release-64bit-static
          else
            SYSTEMARCH="x86"
            msg "INFO: Installing ffmpeg ${SYSTEMARCH}..."
            curl ${crlGet} "http://johnvansickle.com/ffmpeg/releases/ffmpeg-release-32bit-static.tar.xz" -o "ffmpeg-release-32bit-static.tar.xz"
            unxz "ffmpeg-release-32bit-static.tar.xz"
            mkdir ffmpeg-release-32bit-static
            tar -xf ffmpeg-release-32bit-static.tar --strip-components 1 -C ffmpeg-release-32bit-static
            cd ffmpeg-release-32bit-static
          fi
          chown root:root {ffmpeg,ffmpeg-10bit,ffprobe,ffserver,qt-faststart}
          chmod 755 {ffmpeg,ffmpeg-10bit,ffprobe,ffserver,qt-faststart}
          cp -af {ffmpeg,ffmpeg-10bit,ffprobe,ffserver,qt-faststart} /usr/bin/
          cd /var/opt
        fi
        msg "INFO: FFmpeg installed"
      else
        msg "INFO: FFmpeg installation skipped"
      fi
    fi
  fi
}
