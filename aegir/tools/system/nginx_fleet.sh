#!/bin/bash

# nginx_fleet.sh -- detect distributed crawler fleets by the fingerprint they
# share, and refuse them at nginx with 429.
#
# A fleet rotates hundreds of addresses, so no per-address scorer ever sees
# more than a few dozen requests from one of them. What it cannot rotate is
# the thing it shares: one exact user agent, walking one route class of one
# vhost, from many addresses at once, without a Referer and with a different
# URL on almost every request. Each run reads the last few minutes of the
# access log, declares a (vhost, user agent) fingerprint when one route class
# passes every gate, records the addresses seen acting as members, and
# renders three exact-match include fragments consumed by the $boa_fleet_*
# maps in /etc/nginx/conf.d/limit-req-zones-boa.conf.
#
# The block is deliberately narrow. A browser-shaped (or any non-crawler)
# agent is refused only from an address already seen acting as a member, only
# with that exact agent, only without a Referer and only when no session
# cookie is present, so a real visitor sharing the string passes by following
# any link or by logging in. Only an agent that names itself a crawler and is
# not browser-shaped is refused per /16 of its observed members, because no
# human browses with it. Keys are exact strings (nginx compares them case
# insensitively), never regexes built from a user agent.
#
# 429 because no scan_nginx scorer counts it: a fleet refusal must never feed
# the per-address ban score, the UA-burst csf ban or the i18n shedding signal.
#
# On by default on every box. One action per scope, so either can be loosened
# alone after a confirmed false positive (/root/.barracuda.cnf):
#   _NGINX_FLEET_ACTION          address scope: browser-shaped agents and
#                                every agent that does not name itself a
#                                crawler (BAN or REPORT, default BAN)
#   _NGINX_FLEET_CRAWLER_ACTION  network scope: self-declared crawler names
#                                (BAN or REPORT; empty inherits the above)
# A scope in REPORT logs WOULD-BAN and neither stores nor renders its
# fingerprints or members; a scope in BAN stores and renders them. Moving a
# scope from BAN to REPORT releases it on the next run.
#
# Sole writer of the store and the fragments. Runs every minute from root cron.
#
# Store /var/xdrago/monitor/log/fleet.tempban (pruned on every run):
#   F|<expiry>|<host>|<A or N>|<b64 lower-cased agent>   fingerprint + scope
#   A|<expiry>|<host>|<address>|<b64 agent>              member address
#   N|<expiry>|<host>|<a.b or IPv6>|<b64 agent>          member network
# Members are rendered only while their fingerprint is live, so a fingerprint
# expiry releases all of its members in one reload.
#
# Usage:
#   nginx_fleet.sh             one detection + render pass
#   nginx_fleet.sh --replay [--action REPORT|BAN] [--crawler-action REPORT|BAN]
#                  [--flags FILE] [--allow CSF] [--dump DIR] LOG...
#       read-only chronological replay of saved logs: prints what would have
#       been declared and refused, per fingerprint and per scope. Both scopes
#       replay as BAN unless --action / --crawler-action say otherwise (an
#       empty --crawler-action inherits --action); the action knobs in the cnf
#       are not applied, so a replay on a loosened box still shows what BAN
#       would refuse. --flags writes one 0/1 line per input line, --dump writes
#       the peak map fragments.
#   nginx_fleet.sh -h | --help

export HOME='/root'
export PATH='/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin'
export LC_ALL=C

_CONFIG_FILE="/root/.barracuda.cnf"

# Defaults, overridden in /root/.barracuda.cnf. Every value is validated below.
_NGINX_FLEET_DETECT="YES"
_NGINX_FLEET_ACTION="BAN"
_NGINX_FLEET_CRAWLER_ACTION=""
_NGINX_FLEET_WINDOW=300
_NGINX_FLEET_MIN_SPAN=180
_NGINX_FLEET_TAIL_MB=64
_NGINX_FLEET_IP_MIN=32
_NGINX_FLEET_REQ_MIN=48
_NGINX_FLEET_SHARE_PCT=8
_NGINX_FLEET_NOREF_PCT=95
_NGINX_FLEET_UNIQ_PCT=80
_NGINX_FLEET_BAD_PCT=5
_NGINX_FLEET_ALLOW_PCT=20
_NGINX_FLEET_CAND_IPS=16
_NGINX_FLEET_NET_MIN_IPS=2
_NGINX_FLEET_TTL=3600
_NGINX_FLEET_MEMBER_TTL=21600
_NGINX_FLEET_RELOAD_GAP=600
_NGINX_FLEET_MAX_FP=16
_NGINX_FLEET_MAX_ENTRIES=20000
_NGINX_FLEET_UA_EXEMPT=""

if [[ -e "${_CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${_CONFIG_FILE}"
fi

# Paths and internals are set after the cnf is sourced, so no cnf variable can
# redirect what this script reads or writes.
_ACCESS_LOG="/var/log/nginx/access.log"
_LOG_DIR="/var/xdrago/monitor/log"
_STORE="${_LOG_DIR}/fleet.tempban"
_FLEET_LOG="${_LOG_DIR}/fleet.log"
_CLEAR_STAMP="${_LOG_DIR}/.fleet.clear.stamp"
_RELOAD_STAMP="${_LOG_DIR}/.fleet.reload.stamp"
_CSF_ALLOW="/etc/csf/csf.allow"
_WEB6_ALLOW="${_LOG_DIR}/web6.allow"
_MYIP_FILE="/root/.found_correct_ipv4.cnf"
_ZONES_FILE="/etc/nginx/conf.d/limit-req-zones-boa.conf"
_OUT_DIR="/data/conf"
_SELF_LOCK="/run/boa_nginx_fleet.lock"
_NGX_LOCK="/run/boa_nginx_config.lock"
_MODE="pass"

# The shipped exemption roster: the harvest detector's crawler and monitor list
# plus the allow-by-default AI classes and user-driven link previewers, which
# the AI policy governs with its own per-vendor aggregate limits. Set after the
# cnf is sourced so it cannot be clobbered. An operator _NGINX_FLEET_UA_EXEMPT
# ADDS to it and can never remove a shipped exemption; an invalid addition is
# dropped and the shipped roster alone applies.
_FLT_UA_EXEMPT_DEFAULT="Googlebot|Google-|GoogleOther|Google Favicon|Mediapartners-Google|AdsBot|Storebot-Google|bingbot|Applebot|DuckDuckBot|Yandex|Baiduspider|SeznamBot|PetalBot|Qwantbot|coccocbot|Yeti|Sogou|archive\.org_bot|facebookexternalhit|Twitterbot|LinkedInBot|Slackbot|Discordbot|TelegramBot|Pinterest|Site24x7|Pingdom|UptimeRobot|StatusCake|OAI-SearchBot|Claude-SearchBot|PerplexityBot|MistralAI-Index|YouBot|Google-CloudVertexBot|ChatGPT-User|Claude-User|MistralAI-User|Meta-ExternalFetcher|Google-?Agent|OAI-AdsBot|DuckAssistBot|Google-Read-Aloud|Google-NotebookLM|Chrome Privacy Preserving Prefetch Proxy|WhatsApp|SkypeUriPreview|kakaotalk-scrap"
if [[ -n "${_NGINX_FLEET_UA_EXEMPT}" ]]; then
  _NGINX_FLEET_UA_EXEMPT="${_FLT_UA_EXEMPT_DEFAULT}|${_NGINX_FLEET_UA_EXEMPT}"
else
  _NGINX_FLEET_UA_EXEMPT="${_FLT_UA_EXEMPT_DEFAULT}"
fi

_fleet_usage() {
  sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# Printable, short copy of an operator value for a CONFIG line.
_fleet_show() {
  printf '%s' "$1" | tr -cd '[:alnum:]._-' | cut -c1-24
}

_fleet_note() {
  echo "$*"
  if [[ "${_MODE}" = "pass" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S' 2> /dev/null) $*" >> "${_FLEET_LOG}" 2> /dev/null
  fi
}

_REPLAY_FLAGS=""
_REPLAY_ALLOW="${_CSF_ALLOW}"
_REPLAY_DUMP=""
_REPLAY_ACTION="BAN"
_REPLAY_CRAWLER_ACTION=""
_REPLAY_OPTS=0
_REPLAY_FILES=()
while (( $# )); do
  case "$1" in
    --replay)
      _MODE="replay"
      shift
      ;;
    --flags|--allow|--dump|--action|--crawler-action)
      if (( $# < 2 )); then
        echo "ERROR: $1 needs a value" >&2
        exit 1
      fi
      case "$1" in
        --flags)          _REPLAY_FLAGS="$2" ;;
        --allow)          _REPLAY_ALLOW="$2" ;;
        --dump)           _REPLAY_DUMP="$2" ;;
        --action)         _REPLAY_ACTION="$2" ;;
        --crawler-action) _REPLAY_CRAWLER_ACTION="$2" ;;
      esac
      _REPLAY_OPTS=1
      shift 2
      ;;
    -h|--help)
      _fleet_usage
      exit 0
      ;;
    *)
      if [[ "${_MODE}" != "replay" ]]; then
        echo "ERROR: unknown option: $1" >&2
        exit 1
      fi
      _REPLAY_FILES+=("$1")
      shift
      ;;
  esac
