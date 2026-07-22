# How To: Check Percona 8 Upgrade Readiness (codebasecheck)

A BOA host runs **one shared Percona server** for every Octopus instance, the Ægir
Hostmaster front end, and every hosted site. Because the whole box shares that one
server, a box-wide upgrade from Percona 5.7 to 8.0/8.4 (required to host Drupal 11) is
gated by the box's **oldest/least-compatible codebase**: one account that cannot run on
MySQL 8 blocks the upgrade for every other account on the box.

`codebasecheck` answers, before you run the upgrade, *which accounts — if any — block it*,
so you can move just those to a legacy Percona 5.7 host and let the rest upgrade.

## What counts as compatible

Core version is the primary gate. BOA's own managed platforms are always new enough, so
these thresholds only flag a customer's frozen custom platform pinned to an old core:

- **Drupal 6**: d6lts/Pressflow **6.51+** (adds MySQL-8 support — reserved-word escaping,
  `ONLY_FULL_GROUP_BY` handling, `mysql_native_password`). Older Drupal 6 is flagged.
- **Drupal 7**: **7.76+** (the release that added MySQL-8 support). Older is flagged.
- **Drupal 8**: **8.6.0+**. Older is flagged.
- **Drupal 9 / 10 / 11 and Backdrop**: supported.
- **Unrecognised codebase**: flagged for manual review (fail-safe).

A flagged (incompatible) codebase means that account must move to a legacy Percona 5.7
host before this box can upgrade — see the migration How Tos
[docs/MIGRATE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MIGRATE.md).

## Modes

```sh
codebasecheck <platform-path>    # check one codebase
codebasecheck --box              # box-wide readiness report (all accounts)
codebasecheck --box --deep       # box report + deep contrib/schema analysis
```

Single-codebase mode is also what the nightly maintenance runs per platform when
`/etc/boa/.allow-codebasecheck.cnf` exists, writing per-platform findings under each
account's `log/ctrl/`.

`--box` walks every `/data/disk/<user>` Octopus account, resolves each account's
platforms, classifies them, and rolls the result up per account:

```
Account o3: READY (22 codebase(s))
Account o7: BLOCKED
    BLOCK   /data/disk/o7/static/legacy/oldsite  [7.44]  Drupal 7 (7.44) predates 7.76 ...
...
RESULT: BLOCKED — these account(s) must move to a legacy Percona 5.7 VM before this box upgrades:
  - o7
```

## Verdicts and exit codes

| Verdict  | Exit | Meaning |
|----------|------|---------|
| READY    | 0    | Every codebase on the box is compatible with Percona 8.x. |
| REVIEW   | 2    | Cores are compatible, but `--deep` found signals to verify first. |
| BLOCKED  | 1    | At least one account's core cannot run on MySQL 8; move it off first. |

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

1. `codebasecheck --box --deep`
2. If **BLOCKED**: move the named account(s) to a legacy Percona 5.7 host
   ([docs/MIGRATE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MIGRATE.md)),
   then re-run.
3. If **REVIEW**: check each finding (raw SQL against a reserved-word table, a flagged
   module) on a test clone.
4. When **READY**: run the staged upgrade `barracuda up-lts system percona-8.0` then
   `barracuda up-lts system percona-8.4`
   ([docs/MAJORUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MAJORUPGRADE.md)).
