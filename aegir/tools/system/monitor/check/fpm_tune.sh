#!/bin/bash
#
# BOA adaptive PHP-FPM tuning — sampler v1.3 (Phases 2+3, READ-ONLY tuning;
# self-installs its libfcgi-bin dependency, guarded and rate-limited).
#
# Appends one JSONL record per live FPM pool ("scope":"pool") and one per live
# PHP version ("scope":"version") to /var/log/boa/fpm-tune/<date>.jsonl. It
# writes NO phpXX.ini, triggers NO FPM restart, changes NO tuning — it only
# accumulates the data the Phase 4 aggregation reads.
#
# Three passes, in this order ON PURPOSE:
#   1. Version discovery + worker USS sweep — BEFORE any socket traffic, so the
#      workers spawned to serve our own status/probe requests never dilute the
#      per-version average USS.
#   2. Per-pool pm.status (json&full) over each pool socket -> pool records.
#   3. Per-version opcache/APCu probe through that version's wwwNN system-pool
#      socket (segments are shared per master, so any pool of the version reads
#      the same data) -> version records, carrying the USS numbers from pass 1.
#
# The PHP probe is embedded below (BOAPROBE heredoc) and self-deploys to
# ${_PROBE_PHP}. It must live under /var/www: BOA sets
# opcache.restrict_api=/var/www (php.sh.inc), so opcache_get_status() only
# works for scripts under that prefix — and only the wwwNN pool (which has no
# open_basedir) can execute from there, which is why the probe goes through the
# wwwNN socket (fallback: the version's first pool socket, opcache then reports
# restricted). Bump _PROBE_VER to force a probe rewrite on the next run. The
# probe degrades gracefully: denied/absent functions report *_fn=0, a blocked
# status API reports opcache_restricted=1, and the version record still carries
# USS and master identity.
#
# Probe self-pollution (Phase 4 must correct for this, see phase2-result.md):
# every pool gets +1 accepted_conn per sample from the status query, and the
# version's probe_pool (normally wwwNN, so the system pool, not a tenant) gets
# one more from the probe — visible from the NEXT sample on, since the probe
# runs after the status pass; on otherwise-idle pools peak_req_mem may show the
# probe's own footprint (small MiB), so idle/cold classification uses
# accepted_conn growth minus the probe count, never active/max_active or a tiny
# peak_req_mem.
#
# Final home (Phase 2b, after live validation): aegir/tools/system/monitor/check/
# launched from minute.sh (self-throttles to ~5 min). Operator validation:
#
#   bash fpm_tune.sh --force --stdout      # sample once, print + store records
#
# Conventions: BOA monitor sibling (cf. php.sh / nginx.sh). No systemd. Parser is
# dependency-free (grep/sort/awk) to match the other monitors; needs cgi-fcgi.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthDat="/var/log/boa/fpm-tune"
_pthLog="${_pthDat}/fpm_tune.log"
_STAMP="${_pthDat}/.last_run"
_RETAIN_DAYS=30
_PROBE_DIR="/var/www/fpm-probe"
_PROBE_PHP="${_PROBE_DIR}/boa-fpm-probe.php"
_PROBE_VER=2

_FORCE=NO
_STDOUT=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)   _FORCE=YES ;;
    --stdout)  _STDOUT=YES ;;
    -h|--help) echo "Usage: fpm_tune.sh [--force] [--stdout]"; exit 0 ;;
    *) echo "Unknown argument: ${_arg}" >&2; exit 2 ;;
  esac
done

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

