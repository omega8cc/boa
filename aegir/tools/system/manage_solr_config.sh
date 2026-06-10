#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=lts
export _xSrl=595ltsT01

[ -e "/root/.proxy.cnf" ] && exit 0

_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"
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

###
### Orphan core cleanup
###
### Three-tier classification for every oct.* / solr.* core found on disk:
###
###   TIER 1 — No vhost at all, OR vhost exists but no Aegir drush alias:
###            Core is unknown to the provisioning layer. Apply short
###            staleness threshold (_ORPHAN_STALE_DAYS, default 14d).
###
###   TIER 2 — Vhost exists AND Aegir alias exists (site is known but may be
###            an abandoned clone, old staging env, renamed domain, etc.):
###            Apply long staleness threshold (_ORPHAN_VHOST_STALE_DAYS,
###            default 60d) on data/index/ mtime only — giving cloned/renamed
###            sites plenty of time before their core is retired.
###
###   TIER 3 — Protected by conf/.protected.conf: never touched regardless.
###
### Staleness is measured on data/index/ (Lucene commit mtime — the cleanest
### signal of real indexing activity). data/ itself is intentionally NOT used
### as the primary signal because Solr keeps it perpetually fresh via tlog,
### write.lock and other bookkeeping writes even on idle cores.
###
### Qualifying cores are NOT deleted — they are unloaded from Solr's registry
### and moved to /var/backups/solrN/<timestamp>-<core>/ for easy recovery.
###
_ORPHAN_STALE_DAYS=14       # tier 1: no vhost / no alias
_ORPHAN_VHOST_STALE_DAYS=60 # tier 2: vhost+alias present but index inactive

_build_active_core_set() {
  # Populates three global associative arrays:
  #
  #   _CORES_WITH_VHOST       — core has a matching enabled nginx vhost
  #   _CORES_WITH_ALIAS       — core also has a matching Aegir drush alias
  #   _CORES_WITH_SOLR_MODULE — site has solr_integration_module explicitly
  #                             set in boa_site_control.ini — these are
  #                             actively managed and must never be archived
  #                             based on index age alone, even if stale
  #
  # All three historical name formats (oct.*, solr.*, <user>.<domain>) are
  # registered for each site so transitional/renamed cores are never wrongly
  # retired.
  declare -gA _CORES_WITH_VHOST=()
  declare -gA _CORES_WITH_ALIAS=()
  declare -gA _CORES_WITH_SOLR_MODULE=()

  for _usEr in $(find /data/disk/ -maxdepth 1 -mindepth 1 | sort); do
    [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] || continue
    local _HM_U_TMP
    _HM_U_TMP=$(echo "${_usEr}" | cut -d'/' -f4 | awk '{ print $1}')

    for _Site in $(find "${_usEr}/config/server_master/nginx/vhost.d" \
        -maxdepth 1 -mindepth 1 -type f | sort); do
      local _DomTmp _STATUS_T _PlxTmp
      _DomTmp=$(echo "${_Site}" | cut -d'/' -f9 | awk '{ print $1}')
      [ -z "${_DomTmp}" ] && continue

      # Skip disabled/parked sites
      _STATUS_T=$(grep "Do not reveal Aegir front-end URL here" "${_Site}" 2>&1)
      [[ "${_STATUS_T}" =~ "Do not reveal Aegir front-end URL here" ]] && continue

      # Skip hostmaster vhosts
      _PlxTmp=$(grep "root " "${_Site}" | cut -d: -f2 | awk '{ print $2}' | sed "s/[\;]//g" 2>&1)
      [[ "${_PlxTmp}" =~ "aegir/distro" ]] && continue

      # Register vhost presence for all three name formats
      _CORES_WITH_VHOST["oct.${_HM_U_TMP}.${_DomTmp}"]=1
      _CORES_WITH_VHOST["solr.${_HM_U_TMP}.${_DomTmp}"]=1
      _CORES_WITH_VHOST["${_HM_U_TMP}.${_DomTmp}"]=1

      # Check for Aegir drush alias
      local _aliasFile="${_usEr}/.drush/${_DomTmp}.alias.drushrc.php"
      if [ -f "${_aliasFile}" ]; then
        _CORES_WITH_ALIAS["oct.${_HM_U_TMP}.${_DomTmp}"]=1
        _CORES_WITH_ALIAS["solr.${_HM_U_TMP}.${_DomTmp}"]=1
        _CORES_WITH_ALIAS["${_HM_U_TMP}.${_DomTmp}"]=1

        # Check for explicit solr_integration_module in boa_site_control.ini.
        # A site with this set is actively managed by _check_sites_list and
        # must not be archived based on index age — _add_solr will recreate
        # the core empty if we archive it, losing the index permanently.
        local _sitePath
        _sitePath=$(grep "site_path'" "${_aliasFile}" \
          | cut -d: -f2 | awk '{print $3}' | sed "s/[\,']//g" 2>/dev/null)
        if [ -n "${_sitePath}" ]; then
          local _ctrlFile="${_sitePath}/modules/boa_site_control.ini"
          if [ -f "${_ctrlFile}" ]; then
            local _solrMod
            _solrMod=$(grep "^solr_integration_module" "${_ctrlFile}" 2>/dev/null)
            if [ -n "${_solrMod}" ]; then
              _CORES_WITH_SOLR_MODULE["oct.${_HM_U_TMP}.${_DomTmp}"]=1
              _CORES_WITH_SOLR_MODULE["solr.${_HM_U_TMP}.${_DomTmp}"]=1
              _CORES_WITH_SOLR_MODULE["${_HM_U_TMP}.${_DomTmp}"]=1
            fi
          fi
        fi
      fi
    done
  done
}

