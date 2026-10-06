#!/bin/bash

# user_admin_access.sh — per-site nginx IP allow/deny scoped to the Drupal /user
# and /admin URIs only, GLOBAL across every Octopus instance.  Parallel to
# ip_access.sh, which denies the WHOLE site to anyone off its list: this one
# denies only the login/admin surface and leaves the rest of the site public.
# Both are pure nginx allow/deny layers with no csf involvement, so both accept
# IPv4 AND IPv6, single addresses AND CIDR subnets; the only difference is scope.
#
# For each instance it reads a control file of `<site>  <ip|cidr…>` records and
# writes two per-site nginx includes into that instance's config/includes/:
#
#   user_admin_access_map/<site>.conf  (http scope) — a `geo` classifying the
#       client IP as allowed (1) or not (0), a `map` flagging a /user|/admin
#       request on the clean $uri (BOA enforces Drupal clean URLs, so those paths
#       always arrive in $uri), and a final `map` $ua_deny_<hash> that is 1 only
#       when an admin-area request arrives from a non-allowed IP;
#   user_admin_access/<site>.conf      (server scope) — a single
#       `if ($ua_deny_<hash>) { return 403; }`.
#
# The per-site vhost pulls the first once at the file head (http scope) via
#   include $server->include_path/user_admin_access_map/<uri>.conf*;
# and the second inside every serving server block (co-located with ip_access) via
#   include $server->include_path/user_admin_access/<uri>.conf*;
# both globs no-op for a site with no fragment, so an un-listed site is entirely
# unaffected and the whole feature is strict opt-in.  The `.conf*` (not bare `*`)
# is deliberate: a bare `<uri>*` would also match a longer site whose name extends
# this one (example.com vs example.com.au), pulling that site's fragment into this
# vhost too and wrongly applying its restriction here; `.conf*` anchors on the
# fragment suffix so only this site's own <uri>.conf matches, while still no-oping
# when absent.  The geo/map is defined once per file and referenced from every
# server block in it (the :443 block precedes it in an SSL vhost — nginx resolves
# map/geo vars across the whole http{} regardless of textual order, so the forward
# reference is fine).
#
# 127.0.0.1, ::1, the server's own IPv4 and every live inbound SSH peer (v4 or v6)
# are always allowed (anti-lockout), so an admin working over SSH can never be shut
# out of /admin.  A site removed from the control file has both fragments pruned
# (restriction lifted).  A deleted control file changes nothing: the lists stay as
# they are (a deletion does not travel to a mirror or a migration target, so it
# could only ever lift one box); remove a site's line or empty the file to lift it.
# A site frozen before the front copies existed gets one from its map.
#
# HTTPS for a site without its own certificate arrives through the wildcard SSL
# front (nginx_wild_ssl.conf), which proxies to the site's :80 vhost, where the
# peer is always 127.0.0.1; a panel's HTTPS proxy connects from the box's own
# address.  The vhost geo trusts those hops to name the visitor (the last
# X-Forwarded-For address, which each of them appends), so the vhost judges the
# real visitor on every hop.  Once the deployed front includes them, each
# listed site also gets two front files in user_admin_access_front/:
# <site>.http.conf (its own geo and $uri map, and a $host map of the server
# names in the site's rendered vhost that no other vhost on the box also
# serves) and <site>.srv.conf (the 403 gate), so the front refuses the clean
# admin paths itself.  A site with no rendered vhost gets no front files.
#
# Grav 2 and Textpattern sites keep their admin surface elsewhere, so a site whose
# platform root positively reads as one of them gets its own lines in the same
# $uri map, and nothing else changes — no new variable, no new include. Drupal,
# Backdrop and Textpattern get the plain /user + /admin line; Grav gets /admin
# only (its /user tree is the public theme and media store, served to every
# visitor). Each adds:
#   Grav 2       /api  — Admin2 at /admin is only a shell; every login, account,
#                page, media and config operation runs through the API plugin, so
#                a list that stopped at /admin left the data surface open.
#   Textpattern  /txpadmin — where BOA maps the Textpattern admin.
# A Grav site that serves a deliberately public headless API adds the keyword
# `api-open` to its record: /admin stays on the list, /api stays public.
#
# Control file (Octopus only — the instance's sites and its control panel, whose
# HTTPS proxy in pre.d includes the panel's fragment and map itself; the master's
# hostmaster has its own, out-of-scope vhost):
#   /data/disk/<oct>/static/control/ip/user_admin.txt
#   Record: `example.com  203.0.113.10  10.0.0.0/8  2001:db8::/32  2001:db8::1`
#   Record: `headless.example.com  203.0.113.10  api-open`

_aegir_health_check="/var/aegir/.drush/hm.alias.drushrc.php"
_drush_health_check="/var/aegir/drush/drush"
_server_ip_file="/root/.found_correct_ipv4.cnf"

