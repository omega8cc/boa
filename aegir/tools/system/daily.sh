#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
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

_WEBG=www-data
_X_SE="3.1.1-stable"
_OSV=$(lsb_release -sc 2>&1)
_SSL_ITD=$(openssl version 2>&1 \
  | tr -d "\n" \
  | cut -d" " -f2 \
  | awk '{ print $1}')
if [[ "${_SSL_ITD}" =~ "1.0.1" ]] \
  || [[ "${_SSL_ITD}" =~ "1.0.2" ]]; then
  _NEW_SSL=YES
fi
crlGet="-L --max-redirs 10 -k -s --retry 10 --retry-delay 5 -A iCab"
vSet="vset --always-set"

###-------------SYSTEM-----------------###

find_fast_mirror() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    rm -f /etc/apt/sources.list.d/openssl.list
    apt-get update -qq &> /dev/null
    apt-get install netcat -fuy --force-yes --reinstall &> /dev/null
    sleep 3
  fi
  ffMirr=$(which ffmirror 2>&1)
  if [ -x "${ffMirr}" ]; then
    ffList="/var/backups/boa-mirrors.txt"
    mkdir -p /var/backups
    if [ ! -e "${ffList}" ]; then
      echo "jp.files.aegir.cc"  > ${ffList}
      echo "nl.files.aegir.cc" >> ${ffList}
      echo "uk.files.aegir.cc" >> ${ffList}
      echo "us.files.aegir.cc" >> ${ffList}
    fi
    if [ -e "${ffList}" ]; then
      _CHECK_MIRROR=$(bash ${ffMirr} < ${ffList} 2>&1)
      _USE_MIR="${_CHECK_MIRROR}"
      [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.aegir.cc"
    else
      _USE_MIR="files.aegir.cc"
    fi
  else
    _USE_MIR="files.aegir.cc"
  fi
  if ! netcat -w 10 -z "${_USE_MIR}" 80; then
    echo "INFO: The mirror ${_USE_MIR} doesn't respond, let's try default"
    _USE_MIR="files.aegir.cc"
  fi
  urlDev="http://${_USE_MIR}/dev"
  urlHmr="http://${_USE_MIR}/versions/master/aegir"
}

extract_archive() {
  if [ ! -z "$1" ]; then
    case $1 in
      *.tar.bz2)   tar xjf $1    ;;
      *.tar.gz)    tar xzf $1    ;;
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
    curl ${crlGet} "${urlDev}/HEAD/$1" -o "$1"
    extract_archive "$1"
  fi
}

