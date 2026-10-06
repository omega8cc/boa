#!/bin/bash

# ip_access.sh — per-site nginx IP allow/deny, GLOBAL across the Ægir master and
# every Octopus instance.  Abstraction of the per-Octopus
# nginx_ip_access_<oct>.sh scripts into one generator.
#
# For each context it reads a control file of `<site>  <ip…>` records and writes
# a per-site nginx include `<site>.conf` (a block of `allow <ip>;` lines + a
# final `deny all;`) into that context's config/includes/ip_access/, which the
# per-vhost template pulls via `include $server->include_path/ip_access/<uri>.conf*`.
# Each allowed entry may be an IPv4 or IPv6 address, with an optional CIDR prefix
# (this is a pure nginx allow/deny layer, no csf involvement, so both families and
# subnets are supported).  127.0.0.1, ::1, the server's own IPv4 and every
# currently logged-in inbound SSH peer (v4 or v6) are always allowed (anti-lockout),
# so an admin / the server can never be shut out.
#
# Control files:
#   master  : /var/aegir/control/ip/access.txt          (the sqladmin proxy)
#   octopus : /data/disk/<oct>/static/control/ip/access.txt
# A site removed from the control file has its fragment pruned (restriction
# lifted).  A deleted Octopus control file changes nothing: the lists stay as they
# are (a deletion does not travel to a mirror or a migration target, so it could
# only ever lift one box); remove a site's line or empty the file to lift it.
# A site frozen before the front copies existed gets one from its fragment.
# Record format: `example.com 203.0.113.2 10.0.0.0/8 2001:db8::/32`.
#
# HTTPS for a site without its own certificate arrives through the wildcard SSL
# front (nginx_wild_ssl.conf), which proxies to the site's :80 vhost, where the
# peer is always 127.0.0.1 -- an address the anti-lockout allows.  So once the
# deployed front includes them, each listed site with a rendered vhost also gets
# two front files in the context's ip_access_front/: <site>.http.conf (a geo of
# the same list and a $host map of the server names in the vhost that no other
# vhost on the box also serves) and <site>.srv.conf (the 403 gate), judged at
# the front against the real visitor.
# The ACME challenge and the MTA-STS policy stay open there, as in the vhosts.
# A control panel's HTTPS proxy in pre.d reaches its vhost from the box's own
# IPv4, which the anti-lockout also allows, so it includes the panel's <site>.conf
# itself and judges the real visitor there.

_aegir_health_check="/var/aegir/.drush/hm.alias.drushrc.php"
_drush_health_check="/var/aegir/drush/drush"
_server_ip_file="/root/.found_correct_ipv4.cnf"

# Bump when the emitted shape changes, to force regeneration independent of the
# control-file mtime. A context with no marker yet reads as a change.
_emit_version="2"

# The deployed front includes the front files only once it carries these lines;
# until then none are written, so a front deploy never meets an unvalidated one.
_front_conf="/var/aegir/config/server_master/nginx/pre.d/nginx_wild_ssl.conf"
_front_on=""
grep -qF 'ip_access_front/*.srv.conf' "${_front_conf}" 2>/dev/null && _front_on="yes"

# Accept an IPv4 or IPv6 address, each with an optional CIDR prefix length — the
# nginx access module (`allow`/`deny`) takes all four forms. The validators are a
# strict SUBSET of what nginx accepts (cross-checked against `nginx -t`), so a
# typo'd address (e.g. 192.168.1.300, 2001:db8::/129) is SKIPPED rather than
# emitted into an `allow` line: a loose check would pass an out-of-range value
# that nginx rejects at configtest, and because configtest validates the WHOLE
# config, one bad fragment would block reloads box-wide until the control file is
# corrected. An out-of-range octet / prefix / bad hextet fails here and is skipped.
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_ipv4="(${_ipv4_octet}\.){3}${_ipv4_octet}"
_ipv4_regex="^${_ipv4}(/(3[0-2]|[12][0-9]|[0-9]))?$"
_hex="[0-9A-Fa-f]{1,4}"
_ipv6_core="(\
(${_hex}:){7}${_hex}|\
(${_hex}:){1,7}:|\
(${_hex}:){1,6}:${_hex}|\
(${_hex}:){1,5}(:${_hex}){1,2}|\
(${_hex}:){1,4}(:${_hex}){1,3}|\
(${_hex}:){1,3}(:${_hex}){1,4}|\
(${_hex}:){1,2}(:${_hex}){1,5}|\
${_hex}:((:${_hex}){1,6})|\
:((:${_hex}){1,7}|:)|\
::(ffff(:0{1,4})?:)?(${_ipv4})|\
(${_hex}:){1,4}:(${_ipv4}))"
_ipv6_regex="^${_ipv6_core}(/(12[0-8]|1[01][0-9]|[0-9]?[0-9]))?$"
_site_name_regex="^([a-zA-Z0-9_-]+\.)*[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}$"
# The front map carries plain lowercased hostnames of at most 174 bytes (the
# exact-key ceiling of map_hash_bucket_size 192). A wildcard alias is skipped:
# at :80 an exact name elsewhere on the box beats it, while a front map would
# claim that other site's traffic. A skipped name only stays as it was; a
# malformed or oversized key would fail the box-wide configtest.
_host_max=174


