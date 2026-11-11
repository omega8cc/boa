#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

# Duplicity runs in flight, counted from root's processes alone: root's own
# duplicity, and root's mybackup pass, which runs an account's queued restore
# as the account through su. An account's own process is never counted: the
# account's site code runs as its backend user in tasks and can give a
# process any command line.
_dcy_live_count() {
  local _a _b _c
  _a=$(pgrep -u root -U root -fc '^([^ ]*/)?((ba|da)?sh|python[0-9.]*) (-[^ ]+ )*[^ ]*duplicity( |$)' 2> /dev/null)
  _b=$(pgrep -u root -U root -fc '^[^ ]*duplicity( |$)' 2> /dev/null)
  _c=$(pgrep -u root -U root -fc '^([^ ]*/)?((ba|da)?sh|python[0-9.]*) (-[^ ]+ )*[^ ]*mybackup( |$)' 2> /dev/null)
  echo $(( ${_a:-0} + ${_b:-0} + ${_c:-0} ))
}

# Function to check if the script is run as root
_check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script should be run as root"
    exit 1
  else
    # shellcheck disable=SC1091
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    # Sanitize to allow only digits and minus sign
    export _B_NICE=${_B_NICE//[^0-9-]/}

    # Validate and set default if necessary
    if ! [[ "${_B_NICE}" =~ ^-?[0-9]+$ ]]; then
      _B_NICE=0
    fi

    # Clamp the value within -20 to 19
    if (( _B_NICE < -20 )); then
      _B_NICE=-20
    elif (( _B_NICE > 19 )); then
      _B_NICE=19
    fi

    renice ${_B_NICE} -p $$ &> /dev/null
    chmod a+w /dev/null
  fi
  # Get the hostname
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
}
_check_root

# Exit if the operator paused heavy maintenance
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

# PHP-idle surgery quiesce: barracuda holds this while swapping PHP
# versions; a marker whose owner PID is gone is stale (crashed run) and
# is cleared, never obeyed -- and /run clears itself on reboot.
if [ -e "/run/boa_php_idle_quiesce.pid" ]; then
  _qsPid=$( { tr -dc '0-9' < /run/boa_php_idle_quiesce.pid; } 2>/dev/null )
  if [ -n "${_qsPid}" ] && kill -0 "${_qsPid}" 2>/dev/null; then
    exit 0
  fi
  rm -f /run/boa_php_idle_quiesce.pid
fi

# nginx's geoip_country reads /usr/share/GeoIP/GeoIPv6.dat, or GeoIP.dat on a
# box without it: the X-GeoIP-Country headers and the GEOIP_COUNTRY_CODE, CODE3
# and NAME values PHP gets. The IPv6 edition answers IPv4 visitors too, by the
# IPv4-mapped address nginx looks them up by. The distro's copies hold data
# from December 2019, so address blocks that changed hands since name the
# wrong country. Once a month both are rebuilt from DB-IP's IP to Country Lite
# (CC BY 4.0, https://db-ip.com) in the same legacy formats, so the variables
# and the form of their values stay as they were (libGeoIP supplies the
# three-letter code and the name). A new file replaces the old one by a
# rename, only once every range reads back right, and the old one is never
# removed first: nginx does not start without it. A month DB-IP has not
# published yet falls back to the month before; a failed fetch keeps the
# files and is tried again the next night.
_refresh_country_db() {
  local _dat="/usr/share/GeoIP/GeoIP.dat" _dat6="/usr/share/GeoIP/GeoIPv6.dat"
  local _log="/var/log/boa/country-db.log"
  local _now _prev _have _m _tmp _new _new6 _info _got _done
  [ -x "/usr/bin/python3" ] && [ -d "/usr/share/GeoIP" ] || return 0
  # A run killed between its mktemp and its cleanup leaves these behind; a
  # run takes minutes, so half a day apart never meets a live one.
  find /usr/share/GeoIP -maxdepth 1 -type f -name '.GeoIP*.dat.??????' \
    -mmin +720 -delete 2> /dev/null
  find /var/backups -maxdepth 1 -type d -name '.boa-geoip.??????' \
    -mmin +720 -exec rm -rf {} + 2> /dev/null
  _now=$(date -u +%Y-%m)
  _prev=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m)
  # The month both files were built from; none when they differ.
  _have=$(tail -c 120 "${_dat}" 2> /dev/null | tr -c '[:print:]' '\n' \
    | grep -oE 'DB-IP Country Lite [0-9]{4}-[0-9]{2}' | tail -n 1 \
    | grep -oE '[0-9]{4}-[0-9]{2}$')
  _m=$(tail -c 120 "${_dat6}" 2> /dev/null | tr -c '[:print:]' '\n' \
    | grep -oE 'DB-IP Country Lite [0-9]{4}-[0-9]{2}' | tail -n 1 \
    | grep -oE '[0-9]{4}-[0-9]{2}$')
  [ "${_m}" = "${_have}" ] || _have=""
  [ "${_have}" = "${_now}" ] && return 0
  if ! _tmp=$(mktemp -d /var/backups/.boa-geoip.XXXXXX 2> /dev/null); then
    echo "$(date) GeoIP.dat: no work folder in /var/backups, kept ${_have:-the distro data}" >> "${_log}"
    return 0
  fi
  _got=""
  for _m in "${_now}" "${_prev}"; do
    [ "${_m}" = "${_have}" ] && _got=none && break
    curl -fsS --max-time 300 -o "${_tmp}/dbip.csv.gz" \
      "https://download.db-ip.com/free/dbip-country-lite-${_m}.csv.gz" &> /dev/null \
      && gzip -t "${_tmp}/dbip.csv.gz" &> /dev/null && _got="${_m}" && break
  done
  if [ -z "${_got}" ]; then
    echo "$(date) GeoIP.dat: no DB-IP file for ${_now} or ${_prev}, kept ${_have:-the files as they are}" >> "${_log}"
  elif [ "${_got}" != "none" ]; then
    _info="DB-IP Country Lite ${_got} CC BY 4.0 db-ip.com"
    _new=$(mktemp /usr/share/GeoIP/.GeoIP.dat.XXXXXX 2> /dev/null)
    _new6=$(mktemp /usr/share/GeoIP/.GeoIPv6.dat.XXXXXX 2> /dev/null)
    if [ -n "${_new}" ] && [ -n "${_new6}" ] \
      && /usr/bin/python3 -I - "${_tmp}/dbip.csv.gz" "${_new}" "${_new6}" "${_info}" \
      /usr/bin/geoiplookup /usr/bin/geoiplookup6 >> "${_tmp}/convert.log" 2>&1 <<'PYCOUNTRY'
import gc, gzip, os, socket, struct, subprocess, sys
from bisect import bisect_right

# libGeoIP's country table: a legacy .dat stores the position in it.
CODES = (
  "-- AP EU AD AE AF AG AI AL AM CW AO AQ AR AS AT AU AW AZ BA BB BD BE BF BG"
  " BH BI BJ BM BN BO BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO"
  " CR CU CV CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR"
  " SX GA GB GD GE GF GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU"
  " ID IE IL IN IO IQ IR IS IT JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB"
  " LC LI LK LR LS LT LU LV LY MA MC MD MG MH MK ML MM MN MO MP MQ MR MS MT MU"
  " MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL"
  " PM PN PR PS PT PW PY QA RE RO RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN"
  " SO SR ST SV SY SZ TC TD TF TG TH TJ TK TM TN TO TL TR TT TV TW TZ UA UG UM"
  " US UY UZ VA VC VE VG VI VN VU WF WS YE YT RS ZA ZM ME ZW A1 A2 O1 AX GG IM"
  " JE BL MF BQ SS O1").split()
BEGIN = 16776960

def fail(msg):
  sys.stderr.write("%s\n" % msg)
  sys.exit(1)

if len(CODES) != 256:
  fail("country table has %d entries" % len(CODES))
index = {}
for i, c in enumerate(CODES):
  if i > 0 and c not in index:
    index[c] = i

src, out4, out6, info, look4, look6 = sys.argv[1:7]

# A code the table lacks (XK) or DB-IP's ZZ reads as unknown, an empty value.
rows4, rows6 = [], []
with gzip.open(src, "rt", encoding="ascii", errors="replace") as f:
  for line in f:
    p = line.strip().split(",")
    if len(p) < 3:
      continue
    v6 = ":" in p[0]
    try:
      if v6:
        s = int.from_bytes(socket.inet_pton(socket.AF_INET6, p[0]), "big")
        e = int.from_bytes(socket.inet_pton(socket.AF_INET6, p[1]), "big")
      else:
        s = struct.unpack("!I", socket.inet_aton(p[0]))[0]
        e = struct.unpack("!I", socket.inet_aton(p[1]))[0]
    except (OSError, socket.error, ValueError):
      fail("bad address in %r" % line[:80])
    c = p[2].strip()
    if len(c) != 2 or not c.isalpha() or not c.isupper() or e < s:
      fail("bad row %r" % line[:80])
    (rows6 if v6 else rows4).append((s, e, index.get(c, 0)))
n4, n6 = len(rows4), len(rows6)
if n4 < 100000:
  fail("only %d IPv4 rows" % n4)
if n6 < 10000:
  fail("only %d IPv6 rows" % n6)

