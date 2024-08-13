#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

_X_SE="540proT00"
crlGet="-L --max-redirs 10 -k -s --retry 10 --retry-delay 5 -A iCab"
aptYesUnth="-y --allow-unauthenticated"
vSet="variable-set --always-set"

###-------------SYSTEM-----------------###

check_config_diff() {
  # $1 is template path
  # $2 is a path to core config
  preCnf="$1"
  slrCnf="$2"
  if [ -f "${preCnf}" ] && [ -f "${slrCnf}" ]; then
    slrCnfUpdate=NO
    diffMyTest=$(diff -w -B ${slrCnf} ${preCnf} 2>&1)
    if [ -z "${diffMyTest}" ]; then
      slrCnfUpdate=""
      echo "INFO: ${slrCnf} diff0 empty -- nothing to update"
    else
      slrCnfUpdate=YES
      # diffMyTest=$(echo -n ${diffMyTest} | fmt -su -w 2500 2>&1)
      echo "INFO: ${slrCnf} diff1 ${diffMyTest}"
    fi
  fi
}

write_solr_config() {
  # ${1} is module
  # ${2} is a path to solr.php
  # ${3} is Jetty/Solr version
  if [ ! -z "${1}" ] \
    && [ ! -z "${2}" ] \
    && [ ! -z "${3}" ] \
    && [ ! -z "${SolrCoreID}" ] \
    && [ -e "${Dir}" ]; then
    if [ "${3}" = "solr7" ]; then
      _PRT="9077"
      _VRS="7.7.3"
    else
      _PRT="8099"
      _VRS="4.9.1"
    fi
    echo "Your SOLR core access details for ${Dom} site are as follows:"  > ${2}
    echo                                                                 >> ${2}
    echo "  Drupal 8 and newer"                                          >> ${2}
    echo "  Solr version .....: ${_VRS}"                                 >> ${2}
    echo "  Solr host ........: 127.0.0.1"                               >> ${2}
    echo "  Solr port ........: ${_PRT}"                                 >> ${2}
    echo "  Solr path ........: leave empty"                             >> ${2}
    echo "  Solr core ........: ${SolrCoreID}"                           >> ${2}
    echo                                                                 >> ${2}
    echo "  Don't forget to manually upload the configuration files"     >> ${2}
    echo "  (schema.xml, solrconfig.xml) under ${Dom}/files/solr"        >> ${2}
    echo                                                                 >> ${2}
    echo "  Drupal 7:"                                                   >> ${2}
    echo "  Solr version .....: ${_VRS}"                                 >> ${2}
    echo "  Solr host ........: 127.0.0.1"                               >> ${2}
    echo "  Solr port ........: ${_PRT}"                                 >> ${2}
    echo "  Solr path ........: /solr/${SolrCoreID}"                     >> ${2}
    echo                                                                 >> ${2}
    echo "It has been auto-configured to work with latest version"       >> ${2}
    echo "of ${1} module, but you need to add the module to"             >> ${2}
    echo "your site codebase before you will be able to use Solr."       >> ${2}
    echo                                                                 >> ${2}
    echo "To learn more please make sure to check the module docs at:"   >> ${2}
    echo                                                                 >> ${2}
    echo "https://drupal.org/project/${1}"                               >> ${2}
    chown ${_HM_U}:users ${2} &> /dev/null
    chmod 440 ${2} &> /dev/null
  fi
}

reload_core_cnf() {
  # ${1} is solr server port
  # ${2} is solr core name
  # Example: reload_core_cnf 9077 ${SolrCoreID}
  # Example: reload_core_cnf 8099 ${SolrCoreID}
  curl "http://127.0.0.1:${1}/solr/admin/cores?action=RELOAD&core=${2}" &> /dev/null
  echo "Reloaded Solr core ${2} cnf on port ${1}"
  wait
}

