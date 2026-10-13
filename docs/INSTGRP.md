# Per-instance group — `instgrp`

Every Octopus account owns a private Unix group named after itself. It is
the primary group of the account's backend user (`oN`), its limited-shell
user (`oN.ftp`), every per-client sub-account (`oN.<client>`) and every
platform developer login (`oN.<client>-dev`, for a client named in
`_LTD_PLATFORM_CLIENTS`), and the account's files carry it. Nothing outside
the account is a member.

Before this, every account's identities shared the box-wide primary group
`users`, and so did their files: a file that granted read to its group — a
site's `drushrc.php` with the database credentials, a Drush alias — granted
it to every other account on the box. The per-instance group makes "group
read" mean "this account's identities", nothing wider.

## What changes, and what does not

| | Before | After |
|---|---|---|
| Primary group of `oN`, `oN.ftp`, `oN.<client>`, `oN.<client>-dev` | `users` | `oN` |
| Group on the account's files (`~/static`, `~/.drush`, platforms, `sites/<uri>/drushrc.php`, …) | `users` | `oN` |
| `users` on those identities | primary | kept, supplementary |
| `settings.php`, `files/`, `private/` | `oN:www-data` | unchanged |
| FPM pool identities `oN.web`, `oN.<php>.web` (the control panel's pool `oN.hm` runs as one of them) | `www-data` only | unchanged, never join `oN` |
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
upgrade converts it.

A group name already held by another identity (a
member, or a user whose primary group it is) leaves the newborn on the
box-wide group too, with a NOTE and no conversion attempt in that run;
every later upgrade alarms until the name is freed. What the conversion
counts as the account's own is exact: `oN`, `oN.<name>` and
`oN.<client>-dev`. Any other name holding the group blocks it.

Each conversion writes `/data/disk/oN/log/instance-group.txt`. An account already converted costs
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
   under `/mnt`) and every path in group `users` that the walk changes (see
   "The tool") is re-grouped — group-only, through a handle opened inside
   the directory `find -P` holds, without following a link or blocking on a
   FIFO, so no symlink is ever followed, nothing outside the tree is reached
   through a re-pointed component, and the `www-data` paths are never
   touched; `chattr +i` inodes are re-grouped with the flag dropped and
   restored around that one change;
5. the marker is written last.

The hosting queue keeps running during an octopus upgrade and a tenant's
sessions keep their old group set, so a file can be written into a not yet
walked directory while the walk runs. The walk is re-run over the residue
(twice at most); whatever still remains is reported as `DRIFT` and finished
by the next pass.

The conversion is kept, never rolled back for files: a
path left in `users` is the old state, not a new exposure, while a rollback
would leave the busiest accounts unconverted on every release. Only a failed
identity move rolls the account back, and a rollback that meets an identity
in use records it in the same file a revert uses (below), for the worker to
finish.

The primary group of an identity in use cannot move: `usermod` refuses a
user that has a process in its own root whose real, effective or saved uid
is that user's (exit 8, nothing changed).

A logged-in shell or SFTP session
of `oN.ftp` or a sub-account is such a process; an FTPS session is not,
because pure-ftpd runs it in a chroot. So `convert` asks the same question,
waits up to a minute for every identity it still has to move (long enough
for a cron run of the account to end) and skips the account while one stays
in use (exit 4, an `ALRT:` line in the upgrade report naming the identity,
its process ids and names), before it changes anything.

It looks again right
before each move; an identity that comes into use in between rolls the moved
identities back and the account is still skipped (4), or the run fails (1)
and names the identity when one of them could not be moved back. The next
upgrade that finds the identity idle converts the account, or run `instgrp
convert oN` once the session has ended. Before this check a logged-in
`oN.ftp` failed the move half way and rolled the whole account back.

`convert` refuses while another BOA run holds `/run/boa_run.pid` (the
upgrade arm holds it itself and says so with `--from-octopus`; a lock that
names the pid of an `instgrp` run killed outright is taken away by the next
`instgrp` run, the next limited-shell worker pass or the next `clear.sh`
tick, so the worker's checks never stay off for hours), waits up to
three minutes for a limited-shell worker pass already running when it takes
that lock and refuses while one is still running (`revert` too; the
upgrade arm waits the same and skips the account as busy), waits a
bounded time for the account's own provision tasks, skips a still-busy
account and an account frozen for a migration (`log/proxied.pid`, the
marker every other root writer honours; `--force` overrides), and defers
a FIRST conversion (exit 5, a note in the upgrade report) while any fetched
root-run writer on the box still carries the box-wide form, or while the BOA
release that carries the Octopus arm has not stamped the box yet
(`/etc/boa/control/instgrp-arm.ready.txt`, written at the tail of that release's
barracuda pass; `instgrp check` shows both): an old `fix-drupal-*` script or
nightly worker would write `users` back on its next pass, an old `websh` would
lock the tenant out of its shell, and on a box that only received the fetched
tools ahead of its upgrade (a staged publish) the tar's own Octopus and system
libraries still write the box-wide group. The arm stamps live in
`/etc/boa/control` (0755, each stamp 0644), out of reach of the clean-ups that
sweep `/var/log/boa` by name; on a box an earlier release stamped in
`/var/log/boa`, `instgrp` copies the per-instance group's stamp before it reads
it, and the barracuda pass writes that stamp in `/var/log/boa` too while an
older `instgrp` can still be fetched.

An account that is already
converted takes its read-only re-pass regardless of the stamp. A skipped or
refused account is reported in
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
pool identities (which must not be in the group), a `web:` line naming the
account's own web group and its state when `wg-oN` exists (see below), the
per-group file counts under the account's roots (`users`, the account's,
`www-data`, `wg-oN` when it exists, `root`, no
group, and any other named group -- a foreign account's after a numeric gid
collision on a copy or a root-run restore, whose identities can read the
files), and one verdict line — `CONVERTED`, `UNCONVERTED`, `DRIFT` (paths
under the roots are not in the account's group: back in `users`, in no
group, or in a foreign group -- an import, a hand `chown`, a tool predating
the form; re-run `convert` or `reclaim`, both only touch what drifted) or
`INCONSISTENT`.

