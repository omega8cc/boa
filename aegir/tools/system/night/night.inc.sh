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
# Default only: every worker sources /root/.barracuda.cnf after this
# file (night_load_run_env), so the cnf value wins; the literal keeps
# the read well-defined and fail-closed if a worker is ever driven
# outside that chain.
_DEBUG_DAILY=NO

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

_ctrl_stage_dir() {
  # Root-only staging dir for control-INI writes, on the same filesystem as the
  # account's platform trees (they all live under the account root). The account
  # root itself is 0711 oN:users, so the tenant may traverse it but cannot create
  # or unlink here; the staging dir is forced root:root 0700 on every call, and a
  # symlink planted in its place is removed rather than followed. Prints the path
  # on success. Reads _usEr from the caller.
  local _s
  [ -n "${_usEr}" ] && [ -d "${_usEr}" ] || return 1
  _s="${_usEr}/.boa-ctrl"
  [ -L "${_s}" ] && rm -f "${_s}" &> /dev/null
  [ -d "${_s}" ] || mkdir -p "${_s}" 2>/dev/null || return 1
  [ -d "${_s}" ] && [ ! -L "${_s}" ] || return 1
  chown root:root "${_s}" &> /dev/null
  chmod 0700 "${_s}" &> /dev/null
  echo "${_s}"
}

_reseed_ctrl_ini() {
  # Seed/refresh a control INI from a regular template, symlink-proof and atomic.
  # The per-site/per-platform control INIs live in a tenant-writable setgid
  # modules dir (oN:users 02775, no sticky, group 'users' shared across all
  # tenants), so a limited-shell/SFTP tenant can delete the seeded INI and plant
  # a symlink at its path; a plain cp -af then writes THROUGH a live link and the
  # following chown/chmod retarget it.
  #
  # Stage the new file in a root-owned 0700 dir under the account root, then
  # mv -f -T it onto the destination. Everything the account owns lives under
  # that root, so the rename is same-filesystem and atomic; rename() replaces a
  # planted symlink (incl. a symlink-to-dir) instead of following it, and a
  # real-dir decoy makes mv fail into the clean skip. Staging outside the
  # platform tree matters: a freshly built platform can still be group-writable
  # all the way up to its sites/ dir, and only the chown/chmod land on the temp
  # -- so a tenant who could write the staging dir could swap the temp for a
  # symlink and have root chown their target. The account root is 0711, so they
  # can traverse but not create there. Refuses a symlink/non-regular SOURCE so a
  # tenant-symlinked template cannot disclose a root file. Reads _usEr and _HM_U
  # from the caller. $1 = source template, $2 = dest INI path.
  local _src="$1"
  local _dst="$2"
  local _stg _new
  [ -L "${_src}" ] && return 1
  [ -f "${_src}" ] || return 1
  [ -n "${_HM_U}" ] || return 1
  [ -d "${_dst%/*}" ] || return 1
  _stg=$(_ctrl_stage_dir) || return 1
  _new=$(mktemp "${_stg}/ctrl.XXXXXX" 2>/dev/null) || return 1
  if [ -L "${_new}" ] || [ ! -f "${_new}" ]; then
    rm -f "${_new}" &> /dev/null
    return 1
  fi
  if ! cat "${_src}" > "${_new}" 2>/dev/null; then
    rm -f "${_new}" &> /dev/null
    return 1
  fi
  chown "${_HM_U}:users" "${_new}" &> /dev/null
  chmod 0664 "${_new}" &> /dev/null
  mv -f -T "${_new}" "${_dst}" &> /dev/null || rm -f "${_new}" &> /dev/null
}

_desymlink_planted() {
  # Strip a tenant-planted symlink at a root-maintained control-INI path before
  # this iteration seeds/edits/appends it. rm -f on a symlink removes only the
  # link (its target survives), and it is a no-op on a regular file, so a legit
  # oN(.ftp):users file and the tenant's own edits are left untouched. The next
  # seed leg re-creates a missing INI as a regular file. Args = paths.
  local _p
  for _p in "$@"; do
    [ -L "${_p}" ] && rm -f "${_p}" &> /dev/null
  done
}

_sanitize_number() {
  echo "$1" | sed 's/[^0-9.]//g'
}

