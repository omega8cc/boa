#!/bin/bash

# =============================================================================
# escapecheck.sh — lsh shell escape monitor for BOA
# Replaces: escapecheck.pl
#
# Scans /var/log/lsh/*.log for forbidden command attempts in the current or
# previous minute, logs matches, and emails an alert via s-nail if any found.
# Each line is logged and mailed once, though the runs of one minute all read
# it; a refusal of a plain command and a forbidden /dev/null stay in the lshell
# logs only; lock.inc's ratelimit holds mails back, and a held line goes out
# with the next mail.
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
# The lines found and not yet mailed; the mail body.
readonly _LOGFILE="${_BOA_LOG_DIR}/last-shell-escape-log"
readonly _DEBUG_LOG="${_BOA_LOG_DIR}/last-shell-escape-y-problem"
# The window's lines already logged, as the last run left them.
readonly _SEEN_FILE="${_BOA_LOG_DIR}/last-shell-escape-seen"
readonly _BARRACUDA_CNF="/root/.barracuda.cnf"
readonly _LOCK_FILE="/var/run/escapecheck.lock"
# Lines kept for the next mail while the ratelimit holds it: past the total,
# each log keeps its newest lines up to the per-log count, and the lines
# dropped are counted for the next mail. A queued line is cut at its length.
readonly _QUEUE_MAX=1000
readonly _QUEUE_PER_LOG=100
readonly _QUEUE_LINE_MAX=2000
# A longer line is never read as routine.
readonly _ROUTINE_LINE_MAX=4096
readonly _DROPPED_FILE="${_BOA_LOG_DIR}/last-shell-escape-dropped"

_SERVER=$(uname -n)
readonly _SERVER

# lock.inc's _incident_email_ratelimit; without it every alert goes out.
for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
  [[ -r "${_L}" ]] && . "${_L}" && break
done

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
# Reads _MY_EMAIL (and _INCIDENT_EMAIL_COOLDOWN_SECS, the ratelimit's hold)
# from .barracuda.cnf without sourcing it: the last assignment
# wins, as it does for the checks that source the file, and quotes around the
# value are taken off. bash's =~ is POSIX ERE, where \s and \S are the letters
# s and S, so the classes are spelled out.
# Unescapes \+ -> + in the address (BOA config convention).
# Checks s-nail is available before attempting to send.
#
# The body is the lines not yet mailed (_LOGFILE). The ratelimit holds a mail
# back and keeps those lines for the next one, so each line is mailed once,
# and held lines go out once the hold ends, new lines or not. With no address
# or no usable s-nail the lines are dropped from the queue; the debug log
# keeps every line in any case.
# -----------------------------------------------------------------------------

_read_email() {
  local _line _val
  _EMAIL=""
  _COOL=""
  [[ -r "${_BARRACUDA_CNF}" ]] || return 0
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    if [[ "${_line}" =~ ^[[:space:]]*(_MY_EMAIL|_INCIDENT_EMAIL_COOLDOWN_SECS)[[:space:]]*=[[:space:]]*([^[:space:]]*) ]]; then
      _val="${BASH_REMATCH[2]}"
      _val="${_val#[\"\']}"
      _val="${_val%[\"\']}"
      if [[ "${BASH_REMATCH[1]}" == "_MY_EMAIL" ]]; then
        _EMAIL="${_val}"
      else
        _COOL="${_val//[^0-9]/}"
      fi
    fi
  done < "${_BARRACUDA_CNF}"
  # Unescape \+ -> + (BOA stores addresses as user\+tag@domain in some configs)
  _EMAIL="${_EMAIL//\\+/+}"
}

