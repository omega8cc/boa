#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

[ -d "/var/backups/csf/water" ] || mkdir -p /var/backups/csf/water

# BOA-canonical fetch options (the shared _crlGet): verified TLS, follow up to 3
# redirects, --fail so an HTTP error yields no body (an error page is never parsed
# as ranges), retry transient failures, iCab UA.
_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"

# Strict IPv4 / IPv4-CIDR validation. These lists feed the csf ALLOW whitelist,
# so only value-valid addresses (each octet 0-255, prefix 0-32) may be written:
# a merely digit-shaped token from a provider format change or a poisoned/garbage
# response (e.g. 999.1.1.1/99) must never reach the firewall. _emit_valid_ips
# filters a candidate list on stdin and logs what it drops (same intent as the
# octet check already guarding the DHCP path below).
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_is_ipv4_or_cidr() { [[ "$1" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}(/(3[0-2]|[12]?[0-9]))?$ ]]; }
_emit_valid_ips() {
  local _x
  for _x in $(cat); do
    if _is_ipv4_or_cidr "${_x}"; then
      echo "${_x}"
    else
      echo "water: skipping invalid range: ${_x}" >&2
    fi
  done
}

# Strict IPv6 / IPv6-CIDR validation for the nginx-native v6 allow store below:
# the same address grammar scan_nginx.sh and nginx_deny6.sh accept (a strict
# subset of what nginx parses), so a merely colon-shaped token from a provider
# format change can never reach the whitelist. Prefix /1-/128; a bare address
# means an exact host. /0 is refused — it would whitelist the entire IPv6
# internet.
_ipv6_hex="[0-9A-Fa-f]{1,4}"
_ipv6_v4tail="(${_ipv4_octet}\.){3}${_ipv4_octet}"
_ipv6_addr="((${_ipv6_hex}:){7}${_ipv6_hex}|(${_ipv6_hex}:){1,7}:|(${_ipv6_hex}:){1,6}:${_ipv6_hex}|(${_ipv6_hex}:){1,5}(:${_ipv6_hex}){1,2}|(${_ipv6_hex}:){1,4}(:${_ipv6_hex}){1,3}|(${_ipv6_hex}:){1,3}(:${_ipv6_hex}){1,4}|(${_ipv6_hex}:){1,2}(:${_ipv6_hex}){1,5}|${_ipv6_hex}:((:${_ipv6_hex}){1,6})|:((:${_ipv6_hex}){1,7}|:)|::(ffff(:0{1,4})?:)?${_ipv6_v4tail}|(${_ipv6_hex}:){1,4}:${_ipv6_v4tail})"
_is_ipv6_or_cidr() { [[ "$1" =~ ^${_ipv6_addr}(/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9]))?$ ]]; }
_emit_valid_ips6() {
  local _x
  for _x in $(cat); do
    if _is_ipv6_or_cidr "${_x}"; then
      echo "${_x}"
    else
      echo "water: skipping invalid IPv6 range: ${_x}" >&2
    fi
  done
}

# nginx-native IPv6 allow store consumed by scan_nginx's _is_whitelisted_ip:
# csf.allow cannot hold an IPv6 entry (csf is IPv4-only), so the published
# crawler ipv6Prefix ranges land here instead and exempt a legitimate IPv6
# crawler from the adaptive IDS scoring and the nginx-native v6 ban. Same
# remove-tagged-then-add refresh model as the csf.allow providers, with one
# deliberate difference: an empty fetch (endpoint down, format change) KEEPS
# the provider's existing entries — a failed refresh must never strip
# whitelist protection from a live crawler range. Untagged (manual operator)
# lines are never touched.
_WEB6_ALLOW="/var/xdrago/monitor/log/web6.allow"
_update_web6_allow() {
  local _tag="${1}" _list="${2}" _IP6
  [ -d "${_WEB6_ALLOW%/*}" ] || mkdir -p "${_WEB6_ALLOW%/*}"
  [ -f "${_WEB6_ALLOW}" ] || touch ${_WEB6_ALLOW}
  if [ -z "${_list}" ]; then
    echo "water: empty ${_tag} IPv6 list; keeping existing ${_WEB6_ALLOW} entries"
    return 0
  fi
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing ${_tag} ips from ${_WEB6_ALLOW}
    sed -i "/${_tag}/d" ${_WEB6_ALLOW}
    wait
  fi
  for _IP6 in ${_list}; do
    if ! grep -qF "${_IP6} # ${_tag}" ${_WEB6_ALLOW} 2>/dev/null; then
      echo "${_IP6} not yet listed in ${_WEB6_ALLOW}"
      echo "${_IP6} # ${_tag} ips" >> ${_WEB6_ALLOW}
    else
      echo "${_IP6} already listed in ${_WEB6_ALLOW}"
    fi
  done
}

# Escape dots so an IP can be used safely in a regex (dots are wildcards
# there — 1.2.3.4 would otherwise match 112.3.4).
_rx() {
  local _s="${1}"
  echo "${_s//./\\.}"
}

# Strict IPv4 for ban/promotion candidates: the archive logs are
# attacker-adjacent input, so only a value-valid address outside the
# reserved ranges (0/8, 127/8 loopback, 224+ multicast) may ever steer
# a csf -d at an address.
_is_ipv4_strict() {
  local _ip="${1}"
  [[ "${_ip}" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}$ ]] || return 1
  local _o1="${_ip%%.*}"
  (( _o1 == 0 || _o1 == 127 || _o1 >= 224 )) && return 1
  return 0
}

_ip_to_int() {
  local _a _b _c _d
  IFS=. read -r _a _b _c _d <<< "${1}"
  echo $(( (_a << 24) + (_b << 16) + (_c << 8) + _d ))
}

