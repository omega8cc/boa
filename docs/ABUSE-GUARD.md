# Nginx Abuse Guard (sysadmin)

The Abuse Guard is BOA's application-layer defence for the web tier — the net that
sits between the firewall and PHP-FPM and keeps scanners, brute-forcers and
distributed search-amplification botnets off your backend. It has two halves that
work on different clocks: a wall of real-time nginx `map`/`geo` guards that drop or
downgrade a hostile request before it costs anything, and a post-hoc log scorer
(`scan_nginx.sh`) that reads recent `access.log` lines, scores each real client, and
feeds genuine offenders into CSF. The firewall ban then flows back into nginx so the
next request from that IP is closed silently. Most of it runs itself; this page is for
when you need to read its state, lift a ban, whitelist a service, or extend it.

The defining property: **detection is post-hoc, enforcement is real-time.** The scorer
cannot block mid-burst — it analyses lines that already happened and produces a *ban for
the next visit*. A scanner firing 75 requests in 20 seconds completes before the next
scan tick; those requests are served cheaply (a `.php` probe gets a no-FPM `404`) and the
IP is blocked for its next visit, then self-unbanned when it stops.

This file covers the whole mechanism. Sibling docs: per-class AI bot handling is in
[AI-POLICY.md](AI-POLICY.md), per-site IP allow/deny in [IP-ACCESS.md](IP-ACCESS.md), the
general security model in [SECURITY.md](SECURITY.md), and the tag/auto-update mechanism in
[SKYNET.md](SKYNET.md).

## The end-to-end pipeline

```
nginx access.log
   │  (nginx_guard.sh tick — scan_nginx reads new lines since the last byte offset)
   ▼
scan_nginx.sh ── scores each real client IP across 3 detectors ──┐
   │  writes offenders                                            │
   ▼                                                              │
web.log  +  scan_nginx.archive.log                                │
   │                              │                               │
   ▼                              ▼                               │
guest-fire.sh               guest-water.sh                        │
web.log → csf -td 900       archive ≥12 hits → csf.deny           │
(temporary, 15 min)         "Brute force Web Server"              │
                            (persistent; ≥24 = do not delete)     │
   │                              │                               │
   └──────────────┬───────────────┘                              │
                  ▼                                               │
        /etc/csf  (csf.tempban 80/443  +  csf.deny)               │
                  │                                               │
                  ▼                                               │
        nginx_deny.sh  (regenerate the geo from current csf)      │
                  │                                               │
                  ▼                                               │
        /data/conf/nginx_banned_ips.conf                          │
                  │                                               │
                  ▼                                               │
        geo $remote_addr $is_banned   (nginx) ◄───────────────────┘
                  │
                  ▼
        return 444   (silent drop, zero backend cost)
```

Each box is a separately-scheduled BOA script, and none of them trusts the others
blindly — every stage re-checks the CSF allow list before it acts. The geo file is a
**derived mirror** of CSF, fully regenerated each pass, so bans self-expire with no
manual cleanup.

| Component | File | Role |
|---|---|---|
| Real-time guards | `server.tpl.php` (maps) + `Inc/vhost_include.tpl.php` (rules) | Classify and drop/downgrade each request |
| Log scorer | `aegir/tools/system/monitor/check/scan_nginx.sh` | Score IPs from `access.log`, write `web.log` |
| Scorer launcher | `aegir/tools/system/monitor/check/nginx_guard.sh` | Run scan_nginx 10× per minute (5 s apart) |
| Temp-ban applier | `aegir/tools/system/guest-fire.sh` | `web.log` → `csf -td 900` (80/443) |
| Persistent escalator | `aegir/tools/system/guest-water.sh` | Archive repeat offenders → `csf.deny` |
| Geo regenerator | `aegir/tools/system/nginx_deny.sh` | CSF state → `nginx_banned_ips.conf` → reload |

The nginx-template files live in the `provision` codebase under
`http/Provision/Config/Nginx/`; the scripts live in `boa-private`. On a box, the scripts
are deployed under `/var/xdrago/`.

## Part 1 — the scan_nginx scoring engine

`scan_nginx.sh` is the detection half. On each tick it reads a window of recent
`access.log` lines, scores every real client IP across three independent detectors, and
writes offenders to `/var/xdrago/monitor/log/web.log` — the entry point of the ban
pipeline. It never sits in the request path and cannot block a request in flight.

### Run model

```
nginx_guard.sh tick (10 passes/min, 5 s apart)
   ↓
re-entrancy guard (shared lock.inc; legacy pgrep fallback exits if >2 instances)
   ↓
load config: built-in defaults, then source /root/.barracuda.cnf (replaces any value)
   ↓
read access.log from the last byte offset (incremental)
   ↓
for each line:  resolve real IP → exemption gate → 3 detectors
   ↓
_handle_blocking / _handle_ddos_blocking / _handle_path_flood_blocking
   ↓
write offenders to web.log + scan_nginx.archive.log
```

- **Window.** Each run reads new bytes since the last position recorded in
  `/var/log/scan_nginx_lastpos`. On a first run, or if the log was rotated/truncated
  (current size < saved offset), the offset resets and the last `_NGINX_DOS_LINES` lines
  (default **1999**) are taken as a baseline.
- **Config precedence.** Built-in defaults are assigned first, then
  `/root/.barracuda.cnf` is sourced and **replaces** any value it sets — a plain
  assignment, not a merge.

### Resolving the real client IP

The log records the IP chain as `"$proxy_add_x_forwarded_for"` (the X-Forwarded-For
values with `$remote_addr` appended last). `scan_nginx` scores **only the last token of
the chain** — the value nginx's realip module rewrote `$remote_addr` to (the
CF-Connecting-IP on Cloudflare vhosts, or the direct peer otherwise). The earlier
X-Forwarded-For entries are client-supplied and spoofable, so they are **never** scored
or banned.

- The real client must be a valid, public **IPv4** address. This script bans via CSF
  (IPv4 here), so an IPv6 last token is left unhandled rather than mis-attributed.
- Private ranges (`10.`, `127.`, `169.254.`, `192.168.`, `172.16–31.`) are skipped.
- The forwarded-for proxy array is deliberately left empty — upstream proxies are never
  ban candidates.

