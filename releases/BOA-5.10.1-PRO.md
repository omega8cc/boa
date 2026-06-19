# AI Policy Edition

## New BOA-5.10.1 PRO/LTS Release Notes

## ⚡ ACTION REQUIRED (CiviCRM sites): enable the CiviCRM command-file control

The `*.drush.inc` command-file filter introduced in **BOA-5.9.5** — which was
**inert** in that release — now actively denies Drush command files under
tenant-writable paths. CiviCRM legitimately ships its own command files
(`civicrm.drush.inc`, `cv.drush.inc`, `civicrm_drush.drush.inc`) inside the site
tree, so **Ægir backend tasks** (verify, migrate, clone) on a CiviCRM site now
require those files to be explicitly allowlisted — an opt-in, per Octopus user,
off by default.

To enable it for an Octopus user (**requires root**), create the control file:

```sh
touch /data/conf/<octopus-user>_civicrm.txt
```

(The Octopus user is derived from the backend task's `$HOME` under `/data/disk/`.)

> **This affects only Ægir backend tasks, not PHP-FPM.** Normal web requests to a
> CiviCRM site never go through Drush, so they are entirely unaffected — the site
> keeps serving traffic exactly as before, with or without the control file. Add
> the file for each affected Octopus user before running their next verify or
> migrate task. **Customers on a managed plan at https://omega8.cc/managed have
> this handled by our team.**

---

## Overview

BOA-5.10.1 PRO/LTS is an **edge-hardening features release**. In total,
**249 commits across five repositories** went into this release:

| Repository | Branch | Commits |
|---|---|---|
| omega8cc/boa | 5.x-dev | 225 |
| omega8cc/provision | 5.x-dev | 19 |
| omega8cc/drush | 8-boa-micro | 3 |
| omega8cc/hosting | 5.x-dev | 1 |
| omega8cc/hosting_le | 5.x-dev | 1 |

The headline is a new **per-class, per-site AI bot policy** backed by
**Cloudflare-aware real-client-IP enforcement**, **web-abuse bans that bite at
nginx** even behind the CDN, and a guided **`edgetest`** harness. The cycle also
refreshes the **tested/supported Drupal distros**, lands the **HTTP/3
trusted-host fix** and the **clone/rename certificate-grab closure**, and
delivers **Percona 8.4 upgrade reliability** work.

---

## AI Bot Policy

The single broad `$is_ai_crawler` deny is replaced by mutually-exclusive,
full-token-matched classes, each independently governable and togglable per site:

- **Training** (GPTBot, ClaudeBot, CCBot, Bytespider, Amazonbot,
  Meta-ExternalAgent, AI2Bot, Diffbot, cohere-ai, omgili, Claude-Web,
  anthropic-ai) — **blocked by default (444)**, with a per-site opt-in to allow.
- **Search / User / Utility** — **allowed and rate-limited per vendor.** The
  rate-limit key is the user-agent, not the client IP, so a vendor's many
  published IPs are capped in aggregate rather than per-IP.
- **Evasive** — **blocked by default**, with a per-site `evasive-allow` opt-in.
  **Perplexity-User** is classified here because it drops its UA and rotates
  IPs/ASNs when blocked, which let a distributed fan-out reach the origin under
  the old allow-by-default handling. **Google-Agent** (Gemini / Project Mariner
  user-triggered browsing) is classified as an honest user and allowed.
- **Forged** — a robots.txt-only opt-out token (`Google-Extended`,
  `Applebot-Extended`) appearing in a request UA is treated as proof of forgery
  and **universally denied (444)**.

Per-site policy is driven by `static/control/ai/policy.txt`; `ai_policy.sh`
writes the per-site nginx fragments across every Octopus instance, with per-class
rate-limit zones.

**Docs:** per-site how-to —
[docs/AI-POLICY-USER.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/AI-POLICY-USER.md);
per-server overview —
[docs/AI-POLICY.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/AI-POLICY.md);
edge testing —
[docs/AI-POLICY-TESTING.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/AI-POLICY-TESTING.md).

---

## Per-Site IP Access Control

An individual site can be locked to specific IP addresses — useful for an
intranet, a staging site, or an admin-only area; everyone else gets a 403.
Per-site allow lists live in `static/control/ip/access.txt` and are applied by
the global `ip_access` generator, with built-in anti-lockout (the server's own
address, the loopback, and any address currently logged in over SSH are always
allowed) and a ~2-minute pickup. Behind Cloudflare the list matches on the
visitor's real IP.

**Docs:** per-site how-to —
[docs/IP-ACCESS-USER.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/IP-ACCESS-USER.md);
per-server overview —
[docs/IP-ACCESS.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/IP-ACCESS.md).

---

## Real Client IP, Everywhere

Behind Cloudflare, the origin only ever sees the CDN edge IP — which breaks rate
limits, bans, logs, and Drupal's notion of the client. This release closes that
blind spot end to end:

- **`real_ip_header CF-Connecting-IP`** with a BOA-managed, auto-refreshed list
  of Cloudflare edge ranges (`cloudflare_realip.sh`), so rate-limit keys,
  `REMOTE_ADDR`, bans, and logs all reflect the true visitor.
- **PHP `REMOTE_ADDR` pinned to the original TCP peer** so Drupal's
  reverse-proxy handling cannot be fed a spoofed client address.
- **The nginx IDS (`scan_nginx`) scores and bans the real client IP**, not the
  spoofable left-most `X-Forwarded-For` value — closing a ban-evasion /
  innocent-IP-framing vector.
- **A new ban-writer mirrors CSF web-abuse bans into an nginx `geo` set**
  (first-guard 444), so a banned real-client IP is dropped at nginx even through
  Cloudflare, where an origin firewall ban would only ever see the CDN edge.
- **Migration-proxy realip / IDS / CSF hybrid:** during an `xmass`/`xoct`
  migration the old host becomes a reverse proxy, so it is trusted at the nginx
  realip layer and hard-whitelisted at the CSF/lfd layer from a control file;
  validators reject `0.0.0.0/0` and any `/0`.

GoAccess-compatible logging records the realip-resolved client as the host field,
with the full `X-Forwarded-For` chain preserved as a trailing `xff=` field.

---

## New Tools

| Tool | Description |
|---|---|
| `edgetest` | Guided one-command pass/fail checker for the whole edge stack; read-only by default, `--full` runs reverted state-changing proofs, `--remote` does cross-box checks. Asserts the evasive Perplexity block and Google-Agent allow. |
| `ai_policy.sh` | Per-site AI policy generator across all Octopus instances. |
| `ip_access` (global) | Single global per-site allow/deny generator with anti-lockout, prune-on-removal, and per-instance configtest/reload/rollback. |
| `cloudflare_realip.sh` / nginx ban-writer | Monitored range/ban generators with atomic writes, change-gating, and a shared nginx-config reload lock to close reload races. |
| `fpm_tune` / `fpmreport` | Read-only adaptive PHP-FPM sampler (changes no tuning) plus an aggregating report tool. |

---

## Hardening & Validation

- **Universal, anchored deny** for secret/config path families (`.env`, `.git`,
  `.aws`, `.ssh`, `secrets.json`, `key.json`, `config.json`, `settings.py`,
  `application.yml`, and similar), matched on the normalized URI so
  percent-encoded and substring evasion cannot bypass it — blocking even a plain
  browser UA.
- **TLS verification restored on external fetches:** dropped insecure `curl -k`
  and standardised ad-hoc fetches on the canonical `_crlGet` with `--fail`, so an
  HTTP error yields an empty body instead of an error page parsed as hostile
  CIDRs.
- **Strict IPv4/IPv6 octet and prefix validation** added to the `ip_access`,
  nginx-deny, Cloudflare-realip, and `csf.allow` generators; a malformed token is
  skipped fail-closed and can no longer break configtest fleet-wide.
- **Drush `*.drush.inc` filter** (the drupal.org #762138 arbitrary-code-execution
  guard) fixed from a silent no-op so the guard now **engages on tenant-writable
  command files where it previously did not**; paths resolved with `realpath()`
  before matching and discovery filtered by path. This alters Drush command
  discovery — see the **ACTION REQUIRED** block for the CiviCRM allowlist.

---

## Clone / Rename Certificate-Grab Closed

A renamed site (Migrate with a changed machine-name) or a clone no longer
inherits the source machine-name's TLS certificate. The new front-end node resets
Encryption to disabled and detaches the old `ssl_key` before save, and stale
per-site Let's Encrypt control files are cleaned up so a later re-enable starts
clean. The hostmaster site and a same-name migrate are unaffected.

> If the new domain should serve TLS, **deliberately re-enable Encryption** for
> it in the Ægir front-end.

---

## Percona 8.4 Upgrade Reliability

- `mysqld` is restarted **unconditionally** after writing startup-only directives
  so `mysql_native_password=ON` loads and root can connect.
- Directive sync is decoupled from innodb sizing, killing an unbounded recursion
  on fresh / `SAME=NO` installs.
- A down `mysqld` is started rather than waited on forever.

> **Note:** a Percona version transition involves a brief `mysqld` restart on the
> upgrade path — plan a short maintenance window.

---

## ICU Pin for Legacy PHP 7.4 intl

ICU is now configurable via `_ICU_FORCE_VRN` in `/root/.barracuda.cnf`, with
apply / precheck / retire handling and an `autoupboa` weekly auto-heal for PHP 7.4
`intl` after a system ICU bump. Off by default; manual procedure in
`docs/ICU-PIN.md`.

---

## Component Versions

> Key components changed this cycle. The full current pin set should be confirmed
> against the codebase before publication.

| Component | Version |
|---|---|
| Nginx | 1.31.2 |
| OpenSSL | 3.5.7 LTS |
| PHP APCu | 5.1.28 |
| Composer | 2.8.2 (rolled back from 2.10.1) |
| Drush (classic) | 8.5.3 |
| Drush | 10.6.2, 11.6.0 (pins de-suffixed) |
| Apache Solr | 9.10.1 |
| PHP GEOS | 1.0.0 (now default on PHP 7.x / 8.x) |
| Commerce Kickstart | 3.3.6 |

---

## Supported / Tested Drupal Distributions

Dropped legacy **Varbase 9** and the unstable **Sector** distro. Current
tested set:

- Drupal CMS installer 2.1.3 (Drupal 11.3.12)
- OpenCulturas 3.0.2
- Commerce Kickstart 3.3.6
- LocalGov 4.0.3
- Thunder 8.3.6
- Varbase 10.1.0
- Vanilla Drupal cores: 10.2.12, 10.3.14, 10.4.10, 10.5.12, 10.6.11, 11.1.10,
  11.2.14, 11.3.12

---

## Important Fixes

- **multiback backups:** the earlier credential-hiding change broke duplicity
  (the B2 backend has no key env var, and the boto3/S3 endpoint form mis-parsed
  for some providers, risking writes to the wrong bucket). The in-URL credential
  form was restored and the updater serial bumped so nodes re-fetch.
- **mysqldump / rsync permissions:** restored `755` on `/usr/bin/mysqldump` and
  `/usr/bin/rsync`, which had been left `750 root:root` so the unprivileged
  `aegir` user could not run them and backups failed with "Permission denied".
- **`$is_ai_crawler` shim restored:** a barracuda upgrade re-renders the master
  http config before instance vhosts, so a not-yet-re-rendered vhost referencing
  the removed variable caused an `nginx -t` failure that took every instance down
  until re-rendered; the variable is kept as a do-not-remove backward-compat shim.
- **ip_access** out-of-range octet typos no longer reach an allow line and block
  nginx reloads box-wide.
- **BOA.sh.txt serials:** multiple `fNN` corrections after the down-counting rule
  was violated, so deployed boxes actually re-fetch the corrected scripts.
- **edgetest false-FAILs:** settle the async nginx reload before toggle/ban
  probes, default to HTTP and switch to HTTPS only on an enforced redirect, and
  classify 5xx/403 as inconclusive.

---

## New Documentation

The new per-site edge controls and the edge-test harness are documented in the repo:

- AI bot control, per site: [docs/AI-POLICY-USER.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/AI-POLICY-USER.md)
- AI bot policy, per-server overview: [docs/AI-POLICY.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/AI-POLICY.md)
- AI bot policy and edge testing: [docs/AI-POLICY-TESTING.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/AI-POLICY-TESTING.md)
- IP access control, per site: [docs/IP-ACCESS-USER.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/IP-ACCESS-USER.md)
- IP access control, per-server overview: [docs/IP-ACCESS.md](https://github.com/omega8cc/boa/blob/5.x-dev/docs/IP-ACCESS.md)

---

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

---

## Links

- Commit history (BOA): https://github.com/omega8cc/boa/commits/5.x-dev/
- Commit history (Provision): https://github.com/omega8cc/provision/commits/5.x-dev/
- Full changelog: https://github.com/omega8cc/boa/blob/5.x-dev/CHANGELOG.txt
- License: https://github.com/omega8cc/boa/blob/5.x-dev/DUALLICENSE.md
