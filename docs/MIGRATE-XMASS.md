# xmass — Full-Server BOA Migration

`xmass` migrates an entire BOA server in a single operation: all Octopus
accounts, all site databases, and all Solr cores move together. It uses MySQL
GTID binlog replication for the database layer and rsync for the filesystem
layer, so incremental syncs can run for days or weeks before a short cutover
window is needed.

## When to Use xmass

- Moving a complete BOA server to new hardware or a new provider.
- OS upgrade by migrating to a freshly installed server rather than upgrading
  in place.
- Any scenario where per-account `xoct` cycles would be impractical due to
  volume (many accounts, large databases, large Solr indices).

**Requirement:** both servers must run **identical Percona MySQL versions**
(e.g. both 8.0, both 8.4). If versions differ, use
[xoct](MIGRATE-XOCT.md) per account instead.

## Architecture Overview

```
SOURCE                                TARGET
──────                                ──────
MySQL (primary)  ─── GTID replication ──▶  MySQL (replica)
                                            reads only during sync
Octopus filesystems ── rsync (periodic) ──▶  /data/disk/oN/
Solr data           ── rsync (at cutover) ─▶  /var/solr*/data/
```

During the sync period (which can last days or weeks) the replica stays current
with zero additional load on the source beyond normal binlog writes. Rsync of
filesystem data is run on demand via `xmass sync`. At cutover:

1. All source web traffic is blocked (503 via `http-off.pid`).
2. Source Solr is stopped and locked out permanently.
3. A final rsync of all data runs.
4. The tool waits for replica lag to reach zero, then triple-confirms.
5. A final `static/files` pass runs — deliberately **before** the lock. The web
   block in step 1 is what stops file writes; a database read lock never gated
   them, so holding one across a walk of every store bought nothing and could
   hold the source database locked for hours on a large account.
6. Source MySQL is locked (`FLUSH TABLES WITH READ LOCK`) and the lag is
   re-confirmed three times under the lock.
7. Target MySQL is promoted (slave decoupled, `RESET SLAVE ALL`).
8. Panel DB access is rewired on the target for every Ægir root: the datadir
   swap killed the target's own panel databases, so the live (replicated)
   hostmaster DB is rediscovered per root, its DB user's password reset, and
   the surviving panel site dir's credentials rewritten to match.
9. `renameaegirhost` runs on the target for every Ægir root (master +
   all Octopus accounts), replacing the source hostname with the target FQDN
   and running a 5-pass Ægir task queue per root.
10. Target Solr starts (transaction logs pre-cleared for clean first start).
11. Source vhosts are converted to proxy via `xoct proxy` per account.
12. DNS is updated; traffic flows directly to target.

Typical total cutover window: **1–3 hours** (dominated by `renameaegirhost`
task queues for large numbers of accounts).

## State Machine

`xmass` tracks migration state in `/data/conf/xmass_state.cnf`. Phases:

```
(none) → init → syncing → cutover → complete
                             ↓
                       rename-failed  (resumable park; see below)
```

Each subcommand checks the current phase and refuses to run out of sequence.
`phase=cutover` is written only immediately before the MySQL lock, so anything
that aborts earlier in the cutover — a failed transfer, a store that will not
fit, a replica that never catches up — leaves the phase at `syncing` and is
recovered by simply re-running the DRY and `--live`.

If the phase does end up wrong, use `xmass reset-phase <phase>` rather than
editing `/data/conf/xmass_state.cnf` by hand. It is a recovery verb and it
warns about the unsafe transitions:

```sh
xmass reset-phase syncing         # only if the target was NOT promoted
xmass reset-phase rename-failed   # target promoted, only the rename tail left
```

`reset-phase` is exempt from the 90%-disk precondition, because a stalled
migration is a likely reason the disk filled in the first place.

To abandon and start over, remove the state file — but only do so if
replication has already been torn down on the target.

## Prerequisites

- Both servers running identical Percona MySQL versions.
- Root SSH key access from source to target (set up via `xmass pre-mig`).
- BOA installed on target at the same release as source (Octopus instances are
  not required on target — replication brings the databases).
