
_if_fix_solr9_mod() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_fix_solr9_mod"
  fi
  [ ! -e "/opt/solr9/server/modules/ltr.mod" ] && cp -af ${_bldPth}/aegir/conf/solr9/*  /opt/solr9/server/modules/
  chown root:root /opt/solr9/server/modules/*
  chmod 644 /opt/solr9/server/modules/*
}

_if_fix_solr9_permissions() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_fix_solr9_permissions"
  fi
  [ ! -e "/var/solr9" ] && mkdir -p /var/solr9
  [ -L "/var/solr9" ] && chown -R solr9:solr9 /mnt/*/var/solr9
  [ -L "/var/solr9" ] && chmod 750 /mnt/*/var/solr9
  [ -e "/var/solr9" ] && chown -R solr9:solr9 /var/solr9/*
  [ -e "/var/solr9" ] && chmod 750 /var/solr9
}

_if_fix_solr7_permissions() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_fix_solr7_permissions"
  fi
  [ ! -e "/var/solr7" ] && mkdir -p /var/solr7
  [ -L "/var/solr7" ] && chown -R solr7:solr7 /mnt/*/var/solr7
  [ -L "/var/solr7" ] && chmod 750 /mnt/*/var/solr7
  [ -e "/var/solr7" ] && chown -R solr7:solr7 /var/solr7/*
  [ -e "/var/solr7" ] && chmod 750 /var/solr7
}

_if_solr_nine() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_solr_nine"
  fi

  if [ -e "/var/solr9/data" ] && [ -L "/var/solr9" ]; then
      _if_fix_solr9_permissions
      _if_fix_solr9_mod
  fi

  local _R_SOLR="9"
  local _N_SOLR="solr${_R_SOLR}"
  local _SOLR_VPATH="/var/${_N_SOLR}/data"
  local _SOLR_CTRL="/var/${_N_SOLR}/solr-${_SOLR_9_VRN}-version.txt"

  if [ ! -d "${_SOLR_VPATH}" ]; then
    echo " "
    _tPrmt="Do you want to install MultiCore Apache Solr ${_R_SOLR}"
    _tPrmt=$(echo -n ${_tPrmt} | fmt -su -w 2500 2>&1)
    if _prompt_yes_no "${_tPrmt}?" ; then
      true
      _msg "INFO: Installing MultiCore Apache Solr ${_R_SOLR}..."
      cd /var/opt
      curl ${_crlGet} "${_urlDev}/solr-${_SOLR_9_VRN}.tgz" -o "solr-${_SOLR_9_VRN}.tgz"
      rm -rf solr-${_SOLR_9_VRN}
      adduser --system --group --shell /bin/bash --home /var/${_N_SOLR} ${_N_SOLR} &> /dev/null
      usermod -aG users ${_N_SOLR}
      tar xzf solr-${_SOLR_9_VRN}.tgz solr-${_SOLR_9_VRN}/bin/install_solr_service.sh --strip-components=2
      bash ./install_solr_service.sh solr-${_SOLR_9_VRN}.tgz -f -i /opt -d /var/${_N_SOLR} -u ${_N_SOLR} -s ${_N_SOLR} -p 9099 &> /dev/null
      cp -af ${_bldPth}/docs/SOLR.txt ${_SOLR_VPATH}/README.txt &> /dev/null
      echo ${_SOLR_9_VRN} > ${_SOLR_CTRL}
      cd /var/opt
      _if_fix_solr9_permissions
      _if_fix_solr9_mod
      _msg "INFO: MultiCore Apache Solr ${_R_SOLR} installed"
    else
      _msg "INFO: MultiCore Apache Solr ${_R_SOLR} not installed"
    fi
  fi

  if [ -e "/etc/default/${_N_SOLR}.in.sh" ]; then
    if [ "${_OS_CODE}" = "excalibur" ]; then
      _useJava=21
    else
      _useJava=17
    fi
    _SOLR9_JAVA_TEST=$(grep "BOA ${_xSrl} Path to Java ${_useJava} on ${_OS_CODE}" /etc/default/${_N_SOLR}.in.sh 2>&1)
    _SOLR9_MODULES_TEST=$(grep "analysis-extras,clustering,extraction,langid,ltr" /etc/default/${_N_SOLR}.in.sh 2>&1)
    _SOLR9_STOP_TEST=$(grep "SOLR_STOP_PORT=19099" /etc/default/${_N_SOLR}.in.sh 2>&1)
    if [[ "${_SOLR9_JAVA_TEST}" =~ "BOA ${_xSrl} Path to Java ${_useJava} on ${_OS_CODE}" ]] \
      && [[ "${_SOLR9_MODULES_TEST}" =~ "analysis-extras,clustering,extraction,langid,ltr" ]] \
      && [[ "${_SOLR9_STOP_TEST}" =~ "SOLR_STOP_PORT=19099" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/^SOLR_STOP_.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "s/^SOLR_JAVA_HOME=.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "s/^SOLR_MODULES=.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "s/^LOG4J_FORMAT_MSG_NO_LOOKUPS=.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "/^$/d" /etc/default/${_N_SOLR}.in.sh
      wait
      echo "LOG4J_FORMAT_MSG_NO_LOOKUPS=true" >> /etc/default/${_N_SOLR}.in.sh
      echo "SOLR_STOP_PORT=19099" >> /etc/default/${_N_SOLR}.in.sh
      echo "SOLR_STOP_KEY=mycustomkey9" >> /etc/default/${_N_SOLR}.in.sh
      if [ "${_OS_CODE}" = "excalibur" ] \
        || [ "${_OS_CODE}" = "daedalus" ] \
        || [ "${_OS_CODE}" = "chimaera" ]; then
        if [ "${_OS_CODE}" = "excalibur" ]; then
          echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-21-openjdk\" # BOA ${_xSrl} Path to Java 21" >> /etc/default/${_N_SOLR}.in.sh
        else
          echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-17-openjdk\" # BOA ${_xSrl} Path to Java 17" >> /etc/default/${_N_SOLR}.in.sh
        fi
        echo "SOLR_MODULES=\"analysis-extras,clustering,extraction,langid,ltr\" # Auto-Enable Modules" >> /etc/default/${_N_SOLR}.in.sh
      fi
    fi
    if [ ! -e "${_SOLR_CTRL}" ]; then
      _msg "INFO: Upgrading MultiCore Apache Solr ${_R_SOLR}..."
      cd /var/opt
      curl ${_crlGet} "${_urlDev}/solr-${_SOLR_9_VRN}.tgz" -o "solr-${_SOLR_9_VRN}.tgz"
      rm -rf solr-${_SOLR_9_VRN}
      tar xzf solr-${_SOLR_9_VRN}.tgz solr-${_SOLR_9_VRN}/bin/install_solr_service.sh --strip-components=2
      bash ./install_solr_service.sh solr-${_SOLR_9_VRN}.tgz -f -i /opt -d /var/${_N_SOLR} -u ${_N_SOLR} -s ${_N_SOLR} -p 9099 &> /dev/null
      echo ${_SOLR_9_VRN} > ${_SOLR_CTRL}
      _if_fix_solr9_permissions
      _if_fix_solr9_mod
      _msg "INFO: MultiCore Apache Solr ${_R_SOLR} upgrade completed"
    fi
  fi
  if [ "${_UP_JDK}" = "YES" ] && [ -e "/etc/init.d/${_N_SOLR}" ]; then
    _msg "INFO: Solr 9 restart in progress - required after java upgrade"
    _mrun "service ${_N_SOLR} restart"
    _msg "INFO: Solr 9 restart completed"
  fi
}

_if_solr_seven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_solr_seven"
  fi

  if [ -e "/var/solr7/data" ] && [ -L "/var/solr7" ]; then
    _if_fix_solr7_permissions
  fi

  local _R_SOLR="7"
  local _N_SOLR="solr${_R_SOLR}"
  local _SOLR_VPATH="/var/${_N_SOLR}/data"
  local _SOLR_CTRL="/var/${_N_SOLR}/solr-${_SOLR_7_VRN}-version.txt"

  if [ ! -d "${_SOLR_VPATH}" ]; then
    echo " "
    _tPrmt="Do you want to install MultiCore Apache Solr ${_R_SOLR}"
    _tPrmt=$(echo -n ${_tPrmt} | fmt -su -w 2500 2>&1)
    if _prompt_yes_no "${_tPrmt}?" ; then
      true
      _msg "INFO: Installing MultiCore Apache Solr ${_R_SOLR}..."
      cd /var/opt
      curl ${_crlGet} "${_urlDev}/solr-${_SOLR_7_VRN}.tgz" -o "solr-${_SOLR_7_VRN}.tgz"
      rm -rf solr-${_SOLR_7_VRN}
      adduser --system --group --shell /bin/bash --home /var/${_N_SOLR} ${_N_SOLR} &> /dev/null
      usermod -aG users ${_N_SOLR}
      tar xzf solr-${_SOLR_7_VRN}.tgz solr-${_SOLR_7_VRN}/bin/install_solr_service.sh --strip-components=2
      bash ./install_solr_service.sh solr-${_SOLR_7_VRN}.tgz -f -i /opt -d /var/${_N_SOLR} -u ${_N_SOLR} -s ${_N_SOLR} -p 9077 &> /dev/null
      cp -af ${_bldPth}/docs/SOLR.txt ${_SOLR_VPATH}/README.txt &> /dev/null
      echo ${_SOLR_7_VRN} > ${_SOLR_CTRL}
      cd /var/opt
      _if_fix_solr7_permissions
      _msg "INFO: MultiCore Apache Solr ${_R_SOLR} installed"
    else
      _msg "INFO: MultiCore Apache Solr ${_R_SOLR} not installed"
    fi
  fi

  if [ -e "/etc/default/${_N_SOLR}.in.sh" ]; then
    _SOLR7_JAVA_TEST=$(grep "BOA ${_xSrl} Path to Java 11" /etc/default/${_N_SOLR}.in.sh 2>&1)
    _SOLR7_STOP_TEST=$(grep "SOLR_STOP_PORT=17077" /etc/default/${_N_SOLR}.in.sh 2>&1)
    if [[ "${_SOLR7_JAVA_TEST}" =~ "BOA ${_xSrl} Path to Java on ${_OS_CODE}" ]] \
      && [[ "${_SOLR7_STOP_TEST}" =~ "SOLR_STOP_PORT=17077" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/^SOLR_STOP_.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "s/^SOLR_JAVA_HOME=.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "s/^LOG4J_FORMAT_MSG_NO_LOOKUPS=.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "/^$/d" /etc/default/${_N_SOLR}.in.sh
      wait
      echo "LOG4J_FORMAT_MSG_NO_LOOKUPS=true" >> /etc/default/${_N_SOLR}.in.sh
      echo "SOLR_STOP_PORT=17077" >> /etc/default/${_N_SOLR}.in.sh
      echo "SOLR_STOP_KEY=mycustomkey7" >> /etc/default/${_N_SOLR}.in.sh
      echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk\" # BOA ${_xSrl} Path to Java 11" >> /etc/default/${_N_SOLR}.in.sh
    fi
    if [ ! -e "${_SOLR_CTRL}" ]; then
      _msg "INFO: Upgrading MultiCore Apache Solr ${_R_SOLR}..."
      cd /var/opt
      curl ${_crlGet} "${_urlDev}/solr-${_SOLR_7_VRN}.tgz" -o "solr-${_SOLR_7_VRN}.tgz"
      rm -rf solr-${_SOLR_7_VRN}
      tar xzf solr-${_SOLR_7_VRN}.tgz solr-${_SOLR_7_VRN}/bin/install_solr_service.sh --strip-components=2
      bash ./install_solr_service.sh solr-${_SOLR_7_VRN}.tgz -f -i /opt -d /var/${_N_SOLR} -u ${_N_SOLR} -s ${_N_SOLR} -p 9077 &> /dev/null
      echo ${_SOLR_7_VRN} > ${_SOLR_CTRL}
      _if_fix_solr7_permissions
      _msg "INFO: MultiCore Apache Solr ${_R_SOLR} upgrade completed"
    fi
  fi
  if [ "${_UP_JDK}" = "YES" ] && [ -e "/etc/init.d/${_N_SOLR}" ]; then
    _msg "INFO: Solr 7 restart in progress - required after java upgrade"
    _mrun "service ${_N_SOLR} restart"
    _msg "INFO: Solr 7 restart completed"
  fi
}

_if_solr_four() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_solr_four"
  fi

  local _R_JETTY=9
  local _JETTY_CTRL="/opt/jetty9/jetty-ctrl-${_JETTY_9_VRN}-${_SOLR_4_VRN}-version.txt"
  local _SOLR_CTRL="/opt/jetty9/solr-${_SOLR_4_VRN}-version.txt"

  if [ -e "/opt/jetty9/start.d/http.ini" ]; then
    local _PORT_CTRL="/opt/jetty9/start.d/.fixed.http.ini.txt"
  else
    local _PORT_CTRL="${_JETTY_CTRL}"
  fi

  if [ ! -d "/opt/solr4" ]; then
    echo " "
    _tPrmt="Do you want to install MultiCore Apache Solr"
    _tPrmt="${_tPrmt} with Jetty ${_R_JETTY}"
    _tPrmt=$(echo -n ${_tPrmt} | fmt -su -w 2500 2>&1)
    if _prompt_yes_no "${_tPrmt}?" ; then
      true
      _msg "INFO: Installing MultiCore Apache Solr with Jetty ${_R_JETTY}..."
      cd /var/opt
      rm -rf jetty-distribution-*
      rm -rf /opt/solr4
      rm -rf /opt/jetty9
      rm -f /etc/jetty.conf
      _get_dev_arch "jetty-distribution-${_JETTY_9_VRN}.tar.gz"
      mv /var/opt/jetty-distribution-${_JETTY_9_VRN} /opt/jetty9
      echo ${_JETTY_9_VRN} > ${_JETTY_CTRL}
      _get_dev_arch "solr-${_SOLR_4_VRN}.tgz"
      cp -af /var/opt/solr-${_SOLR_4_VRN}/dist/solr-${_SOLR_4_VRN}.war \
        /opt/jetty9/webapps/solr.war
      mv -f /var/opt/solr-${_SOLR_4_VRN}/example/multicore \
        /opt/solr4 &> /dev/null
      mkdir -p /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/conf
      mkdir -p /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/data
      mkdir -p /var/log/jetty9
      if [ ! -e "/opt/tika9" ]; then
        cd /var/opt
        rm -rf apachesolr_attachments*
        _get_dev_contrib "apachesolr_attachments-7.x-1.x-dev.tar.gz"
        cd /var/opt/solr-${_SOLR_4_VRN}/example/solr/collection1/conf/
        patch -p0 < \
          /var/opt/apachesolr_attachments/solrconfig.tika.patch &> /dev/null
        ln -sfn /opt/jetty9/lib /opt/tika9
        ln -sfn /opt/jetty9/lib /opt/tika
        cd /opt/tika9
        rm -f tika-app*
        _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
        for e in ${_TIKA_V}; do
          wget ${_wgetGet} ${_urlDev}/tika-app-${e}.jar
        done
      fi
      for _Dir in `find /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/ \
        -maxdepth 1 -mindepth 1 -type d | grep conf`; do
        if [[ "${_Dir}" =~ "/opt/solr4/core" ]]; then
          rm -rf ${_Dir}/*
        fi
        cp -af /var/opt/solr-${_SOLR_4_VRN}/example/solr/collection1/conf/* \
          ${_Dir}/ &> /dev/null
      done
      adduser --system --group --home /opt/solr4 jetty9 &> /dev/null
      if [ ! -e "/opt/solr4/search_api_solr-7.x-1.17.log" ]; then
        cd /var/opt
        rm -rf search_api_solr*
        _get_dev_contrib "search_api_solr-7.x-1.17.tar.gz"
        for _Dir in `find /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/ \
          -maxdepth 1 -mindepth 1 -type d | grep conf`; do
          cp -af /var/opt/search_api_solr/solr-conf/4.x/* ${_Dir}/ &> /dev/null
        done
        sed -i "s/8983/8099/g" \
          /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/conf/solrcore.properties &> /dev/null
        touch /opt/solr4/search_api_solr-7.x-1.17.log
      fi
      cp -af ${_bldPth}/docs/SOLR.txt /opt/solr4/README.txt &> /dev/null
      cd /var/opt
      _get_dev_arch "slf4j-${_SLF4J_VRN}.tar.gz"
      _slf4jPth="/var/opt/slf4j-${_SLF4J_VRN}"
      rm -rf /opt/jetty9/lib/ext/*
      cp -af ${_slf4jPth}/jcl-over-slf4j*.jar /opt/jetty9/lib/ext/
      cp -af ${_slf4jPth}/jul-to-slf4j*.jar   /opt/jetty9/lib/ext/
      cp -af ${_slf4jPth}/slf4j-api*.jar      /opt/jetty9/lib/ext/
      cp -af ${_slf4jPth}/slf4j-log4j12*.jar  /opt/jetty9/lib/ext/
      _get_dev_arch "log4j-${_LOGJ4_VRN}.tar.gz"
      cp -af /var/opt/log4j-${_LOGJ4_VRN}/*.jar /opt/jetty9/lib/ext/
      rm -f /opt/jetty9/lib/ext/*sources.jar
      chown -R jetty9:jetty9 /opt/solr4
      chown -R jetty9:jetty9 /opt/jetty9
      chown -R jetty9:jetty9 /var/log/jetty9
      echo "JAVA=/usr/bin/java # Path to Java 1.8" > /etc/default/jetty9
      echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk/jre # Path to Java 1.8" >> \
        /etc/default/jetty9
      echo "NO_START=0 # Start on boot" >> /etc/default/jetty9
      echo "JETTY_HOST=127.0.0.1 # Listen on localhost" >> /etc/default/jetty9
      echo "JETTY_PORT=8099 # Run on this port" >> /etc/default/jetty9
      echo "JETTY_USER=jetty9 # Run as this user" >> /etc/default/jetty9
      echo "JETTY_HOME=/opt/jetty9 # Home directory" >> /etc/default/jetty9
      echo "JETTY_LOGS=/var/log/jetty9 # Logs directory" >> /etc/default/jetty9
      echo "JETTY_RUN=/run # Run directory" >> /etc/default/jetty9
      echo "JETTY_PID=\$JETTY_RUN/jetty9.pid # Pid file" >> /etc/default/jetty9
      echo "JAVA_OPTIONS=\"-Xms64m -Xmx128m -Djava.awt.headless=true \
        -Dsolr.solr.home=/opt/solr4 \$JAVA_OPTIONS\" \
        # Options" | fmt -su -w 2500 >> /etc/default/jetty9
      if [ -e "/opt/jetty9/start.d/http.ini" ]; then
        sed -i "s/8080/8099/g" /opt/jetty9/start.d/http.ini &> /dev/null
        touch /opt/jetty9/start.d/.fixed.http.ini.txt &> /dev/null
      fi
      if [ -e "/opt/jetty9/start.ini" ]; then
        sed -i "s/8080/8099/g" /opt/jetty9/start.ini &> /dev/null
        touch /opt/jetty9/.fixed.start.ini.txt &> /dev/null
      fi
      sed -i "s/8080/8099/g" /opt/jetty9/bin/jetty.sh &> /dev/null
      ln -sfn /opt/jetty9/bin/jetty.sh /etc/init.d/jetty9 &> /dev/null
      chmod 755 /etc/init.d/jetty9
      _mrun "update-rc.d jetty9 defaults"
      _mrun "service jetty9 start"
      echo ${_SOLR_4_VRN} > ${_SOLR_CTRL}
      _msg "INFO: MultiCore Apache Solr with Jetty ${_R_JETTY} installed"
    else
      _msg "INFO: MultiCore Apache Solr with Jetty ${_R_JETTY} not installed"
    fi
  fi

  if [ "${_UP_JDK}" = "YES" ] && [ -e "/etc/init.d/jetty9" ]; then
    _msg "INFO: Jetty 9 restart in progress - required after java upgrade"
    pkill -9 -f jetty9
    _mrun "service jetty9 start"
    _msg "INFO: Jetty 9 restart completed"
  fi

  if [ -e "/opt/jetty9/VERSION.txt" ]; then
    _JETTY9_JAVA_TEST=$(grep "Path to Java 1.8" /etc/default/jetty9 2>&1)
    if [[ "${_JETTY9_JAVA_TEST}" =~ "Path to Java 1.8" ]]; then
      _DO_NOTHING=YES
    else
      echo "JAVA=/usr/bin/java8 # Path to Java 1.8" > /etc/default/jetty9
      echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk/jre # Path to Java 1.8" >> \
        /etc/default/jetty9
      echo "NO_START=0 # Start on boot" >> /etc/default/jetty9
      echo "JETTY_HOST=127.0.0.1 # Listen on localhost" >> /etc/default/jetty9
      echo "JETTY_PORT=8099 # Run on this port" >> /etc/default/jetty9
      echo "JETTY_USER=jetty9 # Run as this user" >> /etc/default/jetty9
      echo "JETTY_HOME=/opt/jetty9 # Home directory" >> /etc/default/jetty9
      echo "JETTY_LOGS=/var/log/jetty9 # Logs directory" >> /etc/default/jetty9
      echo "JETTY_RUN=/run # Run directory" >> /etc/default/jetty9
      echo "JETTY_PID=\$JETTY_RUN/jetty9.pid # Pid file" >> /etc/default/jetty9
      echo "JAVA_OPTIONS=\"-Xms64m -Xmx128m \
        -Djava.awt.headless=true \
        -Dsolr.solr.home=/opt/solr4 \$JAVA_OPTIONS\" \
        # Options" | fmt -su -w 2500 >> /etc/default/jetty9
    fi
    if [ ! -e "${_PORT_CTRL}" ] \
      || [ ! -e "/opt/jetty9/lib/ext/slf4j-api-${_SLF4J_VRN}.jar" ] \
      || [ ! -e "/opt/jetty9/.fixed.start.ini.txt" ] \
      || [ ! -e "/opt/jetty9/lib/tika-app-1.8.jar" ] \
      || [ ! -e "/opt/jetty9/lib/ext/log4j-1.2.17.jar" ] \
      || [ ! -e "${_JETTY_CTRL}" ] \
      || [ ! -e "${_SOLR_CTRL}" ]; then
      _msg "INFO: Upgrading MultiCore Apache Solr with Jetty ${_R_JETTY}..."
      cd /var/opt
      rm -rf jetty-distribution-*
      pkill -9 -f jetty9
      mv -f /opt/jetty9 ${_vBs}/jetty9-${_xSrl}-${_X_VERSION}-${_NOW}
      _get_dev_arch "jetty-distribution-${_JETTY_9_VRN}.tar.gz"
      mv /var/opt/jetty-distribution-${_JETTY_9_VRN} /opt/jetty9
      echo ${_JETTY_9_VRN} > ${_JETTY_CTRL}
      if [ -e "/opt/jetty9/start.d/http.ini" ]; then
        sed -i "s/8080/8099/g" /opt/jetty9/start.d/http.ini &> /dev/null
        touch /opt/jetty9/start.d/.fixed.http.ini.txt &> /dev/null
      fi
      if [ -e "/opt/jetty9/start.ini" ]; then
        sed -i "s/8080/8099/g" /opt/jetty9/start.ini &> /dev/null
        touch /opt/jetty9/.fixed.start.ini.txt &> /dev/null
      fi
      sed -i "s/8080/8099/g" /opt/jetty9/bin/jetty.sh &> /dev/null
      _get_dev_arch "solr-${_SOLR_4_VRN}.tgz"
      cp -af /var/opt/solr-${_SOLR_4_VRN}/dist/solr-${_SOLR_4_VRN}.war \
        /opt/jetty9/webapps/solr.war
      rm -rf /opt/jetty9/solr
      cd /opt/jetty9/lib/
      rm -f tika-app*
      _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
      for e in ${_TIKA_V}; do
        wget ${_wgetGet} ${_urlDev}/tika-app-${e}.jar
      done
      cd /var/opt
      _get_dev_arch "slf4j-${_SLF4J_VRN}.tar.gz"
      _slf4jPth="/var/opt/slf4j-${_SLF4J_VRN}"
      rm -rf /opt/jetty9/lib/ext/*
      cp -af ${_slf4jPth}/jcl-over-slf4j*.jar /opt/jetty9/lib/ext/
      cp -af ${_slf4jPth}/jul-to-slf4j*.jar   /opt/jetty9/lib/ext/
      cp -af ${_slf4jPth}/slf4j-api*.jar      /opt/jetty9/lib/ext/
      cp -af ${_slf4jPth}/slf4j-log4j12*.jar  /opt/jetty9/lib/ext/
      _get_dev_arch "log4j-${_LOGJ4_VRN}.tar.gz"
      cp -af /var/opt/log4j-${_LOGJ4_VRN}/*.jar /opt/jetty9/lib/ext/
      rm -f /opt/jetty9/lib/ext/*sources.jar
      chown -R jetty9:jetty9 /opt/jetty9
      _mrun "service jetty9 start"
      echo ${_SOLR_4_VRN} > ${_SOLR_CTRL}
      _msg "INFO: MultiCore Apache Solr with Jetty ${_R_JETTY} upgrade completed"
    fi
  fi
}

_if_install_upgrade_solr() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _if_install_upgrade_solr"
  fi
  _if_to_do_fix
  _if_hosted_sys

  if [ "${_OS_CODE}" != "excalibur" ]; then
    if [[ "${_XTRAS_LIST}" =~ "SR4" ]] \
      || [ -e "/opt/solr4/solr.xml" ]; then
      _if_solr_four
    fi
    if [[ "${_XTRAS_LIST}" =~ "SR7" ]] \
      || [ -e "/var/solr7/logs/solr.log" ]; then
      _if_solr_seven
    fi
  fi
  if [[ "${_XTRAS_LIST}" =~ "SR9" ]] \
    || [ ! -e "/var/solr9/logs/solr.log" ] \
    || [ "${_hostedSys}" = "YES" ]; then
    _if_solr_nine
  fi
}
