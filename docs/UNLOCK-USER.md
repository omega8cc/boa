# In-Place Upgrades — Unlocking Your Codebase (`unlock.info`)

Every night BOA re-asserts a **codebase lock** on the platforms your sites
run on: the code trees are chowned back to your account's backend user
(`o1`), and a standard permission map is applied. Day-to-day work is not
affected — files stay group-writable (`0664`, dirs `0775`) and your shell
user (`o1.ftp`) shares the group — but the backend user keeps the
*owner-only* rights: changing permissions, replacing the deliberately
hardened read-only paths, and being the identity git trusts as the
repository owner.

That is exactly what stands between you and an in-place `composer update`
or a git-driven core upgrade. Composer needs to chmod and replace things
like `vendor/drush` (which BOA locks to `0400` nightly); git refuses to
work in a repository owned by a different user. The supported answer is a
single control file — the key to the lock:

```sh
touch ~/static/control/unlock.info
```

While that file exists, the nightly maintenance flips the direction: your
registered platform codebases are chowned to your **shell user** instead,
so composer, git and chmod all work in an ordinary shell session. Remove
the file and the next nightly run hands ownership back to the backend user
and restores the default protection.

**Never use this method unless you are prepared for extended downtime.**
An in-place upgrade has no safety net beyond the one you build yourself,
and the recovery path is slow by design: one mistake — most commonly
running a platform *Verify* before the PHP and Nginx caches have expired
and shown that the sites really still work — hands code ownership
straight back to the backend user while the new code is broken. From that
moment you cannot touch the code: the sites stay down until the next
nightly run returns ownership to you, or until support can step in. If a
day of downtime is unacceptable, take the safe path instead: build the
upgraded codebase as a new platform and migrate your sites onto it.

## The upgrade workflow

1. **Back up the codebase yourself.** The Ægir *Backup* task never
   includes the platform codebase — it archives the site directory plus,
   depending on the backup mode, a database dump, and nothing else.
   Codebase backup is a fully manual job: copy the platform tree aside
   as your shell user, or make sure git and the committed `composer.lock`
   can rebuild the exact pre-upgrade code. Run the site *Backup* task as
   well for a site-directory and database restore point — just know it
   cannot bring your code back.
2. `touch ~/static/control/unlock.info` as your shell user.
3. **Wait for the nightly run** (early morning, server time) to flip
   ownership, or ask support to expedite it. You can confirm with
   `ls -l` — code should be owned by your `.ftp` user.
4. Do the work in your shell: `composer update`, `git pull`, patches. On
   composer-managed codebases run composer in the **repository root** (the
   directory holding `composer.json`), not the web docroot. If a hardened
   path such as `vendor/drush` is in the way, you now own it — chmod it
   and carry on; the nightly sweep re-hardens it later.
5. **Prove the sites still work — only then run Verify.** Do not trust
   the first page loads after the code swap: the PHP opcache and the
   Nginx cache can go on serving the pre-upgrade code and cached pages
   for a while, so a site can look fine while the new code is already
   broken. Wait for those caches to expire, then test properly — log
   in, hit uncached pages, watch the logs. Once you are confident, run
   *Verify* on the platform (and the site) from the Ægir control panel.
   Verify registers the changed code — and a platform Verify also
   chowns the code back to the backend user immediately. Run it while
   the code is broken and you have locked yourself out of the fix (see
   the warning above).
6. `rm ~/static/control/unlock.info` so the next nightly run restores the
   default lock. Do not leave the unlock in place permanently — it exists
   for maintenance windows, not as a lifestyle.

## What the unlock does not change

- **Your sites' PHP never gets write access to code.** Site PHP runs as a
  separate web-only user that is not in your files' group, in either lock
  state. The unlock hands owner rights to your shell user — it does not
  expose code to the web application.
- **BOA-managed files stay managed.** `settings.php` and friends remain
  owned by the backend user and read-only, and the `sites/` directory
  skeleton and a few managed container directories stay owned by the
  backend user even while unlocked — that does not affect composer or
  git.
- **The nightly permission sweep still runs.** Directories `0775`, files
  `0664`, hardened paths re-locked to `0400` — only the *ownership*
  direction follows `unlock.info`.
- **Verify tasks always re-lock.** A platform Verify chowns code back to
  the backend user immediately, whatever the lock state; the nightly run
  restores your unlock the following night while `unlock.info` remains in
  place.

## Excluding a single platform

An account-wide unlock is usually the right tool, but you can also take
one platform out of the nightly ownership management entirely: place an
empty `skip.info` file in the platform's docroot — and, for
composer-managed codebases, one in the repository root next to
`composer.json` as well. A skipped platform keeps whatever ownership you
set on the code trees, in both directions; BOA still manages the `sites/`
skeleton, settings files and `files/` areas, and the permission sweep
itself still applies.

## The fine print

The lock is a security default, not an obstacle: keeping owner rights on
the backend user means a leaked SFTP credential cannot quietly chmod away
the hardening or tamper with git internals on your platforms (the operator
mechanics live in [UNLOCK.md](UNLOCK.md)). Treat the unlock as you would
`sudo` — switch it on for the job, switch it off after. And if an upgrade
goes wrong, the way back is the codebase copy you made yourself in step
one (or a git/composer rebuild) — the Ægir *Backup* archive can restore
the site directory and database, never the code.
