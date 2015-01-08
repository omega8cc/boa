#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
_HOST_TEST=`uname -n 2>&1`
_VM_TEST=`uname -a 2>&1`
_USRG=users
_WEBG=www-data
_THIS_RV=`lsb_release -sc`
if [ "$_THIS_RV" = "wheezy" ] || [ "$_THIS_RV" = "trusty" ] || [ "$_THIS_RV" = "precise" ] ; then
  _RUBY_VERSION=2.2.0
else
  _RUBY_VERSION=2.0.0
fi
if [[ "$_VM_TEST" =~ beng ]] ; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi
if [ -x "/usr/bin/gpg2" ] ; then
  _GPG=gpg2
else
  _GPG=gpg
fi

###-------------SYSTEM-----------------###

extract_archive() {
  if [ ! -z $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xjf $1    ;;
      *.tar.gz)    tar xzf $1    ;;
      *.bz2)       bunzip2 $1    ;;
      *.rar)       unrar x $1    ;;
      *.gz)        gunzip -q $1  ;;
      *.tar)       tar xf $1     ;;
      *.tbz2)      tar xjf $1    ;;
      *.tgz)       tar xzf $1    ;;
      *.zip)       unzip -qq $1  ;;
      *.Z)         uncompress $1 ;;
      *.7z)        7z x $1       ;;
      *)           echo "'$1' cannot be extracted via >extract<" ;;
    esac
    rm -f $1
  fi
}

get_dev_ext() {
  if [ ! -z $1 ] ; then
    curl -L --max-redirs 10 -k -s -O --retry 10 --retry-delay 15 -A iCab "http://files.aegir.cc/dev/HEAD/$1"
    extract_archive "$1"
  fi
}

