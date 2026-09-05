# Per-instance group — `instgrp`

Every Octopus account owns a private Unix group named after itself. It is
the primary group of the account's backend user (`oN`), its limited-shell
user (`oN.ftp`) and every per-client sub-account (`oN.<client>`), and the
account's files carry it. Nothing outside the account is a member.

Before this, every account's identities shared the box-wide primary group
`users`, and so did their files: a file that granted read to its group — a
site's `drushrc.php` with the database credentials, a Drush alias — granted
it to every other account on the box. The per-instance group makes "group
read" mean "this account's identities", nothing wider.

## What changes, and what does not

| | Before | After |
|---|---|---|
| Primary group of `oN`, `oN.ftp`, `oN.<client>` | `users` | `oN` |
| Group on the account's files (`~/static`, `~/.drush`, platforms, `sites/<uri>/drushrc.php`, …) | `users` | `oN` |
| `users` on those identities | primary | kept, supplementary |
| `settings.php`, `files/`, `private/` | `oN:www-data` | unchanged |
| FPM pool identities `oN.web`, `oN.<php>.web` | `www-data` only | unchanged, never join `oN` |
| Shared codebases under `/data/all` | `root:users` | unchanged, by design |

`users` stays on every identity on purpose: on a BOA server it is the
execute capability, not a data group. The system binaries are `root:users
0750` (lshell included) and the shared-core directories tenants may write
to are group `users`. An identity outside `users` cannot run `git`,
`composer` or log in. Nothing removes it; the build-time guards on the tree
refuse any tool that would.

## How an account gets there

Nothing to do. The octopus upgrade converts each account it upgrades (before
the rest of the run, so the run already writes with the new group), and an
account created after this ships is born converted -- when the box is ready
for it: the tool present and every fetched root-run writer group-aware
(`instgrp check`), else it is born on the box-wide group and the next
upgrade converts it. A group name already held by another identity (a
member, or a user whose primary group it is) leaves the newborn on the
box-wide group too, with a NOTE and no conversion attempt in that run;
every later upgrade alarms until the name is freed. Each conversion writes
`/data/disk/oN/log/instance-group.txt`. An account already converted costs
one read-only traversal on every later upgrade (early-quit on the first path
outside its group), no walk and no write.

The order never leaves an identity without access it had:

1. the group is created (a same-named group left behind by an earlier
   purge is adopted only while nothing holds it);
2. `users`, `www-data` and the lshell groups are asserted as supplementary
   groups on every identity of the account;
3. only then does the primary group move;
4. the account's roots are walked (`/data/disk/oN`, `/home/oN.ftp`, the
   sub-account homes, `/opt/user/{gems,npm}/oN*`, a static store relocated
   under `/mnt`) and every path still in group `users` is re-grouped — one
   `chown -R -h -P --from=:users` per root, group-only, by directory
   descriptor, so no symlink is ever followed, nothing outside the tree can
   be reached through a re-pointed component, and the `www-data` paths are
   never touched; the few `chattr +i` inodes chown reports are re-grouped
   with the flag dropped and restored around that one change;
5. the marker is written last.

The hosting queue keeps running during an octopus upgrade and a tenant's
sessions keep their old group set, so a file can be written into a not yet
walked directory while the walk runs. The walk is re-run over the residue
(twice at most); whatever still remains is reported as `DRIFT` and finished
by the next pass. The conversion is kept, never rolled back for files: a
path left in `users` is the old state, not a new exposure, while a rollback
would leave the busiest accounts unconverted on every release. Only a failed
identity move rolls the account back.

A shell logged in before the conversion keeps its old group set until it
reconnects; its own files still open through the owner bits.

`convert` refuses while another BOA run holds `/run/boa_run.pid` (the
upgrade arm holds it itself and says so with `--from-octopus`), waits a
bounded time for the account's own provision tasks, skips a still-busy
account and an account frozen for a migration (`log/proxied.pid`, the
marker every other root writer honours; `--force` overrides), and defers
(exit 5, a note in the upgrade report) while any fetched root-run writer on
the box still carries the box-wide form (`instgrp check`): an old `fix-drupal-*` script or nightly worker
would write `users` back on its next pass, and an old `websh` would lock
the tenant out of its shell. A skipped or refused account is reported in
the upgrade report (the `ALRT:` line the octopus report reads); nothing
retries it before the next upgrade.
Every BOA writer over account trees derives the group per account
(`_acct_group` in `lib/functions/helper.sh.inc`, copied verbatim into the
standalone tools): `users` until the account carries its own group, the
account's group after, so a mixed fleet keeps working throughout.

## The tool

Root-only, installed hardened in `/opt/local/bin`, never in sudoers or the
limited shell:

```sh
instgrp status  oN | all
instgrp convert oN | all [--from-octopus] [--force]
instgrp reclaim oN | all [--force]
instgrp revert  oN [--keep-enabled]
instgrp check
```

`status` prints the marker, the group, every identity's group set, the FPM
pool identities (which must not be in the group), the per-group file counts
under the account's roots (`users`, the account's, `www-data`, `root`, no
group, and any other named group -- a foreign account's after a numeric gid
collision on a copy or a root-run restore, whose identities can read the
files), and one verdict line — `CONVERTED`, `UNCONVERTED`, `DRIFT` (paths
under the roots are not in the account's group: back in `users`, in no
group, or in a foreign group -- an import, a hand `chown`, a tool predating
the form; re-run `convert` or `reclaim`, both only touch what drifted) or
`INCONSISTENT`. Exit status 0 / 0 / 2 / 3 in that order (4 = skipped, 5 =
not ready; over `all` the worst class wins: failed, inconsistent, drift, not
ready, skipped, done). A converted
account without a valid marker (born converted with the tool absent, a
copied marker dropped) reads `CONVERTED` with a note; the next `convert`
rewrites the marker. Every action logs one line to
`/var/log/boa/instgrp.log`.