update_solr() {
  # ${1} is module
  # ${2} is solr core path (auto) == _SOLR_DIR
  _SERV="solr7"
  if [ ! -z "${1}" ] && [ -e "/data/conf/solr" ]; then
    if [ "${1}" = "apachesolr" ]; then
      _SERV="jetty9"
      if [ -e "${Plr}/modules/o_contrib_seven" ]; then
        if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ]; then
          slrCnfUpdate=""
          check_config_diff "/data/conf/solr/apachesolr/7/schema.xml" "${2}/conf/schema.xml"
          if [ ! -z "${slrCnfUpdate}" ]; then
            rm -f ${2}/conf/*
            cp -af /data/conf/solr/apachesolr/7/* ${2}/conf/
            chmod 644 ${2}/conf/*
            chown jetty9:jetty9 ${2}/conf/*
            touch ${2}/conf/.just-updated.pid
          else
            rm -f ${2}/conf/.just-updated.pid
            rm -f ${2}/conf/.yes-update.txt
          fi
        fi
      elif [ -e "${Plr}/modules/o_contrib" ]; then
        if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ]; then
          slrCnfUpdate=""
          check_config_diff "/data/conf/solr/apachesolr/6/schema.xml" "${2}/conf/schema.xml"
          if [ ! -z "${slrCnfUpdate}" ]; then
            rm -f ${2}/conf/*
            cp -af /data/conf/solr/apachesolr/6/* ${2}/conf/
            chmod 644 ${2}/conf/*
            chown jetty9:jetty9 ${2}/conf/*
            touch ${2}/conf/.just-updated.pid
          else
            rm -f ${2}/conf/.just-updated.pid
            rm -f ${2}/conf/.yes-update.txt
          fi
        fi
      fi
    elif [ "${1}" = "search_api_solr" ] \
      && [ -e "${Plr}/modules/o_contrib_seven" ]; then
      if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ]; then
        check_config_diff "/data/conf/solr/search_api_solr/7/schema.xml" "${2}/conf/schema.xml"
        if [ ! -z "${slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/7/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown solr7:solr7 ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
        check_config_diff "/data/conf/solr/search_api_solr/7/solrcore.properties" "${2}/conf/solrcore.properties"
        if [ ! -z "${slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/7/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown solr7:solr7 ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
      fi
    elif [ "${1}" = "search_api_solr" ] \
      && [ -e "${Plr}/sites/${Dom}/files/solr/schema.xml" ] \
      && [ -e "${Plr}/sites/${Dom}/files/solr/solrconfig.xml" ] \
      && [ -e "${Plr}/sites/${Dom}/files/solr/solrcore.properties" ]; then
      if [ ! -e "${2}/conf/.protected.conf" ] && [ -e "${2}/conf" ]; then
        check_config_diff "${Plr}/sites/${Dom}/files/solr/schema.xml" "${2}/conf/schema.xml"
        if [ ! -z "${slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af ${Plr}/sites/${Dom}/files/solr/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown solr7:solr7 ${2}/conf/*
          rm -f ${Plr}/sites/${Dom}/files/solr/*
          touch ${2}/conf/.yes-custom.txt
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
      fi
    elif [ "${1}" = "search_api_solr" ] \
      && [ ! -e "${Plr}/sites/${Dom}/files/solr/schema.xml" ]; then
      if [ ! -e "${2}/conf/.protected.conf" ] \
        && [ ! -e "${2}/conf/.yes-custom.txt" ] \
        && [ -e "${2}/conf" ]; then
        check_config_diff "/data/conf/solr/search_api_solr/8/schema.xml" "${2}/conf/schema.xml"
        if [ ! -z "${slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/8/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown solr7:solr7 ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
        check_config_diff "/data/conf/solr/search_api_solr/8/solrcore.properties" "${2}/conf/solrcore.properties"
        if [ ! -z "${slrCnfUpdate}" ]; then
          rm -f ${2}/conf/*
          cp -af /data/conf/solr/search_api_solr/8/* ${2}/conf/
          chmod 644 ${2}/conf/*
          chown solr7:solr7 ${2}/conf/*
          touch ${2}/conf/.just-updated.pid
        else
          rm -f ${2}/conf/.just-updated.pid
          rm -f ${2}/conf/.yes-update.txt
        fi
      fi
    fi
    fiLe="${Dir}/solr.php"
    echo "Info file for ${Dom} is ${fiLe}"
    echo "Info _SERV is ${_SERV}"
    _SOLR_CONFIG_INFO_UPDATE=NO
    if [ -e "${fiLe}" ]; then
      _SOLR_CONFIG_INFO_TEST=$(grep "${SolrCoreID}" ${fiLe} 2>&1)
      if [[ ! "${_SOLR_CONFIG_INFO_TEST}" =~ "${SolrCoreID}" ]]; then
        _SOLR_CONFIG_INFO_UPDATE=YES
      fi
    fi
    if [ ! -e "${fiLe}" ] \
      || [ "${_SOLR_CONFIG_INFO_UPDATE}" = "YES" ] \
      || [ -e "${2}/conf/.just-updated.pid" ]; then
      if [[ "${2}" =~ "/opt/solr4" ]] && [ ! -z "${_SERV}" ]; then
        write_solr_config ${1} ${fiLe} ${_SERV}
        echo "Updated ${fiLe} with ${2} details"
        touch ${2}/conf/${_X_SE}.conf
        reload_core_cnf 8099 ${SolrCoreID}
      elif [[ "${2}" =~ "/var/solr7/data" ]] && [ ! -z "${_SERV}" ]; then
        write_solr_config ${1} ${fiLe} ${_SERV}
        echo "Updated ${fiLe} with ${2} details"
        touch ${2}/conf/${_X_SE}.conf
        reload_core_cnf 9077 ${SolrCoreID}
      fi
    fi
  fi
}

add_solr() {
  # ${1} is module
  # ${2} is solr core path
  if [ "${1}" = "apachesolr" ]; then
    _SOLR_BASE="/opt/solr4"
  elif [ "${1}" = "search_api_solr" ]; then
    _SOLR_BASE="/var/solr7/data"
  fi
  if [ ! -z "${1}" ] && [ ! -z "${2}" ] && [ -e "/data/conf/solr" ]; then
    if [ ! -e "${2}" ]; then
      if [ "${_SOLR_BASE}" = "/var/solr7/data" ] \
        && [ -x "/opt/solr7/bin/solr" ] \
        && [ -e "/var/solr7/data/solr.xml" ]; then
        if [ -e "${Plr}/modules/o_contrib_eight" ] \
          || [ -e "${Plr}/modules/o_contrib_nine" ] \
          || [ -e "${Plr}/modules/o_contrib_ten" ]; then
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${SolrCoreID} -d /data/conf/solr/search_api_solr/8"
          wait
        elif [ -e "${Plr}/modules/o_contrib_seven" ]; then
          su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr create_core -p 9077 -c ${SolrCoreID} -d /data/conf/solr/search_api_solr/7"
          wait
        else
          echo "The search_api_solr is supported only for Drupal 7 and newer!"
        fi
      else
        rm -rf ${_SOLR_BASE}/core0/data/*
        cp -a ${_SOLR_BASE}/core0 ${2}
        sed -i "s/.*name=\"${LegacySolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "s/.*name=\"${OldSolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "s/.*<core name=\"core0\" instanceDir=\"core0\" \/>.*/<core name=\"core0\" instanceDir=\"core0\" \/>\n<core name=\"${SolrCoreID}\" instanceDir=\"${SolrCoreID}\" \/>\n/g" ${_SOLR_BASE}/solr.xml
        wait
        sed -i "/^$/d" ${_SOLR_BASE}/solr.xml &> /dev/null
        wait
        if [[ "${_SOLR_BASE}" =~ "/opt/solr4" ]]; then
          kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
          service jetty9 start &> /dev/null
        fi
      fi
      echo "New Solr with ${1} for ${2} added"
    fi
    update_solr "${1}" "${2}"
  fi
}