> **Realip dependency — a bad trust chain scores the wrong IP.** If the realip trust
> chain is wrong (e.g. a customer's own reverse proxy is not in `set_real_ip_from`),
> every request through it is attributed to the *proxy's* address. The Abuse Guard then
> scores that one IP for all the traffic behind it and can ban the whole site. Getting
> realip right (via `cloudflare_realip.sh` / `migration_proxy_realip.sh` and the rendered
> `set_real_ip_from` ranges) is a prerequisite, not an optional extra. Symptom: a single
> upstream/CDN IP racking up a huge score for traffic that is obviously many clients.

### The exemption gate

Immediately after the IP is resolved, and **before any detector runs**, each line is
tested against `_NGINX_DOS_IGNORE_PATHS`, a space-separated list of URI prefixes that must
never be scored. Because the test runs at loop scope (a `continue`), an exempt line is
skipped by **all three** detectors at once.

This exists because machine/API endpoints authenticate per request at the application
layer (HMAC, OAuth tokens), not by IP — so IP-counting them is always wrong. A webhook
provider (Shopify, QuickBooks, Stripe…) delivers in bursts from a rotating pool; an API
client is simply high-volume. Either pattern otherwise reads as a per-IP or shared-UA
flood and self-bans a legitimate caller. Default list:

```
/shopify/webhook /quickbooks/webhook /stripe/webhook
/paypal/webhook /github/webhook /gitlab/webhook
/graphql /public-api /oauth2
```

The match is deliberately strict and laundering-proof:

- It parses the **real `$request` URI** out of the line — not a substring search over the
  whole line — so a token smuggled into a User-Agent, Referer, or query string cannot
  forge an exemption.
- It requires a full `METHOD /path HTTP/x` shape, strips the query string, and refuses any
  URI containing `..` or a `%` escape (an encoded traversal like
  `/shopify/webhook/%2e%2e/wp-login.php` is scored, not exempted).
- Each entry matches as an exact path **or** a sub-path prefix (`/graphql` exempts
  `/graphql/api/endpoint`).
- It is **status-agnostic** — a `444` on an exempt path is also skipped, which is what
  stops a banned webhook IP's retries from re-feeding its own score.

The defaults ship in the script (not only the per-box override) so the exemption survives
a `/root/.barracuda.cnf` regeneration. An override **replaces** the whole list — include
everything the box needs; an empty value disables the feature.

> **Under the hood — the function-IFS gotcha.** The script runs under a global
> `IFS=$'\n\t'` (no space), so any function that word-splits a space-separated value must
> set a function-local whitespace IFS first or the split collapses to one token and
> silently matches nothing. `_is_ignored_request` sets `local … IFS=$' \t\n'`; the two
> aggregate handlers use the `_SAVE_IFS="${IFS}"; IFS=' '; …; IFS="${_SAVE_IFS}"`
> save/restore idiom. A space-split helper tested interactively passes but fails
> in-script — when one "matches nothing", suspect the inherited IFS before re-auditing the
> matching logic.

### Detector 1 — per-IP scoring

`_process_ip` accumulates a weighted counter per real IP. The weights derive from
`_NGINX_DOS_LIMIT` (default **399**):

| Event | Weight added | Default value |
|---|---|---|
| SQLi / blind-timing pattern match (`_NGINX_DOS_STOP`) | `+ _NGINX_DOS_LIMIT` | 399 — one hit saturates the score to the limit; a block still needs score *above* the limit plus the 3-request floor |
| Any `400/403/404/410/444/500` response | `_INC_NR` | ≈ 10 (`LIMIT/40`, min 3) |
| `444` on a *watched* attack path | `+ _NGINX_DOS_444_WEIGHT` | ≈ 133 (`LIMIT/3`) |
| `.php` request **path** that `404`s (webshell probe) | `+ _NGINX_PHP_PROBE_WEIGHT` | ≈ 133 (`LIMIT/3`) |
| `wp-(content\|admin\|includes\|json)` anywhere in the line | `+ _INC_NR` | ≈ 10 |
| `GET`/`POST` to `/user/login` | `+ _INC_S_NR` | ≈ 5 (`LIMIT/80`, min 3) |

The first row is the heaviest: a line matching the `_NGINX_DOS_STOP` regex adds the
**entire** `_NGINX_DOS_LIMIT` at once. The default is a SQLi blind-timing fingerprint set
— `WAITFOR.DELAY|DECLARE.*@x|/\*\*/|%27.*%29.*%3B|0x[0-9a-f]{6}` — matched unanchored
against the whole log line, and evaluated in **both** DoS modes.

An IP is written to `web.log` when its score crosses the limit **and** it made at least
`_NGINX_MIN_BLOCK_REQS` (default 3) raw requests in the window. The raw-request floor stops
a single heavily-weighted hit from banning a one-request IP.

> **Under the hood.** The block threshold compared in `_handle_blocking` is
> `_MININUMBER = (_NGINX_DOS_LIMIT + 1) / 2` for the first gate, and the IP is only banned
> when its score also exceeds `_CRITNUMBER` (normally `_NGINX_DOS_LIMIT`). Two session
> shields raise `_CRITNUMBER` to a sentinel so the IP is effectively never banned: an IP
> with an active SSH session (`_is_logged_in`) → `9999`, and the box's own `_MYIP` →
> `9998`.

A second tier of `+5` increments fires **only when `_NGINX_DOS_MODE=1`** (default is mode
**2**, where they are inactive):

| Event (mode 1 only) | Weight added |
|---|---|
| `POST /[xx/]?(user\|user/(register\|pass\|login)\|node/add)` | `+ 5` |
| `GET /[xx/]?node/add` | `+ 5` |
| `GET /[xx/]?search` | `+ 5` |

The optional `[xx/]` prefix matches a two-letter language segment (e.g. `/de/search`).
On a default (mode-2) box these add nothing.

Worked examples, with defaults:

- **Webshell scanner.** A `.php` probe that `404`s scores ~133 per hit; three hits → 399 ≥
  limit → blocked in ~3 requests instead of ~140. A single stale `.php` link from a real
  visitor scores 133 once — below the limit and below the 3-request floor — so it never
  bans. Heavy weight that does not saturate is false-positive-safe.
- **Ordinary 404 noise.** A normal missing page scores ~10; it takes ~40 such hits to reach
  the limit, so incidental 404s don't ban.

The `.php`-probe weight is path-anchored (the `.php` must be in the request path, not the
query string/Referer/UA) and excludes legitimate entry points
(`index`, `update`, `install`, `cron`, `xmlrpc`, `authorize`, `restore`, `rebuild`,
`boost_stats`, `rtoc`, `js`). On a 4 GB box this means a routine bot sweep for
`shell.php`, `c99.php`, `wp-load.php` self-bans in seconds with no PHP bootstrap, while
your own `/index.php` and cron never accrue probe weight.

### Detector 2 — shared-UA aggregate (DDoS)

Distributed floods often share one machine User-Agent across many rotating IPs.
`_track_ua_ip` builds, per UA, the set of distinct real IPs and the total request count.
After the loop, `_handle_ddos_blocking` declares a UA an attack fingerprint when **either**
threshold is crossed:

| Threshold | Default | Meaning |
|---|---|---|
| `_NGINX_DDOS_UA_IP_THRESHOLD` | 100 | distinct IPs sharing the UA |
| `_NGINX_DDOS_UA_REQ_THRESHOLD` | 1000 | total requests under the UA |

When a UA is flagged, every contributing IP that made at least `_NGINX_DDOS_IP_MIN_REQS`
(default 20) requests with it is blocked. The per-IP minimum keeps incidental hits
from a shared egress (one Cloudflare PoP, a CGNAT or Apple-Private-Relay address) out of
the block list. UAs of 10 characters or fewer are ignored to avoid matching empty or
trivial agents. This is the detector that, before the path-exemption existed, banned an
entire webhook provider's rotating pool on its shared `Shopify-Captain-Hook` / `GuzzleHttp`
UA — which is why the exemption gate runs at loop scope and covers this detector too.

**Window and tuning (revised after the am095 incident).** Every threshold here is measured
against a short window: `nginx_guard.sh` runs `scan_nginx.sh` about every 5 s and
byte-offset tracking means each run scores only the lines appended since the previous run.
The original defaults (20 IPs / 200 reqs / 3-request block) sat far below real traffic for
that window — on a high-traffic public site the single most common mobile-browser UA string
is shared by far more than 20 distinct IPs (and 200 requests) every 5 s, so the detector
flagged a legitimate popular browser and banned every visitor making ≥ 3 requests under it.
Search sessions were hit hardest because one search fires several requests under one UA
(results page + per-keystroke autocomplete + AJAX views + result clicks). A genuine
distributed botnet *randomises* its UA per IP, so a single UA shared by many IPs is the
signature of a real browser, not a bot. The defaults are now 100 IPs / 1000 reqs /
20-request block; genuinely abusive single IPs are still caught by Detector 1 (per-IP
weighted score) and Detector 3 (path-flood). See **Recovering from false positives** below
to release IPs that an over-tight box already banned.

### Detector 3 — path-flood aggregate

The hardest pattern is a botnet sending **one request per IP**: no single address ever
trips a per-IP limit. `_track_path_flood` counts both `200` and `444` traffic to each
watched expensive-path prefix across all IPs, and `_handle_path_flood_blocking` blocks
every qualifying participant once a prefix is declared under flood:

| Threshold | Default | Meaning |
|---|---|---|
| `_NGINX_PATH_FLOOD_IP_THRESHOLD` | 30 | distinct IPs on the prefix (200 + 444) |
| `_NGINX_PATH_FLOOD_REQ_THRESHOLD` | 100 | total 200 + 444 responses to the prefix |
| `_NGINX_PATH_FLOOD_IP_MIN_REQS` | 20 | per-(prefix, IP) **200**-response count before that IP is listed |
| `_NGINX_PATH_FLOOD_SLOW_SECS` | 3 | upstream seconds above which a 200 is "slow" |

The flood **declaration** counts both `200` and `444` (so distributed bots the real-time
guards already `444` are still caught and reported in aggregate). The per-IP **listing /
`csf -td` gate** counts **only `200` responses** — backend-reaching requests that actually
cost a Solr / PHP-FPM cycle. An IP whose hits to the watched prefix were all `444` is
already free-blocked by nginx at zero backend cost, so it is **not** individually banned: a
`csf -td` on it would be redundant, would bloat `web.log` during distributed `444` floods,
and risks false-positiving CGNAT / shared-egress clients. A `200` slower than
`_NGINX_PATH_FLOOD_SLOW_SECS` earns an extra per-IP increment. Watched prefixes come from
`_NGINX_PATH_FLOOD_WATCH` (Solr / Search-API / facet endpoints by default); this detector
was built for search-amplification attacks that bypass simple `444` rules by adding a
Referer.

### Detector 4 — HTTP/1.0 registration-spam (auth paths)

A credential / registration-spam botnet POSTs scam payloads to the Drupal auth paths
(`/user/register`, `/user/password`) over **HTTP/1.0** while forging a modern-browser
User-Agent. HTTP/1.0 is the clean transport-layer tell: no browser built in ~15 years speaks
HTTP/1.0 to a public HTTPS host, so HTTP/1.0 to an auth path is never a real visitor. The bot
paces **one slow request per IP** from a small CIDR block (a `/29` was the reference case),
which defeats Detectors 1–3 at once — the per-IP scorer never reaches its raw-request floor
inside a window, the shared-UA aggregate needs ~100 IPs, and the path-flood watch list is
Solr/search-only. An inline per-site `444` guard can drop this traffic at nginx; this
detector turns the same HTTP/1.0-to-auth-path signal into a **CSF ban** so the firewall drops
the source before nginx.

`_track_http10_auth` tallies, per real client IP, requests whose **request line** is HTTP/1.0
and whose URI matches `_NGINX_HTTP10_AUTH_PATHS`. Both the protocol and the URI are read from
the `"$request"` log field via the same positional, traversal-rejecting parse as the
exemption gate, so a token smuggled into a User-Agent, Referer or query string can never fake
either signal. After the loop the per-IP tallies merge into a sliding window that **spans
runs** (a small state file at `/var/xdrago/monitor/log/http10_auth.window`, pruned each tick,
exactly like the i18n window) — necessary because the bot is far too slow to accumulate
inside one ~5 s scan window. `_handle_http10_auth_flood` then bans a **seen** IP once either:

| Threshold | Default | Meaning |
|---|---|---|
| `_NGINX_HTTP10_AUTH_IP_THRESHOLD` | 3 | windowed HTTP/1.0 auth-path hits from that IP |
| `_NGINX_HTTP10_AUTH_CIDR_THRESHOLD` | 6 | windowed hits aggregated over the IP's `/24` |

The `/24` aggregate escalates the slow distributed block cleanly — the group crosses the
threshold long before any single trickling address would — while only IPs **actually
observed** sending HTTP/1.0 to an auth path are banned, never an unseen address in the `/24`.
A lone stray HTTP/1.0 hit stays below both thresholds and never bans. The ban reuses
`_block_ip` (so the csf.allow whitelist, logged-in, local-IP and already-banned guards all
apply) and feeds the same `guest-fire` → `guest-water` pipeline as every other detector.

The detector is **on by default**, opt-out per box (`_NGINX_HTTP10_AUTH_DETECT=NO`); the
per-line tally is skipped entirely when off. One caveat drives that opt-out: `$server_protocol`
is the protocol on the connection to **this** nginx, not the realip-recovered client's, so a
reverse proxy that forwards to origin over HTTP/1.0 would make all proxied traffic look like
HTTP/1.0 here. BOA's own proxy layer (the migration / PX0 `*_proxy.conf` and the wildcard-SSL
`nginx_wild_ssl.conf`) sets `proxy_http_version 1.1`, so a correctly-updated BOA front proxy
no longer downgrades and real visitors stay HTTP/1.1 / HTTP/2 at origin. **Opt out** only on a
box still fronted by a non-BOA proxy or CDN that talks HTTP/1.0 to origin, or not yet updated
to the HTTP/1.1 proxy confs (see **Part 5**). A malformed `_NGINX_HTTP10_AUTH_PATHS` override
fails closed — the detector counts nothing rather than mis-banning.

