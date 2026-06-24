# PHP-FPM Version Management in BOA

The Ægir version provided by BOA is now fully compatible with PHP 8.5, so it can be used as default version in the Ægir PHP configuration files:
`~/static/control/cli.info` and `~/static/control/fpm.info`

### Global PHP-FPM Version Control

BOA allows you to manage the PHP-FPM version across all sites hosted on an Octopus instance using the `fpm.info` file.

- The `~/static/control/fpm.info` file, if it exists and contains a supported and installed PHP-FPM version, will be used by a system agent running every 1-2 minutes to switch the PHP-FPM version used for all web requests on this Octopus instance.

#### **IMPORTANT**:
- If used, this will switch PHP-FPM for **all** Drupal sites hosted on the instance, unless a `multi-fpm.info` control file also exists.

### Supported Values for Single PHP-FPM Mode:
- 8.5, 8.4, 8.3

#### **NOTE**:
- Only one line and one value (e.g., `8.3`) should be present in this file; otherwise, the system will ignore it.
- If the `fpm.info` file doesn’t exist, the system will create it and set it to the lowest available PHP version installed, not the system default version. This ensures backward compatibility for instances installed before upgrading to BOA-4.1.3 when the default PHP version was 5.6. Without this safeguard, upgrading could break most hosted sites that haven't been tested for PHP 8.1+ compatibility.

---

### Multi-PHP-FPM Support for Sites on Octopus Instance

You can enable multiple PHP versions for different sites using the `multi-fpm.info` file.

- **File Location**: `~/static/control/multi-fpm.info`
- If this file exists, it will override the default `fpm.info` configuration for the sites listed in the `multi-fpm.info` file.

Example of `multi-fpm.info`:
```
foo.com 8.5
bar.com 7.4
old.com 5.6
```

- **NOTE**: Each line in the `multi-fpm.info` file must start with the **main site name** (not an alias), followed by a single space, and then the PHP-FPM version to use.

#### **IMPORTANT**: Supported Drupal core versions and distributions have different PHP versions requirements, while not all PHP versions out of currently supported twelve (12) versions are installed by default. Ensure that you have corresponding PHP versions installed with barracuda before attempting to install older Drupal versions and distributions. On hosted BOA contact your host if you need any legacy PHP installed again.

#### PHP CAVEATS for Drupal core 7-10 versions:

- [Drupal 7 PHP Requirements](https://www.drupal.org/docs/7/system-requirements/php-requirements)
- [Drupal System Requirements](https://www.drupal.org/docs/system-requirements/php-requirements)

#### Please check regularly: [PHP Supported Versions](https://www.php.net/supported-versions.php)

## PHP-FPM Resource Allocation (workers and memory)

Each Octopus instance gets its own PHP-FPM pool per PHP version, shared by all
of that instance's sites running on that version. BOA sizes two limits on every
pool — `pm.max_children` (how many requests it can serve at once) and
`memory_limit` (per-request memory ceiling) — from the instance **plan**
(`_CLIENT_OPTION`) and the box capacity. Pools run in `ondemand` mode, so an
idle version pool spawns no workers and costs almost nothing regardless of its
ceiling.

Plans fall into two classes.

### Shared plans

`POWER`, `BUS`, `EDGE`, `AGAIN`, `SSD`, `CLASSIC`, `MINI`, `MICRO`, `QUIET`,
`HEADSPACE` are packed many to a box, so they keep small, fixed limits:

| Plan | pm.max_children | memory_limit |
|---|---|---|
| `POWER` / `BUS` | 16 | 768 MB |
| `EDGE` / `AGAIN` / `SSD` / `CLASSIC` | 4 | 512 MB |
| `MINI` / `MICRO` / `QUIET` / `HEADSPACE` | 2 | 256 MB |

The worker count is `base × engines × 2`, where *engines* is the instance's
allotted cores (`_CLIENT_CORES`, default 1). The `memory_limit` band is capped
at the box's RAM-scaled ceiling (below), so on a small VM even these values are
reduced. (`QUIET` is the exception that is not doubled — it stays at the
minimum.)

### Dedicated plans

`PHANTOM`, `ULTRA`, `MONSTER`, `CLUSTER` own the box, so BOA ignores the fixed
tier and sizes `pm.max_children` from actual box capacity:

```
pm.max_children = min( _PHP_FPM_RAM_PCT% × total_RAM / ~64 MB ,
                       CPU_cores × _PHP_FPM_CPU_FACTOR )      # floor 8
```

RAM is the primary axis (a PHP worker's measured footprint is roughly 64 MB);
CPU is a sanity cap, since FPM workers are I/O-bound. With the defaults
(50% of RAM, 8 × cores) a 16-core / 62 GB host lands around 128 workers.
Dedicated pools keep the generous box-wide `memory_limit`. The value is
recomputed on every run, so an upgrade never resets it to a fixed tier.

### Tiny VMs

The box-wide PHP `memory_limit` floor scales with installed RAM so small VMs are
not pinned to a 1 GB per-pool ceiling that triggers out-of-memory under load:

| Total RAM | memory_limit floor |
|---|---|
| < 2 GB | 256 MB |
| 2–4 GB | 512 MB |
| ≥ 4 GB | 1024 MB |

Boxes with 4 GB or more are unchanged from the historical behaviour; only
smaller boxes are lowered.

### Control variables

These per-instance overrides live in `/root/.<instance>.octopus.cnf` and all
default to `AUTO` (fully automatic). Set a value only to override:

| Variable | Effect |
|---|---|
| `_PHP_FPM_MAX_CHILDREN_FORCE` | Pin an exact `pm.max_children` (minimum 8) for any plan; never clobbered by an upgrade. |
| `_PHP_FPM_MEMORY_LIMIT_FORCE` | Pin an exact `memory_limit` in MB (minimum 64) for any plan. |
| `_PHP_FPM_RAM_PCT` | Percent of total RAM budgeted for dedicated-plan workers (`AUTO` = 50). |
| `_PHP_FPM_CPU_FACTOR` | Dedicated-plan CPU cap multiplier: `cores × factor` (`AUTO` = 8). |
| `_PHP_FPM_WORKERS` | Explicit worker count for the instance (`AUTO` = plan tier / dynamic calc). |

### Why one busy site can return 502 to its neighbours

All sites on an instance share the per-version pool. When that pool reaches
`pm.max_children`, every site on the instance returns `502` — even idle ones —
because they are all waiting on the same saturated pool. Dedicated plans size
the pool from box capacity to absorb bursts; shared plans are capped on purpose,
so a busy shared tenant is expected to queue at its ceiling.

Raising `pm.max_children` is **not** the cure when the cause is *abusive* — the
attack consumes any ceiling, and a higher one only raises the OOM point. When a
distributed flood of expensive anonymous requests saturates the pool (e.g. a
scraper crawling localized on-the-fly-translation pages, which hold a worker for
tens of seconds each), BOA bounds that request class at the nginx edge so it can
never consume more than a small fixed slice of the shared pool, and trips an
alarm the instant a pool hits its ceiling. See the i18n concurrency guardrail and
the FPM-saturation trigger in [ABUSE-GUARD.md](ABUSE-GUARD.md).

### Inspecting the allocation

`fpmreport` shows, per pool, the `plan`, `eng` (engines), the configured
`cfg_kids` (`pm.max_children`) and `cfg_mem` (`memory_limit`), next to the
observed peak active workers and p95. That lets you confirm a pool's limits
match what its plan should produce. Both `fpmreport` and its sampler
`fpm_tune` are strictly read-only — they change no configuration. See
[MONITOR.md](MONITOR.md) for the wider self-healing monitor stack.
