#!/bin/bash

###
### migration_proxy_certs.sh -- the certificate mirror for migration proxies.
###
### A converted source serves each site over HTTPS with its OWN certificate,
### frozen at cutover: renewals stop on a proxied account by design (owl.sh
### and the fleet LE sweep both skip it, and the proxy forwards ACME
### challenges to the target), so the TARGET is the sole issuer from
### conversion onwards. Without this mirror a long-lived proxy presents an
### expired certificate 69-90 days after cutover, silently, to exactly the
### visitors whose owners took the "no hurry" advice.
###
### Daily from cron (a quiet no-op on boxes with no proxied account): for
### every HTTPS proxy vhost, locate the same domain's live certificate set on
### the target over ssh and, when the target's notAfter is strictly newer,
### pull privkey/fullchain/cert/chain into the local LE store -- staged,
### verified (parse + enddate + key/cert pubkey match), ownership/mode
### preserved, with a .bak set kept. The real files live under
### tools/le/certs/<domain>/; the openssl.* names in ssl.d are symlinks into
### them (provision_hosting_le), so the symlink topology is never touched.
### One nginx -t + reload at the end under the shared config lock; a failed
### configtest restores every set swapped this run and does not reload.
###
### Safe when the target is unreachable: nothing newer is found and the last
### good certificate stays in place -- the proxy's TLS depends only on files
### already on its own disk. Mails the admin when the earliest certificate
### behind a retained proxy vhost is within _MIGRATION_PROXY_CERT_WARN_DAYS
### (default 21) and could not be refreshed; this is the only warning path
### that exists on a proxied box.
###
### All proxied accounts are mirrored regardless of mode: a temporary proxy
### that overstays decays exactly the same way, and fresh TLS during any
### residual relay window harms nothing. Withdrawal is an operator act
### (xoct proxy-retire), never a certificate accident.
###
### One class is NOT mirrored, because nothing can be: a site that was named
### under this box's own hostname was renamed on the target by the cutover,
### and its old name is answered here with a bare 301 to the new one. No
### proxy_pass names a peer and the target no longer issues for the retired
### name, so its certificate simply runs out. That is reported, by name and
### by mail, once when it enters the warning window and once when it has
### expired -- an HTTPS visitor of the old URL then meets the browser's
### warning before the redirect, and only the site's owner can act on that.
###
### Usage: migration_proxy_certs.sh [--dry]
###

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_DRY=NO
[ "$1" = "--dry" ] && _DRY=YES

