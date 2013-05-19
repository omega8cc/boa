#!/bin/bash
###
### /var/xdrago/guest-water.sh
### sed -i "s/.*water.*//g" /etc/crontab
### echo "01 *    * * *   root    bash /var/xdrago/guest-water.sh >/dev/null 2>&1" >> /etc/crontab
### sed -i "/^$/d" /etc/crontab
###
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SHELL=/bin/bash
guard_stats()
{
  if [ -e "$_HA" ] ; then
    for _IP in `cat $_HA | cut -d '#' -f1 | sort | uniq`
    do
      _NR_TEST="0"
      _NR_TEST=$(tr -s ' ' '\n' < $_HA | grep -c $_IP 2>&1)
      echo $_IP $_NR_TEST
      if [ ! -z $_NR_TEST ] && [ $_NR_TEST -ge "8" ] ; then
        _FW_TEST=$(iptables --list -n | grep $_IP 2>&1)
        if [[ "$_FW_TEST" =~ "$_IP" ]] ; then
          echo "$_IP already denied or allowed on port 22"
        else
          if [ $_NR_TEST -ge "24" ] ; then
            echo "Deny $_IP permanently $_NR_TEST"
            csf -d $_IP do not delete Brute force SSH Server $_NR_TEST attacks
          else
            echo "Deny $_IP until limits rotation $_NR_TEST"
            csf -d $_IP Brute force SSH Server $_NR_TEST attacks
          fi
        fi
        sleep 1
      fi
    done
  fi
  if [ -e "$_WA" ] ; then
    for _IP in `cat $_WA | cut -d '#' -f1 | sort | uniq`
    do
      _NR_TEST="0"
      _NR_TEST=$(tr -s ' ' '\n' < $_WA | grep -c $_IP 2>&1)
      echo $_IP $_NR_TEST
      if [ ! -z $_NR_TEST ] && [ $_NR_TEST -ge "8" ] ; then
        _FW_TEST=$(iptables --list -n | grep $_IP 2>&1)
        if [[ "$_FW_TEST" =~ "$_IP" ]] ; then
          echo "$_IP already denied or allowed on port 80"
        else
          if [ $_NR_TEST -ge "24" ] ; then
            echo "Deny $_IP permanently $_NR_TEST"
            csf -d $_IP do not delete Brute force Web Server $_NR_TEST attacks
          else
            echo "Deny $_IP until limits rotation $_NR_TEST"
            csf -d $_IP Brute force Web Server $_NR_TEST attacks
          fi
        fi
        sleep 1
      fi
    done
  fi
  if [ -e "$_FA" ] ; then
    for _IP in `cat $_FA | cut -d '#' -f1 | sort | uniq`
    do
      _NR_TEST="0"
      _NR_TEST=$(tr -s ' ' '\n' < $_FA | grep -c $_IP 2>&1)
      echo $_IP $_NR_TEST
      if [ ! -z $_NR_TEST ] && [ $_NR_TEST -ge "8" ] ; then
        _FW_TEST=$(iptables --list -n | grep $_IP 2>&1)
        if [[ "$_FW_TEST" =~ "$_IP" ]] ; then
          echo "$_IP already denied or allowed on port 21"
        else
          if [ $_NR_TEST -ge "24" ] ; then
            echo "Deny $_IP permanently $_NR_TEST"
            csf -d $_IP do not delete Brute force FTP Server $_NR_TEST attacks
          else
            echo "Deny $_IP until limits rotation $_NR_TEST"
            csf -d $_IP Brute force FTP Server $_NR_TEST attacks
          fi
        fi
        sleep 1
      fi
    done
  fi
  if [ -e "$_SA" ] ; then
    for _IP in `cat $_SA | cut -d '#' -f1 | sort | uniq`
    do
      _NR_TEST="0"
      _NR_TEST=$(tr -s ' ' '\n' < $_SA | grep -c $_IP 2>&1)
      echo $_IP $_NR_TEST
      if [ ! -z $_NR_TEST ] && [ $_NR_TEST -ge "8" ] ; then
        _FW_TEST=$(iptables --list -n | grep $_IP 2>&1)
        if [[ "$_FW_TEST" =~ "$_IP" ]] ; then
          echo "$_IP already denied or allowed on port 25"
        else
          if [ $_NR_TEST -ge "24" ] ; then
            echo "Deny $_IP permanently $_NR_TEST"
            csf -d $_IP do not delete Brute force SMTP Server $_NR_TEST attacks
          else
            echo "Deny $_IP until limits rotation $_NR_TEST"
            csf -d $_IP Brute force SMTP Server $_NR_TEST attacks
          fi
        fi
        sleep 1
      fi
    done
  fi
}
if [ -e "/etc/csf/csf.deny" ] && [ -e "/usr/sbin/csf" ] ; then
  _HA=/var/xdrago/monitor/hackcheck.archive.log
  _WA=/var/xdrago/monitor/scan_nginx.archive.log
  _FA=/var/xdrago/monitor/hackftp.archive.log
  _SA=/var/xdrago/monitor/hackmail.archive.log
  guard_stats
  rm -f /var/xdrago/monitor/ssh.log
  rm -f /var/xdrago/monitor/web.log
  rm -f /var/xdrago/monitor/ftp.log
  rm -f /var/xdrago/monitor/smtp.log
  ntpdate pool.ntp.org
  csf -q
fi
###EOF2013###
