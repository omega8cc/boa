#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

_pthOml="/var/log/boa/system.incident.log"

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

# Run only on fully installed system
[ ! -e "/var/log/boa/reset_no_new_password.pid" ] && exit 0

: "${_CRON_COOLDOWN_SECS:=30}"
: "${_POSTFIX_COOLDOWN_SECS:=30}"
: "${_LFD_COOLDOWN_SECS:=30}"

###
### Pacing for the OOM response. Sanitised where used; the flap knobs are only
### consumed when the shared lock.inc breaker primitives are present.
###
export _OOM_COOLDOWN_SECS=${_OOM_COOLDOWN_SECS//[^0-9]/}
: "${_OOM_COOLDOWN_SECS:=60}"      # Minimum gap between two OOM kills
: "${_OOM_FLAP_MAX:=3}"            # Kills tolerated inside the window
: "${_OOM_FLAP_WINDOW_SECS:=3600}" # Window those kills are counted in
: "${_OOM_FLAP_LATCH_MINS:=60}"    # Cool-off before an open circuit re-arms
# Never the victim of an automatic kill: the database (killing it IS the outage
# this machinery exists to prevent, and on a database box it is always the
# largest resident set), the ssh lifeline, and the provision/backup chain,
# where a kill means a broken task or a corrupt dump rather than freed memory.
# Matching too much here is the SAFE direction -- an over-broad exemption skips
# a candidate, never kills an extra one.
_OOM_EXEMPT='mysqld|sshd|provision|drush|mydumper|duplicity|aegir.sh|backboa|multiback'


###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

###
### Load + normalize _INCIDENT_REPORT
###
### Legacy values:
###   NO  becomes OFF (see below)
###   YES becomes MINI (see below)
###
### Current values:
###   OFF  == Total silence, no email alerts
###   ALL  == Very noisy, good for debugging
###   MINI == Only the most important alerts (default)
###   CRIT == Only critical if _lvl=ALERT
###
_normalize_incident_report() {
  : "${_INCIDENT_REPORT:=CRIT}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT^^}"
  _INCIDENT_REPORT="${_INCIDENT_REPORT//[^A-Z]/}"
  ###
  ### Map legacy + validate
  ###
  case "${_INCIDENT_REPORT}" in
    NO)   _INCIDENT_REPORT="OFF"  ;;
    YES)  _INCIDENT_REPORT="CRIT" ;;
    MINI) _INCIDENT_REPORT="CRIT" ;;
    OFF|ALL|CRIT) : ;;
    *)    _INCIDENT_REPORT="CRIT" ;;
  esac
}
_normalize_incident_report

###
### Function to send incident email report
###
_incident_email_report() {
  _check_uptime_grace_period >/dev/null || return 1
  local _subject="${1:-(no subject)}"
  local _lvl="${2:-INFO}"
  _lvl="${_lvl^^}"
  [ -n "${_MY_EMAIL}" ] || return 1
  # Decide if we should send
  case "${_INCIDENT_REPORT}" in
    OFF)  return 1 ;;                            # always veto
    CRIT) [ "${_lvl}" = "ALERT" ] || return 1 ;; # veto unless ALERT
    ALL) : ;;                                    # allow
  esac
  # One alert per cooldown, not one per pass. This watchdog reports sixteen
  # different conditions, so a single service failing repeatedly used to bury
  # the rest. Nothing is lost: every incident is still written to the log, and
  # the mail body is the tail of that log, so the next alert that goes out
  # carries the ones held back. $3 overrides the key for a class of alert that
  # should keep its own cooldown. An older lock.inc simply sends as before.
  local _sfx=""
  # Keep the severity ladder meaningful through the throttle. This watchdog
  # reports sixteen conditions and exactly one of them is ALERT: the whole-stack
  # OOM teardown. On a shared key a routine notice about vnstat or cron could
  # hold that page back, which inverts the ranking the ladder just applied. So
  # an ALERT keeps its own cooldown by construction, not by remembering to pass
  # a key at the call site. $3 still overrides for a finer split.
  local _key="${3:-}"
  if [ -z "${_key}" ]; then
    if [ "${_lvl}" = "ALERT" ]; then
      _key="system-alert"
    else
      _key="system"
    fi
  fi
  if command -v _incident_email_ratelimit >/dev/null 2>&1; then
    if ! _incident_email_ratelimit "${_key}"; then
      echo "$(date) INFO: alert for '${_subject}' held back, one was already sent this cooldown" >> ${_pthOml}
      return 1
    fi
    if [ "${_INCIDENT_SUPPRESSED:-0}" -gt 0 ]; then
      _sfx=" (+${_INCIDENT_SUPPRESSED} more since the last alert)"
    fi
  fi
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
  s-nail -s "Incident Report on ${_hName}: ${_subject}${_sfx}" "${_MY_EMAIL}" < <(tail -n 200 "${_pthOml}")
}

