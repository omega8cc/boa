# Backdrop CMS support in BOA

BOA runs **Backdrop CMS** as a first-class platform: auto-built platforms
tracking the newest Backdrop release, the full Ægir site lifecycle
(install, verify, clone, backup, restore, import, delete), both CLIs
(`bee` and Drush 8), Valkey object caching with automatic database
fallback, panel-driven cron — and a safe, copy-based **Drupal 7 →
Backdrop upgrade task** whose source site is never in the write path.

Backdrop support ships **dark** and is enabled per Octopus instance.
Nothing changes on instances that do not opt in.

## Enabling Backdrop support

The gate is `_BACKDROP_SUPPORT`, mirrored (not shared) in two control
files because two different programs act on it:

| File | Program | What it gates |
|---|---|---|
| `/root/.<user>.octopus.cnf` | Octopus | Backdrop platforms + the Ægir frontend module |
| `/root/.barracuda.cnf` | Barracuda | System tools (the `bee` CLI install) |

Set in the Octopus config:

```
_BACKDROP_SUPPORT=YES
_PLATFORMS_LIST=ALL   # or include the BDR symbol explicitly
```

and mirror `_BACKDROP_SUPPORT=YES` in `/root/.barracuda.cnf`, then run
the normal upgrade pair:

```
barracuda up-{dev|lts|pro} system
octopus up-{dev|lts|pro} <user>
```

After the run the instance has:

- **Three Backdrop platforms** (dev/stage/prod trees), auto-built from
  the version-less `backdrop.tar.gz` on the BOA mirror and registered in
  Ægir. Backdrop platforms always track the newest release — there is no
  per-version pin to maintain (see `PLATFORMS.md`).
- **The `hosting_backdrop` frontend module** enabled on the hostmaster
  (the `backdropcms` hosting feature). Enabling it queues a one-time
  verify of every existing platform so each platform's Backdrop marker
  is fresh — on a box that already had Backdrop platforms before the
  module, that sweep is what makes them visible as upgrade targets. It
  also grants the `create backdrop_upgrade task` permission to the
  `aegir administrator` role.
- **`bee`**, the native Backdrop CLI, at `/opt/local/bin/bee`, plus the
  backdrop-drush-extension wired into the backend Drush 8.

## How a Backdrop site differs from a Drupal site (operator view)

Backdrop is a Drupal-7-lineage fork, and BOA manages it through the same
Ægir tasks — but four mechanics differ and all four are handled for you:

- **Configuration is file-based JSON**, written at runtime by the web
  process into `sites/<domain>/private/config/{active,staging}`. BOA
  pins the config directories there so they ride every site backup, keeps
  them writable (Backdrop requires it permanently, unlike Drupal 8+
  staging), and denies them at the Nginx level.
- **settings.php uses the scalar `$database` array**, not Drupal's
  nested `$databases` array. Ægir renders the correct template
  automatically.
- **Cron is key-authenticated**: the key lives in Backdrop's `{state}`
  store and the endpoint is `core/cron.php?cron_key=...`. Ægir owns cron
  scheduling exactly as for Drupal sites; Backdrop's own visit-triggered
  cron is switched off via the global include so runs never double up.
- **Object cache**: every Backdrop platform ships the Backdrop-native
  Valkey/Redis cache module baked in. The BOA global include
  (`global-bd.inc`) wires each site to Valkey when it is available and
  falls back to Backdrop's database cache — with the shared backoff flag,
  so a stopped Valkey is not re-probed on every request.

## Command line: bee and Drush

Backdrop sites answer to **both** CLIs:

- `bee` — the native Backdrop CLI. The BOA launcher picks a modern PHP
  automatically (Backdrop's own floor is PHP 7.1; `bee` never runs under
  PHP 5.6). Backend identities (root, `aegir`, `o1`-style Octopus users)
  have the full verb set. Client shell identities (`o1.ftp`-style) get
  the everyday verbs, while destructive ones (database import and drop,
  fresh site install, `eval`-class verbs) are refused — restores go
  through the Ægir control panel. `bee db-export` stays available to
  clients.
- `drush` (Drush 8) — the backdrop-drush-extension teaches Drush 8 to
  bootstrap Backdrop, so per-site aliases, `status`, `cc all`,
  `sql-dump` and friends work as on Drupal 7. All Ægir backend tasks run
  through this path.

## Site lifecycle

Install, Verify, Clone, Backup, Restore, Import and Delete work from the
Ægir frontend with the same semantics as Drupal sites. Notes:

- **Install** runs through Backdrop's own installer (driven by `bee`),
  then Ægir verifies and serves the site as usual.
- **Clone** gives the copy its own database, its own config directories
  and its own files store; cloned and imported sites land with cron and
  Encryption (LE) disabled on purpose, so a copy never emails users or
  runs background processes that confuse the live site.
- **Migrate is deliberately refused** whenever the source or the target
  is a Backdrop platform. The stock Ægir migrate machinery is
  Drupal-version based and was never safe cross-lineage; until a
  Backdrop-native migrate ships, move Backdrop sites with Clone (and
  Delete the original after cutover), and upgrade Drupal 7 sites with
  the dedicated task below — never with Migrate.

## Upgrading a Drupal 7 site to Backdrop