The walk regroups a directory, a regular file with one link, and a regular
file with more than one link or a FIFO whose owner is one of the account's
identities (`oN`, `oN.ftp`, a sub-account) that is a member of the target
group when the walk runs: that owner could make the same change itself with
`chgrp`, so root making it grants nothing.

Any other hard-linked file or FIFO, a socket or a device keeps its group:
the account can create the first three (a device node only root can make:
`mknod` needs `CAP_MKNOD`), and a hard link may share its inode with a file
the account does not own.

`status` reports them on an `other:` line with a count and up to three
examples; they never count as drift, and `convert` and `reclaim` log their
number. `revert` keeps the group while any of them still carries it
(exit 2): deleted, the group would leave them in a bare numeric gid that
the next account created can be handed. A symlink keeps its group too, but
is never counted and never keeps the group from `revert`: a symlink's group
is never used for access.

Exit status 0 / 0 / 2 / 3 in that order (4 = skipped, 5 =
not ready; over `all` the worst class wins: failed, inconsistent, drift, not
ready, skipped, done). A converted
account without a valid marker (born converted with the tool absent, a
copied marker dropped) reads `CONVERTED` with a note; the next `convert`
rewrites the marker. Every action logs one line to
`/var/log/boa/instgrp.log`.

`reclaim` is the file half alone: every path under the roots that the walk
changes takes the account's current group (`users` while unconverted), a
marker that does not
record this box's group is dropped. No identity change and no lock, so it
is what a root-run restore, a migration destination and the nightly run.
`convert` and `reclaim` leave the paths of the account's own web group
(`wg-oN`, while it exists) alone: those are the account's web paths, which
its FPM pools reach through that group.

It still
defers (exit 4) while a BOA install or upgrade run is live (`/run/boa_run.pid`,
`/run/boa_wait.pid` or `/run/octopus_install_run.pid`), unless the Octopus arm
called it with `--from-octopus`, and it refuses with exit 3 when the account reads
as converted while an identity is still on the box-wide group: reclaiming then
would re-flatten the tree, so run `instgrp convert <account>` (or let the
limited-shell worker heal the identity) first. It
honours the migration freeze exactly as `convert` does: an account carrying
`log/proxied.pid` is skipped (exit 4) unless `--force` is given.

`revert` is the exact inverse: files first (so no identity ever loses a
group its files still carry), then the primary groups back to `users`, the
account members removed from the group, the marker removed, the group
deleted once no path and no identity carries it (a path written during the
walk keeps the group in place, re-run; so does an entry the walk never
changes other than a symlink, exit 2, see above). It writes
`_INSTANCE_GROUP=NO` into
the account's octopus cnf, so the next unattended upgrade does not convert
the account again (`--keep-enabled` leaves the cnf alone).

`revert` refuses (exit 1) while a group `wg-oN` exists, in any state: the
account's web group goes first.

Like `convert`,
it does not start while an identity it has to move back is in use (exit 4),
and after the file walk it waits again before each identity's move; one
still in use then stays on the account's group, is named, and `revert`
exits 1 with the group kept.

That identity is recorded in
`/var/log/boa/instgrp.revert-pending.oN`, `status` reports the unfinished
revert, and the 3-minute limited-shell worker moves it back to `users` on
its first pass that finds it idle (a logged-in session ends, a cron run
completes), logs that to `instgrp.log` and the incident log, and drops the
record; run `revert` once more to remove the now empty group (or `convert`
to convert again). A `convert` in between supersedes the pending revert;
the nightly per-account pass writes with the box-wide group and skips its
drift probe while the record exists.

## Opting an account out

`_INSTANCE_GROUP=NO` in `/root/.oN.octopus.cnf` keeps that account on the
box-wide model: the upgrade arm skips it, and a fresh account carrying the
line is born the old way.

For a NEW account, create `/root/.oN.octopus.cnf`
before `boa in-octopus` holding just two lines, `_USER="oN"` and
`_INSTANCE_GROUP=NO`; the install completes the file with its defaults and
keeps the seeded lines. Never copy another account's cnf for that: it carries
the other account's `_DOMAIN` (the install puts the derived name back, with a
NOTE). It does not undo a conversion already made — run
`instgrp revert oN` for that, which writes the line itself. An explicit
`instgrp convert` ignores the switch; it is the operator's order. The key
is persisted per instance (written at install, appended with its default on
upgrade when absent).

`boa cleanup purge oN` removes the account's group after its identities (the
platform developer logins included). It first sets the account's task
dispatcher aside and ends whatever still runs as one of its identities (a
PHP worker, a task, a shell), so no identity survives the purge by being
busy. Removing a single sub-account leaves the group in place: it belongs to
the account.

