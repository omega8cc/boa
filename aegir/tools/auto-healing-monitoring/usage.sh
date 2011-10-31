#!/bin/bash

###----------------------------------------###
### AUTOMATED MAINTENANCE CONFIGURATION    ###
###----------------------------------------###
###
### The usage monitor script has now an option
### to fix permissions on all sites and also
### to enable some performance related modules
### plus disable modules known to cause
### performance issues or not recommended
### to run on production sites.
###
### Since it is not always a good idea
### to force it on every run, you may want
### to change default settings below.
###
### Note: the modules on/off switch will
### affect only sites without "dev" in the
### *main* domain name (the "dev" in the
### domain alias is not checked here).
###
_PERMISSIONS=YES
_MODULES=YES
_MODULES_ON="syslog cache path_alias_cache robotstxt filefield_nginx_progress"
_MODULES_OFF="dblog update l10n_update devel cookie_cache_bypass poormanscron supercron expire purge"


###-------------SYSTEM-----------------###

fix_pressflow_core_one()
{
if [ "$_FIX_CORE_ONE" != "NO" ] ; then
  if [ -e "$Plr/modules/o_contrib" ] ; then
    searchStringE="/distro/$_LAST_ALL/"
    case $Plr in
    *"$searchStringE"*)
    if [ ! -e "$Plr/includes/fix_pressflow_core_two.txt" ] ; then
      cp -af /var/opt/pressflow-6-fix/includes/file.inc   $Plr/includes/
      cp -af /var/opt/pressflow-6-fix/includes/common.inc $Plr/includes/
      echo fixed > $Plr/includes/fix_pressflow_core_two.txt
    fi
    ;;
    *) ;;
    esac
  fi
fi
}

fix_clear_cache()
{
if [ -d "$Plr/profiles/hostmaster" ] ; then
  cd $Dir
  su -s /bin/bash $_THIS_HM_USER -c "drush cc all &> /dev/null"
fi
}

