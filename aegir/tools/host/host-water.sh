#!/bin/bash

PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin
SHELL=/bin/bash

whitelist_ip_pingdom() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing pingdom ips from csf.allow
    sed -i "s/.*pingdom.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS=$(curl -k -s https://my.pingdom.com/probes/feed \
    | grep '<pingdom:ip>' \
    | sed 's/.*::.*//g' \
    | sed 's/[^0-9\.]//g' \
    | sort \
    | uniq 2>&1)

  for _IP in ${_IPS}; do
    echo checking pingdom ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # pingdom ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

whitelist_ip_cloudflare() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing cloudflare ips from csf.allow
    sed -i "s/.*cloudflare.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS=$(curl -k -s https://www.cloudflare.com/ips-v4 \
    | sed 's/.*::.*//g' \
    | sed 's/[^0-9\.\/]//g' \
    | sort \
    | uniq 2>&1)

  for _IP in ${_IPS}; do
    echo checking cloudflare ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # cloudflare ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

whitelist_ip_incapsula() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing incapsula ips from csf.allow
    sed -i "s/.*incapsula.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS=$(curl -k -s --data "resp_format=text" https://my.incapsula.com/api/integration/v1/ips \
    | sed 's/.*::.*//g' \
    | sed 's/[^0-9\.\/]//g' \
    | sort \
    | uniq 2>&1)

  for _IP in ${_IPS}; do
    echo checking incapsula ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # incapsula ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

whitelist_ip_googlebot() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing googlebot ips from csf.allow
    sed -i "s/.*googlebot.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS="66.249.64.0/19"

  for _IP in ${_IPS}; do
    echo checking googlebot ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # googlebot ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  sed -i "s/66.249..*//g" /etc/csf/csf.deny
  wait
}

whitelist_ip_microsoft() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing microsoft ips from csf.allow
    sed -i "s/.*microsoft.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS="65.52.0.0/14 199.30.16.0/20"

  for _IP in ${_IPS}; do
    echo checking microsoft ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # microsoft ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  sed -i "s/65.5.*//g" /etc/csf/csf.deny
  wait
  sed -i "s/199.30..*//g" /etc/csf/csf.deny
  wait
}

whitelist_ip_sucuri() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing sucuri ips from csf.allow
    sed -i "s/.*sucuri.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS="192.88.134.0/23 185.93.228.0/22 66.248.200.0/22 208.109.0.0/22"

  for _IP in ${_IPS}; do
    echo checking sucuri ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # sucuri ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

whitelist_ip_authzero() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing authzero ips from csf.allow
    sed -i "s/.*authzero.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS="35.167.74.121 35.166.202.113 35.160.3.103 54.183.64.135 54.67.77.38 54.67.15.170 54.183.204.205 35.171.156.124 18.233.90.226 3.211.189.167 52.28.56.226 52.28.45.240 52.16.224.164 52.16.193.66 34.253.4.94 52.50.106.250 52.211.56.181 52.213.38.246 52.213.74.69 52.213.216.142 35.156.51.163 35.157.221.52 52.28.184.187 52.28.212.16 52.29.176.99 52.57.230.214 54.76.184.103 52.210.122.50 52.208.95.174 52.210.122.50 52.208.95.174 54.76.184.103 52.64.84.177 52.64.111.197 54.153.131.0 13.210.52.131 13.55.232.24 13.54.254.182 52.62.91.160 52.63.36.78 52.64.120.184 54.66.205.24 54.79.46.4"

  for _IP in ${_IPS}; do
    echo checking authzero ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # authzero ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

whitelist_ip_site24x7() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing site24x7 ips from csf.allow
    sed -i "s/.*site24x7.*//g" /etc/csf/csf.allow
    wait
    sed -i "/^$/d" /etc/csf/csf.allow
    wait
  fi

  _IPS=$(host -a site24x7.enduserexp.com 8.8.8.8  \
    | grep 'IN.*A' \
    | cut -d 'A' -f2 \
    | sed 's/[^0-9\.]//g' \
    | sort \
    | uniq 2>&1)

  for _IP in ${_IPS}; do
    echo checking site24x7 ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # site24x7 ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
  if [ ! -e "/root/.whitelist.site24x7.cnf" ]; then
    csf -tf
    csf -df
    touch /root/.whitelist.site24x7.cnf
  fi
}

