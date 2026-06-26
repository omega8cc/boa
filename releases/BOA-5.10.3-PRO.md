# Watchtower Edition

## New BOA-5.10.3 PRO/LTS Release Notes

BOA-5.10.3 PRO/LTS is a **hardening-and-fixes release** built around the **Nginx
Abuse Guard** and the **self-healing monitor stack**. It advances the web IDS
with several new detectors — an **HTTP/1.0 registration-spam auto-ban**, a
**webshell `*.php` fast-ban**, a **multi-tier distributed translation-flood
defence**, and **webhook/API exemptions** — while **retuning the over-aggressive
5.10.1 defaults** that were false-banning real visitors on busy sites, and ships
a one-shot **`clearwebbans`** release valve. Alongside it land new read-only
operator tools (**`loadreport`**, **`floodreport`**), an **idle monitor fan-out
throttle**, **load-auto-pause refinements**, and **PHP-FPM capacity allocation**
that stops upgrade-time throttling — plus a batch of **Drupal 8+ deploy and
clone/migrate reliability fixes** and the headline workflow win below.

In total, **65 commits across four repositories** went into this release:

| Repository | Branch | Commits |
|---|---|---|
| omega8cc/boa | 5.x-dev | 46 |
| omega8cc/provision | 5.x-dev | 15 |
| omega8cc/hosting_tasks_extra | 5.x-dev | 3 |
| omega8cc/hosting | 5.x-dev | 1 |

## Local Drush Lock / Unlock — A Reliable First-Class Workflow

The standout workflow improvement in this release is the **Local Drush
lock/unlock subsystem**, which underpins safe site-local `vdrush`/Composer use
on modern Drupal platforms.

- **"Lock Local Drush" is a fully working, visible platform task.** Its
  control-panel button is wired up alongside the existing permission,
  node-access and views integration, and the command is rebuilt as a **thin
  wrapper that delegates to the same canonical lock routine Platform Verify
  uses**, so it stays correct as that battle-tested path evolves.
- **It is the lighter alternative to a full Platform Verify** for re-locking a
  platform and restoring Drush 8 compatibility after site-local `vdrush` or
  Composer work — a targeted, fast operation rather than a full re-verify.
- **Lock and Unlock are now idempotent.** Re-running either on a platform
  already in the requested state is a clean no-op, with lock state derived from
  **on-disk reality** (the patch sentinels plus the actual `0400`/`0775`
  permission bits on `vendor/drush` and the Symfony console) rather than
  marker/PID files in the platform root.
- **Robust across Drupal versions.** Both commands bootstrap consistently
  (mirroring Platform Verify) and run cleanly whether a platform is currently
  locked or unlocked on Drupal 10/11; they fail closed if the Drupal major
  version cannot be resolved, and the console patches are verified with
  `patch --dry-run` before they are applied or reverted.

> **Companion fix:** the **"Rebuild registry"** and **"Flush all caches"**
> front-end tasks now work on Drupal 8+ as well — both rebuild the service
> container and flush caches via the site-local Drush on D10/11 (where Ægir
> Drush 8 cannot bootstrap), and both remain visible.

## Nginx Abuse Guard — New Detectors

This release adds four new detectors to the web IDS and closes the false-positive
trap that made one of them safe to ship on by default.

- **HTTP/1.0 registration-spam auto-ban (on by default).** A
  credential/registration-spam botnet POSTs to `/user/register` and
  `/user/password` over HTTP/1.0 while forging a modern-browser User-Agent,
  paced at ~1 slow request per IP across a small CIDR — traffic the per-IP,
  444-weight and shared-UA scorers all miss. A cross-run sliding window
  accumulates HTTP/1.0 auth-path hits per **real client IP** and bans once an
  IP's own count reaches **3** *or* its **/24 aggregate** reaches **6**. Only
  IPs actually seen sending HTTP/1.0 to an auth path are banned; the existing
  whitelist / logged-in / local-IP / already-banned guards all still apply, and
  the request-line parse is laundering-proof.
- **Webshell `*.php` probe fast-ban by content.** On a Drupal/Backdrop docroot
  any non-entry `*.php` that 404s is never a real page, so a 404 on such a path
  is weighted heavily (`_NGINX_PHP_PROBE_WEIGHT`, default `_NGINX_DOS_LIMIT/3` =
  133) and a shell scanner is banned after **~3 hits** instead of ~140. The
  match is path-anchored (status 404 **and** a `*.php` in the request path
  only — query/Referer/UA `.php` never match), so one stale `.php` link from a
  real visitor stays below the ban floor. Genuine entry points
  (`index`/`update`/`install`/`cron`/`xmlrpc`/`authorize`/`restore`/`rebuild`/…)
  are excluded.
