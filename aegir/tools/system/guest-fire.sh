#!/bin/bash
###
### /var/xdrago/guest-fire.sh
### sed -i "s/.*fire.*//g" /etc/crontab
### echo "*/1 * * * *   root    bash /var/xdrago/guest-fire.sh >/dev/null 2>&1" >> /etc/crontab
### sed -i "/^$/d" /etc/crontab
###
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash
guest_guard()
{
  if [ -e "/var/xdrago/monitor/ssh.log" ] ; then
    for _IP in `cat /var/xdrago/monitor/ssh.log | cut -d '#' -f1 | sort`
    do
      _FW_TEST=$(iptables --list -n | grep $_IP 2>&1)
      if [[ "$_FW_TEST" =~ "$_IP" ]] ; then
        echo "$_IP already denied or allowed on port 22"
      else
        echo "Deny $_IP on port 22 in the next 1h"
        csf -td $_IP 3600 -p 22
      fi
      sleep 1
    done
  fi
  sleep 1
  if [ -e "/var/xdrago/monitor/web.log" ] ; then
    for _IP in `cat /var/xdrago/monitor/web.log | cut -d '#' -f1 | sort`
    do
      _FW_TEST=$(iptables --list -n | grep $_IP 2>&1)
      if [[ "$_FW_TEST" =~ "$_IP" ]] ; then
        echo "$_IP already denied or allowed on port 80"
      else
        echo "Deny $_IP on port 80 in the next 1h"
        csf -td $_IP 3600 -p 80
      fi
      sleep 1
    done
  fi
  echo Completed for $i
}
if [ -e "/etc/csf/csf.deny" ] && [ -e "/usr/sbin/csf" ] ; then
  guest_guard
  sleep 15
  guest_guard
  sleep 15
  guest_guard
fi
###EOF2013###