# Run only on a fully installed system (same guard the sibling monitors use).
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# Nice ourselves down; this is a background sampler.
export _B_NICE=${_B_NICE//[^0-9-]/}
if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then _B_NICE=10; fi
if   (( _B_NICE < -20 )); then _B_NICE=-20
elif (( _B_NICE >  19 )); then _B_NICE=19; fi
renice ${_B_NICE} -p $$ &> /dev/null

###
### Atomic lock/unlock to prevent TOCTOU race (same pattern as the sibling monitors).
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    _single_instance_lock
  else
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

mkdir -p "${_pthDat}"

# Self-throttle to ~5 min (minute.sh relaunches us every minute), unless --force.
if [ "${_FORCE}" != "YES" ] && [ -e "${_STAMP}" ] \
  && [ -z "$(find "${_STAMP}" -mmin +4 2>/dev/null)" ]; then
  exit 0
fi
touch "${_STAMP}"

# cgi-fcgi (libfcgi-bin) is required. The base package set ensures it on system
# upgrades, but nodes that receive this monitor first must self-heal: install it
# here, guarded -- never while barracuda or another apt/dpkg run is active, and
# retry at most every ~6h so a broken repo cannot turn this monitor into an apt
# hammer (or a log spammer; failures log one line per attempt cycle, success one).
_DEP_STAMP="${_pthDat}/.dep_attempt"
if ! command -v cgi-fcgi >/dev/null 2>&1; then
  # Another package operation in flight: try again on a later tick, silently.
  if [ -e "/run/boa_run.pid" ]; then
    exit 0
  fi
  if pgrep -x apt-get >/dev/null 2>&1 || pgrep -x apt >/dev/null 2>&1 \
    || pgrep -x dpkg >/dev/null 2>&1 || pgrep -x aptitude >/dev/null 2>&1; then
    exit 0
  fi
  # Rate-limit attempts to one per ~6h.
  if [ -e "${_DEP_STAMP}" ] \
    && [ -z "$(find "${_DEP_STAMP}" -mmin +360 2>/dev/null)" ]; then
    exit 0
  fi
  touch "${_DEP_STAMP}"
  # Keep only the last attempt output for debugging.
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libfcgi-bin > "${_pthLog}.apt" 2>&1
  if ! command -v cgi-fcgi >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update >> "${_pthLog}.apt" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libfcgi-bin >> "${_pthLog}.apt" 2>&1
  fi
  if command -v cgi-fcgi >/dev/null 2>&1; then
    echo "$(date) installed libfcgi-bin (cgi-fcgi); FPM sampling enabled" >> "${_pthLog}"
    rm -f "${_DEP_STAMP}"
  else
    echo "$(date) libfcgi-bin install failed; next attempt in ~6h (see fpm_tune.log.apt)" >> "${_pthLog}"
    exit 0
  fi
fi

# No FPM pools (e.g. a proxy node) -> nothing to do.
shopt -s nullglob
_socks=(/run/*.fpm.socket)
shopt -u nullglob
[ ${#_socks[@]} -gt 0 ] || exit 0

#
# Self-deploy the per-version opcache/APCu probe. Lives under /var/www to
# satisfy opcache.restrict_api=/var/www; executed via the wwwNN pool, which has
# no open_basedir. Plain PHP 5.x-compatible (php56..php85 all execute it).
# World-readable, root-owned, never written by the pool user.
_ensure_probe_php() {
  # v1.1 deployed the probe under /data/conf, where opcache.restrict_api blocks
  # the status API; remove that copy if present.
  if [ -e "/data/conf/fpm-probe/boa-fpm-probe.php" ]; then
    rm -rf /data/conf/fpm-probe
  fi
  if [ -e "${_PROBE_PHP}" ] \
    && grep -q "boa-fpm-probe v${_PROBE_VER} (fpm_tune)" "${_PROBE_PHP}" 2>/dev/null; then
    return 0
  fi
  mkdir -p "${_PROBE_DIR}"
  chmod 0755 "${_PROBE_DIR}"
  cat > "${_PROBE_PHP}.tmp" <<'BOAPROBE'
<?php
/* boa-fpm-probe v2 (fpm_tune) - written by fpm_tune.sh, do not edit */
error_reporting(0);
ini_set('display_errors', '0');
if (!headers_sent()) { header('Content-Type: application/json'); }
function _boa_shorthand_bytes($v) {
  $v = trim((string) $v);
  if ($v === '') { return 0; }
  $u = strtoupper(substr($v, -1));
  $n = (float) $v;
  if ($u === 'G') { $n *= 1073741824; }
  elseif ($u === 'M') { $n *= 1048576; }
  elseif ($u === 'K') { $n *= 1024; }
  return (int) $n;
}
$o = array(
  'probe' => 'ok',
  'php' => PHP_VERSION,
  'memory_limit_bytes' => _boa_shorthand_bytes(ini_get('memory_limit')),
  'opcache_fn' => 0, 'opcache_ini_enable' => 0, 'opcache_enabled' => 0,
  'opcache_restricted' => 0,
  'opcache_used_bytes' => 0, 'opcache_free_bytes' => 0, 'opcache_wasted_bytes' => 0,
  'opcache_hit_x100' => 0, 'opcache_oom_restarts' => 0, 'opcache_hash_restarts' => 0,
  'opcache_cached_scripts' => 0, 'opcache_cached_keys' => 0, 'opcache_max_keys' => 0,
  'opcache_conf_bytes' => 0, 'opcache_max_files' => 0,
  'apcu_fn' => 0, 'apcu_enabled' => 0,
  'apcu_seg_bytes' => 0, 'apcu_avail_bytes' => 0,
  'apcu_entries' => 0, 'apcu_expunges' => 0, 'apcu_conf_bytes' => 0,
);
if (function_exists('opcache_get_status')) {
  $o['opcache_fn'] = 1;
  $o['opcache_ini_enable'] = ((int) ini_get('opcache.enable') === 1) ? 1 : 0;
  /* opcache.memory_consumption is a plain megabytes number, not shorthand */
  $o['opcache_conf_bytes'] = ((int) ini_get('opcache.memory_consumption')) * 1048576;
  $o['opcache_max_files'] = (int) ini_get('opcache.max_accelerated_files');
  $s = @opcache_get_status(false);
  if (!is_array($s) && $o['opcache_ini_enable'] === 1) {
    /* enabled per ini but status unavailable: in FPM this means the script
       path is outside opcache.restrict_api */
    $o['opcache_restricted'] = 1;
  }
  if (is_array($s)) {
    $o['opcache_enabled'] = empty($s['opcache_enabled']) ? 0 : 1;
    if (isset($s['memory_usage']) && is_array($s['memory_usage'])) {
      $m = $s['memory_usage'];
      $o['opcache_used_bytes'] = (int) $m['used_memory'];
      $o['opcache_free_bytes'] = (int) $m['free_memory'];
      $o['opcache_wasted_bytes'] = (int) $m['wasted_memory'];
    }
    if (isset($s['opcache_statistics']) && is_array($s['opcache_statistics'])) {
      $t = $s['opcache_statistics'];
      $o['opcache_hit_x100'] = (int) round(((float) $t['opcache_hit_rate']) * 100);
      $o['opcache_oom_restarts'] = (int) $t['oom_restarts'];
      $o['opcache_hash_restarts'] = (int) $t['hash_restarts'];
      $o['opcache_cached_scripts'] = (int) $t['num_cached_scripts'];
      $o['opcache_cached_keys'] = (int) $t['num_cached_keys'];
      $o['opcache_max_keys'] = (int) $t['max_cached_keys'];
    }
  }
}
if (function_exists('apcu_sma_info') && function_exists('apcu_cache_info')) {
  $o['apcu_fn'] = 1;
  $o['apcu_conf_bytes'] = _boa_shorthand_bytes(ini_get('apc.shm_size'));
  $sma = @apcu_sma_info(true);
  if (is_array($sma) && isset($sma['seg_size'])) {
    $o['apcu_enabled'] = 1;
    $o['apcu_seg_bytes'] = (int) (((int) $sma['num_seg']) * ((float) $sma['seg_size']));
    $o['apcu_avail_bytes'] = (int) $sma['avail_mem'];
  }
  $ci = @apcu_cache_info(true);
  if (is_array($ci)) {
    $o['apcu_entries'] = (int) (isset($ci['num_entries']) ? $ci['num_entries'] : 0);
    $o['apcu_expunges'] = (int) (isset($ci['expunges']) ? $ci['expunges'] : 0);
  }
}
echo json_encode($o);
BOAPROBE
  chown root:root "${_PROBE_PHP}.tmp" &> /dev/null
  chmod 0644 "${_PROBE_PHP}.tmp"
  mv -f "${_PROBE_PHP}.tmp" "${_PROBE_PHP}"
}
_ensure_probe_php

_HOST=$(hostname -f 2>/dev/null || hostname)
_TS=$(date +%s)
_OUT="${_pthDat}/$(date +%Y%m%d).jsonl"

# Query an FPM internal path over a unix socket. $1=socket $2=path $3=query
_fcgi_get() {
  SCRIPT_NAME="$2" SCRIPT_FILENAME="$2" QUERY_STRING="$3" REQUEST_METHOD=GET \
    timeout 5 cgi-fcgi -bind -connect "$1" 2>/dev/null
}
# Sanitise to a non-negative integer (default 0).
_num()  { local _x="${1//[^0-9]/}"; printf '%s' "${_x:-0}"; }
# First integer value of "key":N (summary scalars precede the processes array, so
# head -n1 picks the master/summary value for keys that also appear per-process).
_jint() { printf '%s' "$1" | grep -o "\"$2\":[0-9]*" | head -n1 | grep -o '[0-9]*$'; }
# Max integer over all occurrences of "key":N (per-process fields).
_jmax() { printf '%s' "$1" | grep -o "\"$2\":[0-9]*" | grep -o '[0-9]*$' | sort -n | tail -n1; }
# First string value of "key":"...".
_jstr() { printf '%s' "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -n1 | cut -d'"' -f4; }
# Parse pool socket name: sets _pool/_user/_ver (system pool is wwwNN, no dot);
# returns non-zero when no numeric version can be derived.
_parse_pool() {
  _pool=${1##*/}; _pool=${_pool%.fpm.socket}
  if [[ "${_pool}" =~ ^www[0-9]+$ ]]; then
    _user="www"; _ver="${_pool#www}"
  else
    _user="${_pool%.*}"; _ver="${_pool##*.}"
  fi
  [[ "${_ver}" =~ ^[0-9]+$ ]]
}

#
# Pass 1 — version discovery + per-version worker USS, BEFORE any socket
# traffic. Workers are direct children of the version master; private
# (Clean+Dirty) from smaps_rollup ~= USS, the honest marginal cost of one
# worker (RSS would double-count the shared opcache/APCu/code pages).
_VERS_SEEN=""
for _sock in "${_socks[@]}"; do
  [ -S "${_sock}" ] || continue
  _parse_pool "${_sock}" || continue
  # Remember each version's wwwNN socket (preferred probe target; restrict_api).
  # Captured before the dedup skip: www sockets sort after the user pools.
  if [[ "${_pool}" =~ ^www[0-9]+$ ]]; then
    _t="_VWSOCK_${_ver}"
    [ -z "${!_t}" ] && printf -v "_VWSOCK_${_ver}" '%s' "${_sock}"
  fi
  case " ${_VERS_SEEN} " in
    *" ${_ver} "*) continue ;;
  esac
  _mpid=$(pgrep -f "/opt/php${_ver}/etc/php${_ver}-fpm.conf" 2>/dev/null | head -n1)
  # Cold version (master down): no signal, skip its pools and its probe.
  [ -n "${_mpid}" ] || continue
  _VERS_SEEN="${_VERS_SEEN} ${_ver}"
  printf -v "_VPID_${_ver}"  '%s' "${_mpid}"
  printf -v "_VSOCK_${_ver}" '%s' "${_sock}"
  printf -v "_VPOOL_${_ver}" '%s' "${_pool}"
  _uss_kb=0; _nkids=0
  for _k in $(pgrep -P "${_mpid}" 2>/dev/null); do
    _pk=$(awk '/^Private_(Clean|Dirty):/ { s += $2 } END { print s + 0 }' \
      "/proc/${_k}/smaps_rollup" 2>/dev/null)
    if [ -n "${_pk}" ] && [ "${_pk}" -gt 0 ] 2>/dev/null; then
      _uss_kb=$(( _uss_kb + _pk ))
      _nkids=$(( _nkids + 1 ))
    fi
  done
  _avg_uss=0
  [ "${_nkids}" -gt 0 ] && _avg_uss=$(( _uss_kb / _nkids ))
  printf -v "_VUSS_${_ver}" '%s' "${_avg_uss}"
  printf -v "_VNK_${_ver}"  '%s' "${_nkids}"
done
[ -n "${_VERS_SEEN}" ] || exit 0

#
# Pass 2 — per-pool pm.status -> pool records.
for _sock in "${_socks[@]}"; do
  [ -S "${_sock}" ] || continue
  _parse_pool "${_sock}" || continue
  case " ${_VERS_SEEN} " in
    *" ${_ver} "*) : ;;
    *) continue ;;
  esac
  _t="_VPID_${_ver}"; _mpid="${!_t}"
  _st=$(_fcgi_get "${_sock}" /fpm-status "json&full")
  printf '%s' "${_st}" | grep -q '"pool"' || continue

  _mstart=$(_num "$(_jint "${_st}" "start time")")
  _acc=$(_num "$(_jint "${_st}" "accepted conn")")
  _active=$(_num "$(_jint "${_st}" "active processes")")
  _idle=$(_num "$(_jint "${_st}" "idle processes")")
  _total=$(_num "$(_jint "${_st}" "total processes")")
  _maxact=$(_num "$(_jint "${_st}" "max active processes")")
  _mcr=$(_num "$(_jint "${_st}" "max children reached")")
  _lq=$(_num "$(_jint "${_st}" "listen queue")")
  _mlq=$(_num "$(_jint "${_st}" "max listen queue")")
  _slow=$(_num "$(_jint "${_st}" "slow requests")")
  # peak_req_mem: max per-process "last request memory" (bytes). On pools with
  # real traffic the max dominates; on probe-only pools this may be 0 or the
  # probe's own small footprint — Phase 4 treats tiny values as idle noise.
  _peak=$(_num "$(_jmax "${_st}" "last request memory")")
  # First live pool of a version supplies master_start for its version record.
  _t="_VMST_${_ver}"
  [ -z "${!_t}" ] && printf -v "_VMST_${_ver}" '%s' "${_mstart}"

  _rec="{\"scope\":\"pool\",\"ts\":${_TS},\"host\":\"${_HOST}\",\"pool\":\"${_pool}\",\"user\":\"${_user}\",\"version\":${_ver},\"master_pid\":${_mpid},\"master_start\":${_mstart},\"accepted_conn\":${_acc},\"active\":${_active},\"idle\":${_idle},\"total\":${_total},\"max_active\":${_maxact},\"max_children_reached\":${_mcr},\"listen_queue\":${_lq},\"max_listen_queue\":${_mlq},\"slow_requests\":${_slow},\"peak_req_mem\":${_peak}}"
  echo "${_rec}" >> "${_OUT}"
  [ "${_STDOUT}" = "YES" ] && echo "${_rec}"