# A held web tier (replication standby) makes `service nginx reload` return
# rc 7 forever, and the revert branch below would then rewrite this instance's
# backup tarball into the SYNCED undo/ tree on every 2-minute pass -- a
# permanent mirror-side divergence, because the sync legs are rsync -u and the
# mirror's copy is always the newer one. On a held standby: keep the generated
# fragments (correct on disk, they activate when promotion starts nginx),
# advance the change-gate markers as a success would, and skip both the reload
# and the revert.
_nginx_held_down() {
  # The nginx watchdog's published verdict: the promoted latch. Absent means
  # HELD, and here "held" only ever means "write the fragments, skip the
  # reload and the revert" -- an unjudged box costs a deferred reload, never
  # a write into the synced undo/ trees on a box whose nginx is down.
  [ -e "/root/.standby.cnf" ] && [ ! -e "/root/.standby.serve.cnf" ] \
    && [ ! -e "/var/log/boa/.standby_promoted.pid" ]
}

# oN owns /data/disk/oN (config/, undo/ and every directory in them), and the
# master's /var/aegir is aegir's, so any name there can be a link or a FIFO,
# and any directory on the way below /data/disk can itself be a link. Root
# reads and writes those names only through these, inside the real
# directory; the control file and the front copies are read only as copies
# taken there, and every rendered vhost as a copy that does not follow a
# link at its own name (vhost.d is the instance's own), none blocking on a
# FIFO, and the fragments, front copies and archives are made in a
# root-only work directory in /run first. The last-good archive in undo/ is
# the owner's to replace: it is copied out without following a link,
# unpacked with no owner and no mode taken from it and only whole within
# 32 MiB, and only a regular file with a fragment's name is put back.
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

# An ALRT for the operator: each line $3... printed, and once a day for the
# condition $1 a dated line with the subject $2 in
# /var/log/boa/nginx.incident.log and a mail to _MY_EMAIL unless
# _INCIDENT_REPORT is OFF. Cron discards this tool's output, so the printed
# lines alone reach nobody. The box config is read with grep: sourcing it
# would set its variables in this run. Each value is taken as sourcing sets
# it: the last definition, without the trailing " #..." comment the
# documented template puts after each setting.
_policy_alert() {
  local _stamp="/run/nginx_policy_alert.${1//[^a-zA-Z0-9._-]/_}" _sub="${2}"
  local _log="/var/log/boa/nginx.incident.log" _l _lvl _mail _host
  shift 2
  for _l in "$@"; do
    echo "ALRT: ${_l}"
  done
  [[ -z "$(find "${_stamp}" -mmin -1440 2> /dev/null)" ]] || return 0
  # a stamp that cannot be written fails open: the alert matters more
  touch "${_stamp}" 2> /dev/null
  mkdir -p "${_log%/*}" 2> /dev/null
  echo "$(date) ${_sub}: $*" >> "${_log}"
  _lvl="$(grep -E '^[[:space:]]*(export[[:space:]]+)?_INCIDENT_REPORT=' \
    /root/.barracuda.cnf 2> /dev/null | tail -n 1 \
    | sed -E 's/^[^=]*=//; s/[[:space:]]+#.*$//' | tr -cd 'A-Za-z')"
  _lvl="${_lvl^^}"
  [[ "${_lvl}" != "OFF" && "${_lvl}" != "NO" ]] || return 0
  _mail="$(grep -E '^[[:space:]]*(export[[:space:]]+)?_MY_EMAIL=' \
    /root/.barracuda.cnf 2> /dev/null | tail -n 1 \
    | sed -E 's/^[^=]*=//; s/[[:space:]]+#.*$//' | tr -d "\"' \\\\")"
  if [[ -z "${_mail}" ]] || ! command -v s-nail > /dev/null 2>&1; then
    return 0
  fi
  _host="$(tr -d '\n' < /etc/hostname 2> /dev/null)"
  [[ -n "${_host}" ]] || _host="$(hostname -f 2> /dev/null)"
  # the mailer, and a delivery it may leave running, never holds the shared
  # nginx-config lock (fd 9)
  printf '%s\n' "${_sub} on ${_host}" "" "$@" "" "Logged to ${_log}" "" "--" \
    "This email has been sent by a BOA nginx policy tool" \
    | s-nail -s "ALERT [${_host}]: ${_sub}" "${_mail}" > /dev/null 2>&1 9>&-
  return 0
}


_valid_ip() {
  local _ip="$1"
  [[ "${_ip}" =~ ${_ipv4_regex} ]] && return 0
  [[ "${_ip}" =~ ${_ipv6_regex} ]] && return 0
  return 1
}

