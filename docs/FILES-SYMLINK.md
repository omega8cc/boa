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
| **Nightly auto-fix** | Convert any not-yet-symlinked site and self-heal partly-symlinked ones, box-wide. | **off** (opt-in) |
| **Daily orphan report** | Email a report of ghost/orphaned store entries (data with no matching active site). | **off** (opt-in) |
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

- Provision (install and clone hooks) calls
  `sudo /usr/local/bin/fix-drupal-site-symlinks.sh --site=<url> …`.
- The wrapper validates its arguments and invokes **only** the narrow single-site
  `autosymlink` apply — it cannot reach the global batch/live modes.
- `autosymlink` (root) **moves** the existing `files`/`private` into the store and
  replaces them with symlinks. It never creates empty store dirs from the
  unprivileged side.

On a fresh install the wrapper is called from `post_provision_install`, before the
site's first verify writes the nginx vhost, so Provision passes `--account`
explicitly (the narrow mode then trusts the Drush alias alone). On a clone it is
called after the post-deploy verify, so the account auto-resolves from the
vhost+alias pair.

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

Provision runs unprivileged, so the install/clone tasks cannot call `autosymlink`
(root) directly. This hardened `sudo`-NOPASSWD wrapper (in `/usr/local/bin`,
alongside the `fix-drupal-*.sh` family) validates its arguments and forwards
**only** the narrow single-site apply — it cannot reach the global batch/live
modes:

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
ls -l  /data/disk/o1/.../sites/example.com/{files,private}
readlink /data/disk/o1/.../sites/example.com/files
#   -> /data/disk/o1/static/files/example.com/files

# The store dir itself must be writable by the web group (account user:www-data):
ls -ld /data/disk/o1/static/files/example.com/files
#   -> drwxrwsr-x o1 www-data

# Dry-run report for one site (no changes):
autosymlink --site example.com

# Box-wide read-only report incl. orphans:
autosymlink report | grep -E '\[REPORT\]'

# Logs:
tail -n 50 /var/log/boa/autosymlink.log
```

## Testing and debugging

`autosymlink` writes to `/var/log/boa/autosymlink.log`; `updatesymlinks` archives
verbose output to `/var/log/boa/autosymlink.verbose.archive.log` and emails a
summary. The Provision task log (in the Aegir front end, or the backend output)
shows the `[native-symlink] …` line for install and clone.

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

### Nightly auto-fix

```bash
echo '_AUTOSYMLINK_NIGHTLY=YES' >> /root/.barracuda.cnf   # then wait for ~05:30, or:
updatesymlinks --auto-fix                                  # run it now
autosymlink report                                         # confirm sites are symlinked
```

### Daily orphan report

To force a positive case: delete a site but leave its `static/files/<site>/`
behind, then:

```bash
echo '_ORPHAN_FILES_REPORT=YES' >> /root/.barracuda.cnf
updatesymlinks --orphan-report      # emails _MY_EMAIL only if an orphan is found
autosymlink report | grep ORPHAN
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
