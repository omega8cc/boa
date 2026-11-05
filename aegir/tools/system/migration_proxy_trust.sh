#!/bin/bash

# Orchestrate migration-proxy trust on THIS host -- the glue xmass/xoct used to
# leave out, wiring the L7 realip recovery and the L4 csf whitelist together.
#
#   migration_proxy_trust.sh trust <ip|cidr> [<ip|cidr>...] [--permanent] [--csf-only]
#   migration_proxy_trust.sh untrust <ip|cidr> [<ip|cidr>...]
#   migration_proxy_trust.sh teardown [--force]
#   migration_proxy_trust.sh reconcile [--force]
#   migration_proxy_trust.sh adopt [--once]
#   migration_proxy_trust.sh release <ip>... [--to=<ip> [--since=<day>]|--over]
#   migration_proxy_trust.sh prune
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
# untrust: remove the given peer IP(s) only, exactly the lines trust writes for
#   them (both control files, csf.allow on 80 and 443, csf.ignore), then refresh
#   the realip include. Every other peer and the permanent marker stay as they
#   are, so one retired source never costs another migration its trust.
#
# teardown: remove ALL migration-proxy trust on this host (both control files,
#   the .cmig realip include, the csf entries) unless the permanent marker is set
#   (--force overrides). csf entries that the immediate strip misses are also
#   cleaned by the next *-water.sh tick (control file gone -> nothing re-added).
#
# reconcile: recompute the trust set from the per-account migration proxy policy
#   records, /root/.<oN>.migproxy.cnf (root:root 0600, written by xoct/xmass,
#   parsed and never sourced, never travelling with an account). Records this
#   host owns (its own _MIG_HOST_IP) with _MIG_ROLE=target decide which peers
#   stay trusted: any permanent or ha-switch peer keeps trust and the
#   permanent marker (ha-switch behaves exactly as permanent for trust and
#   teardown; it differs only in the client notification); all-temporary,
#   all-retired or no live peers tears everything down INCLUDING the marker,
#   because the union proves nothing needs it. Record peers must be plain
#   dotted quads (no CIDR, not this host, not loopback). An account marked
#   proxied (/root/.<oN>.migproxy.proxied) with no valid record is never
#   guessed at: its trust and the marker are left as found and reported. With
#   no records at all this behaves exactly as teardown always has (marker
#   honoured; --force overrides), so an unconverted fleet sees bit-identical
#   post-mig behaviour.
#   Nothing under /data/disk/<oN> is trusted: the account can write there.
#   A root-written log/migproxy.cnf left by older tools and never adopted
#   makes its account undeclared (add-only, no address taken from it, the
#   marker left as found) when the import refused it or it was written after
#   the import; an older copy the import never saw counts as absent, and an
#   account-written one is ignored and reported; log/proxied.pid is never
#   read.
#
# adopt: import, once per host, what older tools left in the accounts' log/
#   (log/migproxy.cnf and log/proxied.pid, both root-written) into the root
#   record and marker, only where root-only state vouches for it: a target
#   record needs every peer address in /root/.migration.peer.addrs, in a root
#   key line tagged '# xmass|xoct|xcopy migration source <ip>', or in a
#   csf.allow line an xmass run wrote for it ('<ip> # xmass migration
#   source', 'target' or 'inbound-proxy'); a source record needs its
#   peer in root's known_hosts, every live proxy vhost of the account
#   forwarding to it, and the pair named in root's own migration state (the
#   xoct gate file /var/log/boa/xoct.migrate.<oN>_<ip>.state, the xmass gate
#   file /var/log/boa/xmass.migrate.<ip>.state, or _XMASS_TARGET_IP=<ip> in
#   /data/conf/xmass_state.cnf), and is refused when that peer also migrated
#   into this box (any of those witnesses but the 'target' csf line a move
#   out of this box wrote: a promoted or round-trip pair, where the record
#   may be superseded) unless the account still relays there: its
#   log/proxied.pid a marker as below and at least one live proxy vhost,
#   every one forwarding to that peer (a promotion removed that file); a
#   source record naming no peer at all (a pin set before any proxy) names
#   no pair, so it is refused and declared again with 'xoct proxy-mode'; a
#   marker needs a root-owned log/proxied.pid reading COMPLETE (its age is
#   carried from that file's mtime). Anything else is refused and the report
#   prints the remedy. An account marked proxied whose root record names no
#   peer gets an ALRT line with the restate remedy: its certificates are not
#   mirrored and a failback denies it until then. So does every adopted
#   source record: its peer account, whatever name it holds, is the copy's
#   (older tools took it from log/), not used until the peer confirms it from
#   its create marker or root restates the pair; no remedy prints the name a
#   copy holds for an account on the other box. The report also names each
#   relay-list address no root record accounts for, with 'untrust <ip>' as
#   the remedy once it is confirmed stale (report only). Without --once it
#   only reports what it would do. --once writes
#   /root/.migration.records.adopted, one line per account and kind with the
#   remedy of a refusal; once it exists nothing is ever imported again, and
#   'adopt' shows what it found, plus the ALRT lines root's files call for
#   now. It reloads no daemon and changes no trust. Text an account could
#   have placed reaches the report and the stamp only as printable bytes.
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

# Per-account records and proxied markers live in root's own home, never in
# the account's tree. Plain assignments, never taken from the environment.
_MIG_REC_DIR="/root"
_MIG_ADOPT_STAMP="/root/.migration.records.adopted"
_MIG_ADOPT_LOCK="/run/boa_migproxy_adopt.lock"
_MIG_PEER_ADDRS="/root/.migration.peer.addrs"
_MIG_AUTH_KEYS="/root/.ssh/authorized_keys"
_MIG_KNOWN_HOSTS="/root/.ssh/known_hosts"
_MIG_CSF_ALLOW="/etc/csf/csf.allow"
# Where the migrations of this box keep their own gate and phase state:
# root's, so a source record's pair is vouched for there, never by the
# account.
_MIG_STATE_DIR="/var/log/boa"
_MIG_XMASS_STATE="/data/conf/xmass_state.cnf"
_MIG_INFO_NAME="migproxy.cnf"
_MIG_REC_HDR="# BOA migration proxy policy (root record). Managed by xoct/xmass. Do not edit by hand."
_MIG_MARK_HDR="# BOA migration proxied marker (root). Managed by xoct/xmass. Do not edit by hand."
_MIG_INFO_PFX="# BOA migration proxy policy (informational copy"
_MIG_LEGACY_HDR="# BOA migration proxy policy. Managed by xoct/xmass. Do not edit by hand."
_MIG_OCTET="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
# ./$1 read through one handle opened O_RDONLY|O_NOFOLLOW|O_NONBLOCK and only
# when that handle is a regular file with one link, owned by root, writable by
# no one else, at most 64 KiB; shape "legacy" also needs gid 0 and mode 0600.
# Prints the handle's mtime on a line of its own, then the bytes. Exit 3 when
# the name is absent, 4 for any other name or shape, 5 on a read error. No
# single quote in the text: it also travels inside remote heredocs.
_MIG_HREAD_PL='use Fcntl; use Errno qw(ENOENT); my ($n, $s) = @ARGV; exit 4 unless defined $s && ($s eq "root" || $s eq "legacy"); sysopen(my $h, $n, O_RDONLY|O_NOFOLLOW|O_NONBLOCK) or exit($! == ENOENT ? 3 : 4); my @t = stat($h); exit 4 unless @t && -f _ && $t[3] == 1 && $t[4] == 0 && $t[7] <= 65536 && ($t[2] & 022) == 0; exit 4 if $s eq "legacy" && !($t[5] == 0 && ($t[2] & 07777) == 0600); my ($d, $r) = (""); while ($r = sysread($h, my $c, 65536)) { $d .= $c; exit 4 if length($d) > 65536; } exit 5 unless defined $r; close($h); binmode(STDOUT); print "$t[9]\n", $d or exit 5; exit 0'
# The file ./$1 (never there before) created with the bytes read from stdin,
# the owner $2:$3 and the read/write bits of the mode $4, all through the one
# handle that created it, opened O_EXCL|O_NOFOLLOW.
_MIG_PUT_PL='use Fcntl; my ($n, $u, $g, $m) = @ARGV; local $/; my $d = <STDIN>; sysopen(my $h, $n, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW, 0600) or exit 1; (print {$h} $d) or exit 1; chown($u, $g, $h) or exit 1; chmod(oct($m) & 0666, $h) or exit 1; close($h) or exit 1; exit 0'

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

  local _ip _fail=""
  for _ip in "${_ips[@]}"; do
    _uniq_append "${_csf_ctrl}" "${_ip}"
    _csf_add_ip "${_ip}"
    if [ "${_csf_only}" != "YES" ] \
      && ! _conf_uniq_append "${_realip_ctrl}" "${_ip}"; then
      _fail="${_fail} ${_ip}"
      _msg "WARN: ${_ip} not recorded in ${_realip_ctrl}"
      continue
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
    if _conf_flag_put "${_perm_flag}"; then
      _msg "marked migration proxy trust PERMANENT (${_perm_flag})"
    else
      _fail="${_fail} ${_perm_flag}"
    fi
  fi
  [ -z "${_fail}" ] || _die "trust: not recorded:${_fail}"
}

# Drop the lines equal to $2 from file $1, in place (owner and mode kept).
# 0 = dropped, 1 = not there, 2 = the rewrite failed and the file is as found:
# a short write (a full disk) must never leave a truncated firewall list.
_drop_line() {
  local _f="$1" _v="$2" _t _rc
  [ -f "${_f}" ] && grep -qxF -- "${_v}" "${_f}" 2>/dev/null || return 1
  _t="$(mktemp "${_f}.untrust.XXXXXX")" || return 2
  grep -vxF -- "${_v}" "${_f}" > "${_t}"
  _rc=$?
  # grep: 0 = lines kept, 1 = none left (every line matched), above 1 = error
  # and the copy must hold every other line (grep -c '' counts an
  # unterminated last line too)
  if [ "${_rc}" -gt 1 ] || [ "$(( $(grep -c '' "${_f}") - $(grep -cxF -- "${_v}" "${_f}") ))" -ne "$(grep -c '' "${_t}")" ]; then
    rm -f "${_t}"
    return 2
  fi
  if ! cat "${_t}" > "${_f}"; then
    rm -f "${_t}"
    return 2
  fi
  rm -f "${_t}"
  return 0
}

_cmd_untrust() {
  local _a _ip _port
  local -a _ips=()
  for _a in "$@"; do
    case "${_a}" in
      --*) _die "unknown option ${_a}" ;;
      *)   _is_ip "${_a}" || _die "not an IP/CIDR: ${_a}"; _ips+=("${_a}") ;;
    esac
  done
  [ "${#_ips[@]}" -gt 0 ] || _die "untrust: no IP/CIDR given"

  local _v _rc
  for _ip in "${_ips[@]}"; do
    _conf_drop_line "${_realip_ctrl}" "${_ip}"
    [ "$?" -eq 2 ] && _die "untrust: could not rewrite ${_realip_ctrl}; left as found"
    _drop_line "${_csf_ctrl}" "${_ip}"
    [ "$?" -eq 2 ] && _die "untrust: could not rewrite ${_csf_ctrl}; left as found"
    if _csf_present; then
      for _v in "tcp|in|d=80|s=${_ip} # migration proxy" "tcp|in|d=443|s=${_ip} # migration proxy"; do
        _drop_line "${_csf_allow}" "${_v}"; _rc=$?
        [ "${_rc}" -eq 2 ] && _die "untrust: could not rewrite ${_csf_allow}; left as found"
        [ "${_rc}" -eq 0 ] && _CSF_CHANGED="YES"
      done
      _drop_line "${_csf_ignore}" "${_ip} # migration proxy"; _rc=$?
      [ "${_rc}" -eq 2 ] && _die "untrust: could not rewrite ${_csf_ignore}; left as found"
      [ "${_rc}" -eq 0 ] && _CSF_CHANGED="YES"
    fi
    _msg "untrusted migration peer ${_ip}"
  done

  [ "${_CSF_CHANGED}" = "YES" ] && _csf_reload
  [ -x "${_realip_tool}" ] && "${_realip_tool}"
}

_cmd_teardown() {
  local _force="NO"
  [ "${1:-}" = "--force" ] && _force="YES"
  if [ -e "${_perm_flag}" ] && [ "${_force}" != "YES" ]; then
    _msg "permanent migration proxy marker present; teardown skipped (use --force)"
    return 0
  fi
  local _dropped=YES
  _conf_drop_file "${_realip_ctrl}" || _dropped=NO
  rm -f "${_csf_ctrl}" "${_perm_flag}"
  _csf_strip
  _csf_reload
  # Control file now gone -> the tool removes the .cmig include.
  [ -x "${_realip_tool}" ] && "${_realip_tool}"
  [ "${_dropped}" = "YES" ] || _die "teardown: could not remove ${_realip_ctrl}"
  _msg "migration proxy trust torn down on this host"
}

# --- per-account policy records (the _mig_* primitives xoct and xmass carry) --
#
# Kept in step with the copies in xoct and xmass, not shared: each body here
# is theirs except the directory pin (_mpt_in_real_dir), the put text
# (_MIG_PUT_PL) and _mig_log_class, which also keeps what it read for adopt.

# The account owns /data/disk/<oN>, so any name there can be a link or a
# FIFO and log/ itself a link, and /data/conf can still be in an account's
# hands (see below): a name in either is read only inside the real
# directory, never through a link, never blocked on a FIFO. Root's own
# directories (/root, /var/log/boa) are entered the same way.
_mpt_in_real_dir() {
  local _d="${1}" _a="" _want
  shift
  case "${_d}" in
    /home/?*) _a=/home ;;
    /data/disk/?*) _a=/data/disk ;;
  esac
  if [ -n "${_a}" ]; then
    _want="$(cd -P -- "${_a}" 2> /dev/null && pwd -P)${_d#"${_a}"}"
  else
    # The parent of a top-level directory (/root) is "/", never the empty
    # name: cd "" fails on one bash and follows CDPATH on another.
    _want="$(cd -P -- "${_d%/*}/" 2> /dev/null && pwd -P)"
    _want="${_want%/}/${_d##*/}"
  fi
  ( cd -P -- "${_d}" 2> /dev/null && [ "$(pwd -P)" = "${_want}" ] && "$@" )
}
_mpt_read_here() {
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
    bs=1048576 count=1 status=none 2> /dev/null
}

