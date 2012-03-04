#!/usr/bin/perl

$| = 1;
if (-f "/var/xdrago/log/optimize_mysql_ao.pid") {
  exit;
}
$mailx_test = `mail -V 2>&1`;
$status="CLEAN";
$thisserver = "acrashsql.sh";
$IP_log = "/var/xdrago/$thisserver";
`rm -f $IP_log`;
$server=`hostname`;
chomp($server);
$timedate=`date +%y%m%d-%H%M`;
chomp($timedate);
$logfile="/var/xdrago/log/mysqlcheck.log";
`touch /var/xdrago/log/optimize_mysql_ao.pid`;
sleep(90);
`/usr/bin/mysqlcheck --port=3306 -h localhost -Aa -u root --password=NdKBu34erty325r6mUHxWy > $logfile`;
&makeactions;
`rm -f /var/xdrago/log/optimize_mysql_ao.pid`;
`touch /var/xdrago/log/last-run-acrashsql`;
if ($mailx_test =~ /(invalid)/i) {
  if ($status ne "CLEAN") {
    `cat $logfile | mail -a "From: help\@omega8.cc" -e -s "SQL check ERROR [$server] $timedate" help\@omega8.cc`;
    `sh $IP_log | mail -a "From: help\@omega8.cc" -e -s "SQL REPAIR done [$server] $timedate" help\@omega8.cc`;
  }
  if ($status ne "ERROR") {
    `cat $logfile | mail -e -a "From: help\@omega8.cc" -s "SQL check CLEAN [$server] $timedate" help\@omega8.cc`;
  }
}
else {
  if ($status ne "CLEAN") {
    `cat $logfile | mail -r help\@omega8.cc -e -s "SQL check ERROR [$server] $timedate" help\@omega8.cc`;
    `sh $IP_log | mail -r help\@omega8.cc -e -s "SQL REPAIR done [$server] $timedate" help\@omega8.cc`;
  }
  if ($status ne "ERROR") {
    `cat $logfile | mail -e -r help\@omega8.cc -s "SQL check CLEAN [$server] $timedate" help\@omega8.cc`;
  }
}
exit;
#############################################################################
sub makeactions
{
      if (!-e "$IP_log") {
        `echo "#!/bin/bash" > /var/xdrago/$thisserver`;
        `echo " " >> /var/xdrago/firewall/$thisserver`;
      }
      open (NOT,"<$IP_log");
      @banetable = <NOT>;
      close (NOT);

local(@SYTUACJA) = `tail --lines=999999999 $logfile 2>&1`;

local($maxnumber,$critnumber,$alert);
local($sumar,$li_cnt{$DOMAIN},$li_cndx{$DOMAIN});
foreach $line (@SYTUACJA) {
  if ($line =~ /(Table \'\.\/)/i) {
    $status="ERROR";
    local($a, $b, $c, $VISITORX, $rest) = split(/\s+/,$line);
    chomp($VISITORX);
    local($a, $VISITOR, $b) = split(/\//,$VISITORX);
    $VISITOR =~ s/[^a-z0-9\_]//g;
    if ($VISITOR =~ /^[a-z0-9]/) {
      chomp($line);
      $li_cnt{$VISITOR}++;
    }
  }
}
foreach $VISITOR (sort keys %li_cnt) {
   $sumar = $sumar + $li_cnt{$VISITOR};
   local($thissumar) = $li_cnt{$VISITOR};
   $maxnumber = 0;
   local($blocked) = 0;
   if ($thissumar > $maxnumber && !$blocked) {
       &trash_it_action($VISITOR,$thissumar);
   }
}

print "\n===[$sumar]\tGLOBAL===\n\n";
undef (%li_cnt);

}

#############################################################################
sub trash_it_action
{
   local($ABUSER,$ILE) = @_;
    print "$ABUSER [$ILE] recorded... $REMOTE_HOST\n";
   `echo "#-- BELOW --# $ABUSER [$ILE] recorded..." >> /var/xdrago/$thisserver`;
   `echo "/usr/bin/mysqlcheck --port=3306 -h localhost -r -u root --password=NdKBu34erty325r6mUHxWy $ABUSER" >> /var/xdrago/$thisserver`;
   `echo "/usr/bin/mysqlcheck --port=3306 -h localhost -o -u root --password=NdKBu34erty325r6mUHxWy $ABUSER" >> /var/xdrago/$thisserver`;
   `echo "/usr/bin/mysqlcheck --port=3306 -h localhost -a -u root --password=NdKBu34erty325r6mUHxWy $ABUSER" >> /var/xdrago/$thisserver`;
   `echo " " >> /var/xdrago/$thisserver`;
}

###EOF###
