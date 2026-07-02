#!/bin/bash

###
### 10-account.sh -- the per-Octopus-account maintenance worker. The whole
### per-account sequence (_account_process): drush prep, octopus.cnf email sync,
### the hostmaster vSet block, the per-site loop (_daily_process), platform GC,
### hostmaster LE, goaccess, and the final chattr relock. Run once per account by
### the owl.sh orchestrator as `10-account.sh <account-path>` (the unit of
### per-account parallelism); also sourceable for testing (defines functions only).
###
### Reads the per-run context from the run-freeze (/run/night/run.env via
### night_load_run_env): _NOW (keystone), _DOW, _O_CONTRIB*, _MODULES_*, _hostedSys,
### _APT_UPDATE and the cnf flags. Re-derives _hName and the per-account/per-site
### state from the <account> arg. Depends on night.inc.sh (drush8 wrappers, chattr,
### load, run-freeze, _apt_clean_update, _if_gen_goaccess) and 20-sites.sh
### (_daily_process + the per-site family), both sourced below.
###
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=dev
export _xSrl=5103devT01
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/20-sites.sh" ] && . /var/xdrago/night/20-sites.sh

_relocate_one_backup_dir() {
  # Relocate a single per-account backup directory onto the static/files
  # filesystem and replace it with a symlink, so large (dereferenced) backups
  # never fill the root partition. Data-safe and never destructive: an EXISTING
  # real dir is moved INCREMENTALLY (rsync --remove-source-files: peak extra space
  # on the tight root FS is ~one file, not a full 2x copy, and each file is removed
  # only after it is copied); on ANY failure the real dir is left in place and no
  # symlink is created, so a backup is never lost. Idempotent.
  # $1 current path (e.g. /data/disk/oX/backups); $2 target under static/files.
  local _src="$1" _dst="$2"

  # Already a symlink to the intended target -> just make sure the store exists.
  if [ -L "${_src}" ]; then
    if [ "$(readlink "${_src}" 2>/dev/null)" = "${_dst}" ]; then
      [ -d "${_dst}" ] || mkdir -p "${_dst}" 2>/dev/null
    else
      echo "backups-on-static: ${_src} is a symlink to an unexpected target; leaving for review"
    fi
    return 0
  fi

  # Only relocate an EXISTING real directory (so its exact ownership is preserved);
  # if the path does not exist yet, do nothing (Aegir creates it on first use and a
  # later run relocates it).
  [ -d "${_src}" ] || return 0

  local _ug
  _ug=$(stat -c '%U:%G' "${_src}" 2>/dev/null)
  [ -n "${_ug}" ] || return 0

  mkdir -p "${_dst}" 2>/dev/null || return 0
  chown "${_ug}" "${_dst}" 2>/dev/null

  if [ -n "$(ls -A "${_src}" 2>/dev/null)" ]; then
    # Re-check the task interlock right before the destructive move: skip (leave the
    # real dir untouched) if a provision task started since the entry check, so a
    # backup being written is never moved mid-write.
    _provision_running && { echo "backups-on-static: provision task active -- left ${_src} as real dir"; return 0; }
    # One-time migration de-links any pre-existing backups<->backup-exports hardlink
    # pairs (the two dirs are moved in separate rsync runs, no -H), so old tarballs
    # briefly cost double space -- on the static FS (the target), not the tight root,
    # and it ages out via the -mtime purge. New backups after relocation hardlink
    # fine (both dirs are then co-located on the static FS).
    rsync -a --remove-source-files "${_src}/" "${_dst}/" 2>/dev/null \
      || { echo "backups-on-static: move failed ${_src} -> ${_dst}; left as real dir"; return 0; }
    find "${_src}" -mindepth 1 -depth -type d -empty -delete 2>/dev/null
  fi

  # Refuse to replace the dir with a symlink unless it emptied cleanly.
  [ -z "$(ls -A "${_src}" 2>/dev/null)" ] \
    || { echo "backups-on-static: ${_src} not empty after move; left as real dir for review"; return 0; }

  rmdir "${_src}" 2>/dev/null || return 0
  ln -s "${_dst}" "${_src}" 2>/dev/null \
    || { echo "backups-on-static: could not symlink ${_src}; data is safe in ${_dst}, relink manually"; return 0; }
  chown -h "${_ug}" "${_src}" 2>/dev/null
  echo "backups-on-static: relocated ${_src} -> ${_dst} (static filesystem)"
}