done
if [[ "${_MODE}" = "pass" ]] && (( _REPLAY_OPTS )); then
  echo "ERROR: --flags, --allow, --dump, --action and --crawler-action need --replay" >&2
  exit 1
fi

# A bad override only discards the custom value; the job always runs on the
# shipped default, and an out-of-range value is as invalid as a non-number, so
# a typo can never turn the gates into a hair trigger.
_fleet_int() {
  local _name="$1" _def="$2" _min="$3" _max="$4" _val
  _val="${!_name}"
  if [[ ! "${_val}" =~ ^[0-9]{1,9}$ ]] || (( 10#${_val} < _min || 10#${_val} > _max )); then
    _fleet_note "CONFIG: ${_name}=$(_fleet_show "${_val}") is invalid, using ${_def}"
    printf -v "${_name}" '%s' "${_def}"
    return 0
  fi
  printf -v "${_name}" '%d' "$(( 10#${_val} ))"
}

_fleet_knobs() {
  _fleet_int _NGINX_FLEET_WINDOW 300 180 900
  _fleet_int _NGINX_FLEET_MIN_SPAN 180 60 900
  _fleet_int _NGINX_FLEET_TAIL_MB 64 8 512
  _fleet_int _NGINX_FLEET_IP_MIN 32 12 100000
  _fleet_int _NGINX_FLEET_REQ_MIN 48 24 1000000
  _fleet_int _NGINX_FLEET_SHARE_PCT 8 2 100
  _fleet_int _NGINX_FLEET_NOREF_PCT 95 50 100
  _fleet_int _NGINX_FLEET_UNIQ_PCT 80 50 100
  _fleet_int _NGINX_FLEET_BAD_PCT 5 0 100
  _fleet_int _NGINX_FLEET_ALLOW_PCT 20 1 100
  _fleet_int _NGINX_FLEET_CAND_IPS 16 4 100000
  _fleet_int _NGINX_FLEET_NET_MIN_IPS 2 2 1000
  _fleet_int _NGINX_FLEET_TTL 3600 600 86400
  _fleet_int _NGINX_FLEET_MEMBER_TTL 21600 600 604800
  _fleet_int _NGINX_FLEET_RELOAD_GAP 600 0 3600
  _fleet_int _NGINX_FLEET_MAX_FP 16 1 64
  _fleet_int _NGINX_FLEET_MAX_ENTRIES 20000 100 100000
  if (( _NGINX_FLEET_MIN_SPAN > _NGINX_FLEET_WINDOW )); then
    _fleet_note "CONFIG: _NGINX_FLEET_MIN_SPAN exceeds _NGINX_FLEET_WINDOW, using 180"
    _NGINX_FLEET_MIN_SPAN=180
  fi
  case "${_NGINX_FLEET_DETECT}" in
    YES|NO) : ;;
    *)
      _fleet_note "CONFIG: _NGINX_FLEET_DETECT=$(_fleet_show "${_NGINX_FLEET_DETECT}") must be YES or NO, using YES"
      _NGINX_FLEET_DETECT="YES"
      ;;
  esac
  # The refusal ships on everywhere, so a typo must never switch it off
  # silently. Case is not significant; any other invalid address action falls
  # back to the shipped BAN with a CONFIG line, and an invalid crawler action
  # inherits the (already validated) address action.
  local _act="${_NGINX_FLEET_ACTION^^}" _cract="${_NGINX_FLEET_CRAWLER_ACTION^^}"
  case "${_act}" in
    REPORT|BAN) _NGINX_FLEET_ACTION="${_act}" ;;
    *)
      _fleet_note "CONFIG: _NGINX_FLEET_ACTION=$(_fleet_show "${_NGINX_FLEET_ACTION}") must be BAN or REPORT, using BAN"
      _NGINX_FLEET_ACTION="BAN"
      ;;
  esac
  case "${_cract}" in
    REPORT|BAN) _NGINX_FLEET_CRAWLER_ACTION="${_cract}" ;;
    "")
      _NGINX_FLEET_CRAWLER_ACTION="${_NGINX_FLEET_ACTION}"
      ;;
    *)
      _fleet_note "CONFIG: _NGINX_FLEET_CRAWLER_ACTION=$(_fleet_show "${_NGINX_FLEET_CRAWLER_ACTION}") must be BAN, REPORT or empty, inheriting _NGINX_FLEET_ACTION=${_NGINX_FLEET_ACTION}"
      _NGINX_FLEET_CRAWLER_ACTION="${_NGINX_FLEET_ACTION}"
      ;;
  esac
}

# SECURITY: every byte after the first quote of a log line is attacker
# controlled. The program is a quoted here-doc, so the shell interpolates
# nothing into it; it opens the log and the store itself; its arguments are
# integers validated above, paths this script built and the operator pattern
# as base64. Agents travel base64 in the store, are compared with eq, and reach
# a fragment only after a strict printable-ASCII grammar check. Nothing derived
# from the log is ever used as a regex, a path or a shell word.
read -r -d '' _FLT_PL <<'_FLT_PERL_EOF'
use strict;
use warnings;
use MIME::Base64 ();
use Digest::MD5 ();
use Socket ();