# /data/conf is root's, but an Octopus upgrade of an earlier release handed it
# to the account it upgraded, so the trust file's and the flag's names there
# can still be a link or a FIFO that account left: they are read and put only
# inside the real /data/conf (_mpt_in_real_dir), through these, on a copy in a
# root-only work directory in /run.
#
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
# Each read-change-put of a /data/conf file below holds this tool's own lock
# (never the shared nginx one, which the realip tool it runs takes), so two
# runs cannot lose each other's line; no daemon starts while it is held.
_CONF_LOCK="/run/.migration_proxy_trust.lock"
# True when $1 is there as a regular file (not a link): a copy of it that
# failed is an error, never an empty file.
_conf_is_plain() {
  [ -f "${1}" ] && [ ! -L "${1}" ]
}
# The line $2 added to the file $1 in /data/conf unless it is there, as
# _uniq_append adds it.
_conf_uniq_append() (
  local _w _rc=0
  exec 8> "${_CONF_LOCK}"
  flock -w 30 8 || exit 1
  _w="$(mktemp -d /run/.migration_proxy_trust.XXXXXX 2> /dev/null)" || exit 1
  trap 'rm -rf -- "${_w}"' EXIT
  mkdir -p "${1%/*}"
  if ! _mpt_in_real_dir "${1%/*}" _conf_get_file_here "${1##*/}" "${_w}/cur"; then
    _conf_is_plain "${1}" && exit 1
    : > "${_w}/cur" || exit 1
  fi
  if ! grep -qxF -- "${2}" "${_w}/cur" 2> /dev/null; then
    echo "${2}" >> "${_w}/cur" || exit 1
    _mpt_in_real_dir "${1%/*}" _conf_put_file_here "${_w}/cur" "${1##*/}" || _rc=1
  fi
  exit "${_rc}"
)
# The lines equal to $2 dropped from the file $1 in /data/conf, as _drop_line
# drops them: 0 = dropped, 1 = not there, 2 = the rewrite failed and the file
# is as found.
_conf_drop_line() (
  local _w _rc
  exec 8> "${_CONF_LOCK}"
  flock -w 30 8 || exit 2
  _w="$(mktemp -d /run/.migration_proxy_trust.XXXXXX 2> /dev/null)" || exit 2
  trap 'rm -rf -- "${_w}"' EXIT
  if ! _mpt_in_real_dir "${1%/*}" _conf_get_file_here "${1##*/}" "${_w}/cur"; then
    _conf_is_plain "${1}" && exit 2
    exit 1
  fi
  _drop_line "${_w}/cur" "${2}"
  _rc=$?
  if [ "${_rc}" -eq 0 ] \
    && ! _mpt_in_real_dir "${1%/*}" _conf_put_file_here "${_w}/cur" "${1##*/}"; then
    _rc=2
  fi
  exit "${_rc}"
)
# The file $1 in /data/conf removed under the lock _conf_uniq_append takes,
# so an append in flight cannot bring back what a teardown just removed.
_conf_drop_file() (
  exec 8> "${_CONF_LOCK}"
  flock -w 30 8 || exit 1
  _mpt_in_real_dir "${1%/*}" _conf_rm_here "${1##*/}"
)
_conf_rm_here() {
  if [ -d "./${1}" ] && [ ! -L "./${1}" ]; then
    rm -rf -- "./${1}"
  else
    rm -f -- "./${1}"
  fi
}
# The regular file $1 in /data/conf printed, read as _conf_get_file_here reads
# it (a link or a FIFO at the name prints nothing and is never opened).
_conf_cat() (
  local _w
  _w="$(mktemp -d /run/.migration_proxy_trust.XXXXXX 2> /dev/null)" || exit 1
  trap 'rm -rf -- "${_w}"' EXIT
  _mpt_in_real_dir "${1%/*}" _conf_get_file_here "${1##*/}" "${_w}/cur" && cat "${_w}/cur"
)
# The empty flag file $1 in /data/conf put as : > made it.
_conf_flag_put() {
  mkdir -p "${1%/*}"
  _mpt_in_real_dir "${1%/*}" _conf_put_file_here /dev/null "${1##*/}"
}

_mig_valid_mode() {
  case "$1" in
    temporary|permanent|ha-switch|retired) return 0 ;;
    *) return 1 ;;
  esac
}
_mig_valid_acct() { [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]; }
_mig_valid_date() { [[ "$1" =~ ^20[0-9]{2}-[01][0-9]-[0-3][0-9]$ ]]; }
# Strict dotted quad: every octet 0-255, no leading zero, no prefix.
_mig_quad() { [[ "${1}" =~ ^(${_MIG_OCTET}\.){3}${_MIG_OCTET}$ ]]; }
# $1 is one of the addresses this box holds.
_mig_own_addr() {
  [ -n "${1}" ] || return 1
  hostname -I 2> /dev/null | tr ' ' '\n' | grep -qxF -- "${1}"
}
# A peer address a record may name: a strict dotted quad that is neither
# the all-zeros host, loopback, nor one of this box's own addresses.
_mig_peer_ok() {
  _mig_quad "${1}" || return 1
  [ "${1}" != "0.0.0.0" ] || return 1
  case "${1}" in
    127.*) return 1 ;;
  esac
  ! _mig_own_addr "${1}"
}
# A trust-set peer: one host, never a range, never the all-zeros host or
# loopback. Peers are split without pathname expansion wherever they are read.
_is_dotted_quad() {
  _mig_quad "${1}" && [ "${1}" != "0.0.0.0" ] && [[ "${1}" != 127.* ]]
}

_my_ipv4s() {
  hostname -I 2>/dev/null | tr ' ' '\n' \
    | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

# Account directories under /data/disk, system directories excluded.
_mig_list_accounts() {
  local _d
  while IFS= read -r _d; do
    _d="${_d##*/}"
    case "${_d}" in
      arch|all|lost+found|lostfound|backups|codebases-cleanup|legacy|xusage) continue ;;
      .*|'') continue ;;
    esac
    _mig_valid_acct "${_d}" && echo "${_d}"
  done < <(find /data/disk -maxdepth 1 -mindepth 1 -type d 2> /dev/null | sort)
}

# Each non-blank line a comment or one _MIG_ key assignment, no key twice:
# anything else makes the whole text malformed. Reads stdin.
_mig_grammar_ok() {
  awk '/^[ \t]*$/ { next }
    /^#/ { next }
    /^_MIG_[A-Z_]+=/ { k = $0; sub(/=.*/, "", k); if (k in s) b = 1; s[k] = 1; next }
    { b = 1 }
    END { exit b }'
}
# The value of the key $2 in the record text $1; empty when missing.
_mig_txt_get() {
  printf '%s\n' "${1}" | grep -m1 "^${2}=" | cut -d= -f2- | tr -d '\r\n'
}

