# Migrations across Percona versions, and verifying a migration

Upgrading a box to Percona 8 is done **in place** and needs no migration — see
[UPGRADE-PERCONA8.md](UPGRADE-PERCONA8.md). This page is about a different job:
you are moving accounts or a whole server between BOA hosts anyway, the two
hosts happen to run different Percona series, and you want to know how the
migration tools handle that. It also carries the before/after checklist that
proves any migration — same-version or not — actually succeeded. It complements
the tool references [MIGRATE-XOCT.md](MIGRATE-XOCT.md) and
[MIGRATE-XMASS.md](MIGRATE-XMASS.md).

## How the move tools handle a version difference

- **`xoct`** moves a single Octopus account with `mydumper`/`myloader`. A logical
  dump does not care which server version wrote it, so `xoct` is
  **cross-version safe** for the data: a Percona 5.7 account's databases land
  intact on a Percona 8.4 box (the older-to-newer direction is the validated
  one). Its codebases must still meet the MySQL-8 floors that `codebasecheck`
  checks to run there; no migration tool checks them.
- **`xmass`** evacuates a whole server with an xtrabackup physical snapshot plus
  GTID replication. Physical backup and replication require **identical Percona
  series and patch level on both ends** (for example both 8.4.13) — `xmass init`
  refuses a mismatch before it touches any data.

So when the two hosts of a whole-server move run different series, you have two
ways forward: bring the older box up to the same series **in place** first
([UPGRADE-PERCONA8.md](UPGRADE-PERCONA8.md)), align the patch level, and then
run `xmass`, or move
account by account with `xoct`. Neither migration tool upgrades anything; a box
changes Percona series only through `barracuda`.

## The MySQL watchdog during a migration

BOA's MySQL watchdog (`/var/xdrago/monitor/check/mysql.sh`) restarts a down
`mysqld`, breaks apparent table locks and kills long-running queries. It cannot
tell a cutover's promotion, a host rename's database work or an xtrabackup
snapshot apart from a genuine hang, so `xoct` and `xmass` hold the maintenance
marker `/run/boa_sql_maintenance.pid` around their critical sections, exactly as
the Percona package upgrade does. While the marker exists the watchdog exits
before any check; a marker older than four hours is treated as abandoned, and
`/run` is tmpfs, so a reboot clears it.

- **`xmass`** holds it on **both** hosts across `init` (the source snapshot and
  the target restore/replica bring-up) and, in `cutover`, across the final
  position read and the target's promotion — the highest data-loss risk in
  the entire toolchain (the cutover takes no global read lock: the 503 gate
  and the parked cron and runners are the write barrier).

  On the default relay-first order the **target** gets its watchdog back just
  before visitors are relayed to it, so the renames' database work runs under
  the watchdog as ordinary client work, while the **source** stays paused to
  the end of the cutover; an estate that keeps the rename-first order
  (`_THIS_DB_HOST` set to the box hostname) keeps both paused through the
  renames.
