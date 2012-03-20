#!/usr/bin/perl

$| = 1;
if (-f "/var/run/boa_wait.pid") {
  exit;
}
$mailx_test = `mail -V 2>&1`;
$status="CLEAN";
$this_filename = "acrashsql.sh";
$this_path = "/var/xdrago/$this_filename";
`rm -f $this_path`;
$server=`hostname`;
chomp($server);
$timedate=`date +%y%m%d-%H%M`;
chomp($timedate);
$logfile="/var/xdrago/log/mysqlcheck.log";
`touch /var/run/boa_wait.pid`;
sleep(90);
`/usr/bin/mysqlcheck --port=3306 -h localhost -Aa -u root --password=NdKBu34erty325r6mUHxWy > $logfile`;
&makeactions;
`rm -f /var/run/boa_wait.pid`;
`touch /var/xdrago/log/last-run-acrashsql`;
if ($mailx_test =~ /(invalid)/i) {
  if ($status ne "CLEAN") {
    `cat $logfile | mail -a "From: help\@omega8.cc" -e -s "SQL check ERROR [$server] $timedate" help\@omega8.cc`;
    `sh $this_path | mail -a "From: help\@omega8.cc" -e -s "SQL REPAIR done [$server] $timedate" help\@omega8.cc`;
  }
  if ($status ne "ERROR") {
    `cat $logfile | mail -e -a "From: help\@omega8.cc" -s "SQL check CLEAN [$server] $timedate" help\@omega8.cc`;
  }
}
else {
  if ($status ne "CLEAN") {
    `cat $logfile | mail -r help\@omega8.cc -e -s "SQL check ERROR [$server] $timedate" help\@omega8.cc`;
    `sh $this_path | mail -r help\@omega8.cc -e -s "SQL REPAIR done [$server] $timedate" help\@omega8.cc`;
  }
  if ($status ne "ERROR") {
    `cat $logfile | mail -e -r help\@omega8.cc -s "SQL check CLEAN [$server] $timedate" help\@omega8.cc`;
  }
}
exit;

#############################################################################
sub makeactions
{
  if (!-e "$this_path") {
    `echo "#!/bin/bash" > /var/xdrago/$this_filename`;
    `echo " " >> /var/xdrago/firewall/$this_filename`;
  }
  open (NOT,"<$this_path");
  @rectable = <NOT>;
  close (NOT);
  local(@MYARR) = `tail --lines=999999999 $logfile 2>&1`;
  local($maxnumber,$critnumber,$alert);
  local($sumar,$li_cnt{$DOMAIN},$li_cndx{$DOMAIN});
  foreach $line (@MYARR) {
    if ($line =~ /(Table \'\.\/)/i) {
      $status="ERROR";
      local($a, $b, $c, $TABLEX, $rest) = split(/\s+/,$line);
      chomp($TABLEX);
      local($a, $TABLE, $b) = split(/\//,$TABLEX);
      $TABLE =~ s/[^a-z0-9\_]//g;
      if ($TABLE =~ /^[a-z0-9]/) {
        chomp($line);
        $li_cnt{$TABLE}++;
      }
    }
  }
  foreach $TABLE (sort keys %li_cnt) {
    $sumar = $sumar + $li_cnt{$TABLE};
    local($thissumar) = $li_cnt{$TABLE};
    $maxnumber = 0;
    if ($thissumar > $maxnumber) {
      &repair_this_action($TABLE,$thissumar);
    }
  }
  print "\n===[$sumar]\tGLOBAL===\n\n";
  undef (%li_cnt);
}

#############################################################################
sub repair_this_action
{
  local($FIXTABLE,$COUNTER) = @_;
  print "$FIXTABLE [$COUNTER] recorded... $REMOTE_HOST\n";
  `echo "#-- BELOW --# $FIXTABLE [$COUNTER] recorded..." >> /var/xdrago/$this_filename`;
  `echo "/usr/bin/mysqlcheck --port=3306 -h localhost -r -u root --password=NdKBu34erty325r6mUHxWy $FIXTABLE" >> /var/xdrago/$this_filename`;
  `echo "/usr/bin/mysqlcheck --port=3306 -h localhost -o -u root --password=NdKBu34erty325r6mUHxWy $FIXTABLE" >> /var/xdrago/$this_filename`;
  `echo "/usr/bin/mysqlcheck --port=3306 -h localhost -a -u root --password=NdKBu34erty325r6mUHxWy $FIXTABLE" >> /var/xdrago/$this_filename`;
  `echo " " >> /var/xdrago/$this_filename`;
}
###EOF2012###