delete_solr() {
  # ${1} is solr core path
  if [[ "${1}" =~ "solr4" ]]; then
    _SOLR_BASE="/opt/solr4"
  elif [[ "${1}" =~ "solr7" ]]; then
    _SOLR_BASE="/var/solr7/data"
  fi
  if [ ! -z "${1}" ] && [ -e "/data/conf/solr" ] && [ -e "${1}/conf" ]; then
    if [ "${_SOLR_BASE}" = "/var/solr7/data" ] \
      && [ -x "/opt/solr7/bin/solr" ] \
      && [ -e "/var/solr7/data/solr.xml" ]; then
      if [ -e "${_SOLR_BASE}/${SolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${SolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${OldSolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${OldSolrCoreID}"
        wait
      fi
      if [ -e "${_SOLR_BASE}/${LegacySolrCoreID}" ]; then
        su -s /bin/bash - solr7 -c "/opt/solr7/bin/solr delete -p 9077 -c ${LegacySolrCoreID}"
        wait
      fi
      rm -f ${Dir}/solr.php
    else
      sed -i "s/.*instanceDir=\"${SolrCoreID}\".*//g" ${_SOLR_BASE}/solr.xml
      wait
      sed -i "s/.*name=\"${LegacySolrCoreID}\".*//g"  ${_SOLR_BASE}/solr.xml
      wait
      sed -i "s/.*name=\"${OldSolrCoreID}\".*//g"     ${_SOLR_BASE}/solr.xml
      wait
      sed -i "/^$/d" ${_SOLR_BASE}/solr.xml &> /dev/null
      wait
      rm -rf ${1}
      rm -f ${Dir}/solr.php
      if [[ "${_SOLR_BASE}" =~ "/opt/solr4" ]]; then
        kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
        service jetty9 start &> /dev/null
      fi
    fi
    echo "Deleted Solr core in ${1}"
  fi
}

check_solr() {
  # ${1} is module
  # ${2} is solr core path
  if [ ! -z "${1}" ] && [ ! -z "${2}" ] && [ -e "/data/conf/solr" ]; then
    echo "Checking Solr with ${1} for ${2}"
    if [ ! -e "${2}" ]; then
      add_solr "${1}" "${2}"
    else
      update_solr "${1}" "${2}"
    fi
  fi
}

setup_solr() {
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
    if [ "${_SOLR_MODULE}" = "apachesolr" ]; then
      _SOLR_BASE="/opt/solr4"
    elif [ "${_SOLR_MODULE}" = "search_api_solr" ]; then
      _SOLR_BASE="/var/solr7/data"
    fi
    _SOLR_DIR="${_SOLR_BASE}/${SolrCoreID}"
    if [ "${_SOLR_MODULE}" = "search_api_solr" ] \
      || [ "${_SOLR_MODULE}" = "apachesolr" ]; then
      check_solr "${_SOLR_MODULE}" "${_SOLR_DIR}"
    else
      _SOLR_DIR_DEL="/opt/solr4/${SolrCoreID}"
      delete_solr "${_SOLR_DIR_DEL}"
      _SOLR_DIR_DEL="/var/solr7/data/${SolrCoreID}"
      delete_solr "${_SOLR_DIR_DEL}"
      _SOLR_DIR_DEL="/opt/solr4/${LegacySolrCoreID}"
      delete_solr "${_SOLR_DIR_DEL}"
      _SOLR_DIR_DEL="/var/solr7/data/${LegacySolrCoreID}"
      delete_solr "${_SOLR_DIR_DEL}"
      _SOLR_DIR_DEL="/opt/solr4/${OldSolrCoreID}"
      delete_solr "${_SOLR_DIR_DEL}"
      _SOLR_DIR_DEL="/var/solr7/data/${OldSolrCoreID}"
      delete_solr "${_SOLR_DIR_DEL}"
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
        update_solr "${_SOLR_MODULE}" "${_SOLR_DIR}"
      fi
    fi
  fi
}

proceed_solr() {
  if [ ! -z "${Dan}" ] \
    && [ "${Dan}" != "hostmaster" ]; then
    CoreID="${Dan}.${_HM_U}"
    CoreHS=$(echo ${CoreID} \
            | openssl md5 \
            | awk '{ print $2}' \
            | tr -d "\n" 2>&1)
    #SolrCoreID="${_HM_U}-${Dan}-${CoreHS}"
    LegacySolrCoreID="${_HM_U}.${Dan}"
    OldSolrCoreID="solr.${_HM_U}.${Dan}"
    SolrCoreID="oct.${_HM_U}.${Dan}"
    setup_solr
  fi
}

check_sites_list() {
  for Site in `find ${User}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _MOMENT=$(date +%y%m%d-%H%M%S 2>&1)
    echo ${_MOMENT} Start Checking Site $Site
    Dom=$(echo $Site | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    if [ -e "${User}/config/server_master/nginx/vhost.d/${Dom}" ]; then
      Plx=$(cat ${User}/config/server_master/nginx/vhost.d/${Dom} \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "$Plx" =~ "aegir/distro" ]]; then
        Dan="hostmaster"
      else
        Dan="${Dom}"
      fi
    fi
    _STATUS_DISABLED=NO
    _STATUS_TEST=$(grep "Do not reveal Aegir front-end URL here" \
      ${User}/config/server_master/nginx/vhost.d/${Dom} 2>&1)
    if [[ "${_STATUS_TEST}" =~ "Do not reveal Aegir front-end URL here" ]]; then
      _STATUS_DISABLED=YES
      echo "${Dom} site is DISABLED"
    fi
    if [ -e "${User}/.drush/${Dan}.alias.drushrc.php" ] \
      && [ "${_STATUS_DISABLED}" = "NO" ]; then
      Dir=$(cat ${User}/.drush/${Dan}.alias.drushrc.php \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _DIR_CTRL_F="${Dir}/modules/boa_site_control.ini"
      Plr=$(cat ${User}/.drush/${Dan}.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _PLR_CTRL_F="${Plr}/sites/all/modules/boa_platform_control.ini"
      proceed_solr
    fi
  done
}

count_cpu() {
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt "0" ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
  echo ${_CPU_NR} > /data/all/cpuinfo
  chmod 644 /data/all/cpuinfo &> /dev/null
}

load_control() {
  if [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
    _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  fi
  if [ -z "${_CPU_MAX_RATIO}" ]; then
    _CPU_MAX_RATIO=6
  fi
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
}

fix_solr7_cnf() {
  if [ -x "/etc/init.d/solr7" ] && [ -e "/var/solr7/logs" ]; then
    _IF_RESTART_SOLR=NO
    for pRp in `find /var/solr7/data/oct.*/conf/solrcore.properties -maxdepth 1 | sort`; do
      if [ -e "${pRp}" ]; then
        _PRP_TEST_ID=$(grep "solr7" ${pRp} 2>&1)
        if [[ ! "${_PRP_TEST_ID}" =~ "solr7" ]]; then
          sed -i "s/^solr\.install\.dir.*//g" ${pRp}
          sed -i "s/^solr\.contrib\.dir.*//g" ${pRp}
          echo "solr.install.dir=/opt/solr7" >> ${pRp}
          sed -i "/^$/d" ${pRp}
          echo "Fixed ${pRp}"
          _IF_RESTART_SOLR=YES
        fi
      fi
    done
    pRp="/var/xdrago/conf/solr/search_api_solr/7/solrcore.properties"
    if [ -e "${pRp}" ]; then
      _PRP_TEST_ID=$(grep "solr7" ${pRp} 2>&1)
      if [[ ! "${_PRP_TEST_ID}" =~ "solr7" ]]; then
        sed -i "s/^solr\.install\.dir.*//g" ${pRp}
        sed -i "s/^solr\.contrib\.dir.*//g" ${pRp}
        echo "solr.install.dir=/opt/solr7" >> ${pRp}
        sed -i "/^$/d" ${pRp}
        echo "Fixed ${pRp}"
        _IF_RESTART_SOLR=YES
      fi
    fi
    pRp="/var/xdrago/conf/solr/search_api_solr/8/solrcore.properties"
    if [ -e "${pRp}" ]; then
      _PRP_TEST_ID=$(grep "solr7" ${pRp} 2>&1)
      if [[ ! "${_PRP_TEST_ID}" =~ "solr7" ]]; then
        sed -i "s/^solr\.install\.dir.*//g" ${pRp}
        sed -i "s/^solr\.contrib\.dir.*//g" ${pRp}
        echo "solr.install.dir=/opt/solr7" >> ${pRp}
        sed -i "/^$/d" ${pRp}
        echo "Fixed ${pRp}"
        _IF_RESTART_SOLR=YES
      fi
    fi
    pRp="/data/conf/solr/search_api_solr/7/solrcore.properties"
    if [ -e "${pRp}" ]; then
      _PRP_TEST_ID=$(grep "solr7" ${pRp} 2>&1)
      if [[ ! "${_PRP_TEST_ID}" =~ "solr7" ]]; then
        sed -i "s/^solr\.install\.dir.*//g" ${pRp}
        sed -i "s/^solr\.contrib\.dir.*//g" ${pRp}
        echo "solr.install.dir=/opt/solr7" >> ${pRp}
        sed -i "/^$/d" ${pRp}
        echo "Fixed ${pRp}"
        _IF_RESTART_SOLR=YES
      fi
    fi
    pRp="/data/conf/solr/search_api_solr/8/solrcore.properties"
    if [ -e "${pRp}" ]; then
      _PRP_TEST_ID=$(grep "solr7" ${pRp} 2>&1)
      if [[ ! "${_PRP_TEST_ID}" =~ "solr7" ]]; then
        sed -i "s/^solr\.install\.dir.*//g" ${pRp}
        sed -i "s/^solr\.contrib\.dir.*//g" ${pRp}
        echo "solr.install.dir=/opt/solr7" >> ${pRp}
        sed -i "/^$/d" ${pRp}
        echo "Fixed ${pRp}"
        _IF_RESTART_SOLR=YES
      fi
    fi
    rStart="/var/solr7/logs/.restarted_fix_solr7_cnf.txt"
    if [ "${_IF_RESTART_SOLR}" = "YES" ] \
      || [ ! -e "${rStart}" ]; then
      echo "Restarting Solr 7..."
      #kill -9 $(ps aux | grep '[s]olr' | awk '{print $2}') &> /dev/null
      service solr7 restart
      touch ${rStart}
    fi
  fi
}
start_up() {
  fix_solr7_cnf
  if [ -d "/var/xdrago/conf/solr/search_api_solr/8" ]; then
    baseCpy="/var/xdrago/conf/solr/search_api_solr/8/schema.xml"
    liveCpy="/data/conf/solr/search_api_solr/8/schema.xml"
    check_config_diff "${baseCpy}" "${liveCpy}"
    if [ ! -e "/data/conf/solr/search_api_solr/8/solrconfig_extra.xml" ] \
      || [ ! -e "/data/conf/solr/.ctrl.${_X_SE}.pid" ] \
      || [ ! -z "${slrCnfUpdate}" ]; then
      rm -rf /data/conf/solr
      cp -af /var/xdrago/conf/solr /data/conf/
      rm -f /data/conf/solr/.ctrl*
      touch /data/conf/solr/.ctrl.${_X_SE}.pid
    fi
  fi
  if [ -d "/var/xdrago/conf/solr/search_api_solr/7" ]; then
    baseCpy="/var/xdrago/conf/solr/search_api_solr/7/schema.xml"
    liveCpy="/data/conf/solr/search_api_solr/7/schema.xml"
    check_config_diff "${baseCpy}" "${liveCpy}"
    if [ ! -e "/data/conf/solr/search_api_solr/7/solrconfig_extra.xml" ] \
      || [ ! -e "/data/conf/solr/.ctrl.${_X_SE}.pid" ] \
      || [ ! -z "${slrCnfUpdate}" ]; then
      rm -rf /data/conf/solr
      cp -af /var/xdrago/conf/solr /data/conf/
      rm -f /data/conf/solr/.ctrl*
      touch /data/conf/solr/.ctrl.${_X_SE}.pid
    fi
  fi
  if [ -d "/var/xdrago/conf/solr/apachesolr/7" ]; then
    baseCpy="/var/xdrago/conf/solr/apachesolr/7/schema.xml"
    liveCpy="/data/conf/solr/apachesolr/7/schema.xml"
    check_config_diff "${baseCpy}" "${liveCpy}"
    if [ ! -e "/data/conf/solr/apachesolr/7/solrconfig_extra.xml" ] \
      || [ ! -e "/data/conf/solr/.ctrl.${_X_SE}.pid" ] \
      || [ ! -z "${slrCnfUpdate}" ]; then
      rm -rf /data/conf/solr
      cp -af /var/xdrago/conf/solr /data/conf/
      rm -f /data/conf/solr/.ctrl*
      touch /data/conf/solr/.ctrl.${_X_SE}.pid
    fi
  fi
  for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    count_cpu
    load_control
    if [ -e "${User}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${User}/log/proxied.pid" ] \
      && [ ! -e "${User}/log/CANCELLED" ]; then
      if [ "${_O_LOAD}" -lt "${_O_LOAD_MAX}" ]; then
        _HM_U=$(echo ${User} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _THIS_HM_SITE=$(cat ${User}/.drush/hostmaster.alias.drushrc.php \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "User ${User}"
        mkdir -p ${User}/log/ctrl
        if [ -e "/root/.${_HM_U}.octopus.cnf" ]; then
          source /root/.${_HM_U}.octopus.cnf
          _MY_EMAIL=${_MY_EMAIL//\\\@/\@}
        fi
        check_sites_list
      fi
    fi
  done
}

_NOW=$(date +%y%m%d-%H%M%S 2>&1)
_NOW=${_NOW//[^0-9-]/}
mkdir -p /var/backups/solr/log
find /var/backups/solr/*/* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
start_up >/var/backups/solr/log/solr-${_NOW}.log 2>&1
exit 0