# Return 0 if any CIDR block read from stdin covers the IP.
_cidr_covers_ip() {
  local _ip="${1}"
  local _int; _int="$(_ip_to_int "${_ip}")"
  local _entry _net _pfx _mask
  while IFS= read -r _entry; do
    _net="${_entry%/*}"; _pfx="${_entry#*/}"
    [[ "${_pfx}" =~ ^[0-9]+$ ]] || continue
    (( _pfx >= 1 && _pfx <= 31 )) || continue
    [[ "${_net}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || continue
    _mask=$(( (0xFFFFFFFF << (32 - _pfx)) & 0xFFFFFFFF ))
    if (( ( _int & _mask ) == ( $(_ip_to_int "${_net}") & _mask ) )); then
      return 0
    fi
  done
  return 1
}

# Membership test against a CSF state file, honouring every entry form CSF
# accepts: plain first-field IP, IP/32, advanced syntax (s=/d=), and covering
# CIDR blocks anywhere in an entry — the same set the per-IP `csf -g` fork
# it replaces used to detect, tested in-shell instead.
_csf_file_matches_ip() {
  local _ip="${1}" _file="${2}"
  local _ip_rx; _ip_rx="$(_rx "${_ip}")"
  [[ -f "${_file}" ]] || return 1
  grep -qE "(^|\|s=|\|d=)${_ip_rx}(/32)?([[:space:]#|]|$)" "${_file}" 2>/dev/null \
    && return 0
  cut -d'#' -f1 "${_file}" 2>/dev/null \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' \
    | sort -u \
    | _cidr_covers_ip "${_ip}"
}

# Return 0 if the IP has an active temp allow (any port).
# /var/lib/csf/csf.tempallow line format: epoch|ip|port|direction|ttl|comment
_is_temp_allowed() {
  local _ip="${1}"
  [[ -f "/var/lib/csf/csf.tempallow" ]] || return 1
  awk -F'|' -v ip="${_ip}" \
    '$2 == ip { _found=1; exit } END { exit !_found }' \
    /var/lib/csf/csf.tempallow 2>/dev/null
}

_whitelist_ip_pingdom() {
  # Pingdom provides probe IPs in multiple formats:
  #   Plain IPv4 list: https://my.pingdom.com/probes/ipv4  (preferred - no parsing needed)
  #   RSS feed:        https://my.pingdom.com/probes/feed  (fallback - XML parsing required)
  # The plain list is simpler and less fragile; RSS is kept as fallback.
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing pingdom ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-pingdom-${_NOW}
    sed -i "s/.*pingdom.*//g" /etc/csf/csf.allow
    wait
  fi
  _IPS=$(curl ${_crlGet} https://my.pingdom.com/probes/ipv4 \
    | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' \
    | sort \
    | uniq 2>&1)
  if [ -z "${_IPS}" ]; then
    echo "pingdom ipv4 endpoint failed, falling back to RSS feed"
    _IPS=$(curl ${_crlGet} https://my.pingdom.com/probes/feed \
      | grep '<pingdom:ip>' \
      | sed 's/.*::.*//g' \
      | sed 's/[^0-9\.]//g' \
      | sort \
      | uniq 2>&1)
  fi
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  echo _IPS pingdom list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    echo checking csf.allow pingdom ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # pingdom ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

_whitelist_ip_cloudflare() {
  # Cloudflare publishes IPv4 ranges at two endpoints (both return identical data):
  #   Plain text: https://www.cloudflare.com/ips-v4  (primary)
  #   JSON API:   https://api.cloudflare.com/client/v4/ips  (fallback, no auth needed)
  # Reference: https://www.cloudflare.com/ips/
  # Allow both web ports: CF edges terminate visitors on 443 as much as 80, and
  # a d=80-only entry leaves 443 exposed to csf.deny hits on a busy edge.
  # Deliberately NOT mirrored into csf.ignore (unlike the migration proxy):
  # realip bans the real client at nginx, and an lfd-immune CF range would mask
  # a misbehaving edge. IPv6 ranges are also deliberately not ingested while
  # TCP6_IN excludes 80/443 - they would match no inbound traffic.
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing cloudflare ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-cloudflare-${_NOW}
    # Delete the tagged lines outright rather than blanking them: the old
    # s///-to-empty form left one blank line per wipe, and with two lines
    # (d=80 + d=443) per CIDR now they would accumulate twice as fast.
    sed -i "/cloudflare/d" /etc/csf/csf.allow
    wait
  fi
  _IPS=$(curl ${_crlGet} https://www.cloudflare.com/ips-v4 \
    | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/[0-9]*' \
    | sort \
    | uniq 2>&1)
  if [ -z "${_IPS}" ]; then
    echo "cloudflare ips-v4 endpoint failed, falling back to JSON API"
    _IPS=$(curl ${_crlGet} https://api.cloudflare.com/client/v4/ips \
      | grep -o '"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/[0-9]*"' \
      | sed 's/"//g' \
      | sort \
      | uniq 2>&1)
  fi
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  echo _IPS cloudflare list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    for _PORT in 80 443; do
      if ! grep -qF "tcp|in|d=${_PORT}|s=${_IP} # cloudflare ips" /etc/csf/csf.allow 2>/dev/null; then
        echo "${_IP} not yet listed for d=${_PORT} in /etc/csf/csf.allow"
        echo "tcp|in|d=${_PORT}|s=${_IP} # cloudflare ips" >> /etc/csf/csf.allow
      else
        echo "${_IP} already listed for d=${_PORT} in /etc/csf/csf.allow"
      fi
    done
  done
}

_whitelist_ip_migration_proxy() {
  # During an xmass/xoct migration the OLD host becomes a reverse proxy that
  # forwards all migrated traffic to this host, so the proxy is the only TCP
  # peer csf/lfd ever sees for those sites -- and lfd cannot be made realip-
  # aware. Hard-whitelist the proxy link on ports 80+443 and csf.ignore it so a
  # flood relayed through the proxy can never get the proxy itself banned (which
  # would blackhole every migrated site at once); the realip layer still recovers
  # and bans the real client at nginx. Source IPs come from the control file the
  # migration tooling writes; an absent file means no migration is in progress,
  # and the tagged entries are stripped (teardown). The tag is also added to the
  # csf.allow diff-guard's ignore list below so these entries are not treated as
  # a manual edit and reverted.
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing migration proxy ips from csf.allow and csf.ignore
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-migproxy-${_NOW}
    sed -i "s/.*migration proxy.*//g" /etc/csf/csf.allow
    sed -i "s/.*migration proxy.*//g" /etc/csf/csf.ignore
    wait
  fi
  if [ ! -e "/root/.migration.proxy.ips.cnf" ]; then
    echo "no migration proxy control file; nothing to whitelist"
    return 0
  fi
  _IPS=$(cat /root/.migration.proxy.ips.cnf \
    | sed 's/#.*//' \
    | tr -s ' \t' '\n' \
    | sort \
    | uniq 2>&1)
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  echo _IPS migration proxy list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    for _PORT in 80 443; do
      if ! grep -qF "tcp|in|d=${_PORT}|s=${_IP} # migration proxy" /etc/csf/csf.allow 2>/dev/null; then
        echo "${_IP} not yet listed for d=${_PORT} in /etc/csf/csf.allow"
        echo "tcp|in|d=${_PORT}|s=${_IP} # migration proxy" >> /etc/csf/csf.allow
      fi
    done
    if ! grep -qF "${_IP} # migration proxy" /etc/csf/csf.ignore 2>/dev/null; then
      echo "${_IP} not yet listed in /etc/csf/csf.ignore"
      echo "${_IP} # migration proxy" >> /etc/csf/csf.ignore
    fi
  done
}

_whitelist_ip_imperva() {
  # Imperva Cloud WAF IP ranges API - no authentication required:
  # https://my.imperva.com/api/integration/v1/ips
  # Formats: text | json | apache | nginx | iptables (default: json)
  # Reference: https://docs.imperva.com/howto/c85245b7
  # Current ranges (as of 2024): 199.83.128.0/21, 198.143.32.0/19, 149.126.72.0/21,
  #   103.28.248.0/22, 185.11.124.0/22, 192.230.64.0/18, 45.64.64.0/22, 107.154.0.0/16,
  #   45.60.0.0/16, 45.223.0.0/16, 131.125.128.0/17 (added May 2023)
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing imperva ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-imperva-${_NOW}
    sed -i "s/.*imperva.*//g" /etc/csf/csf.allow
    wait
  fi
  _IPS=$(curl ${_crlGet} --data "resp_format=text" https://my.imperva.com/api/integration/v1/ips \
    | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/[0-9]*' \
    | sort \
    | uniq 2>&1)
  if [ -z "${_IPS}" ]; then
    echo "imperva text endpoint failed, falling back to JSON format"
    _IPS=$(curl ${_crlGet} --data "resp_format=json" https://my.imperva.com/api/integration/v1/ips \
      | grep -o '"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/[0-9]*"' \
      | sed 's/"//g' \
      | sort \
      | uniq 2>&1)
  fi
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  echo _IPS imperva list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    echo checking csf.allow imperva ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # imperva ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  # Clean up Imperva ranges from csf.deny
  # All current Imperva ranges by significant octets:
  sed -i "/^199\.83\./d" /etc/csf/csf.deny
  sed -i "/^198\.143\./d" /etc/csf/csf.deny
  sed -i "/^149\.126\./d" /etc/csf/csf.deny
  sed -i "/^103\.28\./d" /etc/csf/csf.deny
  sed -i "/^185\.11\./d" /etc/csf/csf.deny
  sed -i "/^192\.230\./d" /etc/csf/csf.deny
  sed -i "/^45\.64\./d" /etc/csf/csf.deny
  sed -i "/^107\.154\./d" /etc/csf/csf.deny
  sed -i "/^45\.60\./d" /etc/csf/csf.deny
  sed -i "/^45\.223\./d" /etc/csf/csf.deny
  sed -i "/^131\.125\./d" /etc/csf/csf.deny
  wait
}

_whitelist_ip_googlebot() {
  # One fetch feeds both families: ipv4Prefix goes to csf.allow below,
  # ipv6Prefix to the nginx-native v6 allow store (csf cannot hold IPv6).
  # Fetch BEFORE the tagged-line cleanup: an empty fetch (endpoint down,
  # format change) must keep the existing entries — the same fail-safe the
  # v6 store documents — never strip live crawler ranges for a day.
  _JSON=$(curl ${_crlGet} https://developers.google.com/static/search/apis/ipranges/googlebot.json 2>&1)
  _IPS=$(echo "${_JSON}" \
    | grep -o '"ipv4Prefix": *"[^"]*"' \
    | sed 's/"ipv4Prefix": *"//g' \
    | sed 's/"//g' \
    | sort \
    | uniq 2>&1)
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  _IPS6=$(echo "${_JSON}" \
    | grep -o '"ipv6Prefix": *"[^"]*"' \
    | sed 's/"ipv6Prefix": *"//g' \
    | sed 's/"//g' \
    | sort \
    | uniq 2>&1)
  _IPS6=$(echo "${_IPS6}" | _emit_valid_ips6)
  echo _IPS6 googlebot list..
  echo ${_IPS6}
  _update_web6_allow googlebot "${_IPS6}"
  echo _IPS googlebot list..
  echo ${_IPS}
  # Heal past bans from csf.deny. Static octets, deliberately BEFORE the
  # empty-fetch guard so healing still runs on a failed fetch.
  sed -i "/^66\.249\./d" /etc/csf/csf.deny
  sed -i "/^192\.178\./d" /etc/csf/csf.deny
  sed -i "/^34\.\(22\|64\|65\|80\|88\|89\|96\|100\|101\|118\|126\|146\|147\|151\|152\|154\|155\|165\|175\|176\)\./d" /etc/csf/csf.deny
  sed -i "/^35\.247\./d" /etc/csf/csf.deny
  wait
  if [ -z "${_IPS}" ]; then
    echo "water: empty googlebot IPv4 list; keeping existing csf.allow entries"
    return 0
  fi
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing googlebot ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-googlebot-${_NOW}
    sed -i "s/.*googlebot.*//g" /etc/csf/csf.allow
    wait
  fi
  for _IP in ${_IPS}; do
    echo checking csf.allow googlebot ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # googlebot ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

_whitelist_ip_google_special() {
  # Google's special-case crawlers (AdsBot, Mediapartners, the SERP favicon
  # fetcher, ...) operate from their own Google-owned rate-limited-proxy
  # ranges, published separately from googlebot.json — a favicon fetch banned
  # here silently drops the site's icon from search results. One fetch feeds
  # both families: ipv4Prefix goes to csf.allow below, ipv6Prefix to the
  # nginx-native v6 allow store (csf cannot hold IPv6). Fetch BEFORE the
  # tagged-line cleanup: an empty fetch must keep the existing entries (the
  # same fail-safe the v6 store documents), never strip live crawler ranges.
  _JSON=$(curl ${_crlGet} https://developers.google.com/static/search/apis/ipranges/special-crawlers.json 2>&1)
  _IPS=$(echo "${_JSON}" \
    | grep -o '"ipv4Prefix": *"[^"]*"' \
    | sed 's/"ipv4Prefix": *"//g' \
    | sed 's/"//g' \
    | sort \
    | uniq 2>&1)
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  _IPS6=$(echo "${_JSON}" \
    | grep -o '"ipv6Prefix": *"[^"]*"' \
    | sed 's/"ipv6Prefix": *"//g' \
    | sed 's/"//g' \
    | sort \
    | uniq 2>&1)
  _IPS6=$(echo "${_IPS6}" | _emit_valid_ips6)
  echo _IPS6 googlespecial list..
  echo ${_IPS6}
  _update_web6_allow googlespecial "${_IPS6}"
  echo _IPS googlespecial list..
  echo ${_IPS}
  # Heal past bans of these ranges from csf.deny. Static octets, deliberately
  # BEFORE the empty-fetch guard so healing still runs on a failed fetch.
  # Third-octet-scoped: the published set covers only slices of wider Google
  # blocks, and the slices in 66.249 and 192.178 are already cleaned by the
  # Googlebot pass above.
  sed -i "/^72\.14\.199\./d" /etc/csf/csf.deny
  sed -i "/^74\.125\.\(148\|149\|150\|151\|216\|217\|218\|219\)\./d" /etc/csf/csf.deny
  sed -i "/^108\.177\.2\./d" /etc/csf/csf.deny
  sed -i "/^209\.85\.238\./d" /etc/csf/csf.deny
  wait
  if [ -z "${_IPS}" ]; then
    echo "water: empty googlespecial IPv4 list; keeping existing csf.allow entries"
    return 0
  fi
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing googlespecial ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-googlespecial-${_NOW}
    sed -i "s/.*googlespecial.*//g" /etc/csf/csf.allow
    wait
  fi
  for _IP in ${_IPS}; do
    echo checking csf.allow googlespecial ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # googlespecial ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

_whitelist_ip_microsoft() {
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing microsoft ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-microsoft-${_NOW}
    sed -i "s/.*microsoft.*//g" /etc/csf/csf.allow
    wait
  fi
  # One fetch feeds both families. bingbot.json publishes no ipv6Prefix
  # entries as of 2026-07 (Bingbot crawls over IPv4 only), so the v6 leg is
  # forward-compatible plumbing: an empty list keeps the store untouched.
  _JSON=$(curl ${_crlGet} https://www.bing.com/toolbox/bingbot.json 2>&1)
  _IPS=$(echo "${_JSON}" \
    | grep -o '"ipv4Prefix": *"[^"]*"' \
    | sed 's/"ipv4Prefix": *"//g' \
    | sed 's/"//g' \
    | sort \
    | uniq 2>&1)
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  _IPS6=$(echo "${_JSON}" \
    | grep -o '"ipv6Prefix": *"[^"]*"' \
    | sed 's/"ipv6Prefix": *"//g' \
    | sed 's/"//g' \
    | sort \
    | uniq 2>&1)
  _IPS6=$(echo "${_IPS6}" | _emit_valid_ips6)
  echo _IPS6 microsoft list..
  echo ${_IPS6}
  _update_web6_allow microsoft "${_IPS6}"
  echo _IPS microsoft list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    echo checking csf.allow microsoft ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # microsoft ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  # Remove all current Bingbot ranges from csf.deny
  # Legacy ranges (no longer in JSON but may be in older deny rules)
  sed -i "/^65\.5[2-5]\./d" /etc/csf/csf.deny
  sed -i "/^199\.30\./d" /etc/csf/csf.deny
  # Current Azure-based Bingbot ranges
  sed -i "/^13\.\(66\|67\|69\|71\)\./d" /etc/csf/csf.deny
  sed -i "/^20\.\(15\|36\|43\|74\|79\|125\)\./d" /etc/csf/csf.deny
  sed -i "/^40\.77\./d" /etc/csf/csf.deny
  sed -i "/^40\.79\./d" /etc/csf/csf.deny
  sed -i "/^51\.105\./d" /etc/csf/csf.deny
  sed -i "/^52\.\(167\|231\)\./d" /etc/csf/csf.deny
  sed -i "/^139\.217\./d" /etc/csf/csf.deny
  sed -i "/^157\.55\./d" /etc/csf/csf.deny
  sed -i "/^191\.233\./d" /etc/csf/csf.deny
  sed -i "/^207\.46\./d" /etc/csf/csf.deny
  wait
}

_whitelist_ip_sucuri() {
  # Sucuri does not publish a machine-readable IP list endpoint.
  # IP ranges are maintained as static documentation at:
  # https://docs.sucuri.net/website-firewall/sucuri-firewall-troubleshooting-guide/
  # Review that page periodically and update _IPS below if ranges change.
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing sucuri ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-sucuri-${_NOW}
    sed -i "s/.*sucuri.*//g" /etc/csf/csf.allow
    wait
  fi
  _IPS="192.88.134.0/23 185.93.228.0/22 66.248.200.0/22 208.109.0.0/22"
  echo _IPS sucuri list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    echo checking csf.allow sucuri ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # sucuri ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  sed -i "/^192\.88\.13[4-5]\./d" /etc/csf/csf.deny
  sed -i "/^185\.93\.22[89]\.\|^185\.93\.23[01]\./d" /etc/csf/csf.deny
  sed -i "/^66\.248\.20[0-3]\./d" /etc/csf/csf.deny
  sed -i "/^208\.109\.[0-3]\./d" /etc/csf/csf.deny
  wait
}

_whitelist_ip_authzero() {
  # Auth0 publishes a machine-readable IP list with region breakdown and changelog at:
  # https://cdn.auth0.com/ip-ranges.json
  # The list is updated ahead of any functional changes; check last_updated_at to detect changes.
  # Only whitelist regions relevant to your Auth0 tenant(s). Currently fetching all regions.
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing authzero ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-authzero-${_NOW}
    sed -i "s/.*authzero.*//g" /etc/csf/csf.allow
    wait
  fi
  _IPS=$(curl ${_crlGet} https://cdn.auth0.com/ip-ranges.json \
    | grep -o '"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/[0-9]*"' \
    | grep -v ':' \
    | sed 's/"//g' \
    | sort \
    | uniq 2>&1)
  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  echo _IPS authzero list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    echo checking csf.allow authzero ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # authzero ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  # Clean up any authzero IPs from csf.deny (current + previously known retired IPs)
  # Since all Auth0 IPs are /32 host routes, we match on the specific addresses from
  # the changelog (both active and historically removed entries) to ensure old deny
  # rules don't linger. The fetch above handles csf.allow; deny cleanup is best-effort
  # by known prefix patterns from Auth0's AWS IP space.
  for _DENY_IP in $(echo "${_IPS}" | sed 's|/32||g'); do
    sed -i "/^${_DENY_IP//./\\.}$/d" /etc/csf/csf.deny
    sed -i "/^${_DENY_IP//./\\.}\/32$/d" /etc/csf/csf.deny
  done
  wait
}

_whitelist_ip_site24x7_extra() {
  # These ranges cover Site24x7 backend/infrastructure IPs (not monitoring probes).
  # Monitoring probe IPs are handled dynamically via DNS in _whitelist_ip_site24x7().
  # No machine-readable endpoint exists for these ranges; review periodically at:
  # https://www.site24x7.com/community/filter/announcements/
  _IPS="87.252.213.0/24 89.36.170.0/24 185.172.199.0/27 185.172.199.128/26 185.230.214.0/23"
  echo _IPS site24x7_extra list..
  echo ${_IPS}
  for _IP in ${_IPS}; do
    echo checking csf.allow site24x7_extra ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # site24x7_extra ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  if [ -e "/etc/boa/.ignore.site24x7.firewall.cnf" ]; then
    for _IP in ${_IPS}; do
      echo checking csf.ignore site24x7_extra ${_IP} now...
      _IP_CHECK=$(cat /etc/csf/csf.ignore \
        | cut -d '#' -f1 \
        | sort \
        | uniq \
        | tr -d "\s" \
        | grep -F "${_IP}" 2>&1)
      if [ -z "${_IP_CHECK}" ]; then
        echo "${_IP} not yet listed in /etc/csf/csf.ignore"
        echo "${_IP} # site24x7_extra ips" >> /etc/csf/csf.ignore
      else
        echo "${_IP} already listed in /etc/csf/csf.ignore"
      fi
    done
  fi
}

_whitelist_ip_site24x7() {
  if [ ! -e "/etc/boa/.whitelist.dont.cleanup.cnf" ]; then
    echo removing site24x7 ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-site24x7-${_NOW}
    sed -i "s/.*site24x7.*//g" /etc/csf/csf.allow
    wait
    echo removing site24x7 ips from csf.ignore
    sed -i "s/.*site24x7.*//g" /etc/csf/csf.ignore
    wait
  fi

  _IPS=$(host site24x7.enduserexp.com 1.1.1.1  \
    | grep 'has address' \
    | cut -d ' ' -f4 \
    | sed 's/[^0-9\.]//g' \
    | sort \
    | uniq 2>&1)

  if [ -z "${_IPS}" ] \
    || [[ ! "${_IPS}" =~ "104.236.16.22" ]] \
    || [[ "${_IPS}" =~ "HINFO" ]]; then
    _IPS=$(dig site24x7.enduserexp.com \
      | grep 'IN.*A' \
      | cut -d 'A' -f2 \
      | sed 's/[^0-9\.]//g' \
      | sort \
      | uniq 2>&1)
  fi

  _IPS=$(echo "${_IPS}" | _emit_valid_ips)
  echo _IPS site24x7 list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow site24x7 ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep -F "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # site24x7 ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done

  if [ -e "/etc/boa/.ignore.site24x7.firewall.cnf" ]; then
    for _IP in ${_IPS}; do
      echo checking csf.ignore site24x7 ${_IP} now...
      _IP_CHECK=$(cat /etc/csf/csf.ignore \
        | cut -d '#' -f1 \
        | sort \
        | uniq \
        | tr -d "\s" \
        | grep -F "${_IP}" 2>&1)
      if [ -z "${_IP_CHECK}" ]; then
        echo "${_IP} not yet listed in /etc/csf/csf.ignore"
        echo "${_IP} # site24x7 ips" >> /etc/csf/csf.ignore
      else
        echo "${_IP} already listed in /etc/csf/csf.ignore"
      fi
    done
  fi

  if [ ! -e "/root/.whitelist.site24x7.cnf" ]; then
    csf -tf
    wait
    csf -df
    wait
    touch /root/.whitelist.site24x7.cnf
    [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
  fi
}

_local_ip_rg() {
  if [ -e "/root/.local.IP.list" ]; then
    echo "the file /root/.local.IP.list already exists"
    for _IP in `hostname -I`; do
      _IP_CHECK=$(cat /root/.local.IP.list \
        | cut -d '#' -f1 \
        | sort \
        | uniq \
        | tr -d "\s" \
        | grep -F "${_IP}" 2>&1)
      if [ -z "${_IP_CHECK}" ]; then
        echo "${_IP} not yet listed in /root/.local.IP.list"
        echo "${_IP} # local IP address" >> /root/.local.IP.list
      else
        echo "${_IP} already listed in /root/.local.IP.list"
      fi
    done
    for _IP in `cat /root/.local.IP.list \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s"`; do
      if [ ! -z "${_IP}" ]; then
        echo removing ${_IP} from d/t firewall rules
        csf -ar ${_IP} &> /dev/null
        csf -dr ${_IP} &> /dev/null
        csf -tr ${_IP} &> /dev/null
      fi
      if [ ! -e "/root/.local.IP.csf.listed" ] && [ ! -z "${_IP}" ]; then
        echo removing ${_IP} from csf.ignore
        sed -i "s/^${_IP} .*//g" /etc/csf/csf.ignore
        wait
        echo removing ${_IP} from csf.allow
        _NOW=$(date +%y%m%d-%H%M%S)
        cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-local-${_NOW}
        sed -i "s/^${_IP} .*//g" /etc/csf/csf.allow
        wait
        echo adding ${_IP} to csf.ignore
        echo "${_IP} # local.IP.list" >> /etc/csf/csf.ignore
        wait
        echo adding ${_IP} to csf.allow
        echo "${_IP} # local.IP.list" >> /etc/csf/csf.allow
        wait
      fi
      [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    done
    touch /root/.local.IP.csf.listed
  else
    echo "the file /root/.local.IP.list does not exist"
    rm -f /root/.tmp.IP.list*
    rm -f /root/.local.IP.list*
    for _IP in `hostname -I`;do echo ${_IP} >> /root/.tmp.IP.list;done
    for _IP in `cat /root/.tmp.IP.list \
      | sort \
      | uniq`;do echo "${_IP} # local IP address" >> /root/.local.IP.list;done
    rm -f /root/.tmp.IP.list*
  fi
}

_guard_stats() {
  if [ ! -e "${_HX}" ] && [ -e "${_HA}" ]; then
    mv -f ${_HA} ${_HX}
  fi
  if [ ! -e "${_WX}" ] && [ -e "${_WA}" ]; then
    mv -f ${_WA} ${_WX}
  fi
  if [ ! -e "${_FX}" ] && [ -e "${_FA}" ]; then
    mv -f ${_FA} ${_FX}
  fi
  if [ -e "${_HA}" ]; then
    _FW_MUTATED=
    for _IP in `cat ${_HA} | cut -d '#' -f1 | sort | uniq`; do
      _IP_RV=
      _NR_TEST="0"
      if ! _is_ipv4_strict "${_IP}"; then
        echo "${_IP} is not a valid public IPv4 address, ignoring ${_HA}"
        continue
      fi
      ### Field-exact count — a substring grep let 1.2.3.4 also count the
      ### lines belonging to 91.2.3.45 and promote on inflated numbers.
      _NR_TEST=$(awk -v ip="${_IP}" '$1 == ip { _n++ } END { print _n + 0 }' ${_HA} 2>/dev/null)
      if [ -e "/root/.local.IP.list" ]; then
        _IP_CHECK=$(grep -E "^[[:space:]]*$(_rx "${_IP}")([[:space:]#]|$)" /root/.local.IP.list 2>/dev/null)
        if [ ! -z "${_IP_CHECK}" ]; then
          _NR_TEST="0"
          echo "${_IP} is a local IP address, ignoring ${_HA}"
        fi
      fi
      if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge 12 ]; then
        echo ${_IP} ${_NR_TEST}
        _FW_TEST=
        ### Permanent block means membership in csf.deny; csf -g cannot be
        ### used for that test because an active TEMP ban also prints DENY
        ### (DENYIN chain), which kept persistent attackers from ever being
        ### promoted to a permanent block. The allow side is tested in-shell
        ### against csf.allow/csf.tempallow (plain, advanced, CIDR, temp) —
        ### the same set the per-IP `csf -g` fork it replaces detected.
        _IP_ESC=$(printf '%s' "${_IP}" | sed 's/\./\\./g')
        _FW_TEST=$(grep -E "^${_IP_ESC}([ #]|$)" /etc/csf/csf.deny 2>/dev/null)
        if _csf_file_matches_ip "${_IP}" /etc/csf/csf.allow; then
          echo "${_IP} already allowed on port 22, cleaning up blocks"
          csf -dr ${_IP}
          csf -tr ${_IP}
          _FW_MUTATED=YES
        elif _is_temp_allowed "${_IP}"; then
          ### Never csf -tr here — that would remove the temp allow itself.
          echo "${_IP} is temporarily allowed on port 22"
        elif [ ! -z "${_FW_TEST}" ]; then
          echo "${_IP} already denied on port 22"
        else
          _IP_RV=$(host -s ${_IP} 2>&1 | tr -d '\n' | tr -cd 'a-zA-Z0-9 ._-' | cut -c1-80)
          if [ "${_NR_TEST}" -ge 24 ]; then
            echo "Deny ${_IP} permanently ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} do not delete Brute force SSH Server ${_NR_TEST} attacks ${_IP_RV}
          else
            echo "Deny ${_IP} until limits rotation ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} Brute force SSH Server ${_NR_TEST} attacks ${_IP_RV}
          fi
          _FW_MUTATED=YES
        fi
      fi
    done
    ### One reassert per archive pass when the rules changed — not one per IP.
    if [ "${_FW_MUTATED}" = "YES" ] && [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
      synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    fi
  fi
  if [ -e "${_WA}" ]; then
    _FW_MUTATED=
    for _IP in `cat ${_WA} | cut -d '#' -f1 | sort | uniq`; do
      _IP_RV=
      _NR_TEST="0"
      if ! _is_ipv4_strict "${_IP}"; then
        echo "${_IP} is not a valid public IPv4 address, ignoring ${_WA}"
        continue
      fi
      ### Field-exact count — a substring grep let 1.2.3.4 also count the
      ### lines belonging to 91.2.3.45 and promote on inflated numbers.
      _NR_TEST=$(awk -v ip="${_IP}" '$1 == ip { _n++ } END { print _n + 0 }' ${_WA} 2>/dev/null)
      if [ -e "/root/.local.IP.list" ]; then
        _IP_CHECK=$(grep -E "^[[:space:]]*$(_rx "${_IP}")([[:space:]#]|$)" /root/.local.IP.list 2>/dev/null)
        if [ ! -z "${_IP_CHECK}" ]; then
          _NR_TEST="0"
          echo "${_IP} is a local IP address, ignoring ${_WA}"
        fi
      fi
      if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge 12 ]; then
        echo ${_IP} ${_NR_TEST}
        _FW_TEST=
        ### Permanent block means membership in csf.deny; csf -g cannot be
        ### used for that test because an active TEMP ban also prints DENY
        ### (DENYIN chain), which kept persistent attackers from ever being
        ### promoted to a permanent block. The allow side is tested in-shell
        ### against csf.allow/csf.tempallow (plain, advanced, CIDR, temp) —
        ### the same set the per-IP `csf -g` fork it replaces detected.
        _IP_ESC=$(printf '%s' "${_IP}" | sed 's/\./\\./g')
        _FW_TEST=$(grep -E "^${_IP_ESC}([ #]|$)" /etc/csf/csf.deny 2>/dev/null)
        if _csf_file_matches_ip "${_IP}" /etc/csf/csf.allow; then
          echo "${_IP} already allowed on port 80, cleaning up blocks"
          csf -dr ${_IP}
          csf -tr ${_IP}
          _FW_MUTATED=YES
        elif _is_temp_allowed "${_IP}"; then
          ### Never csf -tr here — that would remove the temp allow itself.
          echo "${_IP} is temporarily allowed on port 80"
        elif [ ! -z "${_FW_TEST}" ]; then
          echo "${_IP} already denied on port 80"
        else
          _IP_RV=$(host -s ${_IP} 2>&1 | tr -d '\n' | tr -cd 'a-zA-Z0-9 ._-' | cut -c1-80)
          if [ "${_NR_TEST}" -ge 24 ]; then
            echo "Deny ${_IP} permanently ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} do not delete Brute force Web Server ${_NR_TEST} attacks ${_IP_RV}
          else
            echo "Deny ${_IP} until limits rotation ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} Brute force Web Server ${_NR_TEST} attacks ${_IP_RV}
          fi
          _FW_MUTATED=YES
        fi
      fi
    done
    ### One reassert per archive pass when the rules changed — not one per IP.
    if [ "${_FW_MUTATED}" = "YES" ] && [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
      synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    fi
  fi
  if [ -e "${_FA}" ]; then
    _FW_MUTATED=
    for _IP in `cat ${_FA} | cut -d '#' -f1 | sort | uniq`; do
      _IP_RV=
      _NR_TEST="0"
      if ! _is_ipv4_strict "${_IP}"; then
        echo "${_IP} is not a valid public IPv4 address, ignoring ${_FA}"
        continue
      fi
      ### Field-exact count — a substring grep let 1.2.3.4 also count the
      ### lines belonging to 91.2.3.45 and promote on inflated numbers.
      _NR_TEST=$(awk -v ip="${_IP}" '$1 == ip { _n++ } END { print _n + 0 }' ${_FA} 2>/dev/null)
      if [ -e "/root/.local.IP.list" ]; then
        _IP_CHECK=$(grep -E "^[[:space:]]*$(_rx "${_IP}")([[:space:]#]|$)" /root/.local.IP.list 2>/dev/null)
        if [ ! -z "${_IP_CHECK}" ]; then
          _NR_TEST="0"
          echo "${_IP} is a local IP address, ignoring ${_FA}"
        fi
      fi
      if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge 12 ]; then
        echo ${_IP} ${_NR_TEST}
        _FW_TEST=
        ### Permanent block means membership in csf.deny; csf -g cannot be
        ### used for that test because an active TEMP ban also prints DENY
        ### (DENYIN chain), which kept persistent attackers from ever being
        ### promoted to a permanent block. The allow side is tested in-shell
        ### against csf.allow/csf.tempallow (plain, advanced, CIDR, temp) —
        ### the same set the per-IP `csf -g` fork it replaces detected.
        _IP_ESC=$(printf '%s' "${_IP}" | sed 's/\./\\./g')
        _FW_TEST=$(grep -E "^${_IP_ESC}([ #]|$)" /etc/csf/csf.deny 2>/dev/null)
        if _csf_file_matches_ip "${_IP}" /etc/csf/csf.allow; then
          echo "${_IP} already allowed on port 21, cleaning up blocks"
          csf -dr ${_IP}
          csf -tr ${_IP}
          _FW_MUTATED=YES
        elif _is_temp_allowed "${_IP}"; then
          ### Never csf -tr here — that would remove the temp allow itself.
          echo "${_IP} is temporarily allowed on port 21"
        elif [ ! -z "${_FW_TEST}" ]; then
          echo "${_IP} already denied on port 21"
        else
          _IP_RV=$(host -s ${_IP} 2>&1 | tr -d '\n' | tr -cd 'a-zA-Z0-9 ._-' | cut -c1-80)
          if [ "${_NR_TEST}" -ge 24 ]; then
            echo "Deny ${_IP} permanently ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} do not delete Brute force FTP Server ${_NR_TEST} attacks ${_IP_RV}
          else
            echo "Deny ${_IP} until limits rotation ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} Brute force FTP Server ${_NR_TEST} attacks ${_IP_RV}
          fi
          _FW_MUTATED=YES
        fi
      fi
    done
    ### One reassert per archive pass when the rules changed — not one per IP.
    if [ "${_FW_MUTATED}" = "YES" ] && [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
      synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    fi
  fi
}

_whitelist_ip_dns() {
  csf -tr 1.1.1.1
  csf -tr 8.8.8.8
  csf -tr 9.9.9.9
  csf -dr 1.1.1.1
  csf -dr 8.8.8.8
  csf -dr 9.9.9.9
  [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
  sed -i "s/.*1.1.1.1.*//g"  /etc/csf/csf.allow
  sed -i "s/.*1.1.1.1.*//g"  /etc/csf/csf.ignore
  sed -i "s/.*8.8.8.8.*//g"  /etc/csf/csf.allow
  sed -i "s/.*8.8.8.8.*//g"  /etc/csf/csf.ignore
  sed -i "s/.*9.9.9.9.*//g"  /etc/csf/csf.allow
  sed -i "s/.*9.9.9.9.*//g"  /etc/csf/csf.ignore
  echo "tcp|out|d=53|d=1.1.1.1 # Cloudflare DNS" >> /etc/csf/csf.allow
  echo "tcp|out|d=53|d=8.8.8.8 # Google DNS" >> /etc/csf/csf.allow
  echo "tcp|out|d=53|d=9.9.9.9 # Cleaner DNS" >> /etc/csf/csf.allow
  sed -i "/^$/d" /etc/csf/csf.ignore
  sed -i "/^$/d" /etc/csf/csf.allow
}

if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
  if [ -e "/root/.local.IP.list" ]; then
    echo local dr/tr start $(date)
    for _IP in `cat /root/.local.IP.list \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s"`; do
      csf -dr ${_IP} &> /dev/null
      csf -tr ${_IP} &> /dev/null
      [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    done
  fi

  _n=$((RANDOM%120+90))
  touch /run/water.pid
  echo Waiting ${_n} seconds...
  sleep ${_n}

  _NOW=$(date +%y%m%d-%H%M%S)
  _NOW=${_NOW//[^0-9-]/}
  _useCnfUpdate=NO
  _vBs="/var/backups"
  _useCnf="/etc/csf/csf.allow"
  _preCnf="${_vBs}/dragon/t/csf.allow.backup-${_NOW}"
  _brkCnf="${_vBs}/dragon/t/csf.allow.broken-${_NOW}"
  if [ -f "${_useCnf}" ]; then
    mkdir -p ${_vBs}/dragon/t/
    cp -af ${_useCnf} ${_preCnf}
  fi

  _whitelist_ip_dns
  _whitelist_ip_pingdom
  _whitelist_ip_cloudflare
  _whitelist_ip_migration_proxy
  _whitelist_ip_googlebot
  _whitelist_ip_google_special
  _whitelist_ip_microsoft
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_imperva
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_sucuri
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_authzero
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_site24x7_extra
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_site24x7

  if [ -f "${_useCnf}" ]; then
    _diffCnfTest=$(diff -w -B \
      -I pingdom \
      -I cloudflare \
      -I googlebot \
      -I googlespecial \
      -I microsoft \
      -I imperva \
      -I sucuri \
      -I authzero \
      -I site24x7 \
      -I migration \
      -I DHCP ${_useCnf} ${_preCnf} 2>&1)
    if [ -z "${_diffCnfTest}" ]; then
      _useCnfUpdate=YES
      echo "YES $(date) diff0 empty" >> ${_vBs}/dragon/t/csf.log
    else
      _diffCnfTest=$(echo -n ${_diffCnfTest} | fmt -su -w 2500 2>&1)
      echo "NO $(date) diff1 ${_diffCnfTest}" >> ${_vBs}/dragon/t/csf.log
    fi
    if [[ "${_diffCnfTest}" =~ "No such file or directory" ]]; then
      echo "NO $(date) diff3 ${_diffCnfTest}" >> ${_vBs}/dragon/t/csf.log
    fi
  fi
  if [ "${_useCnfUpdate}" = "NO" ]; then
    cp -af ${_useCnf} ${_brkCnf}
    cp -af ${_preCnf} ${_useCnf}
  fi

  if [ -e "/etc/boa/.full.csf.cleanup.cnf" ]; then
    sed -i "s/.*do not delete.*//g" /etc/csf/csf.deny
    wait
    sed -i "/^$/d" /etc/csf/csf.deny
    wait
  fi

  pkill -9 -f ConfigServer
  killall sleep &> /dev/null
  rm -f /etc/csf/csf.error
  if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
    csf -ra &> /dev/null
    synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
  else
    csf -r &> /dev/null
  fi
  csf -tf
  ### Linux kernel TCP SACK CVEs mitigation
  ### CVE-2019-11477 SACK Panic
  ### CVE-2019-11478 SACK Slowness
  ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
  if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    ### Persist the rules via csfpost.sh so csf -r cannot flush them; the
    ### appended lines use POSIX redirects only (csfpost.sh runs under sh).
    ### Gated on -x so the fresh-install csfpost.sh seeding block in
    ### BOA.sh.txt (gated on ! -x) is never preempted.
    if [ -x "/etc/csf/csfpost.sh" ] \
      && ! grep -q "BOA-SACK-MITIGATION" /etc/csf/csfpost.sh; then
      echo "### BOA-SACK-MITIGATION begin (CVE-2019-11477/78/79) do not edit" >> /etc/csf/csfpost.sh
      echo "sysctl net.ipv4.tcp_mtu_probing=0 >/dev/null 2>&1" >> /etc/csf/csfpost.sh
      echo "iptables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP >/dev/null 2>&1 || iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP" >> /etc/csf/csfpost.sh
      echo "ip6tables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP >/dev/null 2>&1 || ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP" >> /etc/csf/csfpost.sh
      echo "### BOA-SACK-MITIGATION end" >> /etc/csf/csfpost.sh
    fi
    _SACK_TEST=$(ip6tables --list | grep tcpmss)
    if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
      sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
      iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    fi
  fi

  echo local start $(date)
  _local_ip_rg

  _HA=/var/xdrago/monitor/log/hackcheck.archive.log
  _HX=/var/xdrago/monitor/log/hackcheck.archive.x3.log
  _WA=/var/xdrago/monitor/log/scan_nginx.archive.log
  _WX=/var/xdrago/monitor/log/scan_nginx.archive.x3.log
  _FA=/var/xdrago/monitor/log/hackftp.archive.log
  _FX=/var/xdrago/monitor/log/hackftp.archive.x3.log

  echo guard start $(date)
  _guard_stats
  rm -f /var/xdrago/monitor/log/ssh.log
  rm -f /var/xdrago/monitor/log/web.log
  rm -f /var/xdrago/monitor/log/ftp.log

  pkill -9 -f ConfigServer
  killall sleep &> /dev/null
  rm -f /etc/csf/csf.error
  service lfd restart
  _NOW=$(date +%y%m%d-%H%M%S)
  cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-dhcp-${_NOW}
  sed -i "s/.*DHCP.*//g" /etc/csf/csf.allow
  wait
  _NOW=$(date +%y%m%d-%H%M%S)
  cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-clear-${_NOW}
  sed -i "/^$/d" /etc/csf/csf.allow
  wait
  sed -i "/^$/d" /etc/csf/csf.ignore
  wait
  if [ -e "/var/log/daemon.log" ]; then
    _DHCP_LOG="/var/log/daemon.log"
  else
    _DHCP_LOG="/var/log/syslog"
  fi
  grep DHCPREQUEST "${_DHCP_LOG}" | awk '{print $12}' | sort -u | while read -r _IP; do
    if [[ ${_IP} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      IFS='.' read -r oct1 oct2 oct3 oct4 <<< "${_IP}"
      if (( oct1 <= 255 && oct2 <= 255 && oct3 <= 255 && oct4 <= 255 )); then
        echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow
      fi
    fi
  done
  if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
    csf -ra &> /dev/null
    synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
  else
    csf -r &> /dev/null
  fi
  ### Linux kernel TCP SACK CVEs mitigation
  ### CVE-2019-11477 SACK Panic
  ### CVE-2019-11478 SACK Slowness
  ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
  if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    ### Persist the rules via csfpost.sh so csf -r cannot flush them; the
    ### appended lines use POSIX redirects only (csfpost.sh runs under sh).
    ### Gated on -x so the fresh-install csfpost.sh seeding block in
    ### BOA.sh.txt (gated on ! -x) is never preempted.
    if [ -x "/etc/csf/csfpost.sh" ] \
      && ! grep -q "BOA-SACK-MITIGATION" /etc/csf/csfpost.sh; then
      echo "### BOA-SACK-MITIGATION begin (CVE-2019-11477/78/79) do not edit" >> /etc/csf/csfpost.sh
      echo "sysctl net.ipv4.tcp_mtu_probing=0 >/dev/null 2>&1" >> /etc/csf/csfpost.sh
      echo "iptables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP >/dev/null 2>&1 || iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP" >> /etc/csf/csfpost.sh
      echo "ip6tables -C INPUT -p tcp -m tcpmss --mss 1:500 -j DROP >/dev/null 2>&1 || ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP" >> /etc/csf/csfpost.sh
      echo "### BOA-SACK-MITIGATION end" >> /etc/csf/csfpost.sh
    fi
    _SACK_TEST=$(ip6tables --list | grep tcpmss)
    if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
      sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
      iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
    fi
  fi
  rm -f /run/water.pid
  echo guard fin $(date)
  ntpdate pool.ntp.org > /dev/null 2>&1 &
fi
exit 0