- **Static- and content-path chain-flood guards.** A distributed botnet (one
  request per IP, realistic randomised Chrome UAs) floods D7-era sites with
  malformed concatenated asset URLs from broken relative-URL resolution. New
  `$is_static_chain` (444, before the asset router) and `$is_content_chain`
  (404, for the content-path twin) maps drop this traffic before a full themed
  bootstrap. `$is_content_chain` is deliberately conservative — it matches only
  when **both** a Drupal code-dir marker appears as a path segment **and** some
  segment repeats 3+ times.
- **Referer-less `/print*` flood block.** The same botnet hammers Drupal
  printer-friendly / email-this-page paths, each 404ing through a full themed
  bootstrap; a genuine print/email click always carries a Referer. BOA now
  returns 444 for a print-export request **only when the Referer is absent**,
  matching D7, D10+ (`entity_print`, `printable`) and Backdrop print families
  and anchored on a numeric node id or export-format segment so content slugs
  like `/printing-services` never match — independent of module state or core
  version.
- **BOA proxies now speak HTTP/1.1 to origin.** All five BOA proxy/migration
  confs (`proxy.conf`, `ssl_proxy.conf`, `pln_proxy.conf`, `https_proxy_le.conf`,
  `nginx_wild_ssl.conf`) had no `proxy_http_version`, so Nginx defaulted to
  HTTP/1.0 to the backend and every proxied request logged as HTTP/1.0 at
  origin. Each now sets `proxy_http_version 1.1` and clears the upstream
  `Connection` header, so a correctly-updated BOA front proxy / PX0 tier no
  longer downgrades real visitors — which is exactly what makes the HTTP/1.0
  auth-spam detector safe to ship on. Already-deployed proxies migrate via
  idempotent regeneration markers; the change is confined to the main
  `location /` block (adminer/sqladmin sub-locations and the HTTP/3 listener
  untouched).
- **Webhook/API IDS exemption list (`_NGINX_DOS_IGNORE_PATHS`).** Token/HMAC-
  authenticated endpoints can bypass all three aggregate scorers (per-IP,
  shared-UA, path-flood). The default ships the common provider webhook roots
  plus `/graphql`, `/public-api` and `/oauth2`. The match is laundering-proof:
  the real request URI is parsed from the `$request` field with the query
  stripped and `..`/percent-encoding refused, so a token smuggled into a
  User-Agent, Referer or query string can never launder an exemption.

## Distributed Translation-Flood Defence

A distributed scraper crawling localized (two-letter language-prefix) pages
forces each uncached page through Drupal's **synchronous on-the-fly
translation**, each request holding a PHP-FPM worker for tens of seconds. Spread
across thousands of IPs at one or two requests each, per-IP limits never trip and
the microcache never helps, so a shared per-account FPM pool saturates and takes
down every site on it. This release lands a layered defence:

- **Tier A — edge concurrency cap.** A per-vhost `limit_conn` (`boa_i18n_anon`)
  at the `location = /index.php` chokepoint, keyed on a **constant per vhost**
  (not the client IP), caps **in-flight anonymous localized requests** (default
  24, ~1/8 of a 192-worker pool) and sheds excess instantly with **444** before
  php-fpm. The key is non-empty only when the vhost is guarded **and** the path
  is localized **and** the session is anonymous, so English, static, and
  authenticated traffic is never counted.
- **Tier B — detector + FPM saturation trigger.** `scan_nginx` aggregates
  localized requests per vhost over a cross-run window and, on a flood, **alerts
  and writes a forensic snapshot** (top talkers, UAs, language prefixes) without
  banning per IP — futile against a distributed source, since Tier A caps in
  real time and any concentrated offender is still caught by the per-IP scorer.
  A companion trigger tails the per-version FPM error logs for the authoritative
  per-pool `reached max_children setting` saturation signal.
- **`floodreport`** (below) is the operator-facing way to read this detector's
  output.

The guardrail ships **on by default** for every Drupal/Backdrop vhost — see
**Operator Notes**.

