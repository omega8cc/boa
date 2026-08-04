# Orphan Database Cleanup — sqlclean

`sqlclean` (installed as `/opt/local/bin/sqlclean`, root only) finds and — on
explicit request — removes MySQL databases that no longer belong to any site
or Ægir frontend on the box. Its main use is source-box hygiene before a
migration whose database leg mirrors every schema wholesale, and periodic
cleanup on long-lived boxes where deleted-account leftovers accumulate.

It never deletes anything by default: with no arguments it only reports.

## What counts as an orphan

The source of truth is the **Drush alias set**, never the nginx vhosts. A
disabled site keeps its database while its vhost is regenerated from a
db-free template; a site behind a migration proxy has its real vhost staged
under a leading dot; a cancelled instance has all vhosts wiped long before
its purge. Vhosts therefore cannot tell a dead database from a live one.

Aliases can: every existing site resolves via
`<root>/.drush/<uri>.alias.drushrc.php` → `site_path` →
`sites/<uri>/drushrc.php` → `$options['db_name']`, and deleting a site in
Ægir removes the alias together with the database. No alias, no database.

Every schema on the server is classified as exactly one of:

* **preserved** — system schemas; every alias-resolved site database across
  `/var/aegir` and all `/data/disk/*` instances; every instance's own
  hostmaster database; names listed in `/root/.sqlclean.protect.cnf`.
* **held** — never deleted, reported loudly: the panel still tracks a live
  site the aliases cannot vouch for, a hostmaster-shaped schema still serves
  an existing platform tree, an alias quarantined in `<root>/undo/` still
  resolves to the database, or a classification query failed. Fix the cause
  in Ægir, then re-run.
* **ghost** — everything else, offered for deletion. A ghost that carries
  Ægir frontend tables whose platform trees are gone is tagged
  `panel-orphan`: besides wasting space, stale panel schemas can abort
  migration tooling that refuses to guess between multiple hostmaster
  candidates.

Databases that belong to nothing Ægir knows about — billing, monitoring,
ad-hoc — must be listed in `/root/.sqlclean.protect.cnf` (one name per line,
`#` comments allowed). Any LIVE run refuses until that file exists, even
empty: its presence records that non-Ægir schemas were reviewed.

## Running it

`sqlclean` — DRY report. Writes the classification to
`/var/log/dbs_to_remain.log` and `/var/log/db_cleanup.log`, and the ghost
list to the manifest `/var/log/sqlclean-ghosts.txt`.

`sqlclean LIVE` — interactive cleanup: each ghost must be confirmed by
typing its exact name. Needs a terminal. Declining a ghost only skips it for
this run — add it to the protect file to keep it permanently.

`sqlclean LIVE auto` — non-interactive cleanup for runbooks. It refuses
unless all of the following hold:

* a DRY run's manifest was copied to `/var/log/sqlclean-ghosts.txt.reviewed`
  (that copy is the operator's sign-off) less than 4 hours ago,
* the current detection still matches the reviewed manifest exactly,
* no resolution alert fired (see below).

The reviewed manifest is consumed after a successful run; every future auto
run needs a fresh review.

## Safety guards

The tool refuses to start while any Ægir/Provision task is running or a BOA
action holds `/run/boa_run.pid` / `/run/boa_wait.pid`, re-checks that
interlock before every drop, takes a lock against concurrent runs, and
verifies the MySQL endpoint is this box's own server before classifying
anything.

Anything that exists but cannot be resolved — an unreadable site drushrc, an
instance whose system user has a home but no `.drush`, a hostmaster alias
that resolves to nothing, a failed per-schema query — raises a resolution
alert. The report still completes, but `LIVE auto` refuses until every
alert is fixed: an unreadable alias must never widen the ghost list
unattended.

When a ghost database is dropped, its dedicated MySQL user (same name, as
provisioned) is dropped with it — unless that user also holds grants on any
other schema, in which case the user is kept and reported.

Exit codes: `0` clean, `1` refused or failed outright, `2` completed with at
least one failed drop (details in `/var/log/db_cleanup.log`).

## Migrations

On the replication-based full-box migration path every schema on the source
is seeded and mirrored to the target, orphans included. Running `sqlclean`
on the source **before** the migration seed both shrinks the transfer and
removes stale panel schemas that the migration tooling would otherwise trip
over. The per-account migration path enumerates databases the same way this
tool does, so orphans are structurally left behind there — cleanup on such a
source is a disk-hygiene question, not a payload one.

The nightly ghost reapers (see [CLEANUP.md](CLEANUP.md)) handle codebases,
platforms and site directories; `sqlclean` is their database-side
counterpart and follows the same policy: no action while tasks run, nothing
acted on from a single unreviewed snapshot, fail closed on anything
unprovable.
