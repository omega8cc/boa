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
    sync && echo 3 | tee /proc/sys/vm/drop_caches
  fi
}

_find_fast_mirror_early() {
  _ffMirr=/opt/local/bin/ffmirror
  if [ -x "${_ffMirr}" ]; then
    _ffList="/var/backups/boa-mirrors-2025-01.txt"
    [ -d "/var/backups" ] || mkdir -p /var/backups
    if [ ! -e "${_ffList}" ]; then
      echo "eu.files.aegir.cc"  > ${_ffList}
      echo "us.files.aegir.cc" >> ${_ffList}
      echo "ao.files.aegir.cc" >> ${_ffList}
    fi
    if [ -e "${_ffList}" ]; then
      _BROKEN_FFMIRR_TEST=$(grep "stuff" ${_ffMirr} 2>&1)
      if [[ "${_BROKEN_FFMIRR_TEST}" =~ "stuff" ]]; then
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _CHECK_MIRROR=$(bash ${_ffMirr} < ${_ffList} 2>&1)
        _USE_MIR="${_CHECK_MIRROR}"
        [[ "${_USE_MIR}" =~ "printf" ]] && _USE_MIR="files.aegir.cc"
      else
        _USE_MIR="files.aegir.cc"
      fi
    else
      _USE_MIR="files.aegir.cc"
    fi
  else
    _USE_MIR="files.aegir.cc"
  fi
  export _urlDev="https://${_USE_MIR}/dev"
}

# Function to download GeoLite2 databases
_fetch_geoip() {

  # Prepare GeoIP directories
  echo "Setting up GeoIP directories..."
  mkdir -p /usr/share/GeoIP
  chmod 755 /usr/share/GeoIP

  # Download and install GeoIP databases
  echo "Downloading GeoIP databases..."
  mkdir -p /opt/tmp
  cd /opt/tmp
  rm -f /opt/tmp/Geo*

  # For GeoIP2 ASN database:
  wget -q -U iCab ${_urlDev}/src/GeoLite2-ASN.mmdb.gz
  gunzip GeoLite2-ASN.mmdb.gz &> /dev/null
  cp -af GeoLite2-ASN.mmdb /usr/share/GeoIP/

  # For GeoIP2 City database:
  wget -q -U iCab ${_urlDev}/src/GeoLite2-City.mmdb.gz
  gunzip GeoLite2-City.mmdb.gz &> /dev/null
  cp -af GeoLite2-City.mmdb /usr/share/GeoIP/

  # For GeoIP2 Country database:
  wget -q -U iCab ${_urlDev}/src/GeoLite2-Country.mmdb.gz
  gunzip GeoLite2-Country.mmdb.gz &> /dev/null
  cp -af GeoLite2-Country.mmdb /usr/share/GeoIP/

  chmod 644 /usr/share/GeoIP/*
  rm -f /opt/tmp/Geo*
  cd
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
  if [ ! -e "/usr/share/GeoIP/GeoLite2-City.mmdb" ]; then
    _find_fast_mirror_early
    _fetch_geoip
  fi

  # Cleanup for /opt/tmp/sess*
  rm -f /opt/tmp/sess*

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
