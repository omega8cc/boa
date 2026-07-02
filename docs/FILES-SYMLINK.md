# Sites Files Directories Symlinking (native, self-healing)

BOA stores each site's writable `files` and `private` directories outside the
platform docroot, inside the owning Octopus account's **static store**, and links
them back into the site with symlinks:

```
/data/disk/<account>/.../sites/<url>/files    ->  /data/disk/<account>/static/files/<url>/files
/data/disk/<account>/.../sites/<url>/private  ->  /data/disk/<account>/static/files/<url>/private
```

Keeping the real data in `static/files/<url>/` (and only a symlink in the
platform) means a site's uploads survive platform rebuilds and code redeploys
untouched, can live on attached/extra storage, and are cheap to back up and
migrate. This is now **native**: new sites are symlinked as part of installation,
clones get their own separate copy, and a set of tools keep the layout correct and
report stray data — with optional, opt-in automation.

This is the server-admin reference. For the per-site user how-to see
[FILES-SYMLINK-USER.md](FILES-SYMLINK-USER.md).

> The account-level `static/files` directory may itself be a real directory or a
> symlink to attached storage; that lower layer is handled separately during
> migration (see [MIGRATE-XOCT.md](MIGRATE-XOCT.md) → *Static Files Symlink
> Handling*). This document is about the **per-site** `sites/<url>/{files,private}`
> links into that store.

## What happens, and when

| Event | Behaviour | Default |
|-------|-----------|---------|
| **New site** install | After the install creates the real `files`/`private` dirs, they are **moved into the static store and symlinked** (delegated to the root tool). | **on** (kill-switchable) |
| **Clone** a site | The new site gets its **own separate copy** of the files in its own store — never a link into the source site's data — when disk space allows; otherwise a warning is logged and the clone still succeeds. | **on** (kill-switchable) |
| **Migrate / rename** a site | Same as clone: after the target verify the migrated/renamed site is re-homed into its **own** store and re-symlinked; the old-name store becomes an orphan (archived on the next nightly sweep). | **on** (kill-switchable) |
| **Reused site name** | When an install/clone reuses a name whose store was left behind by an earlier site of the same name, the stale store is **archived aside** (to `static/files/.archived/…`) and the new site converts cleanly — no skip, no manual step. | **on** |
| **Nightly auto-fix** | Convert any not-yet-symlinked site and self-heal partly-symlinked ones, box-wide. | **on** on omega8.cc-hosted (`.aegir.cc`); **opt-in** otherwise |
| **Orphaned store** (site deleted, name not reused) | The nightly auto-fix **archives** the leftover store aside into `static/files/.archived/…` (never deletes; a *disabled* site is left in place); the opt-in report additionally emails any found. | archive with auto-fix; report opt-in |
| **Backups relocation** (nightly) | On an account whose `static/files` is a **separate filesystem**, move `backups`/`backup-exports` onto it (via symlinks) so large backups can't fill the root partition. | **on** where applicable (kill-switchable) |
| **Manual run** | Convert/report on demand with the tools below. | — |

Native creation applies to Octopus-hosted accounts (`/data/disk/<account>`).
Existing sites whose `files`/`private` are still **real directories** are **not**
auto-converted during a normal install or verify (that would move data at an
unexpected time); convert them with the opt-in nightly auto-fix or a manual run.

## Privilege model

The per-account static store (`<account>/static/files`) is **root-managed** (the
backup subsystem owns it), so the unprivileged Octopus account user that runs a
Provision install/clone task cannot create or move data inside it. The
move-and-symlink therefore always runs **as root**, via a hardened NOPASSWD sudo
wrapper:

- Provision (install, clone and migrate/rename hooks) calls
  `sudo /usr/local/bin/fix-drupal-site-symlinks.sh --site=<url> …`.
- The wrapper validates its arguments and invokes **only** the narrow single-site
  `autosymlink` apply — it cannot reach the global batch/live modes.
- `autosymlink` (root) **moves** the existing `files`/`private` into the store and
  replaces them with symlinks. It never creates empty store dirs from the
  unprivileged side.

On a fresh install the wrapper is called from `post_provision_install`, before the
site's first verify writes the nginx vhost, so Provision passes `--account`
explicitly (the narrow mode then trusts the Drush alias alone). On a clone or a
migrate/rename it is called after the target verify, so the account auto-resolves
from the vhost+alias pair.

