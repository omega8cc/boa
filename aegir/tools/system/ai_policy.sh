#!/bin/bash

# ai_policy.sh — per-site AI bot policy, GLOBAL across all Octopus instances.
#
# Abstraction of the per-Octopus nginx_ip_access_<oct>.sh pattern: a single
# script that loops over every Octopus instance under /data/disk/<oct> which has
# an ACTIVATED control file at /data/disk/<oct>/static/control/ai/policy.txt, and
# for each generates per-site nginx fragments into that instance's own
# /data/disk/<oct>/config/includes/ai_policy/<site>.conf — exactly the path the
# per-satellite vhost pulls via `include $server->include_path/ai_policy/<uri>.conf*`.
#
# Control records: `<site>  [train-allow] [evasive-allow] [search-block] [user-block] [utility-block]`
# turning the global AI default (training + evasive blocked; search/user/utility
# allowed + rate-limited) on/off for that site:
#   train-allow    -> set $ai_train_allow 1;            (allow AI training)
#   evasive-allow  -> set $ai_evasive_allow 1;          (allow evasive user-fetch, e.g. Perplexity)
#   search-block   -> if ($is_ai_search)  { return 444; }
#   user-block     -> if ($is_ai_user)    { return 444; }
#   utility-block  -> if ($is_ai_utility) { return 444; }
# A site with no record keeps the global defaults.  No SSH/server-IP anti-lockout
# logic — that is an ip_access (IP allow/deny) concern, irrelevant to AI classes.

# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy) never overlap their
# configtest+reload; wait up to 30s, then skip this run and retry next tick.
_lock_file="/run/boa_nginx_config.lock"
# Bump when the emitted directive shape changes, to force regeneration
# independent of the control-file mtime.
_emit_version="2"
_site_name_regex="^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}$"

# Re-entrancy guard for the whole global run.
exec 9>"${_lock_file}" 2>/dev/null
if ! flock -w 30 9; then
  echo "Could not acquire the shared nginx-config lock; skipping this run."
  exit 0
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx not installed; nothing to do."
  exit 0
fi


# A held web tier (replication standby) makes `service nginx reload` return
# rc 7 forever, and the revert branch below would then rewrite this instance's
# backup tarball into the SYNCED undo/ tree on every 2-minute pass -- a
# permanent mirror-side divergence, because the sync legs are rsync -u and the
# mirror's copy is always the newer one. On a held standby: keep the generated
# fragments (they are correct on disk and activate when promotion starts
# nginx), advance the change-gate markers as a success would, and skip both
# the reload and the revert.
_nginx_held_down() {
  # The nginx watchdog's published verdict: the promoted latch. Absent means
  # HELD, and here "held" only ever means "write the fragments, skip the
  # reload and the revert" -- an unjudged box costs a deferred reload, never
  # a write into the synced undo/ trees on a box whose nginx is down.
  [ -e "/root/.standby.cnf" ] && [ ! -e "/root/.standby.serve.cnf" ] \
    && [ ! -e "/var/log/boa/.standby_promoted.pid" ]
}

