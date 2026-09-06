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
# Default only: every worker sources /root/.barracuda.cnf after this
# file (night_load_run_env), so the cnf value wins; the literal keeps
# the read well-defined and fail-closed if a worker is ever driven
# outside that chain.
_GOACCESS_ALL=NO

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=dev
export _xSrl=588855devT01
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/20-sites.sh" ] && . /var/xdrago/night/20-sites.sh
# Fail closed: the two libraries are delivered by independent fNN fetches, so
# this worker can land ahead of a night.inc.sh that has no in-flight gate --
# and an undefined function returns 127, which the reap's "! _night_boa_pass_active"
# would read as "no pass running". Defined only if the real one is absent
command -v _night_boa_pass_active > /dev/null 2>&1 \
  || _night_boa_pass_active() { return 0; }
# Same reason, and the same direction as the reap gate: every
# "_provision_running && bail" is fail-OPEN when the function is missing, so the
# cleanup would run through a live Provision task. Deliberately the BROAD
# substring form rather than a copy of the anchored library body: it runs only
# while the library is briefly behind, and over-matching there just skips a
# cleanup. A stub claiming a task is always active would instead spin the drain
# loop below for its full 60s and defer every relocation, every night.
command -v _provision_running > /dev/null 2>&1 \
  || _provision_running() { pgrep -f provision > /dev/null 2>&1; }
