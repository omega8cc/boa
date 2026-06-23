# BOA monitor stack (sysadmin)

BOA has no external monitoring agent and no resident daemon. Every box watches and repairs **itself** from a single root crontab that fires a handful of short-lived bash scripts every minute. Those scripts sample load, restart dead services, kill runaway processes, scan auth logs for abuse, and drain the Aegir task queue — then exit. There is nothing long-running to crash; the watchdog *is* the cron tick. Think of it as the octopus feeling each of its own arms every few seconds and pulling back anything that has gone limp.

This document covers the **service / load / process** side of that machinery: what cron launches, the self-looping fan-out that gives it sub-minute reaction time, the per-service watchdogs, the load auto-pause ladder, the process guards and auth scanners, the box-class throttle that keeps the fan-out from pinning idle load on small hosts, and the `loadreport` profiler used to measure it.

The **security-facing** members of the same `/var/xdrago/monitor/` family — the nginx log scorer `scan_nginx.sh` and the csf ban pipeline — are documented in [SECURITY.md](SECURITY.md), and the AI-crawler and ban-mirror generators in [AI-POLICY.md](AI-POLICY.md) and [IP-ACCESS.md](IP-ACCESS.md). The self-update half (how the monitor scripts themselves get refreshed on every box) is [SKYNET.md](SKYNET.md). This document points at those rather than repeating them.

## The root crontab

The installed root crontab lives at `/var/spool/cron/crontabs/root`. Its master copy is `aegir/tools/system/cron/crontabs/root`, copied into place on every install/upgrade. Do not hand-edit the installed file — its own header says so, and the next upgrade overwrites it. Per-box additions go in `/var/xdrago/cron/custom.txt`, which BOA appends after the copy.

| Cmd | Cadence | Role |
|---|---|---|
| `second.sh` | every minute (self-loops ×10) | Load sampling + auto-pause + heavy watchdog/scanner fan-out |
| `minute.sh` | every minute (self-loops) | Service auto-healing watchdog fan-out (nginx, php, mysql, …) |
| `guest-fire.sh` | every minute | Apply temporary csf web bans (see [SECURITY.md](SECURITY.md)) |
| `runner.sh` | every minute (`nice -n5 ionice -c2 -n7`) | Drain the Aegir hosting task queue (`/var/xdrago/run-*`) |
| `ip_access.sh` | every 2 min | Maintain per-site IP access rules (see [IP-ACCESS.md](IP-ACCESS.md)) |
| `ai_policy.sh` | every 2 min | Apply the AI-crawler policy (see [AI-POLICY.md](AI-POLICY.md)) |
| `nginx_deny.sh` | every 2 min | Regenerate the nginx ban geo from csf state (see [SECURITY.md](SECURITY.md)) |
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
| `daily.sh` | 04:15 daily | Daily maintenance (control-file migration, cleanup, version bumps) |

The per-minute monitors (`second.sh`, `minute.sh`, `guest-fire.sh`, `runner.sh`) are the live self-healing core. The 2-minute and longer jobs are slower-changing maintenance. The daily/backup block is out of scope here.

## Where the pieces live

The repo source under `aegir/tools/system/` is deployed verbatim to `/var/xdrago/` on the box (`cp -af .../aegir/tools/system/* /var/xdrago/`). So a file the source tree calls `aegir/tools/system/minute.sh` is `/var/xdrago/minute.sh` at runtime. The single-shot monitors live one level down in `/var/xdrago/monitor/check/`. `loadreport` is the exception — it is deployed to `/opt/local/bin/loadreport` with a `/usr/local/bin/loadreport` symlink, like `fpmreport`.

| Launcher (repo → box) | What it drives |
|---|---|
| `aegir/tools/system/minute.sh` → `/var/xdrago/minute.sh` | Per-pass fan-out of the per-service watchdogs (`monitor/check/{system,unbound,valkey/redis,mysql,php,fpm_tune,nginx,nginx_guard,java}.sh`) |
| `aegir/tools/system/second.sh` → `/var/xdrago/second.sh` | Load sampling / auto-pause, the `_proc_control` service guards, the `hackcheck`/`hackftp`/`escapecheck` scanners |
| `aegir/tools/system/runner.sh` → `/var/xdrago/runner.sh` | Drains the `/var/xdrago/run-*` Aegir hosting tasks, gated by load and queue state |
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

