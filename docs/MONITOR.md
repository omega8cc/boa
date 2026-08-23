# BOA monitor stack (sysadmin)

BOA has no external monitoring agent and no resident daemon. Every box watches and repairs **itself** from a single root crontab that fires a handful of short-lived bash scripts every minute. Those scripts sample load, restart dead services, kill runaway processes, scan auth logs for abuse, and drain the Ægir task queue — then exit. There is nothing long-running to crash; the watchdog *is* the cron tick. Think of it as the octopus feeling each of its own arms every few seconds and pulling back anything that has gone limp.

This document covers the **service / load / process** side of that machinery: what cron launches, the self-looping fan-out that gives it sub-minute reaction time, the per-service watchdogs, the load auto-pause ladder, the process guards and auth scanners, the box-class throttle that keeps the fan-out from pinning idle load on small hosts, and the `loadreport` profiler used to measure it.

The **security-facing** members of the same `/var/xdrago/monitor/` family — the nginx log scorer `scan_nginx.sh` (with the distributed-i18n-flood detector and the FPM-saturation trigger) and the csf ban pipeline — are documented in [ABUSE-GUARD.md](ABUSE-GUARD.md), and the AI-crawler and ban-mirror generators in [AI-POLICY.md](AI-POLICY.md) and [IP-ACCESS.md](IP-ACCESS.md). The self-update half (how the monitor scripts themselves get refreshed on every box) is [SKYNET.md](SKYNET.md). This document points at those rather than repeating them.

## The root crontab

The installed root crontab lives at `/var/spool/cron/crontabs/root`. Its master copy is `aegir/tools/system/cron/crontabs/root`, copied into place on every install/upgrade. Do not hand-edit the installed file — its own header says so, and the next upgrade overwrites it. Per-box additions go in `/var/xdrago/cron/custom.txt`, which BOA appends after the copy.

| Cmd | Cadence | Role |
|---|---|---|
| `second.sh` | every minute (self-loops ×10) | Load sampling + auto-pause + heavy watchdog/scanner fan-out |
| `minute.sh` | every minute (self-loops) | Service auto-healing watchdog fan-out (nginx, php, mysql, …) |
| `guest-fire.sh` | every minute | Apply temporary csf web bans (see [SECURITY.md](SECURITY.md)) |
| `runner.sh` | every minute (`nice -n5 ionice -c2 -n7`) | Drain the Ægir hosting task queue (`/var/xdrago/run-*`) |
| `ip_access.sh` | every 2 min | Maintain per-site IP access rules, IPv4/IPv6/CIDR (see [IP-ACCESS.md](IP-ACCESS.md)) |
| `user_admin_access.sh` | every 2 min | Maintain per-site `/user`+`/admin` IP access rules, IPv4/IPv6/CIDR (see [USER-ADMIN-ACCESS.md](USER-ADMIN-ACCESS.md)) |
| `ai_policy.sh` | every 2 min | Apply the AI-crawler policy (see [AI-POLICY.md](AI-POLICY.md)) |
| `nginx_deny.sh` | every 2 min | Regenerate the nginx IPv4 ban geo from csf state (see [SECURITY.md](SECURITY.md)) |
| `nginx_deny6.sh` | every 2 min | Regenerate the nginx-native IPv6 ban geo (csf is IPv4-only; see [ABUSE-GUARD.md](ABUSE-GUARD.md)) |
| `migration_proxy_realip.sh` | every 5 min | Refresh migration-proxy realip ranges |
| `clear.sh` | every 5 min | Periodic cleanup |
| `loadreport --log` | every 30 min (`nice -n10 ionice -c3`) | Profile which monitor scripts cost CPU/RSS (read-only) |
| `manage_ltd_users.sh` | every 3 min (`nice -n5 ionice -c2 -n7`) | Maintain limited shell users |
| `manage_solr_config.sh` | every 4 min (`nice -n5 ionice -c2 -n7`) | Maintain per-site Solr config |
| `guest-water.sh` | 05:01 daily | Escalate repeat offenders to persistent `csf.deny` (see [SECURITY.md](SECURITY.md)) |
| `cloudflare_realip.sh` | 04:45 daily | Refresh Cloudflare realip ranges |
| `purge_binlogs.sh` | hourly (`:01`) | Purge MySQL binary logs |
| `mysql_cleanup.sh` | hourly (`:30`) | MySQL housekeeping |
| `mysql_backup.sh` / `mysql_cluster_backup.sh` | 01:15 / 02:15 daily | SQL dumps |
| `graceful.sh` | 03:01 daily | Graceful service cycle |
| `backboa backup` / `duobackboa backup` | 03:15 / 05:15 daily | Off-site backups |
| `owl.sh` | 04:15 daily | Daily maintenance (control-file migration, cleanup, version bumps) |

The per-minute monitors (`second.sh`, `minute.sh`, `guest-fire.sh`, `runner.sh`) are the live self-healing core. The 2-minute and longer jobs are slower-changing maintenance. The daily/backup block is out of scope here.

## Where the pieces live

The repo source under `aegir/tools/system/` is deployed verbatim to `/var/xdrago/` on the box (`cp -af .../aegir/tools/system/* /var/xdrago/`). So a file the source tree calls `aegir/tools/system/minute.sh` is `/var/xdrago/minute.sh` at runtime. The single-shot monitors live one level down in `/var/xdrago/monitor/check/`. `loadreport` is the exception — it is deployed to `/opt/local/bin/loadreport` with a `/usr/local/bin/loadreport` symlink, like `fpmreport`.

| Launcher (repo → box) | What it drives |
|---|---|
| `aegir/tools/system/minute.sh` → `/var/xdrago/minute.sh` | Per-pass fan-out of the per-service watchdogs (`monitor/check/{system,unbound,valkey/redis,mysql,php,fpm_tune,sqlprobe,batch_guard,task_guard,nginx,nginx_guard,java}.sh`) |
| `aegir/tools/system/second.sh` → `/var/xdrago/second.sh` | Load sampling / auto-pause, the `_proc_control` service guards, the `hackcheck`/`hackftp`/`escapecheck` scanners |
| `aegir/tools/system/runner.sh` → `/var/xdrago/runner.sh` | Drains the `/var/xdrago/run-*` Ægir hosting tasks, gated by load and queue state |
| `aegir/tools/bin/loadreport` → `/opt/local/bin/loadreport` | Read-only `/proc` profiler; JSONL log every 30 min |

Every per-service watchdog launched by `minute.sh` re-sources `/root/.barracuda.cnf` on entry (so every `_VAR` override below is read fresh each pass) and exits immediately unless `/var/log/boa/reset_no_new_password.pid` exists — i.e. the auto-healing watchdogs stay dormant until the box is a fully installed BOA system. (The `second.sh` process guards and the launchers themselves do not gate on that marker.)

## The per-minute fan-out (and why idle load is high)

The crucial mechanism: **`second.sh` and `minute.sh` are launched once per minute by cron, but each self-loops with `sleep` between passes** to cover the whole minute at roughly 5-second granularity. They do not stay resident; they iterate, spawn a wave of single-shot monitors, sleep, and repeat until the minute is up — then exit, and cron starts them again.

```
cron (* * * * *)
   │  fires once per minute
   ▼
second.sh / minute.sh   ── re-entrancy guard (lock.inc; legacy pgrep fallback)
   │
   │  self-loop: iterate, fan out short-lived monitors, sleep, repeat (≈ whole minute)
   ▼
 pass 1 ─ fan out monitors ─ sleep ┐
 pass 2 ─ fan out monitors ─ sleep │  ~5s reaction granularity (NORMAL box)
 pass k ─ fan out monitors ─ sleep ┘
   │
   ▼  each spawned child:
   re-source /root/.barracuda.cnf  +  pgrep scans  +  check one service
```

This is **by design**: a dead `php-fpm` or a load spike is caught within ~5 seconds, not at the next whole-minute tick. But it is also the **dominant idle-load source on small boxes**. Roughly twenty short-lived processes are spawned every ~5 seconds, each re-sourcing `/root/.barracuda.cnf` and running `pgrep` scans. With zero site traffic, that churn alone can pin the load average at 3–4 on a 2 CPU / 4 GB box. The cost is fork/exec and config re-parsing, not real work — which is why only *disabling cron* (not tuning any single watchdog) drops the load to ~0. That is what the box-class throttle below tames.

> **Under the hood — why churn shows as load.** The Linux load average counts processes that are runnable or in uninterruptible sleep, sampled continuously. A constant stream of fork → source → `pgrep` → exit keeps several processes runnable at almost any instant, so the *average* runnable count stays near 3–4 even though no single task runs for long. On a NORMAL box `minute.sh` does ~9 passes × ~8 spawns ≈ 72 watchdog spawns/min, plus their helper forks; with `second.sh` on top the box churns on the order of 100–150 short-lived processes per minute.

## Re-entrancy: one instance at a time