## Calmer, Self-Throttling Monitoring

- **Idle fan-out throttle.** On small, slow and CI hosts the per-minute
  `second.sh`/`minute.sh` self-loops fanning out ~20 short-lived monitor scripts
  every 5s were the dominant idle-load source — holding load **3–4 on a
  2-CPU/4GB box with zero traffic**. A box classifier (CI/SLOW/NORMAL), reusing
  the queue runner's own signals, runs `minute.sh` at 9 passes/5s on NORMAL,
  3 passes/18s on SLOW, 1 pass on CI; `second.sh` keeps its responsive load
  sampling but runs the expensive watchdog fan-out only every Nth pass. **NORMAL
  production hosts are behaviourally unchanged.**
- **Load auto-pause refinements.** Resume now has **hysteresis** (web stays
  paused until load falls below `0.8 ×` the MAX threshold on **both** the 1- and
  5-minute averages) so a box hovering at the threshold no longer flaps; a
  backup's disk-bound (I/O-wait) load no longer triggers a web pause, gated on a
  **measured iowait** sample; the "verify twice" re-check now re-reads the
  current load instead of a stale value.
- **Incident-log hygiene.** Alert emails now mail **only the last 200 lines** of
  the incident log (one had grown to ~1.9MB of months-old history), and a new
  **weekly logrotate** bounds `/var/log/boa/*.incident.log` on disk.

## New Operator Tools

