#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

tRee=dev
export tRee="${tRee}"

check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
    if [ ! -e "/dev/fd" ]; then
      if [ -e "/proc/self/fd" ]; then
        rm -rf /dev/fd
        ln -s /proc/self/fd /dev/fd
      fi
    fi
  else
    echo "ERROR: This script should be ran as a root user"
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

if [ -e "/root/.pause_heavy_tasks_maint.cnf" ]; then
  exit 0
fi

_X_SE="520devT02"
_WEBG=www-data
_OSR=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
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
crlGet="-L --max-redirs 10 -k -s --retry 10 --retry-delay 5 -A iCab"
aptYesUnth="-y --allow-unauthenticated"
cGet="config-get user.settings"
cSet="config-set user.settings"
vGet="variable-get"
vSet="variable-set --always-set"

###-------------SYSTEM-----------------###

os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _THIS_RV=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_THIS_RV}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
os_detection_minimal

apt_clean_update() {
  apt-get clean -qq 2> /dev/null
  rm -rf /var/lib/apt/lists/* &> /dev/null
  ${_APT_UPDATE} -qq 2> /dev/null
}

find_fast_mirror_early() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    apt_clean_update
    apt-get install netcat ${aptYesUnth} &> /dev/null
    apt-get install netcat-traditional ${aptYesUnth} &> /dev/null
    wait
  fi
  ffMirr=$(which ffmirror 2>&1)
  if [ -x "${ffMirr}" ]; then
    ffList="/var/backups/boa-mirrors-2024-01.txt"
    mkdir -p /var/backups
    if [ ! -e "${ffList}" ]; then
      echo "de.files.aegir.cc"  > ${ffList}
      echo "ny.files.aegir.cc" >> ${ffList}
      echo "sg.files.aegir.cc" >> ${ffList}
    fi
    if [ -e "${ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
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
  urlDev="http://${_USE_MIR}/dev"
  urlHmr="http://${_USE_MIR}/versions/${tRee}/boa/aegir"
}

extract_archive() {
  if [ ! -z "$1" ]; then
    case $1 in
      *.tar.bz2)   tar xjf $1    ;;
      *.tar.gz)    tar xzf $1    ;;
      *.tar.xz)    tar xvf $1    ;;
      *.bz2)       bunzip2 $1    ;;
      *.rar)       unrar x $1    ;;
      *.gz)        gunzip -q $1  ;;
      *.tar)       tar xf $1     ;;
      *.tbz2)      tar xjf $1    ;;
      *.tgz)       tar xzf $1    ;;
      *.zip)       unzip -qq $1  ;;
      *.Z)         uncompress $1 ;;
      *.7z)        7z x $1       ;;
      *)           echo "'$1' cannot be extracted via >extract<" ;;
    esac
    rm -f $1
  fi
}

get_dev_ext() {
  if [ ! -z "$1" ]; then
    curl ${crlGet} "${urlDev}/DEV/$1" -o "$1"
    if [ -e "$1" ]; then
      extract_archive "$1"
    else
      echo "OOPS: $1 failed download from ${urlDev}/DEV/$1"
    fi
  fi
}

enable_chattr() {
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

disable_chattr() {
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

run_drush8_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${nOw} ${_HM_U} running drush8 @${Dom} $1"
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${Dom} $1" &> /dev/null
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${Dom} $1" &> /dev/null
  fi
  wait
}

run_drush8_hmr_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${nOw} ${_HM_U} running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

run_drush8_hmr_master_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${nOw} aegir running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - aegir -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

run_drush8_nosilent_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    nOw=$(date +%y%m%d-%H%M%S 2>&1)
    echo "${nOw} ${_HM_U} running drush8 @${Dom} $1"
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${Dom} $1"
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${Dom} $1"
  fi
  wait
}

check_if_required_with_drush8() {
  _REQ=YES
  _REI_TEST=$(run_drush8_nosilent_cmd "pmi $1 --fields=required_by" 2>&1)
  _REL_TEST=$(echo "${_REI_TEST}" | grep "Required by" 2>&1)
  if [[ "${_REL_TEST}" =~ "was not found" ]]; then
    _REQ=NULL
    echo "_REQ for $1 is ${_REQ} in ${Dom} == null == via ${_REL_TEST}"
  else
    echo "CTRL _REL_TEST _REQ for $1 is ${_REQ} in ${Dom} == init == via ${_REL_TEST}"
    _REN_TEST=$(echo "${_REI_TEST}" | grep "Required by.*:.*none" 2>&1)
    if [[ "${_REN_TEST}" =~ "Required by" ]]; then
      _REQ=NO
      echo "_REQ for $1 is ${_REQ} in ${Dom} == 0 == via ${_REN_TEST}"
    else
      echo "CTRL _REN_TEST _REQ for $1 is ${_REQ} in ${Dom} == 1 == via ${_REN_TEST}"
      _REM_TEST=$(echo "${_REI_TEST}" | grep "Required by.*minimal" 2>&1)
      if [[ "${_REM_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${Dom} == 2 == via ${_REM_TEST}"
      fi
      _RES_TEST=$(echo "${_REI_TEST}" | grep "Required by.*standard" 2>&1)
      if [[ "${_RES_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${Dom} == 3 == via ${_RES_TEST}"
      fi
      _RET_TEST=$(echo "${_REI_TEST}" | grep "Required by.*testing" 2>&1)
      if [[ "${_RET_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${Dom} == 4 == via ${_RET_TEST}"
      fi
      _REH_TEST=$(echo "${_REI_TEST}" | grep "Required by.*hacked" 2>&1)
      if [[ "${_REH_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${Dom} == 5 == via ${_REH_TEST}"
      fi
      _RED_TEST=$(echo "${_REI_TEST}" | grep "Required by.*devel" 2>&1)
      if [[ "${_RED_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${Dom} == 6 == via ${_RED_TEST}"
      fi
      _REW_TEST=$(echo "${_REI_TEST}" | grep "Required by.*watchdog_live" 2>&1)
      if [[ "${_REW_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        "echo _REQ for $1 is ${_REQ} in ${Dom} == 7 == via ${_REW_TEST}"
      fi
    fi
    Profile=$(run_drush8_nosilent_cmd "${vGet} ^install_profile$" \
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
        echo "_REQ for $1 is ${_REQ} in ${Dom} == 8 == via ${_REP_TEST}"
      else
        echo "CTRL _REP_TEST _REQ for $1 is ${_REQ} in ${Dom} == 9 == via ${_REP_TEST}"
      fi
    fi
    _REA_TEST=$(echo "${_REI_TEST}" | grep "Required by.*apps" 2>&1)
    if [[ "${_REA_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${Dom} == 10 == via ${_REA_TEST}"
    fi
    _REF_TEST=$(echo "${_REI_TEST}" | grep "Required by.*features" 2>&1)
    if [[ "${_REF_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${Dom} == 11 == via ${_REF_TEST}"
    fi
  fi
}

check_if_skip() {
  for s in ${_MODULES_SKIP}; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ]; then
      _SKIP=YES
      #echo $1 is whitelisted and will not be disabled in ${Dom}
    fi
  done
}

check_if_force() {
  for s in ${_MODULES_FORCE}; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ]; then
      _FORCE=YES
      echo $1 is blacklisted and will be forcefully disabled in ${Dom}
    fi
  done
}

disable_modules_with_drush8() {
  for m in $1; do
    _SKIP=NO
    _FORCE=NO
    if [ ! -z "${_MODULES_SKIP}" ]; then
      check_if_skip "$m"
    fi
    if [ ! -z "${_MODULES_FORCE}" ]; then
      check_if_force "$m"
    fi
    if [ "${_SKIP}" = "NO" ]; then
      _MODULE_T=$(run_drush8_nosilent_cmd "pml --status=enabled \
        --type=module | grep \($m\)" 2>&1)
      if [[ "${_MODULE_T}" =~ "($m)" ]]; then
        if [ "${_FORCE}" = "NO" ]; then
          check_if_required_with_drush8 "$m"
        else
          echo "$m dependencies not checked in ${Dom} action forced"
          _REQ=FCE
        fi
        if [ "${_REQ}" = "FCE" ]; then
          run_drush8_cmd "dis $m -y"
          echo "$m FCE disabled in ${Dom}"
        elif [ "${_REQ}" = "NO" ]; then
          run_drush8_cmd "dis $m -y"
          echo "$m disabled in ${Dom}"
        elif [ "${_REQ}" = "NULL" ]; then
          echo "$m is not used in ${Dom}"
        else
          echo "$m is required and can not be disabled in ${Dom}"
        fi
      fi
    fi
  done
}

enable_modules_with_drush8() {
  for m in $1; do
    _MODULE_T=$(run_drush8_nosilent_cmd "pml --status=enabled \
      --type=module | grep \($m\)" 2>&1)
    if [[ "${_MODULE_T}" =~ "($m)" ]]; then
      _DO_NOTHING=YES
    else
      run_drush8_cmd "en $m -y"
      echo "$m enabled in ${Dom}"
    fi
  done
}

sync_user_register_protection_ini_vars() {
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
  if [ -e "${User}/static/control/enable_user_register_protection.info" ]; then
    mv -f ${User}/static/control/enable_user_register_protection.info \
      ${User}/static/control/enable_strict_user_register_protection.info
  fi
  if [ -e "${User}/static/control/disable_user_register_protection.info" ]; then
    mv -f ${User}/static/control/disable_user_register_protection.info \
      ${User}/static/control/ignore_user_register_protection.info
  fi
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ -e "${User}/static/control/enable_strict_user_register_protection.info" ]; then
    sed -i "s/.*enable.*user_register_protection.*/enable_strict_user_register_protection = TRUE/g" \
      ${_PLR_CTRL_F} &> /dev/null
    wait
    _ENABLE_STRICT_USER_REGISTER_PROTECTION=YES
  fi
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ] \
    && [ -e "${User}/static/control/ignore_user_register_protection.info" ]; then
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
  if [ -e "${User}/static/control/ignore_user_register_protection.info" ]; then
    _IGNORE_USER_REGISTER_PROTECTION=YES
  fi
}