# The file $2 in the real directory $1, read with _MIG_HREAD_PL in the
# shape $3: the handle's mtime line, then the content. Status 0 read, 3
# absent, 4 anything else at the name (or the directory not a real one),
# 5 a read error.
_mig_hread() {
  local _rc
  case "${2}" in
    ""|*/*) return 4 ;;
  esac
  if [ ! -e "${1}" ] && [ ! -L "${1}" ]; then
    return 3
  fi
  _mpt_in_real_dir "${1}" perl -e "${_MIG_HREAD_PL}" -- "./${2}" "${3}"
  _rc=$?
  case "${_rc}" in
    0|3|4|5) return "${_rc}" ;;
  esac
  return 4
}
# The root record and marker paths of the account $1; status 1, nothing
# printed, for a name that is not an account's.
_mig_rec() {
  _mig_valid_acct "${1}" && [ "${1#.}" = "${1}" ] || return 1
  printf '%s\n' "${_MIG_REC_DIR}/.${1}.migproxy.cnf"
}
_mig_mark() {
  _mig_valid_acct "${1}" && [ "${1#.}" = "${1}" ] || return 1
  printf '%s\n' "${_MIG_REC_DIR}/.${1}.migproxy.proxied"
}
# The root file $1 (a name in _MIG_REC_DIR) without its mtime line, CR
# stripped, once it reads in the root shape and keeps the grammar. Status 3
# absent, 4 anything else.
_mig_root_text() {
  local _t _rc
  _t="$(_mig_hread "${_MIG_REC_DIR}" "${1}" root)"
  _rc=$?
  case "${_rc}" in
    0) ;;
    3) return 3 ;;
    *) return 4 ;;
  esac
  _t="$(printf '%s\n' "${_t}" | sed 1d | tr -d '\r')"
  printf '%s\n' "${_t}" | _mig_grammar_ok || return 4
  printf '%s\n' "${_t}"
}
# The root record of the account $1. Status 1 bad name, 3 none, 4
# malformed.
_mig_rec_text() {
  local _n
  _n="$(_mig_rec "${1}")" || return 1
  _mig_root_text "${_n##*/}"
}
# The mtime of the handle the root record of $1 was read through.
_mig_rec_mtime() {
  local _n _t _rc
  _n="$(_mig_rec "${1}")" || return 1
  _t="$(_mig_hread "${_MIG_REC_DIR}" "${_n##*/}" root)"
  _rc=$?
  case "${_rc}" in
    0) ;;
    3) return 3 ;;
    *) return 4 ;;
  esac
  printf '%s\n' "${_t}" | sed 1d | tr -d '\r' | _mig_grammar_ok || return 4
  printf '%s\n' "${_t%%$'\n'*}"
}
# The value of the key $2 in the root record of $1 (empty when the key is
# missing). Parsed, never sourced.
_mig_rec_get() {
  local _t _rc
  _t="$(_mig_rec_text "${1}")"
  _rc=$?
  [ "${_rc}" = "0" ] || return "${_rc}"
  _mig_txt_get "${_t}" "${2}"
  return 0
}
# The record text $1 authored by this box: its _MIG_HOST_IP is one of
# this box's addresses. A record for another address (a renumbered box)
# is reported, never acted on.
_mig_txt_mine() {
  local _h
  _h="$(_mig_txt_get "${1}" _MIG_HOST_IP)"
  _mig_quad "${_h}" && _mig_own_addr "${_h}"
}
_mig_is_mine() {
  local _t
  _t="$(_mig_rec_text "${1}")" || return 1
  _mig_txt_mine "${_t}"
}
# A value read from a copy root did not write itself, as a refusal shows it:
# at most 64 bytes, anything outside the address and name alphabet as ?, so
# no terminal control byte and no pasteable text reaches root's screen or
# the import stamp.
_mig_shown() {
  printf '%s' "${1}" | LC_ALL=C head -c 64 | LC_ALL=C tr -c 'A-Za-z0-9._:/,-' '?'
}
# Every key of the record text $1 within its grammar; the first failing
# reason printed, status 1. Unknown keys are left to the caller.
_mig_txt_valid() {
  local _t="${1}" _v _role _peer _ip _k
  local -a _ips
  _role="$(_mig_txt_get "${_t}" _MIG_ROLE)"
  case "${_role}" in
    source|target) ;;
    *) echo "invalid _MIG_ROLE '$(_mig_shown "${_role}")'"; return 1 ;;
  esac
  _v="$(_mig_txt_get "${_t}" _MIG_HOST_IP)"
  _mig_quad "${_v}" || { echo "invalid _MIG_HOST_IP '$(_mig_shown "${_v}")'"; return 1; }
  _peer="$(_mig_txt_get "${_t}" _MIG_PEER_IP)"
  if [ -n "${_peer}" ] && ! _mig_peer_ok "${_peer}"; then
    echo "invalid _MIG_PEER_IP '$(_mig_shown "${_peer}")'"
    return 1
  fi
  if [ "${_role}" = "target" ] && [ -z "${_peer}" ]; then
    echo "target record without _MIG_PEER_IP"
    return 1
  fi
  _v="$(_mig_txt_get "${_t}" _MIG_PEER_IPS)"
  IFS=' ,' read -r -a _ips <<< "${_v}"
  for _ip in "${_ips[@]}"; do
    _mig_peer_ok "${_ip}" || { echo "invalid _MIG_PEER_IPS address '$(_mig_shown "${_ip}")'"; return 1; }
  done
  _v="$(_mig_txt_get "${_t}" _MIG_PEER_OCT)"
  if [ -n "${_v}" ] && ! _mig_valid_acct "${_v}"; then
    echo "invalid _MIG_PEER_OCT '$(_mig_shown "${_v}")'"
    return 1
  fi
  _v="$(_mig_txt_get "${_t}" _MIG_MODE)"
  _mig_valid_mode "${_v}" || { echo "invalid _MIG_MODE '$(_mig_shown "${_v}")'"; return 1; }
  _v="$(_mig_txt_get "${_t}" _MIG_SCOPE)"
  case "${_v}" in
    account|box|"") ;;
    *) echo "invalid _MIG_SCOPE '$(_mig_shown "${_v}")'"; return 1 ;;
  esac
  _v="$(_mig_txt_get "${_t}" _MIG_DEADLINE)"
  if [ -n "${_v}" ] && [ "${_v}" != "none" ] && ! _mig_valid_date "${_v}"; then
    echo "invalid _MIG_DEADLINE '$(_mig_shown "${_v}")'"
    return 1
  fi
  for _k in _MIG_RETIRE_DATE _MIG_STAMPED _MIG_ADOPTED _MIG_RELAY_ENDED; do
    _v="$(_mig_txt_get "${_t}" "${_k}")"
    if [ -n "${_v}" ] && ! _mig_valid_date "${_v}"; then
      echo "invalid ${_k} '$(_mig_shown "${_v}")'"
      return 1
    fi
  done
  return 0
}
# The root record of $1 passes every rule a decision needs.
_mig_rec_valid() {
  local _t _rc
  _t="$(_mig_rec_text "${1}")"
  _rc=$?
  case "${_rc}" in
    0) ;;
    3) echo "no root record"; return 1 ;;
    *) echo "malformed root record"; return 1 ;;
  esac
  _mig_txt_valid "${_t}"
}
# The accounts that hold a root record, one per line, sorted. A name that
# is not an account's, or whose /data/disk/<name> is not a real directory,
# is skipped and named on stderr: a record ends when its account ends.
_mig_rec_list() {
  local _f _a _l=""
  for _f in "${_MIG_REC_DIR}"/.*.migproxy.cnf; do
    [ -e "${_f}" ] || [ -L "${_f}" ] || continue
    _a="${_f#"${_MIG_REC_DIR}/."}"; _a="${_a%.migproxy.cnf}"
    if ! _mig_rec "${_a}" > /dev/null; then
      echo "record ${_f}: not an account name; skipped" >&2
      continue
    fi
    if [ ! -d "/data/disk/${_a}" ] || [ -L "/data/disk/${_a}" ]; then
      echo "record ${_f}: /data/disk/${_a} is not a real directory; skipped" >&2
      continue
    fi
    _l="${_l}${_a}"$'\n'
  done
  [ -n "${_l}" ] && printf '%s' "${_l}" | sort
  return 0
}
# stdin put at $1, a name in _MIG_REC_DIR: a fresh root:root 0600 file
# created through one handle (_MIG_PUT_PL), then renamed over the name.
_mig_root_put() {
  case "${1}" in
    ""|*/*|.|..) return 1 ;;
  esac
  ( umask 077
    cd -P -- "${_MIG_REC_DIR}" 2> /dev/null || exit 1
    _t="./${1}.put.$$.${RANDOM}"
    rm -f -- "${_t}"
    if perl -e "${_MIG_PUT_PL}" "${_t}" 0 0 600 \
      && mv -f -T -- "${_t}" "./${1}"; then
      exit 0
    fi
    rm -f -- "${_t}"
    exit 1 )
}
# The root record of $1 replaced by stdin.
_mig_rec_put() {
  local _n
  _n="$(_mig_rec "${1}")" || return 1
  _mig_root_put "${_n##*/}"
}
# The root proxied marker of $1, written by the tool $2 and dated with the
# epoch $3 (now when empty).
_mig_mark_put() {
  local _n _at="${3}"
  _n="$(_mig_mark "${1}")" || return 1
  case "${2}" in
    xoct|xmass|adopt) ;;
    *) return 1 ;;
  esac
  [ -n "${_at}" ] || _at="$(date +%s)"
  [[ "${_at}" =~ ^[0-9]{9,11}$ ]] || return 1
  printf '%s\n' "${_MIG_MARK_HDR}" "_MIG_PROXIED=COMPLETE" \
    "_MIG_PROXIED_AT=${_at}" "_MIG_PROXIED_BY=${2}" \
    | _mig_root_put "${_n##*/}"
}
# The epoch the account $1 was proxied at, printed when its root marker is
# valid: root shape, the grammar, COMPLETE, and a sane date (no later than
# a day ahead). Status 1 otherwise.
_mig_mark_at() {
  local _n _t _at
  _n="$(_mig_mark "${1}")" || return 1
  _t="$(_mig_root_text "${_n##*/}")" || return 1
  [ "$(_mig_txt_get "${_t}" _MIG_PROXIED)" = "COMPLETE" ] || return 1
  _at="$(_mig_txt_get "${_t}" _MIG_PROXIED_AT)"
  [[ "${_at}" =~ ^[0-9]{9,11}$ ]] || return 1
  [ "${_at}" -le "$(( $(date +%s) + 86400 ))" ] || return 1
  printf '%s\n' "${_at}"
}
_mig_is_proxied() {
  _mig_mark_at "${1}" > /dev/null
}
# Whether the root source record of $1 was imported from an older tool's
# copy: its peer account, whatever name it holds, is the copy's, which an
# account could have planted (older tools took it from log/). Nothing acts
# on that name unless the peer confirms it from its own create marker, or
# root restates the pair.
_mig_rec_adopted_src() {
  local _t
  _t="$(_mig_rec_text "${1}")" || return 1
  [ "$(_mig_txt_get "${_t}" _MIG_ROLE)" = "source" ] || return 1
  [ -n "$(_mig_txt_get "${_t}" _MIG_ADOPTED)" ]
}
# What log/migproxy.cnf of the account $1 is, in one word, for display,
# classification and refusals only: it never supplies an address or a
# mode. "none" absent; "account" anything the account could have put
# there (a link, a FIFO, another owner or mode, a hard link, or a root file
# without a known header); "info" the informational copy; "legacy-mine
# <mtime>" a record an older tool wrote on this box; "legacy-foreign" one
# that travelled here; "legacy-stale" an older copy the one-time import
# never judged (counts as absent; see _mig_copy_stale). Called without a
# subshell it also leaves the word in _MIG_LOG_CLS and the read in
# _MIG_LOG_RAW, so adopt judges the very bytes it classified.
_MIG_LOG_CLS=""
_MIG_LOG_RAW=""
_mig_log_class() {
  local _t _rc _m _l1 _h
  _MIG_LOG_CLS=none
  _MIG_LOG_RAW=""
  if ! _mig_valid_acct "${1}"; then
    echo none
    return 1
  fi
  _t="$(_mig_hread "/data/disk/${1}/log" "${_MIG_INFO_NAME}" legacy)"
  _rc=$?
  case "${_rc}" in
    0) ;;
    3) echo none; return 0 ;;
    *) _MIG_LOG_CLS=account; echo account; return 0 ;;
  esac
  _MIG_LOG_RAW="${_t}"
  _m="${_t%%$'\n'*}"
  _t="$(printf '%s\n' "${_t}" | sed 1d | tr -d '\r')"
  _l1="${_t%%$'\n'*}"
  case "${_l1}" in
    "${_MIG_INFO_PFX}"*) _MIG_LOG_CLS=info; echo info; return 0 ;;
  esac
  if [ "${_l1}" = "${_MIG_LEGACY_HDR}" ]; then
    _h="$(_mig_txt_get "${_t}" _MIG_HOST_IP)"
    if _mig_quad "${_h}" && _mig_own_addr "${_h}"; then
      _MIG_LOG_CLS="legacy-mine ${_m}"
      _mig_copy_stale "${1}" "${_m}" && _MIG_LOG_CLS=legacy-stale
    else
      _MIG_LOG_CLS=legacy-foreign
    fi
    echo "${_MIG_LOG_CLS}"
    return 0
  fi
  _MIG_LOG_CLS=account
  echo account
}
# Whether the legacy copy of $1 (handle mtime $2) is one the one-time import
# never judged: the stamp exists, the copy is not newer, and the stamp does
# not list the account's record as refused. Such a copy was set aside while
# the import ran and put back after; it counts as absent.
_mig_copy_stale() {
  local _st
  _st="$(_mig_hread "${_MIG_ADOPT_STAMP%/*}" "${_MIG_ADOPT_STAMP##*/}" root 2> /dev/null)" || return 1
  [[ "${_st%%$'\n'*}" =~ ^[0-9]+$ ]] && [[ "${2}" =~ ^[0-9]+$ ]] || return 1
  [ "${2}" -le "${_st%%$'\n'*}" ] || return 1
  ! printf '%s\n' "${_st}" | awk -F'|' -v a="${1}" \
    '$1 == a && $2 == "record" && $3 == "refused" { f = 1 } END { exit !f }'
}
# _MIG_ROLE (or the key $2) of a legacy-shaped log/migproxy.cnf of $1
# (either host), else empty. For refusals only: a value read here is
# compared or named in a refusal, never acted on.
_mig_log_role() {
  local _t _k="${2:-_MIG_ROLE}"
  _mig_valid_acct "${1}" || return 0
  case "${_k}" in
    _MIG_ROLE|_MIG_PEER_IP|_MIG_PEER_OCT) ;;
    *) return 0 ;;
  esac
  _t="$(_mig_hread "/data/disk/${1}/log" "${_MIG_INFO_NAME}" legacy)" || return 0
  _t="$(printf '%s\n' "${_t}" | sed 1d | tr -d '\r')"
  [ "${_t%%$'\n'*}" = "${_MIG_LEGACY_HDR}" ] || return 0
  _mig_txt_get "${_t}" "${_k}"
}
# Whether root itself holds a witness of the migration peer $1: the
# address list root keeps beside each peer record it receives, a root key
# line tagged for that address by a pre-mig, or a firewall line an xmass
# run wrote for that pair (its source, its target, or the inbound reach a
# promotion carried). The relay list and the realip file are not
# witnesses: records feed them.
_mig_witnessed() {
  local _rx
  _mig_quad "${1}" || return 1
  _rx="${1//./\\.}"
  grep -qxF -- "${1}" "${_MIG_PEER_ADDRS}" 2> /dev/null && return 0
  grep -vE '^[[:space:]]*#' "${_MIG_AUTH_KEYS}" 2> /dev/null \
    | grep -qE -- " # (xmass|xoct|xcopy) migration source ${_rx}[[:space:]]*\$" \
    && return 0
  grep -qE -- "^${_rx} # xmass migration (source|target|inbound-proxy)[[:space:]]*\$" "${_MIG_CSF_ALLOW}" 2> /dev/null
}

# Whether the relay the target record text $1 describes is over: an init on its
# front ended it (_MIG_RELAY_ENDED), or it was retired and its promised date has
# passed. A retired record with no readable date is never over.
_mig_txt_relay_over() {
  local _d
  [ -n "$(_mig_txt_get "${1}" _MIG_RELAY_ENDED)" ] && return 0
  [ "$(_mig_txt_get "${1}" _MIG_MODE)" = "retired" ] || return 1
  _d="$(_mig_txt_get "${1}" _MIG_RETIRE_DATE)"
  [ -n "${_d}" ] || _d="$(_mig_txt_get "${1}" _MIG_STAMPED)"
  _mig_valid_date "${_d}" || return 1
  [[ "${_d}" < "$(date -u '+%Y-%m-%d')" ]]
}

# --- trust-only helpers ------------------------------------------------------

