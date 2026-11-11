#!/bin/bash

# =============================================================================
# escapecheck.sh — lsh shell escape monitor for BOA
# Replaces: escapecheck.pl
#
# Scans /var/log/lsh/*.log for forbidden command attempts in the current or
# previous minute, logs matches, and emails an alert via s-nail if any found.
#
# Improvements over the Perl original:
#   - Accepts current AND previous minute (closes cron timing race window)
#   - Fixes s-nail invocation: Perl used system(list) which passed '<' and the
#     logfile path as literal arguments to s-nail rather than shell redirection,
#     so the email body was always empty; bash uses proper stdin redirection
#   - noclobber lock prevents overlapping cron runs
#   - _MY_EMAIL unescaping (\+ -> +) preserved from original
#
# Requires: bash >= 4.2, s-nail (for email alerts)
# =============================================================================

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly _BOA_LOG_DIR="/var/log/boa"
readonly _LSH_LOG_DIR="/var/log/lsh"
readonly _LOGFILE="${_BOA_LOG_DIR}/last-shell-escape-log"
readonly _DEBUG_LOG="${_BOA_LOG_DIR}/last-shell-escape-y-problem"
readonly _BARRACUDA_CNF="/root/.barracuda.cnf"
readonly _LOCK_FILE="/var/run/escapecheck.lock"

_SERVER=$(uname -n)
readonly _SERVER

# -----------------------------------------------------------------------------
# Lock
# -----------------------------------------------------------------------------

_acquire_lock() {
  if ! ( set -o noclobber; echo "$$" > "${_LOCK_FILE}" ) 2>/dev/null; then
    local _existing_pid
    _existing_pid=$(cat "${_LOCK_FILE}" 2>/dev/null)
    if kill -0 "${_existing_pid}" 2>/dev/null; then
      exit 0
    else
      echo "$$" > "${_LOCK_FILE}"
    fi
  fi
  trap 'rm -f "${_LOCK_FILE}"' EXIT INT TERM
}

# -----------------------------------------------------------------------------
# Timestamp helpers
#
# lsh log format: "YYYY-MM-DD HH:MM:SS,mmm [pid] FORBIDDEN: ..."
# Comparator:     "YYYY-MM-DD HH:MM"
#
# Unlike auth.log this is a single fixed format — no dual-format detection
# needed.  Current AND previous minute accepted (same cron race fix as
# hackcheck.sh / hackftp.sh).
# -----------------------------------------------------------------------------

_NOW_IS=""   # "YYYY-MM-DD HH:MM"
_PREV_IS=""  # "YYYY-MM-DD HH:MM"  (one minute ago)

_set_timestamps() {
  _NOW_IS=$(date +%Y-%m-%d\ %H:%M)
  _PREV_IS=$(date -d '1 minute ago' +%Y-%m-%d\ %H:%M)
}

# Extract "YYYY-MM-DD HH:MM" from an lsh log line and check against window.
# lsh line fields: DATE TIME,ms rest...
#   field1: 2026-05-10
#   field2: 12:35:28,123   → strip comma and anything after it → 12:35:28
#           → strip non-numeric/colon  → keep HH:MM part
_line_is_recent() {
  local _line="${1}"
  local _dateq _timeq _timex _hour _min

  read -r _dateq _timeq _ <<< "${_line}"

  # Strip milliseconds: "12:35:28,123" -> "12:35:28"
  _timex="${_timeq%%,*}"
  # Strip anything non-numeric or non-colon (mirrors Perl $TIMEX =~ s/[^0-9\:]//g)
  _timex="${_timex//[^0-9:]/}"
  [[ "${_timex}" =~ ^[0-9] ]] || return 1

  _hour="${_timex%%:*}"
  _min="${_timex#*:}"; _min="${_min%%:*}"

  local _log_is="${_dateq} ${_hour}:${_min}"
  [[ "${_log_is}" == "${_NOW_IS}" || "${_log_is}" == "${_PREV_IS}" ]]
}

# -----------------------------------------------------------------------------
# Email helper
#
# Reads _MY_EMAIL from .barracuda.cnf (same regex as Perl original).
# Unescapes \+ -> + in the address (BOA config convention).
# Checks s-nail is available before attempting to send.
#
# FIX: Perl original used system('s-nail', '-s', subject, email, '<', logfile)
# which passes '<' as a literal argument (system(list) bypasses the shell),
# making the email body always empty.  Correct form is stdin redirection.
# -----------------------------------------------------------------------------

_send_alert() {
  local _email="" _line

  if [[ -r "${_BARRACUDA_CNF}" ]]; then
    while IFS= read -r _line; do
      if [[ "${_line}" =~ ^\s*_MY_EMAIL\s*=\s*(\S+) ]]; then
        _email="${BASH_REMATCH[1]}"
        break
      fi
    done < "${_BARRACUDA_CNF}"
  fi

  # Unescape \+ -> + (BOA stores addresses as user\+tag@domain in some configs)
  _email="${_email//\\+/+}"

  [[ -n "${_email}" ]] || return 0
  [[ -s "${_LOGFILE}" ]] || return 0

  # Check s-nail is present and built for Linux (mirrors Perl $mailx_test check)
  local _mailx_test
  _mailx_test=$(s-nail -V 2>&1)
  if [[ "${_mailx_test,,}" =~ "built for linux" ]]; then
    s-nail -s "Shell Escape Alert [${_SERVER}] ${_NOW_IS}" \
           "${_email}" \
           < "${_LOGFILE}"
  fi
}

# -----------------------------------------------------------------------------
# Main detection logic  (replaces makeactions)
# -----------------------------------------------------------------------------

