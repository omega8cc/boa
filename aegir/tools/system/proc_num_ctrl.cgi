#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

###
### System Services Monitor running every 5 seconds
###
if (!-d "/var/run/mysqld") {
  system("mkdir -p /var/run/mysqld");
  system("chown -R mysql:root /var/run/mysqld");
}
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
  if ($COMMAND =~ /sbin\/syslogd/ && -f "/var/run/syslogd.pid") {$sysklogdlives = "YES"; $sysklogdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/syslogd/ && -f "/var/run/syslog.pid") {$syslogdlives = "YES"; $syslogdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /xinetd/) {$xinetdlives = "YES"; $xinetdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /lsyncd/) {$lsyncdlives = "YES"; $lsyncdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sshd/) {$sshdlives = "YES"; $sshdsumar = $li_cnt{$COMMAND};}
}
foreach $X (sort keys %li_cnt) {
  if ($X =~ /php70/) {$php70lives = "YES";}
  if ($X =~ /php56/) {$php56lives = "YES";}
  if ($X =~ /php55/) {$php55lives = "YES";}
  if ($X =~ /php54/) {$php54lives = "YES";}
  if ($X =~ /php53/) {$php53lives = "YES";}
}
foreach $K (sort keys %li_cnt) {
  if ($K =~ /convert/) {$convertlives = "YES"; $convertsumar = $li_cnt{$K};}
}
if ($convertsumar > 1)
{
  &convert_action;
}
print "\n $sumar ALL procs\t\tGLOBAL";
print "\n $namedsumar Bind procs\t\tGLOBAL" if ($namedlives);
print "\n $buagentsumar Backup procs\t\tGLOBAL" if ($buagentlives);
print "\n $collectdsumar Collectd\t\tGLOBAL" if ($collectdlives);
print "\n $dhcpcdsumar dhcpcd procs\t\tGLOBAL" if ($dhcpcdlives);
print "\n $fpmsumar FPM procs\t\tGLOBAL" if ($fpmlives);
print "\n 1 FPM70 procs\t\tGLOBAL" if ($php70lives);
print "\n 1 FPM56 procs\t\tGLOBAL" if ($php56lives);
print "\n 1 FPM55 procs\t\tGLOBAL" if ($php55lives);
print "\n 1 FPM54 procs\t\tGLOBAL" if ($php54lives);
print "\n 1 FPM53 procs\t\tGLOBAL" if ($php53lives);
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
print "\n $rsyslogdsumar Syslog procs\t\tGLOBAL" if ($rsyslogdlives);
print "\n $sysklogdsumar Syslog procs\t\tGLOBAL" if ($sysklogdlives);
print "\n $syslogdsumar Syslog procs\t\tGLOBAL" if ($syslogdlives);
print "\n $convertsumar Convert procs\t\tGLOBAL" if ($convertlives);
print "\n $xinetdsumar Xinetd procs\t\tGLOBAL" if ($xinetdlives);
print "\n $lsyncdsumar Lsyncd procs\t\tGLOBAL" if ($lsyncdlives);
print "\n $sshdsumar SSHd procs\t\tGLOBAL" if ($sshdlives);

system("service bind9 restart") if (!$namedsumar && -f "/etc/init.d/bind9");
system("service ssh restart") if (!$sshdsumar && -f "/etc/init.d/ssh");

if (-e "/usr/sbin/pdnsd" && (!$pdnsdsumar || !-e "/etc/resolvconf/run/interface/lo.pdnsd") && !-f "/var/run/boa_run.pid") {
  system("mkdir -p /var/cache/pdnsd");
  system("chown -R pdnsd:proxy /var/cache/pdnsd");
  system("resolvconf -u");
  system("service pdnsd restart");
  system("pdnsd-ctl empty-cache");
}

if ((!$mysqlsumar || $mysqlsumar > 150) && !-f "/var/run/mysql_restart_running.pid" && !-f "/var/run/boa_run.pid" && !-f "/root/.remote.db.cnf") {
  system("bash /var/xdrago/move_sql.sh");
}

if (-f "/root/.mstr.clstr.cnf" || -f "/root/.wbhd.clstr.cnf") {
  if ($mysqlives && -f "/root/.remote.db.cnf") {
    system("mysql -u root -e \"SET GLOBAL innodb_max_dirty_pages_pct = 0\;\"");
    system("mysql -u root -e \"SET GLOBAL innodb_buffer_pool_dump_at_shutdown = 1\;\"");
    system("mysql -u root -e \"SET GLOBAL innodb_io_capacity = 8000\;\"");
    system("mysql -u root -e \"SET GLOBAL innodb_buffer_pool_dump_pct = 100\;\"");
    system("service mysql stop");
  }
}