# Which of the three witnesses vouches for $1, for the report only (the
# decision is _mig_witnessed's): each one asked alone, a firewall line named
# by its kind.
_mpt_witness_kind() {
  local _k _rx="${1//./\\.}"
  if ( _MIG_AUTH_KEYS=/dev/null; _MIG_CSF_ALLOW=/dev/null; _mig_witnessed "${1}" ); then
    echo peer.addrs
  elif ( _MIG_PEER_ADDRS=/dev/null; _MIG_CSF_ALLOW=/dev/null; _mig_witnessed "${1}" ); then
    echo key-tag
  elif ( _MIG_PEER_ADDRS=/dev/null; _MIG_AUTH_KEYS=/dev/null; _mig_witnessed "${1}" ); then
    for _k in source inbound-proxy target; do
      if grep -qE -- "^${_rx} # xmass migration ${_k}[[:space:]]*\$" "${_MIG_CSF_ALLOW}" 2> /dev/null; then
        echo "csf-${_k}"
        return 0
      fi
    done
    echo csf
  else
    echo none
  fi
}
# Whether root holds a witness that the peer $1 migrated or relays INTO this
# box: any witness but the firewall line a move out of this box wrote for its
# own target, which every xmass source keeps for the peer its records name.
_mpt_inbound_witnessed() {
  local _rx
  ( _MIG_CSF_ALLOW=/dev/null; _mig_witnessed "${1}" ) && return 0
  _mig_quad "${1}" || return 1
  _rx="${1//./\\.}"
  grep -qE -- "^${_rx} # xmass migration (source|inbound-proxy)[[:space:]]*\$" "${_MIG_CSF_ALLOW}" 2> /dev/null
}
# A name an operator may be shown inside a command line: an account name
# that starts with a letter or a digit. A leading dash reads as an option
# (--all), a leading dot is no account's.
_mpt_name_ok() { [ "${#1}" -le 64 ] && [[ "${1}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; }
# Report text as the terminal and the stamp may take it: every control and
# 8-bit byte dropped (no escape sequence, no line break that would forge a
# stamp line). A backstop under _mig_shown, which names the values.
_mpt_plain() { printf '%s' "${1}" | LC_ALL=C tr -d '\000-\037\177-\377'; }
# The first _MIG_ key of the record text $1 the record format does not
# define; nothing when every key is known.
_mpt_unknown_key() {
  printf '%s\n' "${1}" | grep -E '^_MIG_[A-Z_]+=' | cut -d= -f1 \
    | grep -vxE '_MIG_(ROLE|HOST_IP|PEER_IP|PEER_OCT|MODE|SCOPE|DEADLINE|RETIRE_DATE|PEER_IPS|STAMPED|ADOPTED)' \
    | head -n1
}
# Root-only state naming the account $1 and the peer $2 as a pair a
# migration from this box ran: the xoct gate file of that account and
# target (either mode), the xmass gate file of that target, or that target
# in this box's xmass state. The account can write none of them. Prints
# which; status 1 when none does.
_mpt_pair_state() {
  local _t
  _mig_valid_acct "${1}" && [ "${1#.}" = "${1}" ] && _is_dotted_quad "${2}" || return 1
  if _mig_hread "${_MIG_STATE_DIR}" "xoct.migrate.${1}_${2}.state" root > /dev/null; then
    echo xoct-state
    return 0
  fi
  if _mig_hread "${_MIG_STATE_DIR}" "xmass.migrate.${2}.state" root > /dev/null; then
    echo xmass-state
    return 0
  fi
  _t="$(_mig_hread "${_MIG_XMASS_STATE%/*}" "${_MIG_XMASS_STATE##*/}" root)" || return 1
  printf '%s\n' "${_t}" | sed 1d | tr -d '\r' | grep -qxF -- "_XMASS_TARGET_IP=${2}" || return 1
  echo xmass-target
}

# The proxy_pass target of each live proxy vhost of account $1 ("tgt <t>"),
# then the count of rename-redirect vhosts ("redirects <n>"). Live means no
# leading dot and no https. prefix; the local control panel and the rename
# redirects are not proxy vhosts. Read inside the real vhost.d.
_mig_vhost_targets() {
  local _u="/data/disk/${1}" _vd _pd _n _vt _t _r=0
  _vd="${_u}/config/server_master/nginx/vhost.d"
  _pd="$(_mpt_in_real_dir "${_u}/.drush" _mpt_read_here hostmaster.alias.drushrc.php \
    | sed -n "s/.*'uri'[[:space:]]*=>[[:space:]]*'\([^']*\)'.*/\1/p" | head -n1)"
  while IFS= read -r -u 8 _n; do
    [ -n "${_n}" ] || continue
    _vt="$(_mpt_in_real_dir "${_vd}" _mpt_read_here "${_n}")"
    if [ -n "${_pd}" ] && { [ "${_n}" = "${_pd}" ] || [ "${_n}" = "www.${_pd}" ]; } \
      && ! grep -q "proxy_pass" <<< "${_vt}"; then
      continue
    fi
    if grep -q "renamed site: redirect to its new name" <<< "${_vt}" \
      && ! grep -q "proxy_pass" <<< "${_vt}" \
      && ! grep -q "fastcgi_param db_name" <<< "${_vt}" \
      && grep -q "^[[:space:]]*return 301 " <<< "${_vt}"; then
      _r=$(( _r + 1 ))
      continue
    fi
    _t="$(grep -m1 "proxy_pass" <<< "${_vt}" \
      | sed "s|.*proxy_pass[[:space:]]*https\{0,1\}://||; s|;.*||" | tr -d ' ')"
    [ -n "${_t}" ] && echo "tgt ${_t}"
  done 8< <(_mpt_in_real_dir "${_vd}" find . -maxdepth 1 -mindepth 1 -type f \
    ! -name '.*' ! -name 'https.*' 2> /dev/null | sed 's|^\./||' | sort)
  echo "redirects ${_r}"
}

_cmd_reconcile() {
  local _force="${1:-}"
  local _keep="" _perm=NO _undeclared="" _records=0 _record_ips="" _legacy=""
  local _t _rc _why _acct _mode _peers _role _mark _myips _ip _kept="" _cls _rmt _fail=""
  local -a _pips

  # Older tools left their records in the accounts' log/; import what root
  # can vouch for once, before the first root record is read.
  [ -e "${_MIG_ADOPT_STAMP}" ] || _cmd_adopt --once

  _myips="$(_my_ipv4s)"
  if [ -z "${_myips}" ]; then
    # Cannot verify which records are OURS. Refusing to act beats silently
    # degrading into a teardown under a live proxy.
    _msg "reconcile: cannot determine this host's IPv4 addresses; leaving trust as found"
    return 0
  fi

  while IFS= read -r _acct; do
    [ -n "${_acct}" ] || continue
    _t="$(_mig_rec_text "${_acct}")"
    _rc=$?
    [ "${_rc}" -eq 3 ] && continue
    if [ "${_rc}" -ne 0 ]; then
      # Never partially honoured: the account is undeclared (add-only).
      _msg "reconcile: ${_acct}: root record malformed; treated as undeclared"
      _undeclared="${_undeclared} ${_acct}"
      continue
    fi
    _role="$(_mig_txt_get "${_t}" _MIG_ROLE)"
    _peers=""
    # Split on spaces and commas, never expanded as a pathname.
    IFS=' ,' read -r -a _pips <<< "$(_mig_txt_get "${_t}" _MIG_PEER_IPS) $(_mig_txt_get "${_t}" _MIG_PEER_IP)"
    for _ip in "${_pips[@]}"; do
      _is_dotted_quad "${_ip}" && _peers="${_peers} ${_ip}"
    done
    if ! _why="$(_mig_txt_valid "${_t}")"; then
      # A record failing validation is never partially honoured; the account
      # is undeclared and a target record of this host's keeps its peers
      # where they parse.
      _msg "reconcile: ${_acct}: root record invalid (${_why}); treated as undeclared"
      _undeclared="${_undeclared} ${_acct}"
      if [ "${_role}" = "target" ] && _mig_is_mine "${_acct}"; then
        _records=$(( _records + 1 ))
        _record_ips="${_record_ips}${_peers}"
        _keep="${_keep}${_peers}"
      fi
      continue
    fi
    # A record written for another address (the box renumbered) is reported,
    # never acted on.
    if ! _mig_is_mine "${_acct}"; then
      _msg "reconcile: ${_acct}: root record names another host address; not acted on"
      continue
    fi
    # Source-authored records describe OUTBOUND proxying; only target-role
    # records say who this host must keep trusting.
    [ "${_role}" = "target" ] || continue
    _records=$(( _records + 1 ))
    # The source may hold several routable addresses (_MIG_PEER_IPS); the
    # relay's egress interface is not always its primary one, so all of them
    # count -- both as trust candidates and as record-owned for the legacy
    # separation below.
    _record_ips="${_record_ips}${_peers}"
    # An init on this relay's own front ended it: the mode stays for the next
    # cutover to rewire, the trust goes.
    [ -n "$(_mig_txt_get "${_t}" _MIG_RELAY_ENDED)" ] && continue
    _mode="$(_mig_txt_get "${_t}" _MIG_MODE)"
    case "${_mode}" in
      permanent|ha-switch)
        # ha-switch behaves exactly as permanent for trust and teardown; it
        # differs only in the client notification.
        _keep="${_keep}${_peers}"
        _perm=YES
      ;;
      temporary|retired)
        # reconcile runs post-mig (DNS moved) or after a policy change:
        # temporary trust ends here, retired never needed it.
        :
      ;;
    esac
  done < <(_mig_rec_list)

  # Trust entries the records do NOT account for predate the record system
  # (an old --permanent migration from a pre-record source). The records
  # cannot prove anything about them, so they are preserved -- "the union
  # proves nothing needs it" only ever applies to record-owned entries.
  for _ip in $( { cat "${_csf_ctrl}" 2> /dev/null
      _conf_cat "${_realip_ctrl}"; } | sort -u); do
    _is_ipv4_or_cidr "${_ip}" || continue
    echo "${_record_ips}" | tr ' ' '\n' | grep -qxF "${_ip}" && continue
    _legacy="${_legacy} ${_ip}"
  done

  # What older tools left in log/ is never read for an address or a mode. A
  # root-written copy the import refused or that came after it, or one
  # written after the root record (older tools during a fleet roll), freezes
  # teardown for its account. An older copy the import never saw was put
  # back from where the account hid it: absent.
  for _acct in $(_mig_list_accounts); do
    _cls="$(_mig_log_class "${_acct}")"
    if [ -e "$(_mig_rec "${_acct}")" ]; then
      case "${_cls}" in
        legacy-mine\ *)
          _rmt="$(_mig_rec_mtime "${_acct}")" || _rmt=""
          if [[ "${_rmt}" =~ ^[0-9]+$ ]] && [ "${_cls#legacy-mine }" -gt "${_rmt}" ]; then
            _msg "reconcile: ${_acct}: log record written by older tools after the root record; treated as undeclared"
            case " ${_undeclared} " in
              *" ${_acct} "*) ;;
              *) _undeclared="${_undeclared} ${_acct}" ;;
            esac
          fi
        ;;
        account)
          _msg "reconcile: ${_acct}: account-written log record ignored"
        ;;
      esac
      continue
    fi
    case "${_cls}" in
      legacy-mine\ *)
        _msg "reconcile: ${_acct}: unadopted log record (not read); treated as undeclared"
        _undeclared="${_undeclared} ${_acct}"
      ;;
      legacy-stale)
        _msg "reconcile: ${_acct}: an older log copy the import never saw; ignored"
      ;;
      account)
        _msg "reconcile: ${_acct}: account-written log record ignored"
      ;;
    esac
  done

  # Accounts marked proxied with no valid record of their own: never guess.
  # Keep whatever trust exists, leave the permanent marker as found, report.
  for _mark in "${_MIG_REC_DIR}"/.*.migproxy.proxied; do
    [ -e "${_mark}" ] || continue
    _acct="${_mark##*/}"
    _acct="${_acct#.}"
    _acct="${_acct%.migproxy.proxied}"
    _mig_mark "${_acct}" > /dev/null || continue
    [ -d "/data/disk/${_acct}" ] && [ ! -L "/data/disk/${_acct}" ] || continue
    _mig_is_proxied "${_acct}" || continue
    case " ${_undeclared} " in *" ${_acct} "*) continue ;; esac
    if _mig_is_mine "${_acct}" \
      && _mig_valid_mode "$(_mig_rec_get "${_acct}" _MIG_MODE)"; then
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

  # Unquoted on purpose: these are space-separated sets being split into lines.
  # shellcheck disable=SC2086
  _keep="$(printf '%s\n' ${_keep} | sort -u | tr '\n' ' ')"
  # shellcheck disable=SC2086
  _legacy="$(printf '%s\n' ${_legacy} | sort -u | tr '\n' ' ')"

  if [ -n "${_undeclared}" ]; then
    # Undeclared accounts have peers this host cannot know, so existing trust
    # is only ever ADDED to here, never stripped, and the permanent marker is
    # left as found (set only if a declared record demands it).
    for _ip in ${_keep}; do
      _uniq_append "${_csf_ctrl}" "${_ip}"
      _conf_uniq_append "${_realip_ctrl}" "${_ip}" || _fail="${_fail} ${_ip}"
      _csf_add_ip "${_ip}"
      _kept="${_kept} ${_ip}"
    done
    [ "${_CSF_CHANGED}" = "YES" ] && _csf_reload
    [ -n "${_kept}" ] && [ -x "${_realip_tool}" ] && "${_realip_tool}"
    if [ "${_perm}" = "YES" ]; then
      _conf_flag_put "${_perm_flag}" || _fail="${_fail} ${_perm_flag}"
    fi
    _msg "reconcile: UNDECLARED proxied accounts:${_undeclared}"
    _msg "  their trust and the permanent marker are left as found; declare policy on the"
    _msg "  proxying source (xoct proxy-mode <oN> <mode>, then xoct proxy ... --repair) so"
    _msg "  the record propagates here"
    [ -n "${_kept}" ] && _msg "reconcile: declared peers (re)trusted:${_kept}"
    [ -z "${_fail}" ] || _die "reconcile: not recorded in /data/conf:${_fail}"
    return 0
  fi

  if [ -z "${_keep// /}" ] && [ -z "${_legacy// /}" ]; then
    # Records exist, none needs trust, and no pre-record entries survive: the
    # union proves nothing needs the marker either, so clear it even though
    # plain teardown would honour it.
    _conf_drop_file "${_realip_ctrl}" || _fail="${_fail} ${_realip_ctrl}"
    rm -f "${_csf_ctrl}" "${_perm_flag}"
    _csf_strip
    _csf_reload
    [ -x "${_realip_tool}" ] && "${_realip_tool}"
    [ -z "${_fail}" ] || _die "reconcile: could not remove ${_realip_ctrl}"
    _msg "reconcile: no live permanent/ha-switch peers; migration proxy trust torn down"
    return 0
  fi

  # Rewrite both control files to exactly keep + legacy; strip every tagged
  # csf entry and re-add that set (no selective strip exists -- strip-all then
  # re-add exploits the existing idempotency).
  _conf_drop_file "${_realip_ctrl}" \
    || _die "reconcile: could not remove ${_realip_ctrl}; nothing changed"
  rm -f "${_csf_ctrl}"
  _csf_strip
  for _ip in ${_keep} ${_legacy}; do
    _uniq_append "${_csf_ctrl}" "${_ip}"
    _conf_uniq_append "${_realip_ctrl}" "${_ip}" || _fail="${_fail} ${_ip}"
    _csf_add_ip "${_ip}"
    _kept="${_kept} ${_ip}"
  done
  _csf_reload
  [ -x "${_realip_tool}" ] && "${_realip_tool}"
  if [ "${_perm}" = "YES" ]; then
    _conf_flag_put "${_perm_flag}" || _fail="${_fail} ${_perm_flag}"
  elif [ -n "${_legacy// /}" ]; then
    # Pre-record entries may belong to an old --permanent proxy this host
    # cannot re-derive; the marker stays exactly as found.
    :
  else
    rm -f "${_perm_flag}"
  fi
  if [ -n "${_legacy// /}" ]; then
    _msg "reconcile: pre-record trust entries preserved:${_legacy}"
    _msg "  (no policy record accounts for them; the permanent marker is left as found."
    _msg "  Remove them with 'teardown --force' once the old proxies are confirmed gone.)"
  fi
  _msg "reconcile: trusted migration peers now:${_kept}"
  [ -z "${_fail}" ] || _die "reconcile: not recorded in /data/conf:${_fail}"
}

# --- adopt: import what older tools left in log/, once ----------------------

_AD_LIVE=NO
_AD_TODAY=""
_AD_LINES=""
_AD_N=0
_AD_M=0
_AD_K=0
_AD_FAIL=NO
_AD_RECIPS=""
# Per account, for the ALRT on a marker without a record naming its peer:
# a source record adopted, the copy a target record, the remedy of a refused
# record, the restate remedy of a source record adopted with its peer
# account unverified, a marker present or adopted; then the run's ALRT lines.
_AD_REC_SRC=NO
_AD_REC_TGT=NO
_AD_REC_REM=""
_AD_REC_UNW=""
_AD_MARK_OK=NO
_AD_ALRT=""

