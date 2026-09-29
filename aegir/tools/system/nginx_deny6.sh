#!/bin/bash

# nginx_deny6.sh — the IPv6 counterpart of nginx_deny.sh.  csf is IPv4-only, so an
# IPv6 web offender detected by scan_nginx cannot be banned at the firewall;
# scan_nginx instead appends it (with an expiry) to an nginx-native store, and this
# tool prunes the expired entries and emits the still-active ones as `<ip6> 1;`
# into /data/conf/nginx_banned_ips.conf6 — picked up by the SAME
# `geo $remote_addr $is_banned` set (its `nginx_banned_ips.conf[6]` include, or
# the older `.c*` glob, names this file) that nginx_deny.sh feeds for IPv4,
# and dropped with a 444 by the guard in the vhost template.  Idempotent: only
# rewrites + reloads when the set changes.
#
# IPv6 can only reach $remote_addr via the trusted realip proxy (BOA disables IPv6
# server-side and pins realip to the Cloudflare ranges), so a banned v6 is always
# the real client, never a spoofable direct peer.
#
# Store (written by scan_nginx.sh, pruned here): lines `<ip6>|<expiry-epoch>`.
# A re-offence appends a fresh expiry; the max per IP wins; expired IPs drop out
# on the next run (the self-expiry that csf provides for the IPv4 side).

_store="/var/xdrago/monitor/log/web6.tempban"
_out_dir="/data/conf"
_out_name="nginx_banned_ips.conf6"
_out_file="${_out_dir}/${_out_name}"
# Leading-dot backup (and put names) so no include ever picks them up (a
# server config rendered before the exact-name patterns still carries the
# `nginx_banned_ips.c*` glob); the install renames inside the directory, so
# it is atomic.
_backup_name=".nginx_banned_ips6.last_good.conf"
_store_tmp="${_store}.tmp.$$"
# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / nginx_deny6 / ai_policy / user_admin_access)
# never overlap their configtest+reload; wait up to 30s, then skip and retry.
_lock_file="/run/boa_nginx_config.lock"

# Strict IPv6 (address-only) validator — a subset of what nginx accepts, so a
# malformed token in the store can never fail the box-wide configtest.
_hex="[0-9A-Fa-f]{1,4}"
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_ipv4="(${_ipv4_octet}\.){3}${_ipv4_octet}"
_ipv6_regex="^((${_hex}:){7}${_hex}|(${_hex}:){1,7}:|(${_hex}:){1,6}:${_hex}|(${_hex}:){1,5}(:${_hex}){1,2}|(${_hex}:){1,4}(:${_hex}){1,3}|(${_hex}:){1,3}(:${_hex}){1,4}|(${_hex}:){1,2}(:${_hex}){1,5}|${_hex}:((:${_hex}){1,6})|:((:${_hex}){1,7}|:)|::(ffff(:0{1,4})?:)?(${_ipv4})|(${_hex}:){1,4}:(${_ipv4}))$"
_is_v6() { [[ "$1" == *:* && "$1" =~ ${_ipv6_regex} ]]; }

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx not installed; nothing to do."
  exit 0
fi

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

_work="$(mktemp -d /run/.nginx_deny6.XXXXXX 2> /dev/null)" \
  || { echo "Cannot create a work directory in /run; skipping this run."; exit 1; }
trap 'rm -rf -- "${_work}"' EXIT
_tmp_file="${_work}/new"

_now=$(date +%s)

# Read the store into ip -> max future expiry (drops expired + collapses the
# duplicate/refreshed lines scan_nginx appends).
declare -A _EXP
if [[ -f "${_store}" ]]; then
  while IFS='|' read -r _ip _exp; do
    _is_v6 "${_ip}" || continue
    [[ "${_exp}" =~ ^[0-9]+$ ]] || continue
    (( _exp > _now )) || continue
    if [[ -z "${_EXP[${_ip}]:-}" ]] || (( _exp > _EXP[${_ip}] )); then
      _EXP[${_ip}]="${_exp}"
    fi
  done < "${_store}"

  # Rewrite the pruned store (surviving entries only) atomically. This is the
  # actual ban self-expiry. A concurrent scan_nginx append that lands between the
  # read above and this mv is lost, but the offender is re-detected on the next
  # ~5s scan, so it self-heals.
  {
    for _ip in "${!_EXP[@]}"; do echo "${_ip}|${_EXP[${_ip}]}"; done
  } > "${_store_tmp}"
  mv -f "${_store_tmp}" "${_store}"
fi

# Nothing banned and no stale output to clear -> done (leave the include glob to
# match zero files rather than write an empty one).
if (( ${#_EXP[@]} == 0 )) && [[ ! -e "${_out_file}" && ! -L "${_out_file}" ]]; then
  exit 0
fi

# Build the geo fragment; entries sorted so an unchanged ban set yields a
# byte-identical file (stable change-gate, no needless reload).
{
  echo "# nginx realip-keyed IPv6 web deny set — generated by /var/xdrago/nginx_deny6.sh."
  echo "# DO NOT EDIT BY HAND.  Mirrors scan_nginx's nginx-native IPv6 ban store"
  echo "# (${_store}).  Consumed by the same geo \$is_banned map as the IPv4 set."
  for _ip in "${!_EXP[@]}"; do echo "${_ip} 1;"; done | sort
} > "${_tmp_file}"

# Change-gate: identical to the live file -> nothing to do (no reload).
if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_out_name}" "${_work}/live" \
  && cmp -s "${_tmp_file}" "${_work}/live"; then
  exit 0
fi

# Back up current, install new atomically, validate, reload, revert on failure.
[[ -f "${_work}/live" ]] \
  && _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/live" "${_backup_name}"
if ! _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_tmp_file}" "${_out_name}"; then
  echo "Could not install ${_out_file}; skipping this run."
  exit 1
fi

_configtest=$(service nginx configtest 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Nginx configtest failed after IPv6 deny-set update: ${_configtest}"
  if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
    echo "Reverting to the last known good IPv6 deny set."
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
  else
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here /dev/null "${_out_name}"
  fi
  exit 1
fi

if ! service nginx reload; then
  echo "Nginx reload failed; reverting IPv6 deny set."
  if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
    service nginx reload
  fi
  exit 1
fi

_count=$(grep -c ' 1;$' "${_tmp_file}" 2>/dev/null)
echo "nginx IPv6 web deny set updated (${_count} entr$([[ "${_count}" == "1" ]] && echo y || echo ies)); Nginx reloaded."
exit 0