Every launcher and every single-shot monitor guards against overlapping runs with the same `_manage_single_lock` pattern. It sources `lock.inc` (from `/opt/local/bin/` or `/opt/local/lib/`) and takes a shared single-instance lock; if that library is absent it falls back to a **legacy `pgrep -fc` count** and exits (logging to `/var/log/boa/too.many.log`) when more than two copies of the script are already running. This is why a slow tick never stacks into a fork storm — a new cron tick that finds the previous one still working simply exits. The auth scanners use their own PID-checked `noclobber` lock instead, to the same end.

`minute.sh` adds harder safety nets before it spawns anything — see the flood guards below.

## Service auto-healing watchdogs (`minute.sh`)

`minute.sh` runs `_launch_auto_healing` once per pass, which `nohup`-spawns each per-service watchdog concurrently. Each checks one service and, if it finds it down, stuck, or misconfigured, repairs it in place. The Valkey/Redis choice is made by an init-script probe: `valkey.sh` runs if `/etc/init.d/valkey-server` exists, else `redis.sh` if `/etc/init.d/redis-server` exists. `fpm_tune.sh`, `sqlprobe.sh`, `batch_guard.sh` and `task_guard.sh` run only if their files are present.

| Watchdog | Guards | Action |
|---|---|---|
| `system.sh` | OS-level health: SSHD, postfix, rsyslog, cron duplicates, LFD, FTPS (pure-ftpd), vnstat, gpg-agent / dirmngr pile-ups, ClamAV, DHCP lease, and system memory pressure | Restarts/starts the down service; on sustained memory pressure kills the single largest process that is safe to kill (below); culls runaway `wkhtmltopdf` between 5–10% free; forces logrotate; rebuilds DHCP allow rules in `csf.allow`; cooldown-gated per service |
| `unbound.sh` | Local DNS resolver: process + PID liveness, a live `host files.boa.io` lookup against `127.0.0.1`, duplicate masters, `/etc/resolv.conf` sanity | Restarts unbound (cooldown-gated); rewrites a BOA-tagged `/etc/resolv.conf` |
| `valkey.sh` | Valkey cache: a live socket `PING` through the cli, and only a connect-level failure — refused, missing socket, reset, or a hang past the probe timeout — counts as down, sustained across five spaced probes; `WRONGPASS`/`NOAUTH` (an auth drift to fix) or any other reply the server composed proves it alive; also `Address already in use` with a missing socket | Soft `service` restart first; forced stop/start only if that fails (that path wipes `/var/lib/valkey/*` — a disposable cache, and a dataset the server refuses to load back is the one fault a plain restart cannot clear). Paced by a cooldown and a flap circuit breaker (below). Honors a site-requested `run-valkey-restart.pid` (or box-wide `_ALLOW_VALKEY_RESTART=YES`) on qualifying plans, cooldown-only — an explicit request is never refused on automation history. PHP-side log symptoms are no longer detection, and it never touches PHP-FPM |
| `redis.sh` | **Retired from delivery**: the upgrade path no longer fetches it, so new installs never receive it | A box that already has it keeps its local copy, and the init-script dispatch still runs it there — legacy pre-Valkey logic (PING restart, `/var/lib/redis/*` wipe, FPM reload, plan-gated `run-redis-restart.pid`) |
| `mysql.sh` | Percona MySQL: a live `mysqladmin ping`, re-probed across a short grace before the server is called down; `Too many connections` floods, high-load × thread-count, runaway per-user queries, stuck `mydumper` | Database-only recovery, never a whole-stack restart: `move_sql.sh dbrestart` when `mysqld` is present but silent, `move_sql.sh start` when absent; kills queries past TTL; `flush-hosts`. A server that answers at all is never restarted. Paced by a cooldown and a flap circuit breaker (below); spawns `sqlcheck.sh` |
| `php.sh` | PHP-FPM (all installed versions, `56`–`85`): master + `wwwNN.fpm.socket` + PID liveness, duplicate masters, `already listen on` / `Address already in use` conflicts, per-pool `max_children` saturation (new error-log hits), giant logs, oversized `fastcgi_temp` | Per-version restart on a sustained, double-checked failure (cooldown-gated); cleans `fastcgi_temp`; honors the plan-gated (or box-wide `_ALLOW_PHP_FPM_RELOAD=YES`) `run-php-fpm-reload.pid` APCu-clear sentinel; spawns `segfault_alert.pl` (unless `/root/.high_traffic.cnf` or `/root/.giant_traffic.cnf` is set) |
| `fpm_tune.sh` | *Read-only* FPM sampler — no restart, no config change | Self-throttles to ~5 min and appends one JSONL record per pool/version to `/var/log/boa/fpm-tune/<date>.jsonl` (the data `fpmreport` reads); self-installs `libfcgi-bin` if missing, rate-limited |
| `sqlprobe.sh` | *Read-only* SQL sampler — no restart, no config change; `_USE_SQLPROBE=NO` opts a box out | Self-throttles to ~5 min and appends one JSONL record (per-second rate deltas between its own samples, pool/connection gauges, MemAvailable/PSI, mysqld VmRSS, plus the per-consumer needs-ledger facts: Solr JVM RSS against its `-Xmx`, FPM aggregate RSS with per-master pool/worker counts, nginx/clamd/valkey RSS, the residual everything-else RSS and the whole-box total, the Valkey hit/miss/eviction rates, and the file-cache evidence pair — MemFree beside MemAvailable, and Active(file)+SReclaimable) to `/var/log/boa/sqlprobe/<date>.jsonl` (the data `memorytuner` reads); refreshes the daily datadir fact, seeds the Valkey measured-ceiling store and maintains the Valkey demand window; skips backup/cache-drop windows, barracuda runs and `run-to-*` transitions |
| `batch_guard.sh` | Local batch self-DoS: the D7 `background_process`+`background_batch` pair re-POSTing `/bgp-start/background_batch%3A<bid>/…` (also the raw-colon and double-encoded `%253A` shapes the contrib emits depending on version and URL mode) from the box's **own** IPs under FPM saturation (nginx 499 storm, cron re-launching every stale process — the loop feeds itself and csf cannot ban the box's own address). Arms on the storm's own signal: many **distinct bids looping at once** — a bid counts only while still POSTing in the fresh minutes, so a site chaining legitimate batches counts as ONE — at or over `_BATCH_GUARD_STORM_BIDS_MIN`, plus a coarse own-IP `/bgp-start/`-only 499 volume bound at or over `_BATCH_GUARD_499_MIN` (implied by the bids floor at default knobs). Only a cron-relaunch storm loops tens of bids in the same fresh window (observed ~27 and ~100); healthy use runs a handful of concurrent batches box-wide, and a lone chatty batch (a running batch re-launches ~every 10 s by design) can never arm it. Load level is deliberately not an arm criterion (a pool-sized storm pins one FPM pool while box-wide load stays under any workable per-core floor — observed live at 0.69/core on a many-core box against the old 1.0/core gate — and the blind spot grows with core count); the ~5-min self-throttle bounds the always-on cost to one page-cache tail of the last 40k access-log lines per tick. Every further stage must pass: per-bid repetition (hour-bounded; wild-ssl fronted duplicates de-duplicated by their forwarded chain), unambiguous vhost→db attribution in nginx's own parse order, a live `background_process` flywheel row, and a two-pass no-change confirmation (blob length+MD5 + queue count) across ≥8 min of continuous service, with the bid still looping in the last minutes | Deletes ONLY the confirmed bid's `{batch}` row — conditionally, on the very fingerprint the confirmation measured, so a batch that moved keeps every row and the pass logs SKIPPED — plus its `background_process` handle; the queue rows are deliberately left to core cron's own reaper. No service restart (the observed storm drained in ~2 min on row deletion alone). Cooldown + flap circuit breaker (below); alerts once per site db; `_USE_BATCH_GUARD=NO` opts a box out, `_BATCH_GUARD_DETECT_ONLY=YES` keeps detection + alerts but never deletes |
| `task_guard.sh` | Crashed-task reaper — the decoupled recovery the dispatcher's 8h `count_running` window explicitly defers to. A task's final status is written only by its runner's own PHP shutdown handler, so a runner killed without reaching it (host reboot, an interrupted octopus/barracuda upgrade swapping the live code trees under its own dispatched tasks, a signal) leaves its current `hosting_task` revision at PROCESSING (-1) forever; each such corpse is subtracted from the dispatch concurrency budget for 8h, so at the default single-task limit one corpse wedges the instance's whole queue ("Maximum number of tasks (N) already running" every minute) and `hosting-pause` spins on it without a timeout. Detection is process evidence, never timestamps alone: only current-revision -1 rows (node-vid join; superseded revisions stay -1 by design) past a grace (`_TASK_GUARD_GRACE_MINS`, default 10) on an instance whose own user has **no** live task runner and **no** live provision backend — one live process holds the entire instance for that pass. Works on every deployed hostmaster vintage with no drush bootstrap (alias → site_path → `drushrc.php` → direct SQL), so it heals boxes whose frontend reaper (current hosting releases reap pid-stamped rows on every dispatch pass) hasn't arrived or whose drush tree the killed upgrade left broken; the per-vid conditional update lets both coexist | Marks each orphaned row `HOSTING_TASK_ERROR` (2) — the truthful outcome, never "Successful" — plus an explicit `hosting_task_log` row naming the watchdog; nothing is re-run (a crashed migrate/clone must never be re-fired blind). Stands down on a replication standby, a finalized PX0 proxy, live barracuda evidence (process-anchored — a stale `boa_run.pid` from a killed run must not park the very reaper that heals it) and fresh SQL-mutation markers; a live octopus run is deliberately NOT a stand-down (its tree swap is what mints the corpses, and on stock hostmaster bytes the run itself then spins on them in `hosting-pause` — a mid-run reap is what un-wedges it). `_USE_TASK_GUARD=NO` opts a box out, `_TASK_GUARD_DETECT_ONLY=YES` keeps detection + alerts but never writes |
| `xdr9000.sh` | *Read-only* permanent archive harvester (XDR9000) — no restart, no ban, no config change; `_XDR9000=NO` stops recording and keeps the archive | Copies the attack-ban ledgers (web/SSH/FTP), the incident logs of eleven auto-heal subsystems, backup outcome archives and the fpm-tune/sqlprobe/load-profile corpora into the append-only JSONL archive under `/var/log/boa/xdr9000/` before their routine reapers run; adds a metric sample every ~5 min and a box-facts record hourly; rolls up daily totals and gzips past months once per date change. The archive survives upgrades and log rotation by construction and is never pruned; the root-only `xdr9000` CLI reads it (see [XDR9000.md](XDR9000.md)) |
| `nginx.sh` | Nginx: master + `/run/nginx.pid` liveness, multiple masters, zombie/stopped master/worker states, `Cannot allocate memory` (OOM), `Address already in use`. A missing pidfile alone, with a live master still serving, is an artefact and stands down; a missing master always heals (workers inherit the listen sockets and serve headless) | Graceful escalation on every restart path, all cooldown-gated: QUIT to the recorded master (verified to still be nginx), a bounded wait, `-9` only for survivors, then `service nginx restart` (rotating `error.log`). Honors the plan-gated (or box-wide `_ALLOW_NGINX_RESTART=YES`) `run-nginx-restart.pid`; a request landing inside a cooldown is kept for the next pass |
| `nginx_guard.sh` | A keep-warm helper: that the nginx **access log** is being written at all | Reloads nginx if `access.log` is missing/empty, then loops `scan_nginx.sh` 10× (5 s apart) — this is the launcher that drives the [SECURITY.md](SECURITY.md) abuse scanner on the minute tick |
| `java.sh` | JVM services: Jenkins, Solr 9 / Solr 7 / Solr 4 (Jetty 9), and Jetty `Address already in use` | Restarts the down/stale-PID service (cleaning its `/tmp` scratch and rotating logs); skips entirely while a BOA/Octopus run is in progress |