# The server_name tokens of each vhost file given, unique per file, lowercased,
# and only those the front map may carry: a plain hostname (no wildcard, no
# regex name, no `_`) of at most _host_max bytes. One program serves the
# per-site read and the box-wide index, so the two can never parse apart. Files
# are read with getline: mawk ends the whole pass at a file argument it cannot
# open, and a vhost removed by a task between the glob and the read must only
# drop out of the count, never truncate it.
_names_awk='
function flush(   rest, seg, n, i, t, seen) {
  rest = buf
  while (match(rest, /server_name[ \t]+[^;]*;/)) {
    seg = substr(rest, RSTART + 11, RLENGTH - 12)
    rest = substr(rest, RSTART + RLENGTH)
    n = split(seg, tok, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      t = tolower(tok[i])
      if (t ~ /^([a-z0-9_-]+\.)+[a-z0-9_-]+$/ && length(t) <= max && !(t in seen)) {
        seen[t] = 1
        print t
      }
    }
  }
  buf = ""
}
BEGIN {
  for (a = 1; a < ARGC; a++) {
    buf = ""
    while ((getline line < ARGV[a]) > 0) {
      sub(/#.*/, "", line)
      buf = buf " " line
    }
    close(ARGV[a])
    flush()
  }
  exit
}
'

_site_hosts() {
  # The names nginx routes to a site that the front map may carry, from its
  # rendered vhost ($1), one per line. Read only as a copy that does not
  # follow a link at its own name or block on a FIFO (_ACCT_COPY_PL, at most
  # 1 MiB): a FIFO would hang the read under the shared lock. No file, no
  # names.
  local _c="${_work}/vhost.one"
  [[ -f "$1" ]] || return 0
  rm -f -- "${_c}"
  printf '%s\0' "$1" "${_c}" | perl -e "${_ACCT_COPY_PL}" 1048576 || return 0
  awk -v max="${_host_max}" "${_names_awk}" "${_c}" 2>/dev/null | sort -u
}

# name -> how many rendered vhost files on the box serve it; built by
# _build_owners at most once per run.
declare -A _host_owners=()
_owners_built=""

_ensure_owners() {
  # One pass over every rendered vhost on the box, and only when the front
  # takes copies and this context lists a site that has a vhost of its own.
  # Runs in the main shell, so the command substitutions after it inherit
  # the index. $1 = control file, $2 = the context's vhost.d dir.
  local _line _s _need=""
  [[ -n "${_front_on}" && -z "${_owners_built}" ]] || return 0
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -r _s _ <<< "${_line}"
    _s=$(echo "${_s}" | tr '[:upper:]' '[:lower:]')
    if [[ ${_s} =~ ${_site_name_regex} && -f "${2}/${_s}" ]]; then
      _need="yes"
      break
    fi
  done < "$1"
  [[ -n "${_need}" ]] || return 0
  _build_owners
}

_build_owners() {
  # The box-wide index itself, at most once per run and in the main shell.
  # Each rendered vhost is read only as a copy that does not follow a link
  # at its own name or block on a FIFO (_ACCT_COPY_PL, at most 1 MiB), 32
  # at a time, each batch parsed and removed before the next, so the copies
  # never take more of /run than one control file copy may; one that is not
  # copied drops out of the count, as one removed between the glob and the
  # read does.
  local _n _h _v _i=0 _j _c="${_work}/vhosts"
  local -a _all=()
  [[ -z "${_owners_built}" ]] || return 0
  _owners_built="yes"
  for _v in /var/aegir/config/server_master/nginx/vhost.d/* \
    /data/disk/*/config/server_master/nginx/vhost.d/*; do
    [[ -f "${_v}" ]] && _all+=("${_v}")
  done
  while read -r _n _h; do
    _host_owners["${_h}"]="${_n}"
  done < <(while [[ "${_i}" -lt "${#_all[@]}" ]]; do
      rm -rf -- "${_c}"
      mkdir -m 0700 -- "${_c}" || break
      _j=0
      for _v in "${_all[@]:${_i}:32}"; do
        _j=$((_j + 1))
        printf '%s\0' "${_v}" "${_c}/${_j}"
      done | perl -e "${_ACCT_COPY_PL}" 1048576
      _i=$((_i + 32))
      for _v in "${_c}"/*; do
        [[ -f "${_v}" ]] && printf '%s\0' "${_v}"
      done | xargs -0 -r awk -v max="${_host_max}" "${_names_awk}" 2>/dev/null
    done | sort | uniq -c
    rm -rf -- "${_c}")
}

_front_hosts() {
  # The names the front map may claim for a site: those of its vhost ($1)
  # that no other rendered vhost on the box also serves, compared without
  # case as nginx matches them. Aegir keeps aliases unique per instance only,
  # so a name another instance also carries is left out -- at :80 only one
  # of them wins it, and a front map must never hand one tenant's list to
  # another tenant's visitors.
  local _h
  _site_hosts "$1" | while IFS= read -r _h; do
    [[ "${_host_owners[${_h}]:-0}" == "1" ]] && echo "${_h}"
  done
}

_front_clear() {
  # A context the run skips keeps no front copies: the front includes every
  # instance's dir, and a copy nobody regenerates could go on claiming a name
  # that has since moved to another site. Its marker goes too, so the copies
  # are rebuilt when the context comes back. Each srv.conf goes before the
  # http.conf that defines its variables. $1 = front dir, $2 = its marker.
  local _any
  _any=$(_acct_in_real_dir "$1" _confs_drop_here)
  _acct_in_real_dir "${2%/*}" rm -f -- "./${2##*/}"
  [[ -n "${_any}" ]] || return 0
  echo "Dropped the front copies of a skipped context: $1"
  _nginx_held_down && return 0
  service nginx configtest &> /dev/null && service nginx reload
}