_send_alert() {
  [[ -s "${_LOGFILE}" ]] || return 0

  _read_email
  # Check s-nail is present and built for Linux (mirrors Perl $mailx_test check)
  local _mailx_test
  _mailx_test=$(s-nail -V 2>&1)
  if [[ -z "${_EMAIL}" ]] || [[ ! "${_mailx_test,,}" =~ "built for linux" ]]; then
    : > "${_LOGFILE}"
    rm -f "${_DROPPED_FILE}"
    return 0
  fi

  if declare -F _incident_email_ratelimit > /dev/null; then
    # the operator's cooldown from the cnf, as the checks that source it see it
    _incident_email_ratelimit "shell-escape" ${_COOL:+"${_COOL}"} || return 0
  fi

  local _count _dropped _more=""
  _count=$(grep -c '' "${_LOGFILE}")
  _dropped=$(tr -dc '0-9' 2> /dev/null < "${_DROPPED_FILE}")
  (( ${_dropped:-0} > 0 )) && _more=", ${_dropped} more in ${_DEBUG_LOG}"
  if s-nail -s "Shell Escape Alert [${_SERVER}] ${_count} new line(s) at ${_NOW_IS}${_more}" \
           "${_EMAIL}" \
           < "${_LOGFILE}"; then
    : > "${_LOGFILE}"
    rm -f "${_DROPPED_FILE}"
  fi
}

# -----------------------------------------------------------------------------
# Main detection logic  (replaces makeactions)
# -----------------------------------------------------------------------------

# The forbidden lines of this minute ($2) and the last ($3) in the lshell logs
# of the directory $1, as "<owner uid> <log>:<line>", at most 999 for each owner: a log
# named <login>.log (no colon, so the prefix ends at the first ".log:"), read
# only when lstat and the opened handle agree it is the same regular file, and
# only its last MiB (lshell appends, so this minute's lines are at the end;
# read from the byte before, so a line starting there is whole); at most 20
# logs opened for each owner, and none more for an owner at its cap. However
# long or many the logs, a run reads at most 20 MiB for each owner.
_LSH_FORBIDDEN_PL='use Fcntl; my ($dir, $a, $b) = @ARGV; opendir(my $dh, $dir) or exit 0; my @f = sort grep { /\A[A-Za-z0-9._-]+\.log\z/ } readdir $dh; closedir($dh); my (%n, %o); for my $f (@f) { my $p = "$dir/$f"; my @l = lstat($p); next unless @l && -f _; next if ($n{$l[4]} // 0) >= 999 || ($o{$l[4]} // 0) >= 20; sysopen(my $h, $p, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or next; my @s = stat($h); unless (@s && -f _ && $s[0] == $l[0] && $s[1] == $l[1]) { close($h); next } my $u = $s[4]; $o{$u}++; my $off = $s[7] > 1048576 ? $s[7] - 1048577 : 0; my $d = ""; if (sysseek($h, $off, 0)) { my $b2; while (length($d) < 1048577 && sysread($h, $b2, 65536)) { $d .= $b2 } } close($h); $d =~ s/\A[^\n]*\n// if $off; for my $line (split /\n/, $d) { next unless $line =~ /forbidden/i; my $t = $line; $t =~ s/\A[ \t]+//; $t = substr($t, 0, 16); next unless $t eq $a || $t eq $b; last if ++$n{$u} > 999; print "$u $p:$line\n" } } exit 0'

# A shell's name, or a word that starts a shell or another user.
_is_launch_word() {
  case "${1}" in
    sh|bash|bash-static|dash|ash|zsh|zsh-static|ksh|ksh93|mksh|mksh-static|pdksh|oksh|lksh|rksh|rksh93|csh|bsd-csh|tcsh|fish|posh|yash|sash|rzsh|busybox|rbash) return 0 ;;
    exec|env|nohup|setsid|su|sudo|doas|pkexec) return 0 ;;
  esac
  return 1
}

