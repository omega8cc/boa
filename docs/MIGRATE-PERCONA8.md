# Migrating to Percona 8 — cross-version behaviour and verification

This is the field reference for moving BOA accounts and whole servers onto
Percona 8 (8.0 or 8.4), and for verifying that any migration — same-version or
cross-version — actually succeeded. It complements the tool references
[MIGRATE-XOCT.md](MIGRATE-XOCT.md) and [MIGRATE-XMASS.md](MIGRATE-XMASS.md) with
the version-specific behaviour that only surfaces on a real Percona 8 target,
plus the pre/post checklist to trust the result.

The two tools split the problem the same way they always do:

- **`xoct`** moves a single Octopus account with `mydumper`/`myloader`. Because
  it exports a logical dump on the source and loads it on the target, it is
  **cross-version safe**: a Percona 5.7 source migrates cleanly onto a Percona
  8.4 target. This is the tool for the actual version jump.
- **`xmass`** evacuates a whole server with an xtrabackup physical snapshot plus
  GTID replication. Physical backup + replication require **identical Percona
  versions on both ends** — `xmass init` refuses a mismatch before it touches
  any data. Use `xmass` to move a fleet that is already on Percona 8, not to
  perform the version jump itself.

So the canonical Percona-8 adoption path is: upgrade the *target* box to Percona
8 first (see [MAJORUPGRADE.md](MAJORUPGRADE.md) — the strict path clamps a
5.7→8.4 request to 8.0 first, so it is two upgrade runs), then `xoct`-migrate
accounts onto it from the old 5.7 boxes. Once a whole region is on 8.4, `xmass`
can evacuate boxes wholesale within that version.

## The MySQL watchdog stands down during migrations and upgrades

BOA runs a MySQL watchdog from cron (`/var/xdrago/monitor/check/mysql.sh`) that
auto-heals a sick server: it restarts a down `mysqld`, breaks apparent table
locks, and kills long-running queries. During normal operation that is exactly
what you want. During a *controlled* database operation it is a race straight
into corrupt data — the watchdog cannot tell a deliberate `FLUSH TABLES WITH
READ LOCK` cutover, an `innodb_fast_shutdown=0` package upgrade, or an
xtrabackup snapshot apart from a genuine hang, and "healing" any of them mid-flight
can lose data.

The watchdog is therefore armed with a single maintenance marker,
`/run/boa_sql_maintenance.pid`:

- **While the marker exists, `mysql.sh` stands down entirely** — it exits before
  any check, so it never restarts, lock-breaks, or query-kills a server that is
  under deliberate maintenance.
- **A stale marker cannot disable auto-heal forever.** If the marker is older
  than four hours, `mysql.sh` treats it as abandoned (an operation that died
  without cleanup), removes it, and resumes normal healing. `/run` is tmpfs, so
  a reboot also clears it.
- The operations that set and clear the marker do so around their own critical
  sections:
  - the **Percona package upgrade** (`_install_with_aptitude_sql`) holds it
    across the whole apt transaction and the `innodb_fast_shutdown=0` restart;
  - **`xmass`** holds it on **both** hosts across `init` (the source snapshot and
    the target restore/replica bring-up) and across the whole `cutover` — the
    `FLUSH TABLES WITH READ LOCK` window is the single highest data-loss risk in
    the entire toolchain;
  - **`xoct`** holds it for `export` (`mydumper` on the source) and `import`
    (`myloader` plus `renameaegirhost`'s dump/reimport on the target).

You do not manage the marker by hand. It matters operationally for one reason:
**do not manually `service cron restart` or force the watchdog to run during a
migration or a Percona upgrade** expecting it to "help" — it is deliberately
muted, and that is correct. If a migration or upgrade dies hard and you are
recovering by hand, confirm the marker is gone (`ls /run/boa_sql_maintenance.pid`)
before you rely on the watchdog again; it self-clears after four hours regardless.

## What xmass needs on a Percona 8 box that a 5.7 box does not

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
The whole 8.x cluster of requirements only appears the first time you run
`xmass` against real Percona 8 servers.

## Cross-version xoct: what transfers and what to watch

`xoct`'s logical dump/restore is version-agnostic for the data itself — the DB
lands correctly on the newer server. Two behaviours are worth knowing when you
migrate onto a fresh Percona 8 target:

- **Post-migration cache/container state.** A migrated-in site can carry the
  source box's stale object cache and (for Drupal 8+) a stale service container.
  BOA does **not** attempt a per-site `drush cr` on import — outside Provision's
  bootstrap context that rebuild fatals on the D8+ Drush/Symfony patch state.
  Instead both `xoct import` and `xmass post-mig` do a **hard infrastructure
  flush**: cold-restart Valkey (or Redis) to drop the object cache, and restart
  every PHP-FPM master to drop opcache/APCu. This is the only treatment trusted
  against cache/container poisoning. Operational consequence: sites are briefly
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
target's install-time account of the same old name. Same-name migrations (the
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
correct outcome — cross-version is `xoct`'s job.

## Field validation — 2026-07

The behaviour above was validated end-to-end on Devuan Daedalus, 8-core ephemeral
boxes, BOA-5.10.3-lts, with two seed sites per account (Drupal 7 on PHP 7.4 and
Drupal 10 on PHP 8.4, each with a unique page marker and a marker DB table). The
Percona-8 boxes reached 8.4 via the real double-upgrade (5.7→8.0→8.4). Coverage
matrix, all passing:

| Scenario | Tool | Direction | Outcome |
|---|---|---|---|
| A57 | `xoct` | 5.7 → 5.7 | PASS (single-account, rename mode) |
| C57 | `xmass` | 5.7 → 5.7 | PASS (whole-server; xtrabackup-24 + GTID on 5.7) |
| A | `xoct` | 5.7 → 8.4 | PASS (cross-version DB jump, mydumper→myloader) |
| B | `xoct` | 8.4 → 8.4 | PASS (single-account, same version) |
| C | `xmass` | 8.4 → 8.4 | PASS (whole-server; xtrabackup-84 + GTID on 8.4) |
| D | `xmass` | 5.7 → 8.4 | PASS — refused at the version gate, target untouched |

The campaign exercised the tools against real Percona 8.4 for the first time and
drove the version-aware `xmass` behaviour and the watchdog-pause safety into the
shipped tools. The detailed per-scenario records and the fix history live in the
`boa-testing` Tier 3 campaign results, not here — this page documents the
resulting behaviour, which is what you operate against.
