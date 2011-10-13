#!/usr/bin/perl

###
### this is a monitor for this server
###
`/etc/init.d/postfix restart` if (!-f "/var/spool/postfix/pid/master.pid");
&global_action;
foreach $USER (sort keys %li_cnt) {
  print " $li_cnt{$USER}\t$USER\n";
  push(@donetable," $li_cnt{$USER}\t$USER");
  $sumar = $sumar + $li_cnt{$USER};
  if ($USER eq "mysql") {$mysqlives = "YES"; $mysqlsumar = $li_cnt{$USER};}
}
foreach $COMMAND (sort keys %li_cnt) {
  if ($COMMAND =~ /nginx/) {$nginxlives = "YES"; $nginxsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /php-cgi/) {$phplives = "YES"; $phpsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /memcache/) {$memcachelives = "YES"; $memcachesumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /redis/) {$redislives = "YES"; $redissumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /java/) {$tomcatlives = "YES"; $tomcatsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /pure-ftpd/) {$ftplives = "YES"; $ftpsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /pdnsd/) {$pdnsdlives = "YES"; $pdnsdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /buagent/) {$buagentlives = "YES"; $buagentsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /dhcpcd-bin/) {$dhcpcdlives = "YES"; $dhcpcdsumar = $li_cnt{$COMMAND};}
  if ($COMMAND =~ /collectd/) {$collectdlives = "YES"; $collectdsumar = $li_cnt{$COMMAND};}
}
print "\n $sumar ALL procs\tGLOBAL";
print "\n $pdnsdsumar DNS procs\tGLOBAL" if ($pdnsdlives);
print "\n $mysqlsumar MySQL procs\tGLOBAL" if ($mysqlives);
print "\n $nginxsumar Nginx procs\tGLOBAL" if ($nginxlives);
print "\n $phpsumar PHP procs\tGLOBAL" if ($phplives);
print "\n $tomcatsumar Tomcat procs\tGLOBAL" if ($tomcatlives);
print "\n $memcachesumar Cache procs\tGLOBAL" if ($memcachelives);
print "\n $redissumar Redis procs\tGLOBAL" if ($redislives);
print "\n $ftpsumar FTP procs\tGLOBAL" if ($ftplives);
print "\n $buagentsumar Backup procs\tGLOBAL" if ($buagentlives);
print "\n $dhcpcdsumar dhcpcd procs\tGLOBAL" if ($dhcpcdlives);
print "\n $collectdsumar collectd procs\tGLOBAL" if ($collectdlives);
if (-e "/usr/sbin/pdnsd") {
  `/etc/init.d/pdnsd restart` if (!$pdnsdsumar);
}
if (!$mysqlsumar || $mysqlsumar > 150) {
  `bash /var/xdrago/move_sql.sh`;
}
if (-f "/var/xdrago/memcache.sh") {
  `/var/xdrago/memcache.sh` if (!$memcachesumar || $memcachesumar < 8);
}
if (!$redissumar && (-f "/etc/init.d/redis-server" || -f "/etc/init.d/redis")) {
  if (-f "/etc/init.d/redis-server") { `/etc/init.d/redis-server start`; }
  elsif (-f "/etc/init.d/redis") { `/etc/init.d/redis start`; }
}
`killall -9 nginx` if ($nginxsumar > 1 && -f "/etc/init.d/nginx");
`/etc/init.d/nginx restart` if (!$nginxsumar && -f "/etc/init.d/nginx");
`/etc/init.d/php-fpm restart` if (!$phpsumar && -f "/etc/init.d/php-fpm");
`/etc/init.d/tomcat start` if (!$tomcatsumar && -f "/etc/init.d/tomcat");
`/etc/init.d/collectd start` if (!$collectdsumar && -f "/etc/init.d/collectd");
if (-f "/usr/local/sbin/pure-config.pl") {
  `/usr/local/sbin/pure-config.pl /usr/local/etc/pure-ftpd.conf` if (!$ftpsumar);
}
if ($mysqlsumar > 0) {
  $resultmysql5 = `/usr/bin/mysqladmin -u root --password=NdKBu34erty325r6mUHxWy -h localhost --port=3306 flush-hosts 2>&1`;
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
   local(@SYTUACJA) = `ps auxf 2>&1`;
   foreach $line (@SYTUACJA) {
   local($USER, $PID, $CPU, $MEM, $VSZ, $RSS, $TTY, $STAT, $START, $TIME, $COMMAND) = split(/\s+/,$line);
         $li_cnt{$USER}++ if ($PID ne "PID");
	 if ($PID ne "PID" && $COMMAND !~ /^(\\)/ && $COMMAND !~ /^(\|)/)
	 {
	   $li_cnt{$COMMAND}++;
	 }
   }
}

###EOF###
