#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=lts
export _xSrl=585ltsT00

[ -e "/root/.proxy.cnf" ] && exit 0

_crlGet="-L --max-redirs 3 -k -s --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 --no-check-certificate -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_vSet="variable-set --always-set"

###-------------SYSTEM-----------------###

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_check_config_diff() {
  # $1 is template path
  # $2 is a path to core config
  _preCnf="$1"
  _slrCnf="$2"
  if [ -f "${_preCnf}" ] && [ -f "${_slrCnf}" ]; then
    _slrCnfUpdate=NO
    _diffMyTest=$(diff -w -B ${_slrCnf} ${_preCnf} 2>&1)
    if [ -z "${_diffMyTest}" ]; then
      _slrCnfUpdate=""
      echo "INFO: ${_slrCnf} diff0 empty -- nothing to update"
    else
      _slrCnfUpdate=YES
      # _diffMyTest=$(echo -n ${_diffMyTest} | fmt -su -w 2500)
      echo "INFO: ${_slrCnf} diff1 ${_diffMyTest}"
    fi
  fi
}

_write_solr_config() {
  # ${1} is module
  # ${2} is a path to solr.php
  # ${3} is Jetty/Solr version
  if [ ! -z "${1}" ] \
    && [ ! -z "${2}" ] \
    && [ ! -z "${3}" ] \
    && [ ! -z "${_SolrCoreID}" ] \
    && [ -e "${_Dir}" ]; then
    if [ "${3}" = "solr9" ]; then
      _PRT="9099"
      _VRS="9.8.1"
    elif [ "${3}" = "solr7" ]; then
      _PRT="9077"
      _VRS="7.7.3"
    else
      _PRT="8099"
      _VRS="4.9.1"
    fi
    if [ "${1}" = "search_api_solr" ] || [ "${1}" = "search_api_solr7" ] || [ "${1}" = "search_api_solr9" ]; then
      _module=search_api_solr
    fi
    echo "Your SOLR core access details for ${_Dom} site are as follows:" > ${2}
    echo                                                                 >> ${2}
    echo "  Drupal 8 and newer"                                          >> ${2}
    echo "  Solr version .....: ${_VRS}"                                 >> ${2}
    echo "  Solr host ........: 127.0.0.1"                               >> ${2}
    echo "  Solr port ........: ${_PRT}"                                 >> ${2}
    echo "  Solr path ........: leave empty"                             >> ${2}
    echo "  Solr core ........: ${_SolrCoreID}"                          >> ${2}
    echo                                                                 >> ${2}
    echo "  Don't forget to manually upload the configuration files"     >> ${2}
    echo "  (schema.xml, solrconfig.xml) under ${_Dom}/files/solr"       >> ${2}
    echo                                                                 >> ${2}
    if [ "${3}" != "solr9" ]; then
      echo "  Drupal 7:"                                                 >> ${2}
      echo "  Solr version .....: ${_VRS}"                               >> ${2}
      echo "  Solr host ........: 127.0.0.1"                             >> ${2}
      echo "  Solr port ........: ${_PRT}"                               >> ${2}
      echo "  Solr path ........: /solr/${_SolrCoreID}"                  >> ${2}
      echo                                                               >> ${2}
    fi
    echo "It has been auto-configured to work with latest version"       >> ${2}
    echo "of your integration module, but you need to add the module "   >> ${2}
    echo "to your site codebase before you will be able to use Solr."    >> ${2}
    echo                                                                 >> ${2}
    echo "To learn more please make sure to check the module docs at:"   >> ${2}
    echo                                                                 >> ${2}
    echo "https://drupal.org/project/${_module}"                         >> ${2}
    chown ${_HM_U}:users ${2} &> /dev/null
    chmod 440 ${2} &> /dev/null
  fi
}

_reload_core_cnf() {
  # ${1} is solr server port
  # ${2} is solr core name
  # Example: _reload_core_cnf 9077 ${_SolrCoreID}
  # Example: _reload_core_cnf 9099 ${_SolrCoreID}
  # Example: _reload_core_cnf 8099 ${_SolrCoreID}
  curl "http://127.0.0.1:${1}/solr/admin/cores?action=RELOAD&core=${2}" &> /dev/null
  echo "Reloaded Solr core ${2} cnf on port ${1}"
  wait
}