What the purge leaves on disk (a static store relocated under `/mnt`, the
gems and npm trees) is handed to `root:root` first. A home that survives
is parked in the purge's zombie directory, shut to root, and its
directories and single-link files are handed to `root:root`.

Anywhere else the purge leaves something
of the account (the parked vhost files, its leftovers), a uid that no
longer names anyone goes to root, whatever the entry is: the next account
created could be given it. A directory or single-link file keeps its group;
a hard-linked file, a link, a FIFO, a socket or a device goes to
`root:root` and loses its set-ID bits and group and other write (a link's
own mode means nothing and stays).

This comes before the groups are decided, so such an entry no longer keeps
one. Nothing is deleted, and a FIFO or a device is changed without being
opened.

A gid that no longer names anything goes to root on every entry there, its
owner kept, once before the groups are decided and again after. So does
the gid of a group the purge removes, before the group goes: that gid is
never free while an entry there still carries it.

A hard-linked file, a link, a FIFO, a socket or a device also loses its
set-ID bits and group write (with an ACL, its mask), and a single-link
file its set-uid bit, which the kernel drops on any change of group. The
next group given that number gains nothing through them.

In `/tmp`, `/var/tmp` and `/dev/shm`, where the kernel trusts what root owns,
what the account's identities left is removed, before they are and again
after, and only a directory of theirs that still holds someone else's
entries goes to root. A gid that names nothing, or that of a group the
purge removes, goes to group root there, before the groups are decided and
again after.

The account's group then goes when no path still carries its gid and no
identity still holds it. While a path does, the gid stays taken: the group
is renamed `<gid>-purged` (for example `1002-purged`) and has no members
unless identities of the account survived the purge (see below).
No account name begins with a digit, so a later account named `oN` is given
a new group and gains nothing through those paths.

The purge names such a path. The scan covers `/data/disk`, `/home` and `/opt/user`, so a living
account's entry in the gems or npm tree keeps the gid too, unless the
account was converted.

On a converted account the group is the primary group of its identities,
and removing the account's own identity would remove the group with it.
The purge renames it `<gid>-purged` first, so the gid stays taken, and
before the decision gives group root to what carries it in the places
above, as for a gid that names nothing: only a path outside them keeps it.
When the gid cannot be held and another group takes it, or a rename fails,
the purge says so with an ALRT.

A group of the account's name that someone outside the account still holds
(a member, or a user whose primary group it is) keeps its name: that holder
already keeps a later account from taking it. One that only the account's
own identities still hold (deluser refused one) is renamed all the same,
with an ALRT naming them: BOA adopts a group of an account's name that only
that account's identities hold.

The purge removes the account's own web group `wg-oN` the same way, when
there is one, together with root's record of it. That group is still there
at the decision on every account, so a living account's entry the scan
meets (it covers `/var/www` too) keeps its gid, as `<gid>-purged`.

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
  before; its web paths have a web group of their own, `wg-aegir`, once an
  operator converts it (below).
- The web group (below) does not close what another account's code can
  reach through nginx (a request for a file a site of this account serves)
  or through its own database user's grants; both need code running as that
  account's backend user. Within one account, every site and sub-account
  still shares the one web group.
- Neither group stops nginx serving another account's file through a link
  an account put in its own site. The nginx link check closes that
  (`NGINX-LINKS.md`); it is not switched on in this release.
- Processes already running with `www-data` when an account enters phase B
  (a shell session, a long Drush run) keep it until they end: the run counts
  them and tells the account to reconnect, and never kills them.
- While its identities were in `www-data`, the account could give a file of
  its own that group and the set-group-ID bit anywhere it could write, and
  run it with `www-data`'s group after phase B. Phase B walks every local
  file system that honours the bit (not `nosuid`) and clears it on each such
  file one of the account's identities or pool users owns, wherever it is,
  by name inside the directory the walk holds open: a directory renamed or
  replaced by a link meanwhile cannot lead the walk elsewhere. The notes
  give the count, `/var/log/boa/instgrp.log` each path.
- Network and FUSE mounts are not walked (a server that stops answering
  would hang the walk); the account's notes name each one not mounted
  `nosuid`, where such a file keeps its bit, so mount those `nosuid`. A
  run killed before the walk, a walk that could not clear a file, or a
  process still holding `www-data` leaves the walk owed (`webstatus` says
  so), and the next run at phase B walks again.

## The account's own web group (`wg-oN`)

The per-instance group closes one account's code and credentials to the
others. The web group closes the rest: a site's files, private files and
settings. Until an account is converted to its own web group they are in
the box-wide group `www-data`, which every account's PHP pools and shell
users are members of, so any of them can read another account's uploads and
private files.

The web group `wg-oN` takes that role for one account only:
the account's identities and its pool users are listed in it, and its web
paths are handed to it. New account names may not begin with `wg-` nor hold
a dot.

### Arming

Nothing converts until the box is armed: `_WEB_GROUP_ARM=YES` in
`/root/.barracuda.cnf`. Every barracuda pass then writes the stamp
`/etc/boa/control/instgrp-web-arm.ready.txt`, and removes it while the setting
is NO. `_WEB_GROUP_PHASE_B=YES` beside it lets the Octopus arm go on to
phase B (below), read as bash reads the file (the last assignment counts;
`export`, quotes and a trailing comment are fine). Both are NO by default.

Tenant isolation is not switched on in this release. The setting writes the
stamp only on a test server that carries the marker
`/root/.tenant-isolation-test.cnf`; anywhere else the pass removes the stamp
and prints a NOTE, so no account converts. A conversion already under way
resumes either way. A later release switches it on.