_check_file_with_wildcard_path() {
  # 2>/dev/null, NOT 2>&1: a glob that matches nothing is passed through
  # literally and ls then prints "cannot access ..." on stderr. Capturing that
  # made _WILDCARD_TEST non-empty for a path that does not exist, so this
  # answered YES for EVERY input and could never answer NO -- the auto-detect
  # callers then seeded auto_detect_*_integration = TRUE into every platform
  # control INI, module present or not. $1 stays unquoted: the glob is the point.
  _WILDCARD_TEST=$(ls $1 2>/dev/null)
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

# Return 0 only when control flag <name> is set to YES (case-insensitive) in the
# control file <file>, else 1. Greps rather than sources, so it is independent
# of load order and never clobbers caller scope; a missing file or unset/non-YES
# value reads as disabled. Gates the ghost/empty cleanup moves so they stay OFF
# until opted in per-system (/root/.barracuda.cnf) or per-account
# (/root/.<user>.octopus.cnf).
_cnf_flag_yes() {
  local _file="$1"
  local _name="$2"
  local _val
  [ -r "${_file}" ] || return 1
  _val=$(grep -E "^[[:space:]]*${_name}=" "${_file}" 2>/dev/null \
    | tail -n1 | cut -d= -f2- | tr -d "\"' " | tr '[:lower:]' '[:upper:]')
  [ "${_val}" = "YES" ]
}

# Master cleanup interlock. While any Ægir/Provision task is running
# (provision-verify/install/clone/migrate/backup/restore), the site and platform
# trees are in flux -- files/private momentarily absent or symlinks mid-repoint,
# aliases mid-rewrite, vhosts staged under a leading dot -- and that transient
# state would be mis-read as a ghost and reaped. Return 0 when a provision
# process is detected, so every cleanup mover can skip while one is in flight.
# Same signal BOA already uses in monitor/check/mysql.sh.
_provision_running() {
  # Genuine task EXECUTIONS only. BOA spawns them as
  #   su -s /bin/bash - <user> -c "<php> /usr/bin/drush @<site> provision-<task>"
  # (_run_drush8_cmd above), so a real task always carries the drush command
  # token somewhere in the tree, and the php/su process running it always has
  # provision on its command line. The bare substring match this replaces
  # reported "running" for any command line that merely MENTIONED a provision
  # path -- a checksum, an editor, an operator's ssh probe, a monitoring loop --
  # and then silently skipped that night's cleanups; observed live when a
  # watcher holding .drush/sys/provision/... in its argv read as a live task.
  # Same lesson, and the same fix, as the _fetch_versioned running-tool guard.
  # The second pattern is the old one plus an execution-shape constraint, so the
  # only processes this stops matching are the non-executions; the first keeps
  # the inner `bash -c "... provision-<task>"` link of the su chain covered.
  pgrep -f "provision-[a-z]" > /dev/null 2>&1 && return 0
  # The front-end dispatch phase of a task carries no provision-* token: the
  # backend child is spawned only after bootstrap, and the post-hooks run after
  # it exits, so those windows were invisible. ( |$) is LOAD-BEARING -- without
  # it this also matches hosting-tasks and hosting-dispatch, the per-minute
  # pollers, which would pin the gate ON and disable every nightly cleanup.
  pgrep -f "hosting-task( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^([^ ]*/)?(php[0-9.]*|su|env|drush[0-9]*)( |$).*provision" > /dev/null 2>&1 && return 0
  return 1
}

# Install/upgrade interlock for the night workers, distinct from the entry gate
# in owl.sh: that one is evaluated ONCE, before the per-account fan-out, so a
# pass that starts afterwards is invisible to it -- and the octopus pass drops
# boa_run.pid at the end of EVERY account (satellite _satellite_post_cleanup),
# so on a multi-account box the lock pids stop being a reliable signal partway
# through. The AegirSetup arm covers the phase that actually builds a new
# distro revision: those children run as "su - oN -c bash .../AegirSetupC.sh.txt"
# and match none of the wrapper or .sh.txt forms the other gates look for.
# Anchored on the executor so a remotely driven install cannot defer this box,
# and the [ABC] class keeps the pattern from matching its own pgrep.
_night_boa_pass_active() {
  [ -e "/run/boa_run.pid" ] && return 0
  [ -e "/run/boa_wait.pid" ] && return 0
  [ -e "/run/octopus_install_run.pid" ] && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/var/backups/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/(barracuda|octopus)( |$)" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-" > /dev/null 2>&1 && return 0
  pgrep -f "^(/[^ ]*/)?(bash|sh|su) .*/aegir/scripts/AegirSetup[ABC]\.sh\.txt" > /dev/null 2>&1 && return 0
  return 1
}

# Consecutive-ghost tracking so nothing is reaped on a single night's snapshot.
# A per-item counter file (caller picks the path, e.g. under <account>/log/ctrl)
# records how many consecutive runs the item has looked like a ghost. Returns 0
# only once that reaches _need (default 2), giving a transient state -- a
# verify/clone in flight, a momentarily-unmounted store, a symlink mid-repoint --
# at least one grace run to recover. The caller MUST call _ghost_seen_reset on
# any run where the item is found valid, so a recovered item never carries a
# stale count into a later reap.
_ghost_seen_enough() {
  local _marker="$1"
  local _need="${2:-2}"
  local _n=0
  [ -f "${_marker}" ] && _n=$(cat "${_marker}" 2>/dev/null)
  _n="${_n//[^0-9]/}"
  [ -n "${_n}" ] || _n=0
  _n=$(( _n + 1 ))
  mkdir -p "$(dirname "${_marker}")" 2>/dev/null
  echo "${_n}" > "${_marker}" 2>/dev/null
  [ "${_n}" -ge "${_need}" ]
}

_ghost_seen_reset() {
  rm -f "$1" 2>/dev/null
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
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
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
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} ${_HM_U} running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

# Whether the account's own Aegir front-end still has a record for a site
# name. A site's hosting_context row is registered with the domain on node
# insert and removed by hosting_context_delete when the node is deleted, so
# it distinguishes "the customer can still see and remove this in the panel"
# (YES) from "only backend leftovers remain" (NO). Echoes YES / NO / UNKNOWN
# (front-end unreachable or unparseable output) -- callers pick the
# fail-direction. Same @hostmaster/account-user shape as _run_drush8_hmr_cmd,
# but CAPTURES output; tail -n1 keeps the count row under any profile noise.
_hmr_context_exists() {
  local _name="$1"
  local _out
  _out=$(su -s /bin/bash - ${_HM_U} -c "drush8 @hostmaster sqlq \"SELECT COUNT(*) FROM hosting_context WHERE name='${_name}'\"" 2>/dev/null \
    | grep -o '[0-9][0-9]*' | tail -n 1)
  case "${_out}" in
    "") echo UNKNOWN ;;
    0)  echo NO ;;
    *)  echo YES ;;
  esac
}

