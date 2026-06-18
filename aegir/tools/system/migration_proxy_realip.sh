#!/bin/bash

# Maintain the nginx realip trust for a *migration proxy* on the NEW host.
#
# During an xmass/xoct migration the OLD host becomes an HTTP+HTTPS reverse
# proxy forwarding every site to this (NEW) host, so the NEW host sees the
# proxy as the TCP peer for all migrated traffic.  The proxy forwards the real
# client in CF-Connecting-IP (see the proxy.conf/ssl_proxy.conf/pln_proxy.conf/
# https_proxy_le.conf templates: `proxy_set_header CF-Connecting-IP
# $remote_addr`).  For the NEW host's unchanged `real_ip_header CF-Connecting-IP`
# to honour that header it must trust the proxy as a realip source -- i.e. emit
# `set_real_ip_from <proxy-ip>`.  This tool writes exactly those lines.
#
# It deliberately rides the SAME wildcard include the Cloudflare ranges use --
# `include /data/conf/nginx_cloudflare_real_ip.c*` in Provision server.tpl.php --
# by writing a sibling `.cmig` member, so no template/fleet re-render is needed.
# The Cloudflare member (`.conf`) is owned by cloudflare_realip.sh and is never
# touched here; this tool owns only the `.cmig` member.
#
# Input is the control file /data/conf/.migration_proxy_trust.cnf (one IPv4/CIDR
# or IPv6/CIDR per line, '#' comments allowed).  An absent/empty control file is
# the teardown signal: the `.cmig` include is removed and nginx reloaded.
#
# Idempotent: only rewrites the include and reloads nginx when the resolved set
# actually changes.  Safe everywhere: trusting an address is inert unless a
# request actually arrives from it.  Mirrors cloudflare_realip.sh in structure,
# locking and configtest/reload discipline.

_out_dir="/data/conf"
_out_file="${_out_dir}/nginx_cloudflare_real_ip.cmig"
_ctrl_file="${_out_dir}/.migration_proxy_trust.cnf"
# Leading-dot tmp/backup names so the `.c*` include glob never picks them up
# (nginx glob skips dotfiles); tmp stays in-dir so the install mv is atomic.
_tmp_file="${_out_dir}/.nginx_cloudflare_real_ip.cmig.tmp.$$"
_backup_file="${_out_dir}/.nginx_cloudflare_real_ip.cmig.last_good"
# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy / migration_proxy_realip) never
# overlap their configtest+reload; wait up to 30s, then skip and retry next tick.
_lock_file="/run/boa_nginx_config.lock"

