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

## Deprecation of xboa

`xboa` has been renamed to `xoct`. The tool is functionally equivalent plus two
improvements: the Aegir DB hostname replacement and post-import task queue are
now delegated to `renameaegirhost` (more thorough, 5-pass queue), and the
hardcoded internal-account email exclusion has been removed so `xoct` works
correctly when invoked by `xmass`.

**Recommended transition:** install a compatibility symlink so existing scripts
and operator muscle-memory continue to work:

```sh
ln -sfn /usr/local/bin/xoct /usr/local/bin/xboa
```

The xboa source file itself should be removed from the repository to avoid
ambiguity. The symlink keeps binary compatibility at zero maintenance cost.

## Detailed Procedures

- [Single-account migration with xoct](MIGRATE-XOCT.md)
- [Full-server migration with xmass](MIGRATE-XMASS.md)
