#!/bin/bash

SHELL=/bin/bash
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

hold()
{
  /etc/init.d/nginx stop
  killall -9 nginx
  sleep 1
  killall -9 nginx
  if [ -e "/etc/init.d/php55-fpm" ] ; then
    /etc/init.d/php55-fpm stop
  fi
  if [ -e "/etc/init.d/php54-fpm" ] ; then
    /etc/init.d/php54-fpm stop
  fi
  if [ -e "/etc/init.d/php53-fpm" ] ; then
    /etc/init.d/php53-fpm stop
  fi
  if [ -e "/etc/init.d/php52-fpm" ] ; then
    /etc/init.d/php52-fpm stop
  fi
  killall -9 php-fpm php-cgi
  echo `date` >> /var/xdrago/log/second.hold.log
  echo load is $_O_LOAD:$_F_LOAD while maxload is $_O_LOAD_MAX:$_F_LOAD_MAX
}

terminate()
{
  if [ -e "/var/run/boa_run.pid" ] ; then
    sleep 1
  else
    killall -9 php drush.php wget curl
    echo `date` >> /var/xdrago/log/second.terminate.log
  fi
}

nginx_high_load_on()
{
  mv -f /data/conf/nginx_high_load_off.conf /data/conf/nginx_high_load.conf
  /etc/init.d/nginx reload
}

nginx_high_load_off()
{
  mv -f /data/conf/nginx_high_load.conf /data/conf/nginx_high_load_off.conf
  /etc/init.d/nginx reload
}

