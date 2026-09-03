#!/bin/bash
#
# XDR9000 — permanent health/attack archive engine v1 (READ-ONLY harvester).
#
# BOA detects attacks, heals services and samples metrics, then destroys the
# records (hourly ban-log reapers, weekly rotate-4 incident logs, 14/30-day
# JSONL prunes, kernel counters zeroed on every csf reload). This engine copies
# those records into a permanent append-only archive BEFORE the reapers run:
#
#   /var/log/boa/xdr9000/YYYY/MM/events-YYYYMMDD.jsonl   harvested events
#   /var/log/boa/xdr9000/YYYY/MM/samples-YYYYMMDD.jsonl  5-min metric samples
#   /var/log/boa/xdr9000/rollup.jsonl                    one line per day, forever
#   /var/log/boa/xdr9000/.state/                         offsets + stamps
#
# Subdirs of /var/log/boa survive both `rm -f /var/log/boa/*.log` upgrade wipes
# and match no logrotate glob — that is why the archive lives here. Nothing in
# this script ever deletes or truncates archive content; the only writers are
# appends and the month-end gzip of past days' event/sample files.
#
# Three passes per launch (minute.sh relaunches us every fan-out pass):
#   1. harvest  — every launch: inode-tracked byte-offset incremental read of
#                 each source, complete lines only, bounded per pass.
#   2. sample   — at most every ~5 min: load/mem/disk/net/SYNPROXY/csf counts.
#   3. rollup   — first launch after a date change: aggregate YESTERDAY into
#                 rollup.jsonl, then gzip past-month event/sample files.
#
# We harvest the *.archive.log attack ledgers, NOT the web/ssh/ftp.log ban
# queues: same ban records, without racing the hourly/15-min deleters. Losses
# are bounded at one pass (~1 min) before clearwebbans or archive rotation.
#
# Opt-out: _XDR9000=NO in /root/.barracuda.cnf stops all passes; the archive
# is never deleted. Sibling conventions: cf. fpm_tune.sh / sqlprobe.sh.
#
# Operator validation:
#
#   bash xdr9000.sh --force        # run all three passes now (rollup if due)
#

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Byte-exact string handling for the offset arithmetic below.
export LC_ALL=C
export LANG=C

_pthArc="/var/log/boa/xdr9000"
_pthSta="${_pthArc}/.state"
_pthLog="${_pthSta}/xdr9000.log"
_SMP_STAMP="${_pthSta}/.last_sample"
_ROL_STAMP="${_pthSta}/.last_rollup"
_MAX_CHUNK=1048576
_MAX_DETAIL=300

_FORCE=NO
for _arg in "$@"; do
  case "${_arg}" in
    --force)   _FORCE=YES ;;
    -h|--help) echo "Usage: xdr9000.sh [--force]"; exit 0 ;;
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

# Operator opt-out: stop recording, never touch the accumulated archive.
[ "${_XDR9000}" = "NO" ] && exit 0

# Run only on a fully installed system (same guard the sibling monitors use).
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

# Nice ourselves down; this is a background archiver.
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

mkdir -p "${_pthSta}"
chmod 700 "${_pthArc}" "${_pthSta}" &> /dev/null

_now=$(date +%s)
_day_dir="${_pthArc}/$(date +%Y/%m)"
_day_tag=$(date +%Y%m%d)
mkdir -p "${_day_dir}"
_EVENTS="${_day_dir}/events-${_day_tag}.jsonl"
_SAMPLES="${_day_dir}/samples-${_day_tag}.jsonl"

