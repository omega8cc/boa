#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

action()
{
  find /data/disk/*/distro/*/*/sites/*/files/tmp/* -mtime +1 -type f -exec rm -rf {} \;
  find /data/disk/*/distro/*/*/sites/*/private/temp/* -mtime +1 -type f -exec rm -rf {} \;
  find /data/disk/*/static/*/sites/*/files/tmp/* -mtime +1 -type f -exec rm -rf {} \;
  find /data/disk/*/static/*/sites/*/private/temp/* -mtime +1 -type f -exec rm -rf {} \;
  find /data/disk/*/static/*/*/sites/*/files/tmp/* -mtime +1 -type f -exec rm -rf {} \;
  find /data/disk/*/static/*/*/sites/*/private/temp/* -mtime +1 -type f -exec rm -rf {} \;
  find /data/disk/*/static/*/*/*/sites/*/files/tmp/* -mtime +1 -type f -exec rm -rf {} \;
  find /data/disk/*/static/*/*/*/sites/*/private/temp/* -mtime +1 -type f -exec rm -rf {} \;
  mkdir -p /usr/share/GeoIP
  chmod 755 /usr/share/GeoIP
  cd /tmp
  wget -q -U iCab http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz
  gunzip GeoIP.dat.gz &> /dev/null
  cp -af GeoIP.dat /usr/share/GeoIP/
  wget -q -U iCab http://geolite.maxmind.com/download/geoip/database/GeoIPv6.dat.gz
  gunzip GeoIPv6.dat.gz &> /dev/null
  cp -af GeoIPv6.dat /usr/share/GeoIP/
  chmod 644 /usr/share/GeoIP/*
  rm -f -r /tmp/GeoIP*
  rm -f -r /opt/tmp
  mkdir -p /opt/tmp
  chmod 777 /opt/tmp
  rm -f /opt/tmp/sess*
  rm -f /tmp/{*error*,sess*,file*,upt*,wsdl*,php*,privatemsg*,media*,mobile*,download*,domain*,ns*,superfish*,context*,.htaccess}
  rm -f -r /tmp/{drush*,mapshape*}
  rm -f /opt/tomcat6/logs/*
  if test -f /root/.high_traffic.cnf ; then
    true
  else
    rm -f -r /var/lib/nginx/speed/*
  fi
  /etc/init.d/nginx reload
  touch /var/run/fmp_wait.pid
  /etc/init.d/php-fpm reload
  /etc/init.d/php53-fpm reload
  sleep 8
  rm -f /var/run/fmp_wait.pid
  echo rotate > /var/log/nginx/speed_purge.log
  if [ -e "/var/log/newrelic" ] ; then
    echo rotate > /var/log/newrelic/nrsysmond.log
    echo rotate > /var/log/newrelic/php_agent.log
    echo rotate > /var/log/newrelic/newrelic-daemon.log
  fi
  touch /var/xdrago/log/graceful.done
}

if test -f /var/run/boa_run.pid ; then
  exit
else
  touch /var/run/boa_wait.pid
  sleep 60
  action
  rm -f /var/run/boa_wait.pid
fi
###EOF2013###
