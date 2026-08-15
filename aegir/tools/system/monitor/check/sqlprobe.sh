#!/bin/bash
#
# BOA SQL sensor — sqlprobe v1.0 (C-004 Phase 2, LOG-ONLY).
#
# Appends one JSONL record per ~5 min to /var/log/boa/sqlprobe/<date>.jsonl:
# per-second rates between THIS sample and the previous one (never cumulative
# lifetime averages — those carry warmup bias), pool/connection gauges, and
# host memory facts (MemAvailable, PSI when present, mysqld VmRSS from
# /proc/<pid>/status — not a ps RSS sweep, which over-counts shared pages).
# It writes NO my.cnf, runs NO SET GLOBAL, restarts NOTHING. The memorytuner
# advisory reads this corpus and names pins; a human applies them.
#
# Three side facts keep the shipped tune-pass stores fresh between weekly
# upgrades (formats byte-identical to the readers in system.sh.inc; the
# readers fail-close on anything malformed, so a missing/stale sampler
# never degrades tuning below the historical behaviour):
#   - /var/log/boa/.my.datadir_mb.txt   refreshed ~daily (same du exclusions)
#   - /var/log/boa/.valkey.used_mb.txt  seeded from used_memory_peak once the
#     cache has >= 1h uptime — the up-* password rotation restarts valkey
#     minutes before the tune pass, so tune-time measurement alone stays
#     dormant on standard runs; this store is what un-dormants it.
#   - /var/log/boa/.valkey.demand.txt   the RM-14 hit-rate demand window
#     ("v1 <start_ts> <samples> <hits> <misses> <evicted> <peak_mb>",
#     7-day decaying accumulation of >=1h-uptime same-run deltas) — the
#     PRIMARY input to the valkey ceiling control loop in
#     _tune_memory_limits; the legacy peak-x4 guard is only its fallback.
#     NB: _USE_SQLPROBE=NO therefore also starves that loop — after 8
#     days the tune pass reverts to the legacy measured guard.
#
# Samples are SKIPPED (silent exit) while backups/cache-droppers run and for
# 20 min after (mysql_backup.sh drops caches unconditionally), during
# barracuda runs (mysqld may restart mid-sample), during run-to-* system
# transitions, and whenever mysqld is absent — downtime is mysql.sh's job.
# Opt-out: _USE_SQLPROBE=NO in /root/.barracuda.cnf (unset means ON).
#
# Operator validation:
#
#   bash sqlprobe.sh --force --stdout      # sample once, print + store record
#
# Conventions: BOA monitor sibling (cf. fpm_tune.sh / mysql.sh). No systemd.
# Parser is dependency-free (grep/cut/awk) to match the other monitors.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthDat="/var/log/boa/sqlprobe"
_pthLog="${_pthDat}/sqlprobe.log"
_STAMP="${_pthDat}/.last_run"
_PREV="${_pthDat}/.prev_status"
_BKP_STAMP="${_pthDat}/.backup_seen"
_RETAIN_DAYS=30
_DATADIR_STORE="/var/log/boa/.my.datadir_mb.txt"
_VALKEY_STORE="/var/log/boa/.valkey.used_mb.txt"
_VALKEY_DEMAND="/var/log/boa/.valkey.demand.txt"
_VK_PREV="${_pthDat}/.prev_valkey"

_FORCE=NO
_STDOUT=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)   _FORCE=YES ;;
    --stdout)  _STDOUT=YES ;;
    -h|--help) echo "Usage: sqlprobe.sh [--force] [--stdout]"; exit 0 ;;
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

# Opt-out (policy: default ON fleet-wide; NO disables).
[ "${_USE_SQLPROBE}" = "NO" ] && exit 0

# Major system transition in flight: measurements would be noise.
for _rt in excalibur daedalus chimaera beowulf; do
  [ -e "/root/.run-to-${_rt}.cnf" ] && exit 0
done

