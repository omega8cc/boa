#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
_WEBG=www-data

###-------------SYSTEM-----------------###

enable_chattr () {
  if [ ! -z "$1" ] && [ -d "/home/$1" ] ; then
    if [ "$1" != "${_THIS_HM_USER}.ftp" ] ; then
      chattr +i /home/$1             &> /dev/null
    else
      chattr +i /home/$1/platforms   &> /dev/null
      chattr +i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.bazaar" ] ; then
      chattr +i /home/$1/.bazaar     &> /dev/null
    fi
    chattr +i /home/$1/.drush        &> /dev/null
    chattr +i /home/$1/.drush/*.ini  &> /dev/null
  fi
}

disable_chattr () {
  if [ ! -z "$1" ] && [ -d "/home/$1" ] ; then
    if [ "$1" != "${_THIS_HM_USER}.ftp" ] ; then
      chattr -i /home/$1             &> /dev/null
    else
      chattr -i /home/$1/platforms   &> /dev/null
      chattr -i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.bazaar" ] ; then
      chattr -i /home/$1/.bazaar     &> /dev/null
    fi
    chattr -i /home/$1/.drush        &> /dev/null
    chattr -i /home/$1/.drush/*.ini  &> /dev/null
  fi
}

run_drush4_cmd () {
  su -s /bin/bash - ${_THIS_HM_USER}.ftp -c "drush4 @${Dom} $1" &> /dev/null
}

run_drush6_hmr_cmd () {
  su -s /bin/bash - $_THIS_HM_USER -c "drush6 $1" &> /dev/null
}

run_drush4_nosilent_cmd () {
  su -s /bin/bash - ${_THIS_HM_USER}.ftp -c "drush4 @${Dom} $1"
}

run_drush6_nosilent_cmd () {
  su -s /bin/bash - ${_THIS_HM_USER}.ftp -c "drush6 cc drush" &> /dev/null
  rm -f -r $User/.tmp/cache
  su -s /bin/bash - ${_THIS_HM_USER}.ftp -c "drush6 @${Dom} $1"
}

check_if_required () {
  _REQ=YES
  _REI_TEST=$(run_drush6_nosilent_cmd "pmi $1 --fields=required_by")
  _REL_TEST=$(echo "$_REI_TEST" | grep "Required by")
  if [[ "$_REL_TEST" =~ "was not found" ]] ; then
    _REQ=NULL
    echo _REQ for $1 is $_REQ in $Dom == 0 == via $_REL_TEST
  else
    echo CTRL _REL_TEST _REQ for $1 is $_REQ in $Dom == 0 == via $_REL_TEST
    _REN_TEST=$(echo "$_REI_TEST" | grep "Required by.*:.*none")
    if [[ "$_REN_TEST" =~ "Required by" ]] ; then
      _REQ=NO
      echo _REQ for $1 is $_REQ in $Dom == 1 == via $_REN_TEST
    else
      echo CTRL _REN_TEST _REQ for $1 is $_REQ in $Dom == 1 == via $_REN_TEST
      _REM_TEST=$(echo "$_REI_TEST" | grep "Required by.*minimal")
      if [[ "$_REM_TEST" =~ "Required by" ]] ; then
        _REQ=NO
        echo _REQ for $1 is $_REQ in $Dom == 2 == via $_REM_TEST
      fi
      _RES_TEST=$(echo "$_REI_TEST" | grep "Required by.*standard")
      if [[ "$_RES_TEST" =~ "Required by" ]] ; then
        _REQ=NO
        echo _REQ for $1 is $_REQ in $Dom == 3 == via $_RES_TEST
      fi
      _RET_TEST=$(echo "$_REI_TEST" | grep "Required by.*testing")
      if [[ "$_RET_TEST" =~ "Required by" ]] ; then
        _REQ=NO
        echo _REQ for $1 is $_REQ in $Dom == 4 == via $_RET_TEST
      fi
      _REH_TEST=$(echo "$_REI_TEST" | grep "Required by.*hacked")
      if [[ "$_REH_TEST" =~ "Required by" ]] ; then
        _REQ=NO
        echo _REQ for $1 is $_REQ in $Dom == 5 == via $_REH_TEST
      fi
      _RED_TEST=$(echo "$_REI_TEST" | grep "Required by.*devel")
      if [[ "$_RED_TEST" =~ "Required by" ]] ; then
        _REQ=NO
        echo _REQ for $1 is $_REQ in $Dom == 6 == via $_RED_TEST
      fi
      _REW_TEST=$(echo "$_REI_TEST" | grep "Required by.*watchdog_live")
      if [[ "$_REW_TEST" =~ "Required by" ]] ; then
        _REQ=NO
        echo _REQ for $1 is $_REQ in $Dom == 7 == via $_REW_TEST
      fi
    fi
    Profile=$(drush4 vget ^install_profile$ | cut -d: -f2 | awk '{ print $1}' | sed "s/['\"]//g" | tr -d "\n" 2>&1)
    Profile=${Profile//[^a-z_]/}
    echo Profile is == $Profile ==
    if [ ! -z "$Profile" ] ; then
      _REP_TEST=$(echo "$_REI_TEST" | grep "Required by.*:.*$Profile")
      if [[ "$_REP_TEST" =~ "Required by" ]] ; then
        _REQ=NO
        echo _REQ for $1 is $_REQ in $Dom == 7 == via $_REP_TEST
      else
        echo CTRL _REP_TEST _REQ for $1 is $_REQ in $Dom == 7 == via $_REP_TEST
      fi
    fi
    _REA_TEST=$(echo "$_REI_TEST" | grep "Required by.*apps")
    if [[ "$_REA_TEST" =~ "Required by" ]] ; then
      _REQ=YES
      echo _REQ for $1 is $_REQ in $Dom == 8 == via $_REA_TEST
    fi
    _REF_TEST=$(echo "$_REI_TEST" | grep "Required by.*features")
    if [[ "$_REF_TEST" =~ "Required by" ]] ; then
      _REQ=YES
      echo _REQ for $1 is $_REQ in $Dom == 9 == via $_REF_TEST
    fi
  fi
}

check_if_skip () {
  for s in $_MODULES_SKIP; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ] ; then
      _SKIP=YES
      #echo $1 is whitelisted and will not be disabled in $Dom
    fi
  done
}

check_if_force () {
  for s in $_MODULES_FORCE; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ] ; then
      _FORCE=YES
      #echo $1 is blacklisted and will be forcefully disabled in $Dom
    fi
  done
}

disable_modules () {
  for m in $1; do
    _SKIP=NO
    _FORCE=NO
    if [ ! -z "$_MODULES_SKIP" ] ; then
      check_if_skip "$m"
    fi
    if [ ! -z "$_MODULES_FORCE" ] ; then
      check_if_force "$m"
    fi
    if [ "$_SKIP" = "NO" ] ; then
      _MODULE_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --type=module | grep \($m\)")
      if [[ "$_MODULE_TEST" =~ "($m)" ]] ; then
        if [ "$_FORCE" = "NO" ] ; then
          check_if_required "$m"
        else
          echo $m dependencies not checked in $Dom
          _REQ=FCE
        fi
        if [ "$_REQ" = "FCE" ] ; then
          run_drush4_cmd "dis $m -y"
          echo $m FCE disabled in $Dom
        elif [ "$_REQ" = "NO" ] ; then
          run_drush4_cmd "dis $m -y"
          echo $m disabled in $Dom
        elif [ "$_REQ" = "NULL" ] ; then
          echo $m is not used in $Dom
        else
          echo $m is required and can not be disabled in $Dom
        fi
      fi
    fi
  done
}

enable_modules () {
  for m in $1; do
    _MODULE_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --type=module | grep \($m\)")
    if [[ "$_MODULE_TEST" =~ "($m)" ]] ; then
      _DO_NOTHING=YES
    else
      run_drush4_cmd "en $m -y"
      echo $m enabled in $Dom
    fi
  done
}

fix_user_register_protection () {

  _PLR_CTRL_FILE="$Plr/sites/all/modules/boa_platform_control.ini"

  if [ -e "$User/static/control/enable_user_register_protection.info" ] && [ -e "/data/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
    cp -af /data/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
    chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
    chmod 0664 $_PLR_CTRL_FILE
  fi

  if [ -e "$_PLR_CTRL_FILE" ] ; then
    _ENABLE_USER_REGISTER_PROTECTION_TEST=$(grep "^enable_user_register_protection = TRUE" $_PLR_CTRL_FILE)
    if [[ "$_ENABLE_USER_REGISTER_PROTECTION_TEST" =~ "enable_user_register_protection = TRUE" ]] ; then
      _ENABLE_USER_REGISTER_PROTECTION=YES
    else
      _ENABLE_USER_REGISTER_PROTECTION=NO
    fi
    if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
      if [ "$_CLIENT_OPTION" = "POWER" ] ; then
        _DISABLE_USER_REGISTER_PROTECTION_TEST=$(grep "^disable_user_register_protection = TRUE" $_PLR_CTRL_FILE)
        if [[ "$_DISABLE_USER_REGISTER_PROTECTION_TEST" =~ "disable_user_register_protection = TRUE" ]] ; then
          _DISABLE_USER_REGISTER_PROTECTION=YES
        else
          _DISABLE_USER_REGISTER_PROTECTION=NO
        fi
      fi
    else
      _DISABLE_USER_REGISTER_PROTECTION_TEST=$(grep "^disable_user_register_protection = TRUE" $_PLR_CTRL_FILE)
      if [[ "$_DISABLE_USER_REGISTER_PROTECTION_TEST" =~ "disable_user_register_protection = TRUE" ]] ; then
        _DISABLE_USER_REGISTER_PROTECTION=YES
      else
        _DISABLE_USER_REGISTER_PROTECTION=NO
      fi
    fi
  else
    _ENABLE_USER_REGISTER_PROTECTION=NO
  fi

  if [ "$_ENABLE_USER_REGISTER_PROTECTION" = "NO" ] && [ -e "$User/static/control/enable_user_register_protection.info" ] ; then
    sed -i "s/.*enable_user_register_protection.*/enable_user_register_protection = TRUE/g" $_PLR_CTRL_FILE &> /dev/null
    _ENABLE_USER_REGISTER_PROTECTION=YES
  fi

  _DIR_CTRL_FILE="$Dir/modules/boa_site_control.ini"
  if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
    cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
    chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
    chmod 0664 $_DIR_CTRL_FILE
  fi

  if [ -e "$_DIR_CTRL_FILE" ] ; then
    _DISABLE_USER_REGISTER_PROTECTION_TEST=$(grep "^disable_user_register_protection = TRUE" $_DIR_CTRL_FILE)
    if [[ "$_DISABLE_USER_REGISTER_PROTECTION_TEST" =~ "disable_user_register_protection = TRUE" ]] ; then
      _DISABLE_USER_REGISTER_PROTECTION=YES
    else
      _DISABLE_USER_REGISTER_PROTECTION=NO
    fi
  else
    _DISABLE_USER_REGISTER_PROTECTION=NO
  fi

  if [ "$_DISABLE_USER_REGISTER_PROTECTION" = "NO" ] ; then
    Prm=$(drush4 vget ^user_register$ | cut -d: -f2 | awk '{ print $1}' | sed "s/['\"]//g" | tr -d "\n" 2>&1)
    Prm=${Prm//[^0-2]/}
    echo Prm user_register for $Dom is $Prm
    if [ "$_ENABLE_USER_REGISTER_PROTECTION" = "YES" ] ; then
      drush4 vset --always-set user_register 0 &> /dev/null
    else
      if [ "$Prm" = "1" ] || [ -z "$Prm" ] ; then
        drush4 vset --always-set user_register 2 &> /dev/null
      fi
      drush4 vset --always-set user_email_verification 1 &> /dev/null
    fi
  fi
}

fix_robots_txt () {
  if [ ! -e "$Dir/files/robots.txt" ] && [ ! -e "$Plr/profiles/hostmaster" ] && [ "$_STATUS" = "OK" ] ; then
    curl -L --max-redirs 10 -k -s --retry 3 --retry-delay 15 -A iCab "http://$Dom/robots.txt?nocache=1&noredis=1" -o $Dir/files/robots.txt
    if [ -e "$Dir/files/robots.txt" ] ; then
      echo >> $Dir/files/robots.txt
    fi
  fi
}

fix_boost_cache () {
  if [ -e "$Plr/cache" ] ; then
    rm -f -r $Plr/cache/*
    rm -f $Plr/cache/{.boost,.htaccess}
  else
    if [ -e "$Plr/sites/all/drush/drushrc.php" ] ; then
      mkdir -p $Plr/cache
    fi
  fi
  if [ -e "$Plr/cache" ] ; then
    chown ${_THIS_HM_USER}.ftp:www-data $Plr/cache
    chmod 02775 $Plr/cache
  fi
  if [ -f "$Plr/robots.txt" ] || [ -L "$Plr/robots.txt" ] ; then
    rm -f $Plr/robots.txt
  fi
}

fix_o_contrib_symlink () {
  if [ "$_O_CONTRIB" != "NO" ] && [ ! -e "$Plr/core" ] ; then
    symlinks -d $Plr/modules &> /dev/null
    if [ -e "$Plr/web.config" ] ; then
      if [ ! -e "$Plr/modules/o_contrib_seven" ] ; then
        ln -sf $_O_CONTRIB_SEVEN $Plr/modules/o_contrib_seven &> /dev/null
      fi
    else
      if [ -e "$Plr/modules/watchdog" ] ; then
        if [ -e "$Plr/modules/o_contrib" ] ; then
          rm -f $Plr/modules/o_contrib &> /dev/null
        fi
      else
        if [ ! -e "$Plr/modules/o_contrib" ] ; then
          ln -sf $_O_CONTRIB $Plr/modules/o_contrib &> /dev/null
        fi
      fi
    fi
  fi
}

sql_convert () {
  sudo -u ${_THIS_HM_USER}.ftp -H /opt/local/bin/sqlmagic convert to-${_SQL_CONVERT}
}

check_site_status () {
  _SITE_TEST=$(drush4 status 2>&1)
  if [[ "$_SITE_TEST" =~ "Error:" ]] || [[ "$_SITE_TEST" =~ "Drush was attempting to connect" ]] ; then
    _SITE_TEST_RESULT=ERROR
  else
    _SITE_TEST_RESULT=OK
  fi
  if [ "$_SITE_TEST_RESULT" = "OK" ] ; then
    _STATUS_TEST=$(run_drush4_nosilent_cmd "status | grep 'Drupal bootstrap.*:.*Successful'")
    if [[ "$_STATUS_TEST" =~ "Successful" ]] ; then
      _STATUS=OK
    else
      _STATUS=BROKEN
      echo "WARNING: THIS SITE IS BROKEN! $Dir"
    fi
  else
    _STATUS=BROKEN
    echo "WARNING: THIS SITE IS PROBABLY BROKEN! $Dir"
  fi
}

check_file_with_wildcard_path () {
  _WILDCARD_TEST=$(ls $1 2> /dev/null)
  if [ -z "$_WILDCARD_TEST" ] ; then
    _FILE_EXISTS=NO
  else
    _FILE_EXISTS=YES
  fi
}

write_solr_config () {
  # $1 is module
  # $2 is a path to solr.php
  if [ ! -z $1 ] && [ ! -z $2 ] && [ -e "${Dir}" ] ; then
    echo "Your SOLR core access details for ${Dom} site are as follows:"  > $2
    echo                                                                 >> $2
    echo "  Solr host ........: 127.0.0.1"                               >> $2
    echo "  Solr port ........: 8099"                                    >> $2
    echo "  Solr path ........: /solr/${_MD5H}.${Dom}.${_THIS_HM_USER}"  >> $2
    echo                                                                 >> $2
    echo "It has been auto-configured to work with latest version"       >> $2
    echo "of $1 module, but you need to add the module to"               >> $2
    echo "your site codebase before you will be able to use Solr."       >> $2
    echo                                                                 >> $2
    echo "To learn more please make sure to check the module docs at:"   >> $2
    echo                                                                 >> $2
    echo "https://drupal.org/project/$1"                                 >> $2
    chown ${_THIS_HM_USER}:users $2
    chmod 440 $2
  fi
}

update_solr () {
  # $1 is module
  # $2 is solr core path
  if [ ! -z $1 ] && [ ! -e "$2/conf/BOA-2.3.3.conf" ] && [ -e "/var/xdrago/conf/solr" ] && [ -e "$2/conf" ] ; then
    if [ "$1" = "apachesolr" ] ; then
      if [ -e "$Plr/modules/o_contrib_seven" ] ; then
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
    elif [ "$1" = "search_api_solr" ] && [ -e "$Plr/modules/o_contrib_seven" ] ; then
      cp -af /var/xdrago/conf/solr/search_api_solr/7/schema.xml $2/conf/
      cp -af /var/xdrago/conf/solr/search_api_solr/7/solrconfig.xml $2/conf/
      cp -af /var/xdrago/conf/solr/search_api_solr/7/solrcore.properties $2/conf/
      touch $2/conf/update-ok.txt
    fi
    if [ -e "$2/conf/update-ok.txt" ] ; then
      write_solr_config $1 ${Dir}/solr.php
      echo "Updated Solr with $1 for $2"
      touch $2/conf/BOA-2.3.3.conf
      if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ] ; then
        kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
        service jetty9 start &> /dev/null
      fi
    fi
  fi
}

add_solr () {
  # $1 is module
  # $2 is solr core path
  if [ ! -z $1 ] && [ ! -z $2 ] && [ -e "/var/xdrago/conf/solr" ] ; then
    if [ ! -e "$2" ] ; then
      cp -a /opt/solr4/core0 $2
      _REL_VERSION=`lsb_release -sc`
      CHAR="[:alnum:]"
      rkey=32
      if [ "$_REL_VERSION" = "wheezy" ] || [ "$_REL_VERSION" = "trusty" ] || [ "$_REL_VERSION" = "precise" ] || [ "$_REL_VERSION" = "oneiric" ] ; then
        _MD5H=`cat /dev/urandom | tr -cd "$CHAR" | head -c ${1:-$rkey} | openssl md5 | awk '{ print $2}' | tr -d "\n"`
      else
        _MD5H=`cat /dev/urandom | tr -cd "$CHAR" | head -c ${1:-$rkey} | openssl md5 | tr -d "\n"`
      fi
      sed -i "s/.*<core name=\"core0\" instanceDir=\"core0\" \/>.*/<core name=\"core0\" instanceDir=\"core0\" \/>\n<core name=\"${_MD5H}.${Dom}.${_THIS_HM_USER}\" instanceDir=\"${_THIS_HM_USER}.${Dom}\" \/>\n/g" /opt/solr4/solr.xml
      update_solr $1 $2
      echo "New Solr with $1 for $2 added"
    fi
  fi
}

delete_solr () {
  # $1 is solr core path
  if [ ! -z $1 ] && [ -e "/var/xdrago/conf/solr" ] && [ -e "$1/conf" ] ; then
    sed -i "s/.*instanceDir=\"${_THIS_HM_USER}.${Dom}\".*//g" /opt/solr4/solr.xml
    sed -i "/^$/d" /opt/solr4/solr.xml &> /dev/null
    rm -f -r $1
    rm -f ${Dir}/solr.php
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ] ; then
      kill -9 $(ps aux | grep '[j]etty9' | awk '{print $2}') &> /dev/null
      service jetty9 start &> /dev/null
    fi
    echo "Deleted Solr for $1"
  fi
}

