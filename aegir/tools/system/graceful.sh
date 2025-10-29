#!/bin/bash

# Environment setup
export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/libexec

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

# Exit if certain config files exist
[ -e "/root/.proxy.cnf" ] && exit 0
[ -e "/root/.pause_heavy_tasks_maint.cnf" ] && exit 0


# Function to determine if the system is hosted
_if_hosted_sys() {
  if [ -e "/root/.host8.cnf" ] || [[ "${_hName}" =~ \.aegir\.cc$ ]]; then
    _HOSTED_SYS="YES"
  else
    _HOSTED_SYS="NO"
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

# Main action function
_graceful_action() {
  echo "Starting system maintenance tasks..."

  # Clean up postfix queue to get rid of bounced emails
  echo "Cleaning up postfix queue..."
  postsuper -d ALL &> /dev/null

  # Restart syslog service
  echo "Restarting syslog service..."
  if [ -e "/etc/init.d/rsyslog" ]; then
    pkill -9 rsyslogd
    service rsyslog start
  elif [ -e "/etc/init.d/sysklogd" ]; then
    pkill -9 sysklogd
    service sysklogd start
  elif [ -e "/etc/init.d/inetutils-syslogd" ]; then
    pkill -9 syslogd
    service inetutils-syslogd start
  fi

  # Clean up old log files
  echo "Cleaning up old pid files..."
  find /var/log/boa/*.pid -mtime +3  -type f -exec rm -rf {} \; &> /dev/null

  # Swap, RAM and disk cache management
  _IF_BCP="$(pgrep -f duplicity)"
  if [ -d "/dev/disk" ]; then
    if [ ! -e "/root/.no.swap.clear.cnf" ]; then
      echo "Resetting swap..."
      swapoff -a
      if [ -z "${_IF_BCP}" ]; then
        swapon -a
      fi
    fi
    echo "Optimizing RAM usage..."
    _optimize_ram
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

  # Reload nginx service
  echo "Reloading nginx service..."
  service nginx reload

  # Restart Solr and Jetty servers if not under high traffic
  if [ ! -e "/run/boa_run.pid" ] \
    && [ ! -e "/root/.giant_traffic.cnf" ] \
    && [ ! -e "/root/.high_traffic.cnf" ]; then
    echo "INFO: Solr and Jetty servers will be restarted in 10 seconds"
    sleep 10
    if [ -x "/etc/init.d/solr9" ] && [ -e "/etc/default/solr9.in.sh" ]; then
      echo "Restarting Solr 9..."
      nice -n 0 service solr9 restart
    fi
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      echo "Restarting Solr 7..."
      nice -n 0 service solr7 restart
    fi
    echo "Stopping any running Jetty processes..."
    pkill -9 -f jetty
    rm -rf /tmp/{drush*,pear,jetty*}
    rm -f /var/log/jetty9/*
    echo "Starting Jetty services..."
    [ -e "/etc/init.d/jetty9" ] && service jetty9 start
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
if [ -e "/run/boa_run.pid" ] || [ -e "/root/.skip_cleanup.cnf" ]; then
  echo "Cleanup skipped due to ongoing operations or configuration settings."
  exit 0
else
  _graceful_action
  exit 0
fi