## The tools

These run as root. `autosymlink`, `updatesymlinks`, and `symlinkinfo` live in
`/opt/local/bin`; the privileged Provision entry point below is in `/usr/local/bin`.

### `autosymlink` — the worker

Converts a site's `files`/`private` real directories into symlinks into the
store, detects and breaks *accidental* cross-site sharing, and reports orphans.

```bash
autosymlink                 # DRY (default): show what would change, change nothing
autosymlink report          # read-only report, including orphaned store entries
autosymlink live            # apply, with a per-site confirmation prompt
autosymlink batch           # apply to all sites, no prompt (needs a prior clean DRY run)
autosymlink --batch-if-clean # DRY, and if clean, BATCH — cron-safe, one shot
```

Narrow single-site mode (used by the Provision install/clone hooks; also handy for
one-off fixes):

```bash
autosymlink --site example.com [--account o1] --apply [--force-unshare]
```

- `--site` / `--account` scope the run to one site. With an explicit `--account`
  only the Drush alias is required (the vhost may not exist yet at install time);
  when `--account` is omitted the account is auto-resolved from the vhost+alias
  pair.
- `--apply` performs the change; without it the narrow run is a read-only DRY for
  that one site. The narrow apply runs its own per-site clean dry-run first and
  only proceeds if it is clean.
- `--force-unshare` breaks an inherited cross-site/cross-account link even if a
  file-sharing control file exists — used by cloning so a fresh clone (which never
  opted into sharing) always gets its own copy.

The narrow mode never touches the global batch state and **defers** while the
nightly maintenance pause is active, so it never races the batch sweep. It also
sets each new symlink's owner:group to match its store target (so the link is not
left `root`-owned).

### `updatesymlinks` — the scheduler / orchestrator

Wraps `autosymlink` with Aegir-queue pausing (the self-healing
`/run/boa_queue_stop.pid`), lock and load guards, and email. Driven by two opt-in
`.barracuda.cnf` variables (see Configuration):

```bash
updatesymlinks --auto-fix       # nightly: batch-if-clean apply + email on changes
updatesymlinks --orphan-report  # daily: read-only orphan report, email only if any found
updatesymlinks                  # legacy: full apply + report, for manual use
updatesymlinks --auto-fix --debug   # explain on stdout WHY a run skips/does nothing
```

When either opt-in is enabled a **single** cron line runs `updatesymlinks --auto-fix`
hourly at `:47` through the night (`22:00`–`05:59`), clear of the 6-hourly duplicity
backups (`:00`) and the nightly backup/owl/upgrade cluster. It self-skips any hour a
heavy task is running (backup, upgrade, provision, high load) and retries the next
hour; the first un-blocked hour does the work, records a per-night stamp
(`/var/log/boa/autosymlink.nightok.stamp`), and every later hour that night is a cheap
no-op. The one line serves both opt-ins: with `_AUTOSYMLINK_NIGHTLY=YES` it runs the
full pause + two-step apply (which folds the orphan report in); with only
`_ORPHAN_FILES_REPORT=YES` it runs the read-only orphan report alone (no pause). The
cron line is always present; it self-exits unless at least one variable is set, so
enabling or disabling is purely a `.barracuda.cnf` change with no cron edit.
(`--orphan-report` remains a manual read-only sub-mode.)

Because every early exit is otherwise silent, add **`--debug`** (or `-d`, any
position) to have it print on stdout *why* a run does nothing — e.g. the opt-ins
are off, the night is already stamped done, a heavy task is running (and which), or
that it ran and simply found nothing to convert. It changes no behaviour; without
the flag the run is silent as before.

```bash
updatesymlinks --auto-fix --debug
#   updatesymlinks[debug]: not acting — both opt-ins are off (…); enable one in /root/.barracuda.cnf
#   updatesymlinks[debug]: not acting — already completed for this night (stamp …); remove it to force a re-run
#   updatesymlinks[debug]: not acting — a heavy task is running, retry next hour: duplicity(1)
```

### `fix-drupal-site-symlinks.sh` — the privileged entry point

