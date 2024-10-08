#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

use warnings;
use File::Spec;

$| = 1;
if (-f "/run/boa_wait.pid") {exit;}
if (-f "/run/fmp_wait.pid") {exit;}
$fpm_status="CLEAN";
$java_status="CLEAN";
$now_is=`date +%b:%d:%H:%M`;
chomp($now_is);
&fpmcheck;
&javacheck;
if ($fpm_status ne "CLEAN") {
  `kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}')`;
  system("touch /run/fmp_wait.pid");
  if (-f "/etc/init.d/php83-fpm") {
    `service php83-fpm restart`;
  }
  if (-f "/etc/init.d/php82-fpm") {
    `service php82-fpm restart`;
  }
  if (-f "/etc/init.d/php81-fpm") {
    `service php81-fpm restart`;
  }
  if (-f "/etc/init.d/php80-fpm") {
    `service php80-fpm restart`;
  }
  if (-f "/etc/init.d/php74-fpm") {
    `service php74-fpm restart`;
  }
  if (-f "/etc/init.d/php73-fpm") {
    `service php73-fpm restart`;
  }
  if (-f "/etc/init.d/php72-fpm") {
    `service php72-fpm restart`;
  }
  if (-f "/etc/init.d/php71-fpm") {
    `service php71-fpm restart`;
  }
  if (-f "/etc/init.d/php70-fpm") {
    `service php70-fpm restart`;
  }
  if (-f "/etc/init.d/php56-fpm") {
    `service php56-fpm restart`;
  }
  if (-f "/etc/init.d/php55-fpm") {
    `service php55-fpm stop`;
  }
  if (-f "/etc/init.d/php54-fpm") {
    `service php54-fpm stop`;
  }
  if (-f "/etc/init.d/php53-fpm") {
    `service php53-fpm stop`;
  }
  sleep(2);
  system("rm -f /run/fmp_wait.pid");
}
if ($java_status ne "CLEAN") {
  `kill -9 $(ps aux | grep '[j]etty' | awk '{print $2}')`;
  sleep(2);
  if (-f "/etc/default/jetty9" && -f "/etc/init.d/jetty9") {
    `service jetty9 start`;
  }
  if (-f "/etc/default/jetty8" && -f "/etc/init.d/jetty8") {
    `service jetty8 start`;
  }
  if (-f "/etc/default/jetty7" && -f "/etc/init.d/jetty7") {
    `service jetty7 start`;
  }
}
`touch /var/xdrago/log/last-run-locked.pid`;
exit;

#############################################################################
sub fpmcheck
{
local(@MYARR)=`grep " 499 0 " /var/log/nginx/access.log | tail --lines=999 2>&1`;
local($sumar,$maxnumber);
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;
    if ($line =~ /( 499 0 )/i) {
      local($a, $DATESTAMPX) = split(/\[/,$line);
      chomp($DATESTAMPX);
      local($DATESTAMP, $b) = split(/\s+/,$DATESTAMPX);
      chomp($DATESTAMP);
      chomp($line);
      $DATESTAMP =~ s/[^A-Za-z0-9\:\/]//g; ### 28/Oct/2012:16:07:11
      local($DAYX, $MONTX, $TIMEX) = split(/\//,$DATESTAMP);
      if ($DAYX =~ /^\s+/) {
        $DAYX =~ s/[^0-9]//g;
      }
      if ($DAYX !~ /^0/ && $DAYX !~ /[0-9]{2}/) {
        $DAYX = "0$DAYX";
      }
      chomp($TIMEX);
      $TIMEX =~ s/[^0-9\:]//g;
      if ($TIMEX =~ /^[0-9]/) {
        local($YEAR, $HOUR, $MIN, $SEC) = split(/:/,$TIMEX);
        $log_is="$MONTX:$DAYX:$HOUR:$MIN";
        local($DROP) = "$MIN";
        if ($now_is eq $log_is) {
          $li_cnt{$DROP}++;
          print "===NEW:[$now_is]:[$log_is]:$line===\n";
          `echo "[$now_is]:[$log_is]:$line" >> /var/xdrago/log/last-fpmcheck-y-problem.log`;
        }
        else {
          print "===OLD:[$now_is]:[$log_is]:$line===\n";
        }
      }
    }
  }
  foreach $DROP (sort keys %li_cnt) {
    $sumar = $sumar + $li_cnt{$DROP};
    local($thissumar) = $li_cnt{$DROP};
    $maxnumber = 8;
    if ($thissumar > $maxnumber) {
      $fpm_status="ERROR";
    }
  }
  undef (%li_cnt);
}
sub javacheck
{
local(@MYARR)=`grep "Apache Solr" /var/log/syslog | tail --lines=999 2>&1`;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;
    if ($line =~ /(timed out)/i || $line =~ /(Communication Error)/i) {
      local($MONTX, $DAYX, $TIMEX, $rest) = split(/\s+/,$line);
      if ($DAYX =~ /^\s+/) {
        $DAYX =~ s/[^0-9]//g;
      }
      if ($DAYX !~ /^0/ && $DAYX !~ /[0-9]{2}/) {
        $DAYX = "0$DAYX";
      }
      chomp($line);
      chomp($TIMEX);
      $TIMEX =~ s/[^0-9\:]//g;
      if ($TIMEX =~ /^[0-9]/) {
        local($HOUR, $MIN, $SEC) = split(/:/,$TIMEX);
        $log_is="$MONTX:$DAYX:$HOUR:$MIN";
        if ($now_is eq $log_is) {
          $java_status="ERROR";
          print "===NEW:[$now_is]:[$log_is]:$line===\n";
          `echo "[$now_is]:[$log_is]:$line" >> /var/xdrago/log/last-javacheck-y-problem`;
        }
        else {
          print "===OLD:[$now_is]:[$log_is]:$line===\n";
        }
      }
    }
  }
}
###EOF2024###
