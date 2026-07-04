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

`renameaegirhost` handles in-place Aegir hostname rename on a single Octopus
root. It is called automatically by xoct (during `import`) and by xmass (during
`cutover`) — you rarely need to invoke it directly. See inline `--help` for
details.

## Former xboa tool (renamed to xoct)

The former `xboa` per-account migration tool was renamed to `xoct`
(Octopus-scoped) and `xboa` has been removed — BOA no longer ships or fetches an
`xboa` binary. `xoct` is functionally equivalent plus two improvements: the
Aegir DB hostname replacement and post-import task queue are now delegated to
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