Provision runs unprivileged, so the install/clone tasks cannot call `autosymlink`
(root) directly. This hardened `sudo`-NOPASSWD wrapper (in `/usr/local/bin`,
alongside the `fix-drupal-*.sh` family) validates its arguments and forwards
**only** the narrow single-site apply — it cannot reach the global batch/live
modes:

```bash
sudo /usr/local/bin/fix-drupal-site-symlinks.sh --site=example.com [--account=o1] [--force-unshare]
```

### `symlinkinfo` — query a site's history (read-only)

Answers, for one or more sites, *was it symlinked and when, is its store archived
(and where), and is it active/disabled/deleted right now* — from the autosymlink
logs plus the live filesystem. It changes nothing.

```bash
symlinkinfo bar.tkm.cc                    # one site
symlinkinfo foo.tkm.cc clone.foo.tkm.cc   # several
symlinkinfo --logs-only <site>            # skip the filesystem scan
symlinkinfo --fs-only <site>              # skip the log parse
```

For each site it reports:

- **Symlinked** — each `files`/`private` conversion, with timestamp and store target.
- **State NOW** — `active` (alias + real-docroot vhost), **`disabled`** (alias +
  placeholder vhost — files kept live, never archived), `deleted` (neither alias nor
  vhost — an orphan), or `partial` (only one survives).
- **Store NOW** — the current store, and whether the in-site path is a live symlink.
- **Archived** — each archive event (reuse vs deleted-site orphan), when, and to
  which `.archived/<stamp>/…` path — plus the archived copies present **on disk right
  now** (with size), so you can find or prune them if not yet purged.

It reads `/var/log/boa/autosymlink.log*` and `autosymlink.verbose.archive.log*`
(including rotated `.gz`) plus `/data/disk/*/static/files[/.archived]`. The site is
matched as a whole path token, so `foo.tkm.cc` never pulls in `clone.foo.tkm.cc`.

## Configuration

### `.barracuda.cnf` variables

| Variable | Default | Effect |
|----------|---------|--------|
| `_AUTOSYMLINK_NIGHTLY` | `NO` | `YES` enables the nightly global auto-fix (pause + two-step, retried hourly at night until it lands, once per night; folds in the orphan report). **Forced to `YES` automatically on omega8.cc-hosted (`.aegir.cc`) systems** — see *Default by system class* below. |
| `_ORPHAN_FILES_REPORT` | `NO` | `YES` enables the nightly read-only orphan email report (served by the same hourly-night schedule). **Forced to `YES` automatically on omega8.cc-hosted (`.aegir.cc`) systems** — see *Default by system class* below. |
| `_AUTOSYMLINK_PAUSE_GRACE` | `240` | Seconds the queue stays paused (grace) before draining and applying — the 3–5 min window that lets an in-flight task finish. |
| `_MY_EMAIL` | (your address) | Recipient for the orphan report and auto-fix notices. |

Native creation and clone handling never need these toggles; they only govern the
nightly automation. Already-installed boxes whose `/root/.barracuda.cnf` predates
these lines resolve exactly as below.

### Default by system class

The two nightly toggles (`_AUTOSYMLINK_NIGHTLY`, `_ORPHAN_FILES_REPORT`) are resolved
by **system type**, so the nightly automation is deliberately on for one class of BOA
host and off for the others:

- **omega8.cc-hosted** — the system hostname ends in `.aegir.cc`. Both toggles are
  **forced on automatically at run time**, overriding whatever `/root/.barracuda.cnf`
  says. Nothing to set: the hosted fleet always runs the nightly auto-fix and orphan
  report. Because the override is evaluated on every run, it also enables already-installed
  hosted boxes without editing their cnf.
- **Self-hosted** — neither an `.aegir.cc` hostname nor a `/root/.host8.cnf` marker.
  **Off by default, opt-in.** Enable them in `/root/.barracuda.cnf` if and when you want
  the nightly automation.
- **Remotely managed by omega8.cc** — carries `/root/.host8.cnf` but the hostname is
  **not** `.aegir.cc`. **Not auto-enabled.** These are turned on **individually**,
  coordinated per box against its available disk/IO resources — never blanket-enabled the
  way the hosted fleet is.

The switch keys on the hostname **only** (`.aegir.cc`), never on `/root/.host8.cnf` — by
design, so remotely-managed boxes that carry `.host8.cnf` are **not** swept into the
automatic default and stay individually coordinated.

