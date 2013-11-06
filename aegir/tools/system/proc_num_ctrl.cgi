#!/usr/bin/perl

###
### this is a monitor for this server
###
`/etc/init.d/postfix restart` if (!-f "/var/spool/postfix/pid/master.pid");
`/etc/init.d/redis-server start` if (!-f "/var/run/redis.pid");
&mysqld_action;
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
}
print "\n $sumar ALL procs\t\tGLOBAL";
print "\n $namedsumar Bind procs\t\tGLOBAL" if ($namedlives);
print "\n $buagentsumar Backup procs\t\tGLOBAL" if ($buagentlives);
print "\n $collectdsumar Collectd\t\tGLOBAL" if ($collectdlives);
print "\n $dhcpcdsumar dhcpcd procs\t\tGLOBAL" if ($dhcpcdlives);
print "\n $fpmsumar FPM procs\t\tGLOBAL" if ($fpmlives);
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
`/etc/init.d/bind9 restart` if (!$namedsumar && -f "/etc/init.d/bind9");
if (-e "/usr/sbin/pdnsd" && !$pdnsdsumar) {
  `/etc/init.d/pdnsd stop; rm -f /var/cache/pdnsd/pdnsd.cache; /etc/init.d/pdnsd start`;
  `/etc/init.d/pdnsd stop; rm -f /var/cache/pdnsd/pdnsd.cache; /etc/init.d/pdnsd start`;
}
if ((!$mysqlsumar || $mysqlsumar > 150) && !-f "/var/xdrago/log/mysql_restart_running.pid") {
  `bash /var/xdrago/move_sql.sh`;
}
if (!$redissumar && (-f "/etc/init.d/redis-server" || -f "/etc/init.d/redis")) {
  if (-f "/etc/init.d/redis-server") { `/etc/init.d/redis-server start`; }
  elsif (-f "/etc/init.d/redis") { `/etc/init.d/redis start`; }
}
`/etc/init.d/newrelic-daemon restart` if (!$newrelicdaemonsumar && -f "/etc/init.d/newrelic-daemon");
`/etc/init.d/newrelic-sysmond restart` if (!$newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond");
`/etc/init.d/postfix restart` if (!$postfixsumar && -f "/etc/init.d/postfix");
`killall -9 nginx; /etc/init.d/nginx start` if (!$nginxsumar && -f "/etc/init.d/nginx" && !-f "/var/run/boa_run.pid");
`/etc/init.d/php-fpm restart` if (!$phpsumar && -f "/etc/init.d/php-fpm");
`killall -9 php-fpm; /etc/init.d/php53-fpm start` if ((!$fpmsumar || $fpmsumar > 1 ) && -f "/etc/init.d/php53-fpm");
`/etc/init.d/jetty7 start` if (!$jetty7sumar && -f "/etc/init.d/jetty7");
`/etc/init.d/jetty8 start` if (!$jetty8sumar && -f "/etc/init.d/jetty8");
`/etc/init.d/jetty9 start` if (!$jetty9sumar && -f "/etc/init.d/jetty9");
`/etc/init.d/tomcat start` if (!$tomcatsumar && -f "/etc/init.d/tomcat");
`/etc/init.d/collectd start` if (!$collectdsumar && -f "/etc/init.d/collectd");
if (-f "/usr/local/sbin/pure-config.pl") {
  `/usr/local/sbin/pure-config.pl /usr/local/etc/pure-ftpd.conf` if (!$ftpsumar);
}
if ($mysqlsumar > 0) {
  $resultmysql5 = `mysqladmin flush-hosts 2>&1`;
  print "\n MySQL hosts flushed...\n";
}
if ($dhcpcdlives) {
  $thishostname = `cat /etc/hostname`;
  chomp($thishostname);
  `hostname -v $thishostname`;
}
exit;

#############################################################################
sub global_action
{
  local(@MYARR) = `ps auxf 2>&1`;
  foreach $line (@MYARR) {
    local($USER, $PID, $CPU, $MEM, $VSZ, $RSS, $TTY, $STAT, $START, $TIME, $COMMAND, $B, $K, $X, $Y, $Z, $T) = split(/\s+/,$line);
    $li_cnt{$USER}++ if ($PID ne "PID");

    if (!-f "/var/run/fmp_wait.pid") {
      if ($PID ne "PID" && $USER =~ /www-data/ && $COMMAND =~ /php-fpm/ && $B =~ /pool/ && $K =~ /www/)
      {
        `killall -9 php-fpm; /etc/init.d/php53-fpm start`;
         $timedate=`date +%y%m%d-%H%M`;
         chomp($timedate);
        `echo $timedate >> /var/xdrago/log/php-fpm.kill.log`;
      }
      if ($PID ne "PID" && $USER =~ /root/ && $COMMAND =~ /php-fpm/ && $B =~ /fpm-config/ && $K =~ /php53-fpm/)
      {
        `killall -9 php-fpm; /etc/init.d/php53-fpm start`;
         $timedate=`date +%y%m%d-%H%M`;
         chomp($timedate);
        `echo $timedate >> /var/xdrago/log/php-fpm.kill.log`;
      }
      if ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $STAT =~ /Zs/ && $B =~ /php-fpm/ && $K =~ /defunct/)
      {
        `killall -9 php-fpm; /etc/init.d/php53-fpm start`;
         $timedate=`date +%y%m%d-%H%M`;
         chomp($timedate);
        `echo $timedate >> /var/xdrago/log/php-fpm.kill.log`;
      }
    }

    if ($PID ne "PID" && $COMMAND =~ /^(\|)/ && $B =~ /^(\\)/ && $CPU =~ /[0-9]{2,}./ && $TIME =~ /[1-9]:/ && $K =~ /php/ && $X =~ /drush/ && $Z =~ /cron/ && $Y !~ /(provision|hosting|process|batch|registry)/ && $Z !~ /(provision|hosting|process|batch|registry)/ && $T !~ /(provision|hosting|process|batch|registry)/)
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "A $timedate $TIME $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(\|)/ && $B =~ /^(\\)/ && $TIME =~ /[3-9]:/ && $K =~ /php/ && $X =~ /drush/ && $Z =~ /cron/ && $Y !~ /(provision|hosting|process|batch|registry)/ && $Z !~ /(provision|hosting|process|batch|registry)/ && $T !~ /(provision|hosting|process|batch|registry)/)
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "B $timedate $TIME $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(\|)/ && $B =~ /^(\\)/ && $CPU =~ /[0-9]{2,}./ && $TIME =~ /[0-9]{2,}:/ && $STAT =~ /R/ && $K =~ /php/ && ($X =~ /(drush|-d)/ || $Z =~ /magic/) && $Y !~ /(provision|hosting|process|batch|registry)/ && $Z !~ /(provision|hosting|process|batch|registry)/ && $T !~ /(provision|hosting|process|batch|registry)/)
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "C $timedate $TIME $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
    }

    if ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $TIME =~ /2:/ && $B =~ /php/ && $K =~ /drush/ && $Y =~ /cron/)
    {
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "$timedate $K $TIME $STAT $START $X $Y" >> /var/xdrago/log/php-cli.watch.log`;
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $TIME =~ /[3-9]:/ && $B =~ /php/ && $K =~ /drush/ && $Y =~ /cron/ && $Y !~ /(provision|hosting|process|batch|registry)/ && $Z !~ /(provision|hosting|process|batch|registry)/ && $T !~ /(provision|hosting|process|batch|registry)/)
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "D $timedate $TIME $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $CPU =~ /[0-9]{2,}./ && $TIME =~ /[0-9]{2,}:/ && $STAT =~ /R/ && $B =~ /php/ && ($K =~ /(drush|-d)/ || $X =~ /magic/) && $Y !~ /(provision|hosting|process|batch|registry)/ && $Z !~ /(provision|hosting|process|batch|registry)/ && $T !~ /(provision|hosting|process|batch|registry)/)
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "E $timedate $TIME $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $CPU =~ /[0-9]{2,}./ && $TIME =~ /[1-9]{1,}:/ && $STAT =~ /R/ && $B =~ /php/ && ($K =~ /drush/ || $X =~ /^(dis|en)/) && $Y !~ /(provision|hosting|process|batch|registry)/ && $Z !~ /(provision|hosting|process|batch|registry)/ && $T !~ /(provision|hosting|process|batch|registry)/)
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "F $timedate $TIME $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $START =~ /[A-Z]/ && $B =~ /php/ && $Y !~ /(provision|hosting|process|batch|registry)/ && $Z !~ /(provision|hosting|process|batch|registry)/ && $T !~ /(provision|hosting|process|batch|registry)/)
    {
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
       $hourminute=`date +%H%M`;
       chomp($hourminute);
       if ($hourminute !~ /^000/)
       {
         `kill -9 $PID`;
         `echo "G $timedate $TIME $STAT $START $COMMAND, $B, $K, $X, $Y, $Z, $T" >> /var/xdrago/log/php-cli.kill.log`;
       }
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(sh|git)/ && $START =~ /[A-Z]/ && $B =~ /(-c|git|clone)/)
    {
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
       $hourminute=`date +%H%M`;
       chomp($hourminute);
       if ($hourminute !~ /^000/)
       {
         `kill -9 $PID`;
         `echo "$timedate $TIME $STAT $START $B" >> /var/xdrago/log/git.kill.log`;
       }
    }
    elsif ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $B =~ /^(sh|git)/ && $START =~ /[A-Z]/ && $K =~ /(-c|git|clone)/)
    {
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
       $hourminute=`date +%H%M`;
       chomp($hourminute);
       if ($hourminute !~ /^000/)
       {
         `kill -9 $PID`;
         `echo "$timedate $TIME $STAT $START $B" >> /var/xdrago/log/git.kill.log`;
       }
    }

    if ($PID ne "PID" && $USER =~ /(tomcat|jetty)/ && $COMMAND =~ /java/ && ($STAT =~ /R/ || $TIME !~ /^[0-5]{1}:/))
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "$timedate $TIME $CPU $MEM $STAT $START $USER" >> /var/xdrago/log/tomcat-jetty-java.kill.log`;
    }

    if ($PID ne "PID" && $COMMAND !~ /^(\\)/ && $COMMAND !~ /^(\|)/)
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
        if ($PID ne "PID" && $COMMAND !~ /java/) {
          $li_cnt{$COMMAND}++;
        }
      }
    }
  }
}
#############################################################################
sub mysqld_action
{
  local($PROCS) = `grep -c processor /proc/cpuinfo`;
  chomp($PROCS);
  $MAXCPU = $PROCS."00";
  if ($PROCS > 2)
  {
    $MAXCPU = 200;
  }
  $MAXCPU = $MAXCPU - 2;
  local(@SQLARR) = `top -n 1 | grep mysqld 2>&1`;
  foreach $line (@SQLARR) {
    if ($line !~ /mysqld_safe/)
    {
      local($PID, $USER, $PR, $NI, $VIRT, $RES, $SHR, $S, $CPU, $MEM, $TIME, $COMMAND) = split(/\s+/,$line);
      if (!-f "/var/xdrago/log/mysql_restart_running.pid" && !-f "/var/run/boa_wait.pid") {
        if ($USER =~ /mysql/ && $COMMAND =~ /mysqld/)
        {
          if ($CPU > $MAXCPU)
          {
            `bash /var/xdrago/move_sql.sh`;
            $timedate=`date +%y%m%d-%H%M`;
            chomp($timedate);
            `echo "$timedate $CPU $MAXCPU" >> /var/xdrago/log/mysql.forced.restart.log`;
            print "B LINE is $line";
          }
          else {
            print "C LINE is $line";
          }
        }
      }
    }
  }
}
###EOF2013###
