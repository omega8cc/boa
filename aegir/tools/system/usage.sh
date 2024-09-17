#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

check_root() {
  if [ `whoami` = "root" ]; then
    ionice -c2 -n7 -p $$
    renice 19 -p $$
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.pause_heavy_tasks_maint.cnf" ]; then
  exit 0
fi

if [ $(pgrep -f usage.sh | grep -v "^$$" | wc -l) -gt 1 ]; then
  echo "Too many usage.sh running"
  exit 0
fi

###-------------SYSTEM-----------------###

_CHECK_HOST=$(uname -n 2>&1)
if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]]; then
    hostedSys=YES
  else
    hostedSys=NO
  fi
}

fix_clear_cache() {
  if [ -e "${Plr}/profiles/hostmaster" ]; then
    su -s /bin/bash - ${_THIS_U} -c "drush8 @hostmaster cache-clear all" &> /dev/null
    wait
  fi
}

check_account_exceptions() {
  _DEV_EXC=NO
  chckStringA="omega8.cc"
  chckStringB="omega8cc"
  chckStringC="mixomax"
  chckStringE="emaylx"
  case ${_CLIENT_EMAIL} in
    *"$chckStringA"*) _DEV_EXC=YES ;;
    *"$chckStringB"*) _DEV_EXC=YES ;;
    *"$chckStringC"*) _DEV_EXC=YES ;;
    *"$chckStringE"*) _DEV_EXC=YES ;;
    *)
    ;;
  esac
}

read_account_data() {
  _CLIENT_CORES=
  _EXTRA_ENGINE=
  _ENGINE_NR=
  _CLIENT_EMAIL=
  _CLIENT_OPTION=
  _DSK_CLU_LIMIT=1
  if [ -e "/data/disk/${_THIS_U}/log/email.txt" ]; then
    _CLIENT_EMAIL=$(cat /data/disk/${_THIS_U}/log/email.txt 2>&1)
    _CLIENT_EMAIL=$(echo -n ${_CLIENT_EMAIL} | tr -d "\n" 2>&1)
    check_account_exceptions
  fi
  if [ -e "/root/.debug.email.txt" ]; then
    _CLIENT_EMAIL="omega8cc@gmail.com"
  fi
  if [ -e "/data/disk/${_THIS_U}/log/cores.txt" ]; then
    _CLIENT_CORES=$(cat /data/disk/${_THIS_U}/log/cores.txt 2>&1)
    _CLIENT_CORES=$(echo -n ${_CLIENT_CORES} | tr -d "\n" 2>&1)
  fi
  if [ -e "/data/disk/${_THIS_U}/log/diskspace.txt" ]; then
    _DSK_CLU_LIMIT=$(cat /data/disk/${_THIS_U}/log/diskspace.txt 2>&1)
    _DSK_CLU_LIMIT=$(echo -n ${_DSK_CLU_LIMIT} | tr -d "\n" 2>&1)
  fi
  if [ "${_CLIENT_CORES}" -gt "1" ]; then
    _ENGINE_NR="Engines"
  else
    _ENGINE_NR="Engine"
  fi
  if [ -e "/data/disk/${_THIS_U}/log/option.txt" ]; then
    _CLIENT_OPTION=$(cat /data/disk/${_THIS_U}/log/option.txt 2>&1)
    _CLIENT_OPTION=$(echo -n ${_CLIENT_OPTION} | tr -d "\n" 2>&1)
  fi
  if [ -e "/data/disk/${_THIS_U}/log/extra.txt" ]; then
    mv -f /data/disk/${_THIS_U}/log/extra.txt /data/disk/${_THIS_U}/log/extra_edge.txt
  fi
  if [ -e "/data/disk/${_THIS_U}/log/extra_edge.txt" ]; then
    _EXTRA_ENGINE=$(cat /data/disk/${_THIS_U}/log/extra_edge.txt 2>&1)
    _EXTRA_ENGINE=$(echo -n ${_EXTRA_ENGINE} | tr -d "\n" 2>&1)
    _ENGINE_NR="${_ENGINE_NR} + ${_EXTRA_ENGINE} x EDGE"
  fi
  if [ -e "/data/disk/${_THIS_U}/log/extra_power.txt" ]; then
    _EXTRA_ENGINE=$(cat /data/disk/${_THIS_U}/log/extra_power.txt 2>&1)
    _EXTRA_ENGINE=$(echo -n ${_EXTRA_ENGINE} | tr -d "\n" 2>&1)
    _ENGINE_NR="${_ENGINE_NR} + ${_EXTRA_ENGINE} x POWER"
  fi
  if [ -e "/data/disk/${_THIS_U}/static/control/cli.info" ]; then
    _CLIENT_CLI=$(cat /data/disk/${_THIS_U}/static/control/cli.info 2>&1)
    _CLIENT_CLI=$(echo -n ${_CLIENT_CLI} | tr -d "\n" 2>&1)
  fi
  if [ -e "/data/disk/${_THIS_U}/static/control/fpm.info" ]; then
    _CLIENT_FPM=$(cat /data/disk/${_THIS_U}/static/control/fpm.info 2>&1)
    _CLIENT_FPM=$(echo -n ${_CLIENT_FPM} | tr -d "\n" 2>&1)
  fi
}