def ranges(rows, top):
  """Ranges that cover all of 0..top once, neighbours of one country merged;
  a gap reads as unknown."""
  rows.sort()
  starts, ends, ids = [], [], []
  def put(s, e, i):
    if ids and ids[-1] == i and ends[-1] + 1 == s:
      ends[-1] = e
    else:
      starts.append(s)
      ends.append(e)
      ids.append(i)
  nxt = 0
  for s, e, i in rows:
    if s < nxt:
      fail("overlapping rows at %x" % s)
    if s > nxt:
      put(nxt, s - 1, 0)
    put(s, e, i)
    nxt = e + 1
  if nxt <= top:
    put(nxt, top, 0)
  return starts, ends, ids

S4, E4, I4 = ranges(rows4, 0xFFFFFFFF)
del rows4
if len(set(I4)) < 200:
  fail("only %d countries" % len(set(I4)))

# The IPv6 file answers IPv4 addresses too, mapped (::ffff:a.b.c.d, the form
# nginx looks an IPv4 client up by) and compatible (::a.b.c.d), as the
# distro's copy does: those two blocks take the IPv4 data, whatever IPv6
# rows cover them.
WIN = (0, 0xFFFF << 32)
def cut(rows):
  out = []
  for s, e, i in rows:
    pieces = [(s, e)]
    for w in WIN:
      we = w + 0xFFFFFFFF
      kept = []
      for a, b in pieces:
        if b < w or a > we:
          kept.append((a, b))
          continue
        if a < w:
          kept.append((a, w - 1))
        if b > we:
          kept.append((we + 1, b))
      pieces = kept
    out.extend((a, b, i) for a, b in pieces)
  return out
rows6 = cut(rows6)
for w in WIN:
  rows6.extend((w + s, w + e, i) for s, e, i in zip(S4, E4, I4))
S6, E6, I6 = ranges(rows6, (1 << 128) - 1)
del rows6
gc.collect()

# A binary tree of 6-byte nodes, two 3-byte little-endian records each: a
# record at or above BEGIN is a leaf (BEGIN + country), any other is the
# next node. libGeoIP starts at node 0 with the top bit (31 or 127).
def make(starts, ends, ids, top):
  tree = bytearray()
  def build(lo, bits):
    k = bisect_right(starts, lo) - 1
    if bits < top and ends[k] >= lo + (1 << bits) - 1:
      return BEGIN + ids[k]
    node = len(tree) // 6
    tree.extend(b"\0" * 6)
    left = build(lo, bits - 1)
    right = build(lo + (1 << (bits - 1)), bits - 1)
    tree[node * 6:node * 6 + 6] = struct.pack("<I", left)[:3] + struct.pack("<I", right)[:3]
    return node
  build(0, top)
  if len(tree) // 6 >= BEGIN:
    fail("tree too large")
  return tree

def seek(tree, ip, depth, off=0):
  """The country for the low depth bits of ip from node off; -1 - node when
  no leaf comes first."""
  for d in range(depth - 1, -1, -1):
    b = off * 6 + (3 if ip >> d & 1 else 0)
    x = tree[b] | tree[b + 1] << 8 | tree[b + 2] << 16
    if x >= BEGIN:
      return x - BEGIN
    off = x
  return -1 - off

# Every range is read back at both ends before either file may be used; in
# the IPv6 file each IPv4 block from the node 96 bits down.
T4 = make(S4, E4, I4, 32)
for s, e, i in zip(S4, E4, I4):
  if seek(T4, s, 32) != i or seek(T4, e, 32) != i:
    fail("IPv4 read-back differs at %d" % s)
T6 = make(S6, E6, I6, 128)
inwin = lambda a: any(w <= a <= w + 0xFFFFFFFF for w in WIN)
for s, e, i in zip(S6, E6, I6):
  if not inwin(s) and (seek(T6, s, 128) != i or seek(T6, e, 128) != i):
    fail("IPv6 read-back differs at %x" % s)
for w in WIN:
  node = -1 - seek(T6, w >> 32, 96)
  if node < 0:
    fail("no IPv4 block at %x" % w)
  for s, e, i in zip(S4, E4, I4):
    if seek(T6, s, 32, node) != i or seek(T6, e, 32, node) != i:
      fail("IPv4 read-back in the IPv6 file differs at %x" % (w + s))

# The distro's layout: the tree, three zero bytes, the description
# geoiplookup -v shows, then the edition marker (1 country, 12 country v6).
for out, tree, ed in ((out4, T4, 1), (out6, T6, 12)):
  with open(out, "wb") as f:
    f.write(bytes(tree) + b"\0\0\0" + info.encode("ascii") + b"\xff\xff\xff" + bytes([ed]))
    f.flush()
    os.fsync(f.fileno())

# The library nginx links reads a spread of ranges from the new files, where
# its geoiplookup tools are installed (libgeoip-dev brings them). It looks a
# Teredo address (2001:0::/32) up by the IPv4 client the address carries, not
# by the tree, so ranges starting there are left out of the spread.
def spot(tool, out, addrs):
  if not os.access(tool, os.X_OK):
    return
  for ip, want in addrs:
    r = subprocess.run([tool, "-f", out, ip], stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, universal_newlines=True)
    if (": %s," % CODES[want]) not in r.stdout:
      fail("%s gives %r for %s, the source %s" % (os.path.basename(tool), r.stdout.strip(), ip, CODES[want]))
