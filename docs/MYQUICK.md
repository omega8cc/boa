# Super Fast Site Cloning and Migration

Blazing fast migrations and cloning, even for sites with complex and large databases, are enabled by default via this control file:

`~/static/control/MyQuick.info`

This file is created automatically for every account by a periodic system agent, so super-fast dumps are the stock behaviour. If you prefer the classic, slower behaviour for an account, opt out by creating this control file instead, and the system will stop creating `MyQuick.info`:

`~/static/control/MyClassic.info`

## How Fast is Super-Fast?

It's faster than you would expect! We have observed it speeding up clone and migration tasks that normally take 1-2 hours to just 3-6 minutes. Yes, that's how fast it is!

This file, while present, enables a super fast per-table and parallel database dump and import. However, it will not leave a conventional complete database dump file in the internal safety copies Ægir makes for itself during migrate and delete tasks, so a Restore from one of those archives brings back the files only and keeps the site's current database (the task log says so).

A Clone is not affected: its safety copy always carries a classic dump, and the new site's database is loaded from it. A Backup task is different: it always carries a Backup Mode, and when none is chosen it defaults to the restorable one.

We need to emphasize this again: with this control file present, all normally slow tasks will become blazing fast, but at the cost of not keeping an archived complete database dump file in the site directory archive where it would otherwise be included.

## Important Considerations

Of course, the system still maintains nightly backups of all your sites using the new split SQL dump archives. However, with this control file present, the restore task cannot use those split archives, because they do not include a single database dump. You can still find that SQL dump split into per-table files in the backups directory, though, in a subdirectory with a timestamp added, so you can still access it manually if needed.

If you need a Restore-capable archive without opting out of super-fast dumps for the whole account, run the site Backup task and choose the **Site files with classic mysqldump DB** option under Backup Mode. That one archive bypasses `MyQuick.info` and produces a conventional single-file mysqldump that the Restore task can use, while `MyQuick.info` continues to provide fast dumps for all other Ægir tasks. A Backup task queued without a mode gets this one by default. Each mode restores exactly what it contains, and this is the only one that carries the database.

## mydumper and myloader Compatibility

mydumper 1.0 removed the `--overwrite-tables` option in favour of the equivalent `--drop-table=DROP`, while binaries older than 0.20.1 accept only `--overwrite-tables` — and BOA's callers now pass `--drop-table=DROP`.

On every system pass (not only at install time) BOA probes the real installed `myloader` in all its layouts — the packaged binary, an in-place source build, or an already-healed one — and reconciles whichever direction is needed: a pre-0.20.1 binary gets a wrapper at `/usr/local/bin/myloader` translating `--drop-table` to `--overwrite-tables` (the source build is moved aside to `myloader.bin` first), a 1.x binary gets the reverse translation, and a binary accepting both gets the wrapper removed in favour of a plain symlink.

The wrappers `exec` the real binary, so exit codes propagate — which is what makes the import failure checks meaningful. Every combination of older and newer callers and binaries therefore keeps working, with no required upgrade ordering and no dependence on ever re-entering an install path.

The binary the wrapper targets is the `myloader` that ships **beside the `mydumper` the callers actually run** — resolved by following `/usr/local/bin/mydumper` to the build it belongs to — and it is pinned into the wrapper rather than re-derived at run time. Simply preferring `/usr/bin` used to let an older packaged `myloader` capture the path next to a newer source-built `mydumper`, which silently split the pair across two releases and failed every import.

Leftovers of whichever build lost are now removed on every pass rather than accumulating. On a host using the packaged build, a real binary left at `/usr/local/bin/mydumper` by an earlier source build is replaced by the symlink and the stale `.bin` companions are dropped; on a host that genuinely needs the source build, the packaged binaries left in `/usr/bin` are purged — but only once the source pair is proven to exist and run, so a failed build can never leave a host with no tools at all.

A dangling symlink at either canonical path is cleared before anything else looks at it, since it answers "installed" to a bare file test while pointing at nothing. As a backstop BOA compares the two versions afterwards and reports a `MyQuick pair mismatch` if they still disagree.

Nightly backups dump every database with mydumper, which in its default mode refuses to dump a database containing non-transactional tables (for example, a stray MyISAM table). The backup scripts count such tables first and add `--trx-tables=0` only for the affected databases, so mixed-engine databases are always included in the nightly archives, while InnoDB-only databases keep the fastest locking path.

On Percona 5.7 the nightly and cluster dumps sync with `FLUSH TABLES WITH READ LOCK` (`--sync-thread-lock-mode=FTWRL`; on Percona 8.x the mode is `AUTO`) and pass `--no-backup-locks` beside it when the installed `mydumper` lists that option. The global read lock alone still gives each dump its consistent point for row changes; a `mydumper` without the option is called as before.