_relocate_backups_to_static_fs() {
  # Move this account's backups + backup-exports onto the static/files filesystem
  # (static/files/.backups + static/files/.backup-exports) via symlinks, so large
  # dereferenced backups cannot fill the root partition, while keeping BOTH on ONE
  # filesystem so the Aegir backup-download hardlinks keep working (hardlinks can
  # not cross filesystems). The leading-dot names are skipped by the site/orphan
  # scan (like static/files/.archived). Gated on static/files being a SEPARATE
  # filesystem (no benefit otherwise), kill-switchable, idempotent, non-fatal.
  local _acct="${_usEr}"
  local _static="${_acct}/static/files"

  # Never move backup data while an Aegir/Provision task (backup/restore/download/
  # clone/migrate) might be writing it -- match the nightly file-mover interlock
  # used by every sibling mover (_provision_running = pgrep -f provision).
  _provision_running && { echo "INFO: provision task active -- skipping backups relocation"; return 0; }

  # Kill-switch: box-wide or per-account.
  [ -f "/data/conf/disable_backups_on_static_fs.cnf" ] && return 0
  [ -f "${_acct}/static/control/no_backups_on_static_fs.info" ] && return 0

  # static/files must exist and resolve to a DIFFERENT device than the account root
  # (else the relocation gives no protection).
  [ -e "${_static}" ] || return 0
  local _acctDev _statDev
  _acctDev=$(stat -c '%d' "${_acct}" 2>/dev/null)
  _statDev=$(stat -L -c '%d' "${_static}" 2>/dev/null)
  [ -n "${_acctDev}" ] && [ -n "${_statDev}" ] || return 0
  [ "${_acctDev}" != "${_statDev}" ] || return 0

  _relocate_one_backup_dir "${_acct}/backups"        "${_static}/.backups"
  _relocate_one_backup_dir "${_acct}/backup-exports" "${_static}/.backup-exports"
}

