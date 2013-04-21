#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
_STRONG_PASSWORDS=EDIT_STRONG_PASSWORDS

###----------------------------###
##    Manage ltd shell users    ##
###----------------------------###
#
# Remove dangerous stuff from the string.
sanitize_string () {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\$\@]//g' | sed 's/\(['"'"'\]\)//g'
}
#
# Add ltd-shell group if not exists.
add_ltd_group_if_not_exists () {
  _LTD_EXISTS=$(getent group ltd-shell 2>&1)
  if [[ "$_LTD_EXISTS" =~ "ltd-shell" ]] ; then
    true
  else
    addgroup --system ltd-shell &> /dev/null
  fi
}
#
# Kill zombies.
kill_zombies () {
for Existing in `cat /etc/passwd | cut -d ':' -f1 | sort`
do
  _SEC_IDY=$(id -nG $Existing 2>&1)
  if [[ "$_SEC_IDY" =~ "ltd-shell" ]] ; then
    _PAR_OWN=`echo $Existing | cut -d. -f1 | awk '{ print $1}'`
    _PAR_DIR="/data/disk/$_PAR_OWN/clients"
    _SEC_SYM="/home/$Existing/sites"
    _SEC_DIR=`readlink -n $_SEC_SYM`
    _SEC_DIR=`echo -n $_SEC_DIR | tr -d "\n"`
    if [ ! -L "$_SEC_SYM" ] || [ ! -e "$_SEC_DIR" ] || [ ! -e "/home/$_PAR_OWN.ftp/users/$Existing" ] ; then
      deluser --remove-home --backup-to /var/backups/zombie/deleted $Existing
      rm -f /home/$_PAR_OWN.ftp/users/$Existing
      echo Zombie $Existing killed
      echo
    fi
  fi
done
}
#
# Fix dot dirs.
fix_dot_dirs()
{
  _USRG=users
  _USER_DRUSH="/home/$_USER_LTD/.drush"
  if [ ! -d "$_USER_DRUSH" ] ; then
    mkdir -p $_USER_DRUSH
    chown $_USER_LTD:$_USRG $_USER_DRUSH
    chmod 700 $_USER_DRUSH
  fi
  _USER_SSH="/home/$_USER_LTD/.ssh"
  if [ ! -d "$_USER_SSH" ] ; then
    mkdir -p $_USER_SSH
    chown -R $_USER_LTD:$_USRG $_USER_SSH
    chmod 700 $_USER_SSH
  fi
  chmod 600 $_USER_SSH/id_{r,d}sa &> /dev/null
  chmod 600 $_USER_SSH/known_hosts &> /dev/null
  _USER_BZR="/home/$_USER_LTD/.bazaar"
  if [ ! -d "$_USER_BZR" ] ; then
    mkdir -p $_USER_BZR
    chown $_USER_LTD:$_USRG $_USER_BZR
    chmod 700 $_USER_BZR
  fi
  echo ignore_missing_extensions=True > $_USER_BZR/bazaar.conf
  if [ ! -L "$_USER_DRUSH/drush_make" ] ; then
    ln -s /var/aegir/.drush/drush_make $_USER_DRUSH/drush_make
  fi
  if [ ! -L "$_USER_DRUSH/registry_rebuild" ] ; then
    ln -s /var/aegir/.drush/registry_rebuild $_USER_DRUSH/registry_rebuild
  fi
  if [ ! -L "$_USER_DRUSH/clean_missing_modules" ] ; then
    ln -s /var/aegir/.drush/clean_missing_modules $_USER_DRUSH/clean_missing_modules
  fi
  if [ ! -L "$_USER_DRUSH/drush_ecl" ] ; then
    ln -s /var/aegir/.drush/drush_ecl $_USER_DRUSH/drush_ecl
  fi
}
#
# OK, create user.
ok_create_user()
{
  _ADMIN="$_OWN.ftp"
  _USER_LTD_ROOT="/home/$_USER_LTD"
  _TMP="/var/tmp"
  _WEBG=www-data
  _USRG=users
  if [ ! -d "$_USER_LTD_ROOT" ] ; then
    useradd -d $_USER_LTD_ROOT -s /usr/bin/lshell -m -N -r $_USER_LTD
    adduser $_USER_LTD $_WEBG
    touch $_TMP/$_USER_LTD.txt
    chmod 0600 $_TMP/$_USER_LTD.txt
    _ESC_LUPASS=""
    _LEN_LUPASS=0
    if [ "$_STRONG_PASSWORDS" = "YES" ] ; then
      _ESC_LUPASS=$(randpass 32 alnum)
      _ESC_LUPASS=`echo -n $_ESC_LUPASS | tr -d "\n"`
      _LEN_LUPASS=$(echo ${#_ESC_LUPASS})
    fi
    if [ -z "$_ESC_LUPASS" ] || [ $_LEN_LUPASS -lt 19 ] ; then
      _ESC_LUPASS=`pwgen -v -s -1`
      _ESC_LUPASS=`echo -n $_ESC_LUPASS | tr -d "\n"`
      _ESC_LUPASS=`sanitize_string "$_ESC_LUPASS"`
    fi
    echo "$_ESC_LUPASS" > $_TMP/$_USER_LTD.txt
    ph=$(makepasswd --clearfrom=$_TMP/$_USER_LTD.txt --crypt-md5 --verbose | grep "=" | cut -d= -f3 | awk '{ print $1}')
    usermod -p $ph $_USER_LTD
    passwd -w 7 -x 90 $_USER_LTD
    usermod -aG lshellg $_USER_LTD
    usermod -aG ltd-shell $_USER_LTD
  fi
  if [ ! -e "/home/$_ADMIN/users/$_USER_LTD" ] ; then
    PXSWD=`cat $_TMP/$_USER_LTD.txt`
    PASWD=`echo -n $PXSWD | tr -d "\n"`
    chsh -s /usr/bin/lshell $_USER_LTD
    echo >> $_THIS_LTD_CONF
    echo "[$_USER_LTD]" >> $_THIS_LTD_CONF
    echo "path : [$_ALLD_DIR]" >> $_THIS_LTD_CONF
    ln -s $Client $_USER_LTD_ROOT/sites
    chmod 700 $_USER_LTD_ROOT
    mkdir -p /home/$_ADMIN/users
    echo "$PASWD" > /home/$_ADMIN/users/$_USER_LTD
  fi
  fix_dot_dirs
  rm -f $_USER_LTD_ROOT/{.profile,.bash_logout,.bashrc}
}
#
# OK, update user.
ok_update_user()
{
  _ADMIN="$_OWN.ftp"
  _USER_LTD_ROOT="/home/$_USER_LTD"
  if [ -e "/home/$_ADMIN/users/$_USER_LTD" ] ; then
    echo >> $_THIS_LTD_CONF
    echo "[$_USER_LTD]" >> $_THIS_LTD_CONF
    echo "path : [$_ALLD_DIR]" >> $_THIS_LTD_CONF
    rm $_USER_LTD_ROOT/sites
    ln -s $Client $_USER_LTD_ROOT/sites
    chmod 700 $_USER_LTD_ROOT
  fi
  fix_dot_dirs
  rm -f $_USER_LTD_ROOT/{.profile,.bash_logout,.bashrc}
}
#
# Add user if not exists.
add_user_if_not_exists () {
  _ID_EXISTS=$(getent passwd $_USER_LTD 2>&1)
  _ID_SHELLS=$(id -nG $_USER_LTD 2>&1)
  if [ -z "$_ID_EXISTS" ] ; then
    ok_create_user
  elif [[ "$_ID_EXISTS" =~ "$_USER_LTD" ]] && [[ "$_ID_SHELLS" =~ "ltd-shell" ]] ; then
    ok_update_user
  fi
}
#
# Manage Access Paths.
manage_sec_access_paths()
{
#for Domain in `find $Client/ -maxdepth 1 -mindepth 1 -type l -printf %P\\n | sort`
for Domain in `find $Client/ -maxdepth 1 -mindepth 1 -type l | sort`
do
  _PATH_DOM=`readlink -n $Domain`
  _PATH_DOM=`echo -n $_PATH_DOM | tr -d "\n"`
  _ALLD_DIR="$_ALLD_DIR, '$_PATH_DOM'"
  if [ -e "$_PATH_DOM" ] ; then
    let "_ALLD_NUM += 1"
  fi
  echo Done for $Domain at $Client
done
}
#
# Manage Secondary Users.
manage_sec()
{
for Client in `find $User/clients/ -maxdepth 1 -mindepth 1 -type d | sort`
do
  _USER_LTD=`echo $Client | cut -d'/' -f6 | awk '{ print $1}'`
  _USER_LTD=${_USER_LTD//[^a-zA-Z0-9]/}
  _USER_LTD=`echo -n $_USER_LTD | tr A-Z a-z`
  _USER_LTD="$_OWN.$_USER_LTD"
  _ALLD_NUM="0"
  _ALLD_CTL="1"
  _ALLD_DIR="'$Client'"
  cd $Client
  manage_sec_access_paths
  #_ALLD_DIR="$_ALLD_DIR, '/home/$_USER_LTD'"
  if [ "$_ALLD_NUM" -ge "$_ALLD_CTL" ] ; then
    add_user_if_not_exists
    echo Done for $Client at $User
  else
    echo Empty $Client at $User - deleting now
    if [ -e "$Client" ] ; then
      rmdir $Client
    fi
  fi
done
}
#
# Manage Primary Users.
manage_own()
{
for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`
do
  if [ -e "$User/config/server_master/nginx/vhost.d" ] && [ -e "$User/log/fpm.txt" ] && [ ! -e "$User/log/CANCELLED" ] ; then
    _OWN=`echo $User | cut -d'/' -f4 | awk '{ print $1}'`
    if [ -e "$User/clients" ] ; then
      echo Managing Users for $User Instance
      rm -f -r $User/clients/admin &> /dev/null
      rm -f -r $User/clients/omega8ccgmailcom &> /dev/null
      rm -f -r $User/clients/nocomega8cc &> /dev/null
      rm -f -r $User/clients/*/backups &> /dev/null
      symlinks -dr $User/clients &> /dev/null
      if [ -e "/home/$_OWN.ftp" ] ; then
        symlinks -dr /home/$_OWN.ftp &> /dev/null
        echo >> $_THIS_LTD_CONF
        echo "[$_OWN.ftp]" >> $_THIS_LTD_CONF
        echo "path : ['/data/disk/$_OWN/distro', '/data/disk/$_OWN/static', '/data/disk/$_OWN/backups', '/data/disk/$_OWN/clients']" >> $_THIS_LTD_CONF
        manage_sec
        if [ -e "/home/$_OWN.ftp/users" ] ; then
          chown -R $_OWN.ftp:users /home/$_OWN.ftp/users
          chmod 700 /home/$_OWN.ftp/users
          chmod 600 /home/$_OWN.ftp/users/*
        fi
        echo Done for $User
      else
        echo Directory /home/$_OWN.ftp not available
      fi
      echo
    else
      echo Directory $User/clients not available
    fi
    echo
  fi
done
}


###-------------SYSTEM-----------------###

_NOW=`date +%y%m%d-%H%M`
mkdir -p /var/backups/ltd/{conf,log,old}
mkdir -p /var/backups/zombie/deleted
_THIS_LTD_CONF="/var/backups/ltd/conf/lshell.conf.$_NOW"
if [ -e "/var/run/boa_run.pid" ] || [ -e "/var/run/boa_wait.pid" ] ; then
  touch /var/xdrago/log/wait-manage-ltd-users
  echo Another BOA task is running, we need to wait
  exit
elif [ ! -e "/var/xdrago/conf/lshell.conf" ] ; then
  echo Missing /var/xdrago/conf/lshell.conf template
  exit
else
  sleep 3
  cat /var/xdrago/conf/lshell.conf > $_THIS_LTD_CONF
  add_ltd_group_if_not_exists
  sleep 1
  kill_zombies >/var/backups/ltd/log/zombies-$_NOW.log 2>&1
  sleep 1
  manage_own >/var/backups/ltd/log/users-$_NOW.log 2>&1
  sleep 1
  cp -af /etc/lshell.conf /var/backups/ltd/old/lshell.conf-before-$_NOW
  _THISHTIP=`hostname -i`
  sed -i "s/8.8.8.8/$_THISHTIP/g" $_THIS_LTD_CONF
  sleep 1
  cp -af $_THIS_LTD_CONF /etc/lshell.conf
  sleep 1
  find /var/backups/ltd/*/* -mtime +1 -type f -exec rm -rf {} \;
  rm -f $_TMP/*.txt
  chmod 700 /home/* &> /dev/null
fi
###EOF2013###