my (%A, @FILES);
for my $arg (@ARGV) {
  my ($k, $v) = split /=/, $arg, 2;
  next unless defined $v;
  if ($k eq 'file') { push @FILES, $v; next; }
  $A{$k} = $v;
}
my $MODE = $A{mode} // 'pass';
my %K;
for my $k (qw(now window min_span tail_bytes ip_min req_min share_pct noref_pct uniq_pct
              bad_pct allow_pct cand_ips net_min_ips ttl member_ttl reload_gap max_fp
              max_entries since ban_a ban_n detect)) {
  my $v = $A{$k} // '0';
  $K{$k} = ($v =~ /\A[0-9]{1,12}\z/) ? $v + 0 : 0;
}
# Internal bounds, not knobs. KEY_MAX: nginx hashes an exact map key only when
# pointer + align8(len + 2) fits in map_hash_bucket_size minus a pointer; the
# master render sets 192, so 174 bytes on x86_64. MEM_MAX bounds one pass.
my $KEY_MAX = 174;
my $MEM_MAX = 2000;
my $MYIP = $A{myip} // '';
my @LOG;

my $EXEMPT;
{
  my $src = MIME::Base64::decode_base64($A{exempt_b64} // '');
  my $def = MIME::Base64::decode_base64($A{exempt_default_b64} // '');
  $EXEMPT = eval { qr/$src/ } if length $src;
  unless (defined $EXEMPT) {
    push @LOG, 'CONFIG: _NGINX_FLEET_UA_EXEMPT is not a valid pattern, using the shipped roster' if length $src;
    $EXEMPT = eval { qr/$def/ };
  }
}

my $B64RE  = qr/\A[A-Za-z0-9+\/]{4,260}={0,2}\z/;
my $OCT    = qr/(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])/;
my $V4RE   = qr/\A$OCT\.$OCT\.$OCT\.$OCT\z/;
my $NETRE  = qr/\A$OCT\.$OCT\z/;
my $HOSTRE = qr/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\z/;
# Map-safe agent grammar, applied to the lower-cased agent: printable ASCII,
# no double quote, apostrophe, backslash, dollar, brace, hash, pipe or angle
# bracket, first byte alphanumeric (never ~regex or \escape), no trailing
# space (nginx trims header values, so such a key could never match).
my $UARE   = qr/\A[a-z0-9][a-z0-9 ()\/;:.,_+=*!?~\@%&\[\]-]{0,173}(?<! )\z/;
my $LRE    = qr/\A"([^"]*)" (\S+) \[([^\]]+)\] "(\S+) (\S+)[^"]*" (\d{3}) \d+ \d+ \d+ "([^"]*)" "([^"]*)"/;
my %MON = (Jan=>1,Feb=>2,Mar=>3,Apr=>4,May=>5,Jun=>6,Jul=>7,Aug=>8,Sep=>9,Oct=>10,Nov=>11,Dec=>12);

sub show {
  my $x = shift // '';
  $x =~ tr/\x20-\x7e//cd;
  return substr($x, 0, 180);
}
sub b64 { return MIME::Base64::encode_base64($_[0], ''); }

# A = address scope, N = network scope; each follows its own action knob.
sub scope_ban { return (($_[0] eq 'N') ? $K{ban_n} : $K{ban_a}) ? 1 : 0; }

sub days_from_civil {
  my ($y, $m, $d) = @_;
  $y -= 1 if $m <= 2;
  my $era = int($y / 400);
  my $yoe = $y - $era * 400;
  my $doy = int((153 * ($m > 2 ? $m - 3 : $m + 9) + 2) / 5) + $d - 1;
  my $doe = $yoe * 365 + int($yoe / 4) - int($yoe / 100) + $doy;
  return $era * 146097 + $doe - 719468;
}
my %TC;
sub ts_epoch {
  my $ts = shift;
  my $e = $TC{$ts};
  return $e if defined $e;
  $e = 0;
  if ($ts =~ m{\A(\d{2})/([A-Z][a-z]{2})/(\d{4}):(\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})\z} && $MON{$2}) {
    $e = days_from_civil($3, $MON{$2}, $1) * 86400 + $4 * 3600 + $5 * 60 + $6
       - ($7 eq '+' ? 1 : -1) * ($8 * 3600 + $9 * 60);
  }
  %TC = () if scalar(keys %TC) > 200000;
  return $TC{$ts} = $e;
}

sub v6bin {
  my $a = shift;
  return undef unless defined $a && $a =~ /\A[0-9A-Fa-f:.]{2,45}\z/ && $a =~ /:/;
  return Socket::inet_pton(Socket::AF_INET6(), $a);
}
sub prefix_eq {
  my ($x, $y, $bits) = @_;
  my $full = int($bits / 8);
  return 0 if substr($x, 0, $full) ne substr($y, 0, $full);
  my $rem = $bits % 8;
  return 1 unless $rem;
  my $m = (0xFF << (8 - $rem)) & 0xFF;
  return ((ord(substr($x, $full, 1)) & $m) == (ord(substr($y, $full, 1)) & $m)) ? 1 : 0;
}
# Client address: the last token of the first field, the scan_nginx rule. Only
# a valid public address is returned; loopback is the wild-ssl backend's copy
# of a request already logged at the front with the real client.
sub client_ip {
  my @t = split /[,\s]+/, shift;
  my $ip = $t[-1] // return undef;
  if ($ip =~ $V4RE) {
    return undef if $ip =~ /\A(?:0\.|10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2[0-9]|3[01])\.)/;
    return $ip;
  }
  my $b = v6bin($ip) // return undef;
  my $f = ord(substr($b, 0, 1));
  my $s = ord(substr($b, 1, 1));
  return undef if ($f & 0xFE) == 0xFC || ($f == 0xFE && ($s & 0xC0) == 0x80)
    || $b eq ("\0" x 15) . "\1" || $b eq "\0" x 16;
  return lc $ip;
}

my (%WL4, %WL16, @WLC4, @WL6, %WLC);
sub load_allow {
  my ($csf, $w6) = @_;
  if (defined $csf && length $csf && open my $fh, '<', $csf) {
    while (my $l = <$fh>) {
      next if $l =~ /\A\s*#/;
      next unless $l =~ /s=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(?:\/([0-9]+))?/;
      my ($ad, $bits) = ($1, $2);
      my @o = split /\./, $ad;
      next if grep { $_ > 255 } @o;
      my $n = ($o[0] << 24) + ($o[1] << 16) + ($o[2] << 8) + $o[3];
      if (!defined $bits || $bits == 32) { $WL4{"$o[0].$o[1].$o[2].$o[3]"} = 1; $WL16{"$o[0].$o[1]"} = 1; next; }
      next if $bits < 1 || $bits > 31;
      my $m = (0xFFFFFFFF << (32 - $bits)) & 0xFFFFFFFF;
      push @WLC4, [$n & $m, $m];
    }
    close $fh;
  }
  if (defined $w6 && length $w6 && open my $fh, '<', $w6) {
    while (my $l = <$fh>) {
      $l =~ s/#.*//s;
      $l =~ s/\s+//g;
      next unless length $l;
      my ($ad, $bits) = split m{/}, $l, 2;
      $bits = 128 unless defined $bits;
      next unless $bits =~ /\A[0-9]{1,3}\z/ && $bits >= 1 && $bits <= 128;
      my $p = v6bin($ad) // next;
      push @WL6, [$p, $bits];
    }
    close $fh;
  }
}
sub is_wl {
  my $ip = shift;
  return 1 if $ip eq $MYIP;
  return $WLC{$ip} if exists $WLC{$ip};
  my $r = 0;
  if ($ip =~ /:/) {
    my $b = v6bin($ip);
    if (defined $b) { for my $e (@WL6) { if (prefix_eq($b, $e->[0], $e->[1])) { $r = 1; last; } } }
  } elsif ($WL4{$ip}) {
    $r = 1;
  } else {
    my @o = split /\./, $ip;
    my $n = ($o[0] << 24) + ($o[1] << 16) + ($o[2] << 8) + $o[3];
    for my $e (@WLC4) { if (($n & $e->[1]) == $e->[0]) { $r = 1; last; } }
  }
  %WLC = () if scalar(keys %WLC) > 500000;
  return $WLC{$ip} = $r;
}
# A /16 that holds any trusted entry is never banned as a network.
sub net_trusted {
  my $nt = shift;
  return 1 if $WL16{$nt};
  my ($a, $b) = split /\./, $nt;
  my $n16 = ($a << 24) + ($b << 16);
  for my $e (@WLC4) {
    my $m = $e->[1] & 0xFFFF0000;
    return 1 if ($e->[0] & $m) == ($n16 & $m);
  }
  if ($MYIP =~ /\A(\d+\.\d+)\./) { return 1 if $1 eq $nt; }
  return 0;
}

