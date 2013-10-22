#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

###----------------------------------------###
### AUTOMATED MAINTENANCE CONFIGURATION    ###
###----------------------------------------###

_MODULES_ON_SEVEN="robotstxt"
_MODULES_ON_SIX="path_alias_cache robotstxt"
_MODULES_OFF_SEVEN="background_process dblog devel l10n_update performance syslog ultimate_cron update"
_MODULES_OFF_SIX="background_process cookie_cache_bypass css_gzip dblog devel javascript_aggregator l10n_update performance poormanscron supercron syslog ultimate_cron update"

###-------------SYSTEM-----------------###

run_drush_cmd () {
  su -s /bin/bash $_THIS_HM_USER -c "drush $1 &> /dev/null"
}

run_drush_dash_cmd () {
  su -s /bin/bash - $_THIS_HM_USER -c "drush $1 &> /dev/null"
}

run_drush_nosilent_cmd () {
  su -s /bin/bash $_THIS_HM_USER -c "drush6 $1"
}

check_if_required () {
  _REQ_TEST=$(run_drush_nosilent_cmd "pmi --fields=required_by $1 | grep ':  none'")
  if [[ "$_REQ_TEST" =~ ":  none" ]] ; then
    _REQ=NO
  else
    _REQ=YES
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
      _MODULE_TEST=$(run_drush_nosilent_cmd "pml --status=enabled --type=module | grep \($m\)")
      if [[ "$_MODULE_TEST" =~ "($m)" ]] ; then
        check_if_required "$m"
        if [ "$_REQ" = "NO" ] ; then
          run_drush_cmd "dis $m -y"
          echo $m disabled in $Dom
        else
          echo $m is required and can not be disabled in $Dom
        fi
      fi
    fi
  done
}

enable_modules () {
  for m in $1; do
    _MODULE_TEST=$(run_drush_nosilent_cmd "pml --status=enabled --type=module | grep \($m\)")
    if [[ "$_MODULE_TEST" =~ "($m)" ]] ; then
      true
    else
      run_drush_cmd "en $m -y"
      echo $m enabled in $Dom
    fi
  done
}

