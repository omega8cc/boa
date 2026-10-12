# Database broker — `boa-dbctl`

Every Octopus account has an instance database user named after the account
(`oN`). Out of the box it holds every privilege on every database of the
server, with the grant option: anything that runs as the account in a backend
task can read and change every other account's databases.

`boa-dbctl` (`/usr/local/bin/boa-dbctl`) is a root tool that takes those rights
away from an account and does, on its behalf, the few things that needed them:
creating, dropping and reserving its databases, granting and revoking its site
users, the verify probes, the fast (mydumper) dumps and loads, and the
migration-source read grants. An account it serves is **switched**. Its
instance user then holds rights on its own databases only, no global privilege
and no grant option, and its tasks reach the broker through `sudo -n`.

It ships **switched off**. Nothing changes for any account until an operator
switches it on, and the commands below are what an operator runs.

In this release `scope oN on` switches no account, forced or not, a new
account's switch and a pass's switch (`--pass`) included, and `baseline
settle` settles nothing: each refuses with `ERR 7 not-released`, unless the
box is a test server that carries the marker
`/root/.tenant-isolation-test.cnf`. A later release lifts that.

`plan`, `off`, `status` and an account already switched work as described
below, with one exception: `scope oN on` run again on a switched account,
which the remedies below use, is refused too outside a test server with the
marker.

## The switch

An account is switched while a root-owned control file exists for it:

```
/data/conf/oN_db_broker.txt   (root:root 0644, no one else may write it)

server=@server_localhost      the one database server context it covers
rows=localhost,%,192.0.2.10   the instance user's rows in use
kept=192.0.2.10               rows of rows= kept only for the stored objects they define
since=2026-10-01T12:00:00Z
```

`kept=` is the broker's own: provision and the Extras read `server=` and
`rows=` only. Only the broker writes it; never name there a row the account's
logins use: a `kept=` row that defines nothing is dropped at the next rotation.

Provision reads the same file: without it, or with a file that is not valid (a
link, another owner, writable by others, no valid `server=` or `rows=`), the
account's tasks take the direct path exactly as before, and the broker refuses
the account's calls (`ERR 8 not-in-broker-mode`). Every site on any other
server context (an Aegir additional database server, for example) keeps the
direct path whatever the file says.

Each switched account's databases are entered in the broker's registry, the
root-only table `boa_dbreg.owners`: one row per database, the database name its
key, so two accounts can never hold the same name. No account login is ever
granted anything on that schema.

Not served, and refused by `scope`: an account on a remote database server, an
account behind ProxySQL, a database cluster.

## Before the first switch on a box

The broker will not switch an account (unless forced) while anything on the
server could hand it its former rights back. It reads every login, every grant
row and every stored object of the server and judges each one:

| What | Belongs when |
|---|---|
| The server's own logins: `root` at `localhost`, `127.0.0.1`, `::1` and the box's own address; `aegir_root` at `localhost` and `%`; the master panel's database user at `localhost` and `%`; `mysql.session`, `mysql.sys`, `mysql.infoschema`, `percona.telemetry` and `debian-sys-maint` at `localhost` | proven, and kept in the box's baseline (below) |
| An account's instance user and current panel user | at a host its logins use; while the account is not switched, proven by a login with the credential its own files hold |
| An account's site users, and its panel's earlier database users | holding no global privilege |
| A login no record names, holding no global privilege (an operator's own user, a test user) | accepted once into the baseline, by an operator or by `baseline settle` (below) |
| A login that holds nothing at all | always (listed in the counts for cleanup) |
| A grant row | the grantee belongs to the owner of the schema |
| A view, trigger, routine or event | its definer belongs to the owner of its schema and keeps no global privilege |

Anything else stops an unforced switch on the box: for example a login no
record names holding a global privilege, a purged account's user, another
account's earlier panel user holding a global privilege, `root` at an address
that is not the box's, a grant on another account's database, any grant row on
a system schema that is not one of the server's own logins', a stored object
in an account's database defined by `root` or by another account's user, a
mandatory role, a persisted variable that was not accepted.

A login named like an account, or a system name at a host the server's own
logins do not use, is never accepted with a global privilege: it is revoked
(`baseline revoke-global`) or dropped (`leftovers`, or by hand).

### The server's own logins: proof and baseline

Each of the server's own logins is proven by a login with the credential the
box holds for it (`/root/.my.cnf` for `root`, the master's server alias for
`aegir_root`, the master panel's `drushrc.php` for its user, the system
maintenance client file where the server package made one). The login goes
over that row's own transport, must land on exactly that row, and the row may
keep no second password (`RETAIN CURRENT PASSWORD`).

A `root` row no transport of the box reaches (on most boxes `::1`, as IPv6 is
off) is proven by its record alone: when it is accepted it takes root's own
password, as the root rotation gives it to every root row. The locked system
logins hold no credential: each must be locked and hold exactly what the same
login holds on an untouched server of the box's exact server version (its
**reference**). So must the stored objects of the `sys` and `mysql` schemas.

