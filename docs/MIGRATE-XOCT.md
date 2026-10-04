# xoct — Single-Account BOA Migration

`xoct` migrates one Octopus instance at a time from a source BOA server to a
target BOA server using mydumper/myloader for database export and rsync for
filesystem transfer. Because it operates at the account level it is safe across
differing Percona MySQL versions — no replication constraints apply.

> **Renamed from xboa.** A compatibility symlink `xboa → xoct` is recommended
> so existing scripts continue to work. See [MIGRATE.md](MIGRATE.md).

## When to Use xoct

- Moving selected accounts between servers (not a full-server move).
- Migrating between servers running different Percona versions.
- Renaming an Octopus account username during migration.
- Any scenario where `xmass` (full-server replication) is not appropriate.

For full-server migrations where Percona versions match, consider
[xmass](MIGRATE-XMASS.md) instead — it cuts total downtime significantly.

## Prerequisites

- Both servers running the same complete BOA release: a full barracuda AND
  octopus run on the older one, never `system` alone. xoct does not check
  this; a target missing a central-map nginx variable that a newer release
  introduced fails the box-wide config test and takes down every migrated site.
- Root SSH access from source to target (`xmass pre-mig` or manual key
  exchange).
- No existing Octopus instance required on target — `xoct create` provisions it.
- `mydumper` / `myloader` installed on source (standard BOA dependency).
- Disk space on source: at least 1× the account's total database size free
  under `/data/disk/<oct>/src/`.
- CSF on target: source IP whitelisted (see below).

## Terminology

| Placeholder | Meaning |
|---|---|
| `source-host` | Source server FQDN (e.g. `server1.example.com`) |
| `target-host` | Target server FQDN |
| `source-ip` | Source server public IP |
| `target-ip` | Target server public IP |
| `o1` | Source Octopus account name |
| `o2` | Target Octopus account name (only in rename mode) |

## Step-by-Step Procedure

> **Every `xoct transfer …` runs a read-only DRY test by default.** It resolves the
> target's storage, prints the plan for each store (`[DRY-PLAN] … would mirror / would
> place real dir …`), pre-checks disk space (including the Solr indices, which can be
> large), and records `CLEAN` or `NOT CLEAN` — making
> **no** changes on either host. The outcome is persisted per account+target in a state
> file (`/var/log/boa/xoct.migrate.<oct>_<tgt>.state`).
>
> To perform the transfer, append
> **`--live`**; it is accepted only after a `CLEAN` dry run for the same account+target
> and refuses if the dry run reported any `DENY` (dangling source symlink, multiple
> `/mnt` mounts, a store that fits nowhere, a transfer leg such as `static/`, `log/`
> or `.drush/` that is a link, or a `static/files`, `backups` or `/mnt` link that
> resolves outside the account's own tree and store).
>
> An account converted to its own web group (`wg-oN`, see `INSTGRP.md`) is also a
> `DENY` when the target's tools predate the web group, or the target's answer cannot
> be read; `--live` then stops before it copies anything. While `wg-oN` exists on the
> source, every leg maps it onto the group the target's writers give the account (its
> `wg-oN` once converted there, `www-data` until then).
>
> Every leg also maps the account's own group (see `INSTGRP.md`) onto the group the
> target account holds (its own once converted there, `users` until then), so a run that
> stops before its closing group pass leaves nothing in another account's group; an
> answer about that group that cannot be read is a `DENY` too (the dry run is `NOT
> CLEAN`, `--live` and `create` stop).
>
> On a rename (`{o2}`) every leg also maps each of the account's identities onto the new
> name's (`o1.ftp` onto `o2.ftp`, and so on; one the target does not have yet, such as a
> client's login, onto `o2` itself), so the copy is never owned by an account the target
> has under the old name. A list of the target's identities that cannot be read, or that
> has no `o2` yet, is a `DENY` too (the dry run is `NOT CLEAN`, `--live` and `create`
> stop; re-run `create` once the target answers).
>
> **What travels of the web group, and what does not.** The account's policy travels: the
> opt-out `_WEB_GROUP=NO` and the `--phase-a` pin `_WEB_GROUP=A`, read as bash reads the
> cnf (`export`, quotes and a trailing comment are fine). `create` writes it into the new
> account's cnf on the target before the install (so the install's own conversion leaves
> the account alone there, or stops it at A), and every later cnf merge mirrors it, a
> removal on the source in any form included.
>
> Nothing else of the account's web-group state travels: its intent (a revert in
> progress, a pin made without its cnf line) and its record stay on the source, and the
> account converts on the target by that box's own `_WEB_GROUP_ARM` and
> `_WEB_GROUP_PHASE_B`. `transfer` prints a `NOTE`, never a refusal, naming the command to
> run on the target (`<dst>` is the account there, the new name on a rename) when:
>
> - the account uses its own web group here and not yet there (a target that is not armed
>   is named as one where it never converts);
> - it is pinned at phase A here without `_WEB_GROUP=A` in its cnf:
>   `instgrp webconvert <account> --phase-a` here, which writes the line;
> - it is pinned here and already at phase B there: `instgrp webconvert <dst> --phase-a`;
> - a web-group revert of it is in progress here: `instgrp webrevert <dst>`;
> - it is at phase B here and the target has `_WEB_GROUP_PHASE_B` off, so it converts
>   there to phase A only: `instgrp webconvert <dst> --phase-b`;
> - it is opted out here and the target already converted it before the opt-out reached
>   it: `instgrp webrevert <dst>` (which also writes the opt-out there).
>
> `xcopy`, which has no cnf merge, carries the policy at `create` only; its `transfer`
> names `instgrp webrevert <dst>` whenever the source is opted out and the target's cnf
> does not say so, and `instgrp webconvert <dst> --phase-a` whenever it is pinned and the
> target's cnf does not say so, whether or not the target converted the account yet. The
> account's `log/web-group-notes.txt` (what the conversion told the account on this box)
> never travels.
>
> `xcopy` maps the account's group and its web group the same way. It never renames: a
> fourth argument naming another account is a `DENY` before the account is read, the
> target is contacted or anything of the account is changed (the dry run is `NOT CLEAN`,
> every verb stops), because `xcopy` rewrites no reference to the old account name in the
> copied vhosts, aliases or panel database (its import renames only the source hostname,
> as `xoct import` does). Move an account under a new name with `xoct`.
>
> The `CLEAN` dry token is **single-use** —
> running `--live` consumes it, so one dry run cannot arm two live runs; re-run the dry
> pass before each additional `--live`. So each transfer below is a two-step: run it once
> to review, then re-run with `--live`. Only `transfer`/`pretransfer` are gated —
> `ssl-gen`, `export`, `import` and the other commands are unaffected.

Only one state-mutating `xoct` verb runs on a box at a time: `export`,
`create`, `import`, `pretransfer`, `transfer`, `proxy`, `proxy-retire`,
`go-live`, `reset-state`, `abandon`, `pre-mig`, `post-mig` and `ssl-gen` all take a box-wide
owner-PID lock, and a second run refuses loudly and non-zero, naming the live
owner's pid. `proxy-mode` stays unlocked on purpose — it writes a policy pin,
not data, so policy can be inspected or pinned during a run. The guard is
liveness-based: a run killed outright (or a reboot) wedges nothing and there
is no stale lock to clear by hand.

### 1. Prepare Target Firewall

On the **target host** — allow source IP through CSF so rsync and MySQL traffic
can reach the target during migration:

```sh
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.allow
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.ignore
csf -ra
```

### 2. Pre-migration Setup

Run `pre-mig` on **source first**, then on **target**. Each call stops BOA
background runners and handles SSH key exchange so root can SSH freely between
the two hosts.

On the source, `pre-mig` publishes root's public key on the box's undefined
vhost and prints the key's fingerprint with the exact command to run on the
target. The target fetches the key over plain HTTP, so it installs it only
with `--key-fp`: the one served key line whose fingerprint matches is added to
`authorized_keys`, tagged `# xoct migration source <ip>`. A missing or
malformed `--key-fp`, or no served key matching it, is refused before
anything is parked, and nothing is added.

