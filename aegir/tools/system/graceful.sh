#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

# Function to check if the script is run as root
_check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script should be run as root"
    exit 1
  else
    [ -e "/root/.barracuda.cnf" ] && source /root/.barracuda.cnf
    # Sanitize and set default value for _B_NICE
    _B_NICE="${_B_NICE//[^0-9]/}"
    : "${_B_NICE:=10}"
    chmod a+w /dev/null
  fi
}
_check_root

# Exit if certain config files exist
[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0

# Get the hostname
_CHECK_HOST="$(uname -n 2>&1)"

# Function to determine if the system is hosted
_if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] || [[ "${_CHECK_HOST}" =~ \.aegir\.cc$ ]]; then
    _HOSTED_SYS="YES"
  else
    _HOSTED_SYS="NO"
  fi
}

# Main action function
_graceful_action() {
  echo "Starting system maintenance tasks..."

  # Clean up postfix queue to get rid of bounced emails
  echo "Cleaning up postfix queue..."
  postsuper -d ALL &> /dev/null

  # Restart syslog service
  echo "Restarting syslog service..."
  if [ -e "/etc/init.d/rsyslog" ]; then
    pkill -9 rsyslogd &> /dev/null
    service rsyslog start &> /dev/null
  elif [ -e "/etc/init.d/sysklogd" ]; then
    pkill -9 sysklogd &> /dev/null
    service sysklogd start &> /dev/null
  elif [ -e "/etc/init.d/inetutils-syslogd" ]; then
    pkill -9 syslogd &> /dev/null
    service inetutils-syslogd start &> /dev/null
  fi

  # Clean up old log files
  echo "Cleaning up old log files..."
  rm -f /var/backups/.auth.IP.list*
  find /var/xdrago/log/*.pid -mtime +3  -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/*.log -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/*.txt -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/last* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/wait* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/lshe* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/ngin* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/grac* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/purg* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/clea* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/proc* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null
  find /var/xdrago/log/redi* -mtime +30 -type f -exec rm -rf {} \; &> /dev/null

  # Swap management
  if [ -d "/dev/disk" ]; then
    _IF_CDP="$(pgrep -f cdp_io)"
    if [ -z "${_IF_CDP}" ] && [ ! -e "/root/.no.swap.clear.cnf" ]; then
      echo "Resetting swap..."
      swapoff -a
      swapon -a
    fi
  fi

  # Setup GeoIP directories
  echo "Setting up GeoIP directories..."
  mkdir -p /usr/share/GeoIP
  chmod 755 /usr/share/GeoIP

  # Download and install GeoIP databases (commented out)
  echo "Downloading GeoIP databases..."
  mkdir -p /opt/tmp
  cd /opt/tmp

  # Uncomment the following lines to download GeoIP databases
  # wget -q -U iCab -N http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz
  # gunzip -f GeoLite2-City.mmdb.gz
  # cp -af GeoLite2-City.mmdb /usr/share/GeoIP/

  # wget -q -U iCab -N http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.mmdb.gz
  # gunzip -f GeoLite2-Country.mmdb.gz
  # cp -af GeoLite2-Country.mmdb /usr/share/GeoIP/

  chmod 644 /usr/share/GeoIP/*
  cd /
  rm -rf /opt/tmp
  mkdir -p /opt/tmp
  chmod 777 /opt/tmp
  rm -f /opt/tmp/sess*

  # Clean up /tmp directory if hosted system
  _if_hosted_sys
  if [ "${_HOSTED_SYS}" = "YES" ]; then
    echo "Cleaning up /tmp directory on hosted system..."
    rm -f /tmp/*
  fi

  # Remove unnecessary files
  echo "Removing unnecessary files..."
  rm -f /root/ksplice-archive.asc
  rm -f /root/install-uptrack
  find /tmp/ -type f \( -name ".ICE-unix" -o -name ".X11-unix" -o -name ".webmin" \) -mtime +0 -exec rm -f {} \;

  # Rotate New Relic logs
  if [ -d "/var/log/newrelic" ]; then
    echo "Rotating New Relic logs..."
    echo rotate > /var/log/newrelic/nrsysmond.log
    echo rotate > /var/log/newrelic/php_agent.log
    echo rotate > /var/log/newrelic/newrelic-daemon.log
  fi

  # Adjust process priorities
  echo "Adjusting process priorities..."
  ionice -c2 -n2 -p $$
  renice "${_B_NICE}" -p $$ &> /dev/null

  # Reload nginx service
  echo "Reloading nginx service..."
  service nginx reload

  # Restart Solr and Jetty servers if not under high traffic
  if [ ! -e "/root/.giant_traffic.cnf" ] && [ ! -e "/root/.high_traffic.cnf" ]; then
    echo "INFO: Solr and Jetty servers will be restarted in 60 seconds"
    touch /run/boa_wait.pid
    sleep 60
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      echo "Restarting Solr 7..."
      service solr7 restart
    fi
    echo "Stopping any running Jetty processes..."
    pkill -9 -f jetty &> /dev/null
    rm -rf /tmp/{drush*,pear,jetty*}
    rm -f /var/log/jetty{7,8,9}/*
    echo "Starting Jetty services..."
    [ -e "/etc/init.d/jetty9" ] && service jetty9 start
    [ -e "/etc/init.d/jetty8" ] && service jetty8 start
    [ -e "/etc/init.d/jetty7" ] && service jetty7 start
    [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
    echo "INFO: Solr and Jetty servers restarted successfully"
  fi

  # Speed cleanup
  _IF_BCP="$(pgrep -f duplicity)"
  if [ -z "${_IF_BCP}" ] && [ ! -e "/run/speed_cleanup.pid" ] && [ ! -e "/root/.giant_traffic.cnf" ]; then
    echo "Performing speed cleanup..."
    touch /run/speed_cleanup.pid
    echo " " >> /var/log/nginx/speed_cleanup.log
    sed -i "s/levels=2:2:2/levels=2:2/g" /var/aegir/config/server_master/nginx.conf
    service nginx reload &> /dev/null
    echo "speed_purge start $(date)" >> /var/log/nginx/speed_cleanup.log
    nice -n19 ionice -c2 -n7 find /var/lib/nginx/speed/ -mtime +1 -exec rm -rf {} \; &> /dev/null
    echo "speed_purge complete $(date)" >> /var/log/nginx/speed_cleanup.log
    service nginx reload &> /dev/null
    rm -f /run/speed_cleanup.pid
  fi

  touch /var/xdrago/log/graceful.done.pid
  echo "System maintenance tasks completed."
}

# Main script execution

# Check for ongoing operations or skip configurations
if [ -e "/run/boa_run.pid" ] || [ -e "/root/.skip_cleanup.cnf" ]; then
  echo "Cleanup skipped due to ongoing operations or configuration settings."
  exit 0
else
  echo "Waiting for 60 seconds before starting maintenance tasks..."
  touch /run/boa_wait.pid
  sleep 60
  _graceful_action
  [ -e "/run/boa_wait.pid" ] && rm -f /run/boa_wait.pid
  exit 0
fi