send_notice_php() {
  _MY_EMAIL="support@omega8.cc"
  _BCC_EMAIL="omega8cc@gmail.com"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "URGENT: Please switch your Aegir instance to PHP 8.1 [${_THIS_U}]" ${_CLIENT_EMAIL}
Hello,

Our monitoring detected that you are still using deprecated
and no longer supported PHP version: $1

We have provided a few years of extended support for
this PHP version, but now we can't extend it any further,
because your system has to be upgraded to newest Debian version,
which doesn't support many deprecated PHP versions.

The upgrade will happen in the first week of May, 2023,
and there are no exceptions possible to avoid it.

This means that all Aegir instances still running PHP $1
will stop working if not switched to one of currently
supported versions: 8.1, 8.2, 8.3

To switch PHP-FPM version on command line, please type:

  echo 8.1 > ~/static/control/fpm.info

You can find more details at: https://learn.omega8.cc/node/330

We are working hard to provide secure and fast hosting
for your Drupal sites, and we appreciate your efforts
to meet the requirements, which are an integral part
of the quality you can expect from Omega8.cc

--
This email has been sent by your Aegir system monitor

EOF
  fi
  echo "INFO: PHP notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
}

detect_deprecated_php() {
  _PHP_FPM_VERSION=
  if [ -e "${User}/static/control/fpm.info" ] \
    && [ ! -e "${User}/log/proxied.pid" ] \
    && [ ! -e "${User}/log/CANCELLED" ]; then
    _PHP_FPM_VERSION=$(cat ${User}/static/control/fpm.info 2>&1)
    _PHP_FPM_VERSION=$(echo -n ${_PHP_FPM_VERSION} | tr -d "\n" 2>&1)
    if [ "${_PHP_FPM_VERSION}" = "5.5" ] \
      || [ "${_PHP_FPM_VERSION}" = "5.4" ] \
      || [ "${_PHP_FPM_VERSION}" = "5.3" ] \
      || [ "${_PHP_FPM_VERSION}" = "5.2" ]; then
      echo Deprecated PHP-FPM ${_PHP_FPM_VERSION} detected in ${_THIS_U}
      read_account_data
      if [ "${_THIS_MODE}" = "verbose" ]; then
        send_notice_php ${_PHP_FPM_VERSION}
      fi
    fi
  fi
}

send_notice_core() {
  _MY_EMAIL="support@omega8.cc"
  _BCC_EMAIL="omega8cc@gmail.com"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "URGENT: Please migrate ${Dom} site to Pressflow (LTS)" ${_CLIENT_EMAIL}
Hello,

Our system detected that you are using vanilla Drupal core
for site ${Dom}.

The platform root directory for this site is:
${Plr}

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
This email has been sent by your Aegir platform core monitor.

EOF
  fi
  echo "INFO: Pressflow notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
}

