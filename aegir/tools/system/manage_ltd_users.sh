#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
export _tRee=pro
export _xSrl=540proT05

_CHECK_HOST=$(uname -n 2>&1)
_OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2 2>&1)

_usrGroup=users
_WEBG=www-data
_crlGet="-L --max-redirs 3 -k -s --retry 3 --retry-delay 5 -A iCab"
_aptYesUnth="-y --allow-unauthenticated"


if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.pause_tasks_maint.cnf" ]; then
  exit 0
fi

if [ -x "/usr/bin/gpg2" ]; then
  _GPG=gpg2
else
  _GPG=gpg
fi

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
}

_find_fast_mirror_early() {
  _isNetc=$(which netcat 2>&1)
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
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

###----------------------------###
##    Manage ltd shell users    ##
###----------------------------###
#
# Remove dangerous stuff from the string.
_sanitize_string() {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\&\|\*]//g; s/\(['"'"'\]\)//g'
}
#
# Add ltd-shell group if not exists.
_add_ltd_group_if_not_exists() {
  _LTD_EXISTS=$(getent group ltd-shell 2>&1)
  if [[ "${_LTD_EXISTS}" =~ "ltd-shell" ]]; then
    _DO_NOTHING=YES
  else
    addgroup --system ltd-shell &> /dev/null
  fi
}
#
# Enable chattr.
_enable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    _U_HD="/home/$1/.drush"
    _U_TP="/home/$1/.tmp"
    _U_II="${_U_HD}/php.ini"
    if [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
      _if_hosted_sys
      if [ "${_hostedSys}" = "YES" ]; then
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
      chown $1:${_usrGroup} ${_U_TP}
      chown $1:${_usrGroup} ${_U_HD}
      chmod 02755 ${_U_TP}
      chmod 02755 ${_U_HD}
      if [ ! -L "${_U_HD}/usr/registry_rebuild" ] \
        && [ -e "${_dscUsr}/.drush/usr/registry_rebuild" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/registry_rebuild \
          ${_U_HD}/usr/registry_rebuild
      fi
      if [ ! -L "${_U_HD}/usr/clean_missing_modules" ] \
        && [ -e "${_dscUsr}/.drush/usr/clean_missing_modules" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/clean_missing_modules \
          ${_U_HD}/usr/clean_missing_modules
      fi
      if [ ! -L "${_U_HD}/usr/drupalgeddon" ] \
        && [ -e "${_dscUsr}/.drush/usr/drupalgeddon" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/drupalgeddon \
          ${_U_HD}/usr/drupalgeddon
      fi
      if [ ! -L "${_U_HD}/usr/drush_ecl" ] \
        && [ -e "${_dscUsr}/.drush/usr/drush_ecl" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/drush_ecl \
          ${_U_HD}/usr/drush_ecl
      fi
      if [ ! -L "${_U_HD}/usr/safe_cache_form_clear" ] \
        && [ -e "${_dscUsr}/.drush/usr/safe_cache_form_clear" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/safe_cache_form_clear \
          ${_U_HD}/usr/safe_cache_form_clear
      fi
      if [ ! -L "${_U_HD}/usr/utf8mb4_convert" ] \
        && [ -e "${_dscUsr}/.drush/usr/utf8mb4_convert" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/utf8mb4_convert \
          ${_U_HD}/usr/utf8mb4_convert
      fi
    fi

    _CHECK_USE_PHP_CLI=$(grep "/opt/php" \
      ${_dscUsr}/tools/drush/drush.php 2>&1)
    _PHP_V="83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
        && [ ! -e "${_U_HD}/.ctrl.php${e}.${_xSrl}.pid" ]; then
        _PHP_CLI_UPDATE=YES
      fi
    done
    echo _PHP_CLI_UPDATE is ${_PHP_CLI_UPDATE} for $1

    if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
      || [ ! -e "${_U_II}" ] \
      || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
      mkdir -p ${_U_HD}
      rm -f ${_U_HD}/.ctrl.php*
      rm -f ${_U_II}
      if [ ! -z "${_T_CLI_VRN}" ]; then
        _USE_PHP_CLI="${_T_CLI_VRN}"
        echo "_USE_PHP_CLI is ${_USE_PHP_CLI} for $1 at ${_USER} WTF"
        echo "_T_CLI_VRN is ${_T_CLI_VRN}"
      else
        _CHECK_USE_PHP_CLI=$(grep "/opt/php" \
          ${_dscUsr}/tools/drush/drush.php 2>&1)
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
          ${_dscUsr}/.drush/usr: \
          ${_dscUsr}/distro:     \
          ${_dscUsr}/platforms:  \
          ${_dscUsr}/static\""
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
        echo > ${_U_HD}/.ctrl.php${_U_INI}.${_xSrl}.pid
        echo > ${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid
      fi
    fi

    _UQ="$1"
    chage -M 99999 ${_UQ} &> /dev/null
    _UPDATE_GEMS=NO
    ###
    ### Cleanup of no longer used/allowed Ruby Gems and NPM access leftovers
    ###
    [ -e "/home/${_UQ}/.rvm" ] && rm -rf /home/${_UQ}/.rvm*
    [ -e "/home/${_UQ}/.gem" ] && rm -rf /home/${_UQ}/.gem*
    [ -e "/home/${_UQ}/.npm" ] && rm -rf /home/${_UQ}/.npm*
    [ -e "/home/${_UQ}/.mkshrc" ] && rm -rf /home/${_UQ}/.mkshrc
    if [ "$1" = "${_USER}.ftp" ]; then
      [ ! -d "/home/${_UQ}/.composer" ] && su -s /bin/bash - ${_UQ} -c "mkdir ~/.composer"
    else
      [ -d "/home/${_UQ}/.composer" ] && rm -rf /home/${_UQ}/.composer
    fi
    ###
    ### Check if Ruby Gems and NPM access should be added or removed
    ###
    if [ -f "${_dscUsr}/static/control/compass.info" ]; then
      ###
      ### Check if Ruby Gems access needs an update
      ###
      if [ ! -e "/opt/user/gems/${_UQ}/gems/oily_png-1.1.1" ] \
        || [ ! -e "${_dscUsr}/log/.gems.build.rb.${_UQ}.${_xSrl}.txt" ]; then
        _UPDATE_GEMS=YES
      fi
      if [ ! -e "/opt/user/npm/${_UQ}/.npm-packages/bin" ] \
        && [ -e "/root/.allow.node.lshell.cnf" ]; then
        _UPDATE_GEMS=YES
      fi
    else
      ###
      ### Remove no longer used Ruby Gems and NPM access
      ###
      [ -e "/home/${_UQ}/.npm" ] && rm -rf /home/${_UQ}/.npm*
      [ -e "/opt/user/gems/${_UQ}" ] && rm -rf /opt/user/gems/${_UQ}
      [ -e "/opt/user/npm/${_UQ}" ] && rm -rf /opt/user/npm/${_UQ}
      [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.gems.build*
      [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.npm.build*
    fi
    if [ "${_UPDATE_GEMS}" = "YES" ]; then
      ###
      ### Ruby Gems are allowed for both main and client SSH accounts
      ###
      [ ! -d "/opt/user/gems/${_UQ}" ] && mkdir -p /opt/user/gems/${_UQ}
      chmod 1777 /opt/user/gems
      chown -R ${_UQ}:users /opt/user/gems/${_UQ}
      chown root:root /opt/user/gems
      if [ -d "/opt/user/gems/${_UQ}" ] \
        && [ -e "/usr/local/lib/ruby/gems/3.3.0/gems/oily_png-1.1.1" ] \
        && [ ! -e "/opt/user/gems/${_UQ}/gems/oily_png-1.1.1" ]; then
        cp -a /usr/local/lib/ruby/gems/3.3.0/gems /opt/user/gems/${_UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/specifications /opt/user/gems/${_UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/extensions /opt/user/gems/${_UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/doc /opt/user/gems/${_UQ}/
        chown -R ${_UQ}:users /opt/user/gems/${_UQ}
        [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.gems.build*
        touch ${_dscUsr}/log/.gems.build.rb.${_UQ}.${_xSrl}.txt
      fi
      ###
      ### Check if NPM support is allowed and if needs an update
      ### NOTE: It will be restricted to the main SSH account only
      ###
      if [ -e "/root/.allow.node.lshell.cnf" ] \
        && [ "$1" = "${_USER}.ftp" ] \
        && [ -x "/usr/bin/node" ] \
        && [ -e "/home/${_UQ}/static/control" ]; then
        if [ ! -e "/opt/user/npm/${_UQ}/.npm-packages/bin" ] \
          || [ ! -e "${_dscUsr}/log/.npm.build.${_UQ}.${_xSrl}.txt" ]; then
          [ ! -d "/opt/user/npm" ] && mkdir -p /opt/user/npm
          chown root:root /opt/user/npm
          chmod 1777 /opt/user/npm
          [ ! -d "/opt/user/npm/${_UQ}" ] && mkdir -p /opt/user/npm/${_UQ}
          [ ! -e "/home/${_UQ}/.npmrc" ] && su -s /bin/bash - ${_UQ} -c "echo 'prefix = /opt/user/npm/${_UQ}/.npm-packages' > ~/.npmrc"
          [ -e "/home/${_UQ}/.npmrc" ] && chattr +i /home/${_UQ}/.npmrc
          mkdir -p /opt/user/npm/${_UQ}/.bundle
          mkdir -p /opt/user/npm/${_UQ}/.composer
          mkdir -p /opt/user/npm/${_UQ}/.config
          mkdir -p /opt/user/npm/${_UQ}/.npm
          mkdir -p /opt/user/npm/${_UQ}/.npm-packages/bin
          mkdir -p /opt/user/npm/${_UQ}/.npm-packages/lib/node_modules
          mkdir -p /opt/user/npm/${_UQ}/.sass-cache
          chown -R ${_UQ}:users /opt/user/npm/${_UQ}
          [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.npm.build*
          touch ${_dscUsr}/log/.npm.build.${_UQ}.${_xSrl}.txt
        fi
      else
        [ -e "/home/${_UQ}/.npm" ] && rm -rf /home/${_UQ}/.npm*
        [ -e "/opt/user/npm/${_UQ}" ] && rm -rf /opt/user/npm/${_UQ}
        [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.npm.build*
      fi
    fi
    rm -f /home/${_UQ}/{.profile,.bash_logout,.bash_profile,.bashrc,.z_login,.zshrc}
    chage -M 90 ${_UQ} &> /dev/null

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
_disable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
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
_kill_zombies() {
  for _Existing in `cat /etc/passwd | cut -d ':' -f1 | sort`; do
    _SEC_IDY=$(id -nG ${_Existing} 2>&1)
    if [[ "${_SEC_IDY}" =~ "ltd-shell" ]] \
      && [ ! -z "${_Existing}" ] \
      && [[ ! "${_Existing}" =~ ".ftp"($) ]] \
      && [[ ! "${_Existing}" =~ ".web"($) ]]; then
      _usrParent=$(echo ${_Existing} | cut -d. -f1 | awk '{ print $1}' 2>&1)
      _usrParentTest=${_usrParent//[^a-z0-9]/}
      if [ ! -z "${_usrParentTest}" ]; then
        _PAR_DIR="/data/disk/${_usrParent}/clients"
        _SEC_SYM="/home/${_Existing}/sites"
        _SEC_DIR=$(readlink -n ${_SEC_SYM} 2>&1)
        _SEC_DIR=$(echo -n ${_SEC_DIR} | tr -d "\n" 2>&1)
        if [ ! -L "${_SEC_SYM}" ] || [ ! -e "${_SEC_DIR}" ] \
          || [ ! -e "/home/${_usrParent}.ftp/users/${_Existing}" ]; then
          mkdir -p /var/backups/zombie/deleted/${_NOW}
          kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
          _disable_chattr ${_Existing}
          rm -rf /home/${_Existing}/.gnupg
          deluser \
            --remove-home \
            --backup-to /var/backups/zombie/deleted/${_NOW} ${_Existing} &> /dev/null
          rm -f /home/${_usrParent}.ftp/users/${_Existing}
          echo Zombie from etc.passwd ${_Existing} killed
          echo
        fi
      fi
    fi
  done
  for _Existing in `ls /home | cut -d '/' -f1 | sort`; do
    _isTest=${_Existing//[^a-z0-9]/}
    if [ ! -z "${_isTest}" ]; then
      _SEC_IDY=$(id -nG ${_Existing} 2>&1)
      if [[ "${_SEC_IDY}" =~ "No such user" ]] \
        && [ ! -z "${_Existing}" ] \
        && [[ ! "${_Existing}" =~ ".ftp"($) ]] \
        && [[ ! "${_Existing}" =~ ".web"($) ]]; then
        _disable_chattr ${_Existing}
        mkdir -p /var/backups/zombie/deleted/${_NOW}
        mv /home/${_Existing} /var/backups/zombie/deleted/${_NOW}/.leftover-${_Existing}
        _usrParent=$(echo ${_Existing} | cut -d. -f1 | awk '{ print $1}' 2>&1)
        if [ -e "/home/${_usrParent}.ftp/users/${_Existing}" ]; then
          rm -f /home/${_usrParent}.ftp/users/${_Existing}
        fi
        echo Zombie from home.dir ${_Existing} killed
        echo
      fi
    fi
  done
}
#
# Fix dot dirs.
_fix_dot_dirs() {
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    _usrTmp="/home/${_usrLtd}/.tmp"
    if [ ! -d "${_usrTmp}" ]; then
      mkdir -p ${_usrTmp}
      chown ${_usrLtd}:${_usrGroup} ${_usrTmp}
      chmod 02755 ${_usrTmp}
    fi
    _usrLftp="/home/${_usrLtd}/.lftp"
    if [ ! -d "${_usrLftp}" ]; then
      mkdir -p ${_usrLftp}
      chown ${_usrLtd}:${_usrGroup} ${_usrLftp}
      chmod 02755 ${_usrLftp}
    fi
    _usrLhist="/home/${_usrLtd}/.lhistory"
    if [ ! -e "${_usrLhist}" ]; then
      touch ${_usrLhist}
      chown ${_usrLtd}:${_usrGroup} ${_usrLhist}
      chmod 644 ${_usrLhist}
    fi
    _usrDrush="/home/${_usrLtd}/.drush"
    if [ ! -d "${_usrDrush}" ]; then
      mkdir -p ${_usrDrush}
      chown ${_usrLtd}:${_usrGroup} ${_usrDrush}
      chmod 700 ${_usrDrush}
    fi
    _usrSsh="/home/${_usrLtd}/.ssh"
    if [ ! -d "${_usrSsh}" ]; then
      mkdir -p ${_usrSsh}
      chown -R ${_usrLtd}:${_usrGroup} ${_usrSsh}
      chmod 700 ${_usrSsh}
    fi
    chmod 600 ${_usrSsh}/id_{r,d}sa &> /dev/null
    chmod 600 ${_usrSsh}/known_hosts &> /dev/null
    _usrBzr="/home/${_usrLtd}/.bazaar"
    if [ -x "/usr/local/bin/bzr" ]; then
      if [ ! -z "${_usrLtd}" ] && [ ! -e "${_usrBzr}/bazaar.conf" ]; then
        mkdir -p ${_usrBzr}
        echo ignore_missing_extensions=True > ${_usrBzr}/bazaar.conf
        chown -R ${_usrLtd}:${_usrGroup} ${_usrBzr}
        chmod 700 ${_usrBzr}
      fi
    else
      if [ ! -z "${_usrLtd}" ] && [ -d "${_usrBzr}" ]; then
        rm -rf ${_usrBzr}
      fi
    fi
  fi
}
#
# Manage Drush _Aliases.
_manage_sec_user_drush_aliases() {
  if [ -e "${_Client}" ]; then
    if [ -L "${_usrLtdRoot}/sites" ]; then
      _symTgt=$(readlink -n ${_usrLtdRoot}/sites 2>&1)
      _symTgt=$(echo -n ${_symTgt} | tr -d "\n" 2>&1)
    else
      rm -f ${_usrLtdRoot}/sites
    fi
    if [ "${_symTgt}" != "${_Client}" ] \
      || [ ! -e "${_usrLtdRoot}/sites" ]; then
      rm -f ${_usrLtdRoot}/sites
      ln -sfn ${_Client} ${_usrLtdRoot}/sites
    fi
  fi
  if [ ! -e "${_usrLtdRoot}/.drush" ]; then
    mkdir -p ${_usrLtdRoot}/.drush
  fi
  for _Alias in `find ${_usrLtdRoot}/.drush/*.alias.drushrc.php \
    -maxdepth 1 -type f | sort`; do
    _AliasName=$(echo "${_Alias}" | cut -d'/' -f5 | awk '{ print $1}' 2>&1)
    _AliasName=$(echo "${_AliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [ ! -z "${_AliasName}" ] \
      && [ ! -e "${_usrLtdRoot}/sites/${_AliasName}" ]; then
      rm -f ${_usrLtdRoot}/.drush/${_AliasName}.alias.drushrc.php
    fi
  done
  for _Symlink in `find ${_usrLtdRoot}/sites/ \
    -maxdepth 1 -mindepth 1 | sort`; do
    _SiteName=$(echo ${_Symlink}  \
      | cut -d'/' -f5 \
      | awk '{ print $1}' 2>&1)
    _pthAliasMain="${_pthParen_tUsr}/.drush/${_SiteName}.alias.drushrc.php"
    _pthAliasCopy="${_usrLtdRoot}/.drush/${_SiteName}.alias.drushrc.php"
    if [ ! -z "${_SiteName}" ] && [ ! -e "${_pthAliasCopy}" ]; then
      cp -af ${_pthAliasMain} ${_pthAliasCopy}
      chmod 440 ${_pthAliasCopy}
    elif [ ! -z "${_SiteName}" ]  && [ -e "${_pthAliasCopy}" ]; then
      _DIFF_T=$(diff -w -B ${_pthAliasCopy} ${_pthAliasMain} 2>&1)
      if [ ! -z "${_DIFF_T}" ]; then
        cp -af ${_pthAliasMain} ${_pthAliasCopy}
        chmod 440 ${_pthAliasCopy}
      fi
    fi
  done
}
#
# OK, create user.
_ok_create_user() {
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    _ADMIN="${_USER}.ftp"
    echo "_ADMIN is == ${_ADMIN} == at _ok_create_user"
    _usrLtdRoot="/home/${_usrLtd}"
    _SEC_SYM="${_usrLtdRoot}/sites"
    _TMP="/var/tmp"
    if [ ! -L "${_SEC_SYM}" ]; then
      mkdir -p /var/backups/zombie/deleted/${_NOW}
      mv -f ${_usrLtdRoot} /var/backups/zombie/deleted/${_NOW}/ &> /dev/null
    fi
    if [ ! -d "${_usrLtdRoot}" ]; then
      if [ -e "/usr/bin/mysecureshell" ] && [ -e "/etc/ssh/sftp_config" ]; then
        useradd -d ${_usrLtdRoot} -s /usr/bin/mysecureshell -m -N -r ${_usrLtd}
        echo "_usrLtdRoot is == ${_usrLtdRoot} == at _ok_create_user"
      else
        useradd -d ${_usrLtdRoot} -s /usr/bin/lshell -m -N -r ${_usrLtd}
      fi
      adduser ${_usrLtd} ${_WEBG}
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
          _ESC_LUPASS=$(_sanitize_string "${_ESC_LUPASS}" 2>&1)
        fi
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _LEN_LUPASS=$(echo ${#_ESC_LUPASS} 2>&1)
      fi
      if [ -z "${_ESC_LUPASS}" ] || [ "${_LEN_LUPASS}" -lt "9" ]; then
        _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _ESC_LUPASS=$(_sanitize_string "${_ESC_LUPASS}" 2>&1)
      fi
      ph=$(mkpasswd -m sha-512 "${_ESC_LUPASS}" \
        $(openssl rand -base64 16 | tr -d '+=' | head -c 16) 2>&1)
      usermod -p $ph ${_usrLtd}
      passwd -w 7 -x 90 ${_usrLtd}
      usermod -aG lshellg ${_usrLtd}
      usermod -aG ltd-shell ${_usrLtd}
    fi
    if [ ! -e "/home/${_ADMIN}/users/${_usrLtd}" ] \
      && [ ! -z "${_ESC_LUPASS}" ]; then
      if [ -e "/usr/bin/mysecureshell" ] \
        && [ -e "/etc/ssh/sftp_config" ]; then
        chsh -s /usr/bin/mysecureshell ${_usrLtd}
      else
        chsh -s /usr/bin/lshell ${_usrLtd}
      fi
      echo >> ${_THIS_LTD_CONF}
      echo "[${_usrLtd}]" >> ${_THIS_LTD_CONF}
      echo "path : [${_ALLD_DIR}]" >> ${_THIS_LTD_CONF}
      chmod 700 ${_usrLtdRoot}
      mkdir -p /home/${_ADMIN}/users
      echo "${_ESC_LUPASS}" > /home/${_ADMIN}/users/${_usrLtd}
    fi
    _fix_dot_dirs
    rm -f ${_usrLtdRoot}/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
}
#
# OK, update user.
_ok_update_user() {
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    _ADMIN="${_USER}.ftp"
    _usrLtdRoot="/home/${_usrLtd}"
    if [ -e "/home/${_ADMIN}/users/${_usrLtd}" ]; then
      echo >> ${_THIS_LTD_CONF}
      echo "[${_usrLtd}]" >> ${_THIS_LTD_CONF}
      echo "path : [${_ALLD_DIR}]" >> ${_THIS_LTD_CONF}
      _manage_sec_user_drush_aliases
      chmod 700 ${_usrLtdRoot}
    fi
    _fix_dot_dirs
    rm -f ${_usrLtdRoot}/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
}
#
# Add user if not exists.
_add_user_if_not_exists() {
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    _ID_EXISTS=$(getent passwd ${_usrLtd} 2>&1)
    _ID_SHELLS=$(id -nG ${_usrLtd} 2>&1)
    echo "_ID_EXISTS is == ${_ID_EXISTS} == at _add_user_if_not_exists"
    echo "_ID_SHELLS is == ${_ID_SHELLS} == at _add_user_if_not_exists"
    if [ -z "${_ID_EXISTS}" ]; then
      echo "We will create user == ${_usrLtd} =="
      _ok_create_user
      _manage_sec_user_drush_aliases
      _enable_chattr ${_usrLtd}
    elif [[ "${_ID_EXISTS}" =~ "${_usrLtd}" ]] \
      && [[ "${_ID_SHELLS}" =~ "ltd-shell" ]]; then
      echo "We will update user == ${_usrLtd} =="
      _disable_chattr ${_usrLtd}
      rm -rf /home/${_usrLtd}/drush-backups
      _usrTmp="/home/${_usrLtd}/.tmp"
      if [ ! -d "${_usrTmp}" ]; then
        mkdir -p ${_usrTmp}
        chown ${_usrLtd}:${_usrGroup} ${_usrTmp}
        chmod 02755 ${_usrTmp}
      fi
      find ${_usrTmp} -mtime +0 -exec rm -rf {} \; &> /dev/null
      _ok_update_user
      _enable_chattr ${_usrLtd}
    fi
  fi
}
#
# Manage Access Paths.
_manage_sec_access_paths() {
#for _Domain in `find ${_Client}/ -maxdepth 1 -mindepth 1 -type l -printf %P\\n | sort`
for _Domain in `find ${_Client}/ -maxdepth 1 -mindepth 1 -type l | sort`; do
  _rawDom=$(echo ${_Domain} | cut -d'/' -f7 | awk '{ print $1}' 2>&1)
  _STATIC_FILES="${_pthParen_tUsr}/static/files/${_rawDom}.files"
  _STATIC_PRIVATE="${_pthParen_tUsr}/static/files/${_rawDom}.private"
  _PATH_DOM=$(readlink -n ${_Domain} 2>&1)
  _PATH_DOM=$(echo -n ${_PATH_DOM} | tr -d "\n" 2>&1)
  _RUBY_PATH="/opt/user/gems/${_usrLtd}"
  _NPM_PATH="/opt/user/npm/${_usrLtd}"
  _ALLD_DIR="${_ALLD_DIR}, '${_PATH_DOM}', '${_STATIC_FILES}', '${_STATIC_PRIVATE}', '${_RUBY_PATH}', '${_NPM_PATH}'"
  if [ -e "${_PATH_DOM}" ]; then
    _ALLD_NUM=$(( _ALLD_NUM += 1 ))
  fi
  echo Done for ${_Domain} at ${_Client}
done
}
#
# Manage Secondary Users.
_manage_sec() {
for _Client in `find ${_pthParen_tUsr}/clients/ -maxdepth 1 -mindepth 1 -type d | sort`; do
  _usrLtd=$(echo ${_Client} | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
  _usrLtd=${_usrLtd//[^a-zA-Z0-9]/}
  _usrLtd=$(echo -n ${_usrLtd} | tr A-Z a-z 2>&1)
  if [ ! -z "${_usrLtd}" ]; then
    _usrLtd="${_USER}.${_usrLtd}"
    echo "_usrLtd is == ${_usrLtd} == at _manage_sec"
    _ALLD_NUM="0"
    _ALLD_CTL="1"
    _ALLD_DIR="'${_Client}'"
    cd ${_Client}
    _manage_sec_access_paths
    #_ALLD_DIR="${_ALLD_DIR}, '/home/${_usrLtd}'"
    if [ "${_ALLD_NUM}" -ge "${_ALLD_CTL}" ]; then
      _add_user_if_not_exists
      echo Done for ${_Client} at ${_pthParen_tUsr}
    else
      echo Empty ${_Client} at ${_pthParen_tUsr} - deleting now
      if [ -e "${_Client}" ]; then
        rmdir ${_Client}
      fi
    fi
  fi
done
}
#
# Update local INI for PHP CLI on the Aegir Satellite Instance.
_php_cli_local_ini_update() {
  _U_HD="${_dscUsr}/.drush"
  _U_TP="${_dscUsr}/.tmp"
  _U_II="${_U_HD}/php.ini"
  _PHP_CLI_UPDATE=NO
  _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_DRUSH_FILE} 2>&1)
  _PHP_V="83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
      && [ ! -e "${_U_HD}/.ctrl.php${e}.${_xSrl}.pid" ]; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
    || [ ! -e "${_U_II}" ] \
    || [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
    mkdir -p ${_U_TP}
    touch ${_U_TP}
    find ${_U_TP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
    mkdir -p ${_U_HD}
    chown ${_USER}:${_usrGroup} ${_U_TP}
    chown ${_USER}:${_usrGroup} ${_U_HD}
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
        ${_dscUsr}:           \
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
      echo > ${_U_HD}/.ctrl.php${_U_INI}.${_xSrl}.pid
      echo > ${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid
    fi
    chattr +i ${_U_II}
  fi
}
#
# Update PHP-CLI for Drush.
_php_cli_drush_update() {
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="${_dscUsr}/tools/drush/${1}"
  else
    _DRUSH_FILE="${_dscUsr}/tools/drush/drush.php"
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
    _DRUSH_HOSTING_DISPATCH_CMD="${_T_CLI}/php ${_dscUsr}/tools/drush/drush.php @hostmaster hosting-dispatch"
    if [ -e "${_dscUsr}/aegir.sh" ]; then
      rm -f ${_dscUsr}/aegir.sh
    fi
    touch ${_dscUsr}/aegir.sh
    echo -e "#!/bin/bash\n\nPATH=.:${_T_CLI}:/usr/sbin:/usr/bin:/sbin:/bin\n \
      \n${_DRUSH_HOSTING_DISPATCH_CMD} \
      \ntouch ${_dscUsr}/${_USER}-task.done" \
      | fmt -su -w 2500 | tee -a ${_dscUsr}/aegir.sh >/dev/null 2>&1
    chown ${_USER}:${_usrGroup} ${_dscUsr}/aegir.sh &> /dev/null
    chmod 0700 ${_dscUsr}/aegir.sh &> /dev/null
  fi
  echo OK > ${_dscUsr}/static/control/.ctrl.cli.${_xSrl}.pid
}

#
# Set default FPM workers.
_satellite_default_fpm_workers() {
  _count_cpu

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
  else
    _PHP_FPM_TIMEOUT=180
  fi

  if [ -e "/root/.dev.server.cnf" ]; then
    echo "DEBUG: _PHP_FPM_TIMEOUT is ${_PHP_FPM_TIMEOUT}" >>/var/backups/ltd/log/users-${_NOW}.log
  fi
}

#
# Tune FPM workers.
_satellite_tune_fpm_workers() {
  _satellite_default_fpm_workers

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
    if [ -e "${_dscUsr}/log/cores.txt" ]; then
      _CLIENT_CORES=$(cat ${_dscUsr}/log/cores.txt 2>&1)
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
_disable_newrelic() {
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
_enable_newrelic() {
  _LOC_NEW_RELIC_KEY=$(cat ${_dscUsr}/static/control/newrelic.info 2>&1)
  _LOC_NEW_RELIC_KEY=${_LOC_NEW_RELIC_KEY//[^0-9a-zA-Z]/}
  _LOC_NEW_RELIC_KEY=$(echo -n ${_LOC_NEW_RELIC_KEY} | tr -d "\n" 2>&1)
  if [ -z "${_LOC_NEW_RELIC_KEY}" ]; then
    _disable_newrelic $1 $2 $3
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
_switch_newrelic() {
  _isPhp="$1"
  _isPhp=${_isPhp//[^0-9]/}
  _isUsr="$2"
  _isUsr=${_isUsr//[^a-z0-9]/}
  _isRld="$3"
  _isRld=${_isRld//[^0-1]/}
  if [ ! -z "${_isPhp}" ] && [ ! -z "${_isUsr}" ] && [ ! -z "${_isRld}" ]; then
    if [ -e "${_dscUsr}/static/control/newrelic.info" ]; then
      _enable_newrelic $1 $2 $3
    else
      _disable_newrelic $1 $2 $3
    fi
  fi
}
#
# Update web user.
_satellite_web_user_update() {
  _isTest="${_WEB}"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
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
      _isTest="$1"
      _isTest=${_isTest//[^a-z0-9]/}
      if [ ! -z "${_isTest}" ]; then
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
          /hdd:           \
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
          ${_dscUsr}/aegir:          \
          ${_dscUsr}/backup-exports: \
          ${_dscUsr}/distro:         \
          ${_dscUsr}/platforms:      \
          ${_dscUsr}/static:         \
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
        echo > ${_T_HD}/.ctrl.php${_T_PV}.${_xSrl}.pid
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
_satellite_remove_web_user() {
  _isTest="${_WEB}"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
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
_satellite_create_web_user() {
  _isTest="${_WEB}"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
    _T_HD="/home/${_WEB}/.drush"
    _T_II="${_T_HD}/php.ini"
    _T_ID_EXISTS=$(getent passwd ${_WEB} 2>&1)
    if [ ! -z "${_T_ID_EXISTS}" ] && [ -e "${_T_II}" ]; then
      _satellite_web_user_update "$1"
    elif [ -z "${_T_ID_EXISTS}" ] || [ ! -e "${_T_II}" ]; then
      _satellite_remove_web_user "clean"
      adduser --force-badname --system --ingroup www-data --home /home/${_WEB} ${_WEB} &> /dev/null
      _satellite_web_user_update "$1"
    fi
  fi
}
#
# Add site specific socket config include.
_site_socket_inc_gen() {
  _unlAeg="${_dscUsr}/static/control/unlock-aegir-php.info"
  _mltFpm="${_dscUsr}/static/control/multi-fpm.info"
  _preFpm="${_dscUsr}/static/control/.prev-multi-fpm.info"
  _mltNgx="${_dscUsr}/static/control/.multi-nginx-fpm.pid"
  _fpmPth="${_dscUsr}/config/server_master/nginx/post.d"

  _hmFront=$(cat ${_dscUsr}/log/domain.txt 2>&1)
  _hmFront=$(echo -n ${_hmFront} | tr -d "\n" 2>&1)
  _hmstAls="${_dscUsr}/.drush/${_hmFront}.alias.drushrc.php"

  _hmstCli=$(cat ${_dscUsr}/log/cli.txt 2>&1)
  _hmstCli=$(echo -n ${_hmstCli} | tr -d "\n" 2>&1)

  if [ ! -e "${_hmstAls}" ]; then
    ln -s ${_dscUsr}/.drush/hostmaster.alias.drushrc.php ${_hmstAls}
  fi

  _PLACEHOLDER_TEST=$(grep "place.holder.dont.remove" ${_mltFpm} 2>&1)

  if [ ! -e "${_dscUsr}/log/no-lock-aegir-fpm.txt" ] \
    || [[ ! "${_PLACEHOLDER_TEST}" =~ "place.holder.dont.remove" ]]; then
    sed -i "s/^${_hmFront} .*//g" ${_mltFpm}
    wait
    sed -i "s/^place.holder.dont.remove .*//g" ${_mltFpm}
    wait
    _PHP_V="83 82 81 74"
    _phpFnd=NO
    for e in ${_PHP_V}; do
      if [ -x "/opt/php${e}/bin/php" ] && [ "${_phpFnd}" = "NO" ]; then
        if [ "${e}" = "83" ]; then
          _phpDot=8.3
        elif [ "${e}" = "82" ]; then
          _phpDot=8.2
        elif [ "${e}" = "81" ]; then
          _phpDot=8.1
        elif [ "${e}" = "74" ]; then
          _phpDot=7.4
        fi
        echo "place.holder.dont.remove ${_phpDot}" >> ${_mltFpm}
        _phpFnd=YES
      fi
    done
    sed -i "s/ *$//g; /^$/d" ${_mltFpm}
    wait
    touch ${_dscUsr}/log/no-lock-aegir-fpm.txt
    rm -f ${_dscUsr}/log/locked-aegir-fpm.txt
    touch ${_dscUsr}/log/unlocked-aegir-fpm.txt
    _mltFpmUpdateForce=YES
  fi

  if [ -x "/opt/php83/bin/php" ] && [ ! -e "/home/${_USER}.83.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  elif [ -x "/opt/php82/bin/php" ] && [ ! -e "/home/${_USER}.82.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  elif [ -x "/opt/php81/bin/php" ] && [ ! -e "/home/${_USER}.81.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  fi

  if [ -f "${_mltFpm}" ]; then
    chown ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control/*.info
    _mltFpmUpdate=NO
    if [ ! -f "${_preFpm}" ]; then
      rm -rf ${_preFpm}
      cp -af ${_mltFpm} ${_preFpm}
    fi
    _diffFpmTest=$(diff -w -B ${_mltFpm} ${_preFpm} 2>&1)
    if [ ! -z "${_diffFpmTest}" ]; then
      _mltFpmUpdate=YES
    fi
    if [ ! -f "${_mltNgx}" ] \
      || [ "${_mltFpmUpdate}" = "YES" ] \
      || [ "${_mltFpmUpdateForce}" = "YES" ]; then
      rm -f ${_fpmPth}/fpm_include_site_*
      IFS=$'\12'
      for p in `cat ${_mltFpm}`;do
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
          && [ -e "${_dscUsr}/.drush/${_SITE_NAME}.alias.drushrc.php" ] \
          && [ -e "/run/${_SOCKET_L_NAME}.fpm.socket" ]; then
          _fpmInc="${_fpmPth}/fpm_include_site_${_SITE_NAME}.inc"
          echo "if ( \$main_site_name = ${_SITE_NAME} ) {" > ${_fpmInc}
          echo "  set \$user_socket \"${_SOCKET_L_NAME}\";" >> ${_fpmInc}
          echo "}" >> ${_fpmInc}
        fi
      done
      touch ${_mltNgx}
      rm -rf ${_preFpm}
      cp -af ${_mltFpm} ${_preFpm}
      ### reload nginx
      service nginx reload &> /dev/null
    fi
  else
    if [ -f "${_mltNgx}" ]; then
      rm -f ${_mltNgx}
    fi
    if [ -f "${_preFpm}" ]; then
      rm -f ${_preFpm}
    fi
  fi
}
#
# Switch PHP Version.
_switch_php() {
  _PHP_CLI_UPDATE=NO
  _FORCE_FPM_SETUP=NO
  _NEW_FPM_SETUP=NO
  _T_CLI_VRN=""
  if [ -e "${_dscUsr}/static/control/fpm.info" ] \
    || [ -e "${_dscUsr}/static/control/cli.info" ] \
    || [ -e "${_dscUsr}/static/control/hhvm.info" ]; then
    echo "Custom FPM, HHVM or CLI settings for ${_USER} exist, running _switch_php checks"
    if [ ! -e "${_dscUsr}/log/un-chattr-ctrl.info" ]; then
      chattr -i ${_dscUsr}/static/control/fpm.info &> /dev/null
      chattr -i ${_dscUsr}/static/control/cli.info &> /dev/null
      chattr -i ${_dscUsr}/log/fpm.txt &> /dev/null
      chattr -i ${_dscUsr}/log/cli.txt &> /dev/null
      chattr -i ${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc &> /dev/null
      touch ${_dscUsr}/log/un-chattr-ctrl.info
    fi
    if [ ! -e "${_dscUsr}/static/control/.single-fpm.${_xSrl}.pid" ]; then
      rm -f ${_dscUsr}/static/control/.single-fpm*.pid
      echo OK > ${_dscUsr}/static/control/.single-fpm.${_xSrl}.pid
      _FORCE_FPM_SETUP=YES
    fi
    if [ -e "${_dscUsr}/static/control/cli.info" ]; then
      _T_CLI_VRN=$(cat ${_dscUsr}/static/control/cli.info 2>&1)
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
          || [ ! -e "${_dscUsr}/static/control/.ctrl.cli.${_xSrl}.pid" ]; then
          _PHP_CLI_UPDATE=YES
          _DRUSH_FILES="drush.php drush"
          for _df in ${_DRUSH_FILES}; do
            _php_cli_drush_update "${_df}"
          done
          if [ -x "${_T_CLI}/php" ]; then
            _php_cli_local_ini_update
            sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_T_CLI_VRN}/g" \
              /root/.${_USER}.octopus.cnf &> /dev/null
            wait
            echo ${_T_CLI_VRN} > ${_dscUsr}/log/cli.txt
            echo ${_T_CLI_VRN} > ${_dscUsr}/static/control/cli.info
            chown ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control/cli.info
          fi
        fi
      fi
    fi
    if [ -e "${_dscUsr}/static/control/hhvm.info" ]; then
      if [ -x "/usr/bin/hhvm" ] \
        && [ -e "/var/xdrago/conf/hhvm/init.d/hhvm.foo" ] \
        && [ -e "/var/xdrago/conf/hhvm/server.foo.ini" ]; then
        if [ ! -e "/opt/hhvm/server.${_USER}.ini" ] \
          || [ ! -e "/etc/init.d/hhvm.${_USER}" ] \
          || [ ! -e "/run/hhvm/${_USER}" ]  ; then
          ### create or update special system user if needed
          _satellite_create_web_user "hhvm"
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
          rm -f ${_dscUsr}/static/control/fpm.info
          ### update nginx configuration
          sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/g" \
            ${_dscUsr}/config/includes/nginx_vhost_common.conf
          wait
          sed -i "s/unix:.*fpm.socket;/unix:\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/g" \
            ${_dscUsr}/.drush/sys/provision/http/Provision/Config/Nginx/Inc/vhost_include.tpl.php
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
        _satellite_remove_web_user "hhvm"
        ### delete leftovers
        rm -f /opt/hhvm/server.${_USER}.ini
        rm -rf /run/hhvm/${_USER}
        rm -rf /var/log/hhvm/${_USER}
        ### update nginx configuration
        sed -i "s/\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/\/var\/run\/\$user_socket.fpm.socket;/g" \
          ${_dscUsr}/config/includes/nginx_vhost_common.conf
        wait
        sed -i "s/\/var\/run\/hhvm\/${_USER}\/hhvm.socket;/\/var\/run\/\$user_socket.fpm.socket;/g" \
          ${_dscUsr}/.drush/sys/provision/http/Provision/Config/Nginx/Inc/vhost_include.tpl.php
        wait
        ### reload nginx
        service nginx reload &> /dev/null
        ### create dummy control file to enable PHP-FPM again
        echo 7.4 > ${_dscUsr}/static/control/fpm.info
        chown ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control/fpm.info
        _FORCE_FPM_SETUP=YES
      fi
    fi
    sleep 5
    if [ ! -e "${_dscUsr}/static/control/hhvm.info" ] \
      && [ -e "${_dscUsr}/static/control/fpm.info" ] \
      && [ -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
      _PHP_FPM_MULTI=NO
      if [ -f "${_dscUsr}/static/control/multi-fpm.info" ] \
        && [ -d "${_dscUsr}/tools/le" ]; then
        _PHP_FPM_MULTI=YES
        if [ ! -e "${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid" ]; then
          rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
          echo OK > ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
          _FORCE_FPM_SETUP=YES
        fi
      else
        if [ -e "${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc" ]; then
          rm -f ${_dscUsr}/config/server_master/nginx/post.d/fpm_include_*
          rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
          service nginx reload &> /dev/null
        fi
      fi
      _T_FPM_VRN=$(cat ${_dscUsr}/static/control/fpm.info 2>&1)
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
        _FMP_D_INC="${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc"
        if [ "${_PHP_FPM_MULTI}" = "YES" ] \
          && [ -d "${_dscUsr}/tools/le" ]; then
          _PHP_M_V="83 82 81 80 74 73 72 71 70 56"
          _D_POOL="${_USER}.${_PHP_SV}"
          if [ ! -e "${_FMP_D_INC}" ]; then
            echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
            touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
            _NEW_FPM_SETUP=YES
          else
            _CHECK_FMP_D=$(grep "${_D_POOL}" ${_FMP_D_INC} 2>&1)
            if [[ "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]]; then
              echo "${_D_POOL} already set in ${_FMP_D_INC}"
            else
              echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
              echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
              touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
              _NEW_FPM_SETUP=YES
            fi
          fi
        else
          _PHP_M_V="${_PHP_SV}"
          rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
          rm -f ${_FMP_D_INC}
        fi
        if [ ! -z "${_T_FPM_VRN}" ] \
          && [ "${_NEW_FPM_SETUP}" = "YES" ]; then
          _satellite_tune_fpm_workers
          sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_T_FPM_VRN}/g" \
            /root/.${_USER}.octopus.cnf &> /dev/null
          wait
          echo ${_T_FPM_VRN} > ${_dscUsr}/log/fpm.txt
          if [ "${_PHP_FPM_MULTI}" = "NO" ]; then
            echo ${_T_FPM_VRN} > ${_dscUsr}/static/control/fpm.info
          fi
          chown ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control/fpm.info
          _PHP_OLD_SV=${_PHP_FPM_VERSION//[^0-9]/}
          _PHP_SV=${_T_FPM_VRN//[^0-9]/}
          if [ -z "${_PHP_SV}" ]; then
            _PHP_SV=74
          fi
          ### create or update special system user if needed
          _FMP_D_INC="${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc"
          if [ "${_PHP_FPM_MULTI}" = "YES" ] \
            && [ -d "${_dscUsr}/tools/le" ]; then
            _PHP_M_V="83 82 81 80 74 73 72 71 70 56"
            _D_POOL="${_USER}.${_PHP_SV}"
            if [ ! -e "${_FMP_D_INC}" ]; then
              echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
              touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
            else
              _CHECK_FMP_D=$(grep "${_D_POOL}" ${_FMP_D_INC} 2>&1)
              if [[ "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]]; then
                echo "${_D_POOL} already set in ${_FMP_D_INC}"
              else
                echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
                echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
                touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
              fi
            fi
          else
            _PHP_M_V="${_PHP_SV}"
            rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
            rm -f ${_FMP_D_INC}
          fi
          for m in ${_PHP_M_V}; do
            if [ -x "/opt/php${m}/bin/php" ]; then
              if [ "${_PHP_FPM_MULTI}" = "YES" ] \
                && [ -d "${_dscUsr}/tools/le" ]; then
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
                      || [ ! -e "/home/${_WEB}/.drush/.ctrl.php${m}.${_xSrl}.pid" ]; then
                      echo _OLD_PHP_IN_USE is ${_OLD_PHP_IN_USE} for ${_WEB} update
                      echo _NEW_PHP_TO_USE is ${m} for ${_WEB} update
                      _satellite_web_user_update "${m}"
                    fi
                  fi
                done
              else
                echo _NEW_PHP_TO_USE is ${m} for ${_WEB} create
                _satellite_create_web_user "${m}"
              fi
            fi
          done
          ### create or update special system user if needed
          if [ "${_PHP_FPM_MULTI}" = "YES" ] \
            && [ -d "${_dscUsr}/tools/le" ]; then
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
                && [ -d "${_dscUsr}/tools/le" ]; then
                _WEB="${_USER}.${m}.web"
                _POOL="${_USER}.${m}"
              else
                _WEB="${_USER}.web"
                _POOL="${_USER}"
              fi
              if [ "${_PHP_FPM_MULTI}" = "YES" ] \
                && [ -d "${_dscUsr}/tools/le" ]; then
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
              _switch_newrelic ${m} ${_POOL} 0
              _nrCheck=YES
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
_manage_site_drush_alias_mirror() {

  for _Alias in `find /home/${_USER}.ftp/.drush/*.alias.drushrc.php \
    -maxdepth 1 -type f | sort`; do
    _AliasFile=$(echo "${_Alias}" | cut -d'/' -f5 | awk '{ print $1}' 2>&1)
    if [ ! -e "${_pthParen_tUsr}/.drush/${_AliasFile}" ] \
      && [ ! -z "${_AliasFile}" ]; then
      rm -f /home/${_USER}.ftp/.drush/${_AliasFile}
    fi
  done

  if [ -e "/home/${_USER}.ftp/.drush/hm.alias.drushrc.php" ]; then
    rm -f /home/${_USER}.ftp/.drush/hm.alias.drushrc.php
  fi
  if [ -e "/home/${_USER}.ftp/.drush/self.alias.drushrc.php" ]; then
    rm -f /home/${_USER}.ftp/.drush/self.alias.drushrc.php
  fi
  if [ -e "${_dscUsr}/.drush/.alias.drushrc.php" ]; then
    rm -f ${_dscUsr}/.drush/.alias.drushrc.php
  fi

  _isAliasUpdate=NO
  for _Alias in `find ${_pthParen_tUsr}/.drush/*.alias.drushrc.php \
    -maxdepth 1 -type f | sort`; do
    ### echo Last_AliasName is ${_AliasName}
    _SiteDir=
    _SiteName=
    _AliasName=
    _AliasName=$(echo "${_Alias}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
    _AliasName=$(echo "${_AliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [ "${_AliasName}" = "hm" ] \
      || [ "${_AliasName}" = "none" ] \
      || [[ "${_AliasName}" =~ (^)"platform_" ]] \
      || [[ "${_AliasName}" =~ (^)"server_" ]] \
      || [[ "${_AliasName}" =~ (^)"self" ]] \
      || [[ "${_AliasName}" =~ (^)"hostmaster" ]] \
      || [ -z "${_AliasName}" ]; then
      _IS_SITE=NO
      _AliasName=
      _SiteName=
      _SiteDir=
    else
      _SiteName="${_AliasName}"
      echo _SiteName is "${_SiteName}"
      ### echo Last_SiteDir is "${_SiteDir}"
      _SiteDir=
      if [[ "${_SiteName}" =~ ".restore"($) ]]; then
        _IS_SITE=NO
        rm -f ${_pthParen_tUsr}/.drush/${_SiteName}.alias.drushrc.php
      else
        _SiteDir=$(cat ${_Alias} \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        if [ -e "${_SiteDir}/drushrc.php" ] \
          && [ -e "${_SiteDir}/files" ] \
          && [ -e "${_SiteDir}/private" ]; then
          echo _SiteDir is ${_SiteDir}
          echo
          _pthAliasMain="${_pthParen_tUsr}/.drush/${_SiteName}.alias.drushrc.php"
          _pthAliasCopy="/home/${_USER}.ftp/.drush/${_SiteName}.alias.drushrc.php"
          if [ ! -e "${_pthAliasCopy}" ]; then
            cp -af ${_pthAliasMain} ${_pthAliasCopy}
            chmod 440 ${_pthAliasCopy}
            _isAliasUpdate=YES
          else
            _DIFF_T=$(diff -w -B ${_pthAliasCopy} ${_pthAliasMain} 2>&1)
            if [ ! -z "${_DIFF_T}" ]; then
              cp -af ${_pthAliasMain} ${_pthAliasCopy}
              chmod 440 ${_pthAliasCopy}
              _isAliasUpdate=YES
            fi
          fi
        else
          rm -f ${_pthAliasCopy}
          echo "ZOMBIE ${_SiteDir} detected"
          echo "Moving GHOST ${_SiteName}.alias.drushrc.php to ${_pthParen_tUsr}/undo/"
          mv -f ${_pthParen_tUsr}/.drush/${_SiteName}.alias.drushrc.php ${_pthParen_tUsr}/undo/ &> /dev/null
          echo
        fi
      fi
    fi
  done
  if [ -x "/usr/bin/drush10" ]; then
    if [ "${_isAliasUpdate}" = "YES" ] \
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
_manage_user() {
  for _pthParen_tUsr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    if [ -e "${_pthParen_tUsr}/config/server_master/nginx/vhost.d" ] \
      && [ -e "${_pthParen_tUsr}/log/fpm.txt" ] \
      && [ ! -e "${_pthParen_tUsr}/log/proxied.pid" ] \
      && [ ! -e "${_pthParen_tUsr}/log/CANCELLED" ]; then
      _USER=""
      _USER=$(echo ${_pthParen_tUsr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
      echo "_USER is == ${_USER} == at _manage_user"
      _WEB="${_USER}.web"
      _dscUsr="/data/disk/${_USER}"
      _octInc="${_dscUsr}/config/includes"
      _octTpl="${_dscUsr}/.drush/sys/provision/http/Provision/Config/Nginx"
      usrDgn="${_dscUsr}/.drush/usr/drupalgeddon"
      if [ -e "${_dscUsr}/log/imported.pid" ] \
        && [ -e "${_dscUsr}/log/post-merge-fix.pid" ]; then
        [ -e "${_dscUsr}/log/imported.pid" ] && mv -f ${_dscUsr}/log/imported.pid ${_dscUsr}/src/
        [ -e "${_dscUsr}/log/exported.pid" ] && mv -f ${_dscUsr}/log/exported.pid ${_dscUsr}/src/
        [ -e "${_dscUsr}/log/hmpathfix.pid" ] && mv -f ${_dscUsr}/log/hmpathfix.pid ${_dscUsr}/src/
        [ -e "${_dscUsr}/log/post-merge-fix.pid" ] && mv -f ${_dscUsr}/log/post-merge-fix.pid ${_dscUsr}/src/
      fi
      if [ ! -e "${_dscUsr}/rector.php" ]; then
        rm -f ${_dscUsr}/*.php* &> /dev/null
        rm -f ${_dscUsr}/composer.lock &> /dev/null
        rm -f ${_dscUsr}/composer.json &> /dev/null
        rm -f -r ${_dscUsr}/vendor &> /dev/null
        rm -f -r ${_dscUsr}/static/vendor &> /dev/null
        rm -f -r ${_dscUsr}/.cache/composer &> /dev/null
        rm -f -r ${_dscUsr}/.config/composer &> /dev/null
        rm -f -r ${_dscUsr}/.composer &> /dev/null
      fi
      chmod 0440 ${_dscUsr}/.drush/*.php &> /dev/null
      chmod 0400 ${_dscUsr}/.drush/drushrc.php &> /dev/null
      chmod 0400 ${_dscUsr}/.drush/hm.alias.drushrc.php &> /dev/null
      chmod 0400 ${_dscUsr}/.drush/hostmaster*.php &> /dev/null
      chmod 0400 ${_dscUsr}/.drush/platform_*.php &> /dev/null
      chmod 0400 ${_dscUsr}/.drush/server_*.php &> /dev/null
      chmod 0710 ${_dscUsr}/.drush &> /dev/null
      find ${_dscUsr}/config/server_master \
        -type d -exec chmod 0700 {} \; &> /dev/null
      find ${_dscUsr}/config/server_master \
        -type f -exec chmod 0600 {} \; &> /dev/null
      chmod +rx ${_dscUsr}/config{,/server_master{,/nginx{,/passwords.d}}} &> /dev/null
      chmod +r ${_dscUsr}/config/server_master/nginx/passwords.d/* &> /dev/null
      if [ ! -e "${_dscUsr}/.tmp/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
        rm -rf ${_dscUsr}/.drush/cache
        mkdir -p ${_dscUsr}/.tmp
        touch ${_dscUsr}/.tmp
        find ${_dscUsr}/.tmp/ -mtime +0 -exec rm -rf {} \; &> /dev/null
        chown ${_USER}:${_usrGroup} ${_dscUsr}/.tmp &> /dev/null
        chmod 02755 ${_dscUsr}/.tmp &> /dev/null
        echo OK > ${_dscUsr}/.tmp/.ctrl.${_tRee}.${_xSrl}.pid
      fi
      if [ ! -e "${_dscUsr}/static/control/.ctrl.${_tRee}.${_xSrl}.pid" ] \
        && [ -e "/home/${_USER}.ftp/clients" ]; then
        mkdir -p ${_dscUsr}/static/control
        chmod 755 ${_dscUsr}/static/control
        if [ -e "/var/xdrago/conf/control-readme.txt" ]; then
          cp -af /var/xdrago/conf/control-readme.txt \
            ${_dscUsr}/static/control/README.txt &> /dev/null
          chmod 0644 ${_dscUsr}/static/control/README.txt
        fi
        chown -R ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control
        rm -f ${_dscUsr}/static/control/.ctrl.*
        echo OK > ${_dscUsr}/static/control/.ctrl.${_tRee}.${_xSrl}.pid
      fi
      if [ -e "${_dscUsr}/static/control/ssl-live-mode.info" ]; then
        if [ -e "${_dscUsr}/tools/le/.ctrl/ssl-demo-mode.pid" ]; then
          rm -f ${_dscUsr}/tools/le/.ctrl/ssl-demo-mode.pid
        fi
      fi
      if [ -e "/root/.${_USER}.octopus.cnf" ]; then
        source /root/.${_USER}.octopus.cnf
      fi
      _THIS_HM_PLR=$(cat ${_dscUsr}/.drush/hostmaster.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_PLR}/modules/path_alias_cache" ] \
        && [ -x "/opt/tools/drush/8/drush/drush.php" ]; then
        if [ -x "/opt/php56/bin/php" ]; then
          echo 5.6 > ${_dscUsr}/static/control/cli.info
        fi
      fi
      _nrCheck=
      _switch_php
      ### reload nginx
      ### service nginx reload &> /dev/null
      if [ -z ${_nrCheck} ]; then
        if [ -z ${_PHP_SV} ]; then
          _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
          if [ -z "${_PHP_SV}" ]; then
            _PHP_SV=74
          fi
        fi
        if [ -f "${_dscUsr}/static/control/multi-fpm.info" ]; then
          _PHP_M_V="83 82 81 80 74 73 72 71 70 56"
          for m in ${_PHP_M_V}; do
            if [ -x "/opt/php${m}/bin/php" ] \
              && [ -e "/opt/php${m}/etc/pool.d/${_USER}.${m}.conf" ]; then
              _switch_newrelic ${m} ${_USER}.${m} 1
            fi
          done
        else
          if [ -x "/opt/php${_PHP_SV}/bin/php" ] \
            && [ -e "/opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf" ]; then
            _switch_newrelic ${_PHP_SV} ${_USER} 1
          fi
        fi
      fi
      _site_socket_inc_gen
      if [ -e "${_pthParen_tUsr}/clients" ] && [ ! -z ${_USER} ]; then
        echo Managing Users for ${_pthParen_tUsr} Instance
        rm -rf ${_pthParen_tUsr}/clients/admin &> /dev/null
        rm -rf ${_pthParen_tUsr}/clients/omega8ccgmailcom &> /dev/null
        rm -rf ${_pthParen_tUsr}/clients/nocomega8cc &> /dev/null
        rm -rf ${_pthParen_tUsr}/clients/*/backups &> /dev/null
        symlinks -dr ${_pthParen_tUsr}/clients &> /dev/null
        if [ -d "/home/${_USER}.ftp" ]; then
          _disable_chattr ${_USER}.ftp
          symlinks -dr /home/${_USER}.ftp &> /dev/null
          echo >> ${_THIS_LTD_CONF}
          echo "[${_USER}.ftp]" >> ${_THIS_LTD_CONF}
          echo "path : ['/opt/user/npm/${_USER}.ftp', \
                        '/opt/user/gems/${_USER}.ftp', \
                        '${_dscUsr}/distro', \
                        '${_dscUsr}/static', \
                        '${_dscUsr}/backups', \
                        '${_dscUsr}/clients']" \
                        | fmt -su -w 2500 >> ${_THIS_LTD_CONF}
          _manage_site_drush_alias_mirror
          _manage_sec
          if [ -d "/home/${_USER}.ftp/clients" ]; then
            chown -R ${_USER}.ftp:${_usrGroup} /home/${_USER}.ftp/users
            chmod 700 /home/${_USER}.ftp/users
            chmod 600 /home/${_USER}.ftp/users/*
          fi
          if [ ! -L "/home/${_USER}.ftp/static" ]; then
            rm -f /home/${_USER}.ftp/{backups,clients,static}
            ln -sfn ${_dscUsr}/backups /home/${_USER}.ftp/backups
            ln -sfn ${_dscUsr}/clients /home/${_USER}.ftp/clients
            ln -sfn ${_dscUsr}/static  /home/${_USER}.ftp/static
          fi
          if [ ! -e "/home/${_USER}.ftp/.tmp/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
            rm -rf /home/${_USER}.ftp/.drush/cache
            rm -rf /home/${_USER}.ftp/.tmp
            mkdir -p /home/${_USER}.ftp/.tmp
            chown ${_USER}.ftp:${_usrGroup} /home/${_USER}.ftp/.tmp &> /dev/null
            chmod 700 /home/${_USER}.ftp/.tmp &> /dev/null
            echo OK > /home/${_USER}.ftp/.tmp/.ctrl.${_tRee}.${_xSrl}.pid
          fi
          _enable_chattr ${_USER}.ftp
          echo Done for ${_pthParen_tUsr}
        else
          echo Directory /home/${_USER}.ftp not available
        fi
        echo
      else
        echo Directory ${_pthParen_tUsr}/clients not available
      fi
      echo
    fi
  done
}

#
# Find correct IP.
_find_correct_ip() {
  if [ -e "/root/.found_correct_ipv4.cnf" ]; then
    _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>&1)
    _LOC_IP=$(echo -n ${_LOC_IP} | tr -d "\n" 2>&1)
  else
    _LOC_IP=$(curl ${_crlGet} https://api.ipify.org \
      | sed 's/[^0-9\.]//g' 2>&1)
    if [ -z "${_LOC_IP}" ]; then
      _LOC_IP=$(curl ${_crlGet} http://ipv4.icanhazip.com \
        | sed 's/[^0-9\.]//g' 2>&1)
    fi
    if [ ! -z "${_LOC_IP}" ]; then
      echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
    fi
  fi
}

#
# Restrict node if needed.
_fix_node_in_lshell_access() {
  _pthLog="/var/xdrago/log"
  if [ ! -e "${_pthLog}" ] && [ -e "/var/xdrago_wait/log" ]; then
    _pthLog="/var/xdrago_wait/log"
  fi
  if [ -e "/etc/lshell.conf" ]; then
    _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
    _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
      || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
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

if [ ! -e "/home/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
  chattr -i /home
  chmod 0711 /home
  chown root:root /home
  rm -f /home/.ctrl.*
  while IFS=':' read -r _login _pass _uid _gid _uname _homedir _shell; do
    if [[ "${_homedir}" = **/home/** ]]; then
      if [ -d "${_homedir}" ]; then
        chattr -i ${_homedir}
        chown ${_uid}:${_gid} ${_homedir} &> /dev/null
        if [ -d "${_homedir}/.ssh" ]; then
          chattr -i ${_homedir}/.ssh
          chown -R ${_uid}:${_gid} ${_homedir}/.ssh &> /dev/null
        fi
        if [ -d "${_homedir}/.tmp" ]; then
          chattr -i ${_homedir}/.tmp
          chown -R ${_uid}:${_gid} ${_homedir}/.tmp &> /dev/null
        fi
        if [ -d "${_homedir}/.drush" ]; then
          chattr +i ${_homedir}/.drush/usr
          chattr +i ${_homedir}/.drush/*.ini
          chattr +i ${_homedir}/.drush
        fi
        if [[ ! "${_login}" =~ ".ftp"($) ]] \
          && [[ ! "${_login}" =~ ".web"($) ]]; then
          chattr +i ${_homedir}
        fi
      fi
    fi
  done < /etc/passwd
  touch /home/.ctrl.${_tRee}.${_xSrl}.pid
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
  _count_cpu
  _find_fast_mirror_early
  find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
  if [ ! -e "${_pthLog}/node.manage.lshell.ctrl.${_tRee}.${_xSrl}.pid" ]; then
    _fix_node_in_lshell_access
    touch ${_pthLog}/node.manage.lshell.ctrl.${_tRee}.${_xSrl}.pid
  fi
  cat /var/xdrago/conf/lshell.conf > ${_THIS_LTD_CONF}
  _find_correct_ip
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
  _add_ltd_group_if_not_exists
  _kill_zombies >/var/backups/ltd/log/zombies-${_NOW}.log 2>&1
  _manage_user >/var/backups/ltd/log/users-${_NOW}.log 2>&1
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
      curl -s -A iCab "${_urlHmr}/helpers/websh.sh.txt" -o /bin/websh
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