# Bump when the emitted directive shape changes, to force regeneration
# independent of the control-file mtime.
_emit_version="6"

# The deployed front includes the front files only once it carries these lines;
# until then none are written, so a front deploy never meets an unvalidated one.
_front_conf="/var/aegir/config/server_master/nginx/pre.d/nginx_wild_ssl.conf"
_front_on=""
grep -qF 'user_admin_access_front/*.srv.conf' "${_front_conf}" 2>/dev/null && _front_on="yes"

# Validators.  Each accepts an IPv4 or IPv6 address, with an optional CIDR prefix
# length, and is a strict SUBSET of what nginx `geo` accepts — cross-checked
# against `nginx -t` — so a validated entry can never break the whole-host
# configtest (which validates every vhost; one bad geo network would block
# reloads box-wide).  A rejected token is skipped with a logged warning, like
# ip_access does for a bad octet.
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

# oN owns /data/disk/oN (config/, undo/ and every directory in them), so any
# name there can be a link or a FIFO, and any directory on the way can itself
# be a link. Root reads and writes those names only through these, inside the
# real directory; the control file and the front copies are read only as
# copies taken there, and the drush aliases and every rendered vhost as
# copies that do not follow a link at their own name (.drush and vhost.d
# are the instance's own), none blocking on a FIFO, and the fragments,
# front copies and archives are made in a root-only work directory in /run
# first. The last-good archive in undo/ is oN's to replace: it is copied
# out without following a link, unpacked with no owner and no mode taken
# from it and only whole within 32 MiB, and only a regular file with a
# fragment's name is put back.
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

_foreign_cms_kind() {
  # Prints grav or txp when the site's platform root positively reads as one,
  # nothing otherwise. The root comes from the instance's own drush alias
  # (written by the backend, never by the tenant) and the shape test is the one
  # the nightly and the Solr agent share: provision's platform detection plus
  # the Drupal negatives, so no Drupal or Backdrop tree can ever read as
  # foreign. Every doubt (no alias, a root that does not resolve, an unknown
  # shape) prints nothing, and the site then keeps the plain /user + /admin
  # line -- a miss leaves a site as it was, it never widens what one matches.
  # The alias is read only as a copy that does not follow a link at its own
  # name or block on a FIFO (_ACCT_COPY_PL, at most 1 MiB).
  # $1 = instance root, $2 = site name.
  local _alias="${1}/.drush/${2}.alias.drushrc.php" _c="${_work}/alias.one"
  local _r
  [[ -f "${_alias}" ]] || return 0
  rm -f -- "${_c}"
  printf '%s\0' "${_alias}" "${_c}" | perl -e "${_ACCT_COPY_PL}" 1048576 || return 0
  _r=$(grep "'root' =>" "${_c}" 2>/dev/null | head -n 1 | cut -d"'" -f4)
  [[ -n "${_r}" ]] || return 0
  _r=$(realpath -e -- "${_r}" 2>/dev/null)
  [[ -n "${_r}" && -d "${_r}" && -f "${_r}/index.php" ]] || return 0
  [[ -e "${_r}/core" ]] && return 0
  [[ -e "${_r}/modules/system/system.module" ]] && return 0
  [[ -e "${_r}/includes/bootstrap.inc" ]] && return 0
  if [[ -f "${_r}/bin/grav" && -f "${_r}/system/defines.php" ]]; then
    echo "grav"
  elif [[ -f "${_r}/css.php" && -f "${_r}/textpattern/index.php" \
    && -f "${_r}/textpattern/lib/constants.php" && ! -e "${_r}/autoload.php" ]]; then
    echo "txp"
  fi
  return 0
}

