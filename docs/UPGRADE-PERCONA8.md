# Upgrading to Percona 8 — in place, no migration

BOA upgrades a server's Percona **in place**, with `barracuda`. Every account,
site, database and PHP version stays on the same box: nothing is
exported, moved or renamed, and none of the migration tools (`xoct`, `xcopy`,
`xmass`) takes part. Getting from Percona 5.7 to 8.0 and 8.4 is an upgrade,
not a migration.

There is one caveat. A box runs **one shared Percona server** for every Octopus
account, every control panel and every hosted site, so every codebase on the
box must be able to run on MySQL 8 before the box upgrades. `codebasecheck`
answers that before you start — see
[CODEBASECHECK.md](CODEBASECHECK.md).

Moving accounts or servers between BOA hosts is a separate job. It can happen
to coincide with a version difference between two hosts; when it does,
[MIGRATE-VERSIONS.md](MIGRATE-VERSIONS.md) covers how the migration tools
handle it.

## The upgrade, step by step

1. **Take a whole-server snapshot** (a VM snapshot or your provider's
   equivalent) and make sure it restores. BOA takes no database backup of its
   own during the upgrade, and a database major upgrade cannot be undone in
   place: the snapshot is the way back.
2. **Check readiness:** `codebasecheck --box --deep`.

    - **READY** — go on.
    - **REVIEW** — the cores are compatible, but look at each deep finding on
      a test clone before you trust the upgrade.
    - **BLOCKED** — a codebase on the box is older than its MySQL-8 floor, or
      its core version could not be read (UNKNOWN). Update that core, or move
      its sites to a newer platform on this box with Ægir's Migrate task (look
      at an UNKNOWN one by hand), then run the check again until it no longer
      says BLOCKED.

3. **Upgrade to 8.0:** `barracuda up-lts system percona-8.0`
4. **Upgrade to 8.4:** `barracuda up-lts system percona-8.4`

Use `up-pro` or `up-dev` on those trees. The two runs are the Devuan Daedalus
path, and on Daedalus only; Devuan Excalibur always runs Percona 8.4 (see
below).

**Two runs, never a jump.** Ask for `percona-8.4` on a 5.7 box and that run
stops at 8.0: the strict upgrade path stages the middle step for that run only,
while `/root/.barracuda.cnf` keeps the 8.4 request, so the next `barracuda` run
finishes the upgrade to 8.4, whatever starts it. Run that second step yourself,
straight after the first, so its downtime lands when you choose.

**Never a downgrade.** BOA does not install an older Percona series over a
newer one. On a box running 8.0 or 8.4, a `_DB_SERIES` in
`/root/.barracuda.cnf` that asks for an older series — a hand edit, a missing
`_DB_SERIES` line (the default is 5.7), or a value BOA does not know (read as
5.7) — is refused. The next `barracuda` run keeps the installed series, writes
it back to `/root/.barracuda.cnf`, and reports the refusal on two `ALRT` lines,
so that run's report mail flags it.

The `percona-X.Y` argument and the `/root/.percona.X.Y.cnf` markers never ask
for an older series either. The way back from an upgrade is the snapshot from
step 1.

Asking for 8.4 also switches on the rotation of the MySQL root password on every upgrade run
and removes the `/root/.mysql.no.new.password.cnf` opt-out, except on a
replication standby (see
[docs/ctrl/system.ctrl](ctrl/system.ctrl)); site and panel credentials are not
touched. A standing
`/root/.percona.8.4.cnf` marker asks for the same as the argument.

## What each run does

- **Sets up a clean stop** (`innodb_fast_shutdown = 0`), so the old server's
  stop in the package swap is a full, clean shutdown.
- **Checks the old tables first.** On the 5.7 → 8.0 run, `mysql_upgrade --force`
  runs against the still-running 5.7 server before anything is swapped.
- **Stops the watchdog from interfering.** The MySQL watchdog stands down for
  the whole package window (see below), so it does not start a competing
  `mysqld` while the new server is coming up.
- **Swaps the packages.** The install stops the old server and starts the new
  one. The first 8.0 start also upgrades the data dictionary, which the code
  notes can take minutes on a large datadir.
- **Fails closed.** If the server package is not installed at the series this
  run is going for after the package phase, the run stops with a FATAL before
  any `my.cnf` tuning for the new series and before it waits for a server that
  cannot start.
- **Writes what the new series needs** into `my.cnf` (the authentication lane
  below among it), restarts the server, and runs `mysqlcheck --auto-repair`
  over every database.