From the release that switches it on, a box is armed by default. A barracuda
pass then writes `_WEB_GROUP_ARM=YES` into a `/root/.barracuda.cnf` that has
no `_WEB_GROUP_ARM` line, on omega8.cc-hosted systems first and on every box
one release later; on an armed box `_WEB_GROUP_PHASE_B=YES` follows the same
way, once phase A has run across those systems.

Only a missing line is written, and only as YES. A line of your own always
stays, so `_WEB_GROUP_ARM=NO` keeps a box out and `_WEB_GROUP_PHASE_B=NO`
keeps it at phase A; either can be set today.

On a box that is not armed, the arm prints nothing for an account with no
web group, intent or record: its line in `/var/log/boa/instgrp.log` is all
it leaves. Before arming a box, run `instgrp webcheck --report`: it lists
the writers that must be current on the box, the stamp, and for each
account whether it is ready and what would hold its phase B back, counted
by kind (below).

A box is ready for a first conversion when the stamp exists, every fetched
writer the conversion relies on carries its web-group form (`instgrp`, the
limited-shell worker, the nightly, both site scripts, `xtrim`, `xoct`,
`xcopy`, `xmass`, `aegir2boa-stage2`), and the account's own provision copy
carries two tokens: `provision_drupal_web_group_private`, the branch that
keeps its private files closed, and `provision_path_web_group`, which keeps
a site outside the account's tree in `www-data` (see "What holds phase B
back").

A box that is not ready refuses with exit 5, names what its check missed,
and changes nothing. `webcheck --report` prints `provision: ready` for an
account whose copy carries both, or the token it lacks.

While a
migration has the box's runners parked (`xoct` and `xcopy` from `pre-mig`
to `post-mig`, an `xmass` cutover until it unparks them), the parked copy
of each is the one read, as it is the copy the park puts back; a live copy
beside a parked one is the one read.

### Phase A and phase B

- **Phase A**: `wg-oN` is made, every identity of the account and every pool
  user is listed in it, the web paths (settings files, the files and
  private stores) are handed to it, the private files take `02770`/`0660`
  (the subtrees nginx never serves, `civicrm/{ConfigAndLog,custom,upload,templates_c}`,
  `backup_migrate` and `config_*`, count as private), the secret files
  (settings, Grav's and Textpattern's credential stores, `.env`) are
  narrowed to their owner and group, and the account's Drush alias
  `web_group` names `wg-oN`. The account's identities are still in
  `www-data` in phase A: nothing a site reads stops being readable.
- **Phase B**: the account's pools run in `wg-oN` (a `group =` line in each
  of its pool files), and its tenant identities (`oN`, `oN.ftp` and the
  sub-accounts) leave `www-data`. From then on no pool and no shell user of
  another account can read the account's web paths.

The run that takes an account to phase B walks its web paths into `wg-oN`
once more after its pools run in `wg-oN` and its identities have left
`www-data`. Until then a pool writes in `www-data`: an upload PHP moves
into a files store from the pool's temporary directory keeps it. What a
site wrote that way during the first walk is taken by the second.
Anything still left after it is noted, with exit 2, and the next run at
phase B walks it.

`www-data` left during the raise in the account's settings files, store
tops, private files or its store on attached storage does not hold phase
B: the second walk takes it in the same run, so uploads there do not keep
phase B waiting while they go on.

The stores of its sites that the conversion does not walk (with no single
mount point under `/mnt`, or its store on attached storage owned by a user
other than root or the account) are read again after the second walk, and
after the walk of every run at phase B: a path a pool left there in
`www-data` is noted, with exit 2, on each such run until it is given
`wg-oN` or the layout is one BOA makes, when the next run at phase B walks
it.

An account's store on attached storage (`<mount>/files/oN/static/files`,
where migratefs moves `~/static/files`) is part of its web paths whether
root or the account owns it: phase A walks it into `wg-oN` as it walks
the home, and `webrevert` walks it back. The per-instance group's own walks
take that store only when the account owns it and no link is on the way to
it.

The Octopus upgrade runs the conversion for every account (the arm, after
the per-instance group's own step): phase A on an armed box, and phase B
where `_WEB_GROUP_PHASE_B=YES`. A new account is converted right after its
install.

### What refuses a conversion

A first conversion, and every step up to phase B, is gated; a refusal
changes nothing and names its reason:

- the account's opt-out, `_WEB_GROUP=NO` in `/root/.oN.octopus.cnf`, read
  as bash reads the file (the last assignment counts; `export`, quotes and
  a trailing comment are fine): the arm and `webconvert all` honour it; a
  per-account operator `webconvert` overrides and removes it;
- the account's opt-out of its per-instance group, `_INSTANCE_GROUP=NO`,
  which the arm and `webconvert all` honour as the web group's opt-out too;
- an account not yet on its per-instance group;
- the box not ready (above);
- www-data left anywhere in a `files` or `private` store of its sites that
  the conversion does not walk, before phase B: with no single mount point
  under `/mnt`, or with its store on attached storage owned by a user
  other than root or the account, the conversion leaves those stores as
  they are, so phase B waits until the layout is one BOA makes;
- the account's `~/static/files` a link that does not resolve (its
  attached storage not mounted, or the link changed), before phase B:
  while the storage is not mounted, no walk and no check reaches the
  store, so phase B waits until the link resolves;
- before phase B only, one of the four things the next section lists.

