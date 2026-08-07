# Super Fast Site Cloning and Migration

Blazing fast migrations and cloning, even for sites with complex and large databases, are enabled by default via this control file:

`~/static/control/MyQuick.info`

This file is created automatically for every account by a periodic system agent, so super-fast dumps are the stock behaviour. If you prefer the classic, slower behaviour for an account, opt out by creating this control file instead, and the system will stop creating `MyQuick.info`:

`~/static/control/MyClassic.info`

## How Fast is Super-Fast?

It's faster than you would expect! We have observed it speeding up clone and migration tasks that normally take 1-2 hours to just 3-6 minutes. Yes, that's how fast it is!

This file, while present, enables a super fast per-table and parallel database dump and import. However, it will not leave a conventional complete database dump file in the site archive normally created by Ægir when you run not only the backup task, but also clone, migrate, and delete tasks. Consequently, the restore task will not work with those archives.

We need to emphasize this again: with this control file present, all normally slow tasks will become blazing fast, but at the cost of not keeping an archived complete database dump file in the site directory archive where it would otherwise be included.

## Important Considerations

Of course, the system still maintains nightly backups of all your sites using the new split SQL dump archives. However, with this control file present, you won't be able to use the restore task in Ægir because the site archive won't include the database dump. You can still find that SQL dump split into per-table files in the backups directory, though, in a subdirectory with a timestamp added, so you can still access it manually if needed.

If you need a Restore-capable archive without opting out of super-fast dumps for the whole account, run the site Backup task and choose the **Site files with classic mysqldump DB** option under Backup Mode. That one archive bypasses `MyQuick.info` and produces a conventional single-file mysqldump that the Restore task can use, while `MyQuick.info` continues to provide fast dumps for all other Ægir tasks. It is the only Backup Mode option usable for the Site Restore task.

## mydumper and myloader Compatibility

mydumper 1.0 removed the `--overwrite-tables` option in favour of the equivalent `--drop-table=DROP`, while binaries older than 0.20.1 accept only `--overwrite-tables` — and BOA's callers now pass `--drop-table=DROP`. On every system pass (not only at install time) BOA probes the real installed `myloader` in all its layouts — the packaged binary, an in-place source build, or an already-healed one — and reconciles whichever direction is needed: a pre-0.20.1 binary gets a wrapper at `/usr/local/bin/myloader` translating `--drop-table` to `--overwrite-tables` (the source build is moved aside to `myloader.bin` first), a 1.x binary gets the reverse translation, and a binary accepting both gets the wrapper removed in favour of a plain symlink. The wrappers `exec` the real binary, so exit codes propagate — which is what makes the import failure checks meaningful. Every combination of older and newer callers and binaries therefore keeps working, with no required upgrade ordering and no dependence on ever re-entering an install path.

Nightly backups dump every database with mydumper, which in its default mode refuses to dump a database containing non-transactional tables (for example, a stray MyISAM table). The backup scripts count such tables first and add `--trx-tables=0` only for the affected databases, so mixed-engine databases are always included in the nightly archives, while InnoDB-only databases keep the fastest locking path.

The `/root/.my.cnf` credentials file is written with exactly five groups — `[client]`, `[mysql]`, `[mysqldump]`, `[mydumper]` and `[myloader]` — separated by empty lines. mydumper and myloader parse this file with a strict key-file parser, so the separator lines must be genuinely empty, and only groups with real consumers are written.

For more information, please visit the [documentation](https://github.com/omega8cc/boa/tree/5.x-lts/docs).

