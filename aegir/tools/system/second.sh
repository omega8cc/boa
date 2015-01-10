#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin

hold() {
  /etc/init.d/nginx stop
  killall -9 nginx
  sleep 1
  killall -9 nginx
  if [ -e "/etc/init.d/php56-fpm" ] ; then
    /etc/init.d/php56-fpm stop
  fi
  if [ -e "/etc/init.d/php55-fpm" ] ; then
    /etc/init.d/php55-fpm stop
  fi
  if [ -e "/etc/init.d/php54-fpm" ] ; then
    /etc/init.d/php54-fpm stop
  fi
  if [ -e "/etc/init.d/php53-fpm" ] ; then
    /etc/init.d/php53-fpm stop
  fi
  killall -9 php-fpm php-cgi
  echo "$(date 2>&1)" >> /var/xdrago/log/second.hold.log
  ### echo "load is ${_O_LOAD}:${_F_LOAD} while
  ### maxload is ${_O_LOAD_MAX}:${_F_LOAD_MAX}"
}

terminate() {
  if [ -e "/var/run/boa_run.pid" ] ; then
    sleep 1
  else
    killall -9 php drush.php wget curl
    echo "$(date 2>&1)" >> /var/xdrago/log/second.terminate.log
  fi
}

nginx_high_load_on() {
  mv -f /data/conf/nginx_high_load_off.conf /data/conf/nginx_high_load.conf
  /etc/init.d/nginx reload
}

nginx_high_load_off() {
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  /etc/init.d/nginx reload
}

check_vhost_health() {
  if [ -e "$1"* ] ; then
    echo vhost $1 exists
    _VHOST_TEST_PLACEHOLDER=$(grep "### access" $1* 2>&1)
    _VHOST_TEST_ALLOW=$(grep "allow .*;" $1* 2>&1)
    _VHOST_TEST_DENY=$(grep "deny .*;" $1* 2>&1)
    if [[ "$_VHOST_TEST_PLACEHOLDER" =~ "access" ]] \
      && [[ "$_VHOST_TEST_DENY" =~ "deny" ]] ; then
      if [[ "$_VHOST_TEST_ALLOW" =~ "allow" ]] ; then
        _VHOST_HEALTH=YES
      else
        _VHOST_HEALTH=YES
      fi
    else
      _VHOST_HEALTH=NO
      sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
        $1* &> /dev/null
      sed -i "s/limit_conn .*/limit_conn                   limreq 555;\n  \
        ### access none\n  deny                         all;/g" $1* &> /dev/null
    fi
  else
    echo vhost $1 does not exist
  fi
}

update_ip_auth_access() {
  touch /var/run/.auth.IP.list.pid
  if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
    if [ -e "/var/aegir/config/server_master/nginx/vhost.d/chive."* ] ; then
      sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
        /var/aegir/config/server_master/nginx/vhost.d/chive.* &> /dev/null
      sed -i "s/limit_conn .*/limit_conn                   limreq 555;\n  \
        ### access update/g" \
        /var/aegir/config/server_master/nginx/vhost.d/chive.* &> /dev/null
    fi
    if [ -e "/var/aegir/config/server_master/nginx/vhost.d/cgp."* ] ; then
      sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
        /var/aegir/config/server_master/nginx/vhost.d/cgp.* &> /dev/null
      sed -i "s/limit_conn .*/limit_conn                   limreq 555;\n  \
        ### access update/g" \
        /var/aegir/config/server_master/nginx/vhost.d/cgp.* &> /dev/null
    fi
    if [ -e "/var/aegir/config/server_master/nginx/vhost.d/sqlbuddy."* ] ; then
      sed -i "s/### access .*//g; s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" \
        /var/aegir/config/server_master/nginx/vhost.d/sqlbuddy.* &> /dev/null
      sed -i "s/limit_conn .*/limit_conn                   limreq 555;\n  \
        ### access update/g" \
        /var/aegir/config/server_master/nginx/vhost.d/sqlbuddy.* &> /dev/null
    fi
    sleep 1
    sed -i '/  ### access .*/ {r /var/backups/.auth.IP.list.tmp
d;};' /var/aegir/config/server_master/nginx/vhost.d/chive.* &> /dev/null
    sed -i '/  ### access .*/ {r /var/backups/.auth.IP.list.tmp
d;};' /var/aegir/config/server_master/nginx/vhost.d/cgp.* &> /dev/null
    sed -i '/  ### access .*/ {r /var/backups/.auth.IP.list.tmp