- **Re-arms the watchdog** once the new server is up.

**What visitors see.** Nginx and PHP-FPM stay up for the whole run; any request
that needs the database fails while `mysqld` is down, from the slow shutdown to
the first start of the new server, and briefly again at the restarts after it.
BOA puts up no maintenance page for this, and a 5.7 → 8.4 upgrade is two such
windows, one per run. Plan them.

## Sites on the PHP 5.6 pool keep working on 8.0 and 8.4

The 8.x default authentication plugin, `caching_sha2_password`, is advertised in
the server's handshake greeting, and PHP 5.6's mysqli aborts on that greeting
before the user's own plugin is consulted. A site served through the `php56`
pool would lose its database on the web while CLI Drush (modern PHP) stayed
healthy, and Drupal 6 would answer its own "Site off-line" page.

BOA's configuration pass therefore advertises the native plugin on both 8.x
series: `authentication_policy = mysql_native_password,,` on 8.0 and 8.4, plus
`default_authentication_plugin = mysql_native_password` on 8.0 and
`mysql_native_password=ON` on 8.4. The greeting is native, a native-plugin user
connects from PHP 5.6, and `caching_sha2` users (root, every modern-PHP site)
still authenticate through the client auth-switch.

On 5.7 the directives are commented out, since 5.7 aborts on the unknown
variables. An existing box's `my.cnf` converges on its next `barracuda up-*`
pass; there is nothing to do by hand. That is why `php56`-pool sites keep
working after each run, on 8.0 as on 8.4.

The Drupal side is a separate matter: Drupal 6 code runs on MySQL 8 from
d6lts/Pressflow 6.51 on (the `codebasecheck` floors). What BOA's configuration
provides is the PHP 5.6 client lane, which no Drupal version bump could supply.

Horizon: this lane exists only for the 8.x generation. `mysql_native_password`
is deprecated but shipped in 8.4 and removed in MySQL/Percona 9.x, so a box
hosting `php56`-pool sites could not be upgraded in place to 9.x. When 9.x
support ever lands, `codebasecheck` is the natural place to gate that.

## The MySQL watchdog stands down during the upgrade

BOA runs a MySQL watchdog from cron (`/var/xdrago/monitor/check/mysql.sh`) that
restarts a down `mysqld`, breaks apparent table locks and kills long-running
queries. During a deliberate database operation it cannot tell an
`innodb_fast_shutdown=0` package upgrade from a genuine hang, and "healing" it
mid-flight — starting a second `mysqld` that races the new one for the datadir
— would abort the data-dictionary upgrade.

The Percona package upgrade therefore holds the maintenance marker
`/run/boa_sql_maintenance.pid` for the whole package window, and while the
marker exists the watchdog exits before any check. A marker older than four
hours is treated as abandoned and removed, and `/run` is tmpfs, so a reboot
clears it too. `xoct` and `xmass` hold the same marker around their own
database work (see [MIGRATE-VERSIONS.md](MIGRATE-VERSIONS.md)).

You do not manage the marker by hand. Do not restart cron or force the watchdog
to run during an upgrade expecting it to help. If an upgrade dies hard and you
recover by hand, check the marker is gone (`ls /run/boa_sql_maintenance.pid`)
before you rely on the watchdog again; it self-clears after four hours
regardless.

## Devuan Excalibur, fresh installs and Drupal 11

- **Excalibur runs Percona 8.4 only.** The automated `autoexcalibur` refuses the
  Daedalus → Excalibur OS upgrade until the box is on 8.4 (the manual path does
  not check), so upgrade Percona in place on Daedalus first (see
  [MAJORUPGRADE.md](MAJORUPGRADE.md)).
- **A new server can start on 8.4** by installing with the `percona-8.4`
  argument (see [INSTALL.md](INSTALL.md)). On Daedalus the default stays 5.7 on
  purpose: what runs keeps running, and the newer engine is a choice you make
  at install, or later with this upgrade.
- **Drupal 11 needs MySQL 8**, which on BOA means Percona 8.4, so a box that
  will host Drupal 11 takes this upgrade (or installs with 8.4).

## Field evidence

The July 2026 Percona 8 test boxes reached 8.4 through this two-run in-place
upgrade (5.7 → 8.0 → 8.4), not through a fresh install; the migration tests run
on them are described in [MIGRATE-VERSIONS.md](MIGRATE-VERSIONS.md).