_core_is_stale() {
  # Returns 0 (stale/archive-eligible) or 1 (fresh/keep).
  # ${1} = core path
  # ${2} = staleness threshold in days
  #
  # Primary signal: data/index/ mtime — updated only on Lucene segment commits.
  # Fallback:       data/ mtime — catches tlog-only replicas mid-reindex.
  # A core with no data/ at all was never indexed → immediately stale.
  local _corePath="${1}"
  local _threshold="${2}"
  local _dataDir="${_corePath}/data"
  local _indexDir="${_corePath}/data/index"

  [ -d "${_dataDir}" ] || return 0  # no data dir → stale

  if [ -d "${_indexDir}" ]; then
    local _indexFresh
    _indexFresh=$(find "${_indexDir}" -maxdepth 0 \
      -mtime "-${_threshold}" 2>/dev/null)
    [ -n "${_indexFresh}" ] && return 1  # index recently committed → keep
  fi

  local _dataFresh
  _dataFresh=$(find "${_dataDir}" -maxdepth 0 \
    -mtime "-${_threshold}" 2>/dev/null)
  [ -n "${_dataFresh}" ] && return 1  # data dir recently touched → keep

  return 0  # both older than threshold → stale
}

_core_last_activity_days() {
  # Echoes age in days of the most recent of data/index/ and data/ mtimes.
  # Used only for human-readable log output.
  local _corePath="${1}"
  local _now _iMtime _dMtime _newest
  _now=$(date +%s)
  _iMtime=0
  _dMtime=0
  [ -d "${_corePath}/data/index" ] && \
    _iMtime=$(stat -c %Y "${_corePath}/data/index" 2>/dev/null || echo 0)
  [ -d "${_corePath}/data" ] && \
    _dMtime=$(stat -c %Y "${_corePath}/data" 2>/dev/null || echo 0)
  _newest=$(( _iMtime >= _dMtime ? _iMtime : _dMtime ))
  echo $(( ( _now - _newest ) / 86400 ))
}