check_solr () {
  # $1 is module
  # $2 is solr core path
  if [ ! -z $1 ] && [ ! -z $2 ] && [ -e "/var/xdrago/conf/solr" ] ; then
    echo "Checking Solr with $1 for $2"
    if [ ! -e "$2" ] ; then
      add_solr $1 $2
    else
      update_solr $1 $2
    fi
  fi
}

setup_solr () {

  _DIR_CTRL_FILE="$Dir/modules/boa_site_control.ini"
  _SOLR_DIR="/opt/solr4/${_THIS_HM_USER}.${Dom}"
  if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
    cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
    chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
    chmod 0664 $_DIR_CTRL_FILE
  fi

  ###
  ### Support for solr_custom_config directive
  ###
  if [ -e "$_DIR_CTRL_FILE" ] ; then
    _SOLR_CUSTOM_CONFIG_PRESENT=$(grep "solr_custom_config" $_DIR_CTRL_FILE)
    if [[ "$_SOLR_CUSTOM_CONFIG_PRESENT" =~ "solr_custom_config" ]] ; then
      _DO_NOTHING=YES
    else
      echo ";solr_custom_config = NO" >> $_DIR_CTRL_FILE
    fi
    _SOLR_CUSTOM_CONFIG_TEST=$(grep "^solr_custom_config = YES" $_DIR_CTRL_FILE)
    if [[ "$_SOLR_CUSTOM_CONFIG_TEST" =~ "solr_custom_config = YES" ]] ; then
      _SOLR_CUSTOM_CONFIG_RESULT=YES
      echo "Solr config for ${_SOLR_DIR} is protected"
    fi
  fi
  ###
  ### Support for solr_integration_module directive
  ###
  if [ -e "$_DIR_CTRL_FILE" ] ; then
    _SOLR_MODULE=""
    _SOLR_INTEGRATION_MODULE_PRESENT=$(grep "solr_integration_module" $_DIR_CTRL_FILE)
    if [[ "$_SOLR_INTEGRATION_MODULE_PRESENT" =~ "solr_integration_module" ]] ; then
      _DO_NOTHING=YES
    else
      echo ";solr_integration_module = NO" >> $_DIR_CTRL_FILE
    fi
    _APACHESOLR_MODULE_TEST=$(grep "^solr_integration_module = apachesolr" $_DIR_CTRL_FILE)
    if [[ "$_APACHESOLR_MODULE_TEST" =~ "solr_integration_module = apachesolr" ]] ; then
      _SOLR_MODULE=apachesolr
    fi
    _SEARCH_API_SOLR_MODULE_TEST=$(grep "^solr_integration_module = search_api_solr" $_DIR_CTRL_FILE)
    if [[ "$_SEARCH_API_SOLR_MODULE_TEST" =~ "solr_integration_module = search_api_solr" ]] ; then
      _SOLR_MODULE=search_api_solr
    fi
    if [ ! -z "$_SOLR_MODULE" ] ; then
      check_solr ${_SOLR_MODULE} ${_SOLR_DIR}
    else
      delete_solr ${_SOLR_DIR}
    fi
  fi
  ###
  ### Support for solr_update_config directive
  ###
  if [ -e "$_DIR_CTRL_FILE" ] ; then
    _SOLR_UPDATE_CONFIG_PRESENT=$(grep "solr_update_config" $_DIR_CTRL_FILE)
    if [[ "$_SOLR_UPDATE_CONFIG_PRESENT" =~ "solr_update_config" ]] ; then
      _DO_NOTHING=YES
    else
      echo ";solr_update_config = NO" >> $_DIR_CTRL_FILE
    fi
    _SOLR_UPDATE_CONFIG_TEST=$(grep "^solr_update_config = YES" $_DIR_CTRL_FILE)
    if [[ "$_SOLR_UPDATE_CONFIG_TEST" =~ "solr_update_config = YES" ]] ; then
      if [ "$_SOLR_CUSTOM_CONFIG_RESULT" = "YES" ] || [ -e "${_SOLR_DIR}/conf/BOA-2.3.3.conf" ] ; then
        _DO_NOTHING=YES
      else
        update_solr ${_SOLR_MODULE} ${_SOLR_DIR}
      fi
    fi
  fi
}

