# Relocating Files Stores to Attached Storage (`migratefs`)

`migratefs` moves large data off the root partition and onto a **separate attached
filesystem**, replacing each moved directory with a symlink so nothing else has to
change. It relocates two things:

- each Octopus account's files store — `/data/disk/<oN>/static/files` — to
  `<mount>/files/<oN>/static/files`, and
- the shared archive — `/data/disk/arch` (SQL dumps, cluster backups) — to
  `<mount>/files/system/arch`.

It is the modern, safe replacement for the old ad-hoc `migratefs.sh`. It reuses
BOA's proven safe-mover pattern (the same one the nightly backups mover uses):
separate-device gate, self-healing task-queue pause, provision drain, live
`rsync` passes plus a closed final pass, ownership preservation, idempotency, and
never-destructive failure
handling — on any error the real directory is left in place and no symlink is
created, so data is never lost.

`migratefs` only relocates the **base**. Once an account's `static/files` is on the
attached disk, the rest is automatic on the next nightly run: `autosymlink` converts
that account's sites into the (now cross-filesystem) store, and the backups mover
relocates its `backups` + `backup-exports` onto the same filesystem. See
[FILES-SYMLINK.md](FILES-SYMLINK.md).

## Two hard requirements — read first

> **This tool is operator-only and is never automated.** There is no guarantee the
> attached storage has enough free space for what you are about to move, so the
> decision and the action are 100% yours: run it by hand, in a maintenance window,
> after reviewing the DRY plan. It is never scheduled and never run by SKYNET. A
> space check is included as a safety net, but you own the call.

> **BOA supports exactly ONE attached mountpoint under `/mnt`.** `migratefs` **and**
> other BOA scripts (notably the lshell FTP-jail path allow-list built in
> `manage_ltd_users.sh` and `satellite.sh.inc`) locate the attached files mount as
> *the single real mountpoint under `/mnt`*. **Multiple `/mnt` mountpoints are NOT
> supported.** BOA cannot tell which one is the "correct" files disk, so it refuses
> to guess: `migratefs` **exits with an error** if it detects more than one, and the
> FTP-jail wiring **fails closed** (wires no mount path) in the same situation.
> Unmount the extras and keep a single attached mount under `/mnt`.

The mount is detected by **what it is** (a real mountpoint / a separate device), not
by its name — any name works (e.g. `/mnt/extra`). There is no dot-in-the-name
convention.

## Usage

```
migratefs [--target <mount>] [--account <oN>] [--no-arch] [--apply] [--yes]
          [--grace <sec>] [--recheck-max <MB>] [--help]
```

