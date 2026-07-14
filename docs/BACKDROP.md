# Backdrop CMS support in BOA

BOA runs **Backdrop CMS** as a first-class platform: auto-built platforms
tracking the newest Backdrop release, the full Ægir site lifecycle
(install, verify, clone, backup, restore, import, delete), both CLIs
(`bee` and Drush 8), Valkey object caching with automatic database
fallback, panel-driven cron — and safe, copy-based upgrade tasks: a
**Drupal 7 → Backdrop upgrade** plus a **Drupal 6 → Drupal 7 step** as
its on-ramp, neither of which ever puts the source site in the write
path.

Backdrop support is **on by default**: the platforms, the panel module
and the CLIs arrive with the normal upgrade pair. Opting out is one
variable per layer.

## Enabling and disabling Backdrop support

The switch is `_BACKDROP_SUPPORT`, mirrored (not shared) in two control
files because two different programs act on it:

| File | Program | What it gates |
|---|---|---|
| `/root/.<user>.octopus.cnf` | Octopus | Backdrop platforms + the Ægir frontend module |
| `/root/.barracuda.cnf` | Barracuda | System tools (the `bee` CLI install) |

It defaults to `YES` in both layers, and Backdrop platforms build
whenever the platform list includes the `BDR` symbol (or is `ALL`, the
shipped default) — so a stock instance gets Backdrop with the normal
upgrade pair:

```
barracuda up-{dev|lts|pro} system
octopus up-{dev|lts|pro} <user>
```

To opt an instance out, set `_BACKDROP_SUPPORT=NO` in its Octopus
config (and mirror it in `/root/.barracuda.cnf` to skip the system
tools as well); the persisted value always wins over the shipped
default. Migration note for boxes upgraded while the gate still
defaulted to `NO`: that value is persisted in their control files, so
flip it to `YES` (or delete the line) to adopt the new default.

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

Install, Verify, Clone, Migrate, Backup, Restore, Import and Delete work
from the Ægir frontend with the same semantics as Drupal sites. Notes:

- **Install** runs through Backdrop's own installer (driven by `bee`),
  then Ægir verifies and serves the site as usual.
- **Clone** gives the copy its own database, its own config directories
  and its own files store; cloned and imported sites land with cron and
  Encryption (LE) disabled on purpose, so a copy never emails users or
  runs background processes that confuse the live site.
- **Migrate** moves a Backdrop site onto another Backdrop platform —
  keeping its domain (the usual reason: relocating onto a freshly built
  platform tracking a newer Backdrop release) or renaming it to a new
  domain. The Migrate form lists only Backdrop platforms for a Backdrop
  site (and only Drupal platforms for a Drupal site); the backend
  refuses a cross-lineage pair outright. As with Drupal, the source is
  backed up first, deployed onto the target into a fresh copy database,
  verified, and only then is the old copy retired; a rename disables
  Encryption for the new name (re-enable it deliberately afterwards).
  A Drupal 7 site does **not** migrate to Backdrop — that is the
  dedicated upgrade task below.
- **Cutover (take over a domain)** makes a Backdrop site answer at a
  domain currently held by another site — typically the original domain
  of the site it was upgraded from. The holder is re-checked when the
  task runs, backed up in full and then deleted; the Backdrop site is
  then renamed to the freed domain through the same machinery as
  Migrate. If nothing holds the domain (say, after an earlier attempt
  stopped between the two steps), the task degrades to a plain rename —
  that is also the re-run recovery path. Encryption ends up disabled
  for the new name (certificates are name-bound); re-enable it
  deliberately afterwards. Custom aliases of the retired site are not
  carried over, and the domain is unserved while the rename completes —
  minutes that scale with the site's size.

## Upgrading a Drupal 7 site to Backdrop

The **Upgrade to Backdrop** task on a Drupal 7 site node is a
copy-based upgrade: it converts a COPY of the site at a NEW domain on a
Backdrop platform. The original Drupal 7 site — its database, its files,
its vhost — is never in the write path and keeps serving throughout.
You test the copy, then cut over deliberately (the Cutover task, a DNS
repoint, or a later rename).
Every failure mode ends with "discard the copy"; the source is intact by
construction.

### Prerequisites

- The source site runs **Drupal 7** with core fully updated (`system`
  schema 7078 or newer: Backdrop's documented floor is 7069, but between
  7069 and 7077 Backdrop's own system updates would be silently skipped
  during the conversion, so the task enforces the honest floor; any
  Drupal 7 core from 7.28 on clears it. The check runs before anything
  is created).
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
- Cut over when you are satisfied: run **Cutover (take over a domain)**
  on the copy's node and give it the original domain — the old site is
  backed up and retired, and the copy takes its place at the original
  address (re-enable Encryption for it afterwards). Prefer a manual
  switch instead? Repointing DNS, or keeping both sites side by side,
  works for as long as you like.