# The whole line of a refusal, as lshell 0.11.16 and later log it: plain
# words (letters, digits, . _ = + , : @ - and quotes), none a shell or a
# launcher once its quotes are dropped, and no path but /dev/null, alone or
# as the target of a redirect (2>/dev/null, > /dev/null, &>/dev/null and
# </dev/null), with 2>&1 and the like beside it. Anything else, a pipe, a
# list, an expansion, another path or a control char lshell wrote as \xNN,
# is no plain line.
_is_plain_line() {
  local _w _bare _want_null=0
  local -a _words=()
  local _re_null='^([0-9]?>>?|&>>?|<)?/dev/null$'
  local _re_op='^([0-9]?>>?|&>>?|<)$'
  local _re_dup='^[0-9]?>&[0-9]$'
  local _re_word="^[A-Za-z0-9._=+,:@\"'-]+\$"
  read -r -a _words <<< "${1}"
  (( ${#_words[@]} )) || return 1
  for _w in "${_words[@]}"; do
    if (( _want_null )); then
      [[ "${_w}" == "/dev/null" ]] || return 1
      _want_null=0
    elif [[ "${_w}" =~ ${_re_null} || "${_w}" =~ ${_re_dup} ]]; then
      :
    elif [[ "${_w}" =~ ${_re_op} ]]; then
      _want_null=1
    elif [[ "${_w}" =~ ${_re_word} ]]; then
      _bare="${_w//[\"\']/}"
      _is_launch_word "${_bare}" && return 1
    else
      return 1
    fi
  done
  (( ! _want_null ))
}

# A refusal that grants nothing and shows no attempt to get round the shell:
# lshell turned down a command that is one plain word (letters, digits and
# . _ = + -), not a shell's name nor a word that starts a shell or another
# user (exec, env, su, sudo and the like), or the path /dev/null exactly. Both
# stay in the lshell logs only. Only the two kinds lshell logs as one parsed
# word are read so: a command over SSH, a shell escape or a control char is
# logged as the whole line its sender wrote, so its quotes can show any text.
# The kind is read before the first quote, which lshell writes. From lshell
# 0.11.16 a refusal that names one word of a longer line ends with
# in "<line>", and that line must be plain too (_is_plain_line). An older
# lshell logs the first word or path of a line it refuses, not the line: a
# line whose first refusal is such a word or /dev/null is left out with it.
_is_routine() {
  local _l="${1}" _head _rest _word _after _typed=""
  # A routine line is short; the pattern cuts below take minutes on a line
  # of hundreds of thousands of characters.
  (( ${#_l} <= _ROUTINE_LINE_MAX )) || return 1
  [[ "${_l}" == *\"*\"* ]] || return 1
  _head="${_l%%\"*}"
  _rest="${_l#*\"}"
  _word="${_rest%%\"*}"
  _after="${_rest#*\"}"
  if [[ -n "${_after}" ]]; then
    # The refused word ends at its closing quote; only the line may follow.
    [[ "${_after}" == ' in "'*'"' ]] || return 1
    _typed="${_after#' in "'}"
    _typed="${_typed%\"}"
  fi
  case "${_head}" in
    *"): lshell: forbidden path: ")
      [[ "${_word}" == "/dev/null" ]] || return 1 ;;
    *"): lshell: forbidden command: ")
      _is_launch_word "${_word}" && return 1
      [[ "${_word}" =~ ^[A-Za-z0-9][A-Za-z0-9._=+-]*$ ]] || return 1 ;;
    *)
      return 1 ;;
  esac
  [[ -z "${_after}" ]] || _is_plain_line "${_typed}"
}

_makeactions() {
  mkdir -p "${_BOA_LOG_DIR}"
  umask 077

  _set_timestamps

  local _status="CLEAN" _raw _seen_line _logname _owner _qline
  local -A _SEEN=() _NEXT=()

  # A run that finds no record (the first one, or the first after a reboot
  # under an older copy) starts the queue afresh: the old copy rewrote
  # _LOGFILE on every run, so its lines would be read again below.
  if [[ -f "${_SEEN_FILE}" ]]; then
    while IFS= read -r _seen_line; do
      [[ -n "${_seen_line}" ]] && _SEEN["${_seen_line}"]=1
    done < "${_SEEN_FILE}"
  else
    rm -f "${_LOGFILE}" "${_DROPPED_FILE}"
  fi

  # The forbidden lines of every lshell log, read as the reader below says.
  while LC_ALL=C IFS= read -r _line; do
    # the owner of the log, which its login cannot choose
    _owner="${_line%% *}"
    _line="${_line#* }"
    _raw="${_line}"
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

    _is_routine "${_line}" && continue

    # Once per line: every run of the window reads it again. The record keeps
    # only the window's lines, which is all a later run can read.
    _NEXT["${_raw}"]=1
    [[ -n "${_SEEN["${_raw}"]+x}" ]] && continue

    _status="ERROR"
    # The mail names the log a line came from and its owner: the line's text
    # is the login's own, the log's name and owner are not.
    _logname="${_raw%%.log:*}"
    _logname="${_logname##*/}.log"
    # A control character (a carriage return) would let the text pose as
    # another line, owner and log in the mail. Cut first: a substitution over
    # the whole line of a login's making takes minutes on a long one.
    _qline="${_line:0:${_QUEUE_LINE_MAX}}"
    _qline="${_qline//[[:cntrl:]]/ }"
    echo "[${_owner//[^0-9]/}] ${_logname}: ${_qline}" >> "${_LOGFILE}"
    echo "[${_NOW_IS}]:[${_NOW_IS}]:[${_line}]" >> "${_DEBUG_LOG}"

  # The logs are read by _LSH_FORBIDDEN_PL: the directory is writable by every
  # lshell login, each log is its login's own and any line in it is the
  # login's to write, so a log is read only as a regular file reached without a
  # link (never blocking on a FIFO), named as lshell names it, its last MiB
  # only, at most 20 logs an owner, the window (this minute and the last)
  # applied before any cap, and the cap of 999 lines per owner: one login's
  # long, busy or many logs must not push another login's fresh lines out of
  # the alert, nor make this run long.
  done < <(perl -e "${_LSH_FORBIDDEN_PL}" "${_LSH_LOG_DIR}" "${_NOW_IS}" "${_PREV_IS}" 2>/dev/null)

  if (( ${#_NEXT[@]} )); then
    printf '%s\n' "${!_NEXT[@]}" > "${_SEEN_FILE}.tmp" \
      && mv -f "${_SEEN_FILE}.tmp" "${_SEEN_FILE}"
  else
    : > "${_SEEN_FILE}"
  fi

  # A queue the ratelimit held through a flood keeps the newest lines of each
  # log owner (a login can make logs of any name, never another owner), so one
  # login's lines never push another login's out of the mail.
  if [[ "${_status}" != "CLEAN" ]] \
    && (( $(grep -c '' "${_LOGFILE}") > _QUEUE_MAX )); then
    local _cut _was
    if LC_ALL=C awk -v m="${_QUEUE_PER_LOG}" -v df="${_LOGFILE}.cut" '
        NR == FNR { c[$1]++; next }
        { if (++s[$1] > c[$1] - m) print; else d++ }
        END { print d + 0 > df }' "${_LOGFILE}" "${_LOGFILE}" > "${_LOGFILE}.tmp"; then
      _cut=$(tr -dc '0-9' 2> /dev/null < "${_LOGFILE}.cut")
      _was=$(tr -dc '0-9' 2> /dev/null < "${_DROPPED_FILE}")
      echo "$(( ${_was:-0} + ${_cut:-0} ))" > "${_DROPPED_FILE}"
      mv -f "${_LOGFILE}.tmp" "${_LOGFILE}"
    fi
    rm -f "${_LOGFILE}.tmp" "${_LOGFILE}.cut"
  fi

  _send_alert
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------

_acquire_lock
_makeactions