`minute.sh` runs `_launch_auto_healing` once per pass, which `nohup`-spawns each per-service watchdog concurrently. Each checks one service and, if it finds it down, stuck, or misconfigured, repairs it in place. The Valkey/Redis choice is made by an init-script probe: `valkey.sh` runs if `/etc/init.d/valkey-server` exists, else `redis.sh` if `/etc/init.d/redis-server` exists. `fpm_tune.sh` runs only if its file is present.

| Watchdog | Guards | Action |
|---|---|---|
| `system.sh` | OS-level health: SSHD, postfix, rsyslog, cron duplicates, LFD, FTPS (pure-ftpd), vnstat, gpg-agent / dirmngr pile-ups, ClamAV, DHCP lease, and system OOM | Restarts/starts the down service; on ≤5% free RAM does the full OOM cascade (below); culls runaway `wkhtmltopdf` between 5–10% free; forces logrotate; rebuilds DHCP allow rules in `csf.allow`; drops page cache when used RAM > 90%; cooldown-gated per service |
| `unbound.sh` | Local DNS resolver: process + PID liveness, a live `host files.boa.io` lookup against `127.0.0.1`, duplicate masters, `/etc/resolv.conf` sanity | Restarts unbound (cooldown-gated); rewrites a BOA-tagged `/etc/resolv.conf` |
| `valkey.sh` | Valkey cache: process + socket `PING` (auth or `NOAUTH`), `Address already in use`, sustained `RedisException: Connection refused` and PhpRedis slowlog hits | Restart on failed double-check (cooldown-gated); cold restart wipes `/var/lib/valkey/*`; reloads all PHP-FPM on REFUSED/SLOW; honors a site-requested `run-valkey-restart.pid` on qualifying plans |
| `redis.sh` | Same logic for the legacy Redis build (`/etc/init.d/redis-server`) | Same: PING-verified restart, `/var/lib/redis/*` wipe on cold restart, FPM reload on REFUSED/SLOW, plan-gated `run-redis-restart.pid` |
| `mysql.sh` | Percona MySQL: master + `mysqld.sock`/`mysqld.pid` liveness, `Too many connections` floods, high-load × thread-count, runaway per-user queries, stuck `mydumper` | Restart via `move_sql.sh` when down or wedged; kills queries past TTL; `flush-hosts`; restarts only when 1-min load > `_LOAD_THRESHOLD` (33.0) **and** threads > `_THREAD_THRESHOLD` (99); spawns `sqlcheck.sh` |
| `php.sh` | PHP-FPM (all installed versions, `56`–`85`): master + `wwwNN.fpm.socket` + PID liveness, duplicate masters, `already listen on` / `Address already in use` conflicts, `process.max` capacity, giant logs, oversized `fastcgi_temp` | Per-version restart on a sustained, double-checked failure (cooldown-gated); cleans `fastcgi_temp`; honors the plan-gated `run-php-fpm-reload.pid` APCu-clear sentinel; spawns `segfault_alert.pl` (unless `/root/.high_traffic.cnf` or `/root/.giant_traffic.cnf` is set) |
| `fpm_tune.sh` | *Read-only* FPM sampler — no restart, no config change | Self-throttles to ~5 min and appends one JSONL record per pool/version to `/var/log/boa/fpm-tune/<date>.jsonl` (the data `fpmreport` reads); self-installs `libfcgi-bin` if missing, rate-limited |
| `nginx.sh` | Nginx: master + `/run/nginx.pid` liveness, multiple masters, zombie/stopped master/worker states, `Cannot allocate memory` (OOM), `Address already in use` | Full kill + `service nginx restart` (rotating `error.log`) on any anomaly, cooldown-gated; honors plan-gated `run-nginx-restart.pid` |
| `nginx_guard.sh` | A keep-warm helper: that the nginx **access log** is being written at all | Reloads nginx if `access.log` is missing/empty, then loops `scan_nginx.sh` 10× (5 s apart) — this is the launcher that drives the [SECURITY.md](SECURITY.md) abuse scanner on the minute tick |
| `java.sh` | JVM services: Jenkins, Solr 9 / Solr 7 / Solr 4 (Jetty 9), and Jetty `Address already in use` | Restarts the down/stale-PID service (cleaning its `/tmp` scratch and rotating logs); skips entirely while a BOA/Octopus run is in progress |

