# The Mirror Publisher (getboa)

`aegir/tools/bin/getboa` runs on the mirror master only. It fetches the BOA git
branches and publishes them as `boa.tar.gz` per tree on the static files mirror.
A BOA pass never installs or runs it on a hosted box.

    getboa dev    # 5.x-dev  ->  /var/www/static/dev/dev/boa.tar.gz
    getboa lts    # 5.x-lts  ->  /var/www/static/dev/lts/boa.tar.gz
    getboa pro    # 5.x-pro  ->  /var/www/static/dev/pro/boa.tar.gz
    getboa all    # all three trees

Each tarball extracts to a top-level `boa/` directory carrying a `.update.txt`
stamp (date, branch, short commit), the layout the `_get_dev_ext()` consumers in
barracuda and octopus expect.

Beside each tarball goes `boa.stamp`, a copy of that `.update.txt`. The Barracuda
and Octopus upgrades compare it with the build tree they staged and fetch the tree
again when it differs (`_boa_tree_stamp_check` in `lib/settings/*.sh.cnf`); the
purge below covers it with the tarball.

## Installing It

Copy `aegir/tools/bin/getboa` to `/opt/local/bin/getboa` on the mirror master,
owned by root, mode 0755. It runs as root. Publishing is atomic (a temporary
directory on the same filesystem, then `mv`), guarded by a lockfile, and safe to
re-run or schedule from cron.

## The Cloudflare Purge

After publishing, the Cloudflare cache is purged for the rewritten URLs on every
mirror hostname. A CF edge can otherwise keep serving a pre-publish tarball for
days (observed 2026-08-18). The purge reads `/root/.cf-purge.cnf` (root-only,
mode 600):

    _CF_API_TOKEN="..."     # CF API token: Zone:Read + Zone:Cache Purge
                            # on the mirror zones
    _CF_MIRROR_HOSTS="..."  # optional space-separated hostname override

Without the config file the purge is skipped loudly and the run still succeeds.
A present-but-broken config or a failed purge exits non-zero so cron surfaces
it; the publish itself is never rolled back.

## Purging Files Other Tools Publish

    getboa purge <file> [<file> ...]

purges the same five hostnames for files ANOTHER tool published into the
webroot, named by absolute path under `/var/www/static` or relative to it. It
exists for the prebuilt `boa-*` packages: `stackbuild` republishes a rebuilt
component under its unchanged filename, nothing purged it, and an edge then
served the previous `.gz` for up to its 30-day TTL beside the new, uncached
sidecar, so every consumer behind that edge failed the checksum and compiled
from sources (found 2026-09-21 on one mirror name after a same-version
republish).

Same gate as the tarballs, per host: a cache-busted HEAD through Cloudflare must
show the local file's size and, where the origin's `Last-Modified` parses, a
copy not older than the local file (a sidecar never changes size, so size alone
says nothing for it); 15-minute bound, 30 URLs per API call. Unlike the publish
path a missing config is an error here: the caller asked for a purge and none
happened. The verb holds its own lock and never waits on, or cleans up after, a
publish running beside it.

On a builder, wire it in through stackbuild's hook, in `/root/.stackbuild.cnf`:

    _PURGE_HOOK="/usr/local/bin/getboa purge"

(use the path getboa is installed at; on the mirror master that is
`/opt/local/bin/getboa`). stackbuild calls it after its cross-sync with every
file published in the run; a failing hook gets a loud `WARN purge hook failed`
in the summary, the replaced filenames are printed, and the publish stands
(see [PREBUILT.md](PREBUILT.md)).

The second builder does NOT get getboa or the token. Its hook runs the master's
getboa over the peer root connection the cross-sync already uses:

    _PURGE_HOOK="ssh -n -o BatchMode=yes -o ConnectTimeout=15 root@<mirror master> /opt/local/bin/getboa purge"

This works because the hook runs AFTER the cross-sync, so the master already
holds the files stackbuild names (same absolute paths on both boxes), and the
origin gate then waits for the passive mirrors as usual. `-n` matters: without
it the remote call eats whatever stdin the caller has. One token, one getboa to
keep current. Two purges cannot run at once: the second is refused by the purge
lock and its builder prints the filenames.
