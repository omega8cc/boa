#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

###
### This is a segfault monitor for php-fpm and nginx
###

use warnings;
use File::Spec;
use Fcntl;

if (!-e "/data/u/") {
  exit;
}
$| = 1;
$this_filename = "segfault_alert";
$s=`uname -n`;
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
until you will run Verify task in the Ægir control panel for this site.

However, if the problem is not fixed and it still causes segfault,
any affected site will be disabled again after another segfault
immediately, to protect your web server availability.
INTROX
;
    _append($this_path, "$intro\n");
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
    # Written by Perl, never through a shell: the site path comes from an
    # alias file and the log lines from logs other users can write to.
    _append($this_path,
      "### PHP: CRASH at $CRASH [$COUNTER] discovered on $now_is for $dx\n"
      . "### SYS: $sysl\n"
      . "### NGX: $ngxl\n"
      . "### PTH: $pthl\n"
      . "### VHT: " . (defined($disl) ? $disl : "") . "\n");
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
    $pthl = &_alias_site_path($d);
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
    chomp ($ngxl);
    chomp ($sysl);
  }
}

#############################################################################
# The site alias lives in the instance's ~/.drush (or /var/aegir/.drush on the
# master), under the bare or the www. name. Read it in Perl. The old backtick
# pipeline went through /bin/sh, which on a BOA box is websh, and websh refuses
# a root command line that names drush -- the alias path does -- so every
# lookup captured that refusal instead of the site path; and its split into
# four fields assumed the raw grep line, which the cut/awk/sed stages had
# already reduced to one, so the instance name was never derived either.
sub _alias_site_path
{
  local($name) = @_;
  local(@cands) = ();
  push(@cands, glob("/data/disk/*/.drush/$name.alias.drushrc.php"));
  push(@cands, glob("/data/disk/*/.drush/www.$name.alias.drushrc.php"));
  push(@cands, "/var/aegir/.drush/$name.alias.drushrc.php");
  push(@cands, "/var/aegir/.drush/www.$name.alias.drushrc.php");
  foreach $cand (@cands) {
    next unless (-f $cand);
    if (open(ALIAS, "<$cand")) {
      while (<ALIAS>) {
        if (/'site_path'\s*=>\s*'([^']+)'/) {
          close(ALIAS);
          return $1;
        }
      }
      close(ALIAS);
    }
  }
  return "";
}

#############################################################################
# Client mail on a test box, as the shell tools' _client_mail_hold: while
# /data/conf/client_mail_hold.txt exists, the client address gets the one
# address it holds instead, the subject noting who would have been mailed;
# a file that anyone but root can write, or that does not hold exactly one
# plain address, stops the client mail (fail closed) with one line saying
# why. Read through one handle opened without following a link or blocking
# on a FIFO, and only while it is a regular file of root's, not writable by
# group or others, with a single link, 1 KiB at most.
# Returns the recipients to use and the note for the subject; an empty
# recipient means send none. Without the file: the recipient given and no
# note, as before.
sub _client_mail_hold
{
  my ($to) = @_;
  my $f = "/data/conf/client_mail_hold.txt";
  return ($to, "") unless (-e $f || -l $f);
  return ($to, "") unless (defined($to) && $to =~ /\S/);
  my $shown = $to;
  $shown =~ s/\\+\@/\@/g;
  $shown =~ s/\s+/ /g;
  $shown =~ s/[^A-Za-z0-9._%+=\@\x27 -]//g;
  $shown = substr($shown, 0, 200);
  $shown =~ s/^ +| +$//g;
  $shown = "?" if ($shown eq "");
  my ($h, $d, $r, $why);
  if (!sysopen($h, $f, O_RDONLY|O_NOFOLLOW|O_NONBLOCK)) {
    return ($to, "") if ($!{ENOENT});
    $why = "is not a regular file of one link, 1 KiB at most, that this run can read";
  }
  else {
    my @s = stat($h);
    if (!@s) {
      $why = "is not a regular file of one link, 1 KiB at most, that this run can read";
    }
    elsif ($s[4] != 0 || ($s[2] & 022)) {
      $why = "is not root's, or group or others can write it, and cannot be trusted";
    }
    elsif (!(-f _ && $s[3] == 1 && $s[7] <= 1024)) {
      $why = "is not a regular file of one link, 1 KiB at most, that this run can read";
    }
    else {
      $d = "";
      while ($r = sysread($h, my $c, 1025)) {
        $d .= $c;
        last if (length($d) > 1024);
      }
      if (!defined($r) || length($d) > 1024) {
        $why = "is not a regular file of one link, 1 KiB at most, that this run can read";
      }
      elsif ($d =~ /\A\s*([A-Za-z0-9_][A-Za-z0-9._%+=\x27-]*\@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)\s*\z/) {
        my $addr = $1;
        close($h);
        return ($addr, " [held for $shown]");
      }
      else {
        $why = "does not hold exactly one plain address";
      }
    }
    close($h);
  }
  print "ALRT: $f $why: client mail for $shown not sent\n";
  return ("", "");
}

