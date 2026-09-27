#!/bin/bash

###
### 20-sites.sh -- per-site (per-vhost) maintenance procedures for one Octopus
### account, plus the per-site loop driver _daily_process. Part of the owl.sh/night
### split; SOURCED by the per-account worker 10-account.sh, which drives the
### _daily_process loop for its account.
###
### Reads the per-run / per-account / per-site context (_NOW, _DOW, _O_CONTRIB*,
### _MODULES_*, the _usEr/_HM_U/_Dom/_Dir/_Plr loop vars, etc.) and the shared
### helpers in night.inc.sh (drush8 wrappers, chattr, load, pure helpers,
### _apt_clean_update, _if_gen_goaccess).
###
# shellcheck disable=SC1091
[ -r "/var/xdrago/night/night.inc.sh" ] && . /var/xdrago/night/night.inc.sh

### Same fNN skew as the fallbacks below: this file can land ahead of a
### night.inc.sh that has no _acct_group; an undefined function returns 127
### with empty output, and `chown user:` then resets the group to the user's
### login group instead of the derived one. Carry the library body as the
### fallback.
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

### night.inc.sh carries its own fNN serial and is fetched separately, so a box
### can briefly hold this file alongside an older library that predates the
### symlink guards. An undefined function returns 127 and, with no set -e here,
### execution simply continues -- which would let every _desymlink_planted call
### below silently no-op and reopen the vector it exists to close. Define a
### fallback only when the library did not supply one; the body mirrors
### night.inc.sh deliberately (see the master/satellite mirror rule). The
### seeding helpers need no such fallback: absent, _reseed_ctrl_ini simply does
### not seed, which degrades maintenance without writing anything unsafe.
if ! declare -F _desymlink_planted > /dev/null 2>&1; then
  _desymlink_planted() {
    local _p
    for _p in "$@"; do
      [ -L "${_p}" ] && rm -f "${_p}" &> /dev/null
    done
  }
fi

### Gate for the alias-derived per-site paths (_Dir, _Plr and their ghost-loop
### twins) before any root op walks them: never a symlink, and resolving
### under this account root -- or under the shared /data/all|/data/disk/all
### platform store a legacy instance may still host sites on, which the
### account anchor alone would silently drop from the whole nightly pass.
### An absent path passes, like _validate_ctrl_dir (the ghost legs need it).
_validate_loop_dir() {
  local _resolved _anchor
  [ -L "$1" ] && return 1
  [ -e "$1" ] || return 0
  [ -d "$1" ] || return 1
  _resolved=$(realpath -e -- "$1" 2>/dev/null) || return 1
  _anchor=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 1
  case "${_resolved}/" in
    "${_anchor}"/*|/data/all/*|/data/disk/all/*) return 0 ;;
  esac
  return 1
}

### _validate_ctrl_dir is used below as a "continue" gate, so an undefined
### function -- 127, i.e. false -- would skip EVERY site on a box whose
### library is briefly behind this file. Fail-open is not an option either
### (that reopens the vector), so carry the real body as the fallback; it
### needs nothing but realpath and _usEr. Mirrors night.inc.sh deliberately.
if ! declare -F _validate_ctrl_dir > /dev/null 2>&1; then
  _validate_ctrl_dir() {
    local _resolved _anchor
    [ -L "$1" ] && return 1
    [ -e "$1" ] || return 0
    [ -d "$1" ] || return 1
    _resolved=$(realpath -e -- "$1" 2>/dev/null) || return 1
    _anchor=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 1
    case "${_resolved}/" in
      "${_anchor}"/*)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }
fi

### The Grav/Textpattern root test and its heal ride the same skew: with an
### older library the test would read false everywhere (127) and every INI leg
### below would keep seeding foreign trees, while a missing heal would leave
### what earlier releases seeded. Carry both library bodies; they mirror
### night.inc.sh deliberately.
if ! declare -F _is_foreign_cms_root > /dev/null 2>&1; then
  _is_foreign_cms_root() {
    local _r="${1%/}"
    [ -n "${_r}" ] && [ -d "${_r}" ] && [ ! -L "${_r}" ] || return 1
    [ -f "${_r}/index.php" ] || return 1
    [ -e "${_r}/core" ] && return 1
    [ -e "${_r}/modules/system/system.module" ] && return 1
    [ -e "${_r}/includes/bootstrap.inc" ] && return 1
    if [ -f "${_r}/bin/grav" ] && [ -f "${_r}/system/defines.php" ]; then
      return 0
    fi
    if [ -f "${_r}/css.php" ] \
      && [ -f "${_r}/textpattern/index.php" ] \
      && [ -f "${_r}/textpattern/lib/constants.php" ] \
      && [ ! -e "${_r}/autoload.php" ]; then
      return 0
    fi
    return 1
  }
fi
if ! declare -F _heal_foreign_cms_ctrl_ini > /dev/null 2>&1; then
  _heal_foreign_cms_ctrl_ini() {
    local _md="$1" _n="$2" _rmd _rus
    [ -n "${_md}" ] || return 0
    [ -L "${_md}" ] && return 0
    [ -d "${_md}" ] || return 0
    _rmd=$(realpath -e -- "${_md}" 2>/dev/null) || return 0
    _rus=$(realpath -e -- "${_usEr}" 2>/dev/null) || return 0
    case "${_rmd}/" in
      "${_rus}"/*) : ;;
      *) return 0 ;;
    esac
    (
      cd -P -- "${_rmd}" 2>/dev/null || exit 0
      [ "$(pwd -P)" = "${_rmd}" ] || exit 0
      if [ -n "${_n}" ]; then
        for _f in "default.${_n}" "${_n}"; do
          if [ -L "./${_f}" ] || [ -f "./${_f}" ]; then
            rm -f -- "./${_f}" \
              && echo "Foreign-CMS control INI removed: ${_rmd}/${_f}"
          fi
        done
      fi
      cd -P .. 2>/dev/null || exit 0
      [ "$(pwd -P)" = "${_rmd%/*}" ] || exit 0
      rmdir -- "${_rmd##*/}" 2>/dev/null \
        && echo "Foreign-CMS empty dir removed: ${_rmd}"
    )
    return 0
  }
fi

### Same delivery hazard, opposite failure direction: every "_provision_running
### && return" below BAILS OUT when a Provision task is running, so a missing
### function -- 127, i.e. false -- reads as "nothing running" and the cleanup
### walks straight through a live task. Deliberately the BROAD substring form,
### not a copy of the anchored library body: this runs only on a box whose
### library is briefly behind, where over-matching merely skips a cleanup (the
### safe direction) and where mirroring a two-pattern regex would be the drift
### risk the anchored version exists to avoid. A stub claiming a task is always
### running would disable every nightly cleanup on such a box instead.
if ! declare -F _provision_running > /dev/null 2>&1; then
  _provision_running() {
    pgrep -f provision > /dev/null 2>&1
  }
fi

### An account owns its static/control, and oN owns the rest of its
### /data/disk/oN (log/, .drush/, config/, tools/, .tmp/, undo/), so any name
### there can be a link or a FIFO, and any directory on the way can itself be
### a link. Root reads and writes those names only through the helpers below.
### The first four are the helper.sh.inc bodies (the night family never
### sources that file), carried unless the library already supplies them.
if ! declare -F _acct_in_real_dir > /dev/null 2>&1; then
  # Run "$@" inside the real directory $1, never one reached through a link
  # an account planted on the way. Below /home and /data/disk (root's) every
  # name on the path must be a real directory; elsewhere the last name is
  # checked against its resolved parent. Once entered, ./name stays in that
  # directory whatever is swapped.
  _acct_in_real_dir() {
    local _d="${1}" _a="" _want
    shift
    case "${_d}" in
      /home/?*) _a=/home ;;
      /data/disk/?*) _a=/data/disk ;;
    esac
    if [ -n "${_a}" ]; then
      _want="$(cd -P -- "${_a}" 2> /dev/null && pwd -P)${_d#"${_a}"}"
    else
      _want="$(cd -P -- "${_d%/*}" 2> /dev/null && pwd -P)/${_d##*/}"
    fi
    ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_want}" ] && "$@" )
  }
fi
if ! declare -F _acct_read_here > /dev/null 2>&1; then
  # ./$1 in the current (pinned) directory: never through a link, never
  # blocked on a FIFO, at most 1 MiB. Empty for anything else.
  _acct_read_here() {
    timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
      bs=1048576 count=1 status=none 2> /dev/null
  }
fi
if ! declare -F _acct_read_in > /dev/null 2>&1; then
  # $2 in the real directory $1, read as _acct_read_here reads it.
  _acct_read_in() {
    _acct_in_real_dir "${1}" _acct_read_here "${2}"
  }
fi
if ! declare -F _acct_put_here > /dev/null 2>&1; then
  # ./$1 in the current (pinned) directory with the content $2 (0644): a
  # fresh file created exclusively, then renamed over the name, so a link or
  # a FIFO put at the name is replaced, never followed or opened, and a
  # reader never finds the name missing.
  _acct_put_here() {
    local _t="./.${1}.put.$$.${RANDOM}"
    rm -f -- "${_t}"
    ( umask 022
      printf '%s\n' "${2}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
      && mv -f -T -- "${_t}" "./${1}" && return 0
    rm -f -- "${_t}"
    return 1
  }
fi

### Run "$@" inside the directory $1 as it resolves now, entered for real: $1
### is never a link itself and resolves strictly below this account root, and
### the resolved path is checked again once entered, so a name on the way
### swapped for a link afterwards is no longer on the path. For the
### alias-derived platform and site trees, which the per-site gates already
### accept through a link on the way; the account's own log/, .drush/ and
### config/ go through _acct_in_real_dir. Reads _usEr.
_acct_in_resolved_dir() {
  _in_resolved_dir acct "$@"
}
### The same for a site dir, which may also sit on the shared /data/all or
### /data/disk/all store a legacy instance still hosts sites on (the stores
### _validate_loop_dir accepts).
_site_in_resolved_dir() {
  _in_resolved_dir site "$@"
}
_in_resolved_dir() {
  local _k="${1}" _d="${2%/}" _rd _rus
  shift 2
  [ -n "${_d}" ] && [ ! -L "${_d}" ] && [ -d "${_d}" ] || return 1
  _rd=$(realpath -e -- "${_d}" 2> /dev/null) || return 1
  _rus=$(realpath -e -- "${_usEr}" 2> /dev/null) || return 1
  case "${_rd}/" in
    "${_rus}"/?*) ;;
    /data/all/?*|/data/disk/all/?*) [ "${_k}" = "site" ] || return 1 ;;
    *) return 1 ;;
  esac
  ( cd -P -- "${_rd}" 2> /dev/null && [ "$(pwd -P)" = "${_rd}" ] && "$@" )
}

