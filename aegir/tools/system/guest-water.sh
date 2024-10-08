#!/bin/bash

export HOME=/root
export SHELL=/bin/bash
export PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

[ ! -d "/var/backups/csf/water" ] && mkdir -p /var/backups/csf/water

_whitelist_ip_pingdom() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing pingdom ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-pingdom-${_NOW}
    sed -i "s/.*pingdom.*//g" /etc/csf/csf.allow
    wait
  fi

  _IPS=$(curl -k -s https://my.pingdom.com/probes/feed \
    | grep '<pingdom:ip>' \
    | sed 's/.*::.*//g' \
    | sed 's/[^0-9\.]//g' \
    | sort \
    | uniq 2>&1)

  echo _IPS pingdom list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow pingdom ${_IP} now...
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

_whitelist_ip_cloudflare() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing cloudflare ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-cloudflare-${_NOW}
    sed -i "s/.*cloudflare.*//g" /etc/csf/csf.allow
    wait
  fi

  _IPS=$(curl -k -s https://www.cloudflare.com/ips-v4 \
    | sed 's/.*::.*//g' \
    | sed 's/[^0-9\.\/]//g' \
    | sort \
    | uniq 2>&1)

  echo _IPS cloudflare list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow cloudflare ${_IP} now...
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

_whitelist_ip_imperva() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing imperva ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-imperva-${_NOW}
    sed -i "s/.*imperva.*//g" /etc/csf/csf.allow
    wait
  fi

  _IPS=$(curl -k -s --data "resp_format=text" https://my.imperva.com/api/integration/v1/ips \
    | sed 's/.*::.*//g' \
    | sed 's/[^0-9\.\/]//g' \
    | sort \
    | uniq 2>&1)

  echo _IPS imperva list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow imperva ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # imperva ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done
}

_whitelist_ip_googlebot() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing googlebot ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-googlebot-${_NOW}
    sed -i "s/.*googlebot.*//g" /etc/csf/csf.allow
    wait
  fi

  _IPS="66.249.64.0/19"

  echo _IPS googlebot list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow googlebot ${_IP} now...
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
  sed -i "s/^66.249..*//g" /etc/csf/csf.deny
  wait
}

_whitelist_ip_microsoft() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing microsoft ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-microsoft-${_NOW}
    sed -i "s/.*microsoft.*//g" /etc/csf/csf.allow
    wait
  fi

  _IPS="65.52.0.0/14 199.30.16.0/20"

  echo _IPS microsoft list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow microsoft ${_IP} now...
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
  sed -i "s/^65.5.*//g" /etc/csf/csf.deny
  wait
  sed -i "s/^199.30..*//g" /etc/csf/csf.deny
  wait
}

_whitelist_ip_sucuri() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing sucuri ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-sucuri-${_NOW}
    sed -i "s/.*sucuri.*//g" /etc/csf/csf.allow
    wait
  fi

  _IPS="192.88.134.0/23 185.93.228.0/22 66.248.200.0/22 208.109.0.0/22"

  echo _IPS sucuri list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow sucuri ${_IP} now...
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

_whitelist_ip_authzero() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing authzero ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-authzero-${_NOW}
    sed -i "s/.*authzero.*//g" /etc/csf/csf.allow
    wait
  fi

  _IPS="35.167.77.121 35.166.202.113 35.160.3.103 54.183.64.135 54.67.77.38 54.67.15.170 54.183.204.205 35.171.156.124 18.233.90.226 3.211.189.167 52.28.56.226 52.28.45.240 52.16.224.164 52.16.193.66 34.253.4.94 52.50.106.250 52.211.56.181 52.213.38.246 52.213.74.69 52.213.216.142 35.156.51.163 35.157.221.52 52.28.184.187 52.28.212.16 52.29.176.99 52.57.230.214 54.76.184.103 52.210.122.50 52.208.95.174 52.210.122.50 52.208.95.174 54.76.184.103 52.64.84.177 52.64.111.197 54.153.131.0 13.210.52.131 13.55.232.24 13.54.254.182 52.62.91.160 52.63.36.78 52.64.120.184 54.66.205.24 54.79.46.4"

  echo _IPS authzero list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow authzero ${_IP} now...
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

