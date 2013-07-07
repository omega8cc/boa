#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

###----------------------------------------###
### AUTOMATED MAINTENANCE CONFIGURATION    ###
###----------------------------------------###
###
### Note: the modules on/off switch will
### affect only sites without "dev." in the
### *main* domain name (the "dev." in the
### domain alias is not checked here).
###
_PERMISSIONS=YES
_MODULES=YES
_MODULES_ON_SEVEN="robotstxt"
_MODULES_ON_SIX="path_alias_cache robotstxt"
_MODULES_OFF_SEVEN="syslog dblog l10n_update devel performance"
_MODULES_OFF_LESS_SEVEN="syslog dblog l10n_update performance devel"
_MODULES_OFF_SIX="syslog cache dblog l10n_update poormanscron supercron css_gzip javascript_aggregator cookie_cache_bypass devel performance"

###-------------SYSTEM-----------------###
fix_user_register_protection () {
  if [ ! -e "$Plr/sites/all/modules/enable_user_register_protection.info" ] && [ -e "$User/static/control/enable_user_register_protection.info" ] ; then
    touch $Plr/sites/all/modules/enable_user_register_protection.info
  fi
}

fix_robots_txt () {
  if [ ! -e "$Dir/files/robots.txt" ] && [ ! -e "$Plr/profiles/hostmaster" ] ; then
    curl -A iCab "http://$Dom/robots.txt?nocache=1&noredis=1" -o $Dir/files/robots.txt
    if [ -e "$Dir/files/robots.txt" ] ; then
      echo >> $Dir/files/robots.txt
    fi
  fi
}

fix_clear_cache () {
  if [ -e "$Plr/profiles/hostmaster" ] ; then
    su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster cc all &> /dev/null"
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
  if [ "$_MODULES" = "YES" ] ; then
    searchStringA="pressflow-5.23.50"
    case $Dir in
      *"$searchStringA"*) ;;
      *)
      if [ -e "$Dir/drushrc.php" ] ; then
        cd $Dir
        if [ -e "$Plr/profiles/hostmaster" ] && [ ! -f "$Plr/profiles/hostmaster/modules-fix.info" ] ; then
          su -s /bin/bash $_THIS_HM_USER -c "drush @hostmaster dis cache syslog dblog -y &> /dev/null"
          echo "modules-fixed" > $Plr/profiles/hostmaster/modules-fix.info
          chown $_THIS_HM_USER:users $Plr/profiles/hostmaster/modules-fix.info
        elif [ -e "$Plr/modules/o_contrib" ] ; then
          su -s /bin/bash $_THIS_HM_USER -c "drush dis $_MODULES_OFF_SIX -y &> /dev/null"
          su -s /bin/bash $_THIS_HM_USER -c "drush en $_MODULES_ON_SIX -y &> /dev/null"
          su -s /bin/bash $_THIS_HM_USER -c "drush sqlq \"UPDATE system SET weight = '-1' WHERE type = 'module' AND name = 'path_alias_cache'\" &> /dev/null"
        elif [ -e "$Plr/modules/o_contrib_seven" ] ; then
          if [ -e "$Plr/profiles/panopoly" ] || [ -e "$Plr/profiles/martplug" ] ; then
            su -s /bin/bash $_THIS_HM_USER -c "drush dis $_MODULES_OFF_LESS_SEVEN -y &> /dev/null"
          else
            su -s /bin/bash $_THIS_HM_USER -c "drush dis $_MODULES_OFF_SEVEN -y &> /dev/null"
          fi
          if [ ! -e "$Plr/sites/all/modules/entitycache_dont_enable.info" ] ; then
            su -s /bin/bash $_THIS_HM_USER -c "drush en entitycache -y &> /dev/null"
          fi
          su -s /bin/bash $_THIS_HM_USER -c "drush en $_MODULES_ON_SEVEN -y &> /dev/null"
        fi
      fi
      ;;
    esac
  fi
}