_wkhtmltopdf_php_cli_oom_kill() {
  echo "$(date) OOM $1 wkhtmltopdf detected" >> ${_pthOml}
  pkill -9 -f wkhtmltopdf
  echo "$(date) OOM wkhtmltopdf killed" >> ${_pthOml}
  # No killall sleep here: a sleeping process holds almost no memory, and the
  # sleeps on a BOA box belong to the monitors themselves -- killing them just
  # makes every watchdog loop lurch forward at once.
  echo "$(date) OOM wkhtmltopdf incident response completed" >> ${_pthOml}
  _incident_email_report "OOM $1 wkhtmltopdf"
  echo >> ${_pthOml}
  exit 0
}

_oom_kill_top_offender() {
  # A memory emergency is healed by freeing memory, not by taking the site
  # down. The previous response here killed seven services within one second
  # of a single low sample -- nginx, every php-fpm pool, java, the cache
  # server (with its data files wiped) -- then restarted the database through
  # the whole-stack path, and never restarted the web tier it had killed. On
  # the box where that was measured, the kernel recorded zero OOM kills during
  # the entire event: the kernel was coping, and only this response was not.
  #
  # Now: confirm the pressure is sustained (the caller), then kill the single
  # largest resident process that is safe to kill, once per cooldown, with a
  # circuit breaker capping the run of them. If nothing is safe to kill, say
  # so loudly and leave the rest to the kernel OOM killer, which picks its
  # victims with far better information than a shell script can.
  local _now _ts _gap _victim _vpid _vrss _vcmd
  touch /run/boa_system_auto_healing.pid
  echo "$(date) OOM $1 detected" >> ${_pthOml}
  # Record kernel corroboration when present. Not required: the point of
  # acting at all is to act before the kernel has to.
  if [ -e "/var/log/kern.log" ]; then
    tail -n 200 /var/log/kern.log 2>/dev/null | grep -i "out of memory\|oom-kill" \
      | tail -n 3 >> ${_pthOml}
  fi
  _now=$(date +%s)
  if command -v _flap_breaker_is_open >/dev/null 2>&1; then
    _OOM_FLAP_MAX=$(_flap_num "${_OOM_FLAP_MAX}" 3)
    [ "${_OOM_FLAP_MAX}" -lt 1 ] && _OOM_FLAP_MAX=1
    _OOM_FLAP_WINDOW_SECS=$(_flap_num "${_OOM_FLAP_WINDOW_SECS}" 3600)
    _OOM_FLAP_LATCH_MINS=$(_flap_num "${_OOM_FLAP_LATCH_MINS}" 60)
    # The window must still hold _OOM_FLAP_MAX kills at the pace this path
    # enforces on itself, or the oldest entry ages out before the breaker can
    # count it and the circuit never opens -- silently, while the box keeps
    # SIGKILLing something every cooldown. Reachable both ways: narrowing the
    # window (120s reads as "three kills in two minutes is flapping") and
    # raising only the cooldown (1800s reads as "at most one kill per half
    # hour") each remove the cap with the other knobs left at their defaults.
    # The +30 covers the confirmation samples plus the rest of a pass.
    _OOM_FLAP_FLOOR=$(( _OOM_FLAP_MAX * (_OOM_COOLDOWN_SECS + 30) ))
    if [ "${_OOM_FLAP_WINDOW_SECS}" -lt "${_OOM_FLAP_FLOOR}" ]; then
      _OOM_FLAP_WINDOW_SECS="${_OOM_FLAP_FLOOR}"
    fi
    if _flap_breaker_is_open "/run/boa_oom_latched.pid" "${_OOM_FLAP_LATCH_MINS}" \
      "/var/log/boa/oom.kill.ledger" "${_pthOml}"; then
      echo "$(date) OOM $1: CIRCUIT OPEN, response refused -- see /run/boa_oom_latched.pid" >> ${_pthOml}
      echo >> ${_pthOml}
      rm -f /run/boa_system_auto_healing.pid
      exit 0
    fi
  fi
  if [ -s "/run/oom-monitor.cooldown" ]; then
    _ts=$(tr -dc '0-9' < /run/oom-monitor.cooldown 2>/dev/null)
    if [ -n "${_ts}" ]; then
      _gap=$(( _now - _ts ))
      # A negative gap means the clock stepped backwards: treat the stamp as
      # unusable and act, rather than going quiet until the clock catches up.
      if [ "${_gap}" -ge 0 ] && [ "${_gap}" -lt "${_OOM_COOLDOWN_SECS}" ]; then
        echo "$(date) INFO: OOM response in cooldown (${_gap}s < ${_OOM_COOLDOWN_SECS}s); skipping" >> ${_pthOml}
        rm -f /run/boa_system_auto_healing.pid
        exit 0
      fi
    fi
  fi
  if command -v _flap_prune_ledger >/dev/null 2>&1; then
    _flap_prune_ledger "/var/log/boa/oom.kill.ledger" "${_now}" "${_OOM_FLAP_WINDOW_SECS}"
    if [ "${_FLAP_COUNT}" -ge "${_OOM_FLAP_MAX}" ]; then
      # The latch carries the whole state of the breaker; the history that
      # opened it goes with it, so any re-arm starts counting at zero.
      echo "$(date) CIRCUIT OPEN: ${_FLAP_COUNT} OOM kills in the last ${_OOM_FLAP_WINDOW_SECS} seconds, so the automatic OOM response is now disabled. Fix the memory consumer, then delete this file to re-arm it; it also re-arms on its own ${_OOM_FLAP_LATCH_MINS} minutes after this stamp." > /run/boa_oom_latched.pid
      rm -f /var/log/boa/oom.kill.ledger
      echo "$(date) OOM $1: CIRCUIT OPEN after ${_FLAP_COUNT} kills within ${_OOM_FLAP_WINDOW_SECS}s -- refusing further automatic kills" >> ${_pthOml}
      _incident_email_report "OOM circuit open: automatic response disabled after ${_FLAP_COUNT} kills" "ALERT" "system-oom-circuit"
      echo >> ${_pthOml}
      rm -f /run/boa_system_auto_healing.pid
      exit 0
    fi
    # Record the attempt BEFORE acting, so a kill that takes this script (or
    # the box) with it still leaves evidence for the breaker.
    echo "${_now}" >> /var/log/boa/oom.kill.ledger
  fi
  # The single largest resident set that is safe to kill. The grep runs on a
  # ps snapshot, so an over-match only ever EXCLUDES a candidate; kernel
  # threads carry no RSS and sort last on their own.
  _victim=$(ps -eo pid=,rss=,args= --sort=-rss 2>/dev/null \
    | grep -vE "${_OOM_EXEMPT}" | head -n 1)
  _vpid=$(echo "${_victim}" | awk '{print $1}')
  _vpid=${_vpid//[^0-9]/}
  _vrss=$(echo "${_victim}" | awk '{print $2}')
  _vcmd=$(echo "${_victim}" | awk '{$1=""; $2=""; print}' | cut -c1-160)
  if [ -z "${_vpid}" ] || [ "${_vpid}" -le 1 ]; then
    echo "$(date) OOM $1: no eligible offender (everything large is exempt) -- leaving it to the kernel" >> ${_pthOml}
    _incident_email_report "OOM $1: no safe process to kill" "ALERT"
    echo >> ${_pthOml}
    rm -f /run/boa_system_auto_healing.pid
    exit 0
  fi
  kill -9 "${_vpid}" 2>/dev/null
  echo "$(date) OOM $1: killed pid ${_vpid} rss ${_vrss}kB cmd${_vcmd}" >> ${_pthOml}
  date +%s > /run/oom-monitor.cooldown
  echo "$(date) OOM incident response completed" >> ${_pthOml}
  _incident_email_report "OOM $1: top offender killed" "ALERT"
  echo >> ${_pthOml}
  rm -f /run/boa_system_auto_healing.pid
  exit 0
}

_system_oom_detection() {
  # Pressure is judged from MemAvailable, which already counts reclaimable
  # cache, and it must be SUSTAINED: one low sample is how a brief allocation
  # burst that the kernel absorbs on its own used to trigger a whole-stack
  # teardown. Stand down the moment any sample recovers.
  local _pct_free _try
  _check_system_ram
  case "${_ram_usage_percent}" in ''|*[!0-9]*) return 0 ;; esac
  _pct_free=$(( 100 - _ram_usage_percent ))
  if [ "${_pct_free}" -le 5 ]; then
    for _try in 1 2; do
      sleep 5
      _check_system_ram
      case "${_ram_usage_percent}" in ''|*[!0-9]*) return 0 ;; esac
      _pct_free=$(( 100 - _ram_usage_percent ))
      [ "${_pct_free}" -gt 5 ] && return 0
    done
    _oom_kill_top_offender "RAM ${_pct_free}pct-free sustained"
  elif [ "${_pct_free}" -le 10 ]; then
    _CNT=$(pgrep -fc wkhtmltopdf)
    if (( _CNT > 2 )); then
      _wkhtmltopdf_php_cli_oom_kill "RAM ${_pct_free}pct-free"
    fi
  fi
}

