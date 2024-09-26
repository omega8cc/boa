#!/usr/bin/perl

### TODO - rewrite this legacy script in bash

$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

###
### This is a httpd abuse monitor for nginx.
###

use warnings;
use File::Spec;

$| = 1;
$this_filename = "scan_nginx";
$times=`date +%y%m%d-%H%M%S`;
chomp($times);
$myip=`cat /root/.found_correct_ipv4.cnf`;
chomp($myip);
print "myip is $myip";
if (-e "/root/.hr.monitor.cnf") {
  $default_critnumber = 399;
  $default_lines = 1999;
  $default_mode = 1;
}
else {
  $default_critnumber = 399;
  $default_lines = 1999;
  $default_mode = 2;
}
&makeactions;
print "\nCONTROL complete for $myip\n";
exit;

#############################################################################
sub makeactions
{
  if (-e "/var/xdrago/monitor/log/web.log") {
    $this_path = "/var/xdrago/monitor/log/web.log";
    open (NOT,"<$this_path");
    @banetable = <NOT>;
    close (NOT);
  }
  if (-e "/root/.local.IP.list") {
    $local_ips = "/root/.local.IP.list";
    open (LOC,"<$local_ips");
    @local_ips_table = <LOC>;
    close (LOC);
  }
  $PROXY = 0;
  $VISITOR = 0;
  local(@MYARR)=`tail --lines=$default_lines /var/log/nginx/access.log 2>&1`;
  local($im_li_cnt{$VISITOR}) = 0;
  local($im_px_cnt{$PROXY}) = 0;
  local($im_sumar) = 0;
  local($im_sumarpx) = 0;
  local($li_cnt{$VISITOR}) = 0;
  local($px_cnt{$PROXY}) = 0;
  local($sumar) = 0;
  local($sumarpx) = 0;
  local($critnumber) = $default_critnumber;
  local($mininumber) = $critnumber / 3;
  print "\n===[$mininumber] mininumber===\n";
  foreach $line (@MYARR) {
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;
    local($VISITOR, $PROXY, $XREAL, $YREAL, $ZREAL, $RESTX) = split(/\s+/,$line);

    if ($VISITOR =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      print "VISITOR: $VISITOR\n";
    }
    if ($PROXY =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      print "PROXY: $PROXY\n";
    }
    if ($XREAL =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      print "XREAL: $XREAL\n";
    }
    if ($YREAL =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      print "YREAL: $YREAL\n";
    }
    if ($ZREAL =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      print "ZREAL: $ZREAL\n";
    }
    if ($RESTX =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      print "RESTX: $RESTX\n";
    }

    $block_unknown = 0;
    if ($VISITOR =~ /^(unknown)/)
    {
      $block_unknown = 1;
    }

    if ($VISITOR =~ /^((192\.168\.)|(172\.16\.)|(unknown)|(10\.)|(127\.0\.))/)
    {
      $VISITOR = $PROXY;
      $PROXY = $XREAL;
      if ($VISITOR =~ /^((192\.168\.)|(172\.16\.)|(unknown)|(10\.)|(127\.0\.))/)
      {
        $VISITOR = $XREAL;
        $PROXY = $YREAL;
        if ($VISITOR =~ /^((192\.168\.)|(172\.16\.)|(unknown)|(10\.)|(127\.0\.))/)
        {
          $VISITOR = $YREAL;
          $PROXY = $ZREAL;
          if ($VISITOR =~ /^((192\.168\.)|(172\.16\.)|(unknown)|(10\.)|(127\.0\.))/)
          {
            $VISITOR = $ZREAL;
          }
        }
      }
    }

    $VISITOR =~ s/[^0-9\.]//g;
    if ($VISITOR !~ /^((192\.168\.)|(172\.16\.)|(10\.)|(127\.0\.))/ && $VISITOR =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      chomp($line);
      $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 99  if ($block_unknown > 0);
      $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 99  if ($line =~ /\" 404 /);
      $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 99  if ($line =~ /\" 403 /);
      $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 99  if ($line =~ /\" 500 /);
      $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 99  if ($line =~ /wp-(content|admin|includes)/);
      $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 19  if ($line =~ /(POST|GET) \/user\/login/);
      local($ignore_admin) = 0;
      local($skip_post) = 0;
      if ($line =~ /(GET|HEAD|POST)/ && $line !~ /\" 301 /) {
        if ($line =~ /\/admin\/content/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/quickedit/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/node\/add/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /GET \/entity_reference_autocomplete/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/entity-browser/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/contextual\/render/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/node\//) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /(GET|POST) \/([a-z]{2}\/)?(civicrm|batch|advagg|views-bulk-operations|node\/[0-9]{1,}\/edit|media\/browser)|POST \/js\/|(GET|POST) \/([a-z]{2}\/)?(hosting|system|admin|app|ckeditor)\/|\/(ajax|autocomplete|shs)\/|plupload|json|api\/rest|GET \/(filefield_nginx_progress|filefield\/progress|files\/progress|file\/progress|elfinder\/connector)|\b(ajax|autocomplete)\b|\b(\/files\/css\/css_)\b|\b(\/files\/js\/js_)\b|\b(\/files\/advagg_)\b/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $skip_post = 1;
          $ignore_admin = 1;
        }
        elsif ($line =~ /files\/(imagecache|styles|media)/) {
          ### print "Monitored Not Counted Dynamic Request URI: $line\n";
          ### $im_li_cnt{$VISITOR}++;
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/.*\.(mp4|m4a|flv|avi|mpe?g|mov|wmv|mp3|ogg|ogv|wav|midi|zip|tar|t?gz|rar|dmg|exe|apk|pxl|ipa)\"/) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/timemachine\/[0-9]{4}\//) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/cart\/checkout/) {
          ### print "Not Counted Dynamic Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/embed\/preview/) {
          ### print "Not Counted Dynamic Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /files\.aegir\.cc/) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /dontcount/) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        else {
          $li_cnt{$VISITOR}++;
        }
        if ($skip_post < 1 || $ignore_admin < 1) {
          if ($default_mode eq "1") {
            $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 5 if ($line =~ /POST/ && $line =~ /(\/user)|(user\/(register|pass|login))|(node\/add)/);
            $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 3 if ($line =~ /GET/  && $line =~ /node\/add/);
            $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 5 if ($line =~ /foobar/);
          }
          else {
            $li_cnt{$VISITOR} = $li_cnt{$VISITOR} + 1  if ($line =~ /POST/);
          }
        }
      }
      else {
        if ($line =~ /0.000/) {
          print "Not Counted Not Supported Request Type: $line\n";
        }
        else {
          if ($ignore_admin < 1) {
            $li_cnt{$VISITOR}++;
            ### print "Counted Not Supported Request Type: $line\n";
          }
        }
      }
    }
    $PROXY =~ s/[^0-9\.]//g;
    if ($PROXY ne $VISITOR && $PROXY !~ /^((192\.168\.)|(172\.16\.)|(10\.)|(127\.0\.))/ && $PROXY =~ /^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$/) {
      chomp($line);
      $px_cnt{$PROXY} = $px_cnt{$PROXY} + 99  if ($block_unknown > 0);
      $px_cnt{$PROXY} = $px_cnt{$PROXY} + 99  if ($line =~ /\" 404 /);
      $px_cnt{$PROXY} = $px_cnt{$PROXY} + 99  if ($line =~ /\" 403 /);
      $px_cnt{$PROXY} = $px_cnt{$PROXY} + 99  if ($line =~ /\" 500 /);
      $px_cnt{$PROXY} = $px_cnt{$PROXY} + 99  if ($line =~ /wp-(content|admin|includes)/);
      $px_cnt{$PROXY} = $px_cnt{$PROXY} + 19  if ($line =~ /(POST|GET) \/user\/login/);
      local($skip_post) = 0;
      local($ignore_admin) = 0;
      if ($line =~ /(GET|HEAD|POST)/ && $line !~ /\" 301 /) {
        if ($line =~ /\/admin\/content/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/quickedit/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/node\/add/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /GET \/entity_reference_autocomplete/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/entity-browser/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/contextual\/render/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /POST \/node\//) {
          ### print "Not Counted Admin Request URI: $line\n";
          $ignore_admin = 1;
        }
        elsif ($line =~ /(GET|POST) \/([a-z]{2}\/)?(civicrm|batch|advagg|views-bulk-operations|node\/[0-9]{1,}\/edit|media\/browser)|POST \/js\/|(GET|POST) \/([a-z]{2}\/)?(hosting|system|admin|app|ckeditor)\/|\/(ajax|autocomplete|shs)\/|plupload|json|api\/rest|GET \/(filefield_nginx_progress|filefield\/progress|files\/progress|file\/progress|elfinder\/connector)|\b(ajax|autocomplete)\b|\b(\/files\/css\/css_)\b|\b(\/files\/js\/js_)\b|\b(\/files\/advagg_)\b/) {
          ### print "Not Counted Admin Request URI: $line\n";
          $skip_post = 1;
          $ignore_admin = 1;
        }
        elsif ($line =~ /files\/(imagecache|styles|media)/) {
          ### print "Monitored Not Counted Dynamic Request URI: $line\n";
          ### $im_px_cnt{$PROXY}++;
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/.*\.(mp4|m4a|flv|avi|mpe?g|mov|wmv|mp3|ogg|ogv|wav|midi|zip|tar|t?gz|rar|dmg|exe|apk|pxl|ipa)\"/) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/timemachine\/[0-9]{4}\//) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/cart\/checkout/) {
          ### print "Not Counted Dynamic Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/embed\/preview/) {
          ### print "Not Counted Dynamic Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /files\.aegir\.cc/) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        elsif ($line =~ /dontcount/) {
          ### print "Not Counted Static Request URI: $line\n";
          $skip_post = 1;
        }
        else {
          $px_cnt{$PROXY}++;
        }
        if ($skip_post < 1 || $ignore_admin < 1) {
          if ($default_mode eq "1") {
            $px_cnt{$PROXY} = $px_cnt{$PROXY} + 5 if ($line =~ /POST/ && $line =~ /(\/user)|(user\/(register|pass|login))|(node\/add)/);
            $px_cnt{$PROXY} = $px_cnt{$PROXY} + 3 if ($line =~ /GET/  && $line =~ /node\/add/);
            $px_cnt{$PROXY} = $px_cnt{$PROXY} + 5 if ($line =~ /foobar/);
          }
          else {
            $px_cnt{$PROXY} = $px_cnt{$PROXY} + 1  if ($line =~ /POST/);
          }
        }
      }
      else {
        if ($line =~ /0.000/) {
          print "Not Counted Not Supported Request Type: $line\n";
        }
        else {
          if ($ignore_admin < 1) {
            $px_cnt{$PROXY}++;
            ### print "Counted Not Supported Request Type: $line\n";
          }
        }
      }
    }
  }
  foreach $VISITOR (sort keys %li_cnt) {
    $sumar = $sumar + $li_cnt{$VISITOR};
    local($thissumar) = $li_cnt{$VISITOR};
    local($critnumber) = $default_critnumber;
    local($mininumber) = $critnumber / 3;
    if ($thissumar > $mininumber) {
      local($isloggedin) = 0;
      &check_who($VISITOR);
      $critnumber = 9999 if ($isloggedin); ### don't block logged in users
      $critnumber = 9998 if ($VISITOR =~ /$myip/); ### don't block own IP
      #print "===[DEBUG] VISITOR is $VISITOR and MYIP is $myip===\n" if ($myip);
      print "===[$isloggedin] LOGGED li_cnt $VISITOR is logged in===\n" if ($isloggedin);
      print "===[$critnumber] MAX li_cnt critnumber for $VISITOR===\n" if ($VISITOR);
      print "===[$thissumar] COUNTER li_cnt counter for $VISITOR===\n" if ($VISITOR);
      local($blocked) = 0;
      &check_remote_ip($VISITOR);
      local($allowed) = 0;
      &check_own_ip($VISITOR);
      if ($thissumar > $critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thissumar] BLOCK li_cnt action for $VISITOR===\n" if ($VISITOR);
          `echo "$VISITOR # [x$thissumar] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$VISITOR # [x$thissumar] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $VISITOR 3600 -p 80`;
          }
        }
      }
    }
  }
  foreach $PROXY (sort keys %px_cnt) {
    $sumarpx = $sumarpx + $px_cnt{$PROXY};
    local($thissumarpx) = $px_cnt{$PROXY};
    local($critnumber) = $default_critnumber;
    local($mininumber) = $critnumber / 3;
    if ($thissumarpx > $mininumber) {
      local($isloggedin) = 0;
      &check_who($PROXY);
      $critnumber = 9997 if ($isloggedin); ### don't block logged in users
      $critnumber = 9996 if ($PROXY eq $myip); ### don't block own IP
      print "===[$isloggedin] LOGGED px_cnt $PROXY is logged in===\n" if ($isloggedin);
      print "===[$critnumber] MAX px_cnt critnumber for $PROXY===\n" if ($PROXY);
      print "===[$thissumarpx] COUNTER px_cnt counter for $PROXY===\n" if ($PROXY);
      local($blocked) = 0;
      &check_remote_ip($PROXY);
      local($allowed) = 0;
      &check_own_ip($PROXY);
      if ($thissumarpx > $critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thissumarpx] BLOCK px_cnt action for $PROXY===\n" if ($PROXY);
          `echo "$PROXY # [x$thissumarpx] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$PROXY # [x$thissumarpx] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $PROXY 3600 -p 80`;
          }
        }
      }
    }
  }
  foreach $VISITOR (sort keys %im_li_cnt) {
    $im_sumar = $im_sumar + $im_li_cnt{$VISITOR};
    local($thisim_sumar) = $im_li_cnt{$VISITOR};
    local($critnumber) = $default_critnumber;
    local($mininumber) = $critnumber / 3;
    if ($thisim_sumar > $mininumber) {
      local($isloggedin) = 0;
      &check_who($VISITOR);
      $critnumber = 9995 if ($isloggedin); ### don't block logged in users
      $critnumber = 9994 if ($VISITOR eq $myip); ### don't block own IP
      print "===[$isloggedin] LOGGED im_li_cnt $VISITOR is logged in===\n" if ($isloggedin);
      print "===[$critnumber] MAX im_li_cnt critnumber for $VISITOR===\n" if ($VISITOR);
      print "===[$thisim_sumar] COUNTER im_li_cnt counter for $VISITOR===\n" if ($VISITOR);
      local($blocked) = 0;
      &check_remote_ip($VISITOR);
      local($allowed) = 0;
      &check_own_ip($VISITOR);
      if ($thisim_sumar > $critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thisim_sumar] BLOCK im_li_cnt action for $VISITOR===\n" if ($VISITOR);
          `echo "$VISITOR # [x$thisim_sumar] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$VISITOR # [x$thisim_sumar] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $VISITOR 3600 -p 80`;
          }
        }
      }
    }
  }
  foreach $PROXY (sort keys %im_px_cnt) {
    $im_sumarpx = $im_sumarpx + $im_px_cnt{$PROXY};
    local($thisim_sumarpx) = $im_px_cnt{$PROXY};
    local($critnumber) = $default_critnumber;
    local($mininumber) = $critnumber / 3;
    if ($thisim_sumarpx > $mininumber) {
      local($isloggedin) = 0;
      &check_who($PROXY);
      $critnumber = 9993 if ($isloggedin); ### don't block logged in users
      $critnumber = 9992 if ($PROXY eq $myip); ### don't block own IP
      print "===[$isloggedin] LOGGED im_px_cnt $PROXY is logged in===\n" if ($isloggedin);
      print "===[$critnumber] MAX im_px_cnt critnumber for $PROXY===\n" if ($PROXY);
      print "===[$thisim_sumarpx] COUNTER im_px_cnt counter for $PROXY===\n" if ($PROXY);
      local($blocked) = 0;
      &check_remote_ip($PROXY);
      local($allowed) = 0;
      &check_own_ip($PROXY);
      if ($thisim_sumarpx > $critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thisim_sumarpx] BLOCK im_px_cnt action for $PROXY===\n" if ($PROXY);
          `echo "$PROXY # [x$thisim_sumarpx] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$PROXY # [x$thisim_sumarpx] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $PROXY 3600 -p 80`;
          }
        }
      }
    }
  }
  print "===[$sumar] sumar===\n";
  print "===[$sumarpx] sumarpx===\n";
  print "===[$im_sumar] im_sumar===\n";
  print "===[$im_sumarpx] im_sumarpx===\n";
  undef (%li_cnt);
  undef (%px_cnt);
  undef (%im_li_cnt);
  undef (%im_px_cnt);
}

#############################################################################
sub check_remote_ip
{
  local($IP) = @_;
  if (-e "/var/xdrago/monitor/log/web.log") {
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
#############################################################################
sub check_who
{
  local($IP) = @_;
  @whotable=`who --ips | awk '{print $5}'`;
  foreach $whorecord (@whotable) {
    chomp ($whorecord);
    local($a, $b, $c, $d, $whoip) = split(/\s+/,$whorecord);
    $whoip =~ s/[^0-9\.]//g;
    if ($whoip eq $IP) {
      $isloggedin = 1;
      print "===[$IP] is AUTH OK===\n";
      last;
    }
  }
}
#############################################################################
sub check_own_ip
{
  local($IP) = @_;
  if (-e "/root/.local.IP.list") {
    foreach $record (@local_ips_table) {
      chomp ($record);
      local($ifallowed, $rest) = split(/\s+/,$record);
      $ifallowed =~ s/[^0-9\.]//g;
      if ($ifallowed eq $IP) {
        $allowed = "ALLOWED";
        print "===[$IP] is MY OK===\n";
        last;
      }
    }
  }
}
###EOF2024###