# The forbidden lines of this minute ($2) and the last ($3) in the lshell logs
# of the directory $1, as "<log>:<line>", at most 999 for each owner: a log
# named <login>.log (no colon, so the prefix ends at the first ".log:"), read
# only when lstat and the opened handle agree it is the same regular file, and
# only its last MiB (lshell appends, so this minute's lines are at the end); an
# owner at its cap has no further log opened. However long or many the logs,
# a run reads at most a MiB a log.
_LSH_FORBIDDEN_PL='use Fcntl; my ($dir, $a, $b) = @ARGV; opendir(my $dh, $dir) or exit 0; my @f = sort grep { /\A[A-Za-z0-9._-]+\.log\z/ } readdir $dh; closedir($dh); my %n; for my $f (@f) { my $p = "$dir/$f"; my @l = lstat($p); next unless @l && -f _; next if ($n{$l[4]} // 0) >= 999; sysopen(my $h, $p, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next; my @s = stat($h); unless (@s && -f _ && $s[0] == $l[0] && $s[1] == $l[1]) { close($h); next } my $u = $s[4]; my $off = $s[7] > 1048576 ? $s[7] - 1048576 : 0; my $d = ""; if (sysseek($h, $off, 0)) { my $b2; while (length($d) < 1048576 && sysread($h, $b2, 65536)) { $d .= $b2 } } close($h); $d =~ s/\A[^\n]*\n// if $off; for my $line (split /\n/, $d) { next unless $line =~ /forbidden/i; my $t = $line; $t =~ s/\A[ \t]+//; $t = substr($t, 0, 16); next unless $t eq $a || $t eq $b; last if ++$n{$u} > 999; print "$p:$line\n" } } exit 0'

_makeactions() {
  mkdir -p "${_BOA_LOG_DIR}"

  # Fresh logfile each run — matches Perl's rm -f $logfile at startup
  rm -f "${_LOGFILE}"

  _set_timestamps

  local _status="CLEAN"

  # The forbidden lines of every lshell log, read as the reader below says.
  while LC_ALL=C IFS= read -r _line; do
    # Sanitise — strip chars outside safe set (mirrors Perl regex, adds = for lsh)
    _line="${_line//[^a-zA-Z0-9: $'\t'\/@_()*/\[\].,\-=]/}"

    # Strip the "filename.log:" prefix that grep -H adds when globbing
    # Perl did: ($log, $line) = split(/.log:/, $line)  when line contains var/log/lsh
    if [[ "${_line}" =~ var/log/lsh ]]; then
      _line="${_line#*.log:}"
      # Trim leading whitespace left after stripping prefix
      _line="${_line#"${_line%%[![:space:]]*}"}"
    fi

    # Pattern filter (mirrors Perl if/elsif):
    #   match: syntax|path|command
    #   OR: "shell escape" whose offending command is not the benign 'exit' teardown
    local _match=0
    local _ll="${_line,,}"
    if [[ "${_ll}" =~ syntax|path|command ]]; then
      _match=1
    elif [[ "${_ll}" == *"shell escape"* ]]; then
      # Skip ONLY the benign bare-'exit' teardown, closing the whole-line-'exit'
      # evasion that let an attacker suppress a real escape by embedding 'exit'
      # anywhere on the line. Anchor on the FIRST 'shell escape' (#*, not ##*): the
      # genuine 'forbidden shell escape:' label is always first, so the attacker
      # cannot re-anchor the parser by embedding the label inside their command.
      # Compare the WHOLE command (surrounding quotes + whitespace stripped) to
      # 'exit' -- a chained 'exit && wget …' or 'exit; …' is a real escape and MUST
      # alert, so only a command that IS exactly 'exit' is skipped. (The command is
      # the quoted field; the sanitiser above is a positional no-op, so strip the
      # quotes here explicitly.)
      local _esc_cmd
      _esc_cmd="${_ll#*shell escape}"                       # after the FIRST label
      _esc_cmd="${_esc_cmd#:}"                              # drop optional ':'
      _esc_cmd="${_esc_cmd#"${_esc_cmd%%[![:space:]]*}"}"   # ltrim
      _esc_cmd="${_esc_cmd%"${_esc_cmd##*[![:space:]]}"}"   # rtrim
      _esc_cmd="${_esc_cmd#\"}"; _esc_cmd="${_esc_cmd%\"}"   # strip surrounding quotes
      [[ "${_esc_cmd}" == "exit" ]] || _match=1
    fi
    (( _match )) || continue

    # Timestamp filter
    _line_is_recent "${_line}" || continue

    _status="ERROR"
    echo "${_line}" >> "${_LOGFILE}"
    echo "[${_NOW_IS}]:[${_NOW_IS}]:[${_line}]" >> "${_DEBUG_LOG}"

  # The logs are read by _LSH_FORBIDDEN_PL: the directory is writable by every
  # lshell login, each log is its login's own and any line in it is the
  # login's to write, so a log is read only as a regular file reached without a
  # link (never blocking on a FIFO), named as lshell names it, its last MiB
  # only, the window (this minute and the last) applied before any cap, and the
  # cap of 999 lines per owner: one login's long, busy or many logs must not
  # push another login's fresh lines out of the alert, nor make this run long.
  done < <(perl -e "${_LSH_FORBIDDEN_PL}" "${_LSH_LOG_DIR}" "${_NOW_IS}" "${_PREV_IS}" 2>/dev/null)

  if [[ "${_status}" != "CLEAN" ]]; then
    _send_alert
  fi
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------

_acquire_lock
_makeactions