A few load-bearing details worth calling out:

- **The OOM cascade in `system.sh` is the heaviest action in the set.** At ≤5% free RAM (computed from `free -mt`, not `MemAvailable`) it kills `wkhtmltopdf`, PHP CLI, nginx, PHP-FPM, Java, the cache server (wiping `/var/lib/valkey` or `/var/lib/redis`) and New Relic, then restarts Percona via `move_sql.sh` — a deliberate hard reset for a box seconds from a kernel OOM-kill. Between 5% and 10% free it only culls runaway `wkhtmltopdf` (more than 2 instances). The threshold is low on purpose: the cascade is disruptive and must fire only in a genuine emergency.
- **`mysql.sh` requires *both* high load and a high thread count** before it restarts Percona (`_LOAD_THRESHOLD` 33.0 *and* `_THREAD_THRESHOLD` 99). Either alone is normal under bursty traffic; the conjunction is what distinguishes a wedged server from a busy one. A needless MySQL restart is itself an outage, so the defaults are conservative.
- **`fpm_tune.sh` never tunes anything live.** It is purely the data collector for FPM capacity sizing; the JSONL it writes is consumed by `fpmreport`.
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

Three patterns recur across the watchdogs:

1. **Double-check before acting.** Almost every restart path re-reads the symptom after a short `sleep` (2–5 s) and acts only if it persists. This filters out the transient flap — a socket mid-reload, a log line from a restart that already happened — that would otherwise trigger a needless restart.
2. **Per-service cooldown stamp.** A restart writes `date +%s` to a `/run/<service>-monitor.cooldown` (or per-version `/run/phpNN-fpm.cooldown`) file. A subsequent failure within the cooldown window (default 30 s) logs a skip instead of restarting again, breaking restart storms when a service is crash-looping for a reason a restart cannot fix. Overridable per service: `_UNBOUND_COOLDOWN_SECS`, `_VALKEY_COOLDOWN_SECS`, `_REDIS_COOLDOWN_SECS`, `_FPM_COOLDOWN_SECS`, `_NGINX_COOLDOWN_SECS`, and `_CRON_/_POSTFIX_/_LFD_COOLDOWN_SECS` (in `system.sh`).
3. **Load and run gating.** Most watchdogs stand down while `/run/max_load.pid` or `/run/critical_load.pid` exists (the box is already shedding work — see Load control below), during a BOA run (`/run/boa_run.pid`), and while another auto-heal of the same service is mid-flight (`/run/boa_<service>_auto_healing.pid`).

### Email reporting

When a watchdog takes a corrective action it appends to `/var/log/boa/<service>.incident.log` and may e-mail `_MY_EMAIL`, gated by `_INCIDENT_REPORT` (from `/root/.barracuda.cnf`). The **send threshold differs by watchdog**: in the per-service watchdogs (`unbound.sh`, `valkey.sh`/`redis.sh`, `php.sh`, `nginx.sh`, `java.sh`) the e-mail is sent **only when `_INCIDENT_REPORT` is `ALL`** — their lower settings still log but mail nothing. `mysql.sh` sends on anything other than `OFF`. Only `system.sh` implements the full `OFF` / `CRIT` (= ALERT-only) / `ALL` ladder. In every case the corrective action and the `.incident.log` entry happen regardless of the e-mail setting. Reporting is additionally suppressed during the post-boot uptime grace period (see Load control), so a reboot does not spray "service was down, restarted" mail while the stack is still coming up.

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
| `_CPU_MAX_RATIO` | `4.1` | 410% | MAX | Pause nginx + PHP-FPM |
| `_CPU_CRIT_RATIO` | `6.1` | 610% | CRIT | Kill long procs, then pause web |

The defaults are deliberately **well above 100%**. A BOA box is expected to run its cores hot under normal traffic; auto-pause is a last resort for genuinely pathological load, not a load balancer. On a 2-core box, SPIDER trips when the 1-minute load average reaches ~4.2, MAX at ~8.2, CRIT at ~12.2. All four are overridable in `/root/.barracuda.cnf` and are sanitised on load (anything but digits and a decimal point is stripped), so a malformed override falls back to the built-in default rather than breaking the arithmetic.

