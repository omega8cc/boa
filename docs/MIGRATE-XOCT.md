# xoct — Single-Account BOA Migration

`xoct` migrates one Octopus instance at a time from a source BOA server to a
target BOA server using mydumper/myloader for database export and rsync for
filesystem transfer. Because it operates at the account level it is safe across
differing Percona MySQL versions — no replication constraints apply.

> **Renamed from xboa.** A compatibility symlink `xboa → xoct` is recommended
> so existing scripts continue to work. See [MIGRATE.md](MIGRATE.md).

## When to Use xoct

- Moving selected accounts between servers (not a full-server move).
- Migrating between servers running different Percona versions.
- Renaming an Octopus account username during migration.
- Any scenario where `xmass` (full-server replication) is not appropriate.

For full-server migrations where Percona versions match, consider
[xmass](MIGRATE-XMASS.md) instead — it cuts total downtime significantly.

## Prerequisites

- Both servers running the same BOA release (minor version differences are
  usually fine; major platform gaps are not).
- Root SSH access from source to target (`xmass pre-mig` or manual key
  exchange).
- No existing Octopus instance required on target — `xoct create` provisions it.
- `mydumper` / `myloader` installed on source (standard BOA dependency).
- Disk space on source: at least 1× the account's total database size free
  under `/data/disk/<oct>/src/`.
- CSF on target: source IP whitelisted (see below).

## Terminology

| Placeholder | Meaning |
|---|---|
| `source-host` | Source server FQDN (e.g. `server1.example.com`) |
| `target-host` | Target server FQDN |
| `source-ip` | Source server public IP |
| `target-ip` | Target server public IP |
| `o1` | Source Octopus account name |
| `o2` | Target Octopus account name (only in rename mode) |

## Step-by-Step Procedure

### 1. Prepare Target Firewall

On the **target host** — allow source IP through CSF so rsync and MySQL traffic
can reach the target during migration:

```sh
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.allow
echo "source-ip # Legacy Proxy" >> /etc/csf/csf.ignore
csf -ra
```

### 2. Pre-migration Setup

Run `pre-mig` on **source first**, then on **target**. Each call stops BOA
background runners and handles SSH key exchange so root can SSH freely between
the two hosts.

**On source:**
```sh
xoct pre-mig source-host
```

**On target:**
```sh
xoct pre-mig source-host
```

### 3. Verify SSH Connectivity

**On source:**
```sh
ssh root@target-ip
exit
```

### 4. Enable Read-Only Mode on Source (Recommended)

Preventing writes during the export window reduces the chance of partial data:

**On source:**
```sh
cp -af /data/conf/global/global-extra.inc \
       /data/conf/global/global-extra.inc.bak
echo >> /data/conf/global/global-extra.inc
echo "\$settings['config_readonly'] = TRUE;" \
     >> /data/conf/global/global-extra.inc
echo "\$conf['site_readonly'] = 1;" \
     >> /data/conf/global/global-extra.inc
```

### 5. Clean State and Run Shared Transfer

**On source:**
```sh
rm -f /data/disk/o1/src/*.sql
rm -f /data/disk/o1/log/*.pid
xoct transfer shared target-ip
xoct create o1 target-ip
xoct pretransfer o1 target-ip
```

`transfer shared` syncs `/data/all`, `/data/disk/all`, `/data/disk/arch`,
Solr cores, `/var/www/static`, and `/etc/bind` to the target.

`create o1` provisions a fresh Octopus instance on the target using the source
account's stored metadata (email, subscription, option, cores).

`pretransfer o1` does a first-pass rsync of large data (platforms, files) while
the account is still live — reducing the time the account must be offline during
the actual export window.

### 6. Prepare Target

**On target:**
```sh
service cron stop
chmod 644 /data/all/cpuinfo
# wait ~5 minutes for any in-progress BOA tasks to settle
```

### 7. Export and Transfer

**On source:**
```sh
xoct export o1 target-ip
xoct transfer o1 target-ip
xoct transfer shared target-ip
```

`export` puts a 503 on all sites in the account (`http-off.pid`), purges the
nginx speed cache, dumps the Aegir hostmaster database and each site database
via mydumper, and marks `exported.pid`.

