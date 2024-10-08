#!/usr/bin/perl

use strict;
use warnings;
use File::Spec;

# Set environment variables
$ENV{'HOME'} = '/root';
$ENV{'PATH'} = '/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin';

# Autoflush output
$| = 1;

# Initialize variables
my $this_filename = "scan_nginx";
my $times = `date +%y%m%d-%H%M%S`;
chomp($times);
my $myip = `cat /root/.found_correct_ipv4.cnf`;
chomp($myip);
print "myip is $myip\n";

# ==============================
# Default Configuration Values
# ==============================

my $NGINX_DOS_LINES = 1999;
my $NGINX_DOS_LIMIT = 399;
my $NGINX_DOS_LOG = 'SILENT';
my $NGINX_DOS_IGNORE = 'doccomment';
my $NGINX_DOS_STOP = 'foobar';
my $NGINX_DOS_MODE = 2;

# ==============================
# Load Configuration File
# ==============================

my $config_file = '/root/.barracuda.cnf';

if (-e $config_file) {
  open my $fh, '<', $config_file or die "Could not open '$config_file' $!";
  while (my $line = <$fh>) {
    chomp $line;
    # Skip comments and empty lines
    next if $line =~ /^\s*#/ || $line =~ /^\s*$/;

    # Parse lines in the form of 'key=value'
    if ($line =~ /^_NGINX_DOS_LINES=(\d+)/) {
      my $NGINX_DOS_LINES = $1;
    }
    if ($line =~ /^_NGINX_DOS_LIMIT=(\d+)/) {
      my $NGINX_DOS_LIMIT = $1;
    }
    if ($line =~ /^_NGINX_DOS_MODE=(\d+)/) {
      my $NGINX_DOS_MODE = $1;
    }
    if ($line =~ /^_NGINX_DOS_LOG=(\S+)/) {
      my $NGINX_DOS_LOG = $1;
    }
    if ($line =~ /^_NGINX_DOS_IGNORE=(\S+)/) {
      my $NGINX_DOS_IGNORE = $1;
    }
    if ($line =~ /^_NGINX_DOS_STOP=(\S+)/) {
      my $NGINX_DOS_STOP = $1;
    }
  }
  close $fh;
}

if (-e "/root/.hr.monitor.cnf") {
  my $NGINX_DOS_MODE = 1;
}
else {
  my $NGINX_DOS_MODE = 2;
}

# Precompute increments based on $NGINX_DOS_LIMIT
my $INC_NUMBER   = int(($NGINX_DOS_LIMIT + 20) / 40);  # Approx division by 40
my $INC_S_NUMBER = int(($NGINX_DOS_LIMIT + 40) / 80);  # Approx division by 80

# Print the configuration for verification
print "CONFIG: NGINX_DOS_LIMIT is $NGINX_DOS_LIMIT\n";
print "CONFIG: NGINX_DOS_LINES is $NGINX_DOS_LINES\n";
print "CONFIG: INC_NUMBER is $INC_NUMBER\n";
print "CONFIG: INC_S_NUMBER is $INC_S_NUMBER\n";

# Execute the main action subroutine
makeactions();

print "\nCONTROL complete for $myip\n";
exit;

