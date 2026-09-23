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
#
# HTTPS for a site without its own certificate arrives through the wildcard SSL
# front (nginx_wild_ssl.conf), which proxies to the site's :80 vhost, where the
# peer is always 127.0.0.1 -- an address the anti-lockout allows.  So once the
# deployed front includes them, each listed site also gets two front files in
# user_admin_access_front/: <site>.http.conf (its own geo and $uri map, and a
# $host map of the server names in the site's rendered vhost that no other
# vhost on the box also serves) and <site>.srv.conf (the 403 gate).  The front
# judges them against the real visitor.  A site with no rendered vhost gets no
# front files.
#
# Grav 2 and Textpattern sites keep their admin surface elsewhere, so a site whose
# platform root positively reads as one of them gets ONE extra line in the same
# $uri map, and nothing else changes — no new variable, no new include, and a
# Drupal or Backdrop site's fragment stays byte-identical:
#   Grav 2       /api  — Admin2 at /admin is only a shell; every login, account,
#                page, media and config operation runs through the API plugin, so
#                a list that stopped at /admin left the data surface open.
#   Textpattern  /txpadmin — where BOA maps the Textpattern admin.
# A Grav site that serves a deliberately public headless API adds the keyword
# `api-open` to its record: /admin stays on the list, /api stays public.
#
# Control file (Octopus only — regular-site vhosts; hostmaster has its own,
# out-of-scope vhost):
#   /data/disk/<oct>/static/control/ip/user_admin.txt
#   Record: `example.com  203.0.113.10  10.0.0.0/8  2001:db8::/32  2001:db8::1`
#   Record: `headless.example.com  203.0.113.10  api-open`

_aegir_health_check="/var/aegir/.drush/hm.alias.drushrc.php"
_drush_health_check="/var/aegir/drush/drush"
_server_ip_file="/root/.found_correct_ipv4.cnf"