# Barracuda run in flight: it may restart mysqld under us mid-sample.
[ -e "/run/boa_run.pid" ] && exit 0
# Same for an install/upgrade leg, which holds only this marker mid-chain.
[ -e "/run/octopus_install_run.pid" ] && exit 0

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

# Backup / cache-drop exclusion: skip while any backup walker is alive and for
# 20 min after the last sighting (mysql_backup.sh drops caches unconditionally,
# which poisons both the miss rates and MemAvailable).
if pgrep -f "[m]ysql_backup" >/dev/null 2>&1 \
  || pgrep -f "[d]uplicity" >/dev/null 2>&1 \
  || pgrep -f "[m]ydumper" >/dev/null 2>&1; then
  touch "${_BKP_STAMP}"
  exit 0
fi
if [ -e "${_BKP_STAMP}" ] \
  && [ -z "$(find "${_BKP_STAMP}" -mmin +20 2>/dev/null)" ]; then
  exit 0
fi

# mysqld must be answering; its downtime is mysql.sh's business, not ours.
if [ ! -S "/run/mysqld/mysqld.sock" ] && [ ! -S "/var/run/mysqld/mysqld.sock" ]; then
  exit 0
fi
_ST=$(timeout 10 mysql -u root -Nse "SHOW GLOBAL STATUS" 2>/dev/null)
[ -n "${_ST}" ] || exit 0
_VR=$(timeout 10 mysql -u root -Nse "SHOW GLOBAL VARIABLES" 2>/dev/null)
[ -n "${_VR}" ] || exit 0

# Sanitise to a non-negative integer (default 0).
_num() { local _x="${1//[^0-9]/}"; printf '%s' "${_x:-0}"; }
# TAB-separated -Nse output: value of a STATUS / VARIABLES row.
_sv() { printf '%s\n' "${_ST}" | grep -m1 "^${1}	" | cut -f2; }
_vv() { printf '%s\n' "${_VR}" | grep -m1 "^${1}	" | cut -f2; }

_TS=$(date +%s)
_HOST=$(hostname -f 2>/dev/null || hostname)
_OUT="${_pthDat}/$(date +%Y%m%d).jsonl"

_UP=$(_num "$(_sv Uptime)")
_LREAD=$(_num "$(_sv Innodb_buffer_pool_read_requests)")
_MISS=$(_num "$(_sv Innodb_buffer_pool_reads)")
_TMPT=$(_num "$(_sv Created_tmp_tables)")
_TMPD=$(_num "$(_sv Created_tmp_disk_tables)")
_KEYR=$(_num "$(_sv Key_reads)")
_DREAD=$(_num "$(_sv Innodb_data_read)")
_DWRIT=$(_num "$(_sv Innodb_data_written)")
_QUEST=$(_num "$(_sv Questions)")
_CONNS=$(_num "$(_sv Connections)")
_PGTOT=$(_num "$(_sv Innodb_buffer_pool_pages_total)")
_PGFREE=$(_num "$(_sv Innodb_buffer_pool_pages_free)")
_THRC=$(_num "$(_sv Threads_connected)")
_THRR=$(_num "$(_sv Threads_running)")
_MAXUSED=$(_num "$(_sv Max_used_connections)")

_POOL_B=$(_num "$(_vv innodb_buffer_pool_size)")
_TMPSZ_B=$(_num "$(_vv tmp_table_size)")
_MAXCONN=$(_num "$(_vv max_connections)")

