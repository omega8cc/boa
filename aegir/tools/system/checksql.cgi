#!/usr/bin/perl

$| = 1;
if (-f "/var/run/boa_wait.pid") {
  exit;
}
$mailx_test = `mail -V 2>&1`;
$status="CLEAN";
$fixfile = "/var/xdrago/acrashsql.sh";
`rm -f $fixfile`;
$server=`uname -n`;
chomp($server);
$timedate=`date +%y%m%d-%H%M`;
chomp($timedate);
$logfile="/var/xdrago/log/mysqlcheck.log";
`touch /var/run/boa_wait.pid`;
sleep(90);
`/usr/bin/mysqlcheck -Aa > $logfile`;
&makeactions;
`rm -f /var/run/boa_wait.pid`;
`touch /var/xdrago/log/last-run-acrashsql`;
if ($mailx_test =~ /(invalid)/i) {
  if ($status ne "CLEAN") {
    `cat $logfile | mail -a "From: notify\@omega8.cc" -e -s "SQL check ERROR [$server] $timedate" notify\@omega8.cc`;
    `sh $fixfile | mail -a "From: notify\@omega8.cc" -e -s "SQL REPAIR done [$server] $timedate" notify\@omega8.cc`;
  }
  if ($status ne "ERROR") {
    `cat $logfile | mail -e -a "From: notify\@omega8.cc" -s "SQL check CLEAN [$server] $timedate" notify\@omega8.cc`;
  }
}
else {
  if ($status ne "CLEAN") {
    `cat $logfile | mail -r notify\@omega8.cc -e -s "SQL check ERROR [$server] $timedate" notify\@omega8.cc`;
    `sh $fixfile | mail -r notify\@omega8.cc -e -s "SQL REPAIR done [$server] $timedate" notify\@omega8.cc`;
  }
  if ($status ne "ERROR") {
    `cat $logfile | mail -e -r notify\@omega8.cc -s "SQL check CLEAN [$server] $timedate" notify\@omega8.cc`;
  }
}
`rm -f $logfile`;
exit;

#############################################################################
sub makeactions
{
  if (!-e "$fixfile") {
    `echo "#!/bin/bash" > $fixfile`;
    `echo " " >> $fixfile`;
  }
  open (NOT,"<$fixfile");
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
  `echo "#-- BELOW --# $FIXTABLE [$COUNTER] recorded..." >> $fixfile`;
  `echo "/usr/bin/mysqlcheck -r $FIXTABLE" >> $fixfile`;
  `echo "/usr/bin/mysqlcheck -o $FIXTABLE" >> $fixfile`;
  `echo "/usr/bin/mysqlcheck -a $FIXTABLE" >> $fixfile`;
  `echo " " >> $fixfile`;
}
###EOF2012###