On 5.7 the `xoct` and `xcopy` site exports, `boa-dbctl dump` and the per-site MyQuick dump Provision takes where no backup mode is set (the safety copies ahead of a Migrate or a Delete, a Restore whose archive carries no database dump, the hostmaster site's own backups and a `provision-backup` run outside the task queue) pass `--no-backup-locks` the same way. They keep mydumper's default lock mode, which takes the same global read lock there; any other server gets the arguments as before.

Without the option, mydumper also takes Percona's backup lock on 5.7 and keeps it until the dump ends, past the release of the global read lock, while a write to a MyISAM table waits for that lock with the table open. The event scheduler makes such a write at every event run (`mysql.event` is MyISAM on 5.7), so such a dump can stall with its `FLUSH TABLES` waiting for that table, which MySQL does not see as a deadlock, and every write on the box then queues behind it.

A `TRUNCATE` that reaches a table before mydumper has read it completes and leaves that table empty in the dump. Without the option, one that comes while mydumper holds its backup lock stalls the dump instead, and holds its table until it is killed.

A dump that fails (non-zero exit or no final `metadata` marker) is never archived: its debris is kept in the run directory as `<db>.FAILED`, the script logs an `ALRT` line for it, and once per run a dated line is appended to `/var/log/boa/mysql.backup.incident.log` and one e-mail is sent to `_MY_EMAIL` naming every missing database, unless `_INCIDENT_REPORT` is `OFF`.

Large tables are chunked and dumped in parallel by mydumper's adaptive chunker and restored in parallel from those chunks. No caller passes the historical `--rows=50000`: a fixed `--rows=N` puts mydumper into fixed-length chunking, where one step covers N key values of the first primary-key column rather than N rows, so it walks the whole MIN..MAX span of that key without re-anchoring on the next key that exists; a table keyed on a sparse bigint (timestamp-derived IDs) therefore produced one empty chunk file per step until the host ran out of inodes.

The adaptive chunker of the mydumper 0.21.3 line had a defect of its own — a split past the last existing key truncated the first chunk's file to zero bytes while exiting clean with `metadata` written (8 to 14 incomplete dumps in 100 on a 60k-row INT-keyed table with one far-away id) — which mydumper 1.0.5 no longer has (100 of 100 complete in the same drill, close to the fixed mode's speed), so BOA pins 1.0.5-1.

Every caller reads the installed mydumper version: on 1.x it passes no `--rows`; on an older build still installed it passes `--rows=-1`, turning integer chunking off (one thread and one file per table, complete every time, slower on huge tables) until the binary is replaced; on the older packaged line (`_MYQUICK_VRN_ONE`, buster) that fallback is permanent. The version is probed per dump and anchored on the tool's banner line.

The replacement does not wait for a full upgrade: the Skynet agent pass (`BOA.sh.txt`, every few minutes) brings a packaged build to the pin itself, never during an install, a dump or a restore, verifying the package's own version and codename before `dpkg` sees it, and re-derives the `myloader` path the way the upgrade pass does; the outcome is written to `/var/log/boa/myquick-deb-<version>.log`, a pass that changed nothing retries later, and a box with `_SKYNET_MODE=OFF`, a source-built pair, or a codename without a packaged build waits for the next `barracuda up-*` pass as before.

