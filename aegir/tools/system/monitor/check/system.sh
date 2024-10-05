#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

_pthOml="/var/xdrago/log/system.incident.log"

_check_root() {
  if [ `whoami` = "root" ]; then
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    chmod a+w /dev/null
  else
    echo "ERROR: This script should be run as a root user"
    exit 1
  fi
}
_check_root

export _INCIDENT_EMAIL_REPORT=${_INCIDENT_EMAIL_REPORT//[^A-Z]/}
: "${_INCIDENT_EMAIL_REPORT:=YES}"

if (( $(pgrep -fc 'system.sh') > 2 )); then
  echo "Too many system.sh running $(date)" >> /var/xdrago/log/too.many.log
  exit 0
fi

_incident_email_report() {
  if [ -n "${_MY_EMAIL}" ] && [ "${_INCIDENT_EMAIL_REPORT}" = "YES" ]; then
    hName=$(cat /etc/hostname 2>&1)
    echo "Sending Incident Report Email on $(date 2>&1)" >> ${_pthOml}
    s-nail -s "Incident Report: ${1} on ${hName} at $(date 2>&1)" ${_MY_EMAIL} < ${_pthOml}
  fi
}

_wkhtmltopdf_php_cli_oom_kill() {
  touch /run/boa_run.pid
  echo "$(date 2>&1) OOM $1 wkhtmltopdf/php-cli detected" >> ${_pthOml}
  sleep 3
  kill -9 $(ps aux | grep '[w]khtmltopdf' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM wkhtmltopdf killed" >> ${_pthOml}
  killall -9 sleep &> /dev/null
  killall -9 php
  echo "$(date 2>&1) OOM php-cli killed" >> ${_pthOml}
  echo "$(date 2>&1) OOM wkhtmltopdf/php-cli incident response completed" >> ${_pthOml}
  _incident_email_report "OOM $1 wkhtmltopdf/php-cli"
  echo >> ${_pthOml}
  [ -e "/run/boa_run.pid" ] && rm -f /run/boa_run.pid
  exit 0
}

_oom_critical_restart() {
  touch /run/boa_run.pid
  echo "$(date 2>&1) OOM $1 detected" >> ${_pthOml}
  kill -9 $(ps aux | grep '[w]khtmltopdf' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM wkhtmltopdf killed" >> ${_pthOml}
  killall -9 sleep &> /dev/null
  killall -9 php
  echo "$(date 2>&1) OOM php-cli killed" >> ${_pthOml}
  mv -f /var/log/nginx/error.log /var/log/nginx/`date +%y%m%d-%H%M`-error.log
  kill -9 $(ps aux | grep '[n]ginx' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM nginx killed" >> ${_pthOml}
  kill -9 $(ps aux | grep '[p]hp-fpm' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM php-fpm killed" >> ${_pthOml}
  kill -9 $(ps aux | grep '[j]ava' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM solr/jetty killed" >> ${_pthOml}
  kill -9 $(ps aux | grep '[n]ewrelic-daemon' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM newrelic-daemon killed" >> ${_pthOml}
  kill -9 $(ps aux | grep '[r]edis-server' | awk '{print $2}') &> /dev/null
  echo "$(date 2>&1) OOM redis-server killed" >> ${_pthOml}
  bash /var/xdrago/move_sql.sh
  wait
  echo "$(date 2>&1) OOM Percona MySQL Server restarted" >> ${_pthOml}
  echo "$(date 2>&1) OOM incident response completed" >> ${_pthOml}
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
    if [ "${_RAM_PCT_FREE}" -le "10" ]; then
      _oom_critical_restart "RAM ${_RAM_PCT_FREE}/${_RAM_TOTAL}"
    elif [ "${_RAM_PCT_FREE}" -le "20" ]; then
      if [ `ps aux | grep -v "grep" | grep --count "wkhtmltopdf"` -gt "2" ]; then
        _wkhtmltopdf_php_cli_oom_kill "RAM ${_RAM_PCT_FREE}/${_RAM_TOTAL}"
      fi
    fi
  fi
}

_if_fix_locked_sshd() {
  _SSH_LOG="/var/log/auth.log"
  if [ `tail --lines=100 ${_SSH_LOG} \
    | grep --count "error: Bind to port 22"` -gt "0" ]; then
    kill -9 $(ps aux | grep '[s]tartups' | awk '{print $2}') &> /dev/null
    service ssh start
    wait
    thisErrLog="$(date 2>&1) SSHD BIND error detected, service restarted"
    echo ${thisErrLog} >> ${_pthOml}
    _incident_email_report "SSHD BIND error detected, service restarted"
    echo >> ${_pthOml}
  fi
}

_if_fix_dhcp() {
  if [ -e "/var/log/daemon.log" ]; then
    _DHCP_LOG="/var/log/daemon.log"
  else
    _DHCP_LOG="/var/log/syslog"
  fi
  if [ -e "${_DHCP_LOG}" ]; then
    if [ `tail --lines=100 ${_DHCP_LOG} \
      | grep --count "dhclient.*Failed"` -gt "0" ]; then
      sed -i "s/.*DHCP.*//g" /etc/csf/csf.allow
      wait
      sed -i "/^$/d" /etc/csf/csf.allow
      grep DHCPREQUEST "${_DHCP_LOG}" | awk '{print $12}' | sort -u | while read -r _IP; do
        if [[ ${_IP} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          IFS='.' read -r oct1 oct2 oct3 oct4 <<< "${_IP}"
          if (( oct1 <= 255 && oct2 <= 255 && oct3 <= 255 && oct4 <= 255 )); then
            echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow
          fi
        fi
      done
      csf -q &> /dev/null
      thisErrLog="$(date 2>&1) DHCP error detected, firewall updated"
      echo ${thisErrLog} >> ${_pthOml}
      _incident_email_report "DHCP error detected, firewall updated"
      echo >> ${_pthOml}
    fi
  fi
}

_cron_duplicate_instances_detection() {
  if [ `ps aux | grep -v "grep" | grep --count "/usr/sbin/cron"` -gt "1" ]; then
    thisErrLog="$(date 2>&1) Too many Cron instances running killed"
    echo ${thisErrLog} >> /var/xdrago/log/cron-count.kill.log
    killall -9 cron &> /dev/null
    service cron start &> /dev/null
    thisErrLog="$(date 2>&1) Too many Cron instances, service restarted"
    echo ${thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many Cron instances, service restarted"
    echo >> ${_pthOml}
  fi
}

_syslog_giant_log_detection() {
  if [ -e "/etc/cron.daily/logrotate" ]; then
    _SYSLOG_SIZE_TEST=$(du -s -h /var/log/syslog)
    if [[ "${_SYSLOG_SIZE_TEST}" =~ "G" ]]; then
      echo ${_SYSLOG_SIZE_TEST} too big
      bash /etc/cron.daily/logrotate &> /dev/null
      wait
      thisErrLog="$(date 2>&1) Syslog ${_SYSLOG_SIZE_TEST} too big, logrotate forced"
      echo ${thisErrLog} >> ${_pthOml}
      _incident_email_report "Syslog ${_SYSLOG_SIZE_TEST} too big, logrotate forced"
      echo >> ${_pthOml}
    fi
  fi
}

_gpg_too_many_instances_detection() {
  if [ `ps aux | grep -v "grep" | grep --count "gpg-agent"` -gt "5" ]; then
    thisErrLog="$(date 2>&1) Too many gpg-agent processes killed"
    echo ${thisErrLog} >> /var/xdrago/log/gpg-agent-count.kill.log
    kill -9 $(ps aux | grep '[g]pg-agent' | awk '{print $2}') &> /dev/null
    thisErrLog="$(date 2>&1) Too many gpg-agent processes killed"
    echo ${thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many gpg-agent processes killed"
    echo >> ${_pthOml}
  fi
}

_dirmngr_too_many_instances_detection() {
  if [ `ps aux | grep -v "grep" | grep --count "dirmngr"` -gt "5" ]; then
    thisErrLog="$(date 2>&1) Too many dirmngr processes killed"
    echo ${thisErrLog} >> /var/xdrago/log/dirmngr-count.kill.log
    kill -9 $(ps aux | grep '[d]irmngr' | awk '{print $2}') &> /dev/null
    thisErrLog="$(date 2>&1) Too many dirmngr processes killed"
    echo ${thisErrLog} >> ${_pthOml}
    _incident_email_report "Too many dirmngr processes killed"
    echo >> ${_pthOml}
  fi
}

_system_oom_detection
_if_fix_locked_sshd
_if_fix_dhcp
_cron_duplicate_instances_detection
_syslog_giant_log_detection
_gpg_too_many_instances_detection
_dirmngr_too_many_instances_detection

echo DONE!
exit 0
###EOF2024###