## Upgrading a Drupal 6 (Pressflow) site — the two-step chain

Backdrop upgrades from Drupal 7 only (its own rule, enforced in its
code), so a Drupal 6 site takes two steps — and both are panel tasks:

1. **Upgrade to Drupal 7 (Backdrop step 1)** on the Drupal 6 site node
   converts a copy of the site — the core schema AND the CCK field
   data — at a NEW domain on a Drupal 7 platform. The Drupal 6 original
   is never in the write path and keeps serving throughout.
2. **Upgrade to Backdrop** on that Drupal 7 copy is the standard task
   above, unchanged.

The intermediate Drupal 7 site is a real, inspectable site with its own
control-panel node: compare it against the source at leisure before
taking step 2, and keep it as a fallback landing for as long as you
like.

### Prerequisites (step 1)

- A **PHP 7.4-pinned instance**: the Drupal 6 code, the pinned contrib
  kit and the field-data migration all run under the instance CLI, and
  7.4 is the supported interpreter for this legacy chain. Set `7.4` in
  the instance's `static/control/cli.info` and `fpm.info` and run the
  Octopus upgrade once. A 7.4 instance is a **dedicated legacy
  instance** — Drupal 8+ platforms on the same instance would break
  (modern Drupal 10/11 needs PHP 8.1+), so keep modern sites elsewhere.
- **Drupal 6 and Drupal 7 platforms** on the instance: include the
  `DL6` and `DL7` symbols in the platform list (see `PLATFORMS.md`).
- The **pinned D6→D7 contrib kit**, staged automatically from the BOA
  mirror into `/data/all/000/d6d7kit` during every Octopus upgrade run
  while Backdrop support is enabled. If the kit is missing, the task
  refuses to start and tells you to run the Octopus upgrade — it never
  downloads anything at task time.
- A **new, unused domain name** for the copy.

### What step 1 does

1. Validates everything fail-closed first: Drupal 6 source (a 6xxx
   `system` schema), a Drupal 7 target platform, the PHP 7.4 instance,
   the staged kit, a free domain. The validation log prints a
   **kit-coverage report**: which of the site's modules the kit
   replaces with their Drupal 7 ports, which the core upgrade handles
   natively, and which have no mapping — those are parked disabled on
   the copy with their data tables kept.