# One result for the stamp: <acct>|<kind>|<result>|<detail>|<date>, plus
# |<remedy> when there is one (no "|" inside a field, no control byte). The
# remedy is kept so a later 'adopt' can show it: the agent pass that usually
# runs the import discards its report.
# $1 at most 512 bytes, cut at a space and marked, so no stored remedy ends
# in a partial address or name.
_ad_cut() {
  local _v="${1}"
  if [ "${#_v}" -le 512 ]; then
    printf '%s' "${_v}"
    return 0
  fi
  _v="${_v:0:463}"
  _v="${_v% *}"
  printf '%s' "${_v} [cut: the adopt --once output had the full text]"
}
_ad_note() {
  local _a="$1" _k="$2" _r="$3" _d _rem
  # bounded, so the stamp stays within what the root reader takes (64 KiB)
  # and every tool can still read it
  _d="$(_ad_cut "$(_mpt_plain "${4//|/}")")"
  _rem="$(_ad_cut "$(_mpt_plain "${5//|/}")")"
  _AD_LINES="${_AD_LINES}${_a}|${_k}|${_r}|${_d}|${_AD_TODAY}${_rem:+|${_rem}}"$'\n'
  case "${_r}" in
    adopted) _AD_N=$(( _AD_N + 1 )) ;;
    refused) _AD_M=$(( _AD_M + 1 )) ;;
    ignored) _AD_K=$(( _AD_K + 1 )) ;;
  esac
}
_ad_word() {
  if [ "${_AD_LIVE}" = "YES" ]; then
    echo "$1"
  else
    case "$1" in
      ADOPTED) echo "would-adopt" ;;
      REFUSED) echo "would-refuse" ;;
      *) echo "$1" ;;
    esac
  fi
}
_ad_refuse() {
  local _a="$1" _k="$2" _why _rem
  _why="$(_mpt_plain "${3}")"
  _rem="$(_mpt_plain "${4}")"
  [ "${_k}" = "record" ] && _AD_REC_REM="${_rem}"
  _msg "adopt: ${_a}: ${_k} $(_ad_word REFUSED): ${_why}"
  [ -n "${_rem}" ] && _msg "adopt: ${_a}:   remedy: ${_rem}"
  _ad_note "${_a}" "${_k}" refused "${_why}" "${_rem}"
}
# The root record of $1 is a valid source record of this box that names
# its peer, and root itself stated the account there: what the certificate
# mirror and a failback's owner gate read for an account this box proxies.
# Status 2 for such a record imported from an older tool's copy, whose peer
# account is unverified (_mig_rec_adopted_src); 1 for anything else.
_ad_rec_peer_ok() {
  local _t
  _t="$(_mig_rec_text "${1}")" || return 1
  _mig_txt_valid "${_t}" > /dev/null || return 1
  _mig_txt_mine "${_t}" || return 1
  [ "$(_mig_txt_get "${_t}" _MIG_ROLE)" = "source" ] \
    && [ -n "$(_mig_txt_get "${_t}" _MIG_PEER_IP)" ] || return 1
  _mig_rec_adopted_src "${1}" && return 2
  return 0
}
# The ALRT for the account $1, marked proxied with no root record naming its
# peer, with the remedy $2: every consumer of the peer skips or denies it, so
# it must not pass as an ordinary refusal.
_ad_alrt() {
  echo "adopt: ALRT: ${1}: marked proxied, but no root record of this box names its peer:"
  echo "adopt: ALRT: ${1}:   its certificates are not mirrored and a failback prep-target denies it until one is restated"
  echo "adopt: ALRT: ${1}:   remedy: $(_mpt_plain "${2}")"
}
# The restate remedy for the account $1 when no refusal names a better one.
_ad_alrt_rem() {
  local _ra="${1}"
  _mpt_name_ok "${_ra}" || _ra="<oN>"
  printf '%s\n' "xoct proxy ${_ra} <target-ip> [<target-oN>] --repair --proxy-mode=<mode>"
}
# The ALRT for the account $1, whose root source record was imported from an
# older tool's copy, with the restate remedy $2: whatever account it names
# on the peer, the account's own included, came from log/.
_ad_alrt_unw() {
  echo "adopt: ALRT: ${1}: its root source record was imported from an older tool's copy:"
  echo "adopt: ALRT: ${1}:   its peer account is the copy's and is not used until the peer confirms it or root restates the pair"
  echo "adopt: ALRT: ${1}:   remedy: $(_mpt_plain "${2}")"
}
# The same account $1 when it is not proxied: nothing relays, and no
# restate is printed, since it would convert sites served here.
_ad_unw_idle() {
  _msg "adopt: ${1}: its root source record was imported from an older tool's copy and it is not proxied:"
  _msg "adopt: ${1}:   its peer account is used only once the peer confirms it; an 'xoct proxy' run to that peer confirms it or asks root to name it"
}
# The option that restates the deadline $1 for the mode $2 as of the day
# $3: xoct takes only a deadline not yet past, so a past or malformed one
# stays a placeholder; ha-switch takes none.
_ad_dlopt() {
  [ "${2}" = "ha-switch" ] && return 0
  case "${1}" in
    none) printf '%s' " --no-deadline" ;;
    '') ;;
    *)
      if _mig_valid_date "${1}" && [[ ! "${1}" < "${3}" ]]; then
        printf '%s' " --deadline=${1}"
      else
        printf '%s' " --deadline=<new date>"
      fi
    ;;
  esac
  return 0
}
# The restate remedy of an imported source record: the account $1 and the
# peer $2 as shown, the record's mode $3 and the mode $4 to restate. The
# account on the peer is always a placeholder, so no name the copy holds
# reaches a command root may paste. A record with a mode is restated
# keeping it, with its deadline and box scope, as a --proxy-mode= would pin
# the account and a later box sweep skip it. A retired pair needs nothing
# while the peer confirms it; its restatement without a mode keeps it
# retired, as a mode would re-wire the peer's trust and mail the client.
_ad_unw_rem() {
  local _r
  if [ "${3}" = "retired" ]; then
    _r="retired per the copy: nothing to do while the create marker on ${2} confirms the account; else restate it kept retired, nothing converted or mailed: xoct proxy ${1} ${2} <target-oN> --repair (--proxy-mode=<mode> reinstates it: re-wires ${2}'s trust, mails the client)"
  elif [ "${4}" = "${3}" ]; then
    _r="xoct proxy ${1} ${2} <target-oN> --repair (it keeps its mode and scope)"
  else
    _r="xoct proxy ${1} ${2} <target-oN> --repair --proxy-mode=${4}"
  fi
  printf '%s\n' "${_r}; confirm on ${2} which account serves ${1}'s sites (the copy's peer account is not taken)"
}
# The same, from the root record of the account $1 as it is now.
_ad_unw_rem_rec() {
  local _t _ra="${1}" _p _m _rm
  _mpt_name_ok "${_ra}" || _ra="<oN>"
  _t="$(_mig_rec_text "${1}")" || _t=""
  _p="$(_mig_txt_get "${_t}" _MIG_PEER_IP)"
  _mig_peer_ok "${_p}" || _p="<target-ip>"
  _m="$(_mig_txt_get "${_t}" _MIG_MODE)"
  case "${_m}" in
    temporary|permanent|ha-switch) _rm="${_m}" ;;
    *) _rm="<mode>" ;;
  esac
  _ad_unw_rem "${_ra}" "${_p}" "${_m}" "${_rm}"
}

_ad_record() {
  local _a="$1" _raw _cls _b _why _role _peer _poct _mode _dl _hip _ip _seen=""
  local _wit="" _wk="" _rem _tg _n _dlopt="" _rec _st _k _ips _rmode
  local _ra _rpeer _rhip _rips="" _inv="" _nt=0 _live="" _unw="" _urem=""
  local -a _all
  _rec="$(_mig_rec "${_a}")" || return 0
  if [ -e "${_rec}" ] || [ -L "${_rec}" ]; then
    _msg "adopt: ${_a}: record present"
    _ad_note "${_a}" record present "root record"
    return 0
  fi
  _mig_log_class "${_a}" > /dev/null
  _cls="${_MIG_LOG_CLS}"
  _raw="${_MIG_LOG_RAW}"
  case "${_cls}" in
    # An older copy the import never saw is absent, as no copy is.
    none|legacy-stale) return 0 ;;
    info)
      _msg "adopt: ${_a}: record ignored: informational copy without a root record"
      _ad_note "${_a}" record ignored "informational copy"
      return 0
    ;;
    legacy-foreign)
      _msg "adopt: ${_a}: record ignored: travelled copy"
      _ad_note "${_a}" record ignored "travelled copy"
      return 0
    ;;
    legacy-mine\ *) ;;
    *)
      _msg "adopt: ${_a}: record ignored: account-written log record"
      _ad_note "${_a}" record ignored "account-written"
      return 0
    ;;
  esac
  _b="$(printf '%s\n' "${_raw}" | sed 1d | tr -d '\r')"
  _role="$(_mig_txt_get "${_b}" _MIG_ROLE)"
  _hip="$(_mig_txt_get "${_b}" _MIG_HOST_IP)"
  _peer="$(_mig_txt_get "${_b}" _MIG_PEER_IP)"
  _poct="$(_mig_txt_get "${_b}" _MIG_PEER_OCT)"
  _mode="$(_mig_txt_get "${_b}" _MIG_MODE)"
  _dl="$(_mig_txt_get "${_b}" _MIG_DEADLINE)"
  _ips="$(_mig_txt_get "${_b}" _MIG_PEER_IPS)"
  [ "${_role}" = "target" ] && _AD_REC_TGT=YES
  # What the operator restates to replace a refused record; the values are
  # the refused record's own, shown only as the suggestion. A remedy is a
  # command line the operator runs as root and the copy may carry what an
  # account planted, so each value is checked against its own grammar
  # first: one that fails stays a placeholder and is named as invalid. xoct
  # takes only a mode it can set and a deadline not yet past, so anything
  # else stays a placeholder too. The stamp drops a bar, so no placeholder
  # carries one. The account on the other box is always a placeholder:
  # older tools wrote _MIG_PEER_OCT, or the account's own name when it was
  # empty, from what the account left in log/, in either role, so no name a
  # copy holds for it is printed into a command, the account's own included.
  if [ "${_role}" = "target" ]; then
    _rpeer="<source-ip>"
  else
    _rpeer="<target-ip>"
  fi
  _ra="${_a}"
  if ! _mpt_name_ok "${_a}"; then
    _ra="<oN>"
    _inv="${_inv} account"
  fi
  if [ -n "${_peer}" ]; then
    if _mig_peer_ok "${_peer}"; then
      _rpeer="${_peer}"
    else
      _inv="${_inv} _MIG_PEER_IP"
    fi
  fi
  _rhip="<this box's address>"
  _mig_quad "${_hip}" && _rhip="${_hip}"
  IFS=' ,' read -r -a _all <<< "${_ips}"
  for _ip in "${_all[@]}"; do
    [ -n "${_ip}" ] && [ "${_ip}" != "${_peer}" ] || continue
    if ! _mig_peer_ok "${_ip}"; then
      case " ${_inv} " in
        *" _MIG_PEER_IPS "*) ;;
        *) _inv="${_inv} _MIG_PEER_IPS" ;;
      esac
      continue
    fi
    case " ${_rips} " in
      *" ${_ip} "*) ;;
      *) _rips="${_rips} ${_ip}" ;;
    esac
  done
  case "${_mode}" in
    temporary|permanent|ha-switch) _rmode="${_mode}" ;;
    *) _rmode="<mode>" ;;
  esac
  _dlopt="$(_ad_dlopt "${_dl}" "${_rmode}" "${_AD_TODAY}")"
  if [ "${_role}" = "target" ]; then
    # Run on the source, naming this box's account: without it the
    # restatement pushes to the same account name here.
    if [ "${_mode}" = "retired" ]; then
      # The source's own record already reads retired, so its retire is a
      # no-op that pushes nothing: no re-run there replaces this copy.
      _rem="nothing to re-push: the source retired this pair; once its proxy is gone: migration_proxy_trust.sh untrust ${_rpeer}${_rips}"
    else
      _rem="on the source box (${_rpeer}): xoct proxy-mode <source-oN> ${_rmode}; if the source reports no root record for the account, restate it with xoct proxy <source-oN> ${_rhip} ${_ra} --repair --proxy-mode=${_rmode}; confirm on ${_rpeer} which of its accounts relays to ${_ra} here (the copy's peer account is not taken)"
    fi
  elif [ -n "${_peer}" ]; then
    # Adopted, the record keeps the copy's peer account, unverified: every
    # tool that needs it confirms it on the peer first, or refuses.
    _unw=YES
    _urem="$(_ad_unw_rem "${_ra}" "${_rpeer}" "${_mode}" "${_rmode}")"
    if [ "${_mode}" = "retired" ]; then
      # Retired and mailed before the upgrade: a restatement would re-wire
      # the peer's trust and mail the client a change, a retire after it a
      # second notice.
      _rem="already retired per the copy: nothing to restate (a restatement re-wires ${_rpeer}'s trust and mails the client); if ${_rpeer} still trusts this box, release it there: migration_proxy_trust.sh untrust ${_rhip} [<this box's other addresses>]"
    else
      # A refusal leaves no root record, so its restatement declares the
      # mode on the run (xoct refuses an unadopted copy's pair without
      # one); only an adopted record has a mode and scope to keep.
      _rem="xoct proxy ${_ra} ${_rpeer} <target-oN> --repair --proxy-mode=${_rmode}${_dlopt}; confirm on ${_rpeer} which account serves ${_ra}'s sites (the copy's peer account is not taken)"
    fi
  else
    _rem="xoct proxy-mode ${_ra} ${_rmode}${_dlopt}"
  fi
  if [ -n "${_inv}" ]; then
    _rem="${_rem} (invalid, left as a placeholder:${_inv})"
    [ -n "${_urem}" ] && _urem="${_urem} (invalid, left as a placeholder:${_inv})"
  fi
  if ! printf '%s\n' "${_b}" | _mig_grammar_ok; then
    _ad_refuse "${_a}" record "malformed log record" "${_rem}"
    return 0
  fi
  _k="$(_mpt_unknown_key "${_b}")"
  if [ -n "${_k}" ]; then
    _ad_refuse "${_a}" record "unknown key ${_k}" "${_rem}"
    return 0
  fi
  if ! _why="$(_mig_txt_valid "${_b}")"; then
    _ad_refuse "${_a}" record "${_why}" "${_rem}"
    return 0
  fi
  # The record grammar takes any account-shaped peer name; one that reads as
  # an option or starts with a dot names no account, and adopted it would
  # reach the root record xoct reads.
  if [ -n "${_poct}" ] && ! _mpt_name_ok "${_poct}"; then
    _ad_refuse "${_a}" record "invalid _MIG_PEER_OCT (not an account name)" "${_rem}"
    return 0
  fi
  # The bytes judged here are the ones classified: written for this box.
  if ! _mig_txt_mine "${_b}"; then
    _ad_refuse "${_a}" record "written for another address" "${_rem}"
    return 0
  fi
  if [ "${_role}" = "target" ]; then
    # Every address must be witnessed: adopting a subset would silently
    # tear down trust for the rest. Split without pathname expansion.
    IFS=' ,' read -r -a _all <<< "${_peer} ${_ips}"
    for _ip in "${_all[@]}"; do
      [ -n "${_ip}" ] || continue
      case " ${_seen} " in *" ${_ip} "*) continue ;; esac
      _seen="${_seen} ${_ip}"
      if ! _mig_witnessed "${_ip}"; then
        _ad_refuse "${_a}" record "unwitnessed ${_ip}" "${_rem}"
        return 0
      fi
      _n="$(_mpt_witness_kind "${_ip}")"
      _wit="${_wit}${_wit:+, }${_n} ${_ip}"
      case "+${_wk}+" in
        *"+${_n}+"*) ;;
        *) _wk="${_wk}${_wk:++}${_n}" ;;
      esac
    done
    _AD_RECIPS="${_AD_RECIPS}${_seen}"
  elif [ -z "${_peer}" ]; then
    # A pin set before any proxy existed names no pair, so no root-only
    # migration state can vouch for it: the operator declares it again.
    if [ -n "${_ips// /}" ]; then
      _ad_refuse "${_a}" record "source record names _MIG_PEER_IPS without _MIG_PEER_IP" "${_rem}"
    else
      _ad_refuse "${_a}" record "source record names no peer, so no root migration state names a pair" "${_rem}"
    fi
    return 0
  else
    if ! ssh-keygen -F "${_peer}" -f "${_MIG_KNOWN_HOSTS}" > /dev/null 2>&1; then
      _ad_refuse "${_a}" record "peer ${_peer} not in root known_hosts" "${_rem}"
      return 0
    fi
    while IFS=' ' read -r _tg _n; do
      [ "${_tg}" = "tgt" ] || continue
      if [ "${_n}" != "${_peer}" ]; then
        _ad_refuse "${_a}" record "vhost target $(_mig_shown "${_n}") is not the record peer ${_peer}" "${_rem}"
        return 0
      fi
      _nt=$(( _nt + 1 ))
    done < <(_mig_vhost_targets "${_a}")
    # known_hosts and the vhosts can both be fed from the account's side:
    # the pair must also be named in root's own migration state.
    if ! _st="$(_mpt_pair_state "${_a}" "${_peer}")"; then
      _ad_refuse "${_a}" record "no root migration state names ${_a} and ${_peer} as a pair" "${_rem}"
      return 0
    fi
    # A box the peer itself migrated into (a promoted failback target, or a
    # pair that ran both ways) keeps its old source record, set aside at
    # promotion, and the state that names it: that record may be superseded.
    # It is not while the account still relays there: a promotion set the
    # record aside and removed log/proxied.pid together, so that file still
    # reading as root's COMPLETE marker, with live proxy vhosts that all
    # forward to the peer, is a relay in service. Otherwise, taken over, the
    # account has no root record: it counts as undeclared (the trust here is
    # only added to, a live cutover refuses it) until its mode is declared.
    if _mpt_inbound_witnessed "${_peer}"; then
      if [ "${_nt}" -gt 0 ] && _ad_pid_proof "${_a}" > /dev/null; then
        _live=YES
        _msg "adopt: ${_a}: peer ${_peer} also migrated into this box ($(_mpt_witness_kind "${_peer}")), but the account still relays there: log/proxied.pid reads COMPLETE and every live proxy vhost (${_nt}) forwards to it"
      else
        if [ "${_nt}" -gt 0 ]; then
          _n="log/proxied.pid is no root COMPLETE marker"
        else
          _n="no live proxy vhost"
        fi
        _ad_refuse "${_a}" record "peer ${_peer} also migrated into this box ($(_mpt_witness_kind "${_peer}")) and ${_n}; the record may be superseded" "only if ${_ra} still relays to ${_rpeer} (its vhosts proxy there): ${_rem}; if this box took it over, nothing to restate; declare its mode with xoct proxy-mode ${_ra} <mode>; until then it counts as undeclared"
        return 0
      fi
    fi
    if [ -e "${_rec}.superseded-by-promotion" ] || [ -L "${_rec}.superseded-by-promotion" ]; then
      _ad_refuse "${_a}" record "a promotion of this box superseded its source record" "nothing to restate; declare its mode with xoct proxy-mode ${_ra} <mode>; until then it counts as undeclared"
      return 0
    fi
    _wk="known_hosts+vhosts+${_st}${_live:++live-relay}"
    _wit="${_wk} ${_peer}"
  fi
  if [ "${_AD_LIVE}" = "YES" ]; then
    _ips="$(printf '%s' "${_ips}" | tr ',' ' ' | tr -s ' ')"
    _ips="${_ips# }"
    _ips="${_ips% }"
    if ! {
      printf '%s\n' "${_MIG_REC_HDR}" \
        "_MIG_ROLE=${_role}" \
        "_MIG_HOST_IP=${_hip}" \
        "_MIG_PEER_IP=${_peer}" \
        "_MIG_PEER_OCT=${_poct}" \
        "_MIG_MODE=${_mode}" \
        "_MIG_SCOPE=$(_mig_txt_get "${_b}" _MIG_SCOPE)" \
        "_MIG_DEADLINE=${_dl}"
      _n="$(_mig_txt_get "${_b}" _MIG_RETIRE_DATE)"
      [ -n "${_n}" ] && printf '%s\n' "_MIG_RETIRE_DATE=${_n}"
      [ -n "${_ips}" ] && printf '%s\n' "_MIG_PEER_IPS=${_ips}"
      printf '%s\n' "_MIG_STAMPED=$(_mig_txt_get "${_b}" _MIG_STAMPED)" \
        "_MIG_ADOPTED=${_AD_TODAY}"
    } | _mig_rec_put "${_a}"; then
      _msg "adopt: ${_a}: record NOT written: the root record could not be put"
      _AD_FAIL=YES
      return 0
    fi
  fi
  _msg "adopt: ${_a}: record ${_role} $(_ad_word ADOPTED) (witness: ${_wit})"
  if [ -n "${_unw}" ]; then
    # The mode stays declared; the account named on the peer is the copy's.
    # The stamp keeps the remedy and the run's tail raises the ALRT.
    _AD_REC_UNW="$(_mpt_plain "${_urem}")"
    _msg "adopt: ${_a}:   its peer account is the copy's and is not used until the peer confirms it or root restates the pair"
    _msg "adopt: ${_a}:   remedy: ${_AD_REC_UNW}"
  fi
  _ad_note "${_a}" record adopted "${_role} witness=${_wk}${_unw:+ peer-account-unverified}" "${_unw:+${_urem}}"
  [ "${_role}" = "source" ] && _AD_REC_SRC=YES
  return 0
}