_whitelist_ip_site24x7_extra() {

  _IPS="87.252.213.0/24 89.36.170.0/24 185.172.199.128/26 185.230.214.0/23 185.172.199.0/27"

  echo _IPS site24x7_extra list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow site24x7_extra ${_IP} now...
    _IP_CHECK=$(cat /etc/csf/csf.allow \
      | cut -d '#' -f1 \
      | sort \
      | uniq \
      | tr -d "\s" \
      | grep "${_IP}" 2>&1)
    if [ -z "${_IP_CHECK}" ]; then
      echo "${_IP} not yet listed in /etc/csf/csf.allow"
      echo "tcp|in|d=80|s=${_IP} # site24x7_extra ips" >> /etc/csf/csf.allow
    else
      echo "${_IP} already listed in /etc/csf/csf.allow"
    fi
  done

  if [ -e "/root/.ignore.site24x7.firewall.cnf" ]; then
    for _IP in ${_IPS}; do
      echo checking csf.ignore site24x7_extra ${_IP} now...
      _IP_CHECK=$(cat /etc/csf/csf.ignore \
        | cut -d '#' -f1 \
        | sort \
        | uniq \
        | tr -d "\s" \
        | grep "${_IP}" 2>&1)
      if [ -z "${_IP_CHECK}" ]; then
        echo "${_IP} not yet listed in /etc/csf/csf.ignore"
        echo "${_IP} # site24x7_extra ips" >> /etc/csf/csf.ignore
      else
        echo "${_IP} already listed in /etc/csf/csf.ignore"
      fi
    done
  fi
}

_whitelist_ip_site24x7() {
  if [ ! -e "/root/.whitelist.dont.cleanup.cnf" ]; then
    echo removing site24x7 ips from csf.allow
    _NOW=$(date +%y%m%d-%H%M%S 2>&1)
    cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-site24x7-${_NOW}
    sed -i "s/.*site24x7.*//g" /etc/csf/csf.allow
    wait
    echo removing site24x7 ips from csf.ignore
    sed -i "s/.*site24x7.*//g" /etc/csf/csf.ignore
    wait
  fi

  _IPS=$(host site24x7.enduserexp.com 1.1.1.1  \
    | grep 'has address' \
    | cut -d ' ' -f4 \
    | sed 's/[^0-9\.]//g' \
    | sort \
    | uniq 2>&1)

  if [ -z "${_IPS}" ] \
    || [[ ! "${_IPS}" =~ "104.236.16.22" ]] \
    || [[ "${_IPS}" =~ "HINFO" ]]; then
    _IPS=$(dig site24x7.enduserexp.com \
      | grep 'IN.*A' \
      | cut -d 'A' -f2 \
      | sed 's/[^0-9\.]//g' \
      | sort \
      | uniq 2>&1)
  fi

  echo _IPS site24x7 list..
  echo ${_IPS}

  for _IP in ${_IPS}; do
    echo checking csf.allow site24x7 ${_IP} now...
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

  if [ -e "/root/.ignore.site24x7.firewall.cnf" ]; then
    for _IP in ${_IPS}; do
      echo checking csf.ignore site24x7 ${_IP} now...
      _IP_CHECK=$(cat /etc/csf/csf.ignore \
        | cut -d '#' -f1 \
        | sort \
        | uniq \
        | tr -d "\s" \
        | grep "${_IP}" 2>&1)
      if [ -z "${_IP_CHECK}" ]; then
        echo "${_IP} not yet listed in /etc/csf/csf.ignore"
        echo "${_IP} # site24x7 ips" >> /etc/csf/csf.ignore
      else
        echo "${_IP} already listed in /etc/csf/csf.ignore"
      fi
    done
  fi

  if [ ! -e "/root/.whitelist.site24x7.cnf" ]; then
    csf -tf
    wait
    csf -df
    wait
    touch /root/.whitelist.site24x7.cnf
  fi
}

_local_ip_rg() {
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
      if [ ! -z "${_IP}" ]; then
        echo removing ${_IP} from d/t firewall rules
        csf -ar ${_IP} &> /dev/null
        csf -dr ${_IP} &> /dev/null
        csf -tr ${_IP} &> /dev/null
      fi
      if [ ! -e "/root/.local.IP.csf.listed" ] && [ ! -z "${_IP}" ]; then
        echo removing ${_IP} from csf.ignore
        sed -i "s/^${_IP} .*//g" /etc/csf/csf.ignore
        wait
        echo removing ${_IP} from csf.allow
        _NOW=$(date +%y%m%d-%H%M%S 2>&1)
        cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-local-${_NOW}
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
}