# Strict IPv4 / IPv4-CIDR and IPv6-CIDR validation -- only value-valid addresses
# may reach a set_real_ip_from line, or a single malformed token would fail the
# nginx configtest for the WHOLE box. Each IPv4 octet 0-255, prefix 0-32; IPv6
# prefix 0-128 with a non-degenerate hex body.
# Reject the all-zeros host and any /0 prefix: set_real_ip_from 0.0.0.0/0 would
# trust the spoofable CF-Connecting-IP from EVERY peer, collapsing the whole
# realip trust boundary. (nginx ignores host bits, so 1.2.3.4/0 == 0.0.0.0/0.)
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_is_ipv4() { [[ "$1" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}$ ]] && [[ "$1" != 0.0.0.0 ]]; }
_is_ipv4_cidr() { [[ "$1" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}/(3[0-2]|[12]?[0-9])$ ]] && [[ "$1" != */0 ]] && [[ "$1" != 0.0.0.0/* ]]; }
_is_ipv6_cidr() {
  local _addr="${1%/*}" _mask="${1#*/}"
  [[ "$1" == */* ]] || return 1
  [[ "${_mask}" =~ ^(12[0-8]|1[01][0-9]|[1-9]?[0-9])$ ]] || return 1
  [[ "${_addr}" =~ ^[0-9a-fA-F:]+$ && "${_addr}" == *:* && "${_addr}" =~ [0-9a-fA-F] ]]
}
_is_ipv6_plain() { [[ "$1" =~ ^[0-9a-fA-F:]+$ && "$1" == *:* && "$1" =~ [0-9a-fA-F] ]]; }

# Global nginx config tool: only meaningful where nginx is installed.
if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx not installed; nothing to do."
  exit 0
fi

# Re-entrancy guard: skip this tick if a previous run is still active.
exec 9>"${_lock_file}" 2>/dev/null
if ! flock -w 30 9; then
  echo "Could not acquire the shared nginx-config lock; skipping this run."
  exit 0
fi

mkdir -p "${_out_dir}"

# Apply the freshly built include (or its removal) with the same configtest/
# reload/revert discipline cloudflare_realip.sh uses.  Args: none (uses globals).
_install_or_remove() {
  local _new="$1"   # path to the staged include, or "" to remove _out_file
  if [[ -z "${_new}" ]]; then
    # Teardown: nothing trusted -> remove the include if present.
    if [[ -f "${_out_file}" ]]; then
      cp -a "${_out_file}" "${_backup_file}"
      rm -f "${_out_file}"
      if ! service nginx configtest >/dev/null 2>&1; then
        echo "configtest failed after removing migration-proxy realip include; reverting."
        cp -a "${_backup_file}" "${_out_file}"
        return 1
      fi
      service nginx reload && echo "Migration-proxy realip trust removed; Nginx reloaded."
    else
      echo "No migration-proxy realip trust present; nothing to do."
    fi
    return 0
  fi

  # Change-gate: identical to the live include -> nothing to do (no reload).
  # Return 2 ("no change") so the caller does not print a misleading "updated".
  if [[ -f "${_out_file}" ]] && cmp -s "${_new}" "${_out_file}"; then
    echo "Migration-proxy realip trust unchanged. Nothing to do."
    rm -f "${_new}"
    return 2
  fi

  [[ -f "${_out_file}" ]] && cp -a "${_out_file}" "${_backup_file}"
  mv -f "${_new}" "${_out_file}"

  if ! service nginx configtest >/dev/null 2>&1; then
    echo "Nginx configtest failed after updating migration-proxy realip trust."
    if [[ -f "${_backup_file}" ]]; then
      echo "Reverting to the last known good include."
      cp -a "${_backup_file}" "${_out_file}"
    else
      echo "No backup to revert to; removing the new include."
      rm -f "${_out_file}"
    fi
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed; reverting migration-proxy realip trust."
    if [[ -f "${_backup_file}" ]]; then
      cp -a "${_backup_file}" "${_out_file}"
      service nginx reload
    fi
    return 1
  fi
  return 0
}

# No control file -> teardown.
if [[ ! -f "${_ctrl_file}" ]]; then
  _install_or_remove ""
  exit $?
fi

# Build the staged include from valid control-file entries.
_count=0
{
  echo "# Migration-proxy trusted realip sources for nginx (set_real_ip_from)."
  echo "# Generated by /var/xdrago/migration_proxy_realip.sh -- DO NOT EDIT BY HAND."
  echo "# Source: ${_ctrl_file} (written by the xmass/xoct migration tooling)."
} > "${_tmp_file}"
while IFS= read -r _line || [[ -n "${_line}" ]]; do
  _line="${_line%%#*}"                 # strip comments
  _line="${_line//[[:space:]]/}"       # strip all whitespace
  [[ -z "${_line}" ]] && continue
  if _is_ipv4 "${_line}" || _is_ipv4_cidr "${_line}" \
    || _is_ipv6_cidr "${_line}" || _is_ipv6_plain "${_line}"; then
    echo "set_real_ip_from ${_line};" >> "${_tmp_file}"
    _count=$((_count + 1))
  else
    echo "migration_proxy_realip: skipped invalid entry: ${_line}" >&2
  fi
done < "${_ctrl_file}"

# Empty/all-invalid control file -> treat as teardown (never leave stale trust).
if [[ "${_count}" -eq 0 ]]; then
  rm -f "${_tmp_file}"
  _install_or_remove ""
  exit $?
fi

_install_or_remove "${_tmp_file}"
_rc=$?
if [[ "${_rc}" -eq 0 ]]; then
  echo "Migration-proxy realip trust updated (${_count} source(s))."
elif [[ "${_rc}" -eq 2 ]]; then
  _rc=0   # no change needed is success
fi
exit "${_rc}"
