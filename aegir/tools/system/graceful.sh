#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

action()
{
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
  rm -f /tmp/*error*
  rm -f /tmp/sess*
  rm -f -r /tmp/*
  rm -f /opt/tmp/*error*
  rm -f /opt/tomcat6/logs/*
  rm -f -r /var/lib/nginx/speed/*
  echo rotate > /var/log/nginx/speed_purge.log
  if [ -e "/var/log/newrelic" ] ; then
    echo rotate > /var/log/newrelic/nrsysmond.log
    echo rotate > /var/log/newrelic/php_agent.log
    echo rotate > /var/log/newrelic/newrelic-daemon.log
  fi
  /etc/init.d/nginx reload
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
###EOF2012###
