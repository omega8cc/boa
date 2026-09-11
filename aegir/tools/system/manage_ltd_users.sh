#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=pro
export _xSrl=588855proT01

_OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
# The || binds to tr (rc 0 on empty input), so the fallback never fired.
_hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n')"
[ -n "${_hName}" ] || _hName="$(hostname -f 2>/dev/null)"
# Script-scope default: the main-body cleanup uses _TMP, but until now the
# only assignment lived inside _ok_create_user, so every ordinary pass ran
# `rm -f /*.txt` against the filesystem root (reproduced live 2026-08-24).
_TMP="/var/tmp"

_usrGroup=users
_WEBG=www-data

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

# One channel for anything this pass has to say to the operator: a dated line
# in the durable incident log, the pass log, and the same text mailed once a
# day per condition unless _INCIDENT_REPORT is OFF. The box config is read
# with grep, never sourced: this pass carries live loop state (_USER, _usrLtd,
# _ALLD_DIR, _ESC_LUPASS) that sourcing the config would silently overwrite
# mid-iteration.
# $1 = rate-limit key ("" mails every pass), $2 = subject, $3 = detail
_ltd_notice() {
  local _key="${1}"
  local _sub="${2}"
  local _dtl="${3}"
  local _stamp=""
  local _mail=""
  local _rprt=""
  local _seen=0
  mkdir -p /var/log/boa 2>/dev/null
  echo "ALRT: ${_sub}${_dtl:+: ${_dtl}}"
  echo "$(date) ${_sub}${_dtl:+: ${_dtl}}" \
    >> /var/log/boa/manage_ltd.incident.log
  if [ -n "${_key}" ]; then
    _key="${_key//[^a-zA-Z0-9._-]/}"
    _stamp="/var/log/boa/manage-ltd-${_key}.alerted"
    _seen=$(stat -c %Y "${_stamp}" 2>/dev/null)
    _seen=${_seen:-0}
    if [ "$(( $(date +%s) - _seen ))" -lt 86400 ]; then
      return 0
    fi
    touch "${_stamp}"
  fi
  _rprt=$(grep -m1 -iE "^[[:space:]]*(export[[:space:]]+)?_INCIDENT_REPORT=" \
    /root/.barracuda.cnf 2>/dev/null | cut -d= -f2- | tr -cd 'A-Za-z')
  _rprt="${_rprt^^}"
  [ "${_rprt}" = "NO" ] && _rprt="OFF"
  [ "${_rprt}" = "OFF" ] && return 0
  _mail=$(grep -m1 -iE "^[[:space:]]*(export[[:space:]]+)?_MY_EMAIL=" \
    /root/.barracuda.cnf 2>/dev/null | cut -d= -f2- | tr -d "\"' \\\\" | tr -d '\n')
  [ -n "${_mail}" ] || return 0
  [[ "$(s-nail -V 2>&1)" =~ "built for Linux" ]] || return 0
  {
    echo "${_sub} on ${_hName}"
    echo
    [ -n "${_dtl}" ] && echo "${_dtl}"
    echo
    echo "Logged to /var/log/boa/manage_ltd.incident.log"
    echo
    echo "--"
    echo "This email has been sent by the BOA limited shell users worker"
  } | s-nail -s "ALERT [${_hName}]: ${_sub}" ${_mail}
}

# Section headers that appear more than once in a generated lshell config.
# lshell builds a strict ConfigParser and does not catch the duplicate-section
# error its read() raises, so ONE repeated header refuses the WHOLE file and
# every account on the box loses its shell -- not just the account named twice.
# Headers are compared with trailing blanks trimmed, as the parser reads them.
_ltd_conf_dup_sections() {
  local _cnf="${1}"
  [ -f "${_cnf}" ] || return 0
  sed -e 's/[[:space:]]*$//' -e '/^\[/!d' "${_cnf}" | sort | uniq -d
}