`reclaim` is the file half alone: every path under the roots takes the
account's current group (`users` while unconverted), a marker that does not
record this box's group is dropped. No identity change and no lock, so it
is what a root-run restore, a migration destination and the nightly run. It
honours the migration freeze exactly as `convert` does: an account carrying
`log/proxied.pid` is skipped (exit 4) unless `--force` is given.

`revert` is the exact inverse: files first (so no identity ever loses a
group its files still carry), then the primary groups back to `users`, the
account members removed from the group, the marker removed, the group
deleted once no path and no identity carries it (a path written during the
walk keeps the group in place; re-run). It writes `_INSTANCE_GROUP=NO` into
the account's octopus cnf, so the next unattended upgrade does not convert
the account again (`--keep-enabled` leaves the cnf alone).

## Opting an account out

`_INSTANCE_GROUP=NO` in `/root/.oN.octopus.cnf` keeps that account on the
box-wide model: the upgrade arm skips it, and a fresh account carrying the
line is born the old way. For a NEW account, create `/root/.oN.octopus.cnf`
before `boa in-octopus` holding just two lines, `_USER="oN"` and
`_INSTANCE_GROUP=NO`; the install completes the file with its defaults and
keeps the seeded lines. Never copy another account's cnf for that: it carries
the other account's `_DOMAIN` (the install puts the derived name back, with a
NOTE). It does not undo a conversion already made — run
`instgrp revert oN` for that, which writes the line itself. An explicit
`instgrp convert` ignores the switch; it is the operator's order. The key
is persisted per instance (written at install, appended with its default on
upgrade when absent).

`boa cleanup purge oN` removes the account's group after its identities; what
the purge leaves on disk (a static store relocated under `/mnt`, the gems
and npm trees) is handed to `root:root` first, and the group stays while any
path still carries it. Removing a single sub-account leaves the group in
place: it belongs to the account.

## What this does not close

- Within one account, a per-client sub-account can still read the
  `drushrc.php` of a sibling site of the same account. The group is
  account-wide, not site-wide (the limited shell's Landlock rules keep
  sub-accounts at their own site directories, but that is a different
  layer). Do not describe this as per-site isolation.
- Shared codebases (`/data/all/…/sites/all/{modules,libraries,themes}`)
  stay `root:users` and group-writable by every account, by design.
  Cross-tenant write into a shared codebase is not closed by this change.
- The master (`/var/aegir`) keeps its own group `aegir` plus `users`, as
  before.

## Operator notes

- Never write the literal `:users` onto an account's tree by hand
  (`chown -R oN:users …`): on a converted account that re-opens the tree
  to every other tenant until it is re-grouped, and `instgrp status`
  reports it as `DRIFT`. Use `chown -R oN:$(id -gn oN) …`, which is right
  on both models. See `FIXREPO.md`.
- What heals drift, and when: the site and platform verifies and the
  nightly re-group the paths they write; the nightly account worker also
  probes the credential-bearing paths (`~/.drush`, `~/backups`, `~/config`,
  `~/tools`, the hostmaster sites, every `drushrc.php` under `~/static`)
  and runs `instgrp reclaim` on a hit; the 3-minute limited-shell worker
  moves an identity that fell back to the box-wide primary group (a hand
  `usermod`, a restored passwd) back onto the account's group; the octopus
  upgrade re-converts. Nothing else re-groups a tree between those.
- Ægir backups, restores, clones and migrations need no conversion step:
  the extracting process is the account's backend user, so the restored
  files take the account's primary group. Root-run restores are different:
  duplicity re-applies the archived ownership, so `backboa`, `duobackboa`,
  `multiback` and `mybackup` re-group what they restored (and run
  `instgrp reclaim` for the account) after every restore whose destination
  resolves inside an account's tree; a restore staged anywhere else is the
  operator's to follow with `instgrp reclaim oN` once the files are in
  place.
- GIDs are allocated per box from the system range, so the same account
  name has different GIDs on two boxes. rsync maps ids by name, and the
  source account's group has no name on a destination whose account is not
  converted, so a moved tree lands there in an unassigned numeric gid.
  `xoct transfer`, `xcopy transfer` and a hand-run `xmass sync --live`
  therefore run a group pass on the destination after every copy (`instgrp
  reclaim` where the tool is installed: paths in no group, in `users` or in
  another named group take the destination account's group, `users` while
  unconverted; passed `--force`, because the destination's own
  `log/proxied.pid`, if any, is its demotion artefact from an earlier
  cutover, not an account served from elsewhere), the xmass legs map the source account's group onto the
  destination account's group as they copy (so the 15-minute standby
  autosync never lands a foreign gid), and none of them carry the
  conversion marker -- it recorded the source box's
  conversion. `instgrp` reads a marker whose gid is not the account group's
  gid on this box as STALE (ignored), and `convert`/`reclaim` claim any path
  of the account's roots that is in no group or in another named group.
