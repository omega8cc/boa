# BOA Migration Tools

BOA provides three purpose-built tools for migrating Octopus instances and full
server environments between remote hosts. `xoct` and `xmass` are compared below;
`xcopy` is `xoct`'s proxy-less variant — the same per-account (or shared-platform)
migration, without the automatic intermediate DNS proxy.

## Choosing the Right Tool

| | **xoct** | **xmass** |
|---|---|---|
| Scope | Single Octopus account | Full server (all accounts + Solr) |
| Method | mydumper/myloader export→transfer→import | MySQL GTID replication + rsync |
| Percona version match required | No — cross-version safe | Yes — identical versions on both ends |
| Downtime window | Per-account (minutes to hours) | Whole-server cutover (1–3 h typical) |
| Intermediate DNS proxy | Yes (automatic) | Yes (automatic via xoct) |
| Concurrent account migration | No — sequential | Yes — all accounts in one operation |
| Incremental pre-sync | No | Yes — repeat `xmass sync` freely |

**Use xoct when** you need to move individual accounts, rename an account during
migration, or move between servers running different Percona versions.

**Use xmass when** you want to migrate an entire server with minimal total
downtime, especially at large scale (many accounts, large databases, large Solr
indices) where per-account mydumper/myloader cycles would be impractical.

## Shared behaviour across the migration tools

- **Single-flight, per box.** Every state-mutating verb of `xoct`, `xcopy` and
  `xmass` takes an owner-PID lock (`/run/<tool>.verb.pid`) and a second run
  refuses loudly and non-zero, naming the live owner's pid. The guard is
  liveness-based — a killed run or a reboot wedges nothing, and there is no
  stale lock to clear. Read-only verbs (`status`, `verify`, `proxy-mode`)
  stay unlocked so a migration can always be inspected mid-run.
- **The tools force themselves current.** `xmass pre-mig` (both hosts) and
  `prep-target` (the target) drop the per-tool control markers for the
  migration tool set and run the housekeeping fetcher synchronously, logging
  each tool's version — a migration prepared days earlier is never run on
  stale tooling. The tool executing the command refreshes on its next verb,
  not mid-run.
- **Same release on both ends.** `xmass prep-target` compares both boxes' BOA
  release stamps and refuses a migration across releases, with no override
  (see MIGRATE-XMASS.md Prerequisites for the reason and the fix).

## Rename helper: renameaegirhost

`renameaegirhost` handles in-place Ægir hostname rename on a single Ægir root
— the BOA master (`--aegir-root /var/aegir`) or an Octopus account
(`--aegir-root /data/disk/oN`). It is called automatically by xoct (during
`import`) and by xmass (during `cutover`), which pin the old hostname for it —
migrations never need a direct invocation. Run it directly only for an
in-place identity change (renaming a cloned VM, moving a box to a new FQDN) or
to resume a partial rename; inline `--help` describes each step.

Before any in-place rewrite begins, the plain pre-rename database dump is
verified complete — exit status plus the dumper's closing marker — and the
run aborts rather than rewrite the database without a complete backup.

### Pre-flight for an in-place rename

The tool takes the NEW hostname from the system FQDN (`hostname -f`), and on a
BOA box the system identity is cnf-driven: any barracuda run — including an
install's cron-fired final phase — re-asserts `_MY_HOSTN` onto the running
hostname and into `/etc/hostname` and `/etc/mailname` (on DHCP-managed hosts a
background monitor additionally restores the running hostname from
`/etc/hostname` within seconds). A stale cnf therefore reverts the hostname
mid-rename; the observed collateral is provision flipping to remote-host mode
against the old identity (failed self-rsync on missing SSH host keys) and a
regenerated legacy nginx config that fails `nginx -t`. Set the full box
identity BEFORE running the tool on an existing box:

1. `/etc/hostname` — the new FQDN;
2. `/etc/hosts` — the new FQDN resolving to this box;
3. `/etc/mailname` — the new FQDN;
4. `/root/.barracuda.cnf` — `_MY_HOSTN` (and `_MY_FRONT`) matching the new
   FQDN.

The tool warns when `_MY_HOSTN` disagrees with the detected new hostname —
treat that warning as a stop sign, not noise. Migration targets are
unaffected: their fresh install writes the cnf with the final FQDN.

### Re-runs, resume, and --force-old

Re-running the tool is convergent: already-renamed values are guard-skipped,
so a repeat run over a rename completed by the current tooling changes
nothing — including when the new FQDN contains the old one (a
subdomain-augmenting rename). One qualification: a re-run on a box renamed by
EARLIER tooling repairs the per-site surfaces the older rename left behind —
settings.php, the `files`/`private` symlinks, the client symlink, the alias
file and the static store. Every repair stays conditioned on old-name
evidence, so a correct site (including one freshly installed on a migration
target) is untouched and not even queued; on such a box the aliases already
carry the new hostname, so pin the old one with `--force-old`. After a partial
or aborted rename the on-disk aliases may already carry the new hostname,
which defeats old-hostname auto-detection (old == new, silent no-op) — resume
with the old hostname pinned explicitly:

