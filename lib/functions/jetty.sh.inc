

if_install_solr_jetty() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    msg "PROC: if_install_solr_jetty"
  fi
  if_to_do_fix
  if_hosted_sys
  if [[ "${_XTRAS_LIST}" =~ "SR7" ]] \
    || [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [ "${hostedSys}" = "YES" ]; then
    _R_SOLR="7"
    _N_SOLR="solr${_R_SOLR}"
    _SOLR_VPATH="/var/${_N_SOLR}/data"
    _SOLR_CTRL="/var/${_N_SOLR}/solr-${_SOLR_7_VRN}-version.txt"
    if [ "${_OS_CODE}" = "jessie" ]; then
      if [ -e "/etc/apt/sources.list.d/java8.list" ]; then
        rm -f /etc/apt/sources.list.d/java8.list
      fi
      echo "deb http://archive.debian.org/debian jessie-backports main" > /etc/apt/sources.list.d/backports.list
      echo "Acquire::Check-Valid-Until \"false\";" >> /etc/apt/apt.conf
      apt_clean_update
      st_runner "${_INSTAPP} -t jessie-backports openjdk-8-jre-headless ca-certificates-java" 2> /dev/null
      java_check_fix
    fi
  fi
  if [[ "${_XTRAS_LIST}" =~ "SR7" ]] \
    || [[ "${_XTRAS_LIST}" =~ "ALL" ]] \
    || [ "${hostedSys}" = "YES" ]; then
    if [ ! -d "${_SOLR_VPATH}" ]; then
      echo " "
      tPrmt="Do you want to install MultiCore Apache Solr ${_R_SOLR}"
      tPrmt="${tPrmt} with Jetty ${_R_JETTY}"
      tPrmt=$(echo -n ${tPrmt} | fmt -su -w 2500 2>&1)
      if prompt_yes_no "${tPrmt}?" ; then
        true
        msg "INFO: Installing MultiCore Apache Solr ${_R_SOLR}..."
        cd /var/opt
        curl ${crlGet} "${urlDev}/solr-${_SOLR_7_VRN}.tgz" -o "solr-${_SOLR_7_VRN}.tgz"
        rm -rf solr-${_SOLR_7_VRN}
        adduser --system --group --shell /bin/bash --home /var/${_N_SOLR} ${_N_SOLR} &> /dev/null
        usermod -aG users ${_N_SOLR}
        tar xzf solr-${_SOLR_7_VRN}.tgz solr-${_SOLR_7_VRN}/bin/install_solr_service.sh --strip-components=2
        bash ./install_solr_service.sh solr-${_SOLR_7_VRN}.tgz -f -i /opt -d /var/${_N_SOLR} -u ${_N_SOLR} -s ${_N_SOLR} -p 9077 &> /dev/null
        cp -af ${bldPth}/docs/SOLR.txt ${_SOLR_VPATH}/README.txt &> /dev/null
        echo ${_SOLR_7_VRN} > ${_SOLR_CTRL}
        cd /var/opt
        msg "INFO: MultiCore Apache Solr ${_R_SOLR} installed"
      else
        msg "INFO: MultiCore Apache Solr ${_R_SOLR} not installed"
      fi
    fi
  fi
  if [ -e "/etc/default/${_N_SOLR}.in.sh" ]; then
    _SOLR7_JAVA_TEST=$(grep "BOA ${_X_SE} Path to Java on ${_OS_CODE}" /etc/default/${_N_SOLR}.in.sh 2>&1)
    if [[ "${_SOLR7_JAVA_TEST}" =~ "BOA ${_X_SE} Path to Java on ${_OS_CODE}" ]]; then
      _DO_NOTHING=YES
    else
      sed -i "s/^SOLR_JAVA_HOME=.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "s/^LOG4J_FORMAT_MSG_NO_LOOKUPS=.*//g" /etc/default/${_N_SOLR}.in.sh
      wait
      sed -i "/^$/d" /etc/default/${_N_SOLR}.in.sh
      wait
      echo "LOG4J_FORMAT_MSG_NO_LOOKUPS=true" >> /etc/default/${_N_SOLR}.in.sh
      if [ "${_OS_CODE}" = "jessie" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-8-openjdk/jre\" # BOA ${_X_SE} Path to Java 8" >> \
          /etc/default/${_N_SOLR}.in.sh
      elif [ "${_OS_CODE}" = "stretch" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-8-openjdk/jre\" # BOA ${_X_SE} Path to Java 8" >> \
          /etc/default/${_N_SOLR}.in.sh
      elif [ "${_OS_CODE}" = "buster" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk\" # BOA ${_X_SE} Path to Java 11" >> \
          /etc/default/${_N_SOLR}.in.sh
      elif [ "${_OS_CODE}" = "bullseye" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk\" # BOA ${_X_SE} Path to Java 11" >> \
          /etc/default/${_N_SOLR}.in.sh
      elif [ "${_OS_CODE}" = "bookworm" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk\" # BOA ${_X_SE} Path to Java 11" >> \
          /etc/default/${_N_SOLR}.in.sh
      elif [ "${_OS_CODE}" = "beowulf" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk\" # BOA ${_X_SE} Path to Java 11" >> \
          /etc/default/${_N_SOLR}.in.sh
      elif [ "${_OS_CODE}" = "chimaera" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk\" # BOA ${_X_SE} Path to Java 11" >> \
          /etc/default/${_N_SOLR}.in.sh
      elif [ "${_OS_CODE}" = "daedalus" ]; then
        echo "SOLR_JAVA_HOME=\"/usr/lib/jvm/java-11-openjdk\" # BOA ${_X_SE} Path to Java 11" >> \
          /etc/default/${_N_SOLR}.in.sh
      fi
    fi
    if [ ! -e "${_SOLR_CTRL}" ]; then
      msg "INFO: Upgrading MultiCore Apache Solr ${_R_SOLR}..."
      cd /var/opt
      curl ${crlGet} "${urlDev}/solr-${_SOLR_7_VRN}.tgz" -o "solr-${_SOLR_7_VRN}.tgz"
      rm -rf solr-${_SOLR_7_VRN}
      tar xzf solr-${_SOLR_7_VRN}.tgz solr-${_SOLR_7_VRN}/bin/install_solr_service.sh --strip-components=2
      bash ./install_solr_service.sh solr-${_SOLR_7_VRN}.tgz -f -i /opt -d /var/${_N_SOLR} -u ${_N_SOLR} -s ${_N_SOLR} -p 9077 &> /dev/null
      echo ${_SOLR_7_VRN} > ${_SOLR_CTRL}
      msg "INFO: MultiCore Apache Solr ${_R_SOLR} upgrade completed"
    fi
  fi
  if [ "${_UP_JDK}" = "YES" ] && [ -e "/etc/init.d/${_N_SOLR}" ]; then
    msg "INFO: Solr 7 restart in progress - required after java upgrade"
    mrun "service ${_N_SOLR} restart" 2> /dev/null
    msg "INFO: Solr 7 restart completed"
  fi

  ###--------------------###
  _R_JETTY=9
  _JETTY_CTRL="/opt/jetty9/jetty-ctrl-${_JETTY_9_VRN}-${_SOLR_4_VRN}-version.txt"
  _SOLR_CTRL="/opt/jetty9/solr-${_SOLR_4_VRN}-version.txt"
  if [ -e "/opt/jetty9/start.d/http.ini" ]; then
    _PORT_CTRL="/opt/jetty9/start.d/.fixed.http.ini.txt"
  else
    _PORT_CTRL="${_JETTY_CTRL}"
  fi
  if [[ "${_XTRAS_LIST}" =~ "SR4" ]] \
    || [ "${hostedSys}" = "YES" ]; then
    if [ ! -d "/opt/solr4" ]; then
      _R_JETTY=9
      echo " "
      tPrmt="Do you want to install MultiCore Apache Solr"
      tPrmt="${tPrmt} with Jetty ${_R_JETTY}"
      tPrmt=$(echo -n ${tPrmt} | fmt -su -w 2500 2>&1)
      if prompt_yes_no "${tPrmt}?" ; then
        true
        msg "INFO: Installing MultiCore Apache Solr with Jetty ${_R_JETTY}..."
        cd /var/opt
        rm -rf jetty-distribution-*
        rm -rf /opt/solr4
        rm -rf /opt/jetty9
        rm -f /etc/jetty.conf
        get_dev_arch "jetty-distribution-${_JETTY_9_VRN}.tar.gz"
        mv /var/opt/jetty-distribution-${_JETTY_9_VRN} /opt/jetty9
        echo ${_JETTY_9_VRN} > ${_JETTY_CTRL}
        get_dev_arch "solr-${_SOLR_4_VRN}.tgz"
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
          get_dev_contrib "apachesolr_attachments-7.x-1.x-dev.tar.gz"
          cd /var/opt/solr-${_SOLR_4_VRN}/example/solr/collection1/conf/
          patch -p0 < \
            /var/opt/apachesolr_attachments/solrconfig.tika.patch &> /dev/null
          ln -sfn /opt/jetty9/lib /opt/tika9
          ln -sfn /opt/jetty9/lib /opt/tika
          cd /opt/tika9
          rm -f tika-app*
          _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
          for e in ${_TIKA_V}; do
            wget -q -U iCab ${urlDev}/tika-app-${e}.jar
          done
        fi
        for Dir in `find /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/ \
          -maxdepth 1 -mindepth 1 -type d | grep conf`; do
          if [[ "${Dir}" =~ "/opt/solr4/core" ]]; then
            rm -rf $Dir/*
          fi
          cp -af /var/opt/solr-${_SOLR_4_VRN}/example/solr/collection1/conf/* \
            $Dir/ &> /dev/null
        done
        adduser --system --group --home /opt/solr4 jetty9 &> /dev/null
        if [ ! -e "/opt/solr4/search_api_solr-7.x-1.15.log" ]; then
          cd /var/opt
          rm -rf search_api_solr*
          get_dev_contrib "search_api_solr-7.x-1.15.tar.gz"
          for Dir in `find /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/ \
            -maxdepth 1 -mindepth 1 -type d | grep conf`; do
            cp -af /var/opt/search_api_solr/solr-conf/4.x/* $Dir/ &> /dev/null
          done
          sed -i "s/8983/8099/g" \
            /opt/solr4/core{0,1,2,3,4,5,6,7,8,9}/conf/solrcore.properties &> /dev/null
          touch /opt/solr4/search_api_solr-7.x-1.15.log
        fi
        cp -af ${bldPth}/docs/SOLR.txt /opt/solr4/README.txt &> /dev/null
        cd /var/opt
        get_dev_arch "slf4j-${_SLF4J_VRN}.tar.gz"
        slf4jPth="/var/opt/slf4j-${_SLF4J_VRN}"
        rm -rf /opt/jetty9/lib/ext/*
        cp -af ${slf4jPth}/jcl-over-slf4j*.jar /opt/jetty9/lib/ext/
        cp -af ${slf4jPth}/jul-to-slf4j*.jar   /opt/jetty9/lib/ext/
        cp -af ${slf4jPth}/slf4j-api*.jar      /opt/jetty9/lib/ext/
        cp -af ${slf4jPth}/slf4j-log4j12*.jar  /opt/jetty9/lib/ext/
        get_dev_arch "log4j-${_LOGJ4_VRN}.tar.gz"
        cp -af /var/opt/log4j-${_LOGJ4_VRN}/*.jar /opt/jetty9/lib/ext/
        rm -f /opt/jetty9/lib/ext/*sources.jar
        chown -R jetty9:jetty9 /opt/solr4
        chown -R jetty9:jetty9 /opt/jetty9
        chown -R jetty9:jetty9 /var/log/jetty9
        if [ "${_OS_CODE}" = "jessie" ]; then
          echo "JAVA=/usr/bin/java7 # Path to Java 1.7" > /etc/default/jetty9
          echo "JAVA_HOME=/usr/lib/jvm/java-7-openjdk/jre # Path to Java 1.7" >> \
            /etc/default/jetty9
        else
          echo "JAVA=/usr/bin/java # Path to Java 1.8" > /etc/default/jetty9
          echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk/jre # Path to Java 1.8" >> \
            /etc/default/jetty9
        fi
        echo "NO_START=0 # Start on boot" >> /etc/default/jetty9
        echo "JETTY_HOST=127.0.0.1 # Listen on localhost" >> /etc/default/jetty9
        echo "JETTY_PORT=8099 # Run on this port" >> /etc/default/jetty9
        echo "JETTY_USER=jetty9 # Run as this user" >> /etc/default/jetty9
        echo "JETTY_HOME=/opt/jetty9 # Home directory" >> /etc/default/jetty9
        echo "JETTY_LOGS=/var/log/jetty9 # Logs directory" >> /etc/default/jetty9
        echo "JETTY_RUN=/var/run # Run directory" >> /etc/default/jetty9
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
        mrun "update-rc.d jetty9 defaults" 2> /dev/null
        mrun "service jetty9 start" 2> /dev/null
        echo ${_SOLR_4_VRN} > ${_SOLR_CTRL}
        msg "INFO: MultiCore Apache Solr with Jetty ${_R_JETTY} installed"
      else
        msg "INFO: MultiCore Apache Solr with Jetty ${_R_JETTY} not installed"
      fi
    fi
  fi
  if [ "${_UP_JDK}" = "YES" ] && [ -e "/etc/init.d/jetty9" ]; then
    msg "INFO: Jetty 9 restart in progress - required after java upgrade"
    kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
    mrun "service jetty9 star"t 2> /dev/null
    msg "INFO: Jetty 9 restart completed"
  fi
  if [ -e "/opt/jetty9/VERSION.txt" ]; then
    if [ "${_OS_CODE}" = "jessie" ]; then
      _JETTY9_JAVA_TEST=$(grep "Path to Java 1.7" /etc/default/jetty9 2>&1)
    else
      _JETTY9_JAVA_TEST=$(grep "Path to Java 1.8" /etc/default/jetty9 2>&1)
    fi
    if [[ "${_JETTY9_JAVA_TEST}" =~ "Path to Java" ]]; then
      _DO_NOTHING=YES
    else
      if [ "${_OS_CODE}" = "jessie" ]; then
        echo "JAVA=/usr/bin/java7 # Path to Java 1.7" > /etc/default/jetty9
        echo "JAVA_HOME=/usr/lib/jvm/java-7-openjdk/jre # Path to Java 1.7" >> \
          /etc/default/jetty9
      else
        echo "JAVA=/usr/bin/java8 # Path to Java 1.8" > /etc/default/jetty9
        echo "JAVA_HOME=/usr/lib/jvm/java-8-openjdk/jre # Path to Java 1.8" >> \
          /etc/default/jetty9
      fi
      echo "NO_START=0 # Start on boot" >> /etc/default/jetty9
      echo "JETTY_HOST=127.0.0.1 # Listen on localhost" >> /etc/default/jetty9
      echo "JETTY_PORT=8099 # Run on this port" >> /etc/default/jetty9
      echo "JETTY_USER=jetty9 # Run as this user" >> /etc/default/jetty9
      echo "JETTY_HOME=/opt/jetty9 # Home directory" >> /etc/default/jetty9
      echo "JETTY_LOGS=/var/log/jetty9 # Logs directory" >> /etc/default/jetty9
      echo "JETTY_RUN=/var/run # Run directory" >> /etc/default/jetty9
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
      msg "INFO: Upgrading MultiCore Apache Solr with Jetty ${_R_JETTY}..."
      cd /var/opt
      rm -rf jetty-distribution-*
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      mv -f /opt/jetty9 ${vBs}/jetty9-${_X_SE}-${_X_VERSION}-${_NOW}
      get_dev_arch "jetty-distribution-${_JETTY_9_VRN}.tar.gz"
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
      get_dev_arch "solr-${_SOLR_4_VRN}.tgz"
      cp -af /var/opt/solr-${_SOLR_4_VRN}/dist/solr-${_SOLR_4_VRN}.war \
        /opt/jetty9/webapps/solr.war
      rm -rf /opt/jetty9/solr
      cd /opt/jetty9/lib/
      rm -f tika-app*
      _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
      for e in ${_TIKA_V}; do
        wget -q -U iCab ${urlDev}/tika-app-${e}.jar
      done
      cd /var/opt
      get_dev_arch "slf4j-${_SLF4J_VRN}.tar.gz"
      slf4jPth="/var/opt/slf4j-${_SLF4J_VRN}"
      rm -rf /opt/jetty9/lib/ext/*
      cp -af ${slf4jPth}/jcl-over-slf4j*.jar /opt/jetty9/lib/ext/
      cp -af ${slf4jPth}/jul-to-slf4j*.jar   /opt/jetty9/lib/ext/
      cp -af ${slf4jPth}/slf4j-api*.jar      /opt/jetty9/lib/ext/
      cp -af ${slf4jPth}/slf4j-log4j12*.jar  /opt/jetty9/lib/ext/
      get_dev_arch "log4j-${_LOGJ4_VRN}.tar.gz"
      cp -af /var/opt/log4j-${_LOGJ4_VRN}/*.jar /opt/jetty9/lib/ext/
      rm -f /opt/jetty9/lib/ext/*sources.jar
      chown -R jetty9:jetty9 /opt/jetty9
      mrun "service jetty9 start" 2> /dev/null
      echo ${_SOLR_4_VRN} > ${_SOLR_CTRL}
      msg "INFO: MultiCore Apache Solr with Jetty ${_R_JETTY} upgrade completed"
    fi
  fi

  ###--------------------###
  _JETTY_CTRL="/opt/jetty8/jetty-ctrl-${_JETTY_8_VRN}-${_SOLR_3_VRN}-version.txt"
  _SOLR_CTRL="/opt/jetty8/solr-${_SOLR_3_VRN}-version.txt"
  if [[ "${_XTRAS_LIST}" =~ "SR3" ]]; then
    if [ ! -d "/opt/solr3" ]; then
      echo " "
      tPrmt="Do you want to install MultiCore Apache Solr 3"
      tPrmt="${tPrmt} with Jetty 8"
      tPrmt=$(echo -n ${tPrmt} | fmt -su -w 2500 2>&1)
      if prompt_yes_no "${tPrmt}?" ; then
        true
        msg "INFO: Installing MultiCore Apache Solr 3 with Jetty 8..."
        cd /var/opt
        rm -rf jetty-distribution-*
        rm -rf /opt/solr3
        rm -rf /opt/jetty8
        rm -f /etc/jetty.conf
        get_dev_arch "jetty-distribution-${_JETTY_8_VRN}.tar.gz"
        mv /var/opt/jetty-distribution-${_JETTY_8_VRN} /opt/jetty8
        get_dev_arch "apache-solr-${_SOLR_3_VRN}.tgz"
        cp -af /var/opt/apache-solr-${_SOLR_3_VRN}/dist/apache-solr-${_SOLR_3_VRN}.war \
          /opt/jetty8/webapps/solr.war
        mv -f /var/opt/apache-solr-${_SOLR_3_VRN}/example/multicore \
          /opt/solr3 &> /dev/null
        mkdir -p /opt/solr3/core{0,1,2,3,4,5,6,7,8,9}/conf
        mkdir -p /opt/solr3/core{0,1,2,3,4,5,6,7,8,9}/data
        mkdir -p /var/log/jetty8
        if [ ! -e "/opt/tika8" ]; then
          cd /var/opt
          rm -rf apachesolr_attachments*
          get_dev_contrib "apachesolr_attachments-7.x-1.x-dev.tar.gz"
          cd /var/opt/apache-solr-${_SOLR_3_VRN}/example/solr/conf
          patch -p0 < \
            /var/opt/apachesolr_attachments/solrconfig.tika.patch &> /dev/null
          ln -sfn /opt/jetty8/lib /opt/tika8
          cd /opt/tika8
          rm -f tika-app*
          _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
          for e in ${_TIKA_V}; do
            wget -q -U iCab ${urlDev}/tika-app-${e}.jar
          done
        fi
        for Dir in `find /opt/solr3/core{0,1,2,3,4,5,6,7,8,9}/ \
          -maxdepth 1 -mindepth 1 -type d | grep conf`; do
          if [[ "${Dir}" =~ "/opt/solr3/core" ]]; then
            rm -rf $Dir/*
          fi
          cp -af /var/opt/apache-solr-${_SOLR_3_VRN}/example/solr/conf/* \
            $Dir/ &> /dev/null
        done
        adduser --system --group --home /opt/solr3 jetty8 &> /dev/null
        if [ ! -e "/opt/solr3/search_api_solr-7.x-1.15.log" ]; then
          cd /var/opt
          rm -rf search_api_solr*
          get_dev_contrib "search_api_solr-7.x-1.15.tar.gz"
          for Dir in `find /opt/solr3/core{0,1,2,3,4,5,6,7,8,9}/ \
            -maxdepth 1 -mindepth 1 -type d | grep conf`; do
            cp -af /var/opt/search_api_solr/solr-conf/3.x/* $Dir/ &> /dev/null
          done
          sed -i "s/8983/8088/g" \
            /opt/solr3/core{0,1,2,3,4,5,6,7,8,9}/conf/solrcore.properties &> /dev/null
          touch /opt/solr3/search_api_solr-7.x-1.15.log
        fi
        cp -af ${bldPth}/docs/SOLR.txt /opt/solr3/README.txt &> /dev/null
        chown -R jetty8:jetty8 /opt/solr3
        chown -R jetty8:jetty8 /opt/jetty8
        chown -R jetty8:jetty8 /var/log/jetty8
        echo "JAVA=/usr/bin/java # Path to Java 1.6" > /etc/default/jetty8
        echo "JAVA_HOME=/usr/lib/jvm/java-6-openjdk/jre # Path to Java 1.6" >> \
          /etc/default/jetty8
        echo "NO_START=0 # Start on boot" >> /etc/default/jetty8
        echo "JETTY_HOST=127.0.0.1 # Listen on localhost" >> /etc/default/jetty8
        echo "JETTY_PORT=8088 # Run on this port" >> /etc/default/jetty8
        echo "JETTY_USER=jetty8 # Run as this user" >> /etc/default/jetty8
        echo "JETTY_HOME=/opt/jetty8 # Home directory" >> /etc/default/jetty8
        echo "JETTY_LOGS=/var/log/jetty8 # Logs directory" >> /etc/default/jetty8
        echo "JETTY_RUN=/var/run # Run directory" >> /etc/default/jetty8
        echo "JETTY_PID=\$JETTY_RUN/jetty8.pid # Pid file" >> /etc/default/jetty8
        echo "JAVA_OPTIONS=\"-Xms64m -Xmx128m \
          -Djava.awt.headless=true \
          -Dsolr.solr.home=/opt/solr3 \$JAVA_OPTIONS\" \
          # Options" | fmt -su -w 2500 >> /etc/default/jetty8
        sed -i "s/8080/8088/g" /opt/jetty8/bin/jetty.sh &> /dev/null
        ln -sfn /opt/jetty8/bin/jetty.sh /etc/init.d/jetty8 &> /dev/null
        chmod 755 /etc/init.d/jetty8
        mrun "update-rc.d jetty8 defaults" 2> /dev/null
        mrun "service jetty8 start" 2> /dev/null
        echo ${_JETTY_8_VRN} > ${_JETTY_CTRL}
        echo ${_SOLR_3_VRN}  > ${_SOLR_CTRL}
        msg "INFO: MultiCore Apache Solr 3 with Jetty 8 installed"
      else
        msg "INFO: MultiCore Apache Solr 3 with Jetty 8 installation skipped"
      fi
    fi
  fi
  if [ "${_UP_JDK}" = "YES" ] && [ -e "/etc/init.d/jetty8" ]; then
    msg "INFO: Jetty 8 restart in progress - required after java upgrade"
    kill -9 $(ps aux | grep '[j]etty8' | awk '{print $2}') &> /dev/null
    mrun "service jetty8 start" 2> /dev/null
    msg "INFO: Jetty 8 restart completed"
  fi
  if [ -e "/opt/jetty8/VERSION.txt" ]; then
    if [ ! -e "${_JETTY_CTRL}" ] || [ ! -e "${_SOLR_CTRL}" ]; then
      msg "INFO: Upgrading MultiCore Apache Solr 3 with Jetty 8..."
      cd /var/opt
      rm -rf jetty-distribution-*
      get_dev_arch "jetty-distribution-${_JETTY_8_VRN}.tar.gz"
      kill -9 $(ps aux | grep '[j]etty8' | awk '{print $2}') &> /dev/null
      mv -f /opt/jetty8 ${vBs}/jetty8-${_X_SE}-${_X_VERSION}-${_NOW}
      mv -f /var/opt/jetty-distribution-${_JETTY_8_VRN} /opt/jetty8
      get_dev_arch "apache-solr-${_SOLR_3_VRN}.tgz"
      cp -af /var/opt/apache-solr-${_SOLR_3_VRN}/dist/apache-solr-${_SOLR_3_VRN}.war \
        /opt/jetty8/webapps/solr.war
      rm -rf /opt/jetty8/solr
      cd /opt/jetty8/lib/
      rm -f tika-app*
      _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
      for e in ${_TIKA_V}; do
        wget -q -U iCab ${urlDev}/tika-app-${e}.jar
      done
      cd /var/opt
      chown -R jetty8:jetty8 /opt/jetty8
      mrun "service jetty8 start" 2> /dev/null
      echo ${_JETTY_8_VRN} > ${_JETTY_CTRL}
      echo ${_SOLR_3_VRN}  > ${_SOLR_CTRL}
      msg "INFO: MultiCore Apache Solr 3 with Jetty 8 upgrade completed"
    fi
  fi

  ###--------------------###
  _JETTY_CTRL="/opt/jetty7/jetty-ctrl-${_JETTY_7_VRN}-${_SOLR_1_VRN}-version.txt"
  _SOLR_CTRL="/opt/jetty7/solr-${_SOLR_1_VRN}-version.txt"
  if [[ "${_XTRAS_LIST}" =~ "SR1" ]] || [ "${_TOMCAT_TO_JETTY}" = "YES" ]; then
    if [ ! -d "/opt/solr1" ]; then
      echo " "
      tPrmt="Do you want to install MultiCore Apache Solr 1"
      tPrmt="${tPrmt} with Jetty 7"
      tPrmt=$(echo -n ${tPrmt} | fmt -su -w 2500 2>&1)
      if prompt_yes_no "${tPrmt}?" ; then
        true
        msg "INFO: Installing MultiCore Apache Solr 1 with Jetty 7..."
        cd /var/opt
        rm -rf jetty-distribution-*
        rm -rf /opt/solr1
        rm -rf /opt/jetty7
        rm -f /etc/jetty.conf
        get_dev_arch "jetty-distribution-${_JETTY_7_VRN}.tar.gz"
        mv /var/opt/jetty-distribution-${_JETTY_7_VRN} /opt/jetty7
        get_dev_arch "apache-solr-${_SOLR_1_VRN}.tgz"
        cp -af /var/opt/apache-solr-${_SOLR_1_VRN}/dist/apache-solr-${_SOLR_1_VRN}.war \
          /opt/jetty7/webapps/solr.war
        mv -f /var/opt/apache-solr-${_SOLR_1_VRN}/example/multicore \
          /opt/solr1 &> /dev/null
        mkdir -p /opt/solr1/core{0,1,2,3,4,5,6,7,8,9}/conf
        mkdir -p /opt/solr1/core{0,1,2,3,4,5,6,7,8,9}/data
        mkdir -p /var/log/jetty7
        if [ ! -e "/opt/tika7" ]; then
          cd /var/opt
          rm -rf apachesolr_attachments*
          get_dev_contrib "apachesolr_attachments-7.x-1.x-dev.tar.gz"
          cd /var/opt/apache-solr-${_SOLR_1_VRN}/example/solr/conf
          patch -p0 < \
            /var/opt/apachesolr_attachments/solrconfig.tika.patch &> /dev/null
          ln -sfn /opt/jetty7/lib /opt/tika7
          cd /opt/tika7
          rm -f tika-app*
          _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
          for e in ${_TIKA_V}; do
            wget -q -U iCab ${urlDev}/tika-app-${e}.jar
          done
        fi
        for Dir in `find /opt/solr1/core{0,1,2,3,4,5,6,7,8,9}/ \
          -maxdepth 1 -mindepth 1 -type d | grep conf`; do
          if [[ "${Dir}" =~ "/opt/solr1/core" ]]; then
            rm -rf $Dir/*
          fi
          cp -af /var/opt/apache-solr-${_SOLR_1_VRN}/example/solr/conf/* \
          $Dir/ &> /dev/null
        done
        adduser --system --group --home /opt/solr1 jetty7 &> /dev/null
        if [ ! -e "/opt/solr1/search_api_solr-7.x-1.15.log" ]; then
          cd /var/opt
          rm -rf search_api_solr*
          get_dev_contrib "search_api_solr-7.x-1.15.tar.gz"
          for Dir in `find /opt/solr1/core{0,1,2,3,4,5,6,7,8,9}/ \
            -maxdepth 1 -mindepth 1 -type d | grep conf`; do
            cp -af /var/opt/search_api_solr/solr-conf/1.4/* \
              $Dir/ &> /dev/null
          done
          sed -i "s/8983/8077/g" \
            /opt/solr1/core{0,1,2,3,4,5,6,7,8,9}/conf/solrcore.properties &> /dev/null
          touch /opt/solr1/search_api_solr-7.x-1.15.log
        fi
        cp -af ${bldPth}/docs/SOLR.txt /opt/solr1/README.txt &> /dev/null
        rm -rf /opt/jetty7/solr
        chown -R jetty7:jetty7 /opt/solr1
        chown -R jetty7:jetty7 /opt/jetty7
        chown -R jetty7:jetty7 /var/log/jetty7
        echo "JAVA=/usr/bin/java # Path to Java 1.6" > /etc/default/jetty7
        echo "JAVA_HOME=/usr/lib/jvm/java-6-openjdk/jre # Path to Java 1.6" >> \
          /etc/default/jetty7
        echo "NO_START=0 # Start on boot" >> /etc/default/jetty7
        echo "JETTY_HOST=127.0.0.1 # Listen on localhost" >> /etc/default/jetty7
        echo "JETTY_PORT=8077 # Run on this port" >> /etc/default/jetty7
        echo "JETTY_USER=jetty7 # Run as this user" >> /etc/default/jetty7
        echo "JETTY_HOME=/opt/jetty7 # Home directory" >> /etc/default/jetty7
        echo "JETTY_LOGS=/var/log/jetty7 # Logs directory" >> /etc/default/jetty7
        echo "JETTY_RUN=/var/run # Run directory" >> /etc/default/jetty7
        echo "JETTY_PID=\$JETTY_RUN/jetty7.pid # Pid file" >> /etc/default/jetty7
        echo "JAVA_OPTIONS=\"-Xms64m -Xmx128m \
          -Djava.awt.headless=true \
          -Dsolr.solr.home=/opt/solr1 \$JAVA_OPTIONS\" \
          # Options" | fmt -su -w 2500 >> /etc/default/jetty7
        sed -i "s/8080/8077/g" /opt/jetty7/bin/jetty.sh &> /dev/null
        ln -sfn /opt/jetty7/bin/jetty.sh /etc/init.d/jetty7 &> /dev/null
        chmod 755 /etc/init.d/jetty7
        mrun "update-rc.d jetty7 defaults" 2> /dev/null
        mrun "service jetty7 start" 2> /dev/null
        echo ${_JETTY_7_VRN} > ${_JETTY_CTRL}
        echo ${_SOLR_1_VRN}  > ${_SOLR_CTRL}
        msg "INFO: MultiCore Apache Solr 1 with Jetty 7 installed"
      else
        msg "INFO: MultiCore Apache Solr 1 with Jetty 7 installation skipped"
      fi
    fi
  fi
  if [ "${_UP_JDK}" = "YES" ] && [ -e "/etc/init.d/jetty7" ]; then
    msg "INFO: Jetty 7 restart in progress - required after java upgrade"
    kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
    mrun "service jetty7 start" 2> /dev/null
    msg "INFO: Jetty 7 restart completed"
  fi
  if [ "${_TOMCAT_TO_JETTY}" = "YES" ] \
    && [ -e "/etc/init.d/jetty7" ] \
    && [ -e "/etc/default/tomcat" ] \
    && [ -e "/etc/init.d/tomcat" ]; then
    msg "INFO: Tomcat 6 to Jetty 7 migration for Apache Solr 1 in progress..."
    mrun "service tomcat stop" 2> /dev/null
    mrun "update-rc.d tomcat remove" 2> /dev/null
    mv -f /etc/init.d/tomcat /etc/init.d/offtomcat &> /dev/null
    mv -f /opt/solr1/solr.xml /opt/solr1/vanilla-solr.xml
    mv -f /opt/solr/* /opt/solr1/
    cp -af ${bldPth}/docs/SOLR.txt /opt/solr1/README.txt &> /dev/null
    chown -R jetty7:jetty7 /opt/solr1
    sed -i "s/8077/8080/g" /etc/default/jetty7 &> /dev/null
    sed -i "s/8077/8080/g" \
      /opt/solr1/core{0,1,2,3,4,5,6,7,8,9}/conf/solrcore.properties &> /dev/null
    wait
    sed -i "s/8077/8080/g" \
      /opt/solr1/site_00{1,2,3,4,5,6,7,8,9}/conf/solrcore.properties &> /dev/null
    wait
    sed -i "s/8077/8080/g" \
      /opt/solr1/conf/solrcore.properties &> /dev/null
    msg "INFO: Jetty 7 restart in progress - required after migration from Tomcat"
    kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
    mrun "service jetty7 start" 2> /dev/null
    sed -i "s/^_TOMCAT_TO_JETTY.*//g" ${barCnf}
    wait
    sed -i "/^$/d" ${barCnf}
    wait
    msg "INFO: Tomcat 6 to Jetty 7 migration for Apache Solr 1 completed"
  fi
  if [ -e "/opt/jetty7/VERSION.txt" ]; then
    if [ ! -e "${_JETTY_CTRL}" ] || [ ! -e "${_SOLR_CTRL}" ]; then
      msg "INFO: Upgrading MultiCore Apache Solr 1 with Jetty 7..."
      cd /var/opt
      rm -rf jetty-distribution-*
      get_dev_arch "jetty-distribution-${_JETTY_7_VRN}.tar.gz"
      kill -9 $(ps aux | grep '[j]etty7' | awk '{print $2}') &> /dev/null
      mv -f /opt/jetty7 ${vBs}/jetty7-${_X_SE}-${_X_VERSION}-${_NOW}
      mv -f /var/opt/jetty-distribution-${_JETTY_7_VRN} /opt/jetty7
      get_dev_arch "apache-solr-${_SOLR_1_VRN}.tgz"
      cp -af /var/opt/apache-solr-${_SOLR_1_VRN}/dist/apache-solr-${_SOLR_1_VRN}.war \
        /opt/jetty7/webapps/solr.war
      rm -rf /opt/jetty7/solr
      cd /opt/jetty7/lib/
      rm -f tika-app*
      _TIKA_V="1.8 1.9 1.10 1.11 1.12 1.13 1.20"
      for e in ${_TIKA_V}; do
        wget -q -U iCab ${urlDev}/tika-app-${e}.jar
      done
      cd /var/opt
      chown -R jetty7:jetty7 /opt/jetty7
      mrun "service jetty7 start" 2> /dev/null
      echo ${_JETTY_7_VRN} > ${_JETTY_CTRL}
      echo ${_SOLR_1_VRN}  > ${_SOLR_CTRL}
      msg "INFO: MultiCore Apache Solr 1 with Jetty 7 upgrade completed"
    fi
  fi
}