_front_keep_valid() {
  # A context whose control file is gone, or is not a regular file in a real
  # directory, keeps its lists exactly as they are, over HTTP and HTTPS
  # alike: a deletion never travels to a mirror or a migration target
  # (static/control is copied additively), so lifting here would lift one box
  # only and the lock would come back after a failover or cutover. To lift,
  # remove a site's line or empty the file. Nothing here writes a new copy,
  # so none of its own is ever dropped either: each host map follows the
  # names only its site's vhost serves, as the vhost fragments follow the
  # vhost they are included in. A new alias is covered on HTTPS as on HTTP, a
  # name that moved to another site leaves the map, and a site with no such
  # name left keeps an empty map (inert) that a later run can fill again.
  # $1 = front dir, $2 = the context's vhost.d dir, $3 = its front marker.
  # Each copy is read out (at most 1 MiB) and put back only inside the real
  # front dir, and only a copy this tool wrote is rewritten: its own first
  # line and one closed $host map of its own. Any other copy read out is
  # dropped, gate first, and a frozen list writes it again from its
  # fragment, so an account's own bytes never come back as root's file; a
  # copy that cannot be read out is left as it is.
  local _f _site _want _have _w="${_work}/keep" _changed=""
  for _f in "$1"/*.http.conf; do
    [[ -e "${_f}" ]] || continue
    _build_owners
    _site=$(basename "${_f}" .http.conf)
    _want=$(_front_hosts "$2/${_site}" | tr '\n' ' ')
    rm -rf -- "${_w}"
    mkdir -m 0700 -- "${_w}" || return 0
    _acct_in_real_dir "$1" _acct_copies_here "${_w}" "${_site}.http.conf"
    [[ -s "${_w}/${_site}.http.conf" ]] || continue
    if ! _have=$(awk -v h="# Generated by /var/xdrago/ip_access.sh — DO NOT EDIT BY HAND." '
        NR == 1 && $0 != h { bad = 1; exit }
        /^map \$host / { if (m++ || $0 !~ /^map \$host \$ipaf_h_[0-9a-f]+ \{$/) { bad = 1; exit }; p = 1; next }
        p && /^}/ { p = 0; c = 1; next }
        p && $2 == "1;" { print $1 }
        END { exit (bad || !c) }' "${_w}/${_site}.http.conf"); then
      _acct_in_real_dir "$1" rm -f -- "./${_site}.srv.conf" "./${_site}.http.conf"
      _changed="yes"
      echo "The front copy of ${_site} is not one this tool wrote; dropped"
      continue
    fi
    _have=$(printf '%s' "${_have}" | sort | tr '\n' ' ')
    [[ "${_want}" == "${_have}" ]] && continue
    if awk -v want="${_want}" '
        /^map \$host / { print; p = 1; next }
        p && /^}/ { n = split(want, w, " "); for (i = 1; i <= n; i++) print "  " w[i] " 1;"; p = 0; print; next }
        p && $2 == "1;" { next }
        { print }' "${_w}/${_site}.http.conf" > "${_w}/new" \
      && _acct_in_real_dir "$1" _conf_put_file_here "${_w}/new" "${_site}.http.conf"; then
      _changed="yes"
      echo "The front copy of ${_site} now claims: ${_want:-no name}"
    fi
  done
  [[ -n "${_changed}" ]] || return 0
  _acct_in_real_dir "${3%/*}" rm -f -- "./${3##*/}"
  _nginx_held_down && return 0
  service nginx configtest &> /dev/null && service nginx reload
}

_front_write() {
  # A site's two front copies: the list as a geo, judged at the wildcard SSL
  # front on the real visitor for every name the site's vhost serves. The host
  # map comes first and selects the rest, so an unrelated request costs one
  # lookup. A redundant /32 or /128 is dropped so it cannot collide as a
  # duplicate geo network with the plain anti-lockout form. The front copies of
  # every context share one http{}: their variables are keyed by context and
  # site, never by the site name alone.
  # $1 = the context's fragments dir, $2 = the root-only dir the copies are
  # made in, $3 = site, $4 = the names (one per line), $5 = the sorted list.
  local _hash _geo_sorted _ip _e _frag _tmp
  _hash=$(echo -n "$1/$3" | md5sum | awk '{print $1}' | cut -c1-12)
  _geo_sorted=$(for _ip in $5; do
    if [[ "${_ip}" == *:* ]]; then echo "${_ip%/128}"; else echo "${_ip%/32}"; fi
  done | sort -u)
  _frag="$2/$3.http.conf"
  _tmp="$2/.$3.http.tmp.$$"
  {
    echo "# Generated by /var/xdrago/ip_access.sh — DO NOT EDIT BY HAND."
    echo "# Wildcard SSL front copy of the whole-site list for $3."
    echo "map \$host \$ipaf_h_${_hash} {"
    echo "  hostnames;"
    echo "  default 0;"
    # read, not a bare for: a *.name wildcard must never glob.
    while IFS= read -r _e; do echo "  ${_e} 1;"; done <<< "$4"
    echo "}"
    echo "geo \$ipaf_ok_${_hash} {"
    echo "  default 0;"
    for _e in ${_geo_sorted}; do echo "  ${_e} 1;"; done
    echo "}"
    echo "map \$ipaf_ok_${_hash} \$ipaf_d_${_hash} {"
    echo "  default 0;"
    echo "  0 \$boa_front_ipa_scope;"
    echo "}"
    echo "map \$ipaf_h_${_hash} \$ipaf_deny_${_hash} {"
    echo "  default 0;"
    echo "  1 \$ipaf_d_${_hash};"
    echo "}"
  } > "${_tmp}"
  mv -f "${_tmp}" "${_frag}"
  _frag="$2/$3.srv.conf"
  _tmp="$2/.$3.srv.tmp.$$"
  {
    echo "# Generated by /var/xdrago/ip_access.sh — DO NOT EDIT BY HAND."
    echo "if (\$ipaf_deny_${_hash}) { return 403; }"
  } > "${_tmp}"
  mv -f "${_tmp}" "${_frag}"
}

