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
5. Source MySQL is briefly locked (`FLUSH TABLES WITH READ LOCK`) while the
   last file writes drain.
6. Target MySQL is promoted (slave decoupled, `RESET SLAVE ALL`).
7. `renameaegirhost` runs on the target for every Aegir root (master +
   all Octopus accounts), replacing the source hostname with the target FQDN
   and running a 5-pass Aegir task queue per root.
8. Target Solr starts (transaction logs pre-cleared for clean first start).
9. Source vhosts are converted to proxy via `xoct proxy` per account.
10. DNS is updated; traffic flows directly to target.

Typical total cutover window: **1–3 hours** (dominated by `renameaegirhost`
task queues for large numbers of accounts).

## State Machine

`xmass` tracks migration state in `/data/conf/xmass_state.cnf`. Phases:

```
(none) → init → syncing → cutover → complete
```

Each subcommand checks the current phase and refuses to run out of sequence.
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

`--permanent-proxy` signals that the source server will remain a permanent HTTP
proxy after cutover (rather than a temporary one pending DNS update). This
affects the wording of the migration-complete notification emails sent by
`xoct proxy` during cutover.

What `init` does:

1. Verifies SSH connectivity and Percona version match.
2. Installs `percona-xtrabackup-*` on source and target if not present.
3. Enables GTID mode on both servers (edits
   `/etc/mysql/conf.d/xmass_gtid.cnf`, restarts MySQL via `move_sql.sh`).
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
xmass sync target-ip
```

Syncs the following to the target on each run:

| Data | Path(s) |
|---|---|
| Shared BOA data | `/data/all`, `/data/disk/all`, `/data/disk/arch`, `/data/disk/legacy` |
| Static web root | `/var/www/static` |
| DNS zone data | `/etc/bind` |
| Usage logs | `/var/log/boa/usage` |
| Solr indices (best-effort) | `/opt/solr4`, `/var/solr7/data`, `/var/solr9/data` |
| Per-account platforms | `/data/disk/oN/distro/` |
| Per-account site files | `/data/disk/oN/static/files` (symlink-safe two-pass) |
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
xmass cutover target-ip [--permanent-proxy]
```

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
| Step 4 | Wait for replica lag = 0 (polls every 15 s, max 30 min, aborts if timeout) |
| Step 5 | `FLUSH TABLES WITH READ LOCK` on source |
| Step 6 | Final rsync pass of `static/files` only (catches last file uploads) |
| Step 7 | Triple-check lag = 0 at 10 s intervals (abort + UNLOCK if any check fails) |
| Step 8 | `STOP SLAVE; RESET SLAVE ALL` on target → target MySQL is now standalone |
| Step 9 | `UNLOCK TABLES` on source |
| Step 10 | Re-transfer `/root/.my.pass.txt` and `/root/.my.cnf` to target (belt-and-braces) |
| Step 11 | Drop replication user `xmass_repl` from source |
| Step 12 | Start nginx on target (serves proxied traffic while rename runs) |
| Step 13 | `renameaegirhost --aegir-root /var/aegir` on target (Aegir master) |
| Step 13 | `renameaegirhost --aegir-root /data/disk/oN` on target (each Octopus account) |
| Step 14 | Clear Solr transaction logs on target; start Solr; HTTP health check |
| Step 15 | Start cron on target; restore BOA runner scripts on target |
| Step 16 | `xoct proxy oN target-ip` for each account on source (vhost conversion + notifications) |
| Step 17 | Remove `http-off.pid` from all source accounts (belt-and-braces) |
| Step 18 | Write `proxied.pid` for all source accounts |
| Step 19 | Mark state `complete` |

If any step between 4 and 8 fails, the tool aborts and unlocks source MySQL
automatically. Source sites remain on 503 (`http-off.pid` in place) —
remove them manually and reload nginx to restore traffic while you
investigate.

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

`xmass init` writes `/etc/mysql/conf.d/xmass_gtid.cnf` on both servers if
GTID is not already enabled:

```ini
[mysqld]
server_id                = <derived from last two IP octets>
gtid_mode                = ON
enforce_gtid_consistency = ON
log_slave_updates        = ON
binlog_format            = ROW
expire_logs_days         = 7
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
| After `init` | Running normally | Stopped; held by `/root/.xmass_solr_hold.pid` |
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

**If `cutover` aborts:** source MySQL is automatically unlocked. Source nginx
is still serving 503 (`http-off.pid` in place). Manually remove
`/data/disk/*/static/control/http-off.pid` on source and reload nginx to
restore service, then investigate before retrying.

**If `cutover` completes but renameaegirhost failed** for one or more accounts:
run `renameaegirhost --aegir-root /data/disk/oN` manually on the target for
the affected accounts. This is safe to re-run.

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
- The `--permanent-proxy` flag changes only the wording in the notification
  emails sent during `xoct proxy` calls at cutover. All technical steps are
  identical regardless.