2. Takes a fresh backup of the live source (recorded under the source
   site's backups as "Pre-upgrade backup").
3. Deploys that backup at the new domain into a fresh copy database.
   The copied Drupal 6 modules are moved aside first (into
   `sites/<domain>/modules-d6d7-quarantine` — kept, never deleted;
   left in place they would fatal the conversion against the
   platform's namesake modules), then Drupal 7's own staged upgrade
   machinery converts the copy database.
4. Gives the copy its own files/private store, stages from the kit
   exactly the Drupal 7 module ports the source actually used, enables
   them (plus core file and image), and runs their schema updates.
5. Migrates the CCK field data with content_migrate — **a hard gate**:
   if any field would be left without its module, the task aborts and
   the copy is discarded. There is deliberately no way to skip a
   field, because skipped CCK data strands silently — the later
   Backdrop upgrade would complete green with the content simply
   absent.
6. Verifies the copy and creates its control-panel node, dark exactly
   like step 2's product: enabled and serving, with cron and
   Encryption off until you flip them deliberately.

### Profiles (step 1)

Nearly every Drupal 6 site uses the stock `default` profile; the
Drupal 7 upgrade renames it to `standard`, and the task records the
same automatically. A custom Drupal 6 profile must exist under the same
name on the Drupal 7 platform (pass it explicitly), or the task refuses
in validation.

### If step 1 fails

Same contract as the Backdrop upgrade: a validation failure creates
nothing; a later failure leaves the source untouched and a disposable
copy — run Delete on the copy's node (or alias) and re-run the task.

## Limitations and non-goals

- **The Drupal 7 → Backdrop task still refuses Drupal 6 sources** — by
  design, matching Backdrop's own rule. The Drupal 6 step is its own
  task (above); run the chain in order.
- **Cross-lineage Migrate is refused**: a Migrate task never moves a
  Drupal site onto a Backdrop platform or the reverse (use the upgrade
  tasks for that). Backdrop → Backdrop and Drupal → Drupal both work.
- **Collation note for imported estates**: BOA-native Drupal 7 databases
  are already utf8mb4 and convert cleanly. A Drupal 7 dump imported from
  an old external server may still be 3-byte utf8 — and the Drupal 7
  copy produced by the Drupal 6 step carries 3-byte tables too (that
  was Drupal 6's era standard, whatever the server) — while on a
  Percona 8.4 box new tables default to utf8mb4, so such sites end up
  mixed and can surface illegal-collation errors on JOIN-heavy pages.
  The dedicated **Convert database to utf8mb4** site task (Aegir
  Extras / hosting_tasks_extra, works on any Drupal 7 site) fixes this:
  probe first (an already-converted database completes as an honest
  no-op), then backup, convert every utf8 table and text column in a
  maintenance window, verify against information_schema, and back
  online. Run it on a clone first, then on the real site; a converted
  source then upgrades to Backdrop cleanly. Backdrop estates imported
  from elsewhere with 3-byte tables have no converter (the extension is
  Drupal-7-only by construction) — a documented gap, expected to stay
  rare.

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

The Drupal 6 chain is proven the same way (2026-07): the full two-step
run from the control panel — a Pressflow 6 fixture through step 1 to a
serving Drupal 7 copy (content fingerprint identical, every CCK field
migrated, quarantine and kit staging observed) and through the
unchanged step 2 to a serving Backdrop site; the field-data migration
exercised across multiple batch passes; the wrong-source refusal
(a Drupal 7 site offered to step 1) creating nothing; and the kit
fetched from the public mirror by the Octopus upgrade run.

A Backdrop **Restore** round-trip is drilled too (2026-07): backup and
restore tasks on an upgraded copy, content and serving verified intact
afterwards. So is **enabling Encryption** on a copy: the enable → key →
verify → Let's Encrypt issuance chain produced a live LE certificate on
a cloned Backdrop copy at a real domain (the panel deliberately skips
issuance for the hosting service's own reserved names, so test-estate
domains show the skip by design — client domains issue).

**Migrate** is drilled both ways (2026-07): a same-domain move of a
Backdrop site onto another Backdrop platform (settings, database and
content reconciled on the target, the source retired with no orphan)
and a rename onto a new domain (the new domain serves the content, the
old domain is removed); both guards — a cross-lineage pair and a no-op
self-migrate — refuse in validation before anything is touched.

**Cutover** is drilled end-to-end (2026-07) on a freshly minted
D6 → D7 → Backdrop pair: the Backdrop copy took over its D7
intermediate's domain in one task (the intermediate backed up and
retired, the copy renamed, serving the content at the original domain,
Encryption off with the re-enable reminder in the task log), the
follow-up verify came back green, and the claim-mode re-run leg renamed
the same site onto a free domain with no delete step. Refusals drilled:
taking over the site's own domain, taking over the hosting front-end,
and running cutover on a Drupal-lineage site (backend validation).

**The default-on posture** is drilled on a fresh install (2026-07): a
stock one-command BOA install with zero Backdrop configuration landed
`_BACKDROP_SUPPORT=YES` in both control files, staged bee and the
D6 → D7 kit from the mirror, enabled the Backdrop frontend module with
all its task permissions (including Cutover), and — once the operator
listed BDR in the standard platforms control file — built and verified
all three Backdrop platforms. The opt-out is drilled on the same box:
with `_BACKDROP_SUPPORT=NO` an upgrade run stages nothing new (the
removed kit stays absent) while everything already provisioned keeps
serving — opting out disables provisioning surfaces, it never tears
down existing sites or platforms.

**The utf8mb4 conversion task** is drilled end-to-end (2026-07) on a
naturally mixed fixture (a Drupal 7 copy minted by the Drupal 6 step:
53 tables and 170 text columns still 3-byte utf8 next to fresh utf8mb4
tables): the probe reported the exact counts, the task took a fresh
backup, converted in a maintenance window and verified the database
fully utf8mb4 against information_schema (independently confirmed),
with the site serving and JOIN-heavy listings clean afterwards — and a
Backdrop upgrade of the converted site produced a serving copy with
zero 3-byte tables, closing the illegal-mix scenario for good. The
drill also hit a real transient ALTER deadlock against a live request:
the task failed honestly (backup named in the log, site brought back
online) and the re-run converted the remainder — which is why the task
now retries transient failures internally. Also drilled: the honest
no-op on a BOA-native site (green, no backup, no maintenance window)
and the refusals on a Backdrop site and a Drupal 6 site (validation
refuses before any side effect).

Out of scope by decision: placing the copy database on a different
database server than the source.