if (!-f "/root/.dbhd.clstr.cnf") {
  if (!-d "/var/run/redis") {
    system("mkdir -p /var/run/redis");
    system("chown -R redis:redis /var/run/redis");
  }
  if (!$redissumar && (-f "/etc/init.d/redis-server" || -f "/etc/init.d/redis") && !-f "/var/run/boa_run.pid") {
    if (-f "/etc/init.d/redis-server") { system("service redis-server start"); }
    elsif (-f "/etc/init.d/redis") { system("service redis start"); }
  }
  local(@RSARR)=`grep -e redis_client_socket /data/conf/global.inc`;
  foreach $line (@RSARR) {
    if ($line =~ /redis_client_socket/) {$redissocket = "YES";}
  }
  system("service redis-server restart") if (!-e "/var/run/redis/redis.sock" && $redissocket);
  sleep(2);
  system("service redis-server restart") if (!-f "/var/run/redis/redis.pid");
}

system("service newrelic-daemon restart") if (!$newrelicdaemonsumar && -f "/etc/init.d/newrelic-daemon" && !-f "/var/run/boa_run.pid");
system("service newrelic-sysmond restart") if (!$newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond" && !-f "/var/run/boa_run.pid" && -f "/root/.enable.newrelic.sysmond.cnf");
system("service newrelic-sysmond stop") if ($newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond" && !-f "/root/.enable.newrelic.sysmond.cnf");
system("service postfix restart") if (!$postfixsumar && -f "/etc/init.d/postfix" && !-f "/var/run/boa_run.pid");

if (!$nginxsumar && -f "/etc/init.d/nginx" && !-f "/var/run/boa_run.pid" && !-f "/root/.dbhd.clstr.cnf") {
  system("killall -9 nginx");
  system("service nginx start");
}

if ($nginxsumar) {
  if (-f "/root/.dbhd.clstr.cnf") {
    if (!-f "/root/.mstr.clstr.cnf" && !-f "/root/.wbhd.clstr.cnf") {
      system("killall -9 nginx");
    }
  }
}

if (-f "/root/.dbhd.clstr.cnf") {
  if ($php70lives || $php56lives || $php55lives || $php54lives || $php53lives) {
    system("killall -9 php-fpm");
  }
  if ($redislives) {
    system("killall -9 redis-server");
  }
}
else {
  system("service php70-fpm restart") if ((!$php70lives || !$fpmsumar || $fpmsumar > 5 || !-f "/var/run/php70-fpm.pid") && -f "/etc/init.d/php70-fpm" && !-f "/var/run/boa_run.pid");
  system("service php56-fpm restart") if ((!$php56lives || !$fpmsumar || $fpmsumar > 5 || !-f "/var/run/php56-fpm.pid") && -f "/etc/init.d/php56-fpm" && !-f "/var/run/boa_run.pid");
  system("service php55-fpm restart") if ((!$php55lives || !$fpmsumar || $fpmsumar > 5 || !-f "/var/run/php55-fpm.pid") && -f "/etc/init.d/php55-fpm" && !-f "/var/run/boa_run.pid");
  system("service php54-fpm restart") if ((!$php54lives || !$fpmsumar || $fpmsumar > 5 || !-f "/var/run/php54-fpm.pid") && -f "/etc/init.d/php54-fpm" && !-f "/var/run/boa_run.pid");
  system("service php53-fpm restart") if ((!$php53lives || !$fpmsumar || $fpmsumar > 5 || !-f "/var/run/php53-fpm.pid") && -f "/etc/init.d/php53-fpm" && !-f "/var/run/boa_run.pid");
}

system("service jetty7 start") if (!$jetty7sumar && -f "/etc/init.d/jetty7" && !-f "/var/run/boa_run.pid");
system("service jetty8 start") if (!$jetty8sumar && -f "/etc/init.d/jetty8" && !-f "/var/run/boa_run.pid");
system("service jetty9 start") if (!$jetty9sumar && -f "/etc/init.d/jetty9" && !-f "/var/run/boa_run.pid");
system("service collectd start") if (!$collectdsumar && -f "/etc/init.d/collectd" && !-f "/var/run/boa_run.pid");
system("service xinetd start") if (!$xinetdsumar && -f "/etc/init.d/xinetd" && !-f "/var/run/boa_run.pid");
system("service lsyncd start") if (!$lsyncdsumar && -f "/etc/init.d/lsyncd" && !-f "/var/run/boa_run.pid");
system("service postfix restart") if (!-f "/var/spool/postfix/pid/master.pid");

if (-f "/usr/local/sbin/pure-config.pl") {
  if (-f "/root/.mstr.clstr.cnf" || -f "/root/.wbhd.clstr.cnf" || -f "/root/.dbhd.clstr.cnf") {
    if ($ftpsumar) {
      system("killall -9 pure-ftpd");
    }
  }
  else {
    `/usr/local/sbin/pure-config.pl /usr/local/etc/pure-ftpd.conf` if (!$ftpsumar && !-f "/var/run/boa_run.pid");
  }
}

if ($mysqlsumar > 0 && !-f "/root/.my.cluster_root_pwd.txt") {
 `mysqladmin flush-hosts &> /dev/null`;
  print "\n MySQL hosts flushed...\n";
}
if ($dhcpcdlives) {
  $thishostname=`cat /etc/hostname`;
  chomp($thishostname);
  system("hostname -b $thishostname");
}
if (-f "/etc/init.d/rsyslog") {
  if (!$rsyslogdsumar || !-f "/var/run/rsyslogd.pid") {
    system("killall -9 rsyslogd");
    system("service rsyslog restart");
  }
}
elsif (-f "/etc/init.d/sysklogd") {
  if (!$sysklogdsumar || !-f "/var/run/syslogd.pid") {
    system("killall -9 sysklogd");
    system("service sysklogd restart");
  }
}
elsif (-f "/etc/init.d/inetutils-syslogd") {
  if (!$syslogdsumar || !-f "/var/run/syslog.pid") {
    system("killall -9 syslogd");
    system("service inetutils-syslogd restart");
  }
}
exit;

#############################################################################
sub global_action
{
  local(@MYARR)=`ps auxf 2>&1`;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,\?\=\|\\\+]//g;
    local($USER, $PID, $CPU, $MEM, $VSZ, $RSS, $TTY, $STAT, $START, ${TIME}, $COMMAND, $B, $K, $X, $Y, $Z, $T) = split(/\s+/,$line);
    $PID =~ s/[^0-9]//g;
    $li_cnt{$USER}++ if ($PID);
    $li_cnt{$X}++ if ($PID && $COMMAND =~ /php-fpm/ && $X =~ /php/);
    $li_cnt{$K}++ if ($PID && $COMMAND =~ /^(\|)/ && $K =~ /convert/);
    local($fpm_result) = "CTRL";

    if ($PID)
    {
      local($HOUR, $MIN) = split(/:/,${TIME});
      $MIN =~ s/^0//g;

      if ($COMMAND =~ /^(\\)/ && $START =~ /[A-Z]/ && $B =~ /php/ && $B !~ /php-fpm/)
      {
        $timedate=`date +%y%m%d-%H%M`;
        chomp($timedate);
        $hourminute=`date +%H%M`;
        chomp($hourminute);
        if ($hourminute !~ /^000/)
        {
          system("kill -9 $PID");
         `echo "G $timedate ${TIME} $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
        }
      }

      if ($COMMAND =~ /^(\\)/ && $B =~ /mysqld/ && $CPU > 10 && $USER =~ /mysql/)
      {
        $timedate=`date +%y%m%d-%H%M%S`;
        chomp($timedate);
        if ($CPU > $MAXSQLCPU && $HOUR > 1 && ($STAT =~ /R/ || $STAT =~ /Z/))
        {
          if (!-f "/var/run/mysql_restart_running.pid" && !-f "/var/run/boa_run.pid" && !-e "/root/.no.sql.cpu.limit.cnf") {
            system("bash /var/xdrago/move_sql.sh");
            $timedate=`date +%y%m%d-%H%M%S`;
            chomp($timedate);
           `echo "$USER CPU:$CPU MAXSQLCPU:$MAXSQLCPU $STAT START:$START TIME:${TIME} $timedate" >> /var/xdrago/log/mysql.forced.restart.log`;
          }
        }
        if ($CPU > 50 && !-f "/var/run/boa_sql_backup.pid") {
         `echo "$USER CPU:$CPU MAXSQLCPU:$MAXSQLCPU $STAT START:$START TIME:${TIME} $timedate" >> /var/xdrago/log/mysql.watch.log`;
        }
      }

      if ($COMMAND =~ /^(\\)/ && $B =~ /php-fpm/ && $K =~ /pool/ && $CPU > 100 && ($STAT =~ /R/ || $STAT =~ /Z/) && $USER !~ /root/)
      {
        if ($HOUR > "0" || $MIN > 9)
        {
          $timedate=`date +%y%m%d-%H%M%S`;
          chomp($timedate);
          if ($CPU > $MAXFPMCPU)
          {
            if (!-e "/root/.no.fpm.cpu.limit.cnf") {
              system("kill -9 $PID");
             `echo "$X CPU:$CPU MAXFPMCPU:$MAXFPMCPU $STAT START:$START TIME:${TIME} $timedate" >> /var/xdrago/log/php-fpm.kill.log`;
              $fpm_result = "KILLED";
            }
          }
         `echo "$X CPU:$CPU $STAT START:$START TIME:${TIME} $timedate $fpm_result" >> /var/xdrago/log/php-fpm.watch.log`;
        }
      }

      if ($COMMAND =~ /^(sh|git)/ && $START =~ /[A-Z]/ && $B =~ /(-c|git|clone)/)
      {
         $timedate=`date +%y%m%d-%H%M%S`;
         chomp($timedate);
         $hourminute=`date +%H%M%S`;
         chomp($hourminute);
         if ($hourminute !~ /^000/)
         {
            system("kill -9 $PID");
           `echo "$timedate ${TIME} $STAT $START $B" >> /var/xdrago/log/git.kill.log`;
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
            system("kill -9 $PID");
           `echo "$timedate ${TIME} $STAT $START $B" >> /var/xdrago/log/git.kill.log`;
         }
      }

      if ($USER =~ /jetty/ && $COMMAND =~ /java/ && $STAT =~ /R/)
      {
         system("kill -9 $PID");
         $timedate=`date +%y%m%d-%H%M%S`;
         chomp($timedate);
        `echo "$timedate ${TIME} $CPU $MEM $STAT $START $USER" >> /var/xdrago/log/jetty-java.kill.log`;
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
            system("kill -9 $PID");
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
sub convert_action
{
  local(@MYARR)=`ps auxf 2>&1`;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,\?\=\|\\\+]//g;
    local($USER, $PID, $CPU, $MEM, $VSZ, $RSS, $TTY, $STAT, $START, ${TIME}, $COMMAND, $B, $K, $X, $Y, $Z, $T) = split(/\s+/,$line);
    $PID =~ s/[^0-9]//g;
    if ($PID)
    {
      local($HOUR, $MIN) = split(/:/,${TIME});
      $MIN =~ s/^0//g;
      if ($COMMAND =~ /^(\|)/ && $K =~ /convert/ && $CPU > 10 && $MIN > 1 && ($STAT =~ /R/ || $STAT =~ /Z/))
      {
        $timedate=`date +%y%m%d-%H%M%S`;
        chomp($timedate);
        if ($convertsumar > 5 && $CPU > 50) {
          system("kill -9 $PID");
         `echo "$USER $CPU $STAT $START ${TIME} $timedate KILL Q $convertsumar" >> /var/xdrago/log/convert.kill.log`;
          $kill_convert = "YES";
        }
        else {
         `echo "$USER $CPU $STAT $START ${TIME} $timedate WATCH $convertsumar" >> /var/xdrago/log/convert.watch.log`;
        }
      }

      if ($kill_convert && $COMMAND =~ /^(\|)/ && $K =~ /bin/ && $Y =~ /convert/)
      {
        system("kill -9 $PID");
       `echo "$USER $CPU $STAT $START ${TIME} $timedate KILL Z $convertsumar" >> /var/xdrago/log/convert.kill.log`;
      }
    }
  }
}

#############################################################################
sub cpu_count_load
{
  local($PROCS)=`grep -c processor /proc/cpuinfo`;
  chomp($PROCS);
  $MAXSQLCPU = $PROCS."00";
  $MAXFPMCPU = $PROCS."00";
  if ($PROCS > 2)
  {
    $MAXSQLCPU = 200;
  }
  $MAXSQLCPU = $MAXSQLCPU - 5;
  $MAXFPMCPU = $MAXFPMCPU - 5;
}
###EOF2017###
