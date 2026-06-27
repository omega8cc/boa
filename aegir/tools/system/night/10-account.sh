#!/bin/bash

###
### 10-account.sh -- the per-Octopus-account maintenance worker. Carved out of
### daily.sh's _daily_action loop body (Phase 2 of the owl.sh/night split): the
### whole per-account sequence -- drush prep, octopus.cnf email sync, the
### hostmaster vSet block, the per-site loop (_daily_process), platform GC,
### hostmaster LE, goaccess, and the final chattr relock. Sourced by daily.sh
### today and called once per account from the load-gated loop; becomes a
### standalone / parallel worker (invoked with the account path) in a later
### phase, once the run-freeze contract carries _NOW and the other per-run state
### across a process boundary.
###
### Reads the per-run ambient state (_NOW, _DOW, _xSrl, _O_CONTRIB*, _MODULES_*,
### _hostedSys, _ENABLE_GOACCESS, ...) and the loop var _usEr set by the caller.
### Depends on night.inc.sh (drush8 wrappers, chattr) plus the per-site
### procedures in 20-sites.sh and a few helpers still resident in daily.sh
### (_apt_clean_update via _le_ssl_check_update, _le_hm_ssl_check_update,
### _check_old_empty_platforms, _purge_cruft_machine) -- all resolved via the
### shared process while sourced; made self-contained when standalone execution
### is introduced.
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh

_account_process() {
  _HM_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
  _THIS_HM_SITE=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
    | grep "site_path'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
  echo "load is ${_O_LOAD} while maxload is ${_O_LOAD_MAX}"
  echo "User ${_usEr}"
  mkdir -p ${_usEr}/log/ctrl
  su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
  wait
  rm -rf ${_usEr}/.tmp/cache
  chage -M 99999 ${_HM_U}.ftp &> /dev/null
  su -s /bin/bash - ${_HM_U}.ftp -c "drush8 cc drush" &> /dev/null
  wait
  chage -M 90 ${_HM_U}.ftp &> /dev/null
  rm -rf /home/${_HM_U}.ftp/.tmp/cache
  _SQL_CONVERT=NO
  _DEL_OLD_EMPTY_PLATFORMS="0"
  if [ -e "/root/.${_HM_U}.octopus.cnf" ]; then
    if [ -x "/usr/bin/drush10" ]; then
      su -s /bin/bash - ${_HM_U} -c "rm -f ~/.drush/sites/*.yml"
      wait
      su -s /bin/bash - ${_HM_U} -c "rm -f ~/.drush/sites/.checksums/*.md5"
      wait
      su -s /bin/bash - ${_HM_U} -c "drush10 core:init --yes" &> /dev/null
      wait
      su -s /bin/bash - ${_HM_U} -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
      wait
    fi

    _MY_OCTO_EMAIL=
    _CLIENT_EMAIL=
    _MY_EMAIL=

    # shellcheck disable=SC1091
    [ -e "/root/.${_HM_U}.octopus.cnf" ] && source /root/.${_HM_U}.octopus.cnf

    [ -n "${_MY_OCTO_EMAIL}" ] && _MY_OCTO_EMAIL=${_MY_OCTO_EMAIL//\\\@/\@}
    [ -n "${_CLIENT_EMAIL}" ] && _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
    [ -n "${_MY_EMAIL}" ] && _MY_EMAIL=${_MY_EMAIL//\\\@/\@}

    _MY_OCTO_EMAIL_TEST=$(grep "^_MY_OCTO_EMAIL=" /root/.${_HM_U}.octopus.cnf 2>&1)
    _MY_EMAIL_TEST=$(grep "^_MY_EMAIL=" /root/.${_HM_U}.octopus.cnf 2>&1)

    if [[ ! "${_MY_OCTO_EMAIL_TEST}" =~ "_MY_OCTO_EMAIL" ]] \
      && [[ "${_MY_EMAIL_TEST}" =~ "_MY_EMAIL" ]] \
      && [ -n "${_MY_EMAIL}" ]; then
      _MY_OCTO_EMAIL="${_MY_EMAIL}"
      sed -i "s/^_MY_EMAIL=.*/_MY_OCTO_EMAIL=\"${_MY_EMAIL}\"/g" /root/.${_HM_U}.octopus.cnf
      _MY_EMAIL=
    fi

    if [ ! -z "${_CLIENT_EMAIL}" ] \
      && [[ ! "${_CLIENT_EMAIL}" =~ "${_MY_OCTO_EMAIL}" ]]; then
      _ALRT_EMAIL="${_CLIENT_EMAIL}"
    else
      _ALRT_EMAIL="${_MY_OCTO_EMAIL}"
    fi

    if [ "${_hostedSys}" = "YES" ]; then
      _BCC_EMAIL="omega8cc@gmail.com"
    else
      _BCC_EMAIL="${_MY_OCTO_EMAIL}"
    fi

    _DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS//[^0-9]/}

    if [ -e "${_usEr}/log/email.txt" ]; then
      _F_CLIENT_EMAIL=$(cat ${_usEr}/log/email.txt 2>&1)
      _F_CLIENT_EMAIL=$(echo -n ${_F_CLIENT_EMAIL} | tr -d "\n" 2>&1)
      _F_CLIENT_EMAIL=${_F_CLIENT_EMAIL//\\\@/\@}
    fi

    if [ ! -z "${_F_CLIENT_EMAIL}" ]; then
      _CLIENT_EMAIL_TEST=$(grep "^_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"" /root/.${_HM_U}.octopus.cnf 2>&1)
      if [[ "${_CLIENT_EMAIL_TEST}" =~ "${_F_CLIENT_EMAIL}" ]]; then
        _DO_NOTHING=YES
      else
        sed -i "s/^_CLIENT_EMAIL=.*/_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"/g" /root/.${_HM_U}.octopus.cnf
        wait
        _CLIENT_EMAIL=${_F_CLIENT_EMAIL}
      fi
    fi
  fi
  _disable_chattr ${_HM_U}.ftp
  rm -rf /home/${_HM_U}.ftp/drush-backups
  if [ -e "${_THIS_HM_SITE}" ]; then
    cd ${_THIS_HM_SITE}
    su -s /bin/bash ${_HM_U} -c "drush8 cc drush" &> /dev/null
    wait
    rm -rf ${_usEr}/.tmp/cache
    _run_drush8_hmr_cmd "${_vSet} hosting_cron_default_interval 3600"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_cron_frequency 1"
    _run_drush8_hmr_cmd "${_vSet} hosting_civicrm_cron_queue_frequency 60"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_task_gc_frequency 300"
    if [ -e "${_usEr}/log/hosting_cron_use_backend.txt" ]; then
      _run_drush8_hmr_cmd "${_vSet} hosting_cron_use_backend 1"
    else
      _run_drush8_hmr_cmd "${_vSet} hosting_cron_use_backend 0"
    fi
    _run_drush8_hmr_cmd "${_vSet} hosting_ignore_default_profiles 0"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_tasks_frequency 1"
    _run_drush8_hmr_cmd "${_vSet} hosting_queue_tasks_items 1"
    _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
    _run_drush8_hmr_cmd "${_vSet} aegir_backup_export_path ${_usEr}/backup-exports"
    _run_drush8_hmr_cmd "fr hosting_custom_settings -y"
    _run_drush8_hmr_cmd "cache-clear all"
    _run_drush8_hmr_cmd "cache-clear all"
  fi
  _daily_process
  _run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
    WHERE task_type='delete' AND task_status='-1'\""
  _run_drush8_hmr_cmd "sqlq \"DELETE FROM hosting_task \
    WHERE task_type='delete' AND task_status='0' AND executed='0'\""
  _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
  _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
    SET status=1 WHERE publish_path LIKE '%/aegir/distro/%'\""
  _check_old_empty_platforms
  _run_drush8_hmr_cmd "${_vSet} hosting_delete_force 0"
  _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
    SET status=-2 WHERE publish_path LIKE '%/aegir/distro/%'\""
  _THIS_HM_PLR=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
    | grep "root'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
  _run_drush8_hmr_cmd "sqlq \"UPDATE hosting_platform \
    SET status=1 WHERE publish_path LIKE '${_THIS_HM_PLR}'\""
  _purge_cruft_machine
  if [ "${_hostedSys}" = "YES" ]; then
    rm -rf ${_usEr}/clients/admin &> /dev/null
    rm -rf ${_usEr}/clients/omega8ccgmailcom &> /dev/null
    rm -rf ${_usEr}/clients/nocomega8cc &> /dev/null
  fi
  rm -rf ${_usEr}/clients/*/backups &> /dev/null
  symlinks -dr ${_usEr}/clients &> /dev/null
  if [ -d "/home/${_HM_U}.ftp" ]; then
    symlinks -dr /home/${_HM_U}.ftp &> /dev/null
    rm -f /home/${_HM_U}.ftp/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
  _le_hm_ssl_check_update ${_HM_U}
  if [ "${_ENABLE_GOACCESS}" = "YES" ] && [ -e "/etc/boa/.goaccess.all.cnf" ]; then
    _if_gen_goaccess "ALL"
  fi
  echo "Done for ${_usEr}"
  _enable_chattr ${_HM_U}.ftp
}