A frozen account (`log/proxied.pid`, a migration in flight) is skipped,
exit 4, unless an operator passes `--force`. A standby box (xmass's
`/root/.standby.cnf`, or `/root/.standby.prep.cnf` while a box is being
prepared as one) refuses every verb but `webrevert`.

### What holds phase B back

Four layouts do not stop an account from converting. It goes to phase A
like any other, and only its step into phase B waits while one of them
stands:

- a site of the account reading another account's files store (an outbound
  share);
- a site on the shared `/data/all` stores;
- any other site whose directory lies outside the account's tree (a site
  dir inside the account's store on attached storage, whether root or the
  account owns that store, is the account's own);
- a site's `files` or `private` store outside the account's own places.

A store is the account's own only as a real directory of the site, or as a
link into the account's own `static/files/` (or its store on attached
storage), as the site scripts take it, never into BOA's own folders there
(`.backups`, `.backup-exports`, `.archived`). A store link anywhere else,
even inside the account's tree, is one of the four.

The conversion leaves such a path exactly as it is: it is never walked,
moved or re-linked, its owner, group and modes stay, and it keeps working,
because in phase A the account's users and pools are still in `www-data`.
A store linked elsewhere inside the account's own tree stays in `www-data`
with everything below it. The one exception is a link to a path that holds,
or lies inside, a site or a store of the account's own: those are the
account's own web files, and the path converts with them. The account's
notes say which it is for each path: `left as it is`, or `part of the
account's own files and converted with them`. Phase B would take
`www-data` away from the pools that read a left path, so phase B waits.

What is left is the path a note names and everything below it, and it is
the conversion's own walks that leave it. A contrived layout can step
outside that: a link into the middle of an archived private store or of a
platform's `keys` directory (the conversion narrows those directories as a
whole), a link to one of the account's top directories, or a store link
that resolves inside its own site's directory, which the nightly takes for
that site's store.

Provision keeps a site whose directory lies outside the account's tree (on
the shared `/data/all` stores, or in another account's tree) in `www-data`
too. Wherever it sets a group or a group-keyed mode on such a site, it gives
`www-data` and the modes it gives an account without a web group of its
own, never `wg-oN`: its directory pass at an install and a deploy (Restore,
Clone, Migrate), the settings writers, and the Backdrop, Grav and
Textpattern writers.

On a Verify, BOA leaves the directory pass to the root site scripts, which
take the group from the path and leave a site outside the account alone.

A path is outside when its real place, all links followed, is neither in
the account's home nor in its store on attached storage. A store of such a
site that is a link into the account's own `static/files/` (or that store)
is inside, so it takes `wg-oN` as every store of the account does, and
`webrevert` walks it with the rest of the account: no path of such a site
is left in a group that no longer exists.

A provision copy older than this gives such a site `wg-oN` wherever it sets
a group. This is why the readiness check asks for the copy that carries
`provision_path_web_group`: no account converts before its copy does this.

- `webconvert <oN>`, `webconvert all` and the Octopus arm take such an
  account to phase A, exit 0. The account's notes
  (`/var/log/boa/instgrp-web.oN.notes.txt`, and a copy in its own
  `log/web-group-notes.txt`) name each path and what clears it.
- `--phase-b` on an account below phase A takes it to A and stops there,
  exit 6. A run that stops before phase A is complete (the task queue not
  drained, exit 6) is finished by the same command run again. On an
  account already at A it is refused before anything is written, exit 6,
  so a pin stays. On a box with `_WEB_GROUP_PHASE_B=YES` the Octopus arm
  is refused the same way on every upgrade of such an account, and the
  upgrade prints a NOTE.
- Each of these runs says where the account stands: `stays at phase A;
  phase B waits (...)` with a count of each kind. An account that carries
  a trait of phase B no record explains (a pool line left in a pool file;
  `webstatus` reads `betwP` or `betwK`) is not at phase A, and the NOTE
  says so: `reads betwP, not phase A ('instgrp webconvert oN' brings it
  there)`. `--phase-b` never takes such a trait back; `instgrp webconvert
  oN` does.
- Nothing clears these for you. A share is removed with the documented tool
  (`autosymlink --site <url> --apply --force-unshare`, see
  `FILES-SYMLINK.md`); a site on the shared stores or outside the account
  moves to a platform in the account's own tree; a store becomes a real
  `files` or `private` directory of its site, or a link into the account's
  own `static/files/`. The next run toward phase B then goes through.
- The tool cannot undo one share: a share of a `private` store whose owner
  runs in its own web group. That store is closed to every other account as
  a whole, so the un-share is refused, with an `[ERROR]` line that names the
  store. The two accounts settle it between them; BOA does not move the
  files for them.
- `instgrp webcheck --report` says `shares:  phase B held` for such an
  account, with a count for each of the four kinds, without running a
  conversion and without writing a note. For an account whose record
  already says phase B it says `phase B on record, not held` with the same
  counts: a layout made after phase B holds nothing back. A record left by
  a phase B rollback that could not finish (marked `rb=1`, below) still
  reads `phase B held`: the next run checks the layouts again.

A share INTO the account's store never holds anything; both accounts are
told (see `FILES-SYMLINK.md`), before the conversion's first write and
again once its private side is done. When the account that owns the store
converts, the reading site loses write there (and read on a private store),
whatever the reading account's own state.