A re-run adds nothing, and an untagged copy of the key already there is
tagged in place. A copy under another source's tag, behind options such as
`from=`, or commented out does not count: the tagged line is added as a line
of its own.

The runners (`runner.sh`, `owl.sh`, `usage.sh`, `graceful.sh` and
`manage_ltd_users.sh`) stay parked until `post-mig` runs on that box: `pre-mig`
writes the park marker `/run/boa_migration_park.pid`, and while it exists
BOA's five-minute tools refresh does not fetch a parked runner back. The park
lasts **at most 24 hours** — the housekeeping script drops an older marker and
the runners return on the next tick — and a reboot ends it too. Re-running
`pre-mig` re-arms it. So on the target, the upgrade `create` arms and the
creation of new sub-users run after `post-mig`, not during the transfer.

A barracuda `system` pass run meanwhile keeps the park as well: while the
marker exists it leaves a parked runner parked instead of deploying it again.
`post-mig` ends the park on that box. It restores the parked runners, removes
a stale parked copy (`.<name>.off`) of any runner a refresh had already
brought back, removes the marker and stops the box serving its published root
key.

**On source:**
```sh
xoct pre-mig source-host
```

It ends with the line to run on the target, for example
`INFO: on the target run: xoct pre-mig source-host --key-fp=SHA256:...`.

**On target:**
```sh
xoct pre-mig source-host --key-fp=SHA256:<the fingerprint printed on the source>
```

### 3. Verify SSH Connectivity

**On source:**
```sh
ssh root@target-ip
exit
```

### 4. Write freeze during the export window

Nothing to do by hand. `xoct export` already puts every site in the account
behind a 503 (`static/control/http-off.pid`), which is what actually stops
writes for the export window; the proxy step lifts it.

A move given up before the proxy step leaves the account on that 503. Lift it
on the source with `xoct abandon o1`: the sites serve from the source again,
the speed cache is purged of the 503 answers, and what export left goes with
the gate. A run that finds no gate (a second one, or after the gate was removed
by hand) clears what export left all the same and says there is nothing to lift.

The export latch (`log/exported.pid`) is cleared, so `proxy` refuses the
account until a fresh export. The panel dump (`src/*.sql`) is cleared, so that
export takes a new one. The control panel leaves the maintenance mode export
put it in.

It is refused while the sites answer, or may answer, from the target through
proxy vhosts: once the account is proxied (`log/proxied.pid`), after a
conversion xmass marked failed (`log/proxy-failed.pid`), and whenever a vhost of
the account carries either proxy template (the plain HTTP `<site>`, or the
HTTPS `https.<site>` that proxy writes beside it), since an xoct `proxy` that
fails or is killed part way stamps nothing.

Finish the proxy step instead (`xoct proxy ... --repair`), or undo it as
proxy's own revert does: put each saved `.<site>` back, remove each
`https.<site>` the proxy wrote and put a saved `.https.<site>` back in its
place, check `nginx -t`, reload nginx, and abandon then.

It is refused too while an xmass cutover holds the box, running or parked past
its freeze: resume the cutover, or follow the restore it printed. A cutover
given up before its target was promoted (its log never printed `Target MySQL
is now standalone: OK`) is closed with `xmass reset-phase syncing` once that
restore is followed.

The account a target already imported stays live there, with its sites, cron
and backups, and its client mail unless a test run holds it. Retire it there
(its `log/CANCELLED`, then `boa cleanup purge <o2>`) before a fresh move to
that box, or the import there refuses it. A test run stays open, and its
`go-live` releases the target's mail hold to that copy, so `go-live` comes only
after the copy is retired.

Run `xoct reset-state o1` here before a fresh move. This box's runners stay
parked until `xoct post-mig` ends the park (see the park above).

An older version of this runbook appended `config_readonly` / `site_readonly`
to `/data/conf/global/global-extra.inc`. Do not do that: the file is box-wide,
so it freezes every *other* account on the source as well, it is overwritten
by the next BOA system pass, and on most site shapes it freezes nothing.

### 5. Clean State and Run Shared Transfer

**On source:**
```sh
xoct reset-state o1              # clears src/*.sql + the migration pid stamps
xoct transfer shared target-ip
xoct create o1 target-ip         # add --fix-php if the target lacks a pinned PHP
xoct pretransfer o1 target-ip
```

`reset-state` replaces the hand-typed `rm -f` lines. It clears
`src/*.sql` (including `prev_hostmaster.sql`), the
`exported`/`transferred`/`imported`/`proxied`/`proxy-failed` pid stamps, the export- and
import-failure latches (`log/export_failed.pid`, `log/import_failed.pid`)
and the recorded import panel database (`log/panel_db.txt`), which is also what a **chained**
migration needs — a box that was once a target keeps a stale dump, an
`imported.pid` that blocks it from ever being an import target again, and a
panel-database pointer that belongs to the previous move.
It never touches serving state, so a site's 503 gate is left alone.

