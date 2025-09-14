#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/log/boa/system.incident.log"

_check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

export _INCIDENT_REPORT=${_INCIDENT_REPORT//[^A-Z]/}
: "${_INCIDENT_REPORT:=YES}"

if (( $(pgrep -fc 'system.sh') > 2 )); then
  echo "Too many system.sh running $(date)" >> /var/log/boa/too.many.log
  exit 0
fi

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_REPORT}" = "YES" ]; then
    _hName="$(cat /etc/hostname 2>/dev/null | tr -d '\n' || hostname -f 2>/dev/null)"
    echo "Sending Incident Report Email on $(date)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${_hName} at $(date)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_wkhtmltopdf_php_cli_oom_kill() {
  touch /run/boa_run.pid
  echo "$(date) OOM $1 wkhtmltopdf/php-cli detected" >> ${_pthOml}
  sleep 3
  kill -9 $(ps aux | grep '[w]khtmltopdf' | awk '{print $2}') &> /dev/null
  echo "$(date) OOM wkhtmltopdf killed" >> ${_pthOml}
  killall -9 sleep &> /dev/null
  killall -9 php
  echo "$(date) OOM php-cli killed" >> ${_pthOml}
  echo "$(date) OOM wkhtmltopdf/php-cli incident response completed" >> ${_pthOml}
  _incident_email_report "OOM $1 wkhtmltopdf/php-cli"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_oom_critical_restart() {
  touch /run/boa_run.pid
  echo "$(date) OOM $1 detected" >> ${_pthOml}
  kill -9 $(ps aux | grep '[w]khtmltopdf' | awk '{print $2}') &> /dev/null
  echo "$(date) OOM wkhtmltopdf killed" >> ${_pthOml}
  killall -9 sleep &> /dev/null
  killall -9 php
  echo "$(date) OOM php-cli killed" >> ${_pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/$(date +%y%m%d-%H%M)-error.log
  kill -9 $(ps aux | grep '[n]ginx' | awk '{print $2}') &> /dev/null
  echo "$(date) OOM nginx killed" >> ${_pthOml}
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "$(date) OOM php-fpm killed" >> ${_pthOml}
  kill -9 $(ps aux | grep '[j]ava' | awk '{print $2}') &> /dev/null
  echo "$(date) OOM solr/jetty killed" >> ${_pthOml}
  kill -9 $(ps aux | grep '[n]ewrelic-daemon' | awk '{print $2}') &> /dev/null
  echo "$(date) OOM newrelic-daemon killed" >> ${_pthOml}
  if [ -e "/etc/init.d/valkey-server" ]; then
    rm -f /var/lib/valkey/*
    kill -9 $(ps aux | grep '[v]alkey-server' | awk '{print $2}') &> /dev/null
    echo "$(date) OOM valkey-server killed" >> ${_pthOml}
  elif [ -e "/etc/init.d/redis-server" ]; then
    rm -f /var/lib/redis/*
    kill -9 $(ps aux | grep '[r]edis-server' | awk '{print $2}') &> /dev/null
    echo "$(date) OOM redis-server killed" >> ${_pthOml}
  fi
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date) OOM Percona MySQL Server restarted" >> ${_pthOml}
  echo "$(date) OOM incident response completed" >> ${_pthOml}
  _incident_email_report "OOM $1 system"
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
      if [ `ps aux | grep -v "grep" | grep --count "wkhtmltopdf"` -gt 2 ]; then
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

_if_fix_locked_sshd() {
  _SSH_LOG="/var/log/auth.log"
  if [ `tail --lines=10 ${_SSH_LOG} \
    | grep --count "error: Bind to port 22"` -gt 0 ]; then
    kill -9 sshd &> /dev/null
    kill -9 $(ps aux | grep '[s]tartups' | awk '{print $2}') &> /dev/null
    service ssh start
    _thisErrLog="$(date) SSHD BIND error detected, service restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "SSHD BIND error detected, service restarted"
    echo >> ${_pthOml}
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
    [ "$count" -gt 0 ] && echo "DHCP failure count: $count" >> "${_pthOml}"

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
        wait
        synproxy_reassert -p "443 80" --quic-port 443 -q &> /dev/null
      else
        csf -r &> /dev/null
      fi

      # Log the error and send an email report
      _thisErrLog="$(date) DHCP error detected, firewall updated"
      echo "${_thisErrLog}" >> "${_pthOml}"
      _incident_email_report "DHCP error detected, firewall updated"
      echo >> "${_pthOml}"
    fi
  fi
}

_cron_duplicate_instances_detection() {
  if [ `ps aux | grep -v "grep" | grep --count "/usr/sbin/cron"` -gt 1 ]; then
    _thisErrLog="$(date) Too many Cron instances running killed"
    echo ${_thisErrLog} >> /var/log/boa/cron-count.kill.log
    killall -9 cron &> /dev/null
    service cron start &> /dev/null
    _thisErrLog="$(date) Too many Cron instances, service restarted"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many Cron instances, service restarted"
    echo >> ${_pthOml}
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
  if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt 5 ]; then
    _thisErrLog="$(date) Too many gpg-agent processes killed"
    echo ${_thisErrLog} >> /var/log/boa/gpg-agent-count.kill.log
    kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
    _thisErrLog="$(date) Too many gpg-agent processes killed"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many gpg-agent processes killed"
    echo >> ${_pthOml}
  fi
}

_dirmngr_too_many_instances_detection() {
  if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt 5 ]; then
    _thisErrLog="$(date) Too many dirmngr processes killed"
    echo ${_thisErrLog} >> /var/log/boa/dirmngr-count.kill.log
    kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
    _thisErrLog="$(date) Too many dirmngr processes killed"
    echo ${_thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many dirmngr processes killed"
    echo >> ${_pthOml}
  fi
}

if [ -e "/run/boa_sql_backup.pid" ] \
  || [ -e "/run/boa_sql_cluster_backup.pid" ] \
  || [ -e "/run/boa_run.pid" ] \
  || [ -e "/run/boa_wait.pid" ] \
  || [ -e "/run/mysql_restart_running.pid" ]; then
  _ALLOW_CTRL=NO
else
  _ALLOW_CTRL=YES
fi

_if_fix_locked_sshd
_if_fix_dhcp
_cron_duplicate_instances_detection
_syslog_giant_log_detection

[ "${_ALLOW_CTRL}" = "YES" ] && _optimize_ram
[ "${_ALLOW_CTRL}" = "YES" ] && _system_oom_detection
[ "${_ALLOW_CTRL}" = "YES" ] && _gpg_too_many_instances_detection
[ "${_ALLOW_CTRL}" = "YES" ] && _dirmngr_too_many_instances_detection

echo DONE!
exit 0