# Whether log/proxied.pid of the account $1 is the marker older tools wrote:
# root's, at most 64 bytes, its first line COMPLETE, its mtime no later than
# a day ahead. Prints that mtime. Status 3 absent, 4 not root-written, 5
# larger than a marker, 6 an import freeze, 7 not COMPLETE, 8 not a past
# date. The one proof both the marker and a live relay's record rest on.
_ad_pid_proof() {
  local _raw _rc _b _l1 _at
  # The x keeps trailing newlines: the size is the file's own.
  _raw="$(_mig_hread "/data/disk/${1}/log" proxied.pid root && printf x)"
  _rc=$?
  [ "${_rc}" -eq 3 ] && return 3
  [ "${_rc}" -eq 0 ] || return 4
  _raw="${_raw%x}"
  _at="${_raw%%$'\n'*}"
  _b="${_raw#*$'\n'}"
  _l1="${_b%%$'\n'*}"
  [ "$(printf '%s' "${_b}" | LC_ALL=C wc -c | tr -d ' ')" -le 64 ] || return 5
  [ "${_l1}" != "A2B-IMPORT-FREEZE" ] || return 6
  [ "${_l1}" = "COMPLETE" ] || return 7
  [[ "${_at}" =~ ^[0-9]{9,11}$ ]] || return 8
  [ "${_at}" -le "$(( $(date +%s) + 86400 ))" ] || return 8
  printf '%s\n' "${_at}"
}

_ad_marker() {
  local _a="$1" _rc _at _rem _ra="$1"
  _mpt_name_ok "${_a}" || _ra="<oN>"
  _rem="xoct proxy ${_ra} <target-ip> [<target-oN>] --repair"
  if _mig_is_proxied "${_a}"; then
    _AD_MARK_OK=YES
    _msg "adopt: ${_a}: marker present"
    _ad_note "${_a}" marker present "root marker"
    return 0
  fi
  _at="$(_ad_pid_proof "${_a}")"
  _rc=$?
  case "${_rc}" in
    0) ;;
    3) return 0 ;;
    4) _ad_refuse "${_a}" marker "log/proxied.pid not root-written" "${_rem}"; return 0 ;;
    5) _ad_refuse "${_a}" marker "log/proxied.pid larger than a marker" "${_rem}"; return 0 ;;
    6) _ad_refuse "${_a}" marker "not a proxy marker (import freeze)" ""; return 0 ;;
    7) _ad_refuse "${_a}" marker "log/proxied.pid does not read COMPLETE" "${_rem}"; return 0 ;;
    *) _ad_refuse "${_a}" marker "log/proxied.pid time is not a past date" "${_rem}"; return 0 ;;
  esac
  # Root wrote that file and an account cannot set a root file's times, so
  # its mtime carries how long the account has been proxied.
  if [ "${_AD_LIVE}" = "YES" ] && ! _mig_mark_put "${_a}" adopt "${_at}"; then
    _msg "adopt: ${_a}: marker NOT written: the root marker could not be put"
    _AD_FAIL=YES
    return 0
  fi
  _AD_MARK_OK=YES
  _msg "adopt: ${_a}: marker $(_ad_word ADOPTED) (proxied since $(date -u -d "@${_at}" '+%Y-%m-%d'))"
  _ad_note "${_a}" marker adopted "log/proxied.pid"
}

# The relay list entries no root target record of this box accounts for,
# once each: pre-record peers, or addresses an older release took from an
# account's log/ copy. Reconcile keeps them; this only names them.
_ad_unaccounted() {
  local _acct _t _ip _acc="${_AD_RECIPS}"
  local -a _all
  while IFS= read -r _acct; do
    [ -n "${_acct}" ] || continue
    _t="$(_mig_rec_text "${_acct}")" || continue
    [ "$(_mig_txt_get "${_t}" _MIG_ROLE)" = "target" ] || continue
    _mig_txt_mine "${_t}" || continue
    IFS=' ,' read -r -a _all <<< "$(_mig_txt_get "${_t}" _MIG_PEER_IP) $(_mig_txt_get "${_t}" _MIG_PEER_IPS)"
    _acc="${_acc} ${_all[*]}"
  done < <(_mig_rec_list 2> /dev/null)
  while IFS= read -r _ip; do
    _is_ipv4_or_cidr "${_ip}" || continue
    case " ${_acc} " in *" ${_ip} "*) continue ;; esac
    _msg "adopt: trusted peer ${_ip} (${_csf_ctrl}): no root record accounts for it; reconcile keeps it"
    _msg "adopt:   remedy, once it is confirmed stale: migration_proxy_trust.sh untrust ${_ip}"
  done < <(sort -u "${_csf_ctrl}" 2> /dev/null)
}

# One pass over every account: the record, then the marker. $1=YES writes
# the root files and the stamp; anything else only reports.
_ad_run() {
  local _acct _rem _pk
  _AD_LIVE="$1"
  _AD_LINES=""; _AD_N=0; _AD_M=0; _AD_K=0; _AD_FAIL=NO; _AD_RECIPS=""
  _AD_ALRT=""
  _AD_TODAY="$(date -u '+%Y-%m-%d')"
  if [ -z "$(_my_ipv4s)" ]; then
    _msg "adopt: cannot determine this host's IPv4 addresses; nothing imported, no stamp"
    return 1
  fi
  while IFS= read -r _acct; do
    [ -n "${_acct}" ] || continue
    _AD_REC_SRC=NO; _AD_REC_TGT=NO; _AD_REC_REM=""; _AD_REC_UNW=""; _AD_MARK_OK=NO
    _ad_record "${_acct}"
    _ad_marker "${_acct}"
    _ad_rec_peer_ok "${_acct}"
    _pk=$?
    # A source record adopted now, or by an earlier run that wrote no
    # stamp, keeps the copy's peer account: proxied or not, every tool that
    # needs it confirms it on the peer first or refuses. Only a proxied
    # account gets the restate as an ALRT: on one served here it would
    # convert the sites, and the next proxy run states the account anyway.
    if [ -n "${_AD_REC_UNW}" ] || [ "${_pk}" -eq 2 ]; then
      _rem="${_AD_REC_UNW}"
      [ -n "${_rem}" ] || _rem="$(_ad_unw_rem_rec "${_acct}")"
      if [ "${_AD_MARK_OK}" = "YES" ]; then
        _AD_ALRT="${_AD_ALRT}$(_ad_alrt_unw "${_acct}" "${_rem}")"$'\n'
      else
        _ad_unw_idle "${_acct}"
      fi
    # A marker taken while the record is not leaves the account proxied with
    # no peer anyone may read. A refused source record's remedy restates it;
    # a target record's names the other box, so the generic one is shown.
    elif [ "${_AD_MARK_OK}" = "YES" ] && [ "${_AD_REC_SRC}" != "YES" ] \
      && [ "${_pk}" -ne 0 ]; then
      _rem="${_AD_REC_REM}"
      if [ -z "${_rem}" ] || [ "${_AD_REC_TGT}" = "YES" ]; then
        _rem="$(_ad_alrt_rem "${_acct}")"
      fi
      _AD_ALRT="${_AD_ALRT}$(_ad_alrt "${_acct}" "${_rem}")"$'\n'
    fi
  done < <(_mig_list_accounts)
  _ad_unaccounted
  # Last before the summary, so the run's tail shows them.
  [ -n "${_AD_ALRT}" ] && printf '%s' "${_AD_ALRT}"
  if [ "${_AD_LIVE}" != "YES" ]; then
    _msg "adopt: report only: ${_AD_N} would-adopt, ${_AD_M} would-refuse, ${_AD_K} ignored; nothing written (run 'adopt --once')"
    return 0
  fi
  if [ "${_AD_FAIL}" = "YES" ]; then
    _msg "adopt: a root write failed; no stamp, so a re-run retries (what was written reads as present)"
    return 1
  fi
  # The stamp sits beside the records, written the way they are.
  if ! {
    printf '%s\n' "# BOA migration record adoption $(date -u '+%Y-%m-%dT%H:%M:%SZ'). Nothing is imported after this file exists."
    printf '%s' "${_AD_LINES}"
  } | ( _MIG_REC_DIR="${_MIG_ADOPT_STAMP%/*}"; _mig_root_put "${_MIG_ADOPT_STAMP##*/}" ); then
    _msg "adopt: stamp ${_MIG_ADOPT_STAMP} not written; a re-run retries"
    return 1
  fi
  _msg "adopt: done: ${_AD_N} adopted, ${_AD_M} refused, ${_AD_K} ignored; stamp ${_MIG_ADOPT_STAMP}"
  return 0
}