_update_solr() {
  # ${1} is module
  # ${2} is solr core path (auto) == _SOLR_DIR
  # ${3} is solr server version: solr9 or solr7 or jetty9
  _SERV="${3}"
  if [ ! -z "${1}" ] && [ -e "/data/conf/solr" ]; then
    if [ "${1}" = "apachesolr" ]; then
      _SERV="jetty9"
      if [ -e "${_Plr}/modules/o_contrib_seven" ]; then
        if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ]; then
          _slrCnfUpdate=""
          _check_config_diff "/data/conf/solr/apachesolr/solr4_drupal7/schema.xml" "${2}/conf/schema.xml"
          if [ ! -z "${_slrCnfUpdate}" ]; then
            rm -f ${2}/conf/*
            cp -af /data/conf/solr/apachesolr/solr4_drupal7/* ${2}/conf/
            chmod 644 ${2}/conf/*
            chown ${_SERV}:${_SERV} ${2}/conf/*
            touch ${2}/conf/.just-updated.pid
          else
            rm -f ${2}/conf/.just-updated.pid
            rm -f ${2}/conf/.yes-update.txt
          fi
        fi
      elif [ -e "${_Plr}/modules/o_contrib" ]; then
        if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ]; then
          _slrCnfUpdate=""
          _check_config_diff "/data/conf/solr/apachesolr/solr4_drupal6/schema.xml" "${2}/conf/schema.xml"
          if [ ! -z "${_slrCnfUpdate}" ]; then
            rm -f ${2}/conf/*
            cp -af /data/conf/solr/apachesolr/solr4_drupal6/* ${2}/conf/
            chmod 644 ${2}/conf/*
            chown ${_SERV}:${_SERV} ${2}/conf/*
            touch ${2}/conf/.just-updated.pid
          else
            rm -f ${2}/conf/.just-updated.pid
            rm -f ${2}/conf/.yes-update.txt
          fi
        fi
      fi
    elif [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ] && [ -e "${_Plr}/modules/o_contrib_seven" ]; then
      if [ "${1}" = "search_api_solr" ] || [ "${1}" = "search_api_solr7" ]; then
        _check_config_diff "/data/conf/solr/search_api_solr/solr7_drupal7/schema.xml" "${2}/conf/schema.xml"
        if [ ! -z "${_slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/solr7_drupal7/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown ${_SERV}:${_SERV} ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
        _check_config_diff "/data/conf/solr/search_api_solr/solr7_drupal7/solrcore.properties" "${2}/conf/solrcore.properties"
        if [ ! -z "${_slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/solr7_drupal7/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown ${_SERV}:${_SERV} ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
      fi
    elif [ ! -e "${_Plr}/modules/o_contrib_seven" ] \
      && [ ! -e "${_Plr}/modules/o_contrib" ] \
      && [ ! -e "${2}/conf/.protected.conf" ] \
      && [ -e "${2}/conf" ] \
      && [ -e "${_Plr}/sites/${_Dom}/files/solr/schema.xml" ] \
      && [ -e "${_Plr}/sites/${_Dom}/files/solr/solrconfig.xml" ] \
      && [ -e "${_Plr}/sites/${_Dom}/files/solr/solrcore.properties" ]; then
      if [ "${1}" = "search_api_solr" ] || [ "${1}" = "search_api_solr7" ] || [ "${1}" = "search_api_solr9" ]; then
        _check_config_diff "${_Plr}/sites/${_Dom}/files/solr/solrconfig.xml" "${2}/conf/solrconfig.xml"
        if [ ! -z "${_slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af ${_Plr}/sites/${_Dom}/files/solr/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown ${_SERV}:${_SERV} ${2}/conf/*
          rm -f ${_Plr}/sites/${_Dom}/files/solr/*
          touch ${2}/conf/.yes-custom.txt
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
      fi
    elif [ "${1}" = "search_api_solr" ] \
      && [ -e "${_Plr}/modules/o_contrib_eight" ] \
      && [ ! -e "${_Plr}/sites/${_Dom}/files/solr/schema.xml" ]; then
      if [ ! -e "${2}/conf/.protected.conf" ] \
        && [ ! -e "${2}/conf/.yes-custom.txt" ] \
        && [ -e "${2}/conf" ]; then
        _check_config_diff "/data/conf/solr/search_api_solr/solr7_drupal8/schema.xml" "${2}/conf/schema.xml"
        if [ ! -z "${_slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/solr7_drupal8/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown ${_SERV}:${_SERV} ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
        _check_config_diff "/data/conf/solr/search_api_solr/solr7_drupal8/solrcore.properties" "${2}/conf/solrcore.properties"
        if [ ! -z "${_slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/solr7_drupal8/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown ${_SERV}:${_SERV} ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
      fi
    fi
    _fiLe="${_Dir}/solr.php"
    echo "Info file for ${_Dom} is ${_fiLe}"
    echo "Info _SERV is ${_SERV}"
    _SOLR_CONFIG_INFO_UPDATE=NO
    if [ -e "${_fiLe}" ]; then
      _SOLR_CONFIG_INFO_TEST=$(grep "${_SolrCoreID}" ${_fiLe} 2>&1)
      if [[ ! "${_SOLR_CONFIG_INFO_TEST}" =~ "${_SolrCoreID}" ]]; then
        _SOLR_CONFIG_INFO_UPDATE=YES
      fi
    fi
    if [ ! -e "${_fiLe}" ] \
      || [ "${_SOLR_CONFIG_INFO_UPDATE}" = "YES" ] \
      || [ -e "${2}/conf/.just-updated.pid" ]; then
      if [[ "${2}" =~ "/opt/solr4" ]] && [ "${_SERV}" = "jetty9" ]; then
        _write_solr_config ${1} ${_fiLe} ${_SERV}
        echo "Updated ${_fiLe} with ${2} details"
        touch ${2}/conf/${_xSrl}.conf
        _reload_core_cnf 8099 ${_SolrCoreID}
      elif [[ "${2}" =~ "/var/solr7/data" ]] && [ "${_SERV}" = "solr7" ]; then
        _write_solr_config ${1} ${_fiLe} ${_SERV}
        echo "Updated ${_fiLe} with ${2} details"
        touch ${2}/conf/${_xSrl}.conf
        _reload_core_cnf 9077 ${_SolrCoreID}
      elif [[ "${2}" =~ "/var/solr9/data" ]] && [ "${_SERV}" = "solr9" ]; then
        _write_solr_config ${1} ${_fiLe} ${_SERV}
        echo "Updated ${_fiLe} with ${2} details"
        touch ${2}/conf/${_xSrl}.conf
        _reload_core_cnf 9099 ${_SolrCoreID}
      fi
    fi
  fi
}

_add_solr() {
  # ${1} is module
  # ${2} is solr core path
  # ${3} is solr core version: solr9, solr7, jetty9
  if [ "${1}" = "apachesolr" ]; then
    _SOLR_BASE="/opt/solr4"
    _SOLR_VER=jetty9
  elif [ "${1}" = "search_api_solr" ]; then
    _SOLR_BASE="/var/solr7/data"
    _SOLR_VER=solr7
  elif [ "${1}" = "search_api_solr7" ]; then
    _SOLR_BASE="/var/solr7/data"
    _SOLR_VER=solr7
  elif [ "${1}" = "search_api_solr9" ]; then
    _SOLR_BASE="/var/solr9/data"
    _SOLR_VER=solr9
  fi

  echo in _add_solr _SolrCoreID is ${_SolrCoreID}
  echo in _add_solr _SOLR_BASE is ${_SOLR_BASE}
  echo in _add_solr _SOLR_VER is ${_SOLR_VER}

  if [ ! -z "${1}" ] && [ ! -z "${2}" ] && [ -e "/data/conf/solr" ]; then
    if [ ! -e "${2}" ]; then
      if [ "${_SOLR_BASE}" = "/var/solr9/data" ] \
        && [ -x "/opt/solr9/bin/solr" ] \
        && [ -e "/var/solr9/data" ]; then
        if [ -e "${_Plr}/modules/o_contrib_ten" ] \
          || [ -e "${_Plr}/modules/o_contrib_eleven" ]; then
          echo in _add_solr create_core -p 9099 -c ${_SolrCoreID}
          su -s /bin/bash - solr9 -c "/opt/solr9/bin/solr create_core -p 9099 -c ${_SolrCoreID}"
          wait
        else
          echo "The Solr 9 is supported only for Drupal 10.2 and newer!"
        fi
      elif [ "${_SOLR_BASE}" = "/var/solr7/data" ] \
        && [ -x "/opt/solr7/bin/solr" ] \
        && [ -e "/var/solr7/data" ]; then
        if [ -e "${_Plr}/modules/o_contrib_seven" ]; then
          echo in _add_solr o_contrib_seven create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID} -d /data/conf/solr/search_api_solr/solr7_drupal7"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_eight" ]; then
          echo in _add_solr o_contrib_eight create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_nine" ]; then
          echo in _add_solr o_contrib_nine create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_ten" ]; then
          echo in _add_solr o_contrib_ten create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        elif [ -e "${_Plr}/modules/o_contrib_eleven" ]; then
          echo in _add_solr o_contrib_eleven create_core -p 9077 -c ${_SolrCoreID}
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${_SolrCoreID}"
          wait
        else
          echo "The Solr 7 is supported only for Drupal 7 and newer!"
        fi
      elif [ "${_SOLR_BASE}" = "/opt/solr4" ]; then
        echo in _add_solr solr4 create ${_SolrCoreID}
        rm -rf ${_SOLR_BASE}/core0/data/*
        cp -a ${_SOLR_BASE}/core0 ${2}
        sed -i "s/.*name=\"${_Legacy_SolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "s/.*name=\"${_Old_SolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "s/.*<core name=\"core0\" instan_ceDir=\"core0\" \/>.*/<core name=\"core0\" instan_ceDir=\"core0\" \/>\n<core name=\"${_SolrCoreID}\" instan_ceDir=\"${_SolrCoreID}\" \/>\n/g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "/^$/d" ${_SOLR_BASE}/solr.xml &> /dev/null
        wait
        pkill -9 -f jetty9
        service jetty9 start &> /dev/null
      fi
      echo "New Solr ${3} with ${1} for ${2} added"
    fi
    _update_solr "${1}" "${2}" "${3}"
  fi
}