_front_fill_frozen() {
  # A context whose control file was deleted before the front copies existed
  # never got one, and nothing rewrites a frozen list, so its sites stayed
  # locked over HTTP and open over HTTPS. Each missing copy is written from
  # the site's frozen vhost fragment, the list the vhost itself applies. As on
  # every other path, a failed configtest drops the new copies.
  # $1 = fragments dir, $2 = front dir, $3 = the context's vhost.d dir,
  # $4 = its front marker. Each fragment is read out, and each copy made in
  # the work dir and put, only inside the real directory.
  [[ -n "${_front_on}" ]] || return 0
  local _f _site _hosts _list _ip _w="${_work}/fill" _new=""
  for _f in "$1"/*.conf; do
    [[ -f "${_f}" && ! -L "${_f}" ]] || continue
    _site=$(basename "${_f}" .conf)
    [[ ${_site} =~ ${_site_name_regex} ]] || continue
    [[ -s "$2/${_site}.http.conf" && -s "$2/${_site}.srv.conf" ]] && continue
    rm -rf -- "${_w}"
    mkdir -m 0700 -- "${_w}" "${_w}/out" || return 0
    _acct_in_real_dir "$1" _acct_copy_here "${_site}.conf" "${_w}/frag" || continue
    grep -qx "deny all;" "${_w}/frag" || continue
    _list=$(awk '$1 == "allow" && NF == 2 { sub(/;$/, "", $2); print $2 }' "${_w}/frag" \
      | while IFS= read -r _ip; do _valid_ip "${_ip}" && echo "${_ip}"; done | sort -u)
    [[ -n "${_list}" ]] || continue
    _build_owners
    _hosts=$(_front_hosts "$3/${_site}")
    [[ -n "${_hosts}" ]] || continue
    _acct_in_real_dir "${2%/*}" mkdir -p -- "./${2##*/}" 2> /dev/null
    _front_write "$1" "${_w}/out" "${_site}" "${_hosts}" "${_list}" 2> /dev/null
    if [[ -s "${_w}/out/${_site}.http.conf" && -s "${_w}/out/${_site}.srv.conf" ]] \
      && _acct_in_real_dir "$2" _confs_put_here "${_w}/out"; then
      _new="${_new} ${_site}"
      echo "The frozen list of ${_site} now holds at the front too"
    else
      # Never leave half a pair: a gate without its maps fails the box-wide
      # configtest, and nothing below tests a site that is not in _new.
      _acct_in_real_dir "$2" rm -f -- "./${_site}.srv.conf" "./${_site}.http.conf"
      echo "Could not write the front copy of ${_site} in $2; retrying next run"
    fi
  done
  [[ -n "${_new}" ]] || return 0
  _acct_in_real_dir "${4%/*}" rm -f -- "./${4##*/}"
  _nginx_held_down && return 0
  if service nginx configtest &> /dev/null; then
    service nginx reload
  else
    for _site in ${_new}; do
      _acct_in_real_dir "$2" rm -f -- "./${_site}.srv.conf" "./${_site}.http.conf"
    done
    echo "Nginx configtest failed; dropped the new front copies in $2"
  fi
}

_front_signature() {
  # The front state and each listed site's routed names, for the change-gate:
  # a front deploy, or an alias added or removed by a Verify, regenerates.
  # $1 = control file, $2 = the context's vhost.d dir.
  local _line _s
  echo "front:${_front_on}"
  [[ -n "${_front_on}" ]] || return 0
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -r _s _ <<< "${_line}"
    _s=$(echo "${_s}" | tr '[:upper:]' '[:lower:]')
    [[ ${_s} =~ ${_site_name_regex} ]] || continue
    echo "${_s}:$(_front_hosts "${2}/${_s}" | tr '\n' ' ')"
  done < "${1}"
}


if [[ ! -f "${_aegir_health_check}" ]] || [[ ! -x "${_drush_health_check}" ]]; then
  echo "Server is not ready yet. Exiting."
  exit 1
fi

# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy) never overlap their
# configtest+reload; wait up to 30s, then skip this run and retry next tick.
exec 9>"/run/boa_nginx_config.lock" 2>/dev/null
if ! flock -w 30 9; then
  echo "Could not acquire the shared nginx-config lock; skipping this run."
  exit 0
fi

_work="$(mktemp -d /run/.ip_access.XXXXXX 2> /dev/null)" \
  || { echo "Cannot create a work directory in /run; skipping this run."; exit 1; }
trap 'rm -rf -- "${_work}"' EXIT