# The stamp's date, from its first line.
_ad_stamp_date() {
  _mig_hread "${_MIG_ADOPT_STAMP%/*}" "${_MIG_ADOPT_STAMP##*/}" root 2> /dev/null \
    | sed -n '2s/^# BOA migration record adoption \([0-9T:Z-]*\)\..*/\1/p'
}
# What the import found, one report line per stamp line, with the remedy
# the stamp kept, without control or 8-bit bytes whatever the stamp holds.
_ad_stamp_report() {
  local _a _k _r _d _dt _rem
  while IFS='|' read -r _a _k _r _d _dt _rem; do
    [ -n "${_k}" ] || continue
    _msg "adopt: ${_a}: ${_k} ${_r}: ${_d} (${_dt})"
    [ -n "${_rem}" ] && _msg "adopt: ${_a}:   remedy: ${_rem}"
  done < <(_mig_hread "${_MIG_ADOPT_STAMP%/*}" "${_MIG_ADOPT_STAMP##*/}" root 2> /dev/null \
    | sed '1,2d' | LC_ALL=C tr -d '\000-\011\013-\037\177-\377')
}
# The ALRT of the import, from root's files as they are now: every account
# whose root source record is still the imported one, its peer account
# unverified, and every account root marks proxied whose root record names
# no peer. The import's own report is often discarded, and a record restated
# since clears it.
_ad_proxied_unrecorded() {
  local _acct _pk
  while IFS= read -r _acct; do
    [ -n "${_acct}" ] || continue
    _ad_rec_peer_ok "${_acct}"
    _pk=$?
    if [ "${_pk}" -eq 2 ]; then
      if _mig_is_proxied "${_acct}"; then
        _ad_alrt_unw "${_acct}" "$(_ad_unw_rem_rec "${_acct}")"
      else
        _ad_unw_idle "${_acct}"
      fi
      continue
    fi
    [ "${_pk}" -eq 0 ] && continue
    _mig_is_proxied "${_acct}" || continue
    _ad_alrt "${_acct}" "$(_ad_alrt_rem "${_acct}")"
  done < <(_mig_list_accounts)
}

# The import itself, under the adoption lock. A subshell, so the lock's
# descriptor never outlives it (a daemon reloaded later must not inherit it).
_ad_once_locked() (
  exec 7> "${_MIG_ADOPT_LOCK}" || exit 1
  if ! flock -w 60 7; then
    _msg "adopt: another adoption holds ${_MIG_ADOPT_LOCK}; nothing imported, no stamp"
    exit 1
  fi
  if [ -e "${_MIG_ADOPT_STAMP}" ]; then
    _msg "adopt: already done $(_ad_stamp_date); nothing is imported again"
    exit 0
  fi
  _ad_run YES
)

_cmd_adopt() {
  case "${1:-}" in
    --once)
      if [ -e "${_MIG_ADOPT_STAMP}" ]; then
        _msg "adopt: already done $(_ad_stamp_date); nothing is imported again"
        return 0
      fi
      _ad_once_locked
      return $?
    ;;
    '') ;;
    *) _die "adopt: unknown option ${1}" ;;
  esac
  if [ -e "${_MIG_ADOPT_STAMP}" ]; then
    _msg "adopt: already done $(_ad_stamp_date); nothing is imported again. What it found:"
    _ad_stamp_report
    _ad_unaccounted
    _ad_proxied_unrecorded
    return 0
  fi
  _ad_run NO
}

# --- trust no record needs any more -------------------------------------------
#
# Serving trust is the relay list, the realip file and the csf "migration proxy"
# lines; reach is a peer's tagged root key and its csf "xmass migration source"
# and "inbound-proxy" lines; the witness is its line in the address list. The
# limits hold for both verbs below: a record is never deleted, absence of a
# record never removes reach (a mirror holds carried reach with no record, and
# a box just promoted needs it for the retarget), the addresses of this box's
# own pair are never touched, and "xmass migration target" and "Legacy Proxy"
# lines are not this tool's.

# Fills the address lists of the root target records: live (a relay still on,
# or a record for another address, which nothing here may judge), held (retired
# inside its promised date) and over. Status 1, and nothing is decided, on a
# record that cannot be read.
_MPT_LIVE=" "
_MPT_HELD=" "
_MPT_OVER=" "
_mpt_scan_records() {
  local _acct _t _rc _ip _b
  local -a _pips
  _MPT_LIVE=" "
  _MPT_HELD=" "
  _MPT_OVER=" "
  while IFS= read -r _acct; do
    [ -n "${_acct}" ] || continue
    _t="$(_mig_rec_text "${_acct}")"
    _rc=$?
    [ "${_rc}" -eq 3 ] && continue
    [ "${_rc}" -eq 0 ] || return 1
    [ "$(_mig_txt_get "${_t}" _MIG_ROLE)" = "target" ] || continue
    if ! _mig_txt_mine "${_t}"; then
      _b=_MPT_LIVE
    elif _mig_txt_relay_over "${_t}"; then
      _b=_MPT_OVER
    elif [ "$(_mig_txt_get "${_t}" _MIG_MODE)" = "retired" ]; then
      _b=_MPT_HELD
    else
      _b=_MPT_LIVE
    fi
    IFS=' ,' read -r -a _pips <<< "$(_mig_txt_get "${_t}" _MIG_PEER_IP) $(_mig_txt_get "${_t}" _MIG_PEER_IPS)"
    for _ip in "${_pips[@]}"; do
      _is_dotted_quad "${_ip}" || continue
      printf -v "${_b}" '%s%s ' "${!_b}" "${_ip}"
    done
  done < <(_mig_rec_list 2> /dev/null)
  return 0
}
_mpt_in() {
  case "${2}" in
    *" ${1} "*) return 0 ;;
  esac
  return 1
}
# The peer $1 is this box's xmass partner: the active it stands by for, a box an
# xmass verb ran toward from here, or the target in its xmass state.
_mpt_xmass_pair() {
  local _t
  _mig_quad "${1}" || return 1
  if [ -e /root/.standby.cnf ] \
    && sed -n 's/^xmass replication target of \([0-9.]*\) since .*/\1/p' /root/.standby.cnf \
      | grep -qxF -- "${1}"; then
    return 0
  fi
  _mig_hread "${_MIG_STATE_DIR}" "xmass.migrate.${1}.state" root > /dev/null && return 0
  _t="$(_mig_hread "${_MIG_XMASS_STATE%/*}" "${_MIG_XMASS_STATE##*/}" root)" || return 1
  printf '%s\n' "${_t}" | sed 1d | tr -d '\r' | grep -qxF -- "_XMASS_TARGET_IP=${1}"
}
# $1 and every address a root record names beside it: a record's whole address
# set is one peer, whose key is tagged with one of them.
_mpt_peer_set() {
  local _a _t _s=" ${1} " _ip
  local -a _pips
  while IFS= read -r _a; do
    [ -n "${_a}" ] || continue
    _t="$(_mig_rec_text "${_a}")" || continue
    IFS=' ,' read -r -a _pips <<< "$(_mig_txt_get "${_t}" _MIG_PEER_IP) $(_mig_txt_get "${_t}" _MIG_PEER_IPS)"
    _mpt_in "${1}" " ${_pips[*]} " || continue
    for _ip in "${_pips[@]}"; do
      _is_dotted_quad "${_ip}" || continue
      _mpt_in "${_ip}" "${_s}" || _s="${_s}${_ip} "
    done
  done < <(_mig_rec_list 2> /dev/null)
  printf '%s\n' "${_s}"
}
# That, or the peer a source record of this box names, by any of its addresses.
_mpt_pair_named() {
  local _a _t _ip _set
  _set="$(_mpt_peer_set "${1}")"
  for _ip in ${_set}; do
    _mpt_xmass_pair "${_ip}" && return 0
  done
  while IFS= read -r _a; do
    [ -n "${_a}" ] || continue
    _t="$(_mig_rec_text "${_a}")" || continue
    [ "$(_mig_txt_get "${_t}" _MIG_ROLE)" = "source" ] || continue
    _mpt_in "$(_mig_txt_get "${_t}" _MIG_PEER_IP)" "${_set}" && return 0
  done < <(_mig_rec_list 2> /dev/null)
  return 1
}
# The day root last gave the address $1 its reach, from its line in the reach
# file. With $2 = grant, a line the first prune seeded is no grant and gives
# nothing.
_mpt_reach_day() {
  local _d
  _d="$(awk -v a="${1}" -v g="${2:-}" '$1 == a && (g != "grant" || NF == 2) { d = $2 } END { print d }' \
    "${_MPT_REACH_DAYS}" 2> /dev/null)"
  _mig_valid_date "${_d}" && printf '%s' "${_d}"
}
# Root gave the peer $1 its reach for something newer than its relays here that
# are over: a new move's key or a carry for a live front, which no ended relay can
# take back. Any day on or after the latest of those relays' ends is newer (a
# retired relay ends, for this, on the day it was retired, so a key given inside
# its promised window stays). A real grant after the day the latest of them began
# (_MIG_BEGAN, kept from the first push) is newer too: another move's key given
# before the relay was restated or retargeted. A seeded day says when reach was
# found, never when it was given, so only the end counts it. Read per address,
# for the whole of the peer's set; a peer none of whose addresses has a day was
# given its reach by tools that kept none, so nothing says how old it is and it
# stays.
_mpt_granted_since() {
  local _a _t _d _e _began="" _over="" _ip _g _known=""
  while IFS= read -r _a; do
    [ -n "${_a}" ] || continue
    _t="$(_mig_rec_text "${_a}")" || continue
    [ "$(_mig_txt_get "${_t}" _MIG_ROLE)" = "target" ] || continue
    _mpt_in "${1}" " $(_mig_txt_get "${_t}" _MIG_PEER_IP) $(_mig_txt_get "${_t}" _MIG_PEER_IPS | tr ',' ' ') " || continue
    _mig_txt_relay_over "${_t}" || continue
    _d="$(_mig_txt_get "${_t}" _MIG_BEGAN)"
    _mig_valid_date "${_d}" && [[ "${_d}" > "${_began}" ]] && _began="${_d}"
    _e="$(_mig_txt_get "${_t}" _MIG_RELAY_ENDED)"
    [ -n "${_e}" ] || _e="$(_mig_txt_get "${_t}" _MIG_STAMPED)"
    _mig_valid_date "${_e}" || _e="$(_mig_txt_get "${_t}" _MIG_RETIRE_DATE)"
    _mig_valid_date "${_e}" && [[ "${_e}" > "${_over}" ]] && _over="${_e}"
  done < <(_mig_rec_list 2> /dev/null)
  [ -n "${_began}${_over}" ] || return 1
  for _ip in $(_mpt_peer_set "${1}"); do
    _d="$(_mpt_reach_day "${_ip}")" || continue
    _known=YES
    [ -n "${_over}" ] && ! [[ "${_d}" < "${_over}" ]] && return 0
    _g="$(_mpt_reach_day "${_ip}" grant)" || continue
    [ -n "${_began}" ] && [[ "${_g}" > "${_began}" ]] && return 0
  done
  [ -z "${_known}" ]
}
# Cron discards what a verb prints: each removal also goes in a log.
_MPT_TRUST_LOG="/var/log/boa/migproxy-trust.log"
# One line per peer, "<address> <day>": when root last gave it its reach. The
# first prune on a box writes "<address> <day> seed" for the reach it finds there.
_MPT_REACH_DAYS="/root/.migration.peer.reach"
# One line per address, "<address> <day>": a target's pre-mig writes it for the
# source it lets in, and that box's post-mig removes the file. While a line names
# a peer, a move from it into this box is under way, and its reach stays: no day
# tells that move's key from one a relay that is over was given. The first prune
# or release on a box writes "<address> <day> seed" for the reach older tools
# gave, whose pre-mig wrote no line: such a move may be under way too. A seeded
# line counts for 30 days.
_MPT_PENDING="/root/.migration.peer.pending"
_mpt_pending() {
  local _ip _old
  _old="$(date -u -d '30 days ago' '+%Y-%m-%d' 2> /dev/null)"
  for _ip in $(_mpt_peer_set "${1}"); do
    awk -v a="${_ip}" -v o="${_old}" '$1 == a && (NF == 2 || ($3 == "seed" && $2 >= o)) { f = 1 } END { exit !f }' \
      "${_MPT_PENDING}" 2> /dev/null && return 0
  done
  return 1
}
_mpt_note() {
  _msg "${1}"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${1}" >> "${_MPT_TRUST_LOG}" 2> /dev/null
  return 0
}
# Removes the peer $1's reach, exact lines only. Status 1 when a file could not
# be rewritten, which is left as found. Sets _CSF_CHANGED.
_mpt_reach_drop() {
  local _ip="${1}" _rx _l _f _rc _n=0
  _rx="${_ip//./\\.}"
  while IFS= read -r _l; do
    [ -n "${_l}" ] || continue
    _drop_line "${_MIG_AUTH_KEYS}" "${_l}"
    if [ "$?" -eq 2 ]; then
      _mpt_note "${_ip}: could not rewrite ${_MIG_AUTH_KEYS}; left as found"
      return 1
    fi
    _n=$(( _n + 1 ))
  done < <(grep -vE '^[[:space:]]*#' "${_MIG_AUTH_KEYS}" 2> /dev/null \
    | grep -E -- " # (xmass|xoct|xcopy) migration source ${_rx}[[:space:]]*\$")
  if _csf_present; then
    for _f in "${_csf_allow}" "${_csf_ignore}"; do
      for _l in "${_ip} # xmass migration source" "${_ip} # xmass migration inbound-proxy"; do
        _drop_line "${_f}" "${_l}"
        _rc=$?
        if [ "${_rc}" -eq 2 ]; then
          _mpt_note "${_ip}: could not rewrite ${_f}; left as found"
          return 1
        fi
        if [ "${_rc}" -eq 0 ]; then
          _CSF_CHANGED="YES"
          _n=$(( _n + 1 ))
        fi
      done
    done
  fi
  [ "${_n}" -gt 0 ] && _mpt_note "${_ip}: reach removed (${_n} line(s))"
  if [ -f "${_MPT_REACH_DAYS}" ]; then
    _l="$(sed -n "/^${_rx} /p" "${_MPT_REACH_DAYS}")"
    [ -z "${_l}" ] || _drop_line "${_MPT_REACH_DAYS}" "${_l}"
  fi
  return 0
}
_mpt_relay_listed() {
  { cat "${_csf_ctrl}" 2> /dev/null; _conf_cat "${_realip_ctrl}"; } | grep -qxF -- "${1}"
}
# An account root cannot speak for yet: a copy older tools left that has no root
# record or is newer than it, or a marker with no record.
_mpt_any_undeclared() {
  local _a _cls _rmt
  while IFS= read -r _a; do
    [ -n "${_a}" ] || continue
    _cls="$(_mig_log_class "${_a}")"
    if [ -e "$(_mig_rec "${_a}")" ]; then
      case "${_cls}" in
        legacy-mine\ *)
          _rmt="$(_mig_rec_mtime "${_a}")" || return 0
          [ "${_cls#legacy-mine }" -gt "${_rmt}" ] && return 0
        ;;
      esac
    else
      case "${_cls}" in
        legacy-mine\ *) return 0 ;;
      esac
      _mig_is_proxied "${_a}" && return 0
    fi
  done < <(_mig_list_accounts)
  return 1
}