###
### Pass 1 — harvest: inode-tracked incremental line reader.
###
### Copies only the bytes appended since the previous pass, never past the last
### complete line. Offset state is `<inode> <offset>`; an inode change or a
### shrink (rotation, wipe, recreation) resets to 0 so the new file is read
### from its start. Reads are bounded per source per pass; the remainder is
### picked up on subsequent passes via the carried offset.
###
_read_new_lines() {
  local _src="$1" _key="$2"
  local _pos_f="${_pthSta}/${_key}.pos"
  local _tmp_f="${_pthSta}/.chunk.$$"
  [ -f "${_src}" ] || return 1
  local _ino _size
  read -r _ino _size < <(stat -c '%i %s' "${_src}" 2>/dev/null)
  [ -z "${_ino}" ] && return 1
  local _p_ino=0 _p_off=0
  [ -f "${_pos_f}" ] && read -r _p_ino _p_off < "${_pos_f}"
  [[ "${_p_off}" =~ ^[0-9]+$ ]] || _p_off=0
  [ "${_ino}" != "${_p_ino}" ] && _p_off=0
  (( _size < _p_off )) && _p_off=0
  if (( _size <= _p_off )); then
    echo "${_ino} ${_p_off}" > "${_pos_f}"
    return 1
  fi
  local _want=$(( _size - _p_off ))
  (( _want > _MAX_CHUNK )) && _want=${_MAX_CHUNK}
  tail -c "+$(( _p_off + 1 ))" "${_src}" 2>/dev/null \
    | head -c "${_want}" > "${_tmp_f}"
  local _got
  _got=$(stat -c '%s' "${_tmp_f}" 2>/dev/null)
  [[ "${_got}" =~ ^[0-9]+$ ]] || _got=0
  if (( _got == 0 )); then
    rm -f "${_tmp_f}"
    return 1
  fi
  # Trim a trailing partial line: it stays unconsumed for the next pass.
  # `$(tail -c 1)` of a newline collapses to the empty string.
  if [ -n "$(tail -c 1 "${_tmp_f}")" ]; then
    local _part
    _part=$(tail -n 1 "${_tmp_f}" | wc -c)
    if (( _part >= _got )); then
      # No complete line in the chunk yet; wait for more bytes.
      rm -f "${_tmp_f}"
      echo "${_ino} ${_p_off}" > "${_pos_f}"
      return 1
    fi
    truncate -s "$(( _got - _part ))" "${_tmp_f}"
    _got=$(( _got - _part ))
  fi
  echo "${_ino} $(( _p_off + _got ))" > "${_pos_f}"
  echo "${_tmp_f}"
  return 0
}

# JSON string hygiene shared by the awk emitters: escape backslash + quote,
# flatten control bytes, cap length.
_AWK_ESC='function esc(s){gsub(/\\/,"\\\\",s);gsub(/"/,"\\\"",s);gsub(/[^[:print:]]/," ",s);if(length(s)>MAXD)s=substr(s,1,MAXD);return s}'

# Attack ledgers: `<IP> # [xN] <yymmdd-HHMMSS>` (scan_nginx.sh:982, hackcheck.sh:363).
_harvest_attack() {
  local _src="$1" _key="$2" _kind="$3" _tmp_f
  _tmp_f=$(_read_new_lines "${_src}" "${_key}") || return 0
  awk -v T="${_now}" -v K="${_kind}" -v MAXD="${_MAX_DETAIL}" "${_AWK_ESC}"'
    /^[0-9a-fA-F.:]+ # \[x[0-9]+\] / {
      ip=$1; n=$3; sub(/^\[x/,"",n); sub(/\]$/,"",n); m=$4
      printf "{\"t\":%s,\"c\":\"atk\",\"k\":\"%s\",\"ip\":\"%s\",\"n\":%s,\"m\":\"%s\"}\n", T, K, esc(ip), n+0, esc(m)
      next
    }
    NF { printf "{\"t\":%s,\"c\":\"atk\",\"k\":\"%s\",\"d\":\"%s\"}\n", T, K, esc($0) }
  ' "${_tmp_f}" >> "${_EVENTS}"
  rm -f "${_tmp_f}"
}

# Free-text event logs: preserve the raw line under a class/source label.
_harvest_raw() {
  local _src="$1" _key="$2" _class="$3" _label="$4" _tmp_f
  _tmp_f=$(_read_new_lines "${_src}" "${_key}") || return 0
  awk -v T="${_now}" -v C="${_class}" -v S="${_label}" -v MAXD="${_MAX_DETAIL}" "${_AWK_ESC}"'
    NF { printf "{\"t\":%s,\"c\":\"%s\",\"s\":\"%s\",\"d\":\"%s\"}\n", T, C, S, esc($0) }
  ' "${_tmp_f}" >> "${_EVENTS}"
  rm -f "${_tmp_f}"
}