#
# Rates between this sample and the previous snapshot. A delta is valid only
# when a previous snapshot exists, mysqld did not restart between them
# (Uptime monotone), and the gap is one to fifteen minutes — longer gaps span
# skipped windows (backups, load pauses) and would smear their aftermath.
_VALID=0
_IVL=0
_lread_ps=0; _miss_ps=0; _miss_ppm=0; _qps=0; _conn_ps=0
_tmp_ps=0; _tmpd_ps=0; _keyr_ps=0; _dread_bps=0; _dwrit_bps=0
if [ -r "${_PREV}" ]; then
  # shellcheck disable=SC2034
  read -r _pTS _pUP _pLREAD _pMISS _pTMPT _pTMPD _pKEYR _pDREAD _pDWRIT \
    _pQUEST _pCONNS < "${_PREV}"
  _pTS=$(_num "${_pTS}"); _pUP=$(_num "${_pUP}")
  _IVL=$(( _TS - _pTS ))
  if [ "${_pTS}" -gt 0 ] && [ "${_UP}" -gt "${_pUP}" ] \
    && [ "${_IVL}" -ge 60 ] && [ "${_IVL}" -le 900 ]; then
    _VALID=1
    _rate() {
      awk -v c="$(_num "$1")" -v p="$(_num "$2")" -v i="${_IVL}" \
        'BEGIN { if (i > 0 && c >= p) printf "%.2f", (c - p) / i; else printf "0" }'
    }
    _lread_ps=$(_rate "${_LREAD}" "${_pLREAD}")
    _miss_ps=$(_rate "${_MISS}" "${_pMISS}")
    _tmp_ps=$(_rate "${_TMPT}" "${_pTMPT}")
    _tmpd_ps=$(_rate "${_TMPD}" "${_pTMPD}")
    _keyr_ps=$(_rate "${_KEYR}" "${_pKEYR}")
    _dread_bps=$(_rate "${_DREAD}" "${_pDREAD}")
    _dwrit_bps=$(_rate "${_DWRIT}" "${_pDWRIT}")
    _qps=$(_rate "${_QUEST}" "${_pQUEST}")
    _conn_ps=$(_rate "${_CONNS}" "${_pCONNS}")
    _miss_ppm=$(awk -v m="${_MISS}" -v pm="$(_num "${_pMISS}")" \
      -v l="${_LREAD}" -v pl="$(_num "${_pLREAD}")" \
      'BEGIN { d = l - pl; if (d > 0 && m >= pm) printf "%.0f", (m - pm) * 1000000 / d; else printf "0" }')
  fi
fi
printf '%s %s %s %s %s %s %s %s %s %s %s\n' \
  "${_TS}" "${_UP}" "${_LREAD}" "${_MISS}" "${_TMPT}" "${_TMPD}" "${_KEYR}" \
  "${_DREAD}" "${_DWRIT}" "${_QUEST}" "${_CONNS}" > "${_PREV}.tmp" \
  && mv -f "${_PREV}.tmp" "${_PREV}"

#
# Host memory facts.
_MEMAVAIL_MB=$(awk '/^MemAvailable:/ { printf "%d", $2 / 1024 }' /proc/meminfo 2>/dev/null)
_MEMAVAIL_MB=$(_num "${_MEMAVAIL_MB}")
_PSI_X100=0
if [ -r "/proc/pressure/memory" ]; then
  _PSI_X100=$(awk '/^some/ { for (f = 2; f <= NF; f++) if ($f ~ /^avg10=/) { sub("avg10=", "", $f); printf "%.0f", $f * 100 } }' \
    /proc/pressure/memory 2>/dev/null)
  _PSI_X100=$(_num "${_PSI_X100}")
fi
_MYPID=$(_num "$(cat /run/mysqld/mysqld.pid 2>/dev/null)")
[ "${_MYPID}" -gt 0 ] 2>/dev/null || _MYPID=$(_num "$(pgrep -x mysqld 2>/dev/null | head -n1)")
_VMRSS_MB=0
if [ "${_MYPID}" -gt 0 ] 2>/dev/null && [ -r "/proc/${_MYPID}/status" ]; then
  _VMRSS_MB=$(awk '/^VmRSS:/ { printf "%d", $2 / 1024 }' "/proc/${_MYPID}/status" 2>/dev/null)
  _VMRSS_MB=$(_num "${_VMRSS_MB}")
fi