# Server's own IP (optional) + currently logged-in SSH IPs (host-wide) feed every
# context's anti-lockout allow list.
_server_ip=""
[[ -f "${_server_ip_file}" ]] && _server_ip=$(cat "${_server_ip_file}" 2>/dev/null)
# The cached address can now be healed (rewritten) at runtime, so validate
# it like every other token -- a malformed value must never reach an
# `allow` line and break the box-wide configtest.
_valid_ip "${_server_ip}" || _server_ip=""

_get_ssh_ips() {
  # `who --ips` is unavailable on Excalibur and newer, so read currently
  # established inbound SSH peers from netstat instead — the BOA-canonical
  # source for logged-in IPs.  netstat prints the foreign address as
  # `<addr>:<port>`; the port is always the final `:field`, so strip it with a
  # trailing-`:port` chop rather than splitting on the first colon — that yields
  # the peer address for BOTH families (IPv4 `1.2.3.4:22` -> `1.2.3.4`, IPv6
  # `2001:db8::2:50913` -> `2001:db8::2`).  Each harvested token is validated by
  # _valid_ip before it reaches an `allow` line, so a parsed-garbage / scoped
  # (fe80::1%eth0) token can never break configtest.
  # sshd may serve a custom _SSH_PORT, but the declared cnf value is not
  # always the effective one: hosted boxes and a failed sshd -t validation
  # force 22, and a cnf edit reaches sshd only on a firewall pass. Harvest
  # against the union of 22, the cnf value (inline comments stripped, never
  # sourced -- sourcing a slice resets config vars) and every port the live
  # sshd config serves, so a default-port box can never lose its peers and
  # a custom-port box is still covered.
  local _p _ports="22" _cnf_port _sshd_ports
  _cnf_port=$(sed -n 's/^_SSH_PORT=//p' /root/.barracuda.cnf 2>/dev/null \
    | tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '" ')
  # The keyword's case varies by build (OpenSSH 10.5 prints "Port 22").
  _sshd_ports=$(/usr/sbin/sshd -T 2>/dev/null | awk 'tolower($1) == "port" {print $2}')
  for _p in ${_cnf_port} ${_sshd_ports}; do
    if [[ "${_p}" =~ ^[0-9]+$ ]] && [[ ! " ${_ports} " =~ " ${_p} " ]]; then
      _ports="${_ports} ${_p}"
    fi
  done
  netstat -tn 2>/dev/null \
    | awk -v p=":(${_ports// /|})$" '$6 == "ESTABLISHED" && $4 ~ p { addr=$5; sub(/:[0-9]+$/, "", addr); print addr }' \
    | sort -u
}
_ssh_ips=$(_get_ssh_ips)
# The server IP is baked into every fragment, so a healed address must
# fire the change-gate exactly like a changed SSH-peer set.
_ssh_ips_hash=$(echo "${_ssh_ips} ${_server_ip}" | md5sum | awk '{print $1}')

