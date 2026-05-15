# DEBUG: Plugin Discovery Failures, Cache Poisoning, and Intermittent Downtime

**Applies to:** BOA 5.x, Drupal 8/9/10, PHP-FPM + APCu + Redis, Aegir-managed sites


## Background

BOA deliberately configures the following Drupal cache bins to use `cache.backend.chainedfast`:

```php
$settings['cache']['bins']['bootstrap']  = 'cache.backend.chainedfast';
$settings['cache']['bins']['discovery']  = 'cache.backend.chainedfast';
$settings['cache']['bins']['config']     = 'cache.backend.chainedfast';
```

`chainedfast` is a multi-tier backend: it reads from and writes to **APCu first**, then
**Redis**, then falls back to the **database**. This is not a default added lightly. Keeping
these expensive, frequently-read caches in fast memory tiers keeps sites responsive and takes
significant read pressure off the disk and database layer — regardless of storage speed, but
critically important on any deployment where disk I/O is a bottleneck.

**Do not override these defaults without understanding the trade-offs described below.**

The key architectural point is that APCu is process-local: each PHP-FPM worker and any CLI
process maintains its own separate APCu memory segment. **Redis, by contrast, is shared
across all processes** — both PHP-FPM workers and CLI drush processes read from and write to
the same Redis instance. This distinction is central to the failure mode described in Issue 1.

APCu is also enabled for CLI processes:

```ini
apc.enable_cli=1
```


## Issue 1: Recurring plugin discovery errors and intermittent downtime

### Symptoms

- Sites experience intermittent downtime in bursts lasting 2–4 minutes
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