fix_user_register_protection () {
  if [ ! -e "$Plr/sites/all/modules/enable_user_register_protection.info" ] && [ -e "$User/static/control/enable_user_register_protection.info" ] ; then
    touch $Plr/sites/all/modules/enable_user_register_protection.info
  fi
  if [ ! -e "$Dir/modules/disable_user_register_protection.info" ] ; then
    Prm=$(drush vget ^user_register$ | cut -d: -f2 | awk '{ print $1}' | sed "s/['\"]//g" | tr -d "\n" 2>&1)
    Prm=${Prm//[^0-2]/}
    echo Prm user_register for $Dom is $Prm
    if [ -e "$Plr/sites/all/modules/enable_user_register_protection.info" ] ; then
      drush vset --always-set user_register 0 &> /dev/null
    else
      if [ "$Prm" = "1" ] || [ -z "$Prm" ] ; then
        drush vset --always-set user_register 2 &> /dev/null
      fi
      drush vset --always-set user_email_verification 1 &> /dev/null
    fi
  fi
}

fix_robots_txt () {
  if [ ! -e "$Dir/files/robots.txt" ] && [ ! -e "$Plr/profiles/hostmaster" ] ; then
    curl -s -A iCab "http://$Dom/robots.txt?nocache=1&noredis=1" -o $Dir/files/robots.txt
    if [ -e "$Dir/files/robots.txt" ] ; then
      echo >> $Dir/files/robots.txt
    fi
  fi
}

fix_clear_cache () {
  if [ -e "$Plr/profiles/hostmaster" ] ; then
    run_drush_dash_cmd "@hostmaster cc all"
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

fix_modules () {
  if [ "$_MODULES_FIX" = "YES" ] ; then
    searchStringA="pressflow-5.23.50"
    case $Dir in
      *"$searchStringA"*) ;;
      *)
      if [ -e "$Dir/drushrc.php" ] ; then
        cd $Dir
        fix_user_register_protection
        if [ -e "$Plr/profiles/hostmaster" ] && [ ! -f "$Plr/profiles/hostmaster/modules-fix.info" ] ; then
          run_drush_cmd "@hostmaster dis cache syslog dblog -y"
          echo "modules-fixed" > $Plr/profiles/hostmaster/modules-fix.info
          chown $_THIS_HM_USER:users $Plr/profiles/hostmaster/modules-fix.info
        elif [ -e "$Plr/modules/o_contrib" ] ; then
          disable_modules "$_MODULES_OFF_SIX"
          enable_modules "$_MODULES_ON_SIX"
          run_drush_cmd "sqlq \"UPDATE system SET weight = '-1' WHERE type = 'module' AND name = 'path_alias_cache'\""
        elif [ -e "$Plr/modules/o_contrib_seven" ] ; then
          disable_modules "$_MODULES_OFF_SEVEN"
          if [ ! -e "$Plr/sites/all/modules/entitycache_dont_enable.info" ] ; then
            enable_modules "entitycache"
          fi
          enable_modules "$_MODULES_ON_SEVEN"
        fi
        _VIEWS_TEST=$(run_drush_nosilent_cmd "pml --status=enabled --no-core --type=module | grep \(views\)")
        if [[ "$_VIEWS_TEST" =~ "Views" ]] && [ ! -e "$Plr/profiles/hostmaster" ] ; then
          if [ ! -e "$Plr/sites/all/modules/views_cache_bully_dont_enable.info" ] ; then
            if [ -e "$Plr/modules/o_contrib_seven/views_cache_bully" ] || [ -e "$Plr/modules/o_contrib/views_cache_bully" ] ; then
              enable_modules "views_cache_bully"
            fi
          fi
          if [ ! -e "$Plr/sites/all/modules/views_content_cache_dont_enable.info" ] ; then
            if [ -e "$Plr/modules/o_contrib_seven/views_content_cache" ] || [ -e "$Plr/modules/o_contrib/views_content_cache" ] ; then
              enable_modules "views_content_cache"
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

process () {
  for Site in `find $User/config/server_master/nginx/vhost.d -maxdepth 1 -mindepth 1 -type f | sort`
  do
    #echo Counting Site $Site
    Dom=`echo $Site | cut -d'/' -f9 | awk '{ print $1}'`
    if [ -e "$User/.drush/$Dom.alias.drushrc.php" ] ; then
      echo Dom is $Dom
      Dir=`cat $User/.drush/$Dom.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      Plr=`cat $User/.drush/$Dom.alias.drushrc.php | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
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
  run_drush_dash_cmd "@hostmaster hosting-task @platform_${_THIS_PLATFORM_NAME} delete --force"
  echo "Old empty platform_${_THIS_PLATFORM_NAME} will be deleted"
}

check_old_empty_platforms () {
  _DEL_OLD_EMPTY_PLATFORMS="0"
  if [ -e "/root/.${_THIS_HM_USER}.octopus.cnf" ] ; then
    source /root/.${_THIS_HM_USER}.octopus.cnf
    _DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS//[^0-9]/}
  fi
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
        if [ -z $_THIS_PLATFORM_SITE ] ; then
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
        process
        if [ -e "$_THIS_HM_SITE" ] ; then
          cd $_THIS_HM_SITE
          run_drush_dash_cmd "@hostmaster vset --always-set hosting_advanced_cron_default_interval 10800"
          run_drush_dash_cmd "@hostmaster vset --always-set hosting_queue_advanced_cron_frequency 1"
          run_drush_dash_cmd "@hostmaster vset --always-set hosting_queue_cron_frequency 53222400"
          run_drush_dash_cmd "@hostmaster vset --always-set hosting_cron_use_backend 1"
          run_drush_dash_cmd "@hostmaster vset --always-set hosting_ignore_default_profiles 0"
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
curl -s -A iCab "https://raw.github.com/omega8cc/nginx-for-drupal/master/aegir/conf/barracuda-version.txt" -o /opt/tmp/barracuda-version.txt
if [ ! -e "/opt/tmp/barracuda-version.txt" ] ; then
  sleep 30
  curl -s -A iCab "https://raw.github.com/omega8cc/nginx-for-drupal/master/aegir/conf/barracuda-version.txt" -o /opt/tmp/barracuda-version.txt
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
if [ "$_PERMISSIONS_FIX" = "YES" ] && [ ! -z "$_INSTALLER_VERSION" ] && [ -e "/opt/tmp/barracuda-version.txt" ] && [ ! -e "/data/all/permissions-fix-$_INSTALLER_VERSION.info" ] ; then
  echo "INFO: Fixing permissions in the /data/all tree..."
  chmod 02775 /data/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  chown -R root:root /data/all
  chown -R root:users /data/all/*/*/sites
  echo fixed > /data/all/permissions-fix-$_INSTALLER_VERSION.info
fi
echo "INFO: Daily maintenance complete"
exit 0
###EOF2013###
