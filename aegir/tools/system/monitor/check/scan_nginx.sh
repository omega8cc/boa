#!/bin/bash

# ==============================================================================
# Script to Monitor and Block Suspicious NGINX Activity (DoS and DDoS)
# ==============================================================================

###
### Atomic lock/unlock to prevent TOCTOU race
###
_manage_single_lock() {
  _SELF_NAME="${_SELF_NAME:-$(basename "$0")}"
  for _L in "/opt/local/bin/lock.inc" "/opt/local/lib/lock.inc"; do
    [ -r "${_L}" ] && . "${_L}" && break
  done
  if [ -n "${_SINGLE_INSTANCE_LIB_VER:-}" ] && command -v _single_instance_lock >/dev/null 2>&1; then
    # use shared lock if available
    _single_instance_lock
  else
    # -------- legacy pgrep guard ---------
    # Exit if more than 2 instances of this script are running
    _SCRIPT=$(basename "$0")
    _CNT=$(pgrep -fc ${_SCRIPT})
    if (( _CNT > 2 )); then
      echo "Too many ${_SCRIPT} running $(date) (count=${_CNT})" >> /var/log/boa/too.many.log
      exit 0
    fi
  fi
}
_manage_single_lock

# ==============================
# Configuration and Environment
# ==============================

# Enable verbose mode if debug configuration exists. The cnf is not sourced
# yet at this point, so the variable arm reads the file directly.
if [[ -e "/etc/boa/.debug.monitor.cnf" ]] \
  || grep -qiE "^[[:space:]]*(export[[:space:]]+)?_DEBUG_MONITOR=[\"' ]*YES" /root/.barracuda.cnf 2>/dev/null; then
  set -x
fi

# Enable strict error handling for debugging only
# set -euo pipefail

# Set environment variables
export HOME='/root'
export PATH='/usr/local/bin:/usr/local/sbin:/opt/local/bin:/usr/bin:/usr/sbin:/bin:/sbin'

# Set Internal Field Separator for safe parsing
IFS=$'\n\t'

# Constants
_TIMES=$(date +%y%m%d-%H%M%S)
# Guarded read: this runs every few seconds from the nginx guard, and a
# missing cache file must not spray shell errors into the monitor log.
_MYIP=""
[ -e "/root/.found_correct_ipv4.cnf" ] \
  && _MYIP=$(cat /root/.found_correct_ipv4.cnf 2>/dev/null | tr -d '\n')

# Function to perform rounded division
_inc_round_division() {
  local numerator=$1
  local denominator=$2
  echo $(( (numerator + (denominator / 2)) / denominator ))
}

# ==============================
# Default Configuration Values
# ==============================

# Default number of lines to process from access.log (positive integer)
_NGINX_DOS_LINES=1999

# Default max allowed number for blocking (positive integer)
_NGINX_DOS_LIMIT=399

# Default mode (1 or 2)
_NGINX_DOS_MODE=2

# Default divisor for increments (positive integer)
_NGINX_DOS_DIV_INC_NR=40
_NGINX_DOS_DIV_INC_S_NR=$(( _NGINX_DOS_DIV_INC_NR * 2 ))

# Default min allowed number for increments (positive integer)
_NGINX_DOS_INC_MIN=3

# Default logging mode, can be SILENT (none), NORMAL or VERBOSE
_NGINX_DOS_LOG=VERBOSE

# Debug instrumentation gate; the cnf value wins after the source below.
_DEBUG_MONITOR=NO

# ---- DDoS / Shared-UA flood detection ----
# These thresholds are evaluated against a SHORT window: nginx_guard.sh runs
# this script roughly every 5s and byte-offset tracking means each run scores
# only the log lines appended since the previous run. The original defaults
# (20 IPs / 200 reqs / 3-req block) were far too low for that window: on a
# high-traffic site the single most common mobile-browser UA string is shared
# by well over 20 distinct IPs (and 200 reqs) within 5s, so the detector flagged
# a legitimate popular browser as an "attack fingerprint" and banned every
# visitor that made >=3 requests under it (observed on a busy hosted D7 site:
# dozens of real residential IPs banned at [x3]-[x6] mid-search).
# Note a genuine distributed botnet RANDOMISES its UA per IP, so one UA shared
# by many IPs is the signature of a real browser, not a bot. The values below
# are sized so only an implausibly homogeneous burst trips the detector;
# genuinely abusive single IPs are still caught by the per-IP weighted scorer
# (_handle_blocking, > _NGINX_DOS_LIMIT) and by the path-flood detector. Tune
# per box in /root/.barracuda.cnf.
#
# Minimum number of distinct IPs sharing the same User-Agent string within the
# current scan window before the UA is considered an attack fingerprint.
_NGINX_DDOS_UA_IP_THRESHOLD=100

# Minimum per-UA request count (across all IPs) in the scan window required to
# declare a DDoS. Catches fast floods even when IPs are few but requests are
# extreme. ~1000 reqs in a ~5s window is ~200 req/s of one exact UA string.
_NGINX_DDOS_UA_REQ_THRESHOLD=1000

# When a DDoS UA is confirmed, only block IPs that contributed at least this
# many requests with that UA. A legitimate search session (results page +
# per-keystroke autocomplete + AJAX views + result clicks) easily reaches a
# handful of requests under one UA in a few seconds, so a low value here is
# exactly what banned the real visitors above; 20 sits clear of any single human
# session while still catching one IP hammering a shared UA.
_NGINX_DDOS_IP_MIN_REQS=20

# ---- Distributed UA-burst scanner-fleet detection (on by default, opt-out) ----
# The per-IP scorer and the DDoS-UA scorer above both EXCLUDE 301 redirects and
# both need a high per-IP / per-UA volume, so a distributed auth-probe flood --
# dozens of cloud IPs sharing ONE forged UA, a few requests each, ~half of them
# 301 redirects to non-Drupal CMS paths -- slips through every existing gate.
# (This is the shape that saturated a small VM on 2026-06-29: ~70 IPs, one UA,
# median 3-4 reqs/IP, ~94% of them 3xx/4xx, none near the per-IP threshold.)
#
# This detector groups by UA, counts ALL statuses INCLUDING 301, and trips only
# when a UA is shared by many IPs AND its traffic is overwhelmingly 3xx/4xx to
# nonexistent paths.  That bad-status ratio is the key false-positive guard: a
# real popular-browser UA shared by many legitimate IPs is ~all 200/304, so it
# never trips, which is why the IP threshold can sit far below the DDoS-UA one
# without re-introducing that popular-browser over-ban.  Set DETECT=NO in
# /root/.barracuda.cnf to disable.  Tune tighter, never looser, on real reports.
_NGINX_UA_BURST_DETECT="YES"
# Minimum distinct IPs sharing one exact UA in the scan window.
_NGINX_UA_BURST_IP_MIN=12
# Minimum total requests for that UA (across all its IPs) in the window.
_NGINX_UA_BURST_REQ_MIN=60
# Minimum percentage of that UA's requests that are "bad" (3xx redirect or 4xx)
# before the fleet is declared hostile.  A legitimate browser fleet is mostly
# 200/304 and stays far below this; only a scanner fleet exceeds it.
_NGINX_UA_BURST_BAD_PCT=80
# When the fleet trips, block only IPs that themselves sent at least this many
# bad (3xx/4xx) probes under that UA.  A legitimate visitor sharing the UA sent
# 200s (zero bad) and is therefore never blocked.
_NGINX_UA_BURST_IP_MIN_BAD=3

# ---- Coordinated document-harvest detection ----
# The existing scorers all key on error ratio or per-IP rate. A distributed
# content scraper trips neither: it succeeds (mostly 2xx) and each of its
# addresses stays far below _NGINX_DOS_LIMIT. What it cannot hide is shape --
# many addresses, under one user agent, each pulling a different document and
# almost never re-reading one.
#
# This runs as its own periodic pass, NOT in the per-line loop. nginx_guard.sh
# invokes this script roughly every 5s and the byte-offset reader means a pass
# sees only a few seconds of log; every candidate signal for this attack class
# is dead or inverted at that width. It needs a few minutes of context, so it
# re-reads a bounded tail on its own schedule.
_NGINX_HARVEST_DETECT="YES"
# REPORT logs WOULD-BAN lines and bans nothing. BAN_NAMED bans only cohorts
# that ALSO match _NGINX_HARVEST_BAN_UA, an operator decision about a known
# attacker. BAN arms the heuristic itself and must not be a default.
_NGINX_HARVEST_ACTION="REPORT"
_NGINX_HARVEST_BAN_UA=""
_NGINX_HARVEST_INTERVAL=60
_NGINX_HARVEST_WINDOW=300
# Fail closed: if the bounded tail does not span this many seconds the box is
# too busy for MAX_LINES and the sample is not representative, so no trip.
_NGINX_HARVEST_MIN_SPAN=180
_NGINX_HARVEST_MAX_LINES=20000
# M: documents an address must pull before it counts as a cohort member.
_NGINX_HARVEST_IP_MIN_REQS=10
# K: heavy members needed to call it coordinated.
_NGINX_HARVEST_IP_THRESHOLD=32
_NGINX_HARVEST_IP_MAX=400
# The keystone. A harvest reads each document once, so distinct-URI share runs
# at or near 100%; real audiences re-read popular pages and sit far below.
_NGINX_HARVEST_UNIQ_PCT=85
_NGINX_HARVEST_OK_PCT=70
# Melt guard: under saturation everything degrades, and a degrading box is not
# evidence of a harvest.
_NGINX_HARVEST_BAD_PCT=5
# Collapsed-realip guard: if this share of a cohort sits inside csf.allow the
# vhost is probably reporting CDN edges as clients, so skip it entirely.
_NGINX_HARVEST_ALLOW_PCT=20
# Cost path. A harvest that pulls expensive pages melts the box on a handful
# of requests per address, so no volume floor can see it. Measured on a real
# incident: the attacker held 90-97% of all backend seconds in every 5-minute
# window of the episode that no volume gate caught, while the worst legitimate
# cohort ever measured on the same box held 22.8%.
_NGINX_HARVEST_COST_PCT=50
_NGINX_HARVEST_COST_IP_MIN=16
_NGINX_HARVEST_COST_MEAN=5
_NGINX_HARVEST_IP_MAX_UAS=2
_NGINX_HARVEST_EXCL_PCT=90
_NGINX_HARVEST_MAX_BANS=10
_NGINX_HARVEST_UA_EXEMPT="Googlebot|Google-|GoogleOther|Mediapartners-Google|AdsBot|Storebot-Google|bingbot|Applebot|DuckDuckBot|Yandex|Baiduspider|SeznamBot|PetalBot|Qwantbot|coccocbot|Yeti|Sogou|archive\.org_bot|facebookexternalhit|Twitterbot|LinkedInBot|Slackbot|Discordbot|TelegramBot|Pinterest|Site24x7|Pingdom|UptimeRobot|StatusCake"
_HRV_STAMP="/var/xdrago/monitor/log/.harvest.stamp"
_HRV_LOG="/var/xdrago/monitor/log/harvest.log"

# Minimum raw requests before _handle_blocking can individually block an IP.
# Scoring multipliers can push a 1-request IP well over DOS_LIMIT; this guard
# ensures only genuinely high-volume IPs enter web.log individually.
# The distributed one-request-per-IP botnet is still caught in aggregate by
# _handle_path_flood_blocking.  Set to 1 to disable.
_NGINX_MIN_BLOCK_REQS=3

# ---- Path-flood / search-amplification detection ----
# Distributed botnets send one request per IP so per-IP rate limits never
# fire. This module tracks total 200 and 444 response traffic to expensive path
# prefixes across *all* IPs and blocks every participant once the path is
# declared under flood. Designed specifically for Solr/Elasticsearch search
# amplification attacks that bypass Nginx 444 rules by adding a Referer.

# Minimum distinct IPs hitting the same watched path prefix (200 and 444
# responses) within the scan window before a path flood is DECLARED. The prior
# default of 5 declared a flood on any busy public search page within the ~5s
# window. Declaration alone never bans — the per-IP gate
# (_NGINX_PATH_FLOOD_IP_MIN_REQS) decides who is blocked — but a low value here
# wastes work and widens the blast radius on a legitimate traffic peak, so it is
# raised to 30. Tune upward further if a flood is still declared on legit peaks.
_NGINX_PATH_FLOOD_IP_THRESHOLD=30

# Minimum total 200 and 444 responses to the same watched path prefix in the
# window before a flood is declared. ~100 search responses in a ~5s window is
# ~20 req/s of search traffic site-wide -- above legitimate interactive use on a
# busy site, well below a real Solr / Search-API amplification flood (was 15,
# i.e. ~3 req/s, which any popular search page exceeds at peak).
_NGINX_PATH_FLOOD_REQ_THRESHOLD=100

# Request time (whole seconds) above which a request is considered "slow".
# NOTE: this is nginx's $request_time, NOT $upstream_response_time -- the log
# format carries no upstream field, so this cannot tell an FPM-served request
# from one nginx answered itself. Under saturation $request_time inflates
# uniformly across every status, static files included, so treat this as a
# latency signal and never as proof that backend cycles were consumed.
_NGINX_PATH_FLOOD_SLOW_SECS=3

# Per-(path-prefix, IP) minimum 200-response count before that IP is added to
# the block list during a path-flood event.  Applies to 200-responses only --
# backend-reaching requests counted via _PATH_IP_200_REQS; a prefix's 444-only
# IPs are not counted toward this gate, since Nginx's map already free-blocks
# them at zero backend cost.  This is the real per-IP protector for legitimate
# visitors: a human searcher will not produce 20 backend-200 search hits in a
# ~5s window, but a shared CGNAT / Apple-Private-Relay egress aggregating many
# real users can exceed the old value of 10.  Kept deliberately MODEST (20, not
# higher): under the default _NGINX_DOS_MODE=2 a backend 200 scores only +1 in
# the per-IP weighted scorer, so a single moderately heavy search scraper is
# caught primarily HERE -- raising this much further would let it through.  Set
# to 1 to block every 200-sending participant.
_NGINX_PATH_FLOOD_IP_MIN_REQS=20

# Extra counter weight added for each confirmed 444 on a watched attack path
# (in addition to the standard _INC_NR increment applied for all 4xx/5xx).
# Combined with _INC_NR, an IP accumulates roughly:
#   (_INC_NR + _NGINX_DOS_444_WEIGHT) × N per scan window.
# Setting this to _NGINX_DOS_LIMIT/3 means an IP is blocked after ~3
# confirmed hits rather than waiting for the full limit to accumulate naturally.
#
# Tradeoff: lower = faster blocking, higher false-positive risk.
# Set to 0 to disable (rely on standard accumulation and path-flood detection).
#
# NOTE: the distributed one-request-per-IP botnet still won't be caught
# individually by this — they're caught in aggregate by _handle_path_flood_blocking.
# This setting helps "smarter" bots that make a few repeated requests.
#
# Do not calculate the default here: /root/.barracuda.cnf may override
# _NGINX_DOS_LIMIT later.  The default is calculated after config loading and
# limit validation, unless _NGINX_DOS_444_WEIGHT is explicitly set in config.


# Pipe-separated list of patterns for flood detection.
#
# Each pattern is matched against the FULL log line (URI path + query string +
# all other fields), so both path-based and query-string-based signals work.
#
# Path patterns  — match the URI segment produced by older search modules:
#   apachesolr_search  Drupal 6/7 Apache Solr module (/search/apachesolr_search/TERM)
#   /search/node       Drupal core node search path
#   /search/user       Drupal core user search path
#
# Query-string patterns  — match the parameter names produced by modern modules.
# These cover any URI (/search, /en/search, /views/...) because the search type
# is identified solely by the query string when using Search API / Solr backend:
#   search_api_views_fulltext  Search API Views exposed filter (most common)
#   search_api_fulltext        Search API programmatic fulltext parameter
#   im_taxonomy_vid            Faceted search taxonomy-vocabulary facet param
#                              (present in both apachesolr_search and Search API
#                               facets module; appears in every facet-bearing URL)
#
# Add further site-specific expensive endpoint substrings as needed.
_NGINX_PATH_FLOOD_WATCH="apachesolr_search|search_api_views_fulltext|search_api_fulltext|im_taxonomy_vid|/search/node|/search/user"

# ---- Distributed localized (i18n) translation-flood detection (Tier B) ----
# A distributed scraper crawling localized pages drives each uncached page
# through an expensive synchronous translation backend, holding a PHP-FPM worker
# for tens of seconds.  The source spreads across thousands of IPs at one or two
# requests each, so neither the per-IP scorer nor the Solr-oriented path-flood
# watch list above catches it.  This detector aggregates LOCALIZED requests per
# vhost over a sliding window that spans runs (each run adds one bucket) and
# trips on the COMBINATION of volume + backend stress, or -- the earlier,
# symmetric signal -- a burst of the 444s the inline Tier-A guardrail (Provision
# boa_i18n_anon limit_conn) emits the instant anonymous localized concurrency
# exceeds its per-vhost cap.  It does NOT ban per IP (futile against a
# distributed source): it alerts, snapshots the top talkers/UAs/path-classes for
# forensics, and persists across repeat bursts.  Site24x7, files.* and the
# webhook ignore-list are already skipped at loop scope before this runs.

# Master switch (YES/NO).
_NGINX_I18N_FLOOD_DETECT=YES

# Sliding-window length in seconds across runs.
_NGINX_I18N_FLOOD_WINDOW=120

# Minimum localized requests to ONE vhost within the window before the
# volume+stress path can trip.  Sized above a busy multilingual site's organic
# localized traffic; the reference incident exceeded this within ~60-90s while a
# cache-warm recon phase (high volume, ~0% stress) stays below the stress gate
# and never trips.
_NGINX_I18N_FLOOD_MIN_REQS=400

# Backend-stress gate (percent): share of windowed localized requests that are
# slow (>= _NGINX_I18N_FLOOD_SLOW_SECS), 5xx, or 444 (Tier-A shedding) before the
# volume+stress path trips.  Benign localized peaks run near 0% here.
_NGINX_I18N_FLOOD_STRESS_PCT=15

# Slow threshold (whole seconds) for the stress gate.
_NGINX_I18N_FLOOD_SLOW_SECS=3

# Early-trip: windowed count of localized 444s to ONE vhost (the Tier-A guardrail
# actively shedding the flood) that trips on its own, independent of volume.
# This is the fastest, most symmetric signal -- it lights up ~60-90s before FPM
# saturation, where the lagging stress signal alone can trip only at the ceiling.
# Set well above the handful of incidental localized 444s (banned IP, forged-AI,
# secret-path) seen in normal traffic.
_NGINX_I18N_FLOOD_C444_THRESHOLD=40

# Per-vhost alert cool-down (seconds): suppress repeat alerts/snapshots for the
# same vhost while a flood is ongoing, so a multi-minute burst yields a handful
# of records, not one every scan cycle.
_NGINX_I18N_FLOOD_COOLDOWN=300

# ---- PHP-FPM saturation early trigger (Tier B) ----
# The authoritative, near-real-time "we are saturating" signal the periodic
# fpmreport sampler misses: PHP-FPM writes
#   WARNING: [pool NAME] server reached max_children setting (N), consider raising it
# to its per-version error log the instant a pool cannot spawn a worker.  Both
# this trigger and BOA's php.sh (_fpm_proc_max_detection) byte-offset-tail these
# logs, so only NEW ceiling hits since each one's last run are acted on; php.sh
# stops at a plain capacity NOTE, while this trigger also alerts to
# i18n_flood.log and writes a box-wide forensic snapshot of the access-log tail.
# Mitigation stays with Tier A (already capping) and, for any concentrated
# offender, the per-IP scorer above.
_NGINX_FPM_SAT_DETECT=YES

# Glob of PHP-FPM per-version error logs.
_NGINX_FPM_ERR_GLOB="/var/log/php/php*-fpm-error.log"

# The literal the FPM master logs when a pool hits its pm.max_children ceiling.
_NGINX_FPM_SAT_PATTERN="reached max_children setting"

# ---- HTTP/1.0 registration-spam botnet detection (ON by default, opt-out) ----
# A credential/registration-spam botnet POSTs to Drupal auth paths (/user/register,
# /user/password) over HTTP/1.0 while forging a modern-browser User-Agent. HTTP/1.0
# is the clean transport-layer tell: no browser built in ~15 years speaks HTTP/1.0
# to a public HTTPS host. The bot paces one slow request per IP from a small CIDR
# block, so neither the per-IP weighted scorer (its raw-reqs floor plus the per-run
# counter reset) nor the search-oriented path-flood watch list ever catches it. A
# per-site Nginx guard returns 444 for this traffic; this detector turns the same
# signal into a CSF ban of the source so the firewall drops it before Nginx.
#
# DEFAULT ON, opt out per box. $server_protocol is the protocol on the connection
# to THIS Nginx, not the realip-recovered client's. BOA's own proxy layer
# (proxy.conf / ssl_proxy.conf / pln_proxy.conf / https_proxy_le.conf and the
# wildcard-SSL nginx_wild_ssl.conf) sets `proxy_http_version 1.1`, so a
# correctly-updated BOA front proxy / PX0 tier no longer downgrades to HTTP/1.0 at
# origin and real visitors stay HTTP/1.1 / HTTP/2 there. The residual
# false-positive sources are a NON-BOA front proxy or CDN that talks HTTP/1.0 to
# origin, or a box not yet updated to the HTTP/1.1 proxy confs; opt out THERE by
# setting _NGINX_HTTP10_AUTH_DETECT=NO in /root/.barracuda.cnf (confirm via the
# access log that real clients show HTTP/1.1 / HTTP/2 and only the bot HTTP/1.0).
_NGINX_HTTP10_AUTH_DETECT=YES

