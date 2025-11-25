#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

use warnings;
use File::Spec;

$| = 1;

if (-f "/root/.proxy.cnf") {
  exit;
}
$mailx_test=`s-nail -V 2>&1`;
$status="CLEAN";
$fixfile = "/var/xdrago/acrashsql.sh";
system("rm -f $fixfile");
$server=`uname -n`;
chomp($server);
$timedate=`date +%y%m%d-%H%M`;
chomp($timedate);
$logfile="/var/log/boa/mysqlcheck.log";
sleep(90);
$mysqlrootpass=`cat /root/.my.pass.txt`;
chomp($mysqlrootpass);
system("/usr/bin/mysqlcheck -u root -Aa > $logfile");
&makeactions;
system("touch /var/log/boa/last-run-acrashsql");
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
if ($email && $mailx_test =~ /(built for Linux)/i) {
  if ($status ne "CLEAN") {
    system('s-nail',
      '-s', "SQL check ERROR [$server] $timedate",
      $email,
      '<', $logfile);
    system("bash $fixfile | s-nail -s \"SQL REPAIR done [$server] $timedate\" $email");
  }
  if ($status ne "ERROR") {
    system('s-nail',
      '-s', "SQL check CLEAN [$server] $timedate",
      $email,
      '<', $logfile);
  }
}
system("rm -f $logfile");
exit;

#############################################################################
sub makeactions
{
  if (!-e "$fixfile") {
    system("echo \"#!/bin/bash\" > $fixfile");
    system("echo \" \" >> $fixfile");
  }
  local(@MYARR)=`tail --lines=999999999 $logfile 2>&1`;
  local($maxnumber) = 0;
  local($sumar) = 0;
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
  print "$FIXTABLE [$COUNTER] recorded...\n";
  system("echo \"#-- BELOW --# $FIXTABLE [$COUNTER] recorded...\" >> $fixfile");
  system("echo \"/usr/bin/mysqlcheck -u root -r $FIXTABLE\" >> $fixfile");
  system("echo \"/usr/bin/mysqlcheck -u root -o $FIXTABLE\" >> $fixfile");
  system("echo \"/usr/bin/mysqlcheck -u root -a $FIXTABLE\" >> $fixfile");
  system("echo \" \" >> $fixfile");
}