A few load-bearing details worth calling out:

- **`system.sh` answers a memory emergency by freeing memory, not by taking the site down.** Pressure is read from `MemAvailable` and the ≤5% condition must hold across three samples five seconds apart, standing down the moment one recovers. The response is a single `kill -9` of the largest resident process that is safe to kill; `mysqld`, `sshd` and the provision/backup chain (`provision`, `drush`, `mydumper`, `duplicity`, `aegir.sh`, `backboa`, `multiback`) are never chosen, because killing one of those means a broken task or a corrupt dump rather than freed memory. If everything large is exempt it logs, pages, and leaves the rest to the kernel OOM killer. Between 5% and 10% free it only culls runaway `wkhtmltopdf` (more than 2 instances). Repeats are paced by `_OOM_COOLDOWN_SECS` (60 s) and capped by a breaker that latches `/run/boa_oom_latched.pid` after `_OOM_FLAP_MAX` (3) kills inside `_OOM_FLAP_WINDOW_SECS` (3600 s), pages once, and waits for an operator or `_OOM_FLAP_LATCH_MINS` (60). This replaced a cascade that killed seven services within three seconds of a single `free -mt` sample, wiped the cache server's data, restarted Percona through the whole-stack path and never restarted the web tier it had killed.
- **`mysql.sh` only restarts a database that will not answer.** A needless MySQL restart is itself an outage, so the test is functional: a `mysqladmin ping` reply of any kind proves the server is alive, an authentication error or `Too many connections` included, and a first failed probe is re-tried across a short grace before the server is called down. That grace matters where `mysqld_safe` supervises Percona, since it respawns a dead `mysqld` within a second or two and the socket and PID file are legitimately absent meanwhile. A busy-but-responsive server is therefore never restarted: high load with a high thread count (`_LOAD_THRESHOLD` 33.0 *and* `_THREAD_THRESHOLD` 99) and a `Too many connections` flood both fall through to the real remedies, `flush-hosts` and the long-query killer.
- **`fpm_tune.sh` never tunes anything live.** It is purely the data collector for FPM capacity sizing; the JSONL it writes is consumed by `fpmreport`.
- **`sqlprobe.sh` never tunes anything live either.** It is the SQL-side sibling: the data collector behind the `memorytuner` advisory, which in turn only *names* `_SQL_*_FORCE` pin lines — applying them stays a human decision. Its three side stores (the daily datadir measurement, the Valkey used-memory peak taken only after an hour of cache uptime, and the Valkey demand window — hits, misses and evictions accumulated from deltas between two same-run samples an hour or more into that run, plus the high-water live occupancy seen within the window; the 7-day rotation decays the counters by halving rather than zeroing them and re-anchors the peak to the current sample, while the control loop clears the whole window whenever it acts, so each step is judged on post-action evidence only) keep the automatic tuning's own stores fresh between weekly upgrades; a box that opts out with `_USE_SQLPROBE=NO` simply falls back to measuring at tune time. The demand window is the primary input to the cache-ceiling control loop in the tune pass, which steps the ceiling from hit rate and eviction behaviour rather than from occupancy; the older peak-times-four rung survives only as its fallback, so an opted-out box reverts to it once the window goes stale. `memorytuner` also renders a per-box needs ledger from the records carrying the ledger keys — measured per-consumer demand with stated margins, an OS reserve derived from residual RSS, and file cache treated as the budget remainder — and that ledger is observation only: it names no pin and applies nothing. While a demand window exists the advisory reports the self-managed ceiling and recommends against `_VALKEY_MAXMEM_FORCE`, since pinning it disables the loop.
- **`batch_guard.sh` can only kill what is provably dead — and load level is never consulted, in either direction.** It arms on the storm's own two-floor signal (`/bgp-start/`-specific own-IP 499 volume + many distinct looping bids — the knobs above), never on load: a pool-sized storm pins one FPM pool and degrades that site while a many-core box's average stays under any workable per-core floor (observed live at 0.69/core against the old 1.0/core gate, for 40+ minutes, blind), and in the other direction it never waits for calm either — its heal is cheap SQL, not a restart. Age is never a criterion (D7 writes `{batch}.timestamp` once, at creation, so a long-running live batch and an abandoned one look identical by age); a bid heals only if it is looping through `/bgp-start/` right now, is driven by a live `background_process` row (which is what the module's cron re-launches — browser and update.php batches never have one, so they are structurally unreachable, and forged request walls cannot make a victim's batches eligible), and its blob fingerprint plus queue count survived at least eight minutes unchanged — with the final DELETE conditional on all three of those same values. It also never gates on the `/run/max_load.pid` tier markers: second.sh sets those even on passes where it declines to pause, so a marker gate would disarm the guard for whole backup nights. What it requires instead is **service continuity**: no candidate confirms unless nginx, every FPM master and mysqld have been up, uninterrupted, since before its first sighting — pidfile birth times and the server's own Uptime are the witnesses — because a teardown (the load auto-pause, a watchdog heal, a DB restart) freezes every blob and would make a live batch read as dead; a teardown that came and went entirely between two passes still invalidates the interval. Knobs: `_BATCH_GUARD_499_MIN` (200) + `_BATCH_GUARD_STORM_BIDS_MIN` (12) — the two arm floors — `_BATCH_GUARD_BID_MIN` (20), `_BATCH_GUARD_COOLDOWN_SECS` (600), breaker `_BATCH_GUARD_FLAP_MAX`/`_BATCH_GUARD_FLAP_WINDOW_SECS`/`_BATCH_GUARD_FLAP_LATCH_MINS` (3/7200/60, latch `/run/boa_batch_guard_latched.pid`); `--detect-only` is the operator dry run and beats any cnf line.
- **`task_guard.sh` can only fail what is provably dead — and it never re-runs anything.** The judgement is the process table: an orphaned PROCESSING row is touched only when it is past the grace, is the task's current revision, and its instance user has no live task runner and no live provision backend — one live process holds the whole instance for that pass, because with per-user evidence the guard never guesses which row a process belongs to (the failure direction is a delayed heal, never a killed live task). The reset is per-vid and conditional on the row still being PROCESSING, so the frontend's own dispatcher reaper (on current hosting releases) and the manual button always win a race. It marks rows failed with a truthful log entry; re-running a crashed task is the operator's call — an auto-`--force` of a crashed migrate or clone is exactly the class of blind re-fire BOA never does.
- **`nginx_guard.sh` is the bridge to the security layer.** `scan_nginx.sh` is detection-only and is launched only here (10 spawns, 5 s apart) on the `minute.sh` fan-out — `second.sh` does not run it. See [SECURITY.md](SECURITY.md).

