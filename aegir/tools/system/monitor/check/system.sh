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

: "${_CRON_COOLDOWN_SECS:=15}"
: "${_POSTFIX_COOLDOWN_SECS:=15}"
: "${_LFD_COOLDOWN_SECS:=15}"

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "$_L" ] && . "$_L" && break
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
  _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
  echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
  s-nail -s "Incident Report on ${_hName}: ${_subject}" "${_MY_EMAIL}" < ${_pthOml}
}

_wkhtmltopdf_php_cli_oom_kill() {
  touch /run/boa_run.pid
  echo "$(date) OOM $1 wkhtmltopdf detected" >> ${_pthOml}
  sleep 3
  pkill -9 -f wkhtmltopdf
  echo "$(date) OOM wkhtmltopdf killed" >> ${_pthOml}
  killall -9 sleep &> /dev/null
  echo "$(date) OOM wkhtmltopdf incident response completed" >> ${_pthOml}
  _incident_email_report "OOM $1 wkhtmltopdf"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_oom_critical_restart() {
  touch /run/boa_run.pid
  echo "$(date) OOM $1 detected" >> ${_pthOml}
  pkill -9 -f wkhtmltopdf
  echo "$(date) OOM wkhtmltopdf killed" >> ${_pthOml}
  killall -9 sleep &> /dev/null
  killall -9 php
  echo "$(date) OOM php-cli killed" >> ${_pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/$(date +%y%m%d-%H%M)-error.log
  pkill -9 -f nginx
  echo "$(date) OOM nginx killed" >> ${_pthOml}
  pkill -9 -f php-fpm
  echo "$(date) OOM php-fpm killed" >> ${_pthOml}
  pkill -9 -f java
  echo "$(date) OOM solr/jetty killed" >> ${_pthOml}
  pkill -9 -f newrelic-daemon
  echo "$(date) OOM newrelic-daemon killed" >> ${_pthOml}
  if [ -e "/etc/init.d/valkey-server" ]; then
    rm -f /var/lib/valkey/*
    pkill -9 -f valkey-server
    echo "$(date) OOM valkey-server killed" >> ${_pthOml}
  elif [ -e "/etc/init.d/redis-server" ]; then
    rm -f /var/lib/redis/*
    pkill -9 -f redis-server
    echo "$(date) OOM redis-server killed" >> ${_pthOml}
  fi
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date) OOM Percona MySQL Server restarted" >> ${_pthOml}
  echo "$(date) OOM incident response completed" >> ${_pthOml}
  _incident_email_report "OOM $1 system" "ALERT"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_system_oom_detection() {
  _RAM_TOTAL=$(free -mt | grep Mem: | cut -d: -f2 | awk '{ print $1}' 2>&1)
  _RAM_FREE_TEST=$(free -mt 2>&1)
  if [[ "${_RAM_FREE_TEST}" =~ "buffers/cache:" ]]; then
    _RAM_FREE=$(free -mt | grep /+ | cut -d: -f2 | awk '{ print $2}' 2>&1)
  else
    _RAM_FREE=$(free -mt | grep Mem: | cut -d: -f2 | awk '{ print $6}' 2>&1)
  fi
  _RAM_PCT_FREE=$(echo "scale=0; $(bc -l <<< "${_RAM_FREE} / ${_RAM_TOTAL} * 100")/1" | bc 2>&1)
  _RAM_PCT_FREE=${_RAM_PCT_FREE//[^0-9]/}
  echo _RAM_TOTAL is ${_RAM_TOTAL}
  echo _RAM_PCT_FREE is ${_RAM_PCT_FREE}
  if [ ! -z "${_RAM_PCT_FREE}" ]; then
    if [ "${_RAM_PCT_FREE}" -le 5 ]; then
      _oom_critical_restart "RAM ${_RAM_PCT_FREE}/${_RAM_TOTAL}"
    elif [ "${_RAM_PCT_FREE}" -le 10 ]; then
      _CNT=$(pgrep -fc wkhtmltopdf)
      if (( _CNT > 2 )); then
        _wkhtmltopdf_php_cli_oom_kill "RAM ${_RAM_PCT_FREE}/${_RAM_TOTAL}"
      fi
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

  # Calculate RAM usage percentage
  _ram_usage_percent=$(_calculate_ram_usage_percent ${_total_ram_kb} ${_available_ram_kb})
}

# Function to check and optimize RAM and disk caches
_optimize_ram() {
  _check_system_ram
  if [ "${_ram_usage_percent}" -gt 90 ]; then
    sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
  fi
}

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

if [ -e "/run/boa_sql_backup.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

[ "${_ALLOW_CTRL}" = "YES" ] && _optimize_ram
[ "${_ALLOW_CTRL}" = "YES" ] && _system_oom_detection
[ "${_ALLOW_CTRL}" = "YES" ] && _lfd_health_check_fix
[ "${_ALLOW_CTRL}" = "YES" ] && _ftpd_health_check_fix
[ "${_ALLOW_CTRL}" = "YES" ] && _vnstat_health_check_fix
[ "${_ALLOW_CTRL}" = "YES" ] && _gpg_too_many_instances_detection
[ "${_ALLOW_CTRL}" = "YES" ] && _dirmngr_too_many_instances_detection
[ "${_ALLOW_CTRL}" = "YES" ] && _clamav_health_check_fix

echo DONE!
exit 0
