#!/bin/bash

###
### night.inc.sh -- shared helper library for the nightly maintenance family.
###
### Sourced by owl.sh (the parent orchestrator) and by the per-account/per-site
### worker scripts split out
### under /var/xdrago/night/. Defines pure helpers, load helpers, the chattr
### lock helpers and the drush8 wrappers so a single copy is shared instead of
### duplicated in every split script. Functions only -- no top-level side
### effects; callers own their own prologue (PATH/HOME) and _check_root.
###
### Bodies are moved verbatim from owl.sh to keep behaviour identical; the
### drush wrappers and chattr helpers read _HM_U/_Dom from the caller's scope
### at call time, exactly as before -- the caller must set them before calling.
###

###-------------CONSTANTS-----------------###

# BOA Tier-0 constants shared by the orchestrator and the night workers. The
# worker subprocesses get these by sourcing this library; the drush config/
# variable verbs (_vSet etc.) are used throughout the per-account/per-site work.
_WEBG=www-data
_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_cGet="config-get user.settings"
_cSet="config-set user.settings"
_vGet="variable-get"
_vSet="variable-set --always-set"

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

# Echo a platform's real Drupal docroot on stdout, or nothing if none found.
# The docroot is the platform root for Drupal 7-era codebases, but a subdir for
# Composer D8+ codebases whose web root differs from the app root: docroot/,
# html/, web/, in that order. Keyed on index.php, the front controller present
# in every Drupal docroot (D6..D11) regardless of build recipe. -f follows the
# symlink and is false for a dangling link, so a decoy like web -> /etc cannot
# register as a docroot. Returns 0 with the path, 1 if no docroot is found.
# Embedded here (not sourced from the install-time helper.sh.inc) so the
# deployed owl/night family carries its own structure-detection logic.
_detect_real_docroot() {
  local _plat="${1%/}"
  local _sub
  [ -n "${_plat}" ] && [ -d "${_plat}" ] || return 1
  if [ -f "${_plat}/index.php" ]; then
    printf '%s\n' "${_plat}"
    return 0
  fi
  for _sub in docroot html web; do
    if [ -f "${_plat}/${_sub}/index.php" ]; then
      printf '%s\n' "${_plat}/${_sub}"
      return 0
    fi
  done
  return 1
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

### Shared helpers promoted from owl.sh / 20-sites.sh (used by both
### the orchestrator and the per-account / per-site workers).

_apt_clean_update() {
  ${_APT_UPDATE} -qq 2>/dev/null
  _CALLER_SCRIPT="$(basename "${BASH_SOURCE[-1]}")"
  _CALLER_SCRIPT="${_CALLER_SCRIPT//[^a-zA-Z0-9._-]/_}"
  date +%s > "/run/_latest_apt_clean_update.${_CALLER_SCRIPT}.pid"
}

_if_gen_goaccess() {
  _PrTestPower=$(grep "POWER" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestPhantom=$(grep "PHANTOM" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestUltra=$(grep "ULTRA" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestMonster=$(grep "MONSTER" /root/.${_HM_U}.octopus.cnf 2>&1)
  _PrTestCluster=$(grep "CLUSTER" /root/.${_HM_U}.octopus.cnf 2>&1)
  if [[ "${_PrTestPower}" =~ "POWER" ]] \
    || [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
    || [[ "${_PrTestUltra}" =~ "ULTRA" ]] \
    || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
    || [[ "${_PrTestCluster}" =~ "CLUSTER" ]]; then
    _isWblgx="$(which weblogx)"
    if [ -x "${_isWblgx}" ]; then
      ${_isWblgx} --site="${1}" --env="${_HM_U}"
      wait
      if [ ! -e "/data/disk/${_HM_U}/static/goaccess" ]; then
        mkdir -p /data/disk/${_HM_U}/static/goaccess
      fi
      if [ -e "/var/www/adminer/access/${_HM_U}/${1}/index.html" ]; then
        cp -af /var/www/adminer/access/${_HM_U}/${1} /data/disk/${_HM_U}/static/goaccess/
      else
        rm -rf /var/www/adminer/access/${_HM_U}/${1}
        rm -rf /data/disk/${_HM_U}/static/goaccess/${1}
      fi
    fi
  fi
}

###-------------RUN-FREEZE-----------------###

# Freeze the per-run state a per-account worker needs into /run/night/run.env so a
# `10-account.sh <account>` subprocess sees the SAME run context the orchestrator
# computed. Called once by the orchestrator (owl.sh) after global-pre,
# before the account loop. _NOW is the keystone -- it names every *-${_NOW}.info
# idempotency guard, so a worker must INHERIT it here and never re-derive it.
night_emit_run_env() {
  mkdir -p /run/night
  {
    echo "export _NOW=\"${_NOW}\""
    echo "export _DOW=\"${_DOW}\""
    echo "export _xSrl=\"${_xSrl}\""
    echo "export _FORCE_SITES_VERIFY=\"${_FORCE_SITES_VERIFY}\""
    echo "export _CTRL_TPL_FORCE_UPDATE=\"${_CTRL_TPL_FORCE_UPDATE}\""
    echo "export _O_CONTRIB=\"${_O_CONTRIB}\""
    echo "export _O_CONTRIB_SEVEN=\"${_O_CONTRIB_SEVEN}\""
    echo "export _O_CONTRIB_EIGHT=\"${_O_CONTRIB_EIGHT}\""
    echo "export _O_CONTRIB_NINE=\"${_O_CONTRIB_NINE}\""
    echo "export _O_CONTRIB_TEN=\"${_O_CONTRIB_TEN}\""
    echo "export _O_CONTRIB_ELEVEN=\"${_O_CONTRIB_ELEVEN}\""
    echo "export _MODULES_FORCE=\"${_MODULES_FORCE}\""
    echo "export _MODULES_ON_SEVEN=\"${_MODULES_ON_SEVEN}\""
    echo "export _MODULES_ON_SIX=\"${_MODULES_ON_SIX}\""
    echo "export _MODULES_OFF_SEVEN=\"${_MODULES_OFF_SEVEN}\""
    echo "export _MODULES_OFF_SIX=\"${_MODULES_OFF_SIX}\""
    echo "export _hostedSys=\"${_hostedSys}\""
    echo "export _APT_UPDATE=\"${_APT_UPDATE}\""
    echo "export _PERMISSIONS_FIX=\"${_PERMISSIONS_FIX}\""
    echo "export _MODULES_FIX=\"${_MODULES_FIX}\""
    echo "export _CLEAR_BOOST=\"${_CLEAR_BOOST}\""
    echo "export _ENABLE_GOACCESS=\"${_ENABLE_GOACCESS}\""
  } > /run/night/run.env
  chmod 0600 /run/night/run.env &> /dev/null
}

# Load the run context in a worker: source .barracuda.cnf first (cnf flags and
# any var not in the freeze), then the run-freeze (authoritative for the frozen
# per-run set). No-op-safe if either is absent.
night_load_run_env() {
  # shellcheck disable=SC1091
  [ -e "/root/.barracuda.cnf" ] && . /root/.barracuda.cnf
  # shellcheck disable=SC1091
  [ -r "/run/night/run.env" ] && . /run/night/run.env
}