### Quiet no-op unless this box actually proxies something.
ls /data/disk/*/log/proxied.pid >/dev/null 2>&1 || exit 0

# shellcheck disable=SC1091
[ -r /opt/local/bin/lock.inc ] && . /opt/local/bin/lock.inc
command -v _single_instance_lock >/dev/null 2>&1 && _single_instance_lock

# shellcheck disable=SC1091
[ -e /root/.barracuda.cnf ] && . /root/.barracuda.cnf
_ADM_EMAIL=${_MY_EMAIL//\\\@/\@}
_WARN_DAYS="${_MIGRATION_PROXY_CERT_WARN_DAYS:-21}"
case "${_WARN_DAYS}" in ''|*[!0-9]*) _WARN_DAYS=21 ;; esac

_SSH="ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new"
_LOCK_FILE="/run/boa_nginx_config.lock"
_NOW_EPOCH=$(date -u '+%s')

_msg() { echo "migration_proxy_certs: $*"; }

_valid_ip()  { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
_valid_dom() { [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; }

### notAfter of the certificate on stdin as epoch seconds; empty on any
### failure.
_cert_end_epoch() {
  local _end
  _end=$(openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  [ -n "${_end}" ] || return 1
  date -ud "${_end}" '+%s' 2>/dev/null
}

### An account owns its log/, config/ and tools/le (the LE store is handed to
### it), so any name there can be a link or a FIFO, and any directory on the
### way can itself be a link. Root reads and writes those names only inside
### the real directory: reads are bounded and never follow a link or block
### on a FIFO, writes are fresh files renamed over the name.
###
### Run "$@" inside the real directory $1, never one reached through a link
### an account planted on the way. Below /home and /data/disk (root's) every
### name on the path must be a real directory; elsewhere the last name is
### checked against its resolved parent. Once entered, ./name stays in that
### directory whatever is swapped.
_mpc_in_real_dir() {
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
### ./$1 in the current (pinned) directory: never through a link, never
### blocked on a FIFO, at most 1 MiB. Empty for anything else.
_mpc_read_here() {
  timeout 10 dd if="./${1}" iflag=nofollow,nonblock,fullblock \
    bs=1048576 count=1 status=none 2> /dev/null
}
### $2 in the real directory $1, read as _mpc_read_here reads it.
_mpc_read_in() {
  _mpc_in_real_dir "${1}" _mpc_read_here "${2}"
}
### The name ./$1 of the current (pinned) LE store resolves to: dehydrated
### keeps each name as a link to the dated file beside it, so such a link is
### followed one step, and only to a plain name in this same directory.
_mpc_cert_name_here() {
  local _l
  if [ -L "./${1}" ]; then
    _l=$(readlink -- "./${1}" 2> /dev/null)
    [[ "${_l}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
    printf '%s' "${_l}"
  else
    printf '%s' "${1}"
  fi
}
### ./$1 of the current (pinned) LE store, read as _mpc_read_here reads it,
### after the one step _mpc_cert_name_here allows.
_mpc_cert_here() {
  local _n
  _n=$(_mpc_cert_name_here "${1}") || return 1
  _mpc_read_here "${_n}"
}
### $2 of the LE store $1, read as _mpc_cert_here reads it.
_mpc_cert_in() {
  _mpc_in_real_dir "${1}" _mpc_cert_here "${2}"
}
### "<uid>:<gid> <mode>" of ./$1 in the current (pinned) directory when it
### is a regular file itself; nothing, status 1, for anything else.
_mpc_plain_attrs_here() {
  local _st
  _st=$(stat -c '%u:%g %a %F' -- "./${1}" 2> /dev/null) || return 1
  case "${_st}" in
    *" regular file"|*" regular empty file") printf '%s' "${_st% regular*}" ;;
    *) return 1 ;;
  esac
}
### "<uid>:<gid> <mode>" of the regular file ./$1 of the current (pinned) LE
### store names (after the one step _mpc_cert_name_here allows); nothing,
### status 1, for anything else.
_mpc_cert_attrs_here() {
  local _n
  _n=$(_mpc_cert_name_here "${1}") || return 1
  _mpc_plain_attrs_here "${_n}"
}
### A mode set on names in the current (pinned) directory through a handle
### opened without following a link or blocking on a FIFO, only on a regular
### file. Args: the mode (octal), the names.
_MPC_FCHMOD_PL='use Fcntl;
my $m = oct(shift @ARGV);
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  stat($h);
  chmod($m, $h) if -f _;
  close($h);
}'
### The file $2 (a root-only staged copy) put at ./$1 in the current
### (pinned) LE store: a fresh file created exclusively, given the owner and
### mode $3 ("<uid>:<gid> <mode>"; empty leaves it root's, 0600) through
### names and handles that never follow a link, then renamed over the name,
### so a link or a FIFO put at the name is replaced, never followed or
### opened.
_mpc_put_here() {
  local _t="./.${1}.put.$$.${RANDOM}" _own="" _mod="600"
  [ -z "${3}" ] || read -r _own _mod <<< "${3}"
  rm -f -- "${_t}"
  if ( umask 077; dd if="${2}" of="${_t}" conv=excl status=none 2> /dev/null ) \
    && { [ -z "${_own}" ] || chown -h "${_own}" "${_t}" 2> /dev/null; } \
    && perl -e "${_MPC_FCHMOD_PL}" "${_mod}" "${_t}" 2> /dev/null \
    && mv -f -T -- "${_t}" "./${1}"; then
    return 0
  fi
  rm -f -- "${_t}"
  return 1
}
### The staged set in $1 put over the names of the current (pinned) LE store:
### each old file kept as <name>.bak and the new one put in its place, both
### with the old file's owner and mode (a dehydrated link is judged by the
### dated file it names, never by the link itself), as _mpc_put_here puts
### them. Every .bak is written first, and nothing is put unless each name
### that had a file got one (status 4), so a rollback never mixes an old and
### a new half; a name with no file drops any .bak left from before. Status
### 3 when not every name could be put in place.
_mpc_swap_here() {
  local _stg="${1}" _f _a _i=0 _rc=0
  local -a _as=()
  for _f in ${_CERT_SET}; do
    if _a=$(_mpc_cert_attrs_here "${_f}"); then
      { _mpc_cert_here "${_f}" > "${_stg}/${_f}.old" \
        && _mpc_put_here "${_f}.bak" "${_stg}/${_f}.old" "${_a}"; } || return 4
    else
      _a=""
      rm -f -- "./${_f}.bak"
    fi
    _as[_i]="${_a}"
    _i=$(( _i + 1 ))
  done
  _i=0
  for _f in ${_CERT_SET}; do
    _mpc_put_here "${_f}" "${_stg}/${_f}" "${_as[_i]}" || _rc=3
    _i=$(( _i + 1 ))
  done
  return "${_rc}"
}
### Every name of the set in the current (pinned) LE store given back the
### content, owner and mode of its .bak, as _mpc_put_here puts it; only a
### .bak that is a regular file itself is used, read never through a link or
### a FIFO.
_mpc_restore_here() {
  local _w _f _a
  _w=$(mktemp -d /var/backups/.boa-mig-certs.XXXXXX 2> /dev/null) || return 1
  for _f in ${_CERT_SET}; do
    _a=$(_mpc_plain_attrs_here "${_f}.bak") || continue
    _mpc_read_here "${_f}.bak" > "${_w}/${_f}" \
      && _mpc_put_here "${_f}" "${_w}/${_f}" "${_a}"
  done
  rm -rf "${_w}"
}
### The set and its .bak copies in the current (pinned) LE store that a
### mirror run of an earlier release left as regular files with mode 0777
### (it gave each the mode of the dehydrated link it replaced) get the mode
### dehydrated writes them with, 0600, through handles that never follow a
### link. Any other mode is left as it is, so this changes nothing once
### healed.
_MPC_HEAL777_PL='use Fcntl;
for my $f (@ARGV) {
  sysopen(my $h, $f, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next;
  my @s = stat($h);
  chmod(0600, $h) if @s && -f _ && ($s[2] & 07777) == 0777;
  close($h);
}'
_mpc_heal_here() {
  local _f
  local -a _n=()
  for _f in ${_CERT_SET}; do
    _n+=( "./${_f}" "./${_f}.bak" )
  done
  perl -e "${_MPC_HEAL777_PL}" "${_n[@]}" 2> /dev/null
}
### $3 of the LE store $2 on the target $1, printed as _mpc_cert_here prints
### it here: the same helpers run there, so the target's copy is read inside
### its real directory too, never through a link or into a FIFO the account
### put on that side.
_mpc_remote_cert() {
  { declare -f _mpc_in_real_dir _mpc_read_here _mpc_cert_name_here _mpc_cert_here
    printf '_mpc_in_real_dir %q _mpc_cert_here %q\n' "${2}" "${3}"
  } | ${_SSH} root@"${1}" "bash -s" 2>/dev/null
}
### A path named in an account's own vhost, as the same file below the
### account root $1 with no link left on the way; nothing, status 1, when it
### resolves anywhere else, so the read never leaves the account's tree.
_mpc_acct_path() {
  local _r _p
  [ -n "${2}" ] || return 1
  _r=$(cd -P -- "${1}" 2> /dev/null && pwd -P) || return 1
  _p=$(realpath -e -- "${2}" 2> /dev/null) || return 1
  case "${_p}" in
    "${_r}"/?*) printf '%s' "${1}${_p#"${_r}"}" ;;
    *) return 1 ;;
  esac
}
### The HTTPS proxy vhost names in the current (pinned) vhost.d, one per
### line; the glob expands in this directory only.
_mpc_https_names_here() {
  local _v
  for _v in ./https.*; do
    _v="${_v#./}"
    case "${_v}" in *$'\n'*) continue ;; esac
    [ -e "./${_v}" ] && printf '%s\n' "${_v}"
  done
}

_CHANGED=NO
_FAIL_REFRESH=""
_RETIRED=""
_SWAPPED_DIRS=""

### True for the cutover's redirect vhost: the HTTPS proxy header is still
### there, but every location (and with it every proxy_pass) was replaced by
### a bare 301 to the renamed site.
### $1 is the vhost's text.
_is_retired_vhost() {
  ! grep -q 'proxy_pass' <<< "$1" \
    && grep -q '^[[:space:]]*return 301 ' <<< "$1"
}
_EARLIEST_EPOCH=""
_EARLIEST_DOM=""

### The four real files behind the ssl.d symlinks; chain.pem is also
### referenced directly by the proxy vhost (ssl_trusted_certificate).
_CERT_SET="privkey.pem fullchain.pem cert.pem chain.pem"

_pull_domain() {
  local _oct="$1" _dom="$2" _tip="$3"
  local _root="/data/disk/${_oct}"
  local _dir="${_root}/tools/le/certs/${_dom}"
  local _rdir _hits _lend _rend _f _ok _stg _rc

  if [ ! -d "${_dir}" ] || [ ! -e "${_dir}/fullchain.pem" ]; then
    _msg "ALRT: ${_oct}/${_dom}: no local LE store at ${_dir}; skipping"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  [ "${_DRY}" = "YES" ] || _mpc_in_real_dir "${_dir}" _mpc_heal_here

  _lend=$(_mpc_cert_in "${_dir}" fullchain.pem | _cert_end_epoch)
  if [ -z "${_lend}" ]; then
    _msg "ALRT: ${_oct}/${_dom}: local fullchain.pem unreadable as a certificate"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  if [ -z "${_EARLIEST_EPOCH}" ] || [ "${_lend}" -lt "${_EARLIEST_EPOCH}" ]; then
    _EARLIEST_EPOCH="${_lend}"; _EARLIEST_DOM="${_dom}"
  fi

  ### Exactly one hit on the target, whatever the account is called there --
  ### this is also what keeps the mirror correct after a rename-mode move.
  _hits=$(${_SSH} root@"${_tip}" \
    "ls -d /data/disk/*/tools/le/certs/${_dom} 2>/dev/null" 2>/dev/null < /dev/null)
  if [ -z "${_hits}" ]; then
    _msg "ALRT: ${_oct}/${_dom}: no LE store for this domain on target ${_tip} (or target unreachable); keeping the local certificate"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  if [ "$(printf '%s\n' "${_hits}" | wc -l)" -ne 1 ]; then
    _msg "ALRT: ${_oct}/${_dom}: MULTIPLE LE stores match on target ${_tip}; refusing to guess"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  _rdir="${_hits}"
  if [[ ! "${_rdir}" =~ ^/data/disk/[A-Za-z0-9._-]+/tools/le/certs/[a-zA-Z0-9.-]+$ ]] \
    || [ "${_rdir##*/}" != "${_dom}" ]; then
    _msg "ALRT: ${_oct}/${_dom}: unexpected LE store path on target ${_tip}; refusing to guess"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi

  _rend=$(_mpc_remote_cert "${_tip}" "${_rdir}" fullchain.pem | _cert_end_epoch)
  if [ -z "${_rend}" ]; then
    _msg "ALRT: ${_oct}/${_dom}: cannot read the target certificate's expiry"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi

  if [ "${_rend}" -le "${_lend}" ]; then
    [ "${_DRY}" = "YES" ] && _msg "DRY: ${_oct}/${_dom}: target is not newer ($(date -ud @"${_rend}" '+%Y-%m-%d') <= $(date -ud @"${_lend}" '+%Y-%m-%d')); nothing to do"
    return 0
  fi

  if [ "${_DRY}" = "YES" ]; then
    _msg "DRY: ${_oct}/${_dom}: WOULD pull (target $(date -ud @"${_rend}" '+%Y-%m-%d') > local $(date -ud @"${_lend}" '+%Y-%m-%d'))"
    return 0
  fi

  ### Stage the whole set from the same remote directory in one pass, so a
  ### renewal landing on the target mid-copy cannot produce a torn pair. The
  ### set is staged in a root-only directory, never in the account's store.
  _stg=$(mktemp -d /var/backups/.boa-mig-certs.XXXXXX 2>/dev/null)
  if [ -z "${_stg}" ]; then
    _msg "ALRT: ${_oct}/${_dom}: no private staging directory; aborting this domain"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  for _f in ${_CERT_SET}; do
    if ! _mpc_remote_cert "${_tip}" "${_rdir}" "${_f}" > "${_stg}/${_f}"; then
      _msg "ALRT: ${_oct}/${_dom}: staging ${_f} from target failed; aborting this domain"
      rm -rf "${_stg}"
      _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
      return 1
    fi
  done

  ### Verify the staged set before anything is touched: the certificate must
  ### parse to the expiry we were promised, and the staged key must actually
  ### belong to the staged certificate (pubkey compare works for RSA and EC).
  _ok=$(_cert_end_epoch < "${_stg}/fullchain.pem")
  if [ "${_ok}" != "${_rend}" ]; then
    _msg "ALRT: ${_oct}/${_dom}: staged certificate does not match the promised expiry; discarding"
    rm -rf "${_stg}"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  if [ "$(openssl x509 -pubkey -noout -in "${_stg}/fullchain.pem" 2>/dev/null | openssl md5 2>/dev/null)" \
    != "$(openssl pkey -pubout -in "${_stg}/privkey.pem" 2>/dev/null | openssl md5 2>/dev/null)" ]; then
    _msg "ALRT: ${_oct}/${_dom}: staged key does not match the staged certificate; discarding"
    rm -rf "${_stg}"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi

  ### Swap the set inside the real store, preserving each file's exact
  ### ownership and mode and keeping a .bak copy for the configtest rollback.
  _mpc_in_real_dir "${_dir}" _mpc_swap_here "${_stg}"
  _rc=$?
  rm -rf "${_stg}"
  if [ "${_rc}" -eq 4 ]; then
    _msg "ALRT: ${_oct}/${_dom}: the current set could not be kept as .bak; nothing swapped"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  if [ "${_rc}" -ne 0 ] && [ "${_rc}" -ne 3 ]; then
    _msg "ALRT: ${_oct}/${_dom}: ${_dir} is not a real directory; nothing swapped"
    _FAIL_REFRESH="${_FAIL_REFRESH} ${_dom}"
    return 1
  fi
  [ "${_rc}" -eq 3 ] \
    && _msg "ALRT: ${_oct}/${_dom}: not every file of the set could be put in place"
  _CHANGED=YES
  _SWAPPED_DIRS="${_SWAPPED_DIRS} ${_dir}"
  _msg "${_oct}/${_dom}: refreshed from target ${_tip} (now valid to $(date -ud @"${_rend}" '+%Y-%m-%d'))"
  return 0
}