# Keep only the LAST stanza of every repeated section, in place. That is the
# precedence the satellite writer already uses when it re-emits an account (it
# strips the existing section, then appends the fresh one), and the one the
# account's own home follows: every client directory the pass visits re-points
# ~/sites with ln -sfn, so the surviving stanza is the one whose client
# directory the account is actually bound to when the pass ends.
_dedup_ltd_conf_sections() {
  local _cnf="${1}"
  local _dup=""
  [ -f "${_cnf}" ] || return 0
  _dup=$(_ltd_conf_dup_sections "${_cnf}")
  [ -n "${_dup}" ] || return 0
  awk 'BEGIN { _keep = 1 }
    { _hdr = $0; sub(/[[:space:]]*$/, "", _hdr) }
    FNR == NR { if (_hdr ~ /^\[/) { _cnt[_hdr] += 1 } ; next }
    _hdr ~ /^\[/ { _num[_hdr] += 1; _keep = (_num[_hdr] == _cnt[_hdr]) }
    _keep' "${_cnf}" "${_cnf}" > "${_cnf}.dedup" \
    && cat "${_cnf}.dedup" > "${_cnf}"
  rm -f "${_cnf}.dedup"
  _ltd_notice "dup-section" \
    "repeated lshell sections collapsed to the last stanza in the generated config" \
    "$(echo ${_dup} | tr '\n' ' ')"
}

# Passive-mirror tenant hold (2026-08-25 ruling: deny fully on standby).
# A tenant login on a mirror is a WRITE channel into the synced trees --
# credentials converge with the active BY DESIGN (.ssh synced, user store
# force-pushed), so only the shell can refuse them. serve.cnf does NOT
# exempt (web-only preview), and neither does the xmass in-flight signal:
# that signal opens at INIT, the window in which the copied-in production
# datadir and the freshly seeded trees are most exposed, and a tenant file
# modified on the mirror then permanently shadows the active's copy under
# the -u sync legs. The hold releases on the MARKER alone -- cutover step
# 15 removes it, as does an init unwind or a hand removal -- and this
# script runs every 3 minutes, so promotion is followed at once.
_LTD_STANDBY_HOLD=NO
if [ -e "/root/.standby.cnf" ]; then
  _LTD_STANDBY_HOLD=YES
fi

_standby_tenant_sweep() {
  # Enforce or release the tenant-shell hold; runs at the end of every
  # pass. Membership in lshellg is the record of "was a tenant shell", so
  # the flip is self-inverse: hold = tenant shells -> nologin (live
  # sessions killed), release = nologin members -> the shell the box-level
  # heal would give them (the exact conditional the per-user heal uses).
  local _lsh_usr _lsh_cur _lsh_restore _lsh_nologin
  _lsh_nologin="/usr/sbin/nologin"
  [ -x "${_lsh_nologin}" ] || _lsh_nologin="/bin/false"
  if [ -e "/usr/bin/mysecureshell" ] \
    && [ -e "/etc/ssh/sftp_config" ]; then
    _lsh_restore="/usr/bin/mysecureshell"
  else
    _lsh_restore="/usr/bin/lshell"
  fi
  # The record of WHO this hold flipped: release must restore exactly these
  # users and no one else -- a tenant an admin deliberately suspended (also
  # nologin) is not ours to re-enable.
  # /var/log/boa, NOT /var/backups/ltd/log: BOA.sh.txt rm -rf's the latter
  # on every release (its manage_ltd refresh block), and this file is the
  # SOLE input of the release below -- losing it strands every tenant at
  # nologin after promotion. /var/log/boa survives releases; its sweeps
  # match *.pid and *.log, neither of which this .txt name matches.
  local _lsh_rec="/var/log/boa/standby-held-shells.txt"
  if [ "${_LTD_STANDBY_HOLD}" = "YES" ]; then
    for _lsh_usr in $(getent group lshellg 2>/dev/null | cut -d: -f4 | tr ',' ' '); do
      _lsh_cur=$(getent passwd "${_lsh_usr}" 2>/dev/null | cut -d: -f7)
      if [ "${_lsh_cur}" = "/usr/bin/lshell" ] \
        || [ "${_lsh_cur}" = "/usr/bin/mysecureshell" ]; then
        # Record FIRST, flip second: a flip that outruns a failed record
        # write is a user the release can never restore.
        mkdir -p /var/log/boa 2>/dev/null
        grep -qxF "${_lsh_usr}" "${_lsh_rec}" 2>/dev/null \
          || echo "${_lsh_usr}" >> "${_lsh_rec}"
        grep -qxF "${_lsh_usr}" "${_lsh_rec}" 2>/dev/null || continue
        usermod -s "${_lsh_nologin}" "${_lsh_usr}" &> /dev/null
        pkill -KILL -u "${_lsh_usr}" &> /dev/null
        echo "$(date) LTD replication standby: tenant login held (${_lsh_usr})" \
          >> /var/log/boa/manage_ltd.incident.log
      fi
    done
  elif [ -s "${_lsh_rec}" ]; then
    # Restore ONLY recorded users, verify each restore actually landed, and
    # keep any failure in the record so the next pass retries it -- one
    # transient usermod failure must never become a permanent lockout.
    local _lsh_left=""
    while read -r _lsh_usr; do
      [ -n "${_lsh_usr}" ] || continue
      _lsh_cur=$(getent passwd "${_lsh_usr}" 2>/dev/null | cut -d: -f7)
      if [ -z "${_lsh_cur}" ]; then
        continue
      fi
      if [ "${_lsh_cur}" = "/usr/sbin/nologin" ] \
        || [ "${_lsh_cur}" = "/bin/false" ]; then
        usermod -s "${_lsh_restore}" "${_lsh_usr}" &> /dev/null
        _lsh_cur=$(getent passwd "${_lsh_usr}" 2>/dev/null | cut -d: -f7)
        if [ "${_lsh_cur}" = "${_lsh_restore}" ]; then
          echo "$(date) LTD standby hold released: tenant login restored (${_lsh_usr})" \
            >> /var/log/boa/manage_ltd.incident.log
        else
          _lsh_left="${_lsh_left}${_lsh_usr}\n"
          echo "$(date) LTD standby release: restore FAILED for ${_lsh_usr}, kept for retry" \
            >> /var/log/boa/manage_ltd.incident.log
        fi
      fi
    done < "${_lsh_rec}"
    if [ -n "${_lsh_left}" ]; then
      printf '%b' "${_lsh_left}" > "${_lsh_rec}"
    else
      rm -f "${_lsh_rec}"
    fi
  fi
}

_provision_running() {
  # Genuine task EXECUTIONS only. BOA spawns them as
  #   su -s /bin/bash - <user> -c "<php> /usr/bin/drush @<site> provision-<task>"
  # so a real task always carries the drush command token somewhere in its
  # process tree, and the php/su process running it always has provision on its
  # command line. The bare substring match this replaces reported "running" for
  # any command line that merely MENTIONED a provision path -- a checksum, an
  # editor, an operator's ssh probe, a monitoring loop. Mirrored from
  # night/night.inc.sh on purpose: this tool has no library to source.
  pgrep -f '(^| )provision-[a-z0-9-]+( |$)' > /dev/null 2>&1 && return 0
  # The front-end dispatch phase of a task carries no provision-* token: the
  # backend child is spawned only after bootstrap, and the post-hooks run after
  # it exits, so those windows were invisible. ( |$) is LOAD-BEARING -- without
  # it this also matches hosting-tasks and hosting-dispatch, the per-minute
  # pollers, which would pin the gate ON and disable every nightly cleanup.
  pgrep -f "hosting-task( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^([^ ]*/)?(php[0-9.]*|su|env|drush[0-9]*)( |$).*provision" > /dev/null 2>&1 && return 0
  return 1
}

_desymlink_planted() {
  # Strip a tenant-planted symlink at a root-maintained path before this pass
  # creates, chowns, chmods or writes it. The tenant owns its own home and the
  # static/control tree, so it controls these names; rm -f on a symlink removes
  # only the link (its target survives) and is a no-op on a regular file, so a
  # legitimate file and the tenant's own content are untouched. Args = paths.
  local _p
  for _p in "$@"; do
    [ -L "${_p}" ] && rm -f "${_p}" &> /dev/null
  done
  return 0
}
_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"
_wgetGet="--max-redirect=3 -q --tries=9 --wait=9 --user-agent='iCab'"
_aptAllow="--allow-unauthenticated"
_aptYesUnth="-y ${_aptAllow}"
_pthLog="/var/log/boa"

[ -e "/etc/boa/.pause_tasks_maint.cnf" ] && exit 0

# NB: no whole-script standby gate here, on purpose. The local-only
# reconciliation this script owns -- system users from clients/, per-user
# php.ini, FPM $user_socket includes, lshell membership -- must run on a
# replication standby exactly as anywhere (xmass relies on sub-users
# appearing on the target within minutes of clients/ landing, and a
# barracuda system pass on a standby needs its post-step). Only the two
# writers into replicated/rsynced state carry scoped standby gates below:
# the ghost-alias reaper and the drush alias-store rebuild.

if [ -x "/usr/bin/gpg2" ]; then
  _GPG=gpg2
else
  _GPG=gpg
fi

###-------------SYSTEM-----------------###

_os_detection_minimal() {
  _APT_UPDATE="apt-get update"
  _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
  _OS_LIST="excalibur daedalus chimaera beowulf buster bullseye bookworm trixie"
  for e in ${_OS_LIST}; do
    if [ "${e}" = "${_OS_CODE}" ]; then
      _APT_UPDATE="apt-get update --allow-releaseinfo-change"
    fi
  done
}
_os_detection_minimal

_apt_clean_update() {
  ${_APT_UPDATE} -qq 2>/dev/null
  _CALLER_SCRIPT="$(basename "${BASH_SOURCE[-1]}")"
  _CALLER_SCRIPT="${_CALLER_SCRIPT//[^a-zA-Z0-9._-]/_}"
  date +%s > "/run/_latest_apt_clean_update.${_CALLER_SCRIPT}.pid"
}

_if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] \
    || [[ "${_hName}" =~ ".aegir.cc"($) ]]; then
    _hostedSys=YES
  else
    _hostedSys=NO
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

_find_fast_mirror_early() {
  _isNetc="$(which netcat)"
  if [ ! -x "${_isNetc}" ] || [ -z "${_isNetc}" ]; then
    if [ ! -e "/etc/apt/apt.conf.d/00sandboxoff" ] \
      && [ -e "/etc/apt/apt.conf.d" ]; then
      echo "APT::Sandbox::User \"root\";" > /etc/apt/apt.conf.d/00sandboxoff
    fi
    _apt_clean_update
    apt-get install netcat-traditional ${_aptYesUnth} 2> /dev/null
    wait
  fi
  _ffMirr=/opt/local/bin/ffmirror
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2026-07.txt"
    [ -d "/var/backups" ] || mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "files.boa.io"  > ${_ffList}
      echo "files.o8.io" >> ${_ffList}
      echo "files.host8.biz" >> ${_ffList}
      echo "files.aegir.biz" >> ${_ffList}
      echo "files.aoboshi.com" >> ${_ffList}
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.boa.io"
      else
        _USE_MIR="files.boa.io"
      fi
    else
      _USE_MIR="files.boa.io"
    fi
  else
    _USE_MIR="files.boa.io"
  fi
  _urlDev="https://${_USE_MIR}/dev"
  _urlHmr="https://${_USE_MIR}/versions/${_tRee}/boa/aegir"
}

###----------------------------###
##    Manage ltd shell users    ##
###----------------------------###
#
# Remove dangerous stuff from the string.
_sanitize_string() {
  echo "$1" | sed 's/[\\\/\^\?\>\`\#\"\{\(\&\|\*]//g; s/\(['"'"'\]\)//g'
}
#
# Add allow-snail group if not exists.
_add_allow_snail_if_not_exists() {
  _SNAIL_EXISTS=$(getent group allow-snail 2>&1)
  if [[ ! "${_SNAIL_EXISTS}" =~ "allow-snail" ]]; then
    addgroup --system allow-snail &> /dev/null
  fi
}
#
# Add ltd-shell group if not exists.
_add_ltd_group_if_not_exists() {
  _LTD_EXISTS=$(getent group ltd-shell 2>&1)
  if [[ ! "${_LTD_EXISTS}" =~ "ltd-shell" ]]; then
    addgroup --system ltd-shell &> /dev/null
  fi
}
#
# The account's Drush 8 ini carried an active open_basedir list for years and
# nothing applied it, until websh started handing the file to the Drush 8 and
# composer it launches (2026-09-08): with open_basedir set php runs without its
# realpath cache and checks every file operation against every listed tree,
# uncached -- a hostmaster bootstrap of three seconds took a hundred and the
# per-minute queue runners loaded every box. open_basedir was never meant for
# the CLI (lshell users are confined by their own measures; the FPM ini keeps
# its list): the writers no longer set it, and this heals the files already on
# disk, once each. The file and its .drush directory are +i and the worker
# keeps them so: the edit is written into the existing inode (no rename, which
# an immutable directory refuses), never through a link in either place, and
# logged only when it took.
_drush_ini_open_basedir_off() {
  local _ini="${1}" _dir _imm=NO _tmp
  [ -n "${_ini}" ] && [ -f "${_ini}" ] && [ ! -L "${_ini}" ] || return 0
  _dir="${_ini%/*}"
  [ -d "${_dir}" ] && [ ! -L "${_dir}" ] || return 0
  grep -q "^open_basedir = " "${_ini}" 2> /dev/null || return 0
  if lsattr -d "${_ini}" 2> /dev/null | cut -d' ' -f1 | grep -q "i"; then
    _imm=YES
    chattr -i "${_ini}" 2> /dev/null
  fi
  _tmp=$(mktemp /root/.drush-ini.XXXXXX 2> /dev/null) || return 0
  if sed "s/^open_basedir = .*/;open_basedir =/" "${_ini}" > "${_tmp}" 2> /dev/null \
    && cat "${_tmp}" > "${_ini}" 2> /dev/null; then
    mkdir -p /var/log/boa 2> /dev/null
    echo "$(date 2>&1) NOTE: open_basedir removed from ${_ini} (never for the CLI)" \
      >> /var/log/boa/drush-ini.incident.log
  fi
  rm -f "${_tmp}"
  [ "${_imm}" = "YES" ] && chattr +i "${_ini}" 2> /dev/null
  return 0
}
# every account ini on the box, once per pass; a repaired file is silent after
_drush_ini_open_basedir_sweep() {
  local _i
  for _i in /home/*/.drush/php.ini /data/disk/o*/.drush/php.ini /var/aegir/.drush/php.ini; do
    _drush_ini_open_basedir_off "${_i}"
  done
}

# Enable chattr.
_enable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    # Group owning this account's tree, derived from the user this call
    # handles -- never the script-scope default, which is box-wide.
    local _accGrp
    _accGrp=$(_acct_group "$1")
    _U_HD="/home/$1/.drush"
    _U_TP="/home/$1/.tmp"
    _U_II="${_U_HD}/php.ini"
    if [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
      # Strip planted links BEFORE the deletes below act on these paths: a
      # tenant who swapped ~/.drush for a symlink would otherwise have root
      # rm -rf through it.
      _desymlink_planted "${_U_TP}" "${_U_HD}"
      _if_hosted_sys
      if [ "${_hostedSys}" = "YES" ]; then
        rm -rf ${_U_HD}/
      else
        rm -f ${_U_HD}/{drush_make,registry_rebuild,clean_missing_modules}
        rm -f ${_U_HD}/{drupalgeddon,drush_ecl,make_local,safe_cache_form*}
        rm -f ${_U_HD}/usr/{drush_make,registry_rebuild,clean_missing_modules}
        rm -f ${_U_HD}/usr/{drupalgeddon,drush_ecl,make_local,safe_cache_form*}
        rm -f ${_U_HD}/usr/{mydropwizard,utf8mb4_convert,backdrop}
        rm -f ${_U_HD}/.ctrl*
        rm -rf ${_U_HD}/{cache,drush.ini,*drushrc*,*.inc}
      fi
      mkdir -p ${_U_HD}/usr
      mkdir -p ${_U_TP}
      touch ${_U_TP}
      # Bare path, not ${_U_TP}/ -- a trailing slash makes find follow a
      # planted link and purge the target tree instead.
      find ${_U_TP} -mindepth 1 -mtime +0 -exec rm -rf {} \; &> /dev/null
      chown -h $1:${_accGrp} ${_U_TP}
      chown -h $1:${_accGrp} ${_U_HD}
      [ ! -L "${_U_TP}" ] && chmod 02755 ${_U_TP}
      [ ! -L "${_U_HD}" ] && chmod 02755 ${_U_HD}
      if [ ! -L "${_U_HD}/usr/registry_rebuild" ] \
        && [ -e "${_dscUsr}/.drush/usr/registry_rebuild" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/registry_rebuild \
          ${_U_HD}/usr/registry_rebuild
      fi
      if [ ! -L "${_U_HD}/usr/clean_missing_modules" ] \
        && [ -e "${_dscUsr}/.drush/usr/clean_missing_modules" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/clean_missing_modules \
          ${_U_HD}/usr/clean_missing_modules
      fi
      if [ ! -L "${_U_HD}/usr/drupalgeddon" ] \
        && [ -e "${_dscUsr}/.drush/usr/drupalgeddon" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/drupalgeddon \
          ${_U_HD}/usr/drupalgeddon
      fi
      if [ ! -L "${_U_HD}/usr/drush_ecl" ] \
        && [ -e "${_dscUsr}/.drush/usr/drush_ecl" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/drush_ecl \
          ${_U_HD}/usr/drush_ecl
      fi
      if [ ! -L "${_U_HD}/usr/safe_cache_form_clear" ] \
        && [ -e "${_dscUsr}/.drush/usr/safe_cache_form_clear" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/safe_cache_form_clear \
          ${_U_HD}/usr/safe_cache_form_clear
      fi
      if [ ! -L "${_U_HD}/usr/utf8mb4_convert" ] \
        && [ -e "${_dscUsr}/.drush/usr/utf8mb4_convert" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/utf8mb4_convert \
          ${_U_HD}/usr/utf8mb4_convert
      fi
      if [ ! -L "${_U_HD}/usr/backdrop" ] \
        && [ -e "${_dscUsr}/.drush/usr/backdrop" ]; then
        ln -sfn ${_dscUsr}/.drush/usr/backdrop \
          ${_U_HD}/usr/backdrop
      fi
    fi

    if [ -e "${_dscUsr}/tools/drush/drush.php" ]; then
      _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_dscUsr}/tools/drush/drush.php 2>&1)
    else
      _CHECK_USE_PHP_CLI=php84
    fi

    _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
    for e in ${_PHP_V}; do
      if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
        && [ ! -e "${_U_HD}/.ctrl.php${e}.${_xSrl}.pid" ]; then
        _PHP_CLI_UPDATE=YES
      fi
    done
    echo _PHP_CLI_UPDATE is ${_PHP_CLI_UPDATE} for $1

    if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
      || [ ! -e "${_U_II}" ] \
      || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
      mkdir -p ${_U_HD}
      rm -f ${_U_HD}/.ctrl.php*
      rm -f ${_U_II}
      if [ ! -z "${_T_CLI_VRN}" ]; then
        _USE_PHP_CLI="${_T_CLI_VRN}"
        echo "_USE_PHP_CLI is ${_USE_PHP_CLI} for $1 at ${_USER} WTF"
        echo "_T_CLI_VRN is ${_T_CLI_VRN}"
      else
        if [ -e "${_dscUsr}/tools/drush/drush.php" ]; then
          _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_dscUsr}/tools/drush/drush.php 2>&1)
        else
          _CHECK_USE_PHP_CLI=php84
        fi
        echo "_CHECK_USE_PHP_CLI is ${_CHECK_USE_PHP_CLI} for $1 at ${_USER}"
        if [[ "${_CHECK_USE_PHP_CLI}" =~ "php85" ]]; then
          _USE_PHP_CLI=8.5
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php84" ]]; then
          _USE_PHP_CLI=8.4
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php83" ]]; then
          _USE_PHP_CLI=8.3
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php82" ]]; then
          _USE_PHP_CLI=8.2
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php81" ]]; then
          _USE_PHP_CLI=8.1
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php80" ]]; then
          _USE_PHP_CLI=8.0
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php74" ]]; then
          _USE_PHP_CLI=7.4
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php73" ]]; then
          _USE_PHP_CLI=7.3
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php72" ]]; then
          _USE_PHP_CLI=7.2
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php71" ]]; then
          _USE_PHP_CLI=7.1
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php70" ]]; then
          _USE_PHP_CLI=7.0
        elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php56" ]]; then
          _USE_PHP_CLI=5.6
        fi
      fi
      echo _USE_PHP_CLI is ${_USE_PHP_CLI} for $1
      if [ "${_USE_PHP_CLI}" = "8.5" ]; then
        cp -af /opt/php85/lib/php.ini ${_U_II}
        _U_INI=85
      elif [ "${_USE_PHP_CLI}" = "8.4" ]; then
        cp -af /opt/php84/lib/php.ini ${_U_II}
        _U_INI=84
      elif [ "${_USE_PHP_CLI}" = "8.3" ]; then
        cp -af /opt/php83/lib/php.ini ${_U_II}
        _U_INI=83
      elif [ "${_USE_PHP_CLI}" = "8.2" ]; then
        cp -af /opt/php82/lib/php.ini ${_U_II}
        _U_INI=82
      elif [ "${_USE_PHP_CLI}" = "8.1" ]; then
        cp -af /opt/php81/lib/php.ini ${_U_II}
        _U_INI=81
      elif [ "${_USE_PHP_CLI}" = "8.0" ]; then
        cp -af /opt/php80/lib/php.ini ${_U_II}
        _U_INI=80
      elif [ "${_USE_PHP_CLI}" = "7.4" ]; then
        cp -af /opt/php74/lib/php.ini ${_U_II}
        _U_INI=74
      elif [ "${_USE_PHP_CLI}" = "7.3" ]; then
        cp -af /opt/php73/lib/php.ini ${_U_II}
        _U_INI=73
      elif [ "${_USE_PHP_CLI}" = "7.2" ]; then
        cp -af /opt/php72/lib/php.ini ${_U_II}
        _U_INI=72
      elif [ "${_USE_PHP_CLI}" = "7.1" ]; then
        cp -af /opt/php71/lib/php.ini ${_U_II}
        _U_INI=71
      elif [ "${_USE_PHP_CLI}" = "7.0" ]; then
        cp -af /opt/php70/lib/php.ini ${_U_II}
        _U_INI=70
      elif [ "${_USE_PHP_CLI}" = "5.6" ]; then
        cp -af /opt/php56/lib/php.ini ${_U_II}
        _U_INI=56
      fi
      if [ -e "${_U_II}" ]; then
        # open_basedir stays out of the CLI ini: it breaks Drush and turns the
        # realpath cache off (every file operation checked against every listed
        # tree, uncached); lshell users are confined by their own measures, and
        # the FPM ini keeps its own list
        _QTP=${_U_TP//\//\\\/}
        sed -i "s/.*open_basedir =.*/;open_basedir =/g"                      ${_U_II}
        wait
        sed -i "s/.*error_reporting =.*/error_reporting = 1/g"               ${_U_II}
        wait
        sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_U_II}
        wait
        sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_U_II}
        wait
        sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_U_II}
        wait
        sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_U_II}
        wait
        # Root-maintained stamps inside a tenant-owned .drush: the .ctrl.php*
        # rm above does not cover the tree stamp, and `echo >` follows a link
        # (truncating an existing target, creating a dangling one).
        _desymlink_planted "${_U_HD}/.ctrl.php${_U_INI}.${_xSrl}.pid" \
          "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid"
        echo > ${_U_HD}/.ctrl.php${_U_INI}.${_xSrl}.pid
        echo > ${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid
      fi
    fi

    _UQ="$1"
    chage -M 99999 ${_UQ} &> /dev/null
    _UPDATE_GEMS=NO
    ###
    ### Cleanup of no longer used/allowed Ruby Gems and NPM access leftovers
    ###
    [ -e "/home/${_UQ}/.rvm" ] && rm -rf /home/${_UQ}/.rvm*
    [ -e "/home/${_UQ}/.gem" ] && rm -rf /home/${_UQ}/.gem*
    [ -e "/home/${_UQ}/.npm" ] && rm -rf /home/${_UQ}/.npm*
    [ -e "/home/${_UQ}/.mkshrc" ] && rm -rf /home/${_UQ}/.mkshrc
    if [ "${_UQ}" = "${_USER}.ftp" ]; then
      [ ! -d "/home/${_UQ}/.composer" ] && su -s /bin/bash - ${_UQ} -c "mkdir ~/.composer"
    else
      [ -d "/home/${_UQ}/.composer" ] && rm -rf /home/${_UQ}/.composer
    fi
    ###
    ### Check if Ruby Gems and NPM access should be added or removed
    ###
    if [ -f "${_dscUsr}/static/control/compass.info" ]; then
      ###
      ### Check if Ruby Gems access needs an update
      ###
      if [ ! -e "/opt/user/gems/${_UQ}/gems/oily_png-1.1.1" ] \
        || [ ! -e "${_dscUsr}/log/.gems.build.rb.${_UQ}.${_xSrl}.txt" ]; then
        _UPDATE_GEMS=YES
      fi
      if [ "${_UQ}" = "${_USER}.ftp" ] \
        && [ ! -e "/opt/user/npm/${_UQ}/.npm-packages/bin" ] \
        && [ -e "/root/.allow.node.lshell.cnf" ]; then
        _UPDATE_GEMS=YES
      fi
    else
      ###
      ### Remove no longer used Ruby Gems and NPM access
      ###
      [ -e "/home/${_UQ}/.npm" ] && rm -rf /home/${_UQ}/.npm*
      [ -e "/opt/user/gems/${_UQ}" ] && rm -rf /opt/user/gems/${_UQ}
      [ -e "/opt/user/npm/${_UQ}" ] && rm -rf /opt/user/npm/${_UQ}
      [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.gems.build*
      [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.npm.build*
    fi
    if [ "${_UPDATE_GEMS}" = "YES" ]; then
      ###
      ### Ruby Gems are allowed for both main and client SSH accounts
      ###
      [ ! -d "/opt/user/gems/${_UQ}" ] && mkdir -p /opt/user/gems/${_UQ}
      chmod 1777 /opt/user/gems
      chown -R ${_UQ}:${_accGrp} /opt/user/gems/${_UQ}
      chown root:root /opt/user/gems
      if [ -d "/opt/user/gems/${_UQ}" ] \
        && [ -e "/usr/local/lib/ruby/gems/3.3.0/gems/oily_png-1.1.1" ] \
        && [ ! -e "/opt/user/gems/${_UQ}/gems/oily_png-1.1.1" ]; then
        cp -a /usr/local/lib/ruby/gems/3.3.0/gems /opt/user/gems/${_UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/specifications /opt/user/gems/${_UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/extensions /opt/user/gems/${_UQ}/
        cp -a /usr/local/lib/ruby/gems/3.3.0/doc /opt/user/gems/${_UQ}/
        chown -R ${_UQ}:${_accGrp} /opt/user/gems/${_UQ}
        [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.gems.build*
        touch ${_dscUsr}/log/.gems.build.rb.${_UQ}.${_xSrl}.txt
      fi
      ###
      ### Check if NPM support is allowed and if needs an update
      ### NOTE: It will be restricted to the main SSH account only
      ###
      if [ -e "/root/.allow.node.lshell.cnf" ] \
        && [ "${_UQ}" = "${_USER}.ftp" ] \
        && [ -x "/usr/bin/node" ] \
        && [ -e "/home/${_UQ}/static/control" ]; then
        if [ ! -e "/opt/user/npm/${_UQ}/.npm-packages/bin" ] \
          || [ ! -e "${_dscUsr}/log/.npm.build.${_UQ}.${_xSrl}.txt" ]; then
          [ ! -d "/opt/user/npm" ] && mkdir -p /opt/user/npm
          chown root:root /opt/user/npm
          chmod 1777 /opt/user/npm
          [ ! -d "/opt/user/npm/${_UQ}" ] && mkdir -p /opt/user/npm/${_UQ}
          [ ! -e "/home/${_UQ}/.npmrc" ] && su -s /bin/bash - ${_UQ} -c "echo 'prefix = /opt/user/npm/${_UQ}/.npm-packages' > ~/.npmrc"
          # chattr opens the referent: refuse a link the tenant planted at this
          # name, or root sets +i on whatever it points at.
          [ -e "/home/${_UQ}/.npmrc" ] && [ ! -L "/home/${_UQ}/.npmrc" ] \
            && chattr +i /home/${_UQ}/.npmrc
          mkdir -p /opt/user/npm/${_UQ}/.bundle
          mkdir -p /opt/user/npm/${_UQ}/.composer
          mkdir -p /opt/user/npm/${_UQ}/.config
          mkdir -p /opt/user/npm/${_UQ}/.npm
          mkdir -p /opt/user/npm/${_UQ}/.npm-packages/bin
          mkdir -p /opt/user/npm/${_UQ}/.npm-packages/lib/node_modules
          mkdir -p /opt/user/npm/${_UQ}/.sass-cache
          chown -R ${_UQ}:${_accGrp} /opt/user/npm/${_UQ}
          [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.npm.build*
          touch ${_dscUsr}/log/.npm.build.${_UQ}.${_xSrl}.txt
        fi
      else
        [ -e "/home/${_UQ}/.npm" ] && rm -rf /home/${_UQ}/.npm*
        [ -e "/opt/user/npm/${_UQ}" ] && rm -rf /opt/user/npm/${_UQ}
        [ -e "${_dscUsr}/log" ] && rm -f ${_dscUsr}/log/.npm.build*
      fi
    fi
    rm -f /home/${_UQ}/{.profile,.bash_logout,.bash_profile,.bashrc,.z_login,.zshrc}
    chage -M 90 ${_UQ} &> /dev/null

    if [ "$1" != "${_USER}.ftp" ]; then
      if [ -d "/home/$1/" ]; then
        chattr +i /home/$1/
      fi
    else
      # A *.ftp home is never made immutable, so every name below is tenant
      # replaceable; chattr always opens the referent. Test the bare path --
      # [ -L "x/" ] with a trailing slash resolves the link and is always false.
      if [ -d "/home/$1/platforms/" ] && [ ! -L "/home/$1/platforms" ]; then
        chattr +i /home/$1/platforms/
        chattr +i /home/$1/platforms/* &> /dev/null
      fi
    fi
    if [ -d "/home/$1/.drush/" ] && [ ! -L "/home/$1/.drush" ]; then
      chattr +i /home/$1/.drush/
      if [ -d "/home/$1/.drush/usr/" ] && [ ! -L "/home/$1/.drush/usr" ]; then
        chattr +i /home/$1/.drush/usr/
      fi
      if [ -f "/home/$1/.drush/php.ini" ] \
        && [ ! -L "/home/$1/.drush/php.ini" ]; then
        chattr +i /home/$1/.drush/*.ini
      fi
    fi
    if [ -d "/home/$1/.bee/" ] && [ ! -L "/home/$1/.bee" ]; then
      chattr +i /home/$1/.bee/
    fi
    if [ -d "/home/$1/.bazaar/" ] && [ ! -L "/home/$1/.bazaar" ]; then
      chattr +i /home/$1/.bazaar/
    fi
  fi
}
#
# Disable chattr.
_disable_chattr() {
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    if [ "$1" != "${_USER}.ftp" ]; then
      if [ -d "/home/$1/" ]; then
        chattr -i /home/$1/
      fi
    else
      # Mirrors the guards in _enable_chattr: same plantable names, same
      # dereference, inverse primitive (clearing +i on a root-protected path).
      if [ -d "/home/$1/platforms/" ] && [ ! -L "/home/$1/platforms" ]; then
        chattr -i /home/$1/platforms/
        chattr -i /home/$1/platforms/* &> /dev/null
      fi
    fi
    if [ -d "/home/$1/.drush/" ] && [ ! -L "/home/$1/.drush" ]; then
      chattr -i /home/$1/.drush/
      if [ -d "/home/$1/.drush/usr/" ] && [ ! -L "/home/$1/.drush/usr" ]; then
        chattr -i /home/$1/.drush/usr/
      fi
      if [ -f "/home/$1/.drush/php.ini" ] \
        && [ ! -L "/home/$1/.drush/php.ini" ]; then
        chattr -i /home/$1/.drush/*.ini
      fi
    fi
    if [ -d "/home/$1/.bee/" ] && [ ! -L "/home/$1/.bee" ]; then
      chattr -i /home/$1/.bee/
    fi
    if [ -d "/home/$1/.bazaar/" ] && [ ! -L "/home/$1/.bazaar" ]; then
      chattr -i /home/$1/.bazaar/
    fi
  fi
}
#
# Platform-level developer account (Adam, 2026-09-07). One extra account per
# client named in _LTD_PLATFORM_CLIENTS (root-owned /root/.<oN>.octopus.cnf,
# never a tenant file), granted only the platforms where EVERY site is that
# client's. It is an ordinary sub-account in every other respect (creation,
# password store, groups, reaper tokens) whose lshell path also carries the
# qualifying app roots, with the drush and composer commands re-added in its
# own section (lshell applies [<user>] last, after the group's minus-lists),
# and a root-placed ~/platforms farm so SFTP sees the same tree. Drush inside
# a locked vendor/drush runs in a timed, chmod-only window: the same bits
# provision's own cache-rebuild window flips, the de-typing patches never
# touched, opened when the account touches ~/.tmp/drush-window.request and
# closed by this worker once root's own clock says the minutes are up.
_LTD_PLATFORM_SUFFIX="-dev"
_LTD_PLATFORM_WINDOW_MIN=60
_LTD_PLATFORM_TOOLS="'composer', 'drush', 'drush10', 'drush11', 'drush8', 'vdrush', 'vendor/drush/drush/drush.php'"
#
# The docroot of a platform dir: index.php at the root or one level down.
_ltd_platform_docroot() {
  local _plat="${1%/}"
  local _sub=""
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
#
# The app root for a site dir (<docroot>/sites/<uri>): the docroot's parent
# when the docroot is the web/docroot/html child of a composer root, where
# vendor/ lives; the docroot itself otherwise.
_ltd_platform_approot() {
  local _site="${1%/}"
  local _doc=""
  local _up=""
  _doc=$(dirname "$(dirname "${_site}")")
  _up=$(dirname "${_doc}")
  case "$(basename "${_doc}")" in
    web|docroot|html)
      if [ -f "${_up}/composer.json" ] || [ -d "${_up}/vendor" ]; then
        _doc="${_up}"
      fi ;;
  esac
  printf '%s\n' "${_doc}"
}
#
# Fail-closed single-client test. Every site directory ON THE PLATFORM must
# resolve into the granted client's own farm: admin-owned sites appear in no
# farm at all, so "absent from the farm" means "someone I cannot see", never
# "not there". Prints the refusing directory (or reason) and fails; prints
# nothing and succeeds when the platform qualifies. Drupal and Backdrop only.
_ltd_platform_refuser() {
  local _root="${1}"
  local _client="${2}"
  local _doc=""
  local _site=""
  local _real=""
  local _lnk=""
  local _hit=""
  _doc=$(_ltd_platform_docroot "${_root}") || { printf '%s\n' "no docroot"; return 1; }
  if [ ! -d "${_doc}/sites" ]; then
    printf '%s\n' "no sites directory"
    return 1
  fi
  if [ ! -d "${_doc}/core" ] && [ ! -f "${_doc}/includes/bootstrap.inc" ]; then
    printf '%s\n' "not a Drupal or Backdrop platform"
    return 1
  fi
  for _site in "${_doc}"/sites/*/; do
    _site="${_site%/}"
    [ -f "${_site}/settings.php" ] || continue
    case "$(basename "${_site}")" in
      all|default) continue ;;
    esac
    _real=$(readlink -f "${_site}")
    _hit=""
    for _lnk in "${_client}"/*; do
      [ -L "${_lnk}" ] || continue
      if [ "$(readlink -f "${_lnk}")" = "${_real}" ]; then
        _hit="yes"
        break
      fi
    done
    if [ -z "${_hit}" ]; then
      printf '%s\n' "${_site}"
      return 1
    fi
  done
  return 0
}
#
# The qualifying app roots of a client, one per line: every platform that
# carries one of the client's sites, kept only when the whole platform is the
# client's. A refused platform is reported once a day, with the directory
# that refused it, and simply not granted.
_ltd_platform_roots() {
  local _client="${1}"
  local _acct="${2}"
  local _lnk=""
  local _tgt=""
  local _root=""
  local _seen=""
  local _why=""
  for _lnk in "${_client}"/*; do
    [ -L "${_lnk}" ] || continue
    _tgt=$(readlink -f "${_lnk}")
    [ -n "${_tgt}" ] && [ -d "${_tgt}" ] || continue
    _root=$(_ltd_platform_approot "${_tgt}")
    # lands inside single quotes in the root-written config: same class as
    # _PATH_DOM, and a path the class mutates is not granted at all
    if [ "${_root}" != "${_root//[^a-zA-Z0-9._\/-]/}" ]; then
      continue
    fi
    [ -n "${_root}" ] && [ -d "${_root}" ] || continue
    case " ${_seen} " in
      *" ${_root} "*) continue ;;
    esac
    _seen="${_seen} ${_root}"
    _why=$(_ltd_platform_refuser "${_root}" "${_client}")
    if [ -n "${_why}" ]; then
      # stdout of this function IS the grant list (command substitution in
      # the caller); the notice echoes, so it goes to stderr or the refused
      # root's own words would land in the path
      _ltd_notice "platform-refused-${_acct}-$(basename "${_root}")" \
        "platform ${_root} refused for ${_acct}" \
        "not single-client: ${_why}" >&2
      continue
    fi
    printf '%s\n' "${_root}"
  done
}
#
# The Drush window. A locked platform and a running site-local Drush exclude
# each other by construction (the lock's psr/log v1 overlay and console
# de-typing exist for Aegir's Drush 8; every modern Drush is typed against
# psr/log v3 and fatals at class load under PHP 8), so the window is a real
# unlock: provision's own provision-dunlock on each granted composer platform,
# run as the instance user, and provision-dlock at expiry. The request is a
# marker the account touches inside its own ~/.tmp (the home is immutable);
# root consumes it and keeps the clock in its own state file, because a
# tenant-owned mtime is not a clock. A platform an operator had already
# unlocked is recorded as such and left unlocked at expiry. Caveats, all
# documented: Aegir's Drush 8 cannot drive that platform's sites while it is
# unlocked, a site Verify re-locks it (the next pass unlocks again while the
# window is open), and provision's comments warn that a container compiled in
# the unlocked state may carry Drush's logger into what the web serves locked.
_ltd_platform_alias() {
  local _root="${1}"
  local _doc=""
  local _f=""
  _doc=$(_ltd_platform_docroot "${_root}") || return 1
  _f=$(grep -lF "'root' => '${_doc}'" /data/disk/${_USER}/.drush/platform_*.alias.drushrc.php 2>/dev/null | head -1)
  [ -n "${_f}" ] || return 1
  _f=$(basename "${_f}")
  _f=${_f#platform_}
  _f=${_f%.alias.drushrc.php}
  [ -n "${_f}" ] || return 1
  printf '%s\n' "${_f}"
}
# locked = the console de-typing is in place (the same test provision's
# provision_check_codebase_status() makes on Output.php)
_ltd_platform_locked() {
  local _out="${1}/vendor/symfony/console/Output/Output.php"
  [ -f "${_out}" ] || return 1
  if grep -qF "doWrite(string" "${_out}" || grep -qF ": void;" "${_out}"; then
    return 1
  fi
  return 0
}
_ltd_platform_task() {
  local _verb="${1}"
  local _alias="${2}"
  local _log="/var/backups/ltd/log/window-${_NOW}.log"
  echo "$(date) ${_USER}: drush8 @platform_${_alias} ${_verb}" >> "${_log}"
  su -s /bin/bash - ${_USER} -c "drush8 @platform_${_alias} ${_verb} -y" >> "${_log}" 2>&1
}
_ltd_platform_window_close() {
  local _acct="${1}"
  local _prev="/var/backups/ltd/window/${_acct}.prev"
  local _was=""
  local _root=""
  local _alias=""
  if [ -s "${_prev}" ]; then
    while read -r _was _root; do
      [ "${_was}" = "locked" ] && [ -n "${_root}" ] && [ -d "${_root}" ] || continue
      _alias=$(_ltd_platform_alias "${_root}") || continue
      _ltd_platform_task provision-dlock "${_alias}"
    done < "${_prev}"
  fi
  rm -f "/var/backups/ltd/window/${_acct}" "${_prev}"
}
_ltd_platform_window() {
  local _acct="${1}"
  local _roots="${2}"
  local _req="/home/${_acct}/.tmp/drush-window.request"
  local _state="/var/backups/ltd/window/${_acct}"
  local _prev="/var/backups/ltd/window/${_acct}.prev"
  local _root=""
  local _alias=""
  local _was=""
  [ -d /var/backups/ltd/window ] || mkdir -p /var/backups/ltd/window
  if [ -f "${_req}" ] && [ ! -L "${_req}" ]; then
    rm -f "${_req}"
    if [ ! -s "${_state}" ]; then
      echo "$(date) LTD platform account ${_acct}: drush window opened for ${_LTD_PLATFORM_WINDOW_MIN} min" \
        >> /var/log/boa/manage_ltd.incident.log
    fi
    # a renewal restarts the clock; the recorded prior states stay
    date +%s > "${_state}"
  fi
  if [ -s "${_state}" ] \
    && [ -n "$(find "${_state}" -maxdepth 0 -mmin -${_LTD_PLATFORM_WINDOW_MIN} 2>/dev/null)" ]; then
    for _root in ${_roots}; do
      [ -d "${_root}/vendor/drush" ] || continue
      _alias=$(_ltd_platform_alias "${_root}") || {
        _ltd_notice "platform-noalias-${_acct}-$(basename "${_root}")" \
          "platform ${_root}: no platform alias found for ${_USER}" \
          "the drush window for ${_acct} cannot unlock it"
        continue
      }
      if ! grep -qF " ${_root}" "${_prev}" 2>/dev/null; then
        _was="unlocked"
        _ltd_platform_locked "${_root}" && _was="locked"
        echo "${_was} ${_root}" >> "${_prev}"
      fi
      # idempotent on an unlocked platform, and what re-opens a platform a
      # site Verify re-locked mid-window
      _ltd_platform_locked "${_root}" && _ltd_platform_task provision-dunlock "${_alias}"
    done
  elif [ -e "${_state}" ] || [ -e "${_prev}" ]; then
    _ltd_platform_window_close "${_acct}"
    echo "$(date) LTD platform account ${_acct}: drush window closed" \
      >> /var/log/boa/manage_ltd.incident.log
  fi
}
#
# The SFTP side. MySecureShell sees the home plus root-placed links only, so
# each qualifying app root is linked under ~/platforms/<rev>-<codebase>; a
# link whose platform stopped qualifying goes the same pass. The home is
# immutable between passes, so it is opened and closed around the edit.
_ltd_platform_farm() {
  local _acct="${1}"
  local _roots="${2}"
  local _home="/home/${_acct}"
  local _farm="/home/${_acct}/platforms"
  local _root=""
  local _name=""
  local _lnk=""
  local _keep=""
  [ -d "${_home}" ] && [ ! -L "${_home}" ] || return 0
  chattr -i "${_home}" 2>/dev/null
  if [ -L "${_farm}" ] || { [ -e "${_farm}" ] && [ ! -d "${_farm}" ]; }; then
    rm -f "${_farm}"
  fi
  [ -d "${_farm}" ] || mkdir -p "${_farm}"
  chown root:root "${_farm}"
  chmod 0755 "${_farm}"
  for _root in ${_roots}; do
    _name="$(basename "$(dirname "${_root}")")-$(basename "${_root}")"
    _keep="${_keep} ${_name}"
    ln -sfn "${_root}" "${_farm}/${_name}"
  done
  for _lnk in "${_farm}"/*; do
    [ -L "${_lnk}" ] || continue
    case " ${_keep} " in
      *" $(basename "${_lnk}") "*) ;;
      *) rm -f "${_lnk}" ;;
    esac
  done
  if [ -n "${_keep}" ]; then
    cat > "${_farm}/README.txt" <<EOF
Platforms granted to this account are linked here, one per codebase, and are
also on your shell path. A Drupal 8+ platform is locked for Aegir's own Drush
between uses, and its site-local Drush cannot run while it is locked; to
unlock your platforms for ${_LTD_PLATFORM_WINDOW_MIN} minutes run:

  touch ~/.tmp/drush-window.request

then, within three minutes, cd into the platform and run vdrush. Touch it
again to extend. While a platform is unlocked, control-panel tasks on its
sites can fail and a site Verify re-locks it (reopened within three minutes);
at expiry every platform is locked again.
https://docs.boa.io/using/connecting/extra-accounts
EOF
    chmod 0644 "${_farm}/README.txt"
  else
    rm -f "${_farm}/README.txt"
  fi
  chattr +i "${_home}" 2>/dev/null
}
#
# One removal for every account this worker takes away: the reaper's zombies
# and a retired platform account alike. The home goes to the zombie backup,
# never to /dev/null.
_ltd_reap_account() {
  local _acct="${1}"
  local _parent="${2}"
  local _why="${3}"
  [ -d "/var/backups/zombie/deleted/${_NOW}" ] || mkdir -p /var/backups/zombie/deleted/${_NOW}
  # only this user's agent: -f matched every gpg-agent on the box
  id -u "${_acct}" &> /dev/null && pkill -9 -u "${_acct}" gpg-agent &> /dev/null
  _disable_chattr ${_acct}
  rm -rf /home/${_acct}/.gnupg
  deluser \
    --remove-home \
    --backup-to /var/backups/zombie/deleted/${_NOW} ${_acct} &> /dev/null
  rm -f /home/${_parent}.ftp/users/${_acct}
  rm -f "/var/backups/ltd/window/${_acct}" "/var/backups/ltd/window/${_acct}.prev"
  echo Zombie from etc.passwd ${_acct} killed
  if [ -n "${_why}" ]; then
    [ -d /var/log/boa ] || mkdir -p /var/log/boa
    echo "$(date) LTD account ${_acct} removed: ${_why}" >> /var/log/boa/manage_ltd.incident.log
  fi
  echo
}
#
# A platform account that left _LTD_PLATFORM_CLIENTS (or whose client
# directory is gone) is removed on the spot: its own section would vanish
# from the published config while the login stayed, which drops it to the
# group policy and the default path, i.e. wider than it ever was.
_ltd_platform_retire() {
  local _acct="${1}"
  _ltd_platform_window_close "${_acct}"
  _ltd_reap_account "${_acct}" "${_USER}" "platform account retired (not in _LTD_PLATFORM_CLIENTS of ${_USER})"
}
#
# Platform accounts of this instance, after the ordinary sub-accounts.
_manage_sec_platform() {
  local _client=""
  local _cdir=""
  local _nam=""
  local _acct=""
  local _roots=""
  local _r=""
  local _granted=""
  local _on=""
  local _ex=""
  for _client in ${_LTD_PLATFORM_CLIENTS}; do
    _client=${_client//[^a-zA-Z0-9._-]/}
    [ -n "${_client}" ] || continue
    _cdir="${_pthParentUsr}/clients/${_client}"
    if [ ! -d "${_cdir}" ] || [ -L "${_cdir}" ]; then
      _ltd_notice "platform-noclient-${_USER}-${_client}" \
        "platform account for ${_USER}: no client directory ${_cdir}" \
        "listed in _LTD_PLATFORM_CLIENTS; nothing granted"
      continue
    fi
    _nam=$(_ltd_name_from_client_dir "${_cdir}")
    [ -n "${_nam}" ] || continue
    # the reserved token: a hyphen no client directory can produce
    # (_ltd_name_from_client_dir keeps [a-zA-Z0-9] only), inside the oN.
    # namespace the standby hold and the reaper's shape both recognise. The
    # duplicate-section collapse is a safety net, never a naming scheme.
    _acct="${_USER}.${_nam}${_LTD_PLATFORM_SUFFIX}"
    if [ "${#_acct}" -gt 32 ]; then
      _ltd_notice "platform-toolong-${_acct}" \
        "platform account name ${_acct} is longer than 32 characters" \
        "shorten the client directory name; nothing granted"
      continue
    fi
    _on="${_on} ${_acct}"
    _roots=$(_ltd_platform_roots "${_cdir}" "${_acct}")
    _usrLtd="${_acct}"
    _Client="${_cdir}"
    echo "_usrLtd is == ${_usrLtd} == at _manage_sec_platform"
    _ALLD_NUM="0"
    _ALLD_CTL="1"
    _ALLD_DIR="'${_cdir}', '/opt/user/gems/${_acct}'"
    cd ${_cdir}
    _manage_sec_access_paths
    _granted=""
    for _r in ${_roots}; do
      _ALLD_DIR="${_ALLD_DIR}, '${_r}'"
      _granted="${_granted} ${_r}"
    done
    if [ -n "${_granted}" ]; then
      _LTD_EXTRA_STANZA="allowed : + [${_LTD_PLATFORM_TOOLS}]
allowed_shell_escape : + [${_LTD_PLATFORM_TOOLS}]"
    else
      _LTD_EXTRA_STANZA=""
    fi
    if [ "${_ALLD_NUM}" -ge "${_ALLD_CTL}" ]; then
      _add_user_if_not_exists
      if getent passwd "${_acct}" > /dev/null 2>&1; then
        _ltd_platform_farm "${_acct}" "${_granted}"
        _ltd_platform_window "${_acct}" "${_granted}"
      fi
      echo "Done platform account ${_acct} for ${_cdir}: ${_granted:-no qualifying platform}"
    fi
    _usrLtd=
    _ALLD_DIR=
    _LTD_EXTRA_STANZA=
  done
  for _ex in $(getent passwd | cut -d: -f1 | grep "^${_USER}\..*${_LTD_PLATFORM_SUFFIX}$"); do
    case " ${_on} " in
      *" ${_ex} "*) continue ;;
    esac
    _ltd_platform_retire "${_ex}"
  done
}
#
# Kill zombies.
_kill_zombies() {
  for _Existing in `cat /etc/passwd | cut -d ':' -f1 | sort`; do
    _SEC_IDY=$(id -nG ${_Existing} 2>&1)
    # Whole-word membership: a substring test also matches ltd-shell-more, the
    # operator-only tier nothing automatic joins today.
    if [[ " ${_SEC_IDY} " == *" ltd-shell "* ]] \
      && [ ! -z "${_Existing}" ] \
      && [[ ! "${_Existing}" =~ ".ftp"($) ]] \
      && [[ ! "${_Existing}" =~ ".web"($) ]]; then
      _usrParent=$(echo ${_Existing} | cut -d. -f1 | awk '{ print $1}' 2>&1)
      _usrParentTest=${_usrParent//[^a-z0-9]/}
      if [ ! -z "${_usrParentTest}" ]; then
        _PAR_DIR="/data/disk/${_usrParent}/clients"
        _SEC_SYM="/home/${_Existing}/sites"
        _SEC_DIR="$(readlink -n "${_SEC_SYM}")"
        if [ ! -L "${_SEC_SYM}" ] || [ ! -e "${_SEC_DIR}" ] \
          || [ ! -e "/home/${_usrParent}.ftp/users/${_Existing}" ]; then
          _ltd_reap_account "${_Existing}" "${_usrParent}" ""
        fi
      fi
    fi
  done
  for _Existing in `ls /home | cut -d '/' -f1 | sort`; do
    _isTest=${_Existing//[^a-z0-9]/}
    if [ ! -z "${_isTest}" ]; then
      # An orphan home is one with no passwd entry at all. The old test read
      # id(1)'s error text for "No such user", but id reports it lowercase
      # ("no such user") and =~ is case sensitive, so this arm never ran on any
      # box. getent's EXIT STATUS is the test: no message to parse, no locale
      # to depend on.
      if ! getent passwd "${_Existing}" > /dev/null 2>&1; then
        _usrParent=$(echo "${_Existing}" | cut -d. -f1 | awk '{ print $1}' 2>&1)
        # Scoped hard, because repairing the test wakes this arm on every box
        # at once: move only a real directory whose name carries the
        # <instance>.<client> shape, whose instance user exists and owns a disk
        # root. The old guard asked only that the name reduce to a non-empty
        # [a-z0-9] string, which lost+found also satisfies. The client half
        # allows a hyphen so a reserved-token account name stays sweepable.
        # The mtime brake is the last of it, against a transient this arm cannot
        # otherwise tell apart: a home staged by a migration before its account
        # exists looks exactly like an orphan. xmass does not create one -- it
        # stages sub-account .ssh under /var/backups/migrate-subuser-ssh
        # precisely because the home is not there yet (xmass, the branch taken
        # when the target has no such account) -- but this arm is newly
        # destructive and must not race a path a later tool adds. An hour is
        # nothing against an arm that has never run, and it is the same brake
        # the ghost-revision reaper uses for the same reason.
        if [ -d "/home/${_Existing}" ] \
          && [ ! -L "/home/${_Existing}" ] \
          && [[ "${_Existing}" =~ ^[a-z0-9]+\.[a-z0-9-]+$ ]] \
          && [[ ! "${_Existing}" =~ \.ftp$ ]] \
          && [[ ! "${_Existing}" =~ \.web$ ]] \
          && [ ! -z "${_usrParent}" ] \
          && getent passwd "${_usrParent}" > /dev/null 2>&1 \
          && [ -d "/data/disk/${_usrParent}" ]; then
          # The mtime brake alone does not hold: mv, cp -a, rsync -a and tar -xp
          # all carry the source's mtime, so a home staged by any of them looks
          # hours old the moment it lands (measured 2026-09-07). The clock that
          # matters is how long THIS arm has seen the home without an account,
          # so the first sighting only records a root-owned marker and the home
          # moves on a later pass, once the marker is an hour old as well.
          _ltd_orphan_seen="/var/backups/zombie/seen/${_Existing}"
          if [ ! -e "${_ltd_orphan_seen}" ]; then
            [ -d /var/backups/zombie/seen ] || mkdir -p /var/backups/zombie/seen
            touch "${_ltd_orphan_seen}"
          elif [ -z "$(find "/home/${_Existing}" -maxdepth 0 -mmin -60 2> /dev/null)" ] \
            && [ -z "$(find "${_ltd_orphan_seen}" -maxdepth 0 -mmin -60 2> /dev/null)" ]; then
            _disable_chattr "${_Existing}"
            [ -d "/var/backups/zombie/deleted/${_NOW}" ] || mkdir -p /var/backups/zombie/deleted/${_NOW}
            # The per-pass log under /var/backups/ltd is erased on every release,
            # and this arm moves a tenant's home aside on an arm that has never
            # run before: record it where it survives, and record a failed move
            # as what it is rather than as a move.
            [ -d /var/log/boa ] || mkdir -p /var/log/boa
            if mv "/home/${_Existing}" "/var/backups/zombie/deleted/${_NOW}/.leftover-${_Existing}"; then
              if [ -e "/home/${_usrParent}.ftp/users/${_Existing}" ]; then
                rm -f "/home/${_usrParent}.ftp/users/${_Existing}"
              fi
              rm -f "${_ltd_orphan_seen}"
              echo "Zombie from home.dir ${_Existing} killed"
              echo "$(date) LTD zombie sweep: orphan home /home/${_Existing} had no passwd entry; moved to /var/backups/zombie/deleted/${_NOW}/.leftover-${_Existing}" \
                >> /var/log/boa/manage_ltd.incident.log
            else
              echo "$(date) LTD zombie sweep: orphan home /home/${_Existing} had no passwd entry; mv to /var/backups/zombie/deleted/${_NOW}/.leftover-${_Existing} FAILED, left in place" \
                >> /var/log/boa/manage_ltd.incident.log
            fi
            echo
          fi
        fi
      fi
    fi
  done
  # A first-sighting marker outlives its reason once the account appears or the
  # home goes away; drop it so a later home of the same name starts a new clock.
  if [ -d "/var/backups/zombie/seen" ]; then
    for _ltd_orphan_seen in /var/backups/zombie/seen/*; do
      [ -e "${_ltd_orphan_seen}" ] || continue
      _Existing=$(basename "${_ltd_orphan_seen}")
      if getent passwd "${_Existing}" > /dev/null 2>&1 \
        || [ ! -d "/home/${_Existing}" ]; then
        rm -f "${_ltd_orphan_seen}"
      fi
    done
  fi
}
#
# Fix dot dirs.
_fix_dot_dirs() {
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    # Group owning this sub-user's tree, derived from the sub-user this call
    # handles -- never the script-scope default, which is box-wide.
    local _accGrp
    _accGrp=$(_acct_group "${_usrLtd}")
    _usrTmp="/home/${_usrLtd}/.tmp"
    # Every dot name this function seeds is root-created and root-chowned in a
    # home the sub-user owns, and none is ever legitimately a symlink here --
    # the [ ! -d ] tests and the chown/chmod that follow them all dereference,
    # so a planted link aims root at any target it names.
    _desymlink_planted "${_usrTmp}" "/home/${_usrLtd}/.lftp" \
      "/home/${_usrLtd}/.lhistory" "/home/${_usrLtd}/.drush" \
      "/home/${_usrLtd}/.bee" "/home/${_usrLtd}/.ssh" \
      "/home/${_usrLtd}/.bazaar"
    if [ ! -d "${_usrTmp}" ]; then
      mkdir -p ${_usrTmp}
      chown -h ${_usrLtd}:${_accGrp} ${_usrTmp}
      [ ! -L "${_usrTmp}" ] && chmod 02755 ${_usrTmp}
    fi
    _usrLftp="/home/${_usrLtd}/.lftp"
    if [ ! -d "${_usrLftp}" ]; then
      mkdir -p ${_usrLftp}
      chown -h ${_usrLtd}:${_accGrp} ${_usrLftp}
      [ ! -L "${_usrLftp}" ] && chmod 02755 ${_usrLftp}
    fi
    _usrLhist="/home/${_usrLtd}/.lhistory"
    if [ ! -e "${_usrLhist}" ]; then
      touch ${_usrLhist}
      chown -h ${_usrLtd}:${_accGrp} ${_usrLhist}
      [ ! -L "${_usrLhist}" ] && chmod 644 ${_usrLhist}
    fi
    _usrDrush="/home/${_usrLtd}/.drush"
    if [ ! -d "${_usrDrush}" ]; then
      mkdir -p ${_usrDrush}
      chown ${_usrLtd}:${_accGrp} ${_usrDrush}
      chmod 700 ${_usrDrush}
    fi
    _usrBee="/home/${_usrLtd}/.bee"
    if [ ! -d "${_usrBee}" ]; then
      mkdir -p ${_usrBee}
      chown ${_usrLtd}:${_accGrp} ${_usrBee}
      chmod 700 ${_usrBee}
    fi
    _usrSsh="/home/${_usrLtd}/.ssh"
    if [ ! -d "${_usrSsh}" ]; then
      mkdir -p ${_usrSsh}
      chown -R ${_usrLtd}:${_accGrp} ${_usrSsh}
      chmod 700 ${_usrSsh}
    fi
    chmod 600 ${_usrSsh}/id_{r,d}sa &> /dev/null
    chmod 600 ${_usrSsh}/known_hosts &> /dev/null
    _usrBzr="/home/${_usrLtd}/.bazaar"
    if [ -x "/usr/local/bin/bzr" ]; then
      if [ ! -z "${_usrLtd}" ] && [ ! -e "${_usrBzr}/bazaar.conf" ]; then
        mkdir -p ${_usrBzr}
        echo ignore_missing_extensions=True > ${_usrBzr}/bazaar.conf
        chown -R ${_usrLtd}:${_accGrp} ${_usrBzr}
        chmod 700 ${_usrBzr}
      fi
    else
      if [ ! -z "${_usrLtd}" ] && [ -d "${_usrBzr}" ]; then
        rm -rf ${_usrBzr}
      fi
    fi
  fi
}
#
# Manage Drush _Aliases.
_manage_sec_user_drush_aliases() {
  if [ -e "${_Client}" ]; then
    if [ -L "${_usrLtdRoot}/sites" ]; then
      _symTgt="$(readlink -n "${_usrLtdRoot}/sites")"
    else
      rm -f ${_usrLtdRoot}/sites
    fi
    if [ "${_symTgt}" != "${_Client}" ] \
      || [ ! -e "${_usrLtdRoot}/sites" ]; then
      rm -f ${_usrLtdRoot}/sites
      ln -sfn ${_Client} ${_usrLtdRoot}/sites
    fi
  fi
  if [ ! -e "${_usrLtdRoot}/.drush" ]; then
    mkdir -p ${_usrLtdRoot}/.drush
  fi

  _ALS_TEST=$(ls -la ${_usrLtdRoot}/.drush/*.alias.drushrc.php 2>&1)
  if [[ ! "${_ALS_TEST}" =~ "No such file" ]]; then
    for _Alias in `find ${_usrLtdRoot}/.drush/*.alias.drushrc.php \
      -maxdepth 1 -type f | sort`; do
      _AliasName=$(echo "${_Alias}" | cut -d'/' -f5 | awk '{ print $1}' 2>&1)
      _AliasName=$(echo "${_AliasName}" \
        | sed "s/.alias.drushrc.php//g" \
        | awk '{ print $1}' 2>&1)
      if [ ! -z "${_AliasName}" ] \
        && [ ! -e "${_usrLtdRoot}/sites/${_AliasName}" ]; then
        rm -f ${_usrLtdRoot}/.drush/${_AliasName}.alias.drushrc.php
      fi
    done
  fi

  for _Symlink in `find ${_usrLtdRoot}/sites/ \
    -maxdepth 1 -mindepth 1 | sort`; do
    _SiteName=$(echo ${_Symlink}  \
      | cut -d'/' -f5 \
      | awk '{ print $1}' 2>&1)
    _pthAliasMain="${_pthParentUsr}/.drush/${_SiteName}.alias.drushrc.php"
    _pthAliasCopy="${_usrLtdRoot}/.drush/${_SiteName}.alias.drushrc.php"
    # The copy is a root-written control file in a home the sub-user owns, and
    # is never legitimately a link: cp -af follows a symlinked DESTINATION and
    # chmod follows too, so strip the plant before either runs. Only the copy --
    # the main alias may legitimately be the front-end link seeded at ~/.drush.
    [ ! -z "${_SiteName}" ] && _desymlink_planted "${_pthAliasCopy}"
    if [ ! -z "${_SiteName}" ] && [ ! -e "${_pthAliasCopy}" ]; then
      cp -af ${_pthAliasMain} ${_pthAliasCopy}
      [ ! -L "${_pthAliasCopy}" ] && chmod 440 ${_pthAliasCopy}
    elif [ ! -z "${_SiteName}" ]  && [ -e "${_pthAliasCopy}" ]; then
      _DIFF_T=$(diff -w -B ${_pthAliasCopy} ${_pthAliasMain} 2>&1)
      if [ ! -z "${_DIFF_T}" ]; then
        cp -af ${_pthAliasMain} ${_pthAliasCopy}
        [ ! -L "${_pthAliasCopy}" ] && chmod 440 ${_pthAliasCopy}
      fi
    fi
  done
}
#
# OK, create user.
_ok_create_user() {
  # Reset the minted-password carriers on EVERY entry, not only on the branch
  # that mints one. _manage_sec resets _usrLtd and _ALLD_DIR between accounts
  # but never these, and _manage_user does not reset them between instances
  # either, so a run that skips useradd because the home already exists would
  # otherwise still hold the PREVIOUS account's password -- emit a stanza for
  # an account that has no passwd entry and write that password into this
  # account's store, across instances. Proven on a rig 2026-09-07.
  _ESC_LUPASS=""
  _LEN_LUPASS=0
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    _ADMIN="${_USER}.ftp"
    echo "_ADMIN is == ${_ADMIN} == at _ok_create_user"
    _usrLtdRoot="/home/${_usrLtd}"
    _SEC_SYM="${_usrLtdRoot}/sites"
    _TMP="/var/tmp"
    if [ ! -L "${_SEC_SYM}" ]; then
      [ -d "/var/backups/zombie/deleted/${_NOW}" ] || mkdir -p /var/backups/zombie/deleted/${_NOW}
      mv -f ${_usrLtdRoot} /var/backups/zombie/deleted/${_NOW}/ &> /dev/null
    fi
    if [ ! -d "${_usrLtdRoot}" ]; then
      if [ "${_LTD_STANDBY_HOLD}" = "YES" ]; then
        # A user born on a held standby (users.txt arrives from the active
        # by sync) never gets a live shell, not even for one pass; record
        # it so promotion restores it like every other held tenant.
        useradd -d ${_usrLtdRoot} -s /usr/sbin/nologin -m -N -r \
          -g ${_usrGroup:-users} ${_usrLtd}
        mkdir -p /var/log/boa 2>/dev/null
        grep -qxF "${_usrLtd}" /var/log/boa/standby-held-shells.txt 2>/dev/null \
          || echo "${_usrLtd}" >> /var/log/boa/standby-held-shells.txt
      elif [ -e "/usr/bin/mysecureshell" ] && [ -e "/etc/ssh/sftp_config" ]; then
        useradd -d ${_usrLtdRoot} -s /usr/bin/mysecureshell -m -N -r \
          -g ${_usrGroup:-users} ${_usrLtd}
        echo "_usrLtdRoot is == ${_usrLtdRoot} == at _ok_create_user"
      else
        useradd -d ${_usrLtdRoot} -s /usr/bin/lshell -m -N -r \
          -g ${_usrGroup:-users} ${_usrLtd}
      fi
      # The primary group is the account's own (-g above, users until the
      # account carries its per-instance group); 'users' stays supplementary
      # in every case -- it is the binary execute ACL, lshell included.
      usermod -aG users ${_usrLtd}
      adduser ${_usrLtd} ${_WEBG}
      # A migration carries /home/<admin>/users/<name> from the source box
      # before this user exists here; honour that stored password so the
      # client's sub-account credential survives the move, instead of
      # minting a new one the carried store would then contradict. Normal
      # operation is unchanged: the store exists before user creation only
      # when something deliberately placed it there.
      if [ -e "/home/${_ADMIN}/users/${_usrLtd}" ]; then
        _ESC_LUPASS=$(cat /home/${_ADMIN}/users/${_usrLtd} 2>/dev/null | tr -d "\n")
        _LEN_LUPASS=$(echo ${#_ESC_LUPASS} 2>&1)
      fi
      if [ "${_STRONG_PASSWORDS}" = "YES" ]  ; then
        _PWD_CHARS=64
      elif [ "${_STRONG_PASSWORDS}" = "NO" ]; then
        _PWD_CHARS=32
      else
        _STRONG_PASSWORDS=${_STRONG_PASSWORDS//[^0-9]/}
        if [ ! -z "${_STRONG_PASSWORDS}" ] \
          && [ "${_STRONG_PASSWORDS}" -gt 32 ]; then
          _PWD_CHARS="${_STRONG_PASSWORDS}"
        else
          _PWD_CHARS=32
        fi
        if [ ! -z "${_PWD_CHARS}" ] && [ "${_PWD_CHARS}" -gt 128 ]; then
          _PWD_CHARS=128
        fi
      fi
      if [ -z "${_ESC_LUPASS}" ] \
        && { [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt 32 ]; }; then
        _RANDPASS_TEST=$(randpass -V 2>&1)
        if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
          _ESC_LUPASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
        else
          _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
          _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
          _ESC_LUPASS=$(_sanitize_string "${_ESC_LUPASS}" 2>&1)
        fi
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _LEN_LUPASS=$(echo ${#_ESC_LUPASS} 2>&1)
      fi
      if [ -z "${_ESC_LUPASS}" ] || [ "${_LEN_LUPASS}" -lt 9 ]; then
        _ESC_LUPASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
        _ESC_LUPASS=$(echo -n "${_ESC_LUPASS}" | tr -d "\n" 2>&1)
        _ESC_LUPASS=$(_sanitize_string "${_ESC_LUPASS}" 2>&1)
      fi
      # Compute the sha-512 hash via stdin and set it via chpasswd -e via
      # stdin too — neither the plaintext password nor the resulting hash
      # ever appears on the cmdline (where /proc/<pid>/cmdline would expose
      # it to local users during the brief usermod -p / mkpasswd window).
      _salt=$(openssl rand -base64 16 | tr -d '+=' | head -c 16)
      ph=$(printf '%s' "${_ESC_LUPASS}" | mkpasswd -m sha-512 -s -S "${_salt}" 2>&1)
      printf '%s:%s\n' "${_usrLtd}" "${ph}" | chpasswd -e &> /dev/null
      passwd -w 7 -x 90 ${_usrLtd}
      usermod -aG lshellg ${_usrLtd}
      usermod -aG ltd-shell ${_usrLtd}
    fi
    if [ ! -z "${_ESC_LUPASS}" ]; then
      if [ "${_LTD_STANDBY_HOLD}" = "YES" ]; then
        : # tenant shells stay nologin while the standby hold is on --
        # healing them back here would reopen the login for the minutes
        # between this heal and the end-of-pass sweep
      elif [ -e "/usr/bin/mysecureshell" ] \
        && [ -e "/etc/ssh/sftp_config" ]; then
        chsh -s /usr/bin/mysecureshell ${_usrLtd}
      else
        chsh -s /usr/bin/lshell ${_usrLtd}
      fi
      echo >> ${_THIS_LTD_CONF}
      echo "[${_usrLtd}]" >> ${_THIS_LTD_CONF}
      echo "path : [${_ALLD_DIR}]" >> ${_THIS_LTD_CONF}
      [ -n "${_LTD_EXTRA_STANZA}" ] && printf '%s\n' "${_LTD_EXTRA_STANZA}" >> ${_THIS_LTD_CONF}
      chmod 700 ${_usrLtdRoot}
      mkdir -p /home/${_ADMIN}/users
      if [ ! -e "/home/${_ADMIN}/users/${_usrLtd}" ]; then
        echo "${_ESC_LUPASS}" > /home/${_ADMIN}/users/${_usrLtd}
      elif [ "$(cat /home/${_ADMIN}/users/${_usrLtd} 2>/dev/null | tr -d '\n')" != "${_ESC_LUPASS}" ]; then
        # The quality floor regenerated over a too-short carried entry; the
        # store must always match the shadow hash that was just set, never
        # advertise a password that no longer works.
        echo "${_ESC_LUPASS}" > /home/${_ADMIN}/users/${_usrLtd}
      fi
    fi
    # A migration stages a sub-account's SSH keys here because the home did
    # not exist on this box yet; adopt them now that it does, once. Only for an
    # account that exists: a home with no passwd entry (the create path with an
    # existing home) must not consume the staged copy -- the chown below could
    # not resolve the owner and the rm -rf would destroy the only copy.
    if [ -d "/var/backups/migrate-subuser-ssh/${_usrLtd}/.ssh" ] \
      && [ -d "${_usrLtdRoot}" ] \
      && getent passwd "${_usrLtd}" > /dev/null 2>&1; then
      cp -af "/var/backups/migrate-subuser-ssh/${_usrLtd}/.ssh" "${_usrLtdRoot}/"
      # Group half derived, not the user name: no group named after a
      # sub-user is ever created, so that chgrp half always failed.
      chown -R ${_usrLtd}:$(_acct_group "${_usrLtd}") "${_usrLtdRoot}/.ssh" &> /dev/null
      chmod 700 "${_usrLtdRoot}/.ssh" &> /dev/null
      chmod 600 "${_usrLtdRoot}"/.ssh/* &> /dev/null
      rm -rf "/var/backups/migrate-subuser-ssh/${_usrLtd}"
      echo "Adopted migrated SSH keys for ${_usrLtd}"
    fi
    _fix_dot_dirs
    rm -f ${_usrLtdRoot}/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
}
#
# Change a sub-user's primary group without usermod's own recursive lchown of
# the home tree (shadow chown_tree: full pathnames, stops at the first
# immutable inode -- and these homes carry chattr +i -- with the passwd entry
# already rewritten). The home field points at an empty root-owned staging
# dir for that one call and is put back at once; the group on the files is
# the alias-copy leg's business.
_set_primary_group() {
  local _u="$1" _g="$2" _h _stage=/var/backups/ltd/.pg-stage
  _h=$(getent passwd "${_u}" 2>/dev/null | cut -d: -f6)
  [ -n "${_h}" ] || return 1
  mkdir -p "${_stage}" && chown root:root "${_stage}" && chmod 0700 "${_stage}"
  # Recorded first (the same record instgrp keeps): a kill between the two
  # usermod calls leaves the passwd home at the staging dir, and
  # _repair_staged_homes puts it back on the next pass.
  [ -d /var/log/boa ] || mkdir -p /var/log/boa
  printf '%s\n' "${_h}" > "/var/log/boa/instgrp.home.${_u}"
  usermod -d "${_stage}" -g "${_g}" "${_u}" > /dev/null 2>&1
  usermod -d "${_h}" "${_u}" > /dev/null 2>&1
  rm -f "/var/log/boa/instgrp.home.${_u}"
  [ "$(id -gn "${_u}" 2>/dev/null)" = "${_g}" ]
}
#
# Any identity whose passwd home is a primary-group staging directory (this
# worker's or instgrp's) was caught between the two usermod calls: put the
# recorded home back, or the one the name implies. Every pass, first thing.
_repair_staged_homes() {
  local _s _u _want _rec
  for _s in /var/backups/ltd/.pg-stage /root/.instgrp.home; do
    for _u in $(getent passwd | awk -F: -v s="${_s}" '$6 == s { print $1 }'); do
      _rec="/var/log/boa/instgrp.home.${_u}"
      _want=""
      [ -s "${_rec}" ] && _want=$(head -1 "${_rec}")
      if [ -z "${_want}" ]; then
        case "${_u}" in
          *.*) _want="/home/${_u}" ;;
          *)   _want="/data/disk/${_u}" ;;
        esac
      fi
      [ -d "${_want}" ] || continue
      usermod -d "${_want}" "${_u}" > /dev/null 2>&1
      if [ "$(getent passwd "${_u}" 2>/dev/null | cut -d: -f6)" = "${_want}" ]; then
        echo "ALERT: ${_u} home field was left at ${_s} by an interrupted group move; restored to ${_want}"
        # the per-pass log under /var/backups/ltd is erased on every release;
        # an identity incident belongs in the durable incident log too
        mkdir -p /var/log/boa 2>/dev/null
        echo "$(date) LTD home repair: ${_u} home field was left at ${_s} by an interrupted group move; restored to ${_want}" \
          >> /var/log/boa/manage_ltd.incident.log
        rm -f "${_rec}"
      fi
    done
  done
}
#
# OK, update user.
_ok_update_user() {
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    _ADMIN="${_USER}.ftp"
    _usrLtdRoot="/home/${_usrLtd}"
    if [ -e "/home/${_ADMIN}/users/${_usrLtd}" ]; then
      echo >> ${_THIS_LTD_CONF}
      echo "[${_usrLtd}]" >> ${_THIS_LTD_CONF}
      echo "path : [${_ALLD_DIR}]" >> ${_THIS_LTD_CONF}
      [ -n "${_LTD_EXTRA_STANZA}" ] && printf '%s\n' "${_LTD_EXTRA_STANZA}" >> ${_THIS_LTD_CONF}
      _manage_sec_user_drush_aliases
      chmod 700 ${_usrLtdRoot}
      # 'users' is the binary execute ACL (root:users 0750, lshell included):
      # every sub-user must be LISTED in it, independently of its primary
      # group. The test reads the group database -- id -nG would answer yes
      # through the primary gid alone, and a later primary move would then
      # drop the group. Repairs an already-stripped identity on every pass.
      if ! getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_usrLtd}"; then
        usermod -aG users ${_usrLtd}
      fi
      # A sub-user still on the box-wide primary group while its account
      # carries the per-instance group (born under an older worker, or the
      # account converted since) cannot read its 0440 alias copies: align it,
      # only once the explicit 'users' membership above is in place, and
      # verified after the move.
      if [ "${_usrGroup}" != "users" ] \
        && [ "$(id -gn ${_usrLtd} 2>/dev/null)" != "${_usrGroup}" ] \
        && getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_usrLtd}"; then
        _set_primary_group ${_usrLtd} ${_usrGroup}
        if id -nG ${_usrLtd} 2>/dev/null | tr ' ' '\n' | grep -qxF users; then
          echo "Sub-user ${_usrLtd} moved to primary group ${_usrGroup}"
        else
          _set_primary_group ${_usrLtd} users
          echo "ALERT: ${_usrLtd} lost group users on the primary move, reverted to users"
          mkdir -p /var/log/boa 2>/dev/null
          echo "$(date) LTD primary move: ${_usrLtd} lost group users on the primary move, reverted to users" \
            >> /var/log/boa/manage_ltd.incident.log
        fi
      fi
    fi
    _fix_dot_dirs
    rm -f ${_usrLtdRoot}/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
}
#
# Add user if not exists.
_add_user_if_not_exists() {
  _usrLtdTest=${_usrLtd//[^a-z0-9]/}
  if [ ! -z "${_usrLtdTest}" ]; then
    _ID_EXISTS=$(getent passwd ${_usrLtd} 2>&1)
    _ID_SHELLS=$(id -nG ${_usrLtd} 2>&1)
    echo "_ID_EXISTS is == ${_ID_EXISTS} == at _add_user_if_not_exists"
    echo "_ID_SHELLS is == ${_ID_SHELLS} == at _add_user_if_not_exists"
    if [ -z "${_ID_EXISTS}" ]; then
      echo "We will create user == ${_usrLtd} =="
      _ok_create_user
      _manage_sec_user_drush_aliases
      _enable_chattr ${_usrLtd}
    elif [[ "${_ID_EXISTS}" =~ "${_usrLtd}" ]] \
      && [[ " ${_ID_SHELLS} " == *" ltd-shell "* ]]; then
      echo "We will update user == ${_usrLtd} =="
      _disable_chattr ${_usrLtd}
      rm -rf /home/${_usrLtd}/drush-backups
      _usrTmp="/home/${_usrLtd}/.tmp"
      _desymlink_planted "${_usrTmp}"
      if [ ! -d "${_usrTmp}" ]; then
        mkdir -p ${_usrTmp}
        chown -h ${_usrLtd}:$(_acct_group "${_usrLtd}") ${_usrTmp}
        [ ! -L "${_usrTmp}" ] && chmod 02755 ${_usrTmp}
      fi
      find ${_usrTmp} -mindepth 1 -mtime +0 -exec rm -rf {} \; &> /dev/null
      _ok_update_user
      _enable_chattr ${_usrLtd}
    fi
  fi
}
#
# Manage Access Paths.
_manage_sec_access_paths() {
#for _Domain in `find ${_Client}/ -maxdepth 1 -mindepth 1 -type l -printf %P\\n | sort`
for _Domain in `find ${_Client}/ -maxdepth 1 -mindepth 1 -type l | sort`; do
  _rawDom=$(echo ${_Domain} | cut -d'/' -f7 | awk '{ print $1}' 2>&1)
  # Both values land inside single quotes in the root-written /etc/lshell.conf:
  # a quote or backslash would close the string and inject shell-confinement
  # policy. _sanitize_string is wrong here -- its class strips '/' too.
  _rawDom=${_rawDom//[^a-zA-Z0-9.-]/}
  _STATIC_FILES="${_pthParentUsr}/static/files/${_rawDom}.files/"
  _STATIC_PRIVATE="${_pthParentUsr}/static/files/${_rawDom}.private/"
  _NEW_STATIC_FILES="${_pthParentUsr}/static/files/${_rawDom}/"
  _PATH_DOM="$(readlink -n "${_Domain}")"
  _PATH_DOM=${_PATH_DOM//[^a-zA-Z0-9._\/-]/}
  # Drupal (and Backdrop) sites only. A Grav capsule or a Textpattern site
  # directory is the whole codebase, so a per-client sub-account reaching it
  # would hold full code and database access there, against the files-only
  # policy these accounts have. Skip such a link and drop it, so neither the
  # lshell path nor the SFTP tree can traverse it (provision no longer
  # creates them; this converges boxes that still carry one).
  if [ -n "${_PATH_DOM}" ] && [ -d "${_PATH_DOM}" ] \
    && [ ! -f "${_PATH_DOM}/settings.php" ] \
    && { { [ -f "${_PATH_DOM}/bin/grav" ] && [ -f "${_PATH_DOM}/system/defines.php" ]; } \
      || { [ -f "${_PATH_DOM}/public/index.php" ] && [ -d "${_PATH_DOM}/admin" ]; }; }; then
    echo "Skipping non-Drupal site ${_Domain} at ${_Client}"
    [ -L "${_Domain}" ] && rm -f "${_Domain}"
    continue
  fi
  # Attached files mount = the SINGLE real mountpoint under /mnt (naming-agnostic).
  # Fail-closed: empty when NONE or when MORE THAN ONE is mounted -- multi-mount is
  # unsupported fleet-wide and cannot be disambiguated, so refuse to guess.
  _mntPoint=$(_pd=$(stat -c '%d' /mnt 2>/dev/null); _n=0; _hit=; for _m in /mnt/*; do
    [ -d "${_m}" ] || continue
    if mountpoint -q "${_m}" 2>/dev/null \
      || { [ -n "${_pd}" ] && [ "$(stat -c '%d' "${_m}" 2>/dev/null)" != "${_pd}" ]; }; then
      _hit="${_m}"; _n=$((_n + 1))
    fi
  done; [ "${_n}" -eq 1 ] && printf '%s' "${_hit}"; :) &&
  _MNT_STATIC_FILES="${_mntPoint}/files/${_USER}/static/files/${_rawDom}/"
#   echo "_ALLD_DIR is == ${_ALLD_DIR} == at _manage_sec_access_paths"
#   echo "_rawDom is == ${_rawDom} == at _manage_sec_access_paths"
#   echo "_STATIC_FILES is == ${_STATIC_FILES} == at _manage_sec_access_paths"
#   echo "_STATIC_PRIVATE is == ${_STATIC_PRIVATE} == at _manage_sec_access_paths"
#   echo "_NEW_STATIC_FILES is == ${_NEW_STATIC_FILES} == at _manage_sec_access_paths"
#   echo "_PATH_DOM is == ${_PATH_DOM} == at _manage_sec_access_paths"
#   [ -n "${_mntPoint}" ] && echo "_mntPoint is == ${_mntPoint} == at _manage_sec_access_paths"
#   [ -n "${_mntPoint}" ] && echo "_MNT_STATIC_FILES is == ${_MNT_STATIC_FILES} == at _manage_sec_access_paths"
  [ -n "${_mntPoint}" ] && _ALLD_DIR="${_ALLD_DIR}, '${_PATH_DOM}', '${_STATIC_FILES}', '${_STATIC_PRIVATE}', '${_NEW_STATIC_FILES}', '${_MNT_STATIC_FILES}'"
  [ -z "${_mntPoint}" ] && _ALLD_DIR="${_ALLD_DIR}, '${_PATH_DOM}', '${_STATIC_FILES}', '${_STATIC_PRIVATE}', '${_NEW_STATIC_FILES}'"
  if [ -e "${_PATH_DOM}" ]; then
    _ALLD_NUM=$(( _ALLD_NUM += 1 ))
  fi
  echo Done for ${_Domain} at ${_Client}
done
}
#
# Sub-account name for one client directory. The pass that creates the accounts
# and the collision scan below must read a client directory identically, or the
# scan would clear a name the pass then collides on -- so both go through here.
_ltd_name_from_client_dir() {
  local _dir="${1}"
  local _nam=""
  _nam=$(echo "${_dir}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
  _nam=${_nam//[^a-zA-Z0-9]/}
  _nam=$(echo -n "${_nam}" | tr A-Z a-z 2>&1)
  printf '%s\n' "${_nam}"
}
#
# Two client directories that differ only in punctuation, case or a trailing
# word collapse to ONE sub-account name, and both halves of the pass then emit
# a stanza for it -- which the strict parser refuses, taking every shell on the
# box down with it. The render side now collapses the repeat and the publish
# side fails closed, so the box stays up; what remains is one account serving
# two clients, and only renaming a client directory undoes that.
#
# Report it, never repair it here. Renaming the account would invalidate a login
# the client already holds, dropping one would be an outage of its own, and
# which of the two directories is the newcomer is not knowable from the listing
# -- so the repair is the operator's, and this makes it visible and durable.
_ltd_collision_scan() {
  local _dir=""
  local _nam=""
  local _dup=""
  local _hits=""
  _dup=$(find ${_pthParentUsr}/clients/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
    | sort | while read -r _dir; do
        _nam=$(_ltd_name_from_client_dir "${_dir}")
        [ -n "${_nam}" ] && echo "${_nam}"
      done | sort | uniq -d)
  [ -n "${_dup}" ] || return 0
  while read -r _nam; do
    [ -n "${_nam}" ] || continue
    _hits=$(find ${_pthParentUsr}/clients/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
      | sort | while read -r _dir; do
          [ "$(_ltd_name_from_client_dir "${_dir}")" = "${_nam}" ] && echo "${_dir}"
        done | tr '\n' ' ')
    _ltd_notice "collide-${_USER}.${_nam}" \
      "client directories collapse to one sub-account ${_USER}.${_nam}" \
      "shared by: ${_hits}-- rename one client so the names differ by more than punctuation or case; until then the LAST directory listed owns both the shell paths and ~/sites, and the others are unreachable through that account"
  done <<< "${_dup}"
}
#
# Manage Secondary Users.
_manage_sec() {
_ltd_collision_scan
for _Client in `find ${_pthParentUsr}/clients/ -maxdepth 1 -mindepth 1 -type d | sort`; do
  _usrLtd=$(_ltd_name_from_client_dir "${_Client}")
  if [ ! -z "${_usrLtd}" ]; then
    _usrLtd="${_USER}.${_usrLtd}"
    echo "_usrLtd is == ${_usrLtd} == at _manage_sec"
    _ALLD_NUM="0"
    _ALLD_CTL="1"
    _ALLD_DIR="'${_Client}', '/opt/user/gems/${_usrLtd}'"
    cd ${_Client}
    _manage_sec_access_paths
    # _ALLD_DIR="${_ALLD_DIR}, '/home/${_usrLtd}'"
    if [ "${_ALLD_NUM}" -ge "${_ALLD_CTL}" ]; then
      _add_user_if_not_exists
      echo Done for ${_Client} at ${_pthParentUsr}
    else
      echo Empty ${_Client} at ${_pthParentUsr} - deleting now
      if [ -e "${_Client}" ]; then
        rmdir ${_Client}
      fi
    fi
  fi
  _usrLtd=
  _ALLD_DIR=
done
}
#
# Update local INI for PHP CLI on the Ægir Satellite Instance.
_php_cli_local_ini_update() {
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="${_dscUsr}/tools/drush/${1}"
  else
    _DRUSH_FILE="${_dscUsr}/tools/drush/drush.php"
  fi
  _U_HD="${_dscUsr}/.drush"
  _U_TP="${_dscUsr}/.tmp"
  _U_II="${_U_HD}/php.ini"
  _PHP_CLI_UPDATE=NO
  if [ ! -e "${_DRUSH_FILE}" ]; then
    return 1  # Exit the function but continue the script
  fi
  _CHECK_USE_PHP_CLI=$(grep "/opt/php" ${_DRUSH_FILE} 2>&1)
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
      && [ ! -e "${_U_HD}/.ctrl.php${e}.${_xSrl}.pid" ]; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  if [ "${_PHP_CLI_UPDATE}" = "YES" ] \
    || [ ! -e "${_U_II}" ] \
    || [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
    mkdir -p ${_U_TP}
    touch ${_U_TP}
    find ${_U_TP}/ -mtime +0 -exec rm -rf {} \; &> /dev/null
    mkdir -p ${_U_HD}
    chown ${_USER}:${_usrGroup} ${_U_TP}
    chown ${_USER}:${_usrGroup} ${_U_HD}
    chmod 755 ${_U_TP}
    chmod 755 ${_U_HD}
    chattr -i ${_U_II}
    rm -f ${_U_HD}/.ctrl.php*
    rm -f ${_U_II}
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php85" ]]; then
      cp -af /opt/php85/lib/php.ini ${_U_II}
      _U_INI=85
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php84" ]]; then
      cp -af /opt/php84/lib/php.ini ${_U_II}
      _U_INI=84
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php83" ]]; then
      cp -af /opt/php83/lib/php.ini ${_U_II}
      _U_INI=83
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php82" ]]; then
      cp -af /opt/php82/lib/php.ini ${_U_II}
      _U_INI=82
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php81" ]]; then
      cp -af /opt/php81/lib/php.ini ${_U_II}
      _U_INI=81
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php80" ]]; then
      cp -af /opt/php80/lib/php.ini ${_U_II}
      _U_INI=80
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php74" ]]; then
      cp -af /opt/php74/lib/php.ini ${_U_II}
      _U_INI=74
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php73" ]]; then
      cp -af /opt/php73/lib/php.ini ${_U_II}
      _U_INI=73
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php72" ]]; then
      cp -af /opt/php72/lib/php.ini ${_U_II}
      _U_INI=72
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php71" ]]; then
      cp -af /opt/php71/lib/php.ini ${_U_II}
      _U_INI=71
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php70" ]]; then
      cp -af /opt/php70/lib/php.ini ${_U_II}
      _U_INI=70
    elif [[ "${_CHECK_USE_PHP_CLI}" =~ "php56" ]]; then
      cp -af /opt/php56/lib/php.ini ${_U_II}
      _U_INI=56
    fi
    if [ -e "${_U_II}" ]; then
      # open_basedir stays out of the CLI ini: it breaks Drush and turns the
      # realpath cache off (every file operation checked against every listed
      # tree, uncached); lshell users are confined by their own measures, and
      # the FPM ini keeps its own list
      _QTP=${_U_TP//\//\\\/}
      sed -i "s/.*open_basedir =.*/;open_basedir =/g"                      ${_U_II}
      wait
      sed -i "s/.*error_reporting =.*/error_reporting = 1/g"               ${_U_II}
      wait
      sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_U_II}
      wait
      sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_U_II}
      wait
      sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_U_II}
      wait
      sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_U_II}
      wait
      echo > ${_U_HD}/.ctrl.php${_U_INI}.${_xSrl}.pid
      echo > ${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid
    fi
    chattr +i ${_U_II}
  fi
}
#
# Update PHP-CLI for Drush.
_php_cli_drush_update() {
  if [ ! -z "${1}" ]; then
    _DRUSH_FILE="${_dscUsr}/tools/drush/${1}"
  else
    _DRUSH_FILE="${_dscUsr}/tools/drush/drush.php"
  fi
  if [ ! -e "${_DRUSH_FILE}" ]; then
    return 1  # Exit the function but continue the script
  fi
  if [ "${_T_CLI_VRN}" = "8.5" ] && [ -x "/opt/php85/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php85\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php85/bin
  elif [ "${_T_CLI_VRN}" = "8.4" ] && [ -x "/opt/php84/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php84\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php84/bin
  elif [ "${_T_CLI_VRN}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php83\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php83/bin
  elif [ "${_T_CLI_VRN}" = "8.2" ] && [ -x "/opt/php82/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php82\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php82/bin
  elif [ "${_T_CLI_VRN}" = "8.1" ] && [ -x "/opt/php81/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php81\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php81/bin
  elif [ "${_T_CLI_VRN}" = "8.0" ] && [ -x "/opt/php80/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php80\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php80/bin
  elif [ "${_T_CLI_VRN}" = "7.4" ] && [ -x "/opt/php74/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php74\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php74/bin
  elif [ "${_T_CLI_VRN}" = "7.3" ] && [ -x "/opt/php73/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php73\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php73/bin
  elif [ "${_T_CLI_VRN}" = "7.2" ] && [ -x "/opt/php72/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php72\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php72/bin
  elif [ "${_T_CLI_VRN}" = "7.1" ] && [ -x "/opt/php71/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php71\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php71/bin
  elif [ "${_T_CLI_VRN}" = "7.0" ] && [ -x "/opt/php70/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php70\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php70/bin
  elif [ "${_T_CLI_VRN}" = "5.6" ] && [ -x "/opt/php56/bin/php" ]; then
    sed -i "s/^#\!\/.*/#\!\/opt\/php56\/bin\/php/g"  ${_DRUSH_FILE} &> /dev/null
    _T_CLI=/opt/php56/bin
  else
    _T_CLI=/foo/bar
  fi
  if [ -x "${_T_CLI}/php" ]; then
    #_DRUSH_HOSTING_TASKS_CMD="/usr/bin/drush @hostmaster hosting-tasks --force"
    _DRUSH_HOSTING_DISPATCH_CMD="${_T_CLI}/php ${_dscUsr}/tools/drush/drush.php @hostmaster hosting-dispatch"
    if [ -e "${_dscUsr}/aegir.sh" ]; then
      rm -f ${_dscUsr}/aegir.sh
    fi
    touch ${_dscUsr}/aegir.sh
    echo -e "#!/bin/bash\n\nPATH=.:${_T_CLI}:/usr/sbin:/usr/bin:/sbin:/bin\n \
      \n${_DRUSH_HOSTING_DISPATCH_CMD} \
      \ntouch ${_dscUsr}/${_USER}-task.done" \
      | fmt -su -w 2500 | tee -a ${_dscUsr}/aegir.sh >/dev/null 2>&1
    chown ${_USER}:${_usrGroup} ${_dscUsr}/aegir.sh &> /dev/null
    chmod 0700 ${_dscUsr}/aegir.sh &> /dev/null
    # The shebang pin on drush.php is bypassed whenever the drush 8 finder
    # runs: it execs drush.launcher, which re-selects PHP via `which php`.
    # The launcher also cannot run at all via its stock `env sh` shebang,
    # because /bin/sh is websh, which refuses user-area scripts. Run it
    # under bash and default its native DRUSH_PHP to the pin -- default,
    # not override: websh exports DRUSH_PHP per invocation from the
    # static/control files (cli.info + instant phpNN.info switches), and
    # that runtime choice must always win over the baked pin.
    _DRUSH_LNCH="${_dscUsr}/tools/drush/drush.launcher"
    if [ -e "${_DRUSH_LNCH}" ]; then
      sed -i "1s/^#\!.*/#\!\/bin\/bash/" ${_DRUSH_LNCH} &> /dev/null
      sed -i "/^export DRUSH_PHP=/d" ${_DRUSH_LNCH} &> /dev/null
      sed -i "1a export DRUSH_PHP=\"\${DRUSH_PHP:-${_T_CLI}/php}\"" ${_DRUSH_LNCH} &> /dev/null
    fi
  fi
  rm -f ${_dscUsr}/static/control/.ctrl.cli.*.pid
  echo "${_T_CLI_VRN}" > ${_dscUsr}/static/control/.ctrl.cli.${_T_CLI_VRN}.${_xSrl}.pid
}

#
# Set default FPM workers.
_satellite_default_fpm_workers() {
  _count_cpu

  # Set _PHP_FPM_WORKERS to AUTO if it is empty
  [ -z "${_PHP_FPM_WORKERS}" ] && _PHP_FPM_WORKERS=AUTO
  # If _PHP_FPM_WORKERS is not AUTO and not empty, then check if it is less than 1
  if [ "${_PHP_FPM_WORKERS}" != "AUTO" ] && [ -n "${_PHP_FPM_WORKERS}" ]; then
    if [ "${_PHP_FPM_WORKERS}" -lt 1 ] 2>/dev/null; then
      _PHP_FPM_WORKERS=AUTO
    fi
  fi
  # If _PHP_FPM_WORKERS is not AUTO, remove non-numeric characters
  [ "${_PHP_FPM_WORKERS}" != "AUTO" ] && _PHP_FPM_WORKERS=${_PHP_FPM_WORKERS//[^0-9]/}

  if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
    _L_PHP_FPM_WORKERS=$(( _CPU_NR * 4 ))
  else
    _L_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}
  fi
  if [ -e "/root/.dev.server.cnf" ]; then
    echo "DEBUG: _L_PHP_FPM_WORKERS is ${_L_PHP_FPM_WORKERS}" >>/var/backups/ltd/log/users-${_NOW}.log
  fi

  # Set _PHP_FPM_TIMEOUT to AUTO if it is empty
  [ -z "${_PHP_FPM_TIMEOUT}" ] && _PHP_FPM_TIMEOUT=AUTO
  # If _PHP_FPM_TIMEOUT is not AUTO and not empty, then check if it is between 60 and 180
  if [ "${_PHP_FPM_TIMEOUT}" != "AUTO" ] && [ -n "${_PHP_FPM_TIMEOUT}" ]; then
    # If _PHP_FPM_TIMEOUT is not AUTO and not empty, remove non-numeric characters
    [ "${_PHP_FPM_TIMEOUT}" != "AUTO" ] && _PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT//[^0-9]/}
    # If _PHP_FPM_TIMEOUT is outside of the allowed range, use either min or max allowed
    if [ "${_PHP_FPM_TIMEOUT}" -lt 60 ]; then
      _PHP_FPM_TIMEOUT=60
    elif [ "${_PHP_FPM_TIMEOUT}" -gt 180 ]; then
      _PHP_FPM_TIMEOUT=180
    fi
  else
    _PHP_FPM_TIMEOUT=180
  fi

  if [ -e "/root/.dev.server.cnf" ]; then
    echo "DEBUG: _PHP_FPM_TIMEOUT is ${_PHP_FPM_TIMEOUT}" >>/var/backups/ltd/log/users-${_NOW}.log
  fi
}

#
# Compute a fully dynamic pm.max_children for dedicated pools (PHANTOM and
# above). Sized from total RAM (primary axis) and capped by CPU (sanity bound),
# using the measured per-child footprint. Independent of the per-plan tier. The
# knobs default to a reasonable calc and are tunable via control variables.
_php_fpm_dynamic_children() {
  local _ram_mb _ram_pct _uss_mb _cpu_factor _ram_max _cpu_max _dyn
  _count_cpu
  _ram_mb=$(free -mt 2>/dev/null | grep Mem: | awk '{ print $2 }')
  _ram_mb="${_ram_mb//[^0-9]/}"
  [ -z "${_ram_mb}" ] && _ram_mb=0
  # Percent of total RAM budgeted for FPM workers (AUTO/invalid -> 50).
  _ram_pct="${_PHP_FPM_RAM_PCT//[^0-9]/}"
  if [ -z "${_ram_pct}" ] || [ "${_ram_pct}" -lt 1 ]; then
    _ram_pct=50
  fi
  # Measured per-child private footprint (USS) in MB.
  _uss_mb="${_PHP_FPM_USS_MB//[^0-9]/}"
  if [ -z "${_uss_mb}" ] || [ "${_uss_mb}" -lt 1 ]; then
    _uss_mb=64
  fi
  # CPU sanity multiplier; workers are I/O-bound so > cores is expected (AUTO/invalid -> 8).
  _cpu_factor="${_PHP_FPM_CPU_FACTOR//[^0-9]/}"
  if [ -z "${_cpu_factor}" ] || [ "${_cpu_factor}" -lt 1 ]; then
    _cpu_factor=8
  fi
  _cpu_max=$(( _CPU_NR * _cpu_factor ))
  if [ "${_ram_mb}" -lt 1 ]; then
    # RAM unreadable: fall back to the CPU sanity bound, never to the low floor.
    _dyn="${_cpu_max}"
  else
    _ram_max=$(( _ram_mb * _ram_pct / 100 / _uss_mb ))
    if [ "${_ram_max}" -lt "${_cpu_max}" ]; then
      _dyn="${_ram_max}"
    else
      _dyn="${_cpu_max}"
    fi
  fi
  [ "${_dyn}" -lt 8 ] && _dyn=8
  echo "${_dyn}"
}

#
# Apply the dedicated/forced pm.max_children policy. A positive
# _PHP_FPM_MAX_CHILDREN_FORCE pins the value for any plan and is never clobbered.
# Otherwise dedicated plans (PHANTOM and above) under AUTO workers are sized
# fully dynamically; shared plans keep their computed per-plan tier value.
_php_fpm_apply_dynamic_children() {
  local _forced
  _forced="${_PHP_FPM_MAX_CHILDREN_FORCE//[^0-9]/}"
  if [ -n "${_forced}" ] && [ "${_forced}" -ge 2 ]; then
    # Clamp the pin to the universal floor so both pool writers honour it equally.
    [ "${_forced}" -lt 8 ] && _forced=8
    _CHILD_MAX_FPM="${_forced}"
    return 0
  fi
  if [ "${_PHP_FPM_WORKERS}" != "AUTO" ]; then
    return 0
  fi
  case "${_CLIENT_OPTION}" in
    PHANTOM|ULTRA|MONSTER|CLUSTER)
      _CHILD_MAX_FPM="$(_php_fpm_dynamic_children)"
      ;;
  esac
  return 0
}

#
# Per-pool PHP-FPM memory_limit (MB) for SHARED plans (POWER and below): a
# strictly restricted per-plan band, capped at a RAM-scaled box ceiling so a
# shared pool never exceeds box capacity on small VMs. Dedicated plans (PHANTOM
# and above) and unset return empty -> they inherit the generous box-wide
# value baked into the common include. A positive _PHP_FPM_MEMORY_LIMIT_FORCE
# (>= 64) pins the value for any plan.
_php_fpm_memory_limit() {
  local _forced _band _ram_total _cap
  _forced="${_PHP_FPM_MEMORY_LIMIT_FORCE//[^0-9]/}"
  if [ -n "${_forced}" ] && [ "${_forced}" -ge 64 ]; then
    echo "${_forced}"
    return 0
  fi
  case "${_CLIENT_OPTION}" in
    POWER|BUS)
      _band=768
      ;;
    EDGE|AGAIN|SSD|CLASSIC)
      _band=512
      ;;
    MINI|MICRO|QUIET|HEADSPACE)
      _band=256
      ;;
    *)
      return 0
      ;;
  esac
  _ram_total=$(free -mt 2>/dev/null | grep Mem: | awk '{ print $2 }')
  _ram_total="${_ram_total//[^0-9]/}"
  [ -z "${_ram_total}" ] && _ram_total=0
  if [ "${_ram_total}" -ge 1 ] && [ "${_ram_total}" -lt 2048 ]; then
    _cap=256
  elif [ "${_ram_total}" -ge 2048 ] && [ "${_ram_total}" -lt 4096 ]; then
    _cap=512
  else
    _cap=1024
  fi
  if [ "${_band}" -gt "${_cap}" ]; then
    _band="${_cap}"
  fi
  echo "${_band}"
}

#
# Tune FPM workers.
_satellite_tune_fpm_workers() {
  _satellite_default_fpm_workers

  _LIM_FPM="${_L_PHP_FPM_WORKERS}"

  if [ ! -z "${_CLIENT_OPTION}" ]; then
    if [ "${_CLIENT_OPTION}" = "MONSTER" ] || [ "${_CLIENT_OPTION}" = "CLUSTER" ]; then
      _CLIENT_OPTION=MONSTER
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=96
      fi
    elif [ "${_CLIENT_OPTION}" = "ULTRA" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=32
      fi
    elif [ "${_CLIENT_OPTION}" = "PHANTOM" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=16
      fi
    elif [ "${_CLIENT_OPTION}" = "POWER" ] \
      || [ "${_CLIENT_OPTION}" = "BUS" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=8
      fi
    elif [ "${_CLIENT_OPTION}" = "EDGE" ] \
      || [ "${_CLIENT_OPTION}" = "AGAIN" ] \
      || [ "${_CLIENT_OPTION}" = "SSD" ] \
      || [ "${_CLIENT_OPTION}" = "CLASSIC" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=2
      fi
    elif [ "${_CLIENT_OPTION}" = "MINI" ] \
      || [ "${_CLIENT_OPTION}" = "MICRO" ] \
      || [ "${_CLIENT_OPTION}" = "QUIET" ] \
      || [ "${_CLIENT_OPTION}" = "HEADSPACE" ]; then
      if [ "${_PHP_FPM_WORKERS}" = "AUTO" ]; then
        _LIM_FPM=1
      fi
    else
      _LIM_FPM=2
    fi
  fi

  if [ ! -z "${_CLIENT_CORES}" ] && [ "${_CLIENT_CORES}" -ge 1 ]; then
    if [ -e "${_dscUsr}/log/cores.txt" ]; then
      _CLIENT_CORES=$(cat ${_dscUsr}/log/cores.txt 2>&1)
      _CLIENT_CORES=$(echo -n ${_CLIENT_CORES} | tr -d "\n" 2>&1)
    fi
    _CLIENT_CORES=${_CLIENT_CORES//[^0-9]/}
    if [ ! -z "${_CLIENT_CORES}" ] && [ "${_CLIENT_CORES}" -ge 1 ]; then
      _LIM_FPM=$(( _LIM_FPM *= _CLIENT_CORES ))
    fi
  fi

  if [ "${_LIM_FPM}" -gt 100 ]; then
    _LIM_FPM=100
  fi

  if [ "${_CLIENT_OPTION}" != "QUIET" ]; then
    _CHILD_MAX_FPM=$(( _LIM_FPM * 2 ))
  fi

  _php_fpm_apply_dynamic_children
  _FPM_MEM_LIMIT="$(_php_fpm_memory_limit)"

  if [ -e "/root/.dev.server.cnf" ]; then
    echo "DEBUG: _LIM_FPM is ${_LIM_FPM}" >>/var/backups/ltd/log/users-${_NOW}.log
    echo "DEBUG: _PHP_FPM_WORKERS is ${_PHP_FPM_WORKERS}" >>/var/backups/ltd/log/users-${_NOW}.log
    echo "DEBUG: _CHILD_MAX_FPM is ${_CHILD_MAX_FPM}" >>/var/backups/ltd/log/users-${_NOW}.log
    echo "DEBUG: _FPM_MEM_LIMIT is ${_FPM_MEM_LIMIT}" >>/var/backups/ltd/log/users-${_NOW}.log
  fi
}

#
# Disable New Relic per Octopus instance.
_disable_newrelic() {
  _THIS_POOL_TPL="/opt/php$1/etc/pool.d/$2.conf"
  if [ -e "${_THIS_POOL_TPL}" ]; then
    _CHECK_NEW_RELIC_KEY=$(grep "newrelic.enabled.*true" ${_THIS_POOL_TPL} 2>&1)
    if [[ "${_CHECK_NEW_RELIC_KEY}" =~ "newrelic.enabled" ]]; then
      echo "New Relic for $2 will be disabled because newrelic.info does not exist"
      sed -i "s/^php_admin_value\[newrelic.license\].*/php_admin_value\[newrelic.license\] = \"\"/g" ${_THIS_POOL_TPL}
      wait
      sed -i "s/^php_admin_value\[newrelic.enabled\].*/php_admin_value\[newrelic.enabled\] = \"false\"/g" ${_THIS_POOL_TPL}
      wait
      if [ "$3" = "1" ] && [ -e "/etc/init.d/php$1-fpm" ]; then
        service php$1-fpm reload &> /dev/null
      fi
    fi
  fi
}
#
# Enable New Relic per Octopus instance.
_enable_newrelic() {
  _LOC_NEW_RELIC_KEY=$(cat ${_dscUsr}/static/control/newrelic.info 2>&1)
  _LOC_NEW_RELIC_KEY=${_LOC_NEW_RELIC_KEY//[^0-9a-zA-Z]/}
  _LOC_NEW_RELIC_KEY=$(echo -n ${_LOC_NEW_RELIC_KEY} | tr -d "\n" 2>&1)
  if [ -z "${_LOC_NEW_RELIC_KEY}" ]; then
    _disable_newrelic $1 $2 $3
  else
    _THIS_POOL_TPL="/opt/php$1/etc/pool.d/$2.conf"
    if [ -e "${_THIS_POOL_TPL}" ]; then
      _CHECK_NEW_RELIC_TPL=$(grep "newrelic.license" ${_THIS_POOL_TPL} 2>&1)
      _CHECK_NEW_RELIC_KEY=$(grep "${_LOC_NEW_RELIC_KEY}" ${_THIS_POOL_TPL} 2>&1)
      if [[ "${_CHECK_NEW_RELIC_KEY}" =~ "${_LOC_NEW_RELIC_KEY}" ]]; then
        echo "New Relic integration is already active for $2"
      else
        if [[ "${_CHECK_NEW_RELIC_TPL}" =~ "newrelic.license" ]]; then
          echo "New Relic for $2 update with key ${_LOC_NEW_RELIC_KEY} in php$1"
          sed -i "s/^php_admin_value\[newrelic.license\].*/php_admin_value\[newrelic.license\] = \"${_LOC_NEW_RELIC_KEY}\"/g" ${_THIS_POOL_TPL}
          wait
          sed -i "s/^php_admin_value\[newrelic.enabled\].*/php_admin_value\[newrelic.enabled\] = \"true\"/g" ${_THIS_POOL_TPL}
          wait
        else
          echo "New Relic for $2 setup with key ${_LOC_NEW_RELIC_KEY} in php$1"
          echo "php_admin_value[newrelic.license] = \"${_LOC_NEW_RELIC_KEY}\"" >> ${_THIS_POOL_TPL}
          echo "php_admin_value[newrelic.enabled] = \"true\"" >> ${_THIS_POOL_TPL}
        fi
        if [ "$3" = "1" ] && [ -e "/etc/init.d/php$1-fpm" ]; then
          service php$1-fpm reload &> /dev/null
        fi
      fi
    fi
  fi
}
#
# Switch New Relic on or off per Octopus instance.
_switch_newrelic() {
  _isPhp="$1"
  _isPhp=${_isPhp//[^0-9]/}
  _isUsr="$2"
  _isUsr=${_isUsr//[^a-z0-9]/}
  _isRld="$3"
  _isRld=${_isRld//[^0-1]/}
  if [ ! -z "${_isPhp}" ] && [ ! -z "${_isUsr}" ] && [ ! -z "${_isRld}" ]; then
    if [ -e "${_dscUsr}/static/control/newrelic.info" ]; then
      _enable_newrelic $1 $2 $3
    else
      _disable_newrelic $1 $2 $3
    fi
  fi
}
#
# Update web user.
_satellite_web_user_update() {
  _isTest="${_WEB}"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
    _T_HD="/home/${_WEB}/.drush"
    _T_TP="/home/${_WEB}/.tmp"
    _T_TS="/home/${_WEB}/.aws"
    _T_II="${_T_HD}/php.ini"
    if [ -d "/home/${_WEB}" ] && [ ! -e "/home/${_WEB}/.lock" ]; then
      chattr -i /home/${_WEB}
      # /home/<user>.web is owned by the FPM user, so a compromised hosted site
      # can plant these names; chattr, mkdir -p and cp -af all walk through a
      # link. Order matters: .drush first, then the file inside it.
      _desymlink_planted "/home/${_WEB}/.drush" "/home/${_WEB}/.tmp" \
        "/home/${_WEB}/.aws" "${_T_II}"
      if [ -d "/home/${_WEB}/.drush" ]; then
        chattr -i /home/${_WEB}/.drush
      fi
      if [ -e "${_T_II}" ]; then
        chattr -i ${_T_II}
      fi
      mkdir -p /home/${_WEB}/.{tmp,drush,aws}
      touch /home/${_WEB}/.lock
      _isTest="$1"
      _isTest=${_isTest//[^a-z0-9]/}
      if [ ! -z "${_isTest}" ]; then
        _T_PV=$1
      fi
      if [ ! -z "${_T_PV}" ] && [ -e "/opt/php${_T_PV}/etc/php${_T_PV}.ini" ]; then
        cp -af /opt/php${_T_PV}/etc/php${_T_PV}.ini ${_T_II}
      else
        if [ -e "/opt/php85/etc/php85.ini" ]; then
          cp -af /opt/php85/etc/php85.ini ${_T_II}
          _T_PV=85
        elif [ -e "/opt/php84/etc/php84.ini" ]; then
          cp -af /opt/php84/etc/php84.ini ${_T_II}
          _T_PV=84
        elif [ -e "/opt/php83/etc/php83.ini" ]; then
          cp -af /opt/php83/etc/php83.ini ${_T_II}
          _T_PV=83
        elif [ -e "/opt/php82/etc/php82.ini" ]; then
          cp -af /opt/php82/etc/php82.ini ${_T_II}
          _T_PV=82
        elif [ -e "/opt/php81/etc/php81.ini" ]; then
          cp -af /opt/php81/etc/php81.ini ${_T_II}
          _T_PV=81
        elif [ -e "/opt/php80/etc/php80.ini" ]; then
          cp -af /opt/php80/etc/php80.ini ${_T_II}
          _T_PV=80
        elif [ -e "/opt/php74/etc/php74.ini" ]; then
          cp -af /opt/php74/etc/php74.ini ${_T_II}
          _T_PV=74
        elif [ -e "/opt/php73/etc/php73.ini" ]; then
          cp -af /opt/php73/etc/php73.ini ${_T_II}
          _T_PV=73
        elif [ -e "/opt/php72/etc/php72.ini" ]; then
          cp -af /opt/php72/etc/php72.ini ${_T_II}
          _T_PV=72
        elif [ -e "/opt/php71/etc/php71.ini" ]; then
          cp -af /opt/php71/etc/php71.ini ${_T_II}
          _T_PV=71
        elif [ -e "/opt/php70/etc/php70.ini" ]; then
          cp -af /opt/php70/etc/php70.ini ${_T_II}
          _T_PV=70
        elif [ -e "/opt/php56/etc/php56.ini" ]; then
          cp -af /opt/php56/etc/php56.ini ${_T_II}
          _T_PV=56
        fi
      fi
      if [ -e "${_T_II}" ]; then
        # open_basedir stays out of the CLI ini: it breaks Drush and turns the
        # realpath cache off (every file operation checked against every listed
        # tree, uncached); lshell users are confined by their own measures, and
        # the FPM ini keeps its own list
        _QTP=${_T_TP//\//\\\/}
        sed -i "s/.*open_basedir =.*/;open_basedir =/g"                              ${_T_II}
        wait
        sed -i "s/.*session.save_path =.*/session.save_path = ${_QTP}/g"     ${_T_II}
        wait
        sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_QTP}/g" ${_T_II}
        wait
        sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_QTP}/g"               ${_T_II}
        wait
        sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_QTP}/g"           ${_T_II}
        wait
        rm -f ${_T_HD}/.ctrl.php*
        echo > ${_T_HD}/.ctrl.php${_T_PV}.${_xSrl}.pid
      fi
      chmod 700 /home/${_WEB}
      chown -R ${_WEB}:${_WEBG} /home/${_WEB}
      chmod 550 /home/${_WEB}/.drush
      chmod 440 /home/${_WEB}/.drush/php.ini
      rm -f /home/${_WEB}/.lock
      if [ -d "/home/${_WEB}" ]; then
        chattr +i /home/${_WEB}
      fi
      if [ -d "/home/${_WEB}/.drush" ]; then
        chattr +i /home/${_WEB}/.drush
      fi
      if [ -e "${_T_II}" ]; then
        chattr +i ${_T_II}
      fi
    fi
  fi
}
#
# Remove web user.
_satellite_remove_web_user() {
  _isTest="${_WEB}"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
    if [ -d "/home/${_WEB}/" ] || [ "$1" = "clean" ]; then
      # "clean" also runs for a web user that never existed (every new
      # per-version pool): nothing to unlock there, and chattr says so on
      # stderr once per installed PHP into this worker's log
      [ -d "/home/${_WEB}/" ] && chattr -i /home/${_WEB}/
      if [ -d "/home/${_WEB}/.drush/" ]; then
        chattr -i /home/${_WEB}/.drush/
      fi
      # only this user's agent (none for a user that never existed): -f
      # matched every gpg-agent on the box
      id -u "${_WEB}" &> /dev/null && pkill -9 -u "${_WEB}" gpg-agent &> /dev/null
      deluser \
        --remove-home \
        --backup-to /var/backups/zombie/deleted ${_WEB} &> /dev/null
      if [ -d "/home/${_WEB}/" ]; then
        rm -rf /home/${_WEB}/ &> /dev/null
      fi
    fi
  fi
}
#
# Add web user.
_satellite_create_web_user() {
  _isTest="${_WEB}"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [[ ! "${_WEB}" =~ ".ftp"($) ]]; then
    _T_HD="/home/${_WEB}/.drush"
    _T_II="${_T_HD}/php.ini"
    _T_ID_EXISTS=$(getent passwd ${_WEB} 2>&1)
    if [ ! -z "${_T_ID_EXISTS}" ] && [ -e "${_T_II}" ]; then
      _satellite_web_user_update "$1"
    elif [ -z "${_T_ID_EXISTS}" ] || [ ! -e "${_T_II}" ]; then
      _satellite_remove_web_user "clean"
      adduser --force-badname --system --ingroup www-data --home /home/${_WEB} ${_WEB} &> /dev/null
      _satellite_web_user_update "$1"
    fi
  fi
}
#
# Add site specific socket config include.
_site_socket_inc_gen() {
  _unlAeg="${_dscUsr}/static/control/unlock-aegir-php.info"
  _mltFpm="${_dscUsr}/static/control/multi-fpm.info"
  _preFpm="${_dscUsr}/static/control/.prev-multi-fpm.info"
  _mltNgx="${_dscUsr}/static/control/.multi-nginx-fpm.pid"
  _fpmPth="${_dscUsr}/config/server_master/nginx/post.d"
  # per account: an earlier account's forced regeneration must not carry
  # over to every account after it in the same pass
  _mltFpmUpdateForce=NO

  _hmFront=$(cat ${_dscUsr}/log/domain.txt 2>&1)
  _hmFront=$(echo -n ${_hmFront} | tr -d "\n" 2>&1)
  _hmstAls="${_dscUsr}/.drush/${_hmFront}.alias.drushrc.php"

  _hmstCli=$(cat ${_dscUsr}/log/cli.txt 2>&1)
  _hmstCli=$(echo -n ${_hmstCli} | tr -d "\n" 2>&1)

  # The <panel-fqdn> symlink to hostmaster.alias.drushrc.php was a crutch for
  # accounts whose hostmaster internals an old migration had left half
  # replaced; it also made the panel look like a site to anything that keys
  # on <fqdn>.alias files. Purge it here, in the regular pass, so an account
  # that still depends on it breaks visibly and is repaired BEFORE its next
  # migration instead of carrying the defect to a new box. Matched by shape,
  # not by the current panel name: a renamed box keeps the old-name symlink
  # too, and it is the same crutch. A real alias file is left alone.
  for _hmstLnk in ${_dscUsr}/.drush/*.alias.drushrc.php; do
    [ -L "${_hmstLnk}" ] || continue
    [ "$(readlink "${_hmstLnk}" 2>/dev/null)" = "${_dscUsr}/.drush/hostmaster.alias.drushrc.php" ] || continue
    rm -f ${_hmstLnk}
  done

  _desymlink_planted "${_mltFpm}"
  _PLACEHOLDER_TEST=$(grep "place.holder.dont.remove" ${_mltFpm} 2>&1)

  if [ ! -e "${_dscUsr}/log/no-lock-aegir-fpm.txt" ] \
    || [[ ! "${_PLACEHOLDER_TEST}" =~ "place.holder.dont.remove" ]]; then
    # a young account has no multi-fpm.info yet (the agents pass writes it
    # later); the two seds below have nothing to clean there and only left
    # "sed: can't read" in this worker's log every three minutes until it
    # appeared
    if [ -f "${_mltFpm}" ]; then
      sed -i "s/^${_hmFront} .*//g" ${_mltFpm}
      wait
      sed -i "s/^place.holder.dont.remove .*//g" ${_mltFpm}
      wait
    fi
    _PHP_V="85 84 83 82 81 74"
    _phpFnd=NO
    for e in ${_PHP_V}; do
      if [ -x "/opt/php${e}/bin/php" ] && [ "${_phpFnd}" = "NO" ]; then
        if [ "${e}" = 85 ]; then
          _phpDot=8.5
        elif [ "${e}" = 84 ]; then
          _phpDot=8.4
        elif [ "${e}" = 83 ]; then
          _phpDot=8.3
        elif [ "${e}" = 82 ]; then
          _phpDot=8.2
        elif [ "${e}" = 81 ]; then
          _phpDot=8.1
        elif [ "${e}" = 74 ]; then
          _phpDot=7.4
        fi
        # static/control itself is created later in this pass (behind the
        # ftp home's clients link); until then there is nowhere to write
        [ -d "${_dscUsr}/static/control" ] && echo "place.holder.dont.remove ${_phpDot}" >> ${_mltFpm}
        _phpFnd=YES
      fi
    done
    # still absent when no PHP binary was found above and nothing appended
    [ -f "${_mltFpm}" ] && sed -i "s/ *$//g; /^$/d" ${_mltFpm}
    wait
    touch ${_dscUsr}/log/no-lock-aegir-fpm.txt
    rm -f ${_dscUsr}/log/locked-aegir-fpm.txt
    touch ${_dscUsr}/log/unlocked-aegir-fpm.txt
    _mltFpmUpdateForce=YES
  fi

  if [ -x "/opt/php85/bin/php" ] && [ ! -e "/home/${_USER}.85.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  elif [ -x "/opt/php84/bin/php" ] && [ ! -e "/home/${_USER}.84.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  elif [ -x "/opt/php83/bin/php" ] && [ ! -e "/home/${_USER}.83.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  elif [ -x "/opt/php82/bin/php" ] && [ ! -e "/home/${_USER}.82.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  elif [ -x "/opt/php81/bin/php" ] && [ ! -e "/home/${_USER}.81.web" ]; then
    rm -f /data/disk/${_USER}/config/server_master/nginx/post.d/fpm_include_default.inc
    _mltFpmUpdateForce=YES
  fi

  if [ -f "${_mltFpm}" ]; then
    # static/control is tenant-owned, so a symlink named <x>.info is matched by
    # this glob; -h keeps the chown on the link instead of its target.
    chown -h ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control/*.info
    _mltFpmUpdate=NO
    if [ ! -f "${_preFpm}" ]; then
      rm -rf ${_preFpm}
      cp -af ${_mltFpm} ${_preFpm}
    fi
    _diffFpmTest=$(diff -w -B ${_mltFpm} ${_preFpm} 2>&1)
    if [ ! -z "${_diffFpmTest}" ]; then
      _mltFpmUpdate=YES
    fi
    if [ ! -f "${_mltNgx}" ] \
      || [ "${_mltFpmUpdate}" = "YES" ] \
      || [ "${_mltFpmUpdateForce}" = "YES" ]; then
      rm -f ${_fpmPth}/fpm_include_site_*
      IFS=$'\12'
      for p in `cat ${_mltFpm}`;do
        _SITE_NAME=`echo $p | cut -d' ' -f1 | awk '{ print $1}'`
        _SITE_NAME=${_SITE_NAME//[^a-zA-Z0-9-.]/}
        _SITE_NAME=$(echo -n ${_SITE_NAME} | tr A-Z a-z 2>&1)
        _SITE_NAME=$(echo -n ${_SITE_NAME} | tr -d "\n" 2>&1)
        _SITE_SOCKET=`echo $p | cut -d' ' -f2 | awk '{ print $1}'`
        _SITE_SOCKET=${_SITE_SOCKET//[^0-9]/}
        _SITE_SOCKET=$(echo -n ${_SITE_SOCKET} | tr -d "\n" 2>&1)
        _SOCKET_L_NAME="${_USER}.${_SITE_SOCKET}"
        if [ ! -z "${_SITE_NAME}" ] \
          && [ ! -z "${_SITE_SOCKET}" ] \
          && [ -x "/opt/php${_SITE_SOCKET}/bin/php" ] \
          && [ -e "${_dscUsr}/.drush/${_SITE_NAME}.alias.drushrc.php" ] \
          && [ -e "/run/${_SOCKET_L_NAME}.fpm.socket" ]; then
          _fpmInc="${_fpmPth}/fpm_include_site_${_SITE_NAME}.inc"
          echo "if ( \$main_site_name = ${_SITE_NAME} ) {" > ${_fpmInc}
          echo "  set \$user_socket \"${_SOCKET_L_NAME}\";" >> ${_fpmInc}
          echo "}" >> ${_fpmInc}
        fi
      done
      touch ${_mltNgx}
      rm -rf ${_preFpm}
      cp -af ${_mltFpm} ${_preFpm}
      ### reload nginx
      service nginx reload &> /dev/null
    fi
  else
    if [ -f "${_mltNgx}" ]; then
      rm -f ${_mltNgx}
    fi
    if [ -f "${_preFpm}" ]; then
      rm -f ${_preFpm}
    fi
  fi
}

#
# Switch PHP Version.
_switch_php() {
  _PHP_CLI_UPDATE=NO
  _FORCE_FPM_SETUP=NO
  _NEW_FPM_SETUP=NO
  _T_CLI_VRN=""

  if [ -e "${_dscUsr}/static/control/fpm.info" ] || [ -e "${_dscUsr}/static/control/cli.info" ]; then
    echo "Custom FPM and CLI settings for ${_USER} exist, running _switch_php checks"
    if [ ! -e "${_dscUsr}/log/un-chattr-ctrl.info" ]; then
      # static/control is tenant-owned; chattr opens the referent, so refuse a
      # planted link rather than clearing +i on whatever it points at.
      [ ! -L "${_dscUsr}/static/control/fpm.info" ] \
        && chattr -i ${_dscUsr}/static/control/fpm.info &> /dev/null
      [ ! -L "${_dscUsr}/static/control/cli.info" ] \
        && chattr -i ${_dscUsr}/static/control/cli.info &> /dev/null
      chattr -i ${_dscUsr}/log/fpm.txt &> /dev/null
      chattr -i ${_dscUsr}/log/cli.txt &> /dev/null
      chattr -i ${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc &> /dev/null
      touch ${_dscUsr}/log/un-chattr-ctrl.info
    fi

    if [ ! -e "${_dscUsr}/static/control/.single-fpm.${_xSrl}.pid" ]; then
      rm -f ${_dscUsr}/static/control/.single-fpm*.pid
      echo OK > ${_dscUsr}/static/control/.single-fpm.${_xSrl}.pid
      _FORCE_FPM_SETUP=YES
    fi

    # Convert shorthand versions (e.g. "83" to "8.3")
    fix_version_format() {
      case "$1" in
        85) echo "8.5";;
        84) echo "8.4";;
        83) echo "8.3";;
        82) echo "8.2";;
        81) echo "8.1";;
        80) echo "8.0";;
        74) echo "7.4";;
        73) echo "7.3";;
        72) echo "7.2";;
        71) echo "7.1";;
        70) echo "7.0";;
        56) echo "5.6";;
        *) echo "$1";;
      esac
    }

    # Helper function to check if a given PHP version is available
    check_version() {
      [ -x "/opt/php${1//./}/bin/php" ]
    }

    # --- CLI portion ---
    if [ -e "${_dscUsr}/static/control/cli.info" ]; then
      # Extract numeric version from file
      _T_CLI_VRN="$(tr -d '\n' < "${_dscUsr}/static/control/cli.info" | tr -cd '0-9.')"

      # Convert shorthand versions (e.g. "83" to "8.3")
      _T_CLI_VRN="$(fix_version_format "${_T_CLI_VRN}")"

      # Define fallback chains for PHP versions
      declare -A fallback=(
        ["8.5"]="8.4 8.3 8.2 8.1"
        ["8.4"]="8.3 8.2 8.1"
        ["8.3"]="8.2 8.1"
        ["8.2"]="8.1 8.3"
        ["8.1"]="8.2 8.3"
        ["8.0"]="8.1"
        ["7.4"]="8.1"
        ["7.3"]="7.4"
        ["7.2"]="7.4"
        ["7.1"]="7.4"
        ["7.0"]="7.4"
        ["5.6"]="7.4"
      )

      # Attempt fallback if the chosen version doesn't exist
      if [ -n "${_T_CLI_VRN}" ] && ! check_version "${_T_CLI_VRN}"; then
        for fbv in ${fallback["$_T_CLI_VRN"]}; do
          if check_version "${fbv}"; then
            _T_CLI_VRN="${fbv}"
            break
          fi
        done
      fi

      if [ -z "${_T_CLI_VRN}" ]; then
        echo "_T_CLI_VRN ELSE is EMPTY"
      else
        echo "_T_CLI_VRN is ${_T_CLI_VRN}"
        if [ "${_T_CLI_VRN}" != "${_PHP_CLI_VERSION}" ] || [ ! -e "${_dscUsr}/static/control/.ctrl.cli.${_T_CLI_VRN}.${_xSrl}.pid" ]; then
          _PHP_CLI_UPDATE=YES
          _DRUSH_FILES="drush.php drush"
          for _df in ${_DRUSH_FILES}; do
            _php_cli_drush_update "${_df}"
          done
          if [ -x "${_T_CLI}/php" ]; then
            _php_cli_local_ini_update
            sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_T_CLI_VRN}/g" /root/.${_USER}.octopus.cnf &> /dev/null
            echo "${_T_CLI_VRN}" > "${_dscUsr}/log/cli.txt"
            _desymlink_planted "${_dscUsr}/static/control/cli.info"
            echo "${_T_CLI_VRN}" > "${_dscUsr}/static/control/cli.info"
            chown -h "${_USER}.ftp:${_usrGroup}" "${_dscUsr}/static/control/cli.info"
          fi
        fi
      fi
    fi

    # --- FPM portion ---
    if [ -e "${_dscUsr}/static/control/fpm.info" ] && [ -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
      _PHP_FPM_MULTI=NO
      if [ -f "${_dscUsr}/static/control/multi-fpm.info" ] && [ -d "${_dscUsr}/tools/le" ]; then
        _PHP_FPM_MULTI=YES
        if [ ! -e "${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid" ]; then
          rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
          echo OK > ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
          _FORCE_FPM_SETUP=YES
        fi
      else
        if [ -e "${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc" ]; then
          rm -f ${_dscUsr}/config/server_master/nginx/post.d/fpm_include_*
          rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
          service nginx reload &> /dev/null
        fi
      fi

      # Read and sanitize the FPM version
      _T_FPM_VRN=$(tr -d '\n' < ${_dscUsr}/static/control/fpm.info | tr -cd '0-9.')

      # Convert shorthand versions (e.g. "83" to "8.3")
      _T_FPM_VRN="$(fix_version_format "${_T_FPM_VRN}")"

      # Define fallback chains for PHP-FPM versions (same as CLI)
      declare -A fpm_fallback=(
        ["8.5"]="8.4 8.3 8.2 8.1"
        ["8.4"]="8.3 8.2 8.1"
        ["8.3"]="8.2 8.1"
        ["8.2"]="8.1 8.3"
        ["8.1"]="8.2 8.3"
        ["8.0"]="8.3"
        ["7.4"]="8.3"
        ["7.3"]="7.4"
        ["7.2"]="7.4"
        ["7.1"]="7.4"
        ["7.0"]="7.4"
        ["5.6"]="7.4"
      )

      # Attempt fallback if the chosen version doesn't exist
      if [ -n "${_T_FPM_VRN}" ] && ! check_version "${_T_FPM_VRN}"; then
        for fbv in ${fpm_fallback["$_T_FPM_VRN"]}; do
          if check_version "${fbv}"; then
            _T_FPM_VRN="${fbv}"
            break
          else
            # If fallback not found, reset _T_FPM_VRN
            _T_FPM_VRN=""
          fi
        done
      fi

      if [ "${_T_FPM_VRN}" != "${_PHP_FPM_VERSION}" ] || [ "${_FORCE_FPM_SETUP}" = "YES" ]; then
        if [ -n "${_T_FPM_VRN}" ]; then
          _NEW_FPM_SETUP=YES
        fi
      fi

      ### Update fpm_include_default.inc if needed
      _PHP_SV=${_T_FPM_VRN//[^0-9]/}
      [ -z "${_PHP_SV}" ] && _PHP_SV=84
      _FMP_D_INC="${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc"

      if [ "${_PHP_FPM_MULTI}" = "YES" ] && [ -d "${_dscUsr}/tools/le" ]; then
        _PHP_M_V="85 84 83 82 81 80 74 73 72 71 70 56"
        _D_POOL="${_USER}.${_PHP_SV}"
        if [ ! -e "${_FMP_D_INC}" ]; then
          echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
          touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
          _NEW_FPM_SETUP=YES
        else
          _CHECK_FMP_D=$(grep "${_D_POOL}" ${_FMP_D_INC} 2>&1)
          if [[ ! "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]]; then
            echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
            echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
            touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
            _NEW_FPM_SETUP=YES
          fi
        fi
      else
        _PHP_M_V="${_PHP_SV}"
        rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
        rm -f ${_FMP_D_INC}
      fi

      if [ -n "${_T_FPM_VRN}" ] && [ "${_NEW_FPM_SETUP}" = "YES" ]; then
        _satellite_tune_fpm_workers
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_T_FPM_VRN}/g" /root/.${_USER}.octopus.cnf &> /dev/null
        echo "${_T_FPM_VRN}" > ${_dscUsr}/log/fpm.txt
        if [ "${_PHP_FPM_MULTI}" = "NO" ]; then
          _desymlink_planted "${_dscUsr}/static/control/fpm.info"
        echo "${_T_FPM_VRN}" > ${_dscUsr}/static/control/fpm.info
        fi
        chown -h ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control/fpm.info

        _PHP_OLD_SV=${_PHP_FPM_VERSION//[^0-9]/}
        _PHP_SV=${_T_FPM_VRN//[^0-9]/}
        [ -z "${_PHP_SV}" ] && _PHP_SV=84

        # Update or create special system user if needed
        if [ "${_PHP_FPM_MULTI}" = "YES" ] && [ -d "${_dscUsr}/tools/le" ]; then
          _PHP_M_V="85 84 83 82 81 80 74 73 72 71 70 56"
          _D_POOL="${_USER}.${_PHP_SV}"
          if [ ! -e "${_FMP_D_INC}" ] && [ -e "/run/${_D_POOL}.fpm.socket" ] && [ -x "/opt/php${_PHP_SV}/bin/php" ]; then
            echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
            touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
          else
            _CHECK_FMP_D=$(grep "${_D_POOL}" ${_FMP_D_INC} 2>&1)
            if [[ ! "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]] && [ -e "/run/${_D_POOL}.fpm.socket" ] && [ -x "/opt/php${_PHP_SV}/bin/php" ]; then
              echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
              echo "set \$user_socket \"${_D_POOL}\";" > ${_FMP_D_INC}
              touch ${_dscUsr}/static/control/.multi-fpm.${_xSrl}.pid
            fi
          fi
        else
          _PHP_M_V="${_PHP_SV}"
          rm -f ${_dscUsr}/static/control/.multi-fpm*.pid
          rm -f ${_FMP_D_INC}
        fi

        # Update/create web users
        for m in ${_PHP_M_V}; do
          if [ -x "/opt/php${m}/bin/php" ]; then
            if [ "${_PHP_FPM_MULTI}" = "YES" ] && [ -d "${_dscUsr}/tools/le" ]; then
              _WEB="${_USER}.${m}.web"
              _POOL="${_USER}.${m}"
            else
              _WEB="${_USER}.web"
              _POOL="${_USER}"
            fi
            if [ -e "/home/${_WEB}/.drush/php.ini" ]; then
              _OLD_PHP_IN_USE=$(grep "/lib/php" /home/${_WEB}/.drush/php.ini 2>&1)
              _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
              for e in ${_PHP_V}; do
                if [[ "${_OLD_PHP_IN_USE}" =~ "php${e}" ]]; then
                  if [ "${e}" != "${m}" ] || [ ! -e "/home/${_WEB}/.drush/.ctrl.php${m}.${_xSrl}.pid" ]; then
                    echo "_OLD_PHP_IN_USE is ${_OLD_PHP_IN_USE} for ${_WEB}, updating to ${m}"
                    _satellite_web_user_update "${m}"
                  fi
                fi
              done
            else
              echo "_NEW_PHP_TO_USE is ${m} for ${_WEB}, creating"
              _satellite_create_web_user "${m}"
            fi
          fi
        done

        # Cleanup old pool files and set up new pools
        if [ "${_PHP_FPM_MULTI}" = "YES" ] && [ -d "${_dscUsr}/tools/le" ]; then
          _PHP_M_V="85 84 83 82 81 80 74 73 72 71 70 56"
          rm -f /opt/php*/etc/pool.d/${_USER}.conf
        else
          _PHP_M_V="${_PHP_SV}"
          rm -f /opt/php*/etc/pool.d/${_USER}.*.conf
          rm -f /opt/php*/etc/pool.d/${_USER}.conf
        fi

        for m in ${_PHP_M_V}; do
          if [ -x "/opt/php${m}/bin/php" ]; then
            if [ "${_PHP_FPM_MULTI}" = "YES" ] && [ -d "${_dscUsr}/tools/le" ]; then
              _WEB="${_USER}.${m}.web"
              _POOL="${_USER}.${m}"
              cp -af /var/xdrago/conf/fpm-pool-foo-multi.conf /opt/php${m}/etc/pool.d/${_POOL}.conf
            else
              _WEB="${_USER}.web"
              _POOL="${_USER}"
              cp -af /var/xdrago/conf/fpm-pool-foo.conf /opt/php${m}/etc/pool.d/${_POOL}.conf
            fi
            sed -i "s/.ftp/.web/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
            wait
            sed -i "s/\/data\/disk\/foo\/.tmp/\/home\/foo.web\/.tmp/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
            wait
            sed -i "s/foo.web/${_WEB}/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
            wait
            sed -i "s/THISPOOL/${_POOL}/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
            wait
            sed -i "s/foo/${_USER}/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
            wait

            if [[ "${m}" == 8* ]] && [ -e "/opt/etc/fpm/fpm-pool-common-modern.conf" ]; then
              sed -i "s/fpm-pool-common.conf/fpm-pool-common-modern.conf/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
            elif [[ "${m}" == 7* ]] && [ -e "/opt/etc/fpm/fpm-pool-common-legacy.conf" ]; then
              sed -i "s/fpm-pool-common.conf/fpm-pool-common-legacy.conf/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
            fi

            [ -n "${_PHP_FPM_DENY}" ] && sed -i "s/passthru,/${_PHP_FPM_DENY},/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
            wait

            if [ -n "${_PHP_FPM_TIMEOUT}" ] && [ "${_PHP_FPM_TIMEOUT}" -ge 60 ]; then
              _PHP_TO="${_PHP_FPM_TIMEOUT}s"
              sed -i "s/180s/${_PHP_TO}/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
            fi

            if [ -n "${_CHILD_MAX_FPM}" ] && [ "${_CHILD_MAX_FPM}" -ge 2 ]; then
              sed -i "s/pm.max_children =.*/pm.max_children = ${_CHILD_MAX_FPM}/g" /opt/php${m}/etc/pool.d/${_POOL}.conf &> /dev/null
              wait
            fi

            if [ -n "${_FPM_MEM_LIMIT}" ] && [ "${_FPM_MEM_LIMIT}" -ge 64 ]; then
              echo "php_admin_value[memory_limit] = ${_FPM_MEM_LIMIT}M" >> /opt/php${m}/etc/pool.d/${_POOL}.conf
              wait
            fi

            _switch_newrelic ${m} ${_POOL} 0

            mkdir -p /var/www/phpcache/${_USER}/${_POOL}
            chgrp www-data /var/www/phpcache/${_USER}/${_POOL}
            chmod 770 /var/www/phpcache/${_USER}/${_POOL}

            [ -e "/etc/init.d/php${_PHP_OLD_SV}-fpm" ] && service php${_PHP_OLD_SV}-fpm reload &> /dev/null
            [ -e "/etc/init.d/php${m}-fpm" ] && service php${m}-fpm reload &> /dev/null
          fi
        done
      fi
    fi
  fi
}

#
# Manage mirroring of drush aliases.
_manage_site_drush_alias_mirror() {

  _ALS_TEST=$(ls -la /home/${_USER}.ftp/.drush/*.alias.drushrc.php 2>&1)
  if [[ ! "${_ALS_TEST}" =~ "No such file" ]]; then
    for _Alias in `find /home/${_USER}.ftp/.drush/*.alias.drushrc.php \
      -maxdepth 1 -type f | sort`; do
      _AliasFile=$(echo "${_Alias}" | cut -d'/' -f5 | awk '{ print $1}' 2>&1)
      if [ ! -e "${_pthParentUsr}/.drush/${_AliasFile}" ] \
        && [ ! -z "${_AliasFile}" ]; then
        rm -f /home/${_USER}.ftp/.drush/${_AliasFile}
     fi
    done
  fi

  if [ -e "/home/${_USER}.ftp/.drush/hm.alias.drushrc.php" ]; then
    rm -f /home/${_USER}.ftp/.drush/hm.alias.drushrc.php
  fi
  if [ -e "/home/${_USER}.ftp/.drush/self.alias.drushrc.php" ]; then
    rm -f /home/${_USER}.ftp/.drush/self.alias.drushrc.php
  fi
  if [ -e "${_dscUsr}/.drush/.alias.drushrc.php" ]; then
    rm -f ${_dscUsr}/.drush/.alias.drushrc.php
  fi

  _isAliasUpdate=NO
  _GHOST_REAPED=NO
  for _Alias in `find ${_pthParentUsr}/.drush/*.alias.drushrc.php \
    -maxdepth 1 -type f | sort`; do
    ### echo Last_AliasName is ${_AliasName}
    _SiteDir=
    _SiteName=
    _AliasName=
    _AliasName=$(echo "${_Alias}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
    _AliasName=$(echo "${_AliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [ "${_AliasName}" = "hm" ] \
      || [ "${_AliasName}" = "none" ] \
      || [[ "${_AliasName}" =~ (^)"platform_" ]] \
      || [[ "${_AliasName}" =~ (^)"server_" ]] \
      || [[ "${_AliasName}" =~ (^)"self" ]] \
      || [[ "${_AliasName}" =~ (^)"hostmaster" ]] \
      || [ -z "${_AliasName}" ]; then
      _IS_SITE=NO
      _AliasName=
      _SiteName=
      _SiteDir=
    else
      _SiteName="${_AliasName}"
      ### echo _SiteName is "${_SiteName}"
      _SiteDir=
      if [[ "${_SiteName}" =~ ".restore"($) ]]; then
        _IS_SITE=NO
        # A .restore alias is Aegir's own transient artifact for a restore task,
        # and this loop runs every 3 minutes against the AUTHORITATIVE alias dir
        # -- so deleting one mid-restore pulls the alias out from under the task.
        # The ghost branch below already refuses to reap while a task is in
        # flight or while the alias is fresh; this leg had no guard at all.
        if _provision_running; then
          : # Ægir task in flight -- the restore may still need this alias
        elif [ -n "$(find ${_Alias} -mmin -60 2>/dev/null)" ]; then
          : # written in the last hour -- likely the task that owns it
        else
          rm -f ${_pthParentUsr}/.drush/${_SiteName}.alias.drushrc.php
        fi
      else
        _SiteDir=$(cat ${_Alias} \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        # Fail closed: a degraded/mid-rewrite alias parses to an empty or
        # non-/data/disk site_path -> KEEP, never reap on a bad parse.
        if [ -z "${_SiteDir}" ] \
          || [ "${_SiteDir}" = "${_SiteDir#/data/disk/}" ]; then
          _IS_SITE=YES
          rm -f ${_pthParentUsr}/log/ctrl/ghost-ltd-${_SiteName}.seen 2>/dev/null
        elif [ -e "${_SiteDir}/drushrc.php" ] \
          || [ -L "${_SiteDir}/drushrc.php" ]; then
          # drushrc.php present = a registered, live site. Mirror its alias to
          # the limited-shell user. Do NOT also require files/private: those are
          # native-symlinked store targets that can be transiently absent.
          # A valid sighting always clears the ghost hold marker, so a site
          # that recovered mid-hold never carries a stale count into a reap.
          rm -f ${_pthParentUsr}/log/ctrl/ghost-ltd-${_SiteName}.seen 2>/dev/null
          _pthAliasMain="${_pthParentUsr}/.drush/${_SiteName}.alias.drushrc.php"
          _pthAliasCopy="/home/${_USER}.ftp/.drush/${_SiteName}.alias.drushrc.php"
          # Root-written control file in the tenant's own home: cp -af follows a
          # symlinked DESTINATION and preserves ownership onto it, chmod follows
          # too. Strip the copy only -- the main alias may legitimately be a link.
          _desymlink_planted "${_pthAliasCopy}"
          if [ ! -e "${_pthAliasCopy}" ]; then
            cp -af ${_pthAliasMain} ${_pthAliasCopy}
            [ ! -L "${_pthAliasCopy}" ] && chmod 440 ${_pthAliasCopy}
            _isAliasUpdate=YES
          else
            _DIFF_T=$(diff -w -B ${_pthAliasCopy} ${_pthAliasMain} 2>&1)
            if [ ! -z "${_DIFF_T}" ]; then
              cp -af ${_pthAliasMain} ${_pthAliasCopy}
              [ ! -L "${_pthAliasCopy}" ] && chmod 440 ${_pthAliasCopy}
              _isAliasUpdate=YES
            fi
          fi
        else
          # drushrc.php absent = ghost candidate. This runs every 3 minutes, so a
          # mid-install/clone site (alias written before its dir is populated)
          # MUST NOT be reaped: skip while an Ægir task is in flight, and while
          # the alias is recently written (< 60 min). Then gate on the opt-in
          # _GHOST_ALIASES_CLEANUP flag (no night.inc.sh here, so check inline).
          _pthAliasCopy="/home/${_USER}.ftp/.drush/${_SiteName}.alias.drushrc.php"
          if _provision_running; then
            : # Ægir task in flight -- the site may be mid-build
          elif [ -n "$(find ${_Alias} -mmin -60 2>/dev/null)" ]; then
            : # alias freshly written (< 60 min) -- likely mid-install/clone
          elif [[ "${_SiteDir}" =~ "aegir/distro" ]]; then
            : # front-end companion (control panel machinery, stale after a
            : # hostname rename or distro bump) -- never reaped here; the
            : # nightly classifier owns these as operator-review items
          elif [ -e "/root/.standby.cnf" ]; then
            : # replication standby: aliases and site dirs arrive by
            : # replication and rsync on their own clocks, so a mid-sync
            : # mismatch is normal -- never reap here
          else
            _GA_OCT="/root/.$(basename ${_pthParentUsr} 2>/dev/null).octopus.cnf"
            _GA_ON=NO
            grep -qiE "^[[:space:]]*_GHOST_ALIASES_CLEANUP=[\"' ]*YES" "${_GA_OCT}" 2>/dev/null && _GA_ON=YES
            grep -qiE "^[[:space:]]*_GHOST_ALIASES_CLEANUP=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null && _GA_ON=YES
            echo "ZOMBIE ${_SiteDir} detected for ${_SiteName}"
            if [ "${_GA_ON}" = "YES" ]; then
              # The alias mtime is no protection during an inbound xoct/xcopy
              # transfer (rsync -a preserves source mtimes; rsync is not a
              # provision process), and /etc/boa/.pause_tasks_maint.cnf is
              # auto-removed on hosted systems within minutes. So persist the
              # first sighting in a marker this script owns and act only once
              # the marker is 48h old: any transfer or rename-rewrite window
              # is far shorter, and on an armed system the classified nightly
              # reaper (client notice, operator-review skips) acts first.
              # Markers start only while the flag is YES, so a flip never
              # mass-reaps accumulated ghosts on its first pass.
              mkdir -p ${_pthParentUsr}/log/ctrl
              _GA_MARK="${_pthParentUsr}/log/ctrl/ghost-ltd-${_SiteName}.seen"
              if [ ! -e "${_GA_MARK}" ]; then
                touch ${_GA_MARK}
                echo "GHOST ${_SiteName}.alias sighted, held for 48h before any move"
              elif [ -n "$(find ${_GA_MARK} -mmin +2880 2>/dev/null)" ]; then
                mkdir -p ${_pthParentUsr}/undo
                _GHOST_REAPED=YES
                rm -f ${_GA_MARK}
                rm -f ${_pthAliasCopy}
                mv -f ${_pthParentUsr}/.drush/${_SiteName}.alias.drushrc.php ${_pthParentUsr}/undo/ &> /dev/null
                echo "GHOST ${_SiteName}.alias.drushrc.php moved to ${_pthParentUsr}/undo/"
              else
                echo "GHOST ${_SiteName}.alias sighted, still inside the 48h hold"
              fi
            else
              echo "GHOST ${_SiteName}.alias detected (dry-run; set _GHOST_ALIASES_CLEANUP=YES to move)"
            fi
          fi
        fi
      fi
    fi
  done
  # The alias-store rebuild wipes and regenerates ~/.drush/sites from the
  # drushrc aliases -- on a standby those arrive by rsync mid-window, and
  # a rebuild against a half-landed set bakes the gaps in. Scoped gate:
  # everything above (users, inis, pools) already ran.
  if [ -x "/usr/bin/drush10" ] && [ "${_GHOST_REAPED}" != "YES" ] \
    && [ ! -e "/root/.standby.cnf" ]; then
    if [ "${_isAliasUpdate}" = "YES" ] \
      || [ ! -e "/home/${_USER}.ftp/.drush/sites/.checksums" ]; then
      chage -M 99999 ${_USER}.ftp &> /dev/null
      su -s /bin/bash - ${_USER}.ftp -c "rm -f ~/.drush/sites/*.yml"
      wait
      su -s /bin/bash - ${_USER}.ftp -c "rm -f ~/.drush/sites/.checksums/*.md5"
      wait
      su -s /bin/bash - ${_USER}.ftp -c "drush10 core:init --yes" &> /dev/null
      wait
      su -s /bin/bash - ${_USER}.ftp -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
      wait
      chage -M 90 ${_USER}.ftp &> /dev/null
      ### Update Drush yml sites aliases also for Ægir system user
      su -s /bin/bash - ${_USER} -c "rm -f ~/.drush/sites/*.yml"
      wait
      su -s /bin/bash - ${_USER} -c "rm -f ~/.drush/sites/.checksums/*.md5"
      wait
      su -s /bin/bash - ${_USER} -c "drush10 core:init --yes" &> /dev/null
      wait
      su -s /bin/bash - ${_USER} -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
      wait
    fi
  fi
}
#
# Manage Primary Users.
# provision parks the de-typed psr/log overlay of every Drupal 10+ unlock
# (a clone, migrate or restore deploy, provision-dunlock) under the account's
# ~/.tmp/psr-log-<date>-<rand> and touches the dir, since mv keeps the
# overlay's old mtime. Nothing reads a stash back (the re-lock re-applies the
# overlay from the account's Drush), so it goes after a week -- on EVERY run,
# unlike the release-gated ~/.tmp sweep above it, which fires once per serial.
# Older releases stashed the same dirs beside the site archives under
# backups/; those are pruned by the same age so the pile ends everywhere.
# Bare paths, -maxdepth 1 and -type d: a planted link is neither followed nor
# matched (as at the sweep above).
_prune_psr_log_stash() {
  local _h="${1}"
  [ -n "${_h}" ] && [ -d "${_h}" ] || return 0
  find ${_h}/.tmp -mindepth 1 -maxdepth 1 -type d -name 'psr-log-*' \
    -mtime +6 -exec rm -rf {} + &> /dev/null
  find ${_h}/backups -mindepth 1 -maxdepth 1 -type d -name 'psr-log-*' \
    -mtime +6 -exec rm -rf {} + &> /dev/null
}

_manage_user() {
  _repair_staged_homes
  for _pthParentUsr in `find /data/disk/ -maxdepth 1 -mindepth 1 | sort`; do
    if [ -e "${_pthParentUsr}/config/server_master/nginx/vhost.d" ] \
      && [ -e "${_pthParentUsr}/log/fpm.txt" ] \
      && [ ! -e "${_pthParentUsr}/log/proxied.pid" ] \
      && [ ! -e "${_pthParentUsr}/log/CANCELLED" ]; then
      _MNT_STATIC_FILES=""
      _mntPoint=""
      _USER=""
      _USER=$(echo ${_pthParentUsr} | cut -d'/' -f4 | awk '{ print $1}' 2>&1)
      # The nightly's per-account pass holds this account's home unlocked for
      # minutes and relocks it at its end; a rebuild in flight here would meet
      # that relock half way (EPERM on every write). Leave the account to the
      # next pass while the marker names a live pass (a dead pid is a killed
      # pass and its marker goes) -- but its lshell stanzas are emitted from
      # the body skipped here, and the conf built this pass replaces the live
      # one on any difference, so carry them over from the live file as they
      # stand or its users would drop to [default] until the hold clears.
      if [ -e "/run/night-account-${_USER}.pid" ]; then
        if kill -0 "$(cat /run/night-account-${_USER}.pid 2>/dev/null)" 2>/dev/null; then
          echo "skipping ${_USER}: the nightly per-account pass holds it"
          echo >> ${_THIS_LTD_CONF}
          awk -v u="${_USER}" '/^\[/ { p = ($0 ~ "^\\[" u "\\.") } p' /etc/lshell.conf >> ${_THIS_LTD_CONF}
          continue
        fi
        rm -f /run/night-account-${_USER}.pid
      fi
      # Identity heal: an account whose marker records THIS box's group but
      # whose backend or shell identity fell back to the box-wide primary
      # group (a hand usermod, a restored passwd) makes _acct_group fail open
      # to 'users' and every root writer re-flatten the tree while the marker
      # still reads converted. Move it back, 'users' listed first, as for the
      # sub-users below.
      # Converted = the group exists and the marker records it, or the backend
      # or shell identity already carries it as primary (a born-converted
      # account has no marker until its first upgrade).
      _igMark="${_pthParentUsr}/log/instance-group.txt"
      _igGid=$(getent group "${_USER}" 2>/dev/null | cut -d: -f3)
      _igConv=NO
      if [ -n "${_igGid}" ]; then
        if [ -f "${_igMark}" ] && [ ! -L "${_igMark}" ] && grep -q " gid=${_igGid}$" "${_igMark}" 2>/dev/null; then
          _igConv=YES
        elif [ "$(id -gn ${_USER} 2>/dev/null)" = "${_USER}" ] || [ "$(id -gn ${_USER}.ftp 2>/dev/null)" = "${_USER}" ]; then
          _igConv=YES
        fi
      fi
      if [ "${_igConv}" = "YES" ]; then
        for _igU in ${_USER} ${_USER}.ftp; do
          getent passwd "${_igU}" >/dev/null 2>&1 || continue
          [ "$(id -gn ${_igU} 2>/dev/null)" = "${_USER}" ] && continue
          if ! getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_igU}"; then
            usermod -aG users ${_igU}
          fi
          if getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_igU}"; then
            _set_primary_group ${_igU} ${_USER}
            if [ "$(id -gn ${_igU} 2>/dev/null)" = "${_USER}" ] \
              && id -nG ${_igU} 2>/dev/null | tr ' ' '\n' | grep -qxF users; then
              # Listed as a member too: provision's membership test reads
              # the group database, where a primary group never shows.
              getent group ${_USER} | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_igU}" || gpasswd -a ${_igU} ${_USER} >/dev/null 2>&1
              echo "Identity ${_igU} moved back to primary group ${_USER}"
            elif [ "$(id -gn ${_igU} 2>/dev/null)" = "${_USER}" ]; then
              _set_primary_group ${_igU} users
              echo "ALERT: ${_igU} lost group users on the primary move, reverted to users"
            else
              echo "ALERT: ${_igU} could not be moved to primary group ${_USER}; left on $(id -gn ${_igU} 2>/dev/null)"
            fi
          fi
        done
      fi
      # Group owning this account's tree, re-derived every iteration so no
      # value carries over to the next account. Falls back to the box-wide
      # default on an account that has no private group.
      _usrGroup=$(_acct_group "${_USER}")
      echo "_USER is == ${_USER} == at _manage_user"
      if getent group allow-snail >/dev/null 2>&1 && \
        ! id -nG "${_USER}" 2>/dev/null | tr ' ' '\n' | grep -qxF "allow-snail"; then
        usermod -aG allow-snail "${_USER}"
      fi
      _WEB="${_USER}.web"
      _dscUsr="/data/disk/${_USER}"
      _octInc="${_dscUsr}/config/includes"
      _octTpl="${_dscUsr}/.drush/sys/provision/http/Provision/Config/Nginx"
      if [ -e "${_dscUsr}/log/imported.pid" ] \
        && [ -e "${_dscUsr}/log/post-merge-fix.pid" ]; then
        [ -e "${_dscUsr}/log/imported.pid" ] && mv -f ${_dscUsr}/log/imported.pid ${_dscUsr}/src/
        [ -e "${_dscUsr}/log/exported.pid" ] && mv -f ${_dscUsr}/log/exported.pid ${_dscUsr}/src/
        [ -e "${_dscUsr}/log/hmpathfix.pid" ] && mv -f ${_dscUsr}/log/hmpathfix.pid ${_dscUsr}/src/
        [ -e "${_dscUsr}/log/post-merge-fix.pid" ] && mv -f ${_dscUsr}/log/post-merge-fix.pid ${_dscUsr}/src/
      fi
      if [ ! -e "${_dscUsr}/rector.php" ]; then
        rm -f ${_dscUsr}/*.php* &> /dev/null
        rm -f ${_dscUsr}/composer.lock &> /dev/null
        rm -f ${_dscUsr}/composer.json &> /dev/null
        rm -f -r ${_dscUsr}/vendor &> /dev/null
        rm -f -r ${_dscUsr}/static/vendor &> /dev/null
        rm -f -r ${_dscUsr}/.cache/composer &> /dev/null
        rm -f -r ${_dscUsr}/.config/composer &> /dev/null
        rm -f -r ${_dscUsr}/.composer &> /dev/null
      fi
      ### .drush is owned by oN, the identity every Ægir task and site-local
      ### Drush run as, so a hostile drush include or a compromised task can
      ### unlink an alias and plant a symlink at its name. chmod follows that link, and 0400 on a shared system path takes
      ### the box down. Only ever chmod a real file.
      for _aFil in ${_dscUsr}/.drush/*.php; do
        [ -f "${_aFil}" ] && [ ! -L "${_aFil}" ] \
          && chmod 0440 "${_aFil}" &> /dev/null
      done
      for _aFil in ${_dscUsr}/.drush/drushrc.php \
        ${_dscUsr}/.drush/hm.alias.drushrc.php \
        ${_dscUsr}/.drush/hostmaster*.php \
        ${_dscUsr}/.drush/platform_*.php \
        ${_dscUsr}/.drush/server_*.php; do
        [ -f "${_aFil}" ] && [ ! -L "${_aFil}" ] \
          && chmod 0400 "${_aFil}" &> /dev/null
      done
      chmod 0710 ${_dscUsr}/.drush &> /dev/null
      find ${_dscUsr}/config/server_master \
        -type d -exec chmod 0700 {} \; &> /dev/null
      find ${_dscUsr}/config/server_master \
        -type f -exec chmod 0600 {} \; &> /dev/null
      chmod +rx ${_dscUsr}/config{,/server_master{,/nginx{,/passwords.d}}} &> /dev/null
      chmod +r ${_dscUsr}/config/server_master/nginx/passwords.d/* &> /dev/null
      if [ ! -e "${_dscUsr}/.tmp/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
        rm -rf ${_dscUsr}/.drush/cache
        _desymlink_planted "${_dscUsr}/.tmp"
        mkdir -p ${_dscUsr}/.tmp
        touch ${_dscUsr}/.tmp
        # Bare path, not ${_dscUsr}/.tmp/ -- a trailing slash makes find follow
        # a planted link and purge the target tree instead (as at _enable_chattr).
        find ${_dscUsr}/.tmp -mindepth 1 -mtime +0 -exec rm -rf {} \; &> /dev/null
        chown -h ${_USER}:${_usrGroup} ${_dscUsr}/.tmp &> /dev/null
        [ ! -L "${_dscUsr}/.tmp" ] && chmod 02755 ${_dscUsr}/.tmp &> /dev/null
        echo OK > ${_dscUsr}/.tmp/.ctrl.${_tRee}.${_xSrl}.pid
      fi
      _prune_psr_log_stash "${_dscUsr}"
      # ~/static is 02775 group `users` with no sticky bit, so any co-tenant on
      # the box can replace the `control` name. Strip a plant unconditionally:
      # gating this on a stamp INSIDE the link lets a target that already
      # carries a matching stamp skip the guard for the whole pass.
      _desymlink_planted "${_dscUsr}/static/control"
      if [ ! -e "${_dscUsr}/static/control/.ctrl.${_tRee}.${_xSrl}.pid" ] \
        && [ -e "/home/${_USER}.ftp/clients" ]; then
        mkdir -p ${_dscUsr}/static/control
        [ ! -L "${_dscUsr}/static/control" ] \
          && chmod 755 ${_dscUsr}/static/control
        if [ -e "/var/xdrago/conf/control-readme.txt" ] \
          && [ -d "${_dscUsr}/static/control" ] \
          && [ ! -L "${_dscUsr}/static/control" ]; then
          _desymlink_planted "${_dscUsr}/static/control/README.txt"
          cp -af /var/xdrago/conf/control-readme.txt \
            ${_dscUsr}/static/control/README.txt &> /dev/null
          [ ! -L "${_dscUsr}/static/control/README.txt" ] \
            && chmod 0644 ${_dscUsr}/static/control/README.txt
        fi
        chown -R ${_USER}.ftp:${_usrGroup} ${_dscUsr}/static/control
        rm -f ${_dscUsr}/static/control/.ctrl.*
        echo OK > ${_dscUsr}/static/control/.ctrl.${_tRee}.${_xSrl}.pid
      fi
      if [ -e "${_dscUsr}/static/control/ssl-live-mode.info" ]; then
        if [ -e "${_dscUsr}/tools/le/.ctrl/ssl-demo-mode.pid" ]; then
          rm -f ${_dscUsr}/tools/le/.ctrl/ssl-demo-mode.pid
        fi
      fi

      # Blank the cnf-supplied values before the conditional source below:
      # when an account has no cnf (a half-finished migration is exactly that
      # state), the previous loop iteration's values would otherwise leak in
      # and this account's pools would be sized and switched from a foreign
      # account's config. The sibling night/10-account.sh blanks its trio for
      # the same reason.
      _PHP_FPM_VERSION=""
      _PHP_CLI_VERSION=""
      _PHP_FPM_WORKERS=""
      _PHP_FPM_TIMEOUT=""
      _PHP_FPM_MAX_CHILDREN_FORCE=""
      _PHP_FPM_MEMORY_LIMIT_FORCE=""
      _PHP_FPM_RAM_PCT=""
      _PHP_FPM_CPU_FACTOR=""
      _PHP_FPM_DENY=""
      _RESERVED_RAM=""
      _CLIENT_EMAIL=""
      _CLIENT_OPTION=""
      _CLIENT_SUBSCR=""
      _CLIENT_CORES=""
      _STRONG_PASSWORDS=""
      _PHP_FPM_USS_MB=""
      _CHILD_MAX_FPM=""
      _LTD_PLATFORM_CLIENTS=""
      if [ ! -e "/root/.${_USER}.octopus.cnf" ]; then
        echo "ALRT: no /root/.${_USER}.octopus.cnf for /data/disk/${_USER}"
      fi
      # shellcheck disable=SC1091
      [ -e "/root/.${_USER}.octopus.cnf" ] && source /root/.${_USER}.octopus.cnf

      _THIS_HM_PLR=$(cat ${_dscUsr}/.drush/hostmaster.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_PLR}/modules/path_alias_cache" ] \
        && [ -x "/opt/tools/drush/8/drush/drush.php" ]; then
        if [ -x "/opt/php56/bin/php" ]; then
        _desymlink_planted "${_dscUsr}/static/control/cli.info"
        echo 5.6 > ${_dscUsr}/static/control/cli.info
        fi
      fi
      _nrCheck=
      _switch_php
      ### reload nginx
      service nginx reload &> /dev/null
      if [ -z ${_nrCheck} ]; then
        if [ -z ${_PHP_SV} ]; then
          _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
          if [ -z "${_PHP_SV}" ]; then
            _PHP_SV=84
          fi
        fi
        if [ -f "${_dscUsr}/static/control/multi-fpm.info" ]; then
          _PHP_M_V="85 84 83 82 81 80 74 73 72 71 70 56"
          for m in ${_PHP_M_V}; do
            if [ -x "/opt/php${m}/bin/php" ] \
              && [ -e "/opt/php${m}/etc/pool.d/${_USER}.${m}.conf" ]; then
              _switch_newrelic ${m} ${_USER}.${m} 1
            fi
          done
        else
          if [ -x "/opt/php${_PHP_SV}/bin/php" ] \
            && [ -e "/opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf" ]; then
            _switch_newrelic ${_PHP_SV} ${_USER} 1
          fi
        fi
      fi
      _site_socket_inc_gen
      if [ -e "${_pthParentUsr}/clients" ] && [ ! -z ${_USER} ]; then
        echo Managing Users for ${_pthParentUsr} Instance
        rm -rf ${_pthParentUsr}/clients/admin &> /dev/null
        rm -rf ${_pthParentUsr}/clients/omega8ccgmailcom &> /dev/null
        rm -rf ${_pthParentUsr}/clients/nocomega8cc &> /dev/null
        rm -rf ${_pthParentUsr}/clients/*/backups &> /dev/null
        symlinks -dr ${_pthParentUsr}/clients &> /dev/null
        if [ -d "/home/${_USER}.ftp" ]; then
          _disable_chattr ${_USER}.ftp
          symlinks -dr /home/${_USER}.ftp &> /dev/null
          # Attached files mount = the SINGLE real mountpoint under /mnt (naming-agnostic).
          # Fail-closed: empty when NONE or when MORE THAN ONE is mounted -- multi-mount
          # is unsupported fleet-wide and cannot be disambiguated, so refuse to guess.
          _mntPoint=$(_pd=$(stat -c '%d' /mnt 2>/dev/null); _n=0; _hit=; for _m in /mnt/*; do
            [ -d "${_m}" ] || continue
            if mountpoint -q "${_m}" 2>/dev/null \
              || { [ -n "${_pd}" ] && [ "$(stat -c '%d' "${_m}" 2>/dev/null)" != "${_pd}" ]; }; then
              _hit="${_m}"; _n=$((_n + 1))
            fi
          done; [ "${_n}" -eq 1 ] && printf '%s' "${_hit}"; :) &&
          _MNT_STATIC_FILES="${_mntPoint}/files/${_USER}/static/files"
          [ -n "${_mntPoint}" ] && echo "_mntPoint is == ${_mntPoint} == at _manage_user"
          [ -n "${_mntPoint}" ] && echo "_MNT_STATIC_FILES is == ${_MNT_STATIC_FILES} == at _manage_user"
          echo >> ${_THIS_LTD_CONF}
          echo "[${_USER}.ftp]" >> ${_THIS_LTD_CONF}
          [ -n "${_mntPoint}" ] && echo "path : ['/opt/user/gems/${_USER}.ftp', \
                        '/opt/user/npm/${_USER}.ftp', \
                        '${_MNT_STATIC_FILES}', \
                        '${_dscUsr}/distro', \
                        '${_dscUsr}/static', \
                        '${_dscUsr}/backups', \
                        '${_dscUsr}/clients']" \
                        | fmt -su -w 2500 >> ${_THIS_LTD_CONF}
          [ -z "${_mntPoint}" ] && echo "path : ['/opt/user/gems/${_USER}.ftp', \
                        '/opt/user/npm/${_USER}.ftp', \
                        '${_dscUsr}/distro', \
                        '${_dscUsr}/static', \
                        '${_dscUsr}/backups', \
                        '${_dscUsr}/clients']" \
                        | fmt -su -w 2500 >> ${_THIS_LTD_CONF}
          _manage_site_drush_alias_mirror
          _manage_sec
          _manage_sec_platform
          if [ -d "/home/${_USER}.ftp/users" ]; then
            chown -R ${_USER}.ftp:${_usrGroup} /home/${_USER}.ftp/users
            [ ! -L "/home/${_USER}.ftp/users" ] \
              && chmod 700 /home/${_USER}.ftp/users
            find /home/${_USER}.ftp/users -maxdepth 1 -type f \
              -exec chmod 600 {} \; &> /dev/null
          fi
          if [ ! -L "/home/${_USER}.ftp/static" ]; then
            rm -f /home/${_USER}.ftp/{backups,clients,static}
            ln -sfn ${_dscUsr}/backups /home/${_USER}.ftp/backups
            ln -sfn ${_dscUsr}/clients /home/${_USER}.ftp/clients
            ln -sfn ${_dscUsr}/static  /home/${_USER}.ftp/static
          fi
          if [ ! -e "/home/${_USER}.ftp/.tmp/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
            [ ! -L "/home/${_USER}.ftp/.drush" ] \
              && rm -rf /home/${_USER}.ftp/.drush/cache
            rm -rf /home/${_USER}.ftp/.tmp
            mkdir -p /home/${_USER}.ftp/.tmp
            chown ${_USER}.ftp:${_usrGroup} /home/${_USER}.ftp/.tmp &> /dev/null
            chmod 700 /home/${_USER}.ftp/.tmp &> /dev/null
            echo OK > /home/${_USER}.ftp/.tmp/.ctrl.${_tRee}.${_xSrl}.pid
          fi
          _enable_chattr ${_USER}.ftp
          echo Done for ${_pthParentUsr}
        else
          echo Directory /home/${_USER}.ftp not available
        fi
        echo
      else
        echo Directory ${_pthParentUsr}/clients not available
      fi
      echo
    fi
  done
}

#
# Find correct IP.
_find_correct_ip() {
  if [ -e "/root/.found_correct_ipv4.cnf" ]; then
    _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>/dev/null | tr -d '\n')
  else
    _LOC_IP=$(curl ${_crlGet} https://api.ipify.org | sed 's/[^0-9\.]//g')
    if [ -z "${_LOC_IP}" ]; then
      _LOC_IP=$(curl ${_crlGet} http://ipv4.icanhazip.com | sed 's/[^0-9\.]//g')
    fi
    if [ ! -z "${_LOC_IP}" ]; then
      echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
    fi
  fi
}

#
# Restrict node if needed.
_fix_node_in_lshell_access() {
  if [ -e "/etc/lshell.conf" ]; then
    _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
    _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
    _PrTestUltra=$(grep "ULTRA" /root/.*.octopus.cnf 2>&1)
    _PrTestMonster=$(grep "MONSTER" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
      || [[ "${_PrTestUltra}" =~ "ULTRA" ]] \
      || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
      || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
      || [ -e "/root/.allow.node.lshell.cnf" ]; then
      _ALLOW_NODE=YES
    else
      _ALLOW_NODE=NO
      sed -i \
        -e "s/, 'node', 'npm', 'npx',/,/gi" \
        -e "s/, 'scp',/,/gi" \
        /etc/lshell.conf /var/xdrago/conf/lshell.conf
    fi
  fi
}

#
# Restrict php if needed.
_fix_php_in_lshell_access() {
  if [ -e "/etc/lshell.conf" ]; then
    _PrTestPhantom=$(grep "PHANTOM" /root/.*.octopus.cnf 2>&1)
    _PrTestCluster=$(grep "CLUSTER" /root/.*.octopus.cnf 2>&1)
    _PrTestUltra=$(grep "ULTRA" /root/.*.octopus.cnf 2>&1)
    _PrTestMonster=$(grep "MONSTER" /root/.*.octopus.cnf 2>&1)
    if [[ "${_PrTestPhantom}" =~ "PHANTOM" ]] \
      || [[ "${_PrTestUltra}" =~ "ULTRA" ]] \
      || [[ "${_PrTestMonster}" =~ "MONSTER" ]] \
      || [[ "${_PrTestCluster}" =~ "CLUSTER" ]] \
      || [ -e "/root/.allow.php.lshell.cnf" ]; then
      _ALLOW_PHP=YES
    else
      _ALLOW_PHP=NO
      sed -i \
        -e "s/, 'php.*':.*php',/,/gi" \
        -e "s/, '\/opt\/php.*',/,/gi" \
        /etc/lshell.conf /var/xdrago/conf/lshell.conf
    fi
  fi
}

###-------------SYSTEM-----------------###

if [ ! -e "/home/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
  chattr -i /home
  chmod 0711 /home
  chown root:root /home
  rm -f /home/.ctrl.*
  while IFS=':' read -r _login _pass _uid _gid _uname _homedir _shell; do
    if [[ "${_homedir}" = **/home/** ]]; then
      if [ -d "${_homedir}" ]; then
        chattr -i ${_homedir}
        chown ${_uid}:${_gid} ${_homedir} &> /dev/null
        if [ -d "${_homedir}/.ssh" ]; then
          chattr -i ${_homedir}/.ssh
          chown -R ${_uid}:${_gid} ${_homedir}/.ssh &> /dev/null
        fi
        if [ -d "${_homedir}/.tmp" ]; then
          chattr -i ${_homedir}/.tmp
          chown -R ${_uid}:${_gid} ${_homedir}/.tmp &> /dev/null
        fi
        if [ -d "${_homedir}/.drush" ]; then
          chattr +i ${_homedir}/.drush/usr
          chattr +i ${_homedir}/.drush/*.ini
          chattr +i ${_homedir}/.drush
        fi
        if [[ ! "${_login}" =~ ".ftp"($) ]] \
          && [[ ! "${_login}" =~ ".web"($) ]]; then
          chattr +i ${_homedir}
        fi
      fi
    fi
  done < /etc/passwd
  touch /home/.ctrl.${_tRee}.${_xSrl}.pid
fi

if [ ! -L "/usr/bin/MySecureShell" ] && [ -x "/usr/bin/mysecureshell" ]; then
  mv -f /usr/bin/MySecureShell /var/backups/legacy-MySecureShell-bin
  ln -sfn /usr/bin/mysecureshell /usr/bin/MySecureShell
fi

_NOW=$(date +%y%m%d-%H%M%S)
_NOW=${_NOW//[^0-9-]/}
[ -d "/var/backups/ltd/conf" ] || mkdir -p /var/backups/ltd/{conf,log,old}
[ -d "/var/backups/ltd/log" ] || mkdir -p /var/backups/ltd/{conf,log,old}
[ -d "/var/backups/ltd/old" ] || mkdir -p /var/backups/ltd/{conf,log,old}
[ -d "/var/backups/zombie/deleted" ] || mkdir -p /var/backups/zombie/deleted
_THIS_LTD_CONF="/var/backups/ltd/conf/lshell.conf.${_NOW}"
if [ -e "/run/manage_ruby_users.pid" ] \
  || [ -e "/run/manage_ltd_users.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/octopus_install_run.pid" ]; then
  touch /var/log/boa/wait-manage-ltd-users.pid
  echo "Another BOA task is running, we have to wait"
  sleep 3
  exit 0
elif [ ! -e "/var/xdrago/conf/lshell.conf" ]; then
  echo "Missing /var/xdrago/conf/lshell.conf template"
  exit 0
else
  rm -f /var/log/boa/wait-manage-ltd-users.pid
  # the pid, not a bare touch: the nightly's per-account pass waits only on a
  # LIVE worker (every other reader tests existence and removes the file)
  echo $$ > /run/manage_ltd_users.pid
  _prune_psr_log_stash "/var/aegir"
  _count_cpu
  _find_fast_mirror_early
  find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -f {} \; &> /dev/null
  # Unconditional, not once per release serial: this pass rebuilds
  # /etc/lshell.conf from the template, and the template is replaced with the
  # shipped one whenever the upgrade arm runs or the re-fetch trigger fires.
  # A serial-gated check left the shipped list in place after such a replace,
  # and the next pass then granted node, npm, npx and scp to every tenant.
  # The check is two substitutions and a plan read, and it is idempotent.
  _fix_node_in_lshell_access
  touch ${_pthLog}/node.manage.lshell.ctrl.${_tRee}.${_xSrl}.pid
#   if [ ! -e "${_pthLog}/php.manage.lshell.ctrl.${_tRee}.${_xSrl}.pid" ]; then
#     _fix_php_in_lshell_access
#     touch ${_pthLog}/php.manage.lshell.ctrl.${_tRee}.${_xSrl}.pid
#   fi
  cat /var/xdrago/conf/lshell.conf > ${_THIS_LTD_CONF}
  _find_correct_ip
  sed -i "s/1.1.1.1/${_LOC_IP}/g" ${_THIS_LTD_CONF}
  wait
  if [ ! -e "/root/.allow.mc.cnf" ]; then
    sed -i "s/'mc', //g" ${_THIS_LTD_CONF}
    wait
    sed -i "s/, 'mc':'mc -u'//g" ${_THIS_LTD_CONF}
    wait
  fi
  if [ ! -e "/etc/boa/.allow.du.cnf" ] \
    && ! grep -qiE "^[[:space:]]*(export[[:space:]]+)?_ALLOW_DU=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
    sed -i "s/'du', //g" ${_THIS_LTD_CONF}
    wait
    sed -i "s/, 'du':'du -s -h'//g" ${_THIS_LTD_CONF}
    wait
  fi
  _add_ltd_group_if_not_exists
  _add_allow_snail_if_not_exists
  _kill_zombies >/var/backups/ltd/log/zombies-${_NOW}.log 2>&1
  _manage_user >/var/backups/ltd/log/users-${_NOW}.log 2>&1
  if [ -e "${_THIS_LTD_CONF}" ]; then
    _dedup_ltd_conf_sections "${_THIS_LTD_CONF}"
    _DUP_SEC=$(_ltd_conf_dup_sections "${_THIS_LTD_CONF}")
    if [ ! -z "${_DUP_SEC}" ]; then
      # Fail closed. lshell refuses a config carrying a repeated section
      # outright, so installing this one would take the shell away from EVERY
      # account on the box; the config already in place is, at worst, stale by
      # one pass. Keep the rejected file for forensics and publish nothing.
      cp -af ${_THIS_LTD_CONF} /var/backups/ltd/old/lshell.conf-rejected-${_NOW}
      _ltd_notice "dup-publish" \
        "generated lshell config REJECTED, /etc/lshell.conf left as it was" \
        "still repeated after the collapse: $(echo ${_DUP_SEC} | tr '\n' ' ')-- kept at /var/backups/ltd/old/lshell.conf-rejected-${_NOW}"
    else
      _DIFF_T=$(diff -w -B ${_THIS_LTD_CONF} /etc/lshell.conf 2>&1)
      if [ ! -z "${_DIFF_T}" ]; then
        cp -af /etc/lshell.conf /var/backups/ltd/old/lshell.conf-before-${_NOW}
        cp -af ${_THIS_LTD_CONF} /etc/lshell.conf
      else
        rm -f ${_THIS_LTD_CONF}
      fi
    fi
  fi
  if [ -L "/bin/sh" ] && [ ! -e "/run/octopus_install_run.pid" ]; then
    _WEB_SH="$(readlink -n /bin/sh)"
    if [ -x "/opt/local/bin/websh" ] \
      && grep -i '_forward_to_dash' /opt/local/bin/websh &> /dev/null; then
      if [ "${_WEB_SH}" != "/opt/local/bin/websh" ]; then
        ln -sfn /opt/local/bin/websh /bin/sh
        if [ -e "/usr/bin/sh" ]; then
          ln -sfn /opt/local/bin/websh /usr/bin/sh
        fi
        [ -x "/bin/websh" ] && [ ! -L "/bin/websh" ] && ln -sfn /opt/local/bin/websh /bin/websh
      fi
    else
      if [ -x "/bin/dash" ]; then
        if [ "${_WEB_SH}" != "/bin/dash" ]; then
          ln -sfn /bin/dash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /bin/dash /usr/bin/sh
          fi
        fi
      elif [ -x "/usr/bin/dash" ]; then
        if [ "${_WEB_SH}" != "/usr/bin/dash" ]; then
          ln -sfn /usr/bin/dash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /usr/bin/dash /usr/bin/sh
          fi
        fi
      elif [ -x "/bin/bash" ]; then
        if [ "${_WEB_SH}" != "/bin/bash" ]; then
          ln -sfn /bin/bash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /bin/bash /usr/bin/sh
          fi
        fi
      elif [ -x "/usr/bin/bash" ]; then
        if [ "${_WEB_SH}" != "/usr/bin/bash" ]; then
          ln -sfn /usr/bin/bash /bin/sh
          if [ -e "/usr/bin/sh" ]; then
            ln -sfn /usr/bin/bash /usr/bin/sh
          fi
        fi
      fi
      curl -s -A iCab "${_urlHmr}/tools/bin/websh" -o /opt/local/bin/websh
      chmod 755 /opt/local/bin/websh
    fi
  fi
  rm -f ${_TMP}/*.txt
  if [ ! -e "/etc/boa/.home.no.wildcard.chmod.cnf" ] \
    && ! grep -qiE "^[[:space:]]*(export[[:space:]]+)?_HOME_NO_WILDCARD_CHMOD=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
    chmod 700 /home/* &> /dev/null
  fi
  # /var/log/lsh is written by the tenants themselves (group lshellg), so a
  # tenant can plant any not-yet-used name there. The sticky bit (healed here:
  # the dir predates it on old boxes) keeps one tenant from unlinking another's
  # log and, with fs.protected_regular=2, from feeding a victim a foreign
  # regular file. Root ignores the sticky bit, so only this pass can remove
  # what a tenant left at someone else's name: anything that is not a regular
  # *.log, and a *.log owned by a user other than the one its name claims (a
  # recycled uid makes a dead tenant's log readable by the wrong tenant). An
  # all-numeric owner is a dead uid: its log stays as history unless a live
  # tenant of that name now needs the file it cannot open (0600, foreign).
  # NUL-delimited records, owner first: a tenant-chosen name may carry a tab or
  # a newline, and a record that fails to parse must never reach the rm. rm
  # does not follow. The owner rule assumes lshell's default <user>.log naming
  # (the shipped conf keeps logfilename unset); an admin who sets it, with
  # either delimiter lshell's parser accepts and in any case, turns the rule
  # off rather than losing every log on the next pass.
  chmod 1770 /var/log/lsh &> /dev/null
  find /var/log/lsh -mindepth 1 -maxdepth 1 \( ! -type f -o ! -name '*.log' \) \
    -exec rm -rf {} + 2>/dev/null
  if ! grep -qiE '^[[:space:]]*logfilename[[:space:]]*[:=]' /etc/lshell.conf 2>/dev/null; then
    find /var/log/lsh -mindepth 1 -maxdepth 1 -type f -name '*.log' -printf '%u\0%f\0' 2>/dev/null \
      | while IFS= read -r -d '' _lshOwner && IFS= read -r -d '' _lshName; do
        [ -n "${_lshOwner}" ] && [ -n "${_lshName}" ] || continue
        case "${_lshOwner}" in
          *[!0-9]*) [ "${_lshName%.log}" = "${_lshOwner}" ] || rm -f "/var/log/lsh/${_lshName}" ;;
          *) id -u "${_lshName%.log}" &> /dev/null && rm -f "/var/log/lsh/${_lshName}" ;;
        esac
      done
  fi
  # -type f refuses a planted link; a tenant swapping its OWN name between the
  # lstat and the chmod is the house-wide check-then-act residual (chmod has no
  # -h), bounded by the sweep above. A young box has no log yet, hence no bare
  # glob (it printed "cannot access").
  find /var/log/lsh -maxdepth 1 -type f -exec chmod 0600 {} + 2>/dev/null
  chmod 0440 /var/aegir/.drush/*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/drushrc.php &> /dev/null
  chmod 0400 /var/aegir/.drush/hm.alias.drushrc.php &> /dev/null
  chmod 0400 /var/aegir/.drush/hostmaster*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/platform_*.php &> /dev/null
  chmod 0400 /var/aegir/.drush/server_*.php &> /dev/null
  chmod 0710 /var/aegir/.drush &> /dev/null
  find /var/aegir/config/server_master \
    -type d -exec chmod 0700 {} \; &> /dev/null
  find /var/aegir/config/server_master \
    -type f -exec chmod 0600 {} \; &> /dev/null
  sleep 5
  _drush_ini_open_basedir_sweep
  _standby_tenant_sweep
  [ -e "/run/manage_ltd_users.pid" ] && rm -f /run/manage_ltd_users.pid
  exit 0
fi

