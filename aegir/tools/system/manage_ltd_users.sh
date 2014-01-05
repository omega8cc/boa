#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/opt/php55/bin:/opt/php54/bin:/opt/php53/bin:/opt/php52/bin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
_STRONG_PASSWORDS=EDIT_STRONG_PASSWORDS
_HOST_TEST=`uname -n 2>&1`
_VM_TEST=`uname -a 2>&1`

###----------------------------###
##    Manage ltd shell users    ##
###----------------------------###
#
# Remove dangerous stuff from the string.
sanitize_string () {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\$\@\&\|\*]//g; s/\(['"'"'\]\)//g'
}
#
# Add ltd-shell group if not exists.
add_ltd_group_if_not_exists () {
  _LTD_EXISTS=$(getent group ltd-shell 2>&1)
  if [[ "$_LTD_EXISTS" =~ "ltd-shell" ]] ; then
    _DO_NOTHING=YES
  else
    addgroup --system ltd-shell &> /dev/null
  fi
}
#
# Enable chattr.
enable_chattr () {
  if [ ! -z "$1" ] && [ -d "/home/$1" ] ; then
    if [ "$1" != "${_OWN}.ftp" ] ; then
      chattr +i /home/$1             &> /dev/null
    else
      chattr +i /home/$1/platforms   &> /dev/null
      chattr +i /home/$1/platforms/* &> /dev/null
    fi
    chattr +i /home/$1/.bazaar       &> /dev/null
    chattr +i /home/$1/.drush        &> /dev/null
  fi
}
#
# Disable chattr.
disable_chattr () {
  if [ ! -z "$1" ] && [ -d "/home/$1" ] ; then
    if [ "$1" != "${_OWN}.ftp" ] ; then
      chattr -i /home/$1             &> /dev/null
    else
      chattr -i /home/$1/platforms   &> /dev/null
      chattr -i /home/$1/platforms/* &> /dev/null
    fi
    chattr -i /home/$1/.bazaar       &> /dev/null
    chattr -i /home/$1/.drush        &> /dev/null
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
    if [ ! -L "$_SEC_SYM" ] || [ ! -e "$_SEC_DIR" ] || [ ! -e "/home/${_PAR_OWN}.ftp/users/$Existing" ] ; then
      disable_chattr $Existing
      deluser --remove-home --backup-to /var/backups/zombie/deleted $Existing
      rm -f /home/${_PAR_OWN}.ftp/users/$Existing
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
  if [ -x "/usr/local/bin/bzr" ] ; then
    if [ ! -d "$_USER_BZR" ] ; then
      mkdir -p $_USER_BZR
      chown $_USER_LTD:$_USRG $_USER_BZR
      chmod 700 $_USER_BZR
    fi
  else
    rm -f -r $_USER_BZR
  fi
  echo ignore_missing_extensions=True > $_USER_BZR/bazaar.conf
  if [ ! -L "$_USER_DRUSH/drush_make" ] ; then
    ln -sf /var/aegir/.drush/drush_make $_USER_DRUSH/drush_make
  fi
  if [ ! -L "$_USER_DRUSH/registry_rebuild" ] ; then
    ln -sf /var/aegir/.drush/registry_rebuild $_USER_DRUSH/registry_rebuild
  fi
  if [ ! -L "$_USER_DRUSH/clean_missing_modules" ] ; then
    ln -sf /var/aegir/.drush/clean_missing_modules $_USER_DRUSH/clean_missing_modules
  fi
  if [ ! -L "$_USER_DRUSH/drush_ecl" ] ; then
    ln -sf /var/aegir/.drush/drush_ecl $_USER_DRUSH/drush_ecl
  fi
}
#
# OK, create user.
ok_create_user()
{
  _ADMIN="${_OWN}.ftp"
  echo "_ADMIN is == $_ADMIN == at ok_create_user"
  _USER_LTD_ROOT="/home/$_USER_LTD"
  _SEC_SYM="$_USER_LTD_ROOT/sites"
  _TMP="/var/tmp"
  _WEBG=www-data
  _USRG=users
  if [ ! -L "$_SEC_SYM" ] ; then
    mkdir -p /var/backups/zombie/deleted/$_NOW
    mv -f $_USER_LTD_ROOT /var/backups/zombie/deleted/$_NOW/ &> /dev/null
  fi
  if [ ! -d "$_USER_LTD_ROOT" ] ; then
    if [ -e "/usr/bin/MySecureShell" ] && [ -e "/etc/ssh/sftp_config" ] ; then
      useradd -d $_USER_LTD_ROOT -s /usr/bin/MySecureShell -m -N -r $_USER_LTD
      echo "_USER_LTD_ROOT is == $_USER_LTD_ROOT == at ok_create_user"
    else
      useradd -d $_USER_LTD_ROOT -s /usr/bin/lshell -m -N -r $_USER_LTD
    fi
    adduser $_USER_LTD $_WEBG
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
    ph=$(mkpasswd -m sha-512 $_ESC_LUPASS $(openssl rand -base64 16 | tr -d '+=' | head -c 16))
    usermod -p $ph $_USER_LTD
    passwd -w 7 -x 90 $_USER_LTD
    usermod -aG lshellg $_USER_LTD
    usermod -aG ltd-shell $_USER_LTD
  fi
  if [ ! -e "/home/$_ADMIN/users/$_USER_LTD" ] && [ ! -z "$_ESC_LUPASS" ] ; then
    if [ -e "/usr/bin/MySecureShell" ] && [ -e "/etc/ssh/sftp_config" ] ; then
      chsh -s /usr/bin/MySecureShell $_USER_LTD
    else
      chsh -s /usr/bin/lshell $_USER_LTD
    fi
    echo >> $_THIS_LTD_CONF
    echo "[$_USER_LTD]" >> $_THIS_LTD_CONF
    echo "path : [$_ALLD_DIR]" >> $_THIS_LTD_CONF
    ln -sf $Client $_USER_LTD_ROOT/sites
    chmod 700 $_USER_LTD_ROOT
    mkdir -p /home/$_ADMIN/users
    echo "$_ESC_LUPASS" > /home/$_ADMIN/users/$_USER_LTD
  fi
  fix_dot_dirs
  rm -f $_USER_LTD_ROOT/{.profile,.bash_logout,.bashrc}
}
#
# OK, update user.
ok_update_user()
{
  _ADMIN="${_OWN}.ftp"
  _USER_LTD_ROOT="/home/$_USER_LTD"
  if [ -e "/home/$_ADMIN/users/$_USER_LTD" ] ; then
    echo >> $_THIS_LTD_CONF
    echo "[$_USER_LTD]" >> $_THIS_LTD_CONF
    echo "path : [$_ALLD_DIR]" >> $_THIS_LTD_CONF
    rm $_USER_LTD_ROOT/sites
    ln -sf $Client $_USER_LTD_ROOT/sites
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
  echo "_ID_EXISTS is == $_ID_EXISTS == at add_user_if_not_exists"
  echo "_ID_SHELLS is == $_ID_SHELLS == at add_user_if_not_exists"
  if [ -z "$_ID_EXISTS" ] ; then
    echo "We will create user == $_USER_LTD =="
    ok_create_user
    enable_chattr $_USER_LTD
  elif [[ "$_ID_EXISTS" =~ "$_USER_LTD" ]] && [[ "$_ID_SHELLS" =~ "ltd-shell" ]] ; then
    echo "We will update user == $_USER_LTD =="
    disable_chattr $_USER_LTD
    ok_update_user
    enable_chattr $_USER_LTD
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
  _USER_LTD="${_OWN}.${_USER_LTD}"
  echo "_USER_LTD is == $_USER_LTD == at manage_sec"
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
# Update PHP-CLI for Drush.
update_php_cli_drush ()
{
  _DRUSH_FILE="/data/disk/${_OWN}/tools/drush/drush.php"
  if [ "$_LOC_PHP_CLI_VERSION" = "5.5" ] && [ -x "/opt/php55/bin/php" ] ; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php55\/bin\/php/g"  $_DRUSH_FILE &> /dev/null
    _L_PHP_CLI=/opt/php55/bin
  elif [ "$_LOC_PHP_CLI_VERSION" = "5.4" ] && [ -x "/opt/php54/bin/php" ] ; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php54\/bin\/php/g"  $_DRUSH_FILE &> /dev/null
    _L_PHP_CLI=/opt/php54/bin
  elif [ "$_LOC_PHP_CLI_VERSION" = "5.3" ] && [ -x "/opt/php53/bin/php" ] ; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php53\/bin\/php/g"  $_DRUSH_FILE &> /dev/null
    _L_PHP_CLI=/opt/php53/bin
  fi
  _DRUSHCMD="$_L_PHP_CLI/php /data/disk/${_OWN}/tools/drush/drush.php"
  if [ -e "/data/disk/${_OWN}/aegir.sh" ] ; then
    rm -f /data/disk/${_OWN}/aegir.sh
  fi
  touch /data/disk/${_OWN}/aegir.sh
  echo -e "#!/bin/bash\n\nPATH=.:$_L_PHP_CLI:/usr/sbin:/usr/bin:/sbin:/bin\n$_DRUSHCMD '@hostmaster' hosting-dispatch\ntouch /data/disk/${_OWN}/${_OWN}-task.done" | tee -a /data/disk/${_OWN}/aegir.sh >/dev/null 2>&1
  chown ${_OWN}:users /data/disk/${_OWN}/aegir.sh &> /dev/null
  chmod 0700 /data/disk/${_OWN}/aegir.sh &> /dev/null
}
#
# Switch PHP Version.
switch_php()
{
  if [ -e "/data/disk/${_OWN}/static/control/fpm.info" ] || [ -e "/data/disk/${_OWN}/static/control/cli.info" ] ; then
    echo "Custom FPM or CLI settings for $_OWN exist, running switch_php checks"
    if [ -e "/root/.${_OWN}.octopus.cnf" ] ; then
      source /root/.${_OWN}.octopus.cnf
    fi
    if [ -e "/data/disk/${_OWN}/static/control/fpm.info" ] && [ -e "/var/xdrago/conf/fpm-pool-foo.conf" ] ; then
      _THIS_NGX_PATH=/data/disk/${_OWN}/config/includes
      _LOC_PHP_FPM_VERSION=`cat /data/disk/${_OWN}/static/control/fpm.info`
      _LOC_PHP_FPM_VERSION=`echo -n $_LOC_PHP_FPM_VERSION | tr -d "\n"`
      if [ "$_LOC_PHP_FPM_VERSION" = "5.5" ] || [ "$_LOC_PHP_FPM_VERSION" = "5.4" ] || [ "$_LOC_PHP_FPM_VERSION" = "5.3" ] || [ "$_LOC_PHP_FPM_VERSION" = "5.2" ]; then
        if [ "$_LOC_PHP_FPM_VERSION" = "5.2" ]; then
          _LOC_PHP_FPM_VERSION=5.3
        fi
        if [ "$_LOC_PHP_FPM_VERSION" != "$_PHP_FPM_VERSION" ] ; then
          sed -i "s/.*_PHP_FPM_VERSION.*/_PHP_FPM_VERSION=$_LOC_PHP_FPM_VERSION/g" /root/.${_OWN}.octopus.cnf &> /dev/null
          _PHP_OLD_SV=${_PHP_FPM_VERSION//[^0-9]/}
          _PHP_SV=${_LOC_PHP_FPM_VERSION//[^0-9]/}
          if [ -z "$_PHP_SV" ] ; then
            _PHP_SV=53
          fi
          _PHP_CN="www${_PHP_SV}"
          if [ -e "/opt/php${_PHP_SV}/etc/php${_PHP_SV}-fpm.conf" ] ; then
            sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_OWN}.fpm.socket;/g" $_THIS_NGX_PATH/nginx_modern_include.conf  &> /dev/null
            sed -i "s/127.0.0.1:.*;/unix:\/var\/run\/${_OWN}.fpm.socket;/g" $_THIS_NGX_PATH/nginx_octopus_include.conf  &> /dev/null
            if [ "$_PHP_CN" = "www53" ] ; then
              sed -i "s/unix:cron:fastcgi.socket;/127.0.0.1:9090;/g" $_THIS_NGX_PATH/nginx_modern_include.conf  &> /dev/null
              sed -i "s/unix:cron:fastcgi.socket;/127.0.0.1:9090;/g" $_THIS_NGX_PATH/nginx_octopus_include.conf  &> /dev/null
            else
              sed -i "s/unix:cron:fastcgi.socket;/unix:\/var\/run\/$_PHP_CN.fpm.socket;/g" $_THIS_NGX_PATH/nginx_modern_include.conf  &> /dev/null
              sed -i "s/unix:cron:fastcgi.socket;/unix:\/var\/run\/$_PHP_CN.fpm.socket;/g" $_THIS_NGX_PATH/nginx_octopus_include.conf  &> /dev/null
            fi
          fi
          rm -f /opt/php*/etc/pool.d/${_OWN}.conf
          cp -af /var/xdrago/conf/fpm-pool-foo.conf /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf
          sed -i "s/foo/${_OWN}/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          if [ ! -z "$_PHP_FPM_DENY" ] ; then
            sed -i "s/passthru,/$_PHP_FPM_DENY,/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          else
            if [[ "$_HOST_TEST" =~ ".host8." ]] && [ ! -e "/boot/grub/grub.cfg" ] && [ ! -e "/boot/grub/menu.lst" ] ; then
              _DO_NOTHING=YES
            else
              sed -i "s/passthru,//g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
            fi
          fi
          if [ "$_PHP_FPM_TIMEOUT" = "AUTO" ] || [ -z "$_PHP_FPM_TIMEOUT" ] ; then
            _PHP_FPM_TIMEOUT=180
          fi
          _PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT//[^0-9]/}
          if [ ! -z "$_PHP_FPM_TIMEOUT" ] ; then
            _PHP_TO="${_PHP_FPM_TIMEOUT}s"
            sed -i "s/180s/$_PHP_TO/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          fi
          if [ -e "/etc/init.d/php${_PHP_OLD_SV}-fpm" ] ; then
            service php${_PHP_OLD_SV}-fpm reload &> /dev/null
          fi
          if [ -e "/etc/init.d/php${_PHP_SV}-fpm" ] ; then
            service php${_PHP_SV}-fpm reload &> /dev/null
          fi
        fi
      fi
    fi
    if [ -e "/data/disk/${_OWN}/static/control/cli.info" ] ; then
      _LOC_PHP_CLI_VERSION=`cat /data/disk/${_OWN}/static/control/cli.info`
      _LOC_PHP_CLI_VERSION=`echo -n $_LOC_PHP_CLI_VERSION | tr -d "\n"`
      if [ "$_LOC_PHP_CLI_VERSION" = "5.5" ] || [ "$_LOC_PHP_CLI_VERSION" = "5.4" ] || [ "$_LOC_PHP_CLI_VERSION" = "5.3" ] || [ "$_LOC_PHP_CLI_VERSION" = "5.2" ]; then
        if [ "$_LOC_PHP_CLI_VERSION" = "5.2" ]; then
          _LOC_PHP_CLI_VERSION=5.3
        fi
        if [ "$_LOC_PHP_CLI_VERSION" != "$_PHP_CLI_VERSION" ] ; then
          sed -i "s/.*_PHP_CLI_VERSION.*/_PHP_CLI_VERSION=$_LOC_PHP_CLI_VERSION/g" /root/.${_OWN}.octopus.cnf &> /dev/null
          update_php_cli_drush
        fi
      fi
    fi
  fi
}
#
# Manage Primary Users.
manage_own()
{
for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`
do
  if [ -e "$User/config/server_master/nginx/vhost.d" ] && [ -e "$User/log/fpm.txt" ] && [ ! -e "$User/log/CANCELLED" ] ; then
    _OWN=""
    _OWN=`echo $User | cut -d'/' -f4 | awk '{ print $1}'`
    echo "_OWN is == $_OWN == at manage_own"
    if [ ! -d "/data/disk/${_OWN}/tmp" ] ; then
      rm -f -r /data/disk/${_OWN}/tmp
      mkdir -p /data/disk/${_OWN}/tmp
      chown ${_OWN}.ftp:www-data /data/disk/${_OWN}/tmp &> /dev/null
      chmod 2770 /data/disk/${_OWN}/tmp &> /dev/null
    fi
    switch_php
    if [ -e "$User/clients" ] && [ ! -z $_OWN ] ; then
      echo Managing Users for $User Instance
      rm -f -r $User/clients/admin &> /dev/null
      rm -f -r $User/clients/omega8ccgmailcom &> /dev/null
      rm -f -r $User/clients/nocomega8cc &> /dev/null
      rm -f -r $User/clients/*/backups &> /dev/null
      symlinks -dr $User/clients &> /dev/null
      if [ -e "/home/${_OWN}.ftp" ] ; then
        disable_chattr ${_OWN}.ftp
        symlinks -dr /home/${_OWN}.ftp &> /dev/null
        echo >> $_THIS_LTD_CONF
        echo "[${_OWN}.ftp]" >> $_THIS_LTD_CONF
        echo "path : ['/data/disk/$_OWN/distro', '/data/disk/$_OWN/static', '/data/disk/$_OWN/backups', '/data/disk/$_OWN/clients']" >> $_THIS_LTD_CONF
        manage_sec
        if [ -e "/home/${_OWN}.ftp/users" ] ; then
          chown -R ${_OWN}.ftp:users /home/${_OWN}.ftp/users
          chmod 700 /home/${_OWN}.ftp/users
          chmod 600 /home/${_OWN}.ftp/users/*
        fi
        enable_chattr ${_OWN}.ftp
        echo Done for $User
      else
        echo Directory /home/${_OWN}.ftp not available
      fi
      echo
    else
      echo Directory $User/clients not available
    fi
    echo
  fi
done
}
#
# Update IP-Auth Xtras Access.
update_ip_auth_xtras_access ()
{
  if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
    sed -i "s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" /var/aegir/config/server_master/nginx/vhost.d/* &> /dev/null
    sed -i '/  ### access .*/ {r /var/backups/.auth.IP.list.tmp
d;};' /var/aegir/config/server_master/nginx/vhost.d/* &> /dev/null
    _NGX_TEST=$(service nginx configtest 2>&1)
    if [[ "$_NGX_TEST" =~ "successful" ]] ; then
      service nginx reload &> /dev/null
    else
      service nginx reload &>     /var/backups/.auth.IP.list.ops
      sed -i "s/allow .*;//g; s/ *$//g; /^$/d" /var/aegir/config/server_master/nginx/vhost.d/* &> /dev/null
      service nginx reload &> /dev/null
    fi
  fi
  for _IP in `who --ips | awk '{print $5}' | sort | uniq | tr -d "\s"`;do _IP=$(echo $_IP | cut -d: -f1); _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" > /var/backups/.auth.IP.list;done
  sed -i "s/\.;/;/g; s/allow                        ;//g; s/ *$//g; /^$/d" /var/backups/.auth.IP.list &> /dev/null
  _ALLOW_TEST=$(grep allow /var/backups/.auth.IP.list)
  if [[ "$_ALLOW_TEST" =~ "allow" ]] ; then
    echo "  deny                         all;" >> /var/backups/.auth.IP.list
    echo "  ### access live"                   >> /var/backups/.auth.IP.list
  else
    echo "  deny                         all;" >  /var/backups/.auth.IP.list
    echo "  ### access none"                   >> /var/backups/.auth.IP.list
  fi
}
#
# Manage IP-Auth Xtras Access.
manage_ip_auth_xtras_access ()
{
  for _IP in `who --ips | awk '{print $5}' | sort | uniq | tr -d "\s"`;do _IP=$(echo $_IP | cut -d: -f1); _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" > /var/backups/.auth.IP.list.tmp;done
  sed -i "s/\.;/;/g; s/allow                        ;//g; s/ *$//g; /^$/d" /var/backups/.auth.IP.list.tmp &> /dev/null
  _ALLOW_TEST=$(grep allow /var/backups/.auth.IP.list.tmp)
  if [[ "$_ALLOW_TEST" =~ "allow" ]] ; then
    echo "  deny                         all;" >> /var/backups/.auth.IP.list.tmp
    echo "  ### access live"                   >> /var/backups/.auth.IP.list.tmp
  else
    echo "  deny                         all;" >  /var/backups/.auth.IP.list.tmp
    echo "  ### access none"                   >> /var/backups/.auth.IP.list.tmp
  fi
  if [ ! -e "/var/backups/.auth.IP.list" ] ; then
    update_ip_auth_xtras_access
  else
    if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
      _DIFF_TEST=$(diff /var/backups/.auth.IP.list.tmp /var/backups/.auth.IP.list)
      if [ ! -z "$_DIFF_TEST" ] ; then
        update_ip_auth_xtras_access
      fi
    fi
  fi
  rm -f /var/backups/.auth.IP.list.tmp
  echo `date` > /var/backups/.auth.IP.list.stamp
}
#

###-------------SYSTEM-----------------###

_NOW=`date +%y%m%d-%H%M`
manage_ip_auth_xtras_access
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
  find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -rf {} \; &> /dev/null
  cat /var/xdrago/conf/lshell.conf > $_THIS_LTD_CONF
  _THISHTNM=`hostname --fqdn`
  _THISHTIP=`echo $(getent ahostsv4 $_THISHTNM) | cut -d: -f2 | awk '{ print $1}'`
  sed -i "s/8.8.8.8/$_THISHTIP/g" $_THIS_LTD_CONF
  if [ ! -e "/root/.allow.mc.cnf" ] ; then
    sed -i "s/'mc', //g" $_THIS_LTD_CONF
    sed -i "s/, 'mc':'mc -u'//g" $_THIS_LTD_CONF
  fi
  add_ltd_group_if_not_exists
  sleep 1
  kill_zombies >/var/backups/ltd/log/zombies-$_NOW.log 2>&1
  sleep 1
  manage_own >/var/backups/ltd/log/users-$_NOW.log 2>&1
  sleep 1
  cp -af /etc/lshell.conf /var/backups/ltd/old/lshell.conf-before-$_NOW
  sleep 1
  cp -af $_THIS_LTD_CONF /etc/lshell.conf
  sleep 1
  find /var/backups/ltd/*/* -mtime +1 -type f -exec rm -rf {} \;
  rm -f $_TMP/*.txt
  if [ ! -e "/root/.home.no.wildcard.chmod.cnf" ] ; then
    chmod 700 /home/* &> /dev/null
  fi
  chmod 600 /var/log/lsh/*
fi
###EOF2014###
