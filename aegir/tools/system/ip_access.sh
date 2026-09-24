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

_front_write() {
  # A site's two front copies: the list as a geo, judged at the wildcard SSL
  # front on the real visitor for every name the site's vhost serves. The host
  # map comes first and selects the rest, so an unrelated request costs one
  # lookup. A redundant /32 or /128 is dropped so it cannot collide as a
  # duplicate geo network with the plain anti-lockout form. The front copies of
  # every context share one http{}: their variables are keyed by context and
  # site, never by the site name alone.
  # $1 = the context's fragments dir, $2 = its front dir, $3 = site,
  # $4 = the names (one per line), $5 = the sorted list.
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
  # $4 = its front marker.
  [[ -n "${_front_on}" ]] || return 0
  local _f _site _hosts _list _ip _new=""
  for _f in "$1"/*.conf; do
    [[ -f "${_f}" && ! -L "${_f}" ]] || continue
    _site=$(basename "${_f}" .conf)
    [[ ${_site} =~ ${_site_name_regex} ]] || continue
    [[ -s "$2/${_site}.http.conf" && -s "$2/${_site}.srv.conf" ]] && continue
    grep -qx "deny all;" "${_f}" || continue
    _list=$(awk '$1 == "allow" && NF == 2 { sub(/;$/, "", $2); print $2 }' "${_f}" \
      | while IFS= read -r _ip; do _valid_ip "${_ip}" && echo "${_ip}"; done | sort -u)
    [[ -n "${_list}" ]] || continue
    _build_owners
    _hosts=$(_front_hosts "$3/${_site}")
    [[ -n "${_hosts}" ]] || continue
    mkdir -p "$2" 2> /dev/null
    _front_write "$1" "$2" "${_site}" "${_hosts}" "${_list}" 2> /dev/null
    if [[ -f "$2/${_site}.http.conf" && -s "$2/${_site}.http.conf" \
      && -f "$2/${_site}.srv.conf" && -s "$2/${_site}.srv.conf" ]]; then
      _new="${_new} ${_site}"
      echo "The frozen list of ${_site} now holds at the front too"
    else
      # Never leave half a pair: a gate without its maps fails the box-wide
      # configtest, and nothing below tests a site that is not in _new.
      rm -f "$2/${_site}.srv.conf" "$2/${_site}.http.conf"
      echo "Could not write the front copy of ${_site} in $2; retrying next run"
    fi
  done
  [[ -n "${_new}" ]] || return 0
  rm -f "$4"
  _nginx_held_down && return 0
  if service nginx configtest &> /dev/null; then
    service nginx reload
  else
    for _site in ${_new}; do rm -f "$2/${_site}.srv.conf" "$2/${_site}.http.conf"; done
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

_process_context() {
  local _input_file="$1" _nginx_path="$2" _backup_dir="$3" _vhost_dir="$4"
  if [[ ! -f "${_input_file}" ]]; then
    _front_fill_frozen "${_nginx_path}" "${_nginx_path}_front" "${_vhost_dir}" "${_nginx_path}/.access_front_hash"
    _front_keep_valid "${_nginx_path}_front" "${_vhost_dir}" "${_nginx_path}/.access_front_hash"
    return 0
  fi

  local _current_backup="${_backup_dir}/.nginx_access_conf.current.bak.tar.gz"
  local _last_good_backup="${_backup_dir}/.nginx_access_conf.last_good.bak.tar.gz"
  local _front_path="${_nginx_path}_front"
  local _timestamp_file="${_nginx_path}/.access_last_mod_time"
  local _ssh_hash_file="${_nginx_path}/.ssh_ips_hash"
  local _version_file="${_nginx_path}/.access_emit_version"
  local _front_file="${_nginx_path}/.access_front_hash"

  mkdir -p "${_nginx_path}" "${_front_path}" "${_backup_dir}"

  # Change-gate: regenerate when the control file changed, the host SSH-IP set
  # changed (so a newly logged-in admin is added to every allow list), the emit
  # version bumped, or the front state or a listed site's routed names changed.
  local _current_mod_time _last_mod_time=0 _previous_ssh_hash="" _last_version=""
  local _front_hash _previous_front_hash=""
  _current_mod_time=$(stat -c %Y "${_input_file}" 2>/dev/null) || return 0
  _ensure_owners "${_input_file}" "${_vhost_dir}"
  _front_hash=$(_front_signature "${_input_file}" "${_vhost_dir}" | md5sum | awk '{print $1}')
  [[ -f "${_timestamp_file}" ]] && _last_mod_time=$(cat "${_timestamp_file}" 2>/dev/null || echo 0)
  [[ -f "${_ssh_hash_file}" ]] && _previous_ssh_hash=$(cat "${_ssh_hash_file}" 2>/dev/null || echo "")
  [[ -f "${_version_file}" ]] && _last_version=$(cat "${_version_file}" 2>/dev/null || echo "")
  [[ -f "${_front_file}" ]] && _previous_front_hash=$(cat "${_front_file}" 2>/dev/null || echo "")
  if [[ "${_current_mod_time}" -le "${_last_mod_time}" \
     && "${_ssh_ips_hash}" == "${_previous_ssh_hash}" \
     && "${_last_version}" == "${_emit_version}" \
     && "${_front_hash}" == "${_previous_front_hash}" ]]; then
    return 0
  fi

  [[ -d "${_nginx_path}" ]] && tar -czf "${_current_backup}" -C "${_nginx_path}" . 2>/dev/null

  # Generate per-site allow/deny fragments; track configured sites and written
  # front files for pruning.
  local -a _configured=() _front_kept=()
  local _line _site _ip _ip_sorted _frag _tmp _hosts _f _base _keep _s
  local -a _ip_list
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
    _frag="${_nginx_path}/${_site}.conf"
    _tmp="${_nginx_path}/.${_site}.tmp.$$"
    {
      for _ip in ${_ip_sorted}; do echo "allow ${_ip};"; done
      echo "deny all;"
    } > "${_tmp}"
    mv -f "${_tmp}" "${_frag}"

    # Front copy: the same list, judged at the wildcard SSL front on the real
    # visitor for every name the site's vhost serves.
    _hosts=""
    [[ -n "${_front_on}" ]] && _hosts=$(_front_hosts "${_vhost_dir}/${_site}")
    if [[ -n "${_hosts}" ]]; then
      _front_write "${_nginx_path}" "${_front_path}" "${_site}" "${_hosts}" "${_ip_sorted}"
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
      echo "Pruned stale ip_access front file: ${_base} (${_input_file})"
    fi
  done

  # Prune fragments for sites no longer in the control file (restriction lifted).
  for _f in "${_nginx_path}"/*.conf; do
    [[ -e "${_f}" ]] || continue
    _base=$(basename "${_f}" .conf)
    _keep=""
    for _s in "${_configured[@]}"; do
      [[ "${_s}" == "${_base}" ]] && _keep="yes" && break
    done
    if [[ -z "${_keep}" ]]; then
      rm -f "${_f}"
      echo "Pruned stale ip_access fragment: ${_base}.conf (${_input_file})"
    fi
  done

  if _nginx_held_down; then
    echo "${_current_mod_time}" > "${_timestamp_file}"
    echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
    echo "${_emit_version}" > "${_version_file}"
    echo "${_front_hash}" > "${_front_file}"
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
    rm -f "${_front_path}"/*.srv.conf "${_front_path}"/*.conf
    if [[ -f "${_last_good_backup}" ]]; then
      echo "Reverting ${_input_file} ip_access to last known good."
      ### Prove the archive is readable BEFORE deleting what is on disk:
      ### the old order wiped every fragment and then extracted from an
      ### unverified tarball, so a corrupt or truncated backup left the
      ### box with no access-control fragments at all.
      if tar -tzf "${_last_good_backup}" &> /dev/null; then
        rm -f "${_nginx_path}"/*.conf
        if ! tar -xzf "${_last_good_backup}" -C "${_nginx_path}" 2>/dev/null; then
          echo "ALRT: restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
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
      echo "No last-good backup for ${_input_file}; removing just-written fragments."
      rm -f "${_nginx_path}"/*.conf
    fi
    # The front copies were dropped and the markers may have come back from
    # the archive: forget the front state so the next pass rebuilds them.
    rm -f "${_front_file}"
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed after ip_access update (${_input_file}); reverting."
    rm -f "${_front_path}"/*.srv.conf "${_front_path}"/*.conf
    if [[ -f "${_last_good_backup}" ]]; then
      if tar -tzf "${_last_good_backup}" &> /dev/null; then
        rm -f "${_nginx_path}"/*.conf
        if ! tar -xzf "${_last_good_backup}" -C "${_nginx_path}" 2>/dev/null; then
          echo "ALRT: restoring ${_last_good_backup} FAILED after the fragments were removed."
        fi
        service nginx reload
      else
        echo "ALRT: last-good backup ${_last_good_backup} is unreadable -- fragments left in place."
      fi
    fi
    rm -f "${_front_file}"
    return 1
  fi

  ### An unverified last-good archive is worse than none: the revert path
  ### above trusts it enough to delete the live fragments.
  if tar -czf "${_last_good_backup}" -C "${_nginx_path}" . 2>/dev/null \
    && tar -tzf "${_last_good_backup}" &> /dev/null; then
    :
  else
    echo "ALRT: could not write a verifiable last-good ip_access backup; removing it"
    rm -f "${_last_good_backup}"
  fi
  echo "${_current_mod_time}" > "${_timestamp_file}"
  echo "${_ssh_ips_hash}" > "${_ssh_hash_file}"
  echo "${_emit_version}" > "${_version_file}"
  echo "${_front_hash}" > "${_front_file}"
  echo "ip_access updated (${_input_file}): ${_configured[*]:-none}; Nginx reloaded."
  return 0
}

# Master (sqladmin) context — seed the control file if absent.
mkdir -p /var/aegir/control/ip
[[ ! -f /var/aegir/control/ip/access.txt ]] && echo "sqladmin.com 192.168.1.1" > /var/aegir/control/ip/access.txt
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