_archive_orphan_core() {
  # Unloads the core from Solr's registry (without deleting any files) then
  # moves the directory to the backup location for easy manual recovery.
  #
  # ${1} = port  ${2} = backup base dir  ${3} = core path  ${4} = timestamp
  #
  # RECOVERY — to restore an archived core:
  #
  #   port=9077  # or 9099 for solr9
  #   core="oct.o1.example.com"
  #   bkp="/var/backups/solr7/20260418-222802-${core}"   # adjust timestamp
  #   dest="/var/solr7/data/${core}"                     # or solr9
  #
  #   mv "${bkp}" "${dest}"
  #   chown -R solr7:solr7 "${dest}"                     # or solr9:solr9
  #   curl "http://127.0.0.1:${port}/solr/admin/cores?action=CREATE&name=${core}&instanceDir=${dest}"
  #
  # NOTE: use CREATE not RELOAD — RELOAD only works for already-registered
  # cores. CREATE re-registers the existing directory without touching files.
  local _port="${1}" _bkpBase="${2}" _corePath="${3}" _ts="${4}"
  local _coreName
  _coreName=$(basename "${_corePath}")

  # Unload via admin API — deleteIndex/DataDir/InstanceDir all false so Solr
  # releases its handle but leaves every file intact for the mv below
  curl -s --max-time 15 \
    "http://127.0.0.1:${_port}/solr/admin/cores?action=UNLOAD&core=${_coreName}&deleteIndex=false&deleteDataDir=false&deleteInstanceDir=false" \
    > /dev/null 2>&1 || true
  wait

  local _bkpDest="${_bkpBase}/${_ts}-${_coreName}"
  mkdir -p "${_bkpBase}"
  if mv "${_corePath}" "${_bkpDest}"; then
    echo "ORPHAN-ARCHIVED: ${_coreName} → ${_bkpDest}"
  else
    echo "ORPHAN-ERROR: mv failed for ${_corePath} — skipping"
  fi
}

_purge_orphan_cores() {
  # ${1} = solr binary   ${2} = solr unix user  ${3} = port
  # ${4} = data dir      ${5} = backup base dir
  local _bin="${1}" _usr="${2}" _port="${3}" _datadir="${4}" _bkpBase="${5}"

  [ -x "${_bin}" ]     || return
  [ -d "${_datadir}" ] || return

  local _archived=0 _protected=0 _fresh=0 _skipped=0 _ts
  _ts=$(date +%Y%m%d-%H%M%S)

  for _corePath in $(find "${_datadir}" -maxdepth 1 -mindepth 1 -type d | sort); do
    local _coreName _dot_count
    _coreName=$(basename "${_corePath}")

    # Only process cores matching our naming convention
    if [[ ! "${_coreName}" =~ ^(oct|solr)\. ]]; then
      _dot_count=$(echo "${_coreName}" | tr -cd '.' | wc -c)
      [ "${_dot_count}" -lt 1 ] && continue
    fi

    # Protection sentinel always wins — no logging spam for these
    if [ -e "${_corePath}/conf/.protected.conf" ]; then
      (( _protected++ ))
      continue
    fi

    local _hasVhost _hasAlias _threshold _tier _age
    _hasVhost=0
    _hasAlias=0
    [ -n "${_CORES_WITH_VHOST[${_coreName}]+x}" ] && _hasVhost=1
    [ -n "${_CORES_WITH_ALIAS[${_coreName}]+x}" ] && _hasAlias=1

    if [ "${_hasVhost}" -eq 1 ] && [ "${_hasAlias}" -eq 1 ]; then
      # Extra gate: if site has solr_integration_module explicitly configured,
      # _check_sites_list actively manages this core and will recreate it
      # empty if we archive it.  Protect it unconditionally.
      if [ -n "${_CORES_WITH_SOLR_MODULE[${_coreName}]+x}" ]; then
        echo "ORPHAN-SKIP: ${_coreName} — solr_integration_module set, actively managed"
        (( _protected++ ))
        continue
      fi
      # Tier 2: properly provisioned site — use the long threshold
      _threshold="${_ORPHAN_VHOST_STALE_DAYS}"
      _tier="tier2(vhost+alias)"
    else
      # Tier 1: no vhost, or vhost with no Aegir alias (nginx leftover / dead clone)
      _threshold="${_ORPHAN_STALE_DAYS}"
      _tier="tier1(no-vhost-or-alias)"
    fi

    if ! _core_is_stale "${_corePath}" "${_threshold}"; then
      _age=$(_core_last_activity_days "${_corePath}")
      echo "ORPHAN-FRESH: ${_coreName} [${_tier}] index ${_age}d ago (threshold ${_threshold}d) — keeping"
      (( _fresh++ ))
      continue
    fi

    _age=$(_core_last_activity_days "${_corePath}")
    echo "ORPHAN-CANDIDATE: ${_coreName} [${_tier}] index ${_age}d ago — archiving"
    _archive_orphan_core "${_port}" "${_bkpBase}" "${_corePath}" "${_ts}"
    (( _archived++ ))
  done

  echo "Orphan cleanup port=${_port}: archived=${_archived} fresh(kept)=${_fresh} protected=${_protected}"
}

