#!/bin/bash

# Orchestrate migration-proxy trust on THIS host -- the glue xmass/xoct used to
# leave out, wiring the L7 realip recovery and the L4 csf whitelist together.
#
#   migration_proxy_trust.sh trust <ip|cidr> [<ip|cidr>...] [--permanent] [--csf-only]
#   migration_proxy_trust.sh teardown [--force]
#   migration_proxy_trust.sh reconcile [--force]
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
# reconcile: recompute the trust set from the per-account migration proxy policy
#   records (/data/disk/<oN>/log/migproxy.cnf, written by xoct/xmass). Records
#   this host owns (its own _MIG_HOST_IP) with _MIG_ROLE=target decide which
#   peers stay trusted: any permanent or ha-switch peer keeps trust and the
#   permanent marker (ha-switch behaves exactly as permanent for trust and
#   teardown; it differs only in the client notification); all-temporary,
#   all-retired or no live peers tears everything down INCLUDING the marker,
#   because the union proves nothing needs it. An account stamped proxied with
#   no valid record is never guessed at: its trust and the marker are left as
#   found and reported. With no records at all this behaves exactly as
#   teardown always has (marker honoured; --force overrides), so an
#   unconverted fleet sees bit-identical post-mig behaviour.
#
# Idempotent and safe to re-run. Mirrors the csf.allow/csf.ignore line format and
# the cleanup-by-"migration proxy"-tag used by _whitelist_ip_migration_proxy in
# guest-water.sh.

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

# --- per-account policy records (mirrors xoct's _mig_* primitives) -----------

_mig_get() {
  local _f="$1" _k="$2"
  [ -r "${_f}" ] || return 1
  grep -m1 "^${_k}=" "${_f}" 2>/dev/null | cut -d= -f2- | tr -d '\r\n'
}

_mig_valid_mode() {
  case "$1" in
    temporary|permanent|ha-switch|retired) return 0 ;;
    *) return 1 ;;
  esac
}

