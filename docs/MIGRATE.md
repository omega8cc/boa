# BOA Migration Tools

BOA provides two purpose-built tools for migrating Octopus instances and full
server environments between remote hosts.

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

## Third Tool: renameaegirhost

`renameaegirhost` handles in-place Ægir hostname rename on a single Ægir root
— the BOA master (`--aegir-root /var/aegir`) or an Octopus account
(`--aegir-root /data/disk/oN`). It is called automatically by xoct (during
`import`) and by xmass (during `cutover`), which pin the old hostname for it —
migrations never need a direct invocation. Run it directly only for an
in-place identity change (renaming a cloned VM, moving a box to a new FQDN) or
to resume a partial rename; inline `--help` describes each step.

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
so a repeat run over a completed rename changes nothing — including when the
new FQDN contains the old one (a subdomain-augmenting rename). After a partial
or aborted rename the on-disk aliases may already carry the new hostname,
which defeats old-hostname auto-detection (old == new, silent no-op) — resume
with the old hostname pinned explicitly:

```sh
renameaegirhost --aegir-root /data/disk/o1 --force-old old.example.com
```

`--dry-run` prints every planned change without modifying anything.

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
values) in `/root/.<oN>.octopus.cnf`, which drives future octopus runs. The
master root has no octopus cnf, so that step no-ops there.

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
