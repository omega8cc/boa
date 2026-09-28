#!/bin/bash

# nginx_deny.sh — mirror BOA's WEB abuse bans into an nginx realip-keyed geo
# deny set, so a banned real-client IP is dropped at nginx (444) even when it
# arrives via Cloudflare — where an origin csf/iptables ban (which only sees the
# CF edge) does not bite.  Idempotent: only rewrites + reloads when the set
# changes.  The nginx side (the geo map + the `if ($is_banned) return 444;`
# guard + the wildcard include of the file written here) lives in the Provision
# templates; this tool only maintains /data/conf/nginx_banned_ips.conf.
#
# Sources (web bans only — ssh/ftp bans work at the csf network layer since they
# are not Cloudflare-proxied):
#   /var/lib/csf/csf.tempban  rows `epoch|ip|port|dir|ttl|comment` with port
#                             80 or 443  (the active 15-min web temp bans from
#                             guest-fire.sh)
#   /etc/csf/csf.deny         lines whose comment is "Brute force Web Server"
#                             (guest-water.sh's persistent web-offender
#                             escalations; this deliberately excludes the
#                             "SSH Server" / "FTP Server" entries and the broad
#                             "SSH/Web Server attacks" blocklist CIDRs)
# The set self-expires: csf drops expired tempban rows and the next run drops
# them from the geo file.

_tempban="/var/lib/csf/csf.tempban"
_csf_deny="/etc/csf/csf.deny"
_web_deny_match="Brute force Web Server"
_out_dir="/data/conf"
_out_name="nginx_banned_ips.conf"
_out_file="${_out_dir}/${_out_name}"
# Leading-dot backup (and put names) so the `.c*` include glob never picks
# them up; the install renames inside the directory, so it is atomic.
_backup_name=".nginx_banned_ips.last_good.conf"
# Shared advisory lock so all BOA nginx-config writers (ip_access /
# cloudflare_realip / nginx_deny / ai_policy) never overlap their
# configtest+reload; wait up to 30s, then skip this run and retry next tick.
_lock_file="/run/boa_nginx_config.lock"

# Accept a bare IPv4 or an IPv4 CIDR (geo handles both); reject anything else
# (IPv6, hostnames, junk) — scan_nginx/csf web bans here are IPv4. Validate each
# octet 0-255 and the prefix 0-32: a loose [0-9]{1,3}/[0-9]{1,2} would let a
# malformed token (e.g. 999.1.1.1 or /99) reach the geo map and fail nginx
# configtest for the whole box.
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_is_ipv4_or_cidr() { [[ "$1" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}(/(3[0-2]|[12]?[0-9]))?$ ]]; }

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
# outside /data/conf) while ./$1 is a regular file: read without following a
# link or blocking on a FIFO. Status 1 when it is not there or not one.
_conf_get_file_here() {
  [ -f "./${1}" ] && [ ! -L "./${1}" ] || return 1
  dd if="./${1}" of="${2}" iflag=nofollow,nonblock status=none 2> /dev/null
}

_work="$(mktemp -d /run/.nginx_deny.XXXXXX 2> /dev/null)" \
  || { echo "Cannot create a work directory in /run; skipping this run."; exit 1; }
trap 'rm -rf -- "${_work}"' EXIT
_tmp_file="${_work}/new"

_collect() {
  # Active WEB temp bans: csf.tempban rows whose port (field 3) is 80 or 443.
  if [[ -f "${_tempban}" ]]; then
    awk -F'|' '($3 == "80" || $3 == "443") { print $2 }' "${_tempban}" 2>/dev/null
  fi
  # Persistent WEB offenders: csf.deny lines tagged by water as Web Server.
  if [[ -f "${_csf_deny}" ]]; then
    grep -F "${_web_deny_match}" "${_csf_deny}" 2>/dev/null | awk '{ print $1 }'
  fi
}

_ips=$(_collect | sort -u)

{
  echo "# nginx realip-keyed web deny set — generated by /var/xdrago/nginx_deny.sh."
  echo "# DO NOT EDIT BY HAND.  Mirrors csf web temp bans (80/443) + csf.deny"
  echo "# 'Brute force Web Server' escalations.  Consumed by the geo \$is_banned map."
  while IFS= read -r _ip; do
    [[ -z "${_ip}" ]] && continue
    if _is_ipv4_or_cidr "${_ip}"; then
      echo "${_ip} 1;"
    fi
  done <<< "${_ips}"
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
  echo "Nginx configtest failed after deny-set update: ${_configtest}"
  if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
    echo "Reverting to the last known good deny set."
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
  else
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here /dev/null "${_out_name}"
  fi
  exit 1
fi

if ! service nginx reload; then
  echo "Nginx reload failed; reverting deny set."
  if _acct_in_real_dir "${_out_dir}" _conf_get_file_here "${_backup_name}" "${_work}/back"; then
    _acct_in_real_dir "${_out_dir}" _conf_put_file_here "${_work}/back" "${_out_name}"
    service nginx reload
  fi
  exit 1
fi

_count=$(grep -c ' 1;$' "${_tmp_file}" 2>/dev/null)
echo "nginx web deny set updated (${_count} entr$([[ "${_count}" == "1" ]] && echo y || echo ies)); Nginx reloaded."
exit 0