### Walk every proxied account's HTTPS proxy vhosts. The peer comes from the
### vhost's own proxy_pass (what is actually serving) and is cross-checked
### against the account's policy record where one exists -- a disagreement is
### exactly the half-repointed state --repair --retarget exists to fix, so
### refuse rather than pull certificates from either candidate.
for _PID in /data/disk/*/log/proxied.pid; do
  [ -e "${_PID}" ] || continue
  _ROOT=$(dirname "$(dirname "${_PID}")")
  _OCT=$(basename "${_ROOT}")
  _CNF=$(_mpc_read_in "${_ROOT}/log" migproxy.cnf)
  _REC_IP=""
  if [ -n "${_CNF}" ] \
    && grep -qx "_MIG_ROLE=source" <<< "${_CNF}" \
    && hostname -I 2>/dev/null | tr ' ' '\n' \
       | grep -qxF "$(grep -m1 '^_MIG_HOST_IP=' <<< "${_CNF}" | cut -d= -f2-)"; then
    _REC_IP=$(grep -m1 '^_MIG_PEER_IP=' <<< "${_CNF}" | cut -d= -f2- | tr -d '\r\n')
    _valid_ip "${_REC_IP}" || _REC_IP=""
  fi
  _VD="${_ROOT}/config/server_master/nginx/vhost.d"
  while IFS= read -r -u 9 _V; do
    _VHS="${_VD}/${_V}"
    _VHC=$(_mpc_read_in "${_VD}" "${_V}")
    grep -q "Secure HTTPS proxy for" <<< "${_VHC}" || continue
    _DOM=$(grep -m1 "Secure HTTPS proxy for" <<< "${_VHC}" \
      | sed 's/.*proxy for //; s/ (START).*//')
    ### A retired (renamed) name has no peer to pull from: its own class,
    ### reported below, never a parse failure.
    if _is_retired_vhost "${_VHC}"; then
      _valid_dom "${_DOM}" && _RETIRED="${_RETIRED} ${_OCT}/${_DOM}"
      continue
    fi
    _VIP=$(grep -m1 'proxy_pass' <<< "${_VHC}" \
      | sed 's/.*https:\/\///; s/;.*//' | tr -d ' ')
    if ! _valid_dom "${_DOM}" || ! _valid_ip "${_VIP}"; then
      _msg "ALRT: ${_OCT}: cannot parse domain/target from ${_VHS}; skipping"
      continue
    fi
    if [ -n "${_REC_IP}" ] && [ "${_REC_IP}" != "${_VIP}" ]; then
      _msg "ALRT: ${_OCT}/${_DOM}: vhost forwards to ${_VIP} but the policy record says ${_REC_IP};"
      _msg "ALRT:   refusing to mirror until they agree -- repair with:"
      _msg "ALRT:   xoct proxy ${_OCT} <correct-ip> --repair --retarget"
      _FAIL_REFRESH="${_FAIL_REFRESH} ${_DOM}"
      continue
    fi
    _pull_domain "${_OCT}" "${_DOM}" "${_VIP}"
  done 9< <(_mpc_in_real_dir "${_VD}" _mpc_https_names_here)
