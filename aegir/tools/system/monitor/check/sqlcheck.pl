#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

use warnings;
use File::Spec;

$| = 1;
if (-f "/run/boa_wait.pid") {exit;}
$status="CLEAN";
$now_is=`date +%b:%d:%H:%M`;
chomp($now_is);
&makeactions;
if ($status ne "CLEAN") {
  `perl /var/xdrago/checksql.pl`;
}
else {
  `touch /var/xdrago/log/last-sqlcheck-clean`;
}
exit;

#############################################################################
sub makeactions
{
local(@MYARR)=`grep mysql /var/log/syslog | tail --lines=999 2>&1`;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;
    if ($line =~ /(Checking table)/i || $line =~ /(is marked as crashed)/i) {
      local($MONTX, $DAYX, $TIMEX, $rest) = split(/\s+/,$line);
      if ($DAYX =~ /^\s+/) {
        $DAYX =~ s/[^0-9]//g;
      }
      if ($DAYX !~ /^0/ && $DAYX !~ /[0-9]{2}/) {
        $DAYX = "0$DAYX";
      }
      chomp($TIMEX);
      $TIMEX =~ s/[^0-9\:]//g;
      if ($TIMEX =~ /^[0-9]/) {
        local($HOUR, $MIN, $SEC) = split(/:/,$TIMEX);
        $log_is="$MONTX:$DAYX:$HOUR:$MIN";
        if ($now_is eq $log_is) {
          $status="ERROR";
          print "===[$now_is]\t[$log_is]===\n";
          `echo "[$now_is]:[$log_is]" >> /var/xdrago/log/last-sqlcheck-y-problem`;
        }
#         else {
#           `echo "[$now_is]:[$log_is]" >> /var/xdrago/log/last-sqlcheck-n-problem`;
#         }
      }
    }
  }
}
###EOF2024###