### Archived-store accumulation alert

Stale stores archived on name reuse (see *Orphan / ghost detection and
stale-store archiving*) accumulate under `static/files/.archived/`. The daily
report emails a `[REPORT] ORPHAN` alert once an account's archived pile reaches a
size threshold — **1 GiB** by default. Override it (in **KB**) box-wide:

```bash
# Alert when an account's static/files/.archived total reaches 5 GiB:
echo 5242880 > /data/conf/native_files_archive_alert_kb.cnf
```

Remove the file to restore the 1 GiB default. This controls only the *alert*; it
never moves or deletes anything.

### Disabling deleted-site auto-archiving

The nightly auto-fix archives deleted-site orphan stores into `.archived/` (see
*Orphan / ghost detection and stale-store archiving*). To turn that off and go back
to **report-only** for orphans — archiving of a *reused* name on install/clone is
unaffected — create:

```bash
touch /data/conf/disable_orphan_store_archiving.cnf
```

Remove the file to re-enable. Either way it never deletes anything.

### Disabling native symlinking (kill-switch)

Native symlinking of new sites is on by default. To turn it off without a code
change, create either control file:

```bash
# Box-wide (all accounts on this host):
touch /data/conf/disable_native_files_symlink.cnf

# Per-account (one Octopus account only):
touch /data/disk/<account>/static/control/no_native_files_symlink.info
```

When present, new sites get plain real `files`/`private` directories as before,
and the clone task leaves the cloned files as-is. Remove the file to re-enable.

### Relocating backups off the root partition

On an account whose `static/files` is a separate filesystem, the nightly
maintenance moves that account's `backups`/`backup-exports` onto it (as symlinks)
so large backups can't fill the root partition — see *Backups on the static
filesystem*. On by default where applicable; disable without a code change:

```bash
# Box-wide (all accounts on this host):
touch /data/conf/disable_backups_on_static_fs.cnf

# Per-account (one Octopus account only):
touch /data/disk/<account>/static/control/no_backups_on_static_fs.info
```

### File sharing between sites (opt-in)

Two sites can deliberately **share** one files store (e.g. a staging copy that
must read the live site's uploads). Mark the intent with a control file in the
account's static store:

```bash
touch /data/disk/<account>/static/control/share.files.<site>.info
```

While that file exists, the tools treat a cross-site symlink for `<site>` as
**intentional** and leave it untouched instead of breaking it into a separate
copy. Cloning is the one exception: a clone always gets its own copy
(`--force-unshare`), because the new site name never opted into the share.

## Cloning behaviour in detail

A clone is built from a backup of the source site. BOA backups preserve symlinks
by default, so a freshly deployed clone initially points its `files` link at the
**source** site's store. After the clone's verify, the clone task runs the narrow
`autosymlink --force-unshare` for the new site, which:

1. copies the source's files into the **new** site's own store, and
2. repoints the new site's symlink at its own copy.

This is **warn-not-fail**: if disk space is short, the tool is missing, or the
copy cannot complete, the step logs a warning (and a loud `[ALERT]` if the new
site may still be sharing the source's data) and **the clone still succeeds**.
Such a clone is left usable; resolve it later with a manual
`fix-drupal-site-symlinks.sh --site=<clone> --force-unshare` run once space is
available.

If the clone reuses a name whose store was left behind by an earlier site of the
same name, that stale store is archived aside first (see *Orphan / ghost detection
and stale-store archiving*), so the clone never collides with it.

**Migrate / rename** behaves the same. A migrate (used for renaming, e.g. deploy
dev/staging to live) deploys from a backup and then, right after the target
verify, runs the narrow `autosymlink --force-unshare` for the migrated/renamed
site — re-homing its `files`/`private` into its **own** store and repointing the
symlinks, and archiving any pre-existing store at the target name aside first.
The old-name store is left as an orphan — reported, and archived into `.archived/`
on the next nightly sweep. Without this a renamed site would keep plain dirs on the
platform partition or a link into the old store.

## Disk space and filesystems

Both local and attached/extra filesystems are supported. Before moving or copying
data the tools compare the source size against the target's free space (`du`/`df`,
filesystem-aware for same-FS vs cross-FS), and **skip with a warning** rather than
fail when space is insufficient. A same-filesystem conversion is a rename (no
extra space needed); a cross-filesystem one copies, then repoints, then removes
the source.

Stale-store **archiving** on name reuse is deliberately placed *under*
`static/files` (`static/files/.archived/`) so it always shares the store's
filesystem and stays a free rename — a `static/files-*` sibling could land on a
small root filesystem and turn the move into a space-consuming copy. Each
archiving still records a `du`/`df` snapshot; a same-FS rename needs no free
space, and a secondary check falls back to an in-place rename only if the archive
would (unexpectedly) cross to a different, too-full device.

## Backups on the static filesystem

A backup of a native-symlinked site can be **large**: the backup tar follows the
`files`/`private` symlinks (dereferences the store), so the tarball holds the full
file data. Those backups land in `/data/disk/<account>/backups` on the **root
partition** — a disk-full risk for a big account whose files live on attached
storage.

When an account's `static/files` is a **separate filesystem** (the large-account
case — files moved to attached/extra storage), the nightly maintenance relocates
that account's `backups` and `backup-exports` onto it and replaces them with
symlinks:

```
/data/disk/<account>/backups         -> /data/disk/<account>/static/files/.backups
/data/disk/<account>/backup-exports  -> /data/disk/<account>/static/files/.backup-exports
```

The Aegir paths are unchanged (the symlinks are transparent), so `backup_path` and
`aegir_backup_export_path` keep working. Both targets live **under** `static/files`
so they share one filesystem — the backup-download **hardlinks** between `backups`
and `backup-exports` keep working (hardlinks cannot cross filesystems) — and the
leading-dot names are skipped by the site/orphan scan, like `.archived`.

- **Gated on a separate filesystem.** On a default single-filesystem box
  `static/files` is on the root device, so there is nowhere better to put backups
  and the relocation is a **deliberate no-op**. It only acts once a large account's
  `static/files` is on attached storage.
- **Safe one-time migration.** Existing backups are moved **incrementally**
  (`rsync --remove-source-files`: ~one file of extra space at a time, per-file
  safe); on any failure the real directory is left in place and no symlink is made.
  It never deletes a backup.
- **Task-queue interlock.** While migrating, the run holds the Aegir task queue
  with a dedicated `/run/boa_queue_stop.pid` (honoured by `runner.sh` — the parent
  exits and each per-account child dispatch skips) so no backup task writes into a
  directory being moved. It self-heals: `clear.sh` removes it once its owner PID is
  gone and `/run` clears on reboot, so it can never freeze the queue. The migration
  is serialised across accounts with a `flock`.
- **Kill-switch** — see *Configuration → Relocating backups off the root
  partition*.

## Orphan / ghost detection and stale-store archiving

When a site is deleted, BOA removes the in-site symlink but leaves the data behind
in `static/files/<url>/` — a **ghost**. Ghosts are archived aside automatically, in
two situations:

- **Deleted site, name not reused — archived by the nightly sweep.** The nightly
  auto-fix (`updatesymlinks --auto-fix` with `_AUTOSYMLINK_NIGHTLY=YES`) moves each
  deleted-site leftover store aside into the hidden, timestamped archive (below) and
  logs an incident. It **never deletes**. Only a store whose name has **neither a
  Drush alias nor a vhost** is archived — i.e. a genuinely deleted site. A merely
  **disabled** site keeps both its alias and its (placeholder) vhost, so it is
  treated as active and **left in place** — its files stay live for a later
  re-enable. A partial/broken state (only one of alias/vhost present) is reported
  but also left in place. The sweep runs with the Aegir task queue paused + drained,
  so no in-flight install/clone can make a live site momentarily look deleted.

  ```
  [REPORT] ORPHAN archive incident: <url> deleted-site leftover size=<N>K -> static/files/.archived/<stamp>/ (target FS avail=<M>K)
  ```

  The read-only report (`updatesymlinks --orphan-report`, or `autosymlink report`)
  still **lists** orphans without moving anything — useful when the auto-fix is off,
  or to preview. To turn the deleted-site auto-archiving off (revert to report-only),
  create `/data/conf/disable_orphan_store_archiving.cnf`.