### Distributed-i18n-flood detection and the FPM saturation trigger

Detectors 1–3 score and ban individual IPs. A distributed flood of **localized**
(translation) pages defeats all three at once: the source spreads over thousands of IPs at
one or two requests each (so the per-IP and shared-UA scorers never trip), and the watched
path list is Solr/search-only (so the path-flood aggregate never sees `/de/…`,
`/zh-hans/…` and the rest). Each uncached localized page runs a synchronous on-the-fly
translation that holds a PHP-FPM worker for tens of seconds, so enough concurrent ones
saturate the shared per-account pool and collapse every site on it.

The real-time **capping** is an inline nginx guardrail (the Tier-A `limit_conn
boa_i18n_anon`, see Part 3). `scan_nginx` adds the **detection** half — it alerts and
snapshots, and **does not ban per IP** (futile against a distributed source); the guardrail
does the actual capping, and any genuinely concentrated offender is still caught by
Detector 1.

- **Distributed-i18n-flood detector.** Per line, localized requests (a leading two-letter
  language prefix on the path, or the D7 `?q=<lang>/` form) are tallied **per vhost** — a
  non-IP key. After the loop the tallies merge into a sliding window that **spans runs** (a
  small state file, pruned each tick), and a vhost trips on either:
  - **guardrail-shedding** — a burst of the `444`s the Tier-A `limit_conn` emits the instant
    anonymous-localized concurrency exceeds its cap (≥ `_NGINX_I18N_FLOOD_C444_THRESHOLD` in
    the window). This is the earliest and most symmetric signal: it lights up ~60–90 s
    before FPM saturation, where the lagging backend-stress signal alone trips only at the
    ceiling;
  - **volume + stress** — windowed localized volume (≥ `_NGINX_I18N_FLOOD_MIN_REQS`) with an
    elevated slow/`5xx`/`444` share (≥ `_NGINX_I18N_FLOOD_STRESS_PCT` %), for a vhost opted
    out of Tier A. A cache-warm recon burst (high volume, ~0 % stress) stays below the
    stress gate and never trips — the gate is what separates a flood from a popularity spike.

  On a trip it appends to `/var/xdrago/monitor/log/i18n_flood.log` and writes a forensic
  snapshot (top client IPs / UAs / language-prefixes for that vhost) under
  `/var/xdrago/monitor/log/i18n_flood/`, with a per-vhost cool-down so a multi-minute burst
  yields a handful of records, not one per tick. The same loop-scope skips (`files.*`,
  `_NGINX_DOS_IGNORE_PATHS`, Site24x7) run first, so monitors and webhooks are never classed,
  and it keys on the realip'd client and vhost, never the CF/PX0 edge.

- **FPM saturation trigger.** Byte-offset-tails the per-version PHP-FPM error logs
  (`/var/log/php/php*-fpm-error.log`) for **new** `reached max_children setting` lines — the
  authoritative "a pool just ran out of workers" signal, captured the instant it happens. (
  `php.sh` greps the **global** `process.max` ceiling, which BOA sets to `0` = disabled, so
  it never sees this per-pool event, and the periodic `fpmreport` sampler misses the live
  peak too.) On a new hit it alerts and snapshots the box-wide top talkers.

Both run after the existing blocking passes and are gated on `_NGINX_I18N_FLOOD_DETECT` /
`_NGINX_FPM_SAT_DETECT` (default `YES`); the per-line tally is skipped entirely when the
detector is off, so the hot loop pays nothing.

### Whitelisting (scorer side)

Three layers protect known-good addresses from every detector:

- **CSF allow list.** `_is_whitelisted_ip` refuses to block any IP the firewall already
  allows (exact host or CIDR). It is a keystone guard covering every call path into
  `_block_ip` — including the bulk DDoS and path-flood passes — so a bulk ban can't drop a
  CDN PoP or a search-engine crawler. The allow is honoured **on every port** regardless of
  the port scope of the `csf.allow` entry (an `s=` record means "trusted source").
- **`/root/.local.IP.list`.** Loaded into `_ALLOWED_IPS`; these IPs are never scored.
- **In-run cache.** `_BANNED_IPS` (seeded from the current `web.log`) prevents an IP being
  written twice in one pass.

To exempt a monitoring service fleet-wide, add its published IPs to the CSF allow list
rather than exempting a path.

> **Note — there is no successful-login skip in scan_nginx.** The "don't ban an IP that
> just logged in" logic lives in the SSH/login monitor `hackcheck.sh`, which builds an
> `_accepted` set from `grep -F 'Accepted ' auth.log` and never bans those IPs.
> scan_nginx's *web*-side login handling is the inverse — it *adds* weight on `/user/login`
> floods. Do not expect a recent web login to protect an IP here. The one session shield
> scan_nginx has (`_is_logged_in`, threshold raised to `9999`) keys off **active SSH
> sessions** (`netstat` ESTABLISHED on port 22), not any web or `auth.log` login. For a
> durable, protocol-independent exemption use `csf.allow` or `/root/.local.IP.list`.

### Output

When a detector decides to block, `_block_ip`:

1. appends `IP # [xSCORE] TIMESTAMP` to `/var/xdrago/monitor/log/web.log` and to
   `/var/xdrago/monitor/log/scan_nginx.archive.log` (skipping IPs already in the in-run
   cache);
2. if `/etc/boa/.instant.csf.block.cnf` exists, also issues `csf -td 900` on ports 80 and
   443 immediately, shaving one hop off the pipeline.

`web.log` feeds the temporary-ban applier; `scan_nginx.archive.log` feeds the persistent
escalator.

## Part 2 — the ban pipeline

Three separately-scheduled scripts carry an offender from a log line, through the
firewall, and back into the nginx `$is_banned` geo.

### Stage 1 — temporary ban (`guest-fire.sh`)

The fast path: a 15-minute temporary CSF ban for every fresh offender in `web.log`. For the
web tier it reads `/var/xdrago/monitor/log/web.log`, takes the IP field
(`cut -d '#' -f1 | sort | uniq`), and for each unique IP:

1. Looks the IP up in CSF (`csf -g`) and checks `csf.allow` for an explicit
   `tcp|in|d=80|s=<ip>` allow entry.
2. **If allowed** (in `csf.allow`, or showing an `ALLOW … ACCEPT … dpt:80` rule), it is
   *cleared* — `csf -dr` and `csf -tr` remove any stray block — and never banned. The allow
   list always wins.
3. **If already denied** on 80 or 443, nothing is done.
4. **Otherwise** it issues a 15-minute temporary ban on both web ports:

   ```bash
   csf -td ${_IP} 900 -p 80
   csf -td ${_IP} 900 -p 443
   ```

The same routine runs over three log files with identical allow-first / already-denied /
temp-ban logic: the web block above (`web.log`, ports 80/443) plus an SSH twin (`ssh.log`,
port 22) and an FTP twin (`ftp.log`, port 21).

The guard runs **five times per invocation** with a 10 s pause between passes, so an IP that
appears mid-run is still caught within the same tick:

```bash
for _iteration in {1..5}; do
  [ ! -e "/run/water.pid" ] && _guest_guard
  sleep 10
done
```

The `[ ! -e "/run/water.pid" ]` test is the interlock with Stage 2: while `guest-water.sh`
runs (it `touch`es `/run/water.pid` on start and removes it on exit), `guest-fire.sh`
**skips its guard passes**, so the two never fight over CSF at the same time.

> **Under the hood — self-healing watchdog.** Under a real flood `web.log` can hold
> thousands of IPs and a single run can stretch from its normal ~50 s (5 × 10 s) into
> minutes, blocking the following cron slots. A watchdog records the PID in `/run/fire.pid`,
> and on the next invocation kills any predecessor still alive past `_FIRE_TIMEOUT`
> (**180 s**), logging to `/var/log/boa/fire_stuck.log`. A normal overlap (within the
> timeout) is left to the single-instance lock, which exits early if more than two copies
> run.

### Stage 2 — persistent escalation (`guest-water.sh`)

`guest-fire.sh` only ever applies *temporary* bans. Repeat offenders are escalated to a
**persistent** CSF deny by `guest-water.sh`, which runs on its own slower schedule and works
from the cumulative archive `/var/xdrago/monitor/log/scan_nginx.archive.log`. For each
unique IP it counts how many times that IP appears across the whole archive:

```bash
_NR_TEST=$(tr -s ' ' '\n' < ${_WA} | grep -cF "${_IP}")
```

After the `csf.allow` / `/root/.local.IP.list` exemptions, that count drives a two-tier
escalation:

| Archive hits | Action | CSF comment |
|---|---|---|
| `≥ 12` | `csf -d` persistent deny | `Brute force Web Server N attacks` |
| `≥ 24` | `csf -d` persistent deny, **do not delete** | `do not delete Brute force Web Server N attacks` |

