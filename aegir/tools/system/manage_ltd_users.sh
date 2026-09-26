#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec
export _tRee=dev
export _xSrl=588855devT01

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
# the -u sync legs.
#
# A bare marker GAP is not a promotion. 'xmass sync --live' treats a
# missing marker on its target as an accident and rewrites it on every
# run, so a gap of seconds is an ordinary event on a healthy mirror, and
# a hold that follows the marker alone hands tenant logins back inside it
# -- on a box whose database is still applying the source's binlog, where
# every tenant write diverges the mirror and permanently shadows the
# active's copy. Measured: a 24 s gap released all four tenants.
#
# So the role, not the marker, decides -- the same predicate the nginx
# watchdog and the DB hold use: PROMOTED = the marker gone AND (the
# cutover's latch, or a role probe that RAN CLEAN, found no replica config
# and read super_read_only as 0). A promotion by hand is "remove the
# marker AND reset the replica", which the operator must do anyway.
# Cutover step 15 removes the marker on a box that is genuinely promoted,
# so the release there is unchanged and still lands within one pass.
#
# The three answers are kept DISTINCT on purpose, because the two
# directions are not symmetrical: flipping live shells to nologin and
# restoring them are both actions, and an unreadable probe justifies
# neither. REPLICA holds, PROMOTED releases, UNKNOWN restores nothing and
# says so once -- but it does NOT hand out a live shell either, which is
# the one direction that is free to be conservative (see the CREATE flag
# below).
_standby_ltd_role() {
  # Publishes _LTD_STANDBY_ROLE (REPLICA|PROMOTED|UNKNOWN), and with it
  # _LTD_STANDBY_WHY -- the whole reason phrase for a caller's one line,
  # empty on PROMOTED.
  # The return code decides, never emptiness alone: 8.4 removed the SLAVE
  # dialect and 5.7 lacks the REPLICA one, so the first call legitimately
  # fails on 5.7, and a refused connection would otherwise read as "no
  # replica config" on a running replica.
  local _rpl _rc _sro
  _LTD_STANDBY_WHY=""
  if [ -e "/root/.standby.cnf" ]; then
    _LTD_STANDBY_ROLE=REPLICA
    _LTD_STANDBY_WHY="the marker is back (the sync restores a missing one)"
    return 0
  fi
  # The latch is the answer the cutover PROVED at its step 11.5; it is not
  # the durable half (second.sh reaps it once the marker is gone), so on a
  # box promoted by hand the probe below is what answers.
  if [ -e "/var/log/boa/.standby_promoted.pid" ]; then
    _LTD_STANDBY_ROLE=PROMOTED
    return 0
  fi
  if ! command -v mysql > /dev/null 2>&1; then
    _LTD_STANDBY_ROLE=UNKNOWN
    _LTD_STANDBY_WHY="marker gone but the role probe could not run (no mysql client)"
    return 0
  fi
  _rpl=$(mysql --defaults-file=/root/.my.cnf --connect-timeout=5 \
    -e "SHOW REPLICA STATUS\G" 2>/dev/null)
  _rc=$?
  if [ "${_rc}" -ne "0" ]; then
    _rpl=$(mysql --defaults-file=/root/.my.cnf --connect-timeout=5 \
      -e "SHOW SLAVE STATUS\G" 2>/dev/null)
    _rc=$?
  fi
  if [ "${_rc}" -ne "0" ]; then
    _LTD_STANDBY_ROLE=UNKNOWN
    _LTD_STANDBY_WHY="marker gone but the role probe did not run clean (credentials? mysqld down?)"
    return 0
  fi
  if [ -n "${_rpl}" ]; then
    _LTD_STANDBY_ROLE=REPLICA
    _LTD_STANDBY_WHY="marker gone but a replica config is still present"
    return 0
  fi
  # No replica config is not yet a promotion: second.sh classifies "no
  # config but the DB still read-only" as a LOST replica (a RESET REPLICA
  # ALL by hand, a failed re-init) and deliberately KEEPS the marker there,
  # and the nginx watchdog reads the same variable before it opens the web
  # tier. Without this leg a lost replica released every tenant shell
  # inside an ordinary sync gap -- the incident this hold exists to
  # prevent, narrowed to lost boxes. It answers REPLICA because the only
  # thing that matters here is that it HOLDS; the reason says which it is.
  _sro=$(mysql --defaults-file=/root/.my.cnf --connect-timeout=5 \
    -N -e "SELECT @@super_read_only" 2>/dev/null | tr -dc '0-9')
  if [ "${_sro}" = "1" ]; then
    _LTD_STANDBY_ROLE=REPLICA
    _LTD_STANDBY_WHY="marker gone, no replica config, but the database is still read-only -- a LOST replica, never promoted"
    return 0
  fi
  if [ "${_sro}" != "0" ]; then
    _LTD_STANDBY_ROLE=UNKNOWN
    _LTD_STANDBY_WHY="marker gone but super_read_only was unreadable (credentials?)"
    return 0
  fi
  _LTD_STANDBY_ROLE=PROMOTED
  return 0
}

_standby_ltd_promoted() {
  # Re-probes on every call, deliberately: this script runs for minutes
  # and the role can change under it.
  _standby_ltd_role
  [ "${_LTD_STANDBY_ROLE}" = "PROMOTED" ]
}

_standby_ltd_hold_kept_log() {
  # One line per episode, shared by both readers below: this script runs
  # every 3 minutes and a half-promoted box can sit there for days.
  # Cleared when the marker returns or the tenants are released.
  #
  # Nothing to report once the marker is back: that is the ordinary held
  # state of a mirror, not a gap-hold, and the remedy this line prescribes
  # (reset the replica by hand) would be wrong advice on a healthy box.
  # The sweep's hold branch reaps the stamp, so the next genuine gap still
  # gets its line.
  [ -e "/root/.standby.cnf" ] && return 0
  [ -e "/run/boa_standby_ltdkept_logged.pid" ] && return 0
  mkdir -p /var/log/boa 2>/dev/null
  touch /run/boa_standby_ltdkept_logged.pid
  echo "$(date) LTD standby hold KEPT: ${_LTD_STANDBY_WHY} -- not a promotion (reset the replica to promote by hand; xmass sync restores the marker)" \
    >> /var/log/boa/manage_ltd.incident.log
  return 0
}

# The HOLD side, read once at the top: it decides the per-user branches
# further down (a tenant created mid-pass is created at nologin, and the
# per-user shell heal stands down) as well as the end-of-pass sweep, and
# they must all agree for the whole pass. The record file is the
# breadcrumb that keeps every box that never held to a single file test:
# only a box whose tenants this hold flipped pays a role probe, and only
# while its marker is missing.
#
# TWO flags, because the two directions are not the same question:
#   _LTD_STANDBY_HOLD        flips live shells to nologin and BLOCKS the
#                            restore -- only a POSITIVE "still a replica"
#                            earns that, and UNKNOWN must not restore a
#                            tenant on a box that may still be a replica.
#   _LTD_STANDBY_CREATE_HELD creates a NEW tenant at nologin plus a record
#                            line, and suppresses the per-user shell heal.
# The create direction is set on every answer that is not PROMOTED,
# UNKNOWN included: handing a live shell to a tenant born inside a gap is
# the only irreversible half (its writes shadow the active's copy for
# good), while creating at nologin + recording is fully reversible -- the
# sweep restores exactly the recorded users once the box reads PROMOTED.
_LTD_STANDBY_HOLD=NO
_LTD_STANDBY_CREATE_HELD=NO
if [ -e "/root/.standby.cnf" ]; then
  _LTD_STANDBY_HOLD=YES
  _LTD_STANDBY_CREATE_HELD=YES
