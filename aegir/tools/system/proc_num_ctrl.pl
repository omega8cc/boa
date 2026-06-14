#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

use warnings;
use File::Spec;

my $run_to_files = [ "/root/.run-to-excalibur.cnf", "/root/.run-to-daedalus.cnf", "/root/.run-to-chimaera.cnf", "/root/.run-to-beowulf.cnf", "/run/boa_run.pid" ];

###
### System Services Monitor running every 5 seconds
###
&cpu_count_load;
&global_action;
$sumar = 0;
foreach $USER (sort keys %li_cnt) {
  print " $li_cnt{$USER}\t$USER\n";
  $sumar = $sumar + $li_cnt{$USER};
  if ($USER eq "mysql") {$mysqlives = "YES"; $mysqlsumar = $li_cnt{$USER};}
  if ($USER eq "jetty9") {$jetty9lives = "YES"; $jetty9sumar = $li_cnt{$USER};}
  if ($USER eq "solr7") {$solr7lives = "YES"; $solr7sumar = $li_cnt{$USER};}
  if ($USER eq "solr9") {$solr9lives = "YES"; $solr9sumar = $li_cnt{$USER};}
}
foreach $COMMAND (sort keys %li_cnt) {
  if ($COMMAND =~ /lfd/) {$lfdlives = "YES"; $lfdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /named/) {$namedlives = "YES"; $namedsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/clamd/) {$clamdlives = "YES"; $clamdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /bin\/freshclam/) {$freshclamlives = "YES"; $freshclamsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /buagent/) {$buagentlives = "YES"; $buagentsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /collectd/) {$collectdlives = "YES"; $collectdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /dhclient/) {$dhclientlives = "YES"; $dhclientsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /dhcpcd/) {$dhcpcdlives = "YES"; $dhcpcdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /nginx:/) {$nginxlives = "YES"; $nginxsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/unbound/) {$unboundlives = "YES"; $unboundsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/vnstatd/) {$vnstatdlives = "YES"; $vnstatdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /php-cgi/) {$phplives = "YES"; $phpsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /php-fpm:/) {$fpmlives = "YES"; $fpmsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /lib\/postfix/) {$postfixlives = "YES"; $postfixsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /pure-ftpd/) {$ftplives = "YES"; $ftpsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /java\/jenkins/) {$jenkinslives = "YES"; $jenkinssumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /bin\/valkey-server/) {$valkeylives = "YES"; $valkeysumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /bin\/redis-server/) {$redislives = "YES"; $redissumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /bin\/newrelic-daemon/) {$newrelicdaemonlives = "YES"; $newrelicdaemonsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /nrsysmond/) {$newrelicsysmondlives = "YES"; $newrelicsysmondsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/rsyslogd/) {$rsyslogdlives = "YES"; $rsyslogdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/syslogd/ && -f "/run/syslogd.pid") {$sysklogdlives = "YES"; $sysklogdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sbin\/syslogd/ && -f "/run/syslog.pid") {$syslogdlives = "YES"; $syslogdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /xinetd/) {$xinetdlives = "YES"; $xinetdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /lsyncd/) {$lsyncdlives = "YES"; $lsyncdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /sshd:/) {$sshdlives = "YES"; $sshdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /proxysql/) {$pxydlives = "YES"; $pxydsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /droplet/) {$dpltlives = "YES"; $dpltsumar = $li_cnt{$COMMAND};}
}
foreach $X (sort keys %li_cnt) {
  if ($X =~ /php85/) {$php85lives = "YES";}
  if ($X =~ /php84/) {$php84lives = "YES";}
  if ($X =~ /php83/) {$php83lives = "YES";}
  if ($X =~ /php82/) {$php82lives = "YES";}
  if ($X =~ /php81/) {$php81lives = "YES";}
  if ($X =~ /php80/) {$php80lives = "YES";}
  if ($X =~ /php74/) {$php74lives = "YES";}
  if ($X =~ /php73/) {$php73lives = "YES";}
  if ($X =~ /php72/) {$php72lives = "YES";}
  if ($X =~ /php71/) {$php71lives = "YES";}
  if ($X =~ /php70/) {$php70lives = "YES";}
  if ($X =~ /php56/) {$php56lives = "YES";}
}
$convertsumar = 0;
foreach $K (sort keys %li_cnt) {
  if ($K =~ /convert/) {$convertlives = "YES"; $convertsumar = $li_cnt{$K};}
}
if ($convertsumar > 1)
{
  &convert_action;
}
print "\n $sumar ALL procs\t\tGLOBAL";
print "\n $lfdsumar LFD procs\t\tGLOBAL" if ($lfdlives && -f "/etc/init.d/lfd");
print "\n $namedsumar Bind procs\t\tGLOBAL" if ($namedlives);
print "\n $clamdsumar Clamd procs\t\tGLOBAL" if ($clamdlives);
print "\n $freshclamsumar Freshclam\t\tGLOBAL" if ($freshclamlives);
print "\n $buagentsumar Backup procs\t\tGLOBAL" if ($buagentlives);
print "\n $collectdsumar Collectd\t\tGLOBAL" if ($collectdlives);
print "\n $dhclientsumar DHCP procs\t\tGLOBAL" if ($dhclientlives);
print "\n $dhcpcdsumar DHCP procs\t\tGLOBAL" if ($dhcpcdlives);
print "\n $fpmsumar FPM procs\t\tGLOBAL" if ($fpmlives);
print "\n 1 FPM85 procs\t\tGLOBAL" if ($php85lives);
print "\n 1 FPM84 procs\t\tGLOBAL" if ($php84lives);
print "\n 1 FPM83 procs\t\tGLOBAL" if ($php83lives);
print "\n 1 FPM82 procs\t\tGLOBAL" if ($php82lives);
print "\n 1 FPM81 procs\t\tGLOBAL" if ($php81lives);
print "\n 1 FPM80 procs\t\tGLOBAL" if ($php80lives);
print "\n 1 FPM74 procs\t\tGLOBAL" if ($php74lives);
print "\n 1 FPM73 procs\t\tGLOBAL" if ($php73lives);
print "\n 1 FPM72 procs\t\tGLOBAL" if ($php72lives);
print "\n 1 FPM71 procs\t\tGLOBAL" if ($php71lives);
print "\n 1 FPM70 procs\t\tGLOBAL" if ($php70lives);
print "\n 1 FPM56 procs\t\tGLOBAL" if ($php56lives);
print "\n $ftpsumar FTP procs\t\tGLOBAL" if ($ftplives);
print "\n $mysqlsumar MySQL procs\t\tGLOBAL" if ($mysqlives);
print "\n $nginxsumar Nginx procs\t\tGLOBAL" if ($nginxlives);
print "\n $unboundsumar DNS procs\t\tGLOBAL" if ($unboundlives);
print "\n $vnstatdsumar Vnstat procs\t\tGLOBAL" if ($vnstatdlives);
print "\n $phpsumar PHP procs\t\tGLOBAL" if ($phplives);
print "\n $postfixsumar Postfix procs\tGLOBAL" if ($postfixlives);
print "\n $valkeysumar Valkey procs\t\tGLOBAL" if ($valkeylives);
print "\n $redissumar Redis procs\t\tGLOBAL" if ($redislives);
print "\n $newrelicdaemonsumar New Relic Apps\tGLOBAL" if ($newrelicdaemonlives);
print "\n $newrelicsysmondsumar New Relic Server\tGLOBAL" if ($newrelicsysmondlives);
print "\n $jetty9sumar Jetty9 procs\t\tGLOBAL" if ($jetty9lives);
print "\n $solr7sumar Solr7 procs\t\tGLOBAL" if ($solr7lives);
print "\n $solr9sumar Solr9 procs\t\tGLOBAL" if ($solr9lives);
print "\n $jenkinssumar Jenkins procs\t\tGLOBAL" if ($jenkinslives);
print "\n $rsyslogdsumar Syslog procs\t\tGLOBAL" if ($rsyslogdlives);
print "\n $sysklogdsumar Syslog procs\t\tGLOBAL" if ($sysklogdlives);
print "\n $syslogdsumar Syslog procs\t\tGLOBAL" if ($syslogdlives);
print "\n $convertsumar Convert procs\t\tGLOBAL" if ($convertlives);
print "\n $xinetdsumar Xinetd procs\t\tGLOBAL" if ($xinetdlives);
print "\n $lsyncdsumar Lsyncd procs\t\tGLOBAL" if ($lsyncdlives);
print "\n $sshdsumar SSHd procs\t\tGLOBAL" if ($sshdlives);
print "\n $pxydsumar PxySQL procs\t\tGLOBAL" if ($pxydlives);
print "\n $dpltsumar Droplet procs\tGLOBAL" if ($dpltlives);
print "\n";

