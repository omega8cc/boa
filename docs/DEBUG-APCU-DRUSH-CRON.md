# DEBUG: Plugin Discovery Failures, Cache Poisoning, and Intermittent Downtime

**Applies to:** BOA 5.x, Drupal 8/9/10, PHP-FPM + APCu + Valkey/Redis, Aegir-managed sites


## Background

BOA deliberately configures the following Drupal cache bins to use `cache.backend.chainedfast`:

```php
$settings['cache']['bins']['bootstrap']  = 'cache.backend.chainedfast';
$settings['cache']['bins']['discovery']  = 'cache.backend.chainedfast';
$settings['cache']['bins']['config']     = 'cache.backend.chainedfast';
```

`chainedfast` is a multi-tier backend: it reads from and writes to **APCu first**, then
**Valkey/Redis**, then falls back to the **database**. This is not a default added lightly.
Keeping these expensive, frequently-read caches in fast memory tiers keeps sites responsive
and takes significant read pressure off the disk and database layer.

**Do not override these defaults without understanding the trade-offs described below.**

The key architectural points are:

- **APCu** is process-local: each PHP-FPM worker and any CLI process maintains its own
  separate APCu memory segment
- **Valkey/Redis** is shared across all processes: both PHP-FPM workers and CLI drush
  processes read from and write to the same instance
- **Both tiers require sufficient memory allocation** for the number of sites hosted —
  starvation at either tier causes cache misses that cascade through the stack

APCu is also enabled for CLI processes:

```ini
apc.enable_cli=1
```


## Diagnostic sequence — start here

When plugin discovery errors appear, **always check Valkey memory and hit rate first**
before investigating other causes. This is the fastest path to diagnosis and the most
common root cause on servers hosting a large number of sites.

```bash
# Check memory ceiling and current usage
valkey-cli -a 'PASSWORD' config get maxmemory
valkey-cli -a 'PASSWORD' info memory | grep -E 'used_memory_human|maxmemory_human|mem_fragmentation_ratio'

# Check hit rate and eviction count
valkey-cli -a 'PASSWORD' info stats | grep -E 'keyspace_hits|keyspace_misses|evicted_keys'
```

**Interpreting results:**

- If `used_memory_human` equals or approaches `maxmemory_human`: Valkey is at its ceiling
- If `evicted_keys` is non-zero and climbing: Valkey is actively evicting cache entries
- If `keyspace_misses` significantly exceeds `keyspace_hits`: cache hit rate is poor

A healthy Valkey instance for a BOA server should have a hit rate above 85-90%. A miss
rate above 50% on a server with many sites almost always indicates `maxmemory` is too low.
**See Issue 1 below.**

If Valkey metrics look healthy, proceed to Issue 2 (Redis/Valkey cache poisoning via CLI
drush) and Issue 3 (disk I/O latency).


## Issue 1: Valkey/Redis memory starvation (confirmed primary cause)

### Symptoms

- Sites experience intermittent downtime in bursts, self-resolving after a few minutes
- Errors in watchdog resembling:

```
Drupal\Component\Plugin\Exception\PluginNotFoundException: The "some_plugin" plugin does not
exist. Valid plugin IDs for Drupal\filter\FilterPluginManager are: ...
```

- Drupal SDC (Single Directory Components) errors of the form:

```
Drupal\Core\Render\Component\Exception\ComponentNotFoundException: Unable to find component
"theme_name:component-name" in the component repository.
```

- Errors consistently involve the **same plugin** across incidents rather than varying
  plugins — this distinguishes starvation from cache poisoning (Issue 2)
- A full cache clear resolves the burst temporarily, but errors recur
- `evicted_keys` counter in Valkey is non-zero and climbing
- Valkey `keyspace_misses` significantly exceeds `keyspace_hits`

### Root cause

Valkey is hard-capped at its `maxmemory` ceiling. When that ceiling is too low for the
number of sites hosted, Valkey is permanently full and continuously evicts cache keys using
the `allkeys-lru` policy to make room for new entries. The `discovery` cache bin — which
holds plugin registration data for all modules on a site — is among the entries that get
evicted. When a PHP-FPM worker needs the discovery cache for a site and finds it evicted,
Drupal must rebuild it from the database. Under concurrent traffic, multiple workers
attempting to rebuild simultaneously can produce incomplete entries and plugin-not-found
fatal errors.

