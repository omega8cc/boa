#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export _tRee=dev
export _xSrl=540devT02

_check_root() {
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
_check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.pause_heavy_tasks_maint.cnf" ]; then
  exit 0
fi

_WEBG=www-data
_OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)

if [ -e "/root/.install.modern.openssl.cnf" ] \
  && [ -x "/usr/local/ssl3/bin/openssl" ]; then
  _SSL_BINARY=/usr/local/ssl3/bin/openssl
else
  _SSL_BINARY=/usr/local/ssl/bin/openssl
fi
_SSL_ITD=$(${_SSL_BINARY} version 2>&1 \
  | tr -d "\n" \
  | cut -d" " -f2 \
  | awk '{ print $1}')
if [[ "${_SSL_ITD}" =~ "3.2." ]] \
  || [[ "${_SSL_ITD}" =~ "3.1." ]] \
  || [[ "${_SSL_ITD}" =~ "3.0." ]] \
  || [[ "${_SSL_ITD}" =~ "1.1." ]] \
  || [[ "${_SSL_ITD}" =~ "1.0." ]]; then
  _NEW_SSL=YES
fi
_crlGet="-L --max-redirs 3 -k -s --retry 3 --retry-delay 5 -A iCab"
_aptYesUnth="-y --allow-unauthenticated"
_cGet="config-get user.settings"
_cSet="config-set user.settings"
_vGet="variable-get"
_vSet="variable-set --always-set"

###-------------SYSTEM-----------------###

_os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
_os_detection_minimal

_apt_clean_update() {
  #apt-get clean -qq 2> /dev/null
  #rm -rf /var/lib/apt/lists/* &> /dev/null
  ${_APT_UPDATE} -qq 2> /dev/null
}

_if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
    _hostedSys=YES
  else
    _hostedSys=NO
  fi
}

_find_fast_mirror_early() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    _apt_clean_update
    apt-get install netcat ${_aptYesUnth} 2> /dev/null
    apt-get install netcat-traditional ${_aptYesUnth} 2> /dev/null
    wait
  fi
  _ffMirr=$(which ffmirror 2>&1)
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2024-01.txt"
    mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "de.files.aegir.cc"  > ${_ffList}
      echo "ny.files.aegir.cc" >> ${_ffList}
      echo "sg.files.aegir.cc" >> ${_ffList}
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.aegir.cc"
      else
        _USE_MIR="files.aegir.cc"
      fi
    else
      _USE_MIR="files.aegir.cc"
    fi
  else
    _USE_MIR="files.aegir.cc"
  fi
  _urlDev="http://${_USE_MIR}/dev"
  _urlHmr="http://${_USE_MIR}/versions/${_tRee}/boa/aegir"
}