if (!any_file_exists($run_to_files)) {
  system("service bind9 restart") if (!$namedsumar && -f "/etc/init.d/bind9");
  system("service proxysql restart") if (!$pxydsumar && -f "/etc/init.d/proxysql");
  system("service droplet-agent restart") if (!$dpltsumar && -f "/etc/init.d/droplet-agent");
  system("service droplet-agent restart") if (!-f "/run/droplet-agent.pid" && -f "/etc/init.d/droplet-agent");
}

if (!any_file_exists($run_to_files)) {
  system("service newrelic-daemon restart") if (!$newrelicdaemonsumar && -f "/etc/init.d/newrelic-daemon");
  system("service newrelic-sysmond restart") if (!$newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond" && -f "/etc/boa/.enable.newrelic.sysmond.cnf");
  system("service newrelic-sysmond stop") if ($newrelicsysmondsumar && -f "/etc/init.d/newrelic-sysmond" && !-f "/etc/boa/.enable.newrelic.sysmond.cnf");
}

if (!any_file_exists($run_to_files)) {
  system("service collectd start") if (!$collectdsumar && -f "/etc/init.d/collectd");
  system("service xinetd start") if (!$xinetdsumar && -f "/etc/init.d/xinetd");
  system("service lsyncd start") if (!$lsyncdsumar && -f "/etc/init.d/lsyncd");
}

if ($dhcpcdlives || $dhclientlives) {
  chomp(my $wanted = `cat /etc/hostname`);
  chomp(my $current = `hostname`);
  if ($current ne $wanted) {
    system("hostname", "-b", $wanted);
  }
}
elsif (-f "/etc/init.d/sysklogd") {
  if (!$sysklogdsumar || !-f "/run/syslogd.pid") {
    system("killall -9 sysklogd");
    system("service sysklogd restart");
  }
}
elsif (-f "/etc/init.d/inetutils-syslogd") {
  if (!$syslogdsumar || !-f "/run/syslog.pid") {
    system("killall -9 syslogd");
    system("service inetutils-syslogd restart");
  }
}

sub any_file_exists {
  my ($files) = @_;
  for my $file (@$files) {
    return 1 if -f $file;
  }
  return 0;
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

    if ($PID)
    {
      local($HOUR, $MIN) = split(/:/,${TIME});
      $MIN =~ s/^0//g;
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
         `echo "$USER $CPU $STAT $START ${TIME} $timedate KILL Q $convertsumar" >> /var/log/boa/convert.kill.log`;
          $kill_convert = "YES";
        }
        else {
         `echo "$USER $CPU $STAT $START ${TIME} $timedate WATCH $convertsumar" >> /var/log/boa/convert.watch.log`;
        }
      }

      if ($kill_convert && $COMMAND =~ /^(\|)/ && $K =~ /bin/ && $Y =~ /convert/)
      {
        system("kill -9 $PID");
       `echo "$USER $CPU $STAT $START ${TIME} $timedate KILL Z $convertsumar" >> /var/log/boa/convert.kill.log`;
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
    $MAXSQLCPU = 600;
  }
  $MAXSQLCPU = $MAXSQLCPU - 5;
  $MAXFPMCPU = $MAXFPMCPU - 5;
}