elif [ -s "/var/log/boa/standby-held-shells.txt" ]; then
  _standby_ltd_role
  if [ "${_LTD_STANDBY_ROLE}" != "PROMOTED" ]; then
    _standby_ltd_hold_kept_log
    _LTD_STANDBY_CREATE_HELD=YES
    # Only a POSITIVE "still a replica" re-holds. UNKNOWN restores nobody
    # and flips nobody: the box may be promoted with a database that
    # cannot answer, and the sweep keeps the record file either way, so
    # the next pass retries.
    if [ "${_LTD_STANDBY_ROLE}" = "REPLICA" ]; then
      _LTD_STANDBY_HOLD=YES
    fi
  fi
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
    # Re-read the MARKER, not the flag: a hold kept across a marker gap is
    # also YES here, and its episode is not over until the marker itself is
    # back. A stamp left behind then would swallow the next episode's line.
    if [ -e "/root/.standby.cnf" ] \
      && [ -e "/run/boa_standby_ltdkept_logged.pid" ]; then
      rm -f /run/boa_standby_ltdkept_logged.pid
    fi
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
    # RELEASE only on a box that reads as PROMOTED, and re-probe HERE: the
    # flag above is the answer from the top of a pass that runs for
    # minutes, and the sync can have restored the marker since.
    if ! _standby_ltd_promoted; then
      # KEEP: the record file is left exactly as it is (it is the sole
      # input of the release, and the only thing that can restore these
      # tenants later), the shells stay at nologin, and the next pass
      # retries. Logged once per episode.
      _standby_ltd_hold_kept_log
      return 0
    fi
    rm -f /run/boa_standby_ltdkept_logged.pid
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
# An alias copy in a home its account owns: every step is on a name the
# account can swap while this runs. Only a regular file is compared, and the
# compare is bounded (a FIFO swapped in after the test would block root's
# read); anything but a clean "same" copies again. The copy never follows a
# link at its own name nor lands in a directory (-T), the old name is removed
# first, and the mode is set when the file is created, never by name afterwards
# (umask, no preserved mode). The directory holding the copy is the account's
# too: callers run both inside _ltd_in_real_dir. $1 = main, $2 = copy.
_ltd_alias_same() {
  [ -f "${2}" ] && [ ! -L "${2}" ] \
    && timeout -k 5 10 diff -w -B "${2}" "${1}" > /dev/null 2>&1
}
_ltd_alias_put() {
  ( umask 0337
    cp -aT --no-preserve=mode --remove-destination "${1}" "${2}" ) 2> /dev/null
}
# Run "$@" inside the real directory $1, never one reached through a link an
# account planted on the way. Below /home and /data/disk (root's) every name
# on the path must be a real directory: an instance user owns everything under
# its /data/disk/<oN> and can swap static/, log/ or config/ as easily as the
# last name (BOA's own links there -- static/files, backups, arch -- are never
# on a path given here). Elsewhere the last name is checked against its
# resolved parent. Once entered, ./name stays in that directory whatever is
# swapped.
_ltd_in_real_dir() {
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
# A root stamp in the current (pinned) directory: the name is removed and
# created exclusively, so a link put there in between is never followed.
# $1 = name, $2 = content.
_ltd_stamp_put() {
  rm -f -- "./${1}"
  printf '%s\n' "${2}" | dd of="./${1}" conv=excl status=none 2> /dev/null
}
# The reset of an account's ~/.drush, run inside the real directory: its
# globs expand there, and usr/ is entered the same way. $1 = hosted YES|NO.
_ltd_drush_strip() {
  if [ "${1}" = "YES" ]; then
    find . -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2> /dev/null
  else
    rm -f -- ./drush_make ./registry_rebuild ./clean_missing_modules
    rm -f -- ./drupalgeddon ./drush_ecl ./make_local ./safe_cache_form*
    _ltd_in_real_dir ./usr _ltd_drush_strip_usr
    rm -f -- ./.ctrl*
    rm -rf -- ./cache ./drush.ini ./*drushrc* ./*.inc
  fi
  mkdir -p ./usr
}
_ltd_drush_strip_usr() {
  rm -f -- ./drush_make ./registry_rebuild ./clean_missing_modules
  rm -f -- ./drupalgeddon ./drush_ecl ./make_local ./safe_cache_form*
  rm -f -- ./mydropwizard ./utf8mb4_convert ./backdrop
}
# The instance's Drush 8 extensions linked into the real ~/.drush/usr.
# $1 = the instance's .drush/usr.
_ltd_drush_usr_links() {
  local _t
  for _t in registry_rebuild clean_missing_modules drupalgeddon drush_ecl \
    safe_cache_form_clear utf8mb4_convert backdrop; do
    if [ ! -L "./${_t}" ] && [ -e "${1}/${_t}" ]; then
      ln -sfn "${1}/${_t}" "./${_t}"
    fi
  done
}
# The account's Drush CLI php.ini and its stamps, written inside the real
# ~/.drush. $1 = PHP version digits (85, 84, ...; empty: none installed),
# $2 = the account's ~/.tmp.
_ltd_drush_ini_put() {
  local _v="${1}" _qtp="${2//\//\\\/}" _w=""
  # the old ini stays until its replacement is in place (the final copy
  # replaces it): a temp directory that cannot be made leaves it, not none
  rm -f -- ./.ctrl.php*
  [ -n "${_v}" ] || { rm -f -- ./php.ini; return 0; }
  # Edited in root's own temp directory and put in place once: a name here is
  # the account's, so a FIFO or link put at php.ini is never opened by sed
  # and the copy never follows a link at the name into a directory (-T).
  _w=$(mktemp -d 2> /dev/null) || return 0
  [ -n "${_w}" ] && [ -d "${_w}" ] || return 0
  if cp -a "/opt/php${_v}/lib/php.ini" "${_w}/php.ini" 2> /dev/null; then
    # open_basedir stays out of the CLI ini: it breaks Drush and turns the
    # realpath cache off (every file operation checked against every listed
    # tree, uncached); lshell users are confined by their own measures, and
    # the FPM ini keeps its own list
    sed -i "s/.*open_basedir =.*/;open_basedir =/g"                      "${_w}/php.ini"
    wait
    sed -i "s/.*error_reporting =.*/error_reporting = 1/g"               "${_w}/php.ini"
    wait
    sed -i "s/.*session.save_path =.*/session.save_path = ${_qtp}/g"     "${_w}/php.ini"
    wait
    sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_qtp}/g" "${_w}/php.ini"
    wait
    sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_qtp}/g"               "${_w}/php.ini"
    wait
    sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_qtp}/g"           "${_w}/php.ini"
    wait
    if cp -aT --remove-destination "${_w}/php.ini" ./php.ini 2> /dev/null; then
      _ltd_stamp_put ".ctrl.php${_v}.${_xSrl}.pid" ""
      _ltd_stamp_put ".ctrl.${_tRee}.${_xSrl}.pid" ""
    fi
  fi
  rm -f -- "${_w}/php.ini"
  rmdir -- "${_w}" 2> /dev/null
  return 0
}
# The same where php.ini is kept immutable between passes: unlocked and
# locked again by name inside the pinned directory, only when it is a regular
# file.
_ltd_drush_ini_put_locked() {
  [ -f ./php.ini ] && [ ! -L ./php.ini ] && chattr -i ./php.ini 2> /dev/null
  _ltd_drush_ini_put "${1}" "${2}"
  [ -f ./php.ini ] && [ ! -L ./php.ini ] && chattr +i ./php.ini 2> /dev/null
  return 0
}
# A mode set on names in a directory an account owns, never through a link:
# each name is opened without following one and without blocking on a FIFO,
# checked to be the expected type and changed through the open handle, so a
# name swapped for a link at any moment is refused, not followed. Run it
# inside _ltd_in_real_dir or from find -execdir: O_NOFOLLOW covers the last
# name only. Args: f|d (regular file or directory), the mode (octal, or
# +octal to add bits), the names.
_LTD_FCHMOD_PL='use Fcntl;
my ($t, $m) = (shift @ARGV, shift @ARGV);
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  if (($t eq "f" && -f _) || ($t eq "d" && -d _)) {
    chmod($m =~ /^\+/ ? (($s[2] & 07777) | oct(substr($m, 1))) : oct($m), $h);
  }
  close($h);
}'
_ltd_chmod_nofollow() {
  # $1 = mode, the rest = regular files
  local _m="${1}"
  shift
  [ "$#" -gt 0 ] || return 0
  perl -e "${_LTD_FCHMOD_PL}" f "${_m}" "$@" 2> /dev/null
}
# The same for every regular file directly in the current (pinned) directory:
# the glob expands here, never in the caller's directory. $1 = mode.
_ltd_chmod_nofollow_here() (
  shopt -s dotglob nullglob
  _ltd_chmod_nofollow "${1}" ./*
)
# rm -f of a glob in the current (pinned) directory; $1 = the pattern,
# quoted by the caller so it expands here.
_ltd_rm_here() {
  # shellcheck disable=SC2086
  rm -f -- ./${1}
}
# True in a pinned directory that is the account's own, or the empty
# root-owned one root has just made at the name: a root-owned directory of
# the account's own tree renamed onto the name (/data/disk/<oN>/.boa-ctrl or
# undo/, a developer home's platforms/) is never swept, handed over or
# written. $1 = the account.
_ltd_mine_here() {
  [ "$(stat -c %U .)" = "${1}" ] && return 0
  [ "$(stat -c %u .)" = "0" ] && [ -z "$(ls -A . 2> /dev/null)" ]
}
# An account's own temp or dot directory, inside the real directory: handed
# to the account, aged out when asked (entries older than a day) and given
# its mode, only when _ltd_mine_here holds. $1 = owner:group, $2 = mode,
# $3 = YES to age it out.
_ltd_own_dir_here() {
  _ltd_mine_here "${1%%:*}" || return 1
  chown -h "${1}" . || return 1
  if [ "${3}" = "YES" ]; then
    touch .
    find . -mindepth 1 -mtime +0 -execdir rm -rf {} \; &> /dev/null
  fi
  chmod "${2}" .
}
# Entries older than a day aged out of an account's own temp directory, from
# inside the real directory (-execdir: rm never resolves a path through a
# name), and only when _ltd_mine_here holds. $1 = the account.
_ltd_age_out_here() {
  _ltd_mine_here "${1}" || return 1
  find . -mindepth 1 -mtime +0 -execdir rm -rf {} \; &> /dev/null
}
# A dot directory root seeds in a home its account owns and can change while
# this runs: created, then handed over and given its mode only inside the
# real directory (never by a name the account can swap meanwhile).
# $1 = path, $2 = mode, $3 = owner:group.
_ltd_dot_dir() {
  [ -d "${1}" ] && return 0
  mkdir -p "${1}"
  _ltd_in_real_dir "${1}" _ltd_own_dir_here "${3}" "${2}" NO
}
# ~/.lhistory, inside the real home: created exclusively (0644 by umask) and
# handed over only when it is the empty root file just made. $1 = owner:group.
_ltd_lhistory_put() {
  ( umask 022; dd of=./.lhistory conv=excl status=none < /dev/null 2> /dev/null ) || return 0
  [ -f ./.lhistory ] && [ ! -L ./.lhistory ] && [ ! -s ./.lhistory ] \
    && [ "$(stat -c %u ./.lhistory)" = "0" ] && chown -h "${1}" ./.lhistory
  return 0
}
# ~/.bazaar's config, inside the real directory. $1 = owner:group.
_ltd_bzr_conf() {
  ( umask 022; _ltd_stamp_put bazaar.conf "ignore_missing_extensions=True" ) \
    && chown -h "${1}" ./bazaar.conf
  chmod 700 .
}
# An Aegir identity's Drush 8 files inside its real ~/.drush: 0440, the
# control ones 0400, the directory 0710. oN (or aegir) owns the directory,
# the identity every Aegir task and site-local Drush run as, so a hostile
# drush include or a compromised task can swap any of these names (or
# ~/.drush itself) for a link; 0400 on a shared system path would take the
# box down.
_ltd_drush_alias_modes() {
  find . -maxdepth 1 -name '*.php' -type f \
    -exec perl -e "${_LTD_FCHMOD_PL}" f 0440 {} + 2> /dev/null
  _ltd_chmod_nofollow 0400 ./drushrc.php ./hm.alias.drushrc.php \
    ./hostmaster*.php ./platform_*.php ./server_*.php
  chmod 0710 .
}
# A file root keeps in a directory an account owns (static/control, oN's
# log/ and nginx post.d/): put as a fresh file inside the real directory,
# read without following a link or blocking on a FIFO (bounded), removed and
# unlocked only there. The account can put a link in any of these
# directories with no race to win. $1 = the directory, then the name (and
# content).
_ltd_put_in() {
  local _d="${1}"
  shift
  _ltd_in_real_dir "${_d}" _ltd_stamp_put "$@"
}
_ltd_read_in() {
  _ltd_in_real_dir "${1}" timeout 10 dd if="./${2}" iflag=nofollow,nonblock,fullblock \
    bs=1048576 count=1 status=none 2> /dev/null
}
# The drushrc aliases a yml store is converted from, as one sum: every name,
# and each file's content read as _ltd_read_in reads it. C collation keeps the
# order the same whatever locale runs the pass. Run inside _ltd_in_real_dir.
_ltd_alias_set_sum() {
  local LC_ALL=C
  local _a=""
  for _a in ./*.alias.drushrc.php; do
    [ -e "${_a}" ] || [ -L "${_a}" ] || continue
    printf '%s\n' "${_a#./}"
    timeout 10 dd if="${_a}" iflag=nofollow,nonblock,fullblock \
      bs=1048576 count=1 status=none 2> /dev/null
  done | md5sum | cut -d' ' -f1
}
_ltd_rm_in() {
  local _d="${1}"
  shift
  _ltd_in_real_dir "${_d}" _ltd_rm_here "$@"
}
_ltd_unlock_here() {
  # +i cleared on regular files only (chattr also refuses a link given by
  # its bare path); names = the args
  local _f
  for _f in "$@"; do
    [ -f "./${_f}" ] && [ ! -L "./${_f}" ] && chattr -i "./${_f}" &> /dev/null
  done
  return 0
}
# The tenant's static/control: the main login owns it (and any co-tenant can
# replace the name in 02775 static/). A file root writes for the main login
# is handed to it by chown -h; root's stamps stay root's.
_ltd_ctrl_read() {
  # $1 = name; prints its content, empty for a link, a FIFO or nothing
  _ltd_read_in "${_dscUsr}/static/control" "${1}"
}
_ltd_ctrl_put_here() {
  ( umask 022; _ltd_stamp_put "${1}" "${2}" ) \
    && chown -h "${_USER}.ftp:${_usrGroup}" "./${1}"
}
_ltd_ctrl_put() {
  # $1 = name, $2 = content: a file of the main login's
  _ltd_in_real_dir "${_dscUsr}/static/control" _ltd_ctrl_put_here "$@"
}
_ltd_ctrl_stamp() {
  # $1 = name, $2 = content: a stamp of root's
  _ltd_put_in "${_dscUsr}/static/control" "$@"
}
_ltd_ctrl_rm() {
  # $1 = name or pattern (quoted), removed inside the real directory
  _ltd_rm_in "${_dscUsr}/static/control" "$@"
}
_ltd_ctrl_info_owner() {
  chown -h "${_USER}.ftp:${_usrGroup}" ./*.info 2> /dev/null
}
# The control directory on the first pass of a serial, inside the real
# directory: the README put in place as a fresh 0644 file, the tree handed to
# the main login (chown -R never follows a link), old stamps swept and this
# serial's written exclusively.
_ltd_ctrl_init() {
  chmod 755 .
  if [ -e "/var/xdrago/conf/control-readme.txt" ]; then
    ( umask 022
      cp -T --no-preserve=mode --remove-destination \
        /var/xdrago/conf/control-readme.txt ./README.txt ) &> /dev/null
  fi
  chown -R "${_USER}.ftp:${_usrGroup}" .
  rm -f -- ./.ctrl.*
  _ltd_stamp_put ".ctrl.${_tRee}.${_xSrl}.pid" "OK"
}
# Inside the real clients/: the retired client directories go, and each
# real client directory's backups/ (never through a client name that is a
# link).
_ltd_clients_sweep() {
  local _c
  rm -rf -- ./admin ./omega8ccgmailcom ./nocomega8cc
  for _c in ./*; do
    [ -d "${_c}" ] && [ ! -L "${_c}" ] || continue
    _ltd_in_real_dir "${_c}" rm -rf -- ./backups
  done
  return 0
}
# ~/.drush locked and unlocked inside the real directory. Locking takes the
# directory first, after which no name in it can change; unlocking clears
# the names while it still holds. chattr opens a name without following a
# link (O_NOFOLLOW), so a link at usr/ or at an ini is refused.
_ltd_drush_lock_here() {
  chattr +i . &> /dev/null
  [ -d ./usr ] && [ ! -L ./usr ] && chattr +i ./usr &> /dev/null
  chattr +i ./*.ini &> /dev/null
  return 0
}
_ltd_drush_unlock_here() {
  [ -d ./usr ] && [ ! -L ./usr ] && chattr -i ./usr &> /dev/null
  chattr -i ./*.ini &> /dev/null
  chattr -i . &> /dev/null
  return 0
}
# The same for a main login's platforms/ and its entries.
_ltd_lock_all_here() {
  chattr +i . &> /dev/null
  chattr +i ./* &> /dev/null
  return 0
}
_ltd_unlock_all_here() {
  chattr -i ./* &> /dev/null
  chattr -i . &> /dev/null
  return 0
}
# ~/.drush/cache of an instance dropped inside the real directory, only when
# it is the instance user's own. $1 = the instance user.
_ltd_drush_cache_drop() {
  _ltd_mine_here "${1}" && rm -rf -- ./cache
  return 0
}
# A migration marker moved from oN's log/ into its src/ (the current, pinned
# directory): read without following a link or blocking, written as a fresh
# file, removed from log/ only inside the real one. $1 = name.
_ltd_log_marker_to_src() {
  local _c
  [ -e "${_dscUsr}/log/${1}" ] || return 0
  _c="$(_ltd_read_in "${_dscUsr}/log" "${1}")"
  _ltd_stamp_put "${1}" "${_c}" && _ltd_rm_in "${_dscUsr}/log" "${1}"
}
# sed -i on a file of the current (pinned) directory, only when it is a
# regular file: through a link sed -i puts a copy of the target at the name.
# $1 = name, $2 = sed script.
_ltd_sed_here() {
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 0
  sed -i "${2}" "./${1}" &> /dev/null
}
# The instance's aegir.sh, inside the real /data/disk/oN: a fresh file, owned
# by oN and 0700 through a handle that never follows a link. $1 = content.
_ltd_aegir_sh_put() {
  ( umask 077; _ltd_stamp_put aegir.sh "${1}" ) || return 1
  chown -h "${_USER}:${_usrGroup}" ./aegir.sh &> /dev/null
  _ltd_chmod_nofollow 0700 ./aegir.sh
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
    # A link at ~/.drush always takes the strip branch: the marker test would
    # otherwise read through it into whatever directory it points at.
    if [ -L "${_U_HD}" ] || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
      # Strip planted links BEFORE the deletes below act on these paths: a
      # tenant who swapped ~/.drush for a symlink would otherwise have root
      # rm -rf through it.
      _desymlink_planted "${_U_TP}" "${_U_HD}"
      _if_hosted_sys
      # The account owns both names and can swap them while this runs: every
      # remove and write inside them happens in the real directory
      # (_ltd_in_real_dir), never by a path through a link put there since.
      mkdir -p ${_U_HD}
      _ltd_in_real_dir "${_U_HD}" _ltd_drush_strip "${_hostedSys}"
      mkdir -p ${_U_TP}
      # aged out (-execdir: rm never resolves a path through a name),
      # handed over and given its mode inside the real directory, and only
      # when it is the account's own: a root-owned directory of the home
      # renamed onto the name is left alone
      _ltd_in_real_dir "${_U_TP}" _ltd_own_dir_here "$1:${_accGrp}" 02755 YES
      chown -h $1:${_accGrp} ${_U_HD}
      _ltd_in_real_dir "${_U_HD}" chmod 02755 .
      _ltd_in_real_dir "${_U_HD}" \
        _ltd_in_real_dir ./usr _ltd_drush_usr_links "${_dscUsr}/.drush/usr"
    fi

    if [ -e "${_dscUsr}/tools/drush/drush.php" ]; then
      _CHECK_USE_PHP_CLI=$(_ltd_read_in "${_dscUsr}/tools/drush" drush.php | grep "/opt/php" 2>&1)
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
      if [ ! -z "${_T_CLI_VRN}" ]; then
        _USE_PHP_CLI="${_T_CLI_VRN}"
        echo "_USE_PHP_CLI is ${_USE_PHP_CLI} for $1 at ${_USER} WTF"
        echo "_T_CLI_VRN is ${_T_CLI_VRN}"
      else
        if [ -e "${_dscUsr}/tools/drush/drush.php" ]; then
          _CHECK_USE_PHP_CLI=$(_ltd_read_in "${_dscUsr}/tools/drush" drush.php | grep "/opt/php" 2>&1)
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
      _U_INI=""
      case "${_USE_PHP_CLI}" in
        8.5|8.4|8.3|8.2|8.1|8.0|7.4|7.3|7.2|7.1|7.0|5.6) _U_INI="${_USE_PHP_CLI/./}" ;;
      esac
      # written inside the real ~/.drush: the ini, its sed rewrites and the
      # stamps never go through a link the account put at one of the names
      _ltd_in_real_dir "${_U_HD}" _ltd_drush_ini_put "${_U_INI}" "${_U_TP}"
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
    elif [[ "${_UQ}" == "${_USER}".*"${_LTD_PLATFORM_SUFFIX}" ]]; then
      # The platform developer login runs Composer too, and its home is
      # immutable between passes: its Composer home and cache are made here,
      # as the login, while the pass holds the home open.
      if [ ! -d "/home/${_UQ}/.composer" ] || [ ! -d "/home/${_UQ}/.cache/composer" ]; then
        su -s /bin/bash - ${_UQ} -c "mkdir -p ~/.composer ~/.cache/composer" &> /dev/null
      fi
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
      _ltd_rm_in "${_dscUsr}/log" '.gems.build*'
      _ltd_rm_in "${_dscUsr}/log" '.npm.build*'
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
        # the account can rename its own entry in the sticky gems/: the trees
        # are copied into the real directory only
        _ltd_in_real_dir "/opt/user/gems/${_UQ}" cp -a \
          /usr/local/lib/ruby/gems/3.3.0/gems \
          /usr/local/lib/ruby/gems/3.3.0/specifications \
          /usr/local/lib/ruby/gems/3.3.0/extensions \
          /usr/local/lib/ruby/gems/3.3.0/doc ./
        chown -R ${_UQ}:${_accGrp} /opt/user/gems/${_UQ}
        _ltd_rm_in "${_dscUsr}/log" '.gems.build*'
        _ltd_put_in "${_dscUsr}/log" ".gems.build.rb.${_UQ}.${_xSrl}.txt" ""
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
          _ltd_rm_in "${_dscUsr}/log" '.npm.build*'
          _ltd_put_in "${_dscUsr}/log" ".npm.build.${_UQ}.${_xSrl}.txt" ""
        fi
      else
        [ -e "/home/${_UQ}/.npm" ] && rm -rf /home/${_UQ}/.npm*
        [ -e "/opt/user/npm/${_UQ}" ] && rm -rf /opt/user/npm/${_UQ}
        _ltd_rm_in "${_dscUsr}/log" '.npm.build*'
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
      # replaceable. chattr refuses a link named by its bare path but follows
      # one behind a trailing slash, so no target here carries one; the tests
      # take the bare path too -- [ -L "x/" ] resolves the link, always false.
      _ltd_in_real_dir "/home/$1/platforms" _ltd_lock_all_here
    fi
    _ltd_in_real_dir "/home/$1/.drush" _ltd_drush_lock_here
    if [ -d "/home/$1/.bee/" ] && [ ! -L "/home/$1/.bee" ]; then
      chattr +i /home/$1/.bee
    fi
    if [ -d "/home/$1/.bazaar/" ] && [ ! -L "/home/$1/.bazaar" ]; then
      chattr +i /home/$1/.bazaar
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
      _ltd_in_real_dir "/home/$1/platforms" _ltd_unlock_all_here
    fi
    _ltd_in_real_dir "/home/$1/.drush" _ltd_drush_unlock_here
    if [ -d "/home/$1/.bee/" ] && [ ! -L "/home/$1/.bee" ]; then
      chattr -i /home/$1/.bee
    fi
    if [ -d "/home/$1/.bazaar/" ] && [ ! -L "/home/$1/.bazaar" ]; then
      chattr -i /home/$1/.bazaar
    fi
  fi
}
#
# Platform-level developer account (2026-09-07 ruling). One extra account per
# client named in _LTD_PLATFORM_CLIENTS (root-owned /root/.<oN>.octopus.cnf,
# never a tenant file), granted only the platforms where EVERY site is that
# client's. It is an ordinary sub-account in every other respect (creation,
# password store, groups, reaper tokens) whose lshell path also carries the
# qualifying app roots, with the drush and composer commands re-added in its
# own section (lshell applies [<user>] last, after the group's minus-lists),
# and a root-placed ~/platforms farm so SFTP sees the same tree. The site-local
# Drush of a locked Drupal 8+ platform runs in a timed window that is a real
# unlock (provision-dunlock on every granted composer platform, provision-dlock
# at expiry on those that were locked; see _ltd_platform_window below), opened
# when the account touches ~/.tmp/drush-window.request and closed by this
# worker once root's own clock says the minutes are up. Every pass also writes
# what the account reaches and why each refused platform is refused, which
# checkmyperms prints: to the account without another client's site names,
# to the main login with them.
_LTD_PLATFORM_SUFFIX="-dev"
_LTD_PLATFORM_WINDOW_MIN=60
_LTD_PLATFORM_TOOLS="'composer', 'drush', 'drush10', 'drush11', 'drush8', 'vdrush', 'vendor/drush/drush/drush.php'"
# The self-check the account keeps with or without a granted platform: a
# developer whose every platform was refused is the one who needs it most.
# On `allowed` only: it runs builtins alone, so lshell's noexec layer stays on.
_LTD_PLATFORM_SELF="'checkmyperms'"
# What checkmyperms prints: one root-written file per login, owned by that
# login and readable by it alone, replaced by rename inside this root-only
# directory, so no tenant ever controls a path root writes to.
_LTD_STATUS_DIR="/var/backups/ltd/status"
_LTD_PLATFORM_ACCT=NO
_LTD_REFUSED_FILE=""
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
    # _PATH_DOM, and a path the class mutates is not granted at all -- but
    # never silently: the operator page promises every platform missing from
    # ~/platforms a named reason
    if [ "${_root}" != "${_root//[^a-zA-Z0-9._\/-]/}" ]; then
      _root=$(_ltd_bytes_printable "${_root}")
      case " ${_seen} " in
        *" ${_root} "*) continue ;;
      esac
      _seen="${_seen} ${_root}"
      _ltd_notice "platform-badpath-${_acct}-$(basename "${_root}")" \
        "platform ${_root} refused for ${_acct}" \
        "its path has characters outside a-z A-Z 0-9 . _ / -" >&2
      _ltd_refused_note charset "${_root}" ""
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
      # root's own words would land in the path. The refuser names either the
      # site directory that is not the client's or one of its fixed reasons;
      # only the first is a single-client refusal.
      case "${_why}" in
        /*)
          _ltd_notice "platform-refused-${_acct}-$(basename "${_root}")" \
            "platform ${_root} refused for ${_acct}" \
            "not single-client: ${_why}" >&2
          _ltd_refused_note site "${_root}" "${_why}"
          ;;
        *)
          _ltd_notice "platform-refused-${_acct}-$(basename "${_root}")" \
            "platform ${_root} refused for ${_acct}" \
            "${_why}" >&2
          _ltd_refused_note structure "${_root}" "${_why}"
          ;;
      esac
      continue
    fi
    printf '%s\n' "${_root}"
  done
}
#
# One refusal for the status writer: kind|root|detail, appended to the file
# the caller named (the roots above run in a command substitution, so a
# variable could not carry them back).
_ltd_refused_note() {
  [ -n "${_LTD_REFUSED_FILE}" ] || return 0
  printf '%s|%s|%s\n' "${1}" "${2}" "${3}" >> "${_LTD_REFUSED_FILE}"
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
  # The alias keeps the path the platform was registered with: the docroot,
  # or for a Composer build possibly its app root. Either names this tree.
  _f=$(grep -lF -e "'root' => '${_doc}'" -e "'root' => '${_root}'" \
    /data/disk/${_USER}/.drush/platform_*.alias.drushrc.php 2>/dev/null | head -1)
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
# While it is open the account can rename ~/platforms and put a link there,
# so everything after the mkdir runs inside the real directory: once it is
# root:root 0755 nothing in it is the account's.
_ltd_platform_farm() {
  local _acct="${1}"
  local _roots="${2}"
  local _home="/home/${_acct}"
  local _farm="/home/${_acct}/platforms"
  [ -d "${_home}" ] && [ ! -L "${_home}" ] || return 0
  chattr -i "${_home}" 2>/dev/null
  if [ -L "${_farm}" ] || { [ -e "${_farm}" ] && [ ! -d "${_farm}" ]; }; then
    rm -f "${_farm}"
  fi
  [ -d "${_farm}" ] || mkdir -p "${_farm}"
  _ltd_in_real_dir "${_farm}" _ltd_platform_farm_fill "${_roots}" \
    || echo "ALERT: ${_farm} not refreshed: not the real directory, or root could not take it over"
  chattr +i "${_home}" 2>/dev/null
}
# The farm's links and README, inside the real ~/platforms. $1 = the roots.
_ltd_platform_farm_fill() {
  local _root=""
  local _name=""
  local _lnk=""
  local _keep=""
  chown -h root:root . && chmod 0755 . || return 1
  for _root in ${1}; do
    _name="$(basename "$(dirname "${_root}")")-$(basename "${_root}")"
    _keep="${_keep} ${_name}"
    ln -sfn "${_root}" "./${_name}"
  done
  for _lnk in ./*; do
    [ -L "${_lnk}" ] || continue
    case " ${_keep} " in
      *" ${_lnk#./} "*) ;;
      *) rm -f -- "${_lnk}" ;;
    esac
  done
  if [ -n "${_keep}" ]; then
    ( umask 022; _ltd_stamp_put README.txt "$(cat <<EOF
Platforms granted to this account are linked here, one per codebase, and are
also on your shell path. Run checkmyperms to see what this login reaches, the
state of each platform, and why a platform carrying one of your sites is not
linked here.

Drupal 7 and Backdrop: drush8 works at any time.

Drupal 8+: the platform is locked for Aegir's own Drush between uses. While
it is locked, Drush 8 answers read-only commands only (drush @site uli,
drush @site status). Anything that changes a site runs through the
platform's own Drush, which needs the platform unlocked; to unlock your
platforms for ${_LTD_PLATFORM_WINDOW_MIN} minutes run:

  touch ~/.tmp/drush-window.request

then, within three minutes:

  cd ~/platforms/<name>
  vdrush @<alias> <command>

(drush11 aliases lists the alias names). Touch it again to extend. While a
platform is unlocked Drush 8 cannot run on it, control-panel tasks on its
sites can fail, and a site Verify re-locks it (reopened within three
minutes); at expiry every platform is locked again.
https://docs.boa.io/using/connecting/extra-accounts
EOF
)" )
  else
    rm -f -- ./README.txt
  fi
  return 0
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
  # users/ is the main login's and can be a link by now: the store goes only
  # from the real directory
  _ltd_in_real_dir "/home/${_parent}.ftp/users" rm -f -- "./${_acct}"
  rm -f "/var/backups/ltd/window/${_acct}" "/var/backups/ltd/window/${_acct}.prev"
  rm -f "${_LTD_STATUS_DIR}/${_acct}" "/var/backups/ltd/.aliases/${_acct}.md5"
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
  local _why="${2:-not in _LTD_PLATFORM_CLIENTS of ${_USER}}"
  _ltd_platform_window_close "${_acct}"
  _ltd_reap_account "${_acct}" "${_USER}" "platform account retired (${_why})"
}
#
# The status files checkmyperms prints. The directory is root's (0711: a
# login reaches its own file by name, lists nothing); each file is owned by
# the one login that reads it, mode 0400, and replaced by rename.
_ltd_status_dir() {
  if [ -L "${_LTD_STATUS_DIR}" ] \
    || { [ -e "${_LTD_STATUS_DIR}" ] && [ ! -d "${_LTD_STATUS_DIR}" ]; }; then
    rm -f "${_LTD_STATUS_DIR}"
  fi
  [ -d "${_LTD_STATUS_DIR}" ] || mkdir -p "${_LTD_STATUS_DIR}"
  chown root:root "${_LTD_STATUS_DIR}"
  chmod 0711 "${_LTD_STATUS_DIR}"
}
_ltd_status_tmp() {
  mktemp "${_LTD_STATUS_DIR}/.tmp.XXXXXXXX"
}
_ltd_status_put() {
  local _login="${1}"
  local _tmp="${2}"
  [ -f "${_tmp}" ] || return 0
  if ! getent passwd "${_login}" > /dev/null 2>&1; then
    rm -f "${_tmp}"
    return 0
  fi
  chown "${_login}" "${_tmp}" && chmod 0400 "${_tmp}" \
    && mv -f "${_tmp}" "${_LTD_STATUS_DIR}/${_login}"
  rm -f "${_tmp}"
}
# printable, and nothing a reader could take for markup or a control code;
# byte by byte whatever locale cron or an upgrade runs this under, the way
# checkmyperms spells the directory it compares with a refused root
_ltd_status_safe() {
  local LC_ALL=C
  local _s="${1}"
  printf '%s' "${_s//[^a-zA-Z0-9._\/@:, ()+-]/?}"
}
_ltd_bytes_printable() {
  local LC_ALL=C
  printf '%s' "${1//[^[:print:]]/?}"
}
# "Drupal 10.1.8", "Drupal 7.105", "Backdrop 1.34.3" from the codebase itself
_ltd_platform_label() {
  local _doc=""
  local _v=""
  _doc=$(_ltd_platform_docroot "${1}") || { printf '%s\n' "unknown codebase"; return 0; }
  if [ -f "${_doc}/core/lib/Drupal.php" ]; then
    _v=$(grep -m1 -oE "const VERSION = '[^']+'" "${_doc}/core/lib/Drupal.php" 2>/dev/null | cut -d"'" -f2)
    printf 'Drupal %s\n' "$(_ltd_status_safe "${_v:-8+}")"
  elif [ -f "${_doc}/core/includes/bootstrap.inc" ]; then
    _v=$(grep -m1 -oE "define\('BACKDROP_VERSION', '[^']+'" "${_doc}/core/includes/bootstrap.inc" 2>/dev/null | cut -d"'" -f4)
    printf 'Backdrop %s\n' "$(_ltd_status_safe "${_v:-1}")"
  elif [ -f "${_doc}/includes/bootstrap.inc" ]; then
    _v=$(grep -m1 -oE "define\('VERSION', '[^']+'" "${_doc}/includes/bootstrap.inc" 2>/dev/null | cut -d"'" -f4)
    printf 'Drupal %s\n' "$(_ltd_status_safe "${_v:-7}")"
  else
    printf '%s\n' "unknown codebase"
  fi
}
# The alias a Drush 9+ store names a site by: every dot but the last becomes
# a hyphen (site:alias-convert's own rule; a bare domain keeps its name).
_ltd_modern_alias() {
  local _n="${1}"
  local _h="${1%.*}"
  [ "${_h}" = "${_n}" ] && { printf '%s' "${_n}"; return 0; }
  printf '%s.%s' "${_h//./-}" "${_n##*.}"
}
# The client's own sites on one app root, space-separated, by link name.
_ltd_platform_sites() {
  local _root="${1}"
  local _cdir="${2}"
  local _lnk=""
  local _out=""
  for _lnk in "${_cdir}"/*; do
    [ -L "${_lnk}" ] || continue
    [ "$(_ltd_platform_approot "$(readlink -f "${_lnk}")")" = "${_root}" ] || continue
    _out="${_out} $(basename "${_lnk}")"
  done
  printf '%s' "${_out# }"
}
# Why a site directory keeps a platform from this client, in the words one
# reader may see. $1 = the refusing site dir, $2 = the client dir, $3 = full
# (the main login, which owns every site of the instance) or dev (the platform
# account, which never learns another client's site). Prints two lines:
# the reason, then the fix.
_ltd_refused_site_why() {
  local _site="${1}"
  local _cdir="${2}"
  local _view="${3}"
  local _real=""
  local _name=""
  local _own=""
  local _lnk=""
  local _al=""
  local _sp=""
  local _live=""
  local _mine=NO
  _real=$(readlink -f "${_site}")
  _name=$(basename "${_site}")
  for _lnk in "${_pthParentUsr}"/clients/*/*; do
    [ -L "${_lnk}" ] || continue
    if [ "$(readlink -f "${_lnk}")" = "${_real}" ]; then
      _own=$(basename "$(dirname "${_lnk}")")
      break
    fi
  done
  [ -L "${_cdir}/${_name}" ] && _mine=YES
  _al="${_pthParentUsr}/.drush/${_name}.alias.drushrc.php"
  if [ -f "${_al}" ]; then
    _sp=$(grep -m1 -oE "'site_path' => '[^']+'" "${_al}" 2>/dev/null | cut -d"'" -f4)
    if [ -n "${_sp}" ] && [ "$(readlink -f "${_sp}")" != "${_real}" ]; then
      _live=$(basename "$(_ltd_platform_approot "$(readlink -f "${_sp}")")")
    fi
  fi
  _name=$(_ltd_status_safe "${_name}")
  _own=$(_ltd_status_safe "${_own}")
  _live=$(_ltd_status_safe "${_live}")
  if [ -n "${_own}" ]; then
    if [ "${_view}" = "full" ]; then
      printf '%s\n' "it also carries ${_name}, a site of client ${_own}"
      printf '%s\n' "assign ${_name} to this client in the control panel, or migrate it to another platform"
    else
      printf '%s\n' "it also carries a site of another client"
      printf '%s\n' "ask the account owner: checkmyperms on the main login names the site"
    fi
  elif [ -n "${_live}" ]; then
    if [ "${_view}" = "full" ] || [ "${_mine}" = "YES" ]; then
      printf '%s\n' "it also carries a leftover copy of ${_name}; the live site runs on ${_live}"
    else
      printf '%s\n' "it also carries a leftover site directory of another site"
    fi
    if [ "${_view}" = "full" ]; then
      printf '%s\n' "ask your host to remove the leftover directory (it is read-only for every login)"
    else
      printf '%s\n' "ask the account owner to have the leftover directory removed"
    fi
  elif [ -n "${_sp}" ]; then
    if [ "${_view}" = "full" ]; then
      printf '%s\n' "it also carries ${_name}, a site assigned to no client with a developer login"
      printf '%s\n' "assign ${_name} to this client in the control panel, or migrate it to another platform"
    else
      printf '%s\n' "it also carries a site that is not one of this client's sites"
      printf '%s\n' "ask the account owner: checkmyperms on the main login names the site"
    fi
  else
    if [ "${_view}" = "full" ] || [ "${_mine}" = "YES" ]; then
      printf '%s\n' "it also carries ${_name}, a site directory with no live site behind it"
    else
      printf '%s\n' "it also carries a site directory with no live site behind it"
    fi
    if [ "${_view}" = "full" ]; then
      printf '%s\n' "ask your host to remove the leftover directory (it is read-only for every login)"
    else
      printf '%s\n' "ask the account owner to have the leftover directory removed"
    fi
  fi
}
# One account's report. $1 = account, $2 = client name, $3 = client dir,
# $4 = granted roots, $5 = refusals file, $6 = full or dev. Machine lines
# (#grant, #refuse) close it for checkmyperms' own look at the cwd.
_ltd_platform_report() {
  local _acct="${1}"
  local _client="${2}"
  local _cdir="${3}"
  local _granted="${4}"
  local _refused="${5}"
  local _view="${6}"
  local _state="/var/backups/ltd/window/${1}"
  local _root=""
  local _doc=""
  local _lbl=""
  local _lock=""
  local _sites=""
  local _s=""
  local _line=""
  local _kind=""
  local _det=""
  local _why=""
  local _n=0
  echo "Developer login $(_ltd_status_safe "${_acct}") (client $(_ltd_status_safe "${_client}")), $(date '+%Y-%m-%d %H:%M %Z')"
  echo
  if [ -s "${_state}" ] \
    && [ -n "$(find "${_state}" -maxdepth 0 -mmin -${_LTD_PLATFORM_WINDOW_MIN} 2>/dev/null)" ]; then
    echo "Drush window: OPEN until $(date -d "@$(( $(stat -c %Y "${_state}") + _LTD_PLATFORM_WINDOW_MIN * 60 ))" '+%H:%M %Z')."
    echo "  Drupal 8+ platforms are unlocked: vdrush works, Drush 8 does not."
  else
    echo "Drush window: closed. Drupal 8+ platforms are locked: Drush 8 answers"
    echo "  read-only commands (uli, status). To unlock them for vdrush for"
    echo "  ${_LTD_PLATFORM_WINDOW_MIN} minutes: touch ~/.tmp/drush-window.request (applied within three minutes)."
  fi
  echo
  echo "Platforms this login reaches (linked in ~/platforms):"
  for _root in ${_granted}; do
    _n=$(( _n + 1 ))
    _lbl=$(_ltd_platform_label "${_root}")
    _doc=$(_ltd_platform_docroot "${_root}")
    _lock=""
    if [ -f "${_doc}/core/lib/Drupal.php" ]; then
      if [ ! -d "${_root}/vendor/drush" ]; then
        _lock=", no site-local Drush (no vdrush here)"
      elif _ltd_platform_locked "${_root}"; then
        _lock=", locked"
      else
        _lock=", unlocked"
      fi
    fi
    echo "  $(_ltd_status_safe "$(basename "$(dirname "${_root}")")-$(basename "${_root}")"): ${_lbl}${_lock}"
    _sites=$(_ltd_platform_sites "${_root}" "${_cdir}")
    for _s in ${_sites}; do
      if [ -f "${_doc}/core/lib/Drupal.php" ] && [ -d "${_root}/vendor/drush" ]; then
        echo "    $(_ltd_status_safe "${_s}")  (vdrush @$(_ltd_status_safe "$(_ltd_modern_alias "${_s}")"))"
      else
        echo "    $(_ltd_status_safe "${_s}")"
      fi
    done
  done
  [ "${_n}" -gt 0 ] || echo "  none"
  echo
  echo "Platforms carrying this client's sites that this login does NOT reach:"
  _n=0
  if [ -s "${_refused}" ]; then
    while IFS= read -r _line; do
      _kind="${_line%%|*}"
      _line="${_line#*|}"
      _root="${_line%%|*}"
      _det="${_line#*|}"
      _n=$(( _n + 1 ))
      echo "  $(_ltd_status_safe "${_root}"): $(_ltd_platform_label "${_root}")"
      _sites=$(_ltd_platform_sites "${_root}" "${_cdir}")
      [ -n "${_sites}" ] && echo "    sites: $(_ltd_status_safe "${_sites}")"
      case "${_kind}" in
        site)
          _why=$(_ltd_refused_site_why "${_det}" "${_cdir}" "${_view}")
          echo "    why: ${_why%%$'\n'*}"
          echo "    fix: ${_why#*$'\n'}"
          ;;
        structure)
          echo "    why: $(_ltd_status_safe "${_det}")"
          echo "    fix: only Drupal and Backdrop platforms are granted"
          ;;
        charset)
          echo "    why: its path has characters outside a-z A-Z 0-9 . _ / -"
          echo "    fix: deploy the platform under a plain directory name"
          ;;
      esac
    done < "${_refused}"
  fi
  [ "${_n}" -gt 0 ] || echo "  none"
  echo
  echo "Every site of this client stays reachable under ~/sites (files, themes,"
  echo "modules, libraries). Drush and the platform code are reachable only on the"
  echo "platforms listed as reached above; on any other, Drush fails with"
  echo "'Failed opening required .../autoload.php'."
  echo
  echo "Drush on a reached platform:"
  echo "  Drupal 7, Backdrop:    drush8 @<site> <command>, at any time"
  echo "  Drupal 8+, locked:     drush @<site> uli, drush @<site> status (Drush 8,"
  echo "                         read-only commands only)"
  echo "  Drupal 8+, any change: open the window, then"
  echo "                         cd ~/platforms/<name> && vdrush @<alias> <command>"
  for _root in ${_granted}; do
    echo "#grant ${_root}"
  done
  if [ -s "${_refused}" ]; then
    while IFS= read -r _line; do
      _line="${_line#*|}"
      echo "#refuse $(_ltd_status_safe "${_line%%|*}")"
    done < "${_refused}"
  fi
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
  local _listed=0
  local _nosite=""
  local _nodir=""
  local _ftpv=""
  local _devv=""
  _ltd_status_dir
  # the main login's view: every platform account of the instance, with the
  # names only the owner of every site may see
  _ftpv=$(_ltd_status_tmp)
  {
    echo "Platform developer logins of ${_USER}, $(date '+%Y-%m-%d %H:%M %Z')"
    echo "(the worker refreshes this every three minutes)"
  } > "${_ftpv}"
  for _client in ${_LTD_PLATFORM_CLIENTS}; do
    _client=${_client//[^a-zA-Z0-9._-]/}
    [ -n "${_client}" ] || continue
    _listed=$(( _listed + 1 ))
    _cdir="${_pthParentUsr}/clients/${_client}"
    if [ ! -d "${_cdir}" ] || [ -L "${_cdir}" ]; then
      _ltd_notice "platform-noclient-${_USER}-${_client}" \
        "platform account for ${_USER}: no client directory ${_cdir}" \
        "listed in _LTD_PLATFORM_CLIENTS; nothing granted"
      {
        echo
        echo "Client ${_client}: enabled by your host, but no developer login exists:"
        echo "  the client owns no Drupal or Backdrop site (or no such client)."
      } >> "${_ftpv}"
      _nam=$(_ltd_name_from_client_dir "${_cdir}")
      [ -n "${_nam}" ] && _nodir="${_nodir} ${_USER}.${_nam}${_LTD_PLATFORM_SUFFIX}"
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
      {
        echo
        echo "Client ${_client}: enabled by your host, but the login name ${_acct}"
        echo "  would be longer than 32 characters; a shorter client name is needed."
      } >> "${_ftpv}"
      continue
    fi
    _LTD_REFUSED_FILE=$(_ltd_status_tmp)
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
      _LTD_EXTRA_STANZA="allowed : + [${_LTD_PLATFORM_TOOLS}, ${_LTD_PLATFORM_SELF}]
allowed_shell_escape : + [${_LTD_PLATFORM_TOOLS}]"
    else
      _LTD_EXTRA_STANZA="allowed : + [${_LTD_PLATFORM_SELF}]"
    fi
    if [ "${_ALLD_NUM}" -ge "${_ALLD_CTL}" ]; then
      # kept only while the client has a site to reach: an account left in
      # place without its section would fall to the group policy
      _on="${_on} ${_acct}"
      _LTD_PLATFORM_ACCT=YES
      _add_user_if_not_exists
      _LTD_PLATFORM_ACCT=NO
      if getent passwd "${_acct}" > /dev/null 2>&1; then
        _ltd_platform_farm "${_acct}" "${_granted}"
        _ltd_platform_window "${_acct}" "${_granted}"
        _devv=$(_ltd_status_tmp)
        _ltd_platform_report "${_acct}" "${_client}" "${_cdir}" "${_granted}" \
          "${_LTD_REFUSED_FILE}" dev > "${_devv}"
        _ltd_status_put "${_acct}" "${_devv}"
        {
          echo
          _ltd_platform_report "${_acct}" "${_client}" "${_cdir}" "${_granted}" \
            "${_LTD_REFUSED_FILE}" full | grep -v '^#'
        } >> "${_ftpv}"
      fi
      echo "Done platform account ${_acct} for ${_cdir}: ${_granted:-no qualifying platform}"
    else
      _nosite="${_nosite} ${_acct}"
      {
        echo
        echo "Client ${_client}: enabled by your host, but no developer login is kept:"
        echo "  none of the client's sites is a Drupal or Backdrop site this pass can"
        echo "  reach (a login that existed is retired until one is)."
      } >> "${_ftpv}"
    fi
    rm -f "${_LTD_REFUSED_FILE}"
    _LTD_REFUSED_FILE=""
    _usrLtd=
    _ALLD_DIR=
    _LTD_EXTRA_STANZA=
  done
  for _ex in $(getent passwd | cut -d: -f1 | grep "^${_USER}\..*${_LTD_PLATFORM_SUFFIX}$"); do
    case " ${_on} " in
      *" ${_ex} "*) continue ;;
    esac
    case " ${_nosite} " in
      *" ${_ex} "*) _ltd_platform_retire "${_ex}" "its client has no Drupal or Backdrop site this pass can reach" ;;
      *)
        case " ${_nodir} " in
          *" ${_ex} "*) _ltd_platform_retire "${_ex}" "its client directory is gone or is a link" ;;
          *) _ltd_platform_retire "${_ex}" ;;
        esac
        ;;
    esac
  done
  if [ "${_listed}" -gt 0 ]; then
    _ltd_status_put "${_USER}.ftp" "${_ftpv}"
  else
    rm -f "${_ftpv}" "${_LTD_STATUS_DIR}/${_USER}.ftp"
  fi
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
              _ltd_in_real_dir "/home/${_usrParent}.ftp/users" \
                rm -f -- "./${_Existing}"
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
    # Every dot name this function seeds is root-created in a home the
    # sub-user owns and can change while this runs (the home is mutable
    # here), and none is ever legitimately a symlink: a planted link is
    # stripped first, and because one can be planted again in between, owners
    # are set by name only with chown -h, modes and writes happen only inside
    # the real directory, and a file is created exclusively, never through a
    # link at its name.
    _desymlink_planted "${_usrTmp}" "/home/${_usrLtd}/.lftp" \
      "/home/${_usrLtd}/.lhistory" "/home/${_usrLtd}/.drush" \
      "/home/${_usrLtd}/.bee" "/home/${_usrLtd}/.ssh" \
      "/home/${_usrLtd}/.bazaar"
    _ltd_dot_dir "${_usrTmp}" 02755 "${_usrLtd}:${_accGrp}"
    _ltd_dot_dir "/home/${_usrLtd}/.lftp" 02755 "${_usrLtd}:${_accGrp}"
    _usrLhist="/home/${_usrLtd}/.lhistory"
    if [ ! -e "${_usrLhist}" ]; then
      _ltd_in_real_dir "/home/${_usrLtd}" _ltd_lhistory_put "${_usrLtd}:${_accGrp}"
    fi
    _ltd_dot_dir "/home/${_usrLtd}/.drush" 700 "${_usrLtd}:${_accGrp}"
    _ltd_dot_dir "/home/${_usrLtd}/.bee" 700 "${_usrLtd}:${_accGrp}"
    _usrSsh="/home/${_usrLtd}/.ssh"
    _ltd_dot_dir "${_usrSsh}" 700 "${_usrLtd}:${_accGrp}"
    _ltd_in_real_dir "${_usrSsh}" \
      _ltd_chmod_nofollow 600 ./id_rsa ./id_dsa ./known_hosts
    _usrBzr="/home/${_usrLtd}/.bazaar"
    if [ -x "/usr/local/bin/bzr" ]; then
      if [ ! -z "${_usrLtd}" ] && [ ! -e "${_usrBzr}/bazaar.conf" ]; then
        mkdir -p ${_usrBzr}
        chown -h ${_usrLtd}:${_accGrp} ${_usrBzr}
        _ltd_in_real_dir "${_usrBzr}" _ltd_bzr_conf "${_usrLtd}:${_accGrp}"
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
  # The account owns ~/.drush and can put a link at its name: every remove and
  # copy below runs inside the real directory (_ltd_in_real_dir), never through
  # a link into another instance's alias store.
  _desymlink_planted "${_usrLtdRoot}/.drush"
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
        _ltd_in_real_dir "${_usrLtdRoot}/.drush" \
          rm -f -- "./${_AliasName}.alias.drushrc.php"
      fi
    done
  fi

  # an alias name that is not a regular file (a FIFO, a device link, a
  # directory) is never root's to open: the diff below reads every copy
  _ltd_in_real_dir "${_usrLtdRoot}/.drush" find . -maxdepth 1 \
    -name '*.alias.drushrc.php' ! -type f -exec rm -rf {} + 2> /dev/null
  for _Symlink in `find ${_usrLtdRoot}/sites/ \
    -maxdepth 1 -mindepth 1 | sort`; do
    _SiteName=$(echo ${_Symlink}  \
      | cut -d'/' -f5 \
      | awk '{ print $1}' 2>&1)
    _pthAliasMain="${_pthParentUsr}/.drush/${_SiteName}.alias.drushrc.php"
    _pthAliasCopy="./${_SiteName}.alias.drushrc.php"
    # The copy is a root-written control file in a home the sub-user owns, and
    # is never legitimately a link: strip a plant at its name, then compare and
    # copy inside the pinned ~/.drush (see _ltd_alias_put). Only the copy -- the
    # main alias may legitimately be the front-end link seeded at ~/.drush.
    [ -z "${_SiteName}" ] && continue
    _ltd_in_real_dir "${_usrLtdRoot}/.drush" _desymlink_planted "${_pthAliasCopy}"
    if ! _ltd_in_real_dir "${_usrLtdRoot}/.drush" \
      _ltd_alias_same "${_pthAliasMain}" "${_pthAliasCopy}"; then
      _ltd_in_real_dir "${_usrLtdRoot}/.drush" \
        _ltd_alias_put "${_pthAliasMain}" "${_pthAliasCopy}"
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
      if [ "${_LTD_STANDBY_CREATE_HELD}" = "YES" ]; then
        # A user born on a held standby (users.txt arrives from the active
        # by sync) never gets a live shell, not even for one pass; record
        # it so promotion restores it like every other held tenant. The
        # CREATE flag, not the sweep's: an unreadable role is not a reason
        # to hand out a shell, and this branch is the reversible one.
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
      # The store's directory and name are the tenant's: read inside users/
      # pinned by its real path (a users/ swapped for a link elsewhere is
      # refused), with one open that never follows a link, never blocks on a
      # FIFO and reads no more than a password's length.
      _lupHome=$(cd -P -- "/home/${_ADMIN}" 2> /dev/null && pwd -P)
      if [ -n "${_lupHome}" ]; then
        _ESC_LUPASS=$(cd -P -- "${_lupHome}/users" 2> /dev/null \
          && [ "$(pwd -P)" = "${_lupHome}/users" ] \
          && [ -f "./${_usrLtd}" ] && [ ! -L "./${_usrLtd}" ] \
          && timeout 10 dd if="./${_usrLtd}" iflag=nofollow,nonblock bs=256 count=1 \
            status=none 2> /dev/null | tr -d "\n")
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
      if [ "${_LTD_STANDBY_CREATE_HELD}" = "YES" ]; then
        : # tenant shells stay nologin while the standby hold is on --
        # healing them back here would reopen the login for the minutes
        # between this heal and the end-of-pass sweep, and an unreadable
        # role is no warrant for that either
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
      # The store sits in the tenant's own home, and this runs only when the
      # account is created, with the password just set: whatever stands at the
      # name goes, and the file is created with O_CREAT|O_EXCL (dd conv=excl),
      # so a name that reappears in between -- a link to a device or a FIFO
      # included, which bash's noclobber would still open -- fails the write
      # instead of taking it or blocking it. The store must always match the
      # shadow hash that was just set.
      _desymlink_planted "/home/${_ADMIN}/users"
      mkdir -p /home/${_ADMIN}/users
      _lupStore="/home/${_ADMIN}/users/${_usrLtd}"
      # /home is root's, so /home/<admin> cannot be swapped: resolve it, and
      # write only inside a users/ whose real path is exactly that one
      _lupHome=$(cd -P -- "/home/${_ADMIN}" 2> /dev/null && pwd -P)
      ( umask 077
        [ -n "${_lupHome}" ] \
          && cd -P -- "${_lupHome}/users" 2> /dev/null \
          && [ "$(pwd -P)" = "${_lupHome}/users" ] \
          && rm -f -- "./${_usrLtd}" \
          && printf '%s\n' "${_ESC_LUPASS}" \
            | dd of="./${_usrLtd}" conv=excl status=none 2> /dev/null ) \
        || echo "ALERT: password store ${_lupStore} not written: users/ is not the real directory, or the name reappeared"
    fi
    # A migration stages a sub-account's SSH keys here because the home did
    # not exist on this box yet; adopt them now that it does, once. Only for an
    # account that exists: a home with no passwd entry (the create path with an
    # existing home) must not consume the staged copy -- the chown below could
    # not resolve the owner and the rm -rf would destroy the only copy.
    if [ -d "/var/backups/migrate-subuser-ssh/${_usrLtd}/.ssh" ] \
      && [ -d "${_usrLtdRoot}" ] \
      && getent passwd "${_usrLtd}" > /dev/null 2>&1; then
      # a home that was already there may carry a link at .ssh
      # copied into the real home, every file put as a fresh one: a link at
      # .ssh, or at a key name inside it, is replaced, never written through
      _desymlink_planted "${_usrLtdRoot}/.ssh"
      _ltd_in_real_dir "${_usrLtdRoot}" \
        cp -a --remove-destination "/var/backups/migrate-subuser-ssh/${_usrLtd}/.ssh" ./
      # Group half derived, not the user name: no group named after a
      # sub-user is ever created, so that chgrp half always failed.
      chown -R ${_usrLtd}:$(_acct_group "${_usrLtd}") "${_usrLtdRoot}/.ssh" &> /dev/null
      _ltd_in_real_dir "${_usrLtdRoot}/.ssh" chmod 700 . &> /dev/null
      _ltd_in_real_dir "${_usrLtdRoot}/.ssh" _ltd_chmod_nofollow_here 600
      rm -rf "/var/backups/migrate-subuser-ssh/${_usrLtd}"
      echo "Adopted migrated SSH keys for ${_usrLtd}"
    fi
    _fix_dot_dirs
    rm -f ${_usrLtdRoot}/{.profile,.bash_logout,.bash_profile,.bashrc}
  fi
}
#
# Put an identity's passwd home back, retrying for up to 10 seconds: usermod
# -d is refused (exit 8, nothing changed) while any process of the identity
# runs in this root, and a process that began between the two usermod calls
# of a move is usually gone within seconds. True once the field reads right.
_restore_home() {
  local _u="$1" _want="$2" _t=0
  usermod -d "${_want}" "${_u}" > /dev/null 2>&1
  while [ "$(getent passwd "${_u}" 2>/dev/null | cut -d: -f6)" != "${_want}" ] \
    && [ "${_t}" -lt 10 ]; do
    sleep 1
    _t=$((_t + 1))
    usermod -d "${_want}" "${_u}" > /dev/null 2>&1
  done
  [ "$(getent passwd "${_u}" 2>/dev/null | cut -d: -f6)" = "${_want}" ]
}
#
# A primary-group move deferred because the identity is in use. The per-pass
# line alone reached nobody (this log is erased on every release), so the
# deferral is stamped, and once it has lasted a day it goes through
# _ltd_notice (incident log + one mail a day per identity). A completed move
# clears the stamp (_ig_defer_clear). $1 = identity, $2 = the group it waits
# to move to, $3 = one line saying what is waiting
_ig_defer_note() {
  local _u="$1" _g="$2" _what="$3" _stamp _since _seen _now _key
  echo "${_what}"
  mkdir -p /var/log/boa 2>/dev/null
  _stamp="/var/log/boa/instgrp.defer.${_u}"
  _now=$(date +%s)
  # The stamp's content is the start of this deferral episode, its mtime the
  # last pass that saw it. A stamp RUNNING passes stopped touching for an
  # hour is an old episode (the identity was moved out of band, by instgrp or
  # by a pass that found it already in place): the count starts again, so a
  # new deferral never alarms on a stale start. Silence while no pass ran at
  # all is not that -- a BOA run holds this worker off for the whole of its
  # pass -- so the gap is measured against the previous pass that did run.
  _seen=$(stat -c %Y "${_stamp}" 2>/dev/null); _seen=${_seen:-0}
  _since=$(head -1 "${_stamp}" 2>/dev/null); _since=${_since//[^0-9]/}
  if [ -z "${_since}" ] \
    || { [ "$(( _now - _seen ))" -gt 3600 ] \
      && [ "$(( _seen + 3600 ))" -lt "$(( ${_LTD_PREV_PASS:-0} + 0 ))" ]; }; then
    _since="${_now}"
    printf '%s\n' "${_since}" > "${_stamp}"
  fi
  touch "${_stamp}"
  [ "$(( _now - _since ))" -ge 86400 ] || return 0
  _key="instgrp-defer-${_u}"
  _since=$(stat -c %Y "/var/log/boa/manage-ltd-${_key//[^a-zA-Z0-9._-]/}.alerted" 2>/dev/null)
  _since=${_since:-0}
  [ "$(( $(date +%s) - _since ))" -ge 86400 ] || return 0
  _ltd_notice "${_key}" \
    "Identity ${_u} has kept a process running for over a day; its move to primary group ${_g} is still deferred" \
    "usermod refuses to change the primary group of a user in use. End the session or process (see instgrp status $(_acct_of_identity "${_u}")), or run instgrp convert/revert once it is idle; the worker retries every pass."
}
_ig_defer_clear() {
  rm -f "/var/log/boa/instgrp.defer.${1}"
}
# the Octopus account an identity belongs to (oN, oN.ftp, oN.<sub> -> oN)
_acct_of_identity() {
  printf '%s\n' "${1%%.*}"
}
# Change a sub-user's primary group without usermod's own recursive lchown of
# the home tree (shadow chown_tree: full pathnames, stops at the first
# immutable inode -- and these homes carry chattr +i -- with the passwd entry
# already rewritten). The home field points at an empty root-owned staging
# dir for that one call and is put back at once; the group on the files is
# the alias-copy leg's business.
_user_in_use() {
  # shadow's user_busy, the check usermod -d runs: a process in this root (a
  # chrooted pure-ftpd session is not) whose real, effective or saved uid is
  # the user's.
  local _uid _p _pids=""
  _uid=$(id -u "$1" 2>/dev/null) || return 1
  for _p in /proc/[0-9]*; do
    [ "${_p}/root" -ef / ] && _pids="${_pids} ${_p#/proc/}"
  done
  awk -v uid="${_uid}" -v pids="${_pids}" 'BEGIN {
    m = split(pids, p, " ")
    for (i = 1; i <= m; i++) {
      f = "/proc/" p[i] "/status"
      while ((getline l < f) > 0) {
        if (l ~ /^Uid:/) {
          split(l, u, /[ \t]+/)
          if (u[2] == uid || u[3] == uid || u[4] == uid) { close(f); exit 0 }
          break
        }
      }
      close(f)
    }
    exit 1
  }'
}
_set_primary_group() {
  local _u="$1" _g="$2" _h _pgUrc _stage=/var/backups/ltd/.pg-stage
  _h=$(getent passwd "${_u}" 2>/dev/null | cut -d: -f6)
  [ -n "${_h}" ] || return 1
  # usermod refuses -d for a user in use (exit 8, nothing changed): a
  # logged-in session keeps the identity where it is until an idle pass.
  # 2 = in use, not a failed move.
  _user_in_use "${_u}" && return 2
  mkdir -p "${_stage}" && chown root:root "${_stage}" && chmod 0700 "${_stage}"
  # Recorded first (the same record instgrp keeps): a kill between the two
  # usermod calls leaves the passwd home at the staging dir, and
  # _repair_staged_homes puts it back on the next pass.
  [ -d /var/log/boa ] || mkdir -p /var/log/boa
  printf '%s\n' "${_h}" > "/var/log/boa/instgrp.home.${_u}"
  usermod -d "${_stage}" -g "${_g}" "${_u}" > /dev/null 2>&1
  _pgUrc=$?
  # The restore is a -d too, so usermod busy-gates it as well: a process of
  # the identity that began between the two calls refuses it while it lives.
  # Retry for a few seconds (most such processes are short); the record
  # stays until the home field reads right, for _repair_staged_homes.
  if _restore_home "${_u}" "${_h}"; then
    rm -f "/var/log/boa/instgrp.home.${_u}"
  else
    echo "ALERT: ${_u} home field left at ${_stage} (in use during the restore); repaired on a later pass"
  fi
  [ "$(id -gn "${_u}" 2>/dev/null)" = "${_g}" ] && return 0
  [ "${_pgUrc}" = "8" ] && return 2
  return 1
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
      if _restore_home "${_u}" "${_want}"; then
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
      # Already on the group it belongs to: no deferral is open for it.
      [ "$(id -gn ${_usrLtd} 2>/dev/null)" = "${_usrGroup}" ] && _ig_defer_clear "${_usrLtd}"
      if [ "${_usrGroup}" != "users" ] \
        && [ "$(id -gn ${_usrLtd} 2>/dev/null)" != "${_usrGroup}" ] \
        && getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_usrLtd}"; then
        _set_primary_group ${_usrLtd} ${_usrGroup}
        _pgRc=$?
        if [ "${_pgRc}" = "2" ]; then
          _ig_defer_note "${_usrLtd}" "${_usrGroup}" "Sub-user ${_usrLtd} has processes running; its move to primary group ${_usrGroup} waits for an idle pass"
        elif ! id -nG ${_usrLtd} 2>/dev/null | tr ' ' '\n' | grep -qxF users; then
          if _set_primary_group ${_usrLtd} users; then
            echo "ALERT: ${_usrLtd} lost group users on the primary move, reverted to users"
          else
            echo "ALERT: ${_usrLtd} lost group users on the primary move and could not be reverted yet; retried next pass"
          fi
          mkdir -p /var/log/boa 2>/dev/null
          echo "$(date) LTD primary move: ${_usrLtd} lost group users on the primary move" \
            >> /var/log/boa/manage_ltd.incident.log
        elif [ "$(id -gn ${_usrLtd} 2>/dev/null)" = "${_usrGroup}" ]; then
          _ig_defer_clear "${_usrLtd}"
          echo "Sub-user ${_usrLtd} moved to primary group ${_usrGroup}"
        else
          echo "ALERT: ${_usrLtd} could not be moved to primary group ${_usrGroup}; left on $(id -gn ${_usrLtd} 2>/dev/null)"
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
      _ltd_drush_store_after_reset YES
    elif [[ "${_ID_EXISTS}" =~ "${_usrLtd}" ]] \
      && [[ " ${_ID_SHELLS} " == *" ltd-shell "* ]]; then
      echo "We will update user == ${_usrLtd} =="
      _disable_chattr ${_usrLtd}
      rm -rf /home/${_usrLtd}/drush-backups
      _usrTmp="/home/${_usrLtd}/.tmp"
      _desymlink_planted "${_usrTmp}"
      _ltd_dot_dir "${_usrTmp}" 02755 "${_usrLtd}:$(_acct_group "${_usrLtd}")"
      _ltd_in_real_dir "${_usrTmp}" _ltd_age_out_here "${_usrLtd}"
      _ok_update_user
      _ltdRst=NO
      [ ! -L "/home/${_usrLtd}/.drush" ] \
        && [ -e "/home/${_usrLtd}/.drush/.ctrl.${_tRee}.${_xSrl}.pid" ] || _ltdRst=YES
      _enable_chattr ${_usrLtd}
      _ltd_drush_store_after_reset "${_ltdRst}"
    fi
  fi
}
#
# The alias copies above are made before _enable_chattr, and on the first pass
# of every release serial _enable_chattr resets ~/.drush (the whole directory
# on a hosted system) -- so a new account, and every account after an update,
# had no @alias for Drush until the next pass. $1 = YES when this pass's
# _enable_chattr ran that reset (its own test: no stamp for this serial): the
# copies are redone onto the reset tree, with ~/.drush opened only around the
# write. A platform account's Drush 9+ store is checked every pass, and
# ~/.drush is opened only when it has to be rebuilt.
_ltd_drush_store_after_reset() {
  local _rst="${1}"
  local _hd="/home/${_usrLtd}/.drush"
  [ -e "/home/${_USER}.ftp/users/${_usrLtd}" ] || return 0
  getent passwd "${_usrLtd}" > /dev/null 2>&1 || return 0
  [ -d "${_hd}" ] && [ ! -L "${_hd}" ] || return 0
  if [ "${_rst}" = "YES" ]; then
    chattr -i "${_hd}" 2>/dev/null
    _manage_sec_user_drush_aliases
    chattr +i "${_hd}" 2>/dev/null
  fi
  if [ "${_LTD_PLATFORM_ACCT}" = "YES" ]; then
    _ltd_platform_alias_store "${_usrLtd}" "${_rst}"
  fi
}
#
# Drush 9+ (vdrush, drush10/11) reads site aliases only from a yml store. The
# main login's store is converted from every alias of the instance; a platform
# account gets its own, converted from its own alias copies -- exactly its
# client's sites -- by the account itself, the same tested route the main
# login's store takes. drush.yml is written with the alias path alone. The
# store is rebuilt when the client's aliases change (summed from the
# instance's own alias files, never from anything in the account's home), when
# ~/.drush was reset, or when it is gone; the sum is recorded only for a
# conversion that finished and produced a store, so a failed one is retried.
# The sums sit in a dot directory, which the nightly age prune of
# /var/backups/ltd/*/* never reaches (it made every store rebuild daily).
_ltd_platform_alias_store() {
  local _acct="${1}"
  local _rst="${2}"
  local _hd="/home/${_acct}/.drush"
  local _mark="/var/backups/ltd/.aliases/${_acct}.md5"
  local _sum=""
  local _lnk=""
  local _src=""
  local _rc=0
  local _need=NO
  [ -x "/usr/bin/drush10" ] || return 0
  [ ! -e "/root/.standby.cnf" ] || return 0
  [ -d "${_hd}" ] && [ ! -L "${_hd}" ] || return 0
  _sum=$(for _lnk in "${_Client}"/*; do
      [ -L "${_lnk}" ] || continue
      _src="${_pthParentUsr}/.drush/$(basename "${_lnk}").alias.drushrc.php"
      [ -f "${_src}" ] && [ ! -L "${_src}" ] && { echo "${_src}"; cat "${_src}"; }
    done | md5sum | cut -d' ' -f1)
  if [ "${_rst}" = "YES" ] \
    || [ ! -d "${_hd}/sites" ] || [ -L "${_hd}/sites" ] \
    || [ ! -f "${_hd}/drush.yml" ] || [ -L "${_hd}/drush.yml" ] \
    || [ "$(cat "${_mark}" 2>/dev/null)" != "${_sum}" ]; then
    _need=YES
  fi
  [ "${_need}" = "YES" ] || return 0
  [ -d /var/backups/ltd/.aliases ] || mkdir -p /var/backups/ltd/.aliases
  chmod 0700 /var/backups/ltd/.aliases
  rm -f "${_mark}"
  chattr -i "${_hd}" 2>/dev/null
  chage -M 99999 "${_acct}" &> /dev/null
  timeout -k 10 300 su -s /bin/bash - "${_acct}" <<'EOF' &> /dev/null
cd "${HOME}" || exit 1
rm -rf .drush/sites .drush/drush.yml
mkdir -p .drush/sites
printf '%s\n' 'drush:' '  paths:' '    alias-path:' "      - '\${env.HOME}/.drush/sites'" > .drush/drush.yml
drush10 site:alias-convert "${HOME}/.drush/sites" --yes
EOF
  _rc=$?
  chage -M 90 "${_acct}" &> /dev/null
  chattr +i "${_hd}" 2>/dev/null
  if [ "${_rc}" -eq 0 ] \
    && { ! compgen -G "${_hd}/*.alias.drushrc.php" > /dev/null \
      || compgen -G "${_hd}/sites/*.site.yml" > /dev/null; }; then
    echo "${_sum}" > "${_mark}"
    echo "Drush 9+ alias store rebuilt for ${_acct}"
  else
    _ltd_notice "platform-aliasstore-${_acct}" \
      "Drush 9+ alias store for ${_acct} not built (rc ${_rc})" \
      "retried on the next pass; vdrush @alias has no aliases meanwhile"
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
  # tools/drush is oN's: a FIFO or link there must not hold or steer root
  _CHECK_USE_PHP_CLI=$(_ltd_read_in "${_DRUSH_FILE%/*}" "${_DRUSH_FILE##*/}" | grep "/opt/php" 2>&1)
  _PHP_V="85 84 83 82 81 80 74 73 72 71 70 56"
  for e in ${_PHP_V}; do
    if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]] \
      && [ ! -e "${_U_HD}/.ctrl.php${e}.${_xSrl}.pid" ]; then
      _PHP_CLI_UPDATE=YES
    fi
  done
  # oN owns /data/disk/oN, so .tmp and .drush (never a link in BOA's own
  # layout) can be swapped for a link at any time: a link takes the rebuild,
  # which strips it; the age sweep never resolves a path through a name
  # (bare path, -execdir); owners change by name only with chown -h; every
  # other remove and write, the CLI ini and both stamps included, happens
  # inside the real directory
  if [ -L "${_U_HD}" ] || [ -L "${_U_TP}" ] \
    || [ "${_PHP_CLI_UPDATE}" = "YES" ] \
    || [ ! -e "${_U_II}" ] \
    || [ ! -d "${_U_TP}" ] \
    || [ ! -e "${_U_HD}/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
    _desymlink_planted "${_U_TP}" "${_U_HD}"
    mkdir -p ${_U_TP} ${_U_HD}
    if _ltd_in_real_dir "${_U_TP}" _ltd_own_dir_here "${_USER}:${_usrGroup}" 755 YES \
      && _ltd_in_real_dir "${_U_HD}" _ltd_own_dir_here "${_USER}:${_usrGroup}" 755 NO; then
      # a literal list: a ${_PHP_V} split by a changed IFS would match nothing
      _U_INI=""
      for e in 85 84 83 82 81 80 74 73 72 71 70 56; do
        if [[ "${_CHECK_USE_PHP_CLI}" =~ "php${e}" ]]; then
          _U_INI="${e}"
          break
        fi
      done
      _ltd_in_real_dir "${_U_HD}" _ltd_drush_ini_put_locked "${_U_INI}" "${_U_TP}"
    else
      echo "ALERT: ${_U_TP} or ${_U_HD} is not ${_USER}'s own directory; its CLI ini left as it was"
    fi
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
  _T_CLI=/foo/bar
  case "${_T_CLI_VRN}" in
    8.5|8.4|8.3|8.2|8.1|8.0|7.4|7.3|7.2|7.1|7.0|5.6)
      if [ -x "/opt/php${_T_CLI_VRN/./}/bin/php" ]; then
        _T_CLI="/opt/php${_T_CLI_VRN/./}/bin"
        # tools/drush is oN's: the shebang is edited inside the real
        # directory, and only on a regular file (sed -i through a link
        # would put a copy of its target in its place)
        _ltd_in_real_dir "${_dscUsr}/tools/drush" _ltd_sed_here \
          "${_DRUSH_FILE##*/}" "s/^#\!\/.*/#\!\/opt\/php${_T_CLI_VRN/./}\/bin\/php/g"
      fi
      ;;
  esac
  if [ -x "${_T_CLI}/php" ]; then
    #_DRUSH_HOSTING_TASKS_CMD="/usr/bin/drush @hostmaster hosting-tasks --force"
    _DRUSH_HOSTING_DISPATCH_CMD="${_T_CLI}/php ${_dscUsr}/tools/drush/drush.php @hostmaster hosting-dispatch"
    # aegir.sh sits in oN's own home: put in place as a fresh file inside the
    # real directory, never through a link at the name
    _ltd_in_real_dir "${_dscUsr}" _ltd_aegir_sh_put "$(echo -e "#!/bin/bash\n\nPATH=.:${_T_CLI}:/usr/sbin:/usr/bin:/sbin:/bin\n \
      \n${_DRUSH_HOSTING_DISPATCH_CMD} \
      \ntouch ${_dscUsr}/${_USER}-task.done" | fmt -su -w 2500)"
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
      _ltd_in_real_dir "${_dscUsr}/tools/drush" _ltd_sed_here drush.launcher \
        "1s/^#\!.*/#\!\/bin\/bash/"
      _ltd_in_real_dir "${_dscUsr}/tools/drush" _ltd_sed_here drush.launcher \
        "/^export DRUSH_PHP=/d"
      _ltd_in_real_dir "${_dscUsr}/tools/drush" _ltd_sed_here drush.launcher \
        "1a export DRUSH_PHP=\"\${DRUSH_PHP:-${_T_CLI}/php}\""
    fi
  fi
  _ltd_ctrl_rm '.ctrl.cli.*.pid'
  _ltd_ctrl_stamp ".ctrl.cli.${_T_CLI_VRN}.${_xSrl}.pid" "${_T_CLI_VRN}"
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
      _CLIENT_CORES=$(_ltd_read_in "${_dscUsr}/log" cores.txt)
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
  _LOC_NEW_RELIC_KEY=$(_ltd_ctrl_read newrelic.info)
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
# The web user's CLI ini and its stamp, inside the real ~/.drush. While the
# directory is still immutable no name in it can change, so the ini is
# unlocked first; the ini is edited in root's own temp directory and put in
# place once, created 0440, so no name the web user can swap is opened or
# chmod-ed. $1 = the source ini (empty: none), $2 = its version digits,
# $3 = the web user's ~/.tmp.
_ltd_web_ini_put() {
  local _src="${1}" _v="${2}" _qtp="${3//\//\\\/}" _w=""
  [ -f ./php.ini ] && [ ! -L ./php.ini ] && chattr -i ./php.ini 2> /dev/null
  chattr -i . 2> /dev/null
  [ -n "${_src}" ] && [ -e "${_src}" ] || return 0
  _w=$(mktemp -d 2> /dev/null) || return 0
  [ -n "${_w}" ] && [ -d "${_w}" ] || return 0
  if cp -f -- "${_src}" "${_w}/php.ini" 2> /dev/null; then
    # open_basedir stays out of the CLI ini: it breaks Drush and turns the
    # realpath cache off (every file operation checked against every listed
    # tree, uncached); lshell users are confined by their own measures, and
    # the FPM ini keeps its own list
    sed -i "s/.*open_basedir =.*/;open_basedir =/g"                      "${_w}/php.ini"
    wait
    sed -i "s/.*session.save_path =.*/session.save_path = ${_qtp}/g"     "${_w}/php.ini"
    wait
    sed -i "s/.*soap.wsdl_cache_dir =.*/soap.wsdl_cache_dir = ${_qtp}/g" "${_w}/php.ini"
    wait
    sed -i "s/.*sys_temp_dir =.*/sys_temp_dir = ${_qtp}/g"               "${_w}/php.ini"
    wait
    sed -i "s/.*upload_tmp_dir =.*/upload_tmp_dir = ${_qtp}/g"           "${_w}/php.ini"
    wait
    if ( umask 0337
      cp -T --no-preserve=mode --remove-destination "${_w}/php.ini" ./php.ini ) 2> /dev/null; then
      rm -f -- ./.ctrl.php*
      _ltd_stamp_put ".ctrl.php${_v}.${_xSrl}.pid" ""
    fi
  fi
  rm -f -- "${_w}/php.ini"
  rmdir -- "${_w}" 2> /dev/null
  return 0
}
# The web user's ~/.drush locked again inside the real directory: the
# directory first, after which no name in it can change, then a regular
# php.ini.
_ltd_web_drush_lock() {
  chmod 550 .
  chattr +i . 2> /dev/null
  [ -f ./php.ini ] && [ ! -L ./php.ini ] && chattr +i ./php.ini 2> /dev/null
  return 0
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
      # can plant these names, and plant them again once they are stripped:
      # after the strip every write, mode and chattr inside ~/.drush happens
      # in the real directory, the ini is edited in root's own temp directory
      # and put in place once, and the lock and the stamp are created
      # exclusively, never through a link at the name.
      _desymlink_planted "/home/${_WEB}/.drush" "/home/${_WEB}/.tmp" \
        "/home/${_WEB}/.aws" "${_T_II}"
      mkdir -p /home/${_WEB}/.{tmp,drush,aws}
      _ltd_in_real_dir "/home/${_WEB}" _ltd_stamp_put .lock ""
      _isTest="$1"
      _isTest=${_isTest//[^a-z0-9]/}
      if [ ! -z "${_isTest}" ]; then
        _T_PV=$1
      fi
      _T_SRC=""
      if [ ! -z "${_T_PV}" ] && [ -e "/opt/php${_T_PV}/etc/php${_T_PV}.ini" ]; then
        _T_SRC="/opt/php${_T_PV}/etc/php${_T_PV}.ini"
      else
        for e in 85 84 83 82 81 80 74 73 72 71 70 56; do
          if [ -e "/opt/php${e}/etc/php${e}.ini" ]; then
            _T_SRC="/opt/php${e}/etc/php${e}.ini"
            _T_PV=${e}
            break
          fi
        done
      fi
      _ltd_in_real_dir "${_T_HD}" _ltd_web_ini_put "${_T_SRC}" "${_T_PV}" "${_T_TP}"
      chmod 700 /home/${_WEB}
      chown -R ${_WEB}:${_WEBG} /home/${_WEB}
      _ltd_in_real_dir "${_T_HD}" _ltd_web_drush_lock
      rm -f /home/${_WEB}/.lock
      if [ -d "/home/${_WEB}" ]; then
        chattr +i /home/${_WEB}
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
        chattr -i /home/${_WEB}/.drush
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

  # log/ is oN's: read without following a link or blocking on a FIFO, and
  # the panel name reaches the sed below as host name characters only (a
  # slash there would end the s/// and let the rest run as sed commands)
  _hmFront=$(_ltd_read_in "${_dscUsr}/log" domain.txt | tr -d "\n")
  _hmFront=${_hmFront//[^a-zA-Z0-9.-]/}
  _hmstAls="${_dscUsr}/.drush/${_hmFront}.alias.drushrc.php"

  _hmstCli=$(_ltd_read_in "${_dscUsr}/log" cli.txt | tr -d "\n")
  _hmstCli=${_hmstCli//[^0-9.]/}

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
  # multi-fpm.info is the main login's: read without following a link or
  # blocking on a FIFO, edited here and put back as a fresh file (sed -i and
  # >> would write through a link put at the name, and sed -i would put a
  # copy of its target there, which the chown below hands to the tenant)
  _mltFpmBody="$(_ltd_ctrl_read multi-fpm.info)"
  _PLACEHOLDER_TEST=$(grep "place.holder.dont.remove" <<< "${_mltFpmBody}" 2>&1)

  if [ ! -e "${_dscUsr}/log/no-lock-aegir-fpm.txt" ] \
    || [[ ! "${_PLACEHOLDER_TEST}" =~ "place.holder.dont.remove" ]]; then
    _PHP_V="85 84 83 82 81 74"
    _phpFnd=NO
    _mltFpmAdd=""
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
        [ -d "${_dscUsr}/static/control" ] && _mltFpmAdd="place.holder.dont.remove ${_phpDot}"
        _phpFnd=YES
      fi
    done
    # a young account has no multi-fpm.info yet (the agents pass writes it
    # later): it stays absent when no PHP binary was found above
    if [ -f "${_mltFpm}" ] || [ -n "${_mltFpmAdd}" ]; then
      _mltFpmBody="$( { sed -e "s/^${_hmFront} .*//g" \
          -e "s/^place.holder.dont.remove .*//g" <<< "${_mltFpmBody}"
        [ -n "${_mltFpmAdd}" ] && echo "${_mltFpmAdd}"; } \
        | sed -e "s/ *$//g" -e "/^$/d")"
      _ltd_ctrl_put multi-fpm.info "${_mltFpmBody}"
    fi
    _ltd_put_in "${_dscUsr}/log" no-lock-aegir-fpm.txt ""
    _ltd_rm_in "${_dscUsr}/log" locked-aegir-fpm.txt
    _ltd_put_in "${_dscUsr}/log" unlocked-aegir-fpm.txt ""
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
    _ltd_in_real_dir "${_dscUsr}/static/control" _ltd_ctrl_info_owner
    _mltFpmBody="$(_ltd_ctrl_read multi-fpm.info)"
    _mltFpmUpdate=NO
    if [ ! -f "${_preFpm}" ]; then
      _ltd_in_real_dir "${_dscUsr}/static/control" rm -rf -- ./.prev-multi-fpm.info
      _ltd_ctrl_put .prev-multi-fpm.info "${_mltFpmBody}"
    fi
    _diffFpmTest=$(diff -w -B <(printf '%s\n' "${_mltFpmBody}") \
      <(_ltd_ctrl_read .prev-multi-fpm.info) 2>&1)
    if [ ! -z "${_diffFpmTest}" ]; then
      _mltFpmUpdate=YES
    fi
    # A pin with no include yet (its site, its PHP version or its pool socket
    # did not exist when the includes were last built) forces one rebuild in
    # the pass it becomes applicable: the baseline alone kept it inert until
    # the file changed, pins from before this check included. A line that
    # never applies (a typo) costs a few stats, no rebuild.
    local _sN _sV _sR
    while read -r _sN _sV _sR; do
      _sN=${_sN//[^a-zA-Z0-9-.]/}
      _sN=${_sN,,}
      _sV=${_sV//[^0-9]/}
      [ -n "${_sN}" ] && [ -n "${_sV}" ] || continue
      [ "${_sN}" = "place.holder.dont.remove" ] && continue
      [ -e "${_fpmPth}/fpm_include_site_${_sN}.inc" ] && continue
      if [ -x "/opt/php${_sV}/bin/php" ] \
        && [ -e "${_dscUsr}/.drush/${_sN}.alias.drushrc.php" ] \
        && [ -e "/run/${_USER}.${_sV}.fpm.socket" ]; then
        _mltFpmUpdateForce=YES
      fi
    done <<< "${_mltFpmBody}"
    # While a whole-server move's promotion window is open on this box (the
    # standby marker plus the fresh in-flight signal), the per-site includes
    # are left exactly as found. The rename running in that window rewrites
    # the pin names and deliberately keeps a stale baseline, so this pass
    # would wipe and rebuild every include of the account -- and the box may
    # already be serving relayed visitors, for whom a pinned site dropping to
    # the account's default PHP version for even one pass is an outage. The
    # move runs this pass itself, once, as soon as its renames are done.
    # Scoped to this block on purpose: the rest of the script must keep
    # running on a standby, and a steady mirror (no fresh signal) still
    # builds its includes as pins arrive.
    if [ -e "/root/.standby.cnf" ] \
      && [ -n "$(find /run/boa_xmass_init.pid /root/.standby.init.pid -mmin -2880 2>/dev/null)" ]; then
      _mltFpmUpdate=HOLD
    elif [ ! -f "${_mltNgx}" ] \
      || [ "${_mltFpmUpdate}" = "YES" ] \
      || [ "${_mltFpmUpdateForce}" = "YES" ]; then
      _ltd_rm_in "${_fpmPth}" 'fpm_include_site_*'
      # local: a bare IFS= here stayed a newline for the rest of the pass,
      # and every later "for x in ${list}" saw one word
      local IFS=$'\12'
      _mltFpmSkip=""
      for p in ${_mltFpmBody};do
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
          _ltd_put_in "${_fpmPth}" "fpm_include_site_${_SITE_NAME}.inc" \
            "if ( \$main_site_name = ${_SITE_NAME} ) {"$'\n'"  set \$user_socket \"${_SOCKET_L_NAME}\";"$'\n'"}"
        elif [ -n "${_SITE_NAME}" ] && [ -n "${_SITE_SOCKET}" ] \
          && [ "${_SITE_NAME}" != "place.holder.dont.remove" ]; then
          _mltFpmSkip="${_mltFpmSkip}${_SITE_NAME} ${_SITE_SOCKET}"$'\n'
        fi
      done
      # the skipped lines, for the tenant to see; the check above retries them
      if [ -n "${_mltFpmSkip}" ]; then
        _ltd_ctrl_put .multi-fpm-skipped.info "${_mltFpmSkip}"
      else
        _ltd_ctrl_rm .multi-fpm-skipped.info
      fi
      _ltd_ctrl_stamp .multi-nginx-fpm.pid ""
      _ltd_in_real_dir "${_dscUsr}/static/control" rm -rf -- ./.prev-multi-fpm.info
      _ltd_ctrl_put .prev-multi-fpm.info "${_mltFpmBody}"
      ### reload nginx -- only a config that passes its own test: a failed
      ### reload keeps the running config, but an invalid one left on disk
      ### turns the next unrelated restart into a box-wide outage
      if nginx -t &> /dev/null; then
        service nginx reload &> /dev/null
      else
        _ltd_notice "nginx-configtest-${_USER}" \
          "nginx -t FAILED after the per-site FPM includes of ${_USER} were rebuilt -- NOT reloaded" \
          "$(nginx -t 2>&1 | tail -3 | tr '\n' ' ')"
      fi
    fi
  else
    if [ -f "${_mltNgx}" ]; then
      _ltd_ctrl_rm .multi-nginx-fpm.pid
    fi
    if [ -f "${_preFpm}" ]; then
      _ltd_ctrl_rm .prev-multi-fpm.info
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
      # static/control is tenant-owned, log/ and config/ are oN's: +i is
      # cleared only on regular files inside the real directories, never on
      # whatever a planted link points at.
      _ltd_in_real_dir "${_dscUsr}/static/control" _ltd_unlock_here fpm.info cli.info
      _ltd_in_real_dir "${_dscUsr}/log" _ltd_unlock_here fpm.txt cli.txt
      _ltd_in_real_dir "${_dscUsr}/config/server_master/nginx/post.d" \
        _ltd_unlock_here fpm_include_default.inc
      _ltd_put_in "${_dscUsr}/log" un-chattr-ctrl.info ""
    fi

    if [ ! -e "${_dscUsr}/static/control/.single-fpm.${_xSrl}.pid" ]; then
      _ltd_ctrl_rm '.single-fpm*.pid'
      _ltd_ctrl_stamp ".single-fpm.${_xSrl}.pid" "OK"
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

    # One known version per control file (8.3 or 83), as the docs promise;
    # anything else -- a second line, a patch level, a word -- is ignored.
    # The reads below join the lines of a file, so without this gate
    # '8.3' + '8.4' became '8.38.4': a pool name that deleted the account's
    # pools in single-FPM mode and a dead default socket in multi-FPM mode.
    _ltd_php_vrn_ok() {
      case "${1}" in
        8.5|8.4|8.3|8.2|8.1|8.0|7.4|7.3|7.2|7.1|7.0|5.6) return 0 ;;
      esac
      return 1
    }

    # --- CLI portion ---
    if [ -e "${_dscUsr}/static/control/cli.info" ]; then
      # Extract numeric version from file
      _T_CLI_VRN="$(_ltd_ctrl_read cli.info | tr -d '\n' | tr -cd '0-9.')"

      # Convert shorthand versions (e.g. "83" to "8.3")
      _T_CLI_VRN="$(fix_version_format "${_T_CLI_VRN}")"
      if [ -n "${_T_CLI_VRN}" ] && ! _ltd_php_vrn_ok "${_T_CLI_VRN}"; then
        echo "ALRT: cli.info of ${_USER} is not one PHP version, ignored"
        _T_CLI_VRN=""
      fi

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
            _ltd_put_in "${_dscUsr}/log" cli.txt "${_T_CLI_VRN}"
            _ltd_ctrl_put cli.info "${_T_CLI_VRN}"
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
          _ltd_ctrl_rm '.multi-fpm*.pid'
          _ltd_ctrl_stamp ".multi-fpm.${_xSrl}.pid" "OK"
          _FORCE_FPM_SETUP=YES
        fi
      else
        if [ -e "${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc" ]; then
          _ltd_rm_in "${_dscUsr}/config/server_master/nginx/post.d" 'fpm_include_*'
          _ltd_ctrl_rm '.multi-fpm*.pid'
          service nginx reload &> /dev/null
        fi
      fi

      # Read and sanitize the FPM version
      _T_FPM_VRN=$(_ltd_ctrl_read fpm.info | tr -d '\n' | tr -cd '0-9.')

      # Convert shorthand versions (e.g. "83" to "8.3")
      _T_FPM_VRN="$(fix_version_format "${_T_FPM_VRN}")"
      if [ -n "${_T_FPM_VRN}" ] && ! _ltd_php_vrn_ok "${_T_FPM_VRN}"; then
        echo "ALRT: fpm.info of ${_USER} is not one PHP version, ignored"
        _T_FPM_VRN=""
      fi
      # An instance an earlier pass already poisoned (a joined version in its
      # octopus.cnf) is set up again on the default version below.
      if [ -z "${_T_FPM_VRN}" ] && [ -n "${_PHP_FPM_VERSION}" ] \
        && ! _ltd_php_vrn_ok "${_PHP_FPM_VERSION}"; then
        echo "ALRT: _PHP_FPM_VERSION of ${_USER} is not one PHP version, set up again on 8.4"
        _T_FPM_VRN=8.4
      fi

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
      if [ -z "${_PHP_SV}" ]; then
        # An ignored or unresolvable fpm.info keeps the version the instance
        # already runs, rather than moving its default pool to 8.4.
        if _ltd_php_vrn_ok "${_PHP_FPM_VERSION}" \
          && [ -x "/opt/php${_PHP_FPM_VERSION//./}/bin/php" ]; then
          _PHP_SV=${_PHP_FPM_VERSION//./}
        else
          _PHP_SV=84
        fi
      fi
      _FMP_D_INC="${_dscUsr}/config/server_master/nginx/post.d/fpm_include_default.inc"

      if [ "${_PHP_FPM_MULTI}" = "YES" ] && [ -d "${_dscUsr}/tools/le" ]; then
        _PHP_M_V="85 84 83 82 81 80 74 73 72 71 70 56"
        _D_POOL="${_USER}.${_PHP_SV}"
        if [ ! -e "${_FMP_D_INC}" ]; then
          _ltd_put_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}" "set \$user_socket \"${_D_POOL}\";"
          _ltd_ctrl_stamp ".multi-fpm.${_xSrl}.pid" ""
          _NEW_FPM_SETUP=YES
        else
          _CHECK_FMP_D=$(_ltd_read_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}" | grep "${_D_POOL}" 2>&1)
          if [[ ! "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]]; then
            echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
            _ltd_put_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}" "set \$user_socket \"${_D_POOL}\";"
            _ltd_ctrl_stamp ".multi-fpm.${_xSrl}.pid" ""
            _NEW_FPM_SETUP=YES
          fi
        fi
      else
        _PHP_M_V="${_PHP_SV}"
        _ltd_ctrl_rm '.multi-fpm*.pid'
        _ltd_rm_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}"
      fi

      if [ -n "${_T_FPM_VRN}" ] && [ "${_NEW_FPM_SETUP}" = "YES" ]; then
        _satellite_tune_fpm_workers
        sed -i "s/^_PHP_FPM_VERSION=.*/_PHP_FPM_VERSION=${_T_FPM_VRN}/g" /root/.${_USER}.octopus.cnf &> /dev/null
        _ltd_put_in "${_dscUsr}/log" fpm.txt "${_T_FPM_VRN}"
        if [ "${_PHP_FPM_MULTI}" = "NO" ]; then
          _ltd_ctrl_put fpm.info "${_T_FPM_VRN}"
        else
          _ltd_in_real_dir "${_dscUsr}/static/control" \
            chown -h "${_USER}.ftp:${_usrGroup}" ./fpm.info
        fi

        _PHP_OLD_SV=${_PHP_FPM_VERSION//[^0-9]/}
        _PHP_SV=${_T_FPM_VRN//[^0-9]/}
        [ -z "${_PHP_SV}" ] && _PHP_SV=84

        # Update or create special system user if needed
        if [ "${_PHP_FPM_MULTI}" = "YES" ] && [ -d "${_dscUsr}/tools/le" ]; then
          _PHP_M_V="85 84 83 82 81 80 74 73 72 71 70 56"
          _D_POOL="${_USER}.${_PHP_SV}"
          if [ ! -e "${_FMP_D_INC}" ] && [ -e "/run/${_D_POOL}.fpm.socket" ] && [ -x "/opt/php${_PHP_SV}/bin/php" ]; then
            _ltd_put_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}" "set \$user_socket \"${_D_POOL}\";"
            _ltd_ctrl_stamp ".multi-fpm.${_xSrl}.pid" ""
          else
            _CHECK_FMP_D=$(_ltd_read_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}" | grep "${_D_POOL}" 2>&1)
            if [[ ! "${_CHECK_FMP_D}" =~ "${_D_POOL}" ]] && [ -e "/run/${_D_POOL}.fpm.socket" ] && [ -x "/opt/php${_PHP_SV}/bin/php" ]; then
              echo "${_D_POOL} must be updated in ${_FMP_D_INC}"
              _ltd_put_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}" "set \$user_socket \"${_D_POOL}\";"
              _ltd_ctrl_stamp ".multi-fpm.${_xSrl}.pid" ""
            fi
          fi
        else
          _PHP_M_V="${_PHP_SV}"
          _ltd_ctrl_rm '.multi-fpm*.pid'
          _ltd_rm_in "${_FMP_D_INC%/*}" "${_FMP_D_INC##*/}"
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
              _OLD_PHP_IN_USE=$(_ltd_read_in "/home/${_WEB}/.drush" php.ini | grep "/lib/php" 2>&1)
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

  # The main login owns ~/.drush (its home is never immutable): every remove
  # and copy into it below runs inside the real directory (_ltd_in_real_dir),
  # never through a link at its name into another alias store.
  local _ftpD="/home/${_USER}.ftp/.drush"
  _desymlink_planted "${_ftpD}"
  _ALS_TEST=$(ls -la /home/${_USER}.ftp/.drush/*.alias.drushrc.php 2>&1)
  if [[ ! "${_ALS_TEST}" =~ "No such file" ]]; then
    for _Alias in `find /home/${_USER}.ftp/.drush/*.alias.drushrc.php \
      -maxdepth 1 -type f | sort`; do
      _AliasFile=$(echo "${_Alias}" | cut -d'/' -f5 | awk '{ print $1}' 2>&1)
      if [ ! -e "${_pthParentUsr}/.drush/${_AliasFile}" ] \
        && [ ! -z "${_AliasFile}" ]; then
        _ltd_in_real_dir "${_ftpD}" rm -f -- "./${_AliasFile}"
     fi
    done
  fi

  _ltd_in_real_dir "${_ftpD}" rm -f -- ./hm.alias.drushrc.php \
    ./self.alias.drushrc.php
  # an alias name that is not a regular file (a FIFO, a device link, a
  # directory) is never root's to open: the diff below reads every copy
  _ltd_in_real_dir "${_ftpD}" find . -maxdepth 1 \
    -name '*.alias.drushrc.php' ! -type f -exec rm -rf {} + 2> /dev/null
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
        _SiteDir=$(_ltd_read_in "${_pthParentUsr}/.drush" "${_Alias##*/}" \
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
          _pthAliasCopy="./${_SiteName}.alias.drushrc.php"
          # Root-written control file in the tenant's own home: strip a plant at
          # its name, then compare and copy inside the pinned ~/.drush (see
          # _ltd_alias_put). Only the copy -- the main alias may be a link.
          _ltd_in_real_dir "${_ftpD}" _desymlink_planted "${_pthAliasCopy}"
          if ! _ltd_in_real_dir "${_ftpD}" \
            _ltd_alias_same "${_pthAliasMain}" "${_pthAliasCopy}"; then
            # The stores are rebuilt only for a copy that landed; one that
            # cannot land in an existing ~/.drush (a directory swapped in after
            # the sweep) is reported. A first pass may run before ~/.drush exists.
            if _ltd_in_real_dir "${_ftpD}" \
              _ltd_alias_put "${_pthAliasMain}" "${_pthAliasCopy}"; then
              _isAliasUpdate=YES
            elif [ -d "${_ftpD}" ] && [ ! -L "${_ftpD}" ]; then
              _ltd_notice "alias-copy-${_USER}-${_SiteName}" \
                "alias copy for ${_USER}.ftp not written" "${_SiteName}"
            fi
          fi
        else
          # drushrc.php absent = ghost candidate. This runs every 3 minutes, so a
          # mid-install/clone site (alias written before its dir is populated)
          # MUST NOT be reaped: skip while an Ægir task is in flight, and while
          # the alias is recently written (< 60 min). Then gate on the opt-in
          # _GHOST_ALIASES_CLEANUP flag (no night.inc.sh here, so check inline).
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
                _ltd_in_real_dir "${_ftpD}" rm -f -- "./${_SiteName}.alias.drushrc.php"
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
  # The copy compare above sees site aliases only. The stores are also rebuilt
  # when no finished rebuild is on record for the instance's drushrc aliases,
  # names and content: a platform or server alias added, changed or deleted,
  # or a site deleted. The record is root's own and never taken from a store
  # listing. The limited-shell copy is also rebuilt when it holds alias
  # copies but no yml alias (a conversion there failed, or the tenant emptied
  # it); an account with no sites has nothing to convert and never needs it.
  # Neither trigger fires again within the hour for the same aliases, so a
  # store that keeps failing costs one rebuild an hour. The records sit in a
  # dot directory: the nightly age prune of /var/backups/ltd/*/* never
  # reaches it.
  local _aliasSetDir="/var/backups/ltd/.stores"
  local _aliasSetMark="${_aliasSetDir}/${_USER}.md5"
  local _aliasSetTry="${_aliasSetDir}/${_USER}.try"
  local _aliasSetSum=""
  local _aliasSetWhy=""
  local _aliasSetErr=""
  local _aliasSetRc=0
  _aliasSetSum=$(_ltd_in_real_dir "${_pthParentUsr}/.drush" _ltd_alias_set_sum)
  if [ "${_isAliasUpdate}" != "YES" ] && [ -n "${_aliasSetSum}" ]; then
    if [ "$(cat "${_aliasSetMark}" 2>/dev/null)" != "${_aliasSetSum}" ]; then
      _aliasSetWhy="no finished rebuild on record for the current drushrc aliases"
    elif compgen -G "${_ftpD}/*.alias.drushrc.php" > /dev/null \
      && ! compgen -G "${_ftpD}/sites/*.site.yml" > /dev/null; then
      _aliasSetWhy="the limited-shell store holds no yml alias"
    fi
    if [ -n "${_aliasSetWhy}" ] \
      && [ "$(cat "${_aliasSetTry}" 2>/dev/null)" = "${_aliasSetSum}" ] \
      && [ -n "$(find "${_aliasSetTry}" -mmin -60 2>/dev/null)" ]; then
      _aliasSetWhy=""
    fi
  fi
  # The alias-store rebuild wipes and regenerates ~/.drush/sites from the
  # drushrc aliases -- on a standby those arrive by rsync mid-window, and
  # a rebuild against a half-landed set bakes the gaps in. Scoped gate:
  # everything above (users, inis, pools) already ran.
  if [ -x "/usr/bin/drush10" ] && [ "${_GHOST_REAPED}" != "YES" ] \
    && [ ! -e "/root/.standby.cnf" ]; then
    if [ "${_isAliasUpdate}" = "YES" ] || [ -n "${_aliasSetWhy}" ]; then
      [ -n "${_aliasSetWhy}" ] \
        && echo "Alias stores of ${_USER}: ${_aliasSetWhy}; rebuilding"
      # Recorded before the stores are wiped, so a pass killed mid-rebuild
      # leaves no record of a finished one; the try record holds a retry of
      # the same aliases to once an hour.
      [ -d "${_aliasSetDir}" ] || mkdir -p "${_aliasSetDir}"
      chmod 0700 "${_aliasSetDir}"
      rm -f "${_aliasSetMark}"
      if [ -n "${_aliasSetSum}" ] \
        && ! echo "${_aliasSetSum}" > "${_aliasSetTry}"; then
        _aliasSetErr="${_aliasSetTry} could not be written"
      fi
      chage -M 99999 ${_USER}.ftp &> /dev/null
      su -s /bin/bash - ${_USER}.ftp -c "rm -f ~/.drush/sites/*.yml"
      wait
      su -s /bin/bash - ${_USER}.ftp -c "rm -f ~/.drush/sites/.checksums/*.md5"
      wait
      timeout -k 10 300 su -s /bin/bash - ${_USER}.ftp -c "drush10 core:init --yes" &> /dev/null
      wait
      timeout -k 10 300 su -s /bin/bash - ${_USER}.ftp -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
      wait
      chage -M 90 ${_USER}.ftp &> /dev/null
      ### Update Drush yml sites aliases also for Ægir system user
      su -s /bin/bash - ${_USER} -c "rm -f ~/.drush/sites/*.yml"
      wait
      su -s /bin/bash - ${_USER} -c "rm -f ~/.drush/sites/.checksums/*.md5"
      wait
      timeout -k 10 300 su -s /bin/bash - ${_USER} -c "drush10 core:init --yes" &> /dev/null
      wait
      timeout -k 10 300 su -s /bin/bash - ${_USER} -c "drush10 site:alias-convert ~/.drush/sites --yes" &> /dev/null
      _aliasSetRc=$?
      wait
      # The rebuild is recorded as finished only when the instance's own store
      # converted and holds its yml aliases (the limited-shell copy is the
      # tenant's to break).
      if [ -z "${_aliasSetSum}" ]; then
        _ltd_notice "aliasstores-${_USER}" \
          "Drush 9+ alias stores of ${_USER}: ${_pthParentUsr}/.drush is not a real directory" \
          "rebuilt only when a site alias changes until it is"
      elif [ -n "${_aliasSetErr}" ]; then
        :
      elif [ "${_aliasSetRc}" -eq 124 ]; then
        _aliasSetErr="drush10 site:alias-convert timed out"
      elif [ "${_aliasSetRc}" -eq 137 ]; then
        _aliasSetErr="drush10 site:alias-convert timed out or was killed"
      elif [ "${_aliasSetRc}" -ne 0 ]; then
        _aliasSetErr="drush10 site:alias-convert exited ${_aliasSetRc}"
      elif compgen -G "${_pthParentUsr}/.drush/*.alias.drushrc.php" > /dev/null \
        && ! compgen -G "${_pthParentUsr}/.drush/sites/*.site.yml" > /dev/null; then
        _aliasSetErr="the conversion wrote no yml alias"
      elif ! echo "${_aliasSetSum}" > "${_aliasSetMark}"; then
        _aliasSetErr="${_aliasSetMark} could not be written"
      fi
      if [ "${_aliasSetErr}" = "${_aliasSetTry} could not be written" ]; then
        _ltd_notice "aliasstores-${_USER}" \
          "Drush 9+ alias stores of ${_USER}: ${_aliasSetErr}" \
          "rebuilt on every pass until it can be"
      elif [ -n "${_aliasSetErr}" ]; then
        _ltd_notice "aliasstores-${_USER}" \
          "Drush 9+ alias stores of ${_USER} not rebuilt: ${_aliasSetErr}" \
          "retried after an hour, or on the next pass when an alias changes"
      fi
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
      # A revert instgrp could not finish (an identity in use when its
      # primary group had to move back) names the identities in this record;
      # finish it here, one idle pass at a time, and never read such an
      # account as converted meanwhile -- the heal below would otherwise move
      # its other identities back ONTO the group the operator is reverting.
      _igPend="/var/log/boa/instgrp.revert-pending.${_USER}"
      if [ -s "${_igPend}" ]; then
        _igLeft=""
        for _igU in $(cat "${_igPend}" 2>/dev/null); do
          case "${_igU}" in "${_USER}"|"${_USER}".*) ;; *) continue ;; esac
          getent passwd "${_igU}" >/dev/null 2>&1 || continue
          if [ "$(id -gn ${_igU} 2>/dev/null)" = "users" ]; then
            _ig_defer_clear "${_igU}"
            continue
          fi
          getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_igU}" || usermod -aG users ${_igU}
          _set_primary_group ${_igU} users
          _pgRc=$?
          if [ "${_pgRc}" = "2" ]; then
            _ig_defer_note "${_igU}" users "Identity ${_igU} has processes running; its move back to primary group users (a revert instgrp could not finish) waits for an idle pass"
            _igLeft="${_igLeft} ${_igU}"
          elif [ "$(id -gn ${_igU} 2>/dev/null)" = "users" ]; then
            _ig_defer_clear "${_igU}"
            gpasswd -d ${_igU} ${_USER} >/dev/null 2>&1
            echo "Identity ${_igU} moved back to primary group users; the revert of ${_USER} instgrp left unfinished is completed for it"
            echo "$(date '+%Y-%m-%d %H:%M:%S') ${_USER}: ${_igU} primary group -> users (revert finished by the limited-shell worker)" >> /var/log/boa/instgrp.log
          else
            echo "ALERT: ${_igU} could not be moved back to primary group users; left on $(id -gn ${_igU} 2>/dev/null), retried next pass"
            _igLeft="${_igLeft} ${_igU}"
          fi
        done
        if [ -z "${_igLeft}" ]; then
          rm -f "${_igPend}"
          echo "$(date '+%Y-%m-%d %H:%M:%S') ${_USER}: PENDING MOVE BACK COMPLETED by the limited-shell worker (a revert, or the rollback of a failed convert); instgrp revert ${_USER} removes the group, instgrp convert ${_USER} converts again" >> /var/log/boa/instgrp.log
          mkdir -p /var/log/boa 2>/dev/null
          echo "$(date) LTD instgrp: every identity of ${_USER} is back on users (a revert, or the rollback of a failed convert, found it in use); instgrp revert ${_USER} removes the group, instgrp convert ${_USER} converts again" \
            >> /var/log/boa/manage_ltd.incident.log
        fi
      elif [ -n "${_igGid}" ]; then
        if [ -f "${_igMark}" ] && [ ! -L "${_igMark}" ] && grep -q " gid=${_igGid}$" "${_igMark}" 2>/dev/null; then
          _igConv=YES
        elif [ "$(id -gn ${_USER} 2>/dev/null)" = "${_USER}" ] || [ "$(id -gn ${_USER}.ftp 2>/dev/null)" = "${_USER}" ]; then
          _igConv=YES
        fi
      fi
      if [ "${_igConv}" = "YES" ]; then
        for _igU in ${_USER} ${_USER}.ftp; do
          getent passwd "${_igU}" >/dev/null 2>&1 || continue
          if [ "$(id -gn ${_igU} 2>/dev/null)" = "${_USER}" ]; then
            # Already there (a move instgrp or an earlier pass finished): no
            # deferral is open for it any more.
            _ig_defer_clear "${_igU}"
            continue
          fi
          if ! getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_igU}"; then
            usermod -aG users ${_igU}
          fi
          if getent group users | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_igU}"; then
            _set_primary_group ${_igU} ${_USER}
            _pgRc=$?
            if [ "${_pgRc}" = "2" ]; then
              _ig_defer_note "${_igU}" "${_USER}" "Identity ${_igU} has processes running; its move back to primary group ${_USER} waits for an idle pass"
            elif [ "$(id -gn ${_igU} 2>/dev/null)" = "${_USER}" ] \
              && id -nG ${_igU} 2>/dev/null | tr ' ' '\n' | grep -qxF users; then
              # Listed as a member too: provision's membership test reads
              # the group database, where a primary group never shows.
              getent group ${_USER} | cut -d: -f4 | tr ',' '\n' | grep -qxF "${_igU}" || gpasswd -a ${_igU} ${_USER} >/dev/null 2>&1
              _ig_defer_clear "${_igU}"
              echo "Identity ${_igU} moved back to primary group ${_USER}"
            elif [ "$(id -gn ${_igU} 2>/dev/null)" = "${_USER}" ]; then
              if _set_primary_group ${_igU} users; then
                echo "ALERT: ${_igU} lost group users on the primary move, reverted to users"
              else
                echo "ALERT: ${_igU} lost group users on the primary move and could not be reverted yet; retried next pass"
              fi
            else
              echo "ALERT: ${_igU} could not be moved to primary group ${_USER}; left on $(id -gn ${_igU} 2>/dev/null)"
            fi
          fi
        done
      fi
      # Group owning this account's tree, re-derived every iteration so no
      # value carries over to the next account. Falls back to the box-wide
      # default on an account that has no private group.
      # While a revert is unfinished the account identity itself is usually
      # the one still on the account's group, which _acct_group would read as
      # converted: this pass then writes and moves with the box-wide group,
      # as the revert intends, instead of pushing the sub-users back onto it.
      if [ -s "${_igPend}" ]; then
        _usrGroup=users
      else
        _usrGroup=$(_acct_group "${_USER}")
      fi
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
        # src/ and log/ are oN's: each marker is read and removed inside the
        # real log/ and written fresh inside the real src/
        for _mvPid in imported exported hmpathfix post-merge-fix; do
          _ltd_in_real_dir "${_dscUsr}/src" _ltd_log_marker_to_src "${_mvPid}.pid"
        done
      fi
      # Composer project leftovers at the account root, and a vendor/ directly
      # in ~/static, can break Aegir backend tasks and the D8+ sites below
      # them: removed unless rector.php marks a Rector workspace. Composer's
      # own home and cache stay: Aegir tasks and builds run Composer as this
      # user, and a pass that removed them under a running Composer failed its
      # install.
      if [ ! -e "${_dscUsr}/rector.php" ]; then
        rm -f ${_dscUsr}/*.php* &> /dev/null
        rm -f ${_dscUsr}/composer.lock &> /dev/null
        rm -f ${_dscUsr}/composer.json &> /dev/null
        rm -f -r ${_dscUsr}/vendor &> /dev/null
        rm -f -r ${_dscUsr}/static/vendor &> /dev/null
      fi
      # every root write under /data/disk/<oN> refuses a path with a link on
      # it (BOA makes none at these names): say so once a day, not silently
      for _pinChk in static log config tools clients src; do
        if [ -L "${_dscUsr}/${_pinChk}" ] \
          && [ -z "$(find "/var/log/boa/manage-ltd-pinlink-${_USER}-${_pinChk}.alerted" -mmin -1440 2> /dev/null)" ]; then
          _ltd_notice "pinlink-${_USER}-${_pinChk}" \
            "${_dscUsr}/${_pinChk} is a link: the ltd worker writes nothing there" \
            "BOA makes no link at this name; put the real directory back"
        fi
      done
      _ltd_in_real_dir "${_dscUsr}/.drush" _ltd_drush_alias_modes &> /dev/null
      # config/ is oN's: the tree is walked from inside the real directory
      # and every mode goes through a handle that never follows a link (a
      # link at passwords.d/<x> would have made its target world-readable)
      _ltd_in_real_dir "${_dscUsr}/config/server_master" \
        find . -type d -execdir perl -e "${_LTD_FCHMOD_PL}" d 0700 {} + &> /dev/null
      _ltd_in_real_dir "${_dscUsr}/config/server_master" \
        find . -type f -execdir perl -e "${_LTD_FCHMOD_PL}" f 0600 {} + &> /dev/null
      for _cfgDir in config config/server_master config/server_master/nginx \
        config/server_master/nginx/passwords.d; do
        _ltd_in_real_dir "${_dscUsr}/${_cfgDir}" \
          perl -e "${_LTD_FCHMOD_PL}" d +0555 . &> /dev/null
      done
      _ltd_in_real_dir "${_dscUsr}/config/server_master/nginx/passwords.d" \
        _ltd_chmod_nofollow_here +0444
      # .tmp is oN's to swap too: a link there always takes this block, which
      # strips it (a stamp read through the link could skip it), and every
      # remove, mode and stamp happens inside the real directory
      if [ -L "${_dscUsr}/.tmp" ] \
        || [ ! -e "${_dscUsr}/.tmp/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
        _ltd_in_real_dir "${_dscUsr}/.drush" _ltd_drush_cache_drop "${_USER}"
        _desymlink_planted "${_dscUsr}/.tmp"
        mkdir -p ${_dscUsr}/.tmp
        if _ltd_in_real_dir "${_dscUsr}/.tmp" \
          _ltd_own_dir_here "${_USER}:${_usrGroup}" 02755 YES; then
          _ltd_in_real_dir "${_dscUsr}/.tmp" \
            _ltd_stamp_put ".ctrl.${_tRee}.${_xSrl}.pid" "OK"
        else
          echo "ALERT: ${_dscUsr}/.tmp is not ${_USER}'s own directory; left as it was"
        fi
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
        _ltd_in_real_dir "${_dscUsr}/static/control" _ltd_ctrl_init
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

      _THIS_HM_PLR=$(_ltd_read_in "${_dscUsr}/.drush" hostmaster.alias.drushrc.php \
        | grep "root'" \
        | cut -d: -f2 \
        | awk '{ print $3}' \
        | sed "s/[\,']//g" 2>&1)
      if [ -e "${_THIS_HM_PLR}/modules/path_alias_cache" ] \
        && [ -x "/opt/tools/drush/8/drush/drush.php" ]; then
        if [ -x "/opt/php56/bin/php" ]; then
        _desymlink_planted "${_dscUsr}/static/control/cli.info"
        _ltd_ctrl_put cli.info 5.6
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
        # clients/ is oN's: a client name there can be a link to anywhere,
        # so the removals run inside the real directories only
        _ltd_in_real_dir "${_pthParentUsr}/clients" _ltd_clients_sweep &> /dev/null
        # dangling links go by a walk from inside the real directory (symlinks
        # -r rebuilds absolute paths as it walks, so a name swapped
        # meanwhile would redirect it)
        _ltd_in_real_dir "${_pthParentUsr}/clients" find . -xtype l -delete &> /dev/null
        if [ -d "/home/${_USER}.ftp" ]; then
          _disable_chattr ${_USER}.ftp
          _ltd_in_real_dir "/home/${_USER}.ftp" find . -xtype l -delete &> /dev/null
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
            # the main login owns users/ and every name in it: the modes are
            # set inside the real directory, each store through a handle that
            # never follows a link put at its name
            chown -R ${_USER}.ftp:${_usrGroup} /home/${_USER}.ftp/users
            _ltd_in_real_dir "/home/${_USER}.ftp/users" chmod 700 .
            _ltd_in_real_dir "/home/${_USER}.ftp/users" \
              _ltd_chmod_nofollow_here 600
          fi
          if [ ! -L "/home/${_USER}.ftp/static" ]; then
            rm -f /home/${_USER}.ftp/{backups,clients,static}
            ln -sfn ${_dscUsr}/backups /home/${_USER}.ftp/backups
            ln -sfn ${_dscUsr}/clients /home/${_USER}.ftp/clients
            ln -sfn ${_dscUsr}/static  /home/${_USER}.ftp/static
          fi
          if [ ! -e "/home/${_USER}.ftp/.tmp/.ctrl.${_tRee}.${_xSrl}.pid" ]; then
            # the main login's home is never immutable: inside ~/.drush and
            # ~/.tmp root works only in the real directories
            _ltd_in_real_dir "/home/${_USER}.ftp/.drush" rm -rf -- ./cache
            rm -rf /home/${_USER}.ftp/.tmp
            mkdir -p /home/${_USER}.ftp/.tmp
            chown -h ${_USER}.ftp:${_usrGroup} /home/${_USER}.ftp/.tmp &> /dev/null
            _ltd_in_real_dir "/home/${_USER}.ftp/.tmp" chmod 700 . &> /dev/null
            _ltd_in_real_dir "/home/${_USER}.ftp/.tmp" \
              _ltd_stamp_put ".ctrl.${_tRee}.${_xSrl}.pid" "OK"
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
          # a link at ~/.drush (a main login's home is never immutable) must
          # not aim chattr at <target>/usr: locked inside the real directory
          _ltd_in_real_dir "${_homedir}/.drush" _ltd_drush_lock_here
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
  # When the PREVIOUS pass ran, read before this one stamps it: a deferral
  # stamp stops advancing either because its episode ended, or because no
  # pass ran at all -- a BOA run holds this worker off for the whole of its
  # pass, an hour and more. Missing (the first pass after an upgrade): take
  # now, so the wall-clock rule alone applies. .txt, not .pid or .log: those
  # two are what the /var/log/boa sweeps match.
  _LTD_PREV_PASS=$(stat -c %Y /var/log/boa/manage-ltd-pass.txt 2>/dev/null)
  _LTD_PREV_PASS=${_LTD_PREV_PASS:-$(date +%s)}
  touch /var/log/boa/manage-ltd-pass.txt
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
  # lshell 0.10 (kept where python3 is older than 3.10) appends env_path to
  # PATH raw, no separator, gluing it onto the last entry; it also never
  # checks that a command exists, which is all the line is for on 0.11
  if lshell --version 2>&1 | grep -q "lshell-0\.10"; then
    sed -i "/^env_path[[:space:]]*:/d" ${_THIS_LTD_CONF}
    wait
  fi
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
  # -type f refuses a planted link, and the mode goes through a handle that
  # never follows one, so a tenant swapping its own name after find's lstat
  # gains nothing. A young box has no log yet, hence no bare glob (it printed
  # "cannot access").
  find /var/log/lsh -maxdepth 1 -type f \
    -execdir perl -e "${_LTD_FCHMOD_PL}" f 0600 {} + 2>/dev/null
  _ltd_in_real_dir /var/aegir/.drush _ltd_drush_alias_modes &> /dev/null
  _ltd_in_real_dir /var/aegir/config/server_master \
    find . -type d -execdir perl -e "${_LTD_FCHMOD_PL}" d 0700 {} + &> /dev/null
  _ltd_in_real_dir /var/aegir/config/server_master \
    find . -type f -execdir perl -e "${_LTD_FCHMOD_PL}" f 0600 {} + &> /dev/null
  sleep 5
  _drush_ini_open_basedir_sweep
  _standby_tenant_sweep
  [ -e "/run/manage_ltd_users.pid" ] && rm -f /run/manage_ltd_users.pid
  exit 0
fi

