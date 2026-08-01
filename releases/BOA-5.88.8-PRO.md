# Continuity Edition

## New BOA-5.88.8 PRO/LTS Release Notes

BOA-5.88.8 PRO/LTS is a milestone for the 5.x tree — a **continuity
release** in every sense of the word. It gives every generation
of the Drupal family a first-class, supported home on one platform:
**Backdrop CMS support ships enabled by default**, a complete
**Drupal 6 → 7 → Backdrop upgrade chain** runs as ordinary control-panel
tasks, **classic Ægir estates can be imported wholesale**, and a rebuilt
**server-to-server migration suite** moves whole servers across Percona
generations. Around the code, the project's public face is renewed:
**[docs.boa.io](https://docs.boa.io)** — the new unified documentation
site — and the new **[omega8.cc](https://omega8.cc)** website with a
**[/news](https://omega8.cc/news)** section are both live. And yes, the
version says **5.88.8**: we are staying in the 5.x tree, and after a cycle
this large the eights felt earned — turn one on its side and you get ∞,
which is rather the point of a Continuity Edition.

In total, **422 commits across six repositories** went into this release:

| Repository | Branch | Commits |
|---|---|---|
| omega8cc/boa | 5.x-dev | 341 |
| omega8cc/provision | 5.x-dev | 57 |
| omega8cc/hosting | 5.x-dev | 19 |
| omega8cc/drush | 8-boa-micro | 2 |
| omega8cc/eldir | 5.x-dev | 2 |
| omega8cc/hosting_tasks_extra | 5.x-dev | 1 |

One more piece of continuity worth stating plainly: the LTS edition
**remains fully current alongside PRO**. The code freeze once pencilled in
for the free edition did not take effect — every headline feature in this
release ships for **both PRO and LTS**.

## A New Home: docs.boa.io and the New omega8.cc

- **[docs.boa.io](https://docs.boa.io)** consolidates years of BOA
  documentation into one unified, searchable site, organised by audience:
  **Using Ægir**, **Self-Hosting**, **Operating**, and **Developing** —
  plus quick-start **cheat sheets** and a generated **reference** of
  configuration variables, commands and control files.
- The new **[omega8.cc](https://omega8.cc)** is live, including a
  **[/news](https://omega8.cc/news)** section (with RSS) where every BOA
  release and platform milestone is announced from now on.
- Release notes have a permanent home in the documentation as well, so the
  full technical record of each release stays one click away from the docs
  it relates to.

## Backdrop CMS Support — Enabled by Default

Backdrop CMS — the community continuation of the Drupal 7 lineage — is now
a **first-class citizen** on every BOA server, and it ships **enabled by
default** (`_BACKDROP_SUPPORT=YES`, opt-out in `/root/.barracuda.cnf`).

- **Full lifecycle in the control panel.** Backdrop platforms are built
  automatically alongside the Drupal set, and Backdrop sites install,
  verify, clone, back up, restore and renew HTTPS certificates through the
  same Ægir tasks Drupal sites use. Backdrop platforms and sites carry a
  clear **BDR badge** in the panel.
- **`bee` command-line support.** Backdrop's CLI companion is installed and
  wired into the same safe shell environment as Drush, and follows the same
  per-site PHP-CLI selection.
- **Valkey/Redis object cache** for Backdrop platforms, matching the
  caching Drupal sites get.
- **Site cron routed to `core/cron.php`** with the cron key handled
  natively; `core/update.php` is gated in the vhost like its Drupal
  counterpart.
- **The upgrade chain is the headline.** Two new clone-preserving site
  tasks carry a legacy site forward without ever touching the original:
  **Drupal 7 → Backdrop** (`backdrop_upgrade`) runs the whole conversion on
  a dark copy, and **Drupal 6 → Drupal 7** (`backdrop_d6_upgrade`) covers
  the first hop with a pinned contrib kit and a dark D7 intermediate — so a
  D6 site can travel D6 → D7 → Backdrop entirely through control-panel
  tasks. When the copy is ready, the **`backdrop_cutover`** task takes over
  the original domain in one step, so the site keeps its URL.
- **Backdrop-to-Backdrop Migrate** works across Backdrop platforms; stock
  cross-lineage Migrate between Drupal and Backdrop is deliberately refused
  — the dedicated upgrade tasks are the supported path.
- **`utf8mb4_convert`** — a new front-end task (via hosting_tasks_extra)
  that converts imported Drupal 7 estates still on 3-byte utf8 tables, a
  common blocker for imported legacy databases.

Operator reference: `docs/BACKDROP.md` (new).

## Import from Classic Ægir

Vanilla Ægir estates — often orphaned on ageing Apache servers — now have a
supported road into BOA. The **aegir2boa** toolset ships in the standard
tools distribution:

- **`aegir2boa-preflight`** surveys a vanilla Ægir server and reports
  exactly what stage 1 and stage 2 will do to it.
- **Stage 1** converts a vanilla Ægir 3.x server from Apache to Nginx **in
  place**, with revert paths at every step.
- **Stage 2** adopts the `/var/aegir` estate into a BOA Octopus instance,
  via two routes: **per-site adoption** for mixed or unknown estates, and a
  **whole-DB import** for homogeneous, current-3.x estates.
- **`aegir3-install`** — an unattended vanilla Ægir 3.x installer for
  Debian — rounds out the set for building rehearsal estates before
  touching a production one.

Both routes were rehearsed end-to-end on disposable machines, with every
revert path drilled. Operator runbook: `docs/AEGIR2BOA.md` (new).

## Local Development: BOA Local and DDEV

- **BOA Local is back.** `boa in-lts local` installs a slim,
  local-development BOA profile on a VM or laptop — no public DNS, no
  licence gate, no manufacturer checks — so the full stack can be developed
  against locally.
- **`ddev-boa`** — a public DDEV add-on (`ddev add-on get omega8cc/ddev-boa`)
  that pulls a BOA-hosted site's database and files into a local DDEV
  project **through the client's own limited shell**, no root involved.
  Operator reference: `docs/DDEV-BOA.md` (new).

## Native Files-Directory Symlinking

New sites and clones now keep their `files/` and `private/` directories in
a **per-site static store outside the platform tree**, symlinked into
place (on by default for new installs and clones, kill-switchable):

- Codebases stay disposable: platform upgrades, migrations and renames move
  code while file assets stay put.
- **Clones get their own symlinked copy** — no accidental sharing.
- New **`symlinkinfo`** tool reports any site's symlink state and archive
  history; `updatesymlinks` gains a gated nightly **auto-fix** mode and a
  read-only daily **orphan report** (both opt-in; stale and orphaned stores
  are archived, never deleted).
- Per-account backup directories can relocate onto the same static
  filesystem overnight, freeing the system disk.

Operator reference: `docs/FILES-SYMLINK.md` (new, admin + per-site).

## Prebuilt Stack Packages on Devuan Daedalus

On **Devuan Daedalus** boxes, BOA now installs its heavy stack — Nginx,
Valkey, OpenSSL, PHP and friends — from **prebuilt `boa-*` Debian
packages** instead of compiling from source (`_USE_PREBUILT_PKGS`
auto-resolves to YES on Daedalus; explicit cnf setting always wins; other
OS releases keep building from source). Installs and upgrades get
dramatically shorter, and every component quietly falls back to the
source build if its package cannot be fetched or installed. The phase-2
set adds **boa-valkey (major 9)** and a **boa-nginx overlay**. Operator
reference: `docs/PREBUILT.md` (new).

## Night Maintenance, Rebuilt

The venerable nightly `daily.sh` monolith is now **`owl.sh`** plus a set of
single-purpose night workers:

- **Per-account work runs as isolated subprocesses** under a run-freeze, so
  one account's maintenance can never wedge the whole night.
- **All nightly cleanup blocks while a Provision task runs** — night jobs
  and control-panel tasks no longer race.
- **Classified ghost-site handling.** The night pass now tells a genuine
  ghost (alias and vhost present, site directory gone) apart from
  front-end records, platform-gone cases and stranded migrations. By
  default it **detects, reports and notifies** — the affected account's
  client contact gets one actionable email per site per month
  (`_GHOST_CLIENT_NOTIFY=YES`) — while every destructive cleanup move
  stays **opt-in** (`_GHOST_*_CLEANUP=NO`), moves things aside into an
  `undo/` area rather than deleting, and arms itself one night before the
  first real move.
- **HTTPS renewal failures now reach humans.** Each account's failed
  Let's Encrypt renewals are reported per account to the operator, and the
  client contact receives one throttled, actionable notice per site per
  week (`_LE_CLIENT_NOTIFY=YES`, with a Reply-To that reaches a person).

## The Server Migration Suite

The migration family — `xoct` (one instance), `xcopy` (one account),
`xmass` (replication-based whole-server moves) — was overhauled end to end
this cycle and validated as a full matrix on disposable VMs:

- **Percona 8.0/8.4-aware replication.** `xmass` now speaks the modern
  replication dialect end to end (REPLICA/SOURCE verbs on 8.4, GTID
  persistence in the include dir `my.cnf` actually reads,
  `binlog_expire_logs_seconds`, `GET_SOURCE_PUBLIC_KEY` replica auth,
  matching xtrabackup repos) — and **refuses** a cross-version 5.7 → 8.x
  replication move by design, where `xoct` handles the cross-version path.
- **Storage-aware, DRY-gated file transfer.** All three tools detect
  attached `/mnt` storage, relocate shared archives, fold Solr indices
  into the disk-space gate, and support dry runs before touching data.
- **`migratefs`** (new) relocates heavy site data onto attached storage
  safely, refusing ambiguous multi-mount setups.
- **`renameaegirhost`** is now fully self-contained for in-place hostname
  renames: site directory, control files, hostmaster verify and stale
  `sites.php` records are all handled, with an account axis for
  rename-mode migrations and documented recovery for aborted runs.
- **Migration renames fail loudly and resumably** — a failed rename parks
  the account for resume instead of half-moving it; panel database access
  is rewired on `xmass` targets before cutover; the migrated-in `503`
  gate clears the moment an import completes.
- **Modern Drupal arrives warm:** per-site PHP version pins are preserved
  through migration, and Drupal 8+ sites get a cold Valkey flush plus a
  PHP-FPM restart on arrival, clearing stale caches (the service
  container finishes rebuilding on the follow-up verify).

References: `docs/MIGRATE-XOCT.md` (updated), `docs/MIGRATE-PERCONA8.md`
(new cross-version Percona reference), plus a Percona 8 readiness How-To.

## Security and the Web IDS

The Nginx Abuse Guard and the wider intrusion-detection stack take another
major step this cycle:

- **Distributed UA-burst scanner-fleet detector** (on by default,
  `_NGINX_UA_BURST_DETECT`). A scanner fleet sharing one User-Agent across
  many IPs — each IP too quiet to trip per-IP limits — is recognised by
  the shared fingerprint's aggregate behaviour (many distinct IPs, high
  request count, overwhelmingly bad statuses) and banned as a unit.
- **Foreign-CMS probe guard.** Requests for admin paths that cannot exist
  on a Drupal, Backdrop or hostmaster docroot — `wp-admin`, `wp-login`,
  `phpmyadmin` and friends — are dropped with `444` at the edge before
  PHP ever sees them. (Adminer paths are untouched — BOA ships Adminer.)
- **IPv6 joins the adaptive web ban.** The web IDS now scores IPv6 clients
  and bans them through an nginx-native, self-expiring store — closing the
  gap left by the IPv4-only firewall layer — with IPv6 and CIDR support
  added to the per-site `ip_access` allow-list as well.
- **Per-site `/user` + `/admin` IP allow-list** (`user_admin_access`). One
  root-managed control file per Octopus instance locks any site's login
  and admin paths to listed IPv4/IPv6 addresses or subnets; the rest of
  the site stays public, and an anti-lockout rule always admits the
  server itself and established SSH peers.
- **Drush extension hygiene, default-secure.** Ægir backend identities no
  longer load `*.drush.inc` extensions from tenant-writable locations —
  closing a long-standing upstream attack path — with per-instance
  root-created opt-ins for CiviCRM and Elysia cron, and BOA's own
  extensions always loading. A verification runbook ships alongside
  (`docs/DRUSH-FILTER-TESTING.md`).
- **A quieter, harder edge everywhere else:** SSH/Web/FTP IDS input
  validation and a ban-evasion fix; log-scanner guards anchored to parsed
  log fields (an attacker-controlled username can no longer spoof its way
  past the SSH or FTP scanners); every `/etc/sudoers` write is
  visudo-validated and de-duplicated; the `fix-drupal-*` NOPASSWD wrappers
  are scoped to the calling tenant's own tree; Ægir install values hand
  off through sealed, per-spawn, owner-scoped includes; the TCP SACK
  mitigation persists across firewall restarts; a rebuilt `sshd_config`
  is validated before sshd restarts; and an invalid legacy ssh_config
  option that silently broke outbound SSH is removed.
- **Cloudflare-fronted sites: the intermittent 502 is gone.** The
  wild-ssl proxy path pinned its upstream to a dead IPv6 localhost
  candidate under load; the upstream is now pinned to `127.0.0.1`,
  Cloudflare ranges are whitelisted on port 443 as well as 80, and the
  proxied HTTPS path is enforced, observed and scored like any other.

## Modern Drupal (10/11) Reliability

- **The container-poison class of failures is fixed.** Drupal 10/11 sites
  could come out of a clone, deploy or fresh install with a service
  container compiled while Ægir's compatibility patches were reverted —
  poisoning the cached container and breaking the site until the next
  verify. All service-container rebuilds now run inside a **chmod-only
  window that keeps the patches applied** (deploy `updatedb`, fresh
  `site-install`, and the post-deploy cache rebuild alike).
- **Fresh D11 installs fail loudly or succeed cleanly:** a failed
  `site-install` now errors the task out instead of limping on, the
  one-time login link is generated correctly again, and the installer's
  policy-module cleanup actually runs.
- **New Drupal 11.4 platform** joins the auto-built set, and the whole
  tested core/distro catalogue moves to the 2026-07-17 build (below).

## The Ægir Panel and Client Experience

- **Welcome emails now include a working control-panel login.** A new
  client account is tied to the instance's SSH identity, so the recipient
  can sign into Ægir from day one — no more "random password nobody ever
  saw". The welcome email was rewritten around the new documentation, and
  every BOA-sent email is now **vendor-agnostic**, pointing at
  [docs.boa.io](https://docs.boa.io) and signed by The BOA Dev Team.
- **Password reset requests route to host support** instead of the
  disabled sendmail path, and the dormant "Request new password" link is
  hidden in the eldir theme.
- **One-step www/non-www rename** in the Migrate form: a site can move
  between `example.com` and `www.example.com` as a single rename, with the
  old alias handled correctly.
- **Imported installed sites land ENABLED** in the panel instead of
  parked in a queued state.

## Task Queue and Dispatch Reliability

- **The task-queue dispatcher is serialized** — concurrent dispatcher runs
  can no longer double-launch a task batch — backed by a per-instance
  lock on the queue runner itself.
- **A stale queue lock clears far sooner** after a crash (shortened lock
  timeout), the dispatcher **re-enables itself** after instance installs
  and upgrades and when a setup self-test fails, orphaned build
  temporaries no longer wedge the queue, and an empty upstream database
  record can no longer wipe stored database credentials.

## Operator Tools and Platform Ops

- **`boa suspend <user>` / `boa unsuspend <user>`** (new, root-only): gate
  every site of an Octopus instance behind an HTTP 503 (with `Retry-After`)
  while backend, Drush and cron keep working — the clean billing-grade
  switch. The flag lives outside the account tree, so the account owner
  cannot remove it. Reference: `docs/SUSPEND.md` (new).
- **`/root/.barracuda.cnf` now shows effective defaults** for all YES/NO
  options — no more guessing what an empty line means — and the self-heal
  never overwrites an operator-set value.
- **`codebasecheck`** gains a box-wide **Percona 8 readiness report** and a
  `--deep` contrib/schema analysis that cuts false-OK results before a
  database major upgrade.
- **`_NGINX_KTLS` opt-out lever** for the OpenSSL 3.2+ kernel-TLS
  receive-path noise seen on some kernels (`docs/NGINX-KTLS.md`, new);
  kTLS remains on by default.
- **`/etc/apt/sources.list` self-heals**: a missing or half-written file is
  regenerated crash-safely (Debian trixie aware), and a failed fetch now
  enforces the canonical mirror rather than restoring a possibly stale
  backup.
- **`staticbuild`** (new): the mirror-source build tool that assembles and
  publishes the tested Drupal/Backdrop codebases — versions derived from
  the actual build, so the catalogue below is always real.
- **Sturdier plumbing:** versioned-fetch is now content-aware (a stale
  serial marker self-heals), lock-pid ownership guards ported to
  `barracuda` and `octopus`, `websh` is single-sourced, and the
  Debian-to-Devuan `autoinit` conversion helper rides out DNS and network
  flaps with a safe re-entry gate.

## Operator Notes

This release has **no mandatory action** — no forced reboot beyond the
usual upgrade flow, and no custom values to re-pin. Two default changes
are worth a conscious decision:

- **Backdrop support is on by default.** On upgrade, a box that never set
  `_BACKDROP_SUPPORT` gets `YES` appended to `/root/.barracuda.cnf`,
  enabling Backdrop platforms, `bee` and the panel integration. Set
  `_BACKDROP_SUPPORT=NO` first if you do not want Backdrop platforms
  built.
- **Prebuilt packages are on by default on Devuan Daedalus only.** Set
  `_USE_PREBUILT_PKGS=NO` to keep compiling from source on Daedalus;
  all other OS releases are unaffected.
- Everything else new ships either safe-by-default (detectors, notices,
  reports) or strictly opt-in (ghost-cleanup moves, nightly symlink
  auto-fix, per-site allow-lists, suspend).

## Component Versions

| Component | Version |
|---|---|
| Nginx | 1.31.3 (was 1.31.2) |
| OpenSSH | 10.4p1 (was 10.3p1) |
| PHP | 8.5.8, 8.4.23, 8.3.32 (default set; 8.4 remains the default CLI/FPM), 8.2.32 available |
| Composer | 2.10.2 (was 2.8.2) |
| Drush 8 (classic) | 8.5.4 (was 8.5.3) |
| New Relic | 12.8.0.37 (was 12.7.0.36) |
| Backup stack | Python 3.14.6 + Duplicity 3.1.0 (was 3.13.9 / 3.0.6) |
| Backdrop CMS | 1.34.2 (new) |
| ImageMagick | distro-packaged (the dormant source-build path was removed) |

Unchanged since BOA-5.10.3: OpenSSL 3.5.7 LTS, cURL 8.21.0, Apache Solr
9.10.1, Valkey 9.1.0 (now also delivered as the prebuilt `boa-valkey`
package on Daedalus), Percona Server (8.4 current, 5.7 legacy), mydumper.

## Supported / Tested Drupal & Backdrop Distributions

The tested catalogue moves to the **2026-07-17 static build**:

- **Backdrop CMS 1.34.2** *(new)*
- **Drupal CMS 2.1.3** (Drupal 11.4.4)
- Commerce Kickstart 5.1.0 (11.4.4) *(major refresh)*, plus CK2 2.40 and
  CK1 2.77 for older lineages
- LocalGov 4.0.2 (11.4.4), Thunder 8.4.0 (11.4.4), farmOS 4.0.4 (11.3.14),
  OpenCulturas 3.0.3 (11.3.14)
- Vanilla cores: 6.60.1, 7.105.1, 9.5.11, 10.0.11 → 10.6.13, 11.1.10,
  11.2.14, 11.3.14, and the new **11.4.4**
- Varbase stays available as its last working 10.1.0 build (upstream's
  project template is currently broken; frozen until fixed upstream)

## Important Fixes

- **Intermittent box-wide 502s behind Cloudflare** on proxied HTTPS,
  root-caused and fixed (dead IPv6 upstream candidate in the wild-ssl
  proxy path).
- **Drupal 10/11 cached-container poisoning** after clone/deploy/install,
  fixed via patch-preserving rebuild windows (above).
- **Composer works for shell users again**: Composer 2.8.3+ switched its
  subprocess model and collided with the safe-shell wrapper; `websh` now
  executes those calls correctly, unblocking the Composer 2.10.2 update.
- **`_SMTP_RELAY_HOST` was never written to Postfix `main.cf`** — the
  outbound relay opt-in now actually configures the relay.
- **Special files can no longer break site backups**: device/special files
  are excluded from backups and all tree transfers, so a stray device
  node no longer aborts a restore or deploy.
- **Octopus bundle installs set the instance email again** (regression),
  and an empty `_PHP_CLI_VERSION` can no longer abort an Ægir install.
- **FTP log scanning** anchors on the real pure-ftpd tag and handles
  IPv6/`::ffff:` peers, so a crafted username can no longer confuse the
  FTP scanner.
- **Nightly log preparation** no longer grows a pid-file name without
  bound; the argless unlock path in the lock library is fixed; a false
  space-check failure in `autosymlink` when the static base was absent is
  fixed; Java initd disabling no longer collides on a path; GRUB rewrites
  are skipped when config is already in sync and applied when it really
  changed.

## New Documentation

New operator references in this release — all also woven into
**[docs.boa.io](https://docs.boa.io)**:

- `docs/BACKDROP.md` — Backdrop CMS operator guide (platforms, tasks,
  upgrade chain, cutover, limitations).
- `docs/AEGIR2BOA.md` — the classic-Ægir-to-BOA migration runbook.
- `docs/DDEV-BOA.md` — local development against a BOA-hosted site.
- `docs/FILES-SYMLINK.md` — native files symlinking (admin + per-site).
- `docs/PREBUILT.md` — prebuilt stack packages.
- `docs/SUSPEND.md` — instance suspend/unsuspend.
- `docs/NGINX-KTLS.md` — the kTLS opt-out lever.
- `docs/MIGRATE-PERCONA8.md` — cross-version Percona 8 migration and
  verification, plus a Percona 8 upgrade-readiness How-To.
- `docs/DRUSH-FILTER-TESTING.md` — verifying the Drush extension filter.
- `docs/USER-ADMIN-ACCESS.md` — the per-site `/user` + `/admin` allow-list.
- `docs/BUILDTESTS.md` — rebuilt around the `staticbuild` procedure.

## Upgrade Instructions

Run inside a `screen` session as root:

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts
octopus up-lts all force
boa reboot
```

For silent, logged mode (output to `/var/backups/reports/up/`, emailed on
completion — useful for cron):

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts log
octopus up-lts all force log
```

Full upgrade documentation: https://github.com/omega8cc/boa/blob/5.x-pro/docs/UPGRADE.md
Self-upgrade automation: https://github.com/omega8cc/boa/blob/5.x-pro/docs/SELFUPGRADE.md

## Links

- Documentation: https://docs.boa.io
- News & announcements: https://omega8.cc/news
- Commit history (BOA): https://github.com/omega8cc/boa/commits/5.x-dev/
- Commit history (Provision): https://github.com/omega8cc/provision/commits/5.x-dev/
- Full changelog: https://github.com/omega8cc/boa/blob/5.x-pro/CHANGELOG.txt
- License: https://github.com/omega8cc/boa/blob/5.x-pro/DUALLICENSE.md
