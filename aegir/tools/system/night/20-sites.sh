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
  _dbName=$(sed -n "s/^\$options\['db_name'\][[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" \
    "${_Dir}/drushrc.php" 2>/dev/null | head -n 1)
  if [ -z "${_dbName}" ]; then
    echo "D8PLUS-POLICY: no db_name in ${_Dir}/drushrc.php for ${_Dom} -- probe skipped"
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
  _IGNORE_USER_REGISTER_PROTECTION=NO
  _ENABLE_STRICT_USER_REGISTER_PROTECTION=NO
  if [ -e "/data/conf/default.boa_platform_control.ini" ] \
    && [ ! -e "${_PLR_CTRL_F}" ]; then
    _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
  fi
  if [ -e "${_PLR_CTRL_F}" ]; then
    _EN_URP_T_S=$(grep "^enable_strict_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    _EN_URP_T=$(grep "^enable_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_EN_URP_T_S}" =~ "enable_strict_user_register_protection = TRUE" ]] \
      || [[ "${_EN_URP_T}" =~ "enable_user_register_protection = TRUE" ]]; then
      _ENABLE_STRICT_USER_REGISTER_PROTECTION=YES
    fi
    _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    _DIS_URP_T_I=$(grep "^ignore_user_register_protection = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_DIS_URP_T}" =~ "disable_user_register_protection = TRUE" ]] \
      || [[ "${_DIS_URP_T_I}" =~ "ignore_user_register_protection = TRUE" ]]; then
      _IGNORE_USER_REGISTER_PROTECTION=YES
    fi
  fi
  if [ -e "${_usEr}/static/control/enable_user_register_protection.info" ]; then
    mv -f ${_usEr}/static/control/enable_user_register_protection.info \
      ${_usEr}/static/control/enable_strict_user_register_protection.info
  fi
  if [ -e "${_usEr}/static/control/disable_user_register_protection.info" ]; then
    mv -f ${_usEr}/static/control/disable_user_register_protection.info \
      ${_usEr}/static/control/ignore_user_register_protection.info
  fi
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "NO" ] \
    && [ -e "${_usEr}/static/control/enable_strict_user_register_protection.info" ]; then
    sed -i "s/.*enable.*user_register_protection.*/enable_strict_user_register_protection = TRUE/g" \
      ${_PLR_CTRL_F} &> /dev/null
    wait
    _ENABLE_STRICT_USER_REGISTER_PROTECTION=YES
  fi
  if [ "${_ENABLE_STRICT_USER_REGISTER_PROTECTION}" = "YES" ] \
    && [ -e "${_usEr}/static/control/ignore_user_register_protection.info" ]; then
    sed -i "s/.*enable.*user_register_protection.*/enable_strict_user_register_protection = FALSE/g" \
      ${_PLR_CTRL_F} &> /dev/null
    wait
    _IGNORE_USER_REGISTER_PROTECTION=YES
  fi
  if [ -e "/data/conf/default.boa_site_control.ini" ] \
    && [ ! -e "${_DIR_CTRL_F}" ]; then
    _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
  fi
  if [ -e "${_DIR_CTRL_F}" ]; then
    _DIS_URP_T=$(grep "^disable_user_register_protection = TRUE" \
      ${_DIR_CTRL_F} 2>&1)
    _DIS_URP_T_I=$(grep "^ignore_user_register_protection = TRUE" \
      ${_DIR_CTRL_F} 2>&1)
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

_fix_llms_txt() {
  # The site files/ dir is tenant-writable (oN:www-data 02775; the shell user is
  # in www-data), so a tenant can plant files/llms.txt as a symlink. curl -o
  # follows it and creates the target of a dangling link, and the chown/chmod
  # below would then retarget it -- a root write to a tenant-chosen path. Strip
  # any planted link first, fetch into a temp in the root-only staging dir under
  # the account root (_ctrl_stage_dir), then mv -f -T over the leaf so rename()
  # replaces a re-planted link instead of following it; guard the trailing
  # metadata legs with [ ! -L ].
  _desymlink_planted "${_Dir}/files/llms.txt"
  # A tenant-uploaded policy is durable content, served as-is for as long as
  # the tenant keeps it -- the docs promise exactly that. Only a copy this
  # refresher itself fetched may be expired, re-fetched or content-gated;
  # provenance is the md5 of the fetched copy, recorded in a marker the tenant
  # cannot reach (the site dir is not group-writable). No marker, or an md5
  # mismatch (the tenant replaced or edited the copy): hands off beyond
  # ownership/mode normalisation.
  _LLMS_MARK="${_Dir}/.llms-fetched.md5"
  _LLMS_SUM=
  if [ -f "${_Dir}/files/llms.txt" ] && [ ! -L "${_Dir}/files/llms.txt" ]; then
    _LLMS_SUM=$(md5sum "${_Dir}/files/llms.txt" 2>/dev/null | cut -d' ' -f1)
    if [ ! -f "${_LLMS_MARK}" ] \
      || [ -z "${_LLMS_SUM}" ] \
      || ! grep -q "^${_LLMS_SUM}$" "${_LLMS_MARK}" 2>/dev/null; then
      rm -f "${_LLMS_MARK}"
      # The [ ! -L ] above is a md5sum fork and a grep away, and files/ is
      # tenant-writable: -h so a link replanted in that window is never
      # followed, and re-test right before the chmod, which has no -h.
      chown -h ${_HM_U}:www-data ${_Dir}/files/llms.txt &> /dev/null
      [ ! -L "${_Dir}/files/llms.txt" ] \
        && chmod 0664 ${_Dir}/files/llms.txt &> /dev/null
      if [ -f "${_Plr}/llms.txt" ] || [ -L "${_Plr}/llms.txt" ]; then
        rm -f ${_Plr}/llms.txt
      fi
      return 0
    fi
    find ${_Dir}/files/llms.txt -mtime +6 -exec rm -f {} \; &> /dev/null
  fi
  if [ ! -e "${_Dir}/files/llms.txt" ] \
    && [ ! -e "${_Plr}/profiles/hostmaster" ] \
    && [ -d "${_Dir}/files" ]; then
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
      mv -f -T "${_LLMS_TMP}" ${_Dir}/files/llms.txt &> /dev/null \
        || rm -f "${_LLMS_TMP}"
    fi
  fi
  _VAR_IF_PRESENT=
  if [ -f "${_Dir}/files/llms.txt" ] && [ ! -L "${_Dir}/files/llms.txt" ]; then
    _VAR_IF_PRESENT=$(grep "##" ${_Dir}/files/llms.txt 2>&1)
  fi
  if [[ ! "${_VAR_IF_PRESENT}" =~ "##" ]]; then
    [ ! -L "${_Dir}/files/llms.txt" ] && rm -f ${_Dir}/files/llms.txt
    rm -f "${_LLMS_MARK}"
  else
    if [ ! -L "${_Dir}/files/llms.txt" ]; then
      chown -h ${_HM_U}:www-data ${_Dir}/files/llms.txt &> /dev/null
      chmod 0664 ${_Dir}/files/llms.txt &> /dev/null
      # The site dir is not group-writable in the steady state, but
      # _fix_static_permissions walks every dir of a ~/static platform through
      # a 0775 window each night, so the marker IS plantable; ">" would follow
      # a link and truncate its target as root.
      _desymlink_planted "${_LLMS_MARK}"
      md5sum "${_Dir}/files/llms.txt" 2>/dev/null | cut -d' ' -f1 \
        > "${_LLMS_MARK}"
    fi
    if [ -f "${_Plr}/llms.txt" ] || [ -L "${_Plr}/llms.txt" ]; then
      rm -f ${_Plr}/llms.txt
    fi
  fi
}

