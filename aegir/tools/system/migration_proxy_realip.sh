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
_out_name="nginx_cloudflare_real_ip.cmig"
_out_file="${_out_dir}/${_out_name}"
_ctrl_name=".migration_proxy_trust.cnf"
_ctrl_file="${_out_dir}/${_ctrl_name}"
# Leading-dot backup (and put names) so the `.c*` include glob never picks
# them up (nginx glob skips dotfiles); the install renames inside the
# directory, so it is atomic.
_backup_name=".nginx_cloudflare_real_ip.cmig.last_good"
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

# /data/conf is root's, but an Octopus upgrade of an earlier release handed it
# to the account it upgraded, so a name there can still be a link or a FIFO
# that account left. Files there are read and put only inside the real
# directory, through these; work files live in a root-only directory in /run.
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
# stdin as the fresh file $1, owned by uid $2 and gid $3 with the mode $4,
# through the one handle that created it O_EXCL|O_NOFOLLOW (helper.sh.inc).
_ACCT_PUT_PL='use Fcntl; my ($n, $u, $g, $m) = @ARGV; local $/; my $d = <STDIN>; sysopen(my $h, $n, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1; (print {$h} $d) or exit 1; chown($u, $g, $h) or exit 1; chmod(oct($m) & 0666, $h) or exit 1; close($h) or exit 1; exit 0'
# The file $1 (root's own, outside /data/conf) put as ./$2 in the current
# (pinned) directory, root's and 0644: written under a fresh name through one
# handle (_ACCT_PUT_PL), then renamed over the name, so a link or a FIFO at
# the name is replaced, never written through or opened; a directory there,
# which the rename cannot replace, is removed first.
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
# ./$1 in the current (pinned) directory copied into the file $2 (root's own,
# outside /data/conf) while ./$1 is a regular file of at most 32 MiB: read
# without following a link or blocking on a FIFO. Status 1 when it is not
# there, not one, or bigger (a file that size is none of these lists, and the
# copy lands in memory-backed /run).
_conf_get_file_here() {
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
  [ "$(stat -c %s -- "./${1}" 2> /dev/null || echo 0)" -le 33554432 ] || return 1
  dd if="./${1}" of="${2}" iflag=nofollow,nonblock status=none 2> /dev/null
}

_work="$(mktemp -d /run/.migration_proxy_realip.XXXXXX 2> /dev/null)" \
  || { echo "Cannot create a work directory in /run; skipping this run."; exit 1; }
trap 'rm -rf -- "${_work}"' EXIT
_tmp_file="${_work}/new"

# Apply the freshly built include (or its removal) with the same configtest/
# reload/revert discipline cloudflare_realip.sh uses.  Args: none (uses globals).
_install_or_remove() {
  local _new="$1"   # path to the staged include, or "" to remove _out_file
  if [[ -z "${_new}" ]]; then
    # Teardown: nothing trusted -> remove the include if present.
    if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_out_name}" "${_work}/live"; then
      _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/live" "${_backup_name}"
      _acct_in_real_dir "${_out_dir}" rm -f -- "./${_out_name}"
      if ! service nginx configtest >/dev/null 2>&1; then
        echo "configtest failed after removing migration-proxy realip include; reverting."
        _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/live" "${_out_name}"
        return 1
      fi
      service nginx reload && echo "Migration-proxy realip trust removed; Nginx reloaded."
    elif [[ -L "${_out_file}" || -e "${_out_file}" ]]; then
      # Not a regular file (a link, a FIFO or a directory left at the name):
      # never this tool's output, so it goes too.
      if _acct_in_real_dir "${_out_dir}" rm -rf -- "./${_out_name}" \
        && [[ ! -e "${_out_file}" && ! -L "${_out_file}" ]]; then
        service nginx reload && echo "Migration-proxy realip trust removed; Nginx reloaded."
      else
        echo "Could not remove ${_out_file}; left as found."
        return 1
      fi
    else
      echo "No migration-proxy realip trust present; nothing to do."
    fi
    return 0
  fi

  # Change-gate: identical to the live include -> nothing to do (no reload).
  # Return 2 ("no change") so the caller does not print a misleading "updated".
  if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_out_name}" "${_work}/live" \
    && cmp -s "${_new}" "${_work}/live"; then
    echo "Migration-proxy realip trust unchanged. Nothing to do."
    return 2
  fi

  [[ -f "${_work}/live" ]] \
    && _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/live" "${_backup_name}"
  if ! _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_new}" "${_out_name}"; then
    echo "Could not install ${_out_file}; skipping this run."
    return 1
  fi

  if ! service nginx configtest >/dev/null 2>&1; then
    echo "Nginx configtest failed after updating migration-proxy realip trust."
    if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
      echo "Reverting to the last known good include."
      _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
    else
      echo "No backup to revert to; removing the new include."
      _acct_in_real_dir "${_out_dir}" rm -f -- "./${_out_name}"
    fi
    return 1
  fi

  if ! service nginx reload; then
    echo "Nginx reload failed; reverting migration-proxy realip trust."
    if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
      _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
      service nginx reload
    fi
    return 1
  fi
  return 0
}

# No control file -> teardown. It is read only as a regular file, into the
# work directory: a link or a FIFO at its name reads as no control file.
if ! _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_ctrl_name}" "${_work}/ctrl"; then
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
done < "${_work}/ctrl"

# Empty/all-invalid control file -> treat as teardown (never leave stale trust).
if [[ "${_count}" -eq 0 ]]; then
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