done

### One configtest + reload for the whole run, under the shared writer lock.
### A failed test restores every set swapped this run and reloads nothing:
### the proxy keeps serving the last good certificates.
if [ "${_CHANGED}" = "YES" ]; then
  exec 8>"${_LOCK_FILE}"
  if flock -w 30 8; then
    if nginx -t >/dev/null 2>&1; then
      service nginx reload >/dev/null 2>&1
      _msg "nginx reloaded with the refreshed certificate set(s)"
    else
      for _DIR in ${_SWAPPED_DIRS}; do
        _mpc_in_real_dir "${_DIR}" _mpc_restore_here
      done
      _msg "ALRT: nginx configtest FAILED after the swap; every set swapped this run was restored and nginx was NOT reloaded"
      flock -u 8
      exit 1
    fi
    flock -u 8
  else
    _msg "ALRT: could not take ${_LOCK_FILE} within 30s; certificates swapped but nginx NOT reloaded -- next run (or any config writer) will pick them up"
  fi
fi

### The only expiry warning a proxied box has: recompute the earliest horizon
### over the vhosts we track and mail when it is close AND a refresh failed.
_EARLIEST_EPOCH=""
_EARLIEST_DOM=""
for _PID in /data/disk/*/log/proxied.pid; do
  [ -e "${_PID}" ] || continue
  _ROOT=$(dirname "$(dirname "${_PID}")")
  _VD="${_ROOT}/config/server_master/nginx/vhost.d"
  while IFS= read -r -u 9 _V; do
    _VHC=$(_mpc_read_in "${_VD}" "${_V}")
    grep -q "Secure HTTPS proxy for" <<< "${_VHC}" || continue
    ### A retired name cannot be refreshed, so it has no place in the horizon
    ### that the refresh-failure mail speaks for; it is reported on its own.
    _is_retired_vhost "${_VHC}" && continue
    _DOM=$(grep -m1 "Secure HTTPS proxy for" <<< "${_VHC}" \
      | sed 's/.*proxy for //; s/ (START).*//')
    _valid_dom "${_DOM}" || continue
    _END=$(_mpc_cert_in "${_ROOT}/tools/le/certs/${_DOM}" fullchain.pem | _cert_end_epoch)
    [ -n "${_END}" ] || continue
    if [ -z "${_EARLIEST_EPOCH}" ] || [ "${_END}" -lt "${_EARLIEST_EPOCH}" ]; then
      _EARLIEST_EPOCH="${_END}"; _EARLIEST_DOM="${_DOM}"
    fi
  done 9< <(_mpc_in_real_dir "${_VD}" _mpc_https_names_here)