# Bash ERE matched against the parsed request URI (query stripped). The optional
# two-letter language prefix mirrors the site's i18n paths. No legitimate HTTP/1.0
# client ever requests these. Must be a valid ERE if overridden.
_NGINX_HTTP10_AUTH_PATHS="^/([a-z]{2}/)?user/(register|password)(/|$)"

# Sliding-window length in seconds across runs. The bot is slow (~1 req/IP every
# few minutes), so a single ~5s scan window never accumulates enough; the window
# persists hits across runs, exactly like the i18n detector's window.state.
_NGINX_HTTP10_AUTH_WINDOW=600

# Ban an individual IP once it reaches this many HTTP/1.0 auth-path hits within
# the window. A lone stray HTTP/1.0 hit (one) stays below it -- the same
# single-hit safety margin the php-probe weight keeps.
_NGINX_HTTP10_AUTH_IP_THRESHOLD=3

# Ban every observed contributing IP of a /24 once that /24's combined HTTP/1.0
# auth-path hits reach this many within the window. The botnet spreads a slow
# trickle across a small CIDR block (a /29 was observed), so the per-IP threshold
# alone reacts too slowly per address; the aggregate trips the whole block
# cleanly. Only IPs actually seen sending HTTP/1.0 to an auth path are banned --
# never an unseen address in the /24. Set very high to rely on the per-IP path
# only.
_NGINX_HTTP10_AUTH_CIDR_THRESHOLD=6

# ---- Guard-404 scraped-interactive-path detection (ON by default, opt-out) ----
# Provision's request-guard family answers a cold GET to an interactive-only
# Drupal path (a Flag toggle, a HybridAuth login window) with a STATIC 404 --
# a real interaction carries a same-origin Referer (and, on the HybridAuth
# path, a session cookie), so the 404 is a per-request bot verdict computed by
# nginx at zero backend cost. A distributed scraper botnet (thousands of
# residential-proxy IPs, median 1 request/IP, rotated real-browser UAs, mixed
# 200/302 statuses) is invisible to every volume- and UA-keyed scorer above,
# and observed IP pools rotate almost completely day to day, so per-IP action
# cannot rely on recurrence. Two things still pay: the multi-hit tail (an IP
# tripping the guard repeatedly inside a short window is a scraper following
# scraped links right now, and stopping it also stops its parallel
# content-crawl 200s that no other scorer counts), and campaign VISIBILITY --
# without it a rotating-IP flood operates in silence for months (the reference
# case ran for over three months before diagnosis).
#
# WHY THE PER-IP ACTION DEFAULTS TO REPORT. Unlike the HTTP/1.0 tell (a
# browser cannot be made to speak HTTP/1.0), this signal is browser-inducible:
# any third-party page can emit `<img referrerpolicy="no-referrer"
# src="https://<hosted-site>/flag/flag/x/1">` and make an innocent visitor's
# browser produce guard 404s on someone else's site -- turning a per-IP ban
# into a remote, box-wide denial of that visitor. Referer-less real traffic
# also exists (sites sending Referrer-Policy: no-referrer, privacy extensions,
# Referer-stripping corporate proxies), and the guard's own 404 is the perfect
# retry amplifier. So the ban is an operator decision on a confirmed campaign,
# exactly like _NGINX_HARVEST_ACTION: REPORT (default) logs GUARD404-WOULD-BAN
# and bans nothing; BAN arms the heuristic. The campaign alert runs in both
# modes because alerting can never mis-ban.
#
# Crawler protection is layered: csf.allow / web6.allow whitelisting exempts
# the providers guest-water.sh publishes (Googlebot, Bingbot, the CDN and
# monitoring ranges), the _NGINX_HARVEST_UA_EXEMPT list covers the legitimate
# crawlers and unfurlers that whitelisting does NOT reach (Applebot,
# DuckDuckBot, Yandex, Baiduspider, archive.org_bot, the social preview
# fetchers, the uptime probes), and the guarded URLs answer 404 so crawlers
# de-index them. No /24 aggregation: unlike the HTTP/1.0 botnet's tight CIDR,
# this class rides ISP-dispersed CGNAT space where a /24 holds real users. Set
# to NO in /root/.barracuda.cnf to disable.
_NGINX_GUARD404_DETECT=YES

# REPORT (default) logs GUARD404-WOULD-BAN lines to the Tier-B alert channel
# and bans nothing. BAN arms the per-IP ban. Arm it per box, on a confirmed
# campaign, having read the inducible-signal note above -- never fleet-wide by
# reflex.
_NGINX_GUARD404_ACTION="REPORT"

# Bash ERE matched against the query-stripped request URI. Default covers the
# guard-family paths whose cold GETs nginx already answers 404: Flag toggles
# (machine-name/<numeric id> tail, D7 Flag 2/3 + D8+ Flag 4) and HybridAuth
# windows (single provider segment, optional trailing slash), each with an
# optional language prefix, matched case-insensitively the way the nginx maps
# (~*) do. Print paths are deliberately NOT here: a bookmarked
# printer-friendly page refreshed a few times is a plausible real visitor, so
# print guard 404s stay with the standard weighted scorer only. On a box whose
# sites 404 these paths from Drupal itself (module absent, guard not yet
# deployed) the hits still count -- a cold Referer-less GET to an
# interactive-only path is the same verdict either way. Must be a valid ERE if
# overridden.
_NGINX_GUARD404_PATHS="^/([A-Za-z]{2}(-[A-Za-z]+)?/)?([Ff][Ll][Aa][Gg]/(flag|unflag|FLAG|UNFLAG)/[A-Za-z0-9_]+/[0-9]|[Hh]ybrid[Aa]uth/window/[A-Za-z0-9_.-]+/?$)"

# Sliding-window length in seconds across runs (same persistence shape as the
# HTTP/1.0 detector's window.state).
_NGINX_GUARD404_WINDOW=600

# Windowed guard-404 count at which an IP is reported (or banned, in BAN
# mode). Sized above what a real visitor can produce: the guard answers 404,
# which invites retries, so a Referer-less human clicking a broken control
# several times must stay under it -- while a scraper walking scraped links
# clears it within seconds. Raising it costs little (the tail is fast);
# lowering it is how false positives start.
_NGINX_GUARD404_IP_THRESHOLD=6

# Campaign visibility: once this many DISTINCT IPs carry windowed guard-404
# state at once, log one GUARD404-CAMPAIGN line + forensic snapshot to
# i18n_flood.log (the Tier-B alert channel). Sized far above organic stray
# 404s -- only a distributed campaign reaches it -- and rate-limited by the
# cool-down below so a multi-hour flood yields a handful of records.
_NGINX_GUARD404_CAMPAIGN_IPS=40

# Per-box campaign alert cool-down in seconds.
_NGINX_GUARD404_COOLDOWN=3600

# Default exclude keywords (empty by default; 'doccomment' will be used if not overridden)
_NGINX_DOS_IGNORE="doccomment"

# Default DoS keywords (empty by default; 'foobar' will be used if not overridden)
_NGINX_DOS_STOP="WAITFOR.DELAY|DECLARE.*@x|/\*\*/|%27.*%29.*%3B|0x[0-9a-f]{6}"

# Endpoints exempt from ALL IDS scoring (per-IP, UA-aggregate, path-flood).
# Space-separated leading-slash paths. Each matches that exact path and any
# sub-path under it, compared against the REAL request URI only -- parsed from
# the $request log field, query stripped, traversal (..) rejected -- so a token
# placed in a User-Agent, Referer, or query string can NEVER launder an
# exemption. Legit machine webhooks (Shopify-Captain-Hook, QuickBooks, Stripe,
# ...) send bursty signed retries; an occasional backend 4xx/5xx or the
# self-inflicted 444 must never let scan_nginx ban the provider's rotating IP
# pool. Backend HMAC + a per-endpoint nginx limit_req are the right controls for
# these, not the cross-path IDS. The default also exempts the common
# token/HMAC-authenticated API roots (/graphql, /public-api, /oauth2): a
# non-Drupal SaaS on this box drives heavy bursts to these from a single client
# or a rotating pool, and the cross-path IDS must never IP-ban an
# app-authenticated API client. Shipping them in the default (not only the
# per-box override) keeps the exemption working even if /root/.barracuda.cnf is
# regenerated. Add your own site-specific routes here per box. Add paths WITHOUT
# a trailing slash (/shopify/webhook, not /shopify/webhook/). Empty disables.
# Override (replaces this list) in /root/.barracuda.cnf.
_NGINX_DOS_IGNORE_PATHS="/shopify/webhook /quickbooks/webhook /stripe/webhook /paypal/webhook /github/webhook /gitlab/webhook /graphql /public-api /oauth2"

# ---- IPv6 adaptive web-ban (ON by default, opt-out) ----
# BOA disables IPv6 server-side and pins realip to the trusted Cloudflare ranges,
# so the ONLY way an IPv6 address can appear as the recovered client (the last
# token of the logged chain) is via a trusted proxy -- it is CF-controlled and
# not client-spoofable, exactly like the IPv4 realip case. csf is IPv4-only, so
# this detector cannot ban an IPv6 offender through the firewall; instead it feeds
# the same nginx `geo $remote_addr $is_banned` enforcement (which already accepts
# IPv6) via an nginx-native store that /var/xdrago/nginx_deny6.sh mirrors into
# /data/conf/nginx_banned_ips.conf6. All scoring/aggregation below is address-
# family-agnostic (the counters are string-keyed), so an IPv6 client rides the
# same per-IP scorer, UA-burst, and path-flood logic as IPv4; only the ingress
# validation and the ban SINK differ. Set to NO in /root/.barracuda.cnf to
# ignore IPv6 clients entirely (the pre-existing IPv4-only behaviour).
_NGINX_V6_BAN_DETECT=YES
# Seconds an IPv6 web ban lives before it self-expires (nginx_deny6.sh prunes the
# store); a re-offence refreshes it. Mirrors the 900s csf web temp ban.
_NGINX_V6_BAN_TTL=900
# nginx-native IPv6 ban store (append-with-expiry): scan_nginx writes offenders,
# nginx_deny6.sh prunes+mirrors them into the geo set. Not a csf file.
_WEB6_STORE="/var/xdrago/monitor/log/web6.tempban"
# nginx-native IPv6 ALLOW store — the v6 counterpart of csf.allow, which cannot
# hold an IPv6 entry (csf is IPv4-only). guest-water.sh mirrors the published
# Googlebot ipv6Prefix crawl ranges into it daily (Bingbot too, once Microsoft
# publishes any); untagged manual entries survive that refresh. One
# `<ip6>[/bits] # comment` per line. _is_whitelisted_ip consults it for every
# IPv6 client, so a legitimate IPv6 crawler is exempt from scoring AND banning
# at the same gates that protect an IPv4 crawler via csf.allow.
_WEB6_ALLOW="/var/xdrago/monitor/log/web6.allow"
# Instant firewall arm for offenders _block_ip has already decided to ban:
# when YES (and csf is installed) the offender also gets an immediate
# `csf -td` temp ban on ports 80/443, ahead of the web.log -> guest-fire
# pipeline. Converted from /etc/boa/.instant.csf.block.cnf (the flag stays
# honoured for one release). Set to YES in /root/.barracuda.cnf to enable.
_INSTANT_CSF_BLOCK=NO

# ==============================
# Load Configuration File
# ==============================

_CONFIG_FILE="/root/.barracuda.cnf"