_delete_solr() {
  # ${1} is solr core path
  if [[ "${1}" =~ "solr4" ]]; then
    _SOLR_BASE="/opt/solr4"
  elif [[ "${1}" =~ "solr7" ]]; then
    _SOLR_BASE="/var/solr7/data"
  elif [[ "${1}" =~ "solr9" ]]; then
    _SOLR_BASE="/var/solr9/data"
  fi
  if [ ! -z "${1}" ] && [ -e "/data/conf/solr" ] && [ -e "${1}/conf" ]; then
    if [ "${_SOLR_BASE}" = "/var/solr9/data" ] \
      && [ -x "/opt/solr9/bin/solr" ] \
      && [ -e "/var/solr9/data/solr.xml" ]; then
      if [ -e "${_SOLR_BASE}/${_SolrCoreID}" ]; then
        su -s /bin/bash - solr9 -c "/opt/solr9/bin/solr delete -p 9099 -c ${_SolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Old_SolrCoreID}" ]; then
        su -s /bin/bash - solr9 -c "/opt/solr9/bin/solr delete -p 9099 -c ${_Old_SolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Legacy_SolrCoreID}" ]; then
        su -s /bin/bash - solr9 -c "/opt/solr9/bin/solr delete -p 9099 -c ${_Legacy_SolrCoreID}"
        wait
      fi
      rm -f ${_Dir}/solr.php
    elif [ "${_SOLR_BASE}" = "/var/solr7/data" ] \
      && [ -x "/opt/solr7/bin/solr" ] \
      && [ -e "/var/solr7/data/solr.xml" ]; then
      if [ -e "${_SOLR_BASE}/${_SolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${_SolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Old_SolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${_Old_SolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${_Legacy_SolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${_Legacy_SolrCoreID}"
        wait
      fi
      rm -f ${_Dir}/solr.php
    elif [ "${_SOLR_BASE}" = "/opt/solr4" ]; then
      sed -i "s/.*instan_ceDir=\"${_SolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
      wait
      sed -i "s/.*name=\"${_Legacy_SolrCoreID}\".*//g"  ${_SOLR_BASE}/solr.xml
      wait
      sed -i "s/.*name=\"${_Old_SolrCoreID}\".*//g"     ${_SOLR_BASE}/solr.xml
      wait
      sed -i "/^$/d" ${_SOLR_BASE}/solr.xml &> /dev/null
      wait
      rm -rf ${1}
      rm -f ${_Dir}/solr.php
      pkill -9 -f jetty9
      service jetty9 start &> /dev/null
    fi
    echo "Deleted Solr core in ${1}"
  fi
}