| Option | Meaning |
|---|---|
| *(no `--apply`)* | DRY plan only — print what would happen, change nothing |
| `--apply` | perform the relocation (pauses the Ægir queue, drains tasks) |
| `--target <mount>` | attached mount to relocate onto, always a mountpoint under `/mnt` (the only supported store placement: the nightly's root-run relocations refuse a store elsewhere); auto-detected as the single real mountpoint under `/mnt` if omitted |
| `--account <oN>` | limit to one account, and skip `arch` (default: all accounts **plus** `arch`). Must be an Octopus account directory name: `arch`, `all`, `legacy`, a path or a dot-name is refused and the run exits 1 before it pauses the queue |
| `--no-arch` | do not relocate `/data/disk/arch` |
| `--yes` | in `--apply`, skip the interactive confirmation |
| `--grace <sec>` | queue-pause grace before draining tasks (default 15) |
| `--recheck-max <MB>` | most data copied again, with the store closed, when it changed during the live copy (default 1024); above it the store stays in place until a quieter run |

Typical run:

```
migratefs --target /mnt/extra            # review the DRY plan first
migratefs --target /mnt/extra --apply    # then perform it
```

Afterwards, convert the sites into the now-attached stores (or wait for the nightly
run):

```
autosymlink --batch-if-clean
```

## What lands where

```
/data/disk/<oN>/static/files   ->  <mount>/files/<oN>/static/files
/data/disk/arch                ->  <mount>/files/system/arch
```

`<mount>/files/<oN>/static/files` is the canonical `_MNT_STATIC_FILES` path the FTP
jail whitelists, so a relocated store stays reachable by the account's `<oN>.ftp`
user. Because the relocation happens at the **base** (`static/files` itself becomes a
symlink), any existing per-site symlinks
(`.../sites/<url>/files -> .../static/files/<url>/files`) keep resolving through it
unchanged.

## Safety properties

- **Separate-device gate, evaluated first.** Every account/`arch` step confirms the
  target is a genuinely different filesystem before touching anything. If the attached
  disk is not mounted (an empty `/mnt/<x>` directory on root is the same device as
  `/data/disk`), the step is skipped — data is never created or moved onto the root
  partition.
- **Root-only destination chain.** Every directory from the mount down to
  `<mount>/files/<oN>/static` (or `files/system`), the mount root included, must be a
  real directory owned by root and not writable by group or others; `--apply` refuses
  the step otherwise, and the DRY plan names the level that would be refused.
- **Move for a live store.** `static/files` is web-served, so the copy runs as two
  non-removing `rsync -a` passes while the store stays live; then the store is set
  aside as `static/.files.migratefs`, closed (root, 0700) and copied a final time with
  `--delete`. Entries that changed during the live passes are copied again by content
  (up to `--recheck-max`), then `ln -s -T` makes the new store live and the set-aside
  copy is removed. The sites have no files for the length of that final pass. Peak
  usage on the target is one copy of the store.
- **Non-destructive.** No source file is removed while copying. The deletions are
  the final pass's `--delete` inside the new copy, the removal of a copy that never
  went live, and, once the link is live, the removal of the set-aside store (kept for
  review when it changed after it was set aside). On a failure the store is left, or
  put back, as a real directory under its name; a store holding a device, FIFO or
  socket is left in place for review.
- **Idempotent.** Re-running converges: an already-relocated store is a no-op; a
  deferred or failed move removes its copy and the next run copies again; a store
  left at the destination by an earlier run is renamed aside as
  `.files.stale.<stamp>.<pid>` for the operator to review and remove; a
  `static/.files.migratefs` left by an interrupted run stops that account for review;
  a fresh account with no `static/files` yet just gets an empty store created on the
  attached disk.
- **Interlocks.** A single-instance lock and the self-healing
  `/run/boa_queue_stop.pid` queue pause + provision drain. An `--apply` run does not
  start while BOA's nightly (`owl.sh`) or a BOA install or upgrade runs, or while
  another live operation holds the queue pause (its owner would end the pause
  mid-relocation); a pause left by an owner that is gone is taken over.
  `updatesymlinks` and the nightly backups mover take the pause the same way: while
  another live operation holds it, `updatesymlinks` retries the next hour and the
  mover leaves that account's backups for the next night.
- **Store hold.** Each store is held while it is relocated:
  `/run/migratefs-account-<oN>.pid`, or `/run/migratefs-arch.pid`, holds the
  `migratefs` pid. The checks below run once before it is written, so a store
  deferred for a reason already known is never held, and again once it is written;
  it is removed when the store is done or the run ends.

  A hold counts only while its pid is a live root process that runs `migratefs`
  (matched as executed, never as a word anywhere on a command line), so a pid reused
  by another user's process never holds a store, and the next `migratefs` run
  removes any hold a killed run left. The passes that change a store honour it:
  - the nightly per-account pass skips a held account for that night, with a line in
    the account's night log;
  - `updatesymlinks` treats a hold as a heavy task and retries the next hour;
  - an `octopus` upgrade skips a held account with an `ALRT` line and completes
    `WITH ERRORS`, naming it;
  - `usage.sh` skips its tmp/dot-file cleanup for a held account;
  - `copydbackup` skips a held account for the whole run, copy and cleanup, with one
    line in `/var/log/backup_validation_issues.log`; a later run copies what it left;
  - the SQL backups (`mysql_backup.sh`, `mysql_cluster_backup.sh`) wait for a held
    `arch`, checking every minute for up to 3 hours, then dump as usual. A hold that
    outlives 3 hours skips that run with a "Backup SKIPPED" notice. The start and
    end of the wait are logged in `/var/log/boa/migratefs.log`.

    A waiting run holds only `/run/boa_sql_backup_wait.pid`, which `migratefs` also
    reads. It counts only while its pid is a live root process that runs an SQL
    backup script, and `clear.sh` removes it once it is not. The run marker
    (`/run/boa_sql_backup.pid`, `/run/boa_sql_cluster_backup.pid`) is written once the
    wait ends, so the checks that stand down on that marker keep running meanwhile.

    The task runner finds the backup by its process, so it holds the task queue for
    the whole wait. The load tiers of `second.sh` stand down only when the load is
    also iowait-bound, which a run that only waits does not cause.
- **Deferrals.** A store is left in place, with the reason logged, when as its hold
  is taken BOA's nightly or that account's nightly pass, a BOA install or upgrade,
  `autosymlink`/`updatesymlinks`, the SQL backup run (with its `usage.sh` and
  `copydbackup` legs), or `copydbackup` run on its own is active; `arch` also while
  any backup writer (`duplicity`/`mydumper`/SQL/cluster/`sequential_backups`) is, so
  a backup file is never moved mid-write. The nightly starting during the run defers
  the remaining stores.

## Notes

- Run `arch` relocation when backups are idle. `migratefs` defers `arch` if it detects
  an active backup writer, and a scheduled SQL backup that starts during the
  relocation waits for it (up to 3 hours), but the safest window is one with no
  scheduled backups.
- `migratefs` pauses the **Ægir task queue**, not web traffic. For a fully quiescent
  move of a busy account, put the site(s) into maintenance mode first.

> **Relocated `arch` and host migration.** Once `/data/disk/arch` (or an account's
> `static/files`) is a symlink to the attached mount, the host-migration tools
> `xoct`/`xcopy` (`transfer shared` / `transfer`) and `xmass` handle it **storage-aware**,
> per the *target's* disk reality: its contents are **mirrored onto the target's `/mnt`
> mount** (with the on-target path re-pointed there) if the target has one, or
> **de-referenced into a real dir** on the target root if it has none — never copied as a
> bare (dangling) symlink.
>
> Make sure those tools are current (storage-aware)
> before migrating a host whose `arch`/`static/files` is relocated;
> older versions would copy/skip the bare symlink and transfer **no** SQL dumps or cluster
> backups. (Consumers that read a path *under* `arch`, e.g. `copydbackup` and
> `mysql_cluster_backup`, resolve through the symlink transparently and need nothing.)
