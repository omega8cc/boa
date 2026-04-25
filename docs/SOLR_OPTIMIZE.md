# BOA Solr — Optimization & Maintenance Guide

This document covers Solr performance diagnosis, orphan core cleanup, index
optimization, and configuration tuning for BOA-managed hosting environments.
It is based on real operational experience and consolidates lessons learned
from both typical Drupal search workloads and high-write non-standard use
cases where Drupal is used as an API layer over a large operational dataset.

## Table of Contents

1. [GC Log Interpretation](#1-gc-log-interpretation)
2. [Orphan Core Accumulation](#2-orphan-core-accumulation)
3. [Orphan Core Cleanup — Manual Checks](#3-orphan-core-cleanup--manual-checks)
4. [Backup Archive Inspection & Recovery](#4-backup-archive-inspection--recovery)
5. [Core Health Checks](#5-core-health-checks)
6. [Index Optimization](#6-index-optimization)
7. [High-Write Core Tuning](#7-high-write-core-tuning)
8. [Automated Cleanup — manage_solr_config.sh](#8-automated-cleanup--manage_solr_configsh)
9. [Automated Index Optimization — manage_solr_config.sh](#9-automated-index-optimization--manage_solr_configsh)
10. [solrconfig.xml Reference — High-Write Workloads](#10-solrconfigxml-reference--high-write-workloads)
11. [Cron Maintenance Tasks](#11-cron-maintenance-tasks)

## 1. GC Log Interpretation

### Tailing the log
```bash
tail -f /var/solr7/logs/solr_gc.log
# or for Solr 9:
tail -f /var/solr9/logs/solr_gc.log
```

### Healthy pattern
Young gen (`ParNew`) collections every few minutes, Old gen declining or
stable, CMS cycles infrequent:

```
GC(N)  ParNew: 740K->155K(784K)
GC(N)  CMS: 1156K->1168K(2819K)
GC(N)  Pause Young (Allocation Failure) 1852M->1293M(3519M) 27ms
```

### Warning signs

**Frozen Old gen — the key indicator of orphan core accumulation:**
```
GC(N)  Old: 1642215K->1642215K(2759348K)   ← identical before/after
GC(N)  Old: 1642215K->1642215K(2759348K)   ← every single cycle
```
CMS is cycling every ~2 seconds but freeing nothing. Each loaded Solr core —
even one with an empty or untouched index — holds live heap references: field
caches, segment readers, filter caches, Lucene internal structures. CMS sees
all of these as live objects and cannot reclaim them. The Old gen flatlines
regardless of how many sweep cycles run.

**Resolution:** removing orphan cores releases those references and allows CMS
to resume normal reclamation. In one case, archiving ~260 orphan cores dropped
Old gen by ~480MB within the same hour and ended a continuous 2-second CMS
spin cycle.

**Continuous 2-second CMS spin:**
Normal CMS cycles every several minutes. If cycles are firing every 2 seconds
and the sweep isn't freeing memory, orphan cores are the most likely cause.
Check `/var/solr7/data/ | wc -l` — a healthy server has a small number of
active cores.

**Abortable Preclean running for seconds:**
```
GC(N)  Concurrent Abortable Preclean 6014.616ms
```
Indicates a sudden allocation burst — large indexing job, query spike, or
(more commonly) many per-document commits causing searcher churn. See
[Section 7](#7-high-write-core-tuning).

**Overlapping onDeckSearchers warning in solr.log:**
```
PERFORMANCE WARNING: Overlapping onDeckSearchers=2
```
Searcher instances are being created faster than they can warm and close.
Caused by commits firing too frequently relative to searcher warm time. See
`maxWarmingSearchers` and `autoSoftCommit` tuning in
[Section 9](#9-solrconfigxml-reference--high-write-workloads).

### Post-restart GC behaviour
After a fresh Solr restart on a small number of cores, CMS may appear to
"flood" the log with 2-second cycles. This is normal startup behaviour — CMS
is burning off startup allocation. Verify Old gen is *decreasing*, not frozen:
```
GC(512)  Old: 137,943K → 134,163K   ← dropping
GC(514)  Old: 134,163K → 128,986K   ← still dropping
GC(532)  Old: 136,608K → 123,930K   ← 13MB freed in one sweep
```
If Metaspace is also decreasing after restart, classloader cleanup is working
correctly — not a leak.

## 2. Orphan Core Accumulation

### What causes orphan cores
When a Drupal site is deleted, renamed, or cloned in Aegir, the nginx vhost
and drush alias are removed or updated, but the corresponding Solr core
directory in `/var/solr7/data/` or `/var/solr9/data/` is never automatically
deleted. Over time these accumulate silently. A server with a long history
of staging environments, client migrations, and development clones can
accumulate hundreds of orphan cores.

Each orphan core, even if never queried, consumes:
- Heap (field caches, segment readers loaded on Solr startup)
- File descriptors (open index files)
- CMS mark time (reachable objects that can never be collected)

### Naming convention
BOA creates cores following the pattern `oct.<user>.<domain>`. Legacy formats
include `solr.<user>.<domain>` and bare `<user>.<domain>`. Any directory in
`/var/solr7/data/` not matching an active vhost+alias pair is an orphan
candidate.

### Detecting accumulation
```bash
# Quick count — healthy servers have tens, not hundreds
ls /var/solr7/data/ | wc -l

# Full inventory with index age and size
for d in /var/solr7/data/*/data/index; do
  core=$(echo "$d" | cut -d'/' -f5)
  age=$(( ( $(date +%s) - $(stat -c %Y "$d") ) / 86400 ))
  size=$(du -sh "${d%/data/index}" 2>/dev/null | cut -f1)
  echo "${age}d  ${size}  $core"
done | sort -n
```

## 3. Orphan Core Cleanup — Manual Checks

These commands are used to classify cores before taking action. Run them
before any cleanup to understand what you're dealing with.

### Full audit: age + vhost + alias + disabled state
```bash
for d in /var/solr7/data/oct.*/; do
  core=$(basename "$d")
  user=$(echo "$core" | cut -d'.' -f2)
  domain=$(echo "$core" | cut -d'.' -f3-)
  idx_age=$(( ( $(date +%s) - $(stat -c %Y "${d}data/index") ) / 86400 ))
  vhost="/data/disk/${user}/config/server_master/nginx/vhost.d/${domain}"
  alias_file="/data/disk/${user}/.drush/${domain}.alias.drushrc.php"
  has_vhost=$([ -f "$vhost" ]      && echo YES || echo NO)
  has_alias=$([ -f "$alias_file" ] && echo YES || echo NO)
  disabled=$(grep -l "Do not reveal Aegir front-end URL here" "$vhost" \
    2>/dev/null && echo YES || echo NO)
  echo "${idx_age}d  vhost=${has_vhost}  alias=${has_alias}  disabled=${disabled}  $domain"
done | sort -n
```

### Check vhost enabled/disabled state
```bash
grep "Do not reveal Aegir front-end URL here" \
  /data/disk/<user>/config/server_master/nginx/vhost.d/<domain>
```
Two matching lines = site is disabled/parked.

### Check Aegir alias (provisioning record)
```bash
ls /data/disk/<user>/.drush/<domain>.alias.drushrc.php
```

### Check solr_integration_module per site
A site with `solr_integration_module` explicitly set in `boa_site_control.ini`
is actively managed — its core will be recreated by `manage_solr_config.sh`
if archived. These should not be archived based on index age alone.
```bash
for d in /var/solr7/data/oct.*/; do
  core=$(basename "$d")
  user=$(echo "$core" | cut -d'.' -f2)
  domain=$(echo "$core" | cut -d'.' -f3-)
  idx_age=$(( ( $(date +%s) - $(stat -c %Y "${d}data/index") ) / 86400 ))
  alias_file="/data/disk/${user}/.drush/${domain}.alias.drushrc.php"
  if [ -f "$alias_file" ]; then
    site_path=$(grep "site_path'" "$alias_file" \
      | cut -d: -f2 | awk '{print $3}' | sed "s/[\,']//g")
    ctrl="${site_path}/modules/boa_site_control.ini"
    solr_mod=$([ -f "$ctrl" ] \
      && grep "^solr_integration_module" "$ctrl" 2>/dev/null \
      || echo "not-set")
  else
    solr_mod="no-alias"
  fi
  echo "${idx_age}d  solr=${solr_mod}  $domain"
done | sort -n
```

### Three-tier classification
Before taking action, classify each orphan candidate:

| Tier | Condition | Safe threshold |
|------|-----------|----------------|
| 1 | No vhost, OR vhost with no Aegir alias | 14 days |
| 2 | Vhost + alias present, no `solr_integration_module` | 60 days |
| Protected | `conf/.protected.conf` present, OR `solr_integration_module` set | Never archive automatically |

Staleness is measured on `data/index/` mtime — Lucene only updates this on
actual segment commits. `data/` mtime is unreliable because Solr keeps it
perpetually fresh via tlog and write.lock even on idle cores.

## 4. Backup Archive Inspection & Recovery

Orphan cores are never deleted — they are unloaded from Solr's registry and
moved to `/var/backups/solr7/` or `/var/backups/solr9/` with a timestamp
prefix for easy identification and recovery.

### List archived cores with age and size
```bash
for bkp in /var/backups/solr7/*/  /var/backups/solr9/*/; do
  [ -d "$bkp" ] || continue
  archived_ts=$(basename "$bkp" | cut -d'-' -f1-2)
  core=$(basename "$bkp" | cut -d'-' -f3-)
  size=$(du -sh "$bkp" 2>/dev/null | cut -f1)
  idx_age=""
  if [ -d "${bkp}data/index" ]; then
    idx_mtime=$(stat -c %Y "${bkp}data/index" 2>/dev/null || echo 0)
    idx_age=$(( ( $(date +%s) - idx_mtime ) / 86400 ))d
  fi
  echo "${archived_ts}  idx=${idx_age}  size=${size}  ${core}"
done | sort
```

### Count and total disk usage
```bash
ls /var/backups/solr7/ | wc -l
du -sh /var/backups/solr7/
```

### Recovery procedure

> **Critical:** Use `CREATE`, not `RELOAD`. `RELOAD` only works for cores
> already registered in Solr's registry. An archived core was unloaded before
> being moved, so Solr has no record of it — `CREATE` re-registers the
> existing directory without touching any index files.

```bash
port=9077                        # 9099 for Solr 9
core="oct.o1.example.com"
ts="20260418-222802"             # timestamp prefix from backup dir name
bkp="/var/backups/solr7/${ts}-${core}"
dest="/var/solr7/data/${core}"   # /var/solr9/data/ for Solr 9

mv "${bkp}" "${dest}"
chown -R solr7:solr7 "${dest}"   # solr9:solr9 for Solr 9
curl "http://127.0.0.1:${port}/solr/admin/cores?action=CREATE&name=${core}&instanceDir=${dest}"
```

Successful response:
```json
{"responseHeader":{"status":0,"QTime":300},"core":"oct.o1.example.com"}
```

`status:400 "No such core"` means you used RELOAD instead of CREATE.

## 5. Core Health Checks

### List all registered cores
```bash
curl -s "http://127.0.0.1:9077/solr/admin/cores?action=STATUS&wt=json" \
  | python3 -m json.tool | grep -E '"name"|"instanceDir"|"uptime"'
```

### Check key index metrics per core
```bash
curl -s "http://127.0.0.1:9077/solr/admin/cores?action=STATUS&core=<corename>&wt=json" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
idx=d['status']['<corename>']['index']
print(f'docs:     {idx[\"numDocs\"]:,}')
print(f'maxDoc:   {idx[\"maxDoc\"]:,}')
print(f'deleted:  {idx[\"maxDoc\"]-idx[\"numDocs\"]:,}')
print(f'segments: {idx[\"segmentCount\"]}')
print(f'size:     {idx[\"sizeInBytes\"]/1073741824:.2f} GB')
"
```

### Warning thresholds

| Metric | Warning threshold | Action |
|--------|-------------------|--------|
| Deleted docs | >20% of maxDoc | `expungeDeletes` or optimize |
| Segment count | >50 | Review merge policy |
| Index size | >500MB | Informational — monitor |

### Check cache stats
```bash
curl "http://127.0.0.1:9077/solr/admin/mbeans?cat=CACHE&stats=true"
```

### Reload a registered core's config
```bash
curl "http://127.0.0.1:9077/solr/admin/cores?action=RELOAD&core=<corename>"
```

### Unload a core without deleting files
```bash
curl "http://127.0.0.1:9077/solr/admin/cores?action=UNLOAD&core=<corename>&deleteIndex=false&deleteDataDir=false&deleteInstanceDir=false"
```

## 6. Index Optimization

### When to optimize
- Deleted doc ratio consistently above 20-30%
- Segment count above 50 (indicates merge policy not keeping up)
- After a large bulk delete/reindex operation

### Check facet breakdown of what's indexed
Useful for understanding why doc counts are high on non-standard deployments:
```bash
curl -s "http://127.0.0.1:9077/solr/<corename>/select?q=*:*&rows=0&facet=true&facet.field=ss_type&facet.limit=20&wt=json" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
counts=d['facet_counts']['facet_fields']['ss_type']
pairs=list(zip(counts[::2],counts[1::2]))
for name,count in sorted(pairs,key=lambda x:-x[1]):
    print(f'{count:>12,}  {name}')
"
```

### expungeDeletes — preferred for live indexes
Merges only segments with deleted docs above threshold. Much cheaper than
full optimize — can run during business hours on a live index:
```bash
curl "http://127.0.0.1:9077/solr/<corename>/update?expungeDeletes=true&waitFlush=false"
```

### Full optimize — use with caution
Forces all segments to merge into one. Required when deleted doc ratio is
very high and `expungeDeletes` hasn't been keeping up. On large indexes (10GB+)
this can take 30-120 minutes and will use significant I/O. Run in `screen`.

During the merge, disk usage temporarily doubles as Lucene writes the merged
output alongside the originals — ensure sufficient free space before starting.
The old files are atomically swapped and deleted only when the merge completes.

```bash
screen -S solr-optimize
# waitFlush=false returns immediately but merge continues in background
# For a blocking call that waits for completion:
curl -v "http://127.0.0.1:9077/solr/<corename>/update?optimize=true&maxSegments=1&waitFlush=true&waitSearcher=true"
```

Monitor progress:
```bash
watch -n10 "ls -lht /var/solr7/data/<corename>/data/index/ | head -8 \
  && echo '---' \
  && du -sh /var/solr7/data/<corename>/data/index/"
```

### Expected results after optimize

| Metric | Typical before | Typical after |
|--------|---------------|---------------|
| Deleted docs | 20-35% of maxDoc | ~0% |
| Segment count | 10-20 | 1-3 |
| Index size | 100% | 60-80% (deleted space reclaimed) |

Do not interrupt an in-progress optimize. Lucene writes are atomic — the old
segments are untouched until the merge completes. Interrupting wastes the work
done so far and may leave temporary merge files that need cleanup on restart.

## 7. High-Write Core Tuning

Standard BOA `solrconfig.xml` defaults are designed for typical Drupal content
sites: moderate document counts, periodic indexing, read-heavy query patterns.
Some sites use Drupal as an API layer over large operational datasets (ERP
systems, inventory databases, CRM backends) with very different characteristics:

- Millions of documents (product variants, orders, accounts, stock entries)
- Per-document commits from the application layer at sub-second frequency
- Continuous writes throughout business hours
- High deleted doc accumulation from record updates

These workloads require specific tuning. Apply to the core's `conf/solrconfig.xml`
(which must have `conf/.protected.conf` set to prevent BOA from overwriting it).

### Identifying a high-write core

Signs in `solr.log`:
```
# Per-document commits firing continuously
14:20:57.467  start commit{optimize=false,softCommit=true,...}
14:20:57.487  start commit{optimize=false,softCommit=true,...}
14:20:57.692  start commit{optimize=false,softCommit=true,...}

# Searcher churn from commit frequency
PERFORMANCE WARNING: Overlapping onDeckSearchers=2

# Verbose merge logging (infoStream=true)
Registered new searcher Searcher@45edbdec[corename] main{ExitableDirectoryReader...
  Uninverting(_dsjh0(7.7.3):C8106628/2311351:[diagnostics={source=merge,...
```

Signs in the GC log:
- Old gen steadily climbing between hard commits
- Metaspace growing (classloaders for new searchers accumulating)
- `Pause Young (Allocation Failure)` firing frequently

### Key parameters to change

See [Section 9](#9-solrconfigxml-reference--high-write-workloads) for a
complete reference config. The most impactful changes in priority order:

**1. `ramBufferSizeMB` — increase from 32 to 256**
At 32MB Lucene flushes to disk very frequently, creating many tiny segments
that immediately need merging. 256MB dramatically reduces flush frequency,
segment count, and background merge pressure.

**2. Switch to `TieredMergePolicy`**
The default `LogByteSizeMergePolicy` (mergeFactor=4) does not handle high
deleted doc ratios well. `TieredMergePolicy` with `deletesPctAllowed=20`
actively triggers merges when deleted docs exceed 20% of a segment, keeping
the ratio self-healing without manual optimize calls.

**3. Disable `infoStream`**
`<infoStream>true</infoStream>` logs every merge operation in extreme detail.
On a high-write core this floods `solr.log` with kilobytes of output per
second. Set to `false` in production.

**4. `autoCommit` — add `openSearcher=false`**
When the application issues its own commits, the autoCommit in solrconfig is
just a safety net. Setting `openSearcher=false` means a hard commit no longer
forces a searcher reopen, saving significant overhead on large indexes.

**5. `autoSoftCommit` — remove `maxDocs` trigger**
With per-document commits from the app, a `maxDocs=2000` soft commit trigger
fires constantly. Remove it and use time-only (`maxTime=10000`) which is
correct for near-realtime search on a continuously updated index.

**6. `maxWarmingSearchers` — increase from 2 to 4**
With frequent soft commits, 2 warming searchers is too restrictive and causes
the `Overlapping onDeckSearchers` warnings. 4 provides headroom without
allowing unbounded searcher accumulation.

## 8. Automated Cleanup — manage_solr_config.sh

The `manage_solr_config.sh` script (run every 4 minutes) includes automated
orphan core cleanup with the following behaviour:

### Execution order (important)
Cleanup runs **after** `_check_sites_list`, not before. This prevents a race
condition where a core with a stale index is archived and then immediately
recreated empty by `_add_solr` in the same script execution.

### Throttle
Cleanup runs at most once every 6 hours via a sentinel file at
`/var/backups/solr/.orphan_cleanup_last_run.pid`.

### Classification logic
1. Build active core sets from current vhosts, drush aliases, and
   `boa_site_control.ini` files
2. For each core on disk, determine tier (see table in Section 3)
3. Check `conf/.protected.conf` — always skip if present
4. Check `solr_integration_module` — always skip if set (core is actively
   managed and would be recreated if archived)
5. Apply staleness check on `data/index/` mtime with tier-appropriate threshold
6. Archive (unload + mv) if all gates pass

### Reading the cleanup log
```bash
# Most recent log
cat /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)

# Orphan decisions only
grep -E "^ORPHAN-" /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)

# Summary line
grep -E "Orphan cleanup port|Active cores|=== Orphan" \
  /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)
```

### Log line reference

| Prefix | Meaning |
|--------|---------|
| `ORPHAN-FRESH` | No qualifying match but index too recent — kept with age shown |
| `ORPHAN-SKIP` | Protected by `.protected.conf` or `solr_integration_module` |
| `ORPHAN-CANDIDATE` | Passed all gates — being archived |
| `ORPHAN-ARCHIVED` | Successfully moved to backup dir |
| `ORPHAN-ERROR` | `mv` failed — core left in place |

### Staleness thresholds

| Variable | Default | Applies to |
|----------|---------|------------|
| `_ORPHAN_STALE_DAYS` | 14 | Tier 1: no vhost, or vhost with no Aegir alias |
| `_ORPHAN_VHOST_STALE_DAYS` | 60 | Tier 2: vhost + alias present |

### Health check
After each cleanup run the script queries the Solr STATUS API and logs:
- `HEALTH-INFO: N cores registered`
- `HEALTH-INIT-FAIL` — core failed to load (classloader held, index broken)
- `HEALTH-WARN ... high segment count=N` — merge policy not keeping up
- `HEALTH-WARN ... deleted=N/M (X%)` — unmerged deletes above 20%
- `HEALTH-WARN ... large index=NMB` — informational, >500MB

## 9. Automated Index Optimization — manage_solr_config.sh

The `manage_solr_config.sh` script includes automated index optimization that
runs after the health check on every invocation, throttled by a sentinel file.

### Execution order in _start_up
```
_check_sites_list → _cleanup_orphan_cores → _check_solr_core_health → _run_optimize_if_due
```
Optimization runs last — after cleanup has removed orphans (no point
optimizing a core about to be archived) and after the health check has logged
the current state for before/after comparison in the log.

### Throttle
Runs at most once every `_OPTIMIZE_INTERVAL_HOURS` hours (default 12) via a
sentinel file at `/var/backups/solr/.optimize_last_run.pid`. Independent of
the orphan cleanup sentinel.

### Thresholds
Three constants at the top of the new block, easy to adjust:

| Variable | Default | Meaning |
|----------|---------|---------|
| `_OPTIMIZE_DEL_PCT_THRESHOLD` | 20 | Deleted doc % that triggers `expungeDeletes` |
| `_OPTIMIZE_FULL_THRESHOLD` | 30 | Deleted doc % that triggers full optimize |
| `_OPTIMIZE_INTERVAL_HOURS` | 12 | Minimum hours between runs |

### Decision logic per core

| Deleted % | Protected core (`.protected.conf`) | Unprotected core |
|-----------|-----------------------------------|-----------------|
| < 20% | skip | skip |
| 20–30% | `expungeDeletes` | `expungeDeletes` |
| > 30% | `expungeDeletes` only | full optimize |

**Why protected cores never get a full optimize:**
Protected cores have custom `solrconfig.xml`, likely including `TieredMergePolicy`
with `deletesPctAllowed` already tuned for their workload. Forcing
`maxSegments=1` on top of that would fight the policy. `expungeDeletes` is
safe because it works within whatever merge policy is configured.

### waitFlush=false
All curl calls return immediately while Solr continues merging in the
background. This keeps the script's runtime bounded regardless of index
size — a 28GB optimize running in the background will not block the next
4-minute script invocation.

### Reading the optimize log
```bash
# All optimize decisions from most recent run
grep -E "^OPTIMIZE-" /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)

# Summary header line
grep "=== Index optimize" /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)
```

### Log line reference

| Prefix | Meaning |
|--------|---------|
| `OPTIMIZE-OK` | Deleted ratio below threshold — no action |
| `OPTIMIZE-EXPUNGE` | `expungeDeletes` triggered (ratio ≥ 20%) |
| `OPTIMIZE-FULL` | Full optimize triggered (ratio ≥ 30%, unprotected) |
| `OPTIMIZE-SKIP` | `python3` not available |
| `OPTIMIZE-ERROR` | No response from Solr API |

### Verifying a background optimize completed
After the script triggers a full optimize with `waitFlush=false`, verify
completion in the next run's health check output, or manually:
```bash
core="oct.o1.example.com"
curl -s "http://127.0.0.1:9077/solr/admin/cores?action=STATUS&core=${core}&wt=json" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
idx=d['status']['${core}']['index']
print(f'docs:     {idx[\"numDocs\"]:,}')
print(f'deleted:  {idx[\"maxDoc\"]-idx[\"numDocs\"]:,}')
print(f'segments: {idx[\"segmentCount\"]}')
print(f'size:     {idx[\"sizeInBytes\"]/1073741824:.2f} GB')
"
```
A completed full optimize shows `deleted: 0` and `segments: 1` (plus a few
tiny segments for documents written since the merge started).

## 10. solrconfig.xml Reference — High-Write Workloads

Complete configuration for cores serving high-write operational datasets.
Apply to `conf/solrconfig.xml` after setting `conf/.protected.conf` to prevent
BOA from overwriting with standard defaults.

Changes from BOA standard defaults are annotated inline. All other settings
are unchanged from the standard `drupal-4.4-solr-7.x` config.

```xml
<indexConfig>
  <!-- Increased from 32MB: larger buffer = fewer flushes = fewer small
       segments = less merge work. Most impactful single change for
       high-write workloads. -->
  <ramBufferSizeMB>256</ramBufferSizeMB>

  <!-- Switched from LogByteSizeMergePolicy (mergeFactor=4).
       TieredMergePolicy handles large indexes with high delete ratios
       far better. deletesPctAllowed=20 triggers merges when deleted
       docs exceed 20% of a segment — keeps ratio self-healing. -->
  <mergePolicyFactory class="org.apache.solr.index.TieredMergePolicyFactory">
    <int name="maxMergeAtOnce">10</int>
    <int name="segmentsPerTier">10</int>
    <double name="maxMergedSegmentMB">8192</double>
    <double name="deletesPctAllowed">20</double>
  </mergePolicyFactory>

  <lockType>${solr.lock.type:native}</lockType>
  <reopenReaders>true</reopenReaders>

  <deletionPolicy class="solr.SolrDeletionPolicy">
    <str name="maxCommitsToKeep">1</str>
    <str name="maxOptimizedCommitsToKeep">0</str>
  </deletionPolicy>

  <!-- Changed from true: was logging every merge operation verbatim,
       flooding solr.log on high-write indexes. -->
  <infoStream>false</infoStream>
</indexConfig>

<updateHandler class="solr.DirectUpdateHandler2">
  <autoCommit>
    <maxDocs>${solr.autoCommit.MaxDocs:10000}</maxDocs>
    <!-- Increased from 120000ms: application issues its own commits,
         so this is a safety net only. -->
    <maxTime>${solr.autoCommit.MaxTime:300000}</maxTime>
    <!-- Added: prevents searcher reopen on every hard commit.
         Soft commit below handles search visibility. -->
    <openSearcher>false</openSearcher>
  </autoCommit>

  <autoSoftCommit>
    <!-- maxDocs trigger removed: with per-document commits from app,
         maxDocs=2000 fired constantly causing searcher churn. -->
    <maxTime>${solr.autoSoftCommit.MaxTime:10000}</maxTime>
  </autoSoftCommit>

  <updateLog>
    <str name="dir">${solr.data.dir:}</str>
  </updateLog>
</updateHandler>

<query>
  <!-- ... standard settings ... -->

  <!-- Increased from 2: frequent soft commits exhaust 2 warming
       searchers, causing "Overlapping onDeckSearchers" warnings. -->
  <maxWarmingSearchers>4</maxWarmingSearchers>
</query>
```

### Deploying config changes without restart
```bash
# Back up first
cp /var/solr7/data/<corename>/conf/solrconfig.xml \
   /var/solr7/data/<corename>/conf/solrconfig.xml.bak.$(date +%Y%m%d)

# Copy new config, then reload
cp /path/to/new/solrconfig.xml \
   /var/solr7/data/<corename>/conf/solrconfig.xml

curl "http://127.0.0.1:9077/solr/admin/cores?action=RELOAD&core=<corename>"
```

## 11. Cron Maintenance Tasks

### expungeDeletes and full optimize
These are now handled automatically by `_run_optimize_if_due` in
`manage_solr_config.sh` (see [Section 9](#9-automated-index-optimization--manage_solr_configsh)).
Manual cron jobs for these are no longer needed on servers running the
current version of the script.

For servers not yet running the updated script, a manual monthly job:
```bash
# /etc/cron.d/solr-maintenance — only needed on older script versions
0 3 1 * * root curl -s "http://127.0.0.1:9077/solr/<corename>/update?expungeDeletes=true&waitFlush=false" > /dev/null
```

### Backup archive pruning
Archives accumulate over time. Cores archived more than 90 days ago with
very old indexes are safe to remove permanently:
```bash
# Review before deleting — check idx= age in listing
for bkp in /var/backups/solr7/*/; do
  archived_ts=$(basename "$bkp" | cut -d'-' -f1-2)
  # Convert timestamp to epoch and compare
  archived_epoch=$(date -d "${archived_ts:0:8} ${archived_ts:9:2}:${archived_ts:11:2}:${archived_ts:13:2}" +%s 2>/dev/null || echo 0)
  age_days=$(( ( $(date +%s) - archived_epoch ) / 86400 ))
  [ $age_days -gt 90 ] && echo "${age_days}d  $(du -sh "$bkp" | cut -f1)  $bkp"
done
```

## Appendix: Before/After Reference Case

This table documents the results from a single remediation session on a
production BOA server that had accumulated orphan cores over several years
and hosted one high-write operational Solr core.

| Metric | Before | After |
|--------|--------|-------|
| Cores in `/var/solr7/data/` | 278 | ~15 active |
| Old gen heap (CMS) | 1,642,215K frozen | ~1,150,000K and reclaiming |
| CMS cycle frequency | Every 2 seconds | Normal (every few minutes) |
| GC log pattern | Frozen Old gen, zero reclamation | Normal young-gen collections |
| High-write core size | 28.4 GB | 16.7 GB |
| Deleted docs | 15,924,319 (34%) | 17,217 (0.06%) |
| Segment count | 15 | 8 |
| `solr.log` noise | Continuous merge infoStream | Normal operational logs |
