#!/usr/bin/perl

###
### System Services Monitor running every 5 seconds
###
local(@RSARR) = system("grep -e redis_client_socket /data/conf/global.inc");
foreach $line (@RSARR) {
  if ($line =~ /redis_client_socket/) {$redissocket = "YES";}
  print "\n Redis socket mode detected...\n";
}
if (!-d "/var/run/redis") {
  system("mkdir -p /var/run/redis");
  system("chown -R redis:redis /var/run/redis");
}
if (!-d "/var/run/mysqld") {
  system("mkdir -p /var/run/mysqld");
  system("chown -R mysql:root /var/run/mysqld");
}
system("service redis-server restart") if (!-e "/var/run/redis/redis.sock" && $redissocket);
sleep(2);
system("service redis-server restart") if (!-f "/var/run/redis/redis.pid");
&cpu_count_load;
&global_action;
foreach $USER (sort keys %li_cnt) {
  print " $li_cnt{$USER}\t$USER\n";
  push(@donetable," $li_cnt{$USER}\t$USER");
  $sumar = $sumar + $li_cnt{$USER};
  if ($USER eq "mysql") {$mysqlives = "YES"; $mysqlsumar = $li_cnt{$USER};}
  if ($USER eq "jetty7") {$jetty7lives = "YES"; $jetty7sumar = $li_cnt{$USER};}
  if ($USER eq "jetty8") {$jetty8lives = "YES"; $jetty8sumar = $li_cnt{$USER};}
  if ($USER eq "jetty9") {$jetty9lives = "YES"; $jetty9sumar = $li_cnt{$USER};}
  if ($USER eq "tomcat") {$tomcatlives = "YES"; $tomcatsumar = $li_cnt{$USER};}
}
foreach $COMMAND (sort keys %li_cnt) {
  if ($COMMAND =~ /named/) {$namedlives = "YES"; $namedsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /buagent/) {$buagentlives = "YES"; $buagentsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /collectd/) {$collectdlives = "YES"; $collectdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /dhcpcd-bin/) {$dhcpcdlives = "YES"; $dhcpcdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /nginx/) {$nginxlives = "YES"; $nginxsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /pdnsd/) {$pdnsdlives = "YES"; $pdnsdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /php-cgi/) {$phplives = "YES"; $phpsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /php-fpm/) {$fpmlives = "YES"; $fpmsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /postfix/) {$postfixlives = "YES"; $postfixsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /pure-ftpd/) {$ftplives = "YES"; $ftpsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /redis-server/) {$redislives = "YES"; $redissumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /newrelic-daemon/) {$newrelicdaemonlives = "YES"; $newrelicdaemonsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /nrsysmond/) {$newrelicsysmondlives = "YES"; $newrelicsysmondsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /rsyslogd/) {$rsyslogdlives = "YES"; $rsyslogdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/syslogd/) {$sysklogdlives = "YES"; $sysklogdsumar = $li_cnt{$COMMAND};}
}
foreach $X (sort keys %li_cnt) {
  if ($X =~ /php55/) {$php55lives = "YES";}
  if ($X =~ /php54/) {$php54lives = "YES";}
  if ($X =~ /php53/) {$php53lives = "YES";}
  if ($X =~ /php52/) {$php52lives = "YES";}
}
print "\n $sumar ALL procs\t\tGLOBAL";
print "\n $namedsumar Bind procs\t\tGLOBAL" if ($namedlives);
print "\n $buagentsumar Backup procs\t\tGLOBAL" if ($buagentlives);
print "\n $collectdsumar Collectd\t\tGLOBAL" if ($collectdlives);
print "\n $dhcpcdsumar dhcpcd procs\t\tGLOBAL" if ($dhcpcdlives);
print "\n $fpmsumar FPM procs\t\tGLOBAL" if ($fpmlives);
print "\n 1 FPM55 procs\t\tGLOBAL" if ($php55lives);
print "\n 1 FPM54 procs\t\tGLOBAL" if ($php54lives);
print "\n 1 FPM53 procs\t\tGLOBAL" if ($php53lives);
print "\n 1 FPM52 procs\t\tGLOBAL" if ($php52lives);
print "\n $ftpsumar FTP procs\t\tGLOBAL" if ($ftplives);
print "\n $mysqlsumar MySQL procs\t\tGLOBAL" if ($mysqlives);
print "\n $nginxsumar Nginx procs\t\tGLOBAL" if ($nginxlives);
print "\n $pdnsdsumar DNS procs\t\tGLOBAL" if ($pdnsdlives);
print "\n $phpsumar PHP procs\t\tGLOBAL" if ($phplives);
print "\n $postfixsumar Postfix procs\tGLOBAL" if ($postfixlives);
print "\n $redissumar Redis procs\t\tGLOBAL" if ($redislives);
print "\n $newrelicdaemonsumar New Relic Apps\tGLOBAL" if ($newrelicdaemonlives);
print "\n $newrelicsysmondsumar New Relic Server\tGLOBAL" if ($newrelicsysmondlives);
print "\n $jetty7sumar Jetty7 procs\t\tGLOBAL" if ($jetty7lives);
print "\n $jetty8sumar Jetty8 procs\t\tGLOBAL" if ($jetty8lives);
print "\n $jetty9sumar Jetty9 procs\t\tGLOBAL" if ($jetty9lives);
print "\n $tomcatsumar Tomcat procs\t\tGLOBAL" if ($tomcatlives);
print "\n $rsyslogdsumar Syslog procs\t\tGLOBAL" if ($rsyslogdlives);
print "\n $sysklogdsumar Syslog procs\t\tGLOBAL" if ($sysklogdlives);
`/etc/init.d/bind9 restart` if (!$namedsumar && -f "/etc/init.d/bind9");
if (-e "/usr/sbin/pdnsd" && !$pdnsdsumar && !-f "/var/run/boa_run.pid") {
  system("/etc/init.d/pdnsd stop");
  system("rm -f /var/cache/pdnsd/pdnsd.cache");
  system("/etc/init.d/pdnsd start");
}
if ((!$mysqlsumar || $mysqlsumar > 150) && !-f "/var/xdrago/log/mysql_restart_running.pid" && !-f "/var/run/boa_run.pid") {
  `bash /var/xdrago/move_sql.sh`;
}
if (!$redissumar && (-f "/etc/init.d/redis-server" || -f "/etc/init.d/redis") && !-f "/var/run/boa_run.pid") {
  if (-f "/etc/init.d/redis-server") { `/etc/init.d/redis-server start`; }
  elsif (-f "/etc/init.d/redis") { `/etc/init.d/redis start`; }
}
`/etc/init.d/newrelic-daemon restart` if (!$newrelicdaemonsumar && -f "/etc/init.d/newrelic-daemon" && !-f "/var/run/boa_run.pid");
`/etc/init.d/newrelic-sysmond restart` if (!$newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond" && !-f "/var/run/boa_run.pid");
`/etc/init.d/postfix restart` if (!$postfixsumar && -f "/etc/init.d/postfix" && !-f "/var/run/boa_run.pid");
if (!$nginxsumar && -f "/etc/init.d/nginx" && !-f "/var/run/boa_run.pid") {
  system("killall -9 nginx");
  system("/etc/init.d/nginx start");
}
`/etc/init.d/php55-fpm restart` if ((!$php55lives || !$fpmsumar || $fpmsumar > 4 || !-f "/var/run/php55-fpm.pid") && -f "/etc/init.d/php55-fpm" && !-f "/var/run/boa_run.pid");
`/etc/init.d/php54-fpm restart` if ((!$php54lives || !$fpmsumar || $fpmsumar > 4 || !-f "/var/run/php54-fpm.pid") && -f "/etc/init.d/php54-fpm" && !-f "/var/run/boa_run.pid");
`/etc/init.d/php53-fpm restart` if ((!$php53lives || !$fpmsumar || $fpmsumar > 4 || !-f "/var/run/php53-fpm.pid") && -f "/etc/init.d/php53-fpm" && !-f "/var/run/boa_run.pid");
`/etc/init.d/php52-fpm restart` if ((!$php52lives || !$phpsumar || !-f "/var/run/php52-fpm.pid") && -f "/etc/init.d/php52-fpm" && !-f "/var/run/boa_run.pid");
`/etc/init.d/jetty7 start` if (!$jetty7sumar && -f "/etc/init.d/jetty7" && !-f "/var/run/boa_run.pid");
`/etc/init.d/jetty8 start` if (!$jetty8sumar && -f "/etc/init.d/jetty8" && !-f "/var/run/boa_run.pid");
`/etc/init.d/jetty9 start` if (!$jetty9sumar && -f "/etc/init.d/jetty9" && !-f "/var/run/boa_run.pid");
`/etc/init.d/tomcat start` if (!$tomcatsumar && -f "/etc/init.d/tomcat" && !-f "/var/run/boa_run.pid");
`/etc/init.d/collectd start` if (!$collectdsumar && -f "/etc/init.d/collectd" && !-f "/var/run/boa_run.pid");
`/etc/init.d/postfix restart` if (!-f "/var/spool/postfix/pid/master.pid");
if (-f "/usr/local/sbin/pure-config.pl") {
  `/usr/local/sbin/pure-config.pl /usr/local/etc/pure-ftpd.conf` if (!$ftpsumar && !-f "/var/run/boa_run.pid");
}
if ($mysqlsumar > 0) {
  $resultmysql5 = `mysqladmin flush-hosts 2>&1`;
  print "\n MySQL hosts flushed...\n";
}
if ($dhcpcdlives) {
  $thishostname = `cat /etc/hostname`;
  chomp($thishostname);
  `hostname -b $thishostname`;
}
if (-f "/etc/init.d/rsyslog") {
  if (!$rsyslogdsumar || !-f "/var/run/rsyslogd.pid") {
    system("service rsyslog restart");
  }
}
elsif (-f "/etc/init.d/sysklogd") {
  if (!$sysklogdsumar || !-f "/var/run/syslogd.pid") {
    system("service sysklogd restart");
  }
}
exit;

#############################################################################
sub global_action
{
  local(@MYARR) = `ps auxf 2>&1`;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,\?\=\|\\\+]//g;
    local($USER, $PID, $CPU, $MEM, $VSZ, $RSS, $TTY, $STAT, $START, $TIME, $COMMAND, $B, $K, $X, $Y, $Z, $T) = split(/\s+/,$line);
    $PID =~ s/[^0-9]//g;
    $li_cnt{$USER}++ if ($PID);
    $li_cnt{$X}++ if ($PID && $COMMAND =~ /php-fpm/ && $X =~ /php/);
    local($fpm_result) = "CTRL";

    if ($PID)
    {
      local($HOUR, $MIN) = split(/:/,$TIME);

      if ($COMMAND =~ /^(\\)/ && $B =~ /mysqld/ && $CPU > 10 && $USER =~ /mysql/)
      {
        $timedate=`date +%y%m%d-%H%M%S`;
        chomp($timedate);
        if ($CPU > $MAXCPU && $HOUR > 1 && ($STAT =~ /R/ || $STAT =~ /Z/))
        {
          if (!-f "/var/xdrago/log/mysql_restart_running.pid" && !-f "/var/run/boa_wait.pid") {
           `bash /var/xdrago/move_sql.sh`;
            $timedate=`date +%y%m%d-%H%M%S`;
            chomp($timedate);
           `echo "$USER CPU:$CPU MAXCPU:$MAXCPU $STAT START:$START TIME:$TIME $timedate" >> /var/xdrago/log/mysql.forced.restart.log`;
          }
        }
       `echo "$USER CPU:$CPU MAXCPU:$MAXCPU $STAT START:$START TIME:$TIME $timedate" >> /var/xdrago/log/mysql.test.log`;
      }

      if ($COMMAND =~ /^(\\)/ && $B =~ /php-fpm/ && $K =~ /pool/ && $CPU > 80 && ($STAT =~ /R/ || $STAT =~ /Z/) && $USER !~ /root/)
      {
        if ($HOUR > "0" || $MIN > 1)
        {
          $timedate=`date +%y%m%d-%H%M%S`;
          chomp($timedate);
          if ($CPU > $MAXCPU)
          {
            if (!-e "/root/.no.fpm.cpu.limit.cnf") {
             `kill -9 $PID`;
             `echo "$X CPU:$CPU $STAT START:$START TIME:$TIME $timedate" >> /var/xdrago/log/php-fpm.kill.log`;
              $fpm_result = "KILLED";
            }
          }
         `echo "$X CPU:$CPU $STAT START:$START TIME:$TIME $timedate $fpm_result" >> /var/xdrago/log/php-fpm.test.log`;
        }
      }

      if ($COMMAND =~ /^(\|)/ && $K =~ /convert/ && $CPU > 90 && $MIN > 1 && ($STAT =~ /R/ || $STAT =~ /Z/))
      {
        $timedate=`date +%y%m%d-%H%M%S`;
        chomp($timedate);
       `kill -9 $PID`;
       `echo "$USER $CPU $STAT $START $TIME $timedate" >> /var/xdrago/log/convert.kill.log`;
        $kill_convert = "YES";
      }

      if ($kill_convert && $COMMAND =~ /^(\|)/ && $K =~ /bin/ && $Y =~ /convert/)
      {
       `kill -9 $PID`;
       `echo "$USER $CPU $STAT $START $TIME $timedate" >> /var/xdrago/log/convert.kill.log`;
      }

      if ($COMMAND =~ /^(sh|git)/ && $START =~ /[A-Z]/ && $B =~ /(-c|git|clone)/)
      {
         $timedate=`date +%y%m%d-%H%M%S`;
         chomp($timedate);
         $hourminute=`date +%H%M%S`;
         chomp($hourminute);
         if ($hourminute !~ /^000/)
         {
           `kill -9 $PID`;
           `echo "$timedate $TIME $STAT $START $B" >> /var/xdrago/log/git.kill.log`;
         }
      }

      if ($COMMAND =~ /^(\\)/ && $B =~ /^(sh|git)/ && $START =~ /[A-Z]/ && $K =~ /(-c|git|clone)/)
      {
         $timedate=`date +%y%m%d-%H%M%S`;
         chomp($timedate);
         $hourminute=`date +%H%M%S`;
         chomp($hourminute);
         if ($hourminute !~ /^000/)
         {
           `kill -9 $PID`;
           `echo "$timedate $TIME $STAT $START $B" >> /var/xdrago/log/git.kill.log`;
         }
      }

      if ($USER =~ /(tomcat|jetty)/ && $COMMAND =~ /java/ && ($STAT =~ /R/ || $TIME !~ /^[0-5]{1}:/))
      {
        `kill -9 $PID`;
         $timedate=`date +%y%m%d-%H%M%S`;
         chomp($timedate);
        `echo "$timedate $TIME $CPU $MEM $STAT $START $USER" >> /var/xdrago/log/tomcat-jetty-java.kill.log`;
      }

      if ($COMMAND !~ /^(\\)/ && $COMMAND !~ /^(\|)/)
      {
        if ($COMMAND =~ /nginx/) {
          if ($USER =~ /root/) {
            $li_cnt{$COMMAND}++;
          }
        }
        elsif ($COMMAND =~ /sendmail/) {
          if ($USER =~ /root/) {
            `kill $PID`;
          }
        }
        else {
          if ($COMMAND !~ /java/) {
            $li_cnt{$COMMAND}++;
          }
        }
      }
    }
  }
}

#############################################################################
sub cpu_count_load
{
  local($PROCS) = `grep -c processor /proc/cpuinfo`;
  chomp($PROCS);
  $MAXCPU = $PROCS."00";
  if ($PROCS > 2)
  {
    $MAXCPU = 200;
  }
  $MAXCPU = $MAXCPU - 2;
}
###EOF2014###