The 12-hit deny lasts until the next CSF limits rotation (routine `csf.deny` trimming
reclaims it). The 24-hit deny carries the literal `do not delete` tag, which CSF's routine
trimming respects — so a heavy repeat offender stays banned across the housekeeping that
would otherwise expire it. The one thing that clears it is the operator-triggered full
cleanup: when `/etc/boa/.full.csf.cleanup.cnf` exists, `guest-water.sh` strips every
`do not delete` line from `csf.deny` (`sed -i "s/.*do not delete.*//g"`).

The same escalation runs over three archives:

| Tier | Archive var | Archive file | CSF label |
|---|---|---|---|
| Web | `_WA` | `scan_nginx.archive.log` | `Brute force Web Server` |
| SSH | `_HA` | `hackcheck.archive.log` | `Brute force SSH Server` |
| FTP | `_FA` | `hackftp.archive.log` | `Brute force FTP Server` |

For the whole run `guest-water.sh` holds the Stage 1 interlock — it `touch`es
`/run/water.pid` early (after its initial `/root/.local.IP.list` unblock pass, **not**
first) and `rm`s it at the very end — and once escalation is done it clears the per-tick
`web.log` / `ssh.log` / `ftp.log` so the next `scan_nginx` window starts clean.

> **Under the hood.** `guest-water.sh` also refreshes the `csf.allow` provider ranges
> (Cloudflare, Googlebot, Bingbot, Pingdom, and — behind
> `/root/.extended.firewall.exceptions.cnf` — Imperva, Sucuri, Auth0, Site24x7), with a
> diff-guard that reverts an unexpected `csf.allow` change and per-provider backups under
> `/var/backups/csf/water/`. That allow-list maintenance is what makes the keystone
> `_is_whitelisted_ip` guard reliable across the whole pipeline.

### Stage 3 — geo regeneration (`nginx_deny.sh`)

A CSF deny stops traffic at the origin firewall — but on a **Cloudflare-proxied** vhost the
origin only ever sees the Cloudflare edge IP, so a CSF/iptables ban on the *real* client
never bites. `nginx_deny.sh` closes that gap: it mirrors the web bans into an nginx
realip-keyed geo deny set, so the banned real client is dropped with a `444` at nginx even
when it arrives via Cloudflare.

It rebuilds `/data/conf/nginx_banned_ips.conf` from current CSF state on every run,
collecting **web bans only** from two sources:

```bash
# Active web temp bans: csf.tempban rows whose port field is 80 or 443
awk -F'|' '($3 == "80" || $3 == "443") { print $2 }' /var/lib/csf/csf.tempban
# Persistent web offenders: csf.deny lines tagged by guest-water
grep -F "Brute force Web Server" /etc/csf/csf.deny | awk '{ print $1 }'
```

This is deliberately **web-scoped**: it picks up the 80/443 temp bans from Stage 1 and the
`Brute force Web Server` denies from Stage 2, and **excludes** the SSH/FTP `csf.deny`
entries and the broad CIDR blocklists — those work at the network layer (they are not
Cloudflare-proxied) and have no place in the nginx geo.

Each collected token is validated as a bare IPv4 address or an IPv4 CIDR (every octet
`0-255`, prefix `0-32`):

```bash
_ipv4_octet="(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])"
[[ "$1" =~ ^(${_ipv4_octet}\.){3}${_ipv4_octet}(/(3[0-2]|[12]?[0-9]))?$ ]]
```

A loose pattern would let a malformed token (`999.1.1.1`, `/99`, IPv6, junk) reach the geo
map and fail the nginx configtest **for the whole box**. Only IPv4/CIDR tokens become
`IP 1;` lines.

The rebuild only disturbs nginx when something actually changed:

- **Change-gate.** The freshly-built file is compared to the live one with `cmp -s`; if
  identical, the run exits with no reload.
- **Atomic install + validate.** The new file is written to a leading-dot temp in the same
  directory (so the `.c*` include glob never sees it) and `mv`-d into place; the current
  file is backed up to `.nginx_banned_ips.last_good.conf` first.
- **Revert on failure.** After install it runs `service nginx configtest` and
  `service nginx reload`; on any failure it restores the last-good file (and reloads), so a
  bad ban set can never take nginx down.
- **Shared lock.** The whole run holds the advisory lock `/run/boa_nginx_config.lock`
  (`flock -w 30`), shared with the other BOA nginx-config writers (`ip_access`,
  `cloudflare_realip`, `ai_policy`, `migration_proxy_realip`) so their configtest+reload
  cycles never overlap. If the lock can't be taken within 30 s the run skips and retries next
  tick.

### Why the geo self-expires

The geo file holds no state of its own. Each `nginx_deny.sh` run rebuilds it **from
scratch** out of the current CSF tables, so the lifecycle is entirely CSF's:

- A Stage 1 temp ban lives in `csf.tempban` for 15 minutes. While it is there it appears in
  the geo; once CSF drops the expired row, the next pass simply doesn't emit it and the geo
  reload removes the `444`.
- A Stage 2 persistent deny stays in the geo until CSF removes the `csf.deny` line — at
  limits rotation for a `≥12` ban, or never (until manual action) for a `do not delete`
  `≥24` ban.

So bans self-expire without any manual cleanup: you manage CSF, and the nginx geo follows.

## Part 3 — the real-time request guards

The guards are a wall of `map`/`geo` directives that classify **every incoming request** —
by client IP, URI shape, User-Agent, Referer, query string — and drop or downgrade hostile
ones before they reach PHP-FPM. They live in two template files:

- **`server.tpl.php`** — the `map`/`geo` *definitions* in the shared `http {}` block,
  rendered once per box. Each map turns a request attribute into a flag.
- **`Inc/vhost_include.tpl.php`** — the `if (…) { return … }` *enforcement* rules in each
  `server {}` block. These read the map variables and act.

Maps are evaluated lazily and the `if` checks are cheap string tests, so this layer runs
before any `try_files`, `@drupal` fallback, or FastCGI round-trip.

### The 444-vs-404 convention

- **`return 444`** — nginx's "close the connection, send no response". Used for **abuse
  denials**: a banned IP, a malformed asset-chain flood, a no-referer print/search probe, a
  forged/training AI crawler, a scanner pattern, a TLS handshake on the plain port. It gives
  the attacker no signal (no status line, body, or timing leak) and is the cheapest
  refusal. It also feeds `scan_nginx`'s per-IP `444`-weight, so a 444'd request both costs
  the attacker a connection and accrues score toward a ban.
- **`return 404`** — a normal, cacheable "not found", reserved for cheap content-shape
  misses where a recoverable error keeps the false-positive blast radius small: the
  node-chain / lang-chain / content-chain URL-mutation floods, and special `.php`-probe
  URLs. A 404 still avoids a PHP bootstrap, so it is nearly as cheap as 444 but safer when
  the pattern *could* rarely match real content.

> **A note on `return 403`.** `vhost_include.tpl.php` also emits `return 403` in several
> places, but these are **not** abuse denials. Each is an `if ($cache_uid = '')`
> unauthenticated-session gate on a Hostmaster `/admin*` or `/hosting/c/server_*` location:
> an anonymous request to an admin URL gets `403`, while a *bot* in the same block gets
> `444`. In short: **403 is reserved for admin/Hostmaster session gates; abuse denials use
> 444.**

### Keying on the real client (realip)

Every guard that tests the client IP — and `scan_nginx` itself — keys on the **true client
address**, not on a spoofable `X-Forwarded-For`. On Cloudflare-fronted vhosts BOA plumbs the
realip module in the shared `http {}` block:

```nginx
real_ip_header    CF-Connecting-IP;
real_ip_recursive on;
include /data/conf/nginx_cloudflare_real_ip.c*;
```

The trusted CF source ranges are supplied by the BOA-managed wildcard include (written and
refreshed by `cloudflare_realip.sh`), so a missing file never breaks `nginx -t`; with no
trusted ranges the `CF-Connecting-IP` header is ignored and `$remote_addr` is left unchanged
(no spoofing risk). After realip runs, `$remote_addr` is the **real visitor** — what the
`$is_banned` geo and `scan_nginx`'s IP-counting both score.

One subtlety on the FastCGI side: BOA pins `fastcgi_param REMOTE_ADDR $realip_remote_addr;`,
so the PHP global sees the **original TCP peer** (the CF edge), while nginx's own
`$remote_addr` stays realip-rewritten to the real client for rate-limit keys, logs and the
deny geo. This keeps Provision's own PHP-side real-client resolution correct and the
nginx-side guards correct at the same time.

### `$is_banned` — the closing link of the pipeline

```nginx
geo $remote_addr $is_banned {
  default 0;
  include /data/conf/nginx_banned_ips.c*;
}
```

enforced near the top of every vhost:

```nginx
if ($is_banned) {
  return 444;
}
```

`nginx_deny.sh` regenerates `/data/conf/nginx_banned_ips.conf` from current CSF state, the
wildcard `.c*` include picks it up on the next reload, and the **next** request from a
banned client is 444'd at zero backend cost. Two safety properties matter: with no entries
`$is_banned` stays `0` (a fresh box or cleared list never errors), and the `.c*` glob is
leading-dot-safe (the in-flight temp and the last-good backup are dot-prefixed, so the
include never picks up a half-written file). Because the deny keys on the realip'd address,
it bites a Cloudflare-proxied attacker at the origin's nginx — where an origin CSF/iptables
ban on a CF-fronted IP would only see the CF edge and miss.

### Chain-mutation flood maps

A distributed botnet that exploits broken relative-URL resolution appends Drupal asset
references onto deep content URLs, producing self-mutating chains. BOA classifies the family
with purpose-built maps, split by whether the mutated URL ends in a static asset (444) or a
content segment (404).

