#!/bin/bash
#
# PHP segfault monitor: the kernel's own segfault lines of PHP processes,
# mailed to the operator alone (_MY_EMAIL). php.sh starts it on its passes.
#
# The kernel's ring buffer is the only source: no program but the kernel and
# root writes it, so a line another user sends to syslog never counts. The
# report names no account: which site ran in a crashed process is never
# judged from a shared log.

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_LOG_DIR="/var/xdrago/monitor/log"
# a name the Perl monitor never used: its segfault_alert.log, left behind on
# boxes, is never read or mailed
_REPORT="${_LOG_DIR}/segfault_alert.report"
_ARCHIVE="${_LOG_DIR}/segfault_alert.archive.log"
_BARRACUDA_CNF="/root/.barracuda.cnf"
# the kernel time of the newest line reported: /run, like the ring buffer,
# starts empty at each boot
_SEEN="/run/segfault_alert.seen"
_MAILED="/run/segfault_alert.mailed"
_LOCK="/run/segfault_alert.lock"
# one mail an hour at most; lines in between wait in the report
_MAIL_EVERY=3600
# kernel lines a mail carries; the archive keeps every one
_MAX_LINES=50

[ -e "/data/u/" ] || exit 0

exec 9> "${_LOCK}" || exit 0
flock -n 9 || exit 0

_SERVER="$(uname -n)"

# The kernel's lines for a PHP process that died on a segfault, as dmesg
# prints them: "[<seconds since boot>] <comm>[<pid>]: segfault at ..."
_kernel_lines() {
  LC_ALL=C dmesg 2> /dev/null \
    | LC_ALL=C grep -aE '^\[ *[0-9]+\.[0-9]+\] php[^[ ]*\[[0-9]+\]: segfault at '
}

# The lines newer than the last one reported.
_new_lines() {
  local _seen=""
  [ -f "${_SEEN}" ] && [ ! -L "${_SEEN}" ] && _seen="$(head -c 32 "${_SEEN}" | LC_ALL=C tr -cd '0-9.')"
  [[ "${_seen}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || _seen=0
  _kernel_lines | LC_ALL=C awk -v s="${_seen}" '
    { t = $0; sub(/^\[ */, "", t); sub(/\].*$/, "", t) }
    t + 0 > s + 0 { print }
  '
}

# The operator's addresses from _MY_EMAIL: the value without its quotes and
# backslashes, split on white space and commas, each word kept only when it is
# one plain address (so none starts with "-" and reads as an s-nail option).
_operator_addresses() {
  [[ $'\xc3\xa9' == ? ]] && local LC_ALL=C
  local _line="" _v _w _ws=()
  [ -f "${_BARRACUDA_CNF}" ] || return 0
  _line="$(LC_ALL=C grep -aE '^[[:space:]]*_MY_EMAIL[[:space:]]*=' "${_BARRACUDA_CNF}" | head -n 1)"
  _v="${_line#*=}"
  _v="${_v//\"/}"
  _v="${_v//\'/}"
  _v="${_v//\\/}"
  IFS=$' \t,' read -r -a _ws <<< "${_v}"
  for _w in "${_ws[@]}"; do
    [[ "${_w}" =~ ^[A-Za-z0-9_][A-Za-z0-9._%+=-]*@[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] \
      && printf '%s\n' "${_w}"
  done
}

_mail_due() {
  local _then
  [ -f "${_MAILED}" ] || return 0
  _then="$(stat -c %Y "${_MAILED}" 2> /dev/null)" || return 0
  [ "$(( $(date +%s) - _then ))" -ge "${_MAIL_EVERY}" ] || [ "${_then}" -gt "$(date +%s)" ]
}

_send_report() {
  local _ops _t _n
  mapfile -t _ops < <(_operator_addresses)
  # the archive keeps every line either way; a report no mail can carry goes
  if [ "${#_ops[@]}" -eq 0 ]; then
    echo "$(date +%y%m%d-%H%M%S) ALRT: _MY_EMAIL in ${_BARRACUDA_CNF} holds no plain address: no mail" \
      | tee -a "${_ARCHIVE}"
    touch "${_MAILED}"
    rm -f "${_REPORT}"
    return 0
  fi
  if ! [[ "$(s-nail -V 2>&1)" =~ "built for Linux" ]]; then
    echo "$(date +%y%m%d-%H%M%S) ALRT: no usable s-nail: no mail" | tee -a "${_ARCHIVE}"
    touch "${_MAILED}"
    rm -f "${_REPORT}"
    return 0
  fi
  _t="$(date +%y%m%d-%H%M)"
  # the header and at most _MAX_LINES kernel lines; the rest are named
  _n="$(grep -c 'segfault at' "${_REPORT}")"
  {
    grep -v 'segfault at' "${_REPORT}"
    grep 'segfault at' "${_REPORT}" | head -n "${_MAX_LINES}"
    [ "${_n}" -gt "${_MAX_LINES}" ] \
      && echo "... and $(( _n - _MAX_LINES )) more in ${_ARCHIVE}"
  } | s-nail -s "PHP Segfault Alert at [${_SERVER}] on ${_t}" "${_ops[@]}"
  touch "${_MAILED}"
  rm -f "${_REPORT}"
}

_makeactions() {
  local _new _last
  mkdir -p "${_LOG_DIR}"
  _new="$(_new_lines)"
  if [ -n "${_new}" ]; then
    _last="$(printf '%s\n' "${_new}" | tail -n 1 | LC_ALL=C sed -E 's/^\[ *([0-9]+\.[0-9]+)\].*$/\1/')"
    printf '%s\n' "${_last}" > "${_SEEN}"
    printf '%s\n' "${_new}" | LC_ALL=C sed "s/^/$(date +%y%m%d-%H%M%S) /" >> "${_ARCHIVE}"
    if [ ! -s "${_REPORT}" ]; then
      {
        echo "The kernel logged these segfaults of PHP processes on ${_SERVER}."
        echo "Each line names the process and its pid; the PHP-FPM error logs"
        echo "under /var/log/php name the pool of a worker that died this way."
        echo
      } > "${_REPORT}"
    fi
    printf '%s\n' "${_new}" >> "${_REPORT}"
  fi
  if [ -s "${_REPORT}" ] && _mail_due; then
    _send_report
  fi
}

_makeactions
exit 0
