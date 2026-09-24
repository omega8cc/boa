# How To: Check Percona 8 Upgrade Readiness (codebasecheck)

A BOA host runs **one shared Percona server** for every Octopus instance, the Ægir
Hostmaster front end, and every hosted site. Because the whole box shares that one
server, the in-place upgrade from Percona 5.7 to 8.0/8.4 (required to host Drupal 11) is
gated by the box's **oldest/least-compatible codebase**: one codebase that cannot run on
MySQL 8 blocks the upgrade for every site on the box until it is made compatible.

`codebasecheck` answers, before you run the upgrade, *which codebases — if any — block it*,
so you can bring those up to their MySQL-8 floor first. The upgrade itself is done in place
with `barracuda` and needs no migration — see
[docs/MIGRATE-PERCONA8.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MIGRATE-PERCONA8.md).

## What counts as compatible

Core version is the primary gate. BOA's own managed platforms are always new enough, so
these thresholds only flag a customer's frozen custom platform pinned to an old core:

- **Drupal 6**: d6lts/Pressflow **6.51+** (adds MySQL-8 support — reserved-word escaping,
  `ONLY_FULL_GROUP_BY` handling, `mysql_native_password`). Older Drupal 6 is flagged.

  The server side is BOA's job and handled on 8.0 and 8.4: `authentication_policy`
  advertises the native plugin (with `default_authentication_plugin` on 8.0 and the plugin
  loaded on 8.4), without which a `php56`-pool site cannot answer the `caching_sha2`
  handshake greeting at all (see docs/MIGRATE-PERCONA8.md). That lane is 8.x-only —
  MySQL/Percona 9.x removes `mysql_native_password` outright, so a box hosting php56-pool
  sites could not be upgraded in place to 9.x, and this check is the natural place to gate
  that if 9.x support ever lands.
- **Drupal 7**: **7.76+** (the release that added MySQL-8 support). Older is flagged.
- **Drupal 8**: **8.6.0+**. Older is flagged.
- **Drupal 9 / 10 / 11 and Backdrop**: supported.
- **Textpattern**: reported as MySQL-8 compatible.
- **Grav**: always `OK`, worded "MySQL-8 review not applicable" -- a flat-file site has no
  database.
- **Unrecognised codebase**: flagged for manual review (fail-safe).

A flagged (incompatible) codebase has to be brought up to its floor before this box can
upgrade: update that platform's core, or move its sites to a newer platform on this box
with Ægir's Migrate task — BOA's own current platforms always qualify. Then run the check
again. An unused old platform still counts while its Drush alias exists, so delete old
platforms you no longer need.

## Modes

```sh
codebasecheck <platform-path>    # check one codebase
codebasecheck --box              # box-wide readiness report (all accounts)
codebasecheck --box --deep       # box report + deep contrib/schema analysis
```

Single-codebase mode is also what the nightly maintenance runs per platform when
`_ALLOW_CODEBASECHECK=YES` is set in `/root/.barracuda.cnf` (the former
`/etc/boa/.allow-codebasecheck.cnf` flag stays honoured during the conversion
window). The zero-byte stamp under each account's `log/ctrl/` only makes the run
once-per-platform-per-night; the findings themselves go to the per-account night
log and, for non-OK codebases, to `/var/log/boa/core/incompatible-*.log`.

`--box` walks every `/data/disk/<user>` Octopus account, resolves each account's
platforms, classifies them, and rolls the result up per account:

```
Account o3: READY (22 codebase(s))
Account o7: BLOCKED
    BLOCK   /data/disk/o7/static/legacy/oldsite  [7.44]  Drupal 7 (7.44) predates 7.76 ...
...
RESULT: BLOCKED — the codebases flagged above must reach their MySQL-8 floor before this box
upgrades (update the core, or move their sites to a newer platform on this box), in:
  - o7
```

## Verdicts and exit codes

| Verdict  | Exit | Meaning |
|----------|------|---------|
| READY    | 0    | Every codebase on the box is compatible with Percona 8.x. |
| REVIEW   | 2    | Cores are compatible, but `--deep` found signals to verify first. |
| BLOCKED  | 1    | At least one codebase's core predates its MySQL-8 floor; update it, or move its sites to a newer platform on this box, and re-run. |

## Deep contrib/schema analysis (`--deep`)

A codebase can pass the core-version check yet still break on 8.x through contrib/custom
code or schema. `--deep` (needs the local MySQL root access via `/root/.my.cnf`; skips
cleanly if unavailable) adds a **REVIEW** tier driven by high-precision signals:

- **utf8mb3 tables** (all databases) — reported as **INFO only**; utf8mb3 runs fine on
  8.4, so this does not change the verdict. It flags where a `utf8mb4` conversion is
  pending if you need 4-byte/emoji data.
- **Reserved-word contrib table names** — a table named with a MySQL-8 reserved word
  (e.g. `groups`, `rank`), excluding the core `system` table which the DB layer always
  quotes. Flagged REVIEW: verify any raw/unquoted SQL against it. Reserved-word *columns*
  are intentionally not scanned — they are pervasive and always quoted by the schema layer.
- **Static code red-flags** in contrib/custom modules — `NO_AUTO_CREATE_USER` (a removed
  sql_mode that errors on 8.x) and the removed `TYPE=<engine>` CREATE TABLE syntax.

`--deep` surfaces risks for a human to verify; it is not a guarantee. The reserved-word
break only fires when a module runs raw unquoted SQL, which cannot be proven from the
schema alone — so a REVIEW result means *look before you trust the upgrade*, not *broken*.

Plain `--box` needs no database access and is fast; `--deep` scans every platform's module
tree and every database, so it takes longer.

## Logs

- `--box` / `--deep`: one report per run at `/var/log/boa/core/box-readiness-<ts>.log`.
- single-codebase incompatibilities: `/var/log/boa/core/incompatible-<ts>.log`.

## Typical workflow before a Percona 8 upgrade

1. Take a whole-server snapshot you can restore.
2. `codebasecheck --box --deep`
3. If **BLOCKED**: update each flagged codebase (the BLOCK line names its platform path and
   core version), or move its sites to a newer platform on this box, then re-run.
4. If **REVIEW**: check each finding (raw SQL against a reserved-word table, a flagged
   module) on a test clone.
5. When **READY**: run the in-place upgrade `barracuda up-lts system percona-8.0` then
   `barracuda up-lts system percona-8.4` (`up-pro`/`up-dev` on those trees)
   ([docs/MIGRATE-PERCONA8.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MIGRATE-PERCONA8.md)).