A full cache clear resolves the burst because it forces a clean rebuild under quieter
conditions and temporarily repopulates Valkey — until eviction pressure returns.

### BOA default formula and why it may be insufficient

BOA sets Valkey's `maxmemory` using the formula:

```bash
_MAX_MEM_VALKEY=$(( _RAM / 6 ))
```

On a 24GB server this produces a 4GB ceiling. For a server hosting a small number of sites
this is adequate, but for servers hosting 100+ Drupal 8/9/10 sites the working set of
bootstrap, discovery, config, render cache, and dynamic page cache across all sites quickly
exceeds this allocation.

BOA 5.x updates this formula to `_RAM / 3`, doubling the default Valkey allocation. On
servers upgraded to this version the ceiling will be recalculated automatically. On older
installations or servers where the ceiling has been manually set, review and increase as
described below.

### Fix

Increase `maxmemory` to approximately 1/3 of available RAM, ensuring sufficient headroom
remains for MySQL buffer pool, PHP-FPM workers, and the OS:

```bash
# Apply immediately (replace PASSWORD and adjust size as appropriate)
valkey-cli -a 'PASSWORD' config set maxmemory 8gb
valkey-cli -a 'PASSWORD' config rewrite
```

Then monitor evictions and hit rate:

```bash
watch -n 10 'valkey-cli -a PASSWORD info stats | grep -E "keyspace_hits|keyspace_misses|evicted_keys"'
```

Evictions should drop to zero within minutes. Hit rate will remain low while the cache
warms from a cold start — allow 15-30 minutes for the working set to repopulate before
evaluating steady-state hit rate. On a server with many sites full warm-up may take longer.

**Note:** The `config rewrite` command persists the change to `valkey.conf`. Verify that
BOA's nightly maintenance does not override this value on your installation.

### RAM sizing guidance

Valkey starvation on a heavily loaded server is often a symptom of the server being
under-allocated for its workload overall. As a rough guide for BOA servers running Drupal
8/9/10:

| Sites hosted | Recommended minimum RAM |
|-------------|------------------------|
| Up to 50    | 16 GB                  |
| 50–150      | 32 GB                  |
| 150–300     | 48 GB                  |
| 300+        | 64 GB or more          |

These figures assume a typical mix of traffic and module complexity. Servers with
unusually large MySQL datasets, high traffic, or many active FPM workers may require more.

Increasing Valkey `maxmemory` within existing RAM is the fastest mitigation, but if the
server is genuinely under-allocated for its site count, a RAM increase is the only complete
solution.


## Issue 2: Valkey/Redis cache poisoning via CLI drush

This is a secondary hypothesis — **investigate only after confirming Valkey memory and hit
rate are healthy** (see diagnostic sequence above and Issue 1).

### Symptoms

- Sites experience intermittent downtime in bursts lasting 2–4 minutes at regular intervals
- **Different plugins fail across incidents** — not always the same plugin — suggesting a
  cache consistency problem rather than a missing entry
- A full cache clear reliably and immediately ends the burst
- Valkey `evicted_keys` is zero or very low and hit rate is above 85%

### Working hypothesis

When any drush process performs a cache rebuild it executes as a PHP CLI process. Valkey is
shared between CLI and FPM processes. If drush writes an incomplete or partially-rebuilt
`discovery` cache entry into Valkey during a rebuild operation, FPM workers will read that
poisoned entry and fail to find registered plugins — producing errors until the entry
expires or is flushed.

This is distinct from the APCu split-pool scenario: with `chainedfast` and Valkey in the
stack, CLI and FPM do share state, and that shared state can be corrupted mid-rebuild.

Aegir's own periodic drush cache clear is a **full flush** rather than a partial rebuild —
which is why it *resolves* rather than *causes* these errors.

### Investigation

The following must be established before drawing firm conclusions:

**1. What triggers the cache rebuild?**

Candidates include:

- Aegir's built-in cron scheduling running drush cron against managed sites
- A custom crontab calling drush cron or drush cache-rebuild directly
- A Drupal cron trigger configured within the site itself
- An external monitoring service triggering cron via `cron.php` on a regular schedule
- Another scheduled process with coincidentally regular timing

**2. Does drush execution correlate with burst onset?**

Check server-side cron logs and Aegir task logs to confirm whether drush runs at the
observed intervals and whether timing matches the start of each error burst.

**3. Is Valkey receiving a poisoned entry at burst onset?**

Valkey keyspace inspection or slow-log analysis around the start of a burst would confirm
or refute the hypothesis directly.

### Recommended actions

**Disable Drupal core's Automated Cron on all Aegir-managed sites.** Automated Cron fires
on page load with no awareness of server load. Aegir's wget-based cron scheduling staggers
runs across sites to prevent simultaneous bursts and is the only recommended cron method
on BOA.

**If drush-based cron is confirmed as the trigger:** switch all affected sites to Aegir's
wget-based cron. With web-based cron, cache writes to Valkey happen from within FPM context
with a fully rebuilt cache, eliminating the conditions that produce a poisoned entry.

**If wget cron appears to not complete (e.g. Scheduler module not publishing nodes on
schedule):** do not switch to drush cron as a workaround. The likely cause is the cron run
exceeding BOA's default PHP execution time limit of 3 minutes (180 seconds). The correct
fix is to increase the limit via the FPM pool configuration files:

```
/opt/etc/fpm/fpm-pool-common.conf
/opt/etc/fpm/fpm-pool-common-legacy.conf
/opt/etc/fpm/fpm-pool-common-modern.conf
```

The relevant settings are `max_execution_time`, `max_input_time`, and
`default_socket_timeout`. See the last entry in
https://github.com/omega8cc/boa/blob/5.x-dev/docs/FAQ.md for details. These files are
overwritten on every barracuda upgrade and must be reapplied after upgrades. Also
investigate why cron exceeds 3 minutes — this is worth resolving independently.


## Issue 3: Intermittent class-not-found / file-unreadable errors

### Symptoms

- Errors of the form:

```
Drupal\Component\Plugin\Exception\PluginException: Plugin (plugin_id) instance class
"Drupal\some_module\Plugin\SomeType\SomeClass" does not exist.
```

- The referenced `.php` file is confirmed present on disk
- The error self-resolves after a few minutes, or requires a site verify to clear
- No filesystem or mount errors visible at the OS level

### Root cause

On deployments using slow or HDD-based storage hosting a large number of sites, disk I/O
saturation during traffic peaks or cache rebuild bursts can cause file read latency high
enough to produce class autoloader failures. These are not mount failures, filesystem
corruption, or missing files — they are I/O latency spikes under disk pressure. BOA
typically runs on fast NVMe storage where this is not a factor, but any deployment on
rotational or otherwise slow disk is susceptible.

Operations that generate broad filesystem activity exacerbate this: cache rebuilds, drush
operations, and Composer runs are common triggers.

### Mitigation

There is no configuration change that eliminates disk I/O saturation on under-resourced
hardware. Reducing unnecessary drush-based operations — particularly drush-based cron
(see Issue 2) — reduces the frequency and severity of high-I/O bursts.

Keeping the BOA chainedfast defaults intact is directly relevant: these defaults keep the
most frequently read caches in APCu and Valkey, out of the disk I/O path entirely.
Reverting them increases database and disk pressure and worsens the conditions under which
these errors occur.


## Incorrect workaround: forcing discovery to the database backend

A tempting workaround when discovery errors appear is to force the `discovery` bin to the
database backend in `local.settings.php`:

```php
// Do not apply this on BOA without understanding the consequences
$settings['cache']['bins']['discovery'] = 'cache.backend.database';
```

This suppresses the symptoms by removing `discovery` from the chainedfast stack entirely.
However, it places every plugin discovery rebuild directly onto the database and disk,
bypassing both APCu and Valkey. On a busy server this is always a performance regression.
The BOA default exists precisely to keep this expensive cache in fast memory.