detect_vanilla_core() {
  if [ ! -e "${Plr}/core" ]; then
    if [ -e "${Plr}/web.config" ]; then
      _DO_NOTHING=YES
    else
      if [ -e "${Plr}/modules/watchdog" ]; then
        if [ ! -e "/boot/grub/grub.cfg" ] \
          && [ ! -e "/boot/grub/menu.lst" ] \
          && [[ "${Plr}" =~ "static" ]] \
          && [ ! -e "${Plr}/modules/cookie_cache_bypass" ]; then
          if_hosted_sys
          if [ "${hostedSys}" = "YES" ]; then
            echo Vanilla Drupal 5.x Platform detected in ${Plr}
            read_account_data
            if [ "${_THIS_MODE}" = "verbose" ]; then
              send_notice_core
            fi
          fi
        fi
      else
        if [ ! -e "${Plr}/modules/path_alias_cache" ] \
          && [ -e "${Plr}/modules/user" ] \
          && [[ "${Plr}" =~ "static" ]]; then
          echo Vanilla Drupal 6.x Platform detected in ${Plr}
          if [ ! -e "/boot/grub/grub.cfg" ] \
            && [ ! -e "/boot/grub/menu.lst" ]; then
            if_hosted_sys
            if [ "${hostedSys}" = "YES" ]; then
              read_account_data
              if [ "${_THIS_MODE}" = "verbose" ]; then
                send_notice_core
              fi
            fi
          fi
        fi
      fi
    fi
  fi
}

