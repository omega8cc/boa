# Ghost and Empty Codebase / Platform Cleanup

During nightly maintenance (`owl.sh`) BOA can detect — and optionally move aside —
codebases and platform registrations that are no longer in use: orphaned code
trees with no working Drupal docroot, legacy shared codebases that no platform
references any more, and empty platform aliases left behind by deleted sites.

Detection is **version-agnostic**. A codebase is judged by whether it has a real
Drupal docroot — an `index.php` at the platform root **or** inside a `web/`,
`docroot/` or `html/` subdir. Composer-based Drupal 8+ platforms, whose web root
differs from the application root and which no longer ship a `sites/all`
directory, are therefore recognised as valid and are **never** treated as ghosts.
The same docroot detection keeps the per-account FTP `platforms/` symlinks and the
codebase permissions correct for those platforms (see [PLATFORMS.md](PLATFORMS.md)).

Every move here is **opt-in and off by default**. Out of the box each check runs
in **dry-run**: it logs what it *would* move and changes nothing. You enable the
actual move per box (or per account) with a control flag, so you can review the
dry-run output first and turn it on only once you are satisfied.

## What it cleans, and when

| Check | What it moves when enabled | Where it moves it | Flag |
|-------|----------------------------|-------------------|------|
| **Ghost codebases** | A Composer codebase under `distro/` that has a `vendor/` dir but no detectable docroot anywhere. | `/var/backups/ghost-codebases-cleanup/…` | `_GHOST_CODEBASES_CLEANUP` |
| **Shared codebases** | A legacy D6/D7 shared codebase under `/data/all` that no live platform symlinks to any more. | `…/codebases-cleanup/…` | `_SHARED_CODEBASES_CLEANUP` |
| **Ghost / empty platforms** | A Drush platform alias whose platform root has no detectable docroot (an empty or broken registration). | the account's (or `/var/aegir`'s) `undo/` dir | `_GHOST_PLATFORMS_CLEANUP` |

All three run once per night from `owl.sh` — the platform check per Octopus
account, the codebase checks once globally after the per-account work. Moves are
**reversible**: nothing is deleted, the codebase or alias is relocated to the
backup/`undo` path above, from where you can restore it.

## Control flags

The flags live in the live control files and default to `NO` (dry-run). BOA seeds
that default into the control files on install and on the next `barracuda up-*`
upgrade; a value you have already set is never overwritten.

| Flag | Control file | Scope |
|------|--------------|-------|
| `_SHARED_CODEBASES_CLEANUP` | `/root/.barracuda.cnf` | system-wide |
| `_GHOST_CODEBASES_CLEANUP` | `/root/.barracuda.cnf` | system-wide |
| `_GHOST_PLATFORMS_CLEANUP` | `/root/.barracuda.cnf` **and** `/root/.<account>.octopus.cnf` | system default + per-account override |

The two codebase checks operate on the whole `/data` tree, so their flags are
system-wide and live only in `barracuda.cnf`. The empty-platform check runs per
Octopus account, so `_GHOST_PLATFORMS_CLEANUP` may also be set in an account's
`octopus.cnf` to enable it for just that account; when it is not set there, the
system-wide value in `barracuda.cnf` applies.

Set a flag to `YES` to perform the move:

```
_GHOST_CODEBASES_CLEANUP=YES
```

While a check is in dry-run it logs lines such as:

```
Ghost /data/disk/o8/distro/002/foo detected (dry-run; set _GHOST_CODEBASES_CLEANUP=YES in /root/.barracuda.cnf to move)
```

so you can see exactly what each check would act on before enabling it. Reviewing
a dry-run run (and the paths it lists) before turning a flag on is recommended.

## While a Provision task is running

No cleanup of any kind runs while an Ægir/Provision task (install, clone,
migrate, verify, backup, restore) is in progress on the box. During those tasks
the site and platform trees are transiently inconsistent, so a snapshot taken
then could mis-read a live site as a ghost. Each cleanup checks for a running
`provision` process first and skips (logging a notice) if one is found, then runs
on the next nightly pass once the box is quiet. This interlock is always on and
sits above the per-cleanup flags.

## Per-site, vhost, and alias cleanup

Finer-grained flags gate cleanup of orphaned per-site artifacts:

| Flag | Gates |
|------|-------|
| `_GHOST_VHOSTS_CLEANUP` | an nginx vhost with no matching site alias |
| `_GHOST_SITES_CLEANUP` | a site registration (alias + vhost) whose site directory is gone |
| `_GHOST_SITE_FILES_CLEANUP` | additionally, that ghost site's leftover files directory (data) |
| `_GHOST_ALIASES_CLEANUP` | a stale per-site alias copy in the limited-shell (FTPS) user tree |