### What `minute.sh` does before the fan-out: flood guards

Before it spawns any watchdog, `minute.sh` runs two flood guards of its own. These protect the box from a runaway monitor or a csf reload storm spinning up faster than it drains — exactly the failure mode that would otherwise pin a small box at high load.

| Guard | Trigger | Action |
|---|---|---|
| `_second_flood_guard` | more than 4 live `second.sh` processes | log to `/var/log/boa/sec-count.kill.log`, `pkill -9 -f second.sh` |
| `_csf_flood_guard` (csf) | more than 4 live `/csf` processes | log to `csf-count.kill.log`, `pkill -9 -f csf`, then `csf -tf` + `csf -df` to flush temp/deny bans |
| `_csf_flood_guard` (fire) | more than 7 `guest-fire.sh` processes | flush csf temp bans, `pkill -9 -f fire.sh`; at more than 9, also purge deny rules |

Both guards are skipped while a BOA run is in progress (`/run/boa_run.pid`) so they never fight an upgrade. `_csf_flood_guard` is additionally gated on the `csf` binary being present (`/usr/sbin/csf`) and no `/run/water.pid` (the guest-water drain) being active, and it re-asserts SYNPROXY (`synproxy_reassert -p "443 80" --no-quic`) when `/etc/csf/csfpost.d/synproxy.sh` is present.

### Cooldowns, double-checks, and load gating

Six patterns recur across the watchdogs:

1. **Double-check before acting.** Almost every restart path re-reads the symptom after a short `sleep` (2–5 s) and acts only if it persists. This filters out the transient flap — a socket mid-reload, a log line from a restart that already happened — that would otherwise trigger a needless restart.
2. **Per-service cooldown stamp.** A restart writes `date +%s` to a `/run/<service>-monitor.cooldown` (or per-version `/run/phpNN-fpm.cooldown`) file. A subsequent failure within the cooldown window (default 30 s) logs a skip instead of restarting again, breaking restart storms when a service is crash-looping for a reason a restart cannot fix. Overridable per service: `_UNBOUND_COOLDOWN_SECS`, `_VALKEY_COOLDOWN_SECS`, `_REDIS_COOLDOWN_SECS`, `_FPM_COOLDOWN_SECS`, `_NGINX_COOLDOWN_SECS`, and `_CRON_/_POSTFIX_/_LFD_COOLDOWN_SECS` (in `system.sh`). The database is the exception to the 30 s figure: `_SQL_COOLDOWN_SECS` defaults to **120 s**, because a database restart takes far longer to settle than a web-tier one.
3. **A flap circuit breaker on repeated heals.** The cooldown spaces two heals; it cannot see a run of them. `mysql.sh` keeps a restart ledger at `/var/log/boa/mysql.restart.ledger`, pruned to `_SQL_FLAP_WINDOW_SECS` and never counted further back than the last boot. Once `_SQL_FLAP_MAX` (3) heals have run inside that window the circuit opens: it writes `/run/boa_mysql_restart_latched.pid`, logs `CIRCUIT OPEN`, sends exactly one e-mail, and stops restarting the database. Recovering a latched host is deliberately a human decision — fix the cause, delete the latch, and healing resumes with the count at zero — but it re-arms itself after `_SQL_FLAP_LATCH_MINS` (60) if nobody does. A server that recovers on its own, a `mysqld_safe` respawn say, is never counted against the budget. `system.sh`'s memory-pressure path uses the same machinery for its kills, and `valkey.sh` runs the same shape for cache restarts — ledger `/var/log/boa/valkey.restart.ledger`, latch `/run/boa_valkey_restart_latched.pid`, knobs `_VALKEY_FLAP_MAX` (3) / `_VALKEY_FLAP_WINDOW_SECS` (3600 s, floored so tick-quantised heals still fit) / `_VALKEY_FLAP_LATCH_MINS` (60) — kept inline in the file for the same delivery-skew reason `mysql.sh` keeps its own copy.
4. **Standing down for a database restart.** `move_sql.sh` stops Nginx and every PHP-FPM pool to restart the database and does not start them again, so those watchdogs are the intended recovery. `nginx.sh`, `php.sh`, `valkey.sh` and `redis.sh` therefore stand their whole pass down while `/run/mysql_restart_running.pid` or `/run/boa_mysql_auto_healing.pid` is present and recent (`_SQL_MUTATION_MAX_MINS`, 15 min), rather than restarting their service into a database that is still coming up. `second.sh` honours the same two markers on the resume side: it will not clear the web pause latch mid-restart. Recovery is deferred, not cancelled.
5. **Keeping table repair out of the way.** `sqlcheck.sh` and `checksql.sh` run a full-server `mysqlcheck` that takes locks across every database, so both decline while a backup, another maintenance operation, an auto-heal or a restart is in flight. `mysql_repair.sh` holds `/run/boa_sql_maintenance.pid` for its own run so the watchdog cannot read that work as a fault.
6. **Load and run gating.** Most watchdogs stand down while `/run/max_load.pid` or `/run/critical_load.pid` exists (the box is already shedding work — see Load control below), during a BOA run (`/run/boa_run.pid`), and while another auto-heal of the same service is mid-flight (`/run/boa_<service>_auto_healing.pid`).

### Email reporting

When a watchdog takes a corrective action it appends to `/var/log/boa/<service>.incident.log` and may e-mail `_MY_EMAIL`, gated by `_INCIDENT_REPORT` (from `/root/.barracuda.cnf`). The **send threshold differs by watchdog**: in `unbound.sh`, `php.sh`, `nginx.sh` and `java.sh` the e-mail is sent **only when `_INCIDENT_REPORT` is `ALL`** — their lower settings still log but mail nothing. `mysql.sh` sends on anything other than `OFF`. `system.sh` implements the `OFF` / `CRIT` (= ALERT-only) / `ALL` ladder. `valkey.sh` implements the full four-step ladder: a genuine cache restart mails at the default `MINI` and up — a cache restart empties the cache, and while that mail was ALL-only an operator learnt about a flapping cache server from the load graphs — the circuit-breaker page is an `ALERT` that `CRIT` still hears, and informational notices stay `ALL`-only. (`redis.sh`, retired from delivery, keeps its old ALL-only gate on boxes that still run it.) In every case the corrective action and the `.incident.log` entry happen regardless of the e-mail setting. A watchdog also sends **one alert per class of incident per `_INCIDENT_EMAIL_COOLDOWN_SECS`** (30 min) rather than one per pass, and says in the subject how many it stood in for; nothing is lost, because every incident is still logged and the mail body is the tail of that log. Classes that are not the same incident keep separate cooldowns — the database circuit breaker, backup contention, anything `system.sh` raises at `ALERT`, the valkey restart (`valkey`) / alert (`valkey-alert`) / circuit (`valkey-circuit`) classes, and `second.sh`'s pause/terminate pages (`second`; a terminate-and-pause pair is one incident, so both share the key and the second mail is held with the first carrying it) — so a cheap alert cannot spend the budget an expensive one needs. Reporting is additionally suppressed during the post-boot uptime grace period (see Load control), so a reboot does not spray "service was down, restarted" mail while the stack is still coming up.

## Load control and auto-pause (`second.sh`)

`_load_control` is BOA's per-host **auto-pause safety net**: it measures the system load average every ~5 seconds and, when load stays dangerously high, throttles crawlers, pauses the web stack, and kills runaway processes — then restores everything automatically once load drops. Its design goal is that a misbehaving site, a crawler storm, or a stuck Drush job degrades *gracefully* — shed load and recover — rather than taking the whole box down so hard that even SSH stalls.

`second.sh` is launched once per minute and self-loops 10 times with `sleep 5`, so the load test fires roughly every 5 seconds across the whole minute. **Load sampling runs on every pass, on every box, regardless of box class** — only the *heavy* fan-out (process guards + scanners) is throttled. Auto-pause therefore stays fully responsive (~5 s reaction window) even on a throttled CI or SLOW host.

### The load metric

`_get_load` reads `/proc/loadavg` and normalises the 1-minute and 5-minute averages to a **per-CPU percentage**:

```
_O_LOAD = (loadavg_1min / nproc) * 100      # 1-minute, per-CPU %
_F_LOAD = (loadavg_5min / nproc) * 100      # 5-minute, per-CPU %
```