# Function to calculate RAM usage percentage as an integer
_calculate_ram_usage_percent() {
  _total_ram_kb=$1
  _available_ram_kb=$2
  used_ram_kb=$((_total_ram_kb - _available_ram_kb))

  # Using integer division to get a whole number percentage
  echo $(( (used_ram_kb * 100) / _total_ram_kb ))
}

# Function to check and display system info
_check_system_ram() {
  # Get the total and available RAM in KB
  _total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  _available_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

  # Fail towards "no reading" rather than a shell arithmetic error: a caller
  # that cannot read the pressure must do nothing destructive.
  if [ -z "${_total_ram_kb}" ] || [ -z "${_available_ram_kb}" ] \
    || [ "${_total_ram_kb}" -eq 0 ] 2>/dev/null; then
    _ram_usage_percent=""
    return 0
  fi

  # Calculate RAM usage percentage
  _ram_usage_percent=$(_calculate_ram_usage_percent ${_total_ram_kb} ${_available_ram_kb})
}

# (The per-minute drop_caches that lived here is gone. Evicting the box-wide
# page cache while memory is tight forces cold re-reads across every site at
# once -- the same stampede amplifier removed from the database heal path --
# and MemAvailable already counts reclaimable cache, so the kernel frees it on
# demand without the stampede.)

