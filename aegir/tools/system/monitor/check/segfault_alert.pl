#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

###
### This is a segfault monitor for php-fpm and nginx
###

use warnings;
use File::Spec;

if (!-e "/data/u/") {
  exit;
}
$| = 1;
$this_filename = "segfault_alert";
$s=`uname -n 2>&1`;
chomp($s);
&makeactions;
print " CONTROL 1 done_______________________\n ...\n";
exit;

#############################################################################
sub makeactions
{
  $this_path = "/var/xdrago/monitor/log/$this_filename.log";
  if (!-e "$this_path") {
    $intro = <<INTRO
This report is generated automatically when new segfault is discovered.

It may be a result of some bug in the PHP version used, but it is often
caused or exposed by something in the affected site's PHP code.

See the reports linked below to learn more:

https://bugs.php.net/bug.php?id=48034
https://drupal.org/node/1462984#comment-5790468
https://drupal.org/node/1366084#comment-5877974
INTRO
;
    $intrx = <<INTROX
Note that any vhost file (not the site) listed below as causing
segfault has been automatically (re)moved to the /var/backups/segfault/
directory, so affected site will display standard UnderConstruction page
until you will run Verify task in the Aegir control panel for this site.

However, if the problem is not fixed and it still causes segfault,
any affected site will be disabled again after another segfault
immediately, to protect your web server availability.
INTROX
;
    `echo "$intro" >> $this_path`;
    #`echo "$intrx" >> $this_path`;
  }
  $this_archive="/var/xdrago/monitor/log/$this_filename.archive.log";
  if (!-f "$this_archive") {
    `touch $this_archive`;
  }
  open (NOT,"<$this_archive");
  @banetable = <NOT>;
  close (NOT);
  local(@MYARR)=`tail --lines=999 /var/log/syslog 2>&1`;
  local($sumar) = 0;
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;
    if ($line =~ /php\-.*: segfault/i) {
      local($MONTX, $DAYX, $TIMEX, $rest) = split(/\s+/,$line);
      chomp($TIMEX);
      $TIMEX =~ s/[^0-9\:]//g;
      if ($TIMEX =~ /^[0-9]/) {
        chomp($line);
        $li_cnt{$TIMEX}++;
      }
    }
  }
  foreach $TIMEX (sort keys %li_cnt) {
    $sumar = $sumar + $li_cnt{$TIMEX};
    local($thissumar) = $li_cnt{$TIMEX};
    local($blocked) = 0;
    &check_ip($TIMEX);
    if (!$blocked && $thissumar > 0) {
      &trash_it_action($TIMEX,$thissumar);
    }
  }
  print "\n===[$sumar]\tGLOBAL===\n\n";
  undef (%li_cnt);
}

#############################################################################
sub trash_it_action
{
  local($CRASH,$COUNTER) = @_;
  $now_is=`date +%y%m%d-%H%M%S`;
  chomp($now_is);
  &find_domain($CRASH);
  if ($found) {
    print "$CRASH [$COUNTER] recorded on [$now_is]\n";
    `echo "### PHP: CRASH at $CRASH [$COUNTER] discovered on $now_is for $dx" >> $this_path`;
    `echo "### SYS: $sysl" >> $this_path`;
    `echo "### NGX: $ngxl" >> $this_path`;
    `echo "### PTH: $pthl" >> $this_path`;
    `echo "### VHT: $disl" >> $this_path`;
    &_send_alert;
  }
}

#############################################################################
sub check_ip
{
  local($i) = @_;
  foreach $line (@banetable) {
    chomp ($line);
    if ($line =~ /discovered/) {
      local($a, $b, $c, $d, $e, $f) = split(/\s+/,$line);
      if ($e eq $i) {
        $blocked = 1;
        last;
      }
    }
  }
}

#############################################################################
sub find_domain
{
  local($CRASHED) = @_;
  $lx = $d;
  $ngxl=`grep "$CRASHED.* 502 " /var/log/nginx/access.log`;
  $ngxl =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,\"]//g;
  $sysl=`grep "$CRASHED.*php\-.*: segfault" /var/log/syslog`;
  $sysl =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;
  local($a, $b, $c, $x, $y) = split(/\"\s+/,"$ngxl");
  local($d, $e) = split(/\s+/,$b);
  $d =~ s/[^a-z0-9\.\-]//g;
  if ($d !~ /^$/) {
    $found = 1;
    $d =~ s/^www\.//g;
    $dx = $d;
    $pthl=`cat /data/disk/*/.drush/$d.alias.drushrc.php | grep 'site_path' | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`;
    if ($pthl =~ /(No such file or directory)/) {
      $pthl=`cat /data/disk/*/.drush/www.$d.alias.drushrc.php | grep 'site_path' | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`;
    }
    if ($pthl =~ /(No such file or directory)/) {
      $pthl=`cat /var/aegir/.drush/$d.alias.drushrc.php | grep 'site_path' | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`;
    }
    if ($pthl =~ /(No such file or directory)/) {
      $pthl=`cat /var/aegir/.drush/www.$d.alias.drushrc.php | grep 'site_path' | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`;
    }
    local($w, $x, $y, $z) = split(/\s+/,$pthl);
    $pthl = $z;
    chomp ($pthl);
    local($o, $p, $q, $r) = split(/\//,$pthl);
    $rx = $r;
    $disla = "/data/disk/$rx/config/server_master/nginx/vhost.d/$d";
    $dislb = "/data/disk/$rx/config/server_master/nginx/vhost.d/www.$d";
    `mkdir -p /var/backups/segfault`;
    if (-f "$disla" && $rx !~ /^$/) {
      #`mv -f $disla /var/backups/segfault/`;
      #`service nginx reload`;
      $disl = $disla;
    }
    elsif (-f "$dislb" && $rx !~ /^$/) {
      #`mv -f $dislb /var/backups/segfault/`;
      #`service nginx reload`;
      $disl = $dislb;
    }
    $ngxl =~ s/([";])/\\$1/g;
    chomp ($ngxl);
    $sysl =~ s/([";])/\\$1/g;
    chomp ($sysl);
  }
}

#############################################################################
sub _send_alert
{
  $this_email="/data/disk/$rx/log/email.txt";
  if (-f "$this_email") {
    open (FILE,"<$this_email");
    while (<FILE>) {
      $cmail = "$_";
    }
    close (FILE);
    chomp ($cmail);
    print "\ncmail===[$cmail]===\n";
  }
  else {
    $cmail="notify\@omega8.cc";
    print "\nlmail___[$cmail]___\n";
  }
  $mailx_test=`s-nail -V 2>&1`;
  $t=`date +%y%m%d-%H%M`;
  chomp($t);
  if ($mailx_test =~ /(built for Linux)/i) {
    `cat $this_path | s-nail -b notify\@omega8.cc -s "PHP Segfault Alert for [$dx] at [$s] on $t" $cmail`;
  }
  `cat /var/xdrago/monitor/log/$this_filename.log >> /var/xdrago/monitor/log/$this_filename.archive.log`;
  `rm -f /var/xdrago/monitor/log/$this_filename.log`;
}

###EOF2024###