Normalising by `nproc` is what makes one set of thresholds valid across a 2-core VM and a 64-core bare-metal host: a per-CPU load of `100%` means the run queue equals the core count regardless of how many cores there are. A box at `_O_LOAD=410%` is running its 1-minute queue at ~4.1× its core count. Both the 1-minute (catches a sudden burst) and 5-minute (catches a sustained grind) figures are tested.

### The thresholds

Four **per-CPU load ratios** define the escalation ladder. `_load_control` multiplies each by 100 to get the percentage threshold compared against `_O_LOAD` / `_F_LOAD`.

| Ratio variable | Default | × 100 = threshold | Tier | Action |
|---|---|---|---|---|
| `_CPU_SPIDER_RATIO` | `2.1` | 210% | SPIDER | Block crawlers (web stays up) |
| `_CPU_TASK_RATIO` | `3.1` | 310% | TASK | Skip backend tasks (web stays up) |
| `_CPU_MAX_RATIO` | `6.1` | 610% | MAX | Pause nginx + PHP-FPM |
| `_CPU_CRIT_RATIO` | `8.1` | 810% | CRIT | Kill long procs, then pause web |

The defaults are deliberately **well above 100%**. A BOA box is expected to run its cores hot under normal traffic; auto-pause is a last resort for genuinely pathological load, not a load balancer. On a 2-core box, SPIDER trips when the 1-minute load average reaches ~4.2, MAX at ~12.2, CRIT at ~16.2. All four are overridable in `/root/.barracuda.cnf` and are sanitised on load (anything but digits and a decimal point is stripped), so a malformed override falls back to the built-in default rather than breaking the arithmetic.

The `TASK` ratio (`3.1`) is consumed by the task-queue runner (below), not by the web-pause ladder. The three tiers `_load_control` itself acts on are SPIDER, MAX and CRIT.

### The escalation ladder

`_load_control` is a single `if/elif` chain evaluated highest-tier first, so only one action fires per pass. Crucially, **every tier is re-verified after a `sleep 9` cooldown** before it acts: a one-off spike that has already passed by the time the cooldown elapses is ignored. Only *sustained* load triggers a response.

```
measure _O_LOAD (1m) and _F_LOAD (5m), per-CPU %
  │
  ▼  CRIT — _O_LOAD or _F_LOAD > 810%?
  │    yes ─► sleep 9, re-check ─► still high:
  │            _terminate_processes  (TERM php/drush/wget/curl, 2s grace, -9 survivors)
  │            then _hold_services   (stop nginx + php-fpm)
  │            touch /run/critical_load.pid
  ▼  MAX — _O_LOAD or _F_LOAD > 610%?
  │    yes ─► sleep 9, re-check ─► still high:
  │            _hold_services        (stop nginx + php-fpm)
  │            touch /run/max_load.pid
  ▼  SPIDER — load > 210% and ≤ 610%?
  │    yes ─► sleep 9, re-check ─► still high:
  │            _nginx_high_load_on   (enable nginx_high_load.conf, block crawlers)
  │            touch /run/spider_load.pid
  ▼  NORMAL — touch /run/normal_load.pid
            if spider protection on and both loads ≤ 210%: _nginx_high_load_off
```

- **SPIDER — block crawlers.** When per-CPU load sits above 210% but at or below 610% (checked on both the 1-minute and 5-minute figures), `_nginx_high_load_on` renames `/data/conf/nginx_high_load_off.conf` to `/data/conf/nginx_high_load.conf` and reloads nginx. That file is glob-included by `aegir/conf/nginx/nginx_compact_include.conf` (`include /data/conf/nginx_high_load.c*;`), so swapping the suffix toggles crawler blocking without rewriting any vhost. The web stack stays fully up for real users; only spiders are shed. This is the only tier that does **not** set `_skip_proc_control`, so the heavy fan-out still runs on its normal cadence.
- **MAX — pause the web stack.** Above 610%, `_hold_services` stops the entire web tier: `service nginx stop`, then `force-quit` on every installed `php<NN>-fpm`, then a belt-and-braces `killall php-fpm` and `killall nginx`. The box stops serving so the run queue can drain. An `ALERT`-level incident is logged and (subject to policy) e-mailed.
- **CRIT — terminate runaways, then pause.** Above 810%, `_terminate_processes` runs **first** — a stuck PHP request, a Drush job in a loop, a wget/curl pulling something huge — *before* `_hold_services` pauses the web tier. Killing the runaway first is what lets the box recover instead of immediately re-spiking after the pause. The kill is TERM-first with a two-second grace before `-9` reaches only the survivors: a Drush job SIGKILLed mid-write leaves half-applied state on disk that no rollback repairs.
- **NORMAL — recovery.** When load is at or below the spider threshold on **both** figures, the box is marked healthy and, if spider protection is on, `_nginx_high_load_off` reverts the file and reloads. Recovery is automatic — there is no manual un-pause. (`_hold_services` *stops* services rather than disabling them, so the next normal pass / service watchdog brings nginx and PHP-FPM back; the spider config is the only piece `_load_control` explicitly reverts.)

### The backup pause-skip (MAX/CRIT only)

Both drastic tiers carry a deliberate exemption: when the high load is caused by a running backup that is genuinely disk-bound, MAX and CRIT **skip** the pause/kill entirely and only log. Pausing nginx/PHP-FPM does nothing for a disk-bound dump — it cuts service for no benefit — so the tier stands down instead. Two conditions must both hold before the skip applies:

- **A backup is in progress** — `_backup_in_progress` matches the BOA backup orchestrators by path (`backboa` / `duobackboa` / `multiback` / `mysql_backup.sh` / `mysql_cluster_backup.sh`) or the dump engines by exact name (`mydumper`, `duplicity`), or finds `/run/boa_sql_cluster_backup.pid`.
- **The load really is I/O-wait-bound** — `_load_is_iowait_bound` samples system iowait% over a short `/proc/stat` delta and requires it at or above `_LOAD_IOWAIT_MIN` (default **10**%). This is what distinguishes a self-limiting backup from a CPU-bound runaway that merely coincides with the backup window: a CPU-bound spike has low iowait, so pause/kill still fire.

The measurement **fails closed** — any read error or degenerate delta yields 0% iowait, which is below the threshold, so the drastic tiers still act. `_LOAD_IOWAIT_MIN` is overridable in `/root/.barracuda.cnf`.

### Resume hysteresis — the pause latch

The MAX/CRIT markers are **latched**: once `/run/max_load.pid` or `/run/critical_load.pid` is set, `_clear_pause_latch` removes them only after **both** the 1-minute and 5-minute per-CPU loads fall below `_CPU_RESUME_THRESHOLD` (= `_CPU_MAX_THRESHOLD` × `_RESUME_FRACTION`, default fraction **0.8** → 80% of the MAX threshold). The service watchdogs restart web only when both markers are absent, so this holds the web tier paused through the dip band just under MAX instead of un-pausing the instant load ticks below the threshold — without it a box hovering at the line flapped pause/resume every pass. `_RESUME_FRACTION` is overridable in `/root/.barracuda.cnf` and is clamped to the open interval (0,1): a value of 0 (or a typo sanitising to a bare `.`) would leave the latch never clearing, and a value ≥ 1 would disable the hysteresis, so anything outside (0,1) resets to the default.

The threshold alone cannot see one kind of flap: a pause that stopped the web tier collapses load toward zero, and a single below-resume reading is exactly what that collapse produces — it proves the web is off, not that the pressure is gone. So the clear takes **`_RESUME_HOLD_PASSES` (default 3, clamped 1–60) consecutive below-resume evaluations**; the streak is persisted in `/run/second_resume_streak` so it spans the script's one-minute lifetimes, goes stale after a quiet gap, and resets whenever the calm is interrupted. The clear also **stands down while a database restart is in flight**, on the same two markers and `_SQL_MUTATION_MAX_MINS` recency bound the web watchdogs use — a latch cleared mid-restart would only queue the herd against a database that is not back yet. Resume is evaluated at the end of **every** pass, whatever load tier ran: a MAX/CRIT pass whose post-sleep re-check just-missed its tier used to run nothing at all, stranding a latch set a minute earlier. Both the held and the cleared latch log one line to `high.load.incident.log`. The latch still **fails toward resume** — a missing or unusable threshold clears the markers after the minimum hold rather than leaving web stuck paused.

### State files in /run

Each pass writes exactly one tier marker under `/run` and removes the other three, so the current posture is always readable from a single existing file. Several service watchdogs read these to decide whether to stand down.

