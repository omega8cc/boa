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

## The switch

An account is switched while a root-owned control file exists for it:

```
/data/conf/oN_db_broker.txt   (root:root 0644, no one else may write it)

server=@server_localhost      the one database server context it covers
rows=localhost,%              the instance user's rows its logins use
since=2026-10-01T12:00:00Z
```

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
| A login no record names, holding no global privilege (an operator's own user, a test user) | accepted once by an operator into the baseline |
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
login holds on a fresh install of the box's exact server version (its
**reference**). So must the stored objects of the `sys` and `mysql` schemas.

The baseline (`boa_dbreg.baseline`) keeps, per accepted login, three
fingerprints the server computes: how it authenticates, what it holds on all
databases, and its grant rows. A change to any of them stops a switch, with
one exception: a new password on a login the box's own credential still opens.
The root tools that legitimately rewrite these logins record them again right
after their own change: the root password rotation, `syncpass fix aegir`, the
master pass and the panel rewire at a promotion. Nothing records the whole set
again on its own.

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

### References

```
boa-dbctl baseline reference <version>
```

prints, on a fresh install of exactly that server version (what `SELECT
VERSION()` returns), the lines that version's reference is made of. The
references ship inside the tool, one block per version. A box whose exact
version has none cannot prove its locked system logins: no account is switched
there unforced, and the nightly check says so every night.

### Leftovers of purged accounts

```
boa-dbctl leftovers list
boa-dbctl leftovers drop --sha <the list's hash>
```

`list` shows three sections:

- A: the database users a purged account left that its records prove (the
  account's own name; its last panel user, as the home its purge parked names
  it);
- B: the ones that only have the shape of a purged account's name;
- C: the stored objects in kept databases that a user of A defines (a drop
  leaves them without a definer).

`drop` drops exactly the rows of section A, and only while the list is still
the one whose hash it is given. Databases are never touched. On the active box
of a standing pair, an account the standby still carries is never in section
A.

## `scope`: switching an account

```
boa-dbctl scope oN plan
boa-dbctl scope oN on --sha <the plan's hash> [--force] [--accept-refusals]
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
the log notes. It pauses the task queue (`/run/boa_queue_stop.pid`), waits for
the account's running tasks to end, saves every grant it is about to change
under `/var/backups/boa/dbrights/`, and then, in an order that never leaves
the account without a way to its databases:

1. the registry entries;
2. the instance user's grant on each of them, on every row in use;
3. the dead-name revokes and the spelling rewrites;
4. the control file: from here the account's tasks take the broker;
5. every global privilege taken from its rows in use and from every panel user
   it has had (by name, its database grants kept);
6. its other rows dropped (a row the server will not drop, as it defines a
   stored object, stays as a row in use, without a global privilege);
7. a server verify run as the account, its proof.

A failure after step 2 puts the account back on the direct path and says at
which step. `on` again on a switched account changes nothing.

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
- `xoct`, `xcopy` and `aegir2boa` enter the databases they make for a switched
  account in the registry.
- `boa cleanup purge` parks the account's control file and marks its registry
  entries purged: no other account can take a name whose database is still
  there.
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
  that writes (`ERR 9 busy standby`); its reads stay open, and the witness reads
  nothing there.
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
It logs in as no one and changes nothing.

## Settings

| Setting | Where | Default |
|---|---|---|
| `_DB_BROKER_IO_LIMIT` | `/root/.barracuda.cnf` | 86400: the seconds one dump or load may run before its process group is stopped |
| `_DB_COUNT_ENFORCE` | `/root/.barracuda.cnf` | `NO` |
| `_DB_BROKER_BORN_SCOPED` | `/root/.barracuda.cnf` | `NO` |
| `_DB_COUNT_MAX` | `/root/.oN.octopus.cnf` | `AUTO` (no limit) |
| `_DB_BROKER_BORN` | `/root/.oN.octopus.cnf` | unset (`NO` keeps the account out of a new account's switch) |

`/root/.barracuda.cnf` is each box's own: set a standing pair's two boxes alike.

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
7 a query or step that failed, 8 not switched, 9 busy (a lock, a standby).