The `TASK` ratio (`3.1`) is consumed by the task-queue runner (below), not by the web-pause ladder. The three tiers `_load_control` itself acts on are SPIDER, MAX and CRIT.

### The escalation ladder

`_load_control` is a single `if/elif` chain evaluated highest-tier first, so only one action fires per pass. Crucially, **every tier is re-verified after a `sleep 9` cooldown** before it acts: a one-off spike that has already passed by the time the cooldown elapses is ignored. Only *sustained* load triggers a response.

```
measure _O_LOAD (1m) and _F_LOAD (5m), per-CPU %
  │
  ▼  CRIT — _O_LOAD or _F_LOAD > 610%?
  │    yes ─► sleep 9, re-check ─► still high:
  │            _terminate_processes  (killall -9 php drush.php wget curl)
  │            then _hold_services   (stop nginx + php-fpm)
  │            touch /run/critical_load.pid
  ▼  MAX — _O_LOAD or _F_LOAD > 410%?
  │    yes ─► sleep 9, re-check ─► still high:
  │            _hold_services        (stop nginx + php-fpm)
  │            touch /run/max_load.pid
  ▼  SPIDER — load > 210% and ≤ 410%?
  │    yes ─► sleep 9, re-check ─► still high:
  │            _nginx_high_load_on   (enable nginx_high_load.conf, block crawlers)
  │            touch /run/spider_load.pid
  ▼  NORMAL — touch /run/normal_load.pid
            if spider protection on and both loads ≤ 210%: _nginx_high_load_off
```

- **SPIDER — block crawlers.** When per-CPU load sits above 210% but at or below 410% (checked on both the 1-minute and 5-minute figures), `_nginx_high_load_on` renames `/data/conf/nginx_high_load_off.conf` to `/data/conf/nginx_high_load.conf` and reloads nginx. That file is glob-included by `aegir/conf/nginx/nginx_compact_include.conf` (`include /data/conf/nginx_high_load.c*;`), so swapping the suffix toggles crawler blocking without rewriting any vhost. The web stack stays fully up for real users; only spiders are shed. This is the only tier that does **not** set `_skip_proc_control`, so the heavy fan-out still runs on its normal cadence.
- **MAX — pause the web stack.** Above 410%, `_hold_services` stops the entire web tier: `service nginx stop`, then `force-quit` on every installed `php<NN>-fpm`, then a belt-and-braces `killall php-fpm` and `killall nginx`. The box stops serving so the run queue can drain. An `ALERT`-level incident is logged and (subject to policy) e-mailed.
- **CRIT — terminate runaways, then pause.** Above 610%, `_terminate_processes` runs **first** (`killall -9 php drush.php wget curl`) — a stuck PHP request, a Drush job in a loop, a wget/curl pulling something huge — *before* `_hold_services` pauses the web tier. Killing the runaway first is what lets the box recover instead of immediately re-spiking after the pause.
- **NORMAL — recovery.** When load is at or below the spider threshold on **both** figures, the box is marked healthy and, if spider protection is on, `_nginx_high_load_off` reverts the file and reloads. Recovery is automatic — there is no manual un-pause. (`_hold_services` *stops* services rather than disabling them, so the next normal pass / service watchdog brings nginx and PHP-FPM back; the spider config is the only piece `_load_control` explicitly reverts.)

### State files in /run

Each pass writes exactly one tier marker under `/run` and removes the other three, so the current posture is always readable from a single existing file. Several service watchdogs read these to decide whether to stand down.