fix_boost_cache()
{
if [ -d "$Plr/cache/normal" ] ; then
  rm -f -r $Plr/cache/normal/*
  rm -f -r $Plr/cache/perm/*
  rm -f -r $Plr/cache/mobile-tablet/*
  rm -f -r $Plr/cache/mobile-smart/*
  rm -f -r $Plr/cache/mobile-other/*
  chown -R $_THIS_HM_USER:www-data $Plr/cache
  chmod -R 2777 $Plr/cache
fi
if [ ! -d "$Plr/cache/mobile-smart" ] ; then
  mkdir -p $Plr/cache/{normal,perm,mobile-tablet,mobile-smart,mobile-other}
  chown -R $_THIS_HM_USER:www-data $Plr/cache
  chmod -R 2777 $Plr/cache
fi
if [ -f "$Plr/robots.txt" ] || [ -L "$Plr/robots.txt" ]; then
  rm -f $Plr/robots.txt
fi
}

read_account_data () {
  if [ -e "/data/disk/$_THIS_HM_USER/log/email.txt" ] ; then
    _CLIENT_EMAIL=`cat /data/disk/$_THIS_HM_USER/log/email.txt`
    _CLIENT_EMAIL=`echo -n $_CLIENT_EMAIL | tr -d "\n"`
  fi
  if [ -e "/data/disk/$_THIS_HM_USER/log/cores.txt" ] ; then
    _CLIENT_CORES=`cat /data/disk/$_THIS_HM_USER/log/cores.txt`
    _CLIENT_CORES=`echo -n $_CLIENT_CORES | tr -d "\n"`
  fi
}

send_notice_core () {
  _ADM_EMAIL="support@omega8.cc"
  _BCC_EMAIL="notify@omega8.cc"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=`mail -V 2>&1`
  if [[ $_MAILX_TEST =~ invalid ]] ; then
  cat <<EOF | mail -a "From: $_ADM_EMAIL" -e -b $_BCC_EMAIL -s "URGENT: Please migrate $Dom site to Pressflow" $_CLIENT_EMAIL
Hello,

Our system detected that you are using vanilla Drupal core
for site $Dom.

The platform root directory for this site is:
$Plr

Using non-Pressflow 6.x core is not allowed on our servers,
unless it is a temporary result of your site import, but
every imported site should be migrated to Pressflow based
platform as soon as possible.

If the site is not migrated to Pressflow based platform
in seven (7) days, it may cause service interruption.

We are working hard to deliver top performance hosting
for your Drupal sites and we appreciate your efforts
to meet the requirements, which are an integral part
of the quality you can expect from Omega8.cc.

--
This e-mail has been sent by your Aegir platform core monitor.

EOF
  else
  cat <<EOF | mail -r $_ADM_EMAIL -e -b $_BCC_EMAIL -s "URGENT: Please migrate $Dom site to Pressflow" $_CLIENT_EMAIL
Hello,

Our system detected that you are using vanilla Drupal core
for site $Dom.

The platform root directory for this site is:
$Plr

Using non-Pressflow 6.x core is not allowed on our servers,
unless it is a temporary result of your site import, but
every imported site should be migrated to Pressflow based
platform as soon as possible.

If the site is not migrated to Pressflow based platform
in seven (7) days, it may cause service interruption.

We are working hard to deliver top performance hosting
for your Drupal sites and we appreciate your efforts
to meet the requirements, which are an integral part
of the quality you can expect from Omega8.cc.

--
This e-mail has been sent by your Aegir platform core monitor.

EOF
  fi
  echo "INFO: Pressflow notice sent to $_CLIENT_EMAIL [$_THIS_HM_USER]: OK"
}

fix_o_contrib_symlink()
{
if [ "$_O_CONTRIB" != "NO" ] ; then
  if [ -e "$Plr/web.config" ] ; then
    if [ ! -e "$Plr/modules/o_contrib_seven" ] ; then
      ln -s $_O_CONTRIB_SEVEN $Plr/modules/o_contrib_seven
    fi
  else
    if [ -e "$Plr/modules/watchdog" ] ; then
      if [ -e "$Plr/modules/o_contrib" ] ; then
        rm -f $Plr/modules/o_contrib
      fi
      echo Drupal 5.x Platform detected in $Plr
    else
      if [ ! -e "$Plr/modules/o_contrib" ] ; then
        ln -s $_O_CONTRIB $Plr/modules/o_contrib
      fi
      if [ ! -e "$Plr/modules/path_alias_cache" ] ; then
        echo Vanilla Drupal 6.x Platform detected in $Plr
        if [[ $_VM_TEST =~ ".host8." ]] ; then
          read_account_data
          send_notice_core
        fi
      fi
    fi
  fi
fi
}

fix_modules()
{
if [ "$_MODULES" = "YES" ]; then
      searchStringA="off-7."
      searchStringB="-5."
      searchStringC="openpublic-off"
      case $Dir in
        *"$searchStringA"*) ;;
        *"$searchStringB"*) ;;
        *"$searchStringC"*) ;;
        *)
        if [ -e "$Dir/drushrc.php" ] ; then
          cd $Dir
          if [ -d "$Plr/profiles/hostmaster" ] && [ ! -f "$Plr/profiles/hostmaster/modules-fix.txt" ] ; then
            su -s /bin/bash $_THIS_HM_USER -c "drush dis cache -y &> /dev/null"
            su -s /bin/bash $_THIS_HM_USER -c "drush en syslog -y &> /dev/null"
            echo "modules-fixed" > $Plr/profiles/hostmaster/modules-fix.txt
            chown $_THIS_HM_USER:users $Plr/profiles/hostmaster/modules-fix.txt
          else
            su -s /bin/bash $_THIS_HM_USER -c "drush dis $_MODULES_OFF -y &> /dev/null"
            su -s /bin/bash $_THIS_HM_USER -c "drush en $_MODULES_ON -y &> /dev/null"
          fi
        fi
        ;;
      esac
fi
}

fix_permissions()
{
if [ "$_PERMISSIONS" = "YES" ]; then
      chown $_THIS_HM_USER:users $Dir/{modules,themes,libraries} &> /dev/null
      chown -R $_THIS_HM_USER.ftp:users $Dir/{modules,themes,libraries}/* &> /dev/null
      find $Dir/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
      find $Dir/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
      chown -R $_THIS_HM_USER:www-data $Dir/files &> /dev/null
      chown -R $_THIS_HM_USER:www-data $Dir/private &> /dev/null
      find $Dir/files -type d -exec chmod 02775 {} \; &> /dev/null
      find $Dir/files -type f -exec chmod 0664 {} \; &> /dev/null
      find $Dir/private -type d -exec chmod 02775 {} \; &> /dev/null
      find $Dir/private -type f -exec chmod 0664 {} \; &> /dev/null
      chown $_THIS_HM_USER:users $Plr/sites/all/{modules,themes,libraries} &> /dev/null
      chown -R $_THIS_HM_USER.ftp:users $Plr/sites/all/{modules,themes,libraries}/* &> /dev/null
      find $Plr/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
      find $Plr/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
      chmod 775 $Plr/sites/all/modules/print/lib/wkhtmltopdf* &> /dev/null
fi
}

count()
{
for Site in `find $User/config/server_master/nginx/vhost.d -maxdepth 1 -type f | sort`
do
    #echo Counting Site $Site
    Dom=`echo $Site | cut -d'/' -f9 | awk '{ print $1}'`
    echo Dom is $Dom
    if [ -e "$User/.drush/$Dom.alias.drushrc.php" ] ; then
      Dir=`cat $User/.drush/$Dom.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      Plr=`cat $User/.drush/$Dom.alias.drushrc.php | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      fix_o_contrib_symlink
      fix_boost_cache
      fix_permissions
      fix_clear_cache
      fix_pressflow_core_one
      searchStringD="dev"
      case $Dom in
        *"$searchStringD"*) ;;
        *)
        fix_modules
        ;;
      esac
      #echo Dir is $Dir
      if [ -e "$Dir/drushrc.php" ] ; then
        Dat=`cat $Dir/drushrc.php | grep "options\['db_name'\] = " | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,';]//g"`
        #echo Dat is $Dat
        if [ -d "$Dir" ] ; then
          DirSize=`du -s $Dir`
          DirSize=`echo "$DirSize" | cut -d'/' -f1 | awk '{ print $1}' | sed "s/[\/\s+]//g"`
          SumDir=$(($SumDir + $DirSize))
          echo DirSize of $Dom is $DirSize
        fi
        if [ -d "/var/lib/mysql/$Dat" ] ; then
          DatSize=`du -s /var/lib/mysql/$Dat`
          DatSize=`echo "$DatSize" | cut -d'/' -f1 | awk '{ print $1}' | sed "s/[\/\s+]//g"`
          SumDat=$(($SumDat + $DatSize))
          echo DatSize of $Dat is $DatSize
        else
          echo Database $Dat does not exist
        fi
      fi
    fi
done
}

send_notice_sql () {
  _ADM_EMAIL="billing@omega8.cc"
  _BCC_EMAIL="notify@omega8.cc"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=`mail -V 2>&1`
  if [[ $_MAILX_TEST =~ invalid ]] ; then
  cat <<EOF | mail -a "From: $_ADM_EMAIL" -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [sql-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES Aegir Cores.

Your allowed databases space is $_CLIENT_SQL_LIMIT MB.
You are currently using $SumDatH MB of databases space.

Please reduce your usage by deleting no longer used sites,
or purchase enough Aegir Cores to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

--
This e-mail has been sent by your Aegir resources usage monitor.

EOF
  else
  cat <<EOF | mail -r $_ADM_EMAIL -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [sql-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES Aegir Cores.

Your allowed databases space is $_CLIENT_SQL_LIMIT MB.
You are currently using $SumDatH MB of databases space.

Please reduce your usage by deleting no longer used sites,
or purchase enough Aegir Cores to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

--
This e-mail has been sent by your Aegir resources usage monitor.

EOF
  fi
  echo "INFO: Update notice sent to $_CLIENT_EMAIL [$_THIS_HM_USER]: OK"
}

send_notice_disk () {
  _ADM_EMAIL="billing@omega8.cc"
  _BCC_EMAIL="notify@omega8.cc"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=`mail -V 2>&1`
  if [[ $_MAILX_TEST =~ invalid ]] ; then
  cat <<EOF | mail -a "From: $_ADM_EMAIL" -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [disk-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES Aegir Cores.

Your allowed disk space is $_CLIENT_DSK_LIMIT MB.
You are currently using $HomSizH MB of disk space.

Please reduce your usage by deleting old backups, files,
and no longer used sites, or purchase enough Aegir Cores
to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

--
This e-mail has been sent by your Aegir resources usage monitor.

EOF
  else
  cat <<EOF | mail -r $_ADM_EMAIL -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [disk-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES Aegir Cores.

Your allowed disk space is $_CLIENT_DSK_LIMIT MB.
You are currently using $HomSizH MB of disk space.

Please reduce your usage by deleting old backups, files,
and no longer used sites, or purchase enough Aegir Cores
to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

--
This e-mail has been sent by your Aegir resources usage monitor.

EOF
  fi
  echo "INFO: Update notice sent to $_CLIENT_EMAIL [$_THIS_HM_USER]: OK"
}

check_limits () {
  read_account_data
  _CLIENT_SQL_LIMIT=256
  _CLIENT_DSK_LIMIT=2560
  let "_CLIENT_SQL_LIMIT *= $_CLIENT_CORES"
  let "_CLIENT_DSK_LIMIT *= $_CLIENT_CORES"
  echo _CLIENT_CORES is $_CLIENT_CORES
  echo _CLIENT_SQL_LIMIT is $_CLIENT_SQL_LIMIT
  echo _CLIENT_DSK_LIMIT is $_CLIENT_DSK_LIMIT
  if [ "$SumDatH" -gt "$_CLIENT_SQL_LIMIT" ] ; then
    send_notice_sql
    echo SQL Usage for $_THIS_HM_USER above limits
  else
    echo SQL Usage for $_THIS_HM_USER below limits
  fi
  if [ "$HomSizH" -gt "$_CLIENT_DSK_LIMIT" ] ; then
    send_notice_disk
    echo Disk Usage for $_THIS_HM_USER above limits
  else
    echo Disk Usage for $_THIS_HM_USER below limits
  fi
}

action()
{
for User in `find /data/disk/ -maxdepth 1 -type d | sort`
do
  NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
  CTL_LOAD=888
  if [ -d "$User/config/server_master/nginx/vhost.d" ] ; then
    if [ $NOW_LOAD -lt $CTL_LOAD ]; then
      SumDir=0
      SumDat=0
      HomSiz=0
      HxmSiz=0
      _THIS_HM_USER=`echo $User | cut -d'/' -f4 | awk '{ print $1}'`
      _THIS_HM_SITE=`cat $User/.drush/hostmaster.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      echo load is $NOW_LOAD while maxload is $CTL_LOAD
      echo Counting User $User
      count
      if [ -d "/home/$_THIS_HM_USER.ftp" ] ; then
        HxmSiz=`du -s /home/$_THIS_HM_USER.ftp` &> /dev/null
        HxmSiz=`echo "$HxmSiz" | cut -d'/' -f1 | awk '{ print $1}' | sed "s/[\/\s+]//g"`
      fi
      HomSiz=`du -s $User` &> /dev/null
      HomSiz=`echo "$HomSiz" | cut -d'/' -f1 | awk '{ print $1}' | sed "s/[\/\s+]//g"`
      HomSiz=$(($HomSiz + $HxmSiz))
      HomSizH=`echo "scale=0; $HomSiz/1024" | bc`;
      SumDatH=`echo "scale=0; $SumDat/1024" | bc`;
      SumDirH=`echo "scale=0; $SumDir/1024" | bc`;
      echo HomSiz is $HomSiz or $HomSizH MB
      echo SumDir is $SumDir or $SumDirH MB
      echo SumDat is $SumDat or $SumDatH MB
      if [[ $_VM_TEST =~ ".host8." ]] ; then
        check_limits
      fi
      if [ -d "$_THIS_HM_SITE" ] ; then
        cd $_THIS_HM_SITE
        su -s /bin/bash $_THIS_HM_USER -c "drush vset --always-set site_footer 'Daily Usage Monitor | Disk <strong>$HomSizH</strong> MB | Databases <strong>$SumDatH</strong> MB | <strong>$_CLIENT_CORES</strong> C' &> /dev/null"
        if [ ! -e "$User/log/custom_cron" ] ; then
          su -s /bin/bash $_THIS_HM_USER -c "drush vset --always-set hosting_queue_cron_frequency 3600 &> /dev/null"
          su -s /bin/bash $_THIS_HM_USER -c "drush vset --always-set hosting_cron_use_backend 0 &> /dev/null"
        fi
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


###-------------SYSTEM-----------------###

_NOW=`date +%y%m%d-%H%M`
_VM_TEST=`uname -a 2>&1`
#
# Check for last all nr
if [ -d "/data/all" ] ; then
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
# Fix one for Pressflow core
_FIX_CORE_ONE=YES
rm -f -r /var/opt/pressflow-6-fix
bzr branch lp:pressflow/6.x /var/opt/pressflow-6-fix &> /dev/null
#
mkdir -p /var/xdrago/log/usage
if test -f /var/xdrago/log/optimize_mysql_ao.pid ; then
  touch /var/xdrago/log/wait-counter
  exit
else
  #touch /var/xdrago/log/optimize_mysql_ao.pid
  #touch /var/run/octopus_barracuda.pid
  sleep 60
  action >/var/xdrago/log/usage/usage-$_NOW.log 2>&1
  killall memcached &> /dev/null
  bash /var/xdrago/memcache.sh
  invoke-rc.d redis-server stop 2>&1
  sleep 2
  rm -f /var/lib/redis/*
  rm -f /var/log/redis/*
  killall redis-server &> /dev/null
  rm -f /var/lib/redis/*
  sleep 2
  invoke-rc.d redis-server restart 2>&1
  sleep 2
  rm -f /var/lib/redis/*
  invoke-rc.d redis-server restart 2>&1
  #rm -f /var/xdrago/log/optimize_mysql_ao.pid
  #rm -f /var/run/octopus_barracuda.pid
fi

###--------------------###
echo "INFO: Checking BARRACUDA version, please wait..."
cd /opt/tmp
wget -q -U iCab http://drupalcode.org/project/barracuda.git/blob_plain/HEAD:/aegir/conf/version.txt
if [ -e "/opt/tmp/version.txt" ] ; then
  _INSTALLER_VERSION=`cat /opt/tmp/version.txt`
  _VERSIONS_TEST=`cat /var/aegir/config/includes/barracuda_log.txt`
  if [[ $_VERSIONS_TEST =~ "$_INSTALLER_VERSION" ]] ; then
    _VERSIONS_TEST_RESULT=OK
    echo "INFO: Version test result: OK"
  else
    cat <<EOF | mail -e -s "New Barracuda $_INSTALLER_VERSION Edition available" notify\@omega8.cc

  There is new $_INSTALLER_VERSION Edition of Barracuda and Octopus available.

  Please review the changelog and upgrade as soon as possible
  to receive all security updates and new features.

  Changelog: http://bit.ly/newboa

  --
  This e-mail has been sent by your Barracuda server upgrade monitor.

EOF
  echo "INFO: Update notice sent: OK"
  fi
fi