- **`$is_static_chain` → 444.** Matches a Drupal asset-dir marker (`sites/all/modules`,
  `ui/external`, …) **buried under** a content path, or a canonical Drupal core asset file
  (`system.base.css`, `drupal.js`, …) buried the same way, or the same asset-dir token
  repeated. Legitimate Drupal asset URLs are root-anchored, so a buried-under-content match
  can only be the flood. Validated against 44k real flood requests with zero false positives
  on root-anchored assets, aggregated files, image styles and `/system/files` private files.
  The 444 fires *before* the asset router would route the absent file to
  `@drupal → /index.php → php-fpm`.
- **`$is_content_chain` → 404.** The content-path twin: the same mutation but the URL ends
  in a content segment, so without a guard it would render a full themed page (200). Matches
  only when **both** signals hold — a Drupal code-dir marker appears as a path segment
  **and** some path segment repeats 3+ times. Deliberately conservative (it covers the clear
  majority, not the 2×-repeat tail) and uses a cheap `404`. The complete cure is a
  source-side `<base href>`/theme fix that stops the site emitting
  root-relative-without-leading-slash links.

Both chain guards apply on **full-domain vhosts only**. They are intentionally **not** in
`subdir.tpl.php`: a subdir site legitimately serves `/<subdir>/sites/all/...` assets, which
`$is_static_chain` would match as buried-under-content. The node-chain / lang-chain guards
(which match on `node/<id>` repetition and language-prefix runs, not asset paths) **do**
apply on subdir vhosts.

### Print no-referer gate → 444

A printer-friendly or email-this-page request is always a *click from* a page, so it carries
a `Referer`; a Referer-less hit to a `/print*` path is the botnet (100% of the observed flood
had no Referer). The gate composes `$is_print_path` (a `/print…` URI shape, anchored on a
numeric node id or an export-format segment) with `$has_no_referrer`:

```nginx
map $is_print_path$has_no_referrer $block_print_no_referer {
  default 0;
  "11"  1;
}
```

enforced as `if ($block_print_no_referer) { return 444; }`. It is **referrer- and
path-shape only** — no module or version detection — so it is FP-safe and version-agnostic:
it covers D7 print / print_mail / print_pdf / printer_and_pdf, D10+ entity_print +
printable, and Backdrop, while content slugs (`/printing-services`, `/print/about-us`,
`/printable-maps`) never match.

### TLS-on-plain → 444

```nginx
map $request $tls_on_plain {
  default '';
  ~*^\x16\x03 tls_on_plain;
}
```

matches a TLS ClientHello frame (record type `0x16`, version `0x03…`) arriving on the plain
HTTP port, enforced as `if ($tls_on_plain) { return 444; }`. It silently drops a TLS
handshake mistakenly or maliciously sent to port 80 rather than returning an error that
would feed scanner automation. Shipped in BOA-5.9.3.

### Bot, crawler and botnet maps

Several UA-keyed maps hard-block known-bad agents:

| Map | Variable | Enforcement |
|---|---|---|
| `$is_crawler` | scraper/SEO/abusive bots (Ahrefs, MJ12, Semrush, PetalBot, Sogou…) | `if ($is_crawler) return 444` |
| `$is_botnet` | semalt/kambasoft referrer-spam family | `if ($is_botnet) return 444` |
| `$is_bot` | generic crawler tokens | `return 444` inside the `/search` and `/user/login` blocks |

**AI-vendor traffic is classified separately** by the `$is_ai_*` maps and the per-class AI
policy — those tokens are deliberately kept out of `$is_crawler` so they don't bypass that
policy. See [AI-POLICY.md](AI-POLICY.md).

A separate `$deny_on_high_load` UA map (crawl/spider/google/yahoo/yandex/baidu/bing) is the
load-shedding variant: it denies almost all crawlers only while the box is under high load.

#### Stale-Chrome botnet detection

Chrome auto-updates aggressively, so a genuine consumer install more than ~12 months stale is
extremely rare. Search-amplification bots fake a "moderately outdated but not obviously fake"
Chrome UA to dodge `$is_bot` while still being detectably stale:

```nginx
map $http_user_agent $is_stale_chrome {
  default 0;
  ~*Chrome/1([0-2][0-9]|3[01])\.  1;   # Chrome/100–131: > 12 months stale
}
```

`$block_stale_chrome_search` combines a stale Chrome UA with fulltext/facet search params and
fires **only in search location blocks**. The standalone `$is_catalina_stale_chrome` adds
macOS Catalina (10.15.7, EOL Nov 2022) + Chrome ≤ 131 — the exact combination of every
confirmed Solr search-amplification bot observed May 2026 — and is applied directly in the
`/search` blocks, so it needs no `$has_fulltext_search` dependency. Both shipped in BOA-5.9.3.

> **Maintenance caveat (carry verbatim).** These dated regexes are self-flagging. The
> in-source note instructs: when Chrome/132 exceeds 12 months (≈ **Feb 2027**), **widen the
> upper bound to `3[0-2]`** and update the comment. The ceiling must move forward as Chrome
> versions age, or the maps will eventually match current browsers (false positives) rather
> than stale ones.

### Scanner-pattern maps: `$is_denied` / `$ua_denied`

Two maps scan the request for attack payloads and 444 it. `$is_denied` (keyed on `$args`) is
**value-scoped** — each pattern is anchored to a single query-string parameter value
(`(?:^|&)[^=&]+=…`) to avoid base64/aggregate false positives — and covers:

- **SQLi**: `union…select`, `select…from/where`, `insert…into`, `delete…from` (with
  whitespace / `%20` / `%2B` / `/**/` variants);
- **blind/timing**: `waitfor delay`, `declare @`, `benchmark/sleep/pg_sleep(`;
- **hex-literal** (`0x…` after `=`/`char`/`cast`/`convert`) and **comment-obfuscated** SQLi;
- **XSS**: `<script`, `%3Cscript`, `javascript:`, `vbscript:`, `data:text/html`, `onload=`,
  `document.cookie` (raw and percent-encoded);
- **PHP-source probes** (`.php?…src/source/highlight`);
- **shell injection** (`system(`);
- **path traversal** raw and single/double percent-encoded (`../`, `%2e%2e/`, `%252e%252e/`).

`$ua_denied` (keyed on `$http_user_agent`) catches the same WAITFOR/declare/benchmark
injection payloads when smuggled inside the User-Agent header. Both shipped/expanded in
BOA-5.9.3.

### Search-amplification family

Solr / Search-API full-text search is expensive, so a botnet that hammers it (even one
request per IP) can amplify load far beyond its request rate. BOA defends the `/search` and
`/user/login` blocks with a layered map family, all keyed off `$has_fulltext_search` (matches
`search_api_views_fulltext`, `search_api_fulltext`, `im_taxonomy_vid` in the query string):

| Tier | Composed map | Signal |
|---|---|---|
| Tier 1 | `$block_search_no_referrer` | fulltext params **and** no Referer |
| Tier 2 | `$has_excessive_facets` | 6+ facets (`f[5]+`), encoded or literal |
| Tier 2 | `$block_search_root_referer` | fulltext **and** bare-root Referer **and** a facet present |
| login | `$block_login_search_destination` | search payload in `/user/login?destination=` **and** no Referer |

These apply as `return 444` inside the `/search` block, the language-prefixed `/xx/search`
block, and the `/user/login` block, alongside `limit_req` search-rate zones.
`$block_login_search_destination` closes a bypass where bots send
`/user/login?destination=search%2F...` so the path is `/user/login` and the `/search` guards
never run. The family landed in BOA-5.9.3.

> **5.9.5 facet-required refinement.** Tier 2's `$block_search_root_referer` originally fired
> on `fulltext + bare-root Referer` alone — which falsely blocked a homepage plain-search
> submission (a real user submitting the search form from the front page sends a bare-root
> Referer with no facets). The fix adds `$has_any_facet` as a required third signal, so the
> block now needs `fulltext + root Referer + at least one facet param`. The plain homepage
> submission has no facet and is no longer a false positive.

### Distributed-i18n-flood inline guardrail (Tier A)

The search-amplification family protects `/search`; the same economics apply to any
expensive **localized** page when a site runs on-the-fly translation. Translation holds a
PHP-FPM worker for tens of seconds and FPM pools are shared per account, so a distributed
scraper of localized pages can starve every site on the pool. A rate limit is the wrong
tool (the source is thousands of IPs at one or two requests each); the right tool bounds the
**concurrency** of the expensive class.

`limit_conn boa_i18n_anon` caps the **in-flight** count of *anonymous localized* requests
**per vhost**, keyed on a constant (`$host`) rather than the client IP — so it bounds the
aggregate blast radius of a distributed flood instead of chasing rotating addresses. Excess
returns `444` instantly, before php-fpm. The key is non-empty only when three maps agree:

```nginx
# server.tpl.php (http{})
limit_conn_zone $boa_i18n_anon_key zone=boa_i18n_anon:10m;
map $host        $boa_i18n_guard { default 1; include /data/conf/boa_i18n_guard.map*; }  # on by default; map file lists hosts to set 0 (opt-out)
map $request_uri $boa_i18n_path  { default 0; ~*^/[a-z][a-z](-[a-z]+)?/ 1; ~*[?&]q=/?[a-z][a-z](-[a-z]+)?/ 1; }
map $cache_uid   $boa_is_anon    { default 0; "" 1; }
map "$boa_i18n_guard$boa_i18n_path$boa_is_anon" $boa_i18n_anon_key { default ""; "111" $host; }
```

```nginx
# Inc/vhost_include.tpl.php — location = /index.php (the single dynamic chokepoint)
limit_conn boa_i18n_anon <nginx_i18n_anon_conn|24>;
limit_conn_status 444;
```

