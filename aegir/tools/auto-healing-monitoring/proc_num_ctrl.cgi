#!/usr/bin/perl

###
### this is a monitor for this server
###
`/etc/init.d/nginx start` if (!-f "/var/run/nginx.pid");
`/etc/init.d/php-fpm start` if (!-f "/var/run/php-fpm.pid");
`/etc/init.d/postfix restart` if (!-f "/var/spool/postfix/pid/master.pid");
&global_action;
foreach $USER (sort keys %li_cnt) {
print " $li_cnt{$USER}\t$USER\n";
push(@donetable," $li_cnt{$USER}\t$USER");
$sumar = $sumar + $li_cnt{$USER};
if ($USER eq "www-data") {$apachelives = "YES"; $wwwsumar = $li_cnt{$USER}}
elsif ($USER eq "mysql") {$mysqlives = "YES"; $mysqlsumar = $li_cnt{$USER};}
}
foreach $COMMAND (sort keys %li_cnt) {
if ($COMMAND =~ /memcache/) {$memcachelives = "YES"; $memcachesumar = $li_cnt{$COMMAND};}
if ($COMMAND =~ /redis/) {$redislives = "YES"; $redissumar = $li_cnt{$COMMAND};}
if ($COMMAND =~ /java/) {$tomcatlives = "YES"; $tomcatsumar = $li_cnt{$COMMAND};}
}
print "\n $sumar ALL procs\tGLOBAL";
print "\n $tomcatsumar Tomcat procs\tGLOBAL";
print "\n $memcachesumar Cache procs\tGLOBAL";
print "\n $redissumar Redis procs\tGLOBAL";
print "\n $mysqlsumar MySQL procs\tGLOBAL\n\n\n";
`/var/xdrago/memcache.sh` if (!$memcachesumar || $memcachesumar < 8);
`/etc/init.d/redis-server start` if (!$redissumar);
`/var/xdrago/move_sql` if (!$mysqlsumar || $mysqlsumar > 150 || $mysqlsumar < 1);
`/etc/init.d/tomcat start` if (!$tomcatsumar);
$host=`hostname`;
chomp($host);
$thispid = $host . ".pid";
`/var/xdrago/move_sql` if (!-f "/var/run/mysqld/mysqld.pid");
if ($mysqlsumar > 0) {
$resultmysql5 = `/usr/bin/mysqladmin -u root --password=NdKBu34erty325r6mUHxWy -h localhost --port=3306 flush-hosts 2>&1`;
print "\n MySQL hosts flushed...\n";
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