- Disk on source: enough space for the xtrabackup staging directory (or stream
  capability if disk is tight — auto-detected; see [Transfer Method](#xtrabackup-transfer-method)).
- CSF on target: source IP whitelisted before running `init`.
- `percona-xtrabackup-*` (matching Percona version): installed automatically
  by `xmass init` if not already present.
- GTID mode: enabled automatically by `xmass init` on both servers if not
  already active. A separate BOA default enabling GTID is recommended but
  not required.

## Account Eligibility

`xmass` migrates only the Octopus accounts under `/data/disk` that pass **all**
of these:

- `log/cores.txt`, `log/option.txt` and `log/email.txt` all present
- `tools/le/dehydrated` present
- `log/CANCELLED` **absent**

Anything else is skipped. Both `sync` and `cutover` print the eligible list and,
for every skipped account, the specific condition it failed:

```
INFO: Eligible Octopus accounts: o1 o2 o5
ALRT: SKIPPED accounts under /data/disk — these will NOT be migrated:
ALRT:     o8: tools/le/dehydrated
ALRT: Confirm every skip above is intended before running --live.
```

**Read that list before every `--live` run.** A skipped account's databases
still replicate, because replication is server-wide, but its files never
transfer and its vhosts are never converted — and the cutover still reports
success. On a box where the skipped account carries most of the traffic, that
is a silent, total failure for those sites.

A skip does **not** mark the DRY run NOT CLEAN, because a genuinely cancelled
account is a legitimate skip. The check is yours to make.

## Terminology

| Placeholder | Meaning |
|---|---|
| `source-host` | Source server FQDN |
| `target-host` | Target server FQDN |
| `source-ip` | Source server IP (used in CSF rules) |
| `target-ip` | Target server IP (passed to all xmass commands) |

---

## Step-by-Step Procedure

### Phase 0 — Pre-migration Setup

Run on **both** hosts (source first, then target). Stops BOA background runners
and sets up root SSH key exchange between the two servers.

**On source:**
```sh
xmass pre-mig source-host
```

**On target:**
```sh
xmass pre-mig source-host
```

Also whitelist the source IP on the target firewall so xtrabackup streaming and
rsync can reach the target:

**On target:**
```sh
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.allow
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.ignore
csf -ra
```

### Phase 1 — Initialise Replication (`xmass init`)

Run on the **source** only.

```sh
xmass init target-ip [--permanent-proxy]
```

`--permanent-proxy` marks the source server as a **permanent** HTTP proxy after
cutover, rather than a temporary one to be decommissioned once DNS points at the
target. It changes two things at cutover and post-migration:

- The migration-proxy trust wired on the target — nginx realip recovery of the
  real client plus the CSF whitelist of the source's proxy IP — is marked
  permanent (`/data/conf/.migration_proxy_permanent.pid`). The `post-mig`
  teardown that would otherwise drop that trust becomes a deliberate no-op, so
  the source stays trusted (realip + csf) indefinitely.
- The migration-complete notification emails sent by `xoct proxy` are worded for
  a permanent rather than a temporary proxy.

What `init` does:

1. Verifies SSH connectivity and Percona version match.
2. Installs `percona-xtrabackup-*` on source and target if not present.
3. Enables GTID mode on both servers (writes `xmass_gtid.cnf` into the
   detected MySQL include dir — see [GTID Configuration](#gtid-configuration)
   for the path — then restarts MySQL via `move_sql.sh`).
4. Creates the replication user `xmass_repl`@`target-ip` on source.
5. Prevents Solr from auto-starting on target (holds it until cutover sync
   is complete).
6. Takes an xtrabackup snapshot and transfers it to target (staged or
   streamed — see [Transfer Method](#xtrabackup-transfer-method)).
7. Restores the snapshot into the target's `/var/lib/mysql` and starts MySQL.
8. Transfers `/root/.my.pass.txt` and `/root/.my.cnf` so the target MySQL
   client credentials match the restored data directory.
9. Configures and starts the MySQL replica (`CHANGE MASTER TO
   MASTER_AUTO_POSITION=1; START SLAVE`).

State file is written as `phase=syncing` on completion.

### Phase 2 — Sync Files (`xmass sync`)

Run on the **source**. Repeat as often as needed — rsync is incremental.

```sh
xmass sync target-ip            # DRY: read-only test/plan, no changes
xmass sync target-ip --live     # perform the sync (after a CLEAN dry run)
```

> **`xmass sync` and `xmass cutover` default to a read-only DRY run** and require an
> explicit **`--live`** to make changes — accepted only after a `CLEAN` dry run for that
> target. The DRY pass resolves the target's storage, prints the plan (`[DRY-PLAN] …`),
> pre-checks disk space for every account's files store **and the Solr indices** (which
> can be large), and records `CLEAN`/`NOT CLEAN`
> for the whole run — a single `DENY` (dangling source symlink, more than one `/mnt`
> mount, or a store that fits nowhere) makes it `NOT CLEAN` and refuses `--live` until
> resolved. Utility/DB commands (`init`, `status`, `pre-mig`, `post-mig`) are not gated,
> and MySQL/xtrabackup steps are never gated.

Syncs the following to the target on each run:

| Data | Path(s) |
|---|---|
| Shared BOA data | `/data/all`, `/data/disk/all`, `/data/disk/arch`, `/data/disk/legacy` |
| Static web root | `/var/www/static` |
| DNS zone data | `/etc/bind` |
| Usage logs | `/var/log/boa/usage` |
| Solr indices (best-effort) | `/opt/solr4`, `/var/solr7/data`, `/var/solr9/data` |
| Per-account platforms | `/data/disk/oN/distro/` |
| Per-account site files | `/data/disk/oN/static/files` (storage-aware: mirrored onto the target's `/mnt` mount, or de-referenced to root if it has none) |
| Per-account drush aliases | `/data/disk/oN/.drush/` (site aliases only) |
| Per-account nginx vhosts | `/data/disk/oN/config/server_master/nginx/vhost.d/` |
| Per-account SSL/LE | `/data/disk/oN/config/ssl.d/`, `config/server_master/ssl.d/`, `tools/le` |
| FTP account SSH keys | `/home/oN.ftp/.ssh` |

MySQL data is **not** rsynced — replication keeps it current continuously.

Run `xmass sync` immediately after `init` for the first full pass (which may
take several hours for large accounts), then periodically as the cutover date
approaches to reduce the amount of data left to transfer at cutover time.

### Phase 3 — Monitor (`xmass status`)

```sh
xmass status target-ip
```

Displays current phase, last sync timestamp, and live replication lag in
seconds. Aim for lag < 60 s before scheduling cutover.

### Phase 4 — Cutover (`xmass cutover`)

Run on the **source**. This is the only step with user-visible downtime.

```sh
xmass cutover target-ip [--permanent-proxy]            # DRY: plan only, no lock/downtime
xmass cutover target-ip --live [--permanent-proxy]     # perform the cutover
```

Without `--live`, `cutover` does a plan-only pass over every account's files store and
stops **before** any destructive step (no MySQL read-lock, no downtime). Run it once to
confirm `CLEAN`, then re-run with `--live` to perform the real cutover.
`--permanent-proxy` on cutover overrides whatever was set at `init`.

**Pre-flight checks** (automatic):

- Confirms phase is `syncing`.
- Confirms no BOA background jobs are running (runner.sh, daily.sh, etc.).
- Confirms system cron is stopped.

**Cutover sequence:**

| Step | What happens |
|---|---|
| Step 0 | Re-hold Solr on target (in case it was manually started since init) |
| Step 1 | Write `http-off.pid` for all accounts → nginx serves 503 on source; purge speed cache |
| Step 2 | Stop all Solr instances on source; touch `/root/.deny.java.cnf` (permanent deny) |
| Step 3 | Final rsync: shared data, Solr (now clean — source stopped), all account data |
| Step 3.5 | **Gate:** abort if any store could not be placed or any transfer failed — before anything destructive |
| Step 4 | Wait for replica lag = 0 (polls every 15 s; ceiling `_XMASS_SYNC_MAX_WAIT`, default 7200 s; on timeout reports whether the lag is closing or growing) |
| Step 5 | Final rsync pass of `static/files` only, **before** the lock (the web block already stopped file writes) |
| Step 5.5 | **Gate:** re-check both of the above, then persist `phase=cutover` |
| Step 6 | `FLUSH TABLES WITH READ LOCK` on source |
| Step 7 | Triple-check lag = 0 at 10 s intervals (abort + UNLOCK if any check fails) |
| Step 8 | `STOP SLAVE; RESET SLAVE ALL` on target → target MySQL is now standalone |
| Step 9 | `UNLOCK TABLES` on source |
| Step 10 | Re-transfer `/root/.my.pass.txt` and `/root/.my.cnf` to target (belt-and-braces) |
| Step 11 | Drop replication user `xmass_repl` from source |
| Step 12 | Start nginx on target (serves proxied traffic while rename runs) |
| Step 12.5 | Rewire panel DB access on target per Ægir root (rediscover live hostmaster DB, reset its user's password, rewrite the panel dir's credentials — the datadir swap killed the fresh-install panel DBs) |
| Step 13 | `renameaegirhost --aegir-root /var/aegir --force-old source-fqdn` on target (Ægir master) |
| Step 13 | `renameaegirhost --aegir-root /data/disk/oN --force-old source-fqdn` on target (each Octopus account) |
| Step 14 | Clear Solr transaction logs on target; start Solr; HTTP health check |
| Step 15 | Start cron on target; restore BOA runner scripts on target |
| Step 16 | `xoct proxy oN target-ip` for each account on source (vhost conversion + notifications) |
| Step 17 | Remove `http-off.pid` from all source accounts (belt-and-braces) |
| Step 18 | Write `proxied.pid` for all source accounts |
| Step 19 | Mark state `complete` |

If any step between 4 and 8 fails the tool aborts and unlocks source MySQL
automatically — including the target promote in step 8, which previously
aborted while still holding the lock.

Source sites remain on 503 (`http-off.pid` in place). Every abort that happens
after the web block prints the exact commands to restore service on the source,
so follow the printed recipe rather than reconstructing it: clear the
`http-off.pid` files, purge the nginx speed cache, reload nginx, remove the Solr
deny file if Solr served from here, start cron, and un-park the five runners.

#### Tuning the replica wait

Step 4 polls until replica lag reaches zero. The ceiling is
`_XMASS_SYNC_MAX_WAIT` seconds, default **7200**; export a different value
before running `cutover` if the source is write-heavy:

```sh
_XMASS_SYNC_MAX_WAIT=14400 xmass cutover target-ip --live
```

On timeout the tool reports the first, previous and last lag samples and says
whether the lag is **closing** or **growing** in the most recent interval — a
growing lag will not be fixed by waiting longer. Percona 5.7 applies the relay
log single-threaded unless told otherwise, so on a busy source set
`slave_parallel_type=LOGICAL_CLOCK` and `slave_parallel_workers=4` on the target
right after `init` rather than raising the ceiling.

### Phase 5 — Post-migration (`xmass post-mig`)

Run on the **target** after DNS has been updated and traffic flows directly.

```sh
xmass post-mig
```

Ensures Solr services are running cleanly, reloads nginx, and restores any
remaining BOA runner scripts.

---

## xtrabackup Transfer Method

`xmass init` automatically selects between staging and streaming based on
available disk space on the source `/` filesystem:

- **Stage:** if free space > 1.5× the MySQL data directory size, the backup
  is written locally to `/var/backups/xmass_stage`, prepared (`--prepare`),
  then rsynced to the target. More disk I/O but easier to resume if the
  transfer is interrupted.
- **Stream:** if free space is insufficient, the backup is piped directly via
  `xbstream` over SSH to `/var/backups/xmass_restore` on the target, where it
  is then prepared. No staging disk required on source.

Example: 154 GB MySQL, 73 GB free on `/` → stream method selected (73 GB < 231 GB needed).

The correct `percona-xtrabackup-*` package (24, 80, or 84) is detected from
the running Percona version and installed automatically if absent.

---

## GTID Configuration

`xmass init` writes `xmass_gtid.cnf` on both servers if GTID is not already
enabled. The MySQL include directory is detected from the `!includedir` that
`my.cnf` actually reads (parsed at runtime), falling back to the first of
`/etc/mysql/conf.d`, `/etc/mysql/percona-server.conf.d`,
`/etc/mysql/mysql.conf.d`, then `/etc/mysql` only if `my.cnf` declares none.
On a BOA box this resolves to `/etc/mysql/conf.d/xmass_gtid.cnf` — detecting by
directory existence alone is wrong there, because `percona-server.conf.d`
exists but BOA's `my.cnf` includes only `conf.d`, so a conf dropped in the
former is never parsed and GTID stays OFF after restart. Contents:

```ini
[mysqld]
server_id                = <derived from last two IP octets>
gtid_mode                = ON
enforce_gtid_consistency = ON
log_slave_updates        = ON
binlog_format            = ROW
expire_logs_days         = 7          # 5.7 only; 8.0+ uses binlog_expire_logs_seconds = 604800 (expire_logs_days was removed in 8.4)
log_bin                  = /var/lib/mysql/mysql-bin  # only if binlog not already on
```

MySQL is restarted via `/var/xdrago/move_sql.sh restart` (which also stops
nginx and PHP-FPM gracefully before stopping MySQL, then starts them again).

If GTID is already enabled by BOA default configuration the existing settings
are left untouched.

---

## Solr Handling

| Stage | Solr on source | Solr on target |
|---|---|---|
| After `init` | Running normally | Stopped; held by `/var/log/boa/.xmass_solr_hold.pid` |
| During `sync` | Running normally | Still held (best-effort Solr rsync only) |
| Cutover step 0 | Running | Re-held and stopped (safety) |
| Cutover step 2 | Stopped; `/root/.deny.java.cnf` created | Held |
| Cutover step 3 | Stopped (clean index state) | Held (final Solr rsync with clean source) |
| Cutover step 14 | — | Tlogs cleared; Solr started; HTTP health check |
| `post-mig` | — | Solr restarted cleanly |

Clearing transaction logs (`tlog/` directories) before starting Solr on the
target prevents double-indexing of any writes that were buffered at the moment
the source Solr was stopped.

---

## MySQL Credentials

xtrabackup replaces the entire `/var/lib/mysql` directory on the target,
including the `mysql` system tables. This means the target's MySQL root
password becomes the source's password. `/root/.my.pass.txt` and
`/root/.my.cnf` are therefore transferred from source to target at two points:
immediately after restore (so MySQL client tools work during slave setup) and
again after promotion at cutover (belt-and-braces, in case anything changed).

---

## State File

`/data/conf/xmass_state.cnf` stores the current migration state. Contents:

```sh
_XMASS_TARGET_IP=<ip>
_XMASS_SRC_IP=<ip>
_XMASS_REPL_PSWD=<generated password>
_XMASS_PERCONA_V=<8.0|8.4|5.7>
_XMASS_INIT_TIME=<YYYYMMDD-HHMMSS>
_XMASS_LAST_SYNC=<YYYYMMDD-HHMMSS>
_XMASS_PHASE=<init|syncing|cutover|complete>
_XMASS_PERMANENT_PROXY=<YES|NO>
```

The file is `chmod 600` (contains the replication password). Do not commit it
to version control.

---

## Aborting or Starting Over

**If `init` fails before replication starts:** remove the state file and retry.

**If `init` fails after replication starts:** on the target run
`mysql -e 'STOP SLAVE; RESET SLAVE ALL;'` to decouple, then drop the
replication user from source
(`mysql -e "DROP USER IF EXISTS 'xmass_repl'@'target-ip';"`)
and remove the state file.

**If `cutover` aborts:** source MySQL is automatically unlocked and the tool
prints the full restore recipe for the source; follow it rather than doing it
from memory. An abort before the lock leaves the phase at `syncing`, so retrying
is a fresh DRY plus `--live` with nothing else to undo.

**If the panel rewire or renameaegirhost fails** for any root, `cutover` parks
resumably at `phase=rename-failed` instead of completing — the failure report
names the affected roots. Fix the cause, then re-run
`xmass cutover target-ip --live` to resume from the parked step (both steps
converge: already-rewired panels and already-renamed roots no-op). To
iterate on a single root first, run
`renameaegirhost --aegir-root /data/disk/oN --force-old source-fqdn` manually
on the target — it is convergent and safe to re-run — then resume the cutover
so the remaining cutover steps complete.

---

## Notes

- `xmass sync` is idempotent — run it as often as you like. Each run is a
  delta rsync; subsequent runs after the first are fast.
- The replication user `xmass_repl` is created only on the source and is
  dropped automatically at cutover. It is never present in normal BOA
  configuration.
- `xmass` enumerates Octopus accounts dynamically from `/data/disk/` — no
  manual account list is needed.
- After cutover the source server functions as an nginx HTTP/HTTPS proxy for
  all migrated sites. It is independent of the target and can be
  decommissioned as soon as DNS has propagated and you are satisfied with the
  target.
- The `--permanent-proxy` flag keeps the source's migration-proxy trust on the
  target permanent: the `post-mig` teardown that normally drops the nginx realip
  + CSF whitelist of the source proxy IP is skipped, so the source stays trusted
  indefinitely. It also words the `xoct proxy` notification emails for a
  permanent rather than a temporary proxy. Without it, the trust is temporary and
  `post-mig` removes it once traffic flows directly to the target.
