# The Codebase Lock — Nightly Ownership Management (`unlock.info`)

BOA treats code ownership on tenant platforms as managed state. Once per
night, the maintenance worker walks every **registered** site, resolves its
platform root, and re-asserts both ownership and permissions. The historical
motivation (post-Drupalgeddon) was to make sure a compromised site cannot
rewrite code at all, and a leaked SFTP credential cannot strip the hardening
or subvert git's repository-ownership trust (the code trees stay
group-writable for the shell pair, so the lock is not a write barrier);
the mechanism survives today as the default *lock*, with a tenant-controlled
*unlock* for in-place maintenance ([UNLOCK-USER.md](UNLOCK-USER.md) is the
tenant-facing walkthrough).

## What the nightly pass does

For each registered site's platform (per account, once per night per
platform, tracked by marker files under `~/log/ctrl/`):

- **Platforms under `~/static`** (all tenant platforms live there): the
  whole codebase is chowned to the account's backend user (`oN`). For
  composer-managed shapes (a docroot with `core/lib/Drupal.php` next to
  `../vendor/autoload.php` and a `composer.json` requiring `drupal/core` or
  `drupal/core-recommended`, the shape of drupal/recommended-project and
  Drupal CMS)
  the pass operates on the **repository root**, so `vendor/` and
  `composer.json` are covered too. Then the permission sweep: directories
  `0775`, files `0664`, and the hardened read-only paths (`vendor/drush`,
  selected `vendor/symfony/console` internals) locked to `0400`.
- **Platform level** (every registered platform, in addition to the pass
  above): `sites/all/{modules,themes,libraries}/*` chowned to `oN` and the
  account's group;
  the `sites/` skeleton re-asserted (`sites` `0751`, `sites/*` `0755`,
  `sites/*.php` `0644`; on a tenant Composer codebase under `~/static` the
  two directories Drupal's scaffold plugin writes into take group write
  instead, `sites` `02771` and `sites/default` `02775`, so a tenant
  composer run can refresh its scaffold files there; others keep
  execute-only on `sites`, every `sites/<uri>` stays `0755`, and a
  symlinked `sites` or `sites/all` makes the pass skip the platform);
  stray code archives (`*.tar`, `*.tar.gz`, `*.zip`) inside `sites/all`
  trees are deleted.
- **Built-in platforms** (`~/distro/NNN/<platform>`): the tenant-writable
  `sites/all/{modules,themes,libraries}` keep `02775`/`0664`; core,
  profiles, includes, vendor and the platform root take `0755`/`0644`, no
  group write (the three Drush-lock dirs keep their lock-state mode).
- **Hostmaster trees** (`aegir/distro/NNN` on an Octopus account,
  `/var/aegir/distro/NNN` on the master): no shell user has any business
  there, so the platform script and the nightly keep them at `0755`/`0644`
  with no group write (root dir included), unlike every other platform.
- **Site level**: each site's `{modules,themes,libraries}/*` chowned to
  `oN` and the account's group with directories `02775` and files `0664`; settings-class
  files (`settings.php`, `local.settings.php`, `civicrm.settings.php`)
  kept at `oN:www-data`, mode `0440`/`0640`; the site's `files/` tree
  chowned to `oN:www-data` (symlink-safe, `chown -h`).

Group-write for the shell pair survives all of this — the lock manages the
**ownership axis**, and with it the owner-only rights: chmod, git's
repository-ownership trust, and replacing read-only paths. The web identity
(the per-account `.web` FPM user, a member of `www-data` only) can write
code in neither state.

## The two tenant switches

- **`~/static/control/unlock.info`** — account-wide direction flip. While
  it exists, the code-tree chowns above target `oN.ftp` instead of `oN` —
  the whole tree for `~/static` platforms, and the
  `{modules,themes,libraries}` contents at platform and site level; the
  container directories, settings files and `files/` areas stay with the
  backend user. That hands the owner-only rights to the shell account so
  in-place `composer update` and git work function. Takes effect on the
  next nightly run; removing the file re-locks the next night.
- **`<platform root>/skip.info`** — per-platform opt-out from the
  recursive code-tree chowns in **both** directions: a skipped platform
  keeps whatever ownership you set on the code trees. The container
  directories, settings files and `files/`/`private/` areas are still
  re-chowned to their managed owners, and the permission sweep still
  runs. The whole-tree pass on composer shapes checks the repository root
  for `skip.info`; the `sites/all` and site-level passes check the
  docroot — advise tenants to place it in both for composer-managed
  codebases.

Platforms that carry **no registered site** are never visited by the
nightly pass at all; a platform Verify still applies the ownership and
permission map, so only an unregistered, never-verified tree is entirely
manual (see [FIXREPO.md](FIXREPO.md) for the group-write repair tool for such
trees).

## Operator knobs

- **`_PERMISSIONS_FIX=YES`** in `/root/.barracuda.cnf` (default `YES`)
  gates the entire nightly permission/ownership machinery.
- **`/etc/boa/.dont.touch.permissions.cnf`** — box-wide kill file; its
  presence skips the machinery for every platform, overriding everything
  below.
- **`fix_files_permissions_daily = FALSE`** in a platform's active INI file
  opts that platform out. The nightly worker seeds the variable into each
  platform INI as a commented-out `TRUE` default. One exception overrides
  the INI opt-out: a Drupal 7 platform missing the SA-CORE-2014-005 core
  patch is always fixed (and patched) regardless.

## Interplay with Ægir tasks

Platform **Verify** (and the install flows that run it) invokes the
sudo-exposed `fix-drupal-platform-ownership.sh` wrapper with the backend
user as the target (`--script-user`) — that is, **a platform Verify
re-locks ownership immediately, in any lock state**. While `unlock.info`
remains in place the next nightly run restores the unlock; but a tenant
mid-upgrade who runs a platform Verify will find the code handed back to
the backend user on the spot. This is by design: Verify's job is to
converge the platform to the managed state.

The nightly ownership flip and `fixrepo` solve different axes: the lock
manages *who owns* registered platforms on a schedule; `fixrepo` repairs
*group-write and setgid* on a tree (typically an unregistered one) once, by
hand. They compose without conflict — a `fixrepo`-treated registered
platform still gets its ownership managed nightly.