_if_fix_dhcp() {
  # Determine the correct log file
  if [ -e "/var/log/daemon.log" ]; then
    _DHCP_LOG="/var/log/daemon.log"
  else
    _DHCP_LOG="/var/log/syslog"
  fi

  # Check if the log file exists
  if [ -e "${_DHCP_LOG}" ]; then
    # Count the number of DHCP failure entries in the last 3 lines
    count=$(tail -n 3 "${_DHCP_LOG}" | grep -c "dhclient:.*Failed")

    # Debugging: Log the count value
    [ "$count" -gt 0 ] && echo "DHCP failure count: $count" >> ${_pthOml}

    # Proceed only if there is at least one failure
    if [ "$count" -gt 0 ]; then
      # Clear existing DHCP entries in csf.allow
      sed -i "s/.*DHCP.*//g" /etc/csf/csf.allow
      wait
      # Remove any empty lines
      sed -i "/^$/d" /etc/csf/csf.allow

      # Extract unique IPs from DHCP requests and add them to csf.allow
      grep DHCPREQUEST "${_DHCP_LOG}" | awk '{print $12}' | sort -u | while read -r _IP; do
        if [[ ${_IP} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          IFS='.' read -r oct1 oct2 oct3 oct4 <<< "${_IP}"
          if (( oct1 <= 255 && oct2 <= 255 && oct3 <= 255 && oct4 <= 255 )); then
            echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow
          fi
        fi
      done

      # Reload the firewall
      if [ -e "/etc/csf/csfpost.d/synproxy.sh" ]; then
        csf -ra &> /dev/null
        synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
      else
        csf -r &> /dev/null
      fi

      # Log the error and send an email report
      _thisErrLog="$(date) DHCP error detected, firewall updated"
      echo "${_thisErrLog}" >> ${_pthOml}
      _incident_email_report "DHCP error detected, firewall updated"
      echo >> ${_pthOml}
    fi
  fi
}

_cron_duplicate_instances_detection() {
  _CNT=$(pgrep -fc /usr/sbin/cron)
  if (( _CNT > 1 )); then
    # Double-check after a short grace to avoid flapping
    sleep 3
    _CNT2=$(pgrep -fc /usr/sbin/cron)
    if (( _CNT2 > 1 )); then
      _cd="/run/cron-monitor.cooldown"
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_CRON_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: Cron duplicates detected but in cooldown; skipping restart" >> ${_pthOml}
          return 0
        fi
      fi
      killall -9 cron &> /dev/null
      service cron start &> /dev/null
      # Cooldown stamp
      date +%s > "${_cd}"
      _thisErrLog="$(date) Too many Cron instances, service restarted (count=${_CNT2})"
      echo ${_thisErrLog} >> ${_pthOml}
      _incident_email_report "Too many Cron instances, service restarted (count=${_CNT2})"
      echo >> ${_pthOml}
    fi
  fi
}

_syslog_giant_log_detection() {
  if [ -e "/etc/cron.daily/logrotate" ]; then
    _SYSLOG_SIZE_TEST=$(du -s -h /var/log/syslog 2>/dev/null)
    if [[ "${_SYSLOG_SIZE_TEST}" =~ "G" ]]; then
      echo ${_SYSLOG_SIZE_TEST} too big
      bash /etc/cron.daily/logrotate &> /dev/null
      wait
      _thisErrLog="$(date) Syslog ${_SYSLOG_SIZE_TEST} too big, logrotate forced"
      echo ${_thisErrLog} >> ${_pthOml}
      _incident_email_report "Syslog ${_SYSLOG_SIZE_TEST} too big, logrotate forced"
      echo >> ${_pthOml}
    fi
  fi
}

_gpg_too_many_instances_detection() {
  _CNT=$(pgrep -fc gpg-agent)
  if (( _CNT > 5 )); then
    pkill -9 -f gpg-agent
    _thisErrLog="$(date) Too many gpg-agent processes killed (count=${_CNT})"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many gpg-agent processes killed (count=${_CNT})"
    echo >> ${_pthOml}
  fi
}

_dirmngr_too_many_instances_detection() {
  _CNT=$(pgrep -fc dirmngr)
  if (( _CNT > 5 )); then
    pkill -9 -f dirmngr
    _thisErrLog="$(date) Too many dirmngr processes killed (count=${_CNT})"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many dirmngr processes killed (count=${_CNT})"
    echo >> ${_pthOml}
  fi
}

_ftpd_health_check_fix() {
  _ftpd_init="/usr/local/sbin/pure-config.pl"
  _ftpd_conf="/usr/local/etc/pure-ftpd.conf"
  _ftpd_bind="/usr/local/sbin/pure-ftpd"
  _ftpd_pid="/run/pure-ftpd.pid"
  _ftpd_restarted=NO
  if [ -x "/usr/local/sbin/pure-ftpd" ] \
    || [ -x "/usr/local/sbin/pure-config.pl" ]; then
    if ! pgrep -f pure-ftpd \
      || [ ! -e "/run/pure-ftpd.pid" ]; then
      if [ -e "${_ftpd_conf}" ]; then
        pkill -9 -f pure-ftpd || true
        if [ -x "${_ftpd_init}" ]; then
          ${_ftpd_init} ${_ftpd_conf}
          _ftpd_restarted=YES
        elif [ -x "${_ftpd_bind}" ]; then
          ${_ftpd_bind} ${_ftpd_conf}
          _ftpd_restarted=YES
        fi
        if [ "${_ftpd_restarted}" = "YES" ]; then
          _thisErrLog="$(date) FTPS Server was down, restarted"
          echo ${_thisErrLog} >> ${_pthOml}
          _incident_email_report "FTPS Server was down, restarted"
          echo >> ${_pthOml}
        fi
      fi
    fi
  fi
}

_postfix_health_check_fix() {
  if [ -x "/etc/init.d/postfix" ]; then
    if ! pgrep -f /usr/lib/postfix \
      || [ ! -e "/var/spool/postfix/pid/master.pid" ]; then
      # Double-check after a short grace
      sleep 2
      if ! pgrep -f /usr/lib/postfix \
        || [ ! -e "/var/spool/postfix/pid/master.pid" ]; then
        _cd="/run/postfix-monitor.cooldown"
        _now=$(date +%s)
        if [ -s "${_cd}" ]; then
          _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
          if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_POSTFIX_COOLDOWN_SECS}" ]; then
            echo "$(date) INFO: Postfix unhealthy but in cooldown; skipping restart" >> ${_pthOml}
            return 0
          fi
        fi
        service postfix restart
        wait
        date +%s > "${_cd}"
        _thisErrLog="$(date) Postfix Server was down, restarted"
        echo ${_thisErrLog} >> ${_pthOml}
        _incident_email_report "Postfix Server was down, restarted"
        echo >> ${_pthOml}
      fi
    fi
  fi
}

_vnstat_health_check_fix() {
  if [ -x "/etc/init.d/vnstat" ] && [ ! -e "/run/vnstat.pid" ]; then
    if ! pgrep -f /usr/sbin/vnstatd \
      || [ ! -e "/run/vnstat/vnstat.pid" ]; then
      service vnstat restart
      wait
      _thisErrLog="$(date) VNStat Monitor was down, restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _incident_email_report "VNStat Monitor was down, restarted"
      echo >> ${_pthOml}
    fi
  fi
}

_lfd_health_check_fix() {
  if [ -x "/etc/init.d/lfd" ]; then
    if ! pgrep -f lfd \
      || [ ! -e "/run/lfd.pid" ]; then
      _cd="/run/lfd-monitor.cooldown"
      _now=$(date +%s)
      if [ -s "${_cd}" ]; then
        _ts=$(cat "${_cd}" 2>/dev/null | tr -d '\n')
        if [ -n "${_ts}" ] && [ $((_now - _ts)) -lt "${_LFD_COOLDOWN_SECS}" ]; then
          echo "$(date) INFO: LFD unhealthy but in cooldown; skipping start" >> ${_pthOml}
          return 0
        fi
      fi
      service lfd start
      csf -e
      # Set cooldown timestamp after attempting recovery
      date +%s > "${_cd}"
      _thisErrLog="$(date) LFD Monitor was down, started"
      echo ${_thisErrLog} >> ${_pthOml}
      _incident_email_report "LFD Monitor was down, started"
      echo >> ${_pthOml}
    fi
  fi
}

_if_fix_locked_sshd() {
  _SSH_LOG="/var/log/auth.log"
  if [ `tail --lines=10 ${_SSH_LOG} \
    | grep --count "error: Bind to port 22"` -gt 0 ]; then
    pkill -9 -f /usr/sbin/sshd || true
    service ssh start
    wait
    _thisErrLog="$(date) SSHD BIND PORT error, service will be restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "SSHD BIND PORT error, service will be restarted"
    echo >> ${_pthOml}
  fi
}

_sshd_health_check_fix() {
  if [ -x "/etc/init.d/ssh" ]; then
    if ! pgrep -f /usr/sbin/sshd \
      || [ ! -e "/run/sshd.pid" ]; then
      service ssh start
      wait
      _thisErrLog="$(date) SSHD Server was down, started"
      echo ${_thisErrLog} >> ${_pthOml}
      _incident_email_report "SSHD Server was down, started"
      echo >> ${_pthOml}
    fi
  fi
}

_clamav_health_check_fix() {
  # Define file paths as variables
  _allow_conf="/root/.allow.clamav.cnf"
  _deny_conf="/root/.deny.clamav.cnf"
  _data_dir="/data/u"
  _freshclam_pid="/run/clamav/freshclam.pid"
  _clamd_pid="/run/clamav/clamd.pid"
  _clamd_service="/etc/init.d/clamav-daemon"
  _freshclam_service="/etc/init.d/clamav-freshclam"
  if [ -e "/run/max_load.pid" ] || [ -e "/run/critical_load.pid" ]; then
    return 1  # Exit the function but continue the script
  fi
  if [ -e "${_allow_conf}" ] \
    && [ ! -e "${_deny_conf}" ] \
    && [ -e "${_data_dir}" ] \
    && [ -e "${_clamd_service}" ] \
    && [ -e "${_freshclam_service}" ]; then
    if [ -x "/etc/init.d/clamav-daemon" ]; then
      if ! pgrep -f /usr/sbin/clamd \
        || [ ! -e "/run/clamav/clamd.pid" ]; then
        pkill -9 -f /usr/sbin/clamd || true
        service clamav-daemon start
        wait
        sleep 5
        _thisErrLog="$(date) Clamav was down, started"
        echo ${_thisErrLog} >> ${_pthOml}
        _incident_email_report "Clamav was down, started"
        echo >> ${_pthOml}
      fi
    fi
    if [ -x "/etc/init.d/clamav-freshclam" ]; then
      if ! pgrep -f /usr/bin/freshclam \
        || [ ! -e "/run/clamav/freshclam.pid" ]; then
        pkill -9 -f /usr/bin/freshclam || true
        service clamav-freshclam start
        wait
        sleep 15
        _thisErrLog="$(date) Freshclam was down, started"
        echo ${_thisErrLog} >> ${_pthOml}
        _incident_email_report "Freshclam was down, started"
        echo >> ${_pthOml}
      fi
    fi
  fi
}

_rsyslog_health_check_fix() {
  if [ -x "/etc/init.d/rsyslog" ]; then
    if ! pgrep -f /usr/sbin/rsyslogd \
      || [ ! -e "/run/rsyslogd.pid" ]; then
      pkill -9 -f /usr/sbin/rsyslogd || true
      service rsyslog restart
      wait
      _thisErrLog="$(date) Rsyslog was down, restarted"
      echo ${_thisErrLog} >> ${_pthOml}
      _incident_email_report "Rsyslog was down, restarted"
      echo >> ${_pthOml}
    fi
  fi
}

_sshd_health_check_fix
_if_fix_locked_sshd
_if_fix_dhcp
_rsyslog_health_check_fix
_postfix_health_check_fix
_cron_duplicate_instances_detection
_syslog_giant_log_detection

if [ -e "/run/boa_system_auto_healing.pid" ] \
  || [ -e "/run/boa_mysql_auto_healing.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ] \
  || [ -e "/run/boa_sql_backup.pid" ]; then
  exit 0
else
  _system_oom_detection
  _lfd_health_check_fix
  _ftpd_health_check_fix
  _vnstat_health_check_fix
  _gpg_too_many_instances_detection
  _dirmngr_too_many_instances_detection
  _clamav_health_check_fix
fi

echo DONE!
exit 0