done

if [ -n "${_EARLIEST_EPOCH}" ]; then
  _DAYS_LEFT=$(( (_EARLIEST_EPOCH - _NOW_EPOCH) / 86400 ))
  if [ "${_DAYS_LEFT}" -lt "${_WARN_DAYS}" ] && [ -n "${_FAIL_REFRESH}" ]; then
    _msg "ALRT: earliest proxy certificate (${_EARLIEST_DOM}) expires in ${_DAYS_LEFT} day(s) and could not be refreshed:${_FAIL_REFRESH}"
    if [ "${_DRY}" != "YES" ] && [ -n "${_ADM_EMAIL}" ]; then
      _MAILX_TEST=$(s-nail -V 2>&1)
      if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
        _HOST=$(hostname -f 2>/dev/null)
        cat <<EOF | s-nail -s "ALERT: migration proxy certificate horizon ${_DAYS_LEFT} day(s) on ${_HOST}" ${_ADM_EMAIL}
The earliest certificate behind a retained migration proxy vhost on ${_HOST}
(${_EARLIEST_DOM}) expires in ${_DAYS_LEFT} day(s), and the daily mirror could
not refresh:${_FAIL_REFRESH}

Once it expires, every HTTPS visitor still reaching those sites through the
old address sees a browser certificate warning. Check that the target still
holds a live store for each domain and that this box can reach it over ssh,
or retire the proxy (xoct proxy-retire) if it is no longer meant to serve.