# Same skew reason: night.inc.sh carries the real _acct_group, but this worker
# is fetched on its own serial and can land ahead of it -- an undefined
# function returns 127 with empty output, which would make the account chowns
# below emit a bare "user:" and reset the group instead of leaving it alone.
if ! declare -F _acct_group > /dev/null 2>&1; then
_acct_group() {
  # Group that owns an account's tree. Derived, never a literal: an account
  # converted to a private primary group named after itself gets that group,
  # everything else (an unconverted box, root, www-data, an adopted odd
  # group) falls back to 'users' -- so a tool landing on an unconverted or
  # half-converted box leaves it exactly as it is today. Box-wide paths
  # (/data/conf, /data/u, the shared cores) keep 'users' and never use this.
  # $1 = account name (oN, oN.ftp, oN.<sub>) or a path under /data/disk/<oN>
  # or /var/aegir (the master keeps 'users' in this phase).
  local _a="${1}" _g
  case "${_a}" in
    /var/aegir|/var/aegir/*|aegir|root|www-data) echo "users"; return 0 ;;
    /data/disk/*) _a="${_a#/data/disk/}"; _a="${_a%%/*}" ;;
    */*) echo "users"; return 0 ;;
  esac
  _a="${_a%%.*}"
  [ -n "${_a}" ] || { echo "users"; return 0; }
  _g=$(id -gn "${_a}" 2> /dev/null)
  [ "${_g}" = "${_a}" ] || _g="users"
  echo "${_g}"
}
fi

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
  # if the path does not exist yet, do nothing (Ægir creates it on first use and a
  # later run relocates it).
  [ -d "${_src}" ] || return 0

  local _ug
  _ug=$(stat -c '%U:%G' "${_src}" 2>/dev/null)
  [ -n "${_ug}" ] || return 0

  # mkdir -p is a silent no-op on a link to a directory and chown follows it,
  # so a symlink planted at the destination would take the chown and then the
  # whole rsync. The store lives under static/, which is group-writable.
  if [ -L "${_dst}" ]; then
    echo "backups-on-static: ${_dst} is a symlink; left ${_src} as real dir"
    return 0
  fi
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
    rsync -a --no-devices --no-specials --remove-source-files "${_src}/" "${_dst}/" 2>/dev/null \
      || { echo "backups-on-static: move failed ${_src} -> ${_dst}; left as real dir"; return 0; }
    find "${_src}/" -mindepth 1 -depth -type d -empty -delete 2>/dev/null
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
  # filesystem so the Ægir backup-download hardlinks keep working (hardlinks can
  # not cross filesystems). The leading-dot names are skipped by the site/orphan
  # scan (like static/files/.archived). Gated on static/files being a SEPARATE
  # filesystem (no benefit otherwise), kill-switchable, idempotent, non-fatal.
  local _acct="${_usEr}"
  local _static="${_acct}/static/files"

  # Kill-switch: box-wide or per-account.
  [ -f "/data/conf/disable_backups_on_static_fs.cnf" ] && return 0
  [ -f "${_acct}/static/control/no_backups_on_static_fs.info" ] && return 0

  # static/files must exist and resolve to a DIFFERENT device than the account root
  # (else the relocation gives no protection). static/files is a separate disk only
  # for large accounts moved to attached storage -- which is exactly the case this
  # protects; on a default single-filesystem box this is a deliberate no-op.
  [ -e "${_static}" ] || return 0
  # ${_acct}/static is 02775 and group-writable by the account's shell
  # identities, so the tenant can replace static/files
  # with a symlink of their choosing -- and every path below is derived from it,
  # with root doing the mkdir, the chown and the rsync at the far end. Both
  # gates here dereference, and a link to a tmpfs (/run, /dev/shm) even passes
  # the different-device test. The only supported placements are in-account or
  # the attached store under /mnt; refuse anything else.
  local _statR _acctR
  _statR=$(realpath -e -- "${_static}" 2>/dev/null) || return 0
  # Resolve BOTH sides: comparing a realpath against a raw prefix silently
  # refuses a legitimate account whose root is reached through a link.
  _acctR=$(realpath -e -- "${_acct}" 2>/dev/null) || return 0
  case "${_statR}/" in
    "${_acctR}"/*|/mnt/*) : ;;
    *)
      echo "backups-on-static: ${_static} resolves outside the account and /mnt; skipping"
      return 0
    ;;
  esac
  local _acctDev _statDev
  _acctDev=$(stat -c '%d' "${_acct}" 2>/dev/null)
  _statDev=$(stat -L -c '%d' "${_static}" 2>/dev/null)
  [ -n "${_acctDev}" ] && [ -n "${_statDev}" ] || return 0
  [ "${_acctDev}" != "${_statDev}" ] || return 0

  # Fast idempotent path: if neither dir is a real dir pending a one-time migration
  # (already a symlink, or absent), just normalise the symlink targets and return --
  # no queue pause needed for a no-op (the common case after the first relocation).
  local _need=NO
  { [ -d "${_acct}/backups" ]        && [ ! -L "${_acct}/backups" ]; }        && _need=YES
  { [ -d "${_acct}/backup-exports" ] && [ ! -L "${_acct}/backup-exports" ]; } && _need=YES
  if [ "${_need}" = "NO" ]; then
    _relocate_one_backup_dir "${_acct}/backups"        "${_static}/.backups"
    _relocate_one_backup_dir "${_acct}/backup-exports" "${_static}/.backup-exports"
    return 0
  fi

  # A real one-time migration is pending. Serialise the parallel per-account fan-out
  # with a real flock (the kernel releases it if this process dies -- no stale-lock
  # guessing), then PAUSE the Ægir task queue with the dedicated, self-healing stop
  # file so no NEW task starts mid-move. runner.sh honours /run/boa_queue_stop.pid
  # (parent exit + per-child skip); clear.sh purges a leaked one after 3h and /run
  # clears on reboot, so it can never freeze the queue. The _provision_running
  # interlock still drains any already-running task first.
  local _lockfd
  exec {_lockfd}>/run/.boa_backups_relocate.flock 2>/dev/null || return 0
  if ! flock -n "${_lockfd}"; then
    exec {_lockfd}>&-
    return 0
  fi

  local _stop="/run/boa_queue_stop.pid" _madeStop=NO
  [ -e "${_stop}" ] || { echo "$$" > "${_stop}" 2>/dev/null && _madeStop=YES; }

  # Drain any in-flight task (bounded ~60s); with the queue paused none starts anew.
  local _t=0
  while _provision_running && [ "${_t}" -lt 30 ]; do sleep 2; _t=$((_t + 1)); done

  if _provision_running; then
    echo "backups-on-static: provision task still active after wait -- deferring relocation for ${_acct}"
  else
    _relocate_one_backup_dir "${_acct}/backups"        "${_static}/.backups"
    _relocate_one_backup_dir "${_acct}/backup-exports" "${_static}/.backup-exports"
  fi

  # Release the queue (only if WE set it and still own it -- verify the recorded PID
  # so we never delete another op's pause) and the flock.
  [ "${_madeStop}" = "YES" ] && [ "$(cat "${_stop}" 2>/dev/null)" = "$$" ] && rm -f "${_stop}"
  flock -u "${_lockfd}"
  exec {_lockfd}>&-
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
  # .tmp sits in the tenant's own, never-immutable home; rm -rf refuses to
  # follow only the FINAL component, so a link planted at .tmp would send this
  # at <target>/cache instead.
  [ -L "/home/${_HM_U}.ftp/.tmp" ] \
    || rm -rf /home/${_HM_U}.ftp/.tmp/cache
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
      _BCC_EMAIL="inbox@boa.io"
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
      elif grep -q "^_CLIENT_EMAIL=" /root/.${_HM_U}.octopus.cnf 2>/dev/null; then
        sed -i "s/^_CLIENT_EMAIL=.*/_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"/g" /root/.${_HM_U}.octopus.cnf
        wait
        _CLIENT_EMAIL=${_F_CLIENT_EMAIL}
      else
        echo "_CLIENT_EMAIL=\"${_F_CLIENT_EMAIL}\"" >> /root/.${_HM_U}.octopus.cnf
        _CLIENT_EMAIL=${_F_CLIENT_EMAIL}
      fi
    fi

    # The email healer above kept the cnf honest against log/email.txt, but
    # its plan-identity siblings could disagree with their log/ stamps
    # forever (a migrated cnf is exactly that state). Same discipline for
    # the plan trio: the log/ stamp is the witness, replace-if-present,
    # append-if-absent.
    for _idPair in "_CLIENT_OPTION:option" "_CLIENT_SUBSCR:subscr" "_CLIENT_CORES:cores"; do
      _idVar="${_idPair%%:*}"
      _idFile="${_usEr}/log/${_idPair##*:}.txt"
      [ -s "${_idFile}" ] || continue
      _idVal=$(cat "${_idFile}" 2>/dev/null | tr -d "\n")
      _idVal=${_idVal//[^a-zA-Z0-9]/}
      [ -z "${_idVal}" ] && continue
      if grep -q "^${_idVar}=\"${_idVal}\"" /root/.${_HM_U}.octopus.cnf 2>/dev/null; then
        _DO_NOTHING=YES
      elif grep -q "^${_idVar}=" /root/.${_HM_U}.octopus.cnf 2>/dev/null; then
        sed -i "s/^${_idVar}=.*/${_idVar}=\"${_idVal}\"/g" /root/.${_HM_U}.octopus.cnf
        wait
      else
        echo "${_idVar}=\"${_idVal}\"" >> /root/.${_HM_U}.octopus.cnf
      fi
    done
  fi
  # The ltd worker rebuilds ~/.drush inside its own unlock/relock span every
  # three minutes; the relock below landing on such a rebuild leaves it half
  # done (EPERM on every write). Hold this account FIRST -- with the marker
  # in place the worker will not enter it (its per-account guard) -- so the
  # wait only has to cover a worker already inside this account's own span.
  # The marker carries this pid: a killed pass must not hold the account.
  echo $$ > /run/night-account-${_HM_U}.pid
  # The worker's pid file names its pid: a worker killed mid-pass leaves the
  # file behind until clear.sh sweeps it, and the nightly must not stall on a
  # dead one. Bounded on purpose; proceeding after the bound is the old race
  # narrowed to "worker still inside this account", so it leaves a witness.
  _nightWait=0
  while [ -e "/run/manage_ltd_users.pid" ] \
    && kill -0 "$(cat /run/manage_ltd_users.pid 2>/dev/null)" 2>/dev/null \
    && [ ${_nightWait} -lt 180 ]; do
    sleep 5
    _nightWait=$((_nightWait + 5))
  done
  [ ${_nightWait} -ge 180 ] \
    && echo "${_HM_U}: the ltd worker is still running after ${_nightWait} s; unlocking anyway"
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
  if [ "${_ENABLE_GOACCESS}" = "YES" ] \
    && { [ "${_GOACCESS_ALL}" = "YES" ] \
      || [ -e "/etc/boa/.goaccess.all.cnf" ]; }; then
    _if_gen_goaccess "ALL"
  fi
  echo "Done for ${_usEr}"
  _le_account_report
  _ghost_account_report
  _enable_chattr ${_HM_U}.ftp
  rm -f /run/night-account-${_HM_U}.pid
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
        | grep -E "^[[:space:]]*'uri'[[:space:]]*=>" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
    fi
  fi
  if [ ! -z "${_hmFront}" ]; then
    _leCrtPath="${_usEr}/tools/le/certs/${_hmFront}"
  fi
  if [ ! -z "${_hmFront}" ] \
    && [ -e "${_usEr}/tools/le/.ctrl/dont-overwrite-${_hmFront}.pid" ]; then
    ### Same immutable-marker contract as the per-site nightly leg. Only the
    ### dehydrated run is gated; the copy to /etc/ssl/private below still
    ### happens, so a manually replaced hostmaster cert propagates.
    echo "LE renewal skipped for hostmaster ${_hmFront} -- immutable dont-overwrite marker present"
  elif [ -x "${_exeLe}" ] \
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
    _marker="${_markerDir}/le-notify.$(printf '%s' "${_cdom}" | tr -c 'a-zA-Z0-9._-' '_').info"
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
  if [ -z "${_reply}" ] || [ "${_reply}" = "root" ] \
    || [[ "${_reply}" =~ ^root@ ]]; then
    # root and the derived root@<fqdn> self-hosted admin identity are both
    # local-only mailboxes -- as undeliverable for a client reply as bare root.
    _reply="${_ADMIN_EMAIL}"
  fi
  echo "Sending LE client notice for ${_HM_U} to ${_CLIENT_EMAIL} on $(date)"
  if [ -n "${_reply}" ] && [ "${_reply}" != "root" ] \
    && ! [[ "${_reply}" =~ ^root@ ]] && [[ "${_reply}" =~ @ ]]; then
    echo "${_clBody}" \
      | s-nail -S replyto="${_reply}" -s "Action needed: HTTPS certificate renewal failed for one or more of your sites" "${_CLIENT_EMAIL}"
  else
    echo "${_clBody}" \
      | s-nail -s "Action needed: HTTPS certificate renewal failed for one or more of your sites" "${_CLIENT_EMAIL}"
  fi
}

