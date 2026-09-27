#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

[ -e "/etc/boa/.look.like.jenkins.cnf" ] && exit 0
grep -qiE "^[[:space:]]*(export[[:space:]]+)?_FORCE_CI_BOX=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null && exit 0
[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0
# A passive mirror must never run usage accounting: it writes the replicated
# /var/log/boa/usage tree, sweeps account trees, and issues hostmaster drush
# writes. Until now this was gated only in the caller (mysql_backup.sh).
[ -e "/root/.standby.cnf" ] && exit 0

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc "(^|(^| )[^ ]*bash )[^ ]*/${_SCRIPT//./\\.}( |$)")
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

###-------------SYSTEM-----------------###

_if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_hName}" =~ ".aegir.cc"($) ]]; then
    _hostedSys=YES
  else
    _hostedSys=NO
  fi
}

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

# An account's main login owns static/control and can write static/, and oN
# owns the rest of /data/disk/oN (log/, .drush/, config/, the site dirs):
# either can put a link or a FIFO at any name there, or swap a directory for
# a link.
# Run "$@" inside the real directory $1 only (every name below /data/disk a
# real directory), so ./name never leads out of the account.
_usage_in_real_dir() {
  local _d="${1}" _want
  shift
  _want="$(cd -P -- /data/disk 2> /dev/null && pwd -P)${_d#/data/disk}"
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_want}" ] && "$@" )
}
# ./$1 in the current (pinned) directory: never through a link, never
# blocked on a FIFO, at most 1 MiB; empty for anything else.
_usage_read_here() {
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
    bs=1048576 count=1 status=none 2> /dev/null
}
# $2 in the real directory $1, read as _usage_read_here reads it.
_usage_read_in() {
  _usage_in_real_dir "${1}" _usage_read_here "${2}"
}
# Run "$@" inside the site directory $1 named in an alias, as it resolves
# now: never a link itself, and strictly below this account's own real root
# (a link on the way that stays inside the account, such as a platform root
# the account reaches through its own link, is accepted), entered for real,
# so ./name stays in it whatever is swapped. Reads _usEr.
_usage_in_site_dir() {
  local _d="${1%/}" _rd _ra
  shift
  [ -n "${_d}" ] && [ ! -L "${_d}" ] && [ -d "${_d}" ] || return 1
  _rd=$(realpath -e -- "${_d}" 2> /dev/null) || return 1
  _ra=$(realpath -e -- "${_usEr}" 2> /dev/null) || return 1
  case "${_rd}/" in
    "${_ra}"/?*) ;;
    *) return 1 ;;
  esac
  ( cd -P -- "${_rd}" 2> /dev/null && [ "$(pwd -P)" = "${_rd}" ] && "$@" )
}
# The file $2 put as ./$1 in the current (pinned) directory (0644): a fresh
# name created exclusively, then renamed over the name, so a link or a FIFO
# put at the name is replaced, never followed or opened.
_usage_put_file_here() {
  local _t="./.${1}.put.$$.${RANDOM}"
  rm -f -- "${_t}"
  if ( umask 022
    dd if="${2}" of="${_t}" conv=excl status=none 2> /dev/null ) \
    && mv -f -T -- "${_t}" "./${1}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# The report directory ./usage in the current (pinned) static/: a link put
# at the name is removed, and only a real directory root owns will do.
_usage_log_dir_here() {
  [ -L ./usage ] && rm -f ./usage &> /dev/null
  [ -e ./usage ] || mkdir ./usage &> /dev/null
  [ -d ./usage ] && [ ! -L ./usage ] && [ -O ./usage ]
}
# The report is written to root's own temp file while the account is
# counted, and put in static/usage once, at the end, inside the real
# directory: a link or FIFO put at the report name, or static/usage swapped
# for a link mid-count, is never written through.
_usage_log_put() {
  if [ "${_uLogFil}" != "/dev/null" ]; then
    if [ -s "${_uLogFil}" ] \
      && ! _usage_in_real_dir "${_uLogDir}" \
        _usage_put_file_here "usage-${_NOW}.log" "${_uLogFil}"; then
      echo "INFO: Usage log dir ${_uLogDir} is no longer a real directory -- report not written"
    fi
    rm -f -- "${_uLogFil}"
  fi
  _uLogFil=/dev/null
}

# What counts besides the account's own tree, which du walks without
# following any link: each of static/files, backups and src only when it is
# a link resolving to the account's own store -- static/files to its real
# static/files or migratefs' <target>/files/<oN>/static/files, backups and
# src into that store (the backups mover's static/files/.backups) -- never
# wherever a link put anywhere else in the tree points. Sets _uFiles (the
# resolved store, empty when none counts) and _uStores (the du operands).
_usage_stores() {
  local _acctR _n _r
  _uFiles=
  _uStores=()
  _acctR=$(realpath -e -- "${_usEr}" 2> /dev/null) || return 0
  _r=$(realpath -e -- "${_usEr}/static/files" 2> /dev/null)
  case "${_r}" in
    "${_acctR}/static/files"|*"/files/${_THIS_U}/static/files") _uFiles="${_r}" ;;
  esac
  [ -n "${_uFiles}" ] || return 0
  [ -L "${_usEr}/static/files" ] && _uStores+=("${_uFiles}")
  for _n in backups src; do
    [ -L "${_usEr}/${_n}" ] || continue
    _r=$(realpath -e -- "${_usEr}/${_n}" 2> /dev/null) || continue
    case "${_r}/" in
      "${_uFiles}"/?*) _uStores+=("${_r}") ;;
    esac
  done
}

_fix_clear_cache() {
  if [ -e "${_Plr}/profiles/hostmaster" ]; then
    su -s /bin/bash - ${_THIS_U} -c "drush8 @hostmaster cache-clear all" &> /dev/null
    wait
  fi
}