_process_context() {
  local _input_file="$1" _nginx_path="$2" _backup_dir="$3" _vhost_dir="$4"
  if [[ ! -f "${_input_file}" ]]; then
    _front_fill_frozen "${_nginx_path}" "${_nginx_path}_front" "${_vhost_dir}" "${_nginx_path}/.access_front_hash"
    _front_keep_valid "${_nginx_path}_front" "${_vhost_dir}" "${_nginx_path}/.access_front_hash"
    return 0
  fi

  local _current_name=".nginx_access_conf.current.bak.tar.gz"
  local _last_good_name=".nginx_access_conf.last_good.bak.tar.gz"
  local _last_good_backup="${_backup_dir}/${_last_good_name}"
  local _front_path="${_nginx_path}_front"
  local _new="${_work}/new" _front_new="${_work}/front"
  local _ctrl="${_work}/ctrl" _mk="${_work}/mk"

  # The control file is read only as the copy taken from its real directory.
  # One that cannot be copied keeps its lists as a deleted one does, and its
  # front copies still follow their sites' names.
  local _current_mod_time
  _current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null) || return 0
  if ! _acct_in_real_dir "${_input_file%/*}" _acct_copy_here "${_input_file##*/}" "${_ctrl}"; then
    echo "${_input_file} is not a regular file in a real directory; skipped."
    _front_keep_valid "${_front_path}" "${_vhost_dir}" "${_nginx_path}/.access_front_hash"
    return 0
  fi

  # Change-gate: regenerate when the control file changed, the host SSH-IP set
  # changed (so a newly logged-in admin is added to every allow list), the emit
  # version bumped, or the front state or a listed site's routed names changed.
  # The markers are copied out of their real directory in one pass; one that
  # is not there, not a regular file, or in a directory that is not real
  # reads as none, and so does a time that is not a number: it is compared
  # as a number.
  local _last_mod_time _previous_ssh_hash _last_version
  local _front_hash _previous_front_hash
  _ensure_owners "${_ctrl}" "${_vhost_dir}"
  _front_hash=$(_front_signature "${_ctrl}" "${_vhost_dir}" | md5sum | awk '{print $1}')
  rm -rf -- "${_mk}"
  mkdir -m 0700 -- "${_mk}" || return 1
  _acct_in_real_dir "${_nginx_path}" _acct_copies_here "${_mk}" .access_last_mod_time \
    .ssh_ips_hash .access_emit_version .access_front_hash
  _line_get _last_mod_time "${_mk}/.access_last_mod_time"
  [[ "${_last_mod_time}" =~ ^[0-9]+$ ]] || _last_mod_time=0
  _line_get _previous_ssh_hash "${_mk}/.ssh_ips_hash"
  _line_get _last_version "${_mk}/.access_emit_version"
  _line_get _previous_front_hash "${_mk}/.access_front_hash"
  if [[ "${_current_mod_time}" -le "${_last_mod_time}" \
     && "${_ssh_ips_hash}" == "${_previous_ssh_hash}" \
     && "${_last_version}" == "${_emit_version}" \
     && "${_front_hash}" == "${_previous_front_hash}" ]]; then
    return 0
  fi

  _acct_in_real_dir "${_nginx_path%/*}" \
    mkdir -p -- "./${_nginx_path##*/}" "./${_front_path##*/}" 2> /dev/null
  _acct_in_real_dir "${_backup_dir%/*}" mkdir -p -- "./${_backup_dir##*/}" 2> /dev/null
  if ! _acct_in_real_dir "${_nginx_path}" true || ! _acct_in_real_dir "${_front_path}" true \
    || ! _acct_in_real_dir "${_backup_dir}" true; then
    echo "ip_access/, ip_access_front/ or ${_backup_dir##*/}/ of ${_input_file} is not a real directory; skipped."
    return 0
  fi

  _snap_store "${_nginx_path}" "${_backup_dir}" "${_current_name}" .

  # Generate per-site allow/deny fragments; track configured sites and written
  # front files for pruning. The work dirs are 0755 so the last-good archive
  # packed from them carries the mode the live directory has.
  local -a _configured=() _front_kept=()
  local _line _site _ip _ip_sorted _hosts
  local -a _ip_list
  rm -rf -- "${_new}" "${_front_new}"
  mkdir -m 0755 -- "${_new}" "${_front_new}" || return 1
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -ra _fields <<< "${_line}"
    _site=$(echo "${_fields[0]}" | tr '[:upper:]' '[:lower:]')
    if [[ ! ${_site} =~ ${_site_name_regex} ]]; then
      echo "Invalid site name: ${_site} (${_input_file}). Skipping."
      continue
    fi
    _ip_list=("127.0.0.1" "::1")
    [[ -n "${_server_ip}" ]] && _ip_list+=("${_server_ip}")
    # SSH peers are validated here (not at harvest) so a scoped/garbage token
    # never reaches an `allow` line and breaks the box-wide configtest.
    for _ip in ${_ssh_ips}; do
      _valid_ip "${_ip}" && _ip_list+=("${_ip}")
    done
    for _ip in "${_fields[@]:1}"; do
      if _valid_ip "${_ip}"; then
        _ip_list+=("${_ip}")
      else
        echo "Invalid IP/subnet: ${_ip} for ${_site} (${_input_file}). Skipping."
      fi
    done
    _ip_sorted=$(printf "%s\n" "${_ip_list[@]}" | sort -u)
    {
      for _ip in ${_ip_sorted}; do echo "allow ${_ip};"; done
      echo "deny all;"
    } > "${_new}/${_site}.conf"

    # Front copy: the same list, judged at the wildcard SSL front on the real
    # visitor for every name the site's vhost serves.
    _hosts=""
    [[ -n "${_front_on}" ]] && _hosts=$(_front_hosts "${_vhost_dir}/${_site}")
    if [[ -n "${_hosts}" ]]; then
      _front_write "${_nginx_path}" "${_front_new}" "${_site}" "${_hosts}" "${_ip_sorted}"
      _front_kept+=("${_site}.http.conf" "${_site}.srv.conf")
    fi
    _configured+=("${_site}")
  done < "${_ctrl}"

  # What this run made goes in place only inside the real directories.
  if ! _acct_in_real_dir "${_nginx_path}" _confs_put_here "${_new}" \
    || ! _acct_in_real_dir "${_front_path}" _confs_put_here "${_front_new}"; then
    echo "Could not put every ip_access file of ${_input_file}; retrying next run."
    return 1
  fi

  # Prune front files not written by this run: an unlisted site, a site with
  # no rendered vhost, or every one while the front does not include them.
  _acct_in_real_dir "${_front_path}" _prune_here "ip_access front file" "${_input_file}" "" \
    "${_front_kept[@]}"

  # Prune fragments for sites no longer in the control file (restriction lifted).
  _acct_in_real_dir "${_nginx_path}" _prune_here "ip_access fragment" "${_input_file}" .conf \
    "${_configured[@]}"

  if _nginx_held_down; then
    _acct_in_real_dir "${_nginx_path}" _acct_put_pairs_here \
      .access_last_mod_time "${_current_mod_time}" .ssh_ips_hash "${_ssh_ips_hash}" \
      .access_emit_version "${_emit_version}" .access_front_hash "${_front_hash}"
    echo "ip_access written (${_input_file}); replication standby -- reload skipped (web tier held)."
    return 0
  fi

  # Validate the whole host nginx config; revert THIS context on failure. The
  # front copies are dropped on every failure and never restored: they only
  # narrow what the front lets through, and an older set could still claim a
  # name that has since moved to another site.
  local _ct
  _ct=$(service nginx configtest 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Nginx configtest failed after ip_access update (${_input_file}): ${_ct}"
    _acct_in_real_dir "${_front_path}" _confs_drop_here > /dev/null
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_input_file} ip_access to last known good."
      ### Prove the archive is readable BEFORE deleting what is on disk:
      ### the old order wiped every fragment and then extracted from an
      ### unverified tarball, so a corrupt or truncated backup left the
      ### box with no access-control fragments at all.
      if _lg_fetch "${_backup_dir}" "${_last_good_name}" "${_work}/lg"; then
        _acct_in_real_dir "${_nginx_path}" _confs_drop_here > /dev/null
        if ! _acct_in_real_dir "${_nginx_path}" _confs_put_here "${_work}/lg"; then
          _policy_alert "ip_access.restore.${_input_file}" \
            "ip_access: restoring the last-good backup FAILED (${_input_file})" \
            "restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
        service nginx reload
      else
        _policy_alert "ip_access.refused.${_input_file}" \
          "ip_access: last-good backup unreadable, fragments kept (${_input_file})" \
          "last-good backup ${_last_good_backup} is unreadable -- keeping the" \
          "fragments now on disk rather than deleting them for an archive" \
          "that cannot be restored. Fix ${_input_file} and re-run."
        # With the front copies gone the rest may pass again.
        service nginx configtest &> /dev/null && service nginx reload
      fi
    else
      # No last-good yet (a first run failed configtest). nginx never reloaded the
      # bad config (configtest gates the reload), so just drop the fragments this
      # run wrote — otherwise a bad one lingers and keeps EVERY tool's configtest
      # failing box-wide until someone finds and fixes it.
      echo "No last-good backup for ${_input_file}; removing just-written fragments."
      _acct_in_real_dir "${_nginx_path}" _confs_drop_here > /dev/null
    fi
    # The front copies were dropped: forget the front state so the next pass
    # rebuilds them.
    _acct_in_real_dir "${_nginx_path}" rm -f -- ./.access_front_hash
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after ip_access update (${_input_file}); reverting."
    _acct_in_real_dir "${_front_path}" _confs_drop_here > /dev/null
    if [[ -f "${_last_good_backup}" ]]; then
      if _lg_fetch "${_backup_dir}" "${_last_good_name}" "${_work}/lg"; then
        _acct_in_real_dir "${_nginx_path}" _confs_drop_here > /dev/null
        if ! _acct_in_real_dir "${_nginx_path}" _confs_put_here "${_work}/lg"; then
          _policy_alert "ip_access.restore.${_input_file}" \
            "ip_access: restoring the last-good backup FAILED (${_input_file})" \
            "restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
        service nginx reload
      else
        _policy_alert "ip_access.refused.${_input_file}" \
          "ip_access: last-good backup unreadable, fragments kept (${_input_file})" \
          "last-good backup ${_last_good_backup} is unreadable -- fragments left in place."
      fi
    fi
    _acct_in_real_dir "${_nginx_path}" rm -f -- ./.access_front_hash
    return 1
  fi

  ### An unverified last-good archive is worse than none: the revert path
  ### above trusts it enough to delete the live fragments. It holds what
  ### this run put, packed from the work dir.
  if ! _lg_store "${_new}" "${_backup_dir}" "${_last_good_name}" .; then
    _policy_alert "ip_access.lgstore.${_input_file}" \
      "ip_access: last-good backup not written (${_input_file})" \
      "could not write a verifiable last-good ip_access backup; removing it"
    _acct_in_real_dir "${_backup_dir}" rm -f -- "./${_last_good_name}"
  fi
  _acct_in_real_dir "${_nginx_path}" _acct_put_pairs_here \
    .access_last_mod_time "${_current_mod_time}" .ssh_ips_hash "${_ssh_ips_hash}" \
    .access_emit_version "${_emit_version}" .access_front_hash "${_front_hash}"
  echo "ip_access updated (${_input_file}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
}