```sh
renameaegirhost --aegir-root /data/disk/o1 --force-old old.example.com
```

`--dry-run` prints every planned change without modifying anything.

### Sites whose name contains the box hostname

A tenant site whose URI embeds the box FQDN follows the box through a
hostname rename. The tool carries, per such site: the site directory itself,
its per-site Drush alias file, its `static/files` store, the site's own
`files`/`private` symlinks into that store, its `clients/<client>/` symlink,
the URI-derived values inside the provision-generated `settings.php`
(public/private/temp file paths, the D10+ config sync directory, the syslog
identity, the absolute `local.settings.php` include, and
`trusted_host_patterns` in **both** its plain and backslash-escaped
spellings — the escaped one is what produces the HTTP 400 when left stale),
and the site's per-site PHP pin row in `static/control/multi-fpm.info`. It
then queues one site verify per renamed site, because the queue's server
verifies regenerate no per-site artefact at all — none of this is
self-healing if left behind.

Two deliberate limits and one refusal:

- The **database name and user are never rewritten**. A `settings.php` that
  carries the old URI on a `database`/`username`/`password`/`db_url` line is
  refused: the run warns, leaves the file untouched, counts it, and the
  summary prints `ATTENTION : N settings.php left untouched`. Rewrite the URI
  values in such a file by hand — never the database name.
- Immediately before the Ægir task queue a **fail-closed gate** aborts the
  run if any site directory still carries the old hostname: the queue would
  import those as brand-new sites, giving each a duplicate panel node — the
  duplicate being the half that owns the data. Resolve the listed directories
  and re-run; under `--dry-run` the gate reports them instead of aborting.

### Confirming the renamed sites serve

The run ends with a serving gate: the tool waits for each renamed site to
actually answer — up to `_RENAME_SERVE_WAIT` seconds per site, default 180 —
accepting 200/301/302 but self-calibrating against the box's catch-all vhost,
so an "Under Construction" 200 for a nonexistent Host never counts as
serving. The closing summary ends with either
`Sites : all N renamed site(s) confirmed serving` or `NOT SERVING : <uris>` —
the run itself still exits 0, so read that line rather than the exit status;
a 400 there is the trusted-host check. The wait exists because `settings.php`
is resolved through PHP's per-worker realpath cache, so a single immediate
check proves nothing in either direction. The gate covers only sites the
rename moved — an account-axis move still needs the usual manual check.

### Reading the residual report

The in-DB rename step ends with a residual count of remaining old-hostname
references in the `variable` and task-history tables. What lands there stays
behind by design and is not a failure:

- task-history rows — Ægir task logs keep old-hostname arguments forever;
- values the safe passes deliberately leave untouched: serialized variables
  embedding PHP objects, and values that already fail to unserialize — the
  rename prints each such variable by name during the run for manual review.

In a subdomain-augmenting rename (the new FQDN contains the old one), the
anti-doubling guard skips any value that already carries the new hostname —
and the residual count excludes those same values, so a mixed value holding
both forms is neither rewritten nor counted. In that regime a zero residual
does not prove zero old-hostname references; mixed values must be found by
hand if they matter (single-hostname columns never legitimately hold both
forms, so this is an edge case).

### Octopus control file

On Octopus roots the tool also rewrites `_DOMAIN` (and any other old-FQDN
values) in `/root/.<oN>.octopus.cnf`, which feeds the install and config
legs. The satellite UPGRADE, however, re-reads its `_DOMAIN` from the
per-instance identity stamp in the account's log directory — not from the
cnf — so the tool rewrites those stamps too (`log/domain.txt` and
`log/setupmail.txt`, ownership and mode preserved): a stamp naming a host
that no longer exists is exactly what the upgrade's own `_DOMAIN` cross-check
trips over. The master root has no octopus cnf, so the cnf step no-ops there.

## Former xboa tool (renamed to xoct)

The former `xboa` per-account migration tool was renamed to `xoct`
(Octopus-scoped) and `xboa` has been removed — BOA no longer ships or fetches an
`xboa` binary. `xoct` is functionally equivalent plus two improvements: the
Ægir DB hostname replacement and post-import task queue are now delegated to
`renameaegirhost` (more thorough, 5-pass queue), and the hardcoded
internal-account email exclusion has been removed so `xoct` works correctly when
invoked by `xmass`.

If you still have scripts referencing `xboa`, update them to call `xoct`
directly. The tool is installed at `/opt/local/bin/xoct`; if you need a
compatibility alias, point it there (note the `/opt/local/bin` path — not
`/usr/local/bin`):

```sh
ln -sfn /opt/local/bin/xoct /opt/local/bin/xboa
```

## Detailed Procedures

- [Single-account migration with xoct](MIGRATE-XOCT.md)
- [Full-server migration with xmass](MIGRATE-XMASS.md)
- [Migrating to Percona 8 — cross-version behaviour and verification](MIGRATE-PERCONA8.md)
