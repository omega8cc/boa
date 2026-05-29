# Active Threat Response & Deep Hardening Edition

## New BOA-5.9.3 PRO/LTS Release Notes

## ⚠️ URGENT: Highly Critical Drupal Security Release — May 20, 2026

A highly critical Drupal core security release (rated 20/25) is scheduled for
**May 20, 2026 between 17:00–21:00 UTC**. Every supported Drupal version from
8 through 11 is affected. Exploits may appear within hours of the announcement.

Full details: https://www.drupal.org/psa-2026-05-18

**BOA cannot apply these patches automatically.** Drupal 8+ codebases are
Composer-managed — patching core outside Composer breaks codebase integrity
and cannot be safely automated across all projects without operator review.

**Customers on any active plan at https://omega8.cc/managed** will receive
priority updates within hours of the release.

**Everyone else** must be ready to run urgent Composer updates and redeploy
platforms through Aegir on May 20. If you would rather not face the next
critical release alone, this is what https://omega8.cc/managed exists for.

## ⚡ ACTION REQUIRED: Upgrade and Reboot

This release includes a new kernel. Run the full upgrade sequence and reboot
at your earliest convenience — do not skip the reboot:

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts
octopus up-lts all force
reboot
```

Running the new kernel closes kernel-level vulnerabilities and is especially
important given the active threat environment described in the alert above.

## Overview

BOA-5.9.3 PRO/LTS covers over three months of development since the HTTP/3 &
KTLS milestone of BOA-5.9.1. The dominant theme is **active threat response**:
the IDS layer has been substantially rewritten, Provision Nginx templates have
gained multiple new DDoS mitigation layers, and CSF tuning has been tightened
across the board. Alongside the security work, this release delivers full
PHP 8.5 toolchain coverage, Valkey hardening, a revamped MySQL backup stack,
and several new administrative tools.

Two fixes with direct operational impact should be applied promptly on any
affected system:

- **Critical PHP CLI version selection bug** — PHP 8.4 was always chosen over
  8.3 on dual-version systems due to a missing `$` in
  `_satellite_check_strict_php_cli()`.
- **Percona 8.4.8 upgrade blocker** — a soname bump
  (`libperconaserverclient22` → `libperconaserverclient24`) caused APT to
  refuse the upgrade, leaving servers on Percona 8.0 indefinitely.


## Security & DDoS Mitigation

### IDS Layer: scan_nginx.sh

The `scan_nginx.sh` scanner has received its most significant upgrade in this
release cycle:

**Byte-offset tracking** eliminates re-reading the entire Nginx access log on
each invocation. The scanner records its file position and resumes from there,
making it fast enough to run on a sub-minute schedule without I/O overhead or
false positives from log rotation races.

**Path-flood and search-amplification detection** is a new layer that
identifies IPs hammering a single URI pattern or abusing Drupal's site search
to amplify PHP-FPM load. Matched IPs are blocked via CSF before they cause
measurable latency impact — without requiring Nginx rate limits that would
also throttle legitimate traffic.

**Self-healing for stuck worker processes** (`_kill_stuck_fire` and
`_kill_stuck_fire_external`) automatically detects and terminates hung scanner
processes, preventing the IDS from wedging during sustained attacks.

**Login-aware blocking** — the scanner now cross-references successful admin
login markers before issuing a block, ensuring that a valid admin session is
never interrupted by an automated block triggered during the same log window.

Three legacy Perl IDS scripts have been rewritten in Bash, improving
portability and debuggability. The `hackcheck.sh` SSH brute-force scanner has
also been extended to catch additional `Invalid user` message variants.

### Nginx DDoS Hardening (Barracuda)

- `_DEFAULT_NGINX_DOS_STOP` variable added for early flood detection
- Path-flood threshold configurable via `_NGINX_PATH_FLOOD_IP_THRESHOLD=5`
- HTTP 444 silent drop now used instead of 403 for all blocked connections
- CSF DNS reverse-lookup checks disabled (reduced latency during large attacks)
- CSF recidivist threshold lowered to 24 (faster repeat offender blocking)

### Nginx DDoS Hardening (Provision — Aegir Nginx Templates)

The Provision Nginx templates have gained the most extensive set of DDoS
mitigations in BOA history:

| Commit | Change |
|--------|--------|
| `is_catalina_stale_chrome` | Botnet UA pattern detection, 444-drops at map level |
| `block_search_root_referer` | Blocks Drupal login-redirect search amplification |
| `is_ai_crawler` | Separate map for AI training crawlers, independent rate limits |
| `limit_req_zone` | Global request-rate zone for fine-grained throttling |
| `ua_denied` extended | Exploit framework and vulnerability scanner UA patterns |
| `is_denied` extended | SQLi timing/blind attacks (SLEEP, WAITFOR, BENCHMARK) |
| TLS ClientHello detection | 444-drops TLS frames sent to plain HTTP port |
| `search_api_fulltext` guard | Direct hits without valid session blocked at Nginx level |
| `variables_hash_max_size` | Increased to prevent hash-bucket overflow |
| `fastcgi_cache_use_stale` | Removed `http_503` to prevent stale-cache serving on downtime |
| `llms_txt` module routing | Correct routing for /llms.txt and files/llms.txt |
| Crawler list updated | Added Turnitin, IbouBot; Claude moved to `is_ai_crawler` |


## PHP

### Critical Fix: PHP CLI Version Selection

A missing `$` in `_satellite_check_strict_php_cli()` caused a literal string
comparison instead of a variable lookup. On any system with both PHP 8.3 and
PHP 8.4 installed, PHP 8.4 was always selected for CLI operations (Drush,
Composer) regardless of the version pinned in `/root/.barracuda.cnf` or
Octopus control files.

This fix restores correct behaviour. Verify your CLI version after upgrading:

```bash
php -v
```

### PHP 8.5: Full Toolchain Coverage

PHP 8.5 is now fully supported across all BOA tools:

- **Imagick 3.8.1** — first Imagick release with PHP 8.5 support; the
  `_fix_php_ini_imagick` helper has been extended accordingly
- **New Relic APM** — now supports PHP 7.2 through 8.5

`php-min` now covers only 8.3, 8.4, and 8.5. Support for older versions has
been removed from the minimum-set definitions.

**Updated PHP versions:** 8.5.6 / 8.4.21 / 8.3.31 / 8.2.31


## Percona / MySQL

### Percona 8.4.8 Upgrade Blocker Fixed

Percona 8.4.8-8 introduced a silent soname bump. The old
`libperconaserverclient22-dev` package conflicts with the new
`libperconaserverclient24`, causing APT to refuse the upgrade with an
unresolvable dependency error and leaving the server on Percona 8.0
indefinitely.

Barracuda now removes the blocking package during the
`_run_aptitude_full_upgrade` phase and syncs `libperconaserverclient24`
before the Percona upgrade step. No manual intervention is required.

### MySQL Backup Stack

- `mydumper` now uses `--sync-thread-lock-mode=AUTO`, shortening the global
  read-lock (FTWRL) window on InnoDB tables and reducing backup impact on
  live sites
- A separate `_backup_mysql_schema` procedure takes schema-only dumps,
  enabling faster structure restores independent of data dumps
- The backup script is now guarded against being overwritten while a backup
  is running
- `secure_file_priv = NULL` added for compatibility with tools using
  `SELECT INTO OUTFILE`
- Custom slow-query and binary logging enabled for Percona
- The X Protocol plugin (`mysqlx`, port 33060) is now disabled on Percona 8.x
- Updated `MyDumper` to 0.21.3-2 / 0.19.3-3


## Valkey

Valkey has received significant configuration hardening in this release:

- **Version:** 9.0.4
- **2× RAM allocation by default** — `maxmemory` is now computed as twice the
  previous default, reducing eviction pressure on high-traffic sites without
  manual tuning
- **RDB snapshots disabled** — `_valkey_no_rdb` is now active by default;
  SAVE operations caused latency spikes under write load
- **`maxmemory-policy allkeys-lru`** — appropriate for a pure cache workload
  where every key is eligible for eviction when memory pressure is high


## Solr

- **Orphan cores health-check every 6 hours** — cores without a matching
  Aegir site are detected and cleaned up automatically, preventing Solr heap
  exhaustion
- **`_optimize_solr_cores`** — new documented sub-command runs a full Solr
  optimize on all active cores; useful before migrations or after large imports
- **Race condition protection** — concurrent Barracuda runs or overlapping cron
  triggers can no longer start a Solr install/restart while another is active
- **Faster restart logic** — upgrades no longer wait for a cold restart when
  a warm restart is sufficient


## Network & autoinit

### Interface Stability for eudev / IONOS Hosts

On IONOS VPS hosts and any provider where `eudev` replaces `systemd-udev`
during Debian-to-Devuan migration, the network interface name can shift
(e.g. `ens6` → `eth0`) unpredictably. Several commits fix this in depth:

1. **Interface rename detection** now happens _before_ any network check,
   not after — preventing a false "network is up" verdict that skipped `vmnetfix`
2. **udev MAC-pinning rule** written before reboot to prevent any future rename
3. **`/etc/network/interfaces` consistency check** verifies the configured
   interface name exists in the kernel before proceeding
4. **Explicit `post-up` onlink helpers** written for `/32` subnet configurations
   where the gateway falls outside the local subnet, making post-reboot routing
   reliable on IONOS /32 allocations


## Performance

- **`_swap_purge_if_bloated`** — when swap exceeds `_SWAP_THRESHOLD=50%`,
  triggers a drop-caches cycle followed by swapoff/swapon to reclaim swap space
  occupied by idle processes
- **APC = ½ × PHP-FPM pool (dynamic)** — opcache memory is now derived at
  runtime as half the PHP-FPM worker pool size, right-sizing it for both small
  and large instances
- **Byte-offset IDS scanning** — scan_nginx.sh no longer re-reads the full log
  on every invocation (see IDS section above)


## Tools

| Tool | Change |
|------|--------|
| `renamemaster` | New: rename Aegir Master hostname end-to-end |
| `renameaegirhost` | Now universal — handles both Master and Satellite |
| `fixmounts` | New: diagnose and repair `/etc/fstab` and TRIM eligibility |
| `xoct` | `http-off` PHP short-circuit for migrations; speed cache purge on toggle; `_xoct_transfer_static_symlink_safe` |
| `updatesymlinks` | New: batch symlink update for automation pipelines |
| `autosymlink` | Track detected/valid sites for orphan static/files reporting |


## System & Reliability

- **`_if_new_kernel_reboot`** — detects kernel upgrade and schedules reboot
- **`_purge_avahi`** — removes avahi-daemon during upgrades (causes DNS delays,
  serves no purpose on headless servers)
- **`_fix_grub_pc_install_devices`** — improved detection for NVMe and
  multi-disk systems during dist-upgrades
- **`/etc/sysctl.conf` modernised** — BBR congestion control, updated inotify
  limits, TCP backlog adjustments
- **OpenSSH 10.3p1 / OpenSSL 3.5.6 LTS** — latest security releases


## Let's Encrypt

- `RENEW_DAYS` increased to **69** (from 8), providing a much wider safety
  margin and aligning with the upcoming 90-day certificate lifetime default
- **DNS-PERSIST-01 challenge type** now supported in the dehydrated client
  configuration, enabling renewal automation for firewall-restricted domains


## Sendmail

- **Root-only sendmail access by default** — direct sendmail access from
  Octopus user accounts is blocked; create `/root/.allow.sendmail.cnf` to
  re-enable for trusted instances
- Lock/unlock logic refactored to prevent stale locks after interrupted runs


## Drupal / Aegir

- `tag1_d7es-7.x-1.4` added to `o_contrib_seven` and Hostmaster;
  `d7security_client` removed (superseded by tag1_d7es)
- Nginx: `llms_txt` module routing added
- Nginx: AI crawler classification separated from search-engine crawlers
- Drush 8.5.0.5 classic


## Component Versions

| Component | Version |
|-----------|---------|
| cURL | 8.20.0 |
| Drush | 8.5.0.5 classic |
| Imagick | 3.8.1 |
| Java | 11.0.31 / 17.0.19 / 21.0.11 |
| MyDumper | 0.21.3-2 / 0.19.3-3 |
| New Relic | 12.7.0.36 |
| Nginx | 1.31.0 |
| OpenSSH | 10.3p1 |
| OpenSSL | 3.5.6 LTS |
| PHP | 8.5.6 / 8.4.21 / 8.3.31 / 8.2.31 |
| Unbound | 1.25.0 |
| Valkey | 9.0.4 |


## Upgrade Instructions

Run inside a `screen` session as root:

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts
octopus up-lts all force
```

For silent logged mode (output written to `/var/backups/reports/up/` and
emailed on completion — useful for cron):

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts log
octopus up-lts all force log
```

Full upgrade documentation: https://github.com/omega8cc/boa/blob/5.x-dev/docs/UPGRADE.md

There are no Drupal platform updates in this release beyond the o_contrib_seven
change noted above. Nginx reload during the CSF rule refresh causes ~2–5 seconds
of connection drops for in-flight requests.


## Links

- Commit history (BOA): https://github.com/omega8cc/boa/commits/5.x-dev/
- Commit history (Provision): https://github.com/omega8cc/provision/commits/5.x-dev/
- Full changelog: https://github.com/omega8cc/boa/blob/5.x-dev/CHANGELOG.txt
- License: https://github.com/omega8cc/boa/blob/5.x-dev/DUALLICENSE.md
