#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

tRee=pro
export tRee="${tRee}"

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

if [ -e "/root/.pause_tasks_maint.cnf" ]; then
  exit 0
fi

os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
  _OS_LIST="daedalus chimaera beowulf buster bullseye bookworm"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
os_detection_minimal

apt_clean_update() {
  #apt-get clean -qq 2> /dev/null
  #rm -rf /var/lib/apt/lists/* &> /dev/null
  ${_APT_UPDATE} -qq 2> /dev/null
}

_X_SE="540devT02"
_CHECK_HOST=$(uname -n 2>&1)
usrGroup=users
_WEBG=www-data
_OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)
if [ -x "/usr/bin/gpg2" ]; then
  _GPG=gpg2
else
  _GPG=gpg
fi
crlGet="-L --max-redirs 10 -k -s --retry 10 --retry-delay 5 -A iCab"
aptYesUnth="-y --allow-unauthenticated"

###-------------SYSTEM-----------------###

_CHECK_HOST=$(uname -n 2>&1)
if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
    hostedSys=YES
  else
    hostedSys=NO
  fi
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
}

find_fast_mirror_early() {
  isNetc=$(which netcat 2>&1)
  if [ ! -x "${isNetc}" ] || [ -z "${isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    apt_clean_update
    apt-get install netcat ${aptYesUnth} 2> /dev/null
    apt-get install netcat-traditional ${aptYesUnth} 2> /dev/null
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

###----------------------------###
##    Manage ltd shell users    ##
###----------------------------###
#
# Remove dangerous stuff from the string.
sanitize_string() {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\&\|\*]//g; s/\(['"'"'\]\)//g'
}
#
# Add ltd-shell group if not exists.
add_ltd_group_if_not_exists() {
  _LTD_EXISTS=$(getent group ltd-shell 2>&1)
  if [[ "${_LTD_EXISTS}" =~ "ltd-shell" ]]; then
    _DO_NOTHING=YES
  else
    addgroup --system ltd-shell &> /dev/null
  fi
}
#
# Enable chattr.
enable_chattr() {
  isTest="$1"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [ -d "/home/$1/" ]; then
    _U_HD="/home/$1/.drush"
    _U_TP="/home/$1/.tmp"
    _U_II="${_U_HD}/php.ini"
    if [ ! -e "${_U_HD}/.ctrl.${_X_SE}.pid" ]; then
      if_hosted_sys
      if [ "${hostedSys}" = "YES" ]; then
        rm -rf ${_U_HD}/
      else
        rm -f ${_U_HD}/{drush_make,registry_rebuild,clean_missing_modules}
        rm -f ${_U_HD}/{drupalgeddon,drush_ecl,make_local,safe_cache_form*}
        rm -f ${_U_HD}/usr/{drush_make,registry_rebuild,clean_missing_modules}
        rm -f ${_U_HD}/usr/{drupalgeddon,drush_ecl,make_local,safe_cache_form*}
        rm -f ${_U_HD}/usr/{mydropwizard,utf8mb4_convert}
        rm -f ${_U_HD}/.ctrl*
        rm -rf ${_U_HD}/{cache,drush.ini,*drushrc*,*.inc}
      fi
      mkdir -p ${_U_HD}/usr
      mkdir -p ${_U_TP}
      touch ${_U_TP}
      find ${_U_TP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
      chown $1:${usrGroup} ${_U_TP}
      chown $1:${usrGroup} ${_U_HD}
      chmod 02755 ${_U_TP}
      chmod 02755 ${_U_HD}
      if [ ! -L "${_U_HD}/usr/registry_rebuild" ] \
        && [ -e "${dscUsr}/.drush/usr/registry_rebuild" ]; then
        ln -sfn ${dscUsr}/.drush/usr/registry_rebuild \
          ${_U_HD}/usr/registry_rebuild
      fi
      if [ ! -L "${_U_HD}/usr/clean_missing_modules" ] \
        && [ -e "${dscUsr}/.drush/usr/clean_missing_modules" ]; then
        ln -sfn ${dscUsr}/.drush/usr/clean_missing_modules \
          ${_U_HD}/usr/clean_missing_modules
      fi
      if [ ! -L "${_U_HD}/usr/drupalgeddon" ] \
        && [ -e "${dscUsr}/.drush/usr/drupalgeddon" ]; then
        ln -sfn ${dscUsr}/.drush/usr/drupalgeddon \
          ${_U_HD}/usr/drupalgeddon
      fi
      if [ ! -L "${_U_HD}/usr/drush_ecl" ] \
        && [ -e "${dscUsr}/.drush/usr/drush_ecl" ]; then
        ln -sfn ${dscUsr}/.drush/usr/drush_ecl \
          ${_U_HD}/usr/drush_ecl
      fi
      if [ ! -L "${_U_HD}/usr/safe_cache_form_clear" ] \
        && [ -e "${dscUsr}/.drush/usr/safe_cache_form_clear" ]; then
        ln -sfn ${dscUsr}/.drush/usr/safe_cache_form_clear \
          ${_U_HD}/usr/safe_cache_form_clear
      fi
      if [ ! -L "${_U_HD}/usr/utf8mb4_convert" ] \
        && [ -e "${dscUsr}/.drush/usr/utf8mb4_convert" ]; then
        ln -sfn ${dscUsr}/.drush/usr/utf8mb4_convert \
          ${_U_HD}/usr/utf8mb4_convert
      fi
    fi

    _CHECK_USE_PHP_CLI=$(grep "/opt/php" \
      ${dscUsr}/tools/drush/drush.php 2>&1)
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
        && [ ! -e "${_U_HD}/.ctrl.php${e}.${_X_SE}.pid" ]; then
        _PHP_CLI_UPDATE=YES
      fi
    done
    echo _PHP_CLI_UPDATE is ${_PHP_CLI_UPDATE} for $1

    if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
      || [ ! -e "${_U_II}" ] \
      || [ ! -e "${_U_HD}/.ctrl.${_X_SE}.pid" ]; then
      mkdir -p ${_U_HD}
      rm -f ${_U_HD}/.ctrl.php*
      rm -f ${_U_II}
      if [ ! -z "${_T_CLI_VRN}" ]; then
        _USE_PHP_CLI="${_T_CLI_VRN}"
        echo "_USE_PHP_CLI is ${_USE_PHP_CLI} for $1 at ${_USER} WTF"
        echo "_T_CLI_VRN is ${_T_CLI_VRN}"
      else
        _CHECK_USE_PHP_CLI=$(grep "/opt/php" \
          ${dscUsr}/tools/drush/drush.php 2>&1)
        echo "_CHECK_USE_PHP_CLI is ${_CHECK_USE_PHP_CLI} for $1 at ${_USER}"
        if [[ "${_CHECK_USE_PHP_CLI}" =~ "php83" ]]; then
          _USE_PHP_CLI=8.3
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php82" ]]; then
          _USE_PHP_CLI=8.2
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php81" ]]; then
          _USE_PHP_CLI=8.1
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php80" ]]; then
          _USE_PHP_CLI=8.0
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php74" ]]; then
          _USE_PHP_CLI=7.4
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php73" ]]; then
          _USE_PHP_CLI=7.3
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php72" ]]; then
          _USE_PHP_CLI=7.2
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php71" ]]; then
          _USE_PHP_CLI=7.1
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php70" ]]; then
          _USE_PHP_CLI=7.0
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php56" ]]; then
          _USE_PHP_CLI=5.6
        fi
      fi
      echo _USE_PHP_CLI is ${_USE_PHP_CLI} for $1
      if [ "${_USE_PHP_CLI}" = "8.3" ]; then
        cp -af /opt/php83/lib/php.ini ${_U_II}
        _U_INI=83
      elif [ "${_USE_PHP_CLI}" = "8.2" ]; then
        cp -af /opt/php82/lib/php.ini ${_U_II}
        _U_INI=82
      elif [ "${_USE_PHP_CLI}" = "8.1" ]; then
        cp -af /opt/php81/lib/php.ini ${_U_II}
        _U_INI=81
      elif [ "${_USE_PHP_CLI}" = "8.0" ]; then
        cp -af /opt/php80/lib/php.ini ${_U_II}
        _U_INI=80
      elif [ "${_USE_PHP_CLI}" = "7.4" ]; then
        cp -af /opt/php74/lib/php.ini ${_U_II}
        _U_INI=74
      elif [ "${_USE_PHP_CLI}" = "7.3" ]; then
        cp -af /opt/php73/lib/php.ini ${_U_II}
        _U_INI=73
      elif [ "${_USE_PHP_CLI}" = "7.2" ]; then
        cp -af /opt/php72/lib/php.ini ${_U_II}
        _U_INI=72
      elif [ "${_USE_PHP_CLI}" = "7.1" ]; then
        cp -af /opt/php71/lib/php.ini ${_U_II}
        _U_INI=71
      elif [ "${_USE_PHP_CLI}" = "7.0" ]; then
        cp -af /opt/php70/lib/php.ini ${_U_II}
        _U_INI=70
      elif [ "${_USE_PHP_CLI}" = "5.6" ]; then
        cp -af /opt/php56/lib/php.ini ${_U_II}
        _U_INI=56
      fi
      if [ -e "${_U_II}" ]; then
        _INI="open_basedir = \".: \
          /data/all:        \
          /data/conf:       \
          /data/disk/all:   \
          /home/$1:         \
          /opt/php56:       \
          /opt/php70:       \
          /opt/php71:       \
          /opt/php72:       \
          /opt/php73:       \
          /opt/php74:       \
          /opt/php80:       \
          /opt/php81:       \
          /opt/php82:       \
          /opt/php83:       \
          /opt/tika:        \
          /opt/tika7:       \
          /opt/tika8:       \
          /opt/tika9:       \
          /dev/urandom:     \
          /opt/tools/drush: \
          /usr/bin:         \
          /usr/local/bin:   \
          ${dscUsr}/.drush/usr: \
          ${dscUsr}/distro:     \
          ${dscUsr}/platforms:  \
          ${dscUsr}/static\""
        _INI=$(echo "${_INI}" | sed "s/ //g" 2>&1)
        _INI=$(echo "${_INI}" | sed "s/open_basedir=/open_basedir = /g" 2>&1)
        _INI=${_INI//\//\\\/}
        _QTP=${_U_TP//\//\\\/}
        sed -i "s/.*open_basedir =.*/${_INI}/g"                              ${_U_II}
        wait
        sed -i "s/.*error_reporting =.*/error_reporting = 1/g"               ${_U_II}
        wait
        sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_U_II}
        wait
        sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_U_II}
        wait
        sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_U_II}
        wait
        sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_U_II}
        wait
        echo > ${_U_HD}/.ctrl.php${_U_INI}.${_X_SE}.pid
        echo > ${_U_HD}/.ctrl.${_X_SE}.pid
      fi
    fi

    UQ="$1"
    chage -M 99999 ${UQ} &> /dev/null
    _UPDATE_GEMS=NO
    ###
    ### Cleanup of no longer used/allowed Ruby Gems and NPM access leftovers
    ###
    [ -e "/home/${UQ}/.rvm" ] && rm -rf /home/${UQ}/.rvm*
    [ -e "/home/${UQ}/.gem" ] && rm -rf /home/${UQ}/.gem*
    [ -e "/home/${UQ}/.npm" ] && rm -rf /home/${UQ}/.npm*
    [ -e "/home/${UQ}/.mkshrc" ] && rm -rf /home/${UQ}/.mkshrc
    if [ "$1" = "${_USER}.ftp" ]; then
      [ ! -d "/home/${UQ}/.composer" ] && su -s /bin/bash - ${UQ} -c "mkdir ~/.composer"
    else
      [ -d "/home/${UQ}/.composer" ] && rm -rf /home/${UQ}/.composer
    fi
    ###
    ### Check if Ruby Gems and NPM access should be added or removed
    ###
    if [ -f "${dscUsr}/static/control/compass.info" ]; then
      ###
      ### Check if Ruby Gems access needs an update
      ###
      if [ ! -e "/opt/user/gems/${UQ}/gems/oily_png-1.1.1" ] \
        || [ ! -e "${dscUsr}/log/.gems.build.rb.${UQ}.${_X_SE}.txt" ]; then
        _UPDATE_GEMS=YES
      fi
      if [ ! -e "/opt/user/npm/${UQ}/.npm-packages/bin" ] \
        && [ -e "/root/.allow.node.lshell.cnf" ]; then
        _UPDATE_GEMS=YES
      fi
    else
      ###
      ### Remove no longer used Ruby Gems and NPM access
      ###
      [ -e "/home/${UQ}/.npm" ] && rm -rf /home/${UQ}/.npm*
      [ -e "/opt/user/gems/${UQ}" ] && rm -rf /opt/user/gems/${UQ}
      [ -e "/opt/user/npm/${UQ}" ] && rm -rf /opt/user/npm/${UQ}
      [ -e "${dscUsr}/log" ] && rm -f ${dscUsr}/log/.gems.build*
      [ -e "${dscUsr}/log" ] && rm -f ${dscUsr}/log/.npm.build*
    fi
    if [ "${_UPDATE_GEMS}" = "YES" ]; then
      ###
      ### Ruby Gems are allowed for both main and client SSH accounts
      ###
      [ ! -d "/opt/user/gems/${UQ}" ] && mkdir -p /opt/user/gems/${UQ}
      chmod 1777 /opt/user/gems
      chown -R ${UQ}:users /opt/user/gems/${UQ}
      chown root:root /opt/user/gems
      if [ -d "/opt/user/gems/${UQ}" ] \
        && [ -e "/usr/local/lib/ruby/gems/3.3.0/gems/oily_png-1.1.1" ] \
        && [ ! -e "/opt/user/gems/${UQ}/gems/oily_png-1.1.1" ]; then
        cp -a /usr/local/lib/ruby/gems/3.3.0/gems /opt/user/gems/${UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/specifications /opt/user/gems/${UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/extensions /opt/user/gems/${UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/doc /opt/user/gems/${UQ}/
        chown -R ${UQ}:users /opt/user/gems/${UQ}
        [ -e "${dscUsr}/log" ] && rm -f ${dscUsr}/log/.gems.build*
        touch ${dscUsr}/log/.gems.build.rb.${UQ}.${_X_SE}.txt
      fi
      ###
      ### Check if NPM support is allowed and if needs an update
      ### NOTE: It will be restricted to the main SSH account only
      ###
      if [ -e "/root/.allow.node.lshell.cnf" ] \
        && [ "$1" = "${_USER}.ftp" ] \
        && [ -x "/usr/bin/node" ] \
        && [ -e "/home/${UQ}/static/control" ]; then
        if [ ! -e "/opt/user/npm/${UQ}/.npm-packages/bin" ] \
          || [ ! -e "${dscUsr}/log/.npm.build.${UQ}.${_X_SE}.txt" ]; then
          [ ! -d "/opt/user/npm" ] && mkdir -p /opt/user/npm
          chown root:root /opt/user/npm
          chmod 1777 /opt/user/npm
          [ ! -d "/opt/user/npm/${UQ}" ] && mkdir -p /opt/user/npm/${UQ}
          [ ! -e "/home/${UQ}/.npmrc" ] && su -s /bin/bash - ${UQ} -c "echo 'prefix = /opt/user/npm/${UQ}/.npm-packages' > ~/.npmrc"
          [ -e "/home/${UQ}/.npmrc" ] && chattr +i /home/${UQ}/.npmrc
          mkdir -p /opt/user/npm/${UQ}/.bundle
          mkdir -p /opt/user/npm/${UQ}/.composer
          mkdir -p /opt/user/npm/${UQ}/.config
          mkdir -p /opt/user/npm/${UQ}/.npm
          mkdir -p /opt/user/npm/${UQ}/.npm-packages/bin
          mkdir -p /opt/user/npm/${UQ}/.npm-packages/lib/node_modules
          mkdir -p /opt/user/npm/${UQ}/.sass-cache
          chown -R ${UQ}:users /opt/user/npm/${UQ}
          [ -e "${dscUsr}/log" ] && rm -f ${dscUsr}/log/.npm.build*
          touch ${dscUsr}/log/.npm.build.${UQ}.${_X_SE}.txt
        fi
      else
        [ -e "/home/${UQ}/.npm" ] && rm -rf /home/${UQ}/.npm*
        [ -e "/opt/user/npm/${UQ}" ] && rm -rf /opt/user/npm/${UQ}
        [ -e "${dscUsr}/log" ] && rm -f ${dscUsr}/log/.npm.build*
      fi
    fi
    rm -f /home/${UQ}/{.profile,.bash_logout,.bash_profile,.bashrc,.zlogin,.zshrc}
    chage -M 90 ${UQ} &> /dev/null

    if [ "$1" != "${_USER}.ftp" ]; then
      if [ -d "/home/$1/" ]; then
        chattr +i /home/$1/
      fi
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
#
# Disable chattr.
disable_chattr() {
  isTest="$1"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_USER}.ftp" ]; then
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
#
# Kill zombies.
kill_zombies() {
  for Existing in `cat /etc/passwd | cut -d ':' -f1 | sort`; do
    _SEC_IDY=$(id -nG ${Existing} 2>&1)
    if [[ "${_SEC_IDY}" =~ "ltd-shell" ]] \
      && [ ! -z "${Existing}" ] \
      && [[ ! "${Existing}" =~ ".ftp"($) ]] \
      && [[ ! "${Existing}" =~ ".web"($) ]]; then
      usrParent=$(echo ${Existing} | cut -d. -f1 | awk '{ print $1}' 2>&1)
      usrParentTest=${usrParent//[^a-z0-9]/}
      if [ ! -z "${usrParentTest}" ]; then
        _PAR_DIR="/data/disk/${usrParent}/clients"
        _SEC_SYM="/home/${Existing}/sites"
        _SEC_DIR=$(readlink -n ${_SEC_SYM} 2>&1)
        _SEC_DIR=$(echo -n ${_SEC_DIR} | tr -d "\n" 2>&1)
        if [ ! -L "${_SEC_SYM}" ] || [ ! -e "${_SEC_DIR}" ] \
          || [ ! -e "/home/${usrParent}.ftp/users/${Existing}" ]; then
          mkdir -p /var/backups/zombie/deleted/${_NOW}
          kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
          disable_chattr ${Existing}
          rm -rf /home/${Existing}/.gnupg
          deluser \
            --remove-home \
            --backup-to /var/backups/zombie/deleted/${_NOW} ${Existing} &> /dev/null
          rm -f /home/${usrParent}.ftp/users/${Existing}
          echo Zombie from etc.passwd ${Existing} killed
          echo
        fi
      fi
    fi
  done
  for Existing in `ls /home | cut -d '/' -f1 | sort`; do
    isTest=${Existing//[^a-z0-9]/}
    if [ ! -z "${isTest}" ]; then
      _SEC_IDY=$(id -nG ${Existing} 2>&1)
      if [[ "${_SEC_IDY}" =~ "No such user" ]] \
        && [ ! -z "${Existing}" ] \
        && [[ ! "${Existing}" =~ ".ftp"($) ]] \
        && [[ ! "${Existing}" =~ ".web"($) ]]; then
        disable_chattr ${Existing}
        mkdir -p /var/backups/zombie/deleted/${_NOW}
        mv /home/${Existing} /var/backups/zombie/deleted/${_NOW}/.leftover-${Existing}
        usrParent=$(echo ${Existing} | cut -d. -f1 | awk '{ print $1}' 2>&1)
        if [ -e "/home/${usrParent}.ftp/users/${Existing}" ]; then
          rm -f /home/${usrParent}.ftp/users/${Existing}
        fi
        echo Zombie from home.dir ${Existing} killed
        echo
      fi
    fi
  done
}
#
# Fix dot dirs.
fix_dot_dirs() {
  usrLtdTest=${usrLtd//[^a-z0-9]/}
  if [ ! -z "${usrLtdTest}" ]; then
    usrTmp="/home/${usrLtd}/.tmp"
    if [ ! -d "${usrTmp}" ]; then
      mkdir -p ${usrTmp}
      chown ${usrLtd}:${usrGroup} ${usrTmp}
      chmod 02755 ${usrTmp}
    fi
    usrLftp="/home/${usrLtd}/.lftp"
    if [ ! -d "${usrLftp}" ]; then
      mkdir -p ${usrLftp}
      chown ${usrLtd}:${usrGroup} ${usrLftp}
      chmod 02755 ${usrLftp}
    fi
    usrLhist="/home/${usrLtd}/.lhistory"
    if [ ! -e "${usrLhist}" ]; then
      touch ${usrLhist}
      chown ${usrLtd}:${usrGroup} ${usrLhist}
      chmod 644 ${usrLhist}
    fi
    usrDrush="/home/${usrLtd}/.drush"
    if [ ! -d "${usrDrush}" ]; then
      mkdir -p ${usrDrush}
      chown ${usrLtd}:${usrGroup} ${usrDrush}
      chmod 700 ${usrDrush}
    fi
    usrSsh="/home/${usrLtd}/.ssh"
    if [ ! -d "${usrSsh}" ]; then
      mkdir -p ${usrSsh}
      chown -R ${usrLtd}:${usrGroup} ${usrSsh}
      chmod 700 ${usrSsh}
    fi
    chmod 600 ${usrSsh}/id_{r,d}sa &> /dev/null
    chmod 600 ${usrSsh}/known_hosts &> /dev/null
    usrBzr="/home/${usrLtd}/.bazaar"
    if [ -x "/usr/local/bin/bzr" ]; then
      if [ ! -z "${usrLtd}" ] && [ ! -e "${usrBzr}/bazaar.conf" ]; then
        mkdir -p ${usrBzr}
        echo ignore_missing_extensions=True > ${usrBzr}/bazaar.conf
        chown -R ${usrLtd}:${usrGroup} ${usrBzr}
        chmod 700 ${usrBzr}
      fi
    else
      if [ ! -z "${usrLtd}" ] && [ -d "${usrBzr}" ]; then
        rm -rf ${usrBzr}
      fi
    fi
  fi
}
#
# Manage Drush Aliases.
manage_sec_user_drush_aliases() {
  if [ -e "${Client}" ]; then
    if [ -L "${usrLtdRoot}/sites" ]; then
      symTgt=$(readlink -n ${usrLtdRoot}/sites 2>&1)
      symTgt=$(echo -n ${symTgt} | tr -d "\n" 2>&1)
    else
      rm -f ${usrLtdRoot}/sites
    fi
    if [ "${symTgt}" != "${Client}" ] \
      || [ ! -e "${usrLtdRoot}/sites" ]; then
      rm -f ${usrLtdRoot}/sites
      ln -sfn ${Client} ${usrLtdRoot}/sites
    fi
  fi
  if [ ! -e "${usrLtdRoot}/.drush" ]; then
    mkdir -p ${usrLtdRoot}/.drush
  fi
  for Alias in `find ${usrLtdRoot}/.drush/*.alias.drushrc.php \
    -maxdepth 1 -type f | sort`; do
    AliasName=$(echo "${Alias}" | cut -d'/' -f5 | awk '{ print $1}' 2>&1)
    AliasName=$(echo "${AliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [ ! -z "${AliasName}" ] \
      && [ ! -e "${usrLtdRoot}/sites/${AliasName}" ]; then
      rm -f ${usrLtdRoot}/.drush/${AliasName}.alias.drushrc.php
    fi
  done
  for Symlink in `find ${usrLtdRoot}/sites/ \
    -maxdepth 1 -mindepth 1 | sort`; do
    SiteName=$(echo ${Symlink}  \
      | cut -d'/' -f5 \
      | awk '{ print $1}' 2>&1)
    pthAliasMain="${pthParentUsr}/.drush/${SiteName}.alias.drushrc.php"
    pthAliasCopy="${usrLtdRoot}/.drush/${SiteName}.alias.drushrc.php"
    if [ ! -z "${SiteName}" ] && [ ! -e "${pthAliasCopy}" ]; then
      cp -af ${pthAliasMain} ${pthAliasCopy}
      chmod 440 ${pthAliasCopy}
    elif [ ! -z "${SiteName}" ]  && [ -e "${pthAliasCopy}" ]; then
      _DIFF_T=$(diff -w -B ${pthAliasCopy} ${pthAliasMain} 2>&1)
      if [ ! -z "${_DIFF_T}" ]; then
        cp -af ${pthAliasMain} ${pthAliasCopy}
        chmod 440 ${pthAliasCopy}
      fi
    fi
  done
}
#
# OK, create user.
ok_create_user() {
  usrLtdTest=${usrLtd//[^a-z0-9]/}
  if [ ! -z "${usrLtdTest}" ]; then
    _ADMIN="${_USER}.ftp"
    echo "_ADMIN is == ${_ADMIN} == at ok_create_user"
    usrLtdRoot="/home/${usrLtd}"
    _SEC_SYM="${usrLtdRoot}/sites"
    _TMP="/var/tmp"
    if [ ! -L "${_SEC_SYM}" ]; then
      mkdir -p /var/backups/zombie/deleted/${_NOW}
      mv -f ${usrLtdRoot} /var/backups/zombie/deleted/${_NOW}/ &> /dev/null
    fi
    if [ ! -d "${usrLtdRoot}" ]; then
      if [ -e "/usr/bin/mysecureshell" ] && [ -e "/etc/ssh/sftp_config" ]; then
        useradd -d ${usrLtdRoot} -s /usr/bin/mysecureshell -m -N -r ${usrLtd}
        echo "usrLtdRoot is == ${usrLtdRoot} == at ok_create_user"
      else
        useradd -d ${usrLtdRoot} -s /usr/bin/lshell -m -N -r ${usrLtd}
      fi
      adduser ${usrLtd} ${_WEBG}
      _ESC_LUPASS=""
      _LEN_LUPASS=0
      if [ "${_STRONG_PASSWORDS}" = "YES" ]  ; then
        _PWD_CHARS=64
      elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
        _PWD_CHARS=32
      else
        _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
        if [ ! -z "${_STRONG_PASSWORDS}" ] \
          && [ "${_STRONG_PASSWORDS}" -gt "32" ]; then
          _PWD_CHARS="${_STRONG_PASSWORDS}"
        else
          _PWD_CHARS=32
        fi
        if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt "128" ]; then
          _PWD_CHARS=128
        fi
      fi
      if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt "32" ]; then
        _RANDPASS_TEST=$(randpass -V 2>&1)
        if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
          _ESC_LUPASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
        else
          _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
          _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
          _ESC_LUPASS=$(sanitize_string "${_ESC_LUPASS}" 2>&1)
        fi
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _LEN_LUPASS=$(echo ${#_ESC_LUPASS} 2>&1)
      fi
      if [ -z "${_ESC_LUPASS}" ] || [ "${_LEN_LUPASS}" -lt "9" ]; then
        _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _ESC_LUPASS=$(sanitize_string "${_ESC_LUPASS}" 2>&1)
      fi
      ph=$(mkpasswd -m sha-512 "${_ESC_LUPASS}" \
        $(openssl rand -base64 16 | tr -d '+=' | head -c 16) 2>&1)
      usermod -p $ph ${usrLtd}
      passwd -w 7 -x 90 ${usrLtd}
      usermod -aG lshellg ${usrLtd}
      usermod -aG ltd-shell ${usrLtd}
    fi
    if [ ! -e "/home/${_ADMIN}/users/${usrLtd}" ] \
      && [ ! -z "${_ESC_LUPASS}" ]; then
      if [ -e "/usr/bin/mysecureshell" ] \
        && [ -e "/etc/ssh/sftp_config" ]; then
        chsh -s /usr/bin/mysecureshell ${usrLtd}
      else
        chsh -s /usr/bin/lshell ${usrLtd}
      fi
      echo >> ${_THIS_LTD_CONF}
      echo "[${usrLtd}]" >> ${_THIS_LTD_CONF}
      echo "path : [${_ALLD_DIR}]" >> ${_THIS_LTD_CONF}
      chmod 700 ${usrLtdRoot}
      mkdir -p /home/${_ADMIN}/users
      echo "${_ESC_LUPASS}" > /home/${_ADMIN}/users/${usrLtd}
    fi
    fix_dot_dirs
    rm -f ${usrLtdRoot}/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
}
#
# OK, update user.
ok_update_user() {
  usrLtdTest=${usrLtd//[^a-z0-9]/}
  if [ ! -z "${usrLtdTest}" ]; then
    _ADMIN="${_USER}.ftp"
    usrLtdRoot="/home/${usrLtd}"
    if [ -e "/home/${_ADMIN}/users/${usrLtd}" ]; then
      echo >> ${_THIS_LTD_CONF}
      echo "[${usrLtd}]" >> ${_THIS_LTD_CONF}
      echo "path : [${_ALLD_DIR}]" >> ${_THIS_LTD_CONF}
      manage_sec_user_drush_aliases
      chmod 700 ${usrLtdRoot}
    fi
    fix_dot_dirs
    rm -f ${usrLtdRoot}/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
}
#
# Add user if not exists.
add_user_if_not_exists() {
  usrLtdTest=${usrLtd//[^a-z0-9]/}
  if [ ! -z "${usrLtdTest}" ]; then
    _ID_EXISTS=$(getent passwd ${usrLtd} 2>&1)
    _ID_SHELLS=$(id -nG ${usrLtd} 2>&1)
    echo "_ID_EXISTS is == ${_ID_EXISTS} == at add_user_if_not_exists"
    echo "_ID_SHELLS is == ${_ID_SHELLS} == at add_user_if_not_exists"
    if [ -z "${_ID_EXISTS}" ]; then
      echo "We will create user == ${usrLtd} =="
      ok_create_user
      manage_sec_user_drush_aliases
      enable_chattr ${usrLtd}
    elif [[ "${_ID_EXISTS}" =~ "${usrLtd}" ]] \
      && [[ "${_ID_SHELLS}" =~ "ltd-shell" ]]; then
      echo "We will update user == ${usrLtd} =="
      disable_chattr ${usrLtd}
      rm -rf /home/${usrLtd}/drush-backups
      usrTmp="/home/${usrLtd}/.tmp"
      if [ ! -d "${usrTmp}" ]; then
        mkdir -p ${usrTmp}
        chown ${usrLtd}:${usrGroup} ${usrTmp}
        chmod 02755 ${usrTmp}
      fi
      find ${usrTmp} -mtime +0 -exec rm -rf {} \; &> /dev/null
      ok_update_user
      enable_chattr ${usrLtd}
    fi
  fi
}
#
# Manage Access Paths.
manage_sec_access_paths() {
#for Domain in `find ${Client}/ -maxdepth 1 -mindepth 1 -type l -printf %P\\n | sort`
for Domain in `find ${Client}/ -maxdepth 1 -mindepth 1 -type l | sort`; do
  rawDom=$(echo ${Domain} | cut -d'/' -f7 | awk '{ print $1}' 2>&1)
  _STATIC_FILES="${pthParentUsr}/static/files/${rawDom}.files"
  _STATIC_PRIVATE="${pthParentUsr}/static/files/${rawDom}.private"
  _PATH_DOM=$(readlink -n ${Domain} 2>&1)
  _PATH_DOM=$(echo -n ${_PATH_DOM} | tr -d "\n" 2>&1)
  _RUBY_PATH="/opt/user/gems/${usrLtd}"
  _NPM_PATH="/opt/user/npm/${usrLtd}"
  _ALLD_DIR="${_ALLD_DIR}, '${_PATH_DOM}', '${_STATIC_FILES}', '${_STATIC_PRIVATE}', '${_RUBY_PATH}', '${_NPM_PATH}'"
  if [ -e "${_PATH_DOM}" ]; then
    _ALLD_NUM=$(( _ALLD_NUM += 1 ))
  fi
  echo Done for ${Domain} at ${Client}
done
}
#
# Manage Secondary Users.
manage_sec() {
for Client in `find ${pthParentUsr}/clients/ -maxdepth 1 -mindepth 1 -type d | sort`; do
  usrLtd=$(echo ${Client} | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
  usrLtd=${usrLtd//[^a-zA-Z0-9]/}
  usrLtd=$(echo -n ${usrLtd} | tr A-Z a-z 2>&1)
  if [ ! -z "${usrLtd}" ]; then
    usrLtd="${_USER}.${usrLtd}"
    echo "usrLtd is == ${usrLtd} == at manage_sec"
    _ALLD_NUM="0"
    _ALLD_CTL="1"
    _ALLD_DIR="'${Client}'"
    cd ${Client}
    manage_sec_access_paths
    #_ALLD_DIR="${_ALLD_DIR}, '/home/${usrLtd}'"
    if [ "${_ALLD_NUM}" -ge "${_ALLD_CTL}" ]; then
      add_user_if_not_exists
      echo Done for ${Client} at ${pthParentUsr}
    else
      echo Empty ${Client} at ${pthParentUsr} - deleting now
      if [ -e "${Client}" ]; then
        rmdir ${Client}
      fi
    fi
  fi
done
}
#
# Update local INI for PHP CLI on the Aegir Satellite Instance.
php_cli_local_ini_update() {
  _U_HD="${dscUsr}/.drush"
  _U_TP="${dscUsr}/.tmp"
  _U_II="${_U_HD}/php.ini"
  _PHP_CLI_UPDATE=NO
  _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_DRUSH_FILE} 2>&1)
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
      && [ ! -e "${_U_HD}/.ctrl.php${e}.${_X_SE}.pid" ]; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
    || [ ! -e "${_U_II}" ] \
    || [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_X_SE}.pid" ]; then
    mkdir -p ${_U_TP}
    touch ${_U_TP}
    find ${_U_TP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
    mkdir -p ${_U_HD}
    chown ${_USER}:${usrGroup} ${_U_TP}
    chown ${_USER}:${usrGroup} ${_U_HD}
    chmod 755 ${_U_TP}
    chmod 755 ${_U_HD}
    chattr -i ${_U_II}
    rm -f ${_U_HD}/.ctrl.php*
    rm -f ${_U_II}
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php83" ]]; then
      cp -af /opt/php83/lib/php.ini ${_U_II}
      _U_INI=83
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php82" ]]; then
      cp -af /opt/php82/lib/php.ini ${_U_II}
      _U_INI=82
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php81" ]]; then
      cp -af /opt/php81/lib/php.ini ${_U_II}
      _U_INI=81
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php80" ]]; then
      cp -af /opt/php80/lib/php.ini ${_U_II}
      _U_INI=80
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php74" ]]; then
      cp -af /opt/php74/lib/php.ini ${_U_II}
      _U_INI=74
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php73" ]]; then
      cp -af /opt/php73/lib/php.ini ${_U_II}
      _U_INI=73
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php72" ]]; then
      cp -af /opt/php72/lib/php.ini ${_U_II}
      _U_INI=72
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php71" ]]; then
      cp -af /opt/php71/lib/php.ini ${_U_II}
      _U_INI=71
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php70" ]]; then
      cp -af /opt/php70/lib/php.ini ${_U_II}
      _U_INI=70
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php56" ]]; then
      cp -af /opt/php56/lib/php.ini ${_U_II}
      _U_INI=56
    fi
    if [ -e "${_U_II}" ]; then
      _INI="open_basedir = \".: \
        /data/all:           \
        /data/conf:          \
        /data/disk/all:      \
        /opt/php56:          \
        /opt/php70:          \
        /opt/php71:          \
        /opt/php72:          \
        /opt/php73:          \
        /opt/php74:          \
        /opt/php80:          \
        /opt/php81:          \
        /opt/php82:          \
        /opt/php83:          \
        /opt/tika:           \
        /opt/tika7:          \
        /opt/tika8:          \
        /opt/tika9:          \
        /dev/urandom:        \
        /opt/tmp/make_local: \
        /opt/tools/drush:    \
        ${dscUsr}:           \
        /usr/local/bin:      \
        /usr/bin\""
      _INI=$(echo "${_INI}" | sed "s/ //g" 2>&1)
      _INI=$(echo "${_INI}" | sed "s/open_basedir=/open_basedir = /g" 2>&1)
      _INI=${_INI//\//\\\/}
      _QTP=${_U_TP//\//\\\/}
      sed -i "s/.*open_basedir =.*/${_INI}/g"                              ${_U_II}
      wait
      sed -i "s/.*error_reporting =.*/error_reporting = 1/g"               ${_U_II}
      wait
      sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_U_II}
      wait
      sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_U_II}
      wait
      sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_U_II}
      wait
      sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_U_II}
      wait
      echo > ${_U_HD}/.ctrl.php${_U_INI}.${_X_SE}.pid
      echo > ${_U_HD}/.ctrl.${_X_SE}.pid
    fi
    chattr +i ${_U_II}
  fi
}
#
# Update PHP-CLI for Drush.
php_cli_drush_update() {
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="${dscUsr}/tools/drush/${1}"
  else
    _DRUSH_FILE="${dscUsr}/tools/drush/drush.php"
  fi
  if [ "${_T_CLI_VRN}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php83\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php83/bin
  elif [ "${_T_CLI_VRN}" = "8.2" ] && [ -x "/opt/php82/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php82\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php82/bin
  elif [ "${_T_CLI_VRN}" = "8.1" ] && [ -x "/opt/php81/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php81\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php81/bin
  elif [ "${_T_CLI_VRN}" = "8.0" ] && [ -x "/opt/php80/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php80\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php80/bin
  elif [ "${_T_CLI_VRN}" = "7.4" ] && [ -x "/opt/php74/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php74\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php74/bin
  elif [ "${_T_CLI_VRN}" = "7.3" ] && [ -x "/opt/php73/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php73\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php73/bin
  elif [ "${_T_CLI_VRN}" = "7.2" ] && [ -x "/opt/php72/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php72\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php72/bin
  elif [ "${_T_CLI_VRN}" = "7.1" ] && [ -x "/opt/php71/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php71\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php71/bin
  elif [ "${_T_CLI_VRN}" = "7.0" ] && [ -x "/opt/php70/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php70\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php70/bin
  elif [ "${_T_CLI_VRN}" = "5.6" ] && [ -x "/opt/php56/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php56\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php56/bin
  else
    _T_CLI=/foo/bar
  fi
  if [ -x "${_T_CLI}/php" ]; then
    #_DRUSH_HOSTING_TASKS_CMD="/usr/bin/drush @hostmaster hosting-tasks --force"
    _DRUSH_HOSTING_DISPATCH_CMD="${_T_CLI}/php ${dscUsr}/tools/drush/drush.php @hostmaster hosting-dispatch"
    if [ -e "${dscUsr}/aegir.sh" ]; then
      rm -f ${dscUsr}/aegir.sh
    fi
    touch ${dscUsr}/aegir.sh
    echo -e "#!/bin/bash\n\nPATH=.:${_T_CLI}:/usr/sbin:/usr/bin:/sbin:/bin\n \
      \n${_DRUSH_HOSTING_DISPATCH_CMD} \
      \ntouch ${dscUsr}/${_USER}-task.done" \
      | fmt -su -w 2500 | tee -a ${dscUsr}/aegir.sh >/dev/null 2>&1
    chown ${_USER}:${usrGroup} ${dscUsr}/aegir.sh &> /dev/null
    chmod 0700 ${dscUsr}/aegir.sh &> /dev/null
  fi
  echo OK > ${dscUsr}/static/control/.ctrl.cli.${_X_SE}.pid
}

#
# Set default FPM workers.
satellite_default_fpm_workers() {
  count_cpu

  # Set _PHP_FPM_WORKERS to AUTO if it is empty
  [ -z "${_PHP_FPM_WORKERS}" ] && _PHP_FPM_WORKERS=AUTO
  # If _PHP_FPM_WORKERS is not AUTO and not empty, then check if it is less than 1
  if [ "${_PHP_FPM_WORKERS}" != "AUTO" ] && [ -n "${_PHP_FPM_WORKERS}" ]; then
    if [ "${_PHP_FPM_WORKERS}" -lt 1 ] 2>/dev/null; then
      _PHP_FPM_WORKERS=AUTO
    fi
  fi
  # If _PHP_FPM_WORKERS is not AUTO, remove non-numeric characters
  [ "${_PHP_FPM_WORKERS}" != "AUTO" ] && _PHP_FPM_WORKERS=${_PHP_FPM_WORKERS//[^0-9]/}

  if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
    _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
  else
    _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
  fi
  if [ -e "/root/.dev.server.cnf" ]; then
    echo "DEBUG: _L_PHP_FPM_WORKERS is ${_L_PHP_FPM_WORKERS}" >>/var/backups/ltd/log/users-${_NOW}.log
  fi

  # Set _PHP_FPM_TIMEOUT to AUTO if it is empty
  [ -z "${_PHP_FPM_TIMEOUT}" ] && _PHP_FPM_TIMEOUT=AUTO
  # If _PHP_FPM_TIMEOUT is not AUTO and not empty, then check if it is between 60 and 180
  if [ "${_PHP_FPM_TIMEOUT}" != "AUTO" ] && [ -n "${_PHP_FPM_TIMEOUT}" ]; then
    # If _PHP_FPM_TIMEOUT is not AUTO and not empty, remove non-numeric characters
    [ "${_PHP_FPM_TIMEOUT}" != "AUTO" ] && _PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT//[^0-9]/}
    # If _PHP_FPM_TIMEOUT is outside of the allowed range, use either min or max allowed
    if [ "${_PHP_FPM_TIMEOUT}" -lt 60 ]; then
      _PHP_FPM_TIMEOUT=60
    elif [ "${_PHP_FPM_TIMEOUT}" -gt 180 ]; then
      _PHP_FPM_TIMEOUT=180
    fi
  fi

  if [ -e "/root/.dev.server.cnf" ]; then
    echo "DEBUG: _PHP_FPM_TIMEOUT is ${_PHP_FPM_TIMEOUT}" >>/var/backups/ltd/log/users-${_NOW}.log
  fi
}

#
# Tune FPM workers.
satellite_tune_fpm_workers() {
  satellite_default_fpm_workers

  _LIM_FPM="${_L_PHP_FPM_WORKERS}"

  if [ ! -z "${_CLIENT_OPTION}" ]; then
    if [ "${_CLIENT_OPTION}" = "CLUSTER" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=96
      fi
    elif [ "${_CLIENT_OPTION}" = "LITE" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=32
      fi
    elif [ "${_CLIENT_OPTION}" = "PHANTOM" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=16
      fi
    elif [ "${_CLIENT_OPTION}" = "POWER" ] \
      || [ "${_CLIENT_OPTION}" = "BUS" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=8
      fi
    elif [ "${_CLIENT_OPTION}" = "EDGE" ] \
      || [ "${_CLIENT_OPTION}" = "SSD" ] \
      || [ "${_CLIENT_OPTION}" = "CLASSIC" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=2
      fi
    elif [ "${_CLIENT_OPTION}" = "MINI" ] \
      || [ "${_CLIENT_OPTION}" = "MICRO" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=1
      fi
    else
      _LIM_FPM=2
    fi
  fi

  if [ ! -z "${_CLIENT_CORES}" ] && [ "${_CLIENT_CORES}" -ge "1" ]; then
    if [ -e "${dscUsr}/log/cores.txt" ]; then
      _CLIENT_CORES=$(cat ${dscUsr}/log/cores.txt 2>&1)
      _CLIENT_CORES=$(echo -n ${_CLIENT_CORES} | tr -d "\n" 2>&1)
    fi
    _CLIENT_CORES=${_CLIENT_CORES//[^0-9]/}
    if [ ! -z "${_CLIENT_CORES}" ] && [ "${_CLIENT_CORES}" -ge "1" ]; then
      _LIM_FPM=$(( _LIM_FPM *= _CLIENT_CORES ))
    fi
  fi

  if [ "${_LIM_FPM}" -gt "100" ]; then
    _LIM_FPM=100
  fi

  _CHILD_MAX_FPM=$(( _LIM_FPM * 2 ))

  if [ -e "/root/.dev.server.cnf" ]; then
    echo "DEBUG: _LIM_FPM is ${_LIM_FPM}" >>/var/backups/ltd/log/users-${_NOW}.log
    echo "DEBUG: _PHP_FPM_WORKERS is ${_PHP_FPM_WORKERS}" >>/var/backups/ltd/log/users-${_NOW}.log
    echo "DEBUG: _CHILD_MAX_FPM is ${_CHILD_MAX_FPM}" >>/var/backups/ltd/log/users-${_NOW}.log
  fi
}

#
# Disable New Relic per Octopus instance.
disable_newrelic() {
  _THIS_POOL_TPL="/opt/php$1/etc/pool.d/$2.conf"
  if [ -e "${_THIS_POOL_TPL}" ]; then
    _CHECK_NEW_RELIC_KEY=$(grep "newrelic.enabled.*true" ${_THIS_POOL_TPL} 2>&1)
    if [[ "${_CHECK_NEW_RELIC_KEY}" =~ "newrelic.enabled" ]]; then
      echo "New Relic for $2 will be disabled because newrelic.info does not exist"
      sed -i "s/^php_admin_value\[newrelic.license\].*/php_admin_value\[newrelic.license\] = \"\"/g" ${_THIS_POOL_TPL}
      wait
      sed -i "s/^php_admin_value\[newrelic.enabled\].*/php_admin_value\[newrelic.enabled\] = \"false\"/g" ${_THIS_POOL_TPL}
      wait
      if [ "$3" = "1" ] && [ -e "/etc/init.d/php$1-fpm" ]; then
        service php$1-fpm reload &> /dev/null
      fi
    fi
  fi
}
#
# Enable New Relic per Octopus instance.
enable_newrelic() {
  _LOC_NEW_RELIC_KEY=$(cat ${dscUsr}/static/control/newrelic.info 2>&1)
  _LOC_NEW_RELIC_KEY=${_LOC_NEW_RELIC_KEY//[^0-9a-zA-Z]/}
  _LOC_NEW_RELIC_KEY=$(echo -n ${_LOC_NEW_RELIC_KEY} | tr -d "\n" 2>&1)
  if [ -z "${_LOC_NEW_RELIC_KEY}" ]; then
    disable_newrelic $1 $2 $3
  else
    _THIS_POOL_TPL="/opt/php$1/etc/pool.d/$2.conf"
    if [ -e "${_THIS_POOL_TPL}" ]; then
      _CHECK_NEW_RELIC_TPL=$(grep "newrelic.license" ${_THIS_POOL_TPL} 2>&1)
      _CHECK_NEW_RELIC_KEY=$(grep "${_LOC_NEW_RELIC_KEY}" ${_THIS_POOL_TPL} 2>&1)
      if [[ "${_CHECK_NEW_RELIC_KEY}" =~ "${_LOC_NEW_RELIC_KEY}" ]]; then
        echo "New Relic integration is already active for $2"
      else
        if [[ "${_CHECK_NEW_RELIC_TPL}" =~ "newrelic.license" ]]; then
          echo "New Relic for $2 update with key ${_LOC_NEW_RELIC_KEY} in php$1"
          sed -i "s/^php_admin_value\[newrelic.license\].*/php_admin_value\[newrelic.license\] = \"${_LOC_NEW_RELIC_KEY}\"/g" ${_THIS_POOL_TPL}
          wait
          sed -i "s/^php_admin_value\[newrelic.enabled\].*/php_admin_value\[newrelic.enabled\] = \"true\"/g" ${_THIS_POOL_TPL}
          wait
        else
          echo "New Relic for $2 setup with key ${_LOC_NEW_RELIC_KEY} in php$1"
          echo "php_admin_value[newrelic.license] = \"${_LOC_NEW_RELIC_KEY}\"" >> ${_THIS_POOL_TPL}
          echo "php_admin_value[newrelic.enabled] = \"true\"" >> ${_THIS_POOL_TPL}
        fi
        if [ "$3" = "1" ] && [ -e "/etc/init.d/php$1-fpm" ]; then
          service php$1-fpm reload &> /dev/null
        fi
      fi
    fi
  fi
}
#
# Switch New Relic on or off per Octopus instance.
switch_newrelic() {
  isPhp="$1"
  isPhp=${isPhp//[^0-9]/}
  isUsr="$2"
  isUsr=${isUsr//[^a-z0-9]/}
  isRld="$3"
  isRld=${isRld//[^0-1]/}
  if [ ! -z "${isPhp}" ] && [ ! -z "${isUsr}" ] && [ ! -z "${isRld}" ]; then
    if [ -e "${dscUsr}/static/control/newrelic.info" ]; then
      enable_newrelic $1 $2 $3
    else
      disable_newrelic $1 $2 $3
    fi
  fi
}
#
# Update web user.
satellite_web_user_update() {
  isTest="${_WEB}"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
    _T_HD="/home/${_WEB}/.drush"
    _T_TP="/home/${_WEB}/.tmp"
    _T_TS="/home/${_WEB}/.aws"
    _T_II="${_T_HD}/php.ini"
    if [ -d "/home/${_WEB}" ] && [ ! -e "/home/${_WEB}/.lock" ]; then
      chattr -i /home/${_WEB}
      if [ -d "/home/${_WEB}/.drush" ]; then
        chattr -i /home/${_WEB}/.drush
      fi
      if [ -e "${_T_II}" ]; then
        chattr -i ${_T_II}
      fi
      mkdir -p /home/${_WEB}/.{tmp,drush,aws}
      touch /home/${_WEB}/.lock
      isTest="$1"
      isTest=${isTest//[^a-z0-9]/}
      if [ ! -z "${isTest}" ]; then
        if [ "$1" = "hhvm" ]; then
          if [ -e "/opt/php56/etc/php56.ini" ] \
            && [ -x "/opt/php56/bin/php" ]; then
            _T_PV=56
          fi
        else
          _T_PV=$1
        fi
      fi
      if [ ! -z "${_T_PV}" ] && [ -e "/opt/php${_T_PV}/etc/php${_T_PV}.ini" ]; then
        cp -af /opt/php${_T_PV}/etc/php${_T_PV}.ini ${_T_II}
      else
        if [ -e "/opt/php83/etc/php83.ini" ]; then
          cp -af /opt/php83/etc/php83.ini ${_T_II}
          _T_PV=83
        elif [ -e "/opt/php82/etc/php82.ini" ]; then
          cp -af /opt/php82/etc/php82.ini ${_T_II}
          _T_PV=82
        elif [ -e "/opt/php81/etc/php81.ini" ]; then
          cp -af /opt/php81/etc/php81.ini ${_T_II}
          _T_PV=81
        elif [ -e "/opt/php80/etc/php80.ini" ]; then
          cp -af /opt/php80/etc/php80.ini ${_T_II}
          _T_PV=80
        elif [ -e "/opt/php74/etc/php74.ini" ]; then
          cp -af /opt/php74/etc/php74.ini ${_T_II}
          _T_PV=74
        elif [ -e "/opt/php73/etc/php73.ini" ]; then
          cp -af /opt/php73/etc/php73.ini ${_T_II}
          _T_PV=73
        elif [ -e "/opt/php72/etc/php72.ini" ]; then
          cp -af /opt/php72/etc/php72.ini ${_T_II}
          _T_PV=72
        elif [ -e "/opt/php71/etc/php71.ini" ]; then
          cp -af /opt/php71/etc/php71.ini ${_T_II}
          _T_PV=71
        elif [ -e "/opt/php70/etc/php70.ini" ]; then
          cp -af /opt/php70/etc/php70.ini ${_T_II}
          _T_PV=70
        elif [ -e "/opt/php56/etc/php56.ini" ]; then
          cp -af /opt/php56/etc/php56.ini ${_T_II}
          _T_PV=56
        fi
      fi
      if [ -e "${_T_II}" ]; then
        _INI="open_basedir = \".: \
          /data/all:      \
          /data/conf:     \
          /data/disk/all: \
          /mnt:           \
          /opt/php56:     \
          /opt/php70:     \
          /opt/php71:     \
          /opt/php72:     \
          /opt/php73:     \
          /opt/php74:     \
          /opt/php80:     \
          /opt/php81:     \
          /opt/php82:     \
          /opt/php83:     \
          /opt/tika:      \
          /opt/tika7:     \
          /opt/tika8:     \
          /opt/tika9:     \
          /dev/urandom:   \
          /srv:           \
          /usr/bin:       \
          /usr/local/bin: \
          /var/second/${_USER}:     \
          ${dscUsr}/aegir:          \
          ${dscUsr}/backup-exports: \
          ${dscUsr}/distro:         \
          ${dscUsr}/platforms:      \
          ${dscUsr}/static:         \
          ${_T_HD}:                 \
          ${_T_TP}:                 \
          ${_T_TS}\""
        _INI=$(echo "${_INI}" | sed "s/ //g" 2>&1)
        _INI=$(echo "${_INI}" | sed "s/open_basedir=/open_basedir = /g" 2>&1)
        _INI=${_INI//\//\\\/}
        _QTP=${_T_TP//\//\\\/}
        sed -i "s/.*open_basedir =.*/${_INI}/g"                              ${_T_II}
        wait
        sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_T_II}
        wait
        sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_T_II}
        wait
        sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_T_II}
        wait
        sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_T_II}
        wait
        if [ "$1" = "hhvm" ]; then
          sed -i "s/.*ioncube.*//g" ${_T_II}
          wait
          sed -i "s/.*opcache.*//g" ${_T_II}
          wait
        fi
        rm -f ${_T_HD}/.ctrl.php*
        echo > ${_T_HD}/.ctrl.php${_T_PV}.${_X_SE}.pid
      fi
      chmod 700 /home/${_WEB}
      chown -R ${_WEB}:${_WEBG} /home/${_WEB}
      chmod 550 /home/${_WEB}/.drush
      chmod 440 /home/${_WEB}/.drush/php.ini
      rm -f /home/${_WEB}/.lock
      if [ -d "/home/${_WEB}" ]; then
        chattr +i /home/${_WEB}
      fi
      if [ -d "/home/${_WEB}/.drush" ]; then
        chattr +i /home/${_WEB}/.drush
      fi
      if [ -e "${_T_II}" ]; then
        chattr +i ${_T_II}
      fi
    fi
  fi
}
#
# Remove web user.
satellite_remove_web_user() {
  isTest="${_WEB}"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
    if [ -d "/home/${_WEB}/" ] || [ "$1" = "clean" ]; then
      chattr -i /home/${_WEB}/
      if [ -d "/home/${_WEB}/.drush/" ]; then
        chattr -i /home/${_WEB}/.drush/
      fi
      kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
      deluser \
        --remove-home \
        --backup-to /var/backups/zombie/deleted ${_WEB} &> /dev/null
      if [ -d "/home/${_WEB}/" ]; then
        rm -rf /home/${_WEB}/ &> /dev/null
      fi
    fi
  fi
}
#
# Add web user.
satellite_create_web_user() {
  isTest="${_WEB}"
  isTest=${isTest//[^a-z0-9]/}
  if [ ! -z "${isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
    _T_HD="/home/${_WEB}/.drush"
    _T_II="${_T_HD}/php.ini"
    _T_ID_EXISTS=$(getent passwd ${_WEB} 2>&1)
    if [ ! -z "${_T_ID_EXISTS}" ] && [ -e "${_T_II}" ]; then
      satellite_web_user_update "$1"
    elif [ -z "${_T_ID_EXISTS}" ] || [ ! -e "${_T_II}" ]; then
      satellite_remove_web_user "clean"
      adduser --force-badname --system --ingroup www-data --home /home/${_WEB} ${_WEB} &> /dev/null
      satellite_web_user_update "$1"
    fi
  fi
}
#
# Add site specific socket config include.
site_socket_inc_gen() {
  unlAeg="${dscUsr}/static/control/unlock-aegir-php.info"
  mltFpm="${dscUsr}/static/control/multi-fpm.info"
  preFpm="${dscUsr}/static/control/.prev-multi-fpm.info"
  mltNgx="${dscUsr}/static/control/.multi-nginx-fpm.pid"
  fpmPth="${dscUsr}/config/server_master/nginx/post.d"

  hmFront=$(cat ${dscUsr}/log/domain.txt 2>&1)
  hmFront=$(echo -n ${hmFront} | tr -d "\n" 2>&1)
  hmstAls="${dscUsr}/.drush/${hmFront}.alias.drushrc.php"

  hmstCli=$(cat ${dscUsr}/log/cli.txt 2>&1)
  hmstCli=$(echo -n ${hmstCli} | tr -d "\n" 2>&1)

  if [ ! -e "${hmstAls}" ]; then
    ln -s ${dscUsr}/.drush/hostmaster.alias.drushrc.php ${hmstAls}
  fi

  _PLACEHOLDER_TEST=$(grep "place.holder.dont.remove" ${mltFpm} 2>&1)

  if [ ! -e "${dscUsr}/log/no-lock-aegir-fpm.txt" ] \
    || [[ ! "${_PLACEHOLDER_TEST}" =~ "place.holder.dont.remove" ]]; then
    sed -i "s/^${hmFront} .*//g" ${mltFpm}
    wait
    sed -i "s/^place.holder.dont.remove .*//g" ${mltFpm}
    wait
    _PHP_V="83 82 81 74"
    phpFnd=NO
    for e in ${_PHP_V}; do
      if [ -x "/opt/php${e}/bin/php" ] && [ "${phpFnd}" = "NO" ]; then
        if [ "${e}" = "83" ]; then
          phpDot=8.3
        elif [ "${e}" = "82" ]; then
          phpDot=8.2
        elif [ "${e}" = "81" ]; then
          phpDot=8.1
        elif [ "${e}" = "74" ]; then
          phpDot=7.4
        fi
        echo "place.holder.dont.remove ${phpDot}" >> ${mltFpm}
        phpFnd=YES
      fi
    done
    sed -i "s/ *$//g; /^$/d" ${mltFpm}
    wait
    touch ${dscUsr}/log/no-lock-aegir-fpm.txt
    rm -f ${dscUsr}/log/locked-aegir-fpm.txt
    touch ${dscUsr}/log/unlocked-aegir-fpm.txt
    mltFpmUpdateForce=YES
  fi

  if [ -x "/opt/php83/bin/php" ] && [ ! -e "/home/${_USER}.83.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    mltFpmUpdateForce=YES
  elif [ -x "/opt/php82/bin/php" ] && [ ! -e "/home/${_USER}.82.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    mltFpmUpdateForce=YES
  elif [ -x "/opt/php81/bin/php" ] && [ ! -e "/home/${_USER}.81.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    mltFpmUpdateForce=YES
  fi

  if [ -f "${mltFpm}" ]; then
    chown ${_USER}.ftp:${usrGroup} ${dscUsr}/static/control/*.info
    mltFpmUpdate=NO
    if [ ! -f "${preFpm}" ]; then
      rm -rf ${preFpm}
      cp -af ${mltFpm} ${preFpm}
    fi
    diffFpmTest=$(diff -w -B ${mltFpm} ${preFpm} 2>&1)
    if [ ! -z "${diffFpmTest}" ]; then
      mltFpmUpdate=YES
    fi
    if [ ! -f "${mltNgx}" ] \
      || [ "${mltFpmUpdate}" = "YES" ] \
      || [ "${mltFpmUpdateForce}" = "YES" ]; then
      rm -f ${fpmPth}/fpm_include_site_*
      IFS=$'\12'
      for p in `cat ${mltFpm}`;do
        _SITE_NAME=`echo $p | cut -d' ' -f1 | awk '{ print $1}'`
        _SITE_NAME=${_SITE_NAME//[^a-zA-Z0-9-.]/}
        _SITE_NAME=$(echo -n ${_SITE_NAME} | tr A-Z a-z 2>&1)
        _SITE_NAME=$(echo -n ${_SITE_NAME} | tr -d "\n" 2>&1)
        _SITE_SOCKET=`echo $p | cut -d' ' -f2 | awk '{ print $1}'`
        _SITE_SOCKET=${_SITE_SOCKET//[^0-9]/}
        _SITE_SOCKET=$(echo -n ${_SITE_SOCKET} | tr -d "\n" 2>&1)
        _SOCKET_L_NAME="${_USER}.${_SITE_SOCKET}"
        if [ ! -z "${_SITE_NAME}" ] \
          && [ ! -z "${_SITE_SOCKET}" ] \
          && [ -e "${dscUsr}/.drush/${_SITE_NAME}.alias.drushrc.php" ] \
          && [ -e "/run/${_SOCKET_L_NAME}.fpm.socket" ]; then
          fpmInc="${fpmPth}/fpm_include_site_${_SITE_NAME}.inc"
          echo "if ( \$main_site_name = ${_SITE_NAME} ) {" > ${fpmInc}
          echo "  set \$user_socket \"${_SOCKET_L_NAME}\";" >> ${fpmInc}
          echo "}" >> ${fpmInc}
        fi
      done
      touch ${mltNgx}
      rm -rf ${preFpm}
      cp -af ${mltFpm} ${preFpm}
      ### reload nginx
      service nginx reload &> /dev/null
    fi
  else
    if [ -f "${mltNgx}" ]; then
      rm -f ${mltNgx}
    fi
    if [ -f "${preFpm}" ]; then
      rm -f ${preFpm}
    fi
  fi
}
#
# Switch PHP Version.
switch_php() {
  _PHP_CLI_UPDATE=NO
  _FORCE_FPM_SETUP=NO
  _NEW_FPM_SETUP=NO
  _T_CLI_VRN=""
  if [ -e "${dscUsr}/static/control/fpm.info" ] \
    || [ -e "${dscUsr}/static/control/cli.info" ] \
    || [ -e "${dscUsr}/static/control/hhvm.info" ]; then
    echo "Custom FPM, HHVM or CLI settings for ${_USER} exist, running switch_php checks"
    if [ ! -e "${dscUsr}/log/un-chattr-ctrl.info" ]; then
      chattr -i ${dscUsr}/static/control/fpm.info &> /dev/null
      chattr -i ${dscUsr}/static/control/cli.info &> /dev/null
      chattr -i ${dscUsr}/log/fpm.txt &> /dev/null
      chattr -i ${dscUsr}/log/cli.txt &> /dev/null
      chattr -i ${dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc &> /dev/null
      touch ${dscUsr}/log/un-chattr-ctrl.info
    fi
    if [ ! -e "${dscUsr}/static/control/.single-fpm.${_X_SE}.pid" ]; then
      rm -f ${dscUsr}/static/control/.single-fpm*.pid
      echo OK > ${dscUsr}/static/control/.single-fpm.${_X_SE}.pid
      _FORCE_FPM_SETUP=YES
    fi
    if [ -e "${dscUsr}/static/control/cli.info" ]; then
      _T_CLI_VRN=$(cat ${dscUsr}/static/control/cli.info 2>&1)
      _T_CLI_VRN=${_T_CLI_VRN//[^0-9.]/}
      _T_CLI_VRN=$(echo -n ${_T_CLI_VRN} | tr -d "\n" 2>&1)
      if [ "${_T_CLI_VRN}" = "83" ]; then
        _T_CLI_VRN=8.3
      elif [ "${_T_CLI_VRN}" = "82" ]; then
        _T_CLI_VRN=8.2
      elif [ "${_T_CLI_VRN}" = "81" ]; then
        _T_CLI_VRN=8.1
      elif [ "${_T_CLI_VRN}" = "80" ]; then
        _T_CLI_VRN=8.0
      elif [ "${_T_CLI_VRN}" = "74" ]; then
        _T_CLI_VRN=7.4
      elif [ "${_T_CLI_VRN}" = "73" ]; then
        _T_CLI_VRN=7.3
      elif [ "${_T_CLI_VRN}" = "72" ]; then
        _T_CLI_VRN=7.2
      elif [ "${_T_CLI_VRN}" = "71" ]; then
        _T_CLI_VRN=7.1
      elif [ "${_T_CLI_VRN}" = "70" ]; then
        _T_CLI_VRN=7.0
      elif [ "${_T_CLI_VRN}" = "56" ]; then
        _T_CLI_VRN=5.6
      fi
      if [ "${_T_CLI_VRN}" = "8.3" ] \
        || [ "${_T_CLI_VRN}" = "8.2" ] \
        || [ "${_T_CLI_VRN}" = "8.1" ] \
        || [ "${_T_CLI_VRN}" = "8.0" ] \
        || [ "${_T_CLI_VRN}" = "7.4" ] \
        || [ "${_T_CLI_VRN}" = "7.3" ] \
        || [ "${_T_CLI_VRN}" = "7.2" ] \
        || [ "${_T_CLI_VRN}" = "7.1" ] \
        || [ "${_T_CLI_VRN}" = "7.0" ] \
        || [ "${_T_CLI_VRN}" = "5.6" ]; then
        if [ "${_T_CLI_VRN}" = "8.3" ] \
          && [ ! -x "/opt/php83/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _T_CLI_VRN=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _T_CLI_VRN=8.1
          fi
        elif [ "${_T_CLI_VRN}" = "8.2" ] \
          && [ ! -x "/opt/php82/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _T_CLI_VRN=8.1
          elif [ -x "/opt/php83/bin/php" ]; then
            _T_CLI_VRN=8.3
          fi
        elif [ "${_T_CLI_VRN}" = "8.1" ] \
          && [ ! -x "/opt/php81/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _T_CLI_VRN=8.2
          elif [ -x "/opt/php83/bin/php" ]; then
            _T_CLI_VRN=8.3
          fi
        elif [ "${_T_CLI_VRN}" = "8.0" ] \
          && [ ! -x "/opt/php80/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _T_CLI_VRN=8.1
          fi
        elif [ "${_T_CLI_VRN}" = "7.4" ] \
          && [ ! -x "/opt/php74/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _T_CLI_VRN=8.1
          fi
        elif [ "${_T_CLI_VRN}" = "7.3" ] \
          && [ ! -x "/opt/php73/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_CLI_VRN=7.4
          fi
        elif [ "${_T_CLI_VRN}" = "7.2" ] \
          && [ ! -x "/opt/php72/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_CLI_VRN=7.4
          fi
        elif [ "${_T_CLI_VRN}" = "7.1" ] \
          && [ ! -x "/opt/php71/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_CLI_VRN=7.4
          fi
        elif [ "${_T_CLI_VRN}" = "7.0" ] \
          && [ ! -x "/opt/php70/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_CLI_VRN=7.4
          fi
        elif [ "${_T_CLI_VRN}" = "5.6" ] \
          && [ ! -x "/opt/php56/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_CLI_VRN=7.4
          fi
        fi
        if [ "${_T_CLI_VRN}" != "${_PHP_CLI_VERSION}" ] \
          || [ ! -e "${dscUsr}/static/control/.ctrl.cli.${_X_SE}.pid" ]; then
          _PHP_CLI_UPDATE=YES
          _DRUSH_FILES="drush.php drush"
          for df in ${_DRUSH_FILES}; do
            php_cli_drush_update "${df}"
          done
          if [ -x "${_T_CLI}/php" ]; then
            php_cli_local_ini_update
            sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_T_CLI_VRN}/g" \
              /root/.${_USER}.octopus.cnf &> /dev/null
            wait
            echo ${_T_CLI_VRN} > ${dscUsr}/log/cli.txt
            echo ${_T_CLI_VRN} > ${dscUsr}/static/control/cli.info
            chown ${_USER}.ftp:${usrGroup} ${dscUsr}/static/control/cli.info
          fi
        fi
      fi
    fi
    if [ -e "${dscUsr}/static/control/hhvm.info" ]; then
      if [ -x "/usr/bin/hhvm" ] \
        && [ -e "/var/xdrago/conf/hhvm/init.d/hhvm.foo" ] \
        && [ -e "/var/xdrago/conf/hhvm/server.foo.ini" ]; then
        if [ ! -e "/opt/hhvm/server.${_USER}.ini" ] \
          || [ ! -e "/etc/init.d/hhvm.${_USER}" ] \
          || [ ! -e "/run/hhvm/${_USER}" ]  ; then
          ### create or update special system user if needed
          satellite_create_web_user "hhvm"
          ### configure custom hhvm server init.d script
          cp -af /var/xdrago/conf/hhvm/init.d/hhvm.foo /etc/init.d/hhvm.${_USER}
          sed -i "s/foo/${_USER}/g" /etc/init.d/hhvm.${_USER} &> /dev/null
          wait
          sed -i "s/.ftp/.web/g" /etc/init.d/hhvm.${_USER} &> /dev/null
          wait
          chmod 755 /etc/init.d/hhvm.${_USER}
          chown root:root /etc/init.d/hhvm.${_USER}
          update-rc.d hhvm.${_USER} defaults &> /dev/null
          ### configure custom hhvm server ini file
          mkdir -p /opt/hhvm
          cp -af /var/xdrago/conf/hhvm/server.foo.ini /opt/hhvm/server.${_USER}.ini
          sed -i "s/foo/${_USER}/g" /opt/hhvm/server.${_USER}.ini &> /dev/null
          wait
          sed -i "s/.ftp/.web/g" /opt/hhvm/server.${_USER}.ini &> /dev/null
          wait
          chmod 755 /opt/hhvm/server.${_USER}.ini
          chown root:root /opt/hhvm/server.${_USER}.ini
          mkdir -p /var/log/hhvm/${_USER}
          chown ${_WEB}:${_WEBG} /var/log/hhvm/${_USER}
          ### start custom hhvm server
          service hhvm.${_USER} start &> /dev/null
          ### remove fpm control file to avoid confusion
          rm -f ${dscUsr}/static/control/fpm.info
          ### update nginx configuration
          sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/g" \
            ${dscUsr}/config/includes/nginx_vhost_common.conf
          wait
          sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/g" \
            ${dscUsr}/.drush/sys/provision/http/Provision/Config/Nginx/Inc/vhost_include.tpl.php
          wait
          ### reload nginx
          service nginx reload &> /dev/null
        fi
      fi
    else
      if [ -e "/opt/hhvm/server.${_USER}.ini" ] \
        || [ -e "/etc/init.d/hhvm.${_USER}" ] \
        || [ -e "/run/hhvm/${_USER}" ]  ; then
        ### disable no longer used custom hhvm server instance
        if [ -e "/etc/init.d/hhvm.${_USER}" ]; then
          service hhvm.${_USER} stop &> /dev/null
          update-rc.d -f hhvm.${_USER} remove &> /dev/null
          rm -f /etc/init.d/hhvm.${_USER}
        fi
        ### delete special system user no longer needed
        satellite_remove_web_user "hhvm"
        ### delete leftovers
        rm -f /opt/hhvm/server.${_USER}.ini
        rm -rf /run/hhvm/${_USER}
        rm -rf /var/log/hhvm/${_USER}
        ### update nginx configuration
        sed -i "s/\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/\/var\/run\/\$user_socket.fpm.socket;/g" \
          ${dscUsr}/config/includes/nginx_vhost_common.conf
        wait
        sed -i "s/\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/\/var\/run\/\$user_socket.fpm.socket;/g" \
          ${dscUsr}/.drush/sys/provision/http/Provision/Config/Nginx/Inc/vhost_include.tpl.php
        wait
        ### reload nginx
        service nginx reload &> /dev/null
        ### create dummy control file to enable PHP-FPM again
        echo 7.4 > ${dscUsr}/static/control/fpm.info
        chown ${_USER}.ftp:${usrGroup} ${dscUsr}/static/control/fpm.info
        _FORCE_FPM_SETUP=YES
      fi
    fi
    sleep 5
    if [ ! -e "${dscUsr}/static/control/hhvm.info" ] \
      && [ -e "${dscUsr}/static/control/fpm.info" ] \
      && [ -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
      _PHP_FPM_MULTI=NO
      if [ -f "${dscUsr}/static/control/multi-fpm.info" ] \
        && [ -d "${dscUsr}/tools/le" ]; then
        _PHP_FPM_MULTI=YES
        if [ ! -e "${dscUsr}/static/control/.multi-fpm.${_X_SE}.pid" ]; then
          rm -f ${dscUsr}/static/control/.multi-fpm*.pid
          echo OK > ${dscUsr}/static/control/.multi-fpm.${_X_SE}.pid
          _FORCE_FPM_SETUP=YES
        fi
      else
        if [ -e "${dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc" ]; then
          rm -f ${dscUsr}/config/server_master/nginx/post.d/fpm_include_*
          rm -f ${dscUsr}/static/control/.multi-fpm*.pid
          service nginx reload &> /dev/null
        fi
      fi
      _T_FPM_VRN=$(cat ${dscUsr}/static/control/fpm.info 2>&1)
      _T_FPM_VRN=${_T_FPM_VRN//[^0-9.]/}
      _T_FPM_VRN=$(echo -n ${_T_FPM_VRN} | tr -d "\n" 2>&1)
      if [ "${_T_FPM_VRN}" = "83" ]; then
        _T_FPM_VRN=8.3
      elif [ "${_T_FPM_VRN}" = "82" ]; then
        _T_FPM_VRN=8.2
      elif [ "${_T_FPM_VRN}" = "81" ]; then
        _T_FPM_VRN=8.1
      elif [ "${_T_FPM_VRN}" = "80" ]; then
        _T_FPM_VRN=8.0
      elif [ "${_T_FPM_VRN}" = "74" ]; then
        _T_FPM_VRN=7.4
      elif [ "${_T_FPM_VRN}" = "73" ]; then
        _T_FPM_VRN=7.3
      elif [ "${_T_FPM_VRN}" = "72" ]; then
        _T_FPM_VRN=7.2
      elif [ "${_T_FPM_VRN}" = "71" ]; then
        _T_FPM_VRN=7.1
      elif [ "${_T_FPM_VRN}" = "70" ]; then
        _T_FPM_VRN=7.0
      elif [ "${_T_FPM_VRN}" = "56" ]; then
        _T_FPM_VRN=5.6
      fi
      if [ "${_T_FPM_VRN}" = "8.3" ] \
        || [ "${_T_FPM_VRN}" = "8.2" ] \
        || [ "${_T_FPM_VRN}" = "8.1" ] \
        || [ "${_T_FPM_VRN}" = "8.0" ] \
        || [ "${_T_FPM_VRN}" = "7.4" ] \
        || [ "${_T_FPM_VRN}" = "7.3" ] \
        || [ "${_T_FPM_VRN}" = "7.2" ] \
        || [ "${_T_FPM_VRN}" = "7.1" ] \
        || [ "${_T_FPM_VRN}" = "7.0" ] \
        || [ "${_T_FPM_VRN}" = "5.6" ]; then
        if [ "${_T_FPM_VRN}" = "8.3" ] \
          && [ ! -x "/opt/php83/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _T_FPM_VRN=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _T_FPM_VRN=8.1
          fi
        elif [ "${_T_FPM_VRN}" = "8.2" ] \
          && [ ! -x "/opt/php82/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _T_FPM_VRN=8.1
          elif [ -x "/opt/php83/bin/php" ]; then
            _T_FPM_VRN=8.3
          fi
        elif [ "${_T_FPM_VRN}" = "8.1" ] \
          && [ ! -x "/opt/php81/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _T_FPM_VRN=8.2
          elif [ -x "/opt/php83/bin/php" ]; then
            _T_FPM_VRN=8.3
          fi
        elif [ "${_T_FPM_VRN}" = "8.0" ] \
          && [ ! -x "/opt/php80/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _T_FPM_VRN=8.1
          fi
        elif [ "${_T_FPM_VRN}" = "7.4" ] \
          && [ ! -x "/opt/php74/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _T_FPM_VRN=8.1
          fi
        elif [ "${_T_FPM_VRN}" = "7.3" ] \
          && [ ! -x "/opt/php73/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_FPM_VRN=7.4
          fi
        elif [ "${_T_FPM_VRN}" = "7.2" ] \
          && [ ! -x "/opt/php72/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_FPM_VRN=7.4
          fi
        elif [ "${_T_FPM_VRN}" = "7.1" ] \
          && [ ! -x "/opt/php71/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_FPM_VRN=7.4
          fi
        elif [ "${_T_FPM_VRN}" = "7.0" ] \
          && [ ! -x "/opt/php70/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_FPM_VRN=7.4
          fi
        elif [ "${_T_FPM_VRN}" = "5.6" ] \
          && [ ! -x "/opt/php56/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _T_FPM_VRN=7.4
          fi
        fi
        if [ "${_T_FPM_VRN}" != "${_PHP_FPM_VERSION}" ] \
          || [ "${_FORCE_FPM_SETUP}" = "YES" ]; then
          _NEW_FPM_SETUP=YES
        fi
        ### update fpm_include_default.inc if needed
        _PHP_SV=${_T_FPM_VRN//[^0-9]/}
        if [ -z "${_PHP_SV}" ]; then
          _PHP_SV=74
        fi
        _FMP_D_INC="${dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc"
        if [ "${_PHP_FPM_MULTI}" = "YES" ] \
          && [ -d "${dscUsr}/tools/le" ]; then
          _PHP_M_V="83 82 81 80 74 73 72 71 70 56"
          _D_POOL="${_USER}.${_PHP_SV}"
          if [ ! -e "${_FMP_D_INC}" ]; then
            echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
            touch ${dscUsr}/static/control/.multi-fpm.${_X_SE}.pid
            _NEW_FPM_SETUP=YES
          else
            _CHECK_FMP_D=$(grep "${_D_POOL}" ${_FMP_D_INC} 2>&1)
            if [[ "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]]; then
              echo "${_D_POOL} already set in ${_FMP_D_INC}"
            else
              echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
              echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
              touch ${dscUsr}/static/control/.multi-fpm.${_X_SE}.pid
              _NEW_FPM_SETUP=YES
            fi
          fi
        else
          _PHP_M_V="${_PHP_SV}"
          rm -f ${dscUsr}/static/control/.multi-fpm*.pid
          rm -f ${_FMP_D_INC}
        fi
        if [ ! -z "${_T_FPM_VRN}" ] \
          && [ "${_NEW_FPM_SETUP}" = "YES" ]; then
          satellite_tune_fpm_workers
          sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_T_FPM_VRN}/g" \
            /root/.${_USER}.octopus.cnf &> /dev/null
          wait
          echo ${_T_FPM_VRN} > ${dscUsr}/log/fpm.txt
          if [ "${_PHP_FPM_MULTI}" = "NO" ]; then
            echo ${_T_FPM_VRN} > ${dscUsr}/static/control/fpm.info
          fi
          chown ${_USER}.ftp:${usrGroup} ${dscUsr}/static/control/fpm.info
          _PHP_OLD_SV=${_PHP_FPM_VERSION//[^0-9]/}
          _PHP_SV=${_T_FPM_VRN//[^0-9]/}
          if [ -z "${_PHP_SV}" ]; then
            _PHP_SV=74
          fi
          ### create or update special system user if needed
          _FMP_D_INC="${dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc"
          if [ "${_PHP_FPM_MULTI}" = "YES" ] \
            && [ -d "${dscUsr}/tools/le" ]; then
            _PHP_M_V="83 82 81 80 74 73 72 71 70 56"
            _D_POOL="${_USER}.${_PHP_SV}"
            if [ ! -e "${_FMP_D_INC}" ]; then
              echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
              touch ${dscUsr}/static/control/.multi-fpm.${_X_SE}.pid
            else
              _CHECK_FMP_D=$(grep "${_D_POOL}" ${_FMP_D_INC} 2>&1)
              if [[ "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]]; then
                echo "${_D_POOL} already set in ${_FMP_D_INC}"
              else
                echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
                echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
                touch ${dscUsr}/static/control/.multi-fpm.${_X_SE}.pid
              fi
            fi
          else
            _PHP_M_V="${_PHP_SV}"
            rm -f ${dscUsr}/static/control/.multi-fpm*.pid
            rm -f ${_FMP_D_INC}
          fi
          for m in ${_PHP_M_V}; do
            if [ -x "/opt/php${m}/bin/php" ]; then
              if [ "${_PHP_FPM_MULTI}" = "YES" ] \
                && [ -d "${dscUsr}/tools/le" ]; then
                _WEB="${_USER}.${m}.web"
                _POOL="${_USER}.${m}"
              else
                _WEB="${_USER}.web"
                _POOL="${_USER}"
              fi
              if [ -e "/home/${_WEB}/.drush/php.ini" ]; then
                _OLD_PHP_IN_USE=$(grep "/lib/php" /home/${_WEB}/.drush/php.ini 2>&1)
                _PHP_V="83 82 81 80 74 73 72 71 70 56"
                for e in ${_PHP_V}; do
                  if [[ "${_OLD_PHP_IN_USE}" =~ "php${e}" ]]; then
                    if [ "${e}" != "${m}" ] \
                      || [ ! -e "/home/${_WEB}/.drush/.ctrl.php${m}.${_X_SE}.pid" ]; then
                      echo _OLD_PHP_IN_USE is ${_OLD_PHP_IN_USE} for ${_WEB} update
                      echo _NEW_PHP_TO_USE is ${m} for ${_WEB} update
                      satellite_web_user_update "${m}"
                    fi
                  fi
                done
              else
                echo _NEW_PHP_TO_USE is ${m} for ${_WEB} create
                satellite_create_web_user "${m}"
              fi
            fi
          done
          ### create or update special system user if needed
          if [ "${_PHP_FPM_MULTI}" = "YES" ] \
            && [ -d "${dscUsr}/tools/le" ]; then
            _PHP_M_V="83 82 81 80 74 73 72 71 70 56"
            rm -f /opt/php*/etc/pool.d/${_USER}.conf
          else
            _PHP_M_V="${_PHP_SV}"
            rm -f /opt/php*/etc/pool.d/${_USER}.*.conf
            rm -f /opt/php*/etc/pool.d/${_USER}.conf
          fi
          for m in ${_PHP_M_V}; do
            if [ -x "/opt/php${m}/bin/php" ]; then
              if [ "${_PHP_FPM_MULTI}" = "YES" ] \
                && [ -d "${dscUsr}/tools/le" ]; then
                _WEB="${_USER}.${m}.web"
                _POOL="${_USER}.${m}"
              else
                _WEB="${_USER}.web"
                _POOL="${_USER}"
              fi
              if [ "${_PHP_FPM_MULTI}" = "YES" ] \
                && [ -d "${dscUsr}/tools/le" ]; then
                cp -af /var/xdrago/conf/fpm-pool-foo-multi.conf \
                  /opt/php${m}/etc/pool.d/${_POOL}.conf
              else
                cp -af /var/xdrago/conf/fpm-pool-foo.conf \
                  /opt/php${m}/etc/pool.d/${_POOL}.conf
              fi
              sed -i "s/.ftp/.web/g" \
                /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
              sed -i "s/\/data\/disk\/foo\/.tmp/\/home\/foo.web\/.tmp/g" \
                /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
              sed -i "s/foo.web/${_WEB}/g" \
                /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
              sed -i "s/THISPOOL/${_POOL}/g" \
                /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
              sed -i "s/foo/${_USER}/g" \
                /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
              if [ ! -z "${_PHP_FPM_DENY}" ]; then
                sed -i "s/passthru,/${_PHP_FPM_DENY},/g" \
                  /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
                wait
              fi
              if [ ! -z "${_PHP_FPM_TIMEOUT}" ] && [ "${_PHP_FPM_TIMEOUT}" -ge "60" ]; then
                _PHP_TO="${_PHP_FPM_TIMEOUT}s"
                sed -i "s/180s/${_PHP_TO}/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
                wait
              fi
              if [ ! -z "${_CHILD_MAX_FPM}" ] && [ "${_CHILD_MAX_FPM}" -ge "2" ]; then
                sed -i "s/pm.max_children =.*/pm.max_children = ${_CHILD_MAX_FPM}/g" \
                  /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
                wait
              fi
              switch_newrelic ${m} ${_POOL} 0
              nrCheck=YES
              if [ -e "/etc/init.d/php${_PHP_OLD_SV}-fpm" ]; then
                service php${_PHP_OLD_SV}-fpm reload &> /dev/null
              fi
              if [ -e "/etc/init.d/php${m}-fpm" ]; then
                service php${m}-fpm reload &> /dev/null
              fi
            fi
          done
        fi
      fi
    fi
  fi
}
#
# Manage mirroring of drush aliases.
manage_site_drush_alias_mirror() {

  for Alias in `find /home/${_USER}.ftp/.drush/*.alias.drushrc.php \
    -maxdepth 1 -type f | sort`; do
    AliasFile=$(echo "${Alias}" | cut -d'/' -f5 | awk '{ print $1}' 2>&1)
    if [ ! -e "${pthParentUsr}/.drush/${AliasFile}" ] \
      && [ ! -z "${AliasFile}" ]; then
      rm -f /home/${_USER}.ftp/.drush/${AliasFile}
    fi
  done

  if [ -e "/home/${_USER}.ftp/.drush/hm.alias.drushrc.php" ]; then
    rm -f /home/${_USER}.ftp/.drush/hm.alias.drushrc.php
  fi
  if [ -e "/home/${_USER}.ftp/.drush/self.alias.drushrc.php" ]; then
    rm -f /home/${_USER}.ftp/.drush/self.alias.drushrc.php
  fi
  if [ -e "${dscUsr}/.drush/.alias.drushrc.php" ]; then
    rm -f ${dscUsr}/.drush/.alias.drushrc.php
  fi

  isAliasUpdate=NO
  for Alias in `find ${pthParentUsr}/.drush/*.alias.drushrc.php \
    -maxdepth 1 -type f | sort`; do
    ### echo LastAliasName is ${AliasName}
    SiteDir=
    SiteName=
    AliasName=
    AliasName=$(echo "${Alias}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
    AliasName=$(echo "${AliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [ "${AliasName}" = "hm" ] \
      || [ "${AliasName}" = "none" ] \
      || [[ "${AliasName}" =~ (^)"platform_" ]] \
      || [[ "${AliasName}" =~ (^)"server_" ]] \
      || [[ "${AliasName}" =~ (^)"self" ]] \
      || [[ "${AliasName}" =~ (^)"hostmaster" ]] \
      || [ -z "${AliasName}" ]; then
      _IS_SITE=NO
      AliasName=
      SiteName=
      SiteDir=
    else
      SiteName="${AliasName}"
      echo SiteName is "${SiteName}"
      ### echo LastSiteDir is "${SiteDir}"
      SiteDir=
      if [[ "${SiteName}" =~ ".restore"($) ]]; then
        _IS_SITE=NO
        rm -f ${pthParentUsr}/.drush/${SiteName}.alias.drushrc.php
      else
        SiteDir=$(cat ${Alias} \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        if [ -e "${SiteDir}/drushrc.php" ] \
          && [ -e "${SiteDir}/files" ] \
          && [ -e "${SiteDir}/private" ]; then
          echo SiteDir is ${SiteDir}
          echo
          pthAliasMain="${pthParentUsr}/.drush/${SiteName}.alias.drushrc.php"
          pthAliasCopy="/home/${_USER}.ftp/.drush/${SiteName}.alias.drushrc.php"
          if [ ! -e "${pthAliasCopy}" ]; then
            cp -af ${pthAliasMain} ${pthAliasCopy}
            chmod 440 ${pthAliasCopy}
            isAliasUpdate=YES
          else
            _DIFF_T=$(diff -w -B ${pthAliasCopy} ${pthAliasMain} 2>&1)
            if [ ! -z "${_DIFF_T}" ]; then
              cp -af ${pthAliasMain} ${pthAliasCopy}
              chmod 440 ${pthAliasCopy}
              isAliasUpdate=YES
            fi
          fi
        else
          rm -f ${pthAliasCopy}
          echo "ZOMBIE ${SiteDir} detected"
          echo "Moving GHOST ${SiteName}.alias.drushrc.php to ${pthParentUsr}/undo/"
          mv -f ${pthParentUsr}/.drush/${SiteName}.alias.drushrc.php ${pthParentUsr}/undo/ &> /dev/null
          echo
        fi
      fi
    fi
  done
  if [ -x "/usr/bin/drush10" ]; then
    if [ "${isAliasUpdate}" = "YES" ] \
      || [ ! -e "/home/${_USER}.ftp/.drush/sites/.checksums" ]; then
      chage -M 99999 ${_USER}.ftp &> /dev/null
      su -s /bin/bash - ${_USER}.ftp -c "rm -f ~/.drush/sites/*.yml"
      wait
      su -s /bin/bash - ${_USER}.ftp -c "rm -f ~/.drush/sites/.checksums/*.md5"
      wait
      su -s /bin/bash - ${_USER}.ftp -c "drush10 core:init --yes" &> /dev/null
      wait
      su -s /bin/bash - ${_USER}.ftp -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
      wait
      chage -M 90 ${_USER}.ftp &> /dev/null
      ### Update Drush yml sites aliases also for Aegir system user
      su -s /bin/bash - ${_USER} -c "rm -f ~/.drush/sites/*.yml"
      wait
      su -s /bin/bash - ${_USER} -c "rm -f ~/.drush/sites/.checksums/*.md5"
      wait
      su -s /bin/bash - ${_USER} -c "drush10 core:init --yes" &> /dev/null
      wait
      su -s /bin/bash - ${_USER} -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
      wait
    fi
  fi
}
#
# Manage Primary Users.
manage_user() {
  for pthParentUsr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    if [ -e "${pthParentUsr}/config/server_master/nginx/vhost.d" ] \
      && [ -e "${pthParentUsr}/log/fpm.txt" ] \
      && [ ! -e "${pthParentUsr}/log/proxied.pid" ] \
      && [ ! -e "${pthParentUsr}/log/CANCELLED" ]; then
      _USER=""
      _USER=$(echo ${pthParentUsr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
      echo "_USER is == ${_USER} == at manage_user"
      _WEB="${_USER}.web"
      dscUsr="/data/disk/${_USER}"
      octInc="${dscUsr}/config/includes"
      octTpl="${dscUsr}/.drush/sys/provision/http/Provision/Config/Nginx"
      usrDgn="${dscUsr}/.drush/usr/drupalgeddon"
      if [ -e "${dscUsr}/log/imported.pid" ] \
        && [ -e "${dscUsr}/log/post-merge-fix.pid" ]; then
        [ -e "${dscUsr}/log/imported.pid" ] && mv -f ${dscUsr}/log/imported.pid ${dscUsr}/src/
        [ -e "${dscUsr}/log/exported.pid" ] && mv -f ${dscUsr}/log/exported.pid ${dscUsr}/src/
        [ -e "${dscUsr}/log/hmpathfix.pid" ] && mv -f ${dscUsr}/log/hmpathfix.pid ${dscUsr}/src/
        [ -e "${dscUsr}/log/post-merge-fix.pid" ] && mv -f ${dscUsr}/log/post-merge-fix.pid ${dscUsr}/src/
      fi
      if [ ! -e "${dscUsr}/rector.php" ]; then
        rm -f ${dscUsr}/*.php* &> /dev/null
        rm -f ${dscUsr}/composer.lock &> /dev/null
        rm -f ${dscUsr}/composer.json &> /dev/null
        rm -f -r ${dscUsr}/vendor &> /dev/null
        rm -f -r ${dscUsr}/static/vendor &> /dev/null
        rm -f -r ${dscUsr}/.cache/composer &> /dev/null
        rm -f -r ${dscUsr}/.config/composer &> /dev/null
        rm -f -r ${dscUsr}/.composer &> /dev/null
      fi
      chmod 0440 ${dscUsr}/.drush/*.php &> /dev/null
      chmod 0400 ${dscUsr}/.drush/drushrc.php &> /dev/null
      chmod 0400 ${dscUsr}/.drush/hm.alias.drushrc.php &> /dev/null
      chmod 0400 ${dscUsr}/.drush/hostmaster*.php &> /dev/null
      chmod 0400 ${dscUsr}/.drush/platform_*.php &> /dev/null
      chmod 0400 ${dscUsr}/.drush/server_*.php &> /dev/null
      chmod 0710 ${dscUsr}/.drush &> /dev/null
      find ${dscUsr}/config/server_master \
        -type d -exec chmod 0700 {} \; &> /dev/null
      find ${dscUsr}/config/server_master \
        -type f -exec chmod 0600 {} \; &> /dev/null
      chmod +rx ${dscUsr}/config{,/server_master{,/nginx{,/passwords.d}}} &> /dev/null
      chmod +r ${dscUsr}/config/server_master/nginx/passwords.d/* &> /dev/null
      if [ ! -e "${dscUsr}/.tmp/.ctrl.${_X_SE}.pid" ]; then
        rm -rf ${dscUsr}/.drush/cache
        mkdir -p ${dscUsr}/.tmp
        touch ${dscUsr}/.tmp
        find ${dscUsr}/.tmp/ -mtime +0 -exec rm -rf {} \; &> /dev/null
        chown ${_USER}:${usrGroup} ${dscUsr}/.tmp &> /dev/null
        chmod 02755 ${dscUsr}/.tmp &> /dev/null
        echo OK > ${dscUsr}/.tmp/.ctrl.${_X_SE}.pid
      fi
      if [ ! -e "${dscUsr}/static/control/.ctrl.${_X_SE}.pid" ] \
        && [ -e "/home/${_USER}.ftp/clients" ]; then
        mkdir -p ${dscUsr}/static/control
        chmod 755 ${dscUsr}/static/control
        if [ -e "/var/xdrago/conf/control-readme.txt" ]; then
          cp -af /var/xdrago/conf/control-readme.txt \
            ${dscUsr}/static/control/README.txt &> /dev/null
          chmod 0644 ${dscUsr}/static/control/README.txt
        fi
        chown -R ${_USER}.ftp:${usrGroup} ${dscUsr}/static/control
        rm -f ${dscUsr}/static/control/.ctrl.*
        echo OK > ${dscUsr}/static/control/.ctrl.${_X_SE}.pid
      fi
      if [ -e "${dscUsr}/static/control/ssl-live-mode.info" ]; then
        if [ -e "${dscUsr}/tools/le/.ctrl/ssl-demo-mode.pid" ]; then
          rm -f ${dscUsr}/tools/le/.ctrl/ssl-demo-mode.pid
        fi
      fi
      if [ -e "/root/.${_USER}.octopus.cnf" ]; then
        source /root/.${_USER}.octopus.cnf
      fi
      _THIS_HM_PLR=$(cat ${dscUsr}/.drush/hostmaster.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_PLR}/modules/path_alias_cache" ] \
        && [ -x "/opt/tools/drush/8/drush/drush.php" ]; then
        if [ -x "/opt/php56/bin/php" ]; then
          echo 5.6 > ${dscUsr}/static/control/cli.info
        fi
      fi
      nrCheck=
      switch_php
      ### reload nginx
      service nginx reload &> /dev/null
      if [ -z ${nrCheck} ]; then
        if [ -z ${_PHP_SV} ]; then
          _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
          if [ -z "${_PHP_SV}" ]; then
            _PHP_SV=74
          fi
        fi
        if [ -f "${dscUsr}/static/control/multi-fpm.info" ]; then
          _PHP_M_V="83 82 81 80 74 73 72 71 70 56"
          for m in ${_PHP_M_V}; do
            if [ -x "/opt/php${m}/bin/php" ] \
              && [ -e "/opt/php${m}/etc/pool.d/${_USER}.${m}.conf" ]; then
              switch_newrelic ${m} ${_USER}.${m} 1
            fi
          done
        else
          if [ -x "/opt/php${_PHP_SV}/bin/php" ] \
            && [ -e "/opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf" ]; then
            switch_newrelic ${_PHP_SV} ${_USER} 1
          fi
        fi
      fi
      site_socket_inc_gen
      if [ -e "${pthParentUsr}/clients" ] && [ ! -z ${_USER} ]; then
        echo Managing Users for ${pthParentUsr} Instance
        rm -rf ${pthParentUsr}/clients/admin &> /dev/null
        rm -rf ${pthParentUsr}/clients/omega8ccgmailcom &> /dev/null
        rm -rf ${pthParentUsr}/clients/nocomega8cc &> /dev/null
        rm -rf ${pthParentUsr}/clients/*/backups &> /dev/null
        symlinks -dr ${pthParentUsr}/clients &> /dev/null
        if [ -d "/home/${_USER}.ftp" ]; then
          disable_chattr ${_USER}.ftp
          symlinks -dr /home/${_USER}.ftp &> /dev/null
          echo >> ${_THIS_LTD_CONF}
          echo "[${_USER}.ftp]" >> ${_THIS_LTD_CONF}
          echo "path : ['/opt/user/npm/${_USER}.ftp', \
                        '/opt/user/gems/${_USER}.ftp', \
                        '${dscUsr}/distro', \
                        '${dscUsr}/static', \
                        '${dscUsr}/backups', \
                        '${dscUsr}/clients']" \
                        | fmt -su -w 2500 >> ${_THIS_LTD_CONF}
          manage_site_drush_alias_mirror
          manage_sec
          if [ -d "/home/${_USER}.ftp/clients" ]; then
            chown -R ${_USER}.ftp:${usrGroup} /home/${_USER}.ftp/users
            chmod 700 /home/${_USER}.ftp/users
            chmod 600 /home/${_USER}.ftp/users/*
          fi
          if [ ! -L "/home/${_USER}.ftp/static" ]; then
            rm -f /home/${_USER}.ftp/{backups,clients,static}
            ln -sfn ${dscUsr}/backups /home/${_USER}.ftp/backups
            ln -sfn ${dscUsr}/clients /home/${_USER}.ftp/clients
            ln -sfn ${dscUsr}/static  /home/${_USER}.ftp/static
          fi
          if [ ! -e "/home/${_USER}.ftp/.tmp/.ctrl.${_X_SE}.pid" ]; then
            rm -rf /home/${_USER}.ftp/.drush/cache
            rm -rf /home/${_USER}.ftp/.tmp
            mkdir -p /home/${_USER}.ftp/.tmp
            chown ${_USER}.ftp:${usrGroup} /home/${_USER}.ftp/.tmp &> /dev/null
            chmod 700 /home/${_USER}.ftp/.tmp &> /dev/null
            echo OK > /home/${_USER}.ftp/.tmp/.ctrl.${_X_SE}.pid
          fi
          enable_chattr ${_USER}.ftp
          echo Done for ${pthParentUsr}
        else
          echo Directory /home/${_USER}.ftp not available
        fi
        echo
      else
        echo Directory ${pthParentUsr}/clients not available
      fi
      echo
    fi
  done
}

#
# Find correct IP.
find_correct_ip() {
  if [ -e "/root/.found_correct_ipv4.cnf" ]; then
    _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>&1)
    _LOC_IP=$(echo -n ${_LOC_IP} | tr -d "\n" 2>&1)
  else
    _LOC_IP=$(curl ${crlGet} https://api.ipify.org \
      | sed 's/[^0-9\.]//g' 2>&1)
    if [ -z "${_LOC_IP}" ]; then
      _LOC_IP=$(curl ${crlGet} http://ipv4.icanhazip.com \
        | sed 's/[^0-9\.]//g' 2>&1)
    fi
    if [ ! -z "${_LOC_IP}" ]; then
      echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
    fi
  fi
}

#
# Restrict node if needed.
fix_node_in_lshell_access() {
  pthLog="/var/xdrago/log"
  if [ ! -e "${pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    pthLog="/var/xdrago_wait/log"
  fi
  if [ -e "/etc/lshell.conf" ]; then
    PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
    PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
    if [[ "${PrTestPhantom}" =~ "PHANTOM" ]] \
      || [[ "${PrTestCluster}" =~ "CLUSTER" ]] \
      || [ -e "/root/.allow.node.lshell.cnf" ]; then
      _ALLOW_NODE=YES
    else
      _ALLOW_NODE=NO
      sed -i "s/, 'node',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'node',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'npm',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'npm',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'npx',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'npx',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'find',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'find',/,/g" /var/xdrago/conf/lshell.conf
      wait
      sed -i "s/, 'scp',/,/g" /etc/lshell.conf
      wait
      sed -i "s/, 'scp',/,/g" /var/xdrago/conf/lshell.conf
      wait
    fi
  fi
}

###-------------SYSTEM-----------------###

if [ ! -e "/home/.ctrl.${_X_SE}.pid" ]; then
  chattr -i /home
  chmod 0711 /home
  chown root:root /home
  rm -f /home/.ctrl.*
  while IFS=':' read -r login pass uid gid uname homedir shell; do
    if [[ "${homedir}" = **/home/** ]]; then
      if [ -d "${homedir}" ]; then
        chattr -i ${homedir}
        chown ${uid}:${gid} ${homedir} &> /dev/null
        if [ -d "${homedir}/.ssh" ]; then
          chattr -i ${homedir}/.ssh
          chown -R ${uid}:${gid} ${homedir}/.ssh &> /dev/null
        fi
        if [ -d "${homedir}/.tmp" ]; then
          chattr -i ${homedir}/.tmp
          chown -R ${uid}:${gid} ${homedir}/.tmp &> /dev/null
        fi
        if [ -d "${homedir}/.drush" ]; then
          chattr +i ${homedir}/.drush/usr
          chattr +i ${homedir}/.drush/*.ini
          chattr +i ${homedir}/.drush
        fi
        if [[ ! "${login}" =~ ".ftp"($) ]] \
          && [[ ! "${login}" =~ ".web"($) ]]; then
          chattr +i ${homedir}
        fi
      fi
    fi
  done < /etc/passwd
  touch /home/.ctrl.${_X_SE}.pid
fi

if [ ! -L "/usr/bin/MySecureShell" ] && [ -x "/usr/bin/mysecureshell" ]; then
  mv -f /usr/bin/MySecureShell /var/backups/legacy-MySecureShell-bin
  ln -sfn /usr/bin/mysecureshell /usr/bin/MySecureShell
fi

_NOW=$(date +%y%m%d-%H%M%S 2>&1)
_NOW=${_NOW//[^0-9-]/}
mkdir -p /var/backups/ltd/{conf,log,old}
mkdir -p /var/backups/zombie/deleted
_THIS_LTD_CONF="/var/backups/ltd/conf/lshell.conf.${_NOW}"
if [ -e "/run/manage_ruby_users.pid" ] \
  || [ -e "/run/manage_ltd_users.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ] \
  || [ -e "/run/octopus_install_run.pid" ]; then
  touch /var/xdrago/log/wait-manage-ltd-users.pid
  echo "Another BOA task is running, we have to wait"
  sleep 3
  exit 0
elif [ ! -e "/var/xdrago/conf/lshell.conf" ]; then
  echo "Missing /var/xdrago/conf/lshell.conf template"
  exit 0
else
  rm -f /var/xdrago/log/wait-manage-ltd-users.pid
  touch /run/manage_ltd_users.pid
  count_cpu
  find_fast_mirror_early
  find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
  if [ ! -e "${pthLog}/node.manage.lshell.ctrl.${_X_SE}.pid" ]; then
    fix_node_in_lshell_access
    touch ${pthLog}/node.manage.lshell.ctrl.${_X_SE}.pid
  fi
  cat /var/xdrago/conf/lshell.conf > ${_THIS_LTD_CONF}
  find_correct_ip
  sed -i "s/1.1.1.1/${_LOC_IP}/g" ${_THIS_LTD_CONF}
  wait
  if [ ! -e "/root/.allow.mc.cnf" ]; then
    sed -i "s/'mc', //g" ${_THIS_LTD_CONF}
    wait
    sed -i "s/, 'mc':'mc -u'//g" ${_THIS_LTD_CONF}
    wait
  fi
  if [ ! -e "/root/.allow.du.cnf" ]; then
    sed -i "s/'du', //g" ${_THIS_LTD_CONF}
    wait
    sed -i "s/, 'du':'du -s -h'//g" ${_THIS_LTD_CONF}
    wait
  fi
  add_ltd_group_if_not_exists
  kill_zombies >/var/backups/ltd/log/zombies-${_NOW}.log 2>&1
  manage_user >/var/backups/ltd/log/users-${_NOW}.log 2>&1
  if [ -e "${_THIS_LTD_CONF}" ]; then
    _DIFF_T=$(diff -w -B ${_THIS_LTD_CONF} /etc/lshell.conf 2>&1)
    if [ ! -z "${_DIFF_T}" ]; then
      cp -af /etc/lshell.conf /var/backups/ltd/old/lshell.conf-before-${_NOW}
      cp -af ${_THIS_LTD_CONF} /etc/lshell.conf
    else
      rm -f ${_THIS_LTD_CONF}
    fi
  fi
  if [ -L "/bin/sh" ] && [ ! -e "/run/octopus_install_run.pid" ]; then
    _WEB_SH=$(readlink -n /bin/sh 2>&1)
    _WEB_SH=$(echo -n ${_WEB_SH} | tr -d "\n" 2>&1)
    if [ -x "/bin/websh" ]; then
      if [ "${_WEB_SH}" != "/bin/websh" ]; then
        ln -sfn /bin/websh /bin/sh
        if [ -e "/usr/bin/sh" ]; then
          ln -sfn /bin/websh /usr/bin/sh
        fi
      fi
    else
      if [ -x "/bin/dash" ]; then
        if [ "${_WEB_SH}" != "/bin/dash" ]; then
          ln -sfn /bin/dash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /bin/dash /usr/bin/sh
          fi
        fi
      elif [ -x "/usr/bin/dash" ]; then
        if [ "${_WEB_SH}" != "/usr/bin/dash" ]; then
          ln -sfn /usr/bin/dash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /usr/bin/dash /usr/bin/sh
          fi
        fi
      elif [ -x "/bin/bash" ]; then
        if [ "${_WEB_SH}" != "/bin/bash" ]; then
          ln -sfn /bin/bash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /bin/bash /usr/bin/sh
          fi
        fi
      elif [ -x "/usr/bin/bash" ]; then
        if [ "${_WEB_SH}" != "/usr/bin/bash" ]; then
          ln -sfn /usr/bin/bash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /usr/bin/bash /usr/bin/sh
          fi
        fi
      fi
      curl -s -A iCab "${urlHmr}/helpers/websh.sh.txt" -o /bin/websh
      chmod 755 /bin/websh
    fi
  fi
  rm -f ${_TMP}/*.txt
  if [ ! -e "/root/.home.no.wildcard.chmod.cnf" ]; then
    chmod 700 /home/* &> /dev/null
  fi
  chmod 0600 /var/log/lsh/*
  chmod 0440 /var/aegir/.drush/*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/drushrc.php &> /dev/null
  chmod 0400 /var/aegir/.drush/hm.alias.drushrc.php &> /dev/null
  chmod 0400 /var/aegir/.drush/hostmaster*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/platform_*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/server_*.php &> /dev/null
  chmod 0710 /var/aegir/.drush &> /dev/null
  find /var/aegir/config/server_master \
    -type d -exec chmod 0700 {} \; &> /dev/null
  find /var/aegir/config/server_master \
    -type f -exec chmod 0600 {} \; &> /dev/null
  sleep 5
  [ -e "/run/manage_ltd_users.pid" ] && rm -f /run/manage_ltd_users.pid
  exit 0
fi
###EOF2024###