local_ip_rg() {
  if [ -e "/root/.local.IP.list" ]; then
    echo "the file /root/.local.IP.list already exists"
    for _IP in `hostname -I`; do
      _IP_CHECK=$(cat /root/.local.IP.list \
        | cut -d '#' -f1 \
        | sort \
        | uniq \
        | tr -d "\s" \
        | grep ${_IP} 2>&1)
      if [ -z "${_IP_CHECK}" ]; then
        echo "${_IP} not yet listed in /root/.local.IP.list"
        echo "${_IP} # local IP address" >> /root/.local.IP.list
      else
        echo "${_IP} already listed in /root/.local.IP.list"
      fi
    done
    for _IP in `cat /root/.local.IP.list \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s"`; do
      echo removing ${_IP} from d/t firewall rules
      csf -ar ${_IP} &> /dev/null
      csf -dr ${_IP} &> /dev/null
      csf -tr ${_IP} &> /dev/null
      if [ ! -e "/root/.local.IP.csf.listed" ]; then
        echo removing ${_IP} from csf.ignore
        sed -i "s/^${_IP} .*//g" /etc/csf/csf.ignore
        wait
        echo removing ${_IP} from csf.allow
        sed -i "s/^${_IP} .*//g" /etc/csf/csf.allow
        wait
        echo adding ${_IP} to csf.ignore
        echo "${_IP} # local.IP.list" >> /etc/csf/csf.ignore
        wait
        echo adding ${_IP} to csf.allow
        echo "${_IP} # local.IP.list" >> /etc/csf/csf.allow
        wait
      fi
    done
    touch /root/.local.IP.csf.listed
  else
    echo "the file /root/.local.IP.list does not exist"
    rm -f /root/.tmp.IP.list*
    rm -f /root/.local.IP.list*
    for _IP in `hostname -I`;do echo ${_IP} >> /root/.tmp.IP.list;done
    for _IP in `cat /root/.tmp.IP.list \
      | sort \
      | uniq`;do echo "${_IP} # local IP address" >> /root/.local.IP.list;done
    rm -f /root/.tmp.IP.list*
  fi
  sed -i "/^$/d" /etc/csf/csf.ignore &> /dev/null
  wait
  sed -i "/^$/d" /etc/csf/csf.allow &> /dev/null
  wait
}