count() {
  for Site in `find ${User}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    #echo Counting Site $Site
    Dom=$(echo $Site | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    #echo "${_THIS_U},${Dom},vhost-exists"
    _DEV_URL=NO
    searchStringB=".dev."
    searchStringC=".devel."
    searchStringD=".temp."
    searchStringE=".tmp."
    searchStringF=".temporary."
    searchStringG=".test."
    searchStringH=".testing."
    searchStringI=".stage."
    searchStringJ=".staging."
    case ${Dom} in
      *"$searchStringB"*) _DEV_URL=YES ;;
      *"$searchStringC"*) _DEV_URL=YES ;;
      *"$searchStringD"*) _DEV_URL=YES ;;
      *"$searchStringE"*) _DEV_URL=YES ;;
      *"$searchStringF"*) _DEV_URL=YES ;;
      *"$searchStringG"*) _DEV_URL=YES ;;
      *"$searchStringH"*) _DEV_URL=YES ;;
      *"$searchStringI"*) _DEV_URL=YES ;;
      *"$searchStringJ"*) _DEV_URL=YES ;;
      *)
      ;;
    esac
    if [ -e "${User}/.drush/${Dom}.alias.drushrc.php" ]; then
      #echo "${_THIS_U},${Dom},drushrc-exists"
      Dir=$(cat ${User}/.drush/${Dom}.alias.drushrc.php \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      Plr=$(cat ${User}/.drush/${Dom}.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      detect_vanilla_core
      fix_clear_cache
      #echo Dir is ${Dir}
      if [ -e "${Dir}/drushrc.php" ] \
        && [ -e "${Dir}/files" ] \
        && [ -e "${Dir}/private" ] \
        && [ ! -e "${Plr}/profiles/hostmaster" ]; then
        if [ ! -e "${Dir}/modules" ]; then
          mkdir ${Dir}/modules
        fi
        #echo "${_THIS_U},${Dom},sitedir-exists"
        Dat=$(cat ${Dir}/drushrc.php \
          | grep "options\['db_name'\] = " \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,';]//g" 2>&1)
        #echo Dat is ${Dat}
        if [ ! -z "${Dat}" ] && [ -e "${Dir}" ]; then
          if [ -L "${Dir}/files" ] || [ -L "${Dir}/private" ]; then
            DirSize=$(du -L -s ${Dir} 2>&1)
          else
            DirSize=$(du -s ${Dir} 2>&1)
          fi
          DirSize=$(echo "${DirSize}" \
            | cut -d'/' -f1 \
            | awk '{ print $1}' \
            | sed "s/[\/\s+]//g" 2>&1)
          SumDir=$(( SumDir + DirSize ))
          echo "${_THIS_U},${Dom},DirSize:${DirSize}"
        fi
        if [ ! -z "${Dat}" ]; then
          if [ -e "/root/.du.sql" ]; then
            DatSize=$(grep "/var/lib/mysql/${Dat}$" /root/.du.sql 2>&1)
          elif [ -e "/root/.du.local.sql" ]; then
            DatSize=$(grep "/var/lib/mysql/${Dat}$" /root/.du.local.sql 2>&1)
          elif [ -e "/var/lib/mysql/${Dat}" ]; then
            DatSize=$(du -s /var/lib/mysql/${Dat} 2>&1)
          fi
          DatSize=$(echo "${DatSize}" \
            | cut -d'/' -f1 \
            | awk '{ print $1}' \
            | sed "s/[\/\s+]//g" 2>&1)
          if [ "${_DEV_URL}" = "YES" ]; then
            SkipDt=$(( SkipDt + DatSize ))
            echo "${_THIS_U},${Dom},DatSize:${DatSize}:${Dat},skip"
          else
            SumDat=$(( SumDat + DatSize ))
            echo "${_THIS_U},${Dom},DatSize:${DatSize}:${Dat}"
          fi
        else
          echo "Database ${Dat} for ${Dom} does not exist"
        fi
      fi
    fi
  done
}

send_notice_sql() {
  _MODE=$1
  if [ "${_MODE}" = "DEV" ]; then
    _SQL_LIM=${_SQL_DEV_LIMIT}
    _SQL_NOW=${SkipDtH}
  else
    _SQL_LIM=${_SQL_MIN_LIMIT}
    _SQL_NOW=${SumDatH}
  fi
  _MY_EMAIL="billing@omega8.cc"
  _BCC_EMAIL="omega8cc@gmail.com"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "NOTICE: Your ${_MODE} DB Usage on [${_THIS_U}] is too high: ${_SQL_NOW} MB" ${_CLIENT_EMAIL}
Hello,

You are using more resources than allocated in your subscription.
You have currently ${_CLIENT_CORES} Aegir ${_CLIENT_OPTION} ${_ENGINE_NR}.

Your allowed databases space for ${_MODE} sites is ${_SQL_LIM} MB,
but you are currently using ${_SQL_NOW} MB of databases space.

Please reduce your usage by deleting no longer used sites, or purchase
enough Aegir Engines to cover your current usage.

You can purchase more Aegir Engines easily online:

  https://omega8.cc/pricing

Note that we do not count(*) any site identified as temporary dev/test,
by having in its main name a special keyword with two dots on both sides:

  .dev.
  .devel.
  .temp.
  .tmp.
  .temporary.
  .test.
  .testing.
  .stage.
  .staging.

For example, a site with main name: abc.test.foo.com is by default excluded
from your allocated resources limits (not counted for billing purposes),
as long as the total databases space used by such sites is no greater than
three times (3x) your limit for LIVE sites listed on our order pages.

However, if we discover that anyone is using this method to hide real
usage via listed keywords in the main site name and adding live domain(s)
as aliases, such account will be suspended without any warning.

--
This email has been sent by your Aegir resources usage daily monitor.

EOF
  fi
  echo "INFO: Notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
}

send_notice_disk() {
  _MY_EMAIL="billing@omega8.cc"
  _BCC_EMAIL="omega8cc@gmail.com"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "NOTICE: Your Disk Usage on [${_THIS_U}] is too high" ${_CLIENT_EMAIL}
Hello,

You are using more resources than allocated in your subscription.
You have currently ${_CLIENT_CORES} Aegir ${_CLIENT_OPTION} ${_ENGINE_NR}.

Your allowed disk space is ${_DSK_MIN_LIMIT} MB.
You are currently using ${HomSizH} MB of disk space.

Please reduce your usage by deleting old backups, files,
and no longer used sites, or purchase enough Aegir Engines
to cover your current usage.

You can purchase more Aegir Engines easily online:

  https://omega8.cc/buy

Note that unlike with database space limits, for files related disk space
we count all your sites, including also all dev/tmp sites, if they exist,
even if they are marked as disabled in your Aegir control panel.

--
This email has been sent by your Aegir resources usage daily monitor.

EOF
  fi
  echo "INFO: Notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
}


send_notice_gprd() {
  _MY_EMAIL="support@omega8.cc"
  _BCC_EMAIL="omega8cc@gmail.com"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "GDPR compliance for your Aegir account" ${_CLIENT_EMAIL}
Hello,

Yes, yet another GDPR email, but it's important that you read and understand
how this new law affects your hosting with us.

The General Data Protection Regulation (GDPR) is a new European privacy law
that goes into effect on May 25, 2018.

The GDPR will replace the EU Data Protection Directive, also known as
Directive 95/46/EC, and will apply a single data protection law
throughout the EU.

Data protection laws govern the way that businesses collect, use, and share
personal data about individuals. Among other things, they require businesses
to process an individual’s personal data fairly and lawfully, allow individuals
to exercise legal rights in respect of their personal data (for example,
to access, correct or delete their personal data), and ensure appropriate
security protections are put in place to protect the personal data they process.

We have taken steps to ensure that we will be compliant with the GDPR
by May 25, 2018.

Please read all details on our website at:

https://omega8.cc/gdpr
https://omega8.cc/gdpr-faq
https://omega8.cc/gdpr-dpa
https://omega8.cc/gdpr-portability

Please contact us if you have any questions: https://omega8.cc/contact

Thank you for your attention.

---
Omega8.cc

EOF
  fi
  echo "INFO: GDPR notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
}

check_limits() {
  _SQL_MIN_LIMIT=0
  _SQL_MAX_LIMIT=0
  _SQL_DEV_LIMIT=0
  _DSK_MIN_LIMIT=0
  _DSK_MAX_LIMIT=0
  _DSK_CLU_LIMIT=1
  read_account_data
  if [ "${_CLIENT_OPTION}" = "CLUSTER" ]; then
    if [ -z "${_DSK_CLU_LIMIT}" ]; then
      _DSK_CLU_LIMIT=1
    fi
    _SQL_MIN_LIMIT=51200
    _DSK_MIN_LIMIT=102400
    _DSK_MAX_LIMIT=107520
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 2048 ))
    _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT *= _DSK_CLU_LIMIT ))
    _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT *= _DSK_CLU_LIMIT ))
  elif [ "${_CLIENT_OPTION}" = "LITE" ]; then
    if [ -z "${_DSK_CLU_LIMIT}" ]; then
      _DSK_CLU_LIMIT=1
    fi
    _SQL_MIN_LIMIT=5120
    _DSK_MIN_LIMIT=51200
    _DSK_MAX_LIMIT=53760
    _SQL_DEV_EXTRA=3
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 1024 ))
    _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT *= _DSK_CLU_LIMIT ))
    _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT *= _DSK_CLU_LIMIT ))
  elif [ "${_CLIENT_OPTION}" = "PHANTOM" ]; then
    if [ -z "${_DSK_CLU_LIMIT}" ]; then
      _DSK_CLU_LIMIT=1
    fi
    _SQL_MIN_LIMIT=10240
    _DSK_MIN_LIMIT=102400
    _DSK_MAX_LIMIT=107520
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 2048 ))
    _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT *= _DSK_CLU_LIMIT ))
    _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT *= _DSK_CLU_LIMIT ))
  elif [ "${_CLIENT_OPTION}" = "POWER" ]; then
    _SQL_MIN_LIMIT=5120
    _DSK_MIN_LIMIT=51200
    _SQL_DEV_EXTRA=3
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 1024 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 2560 ))
  elif [ "${_CLIENT_OPTION}" = "EDGE" ] \
    || [ "${_CLIENT_OPTION}" = "SSD" ] \
    || [ "${_CLIENT_OPTION}" = "CLASSIC" ]; then
    _CLIENT_OPTION=EDGE
    _SQL_MIN_LIMIT=1024
    _DSK_MIN_LIMIT=15360
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 512 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 1280 ))
  elif [ "${_CLIENT_OPTION}" = "MINI" ]; then
    _SQL_MIN_LIMIT=1024
    _DSK_MIN_LIMIT=15360
    _SQL_DEV_EXTRA=1
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 512 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 1280 ))
  elif [ "${_CLIENT_OPTION}" = "MICRO" ]; then
    _SQL_MIN_LIMIT=512
    _DSK_MIN_LIMIT=5120
    _SQL_DEV_EXTRA=1
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 256 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 640 ))
  else
    _SQL_MIN_LIMIT=512
    _DSK_MIN_LIMIT=7680
    _SQL_DEV_EXTRA=1
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 256 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 640 ))
  fi
  _SQL_MIN_LIMIT=$(( _SQL_MIN_LIMIT *= _CLIENT_CORES ))
  _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT *= _CLIENT_CORES ))
  _SQL_MAX_LIMIT=$(( _SQL_MAX_LIMIT *= _CLIENT_CORES ))
  _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT *= _CLIENT_CORES ))
  _SQL_DEV_LIMIT=${_SQL_MIN_LIMIT}
  _SQL_DEV_LIMIT=$(( _SQL_DEV_LIMIT *= _CLIENT_CORES ))
  _SQL_DEV_LIMIT=$(( _SQL_DEV_LIMIT *= _SQL_DEV_EXTRA ))
  if [ ! -z "${_EXTRA_ENGINE}" ]; then
    if [ -e "/data/disk/${_THIS_U}/log/extra_edge.txt" ]; then
      _SQL_ADD_LIMIT=1024
      _DSK_ADD_LIMIT=15360
    elif [ -e "/data/disk/${_THIS_U}/log/extra_power.txt" ]; then
      _SQL_ADD_LIMIT=5120
      _DSK_ADD_LIMIT=51200
    fi
    _SQL_ADD_LIMIT=$(( _SQL_ADD_LIMIT *= _EXTRA_ENGINE ))
    _DSK_ADD_LIMIT=$(( _DSK_ADD_LIMIT *= _EXTRA_ENGINE ))
    _SQL_MIN_LIMIT=$(( _SQL_MIN_LIMIT + _SQL_ADD_LIMIT ))
    _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT + _DSK_ADD_LIMIT ))
    _SQL_MAX_LIMIT=$(( _SQL_MAX_LIMIT + _SQL_ADD_LIMIT ))
    _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT + _DSK_ADD_LIMIT ))
    echo _EXTRA_ENGINE is ${_EXTRA_ENGINE}
  fi
  echo _CLIENT_CORES is ${_CLIENT_CORES}
  echo _SQL_MIN_LIMIT is ${_SQL_MIN_LIMIT}
  echo _SQL_MAX_LIMIT is ${_SQL_MAX_LIMIT}
  echo _SQL_DEV_LIMIT is ${_SQL_DEV_LIMIT}
  echo _DSK_MIN_LIMIT is ${_DSK_MIN_LIMIT}
  echo _DSK_MAX_LIMIT is ${_DSK_MAX_LIMIT}
  if [ "${SumDatH}" -gt "${_SQL_MAX_LIMIT}" ]; then
    if [ ! -e "${User}/log/CANCELLED" ] \
      && [ ! -e "${User}/log/proxied.pid" ]; then
      if [ "${_THIS_MODE}" = "verbose" ]; then
        send_notice_sql "LIVE"
      fi
    fi
    echo SQL Usage for ${_THIS_U} above limits
  elif [ "${SkipDtH}" -gt "${_SQL_DEV_LIMIT}" ]; then
    if [ ! -e "${User}/log/CANCELLED" ] \
      && [ ! -e "${User}/log/proxied.pid" ]; then
      if [ "${_THIS_MODE}" = "verbose" ]; then
        send_notice_sql "DEV"
      fi
    fi
    echo SQL Usage for ${_THIS_U} above limits
  else
    echo SQL Usage for ${_THIS_U} below limits
  fi
  if [ "${HomSizH}" -gt "${_DSK_MAX_LIMIT}" ]; then
    if [ ! -e "${User}/log/CANCELLED" ] \
      && [ ! -e "${User}/log/proxied.pid" ]; then
      if [ "${_THIS_MODE}" = "verbose" ]; then
        send_notice_disk
      fi
    fi
    echo Disk Usage for ${_THIS_U} above limits
  else
    echo Disk Usage for ${_THIS_U} below limits
  fi
  if [ ! -e "${User}/log/GDPRsent.log" ]; then
    if [ ! -e "${User}/log/CANCELLED" ] \
      && [ ! -e "${User}/log/proxied.pid" ]; then
      if [ "${_THIS_MODE}" = "verbose" ]; then
        send_notice_gprd
        touch ${User}/log/GDPRsent.log
        echo GDPR info for ${_THIS_U} sent
      fi
    fi
  fi
}

count_cpu() {
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt "0" ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ]; then
    _CPU_NR=1
  fi
}

load_control() {
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  export _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  : "${_CPU_MAX_RATIO:=6}"
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
}

sub_count_usr_home() {
  if [ -e "$1" ]; then
    HqmSiz=$(du -s $1 2>&1)
    HqmSiz=$(echo "${HqmSiz}" \
      | cut -d'/' -f1 \
      | awk '{ print $1}' \
      | sed "s/[\/\s+]//g" 2>&1)
    HxmSiz=$(( HxmSiz + HqmSiz ))
    ### echo $1 disk usage is $HqmSiz
    ### echo HxmSiz total is $HxmSiz
  fi
}

action() {
  for User in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    count_cpu
    load_control
    if [ -e "${User}/config/server_master/nginx/vhost.d" ]; then
      if [ "${_O_LOAD}" -lt "${_O_LOAD_MAX}" ]; then
        SumDir=0
        SumDat=0
        SkipDt=0
        HomSiz=0
        HxmSiz=0
        HqmSiz=0
        _THIS_U=$(echo ${User} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _THIS_HM_SITE=$(cat ${User}/.drush/hostmaster.alias.drushrc.php \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _THIS_HM_PLR=$(cat ${User}/.drush/hostmaster.alias.drushrc.php \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        echo load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}
        if [ ! -e "${User}/log/skip-force-cleanup.txt" ]; then
          cd ${User}
          echo "Remove various tmp/dot files breaking du command"
          find . -name ".DS_Store" -type f | xargs rm -rf &> /dev/null
          find . -name "*~" -type f | xargs rm -rf &> /dev/null
          find . -name "*#" -type f | xargs rm -rf &> /dev/null
          find . -name ".#*" -type f | xargs rm -rf &> /dev/null
          find . -name "*--" -type f | xargs rm -rf &> /dev/null
          find . -name "._*" -type f | xargs rm -rf &> /dev/null
          find . -name "*~" -type l | xargs rm -rf &> /dev/null
          find . -name "*#" -type l | xargs rm -rf &> /dev/null
          find . -name ".#*" -type l | xargs rm -rf &> /dev/null
          find . -name "*--" -type l | xargs rm -rf &> /dev/null
          find . -name "._*" -type l | xargs rm -rf &> /dev/null
        fi
        echo Counting User ${User}
        _DOW=$(date +%u 2>&1)
        _DOW=${_DOW//[^1-7]/}
        if [ "${_DOW}" = "2" ]; then
          detect_deprecated_php
        fi
        count
        if [ -d "/home/${_THIS_U}.ftp" ]; then
          for uH in `find /home/${_THIS_U}.* -maxdepth 0 -mindepth 0 | sort`; do
            if [ -d "${uH}" ]; then
              sub_count_usr_home ${uH}
            fi
          done
          for uR in `find /var/solr7/data/oct.${_THIS_U}.* -maxdepth 0 -mindepth 0 | sort`; do
            if [ -d "${uR}" ]; then
              sub_count_usr_home ${uR}
            fi
          done
          for uO in `find /opt/solr4/${_THIS_U}.* -maxdepth 0 -mindepth 0 | sort`; do
            if [ -d "${uO}" ]; then
              sub_count_usr_home ${uO}
            fi
          done
        fi
        if [ -L "${User}" ]; then
          HomSiz=$(du -D -s ${User} 2>&1)
        else
          HomSiz=$(du -s ${User} 2>&1)
        fi
        HomSiz=$(echo "${HomSiz}" \
          | cut -d'/' -f1 \
          | awk '{ print $1}' \
          | sed "s/[\/\s+]//g" 2>&1)
        HomSiz=$(( HomSiz + HxmSiz ))
        HomSizH=$(echo "scale=0; ${HomSiz}/1024" | bc 2>&1)
        SumDatH=$(echo "scale=0; ${SumDat}/1024" | bc 2>&1)
        SkipDtH=$(echo "scale=0; ${SkipDt}/1024" | bc 2>&1)
        SumDirH=$(echo "scale=0; ${SumDir}/1024" | bc 2>&1)
        echo HomSiz is ${HomSiz} or ${HomSizH} MB
        echo SumDir is ${SumDir} or ${SumDirH} MB
        echo SumDat is ${SumDat} or ${SumDatH} MB
        echo SkipDt is ${SkipDt} or ${SkipDtH} MB
        if_hosted_sys
        if [ "${hostedSys}" = "YES" ]; then
          check_limits
          if [ -e "${_THIS_HM_SITE}" ]; then
            su -s /bin/bash - ${_THIS_U} -c "drush8 @hostmaster \
              variable-set --always-set site_footer 'Usage on ${_DATE} \
              | Files <strong>${HomSizH}</strong> MB \
              | LiveDb <strong>${SumDatH}</strong> MB \
              | DevDb <strong>${SkipDtH}</strong> MB \
              | <strong>${_CLIENT_CORES}</strong> \
              ${_CLIENT_OPTION} ${_ENGINE_NR} \
              | CLI <strong>${_CLIENT_CLI}</strong> \
              | FPM <strong>${_CLIENT_FPM}</strong>'" &> /dev/null
            wait
            if [ ! -e "${User}/log/CANCELLED" ] \
              && [ "${_DEV_EXC}" = "NO" ] \
              && [ ! -e "${User}/log/proxied.pid" ]; then
              eMail=${_CLIENT_EMAIL//\\\@/\@}
              AegirUrl=$(cat ${User}/log/domain.txt 2>&1)
              if [ "${HomSizH}" -gt "${_DSK_MAX_LIMIT}" ]; then
                Files="!x!FilesAll"
              else
                Files="FilesAll"
              fi
              if [ "${SumDatH}" -gt "${_SQL_MAX_LIMIT}" ]; then
                DbsL="!x!DbsLive"
              else
                DbsL="DbsLive"
              fi
              if [ "${SkipDtH}" -gt "${_SQL_DEV_LIMIT}" ]; then
                DbsD="!x!DbsDev"
              else
                DbsD="DbsDev"
              fi
              if [ "${_THIS_MODE}" = "verbose" ] || [ -z "${_THIS_MODE}" ]; then
                _LOG_FILE="usage-latest-verbose.log"
              elif [ "${_THIS_MODE}" = "silent" ]; then
                _LOG_FILE="usage-latest-silent.log"
              fi
              echo "${AegirUrl},${Files}:${HomSizH},${DbsL}:${SumDatH},${DbsD}:${SkipDtH},${eMail},Subs:${_CLIENT_OPTION}:${_CLIENT_CORES},${_THIS_U}" >> /var/xdrago/log/usage/${_LOG_FILE}
            fi
            TmDir="${_THIS_HM_PLR}/profiles/hostmaster/themes/aegir/eldir"
            PgTpl="${TmDir}/page.tpl.php"
            EldirF="0001-Print-site_footer-if-defined.patch"
            TplPatch="/var/xdrago/conf/${EldirF}"
            if [ -e "${PgTpl}" ] && [ -e "${TplPatch}" ]; then
              _IS_SF=$(grep "site_footer" ${PgTpl} 2>&1)
              if [[ ! "${_IS_SF}" =~ "site_footer" ]]; then
                cd ${TmDir}
                patch -p1 < ${TplPatch} &> /dev/null
                cd
              fi
            fi
            su -s /bin/bash - ${_THIS_U} \
              -c "drush8 @hostmaster cache-clear all" &> /dev/null
            wait
          fi
        else
          if [ -e "${_THIS_HM_SITE}" ]; then
            su -s /bin/bash - ${_THIS_U} \
              -c "drush8 @hostmaster variable-set \
              --always-set site_footer ''" &> /dev/null
            wait
            su -s /bin/bash - ${_THIS_U} \
              -c "drush8 @hostmaster cache-clear all" &> /dev/null
            wait
          fi
        fi
        echo "Done for ${User}"
      else
        echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
        echo "...we have to wait..."
      fi
      echo
      echo
    fi
  done
}

###--------------------###
echo "INFO: Starting usage monitoring on `date`"
_NOW=$(date +%y%m%d-%H%M%S 2>&1)
_NOW=${_NOW//[^0-9-]/}
_DATE=$(date 2>&1)
_CHECK_HOST=$(uname -n 2>&1)
mkdir -p /var/xdrago/log/usage
if [ "${1}" = "verbose" ] || [ -z "${1}" ]; then
  _THIS_MODE="verbose"
  rm -f /var/xdrago/log/usage/usage-latest-verbose.log
elif [ "${1}" = "silent" ]; then
  _THIS_MODE="silent"
  rm -f /var/xdrago/log/usage/usage-latest-silent.log
fi
action >/var/xdrago/log/usage/usage-${_NOW}.log 2>&1
echo "INFO: Completing usage monitoring on `date`"
exit 0
###EOF2024###