d;};' /var/aegir/config/server_master/nginx/vhost.d/sqlbuddy.* &> /dev/null
    mv -f /var/aegir/config/server_master/nginx/vhost.d/sed* /var/backups/
    check_vhost_health "/var/aegir/config/server_master/nginx/vhost.d/chive."
    check_vhost_health "/var/aegir/config/server_master/nginx/vhost.d/cgp."
    check_vhost_health "/var/aegir/config/server_master/nginx/vhost.d/sqlbuddy."
    _NGX_TEST=$(service nginx configtest 2>&1)
    if [[ "$_NGX_TEST" =~ "successful" ]] ; then
      service nginx reload &> /dev/null
    else
      service nginx reload &> /var/backups/.auth.IP.list.ops
      sed -i "s/allow .*;//g; s/ *$//g; /^$/d" \
        /var/aegir/config/server_master/nginx/vhost.d/chive.*    &> /dev/null
      sed -i "s/allow .*;//g; s/ *$//g; /^$/d" \
        /var/aegir/config/server_master/nginx/vhost.d/cgp.*      &> /dev/null
      sed -i "s/allow .*;//g; s/ *$//g; /^$/d" \
        /var/aegir/config/server_master/nginx/vhost.d/sqlbuddy.* &> /dev/null
      check_vhost_health "/var/aegir/config/server_master/nginx/vhost.d/chive."
      check_vhost_health "/var/aegir/config/server_master/nginx/vhost.d/cgp."
      check_vhost_health "/var/aegir/config/server_master/nginx/vhost.d/sqlbuddy."
      service nginx reload &> /dev/null
    fi
  fi
  rm -f /var/backups/.auth.IP.list
  for _IP in `who --ips \
    | sed 's/.*tty.*//g; s/.*root.*hvc.*//g' \
    | cut -d: -f2 \
    | cut -d' ' -f2 \
    | sed 's/.*\/.*:S.*//g; s/:S.*//g; s/(//g' \
    | tr -d "\s" \
    | sort \
    | uniq`;do _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" \
      >> /var/backups/.auth.IP.list;done
  if [ -e "/root/.ip.protected.vhost.whitelist.cnf" ] ; then
    for _IP in `cat /root/.ip.protected.vhost.whitelist.cnf \
      | sort \
      | uniq`;do _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" \
        >> /var/backups/.auth.IP.list;done
  fi
  sed -i "s/\.;/;/g; s/allow                        ;//g; s/ *$//g; /^$/d" \
    /var/backups/.auth.IP.list &> /dev/null
  if [ -e "/var/backups/.auth.IP.list" ] ; then
    _ALLOW_TEST_LIST=$(grep allow /var/backups/.auth.IP.list)
  fi
  if [[ "$_ALLOW_TEST_LIST" =~ "allow" ]] ; then
    echo "  deny                         all;" >> /var/backups/.auth.IP.list
    echo "  ### access live"                   >> /var/backups/.auth.IP.list
  else
    echo "  deny                         all;" >  /var/backups/.auth.IP.list
    echo "  ### access none"                   >> /var/backups/.auth.IP.list
  fi
  sleep 1
  rm -f /var/run/.auth.IP.list.pid
}