`transfer o1` rsyncs platforms, files, drush aliases, nginx vhosts, SSL certs,
and Let's Encrypt config to the target. The `static/files` transfer uses a
two-pass symlink-safe method (see [Static Files Note](#static-files-symlink-handling)).

A second `transfer shared` picks up any changes to shared data since step 5.

### 8. Import on Target

**On target:**
```sh
ln -sfn $(which websh) /bin/sh
ln -sfn $(which websh) /usr/bin/sh
ls -la /bin/sh   # confirm websh
xoct import o1 target-ip
service nginx reload
xoct post-mig
service cron start
```

`import` re-imports the Aegir hostmaster database, removes any ghost/empty
platform registrations left over from earlier migrations, then calls
`renameaegirhost --aegir-root /data/disk/o1` which:

- Rewrites all drush alias files (old source hostname → target FQDN).
- Rewrites and renames nginx vhost files.
- Dumps the Aegir DB, replaces the source hostname throughout, and re-imports.
- Reloads nginx.
- Runs the Aegir task queue **5 passes** (cc drush + server_master verify +
  server_localhost verify + hosting-dispatch + hosting-tasks) to regenerate
  all aliases, vhosts, and db-host entries from the updated database.

`post-mig` restarts Solr and nginx, restores BOA runner scripts.

### 9. Enable Proxy on Source

**On source:**
```sh
xoct proxy o1 target-ip
service nginx reload
xoct post-mig
```

`proxy o1` converts all nginx vhost files for the account to proxy templates
that forward traffic to `target-ip`, removes `http-off.pid` (sites return to
200 responses, now proxied), and sends the migration-complete notification email
to the account owner.

`post-mig` restores BOA runner scripts on source.

### 10. Update DNS

Update DNS A records for all sites in `o1` to point to `target-ip`. Once DNS
has propagated, traffic flows directly to the target without the proxy hop.
Remove the source CSF whitelist entry added in step 1 after the proxy is no
longer needed.

---

## Optional: Account Rename Mode (o2)

Pass a fourth argument to migrate from account `o1` on source to account `o2`
on target. Use the same `o2` value consistently across all commands:

```sh
xoct create o1 target-ip o2
xoct pretransfer o1 target-ip o2
xoct transfer o1 target-ip o2
xoct import o1 target-ip o2
xoct proxy o1 target-ip o2
```

- `o1` = source account name
- `o2` = target account name (must not already exist before `create`)
- `transfer shared` does not use `o2` — it is not account-specific
- All path references (`/data/disk/o1.ftp`, etc.) are rewritten to `o2`
  automatically during transfer

---

## Static Files Symlink Handling

Some BOA systems store `static/files` as a plain directory; others have it as a
symlink to attached or extra storage. During `xoct transfer`, the tool handles
this safely without using `rsync --copy-links` (which would dereference all
symlinks and break the expected Aegir layout):

1. Syncs `static/` with all symlinks preserved, excluding `static/files`.
2. Resolves the source `static/files` path (whether it is a real directory or a
   symlink target).
3. Creates `static/files` on the target as a real local directory.
4. Syncs the resolved content into that directory separately.

Site-level symlinks (`sites/*/files`, `sites/*/private`) remain symlinks
pointing into the account tree, exactly as BOA/Aegir expects.

The shared archive `/data/disk/arch` is handled the same way during
`xoct transfer shared` (and by `xcopy`/`xmass`): if it has been relocated onto
attached storage with [`migratefs`](MIGRATEFS.md) it is a symlink, so the tool
resolves it (`readlink -f`, arch only — no blanket `--copy-links`) and materializes
its contents as a real `/data/disk/arch` on the target. This keeps the SQL dumps and
cluster backups transferring correctly whether or not `arch` is relocated.

### Verification (Recommended for Large Accounts)

**On target, after import:**
```sh
# static/files must be a real directory, not a symlink
[ -d /data/disk/o1/static/files ] && \
  [ ! -L /data/disk/o1/static/files ] && \
  echo OK_static_files_real_dir

# site-level files/private must remain symlinks
find /data/disk/o1/static/platforms -path '*/sites/*/files'   -type l | head
find /data/disk/o1/static/platforms -path '*/sites/*/private' -type l | head
```

Replace `/data/disk/o1` with `/data/disk/o2` if rename mode was used.

---

## Notes

- **Drupal 6 IP blocking:** for D6 sites that block by IP, whitelist `source-ip`
  at `/admin/user/rules` (Host rule, Allow type) before migration, or flush
  the `{access}` table via Chive afterwards.
- **Idempotency:** most pid-gated steps are safe to repeat after a failed run;
  remove the relevant `*.pid` file under `/data/disk/o1/log/` to force a step
  to re-run.
- **Internal accounts:** xoct no longer hard-excludes accounts by email domain.
  Account eligibility is determined solely by the presence of required log files
  and the absence of `CANCELLED` / already-done pid files.
- **xmass calls xoct:** when `xmass cutover` converts source accounts to proxy
  vhosts, it calls `xoct proxy` internally. No manual invocation is needed in
  that flow.
- **Proxy protocol (HTTP/1.1 to origin):** the proxy vhosts `xoct proxy`
  generates talk **HTTP/1.1** to the origin (`proxy_http_version 1.1`), not
  nginx's default HTTP/1.0, so the origin sees the real request protocol and
  modern semantics (chunked streaming) apply. This is **not migration-only**:
  the same proxy templates back the local LE-enabled proxy that fronts the Ægir
  Hostmaster control panel and Adminer over HTTPS. It also keeps the origin's
  HTTP/1.0 registration-spam guard from false-flagging legitimate proxied access
  — which would otherwise all arrive as HTTP/1.0 at the origin — see
  [ABUSE-GUARD.md](ABUSE-GUARD.md).