_harvest_pass() {
  local _mon="/var/xdrago/monitor/log"
  _harvest_attack "${_mon}/scan_nginx.archive.log" "atk_web" "web"
  _harvest_attack "${_mon}/hackcheck.archive.log"  "atk_ssh" "ssh"
  _harvest_attack "${_mon}/hackftp.archive.log"    "atk_ftp" "ftp"
  _harvest_raw "${_mon}/i18n_flood.log" "atk_i18n" "atk" "i18n"
  _harvest_raw "${_mon}/segfault_alert.archive.log" "inc_segv" "inc" "segv"
  local _b="/var/log/boa"
  local _i
  for _i in high.load oom nginx mysql mysql.backup php valkey redis unbound java system batch_guard task_guard; do
    _harvest_raw "${_b}/${_i}.incident.log" "inc_${_i//./_}" "inc" "${_i}"
  done
  _harvest_raw "${_b}/oom.incident.old.log" "inc_oom_old" "inc" "oom"
  _harvest_raw "${_b}/sql_watch.log"    "inc_sqlkill"     "inc" "sqlkill"
  _harvest_raw "${_b}/convert.kill.log" "inc_convertkill" "inc" "convertkill"
  # Backup outcome archives (append-only, but wiped by the major-OS-upgrade
  # `rm -f /var/log/boa/*.log` — harvesting preserves them past that).
  local _f _stem
  for _f in "${_b}"/*.archive.log; do
    [ -e "${_f}" ] || continue
    _stem=$(basename "${_f}" .archive.log)
    # autosymlink.verbose is a banner-heavy debug archive, not an outcome
    # record -- and it is already permanent in place; skip the noise.
    [ "${_stem}" = "autosymlink.verbose" ] && continue
    _harvest_raw "${_f}" "bkp_${_stem//[^a-zA-Z0-9_-]/_}" "bkp" "${_stem}"
  done
}

# Verbatim stream copy: the metric corpora are already JSONL, so their lines
# land unchanged in per-day archive streams (provenance via filename).
_harvest_verbatim() {
  local _src="$1" _key="$2" _dst="$3" _tmp_f
  _tmp_f=$(_read_new_lines "${_src}" "${_key}") || return 0
  cat "${_tmp_f}" >> "${_dst}"
  rm -f "${_tmp_f}"
}

###
### Pass 1b — metric corpora: preserve the three rich JSONL time series BOA
### self-prunes (fpm-tune 30d, sqlprobe 30d, loadreport 14d). Every file still
### present in each corpus is offset-tracked, so the first deploy gradually
### backfills the survivors (bounded per pass) and steady state copies only
### fresh lines. Archive names: fpm-/sql-/load-YYYYMMDD.jsonl in the source
### day's YYYY/MM dir. Offset files for vanished source days age out below.
###
_metrics_pass() {
  local _f _tag _dir
  for _f in /var/log/boa/fpm-tune/[0-9]*.jsonl; do
    [ -e "${_f}" ] || continue
    _tag=$(basename "${_f}" .jsonl)
    [[ "${_tag}" =~ ^[0-9]{8}$ ]] || continue
    _dir="${_pthArc}/${_tag:0:4}/${_tag:4:2}"
    mkdir -p "${_dir}"
    _harvest_verbatim "${_f}" "met_fpm_${_tag}" "${_dir}/fpm-${_tag}.jsonl"
  done
  for _f in /var/log/boa/sqlprobe/[0-9]*.jsonl; do
    [ -e "${_f}" ] || continue
    _tag=$(basename "${_f}" .jsonl)
    [[ "${_tag}" =~ ^[0-9]{8}$ ]] || continue
    _dir="${_pthArc}/${_tag:0:4}/${_tag:4:2}"
    mkdir -p "${_dir}"
    _harvest_verbatim "${_f}" "met_sql_${_tag}" "${_dir}/sql-${_tag}.jsonl"
  done
  for _f in /var/log/boa/load-profile/[0-9]*-[0-9]*-[0-9]*.jsonl; do
    [ -e "${_f}" ] || continue
    _tag=$(basename "${_f}" .jsonl)
    _tag="${_tag//-/}"
    [[ "${_tag}" =~ ^[0-9]{8}$ ]] || continue
    _dir="${_pthArc}/${_tag:0:4}/${_tag:4:2}"
    mkdir -p "${_dir}"
    _harvest_verbatim "${_f}" "met_load_${_tag}" "${_dir}/load-${_tag}.jsonl"
  done
  # A consumed source file keeps its .pos mtime fresh every pass; once the
  # corpus prunes the file, the .pos stops being touched and ages out here.
  find "${_pthSta}" -name 'met_*.pos' -mtime +7 -delete 2>/dev/null
}

###
### Pass 2 — sample: one JSONL line of gauges + reset-floored counter deltas.
###
_counter_delta() {
  # args: key current-value -> prints delta since the previous sample.
  # No previous baseline (first run) and counter resets both floor to 0.
  local _key="$1" _cur="$2" _prev=0 _had=0
  local _prev_f="${_pthSta}/.prev_${_key}"
  if [ -f "${_prev_f}" ]; then
    _had=1
    read -r _prev < "${_prev_f}"
  fi
  [[ "${_prev}" =~ ^[0-9]+$ ]] || _prev=0
  [[ "${_cur}"  =~ ^[0-9]+$ ]] || _cur=0
  echo "${_cur}" > "${_prev_f}"
  if (( _had == 0 )); then
    echo 0
  elif (( _cur >= _prev )); then
    echo $(( _cur - _prev ))
  else
    echo 0
  fi
}

_sample_pass() {
  if [ "${_FORCE}" != "YES" ] && [ -e "${_SMP_STAMP}" ] \
    && [ -z "$(find "${_SMP_STAMP}" -mmin +4 2>/dev/null)" ]; then
    return 0
  fi
  touch "${_SMP_STAMP}"
  local _l1 _l5 _l15 _rest
  read -r _l1 _l5 _l15 _rest < /proc/loadavg
  local _mem_kb _swp_t _swp_f
  _mem_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  _swp_t=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  _swp_f=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
  local _swp_used=$(( ${_swp_t:-0} - ${_swp_f:-0} ))
  local _dsk_root _dsk_data
  _dsk_root=$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  _dsk_data=$(df -P /data 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  local _tier="normal"
  [ -e "/run/spider_load.pid" ]   && _tier="spider"
  [ -e "/run/max_load.pid" ]      && _tier="max"
  [ -e "/run/critical_load.pid" ] && _tier="critical"
  local _ifc _rx=0 _tx=0
  _ifc=$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')
  if [ -n "${_ifc}" ]; then
    read -r _rx _tx < <(awk -v I="${_ifc}:" '$1 == I {print $2, $10}' /proc/net/dev)
  fi
  local _rx_d _tx_d
  _rx_d=$(_counter_delta "net_rx" "${_rx:-0}")
  _tx_d=$(_counter_delta "net_tx" "${_tx:-0}")
  local _syn=0 _syn_d=0
  if iptables -nvxL SYNPROXY_EARLY &> /dev/null; then
    _syn=$(iptables -nvxL SYNPROXY_EARLY 2>/dev/null | awk 'NR>2 {s+=$1} END {print s+0}')
    _syn_d=$(_counter_delta "synproxy" "${_syn}")
  fi
  local _deny=0 _tban=0
  [ -f "/etc/csf/csf.deny" ] \
    && _deny=$(grep -c '^[0-9a-fA-F]' /etc/csf/csf.deny 2>/dev/null)
  [ -f "/var/lib/csf/csf.tempban" ] \
    && _tban=$(wc -l < /var/lib/csf/csf.tempban 2>/dev/null)
  printf '{"t":%s,"c":"smp","l1":%s,"l5":%s,"l15":%s,"mem":%s,"swp":%s,"dr":%s,"dd":%s,"tier":"%s","rx":%s,"tx":%s,"rxd":%s,"txd":%s,"syn":%s,"synd":%s,"deny":%s,"tban":%s}\n' \
    "${_now}" "${_l1:-0}" "${_l5:-0}" "${_l15:-0}" "${_mem_kb:-0}" "${_swp_used}" \
    "${_dsk_root:-0}" "${_dsk_data:-0}" "${_tier}" "${_rx:-0}" "${_tx:-0}" \
    "${_rx_d}" "${_tx_d}" "${_syn}" "${_syn_d}" "${_deny:-0}" "${_tban:-0}" \
    >> "${_SAMPLES}"
}

###
### Pass 2b — box facts: one hourly `fct` record in the samples stream with
### what `boa info` derives live and never stores: kernel, CPU count, RAM,
### swap, per-mount disk space, uptime, and the boa-info service verdicts
### (same pidfile map, same not-installed gates, same dead-pid rule).
###
_FCT_STAMP="${_pthSta}/.last_fact"
_svc_down=""
_svc_total=0

_svc_check() {
  # args: name pidfile [absence-marker] — mirrors boa's _display_time: the
  # marker excuses the service only when it would otherwise count as down.
  local _n="$1" _p="$2" _m="$3" _pid=""
  if [ -f "${_p}" ]; then
    _pid=$(head -n 1 "${_p}" 2>/dev/null | tr -dc '0-9')
  fi
  if [ -n "${_pid}" ] && ps -p "${_pid}" > /dev/null 2>&1; then
    (( _svc_total++ ))
    return
  fi
  if [ -n "${_m}" ] && [ ! -e "${_m}" ]; then
    return
  fi
  (( _svc_total++ ))
  _svc_down="${_svc_down:+${_svc_down},}\"${_n}\""
}

_fact_pass() {
  if [ "${_FORCE}" != "YES" ] && [ -e "${_FCT_STAMP}" ] \
    && [ -z "$(find "${_FCT_STAMP}" -mmin +55 2>/dev/null)" ]; then
    return 0
  fi
  touch "${_FCT_STAMP}"
  local _kernel _ncpu _mem_t _mem_a _swp_t _swp_f _up
  _kernel=$(uname -r)
  _ncpu=$(nproc 2>/dev/null)
  _mem_t=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  _mem_a=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  _swp_t=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
  _swp_f=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)
  _up=$(awk '{print int($1)}' /proc/uptime)
  local _disks=""
  local _dev _sz _us _av _pct _mnt
  while read -r _dev _sz _us _av _pct _mnt; do
    case "${_mnt}" in
      /|/data)
        _disks="${_disks:+${_disks},}{\"m\":\"${_mnt}\",\"sz\":${_sz},\"us\":${_us},\"av\":${_av}}"
      ;;
    esac
  done < <(df -P -k / /data 2>/dev/null | awk 'NR > 1' | sort -u)
  _svc_down=""
  _svc_total=0
  _svc_check sshd      /run/sshd.pid
  _svc_check crond     /run/crond.pid
  _svc_check postfix   /var/spool/postfix/pid/master.pid
  _svc_check nginx     /run/nginx.pid
  local _e
  for _e in 56 70 71 72 73 74 80 81 82 83 84 85; do
    _svc_check "php${_e}-fpm" "/run/php${_e}-fpm.pid" "/opt/php${_e}/bin/php"
  done
  _svc_check mysql     /run/mysqld/mysqld.pid
  _svc_check valkey    /run/valkey/valkey.pid
  _svc_check jenkins   /run/jenkins/jenkins.pid   /var/lib/jenkins
  _svc_check solr9     /var/solr9/solr-9099.pid   /var/solr9/logs/solr.log
  _svc_check solr7     /var/solr7/solr-9077.pid   /var/solr7/logs/solr.log
  _svc_check solr4     /run/jetty9.pid            /opt/solr4/solr.xml
  _svc_check pure-ftpd /run/pure-ftpd.pid         /usr/local/sbin/pure-ftpd
  _svc_check lfd       /run/lfd.pid
  _svc_check rsyslogd  /run/rsyslogd.pid
  _svc_check unbound   /run/unbound/unbound.pid
  _svc_check vnstat    /run/vnstat/vnstat.pid
  printf '{"t":%s,"c":"fct","kernel":"%s","ncpu":%s,"mem_total":%s,"mem_avail":%s,"swp_total":%s,"swp_used":%s,"up":%s,"disks":[%s],"svc":%s,"down":[%s]}\n' \
    "${_now}" "${_kernel}" "${_ncpu:-0}" "${_mem_t:-0}" "${_mem_a:-0}" \
    "${_swp_t:-0}" "$(( ${_swp_t:-0} - ${_swp_f:-0} ))" "${_up:-0}" \
    "${_disks}" "${_svc_total}" "${_svc_down}" >> "${_SAMPLES}"
}

###
### Pass 3 — rollup: aggregate yesterday into the permanent per-day spine,
### then gzip event/sample files from past months.
###
_rollup_pass() {
  local _today _last _y_tag _y_dir
  _today=$(date +%F)
  _last=""
  [ -f "${_ROL_STAMP}" ] && read -r _last < "${_ROL_STAMP}"
  [ "${_last}" = "${_today}" ] && return 0
  _y_tag=$(date -d yesterday +%Y%m%d 2>/dev/null) || return 0
  _y_dir="${_pthArc}/$(date -d yesterday +%Y/%m)"
  local _ev="${_y_dir}/events-${_y_tag}.jsonl"
  local _sm="${_y_dir}/samples-${_y_tag}.jsonl"
  local _host _boa
  _host=$(hostname -f 2>/dev/null) || _host=$(hostname)
  _boa=$(tail -n 1 /var/log/barracuda_log.txt 2>/dev/null \
    | grep -oE 'Barracuda [^ /]+' | awk '{print $2}')
  {
    printf '{"c":"day","date":"%s","h":"%s","v":"%s"' \
      "$(date -d yesterday +%F)" "${_host}" "${_boa:-unknown}"
    if [ -s "${_ev}" ]; then
      awk '
        /"c":"atk","k":"web"/ { web++; if (match($0, /"ip":"[^"]+"/)) ips[substr($0, RSTART+6, RLENGTH-7)] = 1 }
        /"c":"atk","k":"ssh"/ { ssh++; if (match($0, /"ip":"[^"]+"/)) ips[substr($0, RSTART+6, RLENGTH-7)] = 1 }
        /"c":"atk","k":"ftp"/ { ftp++; if (match($0, /"ip":"[^"]+"/)) ips[substr($0, RSTART+6, RLENGTH-7)] = 1 }
        /"c":"atk","s":"i18n"/ { i18n++ }
        /"c":"inc"/ { inc++ }
        /"c":"bkp"/ { bkp++ }
        END {
          u=0; for (i in ips) u++
          printf ",\"atk_web\":%d,\"atk_ssh\":%d,\"atk_ftp\":%d,\"atk_i18n\":%d,\"uniq_ip\":%d,\"inc\":%d,\"bkp\":%d", web+0, ssh+0, ftp+0, i18n+0, u, inc+0, bkp+0
        }
      ' "${_ev}"
    else
      printf ',"atk_web":0,"atk_ssh":0,"atk_ftp":0,"atk_i18n":0,"uniq_ip":0,"inc":0,"bkp":0'
    fi
    if [ -s "${_sm}" ]; then
      awk '
        !/"c":"smp"/ { next }
        { if (match($0, /"l1":[0-9.]+/))   { v=substr($0, RSTART+5, RLENGTH-5)+0; if (v>l1max) l1max=v }
          if (match($0, /"rxd":[0-9]+/))   { rx+=substr($0, RSTART+6, RLENGTH-6)+0 }
          if (match($0, /"txd":[0-9]+/))   { tx+=substr($0, RSTART+6, RLENGTH-6)+0 }
          if (match($0, /"synd":[0-9]+/))  { syn+=substr($0, RSTART+7, RLENGTH-7)+0 }
          if (match($0, /"deny":[0-9]+/))  { v=substr($0, RSTART+7, RLENGTH-7)+0; if (v>dmax) dmax=v }
          n++ }
        END { printf ",\"l1_max\":%s,\"net_rx\":%.0f,\"net_tx\":%.0f,\"syn\":%.0f,\"deny_max\":%d,\"smp\":%d", l1max+0, rx+0, tx+0, syn+0, dmax+0, n+0 }
      ' "${_sm}"
    else
      printf ',"l1_max":0,"net_rx":0,"net_tx":0,"syn":0,"deny_max":0,"smp":0'
    fi
    printf '}\n'
  } >> "${_pthArc}/rollup.jsonl"
  echo "${_today}" > "${_ROL_STAMP}"
  # Compress event/sample files from past months (never rollup.jsonl, never
  # the current month, never anything younger than a day).
  find "${_pthArc}" -mindepth 3 -name '*.jsonl' \
    ! -path "*/$(date +%Y/%m)/*" -mtime +1 -exec gzip -9 {} \; 2>/dev/null
}

_harvest_pass
_metrics_pass
_sample_pass
_fact_pass
_rollup_pass

exit 0