### The verbs

    instgrp webconvert <oN> [--phase-a|--phase-b] [--force]
    instgrp webconvert all [--phase-b]
    instgrp webrevert  <oN> [--keep-enabled] [--force]
    instgrp webstatus  <oN>|aegir|all
    instgrp webcheck   [--report]
    instgrp webdrift   <oN>|aegir [--report [--deep]] [--own night] | --box

- `webconvert <oN>` takes the account as far as it already goes or to
  phase A, whichever is higher; `--phase-b` takes it to phase B; `--phase-a`
  stops at A and pins it there. The pin is `_WEB_GROUP=A` in the account's
  cnf: the arm, `webconvert all` and `all --phase-b` take a pinned account
  to A at most, a plain `webconvert` keeps the pin, and only a per-account
  `--phase-b` or `webrevert` lifts it. The migration tools carry it with the
  cnf (below), so a box the account moves to keeps it at A too.
- `webconvert all` converts every account, in three rounds so each PHP
  version is reloaded once. On a standby, and for an opted-out account
  that has no web group yet, it refuses at once, without waiting for the
  account's nightly pass.
- `webrevert <oN>` goes back the whole way: phase B undone first, then A,
  then the group removed. It writes the opt-out first (over a pin), so the
  arm does not convert the account again; `--keep-enabled` writes none and
  keeps a pin.
- Beyond the account's roots, `webrevert` walks back its store on attached
  storage when root owns it (as migratefs leaves the one BOA made in the
  home; the conversion takes it the same way, and the roots take it when
  the account owns it), and the stores of the account's sites there when
  that store is not one of the walk's roots (no single mount point under
  `/mnt`, an owner other than root or the account, or a link on the way).
  The group goes only once none of them carries it.
- Before it removes the group, `webrevert` also reads every files store of
  the account's name on a mount under `/mnt` (`<mount>/files/oN/static/files`),
  whatever the mount count or the store's owner. When the layout changed
  since the conversion (a second mount point, another owner), a store the
  conversion walked may be in none of the walks above: while it carries
  `wg-oN`, the group is kept and the message names the store and what
  clears it. A `webrevert` once the layout is back walks it and removes
  the group.
- A path under `/mnt` that no revert walks keeps the group on every
  `webrevert`: the store of a site removed since the conversion, with no
  single mount point under `/mnt` or the account's store owned by a user
  other than root or the account from the conversion on; or a copy of the
  account's store in a directory under `/mnt` that is not the single
  mount point. The message says what clears it: an operator gives those
  paths `www-data`, or the store holding them becomes the account's store
  at the single mount point (root's or the account's), which `webrevert`
  walks.
- While the account's `~/static/files` is a link that does not resolve
  (its attached storage not mounted, or the link changed), `webrevert`
  walks back what it reaches but keeps the group, and the message names
  the link: the store's paths may still carry `wg-oN`. A `webrevert` once
  it resolves walks the store and removes the group.
