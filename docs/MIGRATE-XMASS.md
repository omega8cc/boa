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

**Requirement:** both servers must run **identical Percona MySQL versions —
series AND patch level** (e.g. both 8.4.13, never 8.4.10 vs 8.4.13). A series
mismatch means xmass is the wrong tool: use [xoct](MIGRATE-XOCT.md) per
account instead. A patch-level mismatch means align the packages first —
failing back a newer datadir onto an older primary is an unsupported
downgrade. Both are enforced gates at `init` (the series gate reads the
client binary, the patch gate asks the server via `SELECT VERSION()`); a
deliberate patch skew can be allowed with `_XMASS_ALLOW_PATCH_SKEW=YES`,
which accepts the forward direction only — a target older than the source
is refused regardless.

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
filesystem data is run on demand via `xmass sync` — or continuously, once the
operator arms `xmass autosync`, which repeats the live sync legs on a fixed
cadence from the active side (see [Automated file sync](#automated-file-sync-for-a-standing-mirror-xmass-autosync);
this is what keeps a **standing mirror's** files fresh, not just its
database). At cutover:

1. All source web traffic is blocked (503 via `http-off.pid`).
2. Source Solr is stopped and locked out permanently.
3. A final rsync of all data runs.
4. The tool waits for replica lag to reach zero, then triple-confirms.
5. A final `static/files` pass runs — deliberately **before** the lock. The web
   block in step 1 is what stops file writes; a database read lock never gated
   them, so holding one across a walk of every store bought nothing and could
   hold the source database locked for hours on a large account.
6. An **advisory** read-only flag is appended to
   `/data/conf/global/global-extra.inc` (the previous file kept beside it as
   `.bak`). This is the step the rest of this runbook calls the *write
   freeze*, and it is belt-and-braces only: the include is box-wide, most site
   shapes ignore it (`site_readonly` needs the `readonlymode` module enabled
   per site), and a `barracuda up-<tree> system` pass on the source rewrites
   the include from the shipped copy, dropping the block. `xoct` refuses the
   same mechanism for the same reasons — see
   [MIGRATE-XOCT.md](MIGRATE-XOCT.md). What actually stops writes for the
   window is the step-1 503 gate plus the parked cron and BOA runners, both
   already in force, so a flag that cannot be written **warns and the cutover
   continues**. A session-scoped read lock is not used at all: it cannot hold
   anything once its client disconnects; the surviving `FLUSH TABLES` only
   pushes buffers. The lag is then re-confirmed three times.
7. Target MySQL is promoted (slave decoupled, `RESET SLAVE ALL`); the freeze
   flag is removed on the **target** later in the sequence. On the source it
   stays for the life of the proxy — the old box serves through the proxy
   from here, but if you roll back to it, restore the include from its
   `.bak`. (An abort that **proves** the promotion did not hold thaws the
   source by itself; a post-promotion park — and a promotion failure whose
   state cannot be read back — keeps the source 503-gated with the flag in
   place, on purpose.)
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
xmass reset-phase rename-failed   # target promoted, only the cutover tail left
```

Arming `rename-failed` re-runs the cutover tail from its head: the resume
**re-asserts the 503 gate and the write freeze on the source**, drops the
replication user, and re-proves the target's web layer before the panel
rewire and the renames.

`reset-phase` is exempt from the 90%-disk precondition, because a stalled
migration is a likely reason the disk filled in the first place.

To abandon and start over, remove the state file — but only do so if
replication has already been torn down on the target.

**Single-flight.** Every state-mutating verb (`pre-mig`, `prep-target`,
`init`, `sync`, `cutover`, `reset-phase`, `post-mig`, `restore-solr`) takes a
box-wide owner-PID lock and a concurrent run is refused non-zero, naming the
owning process. `status` and `verify` stay unlocked, so a migration can always
be inspected mid-run. Liveness — not the file — is what is checked: a killed
run leaves nothing to clean up, and a recycled PID belonging to some other
process does not block.

## Prerequisites

- Both servers running identical Percona MySQL versions — series and patch
  level (both gated at `init`; see the requirement above).
- Root SSH key access from source to target (set up via `xmass pre-mig`;
  the source also learns the target's SSH host key automatically). The verb
  is two-sided: run `xmass pre-mig <own-fqdn>` ON the source to publish its
  key (publish mode fires when the argument equals the box's own hostname),
  then `xmass pre-mig <source-address>` ON the target to fetch and install
  it. On a failback chain the roles have swapped — publish on the new
  source first, or the fetch finds nothing (a proxied box relays its
  undefined vhost onward instead of serving the key).
- BOA installed on target at the **same release** as source. This is an
  enforced gate, not advice: `prep-target` reads the release stamp from
  `boa info` on both ends at first target contact and **refuses with no
  override** when they differ — a target missing a central-map nginx variable
  a newer release introduced fails the box-wide config test and takes down
  every migrated site, not only the site that needed it. The tree may
  legitimately differ (lts vs pro); an unreadable stamp on either side is
  fatal too ("refusing to migrate blind"). The fix is a FULL run — barracuda
  AND octopus — on the older box, then re-run. The same comparison is
  re-asserted at `init` and again in the `cutover --live` pre-flight (and
  reported as a `DENY` in the cutover DRY run), because `prep-target` is not
  a precondition of `init` and BOA is rolling — a tag can move either box
  during the days or weeks of incremental syncs.
- **An installed Octopus account on the target for every eligible source
  account, with matching names.** Replication brings the databases, but the
  files rsync into `/data/disk/<oN>/`, the cutover renames each Ægir root and
  the panel rewire runs per root — all of which need a real install (system
  user, FPM pool, vhost include), not a directory. `xmass prep-target` creates
  them; `init`, `sync` and `cutover` all refuse to proceed without them.
- **The target's Solr set mirrors the source's *used* set.** A hosted-named
  target installs all three Solr versions on its first full `barracuda` pass,
  while a migration target should carry only what its source actually uses.
  `prep-target` gates on this and, without `--fix-solr`, **refuses on any
  mismatch**; `init`, `sync` and `cutover` re-gate on the same comparison. The
  classification measured while the source is still healthy is recorded in
  `/data/conf/xmass_solr_used.cnf`, because a post-cutover source reads as
  using nothing.
- Disk on source: enough space for the xtrabackup staging directory (or stream
  capability if disk is tight — auto-detected; see [Transfer Method](#xtrabackup-transfer-method)).
  `init` also checks the **target** has room for the datadir restore before
  displacing anything (override: `_XMASS_SKIP_DISK_GATE=YES`).
- CSF: source IP allowed on the target **and** target IP allowed on the source
  — the target dials back to source:3306. `prep-target` appends each peer to
  **both** `csf.allow` and `csf.ignore` (append-once) and reloads CSF: an
  allow on its own is not durable, because the login-failure daemon can still
  temp-deny the peer mid-migration, and a temp-deny on the reverse path fails
  `init` *after* the target datadir has been replaced. The reverse path is
  proven before anything destructive depends on it.
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

On both hosts `pre-mig` first forces the migration tool set current: it drops
the per-tool control markers for the six migration tools, runs the 5-minute
housekeeping script synchronously, then logs each tool's resulting version
line — so a migration is never run on stale tooling. The tool executing the
command itself refreshes on the next verb, not mid-run (the fetcher refuses to
replace a live process), and the log says so.

In target mode `pre-mig` also removes this box's OWN published root public key
from the nginx web root, not just the fetched copy — a box that was ever a
migration source otherwise goes on serving a root public key at the
undefined-host URL indefinitely, and a later migration could fetch the wrong
box's key from it. It also opens the firewall for the source, which the source
can never arrange for itself.

**On source:**
```sh
xmass pre-mig source-host
```

**On target:**
```sh
xmass pre-mig source-host
```

### Phase 0.5 — Prepare the target (`xmass prep-target`)

Run on the **source**, after `pre-mig` has completed on both hosts and before
`init`. This is everything the target must have in place before its Octopus
accounts exist and before `init` replaces its datadir:

```sh
xmass prep-target target-ip [--fix-php] [--fix-solr]
```

What it does, in order:

0. **Tool refresh + same-release gate** — forces the migration tool set
   current on the target (markers dropped, housekeeping run, versions logged),
   then compares both boxes' BOA release stamps and refuses on a mismatch or
   an unreadable stamp (see Prerequisites — no override).
1. **CSF both directions** — appends each peer to both `csf.allow` and
   `csf.ignore` here and there (an allow alone still leaves the peer exposed
   to a guard temp-deny mid-migration), reloads CSF, then proves the reverse
   `target → source:3306` path by opening it. A dead reverse path is fatal now
   rather than at `init`, which fails *after* the target datadir has already
   been replaced. Override with `_XMASS_SKIP_REVERSE_CHECK=YES` if you
   firewall differently.
2. **Solr coverage gate** — classifies each Solr version's use on the source
   from measured state (installed and listening service, dotted core names,
   the one-year `data/index` write bar, `boa_site_control.ini` bindings and
   the `SR*` opt-in tokens), then compares that used set against the target's
   own install and deny state. Live bindings count as used regardless of write
   age, and a version that reads as ambiguous is reported for a per-box ruling,
   never auto-denied. Without `--fix-solr` the gate is **fatal on every defect
   class**, repairable ones included — it is stricter here than the `init`,
   `sync` and `cutover` re-gates, which refuse only on a used version that is
   not serviceable on the target. It runs **before** the PHP gate on purpose:
   `--fix-php` drives a full `barracuda system` pass on the target, and on a
   hosted-named box that pass is exactly the all-three-Solr install trigger, so
   the deny set must be on the target's disk before it. `--fix-solr`
   reconciles: per-version denies (`_DENY_JETTY9`/`_DENY_SOLR7`/`_DENY_SOLR9`
   plus the `/etc/boa/.deny.*.cnf` markers) for every unused version, the
   blanket java pair when the source uses no Solr at all, unparking of used
   versions by driving the target's own `xmass restore-solr`, and any still
   missing used version queued onto the system pass (shared with `--fix-php`'s
   pass when both are owed). The fix path refuses by design on two target
   shapes: a finalized PX0 proxy (`/root/.proxy.cnf`), where Solr is down
   deliberately and the proxy shape has to be undone first, and a target whose
   tool set is too stale to have `xmass` on `PATH` — re-run `xmass pre-mig`
   there, then re-run this. Why it is a gate at all: the first `sync` lands
   every source Solr data tree on the target, and a landed tree makes BOA's
   installer treat that version as installed forever, so a used version that
   is not serviceable there surfaces only after promotion, as silently broken
   search.
3. **PHP coverage gate** — collects every version pinned by any eligible
   account (`static/control/fpm.info`, `cli.info`, and the per-site column of
   `multi-fpm.info`) and verifies each is installed on the target. Missing
   versions are fatal, because a pinned-but-absent PHP is silently downgraded
   by BOA's own fallback ladder and the affected sites serve on the wrong
   interpreter. With `--fix-php` the missing versions are appended to the
   target's `_PHP_MULTI_INSTALL` and one `barracuda up-<tree> system` pass is
   driven there to build them (~30 minutes).
4. **Certificate health sweep** on the source — names every zero-byte,
   unparseable or expired certificate, so a broken renewal is fixed before the
   migration rather than debugged alongside it.
5. **Per-account install and seeding** — drives `xoct create` for each eligible
   account, which installs from the **target's own tree** with the source's
   plan stamps, then seeds the account's `/root/.<oN>.octopus.cnf` (portable
   values only), force-copies the PHP pin files and carries the client's shell
   credentials. Already-installed accounts are re-seeded, not re-installed.
6. **Suspension flags** mirrored (`/data/conf/suspended/<oN>.pid` lives outside
   the account tree, so no file sync can carry it — an unmirrored suspension
   means a non-paying account resumes serving on the target).
7. **Verification** — refuses to report success unless every eligible account
   is present on the target as a real install.

The verb is idempotent: re-run it after fixing anything it refused on.

### The target-silence gate (prep-target, init, cutover)

Every account install and every re-seed on the target leaves a background
octopus pass behind, and each pass queues platform verifies that the Ægir
queue runs minutes later. A target is **silent** when it holds no BOA run
lock (`/run/boa_run.pid`, `/run/boa_wait.pid`, `/run/octopus_install_run.pid`),
no account has `static/control/run-upgrade.pid` armed, every root's
`hosting_task` queue is empty (current revisions, queued or processing) and no
dispatch, verify or installer process runs. The probe fails closed: an
unreadable root or an unreadable target counts as busy.

- `prep-target` reports the wait after its account verification; a timeout
  there only warns (nothing destructive follows).
- `init` waits, bounded, before its first target mutation and refuses on
  timeout.
- `cutover --live` waits, in the narrower run-locks-and-processes scope (the
  target is a standby: its runner never consumes an armed pid and its panel
  rows are the source's), after every cheap refusal and before the first
  source mutation; the DRY run reports a busy target as a DENY.

Knobs: `_XMASS_TARGET_SILENT_MAX_WAIT` (seconds, default 2400) and
`_XMASS_SKIP_TARGET_SILENCE=YES` (skip the wait deliberately, logged). Related
`xoct create` knobs: `_XOCT_TARGET_QUIET_MAX_WAIT` (wait for a quiet target
before the account install, default 1800) and `_XOCT_CREATE_MAX_WAIT` (the
post-install settle, default 900).

### Phase 1 — Initialise Replication (`xmass init`)

Run on the **source** only.

```sh
xmass init target-ip [--proxy-mode=temporary|permanent|ha-switch] [--proxy-deadline=YYYY-MM-DD|+Nd]
```

Proxy policy is **per Octopus account**, not per box. `--proxy-mode` writes only
the box **default** (`/data/conf/migproxy_mode.txt`); each account's own record
(`/data/disk/oN/log/migproxy.cnf`, set with `xoct proxy-mode oN <mode>`) always
wins over it. Only a **source-role** record participates: a record whose role
is `target` — the inbound half of the peer pair, stamped when this box was
itself brought in by a migration — is ignored for this box's own proxy-mode
resolution, so on a chained move (a box migrated in yesterday, migrating out
today) a travelled inbound record can never outrank the operator's explicit
`--proxy-mode`. The resolved mode decides, per account:

- what the migration-complete email tells that customer about the old address
  (temporary with or without a deadline, kept in place, or an HA switch point);
- whether the migration-proxy trust on the target (nginx realip recovery of the
  real client plus the CSF whitelist of the source's proxy IP) survives
  `post-mig` — any account resolving `permanent` or `ha-switch` keeps it, and
  the target's `migration_proxy_trust.sh reconcile` recomputes the kept peer
  set from the per-account records (`ha-switch` behaves exactly as `permanent`
  for trust and teardown; it differs only in the client notification).

`--proxy-deadline` sets the box-default deadline the temporary/permanent mail
blocks quote; it accepts an absolute date or `+Nd` and refuses past dates.
`--permanent-proxy` remains a deprecated alias for `--proxy-mode=permanent`.

`init` prints each account's resolved mode and names any account that would
fall back to the built-in default — declare those before cutover, because
`cutover --live` refuses to proceed while any account is undeclared. Modes are
declared here at init time precisely because this is the cheap moment to fix
them; discovering an undeclared account inside the cutover window is the
expensive one.

What `init` does:

0. Re-gates what `prep-target` established, because a hand-prepared target must
   be verified rather than trusted: the same BOA release on both ends, every
   eligible account installed on the target, every pinned PHP version present
   there, the target's Solr set still
   mirroring the source's recorded used set, the two derived replication
   `server_id`s distinct (they come from the last two IP octets only, so two
   boxes in one /16 collide and replication simply refuses to start), and the
   target has room for the datadir restore. It also sweeps the source's
   certificates for broken renewals. Each of these refuses **before** anything
   destructive happens.
1. Verifies SSH connectivity and Percona version match.
2. Installs `percona-xtrabackup-*` on source and target if not present.
3. Enables GTID mode on both servers (writes `xmass_gtid.cnf` into the
   detected MySQL include dir — see [GTID Configuration](#gtid-configuration)
   for the path — then restarts MySQL via `move_sql.sh`).
4. Creates the replication user `xmass_repl`@`target-ip` on source.
5. Prevents Solr from starting on the target: stops it AND disarms its
   init scripts (exec bit and rc links dropped), so neither boot, a
   barracuda pass, nor the java.sh watchdog can bring it back mid-sync.
   `/var/log/boa/.xmass_solr_hold.pid` records the hold, and java.sh
   re-asserts the disarm every minute while it exists. Cutover step 14
   or `post-mig` re-arm symmetrically.
5a. **Arms the standby write gates on the target.** `/root/.standby.cnf`
   is written FIRST, before the datadir swap, together with an in-flight
   signal (`/run/boa_xmass_init.pid`). Cron stays RUNNING for the whole
   window — a standby is a working BOA box, with IDS and every watchdog
   live — and passivity comes from per-job gates on the marker in every
   local writer: the task queue and the Aegir dispatch it parks, the
   night work, cache TRUNCATEs, Solr core management, binlog purge,
   mysqlcheck repairs, cluster dumps, and the whole duplicity backup
   chain (`mybackup`, `multiback`, `backboa`, `duobackboa` exit quietly —
   the active owns the backup lineage). On top of the gates, init locks
   the replica's database outright: the `xmass-standby-hold` block
   (`read_only` + `super_read_only`) is written into the target's
   `xmass_gtid.cnf` — so the lock survives every mysqld restart and
   reboot — and set live once the replica threads verify. The
   replication appliers are exempt by definition; everything else, root
   included, is refused at the server. The mysql watchdog re-asserts the
   lock every minute, converts a standing mirror built by older bytes
   the same way (it appends the block and locks the runtime), and
   releases it only once the marker is gone — with the runtime unlock
   verified BEFORE the block is stripped. The web tier is held DOWN for
   the whole window (the `start()` gate in the shipped nginx init script
   covers even the boot rc links, the per-minute enforcer covers
   everything else, and the `BOA_STANDBY_WEB` firewall chain — IPv4+IPv6,
   loopback exempt — is re-added by `csfpost.sh` after any `csf -r`),
   FTPS is killed on sight with its self-healer standing down, and
   tenant lshell/mysecureshell logins flip to `nologin` (recorded, with
   the release restoring exactly the recorded users). The operator
   escape hatch `/root/.standby.serve.cnf` opens the WEB tier only — a
   read-only preview; the DB, tenant, FTPS and backup holds all stay.
   Both `init` and `prep-target` first read the target's marker back and
   hard-refuse a role clash: a target serving as a DIFFERENT source's
   standby is never overlaid (same-source is the normal re-init repair
   path), `prep-target` refuses ANY standby target, a box that itself
   carries the marker refuses to source a migration, and the probe fails
   CLOSED on a transport error. The in-flight signal tells
   second.sh that an empty role probe is expected until replication
   starts. second.sh mirrors it to a reboot-proof twin
   (`/root/.standby.init.pid`), so a target reboot inside the window
   cannot license promotion; both clear once the replica runs, or when the
   marker goes, and both age out under a dead init.
5b. **Purges unfinished `delete` tasks** from every eligible account's
   hostmaster queue before the databases travel: the whole panel DB
   replicates, cutover runs the task queue with force on the target, and a
   stranded delete (xmass's own `pre-mig` kills the dispatcher, which is
   exactly how one strands) would execute against brand-new production.
   Other task types are reported at cutover, never deleted.
6. Takes an xtrabackup snapshot and transfers it to target (staged or
   streamed — see [Transfer Method](#xtrabackup-transfer-method)). The
   snapshot bounds its backup-lock wait (15 minutes) and kills a query
   that blocks it after 60 s regardless of method, so an `init` cannot
   sit forever behind one long report.
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
> for the whole run — a single `DENY` (a dangling **named store** such as
> `static/files` or `arch`, more than one `/mnt` mount, or a store that fits nowhere)
> makes it `NOT CLEAN` and refuses `--live` until resolved. A dangling link found by
> the out-of-root **sweep** is reported but never a `DENY` by itself. Utility/DB commands (`init`, `status`, `pre-mig`, `post-mig`) are not gated,
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
| Per-account source trees | `/data/disk/oN/src/` |
| Per-account site files | `/data/disk/oN/static/files` (storage-aware: mirrored onto the target's `/mnt` mount, or de-referenced to root if it has none) |
| Per-account drush aliases | `/data/disk/oN/.drush/` (site aliases only) |
| Per-account nginx vhosts | `/data/disk/oN/config/server_master/nginx/vhost.d/` |
| Per-account SSL/LE | `/data/disk/oN/config/ssl.d/`, `config/server_master/ssl.d/`, `tools/le` |
| FTP account SSH keys | `/home/oN.ftp/.ssh` |
| Sub-account registry + backups/undo | `/data/disk/oN/clients/`, `backups/`, `undo/` (`clients/` drives sub-user creation on the target; `backups/` is required by `renameaegirhost`'s Ægir-root validation and is space-gated like the Solr trees) |
| Client toolchains | `/opt/user/gems/oN.ftp`, `/opt/user/npm/oN.ftp` |
| Shell credentials | `<oN>.ftp` shadow hash + `log/pass.txt` as a pair, the sub-account password store `/home/oN.ftp/users/`, and each sub-user's hash and `.ssh` |
| Per-account config | `/root/.<oN>.octopus.cnf` (portable values merged into the target's copy), `static/control/{fpm,cli,multi-fpm}.info` and `log/{fpm,cli,email,option,cores,subscr}.txt` (forced, no `-u`) |
| Suspension flag | `/data/conf/suspended/<oN>.pid` (mirrored, presence and absence) |
| Out-of-root symlink content | Every synced tree is swept for symlinks whose target lives **outside** the synced trees (typically a secondary `/mnt` volume — per-account backup stores under `/data/disk/arch/sql` are the canonical case). Their content **materialises** on the target as real dirs/files: mirrored onto the target's own single mount when it has one and the store lands under `/data/disk`, de-referenced to a real dir/file on the target root otherwise. Space-gated per store/batch like everything else |

MySQL data is **not** rsynced — replication keeps it current continuously.

### Deletions: what a sync removes on the target, and what it never does

Source-side deletions **propagate on the data trees** during `sync` (manual
and automated alike): `distro/`, `src/`, `static/files`, `arch`, `backups/`,
`undo/`, the client toolchains, the Solr data trees and the shared
`/data/all`, `/data/disk/all`, `/data/disk/legacy` and `/var/www/static`
trees. Without this a standing mirror grows without bound, and it grows
*nightly*: the per-account SQL dump stores under `arch`, each account's
`backups/` and the Solr index segments all rotate on the active every night,
and a mirror can never reclaim any of it on its own — `owl.sh` exits on the
standby marker, so the box's whole nightly cleanup is parked while it is a
mirror.

Three things are deliberately **not** pruned:

- **Control, credential and target-role legs stay additive** — `log/`,
  `.drush/`, `config/`, the sub-account password store and the PHP pin
  witnesses under `static/control`. They carry target-owned state or are
  force-copied, and deleting there would fight the target's own install.
- **The cutover legs stay additive**, plan and live alike. That is the one
  window where the target is about to become production and a wrong deletion
  is unrecoverable; a promoted box resumes its own `owl.sh` cleanup within
  the night and reclaims normally.
- **Files excluded from a leg are never deletion candidates** (`--delete-excluded`
  is never passed), so `proxied.pid`, `migproxy.cnf`, `pass.txt` and the
  target's immutable `php.ini` are safe by construction.

The guards on every pruning leg, none of them optional:

| Guard | What it prevents |
|---|---|
| `--delete-after` | Nothing is removed until the transfer succeeded, so a failed leg cannot leave the target both pruned and un-copied |
| `--max-delete` (`_XMASS_MAX_DELETE`, default 5000) | rsync **refuses** (exit 25) rather than carry out a mass deletion — the catastrophe guard: "wiped the mirror" becomes "a loud pass failure a human reads" |
| Never with `--ignore-errors` | That flag means *delete even though the source had read errors*, which is exactly what must not happen; a leg either prunes or keeps the historical tolerance, never both |
| Empty-source refusal | An unmounted secondary volume reads as an **empty directory**; a `--delete` against it would erase the mirror's only copy of every client file. An empty source is never a licence to delete — the leg logs it and stays additive |

A tripped delete guard is a refusal to read, not an error to retry: nothing
beyond the limit was deleted. Confirm the source really lost that many files
— an unmounted volume and a genuine mass deletion look identical from the
sending side — and only then re-run once with `_XMASS_MAX_DELETE` raised.
Expect it to trip on the **first** pruning pass against a mirror that has
been accreting for months; that is the guard doing its job.

A mirror-side *rewrite* of a file that still exists on the source is still
never undone — `-u` keeps the newer copy, and only the accretion of files the
source no longer has is what deletion addresses.

Optional per-account config directories (`pre.d`, `post.d`, `subdir.d`,
`platform.d`, `config/ssl.d`, `config/server_master/ssl.d`, `tools/le`) are
skipped with a logged "nothing to send" when absent rather than failing the
run — a genuine transfer failure on a directory that IS present still aborts
before anything destructive.

Three deliberate exclusions from the `log/` sync: `proxied.pid` and
`migproxy.cnf` are target-role state that must never be overwritten from the
source (they would disable LE renewal on the target and clobber its policy
record on the documented `reset-phase syncing` recovery path), and `pass.txt`
rides the credential carry instead so it can never advertise a password the
target's `/etc/shadow` does not hold. `log/domain.txt` is synced with `-u` on
purpose: the target's own FQDN stamp is what `renameaegirhost` wants.

### Out-of-root symlinks — what materialises and what stays a link

rsync carries symlinks **as links**, so a link whose target lives outside the
synced trees would arrive dangling and its content would never travel. Every
`sync`/`cutover` pass therefore sweeps each synced tree first and classifies
every symlink:

- **Stays a link, never dereferenced**: links into the normal BOA fabric —
  platform links into `/data/all`, `.drush` links, links to BOA-installed
  toolchains (any standard FHS prefix that exists on every BOA box) — and
  relative links resolving inside the tree being copied.
- **Materialises**: links whose first hop *and* final target live outside
  those prefixes and exist (the secondary-mount class). Dir links transfer
  one store each; file links ride one batched, space-gated `rsync
  --copy-links` per tree. Nested links inside a materialised tree are handled
  the same way, a few levels deep.
- **Reported, never a DENY by itself**: dangling links (a cluster under one
  `/mnt` prefix usually means the volume is not mounted — the report says so;
  the target's last materialised copy is left in place), link chains that
  escape and re-enter the synced trees, links that resolve out-of-root only
  via an intermediate link, links under an account subtree that its own
  delta leg re-sends each sync, and links whose name cannot be shell-quoted
  safely.

`pre-mig` (on the source) and `init` print the full link map with sizes and an
aggregate space probe **before anything moves**; the binding per-store gates
run inside the sync legs themselves. `verify` sweeps the target (including its
mount) for dangling links afterwards.

### Why the PHP pins and the account cnf need forcing

Both are the same defect class. A `-u` (skip-newer) sync silently loses to the
target's fresh install, which wrote its own defaults minutes earlier. For the
PHP pins that means every migrated site quietly serving on the target's
install-time PHP instead of the version it was pinned to.

The direction of authority matters here: BOA derives
`/root/.<oN>.octopus.cnf` **from** `static/control/fpm.info` and `cli.info`
(in `_satellite_cnf`, and again in `manage_ltd_users.sh` every few minutes) —
never the reverse. So the `.info` files are what actually make a pin stick,
and they are force-copied without `-u`; the cnf merge carries the values only
it owns (FPM tuning knobs, `_CLIENT_*` plan identity, ghost-cleanup flags,
`_RESERVED_RAM`). The merge is per key, so the target's host-specific lines
(`_MY_OWNIP`, `_LOCAL_NETWORK_IP`, `_THIS_DB_HOST`/`_PORT`, `_DOMAIN`) are
never touched — BOA re-derives those correctly for the new box.

The per-site rows of `multi-fpm.info` key on the site URI, so a rename that
changes a site's URI also re-keys those pins — `renameaegirhost` carries them
through its hostname pass. Left stale, a host-derived site's pin goes inert
(no FPM include is emitted) and the site silently serves on the account's
default PHP version.

Run `xmass sync` immediately after `init` for the first full pass (which may
take several hours for large accounts), then periodically as the cutover date
approaches to reduce the amount of data left to transfer at cutover time.

### Automated file sync for a standing mirror (`xmass autosync`)

A standing HA mirror is a migration deliberately parked at `phase=syncing`:
its database is continuously current through replication, but the file legs
above only run when someone runs them. `xmass autosync` closes that gap — it
arms a cadence that repeats the exact `sync --live` leg set unattended, so
the mirror's files stay minutes behind its database instead of days. It is
one-way and driven from the **active** side only, by design: nothing moves a
mirror out of sync except the active server. No daemon and no inotify
machinery is involved — the driver is the standard per-minute monitor fan-out
(`monitor/check/autosync.sh` via `minute.sh`), and each pass is the same
idempotent delta rsync you would have run by hand.

```sh
xmass autosync target-ip              # arm, default cadence (every 15 min)
xmass autosync target-ip --every=30   # arm with a custom cadence (5–1440 min)
xmass autosync --status               # marker, cadence, last completed pass
xmass autosync --off                  # disarm (cutover disarms by itself)
```

**Arming requires, and refuses without:** the `syncing` phase; a target that
matches the replication target in the state file; at least one **completed
operator-driven `sync --live`** for this migration; and a target that holds
`/root/.standby.cnf` right now (probed, failing closed on transport errors).
The completed-live-sync requirement is not ceremony: the automated pass runs
without the DRY/`--live` token, and what makes that sound is that you have
read the DRY plan and the eligible/**skipped-account list** at least once.
An account added later that is missing on the target fails the pass loudly
(the same target-readiness gates run in die mode every pass) — run
`xmass prep-target` for it, exactly as before a manual sync.

**Every pass, before any bytes move,** the run re-verifies the whole state
and prefers doing nothing over doing the wrong thing:

- *Defers silently* (normal ticks, retried at the next cadence): another
  xmass verb holds the single-flight lock — an operator's own `sync`, a
  `cutover`, or a previous automated pass still transferring, so passes can
  never overlap and never fight the migration tooling; a live
  `barracuda`/`octopus` run (process-anchored evidence, so a stale pid file
  can never park the cadence forever); the in-flight init window signals;
  phases `init`, `cutover` and `rename-failed`.
- *Stands down loudly* (non-zero, mailed through the standard
  `_INCIDENT_REPORT` throttle): the target **no longer holds its standby
  marker** — the mirror was promoted or retired, and a sync now could write
  into a live box; the marker names a different target than the state file;
  no completed live sync is recorded for the pair (a same-target re-init
  resets that record on purpose — the cadence stays armed but stands down
  until you run one manual DRY + `--live` for the rebuilt pair, then it
  resumes by itself); three consecutive transport failures to the mirror
  (fail-closed — a dead mirror link must not age the files silently); any
  real transfer or gate failure inside the legs. One more difference from a
  manual pass: an unattended pass **never re-places a store** — a store that
  stops fitting at its established placement (target mount or root) is a
  loud DENY, never the silent mirror-to-root fallback an operator pass may
  choose. And the fit gates credit the bytes already sitting at the
  destination, so a mirror whose storage is sized to the data does not
  false-refuse every delta pass after the first full copy.

The target's standby marker is verified at pass start **and re-proved at
every leg boundary** (before the shared, Solr and each account leg), so a
promotion mid-pass stops the pass at the next boundary rather than after
hours; the residual exposure is one in-flight transfer leg. Unlike a manual
`sync --live`, an automated pass **never restores a missing standby marker
on the target**: automation verifies the mirror's role, it never (re)creates
it. The marker's absence is the promotion signal, and a blind restore from a
surviving active would re-hold a freshly promoted production box within a
minute.

Silent deferral can never become silent death: the driver alarms — one daily
latched warning plus one mail — whenever no pass has **completed** for six
cadences, whatever the reason (a phase wedged by an aborted cutover, a stuck
lock, a hand-edit). If the alarm fires, read the defer/refusal reasons in
the pass log.

**The cadence you arm is a ceiling on frequency, not a promise.** A pass
walks the estate's metadata several times over — rsync's own file list, the
space gates, the symlink sweep — so on a large estate it can take longer
than the interval. Passes never overlap (the lock defers a late tick), but
without a second bound the pair would then run *back to back forever*,
walking continuously with no operator-visible sign of it. So the driver
enforces a **duty cycle**: a pass may occupy at most one part in
`_XMASS_AUTOSYNC_DUTY + 1` of wall clock (default 3, i.e. at most a
quarter), which means the box rests at least three times the last measured
pass duration before starting the next one. The armed cadence still wins
whenever it is the longer of the two — the guard only ever slows a pair
down.

`xmass autosync --status` prints the effective interval alongside the armed
one, and arming warns when the cadence you asked for is less than twice the
last measured pass, so the two never silently disagree. The staleness alarm
measures against the *effective* window, not the armed cadence — a pair the
guard has correctly slowed down is not stale.

The cadence default is 15 minutes with a floor of 5. The floor exists
because below it the rsync tree walk never rests on a large estate; the duty
cycle is what actually protects a box whose passes are long.

Two costs are also skipped on automated passes specifically, because on a
large estate they are the dominant ones and neither can change what the pass
does: the per-account symlink sweep no longer descends the subtrees whose
own delta legs already re-send their links (a link found there is
report-only, and the exclude list it would build is consumed before the
sweep runs), and the exact "newest index write" date in the Solr
classification — report prose that no verdict reads — is bucketed from
measurements already taken rather than recomputed with a full walk of every
core's index tree. Manual passes keep both in full, because an operator is
reading that output. Each pass appends its full output (including
the eligible/skipped list) to `/var/log/boa/xmass.autosync.log` (size-bounded),
records the last successful pass in `/var/log/boa/xmass.autosync.status`
(also shown by `xmass status`), runs under `ionice`/`nice` so the local tree
walk stays polite on a serving box, and is killed at a hard ceiling
(`_XMASS_AUTOSYNC_TIMEOUT`, default 21600 s) if a transfer hangs — safe,
because the legs are idempotent and the next tick resumes the delta.

The marker `/root/.xmass.autosync.cnf` is the single switch. It is cleared
automatically whenever the migration phase reaches `complete` (a finished
cutover, `reset-phase complete`); a fresh `init` to a **different** target
removes a stale marker (a same-target re-init is the mirror-repair path and
keeps the cadence armed — standing down until the first manual live sync,
as above). A leftover marker on a box that is itself a standby or a
finalized proxy is never acted on — one daily latched warning plus one
daily mail, no sync. `_USE_XMASS_AUTOSYNC=NO` in `/root/.barracuda.cnf`
parks the driver box-wide without touching the marker.

For a **planned** cutover there is nothing to pre-arrange: a cadence tick
that meets the running cutover defers on the verb lock, and completion
clears the marker. If a tick's pass is already *transferring* when you want
to start, the cutover is refused by the same lock — either wait it out (a
delta pass is short) or `xmass autosync --off` first and re-run.

### Phase 3 — Monitor (`xmass status`)

```sh
xmass status target-ip
```

Displays current phase, last sync timestamp, and live replication lag in
seconds. Aim for lag < 60 s before scheduling cutover.

### Phase 4 — Cutover (`xmass cutover`)

Run on the **source**. This is the only step with user-visible downtime.

```sh
xmass cutover target-ip [--proxy-mode=...] [--proxy-deadline=...]          # DRY: plan only
xmass cutover target-ip --live [--proxy-mode=...] [--proxy-deadline=...]   # perform the cutover
```

Without `--live`, `cutover` does a plan-only pass over every account's files store and
stops **before** any destructive step (no MySQL read-lock, no downtime). Run it once to
confirm `CLEAN`, then re-run with `--live` to perform the real cutover.
`--proxy-mode`/`--proxy-deadline` on cutover override whatever was set at `init`
(box default only — per-account pins always win). The DRY pass prints each
account's resolved mode; `--live` **refuses** to proceed while any account
would fall back to the built-in default, because a mass cutover mails every
customer on the box and a wrong story cannot be unsent. A mode pin never
affects migration eligibility — it only pins what that customer is told.

**Pre-flight** (automatic, in this order — every refusal happens before the
first change to the source):

- Confirms phase is `syncing`.
- Refuses to run outside `screen`/`tmux`: a dropped session mid-cutover strands
  the source on 503. Override with `_XMASS_NO_SCREEN=YES`.
- Re-gates the same-release stamp, account existence, PHP coverage and Solr coverage on the target.
  The release can have drifted since `init`, and a target missing a
  central-map nginx variable takes down every migrated site at once.
- Refuses while any account's proxy mode is undeclared, then consumes the
  clean-dry token.
- Reports, per account, the tasks still queued or interrupted in its panel
  queue, by type — they travel with the replicated database and execute on the
  TARGET when cutover starts its queue, so cancel anything you do not want
  carried across before proceeding.
- **Then** stops cron and parks the five BOA runners itself. The box's own cron
  restores a park done at `pre-mig` time within minutes, so parking here — not
  refusing and asking the operator to re-park — is what makes the window
  reliable. If the cutover aborts after this point, the printed restore recipe
  covers it.

**Cutover sequence:**

| Step | What happens |
|---|---|
| Step 0 | Re-hold Solr on target (in case it was manually started since init) |
| Step 1 | Write `http-off.pid` for all accounts → nginx serves 503 on source; purge speed cache |
| Step 2 | Stop all Solr instances on source; touch `/root/.deny.java.cnf` AND set `_DENY_JAVA=YES` in `/root/.barracuda.cnf` (permanent deny; to reverse on a rolled-back source run `xmass restore-solr` -- clearing the deny by hand is **not** enough, see below) |
| Step 3 | Final rsync: shared data, Solr (now clean — source stopped), all account data |
| Step 3.5 | **Gate:** abort if any store could not be placed or any transfer failed — before anything destructive |
| Step 4 | Wait for replica lag = 0 (polls every 15 s; ceiling `_XMASS_SYNC_MAX_WAIT`, default 7200 s; on timeout reports whether the lag is closing or growing) |
| Step 5 | Final rsync pass of `static/files` only, **before** the lock (the web block already stopped file writes) |
| Step 5.5 | **Gate:** re-check both of the above, then persist `phase=cutover` |
| Step 6 | Append the **advisory** read-only flag to `/data/conf/global/global-extra.inc` (previous file kept as `.bak`), then `FLUSH TABLES` to push buffers. The flag is belt-and-braces only (box-wide, ignored by most site shapes, dropped by the next BOA system pass) and the cutover **continues with a warning if it cannot be written**: the write barrier is the step-1 503 gate plus the parked cron and runners. A session read lock is not relied on — it cannot survive a disconnect |
| Step 7 | Triple-check lag = 0 at 10 s intervals. On any failed check: unlock source MySQL, **thaw the write freeze**, and abort — the target is not promoted at this point, so the source is handed back writable |
| Step 8 | `STOP SLAVE; RESET SLAVE ALL` on target → target MySQL is now standalone. On failure the exit code alone cannot say whether the promotion committed (transport can fail after mysql ran), so the tool **reads the target's replica state back** and picks one of three exits: still a replica → unlock, **thaw**, abort (the source is the only production box); replica config gone → the promotion committed → **park resumably** at `phase=rename-failed`; state unreadable → the source stays 503-gated with the flag in place (lifting either could silently lose writes) and the message spells out how to determine the state and which recovery to run |
| Step 9 | Belt-and-braces `UNLOCK TABLES` on source (no lock is normally held); the write freeze stays — the source serves through the proxy from here |
| Step 10 | Re-transfer `/root/.my.pass.txt` and `/root/.my.cnf` to target (belt-and-braces) |
| Step 11 | Drop replication user `xmass_repl` from source. Runs at the head of the cutover tail (idempotent), so a park upstream of it — the step-8 committed-promotion park — still gets the grant dropped when the resumed run completes |
| Step 11.5 | Unlock the promoted target's database — on EVERY entry into the cutover tail, resumes included, since every step after it writes the target DB. `SET GLOBAL super_read_only=OFF` plus `read_only=OFF`, with the runtime readback verified (both variables) BEFORE the `xmass-standby-hold` block is stripped from `xmass_gtid.cnf`; a failed unlock **parks resumably at `phase=rename-failed`** rather than marching the renames into a read-only DB, and with mysql unreachable the cnf block deliberately survives as the watchdog's retry key |
| Step 12 | Prove the target's web layer, then start nginx there: the `BOA_STANDBY_WEB` firewall hold is removed first (both address families), then `nginx -t` on the target (an invalid config **refuses the conversion**, printing the tail of the test output), then require a real HTTP answer on the target's port 80 — on loopback AND externally from the source (the path client traffic takes after the DNS flip; a browser UA, because curl's default lands in BOA's own crawler map, and HTTPS too when the target has a public 443 listener), since the loopback curl cannot see an INPUT-chain firewall drop. This proof runs at the **head of the cutover tail**, so every entry re-runs it — the normal flow and each resume of a parked cutover (nothing later in the tail gates on the web layer: the step-13 serve-wait measures and reports, and nothing else can *start* a stopped nginx). Either refusal **parks resumably at `phase=rename-failed`** and prints the full source-restore recipe (write-freeze guidance included): the target stays promoted, the source stays 503-gated and frozen, and the SQL watchdogs stay paused. Fix nginx on the target, then re-run `xmass cutover target-ip --live` — the resume re-runs this proof and starts nginx itself |
| Step 12.5 | Rewire panel DB access on target per Ægir root (rediscover live hostmaster DB, reset its user's password, rewrite the panel dir's credentials — the datadir swap killed the fresh-install panel DBs). When the source's panel platform number diverges from the target's (an aged source vs a fresh target — the normal production shape), the step adopts the target's code-bearing panel platform and repoints the hostmaster platform row in the live DB; the DB persist is load-bearing because the rename queue's hostmaster verify regenerates the alias FROM the DB, so an alias-only correction is undone and the panel 404s from a hollow platform path |
| Step 13 | `renameaegirhost --aegir-root /var/aegir --force-old source-fqdn` on target (Ægir master) |
| Step 13 | `renameaegirhost --aegir-root /data/disk/oN --force-old source-fqdn` on target (each Octopus account). The rename moves host-derived tenant site directories onto the new hostname together with every URI-keyed surface (per-site Drush alias file, static files store, per-site PHP pins), and **aborts before the Ægir task queue** if any site dir still carries the old hostname — the queue would import those as brand-new sites with duplicate panel nodes. Inside a cutover that refusal parks at `phase=rename-failed`. After the renames it waits for each renamed site to actually serve (up to 180 s per site, `_RENAME_SERVE_WAIT`; the box's catch-all page is discriminated so an unknown-host 200 never passes) — minutes per site here are the wait, not a hang; a site named as never serving with a 400 usually means its trusted-host settings |
| Step 14 | Clear Solr transaction logs on target; start Solr; HTTP health check |
| Step 14.5 | Compare the source's Solr core set against what the target actually registered, and name every core present as data but unregistered (registration is core-shape-specific and stays manual). Scoped to the real, dotted cores of the versions expected to **serve** on the target (used + ambiguous): a version this run deliberately denied has no service there by design, and its data trees travel with the sync regardless, so its cores are not reported |
| Step 15 | Start cron on target; restore BOA runner scripts on target |
| Step 16 | `xoct proxy oN target-ip` for each account on source (records + trust + vhost conversion + mode-selected notification); failures collect per account. First checks that `migration_proxy_certs.sh` exists **and is scheduled** here — from this point the source serves the proxied sites' TLS and only the daily mirror keeps it fresh |
| Step 17 | Remove `http-off.pid` from source accounts — a failed conversion keeps its 503 gate (its vhosts would otherwise serve the old local copy against a database that now lives on the target) |
| Step 18 | Write `proxied.pid` for successfully converted accounts only |
| Step 18.5 | Start cron and un-park the five runners **on the source**. Without this the source proxy runs nothing again — including its own certificate mirror, which is what keeps a long-lived proxy from serving expired certificates ~90 days later |
| Step 19 | Mark state `complete` |

If any step between 4 and 8 fails the tool aborts; no session lock is held any
more, so there is nothing to unlock (the belt-and-braces `UNLOCK TABLES` runs
regardless). An abort at step 7 also **thaws the write freeze by itself** — the
target is not promoted at that point, so the source is handed back writable. A
step-8 failure first reads the target's replica state back and thaws only when
the target is provably still a replica; a committed promotion parks resumably,
and an unreadable target keeps the freeze with explicit instructions (see the
step table above).

Source sites remain on 503 (`http-off.pid` in place). Every abort that happens
after the web block prints the exact commands to restore service on the source,
so follow the printed recipe rather than reconstructing it: clear the
`http-off.pid` files, purge the nginx speed cache, reload nginx, remove the Solr
deny file if Solr served from here, start cron, and un-park the five runners.
When the write freeze is still in place as the recipe prints (a post-promotion
park), the recipe includes the thaw line and says when it is safe to use it:
thaw only to abandon the cutover and keep the source as production — after the
promotion, writes accepted on the source can never reach the target.

#### Replica parallel apply (Percona 5.7)

Percona 5.7 applies the relay log single-threaded unless told otherwise, which
on a write-heavy source lets the replica drift and blows the cutover's lag
wait. `xmass init` now sets `slave_parallel_type=LOGICAL_CLOCK` and
`slave_parallel_workers` (default 4, `_XMASS_PARALLEL_WORKERS` to change it)
both persistently in `xmass_gtid.cnf` and at runtime before the replica
threads start. 8.0+ already defaults to parallel apply, so nothing is written
there.

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

### Phase 4.5 — Verify (`xmass verify`)

Run on the **source** after the cutover. Read-only; changes nothing on either
host:

```sh
xmass verify [target-ip]        # target-ip defaults to the one in the state file
```

Per account it takes one real site vhost and fetches it twice, **at least 5 s
apart**, directly against the target, plus one request relayed through this
source's proxy and (where the site has certificates) one HTTPS probe. The
spacing is not cosmetic: BOA answers fetch bursts with transient 200
"Page not found" bodies, so a single fast fetch proves nothing — re-run
`verify` before recording any site as broken. It also reports leftover
`http-off.pid` files, and whether cron and the certificate mirror are alive on
this box.

### Phase 5 — Post-migration (`xmass post-mig`)

Run on the **target** after DNS has been updated and traffic flows directly.

```sh
xmass post-mig
```

Ensures Solr services are running cleanly, reloads nginx, restores any
remaining BOA runner scripts, and **reconciles** the migration-proxy trust
from the per-account policy records: peers whose accounts resolved
`temporary` are dropped, `permanent`/`ha-switch` peers stay trusted
(restricted to the live peer set), undeclared accounts leave everything as
found and are reported. With no records at all it behaves exactly as the old
unconditional teardown (the permanent marker is honoured).

It also **rebuilds the pinned PHP pools**, which is not cosmetic. A
migrated account arrives carrying the source's per-release FPM markers
(`static/control/.multi-fpm.<tree>.<xSrl>.pid` and
`.multi-nginx-fpm.pid`). Both boxes run the same release, so without this
step the target reads them as "pool set already built", never creates
pools for versions that exist only here — exactly the interpreters
`prep-target --fix-php` built for the carried pins — and never regenerates
the per-site socket includes. The pins survive intact and stay INERT:
every pinned site is served by the account's DEFAULT pool, indefinitely,
because nothing re-triggers until the release serial moves or the pin file
changes. `post-mig` clears the markers, lets the normal sweep rebuild in
the two passes it needs (the include generator will not emit a site
include before that pool's socket exists), then prints per account either

```
INFO:   o1: every pinned PHP pool is live
```

or an `ALRT` naming each pin that is still missing. **Treat any such ALRT
as a stop**: those sites are running on the wrong interpreter right now.
Spot-check independently with `/run/<oN>.<NN>.fpm.socket` and the site's
`post.d/fpm_include_site_<domain>.inc`. Note that a site answering HTTP
200 with correct content proves nothing here — a Drupal 7 core tolerant of
PHP 8.4 looks perfectly healthy while mis-pinned, whereas a 5.6 or 7.x
site fatals.

> **Do not skip `post-mig`.** It re-arms and restarts Solr, clears any
> leftover hold or standby marker, restores the five runners, and
> reconciles the migration-proxy trust. Cron runs on the target for the
> whole window by design — the per-job standby gates carry the passivity —
> so a quiet box is NOT the expected state at any point. Every hold
> releases with the marker: the cutover itself unlocks the DB (step 11.5)
> and opens the firewall (step 12); the watchdog layers release the rest
> within about a minute — nginx healed up, FTPS resurrected, backups
> resumed, tenant logins restored (verified per user, at the
> manage_ltd cadence). After `post-mig`,
> verify the marker is gone (`test -e /root/.standby.cnf` must fail) and
> the task queue drains. A target quiesced by pre-gate BOA bytes may still
> have cron stopped; cutover step 15 starts it as vintage tolerance —
> verify with `pgrep -x cron`.

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

Either way the snapshot bounds its backup-lock wait to 15 minutes and kills
a query that blocks it after 60 s, so an `init` cannot sit forever behind
one long report.

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
| Before `init` (`prep-target`) | Classified per version as used / unused / ambiguous from measured state; the verdict is recorded in `/data/conf/xmass_solr_used.cnf` | Deny set mirrored to the source's **used** set: per-version denies for unused versions, the blanket java pair when the source uses none, used versions unparked and installed. Gated at `prep-target` and fatal there without `--fix-solr` |
| After `init` | Running normally | Stopped and DISARMED (exec bit + rc links dropped; `/var/log/boa/.xmass_solr_hold.pid` records the hold, java.sh re-asserts it every minute — surviving reboots and barracuda passes) |
| During `sync` | Running normally | Still held (best-effort Solr rsync only) |
| Cutover step 0 | Running | Re-held and stopped (safety) |
| Cutover step 2 | Stopped; `/root/.deny.java.cnf` created + `_DENY_JAVA=YES` set | Held |
| Cutover step 3 | Stopped (clean index state) | Held (final Solr rsync with clean source) |
| Cutover step 14 | — | Re-armed (exec bits + rc links restored); tlogs cleared; Solr started; HTTP health check |
| `post-mig` | — | Hold cleared + re-armed if leftover; Solr restarted cleanly |

Clearing transaction logs (`tlog/` directories) before starting Solr on the
target prevents double-indexing of any writes that were buffered at the moment
the source Solr was stopped.

### Restoring Solr on a rolled-back source

Cutover step 2 disables Solr on the source **permanently and in two forms**.
That is correct for a real migration, where the source is being retired, but a
cutover that gets rolled back with the source kept in service leaves the deny
armed. Use:

```
xmass restore-solr
```

Run it on the source. It clears `/root/.deny.java.cnf` and sets
`_DENY_JAVA=NO`, then re-arms and starts each Solr service whose **own** deny
(`_DENY_SOLR9`, `_DENY_SOLR7`, `_DENY_JETTY9` and their `/etc/boa/.deny.*.cnf`
markers) is not set. It refuses on a finalized PX0 proxy (`/root/.proxy.cnf`),
where Solr is down by design after `xtrim finalize`. It is idempotent.

**Why clearing the deny by hand is not enough.** `autoupboa`, called from
`/var/xdrago/clear.sh` every 5 minutes, honours either deny form by running
`update-rc.d -f solr9 remove`, moving `/etc/init.d/solr9` to
`/var/backups/solr9.initd`, and `pkill -9 -f java`. So the missing init script
is a *symptom*: putting it back while a deny is still armed is undone within
five minutes. The order matters -- deny first, service second.

**BOA does not self-heal this.** `_if_solr_nine` re-runs Solr's
`install_solr_service.sh` only when `/var/solr9/data` or the version stamp
`/var/solr9/solr-<version>-version.txt` is missing. A rolled-back source still
has both, so no `barracuda up-*` pass ever recreates the init script. Where no
parked copy survives in `/var/backups`, `restore-solr` regenerates it from
`/opt/solr9/bin/init.d/solr` using the same four substitutions
`install_solr_service.sh` applies.

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

**If `cutover` aborts:** the tool prints the full restore recipe for the
source; follow it rather than doing it from memory. An abort before the write
freeze leaves the phase at `syncing`, so retrying is a fresh DRY plus `--live`
with nothing else to undo. An abort at step 7 — and a step-8 failure whose
read-back proves the target is still a replica — unlocks source MySQL **and
thaws the write freeze itself**; the phase is `cutover`, so retrying is
`xmass reset-phase syncing`, a fresh DRY, then `--live`. A refusal at step 12
or later (and a step-8 failure whose promotion actually committed) parks
resumably at `phase=rename-failed` with the target promoted: the source stays
503-gated, with the advisory flag deliberately left in place, and the printed
recipe **leads with the resume instruction** — the restore lines below it,
including the thaw, are only for abandoning the cutover and keeping the source
as production. A
step-8 failure whose target cannot be read back at all keeps the freeze and
prints how to determine the promotion state and which recovery to run.

**If the step-12 web-layer proof, the panel rewire, or renameaegirhost
fails** — or a step-8 promotion turns out to have **committed** despite a
reported failure — `cutover` parks resumably at `phase=rename-failed` instead
of completing; the failure report names the cause (for a failed rename, the
affected roots). Fix the cause, then re-run
`xmass cutover target-ip --live` — the resume re-enters the cutover tail at
its head (re-asserting the source's 503 gate and write freeze, dropping the
replication user, re-running the web-layer proof — which starts the target's
nginx itself) and every step in it converges: already-rewired panels and
already-renamed roots no-op. To iterate on a single root first, run
`renameaegirhost --aegir-root /data/disk/oN --force-old source-fqdn` manually
on the target — it is convergent and safe to re-run — then resume the cutover
so the remaining cutover steps complete.

---

## Notes

- `xmass sync` is idempotent — run it as often as you like. Each run is a
  delta rsync; subsequent runs after the first are fast. For a standing
  mirror, `xmass autosync` runs exactly these passes on a fixed cadence so
  nobody has to remember to (see the sync phase above).
- The replication user `xmass_repl` is created only on the source and is
  dropped automatically at cutover. It is never present in normal BOA
  configuration.
- `xmass` enumerates Octopus accounts dynamically from `/data/disk/` — no
  manual account list is needed.
- After cutover the source server functions as an nginx HTTP/HTTPS proxy for
  all migrated sites. It is independent of the target and can be
  decommissioned as soon as DNS has propagated and you are satisfied with the
  target.
- Proxy longevity is per account, driven by each account's policy record
  (`/data/disk/oN/log/migproxy.cnf`, see `xoct proxy-mode --all` for the
  table). At `post-mig` the target reconciles rather than tears down: accounts
  resolved `permanent` or `ha-switch` keep the source trusted (nginx realip +
  CSF whitelist, restricted to the live peer set); `temporary` accounts drop
  it once traffic flows directly. A later mode change on the source
  (`xoct proxy-mode oN <mode>`) pushes the updated record to the target and
  re-reconciles there, so the teardown decision never goes stale.
  `--permanent-proxy` is a deprecated alias for `--proxy-mode=permanent`.