- **On by default, per-host opt-out.** `$boa_i18n_guard` is `1` for every vhost; the
  wildcard-included `/data/conf/boa_i18n_guard.map` lists hosts to set to `0` to opt them
  out (an absent/empty file leaves every host guarded). Defaulting on is safe because a
  leading two-letter path prefix is Drupal's URL language-negotiation convention, never a
  content subdirectory — the same assumption the `/[a-z][a-z]/search` and
  `/[a-z][a-z]/civicrm` locations already rely on fleet-wide. The opt-out exists for the
  rare exception: a non-Drupal app, or a single-language site that uses a two-letter path
  for a region with URL language-negotiation off. The map is the same two-stage idiom as
  `$is_banned` (global map always defined so `nginx -t` never sees an undefined variable;
  per-host state from an included data file). See Part 5 for opting a host out.
- **Keyed on `$request_uri`, not `$uri`.** BOA rewrites clean URLs to `/index.php` before
  the map evaluates, so `$uri` would already read `/index.php`; `$request_uri` keeps the
  original `/de/product?page=1`. The second `?q=` pattern closes the D7
  `/index.php?q=<lang>/` form, and matches neither ordinary `q=node/`, `q=user/` nor
  `q=desktop`.
- **Anonymous only.** `$boa_is_anon` reuses the authoritative `$cache_uid` session map, so a
  logged-in editor (a `SESS`/`SSESS` cookie) is never capped.
- **Applied at `location = /index.php`** — the one location every dynamic request funnels
  through — so static files under `/xx/` (served by their own locations) are correctly
  excluded. `limit_conn_status 444` also aligns the co-located per-IP `limreq` cap to the
  444 convention.

Sizing: the default cap is **24** in-flight (~⅛ of a 192-worker pool), tunable via the
provision-side option `nginx_i18n_anon_conn`. Measured legitimate human localized
concurrency is well under 20 while a saturating flood needs hundreds, so 24 cleanly
separates the two while bounding the expensive class to a small slice of the pool. The
Tier-B detector (Part 1) watches the `444`s this guardrail sheds as its earliest signal.

### Edge-policy guards (defined here, documented elsewhere)

Three further request-path defences are defined in the same template pair but belong to BOA's
edge-policy layer:

- **AI-class policy maps** — `$is_ai_training`, `$is_ai_search`, `$is_ai_evasive`,
  `$is_ai_forged`. Training and evasive AI fetchers are blocked by default (444) with a
  per-site opt-in; forged AI UAs (robots.txt-only tokens a real client never sends) are
  universally 444'd. Full mechanism in [AI-POLICY.md](AI-POLICY.md).
- **Secret-path deny** — `map $uri $is_secret_path` 444's probes for `.env` / `.git` /
  `.aws` / `.ssh`, `secrets.json`, `config.json`, `application.yml`, `settings.py` and
  similar, on **any** UA.
- **Cloudflare realip ranges** — the trusted-range include refreshed by
  `cloudflare_realip.sh` (see "Keying on the real client"). Per-site IP access control is in
  [IP-ACCESS.md](IP-ACCESS.md).

### Where each guard fires (ordering)

Within a vhost the guards run roughly in this order — earliest = cheapest / most universal:

```
$is_node_chain          → 404
$is_lang_chain          → 404
$is_static_chain        → 444
$is_content_chain       → 404
$block_print_no_referer → 444
SA-CORE-2018-002 RCE    → 444
$is_banned              → 444   ← ban-pipeline closing guard
=PHP… version probe     → 404
$is_secret_path         → 444   edge-policy
$is_ai_forged           → 444   edge-policy
AI training / evasive   → 444   edge-policy
$is_crawler             → 444
$is_botnet              → 444
bad request method      → 444
$is_denied              → 444
$ua_denied              → 444
$tls_on_plain           → 444
… then per-location: /search, /xx/search, /user/login families,
  and at location = /index.php: limit_conn boa_i18n_anon → 444 (Tier-A i18n guardrail)
```

> **Under the hood.** Two related nginx tunables were adjusted alongside these maps. In the
> shared `http {}` block, `variables_hash_max_size 2048` was raised to accommodate the growing
> set of `map` variables. Separately, the per-location FastCGI microcache directive
> `fastcgi_cache_use_stale` no longer includes `http_503`, so a `503` is no longer served from
> stale cache.

## Part 4 — configuration reference

Every tuning knob lives in `scan_nginx.sh` as a built-in default; then
`/root/.barracuda.cnf` is sourced and **replaces** any value it sets (a plain assignment,
not a merge). A scalar override simply wins; a **list** override
(`_NGINX_DOS_IGNORE_PATHS`, `_NGINX_PATH_FLOOD_WATCH`) replaces the whole list (an empty
value disables that feature).

> **Where defaults come from.** `scan_nginx.sh` hard-codes a built-in default for each
> variable so the script is correct on an untouched box. Separately, `autoupboa` seeds a
> **subset** into `/root/.barracuda.cnf` (`_DEFAULT_NGINX_DOS_*`) so they appear as editable
> lines: `_NGINX_DOS_LINES`, `_NGINX_DOS_LIMIT`, `_NGINX_DOS_MODE`, `_NGINX_DOS_DIV_INC_NR`,
> `_NGINX_DOS_INC_MIN`, `_NGINX_DOS_LOG`, `_NGINX_DOS_IGNORE`, `_NGINX_DOS_STOP`.
> `autoupboa` also normalises `_NGINX_DOS_LIMIT` back to `399` on each pass. The DDoS,
> path-flood, ignore-paths, 444-weight and php-probe knobs are **not** seeded — they take the
> script's built-in defaults unless you add them to `/root/.barracuda.cnf` yourself. Where the
> seeded value differs from the script default, the seeded one wins (notably
> `_NGINX_DOS_LOG`).

### Window and per-IP scoring

| Variable | Default | What it controls |
|---|---|---|
| `_NGINX_DOS_LINES` | `1999` | Lines of `access.log` read on a baseline run (the scan window). |
| `_NGINX_DOS_LIMIT` | `399` | Per-IP score at which an IP is written to `web.log`. All weights below derive from it. `autoupboa` re-normalises it to `399` each pass. |
| `_NGINX_DOS_MODE` | `2` | Per-IP algorithm. Mode `1` adds extra `+5` increments for `POST` to `/user`, `/user/(register\|pass\|login)`, `/node/add` and `GET` to `/node/add` and `/search`; mode `2` (default) skips those. **Both modes** apply the `_NGINX_DOS_STOP` check. |
| `_NGINX_DOS_LOG` | `VERBOSE` *(script)* / `SILENT` *(seeded)* | Log verbosity: `SILENT`, `NORMAL`, or `VERBOSE`. The script's built-in fallback is `VERBOSE`, but `autoupboa` seeds `SILENT`, so a normally-managed box runs **SILENT** unless changed. |
| `_NGINX_DOS_DIV_INC_NR` | `40` | Divisor for the standard 4xx/5xx increment: `_INC_NR = _NGINX_DOS_LIMIT / 40` (≈ 10). |
| `_NGINX_DOS_INC_MIN` | `3` | Floor for the computed increments — `_INC_NR` and `_INC_S_NR` are never less than this. |

The `/user/login` increment uses `_INC_S_NR = _NGINX_DOS_LIMIT / 80` (≈ 5, floored at
`_NGINX_DOS_INC_MIN`). Its divisor `_NGINX_DOS_DIV_INC_S_NR` is derived as
`_NGINX_DOS_DIV_INC_NR × 2` and is not a separately tunable knob.

| Variable | Default | What it controls |
|---|---|---|
| `_NGINX_DOS_444_WEIGHT` | `_NGINX_DOS_LIMIT / 3` (≈ 133), **computed** | Extra weight per confirmed `444` on a watched attack path (on top of `_INC_NR`). Honoured as set if numeric in config; `0` disables. |
| `_NGINX_PHP_PROBE_WEIGHT` | `_NGINX_DOS_LIMIT / 3` (≈ 133), **computed** | Extra weight for a `.php` request **path** that `404`s on a Drupal docroot. Honoured as set if numeric; `0` disables. |
| `_NGINX_MIN_BLOCK_REQS` | `3` | Minimum raw (unweighted) requests an IP must make before it can be individually blocked. Set to `1` to disable the floor. |

The two `*_WEIGHT` knobs are **not** in the static default block — they are computed
*after* the config is sourced (`_NGINX_DOS_LIMIT / 3`), but only if the operator did not set
a numeric value. This preserves an explicit `=0` (disable) or custom value and avoids a stale
default when the config later lowers `_NGINX_DOS_LIMIT`.

#### `_NGINX_DOS_STOP` — SQLi / blind-timing regex

```
_NGINX_DOS_STOP="WAITFOR.DELAY|DECLARE.*@x|/\*\*/|%27.*%29.*%3B|0x[0-9a-f]{6}"
```

This is **not** a generic flood-rate knob and **not** a "+5 counter". It is a
regular-expression set of SQL-injection / blind-timing fingerprints. When a log line
matches, `_process_ip` adds the **full** `_NGINX_DOS_LIMIT` in a single hit, saturating the
score to the block threshold at once. A block still requires the IP to clear the
`_NGINX_MIN_BLOCK_REQS` floor (default 3), so a lone probe from an otherwise idle IP is caught
in aggregate, not instantly. The regex is matched unanchored against the whole log line. An
empty value disables injection-keyword scoring entirely.

### DDoS — shared-UA aggregate

| Variable | Default | What it controls |
|---|---|---|
| `_NGINX_DDOS_UA_IP_THRESHOLD` | `100` | Distinct IPs sharing one UA before that UA is treated as an attack fingerprint. A common mobile-browser UA on a busy site is shared by many IPs, so this must stay well above real peak. |
| `_NGINX_DDOS_UA_REQ_THRESHOLD` | `1000` | Total per-UA requests (across all IPs, ~5 s window) that flags a UA even when its IP count is low but volume is extreme. |
| `_NGINX_DDOS_IP_MIN_REQS` | `20` | When a UA is flagged, only block contributing IPs that made at least this many requests with it. A legitimate search session reaches several requests under one UA, so a low value here is what false-positives real visitors. |