_kinds_signature() {
  # One `<site>:<kind>` line per valid record, for the change-gate.
  # $1 = instance root, $2 = control file.
  local _line _s
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -r _s _ <<< "${_line}"
    _s=$(echo "${_s}" | tr '[:upper:]' '[:lower:]')
    [[ ${_s} =~ ${_site_name_regex} ]] || continue
    echo "${_s}:$(_foreign_cms_kind "${1}" "${_s}")"
  done < "${2}"
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
    if ! _have=$(awk -v h="# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND." '
        NR == 1 && $0 != h { bad = 1; exit }
        /^map \$host / { if (m++ || $0 !~ /^map \$host \$uaf_h_[0-9a-f]+ \{$/) { bad = 1; exit }; p = 1; next }
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

_front_signature() {
  # The front state and each listed site's routed names, for the change-gate:
  # a front deploy, or an alias added or removed by a Verify, regenerates.
  # $1 = instance root, $2 = control file.
  local _line _s
  echo "front:${_front_on}"
  [[ -n "${_front_on}" ]] || return 0
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -r _s _ <<< "${_line}"
    _s=$(echo "${_s}" | tr '[:upper:]' '[:lower:]')
    [[ ${_s} =~ ${_site_name_regex} ]] || continue
    echo "${_s}:$(_front_hosts "${1}/config/server_master/nginx/vhost.d/${_s}" | tr '\n' ' ')"
  done < "${2}"
}

_front_write() {
  # A site's two front copies: the list, judged at the wildcard SSL front on
  # the real visitor for every name the site's vhost serves. The host map
  # comes first and selects the rest, so an unrelated request costs one
  # lookup. The front copies of every instance share one http{}: their
  # variables are keyed by instance and site, never by the site name alone.
  # $1 = instance root, $2 = the root-only dir the copies are made in,
  # $3 = site, $4 = the names (one per line), $5 = the geo body, $6 = the
  # $uri map body.
  local _fhash _e _frag _tmp
  _fhash=$(echo -n "$1/$3" | md5sum | awk '{print $1}' | cut -c1-12)
  _frag="$2/$3.http.conf"
  _tmp="$2/.$3.http.tmp.$$"
  {
    echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
    echo "# Wildcard SSL front copy of the /user + /admin list for $3."
    echo "map \$host \$uaf_h_${_fhash} {"
    echo "  hostnames;"
    echo "  default 0;"
    # read, not a bare for: a *.name wildcard must never glob.
    while IFS= read -r _e; do echo "  ${_e} 1;"; done <<< "$4"
    echo "}"
    echo "geo \$uaf_ok_${_fhash} {"
    printf '%s\n' "$5"
    echo "}"
    echo "map \$uri \$uaf_u_${_fhash} {"
    printf '%s\n' "$6"
    echo "}"
    echo "map \"\$uaf_u_${_fhash}\$uaf_ok_${_fhash}\" \$uaf_d_${_fhash} {"
    echo "  default 0;"
    echo "  \"10\" 1;"
    echo "}"
    echo "map \$uaf_h_${_fhash} \$uaf_deny_${_fhash} {"
    echo "  default 0;"
    echo "  1 \$uaf_d_${_fhash};"
    echo "}"
    # The lock verdict for this site, judged at the front on the real visitor,
    # for the PHP ?q= gate: 1 when not allowed, 0 when allowed.
    echo "map \$uaf_ok_${_fhash} \$uaf_lk_${_fhash} {"
    echo "  default 1;"
    echo "  1 0;"
    echo "}"
  } > "${_tmp}"
  mv -f "${_tmp}" "${_frag}"
  _frag="$2/$3.srv.conf"
  _tmp="$2/.$3.srv.tmp.$$"
  {
    echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
    echo "if (\$uaf_deny_${_fhash}) { return 403; }"
    # Only this site's request publishes its verdict; the front defaults the
    # shared variable to "0" (allowed) and forwards it to the backend, which
    # decodes q and gates the ?q= route form the front cannot match on \$uri.
    echo "if (\$uaf_h_${_fhash}) { set \$boa_ua_lk_fwd \$uaf_lk_${_fhash}; }"
  } > "${_tmp}"
  mv -f "${_tmp}" "${_frag}"
}

_front_fill_frozen() {
  # An instance whose control file was deleted before the front copies existed
  # never got one, and nothing rewrites a frozen list, so its sites' admin
  # paths stayed locked over HTTP and open over HTTPS. Each missing copy is
  # written from the site's frozen map, the list and paths its vhost applies
  # (an api-open choice included); a line this generator would not write
  # leaves the site alone. As on every other path, a failed configtest drops
  # the new copies. $1 = instance root, $2 = map dir, $3 = srv dir,
  # $4 = front dir, $5 = the instance's vhost.d dir, $6 = its front marker.
  # Each map is read out, and each copy made in the work dir and put, only
  # inside the real directory.
  [[ -n "${_front_on}" ]] || return 0
  local _f _site _hosts _geo _area _l _ok _known _w="${_work}/fill" _new=""
  _known=$(printf '%s\n' "$(_area_lines "" "")" "$(_area_lines grav "")" \
    "$(_area_lines txp "")" | sort -u)
  for _f in "$2"/*.conf; do
    [[ -f "${_f}" && ! -L "${_f}" ]] || continue
    _site=$(basename "${_f}" .conf)
    [[ ${_site} =~ ${_site_name_regex} ]] || continue
    [[ -f "$3/${_site}.conf" ]] || continue
    [[ -s "$4/${_site}.http.conf" && -s "$4/${_site}.srv.conf" ]] && continue
    rm -rf -- "${_w}"
    mkdir -m 0700 -- "${_w}" "${_w}/out" || return 0
    _acct_in_real_dir "$2" _acct_copy_here "${_site}.conf" "${_w}/map" || continue
    # Each body once per line: nginx refuses a second default in a map. The
    # vhost geo's trusted-hop proxy lines stay out: the front judges its own
    # peer, the real visitor, and must never read a forwarded address.
    _geo=$(awk '/^geo \$ua_ip_ok_/ { p = 1; next } p && /^}/ { exit } p && /^  proxy / { next } p && !s[$0]++ { print }' "${_w}/map")
    _area=$(awk '/^map \$uri \$ua_u_/ { p = 1; next } p && /^}/ { exit } p && !s[$0]++ { print }' "${_w}/map")
    _ok="yes"
    while IFS= read -r _l; do
      [[ "${_l}" == "  default 0;" ]] && continue
      [[ "${_l}" =~ ^\ \ ([^\ ]+)\ 1\;$ ]] && _valid_ip "${BASH_REMATCH[1]}" && continue
      _ok=""
    done <<< "${_geo}"
    while IFS= read -r _l; do
      grep -qxF -- "${_l}" <<< "${_known}" || _ok=""
    done <<< "${_area}"
    [[ -n "${_ok}" && "${_geo}" == *" 1;"* && "${_area}" == *" 1;"* ]] || continue
    _build_owners
    _hosts=$(_front_hosts "$5/${_site}")
    [[ -n "${_hosts}" ]] || continue
    _acct_in_real_dir "${4%/*}" mkdir -p -- "./${4##*/}" 2> /dev/null
    _front_write "$1" "${_w}/out" "${_site}" "${_hosts}" "${_geo}" "${_area}" 2> /dev/null
    if [[ -s "${_w}/out/${_site}.http.conf" && -s "${_w}/out/${_site}.srv.conf" ]] \
      && _acct_in_real_dir "$4" _confs_put_here "${_w}/out"; then
      _new="${_new} ${_site}"
      echo "The frozen /user + /admin list of ${_site} now holds at the front too"
    else
      # Never leave half a pair: a gate without its maps fails the box-wide
      # configtest, and nothing below tests a site that is not in _new.
      _acct_in_real_dir "$4" rm -f -- "./${_site}.srv.conf" "./${_site}.http.conf"
      echo "Could not write the front copy of ${_site} in $4; retrying next run"
    fi
  done
  [[ -n "${_new}" ]] || return 0
  _acct_in_real_dir "${6%/*}" rm -f -- "./${6##*/}"
  _nginx_held_down && return 0
  if service nginx configtest &> /dev/null; then
    service nginx reload
  else
    for _site in ${_new}; do
      _acct_in_real_dir "$4" rm -f -- "./${_site}.srv.conf" "./${_site}.http.conf"
    done
    echo "Nginx configtest failed; dropped the new front copies in $4"
  fi
}

_geo_lines() {
  # Body of an allow-list geo. $1 = the sorted, de-duplicated entries.
  local _e
  echo "  default 0;"
  for _e in $1; do echo "  ${_e} 1;"; done
}

_area_lines() {
  # Body of the $uri map for the admin surface. $1 = CMS kind, $2 = api-open.
  echo "  default 0;"
  # Grav's /user is its public theme and media tree, served to every
  # visitor, so a Grav map gates /admin only. A language-prefixed login
  # (/de/user) is not matched: a prefix pattern would also gate a parent
  # site's subdirectory sites, API endpoints such as /api/user/login and
  # content paths shaped like a prefix.
  if [[ "$1" == "grav" ]]; then
    echo "  ~*^/+admin(?:/|\$) 1;"
  else
    echo "  ~*^/+(?:user|admin)(?:/|\$) 1;"
  fi
  # The whole /api route, not /api/v1, so a later version segment is
  # covered too. The (?:/|\$) tail holds the match to the plugin's real
  # routes: it wakes on any path that merely begins with /api, but such a
  # lookalike (same length or not) lands on no endpoint, it only draws the
  # plugin's own 401. The prefix is the API plugin's default: a site that
  # renames its route moves it out from under the list. A language prefix
  # needs no arm -- on a multi-language capsule /en/admin and /en/api/v1
  # are plain 404s.
  if [[ "$1" == "grav" && -z "$2" ]]; then
    echo "  ~*^/+api(?:/|\$) 1;"
  elif [[ "$1" == "txp" ]]; then
    echo "  ~*^/+txpadmin(?:/|\$) 1;"
  fi
}

if [[ ! -f "${_aegir_health_check}" ]] || [[ ! -x "${_drush_health_check}" ]]; then
  echo "Server is not ready yet. Exiting."
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx not installed; nothing to do."
  exit 0
fi

# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy / user_admin_access) never overlap
# their configtest+reload; wait up to 30s, then skip this run and retry next tick.
exec 9>"/run/boa_nginx_config.lock" 2>/dev/null
if ! flock -w 30 9; then
  echo "Could not acquire the shared nginx-config lock; skipping this run."
  exit 0
fi

_work="$(mktemp -d /run/.user_admin_access.XXXXXX 2> /dev/null)" \
  || { echo "Cannot create a work directory in /run; skipping this run."; exit 1; }
trap 'rm -rf -- "${_work}"' EXIT

# Server's own IPv4 (optional) + currently logged-in inbound SSH peers (v4 or v6)
# feed every context's anti-lockout allow list.
_server_ip=""
[[ -f "${_server_ip_file}" ]] && _server_ip=$(cat "${_server_ip_file}" 2>/dev/null)
# The cached address can now be healed (rewritten) at runtime, so validate
# it like every other token -- a malformed value must never reach a geo
# entry and break the box-wide configtest.
_valid_ip "${_server_ip}" || _server_ip=""

_get_ssh_ips() {
  # Same source ip_access.sh uses: `who --ips` is unavailable on Excalibur and
  # newer, so read established inbound SSH peers from netstat.  netstat prints the
  # foreign address as `<addr>:<port>`; the port is always the final `:field`, so
  # strip it with a trailing-`:port` chop rather than splitting on the first colon
  # — that yields the peer address for BOTH families (IPv4 `1.2.3.4:22` ->
  # `1.2.3.4`, IPv6 `2001:db8::2:50913` -> `2001:db8::2`).  Each harvested token is
  # validated by _valid_ip before it reaches a geo entry, so a parsed-garbage /
  # scoped (fe80::1%eth0) token can never break configtest.
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

_process_instance() {
  local _root="$1"
  local _input_file="${_root}/static/control/ip/user_admin.txt"
  local _map_path="${_root}/config/includes/user_admin_access_map"
  local _srv_path="${_root}/config/includes/user_admin_access"
  local _front_path="${_root}/config/includes/user_admin_access_front"
  local _vhost_dir="${_root}/config/server_master/nginx/vhost.d"
  local _backup_dir="${_root}/undo"
  local _current_name=".nginx_user_admin.current.bak.tar.gz"
  local _last_good_name=".nginx_user_admin.last_good.bak.tar.gz"
  local _last_good_backup="${_backup_dir}/${_last_good_name}"
  local _front_file="${_srv_path}/.ua_front_hash"
  local _new="${_work}/new" _front_new="${_work}/front"
  local _ctrl="${_work}/ctrl" _mk="${_work}/mk"

  if [[ ! -f "${_input_file}" ]]; then
    _front_fill_frozen "${_root}" "${_map_path}" "${_srv_path}" "${_front_path}" "${_vhost_dir}" "${_front_file}"
    _front_keep_valid "${_front_path}" "${_vhost_dir}" "${_front_file}"
    return 0
  fi
  [[ -d "${_root}/config/includes" ]] || return 0

  # The control file is read only as the copy taken from its real directory.
  # One that cannot be copied keeps its lists as a deleted one does, and its
  # front copies still follow their sites' names.
  local _current_mod_time
  _current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null) || return 0
  if ! _acct_in_real_dir "${_input_file%/*}" _acct_copy_here "${_input_file##*/}" "${_ctrl}"; then
    echo "The control file of ${_root} is not a regular file in a real directory; skipped."
    _front_keep_valid "${_front_path}" "${_vhost_dir}" "${_front_file}"
    return 0
  fi

  # Change-gate: regenerate only when the control file changed, the host SSH-IP
  # set changed (a newly logged-in admin must propagate), the emit version
  # bumped, a listed site's CMS kind changed, or the front state or a listed
  # site's routed names changed.  No change -> no write, no reload.  The kind
  # and the names are baked into the fragments, so a record written before
  # its site exists, a name re-created as another CMS or an alias added later
  # must regenerate without anyone touching the control file. The markers
  # are copied out of their real directory in one pass; one that is not
  # there, not a regular file, or in a directory that is not real reads as
  # none, and so does a time that is not a number: it is compared as a
  # number.
  local _last_mod_time _previous_ssh_hash _last_version
  local _kinds_hash _previous_kinds_hash _front_hash _previous_front_hash
  _kinds_hash=$(_kinds_signature "${_root}" "${_ctrl}" | md5sum | awk '{print $1}')
  _ensure_owners "${_ctrl}" "${_vhost_dir}"
  _front_hash=$(_front_signature "${_root}" "${_ctrl}" | md5sum | awk '{print $1}')
  rm -rf -- "${_mk}"
  mkdir -m 0700 -- "${_mk}" || return 1
  _acct_in_real_dir "${_srv_path}" _acct_copies_here "${_mk}" .ua_last_mod_time \
    .ua_ssh_ips_hash .ua_emit_version .ua_cms_kinds_hash .ua_front_hash
  _line_get _last_mod_time "${_mk}/.ua_last_mod_time"
  [[ "${_last_mod_time}" =~ ^[0-9]+$ ]] || _last_mod_time=0
  _line_get _previous_ssh_hash "${_mk}/.ua_ssh_ips_hash"
  _line_get _last_version "${_mk}/.ua_emit_version"
  _line_get _previous_kinds_hash "${_mk}/.ua_cms_kinds_hash"
  _line_get _previous_front_hash "${_mk}/.ua_front_hash"
  if [[ "${_current_mod_time}" -le "${_last_mod_time}" \
     && "${_ssh_ips_hash}" == "${_previous_ssh_hash}" \
     && "${_last_version}" == "${_emit_version}" \
     && "${_kinds_hash}" == "${_previous_kinds_hash}" \
     && "${_front_hash}" == "${_previous_front_hash}" ]]; then
    return 0
  fi

  _acct_in_real_dir "${_root}/config/includes" mkdir -p -- ./user_admin_access_map \
    ./user_admin_access ./user_admin_access_front 2> /dev/null
  _acct_in_real_dir "${_root}" mkdir -p ./undo 2> /dev/null
  if ! _acct_in_real_dir "${_map_path}" true || ! _acct_in_real_dir "${_srv_path}" true \
    || ! _acct_in_real_dir "${_front_path}" true || ! _acct_in_real_dir "${_backup_dir}" true; then
    echo "A user_admin_access dir or undo/ of ${_root} is not a real directory; skipped."
    return 0
  fi

  # Back up the site-vhost fragment dirs before regenerating. The front copies
  # are never backed up: a failed run drops them (see below).
  _snap_store "${_root}/config/includes" "${_backup_dir}" "${_current_name}" \
    user_admin_access_map user_admin_access

  # Generate per-site fragments; track configured sites and written front
  # files for pruning. The work dirs are 0755 so the last-good archive packed
  # from them carries the modes the live directories have.
  local -a _configured=() _fields _ip_list _front_kept=()
  local _line _site _hash _ip _norm _ip_sorted _d
  local _kind _api_open _hosts
  rm -rf -- "${_new}" "${_front_new}"
  mkdir -m 0755 -- "${_new}" "${_new}/user_admin_access_map" "${_new}/user_admin_access" \
    "${_front_new}" || return 1
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    [[ -z "${_line// /}" ]] && continue
    read -ra _fields <<< "${_line}"
    _site=$(echo "${_fields[0]}" | tr '[:upper:]' '[:lower:]')
    if [[ ! ${_site} =~ ${_site_name_regex} ]]; then
      echo "Invalid site name: ${_site} (${_input_file}). Skipping."
      continue
    fi
    _hash=$(echo -n "${_site}" | md5sum | awk '{print $1}' | cut -c1-12)

    # Anti-lockout, then the operator's validated entries.
    _ip_list=("127.0.0.1" "::1")
    [[ -n "${_server_ip}" ]] && _ip_list+=("${_server_ip}")
    # SSH peers validated here (not at harvest) so a scoped/garbage token never
    # reaches a geo entry and breaks the box-wide configtest.
    for _ip in ${_ssh_ips}; do
      _valid_ip "${_ip}" && _ip_list+=("${_ip}")
    done
    _kind=$(_foreign_cms_kind "${_root}" "${_site}")
    _api_open=""
    for _ip in "${_fields[@]:1}"; do
      # A keyword, not an address: the site keeps its API public. It means
      # nothing outside a Grav record and is accepted silently there.
      if [[ $(echo "${_ip}" | tr '[:upper:]' '[:lower:]') == "api-open" ]]; then
        _api_open="yes"
        continue
      fi
      if _valid_ip "${_ip}"; then
        # Drop a redundant host prefix so a listed 1.2.3.4/32 (or v6 …/128) does
        # not collide as a duplicate geo network with the plain anti-lockout form.
        if [[ "${_ip}" == *:* ]]; then
          _norm="${_ip%/128}"
        else
          _norm="${_ip%/32}"
        fi
        _ip_list+=("${_norm}")
      else
        echo "Invalid IP/subnet: ${_ip} for ${_site} (${_input_file}). Skipping."
      fi
    done
    _ip_sorted=$(printf '%s\n' "${_ip_list[@]}" | sort -u)

    # http-scope fragment: geo (IP -> allowed) + area maps + deny map.
    {
      echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
      echo "# Per-site /user + /admin IP access for ${_site}."
      echo "geo \$ua_ip_ok_${_hash} {"
      # The on-box hops, the wildcard SSL front on loopback and the panel's HTTPS
      # proxy on the box's own address, are trusted to name the visitor: geo then
      # judges the last X-Forwarded-For address, which each of them appends
      # itself, so this vhost judges the real visitor on every hop and a remote
      # client's own header is never read. Not recursive: an address a client
      # puts earlier in the header can never step past the appended one. A
      # loopback caller that sends no such header is still judged as loopback.
      echo "  proxy 127.0.0.1;"
      echo "  proxy ::1;"
      [[ -n "${_server_ip}" ]] && echo "  proxy ${_server_ip};"
      _geo_lines "${_ip_sorted}"
      echo "}"
      # BOA enforces Drupal clean URLs, so /user and /admin always arrive as the
      # real request path in \$uri (which nginx percent-decodes and normalises —
      # /./ , and // under the default merge_slashes on). This nginx layer matches
      # \$uri only: \$arg_q cannot be matched reliably at nginx (it is neither
      # percent-decoded nor de-duplicated the way Drupal reads \$_GET['q']).
      # ^/+ (not ^/) also catches a multi-slash //admin even if a vhost ever
      # disabled merge_slashes. The legacy query-string route form (?q=user/…),
      # which Drupal 6/7 and Backdrop still route on and which arrives with \$uri
      # '/', is caught in PHP instead: the per-request lock verdict below travels
      # to the backend and BOA's global settings refuse a \$_GET['q'] that resolves
      # to the user/admin surface from a locked visitor.
      echo "map \$uri \$ua_u_${_hash} {"
      _area_lines "${_kind}" "${_api_open}"
      echo "}"
      echo "map \"\$ua_u_${_hash}\$ua_ip_ok_${_hash}\" \$ua_deny_${_hash} {"
      echo "  default 0;"
      echo "  \"10\" 1;"
      echo "}"
      # The lock verdict for the PHP layer: 1 when this visitor is NOT allowed to
      # the admin surface, 0 when allowed. The backend gates the ?q= route form on
      # it. It is the real visitor's verdict on a direct hit and on the proxied
      # HTTPS hops alike (the geo above reads the address those hops forward).
      echo "map \$ua_ip_ok_${_hash} \$ua_lk_${_hash} {"
      echo "  default 1;"
      echo "  1 0;"
      echo "}"
    } > "${_new}/user_admin_access_map/${_site}.conf"

    # server-scope fragment: the 403 gate for the clean-path admin surface, and
    # the lock verdict for the PHP ?q= gate. The fastcgi_param sits at server
    # level, as the vhost's db_* params do, so it reaches the PHP locations that
    # declare none of their own (the page route); being in this fragment, it
    # reaches every listed site as soon as this generator runs, with no vhost
    # rebuild, and an unlisted site never carries it. The set feeds the proxy
    # templates that forward the verdict as a header; the panel's HTTPS proxy
    # includes this file too, where the param is inert.
    {
      echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
      echo "if (\$ua_deny_${_hash}) { return 403; }"
      echo "set \$boa_ua_lk_self \$ua_lk_${_hash};"
      echo "fastcgi_param BOA_UA_LK_SELF \$ua_lk_${_hash};"
    } > "${_new}/user_admin_access/${_site}.conf"

    # Front copy: the same list, judged at the wildcard SSL front on the real
    # visitor for every name the site's vhost serves.
    _hosts=""
    [[ -n "${_front_on}" ]] && _hosts=$(_front_hosts "${_vhost_dir}/${_site}")
    if [[ -n "${_hosts}" ]]; then
      _front_write "${_root}" "${_front_new}" "${_site}" "${_hosts}" \
        "$(_geo_lines "${_ip_sorted}")" "$(_area_lines "${_kind}" "${_api_open}")"
      _front_kept+=("${_site}.http.conf" "${_site}.srv.conf")
    fi

    _configured+=("${_site}")
  done < "${_ctrl}"

  # What this run made goes in place only inside the real directories: every
  # map before any gate, so a gate never lands without the map it reads.
  if ! _acct_in_real_dir "${_map_path}" _confs_put_here "${_new}/user_admin_access_map" \
    || ! _acct_in_real_dir "${_srv_path}" _confs_put_here "${_new}/user_admin_access" \
    || ! _acct_in_real_dir "${_front_path}" _confs_put_here "${_front_new}"; then
    echo "Could not put every user_admin_access file of ${_root}; retrying next run."
    return 1
  fi

  # Prune front files not written by this run: an unlisted site, a site with
  # no rendered vhost, or every one while the front does not include them.
  _acct_in_real_dir "${_front_path}" _prune_here "user_admin_access front file" \
    "${_front_path}" "" "${_front_kept[@]}"

  # Prune fragments (both dirs) for sites no longer in the control file, the
  # server-scope gate before the map that defines its variable: a gate that
  # outlives its map fails any reload that lands in between.
  for _d in "${_srv_path}" "${_map_path}"; do
    _acct_in_real_dir "${_d}" _prune_here "user_admin_access fragment" "${_d}" .conf \
      "${_configured[@]}"
  done

  if _nginx_held_down; then
    _ua_markers_put
    echo "user_admin_access written (${_root}); replication standby -- reload skipped (web tier held)."
    return 0
  fi

  # Validate the whole host nginx config; revert THIS instance on failure. The
  # front copies are dropped on every failure and never restored: they only
  # narrow what the front lets through, and an older set could still claim a
  # name that has since moved to another site.
  local _ct
  _ct=$(service nginx configtest 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Nginx configtest failed after user_admin_access update (${_root}): ${_ct}"
    _acct_in_real_dir "${_front_path}" _confs_drop_here > /dev/null
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_root} user_admin_access to last known good."
      ### Prove the archive is readable BEFORE deleting what is on disk: an
      ### unverified one could leave the instance with no fragments at all.
      if _lg_fetch "${_backup_dir}" "${_last_good_name}" "${_work}/lg"; then
        _ua_restore
        service nginx reload
      else
        _policy_alert "user_admin_access.refused.${_root}" \
          "user_admin_access: last-good backup unreadable, fragments kept (${_root})" \
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
      echo "No last-good backup for ${_root}; removing just-written fragments."
      _acct_in_real_dir "${_srv_path}" _confs_drop_here > /dev/null
      _acct_in_real_dir "${_map_path}" _confs_drop_here > /dev/null
    fi
    # The front copies were dropped: forget the front state so the next pass
    # rebuilds them.
    _acct_in_real_dir "${_srv_path}" rm -f -- ./.ua_front_hash
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after user_admin_access update (${_root}); reverting."
    _acct_in_real_dir "${_front_path}" _confs_drop_here > /dev/null
    if [[ -f "${_last_good_backup}" ]]; then
      if _lg_fetch "${_backup_dir}" "${_last_good_name}" "${_work}/lg"; then
        _ua_restore
        service nginx reload
      else
        _policy_alert "user_admin_access.refused.${_root}" \
          "user_admin_access: last-good backup unreadable, fragments kept (${_root})" \
          "last-good backup ${_last_good_backup} is unreadable -- fragments left in place."
      fi
    fi
    _acct_in_real_dir "${_srv_path}" rm -f -- ./.ua_front_hash
    return 1
  fi

  # Success: refresh this instance's last-good backup + change-gate markers.
  ### An unverified last-good archive is worse than none: the revert path
  ### above trusts it enough to delete the live fragments. It holds what
  ### this run put, packed from the work dir.
  if ! _lg_store "${_new}" "${_backup_dir}" "${_last_good_name}" \
    user_admin_access_map user_admin_access; then
    _policy_alert "user_admin_access.lgstore.${_root}" \
      "user_admin_access: last-good backup not written (${_root})" \
      "could not write a verifiable last-good user_admin_access backup; removing it"
    _acct_in_real_dir "${_backup_dir}" rm -f -- "./${_last_good_name}"
  fi
  _ua_markers_put
  echo "user_admin_access updated (${_root}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
}

# The change-gate markers of the running _process_instance put in its real
# srv dir.
_ua_markers_put() {
  _acct_in_real_dir "${_srv_path}" _acct_put_pairs_here \
    .ua_last_mod_time "${_current_mod_time}" .ua_ssh_ips_hash "${_ssh_ips_hash}" \
    .ua_emit_version "${_emit_version}" .ua_cms_kinds_hash "${_kinds_hash}" \
    .ua_front_hash "${_front_hash}"
}

# The fragments of the running _process_instance replaced by those unpacked
# from its last-good archive into the work dir: every gate dropped before
# the maps, every map put before the gates.
_ua_restore() {
  _acct_in_real_dir "${_srv_path}" _confs_drop_here > /dev/null
  _acct_in_real_dir "${_map_path}" _confs_drop_here > /dev/null
  if ! _acct_in_real_dir "${_map_path}" _confs_put_here "${_work}/lg/user_admin_access_map" \
    || ! _acct_in_real_dir "${_srv_path}" _confs_put_here "${_work}/lg/user_admin_access"; then
    _policy_alert "user_admin_access.restore.${_root}" \
      "user_admin_access: restoring the last-good backup FAILED (${_root})" \
      "restoring ${_last_good_backup} FAILED after the fragments were removed."
  fi
  _acct_in_real_dir "${_front_path}" _confs_drop_here > /dev/null
}

# Octopus instances only. Real instances carry tools/drush; the BOA-canonical
# instance test transparently skips every non-instance pseudo-dir (arch, all,
# legacy, global, static, custom, …), not just 'arch' by name.
for _root in /data/disk/*; do
  [[ -d "${_root}" ]] || continue
  if [[ ! -e "${_root}/tools/drush" ]]; then
    # Only an instance that is gone: an Octopus upgrade moves tools/drush
    # aside for a moment while the instance itself stays live.
    [[ ! -e "/root/.${_root##*/}.octopus.cnf" \
      && -d "${_root}/config/includes/user_admin_access_front" ]] \
      && _front_clear "${_root}/config/includes/user_admin_access_front" \
        "${_root}/config/includes/user_admin_access/.ua_front_hash"
    continue
  fi
  _process_instance "${_root}"
done

exit 0
