#!/bin/bash

HOME=/root
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

export PATH=${PATH}
export SHELL=${SHELL}
export HOME=${HOME}

check_root() {
  if [ `whoami` = "root" ]; then
    if [ -e "/root/.barracuda.cnf" ]; then
      source /root/.barracuda.cnf
      _B_NICE=${_B_NICE//[^0-9]/}
    fi
    if [ -z "${_B_NICE}" ]; then
      _B_NICE=10
    fi
    chmod a+w /dev/null
    if [ ! -e "/dev/fd" ]; then
      if [ -e "/proc/self/fd" ]; then
        rm -rf /dev/fd
        ln -s /proc/self/fd /dev/fd
      fi
    fi
  else
    echo "ERROR: This script should be ran as a root user"
    exit 1
  fi
}
check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

if [ -e "/root/.pause_heavy_tasks_maint.cnf" ]; then
  exit 0
fi

action() {

  #
  # Clean up postfix queue to get rid of bounced emails.
  # See also: https://omega8.cc/never-send-mailings-from-aegir-server-322
  sudo postsuper -d ALL &> /dev/null

  if [ -e "/etc/init.d/rsyslog" ]; then
    killall -9 rsyslogd &> /dev/null
    service rsyslog start &> /dev/null
  elif [ -e "/etc/init.d/sysklogd" ]; then
    killall -9 sysklogd &> /dev/null
    service sysklogd start &> /dev/null
  elif [ -e "/etc/init.d/inetutils-syslogd" ]; then
    killall -9 syslogd &> /dev/null
    service inetutils-syslogd start &> /dev/null
  fi
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

  if [ -d "/dev/disk" ]; then
    _IF_CDP=$(ps aux | grep '[c]dp_io' | awk '{print $2}')
    if [ -z "${_IF_CDP}" ] && [ ! -e "/root/.no.swap.clear.cnf" ]; then
      swapoff -a
      swapon -a
    fi
  fi

  mkdir -p /usr/share/GeoIP
  chmod 755 /usr/share/GeoIP
  mkdir -p /opt/tmp
  cd /opt/tmp

# For GeoIP2 City database:
#   wget -q -U iCab \
#     wget -N http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz
#   gunzip GeoLite2-City.mmdb.gz &> /dev/null
#   cp -af GeoLite2-City.mmdb /usr/share/GeoIP/

# For GeoIP2 Country database:
#   wget -q -U iCab \
#     wget -N http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.mmdb.gz
#   gunzip GeoLite2-Country.mmdb.gz &> /dev/null
#   cp -af GeoLite2-Country.mmdb /usr/share/GeoIP/

  chmod 644 /usr/share/GeoIP/*
  rm -rf /opt/tmp
  mkdir -p /opt/tmp
  chmod 777 /opt/tmp
  rm -f /opt/tmp/sess*
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".o8.io"($) ]] \
    || [[ "${_CHECK_HOST}" =~ ".aegir.cc"($) ]] \
    || [ -e "/root/.host8.cnf" ]; then
    rm -f /tmp/*
  fi
  rm -f /root/ksplice-archive.asc
  rm -f /root/install-uptrack
  find /tmp/{.ICE-unix,.X11-unix,.webmin} -mtime +0 -type f -exec rm -rf {} \;
  if [ -e "/var/log/newrelic" ]; then
    echo rotate > /var/log/newrelic/nrsysmond.log
    echo rotate > /var/log/newrelic/php_agent.log
    echo rotate > /var/log/newrelic/newrelic-daemon.log
  fi
  ionice -c2 -n2 -p $$
  renice ${_B_NICE} -p $$ &> /dev/null
  service nginx reload
  if [ ! -e "/root/.giant_traffic.cnf" ] \
    && [ ! -e "/root/.high_traffic.cnf" ]; then
    echo "INFO: Solr and Jetty servers will be restarted in 60 seconds"
    touch /var/run/boa_wait.pid
    sleep 60
    if [ -x "/etc/init.d/solr7" ] && [ -e "/etc/default/solr7.in.sh" ]; then
      kill -9 $(ps aux | grep '[s]olr' | awk '{print $2}') &> /dev/null
      #service solr7 start
    fi
    kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}') &> /dev/null
    rm -rf /tmp/{drush*,pear,jetty*}
    rm -f /var/log/jetty{7,8,9}/*
#     if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
#       service jetty9 start
#     fi
#     if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
#       service jetty8 start
#     fi
#     if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
#       service jetty7 start
#     fi
    [ -e "/var/run/boa_wait.pid" ] && rm -f /var/run/boa_wait.pid
    echo "INFO: Solr and Jetty servers restarted OK"
  fi
  _IF_BCP=$(ps aux | grep '[d]uplicity' | awk '{print $2}')
  if [ -z "${_IF_BCP}" ] \
    && [ ! -e "/var/run/speed_cleanup.pid" ] \
    && [ ! -e "/root/.giant_traffic.cnf" ]; then
    touch /var/run/speed_cleanup.pid
    echo " " >> /var/log/nginx/speed_cleanup.log
    sed -i "s/levels=2:2:2/levels=2:2/g" /var/aegir/config/server_master/nginx.conf
    service nginx reload &> /dev/null
    echo "speed_purge start `date`" >> /var/log/nginx/speed_cleanup.log
    nice -n19 ionice -c2 -n7 find /var/lib/nginx/speed/* -mtime +1 -exec rm -rf {} \; &> /dev/null
    echo "speed_purge complete `date`" >> /var/log/nginx/speed_cleanup.log
    service nginx reload &> /dev/null
    rm -f /var/run/speed_cleanup.pid
  fi
  touch /var/xdrago/log/graceful.done.pid
}

###--------------------###
_NOW=$(date +%y%m%d-%H%M%S 2>&1)
_NOW=${_NOW//[^0-9-]/}
_CHECK_HOST=$(uname -n 2>&1)
_VM_TEST=$(uname -a 2>&1)
if [[ "${_VM_TEST}" =~ "-beng" ]]; then
  _VMFAMILY="VS"
else
  _VMFAMILY="XEN"
fi

if [ -e "/var/run/boa_run.pid" ] || [ -e "/root/.skip_cleanup.cnf" ]; then
  exit 0
else
  touch /var/run/boa_wait.pid
  sleep 60
  action
  [ -e "/var/run/boa_wait.pid" ] && rm -f /var/run/boa_wait.pid
  exit 0
fi
###EOF2024###