`transfer shared` syncs `/data/all`, `/data/disk/all`, `/data/disk/arch`,
`/data/disk/legacy` (when the source has one), Solr cores, `/var/www/static`, `/etc/bind`, and the usage logs under
`/var/log/boa/usage` to the target. A Solr index tree that does not fit on
the target is a **hard stop**, not a skip: each Solr home is space-checked
before its rsync and a failure refuses the run non-zero ("refusing to migrate
without its search indices") — free space on the target and re-run, rather
than discovering an index-less account later.

`create`, `export` and `pretransfer` read the account's client address
first, before the target is contacted: the words of `log/email.txt`, or,
when the file holds no plain address, `_CLIENT_EMAIL` in root's
`/root/.<o1>.octopus.cnf`, which is what the account's own Octopus pass
falls back to. They refuse two kinds of account:

- an **internal** account, whose address is one of the hosted service's own:
  `_USR o1 is not eligible for migration: internal only`. `xcopy` refuses it
  too, on every verb. A move of every account of the box carries internal
  ones too: `xmass` says so to the `create` it runs, and when you move a
  whole box account by account with `xoct` (where `xmass` cannot run, for
  example across Percona series), put `_XOCT_BOX_MOVE=YES` before those three
  verbs for such an account, as the refusal prints:
  `_XOCT_BOX_MOVE=YES xoct create o1 target-ip`.
- an account with **no plain address** in either place:
  `_USR o1 is not eligible for migration: no plain address in log/email.txt
  ('...') or in _CLIENT_EMAIL of /root/.o1.octopus.cnf`. Set the client's
  address as `_CLIENT_EMAIL` in that root file and re-run; the account's own
  file is left as it is. No stand-in address is ever put in its place.

`transfer`, `import` and `proxy` refuse neither, so a move already under way
is never stopped half way; a notice to an account with no plain address is
not sent, and the run says so (`no notice is sent`).

An account whose address is a list of several addresses is installed with
the first one (the install takes one), and `transfer` carries the account's
own `log/email.txt` over the install's copy, so the target keeps the list as
it is. The notices go to the whole list, as the account's own mail does.

`create o1` provisions the target Octopus instance **and seeds its identity**:

- **Before installing** it verifies the target has every PHP version this
  account pins — from `static/control/fpm.info`, `cli.info`, the per-site
  column of `multi-fpm.info`, every line of `cli-per-platform.info` and the
  `phpNN.info` switch that steers the command line (the highest one whose PHP
  is installed on the source). A missing version is fatal, because BOA's own
  fallback ladder would silently downgrade the pin and serve the sites on a
  different interpreter. `xoct create o1 target-ip --fix-php` instead appends
  the missing versions to the target's `_PHP_MULTI_INSTALL` and drives one
  `barracuda up-<tree> system` pass there to build them (~30 minutes).

  A `phpNN.info` switch or a `cli-per-platform.info` line that names a PHP the
  source lacks is inert there and takes effect on a target that has that PHP,
  so check both files when the two boxes carry different PHP sets.
- It installs from the **target's** BOA tree, not this box's, so a cross-tree
  migration does not send the source's tree through the target's licence gate,
  and uses `boa in-oct` rather than `in-octopus` when the source account is
  ProxySQL-wired (carrying the marker across).
- The install's welcome email is suppressed for this run, because the
  credential carry below immediately replaces the password it would announce.
  Under `admail=` (see [Test and canary runs](#test-and-canary-runs-admail))
  a create that cannot put the target's mail-suppression marker refuses
  before it installs. The runner takes that marker off when it starts a
  queued upgrade, so the install waits for a quiet target first, and says so
  if the marker was gone when the install ended (the welcome may then have
  gone out).
- **After the install settles** it merges the portable values of
  `/root/.<o1>.octopus.cnf` into the target's copy (FPM tuning knobs,
  `_CLIENT_*` plan identity, ghost-cleanup flags, `_RESERVED_RAM` — never the
  host-specific lines, which BOA re-derives correctly for the new box), force-
  copies the PHP pin files, and carries the client's shell credentials: the
  `<o1>.ftp` shadow hash paired with `log/pass.txt`, the sub-account password
  store, and each sub-user's hash and SSH keys.
- Sub-users that do not exist on the target yet converge when
  `manage_ltd_users.sh` creates them there from `clients/`, adopting the
  carried password and staged keys. While the target's runners are parked
  that happens after `post-mig`, or during `import` when it rebuilds the
  account's pinned PHP pools.
- It then verifies the pins actually took, and reports any that did not.
- It puts the account's one-pass marker on the target,
  `/data/conf/<o1>_skip_upgrade_email.txt` (root's), and `import` puts it
  again when a pass took it since. The first Octopus pass there that would
  mail the account's "Ægir Upgrade" notice sends none and takes the marker
  away: the move carries the account's setup mail along, and the client has
  what that notice says from the move. Every later pass mails as the
  account's `_SEND_UPGRADE_EMAIL` says.
- An account whose `_SEND_UPGRADE_EMAIL` is `NO` on the source gets no
  marker: no pass of it would take the marker, which would then swallow the
  first notice after the switch is turned on.

After a successful install `create` puts a root-only marker on the target,
`/root/.<o1>.migration-create.txt`, naming this box (`hostname -f`) and the
source account. It also records which account of that name it was put for:
the account's user ID on the target and the inode number and birth time of its
`/data/disk/<o1>` directory there. A refused install (the name taken, a run
lock held) stops the create before anything else runs there.

Re-running `create` on an account the target already holds skips the install
and re-seeds only, and only when that marker names this box and this account
and the user ID and directory it records are still the account's. An account
of the same name that this migration did not create is refused (`DENY: ...
already holds an account named o1 that this migration did not create`) before
anything is changed on the target, and so is a marker that cannot be read.
So is a marker left behind by an earlier account of the name: an account
made again under the name gets a directory born later (and usually its old user
ID back), and the refusal says
the marker was put for an earlier one. `boa cleanup purge` moves the marker
aside with the account's other files in `/root`.

Every `create` clears the stale control pids of the account on the target
before it arms the upgrade, but never its 503 gate
(`static/control/http-off.pid`): an account held behind one (an old active
fenced after an emergency promotion, an import that failed and put its gate
back) stays held until the import's tail or a cutover's promotion lifts it.

To converge an account that really is this migration's but carries no marker
(one prepared by hand, or created before the marker existed), put the marker
on the target by hand: the refusal prints the one-line command, which records
the account's user ID and directory as they are when it runs. Or re-run with
`--adopt`, which takes the account the target holds as this migration's and
puts the marker.

`xmass prep-target` passes `--adopt` only for the same-name
accounts its own ownership rule takes (one with no site, or one relaying to
the source; see [MIGRATE-XMASS.md](MIGRATE-XMASS.md)) and refuses the rest
before the target changes. `xcopy create` writes and reads the same marker.

`pretransfer o1` does a first-pass rsync of large data (platforms, files) while
the account is still live — reducing the time the account must be offline during
the actual export window.

### 6. Prepare Target

Nothing to do by hand: `xoct import` (step 8) stops cron the Devuan-safe way,
fixes the `cpuinfo` mode and waits — bounded, on the actual signal — until no
`barracuda`/`octopus`/`AegirSetup` job is running, instead of the old fixed
five-minute guess. `xoct post-mig` starts cron again.

### 7. Export and Transfer

**On source:**
```sh
xoct export o1 target-ip
xoct transfer o1 target-ip
xoct transfer shared target-ip
```

`export` puts a 503 on all sites in the account (`http-off.pid`), purges the
nginx speed cache, dumps each site database via mydumper and the Ægir
hostmaster database via mysqldump, and marks `exported.pid` — but ONLY when
every dump completed truthfully. A database carrying any non-transactional
table is dumped with mydumper's transactional-only mode turned off, selected
automatically per database, so a stray MyISAM table neither fails the export
nor withholds the account's export stamp. Each site dump carries the
database's triggers, stored routines and events, and the import keeps their
definer, the site's database user it creates first (see
[MYQUICK.md](MYQUICK.md#triggers-stored-routines-and-events)).

The hostmaster dump carries no GTID state of the source: it is taken with
`--set-gtid-purged=OFF` when the local `mysqldump` takes that option (a
MariaDB client, which does not, writes no GTID state anyway). A box with GTID
on (every box an `xmass` run touched) would otherwise write
`SET @@GLOBAL.GTID_PURGED` into it: the import then fails on a box that
shares that history (a move back, a failback, a second move between the same
pair, "ERROR 3546" on 8.x), and where it passes it stays out of that box's
binary log. `xcopy` dumps the same way.

The hostmaster dump must exit clean and be
non-empty, and every per-site mydumper run must exit clean AND leave its
final `metadata` marker. A site whose database the account cannot prove its own
(its drushrc `db_user` is not its `db_name`, or those credentials do not open it) is
not dumped and is recorded as a failed database.

Any failure withholds `exported.pid`, records the
failed databases in `log/export_failed.pid`, prints an INCOMPLETE verdict
and exits non-zero. The recovery is simply re-running the same `export`
after fixing the cause: site dumps are redone in place, the hostmaster dump
is kept, and the client start notice is NOT re-mailed (one notice per
account+target).

While `log/export_failed.pid` exists, `transfer` and `import` refuse the
account. `--force` on either bypasses ONLY that refusal, loudly. The latch
travels with the account transfer, so a target refuses a forced-through
partial export too; a later transfer that passed the gate cleanly clears
the travelled latch on the target. After a fully forced-through partial
migration, `xoct proxy` also needs `--force` (exported.pid was truthfully
withheld), which accepts the partial export on the same explicit axis.

An account not proxied yet, with no `log/exported.pid` and no `--force` over
a `log/export_failed.pid`, is refused by `proxy` ("not exported") before it
writes anything, an account whose only site is its panel included.

`transfer o1` rsyncs platforms, files, drush aliases, nginx vhosts, SSL certs,
and Let's Encrypt config to the target. The platform and per-site drush
aliases travel; the account's panel aliases (`hostmaster`, `hm` and
`server_master`) do not — the target keeps its own, because `import` reads
them to find the panel it imports into, and the source's copies name a panel
site and a server the target does not have. The `static/files` transfer uses a
two-pass symlink-safe method (see [Static Files Note](#static-files-symlink-handling)).

A second `transfer shared` picks up any changes to shared data since step 5.

### 8. Import on Target

**On target:**
```sh
ln -sfn $(which websh) /bin/sh
ln -sfn $(which websh) /usr/bin/sh
ls -la /bin/sh   # confirm websh
xoct import o1 target-ip
service nginx reload
xoct post-mig
service cron start
```

`import` also rebuilds the account's **pinned PHP pools** on this box.
The account arrives carrying the source's per-release FPM markers
(`static/control/.multi-fpm.<tree>.<xSrl>.pid` and
`.multi-nginx-fpm.pid`); both boxes run the same release, so without
clearing them the target treats the pool set as already built, never
creates pools for versions that exist only here, and never regenerates
the per-site socket includes — leaving every pinned site served by the
account DEFAULT pool indefinitely.

The import clears the markers, lets
the normal sweep rebuild in two passes, and then reports either
`every pinned PHP pool is live` or an `ALRT` naming each pin that is
not. Treat such an ALRT as a stop: a site answering 200 with the right
content can still be running on the wrong interpreter.

The rebuild runs twice: once before the rename, so the rename's serving
check meets pools that answer, and once after it, so the per-site socket
includes follow the renamed sites.

> **cron stays stopped until `post-mig`.** The import quiesces the
> target by stopping cron; only `post-mig` restarts it. A box left
> without it silently stops receiving fleet updates altogether. Check
> `pgrep -x cron` before you walk away.

`import` refuses before it changes anything — it exits non-zero with an
`ERROR` line, leaves cron and the 503 gate alone and stamps nothing — when
the account is not installed on the target (`create` has not run), when
`src/prev_hostmaster.sql` has not arrived, when `log/sourcefqdn.txt` is
missing (run `xoct reset-state o1`, `export` and `transfer` again on the
source), when the account's hostmaster alias names a panel site with no
`drushrc.php` on the target, or when that `drushrc.php` names no panel
database. Each of these used to skip the whole panel import silently and
still report success.

`import` refuses while the travelled `log/export_failed.pid` marks the
export incomplete (`--force` bypasses only that gate). Per-site database
loads are truthful: a transferred dump directory without mydumper's final
`metadata` marker is SKIPPED (a partial dump silently restoring an
incomplete database is the failure being guarded against), a failed
myloader run is counted, and a site whose db credentials cannot be parsed
is counted too. Each load passes `--ignore-set=SQL_LOG_BIN` when the
installed `myloader` lists it, so it is written to the binary log and
reaches a replica of the target (see
[MYQUICK.md](MYQUICK.md#imports-are-written-to-the-binary-log)).

One exception keeps mixed accounts importable: a site with
no transferred dump whose database on this box is **already populated** is
a target-native site (the account's own pre-existing dedicated site is the
common shape) and is left as-is, not counted as a failure — only a site
with neither a dump nor a populated local database counts.

Sites with a counted failure do NOT get their `verify`
scheduled; clean sites import and verify normally. Any counted failure
writes `log/import_failed.pid`, prints an INCOMPLETE verdict naming the
databases and exits non-zero — the printed recovery re-runs the full
import from the same transferred dumps after the cause is fixed.

`import` first resolves which panel database to import INTO. The runner park
holds the enforced post-install upgrade `create` armed until `post-mig`, but
when the park lapsed or was never taken on the target, that upgrade rebuilds
the dest account's panel between `create` and `import`. It replaces the panel
database and leaves the on-disk alias naming the dropped one — pouring the
dump into a nonexistent database. So the alias-derived name is validated
against the live database set, and when it is gone the live panel database
is rediscovered the same way the `xmass` cutover does.

A previous partial run
is picked up too: a database already carrying the source panel front is
resumed into rather than abandoned, and the winning name is recorded under
`log/panel_db.txt` so a re-run is deterministic. The dump import is checked;
a failure aborts before anything is renamed.

`import` then re-imports the Ægir hostmaster database, keeping the panel
front page the dump carries (a front-page node included), and reconciles the
panel platform, which
absorbs distro-number drift: the imported database names the SOURCE's
hostmaster platform path, while the target account's live panel usually sits
on a different `aegir/distro/NNN` (the panel platform is rebuilt whenever
the PHP pin changes, and retired platform trees keep their code, so code
presence at the imported number proves nothing).

The import locates the
target's unique live panel — the site dir carrying `drushrc.php` +
`settings.php` on a code-bearing platform — and repoints the hostmaster
platform row in the imported database before the rename runs, so the rename
queue's DB-derived regeneration lands on a platform that really serves. If
that live panel's stored credentials still name a replaced database, they
are rewritten to the database actually holding the import (with a fresh
password) — `renameaegirhost` reads those files to find the Ægir database
and cannot bootstrap otherwise.

An unresolvable panel (zero or several
candidates, or a repoint that matches no row) aborts the import with
recovery steps rather than completing with a dead control panel.

The imported panel names the source's login for its database server. Before
the rename, `import` gives that row the account's own name on this box (the
new name on a rename) and the password this box set for it
(`.<o1>.pass.txt` in the account root, `.<o2>.pass.txt` on a rename), so
every server verify, the rename's first, connects. When that file cannot be
read, or its first line is not nine or more of `A-Za-z0-9+/=%@._-`, the row
still takes the account's name, an `ALRT` says so, and the server verifies
fail until the account's next Octopus pass sets the password.

Before the rename, `import` loads every site's database and creates its
database user (the per-site checks above), rebuilds the account's pinned
PHP pools and lifts the export's 503 gate (`static/control/http-off.pid`).
The rename's task queue verifies every renamed site, which needs the site's
database user, and its serving check then probes each one, which needs a
live pool outside the gate.

The verify of each cleanly loaded site is scheduled after the rename, under
the site's name on this box. Where the panel's hosting module knows how, the
verifies wait up to ten minutes in all for the rename's own tasks to finish
first, and each one after that waits 30 seconds; without it each waits 30
seconds. A verify still waiting then is left queued and runs after `post-mig`.

A site is known across the rename by its directory: one the load did not see
(or whose site_path it could not enter) is loaded and verified then. A site
loaded before the rename but not found after it, and a site whose site_path
could not be entered before the rename and is not found after it, count as a
failed import. A failed rename puts the 503 gate back.

With the panel reconciled and the sites loaded, `import` calls
`renameaegirhost --aegir-root /data/disk/o1 --force-old source-fqdn` (the
source hostname was recorded at export time; the target's own
`server_master` alias names the target, so the rename never reads OLD from
an alias) which:

- Rewrites all drush alias files (old source hostname → target FQDN).
- Rewrites and renames nginx vhost files.
- Renames the source hostname inside the Ægir DB with serialize-safe,
  targeted statements (a plain dump is taken first, as a backup only).
- Reloads nginx.
- Runs the Ægir task queue **5 passes** (cc drush + server_master verify +
  server_localhost verify + hosting-dispatch + hosting-tasks) to regenerate
  all aliases, vhosts, and db-host entries from the updated database.

`post-mig` restarts Solr and nginx, restores BOA runner scripts and removes
the park marker. The restored runner then consumes the upgrade `create`
armed, which now runs on the imported account, and `manage_ltd_users.sh`
creates any sub-users still missing.

### 9. Enable Proxy on Source

**On source:**
```sh
xoct proxy o1 target-ip [--proxy-mode=temporary|permanent|ha-switch] [--deadline=YYYY-MM-DD|+Nd|--no-deadline]
service nginx reload
xoct post-mig
```

`proxy o1` resolves the account's proxy mode (explicit flag, else the
account's own **source-role** record set with `xoct proxy-mode`, else the box
default in `/data/conf/migproxy_mode.txt`, else `temporary` with a loud
warning — an inbound *target-role* record left by the migration that brought
the account onto this box is never resolved as this box's proxy mode, so a
chained move follows the operator's flag or the box default rather than the
previous migration's mode and deadline), writes
the policy record on both ends (`log/migproxy.cnf`, root-owned, parsed never
sourced), wires the migration-proxy trust on the **target** (nginx realip
recovery + CSF whitelist of this source's IP, `--permanent` for
`permanent`/`ha-switch`), converts all nginx vhost files for the account to
proxy templates that forward traffic to `target-ip`, removes `http-off.pid`
(sites return to 200 responses, now proxied), and sends the mode-selected
migration-complete notification to the account owner.

A failed conversion
sends nothing, stamps nothing and exits non-zero.

The account's **control panel is never proxied**. It is identified by what it
is — the `site_path` of the hostmaster alias — not by which alias files exist,
keeps its local vhost, and is put into Drupal's own maintenance mode once the
conversion is in: it stays online on the old box as a monitoring canary, an
admin can still log in, and nobody else can queue tasks against a database
that now lives on the target. The target does not serve a source-named panel,
so a proxied panel would only ever answer the new box's catch-all page.

A
panel an earlier conversion had proxied is restored from its saved dot-file
copy on the next `proxy` run. The legacy `<panel-fqdn>.alias.drushrc.php`
symlink to the hostmaster alias, which used to make the panel look like a site
to this tool, is purged by BOA's regular ltd-users pass on every box; an
account that still depends on it must be repaired **before** it migrates.

In the same breath as stamping `proxied.pid`, `proxy` **parks the converted
account's Ægir dispatcher** (moved into BOA's own off-run directory). Without
it a single dispatcher tick runs the account's queue, whose pending Verify
regenerates the site vhosts straight from the database and silently
un-converts the proxy — the old box then resumes serving its own stale copy.
`xoct post-mig`, which restores runners, re-parks any account carrying
`proxied.pid` instead of handing back the dispatcher that would undo the
proxy; the same reasoning governs a later restore, see
[PX0-XTRIM.md](PX0-XTRIM.md).

An account whose conversion failed at an `xmass` cutover carries
`log/proxy-failed.pid`, which keeps its dispatcher parked, makes octopus skip
it and holds back the usage notices until the repair; the successful `proxy`
run that repairs it removes the marker. It never travels with a transfer, an
`import` clears one that did, and `reset-state` clears it with the other
migration stamps.

The completion reload is configtest-gated: if `nginx -t` fails, a first
conversion reverts **both halves** of every vhost it rewrote — the plain HTTP
vhost from its dot-backup (`.<domain>`) and the site's real HTTPS server
block, which the conversion saves as `.https.<domain>` before overwriting it
(first copy only, so a repair pass cannot destroy the original) — so
"reverted to the pre-conversion vhosts" means TLS is back too, not just that
nginx parses.

A `--repair` (where the saved copy is the pre-migration
original, not the working proxy vhost) refuses and says exactly why restoring
it would be wrong. Either way nginx is never reloaded into a broken config.

An HTTPS proxy vhost is written only when **all three** files its template
references exist — the account's `ssl.d/<domain>/openssl.key` and
`openssl_chain.crt`, plus the Let's Encrypt `tools/le/certs/<domain>/chain.pem`
— because nginx refuses to load a server block whose certificate file is
missing and the proxy render is box-wide, so one partial certificate
directory would fail the configtest for the whole conversion. A site missing
any of the three is counted and **named with the missing files** rather than
skipped silently; re-run with `--repair` once the material exists.

Both proxy templates forward `/.well-known/acme-challenge` to the target, which
is what lets the target issue certificates for names that still resolve to the
proxy. One vhost is not proxied at all: when `xmass` drives the conversion, a site
named under the source box's own hostname, which the cutover renamed on the
target, answers a `301` to its new name over HTTP and HTTPS.

The redirect needs both hostnames, which `xmass` hands over in the
environment (`_XOCT_TARGET_FQDN`, `_XOCT_MY_FQDN`; there is no flag). A later
run keeps it without them: when the account already answers a renamed site
with a `301`, or still holds sites on the per-host gate after a
`--defer-host-named` pass, `proxy` reads them itself — this box's panel
hostname (the server alias's `remote_host`, else `hostname -f`, the lookup
`xmass` uses) and the target's `hostname -f` as it answers now, after
learning the target's host key.

So a `--repair` (with or without
`--renotify`) or the `--repair --retarget` after a failover keeps the old names
answering a `301`, re-pointed at the new box's names. The run refuses before it
changes anything when it cannot: a target that does not let this box in gets
the same remedy as a refused retarget, and one that answers without a usable
name gets the command's prefix to set by hand. Names handed over in the
environment must be hostnames too.

Repair and repoint (the tool names the flag when you need it):

```sh
xoct proxy o1 target-ip --repair              # rebuild the proxy vhosts; mails only if the promise changed
xoct proxy o1 new-target-ip o2 --repair --retarget   # repoint to a new target; releases trust on the old one
```

A retarget the new target refuses (`peer <ip> did not accept the record`, with
what its ssh said) enumerates the three things to check ON that box before
re-running here: this proxy's root key in its `authorized_keys`, `csf -a` for
each of this box's addresses, and free disk under `/data/disk` (the record
write is fail-closed on a truncated file). After a failover the usual cause is
the first two: an `xmass cutover` carries the demoted box's inbound proxies'
reach forward at promotion (its step 15.95), an older cutover did not.

Never
pre-wire the SERVING trust by hand for this — `xoct` wires it itself once the
push lands, and a hand-wired entry is one no record accounts for.

Policy without re-running a migration:

```sh
xoct proxy-mode --all                         # the table: mode, deadline, scope, peer, last told
xoct proxy-mode o1 permanent                  # pin one account (wins over any box default)
xoct proxy-mode o1 temporary --no-deadline    # pin one account with no end date
xoct proxy-mode --all temporary --deadline=+30d   # box sweep; never overwrites pins (--force-pinned overrides)
xoct proxy-retire {o1|--all} [--deadline=+14d] [--no-notify]   # mark retired + send the withdrawal notice; --all skips an already-retired account by name
```

Every policy change is pushed to the target's record and re-reconciled there,
so the target's teardown decision follows the promise; the client is mailed a
short follow-up whenever the promised arrangement changes (`--no-notify`
suppresses and logs, `--renotify` forces). A retired record keeps the
withdrawal date it promised as `_MIG_RETIRE_DATE` (the table's deadline
column shows it on retired rows), so the date stays readable after the
proxy policy itself is gone.

The deadline resolves per account. A date the account's record holds wins,
and so does an explicit `--no-deadline`, which the record keeps as `none`
(`_MIG_DEADLINE=none`, on both ends of the pair); only a record with no
deadline at all, or an account with no record yet, takes the box default in
`/data/conf/migproxy_deadline.txt`.

A later `proxy-mode` or `proxy` run
without a deadline flag keeps what the record holds (a switch to
`ha-switch` keeps a `none` but drops a date, which leaves the deadline
unset), `--deadline=` replaces it, and a `--force-pinned` sweep
replaces a pinned mode but keeps its deadline unless the sweep carries a
deadline flag itself. `proxy-retire` clears it, so a mode declared after a
retirement takes the box default again. The table shows `none` for an
explicit no-deadline and `-` for an unset one.

`post-mig` restores BOA runner scripts on source, removes the park marker,
stops serving the root key `pre-mig` published and reconciles migration-proxy
trust from the policy records (a quiet no-op on a box holding none).

### 10. Update DNS

Update DNS A records for all sites in `o1` to point to `target-ip`. Once DNS
has propagated, traffic flows directly to the target without the proxy hop.
Remove the source CSF whitelist entry added in step 1 after the proxy is no
longer needed; the target side is handled by `xmass post-mig` /
`migration_proxy_trust.sh reconcile` per the account's proxy mode.

---

## Test and canary runs (`admail=`)

A migration mails the account's client: the start notice at `export`, the
completion notice at `proxy`, a follow-up when the proxy arrangement changes
and the withdrawal notice at `proxy-retire`. The target's Octopus passes
after the move can mail the client too (the upgrade notice, the usage
reports). A test or canary run of a real account must not. Add
`admail=<address>` to every verb of that run, anywhere on the line (the
token `boa in-octopus` takes):

```sh
# on the source
xoct create o1 target-ip admail=you@example.com
xoct export o1 target-ip admail=you@example.com
xoct transfer o1 target-ip admail=you@example.com          # the dry run
xoct transfer o1 target-ip --live admail=you@example.com
# on the target
xoct import o1 target-ip admail=you@example.com
# on the source
xoct proxy o1 target-ip admail=you@example.com
```

`pretransfer` takes it the same way. The other steps of the procedure
(`pre-mig`, `transfer shared`, `post-mig`) are box-wide and take no token.

- Every client notice of the run goes to that address alone: no copy to the
  client and no operator copy. The notice line ends with `(admail=; the
  account's own address was not mailed)`.
- The send is logged in `log/migproxy.log` as `testmail`, never as `mail`: a
  later real run still sends its own start notice, and the policy table's
  "last told" column and the follow-up rule read only what the client was
  really told. A policy follow-up under `admail=` therefore goes out only
  with `--renotify`, unless the client really was told something before.
- `create` installs only with the install's own welcome mail held back, and
  refuses before installing when it cannot hold it back.
- `create` and `import` switch the account's upgrade notice off on the target
  (`_SEND_UPGRADE_EMAIL=NO` in `/root/.<o1>.octopus.cnf` there): the move
  brings the account's setup mail along, and every Octopus pass there after
  the first would mail the notice to the client. A `create` that cannot
  switch it off refuses.
- `create` holds the target's client mail for that address, before it
  installs: `/data/conf/client_mail_hold.txt` (root's, one plain address)
  makes BOA's own senders on that box deliver every mail addressed to a
  client there instead, the usage reports and the pass reports included.
  `import` under `admail=` holds its own box's the same way. A hold already
  there for another address is left as it is. The hold is box-wide: every
  account the target serves is held while it is there.
- The accounts keep their own addresses.

`admail=` must hold one plain address, or the run refuses and names what it
got: a letter, digit or underscore first, and a domain that starts with a
letter or digit, the form the reader of the mail hold below takes too.
`--no-notify` is different: it sends nothing (logged as `skip`).

**The run is recorded, so a forgotten token cannot mail the client.**
`create` under `admail=` writes the address to
`/data/conf/xoct_admail.<o1>.txt` (root's) on the source, with a second line
marking it as the source's, and to the same file for the installed account on
the target; `import` under it writes the target's too. While the record exists on a box, every `xoct` verb for that
account there refuses to run without `admail=`, naming the recorded address:
`create`, `export`, `pretransfer`, `transfer`, `proxy`, `proxy-mode` and
`proxy-retire`. The re-run lines `xoct` prints after a failure carry the
token.

A record already on the source is left as it is: an account that came to
this box in a test run still open keeps that run's record when this box
moves it on, so the box's mail hold still counts it until that run goes
live.

`xmass`'s record of a test run of the whole box
(`/data/conf/xmass_admail.txt`) holds every `xoct` verb on the source the
same way, for every account, and so does its mark on the target
(`/data/conf/xmass_test_run.<source-hostname>.txt`) there.

`import` is the one verb that does not refuse: on an account the record
names, it switches the upgrade notice off by itself. On the target, every
cnf merge (`create`, each `transfer --live`) keeps the upgrade notice off
while the record is there, token or not.

`proxy-retire` on the source, and `proxy-mode` on either box, mail a client
only when the box's migration log shows it was really told of the move (a
`mail` line, never `testmail`). `proxy-retire` also counts an account
converted before the log recorded its notices as told. After a test run no
withdrawal or follow-up reaches the client, whatever the token.

On the source only a line naming a box this box moved the account to
counts: this move's target, and every target a `proxy` of it from this box
named, so after a retarget the notices naming the target before it still
count.

A line naming this box never does: `log/` travels with the account,
so a box that was the target of an earlier move holds that move's notices,
which name it.

Nor does the line a `proxy-mode` run here writes while this box is the
target (`set-inbound`), which names the box the account came from, nor a
notice sent from here as the target: `proxy-mode` logs it `change-inbound`
and `proxy-retire` logs it `retire-inbound`. Neither counts when this box
moves the account on, back to that box included (a failback). A notice an
older `xoct` sent there was logged `change`, and that one still counts if
this box later moves the account back to that box.

On a standing `xmass` pair the account's `log/` rides every sync pass from
the active to the mirror (a copy newer on the mirror is kept), and
`log/migproxy.log` with it. After a switch the promoted box holds the log as
it stood at the last pass; the lines the cutover writes on the old active
after that pass (the `set` line naming the promoted box, the switch's own
notice) stay on the old active.

`proxy-retire` on the target mails the client: the source sends the
notices, so the target's log never shows one, and a retire there is the
route when the source is gone for good. A test run is refused there by its
record, by `xmass`'s mark and by the box's mail hold.

A box that holds its clients' mail takes no real run: without `admail=`,
every verb but `import` refuses while `/data/conf/client_mail_hold.txt` is
on this box, and `create`, `pretransfer`, `transfer` and `proxy` also while
it is on the target, naming it. `import` says so and goes on. The read of
the target's hold gives up after 15 seconds on a target that does not
answer, and the verb goes on to its own contact, which reports it. `xcopy`
reads the target's hold the same way.

**A canary goes live** with one verb on the source:

```sh
xoct go-live o1 target-ip [o2]
```

It removes the records on both boxes, and the hold on each box where it
holds the canary's address and no other test run is recorded there (the
record of another canary that came to that box, an `xmass` test run's mark).
A hold go-live keeps is named with the test runs it counted.

The record of a canary that box moves away does not count: that client's
mail is held on its own target. One that came to that box in a test run
still open counts until that run goes live, also while the box moves it on.

It sets `_SEND_UPGRADE_EMAIL` on the target back to the source's value (with
`NO` it also removes the one-pass marker there), and, once the account is
proxied, sends the client the completion notice it never received (the
`proxy --repair --renotify` path).

Several canaries on one target share its hold: the go-live of each sends
its completion notice, and the hold stays until the last test run recorded
there ends, so the moved client's mail from that box stays held until then.

Without `o2` the target account is the one this move's proxy policy record
names (written by `proxy`), else `o1` when the target holds a create marker
naming this box and `o1`. Otherwise go-live refuses before anything changes
and asks for `o2`: before `proxy` a renamed canary has no policy record of
this move, the target's own `o1` is another account, and a test-run record of
`o1` there can be another box's canary.

The target goes first; a run that cannot reach it changes nothing on the
source. A re-run is a no-op: it sends nothing more and names a hold kept for
another test run again. It refuses `admail=`, and refuses while `xmass`'s
record of a whole-box test run is on the source (`xmass go-live` ends that
one, see [MIGRATE-XMASS.md](MIGRATE-XMASS.md)). `reset-state` keeps the
records.

`xcopy` takes the same token; it sends no notices of its own, so it acts on
`create` (the upgrade notice, and a refusal when the welcome mail cannot be
held back) and `import` (the upgrade notice). Every `xcopy create`, test or
real, installs with the welcome mail held back and puts the one-pass marker,
as `xoct create` does.

`xcopy` keeps no record and puts no hold: nothing could tell when a hold it
put may go. A real `xcopy` (no `admail=`) refuses `create`, `pretransfer`
and `transfer` while the target holds its clients' mail, as `xoct` does, and
`import` says so. A test copy whose target must not mail the client needs
the hold put there by hand, and removed when the test ends (see "Holding
client mail on a test box" in [MIGRATE.md](MIGRATE.md)).

A copy made under `admail=` keeps `_SEND_UPGRADE_EMAIL=NO` in
`/root/.<o1>.octopus.cnf` on the target until you set it back there, once
the copy serves for real; the first pass after that sends no upgrade notice
(the one-pass marker). `xmass` takes the token on `prep-target` and
`cutover` and keeps a record of its own, see
[MIGRATE-XMASS.md](MIGRATE-XMASS.md): the `xoct create` runs it drives put
none of these.

## Optional: Account Rename Mode (o2)

Pass a fourth argument to migrate from account `o1` on source to account `o2`
on target. Use the same `o2` value consistently across all commands:

```sh
xoct create o1 target-ip o2
xoct pretransfer o1 target-ip o2
xoct transfer o1 target-ip o2
xoct import o1 target-ip o2
xoct proxy o1 target-ip o2
```

- `o1` = source account name
- `o2` = target account name (must not already exist before `create`)
- `transfer shared` does not use `o2` — it is not account-specific
- The account's path references (`/data/disk/o1`, `/home/o1.ftp` and the
  FPM `$user_socket` token) in its Drush aliases and its nginx and `ssl.d`
  config are rewritten to `o2` automatically during transfer, and each
  `static/`, `distro/`, `config/`, `tools/` and `clients/` link naming the source
  tree is made again pointing at `o2`, by the link's own owner (root's by root); a
  link its owner cannot make
  there, or one in the root group that root does not own, keeps its old
  target and is named in an `ALRT` line
- What the source account's identities owned is handed to `o2` and
  `o2.ftp` during transfer, in one walk per owner over the account tree,
  the `.ftp` home and the account's part of the attached store. A hard link
  to another file is never handed over, and a link is made again by its
  new owner. A directory swapped for a link or another directory while the
  walk runs is not entered and is named in an `ALRT` line
- `import` also moves the ACCOUNT axis inside the imported Ægir DB (via
  renameaegirhost `--old-account/--new-account`): the control panel identity
  becomes `o2.<target-fqdn>` (adopting the fresh install's panel site dir and
  its valid credentials), and `/data/disk/o1` paths in platform, git, backup
  and package records become `/data/disk/o2` — otherwise the first DB-driven
  regeneration after migration would re-stamp the stale source paths over the
  transfer-time fixes. Customer-site URIs are never touched: a site living on
  the account subdomain (e.g. `shop.o1.<fqdn>`) keeps its name.
- The account rename also carries the shell/FTP login name (`o1.ftp` →
  `o2.ftp`) on the credential lines of the account's stored welcome mail, so
  the on-disk credentials copy — the file you are pointed at when a send
  fails — is consistent with the new account rather than naming the retired
  one.
- A mistyped or unknown `--flag` on `create`, `transfer`, `pretransfer`,
  `import` or `proxy` is a **hard error**, precisely because on those verbs
  the next free positional argument is this rename value — a silently
  consumed flag would have become a rename instruction. `proxy-mode` and
  `proxy-retire` refuse an unknown flag the same way.

---

## Static Files Symlink Handling

Some BOA systems store `static/files` as a plain directory on the root partition;
others relocate it (with [`migratefs`](MIGRATEFS.md)) to a symlink onto attached/extra
storage. During `xoct transfer`, the tool places the store on the target according to
**the target's own disk reality** — never blindly onto the target root, which may be
too small — and never uses a blanket `rsync --copy-links`:

1. Syncs `static/` with all symlinks preserved, excluding `static/files` (a
   `static/` that is itself a link is refused with a `DENY`).
2. Resolves the source `static/files` to its real directory — the account's own tree
   or its own part of the attached store (`<mount>/files/<account>/`); any other
   target is a `DENY`.
3. Detects whether the **target** has a single attached mount under `/mnt`, then:
   - **Target has a mount** → the contents are **mirrored** onto the target mount at
     `<mount>/files/<account>/static/files`, and `static/files` on the target becomes a
     **symlink** to it — even if the target root has room. This keeps a large store on
     dedicated storage and off the root partition.
   - **Target has no mount** → the store is **de-referenced** into a **real directory**
     at `static/files` on the target root.
   - A source that was a **real dir** on root stays a real dir on the target root (the
     target mount is used only as a fallback if root cannot fit it).

Site-level symlinks (`sites/*/files`, `sites/*/private`) stay symlinks and resolve
either way, because they point at the account-relative `static/files` path, not at any
`/mnt` path. The shared archive `/data/disk/arch` (and any other legacy `/mnt`-anchored
symlink) is handled by the same rule, so SQL dumps and cluster backups transfer
correctly in every source/target storage combination.

On a move that renames the account, the transfer re-points every link under `static/`,
`distro/`, `config/`, `tools/` and `clients/` that names the source account's tree
(`/data/disk/o1/...`) at the new account's (`/data/disk/o2/...`), each made again by its
own owner (one that cannot be made so is left and named in an `ALRT`).

A site's `files` and `private` links, on a tenant platform under `static/` or a
BOA-built one under `distro/`, then name the moved store. A Let's Encrypt site's
certificate links (`config/ssl.d/<site>` and `config/server_master/ssl.d/<site>`, and the
`openssl.*` links in `tools/le/certs/<site>/`) name its certificate in the new account's tree
(`/data/disk/o2/tools/le/certs/<site>`), and a client's site links name the site's directory
there. A link naming anything else is left as it is.

> **BOA supports a single attached mount under `/mnt`.** The migration tools refuse a
> target (or source) that has more than one.

### Verification (Recommended for Large Accounts)

**On target, after import** — `static/files` is a real directory when the target has no
attached mount, or a symlink onto the target's mount when it has one; **both are
correct**. What matters is that the contents are present (not a dangling link) and the
site-level `files`/`private` stay symlinks:
```sh
# static/files: real dir OR symlink into the target's /mnt mount — both OK
ls -ld /data/disk/o1/static/files

# contents must be present (real files, never an empty/dangling target)
ls -A /data/disk/o1/static/files/ | head

# site-level files/private remain symlinks either way, on tenant platforms
# under static/ and on BOA-built ones under distro/
find /data/disk/o1/static/platforms /data/disk/o1/distro -path '*/sites/*/files'   -type l | head
find /data/disk/o1/static/platforms /data/disk/o1/distro -path '*/sites/*/private' -type l | head
```

Replace `/data/disk/o1` with `/data/disk/o2` if rename mode was used.

On a renamed move, no link in the account may still name the source account's tree (`o1` the
source's name here, `o2` the new one); this prints nothing:

```sh
find /data/disk/o2 -type l -lname '/data/disk/o1/*' | head
```

---

## Notes

- **Client mail on a test target:** the target's own Octopus, nightly and
  usage passes mail the account's client. While
  `/data/conf/client_mail_hold.txt` holds one address, BOA sends that mail to
  it instead; see "Holding client mail on a test box" in
  [MIGRATE.md](MIGRATE.md).
- **Chained migrations (a former target becomes a source):** a completed
  `xoct import` starts a fresh migration lifecycle on the new box — the
  source-role latches that travelled inside the account's `log/` tree
  (`exported.pid`, `transferred.pid`, `export_failed.pid`) are cleared in the
  same breath as stamping `imported.pid`, so a box that has just received an
  account can be a source for the next leg without hand-clearing them.

  What
  is deliberately left behind: `src/prev_hostmaster.sql` and
  `log/imported.pid`. With `prev_hostmaster.sql` present,
  a new `xoct export` does NOT write a fresh dump (the dump step is gated on
  its absence, protecting a dump a pending import still needs) — so a
  chained transfer would ship the STALE dump from the earlier migration.
  `imported.pid` additionally blocks the account from ever being an import
  target again. Before exporting a former target onward (target-of-target,
  or migrating back), run `xoct reset-state o1`.
  `log/sourcefqdn.txt` needs no such cleanup — it is rewritten in lockstep
  with every dump, so it can never go stale independently of
  `prev_hostmaster.sql`.
- **What the client keeps.** Their Ægir panel login, SSH/SFTP password and SQL
  password all carry over, as do the main account's SSH keys and every
  sub-account's password and keys. The migration mail says so; if you change
  the carry behaviour, change that copy in the same work-unit.
- **Drupal 6 IP blocking:** for D6 sites that block by IP, whitelist `source-ip`
  at `/admin/user/rules` (Host rule, Allow type) before migration, or flush
  the `{access}` table via Chive afterwards.
- **Idempotency:** most pid-gated steps are safe to repeat after a failed run;
  remove the relevant `*.pid` file under `/data/disk/o1/log/` to force a step
  to re-run.
- **Internal accounts:** a move of one account refuses an internal account (the
  hosted service's own address) and one with no plain address in
  `log/email.txt` or in root's `_CLIENT_EMAIL`, at `create`, `export` and
  `pretransfer`, before the target is contacted (see step 5). Otherwise
  eligibility is the presence of the required log files and the absence of
  `CANCELLED` and of the already-done pid files. `xmass` carries internal
  accounts with the rest of the box, and `_XOCT_BOX_MOVE=YES` does the same
  for a whole box moved account by account with `xoct`.
- **xmass calls xoct:** when `xmass cutover` converts source accounts to proxy
  vhosts, it calls `xoct proxy` internally. No manual invocation is needed in
  that flow.
- **`ssl-gen` reports only what it really wrote:** it creates the nginx
  `pre.d` config directory if the master is missing it (inheriting the
  parent's ownership), refuses the domain by name if it cannot ("NO proxy
  config written"), and reports a proxy config as created only when the file
  is actually non-empty on disk — so a run that reports success really did
  write proxy config.
- **Proxy protocol (HTTP/1.1 to origin):** the proxy vhosts `xoct proxy`
  generates talk **HTTP/1.1** to the origin (`proxy_http_version 1.1`), not
  nginx's default HTTP/1.0, so the origin sees the real request protocol and
  modern semantics (chunked streaming) apply. This is **not migration-only**:
  the same proxy templates back the local LE-enabled proxy that fronts the Ægir
  Hostmaster control panel and Adminer over HTTPS. It also keeps the origin's
  HTTP/1.0 registration-spam guard from false-flagging legitimate proxied access
  — which would otherwise all arrive as HTTP/1.0 at the origin — see
  [ABUSE-GUARD.md](ABUSE-GUARD.md).
