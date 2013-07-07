#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

###-------------SYSTEM-----------------###
fix_clear_cache () {
  if [ -e "$Plr/profiles/hostmaster" ] ; then
    su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster cc all &> /dev/null"
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
  if [ -e "/data/disk/$_THIS_HM_USER/log/option.txt" ] ; then
    _CLIENT_OPTION=`cat /data/disk/$_THIS_HM_USER/log/option.txt`
    _CLIENT_OPTION=`echo -n $_CLIENT_OPTION | tr -d "\n"`
  fi
}

send_notice_core () {
  _ADM_EMAIL="support@omega8.cc"
  _BCC_EMAIL="notify@omega8.cc"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=`mail -V 2>&1`
  if [[ "$_MAILX_TEST" =~ "invalid" ]] ; then
  cat <<EOF | mail -a "From: $_ADM_EMAIL" -e -b $_BCC_EMAIL -s "URGENT: Please migrate $Dom site to Pressflow" $_CLIENT_EMAIL
Hello,

Our system detected that you are using vanilla Drupal core
for site $Dom.

The platform root directory for this site is:
$Plr

Using non-Pressflow 5.x or 6.x core is not allowed
on our servers, unless it is a temporary result of your site
import, but every imported site should be migrated to Pressflow
based platform as soon as possible.

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

Using non-Pressflow 5.x or 6.x core is not allowed
on our servers, unless it is a temporary result of your site
import, but every imported site should be migrated to Pressflow
based platform as soon as possible.

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

detect_vanilla_core () {
  if [ ! -e "$Plr/core" ] ; then
    if [ -e "$Plr/web.config" ] ; then
      true
    else
      if [ -e "$Plr/modules/watchdog" ] ; then
        if [[ "$_VM_TEST" =~ ".host8." ]] && [ ! -e "/boot/grub/menu.lst" ] && [[ "$Plr" =~ "static" ]] && [ ! -e "$Plr/modules/cookie_cache_bypass" ] ; then
          echo Vanilla Drupal 5.x Platform detected in $Plr
          read_account_data
          send_notice_core
        fi
      else
        if [ ! -e "$Plr/modules/path_alias_cache" ] && [ -e "$Plr/modules/user" ] && [[ "$Plr" =~ "static" ]] ; then
          echo Vanilla Drupal 6.x Platform detected in $Plr
          if [[ "$_VM_TEST" =~ ".host8." ]] && [ ! -e "/boot/grub/menu.lst" ] ; then
            read_account_data
            send_notice_core
          fi
        fi
      fi
    fi
  fi
}

count () {
  for Site in `find $User/config/server_master/nginx/vhost.d -maxdepth 1 -mindepth 1 -type f | sort`
  do
    #echo Counting Site $Site
    Dom=`echo $Site | cut -d'/' -f9 | awk '{ print $1}'`
    if [ -e "$User/.drush/$Dom.alias.drushrc.php" ] ; then
      echo Dom is $Dom
      Dir=`cat $User/.drush/$Dom.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      Plr=`cat $User/.drush/$Dom.alias.drushrc.php | grep "root'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
      detect_vanilla_core
      fix_clear_cache
      #echo Dir is $Dir
      if [ -e "$Dir/drushrc.php" ] ; then
      Dat=`cat $Dir/drushrc.php | grep "options\['db_name'\] = " | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,';]//g"`
      #echo Dat is $Dat
      if [ -e "$Dir" ] ; then
        DirSize=`du -s $Dir`
        DirSize=`echo "$DirSize" | cut -d'/' -f1 | awk '{ print $1}' | sed "s/[\/\s+]//g"`
        SumDir=$(($SumDir + $DirSize))
        echo DirSize of $Dom is $DirSize
      fi
      if [ -e "/var/lib/mysql/$Dat" ] ; then
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
  if [[ "$_MAILX_TEST" =~ "invalid" ]] ; then
  cat <<EOF | mail -a "From: $_ADM_EMAIL" -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [sql-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES $_CLIENT_OPTION Core(s) on a SSD+SAS System.

Your allowed databases space is $_CLIENT_SQL_LIMIT MB.
You are currently using $SumDatH MB of databases space.

Please reduce your usage by deleting no longer used sites,
or by converting their tables to MyISAM format on command line
when in the site directory with:

  $ sqlmagic convert to-myisam

or purchase enough Aegir Cores to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

Please don't ignore this message! If you are using more resources
than allocated in your subscription for more than 30 calendar days
without purchasing an upgrade, YOUR INSTANCE WILL BE SUSPENDED
WITHOUT FURTHER NOTICE, and to restore it you will have to pay for
all past due overages plus \$100 USD reconnection fee.

We provide generous soft-limits and we allow free-of-charge overages
between weekly checks which happen every Monday, but in return
we expect that you will not abuse this feature.

Thank you in advance.

--
This e-mail has been sent by your Aegir resources usage weekly monitor.

EOF
  else
  cat <<EOF | mail -r $_ADM_EMAIL -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [sql-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES $_CLIENT_OPTION Core(s) on a SSD+SAS System.

Your allowed databases space is $_CLIENT_SQL_LIMIT MB.
You are currently using $SumDatH MB of databases space.

Please reduce your usage by deleting no longer used sites,
or by converting their tables to MyISAM format on command line
when in the site directory with:

  $ sqlmagic convert to-myisam

or purchase enough Aegir Cores to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

Please don't ignore this message! If you are using more resources
than allocated in your subscription for more than 30 calendar days
without purchasing an upgrade, YOUR INSTANCE WILL BE SUSPENDED
WITHOUT FURTHER NOTICE, and to restore it you will have to pay for
all past due overages plus \$100 USD reconnection fee.

We provide generous soft-limits and we allow free-of-charge overages
between weekly checks which happen every Monday, but in return
we expect that you will not abuse this feature.

Thank you in advance.

--
This e-mail has been sent by your Aegir resources usage weekly monitor.

EOF
  fi
  echo "INFO: Update notice sent to $_CLIENT_EMAIL [$_THIS_HM_USER]: OK"
}

send_notice_disk () {
  _ADM_EMAIL="billing@omega8.cc"
  _BCC_EMAIL="notify@omega8.cc"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=`mail -V 2>&1`
  if [[ "$_MAILX_TEST" =~ "invalid" ]] ; then
  cat <<EOF | mail -a "From: $_ADM_EMAIL" -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [disk-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES $_CLIENT_OPTION Core(s) on a SSD+SAS System.

Your allowed disk space is $_CLIENT_DSK_LIMIT MB.
You are currently using $HomSizH MB of disk space.

Please reduce your usage by deleting old backups, files,
and no longer used sites, or purchase enough Aegir Cores
to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

Please don't ignore this message! If you are using more resources
than allocated in your subscription for more than 30 calendar days
without purchasing an upgrade, YOUR INSTANCE WILL BE SUSPENDED
WITHOUT FURTHER NOTICE, and to restore it you will have to pay for
all past due overages plus \$100 USD reconnection fee.

We provide generous soft-limits and we allow free-of-charge overages
between weekly checks which happen every Monday, but in return
we expect that you will not abuse this feature.

Thank you in advance.

--
This e-mail has been sent by your Aegir resources usage weekly monitor.

EOF
  else
  cat <<EOF | mail -r $_ADM_EMAIL -e -b $_BCC_EMAIL -s "Your Aegir instance needs an upgrade [disk-$_THIS_HM_USER]" $_CLIENT_EMAIL
Hello,

You are using more resources than allocated with your subscription.
You have currently $_CLIENT_CORES $_CLIENT_OPTION Core(s) on a SSD+SAS System.

Your allowed disk space is $_CLIENT_DSK_LIMIT MB.
You are currently using $HomSizH MB of disk space.

Please reduce your usage by deleting old backups, files,
and no longer used sites, or purchase enough Aegir Cores
to cover your current usage.

You can purchase more Aegir Cores easily online:

  http://omega8.cc/upgrade

Please don't ignore this message! If you are using more resources
than allocated in your subscription for more than 30 calendar days
without purchasing an upgrade, YOUR INSTANCE WILL BE SUSPENDED
WITHOUT FURTHER NOTICE, and to restore it you will have to pay for
all past due overages plus \$100 USD reconnection fee.

We provide generous soft-limits and we allow free-of-charge overages
between weekly checks which happen every Monday, but in return
we expect that you will not abuse this feature.

Thank you in advance.

--
This e-mail has been sent by your Aegir resources usage weekly monitor.

EOF
  fi
  echo "INFO: Update notice sent to $_CLIENT_EMAIL [$_THIS_HM_USER]: OK"
}

check_limits () {
  read_account_data
  if [ "$_CLIENT_OPTION" = "SSD" ] ; then
    _CLIENT_SQL_LIMIT=512
    _CLIENT_DSK_LIMIT=10240
    _SQL_LIMIT=$(($_CLIENT_SQL_LIMIT + 128))
    _DSK_LIMIT=$(($_CLIENT_DSK_LIMIT + 2560))
  else
    _CLIENT_SQL_LIMIT=256
    _CLIENT_DSK_LIMIT=5120
    _SQL_LIMIT=$(($_CLIENT_SQL_LIMIT + 64))
    _DSK_LIMIT=$(($_CLIENT_DSK_LIMIT + 1280))
  fi
  let "_CLIENT_SQL_LIMIT *= $_CLIENT_CORES"
  let "_CLIENT_DSK_LIMIT *= $_CLIENT_CORES"
  let "_SQL_LIMIT *= $_CLIENT_CORES"
  let "_DSK_LIMIT *= $_CLIENT_CORES"
  echo _CLIENT_CORES is $_CLIENT_CORES
  echo _CLIENT_SQL_LIMIT is $_CLIENT_SQL_LIMIT
  echo _SQL_LIMIT is $_SQL_LIMIT
  echo _CLIENT_DSK_LIMIT is $_CLIENT_DSK_LIMIT
  echo _DSK_LIMIT is $_DSK_LIMIT
  if [ "$SumDatH" -gt "$_SQL_LIMIT" ] ; then
    if [ ! -e "$User/log/CANCELLED" ] ; then
      send_notice_sql
    fi
    echo SQL Usage for $_THIS_HM_USER above limits
  else
    echo SQL Usage for $_THIS_HM_USER below limits
  fi
  if [ "$HomSizH" -gt "$_DSK_LIMIT" ] ; then
    if [ ! -e "$User/log/CANCELLED" ] ; then
      send_notice_disk
    fi
    echo Disk Usage for $_THIS_HM_USER above limits
  else
    echo Disk Usage for $_THIS_HM_USER below limits
  fi
}

action () {
  for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`
  do
    NOW_LOAD=`awk '{print $1*100}' /proc/loadavg`
    CTL_LOAD=888
    if [ -e "$User/config/server_master/nginx/vhost.d" ] ; then
      if [ $NOW_LOAD -lt $CTL_LOAD ] ; then
        SumDir=0
        SumDat=0
        HomSiz=0
        HxmSiz=0
        _THIS_HM_USER=`echo $User | cut -d'/' -f4 | awk '{ print $1}'`
        _THIS_HM_SITE=`cat $User/.drush/hostmaster.alias.drushrc.php | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
        echo load is $NOW_LOAD while maxload is $CTL_LOAD
        echo Counting User $User
        count
        if [ -e "/home/$_THIS_HM_USER.ftp" ] ; then
          HxmSiz=`du -s /home/$_THIS_HM_USER.ftp` &> /dev/null
          HxmSiz=`echo "$HxmSiz" | cut -d'/' -f1 | awk '{ print $1}' | sed "s/[\/\s+]//g"`
        fi
        if [ -L "$User" ] ; then
          HomSiz=`du -D -s $User` &> /dev/null
        else
          HomSiz=`du -s $User` &> /dev/null
        fi
        HomSiz=`echo "$HomSiz" | cut -d'/' -f1 | awk '{ print $1}' | sed "s/[\/\s+]//g"`
        HomSiz=$(($HomSiz + $HxmSiz))
        HomSizH=`echo "scale=0; $HomSiz/1024" | bc`;
        SumDatH=`echo "scale=0; $SumDat/1024" | bc`;
        SumDirH=`echo "scale=0; $SumDir/1024" | bc`;
        echo HomSiz is $HomSiz or $HomSizH MB
        echo SumDir is $SumDir or $SumDirH MB
        echo SumDat is $SumDat or $SumDatH MB
        if [[ "$_VM_TEST" =~ ".host8." ]] && [ ! -e "/boot/grub/menu.lst" ] ; then
          check_limits
          if [ -e "$_THIS_HM_SITE" ] ; then
            su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster vset --always-set site_footer 'Weekly Usage Monitor | Disk <strong>$HomSizH</strong> MB | Databases <strong>$SumDatH</strong> MB | <strong>$_CLIENT_CORES</strong> $_CLIENT_OPTION | SSD+SAS System' &> /dev/null"
            su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster cc all &> /dev/null"
          fi
        else
          if [ -e "$_THIS_HM_SITE" ] ; then
            su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster vset --always-set site_footer '' &> /dev/null"
            su -s /bin/bash - $_THIS_HM_USER -c "drush @hostmaster cc all &> /dev/null"
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

###--------------------###
echo "INFO: Weekly maintenance start"
_NOW=`date +%y%m%d-%H%M`
_VM_TEST=`uname -a 2>&1`
mkdir -p /var/xdrago/log/usage
action >/var/xdrago/log/usage/usage-$_NOW.log 2>&1
echo "INFO: Weekly maintenance complete"
exit 0
###EOF2013###