sub internal_host {
  return $_[0] =~ /(?:\A|\.)files\.(?:boa\.io|o8\.io|host8\.biz|aegir\.cc|aegir\.biz|aoboshi\.com)\z/ ? 1 : 0;
}
# Route class: the first path segment after an optional language prefix, on
# the path nginx itself would route (percent-decoded, slashes merged, dot
# segments resolved, lower-cased), so case or encoding games on the first
# segment cannot split one crawl into many small classes.
sub route_class {
  my $p = shift;
  $p =~ s/[?#].*\z//s;
  $p =~ s{\A[A-Za-z][A-Za-z0-9+.-]*://[^/]*}{};
  $p = '/' if $p eq '';
  return undef unless substr($p, 0, 1) eq '/';
  $p =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
  $p = lc $p;
  my $trail = $p =~ m{/\z} ? 1 : 0;
  my @out;
  for my $s (split m{/+}, $p) {
    next if $s eq '' || $s eq '.';
    if ($s eq '..') { pop @out; next; }
    push @out, $s;
  }
  shift @out if @out && $out[0] =~ /\A[a-z]{2}(?:-[a-z]+)?\z/ && (@out > 1 || $trail);
  my $c = substr($out[0] // '', 0, 64);
  # Dot names and machine-standard files belong to other controls.
  return undef if $c =~ /\A\./ || $c =~ /\A(?:robots\.txt|sitemap\.xml|favicon\.ico|ads\.txt|apple-app-site-association)\z/;
  return $c;
}
my %EXC;
sub exempt_ua {
  my $u = shift;
  return $EXC{$u} if exists $EXC{$u};
  %EXC = () if scalar(keys %EXC) > 100000;
  return $EXC{$u} = (defined $EXEMPT && $u =~ $EXEMPT) ? 1 : 0;
}
# Record: [epoch, ip, host, ua_lc, ua, class, noref, status, target, exempt]
# ip is '' and class undef when the line may be enforced but never counted.
sub build_rec {
  my $l = shift;
  my ($ipf, $host, $ts, undef, $target, $st, $ref, $ua) = $l =~ $LRE or return undef;
  my $e = ts_epoch($ts) or return undef;
  $host = lc $host;
  my $ip = client_ip($ipf) // '';
  my $cls;
  if ($ip ne '' && length($host) <= 120 && $host =~ $HOSTRE && !internal_host($host)
      && $ua ne '' && $ua ne '-') {
    $cls = route_class($target);
  }
  return [$e, $ip, $host, lc $ua, $ua, $cls, ($ref eq '-' || $ref eq '') ? 1 : 0, $st, $target,
          defined $cls ? exempt_ua($ua) : 0];
}
# Scope from the lower-cased agent. Anything browser-shaped, and anything that
# does not name itself a crawler, gets the per-address scope; only a
# self-declared crawler that is not browser-shaped gets the /16 scope.
sub scope_of {
  my $u = shift;
  return 'A' if $u =~ m{\Amozilla/5\.0 \([^()]+\) (?:applewebkit/[0-9.]+ \(khtml, like gecko\)|gecko/[0-9]+ )};
  return 'N' if $u =~ /bot|crawl|spider|slurp|scrap|headless|https?:/;
  return 'A';
}

sub analyse {
  my ($recs, $cut, $now) = @_;
  my (%hn, %kn, %kip, %knr, %kurl, %kbad, %kwl, %gip, %gnr, %gwl, %gex, %orig);
  for my $r (@$recs) {
    next if $r->[0] < $cut || $r->[0] > $now || !defined $r->[5];
    my $host = $r->[2];
    $hn{$host}++;
    my $g = $host . "\x1f" . $r->[3];
    my $k = $g . "\x1f" . $r->[5];
    my $ip = $r->[1];
    $gex{$g} = 1 if $r->[9];
    if (is_wl($ip)) { $gwl{$g}{$ip} = 1; $kwl{$k}{$ip} = 1; next; }
    $kn{$k}++;
    $kip{$k}{$ip} = 1;
    $knr{$k} += $r->[6];
    $kurl{$k}{$r->[8]} = 1;
    $kbad{$k}++ if $r->[7] =~ /\A5/ || $r->[7] eq '444';
    $gip{$g}{$ip}++;
    $gnr{$g}{$ip} += $r->[6];
    $orig{$g} //= $r->[4];
  }
  my %decl;
  for my $k (keys %kn) {
    my $n = $kn{$k};
    next if $n < $K{req_min};
    my $ni = scalar keys %{$kip{$k}};
    next if $ni < $K{ip_min};
    my ($host, $ual, $cls) = split /\x1f/, $k, 3;
    next if 100 * $n < $K{share_pct} * $hn{$host};
    next if 100 * $knr{$k} < $K{noref_pct} * $n;
    my $nu = scalar keys %{$kurl{$k}};
    next if 100 * $nu < $K{uniq_pct} * $n;
    my $nb = $kbad{$k} // 0;
    next if 100 * $nb > $K{bad_pct} * $n;
    my $g = $host . "\x1f" . $ual;
    my $stat = sprintf('class=/%s ips=%d reqs=%d share=%d%% noref=%d%% uniq=%d%% bad=%d%%',
      show($cls), $ni, $n, int(100 * $n / $hn{$host}), int(100 * $knr{$k} / $n),
      int(100 * $nu / $n), int(100 * $nb / $n));
    if ($gex{$g}) { push @LOG, "EXEMPT host=$host $stat ua=" . show($orig{$g}); next; }
    my $wl = scalar keys %{$kwl{$k} // {}};
    if (100 * $wl >= $K{allow_pct} * ($wl + $ni)) {
      push @LOG, "REALIP-SUSPECT host=$host $stat whitelisted=$wl ua=" . show($orig{$g});
      next;
    }
    $decl{$g} = [$n, $stat] if !$decl{$g} || $n > $decl{$g}[0];
  }
  return (\%decl, \%gip, \%gnr, \%gwl, \%orig);
}

sub members {
  my ($g, $scope, $gip, $gnr, $gwl) = @_;
  my $ips = $gip->{$g} // {};
  my @ips = sort { $ips->{$b} <=> $ips->{$a} || $a cmp $b } keys %$ips;
  splice(@ips, $MEM_MAX) if @ips > $MEM_MAX;
  my (@addr, @net, %n16);
  for my $ip (@ips) {
    if ($scope eq 'A') {
      push @addr, $ip if 100 * $gnr->{$g}{$ip} >= $K{noref_pct} * $ips->{$ip};
    } elsif ($ip =~ /\A(\d+\.\d+)\./) {
      $n16{$1}++;
    } else {
      push @net, $ip;
    }
  }
  if (%n16) {
    my %held;
    for my $w (keys %{$gwl->{$g} // {}}) { $held{$1} = 1 if $w =~ /\A(\d+\.\d+)\./; }
    for my $nt (sort keys %n16) {
      push @net, $nt if $n16{$nt} >= $K{net_min_ips} && !$held{$nt} && !net_trusted($nt);
    }
  }
  return (\@addr, \@net);
}

# A fingerprint whose scope is in REPORT is not loaded, so switching a scope
# from BAN to REPORT drops it and store_prune then drops its members.
sub store_load {
  my ($path, $now) = @_;
  my $S = { F => {}, M => {} };
  return $S unless defined $path && length $path && open my $fh, '<', $path;
  while (my $l = <$fh>) {
    chomp $l;
    my @f = split /\|/, $l, -1;
    next unless @f == 5 && $f[1] =~ /\A[0-9]{1,12}\z/ && $f[1] > $now;
    my ($kind, $exp, $host, $x, $b) = @f;
    next unless length($host) <= 120 && $host =~ $HOSTRE && $b =~ $B64RE;
    if ($kind eq 'F') {
      next unless ($x eq 'A' || $x eq 'N') && scope_ban($x);
      my $o = $S->{F}{"$host|$b"};
      $S->{F}{"$host|$b"} = [$exp, $x] if !$o || $exp > $o->[0];
    } elsif (($kind eq 'A' && ($x =~ $V4RE || defined v6bin($x)))
          || ($kind eq 'N' && ($x =~ $NETRE || defined v6bin($x)))) {
      my $mk = "$kind|$host|" . lc($x) . "|$b";
      $S->{M}{$mk} = $exp if !$S->{M}{$mk} || $exp > $S->{M}{$mk};
    }
  }
  close $fh;
  return $S;
}

sub map_safe {
  my $ua = shift;
  return ($ua =~ $UARE && $ua !~ /\A(?:default|include|hostnames|volatile)\z/
    && length($ua) <= $KEY_MAX) ? 1 : 0;
}

sub store_apply {
  my ($S, $now, $decl, $gip, $gnr, $gwl, $orig) = @_;
  for my $g (sort keys %$decl) {
    my ($host, $ual) = split /\x1f/, $g, 2;
    my $fk = "$host|" . b64($ual);
    my $scope = $S->{F}{$fk} ? $S->{F}{$fk}[1] : scope_of($ual);
    my $ban = scope_ban($scope);
    # An agent no exact key can carry is reported, never stored: it could not
    # be refused anyway, and a stored one would take a _NGINX_FLEET_MAX_FP slot
    # that a refusable fleet needs (an attacker could crowd the cap with them).
    unless (map_safe($ual)) {
      push @LOG, sprintf('UNBANNABLE host=%s scope=%s %s ua=%s -- outside the map-safe grammar, reported only',
        $host, $scope, $decl->{$g}[1], show($orig->{$g}));
      next;
    }
    push @LOG, sprintf('%s host=%s scope=%s %s ua=%s', ($ban ? 'DECLARE' : 'WOULD-BAN'),
      $host, $scope, $decl->{$g}[1], show($orig->{$g}));
    next unless $ban;
    $S->{F}{$fk} = [$now + $K{ttl}, $scope];
  }
  return unless $K{ban_a} || $K{ban_n};
  for my $g (sort keys %$gip) {
    my ($host, $ual) = split /\x1f/, $g, 2;
    my $b = b64($ual);
    my $F = $S->{F}{"$host|$b"} or next;
    next unless $F->[0] > $now;
    next unless $decl->{$g} || scalar(keys %{$gip->{$g}}) >= $K{cand_ips};
    my ($addr, $net) = members($g, $F->[1], $gip, $gnr, $gwl);
    my $kind = $F->[1];
    for my $x ($kind eq 'A' ? @$addr : @$net) {
      $S->{M}{"$kind|$host|$x|$b"} = $now + $K{member_ttl};
    }
  }
}

sub store_prune {
  my ($S, $now) = @_;
  for my $fk (keys %{$S->{F}}) {
    delete $S->{F}{$fk} unless $S->{F}{$fk}[0] > $now && scope_ban($S->{F}{$fk}[1]);
  }
  my @live = sort { $S->{F}{$b}[0] <=> $S->{F}{$a}[0] || $a cmp $b } keys %{$S->{F}};
  if (@live > $K{max_fp}) {
    for my $fk (@live[$K{max_fp} .. $#live]) {
      my ($host) = split /\|/, $fk, 2;
      push @LOG, "CAP host=$host fingerprint dropped, _NGINX_FLEET_MAX_FP=$K{max_fp} reached";
      delete $S->{F}{$fk};
    }
  }
  for my $mk (keys %{$S->{M}}) {
    my ($kind, $host, $x, $b) = split /\|/, $mk, 4;
    my $F = $S->{F}{"$host|$b"};
    delete $S->{M}{$mk} unless $S->{M}{$mk} > $now && $F && $F->[1] eq $kind;
  }
}

sub store_text {
  my $S = shift;
  my @o;
  for my $fk (sort keys %{$S->{F}}) {
    my ($host, $b) = split /\|/, $fk, 2;
    push @o, "F|$S->{F}{$fk}[0]|$host|$S->{F}{$fk}[1]|$b\n";
  }
  for my $mk (sort keys %{$S->{M}}) {
    my ($kind, $host, $x, $b) = split /\|/, $mk, 4;
    push @o, "$kind|$S->{M}{$mk}|$host|$x|$b\n";
  }
  return join '', @o;
}

my %UNBANNABLE_SEEN;
sub render {
  my $S = shift;
  my (%live, %idua, %uaid, %addr, %net);
  for my $fk (sort keys %{$S->{F}}) {
    my ($host, $b) = split /\|/, $fk, 2;
    my $ua = MIME::Base64::decode_base64($b);
    unless (map_safe($ua)) {
      push @LOG, "UNBANNABLE host=$host ua=" . show($ua) . ' -- outside the map-safe grammar, reported only'
        unless $UNBANNABLE_SEEN{$fk}++;
      next;
    }
    my $id = 'f' . substr(Digest::MD5::md5_hex($ua), 0, 8);
    next if exists $idua{$id} && $idua{$id} ne $ua;
    $idua{$id} = $ua;
    $uaid{$ua} = $id;
    $live{$fk} = [$id, $S->{F}{$fk}[1]];
  }
  for my $mk (keys %{$S->{M}}) {
    my ($kind, $host, $x, $b) = split /\|/, $mk, 4;
    my $L = $live{"$host|$b"} or next;
    next unless $L->[1] eq $kind;
    my $key = "$host|$x|$L->[0]";
    next if length($key) > $KEY_MAX;
    ($kind eq 'A' ? \%addr : \%net)->{$key} = $S->{M}{$mk};
  }
  my %txt;
  my $hdr = "# generated by /var/xdrago/nginx_fleet.sh -- DO NOT EDIT BY HAND.\n";
  $txt{ua} = $hdr . join('', map { "\"$_\" $uaid{$_};\n" } sort keys %uaid);
  my %cnt = (fp => scalar(keys %live), ua => scalar(keys %uaid));
  for my $spec (['addr', \%addr], ['net', \%net]) {
    my ($name, $h) = @$spec;
    my @k = sort { $h->{$b} <=> $h->{$a} || $a cmp $b } keys %$h;
    if (@k > $K{max_entries}) {
      push @LOG, "CAP $name map holds the newest $K{max_entries} of " . scalar(@k) . ' entries';
      splice(@k, $K{max_entries});
    }
    $txt{$name} = $hdr . join('', map { "\"$_\" 1;\n" } sort @k);
    $cnt{$name} = scalar @k;
  }
  return (\%txt, \%cnt);
}

sub write_file {
  my ($path, $body) = @_;
  open my $fh, '>', $path or return 0;
  print $fh $body;
  return close($fh) ? 1 : 0;
}

if ($MODE eq 'pass') {
  load_allow($A{csf_allow}, $A{web6_allow});
  my $now = $K{now};
  my $any_ban = ($K{ban_a} || $K{ban_n}) ? 1 : 0;
  my ($decl, $gip, $gnr, $gwl, $orig) = ({}, {}, {}, {}, {});
  if ($K{detect} && defined $A{log} && open my $fh, '<', $A{log}) {
    my $size = -s $fh;
    my $start = $size > $K{tail_bytes} ? $size - $K{tail_bytes} : 0;
    seek $fh, $start, 0;
    <$fh> if $start > 0;
    my (@recs, $lo);
    my $cut = $now - $K{window};
    while (tell($fh) < $size) {
      my $l = <$fh>;
      last unless defined $l;
      next unless substr($l, -1) eq "\n";
      my ($ts) = $l =~ /\[([^\]]+)\]/ or next;
      my $e = ts_epoch($ts) or next;
      next if $e < $K{since};
      $lo //= $e;
      next if $e < $cut || $e > $now;
      my $r = build_rec($l) or next;
      push @recs, $r;
    }
    close $fh;
    if (defined $lo && $now - $lo >= $K{min_span}) {
      ($decl, $gip, $gnr, $gwl, $orig) = analyse(\@recs, $cut, $now);
    } elsif ($start > 0) {
      push @LOG, 'NOTE: the last ' . int($K{tail_bytes} / 1048576) . ' MB of the log span under '
        . "$K{min_span}s, detection skipped this run (raise _NGINX_FLEET_TAIL_MB)";
    }
  }
  my $S = $any_ban ? store_load($A{store}, $now) : { F => {}, M => {} };
  store_apply($S, $now, $decl, $gip, $gnr, $gwl, $orig);
  store_prune($S, $now);
  my ($txt, $cnt) = render($S);
  my $ok = 1;
  $ok &&= write_file($A{store_tmp}, store_text($S)) if $any_ban;
  $ok &&= write_file($A{tmp_ua}, $txt->{ua});
  $ok &&= write_file($A{tmp_addr}, $txt->{addr});
  $ok &&= write_file($A{tmp_net}, $txt->{net});
  print "LOG $_\n" for @LOG;
  exit 2 unless $ok;
  printf "RESULT %d %d %d\n", $cnt->{fp}, $cnt->{addr}, $cnt->{net};
  exit 0;
}

if ($MODE eq 'replay') {
  load_allow($A{csf_allow}, $A{web6_allow});
  print "$_\n" for @LOG;
  my $FLG;
  if (defined $A{flags} && length $A{flags}) { open $FLG, '>', $A{flags} or die "cannot write flags\n"; }
  my (@win, $lo, $next);
  my $S = { F => {}, M => {} };
  my (%live_ua, %live_addr, %live_net, %prev, %ev);
  my ($last_reload, $reloads, $passes, $lines, $blocked) = (-1e12, 0, 0, 0, 0);
  my %peak = (fp => 0, addr => 0, net => 0);
  my (%fp_first, %fp_passes, %fp_scope, %fp_blocked, %fp_orig);
  my $pass = sub {
    my $now = shift;
    $passes++;
    @LOG = ();
    my ($decl, $gip, $gnr, $gwl, $orig) = ({}, {}, {}, {}, {});
    ($decl, $gip, $gnr, $gwl, $orig) = analyse(\@win, $now - $K{window}, $now)
      if $now - $lo >= $K{min_span};
    for my $g (keys %$decl) {
      my ($host, $ual) = split /\x1f/, $g, 2;
      $fp_first{$g} //= $now;
      $fp_passes{$g}++;
      $fp_scope{$g} //= scope_of($ual);
      $fp_orig{$g} //= $orig->{$g};
    }
    store_apply($S, $now, $decl, $gip, $gnr, $gwl, $orig);
    store_prune($S, $now);
    my ($txt, $cnt) = render($S);
    for my $l (@LOG) { $ev{$1}++ if $l =~ /\A(UNBANNABLE|CAP|REALIP-SUSPECT|EXEMPT|CONFIG)/; }
    # Pass mode writes no fragment and reloads nothing while nothing has ever
    # been live, so the replay must not count that first header-only render.
    return if !%prev && !$cnt->{fp};
    my $ua_changed = $txt->{ua} ne ($prev{ua} // '');
    my $changed = $ua_changed || $txt->{addr} ne ($prev{addr} // '') || $txt->{net} ne ($prev{net} // '');
    return unless $changed;
    return unless $ua_changed || $now - $last_reload >= $K{reload_gap};
    %prev = %$txt;
    $last_reload = $now;
    $reloads++;
    %live_ua = (); %live_addr = (); %live_net = ();
    for my $l (split /\n/, $txt->{ua})   { $live_ua{lc $1} = $2 if $l =~ /\A"(.*)" (f[0-9a-f]{8});\z/; }
    for my $l (split /\n/, $txt->{addr}) { $live_addr{lc $1} = 1 if $l =~ /\A"(.*)" 1;\z/; }
    for my $l (split /\n/, $txt->{net})  { $live_net{lc $1} = 1 if $l =~ /\A"(.*)" 1;\z/; }
    $peak{$_} = $cnt->{$_} > $peak{$_} ? $cnt->{$_} : $peak{$_} for qw(fp addr net);
    if (defined $A{dump_dir} && length $A{dump_dir} && $cnt->{addr} >= $peak{addr}) {
      write_file("$A{dump_dir}/nginx_fleet_$_.conf", $txt->{$_}) for qw(ua addr net);
    }
  };
  for my $file (@FILES) {
    open my $fh, '<', $file or die "cannot read $file\n";
    while (my $l = <$fh>) {
      $lines++;
      my ($ts) = $l =~ /\[([^\]]+)\]/;
      my $e = defined $ts ? ts_epoch($ts) : 0;
      unless ($e) { print $FLG "0\n" if $FLG; next; }
      $lo //= $e;
      $next //= (int($e / 60) + 1) * 60;
      while ($e >= $next) { $pass->($next); $next += 60; }
      my $r = build_rec($l);
      my $blk = 0;
      if ($r && $r->[1] ne '' && (my $id = $live_ua{$r->[3]})) {
        my $nt = $r->[1] =~ /\A(\d+\.\d+)\./ ? $1 : $r->[1];
        # Replay has no cookies: every request is treated as anonymous.
        if ($live_net{"$r->[2]|$nt|$id"} || ($live_addr{"$r->[2]|$r->[1]|$id"} && $r->[6])) {
          $blk = 1;
          $blocked++;
          $fp_blocked{$r->[2] . "\x1f" . $r->[3]}++;
        }
      }
      print $FLG "$blk\n" if $FLG;
      next unless $r;
      $r->[7] = '429' if $blk;
      push @win, $r;
      shift @win while @win && $win[0][0] < $e - $K{window} - 120;
    }
    close $fh;
  }
  close $FLG if $FLG;
  printf "REPLAY lines=%d passes=%d reloads=%d blocked=%d peak_fingerprints=%d peak_addresses=%d peak_networks=%d\n",
    $lines, $passes, $reloads, $blocked, $peak{fp}, $peak{addr}, $peak{net};
  printf "EVENTS %s\n", join(' ', map { "$_=$ev{$_}" } sort keys %ev);
  my (%sc_fp, %sc_passes, %sc_blocked);
  for my $g (keys %fp_first) {
    my $sc = $fp_scope{$g};
    $sc_fp{$sc}++;
    $sc_passes{$sc} += $fp_passes{$g};
    $sc_blocked{$sc} += $fp_blocked{$g} // 0;
  }
  for my $sc (qw(A N)) {
    printf "SCOPE scope=%s action=%s fingerprints=%d declaring_passes=%d blocked=%d\n", $sc,
      scope_ban($sc) ? 'BAN' : 'REPORT', $sc_fp{$sc} // 0, $sc_passes{$sc} // 0, $sc_blocked{$sc} // 0;
  }
  for my $g (sort { $fp_first{$a} <=> $fp_first{$b} || $a cmp $b } keys %fp_first) {
    my ($host, $ual) = split /\x1f/, $g, 2;
    printf "FINGERPRINT first=%d passes=%d scope=%s action=%s blocked=%d host=%s ua=%s\n", $fp_first{$g},
      $fp_passes{$g}, $fp_scope{$g}, scope_ban($fp_scope{$g}) ? 'BAN' : 'REPORT',
      $fp_blocked{$g} // 0, $host, show($fp_orig{$g});
  }
  exit 0;
}
exit 1;
_FLT_PERL_EOF

# Fills _ARGS with the validated knobs every mode passes to the analyser.
_fleet_common_args() {
  local _exempt_b64 _exempt_def_b64 _myip=""
  _exempt_b64=$(printf '%s' "${_NGINX_FLEET_UA_EXEMPT}" | base64 | tr -d '\n')
  _exempt_def_b64=$(printf '%s' "${_FLT_UA_EXEMPT_DEFAULT}" | base64 | tr -d '\n')
  if [[ -f "${_MYIP_FILE}" ]]; then
    _myip=$(tr -cd '0-9.' < "${_MYIP_FILE}" 2> /dev/null)
  fi
  _ARGS=(
    "window=${_NGINX_FLEET_WINDOW}" "min_span=${_NGINX_FLEET_MIN_SPAN}"
    "tail_bytes=$(( _NGINX_FLEET_TAIL_MB * 1048576 ))"
    "ip_min=${_NGINX_FLEET_IP_MIN}" "req_min=${_NGINX_FLEET_REQ_MIN}"
    "share_pct=${_NGINX_FLEET_SHARE_PCT}" "noref_pct=${_NGINX_FLEET_NOREF_PCT}"
    "uniq_pct=${_NGINX_FLEET_UNIQ_PCT}" "bad_pct=${_NGINX_FLEET_BAD_PCT}"
    "allow_pct=${_NGINX_FLEET_ALLOW_PCT}" "cand_ips=${_NGINX_FLEET_CAND_IPS}"
    "net_min_ips=${_NGINX_FLEET_NET_MIN_IPS}" "ttl=${_NGINX_FLEET_TTL}"
    "member_ttl=${_NGINX_FLEET_MEMBER_TTL}" "reload_gap=${_NGINX_FLEET_RELOAD_GAP}"
    "max_fp=${_NGINX_FLEET_MAX_FP}" "max_entries=${_NGINX_FLEET_MAX_ENTRIES}"
    "exempt_b64=${_exempt_b64}" "exempt_default_b64=${_exempt_def_b64}" "myip=${_myip}"
  )
}

if [[ "${_MODE}" = "replay" ]]; then
  # Case-insensitive like the cnf knobs, but a bad value on the command line is
  # an error rather than a fallback: the operator is watching this run.
  _REPLAY_ACTION="${_REPLAY_ACTION^^}"
  _REPLAY_CRAWLER_ACTION="${_REPLAY_CRAWLER_ACTION^^}"
  case "${_REPLAY_ACTION}" in
    REPORT|BAN) : ;;
    *)
      echo "ERROR: --action must be BAN or REPORT" >&2
      exit 1
      ;;
  esac
  case "${_REPLAY_CRAWLER_ACTION}" in
    ""|REPORT|BAN) : ;;
    *)
      echo "ERROR: --crawler-action must be BAN, REPORT or empty" >&2
      exit 1
      ;;
  esac
  if (( ${#_REPLAY_FILES[@]} == 0 )); then
    echo "ERROR: --replay needs at least one log file" >&2
    exit 1
  fi
  _FILE_ARGS=()
  for _F in "${_REPLAY_FILES[@]}"; do
    if [[ ! -f "${_F}" ]]; then
      echo "ERROR: no such log: ${_F}" >&2
      exit 1
    fi
    _FILE_ARGS+=("file=${_F}")
  done
  # The replay flags stand in for the cnf action knobs and resolve through the
  # same validation, so an empty --crawler-action inherits --action.
  _NGINX_FLEET_ACTION="${_REPLAY_ACTION}"
  _NGINX_FLEET_CRAWLER_ACTION="${_REPLAY_CRAWLER_ACTION}"
  _fleet_knobs
  _fleet_common_args
  _BAN_A=0
  _BAN_N=0
  [[ "${_NGINX_FLEET_ACTION}" = "BAN" ]] && _BAN_A=1
  [[ "${_NGINX_FLEET_CRAWLER_ACTION}" = "BAN" ]] && _BAN_N=1
  perl -e "${_FLT_PL}" -- mode=replay "${_ARGS[@]}" "ban_a=${_BAN_A}" "ban_n=${_BAN_N}" detect=1 \
    "csf_allow=${_REPLAY_ALLOW}" "web6_allow=${_WEB6_ALLOW}" \
    "flags=${_REPLAY_FLAGS}" "dump_dir=${_REPLAY_DUMP}" "${_FILE_ARGS[@]}"
  exit $?
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: must run as root" >&2
  exit 1
fi
if ! command -v nginx > /dev/null 2>&1; then
  exit 0
fi
# Passive replication standby: the web tier is held down, nothing to learn.
if [[ -e "/root/.standby.cnf" ]] && [[ ! -e "/root/.standby.serve.cnf" ]] \
  && [[ -z "$(find /run/boa_xmass_init.pid /root/.standby.init.pid -mmin -2880 2> /dev/null)" ]]; then
  exit 0
fi

# Single instance. The lock descriptors are closed on every service call below:
# a daemon started under an inherited descriptor would hold the lock forever.
exec 8> "${_SELF_LOCK}"
if ! flock -n 8; then
  exit 0
fi

mkdir -p "${_OUT_DIR}" "${_LOG_DIR}"
_fleet_knobs
_fleet_common_args

_NOW=$(date +%s)
if [[ ! "${_NOW}" =~ ^[0-9]+$ ]]; then
  exit 0
fi
_SINCE=0
if [[ -f "${_CLEAR_STAMP}" ]]; then
  _SINCE=$(tr -cd '0-9' < "${_CLEAR_STAMP}" 2> /dev/null)
  [[ "${_SINCE}" =~ ^[0-9]{1,12}$ ]] || _SINCE=0
fi
_DETECT=0
_BAN_A=0
_BAN_N=0
if [[ "${_NGINX_FLEET_DETECT}" = "YES" ]]; then
  _DETECT=1
  [[ "${_NGINX_FLEET_ACTION}" = "BAN" ]] && _BAN_A=1
  [[ "${_NGINX_FLEET_CRAWLER_ACTION}" = "BAN" ]] && _BAN_N=1
fi
_ANY_BAN=$(( _BAN_A | _BAN_N ))

_NAMES=(ua addr net)
declare -A _TMP _OUT _BAK
for _F in "${_NAMES[@]}"; do
  _OUT[${_F}]="${_OUT_DIR}/nginx_fleet_${_F}.conf"
  _TMP[${_F}]="${_OUT_DIR}/.nginx_fleet_${_F}.tmp.$$"
  _BAK[${_F}]="${_OUT_DIR}/.nginx_fleet_${_F}.last_good.conf"
done
_STORE_TMP="${_STORE}.tmp.$$"

_fleet_cleanup() {
  rm -f "${_TMP[ua]}" "${_TMP[addr]}" "${_TMP[net]}" "${_STORE_TMP}"
}

_fleet_revert() {
  local _f
  for _f in "${_NAMES[@]}"; do
    if [[ -f "${_BAK[${_f}]}" ]]; then
      cp -a "${_BAK[${_f}]}" "${_OUT[${_f}]}"
    else
      rm -f "${_OUT[${_f}]}"
    fi
  done
}

_RESULT=""
while IFS= read -r _LINE; do
  case "${_LINE}" in
    "LOG "*)    _fleet_note "${_LINE#LOG }" ;;
    "RESULT "*) _RESULT="${_LINE#RESULT }" ;;
  esac
done < <(perl -e "${_FLT_PL}" -- mode=pass "${_ARGS[@]}" "now=${_NOW}" "since=${_SINCE}" \
  "ban_a=${_BAN_A}" "ban_n=${_BAN_N}" "detect=${_DETECT}" "log=${_ACCESS_LOG}" \
  "store=${_STORE}" "store_tmp=${_STORE_TMP}" "csf_allow=${_CSF_ALLOW}" \
  "web6_allow=${_WEB6_ALLOW}" "tmp_ua=${_TMP[ua]}" "tmp_addr=${_TMP[addr]}" \
  "tmp_net=${_TMP[net]}" 2> /dev/null)
if [[ ! "${_RESULT}" =~ ^[0-9]+\ [0-9]+\ [0-9]+$ ]]; then
  _fleet_note "ALERT: fleet analyser failed or could not write its temp files; store and live maps left untouched"
  _fleet_cleanup
  exit 1
fi
read -r _CNT_FP _CNT_ADDR _CNT_NET <<< "${_RESULT}"

# No scope in BAN (or DETECT=NO) means no store at all, so a later switch back
# to BAN starts from fresh evidence instead of resurrecting old members.
if (( _ANY_BAN )); then
  if (( _CNT_FP == 0 )) && [[ ! -s "${_STORE}" ]]; then
    # Nothing live and nothing recorded: leave no empty file behind, so a box
    # that has never seen a fleet keeps a clean state directory.
    rm -f "${_STORE}" "${_STORE_TMP}"
  elif ! mv -f "${_STORE_TMP}" "${_STORE}"; then
    _fleet_note "ALERT: cannot install ${_STORE}; live maps left untouched"
    _fleet_cleanup
    exit 1
  fi
else
  rm -f "${_STORE}" "${_STORE_TMP}"
fi

# Nothing live and nothing stale to clear: leave the include globs empty.
if (( _CNT_FP == 0 )) && [[ ! -f "${_OUT[ua]}" && ! -f "${_OUT[addr]}" && ! -f "${_OUT[net]}" ]]; then
  _fleet_cleanup
  exit 0
fi
# Fragments are inert until the zones file declares the maps that read them.
if ! grep -qF 'map $boa_fleet_uaid $boa_fleet_block {' "${_ZONES_FILE}" 2> /dev/null; then
  _fleet_cleanup
  exit 0
fi

_CHANGED=0
for _F in "${_NAMES[@]}"; do
  if [[ ! -f "${_OUT[${_F}]}" ]] || ! cmp -s "${_TMP[${_F}]}" "${_OUT[${_F}]}"; then
    _CHANGED=1
  fi
done
if (( _CHANGED == 0 )); then
  _fleet_cleanup
  exit 0
fi
# A live fleet adds members on most runs. A new or expired fingerprint applies
# at once; a member-only change waits for _NGINX_FLEET_RELOAD_GAP since the
# last reload, so a long fleet costs one reload per gap, not one per minute.
if [[ -f "${_OUT[ua]}" ]] && cmp -s "${_TMP[ua]}" "${_OUT[ua]}"; then
  _LAST=0
  if [[ -f "${_RELOAD_STAMP}" ]]; then
    _LAST=$(tr -cd '0-9' < "${_RELOAD_STAMP}" 2> /dev/null)
  fi
  [[ "${_LAST}" =~ ^[0-9]{1,12}$ ]] || _LAST=0
  if (( _NOW - _LAST < _NGINX_FLEET_RELOAD_GAP )); then
    _fleet_cleanup
    exit 0
  fi
fi

exec 9> "${_NGX_LOCK}"
if ! flock -w 30 9; then
  _fleet_note "NOTE: shared nginx-config lock busy; fleet maps deferred to the next run"
  _fleet_cleanup
  exit 0
fi

# Back up every live fragment before touching any, so a failed copy (full
# disk) leaves the live set exactly as it was.
for _F in "${_NAMES[@]}"; do
  rm -f "${_BAK[${_F}]}"
  if [[ -f "${_OUT[${_F}]}" ]] && ! cp -a "${_OUT[${_F}]}" "${_BAK[${_F}]}"; then
    _fleet_note "ALERT: cannot back up ${_OUT[${_F}]}; live maps left untouched"
    rm -f "${_BAK[ua]}" "${_BAK[addr]}" "${_BAK[net]}"
    _fleet_cleanup
    exit 1
  fi
done
for _F in "${_NAMES[@]}"; do
  if ! mv -f "${_TMP[${_F}]}" "${_OUT[${_F}]}"; then
    _fleet_revert
    _fleet_note "ALERT: cannot install ${_OUT[${_F}]}; last good fleet maps restored"
    _fleet_cleanup
    exit 1
  fi
done

_CONFIGTEST=$(service nginx configtest 2>&1 8>&- 9>&-)
_RC=$?
if (( _RC != 0 )); then
  _fleet_revert
  # Name the line that rejected the set: configtest output can open with
  # unrelated [warn] or [alert] lines that would fill the slice.
  _REASON=$(printf '%s\n' "${_CONFIGTEST}" | grep -m1 -E '\[(emerg|crit|error)\]')
  [[ -n "${_REASON}" ]] || _REASON="${_CONFIGTEST}"
  _fleet_note "ALERT: nginx configtest rejected the fleet maps, last good set restored: $(printf '%s' "${_REASON}" | tr -cd '[:print:]' | cut -c1-300)"
  exit 1
fi
if ! service nginx reload > /dev/null 2>&1 8>&- 9>&-; then
  _fleet_revert
  service nginx reload > /dev/null 2>&1 8>&- 9>&-
  _fleet_note "ALERT: nginx reload failed, last good fleet maps restored"
  exit 1
fi
echo "${_NOW}" > "${_RELOAD_STAMP}"
_fleet_note "RELOAD: fleet maps live (${_CNT_FP} fingerprints, ${_CNT_ADDR} addresses, ${_CNT_NET} networks)"
exit 0
