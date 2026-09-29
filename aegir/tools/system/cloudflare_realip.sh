#!/bin/bash

# Generate the nginx realip trusted-source include from Cloudflare's published
# edge ranges, so `set_real_ip_from <range>` + `real_ip_header CF-Connecting-IP`
# resolve $remote_addr to the real client on CF-fronted vhosts (rate-limit keys,
# logs and deny then key on the visitor, not the CF edge).
#
# Idempotent: only rewrites the include and reloads nginx when the fetched
# ranges actually change.  Safe on non-CF boxes: declaring CF ranges as trusted
# is inert unless a request actually arrives from one of them, so realip never
# triggers for direct traffic.
#
# The realip directives and the wildcard `include .../nginx_cloudflare_real_ip.c*`
# live in the generated nginx server config (Provision server.tpl.php); this tool
# only maintains the ranges file that include consumes.

_out_dir="/data/conf"
_out_name="nginx_cloudflare_real_ip.conf"
_out_file="${_out_dir}/${_out_name}"
# Leading-dot backup (and put names) so the `.c*` include glob never picks
# them up (nginx glob skips dotfiles); the install renames inside the
# directory, so it is atomic.
_backup_name=".nginx_cloudflare_real_ip.last_good.conf"
# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy) never overlap their
# configtest+reload; wait up to 30s, then skip this run and retry next tick.
_lock_file="/run/boa_nginx_config.lock"
_min_ranges=8
# BOA-canonical fetch options (same _crlGet used across BOA): verified TLS, follow
# up to 3 redirects, --fail so an HTTP error yields no body (an error page is never
# parsed as ranges), retry transient failures, iCab UA.
_crlGet="-L --max-redirs 3 -s --fail --retry 9 --retry-delay 9 -A iCab"

# Cloudflare publishes its ranges at these no-auth endpoints (same source the
# csf.allow whitelist in *-water.sh uses); the JSON API carries both families.
_cf_v4_url="https://www.cloudflare.com/ips-v4"
_cf_v6_url="https://www.cloudflare.com/ips-v6"
_cf_json_url="https://api.cloudflare.com/client/v4/ips"

# Validators (the safety net — only value-valid CIDRs are ever written). Shape
# alone is not enough: an out-of-range octet or prefix (e.g. 999.1.1.1/33) from a
# Cloudflare format change or a corrupted/truncated response would pass a loose
# check, reach a set_real_ip_from line, and fail nginx configtest for the WHOLE
# box. Validate each octet 0-255, the IPv4 prefix 0-32 and the IPv6 prefix 0-128,
# and reject a degenerate v6 body (a bare ':' / '::' with no hex group).
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_is_ipv4_cidr() { [[ "$1" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}/(3[0-2]|[12]?[0-9])$ ]]; }
_is_ipv6_cidr() {
  local _addr="${1%/*}" _mask="${1#*/}"
  [[ "$1" == */* ]] || return 1
  [[ "${_mask}" =~ ^(12[0-8]|1[01][0-9]|[1-9]?[0-9])$ ]] || return 1
  [[ "${_addr}" =~ ^[0-9a-fA-F:]+$ && "${_addr}" == *:* && "${_addr}" =~ [0-9a-fA-F] ]]
}

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

_work="$(mktemp -d /run/.cloudflare_realip.XXXXXX 2> /dev/null)" \
  || { echo "Cannot create a work directory in /run; skipping this run."; exit 1; }
trap 'rm -rf -- "${_work}"' EXIT
_tmp_file="${_work}/new"

_fetch_cf_ranges() {
  local _v4 _v6 _json
  _v4=$(curl ${_crlGet} "${_cf_v4_url}" 2>/dev/null \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | sort -u)
  _v6=$(curl ${_crlGet} "${_cf_v6_url}" 2>/dev/null \
    | grep -oiE '[0-9a-f:]*:[0-9a-f:]*/[0-9]{1,3}' | sort -u)
  if [[ -z "${_v4}" ]]; then
    echo "cloudflare ips-v4 endpoint failed; falling back to JSON API" >&2
    _json=$(curl ${_crlGet} "${_cf_json_url}" 2>/dev/null)
    _v4=$(echo "${_json}" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' | sort -u)
    [[ -z "${_v6}" ]] && _v6=$(echo "${_json}" \
      | grep -oiE '[0-9a-f:]*:[0-9a-f:]*/[0-9]{1,3}' | sort -u)
  fi
  printf '%s\n%s\n' "${_v4}" "${_v6}"
}

_raw_ranges=$(_fetch_cf_ranges | grep -v '^$' | sort -u)

# Never wipe a known-good include on a failed/empty fetch.
if [[ -z "${_raw_ranges}" ]]; then
  echo "No Cloudflare ranges fetched; leaving existing include untouched."
  exit 1
fi

{
  echo "# Cloudflare trusted edge ranges for nginx realip."
  echo "# Generated by /var/xdrago/cloudflare_realip.sh -- DO NOT EDIT BY HAND."
  echo "# Source: ${_cf_v4_url} , ${_cf_v6_url} (JSON fallback ${_cf_json_url})."
  while IFS= read -r _cidr; do
    [[ -z "${_cidr}" ]] && continue
    if _is_ipv4_cidr "${_cidr}" || _is_ipv6_cidr "${_cidr}"; then
      echo "set_real_ip_from ${_cidr};"
    else
      echo "cloudflare_realip: skipped invalid range: ${_cidr}" >&2
    fi
  done <<< "${_raw_ranges}"
} > "${_tmp_file}"

# Guard against a partial fetch silently shrinking the trust list.
_count=$(grep -c '^set_real_ip_from ' "${_tmp_file}" 2>/dev/null)
if [[ "${_count}" -lt "${_min_ranges}" ]]; then
  echo "Only ${_count} ranges parsed (< ${_min_ranges}); refusing to apply."
  exit 1
fi

# Change-gate: identical to the live include -> nothing to do (no reload).
if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_out_name}" "${_work}/live" \
  && cmp -s "${_tmp_file}" "${_work}/live"; then
  echo "Cloudflare ranges unchanged (${_count} entries). Nothing to do."
  exit 0
fi

# Back up the current good include, then atomically install the new one.
[[ -f "${_work}/live" ]] \
  && _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/live" "${_backup_name}"
if ! _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_tmp_file}" "${_out_name}"; then
  echo "Could not install ${_out_file}; skipping this run."
  exit 1
fi

# Validate the whole nginx config; revert on failure.
_configtest=$(service nginx configtest 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Nginx configtest failed after updating Cloudflare ranges: ${_configtest}"
  if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
    echo "Reverting to the last known good Cloudflare ranges include."
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
  else
    echo "No backup to revert to; removing the new include."
    _acct_in_real_dir "${_out_dir}" rm -f -- "./${_out_name}"
  fi
  exit 1
fi

# Reload nginx; revert on failure.
if ! service nginx reload; then
  echo "Nginx reload failed; reverting Cloudflare ranges include."
  if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
    service nginx reload
  fi
  exit 1
fi

echo "Cloudflare realip ranges updated (${_count} entries) and Nginx reloaded."
exit 0