_my_ipv4s() {
  hostname -I 2>/dev/null | tr ' ' '\n' \
    | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

_cmd_reconcile() {
  local _force="${1:-}"
  local _keep="" _perm=NO _undeclared="" _records=0
  local _cnf _root _acct _mode _peer _hip _role _pid _myips _ip _kept=""

  _myips="$(_my_ipv4s)"
  if [ -z "${_myips}" ]; then
    # Cannot verify which records are OURS (a record that arrived by the log/
    # rsync must never be a decision input). Refusing to act beats silently
    # degrading into a teardown under a live proxy.
    _msg "reconcile: cannot determine this host's IPv4 addresses; leaving trust as found"
    return 0
  fi

  for _cnf in /data/disk/*/log/migproxy.cnf; do
    [ -e "${_cnf}" ] || continue
    _hip="$(_mig_get "${_cnf}" _MIG_HOST_IP)"
    # A record whose host IP is not ours arrived from the peer by rsync:
    # provenance for reporting, never a decision input here.
    echo "${_myips}" | grep -qxF "${_hip}" || continue
    _role="$(_mig_get "${_cnf}" _MIG_ROLE)"
    # Source-authored records describe OUTBOUND proxying; only target-role
    # records say who this host must keep trusting.
    [ "${_role}" = "target" ] || continue
    _records=$(( _records + 1 ))
    _acct="$(basename "$(dirname "$(dirname "${_cnf}")")")"
    _mode="$(_mig_get "${_cnf}" _MIG_MODE)"
    _peer="$(_mig_get "${_cnf}" _MIG_PEER_IP)"
    if ! _mig_valid_mode "${_mode}" || ! _is_ipv4_or_cidr "${_peer}"; then
      # A record failing validation is never partially honoured; treat the
      # account as undeclared and keep its peer where one parses.
      _undeclared="${_undeclared} ${_acct}"
      _is_ipv4_or_cidr "${_peer}" && _keep="${_keep} ${_peer}"
      continue
    fi
    case "${_mode}" in
      permanent|ha-switch)
        # ha-switch behaves exactly as permanent for trust and teardown; it
        # differs only in the client notification.
        _keep="${_keep} ${_peer}"
        _perm=YES
      ;;
      temporary|retired)
        # reconcile runs post-mig (DNS moved) or after a policy change:
        # temporary trust ends here, retired never needed it.
        :
      ;;
    esac
  done

  # Accounts stamped proxied with no valid record of their own: never guess.
  # Keep whatever trust exists, leave the permanent marker as found, report.
  for _pid in /data/disk/*/log/proxied.pid; do
    [ -e "${_pid}" ] || continue
    _root="$(dirname "$(dirname "${_pid}")")"
    _acct="$(basename "${_root}")"
    case " ${_undeclared} " in *" ${_acct} "*) continue ;; esac
    _cnf="${_root}/log/migproxy.cnf"
    _hip="$(_mig_get "${_cnf}" _MIG_HOST_IP)"
    _mode="$(_mig_get "${_cnf}" _MIG_MODE)"
    if [ -n "${_hip}" ] && echo "${_myips}" | grep -qxF "${_hip}" \
      && _mig_valid_mode "${_mode}"; then
      continue   # declared (either role); its policy already spoke above
    fi
    _undeclared="${_undeclared} ${_acct}"
  done

  if [ "${_records}" -eq 0 ] && [ -z "${_undeclared}" ]; then
    if [ ! -e "${_realip_ctrl}" ] && [ ! -e "${_csf_ctrl}" ] && [ ! -e "${_perm_flag}" ]; then
      _msg "reconcile: no migration-proxy records and no trust wired; nothing to do"
      return 0
    fi
    # Pre-records fleet: behave exactly as teardown always has (the permanent
    # marker is honoured; --force overrides). Unquoted on purpose: an empty
    # _force must vanish, not arrive as an empty first argument.
    # shellcheck disable=SC2086
    _cmd_teardown ${_force}
    return $?
  fi

  # Unquoted on purpose: _keep is a space-separated set being split into lines.
  # shellcheck disable=SC2086
  _keep="$(printf '%s\n' ${_keep} | sort -u | tr '\n' ' ')"

  if [ -n "${_undeclared}" ]; then
    # Undeclared accounts have peers this host cannot know, so existing trust
    # is only ever ADDED to here, never stripped, and the permanent marker is
    # left as found (set only if a declared record demands it).
    for _ip in ${_keep}; do
      _uniq_append "${_csf_ctrl}" "${_ip}"
      _uniq_append "${_realip_ctrl}" "${_ip}"
      _csf_add_ip "${_ip}"
      _kept="${_kept} ${_ip}"
    done
    [ "${_CSF_CHANGED}" = "YES" ] && _csf_reload
    [ -n "${_kept}" ] && [ -x "${_realip_tool}" ] && "${_realip_tool}"
    if [ "${_perm}" = "YES" ]; then
      mkdir -p "$(dirname "${_perm_flag}")"
      : > "${_perm_flag}"
    fi
    _msg "reconcile: UNDECLARED proxied accounts:${_undeclared}"
    _msg "  their trust and the permanent marker are left as found; declare policy on the"
    _msg "  proxying source (xoct proxy-mode <oN> <mode>, then xoct proxy ... --repair) so"
    _msg "  the record propagates here"
    [ -n "${_kept}" ] && _msg "reconcile: declared peers (re)trusted:${_kept}"
    return 0
  fi

  if [ -z "${_keep// /}" ]; then
    # Records exist and none needs trust: the union proves nothing needs the
    # marker either, so clear it even though plain teardown would honour it.
    rm -f "${_realip_ctrl}" "${_csf_ctrl}" "${_perm_flag}"
    _csf_strip
    _csf_reload
    [ -x "${_realip_tool}" ] && "${_realip_tool}"
    _msg "reconcile: no live permanent/ha-switch peers; migration proxy trust torn down"
    return 0
  fi

  # Rewrite both control files to exactly the keep set; strip every tagged csf
  # entry and re-add the keep set (no selective strip exists -- strip-all then
  # re-add exploits the existing idempotency).
  rm -f "${_realip_ctrl}" "${_csf_ctrl}"
  _csf_strip
  for _ip in ${_keep}; do
    _uniq_append "${_csf_ctrl}" "${_ip}"
    _uniq_append "${_realip_ctrl}" "${_ip}"
    _csf_add_ip "${_ip}"
    _kept="${_kept} ${_ip}"
  done
  _csf_reload
  [ -x "${_realip_tool}" ] && "${_realip_tool}"
  if [ "${_perm}" = "YES" ]; then
    mkdir -p "$(dirname "${_perm_flag}")"
    : > "${_perm_flag}"
  else
    rm -f "${_perm_flag}"
  fi
  _msg "reconcile: trusted migration peers now:${_kept}"
}

case "${1:-}" in
  trust)     shift; _cmd_trust "$@" ;;
  teardown)  shift; _cmd_teardown "$@" ;;
  reconcile) shift; _cmd_reconcile "$@" ;;
  *)
    echo "Usage: $0 trust <ip|cidr>... [--permanent] [--csf-only]"
    echo "       $0 teardown [--force]"
    echo "       $0 reconcile [--force]"
    exit 1
  ;;
esac