- `webstatus` prints what the account carries (group, members, `www-data`
  listings, pool lines, the pools' groups, the alias, the tops), the intent
  and the record, and a verdict: `NONE`, `A`, `B`, `BETWEEN(...)` naming
  what differs, or `FOREIGN` (someone outside the account holds `wg-oN`).
- `webcheck` is the readiness report above.
- `webdrift` is what the watchers read (below); `--own night` is the
  nightly's own form of it.

Exit codes: 0 done, 1 failed, 2 residue or a group kept, 4 busy or frozen,
5 not ready, or phase B waiting (`~/static/files` a link that does not
resolve, or `www-data` in a store of its sites that the conversion does
not walk), 6 refused or deferred (opted out, phase B held by a share or
by a site or store outside the account, a standby, a revert in progress, a
pin, the task queue not drained). Only `webrevert` and
`--phase-a` ever lower an account; nothing else does, whatever it finds.

The Octopus upgrade's note for an exit 2 or 5 points at
`/var/log/boa/instgrp.log`, which names the reason.

### Intent and record

Two root-only files per account say where it stands:

- the intent, `/var/log/boa/instgrp-web.oN.txt`: the level the last run
  aimed at, the `--phase-a` pin, and that run's exit code;
- the record, `/root/.oN.web-group.txt` (`wg-oN gid=<n> phase=<A|B>`): the
  level reached. The writers (the site scripts, the nightly, the pool
  writers) read only the record, and only while `wg-oN` exists under the
  gid it names.

Both stay on the box: a migration carries neither (below), and a backup of
`/root` or `/var/log` restored later can bring back a stale one, which the
watchers then report. A phase B whose final check fails is rolled back;
when that rollback cannot finish, the record keeps phase B with a mark
(`rb=1`), and the next run checks the account's shares again before it
completes phase B, so a share made in between holds phase B back rather
than being cut off.

### Watching for drift

The 3-minute limited-shell worker and the nightly read each converted
account's state against its intent and record (`instgrp webdrift`) and
raise what differs through their incident channels (the worker's
`/var/log/boa/manage_ltd.incident.log` and one mail a day per condition,
the nightly's incident mail to the box's operator address, never the
account owner). A
run killed half way, a lost intent or record, a pool line or a `www-data`
listing changed by hand, or a stale record restored all show there. The
nightly also reads the account's private set in depth (`--deep`) and runs
`instgrp reclaim` when `www-data` is back in it.

Two more conditions are raised the same way. On an armed box that is no
standby, an account that has had no web group, no intent and no record
for over a day (not opted out, not frozen for a migration) is reported
with what holds it back: nothing has converted it, for instance a box
promoted by hand from a mirror. `_WEB_GROUP=NO` in its cnf leaves such an
account alone for good; an account opted out of its per-instance group
(`_INSTANCE_GROUP=NO`) is named once in the pass's log, never reported.

An account at phase A whose phase B is held back (above), on a box with
`_WEB_GROUP_PHASE_B=YES`, gets one line a night in its own nightly log,
`/var/log/boa/daily/acct-oN-<YYMMDD-HHMMSS>.log`, with the count of each
kind:

    oN: web group: DR10 oN: at phase A; phase B waits (outbound shares 1, ...)

The nightly's pass of the account writes it; the 3-minute worker does not.
It is a note, never an alarm and never a mail. There is none while phase B
is off on the box, and none for an account pinned at A. To list the
accounts held last night:

    grep -h 'web group: DR10' /var/log/boa/daily/acct-*.log

Logs of earlier months are kept under `/var/log/boa/daily/<MM-YYYY>/`. To
read the line for one account now: `instgrp webdrift oN --own night`.

On any box, `/root/.standby.prep.cnf` standing for over three days
without `/root/.standby.cnf` is reported too: while it stands, no account
there converts.

A file uploaded into a public directory with no world read (a `0640`
upload) would be refused by nginx in phase B. The worker opens such files
on its next pass (world read and directory search added, only to a file
with one link, never in the private set). It never opens a files store
that is not the account's own (above): at phase A it says nothing about
one, at phase B it reports it. When its walk of an account runs
out of time three passes in a row it says so, and the nightly then walks
the account's public set whole (`instgrp reclaim`, after the site loop),
which also moves the worker's starting point forward.

When the worker
still finishes no pass after that (a store too large for its time bound),
the nightly repeats the walk once a week; the site loop's permissions
pass keeps each site's files store public in between.

### The master (`wg-aegir`)

The same verbs take `aegir` for the master instance: `wg-aegir`, whose
members are `aegir` and every master pool user `wwwNN`. Phase B takes the
`wwwNN` users out of `www-data` (the backend user `aegir` stays in it) and
runs the master's pools in their own groups. `webconvert aegir` holds the
master's task queue and parks the aegir crontab for its whole run. The
master is converted by an operator only; the Octopus arm never touches it.
Once converted, hostmaster's own `files/`, the site scripts and the
`/var/www` tools (Adminer, Chive, SQL Buddy, CGP) take `wg-aegir` or the
serving pool's group.

A hold left by a run killed outright, the master's or an account's, is
obeyed only while its pid is a live root process: `clear.sh` removes it
otherwise, and the queue runner then brings the aegir crontab back.

The task queue pause an account's run takes (`/run/boa_queue_stop.pid`) is
box-wide: the queue runner stops every instance's queue while it exists,
whatever its pid. A web-group run of any account removes it when its pid is
not a live root process, and its own account's hold the same way, even a run
that skips or refuses the account, as the Octopus arm's does after a killed
revert. `clear.sh` removes both on its next tick otherwise (every five
minutes).

### Migrations and standby boxes

`xoct`, `xcopy` and `xmass` carry the account's policy, the opt-out
(`_WEB_GROUP=NO`) and the pin (`_WEB_GROUP=A`), read as bash reads the
cnf. It is written into the new account's cnf on the target before its
install, so the install's own arm leaves the account alone, or stops it
at A. `xoct` and `xmass` mirror it at every later cnf merge, its removal
in any form included.

They carry neither the intent nor the record, so a revert in progress, and
a pin that is only in the intent (no `_WEB_GROUP=A` in the cnf), stay
behind. The account converts on the target by that box's own settings, and
the tools print a NOTE naming the command to run there: "after its
promotion" when the target is a standby, and a plain warning when the
target is not armed, where nothing ever converts. See `MIGRATE-XOCT.md`
and `MIGRATE-XMASS.md`.

A box being prepared as an xmass standby carries `/root/.standby.prep.cnf`
from `xmass prep-target` on: its accounts stay unconverted until the
promotion. `xmass init` first reverts, with `--keep-enabled`, every account
on the target that carries its own web group, or only its record or
intent, once its read-only gates have passed and before the datadir swap.
A pin's `_WEB_GROUP=A` stays.

The cutover's last step runs `instgrp webconvert all` on the promoted box
(`--phase-b` where it sets `_WEB_GROUP_PHASE_B=YES`), each account gated
as any first conversion, and converts the master as the box it was
promoted from ran it. `xmass post-mig` runs the same for the accounts,
which covers a promotion by hand. Both do nothing on a box that is not
armed.

`xmass init` marks the preparation mark committed once the box is a
running replica. From then on the box's own watchdog removes it as soon
as the box reads as promoted (no standby marker, no replica, the database
unlocked), so a promotion by hand without `post-mig`, or a mirror retired
by removing its marker, does not keep its accounts unconverted. A
preparation given up before that leaves the mark until it is removed by
hand, and the watchers report it after three days.

At every sync, and at `prep-target`, `verify` and `status`, `xmass` also
compares what converts on the two boxes: whether each is armed, whether
each has `_WEB_GROUP_PHASE_B=YES`, and the master's own web group. A
switch onto a box that is not armed leaves every account unconverted for
good, so a standing mirror is set as its active is.

Files a conversion on the active hands to `wg-oN` while a sync is copying
the account land in `www-data` on the standby (the group its accounts have
there), never under the active's numeric gid; the next pass maps them as
asked of the standby. A rewrite of the account's Drush alias `web_group`
keeps the file's time, so it never decides which box's copy a later sync
keeps.

## Operator notes

- Never write the literal `:users` onto an account's tree by hand
  (`chown -R oN:users …`): on a converted account that re-opens the tree
  to every other tenant until it is re-grouped, and `instgrp status`
  reports it as `DRIFT`. Use `chown -R oN:$(id -gn oN) …`, which is right
  on both models. See `FIXREPO.md`.
- Root cron lines in `/var/xdrago/cron/custom.txt` follow the same rule.
  Every barracuda upgrade rewrites a plain
  `chown [options] oN[.ftp]:users [options] /data/disk/oN[/…]` (every path
  under the account, only redirections after it) to `oN[.ftp]:$(id -gn oN)`
  before it appends the file to root's crontab, keeps the previous file in
  the dragon config store (`/var/backups/dragon/config/<run>/custom.txt`)
  and prints a NOTE. Any other form (a `chgrp`, a chown that also names
  another path, a quoted or commented line) is appended as written and named
  in a second NOTE: write it with `$(id -gn oN)`.
- What heals drift, and when: the site and platform verifies and the
  nightly re-group the paths they write; the nightly account worker also
  probes the credential-bearing paths (`~/.drush`, `~/backups`, `~/config`,
  `~/tools`, the hostmaster sites, every `drushrc.php` under `~/static`)
  and runs `instgrp reclaim` on a hit; the 3-minute limited-shell worker
  moves an identity that fell back to the box-wide primary group (a hand
  `usermod`, a restored passwd) back onto the account's group once that
  identity is no longer in use (until then its log says the move waits
  for an idle pass; a deferral that has lasted a day is raised through
  the worker's incident channel, `/var/log/boa/manage_ltd.incident.log`
  plus one mail a day per identity unless `_INCIDENT_REPORT` is OFF), and
  finishes a `revert` that left an identity on the account's group the
  same way; both tools also put back a passwd home field an interrupted
  group move left at a staging directory, retrying for ten seconds while
  the identity is in use (`status` reports such a home as INCONSISTENT
  until then); the octopus
  upgrade re-converts.

  Nothing else re-groups a tree between those. An
  account frozen for a migration (`log/proxied.pid`) is outside all of it:
  the nightly never visits it and `reclaim` skips it, so a frozen
  destination is healed only by the migration tool's own pass (below).
- Ægir backups, restores, clones and migrations need no conversion step:
  the extracting process is the account's backend user, so the restored
  files take the account's primary group. Root-run restores are different:
  duplicity re-applies the archived ownership, so `backboa`, `duobackboa`,
  `multiback` and `mybackup` re-group what they restored (and run
  `instgrp reclaim` for the account) after every restore whose destination
  resolves inside an account's tree or its relocated files store (a single
  restored file included); a restore staged anywhere else is the
  operator's to follow with `instgrp reclaim oN` once the files are in
  place.

  `backboa`, `duobackboa` and `multiback` restore a path inside an
  account's tree in a directory only root can open and then move it into
  place. Before the move they give the account what the restore wrote
  under any owner but root and the account's own identities (an archive
  from another box lands its owners' names or numbers, which here can be
  another account's), owner only: directories and single-link regular
  files, never a link, a FIFO or a hard-linked file. What the destination
  already held, or what is moved into the tree once it is in place, keeps
  its owner.