- **`xoct`** holds it for `export` (`mydumper` on the source) and `import`
  (`myloader` plus `renameaegirhost`'s dump/reimport on the target).

Do not restart cron or force the watchdog to run during a migration expecting
it to help. If a migration dies hard and you recover by hand, check the marker
is gone (`ls /run/boa_sql_maintenance.pid`) before you rely on the watchdog
again; it self-clears after four hours regardless.

## What xmass needs on a Percona 8 pair that a 5.7 pair does not

Whole-server replication vocabulary and defaults changed substantially between
5.7 and 8.x. `xmass` is version-aware and handles all of the following
automatically — they are documented here so the behaviour is understood, not so
you configure anything:

- **xtrabackup version and repositories.** Physical backup needs the xtrabackup
  build that matches the server: `percona-xtrabackup-24` for 5.7,
  `percona-xtrabackup-80` for 8.0, `percona-xtrabackup-84-lts` for 8.4. BOA's
  base install configures only the Percona *server* repository, so `xmass`
  derives and enables the matching `pxb-*` repository (reusing the server repo's
  keyring and codename) before installing. It also enables Percona's `tools`
  repository, because xtrabackup depends on `libdbd-mysql-perl`, and the Debian
  build of that package pulls `libmariadb3`, which BOA pins uninstallable — the
  Percona `tools` build depends on the Percona client instead and resolves
  cleanly.
- **Binlog expiry.** `expire_logs_days` was removed in 8.4. On 8.0+ the GTID
  configuration `xmass` writes uses `binlog_expire_logs_seconds`.
- **Replication statement vocabulary.** The `CHANGE MASTER TO` / `START SLAVE` /
  `SHOW SLAVE STATUS` / `RESET MASTER` family was removed in 8.4 in favour of
  `CHANGE REPLICATION SOURCE TO` / `START REPLICA` / `SHOW REPLICA STATUS` /
  `RESET BINARY LOGS AND GTIDS`. `xmass` selects the correct dialect for the
  running version across **every** phase (`init`, `sync`, `status`, `cutover`),
  not only at `init`.
- **GTID persistence.** Enabling GTID at runtime is not enough — the xtrabackup
  copy-back restarts the server, and an unpersisted `gtid_mode` reverts to OFF
  on restart, which silently breaks the replica bring-up. `xmass` writes the
  GTID settings into the include directory that the server's `my.cnf` actually
  reads (`!includedir`, not a guessed `*.conf.d`) and asserts `gtid_mode=ON`
  after the restart.
- **Replica authentication.** `caching_sha2_password` (the 8.0+ default auth
  plugin) refuses to authenticate a replica over a non-TLS channel unless the
  replica is told to fetch the source's public key. `xmass` sets
  `GET_SOURCE_PUBLIC_KEY=1` on the replication link and verifies that **both**
  the IO and SQL replica threads report running before it proceeds.

None of this applies to a same-version 5.7→5.7 `xmass` move, which uses
`percona-xtrabackup-24` and the legacy `MASTER`/`SLAVE` vocabulary throughout.

## Cross-version xoct: what transfers and what to watch

`xoct`'s logical dump/restore is version-agnostic for the data itself — the DB
lands correctly on the newer server. Two behaviours of every `xoct` import are
worth knowing, across versions or not:

- **Post-migration cache/container state.** A migrated-in site can carry the
  source box's stale object cache and (for Drupal 8+) a stale service container.
  BOA does **not** attempt a per-site `drush cr` on import — outside Provision's
  bootstrap context that rebuild fatals on the D8+ Drush/Symfony patch state.
  Instead both `xoct import` and `xmass post-mig` do a **hard infrastructure
  flush**: cold-restart Valkey (or Redis) to drop the object cache, and restart
  every PHP-FPM master to drop opcache/APCu. This is the only treatment trusted
  against cache/container poisoning.

  Operational consequence: sites are briefly
  unavailable (seconds) immediately after the flush and warm up on the next
  request — expected, not a fault.
- **Per-site PHP version pin.** Each site's PHP version lives in the account's
  `static/control/multi-fpm.info`. `xoct` preserves this pin across the move, so
  a site running on 7.4 on the source keeps running on 7.4 on the target even
  though the target account was freshly created with a different default.

### Rename-mode caveats (`o1`→`o2`)

`xoct`'s optional fourth argument renames the account on the target. Rename mode
rewrites account references — including the per-site FPM `$user_socket` account
token, so a renamed site is served by its own account's FPM pool rather than the
target's install-time account of the same old name.

Same-name migrations (the
common production case, and the only mode `xmass` performs) do not exercise the
rename rewrites at all. When you do rename, verify the renamed site serves a real
`200` **direct to the target** (not a proxy or catch-all) — a site-wide `403`
after a rename historically meant a socket token still pointed at the wrong
account's pool.

## Verification — how to trust a migration

A bare "the site returns 200" proves almost nothing: it can be nginx's catch-all,
a cached page from the source, or the wrong account's FPM pool answering. Record
a real BEFORE baseline on the source and check the same things AFTER on the
target, fetched **directly to the target IP**.

**Before (on the source, per site):**

- a unique body marker string you can grep for in the served HTML;
- HTTP `200` on a real Drupal route (e.g. `/user/login`), not the front catch-all;
- a known row count in a marker table (or any table you can count);
- `drush @<alias> status` bootstraps cleanly.

**After (direct to the target, per site):**

| Check | What it proves |
|---|---|
| served HTML contains the exact BEFORE marker | the right site's content is live, not a cache or catch-all |
| HTTP `200` on the same real route, direct to target IP | FPM is executing as the correct account, not 403/503 |
| marker-table row count matches BEFORE | the DB imported completely, not a truncated load |
| `drush @<alias> status` bootstraps on the target | settings/DB creds/paths rewrote correctly |
| `static/files` content present on the target store | file store transferred |
| site-level `files`/`private` are still symlinks | the storage layout survived (not copied as plain dirs) |
| source serves the same marker **via proxy** | the source→target proxy hop is live for DNS-propagation window |

**Whole-server (`xmass`) additional gates:**

- `xmass init` prints the version-match confirmation (identical Percona on both);
- both replica threads report running (`SHOW REPLICA STATUS` / `SHOW SLAVE
  STATUS` per version) with lag falling to zero;
- `xmass sync` reaches a CLEAN dry plan before you run it `--live`;
- `xmass status` shows lag under a minute before cutover;
- after cutover, `_XMASS_PHASE=complete`, every account serves its marker on the
  target, replication is torn down (target standalone), and the source proxies.

**Negative gate (cross-version `xmass`):** `xmass init` from a 5.7 source to an
8.4 target must exit non-zero with the version-mismatch refusal *before* any
xtrabackup or GTID step, leaving the target's data untouched. The refusal is the
correct outcome: `xmass` never bridges a version gap. Upgrade the older box in
place first, or move account by account with `xoct`.

## Field validation — 2026-07

The behaviour above was validated end-to-end on Devuan Daedalus, 8-core ephemeral
boxes, BOA-5.10.3-lts, with two seed sites per account (Drupal 7 on PHP 7.4 and
Drupal 10 on PHP 8.4, each with a unique page marker and a marker DB table). The
Percona-8 boxes reached 8.4 through the real in-place two-run upgrade
(5.7→8.0→8.4), not a fresh install. Coverage matrix, all passing:

| Scenario | Tool | Direction | Outcome |
|---|---|---|---|
| A57 | `xoct` | 5.7 → 5.7 | PASS (single-account, rename mode) |
| C57 | `xmass` | 5.7 → 5.7 | PASS (whole-server; xtrabackup-24 + GTID on 5.7) |
| A | `xoct` | 5.7 → 8.4 | PASS (single-account move between hosts on different series) |
| B | `xoct` | 8.4 → 8.4 | PASS (single-account, same version) |
| C | `xmass` | 8.4 → 8.4 | PASS (whole-server; xtrabackup-84 + GTID on 8.4) |
| D | `xmass` | 5.7 → 8.4 | PASS — refused at the version gate, target untouched |

The version-aware `xmass` behaviour and the watchdog-pause safety were first
validated against real Percona 8.4 in that campaign, across both same-version
and cross-version pairs. This page documents the resulting behaviour, which is
what you operate against.