_run_drush8_hmr_master_cmd() {
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
    _nOw=$(date +%y%m%d-%H%M%S)
    echo "${_nOw} aegir running drush8 @hostmaster $1"
  fi
  su -s /bin/bash - aegir -c "drush8 @hostmaster $1" &> /dev/null
  wait
}

_run_drush8_nosilent_cmd() {
  if [ "${_DEBUG_DAILY}" = "YES" ] \
    || [ -e "/root/.debug_daily.info" ]; then
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
      # static/ is tenant-writable (02775, no sticky), so goaccess can be a
      # planted symlink: -e dereferences it and mkdir -p succeeds silently on a
      # link to a directory, after which cp -af would drop a root-owned report
      # tree into a location of the tenant's choosing. Strip a planted link and
      # publish only into a real directory root itself owns.
      _desymlink_planted "/data/disk/${_HM_U}/static/goaccess"
      if [ ! -e "/data/disk/${_HM_U}/static/goaccess" ]; then
        mkdir -p /data/disk/${_HM_U}/static/goaccess
      fi
      if [ -e "/var/www/adminer/access/${_HM_U}/${1}/index.html" ] \
        && [ -d "/data/disk/${_HM_U}/static/goaccess" ] \
        && [ ! -L "/data/disk/${_HM_U}/static/goaccess" ] \
        && [ -O "/data/disk/${_HM_U}/static/goaccess" ]; then
        cp -af /var/www/adminer/access/${_HM_U}/${1} /data/disk/${_HM_U}/static/goaccess/
      else
        rm -rf /var/www/adminer/access/${_HM_U}/${1}
        rm -rf /data/disk/${_HM_U}/static/goaccess/${1}
      fi
    fi
  fi
}

###-------------NIGHT LOG + LE INCIDENT-----------------###

# Per-account night log path. The orchestrator (owl.sh) redirects each
# `10-account.sh <account>` run here -- serial AND parallel -- so every
# account's output lands in its own file; the worker reads the same path back
# to build its Let's Encrypt renewal incident report. Both sides derive it
# identically from _NOW (the frozen run keystone) + the account basename, so
# they always agree on the file name.
_acct_night_log() {
  echo "/var/log/boa/daily/acct-$(basename "$1")-${_NOW}.log"
}