#############################################################################
# Append text to a file, in Perl.
sub _append
{
  my ($path, $text) = @_;
  if (open(my $out, '>>', $path)) {
    print $out $text;
    close($out);
  }
}

#############################################################################
# The plain addresses in a line, as the nightly's mail list takes them: words
# split on white space (and on commas when $2 is set, for the operator's
# line), \@ read as @, each word kept only when it is one plain address; a
# line over 4 KiB gives none. Returns the kept words and the count dropped.
sub _mail_words
{
  my ($line, $commas) = @_;
  return ([], 0) unless (defined($line) && length($line) <= 4096);
  $line =~ s/\\+\@/\@/g;
  $line =~ s/^\s*(["\x27])(.*)\1\s*$/$2/;
  # the operator's cnf value reached s-nail through a shell, which dropped
  # each backslash before a character
  $line =~ s/\\(.)/$1/g if ($commas);
  my (@kept, $dropped);
  $dropped = 0;
  my $sep = $commas ? qr/[\s,]+/ : qr/\s+/;
  foreach my $w (split($sep, $line)) {
    next if ($w eq "");
    if ($w =~ /\A[A-Za-z0-9_][A-Za-z0-9._%+=\x27-]*\@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z/) {
      push(@kept, $w);
    }
    else {
      $dropped++;
    }
  }
  return (\@kept, $dropped);
}

#############################################################################
# A line for the operator: printed, and written into the report, which the
# archive keeps whether or not a mail goes out.
sub _notice
{
  my ($text) = @_;
  print "$text\n";
  _append($this_path, "### ALRT: $text\n");
}

#############################################################################
# The report goes to s-nail on its standard input, every value as its own
# argument: no shell reads the client address, which the account's log
# directory holds, or anything else here.
sub _send_alert
{
  my $email;
  my $cmail;
  my $this_email;
  if (open my $fh, '<', '/root/.barracuda.cnf') {
    while (<$fh>) {
      if (/^\s*_MY_EMAIL\s*=\s*(\S+)/) {
        $email = $1;
        last;
      }
    }
    close $fh;
  }
  my @ops = ();
  if (defined($email)) {
    my ($k, $n) = _mail_words($email, 1);
    @ops = @{$k} if ($k);
    _notice("_MY_EMAIL in /root/.barracuda.cnf holds no plain address: no copy to the operator")
      if (!@ops);
  }
  my @to = ();
  $this_email="/data/disk/$rx/log/email.txt";
  if (-f "$this_email") {
    open (FILE,"<$this_email");
    while (<FILE>) {
      $cmail = "$_";
    }
    close (FILE);
    chomp ($cmail) if (defined($cmail));
    my ($k, $n) = _mail_words($cmail, 0);
    @to = @{$k} if ($k);
    _notice("$this_email: $n word(s) that are not plain addresses left out")
      if ($n > 0 && @to);
    _notice("$this_email holds no plain address: client mail not sent")
      if (!@to && defined($cmail) && $cmail =~ /\S/);
  }
  $mailx_test=`s-nail -V 2>&1`;
  $t=`date +%y%m%d-%H%M`;
  chomp($t);
  if (defined($email) && @to && $mailx_test =~ /(built for Linux)/i) {
    my ($hold_to, $hold_sfx) = _client_mail_hold(join(" ", @to));
    if ($hold_to ne "") {
      @to = ($hold_to) if ($hold_sfx ne "");
      my $subject = "PHP Segfault Alert for [$dx] at [$s] on $t$hold_sfx";
      # every address starts with a letter, digit or underscore, so s-nail
      # never reads one as an option
      my @args = ('-s', $subject);
      unshift(@args, '-b', join(",", @ops)) if (@ops);
      if (open(my $rep, '<', $this_path)) {
        if (open(my $mail, '|-', 's-nail', @args, @to)) {
          print $mail $_ while (<$rep>);
          close($mail);
        }
        close($rep);
      }
    }
  }
  `cat /var/xdrago/monitor/log/$this_filename.log >> /var/xdrago/monitor/log/$this_filename.archive.log`;
  `rm -f /var/xdrago/monitor/log/$this_filename.log`;
}