_guard_stats() {
  if [ ! -e "${_HX}" ] && [ -e "${_HA}" ]; then
    mv -f ${_HA} ${_HX}
  fi
  if [ ! -e "${_WX}" ] && [ -e "${_WA}" ]; then
    mv -f ${_WA} ${_WX}
  fi
  if [ ! -e "${_FX}" ] && [ -e "${_FA}" ]; then
    mv -f ${_FA} ${_FX}
  fi
  if [ -e "${_HA}" ]; then
    for _IP in `cat ${_HA} | cut -d '#' -f1 | sort | uniq`; do
      _IP_RV=
      _NR_TEST="0"
      _NR_TEST=$(tr -s ' ' '\n' < ${_HA} | grep -c ${_IP} 2>&1)
      if [ -e "/root/.local.IP.list" ]; then
        _IP_CHECK=$(cat /root/.local.IP.list \
          | cut -d '#' -f1 \
          | sort \
          | uniq \
          | tr -d "\s" \
          | grep ${_IP} 2>&1)
        if [ ! -z "${_IP_CHECK}" ]; then
          _NR_TEST="0"
          echo "${_IP} is a local IP address, ignoring ${_HA}"
        fi
      fi
      if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge "24" ]; then
        echo ${_IP} ${_NR_TEST}
        _FW_TEST=
        _FF_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        _FF_TEST=$(grep "=${_IP} " /etc/csf/csf.allow 2>&1)
        if [[ "${_FF_TEST}" =~ "${_IP}" ]] || [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 22"
          if [[ "${_FF_TEST}" =~ "${_IP}" ]]; then
            csf -dr ${_IP}
            csf -tr ${_IP}
          fi
        else
          _IP_RV=$(host -s ${_IP} 2>&1)
          if [ "${_NR_TEST}" -ge "64" ]; then
            echo "Deny ${_IP} permanently ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} do not delete Brute force SSH Server ${_NR_TEST} attacks ${_IP_RV}
          else
            echo "Deny ${_IP} until limits rotation ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} Brute force SSH Server ${_NR_TEST} attacks ${_IP_RV}
          fi
        fi
      fi
    done
  fi
  if [ -e "${_WA}" ]; then
    for _IP in `cat ${_WA} | cut -d '#' -f1 | sort | uniq`; do
      _IP_RV=
      _NR_TEST="0"
      _NR_TEST=$(tr -s ' ' '\n' < ${_WA} | grep -c ${_IP} 2>&1)
      if [ -e "/root/.local.IP.list" ]; then
        _IP_CHECK=$(cat /root/.local.IP.list \
          | cut -d '#' -f1 \
          | sort \
          | uniq \
          | tr -d "\s" \
          | grep ${_IP} 2>&1)
        if [ ! -z "${_IP_CHECK}" ]; then
          _NR_TEST="0"
          echo "${_IP} is a local IP address, ignoring ${_WA}"
        fi
      fi
      if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge "24" ]; then
        echo ${_IP} ${_NR_TEST}
        _FW_TEST=
        _FF_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        _FF_TEST=$(grep "=${_IP} " /etc/csf/csf.allow 2>&1)
        if [[ "${_FF_TEST}" =~ "${_IP}" ]] || [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 80"
          if [[ "${_FF_TEST}" =~ "${_IP}" ]]; then
            csf -dr ${_IP}
            csf -tr ${_IP}
          fi
        else
          _IP_RV=$(host -s ${_IP} 2>&1)
          if [ "${_NR_TEST}" -ge "64" ]; then
            echo "Deny ${_IP} permanently ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} do not delete Brute force Web Server ${_NR_TEST} attacks ${_IP_RV}
          else
            echo "Deny ${_IP} until limits rotation ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} Brute force Web Server ${_NR_TEST} attacks ${_IP_RV}
          fi
        fi
      fi
    done
  fi
  if [ -e "${_FA}" ]; then
    for _IP in `cat ${_FA} | cut -d '#' -f1 | sort | uniq`; do
      _IP_RV=
      _NR_TEST="0"
      _NR_TEST=$(tr -s ' ' '\n' < ${_FA} | grep -c ${_IP} 2>&1)
      if [ -e "/root/.local.IP.list" ]; then
        _IP_CHECK=$(cat /root/.local.IP.list \
          | cut -d '#' -f1 \
          | sort \
          | uniq \
          | tr -d "\s" \
          | grep ${_IP} 2>&1)
        if [ ! -z "${_IP_CHECK}" ]; then
          _NR_TEST="0"
          echo "${_IP} is a local IP address, ignoring ${_FA}"
        fi
      fi
      if [ ! -z "${_NR_TEST}" ] && [ "${_NR_TEST}" -ge "24" ]; then
        echo ${_IP} ${_NR_TEST}
        _FW_TEST=
        _FF_TEST=
        _FW_TEST=$(csf -g ${_IP} 2>&1)
        _FF_TEST=$(grep "=${_IP} " /etc/csf/csf.allow 2>&1)
        if [[ "${_FF_TEST}" =~ "${_IP}" ]] || [[ "${_FW_TEST}" =~ "DENY" ]] || [[ "${_FW_TEST}" =~ "ALLOW" ]]; then
          echo "${_IP} already denied or allowed on port 21"
          if [[ "${_FF_TEST}" =~ "${_IP}" ]]; then
            csf -dr ${_IP}
            csf -tr ${_IP}
          fi
        else
          _IP_RV=$(host -s ${_IP} 2>&1)
          if [ "${_NR_TEST}" -ge "64" ]; then
            echo "Deny ${_IP} permanently ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} do not delete Brute force FTP Server ${_NR_TEST} attacks ${_IP_RV}
          else
            echo "Deny ${_IP} until limits rotation ${_NR_TEST} ${_IP_RV}"
            csf -d ${_IP} Brute force FTP Server ${_NR_TEST} attacks ${_IP_RV}
          fi
        fi
      fi
    done
  fi
}