fix_static_permissions () {
  if [ ! -f "$Plr/profiles/permissions-fix.info" ] ; then
    chown -R $_THIS_HM_USER.ftp:users $Plr/profiles &> /dev/null
    find $Plr/profiles -type d -exec chmod 02775 {} \; &> /dev/null
    find $Plr/profiles -type f -exec chmod 0664 {} \; &> /dev/null
    echo fixed > $Plr/profiles/permissions-fix.info
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
    chown -R $_THIS_HM_USER.ftp:users $Plr/sites/all/{modules,themes,libraries}/* &> /dev/null
    chown $_THIS_HM_USER:users $Plr/drushrc.php $Plr/sites $Plr/sites/all $Plr/sites/all/{modules,themes,libraries} &> /dev/null
    find $Plr/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
    find $Plr/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
    ### known exceptions
    chmod 775 $Plr/sites/all/modules/print/lib/wkhtmltopdf* &> /dev/null
    chmod -R 775 $Plr/sites/all/libraries/tcpdf/cache &> /dev/null
    chown -R www-data:www-data $Plr/sites/all/libraries/tcpdf/cache &> /dev/null
    echo fixed > $Plr/sites/all/permissions-fix-$_NOW.info
  fi
  ### modules,themes,libraries - site level
  chown -R $_THIS_HM_USER.ftp:users $Dir/{modules,themes,libraries}/* &> /dev/null
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
      fix_user_register_protection
      if [ "$_PERMISSIONS" = "YES" ] ; then
        fix_permissions
      fi
    fi
  done
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
        echo Counting User $User
        process
        if [ -e "$_THIS_HM_SITE" ] ; then
          cd $_THIS_HM_SITE
          su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster vset --always-set hosting_advanced_cron_default_interval 10800 &> /dev/null"
          su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster vset --always-set hosting_queue_advanced_cron_frequency 1 &> /dev/null"
          su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster vset --always-set hosting_queue_cron_frequency 53222400 &> /dev/null"
          su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster vset --always-set hosting_cron_use_backend 1 &> /dev/null"
          su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster vset --always-set hosting_ignore_default_profiles 0 &> /dev/null"
        fi
        if [[ "$_VM_TEST" =~ ".host8." ]] ; then
          rm -f -r $User/clients/admin &> /dev/null
          rm -f -r $User/clients/omega8ccgmailcom &> /dev/null
          rm -f -r $User/clients/nocomega8cc &> /dev/null
        fi
        rm -f -r $User/clients/*/backups &> /dev/null
        symlinks -dr $User/clients &> /dev/null
        if [ -e "/home/$_THIS_HM_USER.ftp" ] ; then
          symlinks -dr /home/$_THIS_HM_USER.ftp &> /dev/null
          rm -f /home/$_THIS_HM_USER.ftp/{.profile,.bash_logout,.bashrc}
        fi
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
_VM_TEST=`uname -a 2>&1`
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
  if [[ "$_VM_TEST" =~ ".host8." ]] ; then
    n=$((RANDOM%800+80))
    echo waiting $n sec
    sleep $n
  fi
  action >/var/xdrago/log/daily/daily-$_NOW.log 2>&1
  echo "INFO: Removing old permissions-fix-* files"
  find /data/disk/*/distro/*/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
  find /data/disk/*/static/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
  find /data/disk/*/static/*/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
  find /data/disk/*/static/*/*/*/sites/all/permissions-fix-* -mtime +1 -type f -exec rm -rf {} \; &> /dev/null
fi

###--------------------###
echo "INFO: Checking BARRACUDA version"
cd /opt/tmp
wget -q -U iCab http://drupalcode.org/project/barracuda.git/blob_plain/HEAD:/aegir/conf/barracuda-version.txt
if [ -e "/opt/tmp/barracuda-version.txt" ] ; then
  _INSTALLER_VERSION=`cat /opt/tmp/barracuda-version.txt`
  _VERSIONS_TEST=`cat /var/log/barracuda_log.txt`
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
#
if [ ! -f "/data/all/permissions-fix-$_INSTALLER_VERSION.info" ] ; then
  echo "INFO: Fixing permissions in the /data/all tree..."
  chmod 02775 /data/all/*/*/sites/all/{modules,libraries,themes} &> /dev/null
  chown -R root:root /data/all
  chown -R root:users /data/all/*/*/sites
  echo fixed > /data/all/permissions-fix-$_INSTALLER_VERSION.info
fi
echo "INFO: Daily maintenance complete"
exit 0
###EOF2013###
