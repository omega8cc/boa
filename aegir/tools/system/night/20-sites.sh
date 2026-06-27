#!/bin/bash

###
### 20-sites.sh -- per-site (per-vhost) maintenance procedures for one Octopus
### account, plus the per-site loop driver _daily_process. Carved out of daily.sh
### (Phase 1 of the owl.sh/night split). Today it is SOURCED by daily.sh and the
### per-site loop is still driven inline by _daily_action; it becomes a standalone
### per-account worker (invoked with the account path) in a later phase, once the
### run-freeze contract that carries _NOW and the other per-run state across a
### process boundary is in place.
###
### Reads the per-run / per-account / per-site ambient variables set by the caller
### (_NOW, _DOW, _xSrl, _O_CONTRIB*, _MODULES_*, the _usEr/_HM_U/_Dom/_Dir/_Plr
### loop vars, etc.) and the shared helpers in night.inc.sh (drush8 wrappers,
### chattr, load + pure helpers). NB: _le_ssl_check_update calls _apt_clean_update,
### which is still provided by daily.sh in this phase; it moves to night.inc.sh
### when this script runs standalone.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh

_check_if_required_with_drush8() {
  _REQ=YES
  _REI_TEST=$(_run_drush8_nosilent_cmd "pmi $1 --fields=required_by" 2>&1)
  _REL_TEST=$(echo "${_REI_TEST}" | grep "Required by" 2>&1)
  if [[ "${_REL_TEST}" =~ "was not found" ]]; then
    _REQ=NULL
    echo "_REQ for $1 is ${_REQ} in ${_Dom} == null == via ${_REL_TEST}"
  else
    echo "CTRL _REL_TEST _REQ for $1 is ${_REQ} in ${_Dom} == init == via ${_REL_TEST}"
    _REN_TEST=$(echo "${_REI_TEST}" | grep "Required by.*:.*none" 2>&1)
    if [[ "${_REN_TEST}" =~ "Required by" ]]; then
      _REQ=NO
      echo "_REQ for $1 is ${_REQ} in ${_Dom} == 0 == via ${_REN_TEST}"
    else
      echo "CTRL _REN_TEST _REQ for $1 is ${_REQ} in ${_Dom} == 1 == via ${_REN_TEST}"
      _REM_TEST=$(echo "${_REI_TEST}" | grep "Required by.*minimal" 2>&1)
      if [[ "${_REM_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 2 == via ${_REM_TEST}"
      fi
      _RES_TEST=$(echo "${_REI_TEST}" | grep "Required by.*standard" 2>&1)
      if [[ "${_RES_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 3 == via ${_RES_TEST}"
      fi
      _RET_TEST=$(echo "${_REI_TEST}" | grep "Required by.*testing" 2>&1)
      if [[ "${_RET_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${_Dom} == 4 == via ${_RET_TEST}"
      fi
      _REH_TEST=$(echo "${_REI_TEST}" | grep "Required by.*hacked" 2>&1)
      if [[ "${_REH_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${_Dom} == 5 == via ${_REH_TEST}"
      fi
      _RED_TEST=$(echo "${_REI_TEST}" | grep "Required by.*devel" 2>&1)
      if [[ "${_RED_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${_Dom} == 6 == via ${_RED_TEST}"
      fi
      _REW_TEST=$(echo "${_REI_TEST}" | grep "Required by.*watchdog_live" 2>&1)
      if [[ "${_REW_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${_Dom} == 7 == via ${_REW_TEST}"
      fi
    fi
    _Profile=$(_run_drush8_nosilent_cmd "${_vGet} ^install_profile$" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    _Profile=${_Profile//[^a-z_]/}
    echo "_Profile is == ${_Profile} =="
    if [ ! -z "${_Profile}" ]; then
      _REP_TEST=$(echo "${_REI_TEST}" | grep "Required by.*:.*${_Profile}" 2>&1)
      if [[ "${_REP_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 8 == via ${_REP_TEST}"
      else
        echo "CTRL _REP_TEST _REQ for $1 is ${_REQ} in ${_Dom} == 9 == via ${_REP_TEST}"
      fi
    fi
    _REA_TEST=$(echo "${_REI_TEST}" | grep "Required by.*apps" 2>&1)
    if [[ "${_REA_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${_Dom} == 10 == via ${_REA_TEST}"
    fi
    _REF_TEST=$(echo "${_REI_TEST}" | grep "Required by.*features" 2>&1)
    if [[ "${_REF_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${_Dom} == 11 == via ${_REF_TEST}"
    fi
  fi
}

_check_if_skip() {
  for s in ${_MODULES_SKIP}; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ]; then
      _SKIP=YES
      #echo $1 is whitelisted and will not be disabled in ${_Dom}
    fi
  done
}

_check_if_force() {
  for s in ${_MODULES_FORCE}; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ]; then
      _FORCE=YES
      echo $1 is blacklisted and will be forcefully disabled in ${_Dom}
    fi
  done
}

_disable_modules_with_drush8() {
  for m in $1; do
    _SKIP=NO
    _FORCE=NO
    if [ ! -z "${_MODULES_SKIP}" ]; then
      _check_if_skip "$m"
    fi
    if [ ! -z "${_MODULES_FORCE}" ]; then
      _check_if_force "$m"
    fi
    if [ "${_SKIP}" = "NO" ]; then
      _MODULE_T=$(_run_drush8_nosilent_cmd "pml --status=enabled \
        --type=module | grep \($m\)" 2>&1)
      if [[ "${_MODULE_T}" =~ "($m)" ]]; then
        if [ "${_FORCE}" = "NO" ]; then
          _check_if_required_with_drush8 "$m"
        else
          echo "$m dependencies not checked in ${_Dom} action forced"
          _REQ=FCE
        fi
        if [ "${_REQ}" = "FCE" ]; then
          _run_drush8_cmd "dis $m -y"
          echo "$m FCE disabled in ${_Dom}"
        elif [ "${_REQ}" = "NO" ]; then
          _run_drush8_cmd "dis $m -y"
          echo "$m disabled in ${_Dom}"
        elif [ "${_REQ}" = "NULL" ]; then
          echo "$m is not used in ${_Dom}"
        else
          echo "$m is required and can not be disabled in ${_Dom}"
        fi
      fi
    fi
  done
}

_enable_modules_with_drush8() {
  for m in $1; do
    _MODULE_T=$(_run_drush8_nosilent_cmd "pml --status=enabled \
      --type=module | grep \($m\)" 2>&1)
    if [[ "${_MODULE_T}" =~ "($m)" ]]; then
      _DO_NOTHING=YES
    else
      _run_drush8_cmd "en $m -y"
      echo "$m enabled in ${_Dom}"
    fi
  done
}

_sync_user_register_protection_ini_vars() {
  _IGNORE_USER_REGISTER_PROTECTION=NO
  _ENABLE_STRICT_USER_REGISTER_PROTECTION=NO
  if [ -e "/data/conf/default.boa_platform_control.ini" ] \
    && [ ! -e "${_PLR_CTRL_F}" ]; then
    cp -af /data/conf/default.boa_platform_control.ini \
      ${_PLR_CTRL_F} &> /dev/null
    chown ${_HM_U}:users ${_PLR_CTRL_F} &> /dev/null
    chmod 0664 ${_PLR_CTRL_F} &> /dev/null
  fi
  if [ -e "${_PLR_CTRL_F}" ]; then
    _EN_URP_T_S=$(grep "^enable_strict_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    _EN_URP_T=$(grep "^enable_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_EN_URP_T_S}" =~ "enable_strict_user_register_protection = TRUE" ]] \
      || [[ "${_EN_URP_T}" =~ "enable_user_register_protection = TRUE" ]]; then
      _ENABLE_STRICT_USER_REGISTER_PROTECTION=YES
    fi
    _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    _DIS_URP_T_I=$(grep "^ignore_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]] \
      || [[ "${_DIS_URP_T_I}" =~ "ignore_user_register_protection = TRUE" ]]; then
      _IGNORE_USER_REGISTER_PROTECTION=YES
    fi
  fi
  if [ -e "${_usEr}/static/control/enable_user_register_protection.info" ]; then
    mv -f ${_usEr}/static/control/enable_user_register_protection.info \
      ${_usEr}/static/control/enable_strict_user_register_protection.info
  fi
  if [ -e "${_usEr}/static/control/disable_user_register_protection.info" ]; then
    mv -f ${_usEr}/static/control/disable_user_register_protection.info \
      ${_usEr}/static/control/ignore_user_register_protection.info
  fi
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ -e "${_usEr}/static/control/enable_strict_user_register_protection.info" ]; then
    sed -i "s/.*enable.*user_register_protection.*/enable_strict_user_register_protection = TRUE/g" \
      ${_PLR_CTRL_F} &> /dev/null
    wait
    _ENABLE_STRICT_USER_REGISTER_PROTECTION=YES
  fi
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ] \
    && [ -e "${_usEr}/static/control/ignore_user_register_protection.info" ]; then
    sed -i "s/.*enable.*user_register_protection.*/enable_strict_user_register_protection = FALSE/g" \
      ${_PLR_CTRL_F} &> /dev/null
    wait
    _IGNORE_USER_REGISTER_PROTECTION=YES
  fi
  if [ -e "/data/conf/default.boa_site_control.ini" ] \
    && [ ! -e "${_DIR_CTRL_F}" ]; then
    cp -af /data/conf/default.boa_site_control.ini ${_DIR_CTRL_F} &> /dev/null
    chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
    chmod 0664 ${_DIR_CTRL_F} &> /dev/null
  fi
  if [ -e "${_DIR_CTRL_F}" ]; then
    _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
      ${_DIR_CTRL_F} 2>&1)
    _DIS_URP_T_I=$(grep "^ignore_user_register_protection = TRUE" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]] \
      || [[ "${_DIS_URP_T_I}" =~ "ignore_user_register_protection = TRUE" ]]; then
      _IGNORE_USER_REGISTER_PROTECTION=YES
    fi
  fi
  if [ -e "${_usEr}/static/control/ignore_user_register_protection.info" ]; then
    _IGNORE_USER_REGISTER_PROTECTION=YES
  fi
}

_fix_user_register_protection_with_vSet() {
  _sync_user_register_protection_ini_vars
  if [ "${_IGNORE_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ ! -e "${_Plr}/core" ]; then
    _Prm=$(_run_drush8_nosilent_cmd "${_vGet} ^user_register$" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    _Prm=${_Prm//[^0-2]/}
    echo "_Prm user_register for ${_Dom} is ${_Prm}"
    if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ]; then
      _run_drush8_cmd "${_vSet} user_register 0"
      echo "_Prm user_register for ${_Dom} set to 0"
    else
      if [ "${_Prm}" = "1" ] || [ -z "${_Prm}" ]; then
        _run_drush8_cmd "${_vSet} user_register 2"
        echo "_Prm user_register for ${_Dom} set to 2"
      fi
      _run_drush8_cmd "${_vSet} user_email_verification 1"
      echo "_Prm user_email_verification for ${_Dom} set to 1"
    fi
  fi
}

_fix_llms_txt() {
  find ${_Dir}/files/llms.txt -mtime +6 -exec rm -f {} \; &> /dev/null
  if [ ! -e "${_Dir}/files/llms.txt" ] \
    && [ ! -e "${_Plr}/profiles/hostmaster" ]; then
    curl -L --max-redirs 10 -k -s --retry 2 --retry-delay 5 \
      -A iCab "http://${_Dom}/llms.txt?nocache=1&noredis=1" \
      -o ${_Dir}/files/llms.txt
    if [ -e "${_Dir}/files/llms.txt" ]; then
      echo >> ${_Dir}/files/llms.txt
    fi
  fi
  _VAR_IF_PRESENT=
  if [ -f "${_Dir}/files/llms.txt" ]; then
    _VAR_IF_PRESENT=$(grep "##" ${_Dir}/files/llms.txt 2>&1)
  fi
  if [[ ! "${_VAR_IF_PRESENT}" =~ "##" ]]; then
    rm -f ${_Dir}/files/llms.txt
  else
    chown ${_HM_U}:www-data ${_Dir}/files/llms.txt &> /dev/null
    chmod 0664 ${_Dir}/files/llms.txt &> /dev/null
    if [ -f "${_Plr}/llms.txt" ] || [ -L "${_Plr}/llms.txt" ]; then
      rm -f ${_Plr}/llms.txt
    fi
  fi
}

_fix_robots_txt() {
  find ${_Dir}/files/robots.txt -mtime +6 -exec rm -f {} \; &> /dev/null
  if [ ! -e "${_Dir}/files/robots.txt" ] \
    && [ ! -e "${_Plr}/profiles/hostmaster" ]; then
    curl -L --max-redirs 10 -k -s --retry 2 --retry-delay 5 \
      -A iCab "http://${_Dom}/robots.txt?nocache=1&noredis=1" \
      -o ${_Dir}/files/robots.txt
    if [ -e "${_Dir}/files/robots.txt" ]; then
      echo >> ${_Dir}/files/robots.txt
    fi
  fi
  _VAR_IF_PRESENT=
  if [ -f "${_Dir}/files/robots.txt" ]; then
    _VAR_IF_PRESENT=$(grep "Disallow:" ${_Dir}/files/robots.txt 2>&1)
  fi
  if [[ ! "${_VAR_IF_PRESENT}" =~ "Disallow:" ]]; then
    rm -f ${_Dir}/files/robots.txt
  else
    chown ${_HM_U}:www-data ${_Dir}/files/robots.txt &> /dev/null
    chmod 0664 ${_Dir}/files/robots.txt &> /dev/null
    if [ -f "${_Plr}/robots.txt" ] || [ -L "${_Plr}/robots.txt" ]; then
      rm -f ${_Plr}/robots.txt
    fi
  fi
}

_fix_boost_cache() {
  if [ -e "${_Plr}/cache" ]; then
    rm -rf ${_Plr}/cache/*
    rm -f ${_Plr}/cache/{.boost,.htaccess}
  else
    if [ -e "${_Plr}/sites/all/drush/drushrc.php" ]; then
      mkdir -p ${_Plr}/cache
    fi
  fi
  if [ -e "${_Plr}/cache" ]; then
    chown ${_HM_U}:www-data ${_Plr}/cache &> /dev/null
    chmod 02775 ${_Plr}/cache &> /dev/null
  fi
}

_fix_o_contrib_symlink() {
  if [ "${_O_CONTRIB_SEVEN}" != "NO" ]; then
    symlinks -d ${_Plr}/modules &> /dev/null
    if [ -e "${_Plr}/web.config" ] \
      && [ -e "${_O_CONTRIB_SEVEN}" ] \
      && [ ! -e "${_Plr}/core" ]; then
      if [ ! -e "${_Plr}/modules/o_contrib_seven" ]; then
        ln -sfn ${_O_CONTRIB_SEVEN} ${_Plr}/modules/o_contrib_seven &> /dev/null
      fi
    elif [ -e "${_Plr}/core" ] \
      && [ ! -e "${_Plr}/core/themes/olivero" ] \
      && [ ! -e "${_Plr}/core/themes/stable9" ] \
      && [ ! -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_EIGHT}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_nine" ] \
        || [ -e "${_Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_nine
        rm -f ${_Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_ten" ] \
        || [ -e "${_Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_ten
        rm -f ${_Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_eleven" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eleven_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eleven
        rm -f ${_Plr}/modules/.o_contrib_eleven_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_eight" ]; then
        ln -sfn ${_O_CONTRIB_EIGHT} ${_Plr}/modules/o_contrib_eight &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ -e "${_Plr}/core/themes/classy" ] \
      && [ ! -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_NINE}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_eight" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eight
        rm -f ${_Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_ten" ] \
        || [ -e "${_Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_ten
        rm -f ${_Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_eleven" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eleven_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eleven
        rm -f ${_Plr}/modules/.o_contrib_eleven_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_nine" ]; then
        ln -sfn ${_O_CONTRIB_NINE} ${_Plr}/modules/o_contrib_nine &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ ! -e "${_Plr}/core/themes/classy" ] \
      && [ ! -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_TEN}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_eight" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eight
        rm -f ${_Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_nine" ] \
        || [ -e "${_Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_nine
        rm -f ${_Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_eleven" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eleven_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eleven
        rm -f ${_Plr}/modules/.o_contrib_eleven_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_ten" ]; then
        ln -sfn ${_O_CONTRIB_TEN} ${_Plr}/modules/o_contrib_ten &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ ! -e "${_Plr}/core/themes/classy" ] \
      && [ -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_ELEVEN}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_eight" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eight
        rm -f ${_Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_nine" ] \
        || [ -e "${_Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_nine
        rm -f ${_Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_ten" ] \
        || [ -e "${_Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_ten
        rm -f ${_Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_eleven" ]; then
        ln -sfn ${_O_CONTRIB_ELEVEN} ${_Plr}/modules/o_contrib_eleven &> /dev/null
      fi
    else
      if [ -e "${_Plr}/modules/watchdog" ]; then
        if [ -e "${_Plr}/modules/o_contrib" ]; then
          rm -f ${_Plr}/modules/o_contrib &> /dev/null
        fi
      else
        if [ ! -e "${_Plr}/modules/o_contrib" ] \
          && [ -e "${_O_CONTRIB}" ]; then
          ln -sfn ${_O_CONTRIB} ${_Plr}/modules/o_contrib &> /dev/null
        fi
      fi
    fi
  fi
}

_sql_convert() {
  sudo -u ${_HM_U}.ftp -H /opt/local/bin/sqlmagic convert @${_Dom} to-${_SQL_CONVERT}
}

_fix_modules() {
  _AUTO_CONFIG_ADVAGG=NO
  if [ -e "${_Plr}/modules/o_contrib/advagg" ] \
    || [ -e "${_Plr}/modules/o_contrib_seven/advagg" ]; then
    _MODULE_T=$(_run_drush8_nosilent_cmd "pml --status=enabled \
      --type=module | grep \(advagg\)" 2>&1)
    if [[ "${_MODULE_T}" =~ "(advagg)" ]]; then
      _AUTO_CONFIG_ADVAGG=YES
    fi
  fi
  if [ "${_AUTO_CONFIG_ADVAGG}" = "YES" ]; then
    if [ -e "/data/conf/default.boa_site_control.ini" ] \
      && [ ! -e "${_DIR_CTRL_F}" ]; then
      cp -af /data/conf/default.boa_site_control.ini \
        ${_DIR_CTRL_F} &> /dev/null
      chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
      chmod 0664 ${_DIR_CTRL_F} &> /dev/null
    fi
    if [ -e "${_DIR_CTRL_F}" ]; then
      _AGG_P=$(grep "advagg_auto_configuration" ${_DIR_CTRL_F} 2>&1)
      _AGG_T=$(grep "^advagg_auto_configuration = TRUE" ${_DIR_CTRL_F} 2>&1)
      if [[ "${_AGG_T}" =~ "advagg_auto_configuration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the site level ini file.
        ###
        if [[ "${_AGG_P}" =~ "advagg_auto_configuration" ]]; then
          sed -i "s/.*advagg_auto_c.*/advagg_auto_configuration = TRUE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        else
          echo "advagg_auto_configuration = TRUE" >> ${_DIR_CTRL_F}
        fi
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_site_control.ini" ] \
      && [ ! -e "${_DIR_CTRL_F}" ]; then
      cp -af /data/conf/default.boa_site_control.ini \
        ${_DIR_CTRL_F} &> /dev/null
      chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
      chmod 0664 ${_DIR_CTRL_F} &> /dev/null
    fi
    if [ -e "${_DIR_CTRL_F}" ]; then
      _AGG_P=$(grep "advagg_auto_configuration" ${_DIR_CTRL_F} 2>&1)
      _AGG_T=$(grep "^advagg_auto_configuration = FALSE" \
        ${_DIR_CTRL_F} 2>&1)
      if [[ "${_AGG_T}" =~ "advagg_auto_configuration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        if [[ "${_AGG_P}" =~ "advagg_auto_configuration" ]]; then
          sed -i "s/.*advagg_auto_c.*/advagg_auto_configuration = FALSE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        else
          echo ";advagg_auto_configuration = FALSE" >> ${_DIR_CTRL_F}
        fi
      fi
    fi
  fi

  if [ -e "${_Plr}/modules/o_contrib_seven" ] \
    && [ ! -e "${_Plr}/core" ]; then
    _PRIV_TEST=$(_run_drush8_nosilent_cmd "${_vGet} ^file_default_scheme$" 2>&1)
    if [[ "${_PRIV_TEST}" =~ "No matching variable" ]]; then
      _PRIV_TEST_RESULT=NONE
    else
      _PRIV_TEST_RESULT=OK
    fi
    _AUTO_CNF_PF_DL=NO
    if [ "${_PRIV_TEST_RESULT}" = "OK" ]; then
      _Pri=$(_run_drush8_nosilent_cmd "${_vGet} ^file_default_scheme$" \
        | cut -d: -f2 \
        | awk '{ print $1}' \
        | sed "s/['\"]//g" \
        | tr -d "\n" 2>&1)
      _Pri=${_Pri//[^a-z]/}
      if [ "${_Pri}" = "private" ] || [ "${_Pri}" = "public" ]; then
        echo _Pri file_default_scheme for ${_Dom} is ${_Pri}
      fi
      if [ "${_Pri}" = "private" ]; then
        _AUTO_CNF_PF_DL=YES
      fi
    fi
    if [ "${_AUTO_CNF_PF_DL}" = "YES" ]; then
      if [ -e "/data/conf/default.boa_site_control.ini" ] \
        && [ ! -e "${_DIR_CTRL_F}" ]; then
        cp -af /data/conf/default.boa_site_control.ini \
          ${_DIR_CTRL_F} &> /dev/null
        chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
        chmod 0664 ${_DIR_CTRL_F} &> /dev/null
      fi
      if [ -e "${_DIR_CTRL_F}" ]; then
        _AC_PFD_T=$(grep "^allow_private_file_downloads = TRUE" \
          ${_DIR_CTRL_F} 2>&1)
        if [[ "${_AC_PFD_T}" =~ "allow_private_file_downloads = TRUE" ]]; then
          _DO_NOTHING=YES
        else
          ###
          ### Do this only for the site level ini file.
          ###
          sed -i "s/.*allow_private_f.*/allow_private_file_downloads = TRUE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        fi
      fi
    else
      if [ -e "/data/conf/default.boa_site_control.ini" ] \
        && [ ! -e "${_DIR_CTRL_F}" ]; then
        cp -af /data/conf/default.boa_site_control.ini \
          ${_DIR_CTRL_F} &> /dev/null
        chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
        chmod 0664 ${_DIR_CTRL_F} &> /dev/null
      fi
      if [ -e "${_DIR_CTRL_F}" ]; then
        _AC_PFD_T=$(grep "^allow_private_file_downloads = FALSE" \
          ${_DIR_CTRL_F} 2>&1)
        if [[ "${_AC_PFD_T}" =~ "allow_private_file_downloads = FALSE" ]]; then
          _DO_NOTHING=YES
        else
          sed -i "s/.*allow_private_f.*/allow_private_file_downloads = FALSE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        fi
      fi
    fi
  fi

  _AUTO_DT_FB_INT=NO
  if [ -e "${_Plr}/sites/all/modules/fb/fb_settings.inc" ] \
    || [ -e "${_Plr}/sites/all/modules/contrib/fb/fb_settings.inc" ]; then
    _AUTO_DT_FB_INT=YES
  else
    _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/fb/fb_settings.inc"
    if [ "${_FILE_EXISTS}" = "YES" ]; then
      _AUTO_DT_FB_INT=YES
    else
      _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/contrib/fb/fb_settings.inc"
      if [ "${_FILE_EXISTS}" = "YES" ]; then
        _AUTO_DT_FB_INT=YES
      fi
    fi
  fi
  if [ "${_AUTO_DT_FB_INT}" = "YES" ]; then
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      cp -af /data/conf/default.boa_platform_control.ini \
        ${_PLR_CTRL_F} &> /dev/null
      chown ${_HM_U}:users ${_PLR_CTRL_F} &> /dev/null
      chmod 0664 ${_PLR_CTRL_F} &> /dev/null
    fi
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_FB_T=$(grep "^auto_detect_facebook_integration = TRUE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_FB_T}" =~ "auto_detect_facebook_integration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the platform level ini file, so the site
        ### level ini file can disable this check by setting it
        ### explicitly to auto_detect_facebook_integration = FALSE
        ###
        sed -i "s/.*auto_detect_face.*/auto_detect_facebook_integration = TRUE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      cp -af /data/conf/default.boa_platform_control.ini \
        ${_PLR_CTRL_F} &> /dev/null
      chown ${_HM_U}:users ${_PLR_CTRL_F} &> /dev/null
      chmod 0664 ${_PLR_CTRL_F} &> /dev/null
    fi
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_FB_T=$(grep "^auto_detect_facebook_integration = FALSE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_FB_T}" =~ "auto_detect_facebook_integration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        sed -i "s/.*auto_detect_face.*/auto_detect_facebook_integration = FALSE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
      fi
    fi
  fi

  _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=NO
  if [ -e "${_Plr}/sites/all/modules/domain/settings.inc" ] \
    || [ -e "${_Plr}/sites/all/modules/contrib/domain/settings.inc" ]; then
    _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
  else
    _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/domain/settings.inc"
    if [ "${_FILE_EXISTS}" = "YES" ]; then
      _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
    else
      _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/contrib/domain/settings.inc"
      if [ "${_FILE_EXISTS}" = "YES" ]; then
        _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
      fi
    fi
  fi
  if [ "${_AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION}" = "YES" ]; then
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      cp -af /data/conf/default.boa_platform_control.ini \
        ${_PLR_CTRL_F} &> /dev/null
      chown ${_HM_U}:users ${_PLR_CTRL_F} &> /dev/null
      chmod 0664 ${_PLR_CTRL_F} &> /dev/null
    fi
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_DA_T=$(grep "^auto_detect_domain_access_integration = TRUE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_DA_T}" =~ "auto_detect_domain_access_integration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the platform level ini file, so the site
        ### level ini file can disable this check by setting it
        ### explicitly to auto_detect_domain_access_integration = FALSE
        ###
        sed -i "s/.*auto_detect_domain.*/auto_detect_domain_access_integration = TRUE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      cp -af /data/conf/default.boa_platform_control.ini \
        ${_PLR_CTRL_F} &> /dev/null
      chown ${_HM_U}:users ${_PLR_CTRL_F} &> /dev/null
      chmod 0664 ${_PLR_CTRL_F} &> /dev/null
    fi
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_DA_T=$(grep "^auto_detect_domain_access_integration = FALSE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_DA_T}" =~ "auto_detect_domain_access_integration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        sed -i "s/.*auto_detect_domain.*/auto_detect_domain_access_integration = FALSE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
      fi
    fi
  fi

  ###
  ### Add new INI variables if missing
  ###
  if [ -e "${_PLR_CTRL_F}" ]; then
    _VAR_IF_PRESENT=$(grep "session_cookie_ttl" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_cookie_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_cookie_ttl = 86400" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "session_gc_eol" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_gc_eol" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_gc_eol = 86400" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "enable_newrelic_integration" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "enable_newrelic_integration" ]]; then
      _DO_NOTHING=YES
    else
      echo ";enable_newrelic_integration = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_nine_mode" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_nine_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_nine_mode = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_eight_mode" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_eight_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_eight_mode = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_forced_mode" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_forced_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_forced_mode = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_lock_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_lock_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_lock_enable = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_path_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_path_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_path_enable = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_scan_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_scan_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_scan_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_exclude_bins" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_exclude_bins" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_exclude_bins = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "speed_booster_anon_cache_ttl" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "speed_booster_anon_cache_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";speed_booster_anon_cache_ttl = 10" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "disable_drupal_page_cache" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "disable_drupal_page_cache" ]]; then
      _DO_NOTHING=YES
    else
      echo ";disable_drupal_page_cache = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "allow_private_file_downloads" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "allow_private_file_downloads" ]]; then
      _DO_NOTHING=YES
    else
      echo ";allow_private_file_downloads = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "entitycache_dont_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "entitycache_dont_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";entitycache_dont_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "views_cache_bully_dont_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "views_cache_bully_dont_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";views_cache_bully_dont_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "views_content_cache_dont_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "views_content_cache_dont_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";views_content_cache_dont_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "set_composer_manager_vendor_dir" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "set_composer_manager_vendor_dir" ]]; then
      _DO_NOTHING=YES
    else
      echo ";set_composer_manager_vendor_dir = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_connect_timeout" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_connect_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_connect_timeout = 0.7" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_read_timeout" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_read_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_read_timeout = 0.7" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_backoff_ttl" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_backoff_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_backoff_ttl = 15" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_probe_retry" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_probe_retry" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_probe_retry = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_apcu_on_recovery" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_apcu_on_recovery" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_apcu_on_recovery = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_debug_header" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_debug_header" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug_header = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep -E "^;?redis_debug[ =]" ${_PLR_CTRL_F} 2>&1)
    if [[ -n "${_VAR_IF_PRESENT}" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug = FALSE" >> ${_PLR_CTRL_F}
    fi
  fi
  if [ -e "${_DIR_CTRL_F}" ]; then
     _VAR_IF_PRESENT=$(grep "session_cookie_ttl" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_cookie_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_cookie_ttl = 86400" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "session_gc_eol" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_gc_eol" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_gc_eol = 86400" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "enable_newrelic_integration" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "enable_newrelic_integration" ]]; then
      _DO_NOTHING=YES
    else
      echo ";enable_newrelic_integration = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_nine_mode" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_nine_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_nine_mode = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_eight_mode" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_eight_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_eight_mode = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_forced_mode" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_forced_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_forced_mode = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_lock_enable" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_lock_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_lock_enable = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_path_enable" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_path_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_path_enable = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_scan_enable" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_scan_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_scan_enable = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_exclude_bins" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_exclude_bins" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_exclude_bins = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "speed_booster_anon_cache_ttl" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "speed_booster_anon_cache_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";speed_booster_anon_cache_ttl = 10" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "disable_drupal_page_cache" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "disable_drupal_page_cache" ]]; then
      _DO_NOTHING=YES
    else
      echo ";disable_drupal_page_cache = FALSE" >> ${_DIR_CTRL_F}
    fi
     _VAR_IF_PRESENT=$(grep "allow_private_file_downloads" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "allow_private_file_downloads" ]]; then
      _DO_NOTHING=YES
    else
      echo ";allow_private_file_downloads = FALSE" >> ${_DIR_CTRL_F}
    fi
     _VAR_IF_PRESENT=$(grep "set_composer_manager_vendor_dir" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "set_composer_manager_vendor_dir" ]]; then
      _DO_NOTHING=YES
    else
      echo ";set_composer_manager_vendor_dir = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_connect_timeout" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_connect_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_connect_timeout = 0.7" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_read_timeout" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_read_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_read_timeout = 0.7" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_backoff_ttl" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_backoff_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_backoff_ttl = 15" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_probe_retry" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_probe_retry" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_probe_retry = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_apcu_on_recovery" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_apcu_on_recovery" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_apcu_on_recovery = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_debug_header" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_debug_header" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug_header = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep -E "^;?redis_debug[ =]" ${_DIR_CTRL_F} 2>&1)
    if [[ -n "${_VAR_IF_PRESENT}" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug = FALSE" >> ${_DIR_CTRL_F}
    fi
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _EC_DE_T=$(grep "^entitycache_dont_enable = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_EC_DE_T}" =~ "entitycache_dont_enable = TRUE" ]] \
      || [ -e "${_Plr}/profiles/commons" ]; then
      _ENTITYCACHE_DONT_ENABLE=YES
    else
      _ENTITYCACHE_DONT_ENABLE=NO
    fi
  else
    _ENTITYCACHE_DONT_ENABLE=NO
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _VCB_DE_T=$(grep "^views_cache_bully_dont_enable = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VCB_DE_T}" =~ "views_cache_bully_dont_enable = TRUE" ]]; then
      _VIEWS_CACHE_BULLY_DONT_ENABLE=YES
    else
      _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
    fi
  else
    _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _VCC_DE_T=$(grep "^views_content_cache_dont_enable = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VCC_DE_T}" =~ "views_content_cache_dont_enable = TRUE" ]]; then
      _VIEWS_CONTENT_CACHE_DONT_ENABLE=YES
    else
      _VIEWS_CONTENT_CACHE_DONT_ENABLE=NO
    fi
  else
    _VIEWS_CONTENT_CACHE_DONT_ENABLE=NO
  fi

  if [ -e "${_Plr}/modules/o_contrib" ]; then
    if [ ! -e "${_Plr}/modules/user" ] \
      || [ ! -e "${_Plr}/sites/all/modules" ] \
      || [ ! -e "${_Plr}/profiles" ]; then
      echo "WARNING: THIS PLATFORM IS BROKEN! ${_Plr}"
    elif [ ! -e "${_Plr}/modules/path_alias_cache" ]; then
      echo "WARNING: THIS PLATFORM IS NOT A VALID PRESSFLOW PLATFORM! ${_Plr}"
    elif [ -e "${_Plr}/modules/path_alias_cache" ] \
      && [ -e "${_Plr}/modules/user" ]; then
      _MODX=ON
      if [ ! -z "${_MODULES_OFF_SIX}" ]; then
        _disable_modules_with_drush8 "${_MODULES_OFF_SIX}"
      fi
      if [ ! -z "${_MODULES_ON_SIX}" ]; then
        _enable_modules_with_drush8 "${_MODULES_ON_SIX}"
      fi
      _run_drush8_cmd "sqlq \"UPDATE system SET weight = '-1' \
        WHERE type = 'module' AND name = 'path_alias_cache'\""
    fi
  elif [ -e "${_Plr}/modules/o_contrib_seven" ]; then
    if [ ! -e "${_Plr}/modules/user" ] \
      || [ ! -e "${_Plr}/sites/all/modules" ] \
      || [ ! -e "${_Plr}/profiles" ]; then
      echo "WARNING: THIS PLATFORM IS BROKEN! ${_Plr}"
    else
      _MODX=ON
      if [ ! -z "${_MODULES_OFF_SEVEN}" ]; then
        _disable_modules_with_drush8 "${_MODULES_OFF_SEVEN}"
      fi
      if [ "${_ENTITYCACHE_DONT_ENABLE}" = "NO" ]; then
        _enable_modules_with_drush8 "entitycache"
      fi
      if [ ! -z "${_MODULES_ON_SEVEN}" ]; then
        _enable_modules_with_drush8 "${_MODULES_ON_SEVEN}"
      fi
    fi
  fi
}

_if_site_db_conversion() {
  ###
  ### Detect db conversion mode, if set per platform or per site.
  ###
  if [ -e "${_PLR_CTRL_F}" ]; then
    _SQL_INDB_P=$(grep "sql_conversion_mode" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_P}" =~ "sql_conversion_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";sql_conversion_mode = NO" >> ${_PLR_CTRL_F}
    fi
    _SQL_INDB_T=$(grep "^sql_conversion_mode = innodb" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_T}" =~ "sql_conversion_mode = innodb" ]]; then
      _SQL_CONVERT=innodb
    fi
    _SQL_MYSM_T=$(grep "^sql_conversion_mode = myisam" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_SQL_MYSM_T}" =~ "sql_conversion_mode = myisam" ]]; then
      _SQL_CONVERT=myisam
    fi
  fi
  if [ -e "${_DIR_CTRL_F}" ]; then
    _SQL_INDB_P=$(grep "sql_conversion_mode" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_P}" =~ "sql_conversion_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";sql_conversion_mode = NO" >> ${_DIR_CTRL_F}
    fi
    _SQL_INDB_T=$(grep "^sql_conversion_mode = innodb" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_T}" =~ "sql_conversion_mode = innodb" ]]; then
      _SQL_CONVERT=innodb
    fi
    _SQL_MYSM_T=$(grep "^sql_conversion_mode = myisam" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SQL_MYSM_T}" =~ "sql_conversion_mode = myisam" ]]; then
      _SQL_CONVERT=myisam
    fi
  fi
  if [ "${_hostedSys}" = "YES" ]; then
    _DENY_SQL_CONVERT=YES
    _SQL_CONVERT=
  fi
  if [ -z "${_DENY_SQL_CONVERT}" ] \
    && [ ! -z "${_SQL_CONVERT}" ] \
    && [ "${_DOW}" = "2" ]; then
    if [ "${_SQL_CONVERT}" = "YES" ]; then
      _SQL_CONVERT=innodb
    elif [ "${_SQL_CONVERT}" = "NO" ]; then
      _SQL_CONVERT=
    fi
    if [ "${_SQL_CONVERT}" = "myisam" ] \
      || [ "${_SQL_CONVERT}" = "innodb" ]; then
      _TIMP=$(date +%y%m%d-%H%M%S)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${_Dom} started"
      _sql_convert
      _TIMP=$(date +%y%m%d-%H%M%S)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${_Dom} completed"
    fi
  fi
}

_cleanup_ghost_platforms() {
  if [ -e "${_Plr}" ]; then
    if [ ! -e "${_Plr}/index.php" ] || [ ! -e "${_Plr}/profiles" ]; then
      if [ ! -e "${_Plr}/vendor" ]; then
        mkdir -p ${_usEr}/undo
        ### mv -f ${_Plr} ${_usEr}/undo/ &> /dev/null
        echo "GHOST platform ${_Plr} detected and moved to ${_usEr}/undo/"
      fi
    fi
  fi
}

_fix_seven_core_patch() {
  if [ ! -f "${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info" ]; then
    _PATCH_TEST=$(grep "foreach (array_values(\$data)" \
      ${_Plr}/includes/database/database.inc 2>&1)
    if [[ "${_PATCH_TEST}" =~ "array_values" ]]; then
      echo fixed > ${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info
    else
      cd ${_Plr}
      patch -p1 < /var/xdrago/conf/SA-CORE-2014-005-D7.patch
      chown ${_HM_U}:users ${_Plr}/includes/database/*.inc &> /dev/null
      chmod 0664 ${_Plr}/includes/database/*.inc &> /dev/null
      echo fixed > ${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info
    fi
    chown ${_HM_U}:users ${_Plr}/profiles/*-fix.info &> /dev/null
    chmod 0664 ${_Plr}/profiles/*-fix.info &> /dev/null
  fi
}

_fix_static_permissions() {
  _cleanup_ghost_platforms
  if [ -e "${_Plr}/profiles" ]; then
    if [ -e "${_Plr}/web.config" ] && [ ! -e "${_Plr}/core" ]; then
      _fix_seven_core_patch
    fi
    if [ -e "${_Plr}/core/lib/Drupal.php" ] \
      && [ -e "${_Plr}/../vendor/autoload.php" ] \
      && grep -q '"drupal/core"' "${_Plr}/../composer.json" 2>/dev/null; then
      _use_Plr="$(cd "${_Plr}/.." && pwd -P)"
    else
      _use_Plr="${_Plr}"
    fi
    if [ ! -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_use_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.ctm-lock-${_NOW}.info" ]; then
        chown -R ${_HM_U} ${_use_Plr} &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.ctm-lock-${_NOW}.info
      fi
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_use_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.ctm-unlock-${_NOW}.info" ]; then
        chown -R ${_HM_U}.ftp ${_use_Plr} &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.ctm-unlock-${_NOW}.info
      fi
    fi
    if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info" ]; then
      find ${_use_Plr} -type d -exec chmod 0775 {} \; &> /dev/null
      find ${_use_Plr} -type f -exec chmod 0664 {} \; &> /dev/null
      if [ -e "${_use_Plr}/vendor/drush" ]; then
        chmod 0400 ${_use_Plr}/vendor/drush
      fi
      if [ -e "${_use_Plr}/vendor/symfony/console/Input" ]; then
        chmod 0400 ${_use_Plr}/vendor/symfony/console/Input
      fi
      if [ -e "${_use_Plr}/vendor/symfony/console/Style" ]; then
        chmod 0400 ${_use_Plr}/vendor/symfony/console/Style
      fi
    fi
  fi
}

_fix_expected_symlinks() {
  if [ ! -e "${_Plr}/js.php" ] && [ -e "${_Plr}" ]; then
    if [ -e "${_Plr}/modules/o_contrib_seven" ] \
      && [ -e "${_O_CONTRIB_SEVEN}/js/js.php" ]; then
      ln -sfn ${_O_CONTRIB_SEVEN}/js/js.php ${_Plr}/js.php &> /dev/null
    elif [ -e "${_Plr}/modules/o_contrib" ] \
      && [ -e "${_O_CONTRIB}/js/js.php" ]; then
      ln -sfn ${_O_CONTRIB}/js/js.php ${_Plr}/js.php &> /dev/null
    fi
  fi
}

_fix_permissions() {
  ### modules,themes,libraries - profile level in ~/static
  searchStringT="/static/"
  case ${_Plr} in
  *"$searchStringT"*)
  _fix_static_permissions
  ;;
  esac
  ### modules,themes,libraries - platform level
  if [ -f "${_Plr}/profiles/core-permissions-update-fix.info" ]; then
    rm -f ${_Plr}/profiles/*permissions*.info
    rm -f ${_Plr}/sites/all/permissions-fix*
  fi
  if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info" ] \
    && [ -e "${_Plr}" ]; then
    mkdir -p ${_Plr}/sites/all/{modules,themes,libraries,drush}
    find ${_Plr}/sites/all/{modules,themes,libraries,drush}/*{.tar,.tar.gz,.zip} \
      -type f -exec rm -f {} \; &> /dev/null
    if [ ! -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.lock-${_NOW}.info" ]; then
        chown -R ${_HM_U}:users \
          ${_Plr}/sites/all/{modules,themes,libraries}/* &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.lock-${_NOW}.info
      fi
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.unlock-${_NOW}.info" ]; then
        chown -R ${_HM_U}.ftp:users \
          ${_Plr}/sites/all/{modules,themes,libraries}/* &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.unlock-${_NOW}.info
      fi
    fi
    chown ${_HM_U}:users \
      ${_Plr}/sites/all/drush/drushrc.php \
      ${_Plr}/sites \
      ${_Plr}/sites/* \
      ${_Plr}/sites/sites.php \
      ${_Plr}/sites/all \
      ${_Plr}/sites/all/{modules,themes,libraries,drush} &> /dev/null
    chmod 0751 ${_Plr}/sites &> /dev/null
    chmod 0755 ${_Plr}/sites/* &> /dev/null
    chmod 0644 ${_Plr}/sites/*.php &> /dev/null
    chmod 0664 ${_Plr}/autoload.php &> /dev/null
    chmod 0644 ${_Plr}/sites/*.txt &> /dev/null
    chmod 0644 ${_Plr}/sites/*.yml &> /dev/null
    chmod 0755 ${_Plr}/sites/all/drush &> /dev/null
    find ${_Plr}/sites/all/{modules,themes,libraries} -type d -exec \
      chmod 02775 {} \; &> /dev/null
    find ${_Plr}/sites/all/{modules,themes,libraries} -type f -exec \
      chmod 0664 {} \; &> /dev/null
    ### expected symlinks
    _fix_expected_symlinks
    ### known exceptions
    chmod -R 775 ${_Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
    chown -R ${_HM_U}:www-data \
      ${_Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
    touch ${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info
  fi
  if [ -e "${_Dir}" ] \
    && [ -e "${_Dir}/drushrc.php" ] \
    && [ -e "${_Dir}/files" ] \
    && [ -e "${_Dir}/private" ]; then
    ### Cleanup
    rm ${_Dir}/*.{codebasecheck*,hm-fix-*,ctm-lock-*,lock-*,perm-fix-*}.info &> /dev/null
    ### directory and settings files - site level
    if [ ! -e "${_Dir}/modules" ]; then
      mkdir ${_Dir}/modules
    fi
    if [ -e "${_Dir}/aegir.services.yml" ]; then
      rm -f ${_Dir}/aegir.services.yml
    fi
    chown ${_HM_U}:users ${_Dir} &> /dev/null
    chown ${_HM_U}:www-data \
      ${_Dir}/{local.settings.php,settings.php,civicrm.settings.php,solr.php} &> /dev/null
    find ${_Dir}/*.php -type f -exec chmod 0440 {} \; &> /dev/null
    chmod 0640 ${_Dir}/civicrm.settings.php &> /dev/null
    ### modules,themes,libraries - site level
    find ${_Dir}/{modules,themes,libraries}/*{.tar,.tar.gz,.zip} -type f -exec \
      rm -f {} \; &> /dev/null
    rm -f ${_Dir}/modules/local-allow.info
    if [ ! -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      chown -R ${_HM_U}:users \
        ${_Dir}/{modules,themes,libraries}/* &> /dev/null
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      chown -R ${_HM_U}.ftp:users \
        ${_Dir}/{modules,themes,libraries}/* &> /dev/null
    fi
    chown ${_HM_U}:users \
      ${_Dir}/drushrc.php \
      ${_Dir}/{modules,themes,libraries} &> /dev/null
    find ${_Dir}/{modules,themes,libraries} -type d -exec \
      chmod 02775 {} \; &> /dev/null
    find ${_Dir}/{modules,themes,libraries} -type f -exec \
      chmod 0664 {} \; &> /dev/null
    ### files - site level
    ### -h replaces the prior -L: prevents recursive chown from dereferencing
    ### attacker-planted symlinks under _Dir/files (the realistic threat is
    ### a tar archive uploaded by a tenant containing an inner symlink, since
    ### Adam confirmed in category 1 that PHP cannot create symlinks directly
    ### but tar extraction can carry them in). Combined with the
    ### _validate_safe_dir gate above this closes the path-prefix and
    ### per-child symlink attack surfaces.
    chown -h -R ${_HM_U}:www-data ${_Dir}/files &> /dev/null
    find ${_Dir}/files/ -type d -exec chmod 02775 {} \; &> /dev/null
    find ${_Dir}/files/ -type f -exec chmod 0664 {} \; &> /dev/null
    chmod 02775 ${_Dir}/files &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files/{tmp,images,pictures,css,js} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files/{advagg_css,advagg_js,ctools} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files/{ctools/css,imagecache,locations} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files/{xmlsitemap,deployment,styles,private} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files/{civicrm,civicrm/templates_c} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files/{civicrm/upload,civicrm/persist} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/files/{civicrm/custom,civicrm/dynamic} &> /dev/null
    ### private - site level
    chown -h -R ${_HM_U}:www-data ${_Dir}/private &> /dev/null
    find ${_Dir}/private/ -type d -exec chmod 02775 {} \; &> /dev/null
    find ${_Dir}/private/ -type f -exec chmod 0664 {} \; &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private/{files,temp} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private/files/backup_migrate &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private/files/backup_migrate/{manual,scheduled} &> /dev/null
    chown -h -R ${_HM_U}:www-data ${_Dir}/private/config &> /dev/null
    _DB_HOST_PRESENT=$(grep "^\$_SERVER\['db_host'\] = \$options\['db_host'\];" \
      ${_Dir}/drushrc.php 2>&1)
    if [[ "${_DB_HOST_PRESENT}" =~ "db_host" ]]; then
      if [ "${_FORCE_SITES_VERIFY}" = "YES" ]; then
        _run_drush8_hmr_cmd "hosting-task @${_Dom} verify --force"
      fi
    else
      echo "\$_SERVER['db_host'] = \$options['db_host'];" >> ${_Dir}/drushrc.php
      _run_drush8_hmr_cmd "hosting-task @${_Dom} verify --force"
    fi
  fi
}

_convert_controls_orig() {
  if [ -e "${_CTRL_DIR}/$1.info" ] \
    || [ -e "${_usEr}/static/control/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      cp -af ${_CTRL_F_TPL} ${_CTRL_F}
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

_convert_controls_orig_no_global() {
  if [ -e "${_CTRL_DIR}/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      cp -af ${_CTRL_F_TPL} ${_CTRL_F}
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

_convert_controls_value() {
  if [ -e "${_CTRL_DIR}/$1.info" ] \
    || [ -e "${_usEr}/static/control/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      cp -af ${_CTRL_F_TPL} ${_CTRL_F}
    fi
    if [ "$1" = "nginx_cache_day" ]; then
      _TTL=86400
    elif [ "$1" = "nginx_cache_hour" ]; then
      _TTL=3600
    elif [ "$1" = "nginx_cache_quarter" ]; then
      _TTL=900
    fi
    sed -i "s/.*speed_booster_anon.*/speed_booster_anon_cache_ttl = ${_TTL}/g" \
      ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

_convert_controls_renamed() {
  if [ -e "${_CTRL_DIR}/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      cp -af ${_CTRL_F_TPL} ${_CTRL_F}
    fi
    if [ "$1" = "cookie_domain" ]; then
      sed -i "s/.*server_name_cookie.*/server_name_cookie_domain = TRUE/g" \
        ${_CTRL_F} &> /dev/null
      wait
    fi
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

_fix_control_settings() {
  _CTRL_NAME_ORIG="redis_lock_enable \
    redis_cache_disable \
    disable_admin_dos_protection \
    allow_anon_node_add \
    allow_private_file_downloads"
  _CTRL_NAME_VALUE="nginx_cache_day \
    nginx_cache_hour \
    nginx_cache_quarter"
  _CTRL_NAME_RENAMED="cookie_domain"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    _convert_controls_orig "$ctrl"
  done
  for ctrl in ${_CTRL_NAME_VALUE}; do
    _convert_controls_value "$ctrl"
  done
  for ctrl in ${_CTRL_NAME_RENAMED}; do
    _convert_controls_renamed "$ctrl"
  done
}

_fix_platform_system_control_settings() {
  _CTRL_NAME_ORIG="enable_user_register_protection \
     entitycache_dont_enable \
     views_cache_bully_dont_enable \
     views_content_cache_dont_enable"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    _convert_controls_orig "$ctrl"
  done
}

_fix_site_system_control_settings() {
  _CTRL_NAME_ORIG="disable_user_register_protection"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    _convert_controls_orig_no_global "$ctrl"
  done
}

_cleanup_ini() {
  if [ -e "${_CTRL_F}" ]; then
    sed -i "s/^;;.*//g"   ${_CTRL_F} &> /dev/null
    wait
    sed -i "s/^ .*//g"    ${_CTRL_F} &> /dev/null
    wait
    sed -i "s/^#.*//g"    ${_CTRL_F} &> /dev/null
    wait
    sed -i "/^$/d"        ${_CTRL_F} &> /dev/null
    wait
    sed -i "s/^\[/\n\[/g" ${_CTRL_F} &> /dev/null
    wait
  fi
}

_add_note_platform_ini() {
  if [ -e "${_CTRL_F}" ]; then
    echo "" >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  This is a platform level ACTIVE INI file which can be used to modify"     >> ${_CTRL_F}
    echo ";;  default BOA system behaviour for all sites hosted on this platform."      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> ${_CTRL_F}
    echo ";;  default.boa_platform_control.ini, since this ACTIVE INI file"             >> ${_CTRL_F}
    echo ";;  may not include all options available after upgrade to BOA-${_xSrl}"      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> ${_CTRL_F}
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
  fi
}

_add_note_site_ini() {
  if [ -e "${_CTRL_F}" ]; then
    echo "" >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  This is a site level ACTIVE INI file which can be used to modify"         >> ${_CTRL_F}
    echo ";;  default BOA system behaviour for this site only."                         >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> ${_CTRL_F}
    echo ";;  default.boa_site_control.ini, since this ACTIVE INI file"                 >> ${_CTRL_F}
    echo ";;  may not include all options available after upgrade to BOA-${_xSrl}"      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> ${_CTRL_F}
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
  fi
}

_fix_platform_control_files() {
  if [ -e "/data/conf/default.boa_platform_control.ini" ]; then
    if [ ! -e "${_Plr}/sites/all/modules/default.boa_platform_control.ini" ] \
      || [ "${_CTRL_TPL_FORCE_UPDATE}" = "YES" ]; then
      cp -af /data/conf/default.boa_platform_control.ini \
        ${_Plr}/sites/all/modules/ &> /dev/null
      chown ${_HM_U}:users ${_Plr}/sites/all/modules/default.boa_platform_control.ini &> /dev/null
      chmod 0664 ${_Plr}/sites/all/modules/default.boa_platform_control.ini &> /dev/null
    fi
    _CTRL_F_TPL="${_Plr}/sites/all/modules/default.boa_platform_control.ini"
    _CTRL_F="${_Plr}/sites/all/modules/boa_platform_control.ini"
    _CTRL_DIR="${_Plr}/sites/all/modules"
    _fix_control_settings
    _fix_platform_system_control_settings
    _cleanup_ini
    _add_note_platform_ini
  fi
}

_fix_site_control_files() {
  if [ -e "/data/conf/default.boa_site_control.ini" ]; then
    if [ ! -e "${_Dir}/modules/default.boa_site_control.ini" ] \
      || [ "${_CTRL_TPL_FORCE_UPDATE}" = "YES" ]; then
      cp -af /data/conf/default.boa_site_control.ini ${_Dir}/modules/ &> /dev/null
      chown ${_HM_U}:users ${_Dir}/modules/default.boa_site_control.ini &> /dev/null
      chmod 0664 ${_Dir}/modules/default.boa_site_control.ini &> /dev/null
    fi
    _CTRL_F_TPL="${_Dir}/modules/default.boa_site_control.ini"
    _CTRL_F="${_Dir}/modules/boa_site_control.ini"
    _CTRL_DIR="${_Dir}/modules"
    _fix_control_settings
    _fix_site_system_control_settings
    _cleanup_ini
    _add_note_site_ini
  fi
}

_cleanup_ghost_vhosts() {
  for _Site in `find ${_usEr}/config/server_master/nginx/vhost.d -maxdepth 1 \
    -mindepth 1 -type f | sort`; do
    _Dom=$(echo ${_Site} | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    if [[ "${_Dom}" =~ ".restore"($) ]]; then
      mkdir -p ${_usEr}/undo
      ### mv -f ${_usEr}/.drush/${_Dom}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
      ### mv -f ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} ${_usEr}/undo/ &> /dev/null
      echo "GHOST vhost for ${_Dom} detected and moved to ${_usEr}/undo/"
    fi
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d/${_Dom}" ]; then
      local _thisVhost="${_usEr}/config/server_master/nginx/vhost.d/${_Dom}"
      local _fixHttpReqired=NO
      if grep -q -e "ssl http2" "${_thisVhost}"; then
        local _fixHttpReqired=YES
      elif ! grep -q -E '^\s*http2\s+on;$' "${_thisVhost}"; then
        local _fixHttpReqired=YES
      elif grep -q -E '^\s+listen.*443\s+quic;$' "${_thisVhost}"; then
        local _fixHttpReqired=YES
      fi
      if [ "${_fixHttpReqired}" = "YES" ]; then
        echo "FIXING vhost for ${_Dom}"
        # Remove 'http2' from 'listen' directives with varying spaces
        sed -i -E 's/(listen\s+[^;]*\s+ssl)\s+http2;$/\1;/' "${_thisVhost}"
        # Remove existing 'http2 on;' lines with varying spaces
        sed -i -E '/^\s*http2\s+on;/d' "${_thisVhost}"
        # Remove existing 'quic' lines with varying spaces
        sed -i -E '/^\s+listen.*443\s+quic;/d' "${_thisVhost}"
        # Remove unwanted directives with varying spaces
        sed -i -E \
          -e '/^\s*ssl_stapling\b/d' \
          -e '/^\s*ssl_stapling_verify\b/d' \
          -e '/^\s*resolver\b/d' \
          -e '/^\s*resolver_timeout\b/d' \
          "${_thisVhost}"
        # Update 'ssl_prefer_server_ciphers' directive, handling spaces
        sed -i -E 's/^\s*ssl_prefer_server_ciphers\s+.*$/ssl_prefer_server_ciphers on;/' "${_thisVhost}"
        # Update 'http3_hq' directive, handling spaces
        sed -i -E 's/http3_hq\s+on;$/http3_hq on;/' "${_thisVhost}"
        if grep -q 'ssl_prefer_server_ciphers' "${_thisVhost}"; then
          # Add 'http2 on;' after 'ssl_prefer_server_ciphers on;', only if not already present
          if ! grep -q -E '^\s*http2\s+on;$' "${_thisVhost}"; then
            sed -i '/ssl_prefer_server_ciphers on;/ a\  http2 on;' "${_thisVhost}"
          fi
        elif grep -q -E '^\s*#http3_hq\s+on;$' "${_thisVhost}"; then
          # Add 'http2 on;' after 'http3_hq on;', only if not already present
          if ! grep -q -E '^\s*http2\s+on;$' "${_thisVhost}"; then
            sed -i '/http3_hq on;/ a\  http2 on;' "${_thisVhost}"
          fi
        fi
      fi
      _Plx=$(cat ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "${_Plx}" =~ "aegir/distro" ]] \
        || [[ "${_Dom}" =~ (^)"https." ]] \
        || [[ "${_Dom}" =~ "--CDN"($) ]]; then
        _SKIP_VHOST=YES
      else
        if [ ! -e "${_usEr}/.drush/${_Dom}.alias.drushrc.php" ]; then
          mkdir -p ${_usEr}/undo
          ### mv -f ${_Site} ${_usEr}/undo/ &> /dev/null
          echo "GHOST vhost for ${_Dom} with no drushrc detected and moved to ${_usEr}/undo/"
        fi
      fi
    fi
  done
}

_cleanup_ghost_drushrc() {
  for _thisAlias in `find ${_usEr}/.drush/*.alias.drushrc.php -maxdepth 1 -type f \
    | sort`; do
    _aliasName=$(echo "${_thisAlias}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
    _aliasName=$(echo "${_aliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [[ "${_aliasName}" =~ (^)"server_" ]] \
      || [[ "${_aliasName}" =~ (^)"hostmaster" ]]; then
      _IS_SITE=NO
    elif [[ "${_aliasName}" =~ (^)"platform_" ]]; then
      _Plm=$(cat ${_thisAlias} \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -d "${_Plm}" ]; then
        if [ ! -e "${_Plm}/index.php" ] || [ ! -e "${_Plm}/profiles" ]; then
          if [ ! -e "${_Plm}/vendor" ]; then
            mkdir -p ${_usEr}/undo
            ### mv -f ${_Plm} ${_usEr}/undo/ &> /dev/null
            echo "GHOST broken platform dir ${_Plm} detected and moved to ${_usEr}/undo/"
            ### mv -f ${_thisAlias} ${_usEr}/undo/ &> /dev/null
            echo "GHOST broken platform alias ${_thisAlias} detected and moved to ${_usEr}/undo/"
          fi
        fi
      else
        mkdir -p ${_usEr}/undo
        ### mv -f ${_thisAlias} ${_usEr}/undo/ &> /dev/null
        echo "GHOST nodir platform alias ${_thisAlias} detected and moved to ${_usEr}/undo/"
      fi
    else
      _T_SITE_NAME="${_aliasName}"
      if [[ "${_T_SITE_NAME}" =~ ".restore"($) ]]; then
        _IS_SITE=NO
        mkdir -p ${_usEr}/undo
        ### mv -f ${_usEr}/.drush/${_T_SITE_NAME}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
        ### mv -f ${_usEr}/config/server_master/nginx/vhost.d/${_T_SITE_NAME} ${_usEr}/undo/ &> /dev/null
        echo "GHOST drushrc and vhost for ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
      else
        _T_SITE_FDIR=$(cat ${_thisAlias} \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        if [ -e "${_T_SITE_FDIR}/drushrc.php" ] \
          && [ -e "${_T_SITE_FDIR}/files" ] \
          && [ -e "${_T_SITE_FDIR}/private" ]; then
          if [ ! -e "${_Dir}/modules" ]; then
            mkdir ${_Dir}/modules
          fi
          _IS_SITE=YES
        else
          mkdir -p ${_usEr}/undo
          ### mv -f ${_usEr}/.drush/${_T_SITE_NAME}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
          echo "GHOST drushrc for ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
          if [[ ! "${_T_SITE_FDIR}" =~ "aegir/distro" ]]; then
            ### mv -f ${_usEr}/config/server_master/nginx/vhost.d/${_T_SITE_NAME} ${_usEr}/undo/ghost-vhost-${_T_SITE_NAME} &> /dev/null
            echo "GHOST vhost for ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
          fi
          if [ -d "${_T_SITE_FDIR}" ]; then
            ### mv -f ${_T_SITE_FDIR} ${_usEr}/undo/ghost-site-${_T_SITE_NAME} &> /dev/null
            echo "GHOST site dir for ${_T_SITE_NAME} detected and moved from ${_T_SITE_FDIR} to ${_usEr}/undo/"
          fi
        fi
      fi
    fi
  done
}

_le_ssl_check_update() {
  _exeLe="${_usEr}/tools/le/dehydrated"
  _Vht="${_usEr}/config/server_master/nginx/vhost.d/${_Dom}"
  if [ -x "${_exeLe}" ] && [ -e "${_Vht}" ]; then
    _SSL_ON_TEST=$(cat ${_Vht} | grep "443 ssl" 2>&1)
    if [[ "${_SSL_ON_TEST}" =~ "443 ssl" ]]; then
      if [ -e "${_usEr}/tools/le/certs/${_Dom}/fullchain.pem" ]; then
        echo "Running LE cert check directly for ${_Dom}"
        _usEaliases=""
        _siTealiases=`cat ${_Vht} \
          | grep "server_name" \
          | sed "s/server_name//g; s/;//g" \
          | sort | uniq \
          | tr -d "\n" \
          | sed "s/  / /g; s/  / /g; s/  / /g" \
          | sort | uniq`
        for _aliAs in `echo "${_siTealiases}"`; do
          if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
            _Dom=$(echo ${_Dom} | sed 's/^www.//g' 2>&1)
            if [ -z "${_usEaliases}" ] \
              && [ ! -z "${_aliAs}" ] \
              && [[ ! "${_aliAs}" =~ ".nodns." ]] \
              && [[ ! "${_aliAs}" =~ "${_Dom}" ]]; then
              _usEaliases="--domain ${_aliAs}"
              echo "--domain ${_aliAs}"
            else
              if [ ! -z "${_aliAs}" ] \
                && [[ ! "${_aliAs}" =~ ".nodns." ]] \
                && [[ ! "${_aliAs}" =~ "${_Dom}" ]]; then
                _usEaliases="${_usEaliases} --domain ${_aliAs}"
                echo "--domain ${_aliAs}"
              fi
            fi
          else
            if [[ ! "${_aliAs}" =~ ".nodns." ]]; then
              echo "--domain ${_aliAs}"
              if [ -z "${_usEaliases}" ] && [ ! -z "${_aliAs}" ]; then
                _usEaliases="--domain ${_aliAs}"
              else
                if [ ! -z "${_aliAs}" ]; then
                  _usEaliases="${_usEaliases} --domain ${_aliAs}"
                fi
              fi
            else
              echo "ignored alias ${_aliAs}"
            fi
          fi
        done
		_DOM=$(date +%e)
		_DOM=${_DOM//[^0-9]/}
		_RDM=$((RANDOM%25+6))
		if [ "${_DOM}" = "${_RDM}" ] || [ -e "${_usEr}/static/control/force-ssl-certs-rebuild.info" ]; then
		  if [ ! -e "${_usEr}/log/ctrl/site.${_Dom}.cert-x1-rebuilt.info" ]; then
			_leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
			mkdir -p ${_usEr}/log/ctrl
			touch ${_usEr}/log/ctrl/site.${_Dom}.cert-x1-rebuilt.info
		  else
			_leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
		  fi
		else
		  _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
		fi
        _dhArgs="--domain ${_Dom} ${_usEaliases}"
        if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
          _Dom=$(echo ${_Dom} | sed 's/^www.//g' 2>&1)
          echo "--domain *.${_Dom}"
          if [ -e "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ] \
            || [ -e "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ]; then
            [ -e "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ] && chattr +i ${_usEr}/static/control/cloudflare-dns-ssl-py.info
            [ -e "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ] && chattr +i ${_usEr}/static/control/cloudflare-dns-ssl-sh.info
            export CF_DNS_SERVERS='8.8.8.8 8.8.4.4'
            export CF_SETTLE_TIME='30'
            export CF_DEBUG='true'
            if [ ! -e "${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh" ]; then
              _apt_clean_update
              apt-get install gawk jq publicsuffix ldnsutils ${_aptYesUnth} 2> /dev/null
              mkdir -p ${_usEr}/tools/le/hooks
              cd ${_usEr}/tools/le
              git clone https://github.com/omega8cc/dehydrated-hook-cloudflare hooks/cloudflare-sh 2> /dev/null
              chmod 755 ${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh
            fi
            if [ ! -e "${_usEr}/tools/le/hooks/cloudflare-py/hook.py" ]; then
              _apt_clean_update
              apt-get install python3-pip python-is-python3 ${_aptYesUnth} 2> /dev/null
              mkdir -p ${_usEr}/tools/le/hooks
              cd ${_usEr}/tools/le
              git clone https://github.com/omega8cc/letsencrypt-cloudflare-hook hooks/cloudflare-py 2> /dev/null
              chmod 755 ${_usEr}/tools/le/hooks/cloudflare-py/hook.py
              pip3 install -r hooks/cloudflare-py/requirements.txt 2> /dev/null
            fi
            if [ -e "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ]; then
              _thisHook="${_usEr}/tools/le/hooks/cloudflare-py/hook.py"
            elif [ -e "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ]; then
              _thisHook="${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh"
            fi
            if [ -e "${_thisHook}" ] && [ -e "${_usEr}/tools/le/config" ]; then
              chattr +i ${_usEr}/tools/le/config
              _dhArgs="--alias ${_Dom} --domain *.${_Dom} --domain ${_Dom} ${_usEaliases}"
              _dhArgs=" ${_dhArgs} --challenge dns-01 --hook '${_thisHook}'"
            fi
          else
            _dhArgs="--alias ${_Dom} --domain *.${_Dom} --domain ${_Dom} ${_usEaliases}"
          fi
        fi
        echo "_leParams is ${_leParams}"
        echo "_dhArgs is ${_dhArgs}"
        su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} ${_dhArgs}"
        wait
        if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
          sleep 30
        else
          sleep 3
        fi
        echo ${_MOMENT} >> /var/log/boa/le/${_Dom}
      fi
    fi
  fi
}

_daily_process() {
  _cleanup_ghost_vhosts
  _cleanup_ghost_drushrc
  for _Site in `find ${_usEr}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _MOMENT=$(date +%y%m%d-%H%M%S)
    echo ${_MOMENT} Start Counting Site ${_Site}
    _Dom=$(echo ${_Site} | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    _Dan=
    _Plx=
    _Plr=
    _Dir=
    _codeBaseCheckDir=
    _codeBaseCheckFile=
    _codeBaseCheckCtrl=
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d/${_Dom}" ]; then
      _Plx=$(cat ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "${_Plx}" =~ "aegir/distro" ]]; then
        _Dan=hostmaster
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
      echo "Dom is ${_Dom}"
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
      # Skip the iteration if the alias-derived paths do not resolve under
      # an allowed BOA root. Guards against a compromised aegir-context user
      # rewriting the alias to redirect chown/chmod onto system paths.
      if [ -n "${_Dir}" ] && ! _validate_safe_dir "${_Dir}"; then
        echo "SKIP: _Dir resolves outside allowed roots: ${_Dir}"
        continue
      fi
      if [ -n "${_Plr}" ] && ! _validate_safe_dir "${_Plr}"; then
        echo "SKIP: _Plr resolves outside allowed roots: ${_Plr}"
        continue
      fi
      if [ -e "${_Plr}" ]; then
        _PlrID=$(echo ${_Plr} \
          | openssl md5 \
          | awk '{ print $2}' \
          | tr -d "\n" 2>&1)
        if [ -e "/etc/boa/.allow-codebasecheck.cnf" ]; then
          _codeBaseCheckDir="${_usEr}/log/ctrl"
          _codeBaseCheckFile="plr.${_PlrID}.codebasecheck-${_NOW}.info"
          _codeBaseCheckCtrl="${_codeBaseCheckDir}/${_codeBaseCheckFile}"
          [ ! -e "${_codeBaseCheckDir}" ] && mkdir "${_codeBaseCheckDir}"
          if [ -x "/opt/local/bin/codebasecheck" ] \
            && [ -e "${_codeBaseCheckDir}" ] \
            && [ ! -e "${_codeBaseCheckCtrl}" ]; then
            codebasecheck "${_Plr}"
            wait
            touch "${_codeBaseCheckCtrl}"
          fi
        fi
        _fix_platform_control_files
        _fix_o_contrib_symlink
        if [ -e "${_Dir}/drushrc.php" ]; then
          cd ${_Dir}
          if [ "${_Dan}" = "hostmaster" ]; then
            if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.hm-fix-${_NOW}.info" ]; then
              su -s /bin/bash - ${_HM_U} -c "drush8 cc drush" &> /dev/null
              wait
              rm -rf ${_usEr}/.tmp/cache
              _run_drush8_hmr_cmd "dis update syslog dblog -y"
              _run_drush8_hmr_cmd "cron"
              _run_drush8_hmr_cmd "cache-clear all"
              _run_drush8_hmr_cmd "cache-clear all"
              _run_drush8_hmr_cmd "utf8mb4-convert-databases -y"
              touch ${_usEr}/log/ctrl/plr.${_PlrID}.hm-fix-${_NOW}.info
            fi
          fi
          if [ ! -z "${_Dan}" ] \
            && [ "${_Dan}" != "hostmaster" ]; then
            _if_site_db_conversion
            searchStringB=".dev."
            searchStringC=".devel."
            searchStringD=".temp."
            searchStringE=".tmp."
            searchStringF=".temporary."
            searchStringG=".test."
            searchStringH=".testing."
            case ${_Dom} in
              *"$searchStringB"*) ;;
              *"$searchStringC"*) ;;
              *"$searchStringD"*) ;;
              *"$searchStringE"*) ;;
              *"$searchStringF"*) ;;
              *"$searchStringG"*) ;;
              *"$searchStringH"*) ;;
              *)
              if [ "${_MODULES_FIX}" = "YES" ]; then
                _fix_modules
                _fix_robots_txt
                _fix_llms_txt
              fi
              _le_ssl_check_update
              if [ "${_ENABLE_GOACCESS}" = "YES" ] && [ -e "${_usEr}/static/control/goaccess/${_Dom}.info" ]; then
                _noPrefixDom="${_Dom#www.}"
                _if_gen_goaccess ${_noPrefixDom}
                _if_gen_goaccess ${_Dom}
              fi
              ;;
            esac
            _fix_site_control_files
            if [ -e "${_Plr}/modules/o_contrib_seven" ] \
              || [ -e "${_Plr}/modules/o_contrib" ]; then
              if [ "${_CLEAR_BOOST}" = "YES" ]; then
                _fix_boost_cache
              fi
              _fix_user_register_protection_with_vSet
              if [[ "${_xSrl}" =~ "OFF" ]]; then
                _run_drush8_cmd "advagg-force-new-aggregates"
                _run_drush8_cmd "cache-clear all"
                _run_drush8_cmd "cache-clear all"
              fi
            fi
          fi
        fi
        ###
        ### Detect permissions fix overrides, if set per platform.
        ###
        _DONT_TOUCH_PERMISSIONS=NO
        if [ -e "${_PLR_CTRL_F}" ]; then
          _FIX_PERMISSIONS_PRESENT=$(grep "fix_files_permissions_daily" \
            ${_PLR_CTRL_F} 2>&1)
          if [[ "${_FIX_PERMISSIONS_PRESENT}" =~ "fix_files_permissions_daily" ]]; then
            _DO_NOTHING=YES
          else
            echo ";fix_files_permissions_daily = TRUE" >> ${_PLR_CTRL_F}
          fi
          _FIX_PERMISSIONS_TEST=$(grep "^fix_files_permissions_daily = FALSE" \
            ${_PLR_CTRL_F} 2>&1)
          if [[ "${_FIX_PERMISSIONS_TEST}" =~ "fix_files_permissions_daily = FALSE" ]]; then
            _DONT_TOUCH_PERMISSIONS=YES
          fi
        fi
        if [ -e "${_Plr}/profiles" ] \
          && [ -e "${_Plr}/web.config" ] \
          && [ ! -e "${_Plr}/core" ] \
          && [ ! -f "${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info" ]; then
          _PATCH_TEST=$(grep "foreach (array_values(\$data)" \
            ${_Plr}/includes/database/database.inc 2>&1)
          if [[ "${_PATCH_TEST}" =~ "array_values" ]]; then
            _DONT_TOUCH_PERMISSIONS="${_DONT_TOUCH_PERMISSIONS}"
          else
            _DONT_TOUCH_PERMISSIONS=NO
          fi
        fi
        if [ -e "/etc/boa/.dont.touch.permissions.cnf" ]; then
          _DONT_TOUCH_PERMISSIONS=YES
        fi
        if [ "${_DONT_TOUCH_PERMISSIONS}" = "NO" ] \
          && [ "${_PERMISSIONS_FIX}" = "YES" ]; then
          _fix_permissions
        fi
      fi
      _MOMENT=$(date +%y%m%d-%H%M%S)
      echo ${_MOMENT} End Counting Site ${_Site}
    fi
  done
}