_cleanup_orphan_cores() {
  # Guard: never run during a BOA install or upgrade
  [ "${_protectedRun}" = "TRUE" ] && return

  # Throttle: run at most once every 6 hours.
  # The sentinel file is touched on each successful run; we skip if it is
  # younger than 6 hours (360 minutes — find -mmin returns a result = fresh).
  local _sentinel="/var/backups/solr/.orphan_cleanup_last_run.pid"
  mkdir -p /var/backups/solr
  if [ -e "${_sentinel}" ]; then
    local _sentinel_fresh
    _sentinel_fresh=$(find "${_sentinel}" -mmin "-360" 2>/dev/null)
    if [ -n "${_sentinel_fresh}" ]; then
      echo "Orphan cleanup skipped -- last run less than 6 hours ago (${_sentinel})"
      return
    fi
  fi

  echo "=== Orphan core cleanup start ==="

  _build_active_core_set
  echo "Active cores with vhost: ${#_CORES_WITH_VHOST[@]}  with alias: ${#_CORES_WITH_ALIAS[@]}  with solr module: ${#_CORES_WITH_SOLR_MODULE[@]}"

  if [ -x "/etc/init.d/solr7" ] && [ -d "/var/solr7/data" ]; then
    mkdir -p /var/backups/solr7
    _purge_orphan_cores \
      "/opt/solr7/bin/solr" "solr7" "9077" "/var/solr7/data" "/var/backups/solr7"
  fi

  if [ -x "/etc/init.d/solr9" ] && [ -d "/var/solr9/data" ]; then
    mkdir -p /var/backups/solr9
    _purge_orphan_cores \
      "/opt/solr9/bin/solr" "solr9" "9099" "/var/solr9/data" "/var/backups/solr9"
  fi

  touch "${_sentinel}"
  echo "=== Orphan core cleanup end ==="
}