# Bump when the emitted directive shape changes, to force regeneration
# independent of the control-file mtime.
_emit_version="3"

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
  # $1 = instance root, $2 = site name.
  local _alias="${1}/.drush/${2}.alias.drushrc.php"
  local _r
  [[ -f "${_alias}" ]] || return 0
  _r=$(grep "'root' =>" "${_alias}" 2>/dev/null | head -n 1 | cut -d"'" -f4)
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
  # rendered vhost ($1), one per line. Regular files only: a FIFO would hang
  # the read under the shared lock. No file, no names.
  [[ -f "$1" ]] || return 0
  awk -v max="${_host_max}" "${_names_awk}" "$1" 2>/dev/null | sort -u
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
  local _n _h _v
  [[ -z "${_owners_built}" ]] || return 0
  _owners_built="yes"
  while read -r _n _h; do
    _host_owners["${_h}"]="${_n}"
  done < <(for _v in /var/aegir/config/server_master/nginx/vhost.d/* \
      /data/disk/*/config/server_master/nginx/vhost.d/*; do
      [[ -f "${_v}" ]] && printf '%s\0' "${_v}"
    done | xargs -0 -r awk -v max="${_host_max}" "${_names_awk}" 2>/dev/null \
      | sort | uniq -c)
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
  local _f _any=""
  for _f in "$1"/*.srv.conf "$1"/*.conf; do
    [[ -e "${_f}" ]] || continue
    rm -f "${_f}"
    _any="yes"
  done
  rm -f "$2"
  [[ -n "${_any}" ]] || return 0
  echo "Dropped the front copies of a skipped context: $1"
  _nginx_held_down && return 0
  service nginx configtest &> /dev/null && service nginx reload
}

_front_keep_valid() {
  # A context whose control file is gone keeps its lists exactly as they are,
  # over HTTP and HTTPS alike: a deletion never travels to a mirror or a
  # migration target (static/control is copied additively), so lifting here
  # would lift one box only and the lock would come back after a failover or
  # cutover. To lift, remove a site's line or empty the file. Nothing here
  # writes a new copy, so none is ever dropped either: each host map follows
  # the names only its site's vhost serves, as the vhost fragments follow the
  # vhost they are included in. A new alias is covered on HTTPS as on HTTP, a
  # name that moved to another site leaves the map, and a site with no such
  # name left keeps an empty map (inert) that a later run can fill again.
  # $1 = front dir, $2 = the context's vhost.d dir, $3 = its front marker.
  local _f _site _want _have _tmp _changed=""
  for _f in "$1"/*.http.conf; do
    [[ -e "${_f}" ]] || continue
    _build_owners
    _site=$(basename "${_f}" .http.conf)
    _want=$(_front_hosts "$2/${_site}" | tr '\n' ' ')
    _have=$(awk '/^map \$host /{p=1; next} p && /^}/{exit} p && $2 == "1;" {print $1}' "${_f}" \
      | sort | tr '\n' ' ')
    [[ "${_want}" == "${_have}" ]] && continue
    _tmp="$1/.${_site}.http.tmp.$$"
    if awk -v want="${_want}" '
        /^map \$host / { print; p = 1; next }
        p && /^}/ { n = split(want, w, " "); for (i = 1; i <= n; i++) print "  " w[i] " 1;"; p = 0; print; next }
        p && $2 == "1;" { next }
        { print }' "${_f}" > "${_tmp}" && mv -f "${_tmp}" "${_f}"; then
      _changed="yes"
      echo "The front copy of ${_site} now claims: ${_want:-no name}"
    else
      rm -f "${_tmp}"
    fi
  done
  [[ -n "${_changed}" ]] || return 0
  rm -f "$3"
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

_geo_lines() {
  # Body of an allow-list geo. $1 = the sorted, de-duplicated entries.
  local _e
  echo "  default 0;"
  for _e in $1; do echo "  ${_e} 1;"; done
}

_area_lines() {
  # Body of the $uri map for the admin surface. $1 = CMS kind, $2 = api-open.
  echo "  default 0;"
  echo "  ~*^/+(?:user|admin)(?:/|\$) 1;"
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
  _sshd_ports=$(/usr/sbin/sshd -T 2>/dev/null | awk '/^port /{print $2}')
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
  local _current_backup="${_backup_dir}/.nginx_user_admin.current.bak.tar.gz"
  local _last_good_backup="${_backup_dir}/.nginx_user_admin.last_good.bak.tar.gz"
  local _timestamp_file="${_srv_path}/.ua_last_mod_time"
  local _ssh_hash_file="${_srv_path}/.ua_ssh_ips_hash"
  local _version_file="${_srv_path}/.ua_emit_version"
  local _kinds_file="${_srv_path}/.ua_cms_kinds_hash"
  local _front_file="${_srv_path}/.ua_front_hash"

  if [[ ! -f "${_input_file}" ]]; then
    _front_keep_valid "${_front_path}" "${_vhost_dir}" "${_front_file}"
    return 0
  fi
  [[ -d "${_root}/config/includes" ]] || return 0

  mkdir -p "${_map_path}" "${_srv_path}" "${_front_path}" "${_backup_dir}"

  # Change-gate: regenerate only when the control file changed, the host SSH-IP
  # set changed (a newly logged-in admin must propagate), the emit version
  # bumped, a listed site's CMS kind changed, or the front state or a listed
  # site's routed names changed.  No change -> no write, no reload.  The kind
  # and the names are baked into the fragments, so a record written before
  # its site exists, a name re-created as another CMS or an alias added later
  # must regenerate without anyone touching the control file.
  local _current_mod_time _last_mod_time=0 _previous_ssh_hash="" _last_version=""
  local _kinds_hash _previous_kinds_hash="" _front_hash _previous_front_hash=""
  _current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null) || return 0
  _kinds_hash=$(_kinds_signature "${_root}" "${_input_file}" | md5sum | awk '{print $1}')
  _ensure_owners "${_input_file}" "${_vhost_dir}"
  _front_hash=$(_front_signature "${_root}" "${_input_file}" | md5sum | awk '{print $1}')
  [[ -f "${_timestamp_file}" ]] && _last_mod_time=$(cat "${_timestamp_file}" 2>/dev/null || echo 0)
  [[ -f "${_ssh_hash_file}" ]] && _previous_ssh_hash=$(cat "${_ssh_hash_file}" 2>/dev/null || echo "")
  [[ -f "${_version_file}" ]] && _last_version=$(cat "${_version_file}" 2>/dev/null || echo "")
  [[ -f "${_kinds_file}" ]] && _previous_kinds_hash=$(cat "${_kinds_file}" 2>/dev/null || echo "")
  [[ -f "${_front_file}" ]] && _previous_front_hash=$(cat "${_front_file}" 2>/dev/null || echo "")
  if [[ "${_current_mod_time}" -le "${_last_mod_time}" \
     && "${_ssh_ips_hash}" == "${_previous_ssh_hash}" \
     && "${_last_version}" == "${_emit_version}" \
     && "${_kinds_hash}" == "${_previous_kinds_hash}" \
     && "${_front_hash}" == "${_previous_front_hash}" ]]; then
    return 0
  fi

  # Back up the site-vhost fragment dirs before regenerating. The front copies
  # are never backed up: a failed run drops them (see below).
  tar -czf "${_current_backup}" -C "${_root}/config/includes" \
    user_admin_access_map user_admin_access 2>/dev/null

  # Generate per-site fragments; track configured sites and written front
  # files for pruning.
  local -a _configured=() _fields _ip_list _front_kept=()
  local _line _site _hash _ip _norm _ip_sorted _frag _tmp _e _d _f _base _keep _s
  local _kind _api_open _hosts _fhash
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
    _frag="${_map_path}/${_site}.conf"
    _tmp="${_map_path}/.${_site}.tmp.$$"
    {
      echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
      echo "# Per-site /user + /admin IP access for ${_site}."
      echo "geo \$ua_ip_ok_${_hash} {"
      _geo_lines "${_ip_sorted}"
      echo "}"
      # BOA enforces Drupal clean URLs, so /user and /admin always arrive as the
      # real request path in \$uri (which nginx percent-decodes and normalises —
      # /./ , and // under the default merge_slashes on). We match \$uri only: the
      # legacy ?q=admin query form is not a clean path and is not served by
      # default on BOA, and \$arg_q cannot be reliably matched at nginx (it is
      # neither percent-decoded nor de-duplicated the way Drupal reads \$_GET['q']).
      # ^/+ (not ^/) also catches a multi-slash //admin even if a vhost ever
      # disabled merge_slashes.
      echo "map \$uri \$ua_u_${_hash} {"
      _area_lines "${_kind}" "${_api_open}"
      echo "}"
      echo "map \"\$ua_u_${_hash}\$ua_ip_ok_${_hash}\" \$ua_deny_${_hash} {"
      echo "  default 0;"
      echo "  \"10\" 1;"
      echo "}"
    } > "${_tmp}"
    mv -f "${_tmp}" "${_frag}"

    # server-scope fragment: the 403 gate for the admin surface.
    _frag="${_srv_path}/${_site}.conf"
    _tmp="${_srv_path}/.${_site}.tmp.$$"
    {
      echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
      echo "if (\$ua_deny_${_hash}) { return 403; }"
    } > "${_tmp}"
    mv -f "${_tmp}" "${_frag}"

    # Front copy: the same list, judged at the wildcard SSL front on the real
    # visitor for every name the site's vhost serves. The host map comes
    # first and selects the rest, so an unrelated request costs one lookup.
    _hosts=""
    [[ -n "${_front_on}" ]] && _hosts=$(_front_hosts "${_vhost_dir}/${_site}")
    if [[ -n "${_hosts}" ]]; then
      # The front copies of every instance share one http{}: key their
      # variables by instance and site, never by the site name alone.
      _fhash=$(echo -n "${_root}/${_site}" | md5sum | awk '{print $1}' | cut -c1-12)
      _frag="${_front_path}/${_site}.http.conf"
      _tmp="${_front_path}/.${_site}.http.tmp.$$"
      {
        echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
        echo "# Wildcard SSL front copy of the /user + /admin list for ${_site}."
        echo "map \$host \$uaf_h_${_fhash} {"
        echo "  hostnames;"
        echo "  default 0;"
        # read, not a bare for: a *.name wildcard must never glob.
        while IFS= read -r _e; do echo "  ${_e} 1;"; done <<< "${_hosts}"
        echo "}"
        echo "geo \$uaf_ok_${_fhash} {"
        _geo_lines "${_ip_sorted}"
        echo "}"
        echo "map \$uri \$uaf_u_${_fhash} {"
        _area_lines "${_kind}" "${_api_open}"
        echo "}"
        echo "map \"\$uaf_u_${_fhash}\$uaf_ok_${_fhash}\" \$uaf_d_${_fhash} {"
        echo "  default 0;"
        echo "  \"10\" 1;"
        echo "}"
        echo "map \$uaf_h_${_fhash} \$uaf_deny_${_fhash} {"
        echo "  default 0;"
        echo "  1 \$uaf_d_${_fhash};"
        echo "}"
      } > "${_tmp}"
      mv -f "${_tmp}" "${_frag}"
      _frag="${_front_path}/${_site}.srv.conf"
      _tmp="${_front_path}/.${_site}.srv.tmp.$$"
      {
        echo "# Generated by /var/xdrago/user_admin_access.sh — DO NOT EDIT BY HAND."
        echo "if (\$uaf_deny_${_fhash}) { return 403; }"
      } > "${_tmp}"
      mv -f "${_tmp}" "${_frag}"
      _front_kept+=("${_site}.http.conf" "${_site}.srv.conf")
    fi

    _configured+=("${_site}")
  done < "${_input_file}"

  # Prune front files not written by this run: an unlisted site, a site with
  # no rendered vhost, or every one while the front does not include them.
  for _f in "${_front_path}"/*.srv.conf "${_front_path}"/*.conf; do
    [[ -e "${_f}" ]] || continue
    _base=$(basename "${_f}")
    _keep=""
    for _s in "${_front_kept[@]}"; do
      [[ "${_s}" == "${_base}" ]] && _keep="yes" && break
    done
    if [[ -z "${_keep}" ]]; then
      rm -f "${_f}"
      echo "Pruned stale user_admin_access front file: ${_base} (${_front_path})"
    fi
  done

  # Prune fragments (both dirs) for sites no longer in the control file.
  for _d in "${_map_path}" "${_srv_path}"; do
    for _f in "${_d}"/*.conf; do
      [[ -e "${_f}" ]] || continue
      _base=$(basename "${_f}" .conf)
      _keep=""
      for _s in "${_configured[@]}"; do
        [[ "${_s}" == "${_base}" ]] && _keep="yes" && break
      done
      if [[ -z "${_keep}" ]]; then
        rm -f "${_f}"
        echo "Pruned stale user_admin_access fragment: ${_base}.conf (${_d})"
      fi
    done
  done

  if _nginx_held_down; then
    echo "${_current_mod_time}" > "${_timestamp_file}"
    echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
    echo "${_emit_version}" > "${_version_file}"
    echo "${_kinds_hash}" > "${_kinds_file}"
    echo "${_front_hash}" > "${_front_file}"
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
    rm -f "${_front_path}"/*.srv.conf "${_front_path}"/*.conf
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_root} user_admin_access to last known good."
      ### Prove the archive is readable BEFORE deleting what is on disk: an
      ### unverified one could leave the instance with no fragments at all.
      if tar -tzf "${_last_good_backup}" &> /dev/null; then
        rm -f "${_map_path}"/*.conf "${_srv_path}"/*.conf
        if ! tar -xzf "${_last_good_backup}" -C "${_root}/config/includes" 2>/dev/null; then
          echo "ALRT: restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
        rm -f "${_front_path}"/*.srv.conf "${_front_path}"/*.conf
        service nginx reload
      else
        echo "ALRT: last-good backup ${_last_good_backup} is unreadable -- keeping the"
        echo "ALRT: fragments now on disk rather than deleting them for an archive"
        echo "ALRT: that cannot be restored. Fix ${_input_file} and re-run."
        # With the front copies gone the rest may pass again.
        service nginx configtest &> /dev/null && service nginx reload
      fi
    else
      # No last-good yet (a first run failed configtest). nginx never reloaded the
      # bad config (configtest gates the reload), so just drop the fragments this
      # run wrote — otherwise a bad one lingers and keeps EVERY tool's configtest
      # failing box-wide until someone finds and fixes it.
      echo "No last-good backup for ${_root}; removing just-written fragments."
      rm -f "${_map_path}"/*.conf "${_srv_path}"/*.conf
    fi
    # The front copies were dropped and the markers may have come back from
    # the archive: forget the front state so the next pass rebuilds them.
    rm -f "${_front_file}"
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after user_admin_access update (${_root}); reverting."
    rm -f "${_front_path}"/*.srv.conf "${_front_path}"/*.conf
    if [[ -f "${_last_good_backup}" ]]; then
      if tar -tzf "${_last_good_backup}" &> /dev/null; then
        rm -f "${_map_path}"/*.conf "${_srv_path}"/*.conf
        if ! tar -xzf "${_last_good_backup}" -C "${_root}/config/includes" 2>/dev/null; then
          echo "ALRT: restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
        rm -f "${_front_path}"/*.srv.conf "${_front_path}"/*.conf
        service nginx reload
      else
        echo "ALRT: last-good backup ${_last_good_backup} is unreadable -- fragments left in place."
      fi
    fi
    rm -f "${_front_file}"
    return 1
  fi

  # Success: refresh this instance's last-good backup + change-gate markers.
  ### An unverified last-good archive is worse than none: the revert path
  ### above trusts it enough to delete the live fragments.
  if tar -czf "${_last_good_backup}" -C "${_root}/config/includes" \
    user_admin_access_map user_admin_access 2>/dev/null \
    && tar -tzf "${_last_good_backup}" &> /dev/null; then
    :
  else
    echo "ALRT: could not write a verifiable last-good user_admin_access backup; removing it"
    rm -f "${_last_good_backup}"
  fi
  echo "${_current_mod_time}" > "${_timestamp_file}"
  echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
  echo "${_emit_version}" > "${_version_file}"
  echo "${_kinds_hash}" > "${_kinds_file}"
  echo "${_front_hash}" > "${_front_file}"
  echo "user_admin_access updated (${_root}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
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