# Master (sqladmin) context — seed the control file if absent, only inside
# its real directory and never through a link left at the name.
mkdir -p /var/aegir/control/ip
if [[ ! -e /var/aegir/control/ip/access.txt && ! -L /var/aegir/control/ip/access.txt ]]; then
  _acct_in_real_dir /var/aegir/control/ip _acct_put_here access.txt "sqladmin.com 192.168.1.1"
fi
_process_context /var/aegir/control/ip/access.txt /var/aegir/config/includes/ip_access /var/aegir/undo \
  /var/aegir/config/server_master/nginx/vhost.d

# Octopus instances. Real instances carry tools/drush; the BOA-canonical instance
# test (see autosymlink) transparently skips every non-instance pseudo-dir
# (arch, all, legacy, global, static, custom, …), not just 'arch' by name.
for _root in /data/disk/*; do
  [[ -d "${_root}" ]] || continue
  if [[ ! -e "${_root}/tools/drush" ]]; then
    # Only an instance that is gone: an Octopus upgrade moves tools/drush
    # aside for a moment while the instance itself stays live.
    [[ ! -e "/root/.${_root##*/}.octopus.cnf" \
      && -d "${_root}/config/includes/ip_access_front" ]] \
      && _front_clear "${_root}/config/includes/ip_access_front" \
        "${_root}/config/includes/ip_access/.access_front_hash"
    continue
  fi
  _process_context "${_root}/static/control/ip/access.txt" "${_root}/config/includes/ip_access" "${_root}/undo" \
    "${_root}/config/server_master/nginx/vhost.d"
done

exit 0
