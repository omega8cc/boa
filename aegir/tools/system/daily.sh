#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

###----------------------------------------###
### AUTOMATED MAINTENANCE CONFIGURATION    ###
###----------------------------------------###

_MODULES_ON_SEVEN="robotstxt"
_MODULES_ON_SIX="path_alias_cache robotstxt"
_MODULES_OFF_SEVEN="background_process dblog devel hacked l10n_update performance syslog ultimate_cron update"
_MODULES_OFF_SIX="background_process cookie_cache_bypass css_gzip dblog devel javascript_aggregator hacked l10n_update performance poormanscron supercron syslog ultimate_cron update"

###-------------SYSTEM-----------------###

run_drush4_cmd () {
  su -s /bin/bash $_THIS_HM_USER -c "drush4 $1 &> /dev/null"
}

run_drush4_dash_cmd () {
  su -s /bin/bash - $_THIS_HM_USER -c "drush4 $1 &> /dev/null"
}

run_drush4_nosilent_cmd () {
  su -s /bin/bash $_THIS_HM_USER -c "drush4 $1"
}

run_drush6_nosilent_cmd () {
  su -s /bin/bash $_THIS_HM_USER -c "drush6 cache-clear drush &> /dev/null"
  su -s /bin/bash $_THIS_HM_USER -c "drush6 $1"
}

check_if_required () {
  _REI_TEST=$(run_drush6_nosilent_cmd "pmi $1")
  _REQ_TEST=$(echo $_REI_TEST | grep 'Required by.*none')
  if [[ "$_REQ_TEST" =~ "Required by" ]] ; then
    _REQ=NO
  elif [[ "$_REI_TEST" =~ "was not found" ]] ; then
    _REQ=NULL
  else
    _REQ=YES
  fi
  _REM_TEST=$(echo $_REI_TEST | grep 'Required by.*minimal')
  if [[ "$_REM_TEST" =~ "Required by" ]] ; then
    _REQ=NO
  fi
  _RES_TEST=$(echo $_REI_TEST | grep 'Required by.*standard')
  if [[ "$_RES_TEST" =~ "Required by" ]] ; then
    _REQ=NO
  fi
  _RET_TEST=$(echo $_REI_TEST | grep 'Required by.*testing')
  if [[ "$_RET_TEST" =~ "Required by" ]] ; then
    _REQ=NO
  fi
  _REH_TEST=$(echo $_REI_TEST | grep 'Required by.*hacked')
  if [[ "$_REH_TEST" =~ "Required by" ]] ; then
    _REQ=NO
  fi
  _RED_TEST=$(echo $_REI_TEST | grep 'Required by.*devel')
  if [[ "$_RED_TEST" =~ "Required by" ]] ; then
    _REQ=NO
  fi
}

check_if_skip () {
  for s in $_MODULES_SKIP; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ] ; then
      _SKIP=YES
      echo $1 is whitelisted and will not be disabled in $Dom
    fi
  done
}

disable_modules () {
  for m in $1; do
    _SKIP=NO
    if [ ! -z "$_MODULES_SKIP" ] ; then
      check_if_skip "$m"
    fi
    if [ "$_SKIP" = "NO" ] ; then
      _MODULE_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --type=module | grep \($m\)")
      if [[ "$_MODULE_TEST" =~ "($m)" ]] ; then
        check_if_required "$m"
        if [ "$_REQ" = "NO" ] ; then
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
      true
    else
      run_drush4_cmd "en $m -y"
      echo $m enabled in $Dom
    fi
  done
}