_whitelist_ip_dns() {
  csf -tr 1.1.1.1
  csf -tr 1.0.0.1
  csf -dr 1.1.1.1
  csf -dr 1.0.0.1
  _NOW=$(date +%y%m%d-%H%M%S 2>&1)
  cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-dns-${_NOW}
  sed -i "s/.*1.1.1.1.*//g"  /etc/csf/csf.allow
  wait
  sed -i "s/.*1.1.1.1.*//g"  /etc/csf/csf.ignore
  wait
  sed -i "s/.*1.0.0.1.*//g"  /etc/csf/csf.allow
  wait
  sed -i "s/.*1.0.0.1.*//g"  /etc/csf/csf.ignore
  wait
  echo "tcp|out|d=53|d=1.1.1.1 # Cloudflare DNS" >> /etc/csf/csf.allow
  echo "tcp|out|d=53|d=1.0.0.1 # Cloudflare DNS" >> /etc/csf/csf.allow
  sed -i "s/.*8.8.8.8.*//g"  /etc/csf/csf.allow
  wait
  sed -i "s/.*8.8.8.8.*//g"  /etc/csf/csf.ignore
  wait
  sed -i "s/.*8.8.4.4.*//g"  /etc/csf/csf.allow
  wait
  sed -i "s/.*8.8.4.4.*//g"  /etc/csf/csf.ignore
  wait
  echo "tcp|out|d=53|d=8.8.8.8 # Google DNS" >> /etc/csf/csf.allow
  echo "tcp|out|d=53|d=8.8.4.4 # Google DNS" >> /etc/csf/csf.allow
}

