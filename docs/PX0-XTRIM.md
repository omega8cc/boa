# xtrim — Shrinking a Fully Proxied (PX0) Source Box

After an `xmass`/`xoct` migration converts a source box into a permanent
web proxy, the box still carries every byte it served: databases, platform
trees, files stores, backups. `xtrim` removes exactly that payload — and
nothing the proxy role needs — so the box fits a minimal plan. It ships to
`/opt/local/bin/xtrim` (root-only, no `/usr/local/bin` symlink, like the
rest of the `x*` migration family).

Design stance: every deletion is derived from the box's own saved vhosts
and drush aliases, proven still-served by the TARGET over ssh, dumped and
verified locally, and recorded in a manifest before the first removal.
There is no guessing and no name matching.

## Verbs

```sh
xtrim status                     # read-only: proxy state, cert horizon,
                                 # reclaimable bytes per account
xtrim plan    <oN|all>           # precondition battery + itemised plan (DRY)
xtrim quiesce <oN|all> [--live]  # stage A ONLY -- reversible, deletes nothing
xtrim restore <oN>               # undo a quiesce from quarantine
xtrim shrink  <oN|all> [--live]  # stage A (skipped if already quiesced)
                                 # + stage B (ONE-WAY)
xtrim finalize [--live] [--drop-datadir]
                                 # box-wide stage C when EVERY account is shrunk
```

The DRY/`--live` token is per verb AND per account: a clean DRY of `plan`
never arms `shrink --live`, and a clean DRY of `quiesce` never arms
`shrink` either; each `--live` consumes its token before work. `all`
operates on PROXIED accounts only and skips the rest with a notice.

### The recommended sequence

```sh
xtrim plan    o1                 # read the itemised plan and the manifest
xtrim quiesce o1                 # DRY
xtrim quiesce o1 --live          # account parked; NOTHING deleted yet
#   ... verify the proxy still serves every site, at your leisure ...
xtrim restore o1                 # changed your mind: fully undone
#   ... or, when satisfied:
xtrim shrink  o1                 # DRY
xtrim shrink  o1 --live          # stage A skipped, stage B runs: ONE-WAY
```

`quiesce` exists because stage A is the only reversible part of the
operation and it deserves to be a step an operator can stop at. It is
idempotent (a second call reports the state and returns), it refuses
once stage B has run, and it leaves the account exactly where `restore`
expects it. Running `shrink --live` straight from an unquiesced account
still works and does both stages, as before.

## Hard refusals (the plan battery)

Root; single instance; `/` under 90%; no `sqlclean` (mutual lock) and no
barracuda/octopus/xoct/xmass/provision/install in flight; the eligibility
triple present; `log/CANCELLED` means `boa cleanup`, never xtrim;
`log/proxied.pid` present and older than `_XTRIM_MIN_DAYS` (default 14,
hard floor 7); every live vhost a proxy vhost agreeing on ONE target IP;
`migproxy.cnf` record agreeing with the vhosts (disagreement names
`xoct proxy --repair --retarget`); no expired certificate behind a
retained HTTPS vhost; every `server_name` serving through the target AND
through the proxy relay (redirects accepted — SSL-Required sites answer
301 on port 80); ssh to the target working; and, for every database about
to be dropped, the TARGET holding a populated schema of that name plus at
least one real (non-proxy) vhost — which is what stops a proxy chain being
mistaken for a target. The SQL endpoint must be this box's own server.

## What the stages do

**Stage A — reversible** (`quiesce`, or the first half of `shrink`).
Parks the account dispatcher OUT of
`/var/xdrago` (never into `off-run/`, which BOA restores from), drains,
quarantines the nginx fpm includes then the FPM pools (never the system
`www<NN>` pool that backs `/sqladmin`), UNLOADs Solr cores with all delete
flags false and moves them to a quarantine SIBLING of their resolved data
dir (an `/mnt`-store index never lands on the root filesystem; origin and
port are recorded in a map), reloads nginx under the shared config lock,
and re-probes every domain. Any regression auto-restores and aborts.

**Stage B — one-way on this box.** Marks its phase at ENTRY (a crash
mid-run leaves `restore` refusing), dumps and gzip-verifies every
database, re-proves the target, then drops databases and their
single-grant users (all three grant hosts), removes `backups/`, `src/`,
`undo/`, `distro/`, the platform trees named by the `platform_*` aliases,
and the static trees — resolving every store symlink FIRST and refusing
any target outside the account or the single `/mnt` store. The proxy
keeps serving throughout: nothing in stage B is in its dependency set.

**Stage C — `finalize`.** Only when every account is shrunk: removes the
shared codebases (`/data/all` and `/data/disk/all`), stops and disables
MySQL (`--drop-datadir` is a separate explicit flag), stops solr/jetty
and disarms their monitor watchdog by dropping the init scripts' exec
bit (the `/var/xdrago/monitor` tree is deliberately not proxy-gated),
stands down every FPM master except the panel front's, and LAST touches
`/root/.proxy.cnf`, which stands the BOA machinery down while the nginx
watchdog keeps running.

## Never touched

`/etc/nginx`, `/var/aegir/config`, the `/data/conf` control files, root
dotfiles, `/etc/ssl/private`, `/etc/csf`, `/var/xdrago`, `/opt/local/bin`,
the account's entire `config/` tree including `ssl.d`, and `tools/le/` in
its entirety — delete `tools/le` and every HTTPS proxy vhost has a
dangling `ssl_certificate` and nginx will not start. Certificate refresh
stays with the daily `migration_proxy_certs.sh` mirror, which must keep
running long after the shrink.

## Rollback truth

Stage A restores automatically on abort, and `xtrim restore <oN>` undoes
it from quarantine — deliberately reachable now that `quiesce` stops
there rather than running straight on into stage B.

**Stage B is not reversible on this box**: "I need
this account back here" is a migration back from the live target using
the manifest's map and the archived aliases; "the target died" is a
restore from the remote backup history. The safety dumps under
`/var/backups/xtrim/<oN>/dbdumps/` cover only the drop step itself.

Retiring the proxy entirely is out of scope — that is the `boa cleanup`
sequence, and mixing the two machineries is how customer data is lost.