guard_stats() {
  for i in `dir -d /vservers/*`; do
    if [ -e "/root/.local.IP.list" ]; then
      cp -af /root/.local.IP.list ${i}/root/.local.IP.list
    fi
    if [ ! -e "${i}/${_HX}" ] && [ -e "${i}/${_HA}" ]; then
      mv -f ${i}/${_HA} ${i}/${_HX}
    fi
    if [ ! -e "${i}/${_WX}" ] && [ -e "${i}/${_WA}" ]; then
      mv -f ${i}/${_WA} ${i}/${_WX}
    fi
    if [ ! -e "${i}/${_FX}" ] && [ -e "${i}/${_FA}" ]; then
      mv -f ${i}/${_FA} ${i}/${_FX}
    fi
    if [ -e "${i}/${_HA}" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/${_HA} | cut -d '#' -f1 | sort | uniq`; do
        _NR_TEST="0"
        _NR_TEST=$(tr -s ' ' '\n' < ${i}/${_HA} | grep -c ${_IP} 2>&1)
        if [ -e "/root/.local.IP.list" ]; then
          _IP_CHECK=$(cat /root/.local.IP.list \
            | cut -d '#' -f1 \
            | sort \
            | uniq \
            | tr -d "\s" \
            | grep ${_IP} 2>&1)
          if [ ! -z "${_IP_CHECK}" ]; then
            _NR_TEST="0"
            echo "${_IP} is a local IP address, ignoring ${i}/${_HA}"
          fi
        fi
        if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge "24" ]; then
          echo ${_IP} ${_NR_TEST}
          _FW_TEST=
          _FW_TEST=$(csf -g ${_IP} 2>&1)
          if [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
            echo "${_IP} already denied or allowed on port 22"
          else
            if [ "${_NR_TEST}" -ge "64" ]; then
              echo "Deny ${_IP} permanently ${_NR_TEST}"
              csf -d ${_IP} do not delete Brute force SSH Server ${_NR_TEST} attacks
            else
              echo "Deny ${_IP} until limits rotation ${_NR_TEST}"
              csf -d ${_IP} Brute force SSH Server ${_NR_TEST} attacks
            fi
          fi
        fi
      done
    fi
    if [ -e "${i}/${_WA}" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/${_WA} | cut -d '#' -f1 | sort | uniq`; do
        _NR_TEST="0"
        _NR_TEST=$(tr -s ' ' '\n' < ${i}/${_WA} | grep -c ${_IP} 2>&1)
        if [ -e "/root/.local.IP.list" ]; then
          _IP_CHECK=$(cat /root/.local.IP.list \
            | cut -d '#' -f1 \
            | sort \
            | uniq \
            | tr -d "\s" \
            | grep ${_IP} 2>&1)
          if [ ! -z "${_IP_CHECK}" ]; then
            _NR_TEST="0"
            echo "${_IP} is a local IP address, ignoring ${i}/${_WA}"
          fi
        fi
        if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge "24" ]; then
          echo ${_IP} ${_NR_TEST}
          _FW_TEST=
          _FW_TEST=$(csf -g ${_IP} 2>&1)
          if [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
            echo "${_IP} already denied or allowed on port 80"
          else
            if [ "${_NR_TEST}" -ge "64" ]; then
              echo "Deny ${_IP} permanently ${_NR_TEST}"
              csf -d ${_IP} do not delete Brute force Web Server ${_NR_TEST} attacks
            else
              echo "Deny ${_IP} until limits rotation ${_NR_TEST}"
              csf -d ${_IP} Brute force Web Server ${_NR_TEST} attacks
            fi
          fi
        fi
      done
    fi
    if [ -e "${i}/$_FA" ] && [ -e "/usr/var/run${i}" ]; then
      for _IP in `cat ${i}/$_FA | cut -d '#' -f1 | sort | uniq`; do
        _NR_TEST="0"
        _NR_TEST=$(tr -s ' ' '\n' < ${i}/$_FA | grep -c ${_IP} 2>&1)
        if [ -e "/root/.local.IP.list" ]; then
          _IP_CHECK=$(cat /root/.local.IP.list \
            | cut -d '#' -f1 \
            | sort \
            | uniq \
            | tr -d "\s" \
            | grep ${_IP} 2>&1)
          if [ ! -z "${_IP_CHECK}" ]; then
            _NR_TEST="0"
            echo "${_IP} is a local IP address, ignoring ${i}/$_FA"
          fi
        fi
        if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge "24" ]; then
          echo ${_IP} ${_NR_TEST}
          _FW_TEST=
          _FW_TEST=$(csf -g ${_IP} 2>&1)
          if [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
            echo "${_IP} already denied or allowed on port 21"
          else
            if [ "${_NR_TEST}" -ge "64" ]; then
              echo "Deny ${_IP} permanently ${_NR_TEST}"
              csf -d ${_IP} do not delete Brute force FTP Server ${_NR_TEST} attacks
            else
              echo "Deny ${_IP} until limits rotation ${_NR_TEST}"
              csf -d ${_IP} Brute force FTP Server ${_NR_TEST} attacks
            fi
          fi
        fi
      done
    fi
  done
}

if [ -e "/vservers" ] \
  && [ -e "/etc/csf/csf.deny" ] \
  && [ -e "/usr/sbin/csf" ]; then
  if [ -e "/root/.local.IP.list" ]; then
    echo local dr/tr start `date`
    for _IP in `cat /root/.local.IP.list \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s"`; do
      csf -dr ${_IP} &> /dev/null
      csf -tr ${_IP} &> /dev/null
    done
  fi

  n=$((RANDOM%120+90))
  touch /var/run/water.pid
  echo Waiting $n seconds...
  sleep $n

  whitelist_ip_pingdom
  whitelist_ip_cloudflare
  whitelist_ip_incapsula
  whitelist_ip_googlebot
  whitelist_ip_microsoft
  whitelist_ip_sucuri
  whitelist_ip_authzero
  whitelist_ip_site24x7

  if [ -e "/root/.full.csf.cleanup.cnf" ]; then
    sed -i "s/.*do not delete.*//g" /etc/csf/csf.deny
    sed -i "/^$/d" /etc/csf/csf.deny
  fi

  rm -f /etc/csf/csf.error
  service lfd restart
  echo "Waiting 8 seconds for firewall clean start..."
  sleep 8
  csf -e
  sleep 1
  csf -q
  echo "Waiting 8 seconds for firewall clean restart..."
  sleep 8
  csf -tf
  sleep 1
  ### Linux kernel TCP SACK CVEs mitigation
  ### CVE-2019-11477 SACK Panic
  ### CVE-2019-11478 SACK Slowness
  ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
  if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
    if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
      sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
      iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
    fi
  fi

  echo local start `date`
  local_ip_rg

  _HA=var/xdrago/monitor/hackcheck.archive.log
  _HX=var/xdrago/monitor/hackcheck.archive.x3.log
  _WA=var/xdrago/monitor/scan_nginx.archive.log
  _WX=var/xdrago/monitor/scan_nginx.archive.x3.log
  _FA=var/xdrago/monitor/hackftp.archive.log
  _FX=var/xdrago/monitor/hackftp.archive.x3.log

  echo guard start `date`
  guard_stats

  rm -f /vservers/*/var/xdrago/monitor/ssh.log
  rm -f /vservers/*/var/xdrago/monitor/web.log
  rm -f /vservers/*/var/xdrago/monitor/ftp.log

  rm -f /etc/csf/csf.error
  service lfd restart
  sleep 8
  csf -e
  sleep 1
  csf -q
  sleep 8
  ### Linux kernel TCP SACK CVEs mitigation
  ### CVE-2019-11477 SACK Panic
  ### CVE-2019-11478 SACK Slowness
  ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
  if [ -e "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
    if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
      sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
      iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
    fi
  fi
  rm -f /var/run/water.pid
  echo guard fin `date`
fi
ntpdate pool.ntp.org
_IF_CDP=$(ps aux | grep '[c]dp_io' | awk '{print $2}')
if [ -z "${_IF_CDP}" ] && [ ! -e "/root/.no.swap.clear.cnf" ]; then
  swapoff -a
  swapon -a
fi
exit 0
###EOF2019###
