#!/bin/bash

# Orchestrate migration-proxy trust on THIS host -- the glue xmass/xoct used to
# leave out, wiring the L7 realip recovery and the L4 csf whitelist together.
#
#   migration_proxy_trust.sh trust <ip|cidr> [<ip|cidr>...] [--permanent] [--csf-only]
#   migration_proxy_trust.sh teardown [--force]
#
# trust: register the given peer IP(s) as trusted migration sources on this host.
#   L4 (always): add to csf.allow on ports 80 AND 443 and to csf.ignore -- applied
#     immediately (csf -r) AND persisted to /root/.migration.proxy.ips.cnf so
#     *-water.sh re-asserts them on every tick (the immediate apply closes the
#     cutover window; water keeps them across reloads).
#   L7 (unless --csf-only): persist to /data/conf/.migration_proxy_trust.cnf and
#     run migration_proxy_realip.sh so nginx realip recovers the real client
#     through the proxy hop. Use --csf-only on the OLD/proxy host: it only needs
#     to never ban the new host; it has no realip recovery of its own to do.
#   --permanent: drop /data/conf/.migration_proxy_permanent.pid so a later
#     teardown is a deliberate no-op (proxy stays in service indefinitely).
#
# teardown: remove ALL migration-proxy trust on this host (both control files,
#   the .cmig realip include, the csf entries) unless the permanent marker is set
#   (--force overrides). csf entries that the immediate strip misses are also
#   cleaned by the next *-water.sh tick (control file gone -> nothing re-added).
#
# Idempotent and safe to re-run. Mirrors the csf.allow/csf.ignore line format and
# the cleanup-by-"migration proxy"-tag used by _whitelist_ip_migration_proxy in
# host-water.sh / guest-water.sh.

export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_realip_ctrl="/data/conf/.migration_proxy_trust.cnf"
_csf_ctrl="/root/.migration.proxy.ips.cnf"
_perm_flag="/data/conf/.migration_proxy_permanent.pid"
_realip_tool="/var/xdrago/migration_proxy_realip.sh"
_csf_allow="/etc/csf/csf.allow"
_csf_ignore="/etc/csf/csf.ignore"

_msg() { echo "$@"; }
_die() { echo "migration_proxy_trust: ERROR: $*" >&2; exit 1; }