| Tool | Description |
|---|---|
| `loadreport` | Read-only, dependency-free `/proc` CPU+RSS profiler attributing recurring load to each BOA script (by command and by cron-launcher subtree) and printing the box's live monitor-throttle class. On demand, `--json`, or an idle-priority `--log` cron writing pruned JSONL; `--data` summarises history. |
| `floodreport` | Read-only summariser for the Tier-B translation-flood detector's output: per-vhost flood events, the pool-wide FPM saturation count, an event timeline, and a merged attack profile. `--days`/`--hours` windows, `--json`; writes nothing, no cron. |
| `clearwebbans` | Root-only, idempotent, web-scoped release valve that clears everyone the web IDS caught — the permanent "Brute force Web Server" `csf` denies and the temporary 80/443 bans, the scan archive logs that re-apply them, and the nginx realip geo-ban set. SSH/FTP bans left intact; supports `--dry-run`. |
| `fpmreport` (extended) | Now shows a per-pool **configured / observed** table (configured `pm.max_children` and `memory_limit` read from each pool's own conf, following `include=` for inherited values) plus the pool's plan and engine/core count, next to observed peak/p95/hit-rate. |

## PHP-FPM Capacity Allocation

- **Dedicated pools size dynamically.** Plans PHANTOM and above now size
  `pm.max_children` from box capacity — RAM as the primary axis (a configurable
  percentage of total RAM over a measured ~64 MB per-child footprint), capped by
  CPU cores × a factor, with an 8 floor — instead of a flat per-plan tier that
  **throttled busy dedicated tenants and returned 502 to siblings** after a
  routine upgrade. Shared plans (POWER and below) keep their restricted per-plan
  tier. Applied in both tenant-pool writers, so a re-run never lowers the result.
- **`memory_limit` follows the same split.** Dedicated plans keep the generous
  box-wide value; shared plans get a restricted per-plan band (POWER/BUS 768,
  EDGE/AGAIN/SSD/CLASSIC 512, MINI/MICRO/QUIET/HEADSPACE 256 MB), each capped at
  a RAM-scaled box ceiling. The box-wide memory floor is now RAM-scaled
  (`<2 GB` → 512/256, `2–4 GB` → 1024/512, `≥4 GB` → 1024/1024 as before),
  **fixing tiny VMs being pinned to a 1 GB per-pool limit that caused OOM**.
- **Optional pins:** `_PHP_FPM_RAM_PCT` (50), `_PHP_FPM_CPU_FACTOR` (8),
  `_PHP_FPM_MAX_CHILDREN_FORCE` and `_PHP_FPM_MEMORY_LIMIT_FORCE` — all default
  AUTO; no action required.

## Drupal 8+ Deploy & Update Reliability

- **D8+ container/cache rebuild after deploy.** After a clone, migrate,
  platform-migration, rename or restore, Drupal 8+ sites now have their service
  container and caches rebuilt — the D8+ analog of the registry rebuild older
  sites already received — run through the **site-local Drush** (`drush cr`) on
  D10/11, where Ægir Drush 8 cannot bootstrap and previously silently did
  nothing.
- **No more "No available releases found".** A clone/migrate/restore carried over
  the Update module's non-expirable `{key_value}` `update_fetch_task` tracker
  rows without the matching queue, wedging D8+ sites permanently with no UI
  recovery. The post-deploy hook now clears that collection on every D8+ deploy.
  Drupal 7 was never affected.
- **Degraded-platform safety.** On a D10/11 platform with no executable
  site-local Drush, a clone/migrate/restore now skips the DB update with a clear
  manual-recovery pointer (Unlock Local Drush, then `vdrush @alias updb`) instead
  of failing noisily through Ægir Drush 8.
- **Correct old-platform handling.** Cross-platform clone/migrate now actually
  unlocks and re-verifies the old platform's site-local Drush around the D10+ DB
  update; the old-platform alias had been read in the guard condition but passed
  as an unassigned (NULL) value to both invokes.

## Web IDS Retune & `clearwebbans`

The shared-UA DDoS and path-flood aggregate detectors fired on legitimate
traffic on high-traffic sites: each scan scores only the ~5s of log lines since
the previous run, so the old defaults (DDoS 20 IPs / 200 reqs / 3-req block;
path-flood 5 / 15 / 10) sat below real peak — a single popular mobile-browser UA
shared by many visitors was read as a botnet fingerprint and every visitor
making 3+ requests under it was banned (search sessions hit hardest). Defaults
are raised to **DDoS 100 / 1000 / 20** and **path-flood 30 / 100 / 20**;
genuinely abusive single IPs are still caught by the per-IP weighted scorer, and
the path-flood firewall ban now gates on backend-reaching **200s only** (a 444-only
IP is already free-blocked by Nginx). If anyone is still stuck from an earlier
false-positive ban, **`clearwebbans`** releases every web ban at once.

## DNS Resolver Hardening

A new **`nodnsupdate`** dhclient enter-hook stops the ISC DHCP client overwriting
BOA's `/etc/resolv.conf` on lease renewal, pinning the box to its intended
resolvers (local `unbound` plus public fallbacks); the runtime path also writes
`resolv.conf` immutable as defence-in-depth. The standalone **`dhcpfix`** tool was
reworked for safe use on a live box — it auto-detects the active DHCP client
(`dhclient`/`dhcpcd`/NetworkManager) and applies the matching no-op without
rewriting `dhclient.conf` or touching `/etc/network/interfaces`.

## Operator Notes

This release has **no must-do action** for a standard BOA box to keep working.
The notes below cover the few changes an operator may want to act on.

- **Re-apply custom-pinned CPU load ratios.** The two drastic high-load ceilings
  are raised fleet-wide (MAX `4.1 → 6.1`, CRIT `6.1 → 8.1` per CPU core). The
  one-time `autoupboa` re-seed rewrites `_CPU_MAX_RATIO` / `_CPU_CRIT_RATIO` /
  `_CPU_TASK_RATIO` / `_CPU_SPIDER_RATIO` in `/root/.barracuda.cnf`
  **unconditionally**, so if you deliberately pinned custom CPU ratios,
  **re-apply them after this update** — pinned values are not preserved.
  Operators who did not pin custom ratios need do nothing.
- **HTTP/1.0 registration-spam ban is on by default.** No action on a standard
  direct-to-origin BOA box. Opt out (`_NGINX_HTTP10_AUTH_DETECT=NO` in
  `/root/.barracuda.cnf`) **only** behind a non-BOA front proxy/CDN that talks
  HTTP/1.0 to origin, or on a box not yet updated to the HTTP/1.1 proxy confs —
  and only after confirming from the access log that real clients show
  HTTP/1.1 / HTTP/2 and only the bot shows HTTP/1.0.
- **i18n translation-flood guardrail is on by default.** Safe for normal
  multilingual sites. To opt a host out, add `"example.com" 0;` to
  `/data/conf/boa_i18n_guard.map` (a BOA-managed wildcard include; absent/empty
  = on for every host) — needed only for a non-Drupal app or a single-language
  site that uses a leading two-letter path for a region rather than a language.
  The per-vhost in-flight cap (default 24) is tunable via the
  `nginx_i18n_anon_conn` Provision option.

## Component Versions

> Only one bundled component changed this cycle. The full current pin set should
> be confirmed against the codebase before publication.

| Component | Version |
|---|---|
| cURL | 8.21.0 (was 8.20.0) |

All other bundled components are **unchanged since BOA-5.10.1**: Nginx 1.31.2,
OpenSSL 3.5.7 LTS, PHP APCu 5.1.28, PHP GEOS 1.0.0, Composer 2.8.2, Apache Solr
9.10.1, the bundled Drush set, and Commerce Kickstart 3.3.6.

## Supported / Tested Drupal Distributions

**Unchanged since BOA-5.10.1.** The current tested set remains Drupal CMS
installer 2.1.3 (Drupal 11.3.12), OpenCulturas 3.0.2, Commerce Kickstart 3.3.6,
LocalGov 4.0.3, Thunder 8.3.6, Varbase 10.1.0, and vanilla Drupal cores 10.2.12,
10.3.14, 10.4.10, 10.5.12, 10.6.11, 11.1.10, 11.2.14, 11.3.12.

## Important Fixes

- **Recurring false bans of webhook/API providers, fixed:** the path-ignore
  exemption list was not being applied at runtime (a shell word-splitting issue
  under `scan_nginx`'s global IFS), so configured exempt paths were still scored
  and their IPs banned. The exemption now applies correctly, and the new
  HTTP/1.0 detector carries the same hardening.
- **Path-flood per-IP gate:** the prior release added a 200-only counter but
  did not yet read it, so the gate banned on the combined 200+444 count; the
  documented intent is now wired in.
- **FPM capacity:** dedicated tenants throttled and siblings 502'ing after a
  routine upgrade (pool reset to the flat tier), and tiny VMs pinned to a 1 GB
  per-pool `memory_limit` that caused OOM — both fixed.
- **FPM-saturation check in `php.sh`:** matched the wrong log signal (the global
  `process.max` ceiling BOA disables) so it never fired; it now matches the
  per-pool `reached max_children setting` with byte-offset tracking.
- **Monitor stack:** the high-load auto-pause now re-reads the current load
  after its cooldown instead of re-checking the entry value, `loadreport`
  captures process data correctly on a real box, monitor-throttle precedence no
  longer misclasses a tiny box carrying both `.slow`/`.fast.cron.cnf`, and the
  SQL-backup/daily re-entrancy check compares its flags correctly so the task
  queue is deferred again during backups.
- **`nodnsupdate` guard hook** is now installed reliably on boxes that did not
  already have the dhclient hooks directory.

## New Documentation

- `docs/MONITOR.md` *(new)* — operator reference for the self-healing monitor
  stack: cron fan-out and the CI/SLOW/NORMAL throttle, per-service watchdogs,
  load auto-pause, process guards, and `loadreport`.
- `docs/ABUSE-GUARD.md` *(new)* — operator reference for the Nginx Abuse Guard:
  `scan_nginx` scoring, the realtime request guards, the `csf` ban pipeline, the
  Tier-A/Tier-B i18n flood protection, the HTTP/1.0 registration-spam detector,
  and the configuration knobs.
- `docs/PHP-FPM.md` expanded with the plan-based worker + `memory_limit` model;
  `docs/SELFUPGRADE.md` corrected so `_AUTO_VER` lists the real tier tokens
  (`dev`/`pro`/`lts`); `docs/MIGRATE-XOCT.md` and `docs/SSL.md` note that the
  `xoct`-generated proxy vhosts talk HTTP/1.1 to origin.

## Upgrade Instructions

Run inside a `screen` session as root:

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts
octopus up-lts all force
reboot
```

For silent, logged mode (output to `/var/backups/reports/up/`, emailed on
completion — useful for cron):

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts log
octopus up-lts all force log
```

Full upgrade documentation: https://github.com/omega8cc/boa/blob/5.x-dev/docs/UPGRADE.md
Self-upgrade automation: https://github.com/omega8cc/boa/blob/5.x-dev/docs/SELFUPGRADE.md

## Links

- Commit history (BOA): https://github.com/omega8cc/boa/commits/5.x-dev/
- Commit history (Provision): https://github.com/omega8cc/provision/commits/5.x-dev/
- Full changelog: https://github.com/omega8cc/boa/blob/5.x-dev/CHANGELOG.txt
- License: https://github.com/omega8cc/boa/blob/5.x-dev/DUALLICENSE.md
