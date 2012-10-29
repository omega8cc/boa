#!/usr/bin/perl

###
### this is a monitor for this server
###
`/etc/init.d/postfix restart` if (!-f "/var/spool/postfix/pid/master.pid");
`/etc/init.d/redis-server start` if (!-f "/var/run/redis.pid");
&global_action;
foreach $USER (sort keys %li_cnt) {
  print " $li_cnt{$USER}\t$USER\n";
  push(@donetable," $li_cnt{$USER}\t$USER");
  $sumar = $sumar + $li_cnt{$USER};
  if ($USER eq "mysql") {$mysqlives = "YES"; $mysqlsumar = $li_cnt{$USER};}
}
foreach $COMMAND (sort keys %li_cnt) {
  if ($COMMAND =~ /buagent/) {$buagentlives = "YES"; $buagentsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /collectd/) {$collectdlives = "YES"; $collectdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /dhcpcd-bin/) {$dhcpcdlives = "YES"; $dhcpcdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /java/) {$tomcatlives = "YES"; $tomcatsumar = $li_cnt{$COMMAND};}
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
print "\n $tomcatsumar Tomcat procs\t\tGLOBAL" if ($tomcatlives);
if (-e "/usr/sbin/pdnsd" && !$pdnsdsumar) {
  `/etc/init.d/pdnsd stop; rm -f /var/cache/pdnsd/pdnsd.cache; /etc/init.d/pdnsd start`;
  `/etc/init.d/pdnsd stop; rm -f /var/cache/pdnsd/pdnsd.cache; /etc/init.d/pdnsd start`;
}
if (!$mysqlsumar || $mysqlsumar > 150) {
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
`/etc/init.d/tomcat start` if (!$tomcatsumar && -f "/etc/init.d/tomcat");
`/etc/init.d/collectd start` if (!$collectdsumar && -f "/etc/init.d/collectd");
if (-f "/usr/local/sbin/pure-config.pl") {
  `/usr/local/sbin/pure-config.pl /usr/local/etc/pure-ftpd.conf` if (!$ftpsumar);
}
if ($mysqlsumar > 0) {
  $resultmysql5 = `/usr/bin/mysqladmin flush-hosts 2>&1`;
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
    local($USER, $PID, $CPU, $MEM, $VSZ, $RSS, $TTY, $STAT, $START, $TIME, $COMMAND, $B, $K, $X, $Y, $Z) = split(/\s+/,$line);
    $li_cnt{$USER}++ if ($PID ne "PID");
    if ($PID ne "PID" && $USER =~ /root/ && $COMMAND =~ /(php-fpm)/ && $B =~ /(fpm-config)/ && $K =~ /(php53-fpm)/)
    {
      `killall -9 php-fpm; /etc/init.d/php53-fpm start`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo $timedate >> /var/xdrago/log/php-fpm.kill.log`;
    }
    if ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $STAT =~ /(Zs)/ && $B =~ /(php-fpm)/ && $K =~ /(defunct)/)
    {
      `killall -9 php-fpm; /etc/init.d/php53-fpm start`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo $timedate >> /var/xdrago/log/php-fpm.kill.log`;
    }
    if ($PID ne "PID" && $COMMAND =~ /^(\\)/ && $TIME !~ /(0:)/ && $B =~ /(php)/ && $K =~ /(drush)/ && $Y =~ /(cron)/)
    {
      `kill -9 $PID`;
       $timedate=`date +%y%m%d-%H%M`;
       chomp($timedate);
      `echo "$timedate $K $TIME $STAT $X $Y" >> /var/xdrago/log/php-cli.kill.log`;
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
        $li_cnt{$COMMAND}++;
      }
    }
  }
}
###EOF2012###