# Reject the all-zeros host and any /0 prefix: trusting 0.0.0.0/0 as a realip
# source (set_real_ip_from) would honour the spoofable CF-Connecting-IP from
# every peer, and whitelisting it in csf would allow the whole internet.
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_is_ipv4_or_cidr() { [[ "$1" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}(/(3[0-2]|[12]?[0-9]))?$ ]] && [[ "$1" != */0 ]] && [[ "$1" != 0.0.0.0 ]] && [[ "$1" != 0.0.0.0/* ]]; }
_is_ipv6_ish() { [[ "$1" =~ ^[0-9a-fA-F:]+:[0-9a-fA-F:]*(/(12[0-8]|1[01][0-9]|[1-9]?[0-9]))?$ ]]; }
_is_ip() { _is_ipv4_or_cidr "$1" || _is_ipv6_ish "$1"; }

_csf_present() { [ -x "/usr/sbin/csf" ] && [ -e "${_csf_allow}" ]; }

_csf_reload() {
  _csf_present || return 0
  if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
    csf -ra &>/dev/null
    command -v synproxy_reassert >/dev/null 2>&1 \
      && synproxy_reassert -p "443 80" --no-quic -q &>/dev/null
  else
    csf -r &>/dev/null
  fi
}

# Set to YES by _csf_add_ip whenever it appends a line, so the caller only pays
# for a csf reload when something actually changed (cheap to call repeatedly).
_CSF_CHANGED="NO"

# Immediate csf whitelist of one peer. IPv4/CIDR only -- this matches
# _whitelist_ip_migration_proxy (which filters via _emit_valid_ips); adding an
# IPv6 line here would be stripped and not re-added by water, so it would flap.
_csf_add_ip() {
  local _ip="$1" _port _line
  _csf_present || return 0
  _is_ipv4_or_cidr "${_ip}" || { _msg "  (csf: skipping non-IPv4 ${_ip})"; return 0; }
  for _port in 80 443; do
    _line="tcp|in|d=${_port}|s=${_ip} # migration proxy"
    if ! grep -qF "${_line}" "${_csf_allow}" 2>/dev/null; then
      echo "${_line}" >> "${_csf_allow}"
      _CSF_CHANGED="YES"
    fi
  done
  if ! grep -qF "${_ip} # migration proxy" "${_csf_ignore}" 2>/dev/null; then
    echo "${_ip} # migration proxy" >> "${_csf_ignore}"
    _CSF_CHANGED="YES"
  fi
}

_csf_strip() {
  _csf_present || return 0
  sed -i "s/.*migration proxy.*//g" "${_csf_allow}"
  sed -i "s/.*migration proxy.*//g" "${_csf_ignore}"
  sed -i "/^$/d" "${_csf_allow}"
  sed -i "/^$/d" "${_csf_ignore}"
}

_uniq_append() {
  local _f="$1" _v="$2"
  [ -f "${_f}" ] || { mkdir -p "$(dirname "${_f}")"; : > "${_f}"; }
  grep -qxF "${_v}" "${_f}" 2>/dev/null || echo "${_v}" >> "${_f}"
}

_cmd_trust() {
  local _csf_only="NO" _permanent="NO" _a
  local -a _ips=()
  for _a in "$@"; do
    case "${_a}" in
      --csf-only)  _csf_only="YES" ;;
      --permanent) _permanent="YES" ;;
      --*)         _die "unknown option ${_a}" ;;
      *)           _is_ip "${_a}" || _die "not an IP/CIDR: ${_a}"; _ips+=("${_a}") ;;
    esac
  done
  [ "${#_ips[@]}" -gt 0 ] || _die "trust: no IP/CIDR given"

  local _ip
  for _ip in "${_ips[@]}"; do
    _uniq_append "${_csf_ctrl}" "${_ip}"
    _csf_add_ip "${_ip}"
    if [ "${_csf_only}" != "YES" ]; then
      _uniq_append "${_realip_ctrl}" "${_ip}"
    fi
    _msg "trusted migration peer ${_ip}"
  done

  [ "${_CSF_CHANGED}" = "YES" ] && _csf_reload

  if [ "${_csf_only}" != "YES" ]; then
    if [ -x "${_realip_tool}" ]; then
      "${_realip_tool}"
    else
      _msg "WARN: ${_realip_tool} not found; realip .cmig not applied"
    fi
  fi

  if [ "${_permanent}" = "YES" ]; then
    mkdir -p "$(dirname "${_perm_flag}")"
    : > "${_perm_flag}"
    _msg "marked migration proxy trust PERMANENT (${_perm_flag})"
  fi
}

_cmd_teardown() {
  local _force="NO"
  [ "${1:-}" = "--force" ] && _force="YES"
  if [ -e "${_perm_flag}" ] && [ "${_force}" != "YES" ]; then
    _msg "permanent migration proxy marker present; teardown skipped (use --force)"
    return 0
  fi
  rm -f "${_realip_ctrl}" "${_csf_ctrl}" "${_perm_flag}"
  _csf_strip
  _csf_reload
  # Control file now gone -> the tool removes the .cmig include.
  [ -x "${_realip_tool}" ] && "${_realip_tool}"
  _msg "migration proxy trust torn down on this host"
}

case "${1:-}" in
  trust)    shift; _cmd_trust "$@" ;;
  teardown) shift; _cmd_teardown "$@" ;;
  *)
    echo "Usage: $0 trust <ip|cidr>... [--permanent] [--csf-only]"
    echo "       $0 teardown [--force]"
    exit 1
  ;;
esac