# Ghost-site client notices follow the LE gate model: ON unless the literal NO,
# per-account octopus.cnf override wins over the barracuda.cnf default.
_ghost_client_notify_on() {
  local _v
  _v=$(echo "${_GHOST_CLIENT_NOTIFY}" | tr -d "\"' " | tr '[:lower:]' '[:upper:]')
  [ "${_v}" = "NO" ] && return 1
  return 0
}

# Build and send the ghost-site notice for THIS account from its own night log.
# A ghost site is a registration (Drush alias + nginx vhost) whose site
# directory no longer exists -- typically an install or clone that failed or
# was rolled back. The nightly _cleanup_ghost_drushrc sweep already logs each
# one (and moves the backend leftovers aside when _GHOST_SITES_CLEANUP=YES),
# but a record still present in the account's own Aegir front-end can only be
# removed there, and any task run on it re-creates the backend leftovers -- so
# the account owner gets an actionable notice, throttled per site. Only the
# post-grace "GHOST drushrc" lines are matched, which the sweep emits ONLY
# after confirming the front-end record still exists (_hmr_context_exists):
# a ghost whose node the customer already deleted is logged as a backend
# leftover instead and cleaned without any mail, since there is nothing they
# could see or act on. Never matched either: the single-night grace line, the
# SKIPPED classifications, the vhost/platform/.restore variants. Same source
# discipline as _le_account_report: only THIS account's log and THIS
# account's _CLIENT_EMAIL, so a notice can never reach the wrong account.
_ghost_account_report() {
  local _acctLog _ghosts _throttle _now _markerDir _marker _fresh
  local _site _ghList _clBody _reply
  _acctLog="$(_acct_night_log "${_usEr}")"
  [ -r "${_acctLog}" ] || return 0
  _ghosts="$(awk '
    /^GHOST drushrc for [^ ]+ detected and moved to / { print $4; next }
    /^GHOST drushrc for [^ ]+ detected \(dry-run/ { print $4 }
  ' "${_acctLog}" 2>/dev/null | sort -u)"
  [ -z "${_ghosts}" ] && return 0
  _ghost_client_notify_on || return 0
  if [ -z "${_CLIENT_EMAIL}" ] || [ "${_CLIENT_EMAIL}" = "root" ]; then
    return 0
  fi
  # Ghosts are not urgent (the dead record is the only thing left), so the
  # throttle is much longer than the 7-day LE one to keep mail volume low.
  _throttle=30
  _now=$(date +%s)
  _markerDir="${_usEr}/log/ctrl"
  mkdir -p "${_markerDir}"
  _ghList=""
  # One record per line, read literally: ${_ghosts} comes from the night log
  # and an unquoted expansion here would word-split it and glob it against the
  # cwd (_account_process cd'd into the hostmaster site dir), putting local
  # filenames into a customer-facing notice.
  while IFS= read -r _site; do
    [ -n "${_site}" ] || continue
    _marker="${_markerDir}/ghost-notify.$(printf '%s' "${_site}" | tr -c 'a-zA-Z0-9._-' '_').info"
    _fresh=YES
    if [ -f "${_marker}" ]; then
      if [ "$(( (_now - $(stat -c %Y "${_marker}" 2>/dev/null || echo 0)) / 86400 ))" -lt "${_throttle}" ]; then
        _fresh=NO
      fi
    fi
    [ "${_fresh}" = "NO" ] && continue
    _ghList="${_ghList}"$'\n'"  - ${_site}"
    touch "${_marker}"
  done <<EOF
${_ghosts}
EOF
  [ -z "${_ghList}" ] && return 0
  _clBody="Hello,"$'\n'
  _clBody="${_clBody}"$'\n'"The nightly maintenance on ${_hName} found broken leftover site"$'\n'"registration(s) in your hosting account:"$'\n'"${_ghList}"$'\n'
  _clBody="${_clBody}"$'\n'"Each of these is a record of a site that has no directory on the server"$'\n'"any more -- typically an install or clone that failed or was rolled back,"$'\n'"so only its registration was left behind. The record still shows up in"$'\n'"your Aegir control panel and keeps being re-detected until it is removed"$'\n'"there; the server cannot remove it for you, because the control panel"$'\n'"re-creates the backend records on the next task run."$'\n'
  _clBody="${_clBody}"$'\n'"How to remove it in your Aegir control panel (takes a minute):"$'\n'
  _clBody="${_clBody}"$'\n'"  - If you do not need the site: open the site's page in the control"$'\n'"    panel, run Disable first if the site still shows as enabled (the"$'\n'"    Delete button appears only on a disabled site), then run Delete."$'\n'"    If Delete fails or never finishes, note the number at the end of"$'\n'"    the site page's address (it looks like /node/12345), then open"$'\n'"    /node/12345/delete in your browser and confirm -- this removes the"$'\n'"    stuck record directly."$'\n'
  _clBody="${_clBody}"$'\n'"  - If you still need the site: open the site's page and re-run the"$'\n'"    failed task (Install or Clone), or delete the broken record and"$'\n'"    create the site afresh."$'\n'
  _clBody="${_clBody}"$'\n'"These records point at no site data on the server, so removing them"$'\n'"does not touch any of your working sites, and nothing is deleted on the"$'\n'"server side by this process."$'\n'
  _clBody="${_clBody}"$'\n'"This is an automated message from your hosting platform."$'\n'
  _reply="${_MY_OCTO_EMAIL}"
  if [ -z "${_reply}" ] || [ "${_reply}" = "root" ] \
    || [[ "${_reply}" =~ ^root@ ]]; then
    # root and the derived root@<fqdn> self-hosted admin identity are both
    # local-only mailboxes -- as undeliverable for a client reply as bare root.
    _reply="${_ADMIN_EMAIL}"
  fi
  echo "Sending ghost-site client notice for ${_HM_U} to ${_CLIENT_EMAIL} on $(date)"
  if [ -n "${_reply}" ] && [ "${_reply}" != "root" ] \
    && ! [[ "${_reply}" =~ ^root@ ]] && [[ "${_reply}" =~ @ ]]; then
    echo "${_clBody}" \
      | s-nail -S replyto="${_reply}" -s "Action suggested: broken leftover site record(s) in your control panel" "${_CLIENT_EMAIL}"
  else
    echo "${_clBody}" \
      | s-nail -s "Action suggested: broken leftover site record(s) in your control panel" "${_CLIENT_EMAIL}"
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

_purge_hits_under_account() {
  # Re-anchor each hit fed in on stdin before deleting it. The static/* globs
  # in _purge_cruft_machine are expanded by the shell, which resolves symlinks
  # in every component, and ${_usEr}/static is 02775 and group-writable by the
  # account's shell identities -- so a tenant-planted link points the pattern
  # at another account's tree. Gate on
  # the RESOLVED path rather than refusing symlinks, because the site files/
  # and private/ links into this account's own store are legitimate. The store
  # may sit on attached storage under /mnt; nothing else is a supported
  # placement. Reads _usEr.
  local _f _r _acct _store
  _acct=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 0
  # No /mnt restriction: this is the account's OWN static/files, resolved --
  # a tenant cannot aim it -- and migratefs relocates the store to whatever
  # --target the operator passed (/mnt is only the auto-detected default), so
  # an /mnt-only test silently disables the purge on a relocated account.
  _store=$(realpath -e -- "${_usEr}/static/files" 2>/dev/null) || _store=
  while IFS= read -r -d '' _f; do
    _r=$(realpath -e -- "${_f}" 2>/dev/null) || continue
    case "${_r}/" in
      "${_acct}"/*) rm -f -- "${_r}" &> /dev/null ; continue ;;
    esac
    [ -n "${_store}" ] || continue
    case "${_r}/" in
      "${_store}"/*) rm -f -- "${_r}" &> /dev/null ;;
    esac
  done
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

  # These globs are expanded by the SHELL, which resolves symlinks in every
  # component, and ${_usEr}/static is 02775 and group-writable by the account's
  # shell identities -- so a link planted at
  # any level aims the same pattern at another account's tree and root does the
  # deleting. find -P is not the fix: the site files/ and private/ components
  # are legitimately symlinks into this account's own store, and refusing them
  # would stop the purge working at all. Re-anchor every hit instead.
  find ${_usEr}/static/*/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/sites/*/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account

  find ${_usEr}/static/*/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account
  find ${_usEr}/static/*/sites/*/private/files/backup_migrate/*/* \
    -mtime +${_PURGE_BACKUPS} -type f -print0 2>/dev/null | _purge_hits_under_account

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

  # /home/<user>.ftp is the tenant's own (chrooted) home and, unlike a backend
  # account root, is never immutable, so .tmp and tmp can be swapped for
  # symlinks. The shell expands the /* glob THROUGH such a link, handing find
  # real starting points inside the target, and rm -rf then reaps an arbitrary
  # tree. Purge only a real directory. ! -name ".*" keeps the glob's
  # dotfile-skipping shape, so the .ctrl.<tree>.<serial>.pid marker that
  # manage_ltd_users.sh keeps in .tmp is left alone.
  for _tmpDir in "/home/${_HM_U}.ftp/.tmp" "/home/${_HM_U}.ftp/tmp"; do
    [ -d "${_tmpDir}" ] && [ ! -L "${_tmpDir}" ] || continue
    find "${_tmpDir}" -mindepth 1 -maxdepth 1 ! -name ".*" \
      -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  done
  find ${_usEr}/.tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  find ${_usEr}/tmp/* \
    -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null

  # Both writes below land inside this account's own tree, so the group is
  # derived from the account rather than hardcoded; 'users' on an unconverted box.
  local _acctGrp _igHit
  _acctGrp=$(_acct_group "${_HM_U}")
  # Drift probe: the credential-bearing paths (~/.drush aliases, backups,
  # config, tools, the hostmaster sites, every drushrc.php under static) are
  # re-grouped by the octopus arm only, so a stale writer or a hand chown
  # between releases would sit unseen for a release cycle. One early-quit
  # find; instgrp reclaim is the file half alone (no identities, no lock),
  # idempotent, so the nightly may run it. An UNCONVERTED account is probed
  # too: a copy or a root-run restore can land its tree in another
  # account's named group there, and reclaim hands it back to the box-wide
  # group -- the same exposure class, which the converted-only gate missed.
  if [ -x "/opt/local/bin/instgrp" ]; then
    # backups may be a link into the static store (relocated backups): probe
    # where the files are. The static leg is bounded to the depth where a
    # site's drushrc.php lives (<platform>[/web]/sites/<uri>/drushrc.php),
    # so the clean case does not traverse every files/ tree.
    _igBak=$(readlink -f -- "${_usEr}/backups" 2>/dev/null)
    _igHit=$(find -P ${_usEr}/.drush ${_igBak:-${_usEr}/backups} ${_usEr}/config ${_usEr}/tools \
      ${_usEr}/aegir/distro/*/sites -xdev \
      ! -group "${_acctGrp}" ! -group www-data ! -group root -print -quit 2>/dev/null)
    if [ -z "${_igHit}" ]; then
      _igHit=$(find -P ${_usEr}/static -xdev -maxdepth 5 -name drushrc.php \
        ! -group "${_acctGrp}" ! -group www-data ! -group root -print -quit 2>/dev/null)
    fi
    if [ -n "${_igHit}" ]; then
      echo "DRIFT: ${_HM_U}: paths outside group ${_acctGrp} (first: ${_igHit}); running instgrp reclaim"
      bash /opt/local/bin/instgrp reclaim ${_HM_U}
    fi
  fi
  chown -R ${_HM_U}:${_acctGrp} ${_usEr}/tools/le
  # static/ is tenant-writable (02775, no sticky) and trash/ is handed to the
  # tenant, so the tenant can swap the directory for a symlink. mkdir -p then
  # succeeds silently on the target, a bare chown retargets it, and the glob
  # trash/* resolves through the link -- which made root chown an arbitrary
  # directory and rm -rf aged entries inside it. Drop a planted link first, act
  # only on a real directory, keep the chown off any link, and purge with find
  # on the bare path (a trailing slash would make find follow a link again).
  [ -L "${_usEr}/static/trash" ] && rm -f ${_usEr}/static/trash &> /dev/null
  mkdir -p ${_usEr}/static/trash
  if [ -d "${_usEr}/static/trash" ] && [ ! -L "${_usEr}/static/trash" ]; then
    chown -h ${_HM_U}.ftp:${_acctGrp} ${_usEr}/static/trash &> /dev/null
    find ${_usEr}/static/trash -mindepth 1 \
      -mtime +${_PURGE_TMP} -exec rm -rf {} \; &> /dev/null
  fi

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
      # An installer creates the new distro/NNN empty and fills it over the
      # following minutes, and the keys/ mkdir above scores it 1 by itself,
      # so an under-populated revision is NOT evidence of a ghost on its own:
      # this used to reap the revision a running install was still building
      # into, leaving the installer cd-ing into a path that no longer existed
      # and extracting whole platform trees into the account's home instead.
      # Two independent brakes, because neither alone is sufficient: the mtime
      # test (a live revision is touched continuously; a real ghost is stale
      # for hours, and the keys/ mkdir defers its first sighting by one night)
      # and the in-flight test (owl.sh gates once at entry, while the octopus
      # pass drops boa_run.pid per account -- so it must be re-checked HERE)
      if [ "${_RevisionTest}" -lt 2 ] && [ ! -z "${_RevisionTest}" ] \
        && [ -z "$(find ${i} -maxdepth 0 -mmin -60 2>/dev/null)" ] \
        && ! _night_boa_pass_active; then
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
      # platforms/ is in the tenant's own home and is mutable for the whole
      # run (_account_process cleared its immutable bit), so it can be a
      # planted symlink: the /* glob then names real entries inside the
      # target and root strips +i off a tree of the tenant's choosing.
      if [ -d "/home/${_HM_U}.ftp/platforms" ] \
        && [ ! -L "/home/${_HM_U}.ftp/platforms" ]; then
        chattr -i /home/${_HM_U}.ftp/platforms
        chattr -i /home/${_HM_U}.ftp/platforms/* &> /dev/null
      fi
      if [ ! -e "${i}/keys" ]; then
        mkdir -p ${i}/keys
        chown ${_HM_U}.ftp:${_WEBG} ${i}/keys &> /dev/null
        chmod 02775 ${i}/keys &> /dev/null
      fi
      # platforms/ and its per-revision children are in the tenant's own home
      # and are mutable for the whole run, so a link planted at either level
      # makes the mkdir -p a silent no-op on the target and both ln -sfn below
      # create (or replace) entries inside a directory of the tenant's
      # choosing. Neither is ever legitimately a symlink; platforms/<rev> is
      # root-maintained, so drop a planted link there the usual way.
      [ -L "/home/${_HM_U}.ftp/platforms" ] && continue
      # Inline rather than _desymlink_planted: that helper lives in night.inc.sh,
      # which is fetched on its own serial, and this file carries no fallback --
      # an undefined function returns 127 and the guard would silently no-op.
      [ -L "/home/${_HM_U}.ftp/platforms/${_distTrNr}" ] \
        && rm -f "/home/${_HM_U}.ftp/platforms/${_distTrNr}" &> /dev/null
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