The **Upgrade to Backdrop** task on a Drupal 7 site node is a
copy-based upgrade: it converts a COPY of the site at a NEW domain on a
Backdrop platform. The original Drupal 7 site — its database, its files,
its vhost — is never in the write path and keeps serving throughout.
You test the copy, then cut over deliberately (DNS or a later rename).
Every failure mode ends with "discard the copy"; the source is intact by
construction.

### Prerequisites

- The source site runs **Drupal 7** with core fully updated (`system`
  schema 7069 or newer — that is Backdrop's hard requirement; the task
  checks and refuses stale cores before creating anything).
- A **verified Backdrop platform** on the same instance (the task form
  lists only those).
- A **new, unused domain name** for the copy.

### What the task does

1. Validates everything fail-closed first: Drupal 7 source, schema
   floor, verified Backdrop target, free domain, mapped install profile.
   The validation log also prints a per-module **UPGRADE/MAP report**
   (see below) before anything is created.
2. Takes a fresh backup of the live source (recorded under the source
   site's backups as "Pre-upgrade backup").
3. Deploys that backup onto the Backdrop platform at the new domain,
   into a **fresh copy database** with fresh credentials.
4. Gives the copy its own files/private store (no sharing with the
   source), and quarantines site-local Drupal 7 modules that Backdrop
   absorbed into core (moved aside into
   `sites/<domain>/modules-preupgrade-quarantine`, never deleted).
5. Runs Backdrop's own upgrade machinery against the copy database in
   staged, separate processes — the same sequence Backdrop's update.php
   performs, exit-code checked at every phase.
6. Verifies the new site and creates its control-panel node. The copy
   lands **enabled and serving**, with **cron and Encryption switched
   off on purpose** — review it first, then enable cron, and request or
   enable a certificate for the new name deliberately.

### The module map (UPGRADE/MAP report)

Backdrop absorbed many popular Drupal 7 modules into core (views, date,
entity, link, redirect, ckeditor, …) and supersedes others
(admin_menu → core admin_bar). The task ships a data map and prints one
line per enabled module in the task log during validation:

- **absorbed / superseded** — handled by core; the old copy of the
  module is quarantined so it cannot shadow core.
- **contrib port exists** — keep it only if the Backdrop port is present
  on the target platform; otherwise the conversion disables it.
- **no equivalent / unknown** — the conversion disables it; its data
  tables are kept, nothing is dropped.

The report is advisory by design: it never blocks the upgrade, and
because validation runs before any copying, a report you don't like
costs nothing — the task has created nothing yet.

### Profiles

Standard maps to standard and minimal to minimal. A custom Drupal 7
install profile that does not exist on the Backdrop platform falls back
to `standard` with a logged warning — the conversion never re-runs an
install profile, so this only affects panel bookkeeping.

### If something fails

- **Validation failure** — nothing was created; fix the reported cause
  and re-run.
- **Conversion or verify failure** — the source is untouched; the copy
  is disposable. Run Delete on the copy's node (or, if no node was
  created yet, on the copy alias) and re-run the task; a fresh attempt
  is cheap because the source backup is re-taken each run.

### After the upgrade

- Compare the copy against the source (content counts, key pages, image
  styles, forms). The conversion carries nodes, comments, users, terms,
  files, URL aliases, custom fields and menu links; site name and
  settings move into Backdrop's config files.
- Enable cron on the copy's node when you are satisfied.
- Enable Encryption (LE) for the new domain deliberately.
- Cut over manually: repoint DNS, or keep both running side by side as
  long as you need. Same-URI cutover automation is intentionally out of
  scope for now — coexistence plus an operator-controlled switch is the
  supported shape.

## Limitations and non-goals

- **Drupal 6 sources are refused.** Upgrade Drupal 6 → Drupal 7 first
  (BOA's normal D6→D7 path), fully update core, then run the Backdrop
  upgrade. This two-step is the official Backdrop position, not a BOA
  shortcut.
- **Backdrop → Backdrop Migrate** is not available yet (see above);
  stock Migrate fails closed rather than risking the source.
- **Collation note for imported estates**: BOA-native Drupal 7 databases
  are already utf8mb4 and convert cleanly. A Drupal 7 dump imported from
  an old external server may still be utf8; on a Percona 8.4 box the
  copy database defaults to utf8mb4, and a mixed pair can surface
  illegal-collation errors on JOIN-heavy pages after conversion. If you
  hit those, convert the source dump's tables to utf8mb4 first and
  re-run the upgrade.

## Validation status

Proven end-to-end on disposable VMs (2026-07): platform auto-build via
Octopus (dev/stage/prod, zero manual steps), the site lifecycle
(install, triple verify, clone, backup, import, delete), web cron
accepting the valid key and returning 403 on bad keys, Valkey caching
with the database fallback exercised both ways, `bee` identity
restrictions, and the Drupal 7 upgrade both from the backend command
and from the control panel task — including the content fingerprint of
a fixture site matching exactly after conversion, the stale-schema
refusal creating nothing, and the marker sweep healing platforms after
a module disable/enable cycle.

Not yet drilled, stated honestly:

- A Backdrop **Restore** round-trip. It shares the deploy-from-backup
  machinery the proven clone path exercises, but it has not been
  separately drilled.

- Enabling Encryption/LE on an upgraded copy afterwards (it is the
  standard per-site LE flow, but it has not been exercised specifically
  on an upgraded copy).
- Placing the copy database on a different database server than the
  source (the task form offers it on multi-DB instances; single-server
  placement is what has been drilled).
- Conversions of imported legacy utf8 estates (see the collation note).