fix_modules () {
  if [ "$_MODULES_FIX" = "YES" ] ; then
    searchStringA="pressflow-5.23.50"
    case $Dir in
      *"$searchStringA"*) ;;
      *)
      if [ -e "$Dir/drushrc.php" ] ; then
        cd $Dir
        check_site_status
        if [ "$_STATUS" = "OK" ] ; then

          setup_solr
          fix_user_register_protection

          _AUTO_CONFIG_ADVAGG=NO
          if [ -e "$Plr/sites/all/modules/advagg" ] || [ -e "$Plr/modules/o_contrib/advagg" ] || [ -e "$Plr/modules/o_contrib_seven/advagg" ] ; then
            _MODULE_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --type=module | grep \(advagg\)")
            if [[ "$_MODULE_TEST" =~ "(advagg)" ]] ; then
              _AUTO_CONFIG_ADVAGG=YES
            fi
          fi
          if [ "$_AUTO_CONFIG_ADVAGG" = "YES" ] ; then
            if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
              chmod 0664 $_DIR_CTRL_FILE
            fi
            if [ -e "$_DIR_CTRL_FILE" ] ; then
              _AUTO_CONFIG_ADVAGG_PRESENT=$(grep "advagg_auto_configuration" $_DIR_CTRL_FILE)
              _AUTO_CONFIG_ADVAGG_TEST=$(grep "^advagg_auto_configuration = TRUE" $_DIR_CTRL_FILE)
              if [[ "$_AUTO_CONFIG_ADVAGG_TEST" =~ "advagg_auto_configuration = TRUE" ]] ; then
                _DO_NOTHING=YES
              else
                ###
                ### Do this only for the site level ini file.
                ###
                if [[ "$_AUTO_CONFIG_ADVAGG_PRESENT" =~ "advagg_auto_configuration" ]] ; then
                  sed -i "s/.*advagg_auto_configuration.*/advagg_auto_configuration = TRUE/g" $_DIR_CTRL_FILE &> /dev/null
                else
                  echo "advagg_auto_configuration = TRUE" >> $_DIR_CTRL_FILE
                fi
              fi
            fi
          else
            if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
              chmod 0664 $_DIR_CTRL_FILE
            fi
            if [ -e "$_DIR_CTRL_FILE" ] ; then
              _AUTO_CONFIG_ADVAGG_PRESENT=$(grep "advagg_auto_configuration" $_DIR_CTRL_FILE)
              _AUTO_CONFIG_ADVAGG_TEST=$(grep "^advagg_auto_configuration = FALSE" $_DIR_CTRL_FILE)
              if [[ "$_AUTO_CONFIG_ADVAGG_TEST" =~ "advagg_auto_configuration = FALSE" ]] ; then
                _DO_NOTHING=YES
              else
                if [[ "$_AUTO_CONFIG_ADVAGG_PRESENT" =~ "advagg_auto_configuration" ]] ; then
                  sed -i "s/.*advagg_auto_configuration.*/advagg_auto_configuration = FALSE/g" $_DIR_CTRL_FILE &> /dev/null
                else
                  echo ";advagg_auto_configuration = FALSE" >> $_DIR_CTRL_FILE
                fi
              fi
            fi
          fi

          _AUTO_CONFIG_PURGE_EXPIRE=NO
          if [ -e "$Plr/modules/o_contrib/purge" ] || [ -e "$Plr/modules/o_contrib_seven/purge" ] ; then
            _MODULE_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --type=module | grep \(purge\)")
            if [[ "$_MODULE_TEST" =~ "(purge)" ]] ; then
              _AUTO_CONFIG_PURGE_EXPIRE=YES
            fi
          fi
          if [ "$_AUTO_CONFIG_PURGE_EXPIRE" = "YES" ] ; then
            if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
              chmod 0664 $_DIR_CTRL_FILE
            fi
            if [ -e "$_DIR_CTRL_FILE" ] ; then
              _AUTO_CONFIG_PURGE_EXPIRE_PRESENT=$(grep "purge_expire_auto_configuration" $_DIR_CTRL_FILE)
              _AUTO_CONFIG_PURGE_EXPIRE_TEST=$(grep "^purge_expire_auto_configuration = TRUE" $_DIR_CTRL_FILE)
              if [[ "$_AUTO_CONFIG_PURGE_EXPIRE_TEST" =~ "purge_expire_auto_configuration = TRUE" ]] ; then
                _DO_NOTHING=YES
              else
                ###
                ### Do this only for the site level ini file.
                ###
                if [[ "$_AUTO_CONFIG_PURGE_EXPIRE_PRESENT" =~ "purge_expire_auto_configuration" ]] ; then
                  sed -i "s/.*purge_expire_auto_configuration.*/purge_expire_auto_configuration = TRUE/g" $_DIR_CTRL_FILE &> /dev/null
                else
                  echo "purge_expire_auto_configuration = TRUE" >> $_DIR_CTRL_FILE
                fi
              fi
            fi
          else
            if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
              chmod 0664 $_DIR_CTRL_FILE
            fi
            if [ -e "$_DIR_CTRL_FILE" ] ; then
              _AUTO_CONFIG_PURGE_EXPIRE_PRESENT=$(grep "purge_expire_auto_configuration" $_DIR_CTRL_FILE)
              _AUTO_CONFIG_PURGE_EXPIRE_TEST=$(grep "^purge_expire_auto_configuration = FALSE" $_DIR_CTRL_FILE)
              if [[ "$_AUTO_CONFIG_PURGE_EXPIRE_TEST" =~ "purge_expire_auto_configuration = FALSE" ]] ; then
                _DO_NOTHING=YES
              else
                if [[ "$_AUTO_CONFIG_PURGE_EXPIRE_PRESENT" =~ "purge_expire_auto_configuration" ]] ; then
                  sed -i "s/.*purge_expire_auto_configuration.*/purge_expire_auto_configuration = FALSE/g" $_DIR_CTRL_FILE &> /dev/null
                else
                  echo ";purge_expire_auto_configuration = FALSE" >> $_DIR_CTRL_FILE
                fi
              fi
            fi
          fi

          if [ -e "$Plr/modules/o_contrib_seven" ] ; then
            _PRIV_TEST=$(drush4 vget ^file_default_scheme$ 2>&1)
            if [[ "$_PRIV_TEST" =~ "No matching variable" ]] ; then
              _PRIV_TEST_RESULT=NONE
            else
              _PRIV_TEST_RESULT=OK
            fi
            _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS=NO
            if [ "$_PRIV_TEST_RESULT" = "OK" ] ; then
              Pri=$(drush4 vget ^file_default_scheme$ | cut -d: -f2 | awk '{ print $1}' | sed "s/['\"]//g" | tr -d "\n" 2>&1)
              Pri=${Pri//[^a-z]/}
              if [ "$Pri" = "private" ] || [ "$Pri" = "public" ] ; then
                echo Pri file_default_scheme for $Dom is $Pri
              fi
              if [ "$Pri" = "private" ] ; then
                _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS=YES
              fi
            fi
            if [ "$_AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS" = "YES" ] ; then
              if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
                cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
                chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
                chmod 0664 $_DIR_CTRL_FILE
              fi
              if [ -e "$_DIR_CTRL_FILE" ] ; then
                _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST=$(grep "^allow_private_file_downloads = TRUE" $_DIR_CTRL_FILE)
                if [[ "$_AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST" =~ "allow_private_file_downloads = TRUE" ]] ; then
                  _DO_NOTHING=YES
                else
                  ###
                  ### Do this only for the site level ini file.
                  ###
                  sed -i "s/.*allow_private_file_downloads.*/allow_private_file_downloads = TRUE/g" $_DIR_CTRL_FILE &> /dev/null
                fi
              fi
            else
              if [ -e "/data/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
                cp -af /data/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
                chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
                chmod 0664 $_DIR_CTRL_FILE
              fi
              if [ -e "$_DIR_CTRL_FILE" ] ; then
                _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST=$(grep "^allow_private_file_downloads = FALSE" $_DIR_CTRL_FILE)
                if [[ "$_AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST" =~ "allow_private_file_downloads = FALSE" ]] ; then
                  _DO_NOTHING=YES
                else
                  sed -i "s/.*allow_private_file_downloads.*/allow_private_file_downloads = FALSE/g" $_DIR_CTRL_FILE &> /dev/null
                fi
              fi
            fi
          fi

          _AUTO_DETECT_FACEBOOK_INTEGRATION=NO
          if [ -e "$Plr/sites/all/modules/fb/fb_settings.inc" ] || [ -e "$Plr/sites/all/modules/contrib/fb/fb_settings.inc" ] ; then
            _AUTO_DETECT_FACEBOOK_INTEGRATION=YES
          else
            check_file_with_wildcard_path "$Plr/profiles/*/modules/fb/fb_settings.inc"
            if [ "$_FILE_EXISTS" = "YES" ] ; then
              _AUTO_DETECT_FACEBOOK_INTEGRATION=YES
            else
              check_file_with_wildcard_path "$Plr/profiles/*/modules/contrib/fb/fb_settings.inc"
              if [ "$_FILE_EXISTS" = "YES" ] ; then
                _AUTO_DETECT_FACEBOOK_INTEGRATION=YES
              fi
            fi
          fi
          if [ "$_AUTO_DETECT_FACEBOOK_INTEGRATION" = "YES" ] ; then
            if [ -e "/data/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_FACEBOOK_INTEGRATION_TEST=$(grep "^auto_detect_facebook_integration = TRUE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_FACEBOOK_INTEGRATION_TEST" =~ "auto_detect_facebook_integration = TRUE" ]] ; then
                _DO_NOTHING=YES
              else
                ###
                ### Do this only for the platform level ini file, so the site level ini file can disable
                ### this check by setting it explicitly to auto_detect_facebook_integration = FALSE
                ###
                sed -i "s/.*auto_detect_facebook_integration.*/auto_detect_facebook_integration = TRUE/g" $_PLR_CTRL_FILE &> /dev/null
              fi
            fi
          else
            if [ -e "/data/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_FACEBOOK_INTEGRATION_TEST=$(grep "^auto_detect_facebook_integration = FALSE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_FACEBOOK_INTEGRATION_TEST" =~ "auto_detect_facebook_integration = FALSE" ]] ; then
                _DO_NOTHING=YES
              else
                sed -i "s/.*auto_detect_facebook_integration.*/auto_detect_facebook_integration = FALSE/g" $_PLR_CTRL_FILE &> /dev/null
              fi
            fi
          fi

          _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=NO
          if [ -e "$Plr/sites/all/modules/domain/settings.inc" ] || [ -e "$Plr/sites/all/modules/contrib/domain/settings.inc" ] ; then
            _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
          else
            check_file_with_wildcard_path "$Plr/profiles/*/modules/domain/settings.inc"
            if [ "$_FILE_EXISTS" = "YES" ] ; then
              _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
            else
              check_file_with_wildcard_path "$Plr/profiles/*/modules/contrib/domain/settings.inc"
              if [ "$_FILE_EXISTS" = "YES" ] ; then
                _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
              fi
            fi
          fi
          if [ "$_AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION" = "YES" ] ; then
            if [ -e "/data/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST=$(grep "^auto_detect_domain_access_integration = TRUE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST" =~ "auto_detect_domain_access_integration = TRUE" ]] ; then
                _DO_NOTHING=YES
              else
                ###
                ### Do this only for the platform level ini file, so the site level ini file can disable
                ### this check by setting it explicitly to auto_detect_domain_access_integration = FALSE
                ###
                sed -i "s/.*auto_detect_domain_access_integration.*/auto_detect_domain_access_integration = TRUE/g" $_PLR_CTRL_FILE &> /dev/null
              fi
            fi
          else
            if [ -e "/data/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /data/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST=$(grep "^auto_detect_domain_access_integration = FALSE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST" =~ "auto_detect_domain_access_integration = FALSE" ]] ; then
                _DO_NOTHING=YES
              else
                sed -i "s/.*auto_detect_domain_access_integration.*/auto_detect_domain_access_integration = FALSE/g" $_PLR_CTRL_FILE &> /dev/null
              fi
            fi
          fi

          ###
          ### Add new INI variables if missing
          ###
          if [ -e "$_PLR_CTRL_FILE" ] ; then
            _VAR_IF_PRESENT=$(grep "session_cookie_ttl" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "session_cookie_ttl" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";session_cookie_ttl = 86400" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "session_gc_eol" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "session_gc_eol" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";session_gc_eol = 86400" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_use_modern" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_use_modern" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_use_modern = TRUE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_flush_forced_mode" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_flush_forced_mode" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_flush_forced_mode = TRUE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_lock_enable" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_lock_enable" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_lock_enable = TRUE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_exclude_bins" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_exclude_bins" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_exclude_bins = FALSE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "speed_booster_anon_cache_ttl" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "speed_booster_anon_cache_ttl" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";speed_booster_anon_cache_ttl = 10" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "disable_drupal_page_cache" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "disable_drupal_page_cache" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";disable_drupal_page_cache = FALSE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "allow_private_file_downloads" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "allow_private_file_downloads" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";allow_private_file_downloads = FALSE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "entitycache_dont_enable" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "entitycache_dont_enable" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";entitycache_dont_enable = FALSE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "views_cache_bully_dont_enable" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "views_cache_bully_dont_enable" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";views_cache_bully_dont_enable = FALSE" >> $_PLR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "views_content_cache_dont_enable" $_PLR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "views_content_cache_dont_enable" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";views_content_cache_dont_enable = FALSE" >> $_PLR_CTRL_FILE
            fi
          fi
          if [ -e "$_DIR_CTRL_FILE" ] ; then
             _VAR_IF_PRESENT=$(grep "session_cookie_ttl" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "session_cookie_ttl" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";session_cookie_ttl = 86400" >> $_DIR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "session_gc_eol" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "session_gc_eol" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";session_gc_eol = 86400" >> $_DIR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_use_modern" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_use_modern" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_use_modern = TRUE" >> $_DIR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_flush_forced_mode" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_flush_forced_mode" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_flush_forced_mode = TRUE" >> $_DIR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_lock_enable" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_lock_enable" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_lock_enable = TRUE" >> $_DIR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "redis_exclude_bins" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "redis_exclude_bins" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";redis_exclude_bins = FALSE" >> $_DIR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "speed_booster_anon_cache_ttl" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "speed_booster_anon_cache_ttl" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";speed_booster_anon_cache_ttl = 10" >> $_DIR_CTRL_FILE
            fi
            _VAR_IF_PRESENT=$(grep "disable_drupal_page_cache" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "disable_drupal_page_cache" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";disable_drupal_page_cache = FALSE" >> $_DIR_CTRL_FILE
            fi
             _VAR_IF_PRESENT=$(grep "allow_private_file_downloads" $_DIR_CTRL_FILE)
            if [[ "$_VAR_IF_PRESENT" =~ "allow_private_file_downloads" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";allow_private_file_downloads = FALSE" >> $_DIR_CTRL_FILE
            fi
          fi

          if [ -e "$_PLR_CTRL_FILE" ] ; then
            _ENTITYCACHE_DONT_ENABLE_TEST=$(grep "^entitycache_dont_enable = TRUE" $_PLR_CTRL_FILE)
            if [[ "$_ENTITYCACHE_DONT_ENABLE_TEST" =~ "entitycache_dont_enable = TRUE" ]] ; then
              _ENTITYCACHE_DONT_ENABLE=YES
            else
              _ENTITYCACHE_DONT_ENABLE=NO
            fi
          else
            _ENTITYCACHE_DONT_ENABLE=NO
          fi

          if [ -e "$_PLR_CTRL_FILE" ] ; then
            _VIEWS_CACHE_BULLY_DONT_ENABLE_TEST=$(grep "^views_cache_bully_dont_enable = TRUE" $_PLR_CTRL_FILE)
            if [[ "$_VIEWS_CACHE_BULLY_DONT_ENABLE_TEST" =~ "views_cache_bully_dont_enable = TRUE" ]] ; then
              _VIEWS_CACHE_BULLY_DONT_ENABLE=YES
            else
              _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
            fi
          else
            _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
          fi

          if [ -e "$_PLR_CTRL_FILE" ] ; then
            _VIEWS_CONTENT_CACHE_DONT_ENABLE_TEST=$(grep "^views_content_cache_dont_enable = TRUE" $_PLR_CTRL_FILE)
            if [[ "$_VIEWS_CONTENT_CACHE_DONT_ENABLE_TEST" =~ "views_content_cache_dont_enable = TRUE" ]] ; then
              _VIEWS_CONTENT_CACHE_DONT_ENABLE=YES
            else
              _VIEWS_CONTENT_CACHE_DONT_ENABLE=NO
            fi
          else
            _VIEWS_CONTENT_CACHE_DONT_ENABLE=NO
          fi

          if [ -e "$Plr/profiles/hostmaster" ] && [ ! -f "$Plr/profiles/hostmaster/modules-fix.info" ] ; then
            run_drush6_hmr_cmd "@hostmaster dis cache syslog dblog -y"
            echo "modules-fixed" > $Plr/profiles/hostmaster/modules-fix.info
            chown $_THIS_HM_USER:users $Plr/profiles/hostmaster/modules-fix.info
          elif [ -e "$Plr/modules/o_contrib" ] ; then
            if [ ! -e "$Plr/modules/user" ] || [ ! -e "$Plr/sites/all/modules" ] || [ ! -e "$Plr/profiles" ] ; then
              echo "WARNING: THIS PLATFORM IS BROKEN! $Plr"
            elif [ ! -e "$Plr/modules/path_alias_cache" ] ; then
              echo "WARNING: THIS PLATFORM IS NOT A VALID PRESSFLOW PLATFORM! $Plr"
            elif [ -e "$Plr/modules/path_alias_cache" ] && [ -e "$Plr/modules/user" ] ; then
              disable_modules "$_MODULES_OFF_SIX"
              enable_modules "$_MODULES_ON_SIX"
              run_drush4_cmd "sqlq \"UPDATE system SET weight = '-1' WHERE type = 'module' AND name = 'path_alias_cache'\""
            fi
          elif [ -e "$Plr/modules/o_contrib_seven" ] ; then
            if [ ! -e "$Plr/modules/user" ] || [ ! -e "$Plr/sites/all/modules" ] || [ ! -e "$Plr/profiles" ] ; then
              echo "WARNING: THIS PLATFORM IS BROKEN! $Plr"
            else
              disable_modules "$_MODULES_OFF_SEVEN"
              if [ "$_ENTITYCACHE_DONT_ENABLE" = "NO" ] ; then
                enable_modules "entitycache"
              fi
              enable_modules "$_MODULES_ON_SEVEN"
            fi
          fi
          if [ ! -e "$Dir/modules/commerce_ubercart_check.info" ] ; then
            _COMMERCE_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --no-core --type=module | grep \(commerce\)")
            _UBERCART_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --no-core --type=module | grep \(uc_cart\)")
            if [[ "$_COMMERCE_TEST" =~ "Commerce" ]] || [[ "$_UBERCART_TEST" =~ "Ubercart" ]] ; then
              disable_modules "views_cache_bully"
            fi
            echo OK > $Dir/modules/commerce_ubercart_check.info
            chown $_THIS_HM_USER:users $Dir/modules/commerce_ubercart_check.info
            chmod 0664 $Dir/modules/commerce_ubercart_check.info
          fi
          if [ -e "$User/static/control/enable_views_cache_bully.info" ] || [ -e "$User/static/control/enable_views_content_cache.info" ] ; then
            _VIEWS_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --no-core --type=module | grep \(views\)")
            if [ -e "$User/static/control/enable_views_content_cache.info" ] ; then
              _CTOOLS_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --no-core --type=module | grep \(ctools\)")
            fi
            if [[ "$_VIEWS_TEST" =~ "Views" ]] && [ ! -e "$Plr/profiles/hostmaster" ] ; then
              if [ "$_VIEWS_CACHE_BULLY_DONT_ENABLE" = "NO" ] && [ -e "$User/static/control/enable_views_cache_bully.info" ] ; then
                if [ -e "$Plr/modules/o_contrib_seven/views_cache_bully" ] || [ -e "$Plr/modules/o_contrib/views_cache_bully" ] ; then
                  enable_modules "views_cache_bully"
                fi
              fi
              if [[ "$_CTOOLS_TEST" =~ "Chaos" ]] && [ "$_VIEWS_CONTENT_CACHE_DONT_ENABLE" = "NO" ] && [ -e "$User/static/control/enable_views_content_cache.info" ] ; then
                if [ -e "$Plr/modules/o_contrib_seven/views_content_cache" ] || [ -e "$Plr/modules/o_contrib/views_content_cache" ] ; then
                  enable_modules "views_content_cache"
                fi
              fi
            fi
          fi

          ###
          ### Detect permissions fix overrides, if set per platform.
          ###
          _DONT_TOUCH_PERMISSIONS=NO
          if [ -e "$_PLR_CTRL_FILE" ] ; then
            _FIX_PERMISSIONS_PRESENT=$(grep "fix_files_permissions_daily" $_PLR_CTRL_FILE)
            if [[ "$_FIX_PERMISSIONS_PRESENT" =~ "fix_files_permissions_daily" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";fix_files_permissions_daily = TRUE" >> $_PLR_CTRL_FILE
            fi
            _FIX_PERMISSIONS_TEST=$(grep "^fix_files_permissions_daily = FALSE" $_PLR_CTRL_FILE)
            if [[ "$_FIX_PERMISSIONS_TEST" =~ "fix_files_permissions_daily = FALSE" ]] ; then
              _DONT_TOUCH_PERMISSIONS=YES
            fi
          fi

          ###
          ### Detect db conversion mode, if set per platform or per site.
          ###
          if [ -e "$_PLR_CTRL_FILE" ] ; then
            _SQL_INNODB_CONVERSION_PRESENT=$(grep "sql_conversion_mode" $_PLR_CTRL_FILE)
            if [[ "$_SQL_INNODB_CONVERSION_PRESENT" =~ "sql_conversion_mode" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";sql_conversion_mode = NO" >> $_PLR_CTRL_FILE
            fi
            _SQL_INNODB_CONVERSION_TEST=$(grep "^sql_conversion_mode = innodb" $_PLR_CTRL_FILE)
            if [[ "$_SQL_INNODB_CONVERSION_TEST" =~ "sql_conversion_mode = innodb" ]] ; then
              _SQL_CONVERT=innodb
            fi
            _SQL_MYISAM_CONVERSION_TEST=$(grep "^sql_conversion_mode = myisam" $_PLR_CTRL_FILE)
            if [[ "$_SQL_MYISAM_CONVERSION_TEST" =~ "sql_conversion_mode = myisam" ]] ; then
              _SQL_CONVERT=myisam
            fi
          fi
          if [ -e "$_DIR_CTRL_FILE" ] ; then
            _SQL_INNODB_CONVERSION_PRESENT=$(grep "sql_conversion_mode" $_DIR_CTRL_FILE)
            if [[ "$_SQL_INNODB_CONVERSION_PRESENT" =~ "sql_conversion_mode" ]] ; then
              _DO_NOTHING=YES
            else
              echo ";sql_conversion_mode = NO" >> $_DIR_CTRL_FILE
            fi
            _SQL_INNODB_CONVERSION_TEST=$(grep "^sql_conversion_mode = innodb" $_DIR_CTRL_FILE)
            if [[ "$_SQL_INNODB_CONVERSION_TEST" =~ "sql_conversion_mode = innodb" ]] ; then
              _SQL_CONVERT=innodb
            fi
            _SQL_MYISAM_CONVERSION_TEST=$(grep "^sql_conversion_mode = myisam" $_DIR_CTRL_FILE)
            if [[ "$_SQL_MYISAM_CONVERSION_TEST" =~ "sql_conversion_mode = myisam" ]] ; then
              _SQL_CONVERT=myisam
            fi
          fi
          if [ ! -z "$_SQL_CONVERT" ] ; then
            if [ "$_SQL_CONVERT" = "YES" ] ; then
              _SQL_CONVERT=innodb
            fi
            if [ "$_SQL_CONVERT" = "myisam" ] || [ "$_SQL_CONVERT" = "innodb" ] ; then
              _TIMESTAMP=`date +%y%m%d-%H%M`
              echo "$_TIMESTAMP sql conversion to-${_SQL_CONVERT} for $Dom started"
              sql_convert
              _TIMESTAMP=`date +%y%m%d-%H%M`
              echo "$_TIMESTAMP sql conversion to-${_SQL_CONVERT} for $Dom completed"
            fi
          fi
        fi
      fi
      ;;
    esac
  fi
}

cleanup_ghost_platforms () {
  if [ -e "$Plr" ] ; then
    if [ ! -e "$Plr/index.php" ] || [ ! -e "$Plr/profiles" ] ; then
      mkdir -p $User/undo
      mv -f $Plr $User/undo/ &> /dev/null
      echo GHOST platform $Plr detected and moved to $User/undo/
    fi
  fi
}

fix_static_permissions () {
  cleanup_ghost_platforms
  if [ -e "$Plr/profiles" ] ; then
    rm -f $Plr/profiles/permissions-fix.info
    rm -f $Plr/profiles/core-permissions-fix.info
    if [ ! -f "$Plr/profiles/permissions-update-fix.info" ] ; then
      find $Plr/profiles -type f -name "*.info" -print0 | xargs -0 sed -i 's/.*dependencies\[\] = update/;dependencies\[\] = update/g' &> /dev/null
      chown -R ${_THIS_HM_USER}.ftp:users $Plr/profiles &> /dev/null
      find $Plr/profiles -type d -exec chmod 02775 {} \; &> /dev/null
      find $Plr/profiles -type f -exec chmod 0664 {} \; &> /dev/null
      echo fixed > $Plr/profiles/permissions-update-fix.info
      chown $_THIS_HM_USER:users $Plr/profiles/permissions-update-fix.info
      chmod 0664 $Plr/profiles/permissions-update-fix.info
    fi
    if [ ! -f "$Plr/profiles/core-permissions-update-fix.info" ] ; then
      chmod 775 $Plr/modules &> /dev/null
      echo fixed > $Plr/profiles/core-permissions-update-fix.info
      chown $_THIS_HM_USER:users $Plr/profiles/core-permissions-update-fix.info
      chmod 0664 $Plr/profiles/core-permissions-update-fix.info
    fi
  fi
}

fix_expected_symlinks () {
  if [ ! -e "$Plr/js.php" ] && [ -e "$Plr" ] ; then
    if [ -e "$Plr/modules/o_contrib_seven" ] && [ -e "$_O_CONTRIB_SEVEN/js/js.php" ] ; then
      ln -s $_O_CONTRIB_SEVEN/js/js.php $Plr/js.php &> /dev/null
    elif [ -e "$Plr/modules/o_contrib" ] && [ -e "$_O_CONTRIB/js/js.php" ] ; then
      ln -s $_O_CONTRIB/js/js.php $Plr/js.php &> /dev/null
    fi
  fi
}

fix_permissions () {
  ### modules,themes,libraries - profile level in ~/static
  searchStringG="/static/"
  case $Plr in
  *"$searchStringG"*)
  fix_static_permissions
  ;;
  esac
  ### modules,themes,libraries - platform level
  if [ ! -f "$Plr/sites/all/permissions-fix-$_NOW.info" ] && [ -e "$Plr" ] ; then
    mkdir -p $Plr/sites/all/{modules,themes,libraries,drush}
    find $Plr/sites/all/modules -type f -name "*.info" -print0 | xargs -0 sed -i 's/.*dependencies\[\] = update/;dependencies\[\] = update/g' &> /dev/null
    find $Plr/sites/all/{modules,themes,libraries,drush}/*{.tar,.tar.gz,.zip} -type f -exec rm -f {} \; &> /dev/null
    chown -R ${_THIS_HM_USER}.ftp:users $Plr/sites/all/{modules,themes,libraries}/* &> /dev/null
    chown $_THIS_HM_USER:users $Plr/sites/all/drush/drushrc.php $Plr/sites $Plr/sites/sites.php $Plr/sites/all $Plr/sites/all/{modules,themes,libraries,drush} &> /dev/null
    chmod 0751 $Plr/sites &> /dev/null
    chmod 0751 $Plr/sites/all &> /dev/null
    chmod 0700 $Plr/sites/all/drush &> /dev/null
    find $Plr/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
    find $Plr/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
    ### expected symlinks
    fix_expected_symlinks
    ### known exceptions
    chmod -R 775 $Plr/sites/all/libraries/tcpdf/cache &> /dev/null
    chown -R www-data:www-data $Plr/sites/all/libraries/tcpdf/cache &> /dev/null
    echo fixed > $Plr/sites/all/permissions-fix-$_NOW.info
    chown $_THIS_HM_USER:users $Plr/sites/all/permissions-fix-$_NOW.info
    chmod 0664 $Plr/sites/all/permissions-fix-$_NOW.info
  fi
  if [ -e "$Dir" ] ; then
    ### directory and settings files - site level
    chown $_THIS_HM_USER:users $Dir &> /dev/null
    chown $_THIS_HM_USER:www-data $Dir/{local.settings.php,settings.php,civicrm.settings.php,solr.php} &> /dev/null
    find $Dir/*.php -type f -exec chmod 0440 {} \; &> /dev/null
    chmod 0640 $Dir/civicrm.settings.php &> /dev/null
    ### modules,themes,libraries - site level
    find $Dir/{modules,themes,libraries}/*{.tar,.tar.gz,.zip} -type f -exec rm -f {} \; &> /dev/null
    rm -f $Dir/modules/local-allow.info
    chown -R ${_THIS_HM_USER}.ftp:users $Dir/{modules,themes,libraries}/* &> /dev/null
    chown $_THIS_HM_USER:users $Dir/drushrc.php $Dir/{modules,themes,libraries} &> /dev/null
    find $Dir/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
    find $Dir/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
    ### files - site level
    chown -L -R ${_THIS_HM_USER}.ftp:www-data $Dir/files &> /dev/null
    find $Dir/files/* -type d -exec chmod 02775 {} \; &> /dev/null
    find $Dir/files/* -type f -exec chmod 0664 {} \; &> /dev/null
    chmod 02775 $Dir/files &> /dev/null
    chown $_THIS_HM_USER:www-data $Dir/files &> /dev/null
    chown $_THIS_HM_USER:www-data $Dir/files/{tmp,images,pictures,css,js,advagg_css,advagg_js,ctools,ctools/css,imagecache,locations,xmlsitemap,deployment,styles,private} &> /dev/null
    ### private - site level
    chown -L -R ${_THIS_HM_USER}.ftp:www-data $Dir/private &> /dev/null
    find $Dir/private -type d -exec chmod 02775 {} \; &> /dev/null
    find $Dir/private -type f -exec chmod 0664 {} \; &> /dev/null
    chown $_THIS_HM_USER:www-data $Dir/private &> /dev/null
    chown $_THIS_HM_USER:www-data $Dir/private/{files,temp} &> /dev/null
    chown $_THIS_HM_USER:www-data $Dir/private/files/backup_migrate &> /dev/null
    chown $_THIS_HM_USER:www-data $Dir/private/files/backup_migrate/{manual,scheduled} &> /dev/null
    chown -L -R $_THIS_HM_USER:www-data $Dir/private/config &> /dev/null
  fi
}

convert_controls_orig () {
  if [ -e "$_CTRL_DIR/$1.info" ] || [ -e "$User/static/control/$1.info" ] ; then
    if [ ! -e "$_CTRL_FILE" ] && [ -e "$_CTRL_FILE_TPL" ] ; then
      cp -af $_CTRL_FILE_TPL $_CTRL_FILE
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" $_CTRL_FILE &> /dev/null
    rm -f $_CTRL_DIR/$1.info
  fi
}

convert_controls_orig_no_global () {
  if [ -e "$_CTRL_DIR/$1.info" ] ; then
    if [ ! -e "$_CTRL_FILE" ] && [ -e "$_CTRL_FILE_TPL" ] ; then
      cp -af $_CTRL_FILE_TPL $_CTRL_FILE
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" $_CTRL_FILE &> /dev/null
    rm -f $_CTRL_DIR/$1.info
  fi
}

convert_controls_value () {
  if [ -e "$_CTRL_DIR/$1.info" ] || [ -e "$User/static/control/$1.info" ] ; then
    if [ ! -e "$_CTRL_FILE" ] && [ -e "$_CTRL_FILE_TPL" ] ; then
      cp -af $_CTRL_FILE_TPL $_CTRL_FILE
    fi
    if [ "$1" = "nginx_cache_day" ] ; then
      _TTL=86400
    elif [ "$1" = "nginx_cache_hour" ] ; then
      _TTL=3600
    elif [ "$1" = "nginx_cache_quarter" ] ; then
      _TTL=900
    fi
    sed -i "s/.*speed_booster_anon_cache_ttl.*/speed_booster_anon_cache_ttl = $_TTL/g" $_CTRL_FILE &> /dev/null
    rm -f $_CTRL_DIR/$1.info
  fi
}

convert_controls_renamed () {
  if [ -e "$_CTRL_DIR/$1.info" ] ; then
    if [ ! -e "$_CTRL_FILE" ] && [ -e "$_CTRL_FILE_TPL" ] ; then
      cp -af $_CTRL_FILE_TPL $_CTRL_FILE
    fi
    if [ "$1" = "cookie_domain" ] ; then
      sed -i "s/.*server_name_cookie_domain.*/server_name_cookie_domain = TRUE/g" $_CTRL_FILE &> /dev/null
    fi
    rm -f $_CTRL_DIR/$1.info
  fi
}

fix_control_settings () {
  _CTRL_NAME_ORIG="redis_lock_enable redis_cache_disable disable_admin_dos_protection allow_anon_node_add allow_private_file_downloads"
  _CTRL_NAME_VALUE="nginx_cache_day nginx_cache_hour nginx_cache_quarter"
  _CTRL_NAME_RENAMED="cookie_domain"
  for ctrl in $_CTRL_NAME_ORIG; do
    convert_controls_orig "$ctrl"
  done
  for ctrl in $_CTRL_NAME_VALUE; do
    convert_controls_value "$ctrl"
  done
  for ctrl in $_CTRL_NAME_RENAMED; do
    convert_controls_renamed "$ctrl"
  done
}

fix_platform_system_control_settings () {
  _CTRL_NAME_ORIG="enable_user_register_protection entitycache_dont_enable views_cache_bully_dont_enable views_content_cache_dont_enable"
  for ctrl in $_CTRL_NAME_ORIG; do
    convert_controls_orig "$ctrl"
  done
}

fix_site_system_control_settings () {
  _CTRL_NAME_ORIG="disable_user_register_protection"
  for ctrl in $_CTRL_NAME_ORIG; do
    convert_controls_orig_no_global "$ctrl"
  done
}

cleanup_ini () {
  if [ -e "$_CTRL_FILE" ] ; then
    sed -i "s/^;;.*//g" $_CTRL_FILE &> /dev/null
    sed -i "/^$/d" $_CTRL_FILE &> /dev/null
    sed -i "s/^\[/\n\[/g" $_CTRL_FILE &> /dev/null
  fi
}

add_note_platform_ini () {
  if [ -e "$_CTRL_FILE" ] ; then
    echo "" >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  This is a platform level ACTIVE INI file which can be used to modify"     >> $_CTRL_FILE
    echo ";;  default BOA system behaviour for all sites hosted on this platform."      >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> $_CTRL_FILE
    echo ";;  default.boa_platform_control.ini, since this ACTIVE INI file"             >> $_CTRL_FILE
    echo ";;  may not include all options available after upgrade to BOA-2.3.3"         >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> $_CTRL_FILE
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
  fi
}

add_note_site_ini () {
  if [ -e "$_CTRL_FILE" ] ; then
    echo "" >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  This is a site level ACTIVE INI file which can be used to modify"         >> $_CTRL_FILE
    echo ";;  default BOA system behaviour for this site only."                         >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> $_CTRL_FILE
    echo ";;  default.boa_site_control.ini, since this ACTIVE INI file"                 >> $_CTRL_FILE
    echo ";;  may not include all options available after upgrade to BOA-2.3.3"         >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> $_CTRL_FILE
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
  fi
}

fix_platform_control_files () {
  if [ -e "/data/conf/default.boa_platform_control.ini" ] ; then
    if [ ! -e "$Plr/sites/all/modules/default.boa_platform_control.ini" ] || [ "$_CTRL_TPL_FORCE_UPDATE" = "YES" ] ; then
      cp -af /data/conf/default.boa_platform_control.ini $Plr/sites/all/modules/ &> /dev/null
      chown $_THIS_HM_USER:users $Plr/sites/all/modules/default.boa_platform_control.ini
      chmod 0664 $Plr/sites/all/modules/default.boa_platform_control.ini
    fi
    _CTRL_FILE_TPL="$Plr/sites/all/modules/default.boa_platform_control.ini"
    _CTRL_FILE="$Plr/sites/all/modules/boa_platform_control.ini"
    _CTRL_DIR="$Plr/sites/all/modules"
    fix_control_settings
    fix_platform_system_control_settings
    cleanup_ini
    add_note_platform_ini
  fi
}

fix_site_control_files () {
  if [ -e "/data/conf/default.boa_site_control.ini" ] ; then
    if [ ! -e "$Dir/modules/default.boa_site_control.ini" ] || [ "$_CTRL_TPL_FORCE_UPDATE" = "YES" ] ; then
      cp -af /data/conf/default.boa_site_control.ini $Dir/modules/ &> /dev/null
      chown $_THIS_HM_USER:users $Dir/modules/default.boa_site_control.ini
      chmod 0664 $Dir/modules/default.boa_site_control.ini
    fi
    _CTRL_FILE_TPL="$Dir/modules/default.boa_site_control.ini"
    _CTRL_FILE="$Dir/modules/boa_site_control.ini"
    _CTRL_DIR="$Dir/modules"
    fix_control_settings
    fix_site_system_control_settings
    cleanup_ini
    add_note_site_ini
  fi
}

cleanup_ghost_vhosts () {
  for Site in `find $User/config/server_master/nginx/vhost.d -maxdepth 1 -mindepth 1 -type f | sort`
  do
    Dom=`echo $Site | cut -d'/' -f9 | awk '{ print $1}'`
    if [[ "$Dom" =~ ".restore"($) ]] ; then
      mkdir -p $User/undo
      mv -f $User/.drush/${Dom}.alias.drushrc.php $User/undo/ &> /dev/null
      mv -f $User/config/server_master/nginx/vhost.d/${Dom} $User/undo/ &> /dev/null
      echo GHOST vhost for $Dom detected and moved to $User/undo/
    fi
    if [ -e "$User/config/server_master/nginx/vhost.d/$Dom" ] ; then
      Plx=`cat $User/config/server_master/nginx/vhost.d/$Dom | grep "root " | cut -d: -f2 | awk '{ print $2}' | sed "s/[\;]//g"`
      if [[ "$Plx" =~ "aegir/distro" ]] || [[ "$Dom" =~ "--CDN"($) ]] ; then
        _SKIP_VHOST=YES
      else
        if [ ! -e "$User/.drush/$Dom.alias.drushrc.php" ] ; then
          mkdir -p $User/undo
          mv -f $Site $User/undo/ &> /dev/null
          echo GHOST vhost for $Dom with no drushrc detected and moved to $User/undo/
        fi
      fi
    fi
  done
}

cleanup_ghost_drushrc () {
  for Alias in `find $User/.drush/*.alias.drushrc.php -maxdepth 1 -type f | sort`
  do
    AliasName=`echo "$Alias" | cut -d'/' -f6 | awk '{ print $1}'`
    AliasName=`echo "$AliasName" | sed "s/.alias.drushrc.php//g" | awk '{ print $1}'`
    if [[ "$AliasName" =~ (^)"server_" ]] || [[ "$AliasName" =~ (^)"hostmaster" ]] ; then
      _IS_SITE=NO
    elif [[ "$AliasName" =~ (^)"platform_" ]] ; then
      Plm=`cat $Alias | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      if [ -d "$Plm" ] ; then
        if [ ! -e "$Plm/index.php" ] || [ ! -e "$Plm/profiles" ] ; then
          mkdir -p $User/undo
          mv -f $Plm $User/undo/ &> /dev/null
          echo GHOST broken platform dir $Plm detected and moved to $User/undo/
          mv -f $Alias $User/undo/ &> /dev/null
          echo GHOST broken platform alias $Alias detected and moved to $User/undo/
        fi
      else
        mkdir -p $User/undo
        mv -f $Alias $User/undo/ &> /dev/null
        echo GHOST nodir platform alias $Alias detected and moved to $User/undo/
      fi
    else
      _THIS_SITE_NAME="$AliasName"
      if [[ "$_THIS_SITE_NAME" =~ ".restore"($) ]] ; then
        _IS_SITE=NO
        mkdir -p $User/undo
        mv -f $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php $User/undo/ &> /dev/null
        mv -f $User/config/server_master/nginx/vhost.d/${_THIS_SITE_NAME} $User/undo/ &> /dev/null
        echo GHOST drushrc and vhost for ${_THIS_SITE_NAME} detected and moved to $User/undo/
      else
        _THIS_SITE_FDIR=`cat $Alias | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
        if [ -d "$_THIS_SITE_FDIR" ] ; then
          _IS_SITE=YES
        else
          mkdir -p $User/undo
          mv -f $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php $User/undo/ &> /dev/null
          mv -f $User/config/server_master/nginx/vhost.d/${_THIS_SITE_NAME} $User/undo/ &> /dev/null
          echo GHOST drushrc and vhost for ${_THIS_SITE_NAME} detected and moved to $User/undo/
        fi
      fi
    fi
  done
}

process () {
  cleanup_ghost_vhosts
  cleanup_ghost_drushrc
  for Site in `find $User/config/server_master/nginx/vhost.d -maxdepth 1 -mindepth 1 -type f | sort`
  do
    #echo Counting Site $Site
    Dom=`echo $Site | cut -d'/' -f9 | awk '{ print $1}'`
    if [ -e "$User/.drush/$Dom.alias.drushrc.php" ] ; then
      echo Dom is $Dom
      Dir=`cat $User/.drush/$Dom.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      Plr=`cat $User/.drush/$Dom.alias.drushrc.php | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      if [ -e "$Plr" ] ; then
        fix_platform_control_files
        fix_o_contrib_symlink
        if [ -e "$Dir" ] ; then
          searchStringD="dev."
          searchStringF="devel."
          case $Dom in
          *"$searchStringD"*) ;;
          *"$searchStringF"*) ;;
          *)
          fix_modules
          fix_robots_txt
          ;;
          esac
          fix_boost_cache
          fix_site_control_files
        fi
        if [ "$_DONT_TOUCH_PERMISSIONS" = "NO" ] && [ "$_PERMISSIONS_FIX" = "YES" ] ; then
          fix_permissions
        fi
      fi
    fi
  done
}

delete_this_platform () {
  run_drush6_hmr_cmd "@hostmaster hosting-task @platform_${_THIS_PLATFORM_NAME} delete --force"
  echo "Old empty platform_${_THIS_PLATFORM_NAME} will be deleted"
}

check_old_empty_platforms () {
  if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] || [ -e "/root/.host8.cnf" ] ; then
    if [[ "$_HOST_TEST" =~ "v189q.nyc." ]] || [[ "$_HOST_TEST" =~ ".qq.o8.io" ]] ; then
      _DO_NOTHING=YES
    else
      if [ "$_DEL_OLD_EMPTY_PLATFORMS" -gt "0" ] && [ ! -z "$_DEL_OLD_EMPTY_PLATFORMS" ] ; then
        _DO_NOTHING=YES
      else
        _DEL_OLD_EMPTY_PLATFORMS="30"
      fi
    fi
  fi
  if [ ! -z "$_DEL_OLD_EMPTY_PLATFORMS" ] ; then
    if [ "$_DEL_OLD_EMPTY_PLATFORMS" -gt "0" ] ; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to ${_DEL_OLD_EMPTY_PLATFORMS} days on ${_THIS_HM_USER} instance"
      for Platform in `find $User/.drush/platform_* -maxdepth 1 -mtime +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`
      do
        _THIS_PLATFORM_NAME=`echo "$Platform" | sed "s/.*platform_//g; s/.alias.drushrc.php//g" | awk '{ print $1}'`
        _THIS_PLATFORM_ROOT=`cat $Platform | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
        _THIS_PLATFORM_SITE=`grep "${_THIS_PLATFORM_ROOT}/sites/" $User/.drush/*.drushrc.php | grep site_path`
        if [ ! -e "${_THIS_PLATFORM_ROOT}/sites/all" ] || [ ! -e "${_THIS_PLATFORM_ROOT}/index.php" ] ; then
          mkdir -p $User/undo
          mv -f $User/.drush/platform_${_THIS_PLATFORM_NAME}.alias.drushrc.php $User/undo/ &> /dev/null
          echo GHOST platform $_THIS_PLATFORM_ROOT detected and moved to $User/undo/
        fi
        if [[ "$_THIS_PLATFORM_SITE" =~ ".restore" ]] ; then
          echo "WARNING: ghost site leftover found: $_THIS_PLATFORM_SITE"
        fi
        if [ -z "$_THIS_PLATFORM_SITE" ] && [ -e "${_THIS_PLATFORM_ROOT}/sites/all" ] ; then
          delete_this_platform
        fi
      done
    fi
  fi
}

purge_cruft_machine () {
  if [ ! -z "$_DEL_OLD_BACKUPS" ] && [ "$_DEL_OLD_BACKUPS" -gt "0" ] ; then
    _PURGE_BACKUPS="$_DEL_OLD_BACKUPS"
  else
    _PURGE_BACKUPS="30"
  fi

  if [ ! -z "$_DEL_OLD_TMP" ] && [ "$_DEL_OLD_TMP" -gt "0" ] ; then
    _PURGE_TMP="$_DEL_OLD_TMP"
  else
    _PURGE_TMP="0"
  fi

  if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] || [ -e "/root/.host8.cnf" ] ; then
    _PURGE_BACKUPS="8"
    _PURGE_TMP="0"
  fi

  find $User/backups/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find $User/distro/*/*/sites/*/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/distro/*/*/sites/*/private/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find $User/static/*/*/*/*/*/sites/*/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/*/sites/*/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/sites/*/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/sites/*/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/sites/*/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find $User/static/*/*/*/*/*/sites/*/private/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/*/sites/*/private/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/sites/*/private/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/sites/*/private/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/sites/*/private/files/backup_migrate/*/* -mtime +${_PURGE_BACKUPS} -type f -exec rm -rf {} \; &> /dev/null

  find $User/distro/*/*/sites/*/files/tmp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/distro/*/*/sites/*/private/temp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/*/*/sites/*/files/tmp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/*/*/sites/*/private/temp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/*/sites/*/files/tmp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/*/sites/*/private/temp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/sites/*/files/tmp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/*/sites/*/private/temp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/sites/*/files/tmp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/*/sites/*/private/temp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/sites/*/files/tmp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null
  find $User/static/*/sites/*/private/temp/* -mtime +${_PURGE_TMP} -type f -exec rm -rf {} \; &> /dev/null

  find /home/${_THIS_HM_USER}.ftp/.tmp/* -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find /home/${_THIS_HM_USER}.ftp/tmp/* -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find $User/.tmp/* -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find $User/tmp/* -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  mkdir -p $User/static/trash
  chown ${_THIS_HM_USER}.ftp:users $User/static/trash
  find $User/static/trash/* -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  REVISIONS="001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 018 019 020 021 022 023 024 025 026 027 028 029 030 031 032 033 034 035 036 037 038 039 040 041 042 043 044 045 046 047 048 049 050"

  for i in $REVISIONS; do
    if [ -e "/home/${_THIS_HM_USER}.ftp/platforms/$i" ] ; then
      RevisionTest=$(ls /home/${_THIS_HM_USER}.ftp/platforms/$i | wc -l | tr -d "\n" 2>&1)
      if [ "$RevisionTest" -lt "2" ] && [ ! -z "$RevisionTest" ] ; then
        chattr -i /home/${_THIS_HM_USER}.ftp/platforms   &> /dev/null
        chattr -i /home/${_THIS_HM_USER}.ftp/platforms/* &> /dev/null
        rm -f -r /home/${_THIS_HM_USER}.ftp/platforms/$i
      fi
    fi
    if [ -d "$User/distro/$i" ] ; then
      if [ ! -d "$User/distro/$i/keys" ] ; then
        mkdir -p $User/distro/$i/keys
      fi
      RevisionTest=$(ls $User/distro/$i | wc -l | tr -d "\n" 2>&1)
      if [ "$RevisionTest" -lt "2" ] && [ ! -z "$RevisionTest" ] ; then
        mkdir -p $User/undo
        mv -f $User/distro/$i $User/undo/ &> /dev/null
        echo GHOST revision $User/distro/$i detected and moved to $User/undo/
      fi
    fi
  done

  for i in $REVISIONS; do
    if [ -e "/data/disk/${_THIS_HM_USER}/distro/$i" ] && [ ! -e "/home/${_THIS_HM_USER}.ftp/platforms/$i" ] ; then
      chattr -i /home/${_THIS_HM_USER}.ftp/platforms   &> /dev/null
      chattr -i /home/${_THIS_HM_USER}.ftp/platforms/* &> /dev/null
      mkdir -p /home/${_THIS_HM_USER}.ftp/platforms/$i
      mkdir -p /data/disk/${_THIS_HM_USER}/distro/$i/keys
      chown ${_THIS_HM_USER}.ftp:$_WEBG /data/disk/${_THIS_HM_USER}/distro/$i/keys
      chmod 02775 /data/disk/${_THIS_HM_USER}/distro/$i/keys
      ln -sf /data/disk/${_THIS_HM_USER}/distro/$i/keys /home/${_THIS_HM_USER}.ftp/platforms/$i/keys
      for Codebase in `find /data/disk/${_THIS_HM_USER}/distro/$i/* -maxdepth 1 -mindepth 1 -type d | grep "/sites$" 2>&1`; do
        CodebaseName=$(echo $Codebase | cut -d'/' -f7 | awk '{ print $1}' 2> /dev/null)
        ln -sf ${Codebase} /home/${_THIS_HM_USER}.ftp/platforms/$i/${CodebaseName}
        echo Fixed symlink to ${Codebase} for ${_THIS_HM_USER}.ftp
      done
    fi
  done
}

count_cpu()
{
  _CPU_INFO=$(grep -c processor /proc/cpuinfo)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc)
  if [ -z "$_NPROC_TEST" ] ; then
    _CPU_NR="$_CPU_INFO"
  else
    _CPU_NR=`nproc`
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "$_CPU_NR" ] && [ ! -z "$_CPU_INFO" ] && [ "$_CPU_NR" -gt "$_CPU_INFO" ] && [ "$_CPU_INFO" -gt "0" ] ; then
    _CPU_NR="$_CPU_INFO"
  fi
  if [ -z "$_CPU_NR" ] || [ "$_CPU_NR" -lt "1" ] ; then
    _CPU_NR=1
  fi
  echo $_CPU_NR > /data/all/cpuinfo
  chmod 644 /data/all/cpuinfo
}

load_control()
{
  if [ -e "/root/.barracuda.cnf" ] ; then
    source /root/.barracuda.cnf
    _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  fi
  if [ -z "$_CPU_MAX_RATIO" ] ; then
    _CPU_MAX_RATIO=6
  fi
  _O_LOAD=`awk '{print $1*100}' /proc/loadavg`
  let "_O_LOAD = (($_O_LOAD / $_CPU_NR))"
  let "_O_LOAD_MAX = ((100 * $_CPU_MAX_RATIO))"
}

shared_codebases_cleanup () {
  if [ -L "/data/all" ] ; then
    _CLD="/data/disk/codebases-cleanup"
  else
    _CLD="/var/backups/codebases-cleanup"
  fi
  REVISIONS="001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 018 019 020 021 022 023 024 025 026 027 028 029 030 031 032 033 034 035 036 037 038 039 040 041 042 043 044 045 046 047 048 049 050"
  for i in $REVISIONS; do
    if [ -d "/data/all/$i/o_contrib" ] ; then
      for Codebase in `find /data/all/$i/* -maxdepth 1 -mindepth 1 -type d | grep "/profiles$" 2>&1`; do
        CodebaseDir=$(echo $Codebase | sed 's/\/profiles//g'| awk '{print $1}' 2> /dev/null)
        CodebaseTest=$(find /data/disk/*/distro/*/*/ -maxdepth 1 -mindepth 1 -type l -lname $Codebase | sort 2>&1)
        if [[ "$CodebaseTest" =~ "No such file or directory" ]] || [ -z "$CodebaseTest" ] ; then
          mkdir -p ${_CLD}/$i
          echo Moving no longer used $CodebaseDir to ${_CLD}/$i/
          mv -f $CodebaseDir ${_CLD}/$i/
          sleep 1
        fi
      done
    fi
  done
}

action () {
  for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`
  do
    count_cpu
    load_control
    if [ -e "$User/config/server_master/nginx/vhost.d" ] && [ ! -e "$User/log/CANCELLED" ] ; then
      if [ $_O_LOAD -lt $_O_LOAD_MAX ] ; then
        _THIS_HM_USER=`echo $User | cut -d'/' -f4 | awk '{ print $1}'`
        _THIS_HM_SITE=`cat $User/.drush/hostmaster.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
        echo load is $_O_LOAD while maxload is $_O_LOAD_MAX
        echo User $User
        su -s /bin/bash $_THIS_HM_USER -c "drush6 cc drush &> /dev/null"
        rm -f -r $User/.tmp/cache
        _SQL_CONVERT=NO
        _DEL_OLD_EMPTY_PLATFORMS="0"
        if [ -e "/root/.${_THIS_HM_USER}.octopus.cnf" ] ; then
          source /root/.${_THIS_HM_USER}.octopus.cnf
          _DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS//[^0-9]/}
        fi
        disable_chattr ${_THIS_HM_USER}.ftp
        rm -f -r /home/${_THIS_HM_USER}.ftp/drush-backups
        process
        if [ -e "$_THIS_HM_SITE" ] ; then
          cd $_THIS_HM_SITE
          su -s /bin/bash $_THIS_HM_USER -c "drush6 cc drush &> /dev/null"
          rm -f -r $User/.tmp/cache
          run_drush6_hmr_cmd "@hostmaster vset --always-set hosting_advanced_cron_default_interval 10800"
          run_drush6_hmr_cmd "@hostmaster vset --always-set hosting_queue_advanced_cron_frequency 1"
          run_drush6_hmr_cmd "@hostmaster vset --always-set hosting_queue_cron_frequency 53222400"
          run_drush6_hmr_cmd "@hostmaster vset --always-set hosting_cron_use_backend 0"
          run_drush6_hmr_cmd "@hostmaster vset --always-set hosting_ignore_default_profiles 0"
          run_drush6_hmr_cmd "@hostmaster vset --always-set hosting_queue_tasks_items 1"
          run_drush6_hmr_cmd "@hostmaster en path_alias_cache -y"
          run_drush6_hmr_cmd "@hostmaster fr aegir_custom_settings -y"
          run_drush6_hmr_cmd "@hostmaster cc all"
          run_drush6_hmr_cmd "@hostmaster fr aegir_custom_settings -y"
          run_drush6_hmr_cmd "@hostmaster cc all"
          run_drush6_hmr_cmd "@hostmaster fr aegir_custom_settings -y"
          run_drush6_hmr_cmd "@hostmaster cc all"
        fi
        run_drush6_hmr_cmd "@hostmaster sqlq \"DELETE FROM hosting_task WHERE task_type='delete' AND task_status='-1'\""
        run_drush6_hmr_cmd "@hostmaster sqlq \"DELETE FROM hosting_task WHERE task_type='delete' AND task_status='0' AND executed='0'\""
        check_old_empty_platforms
        purge_cruft_machine
        if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
          rm -f -r $User/clients/admin &> /dev/null
          rm -f -r $User/clients/omega8ccgmailcom &> /dev/null
          rm -f -r $User/clients/nocomega8cc &> /dev/null
        fi
        rm -f -r $User/clients/*/backups &> /dev/null
        symlinks -dr $User/clients &> /dev/null
        if [ -e "/home/${_THIS_HM_USER}.ftp" ] ; then
          symlinks -dr /home/${_THIS_HM_USER}.ftp &> /dev/null
          rm -f /home/${_THIS_HM_USER}.ftp/{.profile,.bash_logout,.bash_profile,.bashrc}
        fi
        echo Done for $User
        enable_chattr ${_THIS_HM_USER}.ftp
      else
        echo load is $_O_LOAD while maxload is $_O_LOAD_MAX
        echo ...we have to wait...
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
_NOW=`date +%y%m%d-%H%M`
_DOW=`date +%w`
_HOST_TEST=`uname -n 2>&1`
_VM_TEST=`uname -a 2>&1`
#
if [[ "$_VM_TEST" =~ beng ]] ; then
  _VMFAMILY="VS"
  _MODULES_FORCE="background_process coder cookie_cache_bypass css_gzip hacked javascript_aggregator memcache memcache_admin poormanscron search_krumo security_review site_audit stage_file_proxy syslog supercron ultimate_cron varnish watchdog_live xhprof"
else
  _VMFAMILY="XEN"
fi
#
if [ "$_DOW" = "6" ] ; then
  _MODULES_ON_SEVEN="robotstxt"
  _MODULES_ON_SIX="path_alias_cache robotstxt"
  _MODULES_OFF_SEVEN="background_process coder dblog devel hacked l10n_update memcache memcache_admin performance search_krumo security_review site_audit stage_file_proxy syslog ultimate_cron update varnish watchdog_live xhprof"
  _MODULES_OFF_SIX="background_process coder cookie_cache_bypass css_gzip dblog devel hacked javascript_aggregator l10n_update memcache memcache_admin performance poormanscron search_krumo security_review stage_file_proxy supercron syslog ultimate_cron update varnish watchdog_live xhprof"
else
  _MODULES_ON_SEVEN="robotstxt"
  _MODULES_ON_SIX="path_alias_cache robotstxt"
  _MODULES_OFF_SEVEN="background_process dblog syslog update"
  _MODULES_OFF_SIX="background_process dblog syslog update"
fi
#
_CTRL_TPL_FORCE_UPDATE=YES
#
# Check for last all nr
if [ -e "/data/all" ] ; then
  cd /data/all
  listl=([0-9]*)
  _LAST_ALL=${listl[@]: -1}
  _O_CONTRIB="/data/all/$_LAST_ALL/o_contrib"
  _O_CONTRIB_SEVEN="/data/all/$_LAST_ALL/o_contrib_seven"
else
  _O_CONTRIB=NO
  _O_CONTRIB_SEVEN=NO
fi
#
mkdir -p /var/xdrago/log/daily
if [ -e "/var/run/boa_wait.pid" ] && [ ! -e "/var/run/boa_system_wait.pid" ] ; then
  touch /var/xdrago/log/wait-for-boa
  exit 1
elif [ -e "/var/run/daily-fix.pid" ] ; then
  touch /var/xdrago/log/wait-for-daily
  exit 1
else
  touch /var/run/daily-fix.pid
  if [ -e "/root/.barracuda.cnf" ] ; then
    source /root/.barracuda.cnf
  fi
  if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
    _PERMISSIONS_FIX=YES
    _MODULES_FIX=YES
    n=$((RANDOM%800+80))
    echo waiting $n sec
    sleep $n
  fi
  if [ -z "$_PERMISSIONS_FIX" ] ; then
    _PERMISSIONS_FIX=YES
  fi
  if [ -z "$_MODULES_FIX" ] ; then
    _MODULES_FIX=YES
  fi
  find /data/all/ -type f -name "*.info" -print0 | xargs -0 sed -i 's/.*dependencies\[\] = update/;dependencies\[\] = update/g' &> /dev/null
  if [ ! -e "/data/all/permissions-fix-post-up-BOA-2.3.3.info" ] ; then
    find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} -type d -exec chmod 02775 {} \; &> /dev/null
    find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} -type f -exec chmod 0664 {} \; &> /dev/null
    echo fixed > /data/all/permissions-fix-post-up-BOA-2.3.3.info
  fi
  action >/var/xdrago/log/daily/daily-$_NOW.log 2>&1
  if [ "$_PERMISSIONS_FIX" = "YES" ] ; then
    echo "INFO: Removing old permissions-fix-* files"
    find /data/disk/*/distro/*/*/sites/all/permissions-fix-* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
    find /data/disk/*/static/*/sites/all/permissions-fix-* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
    find /data/disk/*/static/*/*/sites/all/permissions-fix-* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
    find /data/disk/*/static/*/*/*/sites/all/permissions-fix-* -mtime +0 -type f -exec rm -rf {} \; &> /dev/null
  fi
  if [ "$_NGINX_FORWARD_SECRECY" = "YES" ] ; then
    for File in `find /etc/ssl/private/*.key -type f` ; do
      _PFS_TEST=$(grep "DH PARAMETERS" $File)
      if [[ "$_PFS_TEST" =~ "DH PARAMETERS" ]] ; then
        _DO_NOTHING=YES
      else
        openssl dhparam -rand - 4096 >> $File
      fi
    done
    for File in `find /etc/ssl/private/*.crt -type f` ; do
      _PFS_TEST=$(grep "DH PARAMETERS" $File)
      if [[ "$_PFS_TEST" =~ "DH PARAMETERS" ]] ; then
        _DO_NOTHING=YES
      else
        openssl dhparam -rand - 4096 >> $File
      fi
    done
    /etc/init.d/nginx reload
  fi
  rm -f /var/backups/BOA.sh.txt-*
  curl -L --max-redirs 10 -k -s --retry 10 --retry-delay 5 -A iCab "http://files.aegir.cc/BOA.sh.txt" -o /var/backups/BOA.sh.txt-$_NOW
  bash /var/backups/BOA.sh.txt-$_NOW &> /dev/null
  rm -f /var/backups/BOA.sh.txt-$_NOW
fi

###--------------------###
echo "INFO: Checking BARRACUDA version"
rm -f /opt/tmp/barracuda-version.txt*
curl -L --max-redirs 10 -k -s --retry 3 --retry-delay 15 -A iCab "http://files.aegir.cc/versions/master/aegir/conf/barracuda-version.txt" -o /opt/tmp/barracuda-version.txt
if [ -e "/opt/tmp/barracuda-version.txt" ] ; then
  _INSTALLER_VERSION=`cat /opt/tmp/barracuda-version.txt`
  _VERSIONS_TEST=`cat /var/log/barracuda_log.txt`
  if [ ! -z "$_INSTALLER_VERSION" ] ; then
    if [[ "$_VERSIONS_TEST" =~ "$_INSTALLER_VERSION" ]] ; then
      _VERSIONS_TEST_RESULT=OK
      echo "INFO: Version test result: OK"
    else
      cat <<EOF | mail -e -s "New $_INSTALLER_VERSION Stable Edition available" notify\@omega8.cc

 There is new $_INSTALLER_VERSION Stable Edition available.

 Please review the changelog and upgrade as soon as possible
 to receive all security updates and new features.

 Changelog: http://bit.ly/boa-changes

 --
 This e-mail has been sent by your Barracuda server upgrade monitor.

EOF
    echo "INFO: Update notice sent: OK"
    fi
  fi
fi
#
if [ "$_PERMISSIONS_FIX" = "YES" ] && [ ! -z "$_INSTALLER_VERSION" ] && [ -e "/opt/tmp/barracuda-version.txt" ] && [ ! -e "/data/all/permissions-fix-$_INSTALLER_VERSION-fixed-dz.info" ] ; then
  echo "INFO: Fixing permissions in the /data/all tree..."
  find /data/all -type d -exec chmod 0755 {} \; &> /dev/null
  find /data/all -type f -exec chmod 0644 {} \; &> /dev/null
  find /data/conf -type d -exec chmod 0755 {} \; &> /dev/null
  find /data/conf -type f -exec chmod 0644 {} \; &> /dev/null
  chown -R root:root /data/conf
  chmod 02775 /data/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  chmod 02775 /data/all/000/core/*/sites/all/{modules,libraries,themes} &> /dev/null
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  chown -R root:root /data/all
  chown -R root:users /data/all/*/*/sites
  chown -R root:users /data/all/000/core/*/sites
  echo fixed > /data/all/permissions-fix-$_INSTALLER_VERSION-fixed-dz.info
fi
if [ ! -e "/var/backups/fix-sites-all-permsissions-2.3.3.txt" ] ; then
  chmod 0751  /data/disk/*/distro/*/*/sites
  chmod 0751  /data/disk/*/distro/*/*/sites/all
  chmod 02775 /data/disk/*/distro/*/*/sites/all/{modules,libraries,themes}
  echo FIXED > /var/backups/fix-sites-all-permsissions-2.3.3.txt
  echo "Permissions in sites/all tree just fixed"
fi
if [ ! -e "/root/.upstart.cnf" ] ; then
  service cron reload &> /dev/null
fi
find /var/backups/ltd/*/* -mtime +0 -type f -exec rm -rf {} \;
find /var/backups/jetty* -mtime +0 -exec rm -rf {} \;
find /var/backups/dragon/* -mtime +7 -exec rm -rf {} \;
if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] || [ -e "/root/.host8.cnf" ] ; then
  if [ -d "/var/backups/codebases-cleanup" ] ; then
    find /var/backups/codebases-cleanup/* -mtime +7 -exec rm -rf {} \;
  elif [ -d "/data/disk/codebases-cleanup" ] ; then
    find /data/disk/codebases-cleanup/* -mtime +7 -exec rm -rf {} \;
  fi
fi
rm -f /tmp/.cron.*.pid
rm -f /tmp/.busy.*.pid
rm -f /data/disk/*/.tmp/.cron.*.pid
rm -f /data/disk/*/.tmp/.busy.*.pid
rm -f /var/run/daily-fix.pid
echo "INFO: Daily maintenance complete"
exit 0
###EOF2014###