fix_user_register_protection () {

  _PLR_CTRL_FILE="$Plr/sites/all/modules/boa_platform_control.ini"

  if [ -e "$User/static/control/enable_user_register_protection.info" ] && [ -e "/var/xdrago/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
    cp -af /var/xdrago/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
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
  else
    _ENABLE_USER_REGISTER_PROTECTION=NO
  fi

  if [ "$_ENABLE_USER_REGISTER_PROTECTION" = "NO" ] && [ -e "$User/static/control/enable_user_register_protection.info" ] ; then
    sed -i "s/.*enable_user_register_protection.*/enable_user_register_protection = TRUE/g" $_PLR_CTRL_FILE &> /dev/null
    _ENABLE_USER_REGISTER_PROTECTION=YES
  fi

  _DIR_CTRL_FILE="$Dir/modules/boa_site_control.ini"

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
    curl -s --retry 3 --retry-delay 15 -A iCab "http://$Dom/robots.txt?nocache=1&noredis=1" -o $Dir/files/robots.txt
    if [ -e "$Dir/files/robots.txt" ] ; then
      echo >> $Dir/files/robots.txt
    fi
  fi
}

fix_clear_cache () {
  if [ -e "$Plr/profiles/hostmaster" ] ; then
    run_drush4_dash_cmd "@hostmaster cc all"
  fi
}

fix_boost_cache () {
  if [ -e "$Plr/cache" ] ; then
    rm -f -r $Plr/cache/*
    rm -f $Plr/cache/{.boost,.htaccess}
  else
    if [ -e "$Plr/drushrc.php" ] ; then
      mkdir -p $Plr/cache
    fi
  fi
  if [ -e "$Plr/cache" ] ; then
    chown $_THIS_HM_USER:www-data $Plr/cache
    chmod 02770 $Plr/cache
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
  sudo -u ${_THIS_HM_USER}.ftp -H sqlmagic convert to-innodb
}

check_site_status () {
  _STATUS_TEST=$(run_drush4_nosilent_cmd "status | grep 'Drupal bootstrap.*Successful'")
  if [[ "$_STATUS_TEST" =~ "Successful" ]] ; then
    _STATUS=OK
  else
    _STATUS=BROKEN
    echo "WARNING: THIS SITE IS BROKEN! $Dir"
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
          if [ "$_SQL_CONVERT" = "YES" ] ; then
            _TIMESTAMP=`date +%y%m%d-%H%M`
            echo "$_TIMESTAMP sql conversion for $Dom started"
            sql_convert
            _TIMESTAMP=`date +%y%m%d-%H%M`
            echo "$_TIMESTAMP sql conversion for $Dom completed"
          fi
          fix_user_register_protection

          _AUTO_CONFIG_ADVAGG=NO
          if [ -e "$Plr/sites/all/modules/advagg" ] || [ -e "$Plr/modules/o_contrib/advagg" ] || [ -e "$Plr/modules/o_contrib_seven/advagg" ] ; then
            _MODULE_TEST=$(run_drush4_nosilent_cmd "pml --status=enabled --type=module | grep \(advagg\)")
            if [[ "$_MODULE_TEST" =~ "(advagg)" ]] ; then
              _AUTO_CONFIG_ADVAGG=YES
            fi
          fi
          if [ "$_AUTO_CONFIG_ADVAGG" = "YES" ] ; then
            if [ -e "/var/xdrago/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
              cp -af /var/xdrago/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
              chmod 0664 $_DIR_CTRL_FILE
            fi
            if [ -e "$_DIR_CTRL_FILE" ] ; then
              _AUTO_CONFIG_ADVAGG_TEST=$(grep "^advagg_auto_configuration = TRUE" $_DIR_CTRL_FILE)
              if [[ "$_AUTO_CONFIG_ADVAGG_TEST" =~ "advagg_auto_configuration = TRUE" ]] ; then
                true
              else
                ###
                ### Do this only for the site level ini file.
                ###
                sed -i "s/.*advagg_auto_configuration.*/advagg_auto_configuration = TRUE/g" $_DIR_CTRL_FILE &> /dev/null
              fi
            fi
          else
            if [ -e "/var/xdrago/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
              cp -af /var/xdrago/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
              chmod 0664 $_DIR_CTRL_FILE
            fi
            if [ -e "$_DIR_CTRL_FILE" ] ; then
              _AUTO_CONFIG_ADVAGG_TEST=$(grep "^advagg_auto_configuration = FALSE" $_DIR_CTRL_FILE)
              if [[ "$_AUTO_CONFIG_ADVAGG_TEST" =~ "advagg_auto_configuration = FALSE" ]] ; then
                true
              else
                sed -i "s/.*advagg_auto_configuration.*/advagg_auto_configuration = FALSE/g" $_DIR_CTRL_FILE &> /dev/null
              fi
            fi
          fi

          if [ -e "$Plr/modules/o_contrib_seven" ] ; then
            _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS=NO
            Pri=$(drush4 vget ^file_default_scheme$ | cut -d: -f2 | awk '{ print $1}' | sed "s/['\"]//g" | tr -d "\n" 2>&1)
            Pri=${Pri//[^a-z]/}
            echo Pri file_default_scheme for $Dom is $Pri
            if [ "$Pri" = "private" ] ; then
              _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS=YES
            fi
            if [ "$_AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS" = "YES" ] ; then
              if [ -e "/var/xdrago/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
                cp -af /var/xdrago/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
                chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
                chmod 0664 $_DIR_CTRL_FILE
              fi
              if [ -e "$_DIR_CTRL_FILE" ] ; then
                _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST=$(grep "^allow_private_file_downloads = TRUE" $_DIR_CTRL_FILE)
                if [[ "$_AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST" =~ "allow_private_file_downloads = TRUE" ]] ; then
                  true
                else
                  ###
                  ### Do this only for the site level ini file.
                  ###
                  sed -i "s/.*allow_private_file_downloads.*/allow_private_file_downloads = TRUE/g" $_DIR_CTRL_FILE &> /dev/null
                fi
              fi
            else
              if [ -e "/var/xdrago/conf/default.boa_site_control.ini" ] && [ ! -e "$_DIR_CTRL_FILE" ] ; then
                cp -af /var/xdrago/conf/default.boa_site_control.ini $_DIR_CTRL_FILE &> /dev/null
                chown $_THIS_HM_USER:users $_DIR_CTRL_FILE
                chmod 0664 $_DIR_CTRL_FILE
              fi
              if [ -e "$_DIR_CTRL_FILE" ] ; then
                _AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST=$(grep "^allow_private_file_downloads = FALSE" $_DIR_CTRL_FILE)
                if [[ "$_AUTO_CONFIG_PRIVATE_FILE_DOWNLOADS_TEST" =~ "allow_private_file_downloads = FALSE" ]] ; then
                  true
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
            if [ -e "/var/xdrago/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /var/xdrago/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_FACEBOOK_INTEGRATION_TEST=$(grep "^auto_detect_facebook_integration = TRUE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_FACEBOOK_INTEGRATION_TEST" =~ "auto_detect_facebook_integration = TRUE" ]] ; then
                true
              else
                ###
                ### Do this only for the platform level ini file, so the site level ini file can disable
                ### this check by setting it explicitly to auto_detect_facebook_integration = FALSE
                ###
                sed -i "s/.*auto_detect_facebook_integration.*/auto_detect_facebook_integration = TRUE/g" $_PLR_CTRL_FILE &> /dev/null
              fi
            fi
          else
            if [ -e "/var/xdrago/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /var/xdrago/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_FACEBOOK_INTEGRATION_TEST=$(grep "^auto_detect_facebook_integration = FALSE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_FACEBOOK_INTEGRATION_TEST" =~ "auto_detect_facebook_integration = FALSE" ]] ; then
                true
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
            if [ -e "/var/xdrago/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /var/xdrago/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST=$(grep "^auto_detect_domain_access_integration = TRUE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST" =~ "auto_detect_domain_access_integration = TRUE" ]] ; then
                true
              else
                ###
                ### Do this only for the platform level ini file, so the site level ini file can disable
                ### this check by setting it explicitly to auto_detect_domain_access_integration = FALSE
                ###
                sed -i "s/.*auto_detect_domain_access_integration.*/auto_detect_domain_access_integration = TRUE/g" $_PLR_CTRL_FILE &> /dev/null
              fi
            fi
          else
            if [ -e "/var/xdrago/conf/default.boa_platform_control.ini" ] && [ ! -e "$_PLR_CTRL_FILE" ] ; then
              cp -af /var/xdrago/conf/default.boa_platform_control.ini $_PLR_CTRL_FILE &> /dev/null
              chown $_THIS_HM_USER:users $_PLR_CTRL_FILE
              chmod 0664 $_PLR_CTRL_FILE
            fi
            if [ -e "$_PLR_CTRL_FILE" ] ; then
              _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST=$(grep "^auto_detect_domain_access_integration = FALSE" $_PLR_CTRL_FILE)
              if [[ "$_AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION_TEST" =~ "auto_detect_domain_access_integration = FALSE" ]] ; then
                true
              else
                sed -i "s/.*auto_detect_domain_access_integration.*/auto_detect_domain_access_integration = FALSE/g" $_PLR_CTRL_FILE &> /dev/null
              fi
            fi
          fi

          ###
          ### Disable redis_lock_enable in case it is enabled until https://drupal.org/node/2135545 is fixed
          ### You can still enable it for testing either in local.settings.php or /data/conf/override.global.inc
          ### with line $all_ini['redis_lock_enable'] = TRUE;
          ###
          if [ -e "$_PLR_CTRL_FILE" ] ; then
            _REDIS_LOCK_ENABLE_TEST=$(grep "^redis_lock_enable = TRUE" $_PLR_CTRL_FILE)
            if [[ "$_REDIS_LOCK_ENABLE_TEST" =~ "redis_lock_enable = TRUE" ]] ; then
              sed -i "s/.*redis_lock_enable.*/;redis_lock_enable = FALSE/g" $_PLR_CTRL_FILE &> /dev/null
            fi
          fi
          if [ -e "$_DIR_CTRL_FILE" ] ; then
            _REDIS_LOCK_ENABLE_TEST=$(grep "^redis_lock_enable = TRUE" $_DIR_CTRL_FILE)
            if [[ "$_REDIS_LOCK_ENABLE_TEST" =~ "redis_lock_enable = TRUE" ]] ; then
              sed -i "s/.*redis_lock_enable.*/;redis_lock_enable = FALSE/g" $_DIR_CTRL_FILE &> /dev/null
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
            run_drush4_cmd "@hostmaster dis cache syslog dblog -y"
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
        fi
      fi
      ;;
    esac
  fi
}

fix_static_permissions () {
  if [ ! -f "$Plr/profiles/permissions-fix.info" ] ; then
    chown -R ${_THIS_HM_USER}.ftp:users $Plr/profiles &> /dev/null
    find $Plr/profiles -type d -exec chmod 02775 {} \; &> /dev/null
    find $Plr/profiles -type f -exec chmod 0664 {} \; &> /dev/null
    echo fixed > $Plr/profiles/permissions-fix.info
    chown $_THIS_HM_USER:users $Plr/profiles/permissions-fix.info
    chmod 0664 $Plr/profiles/permissions-fix.info
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
  if [ ! -f "$Plr/sites/all/permissions-fix-$_NOW.info" ] ; then
    mkdir -p $Plr/sites/all/{modules,themes,libraries}
    chown -R ${_THIS_HM_USER}.ftp:users $Plr/sites/all/{modules,themes,libraries}/* &> /dev/null
    chown $_THIS_HM_USER:users $Plr/drushrc.php $Plr/sites $Plr/sites/sites.php $Plr/sites/all $Plr/sites/all/{modules,themes,libraries} &> /dev/null
    find $Plr/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
    find $Plr/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
    ### known exceptions
    chmod 775 $Plr/sites/all/modules/print/lib/wkhtmltopdf* &> /dev/null
    chmod -R 775 $Plr/sites/all/libraries/tcpdf/cache &> /dev/null
    chown -R www-data:www-data $Plr/sites/all/libraries/tcpdf/cache &> /dev/null
    echo fixed > $Plr/sites/all/permissions-fix-$_NOW.info
    chown $_THIS_HM_USER:users $Plr/sites/all/permissions-fix-$_NOW.info
    chmod 0664 $Plr/sites/all/permissions-fix-$_NOW.info
  fi
  ### directory and settings files - site level
  chown $_THIS_HM_USER:users $Dir &> /dev/null
  chown $_THIS_HM_USER:www-data $Dir/{local.settings.php,settings.php,civicrm.settings.php} &> /dev/null
  find $Dir/*.php -type f -exec chmod 0440 {} \; &> /dev/null
  chmod 0640 $Dir/civicrm.settings.php &> /dev/null
  ### modules,themes,libraries - site level
  chown -R ${_THIS_HM_USER}.ftp:users $Dir/{modules,themes,libraries}/* &> /dev/null
  chown $_THIS_HM_USER:users $Dir/drushrc.php $Dir/{modules,themes,libraries} &> /dev/null
  find $Dir/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
  find $Dir/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
  ### files - site level
  chown -L -R www-data:www-data $Dir/files &> /dev/null
  find $Dir/files/* -type d -exec chmod 02775 {} \; &> /dev/null
  find $Dir/files/* -type f -exec chmod 0664 {} \; &> /dev/null
  chmod 02775 $Dir/files &> /dev/null
  chown $_THIS_HM_USER:www-data $Dir/files &> /dev/null
  chown $_THIS_HM_USER:www-data $Dir/files/{tmp,images,pictures,css,js,advagg_css,advagg_js,ctools,ctools/css,imagecache,locations,xmlsitemap,deployment,styles,private} &> /dev/null
  ### private - site level
  chown -L -R www-data:www-data $Dir/private &> /dev/null
  find $Dir/private -type d -exec chmod 02775 {} \; &> /dev/null
  find $Dir/private -type f -exec chmod 0664 {} \; &> /dev/null
  chown $_THIS_HM_USER:www-data $Dir/private &> /dev/null
  chown $_THIS_HM_USER:www-data $Dir/private/{files,temp} &> /dev/null
  chown $_THIS_HM_USER:www-data $Dir/private/files/backup_migrate &> /dev/null
  chown $_THIS_HM_USER:www-data $Dir/private/files/backup_migrate/{manual,scheduled} &> /dev/null
  chown -L -R $_THIS_HM_USER:www-data $Dir/private/config &> /dev/null
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
    echo ";;  This is a platform level ACTIVE INI file which can be used to modify"    >> $_CTRL_FILE
    echo ";;  default BOA system behaviour for all sites hosted on this platform."     >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> $_CTRL_FILE
    echo ";;  default.boa_platform_control.ini, since this ACTIVE INI file"            >> $_CTRL_FILE
    echo ";;  may not include all options available after upgrade to BOA-2.1.2"        >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Note that it takes ~5 seconds to see any modification results in action" >> $_CTRL_FILE
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."         >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
  fi
}

add_note_site_ini () {
  if [ -e "$_CTRL_FILE" ] ; then
    echo "" >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  This is a site level ACTIVE INI file which can be used to modify"        >> $_CTRL_FILE
    echo ";;  default BOA system behaviour for this site only."                        >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> $_CTRL_FILE
    echo ";;  default.boa_site_control.ini, since this ACTIVE INI file"                >> $_CTRL_FILE
    echo ";;  may not include all options available after upgrade to BOA-2.1.2"        >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
    echo ";;  Note that it takes ~5 seconds to see any modification results in action" >> $_CTRL_FILE
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."         >> $_CTRL_FILE
    echo ";;" >> $_CTRL_FILE
  fi
}

fix_platform_control_files () {
  if [ -e "/var/xdrago/conf/default.boa_platform_control.ini" ] ; then
    if [ ! -e "$Plr/sites/all/modules/default.boa_platform_control.ini" ] || [ "$_CTRL_TPL_FORCE_UPDATE" = "YES" ] ; then
      cp -af /var/xdrago/conf/default.boa_platform_control.ini $Plr/sites/all/modules/ &> /dev/null
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
  if [ -e "/var/xdrago/conf/default.boa_site_control.ini" ] ; then
    if [ ! -e "$Dir/modules/default.boa_site_control.ini" ] || [ "$_CTRL_TPL_FORCE_UPDATE" = "YES" ] ; then
      cp -af /var/xdrago/conf/default.boa_site_control.ini $Dir/modules/ &> /dev/null
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

process () {
  for Site in `find $User/config/server_master/nginx/vhost.d -maxdepth 1 -mindepth 1 -type f | sort`
  do
    #echo Counting Site $Site
    Dom=`echo $Site | cut -d'/' -f9 | awk '{ print $1}'`
    if [ -e "$User/.drush/$Dom.alias.drushrc.php" ] ; then
      echo Dom is $Dom
      Dir=`cat $User/.drush/$Dom.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      Plr=`cat $User/.drush/$Dom.alias.drushrc.php | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      fix_site_control_files
      fix_platform_control_files
      fix_o_contrib_symlink
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
      fix_clear_cache
      if [ "$_PERMISSIONS_FIX" = "YES" ] ; then
        fix_permissions
      fi
    fi
  done
}

delete_this_platform () {
  run_drush4_dash_cmd "@hostmaster hosting-task @platform_${_THIS_PLATFORM_NAME} delete --force"
  echo "Old empty platform_${_THIS_PLATFORM_NAME} will be deleted"
}

check_old_empty_platforms () {
  if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
    if [[ "$_HOST_TEST" =~ "v189q.nyc." ]] || [[ "$_HOST_TEST" =~ "v182q.nyc." ]] || [[ "$_HOST_TEST" =~ "ocean.nyc." ]] ; then
      true
    else
      _DEL_OLD_EMPTY_PLATFORMS="60"
    fi
  fi
  if [ ! -z "$_DEL_OLD_EMPTY_PLATFORMS" ] ; then
    if [ "$_DEL_OLD_EMPTY_PLATFORMS" -gt "0" ] ; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to ${_DEL_OLD_EMPTY_PLATFORMS} days on ${_THIS_HM_USER} instance"
      for Platform in `find $User/.drush/platform_* -maxdepth 1 -mtime +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`
      do
        _THIS_PLATFORM_NAME=`echo "$Platform" | sed "s/.*platform_//g; s/.alias.drushrc.php//g" | awk '{ print $1}'`
        _THIS_PLATFORM_ROOT=`cat $Platform | grep 'root' | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
        _THIS_PLATFORM_SITE=`grep "${_THIS_PLATFORM_ROOT}/sites/" $User/.drush/* | grep site_path`
        if [ ! -e "${_THIS_PLATFORM_ROOT}/sites/all" ] ; then
          echo "WARNING: ghost platform found: $_THIS_PLATFORM_ROOT"
          rm -f $User/.drush/platform_${_THIS_PLATFORM_NAME}.alias.drushrc.php
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

action () {
  for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`
  do
    NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
    CTL_LOAD=888
    if [ -e "$User/config/server_master/nginx/vhost.d" ] ; then
      if [ $NOW_LOAD -lt $CTL_LOAD ] ; then
        _THIS_HM_USER=`echo $User | cut -d'/' -f4 | awk '{ print $1}'`
        _THIS_HM_SITE=`cat $User/.drush/hostmaster.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
        echo load is $NOW_LOAD while maxload is $CTL_LOAD
        echo User $User
        _SQL_CONVERT=NO
        _DEL_OLD_EMPTY_PLATFORMS="0"
        if [ -e "/root/.${_THIS_HM_USER}.octopus.cnf" ] ; then
          source /root/.${_THIS_HM_USER}.octopus.cnf
          _DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS//[^0-9]/}
        fi
        process
        if [ -e "$_THIS_HM_SITE" ] ; then
          cd $_THIS_HM_SITE
          run_drush4_dash_cmd "@hostmaster vset --always-set hosting_advanced_cron_default_interval 10800"
          run_drush4_dash_cmd "@hostmaster vset --always-set hosting_queue_advanced_cron_frequency 1"
          run_drush4_dash_cmd "@hostmaster vset --always-set hosting_queue_cron_frequency 53222400"
          run_drush4_dash_cmd "@hostmaster vset --always-set hosting_cron_use_backend 1"
          run_drush4_dash_cmd "@hostmaster vset --always-set hosting_ignore_default_profiles 0"
        fi
        if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
          rm -f -r $User/clients/admin &> /dev/null
          rm -f -r $User/clients/omega8ccgmailcom &> /dev/null
          rm -f -r $User/clients/nocomega8cc &> /dev/null
        fi
        rm -f -r $User/clients/*/backups &> /dev/null
        symlinks -dr $User/clients &> /dev/null
        if [ -e "/home/${_THIS_HM_USER}.ftp" ] ; then
          symlinks -dr /home/${_THIS_HM_USER}.ftp &> /dev/null
          rm -f /home/${_THIS_HM_USER}.ftp/{.profile,.bash_logout,.bashrc}
        fi
        run_drush4_dash_cmd "@hostmaster sqlq \"DELETE FROM hosting_task WHERE task_type='delete' AND task_status='-1'\""
        run_drush4_dash_cmd "@hostmaster sqlq \"DELETE FROM hosting_task WHERE task_type='delete' AND task_status='0' AND executed='0'\""
        check_old_empty_platforms
        echo Done for $User
      else
        echo load is $NOW_LOAD while maxload is $CTL_LOAD
        echo ...we have to wait...
      fi
      echo
      echo
    fi
  done
}

###--------------------###
echo "INFO: Daily maintenance start"
_NOW=`date +%y%m%d-%H%M`
_HOST_TEST=`uname -n 2>&1`
_VM_TEST=`uname -a 2>&1`
if [[ "$_VM_TEST" =~ beng ]] ; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
_CTRL_TPL_FORCE_UPDATE=YES
sed -i "s/58 9/58 2/g" /var/spool/cron/crontabs/root &> /dev/null
chown root:crontab /var/spool/cron/crontabs/root
chmod 600 /var/spool/cron/crontabs/root
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
if test -f /var/run/boa_wait.pid ; then
  touch /var/xdrago/log/wait-counter
  exit 1
else
  source /root/.barracuda.cnf
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
  if [ ! -e "/data/all/permissions-fix-post-up-2.1.1.info" ] ; then
    find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} -type d -exec chmod 02775 {} \; &> /dev/null
    find /data/disk/*/distro/*/*/sites/all/{libraries,modules,themes} -type f -exec chmod 0664 {} \; &> /dev/null
    echo fixed > /data/all/permissions-fix-post-up-2.1.1.info
  fi
  action >/var/xdrago/log/daily/daily-$_NOW.log 2>&1
  if [ "$_PERMISSIONS_FIX" = "YES" ] ; then
    echo "INFO: Removing old permissions-fix-* files"
    find /data/disk/*/distro/*/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
    find /data/disk/*/static/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
    find /data/disk/*/static/*/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
    find /data/disk/*/static/*/*/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
  fi
  if [ "$_NGINX_FORWARD_SECRECY" = "YES" ] ; then
    for File in `find /etc/ssl/private/*.key -type f` ; do
      _PFS_TEST=$(grep "DH PARAMETERS" $File)
      if [[ "$_PFS_TEST" =~ "DH PARAMETERS" ]] ; then
        true
      else
        openssl dhparam -rand - 2048 >> $File
      fi
    done
    for File in `find /etc/ssl/private/*.crt -type f` ; do
      _PFS_TEST=$(grep "DH PARAMETERS" $File)
      if [[ "$_PFS_TEST" =~ "DH PARAMETERS" ]] ; then
        true
      else
        openssl dhparam -rand - 2048 >> $File
      fi
    done
    /etc/init.d/nginx reload
  fi
fi

###--------------------###
echo "INFO: Checking BARRACUDA version"
rm -f /opt/tmp/barracuda-version.txt*
curl -s --retry 3 --retry-delay 15 -A iCab "http://files.aegir.cc/versions/master/aegir/conf/barracuda-version.txt" -o /opt/tmp/barracuda-version.txt
if [ ! -e "/opt/tmp/barracuda-version.txt" ] ; then
  sleep 30
  curl -s --retry 3 --retry-delay 15 -A iCab "http://files.aegir.cc/versions/master/aegir/conf/barracuda-version.txt" -o /opt/tmp/barracuda-version.txt
fi
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

 Changelog: http://bit.ly/newboa

 --
 This e-mail has been sent by your Barracuda server upgrade monitor.

EOF
    echo "INFO: Update notice sent: OK"
    fi
  fi
fi
#
if [ "$_PERMISSIONS_FIX" = "YES" ] && [ ! -z "$_INSTALLER_VERSION" ] && [ -e "/opt/tmp/barracuda-version.txt" ] && [ ! -e "/data/all/permissions-fix-$_INSTALLER_VERSION-fixed.info" ] ; then
  echo "INFO: Fixing permissions in the /data/all tree..."
  find /data/all -type d -exec chmod 0755 {} \; &> /dev/null
  find /data/all -type f -exec chmod 0644 {} \; &> /dev/null
  find /data/conf -type d -exec chmod 0755 {} \; &> /dev/null
  find /data/conf -type f -exec chmod 0644 {} \; &> /dev/null
  chown -R root:root /data/conf
  chmod 02775 /data/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  chown -R root:root /data/all
  chown -R root:users /data/all/*/*/sites
  echo fixed > /data/all/permissions-fix-$_INSTALLER_VERSION-fixed.info
fi
echo "INFO: Daily maintenance complete"
exit 0
###EOF2013###