### ./$1 in the current (pinned) directory replaced by the exact bytes $2, only
### while ./$1 is a regular file below 1 MiB (so a bounded read saw all of
### it): a fresh file created exclusively with the owner, group and read/write
### bits of the file it replaces, then renamed over the name. Nothing is
### written through a link, a FIFO or a name swapped in meanwhile, and no
### chmod by name follows.
_acct_put_same_here() {
  local _t="./.${1}.put.$$.${RANDOM}" _st _typ _own _mod _sz
  _st=$(stat -c '%F|%u:%g|%a|%s' -- "./${1}" 2> /dev/null) || return 1
  IFS='|' read -r _typ _own _mod _sz <<< "${_st}"
  case "${_typ}" in
    "regular file"|"regular empty file") ;;
    *) return 1 ;;
  esac
  [ "${_sz}" -lt 1048576 ] || return 1
  rm -f -- "${_t}"
  if ( umask "$(printf '%03o' "$(( 0777 & ~8#${_mod} ))")"
    printf '%s' "${2}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
    && chown -h "${_own}" "${_t}" 2> /dev/null \
    && mv -f -T -- "${_t}" "./${1}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
### ./$1 of the current (pinned) directory as text: status 1, and nothing,
### unless it is a regular file; read as _acct_read_here reads it.
_acct_read_plain_here() {
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
  _acct_read_here "${1}"
}
### ./$1 edited by the sed arguments after it, as sed -i edited it (the same
### bytes: the trailing "x" keeps every newline through the substitutions),
### and put back as _acct_put_same_here puts it.
_acct_sed_same_here() {
  local _n="${1}" _c
  shift
  _c=$(_acct_read_plain_here "${_n}" && echo x) || return 1
  _c=$(printf '%s' "${_c%x}" | sed "$@"; echo x)
  _acct_put_same_here "${_n}" "${_c%x}"
}
### The lines $2 appended to ./$1 as ">>" appended them (one newline after
### the last), and put back as _acct_put_same_here puts it.
_acct_add_same_here() {
  local _c
  _c=$(_acct_read_plain_here "${1}" && echo x) || return 1
  _acct_put_same_here "${1}" "${_c%x}${2}"$'\n'
}

### The control INIs sit in tenant-writable setgid modules dirs, so an INI can
### be swapped for a link or a FIFO between any test and its use, and the dir
### itself for a link. Each is read and edited only inside its modules dir,
### entered for real (_acct_in_resolved_dir): a read is bounded and never
### follows a link or blocks on a FIFO; an edit is made in memory and lands
### as a fresh file with the INI's own owner and mode. $1 = the INI path.
_ctrl_ini_read() {
  _acct_in_resolved_dir "${1%/*}" _acct_read_plain_here "${1##*/}"
}
_ctrl_ini_sed() {
  local _f="${1}"
  shift
  _acct_in_resolved_dir "${_f%/*}" _acct_sed_same_here "${_f##*/}" "$@"
}
_ctrl_ini_add() {
  _acct_in_resolved_dir "${1%/*}" _acct_add_same_here "${1##*/}" "${2}"
}
### For the "add if missing" legs: the INI text is read once into
### _CTRL_INI_TXT, and the line $2 is added unless grep finds $1 there (ERE
### with $3 = -E). The text grows with each added line, so a later test sees
### it as it saw the appended file; the additions collect in _CTRL_INI_ADD
### for a single _ctrl_ini_add.
_ctrl_ini_want() {
  if ! grep -q ${3:+"${3}"} -- "${1}" <<< "${_CTRL_INI_TXT}" 2> /dev/null; then
    _CTRL_INI_TXT="${_CTRL_INI_TXT}"$'\n'"${2}"
    _CTRL_INI_ADD="${_CTRL_INI_ADD}${_CTRL_INI_ADD:+$'\n'}${2}"
  fi
}

### A root marker in the account's log/ctrl (made first if missing): a fresh
### empty file created exclusively inside the real directory and renamed over
### the name, so a link or a FIFO put at the name is replaced, never followed
### or opened, and nothing is created through a link at log/ or log/ctrl.
### $1 = marker name.
_log_ctrl_mark() {
  _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null
  _acct_in_real_dir "${_usEr}/log/ctrl" _acct_mark_here "${1}"
}
### ./$1 in the current (pinned) directory as a fresh empty file, put as
### _acct_put_here puts one.
_acct_mark_here() {
  local _t="./.${1}.mark.$$.${RANDOM}"
  rm -f -- "${_t}"
  dd if=/dev/null of="${_t}" conv=excl status=none 2> /dev/null \
    && mv -f -T -- "${_t}" "./${1}" && return 0
  rm -f -- "${_t}"
  return 1
}

### Move ./$1 of the current directory, entered for real by the caller, into
### this account's real undo/ as $2 (default: the same name); undo/ is made
### first if missing. undo/ is opened and checked to be the account's own
### real directory, and the rename goes through that open directory
### (/proc/self/fd), so neither end can land anywhere else whatever name on
### either path is swapped for a link meanwhile; -T never moves into a
### directory or through a link found at the new name. Reads _usEr.
_acct_undo_here() {
  local _u
  _u="$(cd -P /data/disk 2> /dev/null && pwd -P)${_usEr#/data/disk}/undo"
  _acct_in_real_dir "${_usEr}" mkdir -p ./undo 2> /dev/null
  exec 9< "${_u}/." || return 1
  [ "$(readlink /proc/self/fd/9)" = "${_u}" ] || return 1
  mv -f -T -- "./${1}" "/proc/self/fd/9/${2:-${1}}"
}
### Move the alias-derived platform or site tree $1 into undo/ as
### _acct_undo_here does, as $2 (default: its own name), from inside its real
### parent directory (_acct_in_resolved_dir).
_acct_undo_tree() {
  local _p="${1%/}"
  _acct_in_resolved_dir "${_p%/*}" _acct_undo_here "${_p##*/}" "${2:-${_p##*/}}"
}

# Default only: every worker sources /root/.barracuda.cnf after this file
# (night_load_run_env), so the cnf value wins; the literal keeps the read
# well-defined and fail-closed if a worker is ever driven outside that chain.
_ALLOW_CODEBASECHECK=NO
_SKIP_PERMISSIONS_PASS=NO

_check_if_required_with_drush8() {
  _REQ=YES
  _REI_TEST=$(_run_drush8_nosilent_cmd "pmi $1 --fields=required_by" 2>&1)
  _REL_TEST=$(echo "${_REI_TEST}" | grep "Required by" 2>&1)
  if [[ "${_REL_TEST}" =~ "was not found" ]]; then
    _REQ=NULL
    echo "_REQ for $1 is ${_REQ} in ${_Dom} == null == via ${_REL_TEST}"
  else
    echo "CTRL _REL_TEST _REQ for $1 is ${_REQ} in ${_Dom} == init == via ${_REL_TEST}"
    _REN_TEST=$(echo "${_REI_TEST}" | grep "Required by.*:.*none" 2>&1)
    if [[ "${_REN_TEST}" =~ "Required by" ]]; then
      _REQ=NO
      echo "_REQ for $1 is ${_REQ} in ${_Dom} == 0 == via ${_REN_TEST}"
    else
      echo "CTRL _REN_TEST _REQ for $1 is ${_REQ} in ${_Dom} == 1 == via ${_REN_TEST}"
      _REM_TEST=$(echo "${_REI_TEST}" | grep "Required by.*minimal" 2>&1)
      if [[ "${_REM_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 2 == via ${_REM_TEST}"
      fi
      _RES_TEST=$(echo "${_REI_TEST}" | grep "Required by.*standard" 2>&1)
      if [[ "${_RES_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 3 == via ${_RES_TEST}"
      fi
      _RET_TEST=$(echo "${_REI_TEST}" | grep "Required by.*testing" 2>&1)
      if [[ "${_RET_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 4 == via ${_RET_TEST}"
      fi
      _REH_TEST=$(echo "${_REI_TEST}" | grep "Required by.*hacked" 2>&1)
      if [[ "${_REH_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 5 == via ${_REH_TEST}"
      fi
      _RED_TEST=$(echo "${_REI_TEST}" | grep "Required by.*devel" 2>&1)
      if [[ "${_RED_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 6 == via ${_RED_TEST}"
      fi
      _REW_TEST=$(echo "${_REI_TEST}" | grep "Required by.*watchdog_live" 2>&1)
      if [[ "${_REW_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 7 == via ${_REW_TEST}"
      fi
    fi
    _Profile=$(_run_drush8_nosilent_cmd "${_vGet} ^install_profile$" \
      | grep "^install_profile:" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    _Profile=${_Profile//[^a-z_]/}
    echo "_Profile is == ${_Profile} =="
    if [ ! -z "${_Profile}" ]; then
      _REP_TEST=$(echo "${_REI_TEST}" | grep "Required by.*:.*${_Profile}" 2>&1)
      if [[ "${_REP_TEST}" =~ "Required by" ]]; then
        _REQ=NO
        echo "_REQ for $1 is ${_REQ} in ${_Dom} == 8 == via ${_REP_TEST}"
      else
        echo "CTRL _REP_TEST _REQ for $1 is ${_REQ} in ${_Dom} == 9 == via ${_REP_TEST}"
      fi
    fi
    _REA_TEST=$(echo "${_REI_TEST}" | grep "Required by.*apps" 2>&1)
    if [[ "${_REA_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${_Dom} == 10 == via ${_REA_TEST}"
    fi
    _REF_TEST=$(echo "${_REI_TEST}" | grep "Required by.*features" 2>&1)
    if [[ "${_REF_TEST}" =~ "Required by" ]]; then
      _REQ=YES
      echo "_REQ for $1 is ${_REQ} in ${_Dom} == 11 == via ${_REF_TEST}"
    fi
  fi
}

_check_if_skip() {
  for s in ${_MODULES_SKIP}; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ]; then
      _SKIP=YES
      #echo $1 is whitelisted and will not be disabled in ${_Dom}
    fi
  done
}

_check_if_force() {
  for s in ${_MODULES_FORCE}; do
    if [ ! -z "$1" ] && [ "$s" = "$1" ]; then
      _FORCE=YES
      echo $1 is blacklisted and will be forcefully disabled in ${_Dom}
    fi
  done
}

_d8plus_module_sentinel_table() {
  # Maps a banned module to the database table whose existence proves it
  # is installed on a D8+ site. D8+ has no disabled-but-installed state
  # (uninstall drops the schema), so table presence is an exact signal.
  # Echoes nothing for a module without a wired sentinel -- the caller
  # reports that loudly instead of silently skipping.
  case "$1" in
    linkchecker) echo "linkchecker_link" ;;
  esac
}

_check_modules_d8plus_policy() {
  # D8+ arm of the module policy: DETECT + ALERT ONLY. Ruling 2026-08-05:
  # a Drush8 full bootstrap against Drupal 8+ can corrupt the site's
  # internals (cached container/router state), so outside Aegir's own
  # controlled backend path nothing may bootstrap a D8+ site -- this
  # probe therefore never runs Drush at all: it reads the site database
  # directly (root mysql; db name parsed from the site drushrc exactly
  # like sqlclean does) and mails the operator on a hit. Remediation
  # stays with the operator via the site's own admin UI (Extend ->
  # Uninstall runs in web context and its uninstall page offers the
  # content-entity removal linkchecker needs) -- never via Drush8.
  # Honours the same _MODULES_SKIP valve as the D6/D7 helpers. Exact
  # table-name match: BOA provisions one unprefixed DB per site, so a
  # prefixed edge case is simply not detected rather than false-alerted.
  local _m _tbl _dbName _hit _hstN
  # The site drushrc is read inside the resolved site dir, bounded and never
  # through a link or a FIFO, and the name reaches root's SQL only when it is
  # a plain identifier, as mysql_backup.sh requires of every database it
  # touches.
  _dbName=$(_site_in_resolved_dir "${_Dir}" _acct_read_plain_here drushrc.php \
    | sed -n "s/^\$options\['db_name'\][[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" \
    2>/dev/null | head -n 1)
  if [ -z "${_dbName}" ]; then
    echo "D8PLUS-POLICY: no db_name in ${_Dir}/drushrc.php for ${_Dom} -- probe skipped"
    return
  fi
  if [[ ! "${_dbName}" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "D8PLUS-POLICY: db_name in ${_Dir}/drushrc.php for ${_Dom} is not a plain identifier -- probe skipped"
    return
  fi
  _hstN="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  for _m in $1; do
    _SKIP=NO
    if [ ! -z "${_MODULES_SKIP}" ]; then
      _check_if_skip "${_m}"
    fi
    if [ "${_SKIP}" = "YES" ]; then
      continue
    fi
    _tbl=$(_d8plus_module_sentinel_table "${_m}")
    if [ -z "${_tbl}" ]; then
      echo "D8PLUS-POLICY: no sentinel table wired for ${_m} -- cannot probe ${_Dom}"
      continue
    fi
    _hit=$(mysql -N -B -e "SELECT COUNT(*) FROM information_schema.tables \
      WHERE table_schema = '${_dbName}' AND table_name = '${_tbl}'" 2>/dev/null)
    if [ "${_hit}" = "1" ]; then
      echo "D8PLUS-POLICY: banned module ${_m} is installed on ${_Dom} (db ${_dbName})"
      {
        echo "The weekly module-policy check found the banned module '${_m}'"
        echo "installed on the Drupal 8+ site ${_Dom} (account ${_HM_U},"
        echo "database ${_dbName}) on ${_hstN}."
        echo ""
        echo "Why it is banned: ${_m} holds PHP-FPM workers on synchronous"
        echo "external requests inside web cron, which starves the account's"
        echo "shared FPM pool (self-inflicted denial of service)."
        echo ""
        echo "This check never modifies the site and will repeat every Tuesday"
        echo "until the module is removed. To remove it, use the site's own"
        echo "admin UI: Extend -> Uninstall -> ${_m} (for linkchecker the"
        echo "uninstall page offers the required 'Remove ... entities' step"
        echo "first). Do NOT use Drush8 against a Drupal 8+ site."
        echo ""
        echo "Reference: docs/MODULES.md in the BOA repository."
      } | s-nail -s "Banned module ${_m} on ${_Dom} (${_HM_U} on ${_hstN})" "${_ADMIN_EMAIL}"
    elif [ "${_hit}" != "0" ]; then
      echo "D8PLUS-POLICY: probe FAILED for ${_Dom} (db ${_dbName}, module ${_m}) -- mysql returned '${_hit}'"
    fi
  done
}

_disable_modules_with_drush8() {
  for m in $1; do
    _SKIP=NO
    _FORCE=NO
    if [ ! -z "${_MODULES_SKIP}" ]; then
      _check_if_skip "$m"
    fi
    if [ ! -z "${_MODULES_FORCE}" ]; then
      _check_if_force "$m"
    fi
    if [ "${_SKIP}" = "NO" ]; then
      _MODULE_T=$(_run_drush8_nosilent_cmd "pml --status=enabled \
        --type=module | grep \($m\)" 2>&1)
      if [[ "${_MODULE_T}" =~ "($m)" ]]; then
        if [ "${_FORCE}" = "NO" ]; then
          _check_if_required_with_drush8 "$m"
        else
          echo "$m dependencies not checked in ${_Dom} action forced"
          _REQ=FCE
        fi
        if [ "${_REQ}" = "FCE" ]; then
          _run_drush8_cmd "dis $m -y"
          echo "$m FCE disabled in ${_Dom}"
        elif [ "${_REQ}" = "NO" ]; then
          _run_drush8_cmd "dis $m -y"
          echo "$m disabled in ${_Dom}"
        elif [ "${_REQ}" = "NULL" ]; then
          echo "$m is not used in ${_Dom}"
        else
          echo "$m is required and can not be disabled in ${_Dom}"
        fi
      fi
    fi
  done
}

_enable_modules_with_drush8() {
  for m in $1; do
    _MODULE_T=$(_run_drush8_nosilent_cmd "pml --status=enabled \
      --type=module | grep \($m\)" 2>&1)
    if [[ "${_MODULE_T}" =~ "($m)" ]]; then
      _DO_NOTHING=YES
    else
      _run_drush8_cmd "en $m -y"
      echo "$m enabled in ${_Dom}"
    fi
  done
}

_sync_user_register_protection_ini_vars() {
  local _iniTxt
  _IGNORE_USER_REGISTER_PROTECTION=NO
  _ENABLE_STRICT_USER_REGISTER_PROTECTION=NO
  ### Both INI names live in tenant-writable setgid modules dirs, and either
  ### can be swapped for a link or a FIFO after any test. Each is read once,
  ### bounded and never through a link (_ctrl_ini_read), and edited only in
  ### memory, landing as a fresh file with its own owner and mode
  ### (_ctrl_ini_sed). The strip lets the seed leg recreate a planted name.
  _desymlink_planted "${_PLR_CTRL_F}" "${_DIR_CTRL_F}"
  if [ -e "/data/conf/default.boa_platform_control.ini" ] \
    && [ ! -e "${_PLR_CTRL_F}" ]; then
    _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
  fi
  if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
    _EN_URP_T_S=$(grep "^enable_strict_user_register_protection = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    _EN_URP_T=$(grep "^enable_user_register_protection = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_EN_URP_T_S}" =~ "enable_strict_user_register_protection = TRUE" ]] \
      || [[ "${_EN_URP_T}" =~ "enable_user_register_protection = TRUE" ]]; then
      _ENABLE_STRICT_USER_REGISTER_PROTECTION=YES
    fi
    _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    _DIS_URP_T_I=$(grep "^ignore_user_register_protection = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]] \
      || [[ "${_DIS_URP_T_I}" =~ "ignore_user_register_protection = TRUE" ]]; then
      _IGNORE_USER_REGISTER_PROTECTION=YES
    fi
  fi
  ### The old names renamed to the new ones inside the real static/control
  ### (the tenant's): mv -T never moves a file into a directory or through a
  ### link put at either name.
  ( _ctl="$(cd -P /data/disk 2> /dev/null && pwd -P)${_usEr#/data/disk}/static/control"
    cd -P -- "${_usEr}/static/control" 2> /dev/null && [ "$(pwd -P)" = "${_ctl}" ] || exit 0
    if [ -f ./enable_user_register_protection.info ] \
      && [ ! -L ./enable_user_register_protection.info ]; then
      mv -f -T ./enable_user_register_protection.info \
        ./enable_strict_user_register_protection.info
    fi
    if [ -f ./disable_user_register_protection.info ] \
      && [ ! -L ./disable_user_register_protection.info ]; then
      mv -f -T ./disable_user_register_protection.info \
        ./ignore_user_register_protection.info
    fi )
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ -e "${_usEr}/static/control/enable_strict_user_register_protection.info" ]; then
    _desymlink_planted "${_PLR_CTRL_F}"
    _ctrl_ini_sed "${_PLR_CTRL_F}" \
      "s/.*enable.*user_register_protection.*/enable_strict_user_register_protection = TRUE/g" \
      &> /dev/null
    _ENABLE_STRICT_USER_REGISTER_PROTECTION=YES
  fi
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ] \
    && [ -e "${_usEr}/static/control/ignore_user_register_protection.info" ]; then
    _desymlink_planted "${_PLR_CTRL_F}"
    _ctrl_ini_sed "${_PLR_CTRL_F}" \
      "s/.*enable.*user_register_protection.*/enable_strict_user_register_protection = FALSE/g" \
      &> /dev/null
    _IGNORE_USER_REGISTER_PROTECTION=YES
  fi
  if [ -e "/data/conf/default.boa_site_control.ini" ] \
    && [ ! -e "${_DIR_CTRL_F}" ]; then
    _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
  fi
  if _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
    _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    _DIS_URP_T_I=$(grep "^ignore_user_register_protection = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]] \
      || [[ "${_DIS_URP_T_I}" =~ "ignore_user_register_protection = TRUE" ]]; then
      _IGNORE_USER_REGISTER_PROTECTION=YES
    fi
  fi
  if [ -e "${_usEr}/static/control/ignore_user_register_protection.info" ]; then
    _IGNORE_USER_REGISTER_PROTECTION=YES
  fi
}

_fix_user_register_protection_with_vSet() {
  _sync_user_register_protection_ini_vars
  if [ "${_IGNORE_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ ! -e "${_Plr}/core" ]; then
    # Keep only the variable's own line before the field split: the stream can
    # carry other text (a wrapper diagnostic, a shell notice), and the filters
    # below would fold it into the value instead of rejecting it.
    _Prm=$(_run_drush8_nosilent_cmd "${_vGet} ^user_register$" \
      | grep "^user_register:" \
      | cut -d: -f2 \
      | awk '{ print $1}' \
      | sed "s/['\"]//g" \
      | tr -d "\n" 2>&1)
    _Prm=${_Prm//[^0-2]/}
    echo "_Prm user_register for ${_Dom} is ${_Prm}"
    if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ]; then
      _run_drush8_cmd "${_vSet} user_register 0"
      echo "_Prm user_register for ${_Dom} set to 0"
    else
      if [ "${_Prm}" = "1" ] || [ -z "${_Prm}" ]; then
        _run_drush8_cmd "${_vSet} user_register 2"
        echo "_Prm user_register for ${_Dom} set to 2"
      fi
      _run_drush8_cmd "${_vSet} user_email_verification 1"
      echo "_Prm user_email_verification for ${_Dom} set to 1"
    fi
  fi
}

### The site's files store as it resolves now, in _R_FLS (status 0): files/ is
### legitimately a link into a static store (the account's own, its copy on
### attached storage, or another account's on an intentional share), and the
### tenant can repoint it. Only a static store or a real child of the site
### dir counts, the rule the permissions pass applies; status 1 otherwise.
_site_files_store() {
  local _rD _rF
  _R_FLS=
  _rD=$(realpath -e -- "${_Dir}" 2> /dev/null) || return 1
  _rF=$(realpath -e -- "${_Dir}/files" 2> /dev/null) || return 1
  [ -d "${_rF}" ] || return 1
  case "${_rF}/" in
    */static/files/*|"${_rD}"/*) _R_FLS="${_rF}"; return 0 ;;
  esac
  return 1
}
### Run "$@" inside the directory $1, a path resolved just before: entered
### with cd -P and checked there, so ./name stays in it whatever is swapped.
_in_pinned_dir() {
  local _d="${1}"
  shift
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_d}" ] && "$@" )
}
### ./$1 removed unless it is a link; a link at the name is left alone.
_rm_nolink_here() {
  [ -L "./${1}" ] || rm -f -- "./${1}"
}
### ./$1 handed to $2 (-h, never through a link) and, while it is still a
### regular file, given the mode $3.
_own_nolink_here() {
  chown -h "${2}" "./${1}" &> /dev/null
  [ -f "./${1}" ] && [ ! -L "./${1}" ] && chmod "${3}" "./${1}" &> /dev/null
  return 0
}

_fix_llms_txt() {
  # The site files/ dir is tenant-writable (oN:www-data 02775; the shell user is
  # in www-data), so a tenant can plant files/llms.txt as a symlink, and
  # files/ itself is a link the tenant can repoint. curl -o follows a link and
  # creates the target of a dangling one, and the chown/chmod below would then
  # retarget it -- a root write to a tenant-chosen path. So every leg acts only
  # inside the store as it resolves once here (_site_files_store), entered for
  # real, on ./llms.txt: strip any planted link first, fetch into a temp in the
  # root-only staging dir under the account root (_ctrl_stage_dir), then
  # mv -f -T over the leaf so rename() replaces a re-planted link instead of
  # following it; the content is read bounded and never through a link, and
  # the trailing metadata legs are gated with [ ! -L ].
  local _fls
  if ! _site_files_store; then
    [ -e "${_Dir}/files" ] \
      && echo "SKIP: ${_Dir}/files resolves outside any static store (llms.txt)"
    return 0
  fi
  _fls="${_R_FLS}"
  _in_pinned_dir "${_fls}" _desymlink_planted ./llms.txt
  # A tenant-uploaded policy is durable content, served as-is for as long as
  # the tenant keeps it -- the docs promise exactly that. Only a copy this
  # refresher itself fetched may be expired, re-fetched or content-gated;
  # provenance is the md5 of the fetched copy, recorded in a marker the tenant
  # cannot reach (the site dir is not group-writable). No marker, or an md5
  # mismatch (the tenant replaced or edited the copy): hands off beyond
  # ownership/mode normalisation. The markers are read, put and removed only
  # inside the resolved site dir (_site_in_resolved_dir).
  _LLMS_MARK="${_Dir}/.llms-fetched.md5"
  _LLMS_SUM=
  if _in_pinned_dir "${_fls}" test -f ./llms.txt -a ! -L ./llms.txt; then
    _LLMS_SUM=$(_in_pinned_dir "${_fls}" _acct_read_plain_here llms.txt \
      | md5sum 2>/dev/null | cut -d' ' -f1)
    # One-time transition for the copies this refresher fetched before the
    # marker existed: they carry none, so they read as tenant content and
    # were never refreshed again anywhere. A marker-less copy is seeded once
    # when the site serves the same bytes now, or when it predates the
    # marker (the pre-marker refresher expired every copy after six days,
    # so a tenant upload that old cannot exist). One check per site,
    # whatever its outcome; a tenant upload since then stays durable.
    _LLMS_SEEDCHK="${_Dir}/.llms-seed.checked"
    if [ ! -f "${_LLMS_MARK}" ] && [ ! -e "${_LLMS_SEEDCHK}" ] \
      && [ ! -e "${_Plr}/profiles/hostmaster" ] && [ -n "${_LLMS_SUM}" ]; then
      _LLMS_SEED=NO
      if [ -n "$(_in_pinned_dir "${_fls}" find ./llms.txt -maxdepth 0 \
        ! -newermt '2026-09-01' 2>/dev/null)" ]; then
        _LLMS_SEED=YES
      else
        _LLMS_STG=$(_ctrl_stage_dir) || _LLMS_STG=
        _LLMS_TMP=
        [ -n "${_LLMS_STG}" ] \
          && _LLMS_TMP=$(mktemp "${_LLMS_STG}/llms.XXXXXX" 2>/dev/null)
        if [ -n "${_LLMS_TMP}" ]; then
          curl -L --max-redirs 10 -k -s --connect-timeout 10 --max-time 20 \
            --retry 2 --retry-delay 5 --retry-max-time 30 \
            -A iCab "http://${_Dom}/llms.txt?nocache=1&noredis=1" \
            -o "${_LLMS_TMP}"
          echo >> "${_LLMS_TMP}"
          [ "$(md5sum "${_LLMS_TMP}" 2>/dev/null | cut -d' ' -f1)" = "${_LLMS_SUM}" ] \
            && _LLMS_SEED=YES
          rm -f "${_LLMS_TMP}"
        fi
      fi
      if [ "${_LLMS_SEED}" = "YES" ]; then
        _site_in_resolved_dir "${_Dir}" \
          _acct_put_here .llms-fetched.md5 "${_LLMS_SUM}"
      fi
      _site_in_resolved_dir "${_Dir}" _acct_mark_here .llms-seed.checked
    fi
    if [ ! -f "${_LLMS_MARK}" ] \
      || [ -z "${_LLMS_SUM}" ] \
      || ! _site_in_resolved_dir "${_Dir}" _acct_read_plain_here .llms-fetched.md5 \
        | grep -q "^${_LLMS_SUM}$" 2>/dev/null; then
      _site_in_resolved_dir "${_Dir}" rm -f -- ./.llms-fetched.md5
      # The test above is a read and a grep away, and files/ is
      # tenant-writable: -h so a link replanted in that window is never
      # followed, and re-test right before the chmod, which has no -h.
      _in_pinned_dir "${_fls}" _own_nolink_here llms.txt "${_HM_U}:www-data" 0664
      if [ -f "${_Plr}/llms.txt" ] || [ -L "${_Plr}/llms.txt" ]; then
        rm -f ${_Plr}/llms.txt
      fi
      return 0
    fi
    _in_pinned_dir "${_fls}" find ./llms.txt -maxdepth 0 -mtime +6 \
      -exec rm -f {} \; &> /dev/null
  fi
  if ! _in_pinned_dir "${_fls}" test -e ./llms.txt \
    && [ ! -e "${_Plr}/profiles/hostmaster" ]; then
    # curl -o re-opens the temp BY NAME after the fetch, so a temp in the site
    # dir can be swapped for a symlink during the bounded retry window whenever
    # _fix_static_permissions has that dir at 0775. Stage in the root-only 0700
    # dir under the account root instead. NB the mv below is an atomic rename
    # only while the store shares the account's filesystem: files/ may be a
    # symlink onto attached storage, or into another account on an intentional
    # share, and mv then degrades to copy+unlink (correct, not atomic).
    _LLMS_STG=$(_ctrl_stage_dir) || _LLMS_STG=
    _LLMS_TMP=
    [ -n "${_LLMS_STG}" ] \
      && _LLMS_TMP=$(mktemp "${_LLMS_STG}/llms.XXXXXX" 2>/dev/null)
    if [ -n "${_LLMS_TMP}" ]; then
      # The site answering here may be one of our own 503 stubs (suspended,
      # off-line, mid-migration), which send Retry-After: 3600, and curl sleeps
      # that between retries; --max-time bounds a single transfer only, so
      # --retry-max-time is what keeps one such site from parking this account's
      # whole nightly -- and with it the drift probe that runs after this loop.
      curl -L --max-redirs 10 -k -s --connect-timeout 10 --max-time 20 \
        --retry 2 --retry-delay 5 --retry-max-time 30 \
        -A iCab "http://${_Dom}/llms.txt?nocache=1&noredis=1" \
        -o "${_LLMS_TMP}"
      echo >> "${_LLMS_TMP}"
      _in_pinned_dir "${_fls}" mv -f -T -- "${_LLMS_TMP}" ./llms.txt &> /dev/null \
        || rm -f "${_LLMS_TMP}"
    fi
  fi
  _VAR_IF_PRESENT=$(_in_pinned_dir "${_fls}" _acct_read_plain_here llms.txt \
    | grep "##" 2>&1)
  if [[ ! "${_VAR_IF_PRESENT}" =~ "##" ]]; then
    _in_pinned_dir "${_fls}" _rm_nolink_here llms.txt
    _site_in_resolved_dir "${_Dir}" rm -f -- ./.llms-fetched.md5
  else
    if _in_pinned_dir "${_fls}" test ! -L ./llms.txt; then
      _in_pinned_dir "${_fls}" _own_nolink_here llms.txt "${_HM_U}:www-data" 0664
      # The site dir is not group-writable in the steady state, but
      # _fix_static_permissions walks every dir of a ~/static platform through
      # a 0775 window each night, so the marker IS plantable: it is put as a
      # fresh file inside the resolved site dir, never through a link there.
      _LLMS_SUM=$(_in_pinned_dir "${_fls}" _acct_read_plain_here llms.txt \
        | md5sum 2>/dev/null | cut -d' ' -f1)
      _site_in_resolved_dir "${_Dir}" \
        _acct_put_here .llms-fetched.md5 "${_LLMS_SUM}"
    fi
    if [ -f "${_Plr}/llms.txt" ] || [ -L "${_Plr}/llms.txt" ]; then
      rm -f ${_Plr}/llms.txt
    fi
  fi
}

_fix_robots_txt() {
  # See _fix_llms_txt: files/ is tenant-writable and a link the tenant can
  # repoint, so every leg acts only inside the store as it resolves once here
  # (_site_files_store), entered for real, on ./robots.txt -- strip the leaf,
  # fetch into a temp in the root-only staging dir under the account root,
  # mv -f -T over the leaf, read it bounded and never through a link, and gate
  # the metadata legs with [ ! -L ].
  local _fls
  if ! _site_files_store; then
    [ -e "${_Dir}/files" ] \
      && echo "SKIP: ${_Dir}/files resolves outside any static store (robots.txt)"
    return 0
  fi
  _fls="${_R_FLS}"
  _in_pinned_dir "${_fls}" _desymlink_planted ./robots.txt
  _in_pinned_dir "${_fls}" find ./robots.txt -maxdepth 0 -mtime +6 \
    -exec rm -f {} \; &> /dev/null
  if ! _in_pinned_dir "${_fls}" test -e ./robots.txt \
    && [ ! -e "${_Plr}/profiles/hostmaster" ]; then
    # curl -o re-opens the temp BY NAME after the fetch, so stage it in the
    # root-only 0700 dir under the account root instead of the site dir, and
    # skip the fetch when that dir cannot be had. The mv below is an atomic
    # rename only while files/ shares the account's filesystem.
    _ROBOTS_STG=$(_ctrl_stage_dir) || _ROBOTS_STG=
    _ROBOTS_TMP=
    [ -n "${_ROBOTS_STG}" ] \
      && _ROBOTS_TMP=$(mktemp "${_ROBOTS_STG}/robots.XXXXXX" 2>/dev/null)
    if [ -n "${_ROBOTS_TMP}" ]; then
      # See _fix_llms_txt: our own 503 stubs send Retry-After: 3600 and curl
      # sleeps that between retries, so the retry sleep needs --retry-max-time;
      # --max-time bounds one transfer only.
      curl -L --max-redirs 10 -k -s --connect-timeout 10 --max-time 20 \
        --retry 2 --retry-delay 5 --retry-max-time 30 \
        -A iCab "http://${_Dom}/robots.txt?nocache=1&noredis=1" \
        -o "${_ROBOTS_TMP}"
      echo >> "${_ROBOTS_TMP}"
      _in_pinned_dir "${_fls}" mv -f -T -- "${_ROBOTS_TMP}" ./robots.txt &> /dev/null \
        || rm -f "${_ROBOTS_TMP}"
    fi
  fi
  _VAR_IF_PRESENT=$(_in_pinned_dir "${_fls}" _acct_read_plain_here robots.txt \
    | grep "Disallow:" 2>&1)
  if [[ ! "${_VAR_IF_PRESENT}" =~ "Disallow:" ]]; then
    _in_pinned_dir "${_fls}" _rm_nolink_here robots.txt
  else
    # -h: files/ is tenant-writable, so the leaf can be replanted between the
    # read above and this call; the link must never be dereferenced.
    _in_pinned_dir "${_fls}" _own_nolink_here robots.txt "${_HM_U}:www-data" 0664
    if [ -f "${_Plr}/robots.txt" ] || [ -L "${_Plr}/robots.txt" ]; then
      rm -f ${_Plr}/robots.txt
    fi
  fi
}

_fix_boost_cache() {
  # ${_Plr} is the docroot, 02775 and group-writable (by the account's shell
  # identities; by ANY tenant while the instance still carries the box-wide
  # 'users' group), so cache is a name a tenant can plant as a symlink, and
  # rm -rf, chown and chmod all
  # walk through it. The boost cache is created and maintained here, so it is
  # never legitimately a link: strip a planted one, then act on a real dir only.
  _desymlink_planted "${_Plr}/cache"
  if [ -e "${_Plr}/cache" ] && [ ! -L "${_Plr}/cache" ]; then
    rm -rf ${_Plr}/cache/*
    rm -f ${_Plr}/cache/{.boost,.htaccess}
  else
    if [ -e "${_Plr}/sites/all/drush/drushrc.php" ]; then
      mkdir -p ${_Plr}/cache
    fi
  fi
  if [ -e "${_Plr}/cache" ] && [ ! -L "${_Plr}/cache" ]; then
    chown -h ${_HM_U}:www-data ${_Plr}/cache &> /dev/null
    chmod 02775 ${_Plr}/cache &> /dev/null
  fi
}

_fix_o_contrib_symlink() {
  if [ "${_O_CONTRIB_SEVEN}" != "NO" ]; then
    symlinks -d ${_Plr}/modules &> /dev/null
    if [ -e "${_Plr}/core/misc/backdrop.js" ]; then
      # Backdrop platform: attach the shared Backdrop bundle. Wrong-core Drupal
      # bundles are purged first (the Drupal module sets are not
      # Backdrop-compatible). Placed before the D8 arm, which its core/
      # (+ absent olivero/stable9/workspaces_ui) would otherwise match and
      # wire o_contrib_eight into a Backdrop tree.
      if [ -e "${_Plr}/modules/o_contrib_eight" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eight
        rm -f ${_Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_nine" ] \
        || [ -e "${_Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_nine
        rm -f ${_Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_ten" ] \
        || [ -e "${_Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_ten
        rm -f ${_Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_eleven" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eleven_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eleven
        rm -f ${_Plr}/modules/.o_contrib_eleven_dont_use
      fi
      # Attach only when the platform has no modules/redis copy: two copies of
      # the module in one scan dir make the winner readdir-order dependent.
      # The verify task owns demoting a baked copy (BOA-built platforms only);
      # after that demotion this repair arm takes over.
      if [ ! -e "${_Plr}/modules/o_contrib_backdrop" ] \
        && [ ! -e "${_Plr}/modules/redis" ] \
        && [ ! -z "${_O_CONTRIB_BACKDROP}" ] \
        && [ "${_O_CONTRIB_BACKDROP}" != "NO" ] \
        && [ -e "${_O_CONTRIB_BACKDROP}" ]; then
        ln -sfn ${_O_CONTRIB_BACKDROP} ${_Plr}/modules/o_contrib_backdrop &> /dev/null
      fi
    elif [ -e "${_Plr}/web.config" ] \
      && [ -e "${_O_CONTRIB_SEVEN}" ] \
      && [ ! -e "${_Plr}/core" ]; then
      if [ ! -e "${_Plr}/modules/o_contrib_seven" ]; then
        ln -sfn ${_O_CONTRIB_SEVEN} ${_Plr}/modules/o_contrib_seven &> /dev/null
      fi
    elif [ -e "${_Plr}/core" ] \
      && [ ! -e "${_Plr}/core/themes/olivero" ] \
      && [ ! -e "${_Plr}/core/themes/stable9" ] \
      && [ ! -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_EIGHT}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_nine" ] \
        || [ -e "${_Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_nine
        rm -f ${_Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_ten" ] \
        || [ -e "${_Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_ten
        rm -f ${_Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_eleven" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eleven_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eleven
        rm -f ${_Plr}/modules/.o_contrib_eleven_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_eight" ]; then
        ln -sfn ${_O_CONTRIB_EIGHT} ${_Plr}/modules/o_contrib_eight &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ -e "${_Plr}/core/themes/classy" ] \
      && [ ! -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_NINE}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_eight" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eight
        rm -f ${_Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_ten" ] \
        || [ -e "${_Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_ten
        rm -f ${_Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_eleven" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eleven_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eleven
        rm -f ${_Plr}/modules/.o_contrib_eleven_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_nine" ]; then
        ln -sfn ${_O_CONTRIB_NINE} ${_Plr}/modules/o_contrib_nine &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ ! -e "${_Plr}/core/themes/classy" ] \
      && [ ! -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_TEN}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_eight" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eight
        rm -f ${_Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_nine" ] \
        || [ -e "${_Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_nine
        rm -f ${_Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_eleven" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eleven_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eleven
        rm -f ${_Plr}/modules/.o_contrib_eleven_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_ten" ]; then
        ln -sfn ${_O_CONTRIB_TEN} ${_Plr}/modules/o_contrib_ten &> /dev/null
      fi
    elif [ -e "${_Plr}/core/themes/olivero" ] \
      && [ ! -e "${_Plr}/core/themes/classy" ] \
      && [ -e "${_Plr}/core/modules/workspaces_ui" ] \
      && [ -e "${_O_CONTRIB_ELEVEN}" ]; then
      if [ -e "${_Plr}/modules/o_contrib_eight" ] \
        || [ -e "${_Plr}/modules/.o_contrib_eight_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_eight
        rm -f ${_Plr}/modules/.o_contrib_eight_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_nine" ] \
        || [ -e "${_Plr}/modules/.o_contrib_nine_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_nine
        rm -f ${_Plr}/modules/.o_contrib_nine_dont_use
      fi
      if [ -e "${_Plr}/modules/o_contrib_ten" ] \
        || [ -e "${_Plr}/modules/.o_contrib_ten_dont_use" ]; then
        rm -f ${_Plr}/modules/o_contrib_ten
        rm -f ${_Plr}/modules/.o_contrib_ten_dont_use
      fi
      if [ ! -e "${_Plr}/modules/o_contrib_eleven" ]; then
        ln -sfn ${_O_CONTRIB_ELEVEN} ${_Plr}/modules/o_contrib_eleven &> /dev/null
      fi
    else
      if [ -e "${_Plr}/modules/watchdog" ]; then
        if [ -e "${_Plr}/modules/o_contrib" ]; then
          rm -f ${_Plr}/modules/o_contrib &> /dev/null
        fi
      else
        if [ ! -e "${_Plr}/modules/o_contrib" ] \
          && [ -e "${_O_CONTRIB}" ]; then
          ln -sfn ${_O_CONTRIB} ${_Plr}/modules/o_contrib &> /dev/null
        fi
      fi
    fi
  fi
}

_sql_convert() {
  sudo -u ${_HM_U}.ftp -H /opt/local/bin/sqlmagic convert @${_Dom} to-${_SQL_CONVERT}
}

_fix_modules() {
  local _iniTxt
  # The per-iteration strip in _daily_process is many drush runs and two curl
  # fetches old by the time we get here, and both modules dirs stay
  # tenant-writable throughout. Every INI leg below reads through
  # _ctrl_ini_read and edits through _ctrl_ini_sed / _ctrl_ini_add, so a
  # name swapped for a link or a FIFO since is never followed or opened; the
  # re-strip lets the seed legs recreate a planted name.
  _desymlink_planted "${_PLR_CTRL_F}" "${_DIR_CTRL_F}"
  _AUTO_CONFIG_ADVAGG=NO
  if [ -e "${_Plr}/modules/o_contrib/advagg" ] \
    || [ -e "${_Plr}/modules/o_contrib_seven/advagg" ]; then
    _MODULE_T=$(_run_drush8_nosilent_cmd "pml --status=enabled \
      --type=module | grep \(advagg\)" 2>&1)
    if [[ "${_MODULE_T}" =~ "(advagg)" ]]; then
      _AUTO_CONFIG_ADVAGG=YES
    fi
  fi
  if [ "${_AUTO_CONFIG_ADVAGG}" = "YES" ]; then
    if [ -e "/data/conf/default.boa_site_control.ini" ] \
      && [ ! -e "${_DIR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
    fi
    if _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
      _AGG_P=$(grep "advagg_auto_configuration" <<< "${_iniTxt}" 2>&1)
      _AGG_T=$(grep "^advagg_auto_configuration = TRUE" <<< "${_iniTxt}" 2>&1)
      if [[ "${_AGG_T}" =~ "advagg_auto_configuration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the site level ini file.
        ###
        if [[ "${_AGG_P}" =~ "advagg_auto_configuration" ]]; then
          _ctrl_ini_sed "${_DIR_CTRL_F}" \
            "s/.*advagg_auto_c.*/advagg_auto_configuration = TRUE/g" &> /dev/null
        else
          _ctrl_ini_add "${_DIR_CTRL_F}" "advagg_auto_configuration = TRUE"
        fi
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_site_control.ini" ] \
      && [ ! -e "${_DIR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
    fi
    if _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
      _AGG_P=$(grep "advagg_auto_configuration" <<< "${_iniTxt}" 2>&1)
      _AGG_T=$(grep "^advagg_auto_configuration = FALSE" \
        <<< "${_iniTxt}" 2>&1)
      if [[ "${_AGG_T}" =~ "advagg_auto_configuration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        if [[ "${_AGG_P}" =~ "advagg_auto_configuration" ]]; then
          _ctrl_ini_sed "${_DIR_CTRL_F}" \
            "s/.*advagg_auto_c.*/advagg_auto_configuration = FALSE/g" &> /dev/null
        else
          _ctrl_ini_add "${_DIR_CTRL_F}" ";advagg_auto_configuration = FALSE"
        fi
      fi
    fi
  fi

  if [ -e "${_Plr}/modules/o_contrib_seven" ] \
    && [ ! -e "${_Plr}/core" ]; then
    _PRIV_TEST=$(_run_drush8_nosilent_cmd "${_vGet} ^file_default_scheme$" 2>&1)
    if [[ "${_PRIV_TEST}" =~ "No matching variable" ]]; then
      _PRIV_TEST_RESULT=NONE
    else
      _PRIV_TEST_RESULT=OK
    fi
    _AUTO_CNF_PF_DL=NO
    if [ "${_PRIV_TEST_RESULT}" = "OK" ]; then
      _Pri=$(_run_drush8_nosilent_cmd "${_vGet} ^file_default_scheme$" \
        | grep "^file_default_scheme:" \
        | cut -d: -f2 \
        | awk '{ print $1}' \
        | sed "s/['\"]//g" \
        | tr -d "\n" 2>&1)
      _Pri=${_Pri//[^a-z]/}
      if [ "${_Pri}" = "private" ] || [ "${_Pri}" = "public" ]; then
        echo _Pri file_default_scheme for ${_Dom} is ${_Pri}
      fi
      if [ "${_Pri}" = "private" ]; then
        _AUTO_CNF_PF_DL=YES
      fi
    fi
    if [ "${_AUTO_CNF_PF_DL}" = "YES" ]; then
      if [ -e "/data/conf/default.boa_site_control.ini" ] \
        && [ ! -e "${_DIR_CTRL_F}" ]; then
        _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
      fi
      if _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
        _AC_PFD_T=$(grep "^allow_private_file_downloads = TRUE" \
          <<< "${_iniTxt}" 2>&1)
        if [[ "${_AC_PFD_T}" =~ "allow_private_file_downloads = TRUE" ]]; then
          _DO_NOTHING=YES
        else
          ###
          ### Do this only for the site level ini file.
          ###
          _ctrl_ini_sed "${_DIR_CTRL_F}" \
            "s/.*allow_private_f.*/allow_private_file_downloads = TRUE/g" &> /dev/null
        fi
      fi
    else
      if [ -e "/data/conf/default.boa_site_control.ini" ] \
        && [ ! -e "${_DIR_CTRL_F}" ]; then
        _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
      fi
      if _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
        _AC_PFD_T=$(grep "^allow_private_file_downloads = FALSE" \
          <<< "${_iniTxt}" 2>&1)
        if [[ "${_AC_PFD_T}" =~ "allow_private_file_downloads = FALSE" ]]; then
          _DO_NOTHING=YES
        else
          _ctrl_ini_sed "${_DIR_CTRL_F}" \
            "s/.*allow_private_f.*/allow_private_file_downloads = FALSE/g" &> /dev/null
        fi
      fi
    fi
  fi

  _AUTO_DT_FB_INT=NO
  if [ -e "${_Plr}/sites/all/modules/fb/fb_settings.inc" ] \
    || [ -e "${_Plr}/sites/all/modules/contrib/fb/fb_settings.inc" ]; then
    _AUTO_DT_FB_INT=YES
  else
    _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/fb/fb_settings.inc"
    if [ "${_FILE_EXISTS}" = "YES" ]; then
      _AUTO_DT_FB_INT=YES
    else
      _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/contrib/fb/fb_settings.inc"
      if [ "${_FILE_EXISTS}" = "YES" ]; then
        _AUTO_DT_FB_INT=YES
      fi
    fi
  fi
  if [ "${_AUTO_DT_FB_INT}" = "YES" ]; then
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
    fi
    if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
      _AD_FB_T=$(grep "^auto_detect_facebook_integration = TRUE" \
        <<< "${_iniTxt}" 2>&1)
      if [[ "${_AD_FB_T}" =~ "auto_detect_facebook_integration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the platform level ini file, so the site
        ### level ini file can disable this check by setting it
        ### explicitly to auto_detect_facebook_integration = FALSE
        ###
        _ctrl_ini_sed "${_PLR_CTRL_F}" \
          "s/.*auto_detect_face.*/auto_detect_facebook_integration = TRUE/g" &> /dev/null
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
    fi
    if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
      _AD_FB_T=$(grep "^auto_detect_facebook_integration = FALSE" \
        <<< "${_iniTxt}" 2>&1)
      if [[ "${_AD_FB_T}" =~ "auto_detect_facebook_integration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        _ctrl_ini_sed "${_PLR_CTRL_F}" \
          "s/.*auto_detect_face.*/auto_detect_facebook_integration = FALSE/g" &> /dev/null
      fi
    fi
  fi

  _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=NO
  if [ -e "${_Plr}/sites/all/modules/domain/settings.inc" ] \
    || [ -e "${_Plr}/sites/all/modules/contrib/domain/settings.inc" ]; then
    _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
  else
    _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/domain/settings.inc"
    if [ "${_FILE_EXISTS}" = "YES" ]; then
      _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
    else
      _check_file_with_wildcard_path "${_Plr}/profiles/*/modules/contrib/domain/settings.inc"
      if [ "${_FILE_EXISTS}" = "YES" ]; then
        _AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION=YES
      fi
    fi
  fi
  if [ "${_AUTO_DETECT_DOMAIN_ACCESS_INTEGRATION}" = "YES" ]; then
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
    fi
    if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
      _AD_DA_T=$(grep "^auto_detect_domain_access_integration = TRUE" \
        <<< "${_iniTxt}" 2>&1)
      if [[ "${_AD_DA_T}" =~ "auto_detect_domain_access_integration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the platform level ini file, so the site
        ### level ini file can disable this check by setting it
        ### explicitly to auto_detect_domain_access_integration = FALSE
        ###
        _ctrl_ini_sed "${_PLR_CTRL_F}" \
          "s/.*auto_detect_domain.*/auto_detect_domain_access_integration = TRUE/g" &> /dev/null
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
    fi
    if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
      _AD_DA_T=$(grep "^auto_detect_domain_access_integration = FALSE" \
        <<< "${_iniTxt}" 2>&1)
      if [[ "${_AD_DA_T}" =~ "auto_detect_domain_access_integration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        _ctrl_ini_sed "${_PLR_CTRL_F}" \
          "s/.*auto_detect_domain.*/auto_detect_domain_access_integration = FALSE/g" &> /dev/null
      fi
    fi
  fi

  ###
  ### Add new INI variables if missing
  ###
  ### Each INI is read once (_ctrl_ini_read) and whatever is missing is
  ### appended in one _ctrl_ini_add, never by ">>" on a name the tenant can
  ### swap. The re-strip lets a later seed leg recreate a planted name.
  _desymlink_planted "${_PLR_CTRL_F}" "${_DIR_CTRL_F}"
  if _CTRL_INI_TXT=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
    _CTRL_INI_ADD=
    _ctrl_ini_want "session_cookie_ttl" ";session_cookie_ttl = 86400"
    _ctrl_ini_want "session_gc_eol" ";session_gc_eol = 86400"
    _ctrl_ini_want "enable_newrelic_integration" ";enable_newrelic_integration = FALSE"
    _ctrl_ini_want "redis_old_nine_mode" ";redis_old_nine_mode = FALSE"
    _ctrl_ini_want "redis_old_eight_mode" ";redis_old_eight_mode = FALSE"
    _ctrl_ini_want "redis_flush_forced_mode" ";redis_flush_forced_mode = TRUE"
    _ctrl_ini_want "redis_lock_enable" ";redis_lock_enable = TRUE"
    _ctrl_ini_want "redis_path_enable" ";redis_path_enable = TRUE"
    _ctrl_ini_want "redis_scan_enable" ";redis_scan_enable = FALSE"
    _ctrl_ini_want "redis_exclude_bins" ";redis_exclude_bins = FALSE"
    _ctrl_ini_want "speed_booster_anon_cache_ttl" ";speed_booster_anon_cache_ttl = 10"
    _ctrl_ini_want "disable_drupal_page_cache" ";disable_drupal_page_cache = FALSE"
    _ctrl_ini_want "allow_private_file_downloads" ";allow_private_file_downloads = FALSE"
    _ctrl_ini_want "entitycache_dont_enable" ";entitycache_dont_enable = FALSE"
    _ctrl_ini_want "views_cache_bully_dont_enable" ";views_cache_bully_dont_enable = FALSE"
    _ctrl_ini_want "views_content_cache_dont_enable" ";views_content_cache_dont_enable = FALSE"
    _ctrl_ini_want "set_composer_manager_vendor_dir" ";set_composer_manager_vendor_dir = FALSE"
    _ctrl_ini_want "redis_connect_timeout" ";redis_connect_timeout = 0.7"
    _ctrl_ini_want "redis_read_timeout" ";redis_read_timeout = 0.7"
    _ctrl_ini_want "redis_backoff_ttl" ";redis_backoff_ttl = 15"
    _ctrl_ini_want "redis_probe_retry" ";redis_probe_retry = TRUE"
    _ctrl_ini_want "redis_flush_apcu_on_recovery" ";redis_flush_apcu_on_recovery = TRUE"
    _ctrl_ini_want "redis_debug_header" ";redis_debug_header = FALSE"
    _ctrl_ini_want "^;?redis_debug[ =]" ";redis_debug = FALSE" -E
    if [ -n "${_CTRL_INI_ADD}" ]; then
      _ctrl_ini_add "${_PLR_CTRL_F}" "${_CTRL_INI_ADD}"
    fi
  fi
  if _CTRL_INI_TXT=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
    _CTRL_INI_ADD=
    _ctrl_ini_want "session_cookie_ttl" ";session_cookie_ttl = 86400"
    _ctrl_ini_want "session_gc_eol" ";session_gc_eol = 86400"
    _ctrl_ini_want "enable_newrelic_integration" ";enable_newrelic_integration = FALSE"
    _ctrl_ini_want "redis_old_nine_mode" ";redis_old_nine_mode = FALSE"
    _ctrl_ini_want "redis_old_eight_mode" ";redis_old_eight_mode = FALSE"
    _ctrl_ini_want "redis_flush_forced_mode" ";redis_flush_forced_mode = TRUE"
    _ctrl_ini_want "redis_lock_enable" ";redis_lock_enable = TRUE"
    _ctrl_ini_want "redis_path_enable" ";redis_path_enable = TRUE"
    _ctrl_ini_want "redis_scan_enable" ";redis_scan_enable = FALSE"
    _ctrl_ini_want "redis_exclude_bins" ";redis_exclude_bins = FALSE"
    _ctrl_ini_want "speed_booster_anon_cache_ttl" ";speed_booster_anon_cache_ttl = 10"
    _ctrl_ini_want "disable_drupal_page_cache" ";disable_drupal_page_cache = FALSE"
    _ctrl_ini_want "allow_private_file_downloads" ";allow_private_file_downloads = FALSE"
    _ctrl_ini_want "set_composer_manager_vendor_dir" ";set_composer_manager_vendor_dir = FALSE"
    _ctrl_ini_want "redis_connect_timeout" ";redis_connect_timeout = 0.7"
    _ctrl_ini_want "redis_read_timeout" ";redis_read_timeout = 0.7"
    _ctrl_ini_want "redis_backoff_ttl" ";redis_backoff_ttl = 15"
    _ctrl_ini_want "redis_probe_retry" ";redis_probe_retry = TRUE"
    _ctrl_ini_want "redis_flush_apcu_on_recovery" ";redis_flush_apcu_on_recovery = TRUE"
    _ctrl_ini_want "redis_debug_header" ";redis_debug_header = FALSE"
    _ctrl_ini_want "^;?redis_debug[ =]" ";redis_debug = FALSE" -E
    if [ -n "${_CTRL_INI_ADD}" ]; then
      _ctrl_ini_add "${_DIR_CTRL_F}" "${_CTRL_INI_ADD}"
    fi
  fi

  if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
    _EC_DE_T=$(grep "^entitycache_dont_enable = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_EC_DE_T}" =~ "entitycache_dont_enable = TRUE" ]] \
      || [ -e "${_Plr}/profiles/commons" ]; then
      _ENTITYCACHE_DONT_ENABLE=YES
    else
      _ENTITYCACHE_DONT_ENABLE=NO
    fi
  else
    _ENTITYCACHE_DONT_ENABLE=NO
  fi

  if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
    _VCB_DE_T=$(grep "^views_cache_bully_dont_enable = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_VCB_DE_T}" =~ "views_cache_bully_dont_enable = TRUE" ]]; then
      _VIEWS_CACHE_BULLY_DONT_ENABLE=YES
    else
      _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
    fi
  else
    _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
  fi

  if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
    _VCC_DE_T=$(grep "^views_content_cache_dont_enable = TRUE" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_VCC_DE_T}" =~ "views_content_cache_dont_enable = TRUE" ]]; then
      _VIEWS_CONTENT_CACHE_DONT_ENABLE=YES
    else
      _VIEWS_CONTENT_CACHE_DONT_ENABLE=NO
    fi
  else
    _VIEWS_CONTENT_CACHE_DONT_ENABLE=NO
  fi

  if [ -e "${_Plr}/modules/o_contrib" ]; then
    if [ ! -e "${_Plr}/modules/user" ] \
      || [ ! -e "${_Plr}/sites/all/modules" ] \
      || [ ! -e "${_Plr}/profiles" ]; then
      echo "WARNING: THIS PLATFORM IS BROKEN! ${_Plr}"
    elif [ ! -e "${_Plr}/modules/path_alias_cache" ]; then
      echo "WARNING: THIS PLATFORM IS NOT A VALID PRESSFLOW PLATFORM! ${_Plr}"
    elif [ -e "${_Plr}/modules/path_alias_cache" ] \
      && [ -e "${_Plr}/modules/user" ]; then
      _MODX=ON
      if [ ! -z "${_MODULES_OFF_SIX}" ]; then
        _disable_modules_with_drush8 "${_MODULES_OFF_SIX}"
      fi
      if [ ! -z "${_MODULES_ON_SIX}" ]; then
        _enable_modules_with_drush8 "${_MODULES_ON_SIX}"
      fi
      _run_drush8_cmd "sqlq \"UPDATE system SET weight = '-1' \
        WHERE type = 'module' AND name = 'path_alias_cache'\""
    fi
  elif [ -e "${_Plr}/modules/o_contrib_seven" ]; then
    if [ ! -e "${_Plr}/modules/user" ] \
      || [ ! -e "${_Plr}/sites/all/modules" ] \
      || [ ! -e "${_Plr}/profiles" ]; then
      echo "WARNING: THIS PLATFORM IS BROKEN! ${_Plr}"
    else
      _MODX=ON
      if [ ! -z "${_MODULES_OFF_SEVEN}" ]; then
        _disable_modules_with_drush8 "${_MODULES_OFF_SEVEN}"
      fi
      if [ "${_ENTITYCACHE_DONT_ENABLE}" = "NO" ]; then
        _enable_modules_with_drush8 "entitycache"
      fi
      if [ ! -z "${_MODULES_ON_SEVEN}" ]; then
        _enable_modules_with_drush8 "${_MODULES_ON_SEVEN}"
      fi
    fi
  elif [ -e "${_Plr}/core/lib/Drupal.php" ]; then
    ###
    ### D8+ platform (the alias root is the docroot; core/lib/Drupal.php
    ### is the D8-11 marker and does not exist in Backdrop). Detection
    ### and operator alert ONLY -- no Drush contact with the site in
    ### either direction (see _check_modules_d8plus_policy), and no ON
    ### twin: enabling modules on config-managed D8+ sites from the
    ### outside would create config drift.
    ###
    _MODX=ON
    if [ ! -z "${_MODULES_OFF_EIGHT_PLUS}" ]; then
      _check_modules_d8plus_policy "${_MODULES_OFF_EIGHT_PLUS}"
    fi
  fi
}

_if_site_db_conversion() {
  local _iniTxt
  ###
  ### Detect db conversion mode, if set per platform or per site.
  ###
  ### Every site starts from the instance value. _SQL_CONVERT is a shell
  ### global this function assigns from the INI files, so without the reset
  ### one site's sql_conversion_mode carried over to every later site of the
  ### same account. The instance value is captured on the account's first
  ### site, before anything here has touched it.
  if [ "${_sqlCnvFor:-}" != "${_HM_U}" ]; then
    _sqlCnvFor="${_HM_U}"
    _sqlCnvAcct="${_SQL_CONVERT:-}"
  fi
  _SQL_CONVERT="${_sqlCnvAcct}"
  ### An instance-wide force ignores the INI files, as octopus.cnf promises.
  _sqlCnvForced=NO
  case "${_sqlCnvAcct}" in
    YES|innodb) _sqlCnvForced=YES ;;
  esac
  if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
    _SQL_INDB_P=$(grep "sql_conversion_mode" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SQL_INDB_P}" =~ "sql_conversion_mode" ]]; then
      _DO_NOTHING=YES
    else
      _ctrl_ini_add "${_PLR_CTRL_F}" ";sql_conversion_mode = NO"
    fi
    _SQL_INDB_T=$(grep "^sql_conversion_mode = innodb" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SQL_INDB_T}" =~ "sql_conversion_mode = innodb" ]] \
      && [ "${_sqlCnvForced}" != "YES" ]; then
      _SQL_CONVERT=innodb
    fi
    _SQL_MYSM_T=$(grep "^sql_conversion_mode = myisam" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SQL_MYSM_T}" =~ "sql_conversion_mode = myisam" ]] \
      && [ "${_sqlCnvForced}" != "YES" ]; then
      _SQL_CONVERT=myisam
    fi
  fi
  if _iniTxt=$(_ctrl_ini_read "${_DIR_CTRL_F}"); then
    _SQL_INDB_P=$(grep "sql_conversion_mode" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SQL_INDB_P}" =~ "sql_conversion_mode" ]]; then
      _DO_NOTHING=YES
    else
      _ctrl_ini_add "${_DIR_CTRL_F}" ";sql_conversion_mode = NO"
    fi
    _SQL_INDB_T=$(grep "^sql_conversion_mode = innodb" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SQL_INDB_T}" =~ "sql_conversion_mode = innodb" ]] \
      && [ "${_sqlCnvForced}" != "YES" ]; then
      _SQL_CONVERT=innodb
    fi
    _SQL_MYSM_T=$(grep "^sql_conversion_mode = myisam" \
      <<< "${_iniTxt}" 2>&1)
    if [[ "${_SQL_MYSM_T}" =~ "sql_conversion_mode = myisam" ]] \
      && [ "${_sqlCnvForced}" != "YES" ]; then
      _SQL_CONVERT=myisam
    fi
  fi
  if [ "${_hostedSys}" = "YES" ]; then
    _DENY_SQL_CONVERT=YES
    _SQL_CONVERT=
  fi
  if [ -z "${_DENY_SQL_CONVERT}" ] \
    && [ ! -z "${_SQL_CONVERT}" ] \
    && [ "${_DOW}" = "2" ]; then
    if [ "${_SQL_CONVERT}" = "YES" ]; then
      _SQL_CONVERT=innodb
    elif [ "${_SQL_CONVERT}" = "NO" ]; then
      _SQL_CONVERT=
    fi
    if [ "${_SQL_CONVERT}" = "myisam" ] \
      || [ "${_SQL_CONVERT}" = "innodb" ]; then
      _TIMP=$(date +%y%m%d-%H%M%S)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${_Dom} started"
      _sql_convert
      _TIMP=$(date +%y%m%d-%H%M%S)
      echo "${_TIMP} sql conversion to-${_SQL_CONVERT} \
        for ${_Dom} completed"
    fi
  fi
}

_cleanup_ghost_platforms() {
  _provision_running && return
  [ -e "${_Plr}" ] || return
  local _gh_mark="${_usEr}/log/ctrl/ghost-platform-$(basename "${_Plr}" 2>/dev/null).seen"
  # Version-agnostic validity: a real docroot (index.php at root or under
  # web/docroot/html on the Provision-docroot-corrected _Plr) or a vendor/ tree
  # means a live platform -- never a ghost. Do NOT key on root index.php+profiles
  # (a Composer D8+ docroot without a top-level profiles/ would be mis-flagged).
  if [ -n "$(_detect_real_docroot "${_Plr}")" ] || [ -e "${_Plr}/vendor" ]; then
    _ghost_seen_reset "${_gh_mark}"
    return
  fi
  # Ghost candidate: require it across consecutive nights before acting, then the
  # opt-in flag (per-account octopus.cnf, else system barracuda.cnf).
  if ! _ghost_seen_enough "${_gh_mark}"; then
    echo "GHOST platform ${_Plr} detected (grace run, not moved)"
    return
  fi
  if _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_PLATFORMS_CLEANUP \
    || _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; then
    _acct_undo_tree "${_Plr}" &> /dev/null
    echo "GHOST platform ${_Plr} detected and moved to ${_usEr}/undo/"
  else
    echo "GHOST platform ${_Plr} detected (dry-run; set _GHOST_PLATFORMS_CLEANUP=YES to move)"
  fi
}

_fix_seven_core_patch() {
  ### Derive the owning group from the PLATFORM PATH, never a literal and never
  ### the account: _Plr may resolve under the shared /data/all or /data/disk/all
  ### store a legacy instance still hosts sites on, and the helper answers
  ### 'users' for those (and on an unconverted box), the account's own group
  ### only for a tree under /data/disk/<account>.
  local _grp
  _grp=$(_acct_group "${_Plr}")
  ### profiles/ is 0775 and group-writable on a static platform, so this marker path
  ### is tenant-plantable, and -f is FALSE for a dangling link. The marker is
  ### put as a fresh file inside the real profiles/ (_acct_put_here), so a link
  ### replanted after the strip is replaced, never written through; the strip
  ### still lets a planted link read as "no marker yet".
  _desymlink_planted "${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info"
  if [ ! -f "${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info" ]; then
    _PATCH_TEST=$(grep "foreach (array_values(\$data)" \
      ${_Plr}/includes/database/database.inc 2>&1)
    if [[ "${_PATCH_TEST}" =~ "array_values" ]]; then
      _acct_in_resolved_dir "${_Plr}/profiles" \
        _acct_put_here SA-CORE-2014-005-D7-fix.info fixed
    else
      cd ${_Plr}
      patch -p1 < /var/xdrago/conf/SA-CORE-2014-005-D7.patch
      ### Every dir in a static platform is 0775 and group-writable, so these glob
      ### hits are tenant-plantable names, and chown and chmod both follow a
      ### symlink named on the command line. -h for the chown; for the chmod,
      ### which has no -h, hand find the SHELL-expanded leaves: a legitimate
      ### shared-core includes/ link is resolved as an intermediate either way,
      ### while a planted leaf is -type l and never matches. No trailing slash
      ### on a directory -- that would make find resolve a planted database/
      ### and walk the target. Same shape as the *.php pass in _fix_permissions.
      chown -h ${_HM_U}:${_grp} ${_Plr}/includes/database/*.inc &> /dev/null
      find ${_Plr}/includes/database/*.inc -type f \
        -exec chmod 0664 {} \; &> /dev/null
      _acct_in_resolved_dir "${_Plr}/profiles" \
        _acct_put_here SA-CORE-2014-005-D7-fix.info fixed
    fi
    ### profiles/ is 0775 and group-writable, so *-fix.info matches tenant-created
    ### names; -h for the chown, and for the chmod hand find the shell-expanded
    ### leaves -- never a directory with a trailing slash, which find would
    ### resolve through a planted link.
    chown -h ${_HM_U}:${_grp} ${_Plr}/profiles/*-fix.info &> /dev/null
    find ${_Plr}/profiles/*-fix.info -type f \
      -exec chmod 0664 {} \; &> /dev/null
  fi
}

_fix_static_permissions() {
  _cleanup_ghost_platforms
  ### ~/static is 02775 and every platform dir under it 0775 (the find below),
  ### both group-writable by the account's shell identities, so the platform
  ### name -- and the docroot name
  ### under it -- are tenant-plantable, and the chown -R below dereferences a
  ### symlink given as its starting point (pwd -P then resolves through it
  ### too). A platform root is never legitimately a symlink and a static
  ### platform always resolves inside the account, so anchor the resolved root
  ### once, here, before anything acts on it.
  _rPlr=$(realpath -e -- "${_Plr}" 2>/dev/null)
  _rUsr=$(realpath -e -- "${_usEr}" 2>/dev/null)
  case "${_rPlr}/" in
    "${_rUsr}"/static/*)
      :
      ;;
    *)
      echo "SKIP: platform root resolves outside ${_usEr}/static: ${_Plr}"
      return
      ;;
  esac
  if [ -e "${_Plr}/profiles" ]; then
    if [ -e "${_Plr}/web.config" ] && [ ! -e "${_Plr}/core" ]; then
      _fix_seven_core_patch
    fi
    if [ -e "${_Plr}/core/lib/Drupal.php" ] \
      && [ -e "${_Plr}/../vendor/autoload.php" ] \
      && grep -qE '"drupal/core(-recommended)?"' "${_Plr}/../composer.json" 2>/dev/null; then
      _use_Plr="$(cd "${_Plr}/.." && pwd -P)"
      ### pwd -P walks one level UP: a tenant who seeds ~/static/composer.json
      ### and ~/static/vendor/autoload.php beside a docroot placed directly
      ### under ~/static would aim the whole-tree chown at ~/static itself
      ### (control/, the files store). An account-level dir is never a
      ### composer app root: fall back to the docroot, as the probe does.
      case "${_use_Plr}/" in
        "${_rUsr}"/|"${_rUsr}"/static/)
          _use_Plr="${_Plr}"
          ;;
      esac
    else
      _use_Plr="${_Plr}"
    fi
    if [ ! -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_use_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.ctm-lock-${_NOW}.info" ]; then
        chown -R ${_HM_U} ${_use_Plr} &> /dev/null
        _log_ctrl_mark "plr.${_PlrID}.ctm-lock-${_NOW}.info"
      fi
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_use_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.ctm-unlock-${_NOW}.info" ]; then
        chown -R ${_HM_U}.ftp ${_use_Plr} &> /dev/null
        _log_ctrl_mark "plr.${_PlrID}.ctm-unlock-${_NOW}.info"
      fi
    fi
    if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info" ]; then
      ### The three Drush-lock dirs keep whatever mode the lock state gave
      ### them (0400 locked, 0775 after Unlock Local Drush), as on a built-in
      ### platform below: only a provision lock or unlock changes that state.
      ### Setting them to 0400 here, after the widening, closed an owner's
      ### unlock as a half-lock: no Aegir patches, and no rebuild of the sites
      ### whose container the site-local Drush compiled in the window, which
      ### then fail every request that logs; the next lock, finding 0400,
      ### skipped that rebuild too. Only the three directories themselves are
      ### skipped (their contents are still walked), and nothing here names
      ### them on a command line, so a link planted at one is never followed.
      find "${_use_Plr}" -type d \
        ! \( -path "*/vendor/drush" -o -path "*/vendor/symfony/console/Input" \
        -o -path "*/vendor/symfony/console/Style" \) \
        -exec chmod 0775 {} \; &> /dev/null
      find ${_use_Plr} -type f -exec chmod 0664 {} \; &> /dev/null
      ### The pass above widened every sites/<uri>/*.php to 0664, and only an
      ### ACCEPTED site's arm narrows its own back (the 0440 pass at site
      ### level). A site the per-site loop refuses -- a symlinked modules at
      ### the control-dir gate, a path failing _validate_loop_dir, a tree
      ### without private/ -- would keep a world-readable, group-writable
      ### settings.php until the plant is gone. Narrow the credential files
      ### here, where the widening happens, for every site dir on the
      ### platform: a refused site must end no wider than an accepted one.
      ### find -P never descends a symlinked sites/ or sites/<uri>, -type f
      ### skips a planted link, so nothing here follows a tenant-plantable
      ### name; the scaffold's default.* copies and sites/all are not named.
      find ${_rPlr}/sites -mindepth 2 -maxdepth 2 -type f \
        \( -name settings.php -o -name local.settings.php \
        -o -name civicrm.settings.php -o -name solr.php -o -name drushrc.php \) \
        ! -path "${_rPlr}/sites/all/*" -exec chmod 0440 {} \; &> /dev/null
    fi
  fi
}

_fix_expected_symlinks() {
  if [ ! -e "${_Plr}/js.php" ] && [ -e "${_Plr}" ]; then
    if [ -e "${_Plr}/modules/o_contrib_seven" ] \
      && [ -e "${_O_CONTRIB_SEVEN}/js/js.php" ]; then
      ln -sfn ${_O_CONTRIB_SEVEN}/js/js.php ${_Plr}/js.php &> /dev/null
    elif [ -e "${_Plr}/modules/o_contrib" ] \
      && [ -e "${_O_CONTRIB}/js/js.php" ]; then
      ln -sfn ${_O_CONTRIB}/js/js.php ${_Plr}/js.php &> /dev/null
    fi
  fi
}

_fix_permissions() {
  ### Derive the owning group from the PLATFORM PATH (re-derived from the site
  ### path below), never a literal and never the account: _Plr and _Dir may
  ### resolve under the shared /data/all or /data/disk/all store a legacy
  ### instance still hosts sites on, and the helper answers 'users' there (and
  ### on an unconverted box), the account's own group only for a tree under
  ### /data/disk/<account>. Local, so nothing leaks across the per-site loop.
  local _grp _drTxt
  _grp=$(_acct_group "${_Plr}")
  ### modules,themes,libraries - profile level in ~/static
  searchStringT="/static/"
  case ${_Plr} in
  *"$searchStringT"*)
  _fix_static_permissions
  ;;
  esac
  ### modules,themes,libraries - platform level
  if [ -f "${_Plr}/profiles/core-permissions-update-fix.info" ]; then
    rm -f ${_Plr}/profiles/*permissions*.info
    rm -f ${_Plr}/sites/all/permissions-fix*
  fi
  ### sites and sites/all are names a tenant can plant as symlinks (the
  ### docroot is group-writable), and every root op below walks THROUGH
  ### them; -h and find -P protect only the final component. A symlinked
  ### skeleton is never legitimate, so leave such a platform alone.
  ### The four names under sites/all -- modules, themes, libraries and
  ### drush -- are plantable as well: a codebase the tenant built under
  ### ~/static carries whatever it was unpacked with, and sites/all is
  ### group-writable for the shell pair between _fix_static_permissions
  ### widening every dir and the sites/* narrowing below. The archive sweep
  ### expands a glob THROUGH all four, both chown -R legs through the first
  ### three and the drushrc.php chown through drush; -h protects only the last
  ### component of each path (the chmod finds take the names as starting
  ### points and never follow them). The loop head already refuses a
  ### symlinked modules; the other three were not covered. None is ever
  ### legitimately a symlink (the o_contrib* links live under the platform
  ### root's own modules/, never under sites/all) -- the shape
  ### fix-drupal-site-ownership.sh refuses outright at site level -- so
  ### withhold every leg that walks through them here, but still re-assert
  ### the skeleton modes and stamp the per-pass marker: a withheld platform
  ### must end no wider than an accepted one, and the whole-tree chmod pass
  ### in _fix_static_permissions keys on that marker. A foreign-CMS platform
  ### is different: its sites/all/drush IS created below (its drushrc renders
  ### there) and no SKIP line is printed; only the legs for the three Drupal
  ### directories it does not carry are withheld.
  local _plrCodeLink=""
  local _cd
  for _cd in modules themes libraries drush; do
    if [ -n "${_Plr}" ] && [ -L "${_Plr}/sites/all/${_cd}" ]; then
      _plrCodeLink="${_plrCodeLink} ${_cd}"
    fi
  done
  if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info" ] \
    && [ -e "${_Plr}" ] \
    && [ ! -L "${_Plr}/sites" ] \
    && [ ! -L "${_Plr}/sites/all" ]; then
    if [ -n "${_plrCodeLink}" ]; then
      echo "SKIP: symlinked sites/all code dir on ${_Plr}:${_plrCodeLink}"
    elif [ "${_FOREIGN_CMS}" = "YES" ]; then
      ### A Grav or Textpattern platform has no Drupal sites/all/{modules,
      ### themes,libraries}; sites/all/drush is where its drushrc renders.
      mkdir -p ${_Plr}/sites/all/drush
    else
      mkdir -p ${_Plr}/sites/all/{modules,themes,libraries,drush}
    fi
    ### Drupal's sites/all/{modules,themes,libraries} carry nothing on a Grav or
    ### Textpattern platform, and the recursive chowns below would walk a link
    ### planted at one of those names: skip the whole leg there.
    if [ "${_FOREIGN_CMS}" != "YES" ] && [ -z "${_plrCodeLink}" ]; then
      find ${_Plr}/sites/all/{modules,themes,libraries,drush}/*{.tar,.tar.gz,.zip} \
        -type f -exec rm -f {} \; &> /dev/null
      if [ ! -e "${_usEr}/static/control/unlock.info" ] \
        && [ ! -e "${_Plr}/skip.info" ]; then
        if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.lock-${_NOW}.info" ]; then
          ### -h: those three dirs are 02775 and group-writable (see the find below),
          ### so every glob hit is a tenant-plantable name and chown -R follows a
          ### symlink given as its starting point. -h also stops the recursion
          ### rewriting ownership through the legitimate o_contrib* links into
          ### the shared distro tree. Same shape as the files leg at 1550.
          chown -h -R ${_HM_U}:${_grp} \
            ${_Plr}/sites/all/{modules,themes,libraries}/* &> /dev/null
          _log_ctrl_mark "plr.${_PlrID}.lock-${_NOW}.info"
        fi
      elif [ -e "${_usEr}/static/control/unlock.info" ] \
        && [ ! -e "${_Plr}/skip.info" ]; then
        if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.unlock-${_NOW}.info" ]; then
          ### -h for the same reason as the lock branch above; here the planted
          ### target would be handed straight to the tenant's shell user.
          chown -h -R ${_HM_U}.ftp:${_grp} \
            ${_Plr}/sites/all/{modules,themes,libraries}/* &> /dev/null
          _log_ctrl_mark "plr.${_PlrID}.unlock-${_NOW}.info"
        fi
      fi
    fi
    ### -h on the chown and find -P (never a bare glob) on the chmods: the
    ### sites/* entries are tenant-creatable names once sites/ takes group
    ### write below, so none of them may be followed. drushrc.php sits BELOW
    ### drush, the one path here that resolves through a plantable name, so
    ### it is withheld with the code-dir legs above.
    if [ -z "${_plrCodeLink}" ]; then
      chown -h ${_HM_U}:${_grp} \
        ${_Plr}/sites/all/drush/drushrc.php &> /dev/null
    fi
    chown -h ${_HM_U}:${_grp} \
      ${_Plr}/sites \
      ${_Plr}/sites/* \
      ${_Plr}/sites/sites.php \
      ${_Plr}/sites/all \
      ${_Plr}/sites/all/{modules,themes,libraries,drush} &> /dev/null
    chmod 0751 ${_Plr}/sites &> /dev/null
    find ${_Plr}/sites -mindepth 1 -maxdepth 1 -type d -exec \
      chmod 0755 {} \; &> /dev/null
    find ${_Plr}/sites -mindepth 1 -maxdepth 1 -type f \
      \( -name "*.php" -o -name "*.txt" -o -name "*.yml" \) -exec \
      chmod 0644 {} \; &> /dev/null
    [ -L "${_Plr}/autoload.php" ] || chmod 0664 ${_Plr}/autoload.php &> /dev/null
    [ -L "${_Plr}/sites/all/drush" ] || chmod 0755 ${_Plr}/sites/all/drush &> /dev/null
    ### Tenant composer codebases: the two directories core's composer
    ### scaffold writes into stay group-writable for the shell user
    ### (omega8cc/boa#1936); mirrors fix-drupal-platform-permissions.sh.
    if [[ "${_Plr}" =~ "/static/" ]] \
      && [ -e "${_Plr}/core/lib/Drupal.php" ]; then
      chmod 02771 ${_Plr}/sites &> /dev/null
      if [ -d "${_Plr}/sites/default" ] && [ ! -L "${_Plr}/sites/default" ]; then
        chmod 02775 ${_Plr}/sites/default &> /dev/null
      fi
    fi
    ### Group write is the shell pair's free-ride territory under ~/static
    ### only. A hostmaster tree (aegir/distro) takes none at all; a built-in
    ### platform keeps its documented tenant-writable sites/all/* but its
    ### core, profiles, includes, vendor and root take none -- heal the
    ### code dirs the platform script used to widen (find -P never follows
    ### the o_contrib* links under sites/all, and vendor/drush keeps its
    ### own lock from the platform script).
    if [[ "${_Plr}" =~ /aegir/distro/ ]]; then
      _pDm=0755
      _pFm=0644
    else
      _pDm=02775
      _pFm=0664
    fi
    ### A Grav or Textpattern root keeps the modes its own platform script
    ### sets: this Drupal code-dir pass stripped Grav's vendor/bin exec bits.
    if [[ ! "${_Plr}" =~ /static/ ]] && [ "${_FOREIGN_CMS}" != "YES" ]; then
      [ -L "${_Plr}" ] || chmod 0755 ${_Plr} &> /dev/null
      ### The three Drush-lock dirs keep whatever mode the lock state gave
      ### them (0400 locked, 0775 after Unlock Local Drush): prune, never
      ### widen or narrow them here.
      find ${_Plr}/{modules,themes,libraries,includes,misc,profiles,core} \
        ${_Plr}/vendor ${_Plr}/../vendor \
        \( -path "*/vendor/drush" -o -path "*/vendor/symfony/console/Input" \
        -o -path "*/vendor/symfony/console/Style" \) -prune \
        -o -type d -exec chmod 0755 {} \; &> /dev/null
      find ${_Plr}/{modules,themes,libraries,includes,misc,profiles,core} \
        ${_Plr}/vendor ${_Plr}/../vendor \
        \( -path "*/vendor/drush" -o -path "*/vendor/symfony/console/Input" \
        -o -path "*/vendor/symfony/console/Style" \) -prune \
        -o -type f -exec chmod 0644 {} \; &> /dev/null
    fi
    find ${_Plr}/sites/all/{modules,themes,libraries} -type d -exec \
      chmod ${_pDm} {} \; &> /dev/null
    find ${_Plr}/sites/all/{modules,themes,libraries} -type f -exec \
      chmod ${_pFm} {} \; &> /dev/null
    ### expected symlinks
    _fix_expected_symlinks
    ### known exceptions
    ### GNU chmod dereferences a symlink given on the command line and has no
    ### -h to fall back on, and sites/all/libraries is tenant-writable, so both
    ### tcpdf and its cache child are names the tenant can plant. A planted
    ### parent redirects the recursive chown too. Precheck both; a real
    ### directory is treated exactly as before.
    if [ "${_FOREIGN_CMS}" != "YES" ] \
      && [ -z "${_plrCodeLink}" ] \
      && [ ! -L "${_Plr}/sites/all/libraries/tcpdf" ] \
      && [ ! -L "${_Plr}/sites/all/libraries/tcpdf/cache" ]; then
      chmod -R 775 ${_Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
      chown -R ${_HM_U}:www-data \
        ${_Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
    fi
    _log_ctrl_mark "plr.${_PlrID}.perm-fix-${_NOW}.info"
  fi
  ### sites/ is 02771 and group-writable on tenant composer codebases (the
  ### account's shell identities; any tenant while the instance still carries
  ### the box-wide 'users' group), so sites/<uri> is a name a tenant can unlink
  ### and re-create: a symlink there redirects
  ### every rm/mkdir/chown/find in this block through it, and none of them
  ### re-checks. A site_path is never legitimately a symlink (alias links point
  ### AT it), so refuse one and leave the site alone.
  ### Same shape one level down: the site's modules, themes and libraries
  ### are 02775 group-writable and the site dir is the tenant's under
  ### unlock.info; the archive sweep and both chown -R legs below expand a
  ### glob through them and the local-allow.info rm resolves through
  ### modules, and only modules is refused by the _validate_ctrl_dir gate
  ### at the head of the loop. Withhold exactly those four legs and let
  ### the rest of the arm run: unlike
  ### fix-drupal-site-ownership.sh, which refuses the whole site and widens
  ### nothing first, this pass has just run _fix_static_permissions over a
  ### ~/static platform (every file 0664), and the *.php 0440 pass in the
  ### arm is the only thing that narrows settings.php back -- a refused site
  ### must end no wider than an accepted one, the platform leg's rule. The
  ### foreign-CMS arm further down expands no glob through those names, so
  ### it is neither withheld nor reported.
  local _siteCodeLink=""
  for _cd in modules themes libraries; do
    if [ -n "${_Dir}" ] && [ -L "${_Dir}/${_cd}" ]; then
      _siteCodeLink="${_siteCodeLink} ${_cd}"
    fi
  done
  if [ -n "${_siteCodeLink}" ] && [ "${_FOREIGN_CMS}" != "YES" ]; then
    echo "SKIP: symlinked site code dir in ${_Dir}:${_siteCodeLink}"
  fi
  if [ -e "${_Dir}" ] \
    && [ ! -L "${_Dir}" ] \
    && [ -e "${_Dir}/drushrc.php" ] \
    && [ -e "${_Dir}/files" ] \
    && [ -e "${_Dir}/private" ] \
    && [ "${_FOREIGN_CMS}" != "YES" ]; then
    ### Cleanup
    rm ${_Dir}/*.{codebasecheck*,hm-fix-*,ctm-lock-*,lock-*,perm-fix-*}.info &> /dev/null
    ### directory and settings files - site level
    if [ ! -e "${_Dir}/modules" ]; then
      mkdir ${_Dir}/modules &> /dev/null
    fi
    if [ -e "${_Dir}/aegir.services.yml" ]; then
      rm -f ${_Dir}/aegir.services.yml
    fi
    ### Site-level writes: re-derive from the SITE path (see the top of this
    ### function) -- a site can sit on the shared store even when its platform
    ### variable does not.
    _grp=$(_acct_group "${_Dir}")
    ### -h on both: the site dir is owned by the tenant's shell user in
    ### unlock.info mode, so each of these names is plantable, and a bare chown
    ### follows the link (settings.php -> /etc/shadow hands root's shadow file
    ### to the tenant). No-op on the regular files they normally are.
    chown -h ${_HM_U}:${_grp} ${_Dir} &> /dev/null
    chown -h ${_HM_U}:www-data \
      ${_Dir}/{local.settings.php,settings.php,civicrm.settings.php,solr.php} &> /dev/null
    find ${_Dir}/*.php -type f -exec chmod 0440 {} \; &> /dev/null
    ### The hostmaster site's drushrc.php carries the instance DB user (ALL
    ### PRIVILEGES) and only the backend user, its owner, ever reads it:
    ### no group read at all, box-wide 'users' or the account's own group alike.
    if [[ "${_Dir}" =~ /aegir/(distro|host_master)/ ]] && [ -f "${_Dir}/drushrc.php" ] \
      && [ ! -L "${_Dir}/drushrc.php" ]; then
      chmod 0400 ${_Dir}/drushrc.php &> /dev/null
    fi
    ### chmod follows a symlink named on the command line and has no -h; the
    ### find above avoids that with -type f, this one did not. Never
    ### legitimately a symlink -- same shape as the autoload.php guard below.
    [ -L "${_Dir}/civicrm.settings.php" ] \
      || chmod 0640 ${_Dir}/civicrm.settings.php &> /dev/null
    ### modules,themes,libraries - site level
    ### A symlink at any of the three redirects the legs below into whatever
    ### was planted -- the glob legs by expansion, the local-allow.info rm
    ### through modules as a path component (the refusal above names it):
    ### withhold exactly these four and nothing else in the arm. The
    ### head-of-loop modules gate is many drush runs old by now, so modules
    ### is re-checked here as well.
    if [ -z "${_siteCodeLink}" ]; then
      find ${_Dir}/{modules,themes,libraries}/*{.tar,.tar.gz,.zip} -type f -exec \
        rm -f {} \; &> /dev/null
      rm -f ${_Dir}/modules/local-allow.info
      if [ ! -e "${_usEr}/static/control/unlock.info" ] \
        && [ ! -e "${_Plr}/skip.info" ]; then
        ### -h: these three dirs are 02775 group 'users' (see the find below),
        ### so every glob hit is a tenant-plantable name and chown -R follows
        ### a symlink given as its starting point. Same shape as the files leg.
        chown -h -R ${_HM_U}:${_grp} \
          ${_Dir}/{modules,themes,libraries}/* &> /dev/null
      elif [ -e "${_usEr}/static/control/unlock.info" ] \
        && [ ! -e "${_Plr}/skip.info" ]; then
        chown -h -R ${_HM_U}.ftp:${_grp} \
          ${_Dir}/{modules,themes,libraries}/* &> /dev/null
      fi
    fi
    ### -h: all four are names in a site dir the tenant owns under
    ### unlock.info; the glob legs above are withheld on a symlinked code dir
    ### and -h keeps these on the names themselves, so nothing here expands
    ### through a link. None is ever legitimately a symlink.
    chown -h ${_HM_U}:${_grp} \
      ${_Dir}/drushrc.php \
      ${_Dir}/{modules,themes,libraries} &> /dev/null
    find ${_Dir}/{modules,themes,libraries} -type d -exec \
      chmod 02775 {} \; &> /dev/null
    find ${_Dir}/{modules,themes,libraries} -type f -exec \
      chmod 0664 {} \; &> /dev/null
    ### files - site level
    ### -h replaces the prior -L: prevents recursive chown from dereferencing
    ### attacker-planted symlinks under _Dir/files (the realistic threat is
    ### a tar archive uploaded by a tenant containing an inner symlink, since
    ### Adam confirmed in category 1 that PHP cannot create symlinks directly
    ### but tar extraction can carry them in). Combined with the
    ### _validate_safe_dir gate above this closes the path-prefix and
    ### per-child symlink attack surfaces.
    chown -h -R ${_HM_U}:www-data ${_Dir}/files &> /dev/null
    ### The trailing slash below is load-bearing -- files/ is legitimately a
    ### symlink into a per-account static store (a shared store may sit under
    ### another account), so find MUST resolve it -- but sites/ is 02771 and
    ### the store 02775, both group 'users', so the link and the name above it
    ### are plantable and these four ops would otherwise walk root's
    ### chmod/chown into whatever was planted (files -> /etc hands every
    ### tenant a writable /etc). Resolve once and act on the canonical path,
    ### and only while it is still a store or a real child of the site dir.
    _rDir=$(realpath -e -- "${_Dir}" 2>/dev/null)
    _rFls=$(realpath -e -- "${_Dir}/files" 2>/dev/null)
    if [ -n "${_rDir}" ] && [ -n "${_rFls}" ]; then
      case "${_rFls}/" in
        */static/files/*|"${_rDir}"/*)
          find "${_rFls}/" -type d -exec chmod 02775 {} \; &> /dev/null
          find "${_rFls}/" -type f -exec chmod 0664 {} \; &> /dev/null
          chmod 02775 "${_rFls}" &> /dev/null
          chown ${_HM_U}:www-data "${_rFls}" &> /dev/null
          ### These names sit inside the tenant-writable files dir, so any of
          ### them can be a planted symlink; -h keeps the chown on the link
          ### instead of its target and is a no-op on the regular directories
          ### they normally are. Spelled against the resolved store, inside
          ### this arm only: on the raw path they would still walk root
          ### through a planted files link the case above just refused.
          chown -h ${_HM_U}:www-data "${_rFls}"/{tmp,images,pictures,css,js} &> /dev/null
          chown -h ${_HM_U}:www-data "${_rFls}"/{advagg_css,advagg_js,ctools} &> /dev/null
          chown -h ${_HM_U}:www-data "${_rFls}"/{ctools/css,imagecache,locations} &> /dev/null
          chown -h ${_HM_U}:www-data "${_rFls}"/{xmlsitemap,deployment,styles,private} &> /dev/null
          chown -h ${_HM_U}:www-data "${_rFls}"/{civicrm,civicrm/templates_c} &> /dev/null
          chown -h ${_HM_U}:www-data "${_rFls}"/{civicrm/upload,civicrm/persist} &> /dev/null
          chown -h ${_HM_U}:www-data "${_rFls}"/{civicrm/custom,civicrm/dynamic} &> /dev/null
          ;;
        *)
          echo "SKIP: ${_Dir}/files resolves outside any static store: ${_rFls}"
          ;;
      esac
    fi
    ### private - site level
    chown -h -R ${_HM_U}:www-data ${_Dir}/private &> /dev/null
    ### Same trailing-slash resolution as the files/ leg above, same reason and
    ### same guard: private/ is legitimately a store symlink, so resolve it
    ### once and only walk a canonical target that is still a store or a real
    ### child of the site dir.
    _rDir=$(realpath -e -- "${_Dir}" 2>/dev/null)
    _rPrv=$(realpath -e -- "${_Dir}/private" 2>/dev/null)
    if [ -n "${_rDir}" ] && [ -n "${_rPrv}" ]; then
      case "${_rPrv}/" in
        */static/files/*|"${_rDir}"/*)
          find "${_rPrv}/" -type d -exec chmod 02775 {} \; &> /dev/null
          find "${_rPrv}/" -type f -exec chmod 0664 {} \; &> /dev/null
          chown ${_HM_U}:www-data "${_rPrv}" &> /dev/null
          ### Same as the files leg: the child entries only on the resolved
          ### store, inside the accepted arm, never on the raw path.
          chown -h ${_HM_U}:www-data "${_rPrv}"/{files,temp} &> /dev/null
          chown -h ${_HM_U}:www-data "${_rPrv}"/files/backup_migrate &> /dev/null
          chown -h ${_HM_U}:www-data "${_rPrv}"/files/backup_migrate/{manual,scheduled} &> /dev/null
          chown -h -R ${_HM_U}:www-data "${_rPrv}"/config &> /dev/null
          ;;
        *)
          echo "SKIP: ${_Dir}/private resolves outside any static store: ${_rPrv}"
          ;;
      esac
    fi
    ### drushrc.php is never legitimately a symlink, and the site dir is the
    ### tenant's under unlock.info: it is read once inside the resolved site
    ### dir, bounded and never through a link or a FIFO, and the missing line
    ### is added as a fresh file with its own owner and mode
    ### (_acct_add_same_here), never by ">>" on a name that can be swapped.
    ### Anything but a regular file is left alone, as the link refusal was.
    if _drTxt=$(_site_in_resolved_dir "${_Dir}" _acct_read_plain_here drushrc.php); then
      _DB_HOST_PRESENT=$(grep "^\$_SERVER\['db_host'\] = \$options\['db_host'\];" \
        <<< "${_drTxt}" 2>&1)
      if [[ "${_DB_HOST_PRESENT}" =~ "db_host" ]]; then
        if [ "${_FORCE_SITES_VERIFY}" = "YES" ]; then
          _run_drush8_hmr_cmd "hosting-task @${_Dom} verify --force"
        fi
      else
        _site_in_resolved_dir "${_Dir}" _acct_add_same_here drushrc.php \
          "\$_SERVER['db_host'] = \$options['db_host'];"
        _run_drush8_hmr_cmd "hosting-task @${_Dom} verify --force"
      fi
    fi
  ### Neither a Grav capsule nor a Textpattern site has a site-level files/
  ### store (a TXP site does have private/, its credential store), so the
  ### Drupal-shaped test above skips them and they get no nightly hygiene
  ### at all -- while FPM keeps writing into them as the per-version web user.
  ### Detect both positively (same predicates the two helpers use) and hand the
  ### site to the helpers: they own the per-CMS model, this leg only re-homes
  ### the tree to the account and its groups. Same symlink refusal as above.
  elif [ -e "${_Dir}" ] \
    && [ ! -L "${_Dir}" ] \
    && [ -e "${_Dir}/drushrc.php" ] \
    && [ ! -f "${_Dir}/settings.php" ] \
    && { { [ -f "${_Dir}/bin/grav" ] \
        && [ -f "${_Dir}/system/defines.php" ]; } \
      || { [ -f "${_Dir}/public/index.php" ] \
        && [ -f "${_Dir}/public/css.php" ] \
        && [ -d "${_Dir}/admin" ]; }; }; then
    ### No control-INI dir here: a Grav or Textpattern site carries no BOA
    ### control INI, and the per-site loop
    ### clears what an earlier release seeded.
    if [ -x "/usr/local/bin/fix-drupal-site-ownership.sh" ]; then
      /usr/local/bin/fix-drupal-site-ownership.sh \
        --site-path="${_Dir}" \
        --script-user="${_HM_U}" \
        --web-group=www-data &> /dev/null
    fi
    if [ -x "/usr/local/bin/fix-drupal-site-permissions.sh" ]; then
      /usr/local/bin/fix-drupal-site-permissions.sh \
        --site-path="${_Dir}" &> /dev/null
    fi
    echo "Foreign-CMS site hygiene applied for ${_Dom}"
  fi
}

_convert_controls_orig() {
  if [ -e "${_CTRL_DIR}/$1.info" ] \
    || [ -e "${_usEr}/static/control/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      _reseed_ctrl_ini "${_CTRL_F_TPL}" "${_CTRL_F}"
    fi
    _ctrl_ini_sed "${_CTRL_F}" "s/.*$1.*/$1 = TRUE/g" &> /dev/null
    _acct_in_resolved_dir "${_CTRL_DIR}" rm -f -- "./$1.info"
  fi
}

_convert_controls_orig_no_global() {
  if [ -e "${_CTRL_DIR}/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      _reseed_ctrl_ini "${_CTRL_F_TPL}" "${_CTRL_F}"
    fi
    _ctrl_ini_sed "${_CTRL_F}" "s/.*$1.*/$1 = TRUE/g" &> /dev/null
    _acct_in_resolved_dir "${_CTRL_DIR}" rm -f -- "./$1.info"
  fi
}

_convert_controls_value() {
  if [ -e "${_CTRL_DIR}/$1.info" ] \
    || [ -e "${_usEr}/static/control/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      _reseed_ctrl_ini "${_CTRL_F_TPL}" "${_CTRL_F}"
    fi
    if [ "$1" = "nginx_cache_day" ]; then
      _TTL=86400
    elif [ "$1" = "nginx_cache_hour" ]; then
      _TTL=3600
    elif [ "$1" = "nginx_cache_quarter" ]; then
      _TTL=900
    fi
    _ctrl_ini_sed "${_CTRL_F}" \
      "s/.*speed_booster_anon.*/speed_booster_anon_cache_ttl = ${_TTL}/g" &> /dev/null
    _acct_in_resolved_dir "${_CTRL_DIR}" rm -f -- "./$1.info"
  fi
}

_convert_controls_renamed() {
  if [ -e "${_CTRL_DIR}/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      _reseed_ctrl_ini "${_CTRL_F_TPL}" "${_CTRL_F}"
    fi
    if [ "$1" = "cookie_domain" ]; then
      _ctrl_ini_sed "${_CTRL_F}" \
        "s/.*server_name_cookie.*/server_name_cookie_domain = TRUE/g" &> /dev/null
    fi
    _acct_in_resolved_dir "${_CTRL_DIR}" rm -f -- "./$1.info"
  fi
}

_fix_control_settings() {
  _CTRL_NAME_ORIG="redis_lock_enable \
    redis_cache_disable \
    disable_admin_dos_protection \
    allow_anon_node_add \
    allow_private_file_downloads"
  _CTRL_NAME_VALUE="nginx_cache_day \
    nginx_cache_hour \
    nginx_cache_quarter"
  _CTRL_NAME_RENAMED="cookie_domain"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    _convert_controls_orig "$ctrl"
  done
  for ctrl in ${_CTRL_NAME_VALUE}; do
    _convert_controls_value "$ctrl"
  done
  for ctrl in ${_CTRL_NAME_RENAMED}; do
    _convert_controls_renamed "$ctrl"
  done
}

_fix_platform_system_control_settings() {
  _CTRL_NAME_ORIG="enable_user_register_protection \
     entitycache_dont_enable \
     views_cache_bully_dont_enable \
     views_content_cache_dont_enable"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    _convert_controls_orig "$ctrl"
  done
}

_fix_site_system_control_settings() {
  _CTRL_NAME_ORIG="disable_user_register_protection"
  for ctrl in ${_CTRL_NAME_ORIG}; do
    _convert_controls_orig_no_global "$ctrl"
  done
}

### The five passes sed -i made, in order, as one in-memory edit of the INI
### (_ctrl_ini_sed): -e expressions run in sequence on every line, and a line
### the fourth deletes never reaches the fifth, as with separate passes.
_cleanup_ini() {
  if [ -e "${_CTRL_F}" ]; then
    _ctrl_ini_sed "${_CTRL_F}" \
      -e "s/^;;.*//g" \
      -e "s/^ .*//g" \
      -e "s/^#.*//g" \
      -e "/^$/d" \
      -e "s/^\[/\n\[/g" &> /dev/null
  fi
}

_add_note_platform_ini() {
  if [ -e "${_CTRL_F}" ]; then
    ### One in-memory append (_ctrl_ini_add), never ">>" on the INI name.
    _ctrl_ini_add "${_CTRL_F}" "$(printf '%s\n' \
      "" \
      ";;" \
      ";;  This is a platform level ACTIVE INI file which can be used to modify" \
      ";;  default BOA system behaviour for all sites hosted on this platform." \
      ";;" \
      ";;  Please review complete documentation included in this file TEMPLATE:" \
      ";;  default.boa_platform_control.ini, since this ACTIVE INI file" \
      ";;  may not include all options available after upgrade to BOA-${_xSrl}" \
      ";;" \
      ";;  Note that BOA reads this file on every request, so a change applies on" \
      ";;  the next one; a page the front cache holds for anonymous visitors can" \
      ";;  hide it for a few seconds. A .dev. alias cuts that cache to 1 second." \
      ";;")"
  fi
}

_add_note_site_ini() {
  if [ -e "${_CTRL_F}" ]; then
    ### One in-memory append (_ctrl_ini_add), never ">>" on the INI name.
    _ctrl_ini_add "${_CTRL_F}" "$(printf '%s\n' \
      "" \
      ";;" \
      ";;  This is a site level ACTIVE INI file which can be used to modify" \
      ";;  default BOA system behaviour for this site only." \
      ";;" \
      ";;  Please review complete documentation included in this file TEMPLATE:" \
      ";;  default.boa_site_control.ini, since this ACTIVE INI file" \
      ";;  may not include all options available after upgrade to BOA-${_xSrl}" \
      ";;" \
      ";;  Note that BOA reads this file on every request, so a change applies on" \
      ";;  the next one; a page the front cache holds for anonymous visitors can" \
      ";;  hide it for a few seconds. A .dev. alias cuts that cache to 1 second." \
      ";;")"
  fi
}

_fix_platform_control_files() {
  if [ -e "/data/conf/default.boa_platform_control.ini" ]; then
    ### Both names live in the tenant-writable setgid sites/all/modules dir.
    ### The legs below edit the INI only through _ctrl_ini_sed/_ctrl_ini_add
    ### (never through a link or a FIFO at the name); the re-strip lets the
    ### seed legs recreate a planted name.
    _desymlink_planted \
      "${_Plr}/sites/all/modules/default.boa_platform_control.ini" \
      "${_Plr}/sites/all/modules/boa_platform_control.ini"
    if [ ! -e "${_Plr}/sites/all/modules/default.boa_platform_control.ini" ] \
      || [ "${_CTRL_TPL_FORCE_UPDATE}" = "YES" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini \
        "${_Plr}/sites/all/modules/default.boa_platform_control.ini"
    fi
    _CTRL_F_TPL="${_Plr}/sites/all/modules/default.boa_platform_control.ini"
    _CTRL_F="${_Plr}/sites/all/modules/boa_platform_control.ini"
    _CTRL_DIR="${_Plr}/sites/all/modules"
    _fix_control_settings
    _fix_platform_system_control_settings
    _cleanup_ini
    _add_note_platform_ini
  fi
}

_fix_site_control_files() {
  if [ -e "/data/conf/default.boa_site_control.ini" ]; then
    ### The strip at the head of the iteration is a full _fix_modules pass, an
    ### LE renewal (sleep 30) and a goaccess run old by the time this is
    ### called, and both names live in the tenant-writable setgid modules dir.
    ### The legs below edit the INI only through _ctrl_ini_sed/_ctrl_ini_add;
    ### the re-strip lets the seed legs recreate a planted name.
    _desymlink_planted \
      "${_Dir}/modules/default.boa_site_control.ini" \
      "${_Dir}/modules/boa_site_control.ini"
    if [ ! -e "${_Dir}/modules/default.boa_site_control.ini" ] \
      || [ "${_CTRL_TPL_FORCE_UPDATE}" = "YES" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_site_control.ini \
        "${_Dir}/modules/default.boa_site_control.ini"
    fi
    _CTRL_F_TPL="${_Dir}/modules/default.boa_site_control.ini"
    _CTRL_F="${_Dir}/modules/boa_site_control.ini"
    _CTRL_DIR="${_Dir}/modules"
    _fix_control_settings
    _fix_site_system_control_settings
    _cleanup_ini
    _add_note_site_ini
  fi
}

### The nightly http2/quic fix-up of the vhost ./$1 in the current (pinned)
### vhost.d: the same tests and the same sed programs sed -i ran, one after
### another, on a bounded no-follow read of the file, put back as
### _acct_put_same_here puts it (its owner and mode kept). A link or a FIFO
### at the name is left alone.
_vhost_http_fix_here() {
  local _v _fixHttpReqired=NO
  _v=$(_acct_read_plain_here "${1}" && echo x) || return 0
  _v="${_v%x}"
  if grep -q -e "ssl http2" <<< "${_v}"; then
    _fixHttpReqired=YES
  elif grep -q -E '^\s*listen[^;]*443[^;]*ssl' <<< "${_v}" \
    && ! grep -q -E '^\s*http2\s+on;$' <<< "${_v}"; then
    # Only a TLS-terminating vhost needs 'http2 on;'. Without this test a
    # plain :80 vhost never satisfied the check, so it was rewritten (and
    # its mtime refreshed) every single night for no change at all.
    _fixHttpReqired=YES
  elif grep -q -E '^\s+listen.*443\s+quic;$' <<< "${_v}"; then
    _fixHttpReqired=YES
  fi
  [ "${_fixHttpReqired}" = "YES" ] || return 0
  echo "FIXING vhost for ${_Dom}"
  # Remove 'http2' from 'listen' directives, existing 'http2 on;' lines,
  # 'quic' lines and unwanted directives (all with varying spaces), then
  # update 'ssl_prefer_server_ciphers' and 'http3_hq'
  _v=$(printf '%s' "${_v}" \
    | sed -E 's/(listen\s+[^;]*\s+ssl)\s+http2;$/\1;/' \
    | sed -E '/^\s*http2\s+on;/d' \
    | sed -E '/^\s+listen.*443\s+quic;/d' \
    | sed -E \
      -e '/^\s*ssl_stapling\b/d' \
      -e '/^\s*ssl_stapling_verify\b/d' \
      -e '/^\s*resolver\b/d' \
      -e '/^\s*resolver_timeout\b/d' \
    | sed -E 's/^\s*ssl_prefer_server_ciphers\s+.*$/ssl_prefer_server_ciphers on;/' \
    | sed -E 's/http3_hq\s+on;$/http3_hq on;/'; echo x)
  _v="${_v%x}"
  if grep -q 'ssl_prefer_server_ciphers' <<< "${_v}"; then
    # Add 'http2 on;' after 'ssl_prefer_server_ciphers on;', only if not already present
    if ! grep -q -E '^\s*http2\s+on;$' <<< "${_v}"; then
      _v=$(printf '%s' "${_v}" | sed '/ssl_prefer_server_ciphers on;/ a\  http2 on;'; echo x)
      _v="${_v%x}"
    fi
  elif grep -q -E '^\s*#?http3_hq\s+on;$' <<< "${_v}"; then
    # Add 'http2 on;' after 'http3_hq on;', only if not already present
    if ! grep -q -E '^\s*http2\s+on;$' <<< "${_v}"; then
      _v=$(printf '%s' "${_v}" | sed '/http3_hq on;/ a\  http2 on;'; echo x)
      _v="${_v%x}"
    fi
  fi
  _acct_put_same_here "${1}" "${_v}"
}

_cleanup_ghost_vhosts() {
  _provision_running && return
  ### config/ and .drush/ are oN's: the vhost list is taken, each vhost read
  ### and fixed, and every move into undo/ made only inside the real
  ### directories (_acct_in_real_dir, _acct_undo_here).
  local _vhD="${_usEr}/config/server_master/nginx/vhost.d"
  for _Site in `_acct_in_real_dir "${_vhD}" find . -maxdepth 1 \
    -mindepth 1 -type f | sort`; do
    _Site="${_vhD}/${_Site#./}"
    _Dom=$(echo ${_Site} | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    # Skip leading-dot companion vhosts (.example.com): intentional staged /
    # preserved rollback originals from proxy-conversion (xoct) and export/import
    # (xcopy) that never have a matching .example.com alias -- reaping them would
    # destroy the rollback or kill an about-to-activate import.
    case "${_Dom}" in .*) continue ;; esac
    # Never reap while a migrate/export of this account is in flight.
    [ -e "${_usEr}/log/exported.pid" ] && continue
    _gh_vmark="${_usEr}/log/ctrl/ghost-vhost-${_Dom}.seen"
    _gh_amark="${_usEr}/log/ctrl/ghost-vhost-noalias-${_Dom}.seen"
    # Freshness is sampled ONCE, here, before this run's own vhost rewrites
    # further down touch the file. BOA rewrites vhosts every night (the http2 /
    # quic fixes below, and the forward-secrecy TLS pass in 90-global-post.sh),
    # so a mtime read after that point always looks fresh, which reset the
    # consecutive-run counters on every run and left the reap permanently
    # unarmed -- while the log blamed the opt-in flag instead.
    _gh_vfresh=NO
    [ -n "$(_acct_in_real_dir "${_vhD}" find "./${_Dom}" -maxdepth 0 \
      -mmin -1440 2>/dev/null)" ] && _gh_vfresh=YES
    # Resolved once per vhost so the reason reported below is the real one.
    _gh_vflag=NO
    if _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_VHOSTS_CLEANUP \
      || _cnf_flag_yes /root/.barracuda.cnf _GHOST_VHOSTS_CLEANUP; then
      _gh_vflag=YES
    fi
    if [[ "${_Dom}" =~ ".restore"($) ]]; then
      if [ "${_gh_vfresh}" = "YES" ]; then
        # Freshly written = a restore still in flight; give it a grace run.
        _ghost_seen_reset "${_gh_vmark}"
      else
        _gh_vseen=NO
        _ghost_seen_enough "${_gh_vmark}" && _gh_vseen=YES
        if [ "${_gh_vseen}" = "YES" ] && [ "${_gh_vflag}" = "YES" ]; then
          _acct_in_real_dir "${_usEr}/.drush" \
            _acct_undo_here "${_Dom}.alias.drushrc.php" &> /dev/null
          _acct_in_real_dir "${_vhD}" _acct_undo_here "${_Dom}" &> /dev/null
          _ghost_seen_reset "${_gh_vmark}"
          _ghost_seen_reset "${_gh_amark}"
          echo "GHOST vhost for ${_Dom} detected and moved to ${_usEr}/undo/"
        elif [ "${_gh_vflag}" = "YES" ]; then
          echo "GHOST vhost for ${_Dom} detected (grace; moves on the next consecutive run)"
        else
          echo "GHOST vhost for ${_Dom} detected (dry-run; set _GHOST_VHOSTS_CLEANUP=YES to move)"
        fi
      fi
    fi
    if [ -e "${_vhD}/${_Dom}" ]; then
      _acct_in_real_dir "${_vhD}" _vhost_http_fix_here "${_Dom}"
      _Plx=$(_acct_read_in "${_vhD}" "${_Dom}" \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "${_Plx}" =~ "aegir/distro" ]] \
        || [[ "${_Dom}" =~ (^)"https." ]] \
        || [[ "${_Dom}" =~ "--CDN"($) ]] \
        || [ -z "${_Plx}" ]; then
        _SKIP_VHOST=YES
      else
        if [ ! -e "${_usEr}/.drush/${_Dom}.alias.drushrc.php" ]; then
          # No matching site alias. Skip a freshly written/staged vhost (mtime
          # < 24h = mid-import/activation, sampled at the top of this iteration
          # before our own fixes rewrote it), require the no-alias state across
          # consecutive nights, then gate on the opt-in flag. Own counter, so
          # this test and the .restore test above never reset or double-count
          # each other through a shared marker.
          if [ "${_gh_vfresh}" = "YES" ]; then
            _ghost_seen_reset "${_gh_amark}"
          else
            _gh_aseen=NO
            _ghost_seen_enough "${_gh_amark}" && _gh_aseen=YES
            if [ "${_gh_aseen}" = "YES" ] && [ "${_gh_vflag}" = "YES" ]; then
              _acct_in_real_dir "${_vhD}" _acct_undo_here "${_Dom}" &> /dev/null
              _ghost_seen_reset "${_gh_amark}"
              echo "GHOST vhost for ${_Dom} with no drushrc detected and moved to ${_usEr}/undo/"
            elif [ "${_gh_vflag}" = "YES" ]; then
              echo "GHOST vhost for ${_Dom} with no drushrc detected (grace; moves on the next consecutive run)"
            else
              echo "GHOST vhost for ${_Dom} with no drushrc detected (dry-run; set _GHOST_VHOSTS_CLEANUP=YES to move)"
            fi
          fi
        else
          _ghost_seen_reset "${_gh_amark}"
        fi
      fi
    fi
  done
}

_cleanup_ghost_drushrc() {
  _provision_running && return
  ### .drush/, config/ and log/ are oN's: the alias list is taken, each alias
  ### read, the arming marker kept, and every move into undo/ made only
  ### inside the real directories (_acct_in_real_dir, _acct_undo_here); a
  ### platform or site tree moves from inside its resolved parent.
  local _drD="${_usEr}/.drush" _alTxt
  # Sites-reap enablement is resolved once per account, and every OFF->ON flip
  # only ARMS on its first enabled run (nothing moved): the consecutive-night
  # ghost counters keep counting during dry-run, so a flip would otherwise
  # reap every long-accumulated ghost at once with no fresh enabled-mode look.
  _GH_REAP_ON=NO
  if _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_SITES_CLEANUP \
    || _cnf_flag_yes /root/.barracuda.cnf _GHOST_SITES_CLEANUP; then
    if [ -e "${_usEr}/log/ctrl/ghost-reap-armed.info" ]; then
      _GH_REAP_ON=YES
    else
      _log_ctrl_mark ghost-reap-armed.info
      echo "GHOST sites cleanup enabled -- arming run for ${_HM_U}, nothing moved tonight"
    fi
  else
    _acct_in_real_dir "${_usEr}/log/ctrl" rm -f -- ./ghost-reap-armed.info
  fi
  for _thisAlias in `_acct_in_real_dir "${_drD}" find . -maxdepth 1 -mindepth 1 \
    -type f -name '*.alias.drushrc.php' ! -name '.*' | sort`; do
    _thisAlias="${_drD}/${_thisAlias#./}"
    _alTxt=$(_acct_read_in "${_drD}" "${_thisAlias##*/}")
    _aliasName=$(echo "${_thisAlias}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
    _aliasName=$(echo "${_aliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [[ "${_aliasName}" =~ (^)"server_" ]] \
      || [[ "${_aliasName}" =~ (^)"hostmaster" ]]; then
      _IS_SITE=NO
    elif [[ "${_aliasName}" =~ (^)"platform_" ]]; then
      _Plm=$(printf '%s\n' "${_alTxt}" \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _gh_pmark="${_usEr}/log/ctrl/ghost-drushrc-platform-${_aliasName}.seen"
      # _Plm is parsed from a Drush alias exactly like _Dir/_Plr in the per-site
      # loop, but reaches an unconditional root "mv -f" -- so it needs the same
      # anchor those get: a real dir, not a symlink, resolving under THIS
      # account root. Refuse the platform rather than move an unknown path.
      if [ -d "${_Plm}" ] && ! _validate_loop_dir "${_Plm}"; then
        echo "SKIP: platform root symlinked or outside ${_usEr}: ${_Plm}"
      elif [ -d "${_Plm}" ]; then
        # Version-agnostic: a real docroot or a vendor/ tree = live platform.
        if [ -n "$(_detect_real_docroot "${_Plm}")" ] || [ -e "${_Plm}/vendor" ]; then
          _ghost_seen_reset "${_gh_pmark}"
        elif _ghost_seen_enough "${_gh_pmark}" \
          && { _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_PLATFORMS_CLEANUP \
            || _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; }; then
          _acct_undo_tree "${_Plm}" &> /dev/null
          _acct_in_real_dir "${_drD}" _acct_undo_here "${_thisAlias##*/}" &> /dev/null
          echo "GHOST broken platform ${_Plm} + alias detected and moved to ${_usEr}/undo/"
        else
          echo "GHOST broken platform ${_Plm} detected (dry-run/grace; set _GHOST_PLATFORMS_CLEANUP=YES to move)"
        fi
      else
        if _ghost_seen_enough "${_gh_pmark}" \
          && { _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_PLATFORMS_CLEANUP \
            || _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; }; then
          _acct_in_real_dir "${_drD}" _acct_undo_here "${_thisAlias##*/}" &> /dev/null
          echo "GHOST nodir platform alias ${_thisAlias} detected and moved to ${_usEr}/undo/"
        else
          echo "GHOST nodir platform alias ${_thisAlias} detected (dry-run/grace; set _GHOST_PLATFORMS_CLEANUP=YES to move)"
        fi
      fi
    else
      _T_SITE_NAME="${_aliasName}"
      _gh_smark="${_usEr}/log/ctrl/ghost-site-${_T_SITE_NAME}.seen"
      if [[ "${_T_SITE_NAME}" =~ ".restore"($) ]]; then
        _IS_SITE=NO
        # .restore leftover: move only the alias (never the vhost, matching the
        # authoritative ltd-user handling), gated + persisted.
        if _ghost_seen_enough "${_gh_smark}" \
          && [ "${_GH_REAP_ON}" = "YES" ]; then
          _acct_in_real_dir "${_drD}" \
            _acct_undo_here "${_T_SITE_NAME}.alias.drushrc.php" &> /dev/null
          echo "GHOST .restore alias ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
        else
          echo "GHOST .restore alias ${_T_SITE_NAME} detected (dry-run/grace; set _GHOST_SITES_CLEANUP=YES to move)"
        fi
      else
        _T_SITE_FDIR=$(printf '%s\n' "${_alTxt}" \
          | grep "site_path'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
        # Fail closed: a degraded/mid-rewrite alias parses to an empty or
        # non-/data/disk site_path -> KEEP, never reap on a bad parse. The
        # prefix test is TEXTUAL, so ".." components pass it and still reach
        # the mkdir and the "mv -f" below; anchor on the resolved path under
        # this account root too. An absent path still passes -- that is the
        # true-ghost case this branch exists to reap.
        if [ -z "${_T_SITE_FDIR}" ] \
          || [ "${_T_SITE_FDIR}" = "${_T_SITE_FDIR#/data/disk/}" ] \
          || ! _validate_loop_dir "${_T_SITE_FDIR}"; then
          _IS_SITE=YES
          _ghost_seen_reset "${_gh_smark}"
        elif [ -e "${_T_SITE_FDIR}/drushrc.php" ] \
          || [ -L "${_T_SITE_FDIR}/drushrc.php" ]; then
          # drushrc.php present = a registered, live site. Do NOT also require
          # files/private: under native files-symlinking those are symlinks into
          # the static store whose target can be transiently absent (unmounted,
          # mid-repoint), so a present settings file alone keeps the site.
          if [ ! -e "${_T_SITE_FDIR}/modules" ] \
            && ! _is_foreign_cms_root "${_T_SITE_FDIR%/sites/*}"; then
            _acct_in_resolved_dir "${_T_SITE_FDIR}" mkdir ./modules
          fi
          _IS_SITE=YES
          _ghost_seen_reset "${_gh_smark}"
        else
          # drushrc.php absent = ghost candidate. Require persistence across
          # consecutive nights, then split flags: registration (alias + vhost)
          # under _GHOST_SITES_CLEANUP; the site files dir under the stricter
          # _GHOST_SITE_FILES_CLEANUP (data, not registration).
          # Classify BEFORE any move. An aegir/distro site_path (FRONT-END) is
          # the account's control panel or its hm/oN.<host> alias companions --
          # a stale one (hostname rename, distro version bump) is system
          # machinery, never a customer leftover, so it must neither be reaped
          # nor ever generate a client notice. A missing platform root
          # (PLATFORM GONE) or a site dir found on another platform of this
          # account (MIGRATE STRANDED) is a platform-level event where the
          # data may be intact elsewhere -- reaping would take every such
          # site's registration (and vhost) down at once. All three are left
          # for operator review; only a true per-site ghost (platform healthy,
          # site dir nowhere) is ever reaped. The root parses are anchored to
          # the 'root' KEY so a value that merely ends in root (e.g.
          # client_name 'root') can never pollute them.
          _GH_CLASS=ghost
          if [[ "${_T_SITE_FDIR}" =~ "aegir/distro" ]]; then
            _GH_CLASS=front-end
          else
            _T_SITE_ROOT=$(printf '%s\n' "${_alTxt}" \
              | grep "'root' =>" \
              | cut -d: -f2 \
              | awk '{ print $3}' \
              | sed "s/[\,']//g" 2>&1)
            if [ -n "${_T_SITE_ROOT}" ] && [ ! -d "${_T_SITE_ROOT}" ]; then
              _GH_CLASS=platform-gone
            else
              # A platform alias keeps the path the platform was registered
              # with, which for a Composer build can be its app root; its site
              # dirs live under the docroot Provision serves. Compare and probe
              # docroots, or a site stranded on such a platform reads as a ghost.
              _GH_SDOC=$(_detect_real_docroot "${_T_SITE_ROOT}") \
                || _GH_SDOC="${_T_SITE_ROOT}"
              for _GH_PALIAS in `_acct_in_real_dir "${_drD}" \
                compgen -G './platform_*.alias.drushrc.php'`; do
                _GH_PROOT=$(_acct_read_in "${_drD}" "${_GH_PALIAS#./}" \
                  | grep "'root' =>" \
                  | cut -d: -f2 \
                  | awk '{ print $3}' \
                  | sed "s/[\,']//g" 2>&1)
                _GH_PDOC=$(_detect_real_docroot "${_GH_PROOT}") \
                  || _GH_PDOC="${_GH_PROOT}"
                if [ -n "${_GH_PDOC}" ] \
                  && [ "${_GH_PDOC}" != "${_GH_SDOC}" ] \
                  && [ -d "${_GH_PDOC}/sites/${_T_SITE_NAME}" ]; then
                  _GH_CLASS=stranded
                  break
                fi
              done
            fi
          fi
          if ! _ghost_seen_enough "${_gh_smark}"; then
            echo "GHOST drushrc for ${_T_SITE_NAME} detected (grace run, not moved)"
          elif [ "${_GH_CLASS}" != "ghost" ]; then
            echo "GHOST candidate ${_T_SITE_NAME} SKIPPED (${_GH_CLASS}: operator review needed, nothing moved)"
          else
            # Only a confirmed true ghost pays for the front-end lookup. YES
            # keeps the customer-facing line: the record is still in their
            # panel, so the client notice is accurate and actionable. NO (the
            # customer already deleted the node -- only backend leftovers
            # remain, which they cannot see or touch) and UNKNOWN both take
            # the backend-leftover line, which the client notice never
            # matches, so that cleanup stays silent.
            _GH_FE=$(_hmr_context_exists "${_T_SITE_NAME}")
            if [ "${_GH_FE}" = "YES" ]; then
              _GH_LINE="GHOST drushrc for ${_T_SITE_NAME}"
            elif [ "${_GH_FE}" = "NO" ]; then
              _GH_LINE="GHOST backend leftover for ${_T_SITE_NAME} (no front-end record)"
            else
              _GH_LINE="GHOST backend leftover for ${_T_SITE_NAME} (front-end check failed)"
            fi
            if [ "${_GH_REAP_ON}" = "YES" ]; then
              _acct_in_real_dir "${_drD}" \
                _acct_undo_here "${_T_SITE_NAME}.alias.drushrc.php" &> /dev/null
              echo "${_GH_LINE} detected and moved to ${_usEr}/undo/"
              if [[ ! "${_T_SITE_FDIR}" =~ "aegir/distro" ]]; then
                _acct_in_real_dir "${_usEr}/config/server_master/nginx/vhost.d" \
                  _acct_undo_here "${_T_SITE_NAME}" "ghost-vhost-${_T_SITE_NAME}" &> /dev/null
                echo "GHOST vhost for ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
              fi
              if [ -d "${_T_SITE_FDIR}" ] \
                && { _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_SITE_FILES_CLEANUP \
                  || _cnf_flag_yes /root/.barracuda.cnf _GHOST_SITE_FILES_CLEANUP; }; then
                _acct_undo_tree "${_T_SITE_FDIR}" "ghost-site-${_T_SITE_NAME}" &> /dev/null
                echo "GHOST site dir ${_T_SITE_FDIR} for ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
              fi
            else
              echo "${_GH_LINE} detected (dry-run; set _GHOST_SITES_CLEANUP=YES to move)"
            fi
          fi
        fi
      fi
    fi
  done
}

### chattr +i on the regular files ./$@ of the current (pinned) directory; a
### link or anything else at a name is left alone.
_chattr_plain_here() {
  local _f
  for _f in "$@"; do
    [ -f "./${_f}" ] && [ ! -L "./${_f}" ] && chattr +i "./${_f}"
  done
  return 0
}
### A Cloudflare DNS hook for dehydrated, cloned by root as tools/le/hooks/$1
### from the repository $2: only inside the real hooks/ (made first if
### missing) while it is root's own, so the account can swap nothing in it,
### and only while the clone dir is not there yet.
_le_hook_clone() {
  _acct_in_real_dir "${_usEr}/tools/le" mkdir -p ./hooks 2> /dev/null
  _acct_in_real_dir "${_usEr}/tools/le/hooks" _le_hook_clone_here "${1}" "${2}"
}
_le_hook_clone_here() {
  [ "$(stat -c '%u' . 2> /dev/null)" = "0" ] || return 1
  if [ -e "./${1}" ] || [ -L "./${1}" ]; then
    return 1
  fi
  git clone "${2}" "./${1}" 2> /dev/null
}
### In a hook clone this pass just made (the current, pinned directory): true
### only while the directory and ./$1 are root's own regular file, so nothing
### there can be swapped by the account between this test and root's use.
_le_hook_root_here() {
  [ "$(stat -c '%u' . 2> /dev/null)" = "0" ] \
    && [ -f "./${1}" ] && [ ! -L "./${1}" ] \
    && [ "$(stat -c '%u' -- "./${1}" 2> /dev/null)" = "0" ]
}
_le_hook_exec_here() {
  _le_hook_root_here "${1}" && chmod 755 "./${1}"
}
### The Python hook made executable, and its requirements installed by root's
### pip3 only from that root-owned clone.
_le_hook_py_here() {
  _le_hook_exec_here hook.py || return 1
  _le_hook_root_here requirements.txt \
    && pip3 install -r ./requirements.txt 2> /dev/null
}

_le_ssl_check_update() {
  ### Work on a local copy: the www strips below (wildcard mode) otherwise
  ### rewrite the caller's per-site loop variable, so every later leg of the
  ### iteration addresses @<stripped> -- an alias that does not exist for a
  ### www-prefixed site -- and _if_gen_goaccess loses its www variant.
  local _Dom="${_Dom}" _vhTxt
  _exeLe="${_usEr}/tools/le/dehydrated"
  _Vht="${_usEr}/config/server_master/nginx/vhost.d/${_Dom}"
  ### The immutable marker Provision honours on Verify must also stop this
  ### nightly leg: dehydrated decides on the leftover cert.pem, so once that
  ### cert has less than RENEW_DAYS runway it re-issues LE symlinks straight
  ### over the operator's custom PEM files. Checked before any www-strip --
  ### the marker is named after the site URI, like on the Verify side.
  if [ -e "${_usEr}/tools/le/.ctrl/dont-overwrite-${_Dom}.pid" ]; then
    echo "LE renewal skipped for ${_Dom} -- immutable dont-overwrite marker present"
    return 0
  fi
  if [ -x "${_exeLe}" ] && [ -e "${_Vht}" ]; then
    ### The vhost is oN's: read once, bounded and never through a link.
    _vhTxt=$(_acct_read_in "${_Vht%/*}" "${_Vht##*/}")
    _SSL_ON_TEST=$(printf '%s\n' "${_vhTxt}" | grep "443 ssl" 2>&1)
    if [[ "${_SSL_ON_TEST}" =~ "443 ssl" ]]; then
      if [ -e "${_usEr}/tools/le/certs/${_Dom}/fullchain.pem" ]; then
        echo "Running LE cert check directly for ${_Dom}"
        _usEaliases=""
        _siTealiases=`printf '%s\n' "${_vhTxt}" \
          | grep "server_name" \
          | sed "s/server_name//g; s/;//g" \
          | sort | uniq \
          | tr -d "\n" \
          | sed "s/  / /g; s/  / /g; s/  / /g" \
          | sort | uniq`
        for _aliAs in `echo "${_siTealiases}"`; do
          if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
            _Dom=$(echo ${_Dom} | sed 's/^www.//g' 2>&1)
            if [ -z "${_usEaliases}" ] \
              && [ ! -z "${_aliAs}" ] \
              && [[ ! "${_aliAs}" =~ ".nodns." ]] \
              && [[ ! "${_aliAs}" =~ "${_Dom}" ]]; then
              _usEaliases="--domain ${_aliAs}"
              echo "--domain ${_aliAs}"
            else
              if [ ! -z "${_aliAs}" ] \
                && [[ ! "${_aliAs}" =~ ".nodns." ]] \
                && [[ ! "${_aliAs}" =~ "${_Dom}" ]]; then
                _usEaliases="${_usEaliases} --domain ${_aliAs}"
                echo "--domain ${_aliAs}"
              fi
            fi
          else
            if [[ ! "${_aliAs}" =~ ".nodns." ]]; then
              echo "--domain ${_aliAs}"
              if [ -z "${_usEaliases}" ] && [ ! -z "${_aliAs}" ]; then
                _usEaliases="--domain ${_aliAs}"
              else
                if [ ! -z "${_aliAs}" ]; then
                  _usEaliases="${_usEaliases} --domain ${_aliAs}"
                fi
              fi
            else
              echo "ignored alias ${_aliAs}"
            fi
          fi
        done
        _DOM=$(date +%e)
        _DOM=${_DOM//[^0-9]/}
        _RDM=$((RANDOM%25+6))
        if [ "${_DOM}" = "${_RDM}" ] || [ -e "${_usEr}/static/control/force-ssl-certs-rebuild.info" ]; then
          if [ ! -e "${_usEr}/log/ctrl/site.${_Dom}.cert-x1-rebuilt.info" ]; then
            _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1' --force"
            _log_ctrl_mark "site.${_Dom}.cert-x1-rebuilt.info"
          else
            _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
          fi
        else
          _leParams="--cron --ipv4 --preferred-chain 'ISRG Root X1'"
        fi
        _dhArgs="--domain ${_Dom} ${_usEaliases}"
        if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
          _Dom=$(echo ${_Dom} | sed 's/^www.//g' 2>&1)
          echo "--domain *.${_Dom}"
          if [ -e "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ] \
            || [ -e "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ]; then
            ### static/control is owned by the tenant SHELL user and sits in a
            ### group-writable static/, so both the flag file and the control
            ### dir are names a tenant can swap for a symlink. chattr has no -h
            ### and follows, which would pin the immutable bit -- root-only to
            ### clear -- on an arbitrary target: lock the flags only inside the
            ### real static/control, and only while each is a regular file.
            ### Skip, never delete: these are the tenant's own opt-in flags,
            ### not root-maintained INIs.
            _acct_in_real_dir "${_usEr}/static/control" _chattr_plain_here \
              cloudflare-dns-ssl-py.info cloudflare-dns-ssl-sh.info
            export CF_DNS_SERVERS='8.8.8.8 8.8.4.4'
            export CF_SETTLE_TIME='30'
            export CF_DEBUG='true'
            ### An exit-status gate on the clone: the old form keyed only on
            ### "hook file absent", so a FAILED clone (no network, or a hooks
            ### dir that already exists) still reached the root pip3 install.
            ### tools/le is oN's, so the clone lands only in the real,
            ### root-owned hooks/, and the chmod and the pip3 install act only
            ### inside that root-owned clone (_le_hook_root_here): pip runs
            ### packaging code as root and may only ever see a tree this clone
            ### just created, never a name the account swapped in.
            if [ ! -e "${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh" ]; then
              _apt_clean_update
              apt-get install gawk jq publicsuffix ldnsutils ${_aptYesUnth} 2> /dev/null
              if _le_hook_clone cloudflare-sh \
                https://github.com/omega8cc/dehydrated-hook-cloudflare; then
                _acct_in_real_dir "${_usEr}/tools/le/hooks/cloudflare-sh" \
                  _le_hook_exec_here cf-hook.sh
              fi
            fi
            if [ ! -e "${_usEr}/tools/le/hooks/cloudflare-py/hook.py" ]; then
              _apt_clean_update
              apt-get install python3-pip python-is-python3 ${_aptYesUnth} 2> /dev/null
              if _le_hook_clone cloudflare-py \
                https://github.com/omega8cc/letsencrypt-cloudflare-hook; then
                _acct_in_real_dir "${_usEr}/tools/le/hooks/cloudflare-py" \
                  _le_hook_py_here
              fi
            fi
            if [ -e "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ]; then
              _thisHook="${_usEr}/tools/le/hooks/cloudflare-py/hook.py"
            elif [ -e "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ]; then
              _thisHook="${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh"
            fi
            if [ -e "${_thisHook}" ] && [ -e "${_usEr}/tools/le/config" ]; then
              _acct_in_real_dir "${_usEr}/tools/le" _chattr_plain_here config
              _dhArgs="--alias ${_Dom} --domain *.${_Dom} --domain ${_Dom} ${_usEaliases}"
              _dhArgs=" ${_dhArgs} --challenge dns-01 --hook '${_thisHook}'"
            fi
          else
            _dhArgs="--alias ${_Dom} --domain *.${_Dom} --domain ${_Dom} ${_usEaliases}"
          fi
        fi
        echo "_leParams is ${_leParams}"
        echo "_dhArgs is ${_dhArgs}"
        su -s /bin/bash - ${_HM_U} -c "${_exeLe} ${_leParams} ${_dhArgs}"
        wait
        if [ -e "${_usEr}/static/control/wildcard-enable-${_Dom}.info" ]; then
          sleep 30
        else
          sleep 3
        fi
        echo ${_MOMENT} >> /var/log/boa/le/${_Dom}
      fi
    fi
  fi
}

_daily_process() {
  ### config/, .drush/, log/ and .tmp/ are oN's: the vhost list is taken and
  ### every vhost and alias read only inside the real directory, bounded and
  ### never through a link or a FIFO (_acct_in_real_dir, _acct_read_in); the
  ### log/ctrl markers go through _log_ctrl_mark.
  local _vhD="${_usEr}/config/server_master/nginx/vhost.d" _vhTxt _alTxt _iniTxt
  _cleanup_ghost_vhosts
  _cleanup_ghost_drushrc
  for _Site in `_acct_in_real_dir "${_vhD}" find . \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
    _Site="${_vhD}/${_Site#./}"
    _MOMENT=$(date +%y%m%d-%H%M%S)
    echo ${_MOMENT} Start Counting Site ${_Site}
    _Dom=$(echo ${_Site} | cut -d'/' -f9 | awk '{ print $1}' 2>&1)
    _Dan=
    _Plx=
    _Plr=
    _Dir=
    _codeBaseCheckDir=
    _codeBaseCheckFile=
    _codeBaseCheckCtrl=
    _FOREIGN_CMS=NO
    _vhTxt=$(_acct_read_in "${_vhD}" "${_Dom}")
    if [ -e "${_vhD}/${_Dom}" ]; then
      _Plx=$(printf '%s\n' "${_vhTxt}" \
        | grep "root " \
        | cut -d: -f2 \
        | awk '{ print $2}' \
        | sed "s/[\;]//g" 2>&1)
      if [[ "${_Plx}" =~ "aegir/distro" ]]; then
        _Dan=hostmaster
      else
        _Dan="${_Dom}"
      fi
    fi
    _STATUS_DISABLED=NO
    _STATUS_TEST=$(grep "Do not reveal Aegir front-end URL here" \
      <<< "${_vhTxt}" 2>&1)
    if [[ "${_STATUS_TEST}" =~ "Do not reveal Aegir front-end URL here" ]]; then
      _STATUS_DISABLED=YES
      echo "${_Dom} site is DISABLED"
    fi
    if [ -e "${_usEr}/.drush/${_Dan}.alias.drushrc.php" ] \
      && [ "${_STATUS_DISABLED}" = "NO" ]; then
      echo "Dom is ${_Dom}"
      _alTxt=$(_acct_read_in "${_usEr}/.drush" "${_Dan}.alias.drushrc.php")
      _Dir=$(printf '%s\n' "${_alTxt}" \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _DIR_CTRL_F="${_Dir}/modules/boa_site_control.ini"
      _Plr=$(printf '%s\n' "${_alTxt}" \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _PLR_CTRL_F="${_Plr}/sites/all/modules/boa_platform_control.ini"
      # Skip the iteration if the alias-derived paths do not resolve under
      # an allowed BOA root. Guards against a compromised aegir-context user
      # rewriting the alias to redirect chown/chmod onto system paths.
      # _validate_safe_dir only bounds these to /data/disk, /var/aegir or
      # /home; it does NOT tie them to this account, and it resolves a planted
      # link rather than refusing it. Both names now sit in a group-writable
      # parent -- ~/static is 02775, and sites/ is 02771 on ~/static D8+
      # codebases since omega8cc/boa#1936 -- so a tenant can aim either at
      # another account or at /var/aegir and still pass. _validate_loop_dir
      # adds exactly the missing half: refuses a symlink, requires the
      # resolved path under ${_usEr} (or the shared platform store a legacy
      # instance may still host sites on).
      if [ -n "${_Dir}" ] \
        && { ! _validate_safe_dir "${_Dir}" || ! _validate_loop_dir "${_Dir}"; }; then
        echo "SKIP: _Dir not a plain dir under ${_usEr}: ${_Dir}"
        continue
      fi
      if [ -n "${_Plr}" ] \
        && { ! _validate_safe_dir "${_Plr}" || ! _validate_loop_dir "${_Plr}"; }; then
        echo "SKIP: _Plr not a plain dir under ${_usEr}: ${_Plr}"
        continue
      fi
      # The checks above validate the alias-derived roots, not the modules
      # dir the control INIs actually live in. That component sits in the
      # tenant-writable setgid tree, and the bare ">>" appends further down
      # follow a symlink planted there just as a rename does, so gate it
      # here too. Absent is allowed; a symlink, or a dir resolving outside
      # the account root, skips the iteration.
      if [ -n "${_Dir}" ] && ! _validate_ctrl_dir "${_Dir}/modules"; then
        echo "SKIP: not a plain dir under ${_usEr}: ${_Dir}/modules"
        continue
      fi
      if [ -n "${_Plr}" ] \
        && ! _validate_ctrl_dir "${_Plr}/sites/all/modules"; then
        echo "SKIP: not a plain dir under ${_usEr}: ${_Plr}/sites/all/modules"
        continue
      fi
      _desymlink_planted \
        "${_DIR_CTRL_F}" \
        "${_Dir}/modules/default.boa_site_control.ini" \
        "${_PLR_CTRL_F}" \
        "${_Plr}/sites/all/modules/default.boa_platform_control.ini"
      # Grav and Textpattern trees carry no BOA control INI: nothing reads one
      # there. Decide once, from the platform
      # root, AFTER the gates above -- a planted modules link skips a foreign
      # site's iteration exactly as it skips a Drupal one, which keeps every
      # later leg off that path -- and clear what an earlier release seeded.
      _FOREIGN_CMS=NO
      _is_foreign_cms_root "${_Plr}" && _FOREIGN_CMS=YES
      if [ "${_FOREIGN_CMS}" = "YES" ]; then
        if [ -n "${_Dir}" ] && [ ! -f "${_Dir}/settings.php" ]; then
          _heal_foreign_cms_ctrl_ini "${_Dir}/modules" boa_site_control.ini
        fi
        if [ ! -L "${_Plr}/sites" ] && [ ! -L "${_Plr}/sites/all" ]; then
          _heal_foreign_cms_ctrl_ini "${_Plr}/sites/all/modules" boa_platform_control.ini
          _heal_foreign_cms_ctrl_ini "${_Plr}/sites/all/themes" ""
          _heal_foreign_cms_ctrl_ini "${_Plr}/sites/all/libraries" ""
        fi
      fi
      if [ -e "${_Plr}" ]; then
        _PlrID=$(echo ${_Plr} \
          | openssl md5 \
          | awk '{ print $2}' \
          | tr -d "\n" 2>&1)
        if [ "${_ALLOW_CODEBASECHECK}" = "YES" ] \
          || [ -e "/etc/boa/.allow-codebasecheck.cnf" ]; then
          _codeBaseCheckDir="${_usEr}/log/ctrl"
          _codeBaseCheckFile="plr.${_PlrID}.codebasecheck-${_NOW}.info"
          _codeBaseCheckCtrl="${_codeBaseCheckDir}/${_codeBaseCheckFile}"
          _acct_in_real_dir "${_usEr}/log" mkdir -p ./ctrl 2> /dev/null
          if [ -x "/opt/local/bin/codebasecheck" ] \
            && [ -e "${_codeBaseCheckDir}" ] \
            && [ ! -e "${_codeBaseCheckCtrl}" ]; then
            codebasecheck "${_Plr}"
            wait
            _log_ctrl_mark "${_codeBaseCheckFile}"
          fi
        fi
        if [ "${_FOREIGN_CMS}" != "YES" ]; then
          _fix_platform_control_files
          _fix_o_contrib_symlink
        fi
        if [ -e "${_Dir}/drushrc.php" ]; then
          cd ${_Dir}
          if [ "${_Dan}" = "hostmaster" ]; then
            if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.hm-fix-${_NOW}.info" ]; then
              su -s /bin/bash - ${_HM_U} -c "drush8 cc drush" &> /dev/null
              wait
              _acct_in_real_dir "${_usEr}/.tmp" rm -rf -- ./cache
              _run_drush8_hmr_cmd "dis update syslog dblog -y"
              _run_drush8_hmr_cmd "cron"
              _run_drush8_hmr_cmd "cache-clear all"
              _run_drush8_hmr_cmd "cache-clear all"
              _run_drush8_hmr_cmd "utf8mb4-convert-databases -y"
              _log_ctrl_mark "plr.${_PlrID}.hm-fix-${_NOW}.info"
            fi
          fi
          if [ ! -z "${_Dan}" ] \
            && [ "${_Dan}" != "hostmaster" ]; then
            if [ "${_FOREIGN_CMS}" != "YES" ]; then
              _if_site_db_conversion
            fi
            searchStringB=".dev."
            searchStringC=".devel."
            searchStringD=".temp."
            searchStringE=".tmp."
            searchStringF=".temporary."
            searchStringG=".test."
            searchStringH=".testing."
            case ${_Dom} in
              *"$searchStringB"*) ;;
              *"$searchStringC"*) ;;
              *"$searchStringD"*) ;;
              *"$searchStringE"*) ;;
              *"$searchStringF"*) ;;
              *"$searchStringG"*) ;;
              *"$searchStringH"*) ;;
              *)
              if [ "${_MODULES_FIX}" = "YES" ]; then
                if [ "${_FOREIGN_CMS}" != "YES" ]; then
                  _fix_modules
                fi
                _fix_robots_txt
                _fix_llms_txt
              fi
              _le_ssl_check_update
              if [ "${_ENABLE_GOACCESS}" = "YES" ] && [ -e "${_usEr}/static/control/goaccess/${_Dom}.info" ]; then
                _noPrefixDom="${_Dom#www.}"
                _if_gen_goaccess ${_noPrefixDom}
                _if_gen_goaccess ${_Dom}
              fi
              ;;
            esac
            if [ "${_FOREIGN_CMS}" != "YES" ]; then
              _fix_site_control_files
            fi
            if [ "${_FOREIGN_CMS}" != "YES" ] \
              && { [ -e "${_Plr}/modules/o_contrib_seven" ] \
              || [ -e "${_Plr}/modules/o_contrib" ]; }; then
              if [ "${_CLEAR_BOOST}" = "YES" ]; then
                _fix_boost_cache
              fi
              _fix_user_register_protection_with_vSet
              if [[ "${_xSrl}" =~ "OFF" ]]; then
                _run_drush8_cmd "advagg-force-new-aggregates"
                _run_drush8_cmd "cache-clear all"
                _run_drush8_cmd "cache-clear all"
              fi
            fi
          fi
        fi
        ###
        ### Detect permissions fix overrides, if set per platform.
        ###
        _DONT_TOUCH_PERMISSIONS=NO
        ### A Grav or Textpattern platform has no control INI to read this
        ### opt-out from; the box-wide switches below still apply.
        if [ "${_FOREIGN_CMS}" != "YES" ]; then
          ### The strip at the head of this iteration is many drush runs old by
          ### now: this late leg reads the INI once (_ctrl_ini_read) and
          ### appends through _ctrl_ini_add, never through a name swapped for a
          ### link or a FIFO since. The re-strip is a no-op on a regular file.
          _desymlink_planted "${_PLR_CTRL_F}"
          if _iniTxt=$(_ctrl_ini_read "${_PLR_CTRL_F}"); then
            _FIX_PERMISSIONS_PRESENT=$(grep "fix_files_permissions_daily" \
              <<< "${_iniTxt}" 2>&1)
            if [[ "${_FIX_PERMISSIONS_PRESENT}" =~ "fix_files_permissions_daily" ]]; then
              _DO_NOTHING=YES
            else
              _ctrl_ini_add "${_PLR_CTRL_F}" ";fix_files_permissions_daily = TRUE"
            fi
            _FIX_PERMISSIONS_TEST=$(grep "^fix_files_permissions_daily = FALSE" \
              <<< "${_iniTxt}" 2>&1)
            if [[ "${_FIX_PERMISSIONS_TEST}" =~ "fix_files_permissions_daily = FALSE" ]]; then
              _DONT_TOUCH_PERMISSIONS=YES
            fi
          fi
        fi
        if [ -e "${_Plr}/profiles" ] \
          && [ -e "${_Plr}/web.config" ] \
          && [ ! -e "${_Plr}/core" ] \
          && [ ! -f "${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info" ]; then
          _PATCH_TEST=$(grep "foreach (array_values(\$data)" \
            ${_Plr}/includes/database/database.inc 2>&1)
          if [[ "${_PATCH_TEST}" =~ "array_values" ]]; then
            _DONT_TOUCH_PERMISSIONS="${_DONT_TOUCH_PERMISSIONS}"
          else
            _DONT_TOUCH_PERMISSIONS=NO
          fi
        fi
        if [ -e "/etc/boa/.dont.touch.permissions.cnf" ] \
          || [ "${_SKIP_PERMISSIONS_PASS}" = "YES" ]; then
          _DONT_TOUCH_PERMISSIONS=YES
        fi
        if [ "${_DONT_TOUCH_PERMISSIONS}" = "NO" ] \
          && [ "${_PERMISSIONS_FIX}" = "YES" ]; then
          _fix_permissions
        fi
      fi
      _MOMENT=$(date +%y%m%d-%H%M%S)
      echo ${_MOMENT} End Counting Site ${_Site}
    fi
  done
}