_account_process() {
  _HM_U=$(echo ${_usEr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
  _THIS_HM_SITE=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
    | grep "site_path'" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1)
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
    _relocate_backups_to_static_fs
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
  _le_account_report
  _enable_chattr ${_HM_U}.ftp
}

### Per-account helpers relocated from owl.sh (hostmaster LE cert +
### empty-platform GC + cruft purge). Called by _account_process above.

_if_le_hm_ssl_old() {
  # Get the current time in seconds since epoch
  _current_time=$(date +%s)

  # Path to the file you want to check
  _filePath="$1"

  # Define the thresholds
  _recent_threshold_days=60  # 60 days to consider for new updates
  _update_check_days=30      # Don't update NEW if it was already set within the last 30 days

  # Check if the path is a symlink
  if [ -L "${_filePath}" ]; then
    _target_file="$(readlink -f "${_filePath}")"
    # Get the file's modification time in seconds since epoch
    _file_mod_time=$(stat -c %Y "${_target_file}")
  else
    # Get the file's modification time in seconds since epoch
    _file_mod_time=$(stat -c %Y "${_filePath}")
  fi

  # Calculate the time difference in minutes
  _time_diff_minutes=$(( (_current_time - _file_mod_time) / 60 ))

  # Calculate the time difference in days
  _time_diff_days=$(( _time_diff_minutes / 1440 ))

  # Calculate the last update check time (from some state file, if exists)
  if [ -f "${_filePath}.lastupdate" ]; then
    _last_update_time=$(cat "${_filePath}.lastupdate")
  else
    _last_update_time=0
  fi

  _last_update_diff_days=$(( (_current_time - _last_update_time) / 86400 ))  # 86400 seconds in a day

  # Check if the file was modified within the last 30 minutes
  if [ "${_time_diff_minutes}" -lt 30 ]; then
    _crtLastMod=NEW
  # Check if the file was modified within the last 60 days and not marked NEW in the last 30 days
  elif [ "${_time_diff_days}" -le "${_recent_threshold_days}" ] && [ "${_last_update_diff_days}" -ge "${_update_check_days}" ]; then
    _crtLastMod=NEW
    echo ${_current_time} > "${_filePath}.lastupdate"
  else
    _crtLastMod=OLD
  fi
}

_if_le_hm_ssl_crt_key_copy() {
  if [ -e "${_leCrtPath}/fullchain.pem" ]; then
    _crtPath="${_leCrtPath}/fullchain.pem"
  elif [ -e "${_leCrtPath}/cert.pem" ]; then
    _crtPath="${_leCrtPath}/cert.pem"
  fi
  if [ -e "${_crtPath}" ]; then
    if [ -L "${_crtPath}" ]; then
      _crtPathR="$(readlink -n "${_crtPath}")"
      if [ -f "${_leCrtPath}/${_crtPathR}" ]; then
        rm -f /etc/ssl/private/${_hmFront}.crt
        cp -a ${_leCrtPath}/${_crtPathR} /etc/ssl/private/${_hmFront}.crt
      fi
    else
      rm -f /etc/ssl/private/${_hmFront}.crt
      cp -a ${_crtPath} /etc/ssl/private/${_hmFront}.crt
    fi
  fi
  _keyPath="${_leCrtPath}/privkey.pem"
  if [ -e "${_keyPath}" ]; then
    if [ -L "${_keyPath}" ]; then
      _keyPathR="$(readlink -n "${_keyPath}")"
      if [ -f "${_leCrtPath}/${_keyPathR}" ]; then
        rm -f /etc/ssl/private/${_hmFront}.key
        cp -a ${_leCrtPath}/${_keyPathR} /etc/ssl/private/${_hmFront}.key
      fi
    else
      rm -f /etc/ssl/private/${_hmFront}.key
      cp -a ${_keyPath} /etc/ssl/private/${_hmFront}.key
    fi
  fi
}

_le_hm_ssl_check_update() {
  _leCrtPath=
  _exeLe="${_usEr}/tools/le/dehydrated"
  if [ -e "${_usEr}/log/domain.txt" ]; then
    _hmFront=$(cat ${_usEr}/log/domain.txt 2>&1)
    _hmFront=$(echo -n ${_hmFront} | tr -d "\n" 2>&1)
  fi
  if [ -e "${_usEr}/log/extra_domain.txt" ]; then
    _hmFrontExtra=$(cat ${_usEr}/log/extra_domain.txt 2>&1)
    _hmFrontExtra=$(echo -n ${_hmFrontExtra} | tr -d "\n" 2>&1)
  fi
  if [ -z "${_hmFront}" ]; then
    if [ -e "${_usEr}/.drush/hostmaster.alias.drushrc.php" ]; then
      _hmFront=$(cat ${_usEr}/.drush/hostmaster.alias.drushrc.php \
        | grep "uri'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    fi
  fi
  if [ ! -z "${_hmFront}" ]; then
    _leCrtPath="${_usEr}/tools/le/certs/${_hmFront}"
  fi
  if [ -x "${_exeLe}" ] \
    && [ ! -z "${_hmFront}" ] \
    && [ -e "${_leCrtPath}/fullchain.pem" ]; then
    _DOM=$(date +%e)
    _DOM=${_DOM//[^0-9]/}
    _RDM=$((RANDOM%25+6))
    if [ "${_DOM}" = "${_RDM}" ] || [ -e "${_usEr}/static/control/force-ssl-certs-rebuild.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/site.${_hmFront}.cert-x1-rebuilt.info" ]; then
        _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
        mkdir -p ${_usEr}/log/ctrl
        touch ${_usEr}/log/ctrl/site.${_hmFront}.cert-x1-rebuilt.info
      else
        _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
      fi
    else
      _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
    fi
    if [ ! -z "${_hmFrontExtra}" ]; then
      echo "Running LE cert check directly for hostmaster ${_HM_U} with ${_hmFrontExtra}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} --domain ${_hmFront} --domain ${_hmFrontExtra}"
      wait
    else
      echo "Running LE cert check directly for hostmaster ${_HM_U}"
      su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} --domain ${_hmFront}"
      wait
    fi
  fi
  _crtLastMod=OLD
  _if_le_hm_ssl_old "${_leCrtPath}/fullchain.pem"
  if [ "${_crtLastMod}" = "NEW" ]; then
    echo "Copying NEW LE cert for hostmaster ${_hmFront} to /etc/ssl/private/"
    _if_le_hm_ssl_crt_key_copy
  else
    echo "No new LE cert for hostmaster ${_hmFront} to copy"
  fi
}

# Client LE notices are ON unless explicitly disabled. The per-account override
# in /root/.<user>.octopus.cnf (already sourced into scope by _account_process)
# wins over the global default frozen from /root/.barracuda.cnf; only the
# literal NO disables. tr is used instead of ${x^^} so it stays portable.
_le_client_notify_on() {
  local _v
  _v=$(echo "${_LE_CLIENT_NOTIFY}" | tr -d "\"' " | tr '[:lower:]' '[:upper:]')
  [ "${_v}" = "NO" ] && return 1
  return 0
}

# Build and send the Let's Encrypt renewal incident report for THIS account
# from its own night log. The operator (server admin _ADMIN_EMAIL, the
# _MY_EMAIL from /root/.barracuda.cnf) gets the full per-account detail every
# night; the affected client (_CLIENT_EMAIL from this account's .octopus.cnf,
# kept in sync with log/email.txt) gets an actionable notice, throttled to once
# per 7 days per failing site so a dead clone does not mail them nightly.
# Reading ONLY this account's log and using ONLY this account's own resolved
# _CLIENT_EMAIL is what guarantees the client notice can never reach the wrong
# account. Operator mail also carries any non-LE backend incident lines so the
# move to per-account logs does not lose the old _thisLog catch-all.
_le_account_report() {
  local _acctLog _fails _nonle _throttle _now _markerDir _marker _fresh
  local _site _cdom _calt _ctype _cdetail _reason _opBody _clBody _clList _reply
  _acctLog="$(_acct_night_log "${_usEr}")"
  [ -r "${_acctLog}" ] || return 0
  _fails="$(_le_extract_failures "${_acctLog}")"
  ###
  ### Operator catch-all for non-validation backend + account/order-level ACME
  ### errors. The rich _le_extract_failures path covers per-domain validation
  ### failures; this restores the old _thisLog _incident_detection coverage of
  ### the ACME urn:* tokens (badNonce/serverInternal/rateLimited surfacing
  ### outside a per-domain detail block) now that per-account output left
  ### _thisLog. The `grep -v '^\["'` drops the per-domain jsonsh dump lines so a
  ### normal validation failure is not also echoed here (already in the report).
  ###
  _nonle="$(grep -E -a \
    'Remote PerformValidation RPC failed|ModuleNotFoundError|Traceback|Drush command terminated abnormally|ArgumentCountError|THIS SITE IS BROKEN|urn:ietf:params:acme:error:|urn:acme:error:serverInternal' \
    "${_acctLog}" 2>/dev/null | grep -v -E '^\["' | sort -u | head -n 40)"
  [ -z "${_fails}" ] && [ -z "${_nonle}" ] && return 0
  _throttle=7
  _now=$(date +%s)
  _markerDir="${_usEr}/log/ctrl"
  mkdir -p "${_markerDir}"

  ###
  ### Operator report -- full per-account detail, every night, unless incident
  ### reporting is silenced (_INCIDENT_REPORT OFF/NO, matching the old gate).
  ###
  if [ -n "${_ADMIN_EMAIL}" ] \
    && [ "${_INCIDENT_REPORT}" != "OFF" ] \
    && [ "${_INCIDENT_REPORT}" != "NO" ]; then
    _opBody="LE (HTTPS certificate) renewal report for account ${_HM_U} on ${_hName}"$'\n'
    if [ -n "${_fails}" ]; then
      _opBody="${_opBody}"$'\n'"Sites failing Let's Encrypt renewal:"$'\n'
      while IFS=$'\x1f' read -r _site _cdom _calt _ctype _cdetail; do
        [ -z "${_cdom}" ] && continue
        _reason="$(_le_reason "${_ctype}" "${_cdetail}")"
        _opBody="${_opBody}"$'\n'"  Site: ${_site}"$'\n'"    Certificate names: ${_calt:-${_cdom}}"$'\n'"    Cause: ${_reason}"$'\n'"    LE detail [${_ctype}]: ${_cdetail}"$'\n'
      done <<EOF
${_fails}
EOF
    fi
    if [ -n "${_nonle}" ]; then
      _opBody="${_opBody}"$'\n'"Other backend incidents detected in this account's run:"$'\n'"${_nonle}"$'\n'
    fi
    _opBody="${_opBody}"$'\n'"Full account log: ${_acctLog}"$'\n'
    echo "Sending LE/incident operator report for ${_HM_U} to ${_ADMIN_EMAIL} on $(date)"
    echo "${_opBody}" \
      | s-nail -s "LE renewal/incident report: ${_HM_U} on ${_hName}" "${_ADMIN_EMAIL}"
  fi

  ###
  ### Client report -- only on LE failures, opt-out aware, throttled per site.
  ### Skip entirely when disabled or when there is no real external client
  ### address (empty or the local "root" alias used on operator master accounts).
  ###
  [ -z "${_fails}" ] && return 0
  _le_client_notify_on || return 0
  if [ -z "${_CLIENT_EMAIL}" ] || [ "${_CLIENT_EMAIL}" = "root" ]; then
    return 0
  fi
  _clList=""
  while IFS=$'\x1f' read -r _site _cdom _calt _ctype _cdetail; do
    [ -z "${_cdom}" ] && continue
    _marker="${_markerDir}/le-notify.$(echo "${_cdom}" | tr -c 'a-zA-Z0-9._-' '_').info"
    _fresh=YES
    if [ -f "${_marker}" ]; then
      if [ "$(( (_now - $(stat -c %Y "${_marker}" 2>/dev/null || echo 0)) / 86400 ))" -lt "${_throttle}" ]; then
        _fresh=NO
      fi
    fi
    [ "${_fresh}" = "NO" ] && continue
    _reason="$(_le_reason "${_ctype}" "${_cdetail}")"
    _clList="${_clList}"$'\n'"  - ${_cdom} -- ${_reason}"$'\n'"      Details: ${_cdetail}"$'\n'
    touch "${_marker}"
  done <<EOF
${_fails}
EOF
  [ -z "${_clList}" ] && return 0
  _clBody="Hello,"$'\n'
  _clBody="${_clBody}"$'\n'"Automatic HTTPS (Let's Encrypt SSL) certificate renewal failed for the"$'\n'"following site(s) in your hosting account on ${_hName}:"$'\n'"${_clList}"
  _clBody="${_clBody}"$'\n'"While a certificate cannot be renewed, this check runs and fails again every"$'\n'"night, so please take one of these actions:"$'\n'
  _clBody="${_clBody}"$'\n'"  - If the site is still in use: update its domain DNS (A/AAAA records) to"$'\n'"    point to this server, and the certificate will renew automatically."$'\n'
  _clBody="${_clBody}"$'\n'"  - If the site or alias is no longer used: please disable Encryption (SSL)"$'\n'"    for it, or remove the obsolete domain alias, to stop these daily"$'\n'"    failures and notices."$'\n'
  _clBody="${_clBody}"$'\n'"This is an automated message from your hosting platform."$'\n'
  # Reply-To the account owner (else the server admin) so a client's reply
  # reaches a human, not the undeliverable root@<host> envelope sender. Only set
  # when it resolves to a real address (non-empty, not "root", has an @).
  _reply="${_MY_OCTO_EMAIL}"
  if [ -z "${_reply}" ] || [ "${_reply}" = "root" ]; then
    _reply="${_ADMIN_EMAIL}"
  fi
  echo "Sending LE client notice for ${_HM_U} to ${_CLIENT_EMAIL} on $(date)"
  if [ -n "${_reply}" ] && [ "${_reply}" != "root" ] && [[ "${_reply}" =~ @ ]]; then
    echo "${_clBody}" \
      | s-nail -S replyto="${_reply}" -s "Action needed: HTTPS certificate renewal failed for one or more of your sites" "${_CLIENT_EMAIL}"
  else
    echo "${_clBody}" \
      | s-nail -s "Action needed: HTTPS certificate renewal failed for one or more of your sites" "${_CLIENT_EMAIL}"
  fi
}

_delete_this_platform() {
  _run_drush8_hmr_cmd "hosting-task @platform_${_T_PFM_NAME} delete --force"
  echo "Old empty platform_${_T_PFM_NAME} will be deleted"
}

_check_old_empty_platforms() {
  _provision_running && { echo "INFO: provision task active -- skipping empty-platform cleanup"; return; }
  if [ "${_hostedSys}" = "YES" ]; then
    if [[ "${_hName}" =~ "demo.aegir.cc" ]] \
      || [ -e "${_usEr}/static/control/platforms.info" ]; then
      _DO_NOTHING=YES
    else
      if [ -n "${_DEL_OLD_EMPTY_PLATFORMS}" ] \
        && [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
        _DO_NOTHING=YES
      else
        _DEL_OLD_EMPTY_PLATFORMS="60"
      fi
    fi
  fi
  if [ ! -z "${_DEL_OLD_EMPTY_PLATFORMS}" ]; then
    if [ "${_DEL_OLD_EMPTY_PLATFORMS}" -gt 0 ]; then
      echo "_DEL_OLD_EMPTY_PLATFORMS is set to \
        ${_DEL_OLD_EMPTY_PLATFORMS} days on ${_HM_U} instance"
      for _Platform in `find ${_usEr}/.drush/platform_* -maxdepth 1 -mtime \
        +${_DEL_OLD_EMPTY_PLATFORMS} -type f | sort`; do
        _T_PFM_NAME=$(echo "${_Platform}" \
          | sed "s/.*platform_//g; s/.alias.drushrc.php//g" \
          | awk '{ print $1}' 2>&1)
        _T_PFM_ROOT=$(cat ${_Platform} \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        _T_PFM_SITE=$(grep "${_T_PFM_ROOT}/sites/" \
          ${_usEr}/.drush/*.drushrc.php \
          | grep site_path 2>&1)
        if [ -z "$(_detect_real_docroot "${_T_PFM_ROOT}")" ]; then
          # Version-agnostic emptiness: no index.php at the (already docroot-
          # corrected) alias root nor under web/docroot/html. Do NOT key on
          # sites/all (D8+ dropped it); the old ${_T_PFM_ROOT}/vendor guard was
          # dead for D8+ since the corrected root is already the web/ docroot.
          if _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_PLATFORMS_CLEANUP \
            || _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; then
            mkdir -p ${_usEr}/undo
            mv -f ${_usEr}/.drush/platform_${_T_PFM_NAME}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
            echo "GHOST platform ${_T_PFM_ROOT} detected and moved to ${_usEr}/undo/"
          else
            echo "GHOST platform ${_T_PFM_ROOT} detected (dry-run; set _GHOST_PLATFORMS_CLEANUP=YES in /root/.${_HM_U}.octopus.cnf or /root/.barracuda.cnf to move)"
          fi
        fi
        if [[ "${_T_PFM_SITE}" =~ ".restore" ]]; then
          echo "WARNING: ghost site leftover found: ${_T_PFM_SITE}"
        fi
        if [ -z "${_T_PFM_SITE}" ] \
          && [ -e "${_T_PFM_ROOT}/sites/all" ]; then
          _delete_this_platform
        fi
      done
    fi
  fi
}

_purge_cruft_machine() {

  if [ ! -z "${_DEL_OLD_TMP}" ] && [ "${_DEL_OLD_TMP}" -gt 0 ]; then
    _PURGE_TMP="${_DEL_OLD_TMP}"
  else
    _PURGE_TMP="0"
  fi

  if [ ! -z "${_DEL_OLD_BACKUPS}" ] && [ "${_DEL_OLD_BACKUPS}" -gt 0 ]; then
    _PURGE_BACKUPS="${_DEL_OLD_BACKUPS}"
  else
    _PURGE_BACKUPS="14"
    if [ "${_hostedSys}" = "YES" ]; then
      _PURGE_BACKUPS="7"
    fi
  fi

  _LOW_NR="2"
  _PURGE_CTRL="14"

  find ${_usEr}/log/ctrl/*cert-x1-rebuilt.info \
    -mtime +${_PURGE_CTRL} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/log/ctrl/le-notify.*.info \
    -mtime +${_PURGE_CTRL} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/log/ctrl/plr* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/log/ctrl/*rom-fix.info \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${_usEr}/clients/*/backups/* -mtime +${_PURGE_BACKUPS} -exec \
    rm -rf {} \; &> /dev/null
  find ${_usEr}/backup-exports/* -mtime +${_PURGE_TMP} -type f -exec \
    rm -rf {} \; &> /dev/null

  find ${_usEr}/distro/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/distro/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/static/*/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/static/*/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -exec rm -f {} \; &> /dev/null

  find ${_usEr}/distro/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/distro/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/files/tmp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null
  find ${_usEr}/static/*/sites/*/private/temp/* \
    -mtime +${_PURGE_TMP} -type f -exec rm -f {} \; &> /dev/null

  find /home/${_HM_U}.ftp/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find /home/${_HM_U}.ftp/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  chown -R ${_HM_U}:users ${_usEr}/tools/le
  mkdir -p ${_usEr}/static/trash
  chown ${_HM_U}.ftp:users ${_usEr}/static/trash &> /dev/null
  find ${_usEr}/static/trash/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  for i in $(dir -d /home/${_HM_U}.ftp/platforms/* 2>/dev/null); do
    if [ -e "${i}" ]; then
      _RevisionTest=$(ls ${i} \
        | wc -l \
        | tr -d "\n" 2>&1)
      if [ "${_RevisionTest}" -lt "${_LOW_NR}" ] \
        && [ ! -z "${_RevisionTest}" ]; then
        if [ -d "/home/${_HM_U}.ftp/platforms" ]; then
          chattr -i /home/${_HM_U}.ftp/platforms
          chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
        fi
        _tStamp=$(date +%y%m%d-%H%M%S)
        [ -d "/var/backups/ghost/${_HM_U}/${_tStamp}" ] || mkdir -p /var/backups/ghost/${_HM_U}/${_tStamp}
        echo "Moving ${i} to /var/backups/ghost/${_HM_U}/${_tStamp}"
        mv -f ${i} /var/backups/ghost/${_HM_U}/${_tStamp}/
      fi
    fi
  done

  for i in $(dir -d ${_usEr}/distro/* 2>/dev/null); do
    if [ -d "${i}" ]; then
      if [ ! -d "${i}/keys" ]; then
        mkdir -p ${i}/keys
      fi
      _RevisionTest=$(ls ${i} | wc -l 2>&1)
      if [ "${_RevisionTest}" -lt 2 ] && [ ! -z "${_RevisionTest}" ]; then
        echo "_RevisionTest is ${_RevisionTest}"
        _tStamp=$(date +%y%m%d-%H%M%S)
        mkdir -p ${_usEr}/undo/dist/${_tStamp}
        mv -f ${i} ${_usEr}/undo/dist/${_tStamp}/ &> /dev/null
        echo "GHOST revision ${i} detected and moved to ${_usEr}/undo/dist/${_tStamp}/"
      fi
    fi
  done

  for i in $(dir -d ${_usEr}/distro/* 2>/dev/null); do
    if [ -e "${i}" ]; then
      _distTrNr=$(echo ${i} \
        | cut -d'/' -f6 \
        | awk '{ print $1}' 2> /dev/null)
      if [ -d "/home/${_HM_U}.ftp/platforms" ]; then
        chattr -i /home/${_HM_U}.ftp/platforms
        chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
      fi
      if [ ! -e "${i}/keys" ]; then
        mkdir -p ${i}/keys
        chown ${_HM_U}.ftp:${_WEBG} ${i}/keys &> /dev/null
        chmod 02775 ${i}/keys &> /dev/null
      fi
      if [ ! -e "/home/${_HM_U}.ftp/platforms/${_distTrNr}" ]; then
        mkdir -p /home/${_HM_U}.ftp/platforms/${_distTrNr}
      fi
      if [ -e "${i}/keys" ] && [ ! -e "/home/${_HM_U}.ftp/platforms/${_distTrNr}/keys" ]; then
        ln -sfn ${i}/keys /home/${_HM_U}.ftp/platforms/${_distTrNr}/keys
      fi
      if [ -e "/home/${_HM_U}.ftp/platforms/data" ]; then
        _tStamp=$(date +%y%m%d-%H%M%S)
        [ -d "/var/backups/ghost/${_HM_U}/${_tStamp}" ] || mkdir -p /var/backups/ghost/${_HM_U}/${_tStamp}
        mv -f /home/${_HM_U}.ftp/platforms/data /var/backups/ghost/${_HM_U}/${_tStamp}/platforms_data
      fi
      for _PlatformDir in `find ${i}/* \
        -maxdepth 0 \
        -type d 2>/dev/null`; do
        _CodebaseName=$(basename "${_PlatformDir}" 2>/dev/null)
        [ "${_CodebaseName}" = "keys" ] && continue
        _Codebase=$(_detect_real_docroot "${_PlatformDir}")
        [ -n "${_Codebase}" ] && [ -d "${_Codebase}/sites" ] || continue
        ln -sfn ${_Codebase}/sites /home/${_HM_U}.ftp/platforms/${_distTrNr}/${_CodebaseName}
        echo "Fixed ${_CodebaseName} in ${_distTrNr} symlink to ${_Codebase}/sites for ${_HM_U}.ftp"
      done
    fi
  done
}

###--------------------###
### When executed directly (not sourced), process exactly one account. The
### orchestrator (owl.sh) already applied the load gate and the
### vhost.d/proxied/CANCELLED eligibility checks before invoking us.
if [ "${0##*/}" = "10-account.sh" ]; then
  if ! command -v _run_drush8_hmr_cmd > /dev/null 2>&1 \
    || ! command -v _daily_process > /dev/null 2>&1; then
    echo "FATAL ERROR: night libraries (night.inc.sh/20-sites.sh) not loaded; aborting"
    exit 1
  fi
  night_load_run_env
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  _usEr="$1"
  if [ -z "${_usEr}" ] || [ ! -d "${_usEr}" ]; then
    echo "FATAL ERROR: 10-account.sh requires a valid account path argument"
    exit 1
  fi
  _account_process
fi