The baseline (`boa_dbreg.baseline`) keeps, per accepted login, three
fingerprints the server computes: how it authenticates, what it holds on all
databases, and its grant rows. A change to any of them stops a switch, with
one exception: a new password on a login the box's own credential still opens.
The root tools that legitimately rewrite these logins record them again right
after their own change: the root password rotation, `syncpass fix aegir`, the
master pass (once the master's server alias holds the new password) and the
panel rewire at a promotion. Nothing records the whole set again on its own.

```
boa-dbctl baseline plan                         every login with its proof and
                                                its place in the baseline, every
                                                row that needs a ruling with
                                                the grant rows it holds, every
                                                finding that stops a switch
boa-dbctl baseline accept pinned                every proven own login
boa-dbctl baseline accept <user>@<host> ...     a row after the operator's ruling
boa-dbctl baseline accept @persisted            the persisted variables as they are
boa-dbctl baseline revoke-global <user>@<host>  every global privilege taken, its
                                                database grants kept, its grants
                                                saved first under
                                                /var/backups/boa/dbrights/
```

`revoke-global` never takes the server's own logins, an account's instance
user, or the replication login of a standing pair.

### What the box settles by itself

```
boa-dbctl baseline settle
```

does, with no ruling asked of anyone, what the box can name exactly, in this
order:

1. every login of the server's own that is proven and not in the baseline
   yet: recorded, as `accept pinned` records it;
2. every login no record names (`UNCLASSIFIED` in `baseline plan`) that
   exists only at the box's own hosts: one that holds a global privilege
   loses it, as `revoke-global` takes it, its grants saved first, and is then
   accepted, unless it then holds nothing, which needs no ruling; one that
   holds none and waits for a ruling is accepted;
3. every instance or panel row `leftovers list` (below) puts in section A,
   at any host: dropped, its `CREATE USER` line and its grants saved first,
   only while every test listed under step 3 below holds. A purged account's
   site users are left to `leftovers drop`.

It runs where a switch would. It is under the release rule above (`ERR 7
not-released`, nothing read or written). It is refused on a standby (`ERR 9
busy standby`), while one is being seeded (`ERR 9 busy standby-init`), on a
box being prepared as a standby (`ERR 9 busy standby-prep`), and while the
box's pair is being switched over, with a switch's own words (`refused pair a
switch to <address> is under way`, `ERR 7 not-ready 1`).

On a box where no account is ever switched it changes nothing, says why in one
line and ends with exit code 0: `OK baseline settle skipped proxysql` (a
ProxySQL box) or `OK baseline settle skipped cluster` (a database cluster).
That is decided before anything asks the local server, whatever it answers.

It reads the box first and takes the baseline lock after, as `leftovers drop`
does: a root tool that records its own row again waits for that lock for a
minute at most. What a write depends on is read again under the lock, and so
are the refusals above: a standby marker or a switch of the pair that appears
during the reads ends the call there, with nothing written.

In step 1 an own login that changed since it was accepted is never recorded
again, whether a login still proves it or not: it is left (`left pinned
<login>: changed since it was accepted`) and keeps stopping a switch. One that
no login proves any more says both (`changed since it was accepted, and not
proven (<why>)`). The root tools that change those rows record them again
themselves; an operator does it with `baseline accept`.

A `root` row at the address `_MY_OWNIP` names in `/root/.barracuda.cnf` takes
root's password and is recorded only while the box holds that address
(`hostname -I` lists it). Where it does not, the row is left: `left pinned
root@<address>: its address is the cnf's, not one this box holds`.

In step 2 the box's own hosts are `localhost`, `127.0.0.1`, `::1` and the
addresses the box holds; the address `_MY_OWNIP` names counts only while the
box holds it. A login is settled only when every row of its user name is at
one of them, whatever the name is: `monitor` made at `localhost` alone is
taken and accepted. Such a login cannot be anyone else's, since no other box
can reach the server through it. The user's rows are read from the server
again, under the lock, before a right is taken or a ruling recorded.

A user with any row at `%` or at any other host (another address, a pattern,
a name, the box's own name included) is left, every row of it: `left
UNCLASSIFIED <login>: it can be used from another host`. On a box that serves
another box's databases, that box's account always has a row at `%`, and
taking its rights would cut that box's sites off. A row left this way that
holds a global privilege, or waits for a ruling, keeps stopping a switch
until an operator revokes, accepts or drops it.

A login that defines a view, trigger, routine or event keeps its rights too:
the server checks a definer's rights when its object runs, so taking them
would stop the object (`left UNCLASSIFIED <login>: it defines <object>:
taking its rights would stop that object`).

The definers are read with the client's warnings shown. When that read comes
with a warning (on 5.7 the server skips, with a warning, the triggers of a
table it cannot open), or fails, the call goes on, but no right is taken and
no row is dropped in that run, on the whole box. Each row left for it says
which: `the read of the stored objects came with a warning` or `the read of
the stored objects failed`.

In step 3 the row's host says nothing: BOA makes every account's instance user
at `localhost` and at `%`. A purged account's instance or panel row is dropped
only while each of these holds, and is left otherwise, with the reason on its
`left` line:

- the account's purge parked its home (`/var/backups/zombie/purged/oN`, a real
  directory);
- no `/root/.oN.octopus.cnf` is there: the purge moves it away, so one that is
  there is a later account of the name, or a half state;
- no row of its user had its password set after the purge, by the server's
  own comparison of `password_last_changed` with the time of the list the
  purge writes in the parked home (`home/.purge.list`) before it drops the
  account's own users. One row set since, and the name is in use by something
  made since. No such list, or a row with no such time: left;
- the row defines no stored object;
- the credential the parked home records for it opens that very row, by a
  login over the row's own transport, as a live account's login is proven:
  the instance user's from the server alias in the parked tarball, the panel
  user's from the parked panel's `drushrc.php`. No such credential, no
  transport of this box that reaches the row, or a login the row does not
  accept: left;
- its `SHOW CREATE USER` line and its grants are saved under
  `/var/backups/boa/dbrights/`, in a file only root reads (it holds the row's
  stored password); a save that fails drops nothing.

The times order two events only on one server's own history. A box seeded from
another server's data (a standby built from a clone, a restore) can hold a
parked home younger than rows another box's account still uses; the login
with the parked account's own credential is what tells such a row apart.

A purged account's site users are never dropped here: the parked home proves
none of them. Each is left with a line that names `leftovers`, whose `drop`
takes them under its list's hash.

Each entry of the saved file can be run again as it is written: the row's
`CREATE USER` line first, then its grants, every statement ended.

A name two accounts' records claim and every login of any other class are
left too, and so is everything that is not a login: a stored object `root`
defines in an account's database, a grant on another account's database,
persisted variables, a mandatory role, a server off its version's reference.
It never drops a row section B lists, or a database.

It prints one line per change and one per thing it left, then the counts:

```
settled accepted <user>@<host>
settled revoked <user>@<host> saved=<file under /var/backups/boa/dbrights/>
settled dropped <user>@<host> saved=<the same file>
left <class or kind> <subject>: <why>
OK baseline settle accepted=N revoked=N dropped=N left=N stops=N
```

`stops` is what `baseline plan` says after it: at 0 nothing on the box stops a
switch. A second run on the same box settles nothing and prints the same
`left` lines. Whatever it leaves is an operator's: `baseline accept`,
`baseline revoke-global`, `leftovers drop`, or the object or grant itself.

A read that fails ends it at once, but for the read of the definers (above).
A change that fails is said in an `ALRT` line and ends it with `ERR 7
baseline-settle-incomplete N` once the rest is done.

Nothing calls `baseline settle` in this release.

### References

```
boa-dbctl baseline reference <version>
```

prints, on an untouched server of exactly that server version (what `SELECT
VERSION()` returns), the lines that version's reference is made of. The
references ship inside the tool. A 5.7 server ends its version with `-log`
while a log (the binary log of a standing pair, for one) was on at its start:
it is the same server, and its reference is the one without that word.

One version has more than one untouched state, and the reference holds each
one known: a server installed on that version and one upgraded into it differ
(the server's own upgrade gives the system logins the dynamic privileges later
versions introduced, and writes some `sys` views in other words), and
`percona.telemetry` is there on some servers only. A login or the stored
objects are proven by any one state's line.

A box whose exact version has no line cannot prove its locked system logins: no
account is switched there unforced, and the nightly check says so every night.

A box of a known version that matches none of its states has the same effect:
`baseline plan` reads the login `off-reference` (`not-in-reference` for a locked
login its version has no line for, `not-locked` for one that is not locked), or
stops on the stored objects of `sys` and `mysql`. `boa-dbctl census` ends with
`reference=ok`, `reference=off` (any of those) or `reference=none` for the box
it runs on.
Before a new state's lines are added, what `baseline reference <version>`
prints there is compared with a server known to be untouched.

### Leftovers of purged accounts

```
boa-dbctl leftovers list
boa-dbctl leftovers drop --sha <the list's hash>
```

`list` shows three sections:

- A: the database users a purged account left that its records prove (the
  account's own name; its last panel user, as the home its purge parked names
  it; its site users, as its registry entries name their databases, since a
  site's user is named as its database: a user that no other account's record
  names, that is none of the server's own logins, and whose every grant is on
  that account's databases or on a name no database has);
- B: the ones that only have the shape of a purged account's name;
- C: the stored objects in kept databases that a user of A defines (a drop
  leaves them without a definer).

A purged account's site users are read only when its purge parked its home
(`/var/backups/zombie/purged/oN`) and moved its root cnf away, as a purge
does. An account with a root cnf and no home (a `/data/disk` not mounted, an
account half made, a name made again after a purge) still has its own name
listed in A, never its site users: read the list before a drop.

`drop` drops exactly the rows of section A, and only while the list is still
the one whose hash it is given. Databases are never touched. On the active box
of a standing pair, an account the standby still carries is never in section
A.

The box-wide check reads a purged account's site user the same way: its grants
and stored objects in that account's databases belong to it, and the login
itself waits for a ruling (drop it here, or accept it into the baseline).

## `scope`: switching an account

```
boa-dbctl scope oN plan
boa-dbctl scope oN on --sha <the plan's hash> [--force] [--accept-refusals]
boa-dbctl scope oN on --pass                    a pass's switch (below)
boa-dbctl scope oN on --born                    a new account's switch (below)
boa-dbctl scope oN off
boa-dbctl scope oN status
```

`plan` changes nothing. It lists what the account must be, and each refusal
with its reason:

- on this box's own database server (`_THIS_DB_HOST` local, its server alias
  naming its own login on a local host), not behind ProxySQL, no cluster;
- its provision copy carrying the broker client, and the migration-source
  files of its panel too where they are there;
- a sudo line letting it run the broker (every barracuda pass writes one per
  account);
- with the binary log on, `log_bin_trust_function_creators=1`, or a load of a
  site with triggers or functions as the site's own login would fail;
- on the active box of a standing pair: the pair not in a switch, the standby
  reachable, a standby, with the account's sudo line and, with the binary log
  on, the same trust setting.

Then the databases it registers: each site record's database on the account's
own server, proven by the site's own recorded login opening it, with no other
account's record or registry entry on it. A site left out is named with its
reason, and the switch is refused while any is (`--accept-refusals` switches
the account without it: that site's database tasks then fail closed).

The plan also lists the rows of the instance user its own login lands on (the
socket, `127.0.0.1`, the box's name), the logins whose global privileges the
switch takes (its instance rows and every panel user it has had), its own
grants on dead names it revokes, grants in the old unescaped spelling it
rewrites, and every finding of the box-wide check. The last line carries the
plan's hash.

`on` reads the plan again and goes on only while it is still the plan whose
hash it is given. It refuses while a finding stands, unless `--force`, which
the log notes.

A finding the switch was forced over stays open, so the account is only as
closed as that finding allows. A routine `root` defines in the account's own
schema, for one, gives the account's instance user every right back when the
account calls it. Where the box keeps a baseline, the nightly witness keeps
naming such a finding until it is settled. The switch a pass makes is never
forced.

`on` pauses the task queue (`/run/boa_queue_stop.pid`), waits for the
account's running tasks to end, saves every grant it is about to change under
`/var/backups/boa/dbrights/`, and then, in an order that never leaves the
account without a way to its databases:

1. the registry entries;
2. the instance user's grant on each of them, on every row in use;
3. the dead-name revokes and the spelling rewrites;
4. the control file: from here the account's tasks take the broker;
5. every global privilege taken from its rows in use and from every panel user
   it has had (by name, its database grants kept);
6. its other rows dropped: a row that defines a view, trigger, routine or
   event (looked up before the drop, since the server lets root drop a
   definer), one whose objects cannot be read, and one the server will not
   drop stay as rows in use, named on `kept=`: each loses every grant it held
   and gets the account's own grants, as a row made again would;
7. a server verify run as the account, its proof.

A failure after step 2 puts the account back on the direct path and says at
which step. `on` again on a switched account makes the same switch again: it
changes nothing unless the instance user's rows did (a row that has come to
define a stored object joins `rows=`; a row no login of the account uses that
defines nothing is dropped and leaves `rows=`).

`off` removes the control file first, then gives every row of the instance user
its rights on all databases back, as an account not switched holds them. The
registry entries stay (they only keep the names held), and no panel user gets
its global privileges back. The next Octopus pass makes the account's other rows
again.

`status` prints whether the account is switched, its control file's server and
rows, its registry counts and whether its instance user holds a global
privilege.

## What keeps an account switched

- The Octopus pass and `syncpass fix oN` rotate a switched account's password
  through the broker: its rows in use are made again with the new password and
  get back their grants on its databases, never rights on all databases.
- A row in use that defines a view, trigger, routine or event is not made
  again: it takes the new password and loses every grant it held, then gets
  its grants on the account's databases back, as a row made again does. A
  grant on another account's database, or one a hand gave it, never stays
  through a rotation.
- Any other row of the instance user that defines one is not dropped: the
  rotation fails, and the broker's log names the row, until an operator
  settles it. When the stored objects cannot be read, no row is dropped; a
  warning or a note on that read counts as such (on 5.7 the server skips, with
  a warning, the triggers of a table it cannot open).
- To settle such a row, re-point or drop its objects, drop the row, and run
  `scope oN on` again. `scope oN on` alone keeps it as a row in use (on
  `kept=`), but the box-wide check still names a row at a host the account's
  logins do not use, as it did before the switch. In this release `scope oN
  on` runs only on a test server with the marker; elsewhere re-pointing or
  dropping the objects and dropping the row is the way, and the next rotation
  succeeds.
- A row on `kept=` leaves `rows=` at the first rotation after it defines
  nothing, and is dropped: re-pointing or dropping its objects is enough. Never
  while the stored objects cannot be read, and never the last row. A drop the
  server refuses fails each rotation (`ERR 7 sql-failed rekey-drop`) until the
  row goes.
- The pass prints every `ALRT` line of the broker's answer, a rotation that
  went through included.
- `xoct`, `xcopy` and `aegir2boa` enter the databases they make for a switched
  account in the registry.
- `boa cleanup purge` parks the account's control file and marks its registry
  entries purged: no other account can take a name whose database is still
  there. Its site users stay with its databases; `leftovers` lists them.
- The nightly run calls `boa-dbctl witness` where an account is switched or the
  registry is in use. It raises an `ALRT` line for a switched account whose
  instance or panel users hold a global privilege, a database of it without its
  instance user's grant, a grant of it on a database not its own, a provision
  copy without the broker client, and for any grant row on the registry.
- Where a baseline is kept the witness also raises every finding of the
  box-wide check. It changes nothing, except that it lets go of reservations a
  day old that nothing used. A query that fails makes it say `ALRT: witness
  incomplete`.

## Standing pairs (xmass)

- The registry and the baseline are tables: they replicate with every other
  schema, so a standby holds them the moment it is promoted.
- The control file is per box: every live pass of the account (`sync`,
  autosync, the cutover's final pass) makes the standby's copy match this box's,
  presence and absence, and only onto a standby. A pass also removes there the
  switch of every account it does not carry. `init` parks the target's own
  control files and `restore-target` puts them back.
- A cutover's dry run refuses a target without the broker's sudo line for a
  switched account, and names settings that differ between the two boxes.
- On a standby, and while one is being seeded, the broker refuses everything
  that writes (`ERR 9 busy standby`); its reads stay open, and the witness and
  the report read nothing there.
- The pair's replication login is one of the server's own while the pair
  stands. A replication login no standing pair of the box names stops an
  unforced switch: drop it by hand where no replica uses it.

## A new account's switch

With `_DB_BROKER_BORN_SCOPED=YES` in `/root/.barracuda.cnf` (off unless set),
a new account is switched at the end of its first Octopus pass, unforced: a box
that is not ready leaves it on the direct path, and the pass says why. Never on
a standby or a box being prepared as one. An account a migration tool installs
here (`xoct create`) is never switched by this setting: it takes its state from
its source instead, switched on the target when it is switched there (where
the target's own checks allow it). `_DB_BROKER_BORN=NO` in an account's
`/root/.oN.octopus.cnf` keeps that account out of it.

The pass makes it with `boa-dbctl scope oN on --born`, which reads the plan
itself: with `--sha`, `--force` or `--accept-refusals`, or on `plan`, `off` or
`status`, it is a usage error. It takes no pause of the task queue and waits
for no task, the account being new.

In this release it switches no account outside a test server (see above): the
pass prints a NOTE and leaves the account on the direct path.

## A pass's switch

```
boa-dbctl scope oN on --pass
```

is the switch an Octopus pass makes for an account, new or not. It reads the
plan itself, so it takes no `--sha`, and it is never forced: with `--sha`,
`--force`, `--accept-refusals` or `--born` it is a usage error. Every refusal
of an unforced switch stands (`not-ready`, `sites-unregistered`,
`not-proven`), and so does the release rule above. It is refused on a standby
and on a box being prepared as one.

It runs only inside a pass. While the pass's wrapper keeps `/run/boa_wait.pid`,
every account's task dispatcher leaves at once, so no task starts under the
switch; without that file the queue is live, and the call is refused (`ERR 9
busy not-in-a-pass`). It takes no pause of the task queue and does not refuse
while a pass's own run markers are there. An operator's own pause of the
queue (`/run/boa_queue_stop.pid`) is not looked at: the call follows the pass,
which the operator started.

It waits for the account's running tasks to end before it reads the plan
(`ERR 9 busy tasks` when they do not), so a database a task made a moment ago
is in the plan.

An account already switched is left as it is when nothing its switch takes
rights from holds a global privilege: its instance user at any row, its panel
user, and every earlier name of that user. It answers `OK scope on oN already
server=<context> rows=<rows>`: nothing was changed (the call only read), no
new file of saved grants, the control file untouched.

One whose control file is valid and where one of those logins holds a global
privilege again goes through the switch. A step that fails then leaves it
switched (`ERR 7 scope-failed <step>`): it is never put back on the direct
path unattended. Where the step was at a row of the instance user, that row
first gets the account's grant on each of its own databases again, and the
`ALRT` line names `boa-dbctl regrant --account oN`, which gives them to every
row in use.

Its line in the broker's log ends with `note=pass`.

Nothing calls it in this release: no pass switches an account that is not new,
and a new account's switch stays as described above.

## The report

```
boa-dbctl report
```

prints one line per account the census lists, then every finding of the
box-wide check, once, and how the server stands against its reference:

```
o1 switched
o2 not-switched <reason>[, <reason>...]
box stop <finding>
OK report accounts=N switched=N unswitched=N stops=N reference=ok|off|none
```

An account's reasons are the ones its own `scope oN plan` gives: each refusal
in the plan's words, `unregistered <database> <why>` for each site left out,
and `box-not-proven N` when nothing of its own holds it and N findings of the
box-wide check would stop its switch. `ready` means its plan refuses nothing.

Three reasons come from outside the plan: `not-released` where this release
switches no account on the box, `opted-out` for an account whose
`/root/.oN.octopus.cnf` says `_DB_BROKER_ARM=NO` (its plan is then not read;
the last such line of the cnf counts, as when the cnf is sourced), and
`control-file-invalid` for a control file that is there and not valid.

The accounts are the census's by name only. A control file that is there and
not valid has three words: `not-switched control-file-invalid` here,
`switched=invalid` in `scope oN status`, and `switched=yes` in the census,
which reads only whether the file is there. Such an account's tasks take the
direct path.

It reads the box once for all accounts, logs in as a plan does (each account's
own login, each site's recorded login) and changes nothing. On a standby it
answers `OK report standby` and reads nothing; a call with any other word
after `report` is a usage error there too. Nothing calls it in this release.

## The database count limit

```
_DB_COUNT_MAX=AUTO        in /root/.oN.octopus.cnf: a number, or AUTO (the
                          built-in default, which is no limit until one is set)
_DB_COUNT_ENFORCE=YES     in /root/.barracuda.cnf: enforce it (off unless set)
```

A switched account at its limit cannot reserve or create a new database name
where the limit is enforced (`ERR 5`); where it is not, the call goes on and the
log notes it. Databases that exist are never affected, and the root tools and a
switch enter what exists without asking. `xmass` and `xoct` carry the account's
value with its other settings.

```
boa-dbctl census [--peak <days>]
```

prints the server's exact version, and per account whether it is switched, how
many live databases its site records name, its registry counts and its limit,
and with `--peak` the highest count the broker's log shows for it in that time.
Its last line says whether the box enforces the limit and how the server stands
against its version's reference. It logs in as no one and changes nothing.

## Settings

| Setting | Where | Default |
|---|---|---|
| `_DB_BROKER_IO_LIMIT` | `/root/.barracuda.cnf` | 86400: the seconds one dump or load may run before its process group is stopped |
| `_DB_COUNT_ENFORCE` | `/root/.barracuda.cnf` | `NO` |
| `_DB_BROKER_BORN_SCOPED` | `/root/.barracuda.cnf` | `NO` |
| `_DB_COUNT_MAX` | `/root/.oN.octopus.cnf` | `AUTO` (no limit) |
| `_DB_BROKER_BORN` | `/root/.oN.octopus.cnf` | unset (`NO` keeps the account out of a new account's switch) |
| `_DB_BROKER_ARM` | `/root/.oN.octopus.cnf` | unset (`NO`: `report` says `opted-out`; nothing else reads it in this release) |

`/root/.barracuda.cnf` is each box's own: set a standing pair's two boxes alike.

A dump or a load holds its account's I/O lock and one of the box's two slots
for as long as it runs, and `_DB_BROKER_IO_LIMIT` is what frees them from a
child that never ends. One past it ends with `ERR 7 time-limit`. A loader
that something else killed before the limit is said as that, never as the
limit: `ERR 7 load-failed 137`, with an `ALRT` line.

A load reads the account's own store (`backups/tmp_expim`), so before the
loader starts the broker walks that store with the account's own rights,
never root's. An entry that is not a real directory or a regular file the
account can open for reading ends the call with `ERR 7 store-entry-refused`:
nothing is loaded and the store is left as it is. A link is such an entry,
whatever it points to (a dump holds plain files only), and so are a FIFO, a
socket and a device. The loader never ends on a link to a file the account
cannot read.

The `ALRT` line names the entry when its name is plain, and says it is not
otherwise. The load ends the same way when the account cannot open the store
or a directory in it, when the walk cannot be made, and when it takes more
than 300 seconds; the line says which.

An entry swapped in after that walk can still hold the account's lock and one
slot until the limit: the limit is the bound.

## Where things are

| | |
|---|---|
| The tool | `/usr/local/bin/boa-dbctl` |
| Control files | `/data/conf/oN_db_broker.txt` |
| Registry, baseline | `boa_dbreg.owners`, `boa_dbreg.baseline` |
| Log, one line per call, never a password | `/var/log/boa/dbctl/dbctl.log` (rotated weekly) |
| Saved grants | `/var/backups/boa/dbrights/` |
| Sudo lines | `/etc/sudoers.d/boa-dbctl` |

Every refusal is `ERR <code> <reason>` with that exit code: 2 usage, 3 not the
account's, 4 taken, 5 at the database count limit, 6 a user it may not touch,
7 a query or step that failed, or a switch this release does not make
(`not-released`), 8 not switched, 9 busy (a lock, a standby, a pass's switch
with no pass running).
