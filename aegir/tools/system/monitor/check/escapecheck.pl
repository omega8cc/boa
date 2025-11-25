#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

use warnings;
use File::Spec;

$| = 1;
$status="CLEAN";
$server=`uname -n`;
chomp($server);
$date_is=`date +%Y-%m-%d`;
chomp($date_is);
$time_is=`date +%H:%M`;
chomp($time_is);
$now_is="$date_is $time_is";
chomp($now_is);
$logfile="/var/log/boa/last-shell-escape-log";
`rm -f $logfile`;
&makeactions;
if ($status ne "CLEAN") {
  my $email;
  if (open my $fh, '<', '/root/.barracuda.cnf') {
    while (<$fh>) {
      if (/^\s*_MY_EMAIL\s*=\s*(\S+)/) {
        $email = $1;
        last;
      }
    }
    close $fh;
  }
  $email =~ s/\\+@/@/g;
  $mailx_test=`s-nail -V 2>&1`;
  if ($email && $mailx_test =~ /(built for Linux)/i) {
    if ($status ne "CLEAN") {
      system('s-nail',
        '-s', "Shell Escape Alert [$server] $now_is",
        $email,
        '<', $logfile);
    }
  }
}
exit;

#############################################################################
sub makeactions
{
local(@MYARR)=`grep -i forbidden /var/log/lsh/*.log | tail --lines=999 2>&1`;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,\=]//g;
    if ($line =~ /(syntax|path|command)/i || ($line =~ /(shell escape)/i && $line !~ /exit/i)) {
      if ($line =~ /(var\/log\/lsh)/i) {
        ($log, $line) = split(/.log:/,$line);
      }
      local($DATEQ, $TIMEQ, $rest) = split(/\s+/,$line);
      local($TIMEX, $rest) = split(/\,/,$TIMEQ);
      chomp($DATEQ);
      chomp($TIMEX);
      chomp($line);
      $TIMEX =~ s/[^0-9\:]//g;
      if ($TIMEX =~ /^[0-9]/) {
        local($HOUR, $MIN, $SEC) = split(/:/,$TIMEX);
        $log_is="$DATEQ $HOUR:$MIN";
        if ($now_is eq $log_is) {
          $status="ERROR";
          `echo "$line" >> $logfile`;
          `echo "[$now_is]:[$log_is]:[$line]" >> /var/log/boa/last-shell-escape-y-problem`;
        }
#         else {
#           `echo "[$now_is]:[$log_is]" >> /var/log/boa/last-shell-escape-n-problem`;
#         }
      }
    }
  }
}

