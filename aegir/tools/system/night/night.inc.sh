#!/bin/bash

###
### night.inc.sh -- shared helper library for the nightly maintenance family.
###
### Sourced by daily.sh (the parent orchestrator, later renamed owl.sh) and,
### in subsequent phases, by the per-account/per-site worker scripts split out
### under /var/xdrago/night/. Defines pure helpers, load helpers, the chattr
### lock helpers and the drush8 wrappers so a single copy is shared instead of
### duplicated in every split script. Functions only -- no top-level side
### effects; callers own their own prologue (PATH/HOME) and _check_root.
###
### Bodies are moved verbatim from daily.sh to keep behaviour identical; the
### drush wrappers and chattr helpers read _HM_U/_Dom from the caller's scope
### at call time, exactly as before -- the caller must set them before calling.
###

###-------------HELPERS-----------------###

# Validate that a caller-controlled path (parsed from a Drush alias file)
# resolves under one of BOA's writable roots. Used by the per-site loop to
# gate chown/chmod operations on _Dir (site_path) and _Plr (platform root):
# the alias file is written by aegir-context Hostmaster tasks and a compromised
# HM_U user could otherwise rewrite the alias to point at /etc and have the
# daily runner chown system paths. Returns 0 on safe path, 1 otherwise.
_validate_safe_dir() {
  local _resolved
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || return 1
  case "${_resolved}/" in
    /data/disk/*|/var/aegir/*|/home/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_check_file_with_wildcard_path() {
  _WILDCARD_TEST=$(ls $1 2>&1)
  if [ -z "${_WILDCARD_TEST}" ]; then
    _FILE_EXISTS=NO
  else
    _FILE_EXISTS=YES
  fi
}

###-------------LOAD-----------------###

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
  echo ${_CPU_NR} > /data/all/cpuinfo
  chmod 644 /data/all/cpuinfo &> /dev/null
}

_get_load() {
  read -r _one _five _rest <<< "$(cat /proc/loadavg)"
  _O_LOAD=$(awk -v _load_value="${_one}" -v _cpus="${_CPU_NR}" 'BEGIN { printf "%.1f", (_load_value / _cpus) * 100 }')
}

_load_control() {
  : "${_CPU_TASK_RATIO:=3.1}"
  [ -e "/root/.force.sites.verify.cnf" ] && _CPU_TASK_RATIO=4.1
  _CPU_TASK_RATIO="$(_sanitize_number "${_CPU_TASK_RATIO}")"
  _O_LOAD_MAX=$(echo "${_CPU_TASK_RATIO} * 100" | bc -l)
  _get_load
}

###-------------CHATTR-----------------###

_enable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      chattr +i /home/$1/
    else
      if [ -d "/home/$1/platforms/" ]; then
        chattr +i /home/$1/platforms/
        chattr +i /home/$1/platforms/* &> /dev/null
      fi
    fi
    if [ -d "/home/$1/.drush/" ]; then
      chattr +i /home/$1/.drush/
    fi
    if [ -d "/home/$1/.drush/usr/" ]; then
      chattr +i /home/$1/.drush/usr/
    fi
    if [ -f "/home/$1/.drush/php.ini" ]; then
      chattr +i /home/$1/.drush/*.ini
    fi
    if [ -d "/home/$1/.bazaar/" ]; then
      chattr +i /home/$1/.bazaar/
    fi
  fi
}

_disable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_HM_U}.ftp" ]; then
      if [ -d "/home/$1/" ]; then
        chattr -i /home/$1/
      fi
    else
      if [ -d "/home/$1/platforms/" ]; then
        chattr -i /home/$1/platforms/
        chattr -i /home/$1/platforms/* &> /dev/null
      fi
    fi
    if [ -d "/home/$1/.drush/" ]; then
      chattr -i /home/$1/.drush/
    fi
    if [ -d "/home/$1/.drush/usr/" ]; then
      chattr -i /home/$1/.drush/usr/
    fi
    if [ -f "/home/$1/.drush/php.ini" ]; then
      chattr -i /home/$1/.drush/*.ini
    fi
    if [ -d "/home/$1/.bazaar/" ]; then
      chattr -i /home/$1/.bazaar/
    fi
  fi
}

###-------------DRUSH8-----------------###

_run_drush8_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} ${_HM_U} running drush8 @${_Dom} $1"
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${_Dom} $1" &> /dev/null
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${_Dom} $1" &> /dev/null
  fi
  wait
}

_run_drush8_hmr_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} ${_HM_U} running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

_run_drush8_hmr_master_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} aegir running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - aegir -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

_run_drush8_nosilent_cmd() {
  if [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} ${_HM_U} running drush8 @${_Dom} $1"
  fi
  if [ -x "/opt/php74/bin/php" ]; then
    su -s /bin/bash - ${_HM_U} -c "/opt/php74/bin/php /usr/bin/drush @${_Dom} $1"
  else
    su -s /bin/bash - ${_HM_U} -c "drush8 @${_Dom} $1"
  fi
  wait
}
