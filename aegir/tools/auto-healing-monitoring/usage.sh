#!/bin/bash
  
###-------------SYSTEM-----------------###

count()
{
for Site in `find $User/config/server_master/nginx/vhost.d -maxdepth 1 -type f | sort`
do
    #echo Counting Site $Site
    Dom=`echo $Site | cut -d'/' -f9 | awk '{ print $1}'`
    echo Dom is $Dom
    if [ -e "$User/.drush/$Dom.alias.drushrc.php" ] ; then
      Dir=`cat $User/.drush/$Dom.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      chown $_THIS_HM_USER:users $Dir/{modules,themes,libraries} &> /dev/null
      chown -R $_THIS_HM_USER.ftp:users $Dir/{modules,themes,libraries}/* &> /dev/null
      find $Dir/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
      find $Dir/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
      chown -R $_THIS_HM_USER:www-data $Dir/files &> /dev/null
      find $Dir/files -type d -exec chmod 02770 {} \; &> /dev/null
      find $Dir/files -type f -exec chmod 0660 {} \; &> /dev/null
      Plr=`cat $User/.drush/$Dom.alias.drushrc.php | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      chown $_THIS_HM_USER:users $Plr/sites/all/{modules,themes,libraries} &> /dev/null
      chown -R $_THIS_HM_USER.ftp:users $Plr/sites/all/{modules,themes,libraries}/* &> /dev/null
      find $Plr/sites/all/{modules,themes,libraries} -type d -exec chmod 02775 {} \; &> /dev/null
      find $Plr/sites/all/{modules,themes,libraries} -type f -exec chmod 0664 {} \; &> /dev/null
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
mkdir -p /var/xdrago/log/usage
if test -f /var/xdrago/log/optimize_mysql_ao.pid ; then
  touch /var/xdrago/log/wait-counter
  exit
else
  action >/var/xdrago/log/usage/usage-$_NOW.log 2>&1
fi