_enable_chattr() {
  isTest="$1"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      chattr +i /home/$1/
    else
      if [ -d "/home/$1/platforms/" ]; then
        chattr +i /home/$1/platforms/
        chattr +i /home/$1/platforms/* &> /dev/null
      fi
    fi
    if [ -d "/home/$1/.drush/" ]; then
      chattr +i /home/$1/.drush/
    fi
    if [ -d "/home/$1/.drush/usr/" ]; then
      chattr +i /home/$1/.drush/usr/
    fi
    if [ -f "/home/$1/.drush/php.ini" ]; then
      chattr +i /home/$1/.drush/*.ini
    fi
    if [ -d "/home/$1/.bazaar/" ]; then
      chattr +i /home/$1/.bazaar/
    fi
  fi
}

_disable_chattr() {
  isTest="$1"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      if [ -d "/home/$1/" ]; then
        chattr -i /home/$1/
      fi
    else
      if [ -d "/home/$1/platforms/" ]; then
        chattr -i /home/$1/platforms/
        chattr -i /home/$1/platforms/* &> /dev/null
      fi
    fi
    if [ -d "/home/$1/.drush/" ]; then
      chattr -i /home/$1/.drush/
    fi
    if [ -d "/home/$1/.drush/usr/" ]; then
      chattr -i /home/$1/.drush/usr/
    fi
    if [ -f "/home/$1/.drush/php.ini" ]; then
      chattr -i /home/$1/.drush/*.ini
    fi
    if [ -d "/home/$1/.bazaar/" ]; then
      chattr -i /home/$1/.bazaar/
    fi
  fi
}

_run_drush8_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${_nOw} ${_HM_U} running drush8 @${_Dom} $1"
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${_Dom} $1" &> /dev/null
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${_Dom} $1" &> /dev/null
  fi
  wait
}

_run_drush8_hmr_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${_nOw} ${_HM_U} running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

_run_drush8_hmr_master_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${_nOw} aegir running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - aegir -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

_run_drush8_nosilent_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${_nOw} ${_HM_U} running drush8 @${_Dom} $1"
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${_Dom} $1"
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${_Dom} $1"
  fi
  wait
}

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
    Profile=$(_run_drush8_nosilent_cmd "${_vGet} ^install_profile$" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    Profile=${Profile//[^a-z_]/}
    echo "Profile is == ${Profile} =="
    if [ ! -z "${Profile}" ]; then
      _REP_TEST=$(echo "${_REI_TEST}" | grep "Required by.*:.*${Profile}" 2>&1)
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

_fix_site_readonlymode() {
  if [ -e "${_usEr}/log/imported.pid" ] \
    || [ -e "${_usEr}/log/exported.pid" ]; then
    if [ -e "${_Dir}/modules/readonlymode_fix.info" ]; then
      touch ${_usEr}/log/ctrl/site.${_Dom}.rom-fix.info
      rm -f ${_Dir}/modules/readonlymode_fix.info
    fi
    if [ ! -e "${_usEr}/log/ctrl/site.${_Dom}.rom-fix.info" ]; then
      _run_drush8_cmd "${_vSet} site_readonly 0"
      touch ${_usEr}/log/ctrl/site.${_Dom}.rom-fix.info
    fi
  fi
}

_fix_user_register_protection_with_vSet() {
  _sync_user_register_protection_ini_vars
  if [ "${_IGNORE_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ ! -e "${_Plr}/core" ]; then
    Prm=$(_run_drush8_nosilent_cmd "${_vGet} ^user_register$" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    Prm=${Prm//[^0-2]/}
    echo "Prm user_register for ${_Dom} is ${Prm}"
    if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ]; then
      _run_drush8_cmd "${_vSet} user_register 0"
      echo "Prm user_register for ${_Dom} set to 0"
    else
      if [ "${Prm}" = "1" ] || [ -z "${Prm}" ]; then
        _run_drush8_cmd "${_vSet} user_register 2"
        echo "Prm user_register for ${_Dom} set to 2"
      fi
      _run_drush8_cmd "${_vSet} user_email_verification 1"
      echo "Prm user_email_verification for ${_Dom} set to 1"
    fi
  fi
  _fix_site_readonlymode
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
      if [ ! -e "${_Plr}/modules/o_contrib_eight" ]; then
        ln -sfn ${_O_CONTRIB_EIGHT} ${_Plr}/modules/o_contrib_eight &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ -e "${_Plr}/core/themes/classy" ] \
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
      if [ ! -e "${_Plr}/modules/o_contrib_nine" ]; then
        ln -sfn ${_O_CONTRIB_NINE} ${_Plr}/modules/o_contrib_nine &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ ! -e "${_Plr}/core/themes/classy" ] \
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
      if [ ! -e "${_Plr}/modules/o_contrib_ten" ]; then
        ln -sfn ${_O_CONTRIB_TEN} ${_Plr}/modules/o_contrib_ten &> /dev/null
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

_send_shutdown_notice() {
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MY_EMAIL=${_MY_EMAIL//\\\@/\@}
  if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
    _MY_EMAIL="support@omega8.cc"
  fi
  if [ ! -z "${_CLIENT_EMAIL}" ] \
    && [[ ! "${_CLIENT_EMAIL}" =~ "${_MY_EMAIL}" ]]; then
    _ALRT_EMAIL="${_CLIENT_EMAIL}"
  else
    _ALRT_EMAIL="${_MY_EMAIL}"
  fi
  _if_hosted_sys
  if [ "${_hostedSys}" = "YES" ]; then
    _BCC_EMAIL="omega8cc@gmail.com"
  else
    _BCC_EMAIL="${_MY_EMAIL}"
  fi
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "ALERT! Shutdown of Hacked ${_Dom} Site on ${_CHECK_HOST}" \
    ${_ALRT_EMAIL}
Hello,

Because you have not fixed this site despite several alerts
sent before, this site is scheduled for automated shutdown
to prevent further damage for the site owner and visitors.

Once the site is disabled, the only way to re-enable it again
is to run the Verify task in your Aegir control panel.

But if you will enable the site and not fix it immediately,
it will be shut down automatically again.

Common signatures of an attack which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${_Plr}

The system hostname is:

  ${_CHECK_HOST}

To learn more on what happened, how it was possible and
how to survive #Drupageddon, please read:

  https://omega8.cc/drupageddon-psa-2014-003-342

--
This email has been sent by your Aegir automatic system monitor.

EOF
  fi
  echo "ALERT: HACKED notice sent to ${_CLIENT_EMAIL} [${_HM_U}]: OK"
}

_send_hacked_alert() {
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MY_EMAIL=${_MY_EMAIL//\\\@/\@}
  if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
    _MY_EMAIL="support@omega8.cc"
  fi
  if [ ! -z "${_CLIENT_EMAIL}" ] \
    && [[ ! "${_CLIENT_EMAIL}" =~ "${_MY_EMAIL}" ]]; then
    _ALRT_EMAIL="${_CLIENT_EMAIL}"
  else
    _ALRT_EMAIL="${_MY_EMAIL}"
  fi
  _if_hosted_sys
  if [ "${_hostedSys}" = "YES" ]; then
    _BCC_EMAIL="omega8cc@gmail.com"
  else
    _BCC_EMAIL="${_MY_EMAIL}"
  fi
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "URGENT: The ${_Dom} site on ${_CHECK_HOST} has been HACKED!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that the site ${_Dom} has been hacked!

Common signatures of an attack which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${_Plr}

The system hostname is:

  ${_CHECK_HOST}

To learn more on what happened, how it was possible and
how to survive #Drupageddon, please read:

  https://omega8.cc/drupageddon-psa-2014-003-342

We have restarted these daily checks on May 7, 2016 to make sure that
no one stays on some too old Drupal version with many known security
vulnerabilities.

You will receive Drupageddon alert for every site with outdated and
not secure codebase, even if it was not affected by Drupageddon bug
directly.

Please be a good web citizen and upgrade to latest Drupal core provided
by BOA-5.4.0-dev. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 8.3

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

--
This email has been sent by your Aegir automatic system monitor.

EOF
  fi
  echo "ALERT: HACKED notice sent to ${_CLIENT_EMAIL} [${_HM_U}]: OK"
}

_send_core_alert() {
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MY_EMAIL=${_MY_EMAIL//\\\@/\@}
  if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
    _MY_EMAIL="support@omega8.cc"
  fi
  if [ ! -z "${_CLIENT_EMAIL}" ] \
    && [[ ! "${_CLIENT_EMAIL}" =~ "${_MY_EMAIL}" ]]; then
    _ALRT_EMAIL="${_CLIENT_EMAIL}"
  else
    _ALRT_EMAIL="${_MY_EMAIL}"
  fi
  _if_hosted_sys
  if [ "${_hostedSys}" = "YES" ]; then
    _BCC_EMAIL="omega8cc@gmail.com"
  else
    _BCC_EMAIL="${_MY_EMAIL}"
  fi
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "URGENT: The ${_Dom} site on ${_CHECK_HOST} runs on not secure Drupal core!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that this site runs on not secure Drupal core:

  ${_Dom}

The Drupageddon check result which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${_Plr}

The system hostname is:

  ${_CHECK_HOST}

Does it mean that your site is vulnerable to Drupageddon attack, recently
made famous again by Panama Papers leak?

  https://www.drupal.org/node/2718467

It depends on the Drupal core version you are using, and if it has been
patched already to close the known attack vectors. You can find more
details on our website at:

  https://omega8.cc/drupageddon-psa-2014-003-342

Even if the Drupal core version used in this site is not vulnerable
to Drupageddon attack, it is still vulnerable to other attacks,
because you have missed Drupal core security release(s).

We have restarted these daily checks on May 7, 2016 to make sure that
no one stays on some too old Drupal version with many known security
vulnerabilities.

You will receive Drupageddon alert for every site with outdated and
not secure codebase, even if it was not affected by Drupageddon bug
directly.

Please be a good web citizen and upgrade to latest Drupal core provided
by BOA-5.4.0-dev. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 8.3

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

--
This email has been sent by your Aegir automatic system monitor.

EOF
  fi
  echo "ALERT: Core notice sent to ${_CLIENT_EMAIL} [${_HM_U}]: OK"
}

_check_site_status_with_drush8() {
  _SITE_TEST=$(_run_drush8_nosilent_cmd "status" 2>&1)
  if [[ "${_SITE_TEST}" =~ "Error:" ]] \
    || [[ "${_SITE_TEST}" =~ "Drush was attempting to connect" ]]; then
    _SITE_TEST_RESULT=ERROR
  else
    _SITE_TEST_RESULT=OK
  fi
  if [ "${_SITE_TEST_RESULT}" = "OK" ]; then
    _STATUS_BOOTSTRAP=$(_run_drush8_nosilent_cmd "status bootstrap \
      | grep 'Drupal bootstrap.*:.*'" 2>&1)
    _STATUS_STATUS=$(_run_drush8_nosilent_cmd "status status \
      | grep 'Database.*:.*'" 2>&1)
    if [[ "${_STATUS_BOOTSTRAP}" =~ "Drupal bootstrap" ]] \
      && [[ "${_STATUS_STATUS}" =~ "Database" ]]; then
      _STATUS=OK
      _RUN_DGN=NO
      if [ -e "${_usEr}/static/control/drupalgeddon.info" ]; then
        _RUN_DGN=YES
      else
        if [ -e "/root/.force.drupalgeddon.cnf" ]; then
          _RUN_DGN=YES
        fi
      fi
      if [ -e "${_Plr}/modules/o_contrib_seven" ] \
        && [ "${_RUN_DGN}" = "YES" ]; then
        if [ -L "/home/${_HM_U}.ftp/.drush/usr/drupalgeddon" ]; then
          _run_drush8_cmd "en update -y"
          _DGDD_T=$(_run_drush8_nosilent_cmd "drupalgeddon-test" 2>&1)
          if [[ "${_DGDD_T}" =~ "No evidence of known Drupalgeddon" ]]; then
            _DO_NOTHING=YES
          elif [[ "${_DGDD_T}" =~ "The drush command" ]] \
            && [[ "${_DGDD_T}" =~ "could not be found" ]]; then
            _DO_NOTHING=YES
          elif [[ "${_DGDD_T}" =~ "has a uid that is" ]] \
            && [[ ! "${_DGDD_T}" =~ "has security vulnerabilities" ]] \
            && [[ "${_DGDD_T}" =~ "higher than" ]]; then
            _DO_NOTHING=YES
          elif [[ "${_DGDD_T}" =~ "has a created timestamp before" ]] \
            && [[ ! "${_DGDD_T}" =~ "has security vulnerabilities" ]]; then
            _DO_NOTHING=YES
          elif [ -z "${_DGDD_T}" ]; then
            _DO_NOTHING=YES
          elif [[ "${_DGDD_T}" =~ "Drush command terminated" ]]; then
            echo "ALERT: THIS SITE IS PROBABLY BROKEN! ${_Dir}"
            echo "${_DGDD_T}"
          else
            echo "ALERT: THIS SITE HAS BEEN HACKED! ${_Dir}"
            _DETECTED="${_DGDD_T}"
            if [ ! -z "${_MY_EMAIL}" ]; then
              if [[ "${_DGDD_T}" =~ "Role \"megauser\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"drupaldev\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"owned\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"system\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"configure\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"drplsys\" discovered" ]]; then
                if [ -e "${_usEr}/config/server_master/nginx/vhost.d/${_Dom}" ]; then
                  ### mv -f ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} ${_usEr}/config/server_master/nginx/vhost.d/.${_Dom}
                  _send_shutdown_notice
                fi
              else
                if [[ "${_DGDD_T}" =~ "has security vulnerabilities" ]]; then
                  _send_core_alert
                else
                  _send_hacked_alert
                fi
              fi
            fi
          fi
        else
          _DGMR_TEST=$(_run_drush8_nosilent_cmd \
            "sqlq \"SELECT * FROM menu_router WHERE access_callback \
            = 'file_put_contents'\" | grep 'file_put_contents'" 2>&1)
          if [[ "${_DGMR_TEST}" =~ "file_put_contents" ]]; then
            echo "ALERT: THIS SITE HAS BEEN HACKED! ${_Dir}"
            _DETECTED="file_put_contents as access_callback detected \
              in menu_router table"
            if [ ! -z "${_MY_EMAIL}" ]; then
              _send_hacked_alert
            fi
          fi
          _DGMR_TEST=$(_run_drush8_nosilent_cmd \
            "sqlq \"SELECT * FROM menu_router WHERE access_callback \
            = 'assert'\" | grep 'assert'" 2>&1)
          if [[ "${_DGMR_TEST}" =~ "assert" ]]; then
            echo "ALERT: THIS SITE HAS BEEN HACKED! ${_Dir}"
            _DETECTED="assert as access_callback detected in menu_router table"
            if [ ! -z "${_MY_EMAIL}" ]; then
              _send_hacked_alert
            fi
          fi
        fi
      fi
    else
      _STATUS=BROKEN
      echo "WARNING: THIS SITE IS BROKEN! ${_Dir}"
    fi
  else
    _STATUS=UNKNOWN
    echo "WARNING: THIS SITE IS PROBABLY BROKEN? ${_Dir}"
  fi
}

_check_file_with_wildcard_path() {
  _WILDCARD_TEST=$(ls $1 2>&1)
  if [ -z "${_WILDCARD_TEST}" ]; then
    _FILE_EXISTS=NO
  else
    _FILE_EXISTS=YES
  fi
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
      Pri=$(_run_drush8_nosilent_cmd "${_vGet} ^file_default_scheme$" \
        | cut -d: -f2 \
        | awk '{ print $1}' \
        | sed "s/['\"]//g" \
        | tr -d "\n" 2>&1)
      Pri=${Pri//[^a-z]/}
      if [ "$Pri" = "private" ] || [ "$Pri" = "public" ]; then
        echo Pri file_default_scheme for ${_Dom} is $Pri
      fi
      if [ "$Pri" = "private" ]; then
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
  _if_hosted_sys
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
      _TIMP=$(date +%y%m%d-%H%M%S 2>&1)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${_Dom} started"
      _sql_convert
      _TIMP=$(date +%y%m%d-%H%M%S 2>&1)
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
    if [ ! -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.ctm-lock-${_NOW}.info" ]; then
        chown -R ${_HM_U} ${_Plr} &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.ctm-lock-${_NOW}.info
      fi
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.ctm-unlock-${_NOW}.info" ]; then
        chown -R ${_HM_U}.ftp ${_Plr} &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.ctm-unlock-${_NOW}.info
      fi
    fi
    if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info" ]; then
      find ${_Plr} -type d -exec chmod 0775 {} \; &> /dev/null
      find ${_Plr} -type f -exec chmod 0664 {} \; &> /dev/null
    fi
  fi
}

_fix_expected_symlinks() {
  if [ ! -e "${_Plr}/js.php" ] && [ -e "${_Plr}" ]; then
    if [ -e "${_Plr}/modules/o_contrib_seven" ] \
      && [ -e "${_O_CONTRIB_SEVEN}/js/js.php" ]; then
      ln -s ${_O_CONTRIB_SEVEN}/js/js.php ${_Plr}/js.php &> /dev/null
    elif [ -e "${_Plr}/modules/o_contrib" ] \
      && [ -e "${_O_CONTRIB}/js/js.php" ]; then
      ln -s ${_O_CONTRIB}/js/js.php ${_Plr}/js.php &> /dev/null
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
    chown -L -R ${_HM_U}:www-data ${_Dir}/files &> /dev/null
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
    chown -L -R ${_HM_U}:www-data ${_Dir}/private &> /dev/null
    find ${_Dir}/private/ -type d -exec chmod 02775 {} \; &> /dev/null
    find ${_Dir}/private/ -type f -exec chmod 0664 {} \; &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private/{files,temp} &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private/files/backup_migrate &> /dev/null
    chown ${_HM_U}:www-data ${_Dir}/private/files/backup_migrate/{manual,scheduled} &> /dev/null
    chown -L -R ${_HM_U}:www-data ${_Dir}/private/config &> /dev/null
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

_if_le_hm_ssl_old() {
  # Get the current time in seconds since epoch
  current_time=$(date +%s)

  # Path to the file you want to check
  fi_lePath="$1"

  # Define the thresholds
  recent_threshold_days=60  # 60 days to consider for new updates
  update_check_days=30      # Don't update NEW if it was already set within the last 30 days

  # Check if the path is a symlink
  if [ -L "${fi_lePath}" ]; then
    target_file=$(readlink -f "${fi_lePath}")
    # Get the file's modification time in seconds since epoch
    file_mod_time=$(stat -c %Y "$target_file")
  else
    # Get the file's modification time in seconds since epoch
    file_mod_time=$(stat -c %Y "${fi_lePath}")
  fi

  # Calculate the time difference in minutes
  time_diff_minutes=$(( (current_time - file_mod_time) / 60 ))

  # Calculate the time difference in days
  time_diff_days=$(( time_diff_minutes / 1440 ))

  # Calculate the last update check time (from some state file, if exists)
  if [ -f "${fi_lePath}.lastupdate" ]; then
    last_update_time=$(cat "${fi_lePath}.lastupdate")
  else
    last_update_time=0
  fi

  last_update_diff_days=$(( (current_time - last_update_time) / 86400 ))  # 86400 seconds in a day

  # Check if the file was modified within the last 30 minutes
  if [ $time_diff_minutes -lt 30 ]; then
    crtLastMod=NEW
  # Check if the file was modified within the last 60 days and not marked NEW in the last 30 days
  elif [ $time_diff_days -le $recent_threshold_days ] && [ $last_update_diff_days -ge $update_check_days ]; then
    crtLastMod=NEW
    echo $current_time > "${fi_lePath}.lastupdate"
  else
    crtLastMod=OLD
  fi
}

_if_le_hm_ssl_crt_key_copy() {
  if [ -e "${leCrtPath}/fullchain.pem" ]; then
    crtPath="${leCrtPath}/fullchain.pem"
  elif [ -e "${leCrtPath}/cert.pem" ]; then
    crtPath="${leCrtPath}/cert.pem"
  fi
  if [ -e "${crtPath}" ]; then
    if [ -L "${crtPath}" ]; then
      crtPathR=$(readlink -n ${crtPath} 2>&1)
      crtPathR=$(echo -n ${crtPathR} | tr -d "\n" 2>&1)
      if [ -f "${leCrtPath}/${crtPathR}" ]; then
        rm -f /etc/ssl/private/${hmFront}.crt
        cp -a ${leCrtPath}/${crtPathR} /etc/ssl/private/${hmFront}.crt
      fi
    else
      rm -f /etc/ssl/private/${hmFront}.crt
      cp -a ${crtPath} /etc/ssl/private/${hmFront}.crt
    fi
  fi
  keyPath="${leCrtPath}/privkey.pem"
  if [ -e "${keyPath}" ]; then
    if [ -L "${keyPath}" ]; then
      keyPathR=$(readlink -n ${keyPath} 2>&1)
      keyPathR=$(echo -n ${keyPathR} | tr -d "\n" 2>&1)
      if [ -f "${leCrtPath}/${keyPathR}" ]; then
        rm -f /etc/ssl/private/${hmFront}.key
        cp -a ${leCrtPath}/${keyPathR} /etc/ssl/private/${hmFront}.key
      fi
    else
      rm -f /etc/ssl/private/${hmFront}.key
      cp -a ${keyPath} /etc/ssl/private/${hmFront}.key
    fi
  fi
}

_le_hm_ssl_check_update() {
  leCrtPath=
  _exeLe="${_usEr}/tools/le/dehydrated"
  if [ -e "${_usEr}/log/domain.txt" ]; then
    hmFront=$(cat ${_usEr}/log/domain.txt 2>&1)
    hmFront=$(echo -n ${hmFront} | tr -d "\n" 2>&1)
  fi
  if [ -e "${_usEr}/log/extra_domain.txt" ]; then
    hmFrontExtra=$(cat ${_usEr}/log/extra_domain.txt 2>&1)
    hmFrontExtra=$(echo -n ${hmFrontExtra} | tr -d "\n" 2>&1)
  fi
  if [ -z "${hmFront}" ]; then
    if [ -e "${_usEr}/.drush/hostmaster.alias.drushrc.php" ]; then
      hmFront=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
        | grep "uri'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    fi
  fi
  if [ ! -z "${hmFront}" ]; then
    leCrtPath="${_usEr}/tools/le/certs/${hmFront}"
  fi
  if [ -x "${_exeLe}" ] \
    && [ ! -z "${hmFront}" ] \
    && [ -e "${leCrtPath}/fullchain.pem" ]; then
    _DOM=$(date +%e 2>&1)
    _DOM=${_DOM//[^0-9]/}
    _RDM=$((RANDOM%25+6))
    if [ "${_DOM}" = "${_RDM}" ] || [ -e "${_usEr}/static/control/force-ssl-certs-rebuild.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/site.${hmFront}.cert-x1-rebuilt.info" ]; then
        leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
        mkdir -p ${_usEr}/log/ctrl
        touch ${_usEr}/log/ctrl/site.${hmFront}.cert-x1-rebuilt.info
      else
        leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
      fi
    else
      leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
    fi
    if [ ! -z "${hmFrontExtra}" ]; then
      echo "Running LE cert check directly for hostmaster ${_HM_U} with ${hmFrontExtra}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${leParams} --domain ${hmFront} --domain ${hmFrontExtra}"
      wait
    else
      echo "Running LE cert check directly for hostmaster ${_HM_U}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${leParams} --domain ${hmFront}"
      wait
    fi
  fi
  crtLastMod=OLD
  _if_le_hm_ssl_old "${leCrtPath}/fullchain.pem"
  if [ "${crtLastMod}" = "NEW" ]; then
    echo "Copying NEW LE cert for hostmaster ${hmFront} to /etc/ssl/private/"
    _if_le_hm_ssl_crt_key_copy
  else
    echo "No new LE cert for hostmaster ${hmFront} to copy"
  fi
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
		_DOM=$(date +%e 2>&1)
		_DOM=${_DOM//[^0-9]/}
		_RDM=$((RANDOM%25+6))
		if [ "${_DOM}" = "${_RDM}" ] || [ -e "${_usEr}/static/control/force-ssl-certs-rebuild.info" ]; then
		  if [ ! -e "${_usEr}/log/ctrl/site.${_Dom}.cert-x1-rebuilt.info" ]; then
			leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
			mkdir -p ${_usEr}/log/ctrl
			touch ${_usEr}/log/ctrl/site.${_Dom}.cert-x1-rebuilt.info
		  else
			leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
		  fi
		else
		  leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
		fi
        dhArgs="--domain ${_Dom} ${_usEaliases}"
        if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
          _Dom=$(echo ${_Dom} | sed 's/^www.//g' 2>&1)
          echo "--domain *.${_Dom}"
          if [ ! -e "${_usEr}/tools/le/hooks/cloudflare/hook.py" ]; then
            mkdir -p ${_usEr}/tools/le/hooks
            cd ${_usEr}/tools/le
            git clone https://github.com/kappataumu/letsencrypt-cloudflare-hook hooks/cloudflare
            pip install -r hooks/cloudflare/requirements.txt
          fi
          if [ -e "${_usEr}/tools/le/hooks/cloudflare/hook.py" ]; then
            if [ -e "${_usEr}/tools/le/config" ]; then
              dhArgs="--alias ${_Dom} --domain *.${_Dom} --domain ${_Dom} ${_usEaliases}"
              dhArgs=" ${dhArgs} --challenge dns-01 --hook '${_usEr}/tools/le/hooks/cloudflare/hook.py'"
            fi
          fi
        fi
        echo "leParams is ${leParams}"
        echo "dhArgs is ${dhArgs}"
        su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${leParams} ${dhArgs}"
        wait
        if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
          sleep 30
        else
          sleep 3
        fi
        echo ${_MOMENT} >> /var/xdrago/log/le/${_Dom}
      fi
    fi
  fi
}

_if_gen_goaccess() {
  _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.${_HM_U}.octopus.cnf 2>&1)
  if [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]]; then
    isWblgx=$(which weblogx 2>&1)
    if [ -x "${isWblgx}" ]; then
      ${isWblgx} --site="${1}" --env="${_HM_U}"
      wait
      if [ ! -e "/data/disk/${_HM_U}/static/goaccess" ]; then
        mkdir -p /data/disk/${_HM_U}/static/goaccess
      fi
      if [ -e "/var/www/adminer/access/${_HM_U}/${1}/index.html" ]; then
        cp -af /var/www/adminer/access/${_HM_U}/${1} /data/disk/${_HM_U}/static/goaccess/
      else
        rm -rf /var/www/adminer/access/${_HM_U}/${1}
        rm -rf /data/disk/${_HM_U}/static/goaccess/${1}
      fi
    fi
  fi
}

_daily_process() {
  _cleanup_ghost_vhosts
  _cleanup_ghost_drushrc
  for _Site in `find ${_usEr}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _MOMENT=$(date +%y%m%d-%H%M%S 2>&1)
    echo ${_MOMENT} Start Counting Site ${_Site}
    _Dom=$(echo ${_Site} | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    _Dan=
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
      if [ -e "${_Plr}" ]; then
        if [ "${_NEW_SSL}" = "YES" ]; then
          _PlrID=$(echo ${_Plr} \
            | openssl md5 \
            | awk '{ print $2}' \
            | tr -d "\n" 2>&1)
        else
          _PlrID=$(echo ${_Plr} \
            | openssl md5 \
            | tr -d "\n" 2>&1)
        fi
        _fix_platform_control_files
        _fix_o_contrib_symlink
        if [ -e "${_Dir}/drushrc.php" ]; then
          cd ${_Dir}
          if [ "${_Dan}" = "hostmaster" ]; then
            _STATUS=OK
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
          else
            if [ -e "${_Plr}/modules/o_contrib_seven" ] \
              || [ -e "${_Plr}/modules/o_contrib" ]; then
              _check_site_status_with_drush8
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
                _CHECK_IS=OFF
                #if [ "${_STATUS}" = "OK" ]; then
                  _fix_modules
                #fi
                _fix_robots_txt
              fi
              _le_ssl_check_update
              if [ "${_ENABLE_GOACCESS}" = "YES" ] && [ -e "${_usEr}/static/control/goaccess/${_Dom}.info" ]; then
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
        if [ "${_DONT_TOUCH_PERMISSIONS}" = "NO" ] \
          && [ "${_PERMISSIONS_FIX}" = "YES" ]; then
          _fix_permissions
        fi
      fi
      _MOMENT=$(date +%y%m%d-%H%M%S 2>&1)
      echo ${_MOMENT} End Counting Site ${_Site}
    fi
  done
}

_delete_this_empty_hostmaster_platform() {
  _run_drush8_hmr_master_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

_check_old_empty_hostmaster_platforms() {
  if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ] \
	&& [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
	_DO_NOTHING=YES
  else
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
	  _DEL_OLD_EMPTY_PLATFORMS="3"
	else
	  _DEL_OLD_EMPTY_PLATFORMS="7"
	fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on /var/aegir instance"
      for Platform in `find /var/aegir/.drush/platform_* -maxdepth 1 -mtime \
        +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`; do
        _T_PFM_NAME=$(echo "${Platform}" \
          | sed "s/.*platform_//g; s/.alias.drushrc.php//g" \
          | awk '{ print $1}' 2>&1)
        _T_PFM_ROOT=$(cat ${Platform} \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _T_PFM_SITE=$(grep "${_T_PFM_ROOT}/sites/" \
          /var/aegir/.drush/*.drushrc.php \
          | grep site_path 2>&1)
        if [ ! -e "${_T_PFM_ROOT}/sites/all" ] \
          || [ ! -e "${_T_PFM_ROOT}/index.php" ]; then
          mkdir -p /var/aegir/undo
          ### mv -f /var/aegir/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php /var/aegir/undo/ &> /dev/null
          echo "GHOST platform ${_T_PFM_ROOT} detected and moved to /var/aegir/undo/"
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_ROOT}/sites/all" ]; then
          _delete_this_empty_hostmaster_platform
        fi
      done
    fi
  fi
}

_delete_this_platform() {
  _run_drush8_hmr_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

_check_old_empty_platforms() {
  _if_hosted_sys
  if [ "${_hostedSys}" = "YES" ]; then
    if [[ "${_CHECK_HOST}" =~ "demo.aegir.cc" ]] \
      || [ -e "${_usEr}/static/control/platforms.info" ]; then
      _DO_NOTHING=YES
    else
      if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ] \
        && [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
        _DO_NOTHING=YES
      else
        _DEL_OLD_EMPTY_PLATFORMS="60"
      fi
    fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on ${_HM_U} instance"
      for Platform in `find ${_usEr}/.drush/platform_* -maxdepth 1 -mtime \
        +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`; do
        _T_PFM_NAME=$(echo "${Platform}" \
          | sed "s/.*platform_//g; s/.alias.drushrc.php//g" \
          | awk '{ print $1}' 2>&1)
        _T_PFM_ROOT=$(cat ${Platform} \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _T_PFM_SITE=$(grep "${_T_PFM_ROOT}/sites/" \
          ${_usEr}/.drush/*.drushrc.php \
          | grep site_path 2>&1)
        if [ ! -e "${_T_PFM_ROOT}/sites/all" ] \
          || [ ! -e "${_T_PFM_ROOT}/index.php" ]; then
          if [ ! -e "${_T_PFM_ROOT}/vendor" ]; then
            mkdir -p ${_usEr}/undo
            ### mv -f ${_usEr}/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
            echo "GHOST platform ${_T_PFM_ROOT} detected and moved to ${_usEr}/undo/"
          fi
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_ROOT}/sites/all" ]; then
          _delete_this_platform
        fi
      done
    fi
  fi
}

_purge_cruft_machine() {

  if [ ! -z "${_DEL_OLD_TMP}" ] && [ "${_DEL_OLD_TMP}" -gt "0" ]; then
    _PURGE_TMP="${_DEL_OLD_TMP}"
  else
    _PURGE_TMP="0"
  fi

  if [ ! -z "${_DEL_OLD_BACKUPS}" ] && [ "${_DEL_OLD_BACKUPS}" -gt "0" ]; then
    _PURGE_BACKUPS="${_DEL_OLD_BACKUPS}"
  else
    _PURGE_BACKUPS="14"
    _if_hosted_sys
    if [ "${_hostedSys}" = "YES" ]; then
      _PURGE_BACKUPS="7"
    fi
  fi

  _LOW_NR="2"
  _PURGE_CTRL="14"

  find ${_usEr}/log/ctrl/*cert-x1-rebuilt.info \
    -mtime +${_PURGE_CTRL} -type f -exec rm -rf {} \; &> /dev/null

  find ${_usEr}/log/ctrl/plr* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null

  find ${_usEr}/log/ctrl/*rom-fix.info \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null

  find ${_usEr}/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${_usEr}/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${_usEr}/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null

  find /var/aegir/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null

  find ${_usEr}/distro/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/distro/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find ${_usEr}/static/*/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find ${_usEr}/static/*/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find ${_usEr}/distro/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/distro/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null

  find /home/${_HM_U}.ftp/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find /home/${_HM_U}.ftp/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  chown -R ${_HM_U}:users ${_usEr}/tools/le
  mkdir -p ${_usEr}/static/trash
  chown ${_HM_U}.ftp:users ${_usEr}/static/trash &> /dev/null
  find ${_usEr}/static/trash/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  for i in `dir -d /home/${_HM_U}.ftp/platforms/*`; do
    if [ -e "${i}" ]; then
      RevisionTest=$(ls ${i} \
        | wc -l \
        | tr -d "\n" 2>&1)
      if [ "${RevisionTest}" -lt "${_LOW_NR}" ] \
        && [ ! -z "${RevisionTest}" ]; then
        if [ -d "/home/${_HM_U}.ftp/platforms" ]; then
          chattr -i /home/${_HM_U}.ftp/platforms
          chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
        fi
        _NOW=$(date +%y%m%d-%H%M%S 2>&1)
        [ ! -e "/var/backups/ghost/${_HM_U}/${_NOW}" ] && mkdir -p /var/backups/ghost/${_HM_U}/${_NOW}
        echo "Moving ${i} to /var/backups/ghost/${_HM_U}/${_NOW}"
        mv -f ${i} /var/backups/ghost/${_HM_U}/${_NOW}/
      fi
    fi
  done

  for i in `dir -d ${_usEr}/distro/*`; do
    if [ -d "${i}" ]; then
      if [ ! -d "${i}/keys" ]; then
        mkdir -p ${i}/keys
      fi
      RevisionTest=$(ls ${i} | wc -l 2>&1)
      if [ "${RevisionTest}" -lt "2" ] && [ ! -z "${RevisionTest}" ]; then
        echo "RevisionTest is ${RevisionTest}"
        _NOW=$(date +%y%m%d-%H%M%S 2>&1)
        mkdir -p ${_usEr}/undo/dist/${_NOW}
        mv -f ${i} ${_usEr}/undo/dist/${_NOW}/ &> /dev/null
        echo "GHOST revision ${i} detected and moved to ${_usEr}/undo/dist/${_NOW}/"
      fi
    fi
  done

  for i in `dir -d ${_usEr}/distro/*`; do
    if [ -e "${i}" ]; then
      distTrNr=$(echo ${i} \
        | cut -d'/' -f6 \
        | awk '{ print $1}' 2> /dev/null)
      if [ -d "/home/${_HM_U}.ftp/platforms" ]; then
        chattr -i /home/${_HM_U}.ftp/platforms
        chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
      fi
      if [ ! -e "${i}/keys" ]; then
        mkdir -p ${i}/keys
        chown ${_HM_U}.ftp:${_WEBG} ${i}/keys &> /dev/null
        chmod 02775 ${i}/keys &> /dev/null
      fi
      if [ ! -e "/home/${_HM_U}.ftp/platforms/${distTrNr}" ]; then
        mkdir -p /home/${_HM_U}.ftp/platforms/${distTrNr}
      fi
      if [ -e "${i}/keys" ] && [ ! -e "/home/${_HM_U}.ftp/platforms/${distTrNr}/keys" ]; then
        ln -sfn ${i}/keys /home/${_HM_U}.ftp/platforms/${distTrNr}/keys
      fi
      if [ -e "/home/${_HM_U}.ftp/platforms/data" ]; then
        _NOW=$(date +%y%m%d-%H%M%S 2>&1)
        [ ! -e "/var/backups/ghost/${_HM_U}/${_NOW}" ] && mkdir -p /var/backups/ghost/${_HM_U}/${_NOW}
        mv -f /home/${_HM_U}.ftp/platforms/data /var/backups/ghost/${_HM_U}/${_NOW}/platforms_data
      fi
      for Codebase in `find ${i}/* \
        -maxdepth 1 \
        -mindepth 1 \
        -type d \
        | grep "/sites$" 2>&1`; do
        CodebaseName=$(echo ${Codebase} \
          | cut -d'/' -f7 \
          | awk '{ print $1}' 2> /dev/null)
        ln -sfn ${Codebase} /home/${_HM_U}.ftp/platforms/${distTrNr}/${CodebaseName}
        echo "Fixed ${CodebaseName} in ${distTrNr} symlink to ${Codebase} for ${_HM_U}.ftp"
      done
    fi
  done
}

_count_cpu() {
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

_load_control() {
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  export _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  : "${_CPU_MAX_RATIO:=2.5}"
  [ -e "/root/.force.sites.verify.cnf" ] && _CPU_MAX_RATIO=88
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
}

_shared_codebases_cleanup() {
  if [ -L "/data/all" ]; then
    _CLD="/data/disk/codebases-cleanup"
  else
    _CLD="/var/backups/codebases-cleanup"
  fi
  for i in `dir -d /data/all/*/`; do
    if [ -d "${i}o_contrib" ]; then
      for Codebase in `find ${i}* -maxdepth 1 -mindepth 1 -type d \
        | grep "/profiles$" 2>&1`; do
        Codebase_Dir=$(echo ${Codebase} \
          | sed 's/\/profiles//g' \
          | awk '{print $1}' 2> /dev/null)
        CodebaseTest=$(find /data/disk/*/distro/*/*/ -maxdepth 1 -mindepth 1 \
          -type l -lname ${Codebase} | sort 2>&1)
        if [[ "${CodebaseTest}" =~ "No such file or directory" ]] \
          || [ -z "${CodebaseTest}" ]; then
          mkdir -p ${_CLD}${i}
          echo "Moving no longer used ${CodebaseDir} to ${_CLD}${i}"
          ### mv -f ${CodebaseDir} ${_CLD}${i}
        fi
      done
    fi
  done
}

_ghost_codebases_cleanup() {
  _CLD="/var/backups/ghost-codebases-cleanup"
  for i in `dir -d /data/disk/*/distro/*/*/`; do
    CodebaseTest=$(find ${i} -maxdepth 1 -mindepth 1 \
      -type d -name vendor | sort 2>&1)
    for vendor in ${CodebaseTest}; do
      Parent_Dir=`echo ${vendor} | sed "s/\/vendor//g"`
      if [ -d "${ParentDir}/docroot/sites/all" ] \
        || [ -d "${ParentDir}/html/sites/all" ] \
        || [ -d "${ParentDir}/web/sites/all" ]; then
        _CLEAN_THIS=SKIP
      else
        _CLEAN_THIS="${ParentDir}"
        _TSTAMP=`date +%y%m%d-%H%M%S`
        mkdir -p ${_CLD}${i}${_TSTAMP}
        echo "Moving ghost ${_CLEAN_THIS} to ${_CLD}${i}${_TSTAMP}/"
        ### mv -f ${_CLEAN_THIS} ${_CLD}${i}${_TSTAMP}/
      fi
    done
  done
}

_prepare_weblogx() {
  _ARCHLOGS=/var/www/adminer/access/archive
  mkdir -p ${_ARCHLOGS}/unzip
  echo "[+] SYNCING LOGS TO: ${_ARCHLOGS}"
  rsync -rlvz --size-only --progress /var/log/nginx/access* ${_ARCHLOGS}/
  echo "[+] COPYING LOGS TO: ${_ARCHLOGS}/unzip/"
  cp -af ${_ARCHLOGS}/access* ${_ARCHLOGS}/unzip/
  echo "[+] DECOMPRESSING GZ FILES"
  find ${_ARCHLOGS}/unzip -name "*.gz" -exec gunzip -f {} \;
  echo "[+] RENAMING RAW FILES"
  for _log in `find ${_ARCHLOGS}/unzip \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    mv -f ${_log} ${_log}.txt;
  done
  rm -f ${_ARCHLOGS}/unzip/*.txt.txt*
  touch ${_ARCHLOGS}/unzip/.global.pid
}

_cleanup_weblogx() {
  _ARCHLOGS=/var/www/adminer/access/archive
  if [ -e "${_ARCHLOGS}/unzip" ]; then
    rm -f ${_ARCHLOGS}/unzip/access*
    rm -f ${_ARCHLOGS}/unzip/.global.pid
  fi
}

_incident_email_report() {
  if [ -e "/root/.barracuda.cnf" ]; then
    source /root/.barracuda.cnf
    local thisEmail="${_MY_EMAIL}"
    export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
    : "${_INCIDENT_EMAIL_REPORT:=YES}"
  fi
  if [ -n "${thisEmail}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${thisLog}
    s-nail -s "Incident Report during daily.sh: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${thisLog}
  fi
}

_incident_detection() {
  # Array of errors to search for
  declare -a errors=(
    "urn:ietf:params:acme:error:unauthorized"
    "urn:ietf:params:acme:error:badNonce"
    "urn:ietf:params:acme:error:rateLimited"
    "urn:acme:error:serverInternal"
    "Remote PerformValidation RPC failed"
    "ModuleNotFoundError"
    "Traceback"
    "Drush command terminated abnormally"
    "ArgumentCountError"
  )

  # Loop through errors and check if any exist in the log file
  for error in "${errors[@]}"; do
    if grep -q "${error}" "${thisLog}"; then
      _incident_email_report "${error}"
      break  # Exit the loop after the first detected error
    fi
  done
}

_daily_action() {
  if [ -n "${_ENABLE_GOACCESS}" ] && [ "${_ENABLE_GOACCESS}" = "YES" ]; then
    _prepare_weblogx
  fi
  for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    _count_cpu
    _load_control
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/CANCELLED" ]; then
      if [ "${_O_LOAD}" -lt "${_O_LOAD_MAX}" ]; then
        _HM_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _THIS_HM_SITE=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "User ${_usEr}"
        mkdir -p ${_usEr}/log/ctrl
        su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
        wait
        rm -rf ${_usEr}/.tmp/cache
        chage -M 99999 ${_HM_U}.ftp &> /dev/null
        su -s /bin/bash - ${_HM_U}.ftp -c "drush8 cc drush" &> /dev/null
        wait
        chage -M 90 ${_HM_U}.ftp &> /dev/null
        rm -rf /home/${_HM_U}.ftp/.tmp/cache
        _SQL_CONVERT=NO
        _DEL_OLD_EMPTY_PLATFORMS="0"
        if [ -e "/root/.${_HM_U}.octopus.cnf" ]; then
          if [ -x "/usr/bin/drush10" ]; then
            su -s /bin/bash - ${_HM_U} -c "rm -f ~/.drush/sites/*.yml"
            wait
            su -s /bin/bash - ${_HM_U} -c "rm -f ~/.drush/sites/.checksums/*.md5"
            wait
            su -s /bin/bash - ${_HM_U} -c "drush10 core:init --yes" &> /dev/null
            wait
            su -s /bin/bash - ${_HM_U} -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
            wait
          fi
          source /root/.${_HM_U}.octopus.cnf
          _DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS//[^0-9]/}
          _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
          _MY_EMAIL=${_MY_EMAIL//\\\@/\@}
          if [ -e "${_usEr}/log/email.txt" ]; then
            _F_CLIENT_EMAIL=$(cat ${_usEr}/log/email.txt 2>&1)
            _F_CLIENT_EMAIL=$(echo -n ${_F_CLIENT_EMAIL} | tr -d "\n" 2>&1)
            _F_CLIENT_EMAIL=${_F_CLIENT_EMAIL//\\\@/\@}
          fi
          if [ ! -z "${_F_CLIENT_EMAIL}" ]; then
            _CLIENT_EMAIL_TEST=$(grep "^_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"" \
              /root/.${_HM_U}.octopus.cnf 2>&1)
            if [[ "${_CLIENT_EMAIL_TEST}" =~ "${_F_CLIENT_EMAIL}" ]]; then
              _DO_NOTHING=YES
            else
              sed -i "s/^_CLIENT_EMAIL=.*/_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"/g" \
                /root/.${_HM_U}.octopus.cnf
              wait
              _CLIENT_EMAIL=${_F_CLIENT_EMAIL}
            fi
          fi
        fi
        _disable_chattr ${_HM_U}.ftp
        rm -rf /home/${_HM_U}.ftp/drush-backups
        if [ -e "${_THIS_HM_SITE}" ]; then
          cd ${_THIS_HM_SITE}
          su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
          wait
          rm -rf ${_usEr}/.tmp/cache
          _run_drush8_hmr_cmd "${_vSet} hosting_cron_default_interval 3600"
          _run_drush8_hmr_cmd "${_vSet} hosting_queue_cron_frequency 1"
          _run_drush8_hmr_cmd "${_vSet} hosting_civicrm_cron_queue_frequency 60"
          _run_drush8_hmr_cmd "${_vSet} hosting_queue_task_gc_frequency 300"
          if [ -e "${_usEr}/log/hosting_cron_use_backend.txt" ]; then
            _run_drush8_hmr_cmd "${_vSet} hosting_cron_use_backend 1"
          else
            _run_drush8_hmr_cmd "${_vSet} hosting_cron_use_backend 0"
          fi
          _run_drush8_hmr_cmd "${_vSet} hosting_ignore_default_profiles 0"
          _run_drush8_hmr_cmd "${_vSet} hosting_queue_tasks_frequency 1"
          _run_drush8_hmr_cmd "${_vSet} hosting_queue_tasks_items 1"
          _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
          _run_drush8_hmr_cmd "${_vSet} aegir_backup_export_path ${_usEr}/backup-exports"
          _run_drush8_hmr_cmd "fr hosting_custom_settings -y"
          _run_drush8_hmr_cmd "cache-clear all"
          _run_drush8_hmr_cmd "cache-clear all"
          if [ -e "${_usEr}/log/imported.pid" ] \
            || [ -e "${_usEr}/log/exported.pid" ]; then
            if [ ! -e "${_usEr}/log/hosting_context.pid" ]; then
              _HM_NID=$(_run_drush8_hmr_cmd "sqlq \
                \"SELECT site.nid FROM hosting_site site JOIN \
                hosting_package_instance pkgi ON pkgi.rid=site.nid JOIN \
                hosting_package pkg ON pkg.nid=pkgi.package_id \
                WHERE pkg.short_name='hostmaster'\" 2>&1")
              _HM_NID=${_HM_NID//[^0-9]/}
              if [ ! -z "${_HM_NID}" ]; then
                _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_context \
                  SET name='hostmaster' WHERE nid='${_HM_NID}'\""
                echo ${_HM_NID} > ${_usEr}/log/hosting_context.pid
              fi
            fi
          fi
        fi
        _daily_process
        _run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
          WHERE task_type='delete' AND task_status='-1'\""
        _run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
          WHERE task_type='delete' AND task_status='0' AND executed='0'\""
        _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
        _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
          SET status=1 WHERE publish_path LIKE '%/aegir/distro/%'\""
        _check_old_empty_platforms
        _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
        _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
          SET status=-2 WHERE publish_path LIKE '%/aegir/distro/%'\""
        _THIS_HM_PLR=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
          SET status=1 WHERE publish_path LIKE '${_THIS_HM_PLR}'\""
        _purge_cruft_machine
        _if_hosted_sys
        if [ "${_hostedSys}" = "YES" ]; then
          rm -rf ${_usEr}/clients/admin &> /dev/null
          rm -rf ${_usEr}/clients/omega8ccgmailcom &> /dev/null
          rm -rf ${_usEr}/clients/nocomega8cc &> /dev/null
        fi
        rm -rf ${_usEr}/clients/*/backups &> /dev/null
        symlinks -dr ${_usEr}/clients &> /dev/null
        if [ -d "/home/${_HM_U}.ftp" ]; then
          symlinks -dr /home/${_HM_U}.ftp &> /dev/null
          rm -f /home/${_HM_U}.ftp/{.profile,.bash_logout,.bash_profile,.bashrc}
        fi
        _le_hm_ssl_check_update ${_HM_U}
        if [ "${_ENABLE_GOACCESS}" = "YES" ] && [ -e "${_usEr}/static/control/goaccess/ALL.info" ]; then
          _if_gen_goaccess "ALL"
        fi
        echo "Done for ${_usEr}"
        _enable_chattr ${_HM_U}.ftp
      else
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "...we have to wait..."
      fi
      echo
      echo
    fi
  done
  _shared_codebases_cleanup
  _ghost_codebases_cleanup
  _check_old_empty_hostmaster_platforms
  if [ -n "${_ENABLE_GOACCESS}" ] && [ "${_ENABLE_GOACCESS}" = "YES" ]; then
    _cleanup_weblogx
  fi
}

###--------------------###
[ ! -d "/data/u" ] && exit 1
echo "INFO: Daily maintenance start"
while [ -e "/run/boa_wait.pid" ]; do
  echo "Waiting for BOA queue availability..."
  sleep 5
done
#
_NOW=$(date +%y%m%d-%H%M%S 2>&1)
_NOW=${_NOW//[^0-9-]/}
_DOW=$(date +%u 2>&1)
_DOW=${_DOW//[^1-7]/}
_CHECK_HOST=$(uname -n 2>&1)
#
if [ -e "/root/.force.sites.verify.cnf" ]; then
  _FORCE_SITES_VERIFY=YES
else
  _FORCE_SITES_VERIFY=NO
fi
#
_MODULES_FORCE="automated_cron \
  backup_migrate \
  coder \
  cookie_cache_bypass \
  hacked \
  poormanscron \
  security_review \
  site_audit \
  syslog \
  watchdog_live \
  xhprof"
#
if [ "${_DOW}" = "2" ]; then
  _MODULES_ON_SEVEN=
  _MODULES_ON_SIX=
  _MODULES_OFF_SEVEN="coder \
    devel \
    filefield_nginx_progress \
    hacked \
    l10n_update \
    linkchecker \
    performance \
    security_review \
    site_audit \
    watchdog_live \
    xhprof"
  _MODULES_OFF_SIX="coder \
    cookie_cache_bypass \
    devel \
    hacked \
    l10n_update \
    linkchecker \
    performance \
    poormanscron \
    security_review \
    supercron \
    watchdog_live \
    xhprof"
else
  _MODULES_ON_SEVEN="robotstxt"
  _MODULES_ON_SIX="path_alias_cache robotstxt"
  _MODULES_OFF_SEVEN="dblog syslog backup_migrate"
  _MODULES_OFF_SIX="dblog syslog backup_migrate"
fi
#
_CTRL_TPL_FORCE_UPDATE=YES
#
# Check for last all nr
if [ -e "/data/all" ]; then
  cd /data/all
  listl=([0-9]*)
  _LAST_ALL=${listl[@]: -1}
  _O_CONTRIB="/data/all/${_LAST_ALL}/o_contrib"
  _O_CONTRIB_SEVEN="/data/all/${_LAST_ALL}/o_contrib_seven"
  _O_CONTRIB_EIGHT="/data/all/${_LAST_ALL}/o_contrib_eight"
  _O_CONTRIB_NINE="/data/all/${_LAST_ALL}/o_contrib_nine"
  _O_CONTRIB_TEN="/data/all/${_LAST_ALL}/o_contrib_ten"
elif [ -e "/data/disk/all" ]; then
  cd /data/disk/all
  listl=([0-9]*)
  _LAST_ALL=${listl[@]: -1}
  _O_CONTRIB="/data/disk/all/${_LAST_ALL}/o_contrib"
  _O_CONTRIB_SEVEN="/data/disk/all/${_LAST_ALL}/o_contrib_seven"
  _O_CONTRIB_EIGHT="/data/disk/all/${_LAST_ALL}/o_contrib_eight"
  _O_CONTRIB_NINE="/data/disk/all/${_LAST_ALL}/o_contrib_nine"
  _O_CONTRIB_TEN="/data/disk/all/${_LAST_ALL}/o_contrib_ten"
else
  _O_CONTRIB=NO
  _O_CONTRIB_SEVEN=NO
  _O_CONTRIB_EIGHT=NO
  _O_CONTRIB_NINE=NO
  _O_CONTRIB_TEN=NO
fi
#
mkdir -p /var/xdrago/log/daily
mkdir -p /var/xdrago/log/le
#
[ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
#
_find_fast_mirror_early
#
###--------------------###
if [ -z "${_SKYNET_MODE}" ] || [ "${_SKYNET_MODE}" = "ON" ]; then
  echo "INFO: Checking BARRACUDA version"
  rm -f /opt/tmp/barracuda-release.txt*
  curl -L -k -s \
    --max-redirs 10 \
    --retry 3 \
    --retry-delay 15 -A iCab \
    "${_urlHmr}/conf/version/barracuda-release.txt" \
    -o /opt/tmp/barracuda-release.txt
else
  rm -f /opt/tmp/barracuda-release.txt*
fi
if [ -e "/opt/tmp/barracuda-release.txt" ]; then
  _X_VERSION=$(cat /opt/tmp/barracuda-release.txt 2>&1)
  _VERSIONS_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
  if [ ! -z "${_X_VERSION}" ]; then
    _MY_EMAIL=${_MY_EMAIL//\\\@/\@}
    if [[ "${_MY_EMAIL}" =~ "omega8.cc" ]]; then
      _MY_EMAIL="notify@omega8.cc"
    fi
    if [[ "${_VERSIONS_TEST}" =~ "${_X_VERSION}" ]]; then
      _VERSIONS_TEST_RESULT=OK
      echo "INFO: Version test result: OK"
    else
      sT="release available, upgrade now!"
      cat <<EOF | s-nail -s "New ${_X_VERSION} ${sT}" ${_MY_EMAIL}

 There is new ${_X_VERSION} release available!

 Please review the changelog and upgrade as soon as possible to receive all security updates and new features.

 BOA Changelog: https://bit.ly/boa-changelog

 BOA Upgrade: https://bit.ly/boa-upgrade-docs

 ---
 This email has been sent by your BOA system release monitor

EOF
    echo "INFO: Update notice sent: OK"
    fi
  fi
fi
#
if [ -e "/run/daily-fix.pid" ]; then
  touch /var/xdrago/log/wait-for-daily
  exit 1
else
  touch /run/daily-fix.pid
  if [ -z "${_PERMISSIONS_FIX}" ]; then
    _PERMISSIONS_FIX=YES
  fi
  if [ -z "${_MODULES_FIX}" ]; then
    _MODULES_FIX=YES
  fi
  if [ -z "${_CLEAR_BOOST}" ]; then
    _CLEAR_BOOST=YES
  fi
  if [ -e "/data/all" ]; then
    if [ ! -e "/data/all/permissions-fix-post-up-${_xSrl}.info" ]; then
      rm -f /data/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/all/permissions-fix-post-up-${_xSrl}.info
    fi
  elif [ -e "/data/disk/all" ]; then
    if [ ! -e "/data/disk/all/permissions-fix-post-up-${_xSrl}.info" ]; then
      rm -f /data/disk/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/disk/all/permissions-fix-post-up-${_xSrl}.info
    fi
  fi

  su -s /bin/bash - aegir -c "drush8 cc drush" &> /dev/null
  wait
  rm -rf /var/aegir/.tmp/cache
  su -s /bin/bash - aegir -c "drush8 @hostmaster dis update syslog dblog -y" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster cron" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster cache-clear all" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster cache-clear all" &> /dev/null
  wait
  su -s /bin/bash - aegir -c "drush8 @hostmaster utf8mb4-convert-databases -y" &> /dev/null
  wait

  thisLog="/var/xdrago/log/daily/daily-${_NOW}.log"

  _daily_action > ${thisLog} 2>&1

  _incident_detection

  dhpWildPath="/etc/ssl/private/nginx-wild-ssl.dhp"
  if [ -e "/etc/ssl/private/4096.dhp" ]; then
    dhpPath="/etc/ssl/private/4096.dhp"
    _DIFF_T=$(diff -w -B ${dhpPath} ${dhpWildPath} 2>&1)
    if [ ! -z "${_DIFF_T}" ]; then
      cp -af ${dhpPath} ${dhpWildPath}
    fi
  fi

  if [ "${_NGINX_FORWARD_SECRECY}" = "YES" ]; then
    if [ ! -e "/etc/ssl/private/4096.dhp" ]; then
      echo "Generating 4096.dhp -- it may take a very long time..."
      openssl dhparam -out /etc/ssl/private/4096.dhp 4096 > /dev/null 2>&1 &
    fi
    for f in `find /etc/ssl/private/*.crt -type f`; do
      sslName=$(echo ${f} | cut -d'/' -f5 | awk '{ print $1}' | sed "s/.crt//g")
      sslFile="/etc/ssl/private/${sslName}.dhp"
      sslFileZ=${sslFile//\//\\\/}
      if [ -e "${f}" ] && [ ! -z "${sslName}" ]; then
        if [ ! -e "${sslFile}" ]; then
          openssl dhparam -out ${sslFile} 2048 &> /dev/null
        else
          _PFS_TEST=$(grep "DH PARAMETERS" ${sslFile} 2>&1)
          if [[ ! "${_PFS_TEST}" =~ "DH PARAMETERS" ]]; then
            openssl dhparam -out ${sslFile} 2048 &> /dev/null
          fi
          sslRootd="/var/aegir/config/server_master/nginx/pre.d"
          sslFileX="${sslRootd}/z_${sslName}_ssl_proxy.conf"
          sslFileY="${sslRootd}/${sslName}_ssl_proxy.conf"
          if [ -e "${sslFileX}" ]; then
            _DHP_TEST=$(grep "sslFile" ${sslFileX} 2>&1)
            if [[ "${_DHP_TEST}" =~ "sslFile" ]]; then
              sed -i "s/.*sslFile.*//g" ${sslFileX} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${sslFileX} &> /dev/null
              wait
            fi
          fi
          if [ -e "${sslFileY}" ]; then
            _DHP_TEST=$(grep "sslFile" ${sslFileY} 2>&1)
            if [[ "${_DHP_TEST}" =~ "sslFile" ]]; then
              sed -i "s/.*sslFile.*//g" ${sslFileY} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${sslFileY} &> /dev/null
              wait
            fi
          fi
          if [ -e "${sslFileX}" ]; then
            _DHP_TEST=$(grep "ssl_dhparam" ${sslFileX} 2>&1)
            if [[ ! "${_DHP_TEST}" =~ "ssl_dhparam" ]]; then
              sed -i "s/ssl_session_timeout .*/ssl_session_timeout          5m;\n  ssl_dhparam                  ${sslFileZ};/g" ${sslFileX} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${sslFileX} &> /dev/null
              wait
            fi
          fi
          if [ -e "${sslFileY}" ]; then
            _DHP_TEST=$(grep "ssl_dhparam" ${sslFileY} 2>&1)
            if [[ ! "${_DHP_TEST}" =~ "ssl_dhparam" ]]; then
              sed -i "s/ssl_session_timeout .*/ssl_session_timeout          5m;\n  ssl_dhparam                  ${sslFileZ};/g" ${sslFileY} &> /dev/null
              wait
              sed -i "s/ *$//g; /^$/d" ${sslFileY} &> /dev/null
              wait
            fi
          fi
        fi
      fi
    done
    if [ -e "/var/aegir/config" ]; then
      sed -i "s/.*ssl_stapling .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf               &> /dev/null
      wait
      sed -i "s/.*ssl_stapling_verify .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf        &> /dev/null
      wait
      sed -i "s/.*resolver .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf                   &> /dev/null
      wait
      sed -i "s/.*resolver_timeout .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf           &> /dev/null
      wait
      sed -i "s/ssl_prefer_server_ciphers .*/ssl_prefer_server_ciphers on;\n  ssl_stapling on;\n  ssl_stapling_verify on;\n  resolver 1.1.1.1 1.0.0.1 valid=300s;\n  resolver_timeout 5s;/g" \
        /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
      wait
      sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf                      &> /dev/null
      wait
    fi
    if [ -d "/data/u" ]; then
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /data/disk/*/config/server_*/nginx/vhost.d/*
    fi
    if [ -e "/var/aegir/config" ]; then
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx.conf
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/vhost.d/*
      sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf
    fi
    service nginx reload
  fi
fi

if [ "${_PERMISSIONS_FIX}" = "YES" ] \
  && [ ! -z "${_X_VERSION}" ] \
  && [ -e "/opt/tmp/barracuda-release.txt" ] \
  && [ ! -e "/data/all/permissions-fix-${_xSrl}-${_X_VERSION}-fixed-dz.info" ]; then
  echo "INFO: Fixing permissions in the /data/all tree..."
  find /data/conf -type d -exec chmod 0755 {} \; &> /dev/null
  find /data/conf -type f -exec chmod 0644 {} \; &> /dev/null
  chown -R root:root /data/conf &> /dev/null
  if [ -e "/data/all" ]; then
    find /data/all -type d -exec chmod 0755 {} \; &> /dev/null
    find /data/all -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 02775 /data/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
    chmod 02775 /data/all/000/core/*/sites/all/{modules,libraries,themes} &> /dev/null
    chown -R root:root /data/all &> /dev/null
    chown -R root:users /data/all/*/*/sites &> /dev/null
    chown -R root:users /data/all/000/core/*/sites &> /dev/null
  elif [ -e "/data/disk/all" ]; then
    find /data/disk/all -type d -exec chmod 0755 {} \; &> /dev/null
    find /data/disk/all -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 02775 /data/disk/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
    chmod 02775 /data/disk/all/000/core/*/sites/all/{modules,libraries,themes} &> /dev/null
    chown -R root:root /data/disk/all &> /dev/null
    chown -R root:users /data/disk/all/*/*/sites &> /dev/null
    chown -R root:users /data/disk/all/000/core/*/sites &> /dev/null
  fi
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  echo fixed > /data/all/permissions-fix-${_xSrl}-${_X_VERSION}-fixed-dz.info
fi
if [ ! -e "/var/backups/fix-sites-all-permsissions-${_xSrl}.txt" ]; then
  chmod 0751  /data/disk/*/distro/*/*/sites &> /dev/null
  chmod 0755  /data/disk/*/distro/*/*/sites/all &> /dev/null
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  echo FIXED > /var/backups/fix-sites-all-permsissions-${_xSrl}.txt
  echo "Permissions in sites/all tree just fixed"
fi
find /var/backups/old-sql* -mtime +1 -exec rm -rf {} \; &> /dev/null
find /var/backups/ltd/*/* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
find /var/backups/solr/*/* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
find /var/backups/jetty* -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/backups/dragon/* -mtime +7 -exec rm -rf {} \; &> /dev/null
_if_hosted_sys
if [ "${_hostedSys}" = "YES" ]; then
  if [ -d "/var/backups/codebases-cleanup" ]; then
    find /var/backups/codebases-cleanup/* -mtime +7 -exec rm -rf {} \; &> /dev/null
  elif [ -d "/data/disk/codebases-cleanup" ]; then
    find /data/disk/codebases-cleanup/* -mtime +7 -exec rm -rf {} \; &> /dev/null
  fi
fi
rm -f /tmp/.cron.*.pid
rm -f /tmp/.busy.*.pid
rm -f /data/disk/*/.tmp/.cron.*.pid
rm -f /data/disk/*/.tmp/.busy.*.pid

###
### Delete duplicity ghost pid file if older than 2 days
###
find /run/*_backup.pid -mtime +1 -exec rm -rf {} \; &> /dev/null
rm -f /run/daily-fix.pid
echo "INFO: Daily maintenance complete"
exit 0
###EOF2024###