done

#
# Pass 3 — one opcache/APCu probe per live version (segments are shared across
# that version's pools), merged with the pass-1 USS numbers -> version records.
for _ver in ${_VERS_SEEN}; do
  _t="_VPID_${_ver}";  _vpid="${!_t}"
  _t="_VSOCK_${_ver}"; _vsock="${!_t}"
  _t="_VPOOL_${_ver}"; _vpool="${!_t}"
  _t="_VUSS_${_ver}";  _vuss="${!_t}"
  _t="_VNK_${_ver}";   _vnk="${!_t}"
  _t="_VMST_${_ver}";  _vmst="${!_t}"
  [ -z "${_vmst}" ] && _vmst=0

  # Prefer the version's wwwNN socket: only the system pool (no open_basedir)
  # can execute the probe under /var/www, where opcache.restrict_api allows the
  # status API. Fall back to the first pool socket (opcache reports restricted).
  _t="_VWSOCK_${_ver}"; _vwsock="${!_t}"
  if [ -n "${_vwsock}" ] && [ -S "${_vwsock}" ]; then
    _vtsock="${_vwsock}"
    _vtpool="${_vwsock##*/}"; _vtpool=${_vtpool%.fpm.socket}
  else
    _vtsock="${_vsock}"
    _vtpool="${_vpool}"
  fi

  _pok=0; _php=""
  _mlb=0; _ofn=0; _oie=0; _oen=0; _ores=0
  _oused=0; _ofree=0; _owaste=0; _ohit=0
  _ooom=0; _ohash=0; _oscripts=0; _okeys=0; _omaxkeys=0; _oconf=0; _omaxf=0
  _afn=0; _aen=0; _aseg=0; _aavail=0; _aent=0; _aexp=0; _aconf=0
  _pr=$(_fcgi_get "${_vtsock}" "${_PROBE_PHP}" "")
  if printf '%s' "${_pr}" | grep -q '"probe":"ok"'; then
    _pok=1
    _php=$(_jstr "${_pr}" "php"); _php=${_php//[^A-Za-z0-9._-]/}
    _mlb=$(_num "$(_jint "${_pr}" "memory_limit_bytes")")
    _ofn=$(_num "$(_jint "${_pr}" "opcache_fn")")
    _oie=$(_num "$(_jint "${_pr}" "opcache_ini_enable")")
    _ores=$(_num "$(_jint "${_pr}" "opcache_restricted")")
    _oen=$(_num "$(_jint "${_pr}" "opcache_enabled")")
    _oused=$(_num "$(_jint "${_pr}" "opcache_used_bytes")")
    _ofree=$(_num "$(_jint "${_pr}" "opcache_free_bytes")")
    _owaste=$(_num "$(_jint "${_pr}" "opcache_wasted_bytes")")
    _ohit=$(_num "$(_jint "${_pr}" "opcache_hit_x100")")
    _ooom=$(_num "$(_jint "${_pr}" "opcache_oom_restarts")")
    _ohash=$(_num "$(_jint "${_pr}" "opcache_hash_restarts")")
    _oscripts=$(_num "$(_jint "${_pr}" "opcache_cached_scripts")")
    _okeys=$(_num "$(_jint "${_pr}" "opcache_cached_keys")")
    _omaxkeys=$(_num "$(_jint "${_pr}" "opcache_max_keys")")
    _oconf=$(_num "$(_jint "${_pr}" "opcache_conf_bytes")")
    _omaxf=$(_num "$(_jint "${_pr}" "opcache_max_files")")
    _afn=$(_num "$(_jint "${_pr}" "apcu_fn")")
    _aen=$(_num "$(_jint "${_pr}" "apcu_enabled")")
    _aseg=$(_num "$(_jint "${_pr}" "apcu_seg_bytes")")
    _aavail=$(_num "$(_jint "${_pr}" "apcu_avail_bytes")")
    _aent=$(_num "$(_jint "${_pr}" "apcu_entries")")
    _aexp=$(_num "$(_jint "${_pr}" "apcu_expunges")")
    _aconf=$(_num "$(_jint "${_pr}" "apcu_conf_bytes")")
  else
    echo "$(date) probe failed for php${_ver} via ${_vtsock}" >> "${_pthLog}"
  fi

  _rec="{\"scope\":\"version\",\"ts\":${_TS},\"host\":\"${_HOST}\",\"version\":${_ver},\"master_pid\":${_vpid},\"master_start\":${_vmst},\"probe_pool\":\"${_vtpool}\",\"probe_ok\":${_pok},\"php\":\"${_php}\",\"memory_limit_bytes\":${_mlb},\"opcache_fn\":${_ofn},\"opcache_ini_enable\":${_oie},\"opcache_restricted\":${_ores},\"opcache_enabled\":${_oen},\"opcache_used_bytes\":${_oused},\"opcache_free_bytes\":${_ofree},\"opcache_wasted_bytes\":${_owaste},\"opcache_hit_x100\":${_ohit},\"opcache_oom_restarts\":${_ooom},\"opcache_hash_restarts\":${_ohash},\"opcache_cached_scripts\":${_oscripts},\"opcache_cached_keys\":${_okeys},\"opcache_max_keys\":${_omaxkeys},\"opcache_conf_bytes\":${_oconf},\"opcache_max_files\":${_omaxf},\"apcu_fn\":${_afn},\"apcu_enabled\":${_aen},\"apcu_seg_bytes\":${_aseg},\"apcu_avail_bytes\":${_aavail},\"apcu_entries\":${_aent},\"apcu_expunges\":${_aexp},\"apcu_conf_bytes\":${_aconf},\"avg_child_uss_kb\":${_vuss},\"n_children\":${_vnk}}"
  echo "${_rec}" >> "${_OUT}"
  [ "${_STDOUT}" = "YES" ] && echo "${_rec}"
done

# Prune old daily files.
find "${_pthDat}" -name '*.jsonl' -mtime +${_RETAIN_DAYS} -delete &> /dev/null

exit 0
