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
migrate. This is now **native**: new sites are created already symlinked, clones
get their own separate copy, and a set of tools keep the layout correct and
report stray data — with optional, opt-in automation.

> The account-level `static/files` directory may itself be a real directory or a
> symlink to attached storage; that lower layer is handled separately during
> migration (see [MIGRATE-XOCT.md](MIGRATE-XOCT.md) → *Static Files Symlink
> Handling*). This document is about the **per-site** `sites/<url>/{files,private}`
> links into that store.

## What happens, and when

| Event | Behaviour | Default |
|-------|-----------|---------|
| **New site** install | `files`/`private` are symlinked into the static store from the start; Drupal core writes through the link. | **on** (kill-switchable) |
| **Clone** a site | The new site gets its **own separate copy** of the files in its own store — never a link into the source site's data — when disk space allows; otherwise a warning is logged and the clone still succeeds. | **on** (kill-switchable) |
| **Nightly auto-fix** | Convert any not-yet-symlinked site and self-heal partly-symlinked ones, box-wide. | **off** (opt-in) |
| **Daily orphan report** | Email a report of ghost/orphaned store entries (data with no matching active site). | **off** (opt-in) |
| **Manual run** | Convert/report on demand with the tools below. | — |

Native creation applies to Octopus-hosted accounts (`/data/disk/<account>`).
Existing sites whose `files`/`private` are still **real directories** are **not**
auto-converted during a normal install or verify (that would move data at an
unexpected time); convert them with the opt-in nightly auto-fix or a manual run.

## The tools

All three live in `/opt/local/bin` and run as root.

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

Narrow single-site mode (used by the clone task; also handy for one-off fixes):

```bash
autosymlink --site example.com [--account o1] --apply [--force-unshare]
```

- `--site` / `--account` scope the run to one site (the account is auto-resolved
  from the vhost+alias pair when omitted).
- `--apply` performs the change; without it the narrow run is a read-only DRY for
  that one site. The narrow apply runs its own per-site clean dry-run first and
  only proceeds if it is clean.
- `--force-unshare` breaks an inherited cross-site/cross-account link even if a
  file-sharing control file exists — used by cloning so a fresh clone (which never
  opted into sharing) always gets its own copy.

The narrow mode never touches the global batch state and **defers** while the
nightly maintenance pause is active, so it never races the batch sweep.

### `updatesymlinks` — the scheduler / orchestrator

Wraps `autosymlink` with task-pausing, lock and load guards, and email. Driven by
two opt-in `.barracuda.cnf` variables (see Configuration):

```bash
updatesymlinks --auto-fix       # nightly: batch-if-clean apply + email on changes
updatesymlinks --orphan-report  # daily: read-only orphan report, email only if any found
updatesymlinks                  # legacy: full apply + report, for manual use
```

When auto-updates are enabled these run from cron (`~05:30` auto-fix, `06:00`
orphan report). The cron lines are always present; each sub-mode self-exits
unless its variable is set, so enabling or disabling is purely a `.barracuda.cnf`
change with no cron edit.

### `fix-drupal-site-symlinks.sh` — the privileged entry point

Provision runs unprivileged, so the clone task cannot call `autosymlink` (root)
directly. This hardened `sudo`-NOPASSWD wrapper (in `/usr/local/bin`, alongside
the `fix-drupal-*.sh` family) validates its arguments and forwards **only** the
narrow single-site apply — it cannot reach the global batch/live modes:

```bash
sudo /usr/local/bin/fix-drupal-site-symlinks.sh --site=example.com [--account=o1] [--force-unshare]
```

## Configuration

### `.barracuda.cnf` variables

| Variable | Default | Effect |
|----------|---------|--------|
| `_AUTOSYMLINK_NIGHTLY` | `NO` | `YES` enables the nightly global auto-fix (`~05:30`). |
| `_ORPHAN_FILES_REPORT` | `NO` | `YES` enables the daily orphan email report (`06:00`). |
| `_MY_EMAIL` | (your address) | Recipient for the orphan report and auto-fix notices. |

Both toggles are off by default; native creation and clone handling do not need
them. Already-installed boxes whose `/root/.barracuda.cnf` predates these lines
default to off automatically.

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

## File sharing between sites (opt-in)

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

## Disk space and filesystems

Both local and attached/extra filesystems are supported. Before moving or copying
data the tools compare the source size against the target's free space (`du`/`df`,
filesystem-aware for same-FS vs cross-FS), and **skip with a warning** rather than
fail when space is insufficient. A same-filesystem conversion is a rename (no
extra space needed); a cross-filesystem one copies, then repoints, then removes
the source.

## Orphan / ghost detection

When a site is deleted, BOA removes the in-site symlink but can leave the data
behind in `static/files/<url>/` — a **ghost**. `autosymlink report` (and the daily
`updatesymlinks --orphan-report`) list any store entry with no matching active
site (no vhost + Drush alias pair). Detection is **report-only by design** — it
never deletes anything. Review the report and remove confirmed ghosts by hand.

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
  task is running.

## Verify

```bash
# A site's files/private should be symlinks into its own static store:
ls -ld /data/disk/o1/static/.../sites/example.com/files
ls -ld /data/disk/o1/static/.../sites/example.com/private
readlink /data/disk/o1/static/.../sites/example.com/files
#   -> /data/disk/o1/static/files/example.com/files

# Dry-run report for one site (no changes):
autosymlink --site example.com

# Box-wide read-only report incl. orphans:
autosymlink report | grep -E '\[REPORT\]'

# Logs:
tail -n 50 /var/log/boa/autosymlink.log
```

## Caveats

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