**This workaround treats the symptom rather than the cause. Identify and fix the root cause
— most likely Valkey memory starvation (Issue 1) — and revert this override.**


## Issue 4: Correct drush usage on BOA

Two drush-related configuration mistakes produce errors that are difficult to diagnose and
are often misattributed to server or cache problems.

### Always use `oN.ftp` under the limited shell, not `oN` under bash

BOA provisions two user accounts per Aegir instance: the main Unix user (`oN`) and the FTP
user (`oN.ftp`). **Always use `oN.ftp` under the limited shell for drush operations.**

Note that **PHP-CLI and PHP-FPM are two independent systems** in BOA. PHP-FPM version is
controlled via `~/static/control/fpm.info` or `~/static/control/multi-fpm.info` (see
[PHP-FPM.md](PHP-FPM.md)). PHP-CLI version — what drush and Composer use — is controlled
separately via `~/static/control/cli.info` or the instant switch files (e.g. `php83.info`).
These do not automatically sync with each other. You are responsible for configuring the
PHP-CLI version to match your sites' PHP-FPM version using those control files.

What the `oN.ftp` limited shell provides is BOA's **special shell wrapper**, which correctly
reads the PHP-CLI control files and applies them, and makes `vdrush` available. When running
as `oN` in a regular bash session the shell wrapper is not active — the control files are
ignored entirely, drush runs against whatever PHP version happens to be the system default,
and `vdrush` will not work correctly.

See: https://github.com/omega8cc/boa/blob/5.x-dev/docs/DRUSH-CLI.md

### Use site-local drush for Drupal 8 and newer

System drush 8 (the BOA-bundled drush available in PATH) is intended for **Drupal 7 only**.
For any site running Drupal 8 or later, always use the site-local drush installed via
Composer in the site's codebase.

Running system drush 8 against a Drupal 8/9/10 site produces API mismatch errors and
incorrect behaviour that is entirely unrelated to server configuration.

See: https://github.com/omega8cc/boa/blob/5.x-dev/docs/DRUSH-CLI.md


## APCu memory sizing

BOA defaults APCu shared memory to 256M:

```ini
apc.shm_size=256M
```

APCu is the first tier of the chainedfast stack, local to each PHP-FPM worker process.
For servers hosting a large number of Drupal 8/9/10 sites, 256M can be insufficient.
Sustained APCu utilisation above 75% increases per-worker miss rates, causing more
frequent fallthrough to Valkey and the database.

On high-utilisation servers the `apc.shm_size` value should be reviewed and increased —
512M is a reasonable starting point. Note that APCu memory is allocated per-server, not
per-worker, so increasing it has a fixed cost regardless of worker count.

Increasing Valkey `maxmemory` (Issue 1) should be the first priority, as Valkey starvation
has a much larger impact on overall cache performance than APCu sizing. APCu increases
complement but do not substitute for adequate Valkey allocation.


## Checklist

For any BOA server experiencing the symptoms described in this document, follow this order:

- [ ] Check Valkey hit rate and eviction count (see diagnostic sequence above)
- [ ] If evicted_keys is non-zero or hit rate is below 85%: increase Valkey maxmemory
      to approximately _RAM / 3 and monitor for improvement — see Issue 1
- [ ] If RAM is insufficient for the site count: escalate a RAM increase request —
      see RAM sizing guidance in Issue 1
- [ ] Disable Drupal core's Automated Cron on all Aegir-managed sites
- [ ] If drush-based cron is confirmed as a trigger: switch to Aegir's wget-based cron
- [ ] If wget cron is not completing: increase PHP execution time limits via
      fpm-pool-common files rather than switching to drush cron — see FAQ.md
- [ ] If `local.settings.php` discovery cache override was applied as a workaround:
      revert it once the root cause is resolved
- [ ] Confirm drush operations are run as `oN.ftp` under the limited shell, not as `oN`
      under bash; confirm PHP-CLI version control files match sites' PHP-FPM version
- [ ] Confirm site-local drush (Composer) is used for all Drupal 8+ sites
- [ ] Review APCu utilisation; consider increasing `apc.shm_size` if above 75%