if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
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

  _n=$((RANDOM%120+90))
  touch /run/water.pid
  echo Waiting $n seconds...
  sleep ${_n}

  _NOW=$(date +%y%m%d-%H%M%S 2>&1)
  _NOW=${_NOW//[^0-9-]/}
  _useCnfUpdate=NO
  _vBs="/var/backups"
  _useCnf="/etc/csf/csf.allow"
  _preCnf="${_vBs}/dragon/t/csf.allow.backup-${_NOW}"
  _brkCnf="${_vBs}/dragon/t/csf.allow.broken-${_NOW}"
  if [ -f "${_useCnf}" ]; then
    mkdir -p ${_vBs}/dragon/t/
    cp -af ${_useCnf} ${_preCnf}
  fi

  _whitelist_ip_dns
  _whitelist_ip_pingdom
  _whitelist_ip_cloudflare
  _whitelist_ip_googlebot
  _whitelist_ip_microsoft
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_imperva
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_sucuri
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_authzero
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_site24x7_extra
  [ -e "/root/.extended.firewall.exceptions.cnf" ] && _whitelist_ip_site24x7

  if [ -f "${_useCnf}" ]; then
    _diffCnfTest=$(diff -w -B \
      -I pingdom \
      -I cloudflare \
      -I googlebot \
      -I microsoft \
      -I imperva \
      -I sucuri \
      -I authzero \
      -I site24x7 \
      -I DHCP ${_useCnf} ${_preCnf} 2>&1)
    if [ -z "${_diffCnfTest}" ]; then
      _useCnfUpdate=YES
      echo "YES $(date 2>&1) diff0 empty" >> ${_vBs}/dragon/t/csf.log
    else
      _diffCnfTest=$(echo -n ${_diffCnfTest} | fmt -su -w 2500 2>&1)
      echo "NO $(date 2>&1) diff1 ${_diffCnfTest}" >> ${_vBs}/dragon/t/csf.log
    fi
    if [[ "${_diffCnfTest}" =~ "No such file or directory" ]]; then
      echo "NO $(date 2>&1) diff3 ${_diffCnfTest}" >> ${_vBs}/dragon/t/csf.log
    fi
  fi
  if [ "${_myCnfUpdate}" = "NO" ]; then
    cp -af ${_useCnf} ${_brkCnf}
    cp -af ${_preCnf} ${_useCnf}
  fi

  if [ -e "/root/.full.csf.cleanup.cnf" ]; then
    sed -i "s/.*do not delete.*//g" /etc/csf/csf.deny
    wait
    sed -i "/^$/d" /etc/csf/csf.deny
    wait
  fi

  kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
  killall sleep &> /dev/null
  rm -f /etc/csf/csf.error
  service lfd restart
  wait
  csf -e
  wait
  csf -tf
  wait
  csf -q
  ### Linux kernel TCP SACK CVEs mitigation
  ### CVE-2019-11477 SACK Panic
  ### CVE-2019-11478 SACK Slowness
  ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
  if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
    if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
      sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
      iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
    fi
  fi

  echo local start `date`
  _local_ip_rg

  _HA=/var/xdrago/monitor/log/hackcheck.archive.log
  _HX=/var/xdrago/monitor/log/hackcheck.archive.x3.log
  _WA=/var/xdrago/monitor/log/scan_nginx.archive.log
  _WX=/var/xdrago/monitor/log/scan_nginx.archive.x3.log
  _FA=/var/xdrago/monitor/log/hackftp.archive.log
  _FX=/var/xdrago/monitor/log/hackftp.archive.x3.log

  echo guard start `date`
  _guard_stats
  rm -f /var/xdrago/monitor/log/ssh.log
  rm -f /var/xdrago/monitor/log/web.log
  rm -f /var/xdrago/monitor/log/ftp.log

  kill -9 $(ps aux | grep '[C]onfigServer' | awk '{print $2}') &> /dev/null
  killall sleep &> /dev/null
  rm -f /etc/csf/csf.error
  service lfd restart
  wait
  _NOW=$(date +%y%m%d-%H%M%S 2>&1)
  cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-dhcp-${_NOW}
  sed -i "s/.*DHCP.*//g" /etc/csf/csf.allow
  wait
  _NOW=$(date +%y%m%d-%H%M%S 2>&1)
  cp -a /etc/csf/csf.allow /var/backups/csf/water/csf.allow-clear-${_NOW}
  sed -i "/^$/d" /etc/csf/csf.allow
  wait
  sed -i "/^$/d" /etc/csf/csf.ignore
  wait
  if [ -e "/var/log/daemon.log" ]; then
    _DHCP_LOG="/var/log/daemon.log"
  else
    _DHCP_LOG="/var/log/syslog"
  fi
  grep DHCPREQUEST "${_DHCP_LOG}" | awk '{print $12}' | sort -u | while read -r _IP; do
    if [[ ${_IP} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      IFS='.' read -r oct1 oct2 oct3 oct4 <<< "${_IP}"
      if (( oct1 <= 255 && oct2 <= 255 && oct3 <= 255 && oct4 <= 255 )); then
        echo "udp|out|d=67|d=${_IP} # Local DHCP out" >> /etc/csf/csf.allow
      fi
    fi
  done
  csf -e
  wait
  csf -q
  ### Linux kernel TCP SACK CVEs mitigation
  ### CVE-2019-11477 SACK Panic
  ### CVE-2019-11478 SACK Slowness
  ### CVE-2019-11479 Excess Resource Consumption Due to Low MSS Values
  if [ -x "/usr/sbin/csf" ] && [ -e "/etc/csf/csf.deny" ]; then
    _SACK_TEST=$(ip6tables --list | grep tcpmss 2>&1)
    if [[ ! "${_SACK_TEST}" =~ "tcpmss" ]]; then
      sysctl net.ipv4.tcp_mtu_probing=0 &> /dev/null
      iptables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
      ip6tables -A INPUT -p tcp -m tcpmss --mss 1:500 -j DROP &> /dev/null
    fi
  fi
  rm -f /run/water.pid
  echo guard fin `date`
  ntpdate pool.ntp.org > /dev/null 2>&1 &
fi
exit 0
###EOF2024###