# A front that moved away or ended asks this box to stop trusting it: its serving
# trust and witness go, a live record's address stays. Its reach goes too with
# --over, or with --to when <ip> is no partner of this box: there the front comes
# back at a failback and needs it. With --since=<day>, the day the relay began, a
# reach root gave later stays: another move from the same box needs it. A peer
# a move into this box is under way from (the pending file) keeps its reach in
# every case. Status 0 released, 3 kept (a live record names every address), 4
# refused: nothing changed and the cause is printed.
_cmd_release() {
  local _a _to="" _over="" _since="" _ip _g _k _reach=NO
  local -a _ips=() _drop=()
  for _a in "$@"; do
    case "${_a}" in
      --to=*) _to="${_a#--to=}" ;;
      --over) _over=YES ;;
      --since=*)
        _since="${_a#--since=}"
        _mig_valid_date "${_since}" || _die "release: not a day: ${_since}"
      ;;
      --*) _die "unknown option ${_a}" ;;
      *)
        _is_dotted_quad "${_a}" || _die "not a peer address: ${_a}"
        _ips+=("${_a}")
      ;;
    esac
  done
  [ "${#_ips[@]}" -gt 0 ] || _die "release: no address given"
  if [ ! -e "${_MIG_ADOPT_STAMP}" ]; then
    _msg "release: the one-time import has not run; nothing released"
    return 4
  fi
  if ! _mpt_scan_records; then
    _msg "release: a root record cannot be read; nothing released"
    return 4
  fi
  if _mpt_any_undeclared; then
    _msg "release: an account here is undeclared and may need this trust; nothing released"
    return 4
  fi
  # Before the first prune, the reach older tools gave is dated and marked as
  # maybe under way here first, as the prune does.
  if [ ! -e "${_MPT_REACH_DAYS}" ]; then
    if _mpt_reach_seed; then
      _mpt_note "release: no reach day was kept here; the reach found is dated today"
    else
      _msg "release: could not write ${_MPT_REACH_DAYS} or ${_MPT_PENDING}; nothing released"
      return 4
    fi
  fi
  for _ip in "${_ips[@]}"; do
    if _mpt_in "${_ip}" "${_MPT_LIVE}"; then
      _msg "release: ${_ip}: a live inbound record names it; kept"
      continue
    fi
    _drop+=("${_ip}")
  done
  [ "${#_drop[@]}" -gt 0 ] || return 3
  _cmd_untrust "${_drop[@]}"
  for _ip in "${_drop[@]}"; do
    _drop_line "${_MIG_PEER_ADDRS}" "${_ip}"
    [ "$?" -eq 2 ] && _mpt_note "release: could not rewrite ${_MIG_PEER_ADDRS}; left as found"
  done
  if [ -n "${_over}" ]; then
    _reach=YES
  elif [ -n "${_to}" ] && [ ! -e /root/.standby.cnf ] && ! _mpt_xmass_pair "${_to}"; then
    _reach=YES
  fi
  # Reach root gave after the relay began here is for something newer, another
  # move from the same box most likely; a seeded day is no grant.
  if [ "${_reach}" = "YES" ] && [ -n "${_since}" ] && [ -z "${_over}" ]; then
    for _ip in "${_drop[@]}"; do
      _g="$(_mpt_reach_day "${_ip}" grant)" || continue
      [[ "${_g}" > "${_since}" ]] || continue
      _msg "release: ${_ip}: root gave it reach on ${_g}, after this relay began on ${_since}; its key and firewall lines stay"
      _reach=NO
      break
    done
  fi
  # The addresses given are one peer's: a move from it into this box under way
  # by any of them keeps the reach of all of them.
  if [ "${_reach}" = "YES" ]; then
    for _ip in "${_ips[@]}"; do
      _mpt_pending "${_ip}" || continue
      _msg "release: ${_ip}: a move from this peer into this box is under way; its key and firewall lines stay"
      _reach=NO
      break
    done
  fi
  if [ "${_reach}" = "YES" ]; then
    _CSF_CHANGED=NO
    for _ip in "${_drop[@]}"; do
      if _mpt_pair_named "${_ip}"; then
        _msg "release: ${_ip}: this box's own pair; its key and firewall lines stay"
        continue
      fi
      # Reach no day was kept for stays, judged on the address's own set as prune
      # judges it: older tools gave it, maybe for a move under way.
      _k=""
      for _a in $(_mpt_peer_set "${_ip}"); do
        _mpt_reach_day "${_a}" > /dev/null && _k=YES
      done
      if [ -z "${_k}" ]; then
        _msg "release: ${_ip}: no day was kept for its reach (older tools gave it); its key and firewall lines stay"
        continue
      fi
      _mpt_reach_drop "${_ip}"
    done
    [ "${_CSF_CHANGED}" = "YES" ] && _csf_reload
  fi
  if [ ! -s "${_csf_ctrl}" ] && [ -z "$(_conf_cat "${_realip_ctrl}")" ] \
    && [ "${_MPT_LIVE}" = " " ]; then
    rm -f "${_perm_flag}"
  fi
  return 0
}

# The first prune on a box: reach older tools gave kept no day. Each address
# holding reach now gets today's, marked seeded, so a relay that ends from now
# on takes it and one that ended before leaves it. A pre-mig's own line, written
# meanwhile, wins: the seed never replaces a file that appeared.
_mpt_reach_seed() {
  local _t="${_MPT_REACH_DAYS}.seed.$$" _p _today
  _today="$(date -u '+%Y-%m-%d')"
  {
    grep -vE '^[[:space:]]*#' "${_MIG_AUTH_KEYS}" 2> /dev/null \
      | sed -n -E 's/.* # (xmass|xoct|xcopy) migration source ([0-9.]+)[[:space:]]*$/\2/p'
    if _csf_present; then
      cat "${_csf_allow}" "${_csf_ignore}" 2> /dev/null \
        | sed -n -E 's/^([0-9.]+) # xmass migration (source|inbound-proxy)$/\1/p'
    fi
  } | sort -u | while IFS= read -r _ip; do
    _is_dotted_quad "${_ip}" || continue
    printf '%s %s seed\n' "${_ip}" "${_today}" || exit 1
  done > "${_t}" || { rm -f -- "${_t}"; return 1; }
  # A move older tools began may be under way from any address seeded here. Its
  # pending line goes first: a seed that fails leaves no reach file, and the
  # next run seeds again.
  _p="${_MPT_PENDING}.seed.$$"
  if ! { { cat "${_MPT_PENDING}" 2> /dev/null; awk '{ print $1, $2, "seed" }' "${_t}"; } \
    | awk '!s[$1]++' > "${_p}" && chmod 600 "${_p}" && mv -f -- "${_p}" "${_MPT_PENDING}"; }; then
    rm -f -- "${_p}" "${_t}"
    return 1
  fi
  chmod 600 "${_t}" && mv -n -- "${_t}" "${_MPT_REACH_DAYS}"
  rm -f -- "${_t}"
  [ -e "${_MPT_REACH_DAYS}" ]
}

# Daily, from the certificate mirror's cron: the reach of a relay that is over,
# and every address-list line nothing names any more. A standby prunes nothing:
# its records and witnesses are what its promotion will need.
_cmd_prune() {
  local _ip _l _seen=" " _drop=""
  [ -e "${_MIG_ADOPT_STAMP}" ] || return 0
  if [ ! -e "${_MPT_REACH_DAYS}" ]; then
    if _mpt_reach_seed; then
      _mpt_note "prune: no reach day was kept here; the reach found is dated today and nothing is pruned this run"
    else
      _mpt_note "prune: could not write ${_MPT_REACH_DAYS}; nothing pruned"
    fi
    return 0
  fi
  if [ -e /root/.standby.cnf ] || [ -e /root/.standby.prep.cnf ]; then
    return 0
  fi
  # A file a killed verb left is no verb: the holder must be alive.
  _l="$(tr -dc '0-9' 2> /dev/null < /run/xmass.verb.pid | head -c 12)"
  if [ -n "${_l}" ] && kill -0 "${_l}" 2> /dev/null; then
    return 0
  fi
  [ -n "$(_my_ipv4s)" ] || return 0
  if ! _mpt_scan_records; then
    _mpt_note "prune: a root record cannot be read; nothing pruned"
    return 0
  fi
  if _mpt_any_undeclared; then
    _mpt_note "prune: an account is undeclared; nothing pruned"
    return 0
  fi
  # Every address is judged once, before anything goes: a drop takes the day
  # line the judgement of a later address of the same peer reads.
  for _ip in ${_MPT_OVER}; do
    _mpt_in "${_ip}" "${_seen}" && continue
    _seen="${_seen}${_ip} "
    _mpt_in "${_ip}" "${_MPT_LIVE}${_MPT_HELD}" && continue
    _mpt_relay_listed "${_ip}" && continue
    if _mpt_pair_named "${_ip}"; then
      _msg "prune: ${_ip}: this box's own pair; its key and firewall lines stay"
      continue
    fi
    if _mpt_pending "${_ip}"; then
      _msg "prune: ${_ip}: a move from it into this box is under way; its key and firewall lines stay"
      continue
    fi
    if _mpt_granted_since "${_ip}"; then
      _msg "prune: ${_ip}: its reach is newer than its ended relay; it stays"
      continue
    fi
    _drop="${_drop} ${_ip}"
  done
  _CSF_CHANGED=NO
  for _ip in ${_drop}; do
    _mpt_reach_drop "${_ip}"
  done
  [ "${_CSF_CHANGED}" = "YES" ] && _csf_reload
  while IFS= read -r _l; do
    [ -n "${_l}" ] || continue
    _mpt_in "${_l}" "${_MPT_LIVE}${_MPT_HELD}" && continue
    _mpt_relay_listed "${_l}" && continue
    _drop_line "${_MIG_PEER_ADDRS}" "${_l}"
    if [ "$?" -eq 2 ]; then
      _mpt_note "prune: could not rewrite ${_MIG_PEER_ADDRS}; left as found"
      return 1
    fi
    _mpt_note "prune: ${_l}: dropped from ${_MIG_PEER_ADDRS}"
  done < <(cat "${_MIG_PEER_ADDRS}" 2> /dev/null)
  return 0
}

case "${1:-}" in
  trust)     shift; _cmd_trust "$@" ;;
  untrust)   shift; _cmd_untrust "$@" ;;
  teardown)  shift; _cmd_teardown "$@" ;;
  reconcile) shift; _cmd_reconcile "$@" ;;
  adopt)     shift; _cmd_adopt "$@" ;;
  release)   shift; _cmd_release "$@" ;;
  prune)     shift; _cmd_prune "$@" ;;
  *)
    echo "Usage: $0 trust <ip|cidr>... [--permanent] [--csf-only]"
    echo "       $0 untrust <ip|cidr>..."
    echo "       $0 teardown [--force]"
    echo "       $0 reconcile [--force]"
    echo "       $0 adopt [--once]"
    echo "       $0 release <ip>... [--to=<ip> [--since=<day>]|--over]"
    echo "       $0 prune"
    exit 1
  ;;
esac