_check_solr_core_health() {
  # Queries the Solr admin STATUS API for every registered core and logs
  # anomalies that could indicate memory pressure or a problematic core:
  #
  #   - Cores reporting initFailures (failed to load)
  #   - High segment count (>50) -- many small unmerged segments hold open
  #     file handles and contribute to Metaspace pressure via per-segment
  #     FieldCache entries
  #   - High deleted doc ratio (>20% of maxDoc) -- unmerged deletes inflate
  #     heap and prevent segment GC
  #   - Large index size (>500MB) -- informational
  #
  # Read-only diagnostic -- no changes are made.
  # ${1} = port   e.g. 9077 or 9099
  # ${2} = label  e.g. solr7 or solr9
  local _port="${1}" _label="${2}"
  local _api="http://127.0.0.1:${_port}/solr/admin/cores?action=STATUS&wt=json"

  if ! command -v python3 &>/dev/null; then
    echo "HEALTH-SKIP: python3 not available, skipping ${_label} core health check"
    return
  fi

  local _json
  _json=$(curl -s --max-time 15 "${_api}" 2>/dev/null)
  if [ -z "${_json}" ]; then
    echo "HEALTH-ERROR: no response from ${_label} on port ${_port}"
    return
  fi

  local _tmpjson
  _tmpjson=$(mktemp /tmp/solr_health_XXXXXX.json)
  echo "${_json}" > "${_tmpjson}"

  echo "=== Core health check ${_label} port=${_port} ==="

  python3 - "${_tmpjson}" <<'PYEOF'
import json, sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception as e:
    print(f"HEALTH-ERROR: JSON parse failed: {e}")
    sys.exit(0)

init_failures = data.get("initFailures", {})
if init_failures:
    for core, err in init_failures.items():
        print(f"HEALTH-INIT-FAIL: {core} -- {err}")

cores = data.get("status", {})
if not cores:
    print("HEALTH-INFO: no cores registered")
    sys.exit(0)

print(f"HEALTH-INFO: {len(cores)} cores registered")

for name, info in sorted(cores.items()):
    index    = info.get("index", {})
    num_docs = index.get("numDocs", 0)
    max_doc  = index.get("maxDoc", 0)
    deleted  = max_doc - num_docs
    segments = index.get("segmentCount", 0)
    size_mb  = index.get("sizeInBytes", 0) / 1048576

    issues = []

    if segments > 50:
        issues.append(f"high segment count={segments}")

    if max_doc > 0:
        del_pct = (deleted / max_doc) * 100
        if del_pct > 20:
            issues.append(f"deleted={deleted}/{max_doc} ({del_pct:.0f}%)")

    if size_mb > 500:
        issues.append(f"large index={size_mb:.0f}MB")

    if issues:
        print(f"HEALTH-WARN: {name}  docs={num_docs}  segs={segments}  "
              f"size={size_mb:.1f}MB  issues: {', '.join(issues)}")
PYEOF

  rm -f "${_tmpjson}"
  echo "=== Core health check end ==="
}