-- migration_proxy_certs.sh
EOF
      fi
    fi
  fi
fi

### Retired (renamed) names: nothing renews their certificates, so the expiry
### is reported rather than fought. One line per name on every run; one mail
### when a name first enters the warning window and one when it has expired
### (markers under /var/log/boa, cleared again if the certificate is ever
### healthy), so the notice is loud once instead of daily noise.
_RET_NEW=""
for _R in ${_RETIRED}; do
  _OCT="${_R%%/*}"
  _DOM="${_R#*/}"
  [ "${_DRY}" = "YES" ] \
    || _mpc_in_real_dir "/data/disk/${_OCT}/tools/le/certs/${_DOM}" _mpc_heal_here
  _VHC=$(_mpc_read_in "/data/disk/${_OCT}/config/server_master/nginx/vhost.d" "https.${_DOM}")
  _CRT=$(grep -m1 'ssl_certificate ' <<< "${_VHC}" | awk '{ print $2 }' | tr -d ';')
  ### The vhost is the account's, so the path it names is read only where it
  ### resolves inside the account's own tree; anything else falls back to the
  ### account's LE store, as an unreadable path always did.
  _CRT=$(_mpc_acct_path "/data/disk/${_OCT}" "${_CRT}") \
    || _CRT="/data/disk/${_OCT}/tools/le/certs/${_DOM}/fullchain.pem"
  _END=$(_mpc_cert_in "${_CRT%/*}" "${_CRT##*/}" | _cert_end_epoch)
  if [ -z "${_END}" ]; then
    _msg "${_OCT}/${_DOM}: retired name (answers 301 to its renamed site); its certificate could not be read"
    continue
  fi
  _RDAYS=$(( (_END - _NOW_EPOCH) / 86400 ))
  _MARK="/var/log/boa/.migration_proxy_certs.retired.${_DOM}"
  if [ "${_END}" -le "${_NOW_EPOCH}" ]; then
    _msg "${_OCT}/${_DOM}: retired name (answers 301 to its renamed site); certificate EXPIRED, nothing renews it"
    if [ ! -e "${_MARK}.expired" ]; then
      _RET_NEW="${_RET_NEW} ${_DOM}(EXPIRED)"
      [ "${_DRY}" != "YES" ] && : > "${_MARK}.expired"
    fi
  else
    _msg "${_OCT}/${_DOM}: retired name (answers 301 to its renamed site); certificate valid ${_RDAYS} more day(s), nothing renews it"
    if [ "${_RDAYS}" -lt "${_WARN_DAYS}" ]; then
      if [ ! -e "${_MARK}.warned" ]; then
        _RET_NEW="${_RET_NEW} ${_DOM}(${_RDAYS}d)"
        [ "${_DRY}" != "YES" ] && : > "${_MARK}.warned"
      fi
    elif [ "${_DRY}" != "YES" ]; then
      rm -f "${_MARK}.warned" "${_MARK}.expired"
    fi
  fi