# $1 as its words joined by single spaces, what echo -n $1 printed, but
# without expanding a glob or taking an option the account wrote there.
_usage_words() (
  set -f
  # shellcheck disable=SC2086
  set -- ${1}
  printf '%s' "$*"
)
# The addresses in $1 (words, as log/email.txt holds them) that have an
# e-mail address's form, joined by single spaces: they reach s-nail, run as
# root, as its recipients, where a word starting with a dash would be an
# option and one naming a file or a command a delivery to it. The form the
# octopus pass and the nightly take: a local part of letters, digits and
# . _ % + = ' - (a letter, a digit or _ first), '@' and a host name. An
# apostrophe or '=' in the local part is kept: both are literal in every
# expansion below. Text over 4 KiB holds no address list and gives nothing.
_usage_mail_list() (
  local _w _o="" _re _q="'"
  _re="^[A-Za-z0-9_][A-Za-z0-9._%+=${_q}-]*@[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$"
  [ "${#1}" -le 4096 ] || exit 0
  set -f
  # shellcheck disable=SC2086
  for _w in ${1//\\\@/\@}; do
    [[ "${_w}" =~ ${_re} ]] || continue
    _o="${_o}${_o:+ }${_w}"
  done
  printf '%s' "${_o}"
)

_check_account_exceptions() {
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

_read_account_data() {
  # log/ is oN's and static/control the tenant's: every name is read inside
  # the real directory, never through a link or blocked on a FIFO
  local _lg="/data/disk/${_THIS_U}/log"
  local _ct="/data/disk/${_THIS_U}/static/control"
  _CLIENT_CORES=
  _EXTRA_ENGINE=
  _ENGINE_NR=
  _CLIENT_EMAIL=
  _CLIENT_OPTION=
  _CLIENT_CLI=
  _CLIENT_FPM=
  _DEV_EXC=NO
  _DSK_CLU_LIMIT=1
  if [ -e "${_lg}/email.txt" ]; then
    # only words in an address's form (_usage_mail_list); a file with none
    # leaves the notices to the Bcc alone
    _CLIENT_EMAIL=$(_usage_mail_list "$(_usage_read_in "${_lg}" email.txt)")
    _check_account_exceptions
  fi
  if [ "${_DEBUG_EMAIL}" = "YES" ] \
    || [ -e "/etc/boa/.debug.email.txt" ]; then
    _CLIENT_EMAIL="inbox@boa.io"
  fi
  # the counts below go into shell arithmetic, which would evaluate
  # anything else as an expression: a whole number or nothing
  if [ -e "${_lg}/cores.txt" ]; then
    _CLIENT_CORES=$(_usage_read_in "${_lg}" cores.txt)
    _CLIENT_CORES=$(_usage_words "${_CLIENT_CORES}")
    [[ "${_CLIENT_CORES}" =~ ^[0-9]+$ ]] || _CLIENT_CORES=
  fi
  if [ -e "${_lg}/diskspace.txt" ]; then
    _DSK_CLU_LIMIT=$(_usage_read_in "${_lg}" diskspace.txt)
    _DSK_CLU_LIMIT=$(_usage_words "${_DSK_CLU_LIMIT}")
    [[ "${_DSK_CLU_LIMIT}" =~ ^[0-9]+$ ]] || _DSK_CLU_LIMIT=
  fi
  if [ "${_CLIENT_CORES:-0}" -gt 1 ]; then
    _ENGINE_NR="Engines"
  else
    _ENGINE_NR="Engine"
  fi
  if [ -e "${_lg}/option.txt" ]; then
    _CLIENT_OPTION=$(_usage_read_in "${_lg}" option.txt)
    _CLIENT_OPTION=$(_usage_words "${_CLIENT_OPTION}")
    # a plan name, one word: it goes into the report line, the panel footer
    # and the notices, and an unknown one takes the default limits
    [[ "${_CLIENT_OPTION}" =~ ^[A-Za-z0-9_-]+$ ]] || _CLIENT_OPTION=
  fi
  if [ -e "${_lg}/extra.txt" ]; then
    # renamed, never moved into a directory or link put at the new name
    _usage_in_real_dir "${_lg}" mv -f -T -- ./extra.txt ./extra_edge.txt
  fi
  if [ -e "${_lg}/extra_edge.txt" ]; then
    _EXTRA_ENGINE=$(_usage_read_in "${_lg}" extra_edge.txt)
    _EXTRA_ENGINE=$(_usage_words "${_EXTRA_ENGINE}")
    [[ "${_EXTRA_ENGINE}" =~ ^[0-9]+$ ]] || _EXTRA_ENGINE=
    _ENGINE_NR="${_ENGINE_NR} + ${_EXTRA_ENGINE} x EDGE"
  fi
  if [ -e "${_lg}/extra_aero.txt" ]; then
    _EXTRA_ENGINE=$(_usage_read_in "${_lg}" extra_aero.txt)
    _EXTRA_ENGINE=$(_usage_words "${_EXTRA_ENGINE}")
    [[ "${_EXTRA_ENGINE}" =~ ^[0-9]+$ ]] || _EXTRA_ENGINE=
    _ENGINE_NR="${_ENGINE_NR} + ${_EXTRA_ENGINE} x AERO"
  fi
  if [ -e "${_lg}/extra_power.txt" ]; then
    _EXTRA_ENGINE=$(_usage_read_in "${_lg}" extra_power.txt)
    _EXTRA_ENGINE=$(_usage_words "${_EXTRA_ENGINE}")
    [[ "${_EXTRA_ENGINE}" =~ ^[0-9]+$ ]] || _EXTRA_ENGINE=
    _ENGINE_NR="${_ENGINE_NR} + ${_EXTRA_ENGINE} x POWER"
  fi
  # kept to a version's characters (the first 64 bytes): these go into the
  # panel footer through a shell command line; reset above, so an account
  # without them never shows the previous account's
  _CLIENT_CLI=$(_usage_read_in "${_ct}" cli.info | head -c 64 | tr -cd '0-9.')
  _CLIENT_FPM=$(_usage_read_in "${_ct}" fpm.info | head -c 64 | tr -cd '0-9.')
}

_send_notice_php() {
  if [ "${_hostedSys}" != "YES" ]; then
    return 1  # Exit the function but continue the script
  fi
  _BCC_EMAIL="inbox@boa.io"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "URGENT: Please switch your Ægir instance to PHP 8.1 [${_THIS_U}]" ${_CLIENT_EMAIL}
Hello,

Our monitoring detected that you are still using deprecated
and no longer supported PHP version: $1

We have provided a few years of extended support for
this PHP version, but now we can't extend it any further,
because your system has to be upgraded to newest Debian version,
which doesn't support many deprecated PHP versions.

The upgrade will happen in the first week of May, 2023,
and there are no exceptions possible to avoid it.

This means that all Ægir instances still running PHP $1
will stop working if not switched to one of currently
supported versions: 8.1, 8.2, 8.3, 8.4, 8.5

To switch PHP-FPM version on command line, please type:

  echo 8.1 > ~/static/control/fpm.info

You can find more details at: https://docs.boa.io/using/tuning/php-version

We are working hard to provide secure and fast hosting
for your Drupal sites, and we appreciate your efforts
to meet the requirements, which are an integral part
of the quality you can expect from Omega8.cc

--
This email has been sent by your Ægir system monitor

EOF
  fi
  echo "INFO: PHP notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
}

_detect_deprecated_php() {
  _PHP_FPM_VERSION=
  if [ -e "${_usEr}/static/control/fpm.info" ] \
    && [ ! -e "${_usEr}/log/proxied.pid" ] \
    && [ ! -e "${_usEr}/log/proxy-failed.pid" ] \
    && [ ! -e "${_usEr}/log/CANCELLED" ]; then
    # read inside the real control directory, never through a link or
    # blocked on a FIFO the tenant put there, and kept to a version's
    # characters
    _PHP_FPM_VERSION=$(_usage_read_in "${_usEr}/static/control" fpm.info \
      | head -c 64 | tr -cd '0-9.')
    if [ "${_PHP_FPM_VERSION}" = "5.5" ] \
      || [ "${_PHP_FPM_VERSION}" = "5.4" ] \
      || [ "${_PHP_FPM_VERSION}" = "5.3" ] \
      || [ "${_PHP_FPM_VERSION}" = "5.2" ]; then
      echo Deprecated PHP-FPM ${_PHP_FPM_VERSION} detected in ${_THIS_U}
      _read_account_data
      if [ "${_THIS_MODE}" = "verbose" ]; then
        _send_notice_php ${_PHP_FPM_VERSION}
      fi
    fi
  fi
}

_send_notice_core() {
  if [ "${_hostedSys}" != "YES" ]; then
    return 1  # Exit the function but continue the script
  fi
  _BCC_EMAIL="inbox@boa.io"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "URGENT: Please migrate ${_Dom} site to Pressflow (LTS)" ${_CLIENT_EMAIL}
Hello,

Our system detected that you are using vanilla Drupal core
for site ${_Dom}.

The platform root directory for this site is:
${_Plr}

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
This email has been sent by your Ægir platform core monitor.

EOF
  fi
  echo "INFO: Pressflow notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
}

_detect_vanilla_core() {
  if [ ! -e "${_Plr}/core" ]; then
    if [ -e "${_Plr}/web.config" ]; then
      _DO_NOTHING=YES
    else
      if [ -e "${_Plr}/modules/watchdog" ]; then
        if [ ! -e "/boot/grub/grub.cfg" ] \
          && [ ! -e "/boot/grub/menu.lst" ] \
          && [[ "${_Plr}" =~ "static" ]] \
          && [ ! -e "${_Plr}/modules/cookie_cache_bypass" ]; then
          _if_hosted_sys
          if [ "${_hostedSys}" = "YES" ]; then
            echo Vanilla Drupal 5.x Platform detected in ${_Plr}
            _read_account_data
            if [ "${_THIS_MODE}" = "verbose" ]; then
              _send_notice_core
            fi
          fi
        fi
      else
        if [ ! -e "${_Plr}/modules/path_alias_cache" ] \
          && [ -e "${_Plr}/modules/user" ] \
          && [[ "${_Plr}" =~ "static" ]]; then
          echo Vanilla Drupal 6.x Platform detected in ${_Plr}
          if [ ! -e "/boot/grub/grub.cfg" ] \
            && [ ! -e "/boot/grub/menu.lst" ]; then
            _if_hosted_sys
            if [ "${_hostedSys}" = "YES" ]; then
              _read_account_data
              if [ "${_THIS_MODE}" = "verbose" ]; then
                _send_notice_core
              fi
            fi
          fi
        fi
      fi
    fi
  fi
}

# Create the control-INI dir in the current (pinned) site directory: only a
# Drupal or Backdrop site (it has settings.php) gets it; a Grav or
# Textpattern site carries no INI.
_usage_ini_dir_here() {
  if [ ! -e ./modules ] && [ -f ./settings.php ]; then
    mkdir ./modules
  fi
}

_usage_count() {
  local _sStores _n _r _Ali
  # config/ and .drush/ are oN's: the vhost names are listed, and each alias
  # read, inside the real directory only; a site directory named by an
  # alias is read, extended and measured only inside the real directory, and
  # only when it lies in this account
  for _Site in $(_usage_in_real_dir "${_usEr}/config/server_master/nginx/vhost.d" \
    find . -maxdepth 1 -mindepth 1 -type f | sort); do
    #echo Counting Site ${_Site}
    #echo "${_THIS_U},${_Dom},vhost-exists"
    _Dom="${_Site#./}"
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
    case ${_Dom} in
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
    if [ -e "${_usEr}/.drush/${_Dom}.alias.drushrc.php" ]; then
      #echo "${_THIS_U},${_Dom},drushrc-exists"
      _Ali=$(_usage_read_in "${_usEr}/.drush" "${_Dom}.alias.drushrc.php")
      _Dir=$(printf '%s\n' "${_Ali}" \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _Plr=$(printf '%s\n' "${_Ali}" \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _detect_vanilla_core
      _fix_clear_cache
      #echo Dir is ${_Dir}
      case "${_Dir}" in
        "${_usEr}"/?*) ;;
        *) _Dir= ;;
      esac
      if [ -n "${_Dir}" ] \
        && [ -e "${_Dir}/drushrc.php" ] \
        && [ -e "${_Dir}/files" ] \
        && [ -e "${_Dir}/private" ] \
        && [ ! -e "${_Plr}/profiles/hostmaster" ]; then
        _usage_in_site_dir "${_Dir}" _usage_ini_dir_here
        #echo "${_THIS_U},${_Dom},sitedir-exists"
        _Dat=$(_usage_in_site_dir "${_Dir}" _usage_read_here drushrc.php \
          | grep "options\['db_name'\] = " \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,';]//g" 2>&1)
        #echo Dat is ${_Dat}
        if [ ! -z "${_Dat}" ] && [ -e "${_Dir}" ]; then
          # the site directory without following any link, plus its files
          # and private only where they resolve into the account's own
          # files store (see _usage_stores)
          _sStores=()
          for _n in files private; do
            [ -n "${_uFiles}" ] && [ -L "${_Dir}/${_n}" ] || continue
            _r=$(realpath -e -- "${_Dir}/${_n}" 2> /dev/null) || continue
            case "${_r}/" in
              "${_uFiles}"/?*) _sStores+=("${_r}") ;;
            esac
          done
          _DirSize=$(_usage_in_site_dir "${_Dir}" \
            du -s -c -- . "${_sStores[@]}" 2>/dev/null | tail -n 1)
          _DirSize=$(echo "${_DirSize}" \
            | cut -d'/' -f1 \
            | awk '{ print $1}' \
            | sed "s/[\/\s+]//g" 2>&1)
          _SumDir=$(( _SumDir + _DirSize ))
          echo "${_THIS_U},${_Dom},_DirSize:${_DirSize}"
          [ "${_THIS_MODE}" = "verbose" ] && echo "  ${_THIS_U},${_Dom},_DirSize:${_DirSize}" >> "${_uLogFil}"
        fi
        if [ ! -z "${_Dat}" ]; then
          # reset for every site, and the name (from the site's drushrc.php)
          # is looked up only as a plain database name, the rule
          # mysql_backup.sh applies: never a path, a pattern or a glob
          _DatSize=
          if [[ "${_Dat}" =~ ^[A-Za-z0-9_]+$ ]]; then
            if [ -e "/var/log/boa/.du.local.sql" ]; then
              _DatSize=$(grep "/var/lib/mysql/${_Dat}$" /var/log/boa/.du.local.sql 2>&1)
            elif [ -e "/var/lib/mysql/${_Dat}" ]; then
              _DatSize=$(du -s "/var/lib/mysql/${_Dat}" 2>/dev/null)
            fi
          fi
          _DatSize=$(echo "${_DatSize}" \
            | cut -d'/' -f1 \
            | awk '{ print $1}' \
            | sed "s/[\/\s+]//g" 2>&1)
          if [ "${_DEV_URL}" = "YES" ]; then
            _SkipDt=$(( _SkipDt + _DatSize ))
            echo "${_THIS_U},${_Dom},_DatSize:${_DatSize}:${_Dat},skip"
            [ "${_THIS_MODE}" = "verbose" ] && echo "  ${_THIS_U},${_Dom},_DatSize:${_DatSize}:${_Dat},skip" >> "${_uLogFil}"
          else
            _SumDat=$(( _SumDat + _DatSize ))
            echo "${_THIS_U},${_Dom},_DatSize:${_DatSize}:${_Dat}"
            [ "${_THIS_MODE}" = "verbose" ] && echo "  ${_THIS_U},${_Dom},_DatSize:${_DatSize}:${_Dat}" >> "${_uLogFil}"
          fi
        else
          echo "Database ${_Dat} for ${_Dom} does not exist"
        fi
      fi
    fi
  done
}

_send_notice_sql() {
  if [ "${_hostedSys}" != "YES" ]; then
    return 1  # Exit the function but continue the script
  fi
  _MODE=$1
  if [ "${_MODE}" = "DEV" ]; then
    _SQL_LIM=${_SQL_DEV_LIMIT}
    _SQL_NOW=${_SkipDtH}
  else
    _SQL_LIM=${_SQL_MIN_LIMIT}
    _SQL_NOW=${_SumDatH}
  fi
  _BCC_EMAIL="inbox@boa.io"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "NOTICE: Your ${_MODE} DB Usage on [${_THIS_U}] is too high: ${_SQL_NOW} MB" ${_CLIENT_EMAIL}
Hello,

You are using more resources than allocated in your subscription.
You have currently ${_CLIENT_CORES} Ægir ${_CLIENT_OPTION} ${_ENGINE_NR}.

Your allowed databases space for ${_MODE} sites is ${_SQL_LIM} MB,
but you are currently using ${_SQL_NOW} MB of databases space.

Please reduce your usage by deleting no longer used sites, or purchase
enough Ægir Engines to cover your current usage.

You can purchase more Ægir Engines easily online:

  https://omega8.cc/pricing

To qualify as DEV/TEST with separate usage limits as specified
in your subscription, the site should have in its main name
a special keyword with ==two dots== on ==both sides== like this:

  .dev.
  .devel.
  .temp.
  .tmp.
  .temporary.
  .test.
  .testing.
  .stage.
  .staging.

For example, a site with main name: abc.test.foo.com is by default
excluded from your allocated databases limits for LIVE sites.

However, if we discover that anyone is using this method to hide real
usage via listed keywords in the main site name and adding live domain(s)
as aliases, such account will be suspended without any warning.

--
This email has been sent by your Ægir resources usage daily monitor.

EOF
  fi
  echo "INFO: Notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
  [ "${_THIS_MODE}" = "verbose" ] && echo "INFO: Notice Your DB Usage sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK" >> "${_uLogFil}"
}

_send_notice_disk() {
  if [ "${_hostedSys}" != "YES" ]; then
    return 1  # Exit the function but continue the script
  fi
  _BCC_EMAIL="inbox@boa.io"
  _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
  cat <<EOF | s-nail -b ${_BCC_EMAIL} \
    -s "NOTICE: Your Disk Usage on [${_THIS_U}] is too high" ${_CLIENT_EMAIL}
Hello,

You are using more resources than allocated in your subscription.
You have currently ${_CLIENT_CORES} Ægir ${_CLIENT_OPTION} ${_ENGINE_NR}.

Your allowed disk space is ${_DSK_MIN_LIMIT} MB.
You are currently using ${_TotSizH} MB of disk space.

Please reduce your usage by deleting old backups, files,
and no longer used sites, or purchase enough Ægir Engines
to cover your current usage.

You can purchase more Ægir Engines easily online:

  https://omega8.cc/buy

Note that unlike with database space limits, for files related disk space
we count all your sites, including also all DEV/TEST sites, if they exist,
even if they are marked as disabled in your Ægir control panel.

--
This email has been sent by your Ægir resources usage daily monitor.

EOF
  fi
  echo "INFO: Notice sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK"
  [ "${_THIS_MODE}" = "verbose" ] && echo "INFO: Notice Your Disk Usage sent to ${_CLIENT_EMAIL} [${_THIS_U}]: OK" >> "${_uLogFil}"
}


_check_limits() {
  _SQL_MIN_LIMIT=0
  _SQL_MAX_LIMIT=0
  _SQL_DEV_LIMIT=0
  _DSK_MIN_LIMIT=0
  _DSK_MAX_LIMIT=0
  _DSK_CLU_LIMIT=1
  _read_account_data
  if [ "${_CLIENT_OPTION}" = "MONSTER" ] || [ "${_CLIENT_OPTION}" = "CLUSTER" ]; then
    _CLIENT_OPTION=MONSTER
    if [ -z "${_DSK_CLU_LIMIT}" ]; then
      _DSK_CLU_LIMIT=1
    fi
    _SQL_MIN_LIMIT=51200
    _DSK_MIN_LIMIT=204800
    _DSK_MAX_LIMIT=215040
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 2048 ))
    _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT *= _DSK_CLU_LIMIT ))
    _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT *= _DSK_CLU_LIMIT ))
  elif [ "${_CLIENT_OPTION}" = "ULTRA" ]; then
    if [ -z "${_DSK_CLU_LIMIT}" ]; then
      _DSK_CLU_LIMIT=1
    fi
    _SQL_MIN_LIMIT=5120
    _DSK_MIN_LIMIT=102400
    _DSK_MAX_LIMIT=107520
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 1024 ))
    _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT *= _DSK_CLU_LIMIT ))
    _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT *= _DSK_CLU_LIMIT ))
  elif [ "${_CLIENT_OPTION}" = "PHANTOM" ]; then
    if [ -z "${_DSK_CLU_LIMIT}" ]; then
      _DSK_CLU_LIMIT=1
    fi
    _SQL_MIN_LIMIT=20480
    _DSK_MIN_LIMIT=409600
    _DSK_MAX_LIMIT=430080
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 2048 ))
    _DSK_MIN_LIMIT=$(( _DSK_MIN_LIMIT *= _DSK_CLU_LIMIT ))
    _DSK_MAX_LIMIT=$(( _DSK_MAX_LIMIT *= _DSK_CLU_LIMIT ))
  elif [ "${_CLIENT_OPTION}" = "POWER" ]; then
    _SQL_MIN_LIMIT=10240
    _DSK_MIN_LIMIT=204800
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 1024 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 2560 ))
  elif [ "${_CLIENT_OPTION}" = "AERO" ]; then
    _SQL_MIN_LIMIT=5120
    _DSK_MIN_LIMIT=102400
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 1024 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 2560 ))
  elif [ "${_CLIENT_OPTION}" = "AGAIN" ]; then
    _SQL_MIN_LIMIT=40960
    _DSK_MIN_LIMIT=409600
    _SQL_DEV_EXTRA=0
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 512 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 1280 ))
  elif [ "${_CLIENT_OPTION}" = "HEADSPACE" ]; then
    _SQL_MIN_LIMIT=20480
    _DSK_MIN_LIMIT=204800
    _SQL_DEV_EXTRA=0
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 512 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 1280 ))
  elif [ "${_CLIENT_OPTION}" = "QUIET" ]; then
    _SQL_MIN_LIMIT=10240
    _DSK_MIN_LIMIT=102400
    _SQL_DEV_EXTRA=0
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 512 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 1280 ))
  elif [ "${_CLIENT_OPTION}" = "EDGE" ] \
    || [ "${_CLIENT_OPTION}" = "SSD" ] \
    || [ "${_CLIENT_OPTION}" = "CLASSIC" ]; then
    _CLIENT_OPTION=EDGE
    _SQL_MIN_LIMIT=2048
    _DSK_MIN_LIMIT=61440
    _SQL_DEV_EXTRA=2
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 512 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 1280 ))
  elif [ "${_CLIENT_OPTION}" = "MINI" ]; then
    _SQL_MIN_LIMIT=2048
    _DSK_MIN_LIMIT=30720
    _SQL_DEV_EXTRA=1
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 512 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 1280 ))
  elif [ "${_CLIENT_OPTION}" = "MICRO" ]; then
    _SQL_MIN_LIMIT=1024
    _DSK_MIN_LIMIT=10240
    _SQL_DEV_EXTRA=1
    _SQL_MAX_LIMIT=$(( _SQL_MIN_LIMIT + 256 ))
    _DSK_MAX_LIMIT=$(( _DSK_MIN_LIMIT + 640 ))
  else
    _SQL_MIN_LIMIT=1024
    _DSK_MIN_LIMIT=15360
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
      _SQL_ADD_LIMIT=2048
      _DSK_ADD_LIMIT=61440
    elif [ -e "/data/disk/${_THIS_U}/log/extra_aero.txt" ]; then
      _SQL_ADD_LIMIT=5120
      _DSK_ADD_LIMIT=102400
    elif [ -e "/data/disk/${_THIS_U}/log/extra_power.txt" ]; then
      _SQL_ADD_LIMIT=10240
      _DSK_ADD_LIMIT=204800
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

  if [ "${_THIS_MODE}" = "verbose" ]; then
    echo "  SQL Usage Limit for Production Sites is ${_SQL_MIN_LIMIT} MB" >> "${_uLogFil}"
    echo "  SQL Usage Limit for Dev/Test Sites is ${_SQL_DEV_LIMIT} MB" >> "${_uLogFil}"
    echo "  Disk Usage Limit for Files and Solr is ${_DSK_MIN_LIMIT} MB" >> "${_uLogFil}"
    echo " " >> "${_uLogFil}"
  fi

  if [ "${_SumDatH}" -gt "${_SQL_MAX_LIMIT}" ]; then
    if [ ! -e "${_usEr}/log/CANCELLED" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/proxy-failed.pid" ]; then
      if [ "${_THIS_MODE}" = "verbose" ]; then
        _send_notice_sql "LIVE"
      fi
    fi
    echo SQL Usage for ${_THIS_U} above limits
    [ "${_THIS_MODE}" = "verbose" ] && echo "  SQL Usage for ${_THIS_U} above limits" >> "${_uLogFil}"
  elif [ "${_SkipDtH}" -gt "${_SQL_DEV_LIMIT}" ]; then
    if [ ! -e "${_usEr}/log/CANCELLED" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/proxy-failed.pid" ]; then
      if [ "${_THIS_MODE}" = "verbose" ]; then
        _send_notice_sql "DEV"
      fi
    fi
    echo SQL Usage for ${_THIS_U} above limits
    [ "${_THIS_MODE}" = "verbose" ] && echo "  SQL Usage for ${_THIS_U} above limits" >> "${_uLogFil}"
  else
    echo SQL Usage for ${_THIS_U} below limits
    [ "${_THIS_MODE}" = "verbose" ] && echo "  SQL Usage for ${_THIS_U} below limits" >> "${_uLogFil}"
  fi
  if [ "${_TotSizH}" -gt "${_DSK_MAX_LIMIT}" ]; then
    if [ ! -e "${_usEr}/log/CANCELLED" ] \
      && [ ! -e "${_usEr}/log/proxied.pid" ] \
      && [ ! -e "${_usEr}/log/proxy-failed.pid" ]; then
      if [ "${_THIS_MODE}" = "verbose" ]; then
        _send_notice_disk
      fi
    fi
    echo Disk Usage for ${_THIS_U} above limits
    [ "${_THIS_MODE}" = "verbose" ] && echo "  Disk Usage for ${_THIS_U} above limits" >> "${_uLogFil}"
  else
    echo Disk Usage for ${_THIS_U} below limits
    [ "${_THIS_MODE}" = "verbose" ] && echo "  Disk Usage for ${_THIS_U} below limits" >> "${_uLogFil}"
  fi
}

_count_cpu() {
  _CPU_INFO="$(grep -c processor /proc/cpuinfo)"
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST="$(which nproc)"
  if [ -z "${_NPROC_TEST}" ]; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt 0 ]; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt 1 ]; then
    _CPU_NR=1
  fi
}

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