### Path-flood — search-amplification aggregate

| Variable | Default | What it controls |
|---|---|---|
| `_NGINX_PATH_FLOOD_IP_THRESHOLD` | `30` | Distinct IPs on a watched prefix before a flood is **declared** (200 + 444). Declaration alone never bans. |
| `_NGINX_PATH_FLOOD_REQ_THRESHOLD` | `100` | Total requests (200 + 444, ~5 s window) to the prefix before a flood is declared. |
| `_NGINX_PATH_FLOOD_SLOW_SECS` | `3` | Upstream seconds above which a 200 counts as "slow" and earns an extra per-IP increment. |
| `_NGINX_PATH_FLOOD_IP_MIN_REQS` | `20` | Per-(prefix, IP) **200**-response count before that IP is listed during a flood — the real per-IP protector for shared-egress visitors. Kept modest (a single heavy search scraper is caught here, since a 200 scores only +1 in the per-IP scorer under the default mode 2). Set to `1` to list every 200-sending participant. |
| `_NGINX_PATH_FLOOD_WATCH` | see below | Pipe-separated patterns matched against the full log line (path **and** query string) that mark a prefix as expensive/watched. |

```
_NGINX_PATH_FLOOD_WATCH="apachesolr_search|search_api_views_fulltext|search_api_fulltext|im_taxonomy_vid|/search/node|/search/user"
```

The defaults cover legacy Apache Solr search paths, Search API Views and programmatic
fulltext parameters, the faceted-search taxonomy facet parameter, and Drupal core
node/user search. Add site-specific expensive endpoint substrings per box; the override
replaces the list.

### Exemptions

These two knobs exempt at **different scopes**:

- `_NGINX_DOS_IGNORE_PATHS` is tested at loop scope **before any detector runs**, so it
  exempts the line from **all three** detectors.
- `_NGINX_DOS_IGNORE` is tested **inside** `_process_ip` and only suppresses the **per-IP**
  counter for that line — the shared-UA and path-flood aggregates still see it.

| Variable | Default | What it controls |
|---|---|---|
| `_NGINX_DOS_IGNORE` | `doccomment` | Keyword(s) that, when found on a `200`/`302` line, exempt it from per-IP scoring (a regex fragment matched against the line). |
| `_NGINX_DOS_IGNORE_PATHS` | see below | Space-separated URI prefixes exempt from **all** IDS scoring. |

```
_NGINX_DOS_IGNORE_PATHS="/shopify/webhook /quickbooks/webhook /stripe/webhook /paypal/webhook /github/webhook /gitlab/webhook /graphql /public-api /oauth2"
```

`_NGINX_DOS_IGNORE_PATHS` rules: paths are space-separated, each a leading-slash absolute
path with **no trailing slash**; each matches that exact path or any sub-path under it; the
match is against the **real `$request` URI** only (query stripped, `..`/`%`-escape refused);
the override **replaces** the default list (an empty value disables the feature). See the
exemption-gate detail in Part 1.

### Distributed-i18n-flood and FPM saturation

These govern the localized-flood detector and the FPM saturation trigger (Part 1). All take
the script's built-in default unless added to `/root/.barracuda.cnf`; none is seeded by
`autoupboa`.

| Variable | Default | What it controls |
|---|---|---|
| `_NGINX_I18N_FLOOD_DETECT` | `YES` | Master switch for the per-vhost localized-flood detector. `NO` skips the per-line tally entirely (zero hot-loop cost). |
| `_NGINX_I18N_FLOOD_WINDOW` | `120` | Sliding-window length in seconds; spans runs (each tick adds one bucket, expired buckets pruned). |
| `_NGINX_I18N_FLOOD_MIN_REQS` | `400` | Windowed localized requests to one vhost before the volume+stress path can trip. Above a busy multilingual site's organic localized traffic. |
| `_NGINX_I18N_FLOOD_STRESS_PCT` | `15` | Minimum share (%) of windowed localized requests that are slow / `5xx` / `444` for the volume+stress trip. Benign localized peaks run near 0 %. |
| `_NGINX_I18N_FLOOD_SLOW_SECS` | `3` | Whole seconds above which a localized request counts as "slow" for the stress gate. |
| `_NGINX_I18N_FLOOD_C444_THRESHOLD` | `40` | Windowed count of localized `444`s to one vhost (the Tier-A guardrail shedding) that trips on its own — the early, symmetric signal. Set well above incidental localized `444`s. |
| `_NGINX_I18N_FLOOD_COOLDOWN` | `300` | Per-vhost seconds between alerts/snapshots, so a long burst yields a handful of records. |
| `_NGINX_FPM_SAT_DETECT` | `YES` | Master switch for the FPM `max_children` tail. |
| `_NGINX_FPM_ERR_GLOB` | `/var/log/php/php*-fpm-error.log` | Glob of the per-version PHP-FPM error logs to tail. |
| `_NGINX_FPM_SAT_PATTERN` | `reached max_children setting` | The literal the FPM master logs on a per-pool ceiling hit. |

The **inline** guardrail's cap is a separate, provision-side option `nginx_i18n_anon_conn`
(default `24`), rendered into the vhost `limit_conn` directive — not a `scan_nginx` knob. The
guardrail is **on by default**; the per-host **opt-out** is the
`/data/conf/boa_i18n_guard.map` data file (Part 5), not a `.barracuda.cnf` variable.

### HTTP/1.0 registration-spam (auth paths)

Govern Detector 4 (Part 1). All take the built-in default unless added to
`/root/.barracuda.cnf`; none is seeded by `autoupboa`.

| Variable | Default | What it controls |
|---|---|---|
| `_NGINX_HTTP10_AUTH_DETECT` | `YES` | Master switch. `NO` skips the per-line tally entirely (zero hot-loop cost) — opt out on a box fronted by a non-BOA / HTTP/1.0-downgrading proxy. |
| `_NGINX_HTTP10_AUTH_PATHS` | `^/([a-z]{2}/)?user/(register\|password)(/\|$)` | ERE matched against the parsed request URI (optional language prefix). A malformed override fails closed and reverts to this default. |
| `_NGINX_HTTP10_AUTH_WINDOW` | `600` | Sliding-window length in seconds; spans runs (the bot is too slow for one ~5 s window). |
| `_NGINX_HTTP10_AUTH_IP_THRESHOLD` | `3` | Windowed HTTP/1.0 auth-path hits from one IP before it is banned. |
| `_NGINX_HTTP10_AUTH_CIDR_THRESHOLD` | `6` | Windowed hits aggregated over an IP's `/24` before every **observed** contributor is banned (CIDR escalation for the slow distributed block). |

## Part 5 — operations and tuning

### Reading live state

Everything the Abuse Guard does is reflected in plain-text files, safe to `cat`/`grep`.

| What | Where | Notes |
|---|---|---|
| Scorer's block list (input to temp-ban) | `/var/xdrago/monitor/log/web.log` | `IP # [xSCORE] TIMESTAMP`; `guest-fire` consumes it into CSF, then `guest-water` purges it (`rm -f`) |
| Persistent archive (input to escalator) | `/var/xdrago/monitor/log/scan_nginx.archive.log` | every block ever written; repeat-offender source |
| Incremental read position | `/var/log/scan_nginx_lastpos` | byte offset into `access.log`; reset on rotate/truncate |
| Live geo (derived mirror of CSF) | `/data/conf/nginx_banned_ips.conf` | regenerated each pass by `nginx_deny.sh`; **do not hand-edit** |
| Active temp bans | `csf -t` (reads `/var/lib/csf/csf.tempban`) | WEB bans are on ports 80/443 |
| Persistent denies | `csf -g <ip>` / `/etc/csf/csf.deny` | water's escalations tagged `Brute force Web Server` |
| i18n-flood + FPM alerts | `/var/xdrago/monitor/log/i18n_flood.log` | Tier-B detector trips and FPM `max_children` hits |
| i18n-flood snapshots | `/var/xdrago/monitor/log/i18n_flood/` | per-trip top talkers/UAs/lang-prefixes; the window state and FPM byte-offsets live here too |

```bash
# Who is currently temp-banned, and on which ports
csf -t

# Is a specific IP banned, and why (temp + permanent + allow)?
csf -g 203.0.113.7

# What did the scorer flag most recently?
tail -n 50 /var/xdrago/monitor/log/web.log

# Which IPs are repeat offenders (escalation candidates)?
cut -d'#' -f1 /var/xdrago/monitor/log/scan_nginx.archive.log | sort | uniq -c | sort -rn | head

# How many entries are in the live geo right now?
grep -c . /data/conf/nginx_banned_ips.conf
```

### Purging or cycling a ban

Because the geo is a mirror of CSF and is fully regenerated each pass, **you never edit the
geo to clear a ban — you change CSF and let it propagate.** Bans also self-expire: a temp
ban is `csf -td … 900` (15 minutes) and disappears on its own.

```bash
# Remove a single temporary ban now (does NOT touch csf.deny)
csf -tr 203.0.113.7

# Remove a permanent deny (water's "Brute force Web Server" escalation)
csf -dr 203.0.113.7

# Flush ALL temporary bans (last resort; the scorer will re-ban real abuse)
csf -tf
```

After any of these the geo still shows the old entry until the next scan tick regenerates
it. To force the geo back in sync immediately:

```bash
bash /var/xdrago/nginx_deny.sh
```

Truncating `archive.log` by hand only resets repeat-offender history — it does **not** lift
any existing ban (those live in CSF and the geo). For a clean slate, remove the CSF entries
first, then optionally truncate the logs.

### Recovering from false positives — `clearwebbans`