update_ip_auth_access()
{
  if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
    sed -i "s/allow .*;//g; s/deny .*;//g; s/ *$//g; /^$/d" /var/aegir/config/server_master/nginx/vhost.d/* &> /dev/null
    sed -i '/  ### access .*/ {r /var/backups/.auth.IP.list.tmp
d;};' /var/aegir/config/server_master/nginx/vhost.d/* &> /dev/null
    _NGX_TEST=$(service nginx configtest 2>&1)
    if [[ "$_NGX_TEST" =~ "successful" ]] ; then
      service nginx reload &> /dev/null
    else
      service nginx reload &> /var/backups/.auth.IP.list.ops
      sed -i "s/allow .*;//g; s/ *$//g; /^$/d" /var/aegir/config/server_master/nginx/vhost.d/* &> /dev/null
      service nginx reload &> /dev/null
    fi
  fi
  rm -f /var/backups/.auth.IP.list
  for _IP in `who --ips | awk '{print $5}' | sort | uniq | tr -d "\s"`;do _IP=$(echo $_IP | cut -d: -f1); _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" >> /var/backups/.auth.IP.list;done
  sed -i "s/\.;/;/g; s/allow                        ;//g; s/ *$//g; /^$/d" /var/backups/.auth.IP.list &> /dev/null
  if [ -e "/var/backups/.auth.IP.list" ] ; then
    _ALLOW_TEST=$(grep allow /var/backups/.auth.IP.list)
  fi
  if [[ "$_ALLOW_TEST" =~ "allow" ]] ; then
    echo "  deny                         all;" >> /var/backups/.auth.IP.list
    echo "  ### access live"                   >> /var/backups/.auth.IP.list
  else
    echo "  deny                         all;" >  /var/backups/.auth.IP.list
    echo "  ### access none"                   >> /var/backups/.auth.IP.list
  fi
}

manage_ip_auth_access()
{
  for _IP in `who --ips | awk '{print $5}' | sort | uniq | tr -d "\s"`;do _IP=$(echo $_IP | cut -d: -f1); _IP=${_IP//[^0-9.]/};echo "  allow                        $_IP;" >> /var/backups/.auth.IP.list.tmp;done
  sed -i "s/\.;/;/g; s/allow                        ;//g; s/ *$//g; /^$/d" /var/backups/.auth.IP.list.tmp &> /dev/null
  if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
    _ALLOW_TEST=$(grep allow /var/backups/.auth.IP.list.tmp)
  fi
  if [[ "$_ALLOW_TEST" =~ "allow" ]] ; then
    echo "  deny                         all;" >> /var/backups/.auth.IP.list.tmp
    echo "  ### access live"                   >> /var/backups/.auth.IP.list.tmp
  else
    echo "  deny                         all;" >  /var/backups/.auth.IP.list.tmp
    echo "  ### access none"                   >> /var/backups/.auth.IP.list.tmp
  fi
  if [ ! -e "/var/backups/.auth.IP.list" ] ; then
    update_ip_auth_access
  else
    if [ -e "/var/backups/.auth.IP.list.tmp" ] ; then
      _DIFF_TEST=$(diff /var/backups/.auth.IP.list.tmp /var/backups/.auth.IP.list)
      if [ ! -z "$_DIFF_TEST" ] ; then
        update_ip_auth_access
      fi
    fi
  fi
  rm -f /var/backups/.auth.IP.list.tmp
}

proc_control()
{
  if [ $_O_LOAD -ge $_O_LOAD_MAX ] ; then
    hold
  elif [ $_F_LOAD -ge $_F_LOAD_MAX ] ; then
    hold
  else
    echo load is $_O_LOAD:$_F_LOAD while maxload is $_O_LOAD_MAX:$_F_LOAD_MAX
    echo ...OK now running proc_num_ctrl...
    perl /var/xdrago/proc_num_ctrl.cgi
    touch /var/xdrago/log/proc_num_ctrl.done
    manage_ip_auth_access
    echo CTL done
  fi
}

load_control()
{
  _O_LOAD=`awk '{print $1*100}' /proc/loadavg`
  echo _O_LOAD is $_O_LOAD
  let "_O_LOAD = (($_O_LOAD / $_CPU_NR))"
  echo _O_LOAD per CPU is $_O_LOAD

  _F_LOAD=`awk '{print $2*100}' /proc/loadavg`
  echo _F_LOAD is $_F_LOAD
  let "_F_LOAD = (($_F_LOAD / $_CPU_NR))"
  echo _F_LOAD per CPU is $_F_LOAD

  let "_O_LOAD_SPR = ((100 * $_CPU_SPIDER_RATIO))"
  echo _O_LOAD_SPR is $_O_LOAD_SPR

  let "_F_LOAD_SPR = (($_O_LOAD_SPR / 9))"
  let "_F_LOAD_SPR = (($_F_LOAD_SPR * 7))"
  echo _F_LOAD_SPR is $_F_LOAD_SPR

  let "_O_LOAD_MAX = ((100 * $_CPU_MAX_RATIO))"
  echo _O_LOAD_MAX is $_O_LOAD_MAX

  let "_F_LOAD_MAX = (($_O_LOAD_MAX / 9))"
  let "_F_LOAD_MAX = (($_F_LOAD_MAX * 7))"
  echo _F_LOAD_MAX is $_F_LOAD_MAX

  let "_O_LOAD_CRT = ((100 * $_CPU_CRIT_RATIO))"
  echo _O_LOAD_CRT is $_O_LOAD_CRT

  let "_F_LOAD_CRT = (($_O_LOAD_CRT / 9))"
  let "_F_LOAD_CRT = (($_F_LOAD_CRT * 7))"
  echo _F_LOAD_CRT is $_F_LOAD_CRT

  if [ $_O_LOAD -ge $_O_LOAD_SPR ] && [ $_O_LOAD -lt $_O_LOAD_MAX ] && [ -e "/data/conf/nginx_high_load_off.conf" ] ; then
    nginx_high_load_on
  elif [ $_F_LOAD -ge $_F_LOAD_SPR ] && [ $_F_LOAD -lt $_F_LOAD_MAX ] && [ -e "/data/conf/nginx_high_load_off.conf" ] ; then
    nginx_high_load_on
  elif [ $_O_LOAD -lt $_O_LOAD_SPR ] && [ $_F_LOAD -lt $_F_LOAD_SPR ] && [ -e "/data/conf/nginx_high_load.conf" ] ; then
    nginx_high_load_off
  fi

  if [ $_O_LOAD -ge $_O_LOAD_CRT ] ; then
    terminate
  elif [ $_F_LOAD -ge $_F_LOAD_CRT ] ; then
    terminate
  fi

  proc_control
}

count_cpu()
{
  _CPU_INFO=$(grep -c processor /proc/cpuinfo)
  _CPU_INFO=${_CPU_INFO//[^0-9]/}
  _NPROC_TEST=$(which nproc)
  if [ -z "$_NPROC_TEST" ] ; then
    _CPU_NR="$_CPU_INFO"
  else
    _CPU_NR=`nproc`
  fi
  _CPU_NR=${_CPU_NR//[^0-9]/}
  if [ ! -z "$_CPU_NR" ] && [ ! -z "$_CPU_INFO" ] && [ "$_CPU_NR" -gt "$_CPU_INFO" ] && [ "$_CPU_INFO" -gt "0" ] ; then
    _CPU_NR="$_CPU_INFO"
  fi
  if [ -z "$_CPU_NR" ] || [ "$_CPU_NR" -lt "1" ] ; then
    _CPU_NR=1
  fi
}

if [ -e "/root/.barracuda.cnf" ] ; then
  source /root/.barracuda.cnf
  _CPU_SPIDER_RATIO=${_CPU_SPIDER_RATIO//[^0-9]/}
  _CPU_MAX_RATIO=${_CPU_MAX_RATIO//[^0-9]/}
  _CPU_CRIT_RATIO=${_CPU_CRIT_RATIO//[^0-9]/}
fi

if [ -z "$_CPU_SPIDER_RATIO" ] ; then
  _CPU_SPIDER_RATIO=3
fi
if [ -z "$_CPU_MAX_RATIO" ] ; then
  _CPU_MAX_RATIO=6
fi
if [ -z "$_CPU_CRIT_RATIO" ] ; then
  _CPU_CRIT_RATIO=9
fi

count_cpu
load_control
sleep 10
load_control
sleep 10
load_control
sleep 10
load_control
sleep 10
load_control
sleep 10
load_control
echo Done !
###EOF2014###