_fix_robots_txt() {
  # See _fix_llms_txt: files/ is tenant-writable, so guard the planted-symlink
  # class -- strip the leaf, fetch into a temp in the root-only staging dir under
  # the account root, mv -f -T over the leaf, and gate the metadata legs with
  # [ ! -L ].
  _desymlink_planted "${_Dir}/files/robots.txt"
  find ${_Dir}/files/robots.txt -mtime +6 -exec rm -f {} \; &> /dev/null
  if [ ! -e "${_Dir}/files/robots.txt" ] \
    && [ ! -e "${_Plr}/profiles/hostmaster" ] \
    && [ -d "${_Dir}/files" ]; then
    _ROBOTS_TMP=$(mktemp "${_Dir}/.robots.XXXXXX" 2>/dev/null)
    if [ -n "${_ROBOTS_TMP}" ]; then
      # See _fix_llms_txt: our own 503 stubs send Retry-After: 3600 and curl
      # sleeps that between retries, so the retry sleep needs --retry-max-time;
      # --max-time bounds one transfer only.
      curl -L --max-redirs 10 -k -s --connect-timeout 10 --max-time 20 \
        --retry 2 --retry-delay 5 --retry-max-time 30 \
        -A iCab "http://${_Dom}/robots.txt?nocache=1&noredis=1" \
        -o "${_ROBOTS_TMP}"
      echo >> "${_ROBOTS_TMP}"
      mv -f -T "${_ROBOTS_TMP}" ${_Dir}/files/robots.txt &> /dev/null \
        || rm -f "${_ROBOTS_TMP}"
    fi
  fi
  _VAR_IF_PRESENT=
  if [ -f "${_Dir}/files/robots.txt" ] && [ ! -L "${_Dir}/files/robots.txt" ]; then
    _VAR_IF_PRESENT=$(grep "Disallow:" ${_Dir}/files/robots.txt 2>&1)
  fi
  if [[ ! "${_VAR_IF_PRESENT}" =~ "Disallow:" ]]; then
    [ ! -L "${_Dir}/files/robots.txt" ] && rm -f ${_Dir}/files/robots.txt
  else
    if [ ! -L "${_Dir}/files/robots.txt" ]; then
      # -h: files/ is tenant-writable, so the leaf can be replanted between the
      # [ ! -L ] above and this call; the link must never be dereferenced.
      chown -h ${_HM_U}:www-data ${_Dir}/files/robots.txt &> /dev/null
      chmod 0664 ${_Dir}/files/robots.txt &> /dev/null
    fi
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
  # The per-iteration strip in _daily_process is many drush runs and two curl
  # fetches old by the time we get here, and both modules dirs stay
  # tenant-writable throughout: a link replanted in that window would take the
  # sed -i and ">>" legs below (">>" follows the final component). Same
  # reasoning, same helper, as the late re-strip at the tail of _daily_process.
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
    if [ -e "${_DIR_CTRL_F}" ]; then
      _AGG_P=$(grep "advagg_auto_configuration" ${_DIR_CTRL_F} 2>&1)
      _AGG_T=$(grep "^advagg_auto_configuration = TRUE" ${_DIR_CTRL_F} 2>&1)
      if [[ "${_AGG_T}" =~ "advagg_auto_configuration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the site level ini file.
        ###
        if [[ "${_AGG_P}" =~ "advagg_auto_configuration" ]]; then
          sed -i "s/.*advagg_auto_c.*/advagg_auto_configuration = TRUE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        else
          echo "advagg_auto_configuration = TRUE" >> ${_DIR_CTRL_F}
        fi
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_site_control.ini" ] \
      && [ ! -e "${_DIR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
    fi
    if [ -e "${_DIR_CTRL_F}" ]; then
      _AGG_P=$(grep "advagg_auto_configuration" ${_DIR_CTRL_F} 2>&1)
      _AGG_T=$(grep "^advagg_auto_configuration = FALSE" \
        ${_DIR_CTRL_F} 2>&1)
      if [[ "${_AGG_T}" =~ "advagg_auto_configuration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        if [[ "${_AGG_P}" =~ "advagg_auto_configuration" ]]; then
          sed -i "s/.*advagg_auto_c.*/advagg_auto_configuration = FALSE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        else
          echo ";advagg_auto_configuration = FALSE" >> ${_DIR_CTRL_F}
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
      if [ -e "${_DIR_CTRL_F}" ]; then
        _AC_PFD_T=$(grep "^allow_private_file_downloads = TRUE" \
          ${_DIR_CTRL_F} 2>&1)
        if [[ "${_AC_PFD_T}" =~ "allow_private_file_downloads = TRUE" ]]; then
          _DO_NOTHING=YES
        else
          ###
          ### Do this only for the site level ini file.
          ###
          sed -i "s/.*allow_private_f.*/allow_private_file_downloads = TRUE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
        fi
      fi
    else
      if [ -e "/data/conf/default.boa_site_control.ini" ] \
        && [ ! -e "${_DIR_CTRL_F}" ]; then
        _reseed_ctrl_ini /data/conf/default.boa_site_control.ini "${_DIR_CTRL_F}"
      fi
      if [ -e "${_DIR_CTRL_F}" ]; then
        _AC_PFD_T=$(grep "^allow_private_file_downloads = FALSE" \
          ${_DIR_CTRL_F} 2>&1)
        if [[ "${_AC_PFD_T}" =~ "allow_private_file_downloads = FALSE" ]]; then
          _DO_NOTHING=YES
        else
          sed -i "s/.*allow_private_f.*/allow_private_file_downloads = FALSE/g" \
      ${_DIR_CTRL_F} &> /dev/null
          wait
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
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_FB_T=$(grep "^auto_detect_facebook_integration = TRUE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_FB_T}" =~ "auto_detect_facebook_integration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the platform level ini file, so the site
        ### level ini file can disable this check by setting it
        ### explicitly to auto_detect_facebook_integration = FALSE
        ###
        sed -i "s/.*auto_detect_face.*/auto_detect_facebook_integration = TRUE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
    fi
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_FB_T=$(grep "^auto_detect_facebook_integration = FALSE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_FB_T}" =~ "auto_detect_facebook_integration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        sed -i "s/.*auto_detect_face.*/auto_detect_facebook_integration = FALSE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
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
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_DA_T=$(grep "^auto_detect_domain_access_integration = TRUE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_DA_T}" =~ "auto_detect_domain_access_integration = TRUE" ]]; then
        _DO_NOTHING=YES
      else
        ###
        ### Do this only for the platform level ini file, so the site
        ### level ini file can disable this check by setting it
        ### explicitly to auto_detect_domain_access_integration = FALSE
        ###
        sed -i "s/.*auto_detect_domain.*/auto_detect_domain_access_integration = TRUE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
      fi
    fi
  else
    if [ -e "/data/conf/default.boa_platform_control.ini" ] \
      && [ ! -e "${_PLR_CTRL_F}" ]; then
      _reseed_ctrl_ini /data/conf/default.boa_platform_control.ini "${_PLR_CTRL_F}"
    fi
    if [ -e "${_PLR_CTRL_F}" ]; then
      _AD_DA_T=$(grep "^auto_detect_domain_access_integration = FALSE" \
        ${_PLR_CTRL_F} 2>&1)
      if [[ "${_AD_DA_T}" =~ "auto_detect_domain_access_integration = FALSE" ]]; then
        _DO_NOTHING=YES
      else
        sed -i "s/.*auto_detect_domain.*/auto_detect_domain_access_integration = FALSE/g" \
          ${_PLR_CTRL_F} &> /dev/null
        wait
      fi
    fi
  fi

  ###
  ### Add new INI variables if missing
  ###
  ### The strip at the head of this iteration is many drush runs old by now
  ### and the INI sits in a 02775 group-writable dir, so re-strip before this
  ### read/append leg (no-op on a regular file).
  _desymlink_planted "${_PLR_CTRL_F}" "${_DIR_CTRL_F}"
  if [ -e "${_PLR_CTRL_F}" ]; then
    _VAR_IF_PRESENT=$(grep "session_cookie_ttl" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_cookie_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_cookie_ttl = 86400" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "session_gc_eol" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_gc_eol" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_gc_eol = 86400" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "enable_newrelic_integration" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "enable_newrelic_integration" ]]; then
      _DO_NOTHING=YES
    else
      echo ";enable_newrelic_integration = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_nine_mode" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_nine_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_nine_mode = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_eight_mode" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_eight_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_eight_mode = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_forced_mode" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_forced_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_forced_mode = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_lock_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_lock_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_lock_enable = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_path_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_path_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_path_enable = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_scan_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_scan_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_scan_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_exclude_bins" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_exclude_bins" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_exclude_bins = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "speed_booster_anon_cache_ttl" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "speed_booster_anon_cache_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";speed_booster_anon_cache_ttl = 10" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "disable_drupal_page_cache" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "disable_drupal_page_cache" ]]; then
      _DO_NOTHING=YES
    else
      echo ";disable_drupal_page_cache = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "allow_private_file_downloads" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "allow_private_file_downloads" ]]; then
      _DO_NOTHING=YES
    else
      echo ";allow_private_file_downloads = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "entitycache_dont_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "entitycache_dont_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";entitycache_dont_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "views_cache_bully_dont_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "views_cache_bully_dont_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";views_cache_bully_dont_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "views_content_cache_dont_enable" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "views_content_cache_dont_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";views_content_cache_dont_enable = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "set_composer_manager_vendor_dir" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "set_composer_manager_vendor_dir" ]]; then
      _DO_NOTHING=YES
    else
      echo ";set_composer_manager_vendor_dir = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_connect_timeout" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_connect_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_connect_timeout = 0.7" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_read_timeout" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_read_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_read_timeout = 0.7" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_backoff_ttl" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_backoff_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_backoff_ttl = 15" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_probe_retry" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_probe_retry" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_probe_retry = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_apcu_on_recovery" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_apcu_on_recovery" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_apcu_on_recovery = TRUE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_debug_header" ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_debug_header" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug_header = FALSE" >> ${_PLR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep -E "^;?redis_debug[ =]" ${_PLR_CTRL_F} 2>&1)
    if [[ -n "${_VAR_IF_PRESENT}" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug = FALSE" >> ${_PLR_CTRL_F}
    fi
  fi
  if [ -e "${_DIR_CTRL_F}" ]; then
     _VAR_IF_PRESENT=$(grep "session_cookie_ttl" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_cookie_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_cookie_ttl = 86400" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "session_gc_eol" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "session_gc_eol" ]]; then
      _DO_NOTHING=YES
    else
      echo ";session_gc_eol = 86400" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "enable_newrelic_integration" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "enable_newrelic_integration" ]]; then
      _DO_NOTHING=YES
    else
      echo ";enable_newrelic_integration = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_nine_mode" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_nine_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_nine_mode = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_old_eight_mode" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_old_eight_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_old_eight_mode = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_forced_mode" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_forced_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_forced_mode = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_lock_enable" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_lock_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_lock_enable = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_path_enable" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_path_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_path_enable = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_scan_enable" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_scan_enable" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_scan_enable = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_exclude_bins" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_exclude_bins" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_exclude_bins = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "speed_booster_anon_cache_ttl" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "speed_booster_anon_cache_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";speed_booster_anon_cache_ttl = 10" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "disable_drupal_page_cache" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "disable_drupal_page_cache" ]]; then
      _DO_NOTHING=YES
    else
      echo ";disable_drupal_page_cache = FALSE" >> ${_DIR_CTRL_F}
    fi
     _VAR_IF_PRESENT=$(grep "allow_private_file_downloads" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "allow_private_file_downloads" ]]; then
      _DO_NOTHING=YES
    else
      echo ";allow_private_file_downloads = FALSE" >> ${_DIR_CTRL_F}
    fi
     _VAR_IF_PRESENT=$(grep "set_composer_manager_vendor_dir" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "set_composer_manager_vendor_dir" ]]; then
      _DO_NOTHING=YES
    else
      echo ";set_composer_manager_vendor_dir = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_connect_timeout" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_connect_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_connect_timeout = 0.7" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_read_timeout" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_read_timeout" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_read_timeout = 0.7" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_backoff_ttl" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_backoff_ttl" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_backoff_ttl = 15" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_probe_retry" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_probe_retry" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_probe_retry = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_flush_apcu_on_recovery" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_flush_apcu_on_recovery" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_flush_apcu_on_recovery = TRUE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep "redis_debug_header" ${_DIR_CTRL_F} 2>&1)
    if [[ "${_VAR_IF_PRESENT}" =~ "redis_debug_header" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug_header = FALSE" >> ${_DIR_CTRL_F}
    fi
    _VAR_IF_PRESENT=$(grep -E "^;?redis_debug[ =]" ${_DIR_CTRL_F} 2>&1)
    if [[ -n "${_VAR_IF_PRESENT}" ]]; then
      _DO_NOTHING=YES
    else
      echo ";redis_debug = FALSE" >> ${_DIR_CTRL_F}
    fi
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _EC_DE_T=$(grep "^entitycache_dont_enable = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_EC_DE_T}" =~ "entitycache_dont_enable = TRUE" ]] \
      || [ -e "${_Plr}/profiles/commons" ]; then
      _ENTITYCACHE_DONT_ENABLE=YES
    else
      _ENTITYCACHE_DONT_ENABLE=NO
    fi
  else
    _ENTITYCACHE_DONT_ENABLE=NO
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _VCB_DE_T=$(grep "^views_cache_bully_dont_enable = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_VCB_DE_T}" =~ "views_cache_bully_dont_enable = TRUE" ]]; then
      _VIEWS_CACHE_BULLY_DONT_ENABLE=YES
    else
      _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
    fi
  else
    _VIEWS_CACHE_BULLY_DONT_ENABLE=NO
  fi

  if [ -e "${_PLR_CTRL_F}" ]; then
    _VCC_DE_T=$(grep "^views_content_cache_dont_enable = TRUE" \
      ${_PLR_CTRL_F} 2>&1)
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
  ###
  ### Detect db conversion mode, if set per platform or per site.
  ###
  if [ -e "${_PLR_CTRL_F}" ]; then
    _SQL_INDB_P=$(grep "sql_conversion_mode" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_P}" =~ "sql_conversion_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";sql_conversion_mode = NO" >> ${_PLR_CTRL_F}
    fi
    _SQL_INDB_T=$(grep "^sql_conversion_mode = innodb" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_T}" =~ "sql_conversion_mode = innodb" ]]; then
      _SQL_CONVERT=innodb
    fi
    _SQL_MYSM_T=$(grep "^sql_conversion_mode = myisam" \
      ${_PLR_CTRL_F} 2>&1)
    if [[ "${_SQL_MYSM_T}" =~ "sql_conversion_mode = myisam" ]]; then
      _SQL_CONVERT=myisam
    fi
  fi
  if [ -e "${_DIR_CTRL_F}" ]; then
    _SQL_INDB_P=$(grep "sql_conversion_mode" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_P}" =~ "sql_conversion_mode" ]]; then
      _DO_NOTHING=YES
    else
      echo ";sql_conversion_mode = NO" >> ${_DIR_CTRL_F}
    fi
    _SQL_INDB_T=$(grep "^sql_conversion_mode = innodb" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SQL_INDB_T}" =~ "sql_conversion_mode = innodb" ]]; then
      _SQL_CONVERT=innodb
    fi
    _SQL_MYSM_T=$(grep "^sql_conversion_mode = myisam" \
      ${_DIR_CTRL_F} 2>&1)
    if [[ "${_SQL_MYSM_T}" =~ "sql_conversion_mode = myisam" ]]; then
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
    mkdir -p ${_usEr}/undo
    mv -f ${_Plr} ${_usEr}/undo/ &> /dev/null
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
  ### is tenant-plantable, and -f is FALSE for a dangling link -- the two
  ### "echo fixed >" writes below would then create the link's TARGET as root.
  ### Strip a planted link first; no-op on the real marker file.
  _desymlink_planted "${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info"
  if [ ! -f "${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info" ]; then
    _PATCH_TEST=$(grep "foreach (array_values(\$data)" \
      ${_Plr}/includes/database/database.inc 2>&1)
    if [[ "${_PATCH_TEST}" =~ "array_values" ]]; then
      echo fixed > ${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info
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
      echo fixed > ${_Plr}/profiles/SA-CORE-2014-005-D7-fix.info
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
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.ctm-lock-${_NOW}.info
      fi
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_use_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.ctm-unlock-${_NOW}.info" ]; then
        chown -R ${_HM_U}.ftp ${_use_Plr} &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.ctm-unlock-${_NOW}.info
      fi
    fi
    if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info" ]; then
      find ${_use_Plr} -type d -exec chmod 0775 {} \; &> /dev/null
      find ${_use_Plr} -type f -exec chmod 0664 {} \; &> /dev/null
      ### chmod follows a symlink named on the command line and has no -h, and
      ### the find above just made every dir in the tree 0775 group-writable, so
      ### all three of these are tenant-plantable names. None is ever
      ### legitimately a symlink -- skip rather than lock whatever was planted.
      if [ -e "${_use_Plr}/vendor/drush" ] \
        && [ ! -L "${_use_Plr}/vendor/drush" ]; then
        chmod 0400 ${_use_Plr}/vendor/drush
      fi
      if [ -e "${_use_Plr}/vendor/symfony/console/Input" ] \
        && [ ! -L "${_use_Plr}/vendor/symfony/console/Input" ]; then
        chmod 0400 ${_use_Plr}/vendor/symfony/console/Input
      fi
      if [ -e "${_use_Plr}/vendor/symfony/console/Style" ] \
        && [ ! -L "${_use_Plr}/vendor/symfony/console/Style" ]; then
        chmod 0400 ${_use_Plr}/vendor/symfony/console/Style
      fi
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
  local _grp
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
  if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info" ] \
    && [ -e "${_Plr}" ] \
    && [ ! -L "${_Plr}/sites" ] \
    && [ ! -L "${_Plr}/sites/all" ]; then
    mkdir -p ${_Plr}/sites/all/{modules,themes,libraries,drush}
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
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.lock-${_NOW}.info
      fi
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      if [ ! -e "${_usEr}/log/ctrl/plr.${_PlrID}.unlock-${_NOW}.info" ]; then
        ### -h for the same reason as the lock branch above; here the planted
        ### target would be handed straight to the tenant's shell user.
        chown -h -R ${_HM_U}.ftp:${_grp} \
          ${_Plr}/sites/all/{modules,themes,libraries}/* &> /dev/null
        touch ${_usEr}/log/ctrl/plr.${_PlrID}.unlock-${_NOW}.info
      fi
    fi
    ### -h on the chown and find -P (never a bare glob) on the chmods: the
    ### sites/* entries are tenant-creatable names once sites/ takes group
    ### write below, so none of them may be followed.
    chown -h ${_HM_U}:${_grp} \
      ${_Plr}/sites/all/drush/drushrc.php \
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
    if [[ ! "${_Plr}" =~ /static/ ]]; then
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
    if [ ! -L "${_Plr}/sites/all/libraries/tcpdf" ] \
      && [ ! -L "${_Plr}/sites/all/libraries/tcpdf/cache" ]; then
      chmod -R 775 ${_Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
      chown -R ${_HM_U}:www-data \
        ${_Plr}/sites/all/libraries/tcpdf/cache &> /dev/null
    fi
    touch ${_usEr}/log/ctrl/plr.${_PlrID}.perm-fix-${_NOW}.info
  fi
  ### sites/ is 02771 and group-writable on tenant composer codebases (the
  ### account's shell identities; any tenant while the instance still carries
  ### the box-wide 'users' group), so sites/<uri> is a name a tenant can unlink
  ### and re-create: a symlink there redirects
  ### every rm/mkdir/chown/find in this block through it, and none of them
  ### re-checks. A site_path is never legitimately a symlink (alias links point
  ### AT it), so refuse one and leave the site alone.
  if [ -e "${_Dir}" ] \
    && [ ! -L "${_Dir}" ] \
    && [ -e "${_Dir}/drushrc.php" ] \
    && [ -e "${_Dir}/files" ] \
    && [ -e "${_Dir}/private" ]; then
    ### Cleanup
    rm ${_Dir}/*.{codebasecheck*,hm-fix-*,ctm-lock-*,lock-*,perm-fix-*}.info &> /dev/null
    ### directory and settings files - site level
    if [ ! -e "${_Dir}/modules" ]; then
      mkdir ${_Dir}/modules
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
    find ${_Dir}/{modules,themes,libraries}/*{.tar,.tar.gz,.zip} -type f -exec \
      rm -f {} \; &> /dev/null
    rm -f ${_Dir}/modules/local-allow.info
    if [ ! -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      ### -h: these three dirs are 02775 group 'users' (see the find below), so
      ### every glob hit is a tenant-plantable name and chown -R follows a
      ### symlink given as its starting point. Same shape as the files leg.
      chown -h -R ${_HM_U}:${_grp} \
        ${_Dir}/{modules,themes,libraries}/* &> /dev/null
    elif [ -e "${_usEr}/static/control/unlock.info" ] \
      && [ ! -e "${_Plr}/skip.info" ]; then
      chown -h -R ${_HM_U}.ftp:${_grp} \
        ${_Dir}/{modules,themes,libraries}/* &> /dev/null
    fi
    ### -h: all four are names in a site dir the tenant owns under
    ### unlock.info, and only modules is covered by the _validate_ctrl_dir gate
    ### at the head of the loop. None is ever legitimately a symlink.
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
          ;;
        *)
          echo "SKIP: ${_Dir}/files resolves outside any static store: ${_rFls}"
          ;;
      esac
    fi
    ### These names sit inside the tenant-writable files dir, so any of them can
    ### be a planted symlink; -h keeps the chown on the link instead of its
    ### target and is a no-op on the regular directories they normally are.
    chown -h ${_HM_U}:www-data ${_Dir}/files/{tmp,images,pictures,css,js} &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/files/{advagg_css,advagg_js,ctools} &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/files/{ctools/css,imagecache,locations} &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/files/{xmlsitemap,deployment,styles,private} &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/files/{civicrm,civicrm/templates_c} &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/files/{civicrm/upload,civicrm/persist} &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/files/{civicrm/custom,civicrm/dynamic} &> /dev/null
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
          ;;
        *)
          echo "SKIP: ${_Dir}/private resolves outside any static store: ${_rPrv}"
          ;;
      esac
    fi
    chown -h ${_HM_U}:www-data ${_Dir}/private/{files,temp} &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/private/files/backup_migrate &> /dev/null
    chown -h ${_HM_U}:www-data ${_Dir}/private/files/backup_migrate/{manual,scheduled} &> /dev/null
    chown -h -R ${_HM_U}:www-data ${_Dir}/private/config &> /dev/null
    _DB_HOST_PRESENT=$(grep "^\$_SERVER\['db_host'\] = \$options\['db_host'\];" \
      ${_Dir}/drushrc.php 2>&1)
    if [[ "${_DB_HOST_PRESENT}" =~ "db_host" ]]; then
      if [ "${_FORCE_SITES_VERIFY}" = "YES" ]; then
        _run_drush8_hmr_cmd "hosting-task @${_Dom} verify --force"
      fi
    elif [ ! -L "${_Dir}/drushrc.php" ]; then
      ### ">>" resolves the path normally and appends THROUGH a symlink at the
      ### final component, creating the target if absent -- and it is the grep
      ### above MISSING the line that gets us here, so any planted target
      ### guarantees the write. drushrc.php is never legitimately a symlink;
      ### refuse rather than strip, since removing a real one breaks the site.
      echo "\$_SERVER['db_host'] = \$options['db_host'];" >> ${_Dir}/drushrc.php
      _run_drush8_hmr_cmd "hosting-task @${_Dom} verify --force"
    fi
  fi
}

_convert_controls_orig() {
  if [ -e "${_CTRL_DIR}/$1.info" ] \
    || [ -e "${_usEr}/static/control/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      _reseed_ctrl_ini "${_CTRL_F_TPL}" "${_CTRL_F}"
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

_convert_controls_orig_no_global() {
  if [ -e "${_CTRL_DIR}/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      _reseed_ctrl_ini "${_CTRL_F_TPL}" "${_CTRL_F}"
    fi
    sed -i "s/.*$1.*/$1 = TRUE/g" ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
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
    sed -i "s/.*speed_booster_anon.*/speed_booster_anon_cache_ttl = ${_TTL}/g" \
      ${_CTRL_F} &> /dev/null
    wait
    rm -f ${_CTRL_DIR}/$1.info
  fi
}

_convert_controls_renamed() {
  if [ -e "${_CTRL_DIR}/$1.info" ]; then
    if [ ! -e "${_CTRL_F}" ] && [ -e "${_CTRL_F_TPL}" ]; then
      _reseed_ctrl_ini "${_CTRL_F_TPL}" "${_CTRL_F}"
    fi
    if [ "$1" = "cookie_domain" ]; then
      sed -i "s/.*server_name_cookie.*/server_name_cookie_domain = TRUE/g" \
        ${_CTRL_F} &> /dev/null
      wait
    fi
    rm -f ${_CTRL_DIR}/$1.info
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

_cleanup_ini() {
  if [ -e "${_CTRL_F}" ]; then
    sed -i "s/^;;.*//g"   ${_CTRL_F} &> /dev/null
    wait
    sed -i "s/^ .*//g"    ${_CTRL_F} &> /dev/null
    wait
    sed -i "s/^#.*//g"    ${_CTRL_F} &> /dev/null
    wait
    sed -i "/^$/d"        ${_CTRL_F} &> /dev/null
    wait
    sed -i "s/^\[/\n\[/g" ${_CTRL_F} &> /dev/null
    wait
  fi
}

_add_note_platform_ini() {
  if [ -e "${_CTRL_F}" ]; then
    echo "" >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  This is a platform level ACTIVE INI file which can be used to modify"     >> ${_CTRL_F}
    echo ";;  default BOA system behaviour for all sites hosted on this platform."      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> ${_CTRL_F}
    echo ";;  default.boa_platform_control.ini, since this ACTIVE INI file"             >> ${_CTRL_F}
    echo ";;  may not include all options available after upgrade to BOA-${_xSrl}"      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> ${_CTRL_F}
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
  fi
}

_add_note_site_ini() {
  if [ -e "${_CTRL_F}" ]; then
    echo "" >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  This is a site level ACTIVE INI file which can be used to modify"         >> ${_CTRL_F}
    echo ";;  default BOA system behaviour for this site only."                         >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Please review complete documentation included in this file TEMPLATE:"     >> ${_CTRL_F}
    echo ";;  default.boa_site_control.ini, since this ACTIVE INI file"                 >> ${_CTRL_F}
    echo ";;  may not include all options available after upgrade to BOA-${_xSrl}"      >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
    echo ";;  Note that it takes ~60 seconds to see any modification results in action" >> ${_CTRL_F}
    echo ";;  due to opcode caching enabled in PHP-FPM for all non-dev sites."          >> ${_CTRL_F}
    echo ";;" >> ${_CTRL_F}
  fi
}

_fix_platform_control_files() {
  if [ -e "/data/conf/default.boa_platform_control.ini" ]; then
    ### Re-strip immediately before the sed -i / ">>" legs below: both names
    ### live in the tenant-writable setgid sites/all/modules dir, sed -i READS
    ### through a planted link and ">>" WRITES through it. Mirrors the strip
    ### the late platform read/append leg already does.
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
    ### called, and both names live in the tenant-writable setgid modules dir:
    ### sed -i READS through a planted link and ">>" WRITES through it. Same
    ### re-strip the late platform read/append leg already does.
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

_cleanup_ghost_vhosts() {
  _provision_running && return
  for _Site in `find ${_usEr}/config/server_master/nginx/vhost.d -maxdepth 1 \
    -mindepth 1 -type f | sort`; do
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
    [ -n "$(find "${_Site}" -mmin -1440 2>/dev/null)" ] && _gh_vfresh=YES
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
          mkdir -p ${_usEr}/undo
          mv -f ${_usEr}/.drush/${_Dom}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
          mv -f ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} ${_usEr}/undo/ &> /dev/null
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
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d/${_Dom}" ]; then
      local _thisVhost="${_usEr}/config/server_master/nginx/vhost.d/${_Dom}"
      local _fixHttpReqired=NO
      if grep -q -e "ssl http2" "${_thisVhost}"; then
        local _fixHttpReqired=YES
      elif grep -q -E '^\s*listen[^;]*443[^;]*ssl' "${_thisVhost}" \
        && ! grep -q -E '^\s*http2\s+on;$' "${_thisVhost}"; then
        # Only a TLS-terminating vhost needs 'http2 on;'. Without this test a
        # plain :80 vhost never satisfied the check, so it was rewritten (and
        # its mtime refreshed) every single night for no change at all.
        local _fixHttpReqired=YES
      elif grep -q -E '^\s+listen.*443\s+quic;$' "${_thisVhost}"; then
        local _fixHttpReqired=YES
      fi
      if [ "${_fixHttpReqired}" = "YES" ]; then
        echo "FIXING vhost for ${_Dom}"
        # Remove 'http2' from 'listen' directives with varying spaces
        sed -i -E 's/(listen\s+[^;]*\s+ssl)\s+http2;$/\1;/' "${_thisVhost}"
        # Remove existing 'http2 on;' lines with varying spaces
        sed -i -E '/^\s*http2\s+on;/d' "${_thisVhost}"
        # Remove existing 'quic' lines with varying spaces
        sed -i -E '/^\s+listen.*443\s+quic;/d' "${_thisVhost}"
        # Remove unwanted directives with varying spaces
        sed -i -E \
          -e '/^\s*ssl_stapling\b/d' \
          -e '/^\s*ssl_stapling_verify\b/d' \
          -e '/^\s*resolver\b/d' \
          -e '/^\s*resolver_timeout\b/d' \
          "${_thisVhost}"
        # Update 'ssl_prefer_server_ciphers' directive, handling spaces
        sed -i -E 's/^\s*ssl_prefer_server_ciphers\s+.*$/ssl_prefer_server_ciphers on;/' "${_thisVhost}"
        # Update 'http3_hq' directive, handling spaces
        sed -i -E 's/http3_hq\s+on;$/http3_hq on;/' "${_thisVhost}"
        if grep -q 'ssl_prefer_server_ciphers' "${_thisVhost}"; then
          # Add 'http2 on;' after 'ssl_prefer_server_ciphers on;', only if not already present
          if ! grep -q -E '^\s*http2\s+on;$' "${_thisVhost}"; then
            sed -i '/ssl_prefer_server_ciphers on;/ a\  http2 on;' "${_thisVhost}"
          fi
        elif grep -q -E '^\s*#?http3_hq\s+on;$' "${_thisVhost}"; then
          # Add 'http2 on;' after 'http3_hq on;', only if not already present
          if ! grep -q -E '^\s*http2\s+on;$' "${_thisVhost}"; then
            sed -i '/http3_hq on;/ a\  http2 on;' "${_thisVhost}"
          fi
        fi
      fi
      _Plx=$(cat ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} \
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
              mkdir -p ${_usEr}/undo
              mv -f ${_Site} ${_usEr}/undo/ &> /dev/null
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
      mkdir -p ${_usEr}/log/ctrl
      touch ${_usEr}/log/ctrl/ghost-reap-armed.info
      echo "GHOST sites cleanup enabled -- arming run for ${_HM_U}, nothing moved tonight"
    fi
  else
    rm -f ${_usEr}/log/ctrl/ghost-reap-armed.info
  fi
  for _thisAlias in `find ${_usEr}/.drush/*.alias.drushrc.php -maxdepth 1 -type f \
    | sort`; do
    _aliasName=$(echo "${_thisAlias}" | cut -d'/' -f6 | awk '{ print $1}' 2>&1)
    _aliasName=$(echo "${_aliasName}" \
      | sed "s/.alias.drushrc.php//g" \
      | awk '{ print $1}' 2>&1)
    if [[ "${_aliasName}" =~ (^)"server_" ]] \
      || [[ "${_aliasName}" =~ (^)"hostmaster" ]]; then
      _IS_SITE=NO
    elif [[ "${_aliasName}" =~ (^)"platform_" ]]; then
      _Plm=$(cat ${_thisAlias} \
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
          mkdir -p ${_usEr}/undo
          mv -f ${_Plm} ${_usEr}/undo/ &> /dev/null
          mv -f ${_thisAlias} ${_usEr}/undo/ &> /dev/null
          echo "GHOST broken platform ${_Plm} + alias detected and moved to ${_usEr}/undo/"
        else
          echo "GHOST broken platform ${_Plm} detected (dry-run/grace; set _GHOST_PLATFORMS_CLEANUP=YES to move)"
        fi
      else
        if _ghost_seen_enough "${_gh_pmark}" \
          && { _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_PLATFORMS_CLEANUP \
            || _cnf_flag_yes /root/.barracuda.cnf _GHOST_PLATFORMS_CLEANUP; }; then
          mkdir -p ${_usEr}/undo
          mv -f ${_thisAlias} ${_usEr}/undo/ &> /dev/null
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
          mkdir -p ${_usEr}/undo
          mv -f ${_usEr}/.drush/${_T_SITE_NAME}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
          echo "GHOST .restore alias ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
        else
          echo "GHOST .restore alias ${_T_SITE_NAME} detected (dry-run/grace; set _GHOST_SITES_CLEANUP=YES to move)"
        fi
      else
        _T_SITE_FDIR=$(cat ${_thisAlias} \
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
          if [ ! -e "${_T_SITE_FDIR}/modules" ]; then
            mkdir ${_T_SITE_FDIR}/modules
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
            _T_SITE_ROOT=$(cat ${_thisAlias} \
              | grep "'root' =>" \
              | cut -d: -f2 \
              | awk '{ print $3}' \
              | sed "s/[\,']//g" 2>&1)
            if [ -n "${_T_SITE_ROOT}" ] && [ ! -d "${_T_SITE_ROOT}" ]; then
              _GH_CLASS=platform-gone
            else
              for _GH_PALIAS in ${_usEr}/.drush/platform_*.alias.drushrc.php; do
                [ -e "${_GH_PALIAS}" ] || continue
                _GH_PROOT=$(cat ${_GH_PALIAS} \
                  | grep "'root' =>" \
                  | cut -d: -f2 \
                  | awk '{ print $3}' \
                  | sed "s/[\,']//g" 2>&1)
                if [ -n "${_GH_PROOT}" ] \
                  && [ "${_GH_PROOT}" != "${_T_SITE_ROOT}" ] \
                  && [ -d "${_GH_PROOT}/sites/${_T_SITE_NAME}" ]; then
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
              mkdir -p ${_usEr}/undo
              mv -f ${_usEr}/.drush/${_T_SITE_NAME}.alias.drushrc.php ${_usEr}/undo/ &> /dev/null
              echo "${_GH_LINE} detected and moved to ${_usEr}/undo/"
              if [[ ! "${_T_SITE_FDIR}" =~ "aegir/distro" ]]; then
                mv -f ${_usEr}/config/server_master/nginx/vhost.d/${_T_SITE_NAME} ${_usEr}/undo/ghost-vhost-${_T_SITE_NAME} &> /dev/null
                echo "GHOST vhost for ${_T_SITE_NAME} detected and moved to ${_usEr}/undo/"
              fi
              if [ -d "${_T_SITE_FDIR}" ] \
                && { _cnf_flag_yes /root/.${_HM_U}.octopus.cnf _GHOST_SITE_FILES_CLEANUP \
                  || _cnf_flag_yes /root/.barracuda.cnf _GHOST_SITE_FILES_CLEANUP; }; then
                mv -f ${_T_SITE_FDIR} ${_usEr}/undo/ghost-site-${_T_SITE_NAME} &> /dev/null
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

_le_ssl_check_update() {
  ### Work on a local copy: the www strips below (wildcard mode) otherwise
  ### rewrite the caller's per-site loop variable, so every later leg of the
  ### iteration addresses @<stripped> -- an alias that does not exist for a
  ### www-prefixed site -- and _if_gen_goaccess loses its www variant.
  local _Dom="${_Dom}"
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
    _SSL_ON_TEST=$(cat ${_Vht} | grep "443 ssl" 2>&1)
    if [[ "${_SSL_ON_TEST}" =~ "443 ssl" ]]; then
      if [ -e "${_usEr}/tools/le/certs/${_Dom}/fullchain.pem" ]; then
        echo "Running LE cert check directly for ${_Dom}"
        _usEaliases=""
        _siTealiases=`cat ${_Vht} \
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
			mkdir -p ${_usEr}/log/ctrl
			touch ${_usEr}/log/ctrl/site.${_Dom}.cert-x1-rebuilt.info
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
            ### clear -- on an arbitrary target. Skip, never delete: these are
            ### the tenant's own opt-in flags, not root-maintained INIs.
            if [ ! -L "${_usEr}/static/control" ]; then
              [ ! -L "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ] \
                && [ -f "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ] \
                && chattr +i "${_usEr}/static/control/cloudflare-dns-ssl-py.info"
              [ ! -L "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ] \
                && [ -f "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ] \
                && chattr +i "${_usEr}/static/control/cloudflare-dns-ssl-sh.info"
            fi
            export CF_DNS_SERVERS='8.8.8.8 8.8.4.4'
            export CF_SETTLE_TIME='30'
            export CF_DEBUG='true'
            ### Absolute clone targets and an exit-status gate. The old form
            ### keyed only on "hook file absent", so a FAILED clone (no network,
            ### or a hooks dir that already exists) still reached the root pip3
            ### install -- and that read a RELATIVE path resolved against an
            ### unchecked cd, i.e. whatever cwd the previous site leg left.
            ### pip runs packaging code as root; it may only ever see a tree
            ### this clone just created. chmod has no -h, so precheck the link.
            if [ ! -e "${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh" ]; then
              _apt_clean_update
              apt-get install gawk jq publicsuffix ldnsutils ${_aptYesUnth} 2> /dev/null
              mkdir -p ${_usEr}/tools/le/hooks
              if git clone https://github.com/omega8cc/dehydrated-hook-cloudflare \
                "${_usEr}/tools/le/hooks/cloudflare-sh" 2> /dev/null \
                && [ ! -L "${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh" ] \
                && [ -f "${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh" ]; then
                chmod 755 "${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh"
              fi
            fi
            if [ ! -e "${_usEr}/tools/le/hooks/cloudflare-py/hook.py" ]; then
              _apt_clean_update
              apt-get install python3-pip python-is-python3 ${_aptYesUnth} 2> /dev/null
              mkdir -p ${_usEr}/tools/le/hooks
              if git clone https://github.com/omega8cc/letsencrypt-cloudflare-hook \
                "${_usEr}/tools/le/hooks/cloudflare-py" 2> /dev/null \
                && [ ! -L "${_usEr}/tools/le/hooks/cloudflare-py/hook.py" ] \
                && [ -f "${_usEr}/tools/le/hooks/cloudflare-py/hook.py" ]; then
                chmod 755 "${_usEr}/tools/le/hooks/cloudflare-py/hook.py"
                if [ ! -L "${_usEr}/tools/le/hooks/cloudflare-py/requirements.txt" ] \
                  && [ -f "${_usEr}/tools/le/hooks/cloudflare-py/requirements.txt" ]; then
                  pip3 install -r "${_usEr}/tools/le/hooks/cloudflare-py/requirements.txt" 2> /dev/null
                fi
              fi
            fi
            if [ -e "${_usEr}/static/control/cloudflare-dns-ssl-py.info" ]; then
              _thisHook="${_usEr}/tools/le/hooks/cloudflare-py/hook.py"
            elif [ -e "${_usEr}/static/control/cloudflare-dns-ssl-sh.info" ]; then
              _thisHook="${_usEr}/tools/le/hooks/cloudflare-sh/cf-hook.sh"
            fi
            if [ -e "${_thisHook}" ] && [ -e "${_usEr}/tools/le/config" ]; then
              chattr +i ${_usEr}/tools/le/config
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
  _cleanup_ghost_vhosts
  _cleanup_ghost_drushrc
  for _Site in `find ${_usEr}/config/server_master/nginx/vhost.d \
    -maxdepth 1 -mindepth 1 -type f | sort`; do
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
    if [ -e "${_usEr}/config/server_master/nginx/vhost.d/${_Dom}" ]; then
      _Plx=$(cat ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} \
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
      ${_usEr}/config/server_master/nginx/vhost.d/${_Dom} 2>&1)
    if [[ "${_STATUS_TEST}" =~ "Do not reveal Aegir front-end URL here" ]]; then
      _STATUS_DISABLED=YES
      echo "${_Dom} site is DISABLED"
    fi
    if [ -e "${_usEr}/.drush/${_Dan}.alias.drushrc.php" ] \
      && [ "${_STATUS_DISABLED}" = "NO" ]; then
      echo "Dom is ${_Dom}"
      _Dir=$(cat ${_usEr}/.drush/${_Dan}.alias.drushrc.php \
        | grep "site_path'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      _DIR_CTRL_F="${_Dir}/modules/boa_site_control.ini"
      _Plr=$(cat ${_usEr}/.drush/${_Dan}.alias.drushrc.php \
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
          [ ! -e "${_codeBaseCheckDir}" ] && mkdir "${_codeBaseCheckDir}"
          if [ -x "/opt/local/bin/codebasecheck" ] \
            && [ -e "${_codeBaseCheckDir}" ] \
            && [ ! -e "${_codeBaseCheckCtrl}" ]; then
            codebasecheck "${_Plr}"
            wait
            touch "${_codeBaseCheckCtrl}"
          fi
        fi
        _fix_platform_control_files
        _fix_o_contrib_symlink
        if [ -e "${_Dir}/drushrc.php" ]; then
          cd ${_Dir}
          if [ "${_Dan}" = "hostmaster" ]; then
            if [ ! -f "${_usEr}/log/ctrl/plr.${_PlrID}.hm-fix-${_NOW}.info" ]; then
              su -s /bin/bash - ${_HM_U} -c "drush8 cc drush" &> /dev/null
              wait
              rm -rf ${_usEr}/.tmp/cache
              _run_drush8_hmr_cmd "dis update syslog dblog -y"
              _run_drush8_hmr_cmd "cron"
              _run_drush8_hmr_cmd "cache-clear all"
              _run_drush8_hmr_cmd "cache-clear all"
              _run_drush8_hmr_cmd "utf8mb4-convert-databases -y"
              touch ${_usEr}/log/ctrl/plr.${_PlrID}.hm-fix-${_NOW}.info
            fi
          fi
          if [ ! -z "${_Dan}" ] \
            && [ "${_Dan}" != "hostmaster" ]; then
            _if_site_db_conversion
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
                _fix_modules
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
            _fix_site_control_files
            if [ -e "${_Plr}/modules/o_contrib_seven" ] \
              || [ -e "${_Plr}/modules/o_contrib" ]; then
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
        ### The strip at the head of this iteration is many drush runs old by
        ### now, so re-strip before this late read/append leg. No-op on a
        ### regular file.
        _desymlink_planted "${_PLR_CTRL_F}"
        if [ -e "${_PLR_CTRL_F}" ]; then
          _FIX_PERMISSIONS_PRESENT=$(grep "fix_files_permissions_daily" \
            ${_PLR_CTRL_F} 2>&1)
          if [[ "${_FIX_PERMISSIONS_PRESENT}" =~ "fix_files_permissions_daily" ]]; then
            _DO_NOTHING=YES
          else
            echo ";fix_files_permissions_daily = TRUE" >> ${_PLR_CTRL_F}
          fi
          _FIX_PERMISSIONS_TEST=$(grep "^fix_files_permissions_daily = FALSE" \
            ${_PLR_CTRL_F} 2>&1)
          if [[ "${_FIX_PERMISSIONS_TEST}" =~ "fix_files_permissions_daily = FALSE" ]]; then
            _DONT_TOUCH_PERMISSIONS=YES
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
