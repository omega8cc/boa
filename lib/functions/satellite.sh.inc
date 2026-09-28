
export _tRee=dev
export _rLsn="BOA-5.88.855"
export _rlsE="${_rLsn}-${_tRee}"
export _bRnh="5.x-${_tRee}"
_hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"

#
# Download and extract from core archive.
_get_core_ext() {
  if [ ! -z "${1}" ]; then
    _max_attempts=10
    _attempt_num=1
    _success=0
    while [ ${_attempt_num} -le ${_max_attempts} ]; do
      [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Attempt ${_attempt_num} of ${_max_attempts}: Downloading $1..."
      if curl ${_crlGet} "https://${_USE_MIR}/core/$1" -o "$1"; then
        _success=1
        break
      else
        [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Attempt ${_attempt_num} failed."
        _attempt_num=$((_attempt_num+1))
        if [ "${_attempt_num}" -le "${_max_attempts}" ]; then
          [ "${_DEBUG_MODE}" = "YES" ] && _msg "DNLD: Retrying in 9 seconds..."
          sleep 9
        fi
      fi
    done
    if [ "${_success}" -eq 1 ]; then
      if [ ! -z "${2}" ]; then
        _extract_archive "${1}" "${2}"
      else
        _extract_archive "${1}"
      fi
    else
      _msg "OOPS: Failed to download https://${_USE_MIR}/core/$1 after ${_max_attempts} attempts"
      return 1  # Exit the function but continue the script
    fi
  fi
}

#
# Stage the pinned D6->D7 contrib kit from the mirror (Backdrop support).
# The provision-backdrop-d6-upgrade task copies module directories from this
# on-box cache and never downloads anything itself; without the staged kit
# the task fails closed in validate. One pinned tarball on the /core/ shelf
# (the pressflow-6.60.1 pattern), stamp-gated for idempotency, re-checked on
# every up-* run. A kit version bump means editing _D6D7_KIT_V here.
_stage_d6d7_kit() {
  local _D6D7_KIT_V="1.0.0"
  local _kitTar="d6-d7-contrib-kit-${_D6D7_KIT_V}.tar.gz"
  local _kitStamp="/data/all/000/kit-v-${_D6D7_KIT_V}.txt"
  local _kitProbe="/data/all/000/d6d7kit/cck/modules/content_migrate/content_migrate.module"
  if [ "${_BACKDROP_SUPPORT}" != "YES" ] || [ ! -d "/data/all/000" ]; then
    return 0
  fi
  if [ -e "${_kitStamp}" ] && [ -e "${_kitProbe}" ]; then
    return 0
  fi
  _msg "INFO: Staging the pinned D6->D7 contrib kit ${_D6D7_KIT_V}"
  rm -rf /opt/tmp/d6d7kit-stage
  mkdir -p /opt/tmp/d6d7kit-stage
  ### Subshell keeps the caller's working directory untouched.
  ( cd /opt/tmp/d6d7kit-stage && _get_core_ext "${_kitTar}" )
  if [ -e "/opt/tmp/d6d7kit-stage/d6-d7-contrib-kit-${_D6D7_KIT_V}/cck/modules/content_migrate/content_migrate.module" ]; then
    rm -rf /data/all/000/d6d7kit
    ### The stamp is written only after a fully successful move: a partial
    ### cross-filesystem mv must not latch an incomplete kit forever.
    if mv -f "/opt/tmp/d6d7kit-stage/d6-d7-contrib-kit-${_D6D7_KIT_V}" /data/all/000/d6d7kit; then
      chown -R root:root /data/all/000/d6d7kit
      find /data/all/000/d6d7kit -type d -exec chmod 0755 {} \; 2> /dev/null
      find /data/all/000/d6d7kit -type f -exec chmod 0644 {} \; 2> /dev/null
      rm -f /data/all/000/kit-v-*.txt
      echo "${_D6D7_KIT_V}" > "${_kitStamp}"
      _msg "INFO: D6->D7 contrib kit ${_D6D7_KIT_V} staged in /data/all/000/d6d7kit"
    else
      _msg "OOPS: D6->D7 contrib kit ${_D6D7_KIT_V} move into /data/all/000 failed; will retry on the next run"
    fi
  else
    _msg "OOPS: D6->D7 contrib kit ${_D6D7_KIT_V} download or extract failed; D6 upgrade tasks fail closed until it is staged"
  fi
  rm -rf /opt/tmp/d6d7kit-stage
}

#
# Stage the newest official Grav admin-bundle release zip for the
# per-instance upgrade channel: provision-grav-upgrade resolves the newest
# grav-admin-v*.zip under ${_ROOT}/static/grav-releases/ (the channel is
# mirror-fed; this box never talks to getgrav.org). Version from the same
# mirror stamp the platform build resolves; presence-gated for idempotency
# and re-checked on every up-* run. The resolver always picks the newest by
# version sort; the three newest staged zips are kept (a rollback restores
# the registered safety copy, never an old zip), older ones are pruned so
# the shelf does not grow by one release archive per Grav release forever.
_stage_grav_releases() {
  local _gVrn _gZip _gDir
  if [ "${_GRAV_SUPPORT}" != "YES" ] || [ -z "${_ROOT}" ]; then
    return 0
  fi
  _gVrn=$(curl ${_crlGet} "https://${_USE_MIR}/core/grav.txt" 2>/dev/null | tr -cd '0-9.')
  [ -z "${_gVrn}" ] && _gVrn="${_GRAV_V_FALLBACK}"
  _gZip="grav-admin-v${_gVrn}.zip"
  _gDir="${_ROOT}/static/grav-releases"
  if [ -e "${_gDir}/${_gZip}" ]; then
    return 0
  fi
  _msg "INFO: Staging the official Grav admin bundle ${_gVrn} for the upgrade channel"
  ### static/ is group-writable: grav-releases is made a real directory and
  ### everything below runs inside it, so a link put at any name there is
  ### never written through, chowned or pruned into.
  _acct_in_real_dir "${_ROOT}/static" _satellite_grav_dir_here
  if _acct_in_real_dir "${_gDir}" _satellite_grav_fetch_here "${_gZip}"; then
    _msg "INFO: Grav admin bundle staged: ${_gDir}/${_gZip}"
  else
    _msg "OOPS: Grav admin bundle ${_gVrn} download failed; the upgrade task refuses until staged"
  fi
}

#
# ./grav-releases made a real directory, run inside the real static/.
_satellite_grav_dir_here() {
  [ -L ./grav-releases ] && rm -f ./grav-releases
  [ -d ./grav-releases ] || mkdir -p ./grav-releases
}

#
# Fetch the bundle $1 into the current (pinned) grav-releases directory.
### Downloaded and checked in root's own temp directory, then put in place
### once: a truncated fetch must never be resolvable as the newest artefact
### (the unzip -l probe rejects short/garbage bodies too), and the directory
### is the account's, so the bundle is created there exclusively under a
### fresh name and renamed over the name, never written through a link or a
### FIFO put at either.
_satellite_grav_fetch_here() {
  local _w _rc=1
  rm -f -- "./.${1}.tmp"
  _w="$(mktemp -d /opt/tmp/.grav-stage.XXXXXX 2> /dev/null)" \
    && [ -d "${_w}" ] || return 1
  curl ${_crlGet} --max-time 600 -o "${_w}/${1}" \
    "https://${_USE_MIR}/core/${1}" 2> /dev/null
  if [ -s "${_w}/${1}" ] && unzip -l "${_w}/${1}" > /dev/null 2>&1 \
    && _satellite_put_stdin_here "${1}" 0644 "${_USER}:${_ACCG:-users}" \
    < "${_w}/${1}"; then
    chown -h "${_USER}:${_ACCG:-users}" . 2> /dev/null
    _prune_grav_releases .
    _rc=0
  fi
  rm -rf -- "${_w}"
  return "${_rc}"
}

#
# Keep the three newest staged official Grav admin-bundle zips; remove the
# rest. Version order, never mtime (a re-fetched old zip must not displace
# a newer one); only complete zips are considered (the .tmp of a fetch in
# flight is left alone).
_prune_grav_releases() {
  local _pDir="$1" _pZip _pKeep=3 _pN
  [ -d "${_pDir}" ] || return 0
  _pN=$(ls "${_pDir}"/grav-admin-v*.zip 2> /dev/null | wc -l)
  [ "${_pN}" -le "${_pKeep}" ] && return 0
  for _pZip in $(ls "${_pDir}"/grav-admin-v*.zip 2> /dev/null \
    | sed 's#.*/grav-admin-v##; s#\.zip$##' | sort -V | head -n -"${_pKeep}"); do
    rm -f "${_pDir}/grav-admin-v${_pZip}.zip"
    _msg "INFO: Pruned the staged Grav admin bundle ${_pZip} (three newest kept)"
  done
}

#
# Stage the native Backdrop CLI (bee) when the barracuda layer has not put
# it in place yet: bee is normally installed by _get_bee on barracuda runs,
# but the Backdrop platform build, hosting_backdrop and the drush extension
# are all octopus-gated, so an octopus-only box (or one whose barracuda cnf
# still carries a pre-migration NO) ends up with a working frontend and no
# backend CLI. Fetch-when-missing only; serial-driven refresh stays with
# the barracuda side, so the two never race over /opt/tools/bee.
_stage_bee() {
  if [ "${_BACKDROP_SUPPORT}" != "YES" ] || [ -e "/opt/tools/bee/bee.php" ]; then
    return 0
  fi
  _msg "INFO: Staging bee, the native Backdrop CLI"
  mkdir -p /opt/tools/bee
  rm -rf /opt/tools/bee/*
  ### Subshell keeps the caller's working directory untouched.
  ( cd /opt/tools/bee && _get_dev_ext "bee.tar.gz" )
  ### Root extraction preserves the build-box owner from the tarball, the
  ### directory itself included: root's whatever landed, like drush.
  chown -R root:root /opt/tools/bee
  if [ -e "/opt/tools/bee/bee.php" ]; then
    find /opt/tools/bee -type d -exec chmod 0755 {} \; &> /dev/null
    find /opt/tools/bee -type f -exec chmod 0644 {} \; &> /dev/null
    chmod 755 /opt/tools/bee/bee.php
  else
    _msg "OOPS: bee download failed; Backdrop site installs will not work yet"
  fi
}

#
# Count system CPUs.
_count_cpu() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _count_cpu"
    _debug_proc
  fi
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

#
# Find correct IP.
_find_correct_ip() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _find_correct_ip"
    _debug_proc
  fi
  if [ -e "/root/.found_correct_ipv4.cnf" ]; then
    _LOC_IP=$(cat /root/.found_correct_ipv4.cnf 2>/dev/null | tr -d '\n')
    ### Self-heal a cache orphaned by a server migration: when the cached
    ### value is no longer any local address AND the box carries a real
    ### public IPv4 (so never on 1:1-NAT topologies, where the egress IP
    ### is legitimately not local -- incl. CGNAT 100.64/10), re-probe at
    ### most ONCE per process with hard timeouts and replace the cache
    ### only on a validated, different dotted quad. A failed probe never
    ### invalidates a working cache. The city memo is dropped on replace,
    ### else it stays pinned to the old address forever.
    if [ -z "${_ipHealDone}" ] && [ -n "${_LOC_IP}" ]; then
      _ipHealDone=YES
      _locV4s=$(ip -4 addr show scope global 2>/dev/null \
        | awk '/inet /{sub(/\/.*/,"",$2); print $2}')
      if [ -n "${_locV4s}" ] && ! echo "${_locV4s}" | grep -qx "${_LOC_IP}"; then
        _hasPubV4=NO
        for _v4 in ${_locV4s}; do
          case "${_v4}" in
            10.*|127.*|169.254.*|192.168.*) ;;
            172.1[6-9].*|172.2[0-9].*|172.3[01].*) ;;
            100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) ;;
            *) _hasPubV4=YES ;;
          esac
        done
        if [ "${_hasPubV4}" = "YES" ]; then
          _freshV4=$(curl -4 -s --connect-timeout 5 --max-time 15 \
            https://api.ipify.org 2>/dev/null | tr -d '\n')
          if [[ ! "${_freshV4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            _freshV4=$(curl -4 -s --connect-timeout 5 --max-time 15 \
              http://ipv4.icanhazip.com 2>/dev/null | tr -d '\n')
          fi
          if [[ "${_freshV4}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
            && [ "${_freshV4}" != "${_LOC_IP}" ]; then
            _LOC_IP="${_freshV4}"
            echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
            rm -f /root/.found_correct_city.cnf
          fi
        fi
      fi
    fi
  else
    _LOC_IP=$(curl ${_crlGet} https://api.ipify.org | sed 's/[^0-9\.]//g')
    if [ -z "${_LOC_IP}" ]; then
      _LOC_IP=$(curl ${_crlGet} http://ipv4.icanhazip.com | sed 's/[^0-9\.]//g')
    fi
    ### Last-resort fallback removed in 2020 in favour of the remote
    ### probes, restored as a TAIL: when BOTH probes fail (mirror or
    ### network outage), resolve the box's own name locally -- callers
    ### assign it via _LOC_DOM right before calling. Single validated
    ### dotted quad only; anything else stays empty (fail-safe).
    if [ -z "${_LOC_IP}" ] && [ -n "${_LOC_DOM}" ]; then
      _LOC_IP=$(getent ahostsv4 "${_LOC_DOM}" 2>/dev/null | awk '{print $1; exit}')
      [[ "${_LOC_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || _LOC_IP=""
      ### Stock images map the FQDN to 127.0.1.1 in /etc/hosts; a loopback
      ### is never the box's public address, so leave empty instead.
      case "${_LOC_IP}" in 127.*) _LOC_IP="" ;; esac
    fi
    if [ ! -z "${_LOC_IP}" ]; then
      echo ${_LOC_IP} > /root/.found_correct_ipv4.cnf
    fi
  fi
  if [ -n "${_LOC_IP}" ] && grep -qE "${_LOC_IP}\s" /etc/hosts; then
    cp -af /etc/hosts /etc/.was.hosts
    sed -i "s/^${_LOC_IP}.*//g" /etc/hosts
    [ -x "/etc/init.d/unbound" ] && [ ! -e "/usr/etc/unbound/unbound.conf.d" ] && mkdir -p /usr/etc/unbound/unbound.conf.d
    [ -x "/etc/init.d/unbound" ] && service unbound restart &> /dev/null
  fi
}

#
# Tune FPM workers.
_satellite_tune_fpm_workers() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_tune_fpm_workers"
    _debug_proc
  fi
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
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "DEBUG: _L_PHP_FPM_WORKERS is ${_L_PHP_FPM_WORKERS}"
    _msg "DEBUG: _PHP_FPM_TIMEOUT is ${_PHP_FPM_TIMEOUT}"
  fi
}

#
# Update web user.
_satellite_web_user_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_web_user_update"
    _debug_proc
  fi
  _isTest="${_WEB}"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ]; then
    _T_HD="/home/${_WEB}/.drush"
    _T_TP="/home/${_WEB}/.tmp"
    _T_TS="/home/${_WEB}/.aws"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "DEBUG: ${_WEB} in _satellite_web_user_update A"
    fi
    # /home is root's, so the home itself cannot be swapped; every name in it
    # is the web user's (a compromised site in the pool can plant one at any
    # moment): past the link strip, root works on .lock, .drush and the stamp
    # only inside the real directories, creating files exclusively
    _T_HR="$(cd -P -- /home 2> /dev/null && pwd -P)/${_WEB}"
    # held off only by a lock an update wrote: a regular root file at .lock
    # younger than an hour; a name the web user planted there, or a lock an
    # interrupted pass left, is replaced by this update's own
    _T_LK=NO
    if [ -f "/home/${_WEB}/.lock" ] && [ ! -L "/home/${_WEB}/.lock" ] \
      && [ "$(stat -c %u "/home/${_WEB}/.lock" 2> /dev/null)" = "0" ] \
      && [ -n "$(find "/home/${_WEB}/.lock" -maxdepth 0 -mmin -60 2> /dev/null)" ]; then
      _T_LK=YES
    fi
    if [ -d "/home/${_WEB}/" ] && [ ! -L "/home/${_WEB}" ] && [ "${_T_LK}" = "NO" ]; then
      chattr -i /home/${_WEB} &> /dev/null
      for _t_n in .drush .tmp .aws .lock; do
        if [ -L "/home/${_WEB}/${_t_n}" ]; then
          rm -f "/home/${_WEB}/${_t_n}"
        fi
      done
      mkdir -p /home/${_WEB}/.{tmp,drush,aws}
      ( cd -P -- "/home/${_WEB}" 2> /dev/null && [ "$(pwd -P)" = "${_T_HR}" ] || exit 0
        rm -f -- ./.lock
        echo | dd of=./.lock conv=excl status=none 2> /dev/null )
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "DEBUG: ${_WEB} in _satellite_web_user_update B"
        _msg "DEBUG: ARG1 is $1 in _satellite_web_user_update B"
      fi
      _isTest="$1"
      _isTest=${_isTest//[^a-z0-9]/}
      if [ ! -z "${_isTest}" ]; then
        _T_PV=$1
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DEBUG: _T_PV is ${_T_PV} in _satellite_web_user_update C"
        fi
      fi
      # the stamp records the pool version the user was set up for (FPM runs
      # on its version's ini and the pool's own temp paths); the php.ini kept
      # beside it is a placeholder naming no PHP version, which the Octopus
      # and ltd worker of earlier releases read as the web user being in
      # place (without one they make it anew, home included). Its text is the
      # ltd worker's _DRUSH_INI_PLACEHOLDER, byte for byte.
      if [ -z "${_T_PV}" ] || [ ! -e "/opt/php${_T_PV}/etc/php${_T_PV}.ini" ]; then
        _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
        for e in ${_PHP_V}; do
          if [ -e "/opt/php${e}/etc/php${e}.ini" ]; then
            _T_PV=${e}
            break
          fi
        done
      fi
      # the placeholder and the stamp are put as the web user's from the
      # start (0444 and 0644, owner and mode set through the handle that
      # created them, _satellite_put_stdin_here), and the flag on php.ini is
      # changed through a handle (_ACCT_CHATTR_PL): a hard link the web user
      # renames over either name is never handed over or locked
      ( cd -P -- "${_T_HD}" 2> /dev/null && [ "$(pwd -P)" = "${_T_HR}/.drush" ] || exit 0
        chattr -i . 2> /dev/null
        [ -f ./php.ini ] && [ ! -L ./php.ini ] \
          && perl -e "${_ACCT_CHATTR_PL}" - ./php.ini 2> /dev/null
        # a link the web user put at the name goes first (unlink never
        # follows it); a released copy of this upkeep wrote through one
        [ -L ./php.ini ] && rm -f -- ./php.ini
        if [ ! -e ./php.ini ] && [ ! -L ./php.ini ]; then
          printf '%s\n' "; no per-account php.ini: the CLI runs on the global ini (kept for older releases)" \
            | _satellite_put_stdin_here php.ini 0444 "${_WEB}:www-data"
        fi
        if [ ! -z "${_T_PV}" ]; then
          rm -f -- ./.ctrl.php*
          echo | _satellite_put_stdin_here ".ctrl.php${_T_PV}.${_xSrl}.pid" \
            0644 "${_WEB}:www-data"
        fi )
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "DEBUG: _T_PV is ${_T_PV} in _satellite_web_user_update D"
      fi
      chmod 700 /home/${_WEB}/
      # handed over as chown -R did, from inside the real home, never a
      # link or a file the web user hard-linked there (_satellite_reown_here)
      _acct_in_real_dir "/home/${_WEB}" _satellite_reown_here "${_WEB}:www-data"
      ( cd -P -- "${_T_HD}" 2> /dev/null && [ "$(pwd -P)" = "${_T_HR}/.drush" ] || exit 0
        chmod 550 .
        chattr +i . 2> /dev/null
        [ -f ./php.ini ] && [ ! -L ./php.ini ] \
          && perl -e "${_ACCT_CHATTR_PL}" + ./php.ini 2> /dev/null )
      ( cd -P -- "/home/${_WEB}" 2> /dev/null && [ "$(pwd -P)" = "${_T_HR}" ] || exit 0
        rm -f -- ./.lock )
      chattr +i /home/${_WEB}/
    fi
  fi
}

#
# Remove web user.
_satellite_remove_web_user() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_remove_web_user"
    _debug_proc
  fi
  if [ -d "/home/${_WEB}/" ] || [ "$1" = "clean" ]; then
    # every name in the home is the web user's: unlocked from inside the
    # real home as chattr -i -R unlocked it, never through a link, nor on a
    # file the web user hard-linked there (_satellite_unlock_tree_here)
    _acct_in_real_dir "/home/${_WEB}" _satellite_unlock_tree_here
    # .drush on '.' from inside it, so nothing swapped in for it is unlocked
    if [ -d "/home/${_WEB}/.drush/" ] && [ ! -L "/home/${_WEB}/.drush" ]; then
      _acct_in_real_dir "/home/${_WEB}/.drush" chattr -i .
    fi
    mkdir -p ${_vBs}/zombie/deleted
    # only this user's agent (none for a user that never existed): -f
    # matched every gpg-agent on the box
    id -u "${_WEB}" &> /dev/null && pkill -9 -u "${_WEB}" gpg-agent &> /dev/null
    deluser --remove-home --backup-to ${_vBs}/zombie/deleted ${_WEB} &> /dev/null
    if [ -d "/home/${_WEB}/" ]; then
      rm -rf /home/${_WEB}/ &> /dev/null
    fi
  fi
}

#
# Add web user.
_satellite_create_web_user() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_create_web_user"
    _debug_proc
  fi
  # an account with its home in place is updated; a missing account or home
  # is made anew
  _T_ID_EXISTS=$(getent passwd ${_WEB} 2>&1)
  if [ ! -z "${_T_ID_EXISTS}" ] && [ -d "/home/${_WEB}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "DEBUG: ARG1 is $1 in _satellite_create_web_user B"
    fi
    _satellite_web_user_update "$1"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "DEBUG: ARG1 is $1 in _satellite_create_web_user C"
    fi
    _satellite_remove_web_user "clean"
    adduser --force-badname --system --ingroup www-data --home /home/${_WEB} ${_WEB} &> /dev/null
    _satellite_web_user_update "$1"
  fi
  # A pool user made anew drops every group listing: once the account holds
  # its own web group, the pool is listed in it before its pool file is
  # written and FPM reloaded, or its workers could not read settings.php.
  _satellite_wg_grant "${_WEB}"
}

#
# An identity of an account that holds its own web group is listed in that
# group (supplementary, verified in the group database, never by id -nG);
# nothing to do while the account has none. $1 = the identity.
_satellite_wg_grant() {
  local _st _g
  _st=$(_web_group_state "${1}")
  case "${_st%% *}" in
    held|converted|phaseb) ;;
    *) return 0 ;;
  esac
  _g="${_st##* }"
  getent group "${_g}" | cut -d: -f4 | tr ',' '\n' | grep -qxF "${1}" && return 0
  usermod -aG "${_g}" "${1}" &> /dev/null
  getent group "${_g}" | cut -d: -f4 | tr ',' '\n' | grep -qxF "${1}" && return 0
  _msg "${_STATUS} A: ALRT: ${1} could not be listed in ${_g}"
  return 1
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
# Tune FPM configuration.
_satellite_tune_fpm_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_tune_fpm_config"
    _debug_proc
  fi
  _satellite_tune_fpm_workers

  _LIM_FPM="${_L_PHP_FPM_WORKERS}"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "DEBUG: _LIM_FPM is ${_LIM_FPM}"
  fi

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

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "DEBUG: _LIM_FPM is ${_LIM_FPM}"
    _msg "DEBUG: _CLIENT_OPTION is ${_CLIENT_OPTION}"
  fi

  if [ ! -z "${_CLIENT_CORES}" ] && [ "${_CLIENT_CORES}" -ge 1 ]; then
    ### the digits of the account's cores.txt, as before, taken by tr (a
    ### pattern substitution over the whole file costs the square of its
    ### length), leading zeros dropped and at most nine kept, so the
    ### product below stays a number
    if [ -e "${_ROOT}/log/cores.txt" ]; then
      _CLIENT_CORES=$(_acct_read_in "${_ROOT}/log" cores.txt \
        | tr -cd '0-9' | sed 's/^0*//' | head -c 9)
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

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "DEBUG: _LIM_FPM is ${_LIM_FPM}"
    _msg "DEBUG: _CHILD_MAX_FPM is ${_CHILD_MAX_FPM}"
    _msg "DEBUG: _FPM_MEM_LIMIT is ${_FPM_MEM_LIMIT}"
  fi

  _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
  if [ -z "${_PHP_SV}" ]; then
    _PHP_SV=84
  fi
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  _PHP_OLD_SV=
  for e in ${_PHP_V}; do
    if [ -e "/opt/php${e}/etc/pool.d/${_USER}.conf" ]; then
      _PHP_OLD_SV=${e}
    fi
  done
  if [ ! -e "/var/xdrago/conf/fpm-pool-foo-multi.conf" ]; then
    mkdir -p /var/xdrago/conf
  fi
  cp -af ${_bldPth}/aegir/conf/php/fpm-pool-foo-multi.conf /var/xdrago/conf/
  cp -af ${_bldPth}/aegir/conf/php/fpm-pool-foo.conf /var/xdrago/conf/
  if [ ! -z "${_PHP_FPM_TIMEOUT}" ] && [ ! -z "${_PHP_SV}" ]; then
    # Guard on the INTERPRETER, not the pool.d dir: BOA creates pool.d for
    # every known PHP version regardless of what is installed, so a dir test
    # passes on essentially any box. With a pin to a version that is not
    # installed the delete sweep would succeed and the pool would be written
    # for a PHP that cannot run it, leaving the account without a working
    # pool (nginx 502). A bad pin must degrade to "unchanged", never "gone".
    if [ -e "/var/xdrago/conf/fpm-pool-foo.conf" ] \
      && [ -x "/opt/php${_PHP_SV}/bin/php" ] \
      && [ -d "/opt/php${_PHP_SV}/etc/pool.d" ]; then
      rm -f /opt/php*/etc/pool.d/${_USER}.conf
      cp -af /var/xdrago/conf/fpm-pool-foo.conf /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf
    fi
    if [ -e "/opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf" ]; then
      ### create or update special system user if needed
      # its stamp records the pool version it was set up for, this serial
      if getent passwd "${_WEB}" &> /dev/null && [ -d "/home/${_WEB}" ]; then
        if [ ! -e "/home/${_WEB}/.drush/.ctrl.php${_PHP_SV}.${_xSrl}.pid" ]; then
          _satellite_web_user_update "${_PHP_SV}"
        fi
      else
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "DEBUG: _PHP_SV is ${_PHP_SV} in _satellite_create_web_user A"
        fi
        _satellite_create_web_user "${_PHP_SV}"
      fi
      ### create or update special system user if needed
      sed -i "s/.ftp/.web/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      sed -i "s/\/data\/disk\/foo\/.tmp/\/home\/foo.web\/.tmp/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      sed -i "s/foo/${_USER}/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      sed -i "s/THISPOOL/${_USER}/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
      if [[ "${_PHP_SV}" == 8* ]] && [ -e "/opt/etc/fpm/fpm-pool-common-modern.conf" ]; then
        sed -i "s/fpm-pool-common.conf/fpm-pool-common-modern.conf/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
        wait
      elif [[ "${_PHP_SV}" == 7* ]] && [ -e "/opt/etc/fpm/fpm-pool-common-legacy.conf" ]; then
        sed -i "s/fpm-pool-common.conf/fpm-pool-common-legacy.conf/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
        wait
      fi
      if [ ! -z "${_PHP_FPM_DENY}" ]; then
        sed -i "s/passthru,/${_PHP_FPM_DENY},/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
        wait
      fi
    fi
    _PHP_TO="${_PHP_FPM_TIMEOUT}s"
    sed -i "s/180s/${_PHP_TO}/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
    wait
    if [ ! -z "${_CHILD_MAX_FPM}" ] && [ "${_CHILD_MAX_FPM}" -ge 8 ]; then
      sed -i "s/pm.max_children =.*/pm.max_children = ${_CHILD_MAX_FPM}/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
    else
      sed -i "s/pm.max_children =.*/pm.max_children = 8/g" /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf &> /dev/null
      wait
    fi
    if [ -n "${_FPM_MEM_LIMIT}" ] && [ "${_FPM_MEM_LIMIT}" -ge 64 ]; then
      echo "php_admin_value[memory_limit] = ${_FPM_MEM_LIMIT}M" >> /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf
      wait
    fi
    # Once the account's identities have left www-data, its pool runs in the
    # account's own web group (after the include, which sets www-data). A
    # group that does not resolve would fail this whole PHP version on
    # reload, so it is written only when it does.
    _T_WGS=$(_web_group_state "${_USER}")
    if [ "${_T_WGS%% *}" = "phaseb" ] && [ "${_T_WGS##* }" = "wg-${_USER}" ] \
      && getent group "${_T_WGS##* }" > /dev/null 2>&1; then
      echo "group = ${_T_WGS##* }" >> /opt/php${_PHP_SV}/etc/pool.d/${_USER}.conf
    fi
    mkdir -p /var/www/phpcache/${_USER}/${_USER}.{85,84,83,82,81,80,74,73,72,71,70,56}
    _T_WG=$(_web_group "${_USER}")
    [ -n "${_T_WG}" ] && chgrp "${_T_WG}" /var/www/phpcache/${_USER}/${_USER}.{85,84,83,82,81,80,74,73,72,71,70,56}
    chmod 770 /var/www/phpcache/${_USER}/${_USER}.{85,84,83,82,81,80,74,73,72,71,70,56}
    if [ ! -d "${_ROOT}/tmp" ]; then
      mkdir -p ${_ROOT}/tmp
      _acct_in_real_dir "${_ROOT}/tmp" \
        chown -h "${_USER}:${_ACCG:-users}" . &> /dev/null
    fi
    if [ ! -z "${_PHP_OLD_SV}" ] \
      && [ -e "/etc/init.d/php${_PHP_OLD_SV}-fpm" ]; then
      _mrun "service php${_PHP_OLD_SV}-fpm reload"
    fi
    if [ -e "/etc/init.d/php${_PHP_SV}-fpm" ]; then
      _mrun "service php${_PHP_SV}-fpm reload"
    fi
  fi
}

#
# Make sure that username is unique and not restricted.
_satellite_check_id() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_check_id"
    _debug_proc
  fi
  _ID_EXISTS=$(getent passwd ${_USER} 2>&1)
  if [ -z "${_ID_EXISTS}" ]; then
    _DO_NOTHING=YES
  elif [[ "${_ID_EXISTS}" =~ "${_USER}" ]]; then
    _msg "ERROR: ${_USER} username is already taken"
    _msg "Please choose different _USER"
    _clean_pid_exit
  else
    _msg "ERROR: ${_USER} username check failed"
    _msg "Please try different _USER"
    _clean_pid_exit
  fi
  if [ "${_USER}" = "admin" ] \
    || [ "${_USER}" = "hostmaster" ] \
    || [ "${_USER}" = "barracuda" ] \
    || [ "${_USER}" = "octopus" ] \
    || [ "${_USER}" = "boa" ] \
    || [ "${_USER}" = "all" ]; then
    _msg "ERROR: ${_USER} is a restricted username"
    _msg "ERROR: Please choose a different _USER"
    _clean_pid_exit
  elif [[ "${_USER}" =~ "drupal" ]] \
    || [[ "${_USER}" =~ "drush" ]] \
    || [[ "${_USER}" =~ "sites" ]] \
    || [[ "${_USER}" =~ "default" ]]; then
    _msg "ERROR: ${_USER} includes restricted keyword"
    _msg "ERROR: Please choose a different _USER"
    _clean_pid_exit
  fi
  _REGEX="^[[:digit:]]"
  if [[ "${_USER}" =~ "${_REGEX}" ]]; then
    _msg "ERROR: ${_USER} is a wrong username"
    _msg "ERROR: The correct username should start with a letter, not digit"
    _clean_pid_exit
  fi
  # wg-<account> is every account's web group: an account of that name would
  # get its per-instance group under another account's web group name. A
  # dot would make the account read as the one named before it (an
  # account's identities are <account>.<name>).
  if [[ "${_USER}" == wg-* ]] || [[ "${_USER}" == *.* ]]; then
    _msg "ERROR: ${_USER} begins with wg-, or holds a dot; both are reserved"
    _msg "ERROR: Please choose a different _USER"
    _clean_pid_exit
  fi
}

#
# Enable chattr.
_enable_chattr() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _enable_chattr"
    _debug_proc
  fi
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    ### A *.ftp home is never immutable, so every name in it is the login's:
    ### each flag is set inside the real directory, on a name that is not a
    ### link (chattr refuses a link named by its bare path, but follows one
    ### behind a trailing slash or on the way); .bazaar on '.' from inside
    ### it, so a file swapped in for it after the test is never locked.
    _acct_in_real_dir "/home/$1/platforms" _satellite_chattr_all_here +i
    _acct_in_real_dir "/home/$1/.drush" _satellite_chattr_drush_here +i
    if [ -d "/home/$1/.bazaar/" ] && [ ! -L "/home/$1/.bazaar" ]; then
      _acct_in_real_dir "/home/$1/.bazaar" chattr +i .
    fi
  fi
}

#
# Disable chattr.
_disable_chattr() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _disable_chattr"
    _debug_proc
  fi
  _isTest="$1"
  _isTest=${_isTest//[^a-z0-9]/}
  if [ ! -z "${_isTest}" ] && [ -d "/home/$1/" ]; then
    ### The same names as _enable_chattr, cleared the same way: inside the
    ### real directory, never through a link.
    _acct_in_real_dir "/home/$1/platforms" _satellite_chattr_all_here -i
    _acct_in_real_dir "/home/$1/.drush" _satellite_chattr_drush_here -i
    if [ -d "/home/$1/.bazaar/" ] && [ ! -L "/home/$1/.bazaar" ]; then
      _acct_in_real_dir "/home/$1/.bazaar" chattr -i .
    fi
  fi
}

#
# Read or create Octopus cnf file.
_satellite_cnf() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_cnf"
    _debug_proc
  fi
  # The omega8.cc-hosted fleet (hostname ends in .aegir.cc) defaults the
  # per-account ghost-cleanup flags to YES, mirroring the barracuda.cnf seed
  # in _barracuda_cnf: only when the line is not already present in the cnf,
  # so the values are written as ordinary octopus.cnf lines and stay
  # operator-toggleable -- never forced on each run. Covers INIT (no cnf yet)
  # and upgrade (resolved before the append-missing pass below persists it),
  # so accounts created on a hosted box are born with the fleet defaults.
  if [[ "${_hName}" =~ ".aegir.cc"($) ]]; then
    grep -q "^_GHOST_PLATFORMS_CLEANUP=" ${_octCnf} 2>/dev/null || _GHOST_PLATFORMS_CLEANUP=YES
    grep -q "^_GHOST_VHOSTS_CLEANUP=" ${_octCnf} 2>/dev/null || _GHOST_VHOSTS_CLEANUP=YES
    grep -q "^_GHOST_SITES_CLEANUP=" ${_octCnf} 2>/dev/null || _GHOST_SITES_CLEANUP=YES
    grep -q "^_GHOST_SITE_FILES_CLEANUP=" ${_octCnf} 2>/dev/null || _GHOST_SITE_FILES_CLEANUP=YES
    grep -q "^_GHOST_ALIASES_CLEANUP=" ${_octCnf} 2>/dev/null || _GHOST_ALIASES_CLEANUP=YES
  fi
  # A hand-seeded cnf -- the documented opt-out creates /root/.oN.octopus.cnf
  # before boa in-octopus with _INSTANCE_GROUP=NO -- carries a line or two,
  # not the forty-odd the creation branch writes, and the append pass below
  # persists only a subset: the account's first upgrade then refused on the
  # email that was never written. A cnf without _MY_OCTO_EMAIL is such a
  # seed: keep its lines, write the full set, lay the seeded lines back.
  _octSeed=""
  _octSeeded=NO
  if [ -e "${_octCnf}" ] && ! grep -q "^_MY_OCTO_EMAIL=" ${_octCnf} 2> /dev/null; then
    _octSeeded=YES
  fi
  if [ "${_octSeeded}" = "YES" ] || [ ! -e "${_octCnf}" ]; then
    if [[ "${_MY_OCTO_EMAIL}" =~ "omega8.cc" ]] \
      || [[ "${_CLIENT_EMAIL}" =~ "omega8.cc" ]]; then
      _if_hosted_sys
      if [ "${_hostedSys}" != "YES" ]; then
        _msg "EXIT: You must enter **your** valid email address"
        _msg "EXIT: in the _MY_OCTO_EMAIL **and** _CLIENT_EMAIL variables"
        _clean_pid_exit
      fi
    fi
    ### A client control-panel account can never exist when _CLIENT_EMAIL
    ### equals _MY_OCTO_EMAIL: the uid-1 super-admin already owns that
    ### address and hosting_client refuses a duplicate, so the welcome
    ### email would ship control-panel login details for an account that
    ### does not exist. Refuse up front, before anything is created.
    ### Compared with mutt-era escaping stripped, so a\@b matches a@b.
    if [ -n "${_CLIENT_EMAIL}" ] \
      && [ "${_MY_OCTO_EMAIL//\\/}" = "${_CLIENT_EMAIL//\\/}" ]; then
      _msg "EXIT: _CLIENT_EMAIL must not be the same address as _MY_OCTO_EMAIL"
      _msg "EXIT: the control panel needs a separate client email for its account"
      _clean_pid_exit
    fi
    # The seed is read and removed only past the two gates above: an exit
    # there took the operator's file with it, and the re-run then installed
    # with the box defaults.
    if [ "${_octSeeded}" = "YES" ]; then
      _octSeed=$(grep -E '^_[A-Z0-9_]+=' ${_octCnf} 2> /dev/null)
      rm -f ${_octCnf}
      _msg "NOTE: ${_octCnf} was hand-seeded; completing it with the install defaults, seeded lines kept"
    fi
    _msg "INFO: Creating your ${_octCnf} config file"
    sleep 1
    echo "###"                                                   > ${_octCnf}
    echo "### Configuration created on ${_NOW} with"            >> ${_octCnf}
    echo "### Octopus version ${_X_VERSION}"                    >> ${_octCnf}
    echo "###"                                                  >> ${_octCnf}
    echo "_USER=\"${_USER}\""                                   >> ${_octCnf}
    echo "_MY_OCTO_EMAIL=\"${_MY_OCTO_EMAIL}\""                 >> ${_octCnf}
    echo "_PLATFORMS_LIST=\"${_PLATFORMS_LIST}\""               >> ${_octCnf}
    echo "_AUTOPILOT=${_AUTOPILOT}"                             >> ${_octCnf}
    echo "_HM_ONLY=${_HM_ONLY}"                                 >> ${_octCnf}
    echo "_PLATFORMS_ONLY=${_PLATFORMS_ONLY}"                   >> ${_octCnf}
    echo "_BACKDROP_SUPPORT=${_BACKDROP_SUPPORT}"               >> ${_octCnf}
    echo "### _BACKDROP_SUPPORT_MIGRATED"                       >> ${_octCnf}
    echo "_GRAV_SUPPORT=${_GRAV_SUPPORT}"                       >> ${_octCnf}
    echo "_TXP_SUPPORT=${_TXP_SUPPORT}"                         >> ${_octCnf}
    echo "_DEBUG_MODE=${_DEBUG_MODE}"                           >> ${_octCnf}
    echo "_DL_MODE=\"${_DL_MODE}\""                             >> ${_octCnf}
    echo "_MY_OWNIP=${_MY_OWNIP}"                               >> ${_octCnf}
    echo "_FORCE_GIT_MIRROR=\"${_FORCE_GIT_MIRROR}\""           >> ${_octCnf}
    echo "_THIS_DB_HOST=${_THIS_DB_HOST}"                       >> ${_octCnf}
    echo "_THIS_DB_PORT=${_THIS_DB_PORT}"                       >> ${_octCnf}
    echo "_DNS_SETUP_TEST=${_DNS_SETUP_TEST}"                   >> ${_octCnf}
    echo "_HOT_SAUCE=${_HOT_SAUCE}"                             >> ${_octCnf}
    echo "_USE_CURRENT=${_USE_CURRENT}"                         >> ${_octCnf}
    echo "_DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS}" >> ${_octCnf}
    echo "_GHOST_PLATFORMS_CLEANUP=${_GHOST_PLATFORMS_CLEANUP}" >> ${_octCnf}
    echo "_GHOST_VHOSTS_CLEANUP=${_GHOST_VHOSTS_CLEANUP}"       >> ${_octCnf}
    echo "_GHOST_SITES_CLEANUP=${_GHOST_SITES_CLEANUP}"         >> ${_octCnf}
    echo "_GHOST_SITE_FILES_CLEANUP=${_GHOST_SITE_FILES_CLEANUP}" >> ${_octCnf}
    echo "_GHOST_ALIASES_CLEANUP=${_GHOST_ALIASES_CLEANUP}"     >> ${_octCnf}
    echo "_INSTANCE_GROUP=${_INSTANCE_GROUP:-YES}"              >> ${_octCnf}
    echo "_SEND_UPGRADE_EMAIL=${_SEND_UPGRADE_EMAIL:-YES}"      >> ${_octCnf}
    echo "_DEL_OLD_BACKUPS=${_DEL_OLD_BACKUPS}"                 >> ${_octCnf}
    echo "_DEL_OLD_TMP=${_DEL_OLD_TMP}"                         >> ${_octCnf}
    echo "_LOCAL_NETWORK_IP=${_LOCAL_NETWORK_IP}"               >> ${_octCnf}
    echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}"                 >> ${_octCnf}
    echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}"                 >> ${_octCnf}
    echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}"                 >> ${_octCnf}
    echo "_PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT}"                 >> ${_octCnf}
    echo "_PHP_FPM_MAX_CHILDREN_FORCE=${_PHP_FPM_MAX_CHILDREN_FORCE:-AUTO}" >> ${_octCnf}
    echo "_PHP_FPM_MEMORY_LIMIT_FORCE=${_PHP_FPM_MEMORY_LIMIT_FORCE:-AUTO}" >> ${_octCnf}
    echo "_PHP_FPM_RAM_PCT=${_PHP_FPM_RAM_PCT:-AUTO}"           >> ${_octCnf}
    echo "_PHP_FPM_CPU_FACTOR=${_PHP_FPM_CPU_FACTOR:-AUTO}"     >> ${_octCnf}
    echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\""                   >> ${_octCnf}
    echo "_LTD_PLATFORM_CLIENTS=\"${_LTD_PLATFORM_CLIENTS}\""   >> ${_octCnf}
    echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}"               >> ${_octCnf}
    echo "_SQL_CONVERT=${_SQL_CONVERT}"                         >> ${_octCnf}
    echo "_RESERVED_RAM=${_RESERVED_RAM}"                       >> ${_octCnf}
    echo "###"                                                  >> ${_octCnf}
    echo "_DOMAIN=\"${_DOMAIN}\""                               >> ${_octCnf}
    echo "_CLIENT_EMAIL=\"${_CLIENT_EMAIL}\""                   >> ${_octCnf}
    echo "_CLIENT_OPTION=\"${_CLIENT_OPTION}\""                 >> ${_octCnf}
    echo "_CLIENT_SUBSCR=\"${_CLIENT_SUBSCR}\""                 >> ${_octCnf}
    echo "_CLIENT_CORES=\"${_CLIENT_CORES}\""                   >> ${_octCnf}
    echo "###"                                                  >> ${_octCnf}
    if [ -n "${_octSeed}" ]; then
      while IFS= read -r _seedLine; do
        [ -n "${_seedLine}" ] || continue
        _seedKey="${_seedLine%%=*}"
        _seedRep=$(printf '%s' "${_seedLine}" | sed 's/[&|\\]/\\&/g')
        if grep -q "^${_seedKey}=" ${_octCnf} 2> /dev/null; then
          sed -i "s|^${_seedKey}=.*|${_seedRep}|" ${_octCnf}
        else
          echo "${_seedLine}" >> ${_octCnf}
        fi
        # this run reads the switch from the variable, not from the file
        if [ "${_seedKey}" = "_INSTANCE_GROUP" ]; then
          _INSTANCE_GROUP=$(printf '%s' "${_seedLine#*=}" | tr -d '"'"'"' ')
        fi
      done <<< "${_octSeed}"
    fi
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Reading your ${_octCnf} config file"
    fi
    sleep 1
    _PHP_FPM_WORKERS_TEST=$(grep _PHP_FPM_WORKERS ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_WORKERS_TEST}" =~ "_PHP_FPM_WORKERS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_WORKERS=${_PHP_FPM_WORKERS}" >> ${_octCnf}
    fi
    _PHP_FPM_MAX_CHILDREN_FORCE_TEST=$(grep _PHP_FPM_MAX_CHILDREN_FORCE ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_MAX_CHILDREN_FORCE_TEST}" =~ "_PHP_FPM_MAX_CHILDREN_FORCE" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_MAX_CHILDREN_FORCE=${_PHP_FPM_MAX_CHILDREN_FORCE:-AUTO}" >> ${_octCnf}
    fi
    _PHP_FPM_MEMORY_LIMIT_FORCE_TEST=$(grep _PHP_FPM_MEMORY_LIMIT_FORCE ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_MEMORY_LIMIT_FORCE_TEST}" =~ "_PHP_FPM_MEMORY_LIMIT_FORCE" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_MEMORY_LIMIT_FORCE=${_PHP_FPM_MEMORY_LIMIT_FORCE:-AUTO}" >> ${_octCnf}
    fi
    _PHP_FPM_RAM_PCT_TEST=$(grep _PHP_FPM_RAM_PCT ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_RAM_PCT_TEST}" =~ "_PHP_FPM_RAM_PCT" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_RAM_PCT=${_PHP_FPM_RAM_PCT:-AUTO}" >> ${_octCnf}
    fi
    _PHP_FPM_CPU_FACTOR_TEST=$(grep _PHP_FPM_CPU_FACTOR ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_CPU_FACTOR_TEST}" =~ "_PHP_FPM_CPU_FACTOR" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_CPU_FACTOR=${_PHP_FPM_CPU_FACTOR:-AUTO}" >> ${_octCnf}
    fi
    _PHP_FPM_TIMEOUT_TEST=$(grep _PHP_FPM_TIMEOUT ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_TIMEOUT_TEST}" =~ "_PHP_FPM_TIMEOUT" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_TIMEOUT=${_PHP_FPM_TIMEOUT}" >> ${_octCnf}
    fi
    _PHP_FPM_DENY_TEST=$(grep _PHP_FPM_DENY ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_DENY_TEST}" =~ "_PHP_FPM_DENY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_DENY=\"${_PHP_FPM_DENY}\"" >> ${_octCnf}
    fi
     _RESERVED_RAM_TEST=$(grep _RESERVED_RAM ${_octCnf} 2>&1)
    if [[ "${_RESERVED_RAM_TEST}" =~ "_RESERVED_RAM" ]]; then
      _DO_NOTHING=YES
    else
      echo "_RESERVED_RAM=${_RESERVED_RAM}" >> ${_octCnf}
    fi
    _PHP_FPM_VERSION_TEST=$(grep _PHP_FPM_VERSION ${_octCnf} 2>&1)
    if [[ "${_PHP_FPM_VERSION_TEST}" =~ "_PHP_FPM_VERSION" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_FPM_VERSION=${_PHP_FPM_VERSION}" >> ${_octCnf}
    fi
    _PHP_CLI_VERSION_TEST=$(grep _PHP_CLI_VERSION ${_octCnf} 2>&1)
    if [[ "${_PHP_CLI_VERSION_TEST}" =~ "_PHP_CLI_VERSION" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PHP_CLI_VERSION=${_PHP_CLI_VERSION}" >> ${_octCnf}
    fi
    _PLATFORMS_ONLY_TEST=$(grep _PLATFORMS_ONLY ${_octCnf} 2>&1)
    if [[ "${_PLATFORMS_ONLY_TEST}" =~ "_PLATFORMS_ONLY" ]]; then
      _DO_NOTHING=YES
    else
      echo "_PLATFORMS_ONLY=${_PLATFORMS_ONLY}" >> ${_octCnf}
    fi
    _BACKDROP_SUPPORT_TEST=$(grep "^_BACKDROP_SUPPORT=" ${_octCnf} 2>&1)
    if [[ "${_BACKDROP_SUPPORT_TEST}" =~ "_BACKDROP_SUPPORT=" ]]; then
      _DO_NOTHING=YES
    else
      echo "_BACKDROP_SUPPORT=${_BACKDROP_SUPPORT}" >> ${_octCnf}
    fi
    ### Ships dark; no _MIGRATED heal by design.
    _GRAV_SUPPORT_TEST=$(grep "^_GRAV_SUPPORT=" ${_octCnf} 2>&1)
    if [[ "${_GRAV_SUPPORT_TEST}" =~ "_GRAV_SUPPORT=" ]]; then
      _DO_NOTHING=YES
    else
      echo "_GRAV_SUPPORT=${_GRAV_SUPPORT}" >> ${_octCnf}
    fi
    ### Ships dark; no _MIGRATED heal by design.
    _TXP_SUPPORT_TEST=$(grep "^_TXP_SUPPORT=" ${_octCnf} 2>&1)
    if [[ "${_TXP_SUPPORT_TEST}" =~ "_TXP_SUPPORT=" ]]; then
      _DO_NOTHING=YES
    else
      echo "_TXP_SUPPORT=${_TXP_SUPPORT}" >> ${_octCnf}
    fi
    ### One-shot opt-out migration; see the barracuda-side twin in
    ### system.sh.inc for the why. Runs before this cnf is sourced, so
    ### the flipped value takes effect in the same run.
    _BDR_MIGRATED_TEST=$(grep _BACKDROP_SUPPORT_MIGRATED ${_octCnf} 2>&1)
    if [[ ! "${_BDR_MIGRATED_TEST}" =~ "_BACKDROP_SUPPORT_MIGRATED" ]]; then
      sed -i "s/^_BACKDROP_SUPPORT=NO$/_BACKDROP_SUPPORT=YES/g" ${_octCnf}
      echo "### _BACKDROP_SUPPORT_MIGRATED" >> ${_octCnf}
    fi

    if [ ! -e "${_ROOT}/static/control/fpm.info" ]; then
      # one version, as fpm.info is read below; any other text counts as none
      _PHP_FPM_VERSION=""
      if [ -e "${_ROOT}/log/fpm.txt" ]; then
        _PHP_FPM_VERSION=$(_satellite_php_vrn "$(_acct_read_in "${_ROOT}/log" fpm.txt)")
      fi
      if [ -z "${_PHP_FPM_VERSION}" ]; then
        _PHP_FPM_VERSION=8.4
      fi
      _acct_put_in "${_ROOT}/static/control" fpm.info "${_PHP_FPM_VERSION}"
    fi

    if [ -e "${_ROOT}/static/control/fpm.info" ]; then
      # one version, dotted or two-digit; other text is ignored: the cnf's
      # version stays and the file is left as it is
      _T_VRN=$(_satellite_php_vrn "$(_acct_read_in "${_ROOT}/static/control" fpm.info)")
      if [ -n "${_T_VRN}" ]; then
        _PHP_FPM_VERSION="${_T_VRN}"
        if [ "${_PHP_FPM_VERSION}" = "8.5" ] \
          && [ ! -x "/opt/php85/bin/php" ]; then
          if [ -x "/opt/php84/bin/php" ]; then
            _PHP_FPM_VERSION=8.4
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_FPM_VERSION=8.3
          elif [ -x "/opt/php82/bin/php" ]; then
            _PHP_FPM_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.4" ] \
          && [ ! -x "/opt/php84/bin/php" ]; then
          if [ -x "/opt/php83/bin/php" ]; then
            _PHP_FPM_VERSION=8.3
          elif [ -x "/opt/php82/bin/php" ]; then
            _PHP_FPM_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.3" ] \
          && [ ! -x "/opt/php83/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_FPM_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.2" ] \
          && [ ! -x "/opt/php82/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_FPM_VERSION=8.3
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.1" ] \
          && [ ! -x "/opt/php81/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_FPM_VERSION=8.2
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_FPM_VERSION=8.3
          fi
        elif [ "${_PHP_FPM_VERSION}" = "8.0" ] \
          && [ ! -x "/opt/php80/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.4" ] \
          && [ ! -x "/opt/php74/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_FPM_VERSION=8.1
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.3" ] \
          && [ ! -x "/opt/php73/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.2" ] \
          && [ ! -x "/opt/php72/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.1" ] \
          && [ ! -x "/opt/php71/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "7.0" ] \
          && [ ! -x "/opt/php70/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        elif [ "${_PHP_FPM_VERSION}" = "5.6" ] \
          && [ ! -x "/opt/php56/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_FPM_VERSION=7.4
          fi
        fi
        if [ -n "${_PHP_FPM_VERSION}" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "VARS: Set _PHP_FPM_VERSION to ${_PHP_FPM_VERSION}"
          fi
          sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_PHP_FPM_VERSION}/g" ${_octCnf}
          _acct_put_in "${_ROOT}/log" fpm.txt "${_PHP_FPM_VERSION}"
          _acct_in_real_dir "${_ROOT}/static/control" _acct_pin_here \
            fpm.info "${_PHP_FPM_VERSION}" "${_USER}.ftp:${_ACCG:-users}"
        fi
      fi
    fi

    if [ ! -e "${_ROOT}/static/control/cli.info" ]; then
      # one version, as cli.info is read below; any other text counts as none
      _PHP_CLI_VERSION=""
      if [ -e "${_ROOT}/log/cli.txt" ]; then
        _PHP_CLI_VERSION=$(_satellite_php_vrn "$(_acct_read_in "${_ROOT}/log" cli.txt)")
      fi
      if [ -z "${_PHP_CLI_VERSION}" ]; then
        _PHP_CLI_VERSION=8.4
      fi
      _acct_put_in "${_ROOT}/static/control" cli.info "${_PHP_CLI_VERSION}"
    fi

    if [ -e "${_ROOT}/static/control/cli.info" ]; then
      # one version, dotted or two-digit; other text is ignored: the cnf's
      # version stays and the file is left as it is
      _T_VRN=$(_satellite_php_vrn "$(_acct_read_in "${_ROOT}/static/control" cli.info)")
      if [ -n "${_T_VRN}" ]; then
        _PHP_CLI_VERSION="${_T_VRN}"
        if [ "${_PHP_CLI_VERSION}" = "8.5" ] \
          && [ ! -x "/opt/php85/bin/php" ]; then
          if [ -x "/opt/php84/bin/php" ]; then
            _PHP_CLI_VERSION=8.4
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_CLI_VERSION=8.3
          elif [ -x "/opt/php82/bin/php" ]; then
            _PHP_CLI_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.4" ] \
          && [ ! -x "/opt/php84/bin/php" ]; then
          if [ -x "/opt/php83/bin/php" ]; then
            _PHP_CLI_VERSION=8.3
          elif [ -x "/opt/php82/bin/php" ]; then
            _PHP_CLI_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.3" ] \
          && [ ! -x "/opt/php83/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_CLI_VERSION=8.2
          elif [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.2" ] \
          && [ ! -x "/opt/php82/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_CLI_VERSION=8.3
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.1" ] \
          && [ ! -x "/opt/php81/bin/php" ]; then
          if [ -x "/opt/php82/bin/php" ]; then
            _PHP_CLI_VERSION=8.2
          elif [ -x "/opt/php83/bin/php" ]; then
            _PHP_CLI_VERSION=8.3
          fi
        elif [ "${_PHP_CLI_VERSION}" = "8.0" ] \
          && [ ! -x "/opt/php80/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.4" ] \
          && [ ! -x "/opt/php74/bin/php" ]; then
          if [ -x "/opt/php81/bin/php" ]; then
            _PHP_CLI_VERSION=8.1
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.3" ] \
          && [ ! -x "/opt/php73/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.2" ] \
          && [ ! -x "/opt/php72/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.1" ] \
          && [ ! -x "/opt/php71/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "7.0" ] \
          && [ ! -x "/opt/php70/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        elif [ "${_PHP_CLI_VERSION}" = "5.6" ] \
          && [ ! -x "/opt/php56/bin/php" ]; then
          if [ -x "/opt/php74/bin/php" ]; then
            _PHP_CLI_VERSION=7.4
          fi
        fi
        if [ -n "${_PHP_CLI_VERSION}" ]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "VARS: Set _PHP_CLI_VERSION to ${_PHP_CLI_VERSION}"
          fi
          sed -i "s/^_PHP_CLI_VERSION=.*/_PHP_CLI_VERSION=${_PHP_CLI_VERSION}/g" ${_octCnf}
          _acct_put_in "${_ROOT}/log" cli.txt "${_PHP_CLI_VERSION}"
          _acct_in_real_dir "${_ROOT}/static/control" _acct_pin_here \
            cli.info "${_PHP_CLI_VERSION}" "${_USER}.ftp:${_ACCG:-users}"
        fi
      fi
    fi

    _O_CONTRIB_UP_TEST=$(grep _O_CONTRIB_UP ${_octCnf} 2>&1)
    if [[ "${_O_CONTRIB_UP_TEST}" =~ "_O_CONTRIB_UP" ]]; then
      sed -i "s/^_O_CONTRIB_UP.*//g" ${_octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${_octCnf} &> /dev/null
      wait
    fi

    _ALLOW_UNSUPPORTED_TEST=$(grep _ALLOW_UNSUPPORTED ${_octCnf} 2>&1)
    if [[ "${_ALLOW_UNSUPPORTED_TEST}" =~ "_ALLOW_UNSUPPORTED" ]]; then
      sed -i "s/^_ALLOW_UNSUPPORTED.*//g" ${_octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${_octCnf} &> /dev/null
      wait
    fi

    _USE_STOCK_TEST=$(grep _USE_STOCK ${_octCnf} 2>&1)
    if [[ "${_USE_STOCK_TEST}" =~ "_USE_STOCK" ]]; then
      sed -i "s/^_USE_STOCK.*//g" ${_octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${_octCnf} &> /dev/null
      wait
    fi

    _HTTP_WILDCARD_TEST=$(grep _HTTP_WILDCARD ${_octCnf} 2>&1)
    if [[ "${_HTTP_WILDCARD_TEST}" =~ "_HTTP_WILDCARD" ]]; then
      sed -i "s/^_HTTP_WILDCARD.*//g" ${_octCnf} &> /dev/null
      wait
      sed -i "/^$/d" ${_octCnf} &> /dev/null
      wait
    fi

    _DEL_OLD_EMPTY_PLATFORMS_TEST=$(grep _DEL_OLD_EMPTY_PLATFORMS ${_octCnf} 2>&1)
    if [[ "${_DEL_OLD_EMPTY_PLATFORMS_TEST}" =~ "_DEL_OLD_EMPTY_PLATFORMS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DEL_OLD_EMPTY_PLATFORMS=${_DEL_OLD_EMPTY_PLATFORMS}" >> ${_octCnf}
    fi

    _GHOST_PLATFORMS_CLEANUP_TEST=$(grep _GHOST_PLATFORMS_CLEANUP ${_octCnf} 2>&1)
    if [[ "${_GHOST_PLATFORMS_CLEANUP_TEST}" =~ "_GHOST_PLATFORMS_CLEANUP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_GHOST_PLATFORMS_CLEANUP=${_GHOST_PLATFORMS_CLEANUP}" >> ${_octCnf}
    fi

    _GHOST_VHOSTS_CLEANUP_TEST=$(grep _GHOST_VHOSTS_CLEANUP ${_octCnf} 2>&1)
    if [[ "${_GHOST_VHOSTS_CLEANUP_TEST}" =~ "_GHOST_VHOSTS_CLEANUP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_GHOST_VHOSTS_CLEANUP=${_GHOST_VHOSTS_CLEANUP}" >> ${_octCnf}
    fi

    _GHOST_SITES_CLEANUP_TEST=$(grep _GHOST_SITES_CLEANUP ${_octCnf} 2>&1)
    if [[ "${_GHOST_SITES_CLEANUP_TEST}" =~ "_GHOST_SITES_CLEANUP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_GHOST_SITES_CLEANUP=${_GHOST_SITES_CLEANUP}" >> ${_octCnf}
    fi

    _GHOST_SITE_FILES_CLEANUP_TEST=$(grep _GHOST_SITE_FILES_CLEANUP ${_octCnf} 2>&1)
    if [[ "${_GHOST_SITE_FILES_CLEANUP_TEST}" =~ "_GHOST_SITE_FILES_CLEANUP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_GHOST_SITE_FILES_CLEANUP=${_GHOST_SITE_FILES_CLEANUP}" >> ${_octCnf}
    fi

    _GHOST_ALIASES_CLEANUP_TEST=$(grep _GHOST_ALIASES_CLEANUP ${_octCnf} 2>&1)
    if [[ "${_GHOST_ALIASES_CLEANUP_TEST}" =~ "_GHOST_ALIASES_CLEANUP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_GHOST_ALIASES_CLEANUP=${_GHOST_ALIASES_CLEANUP}" >> ${_octCnf}
    fi

    _INSTANCE_GROUP_TEST=$(grep _INSTANCE_GROUP ${_octCnf} 2>&1)
    if [[ "${_INSTANCE_GROUP_TEST}" =~ "_INSTANCE_GROUP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_INSTANCE_GROUP=${_INSTANCE_GROUP:-YES}" >> ${_octCnf}
    fi

    _SEND_UPGRADE_EMAIL_TEST=$(grep "^_SEND_UPGRADE_EMAIL=" ${_octCnf} 2>&1)
    if [[ "${_SEND_UPGRADE_EMAIL_TEST}" =~ "_SEND_UPGRADE_EMAIL=" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SEND_UPGRADE_EMAIL=${_SEND_UPGRADE_EMAIL:-YES}" >> ${_octCnf}
    fi

    _DEL_OLD_BACKUPS_TEST=$(grep _DEL_OLD_BACKUPS ${_octCnf} 2>&1)
    if [[ "${_DEL_OLD_BACKUPS_TEST}" =~ "_DEL_OLD_BACKUPS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DEL_OLD_BACKUPS=${_DEL_OLD_BACKUPS}" >> ${_octCnf}
    fi

    _DEL_OLD_TMP_TEST=$(grep _DEL_OLD_TMP ${_octCnf} 2>&1)
    if [[ "${_DEL_OLD_TMP_TEST}" =~ "_DEL_OLD_TMP" ]]; then
      _DO_NOTHING=YES
    else
      echo "_DEL_OLD_TMP=${_DEL_OLD_TMP}" >> ${_octCnf}
    fi

    _STRONG_PASSWORDS_TEST=$(grep _STRONG_PASSWORDS ${_octCnf} 2>&1)
    if [[ "${_STRONG_PASSWORDS_TEST}" =~ "_STRONG_PASSWORDS" ]]; then
      _DO_NOTHING=YES
    else
      echo "_STRONG_PASSWORDS=${_STRONG_PASSWORDS}" >> ${_octCnf}
    fi

    _SQL_CONVERT_TEST=$(grep _SQL_CONVERT ${_octCnf} 2>&1)
    if [[ "${_SQL_CONVERT_TEST}" =~ "_SQL_CONVERT" ]]; then
      _DO_NOTHING=YES
    else
      echo "_SQL_CONVERT=${_SQL_CONVERT}" >> ${_octCnf}
    fi

    _DL_MODE_TEST=$(grep _DL_MODE ${_octCnf} 2>&1)
    if [[ ! "${_DL_MODE_TEST}" =~ "_DL_MODE" ]]; then
      if [ -n "${_DL_MODE}" ]; then
        echo "_DL_MODE=${_DL_MODE}" >> ${_octCnf}
        export _DL_MODE=${_DL_MODE}
      else
        echo "_DL_MODE=BATCH" >> ${_octCnf}
        export _DL_MODE=BATCH
      fi
    fi

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "NOTE! Please review all config options displayed below"
      sleep 3
      echo " "
      while read line; do
        echo "$line"
      done < ${_octCnf}
      echo " "
    fi

    _domDerived="${_DOMAIN}"
    if [ -e "${_octCnf}" ]; then
      source ${_octCnf}
    fi
    # A cnf copied from a sibling account (the nearest thing to a template
    # once the fetched one is gone) carries the sibling's _DOMAIN: at INIT
    # that hands the new account another account's hostmaster name. A domain
    # another account's cnf owns is never this one's; the derived name is.
    if [ "${_STATUS}" = "INIT" ] && [ -n "${_domDerived}" ] \
      && [ "${_DOMAIN}" != "${_domDerived}" ] \
      && grep -l "^_DOMAIN=\"${_DOMAIN}\"" /root/.o*.octopus.cnf 2> /dev/null | grep -qv "^${_octCnf}$"; then
      _msg "NOTE: _DOMAIN ${_DOMAIN} in ${_octCnf} belongs to another account; using ${_domDerived}"
      _DOMAIN="${_domDerived}"
      sed -i "s|^_DOMAIN=.*|_DOMAIN=\"${_DOMAIN}\"|" ${_octCnf}
    fi
    _PRE_PLATFORMS_LIST="${_PLATFORMS_LIST}"
    if [ -e "${_ROOT}/static/control/platforms.info" ]; then
      ### the symbols of the account's file: blanks and line breaks made
      ### single spaces and every other character but 0-9 and A-Z dropped,
      ### by tr, never expanded as a file name pattern
      _PLATFORMS_LIST=$(_acct_read_in "${_ROOT}/static/control" platforms.info \
        | tr -s '[:space:]' ' ' | tr -cd ' 0-9A-Z' | tr -s ' ')
      _PLATFORMS_LIST="${_PLATFORMS_LIST# }"
      _PLATFORMS_LIST="${_PLATFORMS_LIST% }"
      _msg "NOTE! Custom Platforms List: ${_PLATFORMS_LIST}"
      if [ -z "${_PLATFORMS_LIST}" ]; then
        _PLATFORMS_LIST="${_PRE_PLATFORMS_LIST}"
        _msg "NOTE! Default Platforms List: ${_PLATFORMS_LIST}"
      fi
    fi
    if [[ "${_MY_OCTO_EMAIL}" =~ "omega8.cc" ]]; then
      _if_hosted_sys
      if [ "${_hostedSys}" != "YES" ]; then
        _msg "EXIT: You must enter **your** valid email address in the"
        _msg "EXIT: _MY_OCTO_EMAIL variable in the ${_octCnf} file"
        _clean_pid_exit
      fi
    fi
    if [ "${_PHP_FPM_VERSION}" = "8.5" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.5" ]; then
      if [ ! -x "/opt/php85/bin/php" ]; then
        if [ -x "/opt/php84/bin/php" ]; then
          _PHP_FPM_VERSION=8.4
          _PHP_CLI_VERSION=8.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.4" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.4" ]; then
      if [ ! -x "/opt/php84/bin/php" ]; then
        if [ -x "/opt/php83/bin/php" ]; then
          _PHP_FPM_VERSION=8.3
          _PHP_CLI_VERSION=8.3
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.3" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.3" ]; then
      if [ ! -x "/opt/php83/bin/php" ]; then
        if [ -x "/opt/php84/bin/php" ]; then
          _PHP_FPM_VERSION=8.4
          _PHP_CLI_VERSION=8.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.2" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.2" ]; then
      if [ ! -x "/opt/php82/bin/php" ]; then
        if [ -x "/opt/php83/bin/php" ]; then
          _PHP_FPM_VERSION=8.3
          _PHP_CLI_VERSION=8.3
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.1" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.1" ]; then
      if [ ! -x "/opt/php81/bin/php" ]; then
        if [ -x "/opt/php83/bin/php" ]; then
          _PHP_FPM_VERSION=8.3
          _PHP_CLI_VERSION=8.3
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "8.0" ] \
      || [ "${_PHP_CLI_VERSION}" = "8.0" ]; then
      if [ ! -x "/opt/php80/bin/php" ]; then
        if [ -x "/opt/php83/bin/php" ]; then
          _PHP_FPM_VERSION=8.3
          _PHP_CLI_VERSION=8.3
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.4" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.4" ]; then
      if [ ! -x "/opt/php74/bin/php" ]; then
        if [ -x "/opt/php83/bin/php" ]; then
          _PHP_FPM_VERSION=8.3
          _PHP_CLI_VERSION=8.3
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.3" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.3" ]; then
      if [ ! -x "/opt/php73/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.2" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.2" ]; then
      if [ ! -x "/opt/php72/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.1" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.1" ]; then
      if [ ! -x "/opt/php71/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "7.0" ] \
      || [ "${_PHP_CLI_VERSION}" = "7.0" ]; then
      if [ ! -x "/opt/php70/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    elif [ "${_PHP_FPM_VERSION}" = "5.6" ] \
      || [ "${_PHP_CLI_VERSION}" = "5.6" ]; then
      if [ ! -x "/opt/php56/bin/php" ]; then
        if [ -x "/opt/php74/bin/php" ]; then
          _PHP_FPM_VERSION=7.4
          _PHP_CLI_VERSION=7.4
        else
          _PHP_FPM_VERSION=
          _PHP_CLI_VERSION=
        fi
      fi
    else
      _PHP_FPM_VERSION=8.4
      _PHP_CLI_VERSION=8.4
    fi
    if [ -z "${_PHP_FPM_VERSION}" ] || [ -z "${_PHP_CLI_VERSION}" ]; then
      _msg "EXIT: You must specify already installed PHP version"
      _msg "EXIT: in both _PHP_FPM_VERSION and _PHP_CLI_VERSION"
      _clean_pid_exit
    fi
  fi

  if [ ! -z "${_LOCAL_NETWORK_IP}" ] \
    && [ "${_THIS_HOST}" != "aegir.local" ]; then
    _DNS_SETUP_TEST=NO
    _MY_OWNIP="${_LOCAL_NETWORK_IP}"
  fi
}

#
# Fix advanced cron IP for cURL requests.
_satellite_fix_cron_curl() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_fix_cron_curl"
    _debug_proc
  fi
  if [ -e "${_ROOT}/.drush/hostmaster.alias.drushrc.php" ]; then
    _THIS_HM_ROOT=$(_satellite_hm_alias_get "root'")
    _pthA="profiles/hostmaster/modules/aegir/hosting/cron"
    _pthB="hosting_cron.module"
    ### Edited only in the account's own real hostmaster tree, never
    ### through a link put at the module or on the way to it.
    if _satellite_hm_path_ok "${_THIS_HM_ROOT}" \
      && [ -e "${_THIS_HM_ROOT}/${_pthA}/${_pthB}" ]; then
      _acct_in_real_dir "${_THIS_HM_ROOT}/${_pthA}" _satellite_copy_here \
        "${_pthB}" "${_pthB}" "s/127.0.0.1/${_CRON_IP}/g"
    fi
  fi
}

#
# Fix multi-IP cron access.
_satellite_fix_multi_ip_cron_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_fix_multi_ip_cron_access"
    _debug_proc
  fi
  [ -e "/root/.local.IP.list.allow" ] && rm -f /root/.local.IP.list.allow
  for _IP in `cat /root/.local.IP.list \
    | cut -d '#' -f1 \
    | sort \
    | uniq \
    | tr -d "\s"`;do echo "  allow        ${_IP};" >> \
      /root/.local.IP.list.allow;done
  echo "  allow 127.0.0.1;" >> /root/.local.IP.list.allow
  ###
  ### Only the locations kept for the box itself (FPM status and ping, the
  ### cron entry points) take the box's other addresses: they are the ones
  ### that allow 127.0.0.1. A location that denies everyone (backup_migrate
  ### files, config sync dirs) stays closed to the box as well, or every proxy
  ### that connects from it (the wildcard SSL front, an HTTPS proxy in pre.d)
  ### would serve those files to any visitor. Each pass first drops the lines
  ### it added before, in its own padded format, and any allow line inside
  ### those two locations, so a file expanded by an older pass heals too. The
  ### rendered subdir vhosts were copied from the template, so they get the
  ### same treatment. These dirs belong to the instance user, so a symlink is
  ### skipped, the new text is staged in a root-only dir, and sed -i writes a
  ### new file and renames it over the path, never through it. mawk has no
  ### {n} repetition and before 1.3.4 no [:class:] sets: both are spelled out.
  ###
  local _f _d _t
  _d=$(mktemp -d /var/backups/.boa-multi-ip.XXXXXX 2>/dev/null) || return 0
  _t="${_d}/stage"
  for _f in ${_octTpl}/Inc/vhost_include.tpl.php \
    ${_octTpl}/subdir.tpl.php \
    ${_octInc}/nginx_vhost_common.conf \
    ${_ROOT}/config/server_master/nginx/subdir.d/*/*.conf; do
    [ -f "${_f}" ] && [ ! -L "${_f}" ] || continue
    awk -v list="/root/.local.IP.list.allow" '
      BEGIN { while ((getline _l < list) > 0) _ips[++_n] = _l }
      /^[ \t]*location[ \t].*files\/(backup_migrate\/|config_)/ { _closed = 1; _depth = 0 }
      {
        _o = gsub(/\{/, "{"); _c = gsub(/\}/, "}")
        if (_closed) _depth += _o - _c
        _drop = 0
        if ($0 ~ /^[ \t]*allow        [^ ;]+;[ \t\r]*$/) _drop = 1
        else if (_closed && $0 ~ /^[ \t]*allow[ \t]/) _drop = 1
        else if ($0 ~ /^[ \t]*allow 127\.0\.0\.1;[ \t\r]*$/) {
          match($0, /^[ \t]*/); _ind = substr($0, 1, RLENGTH)
          for (_i = 1; _i <= _n; _i++) { _s = _ips[_i]; sub(/^[ \t]*/, _ind, _s); print _s }
          _drop = 1
        }
        if (!_drop) print
        if (_closed && _depth <= 0 && (_o || _c)) _closed = 0
      }' "${_f}" > "${_t}"
    if [ -s "${_t}" ] && [ -s "${_f}" ] && ! cmp -s "${_t}" "${_f}"; then
      sed -i -e "1r ${_t}" -e d "${_f}"
    fi
  done
  rm -rf "${_d}"
}

#
# Sub Force advanced Nginx configuration.
_satellite_sub_satellite_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_sub_satellite_force_advanced_nginx_config"
    _debug_proc
  fi
  if [ -d "${_octInc}" ]; then
    _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
    if [ -z "${_PHP_SV}" ]; then
      _PHP_SV=84
    fi
    if [ -e "/opt/php${_PHP_SV}/etc/php${_PHP_SV}-fpm.conf" ]; then
      sed -i "s/set.*user_socket.*/set \$user_socket \"${_USER}\";/g" ${_octTpl}/Inc/vhost_include.tpl.php &> /dev/null
      sed -i "s/set.*user_socket.*/set \$user_socket \"${_USER}\";/g" ${_octTpl}/subdir.tpl.php            &> /dev/null
      sed -i "s/set.*user_socket.*/set \$user_socket \"${_USER}\";/g" ${_octInc}/nginx_vhost_common.conf   &> /dev/null
    fi
    if [ ! -z "${_CUSTOM_COLLATION_SQL}" ]; then
      _SITES_COLLATION_SQL=${_CUSTOM_COLLATION_SQL}
    fi
    if [ ! -z "${_SITES_COLLATION_SQL}" ]; then
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_10.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_9.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_8.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_7.tpl.php &> /dev/null
      sed -i "s/utf8mb4_unicode_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_6.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_10.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_9.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_8.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_7.tpl.php &> /dev/null
      sed -i "s/utf8mb4_general_ci/${_SITES_COLLATION_SQL}/g" ${_octSetTpl}/provision_drupal_settings_6.tpl.php &> /dev/null
    fi
    _CRON_IP=${_THISHTIP//[^0-9.]/}
    if [ ! -e "/root/.local.IP.list" ]; then
      rm -f /root/.tmp.IP.list*
      rm -f /root/.local.IP.list*
      for _IP in `hostname -I`;do echo ${_IP} >> /root/.tmp.IP.list;done
      for _IP in `cat /root/.tmp.IP.list \
        | sort \
        | uniq`;do echo "${_IP} # local IP address" >> /root/.local.IP.list;done
      rm -f /root/.tmp.IP.list*
    fi
    _IP_IF_PRESENT=$(grep "${_CRON_IP}" /root/.local.IP.list 2>&1)
    if [[ "${_IP_IF_PRESENT}" =~ "${_CRON_IP}" ]]; then
      _IP_PRESENT=YES
    else
      _IP_PRESENT=NO
    fi
    if [ ! -z "${_CRON_IP}" ] \
      && [ "${_IP_PRESENT}" = "YES" ] \
      && [ -e "/root/.local.IP.list" ]; then
      _satellite_fix_multi_ip_cron_access
      _satellite_fix_cron_curl
    fi
  fi
}

#
# Force advanced Nginx configuration.
_satellite_force_advanced_nginx_config() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_force_advanced_nginx_config"
    _debug_proc
  fi
  _satellite_sub_satellite_force_advanced_nginx_config
  if [ -e "${_ROOT}/config/includes/nginx_vhost_common.conf" ]; then
    # removed inside the instance user's real config/includes only
    _acct_in_real_dir "${_ROOT}/config/includes" rm -f -- \
      ./nginx_advanced_include.conf ./nginx_legacy_include.conf \
      ./nginx_modern_include.conf ./nginx_octopus_include.conf \
      ./nginx_simple_include.conf
  fi
}

#
# The instance's own .tmp and .drush on an upgrade: the CLI keeps no php.ini
# there (its version's global ini applies, the temp paths come from TMPDIR),
# only the directories and the release serial's stamp.
_satellite_update_local_dirs_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_update_local_dirs_cli"
    _debug_proc
  fi
  _U_HD="${_ROOT}/.drush"
  _U_TP="${_ROOT}/.tmp"
  if [ ! -e "${_DRUSH_FILE}" ]; then
    return 1  # Exit the function but continue the script
  fi
  if [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
    # The instance user owns ${_ROOT} and can swap .tmp or .drush for a link
    # (its own Drush runs just before this): a link there is removed, the age
    # sweep never resolves a path through a name (bare path, -execdir), and
    # every remove and write happens inside the real directory
    [ -L "${_U_TP}" ] && rm -f "${_U_TP}"
    [ -L "${_U_HD}" ] && rm -f "${_U_HD}"
    mkdir -p ${_U_TP}
    mkdir -p ${_U_HD}
    _U_REAL="$(cd -P -- "${_ROOT}" 2> /dev/null && pwd -P)"
    # aged out only when .tmp is the instance user's own (or the empty one just made):
    # a root-owned directory of the tree renamed onto the name is left alone
    ( cd -P -- "${_U_TP}" 2> /dev/null && [ "$(pwd -P)" = "${_U_REAL}/.tmp" ] || exit 0
      [ "$(stat -c %U .)" = "${_USER}" ] \
        || { [ "$(stat -c %u .)" = "0" ] && [ -z "$(ls -A . 2> /dev/null)" ]; } || exit 0
      touch . && chmod 02755 .
      find . -mindepth 1 -mtime +0 -execdir rm -rf {} \; &> /dev/null )
    # the stamp is created exclusively, never through a link at the name
    ( cd -P -- "${_U_HD}" 2> /dev/null && [ "$(pwd -P)" = "${_U_REAL}/.drush" ] || exit 0
      mkdir -p ./sys ./xts ./usr
      rm -f -- ./.ctrl.php* "./.ctrl.${_tRee}.${_xSrl}.pid"
      echo | dd of="./.ctrl.${_tRee}.${_xSrl}.pid" conv=excl status=none 2> /dev/null
    )
  fi
}

#
# drush.php or drush.launcher of the account's own Drush (tools/drush, the
# instance user's) edited with the sed script $2 inside the real directory,
# as _satellite_copy_here edits: never through a link put at the file or at
# tools/ or drush/ on the way.
_satellite_tools_drush_edit() {
  _acct_in_real_dir "${_ROOT}/tools/drush" _satellite_copy_here \
    "${1}" "${1}" "${2}"
}

#
# Update php-cli for Drush.
_satellite_update_drush_php_cli() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_update_drush_php_cli"
    _debug_proc
  fi
  _DRUSH_FILE="${_ROOT}/tools/drush/drush.php"
  if [ "${_PHP_CLI_VERSION}" = "8.5" ] && [ -x "/opt/php85/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php85\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.4" ] && [ -x "/opt/php84/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php84\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.3" ] && [ -x "/opt/php83/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php83\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.2" ] && [ -x "/opt/php82/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php82\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.1" ] && [ -x "/opt/php81/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php81\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "8.0" ] && [ -x "/opt/php80/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php80\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.4" ] && [ -x "/opt/php74/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php74\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.3" ] && [ -x "/opt/php73/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php73\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.2" ] && [ -x "/opt/php72/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php72\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.1" ] && [ -x "/opt/php71/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php71\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "7.0" ] && [ -x "/opt/php70/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php70\/bin\/php/g" &> /dev/null
  elif [ "${_PHP_CLI_VERSION}" = "5.6" ] && [ -x "/opt/php56/bin/php" ]; then
    _satellite_tools_drush_edit drush.php "s/^#\!\/.*/#\!\/opt\/php56\/bin\/php/g" &> /dev/null
  else
    _msg "${_STATUS} B: FATAL ERROR: _PHP_CLI_VERSION is not set correctly"
    _msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
    # Root-side pass (called from _satellite_run_child_b after the B child
    # exited): signal root's own outcome in the root-owned tree like the abort
    # right after the B check does -- never a root touch inside the
    # instance-owned dir (1145fc647's invariant).
    touch "/opt/tmp/state/.root/${_USER}/status-AegirSetupA-FAIL"
    exit 1
  fi
  # The shebang pin on drush.php is bypassed whenever the drush 8 finder
  # runs: it execs drush.launcher, which re-selects PHP via `which php`.
  # The launcher also cannot run at all via its stock `env sh` shebang,
  # because /bin/sh is websh, which refuses user-area scripts. Run it
  # under bash and default its native DRUSH_PHP to the pin -- default,
  # not override: websh exports DRUSH_PHP per invocation from the
  # static/control files (cli.info + instant phpNN.info switches), and
  # that runtime choice must always win over the baked pin.
  _DRUSH_LNCH="${_ROOT}/tools/drush/drush.launcher"
  _LNCH_PHP="/opt/php${_PHP_CLI_VERSION//./}/bin/php"
  if [ -e "${_DRUSH_LNCH}" ] && [ -x "${_LNCH_PHP}" ]; then
    _satellite_tools_drush_edit drush.launcher \
      "1s/^#\!.*/#\!\/bin\/bash/" &> /dev/null
    _satellite_tools_drush_edit drush.launcher \
      "/^export DRUSH_PHP=/d" &> /dev/null
    _satellite_tools_drush_edit drush.launcher \
      "1a export DRUSH_PHP=\"\${DRUSH_PHP:-${_LNCH_PHP}}\"" &> /dev/null
  fi
}

#
# Create shared dirs.
_satellite_create_shared_dirs() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_create_shared_dirs"
    _debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Creating shared directories..."
  fi
  mkdir -p ${_D}/000/{core,modules}
  rm -rf /data/src
  if [ ! -d "${_CORE}" ]; then
    mkdir -p ${_CORE}
  fi
  ### An earlier pass that stopped before its cleanup leaves these to the
  ### account that ran it, which could have put a link or a hard link at any
  ### name in them: each directory below /data/all is handed over and moded
  ### on '.' from inside it, never through a link. /data/conf is not handed
  ### over: it stays root's for the whole run (_satellite_add_user_dirs).
  chown ${_USER}:${_USRG} ${_D}              &> /dev/null
  _acct_in_real_dir "${_D}/000" chown -h "${_USER}:${_USRG}" . &> /dev/null
  _acct_in_real_dir "${_D}/000" _acct_in_real_dir ./core \
    chown -h "${_USER}:${_USRG}" . &> /dev/null
  _acct_in_real_dir "${_CORE}" chown -h "${_USER}:${_USRG}" . &> /dev/null
  ### 777 here made /data, /data/disk, /data/conf and the shared /data/all
  ### store writable by every local user for the whole platform build below
  ### (reverted only in _satellite_batch_cleanup) -- long enough to drop code
  ### into a codebase every legacy site loads, or into the global config tree.
  ### The build runs as ${_USER}, which the chown above already made the owner
  ### of the store, so owner-write is all it ever needed there; it writes
  ### nothing in /data/conf, which stays root's. These are the same modes
  ### _satellite_batch_cleanup asserts at the end of the run.
  chmod 0755 ${_D} &> /dev/null
  chmod 0711 /data /data/disk /data/conf &> /dev/null
  _acct_in_real_dir "${_CORE}" chmod 0711 . &> /dev/null
}

#
# Update o_contrib.
_satellite_o_contrib_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_o_contrib_update_global"
    _debug_proc
  fi

  _RMMODULES="drupal-nginx-fast-x-accel-redirect varnish bakery session443 \
    cookie_cache_bypass_adv module_supports imageinfo_cache redis"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib" ] \
      && [ ! -e "${i}/o_contrib/update-${_xSrl}-${_X_VERSION}.info" ]; then
      _FORCE_UP_SIX=YES
    elif [ -e "${i}/o_contrib" ] \
      && [ ! -e "${_D}/000/modules/redis_edge" ]; then
      _FORCE_UP_SIX=YES
    elif [ -e "${i}/o_contrib" ] \
      && [ ! -L "${i}/o_contrib/redis_edge" ]; then
      _FORCE_UP_SIX=YES
    else
      _FORCE_UP_SIX=NO
    fi
    if [ "${_FORCE_UP_SIX}" = "YES" ] && [ -e "${i}/o_contrib" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib/$m" ]; then
          rm -rf ${i}/o_contrib/$m
        fi
      done
      cd ${i}/o_contrib
      if [ ! -d "${i}/o_contrib/advagg" ]; then
        _get_dev_contrib "advagg-6.x-1.11.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/boost" ]; then
        _get_dev_contrib "boost-6.x-1.22.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/cdn" ]; then
        _get_dev_contrib "cdn-6.x-2.7.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/force_password_change" ]; then
        _get_dev_contrib "force_password_change-6.x-3.4.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/fpa" ]; then
        _get_dev_contrib "fpa-6.x-2.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/httprl" ]; then
        _get_dev_contrib "httprl-6.x-1.14.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/js" ]; then
        _get_dev_contrib "js-6.x-1.3.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/panels_content_cache" ]; then
        _get_dev_contrib "panels_content_cache-6.x-1.0.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/phpass" ]; then
        _get_dev_contrib "phpass-6.x-2.1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/session_expire" ]; then
        _get_dev_contrib "session_expire-6.x-1.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/taxonomy_edge" ]; then
        _get_dev_contrib "taxonomy_edge-6.x-1.7.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/views_cache_bully" ]; then
        _get_dev_contrib "views_cache_bully-6.x-3.1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib/views_content_cache" ]; then
        _get_dev_contrib "views_content_cache-6.x-2.x-dev.tar.gz"
      fi
      if [ -d "${i}/o_contrib/expire" ]; then
        rm -rf ${i}/o_contrib/expire
      fi
      if [ -d "${i}/o_contrib/purge" ]; then
        rm -rf ${i}/o_contrib/purge
      fi
      if [ -d "${i}/o_contrib/cache_backport" ]; then
        rm -rf ${i}/o_contrib/cache_backport
      fi
      if [ -d "${i}/o_contrib/redis" ]; then
        rm -rf ${i}/o_contrib/redis
      fi
      if [ -d "${i}/o_contrib/redis_edge" ]; then
        rm -rf ${i}/o_contrib/redis_edge
      fi
      if [ -e "${_D}/000/modules/cache_backport" ] \
        && [ ! -L "${i}/o_contrib/cache_backport" ]; then
        ln -sfn ${_D}/000/modules/cache_backport ${i}/o_contrib/cache_backport
      fi
      if [ -L "${i}/o_contrib/redis" ]; then
        rm -f ${i}/o_contrib/redis
      fi
      if [ -e "${_D}/000/modules/redis_edge" ] \
        && [ ! -L "${i}/o_contrib/redis_edge" ]; then
        ln -sfn ${_D}/000/modules/redis_edge ${i}/o_contrib/redis_edge
      fi
      touch ${i}/o_contrib/update-${_xSrl}-${_X_VERSION}.info
      find ${i}/o_contrib -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib -type f -exec chmod 0644 {} \; &> /dev/null
    fi
    if [ -d "${_D}/$i" ]; then
      for p in `find ${i}/ -maxdepth 1 -mindepth 1 -type d | sort`; do
        if [ -d "$p/modules/cookie_cache_bypass" ]; then
          rm -rf $p/modules/cookie_cache_bypass
        fi
      done
    fi
  done
  cd
}

#
# Update o_contrib_seven.
_satellite_o_contrib_seven_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_o_contrib_seven_update_global"
    _debug_proc
  fi

  _RMMODULES="session443 cookie_cache_bypass_adv agrcache speedy redis"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_seven" ] \
      && [ ! -e "${i}/o_contrib_seven/update-${_xSrl}-${_X_VERSION}.info" ]; then
      _FORCE_UP_SEVEN=YES
    elif [ -e "${i}/o_contrib_seven" ] \
      && [ ! -e "${i}/o_contrib_seven/views_accelerator" ]; then
      _FORCE_UP_SEVEN=YES
    elif [ -e "${i}/o_contrib_seven" ] \
      && [ ! -e "${_D}/000/modules/redis_edge" ]; then
      _FORCE_UP_SEVEN=YES
    elif [ -e "${i}/o_contrib_seven" ] \
      && [ ! -L "${i}/o_contrib_seven/redis_edge" ]; then
      _FORCE_UP_SEVEN=YES
    else
      _FORCE_UP_SEVEN=NO
    fi
    if [ "${_FORCE_UP_SEVEN}" = "YES" ] \
      && [ -e "${i}/o_contrib_seven" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_seven/$m" ]; then
          rm -rf ${i}/o_contrib_seven/$m
        fi
      done
      _ADMINER_VRN=4.8.1
      cd ${i}/o_contrib_seven
      if [ ! -e "${i}/o_contrib_seven/adminer/adminer/adminer-${_ADMINER_VRN}-mysql.php" ]; then
        rm -rf ${i}/o_contrib_seven/adminer
        _get_dev_contrib "adminer_bundle-7.x-1.2.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/advagg" ]; then
        _get_dev_contrib "advagg-7.x-2.36.tar.gz"
      fi
      if [ ! -e "${i}/o_contrib_seven/autoslave/patches/update-pdo-7.22.patch" ]; then
        rm -rf ${i}/o_contrib_seven/autoslave
        _get_dev_contrib "autoslave-7.x-1.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/boost" ]; then
        _get_dev_contrib "boost-7.x-1.2.tar.gz"
      fi
      if [ ! -e "${i}/o_contrib_seven/cache_consistent/3010585-cache-consistent-php72-2.patch" ]; then
        rm -rf ${i}/o_contrib_seven/cache_consistent
        _get_dev_contrib "cache_consistent-7.x-2.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/cdn" ]; then
        _get_dev_contrib "cdn-7.x-2.10.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/display_cache" ]; then
        _get_dev_contrib "display_cache-7.x-1.3.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/entity_print" ]; then
        _get_dev_contrib "entity_print-7.x-1.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/entitycache" ]; then
        _get_dev_contrib "entitycache-7.x-1.7.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/file_resup" ]; then
        _get_dev_contrib "file_resup-7.x-1.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/force_password_change" ]; then
        _get_dev_contrib "force_password_change-7.x-2.2.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/fpa" ]; then
        _get_dev_contrib "fpa-7.x-2.6.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/httprl" ]; then
        _get_dev_contrib "httprl-7.x-1.14.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/js" ]; then
        _get_dev_contrib "js-7.x-2.5.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/panels_content_cache" ]; then
        _get_dev_contrib "panels_content_cache-7.x-1.4.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/session_expire" ]; then
        _get_dev_contrib "session_expire-7.x-1.x-dev.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/speedy" ]; then
        _get_dev_contrib "speedy-7.x-1.34.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/taxonomy_edge" ]; then
        _get_dev_contrib "taxonomy_edge-7.x-1.9.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/views_accelerator" ]; then
        _get_dev_contrib "views_accelerator-7.x-1.0-beta1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/views_cache_bully" ]; then
        _get_dev_contrib "views_cache_bully-7.x-3.1.tar.gz"
      fi
      if [ ! -d "${i}/o_contrib_seven/views_content_cache" ]; then
        _get_dev_contrib "views_content_cache-7.x-3.0-alpha3.tar.gz"
      fi
      if [ ! -e "${i}/o_contrib_seven/entitycache/includes/entitycache.node.inc" ]; then
        rm -rf ${i}/o_contrib_seven/entitycache
        _get_dev_contrib "entitycache-7.x-1.7.tar.gz"
      fi
      if [ -d "${i}/o_contrib_seven/expire" ] \
        || [ -d "${i}/o_contrib_seven/purge" ]; then
        rm -rf ${i}/o_contrib_seven/expire
        rm -rf ${i}/o_contrib_seven/purge
      fi
      if [ -d "${i}/o_contrib_seven/redis" ]; then
        rm -rf ${i}/o_contrib_seven/redis
      fi
      if [ -d "${i}/o_contrib_seven/redis_edge" ]; then
        rm -rf ${i}/o_contrib_seven/redis_edge
      fi
      if [ -L "${i}/o_contrib_seven/redis" ]; then
        rm -f ${i}/o_contrib_seven/redis
      fi
      if [ -e "${_D}/000/modules/redis_edge" ] \
        && [ ! -L "${i}/o_contrib_seven/redis_edge" ]; then
        ln -sfn ${_D}/000/modules/redis_edge ${i}/o_contrib_seven/redis_edge
      fi
      find ${i}/o_contrib_seven -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_seven -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_seven/update-${_xSrl}-${_X_VERSION}.info
    fi
  done
  cd
}

#
# Update o_contrib_eight.
_satellite_o_contrib_eight_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_o_contrib_eight_update_global"
    _debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_eight" ] \
      && [ ! -e "${i}/o_contrib_eight/update-${_xSrl}-${_X_VERSION}.info" ]; then
      _FORCE_UP_EIGHT=YES
    elif [ -e "${i}/o_contrib_eight" ] \
      && [ ! -e "${_D}/000/modules/redis_eight" ]; then
      _FORCE_UP_EIGHT=YES
    elif [ -e "${i}/o_contrib_eight" ] \
      && [ ! -L "${i}/o_contrib_eight/redis_eight" ]; then
      _FORCE_UP_EIGHT=YES
    elif [ -e "${i}/o_contrib_eight" ] \
      && [ ! -L "${i}/o_contrib_eight/redis_compr" ]; then
      _FORCE_UP_EIGHT=YES
    else
      _FORCE_UP_EIGHT=NO
    fi
    if [ "${_FORCE_UP_EIGHT}" = "YES" ] \
      && [ -e "${i}/o_contrib_eight" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_eight/$m" ]; then
          rm -rf ${i}/o_contrib_eight/$m
        fi
      done
      cd ${i}/o_contrib_eight
      if [ -d "${i}/o_contrib_eight/redis_eight" ]; then
        rm -rf ${i}/o_contrib_eight/redis_eight
      fi
      if [ -e "${_D}/000/modules/redis_eight" ] \
        && [ ! -L "${i}/o_contrib_eight/redis_eight" ]; then
        ln -sfn ${_D}/000/modules/redis_eight ${i}/o_contrib_eight/redis_eight
      fi
      if [ -e "${_D}/000/modules/redis_compr" ] \
        && [ ! -L "${i}/o_contrib_eight/redis_compr" ]; then
        ln -sfn ${_D}/000/modules/redis_compr ${i}/o_contrib_eight/redis_compr
      fi
      find ${i}/o_contrib_eight -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_eight -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_eight/update-${_xSrl}-${_X_VERSION}.info
    fi
  done
  cd
}


#
# Update o_contrib_nine.
_satellite_o_contrib_nine_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_o_contrib_nine_update_global"
    _debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_nine" ] \
      && [ ! -e "${i}/o_contrib_nine/update-${_xSrl}-${_X_VERSION}.info" ]; then
      _FORCE_UP_NINE=YES
    elif [ -e "${i}/o_contrib_nine" ] \
      && [ ! -L "${i}/o_contrib_nine/redis_nine_ten" ]; then
      _FORCE_UP_NINE=YES
    else
      _FORCE_UP_NINE=NO
    fi
    if [ "${_FORCE_UP_NINE}" = "YES" ] \
      && [ -e "${i}/o_contrib_nine" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_nine/$m" ]; then
          rm -rf ${i}/o_contrib_nine/$m
        fi
      done
      cd ${i}/o_contrib_nine
      if [ -d "${i}/o_contrib_nine/redis_eight" ]; then
        rm -rf ${i}/o_contrib_nine/redis_eight
      fi
      if [ -e "${_D}/000/modules/redis_nine_ten" ] \
        && [ ! -L "${i}/o_contrib_nine/redis_nine_ten" ]; then
        ln -sfn ${_D}/000/modules/redis_nine_ten ${i}/o_contrib_nine/redis_nine_ten
      fi
      if [ -e "${_D}/000/modules/redis_compr" ] \
        && [ ! -L "${i}/o_contrib_nine/redis_compr" ]; then
        ln -sfn ${_D}/000/modules/redis_compr ${i}/o_contrib_nine/redis_compr
      fi
      find ${i}/o_contrib_nine -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_nine -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_nine/update-${_xSrl}-${_X_VERSION}.info
    fi
  done
  cd
}


#
# Update o_contrib_ten.
_satellite_o_contrib_ten_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_o_contrib_ten_update_global"
    _debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_ten" ] \
      && [ ! -e "${i}/o_contrib_ten/update-${_xSrl}-${_X_VERSION}.info" ]; then
      _FORCE_UP_TEN=YES
    elif [ -e "${i}/o_contrib_ten" ] \
      && [ ! -L "${i}/o_contrib_ten/redis_ten_eleven" ]; then
      _FORCE_UP_TEN=YES
    else
      _FORCE_UP_TEN=NO
    fi
    if [ "${_FORCE_UP_TEN}" = "YES" ] \
      && [ -e "${i}/o_contrib_ten" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_ten/$m" ]; then
          rm -rf ${i}/o_contrib_ten/$m
        fi
      done
      cd ${i}/o_contrib_ten
      if [ -d "${i}/o_contrib_ten/redis_compr" ]; then
        rm -rf ${i}/o_contrib_ten/redis_compr
      fi
      if [ -d "${i}/o_contrib_ten/redis_eight" ]; then
        rm -rf ${i}/o_contrib_ten/redis_eight
      fi
      if [ -d "${i}/o_contrib_ten/redis_nine_ten" ]; then
        rm -rf ${i}/o_contrib_ten/redis_nine_ten
      fi
      if [ -e "${_D}/000/modules/redis_ten_eleven" ] \
        && [ ! -L "${i}/o_contrib_ten/redis_ten_eleven" ]; then
        ln -sfn ${_D}/000/modules/redis_ten_eleven ${i}/o_contrib_ten/redis_ten_eleven
      fi
      find ${i}/o_contrib_ten -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_ten -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_ten/update-${_xSrl}-${_X_VERSION}.info
    fi
  done
  cd
}


#
# Update o_contrib_eleven.
_satellite_o_contrib_eleven_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_o_contrib_eleven_update_global"
    _debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_eleven" ] \
      && [ ! -e "${i}/o_contrib_eleven/update-${_xSrl}-${_X_VERSION}.info" ]; then
      _FORCE_UP_TEN=YES
    elif [ -e "${i}/o_contrib_eleven" ] \
      && [ ! -L "${i}/o_contrib_eleven/redis_ten_eleven" ]; then
      _FORCE_UP_TEN=YES
    else
      _FORCE_UP_TEN=NO
    fi
    if [ "${_FORCE_UP_TEN}" = "YES" ] \
      && [ -e "${i}/o_contrib_eleven" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_eleven/$m" ]; then
          rm -rf ${i}/o_contrib_eleven/$m
        fi
      done
      cd ${i}/o_contrib_eleven
      if [ -d "${i}/o_contrib_eleven/redis_compr" ]; then
        rm -rf ${i}/o_contrib_eleven/redis_compr
      fi
      if [ -d "${i}/o_contrib_eleven/redis_eight" ]; then
        rm -rf ${i}/o_contrib_eleven/redis_eight
      fi
      if [ -d "${i}/o_contrib_eleven/redis_nine_ten" ]; then
        rm -rf ${i}/o_contrib_eleven/redis_nine_ten
      fi
      if [ -e "${_D}/000/modules/redis_ten_eleven" ] \
        && [ ! -L "${i}/o_contrib_eleven/redis_ten_eleven" ]; then
        ln -sfn ${_D}/000/modules/redis_ten_eleven ${i}/o_contrib_eleven/redis_ten_eleven
      fi
      find ${i}/o_contrib_eleven -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_eleven -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_eleven/update-${_xSrl}-${_X_VERSION}.info
    fi
  done
  cd
}

_satellite_o_contrib_backdrop_update_global() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_o_contrib_backdrop_update_global"
    _debug_proc
  fi

  _RMMODULES="some_foo_bar"

  for i in `dir -d ${_D}/*`; do
    if [ -e "${i}/o_contrib_backdrop" ]; then
      _satellite_restore_o_contrib_backdrop_webform "${i}/o_contrib_backdrop" "${i##*/}"
    fi
    if [ -d "${i}/o_contrib_backdrop/webform" ] \
      && [ ! -e "${i}/o_contrib_backdrop/webform/ver-${_WEBFORM_B_TAG}.info" ]; then
      _satellite_refresh_o_contrib_backdrop_webform "${i}/o_contrib_backdrop" "${i##*/}"
    fi
    if [ -e "${i}/o_contrib_backdrop" ] \
      && [ ! -e "${i}/o_contrib_backdrop/update-${_xSrl}-${_X_VERSION}.info" ]; then
      _FORCE_UP_BACKDROP=YES
    elif [ -e "${i}/o_contrib_backdrop" ] \
      && [ ! -L "${i}/o_contrib_backdrop/redis_backdrop" ]; then
      _FORCE_UP_BACKDROP=YES
    else
      _FORCE_UP_BACKDROP=NO
    fi
    if [ "${_FORCE_UP_BACKDROP}" = "YES" ] \
      && [ -e "${i}/o_contrib_backdrop" ]; then
      for m in ${_RMMODULES}; do
        if [ -d "${i}/o_contrib_backdrop/$m" ]; then
          rm -rf ${i}/o_contrib_backdrop/$m
        fi
      done
      cd ${i}/o_contrib_backdrop
      if [ -e "${_D}/000/modules/redis_backdrop" ] \
        && [ ! -L "${i}/o_contrib_backdrop/redis_backdrop" ]; then
        ln -sfn ${_D}/000/modules/redis_backdrop ${i}/o_contrib_backdrop/redis_backdrop
      fi
      find ${i}/o_contrib_backdrop -type d -exec chmod 0755 {} \; &> /dev/null
      find ${i}/o_contrib_backdrop -type f -exec chmod 0644 {} \; &> /dev/null
      touch ${i}/o_contrib_backdrop/update-${_xSrl}-${_X_VERSION}.info
    fi
  done
  cd
}


#
# The Backdrop webform release every o_contrib_backdrop bundle carries: bumped
# when a new tag is published to the contrib shelves. A bundle records the tag
# it holds (webform/ver-<tag>.info); a bundle holding another one is refreshed
# on the next upgrade pass (_satellite_refresh_o_contrib_backdrop_webform).
_WEBFORM_B_TAG="1.x-4.26.6"

#
# Download o_contrib_backdrop. The bundle carries the Backdrop-native contrib
# BOA maintains for every Backdrop platform; like the D6/D7 bundles the redis
# integration is a symlink into the single shared /data/all/000/modules copy,
# created here at download time so a fresh space is never redis-less. Plain
# curated members (webform since 2026-09) extract into the bundle dir.
_satellite_download_o_contrib_backdrop() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_o_contrib_backdrop"
    _debug_proc
  fi
  touch update-${_xSrl}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Downloading o_contrib_backdrop modules..."
  fi
  ### Plain bundle members extract into the bundle dir itself, so they MUST
  ### run before the redis block below, whose fetch-needed branch cd's into
  ### the shared store and never returns (same ordering as o_contrib_eleven).
  if _o_contrib_backdrop_webform_get "${PWD}"; then
    echo update > ./webform/ver-${_WEBFORM_B_TAG}.info
  else
    _msg "${_STATUS} A: webform-${_WEBFORM_B_TAG} not fetched into o_contrib_backdrop"
  fi
  if [ ! -L "./redis_backdrop" ]; then
    ln -sfn ${_D}/000/modules/redis_backdrop redis_backdrop
  fi
  if [ ! -e "${_D}/000/modules/redis_backdrop/ver-${_REDIS_B_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_backdrop
    _get_dev_contrib "redis_backdrop-${_REDIS_B_VERSION}.tar.gz"
    # every instance's Backdrop sites run this copy: root's, whatever owner
    # the archive recorded
    chown -R root:root ${_D}/000/modules/redis_backdrop &> /dev/null
    echo update > ${_D}/000/modules/redis_backdrop/ver-${_REDIS_B_VERSION}.${_xSrl}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}

#
# Fetch the _WEBFORM_B_TAG release into directory $1 and unpack it there as
# webform/. Returns 0 only when the archive tests whole, unpacks cleanly and
# holds the module's .info and .module files; the tree is root's whatever owner
# the archive recorded, since every instance's Backdrop sites run it. A failed
# attempt leaves no webform/ behind.
_o_contrib_backdrop_webform_get() {
  local _dst="$1" _tgz="webform-${_WEBFORM_B_TAG}.tar.gz" _try
  for _try in 1 2 3; do
    rm -rf "${_dst}/webform" "${_dst}/${_tgz}"
    if curl ${_crlGet} "${_urlDev}/${_tRee}/contrib/${_tgz}" -o "${_dst}/${_tgz}" \
      && gzip -t "${_dst}/${_tgz}" &> /dev/null \
      && tar -xzf "${_dst}/${_tgz}" -C "${_dst}" --no-same-owner \
      && [ -e "${_dst}/webform/webform.info" ] \
      && [ -e "${_dst}/webform/webform.module" ]; then
      rm -f "${_dst}/${_tgz}"
      chown -R root:root "${_dst}/webform" &> /dev/null
      find "${_dst}/webform" -type d -exec chmod 0755 {} \; &> /dev/null
      find "${_dst}/webform" -type f -exec chmod 0644 {} \; &> /dev/null
      return 0
    fi
    [ "${_try}" -lt 3 ] && sleep 9
  done
  rm -rf "${_dst}/webform" "${_dst}/${_tgz}"
  return 1
}

#
# Replace the webform member of one o_contrib_backdrop bundle ($1, platform
# generation $2) with the _WEBFORM_B_TAG release. The new tree is fetched into
# a stage dir under ${_D} named for the generation (a hidden dir inside the
# bundle would be scanned as a second module by the sites) and renamed in only
# once complete; a failed fetch leaves the member the sites run as it was. A
# stage still holding the old tree while the bundle has none is kept for
# _satellite_restore_o_contrib_backdrop_webform.
_satellite_refresh_o_contrib_backdrop_webform() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_refresh_o_contrib_backdrop_webform $1"
    _debug_proc
  fi
  local _bnd="$1" _gen="$2" _stg
  [ -d "${_bnd}/webform" ] && [ ! -L "${_bnd}/webform" ] || return 0
  _stg=$(mktemp -d "${_D}/.webform-stage.${_gen}.XXXXXX") || return 1
  if _o_contrib_backdrop_webform_get "${_stg}"; then
    echo update > ${_stg}/webform/ver-${_WEBFORM_B_TAG}.info
    if mv "${_bnd}/webform" "${_stg}/prev"; then
      if mv "${_stg}/webform" "${_bnd}/webform"; then
        _msg "${_STATUS} A: o_contrib_backdrop webform ${_WEBFORM_B_TAG} in ${_bnd}"
      else
        mv "${_stg}/prev" "${_bnd}/webform"
        _msg "${_STATUS} A: o_contrib_backdrop webform swap failed in ${_bnd}, kept"
      fi
    fi
  else
    _msg "${_STATUS} A: webform-${_WEBFORM_B_TAG} not fetched, ${_bnd} keeps its webform"
  fi
  if [ -e "${_bnd}/webform" ] || [ ! -d "${_stg}/prev" ]; then
    rm -rf "${_stg}"
  fi
}

#
# A pass stopped between the two renames of a refresh leaves the bundle ($1,
# generation $2) without webform/ and the old tree in the generation's stage:
# put it back. Stages of a bundle that has its webform/ are leftovers.
_satellite_restore_o_contrib_backdrop_webform() {
  local _bnd="$1" _gen="$2" _s
  for _s in ${_D}/.webform-stage.${_gen}.*; do
    [ -d "${_s}" ] || continue
    if [ ! -e "${_bnd}/webform" ] && [ -e "${_s}/prev/webform.info" ] \
      && mv "${_s}/prev" "${_bnd}/webform"; then
      _msg "${_STATUS} A: o_contrib_backdrop webform put back in ${_bnd}"
    fi
    [ -e "${_bnd}/webform" ] && rm -rf "${_s}"
  done
}


#
# Download o_contrib_eleven.
_satellite_download_o_contrib_eleven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_o_contrib_eleven"
    _debug_proc
  fi
  touch update-${_xSrl}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Downloading o_contrib_eleven modules..."
  fi
  _get_dev_contrib "robotstxt-8.x-1.6.tar.gz"
  _get_dev_contrib "readonlymode-8.x-1.4.tar.gz"
  if [ ! -e "${_D}/000/modules/redis_ten_eleven/ver-${_REDIS_E_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_ten_eleven
    _get_dev_contrib "redis_ten_eleven-${_REDIS_E_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_ten_eleven/ver-${_REDIS_E_VERSION}.${_xSrl}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}


#
# Download o_contrib_ten.
_satellite_download_o_contrib_ten() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_o_contrib_ten"
    _debug_proc
  fi
  touch update-${_xSrl}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Downloading o_contrib_ten modules..."
  fi
  _get_dev_contrib "robotstxt-8.x-1.6.tar.gz"
  _get_dev_contrib "readonlymode-8.x-1.4.tar.gz"
  if [ ! -e "${_D}/000/modules/redis_ten_eleven/ver-${_REDIS_E_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_ten_eleven
    _get_dev_contrib "redis_ten_eleven-${_REDIS_E_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_ten_eleven/ver-${_REDIS_E_VERSION}.${_xSrl}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}


#
# Download o_contrib_nine.
_satellite_download_o_contrib_nine() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_o_contrib_nine"
    _debug_proc
  fi
  touch update-${_xSrl}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Downloading o_contrib_nine modules..."
  fi
  _get_dev_contrib "robotstxt-8.x-1.5.tar.gz"
  _get_dev_contrib "readonlymode-8.x-1.2.tar.gz"
  if [ ! -e "${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_nine_ten
    _get_dev_contrib "redis_nine_ten-${_REDIS_T_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_xSrl}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_compr
    _get_dev_contrib "redis_compr-${_REDIS_C_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_xSrl}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}


#
# Download o_contrib_eight.
_satellite_download_o_contrib_eight() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_o_contrib_eight"
    _debug_proc
  fi
  touch update-${_xSrl}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Downloading o_contrib_eight modules..."
  fi
  _get_dev_contrib "robotstxt-8.x-1.4.tar.gz"
  _get_dev_contrib "readonlymode-8.x-1.2.tar.gz"
  if [ ! -e "${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_eight
    _get_dev_contrib "redis_eight-${_REDIS_N_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_xSrl}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_compr
    _get_dev_contrib "redis_compr-${_REDIS_C_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_xSrl}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}


#
# Download o_contrib_seven.
_satellite_download_o_contrib_seven() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_o_contrib_seven"
    _debug_proc
  fi
  touch update-${_xSrl}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Downloading o_contrib_seven modules..."
  fi
  _get_dev_contrib "admin-7.x-2.0-beta3.tar.gz"
  _get_dev_contrib "adminer_bundle-7.x-1.2.tar.gz"
  # _get_dev_contrib "adminer-7.x-1.2.tar.gz"
  # curl ${_crlGet} "https://github.com/vrana/adminer/releases/download/v${_ADMINER_VRN}/adminer-${_ADMINER_VRN}-mysql.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/adminer-${_ADMINER_VRN}-mysql.php"
  # curl ${_crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/designs/nette/adminer.css" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/styles/adminer.css"
  # curl ${_crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/plugin.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/plugin.php"
  # curl ${_crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/enum-option.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/enum-option.php"
  # curl ${_crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/edit-textarea.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/edit-textarea.php"
  # curl ${_crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/version-noverify.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/version-noverify.php"
  # curl ${_crlGet} "https://raw.githubusercontent.com/vrana/adminer/v${_ADMINER_VRN}/plugins/frames.php" -o "${_CORE}/${i}/o_contrib_seven/adminer/adminer/plugins/frames.php"
  _get_dev_contrib "advagg-7.x-2.36.tar.gz"
  _get_dev_contrib "autoslave-7.x-1.x-dev.tar.gz"
  _get_dev_contrib "blockcache_alter-7.x-1.1.tar.gz"
  _get_dev_contrib "boost-7.x-1.2.tar.gz"
  _get_dev_contrib "cache_consistent-7.x-2.x-dev.tar.gz"
  _get_dev_contrib "cdn-7.x-2.10.tar.gz"
  _get_dev_contrib "config_perms-7.x-2.2.tar.gz"
  _get_dev_contrib "css_emimage-7.x-1.3.tar.gz"
  _get_dev_contrib "display_cache-7.x-1.3.tar.gz"
  _get_dev_contrib "entity_print-7.x-1.5.tar.gz"
  _get_dev_contrib "entitycache-7.x-1.7.tar.gz"
  _get_dev_contrib "esi-7.x-3.x-dev.tar.gz"
  _get_dev_contrib "file_resup-7.x-1.5.tar.gz"
  _get_dev_contrib "flood_control-7.x-1.1.tar.gz"
  _get_dev_contrib "force_password_change-7.x-2.2.tar.gz"
  _get_dev_contrib "fpa-7.x-2.6.tar.gz"
  _get_dev_contrib "httprl-7.x-1.14.tar.gz"
  _get_dev_contrib "js-7.x-2.5.tar.gz"
  _get_dev_contrib "login_security-7.x-1.9.tar.gz"
  _get_dev_contrib "nocurrent_pass-7.x-1.1.tar.gz"
  _get_dev_contrib "panels_content_cache-7.x-1.4.tar.gz"
  _get_dev_contrib "readonlymode-7.x-1.2.tar.gz"
  _get_dev_contrib "reroute_email-7.x-1.4.tar.gz"
  _get_dev_contrib "robotstxt-7.x-1.4.tar.gz"
  _get_dev_contrib "securesite-7.x-2.0-beta3.tar.gz"
  _get_dev_contrib "session_expire-7.x-1.x-dev.tar.gz"
  _get_dev_contrib "site_verify-7.x-1.2.tar.gz"
  _get_dev_contrib "speedy-7.x-1.34.tar.gz"
  _get_dev_contrib "tag1_d7es-7.x-1.4.tar.gz"
  _get_dev_contrib "taxonomy_edge-7.x-1.9.tar.gz"
  _get_dev_contrib "variable_clean-7.x-1.x-dev.tar.gz"
  _get_dev_contrib "views_accelerator-7.x-1.0-beta1.tar.gz"
  _get_dev_contrib "views_cache_bully-7.x-3.1.tar.gz"
  _get_dev_contrib "views_content_cache-7.x-3.0-alpha3.tar.gz"
  _get_dev_contrib "views404-7.x-1.0-beta1.tar.gz"
  rm -rf nginx_accel_redirect*
  rm -rf purge*
  rm -rf expire*
  find ./ -type d -exec chmod 0755 {} \; &> /dev/null
  find ./ -type f -exec chmod 0644 {} \; &> /dev/null
  touch ctrl-${_xSrl}-${_X_VERSION}
  if [ -L "./redis" ]; then
    rm -f redis
  fi
  if [ ! -L "./redis_edge" ]; then
    ln -sfn ${_D}/000/modules/redis_edge redis_edge
  fi
  if [ -e "${_D}/000/modules/redis" ]; then
    rm -rf ${_D}/000/modules/redis
  fi
  if [ ! -e "${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_edge
    _get_dev_contrib "redis_edge-${_REDIS_L_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_xSrl}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}

#
# Download o_contrib_six.
_satellite_download_o_contrib_six() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_o_contrib_six"
    _debug_proc
  fi
  touch update-${_xSrl}-${_X_VERSION}.info
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Downloading o_contrib modules..."
  fi
  _get_dev_contrib "admin-6.x-2.0.tar.gz"
  _get_dev_contrib "advagg-6.x-1.11.tar.gz"
  _get_dev_contrib "blockcache_alter-6.x-1.6.tar.gz"
  _get_dev_contrib "boost-6.x-1.22.tar.gz"
  _get_dev_contrib "cdn-6.x-2.7.tar.gz"
  _get_dev_contrib "config_perms-6.x-2.x-dev.tar.gz"
  _get_dev_contrib "css_emimage-6.x-2.x-dev.tar.gz"
  _get_dev_contrib "dbtuner-6.x-1.x-dev.tar.gz"
  _get_dev_contrib "esi-6.x-2.x-dev.tar.gz"
  _get_dev_contrib "force_password_change-6.x-3.4.tar.gz"
  _get_dev_contrib "fpa-6.x-2.5.tar.gz"
  _get_dev_contrib "httprl-6.x-1.14.tar.gz"
  _get_dev_contrib "image-6.x-1.2.tar.gz"
  _get_dev_contrib "js-6.x-1.3.tar.gz"
  _get_dev_contrib "login_security-6.x-1.4.tar.gz"
  _get_dev_contrib "panels_content_cache-6.x-1.0.tar.gz"
  _get_dev_contrib "phpass-6.x-2.1.tar.gz"
  _get_dev_contrib "private_upload-6.x-1.x-dev.tar.gz"
  _get_dev_contrib "readonlymode-6.x-1.2.tar.gz"
  _get_dev_contrib "reroute_email-6.x-1.3.tar.gz"
  _get_dev_contrib "robotstxt-6.x-1.4.tar.gz"
  _get_dev_contrib "securesite-6.x-2.4.tar.gz"
  _get_dev_contrib "session_expire-6.x-1.x-dev.tar.gz"
  _get_dev_contrib "site_verify-6.x-1.0.tar.gz"
  _get_dev_contrib "taxonomy_edge-6.x-1.7.tar.gz"
  _get_dev_contrib "variable_clean-6.x-1.x-dev.tar.gz"
  _get_dev_contrib "views_cache_bully-6.x-3.1.tar.gz"
  _get_dev_contrib "views_content_cache-6.x-2.x-dev.tar.gz"
  _get_dev_contrib "views404-6.x-1.x-dev.tar.gz"
  rm -rf nginx_accel_redirect*
  rm -rf purge*
  rm -rf expire*
  find ./ -type d -exec chmod 0755 {} \; &> /dev/null
  find ./ -type f -exec chmod 0644 {} \; &> /dev/null
  touch ctrl-${_xSrl}-${_X_VERSION}
  if [ -L "./redis" ]; then
    rm -f redis
  fi
  if [ ! -L "./redis_edge" ]; then
    ln -sfn ${_D}/000/modules/redis_edge redis_edge
  fi
  if [ ! -L "./cache_backport" ]; then
    ln -sfn ${_D}/000/modules/cache_backport cache_backport
  fi
  if [ ! -e "${_D}/000/modules/cache_backport/update-${_xSrl}-${_X_VERSION}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/cache_backport
    _get_dev_contrib "cache_backport-6.x-1.0-rc4.tar.gz"
    echo update > cache_backport/update-${_xSrl}-${_X_VERSION}.info
  fi
  if [ -e "${_D}/000/modules/redis" ]; then
    rm -rf ${_D}/000/modules/redis
  fi
  if [ ! -e "${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_edge
    _get_dev_contrib "redis_edge-${_REDIS_L_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_xSrl}.info
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}

#
# Upgrade o_contrib.
_satellite_check_fix_o_contrib() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_check_fix_o_contrib"
    _debug_proc
  fi
  if [ -e "${_CORE}/o_contrib_eleven" ]; then
    if [ ! -e "${_CORE}/o_contrib_eleven/redis_ten_eleven" ] \
      || [ -e "${_CORE}/o_contrib_eleven/advagg" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      _msg "${_STATUS} A: Running o_contrib_eleven forced upgrade..."
      cd ${_CORE}/o_contrib_eleven
      rm -rf ${_CORE}/o_contrib_eleven/*
      _satellite_download_o_contrib_eleven
      cd ${_CORE}/o_contrib_eleven
    fi
  fi
  if [ -e "${_CORE}/o_contrib_ten" ]; then
    if [ ! -e "${_CORE}/o_contrib_ten/redis_ten_eleven" ] \
      || [ -e "${_CORE}/o_contrib_ten/advagg" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      _msg "${_STATUS} A: Running o_contrib_ten forced upgrade..."
      cd ${_CORE}/o_contrib_ten
      rm -rf ${_CORE}/o_contrib_ten/*
      _satellite_download_o_contrib_ten
      cd ${_CORE}/o_contrib_ten
    fi
  fi
  if [ -e "${_CORE}/o_contrib_nine" ]; then
    if [ ! -e "${_CORE}/o_contrib_nine/redis_nine_ten" ] \
      || [ ! -e "${_CORE}/o_contrib_nine/redis_compr" ] \
      || [ -e "${_CORE}/o_contrib_nine/advagg" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      _msg "${_STATUS} A: Running o_contrib_nine forced upgrade..."
      cd ${_CORE}/o_contrib_nine
      rm -rf ${_CORE}/o_contrib_nine/*
      _satellite_download_o_contrib_nine
      cd ${_CORE}/o_contrib_nine
    fi
  fi
  if [ -e "${_CORE}/o_contrib_eight" ]; then
    if [ ! -e "${_CORE}/o_contrib_eight/redis_compr" ] \
      || [ ! -e "${_CORE}/o_contrib_eight/redis_eight" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      _msg "${_STATUS} A: Running o_contrib_eight forced upgrade..."
      cd ${_CORE}/o_contrib_eight
      rm -rf ${_CORE}/o_contrib_eight/*
      _satellite_download_o_contrib_eight
      cd ${_CORE}/o_contrib_eight
    fi
  fi
  if [ -e "${_CORE}/o_contrib_seven" ]; then
    if [ ! -d "${_CORE}/o_contrib_seven/tag1_d7es" ] \
      || [ ! -e "${_CORE}/o_contrib_seven/redis_edge" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      _msg "${_STATUS} A: Running o_contrib_seven forced upgrade..."
      cd ${_CORE}/o_contrib_seven
      rm -rf ${_CORE}/o_contrib_seven/*
      _satellite_download_o_contrib_seven
      cd ${_CORE}/o_contrib_seven
    fi
  fi
  if [ -e "${_CORE}/o_contrib" ]; then
    if [ ! -d "${_CORE}/o_contrib/robotstxt" ] \
      || [ ! -e "${_CORE}/o_contrib/redis_edge" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      _msg "${_STATUS} A: Running o_contrib forced upgrade..."
      cd ${_CORE}/o_contrib
      rm -rf ${_CORE}/o_contrib/*
      _satellite_download_o_contrib_six
      cd ${_CORE}/o_contrib
    fi
  fi
  if [ -e "${_CORE}/o_contrib_backdrop" ]; then
    if [ ! -e "${_CORE}/o_contrib_backdrop/redis_backdrop" ] \
      || [ ! -d "${_CORE}/o_contrib_backdrop/webform" ] \
      || [ "${_O_CONTRIB_FORCED_UP}" = "YES" ]; then
      _msg "${_STATUS} A: Running o_contrib_backdrop forced upgrade..."
      # The webform the sites run waits in a stage of this generation while
      # the bundle is rebuilt, and comes back if the new one was not fetched
      # (_satellite_restore_o_contrib_backdrop_webform on an interrupted pass).
      _bdKeep=""
      if [ -d "${_CORE}/o_contrib_backdrop/webform" ] \
        && [ ! -L "${_CORE}/o_contrib_backdrop/webform" ]; then
        _bdKeep=$(mktemp -d "${_D}/.webform-stage.${_CORE##*/}.XXXXXX") \
          && mv "${_CORE}/o_contrib_backdrop/webform" "${_bdKeep}/prev" \
          || _bdKeep=""
      fi
      cd ${_CORE}/o_contrib_backdrop
      rm -rf ${_CORE}/o_contrib_backdrop/*
      _satellite_download_o_contrib_backdrop
      cd ${_CORE}/o_contrib_backdrop
      if [ -n "${_bdKeep}" ]; then
        if [ ! -e "${_CORE}/o_contrib_backdrop/webform" ] && [ -d "${_bdKeep}/prev" ] \
          && mv "${_bdKeep}/prev" "${_CORE}/o_contrib_backdrop/webform"; then
          _msg "${_STATUS} A: o_contrib_backdrop keeps its previous webform"
        fi
        # a stage still holding the only copy waits for the restore step
        if [ -e "${_CORE}/o_contrib_backdrop/webform" ] || [ ! -d "${_bdKeep}/prev" ]; then
          rm -rf "${_bdKeep}"
        fi
      fi
    fi
  fi
  if [ ! -e "${_D}/000/modules/cache_backport/update-${_xSrl}-${_X_VERSION}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/cache_backport
    _get_dev_contrib "cache_backport-6.x-1.0-rc4.tar.gz"
    echo update > cache_backport/update-${_xSrl}-${_X_VERSION}.info
  fi
  if [ -e "${_D}/000/modules/redis" ]; then
    rm -rf ${_D}/000/modules/redis
  fi
  if [ ! -e "${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_edge
    _get_dev_contrib "redis_edge-${_REDIS_L_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_edge/ver-${_REDIS_L_VERSION}.${_xSrl}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_eight
    _get_dev_contrib "redis_eight-${_REDIS_N_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_eight/ver-${_REDIS_N_VERSION}.${_xSrl}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_compr
    _get_dev_contrib "redis_compr-${_REDIS_C_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_compr/ver-${_REDIS_C_VERSION}.${_xSrl}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_nine_ten
    _get_dev_contrib "redis_nine_ten-${_REDIS_T_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_nine_ten/ver-${_REDIS_T_VERSION}.${_xSrl}.info
  fi
  if [ ! -e "${_D}/000/modules/redis_ten_eleven/ver-${_REDIS_E_VERSION}.${_xSrl}.info" ]; then
    mkdir -p ${_D}/000/modules
    cd ${_D}/000/modules
    rm -rf ${_D}/000/modules/redis_ten_eleven
    _get_dev_contrib "redis_ten_eleven-${_REDIS_E_VERSION}.tar.gz"
    echo update > ${_D}/000/modules/redis_ten_eleven/ver-${_REDIS_E_VERSION}.${_xSrl}.info
  fi
  ### The Backdrop store is refreshed only where the bundle exists (or the
  ### support gate is on) so opted-out boxes never fetch it.
  if [ "${_BACKDROP_SUPPORT}" = "YES" ] \
    || [ -e "${_D}/000/modules/o_contrib_backdrop" ]; then
    if [ ! -e "${_D}/000/modules/redis_backdrop/ver-${_REDIS_B_VERSION}.${_xSrl}.info" ]; then
      mkdir -p ${_D}/000/modules
      cd ${_D}/000/modules
      rm -rf ${_D}/000/modules/redis_backdrop
      _get_dev_contrib "redis_backdrop-${_REDIS_B_VERSION}.tar.gz"
      chown -R root:root ${_D}/000/modules/redis_backdrop &> /dev/null
      echo update > ${_D}/000/modules/redis_backdrop/ver-${_REDIS_B_VERSION}.${_xSrl}.info
    fi
  fi
  find ${_D}/000/modules -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_D}/000/modules -type f -exec chmod 0644 {} \; &> /dev/null
}

#
# Manage o_contrib.
_satellite_manage_o_contrib() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_manage_o_contrib"
    _debug_proc
  fi
  if [ ! -e "${_CORE}/o_contrib_eleven" ]; then
    mkdir -p ${_CORE}/o_contrib_eleven
    cd ${_CORE}/o_contrib_eleven
    _satellite_download_o_contrib_eleven
    cd ${_CORE}/o_contrib_eleven
  fi
  if [ ! -e "${_CORE}/o_contrib_ten" ]; then
    mkdir -p ${_CORE}/o_contrib_ten
    cd ${_CORE}/o_contrib_ten
    _satellite_download_o_contrib_ten
    cd ${_CORE}/o_contrib_ten
  fi
  if [ ! -e "${_CORE}/o_contrib_nine" ]; then
    mkdir -p ${_CORE}/o_contrib_nine
    cd ${_CORE}/o_contrib_nine
    _satellite_download_o_contrib_nine
    cd ${_CORE}/o_contrib_nine
  fi
  if [ ! -e "${_CORE}/o_contrib_eight" ]; then
    mkdir -p ${_CORE}/o_contrib_eight
    cd ${_CORE}/o_contrib_eight
    _satellite_download_o_contrib_eight
    cd ${_CORE}/o_contrib_eight
  fi
  if [ ! -e "${_CORE}/o_contrib_seven" ]; then
    mkdir -p ${_CORE}/o_contrib_seven
    cd ${_CORE}/o_contrib_seven
    _satellite_download_o_contrib_seven
    cd ${_CORE}/o_contrib_seven
  fi
  if [ ! -e "${_CORE}/o_contrib" ]; then
    mkdir -p ${_CORE}/o_contrib
    cd ${_CORE}/o_contrib
    _satellite_download_o_contrib_six
    cd ${_CORE}/o_contrib
  fi
  ### Backdrop bundle creation is support-gated; an already existing bundle
  ### is kept fresh below regardless (opt-out is never a teardown).
  if [ "${_BACKDROP_SUPPORT}" = "YES" ] \
    && [ ! -e "${_CORE}/o_contrib_backdrop" ]; then
    mkdir -p ${_CORE}/o_contrib_backdrop
    cd ${_CORE}/o_contrib_backdrop
    _satellite_download_o_contrib_backdrop
    cd ${_CORE}/o_contrib_backdrop
  fi
  mkdir -p ${_D}/000/modules
  rm -f ${_D}/000/modules/o_contrib_eleven
  ln -sfn ${_CORE}/o_contrib_eleven ${_D}/000/modules/o_contrib_eleven
  rm -f ${_D}/000/modules/o_contrib_ten
  ln -sfn ${_CORE}/o_contrib_ten ${_D}/000/modules/o_contrib_ten
  rm -f ${_D}/000/modules/o_contrib_nine
  ln -sfn ${_CORE}/o_contrib_nine ${_D}/000/modules/o_contrib_nine
  rm -f ${_D}/000/modules/o_contrib_eight
  ln -sfn ${_CORE}/o_contrib_eight ${_D}/000/modules/o_contrib_eight
  rm -f ${_D}/000/modules/o_contrib_seven
  ln -sfn ${_CORE}/o_contrib_seven ${_D}/000/modules/o_contrib_seven
  rm -f ${_D}/000/modules/o_contrib
  ln -sfn ${_CORE}/o_contrib ${_D}/000/modules/o_contrib
  if [ -e "${_CORE}/o_contrib_backdrop" ]; then
    rm -f ${_D}/000/modules/o_contrib_backdrop
    ln -sfn ${_CORE}/o_contrib_backdrop ${_D}/000/modules/o_contrib_backdrop
  fi
  if [ "${_STATUS}" != "INIT" ]; then
    _satellite_check_fix_o_contrib
  fi
}

_satellite_hot_sauce_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_hot_sauce_check"
    _debug_proc
  fi
  _mNewC="Shared platforms code v.${_ALL_DISTRO} (new) will be created"
  _mLstC="Shared platforms code v.${_LAST_ALL} will be used"
  if [ "${_HOT_SAUCE}" = "NO" ]; then
    _CORE="${_D}/${_LAST_ALL}"
    _THIS_CORE="${_LAST_ALL}"
    if [ "${_USE_CURRENT}" = "YES" ] \
      && [ -e "${_D}/000/core-v-${_SMALLCORE6_V}.txt" ] \
      && [ -e "${_D}/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      _msg "${_STATUS} A: ${_mLstC}"
    elif [ "${_USE_CURRENT}" = "NO" ] \
      || [ ! -e "${_D}/000/core-v-${_SMALLCORE6_V}.txt" ] \
      || [ ! -e "${_D}/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      _CORE="${_D}/${_ALL_DISTRO}"
      _THIS_CORE="${_ALL_DISTRO}"
      _msg "${_STATUS} A: ${_mNewC}"
      sed -i "s/^_USE_CURRENT=.*/_USE_CURRENT=NO/g" ${_vBs}/${_filIncO}
      wait
    else
      _msg "${_STATUS} A: ${_mLstC}"
    fi
  else
    _CORE="${_D}/${_ALL_DISTRO}"
    _THIS_CORE="${_ALL_DISTRO}"
    _msg "${_STATUS} A: ${_mNewC}"
  fi
}

# A same-named group is HELD when another identity owns it: a listed member
# or a user whose primary group it is, the account's own identities excepted
# (their primary group IS the account's group once adopted or converted).
# Shared by the useradd site (AegirSetupA, a child process) and the launcher's
# post hook, which cannot pass a variable between them.
_instance_group_held() {
  local _g="$1" _gid _m
  getent group "${_g}" > /dev/null 2>&1 || return 1
  _m=$(getent group "${_g}" | cut -d: -f4 | tr ',' '\n' | grep -v -E "^${_g}(\.|$)")
  [ -n "${_m}" ] && return 0
  _gid=$(getent group "${_g}" | cut -d: -f3)
  getent passwd | awk -F: -v g="${_gid}" -v u="${_g}" \
    '$4 == g && $1 != u && index($1, u ".") != 1 { f=1 } END { exit !f }'
}

_satellite_add_user_dirs() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_add_user_dirs"
    _debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Creating directories with correct permissions"
  fi
  mkdir -p /data/u
  mkdir -p /data/disk
  mkdir -p /data/conf
  chown root:root /data &> /dev/null
  chown root:root /data/disk &> /dev/null
  if [ ! -d "${_ROOT}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Adding user..."
    fi
    find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -f {} \; &> /dev/null
    # Born into a private primary group named after the account (the
    # per-instance group model, see instgrp): everything the account's
    # identities create from here on is group-owned by the account alone,
    # never by the box-wide 'users'. 'users' stays SUPPLEMENTARY on the
    # identity -- it is the binary execute ACL (root:users 0750), not a data
    # group. A same-named group left behind by an earlier purge is adopted
    # only while nobody holds it. _INSTANCE_GROUP=NO in the cnf keeps the
    # box-wide primary group. Born converted only when the box is ready for
    # it -- the tool present and every fetched root-run writer group-aware,
    # the gate the upgrade arm's convert enforces: a pre-compat websh would
    # lock the newborn out of its shell, an old nightly worker would
    # re-flatten its tree. Otherwise it is born on the box-wide group and
    # the next upgrade converts it.
    _ACCG="${_USRG}"
    if [ "${_INSTANCE_GROUP}" != "NO" ]; then
      if [ -x "/opt/local/bin/instgrp" ] \
        && bash /opt/local/bin/instgrp check > /dev/null 2>&1; then
        if ! getent group "${_USER}" > /dev/null 2>&1; then
          addgroup --system "${_USER}" &> /dev/null
        fi
        if getent group "${_USER}" > /dev/null 2>&1 \
          && ! _instance_group_held "${_USER}"; then
          _ACCG="${_USER}"
        else
          _msg "NOTE: group ${_USER} exists and is held by someone else; ${_USER} is born on the box-wide group"
        fi
      else
        _msg "NOTE: instgrp absent or the box not ready for the per-instance group (instgrp check); ${_USER} is born on the box-wide group, the next upgrade converts it"
      fi
    fi
    adduser --system --home ${_ROOT} --ingroup ${_ACCG} ${_USER} &> /dev/null
    adduser ${_USER} ${_USRG} &> /dev/null
    adduser ${_USER} ${_WEBG} &> /dev/null
    _ACCG=$(_acct_group "${_USER}")
  fi
  # No blanket chown of the scratch root here. It used to hand the whole tree
  # to this user -- including the build tree root sources on its next pass, and
  # every scratch file the next root writer reopens -- while only the top inode
  # was ever handed back, so root was left opening files it did not own inside
  # a sticky directory. The children need nothing outside their own paths.
  # /data/conf is box-wide and stays root's for the whole run: every site on
  # the box loads its global includes from it, and nothing run as the account
  # writes there. A run of an earlier release handed it to the account, and
  # one that stopped before its cleanup left it so: it is taken back here,
  # before anything runs as the account (_satellite_conf_root_here).
  _acct_in_real_dir /data/conf _satellite_conf_root_here &> /dev/null
  # On a fresh install the per-child includes are materialised before
  # this user exists, so ownership must be re-asserted here or the su'd
  # children cannot read their 0600 copies
  for _hndChd in AegirSetupB AegirSetupC; do
    if [ -e "${_vBs}/${_filIncO}.${_USER}.${_hndChd}" ]; then
      chown ${_USER}:${_USRG} \
        ${_vBs}/${_filIncO}.${_USER}.${_hndChd} &> /dev/null
      chmod 0600 ${_vBs}/${_filIncO}.${_USER}.${_hndChd}
    fi
  done
}

_satellite_prepare_child_scripts() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_prepare_child_scripts"
    _debug_proc
  fi
  chmod 0711 ${_ROOT}
  cd ${_ROOT}
  _AegirSetupB="${_bldPth}/aegir/scripts/AegirSetupB.sh.txt"
  _AegirSetupC="${_bldPth}/aegir/scripts/AegirSetupC.sh.txt"
  # Ownership follows the writer: root owns the state root, and each child gets
  # exactly one directory of its own to signal in, so nothing a child writes
  # lands anywhere a later root writer will reopen.
  mkdir -p /opt/tmp/state/${_USER} &> /dev/null
  chown root:root /opt/tmp/state &> /dev/null
  chmod 0755 /opt/tmp/state &> /dev/null
  chown ${_USER}:${_USRG} /opt/tmp/state/${_USER} &> /dev/null
  chmod 0700 /opt/tmp/state/${_USER} &> /dev/null
  # Root's own markers (AegirSetupA OK/FAIL) live in a root-owned tree: a
  # tenant-planted symlink in the user-owned dir above must never be followed
  # by root's touch. Same name layout, one level down under .root.
  mkdir -p /opt/tmp/state/.root/${_USER} &> /dev/null
  chown root:root /opt/tmp/state/.root /opt/tmp/state/.root/${_USER} &> /dev/null
  chmod 0755 /opt/tmp/state/.root &> /dev/null
  chmod 0700 /opt/tmp/state/.root/${_USER} &> /dev/null
  # No chown into the build tree: the children are started as
  # `su - <user> -c "/bin/bash <script>"`, so they need read and nothing more,
  # and the tree is left 0755 for exactly that. Handing these two files to the
  # satellite user was only ever a workaround for their 0700 mode, and it put
  # user-writable files on a path root sources.
}

#
# Generate provision backend db_passwd.
_provision_backend_dbpass_generate() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _provision_backend_dbpass_generate"
    _debug_proc
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _ESC_PASS=""
  _LEN_PASS=0
  if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
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
  if [ "${_STRONG_PASSWORDS}" = "YES" ] \
    || [ "${_PWD_CHARS}" -gt 32 ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
        _ESC_PASS="$(openssl rand -base64 64 | tr -d '\n')"
      else
        _RANDPASS_TEST=$(randpass -V 2>&1)
        if [[ "${_RANDPASS_TEST}" =~ "alnum" ]]; then
          _ESC_PASS=$(randpass "${_PWD_CHARS}" alnum 2>&1)
        else
          _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
          _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
          _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
        fi
      fi
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _isPythonTwo="$(which python2)"
    _isPythonThree="$(which python3)"
    _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
    if [ -x "${_isPythonThree}" ]; then
      _ENC_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${_ESC_PASS}'''))")
    elif [ -x "${_isPythonTwo}" ]; then
      _ENC_PASS=$(python2 -c "import urllib; print urllib.quote('''${_ESC_PASS}''')")
    fi
    _LEN_PASS=$(echo ${#_ESC_PASS} 2>&1)
  fi
  if [ -z "${_ESC_PASS}" ] || [ "${_LEN_PASS}" -lt 9 ]; then
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      _ESC_PASS=$(shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0' 2>&1)
      _ESC_PASS=$(echo -n "${_ESC_PASS}" | tr -d "\n" 2>&1)
      _ESC_PASS=$(_sanitize_string "${_ESC_PASS}" 2>&1)
    else
      if [ -e "/root/.my.pass.txt" ]; then
        _ESC_PASS=$(cat /root/.my.pass.txt 2>/dev/null | tr -d '\n')
      else
        _ESC_PASS=sCWL4tgEpyS5cLZITshxSTWRjhsUOeR6
      fi
    fi
    _ENC_PASS="${_ESC_PASS}"
  fi

  ### Both files are put in the account root (the instance user's) as fresh
  ### 0600 files handed to that user, never written, handed over or given a
  ### mode through a link put at the name.
  _L_SYS="${_ROOT}/.${_USER}.pass.txt"
  echo "${_ESC_PASS}" | _acct_in_real_dir "${_ROOT}" _satellite_put_stdin_here \
    ".${_USER}.pass.txt" 0600 "${_USER}:${_ACCG:-users}"

  ### The install path resolves the mode before it writes this file (FQDN
  ### becomes the box's own name, PROXYSQL the local proxy address); this
  ### path kept the raw literal, so after the first upgrade the file named a
  ### host nothing can connect to. _THIS_DB_HOST itself stays as it is: the
  ### blocks below still branch on the literal.
  _OCT_DB_HOST_W="${_THIS_DB_HOST}"
  if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _OCT_DB_HOST_W="${_hName}"
  elif [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
    _OCT_DB_HOST_W=127.0.0.1
  fi
  _L_SYS_PHP="${_ROOT}/.${_USER}.pass.php"
  { echo "<?php"
    echo "\$oct_db_user = \"${_USER}\";"
    echo "\$oct_db_pass = \"${_ESC_PASS}\";"
    echo "\$oct_db_host = \"${_OCT_DB_HOST_W}\";"
    echo "\$oct_db_port = \"${_THIS_DB_PORT}\";"
    echo "\$oct_db_dirs = \"/data/disk/${_USER}/backups\";"
  } | _acct_in_real_dir "${_ROOT}" _satellite_put_stdin_here \
    ".${_USER}.pass.php" 0600 "${_USER}:${_ACCG:-users}"

  _ESC="*.*"

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    _USE_AEGIR_HOST="${_hName}"
    _SQL_CONNECT=localhost
    if [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
      _SQL_CONNECT=127.0.0.1
    fi
    _USE_DB_USER="${_USER}"
  else
    _USE_AEGIR_HOST="${_hName}"
    _SQL_CONNECT="${_THIS_DB_HOST}"
    _USE_DB_USER=aegir_root
  fi
  if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
    _USE_AEGIR_HOST="${_hName}"
    _SQL_CONNECT=localhost
  fi
  _find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"

  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
  fi

  if [ "${_THIS_DB_HOST}" = "localhost" ] \
    || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
    || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
    || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL14 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
        _write_proxysql_adm_cnf &> /dev/null
        mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
      fi
      ###
      ###
      # if [ -e "/root/.my.cluster_root_pwd.txt" ]; then
      #   _ROOT_SQL_PASWD=$(cat /root/.my.cluster_root_pwd.txt 2>&1)
      #   _ROOT_SQL_PASWD=$(echo -n ${_ROOT_SQL_PASWD} | tr -d "\n" 2>&1)
      # elif [ -e "/root/.my.pass.txt" ]; then
      #   _ROOT_SQL_PASWD=$(cat /root/.my.pass.tx 2>&1)
      #   _ROOT_SQL_PASWD=$(echo -n ${_ROOT_SQL_PASWD} | tr -d "\n" 2>&1)
      # fi
      # if [ -e "/root/.my.cluster_write_node.txt" ]; then
      #   _CL_WR_NODE=$(cat /root/.my.cluster_write_node.txt 2>&1)
      #   _CL_WR_NODE=$(echo -n ${_CL_WR_NODE} | tr -d "\n" 2>&1)
      #   _SQL_CONNECT="${_CL_WR_NODE}"
      #   _THIS_DB_PORT="3306"
      # fi
      ### -p${_ROOT_SQL_PASWD}
      ### [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL14CR -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
      ###
      ###
      mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    else
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
        || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL15 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
        if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
          _write_proxysql_adm_cnf &> /dev/null
          mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
        fi
        _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
        ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
        ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
        ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
        ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
        ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
        mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
      fi
    fi
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
  fi
}

#
# Re-assert hosting_dispatch_enabled before kicking the queue (satellite copy,
# kept separate from the master.sh.inc copy by design). An Octopus instance runs
# hosting-setup as its own user, and a non-zero dispatch self-test there leaves
# the dispatcher disabled, silently stopping the task queue. Detect and re-enable,
# reporting only when a correction was needed.
#   su   -> caller is root (pre-install): su to the instance user.
#   bare -> caller already runs as the instance user (SetupB child).
_ensure_hosting_dispatch_enabled() {
  local _disp_mode="${1:-bare}"
  local _disp_ev
  local _disp_fix
  _disp_ev='if (!variable_get("hosting_dispatch_enabled", FALSE)) { variable_set("hosting_dispatch_enabled", TRUE); echo "REENABLED"; }'
  if [[ "${_disp_mode}" = "su" ]]; then
    _disp_fix=$(su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster ev '${_disp_ev}'" 2>/dev/null)
  else
    _disp_fix=$(${_DRUSHCMD} @hostmaster ev "${_disp_ev}" 2>/dev/null)
  fi
  if [[ "${_disp_fix}" =~ REENABLED ]]; then
    _msg "INFO: hosting_dispatch_enabled was off for ${_USER}; task queue dispatcher re-enabled"
  fi
}

#
# Sync provision backend db_passwd.
_provision_backend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _provision_backend_dbpass_sync"
    _debug_proc
  fi
  _find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  _RESOLVEIP="${_LOC_IP}"
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Syncing provision backend db_passwd..."
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  _L_SYS="${_ROOT}/.${_USER}.pass.txt"
  ### The account home allows traversal, so a lax mode on these backups is
  ### readable by local users by exact path; never trust the moved file's
  ### inherited mode -- set 0600 explicitly. Moved by name inside the real
  ### account root (-T: a link put at the backup name is replaced, never
  ### followed into the directory it leads to), and the mode is set through
  ### a handle only on a file with a single link (_SAT_NOFOLLOW_CHMOD_PL).
  _acct_in_real_dir "${_ROOT}" mv -f -T -- "./.${_USER}.pass.txt" \
    "./.${_USER}.pass.txt-pre-${_xSrl}-${_X_VERSION}-${_NOW}" &> /dev/null
  _acct_in_real_dir "${_ROOT}" _satellite_chmod_nofollow f 0600 \
    "./.${_USER}.pass.txt-pre-${_xSrl}-${_X_VERSION}-${_NOW}" &> /dev/null
  _L_SYS_PHP="${_ROOT}/.${_USER}.pass.php"
  _acct_in_real_dir "${_ROOT}" mv -f -T -- "./.${_USER}.pass.php" \
    "./.${_USER}.pass.php-pre-${_xSrl}-${_X_VERSION}-${_NOW}" &> /dev/null
  _acct_in_real_dir "${_ROOT}" _satellite_chmod_nofollow f 0600 \
    "./.${_USER}.pass.php-pre-${_xSrl}-${_X_VERSION}-${_NOW}" &> /dev/null
  _provision_backend_dbpass_generate
  if [ ! -z "${_ESC_PASS}" ] || [ ! -z "${_ENC_PASS}" ]; then
    su -s /bin/bash - ${_USER} -c "${_DRUSHCMD} @hostmaster \
      sqlq \"UPDATE hosting_db_server SET db_passwd='${_ESC_PASS}' \
      WHERE db_user='${_USER}'\"" &> /dev/null
    wait
    _ESC="*.*"
    _USE_DB_USER="${_USER}"
    _USE_AEGIR_HOST="${_hName}"
    _find_correct_ip
    _USE_RESOLVEIP="${_LOC_IP}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL16 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_ESC_PASS}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_ESC_PASS}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_ESC_PASS}';
EOFMYSQL
    ### The aliases are the instance user's: edited inside the real .drush,
    ### never through a link put at an alias or at .drush.
    _acct_in_real_dir "${_ROOT}/.drush" _satellite_edit_all_here \
      "s/mysql:\/\/${_USER}:.*/mysql:\/\/${_USER}:${_ENC_PASS}@${_SQL_CONNECT}',/g" \
      'server_*.alias.drushrc.php' &> /dev/null
    wait
  else
    _msg "CRIT: _ESC_PASS empty or not generated"
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
  fi
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} cc drush" &> /dev/null
  wait
  _acct_in_real_dir "${_ROOT}/.tmp" rm -rf -- ./cache
  if [ -e "${_ROOT}/.drush/server_localhost.alias.drushrc.php" ]; then
    su -s /bin/bash - ${_USER} -c "${_DRUSHCMD:-drush8} @hostmaster \
      hosting-task @server_localhost verify --force" &> /dev/null
  else
    su -s /bin/bash - ${_USER} -c "${_DRUSHCMD:-drush8} @hostmaster \
      hosting-task @server_master verify --force" &> /dev/null
  fi
  wait
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Running hosting-dispatch/hosting-tasks..."
  fi
  _ensure_hosting_dispatch_enabled su
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-dispatch" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  sleep 5
  su -s /bin/bash ${_USER} -c "${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0" &> /dev/null
  wait
  # The sweeps above run their tasks synchronously (--fork=0), but a runner
  # forked by the regular dispatch can still be in flight. AegirSetupB is
  # about to swap the live drush/provision trees (.drush/sys, .drush/usr,
  # tools/drush); a task runner still executing from them dies on its next
  # lazy include without ever writing its final status - that write only
  # happens in the runner's own shutdown handler - leaving the task parked
  # at PROCESSING and the queue wedged behind it for the whole running-items
  # window. Give in-flight runners a bounded window to finish instead of
  # racing them; the dispatcher-side reaper heals whatever this misses.
  _QUIESCE_WAIT=0
  while pgrep -u "${_USER}" -f "drush.php.*hosting-task" > /dev/null 2>&1; do
    _QUIESCE_WAIT=$(( _QUIESCE_WAIT + 1 ))
    if [[ "${_QUIESCE_WAIT}" -ge 60 ]]; then
      break
    fi
    sleep 5
  done
}

#
# The option $2 (db_user, db_name, db_passwd) of the drushrc.php in the real
# directory $1, parsed as before from a bounded read that never follows a
# link or blocks on a FIFO.
_satellite_drc_get() {
  _acct_read_in "${1}" drushrc.php \
    | grep "options\['${2}'\] = " \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,';]//g" 2>&1
}
# True when no other hostmaster on this box, another account's or the
# master's, has $1 as its database user. Each alias and drushrc.php is read
# as _satellite_drc_get reads it, and a site path is followed only inside
# that instance's own hostmaster tree.
_satellite_hm_dbuser_own() {
  local _a _p
  for _a in /var/aegir /data/disk/*; do
    [ "${_a}" = "${_ROOT}" ] && continue
    [ -d "${_a}/.drush" ] || continue
    _p=$(_acct_read_in "${_a}/.drush" hostmaster.alias.drushrc.php \
      | grep "site_path'" \
      | cut -d: -f2 \
      | awk '{ print $3}' \
      | sed "s/[\,']//g" 2>&1)
    case "${_p}" in
      *[!A-Za-z0-9._/-]*|*/../*) continue ;;
      "${_a}"/aegir/distro/*/sites/?*|/var/aegir/*/sites/?*) ;;
      *) continue ;;
    esac
    [ "$(_satellite_drc_get "${_p}" db_user)" = "${1}" ] && return 1
  done
  return 0
}

#
# Sync hostmaster frontend db_passwd.
_hostmaster_frontend_dbpass_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _hostmaster_frontend_dbpass_sync"
    _debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Syncing hostmaster frontend db_passwd..."
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  ### The alias and the site's drushrc.php are the instance user's: read
  ### bounded, never through a link or from a FIFO, and only from a site in
  ### the account's own hostmaster tree.
  _THIS_HM_SPTH=$(_satellite_hm_alias_get "site_path'")
  _satellite_hm_path_ok "${_THIS_HM_SPTH}" site || _THIS_HM_SPTH=""
  _THIS_HM_DBUR=""
  _THIS_HM_DBPD=""
  if [ -n "${_THIS_HM_SPTH}" ]; then
    _THIS_HM_DBUR=$(_satellite_drc_get "${_THIS_HM_SPTH}" db_user)
    _THIS_HM_DBPD=$(_satellite_drc_get "${_THIS_HM_SPTH}" db_passwd)
    ### Both go into SQL root runs: the user only as a plain database user
    ### name that is not one of the server's own, the password only in the
    ### alphabets the provisioning and BOA generators use. The user is also
    ### the site's database name, as provisioning and transfers set it, and
    ### no other hostmaster on this box names it as its own.
    if [[ ! "${_THIS_HM_DBUR}" =~ ^[A-Za-z0-9_]{1,32}$ ]] \
      || [ "${_THIS_HM_DBUR}" = "root" ] \
      || [ "${_THIS_HM_DBUR}" = "aegir_root" ] \
      || [ -e "/data/disk/${_THIS_HM_DBUR}" ] \
      || [[ ! "${_THIS_HM_DBPD}" =~ ^[A-Za-z0-9%@._+=/-]+$ ]] \
      || [ "${_THIS_HM_DBUR}" != "$(_satellite_drc_get "${_THIS_HM_SPTH}" db_name)" ] \
      || ! _satellite_hm_dbuser_own "${_THIS_HM_DBUR}"; then
      if [ -n "${_THIS_HM_DBUR}" ] || [ -n "${_THIS_HM_DBPD}" ]; then
        _msg "ALRT: ${_USER} hostmaster db_user or db_passwd is not in the expected form, or db_user is not this instance's own; frontend db sync skipped"
      fi
      _THIS_HM_DBUR=""
      _THIS_HM_DBPD=""
    fi
  fi
  if [ -e "${_THIS_HM_SPTH}" ] \
    && [ ! -z "${_THIS_HM_DBUR}" ] \
    && [ ! -z "${_THIS_HM_DBPD}" ]; then
    _ESC="*.*"
    _USE_DB_USER="${_THIS_HM_DBUR}"
    _USE_AEGIR_HOST="${_hName}"
    _find_correct_ip
    _USE_RESOLVEIP="${_LOC_IP}"
    [ -e "/root/.my.cluster_root_pwd.txt" ] && echo "SQL17 -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -uroot"
    if [ -e "/root/.my.proxysql_adm_pwd.txt" ]; then
      _write_proxysql_adm_cnf &> /dev/null
      mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_USE_DB_USER}';
DELETE FROM mysql_query_rules WHERE username='${_USE_DB_USER}';
INSERT INTO mysql_users (username,password,default_hostgroup) VALUES ('${_USE_DB_USER}','${_THIS_HM_DBPD}','10');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS FROM RUNTIME;
SAVE MYSQL USERS TO DISK;
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',10,1);
INSERT INTO mysql_query_rules (username,destination_hostgroup,active) VALUES ('${_USE_DB_USER}',11,1);
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
PROXYSQL
    fi
    _C_SQL="mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp --database=mysql -e"
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_AEGIR_HOST}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'${_USE_RESOLVEIP}';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'localhost';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'127.0.0.1';" &> /dev/null
    ${_C_SQL} "DROP USER '${_USE_DB_USER}'@'%';" &> /dev/null
    mysql --silent -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp -u root mysql<<EOFMYSQL
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'localhost';
CREATE USER IF NOT EXISTS '${_USE_DB_USER}'@'%';
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL ON ${_ESC} TO '${_USE_DB_USER}'@'%' WITH GRANT OPTION;
ALTER USER '${_USE_DB_USER}'@'localhost' IDENTIFIED BY '${_THIS_HM_DBPD}';
ALTER USER '${_USE_DB_USER}'@'%' IDENTIFIED BY '${_THIS_HM_DBPD}';
EOFMYSQL
  fi
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
    mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-privileges &> /dev/null
  else
    mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG PRIVILEGES" &> /dev/null
  fi
}

_satellite_run_pre_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_run_pre_install"
    _debug_proc
  fi
  _find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  _RESOLVEIP="${_LOC_IP}"
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    _SQL_CONNECT=127.0.0.1
    _THIS_DB_PORT=6033
  else
    _THIS_DB_PORT=3306
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
      _SQL_CONNECT=127.0.0.1
      _THIS_DB_PORT=6033
      mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-hosts &> /dev/null
    else
      mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG HOSTS" &> /dev/null
    fi
    _provision_backend_dbpass_generate
    _sudoers_safe_append /etc/sudoers \
      "${_USER} ALL=NOPASSWD: /etc/init.d/nginx" "${_USER} ALL=NOPASSWD"
    _SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership fix-drupal-site-symlinks lock-local-drush-permissions)
    for _SCRIPT in ${_SCRIPTS[@]}; do
      _sudoers_safe_append /etc/sudoers.d/${_SCRIPT} \
        "${_USER} ALL=NOPASSWD: /usr/local/bin/${_SCRIPT}.sh"
    done
  else
    _sudoers_safe_append /etc/sudoers \
      "${_USER} ALL=NOPASSWD: /etc/init.d/nginx" "${_USER} ALL=NOPASSWD"
    _SCRIPTS=(fix-drupal-platform-permissions fix-drupal-site-permissions fix-drupal-platform-ownership fix-drupal-site-ownership fix-drupal-site-symlinks lock-local-drush-permissions)
    for _SCRIPT in ${_SCRIPTS[@]}; do
      _sudoers_safe_append /etc/sudoers.d/${_SCRIPT} \
        "${_USER} ALL=NOPASSWD: /usr/local/bin/${_SCRIPT}.sh"
    done
    if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
      _SQL_CONNECT=127.0.0.1
      _THIS_DB_PORT=6033
      mysqladmin -u root -h${_SQL_CONNECT} -P${_THIS_DB_PORT} --protocol=tcp flush-hosts &> /dev/null
    else
      mysql -u root -e "FLUSH NO_WRITE_TO_BINLOG HOSTS" &> /dev/null
    fi
    _RST=$(syncpass fix ${_USER} 2>&1)
    _provision_backend_dbpass_sync
  fi
  cd ${_ROOT}
}

#
# Download for Drush Make Local build.
_satellite_download_for_local_build() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_download_for_local_build"
    _debug_proc
  fi
  _mL="/opt/tmp/make_local"
  mkdir -p ${_mL}
  if [ ! -e "${_mL}/hostmaster/hostmaster.make" ] \
    || [ ! -e "${_mL}/hosting/hosting.module" ] \
    || [ ! -e "${_mL}/drupal/modules/system/system.module" ]; then
    rm -rf ${_mL}
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: Downloading hostmaster modules..."
    fi
    if [ "${_DL_MODE}" = "BATCH" ]; then
      rm -rf /opt/tmp/make_local
      cd /opt/tmp
      _get_dev_ext "make_local.tar.gz"
      if [ -e "${_mL}/hostmaster/hostmaster.make" ] \
        && [ -e "${_mL}/hosting/hosting.module" ] \
        && [ -e "${_mL}/drupal/modules/system/system.module" ]; then
        [ -e "make_local.tar.gz" ] && rm -f make_local.tar.gz
      fi
    else
      mkdir -p ${_mL}
      cd ${_mL}
      ### Drupal Core
      _get_core_ext "${_DRUPAL7}.tar.gz"
      mv -f ${_mL}/${_DRUPAL7} ${_mL}/drupal
      ### Ægir Core
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hostmaster.git    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting.git       &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/eldir.git         &> /dev/null
      ### Ægir Golden + BOA Settings
        ${_gCb} 5.x-${_tRee} ${_gitHub}/aegir_objects.git                  &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_civicrm.git                &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_custom_settings.git        &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_deploy.git                 &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_git.git                    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_le.git                     &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_remote_import.git          &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_site_backup_manager.git    &> /dev/null
        ${_gCb} 5.x-${_tRee} ${_gitHub}/hosting_tasks_extra.git            &> /dev/null
        rm -rf */.git
      ### Ægir Drupal Contrib
      _get_dev_stc "admin_menu-7.x-3.0-rc7.tar.gz"
      _get_dev_stc "betterlogin-7.x-1.5.tar.gz"
      _get_dev_stc "ctools-7.x-1.21.tar.gz"
      _get_dev_stc "entity-7.x-1.12.tar.gz"
      _get_dev_stc "libraries-7.x-2.5.tar.gz"
      _get_dev_stc "module_filter-7.x-2.3.tar.gz"
      _get_dev_stc "openidadmin-7.x-1.0.tar.gz"
      _get_dev_stc "overlay_paths-7.x-1.3.tar.gz"
      _get_dev_stc "r4032login-7.x-1.8.tar.gz"
      _get_dev_stc "tfa_basic-7.x-1.1.tar.gz"
      _get_dev_stc "tfa-7.x-2.1.tar.gz"
      _get_dev_stc "timeago-7.x-2.3.tar.gz"
      _get_dev_stc "views_bulk_operations-7.x-3.7.tar.gz"
      _get_dev_stc "views-7.x-3.30.tar.gz"
      ### Ægir Third Party Libraries
      _get_dev_stc "qrcodejs.tar.gz"
      _get_dev_stc "timeagojs.tar.gz"
      _get_dev_stc "vuejs.tar.gz"
      ### BOA Drupal Contrib
      _get_dev_stc "tag1_d7es-7.x-1.4.tar.gz"
      _get_dev_stc "features_extra-7.x-1.2.tar.gz"
      _get_dev_stc "features-7.x-2.15.tar.gz"
      _get_dev_stc "idna_convert-7.x-1.0.tar.gz"
      _get_dev_stc "revision_deletion-7.x-1.3.tar.gz"
      _get_dev_stc "strongarm-7.x-2.0.tar.gz"
      _get_dev_stc "userprotect-7.x-1.3.tar.gz"
      _get_dev_stc "environment_indicator-7.x-2.9.tar.gz"
    fi
    find ${_mL} -type d -exec chmod 0755 {} \; &> /dev/null
    find ${_mL} -type f -exec chmod 0644 {} \; &> /dev/null
    chown -R root:root ${_mL}
  fi
}

#
# Run child B.
_satellite_run_child_b() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_run_child_b"
    _debug_proc
  fi
  _find_correct_ip
  _USE_RESOLVEIP="${_LOC_IP}"
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Switching user and running AegirSetupB..."
    fi
    rm -f /opt/tmp/testecho*
    chown root:${_USRG} /data/u &> /dev/null
    chmod 0771 /data/u &> /dev/null
    su -s /bin/bash - ${_USER} -c "/bin/bash ${_AegirSetupB} ${_USER}"
    wait
    if [ -e "/opt/tmp/state/${_USER}/status-AegirSetupB-FAIL" ] \
      || [ ! -e "/opt/tmp/state/${_USER}/status-AegirSetupB-OK" ]; then
      _msg "${_STATUS} A: FATAL ERROR: AegirSetupB installer failed"
      _msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
      touch "/opt/tmp/state/.root/${_USER}/status-AegirSetupA-FAIL"
      exit 1
    fi
    chmod 0700 /data/u &> /dev/null
    chown root:root /data/u &> /dev/null
    _msg "${_STATUS} A: Ægir Satellite Instance installed"
  else
    if [ "${_PLATFORMS_ONLY}" = "YES" ]; then
      _msg "${_STATUS} A: Satellite Instance Hostmaster upgrade skipped"
    else
      ### .drush is the instance user's: its layout is rebuilt by that user
      ### (the clone lands in its own tree as before, handed to it below),
      ### and root removes names there only inside the real directories.
      if [ ! -d "${_ROOT}/.drush/sys/provision/http" ]; then
        _satellite_as_user "mkdir -p ${_ROOT}/.drush/sys \
          ${_ROOT}/.drush/xts ${_ROOT}/.drush/usr; \
          rm -rf ${_ROOT}/.drush/provision ${_ROOT}/.drush/sys/provision; \
          ${_gCb} ${_BRANCH_PRN} ${_gitHub}/provision.git \
          ${_ROOT}/.drush/sys/provision" &> /dev/null
      fi
      _acct_in_real_dir "${_ROOT}/.drush" rm -rf -- ./drush_make
      _acct_in_real_dir "${_ROOT}/.drush/sys" rm -rf -- ./drush_make
      _hostmaster_frontend_dbpass_sync
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "${_STATUS} A: Switching user and running AegirSetupB..."
      fi
      rm -f /opt/tmp/testecho*
      _THIS_HM_ROOT=$(_satellite_hm_alias_get "root'")
      _THIS_HM_SITE=$(_satellite_hm_alias_get "site_path'")
      # a CLI php.ini an earlier release left (+i) would refuse the chown;
      # the ltd worker removes it. Cleared inside the real .drush only.
      _U_HD="${_ROOT}/.drush"
      _acct_in_real_dir "${_U_HD}" _satellite_unlock_here php.ini
      ### handed over inside each real directory, so the walk never follows
      ### a link the account put at .drush, backups, clients, config or
      ### tools, and never hands over a link, a FIFO or a hard-linked file
      ### the account left in the tree (_satellite_reown_here)
      _acct_in_real_dir "${_ROOT}/.drush" \
        _satellite_reown_here "${_USER}:${_ACCG:-users}"
      _acct_in_real_dir "${_ROOT}/backups" \
        _satellite_reown_here "${_USER}:${_ACCG:-users}"
      _acct_in_real_dir "${_ROOT}/clients" \
        _satellite_reown_here "${_USER}:${_ACCG:-users}"
      # nginx reads the basic auth password files on every request: their
      # group is the web server's, so the hand-over leaves that subtree to
      # the setter below and never takes them out of it for a moment.
      # -execdir, never -exec: each name is changed inside the directory
      # find entered without following a link, through a handle, so no
      # directory between is looked up again by path (the account could
      # have swapped it for a link by then). -execdir wants an absolute PATH.
      _acct_in_real_dir "${_ROOT}/config" \
        _satellite_reown_here "${_USER}:${_ACCG:-users}" \
        -path ./server_master/nginx/passwords.d -prune -o
      _satellite_server_master_modes basic_auth &> /dev/null
      _acct_in_real_dir "${_ROOT}/tools" \
        _satellite_reown_here "${_USER}:${_ACCG:-users}"
      ### The hostmaster root and site come from the account's own alias:
      ### handed over only inside its own real hostmaster tree.
      if _satellite_hm_path_ok "${_THIS_HM_ROOT}"; then
        _acct_in_real_dir "${_THIS_HM_ROOT}" _satellite_reown_here "${_USER}"
      else
        _msg "${_STATUS} A: NOTE: hostmaster root outside ${_ROOT}/aegir/distro left as it is"
      fi
      if _satellite_hm_path_ok "${_THIS_HM_SITE}" site; then
        ### files/ moved into the account's store (autosymlink) is a link:
        ### the link is made anew as the account's own under a fresh name
        ### and renamed over it (never chowned by name, where a file could
        ### be swapped in), and the modes are set in the store it leads to
        ### when that is the account's own.
        _T_WG=$(_web_group "${_USER}")
        if [ -L "${_THIS_HM_SITE}/files" ]; then
          _acct_in_real_dir "${_THIS_HM_SITE}" \
            _satellite_relink_here files "${_USER}${_T_WG:+:${_T_WG}}"
        else
          _acct_in_real_dir "${_THIS_HM_SITE}/files" \
            _satellite_reown_here "${_USER}${_T_WG:+:${_T_WG}}"
        fi
        _satellite_in_store_dir "${_THIS_HM_SITE}/files" \
          _satellite_tree_mode_all_here 02775 0664
      else
        _msg "${_STATUS} A: NOTE: hostmaster site outside ${_ROOT}/aegir/distro left as it is"
      fi
      chown root:${_USRG} /data/u &> /dev/null
      chmod 0771 /data/u &> /dev/null
      su -s /bin/bash - ${_USER} -c "/bin/bash ${_AegirSetupB} ${_USER}"
      wait
      _acct_in_real_dir "${_ROOT}/tools/drush" \
        _satellite_reown_here "${_USER}:${_ACCG:-users}"
      _satellite_update_drush_php_cli
      _satellite_update_local_dirs_cli
      if [ -e "/opt/tmp/state/${_USER}/status-AegirSetupB-FAIL" ] \
        || [ ! -e "/opt/tmp/state/${_USER}/status-AegirSetupB-OK" ]; then
        _msg "${_STATUS} A: FATAL ERROR: AegirSetupB installer failed"
        _msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
        touch "/opt/tmp/state/.root/${_USER}/status-AegirSetupA-FAIL"
        exit 1
      else
        ### Old hostmaster backups go to backups/system/old_hostmaster: both
        ### directories are made and handed over by root inside their real
        ### directories (backups may be a link into the account's store),
        ### and the instance user moves its own files there.
        _satellite_in_store_dir "${_ROOT}/backups" \
          _satellite_sys_dir_here old_hostmaster &> /dev/null
        _satellite_as_user "_d=${_ROOT}/backups/system/old_hostmaster; \
          mv -f ${_ROOT}/backups/*host8* \${_d}/; \
          mv -f ${_ROOT}/backups/*o8.io* \${_d}/; \
          mv -f ${_ROOT}/backups/*boa.io* \${_d}/; \
          mv -f ${_ROOT}/backups/*aegir.cc* \${_d}/; \
          chmod 600 \${_d}/*" &> /dev/null
        _hostmaster_frontend_dbpass_sync
      fi
      su -s /bin/bash - ${_USER} -c "drush8 @hm rr" &> /dev/null
      wait
      chmod 0700 /data/u &> /dev/null
      chown root:root /data/u &> /dev/null
      _msg "${_STATUS} A: Ægir Satellite Instance upgrade completed"
    fi
  fi
}

_satellite_if_create_local_bin() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_create_local_bin"
    _debug_proc
  fi
  ### bin/ is the instance user's: handed over and linked inside the real
  ### directory only, never through a link put at bin.
  _L_BIN="${_ROOT}/bin"
  if [ ! -d "${_L_BIN}" ]; then
    mkdir -p ${_L_BIN}
    _acct_in_real_dir "${_L_BIN}" _satellite_own_dir_here \
      "${_USER}:${_ACCG:-users}" 700
  fi
  if [ ! -L "${_L_BIN}/drush" ]; then
    _acct_in_real_dir "${_L_BIN}" \
      ln -sfn "${_ROOT}/tools/drush/drush" ./drush
  fi
}

#
# Run standard post-install.
_satellite_run_post_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_run_post_install"
    _debug_proc
  fi
  _LOCAL_STATUS="${_STATUS}"
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    if [ ! -e "${_ROOT}/config/${_USER}.nginx.conf" ]; then
      rm -f /var/aegir/config/server_master/nginx/platform.d/${_USER}.conf
      ### config/ is the instance user's: the include file is put there as a
      ### fresh file inside the real directory, never through a link put at
      ### the name.
      echo "include ${_ROOT}/config/server_master/nginx/vhost.d/*;" \
        | _acct_in_real_dir "${_ROOT}/config" _satellite_put_stdin_here \
          "${_USER}.nginx.conf" 0644 ""
      ln -sfn ${_ROOT}/config/${_USER}.nginx.conf \
        /var/aegir/config/server_master/nginx/platform.d/${_USER}.conf
    fi
    ### the site tree is the instance user's: the group is changed from
    ### inside the real directories, through a handle, never on a link or a
    ### file hard-linked there
    _T_WG=$(_web_group "${_USER}")
    if [ -n "${_T_WG}" ]; then
      _acct_in_real_dir "${_HM_ROOT}/sites/${_DOMAIN}/files" \
        _satellite_reown_here ":${_T_WG}"
      _acct_in_real_dir "${_HM_ROOT}/sites/${_DOMAIN}" \
        _satellite_reown_names_here ":${_T_WG}" ./settings.php
    fi
    rm -rf ${_HM_ROOT}/profiles/default
    rm -rf ${_HM_ROOT}/themes/bluemarine
    rm -rf ${_HM_ROOT}/themes/chameleon
    rm -rf ${_HM_ROOT}/themes/pushbutton
    rm -rf ${_HM_ROOT}/scripts
    rm -f ${_HM_ROOT}/themes/README.txt
    rm -f ${_HM_ROOT}/*.txt
    _mrun "service nginx reload"
    cd ${_HM_ROOT}
    # a fresh file inside the real directory, never written through a link
    # put at the name (cp -a sets owner and mode on the file it created)
    _acct_in_real_dir "${_HM_ROOT}" cp -afT --remove-destination \
      /opt/tmp/boa/aegir/conf/tpl/robots.txt ./robots.txt
    cd ${_ROOT}
  fi
}

#
# A mode set on names in a directory an account owns, never through a link
# (the ltd worker's setter): each name is opened without following one and
# without blocking on a FIFO, checked to be the expected type and changed
# through the open handle. Run it inside a directory pinned with cd -P and
# checked with pwd -P, or from find -execdir there. Args: d|f|p|q|w, the mode
# (octal), the account user, the web group, the names. p, q and w are the
# HTTP basic auth password directory and files as the Aegir task expects
# them: in the web server's group, the directory setgid and closed to other
# accounts, changed only when the account owns them (q: root, only for one
# just made) and a file has a single link. A regular file (f) too is changed
# only while it has a single link.
_SAT_FCHMOD_PL='use Fcntl;
my ($t, $m) = (shift @ARGV, oct(shift @ARGV));
my $uid = (getpwnam(shift @ARGV))[2];
my $gid = (getgrnam(shift @ARGV))[2];
defined $uid && defined $gid or exit 1;
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if (($t eq "d" && -d _) || ($t eq "f" && -f _ && $s[3] == 1)) {
    chmod($m, $h);
  }
  elsif (-d _ && (($t eq "p" && $s[4] == $uid) || ($t eq "q" && $s[4] == 0))) {
    chown($uid, $gid, $h);
    chmod($m, $h);
  }
  elsif ($t eq "w" && -f _ && $s[4] == $uid && $s[3] == 1) {
    chown(-1, $gid, $h);
    chmod($m, $h);
  }
  close($h);
}'
#
# config/server_master is the account's: 0700 directories and 0600 files, set
# from inside the real directory through the setter above. nginx (www-data)
# opens each site's HTTP basic auth password file on every request, and the
# ltd worker, which keeps the modes it needs, is held off until this run
# ends, so the path to those files and the files themselves get the worker's
# final modes in one step: server_master and nginx 0755, passwords.d 02710
# (made when missing), each file 0640 (p and w above). $1 = all: the whole
# tree; anything else: the password files and the path to them only.
_satellite_server_master_modes() {
  local _sm
  _sm="$(cd -P -- /data/disk 2> /dev/null && pwd -P)/${_USER}/config/server_master"
  ( PATH=/usr/local/bin:/usr/bin:/bin
    cd -P -- "${_ROOT}/config/server_master" 2> /dev/null \
      && [ "$(pwd -P)" = "${_sm}" ] || exit 1
    if [ "${1}" = "all" ]; then
      find . -type d ! -path . ! -path ./nginx ! -path ./nginx/passwords.d \
        -execdir perl -e "${_SAT_FCHMOD_PL}" d 0700 "${_USER}" "${_WEBG}" {} +
      find . -type f ! \( -path './nginx/passwords.d/*' ! -path './nginx/passwords.d/*/*' \) \
        -execdir perl -e "${_SAT_FCHMOD_PL}" f 0600 "${_USER}" "${_WEBG}" {} +
    fi
    perl -e "${_SAT_FCHMOD_PL}" d 0755 "${_USER}" "${_WEBG}" . ./nginx )
  ( PATH=/usr/local/bin:/usr/bin:/bin
    cd -P -- "${_ROOT}/config/server_master/nginx" 2> /dev/null \
      && [ "$(pwd -P)" = "${_sm}/nginx" ] || exit 1
    _t=p
    if [ ! -e ./passwords.d ] && [ ! -L ./passwords.d ]; then
      mkdir -m 02710 ./passwords.d && _t=q
    fi
    perl -e "${_SAT_FCHMOD_PL}" "${_t}" 02710 "${_USER}" "${_WEBG}" ./passwords.d )
  ( PATH=/usr/local/bin:/usr/bin:/bin
    cd -P -- "${_ROOT}/config/server_master/nginx/passwords.d" 2> /dev/null \
      && [ "$(pwd -P)" = "${_sm}/nginx/passwords.d" ] || exit 1
    shopt -s dotglob nullglob
    set -- ./*
    [ "$#" -gt 0 ] || exit 0
    perl -e "${_SAT_FCHMOD_PL}" w 0640 "${_USER}" "${_WEBG}" "$@" )
}

#
# Set permissions for all.
_satellite_set_permissions_for_all() {
  local _hmP
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_set_permissions_for_all"
    _debug_proc
  fi
  _acct_in_real_dir "${_HM_ROOT}" chmod 0755 . &> /dev/null
  _satellite_server_master_modes all &> /dev/null
  _acct_in_real_dir "${_ROOT}/config" chmod 0711 . &> /dev/null
  _acct_in_real_dir "${_ROOT}/config/includes" chmod 0711 . &> /dev/null
  ### backups may be a link into the account's store (relocated backups):
  ### the mode is set in the store it leads to when that is the account's
  _satellite_in_store_dir "${_ROOT}/backups" chmod 0750 . &> /dev/null
  _acct_in_real_dir "${_ROOT}/clients" chmod 0750 . &> /dev/null
  ### Each hostmaster platform's profiles/ and sites/all/ walked from inside
  ### its real directory, every mode set without following a link.
  for _hmP in "${_ROOT}"/aegir/distro/*; do
    _acct_in_real_dir "${_hmP}/profiles" \
      _satellite_tree_modes_here 0755 0644 &> /dev/null
    _acct_in_real_dir "${_hmP}/sites/all" \
      _satellite_tree_modes_here 0755 0644 &> /dev/null
  done
  _acct_in_real_dir "${_ROOT}/.drush" \
    _satellite_reown_here "${_USER}:${_ACCG:-users}" &> /dev/null
  _acct_in_real_dir "${_ROOT}/.drush" _satellite_drush_modes_here &> /dev/null
}

#
# The instance user's .drush, run inside the real directory: directories
# 0710 (usr and below 0750), files 0640, the top-level PHP files 0440 and the
# aliases 0400, hm.alias made from the hostmaster alias where missing. Every
# mode is set through a handle opened without following a link, in the
# directory find walked (-execdir), so a name swapped for a link is refused,
# and a file with more than one link (planted or renamed over a name) is
# left alone (_SAT_NOFOLLOW_CHMOD_PL).
_satellite_drush_modes_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  shopt -s nullglob
  find . -mindepth 1 -type d \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d 0710 {} +
  find ./usr -type d \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d 0750 {} +
  find . -type f \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" f 0640 {} +
  _satellite_chmod_nofollow f 0440 ./*.php
  if [ ! -e ./hm.alias.drushrc.php ]; then
    _satellite_copy_here hostmaster.alias.drushrc.php hm.alias.drushrc.php \
      "s/\['hostmaster'\]/['hm']/g"
  fi
  _satellite_chmod_nofollow f 0400 ./server_*.php ./platform_*.php \
    ./hostmaster*.php ./hm.alias.drushrc.php
  _satellite_chmod_nofollow d 0710 .
)

#
# Run child C.
_satellite_run_child_c() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_run_child_c"
    _debug_proc
  fi
  _LOCAL_STATUS="${_STATUS}"
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    _DIST_INSTALL=YES
    rm -f /opt/tmp/testecho*
    _satellite_create_shared_dirs
    _satellite_manage_o_contrib
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Switching user and running Platforms build"
    fi
    cd ${_ROOT}
    _AegirSetupC="${_bldPth}/aegir/scripts/AegirSetupC.sh.txt"
    su -s /bin/bash - ${_USER} -c "/bin/bash ${_AegirSetupC} ${_USER}"
    wait
    if [ -e "/opt/tmp/state/${_USER}/status-AegirSetupC-FAIL" ] \
      || [ ! -e "/opt/tmp/state/${_USER}/status-AegirSetupC-OK" ]; then
      _msg "${_STATUS} A: FATAL ERROR: AegirSetupC installer failed"
      _msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
      touch "/opt/tmp/state/.root/${_USER}/status-AegirSetupA-FAIL"
      exit 1
    fi
  else
    if [ "${_HM_ONLY}" = "YES" ]; then
      _DIST_INSTALL=NO
    else
      echo " "
      if _prompt_yes_no "Do you want to install some ready to use platforms?"; then
        true
        _DIST_INSTALL=YES
        rm -f /opt/tmp/testecho*
        _satellite_create_shared_dirs
        _satellite_manage_o_contrib
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "${_STATUS} A: Switching user and running Platforms build"
        fi
        cd ${_ROOT}
        _AegirSetupC="${_bldPth}/aegir/scripts/AegirSetupC.sh.txt"
        su -s /bin/bash - ${_USER} -c "/bin/bash ${_AegirSetupC} ${_USER}"
        wait
        if [ -e "/opt/tmp/state/${_USER}/status-AegirSetupC-FAIL" ] \
          || [ ! -e "/opt/tmp/state/${_USER}/status-AegirSetupC-OK" ]; then
          _msg "${_STATUS} A: FATAL ERROR: AegirSetupC installer failed"
          _msg "${_STATUS} A: FATAL ERROR: Aborting AegirSetupA installer NOW!"
          touch "/opt/tmp/state/.root/${_USER}/status-AegirSetupA-FAIL"
          exit 1
        fi
      else
        _msg "${_STATUS} A: No new Platforms added this time"
      fi
    fi
  fi
  if [ ! -e "${_CORE}/dot-files-ctrl-${_xSrl}-${_X_VERSION}" ] \
    && [ -e "${_CORE}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Cleaning up various dot files, please wait..."
    fi
    cd ${_CORE}
    find . -name .svn -exec rm -rf {} \; &> /dev/null
    find . -name .bzr -exec rm -rf {} \; &> /dev/null
    find . -name .git -exec rm -rf {} \; &> /dev/null
    find . -name .DS_Store -type f | xargs rm -f &> /dev/null
    find . -name "._*" -type f | xargs rm -f &> /dev/null
    # the core is the account's during the build: the stamp is put as a
    # fresh empty file (as touch made it) inside the real directory, never
    # created through a link put at the name
    _acct_in_real_dir "${_CORE}" _satellite_put_stdin_here \
      "dot-files-ctrl-${_xSrl}-${_X_VERSION}" 0644 "" < /dev/null
  fi
}

_satellite_child_scripts_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_scripts_cleanup"
    _debug_proc
  fi
  rm -f ${_ROOT}/AegirSetupC.sh.txt*
  rm -f ${_ROOT}/AegirSetupB.sh.txt*
  rm -f ${_ROOT}/*.sh.txt
  rm -f /var/spool/cron/crontabs/${_USER}
}

#
# Add allow-snail group if not exists.
_add_allow_snail_if_not_exists() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _add_allow_snail_if_not_exists"
  fi
  _SNAIL_EXISTS=$(getent group allow-snail 2>&1)
  if [[ ! "${_SNAIL_EXISTS}" =~ "allow-snail" ]]; then
    addgroup --system allow-snail &> /dev/null
  fi
}

#
# Unlock sendmail for allow-snail group
_unlock_sendmail_for_snail() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _unlock_sendmail_for_snail"
  fi
  _add_allow_snail_if_not_exists
  chown root /usr/sbin/sendmail &> /dev/null
  chgrp allow-snail /usr/sbin/sendmail &> /dev/null
  chmod 755 /usr/sbin/sendmail &> /dev/null
}

_satellite_if_add_snail_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_add_snail_access"
  fi
  _unlock_sendmail_for_snail
  if getent group allow-snail >/dev/null 2>&1 && \
    ! id -nG "${_USER}" 2>/dev/null | tr ' ' '\n' | grep -qxF "allow-snail"; then
    usermod -aG allow-snail "${_USER}"
  fi
}

#
# Per-instance group: hand the account's identities and files to a private
# group named after the account (tool: instgrp, delivered by BOA.sh.txt). On
# an upgrade this runs before _satellite_make so the rest of the run already
# writes with the new group; on a fresh install the identities exist only
# after AegirSetupA, so it runs after _satellite_make. instgrp refuses while
# any fetched root-run writer on the box still carries the box-wide form and
# skips (never half-converts) a busy account. Per-account opt-out:
# _INSTANCE_GROUP=NO in the octopus cnf.
_satellite_if_instance_group() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_instance_group $1"
    _debug_proc
  fi
  case "$1" in
    pre)  [ "${_STATUS}" = "UPGRADE" ] || return 0 ;;
    post) [ "${_STATUS}" = "INIT" ] || return 0 ;;
    *) return 0 ;;
  esac
  if [ "${_INSTANCE_GROUP}" = "NO" ] \
    || grep -q "^_INSTANCE_GROUP=NO" ${_octCnf} 2> /dev/null; then
    _msg "NOTE: per-instance group disabled for ${_USER} (_INSTANCE_GROUP=NO)"
    return 0
  fi
  if [ ! -e "/opt/local/bin/instgrp" ]; then
    _msg "NOTE: instgrp not installed yet, ${_USER} keeps the box-wide group this pass"
    return 0
  fi
  # INIT already found the group name held by another identity and said so
  # when it created the account (in AegirSetupA, a child process, so the
  # verdict is read again here from the group database); a convert now can
  # only fail on the same name and would end the same run with an alarm on
  # top of that note. The verdict of an INIT on a held name is the note; the
  # upgrade arm alarms on every later pass until the name is freed.
  if [ "$1" = "post" ] && _instance_group_held "${_USER}"; then
    _msg "NOTE: ${_USER} stays on the box-wide group while the group name is held; free it, then the next upgrade converts (or run instgrp convert ${_USER})"
    return 0
  fi
  bash /opt/local/bin/instgrp convert ${_USER} --from-octopus
  _iGrc=$?
  # ALRT: is the token the octopus report classifier greps for; anything
  # else leaves the run reported as a successful upgrade. A skipped account
  # (busy, frozen) is unconverted after a fleet pass and nothing retries it
  # before the next one, so it is reported too. Drift (paths written during
  # the walk) is converted, finished by the next pass: a note.
  case "${_iGrc}" in
    0) ;;
    2) _msg "NOTE: instgrp convert ${_USER} left paths to re-group (written during the walk); the next pass finishes them, see /var/log/boa/instgrp.log" ;;
    5) _msg "NOTE: instgrp convert ${_USER} deferred: a fetched root-run writer on this box still carries the box-wide form, or the release that carries this arm has not stamped the box yet (instgrp check); the next pass converts once the tools refresh or the BOA upgrade lands" ;;
    *)
      # name the exit class; the old text listed the code legend in a
      # shape that read as a tally of accounts
      case "${_iGrc}" in
        1) _iGwhy="failed" ;;
        3) _iGwhy="inconsistent: marker or files say converted while an identity is on the box-wide group" ;;
        4) _iGwhy="skipped: busy, frozen, or an identity in use such as a logged-in session" ;;
        *) _iGwhy="unexpected exit code" ;;
      esac
      _msg "ALRT: instgrp convert ${_USER} returned ${_iGrc} (${_iGwhy}), see /var/log/boa/instgrp.log" ;;
  esac
  # The rest of this run writes with whatever group the account carries now.
  _ACCG=$(_acct_group "${_USER}")
}

_satellite_if_add_ftps_lshell_access() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_add_ftps_lshell_access"
    _debug_proc
  fi
  _USERFTP="${_USER}.ftp"
  _USERFTP_ROOT="/home/${_USERFTP}"
  if [ -e "/usr/bin/mysecureshell" ] && [ -e "/etc/ssh/sftp_config" ]; then
    _PATH_LSHELL="/usr/bin/mysecureshell"
  else
    _PATH_LSHELL="/usr/bin/lshell"
  fi
  # Existence test, not a group-list shape: the old `id -nG =~ users` form
  # would re-enter this branch -- and mint a NEW password for an existing
  # account -- on any box where the identity's group list stops carrying
  # the word 'users' first, which is exactly what a per-instance primary
  # group does. Group grants are re-asserted below, outside this branch.
  if ! getent passwd "${_USERFTP}" > /dev/null 2>&1 \
    || [ ! -d "${_USERFTP_ROOT}" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Adding ftps/lshell user"
    fi
    # add user
    find /etc/[a-z]*\.lock -maxdepth 1 -type f -exec rm -f {} \; &> /dev/null
    # -N leaves the primary group to /etc/default/useradd (users); name it
    # explicitly so an account carrying its per-instance group gets that one.
    useradd -d /home/${_USERFTP} -s ${_PATH_LSHELL} -m -N -r \
      -g ${_ACCG:-users} ${_USERFTP} &> /dev/null
    # The file which contains the password is private from the start: made
    # 0600 below as a fresh file inside the real log/ (the instance user's),
    # never through a link or a FIFO put at the name
    cd ${_ROOT}/log
    # generate a nice secure password and put it in a file
    _ESC_LUPASS=""
    _LEN_LUPASS=0
    if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
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
    if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt 32 ]; then
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
    echo "${_ESC_LUPASS}" \
      | _acct_in_real_dir "${_ROOT}/log" _satellite_put_stdin_here pass.txt 0600 ""
    # get the password hash via stdin so the plaintext never reaches
    # /proc/<pid>/cmdline; set the hash via chpasswd -e via stdin so the
    # hash never reaches /proc either.
    _salt=$(openssl rand -base64 16 | tr -d '+=' | head -c 16)
    ph=$(printf '%s' "${_ESC_LUPASS}" | mkpasswd -m sha-512 -s -S "${_salt}")
    printf '%s:%s\n' "${_USERFTP}" "${ph}" | chpasswd -e &> /dev/null
    passwd -w 7 -x 90 ${_USERFTP} &> /dev/null
  fi
  # 'users' explicitly supplementary: the binary execute ACL (root:users
  # 0750, lshell included) must survive the move of the primary group to the
  # per-instance group. Lists the identity in the group database whatever its
  # primary group is; a primary 'users' alone is not a listed membership.
  usermod -aG ${_USRG} ${_USERFTP} &> /dev/null
  # www-data (files/ write, settings.php read) until the account's identities
  # have left it for the account's own web group, listed once it holds one.
  _T_WGS=$(_web_group_state "${_USERFTP}")
  [ "${_T_WGS%% *}" = "phaseb" ] || adduser ${_USERFTP} ${_WEBG} &> /dev/null
  _satellite_wg_grant "${_USERFTP}"
  usermod -aG lshellg ${_USERFTP}
  chsh -s ${_PATH_LSHELL} ${_USERFTP} &> /dev/null
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
  _MNT_STATIC_FILES="${_mntPoint}/files/${_USER}/static/files"
  # This runs on every pass, not only when the identity was just made, so the
  # section is replaced, never stacked: lshell's parser is strict and refuses
  # the whole file for a user with two [name] sections until the 3-minute
  # worker rewrites it. Written back in place so the file keeps its inode.
  if grep -q "^\[${_USERFTP}\]" /etc/lshell.conf 2> /dev/null; then
    awk -v s="[${_USERFTP}]" '/^\[/ { skip = ($0 == s) } !skip { print }' \
      /etc/lshell.conf > /etc/lshell.conf.tmp \
      && cat /etc/lshell.conf.tmp > /etc/lshell.conf
    rm -f /etc/lshell.conf.tmp
  fi
  echo >> /etc/lshell.conf
  echo "[${_USERFTP}]" >> /etc/lshell.conf
  # The attached-files store is listed only when one is mounted; with none,
  # _mntPoint is empty and the entry would name a path that does not exist.
  _lshPaths="'/opt/user/gems/${_USERFTP}', '/opt/user/npm/${_USERFTP}'"
  [ -n "${_mntPoint}" ] && _lshPaths="${_lshPaths}, '${_MNT_STATIC_FILES}'"
  echo "path : [${_lshPaths}, '${_ROOT}/distro', '${_ROOT}/static', '${_ROOT}/backups', '${_ROOT}/clients']" \
    | fmt -su -w 2500 >> /etc/lshell.conf
}

_satellite_if_add_update_user_symlinks() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_add_update_user_symlinks"
    _debug_proc
  fi
  ###---### Add symlink to the sites backups.
  #
  _USERFTP="${_USER}.ftp"
  _USER_HD="/home/${_USERFTP}"
  _USER_DS="${_USER_HD}/.drush"
  _disable_chattr ${_USERFTP}
  if [ ! -L "${_USER_HD}/backups" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Adding symlink to the sites backups"
    fi
    ln -sfn ${_ROOT}/backups ${_USER_HD}/backups
  fi

  ###---### Remove legacy symlinks.
  #
  ### ~/.drush is the main login's (never immutable while this runs): the
  ### names are removed inside the real directory.
  _acct_in_real_dir "${_USER_DS}" rm -f -- ./drush_make ./registry_rebuild \
    ./clean_missing_modules ./drush_ecl ./make_local \
    ./safe_cache_form_clear ./mydropwizard ./utf8mb4_convert &> /dev/null

  ###---### Add symlinks to the system drush extensions.
  #
  ### ~/.drush and ~/.drush/usr are made real directories (a link put at
  ### either name is removed first) and handed to the main login, and each
  ### link is made, inside the real directory.
  for _dsX in registry_rebuild clean_missing_modules drupalgeddon \
    drush_ecl safe_cache_form_clear utf8mb4_convert; do
    if [ ! -L "${_USER_DS}/usr/${_dsX}" ] \
      && [ -e "${_ROOT}/.drush/usr/${_dsX}" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "${_STATUS} A: Adding symlink to the system ${_dsX}"
      fi
      [ -L "${_USER_DS}" ] && rm -f "${_USER_DS}"
      mkdir -p "${_USER_DS}"
      _acct_in_real_dir "${_USER_DS}" \
        _satellite_user_ds_link_here "${_dsX}" &> /dev/null
    fi
  done

  ###---### Add symlink to the clients directory.
  #
  if [ ! -L "${_USER_HD}/clients" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Adding symlink to the clients directory"
    fi
    ln -sfn ${_ROOT}/clients ${_USER_HD}/clients
  fi
  _acct_in_real_dir "${_ROOT}/clients" _satellite_clients_clean_here &> /dev/null
}

#
# The instance user's clients/ (the current, pinned directory) cleaned: the
# legacy client dirs removed, each client's backups/ removed inside that
# client's real directory, dangling links dropped; nothing is reached
# through a link put at clients or at a client name.
_satellite_clients_clean_here() {
  local _c
  rm -rf -- ./admin ./omega8ccgmailcom ./nocomega8cc
  for _c in ./*; do
    [ -d "${_c}" ] && [ ! -L "${_c}" ] || continue
    _acct_in_real_dir "$(pwd -P)/${_c#./}" rm -rf -- ./backups
  done
  symlinks -dr . &> /dev/null
}

_satellite_if_add_update_user_dot_dirs() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_add_update_user_dot_dirs"
    _debug_proc
  fi
  ### The main login's home is never immutable, so every name in it is the
  ### login's: where a directory is missing, a link at the name is removed
  ### first, and the new directory is set up inside the real directory.

  ###---### Create .tmp dir if not exists.
  #
  _USER_TMP="${_USER_HD}/.tmp"
  if [ ! -d "${_USER_TMP}" ]; then
    [ -L "${_USER_TMP}" ] && rm -f "${_USER_TMP}"
    mkdir -p "${_USER_TMP}"
    _acct_in_real_dir "${_USER_TMP}" _satellite_ftp_tmp_here &> /dev/null
  fi

  ###---### Create .ssh dir if not exists.
  #
  _USER_SSH="${_USER_HD}/.ssh"
  if [ ! -d "${_USER_SSH}" ]; then
    [ -L "${_USER_SSH}" ] && rm -f "${_USER_SSH}"
    mkdir -p "${_USER_SSH}"
    _acct_in_real_dir "${_USER_SSH}" \
      _satellite_reown_here "${_USERFTP}:${_ACCG:-users}" &> /dev/null
    _acct_in_real_dir "${_USER_SSH}" chmod 700 . &> /dev/null
  fi
  # the main login's own keys: set through a handle inside the real .ssh,
  # never through a link put at a key name or at .ssh; authorized_keys too,
  # which sshd's StrictModes refuses once it is group-writable
  _acct_in_real_dir "${_USER_SSH}" _satellite_chmod_nofollow f 0600 \
    ./id_rsa ./id_dsa ./authorized_keys ./authorized_keys2 &> /dev/null

  ###---### Create .bazaar dir and conf file if not exist.
  #
  _USER_BZR="${_USER_HD}/.bazaar"
  if [ -x "/usr/local/bin/bzr" ]; then
    if [ ! -e "${_USER_BZR}/bazaar.conf" ]; then
      [ -L "${_USER_BZR}" ] && rm -f "${_USER_BZR}"
      mkdir -p "${_USER_BZR}"
      _acct_in_real_dir "${_USER_BZR}" _satellite_bzr_seed_here \
        "${_USERFTP}:${_ACCG:-users}" &> /dev/null
    fi
  else
    if [ -d "${_USER_BZR}" ]; then
      rm -rf ${_USER_BZR}
    fi
  fi

  ###---### Remove not used dot files.
  #
  rm -f ${_USER_HD}/{.profile,.bash_logout,.bash_profile,.bashrc}
}

###---### Reading or creating pass.txt.
#
_satellite_if_read_create_pass_txt() {
  local _pSt
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_read_create_pass_txt"
    _debug_proc
  fi
  if [ "${_HM_ONLY}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    ### The account root and log/ are the instance user's: pass.txt is read
    ### bounded, never through a link or from a FIFO, and written as a fresh
    ### 0600 file (moved: with the old file's owner and mode) inside the
    ### real log/, never through a link put at either name.
    if [ -e "${_ROOT}/pass.txt" ]; then
      _PASWD=$(_satellite_pass_read "${_ROOT}" pass.txt)
      _pSt="$(_acct_in_real_dir "${_ROOT}" _satellite_stat_here pass.txt)" \
        && _acct_read_in "${_ROOT}" pass.txt \
        | _acct_in_real_dir "${_ROOT}/log" _satellite_put_stdin_here \
          pass.txt "${_pSt#* }" "${_pSt%% *}" \
        && rm -f "${_ROOT}/pass.txt"
    elif [ -e "${_ROOT}/log/pass.txt" ]; then
      _PASWD=$(_satellite_pass_read "${_ROOT}/log" pass.txt)
      rm -f ${_ROOT}/pass.txt
    else
      cd ${_ROOT}/log
      _ESC_LUPASS=""
      _LEN_LUPASS=0
      if [ "${_STRONG_PASSWORDS}" = "YES" ]; then
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
      if [ "${_STRONG_PASSWORDS}" = "YES" ] || [ "${_PWD_CHARS}" -gt 32 ]; then
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
      echo "${_ESC_LUPASS}" \
        | _acct_in_real_dir "${_ROOT}/log" _satellite_put_stdin_here pass.txt 0600 ""
      # See sibling site above — stdin-based mkpasswd + chpasswd -e keep
      # the plaintext password and the resulting hash out of /proc/PID/cmdline.
      _salt=$(openssl rand -base64 16 | tr -d '+=' | head -c 16)
      ph=$(printf '%s' "${_ESC_LUPASS}" | mkpasswd -m sha-512 -s -S "${_salt}")
      printf '%s:%s\n' "${_USERFTP}" "${ph}" | chpasswd -e &> /dev/null
      _PASWD=$(_satellite_pass_read "${_ROOT}/log" pass.txt)
    fi
  fi
}

###---### Add/Update platforms ftp symlinks.
#
_satellite_if_add_update_user_platforms_symlinks() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_add_update_user_platforms_symlinks"
    _debug_proc
  fi

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Add/Update platforms ftp symlinks"
  fi

  _HM_U="${_USER}"
  _LOW_NR="2"
  _usEr="${_ROOT}"
  _PL_HOME="/home/${_HM_U}.ftp/platforms"

  ### platforms/ in the main login's home and distro/ of the instance user,
  ### and every name in either, can be swapped for a link: each is acted on
  ### inside its real directory, an entry is moved by its own name there,
  ### and a revision is moved into undo/ by the instance user itself.
  _acct_in_real_dir "${_PL_HOME}" _satellite_pl_ghosts_here
  _acct_in_real_dir "${_usEr}/distro" _satellite_distro_ghosts_here
  _acct_in_real_dir "${_usEr}/distro" _satellite_distro_links_here
}

#
# Run inside the real platforms/ of the main login: an entry holding fewer
# than two names is moved to /var/backups/ghost by its own name (a link is
# moved as the link).
_satellite_pl_ghosts_here() {
  local _p _n _g
  for _p in ./*; do
    [ -e "${_p}" ] || continue
    _n=$(ls -- "${_p}" 2> /dev/null | wc -l | tr -d "\n")
    [ -n "${_n}" ] && [ "${_n}" -lt "${_LOW_NR}" ] || continue
    _satellite_chattr_all_here -i
    _g="/var/backups/ghost/${_HM_U}/$(date +%y%m%d-%H%M%S)"
    [ -d "${_g}" ] || mkdir -p "${_g}"
    [ "${_DEBUG_MODE}" = "YES" ] && echo "Moving ${_PL_HOME}/${_p#./} to ${_g}"
    mv -f -- "${_p}" "${_g}/"
  done
  return 0
}

#
# Run inside the real distro/ of the instance user: each real revision
# directory gets its keys/ where missing, and one holding fewer than two
# names and untouched for an hour is moved to undo/dist/<stamp>: root makes
# that directory inside the real undo/dist and hands it over, the instance
# user moves its own revision into it. A revision that is a link is left
# alone.
_satellite_distro_ghosts_here() {
  local i _n _s
  for i in ./*; do
    [ -d "${i}" ] && [ ! -L "${i}" ] || continue
    # The account owns distro/ and its entries: never through a planted
    # link (a revision or keys itself), and root's own directory stays
    # root's (the owner and mode it has always had).
    if [ ! -L "${i}" ] && [ ! -e "${i}/keys" ] && [ ! -L "${i}/keys" ]; then
      _acct_in_real_dir "${i}" mkdir -m 0755 ./keys &> /dev/null
    fi
    _n=$(ls -- "${i}" 2> /dev/null | wc -l | tr -d "\n")
    # Age gate, mirroring the nightly copy in night/10-account.sh: an
    # under-populated revision is not a ghost by itself, because an
    # installer creates the new distro/NNN empty and the keys/ mkdir above
    # scores it 1 on its own. This copy runs inside AegirSetupA, i.e. inside
    # the install, so it deliberately carries NO in-flight test -- that
    # would disable it permanently here; the mtime brake is what makes it
    # safe, and a real ghost is stale for hours
    if [ -n "${_n}" ] && [ "${_n}" -lt 2 ] \
      && [ -z "$(find "${i}" -maxdepth 0 -mmin -60 2> /dev/null)" ]; then
      [ "${_DEBUG_MODE}" = "YES" ] && echo "_RevisionTest is ${_n}"
      _s="$(date +%y%m%d-%H%M%S)"
      _acct_in_real_dir "${_usEr}" _satellite_sub_here undo \
        _satellite_sub_here dist _satellite_sub_here "${_s}" \
        chown -h "${_USER}:${_ACCG:-users}" . &> /dev/null
      _satellite_as_user "mv -f -- \
        ${_usEr}/distro/$(printf '%q' "${i#./}") \
        ${_usEr}/undo/dist/${_s}/" &> /dev/null
      [ "${_DEBUG_MODE}" = "YES" ] && echo "GHOST revision ${_usEr}/distro/${i#./} detected and moved to ${_usEr}/undo/dist/${_s}/"
    fi
  done
  return 0
}

#
# Run inside the real distro/ of the instance user: for each real revision
# directory, the main login's platforms/<revision> (and platforms/ itself,
# a link put at that name removed first) made where missing, and in it the
# link to the revision's keys/ when that is a real directory and one link
# per platform to that platform's sites/, each made inside the real
# directory.
_satellite_distro_links_here() {
  local i _n _p _c
  for i in ./*; do
    [ -d "${i}" ] && [ ! -L "${i}" ] || continue
    _n="${i#./}"
    if [ ! -d "${_PL_HOME}" ]; then
      [ -L "${_PL_HOME}" ] && rm -f "${_PL_HOME}"
      mkdir -p "${_PL_HOME}"
    fi
    _acct_in_real_dir "${_PL_HOME}" _satellite_chattr_all_here -i
    _acct_in_real_dir "${_PL_HOME}" mkdir -p -- "./${_n}"
    if [ -d "${i}/keys" ] && [ ! -L "${i}/keys" ]; then
      _acct_in_real_dir "${_PL_HOME}/${_n}" _satellite_link_new_here \
        "${_usEr}/distro/${_n}/keys" keys
    fi
    _acct_in_real_dir "${_PL_HOME}" _satellite_pl_data_here
    for _p in "${i}"/*; do
      [ -d "${_p}" ] && [ ! -L "${_p}" ] || continue
      [ "${_p##*/}" = "keys" ] && continue
      _c=$(_detect_real_docroot "${_usEr}/distro/${_n}/${_p##*/}")
      [ -n "${_c}" ] && [ -d "${_c}/sites" ] || continue
      _acct_in_real_dir "${_PL_HOME}/${_n}" \
        ln -sfn "${_c}/sites" "./${_p##*/}"
      [ "${_DEBUG_MODE}" = "YES" ] && echo "Fixed ${_p##*/} in ${_n} symlink to ${_c}/sites for ${_HM_U}.ftp"
    done
  done
  return 0
}

#
# ./data in the current (pinned) platforms/ moved to /var/backups/ghost.
_satellite_pl_data_here() {
  local _g
  [ -e ./data ] || return 0
  _g="/var/backups/ghost/${_HM_U}/$(date +%y%m%d-%H%M%S)"
  [ -d "${_g}" ] || mkdir -p "${_g}"
  mv -f -- ./data "${_g}/platforms_data"
}

_satellite_if_add_update_backend_user_dirs_files_clean() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_add_update_backend_user_dirs_files_clean"
    _debug_proc
  fi
  ###---### Create ~/static dir if not exists.
  #
  if [ ! -d "${_ROOT}/static" ]; then
    mkdir -p ${_ROOT}/static
    ln -sfn ${_ROOT}/static /home/${_USERFTP}/static
  fi
  ### static/ is the account's and group-writable: its owner and mode are set
  ### and EMPTY.txt is put inside the real directory, never through a link
  ### put at static or at EMPTY.txt.
  _acct_in_real_dir "${_ROOT}/static" _satellite_own_dir_here \
    "${_USER}:${_ACCG:-users}" 02775 &> /dev/null
  _acct_put_in "${_ROOT}/static" EMPTY.txt empty

  ###---### Create ~/.tmp dir if not exists.
  #
  if [ ! -d "${_ROOT}/.tmp" ]; then
    rm -rf ${_ROOT}/.tmp
    mkdir -p ${_ROOT}/.tmp
    _acct_in_real_dir "${_ROOT}/.tmp" _satellite_own_dir_here \
      "${_USER}:${_ACCG:-users}" 02775
  fi

  ###---### Create .ssh dir and keys if not exist, plus some known_hosts for system user.
  #
  if [ ! -e "${_ROOT}/.ssh/id_ed25519.pub" ]; then
    su -s /bin/bash - ${_USER} -c "ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H ${_USER}.beanstalkapp.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H ${_USER}.unfuddle.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H beanstalkapp.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H bitbucket.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H codebasehq.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H drupal.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H git.drupal.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H github.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H gitlab.org >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H gitlab.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    su -s /bin/bash - ${_USER} -c "ssh-keyscan -t rsa -H unfuddle.com >> ~/.ssh/known_hosts" &> /dev/null
    wait
    ### The public key is copied as the instance user's 0644 file: read
    ### bounded from the real .ssh, created exclusively in the real static/,
    ### never through a link put at either name.
    local _pubK
    _pubK="$(_acct_read_in "${_ROOT}/.ssh" id_ed25519.pub)"
    if [ -n "${_pubK}" ]; then
      _acct_in_real_dir "${_ROOT}/static" _acct_pin_here \
        "${_USER}.id_ed25519.pub" "${_pubK}" "${_USER}:${_ACCG:-users}"
    fi
  fi

  ###---### Create .bazaar dir and conf file if not exist for system user.
  #
  _SYSTEM_USER_BZR="${_ROOT}/.bazaar"
  if [ -x "/usr/local/bin/bzr" ]; then
    if [ ! -e "${_SYSTEM_USER_BZR}/bazaar.conf" ]; then
      ### a link at .bazaar is removed first, then the directory is seeded
      ### and handed over inside the real directory
      [ -L "${_SYSTEM_USER_BZR}" ] && rm -f "${_SYSTEM_USER_BZR}"
      mkdir -p "${_SYSTEM_USER_BZR}"
      _acct_in_real_dir "${_SYSTEM_USER_BZR}" _satellite_bzr_seed_here \
        "${_USER}:${_ACCG:-users}" &> /dev/null
    fi
  else
    if [ -d "${_SYSTEM_USER_BZR}" ]; then
      rm -rf ${_SYSTEM_USER_BZR}
    fi
  fi

  ###---### Create other dirs and symlinks if not exist.
  #
  # For two years _QR and _QH were unset here, so this block made /keys (with
  # a /keys/keys self-link) at the root of the filesystem, in group www-data:
  # take it away when it holds nothing but that link.
  if [ -d "/keys" ] && [ ! -L "/keys" ] && [ "$(ls -A /keys 2> /dev/null)" = "keys" ] \
    && [ -L "/keys/keys" ] && [ "$(readlink /keys/keys)" = "/keys" ]; then
    rm -f /keys/keys && rmdir /keys
  fi
  # One that holds more is left in place, but handed back to root and closed
  # (0700), which cuts every login off from all below it: whether its owner
  # is still a *.ftp login, one since removed (no name), or it is still in
  # the web group it was made in. Nothing in BOA reads /keys.
  if [ -d "/keys" ] && [ ! -L "/keys" ]; then
    case "$(stat -c '%U:%G' /keys 2> /dev/null)" in
      root:*|"") ;;
      *.ftp:*|UNKNOWN:*|*:"${_WEBG:-www-data}")
        chown -h root:root /keys
        chmod 0700 /keys
        _msg "NOTE: /keys at the filesystem root is not empty; handed back to root (0700) and left in place"
        ;;
    esac
  fi
  if [ "${_HM_ONLY}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    # The new shared-code platforms lose their robots.txt: inside the real
    # distro/<core>, never through a platform entry the account planted as a
    # link.
    local _qW
    _qW="$(cd -P -- /data/disk 2> /dev/null && pwd -P)/${_USER}/distro/${_THIS_CORE}"
    if [ -n "${_THIS_CORE}" ]; then
      ( PATH=/usr/local/bin:/usr/bin:/bin
        cd -P -- "${_ROOT}/distro/${_THIS_CORE}" 2> /dev/null \
          && [ "$(pwd -P)" = "${_qW}" ] || exit 0
        find . -mindepth 2 -maxdepth 2 -name robots.txt ! -type d -delete ) &> /dev/null
    fi
    ### The core and the shared store are the account's during the build:
    ### the profiles are found from inside the real directory (find never
    ### follows a link, the globs did) and edited from the directory find
    ### walked, and each stamp is put as a fresh empty file (as touch made
    ### it), never created through a link put at the name.
    if [ ! -e "${_CORE}/javascript_aggregator.out.txt" ] \
      && [ -e "${_CORE}" ]; then
      _acct_in_real_dir "${_CORE}" env PATH=/usr/local/bin:/usr/bin:/bin \
        find . -mindepth 4 -maxdepth 4 -regextype posix-extended \
        -regex '\./[^/.][^/]*/profiles/[^/.][^/]*/[^/.][^/]*\.profile' \
        -type f -execdir timeout 60 sed -i \
        "s/, 'javascript_aggregator'//g" {} + &> /dev/null
      wait
      _acct_in_real_dir "${_CORE}" _satellite_put_stdin_here \
        javascript_aggregator.out.txt 0644 "" < /dev/null
    fi
  fi

  ###---### Remove not used cache module.
  #
  if [ ! -e "${_D}/000/old_cache.out2.txt" ] && [ -e "${_D}/000" ]; then
    _acct_in_real_dir "${_D}" env PATH=/usr/local/bin:/usr/bin:/bin \
      find . -mindepth 5 -maxdepth 5 -regextype posix-extended \
      -regex '\./[^/.][^/]*/[^/.][^/]*/profiles/[^/.][^/]*/[^/.][^/]*\.profile' \
      -type f -execdir timeout 60 sed -i \
      -e "s/, 'cache'//g" -e "s/'cache', //g" {} + &> /dev/null
    wait
    _acct_in_real_dir "${_D}" env PATH=/usr/local/bin:/usr/bin:/bin \
      find . -mindepth 3 -maxdepth 3 -regextype posix-extended \
      -regex '\./[^/.][^/]*/o_contrib/cache' -execdir rm -rf {} + &> /dev/null
    _acct_in_real_dir "${_D}/000" _satellite_put_stdin_here \
      old_cache.out2.txt 0644 "" < /dev/null
  fi
}

###---### Preparing setupmail.txt.
#
_satellite_prepare_setup_email_tpl() {
  local _mW _mT
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_prepare_setup_email_tpl"
    _debug_proc
  fi
  if [ "${_HM_ONLY}" = "YES" ]; then
    _DO_NOTHING=YES
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Preparing setupmail.txt"
    fi
    [ -n "${_MY_OCTO_EMAIL}" ] && _MY_OCTO_EMAIL=${_MY_OCTO_EMAIL//\\\@/\@}
    [ -n "${_CLIENT_EMAIL}" ] && _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
    if [ -e "${_ROOT}/log/setupmail.txt" ] \
      || [ -e "${_ROOT}/log/legacy_setupmail.txt" ] \
      || [ -e "${_ROOT}/log/latest_setupmail.txt" ]; then
      if [ "${_DIST_INSTALL}" = "YES" ]; then
        cd ${_ROOT}/log
        if [ -e "${_ROOT}/log/upgrademail.txt" ]; then
          _acct_in_real_dir "${_ROOT}/log" mv -f -T -- ./upgrademail.txt \
            "./upgrademail-pre-${_THIS_CORE}.txt"
        fi
        ### log/ is the instance user's: the email is rendered in root's own
        ### temp directory and put there once, as a fresh file, never written
        ### through a link or a FIFO put at the name.
        _mW="$(mktemp -d /opt/tmp/.mail-render.XXXXXX 2> /dev/null)"
        _mT="${_mW}/upgrademail.txt"
        if [ -d "${_mW}" ] \
          && cp -af /opt/tmp/boa/aegir/conf/tpl/upgrademail.txt "${_mT}"; then
          ### Anchored patterns: an unescaped dot or bare 'dragon' would also
          ### match inside a real instance domain injected by an earlier sed.
          ### The password (the account's log/pass.txt) and the other values
          ### are put in as literal text (_satellite_sed_rep).
          sed -i "s/aegir\.url\.name/$(_satellite_sed_rep "${_DOMAIN}")/g" "${_mT}"
          wait
          sed -i "s/dragon\.ftp/${_USER}.ftp/g" "${_mT}"
          wait
          sed -i "s/FN8rXcQn/$(_satellite_sed_rep "${_PASWD}")/g" "${_mT}"
          wait
          sed -i "s/166\.84\.6\.231/$(_satellite_sed_rep "${_THISHTIP}")/g" "${_mT}"
          wait
          sed -i "s/boa\.version/${_X_VERSION}/g" "${_mT}"
          wait
          _acct_in_real_dir "${_ROOT}/log" _satellite_put_stdin_here \
            upgrademail.txt "$(stat -c %a "${_mT}")" "" < "${_mT}"
        fi
        [ -n "${_mW}" ] && rm -rf -- "${_mW}"
      else
        _SEND_UPGRADE_EMAIL=NO
      fi
    elif [ "${_STATUS}" = "INIT" ]; then
     cd ${_ROOT}/log
     ### Rendered in root's own temp directory and put in log/ once, as the
     ### upgrade email above is.
     _mW="$(mktemp -d /opt/tmp/.mail-render.XXXXXX 2> /dev/null)"
     _mT="${_mW}/setupmail.txt"
     if [ -d "${_mW}" ] \
       && cp -af /opt/tmp/boa/aegir/conf/tpl/setupmail.txt "${_mT}"; then
       ### Anchored patterns: an unescaped dot or bare 'dragon' would also
       ### match inside a real instance domain injected by an earlier sed.
       sed -i "s/aegir\.url\.name/$(_satellite_sed_rep "${_DOMAIN}")/g" "${_mT}"
       wait
       sed -i "s/dragon\.ftp/${_USER}.ftp/g" "${_mT}"
       wait
       sed -i "s/FN8rXcQn/$(_satellite_sed_rep "${_PASWD}")/g" "${_mT}"
       wait
       ### The template placeholder is a real foreign address, so only a
       ### validated IPv4 may replace it; anything else keeps _ipOk=NO and
       ### the GOING LIVE strip below removes the whole section instead.
       _ipOk=NO
       if [ -n "${_THISHTIP}" ]; then
         if [ -e "/usr/bin/sipcalc" ]; then
           _IP_TEST=$(sipcalc ${_THISHTIP} 2>&1)
           [[ ! "${_IP_TEST}" =~ "ERR" ]] && _ipOk=YES
         elif [[ "${_THISHTIP}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
           _ipOk=YES
         fi
       fi
       if [ "${_ipOk}" = "YES" ]; then
         sed -i "s/166\.84\.6\.231/$(_satellite_sed_rep "${_THISHTIP}")/g" "${_mT}"
         wait
       else
         _msg "ALRT: _THISHTIP is empty or invalid; dropping the GOING LIVE section from the welcome email"
       fi
       sed -i "s/boa\.version/${_X_VERSION}/g" "${_mT}"
       wait
       ### FTPS is an opt-in xtra; drop its port line when Pure-FTPd is absent
       ### so the email never advertises a port nothing is listening on.
       if [ ! -e "/usr/local/sbin/pure-ftpd" ]; then
         sed -i "/21 (FTPS/d" "${_mT}"
         wait
       fi
       ### Adminer is guaranteed only where the hosted-aware gate installs it
       ### (hosted systems, or ADM/ALL in _XTRAS_LIST); a self-hosted box
       ### without it would email a database-browser URL that never opens.
       ### Strip the MANAGING YOUR DATABASES section (rule line above the
       ### heading through the line before the next section's rule) when the
       ### app is absent. Bounds are computed from the rendered file, so a
       ### template reflow cannot misdelete; no end rule found = keep.
       if [ ! -e "/var/www/adminer/index.php" ]; then
         _dbHead=$(grep -n '^MANAGING YOUR DATABASES$' "${_mT}" \
           | head -n 1 | cut -d: -f1)
         if [ -n "${_dbHead}" ] && [ "${_dbHead}" -gt 1 ]; then
           _dbTop=$(( _dbHead - 1 ))
           ### Literal 40-dash rule line: mawk has no {n} interval support.
           _dbNext=$(awk -v s="${_dbHead}" 'NR > (s + 1) && /^----------------------------------------$/ { print NR; exit }' \
             "${_mT}")
           if [ -n "${_dbNext}" ] && [ "${_dbNext}" -gt "$(( _dbTop + 2 ))" ]; then
             _dbEnd=$(( _dbNext - 1 ))
             sed -i "${_dbTop},${_dbEnd}d" "${_mT}"
             wait
           fi
         fi
       fi
       ### The template hardcodes the default SSH port; a self-hosted box may
       ### run sshd on a custom _SSH_PORT (hosted boxes are forced to 22).
       ### Substitute both the credentials line (anchored, so the FTPS line
       ### stays untouched) and the /sqladmin unlock wording. Guarded: only a
       ### validated numeric port is written, else the template's 22 stays.
       if [[ "${_SSH_PORT}" =~ ^[0-9]+$ ]] && [ "${_SSH_PORT}" != "22" ]; then
         sed -i "s/^port: 22 /port: ${_SSH_PORT} /" "${_mT}"
         wait
         sed -i "s/(port 22)/(port ${_SSH_PORT})/" "${_mT}"
         wait
       fi
       ### GOING LIVE tells the client to publish this box's address as an
       ### A record; strip the whole section (rule line above the heading
       ### through the section's closing rule line) when there is nothing
       ### publishable: LOCAL-network topologies (RFC1918 never belongs in
       ### client DNS) or an empty/invalid _THISHTIP (the placeholder would
       ### otherwise ship as a real foreign address). Bounds are computed
       ### from the rendered file, so a template reflow cannot misdelete.
       if [ -n "${_LOCAL_NETWORK_IP}" ] || [ "${_ipOk}" != "YES" ]; then
         _glHead=$(grep -n '^GOING LIVE$' "${_mT}" \
           | head -n 1 | cut -d: -f1)
         if [ -n "${_glHead}" ] && [ "${_glHead}" -gt 1 ]; then
           _glTop=$(( _glHead - 1 ))
           ### Literal 40-dash rule line: mawk has no {n} interval support.
           ### Stop BEFORE the next rule line: deleting through it removed
           ### the separator between the preceding section and the sign-off.
           _glNext=$(awk -v s="${_glHead}" 'NR > (s + 1) && /^----------------------------------------$/ { print NR; exit }' \
             "${_mT}")
           if [ -n "${_glNext}" ] && [ "${_glNext}" -gt "$(( _glTop + 2 ))" ]; then
             _glEnd=$(( _glNext - 1 ))
             sed -i "${_glTop},${_glEnd}d" "${_mT}"
             wait
           fi
         fi
       fi
       _acct_in_real_dir "${_ROOT}/log" _satellite_put_stdin_here \
         setupmail.txt "$(stat -c %a "${_mT}")" "" < "${_mT}"
     fi
     [ -n "${_mW}" ] && rm -rf -- "${_mW}"
    fi
  fi
}

###---### Set the client control-panel login (reuse the SSH/FTP identity).
#
_satellite_set_client_login() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_set_client_login"
    _debug_proc
  fi
  if [ "${_STATUS}" != "INIT" ]; then
    return 0
  fi
  if [ -z "${_CLIENT_EMAIL}" ] || [ -z "${_PASWD}" ]; then
    return 0
  fi
  # hosting_client gives the auto-created control-panel account an unusable
  # random password, so first login is impossible without a one-time link.
  # Reuse the shell identity instead: rename the account to ${_USER}.ftp and
  # set its password to the shell password. Matched by _CLIENT_EMAIL; the
  # uid>1 guard keeps the super-admin (uid 1) untouched. Runs as the octopus
  # user via the same drush pattern used above; _PASWD exists by this point.
  # Never fire-and-forget: the welcome email already states this login, so
  # any silent failure (bootstrap, DB, missing user) must become a loud
  # ALRT -- same sentinel pattern as _ensure_hosting_dispatch_enabled.
  local _login_ev _login_fix
  _login_ev="\$u = user_load_by_mail(\"${_CLIENT_EMAIL}\"); if (\$u && \$u->uid > 1 && user_save(\$u, array(\"name\" => \"${_USER}.ftp\", \"pass\" => \"${_PASWD}\"))) { echo \"RENAMED\"; }"
  _login_fix=$(su -s /bin/bash - ${_USER} -c "${_DRUSHCMD} @hostmaster ev '${_login_ev}'" 2>/dev/null)
  if [[ "${_login_fix}" =~ RENAMED ]]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "INFO: control-panel login for ${_USER} set to ${_USER}.ftp"
    fi
  else
    _msg "ALRT: control-panel login for ${_USER} was not set"
    _msg "ALRT: welcome email login details for the control panel will be wrong"
  fi
}

###---### Sending setup email.
#
_satellite_send_welcome_email() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_send_welcome_email"
    _debug_proc
  fi
  _MAILX_TEST=$(s-nail -V 2>&1)
  if [ "${_STATUS}" = "INIT" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Sending setup email on init..."
    fi
    _TIME=$(date)
    _Q="Your Ægir Install on ${_TIME} [${_USER}]"
    # one space between words, as the unquoted echo wrote the date
    _acct_put_in "${_ROOT}/log" date-init.txt "${_TIME//  / }"
    ### Historic renders can exist under legacy names; resolve the body
    ### once and use the SAME file for the guard and the send, so the
    ### guard can never pass on a name the send does not read (that
    ### combination mailed an empty credentials email). log/ is the
    ### instance user's: the body is read bounded from the real directory,
    ### never through a link or from a FIFO put at the name.
    _mailSrc=""
    for _mailCand in setupmail.txt legacy_setupmail.txt latest_setupmail.txt; do
      if [ -e "${_ROOT}/log/${_mailCand}" ]; then
        _mailSrc="${_ROOT}/log/${_mailCand}"
        break
      fi
    done
    if [ -n "${_mailSrc}" ]; then
      ### No send-time filter: the mailed body must stay byte-identical to
      ### the on-disk copy the operator is told to fall back to.
      _MAIL_SENT=NO
      if [[ "${_MAILX_TEST}" =~ "built for Linux" ]] \
        && [ -n "${_CLIENT_EMAIL}" ]; then
        if [ -n "${_MY_OCTO_EMAIL}" ]; then
          _acct_read_in "${_ROOT}/log" "${_mailSrc##*/}" \
            | s-nail -S ttycharset=utf-8 -S sendcharsets=utf-8 \
            -b "${_MY_OCTO_EMAIL}" -s "${_Q}" "${_CLIENT_EMAIL}" \
            && _MAIL_SENT=YES
        else
          _acct_read_in "${_ROOT}/log" "${_mailSrc##*/}" \
            | s-nail -S ttycharset=utf-8 -S sendcharsets=utf-8 \
            -s "${_Q}" "${_CLIENT_EMAIL}" \
            && _MAIL_SENT=YES
        fi
      fi
      if [ "${_MAIL_SENT}" = "NO" ]; then
        _msg "ALRT: Welcome email for ${_USER} was NOT sent"
        _msg "ALRT: Credentials are in ${_mailSrc}"
      fi
    fi
  else
    ### _SEND_UPGRADE_EMAIL=NO is an operator off-switch for the upgrade
    ### notice only; the INIT welcome email always sends.
    if [ "${_DIST_INSTALL}" = "YES" ] && [ "${_PLATFORMS_ONLY}" = "NO" ] \
      && [ "${_SEND_UPGRADE_EMAIL}" != "NO" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "${_STATUS} A: Resending setup email on upgrade..."
      fi
      _TIME=$(date)
      _Q="[${_X_VERSION}] Ægir Upgrade [${_USER}]"
      _acct_put_in "${_ROOT}/log" "date-upgrade-${_THIS_CORE}.txt" "${_TIME//  / }"
      ### Never fall back to the INIT-time setupmail render: it carries the
      ### original password under a Welcome body, so resending it under an
      ### Upgrade subject would mail stale credentials. No upgrademail.txt
      ### means no send; the trail below says which kind of miss it was.
      _mailBody="${_ROOT}/log/upgrademail.txt"
      _MAIL_SENT=NO
      if [[ "${_MAILX_TEST}" =~ "built for Linux" ]] \
        && [ -e "${_mailBody}" ] \
        && [ -n "${_CLIENT_EMAIL}" ]; then
        if [ -n "${_MY_OCTO_EMAIL}" ]; then
          _acct_read_in "${_ROOT}/log" upgrademail.txt \
            | s-nail -S ttycharset=utf-8 -S sendcharsets=utf-8 \
            -b "${_MY_OCTO_EMAIL}" -s "${_Q}" "${_CLIENT_EMAIL}" \
            && _MAIL_SENT=YES
        else
          _acct_read_in "${_ROOT}/log" upgrademail.txt \
            | s-nail -S ttycharset=utf-8 -S sendcharsets=utf-8 \
            -s "${_Q}" "${_CLIENT_EMAIL}" \
            && _MAIL_SENT=YES
        fi
      fi
      if [ "${_MAIL_SENT}" = "NO" ]; then
        ### The upgrade body is rendered only beside an INIT-time setupmail
        ### render (_satellite_prepare_setup_email_tpl), and an account
        ### installed under /root/.silent.update.cnf has none until its
        ### files arrive. With neither file present there was nothing to
        ### send and nothing failed, while an ALRT reports the whole pass
        ### as failed. A missing body beside a setupmail render is a failed
        ### render and a body that did not go out is a failed send: both
        ### stay loud.
        local _mailInit _mailCand
        _mailInit=NO
        for _mailCand in setupmail.txt legacy_setupmail.txt latest_setupmail.txt; do
          [ -e "${_ROOT}/log/${_mailCand}" ] && _mailInit=YES
        done
        if [ ! -e "${_mailBody}" ] && [ "${_mailInit}" = "NO" ]; then
          _msg "NOTE: No upgrade email for ${_USER}: no setup email render exists in ${_ROOT}/log"
        else
          _msg "ALRT: Upgrade email for ${_USER} was NOT sent"
          _msg "ALRT: The intended message body is in ${_mailBody}"
        fi
      fi
    else
      _SEND_UPGRADE_EMAIL=NO
    fi
  fi
}

#
# Satellite start.
_satellite_make() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_make"
    _debug_proc
  fi
  export _OS_DIST=$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2)
  export _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)
  if [ -d "/data/all/000" ]; then
    if [ ! -e "/data/all/000/core-v-${_SMALLCORE6_V}.txt" ] \
      || [ ! -e "/data/all/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      export _USE_CURRENT=NO
      export _HOT_SAUCE=YES
      export _HM_ONLY=NO
    fi
  fi

  _tocIncO="${_filIncO}.${_USER}"

  # Refuse to hand off provably broken values: each of these breaks the
  # children unconditionally (paths, mirror fetches, the shared-core prep)
  # and none is a legitimate empty state in any octopus mode
  for _hndVar in _USER _USE_MIR _DOMAIN _HM_DISTRO _ALL_DISTRO \
    _DRUPAL6 _DRUPAL7 _SMALLCORE6_V _SMALLCORE7_V; do
    if [ -z "${!_hndVar}" ]; then
      _msg "FATAL ERROR: ${_hndVar} is empty, child hand-off aborted"
      _msg "FATAL ERROR: Aborting Octopus installer NOW!"
      rm -f /opt/tmp/status-Octopus-FAIL
      touch /opt/tmp/status-Octopus-FAIL
      _clean_pid_exit _satellite_make_env
    fi
  done

  # Each child sources only its own sealed per-spawn include; build the
  # common payload on a private same-dir temp copy of this pass's base
  # (the wrapper's per-user clone on upgrades, the freshly fetched shared
  # include on installs), so the values are never half-written nor
  # readable by other local users
  if [ -e "${_vBs}/${_tocIncO}" ]; then
    _incBase="${_vBs}/${_tocIncO}"
  elif [ -e "${_vBs}/${_filIncO}" ]; then
    _incBase="${_vBs}/${_filIncO}"
  else
    _msg "FATAL ERROR: ${_vBs}/${_filIncO} is missing"
    _msg "FATAL ERROR: Aborting Octopus installer NOW!"
    rm -f /opt/tmp/status-Octopus-FAIL
    touch /opt/tmp/status-Octopus-FAIL
    _clean_pid_exit _satellite_make_inc
  fi
  _tmpIncO="${_vBs}/.${_tocIncO}.tmp"
  rm -f ${_tmpIncO}
  cp -af ${_incBase} ${_tmpIncO}
  chmod 0600 ${_tmpIncO}
  _writeTo="${_tmpIncO}"

  # Never serialize an empty PHP version: these appends shadow the
  # template's shipped default, so an empty value here would reach the
  # su'd child as-is and break its version branch table
  if [ -z "${_PHP_CLI_VERSION}" ]; then
    _cliPhpBin=$(readlink -f /usr/bin/php 2>/dev/null)
    _cliPhpNum="${_cliPhpBin%/bin/php}"
    _cliPhpNum="${_cliPhpNum##*php}"
    if [ -n "${_cliPhpNum}" ] && [ -x "/opt/php${_cliPhpNum}/bin/php" ]; then
      _PHP_CLI_VERSION="${_cliPhpNum:0:1}.${_cliPhpNum:1}"
    else
      for _fbV in 84 85 83 82 81 80 74; do
        if [ -x "/opt/php${_fbV}/bin/php" ]; then
          _PHP_CLI_VERSION="${_fbV:0:1}.${_fbV:1}"
          break
        fi
      done
    fi
    if [ -z "${_PHP_CLI_VERSION}" ]; then
      _PHP_CLI_VERSION=8.4
    fi
  fi
  if [ -z "${_PHP_FPM_VERSION}" ]; then
    _PHP_FPM_VERSION="${_PHP_CLI_VERSION}"
  fi

  export _xSrl=588855devT01
  export _X_VERSION="${_X_VERSION}"

  echo "export _AEGIR_VERSION=\"${_AEGIR_VERSION}\""         >> ${_writeTo}
  echo "export _AEGIR_XTS_VRN=\"${_tRee}\""                  >> ${_writeTo}
  echo "export _ALL_DISTRO=\"${_ALL_DISTRO}\""               >> ${_writeTo}
  echo "export _AUTOPILOT=\"${_AUTOPILOT}\""                 >> ${_writeTo}
  echo "export _BOA_REPO_GIT_URL=\"${_BOA_REPO_GIT_URL}\""   >> ${_writeTo}
  echo "export _BOA_REPO_NAME=\"${_BOA_REPO_NAME}\""         >> ${_writeTo}
  echo "export _BRANCH_BOA=\"${_BRANCH_BOA}\""               >> ${_writeTo}
  echo "export _BRANCH_PRN=\"${_BRANCH_PRN}\""               >> ${_writeTo}
  # Values the account's own files or directory names can carry (log/*.txt,
  # distro/ names) are written quoted for the shell, never inside bare
  # double quotes: the children source this include, AegirSetupA as root.
  _satellite_inc_put _CLIENT_CORES
  _satellite_inc_put _CLIENT_EMAIL
  _satellite_inc_put _CLIENT_OPTION
  echo "export _DEBUG_MODE=\"${_DEBUG_MODE}\""               >> ${_writeTo}
  echo "export _DL_MODE=\"${_DL_MODE}\""                     >> ${_writeTo}
  echo "export _DISTRO=\"${_DISTRO}\""                       >> ${_writeTo}
  _satellite_inc_put _DOMAIN

  echo "export _DRUPAL6=\"${_DRUPAL6}\""                     >> ${_writeTo}
  echo "export _DRUPAL6_D=\"${_DRUPAL6}-dev\""               >> ${_writeTo}
  echo "export _DRUPAL6_P=\"${_DRUPAL6}-prod\""              >> ${_writeTo}
  echo "export _DRUPAL6_S=\"${_DRUPAL6}-stage\""             >> ${_writeTo}

  echo "export _DRUPAL7=\"${_DRUPAL7}\""                     >> ${_writeTo}
  echo "export _DRUPAL7_D=\"${_DRUPAL7}-dev\""               >> ${_writeTo}
  echo "export _DRUPAL7_P=\"${_DRUPAL7}-prod\""              >> ${_writeTo}
  echo "export _DRUPAL7_S=\"${_DRUPAL7}-stage\""             >> ${_writeTo}

  echo "export _DRUPAL9=\"${_DRUPAL9}\""                     >> ${_writeTo}
  echo "export _DRUPAL9_D=\"${_DRUPAL9}-dev\""               >> ${_writeTo}
  echo "export _DRUPAL9_P=\"${_DRUPAL9}-prod\""              >> ${_writeTo}
  echo "export _DRUPAL9_S=\"${_DRUPAL9}-stage\""             >> ${_writeTo}

  echo "export _DRUPAL10_0=\"${_DRUPAL10_0}\""               >> ${_writeTo}
  echo "export _DRUPAL10_0_D=\"${_DRUPAL10_0}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL10_0_P=\"${_DRUPAL10_0}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL10_0_S=\"${_DRUPAL10_0}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL10_1=\"${_DRUPAL10_1}\""               >> ${_writeTo}
  echo "export _DRUPAL10_1_D=\"${_DRUPAL10_1}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL10_1_P=\"${_DRUPAL10_1}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL10_1_S=\"${_DRUPAL10_1}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL10_2=\"${_DRUPAL10_2}\""               >> ${_writeTo}
  echo "export _DRUPAL10_2_D=\"${_DRUPAL10_2}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL10_2_P=\"${_DRUPAL10_2}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL10_2_S=\"${_DRUPAL10_2}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL10_3=\"${_DRUPAL10_3}\""               >> ${_writeTo}
  echo "export _DRUPAL10_3_D=\"${_DRUPAL10_3}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL10_3_P=\"${_DRUPAL10_3}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL10_3_S=\"${_DRUPAL10_3}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL10_4=\"${_DRUPAL10_4}\""               >> ${_writeTo}
  echo "export _DRUPAL10_4_D=\"${_DRUPAL10_4}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL10_4_P=\"${_DRUPAL10_4}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL10_4_S=\"${_DRUPAL10_4}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL10_5=\"${_DRUPAL10_5}\""               >> ${_writeTo}
  echo "export _DRUPAL10_5_D=\"${_DRUPAL10_5}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL10_5_P=\"${_DRUPAL10_5}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL10_5_S=\"${_DRUPAL10_5}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL10_6=\"${_DRUPAL10_6}\""               >> ${_writeTo}
  echo "export _DRUPAL10_6_D=\"${_DRUPAL10_6}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL10_6_P=\"${_DRUPAL10_6}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL10_6_S=\"${_DRUPAL10_6}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL11_1=\"${_DRUPAL11_1}\""               >> ${_writeTo}
  echo "export _DRUPAL11_1_D=\"${_DRUPAL11_1}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL11_1_P=\"${_DRUPAL11_1}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL11_1_S=\"${_DRUPAL11_1}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL11_2=\"${_DRUPAL11_2}\""               >> ${_writeTo}
  echo "export _DRUPAL11_2_D=\"${_DRUPAL11_2}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL11_2_P=\"${_DRUPAL11_2}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL11_2_S=\"${_DRUPAL11_2}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL11_3=\"${_DRUPAL11_3}\""               >> ${_writeTo}
  echo "export _DRUPAL11_3_D=\"${_DRUPAL11_3}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL11_3_P=\"${_DRUPAL11_3}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL11_3_S=\"${_DRUPAL11_3}-stage\""       >> ${_writeTo}

  echo "export _DRUPAL11_4=\"${_DRUPAL11_4}\""               >> ${_writeTo}
  echo "export _DRUPAL11_4_D=\"${_DRUPAL11_4}-dev\""         >> ${_writeTo}
  echo "export _DRUPAL11_4_P=\"${_DRUPAL11_4}-prod\""        >> ${_writeTo}
  echo "export _DRUPAL11_4_S=\"${_DRUPAL11_4}-stage\""       >> ${_writeTo}

  # Resolve the newest Backdrop version from the mirror stamp so platforms track
  # the latest release without a hardcoded pin (fallback: _BACKDROP_V_FALLBACK);
  # the platform build fetches the matching versioned backdrop-<ver>.tar.gz.
  _bdrVrn=$(curl ${_crlGet} "https://${_USE_MIR}/core/backdrop.txt" 2>/dev/null | tr -cd '0-9.')
  [ -z "${_bdrVrn}" ] && _bdrVrn="${_BACKDROP_V_FALLBACK}"
  echo "export _BACKDROP_V=\"${_bdrVrn}\""                   >> ${_writeTo}
  echo "export _BACKDROP=\"backdrop-${_bdrVrn}\""            >> ${_writeTo}
  echo "export _BACKDROP_D=\"backdrop-${_bdrVrn}-dev\""      >> ${_writeTo}
  echo "export _BACKDROP_P=\"backdrop-${_bdrVrn}-prod\""     >> ${_writeTo}
  echo "export _BACKDROP_S=\"backdrop-${_bdrVrn}-stage\""    >> ${_writeTo}
  # The su'd child installers (AegirSetupC.sh.txt) source ONLY this env include,
  # not the root .octopus.cnf where the operator sets _BACKDROP_SUPPORT, so the
  # gate must be carried here too -- else the child BDR build arm
  # ([ "${_BACKDROP_SUPPORT}" = "YES" ]) is permanently dead and Backdrop
  # platforms never auto-build. Fail-closed: NO/empty keeps the gate shut.
  echo "export _BACKDROP_SUPPORT=\"${_BACKDROP_SUPPORT}\""   >> ${_writeTo}

  # Resolve the newest Grav version from the mirror stamp so platforms track
  # the latest official admin-bundle release without a hardcoded pin
  # (fallback: _GRAV_V_FALLBACK); the platform build fetches the matching
  # versioned grav-<ver>.tar.gz.
  _gravVrn=$(curl ${_crlGet} "https://${_USE_MIR}/core/grav.txt" 2>/dev/null | tr -cd '0-9.')
  [ -z "${_gravVrn}" ] && _gravVrn="${_GRAV_V_FALLBACK}"
  echo "export _GRAV_V=\"${_gravVrn}\""                      >> ${_writeTo}
  echo "export _GRAV=\"grav-${_gravVrn}\""                   >> ${_writeTo}
  echo "export _GRAV_D=\"grav-${_gravVrn}-dev\""             >> ${_writeTo}
  echo "export _GRAV_P=\"grav-${_gravVrn}-prod\""            >> ${_writeTo}
  echo "export _GRAV_S=\"grav-${_gravVrn}-stage\""           >> ${_writeTo}
  # Same sealed-include contract as _BACKDROP_SUPPORT above: the su'd child
  # installers source ONLY this env include, so the child GRV build arm reads
  # the gate from here. Fail-closed: NO/empty keeps the gate shut.
  echo "export _GRAV_SUPPORT=\"${_GRAV_SUPPORT}\""           >> ${_writeTo}

  # Resolve the newest Textpattern version from the mirror stamp so platforms
  # track the latest stable release without a hardcoded pin (fallback:
  # _TXP_V_FALLBACK); the platform build fetches the matching versioned
  # textpattern-<ver>.tar.gz. Stable releases are tags on main; the mirror's
  # textpattern.txt is published LAST by staticbuild, so a version resolved
  # here always has its artefacts already on the mirror.
  _txpVrn=$(curl ${_crlGet} "https://${_USE_MIR}/core/textpattern.txt" 2>/dev/null | tr -cd '0-9.')
  [ -z "${_txpVrn}" ] && _txpVrn="${_TXP_V_FALLBACK}"
  echo "export _TXP_V=\"${_txpVrn}\""                        >> ${_writeTo}
  echo "export _TXP=\"textpattern-${_txpVrn}\""              >> ${_writeTo}
  echo "export _TXP_D=\"textpattern-${_txpVrn}-dev\""        >> ${_writeTo}
  echo "export _TXP_P=\"textpattern-${_txpVrn}-prod\""       >> ${_writeTo}
  echo "export _TXP_S=\"textpattern-${_txpVrn}-stage\""      >> ${_writeTo}
  # Same reason as the two gates above: the su'd child installers source ONLY
  # this env include, never the root .octopus.cnf where the operator sets the
  # gate, so an unpropagated _TXP_SUPPORT is permanently dead in the child.
  # Fail-closed: NO/empty keeps the gate shut.
  echo "export _TXP_SUPPORT=\"${_TXP_SUPPORT}\""             >> ${_writeTo}

  echo "export _DRUSH_VERSION=\"${_DRUSH_VERSION}\""         >> ${_writeTo}
  echo "export _F_TIME=\"${_F_TIME}\""                       >> ${_writeTo}
  echo "export _HM_DISTRO=\"${_HM_DISTRO}\""                 >> ${_writeTo}
  echo "export _HM_ONLY=\"${_HM_ONLY}\""                     >> ${_writeTo}
  echo "export _HOT_SAUCE=\"${_HOT_SAUCE}\""                 >> ${_writeTo}
  echo "export _LAST_ALL=\"${_LAST_ALL}\""                   >> ${_writeTo}
  _satellite_inc_put _LAST_HMR
  _satellite_inc_put _LASTNUM
  # The children must know a LOCAL-network topology to keep RFC1918
  # addresses out of the rendered welcome email's DNS guidance.
  echo "export _LOCAL_NETWORK_IP=\"${_LOCAL_NETWORK_IP}\""   >> ${_writeTo}
  echo "export _MY_OCTO_EMAIL=\"${_MY_OCTO_EMAIL}\""         >> ${_writeTo}
  echo "export _MY_OWNIP=\"${_MY_OWNIP}\""                   >> ${_writeTo}
  echo "export _NOW=\"${_NOW}\""                             >> ${_writeTo}
  echo "export _OS_DIST=\"${_OS_DIST}\""                     >> ${_writeTo}
  echo "export _OS_CODE=\"${_OS_CODE}\""                     >> ${_writeTo}
  _satellite_inc_put _PHP_CLI_VERSION
  _satellite_inc_put _PHP_FPM_VERSION
  echo "export _PLATFORMS_LIST=\"${_PLATFORMS_LIST}\""       >> ${_writeTo}
  echo "export _PLATFORMS_ONLY=\"${_PLATFORMS_ONLY}\""       >> ${_writeTo}
  echo "export _PURGE_MODE=\"${_PURGE_MODE}\""               >> ${_writeTo}
  echo "export _REDIS_C_VERSION=\"${_REDIS_C_VERSION}\""     >> ${_writeTo}
  echo "export _REDIS_L_VERSION=\"${_REDIS_L_VERSION}\""     >> ${_writeTo}
  echo "export _REDIS_N_VERSION=\"${_REDIS_N_VERSION}\""     >> ${_writeTo}
  echo "export _REDIS_T_VERSION=\"${_REDIS_T_VERSION}\""     >> ${_writeTo}
  echo "export _REDIS_E_VERSION=\"${_REDIS_E_VERSION}\""     >> ${_writeTo}
  echo "export _REDIS_B_VERSION=\"${_REDIS_B_VERSION}\""     >> ${_writeTo}
  echo "export _SERIES_RESULT=\"${_SERIES_RESULT}\""         >> ${_writeTo}

  echo "export _SMALLCORE10_0_V=\"${_SMALLCORE10_0_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE10_1_V=\"${_SMALLCORE10_1_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE10_2_V=\"${_SMALLCORE10_2_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE10_3_V=\"${_SMALLCORE10_3_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE10_4_V=\"${_SMALLCORE10_4_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE10_5_V=\"${_SMALLCORE10_5_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE10_6_V=\"${_SMALLCORE10_6_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE11_1_V=\"${_SMALLCORE11_1_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE11_2_V=\"${_SMALLCORE11_2_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE11_3_V=\"${_SMALLCORE11_3_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE11_4_V=\"${_SMALLCORE11_4_V}\""     >> ${_writeTo}
  echo "export _SMALLCORE6_V=\"${_SMALLCORE6_V}\""           >> ${_writeTo}
  echo "export _SMALLCORE7_V=\"${_SMALLCORE7_V}\""           >> ${_writeTo}
  echo "export _SMALLCORE9_V=\"${_SMALLCORE9_V}\""           >> ${_writeTo}

  echo "export _SPINNER=\"${_SPINNER}\""                     >> ${_writeTo}
  # The emailed SSH port must be what sshd actually serves, never only a
  # declared value: hosted boxes and a failed sshd -t validation force 22
  # while the barracuda cnf may still say otherwise. Prefer the live sshd
  # config, fall back to the cnf (inline comments stripped, never sourced
  # -- sourcing a cnf slice resets config vars), then 22. Only a validated
  # numeric value is handed off, so the email fails safe to the template's
  # default.
  # The keyword's case varies by build (OpenSSH 10.5 prints "Port 22").
  _sshPrt=$(/usr/sbin/sshd -T 2>/dev/null | awk 'tolower($1) == "port" {print $2; exit}')
  if [[ ! "${_sshPrt}" =~ ^[0-9]+$ ]]; then
    _sshPrt=$(sed -n 's/^_SSH_PORT=//p' /root/.barracuda.cnf 2>/dev/null \
      | tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '" ')
  fi
  [[ "${_sshPrt}" =~ ^[0-9]+$ ]] || _sshPrt=22
  echo "export _SSH_PORT=\"${_sshPrt}\""                     >> ${_writeTo}
  echo "export _STRONG_PASSWORDS=\"${_STRONG_PASSWORDS}\""   >> ${_writeTo}
  echo "export _T_BUILD=\"${_T_BUILD}\""                     >> ${_writeTo}
  echo "export _THIS_DB_HOST=\"${_THIS_DB_HOST}\""           >> ${_writeTo}
  echo "export _THIS_DB_PORT=\"${_THIS_DB_PORT}\""           >> ${_writeTo}
  echo "export _OS_DIST=\"${_OS_DIST}\""                     >> ${_writeTo}
  echo "export _OS_CODE=\"${_OS_CODE}\""                     >> ${_writeTo}
  echo "export _THISHTIP=\"${_THISHTIP}\""                   >> ${_writeTo}
  echo "export _TODAY=\"${_TODAY}\""                         >> ${_writeTo}
  echo "export _USE_CURRENT=\"${_USE_CURRENT}\""             >> ${_writeTo}
  echo "export _USE_MIR=\"${_USE_MIR}\""                     >> ${_writeTo}
  echo "export _USER=\"${_USER}\""                           >> ${_writeTo}
  echo "export _USRG=\"${_USRG}\""                           >> ${_writeTo}
  echo "export _ACCG=\"${_ACCG}\""                           >> ${_writeTo}
  echo "export _INSTANCE_GROUP=\"${_INSTANCE_GROUP:-YES}\""    >> ${_writeTo}
  # The upgrade notice is sent by the stage A child, which sees only this
  # include: without the line the instance's NO never reached the send and
  # the switch did nothing. Only an exact NO is handed on, so a mistyped
  # value can never silence the notice.
  if [ "${_SEND_UPGRADE_EMAIL}" = "NO" ]; then
    echo "export _SEND_UPGRADE_EMAIL=\"NO\""                    >> ${_writeTo}
  else
    echo "export _SEND_UPGRADE_EMAIL=\"YES\""                   >> ${_writeTo}
  fi
  echo "export _WEBG=\"${_WEBG}\""                           >> ${_writeTo}
  echo "export _xSrl=\"${_xSrl}\""                           >> ${_writeTo}
  echo "export _X_VERSION=\"${_X_VERSION}\""                 >> ${_writeTo}

  # The phpNN.info instant markers steer every websh-dispatched CLI run,
  # but the platforms build child never passes through websh: it is
  # spawned as an explicit /bin/bash and takes its PHP purely from the
  # _PHP_CLI_VERSION serialized above, so only cli.info used to reach a
  # build. Resolve the markers here, at the producer, with websh's exact
  # rule -- highest marked-and-installed version wins, overriding the
  # cli.info-derived value while the marker exists -- and hand the
  # result to AegirSetupC alone via its sealed copy below. A/B keep the
  # cli.info value: the hostmaster leg must never follow client markers,
  # and the durable pins (drush shebang, launcher, octopus cnf) stay
  # cli.info-based so removing the marker leaves no trace. The forced
  # path_alias_cache 5.6 pin also outranks markers -- that pin exists
  # because a newer CLI breaks such platforms.
  _MRK_CLI_VERSION=
  _MRK_HM_PLR=
  if [ -e "${_ROOT}/.drush/hostmaster.alias.drushrc.php" ]; then
    _MRK_HM_PLR=$(_satellite_hm_alias_get "root'")
  fi
  if [ -z "${_MRK_HM_PLR}" ] \
    || [ ! -e "${_MRK_HM_PLR}/modules/path_alias_cache" ] \
    || [ ! -x "/opt/tools/drush/8/drush/drush.php" ] \
    || [ ! -x "/opt/php56/bin/php" ]; then
    for _mrkV in 56 70 71 72 73 74 80 81 82 83 84 85; do
      if [ -e "${_ROOT}/static/control/php${_mrkV}.info" ] \
        && [ -x "/opt/php${_mrkV}/bin/php" ]; then
        _MRK_CLI_VERSION="${_mrkV:0:1}.${_mrkV:1}"
      fi
    done
  fi
  if [ "${_MRK_CLI_VERSION}" = "${_PHP_CLI_VERSION}" ]; then
    _MRK_CLI_VERSION=
  fi
  if [ -n "${_MRK_CLI_VERSION}" ]; then
    _msg "VARS: Platforms build php-cli follows marker ${_MRK_CLI_VERSION} (cli.info ${_PHP_CLI_VERSION})"
  fi

  # Fan the common payload out to one sealed single-consumer include per
  # child, atomically, 0600, owned by the identity that sources it
  # (AegirSetupA runs as root; B/C run su'd as the instance user). The
  # per-user octopus.sh.cnf.<user> stays the wrapper-managed root channel
  # and no longer carries these appends. The seal must stay the LAST
  # line: each child asserts it after sourcing, so a truncated append
  # sequence or a foreign include is detected, not used.
  for _hndChd in AegirSetupA AegirSetupB AegirSetupC; do
    _hndTmp="${_vBs}/.${_tocIncO}.${_hndChd}.tmp"
    rm -f ${_hndTmp}
    cp -af ${_tmpIncO} ${_hndTmp}
    if [ "${_hndChd}" = "AegirSetupC" ] && [ -n "${_MRK_CLI_VERSION}" ]; then
      echo "export _PHP_CLI_VERSION=\"${_MRK_CLI_VERSION}\"" >> ${_hndTmp}
    fi
    echo "export _HANDOFF_SEAL=\"${_hndChd}\"" >> ${_hndTmp}
    if [ "${_hndChd}" = "AegirSetupA" ]; then
      chown root:root ${_hndTmp} &> /dev/null
    else
      chown ${_USER}:${_USRG} ${_hndTmp} &> /dev/null
    fi
    chmod 0600 ${_hndTmp}
    mv -f ${_hndTmp} ${_vBs}/${_tocIncO}.${_hndChd}
  done
  rm -f ${_tmpIncO}

  _THISHOST="${_hName}"
  if [ -e "/usr/bin/sipcalc" ]; then
    if [ -z "${_THISHTIP}" ]; then
      _LOC_DOM="${_THISHOST}"
      _find_correct_ip
      _THISHTIP="${_LOC_IP}"
    fi
    _IP_TEST=$(sipcalc ${_THISHTIP} 2>&1)
    if [[ "${_IP_TEST}" =~ "ERR" ]]; then
      _IP_TEST_RESULT=FAIL
      _LOCAL_THISHTIP=all
    else
      _IP_TEST_RESULT=OK
      _LOCAL_THISHTIP="${_THISHTIP}"
    fi
  else
    _LOCAL_THISHTIP="${_THISHTIP}"
  fi
  if [ -z "${_LOCAL_THISHTIP}" ]; then
    _LOC_DOM="${_THISHOST}"
    _find_correct_ip
    _LOCAL_THISHTIP="${_LOC_IP}"
  fi
  if [ -z "${_LOCAL_THISHTIP}" ]; then
    _LOCAL_THISHTIP=all
  fi

  cp -af ${_bldPth}/aegir/scripts/run-xdrago /var/xdrago/run-${_USER}
  sed -i "s/EDIT_USER/${_USER}/g" /var/xdrago/run-${_USER}
  wait
  chmod 700 /var/xdrago/run-${_USER} &> /dev/null
  # 0755 in the build tree, not 0700: the setup children are read by a su'd
  # satellite user, and read is all they need. The deployed copy above keeps
  # 0700 -- it is a different file on a different path.
  chmod 0755 ${_bldPth}/aegir/scripts/* &> /dev/null

  ### Make sure that required web services are up and running
  _mrun "webserver up"

  ###
  _AegirSetupA="${_bldPth}/aegir/scripts/AegirSetupA.sh.txt"
  bash ${_AegirSetupA} ${_USER}
  wait
  ###

  if [ -e "/opt/tmp/state/.root/${_USER}/status-AegirSetupA-FAIL" ] \
    || [ ! -e "/opt/tmp/state/.root/${_USER}/status-AegirSetupA-OK" ]; then
    _msg "FATAL ERROR: AegirSetupA installer failed"
    _msg "FATAL ERROR: Aborting Octopus installer NOW!"
    rm -f /opt/tmp/status-Octopus-FAIL
    touch /opt/tmp/status-Octopus-FAIL
    _clean_pid_exit _satellite_make_a
  fi
  # On a fresh install the identities were created inside AegirSetupA, so the
  # group derived before they existed is stale here; the parent's remaining
  # writes must use the account's real group.
  _ACCG=$(_acct_group "${_USER}")

  ### log/ is the instance user's: a missing name is put there as a fresh
  ### file inside the real directory, never created through a dangling link.
  if [ ! -e "${_ROOT}/log/email.txt" ]; then
    _acct_put_in "${_ROOT}/log" email.txt "${_CLIENT_EMAIL}"
  fi
  if [ ! -e "${_ROOT}/log/option.txt" ]; then
    _acct_put_in "${_ROOT}/log" option.txt "${_CLIENT_OPTION}"
  fi
  if [ ! -e "${_ROOT}/log/cores.txt" ]; then
    _acct_put_in "${_ROOT}/log" cores.txt "${_CLIENT_CORES}"
  fi
  if [ ! -e "${_ROOT}/log/subscr.txt" ]; then
    _acct_put_in "${_ROOT}/log" subscr.txt "${_CLIENT_SUBSCR}"
  fi
  if [ ! -e "${_ROOT}/log/fpm.txt" ]; then
    _acct_put_in "${_ROOT}/log" fpm.txt "${_PHP_FPM_VERSION}"
  fi
  if [ ! -e "${_ROOT}/log/cli.txt" ]; then
    _acct_put_in "${_ROOT}/log" cli.txt "${_PHP_CLI_VERSION}"
  fi
  _acct_in_real_dir "${_ROOT}/static" _satellite_ctrl_dir_here
  _acct_in_real_dir "${_ROOT}/static/control" _satellite_ctrl_make_here

  if [ -d "/data/all/000" ]; then
    if [ ! -e "/data/all/000/core-v-${_SMALLCORE6_V}.txt" ] \
      || [ ! -e "/data/all/000/core-v-${_SMALLCORE7_V}.txt" ]; then
      echo "${_SMALLCORE6_V}" > /data/all/000/core-v-${_SMALLCORE6_V}.txt
      echo "${_SMALLCORE7_V}" > /data/all/000/core-v-${_SMALLCORE7_V}.txt
    fi
  fi

  ### Stage the pinned D6->D7 contrib kit for provision-backdrop-d6-upgrade,
  ### behind _BACKDROP_SUPPORT. Stamp-gated no-op when current.
  _stage_d6d7_kit
  _stage_grav_releases
  ### Backstop bee for octopus-only boxes; no-op when already installed.
  _stage_bee

  if [ -e "${_ROOT}/log/email.txt" ]; then
    _PHP_FPM_MULTI=NO
    if [ -f "${_ROOT}/static/control/multi-fpm.info" ] \
      && [ -d "${_ROOT}/tools/le" ]; then
      _PHP_FPM_MULTI=YES
    fi
    if [ "${_PHP_FPM_MULTI}" = "NO" ]; then
      _satellite_tune_fpm_config
    fi
    _satellite_force_advanced_nginx_config
    _mrun "service nginx reload"
  fi
}

_satellite_if_head_github_connection_test() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_head_github_connection_test"
    _debug_proc
  fi
  ###--------------------###
  if [ "${_DL_MODE}" = "GIT" ]; then
    rm -rf /opt/tmp/test-*
    _check_connection
    _GITHUB_TEST=$(git clone ${_gitHub}/provision.git /opt/tmp/test-provision 2>&1)
    if [[ "${_GITHUB_TEST}" =~ "fatal" ]]; then
      echo " "
      _msg "EXIT on error (provision) due to GitHub downtime"
      _msg "Please try to run this script again in a few minutes"
      _msg "You may want to check https://www.githubstatus.com"
      _msg "Bye"
      rm -rf /opt/tmp/test-*
      _clean_pid_exit _satellite_if_head_github_connection_test_a
    fi
  fi
}

_satellite_if_sql_exception_test() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_sql_exception_test"
    _debug_proc
  fi
  ###--------------------###
  if [ ! -e "/run/mysqld/mysqld.pid" ] \
    || [ ! -e "/run/mysqld/mysqld.sock" ]; then
    _msg "ALRT! ${_DB_SERVER} server not running properly!"
    _msg "EXIT: We can't proceed and will exit now"
    _msg "HINT: (re)start ${_DB_SERVER} server, then run the installer again"
    _msg "Bye"
    _clean_pid_exit _satellite_if_sql_exception_test_a
  fi
}

_check_system_manufacturer() {
  # Extract manufacturer string
  _SYS_MANUFACTURER_RAW=$(dmidecode -s system-manufacturer 2>/dev/null)

  # Trim leading/trailing whitespace, convert spaces to underscores
  _SYS_MANUFACTURER_CLEAN=$(printf "%s" "${_SYS_MANUFACTURER_RAW}" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/_/g')

  # Normalise: keep only A-Za-z0-9_
  _SYS_MANUFACTURER=$(printf "%s" "${_SYS_MANUFACTURER_CLEAN}" | tr -cd 'A-Za-z0-9_')

  # Enforce max length with safe underscore-aware truncation
  _MAX_LEN=32
  if [ "${#_SYS_MANUFACTURER}" -gt "${_MAX_LEN}" ]; then
    _CUT=$(printf "%s" "${_SYS_MANUFACTURER}" | cut -c1-"${_MAX_LEN}")
    _SAFE_CUT=$(printf "%s" "${_CUT}" | sed 's/_[^_]*$//')
    if [ -n "${_SAFE_CUT}" ]; then
      _SYS_MANUFACTURER="${_SAFE_CUT}"
    else
      _SYS_MANUFACTURER="${_CUT}"
    fi
  fi

  # Secondary variable: lowercase
  _SYS_MANUFACTURER_LC=$(printf "%s" "${_SYS_MANUFACTURER}" | tr 'A-Z' 'a-z')

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "_SYS_MANUFACTURER_RAW: ${_SYS_MANUFACTURER_RAW}"
    _msg "_SYS_MANUFACTURER_CLEAN: ${_SYS_MANUFACTURER_CLEAN}"
    _msg "_SYS_MANUFACTURER: ${_SYS_MANUFACTURER}"
    _msg "_SYS_MANUFACTURER_LC: ${_SYS_MANUFACTURER_LC}"
  fi
}

_satellite_if_running_as_root_octopus() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_running_as_root_octopus"
    _debug_proc
  fi
  if [ "$(id -u)" -eq 0 ]; then
    chmod a+w /dev/null
    _check_system_manufacturer
    if [ -n "${_SYS_MANUFACTURER_LC}" ]; then
      if  [ ! -e "/var/aegir/.drush/hm.alias.drushrc.php" ] \
        || [ ! -e "/data/u" ] \
        || [ ! -e "/var/xdrago" ]; then
        if [ ! -e "/var/log/boa/${_SYS_MANUFACTURER_LC}_vm_postinstall.pid" ]; then
          touch /var/log/boa/${_SYS_MANUFACTURER_LC}_vm.pid
        fi
      fi
    fi
  else
    _msg "ERROR: This script should be run as a root user"
    _msg "Bye"
    _clean_pid_exit
  fi
}

_satellite_check_sanitize_user_name() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_check_sanitize_user_name"
    _debug_proc
  fi
  _USER=${_USER//[^a-zA-Z0-9-.]/}
  _USER=$(echo -n ${_USER} | tr A-Z a-z 2>&1)
  _WEB="${_USER}.web"
  _ROOT="/data/disk/${_USER}"
  # Group owning this account's tree, derived per run: 'users' until the
  # account carries a private primary group named after itself (see
  # _acct_group in helper.sh.inc). _USRG stays the box-wide group for the
  # shared paths (/data/u, the cores) and must not be repointed.
  _ACCG=$(_acct_group "${_USER}")
  if [ -d "${_ROOT}" ]; then
    _STATUS=UPGRADE
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _satellite_check_id
  fi
}

_satellite_if_localhost_mode_magic() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_localhost_mode_magic"
    _debug_proc
  fi
  _THIS_HOST="${_hName}"
  if [ "${_THIS_HOST}" = "aegir.local" ] && [ ! -d "${_ROOT}" ]; then
    _DEBUG_MODE=NO
    _DNS_SETUP_TEST=NO
    _DOMAIN="${_USER}.sub.aegir.local"
    _LOCAL_NETWORK_IP="127.0.1.1"
    _MY_OWNIP="${_LOCAL_NETWORK_IP}"
    _msg "_LOCAL_NETWORK_IP is ${_LOCAL_NETWORK_IP}"
  fi
}

_satellite_check_sanitize_domain_name() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_check_sanitize_domain_name"
    _debug_proc
  fi
  _DOMAIN=${_DOMAIN//[^a-zA-Z0-9-.]/}
  _DOMAIN=$(echo -n ${_DOMAIN} | tr A-Z a-z 2>&1)
  if [ ! -f "/var/aegir/config/server_master/nginx/vhost.d/${_DOMAIN}" ]; then
    _DO_NOTHING=YES
  else
    _msg "ERROR: ${_DOMAIN} is already used on the Ægir Master Instance"
    _msg "Please change the value for _DOMAIN to make it unique"
    _msg "Bye"
    _clean_pid_exit
  fi
}

_satellite_detect_vm_family() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_detect_vm_family"
    _debug_proc
  fi
  _VM_TEST="$(uname -a)"
  if [[ "${_VM_TEST}" =~ "-beng" ]]; then
    _VMFAMILY="VS"
  else
    _VMFAMILY="XEN"
  fi
  # Check for Amazon EC2 in the system manufacturer field
  if dmidecode -s system-manufacturer 2> /dev/null | grep -qi 'Amazon EC2'; then
    _VMFAMILY="AWS"
  fi
  if [ "${_VMFAMILY}" = "AWS" ]; then
    if [ "${_STATUS}" = "INIT" ]; then
      _THIS_DB_HOST=localhost
    fi
    _LOC_DOM="${_DOMAIN}"
    if [ -z "${_MY_OWNIP}" ]; then
      _find_correct_ip
      _MY_OWNIP="${_LOC_IP}"
    else
      _LOC_IP="${_MY_OWNIP}"
    fi
  fi
}

#
# The account's static/control is the main login's, so it can put a link or
# a FIFO at any name there, or at control itself: these run inside the real
# directory (_acct_in_real_dir) and never follow or open either.
#
# ./control made a real directory, run inside the real static/: a link put
# at the name is removed, a missing directory created 0755.
_satellite_ctrl_dir_here() {
  [ -L ./control ] && rm -f ./control
  [ -d ./control ] || ( umask 022; mkdir -p ./control )
}
# The control directory on install and upgrade (run inside it): fpm.info
# and cli.info where missing (cli.info from a regular fpm.info), the README
# and this serial's stamp on its first pass, the tree handed to the main
# login as _satellite_reown_here hands it (never a link, nor a file the
# login hard-linked there).
_satellite_ctrl_make_here() {
  local _v
  [ -e ./fpm.info ] || _acct_put_here fpm.info "${_PHP_FPM_VERSION}"
  if [ ! -e ./cli.info ]; then
    _v=""
    [ -e ./fpm.info ] && _v="$(_acct_read_here fpm.info)"
    _acct_put_here cli.info "${_v:-${_PHP_CLI_VERSION}}"
  fi
  if [ ! -e "./.ctrl.${_tRee}.${_xSrl}.pid" ] \
    && [ -e "/home/${_USER}.ftp/clients" ]; then
    if [ -e "/var/xdrago/conf/control-readme.txt" ]; then
      ( umask 022
        cp -T --no-preserve=mode --remove-destination \
          /var/xdrago/conf/control-readme.txt ./README.txt ) &> /dev/null
    fi
    rm -f -- ./.ctrl.*
    _acct_put_here ".ctrl.${_tRee}.${_xSrl}.pid" OK
  fi
  _satellite_reown_here "${_USER}.ftp:${_ACCG:-users}"
}

#
# The instance user owns the rest of the account (log/, .drush/, tools/,
# .ssh/, the hostmaster tree), so any name there can be a link or a FIFO too.
# Root reads, writes, copies, edits and sets modes there only through these,
# run inside the real directory (_acct_in_real_dir), beside the shared
# _acct_* helpers.
#
# A mode set on names in the current (pinned) directory, never through a
# link: each name is opened without following one and without blocking on a
# FIFO, checked to be the expected type and changed through the open handle.
# Run it inside a pinned directory or from find -execdir: O_NOFOLLOW covers
# the last name only. Args: f|d (regular file or directory), the mode
# (octal), the names.
# A directory keeps its set-user-ID and set-group-ID bits unless the mode has
# five digits (02775, 00755), as chmod(1) does with a numeric mode. A regular
# file is changed only while it has a single link: a hard link the account
# planted or renamed over a name is never given the mode.
_SAT_NOFOLLOW_CHMOD_PL='use Fcntl;
my ($t, $ms) = (shift @ARGV, shift @ARGV);
my ($m, $k) = (oct($ms), length($ms) < 5 ? 06000 : 0);
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if ($t eq "f" && -f _ && $s[3] == 1) {
    chmod($m, $h);
  } elsif ($t eq "d" && -d _) {
    chmod($m | ($s[2] & $k), $h);
  }
  close($h);
}'
_satellite_chmod_nofollow() {
  local _t="${1}" _m="${2}"
  shift 2
  [ "$#" -gt 0 ] || return 0
  perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" "${_t}" "${_m}" "$@" 2> /dev/null
}
# ./$1 in the current (pinned) directory made from stdin: a fresh file
# created exclusively (0600 until it is complete), handed to $3 (owner:group,
# names or numbers; empty leaves it root's) and given the mode $2, both
# through the handle that created it (_ACCT_PUT_MODE_PL), and renamed over
# the name, so a link or a FIFO put at the name is replaced, never followed
# or opened, and nothing is handed over or moded by name.
_satellite_put_stdin_here() {
  local _t="./.${1}.put.$$.${RANDOM}" _u=-1 _g=-1
  if [ -n "${3}" ]; then
    _u="${3%%:*}"
    _g="${3#*:}"
    [[ "${_u}" =~ ^[0-9]+$ ]] || _u=$(id -u -- "${_u}" 2> /dev/null)
    [[ "${_g}" =~ ^[0-9]+$ ]] \
      || _g=$(getent group "${_g}" 2> /dev/null | cut -d: -f3)
    [[ "${_u}" =~ ^[0-9]+$ && "${_g}" =~ ^[0-9]+$ ]] || return 1
  fi
  rm -f -- "${_t}"
  if perl -e "${_ACCT_PUT_MODE_PL}" "${_t}" "${_u}" "${_g}" "${2:-0644}" \
    2> /dev/null && mv -f -T -- "${_t}" "./${1}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# owner[:group] as chown takes it (names; an empty owner or no group keeps
# that id) printed as the "uid gid" _ACCT_REOWN_PL takes (-1 kept); nothing
# when a name does not resolve.
_satellite_ids() {
  local _u=-1 _g=-1
  [ -z "${1%%:*}" ] || _u=$(id -u -- "${1%%:*}" 2> /dev/null)
  if [[ "${1}" == *:* ]]; then
    _g=$(getent group "${1#*:}" 2> /dev/null | cut -d: -f3)
  fi
  [[ "${_u}" =~ ^(-1|[0-9]+)$ && "${_g}" =~ ^(-1|[0-9]+)$ ]] || return 1
  echo "${_u} ${_g}"
}
# The current (pinned) directory and everything below it handed to $1
# (owner[:group], as chown -R took it) through _ACCT_REOWN_PL, from the
# directory find walked (-execdir): each directory and each regular file
# with a single link, never a link, a FIFO, a socket or a hard-linked file,
# so a hard link the account planted in the tree is never handed over.
# Further arguments are find tests put in front of the walk (a prune).
_satellite_reown_here() {
  local _u _g
  read -r _u _g <<< "$(_satellite_ids "${1}")"
  [ -n "${_g}" ] || return 1
  shift
  perl -e "${_ACCT_REOWN_PL}" -- "${_u}" "${_g}" . \
    && env PATH=/usr/local/bin:/usr/bin:/bin find . -mindepth 1 "$@" \
      -execdir perl -e "${_ACCT_REOWN_PL}" -- "${_u}" "${_g}" {} +
}
# The names given in the current (pinned) directory handed to $1
# (owner[:group]) through _ACCT_REOWN_PL, as chown or chgrp handed them,
# except a link, a FIFO, a socket or a hard-linked file.
_satellite_reown_names_here() {
  local _u _g
  read -r _u _g <<< "$(_satellite_ids "${1}")"
  [ -n "${_g}" ] || return 1
  shift
  perl -e "${_ACCT_REOWN_PL}" -- "${_u}" "${_g}" "$@"
}
# The current (pinned) directory and every directory below it set to $1,
# every regular file below it to $2, as find -type d|f -exec chmod set them,
# each through a handle opened without following a link, from the
# directory find walked (-execdir); a hard-linked file is left alone.
_satellite_modes_walk_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  _satellite_chmod_nofollow d "${1}" .
  find . -mindepth 1 -type d \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d "${1}" {} +
  find . -mindepth 1 -type f \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" f "${2}" {} +
)
# Each directory and regular file named (find -execdir, or in a pinned
# directory) made root's, with the mode $1 for a directory (its set-ID bits
# kept, as chmod 0755 keeps them) and $2 for a file, except xmass's two
# records, which xmass writes 0600. An entry is checked by lstat before it is
# opened, so a FIFO or a device is never opened, and is changed through its
# own handle, never through a link. A hard-linked file is taken back too:
# /data/conf is never an account's, so a file an account linked there is
# made root's, as chown -R root:root made it.
_CONF_ROOT_PL='use Fcntl;
my ($dm, $fm) = (oct(shift @ARGV), oct(shift @ARGV));
for my $f (@ARGV) {
  my @l = lstat($f);
  next unless @l && (-d _ || -f _);
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if (@s && $s[0] == $l[0] && $s[1] == $l[1]) {
    if (-d _) {
      chown(0, 0, $h);
      chmod($dm | ($s[2] & 06000), $h);
    } elsif (-f _) {
      chown(0, 0, $h);
      chmod($f =~ m{(^|/)xmass_(state|solr_used)\.cnf(\.tmp\.\d+)?$} ? 0600 : $fm, $h);
    }
  }
  close($h);
}'
# /data/conf (the current, pinned directory) and everything below it made
# root's (_CONF_ROOT_PL): directories 0755, files 0644, the top 0711. Every
# site on the box loads its global includes from here and nothing an account
# runs writes here, so it is never handed to an account.
_satellite_conf_root_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  perl -e "${_CONF_ROOT_PL}" 0755 0644 .
  find . -mindepth 1 \( -type d -o -type f \) \
    -execdir perl -e "${_CONF_ROOT_PL}" 0755 0644 {} +
  chmod 0711 .
)
# stdin appended to ./$1 in the current (pinned) directory, as >> appends
# (a missing file created 0644), but only to a regular file: a link or a FIFO
# put at the name is refused, never followed or opened.
_SAT_APPEND_PL='use Fcntl;
sysopen(my $h, $ARGV[0], O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0644)
  or exit 1;
-f $h or exit 1;
local $/;
my $d = <STDIN>;
print {$h} $d if defined $d;
close($h) or exit 1;'
_satellite_append_here() {
  perl -e "${_SAT_APPEND_PL}" "./${1}" 2> /dev/null
}
# The last MiB of ./$1 in the current (pinned) directory (all of it when
# smaller), read as _acct_read_here reads: for a log whose newest lines are
# at its end.
_satellite_read_tail_here() {
  local _s
  _s="$(stat -c %s -- "./${1}" 2> /dev/null)"
  _s="$(( ${_s:-0} > 1048576 ? ${_s:-0} - 1048576 : 0 ))"
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock,skip_bytes \
    skip="${_s}" bs=1048576 count=1 status=none 2> /dev/null
}
# uid:gid and mode of ./$1 in the current (pinned) directory when it is a
# regular file _acct_read_here reads whole (1 MiB at most); fails otherwise.
_satellite_stat_here() {
  local _o _m _s
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
  read -r _o _m _s <<< "$(stat -c '%u:%g %a %s' -- "./${1}" 2> /dev/null)"
  [ -n "${_s}" ] && [ "${_s}" -le 1048576 ] || return 1
  echo "${_o} ${_m}"
}
# ./$2 in the current (pinned) directory made from the regular file ./$1 (the
# same name edits it in place), through the sed script $3 when given, with
# $1's owner and mode: what cp -a or sed -i did there, without following a
# link or opening a FIFO at either name.
_satellite_copy_here() {
  local _st
  _st="$(_satellite_stat_here "${1}")" || return 1
  _acct_read_here "${1}" | sed -e "${3:-}" \
    | _satellite_put_stdin_here "${2}" "${_st#* }" "${_st%% *}"
}
# The sed script $1 applied as _satellite_copy_here applies it to every name
# the glob $2 matches in the current (pinned) directory, expanded there.
_satellite_edit_all_here() (
  local _f
  shopt -s nullglob
  # shellcheck disable=SC2086
  for _f in ./${2}; do
    _satellite_copy_here "${_f#./}" "${_f#./}" "${1}"
  done
)
# The current (pinned) directory handed to $1 (owner:group) with the mode $2.
_satellite_own_dir_here() {
  chown -h "${1}" . && chmod "${2}" .
}
# The link ./$1 in the current (pinned) directory handed to $2 (owner[:group]
# names; an owner alone keeps the link's group), as chown -h handed it: made
# anew by that owner (setpriv) under a fresh name, to the same target, and
# renamed over the name, so nothing is chowned by name where the account
# could swap a file in for the link. Left as it is when it already has that
# owner or cannot be made so. Only the owner is compared: in a setgid
# directory a new link takes the directory's group whatever the maker's, and
# a link's group grants nothing, so comparing it would re-make the link on
# every pass.
_satellite_relink_here() {
  local _t="./.${1}.rln.$$.${RANDOM}" _l _u _g
  read -r _u _g <<< "$(_satellite_ids "${2}")"
  [ -L "./${1}" ] || return 1
  [ "${_g}" = "-1" ] && _g="$(stat -c %g -- "./${1}" 2> /dev/null)"
  [[ "${_u}" =~ ^[0-9]+$ && "${_g}" =~ ^[0-9]+$ ]] || return 1
  [ "$(stat -c '%u' -- "./${1}" 2> /dev/null)" = "${_u}" ] && return 0
  _l="$(readlink -- "./${1}")" && [ -n "${_l}" ] || return 1
  rm -f -- "${_t}"
  setpriv --reuid="${_u}" --regid="${_g}" --clear-groups \
    ln -s -- "${_l}" "${_t}" 2> /dev/null
  if [ -L "${_t}" ] && mv -f -T -- "${_t}" "./${1}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# One value of the account's hostmaster alias ($1 = the key and its closing
# quote, as root' or site_path'), parsed as before from a bounded read that
# never follows a link or blocks on a FIFO.
_satellite_hm_alias_get() {
  _acct_read_in "${_ROOT}/.drush" hostmaster.alias.drushrc.php \
    | grep "${1}" \
    | cut -d: -f2 \
    | awk '{ print $3}' \
    | sed "s/[\,']//g" 2>&1
}
# True when $1 names one of the account's own hostmaster roots
# (<root>/aegir/distro/<name>) or, with $2 = site, a site in one
# (.../<name>/sites/<site>). The alias is the account's file: a path read
# from it is used only there, and only through _acct_in_real_dir, which also
# refuses a link or a dot name on the way.
_satellite_hm_path_ok() {
  local _p="${1#"${_ROOT}/aegir/distro/"}"
  [ -n "${1}" ] && [ "${_p}" != "${1}" ] || return 1
  if [ "${2}" = "site" ]; then
    [[ "${_p}" =~ ^[^/]+/sites/[^/]+$ ]]
  else
    [[ "${_p}" =~ ^[^/]+$ ]]
  fi
}
# Run "$@" inside the real directory $1, as _acct_in_real_dir runs it, or,
# when $1 is a link into the account's files store (backups relocated onto
# the store, a site's files/ or private/ moved into it), inside the
# directory the link resolves to: only one in the account's own
# static/files, or in the store moved onto attached storage
# (/mnt/<mount>/files/<oN>/static/files). Any other link is refused.
_satellite_in_store_dir() {
  local _d="${1}" _r _s _m
  shift
  if [ ! -L "${_d}" ]; then
    _acct_in_real_dir "${_d}" "$@"
    return
  fi
  _r="$(readlink -f -- "${_d}" 2> /dev/null)"
  _s="$(cd -P -- /data/disk 2> /dev/null && pwd -P)/${_USER}/static/files/"
  # The store on attached storage is /mnt/<mount>/files/<oN>/static/files,
  # the mount itself possibly nested, as migratefs accepts it under /mnt,
  # as the nightly decides it.
  case "${_r}" in
    ""|*[!A-Za-z0-9._/-]*) return 1 ;;
    "${_s}"?*) ;;
    /mnt/?*/files/"${_USER}"/static/files/?*)
      _m="${_r%%/files/"${_USER}"/static/files/*}"
      case "${_m}" in
        */files/*|*/static/*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  ( cd -P -- "${_r}" 2> /dev/null && [ "$(pwd -P)" = "${_r}" ] && "$@" )
}
# ./$1 in the current (pinned) directory made a directory where missing,
# then "${@:2}" run inside it as _acct_in_real_dir runs it: a link put at
# the name is never followed or entered.
_satellite_sub_here() {
  local _n="${1}"
  shift
  mkdir -p -- "./${_n}" 2> /dev/null
  _acct_in_real_dir "./${_n}" "$@"
}
# The command line $1 run by the instance user from its own home, with HOME
# set to it and the system PATH, whatever the calling environment holds
# (git reads its config from HOME): whatever a link in the account's tree
# leads to, it reaches only what that user may change.
_satellite_as_user() {
  su -s /bin/bash "${_USER}" \
    -c "cd ${_ROOT} && export HOME=${_ROOT} PATH=/usr/local/bin:/usr/bin:/bin && { ${1}; }"
}
# +i cleared on each regular file named, in the current (pinned) directory,
# through a handle (_ACCT_CHATTR_PL): never through a link, nor on a file
# the account hard-linked or renamed over the name.
_satellite_unlock_here() {
  local _f
  for _f in "$@"; do
    [ -f "./${_f}" ] && [ ! -L "./${_f}" ] \
      && perl -e "${_ACCT_CHATTR_PL}" - "./${_f}" &> /dev/null
  done
  return 0
}
# The current (pinned) platforms/ of a main login and each entry in it
# locked ($1 = +i) or unlocked (-i): a directory entry from inside it (on
# '.', once entered as the real directory), a regular file through a handle
# (_ACCT_CHATTR_PL, a single link only); a link is left alone.
_satellite_chattr_all_here() {
  local _e
  chattr "${1}" . &> /dev/null
  for _e in ./*; do
    if [ -d "${_e}" ] && [ ! -L "${_e}" ]; then
      _acct_in_real_dir "${_e}" chattr "${1}" . &> /dev/null
    elif [ -f "${_e}" ] && [ ! -L "${_e}" ]; then
      perl -e "${_ACCT_CHATTR_PL}" "${1%i}" "${_e}" &> /dev/null
    fi
  done
  return 0
}
# The current (pinned) ~/.drush of a main login locked ($1 = +i) or
# unlocked (-i) with its usr/ when that is a real directory (from inside
# it, on '.'); unlocking also clears a CLI php.ini an earlier release left,
# for the ltd worker to remove.
_satellite_chattr_drush_here() {
  chattr "${1}" . &> /dev/null
  [ -d ./usr ] && [ ! -L ./usr ] \
    && _acct_in_real_dir ./usr chattr "${1}" . &> /dev/null
  [ "${1}" = "-i" ] && _satellite_unlock_here php.ini
  return 0
}
# The current (pinned) directory and every directory and single-link
# regular file below it unlocked (-i), each through a handle opened without
# following a link or blocking on a FIFO (_ACCT_CHATTR_PL), from the
# directory find walked (-execdir): a link, a FIFO or a hard-linked file is
# left alone.
_satellite_unlock_tree_here() {
  perl -e "${_ACCT_CHATTR_PL}" - . &> /dev/null
  env PATH=/usr/local/bin:/usr/bin:/bin find . -mindepth 1 \
    \( -type d -o -type f \) \
    -execdir perl -e "${_ACCT_CHATTR_PL}" - {} + &> /dev/null
  return 0
}
# Every directory set to $1 and every file to $2 below the current (pinned)
# directory, top-level dot names left out as the globs this replaces left
# them, each through a handle opened without following a link, from the
# directory find walked (-execdir).
_satellite_tree_modes_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  find . -mindepth 1 -path './.*' -prune -o -type d \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d "${1}" {} +
  find . -mindepth 1 -path './.*' -prune -o -type f \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" f "${2}" {} +
)
# The current (pinned) directory and every directory below it set to $1,
# every regular file below it to $2, dot entries included, as the nightly
# sets a site's files store, each through a handle opened without
# following a link, from the directory find walked (-execdir): a name
# swapped for a link during the walk is refused, never followed.
_satellite_tree_mode_all_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  _satellite_chmod_nofollow d "${1}" .
  find . -mindepth 1 -type d \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d "${1}" {} +
  find . -mindepth 1 -type f \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" f "${2}" {} +
)
# The current (pinned) backups directory's system/ (and system/$1 when
# given) made where missing, handed to the instance user and set 0700,
# each inside its real directory: the instance user moves its own old
# backups there.
_satellite_sys_dir_here() {
  _satellite_sub_here system _satellite_own_dir_here \
    "${_USER}:${_ACCG:-users}" 0700 || return 1
  [ -z "${1}" ] || _acct_in_real_dir ./system _satellite_sub_here "${1}" \
    _satellite_own_dir_here "${_USER}:${_ACCG:-users}" 0700
}
# The main login's new ~/.tmp (the current, pinned directory): anything
# older than a day removed from inside the directory find walked, the tree
# handed to the login (_satellite_reown_here), the directory 0755.
_satellite_ftp_tmp_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  touch .
  find . -mindepth 1 -mtime +0 -execdir rm -rf {} \;
  _satellite_reown_here "${_USERFTP}:${_ACCG:-users}"
  chmod 755 .
)
# A login's ~/.bazaar (the current, pinned directory) seeded: bazaar.conf
# put as a fresh file, the tree handed to $1 (owner:group) as
# _satellite_reown_here hands it, the directory 0700.
_satellite_bzr_seed_here() {
  _acct_put_here bazaar.conf ignore_missing_extensions=True
  _satellite_reown_here "${1}"
  chmod 700 .
}
# The main login's ~/.drush (the current, pinned directory) and its usr/
# made real directories and handed to the login, ~/.drush 0700, and usr/$1
# linked to the instance user's own copy of that drush extension: a link
# put at usr is removed first, and usr/ is handed over from inside it (on
# '.', once entered as the real directory), so no owner or mode is set
# through a link or on a file put at the name.
_satellite_user_ds_link_here() {
  [ -L ./usr ] && rm -f ./usr
  mkdir -p ./usr
  chown -h "${_USERFTP}:${_ACCG:-users}" .
  _acct_in_real_dir ./usr chown -h "${_USERFTP}:${_ACCG:-users}" .
  chmod 700 .
  _acct_in_real_dir ./usr ln -sfn "${_ROOT}/.drush/usr/${1}" "./${1}"
}
# ./$2 in the current (pinned) directory made a link to $1 where no name
# there resolves.
_satellite_link_new_here() {
  [ -e "./${2}" ] || ln -sfn "${1}" "./${2}"
}

#
# Text the account controls (log/*.txt, the names in its tree) reaches the
# root cnf, the per-child include root sources and sed scripts root runs
# only in the form these accept, or quoted by them.
#
# True when $1 is a host name in the form the install takes one: lower-case
# letters, digits, dots and hyphens, starting and ending with a letter or a
# digit.
_satellite_host_ok() {
  [[ "${1}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]
}
# True when $1 names none of the box's own certificates in /etc/ssl/private
# (a name without a dot, such as nginx-wild-ssl or ssl-cert-snakeoil; every
# account front is a full domain name), not the master's front and not the
# front (_DOMAIN) of another account on this box: an account's front names
# root's /etc/ssl/private/<front>.crt and .key and its proxy vhost.
_satellite_front_free() {
  local _c _u _d
  case "${1}" in
    *.*) ;;
    *) return 1 ;;
  esac
  _d=$(sed -n 's/^_MY_FRONT=//p' /root/.barracuda.cnf 2> /dev/null \
    | tail -n 1 | tr -d "\"' ")
  [ "${_d}" = "${1}" ] && return 1
  _d=$(grep -E "^[[:space:]]*'uri'[[:space:]]*=>" \
    /var/aegir/.drush/hostmaster.alias.drushrc.php 2> /dev/null \
    | head -n 1 | cut -d"'" -f4)
  [ "${_d}" = "${1}" ] && return 1
  for _c in /root/.*.octopus.cnf; do
    [ -f "${_c}" ] || continue
    _u="${_c#/root/.}"
    _u="${_u%.octopus.cnf}"
    [ "${_u}" = "${_USER}" ] && continue
    [ -d "/data/disk/${_u}" ] || continue
    _d=$(sed -n 's/^_DOMAIN=//p' "${_c}" 2> /dev/null \
      | tail -n 1 | tr -d "\"' ")
    [ "${_d}" = "${1}" ] && return 1
  done
  return 0
}
# True when $1 is one e-mail address, or several separated by single
# spaces, each in a plain form: a local part of letters, digits and
# . _ % + = ' - (a letter, a digit or _ first), '@' and a host name. The
# form holds no double quote, $, backquote, backslash, '/', '&' or line
# break.
_satellite_email_ok() {
  local _q="'" _w _re
  _w="[A-Za-z0-9_][A-Za-z0-9._%+=${_q}-]*@[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?"
  _re="^${_w}( ${_w})*$"
  [[ "${1}" =~ ${_re} ]]
}
# $1 without the blanks around it; nothing for text over 1024 characters,
# longer than any value read this way, so the caller keeps its own value
# (the cost of these trims grows with the square of the length).
_satellite_trim() {
  local _t="${1}"
  [ "${#_t}" -le 1024 ] || return 0
  _t="${_t#"${_t%%[![:space:]]*}"}"
  printf '%s' "${_t%"${_t##*[![:space:]]}"}"
}
# The account's password file $2 in the real directory $1, read bounded and
# joined into one line as echo joined it, never expanded as a file name
# pattern; nothing for text over 256 characters (the generators make 128 at
# most).
_satellite_pass_read() (
  local _v
  _v="$(_acct_read_in "${1}" "${2}")"
  [ "${#_v}" -le 256 ] || exit 0
  set -f
  # shellcheck disable=SC2086
  echo -n ${_v}
)
# The account's log/$1, read bounded, blanks around it dropped, put in the
# variable $2 when the whole of it matches the extended regular expression
# $3; any other text leaves $2 as the root cnf set it.
_satellite_log_value() {
  local _v
  _v="$(_satellite_trim "$(_acct_read_in "${_ROOT}/log" "${1}")")"
  if [[ "${_v}" =~ ${3} ]]; then
    printf -v "${2}" '%s' "${_v}"
  else
    _msg "NOTE: ${_ROOT}/log/${1} ignored, ${2} kept as set in ${_octCnf}"
  fi
}
# $1 made literal for the replacement of a sed s/// command: each '\', '/'
# and '&' escaped and line breaks dropped, so no text can end the command
# or add to it.
_satellite_sed_rep() {
  local _v
  _v=${1//$'\n'/}
  # shellcheck disable=SC1003
  _v=${_v//\\/'\\'}
  _v=${_v//\//'\/'}
  _v=${_v//&/'\&'}
  printf '%s' "${_v}"
}
# export $1="the value of $1" appended to the include being written
# (_writeTo), the value quoted for the shell (printf %q), so no text can end
# its quotes.
_satellite_inc_put() {
  printf 'export %s=%q\n' "${1}" "${!1}" >> "${_writeTo}"
}

#
# One PHP version in the text of fpm.info or cli.info, dotted (8.4) or
# two-digit (84, as the ltd worker also reads it), printed dotted; nothing for
# any other text, and nothing for text over 64 characters, before any
# pattern substitution (its cost grows with the square of the length).
_satellite_php_vrn() {
  [ "${#1}" -le 64 ] || return 0
  local _t="${1//[^0-9.]/}" _d="${1//[^0-9]/}"
  case "${_t}" in
    [0-9].[0-9]|[0-9][0-9]) ;;
    *) return 0 ;;
  esac
  case "${_d}" in
    56|70|71|72|73|74|80|81|82|83|84|85) echo "${_d:0:1}.${_d:1:1}" ;;
  esac
}

_satellite_check_php_compatibility() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_check_php_compatibility"
    _debug_proc
  fi
  # Only a pin to PHP older than 5.6 stops the upgrade. Any other text, a
  # two-digit version or a file that holds no version, is not a reason to
  # refuse: the reads below ignore what is not one version (text over 64
  # characters included, before any pattern substitution).
  _PHP_FPM_LEGACY_FREE=YES
  if [ -e "${_ROOT}/static/control/fpm.info" ]; then
    _T_FPM_VRN=$(_acct_read_in "${_ROOT}/static/control" fpm.info)
    [ "${#_T_FPM_VRN}" -le 64 ] || _T_FPM_VRN=""
    _T_FPM_VRN=${_T_FPM_VRN//[^0-9.]/}
    case "${_T_FPM_VRN}" in
      5.2|5.3|5.4|5.5|52|53|54|55) _PHP_FPM_LEGACY_FREE=NO ;;
    esac
  fi
  _PHP_CLI_LEGACY_FREE=YES
  if [ -e "${_ROOT}/static/control/cli.info" ]; then
    _T_CLI_VRN=$(_acct_read_in "${_ROOT}/static/control" cli.info)
    [ "${#_T_CLI_VRN}" -le 64 ] || _T_CLI_VRN=""
    _T_CLI_VRN=${_T_CLI_VRN//[^0-9.]/}
    case "${_T_CLI_VRN}" in
      5.2|5.3|5.4|5.5|52|53|54|55) _PHP_CLI_LEGACY_FREE=NO ;;
    esac
  fi
  if [ "${_PHP_CLI_LEGACY_FREE}" = "YES" ] \
    && [ "${_PHP_FPM_LEGACY_FREE}" = "YES" ]; then
    _PHP_LEGACY_FREE=YES
  else
    _PHP_LEGACY_FREE=NO
  fi
  if [ "${_PHP_LEGACY_FREE}" = "NO" ]; then
    _msg "ERROR: This instance ${_USER} still depends on the old PHP version"
    _msg "FPM.${_T_FPM_VRN} CLI.${_T_CLI_VRN}"
    _msg "It is not possible to upgrade it to ${_X_VERSION}"
    _msg "Please switch FPM and CLI on ${_USER} to PHP 5.6 or newer"
    _msg "Then please run the octopus upgrade again"
    _msg "Bye"
    _clean_pid_exit
  fi
}

_satellite_check_octopus_vs_barracuda_ver() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_check_octopus_vs_barracuda_ver"
    _debug_proc
  fi
  if [ ! -f "/var/log/barracuda_log.txt" ]; then
    _msg "ERROR: This octopus installer can be used only when the same version"
    _msg "of boa or barracuda installer was used before. Your system must be"
    _msg "upgraded with barracuda installer version ${_rLsn} first!"
    _msg "Bye"
    _clean_pid_exit _satellite_check_octopus_vs_barracuda_ver_a
  else
    _VERSIONS_TEST=$(cat /var/log/barracuda_log.txt 2>&1)
    if [[ "${_VERSIONS_TEST}" =~ "Barracuda ${_rLsn}-" ]]; then
      _VERSIONS_TEST_RESULT=OK
    else
      _msg "ERROR: This octopus installer can be used only when the same version"
      _msg "of boa or barracuda installer was used before. Your system must be"
      _msg "upgraded with barracuda installer version ${_rLsn} first!"
      _msg "Bye"
      _clean_pid_exit _satellite_check_octopus_vs_barracuda_ver_b
    fi
  fi
  if [ -e "${_ROOT}/log/octopus_log.txt" ]; then
    ### tools/ and log/ are the instance user's: the key is put as a fresh
    ### file and the log read bounded (its newest lines), both inside the
    ### real directories, never through a link or a FIFO put there.
    if [ -e "/var/aegir/key/barracuda_key.txt" ] \
      && [ ! -e "${_ROOT}/tools/key/octopus_key.txt" ]; then
      _acct_in_real_dir "${_ROOT}/tools" mkdir -p ./key
      _acct_in_real_dir "${_ROOT}/tools/key" _satellite_put_stdin_here \
        octopus_key.txt 0644 "" < /var/aegir/key/barracuda_key.txt
    fi
    _SERIES_TEST=$(_acct_in_real_dir "${_ROOT}/log" \
      _satellite_read_tail_here octopus_log.txt)
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _VERSIONS_TEST_RESULT=OK
    else
      _msg "ERROR: This octopus installer can be used only when the instance"
      _msg "has been already upgraded to BOA-4.x or BOA-5.x release"
      _msg "Please run 'octopus up-lts/pro/dev ${_USER} force' upgrade first!"
      _msg "Display all supported commands with: octopus help"
      _msg "Bye"
      _clean_pid_exit _satellite_check_octopus_vs_barracuda_ver_c
    fi
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _SERIES_RESULT=OK
    fi
  fi
  if [ -e "${_ROOT}/log/octopus_log.txt" ] \
    && [ "${_tRee}" = "lts" ]; then
    _SERIES_TEST=$(_acct_in_real_dir "${_ROOT}/log" \
      _satellite_read_tail_here octopus_log.txt)
    if [[ "${_SERIES_TEST}" =~ "Octopus ${_rLsn}-pro" ]]; then
      _msg "ERROR: Your Octopus has been already upgraded to ${_rLsn}-pro"
      _msg "You can not downgrade back to previous/older/lts BOA version"
      _msg "Please use 'octopus up-pro ${_USER} force' to upgrade"
      _msg "Display all supported commands with: octopus help"
      _msg "Bye"
      _clean_pid_exit _satellite_check_octopus_vs_barracuda_ver_d
    fi
  fi
  rm -f /opt/tmp/testecho*
}

# The stamp read from log/domain.txt (the account's file) kept only as a
# host name naming nothing the box or another account uses
# (_satellite_front_free), surrounding blanks dropped; any other text counts
# as no stamp, which the guard below heals from the root cnf or refuses.
_satellite_domain_stamp_form() {
  local _t
  _t="$(_satellite_trim "${_DOMAIN}")"
  if _satellite_host_ok "${_t}" && _satellite_front_free "${_t}"; then
    _DOMAIN="${_t}"
  elif [ -n "${_DOMAIN}" ]; then
    _msg "NOTE: ${_ROOT}/log/domain.txt is not a host name this account may use; ignored"
    _DOMAIN=""
  fi
}

_satellite_domain_stamp_guard() {
  ### The upgrade re-reads _DOMAIN from <root>/log/domain.txt, and a stale
  ### stamp silently mis-targets destructive steps: the previous-install
  ### test then declares the healthy platform a zombie and moves it to
  ### backups/system before a rebuild that cannot bootstrap. Never trust
  ### the single file — same doctrine as the /root/.my.cnf vs
  ### /root/.my.pass.txt root-SQL cross-check: converge the witnesses to
  ### one enforced truth before any upgrade step runs. The on-disk
  ### hostmaster site (distro/NNN/sites/<domain>/settings.php) is the
  ### primary arbiter when unambiguous: BOTH the stamp and the octopus cnf
  ### _DOMAIN converge to it. Without an on-disk arbiter the two files
  ### must agree; a disagreement aborts while nothing has been modified.
  ### The cnf is parsed last-assignment-wins (source semantics) and healed
  ### by replace-then-append so re-runs stay single-line idempotent.
  ### Hostname-derived values are NOT a witness: custom satellite fronts
  ### are legitimate and live only in these files.
  local _cnfDom=""
  local _realDom=""
  local _realNr=0
  local _octCnfG="/root/.${_USER}.octopus.cnf"
  local _p _d
  if [ -e "${_octCnfG}" ]; then
    _cnfDom=$(grep "^_DOMAIN=" ${_octCnfG} 2>/dev/null \
      | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "\n")
  fi
  for _p in "${_ROOT}"/aegir/distro/[0-9]*/sites/*/settings.php; do
    [ -e "${_p}" ] || continue
    _d="${_p%/settings.php}"
    _d="${_d##*/}"
    case "${_d}" in
      all|default) continue ;;
    esac
    ### a directory name in the account's own tree, written to the root
    ### cnf: an arbiter only in the form of a host name that names nothing
    ### the box or another account uses
    _satellite_host_ok "${_d}" && _satellite_front_free "${_d}" || continue
    if [ -z "${_realDom}" ]; then
      _realDom="${_d}"
      _realNr=1
    elif [ "${_d}" != "${_realDom}" ]; then
      _realNr=2
    fi
  done
  if [ "${_realNr}" = "1" ] && [ -n "${_realDom}" ]; then
    if [ "${_DOMAIN}" != "${_realDom}" ]; then
      if [ -n "${_DOMAIN}" ]; then
        _msg "NOTE: log/domain.txt (${_DOMAIN}) does not match the on-disk"
        _msg "NOTE: hostmaster site (${_realDom}) — converging the stamp"
      fi
      _DOMAIN="${_realDom}"
      ### a fresh file in the real log/ handed to the instance user, never
      ### written or handed over through a link put at the name
      _acct_in_real_dir "${_ROOT}/log" _acct_pin_here domain.txt \
        "${_DOMAIN}" "${_USER}:${_ACCG:-users}" &> /dev/null
    fi
    if [ -e "${_octCnfG}" ] && [ "${_cnfDom}" != "${_realDom}" ]; then
      if [ -n "${_cnfDom}" ]; then
        _msg "NOTE: ${_octCnfG} _DOMAIN (${_cnfDom}) does not match the"
        _msg "NOTE: on-disk hostmaster site (${_realDom}) — converging"
      fi
      sed -i "/^_DOMAIN=/d" ${_octCnfG}
      echo "_DOMAIN=\"${_realDom}\"" >> ${_octCnfG}
    fi
  else
    if [ -n "${_cnfDom}" ] && [ -n "${_DOMAIN}" ]; then
      if [ "${_cnfDom}" != "${_DOMAIN}" ]; then
        _msg "FATAL ERROR: Octopus identity mismatch for ${_USER}"
        _msg "FATAL ERROR: ${_ROOT}/log/domain.txt says: ${_DOMAIN}"
        _msg "FATAL ERROR: ${_octCnfG} _DOMAIN says: ${_cnfDom}"
        _msg "FATAL ERROR: and the on-disk platform cannot arbitrate"
        _msg "FATAL ERROR: (settings.php for neither or several). Fix the"
        _msg "FATAL ERROR: stale side before re-running the upgrade; a"
        _msg "FATAL ERROR: hostname rename must update both (current"
        _msg "FATAL ERROR: renameaegirhost does). Nothing was modified."
        _clean_pid_exit _satellite_domain_stamp_guard
      fi
    elif [ -n "${_cnfDom}" ] && [ -z "${_DOMAIN}" ]; then
      _DOMAIN="${_cnfDom}"
      _acct_in_real_dir "${_ROOT}/log" _acct_pin_here domain.txt \
        "${_DOMAIN}" "${_USER}:${_ACCG:-users}" &> /dev/null
      _msg "NOTE: empty log/domain.txt healed from ${_octCnfG}: ${_DOMAIN}"
    elif [ -z "${_cnfDom}" ] && [ -n "${_DOMAIN}" ] && [ -e "${_octCnfG}" ]; then
      ### No arbiter and no cnf witness: proceed on the stamp but never
      ### launder the unverified value into the cnf.
      _msg "NOTE: ${_octCnfG} carries no _DOMAIN line; proceeding on the"
      _msg "NOTE: stamp ${_DOMAIN} (no on-disk hostmaster site to verify)"
    fi
  fi
}

_satellite_if_init_or_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_init_or_upgrade"
    _debug_proc
  fi
  if [ -d "${_ROOT}" ]; then
    _msg "Octopus Satellite Instance Upgrade in progress..."
    if [ -d "${_ROOT}/distro" ]; then
      ### log/ is the instance user's: its files are read bounded, never
      ### through a link or from a FIFO, and written as fresh files inside
      ### the real directory.
      if [ -e "${_ROOT}/log/domain.txt" ]; then
        _DOMAIN=$(_acct_read_in "${_ROOT}/log" domain.txt | tr -d '\n')
        _satellite_domain_stamp_form
      fi
      _satellite_domain_stamp_guard
      if [ -z "${_DOMAIN}" ]; then
        _msg "ALERT! _DOMAIN is e-m-p-t-y, exit now"
        _clean_pid_exit _satellite_if_init_or_upgrade_a
      fi
      if [ -z "${_USER}" ]; then
        _msg "ALERT! _USER is e-m-p-t-y, exit now"
        _clean_pid_exit _satellite_if_init_or_upgrade_b
      fi
      _if_hosted_sys
      if [ "${_hostedSys}" = "YES" ]; then
        if [ -e "${_ROOT}/log/amazing_upgrade.txt" ] \
          && [ ! -e "${_ROOT}/log/amazing_upgrade_complete.txt" ]; then
          if [ -e "${_ROOT}/log/original_option.txt" ]; then
            _acct_in_real_dir "${_ROOT}/log" _satellite_copy_here \
              option.txt prev_option.txt
            _acct_in_real_dir "${_ROOT}/log" _satellite_copy_here \
              original_option.txt option.txt
          fi
          if [ -e "${_ROOT}/log/original_cores.txt" ]; then
            _acct_in_real_dir "${_ROOT}/log" _satellite_copy_here \
              cores.txt prev_cores.txt
            _acct_in_real_dir "${_ROOT}/log" _satellite_copy_here \
              original_cores.txt cores.txt
          fi
          _acct_put_in "${_ROOT}/log" amazing_upgrade_complete.txt completed
        fi
      fi
      ### Each value is taken in its own form only (the option and the plan
      ### one word, the cores digits, the e-mail plain addresses, one or
      ### several, as the nightly takes them); other text leaves the value
      ### the root cnf gives.
      if [ -e "${_ROOT}/log/option.txt" ]; then
        _satellite_log_value option.txt _CLIENT_OPTION '^[A-Za-z0-9_]+$'
      fi
      if [ -e "${_ROOT}/log/cores.txt" ]; then
        _satellite_log_value cores.txt _CLIENT_CORES '^[0-9]+$'
      fi
      if [ -e "${_ROOT}/log/subscr.txt" ]; then
        _satellite_log_value subscr.txt _CLIENT_SUBSCR '^[A-Za-z0-9_]+$'
      fi
      if [ -e "${_ROOT}/log/email.txt" ]; then
        _T_EML="$(_satellite_trim "$(_acct_read_in "${_ROOT}/log" email.txt \
          | tr -s '[:space:]' ' ')")"
        _T_EML=${_T_EML//\\\@/\@}
        if _satellite_email_ok "${_T_EML}"; then
          _CLIENT_EMAIL="${_T_EML}"
        else
          _msg "NOTE: ${_ROOT}/log/email.txt ignored, _CLIENT_EMAIL kept as set in ${_octCnf}"
        fi
        if [[ "${_CLIENT_EMAIL}" =~ "@" ]]; then
          _DO_NOTHING=YES
        else
          _msg "EXIT: You must enter your valid email address in the"
          _msg "EXIT: _CLIENT_EMAIL variable written both in the"
          _msg "EXIT: ${_octCnf} file and in the"
          _msg "EXIT: ${_ROOT}/log/email.txt file"
          _msg "EXIT: Bye (1)"
          _clean_pid_exit _satellite_if_init_or_upgrade_c
        fi
        _CLIENT_EMAIL=${_CLIENT_EMAIL//\\\@/\@}
      fi
      if [[ "${_CLIENT_EMAIL}" =~ "omega8.cc" ]]; then
        _if_hosted_sys
        if [ "${_hostedSys}" != "YES" ]; then
          _msg "EXIT: You must enter your valid email address in the"
          _msg "EXIT: _CLIENT_EMAIL variable written both in the"
          _msg "EXIT: ${_octCnf} file and in the"
          _msg "EXIT: ${_ROOT}/log/email.txt file"
          _msg "EXIT: Bye (2)"
          _clean_pid_exit _satellite_if_init_or_upgrade_d
        fi
      fi
      #
      # Check for _last distro nr
      if [ -d "${_ROOT}/distro" ]; then
        cd ${_ROOT}/distro
        _list=([0-9]*)
        _last=${_list[@]: -1}
        _LASTNUM=$_last
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          _nextnum=00$((10#0${_last%%[^0-9]*} + 1))
        else
          _nextnum=00$((10#${_last%%[^0-9]*} + 1))
        fi
        _nextnum=${_nextnum: -3}
        _DISTRO=${_nextnum}
      fi
      #
      # Check for _last hm nr
      if [ -d "${_ROOT}/aegir/distro" ]; then
        cd ${_ROOT}/aegir/distro
        _listx=([0-9]*)
        _lastx=${_listx[@]: -1}
        _LAST_HMR=$_lastx
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          _nextnumx=00$((10#0${_lastx%%[^0-9]*} + 1))
        else
          _nextnumx=00$((10#${_lastx%%[^0-9]*} + 1))
        fi
        _nextnumx=${_nextnumx: -3}
        _HM_DISTRO=${_nextnumx}
      fi
      #
      # Check for _last all nr
      if [ -d "/data/all" ]; then
        cd /data/all
        _listl=([0-9]*)
        _lastl=${_listl[@]: -1}
        export _LAST_ALL=${_lastl}
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          _nextnuml=00$((10#0${_lastl%%[^0-9]*} + 1))
        else
          _nextnuml=00$((10#${_lastl%%[^0-9]*} + 1))
        fi
        _nextnuml=${_nextnuml: -3}
        export _ALL_DISTRO=${_nextnuml}
      fi
    #
    #
    elif [ ! -d "${_ROOT}/distro" ]; then
      if [ -e "${_ROOT}/log/domain.txt" ]; then
        _DOMAIN=$(_acct_read_in "${_ROOT}/log" domain.txt | tr -d '\n')
        _satellite_domain_stamp_form
      fi
      _satellite_domain_stamp_guard
    fi
  else
    _msg "New Octopus Setup on ${_hName} in progress..."
    #
    # Check for last all nr
    if [ -d "/data/all" ]; then
      cd /data/all
      _listl=([0-9]*)
      _lastl=${_listl[@]: -1}
      export _LAST_ALL=${_lastl}
      _BASH_TEST=$(bash --version 2>&1)
      if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
        _nextnuml=00$((10#0${_lastl%%[^0-9]*} + 1))
      else
        _nextnuml=00$((10#${_lastl%%[^0-9]*} + 1))
      fi
      _nextnuml=${_nextnuml: -3}
      export _ALL_DISTRO=${_nextnuml}
    fi
  fi
}

_satellite_if_major_upgrade() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_major_upgrade"
    _debug_proc
  fi
  if [ "${_CLIENT_OPTION}" = "POWER" ] \
    && [ -e "${_ROOT}/log/octopus_log.txt" ]; then
    _SERIES_TEST=$(_acct_in_real_dir "${_ROOT}/log" \
      _satellite_read_tail_here octopus_log.txt)
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _IT_IS_OK=YES
    else
      if [ ! -e "${_ROOT}/log/_satellite_major_upgrade_ok.txt" ]; then
        _msg "ERROR: Major version upgrade requires control file:"
        _msg "${_ROOT}/log/_satellite_major_upgrade_ok.txt"
        _msg "Bye"
        _clean_pid_exit _satellite_if_major_upgrade_a
      fi
    fi
  fi
  if [ "${_CLIENT_OPTION}" = "CLUSTER" ] \
    && [ -e "${_ROOT}/log/octopus_log.txt" ]; then
    _SERIES_TEST=$(_acct_in_real_dir "${_ROOT}/log" \
      _satellite_read_tail_here octopus_log.txt)
    if [[ "${_SERIES_TEST}" =~ "BOA-5." ]] \
      || [[ "${_SERIES_TEST}" =~ "BOA-4." ]]; then
      _IT_IS_OK=YES
    else
      if [ ! -e "${_ROOT}/log/_satellite_major_upgrade_ok.txt" ]; then
        _msg "ERROR: Major version upgrade requires control file:"
        _msg "${_ROOT}/log/_satellite_major_upgrade_ok.txt"
        _msg "Bye"
        _clean_pid_exit _satellite_if_major_upgrade_b
      fi
    fi
  fi
}

_satellite_if_check_dns() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_if_check_dns"
    _debug_proc
  fi
  if [ "${_DNS_SETUP_TEST}" = "YES" ]; then
    if [ "${_VMFAMILY}" = "AWS" ]; then
      _LOC_DOM="${_DOMAIN}"
      if [ -z "${_MY_OWNIP}" ]; then
        _find_correct_ip
        _MY_OWNIP="${_LOC_IP}"
      else
        _LOC_IP="${_MY_OWNIP}"
      fi
    fi
    if [ -z "${_MY_OWNIP}" ]; then
      _find_correct_ip
      _THISHTIP="${_LOC_IP}"
    else
      _THISHTIP="${_MY_OWNIP}"
    fi
    _LOC_DOM="${_DOMAIN}"
    _find_correct_ip
    _THISRDIP="${_LOC_IP}"
    if [ "${_THISRDIP}" = "${_THISHTIP}" ]; then
      _DO_NOTHING=YES
    else
      _msg "ERROR: ${_DOMAIN} doesn't point to your IP: ${_THISHTIP}"
      _msg "Please make sure you have a valid A record in your DNS"
      _msg "It is also possible that DNS change didn't propagate yet"
      _msg "Bye"
      _clean_pid_exit _satellite_if_check_dns_a
    fi
  else
    if [ -z "${_MY_OWNIP}" ]; then
      _LOC_DOM="${_DOMAIN}"
      _find_correct_ip
      _THISHTIP="${_LOC_IP}"
      _THISRDIP="${_LOC_IP}"
    else
      _THISHTIP="${_MY_OWNIP}"
      _THISRDIP="${_MY_OWNIP}"
    fi
  fi
}

_satellite_checkpoint() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_checkpoint"
    _debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    echo " "
    _msg "START -> checkpoint: "
  fi

  export _OS_DIST=$(lsb_release -ar 2>/dev/null | grep -i distributor | cut -s -f2)
  export _OS_CODE=$(lsb_release -ar 2>/dev/null | grep -i codename | cut -s -f2)

  if [ "${_STATUS}" = "INIT" ]; then
    _modeDetect="installation"
    _optInf="${_CLIENT_OPTION} / ${_CLIENT_SUBSCR} / ${_CLIENT_CORES} C"
    cat <<EOF

    * Your email address is ${_MY_OCTO_EMAIL}
    * Your client email address is ${_CLIENT_EMAIL}
    * Your Ægir control panel for this instance will be available at:
        https://${_DOMAIN}
    * Your Ægir system user for this instance will be ${_USER}
    * This Octopus will use PHP-CLI ${_PHP_CLI_VERSION} for all sites
    * This Octopus will use PHP-FPM ${_PHP_FPM_VERSION} for all sites
    * This Octopus includes platforms: ${_PLATFORMS_LIST}
    * This Octopus options are listed as ${_optInf}

EOF
  else
    _modeDetect="upgrade"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _optInf="${_CLIENT_OPTION} / ${_CLIENT_SUBSCR} / ${_CLIENT_CORES} C"
      cat <<EOF

    * Your Ægir control panel for this instance is available at:
        https://${_DOMAIN}
    * Your Ægir system user for this instance is ${_USER}
    * This Octopus will use PHP-CLI ${_PHP_CLI_VERSION} for all sites
    * This Octopus will use PHP-FPM ${_PHP_FPM_VERSION} for all sites
    * This Octopus includes platforms: ${_PLATFORMS_LIST}
    * This Octopus options are listed as ${_optInf}

EOF
    else
      echo " "
      _thiSys="${_OS_DIST}/${_OS_CODE}"
      _msg "This Octopus System is ${_thiSys}"
      _msg "This Octopus PHP FPM/CLI version is ${_PHP_FPM_VERSION}/${_PHP_CLI_VERSION}"
      _msg "This Octopus URL address is ${_DOMAIN}"
      echo " "
    fi
  fi

  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "8s before we will continue..."
    export _DEBUG_MODE="${_DEBUG_MODE}"
    if [ ! -z "${_USE_MIR}" ]; then
      export _USE_MIR="${_USE_MIR}"
    fi
  fi
  sleep 8
}

_satellite_pre_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_pre_cleanup"
    _debug_proc
  fi
  rm -f /tmp/cache.inc*
  rm -f /opt/tmp/status-*
  # Only this instance's own signal dir. /opt/tmp/state/<user> is per-instance
  # (0700, instance-owned) and the master keeps its own state/aegir, so purging
  # the whole state root here destroys the markers of any other run in flight:
  # that run finishes its work but cannot stamp status-AegirSetupA-OK and dies
  # with a phantom FATAL. An empty _USER would resolve to the state root itself,
  # so skip rather than widen.
  if [ -n "${_USER}" ]; then
    rm -rf "/opt/tmp/state/${_USER}"
    # Root's own marker dir for this instance (AegirSetupA OK/FAIL) -- same
    # per-run purge, same scoping.
    rm -rf "/opt/tmp/state/.root/${_USER}"
  fi
  rm -rf /tmp/drush_make_tmp*
  rm -rf /tmp/make_tmp*
  rm -f /tmp/pm-updatecode*
  if [ -d "/home/${_USER}.ftp/" ]; then
    _disable_chattr ${_USER}.ftp
  fi
}

### Run inside the real vhost.d: each regular file there whose name is a
### host name other than $1 (the hostmaster's), read as _acct_read_here
### reads it, that declares the db_* set without the nginx db variables,
### printed as "<name>", for the PHP array below. The name becomes a PHP
### string literal: a vhost file is named by the site's URI, so anything
### outside the hostname alphabet is not a site of ours.
_satellite_dbvars_list_here() {
  local _v _d _t
  for _v in ./*; do
    [ -f "${_v}" ] && [ ! -L "${_v}" ] || continue
    _d="${_v#./}"
    case "${_d}" in .*|https.*) continue ;; esac
    [ "${_d}" = "${1}" ] && continue
    case "${_d}" in *[!A-Za-z0-9.-]*) continue ;; esac
    _t="$(_acct_read_here "${_d}")"
    case "${_t}" in *'set $boa_db_type'*) continue ;; esac
    case "${_t}" in *'fastcgi_param db_type'*) ;; *) continue ;; esac
    printf '"%s",' "${_d}"
  done
}

### The shared nginx include now takes the site's database credentials
### through variables the site vhost sets after the include line; a vhost
### rendered before that keeps passing EMPTY credentials to the locations
### that declare their own fastcgi_param set (/cron/<key>, update.php,
### authorize.php), and on a cloaked site those requests reach PHP with no
### database at all. A site vhost is re-rendered only by the site's own
### Verify, so queue one for every such site once this pass has rendered the
### include. Self-limiting: a re-rendered vhost carries the lines and is
### never queued again; Grav and TXP vhosts carry no credentials and are
### skipped; the queue runs them one at a time under the runner lock.
### The test for "carries credentials" is the server-level fastcgi_param
### db_* set every Drupal vhost declares (placeholders when the site has no
### database) -- NOT the urlencoded marker, which only a recent render
### carries: a vhost from an older provision holds the credentials without
### it, and that is every site not re-verified since the marker arrived.
_satellite_queue_dbvars_site_verifies() {
  local _inc="${_ROOT}/config/includes/nginx_vhost_common.conf"
  local _vhd="${_ROOT}/config/server_master/nginx/vhost.d"
  local _list="" _n
  ### _DRUSHCMD exists only in the AegirSetup child scripts; this runs in
  ### the launcher's own process, where the instance user's drush8 is on
  ### the login PATH.
  local _hmDrush="${_DRUSHCMD:-drush8}"
  ### config/ is the instance user's: the include and each vhost are read
  ### bounded inside the real directory, never through a link or from a
  ### FIFO put at the name; vhost.d is entered once for all its files.
  [ -f "${_inc}" ] && _acct_read_in "${_inc%/*}" "${_inc##*/}" \
    | grep -q '^set \$boa_db_type' || return 0
  [ -d "${_vhd}" ] || return 0
  _list="$(_acct_in_real_dir "${_vhd}" _satellite_dbvars_list_here "${_DOMAIN}")"
  [ -n "${_list}" ] || return 0
  ### One hostmaster bootstrap for the whole list: a per-site drush call
  ### costs seconds each and a box with hundreds of sites would spend that
  ### inside the upgrade pass. hosting_add_task QUEUES the task (folded per
  ### node); the hosting-task command would run the verify here and now.
  ### Counted only when the frontend returned the task.
  _n=$(su -s /bin/bash - ${_USER} -c "${_hmDrush} @hostmaster php-eval '\$n = 0; foreach (array(${_list}) as \$u) { \$s = hosting_get_site_by_url(\$u); if (\$s && !empty(\$s->nid)) { \$t = hosting_add_task(\$s->nid, \"verify\"); if (is_object(\$t) && !empty(\$t->nid)) { \$n++; } } } print \"queued=\" . \$n;'" 2>/dev/null)
  case "${_n}" in
    *queued=*) ;;
    *) _msg "INFO: the frontend did not answer the db-variables Verify queueing; the next pass retries"
       return 0 ;;
  esac
  _n="${_n##*queued=}"
  _n="${_n%%[^0-9]*}"
  if [ -n "${_n}" ] && [ "${_n}" -gt 0 ]; then
    _msg "INFO: queued a Verify for ${_n} site(s) whose vhost predates the nginx db variables"
  fi
}

_satellite_post_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_post_cleanup"
    _debug_proc
  fi
  if [ -d "/home/${_USER}.ftp/" ]; then
    _enable_chattr ${_USER}.ftp
  fi
  rm -f /tmp/cache.inc*
  rm -rf /var/opt/*
  rm -rf /tmp/drush_make_tmp*
  rm -rf /tmp/make_tmp*
  rm -f /tmp/pm-updatecode*
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  _acct_in_real_dir "${_ROOT}/.tmp" rm -rf -- ./cache
  [ -e "/run/manage_ltd_users.pid" ] && rm -f /run/manage_ltd_users.pid
  [ -e "/run/manage_ruby_users.pid" ] && rm -f /run/manage_ruby_users.pid
}

_satellite_letsencrypt_crt_key_copy() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_letsencrypt_crt_key_copy"
    _debug_proc
  fi
  if [ -e "${_leCrtPath}/fullchain.pem" ]; then
    _crtPath="${_leCrtPath}/fullchain.pem"
  elif [ -e "${_leCrtPath}/cert.pem" ]; then
    _crtPath="${_leCrtPath}/cert.pem"
  fi
  _keyPath="${_leCrtPath}/privkey.pem"
  ### tools/le is the instance user's: the certificate and the key are read
  ### bounded inside the real certs/<domain>/, through a link only to a file
  ### beside it (as the client links each name to a versioned file), and
  ### written as root's own 0600 files, only under the account's own front.
  if [[ ! "${_DOMAIN}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] \
    || ! _satellite_front_free "${_DOMAIN}"; then
    _msg "NOTE: the ${_USER} front is not a host name this account may use; certificate not copied"
    return 0
  fi
  if [ -e "${_crtPath}" ]; then
    _satellite_le_copy "${_crtPath##*/}" "/etc/ssl/private/${_DOMAIN}.crt"
  fi
  if [ -e "${_keyPath}" ]; then
    _satellite_le_copy privkey.pem "/etc/ssl/private/${_DOMAIN}.key"
  fi
}

#
# ./$1 in the current (pinned) certs/<domain>/, or the file beside it its
# link names, read as _acct_read_here reads; nothing for a link that leads
# anywhere else.
_satellite_le_file_here() {
  local _f="${1}" _t
  if [ -L "./${_f}" ]; then
    _t="$(readlink -- "./${_f}")"
    case "${_t}" in
      ""|.|..|*/*) return 1 ;;
    esac
    _f="${_t}"
  fi
  _acct_read_here "${_f}"
}
# The file $1 of the account's certs/<domain>/ (_leCrtPath), read as
# _satellite_le_file_here reads it, put at root's own $2 (0600) as a fresh
# file renamed over the name; $2 stays as it is when nothing is read.
_satellite_le_copy() {
  local _c _t="${2}.put.$$.${RANDOM}"
  _c="$(_acct_in_real_dir "${_leCrtPath}" _satellite_le_file_here "${1}")"
  [ -n "${_c}" ] || return 1
  rm -f -- "${_t}"
  ( umask 077
    printf '%s\n' "${_c}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
    && mv -f -T -- "${_t}" "${2}" && return 0
  rm -f -- "${_t}"
  return 1
}

_satellite_letsencrypt_vhost_sync() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_letsencrypt_vhost_sync"
    _debug_proc
  fi
  [ -e "/root/.ssl.proxy.cnf" ] && rm -f /root/.ssl.proxy.cnf
  _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
  _PHP_CN="www${_PHP_SV}"
  sed -i "s/127.0.0.1:9000;/unix:\/var\/run\/${_PHP_CN}.fpm.socket;/g" ${_Ssl}
  wait
  if [ -e "${_crtPath}" ]; then
    _crtPath=${_crtPath//\//\\\/}
    sed -i "s/ssl_certificate .*/ssl_certificate              ${_crtPath};/g" ${_Ssl}
    wait
  fi
  if [ -e "${_keyPath}" ]; then
    _keyPath=${_keyPath//\//\\\/}
    sed -i "s/ssl_certificate_key .*/ssl_certificate_key          ${_keyPath};/g" ${_Ssl}
    wait
  fi
  _dhpWildPath="/etc/ssl/private/nginx-wild-ssl.dhp"
  if [ -e "/etc/ssl/private/4096.dhp" ]; then
    _dhpPath="/etc/ssl/private/4096.dhp"
    _DIFF_T=$(diff -w -B ${_dhpPath} ${_dhpWildPath} 2>&1)
    if [ ! -z "${_DIFF_T}" ]; then
      cp -af ${_dhpPath} ${_dhpWildPath}
    fi
  elif [ -e "/etc/ssl/private/${_DOMAIN}.dhp" ]; then
    _dhpPath="/etc/ssl/private/${_DOMAIN}.dhp"
  elif [ -e "${_dhpWildPath}" ]; then
    _dhpPath="${_dhpWildPath}"
  fi
  if [ -e "${_dhpPath}" ]; then
    _dhpPath=${_dhpPath//\//\\\/}
    sed -i "s/ssl_dhparam .*/ssl_dhparam                  ${_dhpPath};/g" ${_Ssl}
  else
    sed -i "s/.*ssl_dhparam .*//g" ${_Ssl}
  fi
  ### Mirror xoct's KTLS opt-out strip here, at the tar-delivered layer:
  ### the fetched xoct can lag this lib, and a stale copy would regenerate
  ### the front with KTLS against the opt-out, re-triggering the update
  ### check on every upgrade while nginx keeps serving KTLS.
  [ -e "/etc/nginx/no_ktls.conf" ] \
    && sed -i "/ssl_conf_command Options.*KTLS/d" ${_Ssl}
  ### The control panel front does not offer HTTP/3. A reload hands the
  ### shared UDP sockets to the new workers, so a QUIC transfer in flight
  ### is cut within seconds of every reload, while a TCP one drains on the
  ### old worker. Reloads follow tasks and ban-list updates every few
  ### minutes, so a multi-gigabyte backup download never completed over
  ### HTTP/3. Alt-Svc clear makes a browser drop the alternative it cached
  ### from earlier visits. Same two-layer shape as the KTLS strip above:
  ### the fetched generator can lag this lib.
  sed -i "/^[[:space:]]*listen .*:443 quic;/d; /^[[:space:]]*http3\(_hq\)\?[[:space:]].*on;/d" ${_Ssl}
  if ! grep -q "Alt-Svc" ${_Ssl}; then
    sed -i "s/^\([[:space:]]*\)proxy_buffering[[:space:]].*off;/&\n\1proxy_hide_header          Alt-Svc;\n\1add_header                 Alt-Svc clear always;/" ${_Ssl}
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: Reloading Nginx..."
    _mrun "service nginx reload"
  else
    _mrun "service nginx reload"
  fi
}

_satellite_ssl_proxy_template_refresh() {
  ### xoct ssl-gen renders the panel proxy from /var/xdrago/conf/ssl_proxy.conf,
  ### which only a barracuda pass refreshes. An octopus pass that runs first
  ### would regenerate from the stale template on every pass until then, so take
  ### the template from this pass's own build tree when it carries a marker the
  ### deployed one lacks. The newest marker is enough: each template carries
  ### every older one.
  local _tpl="/var/xdrago/conf/ssl_proxy.conf"
  local _src="${_bldPth}/aegir/tools/system/conf/ssl_proxy.conf"
  grep -q boa_panel_lock "${_tpl}" 2>/dev/null && return 0
  grep -q boa_panel_lock "${_src}" 2>/dev/null || return 0
  mkdir -p /var/xdrago/conf
  cp -af "${_src}" "${_tpl}"
}

_satellite_letsencrypt_vhost_setup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_letsencrypt_vhost_setup"
    _debug_proc
  fi
  _ifvHst="YES"
  _leRoot="${_ROOT}/tools/le"
  _leKeyJ="${_leRoot}/tools/le/private_key.json"
  _leKeyP="${_leRoot}/tools/le/private_key.pem"
  _leCrtPath="${_leRoot}/certs/${_DOMAIN}"
  _exeLe="${_leRoot}/dehydrated"
  _Ssl="/var/aegir/config/server_master/nginx/pre.d/z_${_DOMAIN}_ssl_proxy.conf"
  ### /root/.ssl.proxy.cnf is one line of five blank-separated fields, the
  ### fourth one address: the first of the client addresses goes there.
  if [ -e "${_leRoot}/.ctrl/ssl-demo-mode.pid" ] \
    && [ -e "${_leRoot}/config.sh" ]; then
    if [ -e "${_Ssl}" ]; then
      rm -f ${_Ssl}
      _ifvHst="NO"
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "${_STATUS} A: Reloading Nginx..."
        _mrun "service nginx reload"
      else
        _mrun "service nginx reload"
      fi
    fi
  fi
  if [ "${_ifvHst}" = "YES" ]; then
    if [ -e "${_leCrtPath}/fullchain.pem" ] \
      || [ -e "${_leCrtPath}/cert.pem" ]; then
      if [ -e "${_Ssl}" ]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          _msg "${_STATUS} A: pre.d/z_${_DOMAIN}_ssl_proxy.conf exists, OK!"
        fi
        _satellite_letsencrypt_crt_key_copy
        ### The panel front carries no QUIC listener and clears Alt-Svc
        ### (see _satellite_letsencrypt_vhost_sync); either one missing
        ### marks a front written before that and needing one regen.
        _HTTP3_TEST=$(grep -E "^[[:space:]]*(listen .* quic;|http3)" ${_Ssl} 2>&1)
        _ALTSVC_TEST=$(grep "Alt-Svc clear" ${_Ssl} 2>&1)
        _KTLS_TEST=$(grep KTLS ${_Ssl} 2>&1)
        _RPRT_TEST=$(grep reuseport ${_Ssl} 2>&1)
        _SQLADMIN_TEST=$(grep sqladmin ${_Ssl} 2>&1)
        ### The /sqladmin crawler drop and css allow-list arrived together,
        ### so their absence marks a pre-hardening vhost needing one regen.
        _SQLADMCRWL_TEST=$(grep is_crawler ${_Ssl} 2>&1)
        _HTTPVER_TEST=$(grep proxy_http_version ${_Ssl} 2>&1)
        ### The loopback-only path refusal (FPM status and ping, cron, stub
        ### status) arrived later; a front without it proxies those paths to
        ### the panel vhost from the box's own address, which admits them.
        _PANELLOCAL_TEST=$(grep boa_panel_local ${_Ssl} 2>&1)
        ### The IDS ban and the panel's own IP lists came after that; without
        ### them the panel vhost judges this proxy's address, which the lists
        ### always admit, so a locked panel answered anyone over HTTPS.
        _PANELLOCK_TEST=$(grep boa_panel_lock ${_Ssl} 2>&1)
        _PHP_SV=${_PHP_FPM_VERSION//[^0-9]/}
        _PHP_CN="www${_PHP_SV}"
        _FPM_SOCKET_VAR=$(grep "unix:/var/run/${_PHP_CN}.fpm.socket" ${_Ssl} 2>&1)
        _FPM_SOCKET_RUN=$(grep "unix:/run/${_PHP_CN}.fpm.socket" ${_Ssl} 2>&1)
        if [[ "${_FPM_SOCKET_VAR}" =~ "fpm.socket" ]] \
          || [[ "${_FPM_SOCKET_RUN}" =~ "fpm.socket" ]]; then
          _FPM_SOCKET_TEST="fpm.socket"
        fi
        ### KTLS opt-out aware: demand KTLS present only when the control file
        ### is absent; when _NGINX_KTLS=NO set it, demand KTLS absent instead,
        ### so the per-domain front is not regenerated in an endless loop.
        _KTLS_NEEDS_UPDATE=NO
        if [ -e "/etc/nginx/no_ktls.conf" ]; then
          [[ "${_KTLS_TEST}" =~ "KTLS" ]] && _KTLS_NEEDS_UPDATE=YES
        else
          [[ ! "${_KTLS_TEST}" =~ "KTLS" ]] && _KTLS_NEEDS_UPDATE=YES
        fi
        if [[ ! "${_FPM_SOCKET_TEST}" =~ "fpm.socket" ]] \
          || [[ "${_HTTP3_TEST}" =~ (quic|http3) ]] \
          || [[ ! "${_ALTSVC_TEST}" =~ "Alt-Svc" ]] \
          || [ "${_KTLS_NEEDS_UPDATE}" = "YES" ] \
          || [[ "${_RPRT_TEST}" =~ "reuseport" ]] \
          || [[ ! "${_SQLADMIN_TEST}" =~ "sqladmin" ]] \
          || [[ ! "${_SQLADMCRWL_TEST}" =~ "is_crawler" ]] \
          || [[ ! "${_HTTPVER_TEST}" =~ "proxy_http_version" ]] \
          || [[ ! "${_PANELLOCAL_TEST}" =~ "boa_panel_local" ]] \
          || [[ ! "${_PANELLOCK_TEST}" =~ "boa_panel_lock" ]]; then
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            _msg "${_STATUS} A: pre.d/z_${_DOMAIN}_ssl_proxy.conf needs update..."
          fi
          _satellite_ssl_proxy_template_refresh
          echo "${_DOMAIN} ${_THISHTIP} ${_USER} ${_CLIENT_EMAIL%% *} ${_THISHTIP}" > /root/.ssl.proxy.cnf
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            bash /opt/local/bin/xoct ssl-gen
            wait
          else
            _mrun "bash /opt/local/bin/xoct ssl-gen"
            wait
          fi
          if [ -e "${_Ssl}" ]; then
            _satellite_letsencrypt_vhost_sync
          else
            _msg "${_STATUS} A: pre.d/z_${_DOMAIN}_ssl_proxy.conf doesn't exist!"
          fi
        fi
      else
        _msg "${_STATUS} A: Creating LE vhost for Hostmaster, please wait..."
        _satellite_letsencrypt_crt_key_copy
        _satellite_ssl_proxy_template_refresh
        echo "${_DOMAIN} ${_THISHTIP} ${_USER} ${_CLIENT_EMAIL%% *} ${_THISHTIP}" > /root/.ssl.proxy.cnf
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          bash /opt/local/bin/xoct ssl-gen
          wait
        else
          _mrun "bash /opt/local/bin/xoct ssl-gen"
          wait
        fi
        if [ -e "${_Ssl}" ]; then
          _satellite_letsencrypt_vhost_sync
        else
          _msg "${_STATUS} A: pre.d/z_${_DOMAIN}_ssl_proxy.conf doesn't exist!"
        fi
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "${_STATUS} A: le/certs/${_DOMAIN}/fullchain.pem doesn't exist!"
      fi
    fi
  fi
}

_satellite_log_update() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_log_update"
    _debug_proc
  fi
  ### log/ is the instance user's: the stamps are put as fresh files and
  ### the entry appended only to a regular octopus_log.txt, inside the real
  ### directory, never through a link or a FIFO put at a name (one space
  ### between words, as the unquoted echo wrote the date).
  if [ "${_STATUS}" = "INIT" ]; then
    _acct_put_in "${_ROOT}/log" date-init.txt "${_F_TIME//  / }"
  else
    _acct_put_in "${_ROOT}/log" "date-upgrade-${_THIS_CORE}.txt" "${_F_TIME//  / }"
  fi
  _OCTOPUS_VERSION_INFO="${_F_TIME} / \
    ${_OS_DIST}.${_OS_CODE} / \
    Octopus ${_X_VERSION}-${_xSrl} / \
    FPM ${_PHP_FPM_VERSION} / \
    CLI ${_PHP_CLI_VERSION}"
  echo "${_OCTOPUS_VERSION_INFO}" | fmt -su -w 2500 \
    | _acct_in_real_dir "${_ROOT}/log" _satellite_append_here octopus_log.txt
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: New entry added to ${_ROOT}/log/octopus_log.txt"
  fi
}

#
# Put the scratch root and the build tree back under root ownership.
#
# The old compensator re-owned only the /opt/tmp inode itself, so every file
# inside stayed owned by whichever satellite user ran last -- and since the
# mode normalizer leaves them 0644, that user kept write access to the shell
# libraries root sources on its next pass. Recursive on the build tree, which
# root executes and sources; the scratch root's own inode is reset too. Only
# the paths root consumes are touched, so a satellite's own scratch is left
# alone.
_satellite_normalize_scratch_owner() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_normalize_scratch_owner"
  fi
  chown root:root /opt/tmp &> /dev/null
  if [[ -d "${_bldPth}" ]]; then
    chown -R root:root "${_bldPth}" &> /dev/null
  fi
}

#
# The shared store $1 (/data/all, or /data/disk/all on an older layout) and
# ${_CORE} handed back to root at the end of the run, with the modes the
# platform build leaves them in. The run handed them to the account, which
# could have put a link or a hard link at any name there: every directory is
# entered as the real directory before anything is done in it, every walk
# goes through _satellite_reown_here or a handle-based mode setter (never a
# link, nor a hard-linked file), and the daily sweep hands the whole store
# back to root first, before any mode is set in it. /data/conf, never handed
# over, is asserted root's again the same way (_satellite_conf_root_here).
_satellite_shared_back() {
  local _b
  _b="$(cd -P -- "${1}" 2> /dev/null && pwd -P)"
  [ -n "${_b}" ] || return 0
  if [ ! -f "${1}/permissions-fix-${_xSrl}-${_X_VERSION}-${_TODAY}.info" ]; then
    _acct_in_real_dir "${_b}" _satellite_shared_fix_here &> /dev/null
  fi
  chown root:root "${1}" &> /dev/null
  _acct_in_real_dir "${_CORE}" chown -h root:root . &> /dev/null
  _acct_in_real_dir "${_CORE}" _acct_in_real_dir ./o_contrib \
    _satellite_root_back_here &> /dev/null
  _acct_in_real_dir "${_CORE}" _acct_in_real_dir ./o_contrib_seven \
    _satellite_root_back_here &> /dev/null
  _acct_in_real_dir "${_b}/000" _satellite_root_back_here &> /dev/null
  _acct_in_real_dir /data/conf _satellite_conf_root_here &> /dev/null
  _satellite_normalize_scratch_owner
  chmod 0711 /data /data/disk /data/conf &> /dev/null
  _acct_in_real_dir "${_b}" _satellite_shared_top_here &> /dev/null
}
# The current (pinned) directory and everything below it handed back to
# root:root as chown -R root:root handed it (_satellite_reown_here), the
# walk calling perl only where a name is not root's already.
_satellite_root_back_here() {
  _satellite_reown_here root:root \! \( -uid 0 -gid 0 \)
}
# The daily sweep of the current (pinned) shared store, as the path globs it
# replaces set it: the store handed to root, 000/ 0755 directories and 0644
# files, */*/profiles 0755, the sites/all/{modules,libraries,themes} of
# */* and 000/core/* 02775, then every */*/sites and
# */*/{web,docroot,html}/sites tree handed to root:users, and the day's
# stamp put. find never follows a link, each name is changed from the
# directory find walked, through a handle, and dot names at the first two
# levels are left out as the globs left them.
_satellite_shared_fix_here() (
  PATH=/usr/local/bin:/usr/bin:/bin
  local _users
  _satellite_root_back_here
  _acct_in_real_dir ./000 _satellite_modes_walk_here 0755 0644
  find . -mindepth 3 -maxdepth 3 -regextype posix-extended \
    -regex '\./[^/.][^/]*/[^/.][^/]*/profiles' \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d 755 {} + \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" f 755 {} +
  find . -mindepth 5 -maxdepth 5 -regextype posix-extended \
    -regex '\./[^/.][^/]*/[^/.][^/]*/sites/all/(modules|libraries|themes)' \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d 02775 {} + \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" f 02775 {} +
  find . -mindepth 6 -maxdepth 6 -regextype posix-extended \
    -regex '\./000/core/[^/.][^/]*/sites/all/(modules|libraries|themes)' \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" d 02775 {} + \
    -execdir perl -e "${_SAT_NOFOLLOW_CHMOD_PL}" f 02775 {} +
  _users=$(getent group users 2> /dev/null | cut -d: -f3)
  if [[ "${_users}" =~ ^[0-9]+$ ]]; then
    find . -mindepth 1 -regextype posix-extended \
      \( -regex '\./[^/]+(/[^/]+)?' \) \
      -o \( -regex '\./[^/.][^/]*/[^/.][^/]*/sites(/.*)?' \
        -execdir perl -e "${_ACCT_REOWN_PL}" -- 0 "${_users}" {} + \) \
      -o -prune
    find . -mindepth 1 -regextype posix-extended \
      \( -regex '\./[^/]+(/[^/]+)?' \
        -o -regex '\./[^/.][^/]*/[^/.][^/]*/(web|docroot|html)' \) \
      -o \( -regex '\./[^/.][^/]*/[^/.][^/]*/(web|docroot|html)/sites(/.*)?' \
        -execdir perl -e "${_ACCT_REOWN_PL}" -- 0 "${_users}" {} + \) \
      -o -prune
  fi
  _acct_put_here "permissions-fix-${_xSrl}-${_X_VERSION}-${_TODAY}.info" fixed
)
# The top of the current (pinned) shared store at the end of the run: each
# name directly in it 0711 (a directory keeping its set-ID bits), the
# cpuinfo file 0644, the store and its 000/ 0755, as chmod set them by path,
# never through a link.
_satellite_shared_top_here() {
  _satellite_chmod_nofollow d 0711 ./*
  _satellite_chmod_nofollow f 0711 ./*
  _satellite_chmod_nofollow f 644 ./cpuinfo
  chmod 0755 .
  _acct_in_real_dir ./000 chmod 0755 .
}
# /data/conf (the current, pinned directory) at the end of the run: arch/log
# made where missing and set 0755, and the old global include copies moved
# into arch/, each directory used only as the real one (a link an account
# put at arch, log or global while a run of an earlier release had handed it
# /data/conf is never followed).
_satellite_conf_arch_here() {
  mkdir -p ./arch
  _acct_in_real_dir ./arch _satellite_sub_here log chmod 0755 . || return 0
  mv -f ./global.inc-pre* ./arch/ &> /dev/null
  [ -d ./global ] && [ ! -L ./global ] \
    && _acct_in_real_dir ./global _satellite_conf_pre_here
  mv -f ./global.inc-before* ./arch/ &> /dev/null
  mv -f ./global.inc-missing* ./arch/ &> /dev/null
  return 0
}
# The old include copies of the current (pinned) global/ moved into the
# arch/ beside it (the glob expands here).
_satellite_conf_pre_here() {
  mv -f ./*inc-pre* ../arch/ &> /dev/null
  return 0
}

_satellite_batch_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_batch_cleanup"
    _debug_proc
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    _L_ST="install"
  else
    _L_ST="upgrade"
  fi
  _msg "Final post-${_L_ST} cleaning, one moment..."
  cd /
  chmod 711 bin boot data dev emul etc home lib lib64 lib32 media mnt &> /dev/null
  chmod 711 opt sbin selinux srv sys usr var share run &> /dev/null
  chmod 700 root &> /dev/null
  if [ -e "${_D}" ]; then
    _satellite_shared_back "${_D}"
  elif [ -e "/data/disk/all" ]; then
    _satellite_shared_back /data/disk/all
  fi
  chmod 0700 /data/u &> /dev/null
  chown root:root /data/u &> /dev/null
  rm -f /data/u/*host8* &> /dev/null
  rm -f /data/u/*o8.io* &> /dev/null
  rm -f /data/u/*boa.io* &> /dev/null
  rm -f /data/u/*aegir.cc* &> /dev/null
  ### backups/ is the instance user's (or a link into its store): its own
  ### old copies are moved into backups/system by that user.
  _satellite_as_user "_b=${_ROOT}/backups; \
    mv -f \${_b}/drupalgeddon-pre* \${_b}/system/; \
    mv -f \${_b}/drush_make-pre* \${_b}/system/; \
    mv -f \${_b}/drush-pre* \${_b}/system/; \
    mv -f \${_b}/make_local-pre* \${_b}/system/; \
    mv -f \${_b}/provision_boost-pre* \${_b}/system/; \
    mv -f \${_b}/provision_cdn-pre* \${_b}/system/; \
    mv -f \${_b}/provision_civicrm-pre* \${_b}/system/; \
    mv -f \${_b}/provision_platform_git-pre* \${_b}/system/; \
    mv -f \${_b}/provision_site_backup-pre* \${_b}/system/; \
    mv -f \${_b}/provision_tasks_extra-pre* \${_b}/system/; \
    mv -f \${_b}/provision-pre* \${_b}/system/; \
    mv -f \${_b}/registry_rebuild-pre* \${_b}/system/; \
    mv -f \${_b}/safe_cache_form_clear-pre* \${_b}/system/; \
    mv -f \${_b}/mydropwizard-pre* \${_b}/system/" &> /dev/null
  # 0755 (not 0777): the surrounding mv operations target /data/conf/arch/,
  # not /data/conf/arch/log — the log subdirectory is vestigial and has no
  # current writer. Matches the parallel fix in system.sh.inc. arch, log and
  # global are used only as the real directories (_satellite_conf_arch_here).
  _acct_in_real_dir /data/conf _satellite_conf_arch_here
  ### module* directories two to five levels below static/ made 0775. static/
  ### is group-writable: walked from the real directory (find does not
  ### follow a link), and each match is entered and checked to be the real
  ### directory at that path before its mode is set on '.', so a name
  ### swapped for a link after the walk is never followed; dot names are
  ### skipped, as the per-depth globs this replaces skipped them.
  _acct_in_real_dir "${_ROOT}/static" _satellite_static_modules_here &> /dev/null
  if [ -d "${_CORE}/${_DRUPAL7}" ]; then
    [ -d "/var/backups/trash" ] || mkdir -p /var/backups/trash
    rm -rf /var/backups/trash/*
    mv -f ${_CORE}/${_DRUPAL7} /var/backups/trash/ &> /dev/null
  fi
}

#
# module* directories two to five levels below the current (pinned) static/,
# each set 0775 from inside it once cd -P lands on the real directory at the
# path find reported.
_satellite_static_modules_here() {
  local _s _m
  _s="$(pwd -P)"
  find . -maxdepth 5 \( -name '.?*' -prune \) \
    -o \( -path './*/*' -type d -name 'module*' -print0 \) \
    | while IFS= read -r -d '' _m; do
      ( cd -P -- "${_m}" 2> /dev/null \
        && [ "$(pwd -P)" = "${_s}/${_m#./}" ] && chmod 775 . )
    done
}

_satellite_display_url_finalize() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_display_url_finalize"
    _debug_proc
  fi
  if [ "${_STATUS}" = "INIT" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _DO_NOTHING=YES
    else
      _AEGIR_LOGIN_URL=$(_acct_in_real_dir "${_ROOT}/log" \
        _satellite_read_tail_here install.log \
        | tail --lines=11 | grep --text "^http:" 2>&1)
      if [ ! -z "${_AEGIR_LOGIN_URL}" ]; then
        echo " "
        _msg "INFO: Congratulations, Ægir Satellite have been installed successfully!"
#         _msg "NOTE! Please wait 2 min before visiting Ægir at:"
#         echo " "
#         _msg "LINK: ${_AEGIR_LOGIN_URL}"
#         echo " "
#         _msg "NOTE! The initial one-time login link will no longer work."
#         sleep 3
#         _msg "To access your Octopus Ægir control panel after the procedure is finished..."
#         _msg "...please generate a new link by running the following command:"
#         sleep 3
#         echo " "
#         echo "  su -s /bin/bash ${_USER} -c \"drush @hm uli\""
#         echo " "
#         sleep 3
      else
        _msg "ALRT! Something went wrong"
        _msg "ALRT! Please check the install log for details:"
        _msg "ALRT! ${_ROOT}/log/install.log"
      fi
    fi
  else
    _satellite_o_contrib_update_global
    _satellite_o_contrib_seven_update_global
    _satellite_o_contrib_eight_update_global
    _satellite_o_contrib_nine_update_global
    _satellite_o_contrib_ten_update_global
    _satellite_o_contrib_eleven_update_global
    _satellite_o_contrib_backdrop_update_global
  fi
  if [ ! -e "/root/.upstart.cnf" ] \
    && ! grep -qiE "^[[:space:]]*(export[[:space:]]+)?_NO_CRON_AUTOSTART=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} A: Starting the cron now"
    fi
    _mrun "service cron start"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} A: All done!"
  fi
  _msg "BYE!"

}


_satellite_child_b_prepare_dirs_permissions() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_prepare_dirs_permissions"
    _debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} B: Creating directories with correct permissions"
  fi
  if [ -e "${_ROOT}/aegir.sh" ]; then
    rm -f ${_ROOT}/aegir.sh
  fi
  #_DRUSH_HOSTING_TASKS_CMD="/usr/bin/drush @hostmaster hosting-tasks --force"
  _DRUSH_HOSTING_DISPATCH_CMD="${_T_CLI}/php ${_ROOT}/tools/drush/drush.php @hostmaster hosting-dispatch"
  touch ${_ROOT}/aegir.sh
  chmod 0700 ${_ROOT}/aegir.sh &> /dev/null
  echo -e \
    "#!/bin/bash\n\nPATH=.:${_T_CLI}:/usr/sbin:/usr/bin:/sbin:/bin\n \
     \n${_DRUSH_HOSTING_DISPATCH_CMD} \
     \ntouch ${_ROOT}/${_USER}-task.done" \
     | fmt -su -w 2500 | tee -a ${_ROOT}/aegir.sh >/dev/null 2>&1

  mkdir -p ${_ROOT}/aegir/distro
  mkdir -p ${_ROOT}/distro/${_DISTRO}
  mkdir -p ${_ROOT}/src/${_DISTRO}
  mkdir -p ${_ROOT}/src/{modules,themes}
  mkdir -p ${_ROOT}/{tools,log,u,backups,platforms,clients}
  chmod 0700 ${_ROOT}/{log,src,u} &> /dev/null
  chmod 0700 ${_ROOT}/src/${_DISTRO} &> /dev/null
  chmod 0700 ${_ROOT}/src/{modules,themes} &> /dev/null
  chmod 0711 ${_ROOT}/{aegir,aegir/distro,distro,platforms,tools} &> /dev/null
  chmod 0711 ${_ROOT}/distro/${_DISTRO} &> /dev/null
  chmod 0750 ${_ROOT}/{backups,clients} &> /dev/null

  if [ "${_STATUS}" = "UPGRADE" ]; then
    #_msg "${_STATUS} B: UPGRADE in progress..."
    if [ -d "${_ROOT}/distro" ]; then
     #_msg "${_STATUS} B: UPGRADE v.2 in progress..."
     if [ -e "${_ROOT}/log/domain.txt" ]; then
      _DOMAIN=$(cat ${_ROOT}/log/domain.txt 2>&1)
      _DOMAIN=$(echo -n ${_DOMAIN} | tr -d "\n" 2>&1)
     fi
     #_msg "${_STATUS} B: _DOMAIN is ${_DOMAIN}"
    elif [ ! -d "${_ROOT}/distro" ]; then
     #_msg "${_STATUS} B: UPGRADE v.1 in progress..."
     #_msg "${_STATUS} B: _DISTRO is ${_DISTRO}"
     if [ -e "${_ROOT}/log/domain.txt" ]; then
      _DOMAIN=$(cat ${_ROOT}/log/domain.txt 2>&1)
      _DOMAIN=$(echo -n ${_DOMAIN} | tr -d "\n" 2>&1)
     fi
     #_msg "${_STATUS} B: _DOMAIN is ${_DOMAIN}"
    fi
  else
    true
    #_msg "${_STATUS} B: NEW AEGIR setup in progress..."
    #_msg "${_STATUS} B: _DISTRO is ${_DISTRO}"
    #_msg "${_STATUS} B: _DOMAIN is ${_DOMAIN}"
  fi
  echo ${_DOMAIN} > ${_ROOT}/log/domain.txt
}

_satellite_child_b_install_drush() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_install_drush"
    _debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} B: Running standard installer"
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    mkdir -p ${_ROOT}/backups/system
    chmod 700 ${_ROOT}/backups/system
    if [ -d "${_ROOT}/aegir/config" ]; then
      if [ ! -d "${_ROOT}/config" ]; then
        cd ${_ROOT}/aegir
        mv -f config ${_ROOT}/config &> /dev/null
        ln -sfn ${_ROOT}/config ${_ROOT}/aegir/config
      fi
    fi
  fi
  # Checked cd: a relative mv after a failed cd acts on the wrong tree.
  local _drCpFail=""
  if [ -f "/opt/tools/drush/8/drush/drush.php" ]; then
    cd ${_ROOT}/tools || return 1
    mv -f drush ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} &> /dev/null
    cp -af /opt/tools/drush/8/drush ${_ROOT}/tools/ || _drCpFail=YES
  else
    cd ${_ROOT}/tools || return 1
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Downloading drush ${_DRUSH_VERSION}..."
    fi
    _get_dev_ext "drush-${_DRUSH_VERSION}.tar.gz"
  fi
  ### Restore to the real path: a mv into the existing tools/ dir parked the
  ### backup beside a missing or partial tools/drush instead of replacing it,
  ### and the live instance then dropped out of every tools/drush check. A
  ### copy that fails part way still leaves a drush.php behind, so its own
  ### status counts too.
  if [ -n "${_ROOT}" ] \
    && { [ -n "${_drCpFail}" ] || [ ! -f "${_ROOT}/tools/drush/drush.php" ]; } \
    && [ -f "${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW}/drush.php" ]; then
    rm -rf ${_ROOT}/tools/drush
    mv -f ${_ROOT}/backups/system/drush-pre-${_DISTRO}-${_NOW} ${_ROOT}/tools/drush
  fi
  cd ${_ROOT}/tools/drush/
  find ${_ROOT}/tools/drush -type d -exec chmod 0755 {} \; &> /dev/null
  find ${_ROOT}/tools/drush -type f -exec chmod 0644 {} \; &> /dev/null
  chmod 755 ${_ROOT}/tools/drush/drush
  chmod 755 ${_ROOT}/tools/drush/drush.complete.sh
  chmod 755 ${_ROOT}/tools/drush/drush.launcher
  chmod 755 ${_ROOT}/tools/drush/drush.php
  chmod 755 ${_ROOT}/tools/drush/unish.sh
  chmod 755 ${_ROOT}/tools/drush/examples/drush.wrapper
  chmod 755 ${_ROOT}/tools/drush/examples/git-bisect.example.sh
  chmod 755 ${_ROOT}/tools/drush/examples/helloworld.script
}

_satellite_child_b_drush_xts_cleanup() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_drush_xts_cleanup"
    _debug_proc
  fi
  if [ "${_STATUS}" = "UPGRADE" ]; then
    mkdir -p ${_ROOT}/backups/system
    chmod 700 ${_ROOT}/backups/system
    mv -f ${_ROOT}/backups/drush-pre* ${_ROOT}/backups/system/ &> /dev/null
    _B_EXT="provision clean_missing_modules drupalgeddon drush_ecl make_local \
      provision_boost provision_cdn provision_civicrm provision_platform_git \
      provision_site_backup provision_tasks_extra remote_import mydropwizard \
      registry_rebuild safe_cache_form_clear security_check security_review \
      utf8mb4_convert"
    for e in ${_B_EXT}; do
      if [ -e "${_ROOT}/.drush/$e" ]; then
        mv -f ${_ROOT}/.drush/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
      if [ -e "${_ROOT}/.drush/xts/$e" ]; then
        mv -f ${_ROOT}/.drush/xts/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
      if [ -e "${_ROOT}/.drush/usr/$e" ]; then
        mv -f ${_ROOT}/.drush/usr/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
      if [ -e "${_ROOT}/.drush/sys/$e" ]; then
        mv -f ${_ROOT}/.drush/sys/$e \
          ${_ROOT}/backups/system/$e-pre-${_DISTRO}-${_NOW} &> /dev/null
        mv -f ${_ROOT}/backups/$e-pre* ${_ROOT}/backups/system/ &> /dev/null
      fi
    done
  fi
}

_satellite_child_b_drush_xts_install() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_drush_xts_install"
    _debug_proc
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} B: Installing Ægir Provision backend..."
  fi
  mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
  rm -rf ${_ROOT}/.drush/drush_make
  rm -rf ${_ROOT}/.drush/sys/drush_make
  cd ${_ROOT}/.drush
  if [ "${_DL_MODE}" = "BATCH" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    _get_dev_ext "backend.tar.gz"
    mv -f ${_ROOT}/.drush/backend/sys ${_ROOT}/.drush/
    mv -f ${_ROOT}/.drush/backend/xts ${_ROOT}/.drush/
    mv -f ${_ROOT}/.drush/backend/usr ${_ROOT}/.drush/
    if [ -e "${_ROOT}/.drush/sys/provision/provision.inc" ] \
      && [ -d "${_ROOT}/.drush/xts/security_review" ] \
      && [ -d "${_ROOT}/.drush/usr/registry_rebuild" ]; then
      [ -e "${_ROOT}/.drush/backend" ] && rm -rf ${_ROOT}/.drush/backend*
    fi
  elif [ "${_DL_MODE}" = "GIT" ]; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    rm -rf ${_ROOT}/.drush/{sys,xts,usr}
    rm -rf ${_ROOT}/.drush/{provision,drush_make}
    mkdir -p ${_ROOT}/.drush/{sys,xts,usr}
    _rD="${_ROOT}/.drush"
    ${_gCb} ${_BRANCH_PRN} ${_gitHub}/provision.git      ${_rD}/sys/provision &> /dev/null
    ${_gCb} 7.x-1.x-dev ${_gitHub}/drupalgeddon.git      ${_rD}/usr/drupalgeddon &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/drush_ecl.git             ${_rD}/usr/drush_ecl &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/security_review.git       ${_rD}/xts/security_review &> /dev/null
    ${_gCb} 7.x-2.x ${_gitHub}/provision_boost.git       ${_rD}/xts/provision_boost &> /dev/null
    ${_gCb} 7.x-2.x ${_gitHub}/registry_rebuild.git      ${_rD}/usr/registry_rebuild &> /dev/null
    ${_gCb} 7.x-1.x ${_gitHub}/safe_cache_form_clear.git ${_rD}/usr/safe_cache_form_clear &> /dev/null
    rm -rf ${_rD}/*/.git
    rm -rf ${_rD}/*/*/.git
    cd ${_rD}/usr
    _get_dev_ext "clean_missing_modules.tar.gz"
    _get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Downloading Drush and Provision extensions from ${_DL_MODE}-${_AEGIR_VERSION}..."
    fi
    cd ${_ROOT}/.drush/sys
    _get_dev_ext "provision.tar.gz"
    cd ${_ROOT}/.drush/usr
    _get_dev_ext "clean_missing_modules.tar.gz"
    _get_dev_ext "drupalgeddon.tar.gz"
    _get_dev_ext "drush_ecl.tar.gz"
    _get_dev_ext "registry_rebuild.tar.gz"
    _get_dev_ext "safe_cache_form_clear.tar.gz"
    _get_dev_ext "utf8mb4_convert-7.x-1.3.tar.gz"
    cd ${_ROOT}/.drush/xts
    _get_dev_ext "provision_boost.tar.gz"
    _get_dev_ext "security_review.tar.gz"
    cd ${_ROOT}/.drush
  fi
  sed -i "s/files.boa.io/${_USE_MIR}/g" ${_ROOT}/.drush/sys/provision/aegir.make &> /dev/null
  wait
  ###
  ### Backdrop Drush extension: a global usr/ contrib command extension (inside
  ### the backend commandfile-filter carve-out). Gated dark; the client symlink
  ### machinery keys on this dir's existence.
  ###
  if [ "${_BACKDROP_SUPPORT}" = "YES" ]; then
    cd ${_ROOT}/.drush/usr
    rm -rf ${_ROOT}/.drush/usr/backdrop
    rm -rf ${_ROOT}/.drush/usr/backdrop-drush-extension
    _get_dev_ext "backdrop-drush-extension.tar.gz"
    if [ -d "${_ROOT}/.drush/usr/backdrop-drush-extension" ]; then
      mv -f ${_ROOT}/.drush/usr/backdrop-drush-extension \
        ${_ROOT}/.drush/usr/backdrop
    fi
    ### De-hint the sole PHP 5.6 parse-fatal (scalar type hints on drush_chalk);
    ### the extension is parsed on every backend drush call, so it must never
    ### fatal on a legacy php56 box. Idempotent: only the still-hinted form matches.
    if [ -e "${_ROOT}/.drush/usr/backdrop/includes/output.inc" ]; then
      sed -i \
        "s/function drush_chalk(string \$output, string \$color)/function drush_chalk(\$output, \$color)/" \
        ${_ROOT}/.drush/usr/backdrop/includes/output.inc &> /dev/null
    fi
    ### Fix the relative require in BackdropBoot::get_version(): the bare
    ### 'includes/output.inc' resolves against Drush core's include_path (whose
    ### output.inc lacks drush_chalk), so the extension's own drush_chalk -- used
    ### by backdrop-pm-enable/subtheme -- is never defined and those commands
    ### fatal. Anchor it to the extension dir. Idempotent: only the bare form
    ### matches. (VM-confirmed 2026-07-11.)
    if [ -e "${_ROOT}/.drush/usr/backdrop/BackdropBoot.php" ]; then
      sed -i \
        "s#require_once 'includes/output.inc';#require_once __DIR__ . '/includes/output.inc';#" \
        ${_ROOT}/.drush/usr/backdrop/BackdropBoot.php &> /dev/null
    fi
    ### Make BackdropBoot::conf_path() pass its arguments through: the stock
    ### wrapper re-hardcodes TRUE/FALSE inside the call, so no caller can ever
    ### force reset=TRUE and a '.' cached by an early empty-sites.php probe
    ### stays poisoned for the whole process (RCA 2026-07-19: B->B migrate
    ### fatal right after backdrop-updatedb). Idempotent: only the stock
    ### hardcoded form matches; the method-to-global call is not recursive.
    if [ -e "${_ROOT}/.drush/usr/backdrop/BackdropBoot.php" ]; then
      sed -i \
        "s/return conf_path(\$require_settings = TRUE, \$reset = FALSE);/return conf_path(\$require_settings, \$reset);/" \
        ${_ROOT}/.drush/usr/backdrop/BackdropBoot.php &> /dev/null
    fi
    ### Stop the extension's command_alter from hijacking Aegir/Provision.
    ### When BackdropBoot is the active bootstrap it replaces any command it
    ### does not recognise with a "not supported by Backdrop" fallback -- which
    ### swallows every provision-* / hosting-* command run against a Backdrop
    ### platform, breaking the whole Provision backend. Provision drives
    ### Backdrop here, so let its commands through untouched. Idempotent: the
    ### guard is inserted once, before the first $backdrop_command assignment.
    ### (VM-confirmed 2026-07-11.)
    if [ -e "${_ROOT}/.drush/usr/backdrop/backdrop.drush.inc" ] \
      && ! grep -q "'provision') === 0" \
        ${_ROOT}/.drush/usr/backdrop/backdrop.drush.inc; then
      sed -i \
        "/^  \$backdrop_command = NULL;/i\\
  if (strpos(\$command['command'], 'provision') === 0 || strpos(\$command['command'], 'hosting') === 0) {\n    return;\n  }\n" \
        ${_ROOT}/.drush/usr/backdrop/backdrop.drush.inc &> /dev/null
    fi
    ### Stop update_check_requirements() logging informational requirements as
    ### warnings: it emits every severity != REQUIREMENT_OK as 'warning', which
    ### also catches REQUIREMENT_INFO -- so core's PHP-version info row lands
    ### in every clone/deploy task log as a "(Currently using PHP Version: ...)"
    ### warning, confusing users. Demote INFO-severity entries to 'info'; real
    ### warnings/errors are unchanged. Idempotent: only the stock two-argument
    ### form matches.
    if [ -e "${_ROOT}/.drush/usr/backdrop/includes/update.inc" ]; then
      sed -i \
        "s/backdrop_set_message(\$message, 'warning');/backdrop_set_message(\$message, (\$requirement['severity'] == REQUIREMENT_INFO) ? 'info' : 'warning');/" \
        ${_ROOT}/.drush/usr/backdrop/includes/update.inc &> /dev/null
    fi
    cd ${_ROOT}/.drush
    wait
  fi
}

_satellite_child_b_drush_test() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_drush_test"
    _debug_proc
  fi
  drush8 cc drush &> /dev/null
  rm -rf ${_ROOT}/.tmp/cache
  if ${_DRUSHCMD} help | grep "^ provision-install" > /dev/null ; then
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Drush test result OK"
    fi
  else
    _msg "${_STATUS} B: FATAL ERROR: Drush is broken (${_DRUSHCMD} help failed)"
    _msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
    touch "/opt/tmp/state/${_USER}/status-AegirSetupB-FAIL"
    exit 1
  fi
  ### Non-fatal Backdrop extension smoke check (gated); the extension is optional,
  ### so a missing detection must not abort AegirSetupB.
  if [ "${_BACKDROP_SUPPORT}" = "YES" ] \
    && [ -e "${_ROOT}/.drush/usr/backdrop/backdrop.drush.inc" ]; then
    drush8 cc drush &> /dev/null
    if ${_DRUSHCMD} help 2>/dev/null | grep -q "backdrop-site-install"; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        _msg "${_STATUS} B: Backdrop Drush extension test result OK"
      fi
    else
      _msg "${_STATUS} B: NOTE: Backdrop Drush extension not detected by Drush"
    fi
  fi
}

_satellite_child_b_aegir_build() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_aegir_build"
    _debug_proc
  fi
  _LOCAL_STATUS="${_STATUS}"
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    cd ${_ROOT}
    _AGR_PXSWD=$(cat ${_ROOT}/.${_USER}.pass.txt 2>&1)
    _AGRPASWD=$(echo -n ${_AGR_PXSWD} | tr -d "\n" 2>&1)
    if [ "${_THIS_DB_HOST}" = "localhost" ] \
      || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
      || [ "${_THIS_DB_HOST}" = "PROXYSQL" ] \
      || [ "${_THIS_DB_HOST}" = "FQDN" ]; then
      if [ "${_THIS_DB_HOST}" = "FQDN" ]; then
        _THIS_DB_HOST="${_hName}"
      elif [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
        _SQL_CONNECT=127.0.0.1
        _THIS_DB_HOST=127.0.0.1
      else
        _THIS_DB_HOST=localhost
      fi
      _USE_AEGIR_HOST="${_hName}"
      _USE_DB_USER="${_USER}"
    else
      _USE_AEGIR_HOST="${_hName}"
      _USE_DB_USER=aegir_root
    fi
    if [ "${_THIS_DB_HOST}" = "${_MY_OWNIP}" ]; then
      _USE_AEGIR_HOST="${_hName}"
      _THIS_DB_HOST="${_hName}"
    fi
    _L_SYS_PHP="${_ROOT}/.${_USER}.pass.php"
    echo "<?php" > ${_L_SYS_PHP}
    echo "\$oct_db_user = \"${_USER}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_pass = \"${_AGRPASWD}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_port = \"${_THIS_DB_PORT}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_host = \"${_THIS_DB_HOST}\";" >> ${_L_SYS_PHP}
    echo "\$oct_db_dirs = \"/data/disk/${_USER}/backups\";" >> ${_L_SYS_PHP}
    chown ${_USER}:${_ACCG:-users} ${_L_SYS_PHP}
    chmod 0600 ${_L_SYS_PHP}

    _msg "${_STATUS} B: Running hostmaster-install, please wait..."
    ${_DRUSHCMD} cc drush >${_ROOT}/log/install.log 2>&1
    rm -rf ${_ROOT}/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      ${_DRUSHCMD} hostmaster-install ${_DOMAIN} \
        --aegir_db_host=${_THIS_DB_HOST} \
        --aegir_db_port=${_THIS_DB_PORT} \
        --aegir_db_pass=${_AGRPASWD} \
        --aegir_db_user=${_USE_DB_USER} \
        --aegir_host=${_USE_AEGIR_HOST} \
        --aegir_root=${_ROOT} \
        --client_email=${_MY_OCTO_EMAIL} \
        --http_service_type=nginx \
        --root=${_HM_ROOT} \
        --script_user=${_USER} \
        --web_group=${_WEBG} \
        --version=${_AEGIR_VERSION} -y -d \
      2>&1 | tee ${_ROOT}/log/install.log
    else
      ${_DRUSHCMD} hostmaster-install ${_DOMAIN} \
        --aegir_db_host=${_THIS_DB_HOST} \
        --aegir_db_port=${_THIS_DB_PORT} \
        --aegir_db_pass=${_AGRPASWD} \
        --aegir_db_user=${_USE_DB_USER} \
        --aegir_host=${_USE_AEGIR_HOST} \
        --aegir_root=${_ROOT} \
        --client_email=${_MY_OCTO_EMAIL} \
        --http_service_type=nginx \
        --root=${_HM_ROOT} \
        --script_user=${_USER} \
        --web_group=${_WEBG} \
        --version=${_AEGIR_VERSION} -y \
      >${_ROOT}/log/install.log 2>&1
    fi
    rm -rf ${_HM_ROOT}/profiles/{default,standard,minimal,testing}
    cd ${_HM_ROOT}
    ### Absolute paths on purpose: when hostmaster-install failed, the cd
    ### above fails too and relative writes pollute the previous cwd.
    mkdir -p ${_HM_ROOT}/sites/all/{modules,themes,libraries}
    mkdir -p ${_HM_ROOT}/sites/${_DOMAIN}/files/{tmp,js,css}
    chmod 02775 -R ${_HM_ROOT}/sites/${_DOMAIN}/files &> /dev/null
    _T_WG=$(_web_group "${_USER}")
    [ -n "${_T_WG}" ] && chgrp -R "${_T_WG}" ${_HM_ROOT}/sites/${_DOMAIN}/files &> /dev/null
    rm -f ${_ROOT}/u/${_DOMAIN}
    ln -sfn ${_HM_ROOT} ${_ROOT}/u/${_DOMAIN}
    rm -f /data/u/${_DOMAIN} &> /dev/null
    ln -sfn ${_HM_ROOT} /data/u/${_DOMAIN}
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Running hosting-dispatch/hosting-tasks..."
    fi
    _ensure_hosting_dispatch_enabled bare
    ${_DRUSHCMD} @hostmaster hosting-dispatch &> /dev/null
    wait
    sleep 5
    ${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0 &> /dev/null
    wait
    sleep 5
    ${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0 &> /dev/null
    wait
    sleep 5
    ${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0 &> /dev/null
    wait
  else
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Testing previous install..."
    fi
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache

    if [ -d "${_HM_ROOT}/modules/o_contrib" ] \
      && [ ! -L "${_HM_ROOT}/modules/o_contrib" ]; then
      rm -f ${_HM_ROOT}/modules/o_contrib/{cache_backport,redis_edge,redis}
    fi
    if [ -d "${_PREV_HM_ROOT}/modules/o_contrib" ] \
      && [ ! -L "${_PREV_HM_ROOT}/modules/o_contrib" ]; then
      rm -f ${_PREV_HM_ROOT}/modules/o_contrib/{cache_backport,redis_edge,redis}
    fi
    if [ -d "${_HM_ROOT}/modules/o_contrib_seven" ] \
      && [ ! -L "${_HM_ROOT}/modules/o_contrib_seven" ]; then
      rm -f ${_HM_ROOT}/modules/o_contrib_seven/{cache_backport,redis_edge,redis}
    fi
    if [ -d "${_PREV_HM_ROOT}/modules/o_contrib_seven" ] \
      && [ ! -L "${_PREV_HM_ROOT}/modules/o_contrib_seven" ]; then
      rm -f ${_PREV_HM_ROOT}/modules/o_contrib_seven/{cache_backport,redis_edge,redis}
    fi
    if [ -e "${_PREV_HM_ROOT}/modules/path_alias_cache" ]; then
      _DEBUG_MODE=YES
    fi
    if [ ! -e "${_PREV_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
      _DEBUG_MODE=YES
      _msg "${_STATUS} B: Testing previous install..."
      _msg "${_STATUS} B: OPS, zombie found, moving it to backups..."
      mv -f ${_PREV_HM_ROOT} \
        ${_ROOT}/backups/system/empty-host-master-${_LAST_HMR}-${_NOW}
      cd ${_ROOT}/aegir/distro
      _list=([0-9]*)
      _last=${_list[@]: -1}
      _L_LAST_HMR=$_last
      _BASH_TEST=$(bash --version 2>&1)
      if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
        _nextnum=00$((10#0${_last%%[^0-9]*} + 1))
      else
        _nextnum=00$((10#${_last%%[^0-9]*} + 1))
      fi
      _nextnum=${_nextnum: -3}
      _L_HM_DISTRO=${_nextnum}
      _HM_ROOT="${_ROOT}/aegir/distro/${_L_HM_DISTRO}"
      _PREV_HM_ROOT="${_ROOT}/aegir/distro/${_L_LAST_HMR}"
      _msg "${_STATUS} B: Testing previous install again after removing zombie..."
      if [ ! -e "${_PREV_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
        _DEBUG_MODE=YES
        _msg "${_STATUS} B: Testing previous install again..."
        _msg "${_STATUS} B: OPS, another zombie found, moving it to backups..."
        mv -f ${_PREV_HM_ROOT} \
          ${_ROOT}/backups/system/empty-host-master-${_L_HM_DISTRO}-${_NOW}-sec
        cd ${_ROOT}/aegir/distro
        _list=([0-9]*)
        _last=${_list[@]: -1}
        _L_LAST_HMR=$_last
        _BASH_TEST=$(bash --version 2>&1)
        if [[ "${_BASH_TEST}" =~ "version 5.1" ]] || [[ "${_BASH_TEST}" =~ "version 5.2" ]]; then
          _nextnum=00$((10#0${_last%%[^0-9]*} + 1))
        else
          _nextnum=00$((10#${_last%%[^0-9]*} + 1))
        fi
        _nextnum=${_nextnum: -3}
        _L_HM_DISTRO=${_nextnum}
        _HM_ROOT="${_ROOT}/aegir/distro/${_L_HM_DISTRO}"
        _PREV_HM_ROOT="${_ROOT}/aegir/distro/${_L_LAST_HMR}"
        _msg "${_STATUS} B: Let's hope there are no more zombies left..."
      fi
    fi
    if [ -d "${_HM_ROOT}" ]; then
      _msg "${_STATUS} B: FATAL ERROR: ${_HM_ROOT} already exists"
      _msg "${_STATUS} B: FATAL ERROR: Too many zombies to delete! Try again..."
      _msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
      touch "/opt/tmp/state/${_USER}/status-AegirSetupB-FAIL"
      exit 1
    fi
    _msg "${_STATUS} B: Hostmaster STATUS: Upgrade in progress..."
    ### security_review breaks the upgrade if active
    mv -f ${_ROOT}/.drush/xts/security_review/security_review.drush.inc \
      ${_ROOT}/.drush/xts/security_review/foo.txt  &> /dev/null
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    if [ -z "${TERM+x}" ]; then
      export TERM=vt100
    fi

    #
    # Fix broken Entity module if needed.
    #
    _pthA="profiles/hostmaster/modules/contrib/entity"
    _pthB="module_filter.module"
    #
    if [ -e "${_PREV_HM_ROOT}/${_pthA}/${_pthB}" ]; then
      _msg "${_STATUS} B: Fixing broken Entity module..."
      rm -rf ${_PREV_HM_ROOT}/${_pthA}
      cd ${_PREV_HM_ROOT}/profiles/hostmaster/modules/contrib
      _get_dev_stc "entity-7.x-1.12.tar.gz"
      ${_DRUSHCMD} @hostmaster en entity -y
      ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_service WHERE service LIKE 'http'" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "INSERT INTO hosting_service (nid, vid, service, type, restart_cmd, port, available) VALUES ('2', '2', 'http', 'nginx_ssl', 'sudo /etc/init.d/nginx reload', '80', '1')" &> /dev/null
      ${_DRUSHCMD} @hostmaster hosting-task @server_master verify --force
      _ensure_hosting_dispatch_enabled bare
      ${_DRUSHCMD} @hostmaster hosting-dispatch
      wait
      sleep 5
      ${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0
      wait
      sleep 5
      ${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0
      wait
      sleep 5
      ${_DRUSHCMD} @hostmaster hosting-tasks --force --fork=0 --strict=0
      wait
      _msg "${_STATUS} B: Waiting 15 seconds..."
      sleep 15
    fi

    if [ -e "${_PREV_HM_ROOT}/modules/path_alias_cache" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        ${_DRUSHCMD} @hostmaster dis aegir_custom_settings -y
        ${_DRUSHCMD} @hostmaster pm-uninstall aegir_custom_settings -y
        ${_DRUSHCMD} @hostmaster dis hosting_advanced_cron -y
        ${_DRUSHCMD} @hostmaster en ctools -y
        ${_DRUSHCMD} @hostmaster registry-rebuild
      else
        ${_DRUSHCMD} @hostmaster dis aegir_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster pm-uninstall aegir_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster dis hosting_advanced_cron -y &> /dev/null
        ${_DRUSHCMD} @hostmaster en ctools -y &> /dev/null
        ${_DRUSHCMD} @hostmaster registry-rebuild &> /dev/null
      fi
    else
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        ${_DRUSHCMD} @hostmaster dis hosting_custom_settings -y
        ${_DRUSHCMD} @hostmaster pm-uninstall hosting_custom_settings -y
        ${_DRUSHCMD} @hostmaster registry-rebuild
      else
        ${_DRUSHCMD} @hostmaster dis hosting_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster pm-uninstall hosting_custom_settings -y &> /dev/null
        ${_DRUSHCMD} @hostmaster registry-rebuild &> /dev/null
      fi
    fi

    cd ${_PREV_HM_ROOT}
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache

    ${_DRUSHCMD} @hostmaster sqlc < ${_bldPth}/aegir/helpers/hosting_cron.sql &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_task_log \
      WHERE timestamp < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 3 MONTH))" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "OPTIMIZE TABLE hosting_task_log" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_task \
      WHERE task_type='delete' AND task_status='-1'" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM hosting_task \
      WHERE task_type='delete' AND task_status='0' AND executed='0'" &> /dev/null

    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      ${_DRUSHCMD} hostmaster-migrate ${_DOMAIN} ${_HM_ROOT} -y -d
      ${_DRUSHCMD} @hostmaster registry-rebuild
    else
      ${_DRUSHCMD} hostmaster-migrate ${_DOMAIN} ${_HM_ROOT} -y &> /dev/null
      ${_DRUSHCMD} @hostmaster registry-rebuild &> /dev/null
    fi
    cd ${_HM_ROOT}
    ### Absolute path on purpose: when hostmaster-migrate failed, the cd
    ### above fails too and a relative mkdir pollutes the previous cwd
    ### (stray aegir/distro/sites/all skeleton).
    mkdir -p ${_HM_ROOT}/sites/all/{modules,themes,libraries}
    export DEBIAN_FRONTEND=text
    mv -f ${_ROOT}/.drush/xts/security_review/foo.txt \
      ${_ROOT}/.drush/xts/security_review/security_review.drush.inc  &> /dev/null
    rm -f ${_ROOT}/u/${_DOMAIN}
    ln -sfn ${_HM_ROOT} ${_ROOT}/u/${_DOMAIN}
    rm -f /data/u/${_DOMAIN} &> /dev/null
    ln -sfn ${_HM_ROOT} /data/u/${_DOMAIN}
    rm -rf ${_HM_ROOT}/profiles/{default,standard,minimal,testing}

    _msg "${_STATUS} B: Hostmaster STATUS: Upgrade completed"
  fi
}

_satellite_child_b_aegir_health_check() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_aegir_health_check"
    _debug_proc
  fi
  ###--------------------###
  if [ "${_LOCAL_STATUS}" = "INIT" ]; then
    _MSG_STATUS="install"
  else
    _MSG_STATUS="upgrade"
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "${_STATUS} B: Simple check if Ægir ${_MSG_STATUS} is successful"
  fi
  if [ -e "${_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
    _msg "${_STATUS} B: Ægir ${_MSG_STATUS} test result: OK"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      _msg "${_STATUS} B: Reloading Nginx..."
      sudo /etc/init.d/nginx reload
    else
      sudo /etc/init.d/nginx reload &> /dev/null
    fi
  else
    _msg "${_STATUS} B: FATAL ERROR: Required file does not exist:"
    _msg "${_STATUS} B: FATAL ERROR: ${_HM_ROOT}/sites/${_DOMAIN}/settings.php"
    _msg "${_STATUS} B: FATAL ERROR: Aborting AegirSetupB installer NOW!"
    touch "/opt/tmp/state/${_USER}/status-AegirSetupB-FAIL"
    exit 1
  fi
}

_le_order() {
  # The dehydrated order for the hostmaster (extra arguments passed through),
  # retried up to three times 15 s apart while the CA answers
  # accountDoesNotExist for the account registered a moment ago (seen on a
  # fresh install 2026-09-10: "Account .../acct/N not found" seconds after
  # --register created N; the pass-level retry then re-ran a whole octopus
  # pass for it). Any other outcome is final on the first attempt.
  local _out="${_ROOT}/log/letsencrypt-${_NOW}.attempt"
  local _try=0
  mkdir -p ${_ROOT}/log
  while : ; do
    _try=$(( _try + 1 ))
    bash ${_exeLe} ${_leParams} --domain ${_DOMAIN} "$@" > ${_out} 2>&1
    wait
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      cat ${_out}
    else
      cat ${_out} >> ${_ROOT}/log/letsencrypt-${_NOW}.log
    fi
    if [ "${_try}" -lt 3 ] && grep -q "accountDoesNotExist" ${_out}; then
      _msg "${_STATUS} B: LE -- the CA does not know the account registered a moment ago, retrying the order in 15s (attempt ${_try} of 3)"
      sleep 15
      continue
    fi
    break
  done
  rm -f ${_out}
}

_satellite_child_b_letsencrypt() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_letsencrypt"
    _debug_proc
  fi
  _leParams="--cron --ipv4"
  _leRoot="${_ROOT}/tools/le"
  _leKeyJ="${_leRoot}/tools/le/private_key.json"
  _leKeyP="${_leRoot}/tools/le/private_key.pem"
  _leCrtPath="${_leRoot}/certs/${_DOMAIN}"
  _exeLe="${_leRoot}/dehydrated"
  _pthLe="${_ROOT}/backups/system/dehydrated"
  mkdir -p ${_ROOT}/backups/system
  chmod 700 ${_ROOT}/backups/system
  rm -f ${_ROOT}/backups/system/letsencrypt*
  rm -f ${_ROOT}/backups/system/dehydrated*
  # Prefer the copy already shipped in the extracted batch tree;
  # the mirror fetch is the fallback when the tree is not available
  if [ -e "${_bldPth}/aegir/helpers/dehydrated" ] \
    && grep -q "OSTYPE" "${_bldPth}/aegir/helpers/dehydrated"; then
    cp -af ${_bldPth}/aegir/helpers/dehydrated ${_pthLe}
  else
    curl ${_crlGet} "${_urlHmr}/helpers/dehydrated" -o ${_pthLe}
  fi
  if [ ! -e "${_leRoot}" ]; then
    _leSetup="YES"
  fi
  if [ -e "${_pthLe}" ] && grep -q "OSTYPE" "${_pthLe}"; then
    mkdir -p ${_leRoot}/.ctrl
    chmod 0711 ${_leRoot}/.ctrl
    mkdir -p ${_leRoot}/.acme-challenges
    chmod 0711 ${_leRoot}/.acme-challenges
    mkdir -p ${_leRoot}/certs
    chmod 0700 ${_leRoot}/certs
    chmod 0711 ${_leRoot}
    cp -af ${_pthLe} ${_exeLe}
    if [ -e "${_exeLe}" ]; then
      chmod 0700 ${_exeLe}
      if [ "${_STATUS}" = "INIT" ] \
        || [ "${_leSetup}" = "YES" ] \
        || [ -e "${_leRoot}/.ctrl/ssl-demo-mode.pid" ]; then
        touch ${_leRoot}/.ctrl/ssl-demo-mode.pid
        echo -e 'CA="https://acme-staging-v02.api.letsencrypt.org/directory"\n' > ${_leRoot}/config.sh
        cp -af ${_leRoot}/config.sh ${_leRoot}/config
        if [ -e "${_leKeyJ}" ]; then
          mv -f ${_leKeyJ} "${_leKeyJ}-prev"
        fi
        if [ -e "${_leKeyP}" ]; then
          mv -f ${_leKeyP} "${_leKeyP}-prev"
        fi
        echo ""
        _msg "${_STATUS} B: Letsencrypt SSL mode: LIVE after auto-upgrade"
        echo ""
        _msg "${_STATUS} B: LE -- !!! ATTENTION"
        _msg "${_STATUS} B: LE -- Never enable SSL for the Hostmaster site in Ægir"
        _msg "${_STATUS} B: LE -- The Hostmaster site SSL is auto-managed separately"
        _msg "${_STATUS} B: LE -- !!! ATTENTION"
        echo ""
      fi
    else
      _msg "${_STATUS} B: LE -- Missing ${_exeLe} file?"
    fi
  fi
  if [ ! -e "${_leRoot}/.ctrl/ssl-demo-mode.pid" ] \
    && [ -e "${_leRoot}/config.sh" ]; then
    rm -f ${_leRoot}/config.sh
    rm -f ${_leRoot}/config
    if [ -e "${_leKeyJ}" ]; then
      mv -f ${_leKeyJ} "${_leKeyJ}-prev"
    fi
    if [ -e "${_leKeyP}" ]; then
      mv -f ${_leKeyP} "${_leKeyP}-prev"
    fi
  fi
  # Marker branch must come first: the closing else removes ${_leCrtPath},
  # which must never hit a manually installed (immutable) cert.
  if [ -e "${_leRoot}/.ctrl/dont-overwrite-${_DOMAIN}.pid" ]; then
    _msg "${_STATUS} B: LE renewal skipped for hostmaster ${_DOMAIN} -- immutable dont-overwrite marker present"
  elif [ -x "${_exeLe}" ] \
    && [ ! -e "${_leRoot}/.ctrl/ssl-demo-mode.pid" ] \
    && [ ! -e "${_leRoot}/config.sh" ]; then
    if [ -e "${_leCrtPath}/fullchain.pem" ]; then
      _msg "${_STATUS} B: Updating Letsencrypt cert for Hostmaster..."
    else
      _msg "${_STATUS} B: Creating Letsencrypt cert for Hostmaster..."
    fi
    _onDemandRegPid="${_leRoot}/.ctrl/onDemand-register.pid"
    if [ "${_DEBUG_MODE}" = "YES" ]; then
      if [ -e "${_onDemandRegPid}" ]; then
        rm -rf ${_leRoot}/accounts*
        bash ${_exeLe} --register --accept-terms
        wait
        bash ${_exeLe} --register --accept-terms
        wait
        _le_order --force
        touch ${_leRoot}/.ctrl/forced-${_DOMAIN}-mode.pid
      else
        bash ${_exeLe} --register --accept-terms
        wait
        _le_order
      fi
    else
      mkdir -p ${_ROOT}/log
      if [ -e "${_onDemandRegPid}" ]; then
        rm -rf ${_leRoot}/accounts*
        bash ${_exeLe} --register --accept-terms >${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
        bash ${_exeLe} --register --accept-terms >>${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
        _le_order --force
        touch ${_leRoot}/.ctrl/forced-${_DOMAIN}-mode.pid
      else
        bash ${_exeLe} --register --accept-terms >>${_ROOT}/log/letsencrypt-${_NOW}.log 2>&1
        wait
        _le_order
      fi
    fi
  else
    if [ -e "${_leCrtPath}/fullchain.pem" ]; then
      rm -rf ${_leCrtPath}
    fi
  fi
}

_satellite_child_b_aegir_ui_enhance() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_aegir_ui_enhance"
    _debug_proc
  fi
  _msg "${_STATUS} B: Enhancing Ægir UI, please wait..."
  mkdir -p ${_HM_ROOT}/sites/all/{modules,themes,libraries}
  mkdir -p ${_HM_ROOT}/profiles/hostmaster/modules/{aegir,contrib}
  cd ${_HM_ROOT}/sites/${_DOMAIN}
  if [ -e "${_HM_ROOT}/sites/${_DOMAIN}/settings.php" ]; then
    _VM_TEST="$(uname -a)"
    if [[ "${_VM_TEST}" =~ "-beng" ]]; then
      _VMFAMILY="VS"
    else
      _VMFAMILY="XEN"
    fi
    cd ${_HM_ROOT}/sites/${_DOMAIN}
    ${_DRUSHCMD} cc drush &> /dev/null
    rm -rf ${_ROOT}/.tmp/cache
    ${_DRUSHCMD} @hostmaster en aegir_objects -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en fix_ownership -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en fix_permissions -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_civicrm -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_civicrm_cron -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_client -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_cron -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_deploy -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_platform_composer -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_platform_composer_git -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_platform_git -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_tasks_extra -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_site_backup_manager -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en hosting_http_basic_auth -y &> /dev/null
    ### Backdrop platform awareness in the hostmaster frontend; gated dark
    ### behind _BACKDROP_SUPPORT. Enabling the module also enables
    ### its 'backdropcms' hosting feature via hosting_modules_enabled().
    if [ "${_BACKDROP_SUPPORT}" = "YES" ]; then
      ${_DRUSHCMD} @hostmaster en hosting_backdrop -y &> /dev/null
    fi
    ### Grav platform awareness in the hostmaster frontend; gated dark
    ### behind _GRAV_SUPPORT. Enabling the module also
    ### enables its 'gravcms' hosting feature via hosting_modules_enabled().
    if [ "${_GRAV_SUPPORT}" = "YES" ]; then
      ${_DRUSHCMD} @hostmaster en hosting_grav -y &> /dev/null
    fi
    ### Textpattern platform awareness in the hostmaster frontend; gated dark
    ### behind _TXP_SUPPORT. Enabling the module also enables
    ### its 'txpcms' hosting feature via hosting_modules_enabled().
    if [ "${_TXP_SUPPORT}" = "YES" ]; then
      ${_DRUSHCMD} @hostmaster en hosting_txp -y &> /dev/null
    fi
    ${_DRUSHCMD} @hostmaster en libraries -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en overlay -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en overlay_paths -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en revision_deletion -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en timeago -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en userprotect -y &> /dev/null
    ${_DRUSHCMD} @hostmaster en environment_indicator -y &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} client 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} clone 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} hosting_admin_client 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} hosting_client_register_user 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} hosting_client_send_welcome 0 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} hosting_feature_client 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_cron_default_interval 3600 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_queue_cron_frequency 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_civicrm_cron_queue_frequency 60 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_queue_task_gc_frequency 300 &> /dev/null
    if [ -e "${_ROOT}/log/hosting_cron_use_backend.txt" ]; then
      ${_DRUSHCMD} @hostmaster ${_vSet} \
        hosting_cron_use_backend 1 &> /dev/null
    else
      ${_DRUSHCMD} @hostmaster ${_vSet} \
        hosting_cron_use_backend 0 &> /dev/null
    fi
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_ignore_default_profiles 0 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_queue_tasks_frequency 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_queue_tasks_items 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_delete_force 0 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_alias_automatic_no_www 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_alias_automatic_www 1 &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_upload_platform_path "${_ROOT}/static" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_upload_upload_path "sites/${_DOMAIN}/files/deployment" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_platform_base_path "${_ROOT}/static/" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      aegir_backup_export_path "${_ROOT}/backup-exports" &> /dev/null
    ${_DRUSHCMD} @hostmaster ${_vSet} \
      hosting_default_profile "standard" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM menu_links \
      WHERE link_path='hosting/platforms'" &> /dev/null
    ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM menu_links \
      WHERE link_path='hosting/sites'" &> /dev/null

    ${_DRUSHCMD} @hostmaster vdel -y --exact hosting_task_logs_types_display &> /dev/null

    ${_DRUSHCMD} @hostmaster ev 'variable_set("hosting_task_logs_types_display", array(
      "error" => "error",
      "info" => "info",
      "message" => "message",
      "notice" => "notice",
      "ok" => "ok",
      "status" => "status",
      "success" => "success",
      "warning" => "warning",
      "backup" => "backup",
      "bootstrap" => "bootstrap",
      "command" => "command",
      "debug" => "none",
      "debugnotify" => "none",
      "queue" => "queue"))' &> /dev/null

    if [ "${_LOCAL_STATUS}" = "INIT" ]; then
      pBy="Octopus System powered by Barracuda"
      ${_DRUSHCMD} @hostmaster ${_vSet} site_name "${pBy}" &> /dev/null
      ${_DRUSHCMD} @hostmaster ${_vSet} site_mail "${_MY_OCTO_EMAIL}" &> /dev/null
      cp -af /opt/tmp/boa/aegir/helpers/make_home.php.txt ./
      mv -f make_home.php.txt make_home.php &> /dev/null
      ${_DRUSHCMD} php-script make_home &> /dev/null
      rm -f make_home.php
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE field_data_body \
        SET body_format='full_html' WHERE bundle='book' AND entity_type='node'" &> /dev/null
      if [ "${_THIS_DB_HOST}" = "localhost" ] \
        || [ "${_THIS_DB_HOST}" = "127.0.0.1" ] \
        || [ "${_THIS_DB_HOST}" = "PROXYSQL" ]; then
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
          SET status=-1 WHERE nid=7" &> /dev/null
      else
        ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
          SET status=-1 WHERE nid=5" &> /dev/null
      fi
      ### The client node is what hosting_client turns into the client
      ### control-panel account; without it the welcome email's panel
      ### login does not exist. The helper used to be copied only from
      ### the transient /opt/tmp build tree, which a concurrent barracuda
      ### or autoupboa pass purges mid-install (observed live on a fresh
      ### install: the copy hit the purge window, every failure below was
      ### silent, and the account never existed). Write the helper in
      ### place when the tree copy is gone, verify the account by mail,
      ### retry once (a stack restart under the chain also breaks the
      ### first attempt), and alert loudly instead of failing silently --
      ### same sentinel pattern as _satellite_set_client_login.
      local _client_chk _client_ev _client_mk_ev _client_try
      _client_ev="\$u = user_load_by_mail(\"${_CLIENT_EMAIL}\"); if (\$u && \$u->uid > 1) { echo \"CLIENTOK\"; }"
      _client_mk_ev="\$number = rand(100000, 999999); \$types = node_types_rebuild(); \$node = new stdClass(); \$node->uid = 1; \$node->type = \"client\"; \$node->email = \"${_CLIENT_EMAIL}\"; \$node->title = \"Octopus\" . \$number; \$node->language = LANGUAGE_NONE; \$node->status = 1; node_object_prepare(\$node); \$node = node_submit(\$node); node_save(\$node); variable_set(\"hosting_default_client\", \$node->nid);"
      for _client_try in 1 2; do
        ### Check first so a retry can never double-create the client
        ### when only the previous verification read failed.
        _client_chk=$(${_DRUSHCMD} @hostmaster ev "${_client_ev}" 2>/dev/null)
        if [[ "${_client_chk}" =~ CLIENTOK ]]; then
          break
        fi
        if [ "${_client_try}" = "2" ]; then
          ### The php-script channel executes at whatever bootstrap
          ### phase drush reached and can silently no-op below a full
          ### bootstrap (observed live: the script ran with node
          ### functions undefined). The retry therefore goes through
          ### drush ev against @hostmaster -- the same channel the
          ### login-set step relies on -- which is full-bootstrap or a
          ### visible error.
          sleep 10
          if [ "${_DEBUG_MODE}" = "YES" ]; then
            ${_DRUSHCMD} @hostmaster ev "${_client_mk_ev}"
          else
            ${_DRUSHCMD} @hostmaster ev "${_client_mk_ev}" &> /dev/null
          fi
          continue
        fi
        if [ -e "/opt/tmp/boa/aegir/helpers/make_client.php.txt" ]; then
          cp -af /opt/tmp/boa/aegir/helpers/make_client.php.txt ./make_client.php
        else
          cat > ./make_client.php <<'MKCLIENTEOF'
<?php

  // Create the client node
  global $argv;
  var_dump($argv);
  $number = rand(100000, 999999);
  $types = node_types_rebuild();
  $node = new stdClass();
  $node->uid = 1;
  $node->type = 'client';
  $node->email = $_SERVER['argv'][3];
  $node->title = 'Octopus' . $number;
  $node->language = LANGUAGE_NONE;
  $node->status = 1;
  node_object_prepare($node);
  $node = node_submit($node);
  node_save($node);
  $this_client_id = $node->nid;
  variable_set('hosting_default_client', $node->nid);

?>
MKCLIENTEOF
        fi
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          ${_DRUSHCMD} php-script make_client ${_CLIENT_EMAIL}
        else
          ${_DRUSHCMD} php-script make_client ${_CLIENT_EMAIL} &> /dev/null
        fi
      done
      _client_chk=$(${_DRUSHCMD} @hostmaster ev "${_client_ev}" 2>/dev/null)
      if [[ ! "${_client_chk}" =~ CLIENTOK ]]; then
        _msg "ALRT: client control-panel account for ${_CLIENT_EMAIL} was not created"
        _msg "ALRT: the welcome email's control-panel login will not exist on this instance"
      fi
      rm -f make_client.php
    else
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
        SET status=-2 WHERE publish_path LIKE '%/aegir/distro/%'" &> /dev/null
      _THIS_HM_PLR=$(cat ${_ROOT}/.drush/hostmaster.alias.drushrc.php \
          | grep "root'" \
          | cut -d: -f2 \
          | awk '{ print $3}' \
          | sed "s/[\,']//g" 2>&1)
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_platform \
      SET status=1 WHERE publish_path LIKE '${_THIS_HM_PLR}'" &> /dev/null
      pBy="Octopus System powered by Barracuda"
      ${_DRUSHCMD} @hostmaster ${_vSet} site_name "${pBy}" &> /dev/null
      cp -af /opt/tmp/boa/aegir/helpers/make_home.php.txt ./
      mv -f make_home.php.txt make_home.php &> /dev/null
      ${_DRUSHCMD} php-script make_home &> /dev/null
      rm -f make_home.php
      ${_DRUSHCMD} @hostmaster sqlq "DELETE FROM field_data_body \
        WHERE body_format IS NULL" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE field_data_body \
        SET body_format='full_html' WHERE bundle='book' AND entity_type='node'" &> /dev/null
    fi

    ${_DRUSHCMD} @hostmaster sqlq "UPDATE menu_links \
      SET hidden=1 WHERE plid=0 AND menu_name LIKE 'user-menu'" &> /dev/null

    if [ "${_DEBUG_MODE}" = "YES" ]; then
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_format"  &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_formats" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter"         &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_le -y
      ${_DRUSHCMD} @hostmaster en hosting_le_vhost -y
      ${_DRUSHCMD} @hostmaster en hosting_migrate_source -y
      ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y
      ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y
      ${_DRUSHCMD} @hostmaster cache-clear all
      ${_DRUSHCMD} @hostmaster updb -y
    else
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_format"  &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter_formats" &> /dev/null
      ${_DRUSHCMD} @hostmaster sqlq "TRUNCATE filter"         &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_le -y               &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_le_vhost -y         &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_migrate_source -y   &> /dev/null
      ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y  &> /dev/null
      ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y  &> /dev/null
      ${_DRUSHCMD} @hostmaster cache-clear all                &> /dev/null
      ${_DRUSHCMD} @hostmaster updb -y                        &> /dev/null
    fi

    ### The migrate_source backend half loads only once its drush/ dir is
    ### listed in $options['include'] in the instance drushrc, and only a
    ### verify of the hostmaster SITE regenerates that list. The builds
    ### and migrations above run before the module is enabled, so on the
    ### pass that first enables it the task would report success while
    ### granting and emitting nothing; regenerate once, only when the
    ### module is enabled but its include entry is still missing.
    local _MIGSRC_TEST
    if ! grep -q "migrate_source/drush" \
      ${_ROOT}/.drush/drushrc.php 2> /dev/null; then
      _MIGSRC_TEST=$(${_DRUSHCMD} @hostmaster ev \
        'if (module_exists("hosting_migrate_source")) { echo "MIGSRCON"; }' 2> /dev/null)
      if [[ "${_MIGSRC_TEST}" =~ MIGSRCON ]]; then
        if [ "${_DEBUG_MODE}" = "YES" ]; then
          ${_DRUSHCMD} @hostmaster provision-verify
        else
          ${_DRUSHCMD} @hostmaster provision-verify &> /dev/null
        fi
      fi
    fi

    if [ "${_LOCAL_STATUS}" = "INIT" ]; then
      if [ "${_DEBUG_MODE}" = "YES" ]; then
        ${_DRUSHCMD} @hostmaster \
          urol "admin" --mail=${_CLIENT_EMAIL}
        ${_DRUSHCMD} @hostmaster \
          urol "aegir account manager" --mail=${_CLIENT_EMAIL}
        ${_DRUSHCMD} @hostmaster \
          urol "aegir client" --mail=${_CLIENT_EMAIL}
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO userprotect \
          (uid, up_name, up_mail, up_pass, up_status, up_roles, up_cancel, up_edit, up_type, up_openid) VALUES \
          ('0', '0', '0', '0', '0', '0', '1', '1', 'user', '1'),\
          ('1', '0', '0', '0', '0', '0', '0', '0', 'admin', '0'),\
          ('1', '1', '1', '1', '1', '1', '1', '1', 'user', '1'),\
          ('2', '0', '0', '0', '1', '1', '1', '0', 'user', '1');"
      else
        ${_DRUSHCMD} @hostmaster \
          urol "admin" --mail=${_CLIENT_EMAIL} &> /dev/null
        ${_DRUSHCMD} @hostmaster \
          urol "aegir account manager" --mail=${_CLIENT_EMAIL} &> /dev/null
        ${_DRUSHCMD} @hostmaster \
          urol "aegir client" --mail=${_CLIENT_EMAIL} &> /dev/null
        ${_DRUSHCMD} @hostmaster sqlq "REPLACE INTO userprotect \
          (uid, up_name, up_mail, up_pass, up_status, up_roles, up_cancel, up_edit, up_type, up_openid) VALUES \
          ('0', '0', '0', '0', '0', '0', '1', '1', 'user', '1'),\
          ('1', '0', '0', '0', '0', '0', '0', '0', 'admin', '0'),\
          ('1', '1', '1', '1', '1', '1', '1', '1', 'user', '1'),\
          ('2', '0', '0', '0', '1', '1', '1', '0', 'user', '1');" &> /dev/null
      fi
    fi

    if [ ! -e "${_ROOT}/log/hosting_le_enable.txt" ]; then
      ${_DRUSHCMD} @hostmaster sqlq "UPDATE hosting_service SET type='nginx_ssl' WHERE service='http'" &> /dev/null
      wait
      ${_DRUSHCMD} @hostmaster hosting-task @server_master verify --force &> /dev/null
      wait
      mkdir -p ${_ROOT}/log
      touch ${_ROOT}/log/hosting_le_enable.txt
    fi
  fi
}

_satellite_child_b_vhosts_hotfix() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_vhosts_hotfix"
    _debug_proc
  fi
  ###---### Make sure there are no ghost or disabled vhost which still listen on IP.
  #
  rPth="${_ROOT}/config/server"
  sed -i "s/.*listen .*127.0.0.1:80;.*//g"             ${rPth}_*/nginx.conf
  wait
  sed -i "s/listen .*\*:80;/listen  \*:80;/g"          ${rPth}_*/nginx.conf
  wait
  ### The port lives twice in a vhost: the server-level fastcgi_param the main
  ### PHP location inherits, and the set line the shared include reads for
  ### the locations that declare their own params. Move both, or the two
  ### copies disagree until the site's next Verify.
  if [ -e "/data/conf/${_USER}_use_proxysql.txt" ]; then
    sed -i "s/param db_port.*/param db_port   6033;/g" ${rPth}_*/nginx/vhost.d/*
    sed -i "s/set \$boa_db_port .*/set \$boa_db_port \"6033\";/g" ${rPth}_*/nginx/vhost.d/*
  else
    sed -i "s/param db_port.*/param db_port   3306;/g" ${rPth}_*/nginx/vhost.d/*
    sed -i "s/set \$boa_db_port .*/set \$boa_db_port \"3306\";/g" ${rPth}_*/nginx/vhost.d/*
  fi
  wait
  sed -i "s/listen .*\*:80;/listen  \*:80;/g"          ${rPth}_*/nginx/vhost.d/*
  wait
}

_satellite_child_b_symlink_global_inc() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_symlink_global_inc"
    _debug_proc
  fi
  cd ${_ROOT}
  if [ -e "/data/conf/global.inc" ]; then
    ln -sfn /data/conf/global.inc ${_ROOT}/config/includes/global.inc
  fi
}

_satellite_child_b_redis_enable_finalize() {
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    _msg "PROC: _satellite_child_b_redis_enable_finalize"
    _debug_proc
  fi
  if [ -e "${_HM_ROOT}/modules/o_contrib" ]; then
    rm -rf ${_HM_ROOT}/modules/o_contrib
  fi
  if [ ! -e "${_HM_ROOT}/modules/o_contrib_seven/redis_edge" ]; then
    if [ -e "/data/all/000/modules/redis_edge" ]; then
      mkdir -p ${_HM_ROOT}/modules/o_contrib_seven
      rm -f ${_HM_ROOT}/modules/o_contrib_seven/{redis_edge,redis}
      ln -sfn /data/all/000/modules/redis_edge \
        ${_HM_ROOT}/modules/o_contrib_seven/redis_edge
    fi
  fi
  if [ "${_DEBUG_MODE}" = "YES" ]; then
    ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y
    ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y
    ${_DRUSHCMD} @hostmaster cache-clear all
  else
    ${_DRUSHCMD} @hostmaster en hosting_custom_settings -y &> /dev/null
    ${_DRUSHCMD} @hostmaster fr hosting_custom_settings -y &> /dev/null
    ${_DRUSHCMD} @hostmaster cache-clear all &> /dev/null
  fi
}