All four are per-account (settable in an account's `octopus.cnf`, with a
system-wide default in `barracuda.cnf`) and default `NO` (dry-run). Setting one
to `YES` performs the move. Because these reapers act on live serving artifacts,
extra safeguards always apply before anything is moved: the Provision interlock
above; the item must be seen as a ghost across consecutive nightly runs (a single
snapshot never acts); files/private are checked symlink-aware, so a transiently
absent native-symlink store target never counts as gone; and a degraded/unparseable
site path keeps the site rather than reaping it. The site reaper additionally
classifies each confirmed candidate before acting: a site path under
`aegir/distro` is the account's own Ægir front-end (or its `hm`/`oN.<host>`
alias companions) — system machinery, never reaped and never reported to the
client; when the site's platform root is missing entirely (a platform moved
or removed outside Ægir), or the site's directory turns up on another
platform of the same account (an interrupted migrate), the event is
platform-level — the data may be intact — so nothing is moved and the finding
is logged for operator review instead. Only a true per-site ghost (platform
directory present, site directory nowhere) is ever reaped. Because the
consecutive-night counters keep counting while a reaper is in dry-run,
turning `_GHOST_SITES_CLEANUP` on does not act immediately either: the first
enabled run per account only arms the reaper (logged, nothing moved), so
accumulated candidates always get one fresh enabled-mode night before any
move. These checks are newer than the codebase ones — exercise them in
dry-run, then on a disposable VM, before enabling on production.

On the omega8.cc-hosted fleet (hostname ending in `.aegir.cc`) the whole
`_GHOST_*_CLEANUP` family is seeded to `YES` in `.barracuda.cnf` (only when
the line is not already present, so an explicit operator value always wins
and the toggle stays available). `_GHOST_ALIASES_CLEANUP` joined the seed
once its 3-minute limited-shell sweep gained a 48-hour first-sighting hold
(marker `log/ctrl/ghost-ltd-<domain>.seen`, cleared on any valid sighting,
accumulated only while the flag is YES — so a flip never mass-reaps a
backlog) and a skip for `aegir/distro` front-end companion aliases. The hold
is the migration protection: `rsync -a` preserves source mtimes so the
60-minute freshness guard cannot recognise a freshly-arrived alias, and a
hand-set `/etc/boa/.pause_tasks_maint.cnf` does not survive on a hosted box
(the box automation removes it within minutes outside a `barracuda` run). On
builds that predate the hold, keep the flag at `NO` in both control files on
any box while it is receiving an account transfer. Everything the sweep moves
lands in the account's `undo/` directory, and the nightly site reaper — with
classification and the client notice — still acts first on an armed system.

## Client notification for ghost sites

A ghost site's registration lives in the account's own Aegir front-end, and
only there can it be removed for good — the backend reapers can move the
leftover alias and vhost aside, but any task run on the record re-creates
them. So when the nightly sweep confirms a ghost site (post-grace, whether or
not `_GHOST_SITES_CLEANUP` is enabled), it first checks the account's own
front-end for the site's record (`hosting_context` row). Only when the record
still exists — so the customer can actually see and remove it — does the
account owner get an email notice naming the site(s) with the exact
control-panel steps: Disable, then run the Delete task, or remove a stuck
record directly via its `node/NNN/delete` address, or re-run the failed
Install/Clone if the site is still wanted. A ghost whose node the customer
already deleted (only backend leftovers remain, invisible to them) is logged
as a backend leftover and cleaned silently, with no mail. The notice follows
the Let's Encrypt client-notice model: it goes to the account's
`_CLIENT_EMAIL` only, is throttled to once per 30 days per site, and is gated
by `_GHOST_CLIENT_NOTIFY` (default `YES`; set `NO` in `/root/.barracuda.cnf`
fleet-wide or in an account's `octopus.cnf` to disable).

## Recovering a moved item

Nothing is deleted, so recovery is just moving the item back from its backup or
`undo` location:

- ghost codebases — `/var/backups/ghost-codebases-cleanup/…`
- shared codebases — `/var/backups/codebases-cleanup/…` (or `/data/disk/codebases-cleanup/…` when `/data/all` is a symlink to attached storage)
- platform aliases — the account's `undo/` dir, or `/var/aegir/undo/` for the Hostmaster instance

See also [PLATFORMS.md](PLATFORMS.md) for the Octopus platform layout,
[MIGRATE-XOCT.md](MIGRATE-XOCT.md) for account migration, and
[BACKUPS.md](BACKUPS.md) for the backup subsystem.