- Errors appear in bursts at regular intervals, then self-resolve
- A full cache clear (e.g. via Aegir's drush-based cache clear) reliably ends the burst

### Working hypothesis: Redis cache poisoning via CLI drush

The regular interval pattern and the self-resolution following a full cache clear point to a
**cache poisoning event in Redis** triggered by a drush CLI process.

When any drush process performs a cache rebuild it executes as a PHP CLI process with its own
local APCu segment. Crucially however, **Redis is shared**: any cache entry drush writes to
Redis is immediately visible to all PHP-FPM workers. If drush writes an incomplete or
partially-rebuilt `discovery` cache entry into Redis during a rebuild operation, FPM workers
will read that poisoned entry and fail to find registered plugins — producing the observed
errors across all concurrent requests until the entry expires or is explicitly flushed.

This is the inverse of the naive APCu split-pool theory (where CLI and FPM are isolated from
each other). With `chainedfast` and Redis in the stack, CLI and FPM *do* share state — and
that shared state can be corrupted by a CLI process mid-rebuild.

The observation that a full cache clear resolves the burst is consistent with this: flushing
Redis removes the poisoned entry, FPM workers fall through to the database, rebuild correctly
within FPM context, and repopulate Redis with a valid entry. Notably, Aegir's own periodic
drush cache clear is a **full flush** rather than a partial rebuild — which is why it
*resolves* rather than *causes* these errors.

### Unknown factors requiring investigation

**This hypothesis is not yet confirmed.** The following must be established before drawing
firm conclusions:

**1. What triggers the cache rebuild?**

The regular interval pattern suggests a scheduled process, but the specific trigger is
unknown. Candidates include:

- Aegir's built-in cron scheduling running drush cron against managed sites
- A custom crontab on the server calling drush cron or drush cache-rebuild directly
- A Drupal cron trigger configured within the site itself (e.g. via Ultimate Cron or similar)
- An external uptime monitoring or scraping service hitting the site on a regular schedule
  and inadvertently triggering a Drupal cron run via `cron.php`
- Another scheduled process with coincidentally regular timing

**2. Does drush execution actually correlate with burst onset?**

Server-side cron logs and Aegir task logs should be checked to confirm whether drush runs
at the observed intervals and whether the timing matches the start of each error burst.

**3. Is Redis receiving a poisoned entry at burst onset?**

Redis keyspace inspection or slow-log analysis around the start of a burst would confirm or
refute the poisoning hypothesis directly.

Until these are established, the recommendations below represent the most likely corrective
actions based on available evidence.

### Recommended actions

**If drush-based cron is confirmed as the trigger:** switch all affected sites to web-based
cron. With web-based cron, execution happens inside a normal PHP-FPM request. Cache writes
to Redis happen from within FPM context, with a fully rebuilt cache, eliminating the
conditions that produce a poisoned entry. Drush-based cron is not recommended on BOA/Aegir
systems. If sites are configured to use it — whether via Aegir's built-in cron scheduling
or a custom crontab — this should be changed.

**If a different trigger is identified:** the nature of that trigger will determine the
appropriate fix. Please report findings so this document can be updated accordingly.

### Incorrect workaround (and why it makes things worse on loaded servers)

A tempting workaround is to force the `discovery` bin to the database backend in
`local.settings.php`:

```php
// Do not apply this on BOA without understanding the consequences
$settings['cache']['bins']['discovery'] = 'cache.backend.database';
```

This does suppress the symptoms by removing `discovery` from the chainedfast stack entirely,
so there is no Redis entry to poison. However, it places every plugin discovery rebuild
directly onto the database and disk, bypassing both APCu and Redis. On a busy server this is
always a performance regression, and on any deployment with slow or HDD-based storage it can
be severely damaging. The BOA default exists precisely to keep this expensive cache in fast
memory. **If applied as a temporary workaround, revert it once the root cause is identified
and resolved.**


## Issue 2: Correct drush usage on BOA

Two drush-related configuration mistakes produce errors that are difficult to diagnose and
are often misattributed to server or cache problems.

### Always use `oN.ftp` under the limited shell, not `oN` under bash

BOA provisions two user accounts per Aegir instance: the main Unix user (`oN`) and the FTP
user (`oN.ftp`). **Always use `oN.ftp` under the limited shell for drush operations.**

The `oN.ftp` limited shell environment is specifically configured to auto-sync the correct
PHP CLI version to match the PHP-FPM version used by each site. When running as `oN` in a
regular bash session there is no such guarantee — drush may execute against a different PHP
version than PHP-FPM, producing unpredictable errors including cache inconsistencies,
serialisation mismatches, and extension availability differences that are easily
misattributed to server or Drupal problems.

### Use site-local drush for Drupal 8 and newer

System drush 8 (the BOA-bundled drush available in PATH) is intended for **Drupal 7 only**.
For any site running Drupal 8 or later, always use the site-local drush installed via
Composer in the site's codebase.

Running system drush 8 against a Drupal 8/9/10 site produces API mismatch errors and
incorrect behaviour that is entirely unrelated to server configuration.

See: https://github.com/omega8cc/boa/blob/5.x-dev/docs/DRUSH-CLI.md


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
hardware. Reducing unnecessary drush-based operations — particularly any drush-based cron
(see Issue 1) — reduces the frequency and severity of high-I/O bursts that contribute to
these errors.

Keeping the BOA chainedfast defaults intact is also directly relevant: these defaults keep
the most frequently read caches in APCu and Redis, out of the disk I/O path entirely.
Reverting them increases database and disk pressure and worsens the conditions under which
these errors occur.


## APCu memory sizing

BOA defaults APCu shared memory to 256M:

```ini
apc.shm_size=256M
```

For servers hosting a large number of Drupal 8/9/10 sites this can be insufficient. Sustained
APCu utilisation above 75% increases eviction pressure: FPM workers more frequently miss in
APCu and fall through to Redis or the database, increasing both Redis load and disk I/O. On
high-utilisation servers the `apc.shm_size` value should be reviewed and increased.

A future BOA improvement under consideration is making `apc.shm_size` dependent on available
server RAM rather than a fixed value, which would address this more systematically across
the platform.


## Open questions (to be resolved per incident)

When investigating a recurrence of Issue 1, the following should be established before
applying fixes:

- [ ] What process triggers the regular cache rebuild — Aegir cron, custom crontab, external
      service, or other?
- [ ] Do server cron logs and Aegir task logs show drush execution correlating with burst onset?
- [ ] Does Redis keyspace inspection show a `discovery` entry written by a CLI process at
      burst onset?
- [ ] Is the interval truly regular (pointing to a scheduler) or only approximately so
      (pointing to traffic-triggered cron)?


## Checklist

For any BOA server experiencing the symptoms described in this document:

- [ ] Identify what triggers the regular cache rebuild (see Open questions above)
- [ ] If drush-based cron is confirmed: switch all affected sites to web-based cron
- [ ] If `local.settings.php` discovery cache override was applied as a workaround: revert
      it once the root cause is resolved
- [ ] Confirm drush operations are run as `oN.ftp` under the limited shell, not as `oN`
      under bash
- [ ] Confirm site-local drush (Composer) is used for all Drupal 8+ sites, not system drush 8
- [ ] Review APCu utilisation; consider increasing `apc.shm_size` if consistently above 75%