| State file | Meaning |
|---|---|
| `/run/normal_load.pid` | Load within normal parameters |
| `/run/spider_load.pid` | Spider protection active (crawlers blocked) |
| `/run/max_load.pid` | Web stack paused (MAX) |
| `/run/critical_load.pid` | Critical: processes killed + web paused |
| `/run/boa_second_auto_healing.pid` | A pause/heal action is in progress (set by `_hold_services` for its duration, so two overlapping passes can't stack service stops) |

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
| `syslog_legacy` | Restarts a **legacy** syslog daemon (`sysklogd` or `inetutils-syslogd`) when down and its init script is present. rsyslog (the BOA default) is handled by `system.sh`, not here. Skipped while a DHCP client is active so it never collides with `hostname_sync` |
| `bind9` | Restarts `bind9` (`named`) when the daemon is down and `/etc/init.d/bind9` exists |
| `proxysql` | Restarts `proxysql` when down and `/etc/init.d/proxysql` exists |
| `droplet` | Restarts the DigitalOcean `droplet-agent` (serial/web-console access on DO VMs) when down/pidfile missing and `/etc/init.d/droplet-agent` exists |
| `newrelic_daemon` | Restarts the New Relic APM `newrelic-daemon` when down and `/etc/init.d/newrelic-daemon` exists |
| `newrelic_sysmond` | New Relic server monitor (`nrsysmond`), gated by the opt-in flag `/etc/boa/.enable.newrelic.sysmond.cnf`: **restarts** it when the flag is present and the daemon is down, **stops** it when the flag is absent and it is running |
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

## The Aegir task-queue runner (`runner.sh`)

`runner.sh` is a **separate** per-minute cron job, not part of the `second.sh`/`minute.sh` fan-out. It drains the Aegir verify/migrate/backup task queue by executing the `/var/xdrago/run-*` runners. It is heavily gated so it never adds load on a box that should stay quiet:

- **Hard stops first.** It exits immediately if `/root/.proxy.cnf`, `/etc/boa/.pause_tasks_maint.cnf`, or a `max_load`/`critical_load` pid is present; and again if too many `runner.sh` instances are already running, or a SQL backup, `daily.sh`, a MySQL restart/cluster-backup, or `boa_cron_wait.pid` is in flight.
- **Load-gated per runner.** `_runner_action` runs a `/var/xdrago/run-*` runner only while the 1-minute per-CPU load is **below `_CPU_TASK_RATIO * 100`** (default 310%); above that it waits. This is the same task ratio used by the load-control logic — backend tasks are skipped under load while the web tier stays up.
- **CI hosts (`/etc/boa/.look.like.jenkins.cnf`).** No automatic queue by default. It runs only if the box is a PRO plan (`POWER`/`PHANTOM`/`CLUSTER`/`ULTRA`/`MONSTER` in the octopus control file) **or** `/etc/boa/.allow.aegir.queue.cnf` is present, *and* at least one `run-aegir-queue.info` exists.
- **Small boxes auto-throttle.** `runner.sh` itself writes `/root/.slow.cron.cnf` and pins it immutable with `chattr +i` when total RAM ≤ 4096 MB. With `.slow.cron.cnf` present (and no `.force.queue.runner.cnf`) it allows only one concurrent runner and runs a single throttled pass per minute with `sleep 15` pads.
- **Fast / forced.** With `/root/.fast.cron.cnf` or `/root/.force.queue.runner.cnf` it runs the queue 10 times in the minute (`sleep 5` between), mirroring the `second.sh` cadence.

> **Disabling the queue does not lower idle load.** Marking a box CI with `.look.like.jenkins.cnf` stops `runner.sh` draining the Aegir queue, but it does **not** by itself remove the idle CPU cost — that comes from the `second.sh`/`minute.sh` monitor fan-out, a *separate* set of cron jobs. (Marking CI does also push `second.sh`/`minute.sh` into the CI box-class, which is the lever that actually quiets the fan-out — see below.)

## Cron cadence and the idle-load throttle

The responsiveness of the fan-out has a cost: on a small or idle box the fan-out itself is the dominant load source (the load 3–4 explained above). Before 2026-06-22, the two "small box" control files (`/root/.slow.cron.cnf`, `/etc/boa/.look.like.jenkins.cnf`) were honoured **only by the task-queue path** — `second.sh` and `minute.sh` ran the full NORMAL cadence on a tiny CI box exactly as on a 192 GB production host. The box-class throttle closes that gap, leaving NORMAL production hosts byte-for-byte unchanged.

### `_monitor_box_class`: CI / SLOW / NORMAL

Both loops classify the box once at startup with an identical `_monitor_box_class` function, resolving to one of three classes with this exact precedence:

| Order | Condition | Class |
|---|---|---|
| 1 | `/etc/boa/.look.like.jenkins.cnf` exists | **CI** |
| 2 | `/root/.fast.cron.cnf` **or** `/root/.force.queue.runner.cnf` exists | **NORMAL** (explicit "full speed" override) |
| 3 | `/root/.slow.cron.cnf` exists **or** total RAM ≤ 4096 MB (from `free -m`) | **SLOW** |
| 4 | none of the above | **NORMAL** (default) |

The order matters: a CI box is CI even if it is also small; an explicit `.fast.cron.cnf` / `.force.queue.runner.cnf` wins over the RAM heuristic so an operator can force full cadence on a small box; otherwise the ≤ 4 GB RAM check classifies the box SLOW even if `runner.sh` has not yet written `.slow.cron.cnf`. Because `runner.sh` auto-creates that immutable marker on ≤ 4 GB boxes, most small hosts hit condition 3 by either branch.

### Per-class cadence

The two loops throttle different things. `minute.sh` reduces both the **number of passes** and the **sleep** between them. `second.sh` keeps its responsive 10×/5 s load-sampling loop intact — load sampling is cheap and auto-pause must stay timely — and gates only the **heavy fan-out** (`_proc_control` plus the three scanners) to run every Nth pass.

| Box class | `minute.sh` fan-out | `second.sh` heavy fan-out | How detected |
|---|---|---|---|
| **NORMAL** | 9 passes, `sleep 5` (~72 spawns/min) | every pass (`_HEAVY_EVERY=1`, 10×/min) | default, or `.fast.cron.cnf` / `.force.queue.runner.cnf` |
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
- **Helper forks roll up to the launcher.** `pgrep`, `awk`, `bc`, `sleep` and friends are attributed to the BOA launcher that spawned them by walking the `/proc` parent chain (depth-bounded). The walk stops at a known launcher or at `cron`; anything past that is `(non-cron)`. The recognised launchers are `second.sh`, `minute.sh`, `runner.sh`, `guest-fire.sh`, `guest-water.sh`, `daily.sh`, `clear.sh`, `ip_access.sh`, `ai_policy.sh`, `nginx_deny.sh`, `migration_proxy_realip.sh`, `cloudflare_realip.sh`, `manage_ltd_users.sh`, `manage_solr_config.sh`, `purge_binlogs.sh`, `mysql_cleanup.sh`, `graceful.sh`.
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

The `nice -n10` / `ionice -c3` (idle I/O class) keeps it off the back of real work. The `--log` path **skips proxy nodes** (exits 0 if `/root/.proxy.cnf` exists), runs a normal live profile, appends the JSON object as one line to `${_LOADPROF_DATA}/YYYY-MM-DD.jsonl` (one file per day), and **prunes** `*.jsonl` older than `_LOADPROF_KEEP_DAYS` (default 14). Read the history back with `--data`, which averages CPU seconds per command across the retained records and tracks peak concurrent RSS.

### Reading the output

The example below is illustrative (constructed from the `printf` formats, not captured from a real box). It shows the shape of a quiet 2-core box where the monitor fan-out, not site traffic, is the load:

```
loadreport — BOA recurring-script resource profile
  host  ng019   span 60s   interval 1s   cores 2   HZ 100
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

`second.sh`, `minute.sh` and `loadreport` are serial-gated in `BOA.sh.txt`, so a box re-fetches the new copy when the serial changes (serials count **down**: a bump is a decrement). Any change to one of these scripts must decrement its `fNN` in `BOA.sh.txt` in the same commit. Current serials: `minute.sh` `f89`, `second.sh` `f97`, `loadreport` `f01`. `loadreport` is fetched to `/opt/local/bin/loadreport`, symlinked to `/usr/local/bin/loadreport`, and `chmod 700`.

## Verify

```bash
# live load posture
ls -1 /run/*_load.pid 2>/dev/null
tail -n 20 /var/log/boa/high.load.incident.log

# which box class this host resolves to (mirror the classifier)
ls -1 /etc/boa/.look.like.jenkins.cnf /root/.fast.cron.cnf \
      /root/.force.queue.runner.cnf /root/.slow.cron.cnf 2>/dev/null
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
