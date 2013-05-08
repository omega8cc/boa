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
  rm -f /tmp/{*error*,sess*,file*,upt*,wsdl*,php*,privatemsg*,media*,mobile*,download*,domain*,drupal*,ns*,superfish*,context*,.htaccess}
  rm -f -r /tmp/{drush*,mapshape*}
  rm -f /opt/tomcat6/logs/*
  rm -f /var/log/jetty{7,8,9}/*
  `killall -9 java`;
  sleep 2
  if [ -e "/etc/default/tomcat" ] && [ -e "/etc/init.d/tomcat" ] ; then
    /etc/init.d/tomcat start
  fi
  if [ -e "/etc/default/jetty9" ] && [ -e "/etc/init.d/jetty9" ] ; then
    /etc/init.d/jetty9 start
  fi
  if [ -e "/etc/default/jetty8" ] && [ -e "/etc/init.d/jetty8" ] ; then
    /etc/init.d/jetty8 start
  fi
  if [ -e "/etc/default/jetty7" ] && [ -e "/etc/init.d/jetty7" ] ; then
    /etc/init.d/jetty7 start
  fi
  if test -f /root/.high_traffic.cnf ; then
    true
  else
    rm -f -r /var/lib/nginx/speed/*
  fi
  /etc/init.d/nginx reload
  touch /var/run/fmp_wait.pid
  if [ -e "/etc/init.d/php-fpm" ] ; then
    /etc/init.d/php-fpm reload
  fi
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