enable_chattr() {
  isTest="$1"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [ -d "/home/$1" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      chattr +i /home/$1             &> /dev/null
    else
      chattr +i /home/$1/platforms   &> /dev/null
      chattr +i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.bazaar" ]; then
      chattr +i /home/$1/.bazaar     &> /dev/null
    fi
    chattr +i /home/$1/.drush        &> /dev/null
    chattr +i /home/$1/.drush/usr    &> /dev/null
    chattr +i /home/$1/.drush/*.ini  &> /dev/null
  fi
}

disable_chattr() {
  if [ ! -z "$1" ] && [ -d "/home/$1" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      chattr -i /home/$1             &> /dev/null
    else
      chattr -i /home/$1/platforms   &> /dev/null
      chattr -i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.bazaar" ]; then
      chattr -i /home/$1/.bazaar     &> /dev/null
    fi
    chattr -i /home/$1/.drush        &> /dev/null
    chattr -i /home/$1/.drush/usr    &> /dev/null
    chattr -i /home/$1/.drush/*.ini  &> /dev/null
    usrSrc="${User}/.drush/usr"
    usrTgt="/home/$1/.drush/usr"
    if [ ! -L "${usrTgt}/drupalgeddon" ] \
      && [ -d "${usrSrc}/drupalgeddon" ]; then
      rm -rf ${usrTgt}/drupalgeddon
      ln -sf ${usrSrc}/drupalgeddon ${usrTgt}/drupalgeddon
    fi
  fi
}

run_drush8_cmd() {
  su -s /bin/bash - ${_HM_U}.ftp -c "drush8 @${Dom} $1" &> /dev/null
}

run_drush8_hmr_cmd() {
  su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster $1" &> /dev/null
}

run_drush8_nosilent_cmd() {
  su -s /bin/bash - ${_HM_U}.ftp -c "drush8 @${Dom} $1"
}

check_if_required() {
  _REQ=YES
  _REI_TEST=$(run_drush8_nosilent_cmd "pmi $1 --fields=required_by" 2>&1)
  _REL_TEST=$(echo "${_REI_TEST}" | grep "Required by" 2>&1)
  if [[ "${_REL_TEST}" =~ "was not found" ]]; then
    _REQ=NULL
    echo "_REQ for $1 is ${_REQ} in ${Dom} == 0 == via ${_REL_TEST}"
  else
    echo "CTRL _REL_TEST _REQ for $1 is ${_REQ} in ${Dom} == 0 == via ${_REL_TEST}"
    _REN_TEST=$(echo "${_REI_TEST}" | grep "Required by.*:.*none" 2>&1)
    if [[ "${_REN_TEST}" =~ "Required by" ]]; then
      _REQ=NO
      echo "_REQ for $1 is ${_REQ} in ${Dom} == 1 == via ${_REN_TEST}"
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
    Profile=$(run_drush8_nosilent_cmd "vget ^install_profile$" \
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
        echo "_REQ for $1 is ${_REQ} in ${Dom} == 7 == via ${_REP_TEST}"
      else
        echo "CTRL _REP_TEST _REQ for $1 is ${_REQ} \
          in ${Dom} == 7 == via ${_REP_TEST}"
      fi
    fi
    _REA_TEST=$(echo "${_REI_TEST}" | grep "Required by.*apps" 2>&1)
    if [[ "${_REA_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${Dom} == 8 == via ${_REA_TEST}"
    fi
    _REF_TEST=$(echo "${_REI_TEST}" | grep "Required by.*features" 2>&1)
    if [[ "${_REF_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${Dom} == 9 == via ${_REF_TEST}"
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
      #echo $1 is blacklisted and will be forcefully disabled in ${Dom}
    fi
  done
}

disable_modules() {
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
          check_if_required "$m"
        else
          echo "$m dependencies not checked in ${Dom}"
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

enable_modules() {
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

fix_user_register_protection() {

  if [ -e "${User}/static/control/enable_user_register_protection.info" ] \
    && [ -e "/data/conf/default.boa_platform_control.ini" ] \
    && [ ! -e "${_PLR_CTRL_F}" ]; then
    cp -af /data/conf/default.boa_platform_control.ini \
      ${_PLR_CTRL_F} &> /dev/null
    chown ${_HM_U}:users ${_PLR_CTRL_F} &> /dev/null
    chmod 0664 ${_PLR_CTRL_F} &> /dev/null
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _EN_URP_T=$(grep "^enable_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_EN_URP_T}" =~ "enable_user_register_protection = TRUE" ]]; then
      _ENABLE_USER_REGISTER_PROTECTION=YES
    else
      _ENABLE_USER_REGISTER_PROTECTION=NO
    fi
    if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
      || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
      || [ "${_VMFAMILY}" = "VS" ]; then
      if [ "${_CLIENT_OPTION}" = "POWER" ]; then
        _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
          ${_PLR_CTRL_F} 2>&1)
        if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]]; then
          _DISABLE_USER_REGISTER_PROTECTION=YES
        else
          _DISABLE_USER_REGISTER_PROTECTION=NO
        fi
      fi
    else
      _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]]; then
        _DISABLE_USER_REGISTER_PROTECTION=YES
      else
        _DISABLE_USER_REGISTER_PROTECTION=NO
      fi
    fi
  else
    _ENABLE_USER_REGISTER_PROTECTION=NO
  fi

  if [ "${_ENABLE_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ -e "${User}/static/control/enable_user_register_protection.info" ]; then
    sed -i "s/.*enable_user_register_protection.*/enable_user_register_protection = TRUE/g" \
      ${_PLR_CTRL_F} &> /dev/null
    wait
    _ENABLE_USER_REGISTER_PROTECTION=YES
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
    if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]]; then
      _DISABLE_USER_REGISTER_PROTECTION=YES
    else
      _DISABLE_USER_REGISTER_PROTECTION=NO
    fi
  else
    _DISABLE_USER_REGISTER_PROTECTION=NO
  fi

  if [ "${_DISABLE_USER_REGISTER_PROTECTION}" = "NO" ]; then
    Prm=$(run_drush8_nosilent_cmd "vget ^user_register$" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    Prm=${Prm//[^0-2]/}
    echo "Prm user_register for ${Dom} is ${Prm}"
    if [ "${_ENABLE_USER_REGISTER_PROTECTION}" = "YES" ]; then
      run_drush8_cmd "${vSet} user_register 0"
    else
      if [ "${Prm}" = "1" ] || [ -z "${Prm}" ]; then
        run_drush8_cmd "${vSet} user_register 2"
      fi
      run_drush8_cmd "${vSet} user_email_verification 1"
    fi
  fi

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

fix_robots_txt() {
  find ${Dir}/files/robots.txt -mtime +6 -exec rm -f {} \; &> /dev/null
  if [ ! -e "${Dir}/files/robots.txt" ] \
    && [ ! -e "${Plr}/profiles/hostmaster" ] \
    && [ "${_STATUS}" = "OK" ]; then
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
  if [ "${_O_CONTRIB}" != "NO" ] && [ ! -e "${Plr}/core" ]; then
    symlinks -d ${Plr}/modules &> /dev/null
    if [ -e "${Plr}/web.config" ]; then
      if [ ! -e "${Plr}/modules/o_contrib_seven" ]; then
        ln -sf ${_O_CONTRIB_SEVEN} ${Plr}/modules/o_contrib_seven &> /dev/null
      fi
    else
      if [ -e "${Plr}/modules/watchdog" ]; then
        if [ -e "${Plr}/modules/o_contrib" ]; then
          rm -f ${Plr}/modules/o_contrib &> /dev/null
        fi
      else
        if [ ! -e "${Plr}/modules/o_contrib" ]; then
          ln -sf ${_O_CONTRIB} ${Plr}/modules/o_contrib &> /dev/null
        fi
      fi
    fi
  fi
}

sql_convert() {
  sudo -u ${_HM_U}.ftp -H /opt/local/bin/sqlmagic convert to-${_SQL_CONVERT}
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
    || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
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
    || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
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
by BOA-3.1.1. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

Note: while we don't provide Drupal sites upgrade service, we can
recommend myDropWizard, if you need to outsource this task:

  https://www.mydropwizard.com

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
by BOA-3.1.1. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

Note: while we don't provide Drupal sites upgrade service, we can
recommend myDropWizard, if you need to outsource this task:

  https://www.mydropwizard.com

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
by BOA-3.1.1. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

Note: while we don't provide Drupal sites upgrade service, we can
recommend myDropWizard, if you need to outsource this task:

  https://www.mydropwizard.com

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
    || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
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
by BOA-3.1.1. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

Note: while we don't provide Drupal sites upgrade service, we can
recommend myDropWizard, if you need to outsource this task:

  https://www.mydropwizard.com

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
by BOA-3.1.1. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

Note: while we don't provide Drupal sites upgrade service, we can
recommend myDropWizard, if you need to outsource this task:

  https://www.mydropwizard.com

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
by BOA-3.1.1. As a bonus, you will be able to speed up your sites
considerably by switching PHP-FPM to 7.0

We recommend to follow this upgrade how-to:

  https://omega8.cc/your-drupal-site-upgrade-safe-workflow-298

The how-to for PHP-FPM version switch can be found at:

  https://omega8.cc/how-to-quickly-switch-php-to-newer-version-330

Note: while we don't provide Drupal sites upgrade service, we can
recommend myDropWizard, if you need to outsource this task:

  https://www.mydropwizard.com

--
This email has been sent by your Aegir automatic system monitor.

EOF
  fi
  echo "ALERT: Core notice sent to ${_CLIENT_EMAIL} [${_HM_U}]: OK"
}

check_site_status() {
  _SITE_TEST=$(run_drush8_nosilent_cmd "status" 2>&1)
  if [[ "${_SITE_TEST}" =~ "Error:" ]] \
    || [[ "${_SITE_TEST}" =~ "Drush was attempting to connect" ]]; then
    _SITE_TEST_RESULT=ERROR
  else
    _SITE_TEST_RESULT=OK
  fi
  if [ "${_SITE_TEST_RESULT}" = "OK" ]; then
    _STATUS_TEST=$(run_drush8_nosilent_cmd "status \
      | grep 'Drupal bootstrap.*:.*Successful'" 2>&1)
    if [[ "${_STATUS_TEST}" =~ "Successful" ]]; then
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
                  mv -f ${User}/config/server_master/nginx/vhost.d/${Dom} \
                    ${User}/config/server_master/nginx/vhost.d/.${Dom}
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
    _STATUS=BROKEN
    echo "WARNING: THIS SITE IS PROBABLY BROKEN! ${Dir}"
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

write_solr_config() {
  # $1 is module
  # $2 is a path to solr.php
  if [ ! -z "$1" ] \
    && [ ! -z $2 ] \
    && [ ! -z "${_MD5H}" ] \
    && [ -e "${Dir}" ]; then
    echo "Your SOLR core access details for ${Dom} site are as follows:"  > $2
    echo                                                                 >> $2
    echo "  Solr host ........: 127.0.0.1"                               >> $2
    echo "  Solr port ........: 8099"                                    >> $2
    echo "  Solr path ........: /solr/${_MD5H}.${Dom}.${_HM_U}"  >> $2
    echo                                                                 >> $2
    echo "It has been auto-configured to work with latest version"       >> $2
    echo "of $1 module, but you need to add the module to"               >> $2
    echo "your site codebase before you will be able to use Solr."       >> $2
    echo                                                                 >> $2
    echo "To learn more please make sure to check the module docs at:"   >> $2
    echo                                                                 >> $2
    echo "https://drupal.org/project/$1"                                 >> $2
    chown ${_HM_U}:users $2 &> /dev/null
    chmod 440 $2 &> /dev/null
  fi
}

update_solr() {
  # $1 is module
  # $2 is solr core path
  if [ ! -z "$1" ] \
    && [ ! -e "$2/conf/.protected.conf" ] \
    && [ ! -e "$2/conf/${_X_SE}.conf" ] \
    && [ -e "/var/xdrago/conf/solr" ] \
    && [ -e "$2/conf" ]; then
    if [ "$1" = "apachesolr" ]; then
      if [ -e "${Plr}/modules/o_contrib_seven" ]; then
        cp -af /var/xdrago/conf/solr/apachesolr/7/schema.xml $2/conf/
        cp -af /var/xdrago/conf/solr/apachesolr/7/solrconfig.xml $2/conf/
        cp -af /var/xdrago/conf/solr/apachesolr/7/solrcore.properties $2/conf/
        touch $2/conf/update-ok.txt
      else
        cp -af /var/xdrago/conf/solr/apachesolr/6/schema.xml $2/conf/
        cp -af /var/xdrago/conf/solr/apachesolr/6/solrconfig.xml $2/conf/
        cp -af /var/xdrago/conf/solr/apachesolr/6/solrcore.properties $2/conf/
        touch $2/conf/update-ok.txt
      fi
    elif [ "$1" = "search_api_solr" ] \
      && [ -e "${Plr}/modules/o_contrib_seven" ]; then
      cp -af /var/xdrago/conf/solr/search_api_solr/7/schema.xml $2/conf/
      cp -af /var/xdrago/conf/solr/search_api_solr/7/solrconfig.xml $2/conf/
      cp -af /var/xdrago/conf/solr/search_api_solr/7/solrcore.properties $2/conf/
      touch $2/conf/update-ok.txt
    fi
    if [ -e "$2/conf/update-ok.txt" ]; then
      write_solr_config $1 ${Dir}/solr.php
      echo "Updated Solr with $1 for $2"
      touch $2/conf/${_X_SE}.conf
      if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
        kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
        service jetty9 start &> /dev/null
      fi
    fi
  fi
}

add_solr() {
  # $1 is module
  # $2 is solr core path
  if [ ! -z "$1" ] && [ ! -z $2 ] && [ -e "/var/xdrago/conf/solr" ]; then
    if [ ! -e "$2" ]; then
      rm -rf /opt/solr4/core0/data/*
      cp -a /opt/solr4/core0 $2
      CHAR="[:alnum:]"
      rkey=32
      if [ "${_NEW_SSL}" = "YES" ] \
        || [ "${_OSV}" = "jessie" ] \
        || [ "${_OSV}" = "wheezy" ] \
        || [ "${_OSV}" = "trusty" ] \
        || [ "${_OSV}" = "precise" ]; then
        _MD5H=$(cat /dev/urandom \
          | tr -cd "$CHAR" \
          | head -c ${1:-$rkey} \
          | openssl md5 \
          | awk '{ print $2}' \
          | tr -d "\n" 2>&1)
      else
        _MD5H=$(cat /dev/urandom \
          | tr -cd "$CHAR" \
          | head -c ${1:-$rkey} \
          | openssl md5 \
          | tr -d "\n" 2>&1)
      fi
      sed -i "s/.*<core name=\"core0\" instanceDir=\"core0\" \/>.*/<core name=\"core0\" instanceDir=\"core0\" \/>\n<core name=\"${_MD5H}.${Dom}.${_HM_U}\" instanceDir=\"${_HM_U}.${Dom}\" \/>\n/g" /opt/solr4/solr.xml
      wait
      update_solr $1 $2
      echo "New Solr with $1 for $2 added"
    fi
  fi
}

delete_solr() {
  # $1 is solr core path
  if [ ! -z "$1" ] \
    && [[ "$1" =~ "/opt/solr4/" ]] \
    && [ -e "/var/xdrago/conf/solr" ] \
    && [ -e "$1/conf" ]; then
    sed -i "s/.*instanceDir=\"${_HM_U}.${Dom}\".*//g" /opt/solr4/solr.xml
    wait
    sed -i "/^$/d" /opt/solr4/solr.xml &> /dev/null
    wait
    rm -rf $1
    rm -f ${Dir}/solr.php
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      service jetty9 start &> /dev/null
    fi
    echo "Deleted Solr for $1"
  fi
}

check_solr() {
  # $1 is module
  # $2 is solr core path
  if [ ! -z "$1" ] && [ ! -z $2 ] && [ -e "/var/xdrago/conf/solr" ]; then
    echo "Checking Solr with $1 for $2"
    if [ ! -e "$2" ]; then
      add_solr $1 $2
    else
      update_solr $1 $2
    fi
  fi
}

setup_solr() {

  _SOLR_DIR="/opt/solr4/${_HM_U}.${Dom}"
  if [ -e "/data/conf/default.boa_site_control.ini" ] \
    && [ ! -e "${_DIR_CTRL_F}" ]; then
    cp -af /data/conf/default.boa_site_control.ini ${_DIR_CTRL_F} &> /dev/null
    chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
    chmod 0664 ${_DIR_CTRL_F} &> /dev/null
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
  ### Support for solr_integration_module directive
  ###
  if [ -e "${_DIR_CTRL_F}" ]; then
    _SOLR_MODULE=""
    _SOLR_IM_PT=$(grep "solr_integration_module" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SOLR_IM_PT}" =~ "solr_integration_module" ]]; then
      _DO_NOTHING=YES
    else
      echo ";solr_integration_module = your_module_name_here" >> ${_DIR_CTRL_F}
    fi
    _ASOLR_T=$(grep "^solr_integration_module = apachesolr" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_ASOLR_T}" =~ "apachesolr" ]]; then
      _SOLR_MODULE=apachesolr
    fi
    _SAPI_SOLR_T=$(grep "^solr_integration_module = search_api_solr" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SAPI_SOLR_T}" =~ "search_api_solr" ]]; then
      _SOLR_MODULE=search_api_solr
    fi
    if [ ! -z "${_SOLR_MODULE}" ]; then
      check_solr ${_SOLR_MODULE} ${_SOLR_DIR}
    else
      delete_solr ${_SOLR_DIR}
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
      if [ ! -e "${_SOLR_DIR}/conf/${_X_SE}.conf" ]; then
        if [ "${_SLR_CM_CFG_RT}" = "NO" ] \
          && [ ! -e "${_SOLR_PROTECT_CTRL}" ]; then
          update_solr ${_SOLR_MODULE} ${_SOLR_DIR}
        fi
      fi
    fi
  fi
}

fix_modules() {
  _AUTO_CONFIG_ADVAGG=NO
  if [ -e "${Plr}/sites/all/modules/advagg" ] \
    || [ -e "${Plr}/modules/o_contrib/advagg" ] \
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

  _AUTO_CONFIG_PURGE_EXPIRE=NO
  if [ -e "${Plr}/modules/o_contrib/purge" ] \
    || [ -e "${Plr}/modules/o_contrib_seven/purge" ]; then
    _MODULE_T=$(run_drush8_nosilent_cmd "pml --status=enabled \
      --type=module | grep \(purge\)" 2>&1)
    if [[ "${_MODULE_T}" =~ "(purge)" ]]; then
      _AUTO_CONFIG_PURGE_EXPIRE=YES
    fi
  fi
  if [ "${_AUTO_CONFIG_PURGE_EXPIRE}" = "YES" ]; then
    if [ -e "/data/conf/default.boa_site_control.ini" ] \
      && [ ! -e "${_DIR_CTRL_F}" ]; then
      cp -af /data/conf/default.boa_site_control.ini \
        ${_DIR_CTRL_F} &> /dev/null
      chown ${_HM_U}:users ${_DIR_CTRL_F} &> /dev/null
      chmod 0664 ${_DIR_CTRL_F} &> /dev/null
    fi
    if [ -e "${_DIR_CTRL_F}" ]; then
      _AC_PE_P=$(grep "purge_expire_auto_configuration" \
        ${_DIR_CTRL_F} 2>&1)
      _AC_PE_T=$(grep "^purge_expire_auto_configuration = TRUE" \
        ${_DIR_CTRL_F} 2>&1)
      if [[ "${_AC_PE_T}" =~ "purge_expire_auto_configuration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the site level ini file.
        ###
        if [[ "${_AC_PE_P}" =~ "purge_expire_auto_configuration" ]]; then
          sed -i "s/.*purge_expire_a.*/purge_expire_auto_configuration = TRUE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        else
          echo "purge_expire_auto_configuration = TRUE" >> ${_DIR_CTRL_F}
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
      _AC_PE_P=$(grep "purge_expire_auto_configuration" \
        ${_DIR_CTRL_F} 2>&1)
      _AC_PE_T=$(grep "^purge_expire_auto_configuration = FALSE" \
        ${_DIR_CTRL_F} 2>&1)
      if [[ "${_AC_PE_T}" =~ "purge_expire_auto_configuration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        if [[ "${_AC_PE_P}" =~ "purge_expire_auto_configuration" ]]; then
          sed -i "s/.*purge_expire_a.*/purge_expire_auto_configuration = FALSE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        else
          echo ";purge_expire_auto_configuration = FALSE" >> \
      ${_DIR_CTRL_F}
        fi
      fi
    fi
  fi

  if [ -e "${Plr}/modules/o_contrib_seven" ]; then
    _PRIV_TEST=$(run_drush8_nosilent_cmd "vget ^file_default_scheme$" 2>&1)
    if [[ "${_PRIV_TEST}" =~ "No matching variable" ]]; then
      _PRIV_TEST_RESULT=NONE
    else
      _PRIV_TEST_RESULT=OK
    fi
    _AUTO_CNF_PF_DL=NO
    if [ "${_PRIV_TEST_RESULT}" = "OK" ]; then
      Pri=$(run_drush8_nosilent_cmd "vget ^file_default_scheme$" \
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
    _VAR_IF_PRESENT=$(grep "redis_use_modern" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_use_modern" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_use_modern = TRUE" >> ${_PLR_CTRL_F}
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
    _VAR_IF_PRESENT=$(grep "redis_use_modern" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_use_modern" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_use_modern = TRUE" >> ${_DIR_CTRL_F}
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
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _EC_DE_T=$(grep "^entitycache_dont_enable = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_EC_DE_T}" =~ "entitycache_dont_enable = TRUE" ]]; then
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
      if [ ! -z "${_MODULES_OFF_SIX}" ]; then
        disable_modules "${_MODULES_OFF_SIX}"
      fi
      if [ ! -z "${_MODULES_ON_SIX}" ]; then
        enable_modules "${_MODULES_ON_SIX}"
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
      if [ ! -z "${_MODULES_OFF_SEVEN}" ]; then
        disable_modules "${_MODULES_OFF_SEVEN}"
      fi
      if [ "${_ENTITYCACHE_DONT_ENABLE}" = "NO" ]; then
        enable_modules "entitycache"
      fi
      if [ ! -z "${_MODULES_ON_SEVEN}" ]; then
        enable_modules "${_MODULES_ON_SEVEN}"
      fi
    fi
  fi
  if [ -e "${Dir}/modules/commerce_ubercart_check.info" ]; then
    touch ${User}/log/ctrl/site.${Dom}.cart-check.info
    rm -f ${Dir}/modules/commerce_ubercart_check.info
  fi
  if [ ! -e "${User}/log/ctrl/site.${Dom}.cart-check.info" ]; then
    _COMMERCE_TEST=$(run_drush8_nosilent_cmd "pml --status=enabled \
      --no-core --type=module | grep \(commerce\)" 2>&1)
    _UBERCART_TEST=$(run_drush8_nosilent_cmd "pml --status=enabled \
      --no-core --type=module | grep \(uc_cart\)" 2>&1)
    if [[ "${_COMMERCE_TEST}" =~ "Commerce" ]] \
      || [[ "${_UBERCART_TEST}" =~ "Ubercart" ]]; then
      disable_modules "views_cache_bully"
    fi
    touch ${User}/log/ctrl/site.${Dom}.cart-check.info
  fi
  if [ -e "${User}/static/control/enable_views_cache_bully.info" ] \
    || [ -e "${User}/static/control/enable_views_content_cache.info" ]; then
    _VIEWS_TEST=$(run_drush8_nosilent_cmd "pml --status=enabled \
      --no-core --type=module | grep \(views\)" 2>&1)
    if [ -e "${User}/static/control/enable_views_content_cache.info" ]; then
      _CTOOLS_TEST=$(run_drush8_nosilent_cmd "pml --status=enabled \
        --no-core --type=module | grep \(ctools\)" 2>&1)
    fi
    if [[ "${_VIEWS_TEST}" =~ "Views" ]] \
      && [ ! -e "${Plr}/profiles/hostmaster" ]; then
      if [ "${_VIEWS_CACHE_BULLY_DONT_ENABLE}" = "NO" ] \
        && [ -e "${User}/static/control/enable_views_cache_bully.info" ]; then
        if [ -e "${Plr}/modules/o_contrib_seven/views_cache_bully" ] \
          || [ -e "${Plr}/modules/o_contrib/views_cache_bully" ]; then
          enable_modules "views_cache_bully"
        fi
      fi
      if [[ "${_CTOOLS_TEST}" =~ "Chaos" ]] \
        && [ "${_VIEWS_CONTENT_CACHE_DONT_ENABLE}" = "NO" ] \
        && [ -e "${User}/static/control/enable_views_content_cache.info" ]; then
        if [ -e "${Plr}/modules/o_contrib_seven/views_content_cache" ] \
          || [ -e "${Plr}/modules/o_contrib/views_content_cache" ]; then
          enable_modules "views_content_cache"
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
  if [ ! -z "${_SQL_CONVERT}" ] && [ "${_DOW}" = "6" ]; then
    if [ "${_SQL_CONVERT}" = "YES" ]; then
      _SQL_CONVERT=innodb
    fi
    if [ "${_SQL_CONVERT}" = "myisam" ] \
      || [ "${_SQL_CONVERT}" = "innodb" ]; then
      _TIMP=$(date +%y%m%d-%H%M 2>&1)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${Dom} started"
      sql_convert
      _TIMP=$(date +%y%m%d-%H%M 2>&1)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${Dom} completed"
    fi
  fi
}

cleanup_ghost_platforms() {
  if [ -e "${Plr}" ]; then
    if [ ! -e "${Plr}/index.php" ] || [ ! -e "${Plr}/profiles" ]; then
      mkdir -p ${User}/undo
      mv -f ${Plr} ${User}/undo/ &> /dev/null
      echo "GHOST platform ${Plr} detected and moved to ${User}/undo/"
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
    if [ -e "${Plr}/web.config" ] && [ ! -d "${Plr}/core" ]; then
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
      find ${Plr}/profiles -type f -name "*.info" -print0 | xargs -0 sed -i \
        's/.*dependencies\[\] = update/;dependencies\[\] = update/g' &> /dev/null
      wait
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
    find ${Plr}/sites/all/modules -type f -name "*.info" -print0 \
      | xargs -0 sed -i \
      's/.*dependencies\[\] = update/;dependencies\[\] = update/g' &> /dev/null
    wait
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
    chmod 0644 ${Plr}/sites/*.txt &> /dev/null
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
    && [ -e "${Dir}/private" ] \
    && [ -e "${Dir}/modules" ]; then
    ### directory and settings files - site level
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
    find ${Dir}/files/* -type d -exec chmod 02775 {} \; &> /dev/null
    find ${Dir}/files/* -type f -exec chmod 0664 {} \; &> /dev/null
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
    find ${Dir}/private -type d -exec chmod 02775 {} \; &> /dev/null
    find ${Dir}/private -type f -exec chmod 0664 {} \; &> /dev/null
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
      mv -f ${User}/.drush/${Dom}.alias.drushrc.php ${User}/undo/ &> /dev/null
      mv -f ${User}/config/server_master/nginx/vhost.d/${Dom} \
        ${User}/undo/ &> /dev/null
      echo "GHOST vhost for ${Dom} detected and moved to ${User}/undo/"
    fi
    if [ -e "${User}/config/server_master/nginx/vhost.d/${Dom}" ]; then
      Plx=$(cat ${User}/config/server_master/nginx/vhost.d/${Dom} \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "$Plx" =~ "aegir/distro" ]] || [[ "${Dom}" =~ "--CDN"($) ]]; then
        _SKIP_VHOST=YES
      else
        if [ ! -e "${User}/.drush/${Dom}.alias.drushrc.php" ]; then
          mkdir -p ${User}/undo
          mv -f $Site ${User}/undo/ &> /dev/null
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
      if [ -d "$Plm" ]; then
        if [ ! -e "$Plm/index.php" ] || [ ! -e "$Plm/profiles" ]; then
          mkdir -p ${User}/undo
          mv -f $Plm ${User}/undo/ &> /dev/null
          echo "GHOST broken platform dir $Plm detected and moved to ${User}/undo/"
          mv -f ${Alias} ${User}/undo/ &> /dev/null
          echo "GHOST broken platform alias ${Alias} detected and moved to ${User}/undo/"
        fi
      else
        mkdir -p ${User}/undo
        mv -f ${Alias} ${User}/undo/ &> /dev/null
        echo "GHOST nodir platform alias ${Alias} detected and moved to ${User}/undo/"
      fi
    else
      _T_SITE_NAME="${AliasName}"
      if [[ "${_T_SITE_NAME}" =~ ".restore"($) ]]; then
        _IS_SITE=NO
        mkdir -p ${User}/undo
        mv -f ${User}/.drush/${_T_SITE_NAME}.alias.drushrc.php \
          ${User}/undo/ &> /dev/null
        mv -f ${User}/config/server_master/nginx/vhost.d/${_T_SITE_NAME} \
          ${User}/undo/ &> /dev/null
        echo "GHOST drushrc and vhost for ${_T_SITE_NAME} detected and moved to ${User}/undo/"
      else
        _T_SITE_FDIR=$(cat ${Alias} \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        if [ -e "${_T_SITE_FDIR}/drushrc.php" ] \
          && [ -e "${_T_SITE_FDIR}/files" ] \
          && [ -e "${_T_SITE_FDIR}/private" ] \
          && [ -e "${_T_SITE_FDIR}/modules" ]; then
          _IS_SITE=YES
        else
          mkdir -p ${User}/undo
          mv -f ${User}/.drush/${_T_SITE_NAME}.alias.drushrc.php \
            ${User}/undo/ &> /dev/null
          echo "GHOST drushrc for ${_T_SITE_NAME} detected and moved to ${User}/undo/"
          if [[ ! "${_T_SITE_FDIR}" =~ "aegir/distro" ]]; then
            mv -f ${User}/config/server_master/nginx/vhost.d/${_T_SITE_NAME} \
              ${User}/undo/ghost-vhost-${_T_SITE_NAME} &> /dev/null
            echo "GHOST vhost for ${_T_SITE_NAME} detected and moved to ${User}/undo/"
          fi
          if [ -d "${_T_SITE_FDIR}" ]; then
            mv -f ${_T_SITE_FDIR} \
              ${User}/undo/ghost-site-${_T_SITE_NAME} &> /dev/null
            echo "GHOST site dir for ${_T_SITE_NAME} detected and moved from ${_T_SITE_FDIR} to ${User}/undo/"
          fi
        fi
      fi
    fi
  done
}

check_update_le_hm_ssl() {
  exeLe="${User}/tools/le/letsencrypt.sh"
  if [ -e "${User}/log/domain.txt" ]; then
    hmFront=$(cat ${User}/log/domain.txt 2>&1)
    hmFront=$(echo -n ${hmFront} | tr -d "\n" 2>&1)
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
    && [ -e "${User}/tools/le/certs/${Dom}/fullchain.pem" ]; then
    echo "Running LE cert check directly for hostmaster ${_HM_U}"
    su -s /bin/bash - ${_HM_U} -c "${exeLe} -c -d ${hmFront}"
    sleep 5
  fi
}

check_update_le_ssl() {
  if [[ "${Dom}" =~ ^(a|b|c|d|e) ]]; then
    runDay="1"
  elif [[ "${Dom}" =~ ^(f|g|h|i) ]]; then
    runDay="2"
  elif [[ "${Dom}" =~ ^(j|k|l|m) ]]; then
    runDay="3"
  elif [[ "${Dom}" =~ ^(n|o|p|q) ]]; then
    runDay="4"
  elif [[ "${Dom}" =~ ^(r|s|t|u) ]]; then
    runDay="5"
  elif [[ "${Dom}" =~ ^(v|w|x|y) ]]; then
    runDay="6"
  else
    runDay="7"
  fi
  if [ "${_DOW}" = "${runDay}" ]; then
    if [ -e "${User}/tools/le/certs/${Dom}/fullchain.pem" ]; then
      echo "Running LE cert check via Verify task for ${Dom}"
      run_drush8_hmr_cmd "hosting-task @${Dom} verify --force"
      sleep 5
    fi
  fi
}

process() {
  cleanup_ghost_vhosts
  cleanup_ghost_drushrc
  for Site in `find ${User}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _MOMENT=$(date +%y%m%d-%H%M 2>&1)
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
        if [ "${_NEW_SSL}" = "YES" ] \
          || [ "${_OSV}" = "jessie" ] \
          || [ "${_OSV}" = "wheezy" ] \
          || [ "${_OSV}" = "trusty" ] \
          || [ "${_OSV}" = "precise" ]; then
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
              run_drush8_hmr_cmd "dis update syslog dblog -y"
              touch ${User}/log/ctrl/plr.${PlrID}.hm-fix-${_NOW}.info
            fi
          else
            check_site_status
          fi
          if [ "${_STATUS}" = "OK" ] \
            && [ ! -z "${Dan}" ] \
            && [ "${Dan}" != "hostmaster" ]; then
            setup_solr
            searchStringB=".dev."
            searchStringC=".devel."
            searchStringD=".temp."
            searchStringE=".tmp."
            searchStringF=".temporary."
            searchStringG=".test."
            searchStringH=".testing."
            searchStringI=".stage."
            searchStringJ=".staging."
            case ${Dom} in
              *"$searchStringB"*) ;;
              *"$searchStringC"*) ;;
              *"$searchStringD"*) ;;
              *"$searchStringE"*) ;;
              *"$searchStringF"*) ;;
              *"$searchStringG"*) ;;
              *"$searchStringH"*) ;;
              *"$searchStringI"*) ;;
              *"$searchStringJ"*) ;;
              *)
              if [ "${_MODULES_FIX}" = "YES" ]; then
                fix_modules
                fix_robots_txt
              fi
              check_update_le_ssl
              ;;
            esac
            fix_boost_cache
            fix_site_control_files
            fix_user_register_protection
          fi
        fi
        if [ -e "${Plr}/profiles" ] \
          && [ -e "${Plr}/web.config" ] \
          && [ ! -d "${Plr}/core" ] \
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
     _MOMENT=$(date +%y%m%d-%H%M 2>&1)
     echo ${_MOMENT} End Counting Site $Site
    fi
  done
}

delete_this_platform() {
  run_drush8_hmr_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

check_old_empty_platforms() {
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
    || [ -e "/root/.host8.cnf" ]; then
    if [[ "${_CHECK_HOST}" =~ "demo.aegir.cc" ]] \
      || [ -e "/root/.debug.cnf" ]; then
      _DO_NOTHING=YES
    else
      if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt "0" ] \
        && [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
        _DO_NOTHING=YES
      else
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
          || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
          || [ "${_VMFAMILY}" = "VS" ]; then
          _DEL_OLD_EMPTY_PLATFORMS="7"
        else
          _DEL_OLD_EMPTY_PLATFORMS="60"
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
          mkdir -p ${User}/undo
          mv -f ${User}/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php \
            ${User}/undo/ &> /dev/null
          echo "GHOST platform ${_T_PFM_ROOT} detected and moved to ${User}/undo/"
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
  if [ ! -z "${_DEL_OLD_BACKUPS}" ] && [ "${_DEL_OLD_BACKUPS}" -gt "0" ]; then
    _PURGE_BACKUPS="${_DEL_OLD_BACKUPS}"
  else
    _PURGE_BACKUPS="30"
  fi

  if [ ! -z "${_DEL_OLD_TMP}" ] && [ "${_DEL_OLD_TMP}" -gt "0" ]; then
    _PURGE_TMP="${_DEL_OLD_TMP}"
  else
    _PURGE_TMP="0"
  fi

  _LOW_NR="2"
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
    || [ -e "/root/.host8.cnf" ]; then
    _PURGE_BACKUPS="8"
    _PURGE_TMP="0"
    _LOW_NR="8"
  fi

  find ${User}/backups/* -mtime +${_PURGE_BACKUPS} -type f -exec \
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

  mkdir -p ${User}/static/trash
  chown ${_HM_U}.ftp:users ${User}/static/trash &> /dev/null
  find ${User}/static/trash/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  find ${User}/log/ctrl/* \
    -mtime +0 -type f -exec rm -rf {} \; &> /dev/null

  _REVISIONS="001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 \
    016 017 018 019 020 021 022 023 024 025 026 027 028 029 030 031 032 033 \
    034 035 036 037 038 039 040 041 042 043 044 045 046 047 048 049 050"

  for i in ${_REVISIONS}; do
    if [ -e "/home/${_HM_U}.ftp/platforms/$i" ]; then
      RevisionTest=$(ls /home/${_HM_U}.ftp/platforms/$i \
        | wc -l \
        | tr -d "\n" 2>&1)
      if [ "${RevisionTest}" -lt "${_LOW_NR}" ] \
        && [ ! -z "${RevisionTest}" ]; then
        chattr -i /home/${_HM_U}.ftp/platforms   &> /dev/null
        chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
        rm -rf /home/${_HM_U}.ftp/platforms/$i
      fi
    fi
  done

  for i in ${_REVISIONS}; do
    if [ -d "${User}/distro/$i" ]; then
      if [ ! -d "${User}/distro/$i/keys" ]; then
        mkdir -p ${User}/distro/$i/keys
      fi
      RevisionTest=$(ls ${User}/distro/$i | wc -l | tr -d "\n" 2>&1)
      if [ "${RevisionTest}" -lt "2" ] && [ ! -z "${RevisionTest}" ]; then
        mkdir -p ${User}/undo
        mv -f ${User}/distro/$i ${User}/undo/ &> /dev/null
        echo "GHOST revision ${User}/distro/$i detected and moved to ${User}/undo/"
      fi
    fi
  done

  for i in ${_REVISIONS}; do
    if [ -e "${User}/distro/$i" ] \
      && [ ! -e "/home/${_HM_U}.ftp/platforms/$i" ]; then
      chattr -i /home/${_HM_U}.ftp/platforms   &> /dev/null
      chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
      mkdir -p /home/${_HM_U}.ftp/platforms/$i
      mkdir -p ${User}/distro/$i/keys
      chown ${_HM_U}.ftp:${_WEBG} ${User}/distro/$i/keys &> /dev/null
      chmod 02775 ${User}/distro/$i/keys &> /dev/null
      ln -sf ${User}/distro/$i/keys /home/${_HM_U}.ftp/platforms/$i/keys
      for Codebase in `find ${User}/distro/$i/* \
        -maxdepth 1 \
        -mindepth 1 \
        -type d \
        | grep "/sites$" 2>&1`; do
        CodebaseName=$(echo ${Codebase} \
          | cut -d'/' -f7 \
          | awk '{ print $1}' 2> /dev/null)
        ln -sf ${Codebase} /home/${_HM_U}.ftp/platforms/$i/${CodebaseName}
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
  _REVISIONS="001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 \
    016 017 018 019 020 021 022 023 024 025 026 027 028 029 030 031 032 033 \
    034 035 036 037 038 039 040 041 042 043 044 045 046 047 048 049 050"
  for i in ${_REVISIONS}; do
    if [ -d "/data/all/$i/o_contrib" ]; then
      for Codebase in `find /data/all/$i/* -maxdepth 1 -mindepth 1 -type d \
        | grep "/profiles$" 2>&1`; do
        CodebaseDir=$(echo ${Codebase} \
          | sed 's/\/profiles//g' \
          | awk '{print $1}' 2> /dev/null)
        CodebaseTest=$(find /data/disk/*/distro/*/*/ -maxdepth 1 -mindepth 1 \
          -type l -lname ${Codebase} | sort 2>&1)
        if [[ "${CodebaseTest}" =~ "No such file or directory" ]] \
          || [ -z "${CodebaseTest}" ]; then
          mkdir -p ${_CLD}/$i
          echo "Moving no longer used ${CodebaseDir} to ${_CLD}/$i/"
          mv -f ${CodebaseDir} ${_CLD}/$i/
          sleep 1
        fi
      done
    fi
  done
}

action() {
  for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    count_cpu
    load_control
    if [ -e "${User}/config/server_master/nginx/vhost.d" ] \
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
        rm -rf ${User}/.tmp/cache
        su -s /bin/bash - ${_HM_U}.ftp -c "drush8 cc drush" &> /dev/null
        rm -rf /home/${_HM_U}.ftp/.tmp/cache
        _SQL_CONVERT=NO
        _DEL_OLD_EMPTY_PLATFORMS="0"
        if [ -e "/root/.${_HM_U}.octopus.cnf" ]; then
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
          rm -rf ${User}/.tmp/cache
          run_drush8_hmr_cmd "${vSet} hosting_cron_default_interval 86400"
          run_drush8_hmr_cmd "${vSet} hosting_queue_cron_frequency 1"
          if [ -e "${User}/log/hosting_cron_use_backend.txt" ]; then
            run_drush8_hmr_cmd "${vSet} hosting_cron_use_backend 1"
          else
             run_drush8_hmr_cmd "${vSet} hosting_cron_use_backend 0"
          fi
          run_drush8_hmr_cmd "${vSet} hosting_ignore_default_profiles 0"
          run_drush8_hmr_cmd "${vSet} hosting_queue_tasks_items 1"
          run_drush8_hmr_cmd "${vSet} aegir_backup_export_path ${User}/backup-exports"
          if [ ! -e "/data/conf/.debug-hosting-custom-settings.cnf" ]; then
            run_drush8_hmr_cmd "fr hosting_custom_settings -y"
          fi
          run_drush8_hmr_cmd "cc all"
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
        check_old_empty_platforms
        purge_cruft_machine
        if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
          || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
          || [ "${_VMFAMILY}" = "VS" ]; then
          rm -rf ${User}/clients/admin &> /dev/null
          rm -rf ${User}/clients/omega8ccgmailcom &> /dev/null
          rm -rf ${User}/clients/nocomega8cc &> /dev/null
        fi
        rm -rf ${User}/clients/*/backups &> /dev/null
        symlinks -dr ${User}/clients &> /dev/null
        if [ -e "/home/${_HM_U}.ftp" ]; then
          symlinks -dr /home/${_HM_U}.ftp &> /dev/null
          rm -f /home/${_HM_U}.ftp/{.profile,.bash_logout,.bash_profile,.bashrc}
        fi
        check_update_le_hm_ssl ${_HM_U}
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
}

###--------------------###
echo "INFO: Daily maintenance start"
#
_NOW=$(date +%y%m%d-%H%M 2>&1)
_NOW=${_NOW//[^0-9-]/}
_DOW=$(date +%u 2>&1)
_DOW=${_DOW//[^1-7]/}
_CHECK_HOST=$(uname -n 2>&1)
_VM_TEST=$(uname -a 2>&1)
if [[ "${_VM_TEST}" =~ "3.8.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.7.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.6.15-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.2.16-beng" ]]; then
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
  _MODULES_FORCE="background_process coder cookie_cache_bypass css_gzip hacked \
    javascript_aggregator memcache memcache_admin poormanscron search_krumo \
    security_review site_audit stage_file_proxy syslog supercron ultimate_cron \
    varnish watchdog_live xhprof"
fi
#
if [ "${_DOW}" = "6" ]; then
  _MODULES_ON_SEVEN="robotstxt"
  _MODULES_ON_SIX="path_alias_cache robotstxt"
  _MODULES_OFF_SEVEN="background_process coder dblog devel hacked l10n_update \
   linkchecker memcache memcache_admin performance search_krumo \
   security_review site_audit stage_file_proxy syslog ultimate_cron update \
   varnish watchdog_live xhprof"
  _MODULES_OFF_SIX="background_process coder cookie_cache_bypass css_gzip \
    dblog devel hacked javascript_aggregator linkchecker l10n_update memcache \
    memcache_admin performance poormanscron search_krumo security_review \
    stage_file_proxy supercron syslog ultimate_cron update varnish \
    watchdog_live xhprof"
elif [ "${_DOW}" = "3" ]; then
  _MODULES_ON_SEVEN="robotstxt"
  _MODULES_ON_SIX="path_alias_cache robotstxt"
  _MODULES_OFF_SEVEN="background_process dblog syslog update"
  _MODULES_OFF_SIX="background_process dblog syslog update"
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
elif [ -e "/data/disk/all" ]; then
  cd /data/disk/all
  listl=([0-9]*)
  _LAST_ALL=${listl[@]: -1}
  _O_CONTRIB="/data/disk/all/${_LAST_ALL}/o_contrib"
  _O_CONTRIB_SEVEN="/data/disk/all/${_LAST_ALL}/o_contrib_seven"
else
  _O_CONTRIB=NO
  _O_CONTRIB_SEVEN=NO
fi
#
mkdir -p /var/xdrago/log/daily
#
if [ -e "/root/.barracuda.cnf" ]; then
  source /root/.barracuda.cnf
fi
#
find_fast_mirror
#
if [ -e "/var/run/boa_wait.pid" ] \
  && [ ! -e "/var/run/boa_system_wait.pid" ]; then
  touch /var/xdrago/log/wait-for-boa
  exit 1
elif [ -e "/var/run/daily-fix.pid" ]; then
  touch /var/xdrago/log/wait-for-daily
  exit 1
elif [ -e "/root/.wbhd.clstr.cnf" ]; then
  exit 1
else
  touch /var/run/daily-fix.pid
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ]; then
    _PERMISSIONS_FIX=YES
    _MODULES_FIX=YES
    n=$((RANDOM%900+80))
    echo "waiting $n sec"
    sleep $n
  fi
  if [ -z "${_PERMISSIONS_FIX}" ]; then
    _PERMISSIONS_FIX=YES
  fi
  if [ -z "${_MODULES_FIX}" ]; then
    _MODULES_FIX=YES
  fi
  if [ -e "/data/all" ]; then
    find /data/all -type f -name "*.info" -print0 | xargs -0 sed -i \
      's/.*dependencies\[\] = update/;dependencies\[\] = update/g' &> /dev/null
    wait
    if [ ! -e "/data/all/permissions-fix-post-up-${_X_SE}.info" ]; then
      rm -f /data/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/all/permissions-fix-post-up-${_X_SE}.info
    fi
  elif [ -e "/data/disk/all" ]; then
    find /data/disk/all -type f -name "*.info" -print0 | xargs -0 sed -i \
      's/.*dependencies\[\] = update/;dependencies\[\] = update/g' &> /dev/null
    wait
    if [ ! -e "/data/disk/all/permissions-fix-post-up-${_X_SE}.info" ]; then
      rm -f /data/disk/all/permissions-fix*
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type d -exec chmod 02775 {} \; &> /dev/null
      find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} \
        -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > /data/disk/all/permissions-fix-post-up-${_X_SE}.info
    fi
  fi

  action >/var/xdrago/log/daily/daily-${_NOW}.log 2>&1

  dhpWildPath="/etc/ssl/private/nginx-wild-ssl.dhp"
  if [ -e "/etc/ssl/private/4096.dhp" ]; then
    dhpPath="/etc/ssl/private/4096.dhp"
    _DIFF_T=$(diff ${dhpPath} ${dhpWildPath} 2>&1)
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
    sed -i "s/ssl_prefer_server_ciphers .*/ssl_prefer_server_ciphers on;\n  ssl_stapling on;\n  ssl_stapling_verify on;\n  resolver 8.8.8.8 8.8.4.4 valid=300s;\n  resolver_timeout 5s;/g" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf &> /dev/null
    wait
    sed -i "s/ *$//g; /^$/d" /var/aegir/config/server_*/nginx/pre.d/*ssl_proxy.conf                      &> /dev/null
    wait
    service nginx reload
  fi
fi

###--------------------###
if [ -z "${_SKYNET_MODE}" ] || [ "${_SKYNET_MODE}" = "ON" ]; then
  echo "INFO: Checking BARRACUDA version"
  rm -f /opt/tmp/barracuda-version.txt*
  curl -L -k -s \
    --max-redirs 10 \
    --retry 3 \
    --retry-delay 15 -A iCab \
    "${urlHmr}/conf/barracuda-version.txt" \
    -o /opt/tmp/barracuda-version.txt
else
  rm -f /opt/tmp/barracuda-version.txt*
fi
if [ -e "/opt/tmp/barracuda-version.txt" ]; then
  _X_VERSION=$(cat /opt/tmp/barracuda-version.txt 2>&1)
  _VERSIONS_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
  if [ ! -z "${_X_VERSION}" ]; then
    if [[ "${_VERSIONS_TEST}" =~ "${_X_VERSION}" ]]; then
      _VERSIONS_TEST_RESULT=OK
      echo "INFO: Version test result: OK"
    else
      sT="Stable Edition available"
      cat <<EOF | mail -e -s "New ${_X_VERSION} ${sT}" notify\@omega8.cc

 There is new ${_X_VERSION} Stable Edition available.

 Please review the changelog and upgrade as soon as possible
 to receive all security updates and new features.

 Changelog: http://bit.ly/boa-changes

 --
 This email has been sent by your Barracuda server upgrade monitor.

EOF
    echo "INFO: Update notice sent: OK"
    fi
  fi
fi
#
if [ "${_PERMISSIONS_FIX}" = "YES" ] \
  && [ ! -z "${_X_VERSION}" ] \
  && [ -e "/opt/tmp/barracuda-version.txt" ] \
  && [ ! -e "/data/all/permissions-fix-${_X_VERSION}-fixed-dz.info" ]; then
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
  echo fixed > /data/all/permissions-fix-${_X_VERSION}-fixed-dz.info
fi
if [ ! -e "/var/backups/fix-sites-all-permsissions-${_X_SE}.txt" ]; then
  chmod 0751  /data/disk/*/distro/*/*/sites &> /dev/null
  chmod 0755  /data/disk/*/distro/*/*/sites/all &> /dev/null
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  echo FIXED > /var/backups/fix-sites-all-permsissions-${_X_SE}.txt
  echo "Permissions in sites/all tree just fixed"
fi
find /var/backups/ltd/*/* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
find /var/backups/jetty* -mtime +0 -exec rm -rf {} \; &> /dev/null
find /var/backups/dragon/* -mtime +7 -exec rm -rf {} \; &> /dev/null
if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
  || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
  || [ "${_VMFAMILY}" = "VS" ] \
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
###EOF2016###
