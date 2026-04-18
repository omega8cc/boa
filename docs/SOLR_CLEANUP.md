# BOA Solr Orphan Core Diagnostics & Maintenance

Reference for manual checks developed while building the orphan core cleanup
logic in `manage_solr_config.sh`.  All commands assume Solr 7 on port 9077
at `/var/solr7/data/`; substitute `solr9`, `9099`, `/var/solr9/data/` where
noted.

---

## GC Health

### Tail the GC log live
```bash
tail -f /var/solr7/logs/solr_gc.log
```

Key warning signs in CMS output:
- Old gen frozen: `Old: 1642215K->1642215K` across every cycle — sweep is
  running but freeing nothing; heap is full of live (or orphaned) objects.
- Cycle interval < 2 seconds — GC spinning continuously, burning CPU.
- `Concurrent Abortable Preclean` running for several seconds — allocation
  burst, likely a large indexing job or sudden load spike.

**Frozen Old gen is a strong indicator of orphan core accumulation.**
Each loaded Solr core — even one with an empty or untouched index — holds
live heap references: field caches, segment readers, filter caches, and
internal Lucene structures.  CMS sees all of these as live objects and cannot
reclaim them, so the Old gen flatlines regardless of how many sweep cycles
run.  Removing orphan cores releases those references and allows CMS to
resume normal reclamation.

On vm387 (April 2026): after archiving ~260 orphan cores, Old gen dropped
~480MB within the same hour (`1,642,215K → ~1,150,000K`) and CMS stopped
its continuous 2-second spin cycle, returning to normal young-gen-only
collections.

---

## Core Inventory

### Count all core directories
```bash
ls /var/solr7/data | wc -l
```

### List all cores with index age and size
```bash
for d in /var/solr7/data/*/data/index; do
  core=$(echo "$d" | cut -d'/' -f5)
  age=$(( ( $(date +%s) - $(stat -c %Y "$d") ) / 86400 ))
  echo "${age}d  $core"
done | sort -n
```

### Full audit: age + size + vhost + alias + disabled state
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

### Check vhost enabled/disabled state for a specific domain
```bash
grep "Do not reveal Aegir front-end URL here" \
  /data/disk/o1/config/server_master/nginx/vhost.d/example.com
```
Two matching lines → site is disabled/parked.

### Check whether a domain has a drush alias (Aegir provisioning record)
```bash
ls /data/disk/o1/.drush/example.com.alias.drushrc.php
```

### Check solr_integration_module setting per site
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

---

## Backup Archive Inspection

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

### Count archived cores
```bash
ls /var/backups/solr7/ | wc -l
ls /var/backups/solr9/ | wc -l
```

### Total disk used by archives
```bash
du -sh /var/backups/solr7/
du -sh /var/backups/solr9/
```

---

## Core Recovery

**Important:** use `CREATE`, not `RELOAD`.  `RELOAD` only works for cores
already registered in Solr's registry.  An archived core was unloaded before
being moved, so Solr has no record of it — `CREATE` re-registers the existing
directory without touching any index files.

```bash
port=9077                        # 9099 for solr9
core="oct.o1.example.com"
ts="20260418-222802"             # timestamp prefix from backup dir name
bkp="/var/backups/solr7/${ts}-${core}"
dest="/var/solr7/data/${core}"   # /var/solr9/data/ for solr9

mv "${bkp}" "${dest}"
chown -R solr7:solr7 "${dest}"   # solr9:solr9 for solr9
curl "http://127.0.0.1:${port}/solr/admin/cores?action=CREATE&name=${core}&instanceDir=${dest}"
```

A successful response looks like:
```json
{"responseHeader":{"status":0,"QTime":300},"core":"oct.o1.example.com"}
```

`status:400 "No such core"` means you used RELOAD instead of CREATE.

---

## Live Core API Checks

### List all registered cores and their status
```bash
curl -s "http://127.0.0.1:9077/solr/admin/cores?action=STATUS" \
  | python3 -m json.tool | grep -E '"name"|"instanceDir"|"uptime"'
```

### Check cache stats (filter/query/document cache hit rates)
```bash
curl "http://127.0.0.1:9077/solr/admin/mbeans?cat=CACHE&stats=true"
```

### Reload a registered core's config (after conf/ changes)
```bash
curl "http://127.0.0.1:9077/solr/admin/cores?action=RELOAD&core=oct.o1.example.com"
```

### Unload a core without deleting files (manual pre-archive step)
```bash
curl "http://127.0.0.1:9077/solr/admin/cores?action=UNLOAD&core=oct.o1.example.com&deleteIndex=false&deleteDataDir=false&deleteInstanceDir=false"
```

---

## Cleanup Script Logs

### View most recent run log
```bash
cat /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)
```

### Filter for orphan decisions only
```bash
grep -E "^ORPHAN-" /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)
```

### Summary of last run outcome
```bash
grep -E "Orphan cleanup port|Active cores|=== Orphan" \
  /var/backups/solr/log/$(ls -t /var/backups/solr/log/ | head -1)
```

Log line prefixes produced by `manage_solr_config.sh`:

| Prefix | Meaning |
|---|---|
| `ORPHAN-FRESH` | No vhost/alias match but index too recent — kept |
| `ORPHAN-CANDIDATE` | Passed all gates — being archived |
| `ORPHAN-ARCHIVED` | Successfully moved to backup dir |
| `ORPHAN-ERROR` | `mv` failed — core left in place |

---

## Staleness Thresholds (manage_solr_config.sh)

| Variable | Default | Applies to |
|---|---|---|
| `_ORPHAN_STALE_DAYS` | 14 | Tier 1: no vhost, or vhost with no Aegir alias |
| `_ORPHAN_VHOST_STALE_DAYS` | 60 | Tier 2: vhost + Aegir alias both present |

Staleness is measured on `data/index/` mtime (Lucene segment commits).
`data/` mtime is used only as a fallback — Solr keeps it perpetually fresh
via tlog and write.lock even on idle cores.

A core with `conf/.protected.conf` is never touched regardless of tier or age.
