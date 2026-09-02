# Making a Codebase Group-Writable for Shared Work (`fixrepo`)

Every Octopus account is really a pair of identities in the same Unix group:
the backend user (`o1`) that PHP-FPM and Drush run as, and the limited shell
user (`o1.ftp`) that people log in as over SFTP/SSH. As long as files carry
the shared group with group-write and directories carry setgid, both sides
can work on the same tree without permission clashes — and BOA provisions
its own trees that way (`~/static` itself ships as `oN:users` mode `2775`).

That model breaks whenever a codebase is created outside BOA's machinery:
a `git clone` or `git pull` run as root (umask `022`), a tarball or
`rsync -a` import, or a build tool writing with a strict umask. The result
is a tree the other identity cannot write to, and — for git checkouts —
a repository whose new objects will keep losing the group bits.

`fixrepo` repairs that in one pass. It is a root-only operator command
(installed hardened in `/opt/local/bin`, never exposed via sudo or lshell)
that performs three actions on a codebase root:

1. `chmod -R g+rwX` over the whole tree — group read/write everywhere,
   execute only on directories and files that are already executable, so
   regular files never become executable.
2. `find <root> -type d -exec chmod g+rws` — setgid on every directory,
   so files created later inherit the shared group.
3. When a `.git` directory is present: an explicit permissions pass over
   the git internals, plus `git config core.sharedRepository group` so git
   itself keeps future objects and refs group-accessible. The config step
   runs as the repository owner, never as root — root-run git would trip
   git's dubious-ownership refusal on `oN`-owned repos and leave a
   root-owned `.git/config` behind.

## Usage

```sh
fixrepo /path/to/codebase

# The canonical target is a codebase under an account's static tree:
fixrepo /data/disk/o1/static/live/drupal_v11_2026
```

Environment knobs (optional):

| Variable | Effect |
|---|---|
| `_DEBUG_MODE=YES` | Verbose per-step progress messages |
| `_STRICT_MODE=NO` | Continue past non-fatal chmod/find errors (default `YES` aborts on the first failure) |

The tool is idempotent — re-running it on an already-fixed tree changes
nothing and is always safe.

## Scope guard

Because a recursive chmod run as root can do box-wide damage from a single
typo, `fixrepo` refuses to act outside the trees that hold codebases. The
argument is first resolved to its absolute physical path (symlink aliases
are validated against their real target), then checked against an
allowlist: it must sit at least one level inside `/data/disk/<user>/`,
`/var/aegir/`, `/var/www/` or `/home/<user>/`. Anything else — `/`, `/etc`,
`/data/disk`, a bare account home — is refused before any change is made.

## What survives contact with the rest of BOA

**Codebases without a registered Ægir site are left alone.** Nothing in BOA
visits them on a schedule, so the grant is durable until you change it.

**Codebases that carry a registered site get nightly maintenance.** The
nightly worker re-asserts BOA's standard model on registered platforms
under `~/static`: directories back to plain `0775` (this clears the setgid
bit) and files to `0664` (group-write itself survives). The same pass also
manages the ownership direction — chowning the tree to `oN`, or to `oN.ftp`
while the tenant's `unlock.info` switch exists — as described in
[UNLOCK.md](UNLOCK.md). In practice
the setgid loss is harmless for the standard pair, because both identities
already share `users` as their primary group.

**Octopus install and upgrade runs** reset a handful of top-level
`module*` directories under `~/static` globs to `0775`, and **platform
Verify** re-tightens a few specific paths on registered platforms (the
root-level `*.php` files to `0644`, and `sites` to `0751` on built-in
platforms; on a tenant Composer codebase under `~/static` it asserts the
group-writable `02771` instead, with `sites/default` at `02775`, so
Drupal's scaffold plugin can write there). Re-run `fixrepo` after those
events if one of the affected paths matters to your workflow.

## Security considerations

The grant is deliberately no wider than BOA's own standard: group `users`
is shared box-wide, and what keeps tenants apart is the `0711` account
homes plus the lshell command allowlist, chrooted SFTP and per-account
PHP-FPM `open_basedir` — not group bits. `fixrepo` extends the same model
to the git metadata, which means `o1.ftp` can then edit `.git` internals
(hooks, config) of that repository; that is exactly the shared-write
workflow the tool exists for, but treat the pair as one trust domain on
that tree.

Note the contrast with `fix-drupal-platform-permissions.sh`: that sibling
*tightens* a registered platform back to BOA's locked-down defaults, while
`fixrepo` deliberately *opens* shared group-write. Use the right one for
the job at hand.

## Notes

- **Ownership is out of scope.** `fixrepo` changes modes only, never
  owner or group — the mode/ownership split is deliberate across BOA's
  permission tooling. If a tree ended up root-owned (a root `git clone`),
  first `chown -R oN:users` it, then run `fixrepo`.
- **Git worktrees and submodules.** When `.git` is a gitfile rather than
  a directory, the tree-wide permissions pass still runs, the git-specific
  steps are skipped, and the summary says so explicitly.
- **umask.** The closing `umask 002` advice is belt-and-braces: BOA
  already pins umask `002` box-wide (login.defs, PAM, profile and SFTP),
  so files created by either identity normally stay group-writable on
  their own.