#############################################################################
sub makeactions {
  # Declare necessary hashes
  my (%li_cnt, %px_cnt, %im_li_cnt, %im_px_cnt);
  my ($sumar, $sumarpx, $im_sumar, $im_sumarpx) = (0, 0, 0, 0);

  # Load banetable if web.log exists
  my @banetable;
  if (-e "/var/xdrago/monitor/log/web.log") {
    my $this_path = "/var/xdrago/monitor/log/web.log";
    open (my $not_fh, '<', $this_path) or die "Cannot open $this_path: $!";
    @banetable = <$not_fh>;
    close ($not_fh);
  }

  # Load local IPs if .local.IP.list exists
  my @local_ips_table;
  if (-e "/root/.local.IP.list") {
    my $local_ips = "/root/.local.IP.list";
    open (my $loc_fh, '<', $local_ips) or die "Cannot open $local_ips: $!";
    @local_ips_table = <$loc_fh>;
    close ($loc_fh);
  }

  # Read the last $NGINX_DOS_LINES from access.log
  my @MYARR = `tail --lines=$NGINX_DOS_LINES /var/log/nginx/access.log 2>&1`;
  chomp(@MYARR);

  # Calculate mininumber
  my $mininumber = $NGINX_DOS_LIMIT / 3;
  print "\n===[$mininumber] mininumber===\n";

  foreach my $line (@MYARR) {
    # Clean the line by removing unwanted characters
    $line =~ s/[^a-zA-Z0-9\:\s\t\/\-\@\_\(\)\*\[\]\.\,]//g;

    # Split the line into its components
    my ($VISITOR, $PROXY, $XREAL, $YREAL, $ZREAL, $RESTX) = split(/\s+/, $line);

    # Debugging outputs for IPs
    print "VISITOR: $VISITOR\n"    if defined $VISITOR    && $VISITOR =~ /^(\d{1,3}\.){3}\d{1,3}$/;
    print "PROXY: $PROXY\n"      if defined $PROXY      && $PROXY =~ /^(\d{1,3}\.){3}\d{1,3}$/;
    print "XREAL: $XREAL\n"      if defined $XREAL      && $XREAL =~ /^(\d{1,3}\.){3}\d{1,3}$/;
    print "YREAL: $YREAL\n"      if defined $YREAL      && $YREAL =~ /^(\d{1,3}\.){3}\d{1,3}$/;
    print "ZREAL: $ZREAL\n"      if defined $ZREAL      && $ZREAL =~ /^(\d{1,3}\.){3}\d{1,3}$/;
    print "RESTX: $RESTX\n"      if defined $RESTX      && $RESTX =~ /^(\d{1,3}\.){3}\d{1,3}$/;

    # Initialize block_unknown flag
    my $block_unknown = 0;
    $block_unknown = 1 if defined $VISITOR && $VISITOR =~ /^unknown/;

    # Resolve VISITOR and PROXY IPs by checking for private or unknown IPs
    if (defined $VISITOR && $VISITOR =~ /^(192\.168\.|172\.16\.|unknown|10\.|127\.0\.)/) {
      $VISITOR = $PROXY // '';
      $PROXY  = $XREAL // '';
      if ($VISITOR =~ /^(192\.168\.|172\.16\.|unknown|10\.|127\.0\.)/) {
        $VISITOR = $XREAL // '';
        $PROXY  = $YREAL // '';
        if ($VISITOR =~ /^(192\.168\.|172\.16\.|unknown|10\.|127\.0\.)/) {
          $VISITOR = $YREAL // '';
          $PROXY  = $ZREAL // '';
          if ($VISITOR =~ /^(192\.168\.|172\.16\.|unknown|10\.|127\.0\.)/) {
            $VISITOR = $ZREAL // '';
          }
        }
      }
    }

    # Clean VISITOR IP
    $VISITOR =~ s/[^0-9\.]//g if defined $VISITOR;

    # Process VISITOR if it's a valid public IP
    if (defined $VISITOR && $VISITOR !~ /^(192\.168\.|172\.16\.|10\.|127\.0\.)/ && $VISITOR =~ /^(\d{1,3}\.){3}\d{1,3}$/) {
      chomp($line);

      # Initialize flags
      my $ignore_admin = 0;
      my $skip_post  = 0;

      # Check for specific request patterns to ignore or skip
      if ($line =~ /(GET|HEAD|POST)/ && $line !~ /\" 301 /) {
        if ($line =~ /\/admin\/content/ ||
          $line =~ /POST \/quickedit/ ||
          $line =~ /POST \/node\/add/ ||
          $line =~ /GET \/entity_reference_autocomplete/ ||
          $line =~ /POST \/entity-browser/ ||
          $line =~ /POST \/contextual\/render/ ||
          $line =~ /POST \/node\//) {
          $ignore_admin = 1;
        }
        elsif ($line =~ /(GET|POST) \/([a-z]{2}\/)?(civicrm|batch|advagg|views-bulk-operations|node\/\d+\/edit|media\/browser)|POST \/js\/|(GET|POST) \/([a-z]{2}\/)?(hosting|system|admin|app|ckeditor)\/|\/(ajax|autocomplete|shs)\/|plupload|json|api\/rest|GET \/(filefield_nginx_progress|filefield\/progress|files\/progress|file\/progress|elfinder\/connector)|\b(ajax|autocomplete)\b|\b(\/files\/css\/css_)\b|\b(\/files\/js\/js_)\b|\b(\/files\/advagg_)\b/) {
          $skip_post = 1;
          $ignore_admin = 1;
        }
        elsif ($line =~ /files\/(imagecache|styles|media)/) {
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/.*\.(mp4|m4a|flv|avi|mpe?g|mov|wmv|mp3|ogg|ogv|wav|midi|zip|tar|t?gz|rar|dmg|exe|apk|pxl|ipa)\"/) {
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/timemachine\/\d{4}\//) {
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/cart\/checkout/) {
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/embed\/preview/) {
          $skip_post = 1;
        }
        elsif ($line =~ /files\.aegir\.cc/) {
          $skip_post = 1;
        }
        elsif ($line =~ /dontcount/) {
          $skip_post = 1;
        }
        else {
          $li_cnt{$VISITOR}++;
        }

        # Additional counter increments based on mode
        if (!$skip_post && !$ignore_admin) {

          # Increment counters with proper initialization
          $li_cnt{$VISITOR} = ($li_cnt{$VISITOR} // 0) + $INC_NUMBER if ($block_unknown > 0);
          $li_cnt{$VISITOR} = ($li_cnt{$VISITOR} // 0) + $INC_NUMBER if ($line =~ /\" 404 /);
          $li_cnt{$VISITOR} = ($li_cnt{$VISITOR} // 0) + $INC_NUMBER if ($line =~ /\" 403 /);
          $li_cnt{$VISITOR} = ($li_cnt{$VISITOR} // 0) + $INC_NUMBER if ($line =~ /\" 500 /);
          $li_cnt{$VISITOR} = ($li_cnt{$VISITOR} // 0) + $INC_NUMBER if ($line =~ /wp-(content|admin|includes)/);
          $li_cnt{$VISITOR} = ($li_cnt{$VISITOR} // 0) + $INC_S_NUMBER if ($line =~ /(POST|GET) \/user\/login/);

          if ($NGINX_DOS_MODE == 1) {
            $li_cnt{$VISITOR} += 5 if ($line =~ /POST/ && $line =~ /(\/user)|(user\/(register|pass|login))|(node\/add)/);
            $li_cnt{$VISITOR} += 3 if ($line =~ /GET/ && $line =~ /node\/add/);
            $li_cnt{$VISITOR} += 5 if ($line =~ /foobar/);
          }
          else {
            $li_cnt{$VISITOR} += 1 if ($line =~ /POST/);
          }
        }
      }
      else {
        if ($line =~ /0\.000/) {
          print "Not Counted Not Supported Request Type: $line\n";
        }
        else {
          if (!$ignore_admin) {
            $li_cnt{$VISITOR}++;
          }
        }
      }
    }

    # Clean PROXY IP
    $PROXY =~ s/[^0-9\.]//g if defined $PROXY;

    # Process PROXY if it's a valid public IP and different from VISITOR
    if (defined $PROXY && defined $VISITOR && $PROXY ne $VISITOR &&
      $PROXY !~ /^(192\.168\.|172\.16\.|10\.|127\.0\.)/ &&
      $PROXY =~ /^(\d{1,3}\.){3}\d{1,3}$/) {
      chomp($line);

      # Initialize flags
      my $skip_post  = 0;
      my $ignore_admin = 0;

      # Check for specific request patterns to ignore or skip
      if ($line =~ /(GET|HEAD|POST)/ && $line !~ /\" 301 /) {
        if ($line =~ /\/admin\/content/ ||
          $line =~ /POST \/quickedit/ ||
          $line =~ /POST \/node\/add/ ||
          $line =~ /GET \/entity_reference_autocomplete/ ||
          $line =~ /POST \/entity-browser/ ||
          $line =~ /POST \/contextual\/render/ ||
          $line =~ /POST \/node\//) {
          $ignore_admin = 1;
        }
        elsif ($line =~ /(GET|POST) \/([a-z]{2}\/)?(civicrm|batch|advagg|views-bulk-operations|node\/\d+\/edit|media\/browser)|POST \/js\/|(GET|POST) \/([a-z]{2}\/)?(hosting|system|admin|app|ckeditor)\/|\/(ajax|autocomplete|shs)\/|plupload|json|api\/rest|GET \/(filefield_nginx_progress|filefield\/progress|files\/progress|file\/progress|elfinder\/connector)|\b(ajax|autocomplete)\b|\b(\/files\/css\/css_)\b|\b(\/files\/js\/js_)\b|\b(\/files\/advagg_)\b/) {
          $skip_post = 1;
          $ignore_admin = 1;
        }
        elsif ($line =~ /files\/(imagecache|styles|media)/) {
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/.*\.(mp4|m4a|flv|avi|mpe?g|mov|wmv|mp3|ogg|ogv|wav|midi|zip|tar|t?gz|rar|dmg|exe|apk|pxl|ipa)\"/) {
          $skip_post = 1;
        }
        elsif ($line =~ /GET \/timemachine\/\d{4}\//) {
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/cart\/checkout/) {
          $skip_post = 1;
        }
        elsif ($line =~ /POST \/.*/ && $line =~ /\/embed\/preview/) {
          $skip_post = 1;
        }
        elsif ($line =~ /files\.aegir\.cc/) {
          $skip_post = 1;
        }
        elsif ($line =~ /dontcount/) {
          $skip_post = 1;
        }
        else {
          $px_cnt{$PROXY}++;
        }

        # Additional counter increments based on mode
        if (!$skip_post && !$ignore_admin) {

          # Increment counters with proper initialization
          $px_cnt{$PROXY} = ($px_cnt{$PROXY} // 0) + $INC_NUMBER if ($block_unknown > 0);
          $px_cnt{$PROXY} = ($px_cnt{$PROXY} // 0) + $INC_NUMBER if ($line =~ /\" 404 /);
          $px_cnt{$PROXY} = ($px_cnt{$PROXY} // 0) + $INC_NUMBER if ($line =~ /\" 403 /);
          $px_cnt{$PROXY} = ($px_cnt{$PROXY} // 0) + $INC_NUMBER if ($line =~ /\" 500 /);
          $px_cnt{$PROXY} = ($px_cnt{$PROXY} // 0) + $INC_NUMBER if ($line =~ /wp-(content|admin|includes)/);
          $px_cnt{$PROXY} = ($px_cnt{$PROXY} // 0) + $INC_S_NUMBER if ($line =~ /(POST|GET) \/user\/login/);

          if ($NGINX_DOS_MODE == 1) {
            $px_cnt{$PROXY} += 5 if ($line =~ /POST/ && $line =~ /(\/user)|(user\/(register|pass|login))|(node\/add)/);
            $px_cnt{$PROXY} += 3 if ($line =~ /GET/ && $line =~ /node\/add/);
            $px_cnt{$PROXY} += 5 if ($line =~ /foobar/);
          }
          else {
            $px_cnt{$PROXY} += 1 if ($line =~ /POST/);
          }
        }
      }
      else {
        if ($line =~ /0\.000/) {
          print "Not Counted Not Supported Request Type: $line\n";
        }
        else {
          if (!$ignore_admin) {
            $px_cnt{$PROXY}++;
          }
        }
      }
    }
  }

  # Process li_cnt hash
  foreach my $VISITOR (sort keys %li_cnt) {
    my $thissumar = $li_cnt{$VISITOR};
    $sumar += $thissumar;
    my $current_critnumber = $NGINX_DOS_LIMIT;
    my $current_mininumber = int(($current_critnumber + 1) / 2);  # Approx division by 2

    if ($thissumar > $current_mininumber) {
      my $isloggedin = check_who($VISITOR);
      $current_critnumber = 9999 if ($isloggedin); # Don't block logged-in users
      $current_critnumber = 9998 if ($VISITOR eq $myip); # Don't block own IP

      print "===[$isloggedin] LOGGED li_cnt $VISITOR is logged in===\n" if ($isloggedin);
      print "===[$current_critnumber] MAX li_cnt critnumber for $VISITOR===\n" if ($VISITOR);
      print "===[$thissumar] COUNTER li_cnt counter for $VISITOR===\n" if ($VISITOR);

      my $blocked = check_remote_ip($VISITOR, @banetable);
      my $allowed = check_own_ip($VISITOR, @local_ips_table);

      if ($thissumar > $current_critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thissumar] BLOCK li_cnt action for $VISITOR===\n" if ($VISITOR);
          `echo "$VISITOR # [x$thissumar] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$VISITOR # [x$thissumar] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $VISITOR 900 -p 80`;
            `/usr/sbin/csf -td $VISITOR 900 -p 443`;
          }
        }
      }
    }
  }

  # Process px_cnt hash
  foreach my $PROXY (sort keys %px_cnt) {
    my $thissumarpx = $px_cnt{$PROXY};
    $sumarpx += $thissumarpx;
    my $current_critnumber = $NGINX_DOS_LIMIT;
    my $current_mininumber = int(($current_critnumber + 1) / 2);  # Approx division by 2

    if ($thissumarpx > $current_mininumber) {
      my $isloggedin = check_who($PROXY);
      $current_critnumber = 9997 if ($isloggedin); # Don't block logged-in users
      $current_critnumber = 9996 if ($PROXY eq $myip); # Don't block own IP

      print "===[$isloggedin] LOGGED px_cnt $PROXY is logged in===\n" if ($isloggedin);
      print "===[$current_critnumber] MAX px_cnt critnumber for $PROXY===\n" if ($PROXY);
      print "===[$thissumarpx] COUNTER px_cnt counter for $PROXY===\n" if ($PROXY);

      my $blocked = check_remote_ip($PROXY, @banetable);
      my $allowed = check_own_ip($PROXY, @local_ips_table);

      if ($thissumarpx > $current_critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thissumarpx] BLOCK px_cnt action for $PROXY===\n" if ($PROXY);
          `echo "$PROXY # [x$thissumarpx] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$PROXY # [x$thissumarpx] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $PROXY 900 -p 80`;
            `/usr/sbin/csf -td $PROXY 900 -p 443`;
          }
        }
      }
    }
  }

  # Process im_li_cnt hash
  foreach my $VISITOR (sort keys %im_li_cnt) {
    my $thisim_sumar = $im_li_cnt{$VISITOR};
    $im_sumar += $thisim_sumar;
    my $current_critnumber = $NGINX_DOS_LIMIT;
    my $current_mininumber = int(($current_critnumber + 1) / 2);  # Approx division by 2

    if ($thisim_sumar > $current_mininumber) {
      my $isloggedin = check_who($VISITOR);
      $current_critnumber = 9995 if ($isloggedin); # Don't block logged-in users
      $current_critnumber = 9994 if ($VISITOR eq $myip); # Don't block own IP

      print "===[$isloggedin] LOGGED im_li_cnt $VISITOR is logged in===\n" if ($isloggedin);
      print "===[$current_critnumber] MAX im_li_cnt critnumber for $VISITOR===\n" if ($VISITOR);
      print "===[$thisim_sumar] COUNTER im_li_cnt counter for $VISITOR===\n" if ($VISITOR);

      my $blocked = check_remote_ip($VISITOR, @banetable);
      my $allowed = check_own_ip($VISITOR, @local_ips_table);

      if ($thisim_sumar > $current_critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thisim_sumar] BLOCK im_li_cnt action for $VISITOR===\n" if ($VISITOR);
          `echo "$VISITOR # [x$thisim_sumar] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$VISITOR # [x$thisim_sumar] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $VISITOR 900 -p 80`;
            `/usr/sbin/csf -td $VISITOR 900 -p 443`;
          }
        }
      }
    }
  }

  # Process im_px_cnt hash
  foreach my $PROXY (sort keys %im_px_cnt) {
    my $thisim_sumarpx = $im_px_cnt{$PROXY};
    $im_sumarpx += $thisim_sumarpx;
    my $current_critnumber = $NGINX_DOS_LIMIT;
    my $current_mininumber = int(($current_critnumber + 1) / 2);  # Approx division by 2

    if ($thisim_sumarpx > $current_mininumber) {
      my $isloggedin = check_who($PROXY);
      $current_critnumber = 9993 if ($isloggedin); # Don't block logged-in users
      $current_critnumber = 9992 if ($PROXY eq $myip); # Don't block own IP

      print "===[$isloggedin] LOGGED im_px_cnt $PROXY is logged in===\n" if ($isloggedin);
      print "===[$current_critnumber] MAX im_px_cnt critnumber for $PROXY===\n" if ($PROXY);
      print "===[$thisim_sumarpx] COUNTER im_px_cnt counter for $PROXY===\n" if ($PROXY);

      my $blocked = check_remote_ip($PROXY, @banetable);
      my $allowed = check_own_ip($PROXY, @local_ips_table);

      if ($thisim_sumarpx > $current_critnumber) {
        if ($allowed ne 'ALLOWED' && !$blocked) {
          print "===[$thisim_sumarpx] BLOCK im_px_cnt action for $PROXY===\n" if ($PROXY);
          `echo "$PROXY # [x$thisim_sumarpx] $times" >> /var/xdrago/monitor/log/web.log`;
          `echo "$PROXY # [x$thisim_sumarpx] $times" >> /var/xdrago/monitor/log/$this_filename.archive.log`;
          if (-e "/etc/csf/csf.deny" && -e "/usr/sbin/csf" && !-e "/var/xdrago/guest-fire.sh") {
            `/usr/sbin/csf -td $PROXY 900 -p 80`;
            `/usr/sbin/csf -td $PROXY 900 -p 443`;
          }
        }
      }
    }
  }

  # Print summary counts
  print "===[$sumar] sumar===\n";
  print "===[$sumarpx] sumarpx===\n";
  print "===[$im_sumar] im_sumar===\n";
  print "===[$im_sumarpx] im_sumarpx===\n";

  # Clear hashes
  %li_cnt    = ();
  %px_cnt    = ();
  %im_li_cnt   = ();
  %im_px_cnt   = ();
}

#############################################################################
sub check_remote_ip {
  my ($IP, @banetable) = @_;
  my $blocked = 0;

  foreach my $banerecord (@banetable) {
    chomp($banerecord);
    my ($ifbanned, $rest) = split(/\s+/, $banerecord, 2);
    $ifbanned =~ s/[^0-9\.]//g;
    if ($ifbanned eq $IP) {
      $blocked = 1;
      last;
    }
  }

  return $blocked;
}

#############################################################################
sub check_who {
  my ($IP) = @_;
  my $isloggedin = 0;
  my @whotable = `who --ips | awk '{print \$5}'`;
  foreach my $whorecord (@whotable) {
    chomp($whorecord);
    my $whoip = $whorecord;
    $whoip =~ s/[^0-9\.]//g if defined $whoip;
    if (defined $whoip && $whoip eq $IP) {
      $isloggedin = 1;
      print "===[$IP] is AUTH OK===\n";
      last;
    }
  }
  return $isloggedin;
}

#############################################################################
sub check_own_ip {
  my ($IP, @local_ips_table) = @_;
  my $allowed = '';

  foreach my $record (@local_ips_table) {
    chomp($record);
    my ($ifallowed, $rest) = split(/\s+/, $record, 2);
    $ifallowed =~ s/[^0-9\.]//g;
    if ($ifallowed eq $IP) {
      $allowed = "ALLOWED";
      print "===[$IP] is MY OK===\n";
      last;
    }
  }

  return $allowed;
}
###EOF2024###