_optimize_solr_cores() {
  # Runs expungeDeletes on every registered core where the deleted doc ratio
  # exceeds _OPTIMIZE_DEL_PCT_THRESHOLD, and a full optimize (maxSegments=1)
  # on cores where the ratio exceeds _OPTIMIZE_FULL_THRESHOLD.
  #
  # Design decisions:
  #
  #   expungeDeletes vs full optimize:
  #     expungeDeletes merges only segments whose deleted doc fraction exceeds
  #     the merge policy threshold. It is cheap, non-blocking for queries, and
  #     safe to run frequently. Full optimize (maxSegments=1) merges everything
  #     into a single segment — expensive on large indexes but reclaims the
  #     most space and gives the best query performance. We use a higher
  #     threshold to trigger the full optimize and only do it when genuinely
  #     needed.
  #
  #   waitFlush=false:
  #     Both calls return immediately while the merge continues in the
  #     background. This keeps the script runtime bounded regardless of index
  #     size. The next health check run will reflect the improved state.
  #
  #   Protected cores (conf/.protected.conf):
  #     These have custom solrconfig.xml and may have their own merge policy
  #     already tuned (e.g. TieredMergePolicy with deletesPctAllowed=20).
  #     We still run expungeDeletes on them if the ratio is very high, but
  #     skip the full optimize to avoid interfering with their tuning.
  #
  #   Throttle:
  #     Sentinel file at /var/backups/solr/.optimize_last_run.pid limits
  #     execution to once every _OPTIMIZE_INTERVAL_HOURS hours (default 12).
  #     This keeps the function rate-limited even though _start_up runs
  #     every 4 minutes.
  #
  # ${1} = port   e.g. 9077 or 9099
  # ${2} = label  e.g. solr7 or solr9
  # ${3} = data dir  e.g. /var/solr7/data
  local _port="${1}" _label="${2}" _datadir="${3}"

  [ -d "${_datadir}" ] || return

  if ! command -v python3 &>/dev/null; then
    echo "OPTIMIZE-SKIP: python3 not available"
    return
  fi

  local _api="http://127.0.0.1:${_port}/solr/admin/cores?action=STATUS&wt=json"
  local _json
  _json=$(curl -s --max-time 15 "${_api}" 2>/dev/null)
  if [ -z "${_json}" ]; then
    echo "OPTIMIZE-ERROR: no response from ${_label} on port ${_port}"
    return
  fi

  local _tmpjson
  _tmpjson=$(mktemp /tmp/solr_optimize_XXXXXX.json)
  echo "${_json}" > "${_tmpjson}"

  echo "=== Index optimize check ${_label} port=${_port} ==="

  # Extract core names and their deleted doc ratios from the STATUS response,
  # then decide per-core action. Output format: <action> <corename>
  # where action is: skip | expunge | optimize
  local _decisions
  _decisions=$(python3 - "${_tmpjson}" \
    "${_OPTIMIZE_DEL_PCT_THRESHOLD}" "${_OPTIMIZE_FULL_THRESHOLD}" <<'PYEOF'
import json, sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception as e:
    print(f"# parse error: {e}", file=sys.stderr)
    sys.exit(0)

expunge_threshold = float(sys.argv[2])
full_threshold    = float(sys.argv[3])

cores = data.get("status", {})
for name, info in sorted(cores.items()):
    index    = info.get("index", {})
    num_docs = index.get("numDocs", 0)
    max_doc  = index.get("maxDoc", 0)
    deleted  = max_doc - num_docs
    del_pct  = (deleted / max_doc * 100) if max_doc > 0 else 0
    size_mb  = index.get("sizeInBytes", 0) / 1048576

    if del_pct >= full_threshold:
        print(f"optimize {name} {del_pct:.1f} {size_mb:.0f}")
    elif del_pct >= expunge_threshold:
        print(f"expunge {name} {del_pct:.1f} {size_mb:.0f}")
    else:
        print(f"skip {name} {del_pct:.1f} {size_mb:.0f}")
PYEOF
)

  rm -f "${_tmpjson}"

  local _action _coreName _delPct _sizeMb _isProtected
  while read -r _action _coreName _delPct _sizeMb; do
    [ -z "${_coreName}" ] && continue

    # Check protection sentinel
    _isProtected=0
    [ -e "${_datadir}/${_coreName}/conf/.protected.conf" ] && _isProtected=1

    case "${_action}" in
      skip)
        echo "OPTIMIZE-OK: ${_coreName} deleted=${_delPct}% — no action needed"
        ;;
      expunge)
        echo "OPTIMIZE-EXPUNGE: ${_coreName} deleted=${_delPct}% size=${_sizeMb}MB — running expungeDeletes"
        curl -s --max-time 30 \
          "http://127.0.0.1:${_port}/solr/${_coreName}/update?expungeDeletes=true&waitFlush=false" \
          > /dev/null 2>&1 || true
        ;;
      optimize)
        if [ "${_isProtected}" -eq 1 ]; then
          # Protected core: TieredMergePolicy may already handle this.
          # Run expungeDeletes only — do not force a full merge that could
          # interfere with a custom merge policy tuned for this workload.
          echo "OPTIMIZE-EXPUNGE: ${_coreName} deleted=${_delPct}% size=${_sizeMb}MB (protected) — expungeDeletes only"
          curl -s --max-time 30 \
            "http://127.0.0.1:${_port}/solr/${_coreName}/update?expungeDeletes=true&waitFlush=false" \
            > /dev/null 2>&1 || true
        else
          echo "OPTIMIZE-FULL: ${_coreName} deleted=${_delPct}% size=${_sizeMb}MB — running full optimize (background)"
          curl -s --max-time 30 \
            "http://127.0.0.1:${_port}/solr/${_coreName}/update?optimize=true&maxSegments=1&waitFlush=false" \
            > /dev/null 2>&1 || true
        fi
        ;;
    esac
  done <<< "${_decisions}"

  echo "=== Index optimize check end ==="
}