#
# Datadir fact, ~daily: same du and exclusions as _sql_budget_derive
# (system.sh.inc), same write idiom; only a successful positive measurement
# may replace the cached value. Never runs inside the backup exclusion —
# we exited above.
if [ ! -e "${_DATADIR_STORE}" ] \
  || [ -n "$(find "${_DATADIR_STORE}" -mmin +1380 2>/dev/null)" ]; then
  _DATADIR_MB=$(timeout 30 nice -n19 du -sm \
    --exclude='ibdata*' --exclude='ib_logfile*' --exclude='ibtmp*' \
    --exclude='#innodb_redo' --exclude='#innodb_temp' --exclude='undo_*' \
    --exclude='binlog.*' --exclude='mysql-bin.*' --exclude='*.log' \
    /var/lib/mysql/ 2>/dev/null | cut -f1)
  _DATADIR_MB="${_DATADIR_MB//[^0-9]/}"
  if [ -n "${_DATADIR_MB}" ] && [ "${_DATADIR_MB}" -gt 0 ]; then
    echo "${_DATADIR_MB}" 2>/dev/null > "${_DATADIR_STORE}" || true
  fi
fi
_DATADIR_MB=$(_num "$(cat "${_DATADIR_STORE}" 2>/dev/null)")

#
# Valkey fact: seed the measured-ceiling store the tune pass reads. Same ACL
# scrape, same >= 1h uptime trust gate, same peak-over-used preference and
# write idiom as the reader in system.sh.inc. Redis-legacy boxes (no
# valkey.conf) are left alone by design.
_VK_SEEDED=0
_VK_MB=0
if [ -e "/etc/valkey/valkey.conf" ]; then
  _VK_PSW=$(grep -m1 "^user default on >" /etc/valkey/valkey.conf 2>/dev/null \
    | sed "s/.*>//; s/ .*//")
  if [ -n "${_VK_PSW}" ]; then
    _VK_INFO=$(timeout 5 valkey-cli -a "${_VK_PSW}" --no-auth-warning INFO 2>/dev/null)
    if [ -z "${_VK_INFO}" ] && [ -S "/run/valkey/valkey.sock" ]; then
      _VK_INFO=$(timeout 5 valkey-cli -s /run/valkey/valkey.sock -a "${_VK_PSW}" --no-auth-warning INFO 2>/dev/null)
    fi
    _VK_USED=$(echo "${_VK_INFO}" | grep "^used_memory:" | cut -d: -f2 | tr -d "[:space:]\r")
    _VK_USED="${_VK_USED//[^0-9]/}"
    _VK_PEAK=$(echo "${_VK_INFO}" | grep "^used_memory_peak:" | cut -d: -f2 | tr -d "[:space:]\r")
    _VK_PEAK="${_VK_PEAK//[^0-9]/}"
    _VK_UPTM=$(echo "${_VK_INFO}" | grep "^uptime_in_seconds:" | cut -d: -f2 | tr -d "[:space:]\r")
    _VK_UPTM="${_VK_UPTM//[^0-9]/}"
    if [ -n "${_VK_PEAK}" ] && [ -n "${_VK_USED}" ] \
      && [ "${_VK_PEAK}" -gt "${_VK_USED}" ]; then
      _VK_USED="${_VK_PEAK}"
    fi
    if [ -n "${_VK_USED}" ] && [ "${_VK_USED}" -gt 0 ] \
      && [ -n "${_VK_UPTM}" ] && [ "${_VK_UPTM}" -ge 3600 ]; then
      _VK_MB=$(( _VK_USED / 1048576 ))
      if [ "${_VK_MB}" -lt 1 ]; then
        _VK_MB=1
      fi
      echo "${_VK_MB}" 2>/dev/null > "${_VALKEY_STORE}" || true
      _VK_SEEDED=1
    fi
    #
    # Demand window for the hit-rate ceiling in _tune_memory_limits
    # (RM-14): occupancy of a long-TTL cache is "space granted so far",
    # not need, so the tune pass sizes from hit/miss/eviction behaviour
    # instead. Deltas follow the SQL-sample discipline exactly — only
    # between two >=1h-uptime samples of the SAME server run (uptime
    # monotone), 1-15 min apart, counters non-decreasing — so restarts
    # and cold refills never pollute the window. The window file is one
    # line, "v1 <start_ts> <samples> <hits> <misses> <evicted> <peak_mb>",
    # atomically replaced, self-rotating at 7 days; the tune-side reader
    # fail-closes on anything malformed, so a missing/garbled window
    # simply keeps the legacy ceiling behaviour.
    _vk_hits_ps=0; _vk_miss_ps=0; _vk_evic_ps=0
    if [ -n "${_VK_UPTM}" ] && [ "${_VK_UPTM}" -ge 3600 ] 2>/dev/null; then
      _VK_HITS=$(echo "${_VK_INFO}" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d "[:space:]\r")
      _VK_HITS=$(_num "${_VK_HITS}")
      _VK_MISS=$(echo "${_VK_INFO}" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d "[:space:]\r")
      _VK_MISS=$(_num "${_VK_MISS}")
      _VK_EVIC=$(echo "${_VK_INFO}" | grep "^evicted_keys:" | cut -d: -f2 | tr -d "[:space:]\r")
      _VK_EVIC=$(_num "${_VK_EVIC}")
      if [ -r "${_VK_PREV}" ]; then
        read -r _vpTS _vpUP _vpHITS _vpMISS _vpEVIC < "${_VK_PREV}"
        _vpTS=$(_num "${_vpTS}"); _vpUP=$(_num "${_vpUP}")
        _vpHITS=$(_num "${_vpHITS}"); _vpMISS=$(_num "${_vpMISS}")
        _vpEVIC=$(_num "${_vpEVIC}")
        _vkIVL=$(( _TS - _vpTS ))
        if [ "${_vpTS}" -gt 0 ] && [ "${_VK_UPTM}" -gt "${_vpUP}" ] \
          && [ "${_vkIVL}" -ge 60 ] && [ "${_vkIVL}" -le 900 ] \
          && [ "${_VK_HITS}" -ge "${_vpHITS}" ] \
          && [ "${_VK_MISS}" -ge "${_vpMISS}" ] \
          && [ "${_VK_EVIC}" -ge "${_vpEVIC}" ]; then
          _vkDH=$(( _VK_HITS - _vpHITS ))
          _vkDM=$(( _VK_MISS - _vpMISS ))
          _vkDE=$(( _VK_EVIC - _vpEVIC ))
          # Two-decimal per-second rates like every sibling _ps key in
          # the record — integer division would floor sub-1/s eviction
          # rates to 0, erasing exactly the signal the widen branch
          # keys on.
          _vk_hits_ps=$(awk -v d="${_vkDH}" -v i="${_vkIVL}" \
            'BEGIN { if (i > 0) printf "%.2f", d / i; else printf "0" }')
          _vk_miss_ps=$(awk -v d="${_vkDM}" -v i="${_vkIVL}" \
            'BEGIN { if (i > 0) printf "%.2f", d / i; else printf "0" }')
          _vk_evic_ps=$(awk -v d="${_vkDE}" -v i="${_vkIVL}" \
            'BEGIN { if (i > 0) printf "%.2f", d / i; else printf "0" }')
          _wOK=0
          if [ -r "${_VALKEY_DEMAND}" ]; then
            read -r _wV _wTS _wN _wH _wM _wE _wP < "${_VALKEY_DEMAND}"
            if [ "${_wV}" = "v1" ]; then
              _wTS=$(_num "${_wTS}"); _wN=$(_num "${_wN}")
              _wH=$(_num "${_wH}"); _wM=$(_num "${_wM}")
              _wE=$(_num "${_wE}"); _wP=$(_num "${_wP}")
              if [ "${_wTS}" -gt 0 ] && [ $(( _TS - _wTS )) -lt 604800 ]; then
                _wOK=1
              elif [ "${_wTS}" -gt 0 ]; then
                # 7-day rotation is a DECAY, never a hard reset: halve
                # the counters and re-anchor the epoch, so the tune-side
                # maturity gate (n>=96, span>=24h) keeps passing on a box
                # that samples continuously — a zeroed window would send
                # the tune pass to its legacy peak-x4 rung for ~a day
                # after every rotation, re-widening a converged ceiling.
                # The peak restarts from the CURRENT sample so a
                # stale-high pre-shrink peak cannot steer the idle rung.
                _wTS="${_TS}"
                _wN=$(( _wN / 2 )); _wH=$(( _wH / 2 ))
                _wM=$(( _wM / 2 )); _wE=$(( _wE / 2 ))
                _wP=0
                _wOK=1
              fi
            fi
          fi
          if [ "${_wOK}" -eq 0 ]; then
            _wTS="${_TS}"; _wN=0; _wH=0; _wM=0; _wE=0; _wP=0
          fi
          _wN=$(( _wN + 1 ))
          _wH=$(( _wH + _vkDH ))
          _wM=$(( _wM + _vkDM ))
          _wE=$(( _wE + _vkDE ))
          if [ "${_VK_MB}" -gt "${_wP}" ]; then
            _wP="${_VK_MB}"
          fi
          printf 'v1 %s %s %s %s %s %s\n' \
            "${_wTS}" "${_wN}" "${_wH}" "${_wM}" "${_wE}" "${_wP}" \
            > "${_VALKEY_DEMAND}.tmp" \
            && mv -f "${_VALKEY_DEMAND}.tmp" "${_VALKEY_DEMAND}"
        fi
      fi
      printf '%s %s %s %s %s\n' \
        "${_TS}" "${_VK_UPTM}" "${_VK_HITS}" "${_VK_MISS}" "${_VK_EVIC}" \
        > "${_VK_PREV}.tmp" && mv -f "${_VK_PREV}.tmp" "${_VK_PREV}"
    fi
  fi