A dump written by one mydumper line and loaded by the other logs schema and structure checksum mismatch warnings; the data checksums match and the restore is complete. The same applies to the cluster variant, the `xoct`/`xcopy` exports and the per-site MyQuick dump provision takes where no backup mode is set (the hostmaster site's own backups, the safety copies ahead of Migrate and Delete, and a backend `provision-backup` run outside the task queue).

The `/root/.my.cnf` credentials file is written with exactly five groups — `[client]`, `[mysql]`, `[mysqldump]`, `[mydumper]` and `[myloader]` — separated by empty lines. mydumper and myloader parse this file with a strict key-file parser, so the separator lines must be genuinely empty, and only groups with real consumers are written.

## Imports Are Written to the Binary Log

Every `myloader` load BOA runs passes `--ignore-set=SQL_LOG_BIN` when the installed `myloader` lists that option: the fast import of an Ægir Migrate task (and of a Restore whose archive carries no database dump), and the per-site imports of `xoct` and `xcopy`.

Without it `myloader` opens every session with `SET SQL_LOG_BIN=0` (its own default, and the packaged `/etc/mydumper.cnf` sets it again for a call without an option file of its own), so on a box running with the binary log on (every box an `xmass` run touched, the active of a standing mirror among them) the loaded tables never reached the replica, and the replica's applier stopped with error 1146 at the first write the site made to them.

With the binary log off, BOA's default, the option changes nothing. `--enable-binlog` is no substitute: the packaged file turns the binary log off again, and the 0.19.3 line refuses the option.

The option also lets a database user without SUPER run `myloader`: the `SET` it removes is refused for such a user (`ERROR 1227`), and `myloader` then exits non-zero although the tables loaded.

A restore you run by hand on such a box takes the same option, with root's option file:

```sh
myloader --defaults-file=/root/.my.cnf --database=<dbname> \
  --directory=<dump-dir> --threads=4 --drop-table=DROP --ignore-set=SQL_LOG_BIN
```

## Triggers, Stored Routines and Events

Every mydumper dump BOA takes carries the database's triggers, stored procedures and functions, and scheduled events along with its tables and views: the nightly and cluster backups, the per-site exports of `xoct` and `xcopy`, and the dump Ægir takes for a Migrate task or for a Restore whose archive carries no database dump. Each of the three options is passed when the installed `mydumper` lists it.

`xoct` and `xcopy` load them as root and keep each object's definer, the site's database user, which the import creates on the target under the same name before the load.

Each object keeps the `sql_mode` it was made under. mydumper writes a whole file under one mode, so after each dump BOA puts each object's own mode, as the server stored it, on a `SET SQL_MODE` line before it and the file's mode after it. Without that, a routine a Drupal site made through its own connection (`ANSI_QUOTES`) failed the fast load, and a trigger using `||` loaded but no longer concatenated. Words MySQL 8 refuses, such as `NO_AUTO_CREATE_USER`, are left out, so a 5.7 dump loads on 8.4.

A dump taken before this keeps the file's one mode for every object. When an object's mode cannot be written, the dump stands as mydumper wrote it and the run says so. The nightly and cluster backups name each such database once per run in `/var/log/boa/mysql.backup.incident.log` and in the notice mail, as they do for a dump that left its routines or events out. The `xoct` and `xcopy` exports print a `WARN` line, `boa-dbctl dump` an `ALRT`, and Provision's fast dump a warning in the task log.

The fast import of a Migrate or of a dump-less Restore gives every view, trigger, routine and event to the site's new database user (`--replace-definer`), as the classic dump path does by loading as that user. Kept as they were, they would name the source database's user, which the task drops when it finishes, and fail from then on. A `myloader` without `--replace-definer` (the 0.19.3 line) loads the tables and views and leaves the triggers, routines and events out; the task log says so.

A nightly dump restored as root brings them back with their own definers, and the site's own database user can restore its dump into its own database too.

The classic `mysqldump` dumps carry them as well: the dump of a Clone, of a Migrate or a Restore on an account without `MyQuick.info`, of the Backup mode with a classic dump, and the nightly and cluster backups in legacy mode. Triggers they always carried; stored routines and events are asked for with `--routines` and `--events`. Ægir's classic dump strips every definer and is loaded as the site's database user, so that user owns each view, trigger, routine and event afterwards; the nightly dumps keep their definers.

An object made while its database had another default collation comes wrapped in `ALTER DATABASE` lines that name the dumped database; Ægir's classic dump drops that name, so the lines apply to the database being loaded.

`mysqldump` stops the whole dump on a routine the dumping user may not read (one another user defines) and on events it may not list, so each option is asked first. When one is refused, the dump is taken without those objects, the task log carries a warning, and the nightly names the database in its backup notice.

A classic load as the site's database user on a box with the binary log on creates triggers and stored functions only while `log_bin_trust_function_creators` is on. `xmass` sets it on both ends of a pair. With the binary log turned on by `_DB_BINARY_LOG=YES`, or by a custom `my.cnf` under `_CUSTOM_CONFIG_SQL=YES`, BOA leaves it at the server's default (off) unless that `my.cnf` sets it, and the load fails with `ERROR 1419` and says so.

With the binary log on and `log_bin_trust_function_creators` off, MySQL refuses a stored function declared without `DETERMINISTIC`, `NO SQL` or `READS SQL DATA` (`ERROR 1418`), and a database user without SUPER may create neither triggers nor stored functions (`ERROR 1419`). A load that meets such an object fails and says so: `xoct` and `xcopy` count the site's import as failed, and a Migrate rolls back with the site left as it was.

`xmass` turns that setting on wherever it turns the binary log on, and the SQL watchdog adds it to an `xmass` configuration written before it did, so neither refusal arises on a box an `xmass` run touched, unless its configuration sets the value itself. Where the setting stays off, declare such a function with one of those characteristics, and restore a dump that carries triggers or functions as root.

For more information, please visit the [documentation](https://github.com/omega8cc/boa/tree/5.x-dev/docs).