# Extract failed Let's Encrypt renewals from a single account's night log.
# dehydrated prints a stable block on failure: a "Processing <domain> [with
# alternative names: ...]" header, then for the failing challenge an ACME
# result whose tab-separated lines include ["error","type"] and
# ["error","detail"]. We emit one record per failure with five fields joined by
# the US control byte (0x1f), NOT a tab: <site-context><US><cert-domain><US>
# <alt-names><US><short-type><US><detail>. The separator must be non-whitespace
# because the alt-names field is EMPTY for single-domain certs, and `read` with
# a whitespace IFS (tab) silently collapses an empty middle field, shifting every
# later field left. 0x1f cannot occur in a domain or ACME detail string.
# Keyed on the ["error","detail"] line (exactly one per failed cert), paired
# with the most recent type + Processing/Running context seen above it.
# Successful or "Skipping renew!" blocks carry no error detail line and are
# never emitted. Operates on ONE account's log, so every record provably
# belongs to that account -- this is what guarantees a client notice can never
# be cross-attributed to the wrong account.
_le_extract_failures() {
  [ -r "$1" ] || return 0
  awk '
    /^Running LE cert check directly for / {
      currun=$0; sub(/^Running LE cert check directly for /,"",currun)
    }
    /^Processing / {
      p=$0; sub(/^Processing /,"",p)
      i=index(p," with alternative names: ")
      if (i>0) { curdom=substr(p,1,i-1); curalt=substr(p,i+length(" with alternative names: ")) }
      else     { curdom=p; curalt="" }
    }
    /^\["error","type"\]/ {
      t=$0; sub(/^\["error","type"\][ \t]+/,"",t); gsub(/"/,"",t); curtype=t
    }
    /^\["error","detail"\]/ {
      d=$0; sub(/^\["error","detail"\][ \t]+/,"",d); sub(/^"/,"",d); sub(/"$/,"",d)
      gsub(/\\"/,"\"",d)
      st=curtype; sub(/^.*:/,"",st)
      printf "%s\037%s\037%s\037%s\037%s\n", currun, curdom, curalt, st, d
      curtype=""
    }
  ' "$1"
}

# Map an ACME error type + detail to a short, non-technical cause phrase, used
# in both the operator and the client mail. The detail string is the most
# reliable signal (the type is sometimes a generic "unauthorized" for several
# distinct causes), so match on it first, then fall back to the type.
_le_reason() {
  local _t="$1"
  local _d="$2"
  case "${_d}" in
    *"key authorization file"*)
      echo "another server is currently answering for this name (an old host, a parked page or a CDN), so verification fails" ;;
    *NXDOMAIN*|*"no valid A records"*|*"DNS problem"*)
      echo "the domain or one of its aliases has no working DNS record pointing to this server" ;;
    *"Timeout during connect"*|*"Connection refused"*|*"Fetching"*)
      echo "the name points to a server that cannot be reached from the Internet (DNS elsewhere or a firewall)" ;;
    *"Invalid response"*)
      echo "the name resolves to a different server (the verification request was answered elsewhere)" ;;
    *)
      case "${_t}" in
        dns)         echo "the domain or one of its aliases has no working DNS record pointing to this server" ;;
        rateLimited) echo "Let's Encrypt temporarily rate-limited new certificates; it will retry automatically" ;;
        *)           echo "the certificate could not be validated by Let's Encrypt" ;;
      esac ;;
  esac
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
    echo "export _O_CONTRIB_BACKDROP=\"${_O_CONTRIB_BACKDROP}\""
    echo "export _MODULES_FORCE=\"${_MODULES_FORCE}\""
    echo "export _MODULES_ON_SEVEN=\"${_MODULES_ON_SEVEN}\""
    echo "export _MODULES_ON_SIX=\"${_MODULES_ON_SIX}\""
    echo "export _MODULES_OFF_SEVEN=\"${_MODULES_OFF_SEVEN}\""
    echo "export _MODULES_OFF_SIX=\"${_MODULES_OFF_SIX}\""
    echo "export _MODULES_OFF_EIGHT_PLUS=\"${_MODULES_OFF_EIGHT_PLUS}\""
    echo "export _hostedSys=\"${_hostedSys}\""
    echo "export _APT_UPDATE=\"${_APT_UPDATE}\""
    echo "export _PERMISSIONS_FIX=\"${_PERMISSIONS_FIX}\""
    echo "export _MODULES_FIX=\"${_MODULES_FIX}\""
    echo "export _CLEAR_BOOST=\"${_CLEAR_BOOST}\""
    echo "export _ENABLE_GOACCESS=\"${_ENABLE_GOACCESS}\""
    echo "export _ADMIN_EMAIL=\"${_MY_EMAIL}\""
    echo "export _INCIDENT_REPORT=\"${_INCIDENT_REPORT}\""
    echo "export _LE_CLIENT_NOTIFY=\"${_LE_CLIENT_NOTIFY}\""
    echo "export _GHOST_CLIENT_NOTIFY=\"${_GHOST_CLIENT_NOTIFY}\""
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