manage_ip_auth_access() {
  for _IP in `who --ips \
    | sed 's/.*tty.*//g; s/.*root.*hvc.*//g' \
    | cut -d: -f2 \
    | cut -d' ' -f2 \
    | sed 's/.*\/.*:S.*//g; s/:S.*//g; s/(//g' \
    | tr -d "\s" \
    | sort \
    | uniq`;do _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" \
      >> /var/backups/.auth.IP.list.tmp;done
  if [ -e "/root/.ip.protected.vhost.whitelist.cnf" ] ; then
    for _IP in `cat /root/.ip.protected.vhost.whitelist.cnf \
      | sort \
      | uniq`;do _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" \
        >> /var/backups/.auth.IP.list.tmp;done
  fi
  sed -i "s/\.;/;/g; s/allow                        ;//g; s/ *$//g; /^$/d" \
    /var/backups/.auth.IP.list.tmp &> /dev/null
  if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
    _ALLOW_TEST_TMP=$(grep allow /var/backups/.auth.IP.list.tmp)
  fi
  if [[ "$_ALLOW_TEST_TMP" =~ "allow" ]] ; then
    echo "  deny                         all;" >> /var/backups/.auth.IP.list.tmp
    echo "  ### access live"                   >> /var/backups/.auth.IP.list.tmp
  else
    echo "  deny                         all;" >  /var/backups/.auth.IP.list.tmp
    echo "  ### access none"                   >> /var/backups/.auth.IP.list.tmp
  fi
  if [ ! -e "/var/run/.auth.IP.list.pid" ] ; then
    if [ ! -e "/var/backups/.auth.IP.list" ] ; then
      update_ip_auth_access
    else
      if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
        _DIFF_TEST=$(diff /var/backups/.auth.IP.list.tmp \
          /var/backups/.auth.IP.list)
        if [ ! -z "${_DIFF_TEST}" ] ; then
          update_ip_auth_access
        fi
      fi
    fi
  fi
  if [ -L "/var/backups/.vhost.d.mstr" ] ; then
    if [ ! -d "/var/backups/.vhost.d.wbhd" ] ; then
      mkdir -p /var/backups/.vhost.d.wbhd
      chmod 700 /var/backups/.vhost.d.wbhd
      cp -af /var/backups/.vhost.d.mstr/* /var/backups/.vhost.d.wbhd/
    fi
    _DIFF_CLSTR_TEST=$(diff /var/backups/.vhost.d.wbhd /var/backups/.vhost.d.mstr)
    if [ ! -z "${_DIFF_CLSTR_TEST}" ] ; then
      service nginx reload &> /dev/null
      rm -f -r /var/backups/.vhost.d.wbhd
      mkdir -p /var/backups/.vhost.d.wbhd
      chmod 700 /var/backups/.vhost.d.wbhd
      cp -af /var/backups/.vhost.d.mstr/* /var/backups/.vhost.d.wbhd/
    fi
  fi
  if [[ "$_ALLOW_TEST_TMP" =~ "allow" ]] ; then
    _VHOST_STATUS_CHIVE=TRUE
    _VHOST_STATUS_CGP=TRUE
    _VHOST_STATUS_SQLBUDDY=TRUE
    if [ -e "/var/aegir/config/server_master/nginx/vhost.d/chive."* ] ; then
      _VHOST_STATUS_CHIVE=FALSE
      _ALLOW_TEST_VHOST_CHIVE=$(grep allow \
        /var/aegir/config/server_master/nginx/vhost.d/chive.*)
      if [[ "$_ALLOW_TEST_VHOST_CHIVE" =~ "allow" ]] ; then
        _VHOST_STATUS_CHIVE=TRUE
      fi
    fi
    if [ -e "/var/aegir/config/server_master/nginx/vhost.d/cgp."* ] ; then
      _VHOST_STATUS_CGP=FALSE
      _ALLOW_TEST_VHOST_CGP=$(grep allow \
        /var/aegir/config/server_master/nginx/vhost.d/cgp.*)
      if [[ "$_ALLOW_TEST_VHOST_CGP" =~ "allow" ]] ; then
        _VHOST_STATUS_CGP=TRUE
      fi
    fi
    if [ -e "/var/aegir/config/server_master/nginx/vhost.d/sqlbuddy."* ] ; then
      _VHOST_STATUS_SQLBUDDY=FALSE
      _ALLOW_TEST_VHOST_SQLBUDDY=$(grep allow \
        /var/aegir/config/server_master/nginx/vhost.d/sqlbuddy.*)
      if [[ "$_ALLOW_TEST_VHOST_SQLBUDDY" =~ "allow" ]] ; then
        _VHOST_STATUS_SQLBUDDY=TRUE
      fi
    fi
    if [ "$_VHOST_STATUS_CHIVE" = "FALSE" ] \
      || [ "$_VHOST_STATUS_CGP" = "FALSE" ] \
      || [ "$_VHOST_STATUS_SQLBUDDY" = "FALSE" ] ; then
      update_ip_auth_access
    fi
  fi
  rm -f /var/backups/.auth.IP.list.tmp
}

proc_control() {
  if [ "${_O_LOAD}" -ge "${_O_LOAD_MAX}" ] ; then
    hold
  elif [ "${_F_LOAD}" -ge "${_F_LOAD_MAX}" ] ; then
    hold
  else
    echo load is ${_O_LOAD}:${_F_LOAD} while maxload is ${_O_LOAD_MAX}:${_F_LOAD_MAX}
    echo ...OK now running proc_num_ctrl...
    perl /var/xdrago/proc_num_ctrl.cgi
    touch /var/xdrago/log/proc_num_ctrl.done
    echo CTL done
  fi
}

load_control() {
  _O_LOAD=$(awk '{print $1*100}' /proc/loadavg 2>&1)
  echo _O_LOAD is ${_O_LOAD}
  _O_LOAD=$(( _O_LOAD / _CPU_NR ))
  echo _O_LOAD per CPU is ${_O_LOAD}

  _F_LOAD=$(awk '{print $2*100}' /proc/loadavg 2>&1)
  echo _F_LOAD is ${_F_LOAD}
  _F_LOAD=$(( _F_LOAD / _CPU_NR ))
  echo _F_LOAD per CPU is ${_F_LOAD}

  _O_LOAD_SPR=$(( 100 * _CPU_SPIDER_RATIO ))
  echo _O_LOAD_SPR is ${_O_LOAD_SPR}

  _F_LOAD_SPR=$(( _O_LOAD_SPR / 9 ))
  _F_LOAD_SPR=$(( _F_LOAD_SPR * 7 ))
  echo _F_LOAD_SPR is ${_F_LOAD_SPR}

  _O_LOAD_MAX=$(( 100 * _CPU_MAX_RATIO ))
  echo _O_LOAD_MAX is ${_O_LOAD_MAX}

  _F_LOAD_MAX=$(( _O_LOAD_MAX / 9 ))
  _F_LOAD_MAX=$(( _F_LOAD_MAX * 7 ))
  echo _F_LOAD_MAX is ${_F_LOAD_MAX}

  _O_LOAD_CRT=$(( _CPU_CRIT_RATIO * 100 ))
  echo _O_LOAD_CRT is ${_O_LOAD_CRT}

  _F_LOAD_CRT=$(( _O_LOAD_CRT / 9 ))
  _F_LOAD_CRT=$(( _F_LOAD_CRT * 7 ))
  echo _F_LOAD_CRT is ${_F_LOAD_CRT}

  if [ "${_O_LOAD}" -ge "${_O_LOAD_SPR}" ] \
    && [ "${_O_LOAD}" -lt "${_O_LOAD_MAX}" ] \
    && [ -e "/data/conf/nginx_high_load_off.conf" ] ; then
    nginx_high_load_on
  elif [ "${_F_LOAD}" -ge "${_F_LOAD_SPR}" ] \
    && [ "${_F_LOAD}" -lt "${_F_LOAD_MAX}" ] \
    && [ -e "/data/conf/nginx_high_load_off.conf" ] ; then
    nginx_high_load_on
  elif [ "${_O_LOAD}" -lt "${_O_LOAD_SPR}" ] \
    && [ "${_F_LOAD}" -lt "${_F_LOAD_SPR}" ] \
    && [ -e "/data/conf/nginx_high_load.conf" ] ; then
    nginx_high_load_off
  fi

  if [ "${_O_LOAD}" -ge "${_O_LOAD_CRT}" ] ; then
    terminate
  elif [ "${_F_LOAD}" -ge "${_F_LOAD_CRT}" ] ; then
    terminate
  fi

  proc_control
}

count_cpu() {
  _CPU_INFO=$(grep -c processor /proc/cpuinfo 2>&1)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc 2>&1)
  if [ -z "${_NPROC_TEST}" ] ; then
    _CPU_NR="${_CPU_INFO}"
  else
    _CPU_NR=$(nproc 2>&1)
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "${_CPU_NR}" ] \
    && [ ! -z "${_CPU_INFO}" ] \
    && [ "${_CPU_NR}" -gt "${_CPU_INFO}" ] \
    && [ "${_CPU_INFO}" -gt "0" ] ; then
    _CPU_NR="${_CPU_INFO}"
  fi
  if [ -z "${_CPU_NR}" ] || [ "${_CPU_NR}" -lt "1" ] ; then
    _CPU_NR=1
  fi
}

if [ -e "/root/.barracuda.cnf" ] ; then
  source /root/.barracuda.cnf
  _CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO//[^0-9]/}
  _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  _CPU_CRIT_RATIO=${_CPU_CRIT_RATIO//[^0-9]/}
fi

if [ -z "${_CPU_SPIDER_RATIO}" ] ; then
  _CPU_SPIDER_RATIO=3
fi
if [ -z "${_CPU_MAX_RATIO}" ] ; then
  _CPU_MAX_RATIO=6
fi
if [ -z "${_CPU_CRIT_RATIO}" ] ; then
  _CPU_CRIT_RATIO=9
fi

count_cpu
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
sleep 3
load_control
manage_ip_auth_access
echo Done !
exit 0
###EOF2015###