- GIDs are allocated per box from the system range, so the same account
  name has different GIDs on two boxes. rsync maps ids by name, and the
  source account's group has no name on a destination whose account is not
  converted, so a moved tree lands there in an unassigned numeric gid.

  `xoct transfer`, `xcopy transfer`, a hand-run `xmass sync --live` and
  `aegir2boa-stage2 transfer` therefore run a group pass on the destination
  after every copy (`instgrp reclaim` where the tool is installed: paths in
  no group, in `users` or in another named group take the destination
  account's group, `users` while unconverted; passed `--force`, because the
  destination's own `log/proxied.pid`, if any, is its demotion artefact
  from an earlier cutover — or, for stage2, a freeze left by a killed
  import — not an account served from elsewhere), every leg of
  `xoct`, `xcopy` and `xmass` maps the source account's group onto the
  destination account's group as it copies (asked of the destination: its
  own group once converted there, `users` until then), so a run that stops
  before its group pass, `xoct create` (which has none) and the 15-minute
  standby autosync never land a foreign gid, and none of them carry the
  conversion marker -- it recorded the source box's
  conversion.

  Where the tool is not installed, or keeps deferring behind a live BOA
  run, an inline pass over the same roots runs instead. It regroups only
  directories and single-link regular files, each through a handle that
  never follows a link. A hard-linked file or FIFO the walk changes (one
  owned by an identity of the account, see "The tool") keeps the group it
  landed with and reads as DRIFT in `status` until
  `instgrp reclaim --force` claims it; any other one is counted on the
  `other:` line, and a symlink keeps its group, never counted.

  The account's own web group travels too. While `wg-oN` exists on the
  source, every leg (the files store included) maps it onto the group the
  destination's writers give the account there: its `wg-oN` once converted
  there, `www-data` until then. The destination's group pass leaves `wg-oN`
  paths alone. `xoct`, `xcopy` and `xmass` refuse (a DENY in the dry run, a
  stop with `--live`) to move an account converted to its web group onto a
  box whose tools predate it, or whose answer cannot be read.

  `instgrp` reads a marker whose gid is not the account group's
  gid on this box as STALE (ignored), and `convert`/`reclaim` claim any path
  of the account's roots that the walk changes and that is in no group or in
  another named group.