_check_solr() {
  # ${1} is module
  # ${2} is solr core path
  # ${3} is solr server version
  if [ ! -z "${1}" ] && [ ! -z "${2}" ] && [ ! -z "${3}" ] && [ -e "/data/conf/solr" ]; then
    echo "Checking Solr ${3} with ${1} for ${2}"
    if [ ! -e "${2}" ]; then
      _add_solr "${1}" "${2}" "${3}"
    else
      _update_solr "${1}" "${2}" "${3}"
    fi
  fi
}

_setup_solr() {
  if [ -e "/data/conf/default.boa_site_control.ini" ] \
    && [ ! -e "${_DIR_CTRL_F}" ]; then
    cp -af /data/conf/default.boa_site_control.ini ${_DIR_CTRL_F} &> /dev/null
    chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
    chmod 0664 ${_DIR_CTRL_F} &> /dev/null
  fi
  ###
  ### Support for solr_integration_module directive
  ###
  if [ -e "${_DIR_CTRL_F}" ]; then
    _SOLR_MODULE="your_module_name_here"
    _SOLR_IM_PT=$(grep "solr_integration_module" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SOLR_IM_PT}" =~ "solr_integration_module" ]]; then
      _DO_NOTHING=YES
    else
      echo ";solr_integration_module = your_module_name_here" >> ${_DIR_CTRL_F}
    fi
    _ASOLR_T=$(grep "^solr_integration_module = apachesolr" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_ASOLR_T}" =~ "apachesolr" ]]; then
      _SOLR_MODULE="apachesolr"
    fi
    _SAPI_SOLR_T=$(grep "^solr_integration_module = search_api_solr" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SAPI_SOLR_T}" =~ "search_api_solr" ]]; then
      _SOLR_MODULE="search_api_solr"
    fi
    _SAPI_SOLR_U=$(grep "^solr_integration_module = search_api_solr7" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SAPI_SOLR_U}" =~ "search_api_solr7" ]]; then
      _SOLR_MODULE="search_api_solr7"
    fi
    _SAPI_SOLR_V=$(grep "^solr_integration_module = search_api_solr9" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SAPI_SOLR_V}" =~ "search_api_solr9" ]]; then
      _SOLR_MODULE="search_api_solr9"
    fi
    if [ "${_SOLR_MODULE}" = "apachesolr" ] && [ -e "/opt/solr4" ]; then
      _SOLR_BASE="/opt/solr4"
      _SOLR_VER=jetty9
    elif [ "${_SOLR_MODULE}" = "search_api_solr" ] && [ -e "/var/solr7/data" ]; then
      _SOLR_BASE="/var/solr7/data"
      _SOLR_VER=solr7
    elif [ "${_SOLR_MODULE}" = "search_api_solr7" ] && [ -e "/var/solr7/data" ]; then
      _SOLR_BASE="/var/solr7/data"
      _SOLR_VER=solr7
    elif [ "${_SOLR_MODULE}" = "search_api_solr9" ] && [ -e "/var/solr9/data" ]; then
      _SOLR_BASE="/var/solr9/data"
      _SOLR_VER=solr9
    else
      _SOLR_MODULE=
      _SOLR_BASE=
      _SOLR_VER=
    fi
    _SOLR_DIR="${_SOLR_BASE}/${_SolrCoreID}"
    if [ "${_SOLR_MODULE}" = "search_api_solr" ] \
      || [ "${_SOLR_MODULE}" = "search_api_solr7" ] \
      || [ "${_SOLR_MODULE}" = "search_api_solr9" ] \
      || [ "${_SOLR_MODULE}" = "apachesolr" ]; then
      [ -n "${_SOLR_VER}" ] && _check_solr "${_SOLR_MODULE}" "${_SOLR_DIR}" "${_SOLR_VER}"
    else
      if [ -n "${_SOLR_VER}" ]; then
        _SOLR_DIR_DEL="/opt/solr4/${_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr7/data/${_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr9/data/${_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/opt/solr4/${_Legacy_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr7/data/${_Legacy_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/opt/solr4/${_Old_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr7/data/${_Old_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
        _SOLR_DIR_DEL="/var/solr9/data/${_Old_SolrCoreID}"
        _delete_solr "${_SOLR_DIR_DEL}"
      fi
    fi
  fi
  ###
  ### Support for solr_custom_config directive
  ###
  if [ -e "${_DIR_CTRL_F}" ]; then
    _SLR_CM_CFG_P=$(grep "solr_custom_config" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SLR_CM_CFG_P}" =~ "solr_custom_config" ]]; then
      _DO_NOTHING=YES
    else
      echo ";solr_custom_config = NO" >> ${_DIR_CTRL_F}
    fi
    _SLR_CM_CFG_RT=NO
    _SOLR_PROTECT_CTRL="${_SOLR_DIR}/conf/.protected.conf"
    _SLR_CM_CFG_T=$(grep "^solr_custom_config = YES" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SLR_CM_CFG_T}" =~ "solr_custom_config = YES" ]]; then
      _SLR_CM_CFG_RT=YES
      if [ ! -e "${_SOLR_PROTECT_CTRL}" ]; then
        touch ${_SOLR_PROTECT_CTRL}
      fi
      echo "Solr config for ${_SOLR_DIR} is protected"
    else
      if [ -e "${_SOLR_PROTECT_CTRL}" ]; then
        rm -f ${_SOLR_PROTECT_CTRL}
      fi
    fi
  fi
  ###
  ### Support for solr_update_config directive
  ###
  if [ -e "${_DIR_CTRL_F}" ]; then
    _SOLR_UP_CFG_PT=$(grep "solr_update_config" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SOLR_UP_CFG_PT}" =~ "solr_update_config" ]]; then
      _DO_NOTHING=YES
    else
      echo ";solr_update_config = NO" >> ${_DIR_CTRL_F}
    fi
    _SOLR_UP_CFG_TT=$(grep "^solr_update_config = YES" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SOLR_UP_CFG_TT}" =~ "solr_update_config = YES" ]]; then
      if [ "${_SLR_CM_CFG_RT}" = "NO" ] \
        && [ ! -e "${_SOLR_PROTECT_CTRL}" ]; then
        _update_solr "${_SOLR_MODULE}" "${_SOLR_DIR}" "${_SOLR_VER}"
      fi
    fi
  fi
}