# oN owns /data/disk/oN (config/, undo/ and every directory in them), so any
# name there can be a link or a FIFO, and any directory on the way can itself
# be a link. Root reads and writes those names only through these, inside the
# real directory; the control file is copied once from its own real
# directory, and the fragments and archives are made in a root-only work
# directory in /run first. The last-good archive in undo/ is oN's to replace:
# it is copied out without following a link, unpacked with no owner and no
# mode taken from it and only whole within 32 MiB, and only a regular file
# with a fragment's name is put back.
#
# Run "$@" inside the real directory $1, never one reached through a link an
# account planted on the way (helper.sh.inc).
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
# ./$1 in the current (pinned) directory with the content $2 (0644): a
# fresh file created exclusively, then renamed over the name, so a link or a
# FIFO put at the name is replaced, never followed or opened.
_acct_put_here() {
  local _t="./.${1}.put.$$.${RANDOM}"
  rm -f -- "${_t}"
  ( umask 022
    printf '%s\n' "${2}" | dd of="${_t}" conv=excl status=none 2> /dev/null ) \
    && mv -f -T -- "${_t}" "./${1}" && return 0
  rm -f -- "${_t}"
  return 1
}
# stdin as the fresh file $1, owned by uid $2 and gid $3 with the mode $4,
# through the one handle that created it O_EXCL|O_NOFOLLOW (helper.sh.inc).
_ACCT_PUT_PL='use Fcntl; my ($n, $u, $g, $m) = @ARGV; local $/; my $d = <STDIN>; sysopen(my $h, $n, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1; (print {$h} $d) or exit 1; chown($u, $g, $h) or exit 1; chmod(oct($m) & 0666, $h) or exit 1; close($h) or exit 1; exit 0'
# The file $1 (root's own) put as ./$2 in the current (pinned) directory,
# root's and 0644: written under a fresh name through one handle
# (_ACCT_PUT_PL), then renamed over the name, so a link or a FIFO at the name
# is replaced, never written through or opened; a directory there, which the
# rename cannot replace, is removed first.
_conf_put_file_here() {
  local _t="./.${2}.put.$$.${RANDOM}"
  rm -f -- "${_t}"
  if [ -d "./${2}" ] && [ ! -L "./${2}" ]; then
    rm -rf -- "./${2}"
  fi
  if perl -e "${_ACCT_PUT_PL}" "${_t}" 0 0 644 < "${1}" \
    && mv -f -T -- "${_t}" "./${2}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
# Each source and destination pair on stdin (NUL-separated) after a byte
# cap $1: the source opened without following a link or blocking on a
# FIFO, and copied only while that handle is a regular file of at most $1
# bytes, into the fresh destination (0600, never through a link), which a
# write that fails (a full /run) removes again. Exit 1 when a pair was not
# copied.
_ACCT_COPY_PL='use Fcntl; my $c = shift; local $/ = "\0"; my $rc = 0; while (defined(my $i = <STDIN>)) { my $o = <STDIN>; defined $o or last; chomp($i); chomp($o); my $ok = 0; if (sysopen(my $h, $i, O_RDONLY|O_NOFOLLOW|O_NONBLOCK)) { my @s = stat($h); if (@s && -f _ && $s[7] <= $c) { my ($d, $b, $n) = (""); while ($n = sysread($h, $b, 1048576)) { $d .= $b; last if length($d) > $c; } if (defined $n && length($d) <= $c && sysopen(my $w, $o, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600)) { $ok = (print {$w} $d) && close($w); unlink($o) unless $ok; } } close($h); } $rc = 1 unless $ok; } exit $rc'
# ./$1 in the current (pinned) directory copied into the root-only file $2
# as _ACCT_COPY_PL copies, whole within 32 MiB. Status 1 when it was not.
_acct_copy_here() {
  rm -f -- "${2}"
  printf '%s\0' "./${1}" "${2}" | perl -e "${_ACCT_COPY_PL}" 33554432
}
# The names $2... of the current (pinned) directory copied under their own
# names into the root-only directory $1 as _ACCT_COPY_PL copies, each whole
# within 1 MiB; a name that is not copied is left out.
_acct_copies_here() {
  local _d="${1}" _n
  shift
  for _n in "$@"; do
    printf '%s\0' "./${_n}" "${_d}/${_n}"
  done | perl -e "${_ACCT_COPY_PL}" 1048576
  return 0
}
# The first line of the root-only file $2 (nothing when there is none) put
# in the variable named $1.
_line_get() {
  local _l=""
  [[ -f "${2}" ]] && IFS= read -r _l < "${2}"
  printf -v "${1}" '%s' "${_l}"
}
# Each name and value pair given put in the current (pinned) directory as
# _acct_put_here puts it. Status 1 when one was not.
_acct_put_pairs_here() {
  local _rc=0
  while [[ $# -ge 2 ]]; do
    _acct_put_here "$1" "$2" || _rc=1
    shift 2
  done
  return "${_rc}"
}
# Every regular file with a single link and a fragment's name (<site>.conf,
# <site>.http.conf, <site>.srv.conf) in the root-only directory $1 put under
# its own name in the current (pinned) directory, each map (*.http.conf)
# before the gate (*.srv.conf) that reads it, and no gate whose map was not
# put. Anything else in $1 is left where it is. Status 1 when $1 is not a
# real directory or a file was not put.
_confs_put_here() {
  local _p _s _n _bad=" " _rc=0
  [[ -d "${1}" && ! -L "${1}" ]] || return 1
  for _p in maps rest; do
    for _s in "${1}"/*.conf; do
      _n="${_s##*/}"
      if [[ "${_n}" == *.http.conf ]]; then
        [[ "${_p}" == "maps" ]] || continue
      else
        [[ "${_p}" == "rest" ]] || continue
      fi
      [[ -f "${_s}" && ! -L "${_s}" ]] || continue
      [[ "$(stat -c %h -- "${_s}" 2> /dev/null)" == "1" ]] || continue
      [[ "${_n%.conf}" =~ ${_site_name_regex} ]] || continue
      if [[ "${_n}" == *.srv.conf && "${_bad}" == *" ${_n%.srv.conf} "* ]]; then
        _rc=1
        continue
      fi
      if ! _conf_put_file_here "${_s}" "${_n}"; then
        _rc=1
        [[ "${_n}" != *.http.conf ]] || _bad="${_bad}${_n%.http.conf} "
      fi
    done
  done
  return "${_rc}"
}
# Every ./*.conf of the current (pinned) directory removed, the gates
# (*.srv.conf) before the maps they read. Prints yes when there was one.
_confs_drop_here() {
  local _f _any=""
  for _f in ./*.srv.conf ./*.conf; do
    [[ -e "${_f}" ]] || continue
    rm -f -- "${_f}"
    _any="yes"
  done
  [[ -z "${_any}" ]] || echo "yes"
}
# Every ./*.conf of the current (pinned) directory that is not kept removed,
# the gates (*.srv.conf) first: $1 = what the log calls one, $2 = where, $3 =
# the suffix a kept name leaves off, then the kept names.
_prune_here() {
  local _what="$1" _where="$2" _x="$3" _f _base _keep _s
  shift 3
  for _f in ./*.srv.conf ./*.conf; do
    [[ -e "${_f}" ]] || continue
    _base="${_f#./}"
    _base="${_base%"${_x}"}"
    _keep=""
    for _s in "$@"; do
      [[ "${_s}" == "${_base}" ]] && _keep="yes" && break
    done
    if [[ -z "${_keep}" ]]; then
      rm -f -- "${_f}"
      echo "Pruned stale ${_what}: ${_base}${_x} (${_where})"
    fi
  done
}
# The names $2... of the current (pinned) directory packed as they are (a
# link stays a link, never followed; holes skipped, not read) into the
# root-only file $1, whole within 60 seconds and 32 MiB. Status 1 otherwise.
_snap_here() {
  local _o="${1}" _rc
  shift
  timeout 60 tar --sparse -czf - -- "$@" 2> /dev/null | head -c 33554433 > "${_o}"
  _rc="${PIPESTATUS[0]}"
  [[ "${_rc}" == "0" || "${_rc}" == "1" ]] || return 1
  [[ "$(stat -c %s -- "${_o}" 2> /dev/null || echo 33554433)" -le 33554432 ]]
}
# The names $4... of the real directory $1 packed as _snap_here packs them,
# then put as $3 in the real directory $2.
_snap_store() {
  local _s="${1}" _d="${2}" _n="${3}"
  shift 3
  rm -f -- "${_work}/snap.tgz"
  _acct_in_real_dir "${_s}" _snap_here "${_work}/snap.tgz" "$@" \
    && _acct_in_real_dir "${_d}" _conf_put_file_here "${_work}/snap.tgz" "${_n}"
}
# The members $4... of the root-only directory $1 packed, proved readable,
# then put as $3 in the real directory $2. Status 1 when one step failed.
_lg_store() {
  local _s="${1}" _d="${2}" _n="${3}"
  shift 3
  rm -f -- "${_s}.tgz"
  tar -czf "${_s}.tgz" -C "${_s}" -- "$@" 2> /dev/null \
    && tar -tzf "${_s}.tgz" &> /dev/null \
    && _acct_in_real_dir "${_d}" _conf_put_file_here "${_s}.tgz" "${_n}"
}
# The archive $1 (root's own copy) unpacked into the fresh root-only
# directory $2: names and contents only, never an owner or a mode, and only
# when it unpacks whole within 32 MiB, counted as the files it made would
# be written out, holes included. Status 1 otherwise.
_lg_unpack() {
  local _rc _sz
  rm -rf -- "${2}" "${2}.tar"
  mkdir -m 0700 -- "${2}" || return 1
  gzip -dc < "${1}" 2> /dev/null | head -c 33554433 > "${2}.tar"
  _rc="${PIPESTATUS[0]}"
  [[ "${_rc}" == "0" ]] || return 1
  [[ "$(stat -c %s -- "${2}.tar" 2> /dev/null || echo 33554433)" -le 33554432 ]] || return 1
  tar -tf "${2}.tar" &> /dev/null \
    && tar -xf "${2}.tar" -C "${2}" --no-same-owner --no-same-permissions &> /dev/null \
    || return 1
  _sz="$(du -sbl -- "${2}" 2> /dev/null | cut -f1)"
  [[ "${_sz}" =~ ^[0-9]+$ ]] && [[ "${_sz}" -le 33554432 ]]
}
# The last-good archive $2 of the real directory $1 copied out as
# _acct_copy_here copies and unpacked as _lg_unpack unpacks into $3.
# Status 1 when it is not there whole.
_lg_fetch() {
  _acct_in_real_dir "${1}" _acct_copy_here "${2}" "${3}.tgz" \
    && _lg_unpack "${3}.tgz" "${3}"
}

_work="$(mktemp -d /run/.ai_policy.XXXXXX 2> /dev/null)" \
  || { echo "Cannot create a work directory in /run; skipping this run."; exit 1; }
trap 'rm -rf -- "${_work}"' EXIT

_process_instance() {
  local _root="$1"
  local _input_file="${_root}/static/control/ai/policy.txt"
  local _ai_path="${_root}/config/includes/ai_policy"
  local _backup_dir="${_root}/undo"
  local _current_name=".nginx_ai_policy.current.bak.tar.gz"
  local _last_good_name=".nginx_ai_policy.last_good.bak.tar.gz"
  local _last_good_backup="${_backup_dir}/${_last_good_name}"
  local _new="${_work}/new" _ctrl="${_work}/ctrl" _mk="${_work}/mk"

  # Only instances with an activated control file and a real includes dir.
  [[ -f "${_input_file}" ]] || return 0
  [[ -d "${_root}/config/includes" ]] || return 0

  # Change-gate: control-file mtime + emit version. The markers are copied
  # out of their real directory in one pass; one that is not there, not a
  # regular file, or in a directory that is not real reads as none, and so
  # does a time that is not a number: it is compared as a number.
  local _current_mod_time _last_mod_time _last_version
  _current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null) || return 0
  rm -rf -- "${_mk}"
  mkdir -m 0700 -- "${_mk}" || return 1
  _acct_in_real_dir "${_ai_path}" _acct_copies_here "${_mk}" .policy_last_mod_time .emit_version
  _line_get _last_mod_time "${_mk}/.policy_last_mod_time"
  [[ "${_last_mod_time}" =~ ^[0-9]+$ ]] || _last_mod_time=0
  _line_get _last_version "${_mk}/.emit_version"
  if [[ "${_current_mod_time}" -le "${_last_mod_time}" && "${_last_version}" == "${_emit_version}" ]]; then
    return 0
  fi

  _acct_in_real_dir "${_root}/config/includes" mkdir -p ./ai_policy 2> /dev/null
  _acct_in_real_dir "${_root}" mkdir -p ./undo 2> /dev/null
  if ! _acct_in_real_dir "${_ai_path}" true || ! _acct_in_real_dir "${_backup_dir}" true; then
    echo "ai_policy/ or undo/ of ${_root} is not a real directory; skipped."
    return 0
  fi
  # The control file is read only as the copy taken from its real directory.
  if ! _acct_in_real_dir "${_input_file%/*}" _acct_copy_here "${_input_file##*/}" "${_ctrl}"; then
    echo "The control file of ${_root} is not a regular file in a real directory; skipped."
    return 0
  fi

  # Back up the instance's current fragments before regenerating.
  _snap_store "${_ai_path}" "${_backup_dir}" "${_current_name}" .

  # Generate fragments; track configured sites for pruning. The work dir is
  # 0755 so the last-good archive packed from it carries the mode the live
  # directory has.
  local -a _configured=()
  local _line _flag _site _body
  rm -rf -- "${_new}"
  mkdir -m 0755 -- "${_new}" || return 1
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -ra _fields <<< "${_line}"
    _site=$(echo "${_fields[0]}" | tr '[:upper:]' '[:lower:]')
    if [[ ! ${_site} =~ ${_site_name_regex} ]]; then
      echo "Invalid site name: ${_site} (${_root}). Skipping."
      continue
    fi
    _body=""
    for _flag in "${_fields[@]:1}"; do
      case "${_flag}" in
        train-allow)   _body+="set \$ai_train_allow 1;"$'\n' ;;
        evasive-allow) _body+="set \$ai_evasive_allow 1;"$'\n' ;;
        search-block)  _body+="if (\$is_ai_search)  { return 444; }"$'\n' ;;
        user-block)    _body+="if (\$is_ai_user)    { return 444; }"$'\n' ;;
        utility-block) _body+="if (\$is_ai_utility) { return 444; }"$'\n' ;;
        *) echo "Unknown policy flag '${_flag}' for ${_site} (${_root}). Skipping flag." ;;
      esac
    done
    if [[ -z "${_body}" ]]; then
      echo "No valid policy flags for ${_site} (${_root}); no fragment written."
      continue
    fi
    {
      echo "# Generated by /var/xdrago/ai_policy.sh — DO NOT EDIT BY HAND."
      echo "# Per-site AI policy for ${_site}."
      printf '%s' "${_body}"
    } > "${_new}/${_site}.conf"
    _configured+=("${_site}")
  done < "${_ctrl}"

  if ! _acct_in_real_dir "${_ai_path}" _confs_put_here "${_new}"; then
    echo "Could not put every AI policy fragment in ${_ai_path}; retrying next run."
    return 1
  fi

  # Prune fragments for sites no longer present in the control file.
  _acct_in_real_dir "${_ai_path}" _prune_here "AI policy fragment" "${_root}" .conf \
    "${_configured[@]}"

  if _nginx_held_down; then
    _acct_in_real_dir "${_ai_path}" _acct_put_pairs_here \
      .policy_last_mod_time "${_current_mod_time}" .emit_version "${_emit_version}"
    echo "AI policy written (${_root}); replication standby -- reload skipped (web tier held)."
    return 0
  fi

  # Validate the whole host nginx config; revert THIS instance on failure.
  local _ct
  _ct=$(service nginx configtest 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Nginx configtest failed after AI policy update (${_root}): ${_ct}"
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_root} AI policy to last known good."
      _ai_revert "${_backup_dir}" "${_last_good_name}" "${_ai_path}"
      service nginx reload
    fi
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after AI policy update (${_root}); reverting."
    if [[ -f "${_last_good_backup}" ]]; then
      _ai_revert "${_backup_dir}" "${_last_good_name}" "${_ai_path}"
      service nginx reload
    fi
    return 1
  fi

  # Success: refresh this instance's last-good backup + change-gate markers.
  _lg_store "${_new}" "${_backup_dir}" "${_last_good_name}" .
  _acct_in_real_dir "${_ai_path}" _acct_put_pairs_here \
    .policy_last_mod_time "${_current_mod_time}" .emit_version "${_emit_version}"
  echo "AI policy updated (${_root}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
}

# The fragments in the real directory $3 replaced by those of the last-good
# archive $2 in the real directory $1; an archive that does not unpack whole
# leaves none.
_ai_revert() {
  local _ok=""
  _lg_fetch "${1}" "${2}" "${_work}/lg" && _ok="yes"
  _acct_in_real_dir "${3}" _confs_drop_here > /dev/null
  [[ -z "${_ok}" ]] || _acct_in_real_dir "${3}" _confs_put_here "${_work}/lg"
}

# Loop over every Octopus instance. Real instances carry tools/drush; the
# BOA-canonical instance test (see autosymlink) transparently skips every
# non-instance pseudo-dir (arch, all, legacy, global, static, custom, …).
for _root in /data/disk/*; do
  [[ -d "${_root}" && -e "${_root}/tools/drush" ]] || continue
  _process_instance "${_root}"
done

exit 0
