#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

###
### This is an auth abuse monitor for ftp.
###

use warnings;
use File::Spec;

$| = 1;
$this_filename = "hackftp";
$times=`date +%y%m%d-%H%M%S`;
chomp($times);
$now_is=`date +%b:%d:%H:%M`;
chomp($now_is);
$timestamp="OLD";
&makeactions;
print "CONTROL complete\n";
exit;

#############################################################################
sub makeactions
{
  if (-e "/var/xdrago/monitor/log/ftp.log") {
    $this_path = "/var/xdrago/monitor/log/ftp.log";
    open (NOT,"<$this_path");
    @banetable = <NOT>;
    close (NOT);
  }
  local(@MYARR)=`tail --lines=999 /var/log/messages 2>&1`;
  local($sumar) = 0;
  local($maxnumber) = 4;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;
    if ($line =~ /(Authentication failed for user)/i || $line =~ /(Sorry, cleartext sessions are not accepted)/i) {
      &verify_timestamp;
      if ($timestamp eq "NEW") {
        local($a, $b, $c, $d, $e, $VISITORX, $rest) = split(/\s+/,$line);
        chomp($VISITORX);
        local($a, $VISITOR) = split(/\@/,$VISITORX);
        $VISITOR =~ s/[^0-9\.]//g;
        if ($VISITOR =~ /^[0-9]/) {
          chomp($line);
          $li_cnt{$VISITOR}++;
        }
      }
    }
  }
  foreach $VISITOR (sort keys %li_cnt) {
    $sumar = $sumar + $li_cnt{$VISITOR};
    local($thissumar) = $li_cnt{$VISITOR};
    local($blocked) = 0;
    &check_ip($VISITOR);
    if ($thissumar > $maxnumber) {
      if (!$blocked) {
        `echo "$VISITOR # [x$thissumar] $times" >> /var/xdrago/monitor/log/ftp.log`;
        `echo "$VISITOR # [x$thissumar] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
        if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
          `/usr/sbin/csf -td $VISITOR 3600 -p 21`;
        }
      }
    }
  }
  print "\n===[$sumar]\tGLOBAL===\n\n";
  undef (%li_cnt);
}

#############################################################################
sub verify_timestamp
{
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
      $timestamp="NEW";
      chomp($line);
      print "===NEW\t[$now_is]\t[$log_is]\t[$line]===\n";
    }
    else {
      chomp($line);
      print "===OLD\t[$now_is]\t[$log_is]\t[$line]===\n";
    }
  }
}

#############################################################################
sub check_ip
{
  local($IP) = @_;
  if (-e "/var/xdrago/monitor/log/ftp.log") {
    foreach $banerecord (@banetable) {
      chomp ($banerecord);
      local($ifbanned, $rest) = split(/\s+/,$banerecord);
      $ifbanned =~ s/[^0-9\.]//g;
      if ($ifbanned eq $IP) {
        $blocked = 1;
        last;
      }
    }
  }
}
###EOF2024###