fi
[ "${_VK_MB}" -gt 0 ] 2>/dev/null \
  || _VK_MB=$(_num "$(cat "${_VALKEY_STORE}" 2>/dev/null)")

_POOL_MB=$(( _POOL_B / 1048576 ))
_TMP_MB=$(( _TMPSZ_B / 1048576 ))

_rec="{\"scope\":\"sql\",\"v\":1,\"ts\":${_TS},\"host\":\"${_HOST}\",\"up\":${_UP},\"interval\":${_IVL},\"valid\":${_VALID},\"lread_ps\":${_lread_ps},\"miss_ps\":${_miss_ps},\"miss_ppm\":${_miss_ppm},\"qps\":${_qps},\"conn_ps\":${_conn_ps},\"tmp_ps\":${_tmp_ps},\"tmp_disk_ps\":${_tmpd_ps},\"key_reads_ps\":${_keyr_ps},\"data_read_bps\":${_dread_bps},\"data_write_bps\":${_dwrit_bps},\"pool_pages_total\":${_PGTOT},\"pool_pages_free\":${_PGFREE},\"threads_conn\":${_THRC},\"threads_run\":${_THRR},\"max_used_conn\":${_MAXUSED},\"max_conn\":${_MAXCONN},\"pool_mb\":${_POOL_MB},\"tmp_mb\":${_TMP_MB},\"mem_avail_mb\":${_MEMAVAIL_MB},\"psi_mem_some10_x100\":${_PSI_X100},\"mysqld_vmrss_mb\":${_VMRSS_MB},\"datadir_mb\":${_DATADIR_MB},\"valkey_used_mb\":${_VK_MB},\"valkey_seeded\":${_VK_SEEDED},\"valkey_hits_ps\":${_vk_hits_ps:-0},\"valkey_miss_ps\":${_vk_miss_ps:-0},\"valkey_evicted_ps\":${_vk_evic_ps:-0}}"
echo "${_rec}" >> "${_OUT}"
[ "${_STDOUT}" = "YES" ] && echo "${_rec}"

# Prune old daily files.
find "${_pthDat}" -name '*.jsonl' -mtime +${_RETAIN_DAYS} -delete &> /dev/null

exit 0