###----------------------------###
##    Manage ltd shell users    ##
###----------------------------###
#
# Remove dangerous stuff from the string.
sanitize_string() {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\$\@\&\|\*]//g; s/\(['"'"'\]\)//g'
}
#
# Add ltd-shell group if not exists.
add_ltd_group_if_not_exists() {
  _LTD_EXISTS=$(getent group ltd-shell 2>&1)
  if [[ "$_LTD_EXISTS" =~ "ltd-shell" ]] ; then
    _DO_NOTHING=YES
  else
    addgroup --system ltd-shell &> /dev/null
  fi
}
#
# Enable chattr.
enable_chattr() {
  if [ ! -z "$1" ] && [ -d "/home/$1" ] ; then
    _U_HD="/home/$1/.drush"
    _U_TP="/home/$1/.tmp"
    if [ ! -e "$_U_HD/.ctrl.240dev.txt" ] ; then
      if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
        rm -f -r $_U_HD/*
        rm -f -r $_U_HD/.*
      else
        rm -f $_U_HD/{drush_make,registry_rebuild,clean_missing_modules,drupalgeddon,drush_ecl}
        rm -f $_U_HD/usr/{drush_make,registry_rebuild,clean_missing_modules,drupalgeddon,drush_ecl}
        rm -f $_U_HD/.ctrl*
        rm -f -r $_U_HD/{cache,drush.ini,*drushrc*,*.inc}
      fi
      mkdir -p       $_U_HD/usr
      rm -f -r       $_U_TP
      mkdir -p       $_U_TP
      chmod 700      $_U_TP
      chmod 700      $_U_HD
      chown $1:users $_U_TP
      chown $1:users $_U_HD
      if [ ! -L "$_U_HD/usr/registry_rebuild" ] ; then
        ln -sf /data/disk/${_OWN}/.drush/usr/registry_rebuild $_U_HD/usr/registry_rebuild
      fi
      if [ ! -L "$_U_HD/usr/clean_missing_modules" ] ; then
        ln -sf /data/disk/${_OWN}/.drush/usr/clean_missing_modules $_U_HD/usr/clean_missing_modules
      fi
      if [ ! -L "$_U_HD/usr/drupalgeddon" ] ; then
        ln -sf /data/disk/${_OWN}/.drush/usr/drupalgeddon $_U_HD/usr/drupalgeddon
      fi
      if [ ! -L "$_U_HD/usr/drush_ecl" ] ; then
        ln -sf /data/disk/${_OWN}/.drush/usr/drush_ecl $_U_HD/usr/drush_ecl
      fi
    fi

    _CHECK_USE_PHP_CLI=`grep "/opt/php" /data/disk/${_OWN}/tools/drush/drush.php`
    _PHP_V="56 55 54 53"
    for e in $_PHP_V; do
      if [[ "$_CHECK_USE_PHP_CLI" =~ "php${e}" ]] && [ ! -e "$_U_HD/.ctrl.php${e}.txt" ] ; then
        _PHP_CLI_UPDATE=YES
      fi
    done
    echo _PHP_CLI_UPDATE is $_PHP_CLI_UPDATE for $1

    if [ "$_PHP_CLI_UPDATE" = "YES" ] || [ ! -e "$_U_HD/php.ini" ] || [ ! -e "$_U_HD/.ctrl.240dev.txt" ] ; then
      mkdir -p $_U_HD
      rm -f $_U_HD/.ctrl.php*
      rm -f $_U_HD/php.ini
      if [ ! -z "$_LOC_PHP_CLI_VERSION" ] ; then
        _USE_PHP_CLI="$_LOC_PHP_CLI_VERSION"
        echo _USE_PHP_CLI is $_USE_PHP_CLI for $1 at ${_OWN} WTF _LOC_PHP_CLI_VERSION is $_LOC_PHP_CLI_VERSION
      else
        _CHECK_USE_PHP_CLI=`grep "/opt/php" /data/disk/${_OWN}/tools/drush/drush.php`
        echo _CHECK_USE_PHP_CLI is $_CHECK_USE_PHP_CLI for $1 at ${_OWN}
        if [[ "$_CHECK_USE_PHP_CLI" =~ "php55" ]] ; then
          _USE_PHP_CLI=5.5
        elif [[ "$_CHECK_USE_PHP_CLI" =~ "php56" ]] ; then
          _USE_PHP_CLI=5.6
        elif [[ "$_CHECK_USE_PHP_CLI" =~ "php54" ]] ; then
          _USE_PHP_CLI=5.4
        elif [[ "$_CHECK_USE_PHP_CLI" =~ "php53" ]] ; then
          _USE_PHP_CLI=5.3
        fi
      fi
      echo _USE_PHP_CLI is $_USE_PHP_CLI for $1
      if [ "$_USE_PHP_CLI" = "5.5" ] ; then
        cp -af /opt/php55/lib/php.ini $_U_HD/php.ini
        _U_INI=55
      elif [ "$_USE_PHP_CLI" = "5.6" ] ; then
        cp -af /opt/php56/lib/php.ini $_U_HD/php.ini
        _U_INI=56
      elif [ "$_USE_PHP_CLI" = "5.4" ] ; then
        cp -af /opt/php54/lib/php.ini $_U_HD/php.ini
        _U_INI=54
      elif [ "$_USE_PHP_CLI" = "5.3" ] ; then
        cp -af /opt/php53/lib/php.ini $_U_HD/php.ini
        _U_INI=53
      fi
      if [ -e "$_U_HD/php.ini" ] ; then
        _INI="open_basedir = \".:/data/disk/${_OWN}/distro:/data/disk/${_OWN}/static:/data/disk/${_OWN}/platforms:/data/all:/data/disk/all:/data/conf:/usr/bin:/opt/tools/drush:/home:/data/disk/${_OWN}/.drush/usr:/opt/tika:/opt/tika7:/opt/tika8:/opt/tika9:/opt/php53:/opt/php54:/opt/php55:/opt/php56\""
        _INI=${_INI//\//\\\/}
        _QTP=${_U_TP//\//\\\/}
        sed -i "s/.*open_basedir =.*/$_INI/g"                              $_U_HD/php.ini &> /dev/null
        sed -i "s/.*error_reporting =.*/error_reporting = 1/g"             $_U_HD/php.ini &> /dev/null
        sed -i "s/.*session.save_path =.*/session.save_path = $_QTP/g"     $_U_HD/php.ini &> /dev/null
        sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = $_QTP/g" $_U_HD/php.ini &> /dev/null
        sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = $_QTP/g"               $_U_HD/php.ini &> /dev/null
        sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = $_QTP/g"           $_U_HD/php.ini &> /dev/null
        echo > $_U_HD/.ctrl.php${_U_INI}.txt
        echo > $_U_HD/.ctrl.240dev.txt
      fi
    fi

    UQ="$1"
    if [ -f "/data/disk/${_OWN}/static/control/compass.info" ] ; then
      if [ -d "/home/${UQ}/.rvm/src" ] ; then
        rm -f -r /home/${UQ}/.rvm/src/*
      fi
      if [ -d "/home/${UQ}/.rvm/archives" ] ; then
        rm -f -r /home/${UQ}/.rvm/archives/*
      fi
      if [ -d "/home/${UQ}/.rvm/log" ] ; then
        rm -f -r /home/${UQ}/.rvm/log/*
      fi
      if [ ! -x "/home/${UQ}/.rvm/bin/rvm" ] ; then
        touch /var/run/manage_rvm_users.pid
        su -s /bin/bash - ${UQ} -c "$_GPG --keyserver hkp://keys.gnupg.net --recv-keys D39DC0E3"
        su -s /bin/bash - ${UQ} -c "\curl -sSL https://rvm.io/mpapis.asc | $_GPG --import"
        su -s /bin/bash   ${UQ} -c "\curl -sSL https://get.rvm.io | bash -s stable"
        su -s /bin/bash - ${UQ} -c "rvm get stable --auto-dotfiles"
        su -s /bin/bash - ${UQ} -c "echo rvm_autoupdate_flag=0 > ~/.rvmrc"
        rm -f /var/run/manage_rvm_users.pid
      fi
      su -s /bin/bash - ${UQ} -c "echo rvm_autoupdate_flag=0 > ~/.rvmrc"
      if [ ! -e "/home/${UQ}/.rvm/rubies/default" ] ; then
        if [ -x "/bin/websh" ] && [ -L "/bin/sh" ] ; then
          _WEB_SH=`readlink -n /bin/sh`
          _WEB_SH=`echo -n $_WEB_SH | tr -d "\n"`
          if [ -x "/bin/dash" ] ; then
            if [ "$_WEB_SH" != "/bin/dash" ] ; then
              rm -f /bin/sh
              ln -s /bin/dash /bin/sh
            fi
          else
            if [ "$_WEB_SH" != "/bin/bash" ] ; then
              rm -f /bin/sh
              ln -s /bin/bash /bin/sh
            fi
          fi
        fi
        touch /var/run/manage_rvm_users.pid
        su -s /bin/bash - ${UQ} -c "rvm install ${_RUBY_VERSION}"
        su -s /bin/bash - ${UQ} -c "rvm use ${_RUBY_VERSION} --default"
        rm -f /var/run/manage_rvm_users.pid
        rm -f /bin/sh
        ln -s /bin/websh /bin/sh
      fi
      if [ ! -f "/data/disk/${_OWN}/log/.gems.build.d.${UQ}.txt" ] ; then
        rm -f /data/disk/${_OWN}/log/eventmachine*
        if [ -x "/bin/websh" ] && [ -L "/bin/sh" ] ; then
          _WEB_SH=`readlink -n /bin/sh`
          _WEB_SH=`echo -n $_WEB_SH | tr -d "\n"`
          if [ -x "/bin/dash" ] ; then
            if [ "$_WEB_SH" != "/bin/dash" ] ; then
              rm -f /bin/sh
              ln -s /bin/dash /bin/sh
            fi
          else
            if [ "$_WEB_SH" != "/bin/bash" ] ; then
              rm -f /bin/sh
              ln -s /bin/bash /bin/sh
            fi
          fi
        fi
        touch /var/run/manage_rvm_users.pid
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --conservative bluecloth"      &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --conservative eventmachine"   &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --conservative ffi"            &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --version 1.9.3 ffi"           &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --conservative hitimes"        &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --conservative http_parser.rb" &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --conservative oily_png"       &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --version 1.1.1 oily_png"      &> /dev/null
        su -s /bin/bash - ${UQ} -c "rvm all do gem install --conservative yajl-ruby"      &> /dev/null
        touch /data/disk/${_OWN}/log/.gems.build.d.${UQ}.txt
        rm -f /var/run/manage_rvm_users.pid
        rm -f /bin/sh
        ln -s /bin/websh /bin/sh
      fi
      if [ -d "/home/${UQ}/.rvm/src" ] ; then
        rm -f -r /home/${UQ}/.rvm/src/*
      fi
      if [ -d "/home/${UQ}/.rvm/archives" ] ; then
        rm -f -r /home/${UQ}/.rvm/archives/*
      fi
      if [ -d "/home/${UQ}/.rvm/log" ] ; then
        rm -f -r /home/${UQ}/.rvm/log/*
      fi
      rm -f /home/${UQ}/{.profile,.bash_logout,.bash_profile,.bashrc,.zlogin,.zshrc}
      rm -f /home/${UQ}/.rvm/scripts/notes
    else
      if [ -d "/home/${UQ}/.rvm" ] || [ -d "/home/${UQ}/.gem" ] ; then
        rm -f /data/disk/${_OWN}/log/.gems.build*
        rm -f -r /home/${UQ}/.rvm    &> /dev/null
        rm -f -r /home/${UQ}/.gem    &> /dev/null
      fi
    fi

    if [ "$1" != "${_OWN}.ftp" ] ; then
      chattr +i /home/$1             &> /dev/null
    else
      chattr +i /home/$1/platforms   &> /dev/null
      chattr +i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.bazaar" ] ; then
      chattr +i /home/$1/.bazaar     &> /dev/null
    fi
    chattr +i /home/$1/.drush        &> /dev/null
    chattr +i /home/$1/.drush/usr    &> /dev/null
    chattr +i /home/$1/.drush/*.ini  &> /dev/null
  fi
}
#
# Disable chattr.
disable_chattr() {
  if [ ! -z "$1" ] && [ -d "/home/$1" ] ; then
    if [ "$1" != "${_OWN}.ftp" ] ; then
      chattr -i /home/$1             &> /dev/null
    else
      chattr -i /home/$1/platforms   &> /dev/null
      chattr -i /home/$1/platforms/* &> /dev/null
    fi
    if [ -d "/home/$1/.bazaar" ] ; then
      chattr -i /home/$1/.bazaar     &> /dev/null
    fi
    chattr -i /home/$1/.drush        &> /dev/null
    chattr -i /home/$1/.drush/usr    &> /dev/null
    chattr -i /home/$1/.drush/*.ini  &> /dev/null
    if [ "$1" != "${_OWN}.ftp" ] ; then
      if [ ! -L "/home/$1/.drush/usr/drupalgeddon" ] && [ -d "/data/disk/${_OWN}/.drush/usr/drupalgeddon" ] ; then
        ln -sf /data/disk/${_OWN}/.drush/usr/drupalgeddon /home/$1/.drush/usr/drupalgeddon
      fi
    else
      if [ ! -d "/data/disk/${_OWN}/.drush/usr/drupalgeddon" ] || [ ! -e "/data/disk/${_OWN}/static/control/.drupalgeddon.in.015.pid" ] ; then
        rm -f /data/disk/${_OWN}/.drush/usr/drupalgeddon &> /dev/null
        cd /data/disk/${_OWN}/.drush/usr
        get_dev_ext "drupalgeddon.tar.gz"
        find /data/disk/${_OWN}/.drush/usr/drupalgeddon -type d -exec chmod 0750 {} \; &> /dev/null
        find /data/disk/${_OWN}/.drush/usr/drupalgeddon -type f -exec chmod 0640 {} \; &> /dev/null
        chown -R ${_OWN}:users /data/disk/${_OWN}/.drush/usr/drupalgeddon
        rm -f /data/disk/${_OWN}/static/control/.drupalgeddon.in.00*.pid
        touch /data/disk/${_OWN}/static/control/.drupalgeddon.in.015.pid
      fi
      if [ ! -L "/home/$1/.drush/usr/drupalgeddon" ] && [ -d "/data/disk/${_OWN}/.drush/usr/drupalgeddon" ] ; then
        rm -f -r /home/$1/.drush/usr/drupalgeddon
        ln -sf /data/disk/${_OWN}/.drush/usr/drupalgeddon /home/$1/.drush/usr/drupalgeddon
      fi
    fi
  fi
}
#
# Kill zombies.
kill_zombies() {
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
fix_dot_dirs() {
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
    if [ ! -e "$_USER_BZR/bazaar.conf" ] ; then
      mkdir -p $_USER_BZR
      echo ignore_missing_extensions=True > $_USER_BZR/bazaar.conf
      chown -R $_USER_LTD:$_USRG $_USER_BZR
      chmod 700 $_USER_BZR
    fi
  else
    rm -f -r $_USER_BZR
  fi
}
#
# Manage Drush Aliases.
manage_sec_user_drush_aliases() {
  rm -f $_USER_LTD_ROOT/sites
  ln -sf $Client $_USER_LTD_ROOT/sites
  mkdir -p $_USER_LTD_ROOT/.drush
  for Alias in `find $_USER_LTD_ROOT/.drush/*.alias.drushrc.php -maxdepth 1 -type f | sort`
  do
    AliasName=`echo "$Alias" | cut -d'/' -f5 | awk '{ print $1}'`
    AliasName=`echo "$AliasName" | sed "s/.alias.drushrc.php//g" | awk '{ print $1}'`
    if [ ! -z "$AliasName" ] && [ ! -e "$_USER_LTD_ROOT/sites/${AliasName}" ] ; then
      rm -f $_USER_LTD_ROOT/.drush/${AliasName}.alias.drushrc.php
    fi
  done
  for Symlink in `find $_USER_LTD_ROOT/sites/ -maxdepth 1 -mindepth 1 | sort`
  do
    _THIS_SITE_NAME=`echo $Symlink | cut -d'/' -f5 | awk '{ print $1}'`
    if [ ! -z "$_THIS_SITE_NAME" ] && [ ! -e "$_USER_LTD_ROOT/.drush/${_THIS_SITE_NAME}.alias.drushrc.php" ] ; then
      cp -af $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php $_USER_LTD_ROOT/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
      chmod 440 $_USER_LTD_ROOT/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
    elif [ ! -z "$_THIS_SITE_NAME" ] && [ -e "$_USER_LTD_ROOT/.drush/${_THIS_SITE_NAME}.alias.drushrc.php" ] ; then
      _DIFF_TEST=$(diff $_USER_LTD_ROOT/.drush/${_THIS_SITE_NAME}.alias.drushrc.php  $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php)
      if [ ! -z "$_DIFF_TEST" ] ; then
        cp -af $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php $_USER_LTD_ROOT/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
        chmod 440 $_USER_LTD_ROOT/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
      fi
    fi
  done
}
#
# OK, create user.
ok_create_user() {
  _ADMIN="${_OWN}.ftp"
  echo "_ADMIN is == $_ADMIN == at ok_create_user"
  _USER_LTD_ROOT="/home/$_USER_LTD"
  _SEC_SYM="$_USER_LTD_ROOT/sites"
  _TMP="/var/tmp"
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
    if [ "$_STRONG_PASSWORDS" = "YES" ]  ; then
      _PWD_CHARS=32
    elif [ "$_STRONG_PASSWORDS" = "NO" ] ; then
      _PWD_CHARS=8
    else
      _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
      if [ ! -z "$_STRONG_PASSWORDS" ] && [ $_STRONG_PASSWORDS -gt "8" ] ; then
        _PWD_CHARS="$_STRONG_PASSWORDS"
      else
        _PWD_CHARS=8
      fi
      if [ ! -z "$_PWD_CHARS" ] && [ $_PWD_CHARS -gt "128" ] ; then
        _PWD_CHARS=128
      fi
    fi
    if [ "$_STRONG_PASSWORDS" = "YES" ] || [ $_PWD_CHARS -gt "8" ] ; then
      _ESC_LUPASS=$(randpass $_PWD_CHARS alnum 2>&1)
      _ESC_LUPASS=`echo -n $_ESC_LUPASS | tr -d "\n"`
      _LEN_LUPASS=$(echo ${#_ESC_LUPASS})
    fi
    if [ -z "$_ESC_LUPASS" ] || [ $_LEN_LUPASS -lt 9 ] ; then
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
    chmod 700 $_USER_LTD_ROOT
    mkdir -p /home/$_ADMIN/users
    echo "$_ESC_LUPASS" > /home/$_ADMIN/users/$_USER_LTD
  fi
  fix_dot_dirs
  rm -f $_USER_LTD_ROOT/{.profile,.bash_logout,.bash_profile,.bashrc}
}
#
# OK, update user.
ok_update_user() {
  _ADMIN="${_OWN}.ftp"
  _USER_LTD_ROOT="/home/$_USER_LTD"
  if [ -e "/home/$_ADMIN/users/$_USER_LTD" ] ; then
    echo >> $_THIS_LTD_CONF
    echo "[$_USER_LTD]" >> $_THIS_LTD_CONF
    echo "path : [$_ALLD_DIR]" >> $_THIS_LTD_CONF
    manage_sec_user_drush_aliases
    chmod 700 $_USER_LTD_ROOT
  fi
  fix_dot_dirs
  rm -f $_USER_LTD_ROOT/{.profile,.bash_logout,.bash_profile,.bashrc}
}
#
# Add user if not exists.
add_user_if_not_exists() {
  _ID_EXISTS=$(getent passwd $_USER_LTD 2>&1)
  _ID_SHELLS=$(id -nG $_USER_LTD 2>&1)
  echo "_ID_EXISTS is == $_ID_EXISTS == at add_user_if_not_exists"
  echo "_ID_SHELLS is == $_ID_SHELLS == at add_user_if_not_exists"
  if [ -z "$_ID_EXISTS" ] ; then
    echo "We will create user == $_USER_LTD =="
    ok_create_user
    manage_sec_user_drush_aliases
    enable_chattr $_USER_LTD
  elif [[ "$_ID_EXISTS" =~ "$_USER_LTD" ]] && [[ "$_ID_SHELLS" =~ "ltd-shell" ]] ; then
    echo "We will update user == $_USER_LTD =="
    disable_chattr $_USER_LTD
    rm -f -r /home/${_USER_LTD}/drush-backups
    find /home/${_USER_LTD}/.tmp/* -mtime +0 -exec rm -rf {} \; &> /dev/null
    ok_update_user
    enable_chattr $_USER_LTD
  fi
}
#
# Manage Access Paths.
manage_sec_access_paths() {
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
manage_sec() {
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
# Update local INI for PHP CLI on the Aegir Satellite Instance.
update_php_cli_local_ini() {
  _U_HD="/data/disk/${_OWN}/.drush"
  _U_TP="/data/disk/${_OWN}/.tmp"
  _PHP_CLI_UPDATE=NO
  _CHECK_USE_PHP_CLI=`grep "/opt/php" $_DRUSH_FILE`
  _PHP_V="56 55 54 53"
  for e in $_PHP_V; do
    if [[ "$_CHECK_USE_PHP_CLI" =~ "php${e}" ]] && [ ! -e "$_U_HD/.ctrl.php${e}.txt" ] ; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  if [ "$_PHP_CLI_UPDATE" = "YES" ] || [ ! -e "$_U_HD/php.ini" ] || [ ! -d "$_U_TP" ] || [ ! -e "$_U_HD/.ctrl.240dev.txt" ] ; then
    rm -f -r $_U_TP
    mkdir -p $_U_TP
    chmod 700 $_U_TP
    mkdir -p $_U_HD
    chattr -i $_U_HD/php.ini &> /dev/null
    rm -f $_U_HD/.ctrl.php*
    rm -f $_U_HD/php.ini
    if [[ "$_CHECK_USE_PHP_CLI" =~ "php55" ]] ; then
      cp -af /opt/php55/lib/php.ini $_U_HD/php.ini
      _U_INI=55
    elif [[ "$_CHECK_USE_PHP_CLI" =~ "php56" ]] ; then
      cp -af /opt/php56/lib/php.ini $_U_HD/php.ini
      _U_INI=56
    elif [[ "$_CHECK_USE_PHP_CLI" =~ "php54" ]] ; then
      cp -af /opt/php54/lib/php.ini $_U_HD/php.ini
      _U_INI=54
    elif [[ "$_CHECK_USE_PHP_CLI" =~ "php53" ]] ; then
      cp -af /opt/php53/lib/php.ini $_U_HD/php.ini
      _U_INI=53
    fi
    if [ -e "$_U_HD/php.ini" ] ; then
      _INI="open_basedir = \".:/data/disk/${_OWN}:/data/all:/data/disk/all:/data/conf:/usr/bin:/opt/tools/drush:/opt/tika:/opt/tika7:/opt/tika8:/opt/tika9:/opt/php53:/opt/php54:/opt/php55:/opt/php56\""
      _INI=${_INI//\//\\\/}
      _QTP=${_U_TP//\//\\\/}
      sed -i "s/.*open_basedir =.*/$_INI/g"                              $_U_HD/php.ini &> /dev/null
      sed -i "s/.*error_reporting =.*/error_reporting = 1/g"             $_U_HD/php.ini &> /dev/null
      sed -i "s/.*session.save_path =.*/session.save_path = $_QTP/g"     $_U_HD/php.ini &> /dev/null
      sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = $_QTP/g" $_U_HD/php.ini &> /dev/null
      sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = $_QTP/g"               $_U_HD/php.ini &> /dev/null
      sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = $_QTP/g"           $_U_HD/php.ini &> /dev/null
      echo > $_U_HD/.ctrl.php${_U_INI}.txt
      echo > $_U_HD/.ctrl.240dev.txt
    fi
    chattr +i $_U_HD/php.ini &> /dev/null
  fi
}
#
# Update PHP-CLI for Drush.
update_php_cli_drush() {
  _DRUSH_FILE="/data/disk/${_OWN}/tools/drush/drush.php"
  if [ "$_LOC_PHP_CLI_VERSION" = "5.5" ] && [ -x "/opt/php55/bin/php" ] ; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php55\/bin\/php/g"  $_DRUSH_FILE &> /dev/null
    _L_PHP_CLI=/opt/php55/bin
  elif [ "$_LOC_PHP_CLI_VERSION" = "5.6" ] && [ -x "/opt/php56/bin/php" ] ; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php56\/bin\/php/g"  $_DRUSH_FILE &> /dev/null
    _L_PHP_CLI=/opt/php56/bin
  elif [ "$_LOC_PHP_CLI_VERSION" = "5.4" ] && [ -x "/opt/php54/bin/php" ] ; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php54\/bin\/php/g"  $_DRUSH_FILE &> /dev/null
    _L_PHP_CLI=/opt/php54/bin
  elif [ "$_LOC_PHP_CLI_VERSION" = "5.3" ] && [ -x "/opt/php53/bin/php" ] ; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php53\/bin\/php/g"  $_DRUSH_FILE &> /dev/null
    _L_PHP_CLI=/opt/php53/bin
  else
    _L_PHP_CLI=/foo/bar
  fi
  if [ -x "$_L_PHP_CLI/php" ] ; then
    _DRUSHCMD="$_L_PHP_CLI/php /data/disk/${_OWN}/tools/drush/drush.php"
    if [ -e "/data/disk/${_OWN}/aegir.sh" ] ; then
      rm -f /data/disk/${_OWN}/aegir.sh
    fi
    touch /data/disk/${_OWN}/aegir.sh
    echo -e "#!/bin/bash\n\nPATH=.:$_L_PHP_CLI:/usr/sbin:/usr/bin:/sbin:/bin\n$_DRUSHCMD '@hostmaster' hosting-dispatch\ntouch /data/disk/${_OWN}/${_OWN}-task.done" | tee -a /data/disk/${_OWN}/aegir.sh >/dev/null 2>&1
    chown ${_OWN}:users /data/disk/${_OWN}/aegir.sh &> /dev/null
    chmod 0700 /data/disk/${_OWN}/aegir.sh &> /dev/null
  fi
}
#
# Tune FPM workers.
tune_fpm_workers() {
  _ETH_TEST=`ifconfig 2>&1`
  _AWS_TEST_A=$(grep cloudimg /etc/fstab)
  _AWS_TEST_B=$(grep cloudconfig /etc/fstab)
  if [[ "$_ETH_TEST" =~ "venet0" ]] ; then
    _VMFAMILY="VZ"
  elif [ -e "/proc/bean_counters" ] ; then
    _VMFAMILY="VZ"
  elif [[ "$_HOST_TEST" =~ ".host8." ]] && [ -e "/boot/grub/menu.lst" ] ; then
    _VMFAMILY="TG"
  elif [[ "$_HOST_TEST" =~ ".host8." ]] && [ -e "/boot/grub/grub.cfg" ] ; then
    _VMFAMILY="TG"
  else
    _VMFAMILY="XEN"
  fi
  if [[ "$_VM_TEST" =~ beng ]] ; then
    _VMFAMILY="VS"
  fi
  if [[ "$_AWS_TEST_A" =~ "cloudimg" ]] || [[ "$_AWS_TEST_B" =~ "cloudconfig" ]] ; then
    _VMFAMILY="AWS"
  fi
  _RAM=`free -mto | grep Mem: | awk '{ print $2 }'`
  if [ "$_RESERVED_RAM" -gt "0" ] ; then
    let "_RAM = (($_RAM - $_RESERVED_RAM))"
  fi
  let "_USE = (($_RAM / 4))"
  if [ "$_USE" -ge "512" ] && [ "$_USE" -lt "1024" ] ; then
    if [ "$_PHP_FPM_WORKERS" = "AUTO" ] ; then
      _L_PHP_FPM_WORKERS=12
    else
      _L_PHP_FPM_WORKERS=$_PHP_FPM_WORKERS
    fi
  elif [ "$_USE" -ge "1024" ] ; then
    if [ "$_VMFAMILY" = "XEN" ] || [ "$_VMFAMILY" = "AWS" ] ; then
      if [ "$_PHP_FPM_WORKERS" = "AUTO" ] ; then
        _L_PHP_FPM_WORKERS=24
      else
        _L_PHP_FPM_WORKERS=$_PHP_FPM_WORKERS
      fi
    elif [ "$_VMFAMILY" = "VS" ] || [ "$_VMFAMILY" = "TG" ] ; then
      if [ -e "/boot/grub/grub.cfg" ] || [ -e "/boot/grub/menu.lst" ] || [ -e "/root/.tg.cnf" ] ; then
        if [ "$_PHP_FPM_WORKERS" = "AUTO" ] ; then
          _L_PHP_FPM_WORKERS=24
        else
          _L_PHP_FPM_WORKERS=$_PHP_FPM_WORKERS
        fi
      else
        if [ "$_PHP_FPM_WORKERS" = "AUTO" ] ; then
          _L_PHP_FPM_WORKERS=6
        else
          _L_PHP_FPM_WORKERS=$_PHP_FPM_WORKERS
        fi
      fi
    else
      if [ "$_PHP_FPM_WORKERS" = "AUTO" ] ; then
        _L_PHP_FPM_WORKERS=12
      else
        _L_PHP_FPM_WORKERS=$_PHP_FPM_WORKERS
      fi
    fi
  else
    if [ "$_PHP_FPM_WORKERS" = "AUTO" ] ; then
      _L_PHP_FPM_WORKERS=6
    else
      _L_PHP_FPM_WORKERS=$_PHP_FPM_WORKERS
    fi
  fi
}
#
# Disable New Relic per Octopus instance.
disable_newrelic() {
  _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
  if [ -z "$_PHP_SV" ] ; then
    _PHP_SV=55
  fi
  _THIS_POOL_TPL="/opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf"
  if [ -e "$_THIS_POOL_TPL" ] ; then
    _CHECK_NEW_RELIC_KEY=`grep "newrelic.enabled.*true" $_THIS_POOL_TPL`
    if [[ "$_CHECK_NEW_RELIC_KEY" =~ "newrelic.enabled" ]] ; then
      echo New Relic for ${_OWN} will be disabled because newrelic.info does not exist
      sed -i "s/^php_admin_value\[newrelic.license\].*/php_admin_value\[newrelic.license\] = \"\"/g" $_THIS_POOL_TPL
      sed -i "s/^php_admin_value\[newrelic.enabled\].*/php_admin_value\[newrelic.enabled\] = \"false\"/g" $_THIS_POOL_TPL
      if [ -e "/etc/init.d/php${_PHP_SV}-fpm" ] ; then
        service php${_PHP_SV}-fpm reload
      fi
    fi
  fi
}
#
# Enable New Relic per Octopus instance.
enable_newrelic() {
  _LOC_NEW_RELIC_KEY=`cat /data/disk/${_OWN}/static/control/newrelic.info`
  _LOC_NEW_RELIC_KEY=${_LOC_NEW_RELIC_KEY//[^0-9a-zA-Z]/}
  _LOC_NEW_RELIC_KEY=`echo -n $_LOC_NEW_RELIC_KEY | tr -d "\n"`
  if [ -z "$_LOC_NEW_RELIC_KEY" ] ; then
    disable_newrelic
  else
    _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
    if [ -z "$_PHP_SV" ] ; then
      _PHP_SV=55
    fi
    _THIS_POOL_TPL="/opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf"
    if [ -e "$_THIS_POOL_TPL" ] ; then
      _CHECK_NEW_RELIC_TPL=`grep "newrelic.license" $_THIS_POOL_TPL`
      _CHECK_NEW_RELIC_KEY=`grep "$_LOC_NEW_RELIC_KEY" $_THIS_POOL_TPL`
      if [[ "$_CHECK_NEW_RELIC_KEY" =~ "$_LOC_NEW_RELIC_KEY" ]] ; then
        echo "New Relic integration is already active for ${_OWN}"
      else
        if [[ "$_CHECK_NEW_RELIC_TPL" =~ "newrelic.license" ]] ; then
          echo New Relic for ${_OWN} update with key $_LOC_NEW_RELIC_KEY in php${_PHP_SV}
          sed -i "s/^php_admin_value\[newrelic.license\].*/php_admin_value\[newrelic.license\] = \"$_LOC_NEW_RELIC_KEY\"/g" $_THIS_POOL_TPL
          sed -i "s/^php_admin_value\[newrelic.enabled\].*/php_admin_value\[newrelic.enabled\] = \"true\"/g" $_THIS_POOL_TPL
        else
          echo New Relic for ${_OWN} setup with key $_LOC_NEW_RELIC_KEY in php${_PHP_SV}
          echo "php_admin_value[newrelic.license] = \"$_LOC_NEW_RELIC_KEY\"" >> $_THIS_POOL_TPL
          echo "php_admin_value[newrelic.enabled] = \"true\"" >> $_THIS_POOL_TPL
        fi
        if [ -e "/etc/init.d/php${_PHP_SV}-fpm" ] ; then
          service php${_PHP_SV}-fpm reload
        fi
      fi
    fi
  fi
}
#
# Switch New Relic on or off per Octopus instance.
switch_newrelic() {
  if [ -e "/data/disk/${_OWN}/static/control/newrelic.info" ] ; then
    enable_newrelic
  else
    disable_newrelic
  fi
}
#
# Update web user.
update_web_user() {
  _T_HD="/home/${_OWN}.web/.drush"
  _T_TP="/home/${_OWN}.web/.tmp"
  if [ -e "/home/${_OWN}.web" ] ; then
    mkdir -p /home/${_OWN}.web/.{tmp,drush}
    if [ ! -z "$1" ] ; then
      if [ "$1" = "hhvm" ] ; then
        if [ -e "/opt/php56/etc/php56.ini" ] ; then
          _T_PV=56
        elif [ -e "/opt/php55/etc/php55.ini" ] ; then
          _T_PV=55
        fi
      else
        _T_PV=$1
      fi
    fi
    if [ ! -z "$_T_PV" ] && [ -e "/opt/php${_T_PV}/etc/php${_T_PV}.ini" ] ; then
      cp -af /opt/php${_T_PV}/etc/php${_T_PV}.ini $_T_HD/php.ini
    else
      if [ -e "/opt/php55/etc/php55.ini" ] ; then
        cp -af /opt/php55/etc/php55.ini $_T_HD/php.ini
        _T_PV=55
      elif [ -e "/opt/php56/etc/php56.ini" ] ; then
        cp -af /opt/php56/etc/php56.ini $_T_HD/php.ini
        _T_PV=56
      elif [ -e "/opt/php54/etc/php54.ini" ] ; then
        cp -af /opt/php54/etc/php54.ini $_T_HD/php.ini
        _T_PV=54
      elif [ -e "/opt/php53/etc/php53.ini" ] ; then
        cp -af /opt/php53/etc/php53.ini $_T_HD/php.ini
        _T_PV=53
      fi
    fi
    if [ -e "$_T_HD/php.ini" ] ; then
      _INI="open_basedir = \".:/data/disk/${_OWN}/distro:/data/disk/${_OWN}/static:/data/disk/${_OWN}/aegir:/data/disk/${_OWN}/platforms:/data/disk/${_OWN}/backup-exports:${_T_TP}:/data/all:/data/disk/all:/data/conf:/var/second/${_OWN}:/mnt:/srv:/usr/bin:/opt/tika:/opt/tika7:/opt/tika8:/opt/tika9:/opt/php53:/opt/php54:/opt/php55:/opt/php56\""
      _INI=${_INI//\//\\\/}
      _QTP=${_T_TP//\//\\\/}
      sed -i "s/.*open_basedir =.*/$_INI/g"                              $_T_HD/php.ini &> /dev/null
      sed -i "s/.*session.save_path =.*/session.save_path = $_QTP/g"     $_T_HD/php.ini &> /dev/null
      sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = $_QTP/g" $_T_HD/php.ini &> /dev/null
      sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = $_QTP/g"               $_T_HD/php.ini &> /dev/null
      sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = $_QTP/g"           $_T_HD/php.ini &> /dev/null
      rm -f $_T_HD/.ctrl.php*
      echo > $_T_HD/.ctrl.php${_T_PV}.txt
    fi
    chmod 700 /home/${_OWN}.web
    chown -R ${_OWN}.web:www-data /home/${_OWN}.web
    chmod 550 /home/${_OWN}.web/.drush
    chmod 440 /home/${_OWN}.web/.drush/php.ini
    chattr +i /home/${_OWN}.web &> /dev/null
    chattr +i /home/${_OWN}.web/.drush &> /dev/null
  fi
}
#
# Remove web user.
remove_web_user() {
  if [ -e "/home/${_OWN}.web/.tmp" ] || [ "$1" = "clean" ] ; then
    chattr -i /home/${_OWN}.web &> /dev/null
    chattr -i /home/${_OWN}.web/.drush &> /dev/null
    deluser --remove-home --backup-to /var/backups/zombie/deleted ${_OWN}.web
    if [ -e "/home/${_OWN}.web" ] ; then
      rm -f -r /home/${_OWN}.web &> /dev/null
    fi
  fi
}
#
# Add web user.
create_web_user() {
  _T_HD="/home/${_OWN}.web/.drush"
  _T_TP="/home/${_OWN}.web/.tmp"
  _T_ID_EXISTS=$(getent passwd ${_OWN}.web 2>&1)
  if [ ! -z "$_T_ID_EXISTS" ] && [ -e "$_T_HD/php.ini" ] ; then
    update_web_user "$1"
  elif [ -z "$_T_ID_EXISTS" ] || [ ! -e "$_T_HD/php.ini" ] ; then
    remove_web_user "clean"
    adduser --force-badname --system --ingroup www-data ${_OWN}.web &> /dev/null
  fi
}
#
# Switch PHP Version.
switch_php() {
  _PHP_CLI_UPDATE=NO
  _LOC_PHP_CLI_VERSION=""
  if [ -e "/data/disk/${_OWN}/static/control/fpm.info" ] || [ -e "/data/disk/${_OWN}/static/control/cli.info" ] || [ -e "/data/disk/${_OWN}/static/control/hhvm.info" ] ; then
    echo "Custom FPM, HHVM or CLI settings for $_OWN exist, running switch_php checks"
    if [ -e "/data/disk/${_OWN}/static/control/cli.info" ] ; then
      _LOC_PHP_CLI_VERSION=`cat /data/disk/${_OWN}/static/control/cli.info`
      _LOC_PHP_CLI_VERSION=${_LOC_PHP_CLI_VERSION//[^0-9.]/}
      _LOC_PHP_CLI_VERSION=`echo -n $_LOC_PHP_CLI_VERSION | tr -d "\n"`
      if [ "$_LOC_PHP_CLI_VERSION" = "5.6" ] || [ "$_LOC_PHP_CLI_VERSION" = "5.5" ] || [ "$_LOC_PHP_CLI_VERSION" = "5.4" ] || [ "$_LOC_PHP_CLI_VERSION" = "5.3" ] || [ "$_LOC_PHP_CLI_VERSION" = "5.2" ]; then
        if [ "$_LOC_PHP_CLI_VERSION" = "5.5" ] && [ ! -x "/opt/php55/bin/php" ] ; then
          if [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.6
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.4
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.3
          fi
        elif [ "$_LOC_PHP_CLI_VERSION" = "5.6" ] && [ ! -x "/opt/php56/bin/php" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.5
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.4
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.3
          fi
        elif [ "$_LOC_PHP_CLI_VERSION" = "5.4" ] && [ ! -x "/opt/php54/bin/php" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.5
          elif [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.6
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.3
          fi
        elif [ "$_LOC_PHP_CLI_VERSION" = "5.3" ] && [ ! -x "/opt/php53/bin/php" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.5
          elif [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.6
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.4
          fi
        elif [ "$_LOC_PHP_CLI_VERSION" = "5.2" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.5
          elif [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.6
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.4
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_CLI_VERSION=5.3
          fi
        fi
        if [ "$_LOC_PHP_CLI_VERSION" != "$_PHP_CLI_VERSION" ] ; then
          _PHP_CLI_UPDATE=YES
          update_php_cli_drush
          if [ -x "$_L_PHP_CLI/php" ] ; then
            update_php_cli_local_ini
            sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=$_LOC_PHP_CLI_VERSION/g" /root/.${_OWN}.octopus.cnf &> /dev/null
            echo $_LOC_PHP_CLI_VERSION > /data/disk/${_OWN}/log/cli.txt
            echo $_LOC_PHP_CLI_VERSION > /data/disk/${_OWN}/static/control/cli.info
            chown ${_OWN}.ftp:users /data/disk/${_OWN}/static/control/cli.info
          fi
        fi
      fi
    fi
    if [ -e "/data/disk/${_OWN}/static/control/hhvm.info" ] ; then
      if [ -x "/usr/bin/hhvm" ] && [ -e "/var/xdrago/conf/hhvm/init.d/hhvm.foo" ] && [ -e "/var/xdrago/conf/hhvm/server.foo.ini" ] ; then
        if [ ! -e "/opt/hhvm/server.${_OWN}.ini" ] || [ ! -e "/etc/init.d/hhvm.${_OWN}" ] || [ ! -e "/var/run/hhvm/${_OWN}" ]  ; then
          ### create or update special system user if needed
          create_web_user "hhvm"
          ### configure custom hhvm server init.d script
          cp -af /var/xdrago/conf/hhvm/init.d/hhvm.foo /etc/init.d/hhvm.${_OWN}
          sed -i "s/foo/${_OWN}/g" /etc/init.d/hhvm.${_OWN} &> /dev/null
          sed -i "s/.ftp/.web/g" /etc/init.d/hhvm.${_OWN} &> /dev/null
          chmod 755 /etc/init.d/hhvm.${_OWN}
          chown root:root /etc/init.d/hhvm.${_OWN}
          update-rc.d hhvm.${_OWN} defaults &> /dev/null
          ### configure custom hhvm server ini file
          mkdir -p /opt/hhvm
          cp -af /var/xdrago/conf/hhvm/server.foo.ini /opt/hhvm/server.${_OWN}.ini
          sed -i "s/foo/${_OWN}/g" /opt/hhvm/server.${_OWN}.ini &> /dev/null
          sed -i "s/.ftp/.web/g" /opt/hhvm/server.${_OWN}.ini &> /dev/null
          chmod 755 /opt/hhvm/server.${_OWN}.ini
          chown root:root /opt/hhvm/server.${_OWN}.ini
          mkdir -p /var/log/hhvm/${_OWN}
          chown ${_OWN}.web:www-data /var/log/hhvm/${_OWN}
          ### start custom hhvm server
          service hhvm.${_OWN} start &> /dev/null
          ### remove fpm control file to avoid confusion
          rm -f /data/disk/${_OWN}/static/control/fpm.info
          ### update nginx configuration
          sed -i "s/\/var\/run\/${_OWN}.fpm.socket/\/var\/run\/hhvm\/${_OWN}\/hhvm.socket/g" /data/disk/${_OWN}/config/includes/nginx_vhost_common.conf
          sed -i "s/\/var\/run\/${_OWN}.fpm.socket/\/var\/run\/hhvm\/${_OWN}\/hhvm.socket/g" /data/disk/${_OWN}/.drush/sys/provision/http/Provision/Config/Nginx/Inc/vhost_include.tpl.php
          ### reload nginx
          service nginx reload &> /dev/null
        fi
      fi
    else
      if [ -e "/opt/hhvm/server.${_OWN}.ini" ] || [ -e "/etc/init.d/hhvm.${_OWN}" ] || [ -e "/var/run/hhvm/${_OWN}" ]  ; then
        ### disable no longer used custom hhvm server instance
        if [ -e "/etc/init.d/hhvm.${_OWN}" ] ; then
          service hhvm.${_OWN} stop &> /dev/null
          update-rc.d -f hhvm.${_OWN} remove &> /dev/null
          rm -f /etc/init.d/hhvm.${_OWN}
        fi
        ### delete special system user no longer needed
        remove_web_user "hhvm"
        ### delete leftovers
        rm -f /opt/hhvm/server.${_OWN}.ini
        rm -f -r /var/run/hhvm/${_OWN}
        rm -f -r /var/log/hhvm/${_OWN}
        ### update nginx configuration
        sed -i "s/\/var\/run\/hhvm\/${_OWN}\/hhvm.socket/\/var\/run\/${_OWN}.fpm.socket/g" /data/disk/${_OWN}/config/includes/nginx_vhost_common.conf
        sed -i "s/\/var\/run\/hhvm\/${_OWN}\/hhvm.socket/\/var\/run\/${_OWN}.fpm.socket/g" /data/disk/${_OWN}/.drush/sys/provision/http/Provision/Config/Nginx/Inc/vhost_include.tpl.php
        ### reload nginx
        service nginx reload &> /dev/null
        ### create dummy control file to enable PHP-FPM again
        echo 5.2 > /data/disk/${_OWN}/static/control/fpm.info
        chown ${_OWN}.ftp:users /data/disk/${_OWN}/static/control/fpm.info
        _FORCE_FPM_SETUP=YES
      fi
    fi
    sleep 5
    if [ ! -e "/data/disk/${_OWN}/static/control/hhvm.info" ] && [ -e "/data/disk/${_OWN}/static/control/fpm.info" ] && [ -e "/var/xdrago/conf/fpm-pool-foo.conf" ] ; then
      _LOC_PHP_FPM_VERSION=`cat /data/disk/${_OWN}/static/control/fpm.info`
      _LOC_PHP_FPM_VERSION=${_LOC_PHP_FPM_VERSION//[^0-9.]/}
      _LOC_PHP_FPM_VERSION=`echo -n $_LOC_PHP_FPM_VERSION | tr -d "\n"`
      if [ "$_LOC_PHP_FPM_VERSION" = "5.6" ] || [ "$_LOC_PHP_FPM_VERSION" = "5.5" ] || [ "$_LOC_PHP_FPM_VERSION" = "5.4" ] || [ "$_LOC_PHP_FPM_VERSION" = "5.3" ] || [ "$_LOC_PHP_FPM_VERSION" = "5.2" ]; then
        if [ "$_LOC_PHP_FPM_VERSION" = "5.5" ] && [ ! -x "/opt/php55/bin/php" ] ; then
          if [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.6
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.4
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.3
          fi
        elif [ "$_LOC_PHP_FPM_VERSION" = "5.6" ] && [ ! -x "/opt/php56/bin/php" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.5
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.4
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.3
          fi
        elif [ "$_LOC_PHP_FPM_VERSION" = "5.4" ] && [ ! -x "/opt/php54/bin/php" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.5
          elif [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.6
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.3
          fi
        elif [ "$_LOC_PHP_FPM_VERSION" = "5.3" ] && [ ! -x "/opt/php53/bin/php" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.5
          elif [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.6
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.4
          fi
        elif [ "$_LOC_PHP_FPM_VERSION" = "5.2" ] ; then
          if [ -x "/opt/php55/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.5
          elif [ -x "/opt/php56/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.6
          elif [ -x "/opt/php54/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.4
          elif [ -x "/opt/php53/bin/php" ] ; then
            _LOC_PHP_FPM_VERSION=5.3
          fi
        fi
        if [ "$_LOC_PHP_FPM_VERSION" != "$_PHP_FPM_VERSION" ] || [ "$_FORCE_FPM_SETUP" = "YES" ] ; then
          _NEW_FPM_SETUP=YES
          _FORCE_FPM_SETUP=NO
        fi
        if [ ! -z "$_LOC_PHP_FPM_VERSION" ] && [ "$_NEW_FPM_SETUP" = "YES" ] ; then
          _NEW_FPM_SETUP=NO
          tune_fpm_workers
          _LIM_FPM="$_L_PHP_FPM_WORKERS"
          if [ "$_LIM_FPM" -lt "24" ] ; then
            if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] ; then
              _LIM_FPM=24
            fi
          fi
          if [ "$_CLIENT_OPTION" = "MICRO" ] ; then
            _LIM_FPM=2
            _PHP_FPM_WORKERS=4
          fi
          let "_CHILD_MAX_FPM = (($_LIM_FPM * 2))"
          if [ "$_PHP_FPM_WORKERS" = "AUTO" ] ; then
            _DO_NOTHING=YES
          else
            _PHP_FPM_WORKERS=${_PHP_FPM_WORKERS//[^0-9]/}
            if [ ! -z "$_PHP_FPM_WORKERS" ] && [ "$_PHP_FPM_WORKERS" -gt "0" ] ; then
              _CHILD_MAX_FPM="$_PHP_FPM_WORKERS"
            fi
          fi
          sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=$_LOC_PHP_FPM_VERSION/g" /root/.${_OWN}.octopus.cnf &> /dev/null
          echo $_LOC_PHP_FPM_VERSION > /data/disk/${_OWN}/log/fpm.txt
          echo $_LOC_PHP_FPM_VERSION > /data/disk/${_OWN}/static/control/fpm.info
          chown ${_OWN}.ftp:users /data/disk/${_OWN}/static/control/fpm.info
          _PHP_OLD_SV=${_PHP_FPM_VERSION//[^0-9]/}
          _PHP_SV=${_LOC_PHP_FPM_VERSION//[^0-9]/}
          if [ -z "$_PHP_SV" ] ; then
            _PHP_SV=55
          fi
          ### create or update special system user if needed
          if [ -e "/home/${_OWN}.web/.drush/php.ini" ] ; then
            _OLD_PHP_IN_USE=`grep "/lib/php" /home/${_OWN}.web/.drush/php.ini`
            _PHP_V="56 55 54 53"
            for e in $_PHP_V; do
              if [[ "$_OLD_PHP_IN_USE" =~ "php${e}" ]] ; then
                if [ "${e}" != "${_PHP_SV}" ]] || [ ! -e "/home/${_OWN}.web/.drush/.ctrl.php${_PHP_SV}.txt" ] ; then
                  echo _OLD_PHP_IN_USE is $_OLD_PHP_IN_USE for ${_OWN}.web update
                  echo _NEW_PHP_TO_USE is $_PHP_SV for ${_OWN}.web update
                  update_web_user "$_PHP_SV"
                fi
              fi
            done
          else
            echo _NEW_PHP_TO_USE is $_PHP_SV for ${_OWN}.web create
            create_web_user "$_PHP_SV"
          fi
          ### create or update special system user if needed
          rm -f /opt/php*/etc/pool.d/${_OWN}.conf
          cp -af /var/xdrago/conf/fpm-pool-foo.conf /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf
          sed -i "s/.ftp/.web/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          sed -i "s/\/data\/disk\/foo\/.tmp/\/home\/foo.web\/.tmp/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          sed -i "s/foo/${_OWN}/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          if [ ! -z "$_PHP_FPM_DENY" ] ; then
            sed -i "s/passthru,/$_PHP_FPM_DENY,/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          else
            if [[ "$_HOST_TEST" =~ ".host8." ]] || [ "$_VMFAMILY" = "VS" ] || [ -e "/root/.host8.cnf" ] ; then
              _DO_NOTHING=YES
            else
              sed -i "s/passthru,//g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
            fi
          fi
          if [ "$_PHP_FPM_TIMEOUT" = "AUTO" ] || [ -z "$_PHP_FPM_TIMEOUT" ] ; then
            _PHP_FPM_TIMEOUT=180
          fi
          _PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT//[^0-9]/}
          if [ "$_PHP_FPM_TIMEOUT" -lt "60" ] ; then
            _PHP_FPM_TIMEOUT=60
          fi
          if [ "$_PHP_FPM_TIMEOUT" -gt "180" ] ; then
            _PHP_FPM_TIMEOUT=180
          fi
          if [ ! -z "$_PHP_FPM_TIMEOUT" ] ; then
            _PHP_TO="${_PHP_FPM_TIMEOUT}s"
            sed -i "s/180s/$_PHP_TO/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
          fi
          if [ ! -z "$_CHILD_MAX_FPM" ] ; then
            sed -i "s/pm.max_children =.*/pm.max_children = $_CHILD_MAX_FPM/g" /opt/php${_PHP_SV}/etc/pool.d/${_OWN}.conf &> /dev/null
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
  fi
}
#
# Manage mirroring of drush aliases.
manage_site_drush_alias_mirror() {

  for Alias in `find /home/${_OWN}.ftp/.drush/*.alias.drushrc.php -maxdepth 1 -type f | sort`
  do
    AliasFile=`echo "$Alias" | cut -d'/' -f5 | awk '{ print $1}'`
    if [ ! -e "$User/.drush/${AliasFile}" ] ; then
      rm -f /home/${_OWN}.ftp/.drush/${AliasFile}
    fi
  done

  rm -f /home/${_OWN}.ftp/.drush/hm.alias.drushrc.php

  for Alias in `find $User/.drush/*.alias.drushrc.php -maxdepth 1 -type f | sort`
  do
    AliasName=`echo "$Alias" | cut -d'/' -f6 | awk '{ print $1}'`
    AliasName=`echo "$AliasName" | sed "s/.alias.drushrc.php//g" | awk '{ print $1}'`
    if [ "$AliasName" = "hm" ] || [[ "$AliasName" =~ (^)"platform_" ]] || [[ "$AliasName" =~ (^)"server_" ]] || [[ "$AliasName" =~ (^)"hostmaster" ]] ; then
      _IS_SITE=NO
    else
      _THIS_SITE_NAME="$AliasName"
      echo _THIS_SITE_NAME is $_THIS_SITE_NAME
      if [[ "$_THIS_SITE_NAME" =~ ".restore"($) ]] ; then
        _IS_SITE=NO
        rm -f $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
      else
        _THIS_SITE_FDIR=`cat $Alias | grep "site_path'" | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`
        if [ -d "$_THIS_SITE_FDIR" ] ; then
          echo _THIS_SITE_FDIR is $_THIS_SITE_FDIR
          if [ ! -e "/home/${_OWN}.ftp/.drush/${_THIS_SITE_NAME}.alias.drushrc.php" ] ; then
            cp -af $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php /home/${_OWN}.ftp/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
            chmod 440 /home/${_OWN}.ftp/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
          else
            _DIFF_TEST=$(diff /home/${_OWN}.ftp/.drush/${_THIS_SITE_NAME}.alias.drushrc.php  $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php)
            if [ ! -z "$_DIFF_TEST" ] ; then
              cp -af $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php /home/${_OWN}.ftp/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
              chmod 440 /home/${_OWN}.ftp/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
            fi
          fi
        else
          rm -f /home/${_OWN}.ftp/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
          echo ZOMBIE $_THIS_SITE_FDIR IN $User/.drush/${_THIS_SITE_NAME}.alias.drushrc.php
        fi
      fi
    fi
  done
}
#
# Manage Primary Users.
manage_own() {
for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`
do
  if [ -e "$User/config/server_master/nginx/vhost.d" ] && [ -e "$User/log/fpm.txt" ] && [ ! -e "$User/log/CANCELLED" ] ; then
    _OWN=""
    _OWN=`echo $User | cut -d'/' -f4 | awk '{ print $1}'`
    echo "_OWN is == $_OWN == at manage_own"
    rm -f /data/disk/${_OWN}/*.php* &> /dev/null
    chmod 0440 /data/disk/${_OWN}/.drush/*.php &> /dev/null
    chmod 0400 /data/disk/${_OWN}/.drush/drushrc.php &> /dev/null
    chmod 0400 /data/disk/${_OWN}/.drush/hm.alias.drushrc.php &> /dev/null
    chmod 0400 /data/disk/${_OWN}/.drush/hostmaster*.php &> /dev/null
    chmod 0400 /data/disk/${_OWN}/.drush/platform_*.php &> /dev/null
    chmod 0400 /data/disk/${_OWN}/.drush/server_*.php &> /dev/null
    chmod 0710 /data/disk/${_OWN}/.drush &> /dev/null
    find /data/disk/${_OWN}/config/server_master -type d -exec chmod 0700 {} \; &> /dev/null
    find /data/disk/${_OWN}/config/server_master -type f -exec chmod 0600 {} \; &> /dev/null
    if [ ! -e "/data/disk/${_OWN}/.tmp/.ctrl.240dev.txt" ] ; then
      rm -f -r /data/disk/${_OWN}/.drush/cache
      rm -f -r /data/disk/${_OWN}/.tmp
      mkdir -p /data/disk/${_OWN}/.tmp
      chown ${_OWN}:www-data /data/disk/${_OWN}/.tmp &> /dev/null
      chmod 02775 /data/disk/${_OWN}/.tmp &> /dev/null
      echo OK > /data/disk/${_OWN}/.tmp/.ctrl.240dev.txt
    fi
    if [ ! -e "/data/disk/${_OWN}/static/control/.ctrl.240dev.txt" ] ; then
      mkdir -p /data/disk/${_OWN}/static/control
      chmod 755 /data/disk/${_OWN}/static/control
      if [ -e "/var/xdrago/conf/control-readme.txt" ] ; then
        cp -af /var/xdrago/conf/control-readme.txt /data/disk/${_OWN}/static/control/README.txt &> /dev/null
        chmod 0644 /data/disk/${_OWN}/static/control/README.txt
      fi
      chown -R ${_OWN}.ftp:$_USRG /data/disk/${_OWN}/static/control &> /dev/null
      echo OK > /data/disk/${_OWN}/static/control/.ctrl.240dev.txt
    fi
    if [ -e "/root/.${_OWN}.octopus.cnf" ] ; then
      source /root/.${_OWN}.octopus.cnf
    fi
    switch_php
    switch_newrelic
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
        manage_site_drush_alias_mirror
        manage_sec
        if [ -e "/home/${_OWN}.ftp/users" ] ; then
          chown -R ${_OWN}.ftp:users /home/${_OWN}.ftp/users
          chmod 700 /home/${_OWN}.ftp/users
          chmod 600 /home/${_OWN}.ftp/users/*
        fi
        if [ ! -L "/home/${_OWN}.ftp/static" ] ; then
          rm -f /home/${_OWN}.ftp/{backups,clients,static}
          ln -sf /data/disk/${_OWN}/backups /home/${_OWN}.ftp/backups
          ln -sf /data/disk/${_OWN}/clients /home/${_OWN}.ftp/clients
          ln -sf /data/disk/${_OWN}/static  /home/${_OWN}.ftp/static
        fi
        if [ ! -e "/home/${_OWN}.ftp/.tmp/.ctrl.240dev.txt" ] ; then
          rm -f -r /home/${_OWN}.ftp/.drush/cache
          rm -f -r /home/${_OWN}.ftp/.tmp
          mkdir -p /home/${_OWN}.ftp/.tmp
          chown ${_OWN}.ftp:users /home/${_OWN}.ftp/.tmp &> /dev/null
          chmod 700 /home/${_OWN}.ftp/.tmp &> /dev/null
          echo OK > /home/${_OWN}.ftp/.tmp/.ctrl.240dev.txt
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

###-------------SYSTEM-----------------###

_NOW=`date +%y%m%d-%H%M`
mkdir -p /var/backups/ltd/{conf,log,old}
mkdir -p /var/backups/zombie/deleted
_THIS_LTD_CONF="/var/backups/ltd/conf/lshell.conf.$_NOW"
if [ -e "/var/run/manage_rvm_users.pid" ] || [ -e "/var/run/manage_ltd_users.pid" ] || [ -e "/var/run/boa_run.pid" ] || [ -e "/var/run/boa_wait.pid" ] ; then
  touch /var/xdrago/log/wait-manage-ltd-users
  echo Another BOA task is running, we have to wait
  exit 0
elif [ ! -e "/var/xdrago/conf/lshell.conf" ] ; then
  echo Missing /var/xdrago/conf/lshell.conf template
  exit 0
else
  touch /var/run/manage_ltd_users.pid
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
  kill_zombies >/var/backups/ltd/log/zombies-$_NOW.log 2>&1
  manage_own >/var/backups/ltd/log/users-$_NOW.log 2>&1
  if [ -e "$_THIS_LTD_CONF" ] ; then
    _DIFF_TEST=$(diff $_THIS_LTD_CONF /etc/lshell.conf)
    if [ ! -z "$_DIFF_TEST" ] ; then
      cp -af /etc/lshell.conf /var/backups/ltd/old/lshell.conf-before-$_NOW
      cp -af $_THIS_LTD_CONF /etc/lshell.conf
    else
      rm -f $_THIS_LTD_CONF
    fi
  fi
  if [ -L "/bin/sh" ] ; then
    _WEB_SH=`readlink -n /bin/sh`
    _WEB_SH=`echo -n $_WEB_SH | tr -d "\n"`
    if [ -x "/bin/websh" ] ; then
      if [ "$_WEB_SH" != "/bin/websh" ] && [ ! -e "/root/.dbhd.clstr.cnf" ] ; then
        rm -f /bin/sh
        ln -s /bin/websh /bin/sh
      fi
    else
      if [ -x "/bin/dash" ] ; then
        if [ "$_WEB_SH" != "/bin/dash" ] ; then
          rm -f /bin/sh
          ln -s /bin/dash /bin/sh
        fi
      else
        if [ "$_WEB_SH" != "/bin/bash" ] ; then
          rm -f /bin/sh
          ln -s /bin/bash /bin/sh
        fi
      fi
      curl -s -A iCab "http://files.aegir.cc/versions/master/aegir/helpers/websh.sh.txt" -o /bin/websh
      chmod 755 /bin/websh
    fi
  fi
  rm -f $_TMP/*.txt
  if [ ! -e "/root/.home.no.wildcard.chmod.cnf" ] ; then
    chmod 700 /home/* &> /dev/null
  fi
  chmod 0600 /var/log/lsh/*
  chmod 0440 /var/aegir/.drush/*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/drushrc.php &> /dev/null
  chmod 0400 /var/aegir/.drush/hm.alias.drushrc.php &> /dev/null
  chmod 0400 /var/aegir/.drush/hostmaster*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/platform_*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/server_*.php &> /dev/null
  chmod 0710 /var/aegir/.drush &> /dev/null
  find /var/aegir/config/server_master -type d -exec chmod 0700 {} \; &> /dev/null
  find /var/aegir/config/server_master -type f -exec chmod 0600 {} \; &> /dev/null
  if [ -e "/var/scout" ] ; then
    _SCOUT_CRON_OFF=$(grep "OFFscoutOFF" /etc/crontab 2>&1)
    if [[ "$_SCOUT_CRON_OFF" =~ "OFFscoutOFF" ]] ; then
      sleep 5
      sed -i "s/OFFscoutOFF/scout/g" /etc/crontab &> /dev/null
    fi
  fi
  if [ -e "/var/backups/reports/up/barracuda" ] ; then
    if [ -e "/root/.mstr.clstr.cnf" ] || [ -e "/root/.wbhd.clstr.cnf" ] || [ -e "/root/.dbhd.clstr.cnf" ] ; then
      if [ -e "/var/spool/cron/crontabs/aegir" ] ; then
        sleep 180
        rm -f /var/spool/cron/crontabs/aegir
        service cron reload &> /dev/null
      fi
    fi
    if [ -e "/root/.mstr.clstr.cnf" ] || [ -e "/root/.wbhd.clstr.cnf" ] ; then
      if [ -e "/var/run/mysqld/mysqld.pid" ] && [ ! -e "/root/.dbhd.clstr.cnf" ] ; then
        service cron stop &> /dev/null
        sleep 180
        touch /root/.remote.db.cnf
        service mysql stop &> /dev/null
        sleep 5
        service cron start &> /dev/null
      fi
    fi
  fi
  sleep 60
  rm -f /var/run/manage_ltd_users.pid
  exit 0
fi
###EOF2015###
