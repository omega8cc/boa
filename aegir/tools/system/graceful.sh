#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

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
  _DF_TEST=$(df -kTh / -l \
    | grep '/' \
    | sed 's/\%//g' \
    | awk '{print $6}' 2> /dev/null)
  _DF_TEST=${_DF_TEST//[^0-9]/}
  if [ ! -z "${_DF_TEST}" ] && [ "${_DF_TEST}" -gt "90" ]; then
    echo "ERROR: Your disk space is almost full !!! ${_DF_TEST}/100"
    echo "ERROR: We can not proceed until it is below 90/100"
    exit 1
  fi
}
check_root

if [ -e "/root/.proxy.cnf" ]; then
  exit 0
fi

action() {
  mkdir -p /usr/share/GeoIP
  chmod 755 /usr/share/GeoIP
  cd /tmp
  wget -q -U iCab \
    http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz
  gunzip GeoIP.dat.gz &> /dev/null
  cp -af GeoIP.dat /usr/share/GeoIP/
  wget -q -U iCab \
    http://geolite.maxmind.com/download/geoip/database/GeoIPv6.dat.gz
  gunzip GeoIPv6.dat.gz &> /dev/null
  cp -af GeoIPv6.dat /usr/share/GeoIP/
  chmod 644 /usr/share/GeoIP/*
  rm -rf /tmp/GeoIP*
  rm -rf /opt/tmp
  mkdir -p /opt/tmp
  chmod 777 /opt/tmp
  rm -f /opt/tmp/sess*
  if [[ "${_CHECK_HOST}" =~ ".host8." ]] \
    || [[ "${_CHECK_HOST}" =~ ".boa.io" ]] \
    || [ "${_VMFAMILY}" = "VS" ] \
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
    echo "INFO: Redis and Jetty servers will be restarted in 60 seconds"
    touch /var/run/boa_wait.pid
    sleep 60
    kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}') &> /dev/null
    rm -rf /tmp/{drush*,pear,jetty*}
    rm -f /var/log/jetty{7,8,9}/*
    if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ]; then
      service jetty9 start
    fi
    if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ]; then
      service jetty8 start
    fi
    if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ]; then
      service jetty7 start
    fi
    service redis-server stop
    killall -9 redis-server
    rm -f /var/run/redis.pid
    rm -f /var/lib/redis/*
    rm -f /var/log/redis/redis-server.log
    service redis-server start
    rm -f /var/run/boa_wait.pid
    echo "INFO: Redis and Jetty servers restarted OK"
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
  touch /var/xdrago/log/graceful.done
}

###--------------------###
_NOW=$(date +%y%m%d-%H%M 2>&1)
_NOW=${_NOW//[^0-9-]/}
_CHECK_HOST=$(uname -n 2>&1)
_VM_TEST=$(uname -a 2>&1)
if [[ "${_VM_TEST}" =~ "3.8.6-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.8.5.2-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.8.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.7.5-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.7.4-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.6.15-beng" ]] \
  || [[ "${_VM_TEST}" =~ "3.2.16-beng" ]]; then
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
  rm -f /var/run/boa_wait.pid
  exit 0
fi
###EOF2017###