k4 = [k for k in range(len(I4)) if I4[k] > 0]
k4 = k4[::max(1, len(k4) // 64)]
spot(look4, out4, [(socket.inet_ntoa(struct.pack("!I", S4[k])), I4[k]) for k in k4])
k6 = [k for k in range(len(I6)) if I6[k] > 0 and not inwin(S6[k]) and S6[k] >> 96 != 0x20010000]
k6 = k6[::max(1, len(k6) // 64)]
a6 = [(socket.inet_ntop(socket.AF_INET6, S6[k].to_bytes(16, "big")), I6[k]) for k in k6]
a6 += [("::ffff:" + socket.inet_ntoa(struct.pack("!I", S4[k])), I4[k]) for k in k4[::4]]
spot(look6, out6, a6)
print("%d IPv4 rows, %d IPv6 rows, %d and %d nodes" % (n4, n6, len(T4) // 6, len(T6) // 6))
PYCOUNTRY
    then
      chmod 644 "${_new}" "${_new6}"
      _done=""
      mv -f "${_new}" "${_dat}" 2> /dev/null && _done="GeoIP.dat"
      mv -f "${_new6}" "${_dat6}" 2> /dev/null && _done="${_done:+${_done} and }GeoIPv6.dat"
      if [ -n "${_done}" ]; then
        echo "$(date) ${_done}: ${_info} ($(tail -n 1 "${_tmp}/convert.log"))" >> "${_log}"
        if nginx -t &> /dev/null; then
          service nginx reload &> /dev/null
        else
          echo "$(date) GeoIP.dat: nginx -t fails, so nginx was not reloaded; it reads the new data at its next reload or start" >> "${_log}"
        fi
      fi
      if [ "${_done}" != "GeoIP.dat and GeoIPv6.dat" ]; then
        echo "$(date) GeoIP.dat: DB-IP ${_got} could not be renamed into place for both files (done: ${_done:-none}), kept ${_have:-the files as they are} for the rest" >> "${_log}"
      fi
    else
      echo "$(date) GeoIP.dat: DB-IP ${_got} not used, kept ${_have:-the files as they are}: $(tail -n 1 "${_tmp}/convert.log" 2> /dev/null)" >> "${_log}"
    fi
    rm -f "${_new}" "${_new6}" 2> /dev/null
  fi
  rm -rf "${_tmp}"
}

# The server template names a country file (GeoIPv6.dat, else GeoIP.dat) only
# when it is there, since nginx does not start with a geoip_country file
# missing. So a config rendered while both were missing runs with every
# country empty, and one rendered before its file went missing stops nginx at
# the next restart; neither says so by itself. Nor does a monthly update that
# keeps failing: the data only ages, and the distribution's copy from 2019
# names the wrong country for blocks that changed hands since. So data older
# than the month before (DB-IP may not have published this one yet), or not
# DB-IP's, is reported too, and GoAccess's DB-IP files the same way while its
# reports are on. Once a day a dated line in /var/log/boa/nginx.incident.log
# and a mail to _MY_EMAIL unless _INCIDENT_REPORT is OFF (both read from the
# config _check_root sourced).
_check_country_db() {
  local _cfg="/var/aegir/config/server_master/nginx.conf"
  local _log="/var/log/boa/nginx.incident.log" _stamp="/run/boa_country_db_alert.pid"
  local _goa="/usr/share/GeoIP/dbip-lite-mmdb.month"
  local _txt _lvl _mail _host _today _file _m _prev
  [ -s "${_cfg}" ] || return 0
  _prev=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m)
  _file=$(grep -m 1 "^[[:space:]]*geoip_country " "${_cfg}" 2> /dev/null \
    | awk '{print $2}' | tr -d ';')
  if [ -z "${_file}" ]; then
    _txt="${_cfg} has no geoip_country line: every visitor's country is empty until the next Verify of the server renders it with /usr/share/GeoIP/GeoIPv6.dat or GeoIP.dat present"
  elif [ ! -s "${_file}" ]; then
    _txt="${_file} is missing and ${_cfg} names it: nginx will not start until the file is back (apt-get install --reinstall geoip-database)"
  else
    _m=$(tail -c 120 "${_file}" 2> /dev/null | tr -c '[:print:]' '\n' \
      | grep -oE 'DB-IP Country Lite [0-9]{4}-[0-9]{2}' | tail -n 1 \
      | grep -oE '[0-9]{4}-[0-9]{2}$')
    if [ -z "${_m}" ]; then
      _txt="${_file} holds no DB-IP data (the distribution's copy is from 2019): the monthly update from DB-IP keeps failing, see /var/log/boa/country-db.log"
    elif [[ "${_m}" < "${_prev}" ]]; then
      _txt="${_file} holds DB-IP's data of ${_m}: the monthly update from DB-IP keeps failing, see /var/log/boa/country-db.log"
    fi
  fi
  if [ "${_ENABLE_GOACCESS}" = "YES" ]; then
    _m=$( { tr -dc '0-9-' < "${_goa}"; } 2> /dev/null)
    [ -s "${_goa%/*}/dbip-city-lite.mmdb" ] && [ -s "${_goa%/*}/dbip-asn-lite.mmdb" ] || _m=""
    if [ -z "${_m}" ]; then
      _m="missing"
    elif [[ "${_m}" < "${_prev}" ]]; then
      _m="from ${_m}"
    else
      _m=""
    fi
    if [ -n "${_m}" ]; then
      _txt="${_txt:+${_txt}; }GoAccess's DB-IP City and ASN files are ${_m}: their monthly update keeps failing, see /var/log/boa/country-db.log"
    fi
  fi
  [ -n "${_txt}" ] || return 0
  # The stamp holds the day it alerted: an age test against a daily cron that
  # reaches this point a little earlier one night skips that night.
  _today=$(date +%F)
  [ "$(cat "${_stamp}" 2> /dev/null)" = "${_today}" ] && return 0
  echo "${_today}" > "${_stamp}" 2> /dev/null
  mkdir -p "${_log%/*}" 2> /dev/null
  echo "$(date) country database: ${_txt}" >> "${_log}"
  _lvl="${_INCIDENT_REPORT^^}"
  _lvl="${_lvl//[^A-Z]/}"
  [ "${_lvl}" != "OFF" ] && [ "${_lvl}" != "NO" ] || return 0
  _mail="${_MY_EMAIL//\\@/@}"
  if [ -z "${_mail}" ] || ! command -v s-nail > /dev/null 2>&1; then
    return 0
  fi
  _host="$(tr -d '\n' 2> /dev/null < /etc/hostname)"
  [ -n "${_host}" ] || _host="$(hostname -f 2> /dev/null)"
  printf '%s\n' "nginx country database on ${_host}" "" "${_txt}" "" \
    "Logged to ${_log}" "" "--" "This email has been sent by BOA graceful.sh" \
    | s-nail -s "ALERT [${_host}]: nginx country database" "${_mail}" > /dev/null 2>&1
  return 0
}

# GoAccess, when the nightly per-site reports are on (_ENABLE_GOACCESS=YES),
# takes its visitors' country, continent and city from DB-IP's IP to City Lite
# and their network from its ASN Lite (CC BY 4.0, https://db-ip.com), kept in
# /usr/share/GeoIP and refreshed once a month like the country files above;
# weblogx names them in its GoAccess config. A file is used only when its
# metadata, at its end where a cut-short download loses it, names its kind,
# and then replaces the old one by a rename. The GeoLite2 files earlier
# passes fetched from the mirror stay where they are.
_refresh_goaccess_db() {
  local _dir="/usr/share/GeoIP" _log="/var/log/boa/country-db.log"
  local _stamp="/usr/share/GeoIP/dbip-lite-mmdb.month"
  local _now _prev _have _m _tmp _got _f _kind _bad _new _new_city _new_asn
  [ -d "${_dir}" ] || return 0
  # A killed run's temp copy (City Lite is over 100 MB) goes even once the
  # reports are switched off.
  find "${_dir}" -maxdepth 1 -type f -name '.dbip-*-lite.mmdb.??????' \
    -mmin +720 -delete 2> /dev/null
  [ "${_ENABLE_GOACCESS}" = "YES" ] || return 0
  _now=$(date -u +%Y-%m)
  _prev=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m)
  _have=$( { tr -dc '0-9-' < "${_stamp}"; } 2> /dev/null)
  [ -s "${_dir}/dbip-city-lite.mmdb" ] && [ -s "${_dir}/dbip-asn-lite.mmdb" ] || _have=""
  [ "${_have}" = "${_now}" ] && return 0
  if ! _tmp=$(mktemp -d /var/backups/.boa-geoip.XXXXXX 2> /dev/null); then
    echo "$(date) GoAccess mmdb: no work folder in /var/backups, kept ${_have:-the files as they are}" >> "${_log}"
    return 0
  fi
  _got=""
  for _m in "${_now}" "${_prev}"; do
    [ "${_m}" = "${_have}" ] && _got=none && break
    _bad=""
    for _f in city asn; do
      curl -fsS --max-time 900 -o "${_tmp}/${_f}.mmdb.gz" \
        "https://download.db-ip.com/free/dbip-${_f}-lite-${_m}.mmdb.gz" &> /dev/null \
        && gzip -t "${_tmp}/${_f}.mmdb.gz" &> /dev/null || _bad="${_f}"
      [ -n "${_bad}" ] && break
    done
    [ -z "${_bad}" ] && _got="${_m}" && break
  done
  if [ -z "${_got}" ]; then
    echo "$(date) GoAccess mmdb: no DB-IP City and ASN files for ${_now} or ${_prev}, kept ${_have:-the files as they are}" >> "${_log}"
  elif [ "${_got}" != "none" ]; then
    _new_city=$(mktemp "${_dir}/.dbip-city-lite.mmdb.XXXXXX" 2> /dev/null)
    _new_asn=$(mktemp "${_dir}/.dbip-asn-lite.mmdb.XXXXXX" 2> /dev/null)
    _bad=""
    for _f in city asn; do
      _kind="DBIP-City-Lite"
      _new="${_new_city}"
      if [ "${_f}" = "asn" ]; then
        _kind="DBIP-ASN-Lite"
        _new="${_new_asn}"
      fi
      if [ -z "${_new}" ] || ! gunzip -c "${_tmp}/${_f}.mmdb.gz" > "${_new}" 2> /dev/null \
        || ! tail -c 131072 "${_new}" | LC_ALL=C grep -a -q -F "MaxMind.com" \
        || ! tail -c 131072 "${_new}" | LC_ALL=C grep -a -q -F "${_kind}"; then
        _bad="${_bad} ${_f}"
      fi
    done
    if [ -z "${_bad}" ] && chmod 644 "${_new_city}" "${_new_asn}" \
      && mv -f "${_new_city}" "${_dir}/dbip-city-lite.mmdb" \
      && mv -f "${_new_asn}" "${_dir}/dbip-asn-lite.mmdb"; then
      echo "${_got}" > "${_stamp}"
      echo "$(date) GoAccess mmdb: dbip-city-lite.mmdb and dbip-asn-lite.mmdb, DB-IP ${_got}" >> "${_log}"
    else
      echo "$(date) GoAccess mmdb: DB-IP ${_got} not used (failed:${_bad:- rename}), kept ${_have:-the files as they are}" >> "${_log}"
    fi
    rm -f "${_new_city}" "${_new_asn}" 2> /dev/null
  fi
  rm -rf "${_tmp}"
}

# Delete only the bounce notices (null sender, listed as MAILER-DAEMON).
# Mail a site sent that is merely deferred keeps postfix's own retry
# lifetime: wiping the whole queue destroyed transactional mail held back
# by a temporary delivery problem.
_purge_postfix_bounces() {
  local _qIds
  _qIds="$(postqueue -p 2> /dev/null | tail -n +2 \
    | awk 'BEGIN { RS = "" } $7 == "MAILER-DAEMON" { print $1 }' \
    | tr -d '*!')"
  if [ -n "${_qIds}" ]; then
    echo "${_qIds}" | postsuper -d - &> /dev/null
  fi
}

# Once a week, remove the copies that BOA leaves on every run and every day
# and nothing else removes: the PHP-FPM logs moved aside on each FPM restart
# and each barracuda or octopus run (php-logs/<stamp>/), kept 30 days so the
# logs of a forced security pass can still be read a month later, when the
# reports saying what to look for usually arrive; the csf.allow copies
# guest-water takes before each provider refresh (csf/water/), kept 7 days;
# then the dragon vault and the other families below. Age is when a copy was
# made (ctime): cp -a keeps the mtime of the file it copies. A stamp sets the
# pace, not a weekday, so a night this pass skips only moves the prune to the
# next night it runs.
_purge_weekly_backups() {
  local _wkStamp="/var/backups/.graceful.weekly.prune.stamp"
  if [ -e "${_wkStamp}" ] \
    && [ -z "$(find "${_wkStamp}" -mmin +9000 2> /dev/null)" ]; then
    return 0
  fi
  echo "Removing old backup copies, markers and leftovers..."
  if [ -d "/var/backups/php-logs" ] && [ ! -L "/var/backups/php-logs" ]; then
    find /var/backups/php-logs -mindepth 1 -maxdepth 1 -ctime +30 \
      -exec rm -rf {} + &> /dev/null
  fi
  if [ -d "/var/backups/csf/water" ] && [ ! -L "/var/backups/csf/water" ]; then
    find /var/backups/csf/water -mindepth 1 -maxdepth 1 -type f -ctime +6 \
      -delete &> /dev/null
  fi
  _prune_dragon_vault
  _purge_run_copies
  _purge_markers
  _purge_dated_files
  _purge_solr_tmp
  _purge_le_accounts
  _purge_leftovers
  touch "${_wkStamp}"
}

# Files dated by the day or the event that nothing reads once that day is past:
# multiback's per-day run markers (it tests only today's), the nginx error logs
# the monitor sets aside at a restart (with the rotated copy the distro's nginx
# rules make of each), codebasecheck's reports (boa info greps them all, so old
# ones kept showing), the flood detector's snapshots, and the copies synproxy
# takes of csf's config at each run (its rollback does not read them).
_purge_dated_files() {
  local _dfD="[0-9][0-9][0-9][0-9][0-9][0-9]"
  _prune_older_than /var/log/boa "back-to-*.${_dfD}.*.log" 30
  _prune_older_than /var/log/nginx "${_dfD}-[0-9][0-9][0-9][0-9]-error.log*" 30
  _prune_older_than /var/log/boa/core 'incompatible-*.log' 30
  _prune_older_than /var/log/boa/core 'box-readiness-*.log' 30
  _prune_older_than /var/xdrago/monitor/log/i18n_flood '[0-9]*-*.txt' 90
  _prune_keep_newest /etc/csf 'csfpost.sh.bak.[0-9]*' 3
  _prune_keep_newest /etc/csf 'csf.conf.bak.[0-9]*' 3
}

# Markers BOA writes in /var/log/boa on every run, at each release or for each
# build. A run reads only its own or the current one, so the newest three are
# kept (by ctime) and none goes by age: a release or a PHP build stays current
# for months. The PHP extension markers are kept per extension and PHP branch,
# since every installed branch has its own current one, and the shared module
# markers per module; a name that does not parse is left alone.
_purge_markers() {
  local _mkL="/var/log/boa" _mkP _mkE _mkB _mkM
  for _mkP in 'sysctl.conf-*.log' 'sec-valkey-pass-*.log' '.curl_libs_fix_*.pid' \
    '._php_libs_fix_*.pid' 'pure-ftpd-build-*.log' 'valkey-*.log' \
    'mss-build-ok-*.log' 'nginx-config-params-fixed-*.log' \
    'fix-drupal-site-permissions-*.log' '.force.f*.ctrl' \
    '.csf_legacy_cleanup.*.pid' '.csf_dhcp_udp_cleanup.*.pid' \
    '.disabled_modules_fix.*.pid' '.curl_ctrl.*.pid' \
    '.etc_crontab_lock_state.*.txt' 'apt-deb-src-updates-*.txt' \
    'lshell-fix-build-*.log' 'csf_BOA-*.log' 'libmagickwand-dev-*-rebuild.log'; do
    _prune_keep_newest "${_mkL}" "${_mkP}" 3
  done
  for _mkE in apcu imagick igbinary f_yaml phpredis-update f_uploadprogress \
    mcrypt php-pecl-jsmin php-geos; do
    for _mkB in $(find "${_mkL}" -mindepth 1 -maxdepth 1 -type f -name "${_mkE}-*.log" \
      -printf '%f\n' 2> /dev/null \
      | sed -n "s/^${_mkE}-.*-\([0-9]\{1,2\}\.[0-9]\{1,2\}\)\.[0-9]\{1,3\}[A-Za-z0-9]*\.log\$/\1/p" \
      | sort -u); do
      _prune_keep_newest "${_mkL}" "${_mkE}-*-${_mkB}.[0-9]*.log" 3
    done
  done
  for _mkM in $(find "${_mkL}" -mindepth 1 -maxdepth 1 -type f -name '*.ctrl.*.log' \
    -printf '%f\n' 2> /dev/null | sed -n 's/^\([a-z_]*\)\.ctrl\.[0-9a-zA-Z]*\.log$/\1/p' \
    | sort -u); do
    _prune_keep_newest "${_mkL}" "${_mkM}.ctrl.*.log" 3
  done
}

# The dragon vault's copies other than config/ go once they are a week old, by
# when each was made (ctime), the rule owl.sh's nightly pass also applies. That
# pass does not run on a standby or a proxy, where barracuda still runs and
# adds a full copy of /var/xdrago to dragon/x on every pass.
_prune_dragon_vault() {
  local _dvS
  [ -d "/var/backups/dragon" ] && [ ! -L "/var/backups/dragon" ] || return 0
  find /var/backups/dragon -mindepth 1 -maxdepth 1 ! -name config ! -type d \
    -ctime +7 -delete &> /dev/null
  for _dvS in /var/backups/dragon/*; do
    [ -d "${_dvS}" ] && [ ! -L "${_dvS}" ] || continue
    [ "${_dvS##*/}" = "config" ] && continue
    find "${_dvS}" -mindepth 1 -maxdepth 1 -ctime +7 \
      -exec rm -rf {} + &> /dev/null
  done
}

# Remove all but the newest $3 entries the find pattern $2 names directly in
# the real directory $1, newest by when each was made there (ctime).
_prune_keep_newest() {
  local _kDir="${1}" _kPat="${2}" _kKeep="${3}"
  [ -d "${_kDir}" ] && [ ! -L "${_kDir}" ] || return 0
  find "${_kDir}" -mindepth 1 -maxdepth 1 -name "${_kPat}" -printf '%C@ %p\0' \
    2> /dev/null | LC_ALL=C sort -z -rn | tail -z -n +$(( _kKeep + 1 )) \
    | cut -z -d' ' -f2- | xargs -0 -r rm -rf -- &> /dev/null
}

# Remove the entries the find pattern $2 names directly in the real directory
# $1 that were made there more than $3 days ago (ctime).
_prune_older_than() {
  local _oDir="${1}" _oPat="${2}" _oDays="${3}"
  [ -d "${_oDir}" ] && [ ! -L "${_oDir}" ] || return 0
  find "${_oDir}" -mindepth 1 -maxdepth 1 -name "${_oPat}" -ctime +"${_oDays}" \
    -exec rm -rf {} + &> /dev/null
}

# Copies BOA makes on every run or on a change and never reads again: the
# config files a barracuda pass replaces, csf's allow and ignore lists at each
# release, the libcurl a cURL change retires, the PHP build options a debug
# build writes, and the drush aliases syncpass rewrites, kept per alias and
# account (a name that does not parse is left alone).
_purge_run_copies() {
  local _rcAls _rcUsr _rcStm="[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]"
  _prune_keep_newest /var/backups 'sources.list-pre-*' 3
  _prune_keep_newest /var/backups '.etc.rsyslog.conf-pre-*' 3
  _prune_keep_newest /var/backups 'resolv.conf.pre-*' 3
  _prune_keep_newest /var/backups 'nginx-pre-*' 3
  _prune_keep_newest /var/backups/csf 'csf.allow.*.txt' 5
  _prune_keep_newest /var/backups/csf 'csf.ignore.*.txt' 5
  _prune_keep_newest /var/backups 'legacy-libcurl-pre-*' 1
  _prune_older_than /var/backups 'php_extra_*' 30
  for _rcAls in server_master server_localhost; do
    for _rcUsr in $(find /var/backups -mindepth 1 -maxdepth 1 -type f \
      -name "${_rcAls}.alias.drushrc.php.*-${_rcStm}" -printf '%f\n' 2> /dev/null \
      | sed -n "s/^${_rcAls}\.alias\.drushrc\.php\.\([a-z0-9._]*\)-[0-9]\{6\}-[0-9]\{6\}\$/\1/p" \
      | sort -u); do
      _prune_keep_newest /var/backups \
        "${_rcAls}.alias.drushrc.php.${_rcUsr}-${_rcStm}" 3
    done
  done
}

# Solr's Jetty leaves a work directory (jetty-*) and a start properties file
# (start_*.properties) in /tmp at every start, and nothing removes the old ones:
# BOA's own cleaner matches only Solr 4's jetty9. Only what the solr7 and solr9
# users own counts, since any account can make such names in /tmp, and of that
# only an entry made over two days ago that is not the newest of its kind for
# its owner and that no process holds open, maps or works in. The maps files
# go through cat: awk given a file that is gone (a process that ended after the
# glob was expanded) stops there and reads none of the rest.
_purge_solr_tmp() {
  local _stU _stK _stC _stE _stHeld
  _stHeld="$( { find /proc/[0-9]*/fd /proc/[0-9]*/cwd -maxdepth 1 -lname '/tmp/*' \
    -printf '%l\n'; cat /proc/[0-9]*/maps | awk '$6 ~ /^\/tmp\// { print $6 }'; } \
    2> /dev/null | sort -u)"
  for _stU in solr7 solr9; do
    id -u "${_stU}" &> /dev/null || continue
    for _stK in 'jetty-*' 'start_*.properties'; do
      find /tmp -mindepth 1 -maxdepth 1 -user "${_stU}" -name "${_stK}" \
        -printf '%C@ %f\n' 2> /dev/null | LC_ALL=C sort -rn | tail -n +2 \
        | while read -r _stC _stE; do
          case "${_stE}" in
            ""|*/*|*[!A-Za-z0-9._-]*) continue ;;
          esac
          if printf '%s\n' "${_stHeld}" | grep -q -e "^/tmp/${_stE}\$" \
            -e "^/tmp/${_stE}/"; then
            continue
          fi
          find /tmp -mindepth 1 -maxdepth 1 -name "${_stE}" -user "${_stU}" \
            -ctime +1 -execdir rm -rf -- {} + 2> /dev/null
        done
    done
  done
}

# The ACME account keys the certificate heal sets aside per account when it
# registers anew (/var/backups/le-accounts/<account>/accounts-<stamp>): the newest
# three per account stay, newest by the date and time in the name, which keeps
# its order whatever later touches the copies. Other names stay.
_purge_le_accounts() {
  local _laD _laE
  [ -d "/var/backups/le-accounts" ] && [ ! -L "/var/backups/le-accounts" ] || return 0
  for _laD in /var/backups/le-accounts/*; do
    [ -d "${_laD}" ] && [ ! -L "${_laD}" ] || continue
    find "${_laD}" -mindepth 1 -maxdepth 1 -name \
      'accounts-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' \
      -printf '%f\n' 2> /dev/null | LC_ALL=C sort -r | tail -n +4 \
      | while read -r _laE; do
        rm -rf -- "${_laD:?}/${_laE}"
      done
  done
}

# Leftovers no current code writes or reads, removed once: the copies of the
# MySQL root password and client config older releases kept at the top of
# /var/backups (they go to dragon/config now), the log folder used before
# /var/log/boa (BOA.sh.txt copied its files there once and then wrote
# .migrated.txt), markers whose writers are gone, and the attack archives older
# releases set aside at each release (<name>.archive.<serial>.log and
# <name>.archive-old-*.log); the live archives and their one-time .x3 copies,
# which guest-water and xdr9000 read, stay. The old folder is emptied only after
# that copy, and never when it leads to /var/log/boa itself.
_purge_leftovers() {
  local _lfA
  rm -f /var/backups/.my.pass.txt-pre-* /var/backups/.my.cnf-pre-*
  if [ -e "/var/log/boa/.migrated.txt" ] \
    && [ -d "/var/xdrago/log" ] && [ ! -L "/var/xdrago/log" ] \
    && [ "$(readlink -f /var/xdrago/log)" != "$(readlink -f /var/log/boa)" ]; then
    find /var/xdrago/log -mindepth 1 -maxdepth 1 ! -name EMPTY.txt \
      -exec rm -rf {} + &> /dev/null
  fi
  rm -f /var/log/boa/sec-redis-pass-* /var/log/boa/.custom_percona_forced.* \
    /var/log/boa/mss-build-master-* /var/log/boa/geos-* \
    /var/log/boa/nginx.kill-start.log /var/log/boa/cron-count.kill.log
  if [ -d "/var/xdrago/monitor/log" ] && [ ! -L "/var/xdrago/monitor/log" ]; then
    for _lfA in hackcheck scan_nginx hackftp; do
      find /var/xdrago/monitor/log -mindepth 1 -maxdepth 1 -type f \
        \( -name "${_lfA}.archive.*.log" ! -name "${_lfA}.archive.x3.log" \
        -o -name "${_lfA}.archive-old-*.log" \) -delete &> /dev/null
    done
  fi
}

# A session cgroup is idle when no process is in it or below it and it has no
# child cgroup.
_session_cgroup_idle() {
  local _cgKey _cgVal _cgSub
  local _cgPop=1
  [ -d "$1" ] && [ -r "$1/cgroup.events" ] || return 1
  while read -r _cgKey _cgVal; do
    if [ "${_cgKey}" = "populated" ]; then
      _cgPop="${_cgVal}"
    fi
  done < "$1/cgroup.events"
  [ "${_cgPop}" = "0" ] || return 1
  for _cgSub in "$1"/*/; do
    [ -d "${_cgSub}" ] && return 1
  done
  return 0
}

# elogind never removes the cgroup it makes for each login session, and every
# su, cron run and ssh login makes one; their kernel memory grows until the
# OOM killer steps in. Barracuda removes elogind's PAM module, but where it is
# still in place (or a long session ended since) remove the empty session
# cgroups: top-level c<N> and <N> directories on the cgroup2 hierarchy elogind
# mounts, never on a systemd host, only those idle at two reads three seconds
# apart. The kernel refuses rmdir on a populated cgroup in any case.
_trim_session_cgroups() {
  local _cgDir _cgLeft
  local -a _cgCand=()
  local -a _cgGone=()
  [ -d "/run/systemd/system" ] && return 0
  grep -qs "^[^ ]* /sys/fs/cgroup cgroup2 " /proc/mounts || return 0
  for _cgDir in /sys/fs/cgroup/c[0-9]* /sys/fs/cgroup/[0-9]*; do
    [[ "${_cgDir##*/}" =~ ^c?[0-9]+$ ]] || continue
    _session_cgroup_idle "${_cgDir}" && _cgCand+=("${_cgDir}")
  done
  (( ${#_cgCand[@]} )) || return 0
  sleep 3
  for _cgDir in "${_cgCand[@]}"; do
    _session_cgroup_idle "${_cgDir}" && _cgGone+=("${_cgDir}")
  done
  (( ${#_cgGone[@]} )) || return 0
  printf '%s\0' "${_cgGone[@]}" | xargs -0 rmdir 2> /dev/null
  _cgLeft=0
  for _cgDir in "${_cgGone[@]}"; do
    [ -d "${_cgDir}" ] && _cgLeft=$(( _cgLeft + 1 ))
  done
  echo "Removed $(( ${#_cgGone[@]} - _cgLeft )) empty login-session cgroups"
}

# Resident size in MB of the shared memory a PHP-FPM master maps (opcache and
# APCu: the master creates both before it forks its workers). A page any worker
# ever filled stays resident until the master restarts, long after that worker
# is gone, so the master's own RSS shows almost none of it: fincore reads the
# segment's own pages instead. Each object counts once.
_fpm_shared_resident_mb() {
  local _rng _perm _off _dev _ino _name _res _seen=" " _tot=0
  while read -r _rng _perm _off _dev _ino _name; do
    [[ "${_perm}" == *s* ]] || continue
    [[ "${_ino}" != "0" ]] || continue
    case "${_name}" in
      /dev/zero*|/memfd:*|/SYSV*) ;;
      *) continue ;;
    esac
    [[ "${_seen}" == *" ${_dev}:${_ino} "* ]] && continue
    _seen="${_seen}${_dev}:${_ino} "
    _res=$(fincore -n -b -o RES "/proc/${1}/map_files/${_rng}" 2> /dev/null)
    _res="${_res//[^0-9]/}"
    [ -n "${_res}" ] && _tot=$(( _tot + _res ))
  done < "/proc/${1}/maps"
  echo "$(( _tot / 1048576 ))"
}

# Every PHP-FPM version keeps its opcache and APCu filled to their high-water
# mark until its master restarts, and BOA sizes each version's segments for the
# whole PHP budget of the box. When sites move to another version, the one they
# left holds its filled segments with nothing using them: a hosted box had its
# database OOM-killed with 5.8 GB held that way beside the 6.2 GB of the version
# in use. Reload a version the FPM sampler saw without a single worker in every
# sample of the last day (at least 12 hours of samples of its current master)
# while it still holds 256 MB or more of them: no request is in flight to lose,
# and the reload hands the memory back.
_reload_idle_fpm_versions() {
  local _now _from _mPid _mVer _mUp _since _verdict _shm _mNew _after
  local _tuneDir="/var/log/boa/fpm-tune"
  local _relLog="/var/log/boa/fpm-idle-reload.log"
  command -v fincore > /dev/null 2>&1 || return 0
  [ -d "${_tuneDir}" ] || return 0
  _now=$(date +%s)
  _from=$(( _now - 86400 ))
  for _mPid in $(pgrep -u root -U root -f '^php-fpm: master process'); do
    _mVer=$(tr '\0' ' ' 2> /dev/null < "/proc/${_mPid}/cmdline" \
      | grep -o '/opt/php[0-9]\+/' | head -n1)
    _mVer="${_mVer//[^0-9]/}"
    [ -n "${_mVer}" ] && [ -e "/etc/init.d/php${_mVer}-fpm" ] || continue
    _mUp=$(ps -o etimes= -p "${_mPid}" 2> /dev/null)
    _mUp="${_mUp//[^0-9]/}"
    [ -n "${_mUp}" ] || continue
    _since=$(( _now - _mUp ))
    [ "${_since}" -lt "${_from}" ] && _since="${_from}"
    _verdict=$(cat "${_tuneDir}/$(date -d "@${_from}" +%Y%m%d).jsonl" \
      "${_tuneDir}/$(date -d "@${_now}" +%Y%m%d).jsonl" 2> /dev/null \
      | awk -v v="${_mVer}" -v p="${_mPid}" -v s="${_since}" '
        function num(k,   r) {
          if (!match($0, "\"" k "\":[0-9]+")) return -1
          r = substr($0, RSTART, RLENGTH); sub(/.*:/, "", r); return r + 0
        }
        /"scope":"version"/ {
          if (num("version") != v || num("master_pid") != p) next
          t = num("ts"); if (t < s) next
          k = num("n_children"); if (k < 0) next
          n++; if (k > 0) busy++
          if (lo == "" || t < lo) lo = t
          if (t > hi) hi = t
        }
        END { if (n >= 100 && hi - lo >= 43200 && busy == 0) print "IDLE" }')
    [ "${_verdict}" = "IDLE" ] || continue
    _shm=$(_fpm_shared_resident_mb "${_mPid}")
    [ "${_shm:-0}" -ge 256 ] || continue
    echo "Reloading PHP ${_mVer} FPM, idle all day with ${_shm} MB of caches..."
    if service "php${_mVer}-fpm" reload > /dev/null 2>&1; then
      # What the version holds after the reload, read from its master then
      # (a fresh master starts at a baseline of some tens of MB).
      sleep 3
      _mNew=$(pgrep -u root -U root -f "^php-fpm: master process \(/opt/php${_mVer}/" | head -n1)
      _after="?"
      [ -n "${_mNew}" ] && _after=$(_fpm_shared_resident_mb "${_mNew}")
      echo "$(date) php${_mVer}-fpm reloaded: no worker for a day, opcache and APCu held ${_shm} MB before, ${_after} MB after" >> "${_relLog}"
    else
      echo "$(date) php${_mVer}-fpm reload FAILED: no worker for a day, ${_shm} MB of opcache and APCu still held" >> "${_relLog}"
    fi
  done
}

# Size in kB and kB in use of one active swap area, "0 0" when it is not on.
_swap_area_kb() {
  awk -v f="$1" '$1 == f { s = $3; u = $4 } END { printf "%d %d\n", s, u }' /proc/swaps
}

# Highest swap use in kB the xdr9000 sampler recorded over the last 14 days,
# and the number of samples read.
_swap_sampled_peak() {
  local _now _d _day _f
  local _arch="/var/log/boa/xdr9000"
  if [ ! -d "${_arch}" ]; then
    echo "0 0"
    return 0
  fi
  _now=$(date +%s)
  for _d in $(seq 0 13); do
    _day=$(date -d "@$(( _now - _d * 86400 ))" +%Y/%m/samples-%Y%m%d)
    for _f in "${_arch}/${_day}.jsonl" "${_arch}/${_day}.jsonl.gz"; do
      [ -e "${_f}" ] && zcat -f "${_f}" 2> /dev/null
    done
  done | awk '
    /"c":"smp"/ && match($0, /"swp":[0-9]+/) {
      v = substr($0, RSTART + 6, RLENGTH - 6) + 0
      n++
      if (v > m) m = v
    }
    END { printf "%d %d\n", m, n }'
}

# Swap cannot be switched on inside a container, and a file built there only
# takes disk space.
_swap_in_container() {
  [ -e "/proc/vz" ] && [ ! -e "/proc/bc" ] && return 0
  [ -e "/proc/bean_counters" ] && return 0
  [ -e "/run/.containerenv" ] && return 0
  [ -e "/.dockerenv" ] && return 0
  { tr '\0' '\n' < /proc/1/environ; } 2> /dev/null | grep -q '^container=' && return 0
  return 1
}

# Build a swap file of $2 MB at $1 and switch it on. fallocate is tried
# first; a filesystem that leaves holes in it makes swapon refuse it, so the
# file is then written out in full. A refusal for lack of permission is not
# retried that way.
_swap_make_file() {
  local _f="$1"
  local _mb="$2"
  local _err
  rm -f "${_f}"
  if ( umask 077; fallocate -l "${_mb}M" "${_f}" ) 2> /dev/null; then
    chmod 600 "${_f}"
    if mkswap "${_f}" > /dev/null 2>&1; then
      _err=$(swapon "${_f}" 2>&1) && return 0
      if [[ "${_err}" =~ "not permitted" ]]; then
        rm -f "${_f}"
        return 1
      fi
    fi
  fi
  rm -f "${_f}"
  if ! ( umask 077; dd if=/dev/zero of="${_f}" bs=1M count="${_mb}" status=none ) 2> /dev/null; then
    rm -f "${_f}"
    return 1
  fi
  chmod 600 "${_f}"
  mkswap "${_f}" > /dev/null 2>&1 && swapon "${_f}" 2> /dev/null && return 0
  rm -f "${_f}"
  return 1
}

# A reboot and multiback's swapon -a bring back only what fstab lists.
_swap_fstab_line() {
  local _tmp
  grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab && return 0
  [ -d "/var/backups" ] || mkdir -p /var/backups
  cp -a /etc/fstab "/var/backups/fstab.pre-swapfile.$(date +%y%m%d-%H%M%S)"
  _tmp=$(mktemp /etc/.fstab.boa.XXXXXX) || return 1
  if cat /etc/fstab > "${_tmp}" \
    && { [ -z "$(tail -c1 "${_tmp}")" ] || echo >> "${_tmp}"; } \
    && echo "/swapfile none swap sw 0 0" >> "${_tmp}" \
    && chmod 644 "${_tmp}" \
    && mv -f "${_tmp}" /etc/fstab; then
    return 0
  fi
  rm -f "${_tmp}"
  return 1
}

# May an area holding $1 kB of swapped pages be switched off now? swapoff reads
# them back holding each owner's address space lock, so a process with pages in
# swap stands still, every thread, until they are in: 4 GB on a slow disk froze
# MySQL for over 8 minutes. So 256 MB at most, about a minute at that speed, and
# only while free RAM can take them back and still keep a tenth of the RAM (at
# least 512 MB) free. The OOM guard in system.sh acts at 5%.
_swap_off_fits() {
  local _availKb _ramKb _spare
  [ "$1" -le 262144 ] || return 1
  _ramKb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  _availKb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  _spare=$(( _ramKb / 10 ))
  [ "${_spare}" -lt 524288 ] && _spare=524288
  [ $(( _availKb - $1 )) -ge "${_spare}" ]
}

# The resize marker: /run/boa_swap_size.pid holds the PID of the graceful.sh
# sizing swap (the form earlier releases read too), /run/boa_swap_size.start
# that process's start time. A resize runs while that very process lives: the
# start time tells it from a later process given the same PID.
_swap_resize_running() {
  local _rszPid _rszStart _rszNow _rszCmd
  _rszPid=$( { tr -dc '0-9' < /run/boa_swap_size.pid; } 2>/dev/null )
  [ -n "${_rszPid}" ] || return 1
  # The start file holds "<PID> <start time>"; one left by another run is
  # ignored.
  _rszStart=$( { awk -v p="${_rszPid}" '$1 == p {print $2}' /run/boa_swap_size.start; } 2>/dev/null )
  _rszStart="${_rszStart//[^0-9]/}"
  if [ -n "${_rszStart}" ]; then
    _rszNow=$(sed 's/^.*) //' "/proc/${_rszPid}/stat" 2>/dev/null | awk '{print $20}')
    [ "${_rszNow}" = "${_rszStart}" ]
    return
  fi
  # No start time yet (written just after the claim, or by an older
  # graceful.sh): the process's own command line names graceful.sh.
  _rszCmd=$( { tr '\0' ' ' < "/proc/${_rszPid}/cmdline"; } 2>/dev/null )
  [[ "${_rszCmd}" == *"graceful.sh"* ]]
}

# The swap total BOA aims for, the /swapfile size that gives it, and what to
# do: "grow", "shrink" or "keep". Arguments in MB: RAM, other swap areas,
# the current /swapfile, the 14-day peak use, and the size BOA recorded when
# it last built /swapfile (empty when it never did). Half the RAM, at least
# 1 GB and at most 4 GB, raised to twice the peak, so a normal fortnight
# stays near half full; a swap that ran 90% full is doubled, as its samples
# cannot show how much more it needed.
# Never above the RAM (under 1 GB of RAM that wins over the floor) or 16 GB.
# The total grows only when it falls a fifth or more short, so a peak that
# crept a little past half full does not resize every fortnight. A file BOA
# built is shrunk when it is twice the size it should be, never below 256 MB
# and never removed; any other /swapfile is only ever grown.
_swap_plan() {
  local _ram="$1" _oth="$2" _file="$3" _peak="$4" _made="$5"
  local _tot _base _want _cap _need _act="keep"
  _tot=$(( _oth + _file ))
  _base=$(( _ram / 2 ))
  [ "${_base}" -lt 1024 ] && _base=1024
  [ "${_base}" -gt 4096 ] && _base=4096
  if [ "${_tot}" -gt 0 ] && [ $(( _peak * 10 )) -ge $(( _tot * 9 )) ]; then
    _want=$(( _tot * 2 ))
  else
    _want=$(( _peak * 2 ))
  fi
  [ "${_want}" -lt "${_base}" ] && _want="${_base}"
  _cap="${_ram}"
  [ "${_cap}" -gt 16384 ] && _cap=16384
  _want=$(( (_want + 255) / 256 * 256 ))
  [ "${_want}" -gt "${_cap}" ] && _want=$(( _cap / 256 * 256 ))
  _need=$(( _want - _oth ))
  if [ "${_need}" -ge 256 ]; then
    if [ $(( _tot * 5 )) -le $(( _want * 4 )) ] \
      && [ "${_need}" -ge $(( _file + 256 )) ]; then
      _act="grow"
    elif [ "${_made}" = "${_file}" ] \
      && [ "${_file}" -gt $(( _need * 2 )) ] \
      && [ "${_file}" -ge $(( _need + 1024 )) ]; then
      _act="shrink"
    fi
  fi
  echo "${_want} ${_need} ${_act}"
}

# The largest file / has room for beside what it holds now: not past 80% of
# / and at least 2 GB left free, as df counts it (used over used plus
# available, the reserved blocks out). Arguments in kB: used and available.
# Prints whole MB, 0 when nothing fits or df gave no figures.
_swap_room() {
  local _used="$1" _av="$2" _byPct _byFree
  case "${_used}" in ""|*[!0-9]*) echo 0; return 0 ;; esac
  case "${_av}" in ""|*[!0-9]*) echo 0; return 0 ;; esac
  _byPct=$(( ((_used + _av) * 80 / 100 - _used) / 1024 ))
  _byFree=$(( (_av - 2097152) / 1024 ))
  [ "${_byFree}" -lt "${_byPct}" ] && _byPct="${_byFree}"
  [ "${_byPct}" -lt 0 ] && _byPct=0
  echo "${_byPct}"
}

# BOA sizes /swapfile to the RAM and to what the box really swaps (see
# _swap_plan). Other swap areas (a provider's partition) count towards the
# total and are never touched. Not in a container, not on a filesystem other
# than ext3, ext4 or xfs. A file that would take / past 80% or leave under
# 2 GB free is grown only as far as / has room for (_swap_room, in 256 MB
# steps), and only when that is still a grow; a later pass grows it on once
# room appears, while the total is still a fifth or more short.
# _SWAP_AUTOSIZE=NO in /root/.barracuda.cnf leaves swap alone.
_size_swap() {
  local _log="/var/log/boa/swap-size.log"
  local _swn="/swapfile.boa"
  local _mark="/etc/boa/control/swapfile-boa.txt"
  local _off="/var/log/boa/swap-size.backoff"
  local _fsType _curKb _curUsed _newKb _newUsed _ramMb _othMb _fileMb
  local _peakKb _smp _usedKb _peakMb _totMb _want _needMb _act
  local _sum _rootSz _rootUsed _rootAv _zramKb _roomMb

  [ "${_SWAP_AUTOSIZE}" = "NO" ] && return 0
  if _swap_in_container; then
    echo "$(date) swap left alone: this system runs in a container" >> "${_log}"
    return 0
  fi
  _fsType=$(awk '$2 == "/" { t = $3 } END { print t }' /proc/mounts)
  case "${_fsType}" in
    ext3|ext4|xfs) ;;
    *)
      echo "$(date) swap left alone: / is ${_fsType:-unknown}, not ext3, ext4 or xfs" >> "${_log}"
      return 0
    ;;
  esac
  if [ -L "/swapfile" ] || { [ -e "/swapfile" ] && [ ! -f "/swapfile" ]; }; then
    echo "$(date) swap left alone: /swapfile is not a plain file" >> "${_log}"
    return 0
  fi
  if pgrep -x swapoff > /dev/null 2>&1; then
    echo "$(date) swap left alone: a swapoff is running" >> "${_log}"
    return 0
  fi

  # A new file an interrupted run left behind, or a grow's extra room beside a
  # /swapfile too full to switch off (below). It stays on until both can go.
  read -r _newKb _newUsed < <(_swap_area_kb "${_swn}")
  if [ "${_newKb}" -gt 0 ]; then
    read -r _curKb _curUsed < <(_swap_area_kb /swapfile)
    if ! _swap_off_fits $(( _newUsed + _curUsed )) || ! swapoff "${_swn}" 2> /dev/null; then
      echo "$(date) swap left alone: ${_swn} stays on beside /swapfile, ${_newUsed} + ${_curUsed} kB in them" >> "${_log}"
      return 0
    fi
  fi
  rm -f "${_swn}"

  # A /swapfile left off (an interrupted run, an operator's file) goes back on
  # before anything else, root-only: swapon only warns about a file others
  # can read, and swapped pages hold whatever the processes held.
  read -r _curKb _curUsed < <(_swap_area_kb /swapfile)
  if [ -f "/swapfile" ]; then
    chown root:root /swapfile 2> /dev/null
    chmod 600 /swapfile 2> /dev/null
  fi
  if [ -f "/swapfile" ] && [ "${_curKb}" -eq 0 ]; then
    swapon /swapfile 2> /dev/null
    read -r _curKb _curUsed < <(_swap_area_kb /swapfile)
  fi
  # fstab lists an active /swapfile from here on, so autoupboa can switch it
  # back on if a later step of this pass is cut short.
  [ "${_curKb}" -gt 0 ] && _swap_fstab_line

  if [ -n "$(find "${_off}" -mmin -10080 2> /dev/null)" ]; then
    echo "$(date) swap left alone: a build failed on $(date -r "${_off}" '+%F %R'), next try 7 days after it" >> "${_log}"
    return 0
  fi

  _ramMb=$(( $(awk '/^MemTotal:/ {print $2}' /proc/meminfo) / 1024 ))
  # /proc/swaps leaves out each area's header page: round up to whole MB.
  # zram is compressed RAM, not room for what RAM cannot hold: it is no swap
  # capacity here, and what it holds now comes off the sampled use (which
  # counts it), as the best estimate of its share of the peak.
  _othMb=$(( ($(awk 'NR > 1 && $1 != "/swapfile" && $1 != "/swapfile.boa" && $1 !~ /^\/dev\/zram/ { s += $3 } END { printf "%d", s }' /proc/swaps) + 1023) / 1024 ))
  _zramKb=$(awk 'NR > 1 && $1 ~ /^\/dev\/zram/ { u += $4 } END { printf "%d", u }' /proc/swaps)
  _fileMb=$(( (_curKb + 1023) / 1024 ))
  read -r _peakKb _smp < <(_swap_sampled_peak)
  _usedKb=$(awk '/^SwapTotal:/ {t = $2} /^SwapFree:/ {f = $2} END {print t - f}' /proc/meminfo)
  [ "${_usedKb}" -gt "${_peakKb}" ] && _peakKb="${_usedKb}"
  _peakKb=$(( _peakKb - _zramKb ))
  [ "${_peakKb}" -lt 0 ] && _peakKb=0
  _peakMb=$(( _peakKb / 1024 ))
  _totMb=$(( _othMb + _fileMb ))

  read -r _want _needMb _act < <(_swap_plan "${_ramMb}" "${_othMb}" \
    "${_fileMb}" "${_peakMb}" "$(cat "${_mark}" 2> /dev/null)")

  _sum="RAM ${_ramMb} MB, swap ${_totMb} MB (/swapfile ${_fileMb} MB), 14-day peak ${_peakMb} MB in ${_smp} samples, target ${_want} MB"
  if [ "${_act}" = "keep" ]; then
    [ "${_curKb}" -gt 0 ] && _swap_fstab_line
    echo "$(date) ${_sum}: kept" >> "${_log}"
    return 0
  fi

  read -r _rootSz _rootUsed _rootAv < <(df -Pk / | awk 'NR == 2 {print $2, $3, $4}')
  _roomMb=$(_swap_room "${_rootUsed}" "${_rootAv}")
  if [ "${_needMb}" -gt "${_roomMb}" ]; then
    # The new file is built beside the old one, so the room is counted with
    # the old file still on disk. A shrink waits for room to build its file.
    _roomMb=$(( _roomMb / 256 * 256 ))
    if [ "${_act}" = "grow" ] && [ "${_roomMb}" -ge $(( _fileMb + 256 )) ]; then
      _sum="${_sum}, room on / for ${_roomMb} of the ${_needMb} MB file"
      _needMb="${_roomMb}"
    else
      echo "$(date) ${_sum}: no room on / for a ${_needMb} MB file (it would pass 80% or leave under 2 GB free)" >> "${_log}"
      return 0
    fi
  fi

  mkdir -p /etc/boa/control
  if [ "${_curKb}" -eq 0 ]; then
    rm -f /swapfile
    if ! _swap_make_file /swapfile "${_needMb}"; then
      touch "${_off}"
      echo "$(date) ${_sum}: building a ${_needMb} MB /swapfile FAILED, next try in 7 days" >> "${_log}"
      return 0
    fi
    _swap_fstab_line
    echo "${_needMb}" > "${_mark}"
    echo "$(date) ${_sum}: /swapfile created, ${_needMb} MB" >> "${_log}"
    return 0
  fi

  # The kernel refuses to rename a swap file that is on, so the new file is
  # built and tried under another name, switched off again while it is still
  # empty, and takes the name once the old one is off: for those seconds only
  # the other swap areas are on, so the swapoffs go ahead only under
  # _swap_off_fits, checked again right before them (a dd build can take
  # minutes). Pages stay in swap until something needs them, so a /swapfile may
  # stay too full to switch off for a long time: a grow then adds the missing
  # room as a second area beside it, which freezes nothing, and a later pass
  # makes one file of them once both can go. A shrink just waits.
  if ! _swap_off_fits "${_curUsed}"; then
    if [ "${_act}" = "grow" ] && _swap_make_file "${_swn}" $(( _needMb - _fileMb )); then
      echo "$(date) ${_sum}: ${_curUsed} kB in /swapfile, too much to switch off; ${_swn} of $(( _needMb - _fileMb )) MB on beside it" >> "${_log}"
      return 0
    fi
    if [ "${_act}" = "grow" ]; then
      touch "${_off}"
      echo "$(date) ${_sum}: building a $(( _needMb - _fileMb )) MB ${_swn} beside /swapfile FAILED, next try in 7 days" >> "${_log}"
      return 0
    fi
    echo "$(date) ${_sum}: ${_act} waits, ${_curUsed} kB in /swapfile, too much to switch off now" >> "${_log}"
    return 0
  fi
  if ! _swap_make_file "${_swn}" "${_needMb}"; then
    touch "${_off}"
    echo "$(date) ${_sum}: building a ${_needMb} MB file to ${_act} /swapfile FAILED, next try in 7 days" >> "${_log}"
    return 0
  fi
  read -r _newKb _newUsed < <(_swap_area_kb "${_swn}")
  read -r _curKb _curUsed < <(_swap_area_kb /swapfile)
  if ! _swap_off_fits $(( _newUsed + _curUsed )); then
    echo "$(date) ${_sum}: ${_act} waits, swap use grew or free RAM fell while the new file was built; ${_swn} left on until the next pass" >> "${_log}"
    return 0
  fi
  if ! swapoff "${_swn}" 2> /dev/null; then
    echo "$(date) ${_sum}: switching the new ${_swn} off FAILED, left on beside /swapfile" >> "${_log}"
    return 0
  fi
  if ! swapoff /swapfile 2> /dev/null; then
    rm -f "${_swn}"
    echo "$(date) ${_sum}: swapoff /swapfile FAILED, /swapfile kept at ${_fileMb} MB" >> "${_log}"
    return 0
  fi
  if ! mv -f "${_swn}" /swapfile; then
    # The old file keeps the name and is a valid swap area: put it back on
    # (something may have done so already). Back off only once it is on, or
    # nothing builds a swap file for a week.
    rm -f "${_swn}"
    swapon /swapfile 2> /dev/null
    read -r _curKb _curUsed < <(_swap_area_kb /swapfile)
    if [ "${_curKb}" -gt 0 ]; then
      touch "${_off}"
      echo "$(date) ${_sum}: the new file could not take the name, /swapfile back on as it was, next try in 7 days" >> "${_log}"
    else
      echo "$(date) ${_sum}: the new file could not take the name and /swapfile would not go back on, the next pass builds one" >> "${_log}"
    fi
    return 0
  fi
  # The file holding the name is BOA's own from here on, on or not.
  echo "${_needMb}" > "${_mark}"
  if swapon /swapfile 2> /dev/null; then
    _swap_fstab_line
    echo "$(date) ${_sum}: /swapfile ${_act}: ${_fileMb} MB to ${_needMb} MB" >> "${_log}"
    return 0
  fi
  # The new file has the name but would not switch on, although it did as
  # ${_swn} a moment ago: no back-off, the next pass switches it on or
  # rebuilds it.
  echo "$(date) ${_sum}: the new ${_needMb} MB /swapfile would not switch on, no /swapfile on, the next pass builds one" >> "${_log}"
}

# Main action function
_graceful_action() {
  echo "Starting system maintenance tasks..."

  # Update Devuan mirrors daily
  _ffDevuan="$(which ffdevuan)"
  _pthLog="/var/log/boa/ffdevuan.update.log"
  if [ -x "${_ffDevuan}" ]; then
    bash ${_ffDevuan} >> ${_pthLog}
    wait
    echo "Devuan Mirrors Updated on [$(date)]" >> ${_pthLog}
    echo >> ${_pthLog}
  fi

  # Clean up postfix queue to get rid of bounced emails
  echo "Removing bounce notices from postfix queue..."
  _purge_postfix_bounces

  # Restart syslog service
  echo "Restarting syslog service..."
  if [ -e "/etc/init.d/rsyslog" ]; then
    pkill -9 rsyslogd
    service rsyslog start
  fi

  # Nothing empties swap or the page cache on a schedule: a page in swap costs
  # nothing until it is touched and swapoff freezes its owner (see
  # _swap_off_fits); clean cache the kernel frees on demand, and a drop sends
  # every site back to the disk for its files.

  # The marker: multiback's swapon stands aside while it names this run, a
  # second run (by hand beside the cron one) leaves swap to the first, and one
  # left by a killed run makes autoupboa switch /swapfile back on. It is
  # claimed by link(2), so it appears whole or not at all and
  # only when absent; a stale one is cleared here, unless a swapoff the killed
  # run started still runs (its trace stays for autoupboa).
  _rszOwn=NO
  _rszTmp="/run/.boa_swap_size.$$"
  if printf '%s\n' "$$" > "${_rszTmp}" 2> /dev/null; then
    if ln "${_rszTmp}" /run/boa_swap_size.pid 2> /dev/null; then
      _rszOwn=YES
    else
      _rszOld=$( { tr -dc '0-9' < /run/boa_swap_size.pid; } 2> /dev/null )
      if [ -n "${_rszOld}" ] && ! _swap_resize_running \
        && ! pgrep -x swapoff > /dev/null 2>&1 \
        && [ "$( { tr -dc '0-9' < /run/boa_swap_size.pid; } 2> /dev/null )" = "${_rszOld}" ]; then
        rm -f /run/boa_swap_size.pid /run/boa_swap_size.start
        ln "${_rszTmp}" /run/boa_swap_size.pid 2> /dev/null && _rszOwn=YES
      fi
    fi
  fi
  rm -f "${_rszTmp}"
  if [ "${_rszOwn}" = "YES" ]; then
    printf '%s %s\n' "$$" "$(sed 's/^.*) //' "/proc/$$/stat" 2> /dev/null | awk '{print $20}')" \
      > "${_rszTmp}.start" 2> /dev/null \
      && mv -f "${_rszTmp}.start" /run/boa_swap_size.start
    rm -f "${_rszTmp}.start"
    echo "Sizing swap..."
    _size_swap
    if [ "$( { tr -dc '0-9' < /run/boa_swap_size.pid; } 2> /dev/null )" = "$$" ]; then
      rm -f /run/boa_swap_size.pid /run/boa_swap_size.start
    fi
  else
    echo "Swap sizing skipped: another graceful.sh run is sizing swap, a swapoff it started still runs, or /run is full"
  fi

  echo "Removing empty login-session cgroups..."
  _trim_session_cgroups

  echo "Checking for PHP-FPM versions idle all day..."
  _reload_idle_fpm_versions

  echo "Checking the country database nginx reads..."
  _refresh_country_db
  _refresh_goaccess_db
  _check_country_db

  # Cleanup for /opt/tmp/sess*
  rm -f /opt/tmp/sess*

  _purge_weekly_backups

  # Speed cleanup
  _IF_BCP=""
  [ "$(_dcy_live_count)" -gt 0 ] && _IF_BCP=YES
  if [ -z "${_IF_BCP}" ] && [ ! -e "/run/speed_cleanup.pid" ] && [ ! -e "/root/.giant_traffic.cnf" ]; then
    echo "Performing speed cleanup..."
    touch /run/speed_cleanup.pid
    echo " " >> /var/log/nginx/speed_cleanup.log
    sed -i "s/levels=2:2:2/levels=2:2/g" /var/aegir/config/server_master/nginx.conf
    service nginx reload &> /dev/null
    echo "speed_purge start $(date)" >> /var/log/nginx/speed_cleanup.log
    nice -n 9 ionice -c2 -n7 find /var/lib/nginx/speed/ -mtime +1 -exec rm -rf {} \; &> /dev/null
    echo "speed_purge complete $(date)" >> /var/log/nginx/speed_cleanup.log
    service nginx reload &> /dev/null
    rm -f /run/speed_cleanup.pid
  fi

  touch /var/log/boa/graceful.done.pid
  echo "System maintenance tasks completed."
}

# Main script execution

# Check for ongoing operations or skip configurations
# In-flight gate. This mirrors _boa_pass_active in owl.sh deliberately (see the
# master/satellite mirror rule): boa_run.pid alone is not enough -- the chained
# install's octopus leg holds only octopus_install_run.pid, boa_wait.pid covers
# the queued window, and the Ægir setup children match none of the wrapper forms
# yet are exactly the phase that rewrites the trees this script sed's and
# reloads nginx against.
_boa_pass_active() {
  [ -e "/run/boa_run.pid" ] && return 0
  [ -e "/run/boa_wait.pid" ] && return 0
  [ -e "/run/octopus_install_run.pid" ] && return 0
  # xmass windows: the init/copy-back phase is exactly when a swapoff can
  # OOM the restore. Fresh-bounded like their consumers
  # (second.sh 2880 min for the init signal, mysql.sh 240 min for the
  # maintenance mute) so a stale marker cannot park this script forever.
  [ -n "$(find /run/boa_xmass_init.pid /root/.standby.init.pid -mmin -2880 2> /dev/null)" ] && return 0
  [ -n "$(find /run/boa_sql_maintenance.pid -mmin -240 2> /dev/null)" ] && return 0
  pgrep -u root -U root -f "^(/[^ ]*/)?bash (-c )?/(var/backups|var/opt/boa-dist)/(BARRACUDA|OCTOPUS)\.sh\.txt" > /dev/null 2>&1 && return 0
  pgrep -u root -U root -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/(barracuda|octopus)( |$)" > /dev/null 2>&1 && return 0
  pgrep -u root -U root -f "^(/[^ ]*/)?bash (-c )?/(opt|usr)/local/bin/boa in-" > /dev/null 2>&1 && return 0
  pgrep -u root -U root -f "^(/[^ ]*/)?(bash|sh|su) .*/aegir/scripts/AegirSetup[ABC]\.sh\.txt" > /dev/null 2>&1 && return 0
  return 1
}

if _boa_pass_active || [ -e "/root/.skip_cleanup.cnf" ]; then
  echo "Cleanup skipped due to ongoing operations or configuration settings."
  exit 0
else
  _graceful_action
  exit 0
fi