`clearwebbans` does the whole "clean slate" sequence above in one idempotent, web-scoped
step. Use it after loosening the limits (or any time the web IDS has false-positived real
visitors) to release **everyone** the WEB detectors caught, in the correct order, without
touching SSH/FTP bans:

1. removes the permanent `csf.deny` "Brute force Web Server" escalations (`csf -dr`);
2. removes the temporary web bans on ports 80/443 (`csf -tr`);
3. clears `web.log` and both `scan_nginx.archive*.log` (so `guest-fire` won't re-apply and
   `guest-water` won't re-escalate them);
4. resets `/var/log/scan_nginx_lastpos` to the **current** end of `access.log` so the next
   scan only sees new traffic instead of reprocessing the lines that caused the bans;
5. regenerates the nginx geo-ban set via `nginx_deny.sh` so `$is_banned` clears at once.

```bash
clearwebbans --dry-run   # report counts + a sample, change nothing
clearwebbans             # forced: do the full web-ban cleanup
```

Run it once the updated `scan_nginx.sh` limits are already deployed (serial `f62`+), so the
released IPs are not immediately re-banned under the old thresholds. SSH and FTP bans are
deliberately left in place — those are real brute-force. On a heavily-polluted box the temp
loop can take a while (one `csf -tr` per IP), same as `guest-fire`.

### Whitelisting

Three independent mechanisms, by what you are protecting:

**Whitelist an IP — use the CSF allow list.** `_is_whitelisted_ip` parses
`/etc/csf/csf.allow` once at startup into an exact-host map plus a CIDR index, and every call
path into a block checks it first. An allowed IP is never scored or banned, on every port
regardless of the entry's port scope.

```bash
# Permanently trust an IP (or CIDR) fleet-wide
csf -a 198.51.100.0/24 "office network"
```

This is the right tool for **a monitoring service**: add its published IP ranges to
`csf.allow` rather than exempting a path. A path exemption opens that URI for everyone; a CSF
allow exempts only the named source. A second, scorer-local layer is `/root/.local.IP.list`
(loaded into `_ALLOWED_IPS`, skipped before scoring) — a convenience for
local/infrastructure addresses; for anything that must also be trusted by the firewall
stages, use `csf.allow`.

**Whitelist a path — `_NGINX_DOS_IGNORE_PATHS`.** When the thing to protect is an endpoint
that authenticates per request (a webhook receiver, an API root), exempt the path rather than
chasing rotating IPs:

```bash
# Override REPLACES the default list — include the shipped defaults you still need
_NGINX_DOS_IGNORE_PATHS="/shopify/webhook /quickbooks/webhook /stripe/webhook \
/paypal/webhook /github/webhook /gitlab/webhook /graphql /public-api /oauth2 \
/my/custom/webhook"
```

### Opting a host out of the i18n guardrail

The Tier-A localized-concurrency cap is **on for every vhost by default** — no per-site
step is needed to protect a multilingual site. You only act to **exclude** a host, for the
rare case where a two-letter path prefix is not a Drupal language (a non-Drupal app behind
nginx, or a single-language site that uses e.g. `/us/` as a region path with URL
language-negotiation off):

```bash
# one line per hostname to EXCLUDE; quoted host, value 0
printf '"%s" 0;\n' static-app.example.com >> /data/conf/boa_i18n_guard.map
nginx -t && service nginx reload      # Devuan: service, not systemctl
```

An absent/empty map leaves every host guarded (the default). To tune the cap set
`nginx_i18n_anon_conn` (default `24`) and re-render the vhost; to widen it fleet-wide raise
that option, to effectively disable Tier A on a host opt it out as above. The Tier-B detector
logs every trip and snapshot under `/var/xdrago/monitor/log/i18n_flood*` (see **Reading live
state**), so a real burst leaves a forensic trail of the top talkers, UAs and
language-prefixes. Unlike a CSF ban this is not per-IP and never appears in `csf -t`/`csf -g`
— it is a concurrency ceiling on a request class, not a block on a source.

### Opting a box out of the HTTP/1.0 registration-spam ban

Detector 4 is **on by default** and needs no activation. Opt a box **out** only when its
affected vhost is fronted by a proxy that talks **HTTP/1.0 to origin** — a non-BOA proxy or
CDN, or a BOA front proxy / PX0 host not yet updated to the `proxy_http_version 1.1` confs —
because there every proxied request (real logins included) logs as HTTP/1.0 at origin and
would be banned:

```bash
# in /root/.barracuda.cnf
_NGINX_HTTP10_AUTH_DETECT=NO
```

Confirm before deciding: `grep 'user/register' /var/log/nginx/access.log` (or `user/password`)
should show real visitors with `HTTP/1.1` / `HTTP/2.0` in the request line (and
`proto="HTTP/1.1"` / `"HTTP/2.0"`) and only the bot as `HTTP/1.0`. If real clients **also**
show `HTTP/1.0`, the box is behind a downgrading proxy — fix that proxy to
`proxy_http_version 1.1` (BOA's own proxies already do) rather than leaving the detector off.
The windowed state lives at `/var/xdrago/monitor/log/http10_auth.window`; bans land in
`web.log` and the csf pipeline like any other detector, so `clearwebbans` (above) recovers a
false positive.

### Enabling debug output

The scorer's verbose logs are governed by `_NGINX_DOS_LOG` (`SILENT` | `NORMAL` |
`VERBOSE`). The script's built-in fallback is `VERBOSE`, but `autoupboa` seeds `SILENT` into
`/root/.barracuda.cnf`, so the **effective stock default is `SILENT`** — `_verbose_log`
writes nothing until you raise the level or set a debug marker. Two `/etc/boa/` markers
control the rest:

| Marker | Effect |
|---|---|
| `/etc/boa/.debug.monitor.cnf` | `set -x` shell trace + `declare -p` dumps of every scoring array on startup |
| `/etc/boa/.debug.monitor.log.cnf` | forces `_verbose_log` on regardless of `_NGINX_DOS_LOG` — the way to get the logs back on a box running `SILENT` |

The verbose log fans out by category: `/var/log/scan_nginx_debug.log` (general),
`/var/log/scan_nginx_flood_debug.log` (counter increments),
`/var/log/scan_nginx_admin_debug.log` and `/var/log/scan_nginx_other_debug.log`
(ignored-URI traces). The category split only appears at `VERBOSE`; at `NORMAL` (or at the
seeded `SILENT` with the `.debug.monitor.log.cnf` marker set) everything lands in the general
log.

To watch a real classification decision, set the marker and run the scorer by hand (it takes
no flags — it is normally launched by `nginx_guard.sh`, 10 short overlapping passes per
minute, gated by the single-instance lock):

```bash
touch /etc/boa/.debug.monitor.log.cnf
bash /var/xdrago/monitor/check/scan_nginx.sh
tail -f /var/log/scan_nginx_debug.log
# for the per-category split, set _NGINX_DOS_LOG=VERBOSE in /root/.barracuda.cnf
# and watch scan_nginx_flood_debug.log instead
rm -f /etc/boa/.debug.monitor.log.cnf   # remember to remove the marker afterwards
```

### Self-healing watchdogs

The worker scripts can hang under a genuine flood (a `web.log` with thousands of IPs makes a
single `guest-fire.sh` pass take minutes). Several independent layers keep the pipeline from
wedging, and they live in different scripts — **not** in scan_nginx:

1. **In-process fire watchdog (`guest-fire.sh`).** At the top of every run it reads
   `/run/fire.pid`; if the recorded PID is alive and the pidfile's mtime is older than
   `_FIRE_TIMEOUT` (**180 s**, 3× the normal ~50 s run), it `kill -9`s the stuck process,
   removes the pidfile, and logs to `/var/log/boa/fire_stuck.log`.
2. **External fire watchdog (`autoupboa`).** Run during the weekly self-upgrade as a
   pidfile-independent safety net. It enumerates `pgrep -f guest-fire.sh`, computes each
   PID's elapsed time from `/proc/PID/stat` field 22 versus `/proc/uptime`, and `kill -9`s
   any older than `_FIRE_WATCHDOG_TIMEOUT` (**180 s**), logging to the same
   `/var/log/boa/fire_stuck.log`.
3. **Scorer single-instance lock (`scan_nginx.sh`).** No fire-style timeout; it self-protects
   by refusing to pile up — it sources `/opt/local/{bin,lib}/lock.inc` and calls
   `_single_instance_lock` if present, else falls back to a legacy `pgrep` guard that exits
   when more than 2 instances run, logging to `/var/log/boa/too.many.log`.

Independently, `minute.sh`'s `_csf_flood_guard` kills runaway `guest-fire.sh` swarms (and CSF
storms) when no protected run is in progress (`/run/boa_run.pid` absent):

- more than **9** fire processes → `csf -tf` + `csf -df` + `pkill -9 -f fire.sh`, logged to
  `/var/log/boa/fire-purge.kill.log`;
- more than **7** → `csf -tf` + `pkill -9 -f fire.sh`, logged to
  `/var/log/boa/fire-count.kill.log`;
- more than **4** `csf` processes → `pkill -9 -f csf` + `csf -tf` + `csf -df`, logged to
  `/var/log/boa/csf-count.kill.log`.

If one of these logs is growing, the box is under sustained flood, not misconfigured — the
watchdog firing is the system working.

### Maintainer caveats (summary)

- **Detection is post-hoc — it cannot block mid-burst.** A burst that completes inside one
  tick is served before the IP is ever written to `web.log`; the scorer produces a ban for
  the *next* visit. The fast-ban weights shorten the *score* needed, not the cron latency. Do
  not "fix" the latency by shrinking the tick — you will just collide with the
  single-instance lock.
- **The realip dependency** scores the wrong IP if the trust chain is wrong — see Part 1.
- **The function-IFS gotcha** silently makes a space-split helper match nothing in-script
  while passing interactively — see Part 1.