# Defaults before the cnf source below so the cnf value wins; the
# variable is the supported switch, the marker stays honoured for
# one release while fleets converge.
_DEBUG_EMAIL=NO

_load_control() {
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
  : "${_CPU_TASK_RATIO:=3.1}"
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

_sub_count_usr_home() {
  if [ -e "$1" ]; then
    _HqmSiz=$(du -s $1 2>/dev/null)
    _HqmSiz=$(echo "${_HqmSiz}" \
      | cut -d'/' -f1 \
      | awk '{ print $1}' \
      | sed "s/[\/\s+]//g" 2>&1)
    _HxmSiz=$(( _HxmSiz + _HqmSiz ))
    ### echo $1 disk usage is $_HqmSiz
    ### echo _HxmSiz total is $_HxmSiz
  fi
}

_usage_action() {
  local _THIS_HM_ALI
  for _usEr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    _count_cpu
    _load_control
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d" ]; then
      if (( $(echo "${_O_LOAD} < ${_O_LOAD_MAX}" | bc -l) )); then
        _HomSiz=0
        _HqmSiz=0
        _HxmSiz=0
        _SkipDt=0
        _SumDat=0
        _SumDir=0
        _TotSiz=0
        _THIS_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
        _uLogDir="${_usEr}/static/usage"
        _uLogFil=/dev/null
        # static/ is tenant-writable (02775, no sticky), so the usage directory
        # name can be replaced with a symlink, before the check or at any
        # moment after it. Strip a planted link inside the real static/ and
        # use only a real directory root owns; the report itself is written
        # to root's own temp file and put there once the account is counted
        # (_usage_log_put). Fail closed to /dev/null rather than write
        # somewhere unverified.
        if _usage_in_real_dir "${_usEr}/static" _usage_log_dir_here; then
          _uLogFil=$(mktemp 2> /dev/null) || _uLogFil=/dev/null
        else
          echo "INFO: Usage log dir ${_uLogDir} is not a root-owned directory -- not writing a report"
        fi
        _usage_stores
        _THIS_HM_ALI=$(_usage_read_in "${_usEr}/.drush" hostmaster.alias.drushrc.php)
        _THIS_HM_SITE=$(printf '%s\n' "${_THIS_HM_ALI}" \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _THIS_HM_PLR=$(printf '%s\n' "${_THIS_HM_ALI}" \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        echo load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}
        if [ ! -e "${_usEr}/log/skip-force-cleanup.txt" ]; then
          cd ${_usEr}
          echo "Remove various tmp/dot files breaking du command"
          # -delete, never a name list through xargs: the names are the
          # tenant's, and xargs splits them at blanks and quotes
          find . -name "exclude.tag" -type f -delete &> /dev/null
          find . -name ".DS_Store" -type f -delete &> /dev/null
          find . -name "*~" -type f -delete &> /dev/null
          find . -name "*#" -type f -delete &> /dev/null
          find . -name ".#*" -type f -delete &> /dev/null
          find . -name "*--" -type f -delete &> /dev/null
          find . -name "._*" -type f -delete &> /dev/null
          find . -name "*~" -type l -delete &> /dev/null
          find . -name "*#" -type l -delete &> /dev/null
          find . -name ".#*" -type l -delete &> /dev/null
          find . -name "*--" -type l -delete &> /dev/null
          find . -name "._*" -type l -delete &> /dev/null
        fi
        echo "Counting User ${_usEr}"
        if [ "${_THIS_MODE}" = "verbose" ]; then
          cat << EOF > "${_uLogFil}"
Counting Usage for User ${_usEr} started on $(date)

Detailed usage per site is shown first and usage summary further below.

To qualify as DEV/TEST with separate usage limits as specified
in your subscription, the site should have in its main name
a special keyword with ==two dots== on ==both sides== like this:

  .dev.
  .devel.
  .temp.
  .tmp.
  .temporary.
  .test.
  .testing.
  .stage.
  .staging.

For example, a site with main name: abc.test.foo.com is by default
excluded from your allocated databases limits for LIVE sites.

Note that unlike with database space limits, for files related disk space
we count all your sites, including also all DEV/TEST sites, if they exist,
even if they are marked as disabled in your Ægir control panel.

  _DirSize is the site files usage in kB
  _DatSize is the site database usage in kB
  The optional =skip= at the end of line identifies DEV/TEST site

EOF
        fi
        _DOW=$(date +%u)
        _DOW=${_DOW//[^1-7]/}
        if [ "${_DOW}" = "2" ]; then
          _detect_deprecated_php
        fi
        _usage_count
        if [ -d "/home/${_THIS_U}.ftp" ]; then
          for _uH in `find /home/${_THIS_U}.* -maxdepth 0 -mindepth 0 | sort`; do
            if [ -d "${_uH}" ]; then
              _sub_count_usr_home ${_uH}
            fi
          done
          for _uR in `find /var/solr9/data/oct.${_THIS_U}.* -maxdepth 0 -mindepth 0 | sort`; do
            if [ -d "${_uR}" ]; then
              _sub_count_usr_home ${_uR}
            fi
          done
          for _uR in `find /var/solr7/data/oct.${_THIS_U}.* -maxdepth 0 -mindepth 0 | sort`; do
            if [ -d "${_uR}" ]; then
              _sub_count_usr_home ${_uR}
            fi
          done
          for _uO in `find /opt/solr4/${_THIS_U}.* -maxdepth 0 -mindepth 0 | sort`; do
            if [ -d "${_uO}" ]; then
              _sub_count_usr_home ${_uO}
            fi
          done
        fi
        # the account's tree without following any link, plus its own
        # relocated stores (_usage_stores); du counts a store reached twice
        # once
        _HomSiz=$(du -s -c -- "${_usEr}" "${_uStores[@]}" 2>/dev/null | tail -n 1)
        _HomSiz=$(echo "${_HomSiz}" \
          | cut -d'/' -f1 \
          | awk '{ print $1}' \
          | sed "s/[\/\s+]//g" 2>&1)

        _TotSiz=$(( _HomSiz + _HxmSiz ))

        _TotSizH=$(echo "scale=0; ${_TotSiz}/1024" | bc 2>&1)
        _SumDirH=$(echo "scale=0; ${_SumDir}/1024" | bc 2>&1)
        _SumDatH=$(echo "scale=0; ${_SumDat}/1024" | bc 2>&1)
        _SkipDtH=$(echo "scale=0; ${_SkipDt}/1024" | bc 2>&1)

        echo _TotSiz is ${_TotSiz} kB or ${_TotSizH} MB
        echo _SumDir is ${_SumDir} kB or ${_SumDirH} MB
        echo _SumDat is ${_SumDat} kB or ${_SumDatH} MB
        echo _SkipDt is ${_SkipDt} kB or ${_SkipDtH} MB

        if [ "${_THIS_MODE}" = "verbose" ]; then
          cat << EOF >> "${_uLogFil}"

  LiveDb Memory Space Used is ${_SumDat} kB or ${_SumDatH} MB
  DevDb Memory Space Used is ${_SkipDt} kB or ${_SkipDtH} MB
  Total Disk Space (Files and Solr) Used is ${_TotSiz} kB or ${_TotSizH} MB

EOF
        fi

        _if_hosted_sys
        if [ "${_hostedSys}" = "YES" ]; then
          if [ -e "${_THIS_HM_SITE}" ]; then
            _check_limits
            su -s /bin/bash - ${_THIS_U} -c "drush8 @hostmaster \
              variable-set --always-set site_footer 'Usage on ${_DATE} \
              | Files <strong>${_TotSizH}</strong> MB \
              | LiveDb <strong>${_SumDatH}</strong> MB \
              | DevDb <strong>${_SkipDtH}</strong> MB \
              | <strong>${_CLIENT_CORES}</strong> \
              ${_CLIENT_OPTION} ${_ENGINE_NR} \
              | CLI <strong>${_CLIENT_CLI}</strong> \
              | FPM <strong>${_CLIENT_FPM}</strong>'" &> /dev/null
            wait
            if [ ! -e "${_usEr}/log/CANCELLED" ] \
              && [ "${_DEV_EXC}" = "NO" ] \
              && [ ! -e "${_usEr}/log/proxied.pid" ] \
              && [ ! -e "${_usEr}/log/proxy-failed.pid" ]; then
              _eMail=${_CLIENT_EMAIL//\\\@/\@}
              # the panel's host name, one per report line: nothing else the
              # account wrote into domain.txt reaches the operator's report
              _AegirUrl=$(_usage_read_in "${_usEr}/log" domain.txt | head -n 1 \
                | tr -d '\r\t ')
              [[ "${_AegirUrl}" =~ ^[A-Za-z0-9.-]+$ ]] || _AegirUrl=
              if [ "${_TotSizH}" -gt "${_DSK_MAX_LIMIT}" ]; then
                _Files="!x!FilesAll"
              else
                _Files="FilesAll"
              fi
              if [ "${_SumDatH}" -gt "${_SQL_MAX_LIMIT}" ]; then
                _DbsL="!x!DbsLive"
              else
                _DbsL="DbsLive"
              fi
              if [ "${_SkipDtH}" -gt "${_SQL_DEV_LIMIT}" ]; then
                _DbsD="!x!DbsDev"
              else
                _DbsD="DbsDev"
              fi
              if [ "${_THIS_MODE}" = "verbose" ] || [ -z "${_THIS_MODE}" ]; then
                _LOG_FILE="usage-latest-verbose.log"
              elif [ "${_THIS_MODE}" = "silent" ]; then
                _LOG_FILE="usage-latest-silent.log"
              fi
              echo "${_AegirUrl},${_Files}:${_TotSizH},${_DbsL}:${_SumDatH},${_DbsD}:${_SkipDtH},${_eMail},Subs:${_CLIENT_OPTION}:${_CLIENT_CORES},${_THIS_U}" >> /var/log/boa/usage/${_LOG_FILE}
            fi
            su -s /bin/bash - ${_THIS_U} \
              -c "drush8 @hostmaster cache-clear all" &> /dev/null
            wait
          fi
        else
          if [ -e "${_THIS_HM_SITE}" ]; then
            _check_limits
            su -s /bin/bash - ${_THIS_U} -c "drush8 @hostmaster \
              variable-set --always-set site_footer 'Usage on ${_DATE} \
              | Files <strong>${_TotSizH}</strong> MB \
              | LiveDb <strong>${_SumDatH}</strong> MB \
              | DevDb <strong>${_SkipDtH}</strong> MB \
              | <strong>${_CLIENT_CORES}</strong> \
              ${_CLIENT_OPTION} ${_ENGINE_NR} \
              | CLI <strong>${_CLIENT_CLI}</strong> \
              | FPM <strong>${_CLIENT_FPM}</strong>'" &> /dev/null
            wait
            if [ ! -e "${_usEr}/log/CANCELLED" ] \
              && [ "${_DEV_EXC}" = "NO" ] \
              && [ ! -e "${_usEr}/log/proxied.pid" ] \
              && [ ! -e "${_usEr}/log/proxy-failed.pid" ]; then
              _eMail=${_CLIENT_EMAIL//\\\@/\@}
              # the panel's host name, one per report line: nothing else the
              # account wrote into domain.txt reaches the operator's report
              _AegirUrl=$(_usage_read_in "${_usEr}/log" domain.txt | head -n 1 \
                | tr -d '\r\t ')
              [[ "${_AegirUrl}" =~ ^[A-Za-z0-9.-]+$ ]] || _AegirUrl=
              if [ "${_TotSizH}" -gt "${_DSK_MAX_LIMIT}" ]; then
                _Files="!x!FilesAll"
              else
                _Files="FilesAll"
              fi
              if [ "${_SumDatH}" -gt "${_SQL_MAX_LIMIT}" ]; then
                _DbsL="!x!DbsLive"
              else
                _DbsL="DbsLive"
              fi
              if [ "${_SkipDtH}" -gt "${_SQL_DEV_LIMIT}" ]; then
                _DbsD="!x!DbsDev"
              else
                _DbsD="DbsDev"
              fi
              if [ "${_THIS_MODE}" = "verbose" ] || [ -z "${_THIS_MODE}" ]; then
                _LOG_FILE="usage-latest-verbose.log"
              elif [ "${_THIS_MODE}" = "silent" ]; then
                _LOG_FILE="usage-latest-silent.log"
              fi
              echo "${_AegirUrl},${_Files}:${_TotSizH},${_DbsL}:${_SumDatH},${_DbsD}:${_SkipDtH},${_eMail},Subs:${_CLIENT_OPTION}:${_CLIENT_CORES},${_THIS_U}" >> /var/log/boa/usage/${_LOG_FILE}
            fi
            su -s /bin/bash - ${_THIS_U} \
              -c "drush8 @hostmaster variable-set \
              --always-set site_footer ''" &> /dev/null
            wait
            su -s /bin/bash - ${_THIS_U} \
              -c "drush8 @hostmaster cache-clear all" &> /dev/null
            wait
          fi
        fi
        echo "Done for ${_usEr}"
        [ "${_THIS_MODE}" = "verbose" ] && echo " " >> "${_uLogFil}"
        [ "${_THIS_MODE}" = "verbose" ] && echo "Counting Usage for User ${_usEr} completed on $(date)" >> "${_uLogFil}"
        _usage_log_put
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
echo "INFO: Starting usage monitoring on $(date)"
_NOW=$(date +%y%m%d-%H%M%S)
_NOW=${_NOW//[^0-9-]/}
_DATE=$(date)
_hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
mkdir -p /var/log/boa/usage
if [ "${1}" = "verbose" ] || [ -z "${1}" ]; then
  _THIS_MODE="verbose"
  rm -f /var/log/boa/usage/usage-latest-verbose.log
elif [ "${1}" = "silent" ]; then
  _THIS_MODE="silent"
  rm -f /var/log/boa/usage/usage-latest-silent.log
fi
_usage_action >/var/log/boa/usage/usage-${_NOW}.log 2>&1
echo "INFO: Completing usage monitoring on $(date)"
exit 0

