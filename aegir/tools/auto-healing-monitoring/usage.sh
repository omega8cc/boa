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
_MODULES=YES
_PERMISSIONS=YES

###-------------SYSTEM-----------------###

fix_pressflow_core_one()
{
if [ "$_FIX_CORE_ONE" != "NO" ] ; then
  if [ -e "$Plr/modules/o_contrib" ] ; then
    searchStringE="/distro/$_LAST_ALL/"
    case $Plr in
    *"$searchStringE"*)
    if [ ! -e "$Plr/includes/fix_pressflow_core_one.txt" ] ; then
      cp -af /var/opt/pressflow-6-fix/includes/file.inc   $Plr/includes/
      cp -af /var/opt/pressflow-6-fix/includes/common.inc $Plr/includes/
      echo fixed > $Plr/includes/fix_pressflow_core_one.txt
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
if [ ! -d "$Plr/cache/normal" ] ; then
  mkdir -p $Plr/cache/{normal,perm}
  chown -R $_THIS_HM_USER:www-data $Plr/cache
  chmod -R 775 $Plr/cache
fi
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
    else
      if [ ! -e "$Plr/modules/o_contrib" ] ; then
        ln -s $_O_CONTRIB $Plr/modules/o_contrib
      fi
    fi
  fi
fi
}

fix_modules()
{
if [ "$_MODULES" = "YES" ]; then
      searchStringA="-7."
      searchStringB="-5."
      searchStringC="openpublic"
      case $Dir in
        *"$searchStringA"*) ;;
        *"$searchStringB"*) ;;
        *"$searchStringC"*) ;;
        *)  
        cd $Dir
        su -s /bin/bash $_THIS_HM_USER -c "drush dis dblog devel search404 cookie_cache_bypass advagg javascript_aggregator -y &> /dev/null"
        su -s /bin/bash $_THIS_HM_USER -c "drush en syslog cache path_alias_cache css_emimage robotstxt -y &> /dev/null"
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
      find $Dir/files -type d -exec chmod 02775 {} \; &> /dev/null
      find $Dir/files -type f -exec chmod 0664 {} \; &> /dev/null
      chown $_THIS_HM_USER:users $Plr/sites/all/{modules,themes,libraries} &> /dev/null
      chown -R $_THIS_HM_USER.ftp:users $Plr/sites/all/{modules,themes,libraries}/* &> /dev/null
      find $Plr/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
      find $Plr/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
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
      HomSizH=`echo "scale=2; $HomSiz/1024" | bc`;
      SumDatH=`echo "scale=2; $SumDat/1024" | bc`;
      SumDirH=`echo "scale=2; $SumDir/1024" | bc`;
      echo HomSiz is $HomSiz or $HomSizH MB
      echo SumDir is $SumDir or $SumDirH MB
      echo SumDat is $SumDat or $SumDatH MB
      cd $_THIS_HM_SITE
      su -s /bin/bash $_THIS_HM_USER -c "drush vset --always-set site_footer 'Daily Usage Monitor | Disk <strong>$HomSizH</strong> MB | Databases <strong>$SumDatH</strong> MB' &> /dev/null"
      su -s /bin/bash $_THIS_HM_USER -c "drush en syslog cache path_alias_cache css_emimage -y &> /dev/null"
      su -s /bin/bash $_THIS_HM_USER -c "drush cc all &> /dev/null"
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
  touch /var/xdrago/log/optimize_mysql_ao.pid
  touch /var/run/octopus_barracuda.pid
  sleep 60
  action >/var/xdrago/log/usage/usage-$_NOW.log 2>&1
  invoke-rc.d redis-server restart 2>&1
  rm -f /var/xdrago/log/optimize_mysql_ao.pid
  rm -f /var/run/octopus_barracuda.pid
fi