if [[ -e "${_CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${_CONFIG_FILE}"
fi

# ==============================
# Validate and adjust variables
# ==============================

# Config Constants
_MAX_LIMIT=${_NGINX_DOS_LINES}
_MIN_LIMIT=$(_inc_round_division "${_MAX_LIMIT}" "40")
_DEFAULT_LIMIT=$(_inc_round_division "${_MAX_LIMIT}" "5")

# Validate _NGINX_DOS_INC_MIN: must be a positive integer
if ! [[ "${_NGINX_DOS_INC_MIN}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Warning: Invalid _NGINX_DOS_INC_MIN ('${_NGINX_DOS_INC_MIN}'). Setting to default (3)."
  _NGINX_DOS_INC_MIN=3
fi

# Validate _NGINX_DOS_DIV_INC_NR: must be a positive integer. An empty or
# invalid cnf value would otherwise clobber the built-in default and feed a
# zero divisor into the increment math below. Recompute the doubled
# short-window divisor so a cnf override keeps the x2 relationship.
if ! [[ "${_NGINX_DOS_DIV_INC_NR}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Warning: Invalid _NGINX_DOS_DIV_INC_NR ('${_NGINX_DOS_DIV_INC_NR}'). Setting to default (40)."
  _NGINX_DOS_DIV_INC_NR=40
fi
_NGINX_DOS_DIV_INC_S_NR=$(( _NGINX_DOS_DIV_INC_NR * 2 ))

# Validate _NGINX_DOS_LIMIT: must be a number within the range
if ! [[ "${_NGINX_DOS_LIMIT}" =~ ^[0-9]+$ ]] || (( _NGINX_DOS_LIMIT < _MIN_LIMIT || _NGINX_DOS_LIMIT > _MAX_LIMIT )); then
  echo "Warning: Invalid _NGINX_DOS_LIMIT ('${_NGINX_DOS_LIMIT}'). Setting to default (${_DEFAULT_LIMIT})."
  _NGINX_DOS_LIMIT=${_DEFAULT_LIMIT}
fi

# Calculate increments with rounded division
_INC_NR=$(_inc_round_division "${_NGINX_DOS_LIMIT}" "${_NGINX_DOS_DIV_INC_NR}")
_INC_S_NR=$(_inc_round_division "${_NGINX_DOS_LIMIT}" "${_NGINX_DOS_DIV_INC_S_NR}")

# Ensure increments are at least _NGINX_DOS_INC_MIN
_INC_NR=$(( _INC_NR < _NGINX_DOS_INC_MIN ? _NGINX_DOS_INC_MIN : _INC_NR ))
_INC_S_NR=$(( _INC_S_NR < _NGINX_DOS_INC_MIN ? _NGINX_DOS_INC_MIN : _INC_S_NR ))

# Calculate default watched-444 weight after config override and limit validation.
# This preserves an explicit _NGINX_DOS_444_WEIGHT=0 or custom numeric value
# from /root/.barracuda.cnf, but prevents stale defaults based on the built-in
# _NGINX_DOS_LIMIT=399 when config later changes the limit to e.g. 99.
if ! [[ "${_NGINX_DOS_444_WEIGHT:-}" =~ ^[0-9]+$ ]]; then
  _NGINX_DOS_444_WEIGHT=$(( _NGINX_DOS_LIMIT / 3 ))
fi

# Weight added for a *.php request-path that 404s on a Drupal docroot. Drupal
# (and Backdrop) routes everything through index.php; the vhost catch-all
# returns 404 for any non-entry *.php, so a *.php 404 is never a real page,
# only a webshell / arbitrary-PHP probe (shell.php, c99.php, wp-load.php).
# LIMIT/3 bans an IP after ~3 probe hits, while a single stale .php link from a
# real visitor (one hit) stays below _MININUMBER and never bans. Preserves an
# explicit override (including 0 to disable) from /root/.barracuda.cnf.
if ! [[ "${_NGINX_PHP_PROBE_WEIGHT:-}" =~ ^[0-9]+$ ]]; then
  _NGINX_PHP_PROBE_WEIGHT=$(( _NGINX_DOS_LIMIT / 3 ))
fi

# Validate the opt-in HTTP/1.0 auth-spam detector numerics; fall back to defaults
# on any non-positive-integer override so userland config cannot break arithmetic.
[[ "${_NGINX_HTTP10_AUTH_WINDOW}" =~ ^[1-9][0-9]*$ ]] || _NGINX_HTTP10_AUTH_WINDOW=600
[[ "${_NGINX_HTTP10_AUTH_IP_THRESHOLD}" =~ ^[1-9][0-9]*$ ]] || _NGINX_HTTP10_AUTH_IP_THRESHOLD=3
[[ "${_NGINX_HTTP10_AUTH_CIDR_THRESHOLD}" =~ ^[1-9][0-9]*$ ]] || _NGINX_HTTP10_AUTH_CIDR_THRESHOLD=6
# Validate the auth-path ERE: a malformed override makes every [[ =~ ]] test
# error (rc>1), which silently counts nothing (fail-closed). Revert to the
# default so a typo does not quietly disable the detector, mirroring the numeric
# fallbacks above. rc 0/1 = valid (match/no-match); rc>1 = bad regex.
[[ "/probe" =~ ${_NGINX_HTTP10_AUTH_PATHS} ]] 2>/dev/null
if (( $? > 1 )); then
  echo "Warning: Invalid _NGINX_HTTP10_AUTH_PATHS regex -- reverting to default."
  _NGINX_HTTP10_AUTH_PATHS="^/([a-z]{2}/)?user/(register|password)(/|$)"
fi

# Validate the guard-404 detector numerics and ERE the same way: numeric
# fallbacks keep arithmetic safe, the regex probe keeps a typo'd override from
# silently counting nothing (rc 0/1 = valid; rc>1 = bad regex).
[[ "${_NGINX_GUARD404_WINDOW}" =~ ^[1-9][0-9]*$ ]]       || _NGINX_GUARD404_WINDOW=600
[[ "${_NGINX_GUARD404_IP_THRESHOLD}" =~ ^[1-9][0-9]*$ ]] || _NGINX_GUARD404_IP_THRESHOLD=6
[[ "${_NGINX_GUARD404_CAMPAIGN_IPS}" =~ ^[1-9][0-9]*$ ]] || _NGINX_GUARD404_CAMPAIGN_IPS=40
[[ "${_NGINX_GUARD404_COOLDOWN}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_GUARD404_COOLDOWN=3600
# Only REPORT and BAN are meaningful; anything else falls back to REPORT so a
# typo can never silently arm the ban.
[[ "${_NGINX_GUARD404_ACTION}" == "BAN" ]] || _NGINX_GUARD404_ACTION="REPORT"
[[ "/probe" =~ ${_NGINX_GUARD404_PATHS} ]] 2>/dev/null
if (( $? > 1 )); then
  echo "Warning: Invalid _NGINX_GUARD404_PATHS regex -- reverting to default."
  _NGINX_GUARD404_PATHS="^/([A-Za-z]{2}(-[A-Za-z]+)?/)?([Ff][Ll][Aa][Gg]/(flag|unflag|FLAG|UNFLAG)/[A-Za-z0-9_]+/[0-9]|[Hh]ybrid[Aa]uth/window/[A-Za-z0-9_.-]+/?$)"
fi

# Validate the UA-burst detector numerics; fall back to defaults on any
# non-positive-integer override so userland config cannot break arithmetic
# (the bad-ratio division in particular requires REQ_MIN >= 1).
[[ "${_NGINX_UA_BURST_IP_MIN}" =~ ^[1-9][0-9]*$ ]]      || _NGINX_UA_BURST_IP_MIN=12
[[ "${_NGINX_UA_BURST_REQ_MIN}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_UA_BURST_REQ_MIN=60
[[ "${_NGINX_UA_BURST_BAD_PCT}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_UA_BURST_BAD_PCT=80
[[ "${_NGINX_UA_BURST_IP_MIN_BAD}" =~ ^[1-9][0-9]*$ ]]  || _NGINX_UA_BURST_IP_MIN_BAD=3

[[ "${_NGINX_HARVEST_INTERVAL}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_HARVEST_INTERVAL=60
[[ "${_NGINX_HARVEST_WINDOW}" =~ ^[1-9][0-9]*$ ]]       || _NGINX_HARVEST_WINDOW=300
[[ "${_NGINX_HARVEST_MIN_SPAN}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_HARVEST_MIN_SPAN=180
[[ "${_NGINX_HARVEST_MAX_LINES}" =~ ^[1-9][0-9]*$ ]]    || _NGINX_HARVEST_MAX_LINES=20000
[[ "${_NGINX_HARVEST_IP_MIN_REQS}" =~ ^[1-9][0-9]*$ ]]  || _NGINX_HARVEST_IP_MIN_REQS=10
[[ "${_NGINX_HARVEST_IP_THRESHOLD}" =~ ^[1-9][0-9]*$ ]] || _NGINX_HARVEST_IP_THRESHOLD=32
[[ "${_NGINX_HARVEST_IP_MAX}" =~ ^[1-9][0-9]*$ ]]       || _NGINX_HARVEST_IP_MAX=400
[[ "${_NGINX_HARVEST_UNIQ_PCT}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_HARVEST_UNIQ_PCT=85
[[ "${_NGINX_HARVEST_OK_PCT}" =~ ^[1-9][0-9]*$ ]]       || _NGINX_HARVEST_OK_PCT=70
[[ "${_NGINX_HARVEST_BAD_PCT}" =~ ^[0-9]+$ ]]           || _NGINX_HARVEST_BAD_PCT=5
[[ "${_NGINX_HARVEST_ALLOW_PCT}" =~ ^[1-9][0-9]*$ ]]    || _NGINX_HARVEST_ALLOW_PCT=20
[[ "${_NGINX_HARVEST_COST_PCT}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_HARVEST_COST_PCT=50
[[ "${_NGINX_HARVEST_COST_IP_MIN}" =~ ^[1-9][0-9]*$ ]]  || _NGINX_HARVEST_COST_IP_MIN=16
[[ "${_NGINX_HARVEST_COST_MEAN}" =~ ^[1-9][0-9]*$ ]]    || _NGINX_HARVEST_COST_MEAN=5
[[ "${_NGINX_HARVEST_IP_MAX_UAS}" =~ ^[1-9][0-9]*$ ]]   || _NGINX_HARVEST_IP_MAX_UAS=2
[[ "${_NGINX_HARVEST_EXCL_PCT}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_HARVEST_EXCL_PCT=90
[[ "${_NGINX_HARVEST_MAX_BANS}" =~ ^[1-9][0-9]*$ ]]     || _NGINX_HARVEST_MAX_BANS=10
### Operator-supplied patterns are the only regexes here; log-derived text is
### never used as a pattern. Probe both so a malformed one cannot abort a scan.
if [[ -n "${_NGINX_HARVEST_UA_EXEMPT}" ]]; then
  if ! [[ "probe" =~ ${_NGINX_HARVEST_UA_EXEMPT} ]] 2> /dev/null; then
    if [[ "$?" -gt 1 ]]; then
      echo "CONFIG: _NGINX_HARVEST_UA_EXEMPT is not a valid ERE, exemptions disabled"
      _NGINX_HARVEST_UA_EXEMPT=""
    fi
  fi
fi
if [[ -n "${_NGINX_HARVEST_BAN_UA}" ]]; then
  if ! [[ "probe" =~ ${_NGINX_HARVEST_BAN_UA} ]] 2> /dev/null; then
    if [[ "$?" -gt 1 ]]; then
      echo "CONFIG: _NGINX_HARVEST_BAN_UA is not a valid ERE, named bans disabled"
      _NGINX_HARVEST_BAN_UA=""
    fi
  fi
fi
case "${_NGINX_HARVEST_ACTION}" in
  REPORT|BAN_NAMED|BAN) : ;;
  *) _NGINX_HARVEST_ACTION="REPORT" ;;
esac
### BAN_NAMED without a pattern would ban nothing; say so rather than pretend.
if [[ "${_NGINX_HARVEST_ACTION}" = "BAN_NAMED" ]] && [[ -z "${_NGINX_HARVEST_BAN_UA}" ]]; then
  echo "CONFIG: _NGINX_HARVEST_ACTION=BAN_NAMED needs _NGINX_HARVEST_BAN_UA, falling back to REPORT"
  _NGINX_HARVEST_ACTION="REPORT"
fi
_HRV_ON=0
[[ "${_NGINX_HARVEST_DETECT}" = "YES" ]] && _HRV_ON=1

echo "CONFIG: _NGINX_DOS_LIMIT is ${_NGINX_DOS_LIMIT}"
echo "CONFIG: _NGINX_DOS_LINES is ${_NGINX_DOS_LINES}"
echo "CONFIG: _INC_NR is ${_INC_NR}"
echo "CONFIG: _INC_S_NR is ${_INC_S_NR}"
echo "CONFIG: _NGINX_DOS_444_WEIGHT is ${_NGINX_DOS_444_WEIGHT}"
echo "CONFIG: _NGINX_PHP_PROBE_WEIGHT is ${_NGINX_PHP_PROBE_WEIGHT}"
echo "CONFIG: _NGINX_HTTP10_AUTH_DETECT is ${_NGINX_HTTP10_AUTH_DETECT}"
echo "CONFIG: _NGINX_GUARD404_DETECT is ${_NGINX_GUARD404_DETECT}"
echo "CONFIG: _NGINX_GUARD404_ACTION is ${_NGINX_GUARD404_ACTION}"

# IPv6 adaptive-ban: derive the on/off flag and validate the TTL. A non-positive
# override falls back to the default so userland config cannot break arithmetic.
_V6_ON=0
[[ "${_NGINX_V6_BAN_DETECT}" == "YES" ]] && _V6_ON=1
[[ "${_NGINX_V6_BAN_TTL}" =~ ^[1-9][0-9]*$ ]] || _NGINX_V6_BAN_TTL=900
echo "CONFIG: _NGINX_V6_BAN_DETECT is ${_NGINX_V6_BAN_DETECT}"
echo "CONFIG: _INSTANT_CSF_BLOCK is ${_INSTANT_CSF_BLOCK}"

# ==============================
# Declare Associative Arrays
# ==============================

declare -A _WL_CACHE
declare -A _BANNED_IPS
declare -A _ALLOWED_IPS
declare -A _LOGGED_IN_IPS
declare -A _COUNTERS
declare -A _LI_CNT
declare -A _PX_CNT
declare -A _LI_REQ_CNT   # raw request counts for _LI_CNT IPs (unweighted, +1/req)
declare -A _PX_REQ_CNT   # raw request counts for _PX_CNT IPs (unweighted, +1/req)

# DDoS / Shared-UA detection arrays
# _UA_IP_COUNT[ua]    = number of distinct real IPs seen with this UA
# _UA_REQ_COUNT[ua]   = total requests seen with this UA
# _UA_IP_SET[ua:ip]   = sentinel: marks that IP 'ip' was seen with UA 'ua'
# _UA_IP_LIST[ua]     = space-separated list of real IPs using this UA
# _UA_IP_REQS[ua:ip]  = request count per (UA, IP) pair
declare -A _UA_IP_COUNT
declare -A _UA_REQ_COUNT
declare -A _UA_IP_SET
declare -A _UA_IP_LIST
declare -A _UA_IP_REQS

# UA-burst scanner-fleet detector (separate from the arrays above so feeding it
# 301 lines never perturbs the existing 301-excluding DDoS-UA scorer).
declare -A _UAB_REQ
declare -A _UAB_BAD
declare -A _UAB_IP_SET
declare -A _UAB_IP_COUNT
declare -A _UAB_IP_LIST
declare -A _UAB_IP_BAD

# Path-flood / search-amplification detection arrays
# Tracks 200 and 444 response traffic to expensive path prefixes across all IPs.
# Catches distributed botnets where no single IP exceeds per-IP rate limits.
#
# _PATH_REQ_COUNT[prefix]    = total 200 and 444 responses to this path prefix
# _PATH_IP_COUNT[prefix]     = distinct real IPs hitting this path prefix (200 and 444)
# _PATH_IP_SET[prefix:ip]    = sentinel: IP seen on this path prefix with 200 or 444
# _PATH_IP_LIST[prefix]      = space-separated list of contributing IPs
# _PATH_IP_REQS[prefix:ip]   = per-(prefix, IP) request count (200 and 444)
# _PATH_SLOW_COUNT[prefix]   = requests with request_time >= _NGINX_PATH_FLOOD_SLOW_SECS
declare -A _PATH_REQ_COUNT
declare -A _PATH_IP_COUNT
declare -A _PATH_IP_SET
declare -A _PATH_IP_LIST
# Per-(path,IP) count of 200 responses only — used to gate individual IP blocking.
# IPs that only received 444 responses are already handled by Nginx at zero
# backend cost; writing them to web.log for csf -td is redundant and causes
# web.log to accumulate thousands of entries during distributed botnet attacks.
declare -A _PATH_IP_200_REQS
declare -A _PATH_IP_REQS
declare -A _PATH_SLOW_COUNT

# Tier-B distributed-i18n-flood per-run tallies (vhost -> count this run).
declare -A _I18N_REQ      # localized requests seen
declare -A _I18N_SLOW     # localized requests with request_time >= SLOW_SECS
declare -A _I18N_ERR      # localized 5xx responses
declare -A _I18N_C444     # localized 444 responses (Tier-A guardrail shedding)

# HTTP/1.0 auth-spam: per-run tally of HTTP/1.0 hits to auth paths, keyed by the
# real client IP. Merged into a cross-run sliding window after the loop.
declare -A _H10_AUTH

# Guard-404 scraped-interactive-path: per-run tally of guard-family 404s,
# keyed by the real client IP. Merged into a cross-run sliding window after
# the loop.
declare -A _G404

# Debugging: Confirm associative arrays are declared
if [[ -e "/etc/boa/.debug.monitor.cnf" || "${_DEBUG_MONITOR}" = "YES" ]]; then
  declare -p _BANNED_IPS _ALLOWED_IPS _LOGGED_IN_IPS _COUNTERS _LI_CNT _PX_CNT
  declare -p _UA_IP_COUNT _UA_REQ_COUNT _UA_IP_SET _UA_IP_LIST _UA_IP_REQS
  declare -p _PATH_REQ_COUNT _PATH_IP_COUNT _PATH_IP_SET _PATH_IP_LIST _PATH_IP_REQS _PATH_IP_200_REQS _PATH_SLOW_COUNT
  declare -p _H10_AUTH
  echo "DEBUG: Associative arrays declared (DoS + DDoS + path-flood sets)."
fi

# ==============================
# Helper Functions
# ==============================

# Function for logging in verbose mode
_verbose_log() {
  local _reason="${1}"
  local _message="${2}"
  local _log_file="/dev/null"

  # Define log file paths
  local _general_log="/var/log/scan_nginx_debug.log"
  local _flood_log="/var/log/scan_nginx_flood_debug.log"
  local _admin_log="/var/log/scan_nginx_admin_debug.log"
  local _other_log="/var/log/scan_nginx_other_debug.log"

  # Check if logging is enabled
  if [[ -e "/etc/boa/.debug.monitor.log.cnf" || "${_NGINX_DOS_LOG}" =~ ^(NORMAL|VERBOSE)$ ]]; then
    if [[ "${_reason}" =~ Counter && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_flood_log}"
    elif [[ "${_reason}" =~ "Admin URI To Ignore" && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_admin_log}"
    elif [[ "${_reason}" =~ "Other URI To Ignore" && "${_NGINX_DOS_LOG}" =~ VERBOSE ]]; then
      _log_file="${_other_log}"
    else
      _log_file="${_general_log}"
    fi

    # Generate timestamp
    _timestamp=$(date)

    # Write to the appropriate log file using printf
    printf "%s %s REASON: %s\n" "${_timestamp}" "${_reason}" "${_message}" >> "${_log_file}"
  fi
}

# Function to validate IP format
_validate_ip() {
  local _IP="$1"
  # Remove any trailing punctuation (comma, period)
  _IP="${_IP%,}"
  _IP="${_IP%.}"
  if [[ "${_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    # Further validate each octet is between 0 and 255
    IFS='.' read -r _a _b _c _d <<< "${_IP}"
    if (( _a <= 255 && _b <= 255 && _c <= 255 && _d <= 255 )); then
      return 0
    fi
  fi
  return 1
}

# Strict IPv6 (address-only) validator, built once. Same grammar as the
# ip_access / user_admin_access generators' IPv6 matcher — a strict subset of what
# nginx accepts, so a validated address never breaks the box-wide configtest when
# nginx_deny6.sh emits it into the geo set. Only ever exercised for the recovered
# (realip, trusted-proxy) client, never a spoofable chain entry.
_V6RE_H="[0-9A-Fa-f]{1,4}"
_V6RE_V4O="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
_V6RE_V4="(${_V6RE_V4O}\.){3}${_V6RE_V4O}"
_V6_RE="^((${_V6RE_H}:){7}${_V6RE_H}|(${_V6RE_H}:){1,7}:|(${_V6RE_H}:){1,6}:${_V6RE_H}|(${_V6RE_H}:){1,5}(:${_V6RE_H}){1,2}|(${_V6RE_H}:){1,4}(:${_V6RE_H}){1,3}|(${_V6RE_H}:){1,3}(:${_V6RE_H}){1,4}|(${_V6RE_H}:){1,2}(:${_V6RE_H}){1,5}|${_V6RE_H}:((:${_V6RE_H}){1,6})|:((:${_V6RE_H}){1,7}|:)|::(ffff(:0{1,4})?:)?(${_V6RE_V4})|(${_V6RE_H}:){1,4}:(${_V6RE_V4}))$"

# Return 0 if $1 is a syntactically valid IPv6 address (no CIDR — a client is a
# single address). Cheap `:`-prescreen before the full ERE keeps the IPv4 hot
# path (no colon) free.
_validate_ip6() {
  [[ "$1" == *:* ]] || return 1
  [[ "$1" =~ ${_V6_RE} ]]
}

# Return 0 if $1 is an IPv6 address in a non-routable / non-CF-client range
# (loopback ::1, unspecified ::, link-local fe80::/10, ULA fc00::/7). A
# realip-recovered CF client is never one of these; this is defence-in-depth so
# such a token can never be scored or written to the ban store.
_is_private_ip6() {
  [[ "$1" =~ ^(::1|::|[Ff][CcDd][0-9A-Fa-f][0-9A-Fa-f]:|[Ff][Ee][89AaBb][0-9A-Fa-f]:) ]]
}

# Expand a syntactically valid IPv6 address into 8 decimal hextet values in
# _V6_HEX[0..7] (assigned in the caller's scope). Handles :: compression and a
# trailing embedded IPv4 (converted to two hextets). Returns non-zero unless the
# expansion yields exactly 8 groups of clean hex — inputs are pre-validated with
# _validate_ip6 everywhere, so a failure here is defence-in-depth only. Pure
# builtins: no subshells, printf -v for the v4 conversion.
_expand_ip6() {
  local _in="$1" _v4 _a _b _c _d _h _i _n IFS=$' \t\n'
  local -a _LP=() _RP=()
  _V6_HEX=()
  if [[ "${_in}" == *.* ]]; then
    _v4="${_in##*:}"
    IFS=. read -r _a _b _c _d <<< "${_v4}"
    [[ "${_d:-}" =~ ^[0-9]+$ ]] || return 1
    printf -v _h '%x:%x' $(( (_a << 8) + _b )) $(( (_c << 8) + _d ))
    _in="${_in%"${_v4}"}${_h}"
  fi
  if [[ "${_in}" == *::* ]]; then
    [[ -n "${_in%%::*}" ]] && IFS=: read -ra _LP <<< "${_in%%::*}"
    [[ -n "${_in#*::}" ]] && IFS=: read -ra _RP <<< "${_in#*::}"
    _n=$(( 8 - ${#_LP[@]} - ${#_RP[@]} ))
    (( _n >= 1 )) || return 1
  else
    IFS=: read -ra _LP <<< "${_in}"
    _n=0
  fi
  for _h in "${_LP[@]}" "${_RP[@]}"; do
    [[ "${_h}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
  done
  _i=0
  for _h in "${_LP[@]}"; do _V6_HEX[_i]=$(( 16#${_h} )); (( _i++ )); done
  while (( _n-- > 0 )); do _V6_HEX[_i]=0; (( _i++ )); done
  for _h in "${_RP[@]}"; do _V6_HEX[_i]=$(( 16#${_h} )); (( _i++ )); done
  (( _i == 8 ))
}

# NOTE: Removed _resolve_real_ip_traversal function (its logic is inlined in the main loop for performance)

# Function to check if an IP is banned using associative array
_is_banned_or_allowed() {
  local _IP="$1"
  if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP}" "_is_banned_or_allowed"
    echo "=== _is_banned_or_allowed ${_IP} ==="
    return 0
  fi
  return 1
}

# Function to check if an IP is allowed (local) using associative array
_is_allowed_local() {
  local _IP="$1"
  if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP}" "_is_allowed_local"
    echo "=== _is_allowed_local ${_IP} ==="
    return 0
  fi
  return 1
}

# Return 0 if IPv6 $1 lies inside any prefix loaded from the nginx-native v6
# allow store (guest-water-maintained crawler ranges + manual entries). The
# store entries are pre-expanded at load time to 8 decimal hextets + prefix
# bits, so the walk is pure integer arithmetic: full hextets compare exactly,
# a non-hextet-aligned boundary compares under a partial mask. The verdict is
# cached per address — the same client repeats across many log lines in a scan
# window, so each unique IPv6 pays for one expansion + one prefix walk per run.
_is_whitelisted_ip6() {
  local _ip="$1" _e _bits _full _rem _msk _i _hit IFS=$' \t\n'
  local -a _V6_HEX _P
  (( ${#_V6_ALLOW[@]} )) || return 1
  case "${_V6_WL_CACHE["${_ip}"]:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  if ! _expand_ip6 "${_ip}"; then
    _V6_WL_CACHE["${_ip}"]=0
    return 1
  fi
  for _e in "${_V6_ALLOW[@]}"; do
    read -r -a _P <<< "${_e}"
    _bits="${_P[8]}"
    _full=$(( _bits / 16 ))
    _rem=$(( _bits % 16 ))
    _hit=1
    for (( _i = 0; _i < _full; _i++ )); do
      (( _V6_HEX[_i] == _P[_i] )) || { _hit=0; break; }
    done
    if (( _hit && _rem )); then
      _msk=$(( (0xFFFF << (16 - _rem)) & 0xFFFF ))
      (( (_V6_HEX[_full] & _msk) == (_P[_full] & _msk) )) || _hit=0
    fi
    if (( _hit )); then
      _V6_WL_CACHE["${_ip}"]=1
      return 0
    fi
  done
  _V6_WL_CACHE["${_ip}"]=0
  return 1
}

# Return 0 if $1 is whitelisted — IPv4 in csf.allow (exact host or CIDR), IPv6
# in the nginx-native v6 allow store (csf.allow cannot hold an IPv6 entry, so
# guest-water.sh mirrors the published crawler ipv6Prefix ranges into
# _WEB6_ALLOW instead; see _is_whitelisted_ip6). The family dispatch here is
# the single point that makes EVERY scoring gate and the _block_ip keystone
# v6-aware at once.
#
# guest-water.sh maintains /etc/csf/csf.allow daily with every provider
# range the firewall trusts: Cloudflare, Googlebot, Bingbot, Pingdom,
# Imperva, Sucuri, Auth0, Site24x7, and local addresses. The monitor must
# honour that single source of truth rather than maintain its own list.
#
# The loader (below) parses csf.allow once at startup into:
#   _CSF_ALLOW_IPS          -- exact host  -> 1  (O(1) lookup)
#   _CSF_ALLOW_CIDR_OCTET1  -- first octet -> 1  (cheap prescreen)
#   _CIDR_NET / _CIDR_MASK / _CIDR_O1            (parallel indexed arrays)
#
# At call time: pure integer arithmetic, no subshells, no external processes.
# Non-whitelisted-octet IPs cost one associative-array lookup and return 1
# immediately; only IPs whose first octet matches a loaded CIDR run the loop.
#
# Honours the allow regardless of the iptables port scope of the csf.allow
# entry: an s= record expresses "trusted source" and must gate the monitor's
# block decision on every port, including 443.
# Memoised, mirroring _V6_WL_CACHE: _CSF_ALLOW_IPS and the _CIDR_* tables are
# loaded once at startup and never re-read, so a verdict cannot go stale within
# a run. Four existing trackers ask about the same IPs repeatedly and each miss
# costs a here-string plus a CIDR walk; the harvest cohort sweep asks about
# every cohort member.
_is_whitelisted_ip() {
  local _ip="$1" _a _b _c _d _ipi _k
  # IPv6 client (only ever scored when _V6_ON): consult the v6 allow store.
  if [[ "${_ip}" == *:* ]]; then
    _is_whitelisted_ip6 "${_ip}"
    return
  fi
  case "${_WL_CACHE["${_ip}"]:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  if [[ -n "${_CSF_ALLOW_IPS["${_ip}"]:-}" ]]; then
    _WL_CACHE["${_ip}"]=1
    return 0
  fi
  IFS=. read -r _a _b _c _d <<< "${_ip}"
  if [[ -z "${_CSF_ALLOW_CIDR_OCTET1["${_a}"]:-}" ]]; then
    _WL_CACHE["${_ip}"]=0
    return 1
  fi
  _ipi=$(( (_a<<24)+(_b<<16)+(_c<<8)+_d ))
  for _k in "${!_CIDR_NET[@]}"; do
    [[ "${_CIDR_O1[_k]}" == "${_a}" ]] || continue
    if (( (_ipi & _CIDR_MASK[_k]) == _CIDR_NET[_k] )); then
      _WL_CACHE["${_ip}"]=1
      return 0
    fi
  done
  _WL_CACHE["${_ip}"]=0
  return 1
}

# Function to check if an IP is logged in using associative array
_is_logged_in() {
  local _IP="$1"
  if [[ -n "${_LOGGED_IN_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP}" "_is_logged_in"
    echo "=== _is_logged_in ${_IP} ==="
    return 0
  fi
  return 1
}

# Function to log and block an IP
# Optional second argument: "silent" suppresses terminal echo (used for bulk path-flood blocking)
_block_ip() {
  local _IP="$1"
  local _SILENT="${2:-}"
  # Keystone safety net: never block any whitelisted IP — IPv4 via csf.allow
  # (exact host or CIDR), IPv6 via the nginx-native v6 allow store; both are
  # maintained daily by guest-water.sh. Blocking one of those entries would
  # drop an entire CDN PoP, monitoring network, or search-engine crawler and
  # surface as origin 502/520 errors. This guard covers every call path to
  # _block_ip, including bulk passes from _handle_ddos_blocking and
  # _handle_path_flood_blocking.
  if _is_whitelisted_ip "${_IP}"; then
    _verbose_log "Whitelisted IP ${_IP} -- refusing to block" "_block_ip"
    return
  fi
  # IPv6 sink: csf is IPv4-only and web.log's loader strips non-[0-9.] (mangling an
  # IPv6), so an IPv6 offender goes to the nginx-native store instead. It is
  # written as `<ip>|<expiry-epoch>`; nginx_deny6.sh prunes+mirrors it into
  # /data/conf/nginx_banned_ips.conf6, which the existing `geo $remote_addr
  # $is_banned` set already includes and 444s. A re-offence appends a fresh
  # expiry (the mirror keeps the max), so a persistent attacker stays banned.
  if [[ "${_IP}" == *:* ]]; then
    if [[ -z "${_BANNED_IPS["${_IP}"]}" ]]; then
      local _v6_exp=$(( $(date +%s) + _NGINX_V6_BAN_TTL ))
      echo "${_IP}|${_v6_exp}" >> "${_WEB6_STORE}"
      echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/scan_nginx.archive.log
      [[ "${_SILENT}" != "silent" ]] && echo "===[${_sumar}] ${_IP} ADDED TO IPv6 nginx ban store (${_WEB6_STORE}) ==="
    else
      [[ "${_SILENT}" != "silent" ]] && echo "===[${_sumar}] ${_IP} ALREADY IN IPv6 nginx ban store ==="
    fi
    _BANNED_IPS["${_IP}"]=1
    return
  fi
  # Append to web.log if not already present (use in-memory cache to avoid grep each time)
  if [[ -z "${_BANNED_IPS["${_IP}"]}" ]]; then
    _verbose_log "${_IP} # [x${_sumar}] ${_TIMES}" "_block_ip"
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/web.log
    echo "${_IP} # [x${_sumar}] ${_TIMES}" >> /var/xdrago/monitor/log/scan_nginx.archive.log
    [[ "${_SILENT}" != "silent" ]] && echo "===[${_sumar}] ${_IP} ADDED TO BLOCK LIST monitor/log/web.log ==="
  else
    [[ "${_SILENT}" != "silent" ]] && echo "===[${_sumar}] ${_IP} ALREADY LISTED IN monitor/log/web.log ==="
  fi
  # Mark IP as banned in this run to prevent duplicate processing
  _BANNED_IPS["${_IP}"]=1

  # Block the IP using csf instantly (temporary block for 15 minutes)
  if [[ -x "/usr/sbin/csf" ]] \
    && { [[ "${_INSTANT_CSF_BLOCK}" == "YES" ]] \
      || [[ -e "/etc/boa/.instant.csf.block.cnf" ]]; }; then
    /usr/sbin/csf -td "${_IP}" 900 -p 80
    /usr/sbin/csf -td "${_IP}" 900 -p 443
    [ -e "/etc/csf/csfpost.d/synproxy.sh" ] && synproxy_reassert -p "443 80" --no-quic -q &> /dev/null
  fi
}

# Function to increment counters based on specific suspicious log patterns
_if_increment_counters() {
  if [[ "${_IP}" = "unknown" ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NR ))
    _verbose_log "Counter++ ${_INC_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "unknown"
  fi
  # Combine checks for HTTP status 400, 404, 403, 410, 444, 500 to increment counters in one go
  if [[ "${_line}" =~ \"\ (400|404|403|410|444|500) ]]; then
    local _code="${BASH_REMATCH[1]}"
    (( _COUNTERS["${_IP}"] += _INC_NR ))
    _verbose_log "Counter++ ${_INC_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "${_code} flood protection"
  fi
  # Extra weight for a confirmed 444 on a watched attack path.
  # Unlike the removed immediate-push approach, this accumulates over multiple
  # hits rather than triggering on the very first request — faster than natural
  # accumulation, but no single hit saturates the counter.  An IP receiving
  # _NGINX_DOS_LIMIT/3 extra per hit is blocked after roughly 3 such requests.
  # The distributed one-request-per-IP botnet is still handled by the aggregate
  # path-flood detection in _handle_path_flood_blocking.
  if [[ ${_NGINX_DOS_444_WEIGHT:-0} -gt 0 && "${_line}" =~ \"\ 444 \
      && ${#_WATCH_PATTERNS[@]} -gt 0 ]]; then
    local _444_PAT
    for _444_PAT in "${_WATCH_PATTERNS[@]}"; do
      if [[ -n "${_444_PAT}" && "${_line}" =~ ${_444_PAT} ]]; then
        (( _COUNTERS["${_IP}"] += _NGINX_DOS_444_WEIGHT ))
        _verbose_log "Counter+=${_NGINX_DOS_444_WEIGHT} for IP ${_IP}: ${_COUNTERS["${_IP}"]} (444 on watched path '${_444_PAT}')" "444 extra weight"
        break
      fi
    done
  fi
  if [[ "${_line}" =~ wp-(content|admin|includes|json) ]]; then
    (( _COUNTERS["${_IP}"] += _INC_NR ))
    _verbose_log "Counter++ ${_INC_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "wp-x flood protection"
  fi
  # Webshell / arbitrary-PHP probe: a *.php request PATH that 404s on a Drupal
  # docroot is never a real page (Drupal/Backdrop route via index.php; the vhost
  # catch-all returns 404 for any non-entry *.php). Weight heavily (~LIMIT/3) so a
  # scanner bans in ~3 hits, but a single stale .php link from a real visitor (one
  # hit) scores below _MININUMBER and never bans. The .php must be in the request
  # path (char class stops at ? and whitespace) so query-string/referer/UA .php do
  # not match. Genuine entry points are excluded: index/update/install/cron/
  # xmlrpc/authorize/restore/rebuild plus boost_stats/rtoc/js (the last three can
  # legitimately 404 for bots via the is_bot guard in their vhost location).
  if [[ ${_NGINX_PHP_PROBE_WEIGHT:-0} -gt 0 \
      && "${_line}" =~ \"\ 404\  \
      && "${_line}" =~ (GET|HEAD|POST)\ /[^\"?[:space:]]*\.php([?/\ ]|\") \
      && ! "${_line}" =~ /(index|update|install|cron|xmlrpc|authorize|restore|rebuild|boost_stats|rtoc|js)\.php ]]; then
    (( _COUNTERS["${_IP}"] += _NGINX_PHP_PROBE_WEIGHT ))
    _verbose_log "Counter+=${_NGINX_PHP_PROBE_WEIGHT} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "php-probe flood protection"
  fi
  if [[ "${_line}" =~ (POST|GET)\ /user/login ]]; then
    (( _COUNTERS["${_IP}"] += _INC_S_NR ))
    _verbose_log "Counter++ ${_INC_S_NR} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/user/login flood protection"
  fi
}

# Return 0 if a log line targets a configured _NGINX_DOS_IGNORE_PATHS endpoint.
# The match is against the REAL request URI parsed out of the line's $request
# field only -- NOT a substring search over the whole line -- so a webhook/API
# token smuggled into a User-Agent, Referer, or query string cannot launder an
# exemption (that was the fatal flaw of a naive whole-line match). The query
# string is stripped and any URI containing ".." is refused, so a sub-path
# prefix can't smuggle a traversal target (e.g. /shopify/webhook/../wp-login.php
# is scored, not exempted). Called at loop scope so it skips ALL three scorers.
_is_ignored_request() {
  [[ -n "${_NGINX_DOS_IGNORE_PATHS}" ]] || return 1
  # Force a whitespace IFS locally. This script runs under a global IFS=$'\n\t'
  # (top of file), which has NO space -- so the space-separated
  # _NGINX_DOS_IGNORE_PATHS loop below would not split, collapse to a single
  # token, match nothing, and silently exempt nothing (every request scored).
  local _line="$1" _after _req _uri _p IFS=$' \t\n'
  _after="${_line#*\"*\"}"        # drop the leading "IP-chain" quoted field
  _req="${_after#*\"}"            # advance to the opening quote of $request
  _req="${_req%%\"*}"            # _req = METHOD URI PROTO
  # Require a full "METHOD /path HTTP/x" shape -- not just "METHOD /...". This is
  # defence-in-depth for the positional parse: it self-validates that field 2 is
  # a genuine request line rather than relying solely on the (true) invariant
  # that nginx escapes literal quotes in the $host/header fields ahead of it, so
  # a forged "POST /shopify/webhook ..." in any earlier field can't impersonate
  # the request token.
  case "${_req}" in [A-Z]*" /"*" HTTP/"[0-9]*) : ;; *) return 1 ;; esac
  _uri="${_req#* }"              # strip METHOD
  _uri="${_uri%% *}"            # strip PROTO
  _uri="${_uri%%\?*}"          # strip query string
  # Absolute path, no literal traversal, and no percent-encoding: $request is the
  # RAW (un-normalized) request line, so an encoded traversal like
  # /shopify/webhook/%2e%2e/wp-login.php would prefix-match an exempt path yet
  # nginx serves it as /wp-login.php. Exempt endpoints never need %-encoding, so
  # refuse any so a clean glob match is the only way in.
  [[ "${_uri}" == /* && "${_uri}" != *".."* && "${_uri}" != *%* ]] || return 1
  for _p in ${_NGINX_DOS_IGNORE_PATHS}; do
    [[ "${_uri}" == "${_p}" || "${_uri}" == "${_p}"/* ]] && return 0
  done
  return 1
}

# Return 0 if the log line's $host vhost field is an internal Ægir file server
# (*.files.{boa.io,o8.io,host8.biz,aegir.cc,aegir.biz,aoboshi.com}). The vhost is
# field 2 -- the first
# whitespace token AFTER the leading quoted IP-chain field -- parsed positionally
# so a "files.*" token smuggled into the request URI, Referer or User-Agent
# cannot launder the exemption (that was the flaw of the whole-line match this
# replaces). Parameter expansion only; forces a whitespace IFS locally because
# the script runs under the global IFS=$'\n\t'.
_is_internal_fileserver() {
  local _after _host IFS=$' \t\n'
  _after="${1#*\"*\"}"                            # drop the "IP-chain" field
  _after="${_after#"${_after%%[![:space:]]*}"}"  # ltrim leading whitespace
  _host="${_after%% *}"                          # $host = first token
  case "${_host}" in
    *.files.boa.io|files.boa.io)             return 0 ;;
    *.files.o8.io|files.o8.io)               return 0 ;;
    *.files.host8.biz|files.host8.biz)       return 0 ;;
    *.files.aegir.cc|files.aegir.cc)         return 0 ;;
    *.files.aegir.biz|files.aegir.biz)       return 0 ;;
    *.files.aoboshi.com|files.aoboshi.com)   return 0 ;;
  esac
  return 1
}

# Set _REQ_PATH to the request URI path (query string stripped) parsed out of the
# line's "$request" field only -- same positional model as _is_ignored_request
# (field 2 = $host, then [time], then "$request" = METHOD URI PROTO). Asset path
# tokens in the Referer/User-Agent/vhost therefore cannot be mistaken for the real
# request path. Literal ".." and the encoded-traversal / double-encoding sequences
# %2e (.) / %2f (/) / %25 (%) are refused: the raw $request is un-normalized, so an
# encoded traversal could prefix-match an asset path yet resolve elsewhere. Other
# %-encoding is allowed so legit image-style filenames (e.g. %20 spaces, UTF-8) stay
# exemptable. Sets _REQ_PATH="" on any malformed/suspicious line so callers fail
# closed (score the request). Assigns to the caller's local _REQ_PATH via dynamic
# scope; parameter expansion only.
_set_request_path() {
  local _after _req IFS=$' \t\n'
  _REQ_PATH=""
  _after="${1#*\"*\"}"        # drop the "IP-chain" field
  _req="${_after#*\"}"        # advance to the opening quote of $request
  _req="${_req%%\"*}"         # _req = METHOD URI PROTO
  case "${_req}" in [A-Z]*" /"*" HTTP/"[0-9]*) : ;; *) return 1 ;; esac
  _req="${_req#* }"           # strip METHOD
  _req="${_req%% *}"          # strip PROTO
  _req="${_req%%\?*}"         # strip query string
  [[ "${_req}" == /* && "${_req}" != *".."* ]] || return 1
  case "${_req}" in *%2[eEfF]*|*%25*) return 1 ;; esac
  _REQ_PATH="${_req}"
  return 0
}

# Function to process each IP
_process_ip() {
  local _IP="$1"
  local _COUNT_REF="$2"
  local _line="$3"
  local _IGNORE_ADMIN=0
  local _IGNORE_OTHER=0
  local _REQ_PATH=""

  # Validate that _COUNT_REF is a recognized associative array
  if [[ "${_COUNT_REF}" != "_LI_CNT" && "${_COUNT_REF}" != "_PX_CNT" ]]; then
    _verbose_log "Error: _COUNT_REF '${_COUNT_REF}' is not a recognized associative array" "_process_ip"
    echo "Error: _COUNT_REF '${_COUNT_REF}' is not a recognized associative array."
    return
  fi

  # Reference the appropriate counter array
  local -n _COUNTERS=${_COUNT_REF}

  # Validate IP format (IPv4, or IPv6 when the v6 adaptive-ban is enabled). A v6
  # client only reaches here via the trusted realip last token (main-loop gate).
  if ! _validate_ip "${_IP}" && ! { (( _V6_ON )) && _validate_ip6 "${_IP}"; }; then
    _verbose_log "Invalid IP format: ${_IP} -- Skipping" "_validate_ip"
    echo "Invalid IP format: ${_IP} -- Skipping."
    return
  fi

  # Skip private network and localhost IPs immediately (both families).
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]] \
      || _is_private_ip6 "${_IP}"; then
    _verbose_log "Private IP ${_IP} -- Skipping" "_process_ip"
    echo "Private IP ${_IP} -- Skipping."
    return
  fi

  # Only examine lines that are GET/HEAD/POST (ignore lines with " 301" redirect)
  if [[ "${_line}" =~ (GET|HEAD|POST) && ! "${_line}" =~ \"\ 301 ]]; then

    # Define admin URIs to ignore (combine multiple patterns into one regex for efficiency)
    if [[ "${_line}" =~ (GET|POST)\ /([a-z]{2}/)?(admin/content|quickedit|node/add|node/[0-9]+/edit|entity_reference_autocomplete|(hosting|system|admin|app|ckeditor)/|entity-browser|contextual/render|views-bulk-operations|civicrm|batch|media/browser).*\"\ (200|302) ]]; then
      _IGNORE_ADMIN=1
    fi
    # If an admin request resulted in a 403 or contains typical WP paths, do not ignore (these might be attacks)
    if [[ "${_line}" =~ (GET|HEAD|POST)\ /.*\"\ 403 ]] || [[ "${_line}" =~ wp-(content|admin|includes|json) ]]; then
      _IGNORE_ADMIN=0
    fi
    if [[ "${_IGNORE_ADMIN}" -eq 1 ]]; then
      _verbose_log "Admin URI To Ignore" "${_line}"
      return
    fi

    # Static aggregated-asset paths: match the parsed request URI path only, not
    # the whole line. These are Drupal aggregate/preprocessed file paths served
    # statically, so an attacker cannot launder the exemption by putting the token
    # in a spoofed Referer/User-Agent, and a real asset-path request cannot carry
    # an effective app-layer attack (static files ignore the query string).
    _set_request_path "${_line}"
    if [[ -n "${_REQ_PATH}" ]] && [[ "${_REQ_PATH}" =~ /files/css/css_ || "${_REQ_PATH}" =~ /files/js/js_ || "${_REQ_PATH}" =~ /files/advagg_ || "${_REQ_PATH}" =~ /files/(imagecache|styles) ]]; then
      _IGNORE_OTHER=1
    fi
    # Define other patterns to skip (combined multiple checks into one conditional with OR)
    if [[ "${_line}" =~ (GET|POST)\ /([a-z]{2}/)?advagg.*\"\ (200|302) || "${_line}" =~ (ajax|autocomplete|shs).*\"\ (200|302) || "${_line}" =~ (plupload|json|api/rest).*\"\ (200|302) || "${_line}" =~ GET\ /(filefield/progress|files/progress|file/progress|elfinder/connector).*\"\ (200|302) || "${_line}" =~ POST\ /js/.*\"\ (200|302) || "${_line}" =~ /files/media.*\"\ (200|302) || "${_line}" =~ GET\ /.*\.(mp4|m4a|flv|avi|mpeg|mov|wmv|mp3|ogg|ogv|wav|midi|zip|tar|tgz|rar|dmg|exe|apk|pxl|ipa|jpe?g|gif|png|ico).*\"\ (200|302) || "${_line}" =~ GET\ /timemachine/[0-9]{4}/.*\"\ (200|302) || "${_line}" =~ POST\ /.*/(cart/checkout|embed/preview).*\"\ (200|302) ]]; then
      _IGNORE_OTHER=1
    fi
    # Exclude lines containing configured ignore keywords or default 'doccomment'
    if [[ -n "${_NGINX_DOS_IGNORE}" ]]; then
      if [[ "${_line}" =~ (${_NGINX_DOS_IGNORE}).*\"\ (200|302) ]]; then
        _IGNORE_OTHER=1
      fi
    else
      if [[ "${_line}" =~ doccomment.*\"\ (200|302) ]]; then
        _IGNORE_OTHER=1
      fi
    fi
    # If the request resulted in a 403 or contains WP paths, do not ignore (likely malicious traffic)
    if [[ "${_line}" =~ (GET|HEAD|POST)\ /.*\"\ 403 ]] || [[ "${_line}" =~ wp-(content|admin|includes|json) ]]; then
      _IGNORE_OTHER=0
    fi
    if [[ "${_IGNORE_OTHER}" -eq 1 ]]; then
      _verbose_log "Other URI To Ignore" "${_line}"
      return
    fi

    # Skip processing if IP is whitelisted in CSF allow list (exact host or CIDR)
    if _is_whitelisted_ip "${_IP}"; then
      return
    fi

    # Initialize or increment the counter safely for this IP.
    # Avoid [[ -v assoc[key] ]] for compatibility with older Bash 4.x.
    (( _COUNTERS["${_IP}"] += 1 ))

    # Track raw request count (+1 per qualifying request, unweighted).
    # Uses plain (( arr[key]++ )) — bash treats an unset element as 0 before
    # the increment, so no [[ -v ]] check is needed.  The [[ -v arr[key] ]]
    # form is unreliable for associative arrays in bash 4.x, causing the
    # counter to reset to 1 on every call instead of accumulating.
    if [[ "${_COUNT_REF}" == "_LI_CNT" ]]; then
      (( _LI_REQ_CNT["${_IP}"]++ ))
    elif [[ "${_COUNT_REF}" == "_PX_CNT" ]]; then
      (( _PX_REQ_CNT["${_IP}"]++ ))
    fi
  fi

  # Additional counting based on mode (only if not ignored by above filters)
  if [[ "${_IGNORE_OTHER}" -eq 0 && "${_IGNORE_ADMIN}" -eq 0 ]]; then
    _if_increment_counters
    if [[ "${_NGINX_DOS_MODE}" -eq 1 ]]; then
      if [[ "${_line}" =~ POST\ /([a-z]{2}/)?(user|user/(register|pass|login)|node/add) ]]; then
        (( _COUNTERS["${_IP}"] += 5 ))
        _verbose_log "Counter++ 5 for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/user/ and /node/add POST flood protection"
      fi
      if [[ "${_line}" =~ GET\ /([a-z]{2}/)?node/add ]]; then
        (( _COUNTERS["${_IP}"] += 5 ))
        _verbose_log "Counter++ 5 for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/node/add GET flood protection"
      fi
      if [[ "${_line}" =~ GET\ /([a-z]{2}/)?search ]]; then
        (( _COUNTERS["${_IP}"] += 5 ))
        _verbose_log "Counter++ 5 for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "/search GET flood protection"
      fi
      if [[ -n "${_NGINX_DOS_STOP}" ]]; then
        if [[ "${_line}" =~ (${_NGINX_DOS_STOP}) ]]; then
          (( _COUNTERS["${_IP}"] += _NGINX_DOS_LIMIT ))
          _verbose_log "Counter++ ${_NGINX_DOS_LIMIT} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "_NGINX_DOS_STOP protection"
        fi
      fi
    else
      if [[ -n "${_NGINX_DOS_STOP}" ]]; then
        if [[ "${_line}" =~ (${_NGINX_DOS_STOP}) ]]; then
          (( _COUNTERS["${_IP}"] += _NGINX_DOS_LIMIT ))
          _verbose_log "Counter++ ${_NGINX_DOS_LIMIT} for IP ${_IP}: ${_COUNTERS["${_IP}"]}" "_NGINX_DOS_STOP protection"
        fi
      fi
    fi
  fi
}

# Function to handle blocking actions
_handle_blocking() {
  local -n _COUNTERS=$1
  local _TYPE=$2
  local _IP _COUNT _CRITNUMBER _MININUMBER _raw_reqs

  # Debug: confirm that _COUNTERS is referencing the intended array
  if [[ -n "${1}" && ( -e "/etc/boa/.debug.monitor.cnf" || "${_DEBUG_MONITOR}" = "YES" ) ]]; then
    declare -p _COUNTERS
    echo "DEBUG: _COUNTERS in _handle_blocking is referencing '${1}'"
  fi

  for _IP in "${!_COUNTERS[@]}"; do
    local _COUNT="${_COUNTERS["${_IP}"]}"
    local _CRITNUMBER="${_NGINX_DOS_LIMIT}"
    local _MININUMBER=$(( (_CRITNUMBER + 1) / 2 ))  # handle integer division rounding

    if (( _COUNT > _MININUMBER )); then
      # Raw-reqs gate: silently skip before any output.
      # DOS_STOP and scoring multipliers can push low-volume IPs over _MININUMBER
      # without them making enough requests to warrant individual blocking.
      # Path-flood aggregate handles them; no output needed here.
      local _raw_reqs=0
      if [[ "$1" == "_LI_CNT" ]]; then
        _raw_reqs="${_LI_REQ_CNT["${_IP}"]:-0}"
      elif [[ "$1" == "_PX_CNT" ]]; then
        _raw_reqs="${_PX_REQ_CNT["${_IP}"]:-0}"
      fi
      (( _raw_reqs < _NGINX_MIN_BLOCK_REQS )) && continue

      if _is_logged_in "${_IP}"; then
        _CRITNUMBER=9999
      fi
      if [[ "${_IP}" == "${_MYIP}" ]]; then
        _CRITNUMBER=9998
      fi

      echo "===[${_CRITNUMBER}] MAX ${_TYPE} critnumber for ${_IP} ==="
      echo "===[${_COUNT}] COUNTER ${_TYPE} counter for ${_IP} ==="

      # Skip blocking if IP is in local allow list
      if _is_allowed_local "${_IP}"; then
        continue
      fi
      # Skip if IP was already banned/processed
      if _is_banned_or_allowed "${_IP}"; then
        continue
      fi

      if (( _COUNT > _CRITNUMBER )); then
        _sumar="${_COUNT}"
        echo "=== block_ip ${_IP} ${_COUNT}/${_CRITNUMBER} [${_raw_reqs} raw reqs] ==="
        _block_ip "${_IP}"
      fi
    fi
  done
}

# ==============================
# DDoS / Shared-UA Detection
# ==============================

# _track_ua_ip IP UA
# Called for every non-ignored request line during the main scan loop.
# Builds per-UA statistics: distinct IP count, total request count, and
# per-(UA,IP) request count. All work is done in-memory using associative
# arrays; no subshells or external processes are spawned.
_track_ua_ip() {
  local _IP="$1"
  local _UA="$2"

  # Skip private/localhost IPs (they cannot be blocked anyway)
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    return
  fi
  # Skip already-banned IPs to avoid inflating counts needlessly
  if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
    return
  fi
  # Skip whitelisted IPs
  if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
    return
  fi

  local _UA_IP_KEY="${_UA}:${_IP}"

  # Increment total-request counter for this UA.
  # Avoid [[ -v assoc[key] ]] for compatibility with older Bash 4.x.
  (( _UA_REQ_COUNT["${_UA}"] += 1 ))

  # Increment per-(UA,IP) request counter.
  (( _UA_IP_REQS["${_UA_IP_KEY}"] += 1 ))

  # Track distinct IPs per UA (use sentinel key to avoid duplicates)
  if [[ -z "${_UA_IP_SET["${_UA_IP_KEY}"]}" ]]; then
    _UA_IP_SET["${_UA_IP_KEY}"]=1
    (( _UA_IP_COUNT["${_UA}"] += 1 ))
    # Append IP to the list for this UA (space-separated; used during blocking phase)
    _UA_IP_LIST["${_UA}"]="${_UA_IP_LIST["${_UA}"]:-}${_UA_IP_LIST["${_UA}"]:+ }${_IP}"
  fi
}

# _handle_ddos_blocking
# Iterates over all tracked User-Agents. When a UA meets either the distinct-IP
# threshold or the total-request threshold it is declared a DDoS fingerprint
# and every contributing IP (that sent at least _NGINX_DDOS_IP_MIN_REQS
# requests with that UA) is individually blocked via _block_ip.
_handle_ddos_blocking() {
  local _UA _IP _ip_count _req_count _ip_reqs _UA_IP_KEY

  for _UA in "${!_UA_REQ_COUNT[@]}"; do
    _ip_count="${_UA_IP_COUNT["${_UA}"]:-0}"
    _req_count="${_UA_REQ_COUNT["${_UA}"]:-0}"

    # Skip only if neither threshold is met.  Using OR for detection is
    # deliberate: many-IP low-rate floods and fewer-IP high-rate floods should
    # both be detected.
    if (( _ip_count < _NGINX_DDOS_UA_IP_THRESHOLD && _req_count < _NGINX_DDOS_UA_REQ_THRESHOLD )); then
      continue
    fi

    # Strip non-printable characters from the UA before any echo / verbose-log
    # call. The UA comes from an attacker-controlled HTTP header and may carry
    # terminal escape sequences; rendering them in cron output or in a tail -f
    # view of the verbose log would confuse an operator. No RCE path (printf
    # in _verbose_log already protects against format-string injection), this
    # is cosmetic hardening.
    local _UA_SAFE="${_UA//[^[:print:][:space:]]/?}"
    _verbose_log "DDoS UA detected [${_ip_count} IPs / ${_req_count} reqs]: ${_UA_SAFE}" "_handle_ddos_blocking"
    echo "=== DDoS UA DETECTED [${_ip_count} distinct IPs | ${_req_count} total reqs] ==="
    echo "=== UA fingerprint: ${_UA_SAFE:0:120} ==="

    # Walk the IP list for this UA and block qualifying IPs.
    # Global IFS is newline+tab, so force space splitting for this list.
    local _SAVE_IFS="${IFS}"
    IFS=' '
    for _IP in ${_UA_IP_LIST["${_UA}"]}; do
      IFS="${_SAVE_IFS}"
      _UA_IP_KEY="${_UA}:${_IP}"
      _ip_reqs="${_UA_IP_REQS["${_UA_IP_KEY}"]:-0}"

      if (( _ip_reqs < _NGINX_DDOS_IP_MIN_REQS )); then
        continue
      fi

      # Skip already-banned, whitelisted, and logged-in IPs
      if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} already banned -- skipping ==="
        continue
      fi
      if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} is whitelisted -- skipping ==="
        continue
      fi
      if _is_logged_in "${_IP}"; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} is logged-in session -- skipping ==="
        continue
      fi
      if [[ "${_IP}" == "${_MYIP}" ]]; then
        echo "===[${_ip_reqs}req] DDoS IP ${_IP} is local server IP -- skipping ==="
        continue
      fi

      _sumar="${_ip_reqs}"
      _block_ip "${_IP}" "silent"
    done
    IFS="${_SAVE_IFS}"
  done
}

# _track_ua_burst IP UA STATUS
# Per-UA tally for the distributed scanner-fleet detector.  Unlike _track_ua_ip
# this is fed EVERY line including 301 redirects, because a distributed
# auth-probe fleet's redirect-heavy traffic is exactly what the 301-excluding
# scorers miss.  Maintains its own arrays so it never perturbs the existing
# DDoS-UA detector.  All in-memory; no subshells.
_track_ua_burst() {
  local _IP="$1"
  local _UA="$2"
  local _ST="$3"

  # Skip private/localhost, already-banned and whitelisted IPs (same as
  # _track_ua_ip -- they cannot or must not be blocked, so do not inflate counts)
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    return
  fi
  if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
    return
  fi
  if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
    return
  fi

  local _K="${_UA}:${_IP}"
  (( _UAB_REQ["${_UA}"] += 1 ))
  if [[ -z "${_UAB_IP_SET["${_K}"]}" ]]; then
    _UAB_IP_SET["${_K}"]=1
    (( _UAB_IP_COUNT["${_UA}"] += 1 ))
    _UAB_IP_LIST["${_UA}"]="${_UAB_IP_LIST["${_UA}"]:-}${_UAB_IP_LIST["${_UA}"]:+ }${_IP}"
  fi

  # "bad" = a response a real browsing session does not accumulate: 3xx
  # redirects (301/302/307/308) and client-error 4xx (400/403/404/410).
  # Excluded: 444 (already blocked, would double-count), 401 (auth challenge),
  # 2xx/3xx-304 (success/cache), 5xx (server fault, not the client's doing).
  case "${_ST}" in
    301|302|307|308|400|403|404|410)
      (( _UAB_BAD["${_UA}"] += 1 ))
      (( _UAB_IP_BAD["${_K}"] += 1 ))
      ;;
  esac
}

# _handle_ua_burst_blocking
# Declares a UA a distributed scanner fleet when it is shared by enough distinct
# IPs, carries enough total volume, AND is overwhelmingly bad-status traffic
# (the ratio gate that keeps a legitimate shared-UA browser fleet, which is
# ~all 200/304, from ever tripping).  Then blocks only the IPs that themselves
# sent enough bad probes under that UA, so a real visitor sharing the UA (0 bad)
# is never caught.  Mirrors _handle_ddos_blocking's whitelist/logged-in/self
# guards and IFS handling.
_handle_ua_burst_blocking() {
  (( _UAB_ON )) || return 0
  local _UA _IP _ip_count _req_count _bad_count _pct _K _ip_bad _UA_SAFE _SAVE_IFS

  for _UA in "${!_UAB_REQ[@]}"; do
    _ip_count="${_UAB_IP_COUNT["${_UA}"]:-0}"
    _req_count="${_UAB_REQ["${_UA}"]:-0}"
    _bad_count="${_UAB_BAD["${_UA}"]:-0}"

    # Need a distributed fleet AND enough total volume to call it an attack.
    (( _ip_count < _NGINX_UA_BURST_IP_MIN )) && continue
    (( _req_count < _NGINX_UA_BURST_REQ_MIN )) && continue
    (( _req_count <= 0 )) && continue

    # Bad-status ratio gate -- the false-positive keystone.
    _pct=$(( (_bad_count * 100) / _req_count ))
    (( _pct < _NGINX_UA_BURST_BAD_PCT )) && continue

    _UA_SAFE="${_UA//[^[:print:][:space:]]/?}"
    _verbose_log "UA-burst fleet [${_ip_count} IPs/${_req_count} reqs/${_pct}% bad]: ${_UA_SAFE}" "_handle_ua_burst_blocking"
    echo "=== UA-BURST SCANNER FLEET [${_ip_count} distinct IPs | ${_req_count} reqs | ${_pct}% bad-status] ==="
    echo "=== UA fingerprint: ${_UA_SAFE:0:120} ==="

    # Global IFS is newline+tab; force space splitting for this list.
    _SAVE_IFS="${IFS}"
    IFS=' '
    for _IP in ${_UAB_IP_LIST["${_UA}"]}; do
      IFS="${_SAVE_IFS}"
      _K="${_UA}:${_IP}"
      _ip_bad="${_UAB_IP_BAD["${_K}"]:-0}"

      # Block only IPs that themselves sent enough bad probes under this UA.
      (( _ip_bad < _NGINX_UA_BURST_IP_MIN_BAD )) && continue

      if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
        continue
      fi
      if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
        echo "===[${_ip_bad}bad] UA-burst IP ${_IP} is whitelisted -- skipping ==="
        continue
      fi
      if _is_logged_in "${_IP}"; then
        echo "===[${_ip_bad}bad] UA-burst IP ${_IP} is logged-in session -- skipping ==="
        continue
      fi
      if [[ "${_IP}" == "${_MYIP}" ]]; then
        continue
      fi

      _sumar="${_ip_bad}"
      _block_ip "${_IP}" "silent"
    done
    IFS="${_SAVE_IFS}"
  done
}

# ==============================
# Path-Flood / Search-Amplification Detection
# ==============================

# ==============================
# Coordinated document-harvest detector
# ==============================
#
# SECURITY: everything below the first quote of a log line is attacker
# controlled. The analyser is a quoted here-doc, so the shell interpolates
# nothing into it; log text reaches perl only on stdin; the only arguments are
# integers this script validated; user agents and hosts are compared with eq
# and returned base64-encoded, so no log-derived byte is ever used as a regex,
# a file path, or a shell word. The stamp file is a fixed path for the same
# reason -- a per-agent marker would hand a UA of ../../../etc/csf/csf.allow a
# root-owned truncate.
read -r -d '' _HRV_PL <<'_HRV_PERL_EOF'
use strict;
use warnings;
use Time::Local ();
use MIME::Base64 ();
my ($cut, $m_min, $k_min, $c_pct, $c_ips, $c_mean) = @ARGV;
$cut ||= 0; $m_min ||= 10; $k_min ||= 32;
$c_pct ||= 50; $c_ips ||= 16; $c_mean ||= 5;
my %mon = (Jan=>0,Feb=>1,Mar=>2,Apr=>3,May=>4,Jun=>5,
           Jul=>6,Aug=>7,Sep=>8,Oct=>9,Nov=>10,Dec=>11);
my (%tc, %docs, %uris, %ok, %bad, %tot, %ipd, %ipu, %ipuri, %iptot, %cost);
my $costall = 0;
my ($lo, $hi) = (0, 0);
my $re = qr{^"([^"]*)" (\S+) \[(\d+/\w+/\d+:\d+:\d+:\d+) [^\]]*\] "\S+ ([^ "]+)[^"]*" (\d{3}) \d+ \d+ \d+ "[^"]*" "([^"]*)" ([0-9.]+)};
while (my $l = <STDIN>) {
  my ($ipf, $host, $ts, $path, $st, $ua, $rt) = $l =~ $re or next;
  # Cost: prefer the real upstream field when the log carries it (ut="..."),
  # which is authoritative for backend time and reads "-" whenever nginx
  # answered the request itself. Fall back to $request_time, which on BOA is a
  # close proxy because access_log is off for every static location, so a
  # logged line is almost always a backend request.
  my $c_r = $rt;
  if ($l =~ / ut="([^"]*)"/) {
    my $u = $1;
    if ($u eq '-') { $c_r = 0; }
    else { $c_r = 0; $c_r += $_ for ($u =~ /([0-9]+\.[0-9]+)/g); }
  }
  my $e = $tc{$ts};
  unless (defined $e) {
    my ($d,$mo,$y,$H,$M,$S) = $ts =~ m{^(\d+)/(\w+)/(\d+):(\d+):(\d+):(\d+)$};
    $e = 0;
    if (defined $mo && exists $mon{$mo}) {
      $e = eval { Time::Local::timelocal($S,$M,$H,$d,$mon{$mo},$y) } || 0;
    }
    $tc{$ts} = $e;
  }
  next unless $e;
  $lo = $e if !$lo || $e < $lo;
  $hi = $e if $e > $hi;
  next if $e < $cut;
  my ($ip) = split /,/, $ipf, 2;
  $ip =~ s/^\s+|\s+$//g;
  next unless $ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
  # Strip the query string: cache-busting parameters would make every human
  # ajax call look like a distinct document and invert the keystone.
  $path =~ s/\?.*$//;
  my $c = $host . "\x1f" . $ua;
  $tot{$c}++;
  $cost{$c} += $c_r;
  $costall  += $c_r;
  $ok{$c}++  if $st =~ /^2/;
  $bad{$c}++ if $st =~ /^5/ || $st eq '444';
  $docs{$c}{$ip}++;
  $uris{$c}{$path} = 1;
  $ipuri{$c}{$ip}{$path} = 1;
  $ipd{$c}{$ip}++;
  $ipu{$ip}{$ua} = 1;
  $iptot{$ip}++;
}
printf "SPAN %d %d\n", $lo, $hi;
my $id = 0;
for my $c (keys %tot) {
  my @heavy = grep { $docs{$c}{$_} >= $m_min } keys %{$docs{$c}};
  my $nip   = scalar(keys %{$docs{$c}});
  my $share = $costall ? int(100 * $cost{$c} / $costall) : 0;
  my $mean  = $tot{$c} ? $cost{$c} / $tot{$c} : 0;
  # Two independent ways in. VOLUME catches a fast harvest. COST catches the
  # slow one that melts the box on a handful of requests per address, which no
  # volume floor can ever see.
  my $why = '';
  $why = 'VOLUME' if scalar(@heavy) >= $k_min;
  if (!$why && $share >= $c_pct && $nip >= $c_ips && $mean >= $c_mean) {
    $why = 'COST';
    @heavy = keys %{$docs{$c}};
  }
  next unless $why;
  $id++;
  my ($host, $ua) = split /\x1f/, $c, 2;
  my $t = $tot{$c} || 1;
  printf "COHORT %d %d %d %d %d %d %s %s %s %d %d\n", $id, scalar(@heavy),
    int(100 * scalar(keys %{$uris{$c}}) / $t),
    int(100 * ($ok{$c}  || 0) / $t),
    int(100 * ($bad{$c} || 0) / $t),
    $t, _b64($ua), _b64($host), $why, $share, int($mean);
  for my $ip (@heavy) {
    my $d = $ipd{$c}{$ip} || 1;
    printf "IP %d %s %d %d %d %d\n", $id, $ip, $d,
      int(100 * scalar(keys %{$ipuri{$c}{$ip}}) / $d),
      scalar(keys %{$ipu{$ip}}),
      int(100 * $d / ($iptot{$ip} || $d));
  }
}
sub _b64 {
  my $x = shift;
  $x = '' unless defined $x;
  my $t = MIME::Base64::encode_base64($x, '');
  return $t eq '' ? '-' : $t;
}
_HRV_PERL_EOF

# One pass per _NGINX_HARVEST_INTERVAL, claimed by mtime on a FIXED path.
_harvest_due() {
  local _now="$1"
  local _last=0
  [[ -f "${_HRV_STAMP}" ]] && _last=$(stat -c %Y "${_HRV_STAMP}" 2> /dev/null)
  [[ "${_last}" =~ ^[0-9]+$ ]] || _last=0
  (( _now - _last < _NGINX_HARVEST_INTERVAL )) && return 1
  : > "${_HRV_STAMP}" 2> /dev/null || return 1
  return 0
}

_harvest_log() {
  echo "$1"
  echo "$(date 2> /dev/null) $1" >> "${_HRV_LOG}"
}

# Decode a base64 field for display only. Never used as a path or a pattern.
_harvest_show() {
  local _b="$1"
  [[ "${_b}" =~ ^[A-Za-z0-9+/=]+$ ]] || { echo "(unprintable)"; return; }
  printf '%s' "${_b}" | base64 -d 2> /dev/null | tr -cd '[:print:]' | cut -c1-160
}

_handle_harvest_blocking() {
  (( _HRV_ON )) || return 0
  local _now
  _now=$(date +%s 2> /dev/null)
  [[ "${_now}" =~ ^[0-9]+$ ]] || return 0
  _harvest_due "${_now}" || return 0

  local _SAVE_IFS="${IFS}"
  local _kind _a _b _c _d _e _f _g _h _i _j _k
  local _lo=0 _hi=0 _span=0 _ncoh=0
  local -A _C_HV _C_UNIQ _C_OK _C_BAD _C_TOT _C_UA _C_HOST _C_IPS _C_WHY _C_SHARE _C_MEAN
  IFS=$' \t\n'
  while read -r _kind _a _b _c _d _e _f _g _h _i _j _k; do
    case "${_kind}" in
      SPAN)
        [[ "${_a}" =~ ^[0-9]+$ ]] && _lo="${_a}"
        [[ "${_b}" =~ ^[0-9]+$ ]] && _hi="${_b}"
        ;;
      COHORT)
        [[ "${_a}" =~ ^[0-9]+$ ]] || continue
        _C_HV["${_a}"]="${_b}"; _C_UNIQ["${_a}"]="${_c}"
        _C_OK["${_a}"]="${_d}";  _C_BAD["${_a}"]="${_e}"
        _C_TOT["${_a}"]="${_f}"; _C_UA["${_a}"]="${_g}"
        _C_HOST["${_a}"]="${_h}"
        case "${_i}" in VOLUME|COST) _C_WHY["${_a}"]="${_i}" ;; *) continue ;; esac
        [[ "${_j}" =~ ^[0-9]+$ ]] && _C_SHARE["${_a}"]="${_j}" || _C_SHARE["${_a}"]=0
        [[ "${_k}" =~ ^[0-9]+$ ]] && _C_MEAN["${_a}"]="${_k}" || _C_MEAN["${_a}"]=0
        (( _ncoh++ ))
        ;;
      IP)
        [[ "${_a}" =~ ^[0-9]+$ ]] || continue
        _validate_ip "${_b}" || continue
        _C_IPS["${_a}"]="${_C_IPS["${_a}"]:-}${_C_IPS["${_a}"]:+ }${_b}:${_c}:${_d}:${_e}:${_f}"
        ;;
    esac
  done < <(tail -n "${_NGINX_HARVEST_MAX_LINES}" "${_log_file}" 2> /dev/null \
    | perl -e "${_HRV_PL}" -- \
        "$(( _now - _NGINX_HARVEST_WINDOW ))" \
        "${_NGINX_HARVEST_IP_MIN_REQS}" \
        "${_NGINX_HARVEST_IP_THRESHOLD}" \
        "${_NGINX_HARVEST_COST_PCT}" \
        "${_NGINX_HARVEST_COST_IP_MIN}" \
        "${_NGINX_HARVEST_COST_MEAN}" 2> /dev/null)

  ### IFS deliberately stays $' \t\n' for the rest of this function: the
  ### script's global IFS has no space in it, and the per-cohort records below
  ### are space-joined, so restoring it here would collapse each cohort's whole
  ### IP list into a single word.
  ### Counted, not probed: ${#arr[@]} on a never-populated associative array
  ### is an unbound-variable error under set -u.
  if (( _ncoh == 0 )); then
    IFS="${_SAVE_IFS}"
    return 0
  fi
  _span=$(( _hi - _lo ))
  if (( _span < _NGINX_HARVEST_MIN_SPAN )); then
    _harvest_log "NOTE: harvest scan span ${_span}s below ${_NGINX_HARVEST_MIN_SPAN}s -- sample not representative, skipping"
    IFS="${_SAVE_IFS}"
    return 0
  fi

  local _id _ua _host _rec _ip _docs _uniq _uas _excl _wl _tot _elig _banned
  for _id in "${!_C_HV[@]}"; do
    _ua=$(_harvest_show "${_C_UA["${_id}"]}")
    _host=$(_harvest_show "${_C_HOST["${_id}"]}")
    (( _C_HV["${_id}"] > _NGINX_HARVEST_IP_MAX )) && continue
    (( _C_UNIQ["${_id}"] < _NGINX_HARVEST_UNIQ_PCT )) && continue
    if [[ "${_C_WHY["${_id}"]}" = "VOLUME" ]]; then
      (( _C_OK["${_id}"] < _NGINX_HARVEST_OK_PCT )) && continue
    else
      ### Cost path: re-check its own floors here too, so a malformed analyser
      ### line can never promote a cohort past them.
      (( _C_SHARE["${_id}"] < _NGINX_HARVEST_COST_PCT )) && continue
      (( _C_MEAN["${_id}"] < _NGINX_HARVEST_COST_MEAN )) && continue
      (( _C_HV["${_id}"] < _NGINX_HARVEST_COST_IP_MIN )) && continue
    fi
    (( _C_BAD["${_id}"] > _NGINX_HARVEST_BAD_PCT )) && continue
    if [[ -n "${_NGINX_HARVEST_UA_EXEMPT}" ]] \
      && [[ "${_ua}" =~ ${_NGINX_HARVEST_UA_EXEMPT} ]]; then
      continue
    fi
    ### Collapsed realip: if much of the cohort is inside csf.allow we are
    ### looking at CDN edges, not clients. Skip the whole vhost.
    _wl=0; _tot=0
    for _rec in ${_C_IPS["${_id}"]}; do
      _ip="${_rec%%:*}"
      (( _tot++ ))
      _is_whitelisted_ip "${_ip}" && (( _wl++ ))
    done
    (( _tot )) || continue
    if (( 100 * _wl / _tot >= _NGINX_HARVEST_ALLOW_PCT )); then
      _harvest_log "REALIP-SUSPECT ${_host} [${_wl}/${_tot} cohort IPs whitelisted] ua=${_ua}"
      continue
    fi
    _harvest_log "=== HARVEST COHORT via ${_C_WHY["${_id}"]} [${_C_HV["${_id}"]} IPs | ${_C_TOT["${_id}"]} docs | uniq ${_C_UNIQ["${_id}"]}% | ok ${_C_OK["${_id}"]}% | bad ${_C_BAD["${_id}"]}% | cost ${_C_SHARE["${_id}"]}% | mean ${_C_MEAN["${_id}"]}s | span ${_span}s] ==="
    _harvest_log "=== host=${_host} ua=${_ua} action=${_NGINX_HARVEST_ACTION} ==="
    _banned=0
    for _rec in ${_C_IPS["${_id}"]}; do
      IFS=':' read -r _ip _docs _uniq _uas _excl <<< "${_rec}"
      _elig="yes"
      (( _uniq < _NGINX_HARVEST_UNIQ_PCT )) && _elig="uniq"
      (( _uas > _NGINX_HARVEST_IP_MAX_UAS )) && _elig="multi-ua"
      (( _excl < _NGINX_HARVEST_EXCL_PCT )) && _elig="shared-ip"
      [[ -n "${_BANNED_IPS["${_ip}"]:-}" ]] && _elig="already-banned"
      [[ -n "${_ALLOWED_IPS["${_ip}"]:-}" ]] && _elig="allowed"
      _is_whitelisted_ip "${_ip}" && _elig="whitelisted"
      _is_logged_in "${_ip}" > /dev/null 2>&1 && _elig="logged-in"
      [[ "${_ip}" = "${_MYIP}" ]] && _elig="local"
      if [[ "${_elig}" != "yes" ]]; then
        _harvest_log "SKIP ${_ip} docs=${_docs} uniq=${_uniq} uas=${_uas} excl=${_excl} gate=${_elig}"
        continue
      fi
      if [[ "${_NGINX_HARVEST_ACTION}" = "BAN" ]] \
        || { [[ "${_NGINX_HARVEST_ACTION}" = "BAN_NAMED" ]] \
             && [[ "${_ua}" =~ ${_NGINX_HARVEST_BAN_UA} ]]; }; then
        if (( _banned >= _NGINX_HARVEST_MAX_BANS )); then
          _harvest_log "CAP ${_ip} docs=${_docs} -- per-pass ban cap ${_NGINX_HARVEST_MAX_BANS} reached"
          continue
        fi
        _block_ip "${_ip}" "silent"
        (( _banned++ ))
        _harvest_log "BAN ${_ip} docs=${_docs} uniq=${_uniq} uas=${_uas} excl=${_excl}"
      else
        _harvest_log "WOULD-BAN ${_ip} docs=${_docs} uniq=${_uniq} uas=${_uas} excl=${_excl}"
      fi
    done
  done
  IFS="${_SAVE_IFS}"
}

# _track_path_flood IP PATH_KEY STATUS REQUEST_TIME
#
# Called for every non-ignored request line whose URI matches one of the
# watched path prefixes defined in _NGINX_PATH_FLOOD_WATCH.
#
# Tracks two response classes:
#   200 — request reached the backend (Solr/PHP-FPM) and consumed real resources.
#         Slow responses (request_time >= _NGINX_PATH_FLOOD_SLOW_SECS) are
#         counted separately so the flood report shows backend load generated.
#   444 — Nginx blocked the request before it touched the backend.
#         Passing them here populates aggregate path/IP counts so
#         _handle_path_flood_blocking can emit a flood report and block any
#         distributed IPs the per-IP counter threshold alone would miss.
#
# All work is done in-memory using associative arrays; no subshells spawned.
_track_path_flood() {
  local _IP="$1"
  local _PATH_KEY="$2"
  local _STATUS="$3"
  local _REQ_TIME="$4"

  # Accept confirmed-attack (444) and resource-consuming (200) responses only
  [[ "${_STATUS}" != "200" && "${_STATUS}" != "444" ]] && return

  # Skip private/localhost IPs (they cannot be blocked anyway)
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    return
  fi
  # Skip already-banned IPs to avoid inflating counts needlessly
  if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
    return
  fi
  # Skip whitelisted IPs
  if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
    return
  fi

  local _PATH_IP_KEY="${_PATH_KEY}:${_IP}"

  # Increment total request counter for this path prefix.
  # Avoid [[ -v assoc[key] ]] for compatibility with older Bash 4.x.
  (( _PATH_REQ_COUNT["${_PATH_KEY}"] += 1 ))

  # Track slow responses (request_time as whole-second integer comparison;
  # avoids bc/awk dependency by stripping the fractional part via parameter
  # expansion before the arithmetic test).
  local _REQ_INT="${_REQ_TIME%%.*}"
  if [[ "${_REQ_INT}" =~ ^[0-9]+$ ]] && (( _REQ_INT >= _NGINX_PATH_FLOOD_SLOW_SECS )); then
    (( _PATH_SLOW_COUNT["${_PATH_KEY}"] += 1 ))
  fi

  # Increment per-(path,IP) request counter.
  (( _PATH_IP_REQS["${_PATH_IP_KEY}"] += 1 ))

  # Count 200 responses per IP separately — only 200s warrant csf -td since
  # 444 responses are already free-blocked by Nginx's own map rules.
  if [[ "${_STATUS}" == "200" ]]; then
    (( _PATH_IP_200_REQS["${_PATH_IP_KEY}"] += 1 ))
  fi

  # Track distinct IPs per path prefix (sentinel pattern identical to _track_ua_ip)
  if [[ -z "${_PATH_IP_SET["${_PATH_IP_KEY}"]}" ]]; then
    _PATH_IP_SET["${_PATH_IP_KEY}"]=1
    (( _PATH_IP_COUNT["${_PATH_KEY}"] += 1 ))
    # Append IP to the space-separated list for this path prefix
    _PATH_IP_LIST["${_PATH_KEY}"]="${_PATH_IP_LIST["${_PATH_KEY}"]:-}${_PATH_IP_LIST["${_PATH_KEY}"]:+ }${_IP}"
  fi
}

# _handle_path_flood_blocking
#
# Iterates over all tracked path prefixes. When a prefix meets either the
# distinct-IP threshold OR the total-request threshold, it is declared a
# search-amplification flood and every contributing IP (that sent at least
# _NGINX_PATH_FLOOD_IP_MIN_REQS requests with that path) is blocked.
#
# Using OR (not AND) here is deliberate: a single path receiving 15+ real
# backend hits from 10+ IPs within one scan window is already anomalous
# regardless of which threshold is crossed first. Tune thresholds higher on
# genuinely high-traffic search pages.
#
# Runs after _handle_ddos_blocking so _BANNED_IPS is already fully populated
# and double-blocking IPs already caught by earlier passes is avoided.
_handle_path_flood_blocking() {
  local _PREFIX _IP _ip_count _req_count _slow_count _ip_reqs _PATH_IP_KEY

  for _PREFIX in "${!_PATH_REQ_COUNT[@]}"; do
    _ip_count="${_PATH_IP_COUNT["${_PREFIX}"]:-0}"
    _req_count="${_PATH_REQ_COUNT["${_PREFIX}"]:-0}"
    _slow_count="${_PATH_SLOW_COUNT["${_PREFIX}"]:-0}"

    # Skip if neither threshold is met
    if (( _ip_count < _NGINX_PATH_FLOOD_IP_THRESHOLD && _req_count < _NGINX_PATH_FLOOD_REQ_THRESHOLD )); then
      continue
    fi

    _verbose_log "Path flood [${_ip_count} IPs / ${_req_count} reqs / ${_slow_count} slow]: ${_PREFIX}" "_handle_path_flood_blocking"
    echo "=== PATH FLOOD DETECTED [${_ip_count} distinct IPs | ${_req_count} total reqs | ${_slow_count} slow 200s] ==="
    echo "=== Path prefix: ${_PREFIX} ==="

    # Walk the IP list for this path prefix and block qualifying IPs.
    # Global IFS is newline+tab, so force space splitting for this list.
    local _SAVE_IFS="${IFS}"
    IFS=' '
    for _IP in ${_PATH_IP_LIST["${_PREFIX}"]}; do
      IFS="${_SAVE_IFS}"
      _PATH_IP_KEY="${_PREFIX}:${_IP}"
      # Gate on backend-reaching 200s only (_PATH_IP_200_REQS): an IP that
      # received only 444s is already free-blocked by Nginx's map at zero
      # backend cost, so csf -td'ing it is redundant and would only bloat
      # web.log during distributed floods. The flood is still detected and
      # reported in aggregate above (200 and 444 both count toward that).
      _ip_reqs="${_PATH_IP_200_REQS["${_PATH_IP_KEY}"]:-0}"

      if (( _ip_reqs < _NGINX_PATH_FLOOD_IP_MIN_REQS )); then
        continue
      fi

      # Skip already-banned, whitelisted, and logged-in IPs
      if [[ -n "${_BANNED_IPS["${_IP}"]}" ]]; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} already banned -- skipping ==="
        continue
      fi
      if [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] || _is_whitelisted_ip "${_IP}"; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} is whitelisted -- skipping ==="
        continue
      fi
      if _is_logged_in "${_IP}"; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} is logged-in session -- skipping ==="
        continue
      fi
      if [[ "${_IP}" == "${_MYIP}" ]]; then
        echo "===[${_ip_reqs}req] Path-flood IP ${_IP} is local server IP -- skipping ==="
        continue
      fi

      _sumar="${_ip_reqs}"
      _block_ip "${_IP}" "silent"
    done
    IFS="${_SAVE_IFS}"
  done
}

# ==============================
# Load Banned / Allowed IPs
# ==============================

# Load banned IPs from web.log into associative array (cache already blocked IPs)
_WEB_LOG="/var/xdrago/monitor/log/web.log"
if [[ -e "${_WEB_LOG}" ]]; then
  while IFS= read -r _line; do
    _ip="${_line%% *}"               # extract IP (before first space or comment)
    _ip="${_ip//[^0-9.]/}"           # clean any non-numeric characters from IP
    if [[ -n "${_ip}" ]]; then
      _BANNED_IPS["${_ip}"]=1
    fi
  done < "${_WEB_LOG}"
fi

# Load currently-active IPv6 web bans from the nginx-native store so an already
# banned v6 client is not re-scored and re-appended each run (which would spam the
# archive + bloat the store between mirror passes). Format `<ip6>|<expiry-epoch>`;
# only still-valid (future-expiry) entries are treated as banned. Expired ones are
# pruned by nginx_deny6.sh, not here (this loop only reads).
if (( _V6_ON )) && [[ -e "${_WEB6_STORE}" ]]; then
  _v6_now="$(date +%s)"
  while IFS='|' read -r _v6_ip _v6_exp; do
    [[ "${_v6_ip}" == *:* ]] || continue
    [[ "${_v6_exp}" =~ ^[0-9]+$ ]] || continue
    (( _v6_exp > _v6_now )) && _BANNED_IPS["${_v6_ip}"]=1
  done < "${_WEB6_STORE}"
fi

# Load allowed local IPs into associative array (IPs that should not be blocked)
_LOCAL_IP_LIST="/root/.local.IP.list"
if [[ -e "${_LOCAL_IP_LIST}" ]]; then
  while IFS= read -r _line; do
    _ip="${_line%% *}"
    _ip="${_ip//[^0-9.]/}"
    if [[ -n "${_ip}" ]]; then
      _ALLOWED_IPS["${_ip}"]=1
    fi
  done < "${_LOCAL_IP_LIST}"
fi

# Load the CSF allow list into memory — the single source of truth for all
# provider ranges, maintained daily by guest-water.sh (Cloudflare, Googlebot,
# Bingbot, Pingdom, Imperva, Sucuri, Auth0, Site24x7, local addresses, ...).
#
# The previous loader only matched exact hosts (s=A.B.C.D), so every provider
# whitelisted as a CIDR (Cloudflare, Googlebot, Bingbot, Imperva, Sucuri, ...)
# was silently ignored: the regex captured the network address from s=A.B.C.D/N
# and filed it as a host key that no real edge IP ever matched. Only Pingdom
# (whitelisted as individual hosts) was actually protected.
#
# This loader separates exact hosts (O(1) assoc lookup) from CIDRs (precomputed
# integer network+mask, bucketed by first octet so _is_whitelisted_ip can do a
# fork-free containment test with a single array lookup as the common-case
# early exit). Destination-only rules (DNS/DHCP use d=<ip>, not s=) are
# excluded naturally since they contain no s= field.
declare -A _CSF_ALLOW_IPS            # exact host -> 1
declare -A _CSF_ALLOW_CIDR_OCTET1    # first octet -> 1  (cheap prescreen)
_CIDR_NET=()                         # masked network as 32-bit int  (indexed)
_CIDR_MASK=()                        # 32-bit subnet mask             (indexed)
_CIDR_O1=()                          # first octet, parallel to above (indexed)
_CSF_ALLOW_FILE="/etc/csf/csf.allow"
if [[ -f "${_CSF_ALLOW_FILE}" ]]; then
  while IFS= read -r _aline; do
    # Skip full-line comments
    [[ "${_aline}" =~ ^[[:space:]]*# ]] && continue
    # Match any s=A.B.C.D or s=A.B.C.D/N (port/direction-agnostic)
    [[ "${_aline}" =~ s=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(/([0-9]+))? ]] || continue
    _addr="${BASH_REMATCH[1]}"
    _bits="${BASH_REMATCH[3]}"
    IFS=. read -r _a _b _c _d <<< "${_addr}"
    # Skip malformed octets
    (( _a<=255 && _b<=255 && _c<=255 && _d<=255 )) || continue
    if [[ -z "${_bits}" || "${_bits}" == "32" ]]; then
      # Bare host or explicit /32 — exact lookup is sufficient
      _CSF_ALLOW_IPS["${_addr}"]=1
    else
      # CIDR — precompute masked network int and mask once at load time so
      # _is_whitelisted_ip never needs subshells or external tools at runtime
      (( _bits < 1 || _bits > 31 )) && continue
      _ni=$(( (_a<<24)+(_b<<16)+(_c<<8)+_d ))
      _mk=$(( (0xFFFFFFFF << (32 - _bits)) & 0xFFFFFFFF ))
      _CIDR_NET+=( $(( _ni & _mk )) )
      _CIDR_MASK+=( "${_mk}" )
      _CIDR_O1+=( "${_a}" )
      _CSF_ALLOW_CIDR_OCTET1["${_a}"]=1
    fi
  done < "${_CSF_ALLOW_FILE}"
fi

# Load the nginx-native IPv6 allow store — the v6 counterpart of the csf.allow
# loader above, closing the gap where a legitimate IPv6 crawler tripping the
# scoring thresholds had no whitelist to save it. guest-water.sh maintains the
# store daily from the published Googlebot/Bingbot ipv6Prefix ranges; untagged
# manual entries survive its refresh. Each `<ip6>[/bits]` entry is strictly
# validated (comment-stripped, bits 1-128, _validate_ip6 grammar) and
# pre-expanded to "8 hextets + bits" so _is_whitelisted_ip6 runs on pure
# integer arithmetic; a malformed line is skipped, never fatal. Gated on
# _V6_ON: with the v6 arm opted out no IPv6 client is ever scored, so there is
# nothing to whitelist and behaviour stays byte-identical to v4-only.
_V6_ALLOW=()
declare -A _V6_WL_CACHE
if (( _V6_ON )) && [[ -f "${_WEB6_ALLOW}" ]]; then
  while IFS= read -r _aline; do
    _entry="${_aline%%#*}"
    _entry="${_entry//[[:space:]]/}"
    [[ -n "${_entry}" ]] || continue
    _addr6="${_entry%%/*}"
    _bits6=128
    if [[ "${_entry}" == */* ]]; then
      _bits6="${_entry##*/}"
      [[ "${_bits6}" =~ ^[0-9]+$ ]] || continue
      (( _bits6 >= 1 && _bits6 <= 128 )) || continue
    fi
    _validate_ip6 "${_addr6}" || continue
    _expand_ip6 "${_addr6}" || continue
    _V6_ALLOW+=( "${_V6_HEX[0]} ${_V6_HEX[1]} ${_V6_HEX[2]} ${_V6_HEX[3]} ${_V6_HEX[4]} ${_V6_HEX[5]} ${_V6_HEX[6]} ${_V6_HEX[7]} ${_bits6}" )
  done < "${_WEB6_ALLOW}"
fi

# ==============================
# Load Logged-In IPs
# ==============================

_get_ssh_ips() {
  # Same port resolution ip_access.sh uses: sshd may serve a custom
  # _SSH_PORT, and the declared cnf value is not always the effective one
  # (hosted boxes and a failed sshd -t validation force 22). Match the
  # union of 22, the cnf value (inline comments stripped, never sourced)
  # and every port the live sshd config serves, so the logged-in shield
  # can never go dark on a default-port box.
  local _p _ports="22" _cnf_port _sshd_ports
  _cnf_port=$(sed -n 's/^_SSH_PORT=//p' /root/.barracuda.cnf 2>/dev/null \
    | tail -n 1 | sed 's/[[:space:]]*#.*$//' | tr -d '" ')
  _sshd_ports=$(/usr/sbin/sshd -T 2>/dev/null | awk '/^port /{print $2}')
  for _p in ${_cnf_port} ${_sshd_ports}; do
    if [[ "${_p}" =~ ^[0-9]+$ ]] && [[ ! " ${_ports} " =~ " ${_p} " ]]; then
      _ports="${_ports} ${_p}"
    fi
  done
  netstat -tn | awk -v p=":(${_ports// /|})$" '$4 ~ p && $6 == "ESTABLISHED" { split($5, a, ":"); print a[1] }' | sort | uniq
}

if command -v netstat &>/dev/null; then
  while IFS= read -r _logged_ip; do
    if _validate_ip "${_logged_ip}"; then
      _LOGGED_IN_IPS["${_logged_ip}"]=1
    fi
  done < <(_get_ssh_ips)
fi

# ==============================
# Pre-process Path-Flood Watch Patterns
# ==============================

# Split _NGINX_PATH_FLOOD_WATCH on '|' once before the main loop to avoid
# repeated string manipulation inside the hot path. The resulting array is
# used during per-line path matching below.
_WATCH_PATTERNS=()
if [[ -n "${_NGINX_PATH_FLOOD_WATCH:-}" ]]; then
  _SAVE_IFS="${IFS}"
  IFS='|' read -ra _WATCH_PATTERNS <<< "${_NGINX_PATH_FLOOD_WATCH}"
  IFS="${_SAVE_IFS}"
fi

# ==============================
# Tier-B: distributed i18n-flood detector + FPM saturation trigger
# ==============================

# Gate the per-line tracking on a single flag and pre-build the line regex once,
# so the hot loop pays nothing when the detector is disabled.  The regex pulls
# the vhost, request path and status from one match (field 1 is the realip
# $remote_addr, field 2 the vhost, then [time] "METHOD path ..." status).
_I18N_ON=0
[[ "${_NGINX_I18N_FLOOD_DETECT}" == "YES" ]] && _I18N_ON=1
_I18N_LINE_RE='^"[^"]*" ([^ ]+) \[[^]]*\] "[A-Z]+ ([^ ]+) [^"]*" ([0-9]{3}) '
_I18N_DIR="/var/xdrago/monitor/log/i18n_flood"
_I18N_LOG="/var/xdrago/monitor/log/i18n_flood.log"

# Gate the HTTP/1.0 auth-spam tracker on a single flag so the hot loop pays
# nothing when the (on-by-default) detector is opted out. State persists the
# cross-run sliding window, like the i18n window.state above.
_H10_ON=0
[[ "${_NGINX_HTTP10_AUTH_DETECT}" == "YES" ]] && _H10_ON=1
_H10_STATE="/var/xdrago/monitor/log/http10_auth.window"

# Gate the guard-404 scraped-interactive-path tracker the same way. State
# persists the cross-run sliding window; the stamp rate-limits campaign alerts.
_G404_ON=0
[[ "${_NGINX_GUARD404_DETECT}" == "YES" ]] && _G404_ON=1
_G404_STATE="/var/xdrago/monitor/log/guard404.window"
_G404_CAMP_STAMP="/var/xdrago/monitor/log/.guard404.campaign.stamp"

# Gate the UA-burst scanner-fleet tracker on a single flag so the hot loop pays
# nothing when the (on-by-default) detector is opted out.
_UAB_ON=0
[[ "${_NGINX_UA_BURST_DETECT}" == "YES" ]] && _UAB_ON=1

# Per-line tally for the windowed detector.  $1 vhost, $2 status, $3 request_time.
_track_i18n_flood() {
  local _h="$1" _st="$2" _ut="$3" _uti
  [[ -n "${_h}" ]] || return 0
  _I18N_REQ["${_h}"]=$(( ${_I18N_REQ["${_h}"]:-0} + 1 ))
  _uti="${_ut%%.*}"
  [[ "${_uti}" =~ ^[0-9]+$ ]] || _uti=0
  if (( _uti >= _NGINX_I18N_FLOOD_SLOW_SECS )); then
    _I18N_SLOW["${_h}"]=$(( ${_I18N_SLOW["${_h}"]:-0} + 1 ))
  fi
  case "${_st}" in
    500|502|503|504) _I18N_ERR["${_h}"]=$(( ${_I18N_ERR["${_h}"]:-0} + 1 )) ;;
    444)             _I18N_C444["${_h}"]=$(( ${_I18N_C444["${_h}"]:-0} + 1 )) ;;
  esac
}

# Per-vhost alert cool-down via a marker file's mtime.  Return 0 (alert) when no
# alert fired for this vhost within _NGINX_I18N_FLOOD_COOLDOWN seconds, else 1.
_i18n_cooldown_ok() {
  local _h="$1" _now="$2" _cd _m
  _cd="${_I18N_DIR}/.cd-${_h//[^a-zA-Z0-9._-]/_}"
  if [[ -f "${_cd}" ]]; then
    _m="$(stat -c %Y "${_cd}" 2>/dev/null)"
    if [[ "${_m}" =~ ^[0-9]+$ ]] && (( _now - _m < _NGINX_I18N_FLOOD_COOLDOWN )); then
      return 1
    fi
  fi
  : > "${_cd}" 2>/dev/null
  return 0
}

# Forensic snapshot of the heaviest talkers/UAs/path-classes for a vhost (or "*"
# for box-wide) from the recent access log.  Echoes the snapshot file path.
# Runs only on a trip, so a perl pass over the tail is acceptable here.
_i18n_snapshot() {
  local _h="$1" _why="$2" _f
  [[ -d "${_I18N_DIR}" ]] || mkdir -p "${_I18N_DIR}" 2>/dev/null
  _f="${_I18N_DIR}/$(date +%y%m%d-%H%M%S)-${_h//[^a-zA-Z0-9._-]/_}.txt"
  {
    echo "# i18n-flood snapshot  vhost=${_h}  reason=${_why}  at=$(date)"
    tail -n "${_NGINX_DOS_LINES}" "${_log_file}" 2>/dev/null \
      | perl -ne '
          BEGIN { $h = shift @ARGV; }
          if (/^"([^"]*)" (\S+) \[[^\]]*\] "(\S+) (\S+)[^"]*" (\d{3}) .* "([^"]*)" ([\d.]+) /) {
            my ($ip,$vh,$path,$st,$ua,$rt) = ($1,$2,$4,$5,$6,$7);
            next if $h ne "*" && $vh ne $h;
            $n++; $rts += $rt; $rtmax = $rt if $rt > $rtmax;
            $ipc{$ip}++; $uac{$ua}++; $stc{$st}++; $vhc{$vh}++;
            $langc{lc($1)}++ if $path =~ m{^/([A-Za-z][A-Za-z](?:-[A-Za-z]+)?)/};
          }
          END {
            printf "total=%d mean_rt=%.2f max_rt=%.2f\n", $n, ($n ? $rts/$n : 0), $rtmax;
            sub top { my ($t,$r,$k)=@_; print "# top $t:\n";
              my @s = sort { $r->{$b} <=> $r->{$a} } keys %$r;
              for (my $i=0; $i<@s && $i<$k; $i++){ printf "  %6d  %s\n", $r->{$s[$i]}, $s[$i] } }
            top("vhosts",\%vhc,10); top("client IPs",\%ipc,15);
            top("User-Agents",\%uac,10); top("status",\%stc,10);
            top("lang-prefixes",\%langc,15);
          }
        ' "${_h}"
  } >> "${_f}" 2>/dev/null
  echo "${_f}"
}

# Merge this run's per-vhost localized tallies into the cross-run sliding window,
# prune expired buckets, and trip on the guardrail-shedding or volume+stress
# condition.  Mitigation is detection + forensics + alert (Tier A does the
# real-time capping); no per-IP bans are issued here.
_handle_i18n_flood() {
  [[ "${_NGINX_I18N_FLOOD_DETECT}" == "YES" ]] || return 0
  local _state="${_I18N_DIR}/window.state" _tmp _now _cut
  local _h _e _r _s _er _c4 _vol _bad _badp _trip _snap
  _now="$(date +%s)"
  [[ "${_now}" =~ ^[0-9]+$ ]] || return 0
  _cut=$(( _now - _NGINX_I18N_FLOOD_WINDOW ))
  [[ -d "${_I18N_DIR}" ]] || mkdir -p "${_I18N_DIR}" 2>/dev/null
  declare -A _W_REQ _W_SLOW _W_ERR _W_C444
  _tmp="${_state}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  # Carry forward unexpired buckets.
  if [[ -f "${_state}" ]]; then
    while IFS='|' read -r _h _e _r _s _er _c4; do
      [[ -n "${_h}" && "${_e}" =~ ^[0-9]+$ ]] || continue
      (( _e > _cut )) || continue
      printf '%s|%s|%s|%s|%s|%s\n' "${_h}" "${_e}" "${_r:-0}" "${_s:-0}" "${_er:-0}" "${_c4:-0}" >> "${_tmp}"
      _W_REQ["${_h}"]=$(( ${_W_REQ["${_h}"]:-0} + ${_r:-0} ))
      _W_SLOW["${_h}"]=$(( ${_W_SLOW["${_h}"]:-0} + ${_s:-0} ))
      _W_ERR["${_h}"]=$(( ${_W_ERR["${_h}"]:-0} + ${_er:-0} ))
      _W_C444["${_h}"]=$(( ${_W_C444["${_h}"]:-0} + ${_c4:-0} ))
    done < "${_state}"
  fi
  # Add this run's buckets.
  for _h in "${!_I18N_REQ[@]}"; do
    _r=${_I18N_REQ["${_h}"]:-0}; _s=${_I18N_SLOW["${_h}"]:-0}
    _er=${_I18N_ERR["${_h}"]:-0}; _c4=${_I18N_C444["${_h}"]:-0}
    printf '%s|%s|%s|%s|%s|%s\n' "${_h}" "${_now}" "${_r}" "${_s}" "${_er}" "${_c4}" >> "${_tmp}"
    _W_REQ["${_h}"]=$(( ${_W_REQ["${_h}"]:-0} + _r ))
    _W_SLOW["${_h}"]=$(( ${_W_SLOW["${_h}"]:-0} + _s ))
    _W_ERR["${_h}"]=$(( ${_W_ERR["${_h}"]:-0} + _er ))
    _W_C444["${_h}"]=$(( ${_W_C444["${_h}"]:-0} + _c4 ))
  done
  mv -f "${_tmp}" "${_state}" 2>/dev/null
  # Evaluate trips per vhost.
  for _h in "${!_W_REQ[@]}"; do
    _vol=${_W_REQ["${_h}"]:-0}
    _bad=$(( ${_W_SLOW["${_h}"]:-0} + ${_W_ERR["${_h}"]:-0} + ${_W_C444["${_h}"]:-0} ))
    _badp=0
    (( _vol > 0 )) && _badp=$(( 100 * _bad / _vol ))
    _trip=""
    if (( ${_W_C444["${_h}"]:-0} >= _NGINX_I18N_FLOOD_C444_THRESHOLD )); then
      _trip="guardrail-shedding (${_W_C444["${_h}"]} x 444 / ${_NGINX_I18N_FLOOD_WINDOW}s)"
    elif (( _vol >= _NGINX_I18N_FLOOD_MIN_REQS && _badp >= _NGINX_I18N_FLOOD_STRESS_PCT )); then
      _trip="volume+stress (${_vol} localized, ${_badp}% slow/5xx/444 / ${_NGINX_I18N_FLOOD_WINDOW}s)"
    fi
    [[ -n "${_trip}" ]] || continue
    _i18n_cooldown_ok "${_h}" "${_now}" || continue
    _snap="$(_i18n_snapshot "${_h}" "${_trip}")"
    printf '%s I18N-FLOOD vhost=%s %s -> %s\n' "$(date)" "${_h}" "${_trip}" "${_snap}" >> "${_I18N_LOG}"
    echo "=== I18N-FLOOD ${_h}: ${_trip} (snapshot ${_snap}) ==="
  done
}

# Tail the PHP-FPM per-version error logs for NEW "reached max_children setting"
# lines (byte-offset tracked) -- the authoritative pool-saturation signal.  On a
# hit, alert and snapshot the box-wide top talkers for forensics.
_check_fpm_saturation() {
  [[ "${_NGINX_FPM_SAT_DETECT}" == "YES" ]] || return 0
  local _posfile="${_I18N_DIR}/fpm_maxchildren.pos" _tmp _f _sz _off _new _hits _hitf _snap
  [[ -d "${_I18N_DIR}" ]] || mkdir -p "${_I18N_DIR}" 2>/dev/null
  declare -A _POS
  if [[ -f "${_posfile}" ]]; then
    while IFS='|' read -r _f _off; do
      [[ -n "${_f}" && "${_off}" =~ ^[0-9]+$ ]] && _POS["${_f}"]="${_off}"
    done < "${_posfile}"
  fi
  _tmp="${_posfile}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  _hits=0; _hitf=""
  for _f in ${_NGINX_FPM_ERR_GLOB}; do
    [[ -f "${_f}" ]] || continue
    _sz="$(stat -c %s "${_f}" 2>/dev/null)"
    [[ "${_sz}" =~ ^[0-9]+$ ]] || _sz=0
    _off="${_POS["${_f}"]:-0}"
    (( _sz < _off )) && _off=0
    if (( _sz > _off )); then
      _new="$(tail -c +$(( _off + 1 )) "${_f}" 2>/dev/null | grep -c -- "${_NGINX_FPM_SAT_PATTERN}")"
      [[ "${_new}" =~ ^[0-9]+$ ]] || _new=0
      if (( _new > 0 )); then
        _hits=$(( _hits + _new ))
        _hitf="${_hitf} ${_f##*/}(${_new})"
      fi
    fi
    printf '%s|%s\n' "${_f}" "${_sz}" >> "${_tmp}"
  done
  mv -f "${_tmp}" "${_posfile}" 2>/dev/null
  if (( _hits > 0 )); then
    _snap="$(_i18n_snapshot "*" "fpm-max-children${_hitf}")"
    printf '%s FPM-SATURATION new max_children hits:%s -> %s\n' "$(date)" "${_hitf}" "${_snap}" >> "${_I18N_LOG}"
    echo "=== FPM-SATURATION: ${_hits} new max_children hit(s):${_hitf} (snapshot ${_snap}) ==="
  fi
}

# ==============================
# HTTP/1.0 Registration-Spam Detection (opt-in)
# ==============================

# _track_http10_auth IP LINE
# Per-line tally for the opt-in HTTP/1.0 auth-spam detector. Counts a hit only
# when the request line is HTTP/1.0 AND its URI matches an auth path. The
# protocol and URI are taken from the request line ($request log field) via the
# same positional, traversal-rejecting parse as _is_ignored_request -- a token
# smuggled into a User-Agent, Referer, or query string can never fake either
# signal. Whitelisted / locally-allowed / already-banned / private IPs are
# skipped here so they never accumulate window state.
_track_http10_auth() {
  local _IP="$1" _line="$2" _after _req _uri IFS=$' \t\n'
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    return
  fi
  [[ -n "${_BANNED_IPS["${_IP}"]}" ]] && return
  [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] && return
  _is_whitelisted_ip "${_IP}" && return
  # Isolate field 2's quoted "METHOD URI PROTO" request line.
  _after="${_line#*\"*\"}"        # drop the leading "remote_addr" quoted field
  _req="${_after#*\"}"            # advance to the opening quote of $request
  _req="${_req%%\"*}"            # _req = METHOD URI PROTO
  # Require a full "METHOD /path HTTP/1.0" shape. The trailing literal both
  # validates the request-line shape and selects HTTP/1.0 in one step (HTTP/1.1
  # and HTTP/2.0 never match), and the "METHOD /" head guards the positional
  # parse against a forged request token in an earlier field.
  case "${_req}" in [A-Z]*" /"*" HTTP/1.0") : ;; *) return ;; esac
  _uri="${_req#* }"              # strip METHOD
  _uri="${_uri%% *}"            # strip PROTO
  _uri="${_uri%%\?*}"          # strip query string
  [[ "${_uri}" == /* && "${_uri}" != *".."* ]] || return
  [[ "${_uri}" =~ ${_NGINX_HTTP10_AUTH_PATHS} ]] || return
  (( _H10_AUTH["${_IP}"] += 1 ))
}

# _handle_http10_auth_flood
# Merge this run's per-IP HTTP/1.0 auth-path tallies into a cross-run sliding
# window (same persistence shape as _handle_i18n_flood), prune expired buckets,
# then ban each observed IP whose own windowed count crosses the per-IP threshold
# OR whose /24 aggregate crosses the CIDR threshold. The CIDR path escalates a
# slow distributed block cleanly; only IPs actually seen are banned. Runs after
# the DoS/DDoS/path-flood passes so _BANNED_IPS is fully populated, and _block_ip
# re-checks the csf.allow whitelist on every call as the keystone safety net.
_handle_http10_auth_flood() {
  (( _H10_ON )) || return 0
  local _state="${_H10_STATE}" _tmp _now _cut _ip _e _c _net
  _now="$(date +%s)"
  [[ "${_now}" =~ ^[0-9]+$ ]] || return 0
  _cut=$(( _now - _NGINX_HTTP10_AUTH_WINDOW ))
  declare -A _W_IP _W_NET
  _tmp="${_state}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  # Carry forward unexpired per-IP buckets from prior runs.
  if [[ -f "${_state}" ]]; then
    while IFS='|' read -r _ip _e _c; do
      [[ -n "${_ip}" && "${_e}" =~ ^[0-9]+$ ]] || continue
      (( _e > _cut )) || continue
      printf '%s|%s|%s\n' "${_ip}" "${_e}" "${_c:-0}" >> "${_tmp}"
      _W_IP["${_ip}"]=$(( ${_W_IP["${_ip}"]:-0} + ${_c:-0} ))
    done < "${_state}"
  fi
  # Add this run's per-IP tallies.
  for _ip in "${!_H10_AUTH[@]}"; do
    _c=${_H10_AUTH["${_ip}"]:-0}
    (( _c > 0 )) || continue
    printf '%s|%s|%s\n' "${_ip}" "${_now}" "${_c}" >> "${_tmp}"
    _W_IP["${_ip}"]=$(( ${_W_IP["${_ip}"]:-0} + _c ))
  done
  mv -f "${_tmp}" "${_state}" 2>/dev/null
  # Aggregate the windowed per-IP counts per /24.
  for _ip in "${!_W_IP[@]}"; do
    _net="${_ip%.*}"
    _W_NET["${_net}"]=$(( ${_W_NET["${_net}"]:-0} + ${_W_IP["${_ip}"]} ))
  done
  # Ban qualifying IPs (per-IP OR /24 aggregate threshold).
  for _ip in "${!_W_IP[@]}"; do
    _net="${_ip%.*}"
    if (( ${_W_IP["${_ip}"]:-0} >= _NGINX_HTTP10_AUTH_IP_THRESHOLD \
       || ${_W_NET["${_net}"]:-0} >= _NGINX_HTTP10_AUTH_CIDR_THRESHOLD )); then
      [[ -n "${_BANNED_IPS["${_ip}"]}" ]] && continue
      [[ -n "${_ALLOWED_IPS["${_ip}"]}" ]] && continue
      _is_logged_in "${_ip}" && continue
      [[ "${_ip}" == "${_MYIP}" ]] && continue
      _sumar="${_W_IP["${_ip}"]}"
      echo "=== HTTP/1.0 AUTH-SPAM ban ${_ip} [ip=${_W_IP["${_ip}"]}/${_NGINX_HTTP10_AUTH_IP_THRESHOLD} ${_net}.0/24=${_W_NET["${_net}"]}/${_NGINX_HTTP10_AUTH_CIDR_THRESHOLD} win=${_NGINX_HTTP10_AUTH_WINDOW}s] ==="
      _verbose_log "HTTP/1.0 auth-spam ban ${_ip} [ip=${_W_IP["${_ip}"]} net=${_net}.0/24=${_W_NET["${_net}"]}]" "_handle_http10_auth_flood"
      _block_ip "${_ip}" "silent"
    fi
  done
}

# ==============================
# Guard-404 Scraped-Interactive-Path Detection (opt-out)
# ==============================

# _track_guard404 IP LINE
# Per-line tally for the guard-404 repeat-offender detector. Counts a hit only
# when ALL of these hold, which together reproduce exactly what the nginx
# guards themselves block -- never a request they deliberately let through:
#   * method GET or HEAD (the guards' composed maps are keyed the same way),
#   * status 404,
#   * the logged Referer is absent ("-"): a guard verdict is by definition
#     Referer-less, so counting a Referer-carrying 404 on the same path would
#     tally Drupal's own not-found and real visitors along with the botnet,
#   * the User-Agent is not a known-legitimate crawler (_NGINX_HARVEST_UA_EXEMPT
#     -- csf.allow whitelisting covers only the handful of providers
#     guest-water.sh publishes, so the UA list is what protects Applebot,
#     DuckDuckBot, Yandex, Baiduspider, archive.org_bot, the social unfurlers
#     and the uptime probes, exactly as it does for the harvest detector),
#   * the query-stripped URI matches the guard-family path class.
# Status, method, URI, Referer and UA are all read positionally from the log
# line's quoted fields via the same traversal-rejecting parse as
# _track_http10_auth, so a token smuggled into any single field can never fake
# a signal. Whitelisted / locally-allowed / already-banned / private IPs are
# skipped here so they never accumulate window state.
#
# The URI is compared as logged, i.e. the RAW request target, while nginx
# matched its normalised $uri: percent-encoded, doubled-slash and dot-segment
# forms therefore go uncounted even though the guard 404'd them. That
# divergence only ever UNDER-counts (it can never manufacture a hit), which is
# the safe direction for a ban input; duplicate slashes are collapsed below
# because they cost nothing to normalise.
_track_guard404() {
  local _IP="$1" _line="$2" _after _req _rest _st _uri _ref _ua IFS=$' \t\n'
  if [[ "${_IP}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    return
  fi
  [[ -n "${_BANNED_IPS["${_IP}"]}" ]] && return
  [[ -n "${_ALLOWED_IPS["${_IP}"]}" ]] && return
  _is_whitelisted_ip "${_IP}" && return
  # Isolate field 2's quoted "METHOD URI PROTO" request line and the text
  # after its closing quote (which starts with the status code).
  _after="${_line#*\"*\"}"        # drop the leading "remote_addr" quoted field
  _req="${_after#*\"}"            # advance past the opening quote of $request
  _rest="${_req#*\"}"            # text after $request's closing quote: " 404 ..."
  _req="${_req%%\"*}"            # _req = METHOD URI PROTO
  # Require a full "GET|HEAD /path HTTP/x.y" shape; the "METHOD /" head also
  # guards the positional parse against a forged request token in an earlier
  # field.
  case "${_req}" in "GET /"*" HTTP/"*|"HEAD /"*" HTTP/"*) : ;; *) return ;; esac
  _st="${_rest# }"
  _st="${_st%% *}"
  [[ "${_st}" == "404" ]] || return
  # Referer is the next quoted field after the status block, the UA the one
  # after that: ... 404 0 196 122 "$http_referer" "$http_user_agent" ...
  _ref="${_rest#*\"}"
  _ref="${_ref%%\"*}"
  [[ -z "${_ref}" || "${_ref}" == "-" ]] || return
  _ua="${_rest#*\"}"             # advance past the referer's opening quote
  _ua="${_ua#*\"}"              # past the referer's closing quote
  _ua="${_ua#*\"}"              # past the UA's opening quote
  _ua="${_ua%%\"*}"
  if [[ -n "${_NGINX_HARVEST_UA_EXEMPT}" && -n "${_ua}" ]] \
    && [[ "${_ua}" =~ ${_NGINX_HARVEST_UA_EXEMPT} ]]; then
    return
  fi
  _uri="${_req#* }"              # strip METHOD
  _uri="${_uri%% *}"            # strip PROTO
  _uri="${_uri%%\?*}"          # strip query string
  [[ "${_uri}" == /* && "${_uri}" != *".."* ]] || return
  while [[ "${_uri}" == *//* ]]; do _uri="${_uri//\/\//\/}"; done
  [[ "${_uri}" =~ ${_NGINX_GUARD404_PATHS} ]] || return
  (( _G404["${_IP}"] += 1 ))
}

# _handle_guard404_flood
# Merge this run's per-IP guard-404 tallies into a cross-run sliding window
# (same persistence shape as _handle_http10_auth_flood), prune expired
# buckets, then act on each observed IP whose windowed count crosses the
# per-IP threshold -- WOULD-BAN reporting or a real ban, per
# _NGINX_GUARD404_ACTION. Deliberately NO /24 aggregation: this botnet class
# rides ISP-dispersed CGNAT space where a /24 holds real users. After that
# pass, surface the campaign itself: once enough DISTINCT IPs carry windowed
# state at the same time, write one GUARD404-CAMPAIGN line + forensic
# snapshot to the Tier-B alert channel (rate-limited by the cool-down stamp)
# -- per-IP action alone leaves a rotating-IP flood invisible to the operator,
# and the campaign alert is the part that is always safe to run. Runs after
# the other passes so _BANNED_IPS is fully populated, and _block_ip re-checks
# the csf.allow whitelist on every call as the keystone safety net.
_handle_guard404_flood() {
  (( _G404_ON )) || return 0
  local _state="${_G404_STATE}" _tmp _now _cut _ip _e _c _campc _last _snap
  _now="$(date +%s)"
  [[ "${_now}" =~ ^[0-9]+$ ]] || return 0
  _cut=$(( _now - _NGINX_GUARD404_WINDOW ))
  declare -A _W_IP
  _tmp="${_state}.$$"
  : > "${_tmp}" 2>/dev/null || return 0
  # Carry forward unexpired per-IP buckets from prior runs.
  if [[ -f "${_state}" ]]; then
    while IFS='|' read -r _ip _e _c; do
      [[ -n "${_ip}" && "${_e}" =~ ^[0-9]+$ ]] || continue
      (( _e > _cut )) || continue
      printf '%s|%s|%s\n' "${_ip}" "${_e}" "${_c:-0}" >> "${_tmp}"
      _W_IP["${_ip}"]=$(( ${_W_IP["${_ip}"]:-0} + ${_c:-0} ))
    done < "${_state}"
  fi
  # Add this run's per-IP tallies.
  for _ip in "${!_G404[@]}"; do
    _c=${_G404["${_ip}"]:-0}
    (( _c > 0 )) || continue
    printf '%s|%s|%s\n' "${_ip}" "${_now}" "${_c}" >> "${_tmp}"
    _W_IP["${_ip}"]=$(( ${_W_IP["${_ip}"]:-0} + _c ))
  done
  mv -f "${_tmp}" "${_state}" 2>/dev/null
  # Act on qualifying IPs (per-IP threshold only; no CIDR escalation).
  # REPORT logs the decision and bans nothing; BAN arms the heuristic.
  for _ip in "${!_W_IP[@]}"; do
    if (( ${_W_IP["${_ip}"]:-0} >= _NGINX_GUARD404_IP_THRESHOLD )); then
      [[ -n "${_BANNED_IPS["${_ip}"]}" ]] && continue
      [[ -n "${_ALLOWED_IPS["${_ip}"]}" ]] && continue
      _is_logged_in "${_ip}" && continue
      [[ "${_ip}" == "${_MYIP}" ]] && continue
      if [[ "${_NGINX_GUARD404_ACTION}" != "BAN" ]]; then
        printf '%s GUARD404-WOULD-BAN %s [x%s win=%ss]\n' \
          "$(date)" "${_ip}" "${_W_IP["${_ip}"]}" "${_NGINX_GUARD404_WINDOW}" >> "${_I18N_LOG}"
        echo "=== GUARD-404 SCRAPER would-ban ${_ip} [ip=${_W_IP["${_ip}"]}/${_NGINX_GUARD404_IP_THRESHOLD} win=${_NGINX_GUARD404_WINDOW}s] (REPORT mode) ==="
        continue
      fi
      _sumar="${_W_IP["${_ip}"]}"
      echo "=== GUARD-404 SCRAPER ban ${_ip} [ip=${_W_IP["${_ip}"]}/${_NGINX_GUARD404_IP_THRESHOLD} win=${_NGINX_GUARD404_WINDOW}s] ==="
      _verbose_log "guard-404 scraper ban ${_ip} [x${_W_IP["${_ip}"]}]" "_handle_guard404_flood"
      _block_ip "${_ip}" "silent"
    fi
  done
  # Campaign visibility (alert-only; never bans by itself).
  _campc=${#_W_IP[@]}
  if (( _campc >= _NGINX_GUARD404_CAMPAIGN_IPS )); then
    _last=0
    [[ -f "${_G404_CAMP_STAMP}" ]] && _last="$(< "${_G404_CAMP_STAMP}")"
    [[ "${_last}" =~ ^[0-9]+$ ]] || _last=0
    if (( _now - _last >= _NGINX_GUARD404_COOLDOWN )); then
      echo "${_now}" > "${_G404_CAMP_STAMP}"
      _snap="$(_i18n_snapshot "*" "guard404-campaign-${_campc}-ips")"
      printf '%s GUARD404-CAMPAIGN distinct_ips=%s window=%ss -> %s\n' \
        "$(date)" "${_campc}" "${_NGINX_GUARD404_WINDOW}" "${_snap}" >> "${_I18N_LOG}"
      echo "=== GUARD404-CAMPAIGN: ${_campc} distinct IPs hit guarded interactive paths in ${_NGINX_GUARD404_WINDOW}s (snapshot ${_snap}) ==="
    fi
  fi
}

# ==============================
# Processing the Access Log
# ==============================

# Use byte offset tracking to read only new lines since last run (reduces redundant I/O)
_OFFSET_FILE="/var/log/scan_nginx_lastpos"
_last_offset=0
if [[ -f "${_OFFSET_FILE}" ]]; then
  _last_offset=$(< "${_OFFSET_FILE}")
fi
_log_file="/var/log/nginx/access.log"
_current_size=0
if [[ -f "${_log_file}" ]]; then
  _current_size=$(stat -c %s "${_log_file}")
fi
if (( _current_size < _last_offset )); then
  # Log file was rotated or truncated; reset offset to start from beginning
  _last_offset=0
fi

if (( _last_offset == 0 )); then
  # First run or reset: process the last $_NGINX_DOS_LINES lines as a baseline
  exec 3< <(tail -n "${_NGINX_DOS_LINES}" "${_log_file}")
else
  # Process only new log entries since the last recorded byte offset
  exec 3< <(tail -c +$(( _last_offset + 1 )) "${_log_file}")
fi

while IFS= read -r _line <&3; do
  # Extract the first quoted string from the log line (which contains the comma-separated IPs)
  if [[ "${_line}" =~ \"([^\"]*)\" ]]; then
    _ip_str="${BASH_REMATCH[1]}"
  else
    _ip_str=""
  fi

  # Split the IP string by commas and trim spaces
  IFS=',' read -ra _ip_array <<< "${_ip_str}"
  for i in "${!_ip_array[@]}"; do
    _ip_array[i]="${_ip_array[i]## }"
    _ip_array[i]="${_ip_array[i]% }"
  done

  # Collect only valid IPv4 addresses from the IP list.
  # _validate_ip applies both the regex and the per-octet 0..255 range check,
  # so off-spec values like 999.999.999.999 are filtered out here at the
  # collection step rather than relying on csf to reject them downstream.
  # This also keeps the _track_ua_ip / _track_path_flood handlers (which do
  # not call _validate_ip themselves) from accumulating junk keys.
  _IP_LIST=()
  for _ip_candidate in "${_ip_array[@]}"; do
    if _validate_ip "${_ip_candidate}"; then
      _IP_LIST+=("${_ip_candidate}")
    fi
  done

  # Debug: Print extracted IPs if debug mode is enabled
  if [[ -e "/etc/boa/.debug.monitor.cnf" || "${_DEBUG_MONITOR}" = "YES" ]]; then
    echo "DEBUG: Extracted IPs: ${_IP_LIST[*]}"
  fi

  # Resolve the real client as the LAST token of the logged field. The current
  # 'main' format logs a single realip-resolved $remote_addr as field 1 (the
  # spoofable X-Forwarded-For chain is relegated to a trailing xff= field this
  # parser never reads), so the array has one element; the last-token rule is
  # kept because it also stays correct on boxes still logging the older
  # chain-style first field ($proxy_add_x_forwarded_for = client-supplied,
  # spoofable entries with the trustworthy $remote_addr appended last).
  # realip rewrites $remote_addr to the CF-Connecting-IP value only for peers
  # inside the trusted Cloudflare ranges (CF-controlled, NOT client-spoofable)
  # and leaves it as the direct peer otherwise.
  # Act only on a valid, public client. An IPv4 last token bans via csf (IPv4).
  # An IPv6 last token can ONLY be a realip-recovered client from a trusted proxy
  # (BOA disables IPv6 server-side and pins realip to the CF ranges, so no direct
  # IPv6 peer and no spoofable chain entry can appear here) -- so it is scored the
  # same way and banned via the nginx-native IPv6 store (see _block_ip). Gated on
  # _V6_ON so opting out restores the pre-existing IPv4-only behaviour.
  _last_raw="${_ip_array[$(( ${#_ip_array[@]} - 1 ))]:-}"
  if _validate_ip "${_last_raw}" \
    && [[ ! "${_last_raw}" =~ ^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
    _REAL_IP="${_last_raw}"
  elif (( _V6_ON )) && _validate_ip6 "${_last_raw}" && ! _is_private_ip6 "${_last_raw}"; then
    _REAL_IP="${_last_raw}"
  else
    _REAL_IP=""
  fi
  # The X-Forwarded-For chain entries ahead of $remote_addr are spoofable
  # upstream values; never treat them as ban candidates.
  _PROXIES_ARRAY=()

  # Debug: Echo the determined real visitor IP and proxy IPs if debug mode is enabled
  if [[ -n "${_REAL_IP}" && ( -e "/etc/boa/.debug.monitor.cnf" || "${_DEBUG_MONITOR}" = "YES" ) ]]; then
    echo "=== checking ${_REAL_IP} / _LI_CNT ==="
  fi
  if [[ -e "/etc/boa/.debug.monitor.cnf" || "${_DEBUG_MONITOR}" = "YES" ]]; then
    for _proxy_ip in "${_PROXIES_ARRAY[@]}"; do
      [[ -n "${_proxy_ip}" ]] && echo "=== checking ${_proxy_ip} / _PX_CNT ==="
    done
  fi

  # Skip internal Ægir file server requests — *.files.{boa.io,o8.io,host8.biz,
  # aegir.cc} hostnames appear in the log's vhost field and must not feed counters,
  # UA tracking, or path-flood detection. Matched on the parsed $host vhost field
  # only (not the whole line), so a "files.*" token in a spoofed URI/Referer/UA
  # cannot launder the full-bypass exemption. At loop scope so it exempts all three
  # scorers (_process_ip, _track_ua_ip, _track_path_flood).
  _is_internal_fileserver "${_line}" && continue

  # Skip configured webhook / API endpoints (_NGINX_DOS_IGNORE_PATHS). Parsed
  # from the real $request URI, not the whole line, so it cannot be laundered via
  # a spoofed UA/Referer/query. At loop scope so it exempts ALL three scorers
  # (per-IP _process_ip, UA-aggregate _track_ua_ip, path-flood _track_path_flood)
  # -- a per-IP-only skip would miss the UA-aggregate ban on a provider's
  # rotating IP pool.
  _is_ignored_request "${_line}" && continue

  # Process the real visitor IP (if determined)
  if [[ -n "${_REAL_IP}" ]]; then
    _process_ip "${_REAL_IP}" "_LI_CNT" "${_line}"
  fi
  # Process each proxy IP (if any were identified as needing blocking)
  for _proxy_ip in "${_PROXIES_ARRAY[@]}"; do
    if [[ -n "${_proxy_ip}" ]]; then
      _process_ip "${_proxy_ip}" "_PX_CNT" "${_line}"
    fi
  done

  # ---- DDoS / Shared-UA tracking + upstream time extraction ----
  # The log format ends: ..."UA" $request_time "$gzip_ratio" proto=...
  # We capture the final quoted UA token and the decimal REQUEST time that
  # follows it -- not upstream time; the log has no upstream field at all.
  # Both values are reused by the path-flood tracker below,
  # so extracting them once here avoids a second regex match per line.
  _DDOS_UA=""
  _REQ_TIME="0"
  if [[ -n "${_REAL_IP}" && "${_line}" =~ \"([^\"]+)\"\ ([0-9]+\.[0-9]+) ]]; then
    _DDOS_UA="${BASH_REMATCH[1]}"
    _REQ_TIME="${BASH_REMATCH[2]}"
    # Only track if UA is non-trivial (longer than 10 chars) and the line is
    # not a redirect (301) so we stay consistent with _process_ip filtering.
    if [[ ${#_DDOS_UA} -gt 10 && ! "${_line}" =~ \"\ 301 ]]; then
      _track_ua_ip "${_REAL_IP}" "${_DDOS_UA}"
    fi
    # UA-burst scanner-fleet tracker.  Unlike the line above this INCLUDES 301
    # redirects, since the distributed probe fleet's redirect-heavy traffic is
    # the very signal the 301-excluding scorers miss.  Gated on _UAB_ON so the
    # hot loop pays nothing when the detector is opted out.
    if (( _UAB_ON )) && [[ ${#_DDOS_UA} -gt 10 ]]; then
      _UAB_ST=""
      _UAB_ST_RE='"\ ([0-9]{3}) '
      if [[ "${_line}" =~ ${_UAB_ST_RE} ]]; then
        _UAB_ST="${BASH_REMATCH[1]}"
        _track_ua_burst "${_REAL_IP}" "${_DDOS_UA}" "${_UAB_ST}"
      fi
    fi
  fi

  # ---- Path-flood / search-amplification tracking ----
  # Extract the HTTP status code for this line and feed matching requests to
  # _track_path_flood for aggregate flood detection and reporting.
  #
  # 200s: consumed real backend resources -- tracked for resource-exhaustion
  #       flood detection via _PATH_SLOW_COUNT and IP/req thresholds.
  # 444s: Nginx blocked the request before it touched the backend.
  #       Passing them here populates aggregate path/IP counts so the flood
  #       report is accurate and _handle_path_flood_blocking catches distributed
  #       IPs that the per-IP counter threshold alone would miss.
  if [[ -n "${_REAL_IP}" && ${#_WATCH_PATTERNS[@]} -gt 0 ]]; then
    _LINE_STATUS=""
    _STATUS_RE='"\ ([0-9]{3}) '
    if [[ "${_line}" =~ ${_STATUS_RE} ]]; then
      _LINE_STATUS="${BASH_REMATCH[1]}"
    fi
    if [[ "${_LINE_STATUS}" == "200" || "${_LINE_STATUS}" == "444" ]]; then
      for _WPFX in "${_WATCH_PATTERNS[@]}"; do
        if [[ -n "${_WPFX}" && "${_line}" =~ ${_WPFX} ]]; then
          _track_path_flood "${_REAL_IP}" "${_WPFX}" "${_LINE_STATUS}" "${_REQ_TIME}"
          # Stop after the first matching prefix to avoid double-counting a
          # single request against multiple overlapping patterns.
          break
        fi
      done
    fi
  fi

  # ---- Distributed localized (i18n) translation-flood tracking (Tier B) ----
  # Aggregate localized requests per vhost (a non-IP key) for the cross-run
  # windowed detector evaluated after the loop.  files.*, the webhook
  # ignore-list and Site24x7 are already skipped at loop scope above, so they
  # never reach here.  Matches a leading two-letter language prefix on the
  # request path (optionally with a script/region suffix, e.g. /pt-br/,
  # /zh-hans/) and the D7 ?q=<lang>/ form, mirroring the Tier-A guardrail class.
  # Lines whose client field is exactly 127.0.0.1 are skipped: a request riding
  # a local 443 front (wild-ssl proxy) logs twice -- once at the front with the
  # real visitor and once at the port-80 backend as loopback -- and counting
  # both would halve the detector's effective per-vhost thresholds.
  if (( _I18N_ON )) && [[ "${_line}" != '"127.0.0.1" '* ]] \
    && [[ "${_line}" =~ ${_I18N_LINE_RE} ]]; then
    _LH="${BASH_REMATCH[1]}"
    _LP="${BASH_REMATCH[2]}"
    _LS="${BASH_REMATCH[3]}"
    if [[ "${_LP}" =~ ^/[A-Za-z][A-Za-z](-[A-Za-z]+)?/ \
       || "${_LP}" =~ [?\&]q=/?[A-Za-z][A-Za-z](-[A-Za-z]+)?/ ]]; then
      _track_i18n_flood "${_LH}" "${_LS}" "${_REQ_TIME}"
    fi
  fi

  # ---- HTTP/1.0 registration-spam botnet tracking (on by default, opt-out) ----
  # Counts HTTP/1.0 requests to auth paths per real client IP for the cross-run
  # windowed ban below. files.*, the webhook ignore-list and Site24x7 are already
  # skipped at loop scope above, so they never reach here.
  if (( _H10_ON )) && [[ -n "${_REAL_IP}" ]]; then
    _track_http10_auth "${_REAL_IP}" "${_line}"
  fi

  # ---- Guard-404 scraped-interactive-path tracking (on by default, opt-out) ----
  # Counts guard-family 404s per real client IP for the cross-run windowed ban
  # below. files.*, the webhook ignore-list and Site24x7 are already skipped at
  # loop scope above, so they never reach here.
  if (( _G404_ON )) && [[ -n "${_REAL_IP}" ]]; then
    _track_guard404 "${_REAL_IP}" "${_line}"
  fi

done

# Close the file descriptor for the log input
exec 3<&-

# Record the new end-of-file offset for next run
if [[ -f "${_log_file}" ]]; then
  stat -c %s "${_log_file}" > "${_OFFSET_FILE}"
fi

# ==============================
# Execute Blocking Logic
# ==============================

_handle_blocking _LI_CNT "li_cnt"
_handle_blocking _PX_CNT "px_cnt"

# DDoS / Shared-UA flood blocking (runs after per-IP counters so _BANNED_IPS
# is already populated and we avoid double-blocking IPs caught by the DoS pass)
_handle_ddos_blocking

# Distributed UA-burst scanner-fleet blocking (on by default, opt-out).  Runs
# after the per-IP and DDoS-UA passes so _BANNED_IPS is populated and we avoid
# re-processing IPs already caught; this pass adds the redirect-heavy
# distributed fleets the 301-excluding scorers above cannot see.
_handle_ua_burst_blocking

# Path-flood / search-amplification blocking (runs last so _BANNED_IPS reflects
# everything caught by the DoS and DDoS passes above; distributed bots that
# slipped through per-IP rate checks are caught here by the aggregate path count)
_handle_path_flood_blocking

# HTTP/1.0 registration-spam blocking (on by default, opt-out). Cross-run
# windowed; runs after the passes above so _BANNED_IPS is fully populated and
# double-blocking avoided.
_handle_http10_auth_flood

# Guard-404 scraped-interactive-path blocking + campaign surfacing (on by
# default, opt-out). Cross-run windowed; runs after the passes above so
# _BANNED_IPS is fully populated and double-blocking avoided.
_handle_guard404_flood

### Runs last: the four existing scorers have already populated _BANNED_IPS,
### so this layer never double-bans and never changes their authority.
_handle_harvest_blocking

# Tier B: evaluate the cross-run distributed-i18n-flood window and tail the
# PHP-FPM error logs for new pool-saturation events.  These detect, alert and
# snapshot only -- the inline Tier-A guardrail does the real-time capping.
_handle_i18n_flood
_check_fpm_saturation

echo "CONTROL complete for ${_MYIP}"
exit 0