done

if [ -n "${_RET_NEW}" ]; then
  _msg "ALRT: certificate(s) of retired site name(s) running out, nothing renews them:${_RET_NEW}"
  if [ "${_DRY}" != "YES" ] && [ -n "${_ADM_EMAIL}" ]; then
    _MAILX_TEST=$(s-nail -V 2>&1)
    if [[ "${_MAILX_TEST}" =~ "built for Linux" ]]; then
      _HOST=$(hostname -f 2>/dev/null)
      cat <<EOF | s-nail -s "NOTICE: certificate of a retired site name is running out on ${_HOST}" ${_ADM_EMAIL}
These site names were under this box's own hostname and were renamed on the
target by the migration; ${_HOST} answers them with a 301 to the new name:
${_RET_NEW}

Nothing renews their certificates: the target no longer issues for a retired
name, and there is no proxy behind it to mirror from. Once a certificate has
expired, an HTTPS visitor of the old URL meets the browser's warning before
the redirect; plain HTTP visitors are redirected as before.

Nothing on this box needs fixing. If the old HTTPS address is still in use,
have its links moved to the site's new name, or retire the proxy
(xoct proxy-retire) when it is no longer meant to serve. This notice is sent
once when a name enters the last ${_WARN_DAYS} day(s) and once when it expires.

-- migration_proxy_certs.sh
EOF
    fi
  fi
fi

exit 0