fix_site_readonlymode() {
  if [ -e "${User}/log/imported.pid" ] \
    || [ -e "${User}/log/exported.pid" ]; then
    if [ -e "${Dir}/modules/readonlymode_fix.info" ]; then
      touch ${User}/log/ctrl/site.${Dom}.rom-fix.info
      rm -f ${Dir}/modules/readonlymode_fix.info
    fi
    if [ ! -e "${User}/log/ctrl/site.${Dom}.rom-fix.info" ]; then
      run_drush8_cmd "${vSet} site_readonly 0"
      touch ${User}/log/ctrl/site.${Dom}.rom-fix.info
    fi
  fi
}

fix_user_register_protection_with_vSet() {
  sync_user_register_protection_ini_vars
  if [ "${_IGNORE_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ ! -e "${Plr}/core" ]; then
    Prm=$(run_drush8_nosilent_cmd "${vGet} ^user_register$" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    Prm=${Prm//[^0-2]/}
    echo "Prm user_register for ${Dom} is ${Prm}"
    if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ]; then
      run_drush8_cmd "${vSet} user_register 0"
      echo "Prm user_register for ${Dom} set to 0"
    else
      if [ "${Prm}" = "1" ] || [ -z "${Prm}" ]; then
        run_drush8_cmd "${vSet} user_register 2"
        echo "Prm user_register for ${Dom} set to 2"
      fi
      run_drush8_cmd "${vSet} user_email_verification 1"
      echo "Prm user_email_verification for ${Dom} set to 1"
    fi
  fi
  fix_site_readonlymode
}

fix_robots_txt() {
  find ${Dir}/files/robots.txt -mtime +6 -exec rm -f {} \; &> /dev/null
  if [ ! -e "${Dir}/files/robots.txt" ] \
    && [ ! -e "${Plr}/profiles/hostmaster" ]; then
    curl -L --max-redirs 10 -k -s --retry 2 --retry-delay 5 \
      -A iCab "http://${Dom}/robots.txt?nocache=1&noredis=1" \
      -o ${Dir}/files/robots.txt
    if [ -e "${Dir}/files/robots.txt" ]; then
      echo >> ${Dir}/files/robots.txt
    fi
  fi
  _VAR_IF_PRESENT=
  if [ -f "${Dir}/files/robots.txt" ]; then
    _VAR_IF_PRESENT=$(grep "Disallow:" ${Dir}/files/robots.txt 2>&1)
  fi
  if [[ ! "${_VAR_IF_PRESENT}" =~ "Disallow:" ]]; then
    rm -f ${Dir}/files/robots.txt
  else
    chown ${_HM_U}:www-data ${Dir}/files/robots.txt &> /dev/null
    chmod 0664 ${Dir}/files/robots.txt &> /dev/null
    if [ -f "${Plr}/robots.txt" ] || [ -L "${Plr}/robots.txt" ]; then
      rm -f ${Plr}/robots.txt
    fi
  fi
}

fix_boost_cache() {
  if [ -e "${Plr}/cache" ]; then
    rm -rf ${Plr}/cache/*
    rm -f ${Plr}/cache/{.boost,.htaccess}
  else
    if [ -e "${Plr}/sites/all/drush/drushrc.php" ]; then
      mkdir -p ${Plr}/cache
    fi
  fi
  if [ -e "${Plr}/cache" ]; then
    chown ${_HM_U}:www-data ${Plr}/cache &> /dev/null
    chmod 02775 ${Plr}/cache &> /dev/null
  fi
}

fix_o_contrib_symlink() {
  if [ "${_O_CONTRIB_SEVEN}" != "NO" ]; then
    symlinks -d ${Plr}/modules &> /dev/null
    if [ -e "${Plr}/web.config" ] \
      && [ -e "${_O_CONTRIB_SEVEN}" ] \
      && [ ! -e "${Plr}/core" ]; then
      if [ ! -e "${Plr}/modules/o_contrib_seven" ]; then
        ln -sfn ${_O_CONTRIB_SEVEN} ${Plr}/modules/o_contrib_seven &> /dev/null
      fi
    elif [ -e "${Plr}/core" ] \
      && [ ! -e "${Plr}/core/themes/olivero" ] \
      && [ ! -e "${Plr}/core/themes/stable9" ] \
      && [ -e "${_O_CONTRIB_EIGHT}" ]; then
      if [ -e "${Plr}/modules/o_contrib_nine" ] \
        || [ -e "${Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${Plr}/modules/o_contrib_nine
        rm -f ${Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${Plr}/modules/o_contrib_ten" ] \
        || [ -e "${Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${Plr}/modules/o_contrib_ten
        rm -f ${Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ ! -e "${Plr}/modules/o_contrib_eight" ]; then
        ln -sfn ${_O_CONTRIB_EIGHT} ${Plr}/modules/o_contrib_eight &> /dev/null
      fi
    elif [ -e "${Plr}/core/themes/olivero" ] \
      && [ -e "${Plr}/core/themes/classy" ] \
      && [ -e "${_O_CONTRIB_NINE}" ]; then
      if [ -e "${Plr}/modules/o_contrib_eight" ] \
        || [ -e "${Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${Plr}/modules/o_contrib_eight
        rm -f ${Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${Plr}/modules/o_contrib_ten" ] \
        || [ -e "${Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${Plr}/modules/o_contrib_ten
        rm -f ${Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ ! -e "${Plr}/modules/o_contrib_nine" ]; then
        ln -sfn ${_O_CONTRIB_NINE} ${Plr}/modules/o_contrib_nine &> /dev/null
      fi
    elif [ -e "${Plr}/core/themes/olivero" ] \
      && [ ! -e "${Plr}/core/themes/classy" ] \
      && [ -e "${_O_CONTRIB_TEN}" ]; then
      if [ -e "${Plr}/modules/o_contrib_eight" ] \
        || [ -e "${Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${Plr}/modules/o_contrib_eight
        rm -f ${Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${Plr}/modules/o_contrib_nine" ] \
        || [ -e "${Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${Plr}/modules/o_contrib_nine
        rm -f ${Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ ! -e "${Plr}/modules/o_contrib_ten" ]; then
        ln -sfn ${_O_CONTRIB_TEN} ${Plr}/modules/o_contrib_ten &> /dev/null
      fi
    else
      if [ -e "${Plr}/modules/watchdog" ]; then
        if [ -e "${Plr}/modules/o_contrib" ]; then
          rm -f ${Plr}/modules/o_contrib &> /dev/null
        fi
      else
        if [ ! -e "${Plr}/modules/o_contrib" ] \
          && [ -e "${_O_CONTRIB}" ]; then
          ln -sfn ${_O_CONTRIB} ${Plr}/modules/o_contrib &> /dev/null
        fi
      fi
    fi
  fi
}

sql_convert() {
  sudo -u ${_HM_U}.ftp -H /opt/local/bin/sqlmagic convert @${Dom} to-${_SQL_CONVERT}
}

send_shutdown_notice() {
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
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
    || [ -e "/root/.host8.cnf" ]; then
    _BCC_EMAIL="omega8cc@gmail.com"
  else
    _BCC_EMAIL="${_MY_EMAIL}"
  fi
  _MAILX_TEST=$(mail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "GNU Mailutils" ]]; then
  cat <<EOF | mail -e -a "From: ${_MY_EMAIL}" -a "Bcc: ${_BCC_EMAIL}" \
    -s "ALERT! Shutdown of Hacked ${Dom} Site on ${_CHECK_HOST}" \
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

  ${Plr}

The system hostname is:

  ${_CHECK_HOST}

To learn more on what happened, how it was possible and
how to survive #Drupageddon, please read:

  https://omega8.cc/drupageddon-psa-2014-003-342

--
This email has been sent by your Aegir automatic system monitor.

EOF
  elif [[ "${_MAILX_TEST}" =~ "invalid" ]]; then
  cat <<EOF | mail -a "From: ${_MY_EMAIL}" -e -b ${_BCC_EMAIL} \
    -s "ALERT! Shutdown of Hacked ${Dom} Site on ${_CHECK_HOST}" \
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

  ${Plr}

The system hostname is:

  ${_CHECK_HOST}

To learn more on what happened, how it was possible and
how to survive #Drupageddon, please read:

  https://omega8.cc/drupageddon-psa-2014-003-342

--
This email has been sent by your Aegir automatic system monitor.

EOF
  else
  cat <<EOF | mail -r ${_MY_EMAIL} -e -b ${_BCC_EMAIL} \
    -s "ALERT! Shutdown of Hacked ${Dom} Site on ${_CHECK_HOST}" \
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

  ${Plr}

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

send_hacked_alert() {
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
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
    || [ -e "/root/.host8.cnf" ]; then
    _BCC_EMAIL="omega8cc@gmail.com"
  else
    _BCC_EMAIL="${_MY_EMAIL}"
  fi
  _MAILX_TEST=$(mail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "GNU Mailutils" ]]; then
  cat <<EOF | mail -e -a "From: ${_MY_EMAIL}" -a "Bcc: ${_BCC_EMAIL}" \
    -s "URGENT: The ${Dom} site on ${_CHECK_HOST} has been HACKED!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that the site ${Dom} has been hacked!

Common signatures of an attack which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${Plr}

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
by BOA-4.1.3. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

--
This email has been sent by your Aegir automatic system monitor.

EOF
  elif [[ "${_MAILX_TEST}" =~ "invalid" ]]; then
  cat <<EOF | mail -a "From: ${_MY_EMAIL}" -e -b ${_BCC_EMAIL} \
    -s "URGENT: The ${Dom} site on ${_CHECK_HOST} has been HACKED!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that the site ${Dom} has been hacked!

Common signatures of an attack which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${Plr}

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
by BOA-4.1.3. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

--
This email has been sent by your Aegir automatic system monitor.

EOF
  else
  cat <<EOF | mail -r ${_MY_EMAIL} -e -b ${_BCC_EMAIL} \
    -s "URGENT: The ${Dom} site on ${_CHECK_HOST} has been HACKED!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that the site ${Dom} has been hacked!

Common signatures of an attack which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${Plr}

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
by BOA-4.1.3. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

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

send_core_alert() {
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
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
    || [ -e "/root/.host8.cnf" ]; then
    _BCC_EMAIL="omega8cc@gmail.com"
  else
    _BCC_EMAIL="${_MY_EMAIL}"
  fi
  _MAILX_TEST=$(mail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "GNU Mailutils" ]]; then
  cat <<EOF | mail -e -a "From: ${_MY_EMAIL}" -a "Bcc: ${_BCC_EMAIL}" \
    -s "URGENT: The ${Dom} site on ${_CHECK_HOST} runs on not secure Drupal core!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that this site runs on not secure Drupal core:

  ${Dom}

The Drupageddon check result which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${Plr}

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
by BOA-4.1.3. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

--
This email has been sent by your Aegir automatic system monitor.

EOF
  elif [[ "${_MAILX_TEST}" =~ "invalid" ]]; then
  cat <<EOF | mail -a "From: ${_MY_EMAIL}" -e -b ${_BCC_EMAIL} \
    -s "URGENT: The ${Dom} site on ${_CHECK_HOST} runs on not secure Drupal core!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that this site runs on not secure Drupal core:

  ${Dom}

The Drupageddon check result which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${Plr}

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
by BOA-4.1.3. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

--
This email has been sent by your Aegir automatic system monitor.

EOF
  else
  cat <<EOF | mail -r ${_MY_EMAIL} -e -b ${_BCC_EMAIL} \
    -s "URGENT: The ${Dom} site on ${_CHECK_HOST} runs on not secure Drupal core!" \
    ${_ALRT_EMAIL}
Hello,

Our monitoring detected that this site runs on not secure Drupal core:

  ${Dom}

The Drupageddon check result which triggered this alert:

${_DETECTED}

The platform root directory for this site is:

  ${Plr}

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
by BOA-4.1.3. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

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

check_site_status_with_drush8() {
  _SITE_TEST=$(run_drush8_nosilent_cmd "status" 2>&1)
  if [[ "${_SITE_TEST}" =~ "Error:" ]] \
    || [[ "${_SITE_TEST}" =~ "Drush was attempting to connect" ]]; then
    _SITE_TEST_RESULT=ERROR
  else
    _SITE_TEST_RESULT=OK
  fi
  if [ "${_SITE_TEST_RESULT}" = "OK" ]; then
    _STATUS_BOOTSTRAP=$(run_drush8_nosilent_cmd "status bootstrap \
      | grep 'Drupal bootstrap.*:.*'" 2>&1)
    _STATUS_STATUS=$(run_drush8_nosilent_cmd "status status \
      | grep 'Database.*:.*'" 2>&1)
    if [[ "${_STATUS_BOOTSTRAP}" =~ "Drupal bootstrap" ]] \
      && [[ "${_STATUS_STATUS}" =~ "Database" ]]; then
      _STATUS=OK
      _RUN_DGN=NO
      if [ -e "${User}/static/control/drupalgeddon.info" ]; then
        _RUN_DGN=YES
      else
        if [ -e "/root/.force.drupalgeddon.cnf" ]; then
          _RUN_DGN=YES
        fi
      fi
      if [ -e "${Plr}/modules/o_contrib_seven" ] \
        && [ "${_RUN_DGN}" = "YES" ]; then
        if [ -L "/home/${_HM_U}.ftp/.drush/usr/drupalgeddon" ]; then
          run_drush8_cmd "en update -y"
          _DGDD_T=$(run_drush8_nosilent_cmd "drupalgeddon-test" 2>&1)
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
            echo "ALERT: THIS SITE IS PROBABLY BROKEN! ${Dir}"
            echo "${_DGDD_T}"
          else
            echo "ALERT: THIS SITE HAS BEEN HACKED! ${Dir}"
            _DETECTED="${_DGDD_T}"
            if [ ! -z "${_MY_EMAIL}" ]; then
              if [[ "${_DGDD_T}" =~ "Role \"megauser\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"drupaldev\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"owned\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"system\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"configure\" discovered" ]] \
                || [[ "${_DGDD_T}" =~ "User \"drplsys\" discovered" ]]; then
                if [ -e "${User}/config/server_master/nginx/vhost.d/${Dom}" ]; then
                  ### mv -f ${User}/config/server_master/nginx/vhost.d/${Dom} ${User}/config/server_master/nginx/vhost.d/.${Dom}
                  send_shutdown_notice
                fi
              else
                if [[ "${_DGDD_T}" =~ "has security vulnerabilities" ]]; then
                  send_core_alert
                else
                  send_hacked_alert
                fi
              fi
            fi
          fi
        else
          _DGMR_TEST=$(run_drush8_nosilent_cmd \
            "sqlq \"SELECT * FROM menu_router WHERE access_callback \
            = 'file_put_contents'\" | grep 'file_put_contents'" 2>&1)
          if [[ "${_DGMR_TEST}" =~ "file_put_contents" ]]; then
            echo "ALERT: THIS SITE HAS BEEN HACKED! ${Dir}"
            _DETECTED="file_put_contents as access_callback detected \
              in menu_router table"
            if [ ! -z "${_MY_EMAIL}" ]; then
              send_hacked_alert
            fi
          fi
          _DGMR_TEST=$(run_drush8_nosilent_cmd \
            "sqlq \"SELECT * FROM menu_router WHERE access_callback \
            = 'assert'\" | grep 'assert'" 2>&1)
          if [[ "${_DGMR_TEST}" =~ "assert" ]]; then
            echo "ALERT: THIS SITE HAS BEEN HACKED! ${Dir}"
            _DETECTED="assert as access_callback detected in menu_router table"
            if [ ! -z "${_MY_EMAIL}" ]; then
              send_hacked_alert
            fi
          fi
        fi
      fi
    else
      _STATUS=BROKEN
      echo "WARNING: THIS SITE IS BROKEN! ${Dir}"
    fi
  else
    _STATUS=UNKNOWN
    echo "WARNING: THIS SITE IS PROBABLY BROKEN? ${Dir}"
  fi
}

check_file_with_wildcard_path() {
  _WILDCARD_TEST=$(ls $1 2>&1)
  if [ -z "${_WILDCARD_TEST}" ]; then
    _FILE_EXISTS=NO
  else
    _FILE_EXISTS=YES
  fi
}

fix_modules() {
  _AUTO_CONFIG_ADVAGG=NO
  if [ -e "${Plr}/modules/o_contrib/advagg" ] \
    || [ -e "${Plr}/modules/o_contrib_seven/advagg" ]; then
    _MODULE_T=$(run_drush8_nosilent_cmd "pml --status=enabled \
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

  if [ -e "${Plr}/modules/o_contrib_seven" ] \
    && [ ! -e "${Plr}/core" ]; then
    _PRIV_TEST=$(run_drush8_nosilent_cmd "${vGet} ^file_default_scheme$" 2>&1)
    if [[ "${_PRIV_TEST}" =~ "No matching variable" ]]; then
      _PRIV_TEST_RESULT=NONE
    else
      _PRIV_TEST_RESULT=OK
    fi
    _AUTO_CNF_PF_DL=NO
    if [ "${_PRIV_TEST_RESULT}" = "OK" ]; then
      Pri=$(run_drush8_nosilent_cmd "${vGet} ^file_default_scheme$" \
        | cut -d: -f2 \
        | awk '{ print $1}' \
        | sed "s/['\"]//g" \
        | tr -d "\n" 2>&1)
      Pri=${Pri//[^a-z]/}
      if [ "$Pri" = "private" ] || [ "$Pri" = "public" ]; then
        echo Pri file_default_scheme for ${Dom} is $Pri
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
  if [ -e "${Plr}/sites/all/modules/fb/fb_settings.inc" ] \
    || [ -e "${Plr}/sites/all/modules/contrib/fb/fb_settings.inc" ]; then
    _AUTO_DT_FB_INT=YES
  else
    check_file_with_wildcard_path "${Plr}/profiles/*/modules/fb/fb_settings.inc"
    if [ "${_FILE_EXISTS}" = "YES" ]; then
      _AUTO_DT_FB_INT=YES
    else
      check_file_with_wildcard_path "${Plr}/profiles/*/modules/contrib/fb/fb_settings.inc"
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
  if [ -e "${Plr}/sites/all/modules/domain/settings.inc" ] \
    || [ -e "${Plr}/sites/all/modules/contrib/domain/settings.inc" ]; then
    _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
  else
    check_file_with_wildcard_path "${Plr}/profiles/*/modules/domain/settings.inc"
    if [ "${_FILE_EXISTS}" = "YES" ]; then
      _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
    else
      check_file_with_wildcard_path "${Plr}/profiles/*/modules/contrib/domain/settings.inc"
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
      || [ -e "${Plr}/profiles/commons" ]; then
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

  if [ -e "${Plr}/modules/o_contrib" ]; then
    if [ ! -e "${Plr}/modules/user" ] \
      || [ ! -e "${Plr}/sites/all/modules" ] \
      || [ ! -e "${Plr}/profiles" ]; then
      echo "WARNING: THIS PLATFORM IS BROKEN! ${Plr}"
    elif [ ! -e "${Plr}/modules/path_alias_cache" ]; then
      echo "WARNING: THIS PLATFORM IS NOT A VALID PRESSFLOW PLATFORM! ${Plr}"
    elif [ -e "${Plr}/modules/path_alias_cache" ] \
      && [ -e "${Plr}/modules/user" ]; then
      _MODX=ON
      if [ ! -z "${_MODULES_OFF_SIX}" ]; then
        disable_modules_with_drush8 "${_MODULES_OFF_SIX}"
      fi
      if [ ! -z "${_MODULES_ON_SIX}" ]; then
        enable_modules_with_drush8 "${_MODULES_ON_SIX}"
      fi
      run_drush8_cmd "sqlq \"UPDATE system SET weight = '-1' \
        WHERE type = 'module' AND name = 'path_alias_cache'\""
    fi
  elif [ -e "${Plr}/modules/o_contrib_seven" ]; then
    if [ ! -e "${Plr}/modules/user" ] \
      || [ ! -e "${Plr}/sites/all/modules" ] \
      || [ ! -e "${Plr}/profiles" ]; then
      echo "WARNING: THIS PLATFORM IS BROKEN! ${Plr}"
    else
      _MODX=ON
      if [ ! -z "${_MODULES_OFF_SEVEN}" ]; then
        disable_modules_with_drush8 "${_MODULES_OFF_SEVEN}"
      fi
      if [ "${_ENTITYCACHE_DONT_ENABLE}" = "NO" ]; then
        enable_modules_with_drush8 "entitycache"
      fi
      if [ ! -z "${_MODULES_ON_SEVEN}" ]; then
        enable_modules_with_drush8 "${_MODULES_ON_SEVEN}"
      fi
    fi
  fi
}

if_site_db_conversion() {
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
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
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
        for ${Dom} started"
      sql_convert
      _TIMP=$(date +%y%m%d-%H%M%S 2>&1)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${Dom} completed"
    fi
  fi
}

cleanup_ghost_platforms() {
  if [ -e "${Plr}" ]; then
    if [ ! -e "${Plr}/index.php" ] || [ ! -e "${Plr}/profiles" ]; then
      if [ ! -e "${Plr}/vendor" ]; then
        mkdir -p ${User}/undo
        ### mv -f ${Plr} ${User}/undo/ &> /dev/null
        echo "GHOST platform ${Plr} detected and moved to ${User}/undo/"
      fi
    fi
  fi
}

fix_seven_core_patch() {
  if [ ! -f "${Plr}/profiles/SA-CORE-2014-005-D7-fix.info" ]; then
    _PATCH_TEST=$(grep "foreach (array_values(\$data)" \
      ${Plr}/includes/database/database.inc 2>&1)
    if [[ "${_PATCH_TEST}" =~ "array_values" ]]; then
      echo fixed > ${Plr}/profiles/SA-CORE-2014-005-D7-fix.info
    else
      cd ${Plr}
      patch -p1 < /var/xdrago/conf/SA-CORE-2014-005-D7.patch
      chown ${_HM_U}:users ${Plr}/includes/database/*.inc &> /dev/null
      chmod 0664 ${Plr}/includes/database/*.inc &> /dev/null
      echo fixed > ${Plr}/profiles/SA-CORE-2014-005-D7-fix.info
    fi
    chown ${_HM_U}:users ${Plr}/profiles/*-fix.info &> /dev/null
    chmod 0664 ${Plr}/profiles/*-fix.info &> /dev/null
  fi
}

fix_static_permissions() {
  cleanup_ghost_platforms
  if [ -e "${Plr}/profiles" ]; then
    if [ -e "${Plr}/web.config" ] && [ ! -e "${Plr}/core" ]; then
      fix_seven_core_patch
    fi
    if [ ! -e "${User}/static/control/unlock.info" ] \
      && [ ! -e "${Plr}/skip.info" ]; then
      if [ ! -e "${User}/log/ctrl/plr.${PlrID}.ctm-lock-${_NOW}.info" ]; then
        chown -R ${_HM_U} ${Plr} &> /dev/null
        touch ${User}/log/ctrl/plr.${PlrID}.ctm-lock-${_NOW}.info
      fi
    elif [ -e "${User}/static/control/unlock.info" ] \
      && [ ! -e "${Plr}/skip.info" ]; then
      if [ ! -e "${User}/log/ctrl/plr.${PlrID}.ctm-unlock-${_NOW}.info" ]; then
        chown -R ${_HM_U}.ftp ${Plr} &> /dev/null
        touch ${User}/log/ctrl/plr.${PlrID}.ctm-unlock-${_NOW}.info
      fi
    fi
    if [ ! -f "${User}/log/ctrl/plr.${PlrID}.perm-fix-${_NOW}.info" ]; then
      find ${Plr} -type d -exec chmod 0775 {} \; &> /dev/null
      find ${Plr} -type f -exec chmod 0664 {} \; &> /dev/null
    fi
  fi
}

fix_expected_symlinks() {
  if [ ! -e "${Plr}/js.php" ] && [ -e "${Plr}" ]; then
    if [ -e "${Plr}/modules/o_contrib_seven" ] \
      && [ -e "${_O_CONTRIB_SEVEN}/js/js.php" ]; then
      ln -s ${_O_CONTRIB_SEVEN}/js/js.php ${Plr}/js.php &> /dev/null
    elif [ -e "${Plr}/modules/o_contrib" ] \
      && [ -e "${_O_CONTRIB}/js/js.php" ]; then
      ln -s ${_O_CONTRIB}/js/js.php ${Plr}/js.php &> /dev/null
    fi
  fi
}

fix_permissions() {
  ### modules,themes,libraries - profile level in ~/static
  searchStringT="/static/"
  case ${Plr} in
  *"$searchStringT"*)
  fix_static_permissions
  ;;
  esac
  ### modules,themes,libraries - platform level
  if [ -f "${Plr}/profiles/core-permissions-update-fix.info" ]; then
    rm -f ${Plr}/profiles/*permissions*.info
    rm -f ${Plr}/sites/all/permissions-fix*
  fi
  if [ ! -f "${User}/log/ctrl/plr.${PlrID}.perm-fix-${_NOW}.info" ] \
    && [ -e "${Plr}" ]; then
    mkdir -p ${Plr}/sites/all/{modules,themes,libraries,drush}
    find ${Plr}/sites/all/{modules,themes,libraries,drush}/*{.tar,.tar.gz,.zip} \
      -type f -exec rm -f {} \; &> /dev/null
    if [ ! -e "${User}/static/control/unlock.info" ] \
      && [ ! -e "${Plr}/skip.info" ]; then
      if [ ! -e "${User}/log/ctrl/plr.${PlrID}.lock-${_NOW}.info" ]; then
        chown -R ${_HM_U}:users \
          ${Plr}/sites/all/{modules,themes,libraries}/* &> /dev/null
        touch ${User}/log/ctrl/plr.${PlrID}.lock-${_NOW}.info
      fi
    elif [ -e "${User}/static/control/unlock.info" ] \
      && [ ! -e "${Plr}/skip.info" ]; then
      if [ ! -e "${User}/log/ctrl/plr.${PlrID}.unlock-${_NOW}.info" ]; then
        chown -R ${_HM_U}.ftp:users \
          ${Plr}/sites/all/{modules,themes,libraries}/* &> /dev/null
        touch ${User}/log/ctrl/plr.${PlrID}.unlock-${_NOW}.info
      fi
    fi
    chown ${_HM_U}:users \
      ${Plr}/sites/all/drush/drushrc.php \
      ${Plr}/sites \
      ${Plr}/sites/* \
      ${Plr}/sites/sites.php \
      ${Plr}/sites/all \
      ${Plr}/sites/all/{modules,themes,libraries,drush} &> /dev/null
    chmod 0751 ${Plr}/sites &> /dev/null
    chmod 0755 ${Plr}/sites/* &> /dev/null
    chmod 0644 ${Plr}/sites/*.php &> /dev/null
    chmod 0664 ${Plr}/autoload.php &> /dev/null
    chmod 0644 ${Plr}/sites/*.txt &> /dev/null
    chmod 0644 ${Plr}/sites/*.yml &> /dev/null
    chmod 0755 ${Plr}/sites/all/drush &> /dev/null
    find ${Plr}/sites/all/{modules,themes,libraries} -type d -exec \
      chmod 02775 {} \; &> /dev/null
    find ${Plr}/sites/all/{modules,themes,libraries} -type f -exec \
      chmod 0664 {} \; &> /dev/null
    ### expected symlinks
    fix_expected_symlinks
    ### known exceptions
    chmod -R 775 ${Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
    chown -R ${_HM_U}:www-data \
      ${Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
    touch ${User}/log/ctrl/plr.${PlrID}.perm-fix-${_NOW}.info
  fi
  if [ -e "${Dir}" ] \
    && [ -e "${Dir}/drushrc.php" ] \
    && [ -e "${Dir}/files" ] \
    && [ -e "${Dir}/private" ]; then
    ### directory and settings files - site level
    if [ ! -e "${Dir}/modules" ]; then
      mkdir ${Dir}/modules
    fi
    if [ -e "${Dir}/aegir.services.yml" ]; then
      rm -f ${Dir}/aegir.services.yml
    fi
    chown ${_HM_U}:users ${Dir} &> /dev/null
    chown ${_HM_U}:www-data \
      ${Dir}/{local.settings.php,settings.php,civicrm.settings.php,solr.php} &> /dev/null
    find ${Dir}/*.php -type f -exec chmod 0440 {} \; &> /dev/null
    chmod 0640 ${Dir}/civicrm.settings.php &> /dev/null
    ### modules,themes,libraries - site level
    find ${Dir}/{modules,themes,libraries}/*{.tar,.tar.gz,.zip} -type f -exec \
      rm -f {} \; &> /dev/null
    rm -f ${Dir}/modules/local-allow.info
    if [ ! -e "${User}/static/control/unlock.info" ] \
      && [ ! -e "${Plr}/skip.info" ]; then
      chown -R ${_HM_U}:users \
        ${Dir}/{modules,themes,libraries}/* &> /dev/null
    elif [ -e "${User}/static/control/unlock.info" ] \
      && [ ! -e "${Plr}/skip.info" ]; then
      chown -R ${_HM_U}.ftp:users \
        ${Dir}/{modules,themes,libraries}/* &> /dev/null
    fi
    chown ${_HM_U}:users \
      ${Dir}/drushrc.php \
      ${Dir}/{modules,themes,libraries} &> /dev/null
    find ${Dir}/{modules,themes,libraries} -type d -exec \
      chmod 02775 {} \; &> /dev/null
    find ${Dir}/{modules,themes,libraries} -type f -exec \
      chmod 0664 {} \; &> /dev/null
    ### files - site level
    chown -L -R ${_HM_U}:www-data ${Dir}/files &> /dev/null
    find ${Dir}/files/ -type d -exec chmod 02775 {} \; &> /dev/null
    find ${Dir}/files/ -type f -exec chmod 0664 {} \; &> /dev/null
    chmod 02775 ${Dir}/files &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files/{tmp,images,pictures,css,js} &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files/{advagg_css,advagg_js,ctools} &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files/{ctools/css,imagecache,locations} &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files/{xmlsitemap,deployment,styles,private} &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files/{civicrm,civicrm/templates_c} &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files/{civicrm/upload,civicrm/persist} &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/files/{civicrm/custom,civicrm/dynamic} &> /dev/null
    ### private - site level
    chown -L -R ${_HM_U}:www-data ${Dir}/private &> /dev/null
    find ${Dir}/private/ -type d -exec chmod 02775 {} \; &> /dev/null
    find ${Dir}/private/ -type f -exec chmod 0664 {} \; &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/private &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/private/{files,temp} &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/private/files/backup_migrate &> /dev/null
    chown ${_HM_U}:www-data ${Dir}/private/files/backup_migrate/{manual,scheduled} &> /dev/null
    chown -L -R ${_HM_U}:www-data ${Dir}/private/config &> /dev/null
    _DB_HOST_PRESENT=$(grep "^\$_SERVER\['db_host'\] = \$options\['db_host'\];" \
      ${Dir}/drushrc.php 2>&1)
    if [[ "${_DB_HOST_PRESENT}" =~ "db_host" ]]; then
      if [ "${_FORCE_SITES_VERIFY}" = "YES" ]; then
        run_drush8_hmr_cmd "hosting-task @${Dom} verify --force"
      fi
    else
      echo "\$_SERVER['db_host'] = \$options['db_host'];" >> ${Dir}/drushrc.php
      run_drush8_hmr_cmd "hosting-task @${Dom} verify --force"
    fi
  fi
}

convert_controls_orig() {
  if [ -e "${_CTRL_DIR}/$1.info" ] \
    || [ -e "${User}/static/control/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      cp -af ${_CTRL_F_TPL} ${_CTRL_F}
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

convert_controls_orig_no_global() {
  if [ -e "${_CTRL_DIR}/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      cp -af ${_CTRL_F_TPL} ${_CTRL_F}
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

convert_controls_value() {
  if [ -e "${_CTRL_DIR}/$1.info" ] \
    || [ -e "${User}/static/control/$1.info" ]; then
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

convert_controls_renamed() {
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

fix_control_settings() {
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
    convert_controls_orig "$ctrl"
  done
  for ctrl in ${_CTRL_NAME_VALUE}; do
    convert_controls_value "$ctrl"
  done
  for ctrl in ${_CTRL_NAME_RENAMED}; do
    convert_controls_renamed "$ctrl"
  done
}

fix_platform_system_control_settings() {
  _CTRL_NAME_ORIG="enable_user_register_protection \
     entitycache_dont_enable \
     views_cache_bully_dont_enable \
     views_content_cache_dont_enable"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    convert_controls_orig "$ctrl"
  done
}

fix_site_system_control_settings() {
  _CTRL_NAME_ORIG="disable_user_register_protection"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    convert_controls_orig_no_global "$ctrl"
  done
}

cleanup_ini() {
  if [ -e "${_CTRL_F}" ]; then
    sed -i "s/^;;.*//g"   ${_CTRL_F} &> /dev/null
    wait
    sed -i "/^$/d"        ${_CTRL_F} &> /dev/null
    wait
    sed -i "s/^\[/\n\[/g" ${_CTRL_F} &> /dev/null
    wait
  fi
}

add_note_platform_ini() {
  if [ -e "${_CTRL_F}" ]; then
    echo "" >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  This is a platform level ACTIVE INI file which can be used to modify"     >> ${_CTRL_F}
    echo ";;  default BOA system behaviour for all sites hosted on this platform."      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> ${_CTRL_F}
    echo ";;  default.boa_platform_control.ini, since this ACTIVE INI file"             >> ${_CTRL_F}
    echo ";;  may not include all options available after upgrade to BOA-${_X_SE}"      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> ${_CTRL_F}
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
  fi
}

add_note_site_ini() {
  if [ -e "${_CTRL_F}" ]; then
    echo "" >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  This is a site level ACTIVE INI file which can be used to modify"         >> ${_CTRL_F}
    echo ";;  default BOA system behaviour for this site only."                         >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> ${_CTRL_F}
    echo ";;  default.boa_site_control.ini, since this ACTIVE INI file"                 >> ${_CTRL_F}
    echo ";;  may not include all options available after upgrade to BOA-${_X_SE}"      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> ${_CTRL_F}
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
  fi
}

fix_platform_control_files() {
  if [ -e "/data/conf/default.boa_platform_control.ini" ]; then
    if [ ! -e "${Plr}/sites/all/modules/default.boa_platform_control.ini" ] \
      || [ "${_CTRL_TPL_FORCE_UPDATE}" = "YES" ]; then
      cp -af /data/conf/default.boa_platform_control.ini \
        ${Plr}/sites/all/modules/ &> /dev/null
      chown ${_HM_U}:users ${Plr}/sites/all/modules/default.boa_platform_control.ini &> /dev/null
      chmod 0664 ${Plr}/sites/all/modules/default.boa_platform_control.ini &> /dev/null
    fi
    _CTRL_F_TPL="${Plr}/sites/all/modules/default.boa_platform_control.ini"
    _CTRL_F="${Plr}/sites/all/modules/boa_platform_control.ini"
    _CTRL_DIR="${Plr}/sites/all/modules"
    fix_control_settings
    fix_platform_system_control_settings
    cleanup_ini
    add_note_platform_ini
  fi
}

fix_site_control_files() {
  if [ -e "/data/conf/default.boa_site_control.ini" ]; then
    if [ ! -e "${Dir}/modules/default.boa_site_control.ini" ] \
      || [ "${_CTRL_TPL_FORCE_UPDATE}" = "YES" ]; then
      cp -af /data/conf/default.boa_site_control.ini ${Dir}/modules/ &> /dev/null
      chown ${_HM_U}:users ${Dir}/modules/default.boa_site_control.ini &> /dev/null
      chmod 0664 ${Dir}/modules/default.boa_site_control.ini &> /dev/null
    fi
    _CTRL_F_TPL="${Dir}/modules/default.boa_site_control.ini"
    _CTRL_F="${Dir}/modules/boa_site_control.ini"
    _CTRL_DIR="${Dir}/modules"
    fix_control_settings
    fix_site_system_control_settings
    cleanup_ini
    add_note_site_ini
  fi
}

cleanup_ghost_vhosts() {
  for Site in `find ${User}/config/server_master/nginx/vhost.d -maxdepth 1 \
    -mindepth 1 -type f | sort`; do
    Dom=$(echo $Site | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    if [[ "${Dom}" =~ ".restore"($) ]]; then
      mkdir -p ${User}/undo
      ### mv -f ${User}/.drush/${Dom}.alias.drushrc.php ${User}/undo/ &> /dev/null
      ### mv -f ${User}/config/server_master/nginx/vhost.d/${Dom} ${User}/undo/ &> /dev/null
      echo "GHOST vhost for ${Dom} detected and moved to ${User}/undo/"
    fi
    if [ -e "${User}/config/server_master/nginx/vhost.d/${Dom}" ]; then
      Plx=$(cat ${User}/config/server_master/nginx/vhost.d/${Dom} \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "$Plx" =~ "aegir/distro" ]] \
        || [[ "${Dom}" =~ (^)"https." ]] \
        || [[ "${Dom}" =~ "--CDN"($) ]]; then
        _SKIP_VHOST=YES
      else
        if [ ! -e "${User}/.drush/${Dom}.alias.drushrc.php" ]; then
          mkdir -p ${User}/undo
          ### mv -f $Site ${User}/undo/ &> /dev/null
          echo "GHOST vhost for ${Dom} with no drushrc detected and moved to ${User}/undo/"
        fi
      fi
    fi
  done
}

cleanup_ghost_drushrc() {
  for Alias in `find ${User}/.drush/*.alias.drushrc.php -maxdepth 1 -type f \
    | sort`; do
    AliasName=$(echo "${Alias}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
    AliasName=$(echo "${AliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [[ "${AliasName}" =~ (^)"server_" ]] \
      || [[ "${AliasName}" =~ (^)"hostmaster" ]]; then
      _IS_SITE=NO
    elif [[ "${AliasName}" =~ (^)"platform_" ]]; then
      Plm=$(cat ${Alias} \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -d "${Plm}" ]; then
        if [ ! -e "${Plm}/index.php" ] || [ ! -e "${Plm}/profiles" ]; then
          if [ ! -e "${Plm}/vendor" ]; then
            mkdir -p ${User}/undo
            ### mv -f ${Plm} ${User}/undo/ &> /dev/null
            echo "GHOST broken platform dir ${Plm} detected and moved to ${User}/undo/"
            ### mv -f ${Alias} ${User}/undo/ &> /dev/null
            echo "GHOST broken platform alias ${Alias} detected and moved to ${User}/undo/"
          fi
        fi
      else
        mkdir -p ${User}/undo
        ### mv -f ${Alias} ${User}/undo/ &> /dev/null
        echo "GHOST nodir platform alias ${Alias} detected and moved to ${User}/undo/"
      fi
    else
      _T_SITE_NAME="${AliasName}"
      if [[ "${_T_SITE_NAME}" =~ ".restore"($) ]]; then
        _IS_SITE=NO
        mkdir -p ${User}/undo
        ### mv -f ${User}/.drush/${_T_SITE_NAME}.alias.drushrc.php ${User}/undo/ &> /dev/null
        ### mv -f ${User}/config/server_master/nginx/vhost.d/${_T_SITE_NAME} ${User}/undo/ &> /dev/null
        echo "GHOST drushrc and vhost for ${_T_SITE_NAME} detected and moved to ${User}/undo/"
      else
        _T_SITE_FDIR=$(cat ${Alias} \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        if [ -e "${_T_SITE_FDIR}/drushrc.php" ] \
          && [ -e "${_T_SITE_FDIR}/files" ] \
          && [ -e "${_T_SITE_FDIR}/private" ]; then
          if [ ! -e "${Dir}/modules" ]; then
            mkdir ${Dir}/modules
          fi
          _IS_SITE=YES
        else
          mkdir -p ${User}/undo
          ### mv -f ${User}/.drush/${_T_SITE_NAME}.alias.drushrc.php ${User}/undo/ &> /dev/null
          echo "GHOST drushrc for ${_T_SITE_NAME} detected and moved to ${User}/undo/"
          if [[ ! "${_T_SITE_FDIR}" =~ "aegir/distro" ]]; then
            ### mv -f ${User}/config/server_master/nginx/vhost.d/${_T_SITE_NAME} ${User}/undo/ghost-vhost-${_T_SITE_NAME} &> /dev/null
            echo "GHOST vhost for ${_T_SITE_NAME} detected and moved to ${User}/undo/"
          fi
          if [ -d "${_T_SITE_FDIR}" ]; then
            ### mv -f ${_T_SITE_FDIR} ${User}/undo/ghost-site-${_T_SITE_NAME} &> /dev/null
            echo "GHOST site dir for ${_T_SITE_NAME} detected and moved from ${_T_SITE_FDIR} to ${User}/undo/"
          fi
        fi
      fi
    fi
  done
}

le_hm_ssl_check_update() {
  exeLe="${User}/tools/le/dehydrated"
  if [ -e "${User}/log/domain.txt" ]; then
    hmFront=$(cat ${User}/log/domain.txt 2>&1)
    hmFront=$(echo -n ${hmFront} | tr -d "\n" 2>&1)
  fi
  if [ -e "${User}/log/extra_domain.txt" ]; then
    hmFrontExtra=$(cat ${User}/log/extra_domain.txt 2>&1)
    hmFrontExtra=$(echo -n ${hmFrontExtra} | tr -d "\n" 2>&1)
  fi
  if [ -z "${hmFront}" ]; then
    if [ -e "${User}/.drush/hostmaster.alias.drushrc.php" ]; then
      hmFront=$(cat ${User}/.drush/hostmaster.alias.drushrc.php \
        | grep "uri'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    fi
  fi
  if [ -x "${exeLe}" ] \
    && [ ! -z "${hmFront}" ] \
    && [ -e "${User}/tools/le/certs/${hmFront}/fullchain.pem" ]; then
    _DOM=$(date +%e 2>&1)
    _DOM=${_DOM//[^0-9]/}
    _RDM=$((RANDOM%25+6))
    if [ "${_DOM}" = "${_RDM}" ] || [ -e "${User}/static/control/force-ssl-certs-rebuild.info" ]; then
      if [ ! -e "${User}/log/ctrl/site.${hmFront}.cert-x1-rebuilt.info" ]; then
        leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
        mkdir -p ${User}/log/ctrl
        touch ${User}/log/ctrl/site.${hmFront}.cert-x1-rebuilt.info
      else
        leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
      fi
    else
      leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
    fi
    if [ ! -z "${hmFrontExtra}" ]; then
      echo "Running LE cert check directly for hostmaster ${_HM_U} with ${hmFrontExtra}"
      su -s /bin/bash - ${_HM_U} -c "${exeLe} ${leParams} --domain ${hmFront} --domain ${hmFrontExtra}"
      wait
    else
      echo "Running LE cert check directly for hostmaster ${_HM_U}"
      su -s /bin/bash - ${_HM_U} -c "${exeLe} ${leParams} --domain ${hmFront}"
      wait
    fi
  fi
}

le_ssl_check_update() {
  exeLe="${User}/tools/le/dehydrated"
  Vht="${User}/config/server_master/nginx/vhost.d/${Dom}"
  if [ -x "${exeLe}" ] && [ -e "${Vht}" ]; then
    _SSL_ON_TEST=$(cat ${Vht} | grep "443 ssl" 2>&1)
    if [[ "${_SSL_ON_TEST}" =~ "443 ssl" ]]; then
      if [ -e "${User}/tools/le/certs/${Dom}/fullchain.pem" ]; then
        echo "Running LE cert check directly for ${Dom}"
        useAliases=""
        siteAliases=`cat ${Vht} \
          | grep "server_name" \
          | sed "s/server_name//g; s/;//g" \
          | sort | uniq \
          | tr -d "\n" \
          | sed "s/  / /g; s/  / /g; s/  / /g" \
          | sort | uniq`
        for alias in `echo "${siteAliases}"`; do
          if [ -e "${User}/static/control/wildcard-enable-${Dom}.info" ]; then
            Dom=$(echo ${Dom} | sed 's/^www.//g' 2>&1)
            if [ -z "${useAliases}" ] \
              && [ ! -z "${alias}" ] \
              && [[ ! "${alias}" =~ ".nodns." ]] \
              && [[ ! "${alias}" =~ "${Dom}" ]]; then
              useAliases="--domain ${alias}"
              echo "--domain ${alias}"
            else
              if [ ! -z "${alias}" ] \
                && [[ ! "${alias}" =~ ".nodns." ]] \
                && [[ ! "${alias}" =~ "${Dom}" ]]; then
                useAliases="${useAliases} --domain ${alias}"
                echo "--domain ${alias}"
              fi
            fi
          else
            if [[ ! "${alias}" =~ ".nodns." ]]; then
              echo "--domain ${alias}"
              if [ -z "${useAliases}" ] && [ ! -z "${alias}" ]; then
                useAliases="--domain ${alias}"
              else
                if [ ! -z "${alias}" ]; then
                  useAliases="${useAliases} --domain ${alias}"
                fi
              fi
            else
              echo "ignored alias ${alias}"
            fi
          fi
        done
		_DOM=$(date +%e 2>&1)
		_DOM=${_DOM//[^0-9]/}
		_RDM=$((RANDOM%25+6))
		if [ "${_DOM}" = "${_RDM}" ] || [ -e "${User}/static/control/force-ssl-certs-rebuild.info" ]; then
		  if [ ! -e "${User}/log/ctrl/site.${Dom}.cert-x1-rebuilt.info" ]; then
			leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
			mkdir -p ${User}/log/ctrl
			touch ${User}/log/ctrl/site.${Dom}.cert-x1-rebuilt.info
		  else
			leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
		  fi
		else
		  leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
		fi
        dhArgs="--domain ${Dom} ${useAliases}"
        if [ -e "${User}/static/control/wildcard-enable-${Dom}.info" ]; then
          Dom=$(echo ${Dom} | sed 's/^www.//g' 2>&1)
          echo "--domain *.${Dom}"
          if [ ! -e "${User}/tools/le/hooks/cloudflare/hook.py" ]; then
            mkdir -p ${User}/tools/le/hooks
            cd ${User}/tools/le
            git clone https://github.com/kappataumu/letsencrypt-cloudflare-hook hooks/cloudflare
            pip install -r hooks/cloudflare/requirements.txt
          fi
          if [ -e "${User}/tools/le/hooks/cloudflare/hook.py" ]; then
            if [ -e "${User}/tools/le/config" ]; then
              dhArgs="--alias ${Dom} --domain *.${Dom} --domain ${Dom} ${useAliases}"
              dhArgs=" ${dhArgs} --challenge dns-01 --hook '${User}/tools/le/hooks/cloudflare/hook.py'"
            fi
          fi
        fi
        echo "leParams is ${leParams}"
        echo "dhArgs is ${dhArgs}"
        su -s /bin/bash - ${_HM_U} -c "${exeLe} ${leParams} ${dhArgs}"
        wait
        if [ -e "${User}/static/control/wildcard-enable-${Dom}.info" ]; then
          sleep 30
        else
          sleep 3
        fi
        echo ${_MOMENT} >> /var/xdrago/log/le/${Dom}
      fi
    fi
  fi
}

if_gen_goaccess() {
  PrTestPower=$(grep "POWER" /root/.${_HM_U}.octopus.cnf 2>&1)
  PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
  PrTestCluster=$(grep "CLUSTER" /root/.${_HM_U}.octopus.cnf 2>&1)
  if [[ "${PrTestPower}" =~ "POWER" ]] \
    || [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${PrTestCluster}" =~ "CLUSTER" ]]; then
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
      fi
    fi
  fi
}

process() {
  cleanup_ghost_vhosts
  cleanup_ghost_drushrc
  for Site in `find ${User}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _MOMENT=$(date +%y%m%d-%H%M%S 2>&1)
    echo ${_MOMENT} Start Counting Site $Site
    Dom=$(echo $Site | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    Dan=
    if [ -e "${User}/config/server_master/nginx/vhost.d/${Dom}" ]; then
      Plx=$(cat ${User}/config/server_master/nginx/vhost.d/${Dom} \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "$Plx" =~ "aegir/distro" ]]; then
        Dan=hostmaster
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
      echo "Dom is ${Dom}"
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
      if [ -e "${Plr}" ]; then
        if [ "${_NEW_SSL}" = "YES" ]; then
          PlrID=$(echo ${Plr} \
            | openssl md5 \
            | awk '{ print $2}' \
            | tr -d "\n" 2>&1)
        else
          PlrID=$(echo ${Plr} \
            | openssl md5 \
            | tr -d "\n" 2>&1)
        fi
        fix_platform_control_files
        fix_o_contrib_symlink
        if [ -e "${Dir}/drushrc.php" ]; then
          cd ${Dir}
          if [ "${Dan}" = "hostmaster" ]; then
            _STATUS=OK
            if [ ! -f "${User}/log/ctrl/plr.${PlrID}.hm-fix-${_NOW}.info" ]; then
              su -s /bin/bash - ${_HM_U} -c "drush8 cc drush" &> /dev/null
              wait
              rm -rf ${User}/.tmp/cache
              run_drush8_hmr_cmd "dis update syslog dblog -y"
              run_drush8_hmr_cmd "cron"
              run_drush8_hmr_cmd "cache-clear all"
              run_drush8_hmr_cmd "cache-clear all"
              run_drush8_hmr_cmd "utf8mb4-convert-databases -y"
              touch ${User}/log/ctrl/plr.${PlrID}.hm-fix-${_NOW}.info
            fi
          else
            if [ -e "${Plr}/modules/o_contrib_seven" ] \
              || [ -e "${Plr}/modules/o_contrib" ]; then
              check_site_status_with_drush8
            fi
          fi
          if [ ! -z "${Dan}" ] \
            && [ "${Dan}" != "hostmaster" ]; then
            if_site_db_conversion
            searchStringB=".dev."
            searchStringC=".devel."
            searchStringD=".temp."
            searchStringE=".tmp."
            searchStringF=".temporary."
            searchStringG=".test."
            searchStringH=".testing."
            case ${Dom} in
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
                  fix_modules
                #fi
                fix_robots_txt
              fi
              le_ssl_check_update
              if_gen_goaccess ${Dom}
              ;;
            esac
            fix_site_control_files
            if [ -e "${Plr}/modules/o_contrib_seven" ] \
              || [ -e "${Plr}/modules/o_contrib" ]; then
              if [ "${_CLEAR_BOOST}" = "YES" ]; then
                fix_boost_cache
              fi
              fix_user_register_protection_with_vSet
              if [[ "${_X_SE}" =~ "OFF" ]]; then
                run_drush8_cmd "advagg-force-new-aggregates"
                run_drush8_cmd "cache-clear all"
                run_drush8_cmd "cache-clear all"
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
        if [ -e "${Plr}/profiles" ] \
          && [ -e "${Plr}/web.config" ] \
          && [ ! -e "${Plr}/core" ] \
          && [ ! -f "${Plr}/profiles/SA-CORE-2014-005-D7-fix.info" ]; then
          _PATCH_TEST=$(grep "foreach (array_values(\$data)" \
            ${Plr}/includes/database/database.inc 2>&1)
          if [[ "${_PATCH_TEST}" =~ "array_values" ]]; then
            _DONT_TOUCH_PERMISSIONS="${_DONT_TOUCH_PERMISSIONS}"
          else
            _DONT_TOUCH_PERMISSIONS=NO
          fi
        fi
        if [ "${_DONT_TOUCH_PERMISSIONS}" = "NO" ] \
          && [ "${_PERMISSIONS_FIX}" = "YES" ]; then
          fix_permissions
        fi
      fi
     _MOMENT=$(date +%y%m%d-%H%M%S 2>&1)
     echo ${_MOMENT} End Counting Site $Site
    fi
  done
}

delete_this_empty_hostmaster_platform() {
  run_drush8_hmr_master_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

check_old_empty_hostmaster_platforms() {
  if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ] \
	&& [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
	_DO_NOTHING=YES
  else
	if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
	  || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
	  || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
	  || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
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
          delete_this_empty_hostmaster_platform
        fi
      done
    fi
  fi
}

delete_this_platform() {
  run_drush8_hmr_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

check_old_empty_platforms() {
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
    || [ -e "/root/.host8.cnf" ]; then
    if [[ "${_CHECK_HOST}" =~ "demo.aegir.cc" ]] \
      || [ -e "${User}/static/control/platforms.info" ] \
      || [ -e "/root/.debug.cnf" ]; then
      _DO_NOTHING=YES
    else
      if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ] \
        && [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
        _DO_NOTHING=YES
      else
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
          || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
          || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
          || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
          _DEL_OLD_EMPTY_PLATFORMS="60"
        else
          _DEL_OLD_EMPTY_PLATFORMS="90"
        fi
      fi
    fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on ${_HM_U} instance"
      for Platform in `find ${User}/.drush/platform_* -maxdepth 1 -mtime \
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
          ${User}/.drush/*.drushrc.php \
          | grep site_path 2>&1)
        if [ ! -e "${_T_PFM_ROOT}/sites/all" ] \
          || [ ! -e "${_T_PFM_ROOT}/index.php" ]; then
          if [ ! -e "${_T_PFM_ROOT}/vendor" ]; then
            mkdir -p ${User}/undo
            ### mv -f ${User}/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php ${User}/undo/ &> /dev/null
            echo "GHOST platform ${_T_PFM_ROOT} detected and moved to ${User}/undo/"
          fi
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_ROOT}/sites/all" ]; then
          delete_this_platform
        fi
      done
    fi
  fi
}

purge_cruft_machine() {

  if [ ! -z "${_DEL_OLD_TMP}" ] && [ "${_DEL_OLD_TMP}" -gt "0" ]; then
    _PURGE_TMP="${_DEL_OLD_TMP}"
  else
    _PURGE_TMP="0"
  fi

  if [ ! -z "${_DEL_OLD_BACKUPS}" ] && [ "${_DEL_OLD_BACKUPS}" -gt "0" ]; then
    _PURGE_BACKUPS="${_DEL_OLD_BACKUPS}"
  else
    _PURGE_BACKUPS="14"
    if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
      || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
      || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
      || [ -e "/root/.host8.cnf" ]; then
      _PURGE_BACKUPS="7"
    fi
  fi

  _LOW_NR="2"
  _PURGE_CTRL="14"

  find ${User}/log/ctrl/*cert-x1-rebuilt.info \
    -mtime +${_PURGE_CTRL} -type f -exec rm -rf {} \; &> /dev/null

  find ${User}/log/ctrl/plr* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null

  find ${User}/log/ctrl/*rom-fix.info \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null

  find ${User}/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${User}/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${User}/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null

  find /var/aegir/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find /var/aegir/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null

  find ${User}/distro/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/distro/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find ${User}/static/*/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find ${User}/static/*/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find ${User}/distro/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/distro/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find ${User}/static/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null

  find /home/${_HM_U}.ftp/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find /home/${_HM_U}.ftp/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${User}/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${User}/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  chown -R ${_HM_U}:users ${User}/tools/le
  mkdir -p ${User}/static/trash
  chown ${_HM_U}.ftp:users ${User}/static/trash &> /dev/null
  find ${User}/static/trash/* \
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
        rm -rf ${i}
      fi
    fi
  done

  for i in `dir -d ${User}/distro/*`; do
    if [ -d "${i}" ]; then
      if [ ! -d "${i}/keys" ]; then
        mkdir -p ${i}/keys
      fi
      RevisionTest=$(ls ${i} | wc -l 2>&1)
      if [ "${RevisionTest}" -lt "2" ] && [ ! -z "${RevisionTest}" ]; then
        _NOW=$(date +%y%m%d-%H%M%S 2>&1)
        mkdir -p ${User}/undo/dist/${_NOW}
        ### mv -f ${i} ${User}/undo/dist/${_NOW}/ &> /dev/null
        echo "GHOST revision ${i} detected and moved to ${User}/undo/dist/${_NOW}/"
      fi
    fi
  done

  for i in `dir -d ${User}/distro/*`; do
    if [ -e "${i}" ] \
      && [ ! -e "/home/${_HM_U}.ftp/platforms/${i}" ]; then
      if [ -d "/home/${_HM_U}.ftp/platforms" ]; then
        chattr -i /home/${_HM_U}.ftp/platforms
        chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
      fi
      mkdir -p /home/${_HM_U}.ftp/platforms/${i}
      mkdir -p ${i}/keys
      chown ${_HM_U}.ftp:${_WEBG} ${i}/keys &> /dev/null
      chmod 02775 ${i}/keys &> /dev/null
      ln -sfn ${i}/keys /home/${_HM_U}.ftp/platforms/${i}/keys
      for Codebase in `find ${i}/* \
        -maxdepth 1 \
        -mindepth 1 \
        -type d \
        | grep "/sites$" 2>&1`; do
        CodebaseName=$(echo ${Codebase} \
          | cut -d'/' -f7 \
          | awk '{ print $1}' 2> /dev/null)
        ln -sfn ${Codebase} /home/${_HM_U}.ftp/platforms/${i}/${CodebaseName}
        echo "Fixed symlink to ${Codebase} for ${_HM_U}.ftp"
      done
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
  if [ -e "/root/.force.sites.verify.cnf" ]; then
    _CPU_MAX_RATIO=88
  fi
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
}

shared_codebases_cleanup() {
  if [ -L "/data/all" ]; then
    _CLD="/data/disk/codebases-cleanup"
  else
    _CLD="/var/backups/codebases-cleanup"
  fi
  for i in `dir -d /data/all/*/`; do
    if [ -d "${i}o_contrib" ]; then
      for Codebase in `find ${i}* -maxdepth 1 -mindepth 1 -type d \
        | grep "/profiles$" 2>&1`; do
        CodebaseDir=$(echo ${Codebase} \
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

ghost_codebases_cleanup() {
  _CLD="/var/backups/ghost-codebases-cleanup"
  for i in `dir -d /data/disk/*/distro/*/*/`; do
    CodebaseTest=$(find ${i} -maxdepth 1 -mindepth 1 \
      -type d -name vendor | sort 2>&1)
    for vendor in ${CodebaseTest}; do
      ParentDir=`echo ${vendor} | sed "s/\/vendor//g"`
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

prepare_weblogx() {
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

cleanup_weblogx() {
  _ARCHLOGS=/var/www/adminer/access/archive
  if [ -e "${_ARCHLOGS}/unzip" ]; then
    rm -f ${_ARCHLOGS}/unzip/access*
    rm -f ${_ARCHLOGS}/unzip/.global.pid
  fi
}

action() {
  prepare_weblogx
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
        su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
        wait
        rm -rf ${User}/.tmp/cache
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
          if [ -e "${User}/log/email.txt" ]; then
            _F_CLIENT_EMAIL=$(cat ${User}/log/email.txt 2>&1)
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
        disable_chattr ${_HM_U}.ftp
        rm -rf /home/${_HM_U}.ftp/drush-backups
        if [ -e "${_THIS_HM_SITE}" ]; then
          cd ${_THIS_HM_SITE}
          su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
          wait
          rm -rf ${User}/.tmp/cache
          run_drush8_hmr_cmd "${vSet} hosting_cron_default_interval 3600"
          run_drush8_hmr_cmd "${vSet} hosting_queue_cron_frequency 1"
          run_drush8_hmr_cmd "${vSet} hosting_civicrm_cron_queue_frequency 60"
          run_drush8_hmr_cmd "${vSet} hosting_queue_task_gc_frequency 300"
          if [ -e "${User}/log/hosting_cron_use_backend.txt" ]; then
            run_drush8_hmr_cmd "${vSet} hosting_cron_use_backend 1"
          else
            run_drush8_hmr_cmd "${vSet} hosting_cron_use_backend 0"
          fi
          run_drush8_hmr_cmd "${vSet} hosting_ignore_default_profiles 0"
          run_drush8_hmr_cmd "${vSet} hosting_queue_tasks_frequency 1"
          run_drush8_hmr_cmd "${vSet} hosting_queue_tasks_items 1"
          run_drush8_hmr_cmd "${vSet} hosting_delete_force 0"
          run_drush8_hmr_cmd "${vSet} aegir_backup_export_path ${User}/backup-exports"
          run_drush8_hmr_cmd "fr hosting_custom_settings -y"
          run_drush8_hmr_cmd "cache-clear all"
          run_drush8_hmr_cmd "cache-clear all"
          if [ -e "${User}/log/imported.pid" ] \
            || [ -e "${User}/log/exported.pid" ]; then
            if [ ! -e "${User}/log/hosting_context.pid" ]; then
              _HM_NID=$(run_drush8_hmr_cmd "sqlq \
                \"SELECT site.nid FROM hosting_site site JOIN \
                hosting_package_instance pkgi ON pkgi.rid=site.nid JOIN \
                hosting_package pkg ON pkg.nid=pkgi.package_id \
                WHERE pkg.short_name='hostmaster'\" 2>&1")
              _HM_NID=${_HM_NID//[^0-9]/}
              if [ ! -z "${_HM_NID}" ]; then
                run_drush8_hmr_cmd "sqlq \"UPDATE hosting_context \
                  SET name='hostmaster' WHERE nid='${_HM_NID}'\""
                echo ${_HM_NID} > ${User}/log/hosting_context.pid
              fi
            fi
          fi
        fi
        process
        run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
          WHERE task_type='delete' AND task_status='-1'\""
        run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
          WHERE task_type='delete' AND task_status='0' AND executed='0'\""
        run_drush8_hmr_cmd "${vSet} hosting_delete_force 0"
        run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
          SET status=1 WHERE publish_path LIKE '%/aegir/distro/%'\""
        check_old_empty_platforms
        run_drush8_hmr_cmd "${vSet} hosting_delete_force 0"
        run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
          SET status=-2 WHERE publish_path LIKE '%/aegir/distro/%'\""
        _THIS_HM_PLR=$(cat ${User}/.drush/hostmaster.alias.drushrc.php \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
          SET status=1 WHERE publish_path LIKE '${_THIS_HM_PLR}'\""
        purge_cruft_machine
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
          || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
          || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
          || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
          rm -rf ${User}/clients/admin &> /dev/null
          rm -rf ${User}/clients/omega8ccgmailcom &> /dev/null
          rm -rf ${User}/clients/nocomega8cc &> /dev/null
        fi
        rm -rf ${User}/clients/*/backups &> /dev/null
        symlinks -dr ${User}/clients &> /dev/null
        if [ -d "/home/${_HM_U}.ftp" ]; then
          symlinks -dr /home/${_HM_U}.ftp &> /dev/null
          rm -f /home/${_HM_U}.ftp/{.profile,.bash_logout,.bash_profile,.bashrc}
        fi
        le_hm_ssl_check_update ${_HM_U}
        ### if_gen_goaccess "ALL"
        echo "Done for ${User}"
        enable_chattr ${_HM_U}.ftp
      else
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "...we have to wait..."
      fi
      echo
      echo
    fi
  done
  shared_codebases_cleanup
  ghost_codebases_cleanup
  check_old_empty_hostmaster_platforms
  cleanup_weblogx
}

###--------------------###
echo "INFO: Daily maintenance start"
while [ -e "/var/run/boa_wait.pid" ]; do
  echo "Waiting for BOA queue availability..."
  sleep 5
done
#
_NOW=$(date +%y%m%d-%H%M%S 2>&1)
_NOW=${_NOW//[^0-9-]/}
_DOW=$(date +%u 2>&1)
_DOW=${_DOW//[^1-7]/}
_CHECK_HOST=$(uname -n 2>&1)
_VM_TEST=$(uname -a 2>&1)
if [[ "${_VM_TEST}" =~ "-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
if [ -e "/root/.force.sites.verify.cnf" ]; then
  _FORCE_SITES_VERIFY=YES
else
  _FORCE_SITES_VERIFY=NO
fi
#
if [ "${_VMFAMILY}" = "VS" ]; then
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
fi
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
if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
fi
#
find_fast_mirror_early
#
###--------------------###
if [ -z "${_SKYNET_MODE}" ] || [ "${_SKYNET_MODE}" = "ON" ]; then
  echo "INFO: Checking BARRACUDA version"
  rm -f /opt/tmp/barracuda-release.txt*
  curl -L -k -s \
    --max-redirs 10 \
    --retry 3 \
    --retry-delay 15 -A iCab \
    "${urlHmr}/conf/barracuda-release.txt" \
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
      sT="Newer BOA available"
      cat <<EOF | mail -e -s "New ${_X_VERSION} ${sT}" ${_MY_EMAIL}

 There is new ${_X_VERSION} version available.

 Please review the changelog and upgrade as soon as possible
 to receive all security updates and new features.

 Changelog: https://github.com/omega8cc/boa/commits/master

 --
 This email has been sent by your Barracuda server upgrade monitor.

EOF
    echo "INFO: Update notice sent: OK"
    fi
  fi
fi
#
if [ -e "/var/run/daily-fix.pid" ]; then
  touch /var/xdrago/log/wait-for-daily
  exit 1
elif [ -e "/root/.wbhd.clstr.cnf" ]; then
  exit 1
else
  touch /var/run/daily-fix.pid
  if [ "${_VMFAMILY}" = "VS" ]; then
    n=$((RANDOM%180+80))
    echo "waiting $n sec"
    sleep $n
  fi
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
    if [ ! -e "/data/all/permissions-fix-post-up-${_X_SE}.info" ]; then
      rm -f /data/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/all/permissions-fix-post-up-${_X_SE}.info
    fi
  elif [ -e "/data/disk/all" ]; then
    if [ ! -e "/data/disk/all/permissions-fix-post-up-${_X_SE}.info" ]; then
      rm -f /data/disk/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/disk/all/permissions-fix-post-up-${_X_SE}.info
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

  action >/var/xdrago/log/daily/daily-${_NOW}.log 2>&1

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
    sed -i "s/.*ssl_stapling .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf               &> /dev/null
    wait
    sed -i "s/.*ssl_stapling_verify .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf        &> /dev/null
    wait
    sed -i "s/.*resolver .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf                   &> /dev/null
    wait
    sed -i "s/.*resolver_timeout .*//g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf           &> /dev/null
    wait
    sed -i "s/ssl_prefer_server_ciphers .*/ssl_prefer_server_ciphers on;\n  ssl_stapling on;\n  ssl_stapling_verify on;\n  resolver 1.1.1.1 1.0.0.1 valid=300s;\n  resolver_timeout 5s;/g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
    wait
    sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf                      &> /dev/null
    wait
    sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /data/disk/*/config/server_*/nginx/vhost.d/*
    sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx.conf
    sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/vhost.d/*
    sed -i "s/TLSv1.1 TLSv1.2 TLSv1.3;/TLSv1.2 TLSv1.3;/g" /var/aegir/config/server_*/nginx/pre.d/*.conf
    service nginx reload
  fi
fi

if [ "${_PERMISSIONS_FIX}" = "YES" ] \
  && [ ! -z "${_X_VERSION}" ] \
  && [ -e "/opt/tmp/barracuda-release.txt" ] \
  && [ ! -e "/data/all/permissions-fix-${_X_SE}-${_X_VERSION}-fixed-dz.info" ]; then
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
  echo fixed > /data/all/permissions-fix-${_X_SE}-${_X_VERSION}-fixed-dz.info
fi
if [ ! -e "/var/backups/fix-sites-all-permsissions-${_X_SE}.txt" ]; then
  chmod 0751  /data/disk/*/distro/*/*/sites &> /dev/null
  chmod 0755  /data/disk/*/distro/*/*/sites/all &> /dev/null
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  echo FIXED > /var/backups/fix-sites-all-permsissions-${_X_SE}.txt
  echo "Permissions in sites/all tree just fixed"
fi
find /var/backups/old-sql* -mtime +1 -exec rm -rf {} \; &> /dev/null
find /var/backups/ltd/*/* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
find /var/backups/solr/*/* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
find /var/backups/jetty* -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/backups/dragon/* -mtime +7 -exec rm -rf {} \; &> /dev/null
if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
  || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
  || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
  || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
  || [ -e "/root/.host8.cnf" ]; then
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
find /var/run/*_backup.pid -mtime +1 -exec rm -rf {} \; &> /dev/null
rm -f /var/run/daily-fix.pid
echo "INFO: Daily maintenance complete"
exit 0
###EOF2024###
