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
separate-device gate, self-healing task-queue pause, provision drain, two-pass
`rsync`, ownership preservation, idempotency, and never-destructive failure
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
          [--grace <sec>] [--help]
```

| Option | Meaning |
|---|---|
| *(no `--apply`)* | DRY plan only — print what would happen, change nothing |
| `--apply` | perform the relocation (pauses the Aegir queue, drains tasks) |
| `--target <mount>` | attached mount to relocate onto; auto-detected as the single real mountpoint under `/mnt` if omitted |
| `--account <oN>` | limit to one account, and skip `arch` (default: all accounts **plus** `arch`) |
| `--no-arch` | do not relocate `/data/disk/arch` |
| `--yes` | in `--apply`, skip the interactive confirmation |
| `--grace <sec>` | queue-pause grace before draining tasks (default 15) |

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
- **Two-pass move for a live store.** `static/files` is web-served, so the copy runs
  as a non-removing `rsync -a` first (the live store stays complete during the long
  transfer), then a fast `--remove-source-files` reconcile, then `rmdir` + `ln -s`.
  Peak usage on the target is one copy of the store; the source filesystem never
  grows.
- **Non-destructive.** The only deletions are `rsync --remove-source-files` (file by
  file, after each is copied) and a `rmdir` that fails closed on a non-empty
  directory. The symlink is created only after the source empties cleanly. On any
  failure the real directory is left in place and the copied data is also present at
  the target.
- **Idempotent.** Re-running converges: an already-relocated store is a no-op, a
  partial move merges and completes, a fresh account with no `static/files` yet just
  gets an empty store created on the attached disk.
- **Interlocks.** A single-instance lock, the self-healing `/run/boa_queue_stop.pid`
  queue pause + provision drain, and — for `arch` — a defer while a backup writer
  (`duplicity`/`mydumper`/cluster/`sequential_backups`) is active, so a backup file
  is never moved mid-write.

## Notes

- Run `arch` relocation when backups are idle. `migratefs` defers `arch` if it detects
  an active backup writer, but the safest window is one with no scheduled backups.
- `migratefs` pauses the **Aegir task queue**, not web traffic. For a fully quiescent
  move of a busy account, put the site(s) into maintenance mode first.

> **Relocated `arch` and host migration.** Once `/data/disk/arch` is a symlink to the
> attached mount, tools that migrate the whole host by rsyncing `/data/disk/arch` as a
> bare path — `xoct`/`xcopy` (`transfer shared`) and `xmass` — must resolve the symlink
> and transfer its **contents**, or they will copy/skip the link itself and the target
> host receives **no** SQL dumps or cluster backups. Verify arch transfers its contents
> before migrating a host whose `arch` has been relocated. (Consumers that read a path
> *under* `arch`, e.g. `copydbackup` and `mysql_cluster_backup`, resolve through the
> symlink transparently and need nothing.)