_run_optimize_if_due() {
  # Throttle wrapper for _optimize_solr_cores.
  # Runs at most once every _OPTIMIZE_INTERVAL_HOURS hours using a sentinel
  # file, then calls per-instance optimize checks.
  [ "${_protectedRun}" = "TRUE" ] && return

  local _sentinel="/var/backups/solr/.optimize_last_run.pid"
  mkdir -p /var/backups/solr

  if [ -e "${_sentinel}" ]; then
    local _sentinelFresh
    _sentinelFresh=$(find "${_sentinel}" \
      -mmin "-$(( _OPTIMIZE_INTERVAL_HOURS * 60 ))" 2>/dev/null)
    if [ -n "${_sentinelFresh}" ]; then
      echo "Index optimize skipped — last run less than ${_OPTIMIZE_INTERVAL_HOURS}h ago"
      return
    fi
  fi

  echo "=== Index optimize start (interval=${_OPTIMIZE_INTERVAL_HOURS}h expunge>=${_OPTIMIZE_DEL_PCT_THRESHOLD}% full>=${_OPTIMIZE_FULL_THRESHOLD}%) ==="

  if [ -x "/etc/init.d/solr7" ] && [ -d "/var/solr7/data" ]; then
    _optimize_solr_cores "9077" "solr7" "/var/solr7/data"
  fi

  if [ -x "/etc/init.d/solr9" ] && [ -d "/var/solr9/data" ]; then
    _optimize_solr_cores "9099" "solr9" "/var/solr9/data"
  fi

  touch "${_sentinel}"
  echo "=== Index optimize end ==="
}

# Thresholds and interval — tune here without touching function logic.
#
# _OPTIMIZE_DEL_PCT_THRESHOLD: deleted doc % at which expungeDeletes fires.
#   Lucene's default merge policy tolerates ~10% before merging naturally.
#   20% is a safe threshold that catches accumulation without over-merging.
#
# _OPTIMIZE_FULL_THRESHOLD: deleted doc % at which a full optimize fires.
#   Only triggered on genuinely problematic indexes. 30% chosen because at
#   this level merge policy is clearly not keeping up with write rate.
#
# _OPTIMIZE_INTERVAL_HOURS: minimum hours between optimize runs.
#   12h means at most 2 runs per day regardless of how often the script
#   is invoked. Set to 6 for more aggressive maintenance.
_OPTIMIZE_DEL_PCT_THRESHOLD=20
_OPTIMIZE_FULL_THRESHOLD=30
_OPTIMIZE_INTERVAL_HOURS=12

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

  # Orphan cleanup runs AFTER _check_sites_list so that any core legitimately
  # recreated by _add_solr in this same run is already on disk and registered
  # before we evaluate what qualifies as an orphan. Running before
  # _check_sites_list caused a race where a managed core with a stale index
  # was archived and then immediately recreated empty by _add_solr.
  _cleanup_orphan_cores
  [ -x "/etc/init.d/solr7" ] && _check_solr_core_health "9077" "solr7"
  [ -x "/etc/init.d/solr9" ] && _check_solr_core_health "9099" "solr9"
  _run_optimize_if_due
}

_is_protected_run() {
  _protectedRun=FALSE
  _optBin="/opt/local/bin"
  _boaBins="autoinit automini barracuda boa octopus"
  for _cbn in ${_boaBins}; do
    if [ -e "${_optBin}/${_cbn}" ]; then
      _CNT=$(pgrep -fc /local/bin/${_cbn})
      if (( _CNT > 0 )); then
        echo "The ${_cbn} is running!"
        _protectedRun=TRUE
      fi
    fi
  done
  [ -e "/run/octopus_install_run.pid" ] && _protectedRun=TRUE
  [ -e "/run/boa_run.pid" ] && _protectedRun=TRUE
  [ -e "/run/boa_wait.pid" ] && _protectedRun=TRUE
}
_is_protected_run

if [ "${_protectedRun}" = "FALSE" ]; then
  _NOW=$(date +%y%m%d-%H%M%S)
  _NOW=${_NOW//[^0-9-]/}
  [ -d "/var/backups/solr/log" ] || mkdir -p /var/backups/solr/log
  find /var/backups/solr/*/* -mtime +0 -type f -exec rm -f {} \; &> /dev/null
  _start_up >/var/backups/solr/log/solr-${_NOW}.log 2>&1
fi

exit 0