- **Reused name — archived on create.** If a fresh install, clone, or migrate/rename
  reuses a name whose ghost store is still present, that stale store would otherwise
  block the new site's conversion. It is **moved aside automatically** and the new
  site converts cleanly. The same archiving covers the **break-sharing** path (a
  clone/migrate whose deployed link still points at another site's store): the
  pre-existing target store is archived aside before the copy.

Every archive lands under the store, on the same filesystem:

```
/data/disk/<account>/static/files/.archived/<UTC-stamp>/<url>/{files,private}
```

The move is **non-destructive** (nothing is deleted), and because `.archived` lives
*under* `static/files` it is always on the **same filesystem** as the store — a free
rename, even when `static/files` is a symlink to attached storage. The leading-dot
`.archived` is skipped by the orphan/site scan, so it is never mistaken for a site,
yet the tools still track it. Every archiving is logged with a `du`/`df` disk-space
snapshot, always — even when space is ample.

**Archived stores accumulate — prune them.** Archiving never reclaims space (a
big site whose name is reused many times leaves many copies). The report
therefore sums the `static/files/.archived/` pile per account and emits an
**emailed** `[REPORT] ORPHAN` alert once the total crosses a threshold (below it,
a plain informational `[REPORT]` line that is not emailed):

```
[REPORT] ORPHAN archived-store pile in account <acct>: …/.archived total=<N>K >= threshold <T>K - prune old entries to reclaim space
```

The threshold defaults to **1 GiB** and is tunable (see *Configuration →
Archived-store accumulation alert*). Prune the reviewed archive by hand:

```bash
du -sh /data/disk/<account>/static/files/.archived/*                 # oldest-first by stamp
rm -rf /data/disk/<account>/static/files/.archived/<UTC-stamp>
```

Deletion of archived stores is **left to the operator, by design** — the tools
archive and alert but never auto-delete. An age-based sweep (as BOA uses for
`/data/disk/<account>/backups`, whose timestamps are always fresh, deleting
anything older than N days) is deliberately **not** applied here: an archived
orphan may hold data that is already very old yet still wanted, so purging it by
age cannot be guaranteed safe. Review the alert and prune by hand.

## Safety properties

- **Crash-safe conversion.** A move that is interrupted between relocating the
  data and creating the symlink is recovered on the next run: the store holds the
  data and the missing in-site link is recreated (self-heal). The move is
  rc-checked, so a symlink is never created over a failed/partial move, and the
  source directory survives any move failure.
- **Clean dry-run before any change.** Both the global batch and the narrow apply
  run a dry pass first and only apply when it is clean.
- **Idempotent.** A site that is already correctly symlinked is a no-op on every
  path (install, verify, clone, nightly).
- **Fail-open.** If the store is unavailable or a link cannot be created, the site
  falls back to plain real directories — never a dangling link and never an
  aborted task.
- **No concurrent corruption.** The narrow apply defers while the nightly batch's
  maintenance pause is active, and the nightly batch skips while a provision/clone
  task is running. The backups relocation additionally holds the task queue with a
  self-healing `/run/boa_queue_stop.pid` and serialises with a `flock`, so no
  backup is moved mid-write.
- **Orphan archiving is deletion-safe.** A deleted-site store is *moved* (never
  deleted) into `.archived/`, and only when the name has **neither** a Drush alias
  **nor** a vhost. A disabled or active site keeps both, so it is never touched; and
  the nightly sweep runs with the task queue paused + drained, so a live site cannot
  momentarily look deleted. Pruning `.archived/` remains the operator's call.

## Verify

```bash
# A site's files/private should be symlinks into its own static store:
ls -l  /data/disk/o1/.../sites/example.com/{files,private}
readlink /data/disk/o1/.../sites/example.com/files
#   -> /data/disk/o1/static/files/example.com/files

# The store dir itself must be writable by the web group (account user:www-data):
ls -ld /data/disk/o1/static/files/example.com/files
#   -> drwxrwsr-x o1 www-data

# Dry-run report for one site (no changes):
autosymlink --site example.com

# Box-wide read-only report incl. orphans and the archived-store pile:
autosymlink report | grep -E '\[REPORT\]'

# One site's full history + current state (symlinked when, archived where, active/disabled/deleted):
symlinkinfo example.com

# Stale/orphan stores archived here (hidden; prune when large):
du -sh /data/disk/o1/static/files/.archived/* 2>/dev/null

# Logs:
tail -n 50 /var/log/boa/autosymlink.log
```

## Testing and debugging

`autosymlink` writes to `/var/log/boa/autosymlink.log`; `updatesymlinks` archives
verbose output to `/var/log/boa/autosymlink.verbose.archive.log` and emails a
summary. The Provision task log (in the Aegir front end, or the backend output)
shows the `[native-symlink] …` line for install, clone and migrate/rename.

### New-site install

1. Install a site, then check the in-site links and the store:
   ```bash
   ls -l /data/disk/<acct>/.../sites/<site>/{files,private}   # both symlinks
   readlink /data/disk/<acct>/.../sites/<site>/files          # -> store/.../files
   ls -ld  /data/disk/<acct>/static/files/<site>/files        # <acct>:www-data, writable
   ```
2. The task log should contain
   `[native-symlink] <site>: files/private moved into the per-account store and symlinked`.

### Clone

1. Clone a symlinked site. The clone's links must point at **its own** store
   (`static/files/<clone>/…`), not the source's:
   ```bash
   readlink /data/disk/<acct>/.../sites/<clone>/files   # -> static/files/<clone>/files
   ```
2. The task log shows the `[native-symlink]` line and **no `[ALERT]`**. An
   `[ALERT] … not completed` line means the unshare could not finish (low disk /
   missing source) and the clone may still share the source store — re-run
   `sudo /usr/local/bin/fix-drupal-site-symlinks.sh --site=<clone> --force-unshare`
   once space is available.

### Reused site name (stale-store archiving)

1. Install a site, delete it but leave its `static/files/<site>/` behind (a
   ghost), then create a site with the **same name**.
2. The new site's task log shows the archive incident and a clean conversion:
   ```bash
   ls -ld /data/disk/<acct>/static/files/.archived/*/<site>   # the old store, moved aside
   readlink /data/disk/<acct>/.../sites/<site>/files          # -> static/files/<site>/files (fresh)
   ```
3. Confirm the accumulation alert fires (lower the threshold to force it):
   ```bash
   echo 1 > /data/conf/native_files_archive_alert_kb.cnf         # 1 KB = always alert (test only)
   updatesymlinks --orphan-report | grep 'archived-store pile'
   rm -f /data/conf/native_files_archive_alert_kb.cnf
   ```

### Migrate / rename

1. Migrate or rename a symlinked site. The migrated/renamed site's links must
   point at **its own** store, not the source/old-name store:
   ```bash
   readlink /data/disk/<acct>/.../sites/<new>/files   # -> static/files/<new>/files
   ```
2. The old-name store `static/files/<old>/` is left as an orphan — reported, and
   archived into `.archived/` on the next nightly sweep.

### Backups on the static filesystem

Only fires where the account's `static/files` is a separate filesystem. After a
nightly run (or `bash /var/xdrago/night/10-account.sh /data/disk/<acct>`):
```bash
readlink /data/disk/<acct>/backups          # -> .../static/files/.backups
readlink /data/disk/<acct>/backup-exports   # -> .../static/files/.backup-exports
# both resolve onto the static FS; a front-end backup download (hardlink) still works
```
While it migrates, `/run/boa_queue_stop.pid` is present and `runner.sh` skips the
queue; it is removed at the end (or self-healed by `clear.sh` if the run crashed).

### Nightly auto-fix

```bash
echo '_AUTOSYMLINK_NIGHTLY=YES' >> /root/.barracuda.cnf   # then wait for the nightly :47 window, or:
updatesymlinks --auto-fix                                  # run it now
symlinkinfo <site>                                         # confirm the site is symlinked (State NOW)
```

### Orphan store: report and auto-archive

To force a positive case: delete a site but leave its `static/files/<site>/`
behind, then:

```bash
# Read-only report (lists it, moves nothing):
echo '_ORPHAN_FILES_REPORT=YES' >> /root/.barracuda.cnf
updatesymlinks --orphan-report      # emails _MY_EMAIL only if an orphan is found
autosymlink report | grep ORPHAN

# Auto-archive it (nightly apply): the store is moved into .archived/ and vanishes
# from static/files. A *disabled* site (alias+vhost present) is left in place.
echo '_AUTOSYMLINK_NIGHTLY=YES' >> /root/.barracuda.cnf
updatesymlinks --auto-fix
symlinkinfo <site>                  # shows the archive event + current .archived path
```

### Share opt-out and kill-switch

```bash
# Share: create the control file, then a non-clone run leaves the cross-site link as-is.
touch /data/disk/<acct>/static/control/share.files.<site>.info

# Kill-switch: with this present, a new install/clone keeps plain dirs.
touch /data/conf/disable_native_files_symlink.cnf
```

### Backup / restore round-trip

Back up a symlinked site and restore it; confirm the restored site has real file
**contents** (the backup follows the link by default, so the tarball holds the
data, not a dangling symlink), and that the restored `files`/`private` are
symlinks into the restored site's store.

### "A new site is not getting symlinked"

Check, in order:

1. **Wrapper installed?** `ls -l /usr/local/bin/fix-drupal-site-symlinks.sh`
   (700 root:root). If missing, it has not been fetched yet — see
   *Deployment* below.
2. **Sudoers entry?** `grep -r fix-drupal-site-symlinks /etc/sudoers.d/` should
   list the account user (and `aegir`).
3. **Kill-switch present?** `/data/conf/disable_native_files_symlink.cnf` or the
   account's `static/control/no_native_files_symlink.info` disables it on purpose.
4. **Account in scope?** Only `/data/disk/<account>` (Octopus) accounts are
   symlinked; the master hostmaster account is left with plain dirs.
5. **Tool ran?** Look for the `[native-symlink]` line in the install task log and
   for a recent entry in `/var/log/boa/autosymlink.log`.
6. **Store writable?** If the store dir came up `root`-owned, the move was done by
   root but the contents are preserved from the source; the store dir should be
   `<account>:www-data`. The in-site symlink itself is owner-matched to the store
   target by `autosymlink`, so it should not be left `root:root`.

### Deployment note

`autosymlink` / `updatesymlinks` reach a box via the regular SKYNET self-update
(`_update_agents` in `BOA.sh.txt`, serial-gated per tool). The privileged wrapper
and the `fix-drupal-*.sh` family are fetched per-file by `_update_boa_tools`. If a
freshly-bumped tool or a newly added script does not appear, the box has not run
the relevant update pass yet — it is retried on the next run (the per-file fetch
re-tries on failure; it does not give up after one attempt).

## Caveats

- **Archived stores are retained; deletion is the operator's call.** A stale
  store archived on name reuse is moved to `static/files/.archived/` and kept —
  the tools **never auto-delete** it, because there is no safe way to guarantee an
  auto-purge would not remove data being kept for a reason. Unlike routine backups
  (fresh-timestamped and safe to rotate by age), an archived orphan may already be
  very old yet still wanted, so no age-based auto-clean is applied. The report
  alerts once the pile passes a size threshold
  (`/data/conf/native_files_archive_alert_kb.cnf`, default 1 GiB); review it and
  prune by hand (see *Orphan / ghost detection and stale-store archiving*).
- **Legacy real directories are not auto-converted** during normal install/verify
  (to avoid moving data at an unexpected time). Convert them with the opt-in
  nightly auto-fix (`_AUTOSYMLINK_NIGHTLY=YES`) or a manual `autosymlink batch`
  after a clean DRY run.
- **Master (hostmaster) account.** Native symlinking is scoped to Octopus
  accounts under `/data/disk`; the master account's own site is left with plain
  directories.
- **Cross-account clone under low disk.** If a clone into a *different* account
  cannot copy the shared source's files for lack of space, the new site may keep a
  link into the source store until the manual `--force-unshare` run is repeated
  with space available — the `[ALERT]` log line flags this case. A same-account
  clone leaving a shared link is harmless (the data stays within one account).
- **Sharing control files are honoured everywhere except cloning.** If you rely on
  an intentional share, keep its `share.files.<site>.info` control file in place;
  do not expect a clone to inherit it.
- **Backups relocation needs a separate `static/files` filesystem.** It is a
  deliberate no-op on a default single-filesystem box (nowhere better to put
  backups) and only helps once a large account's `static/files` is on attached
  storage. The one-time migration de-links any pre-existing `backups`↔`backup-exports`
  hardlink pairs (the two dirs are moved separately), a bounded transient
  double-space cost on the static FS that ages out via the backup purge; backups
  taken after relocation hardlink normally.