_proceed_solr() {
  if [ ! -z "${_Dan}" ] \
    && [ "${_Dan}" != "hostmaster" ]; then
    CoreID="${_Dan}.${_HM_U}"
    CoreHS=$(echo ${CoreID} \
      | openssl md5 \
      | awk '{ print $2}' \
      | tr -d "\n" 2>&1)
    #_SolrCoreID="${_HM_U}-${_Dan}-${CoreHS}"
    _Legacy_SolrCoreID="${_HM_U}.${_Dan}"
    _Old_SolrCoreID="solr.${_HM_U}.${_Dan}"
    _SolrCoreID="oct.${_HM_U}.${_Dan}"
    _setup_solr
  fi
}

_check_sites_list() {
  for _Site in `find ${_usEr}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _MOMENT=$(date +%y%m%d-%H%M%S)
    echo ${_MOMENT} Start Checking Site ${_Site}
    _Dom=$(echo ${_Site} | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d/${_Dom}" ]; then
      _Plx=$(cat ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "${_Plx}" =~ "aegir/distro" ]]; then
        _Dan="hostmaster"
      else
        _Dan="${_Dom}"
      fi
    fi
    _STATUS_DISABLED=NO
    _STATUS_TEST=$(grep "Do not reveal Aegir front-end URL here" \
      ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} 2>&1)
    if [[ "${_STATUS_TEST}" =~ "Do not reveal Aegir front-end URL here" ]]; then
      _STATUS_DISABLED=YES
      echo "${_Dom} site is DISABLED"
    fi
    if [ -e "${_usEr}/.drush/${_Dan}.alias.drushrc.php" ] \
      && [ "${_STATUS_DISABLED}" = "NO" ]; then
      _Dir=$(cat ${_usEr}/.drush/${_Dan}.alias.drushrc.php \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _DIR_CTRL_F="${_Dir}/modules/boa_site_control.ini"
      _Plr=$(cat ${_usEr}/.drush/${_Dan}.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _PLR_CTRL_F="${_Plr}/sites/all/modules/boa_platform_control.ini"
      _proceed_solr
    fi
  done
}

_count_cpu() {
  _CPU_INFO="$(grep -c processor /proc/cpuinfo)"
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST="$(which nproc)"
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt 0 ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt 1 ]; then
    _CPU_NR=1
  fi
  echo ${_CPU_NR} > /data/all/cpuinfo
  chmod 644 /data/all/cpuinfo &> /dev/null
}

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

_load_control() {
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  : "${_CPU_TASK_RATIO:=3.1}"
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

_fix_solr9_core() {
  local file="$1"
  if [ -e "${file}" ]; then
    local _test_id
    _test_id=$(grep "solr9" "${file}" 2>&1)
    _test_port=$(grep "9099" "${file}" 2>&1)
    if [[ ! "${_test_id}" =~ "solr9" ]] || [[ ! "${_test_port}" =~ "9099" ]]; then
      sed -i "s/^solr\.replication\.masterUrl.*//g" "${file}"
      sed -i "s/^solr\.install\.dir.*//g" "${file}"
      sed -i "s/^solr\.contrib\.dir.*//g" "${file}"
      echo "solr.replication.masterUrl=http://localhost:9099" >> "${file}"
      echo "solr.install.dir=/opt/solr9" >> "${file}"
      sed -i "/^$/d" "${file}"
      echo "Fixed ${file}"
      _IF_RESTART_SOLR=YES
    fi
  fi
}

_fix_solr9_cnf() {
  if [ -x "/etc/init.d/solr9" ] && [ -e "/var/solr9/logs" ]; then
    _IF_RESTART_SOLR=NO
    for _pRp in `find /var/solr9/data/oct.*/conf/solrcore.properties -maxdepth 1 | sort`; do
      if [ -e "${_pRp}" ]; then
        _PRP_TEST_ID=$(grep "solr9" ${_pRp} 2>&1)
        _PRP_TEST_PORT=$(grep "9099" ${_pRp} 2>&1)
        if [[ ! "${_PRP_TEST_ID}" =~ "solr9" ]] || [[ ! "${_PRP_TEST_PORT}" =~ "9099" ]]; then
          sed -i "s/^solr\.replication\.masterUrl.*//g" ${_pRp}
          sed -i "s/^solr\.install\.dir.*//g" ${_pRp}
          sed -i "s/^solr\.contrib\.dir.*//g" ${_pRp}
          echo "solr.replication.masterUrl=http://localhost:9099" >> ${_pRp}
          echo "solr.install.dir=/opt/solr9" >> ${_pRp}
          sed -i "/^$/d" ${_pRp}
          echo "Fixed ${_pRp}"
          _IF_RESTART_SOLR=YES
        fi
      fi
    done
    _solr9_paths=(
      "/var/xdrago/conf/solr/search_api_solr/solr9_drupal10/solrcore.properties"
      "/data/conf/solr/search_api_solr/solr9_drupal10/solrcore.properties"
    )
    for path in "${_solr9_paths[@]}"; do
      _fix_solr9_core "${path}"
    done
    rStart="/var/solr9/logs/.restarted_new_fix_solr9_cnf.txt"
    if [ "${_IF_RESTART_SOLR}" = "YES" ] \
      || [ ! -e "${rStart}" ]; then
      echo "Restarting Solr 9..."
      service solr9 restart
      wait
      touch ${rStart}
    fi
  fi
}

_fix_solr7_core() {
  local file="$1"
  if [ -e "${file}" ]; then
    local _test_id
    _test_id=$(grep "solr7" "${file}" 2>&1)
    if [[ ! "${_test_id}" =~ "solr7" ]]; then
      sed -i "s/^solr\.install\.dir.*//g" "${file}"
      sed -i "s/^solr\.contrib\.dir.*//g" "${file}"
      echo "solr.install.dir=/opt/solr7" >> "${file}"
      sed -i "/^$/d" "${file}"
      echo "Fixed ${file}"
      _IF_RESTART_SOLR=YES
    fi
  fi
}

_fix_solr7_cnf() {
  if [ -x "/etc/init.d/solr7" ] && [ -e "/var/solr7/logs" ]; then
    _IF_RESTART_SOLR=NO
    for _pRp in `find /var/solr7/data/oct.*/conf/solrcore.properties -maxdepth 1 | sort`; do
      if [ -e "${_pRp}" ]; then
        _PRP_TEST_ID=$(grep "solr7" ${_pRp} 2>&1)
        if [[ ! "${_PRP_TEST_ID}" =~ "solr7" ]]; then
          sed -i "s/^solr\.install\.dir.*//g" ${_pRp}
          sed -i "s/^solr\.contrib\.dir.*//g" ${_pRp}
          echo "solr.install.dir=/opt/solr7" >> ${_pRp}
          sed -i "/^$/d" ${_pRp}
          echo "Fixed ${_pRp}"
          _IF_RESTART_SOLR=YES
        fi
      fi
    done
    _solr7_paths=(
      "/var/xdrago/conf/solr/search_api_solr/solr7_drupal7/solrcore.properties"
      "/var/xdrago/conf/solr/search_api_solr/solr7_drupal8/solrcore.properties"
      "/var/xdrago/conf/solr/search_api_solr/solr7_drupal9/solrcore.properties"
      "/var/xdrago/conf/solr/search_api_solr/solr7_drupal10/solrcore.properties"
      "/data/conf/solr/search_api_solr/solr7_drupal7/solrcore.properties"
      "/data/conf/solr/search_api_solr/solr7_drupal8/solrcore.properties"
      "/data/conf/solr/search_api_solr/solr7_drupal9/solrcore.properties"
      "/data/conf/solr/search_api_solr/solr7_drupal10/solrcore.properties"
    )
    for path in "${_solr7_paths[@]}"; do
      _fix_solr7_core "${path}"
    done
    rStart="/var/solr7/logs/.restarted_new_fix_solr7_cnf.txt"
    if [ "${_IF_RESTART_SOLR}" = "YES" ] \
      || [ ! -e "${rStart}" ]; then
      echo "Restarting Solr 7..."
      service solr7 restart
      wait
      touch ${rStart}
    fi
  fi
}

_sync_solr_config() {
  local _rel_dir="$1"
  local _base_dir="/var/xdrago/conf/solr/${_rel_dir}"

  if [ -d "${_base_dir}" ]; then
    local _baseCpy="${_base_dir}/schema.xml"
    local _liveCpy="/data/conf/solr/${_rel_dir}/schema.xml"

    _check_config_diff "${_baseCpy}" "${_liveCpy}"

    if [ ! -e "/data/conf/solr/${_rel_dir}/solrconfig.xml" ] \
      || [ ! -e "/data/conf/solr/.ctrl.${_tRee}.${_xSrl}.pid" ] \
      || [ ! -z "${_slrCnfUpdate}" ]; then
      rm -rf /data/conf/solr
      cp -af /var/xdrago/conf/solr /data/conf/
      rm -f /data/conf/solr/.ctrl*
      touch /data/conf/solr/.ctrl.${_tRee}.${_xSrl}.pid
    fi
  fi
}

_start_up() {
  _fix_solr9_cnf
  _fix_solr7_cnf

  _solr_cnf_dirs=(
    "search_api_solr/solr7_drupal7"
    "search_api_solr/solr7_drupal8"
    "search_api_solr/solr7_drupal9"
    "search_api_solr/solr7_drupal10"
    "search_api_solr/solr9_drupal10"
    "apachesolr/solr4_drupal6"
    "apachesolr/solr4_drupal7"
  )

  for dir in "${_solr_cnf_dirs[@]}"; do
    _sync_solr_config "$dir"
  done

  for _usEr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    _count_cpu
    _load_control
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/CANCELLED" ]; then
      if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
        _HM_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _THIS_HM_SITE=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "User ${_usEr}"
        mkdir -p ${_usEr}/log/ctrl
        # shellcheck disable=SC1091
        [ -e "/root/.${_HM_U}.octopus.cnf" ] && source /root/.${_HM_U}.octopus.cnf
        _check_sites_list
      fi
    fi
  done
}

_NOW=$(date +%y%m%d-%H%M%S)
_NOW=${_NOW//[^0-9-]/}
mkdir -p /var/backups/solr/log
find /var/backups/solr/*/* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
_start_up >/var/backups/solr/log/solr-${_NOW}.log 2>&1
exit 0