| State file | Meaning |
|---|---|
| `/run/normal_load.pid` | Load within normal parameters |
| `/run/spider_load.pid` | Spider protection active (crawlers blocked) |
| `/run/max_load.pid` | Web stack paused (MAX) |
| `/run/critical_load.pid` | Critical: processes killed + web paused |
| `/run/boa_second_auto_healing.pid` | A pause/heal action is in progress (set by `_hold_services` for its duration, so two overlapping passes can't stack service stops). Honoured only while fresh: a marker older than ~2 minutes is an orphan from a run that died mid-hold and is dropped, so it can no longer gate pauses off for the ~10 minutes it took `clear.sh`'s five-minute reaper to catch it |
| `/run/second_resume_streak` | The count of consecutive below-resume evaluations behind the pause-latch minimum hold (`_RESUME_HOLD_PASSES`); removed on clear, on interrupted calm, and when no latch exists |

To read the live posture:

```bash
ls -1 /run/*_load.pid 2>/dev/null
tail -n 20 /var/log/boa/high.load.incident.log
```

### Incident reporting and the uptime grace gate

When a pause or kill fires, `_incident_email_report` appends to `/var/log/boa/high.load.incident.log` and may e-mail an alert. Two gates control whether mail is actually sent.

**Policy gate — `_INCIDENT_REPORT`.** Normalised to upper-case and matched against three current levels:

| Value | Behaviour |
|---|---|
| `OFF` | Total silence — never email (legacy `NO` maps here) |
| `CRIT` | Email only when the event level is `ALERT` (the effective default) |
| `ALL` | Email every event — very noisy, debugging only |

Legacy values are remapped at runtime: `NO` → `OFF`, `YES` → `CRIT`, `MINI` → `CRIT`; anything unrecognised also falls back to `CRIT`, so a typo fails safe to "critical alerts only". The shipped `/root/.barracuda.cnf` sets `_INCIDENT_REPORT=MINI`, which normalises to `CRIT` — so out of the box you receive only ALERT-level mail from `second.sh`. The pause/kill actions are coded at `ALERT`, so they are delivered under the default policy; the spider on/off events are coded at `INFO` and their e-mail calls are commented out, so routine crawler shedding is logged but never mailed.

> **Source note.** The comment block above the `_INCIDENT_REPORT` `case` in `second.sh` still describes an older intent where `MINI` was a distinct "most important alerts" level. There is no separate `MINI` runtime level any more — the code collapses both `YES` and `MINI` into `CRIT`. Trust the `case`, not the comment.

**Uptime grace gate — `_check_uptime_grace_period`** (from `lock.inc`) is the first thing `_incident_email_report` checks. It suppresses the e-mail (and forces `_INCIDENT_REPORT=OFF`) when **any** of these hold: system uptime is under 15 minutes; the Hostmaster alias `/var/aegir/.drush/hm.alias.drushrc.php` is missing, or `csf`/`lfd` aren't up yet; or an install/upgrade is mid-flight (`/run/octopus_install_run.pid`, `/run/boa_run.pid`, `/run/boa_wait.pid`). This stops a fresh boot or an in-progress BOA upgrade — both of which legitimately spike load — from flooding the mailbox before the box has settled.

**Destination — `_MY_EMAIL`** (default `notify@omega8.cc`), sent via `s-nail`; if empty, no mail is sent. The body is the incident log, which records every action (`Web Server Paused`, `PHP/Wget/cURL terminated`, spider protection enabled/disabled) with a timestamp and the offending load percentage regardless of whether mail was sent.

### Process priority — `_B_NICE`

`second.sh` renices itself (and the `_proc_control` pass) to `_B_NICE`. The value is sanitised to an integer and **clamped to the valid `nice` range `-20..19`**; anything out-of-range or non-numeric falls back to `0`. Set `_B_NICE` in `/root/.barracuda.cnf` to bias the whole monitor pass softer or harder against site traffic.

## Process guards and auth scanners (`second.sh` heavy pass)

On its *heavy* passes (cadence below), `second.sh` runs two extra blocks: the `_proc_control` service guards, and three auth/escape scanners launched directly.

### `_proc_control` — service guards

`_proc_control` is the successor to the legacy `proc_num_ctrl.pl`. Instead of one monolithic Perl monitor it fans out individual single-shot guards under `monitor/check/`, each detached via nohup/setsid. Each guard is **presence-gated**: a guard whose `.sh` file is not present (not fetched, or deliberately removed) is simply skipped. `_proc_control` itself is skipped on a heavy pass when load limits were already exceeded (`_skip_proc_control`, set by `_load_control` on a MAX/CRIT trip) — the three scanners below are launched **outside** that gate and still run. After fanning out, `_proc_control` touches `/var/log/boa/proc_num_ctrl.done.pid` as a heartbeat.

| Guard | Watches / acts on |
|---|---|
| `sendmail_guard` | Kills any **root-owned** process whose executable name contains `sendmail` (BOA delivers mail via postfix/msmtp, so a root sendmail MTA should never run). Excludes itself and its shell |
| `convert_guard` | Runaway ImageMagick `convert`. Acts only when more than one is running; a hot one (>10% CPU, accumulated CPU time, R/Z state) is logged to `convert.watch.log`, or **killed** when more than 5 are running *and* it exceeds 50% CPU (logged to `convert.kill.log`) |
| `hostname_sync` | On DHCP-managed hosts (`dhcpcd`/`dhclient` running), restores the running hostname from a non-empty `/etc/hostname` after a lease renewal reset it |
| `bind9` | Restarts `bind9` (`named`) when the daemon is down and `/etc/init.d/bind9` exists |
| `proxysql` | Restarts `proxysql` when down and `/etc/init.d/proxysql` exists |
| `droplet` | Restarts the DigitalOcean `droplet-agent` (serial/web-console access on DO VMs) when down/pidfile missing and `/etc/init.d/droplet-agent` exists |
| `newrelic_daemon` | Restarts the New Relic APM `newrelic-daemon` when down and `/etc/init.d/newrelic-daemon` exists |
| `newrelic_sysmond` | New Relic server monitor (`nrsysmond`), gated by the opt-in `_ENABLE_NEWRELIC_SYSMOND=YES` cnf variable (the former `/etc/boa/.enable.newrelic.sysmond.cnf` flag stays honoured during the conversion window): **restarts** it when enabled and the daemon is down, **stops** it when disabled and it is running |
| `collectd` | Starts `collectd` when down and `/etc/init.d/collectd` exists |
| `xinetd` | Starts `xinetd` when down and `/etc/init.d/xinetd` exists |
| `lsyncd` | Starts `lsyncd` when down and `/etc/init.d/lsyncd` exists |

The daemon-recovery guards (`bind9` through `lsyncd`) additionally bail out early while a BOA upgrade/maintenance run is in progress (`_run_to_active`: any of the `/root/.run-to-*.cnf` markers or `/run/boa_run.pid`), so service recovery never fights an in-flight upgrade.

### Auth and shell-escape scanners

On every heavy pass, `second.sh` also launches three log scanners directly, each detached with nohup. Unlike the nginx abuse scorer (see [SECURITY.md](SECURITY.md)), these are **single-pattern auth and shell-escape scanners** — two ban via csf, one e-mails an alert.

| Scanner | Scans | Looks for | Action |
|---|---|---|---|
| `hackcheck.sh` | `/var/log/auth.log` (incremental, byte-offset) | SSH auth abuse — failed-password / invalid-user / preauth disconnect / reset / timeout / malformed-banner probes from a non-local IPv4 | `csf -td <ip> 900 -p 22` (15-min temp ban) |
| `hackftp.sh` | `/var/log/messages` (incremental, byte-offset) | FTP (proftpd) auth abuse — `Authentication failed for user` and `cleartext sessions not accepted`, extracting `user@IP` | `csf -td <ip> 3600 -p 21` (1-hour temp ban) |
| `escapecheck.sh` | `/var/log/lsh/*.log` | `lsh` restricted-shell escape attempts in the current or previous minute | Email alert to `_MY_EMAIL` via `s-nail` (no ban) |

Shared design notes (verified against all three scripts):

- **Cron-race window.** All three accept both the **current and previous minute**, so an event logged late in one minute is not missed when the scan runs at the top of the next.
- **Dual timestamp formats.** `hackcheck.sh` and `hackftp.sh` parse both classic syslog and ISO 8601 (Debian 12+ rsyslog) timestamps; `escapecheck.sh` uses lsh's fixed `YYYY-MM-DD HH:MM:SS,mmm` format.
- **Incremental reads.** `hackcheck.sh` and `hackftp.sh` track a byte offset (`/var/log/scan_hackcheck_lastpos`, `/var/log/scan_hackftp_lastpos`) and read only bytes appended since the previous run, resetting on rotation/truncation.
- **`noclobber` lock.** Each takes a PID-checked `noclobber` lock (`/var/run/{hackcheck,hackftp,escapecheck}.lock`) so overlapping cron runs cannot stack.
- **Allow-list / maintenance safety.** `hackcheck.sh` never bans an IP present in `/etc/csf/csf.allow` or `/etc/csf/csf.ignore`, never bans an IP that had an `Accepted` login in the window, and — like `hackftp.sh` — suppresses direct csf bans while the `/var/xdrago/guest-fire.sh` maintenance flag is present (enforcement is then handled by `guest-fire.sh`). Bans are recycled after their TTL (`_BAN_SECONDS`) so an expired IP can be re-armed.

## The Ægir task-queue runner (`runner.sh`)

`runner.sh` is a **separate** per-minute cron job, not part of the `second.sh`/`minute.sh` fan-out. It drains the Ægir verify/migrate/backup task queue by executing the `/var/xdrago/run-*` runners. It is heavily gated so it never adds load on a box that should stay quiet:

- **Hard stops first.** It exits immediately if `/root/.proxy.cnf` (rightful: a proxy has no local sites for tasks), `/etc/boa/.pause_tasks_maint.cnf`, the PHP-idle quiesce marker `/run/boa_php_idle_quiesce.pid` (owner-PID keyed, dead-owner self-cleaning), or a `max_load`/`critical_load` pid is present; and again if too many `runner.sh` instances are already running, or a SQL backup, `owl.sh`, a MySQL restart/cluster-backup, or `boa_cron_wait.pid` is in flight.
- **Load-gated per runner.** `_runner_action` runs a `/var/xdrago/run-*` runner only while the 1-minute per-CPU load is **below `_CPU_TASK_RATIO * 100`** (default 310%); above that it waits. This is the same task ratio used by the load-control logic — backend tasks are skipped under load while the web tier stays up.
- **CI hosts (`/etc/boa/.look.like.jenkins.cnf` or `_FORCE_CI_BOX=YES` in `/root/.barracuda.cnf`).** No automatic queue by default. It runs only if the box is a PRO plan (`POWER`/`PHANTOM`/`CLUSTER`/`ULTRA`/`MONSTER` in the octopus control file) **or** `/etc/boa/.allow.aegir.queue.cnf` is present (or `_ALLOW_AEGIR_QUEUE=YES`), *and* at least one `run-aegir-queue.info` exists.
- **Small boxes auto-throttle.** `runner.sh` itself writes `/root/.slow.cron.cnf` and pins it immutable with `chattr +i` when total RAM ≤ 4096 MB. With `.slow.cron.cnf` present (and no `.force.queue.runner.cnf`) it allows only one concurrent runner and runs a single throttled pass per minute with `sleep 15` pads.
- **Fast / forced.** With `/root/.fast.cron.cnf` or `/root/.force.queue.runner.cnf` it runs the queue 10 times in the minute (`sleep 5` between), mirroring the `second.sh` cadence.

> **Disabling the queue does not lower idle load.** Marking a box CI with `.look.like.jenkins.cnf` stops `runner.sh` draining the Ægir queue, but it does **not** by itself remove the idle CPU cost — that comes from the `second.sh`/`minute.sh` monitor fan-out, a *separate* set of cron jobs. (Marking CI does also push `second.sh`/`minute.sh` into the CI box-class, which is the lever that actually quiets the fan-out — see below.)

## Cron cadence and the idle-load throttle

The responsiveness of the fan-out has a cost: on a small or idle box the fan-out itself is the dominant load source (the load 3–4 explained above). Before 2026-06-22, the two "small box" control files (`/root/.slow.cron.cnf`, `/etc/boa/.look.like.jenkins.cnf`) were honoured **only by the task-queue path** — `second.sh` and `minute.sh` ran the full NORMAL cadence on a tiny CI box exactly as on a 192 GB production host. The box-class throttle closes that gap, leaving NORMAL production hosts byte-for-byte unchanged.

### `_monitor_box_class`: CI / SLOW / NORMAL

Both loops classify the box once at startup with an identical `_monitor_box_class` function, resolving to one of three classes with this exact precedence:

| Order | Condition | Class |
|---|---|---|
| 1 | `/etc/boa/.look.like.jenkins.cnf` exists (or `_FORCE_CI_BOX=YES` in the cnf) | **CI** |
| 2 | (`/root/.slow.cron.cnf` exists **or** total RAM ≤ 4096 MB from `free -m`) **and** `/root/.force.queue.runner.cnf` is **absent** | **SLOW** |
| 3 | none of the above | **NORMAL** (default) |

The order matters: a CI box is CI even if it is also small; otherwise the ≤ 4 GB RAM check classifies the box SLOW even if `runner.sh` has not yet written `.slow.cron.cnf`. The one escape hatch is `.force.queue.runner.cnf`: present, it suppresses the SLOW gate so a small box runs the full NORMAL cadence. `.fast.cron.cnf` is deliberately **not** honoured here — `runner.sh` ignores it while `.slow.cron.cnf` is set, so letting it force NORMAL would un-throttle exactly the tiny boxes this targets (e.g. a 4 GB box carrying both markers). Because `runner.sh` auto-creates the immutable `.slow.cron.cnf` marker on ≤ 4 GB boxes, most small hosts hit the SLOW condition by either branch.

### Per-class cadence

The two loops throttle different things. `minute.sh` reduces both the **number of passes** and the **sleep** between them. `second.sh` keeps its responsive 10×/5 s load-sampling loop intact — load sampling is cheap and auto-pause must stay timely — and gates only the **heavy fan-out** (`_proc_control` plus the three scanners) to run every Nth pass.

| Box class | `minute.sh` fan-out | `second.sh` heavy fan-out | How detected |
|---|---|---|---|
| **NORMAL** | 9 passes, `sleep 5` (~72 spawns/min) | every pass (`_HEAVY_EVERY=1`, 10×/min) | default, or `.force.queue.runner.cnf` overriding a small box |
| **SLOW** | 3 passes, `sleep 18` (~24 spawns/min) | every 4th pass (`_HEAVY_EVERY=4`, ~3×/min) | `.slow.cron.cnf` or RAM ≤ 4096 MB |
| **CI** | 1 pass (~8 spawns/min) | every 10th pass (`_HEAVY_EVERY=10`, 1×/min) | `.look.like.jenkins.cnf` |

NORMAL values are exactly the historical behaviour. SLOW and CI trade fan-out granularity for idle quiet — a tiny or CI box does not need a 5-second watchdog heartbeat. `second.sh` keeps its full 10-pass / `sleep 5` loop in **every** class because that is where the high-load auto-pause sampling lives, so load detection reacts just as fast on a SLOW or CI box as on a NORMAL one.

> **Under the hood — the heavy-pass gate.** `second.sh` runs the heavy block on iteration `k` when `(k - 1) % _HEAVY_EVERY == 0`. On SLOW (`_HEAVY_EVERY=4`) that is iterations 1, 5 and 9 — three heavy passes per minute; on CI (`10`) only iteration 1.

### Override variables

Each computed default can be overridden from `/root/.barracuda.cnf`. The override must be an integer; the value **replaces** the per-class default, and each is then floored at 1 so a misconfiguration cannot disable the loop. A non-numeric or empty value is ignored and the class default stands.

| Variable | Loop | Per-class default | Effect |
|---|---|---|---|
| `_MONITOR_FANOUT_ITER` | `minute.sh` | NORMAL 9 / SLOW 3 / CI 1 | Number of `_launch_auto_healing` passes per minute |
| `_MONITOR_FANOUT_SLEEP` | `minute.sh` | NORMAL 5 / SLOW 18 / CI 5 | Seconds slept between passes |
| `_MONITOR_HEAVY_EVERY` | `second.sh` | NORMAL 1 / SLOW 4 / CI 10 | Run the heavy fan-out every Nth pass of the 10-pass loop |

> **NORMAL is unchanged.** With no override and no slow/CI marker, the defaults reproduce the historical cadence exactly. You only need these variables on a box where the class default is not aggressive enough (or, rarely, to force a NORMAL box quieter), e.g. on a disposable CI VM:
>
> ```ini
> _MONITOR_FANOUT_ITER=1
> _MONITOR_HEAVY_EVERY=20
> ```
>
> Do not raise `_MONITOR_FANOUT_SLEEP` so high that a stuck service goes unnoticed for minutes on a host you actually care about — the trade-off is detection latency for idle quiet, and it is only safe to lean hard on disposable or genuinely idle hosts.

## loadreport — the monitor resource profiler

`loadreport` answers one question: **on an idle box with no site traffic, which recurring script is burning the load average?** The monitor children live for a fraction of a second, so a `top`/`ps` snapshot almost never catches them, and `sysstat`/`pidstat`/process accounting are not installed on a stock BOA box. `loadreport` sidesteps all of that by sampling `/proc` repeatedly across a window and reconstructing per-script totals. It is dependency-free (pure bash + `/proc`, `sort`/`awk` only at print time), writes no configuration, and changes nothing. Linux only.

It is **not** one of the `/var/xdrago/` monitors — it does not loop and enforces nothing. You run it by hand, and one low-priority cron entry logs a periodic sample for history.

### How it works

- **Identity by `(pid, starttime)`.** Because targets are short-lived and PIDs recycle, every process is keyed by its PID *and* its start tick, so two scripts that reuse a PID are never conflated.
- **Birth-aware CPU charging.** The window start is recorded in boot-relative clock ticks from `/proc/uptime`. A process born during the window is charged its full cumulative CPU (`utime+stime`) from birth; a pre-existing process is charged only its in-window delta — which makes per-run totals meaningful for a script that spawns fresh every tick.
- **bash/sh resolve to the script.** A process whose `comm` is `bash`/`sh`/`dash` is relabelled to the basename of the first `*.sh`/`*.pl`/`*.php` argument in its `cmdline`, so a hundred `bash` wrappers collapse into `minute.sh`, `scan_nginx.sh`, etc. instead of a useless `bash` bucket.
- **Helper forks roll up to the launcher.** `pgrep`, `awk`, `bc`, `sleep` and friends are attributed to the BOA launcher that spawned them by walking the `/proc` parent chain (depth-bounded). The walk stops at a known launcher or at `cron`; anything past that is `(non-cron)`. The recognised launchers are `second.sh`, `minute.sh`, `runner.sh`, `guest-fire.sh`, `guest-water.sh`, `owl.sh`, `clear.sh`, `ip_access.sh`, `user_admin_access.sh`, `ai_policy.sh`, `nginx_deny.sh`, `nginx_deny6.sh`, `migration_proxy_realip.sh`, `cloudflare_realip.sh`, `manage_ltd_users.sh`, `manage_solr_config.sh`, `purge_binlogs.sh`, `mysql_cleanup.sh`, `graceful.sh`.
- **Systemic fork/ctxt bounds.** The window's `processes` and `ctxt` deltas from `/proc/stat` bound the *total* fork and context-switch churn, including processes too short-lived to ever appear in a sample.
- **Self-excluded.** It skips its own PID and its own `sleep` child, so the profiler never charges itself.

### Two views

- **BY COMMAND** — one row per resolved script basename: summed CPU seconds, percent of one core over the span, spawn count, peak RSS for a single process, and concurrent RSS (worst-case sum of that script's live instances in any one pass).
- **BY LAUNCHER (subtree)** — the same CPU rolled up to the owning cron launcher, so a launcher's *whole* cost (itself plus every helper fork) lands in one number. This is the view that tells you which cron entry is the real load source.

### Usage

| Invocation | Mode | Effect |
|---|---|---|
| `loadreport` | live | Default human report. Profiles for `_LOADPROF_WINDOW` (60 s) sampling every `_LOADPROF_INTERVAL` (1 s), prints both tables, top `_LOADPROF_TOP` (25) rows |
| `loadreport --window N` | live | Override the profiling window in seconds (validated `>= 1`, else 60) |
| `loadreport --interval S` | live | Override the sample interval in seconds; accepts a decimal (e.g. `0.5`). Must be `> 0`, else 1 |
| `loadreport --top N` | live | Show the top `N` rows by command instead of 25 |
| `loadreport --all` | live | Show every row |
| `loadreport --json` | live | Emit one machine-readable JSON object instead of the tables |
| `loadreport --log` | log | Profile once, append a JSONL record to the data dir, prune old logs. The `*/30` cron entry |
| `loadreport --data DIR\|FILE… [--days N]` | data | Summarise logged JSONL history; `--days N` restricts to the last `N` days |
| `loadreport -h` / `--help` | — | Usage |

Numeric inputs are validated defensively and fall back to the default on garbage rather than dividing by zero. Every default is overridable from the **process environment** or an equivalent CLI flag — `loadreport` does not read `/root/.barracuda.cnf` (unlike the watchdogs), so these are tuned by exporting the variable before the run, not from a control file:

| Variable | Default | Meaning |
|---|---|---|
| `_LOADPROF_WINDOW` | `60` | profiling window, seconds |
| `_LOADPROF_INTERVAL` | `1` | sample interval, seconds (decimal ok) |
| `_LOADPROF_TOP` | `25` | rows in the BY COMMAND table |
| `_LOADPROF_DATA` | `/var/log/boa/load-profile` | history directory for `--log`/`--data` |
| `_LOADPROF_KEEP_DAYS` | `14` | retention for `--log` pruning, days |

### The periodic logger

The root crontab runs the logger every 30 minutes at idle priority:

```
*/30 * * * * /usr/bin/nice -n10 /usr/bin/ionice -c3 \
  bash /opt/local/bin/loadreport --log >/dev/null 2>&1
```

The `nice -n10` / `ionice -c3` (idle I/O class) keeps it off the back of real work. The `--log` path runs on proxy nodes too (since the 2026-08-09 marker narrowing — relay load is exactly what a PX0 box carries), runs a normal live profile, appends the JSON object as one line to `${_LOADPROF_DATA}/YYYY-MM-DD.jsonl` (one file per day), and **prunes** `*.jsonl` older than `_LOADPROF_KEEP_DAYS` (default 14). Read the history back with `--data`, which averages CPU seconds per command across the retained records and tracks peak concurrent RSS.

### Reading the output

The example below is illustrative (constructed from the `printf` formats, not captured from a real box). It shows the shape of a quiet 2-core box where the monitor fan-out, not site traffic, is the load:

```
loadreport — BOA recurring-script resource profile
  host  example   span 60s   interval 1s   cores 2   HZ 100
  load1 3.41 -> 3.18
  forks during span: 2280 (2280/min)   ctxt switches: 41200 (687/s)
  distinct processes sampled: 214

  BY COMMAND                     CPU_s  %1core  spawns  peakRSS  concRSS
  minute.sh                       9.74    16.2      11      6.1     34.8
  second.sh                       7.05    11.8      12      5.9     41.2
  scan_nginx.sh                   3.61     6.0       3      9.4      9.4
  pgrep                           2.88     4.8     180      1.2     12.6
  ip_access.sh                    1.10     1.8       1      4.7      4.7

  BY LAUNCHER (subtree)          CPU_s  %1core   procs
  minute.sh                      14.92    24.8      96
  second.sh                      11.40    19.0     104
  (non-cron)                      1.95     3.2      14
```

How to read it:

- The **summary line** (`forks during span`, `ctxt switches`) is the systemic churn. `2280/min` forks on an idle box is the fan-out, not your sites. This includes processes too short-lived to be named individually.
- **BY COMMAND** names the worst scripts. `pgrep` with 180 spawns but little CPU each is the per-child cost of the monitor scans, multiplied across the fan-out.
- **BY LAUNCHER** rolls every `pgrep`/`awk` fork back under `minute.sh` / `second.sh`. When those two subtrees dominate the launcher table, **the fan-out is your idle load** — throttle it via the box-class knobs above.
- `concRSS` is worst-case concurrent memory: `minute.sh` peaked at ~35 MB of simultaneously-live instances even though any single one was ~6 MB.
- `scan_nginx.sh` shows up as its own BY COMMAND row, but because it is not in the launcher list its cost rolls up under `minute.sh` (its launcher, via `nginx_guard.sh`) in the BY LAUNCHER table.

### Caveat — sub-tick processes are counted, not named

A process born *and reaped entirely between two ticks* never appears in a sample, so it is **not named** in either table — but it is still counted in the systemic `forks` total from `/proc/stat`, which is why that number can exceed the sum of the named `spawns`. If the fork total is high but the named tables look light, rerun with a finer `--interval` (e.g. `0.5` or `0.25`) to catch more of it. Processes shorter than the sample gap are inherently invisible by name, but the `/proc/stat` counters always bound the true total.

## Serials and deployment

`second.sh`, `minute.sh` and `loadreport` are serial-gated in `BOA.sh.txt`, so each box automatically re-fetches the current copy whenever one of these scripts changes — you do not pull updates by hand. `loadreport` is fetched to `/opt/local/bin/loadreport`, symlinked to `/usr/local/bin/loadreport`, and `chmod 700`.

## Verify

```bash
# live load posture
ls -1 /run/*_load.pid 2>/dev/null
tail -n 20 /var/log/boa/high.load.incident.log

# which box class this host resolves to (mirror the classifier)
ls -1 /etc/boa/.look.like.jenkins.cnf /root/.fast.cron.cnf \
      /root/.force.queue.runner.cnf /root/.slow.cron.cnf 2>/dev/null
grep -E "^_FORCE_CI_BOX=" /root/.barracuda.cnf 2>/dev/null
free -m | awk '/^Mem:/{print "RAM MB:", $2}'

# who is burning idle load (live 60s profile, then logged history)
loadreport --top 40
loadreport --data /var/log/boa/load-profile --days 1

# recent auto-heal / kill activity
tail -n 20 /var/log/boa/*.incident.log 2>/dev/null
ls -1 /var/log/boa/*.kill.log 2>/dev/null
```

## See also

- [SECURITY.md](SECURITY.md) — the security-facing members of the same `/var/xdrago/monitor/` family: `scan_nginx.sh` and the csf ban pipeline (`guest-fire` → `guest-water` → `nginx_deny`) that this stack drives but does not duplicate.
- [AI-POLICY.md](AI-POLICY.md) — the AI-crawler classification and per-site policy applied at the nginx layer (`ai_policy.sh`).
- [IP-ACCESS.md](IP-ACCESS.md) — per-site IP allow/deny rules (`ip_access.sh`).
- [SKYNET.md](SKYNET.md) — the auto-self-update mechanism that keeps these monitor scripts current on every box.
